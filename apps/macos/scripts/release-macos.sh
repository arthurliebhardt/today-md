#!/usr/bin/env bash
# Build release artifacts only. Publication is a separate, final operation.
set -euo pipefail
set +vx
umask 077
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
cd "$repo_dir"
python3 "$script_dir/release-metadata.py" check-inputs
[[ "$(uname -s)" == Darwin ]] || { echo 'A macOS runner is required' >&2; exit 1; }
[[ "${GITHUB_REPOSITORY:-arthurliebhardt/today-md}" == arthurliebhardt/today-md ]] || {
  echo 'The stable feed is configured for arthurliebhardt/today-md' >&2; exit 1;
}
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}")" ]] || {
  echo 'Check out the exact release tag before packaging' >&2; exit 1;
}
for command in xcrun xcodebuild security codesign ditto gh python3 curl; do
  command -v "$command" >/dev/null || { echo "Missing tool: $command" >&2; exit 1; }
done
output_dir="$repo_dir/dist/macos"
[[ ! -e "$output_dir" ]] || { echo 'dist/macos already exists; move it aside before a new release build' >&2; exit 1; }
work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/today-md-release.XXXXXX")
keychain="$work_dir/signing.keychain-db"
cleanup() {
  local status=$?
  if [[ -f "$work_dir/original-keychains.json" ]]; then
    python3 - "$work_dir/original-keychains.json" <<'PY' || true
import json, subprocess, sys
subprocess.run(["security", "list-keychains", "-d", "user", "-s", *json.load(open(sys.argv[1]))], check=True)
PY
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
security list-keychains -d user | python3 -c 'import json,shlex,sys; json.dump(shlex.split(sys.stdin.read()),sys.stdout)' > "$work_dir/original-keychains.json"
python3 - "$work_dir" <<'PY'
import base64, os, pathlib, sys
directory = pathlib.Path(sys.argv[1])
(directory / "certificate.p12").write_bytes(base64.b64decode(os.environ["MACOS_SIGNING_P12"].strip(), validate=True))
(directory / "AuthKey.p8").write_text(os.environ["ASC_PRIVATE_KEY_P8"])
PY
keychain_password=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work_dir/certificate.p12" -k "$keychain" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
python3 - "$work_dir/original-keychains.json" "$keychain" <<'PY'
import json, subprocess, sys
subprocess.run(["security", "list-keychains", "-d", "user", "-s", sys.argv[2], *json.load(open(sys.argv[1]))], check=True)
PY
sparkle_private_key=${SPARKLE_PRIVATE_KEY:?}
unset MACOS_SIGNING_P12 MACOS_SIGNING_P12_PASSWORD ASC_PRIVATE_KEY_P8 SPARKLE_PRIVATE_KEY
signing_identity=$(security find-identity -v -p codesigning "$keychain" | python3 -c '
import os,re,sys
identities = re.findall(r"([A-F0-9]{40}) \"Developer ID Application: [^\"]+ \(" + re.escape(os.environ["MACOS_TEAM_ID"]) + r"\)\"", sys.stdin.read())
if len(identities) != 1:
    sys.exit("Import exactly one valid Developer ID Application certificate and private key for MACOS_TEAM_ID")
print(identities[0])')
# A canary fails before the archive if the imported private key is inaccessible.
cp /usr/bin/true "$work_dir/signing-canary"
codesign --force --sign "$signing_identity" --keychain "$keychain" --timestamp --options runtime "$work_dir/signing-canary"
mkdir -p "$output_dir"
archive_path="$work_dir/today-md.xcarchive"
xcodebuild -project apps/macos/today-md.xcodeproj -scheme today-md-github \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" -derivedDataPath "$work_dir/DerivedData" \
  -clonedSourcePackagesDirPath "$work_dir/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  DEVELOPMENT_TEAM="$MACOS_TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$signing_identity" "OTHER_CODE_SIGN_FLAGS=--keychain $keychain" \
  PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=YES \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" archive
python3 - "$work_dir/ExportOptions.plist" "$MACOS_TEAM_ID" "$signing_identity" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as stream:
    plistlib.dump({"method": "developer-id", "teamID": sys.argv[2], "signingStyle": "manual",
                  "signingCertificate": sys.argv[3], "stripSwiftSymbols": True}, stream)
PY
xcodebuild -exportArchive -archivePath "$archive_path" \
  -exportOptionsPlist "$work_dir/ExportOptions.plist" -exportPath "$output_dir/export"
app="$output_dir/export/today-md.app"
framework="$app/Contents/Frameworks/Sparkle.framework"
[[ -d "$framework" ]] || { echo 'GitHub build is missing Sparkle.framework' >&2; exit 1; }
# Sign from the innermost helpers out. Preserve their sandbox entitlements.
while IFS= read -r -d '' helper; do
  codesign --force --sign "$signing_identity" --keychain "$keychain" --timestamp \
    --options runtime --preserve-metadata=identifier,entitlements "$helper"
done < <(find "$framework/Versions/B" -depth \( -name '*.xpc' -o -name '*.app' -o -name Autoupdate \) -print0)
for bundle in "$framework" "$app"; do
  codesign --force --sign "$signing_identity" --keychain "$keychain" --timestamp \
    --options runtime --preserve-metadata=identifier,entitlements "$bundle"
done
build=$(python3 "$script_dir/release-metadata.py" check-app "$app" "$RELEASE_TAG")
[[ "$build" == "$(python3 "$script_dir/release-metadata.py" project-version --build)" ]]
codesign --verify --deep --strict --verbose=2 "$app"
while IFS= read -r -d '' bundle; do
  codesign -dv --verbose=4 "$bundle" 2>&1 | python3 -c '
import os,sys
details=sys.stdin.read()
if "TeamIdentifier=" + os.environ["MACOS_TEAM_ID"] not in details or "runtime" not in details:
    sys.exit("All executable bundles must use the configured Developer ID team and hardened runtime")'
done < <(find "$app" -depth \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' -o -name Autoupdate \) -print0)
codesign -d --entitlements :- "$app" 2>/dev/null | python3 -c '
import plistlib,sys
entitlements=plistlib.loads(sys.stdin.buffer.read())
if entitlements.get("com.apple.security.get-task-allow",False):
    sys.exit("A release cannot carry the debugger entitlement")'
/usr/bin/lipo "$app/Contents/MacOS/today-md" -verify_arch arm64 x86_64
ditto -c -k --sequesterRsrc --keepParent "$app" "$work_dir/notarization.zip"
diagnostics_dir="$output_dir/diagnostics"
mkdir -p "$diagnostics_dir"
notary_command_status=0
xcrun notarytool submit "$work_dir/notarization.zip" --key "$work_dir/AuthKey.p8" \
  --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --timeout 20m \
  --output-format json > "$diagnostics_dir/notarization.json" || notary_command_status=$?
notary_accepted=0
python3 - "$diagnostics_dir/notarization.json" <<'PY' && notary_accepted=1
import json,sys
try:
    result=json.load(open(sys.argv[1]))
except (ValueError, OSError):
    sys.exit("Apple notarization did not return submission JSON; inspect the command error above")
if result.get("status") != "Accepted":
    sys.exit("Apple notarization was not Accepted; inspect submission " + str(result.get("id")))
print("Apple notarization accepted: " + result["id"])
PY
if [[ "$notary_command_status" != 0 || "$notary_accepted" != 1 ]]; then
  submission_id=$(python3 - "$diagnostics_dir/notarization.json" <<'PY'
import json,sys
try:
    print(json.load(open(sys.argv[1])).get("id", ""))
except (ValueError, OSError):
    pass
PY
  )
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" "$diagnostics_dir/notarization-log.json" \
      --key "$work_dir/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
  fi
  echo "Notarization diagnostics retained in $diagnostics_dir" >&2
  exit 1
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
update_dir="$work_dir/update"
mkdir "$update_dir"
zip_name="today-md-$RELEASE_TAG-macos.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$update_dir/$zip_name"
ditto -c -k --sequesterRsrc --keepParent "$archive_path/dSYMs" "$output_dir/today-md-$RELEASE_TAG-macos.dSYM.zip"
# Use exactly the same pinned Sparkle release as the application's dependency.
curl --fail --silent --show-error --location --retry 3 \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz \
  -o "$work_dir/Sparkle.tar.xz"
printf '%s  %s\n' c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c "$work_dir/Sparkle.tar.xz" | shasum -a 256 -c -
mkdir "$work_dir/Sparkle"
tar -xJf "$work_dir/Sparkle.tar.xz" -C "$work_dir/Sparkle"
sign_update="$work_dir/Sparkle/bin/sign_update"
# Preserve older entries, including updates for older macOS requirements.
if gh api repos/arthurliebhardt/today-md/releases/latest > "$work_dir/latest.json" 2> "$work_dir/latest-error"; then
  previous_tag=$(python3 - "$work_dir/latest.json" <<'PY'
import json,sys
release=json.load(open(sys.argv[1]))
if any(asset["name"] == "appcast.xml" for asset in release["assets"]):
    print(release["tag_name"])
PY
  )
  if [[ -n "$previous_tag" ]]; then
    gh release download "$previous_tag" --repo arthurliebhardt/today-md --pattern appcast.xml --dir "$update_dir"
    printf '%s\n' "$sparkle_private_key" | "$sign_update" --ed-key-file - --verify "$update_dir/appcast.xml"
    python3 "$script_dir/release-metadata.py" check-previous-build "$update_dir/appcast.xml" "$build"
  fi
elif ! grep -q 'HTTP 404' "$work_dir/latest-error"; then
  cat "$work_dir/latest-error" >&2
  exit 1
fi
gh api repos/arthurliebhardt/today-md/releases/generate-notes \
  -f tag_name="$RELEASE_TAG" -f target_commitish="$(git rev-parse HEAD)" \
  --jq .body > "$update_dir/${zip_name%.zip}.txt"
printf '%s\n' "$sparkle_private_key" | "$work_dir/Sparkle/bin/generate_appcast" \
  --ed-key-file - --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "https://github.com/arthurliebhardt/today-md/releases/download/$RELEASE_TAG/" \
  --link https://todaymd.app "$update_dir"
unset sparkle_private_key
cp "$update_dir/$zip_name" "$update_dir/appcast.xml" "$output_dir/"
bash "$script_dir/verify-sparkle-release.sh" "$output_dir/appcast.xml" "$output_dir/$zip_name" "$RELEASE_TAG" "$build"
# Verify the actual packaged bytes, including framework symlinks and the stapled ticket.
mkdir "$work_dir/unpacked"
ditto -x -k "$output_dir/$zip_name" "$work_dir/unpacked"
codesign --verify --deep --strict --verbose=2 "$work_dir/unpacked/today-md.app"
xcrun stapler validate "$work_dir/unpacked/today-md.app"
spctl --assess --type execute --verbose=2 "$work_dir/unpacked/today-md.app"
python3 - "$output_dir/release.json" "$RELEASE_TAG" "$build" "$(git rev-parse HEAD)" <<'PY'
import json,sys
with open(sys.argv[1], "w") as stream:
    json.dump({"tag": sys.argv[2], "version": sys.argv[2][1:], "build": sys.argv[3],
               "commit": sys.argv[4], "sparkle": "2.10.0"}, stream, indent=2)
    stream.write("\n")
PY
(cd "$output_dir" && shasum -a 256 ./*.zip appcast.xml release.json > SHA256SUMS)
echo "Verified signed release files are ready in $output_dir"
