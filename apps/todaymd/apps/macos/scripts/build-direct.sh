#!/usr/bin/env bash
# Builds the direct-download edition sold on toolstokeep.com: the same app,
# compiled with TODAYMD_LICENSED so Pro needs a toolstokeep license key, signed
# with Developer ID, notarized and zipped. GitHub/source builds are untouched.
#
#   TEAM_ID=ABCDE12345 bash scripts/build-direct.sh 1.8.1
#
# Needs once:
#   - CODESIGN_IDENTITY and CODESIGN_KEYCHAIN from a prepared signing environment
#   - NOTARY_KEY_FILE, ASC_KEY_ID and ASC_ISSUER_ID for Apple notarization
#   - TodayMdPurchaseManager.licensePublicKey set to toolstokeep.com's LICENSE_PUBLIC_KEY
# Then publish the zip from site/:
#   npm run release:publish -- todaymd 1.9.0 ../apps/todaymd/apps/macos/build/direct/1.9.0/today-md-1.9.0.zip any
set -euo pipefail
set +vx
umask 077

VERSION=${1:?usage: build-direct.sh <version>}
TEAM_ID=${TEAM_ID:?set TEAM_ID to your Apple Developer team id}
: "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY to the Developer ID Application identity}"
: "${CODESIGN_KEYCHAIN:?set CODESIGN_KEYCHAIN to the prepared signing keychain}"
: "${NOTARY_KEY_FILE:?set NOTARY_KEY_FILE to the temporary App Store Connect API key file}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
cd "$(dirname "$0")/.."
export VERSION TEAM_ID
BUILD_NUMBER=$(python3 scripts/release-metadata.py project-version --build)
export BUILD_NUMBER
[[ "$VERSION" == "$(python3 scripts/release-metadata.py project-version --short)" ]] || {
  echo 'The version must match Config/Version.xcconfig' >&2; exit 1;
}

if grep -q 'REPLACE_WITH_LICENSE_PUBLIC_KEY' today-md/Stores/TodayMdPurchaseManager.swift; then
  echo "Set TodayMdPurchaseManager.licensePublicKey to LICENSE_PUBLIC_KEY first." >&2
  exit 1
fi

OUT="build/direct/$VERSION"
[[ ! -e "$OUT" ]] || { echo "$OUT already exists; preserve it before a new build" >&2; exit 1; }
mkdir -p "$OUT/export" "$OUT/diagnostics"
work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/today-md-direct.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
stapler_with_retry() {
  local attempt status=1
  for attempt in 1 2 3; do
    if xcrun stapler "$@"; then
      return 0
    else
      status=$?
    fi
    [[ "$status" == 68 ]] || return "$status"
    if [[ "$attempt" -lt 3 ]]; then
      echo "Stapler $1 returned network error 68; retrying ($attempt/3)" >&2
      sleep "$((attempt * 5))"
    fi
  done
  return "$status"
}
cp /usr/bin/true "$work_dir/signing-canary"
python3 - "$CODESIGN_IDENTITY" "$CODESIGN_KEYCHAIN" "$work_dir/signing-canary" <<'PY'
import subprocess, sys
try:
    subprocess.run(["/usr/bin/codesign", "--force", "--sign", sys.argv[1], "--keychain", sys.argv[2],
                    "--timestamp=none", "--options", "runtime", sys.argv[3]], check=True, timeout=30)
except subprocess.TimeoutExpired:
    sys.exit("The Developer ID signing canary timed out; packaging has not started")
PY
developer_id_requirement='anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
codesign --verify --strict -R="$developer_id_requirement" "$work_dir/signing-canary"

xcodebuild archive \
  -project today-md.xcodeproj -scheme today-md -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$OUT/today-md.xcarchive" \
  -derivedDataPath "$work_dir/DerivedData" \
  DEVELOPMENT_TEAM="$TEAM_ID" MARKETING_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_ENTITLEMENTS=today-md/today-md-direct.entitlements \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=TODAYMD_LICENSED \
  ENABLE_HARDENED_RUNTIME=YES 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO

APP="$OUT/export/today-md.app"
ZIP="$OUT/today-md-$VERSION.zip"
ditto "$OUT/today-md.xcarchive/Products/Applications/today-md.app" "$APP"
codesign --force --sign "$CODESIGN_IDENTITY" --keychain "$CODESIGN_KEYCHAIN" --timestamp \
  --options runtime --generate-entitlement-der --entitlements today-md/today-md-direct.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 -R="$developer_id_requirement" "$APP"
python3 - "$APP" <<'PY'
import base64, os, pathlib, plistlib, re, subprocess, sys
app=pathlib.Path(sys.argv[1])
info=plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleShortVersionString"] == os.environ["VERSION"]
assert str(info["CFBundleVersion"]) == os.environ["BUILD_NUMBER"]
assert info["CFBundleIdentifier"] == "com.today-md.app"
binary=app / "Contents/MacOS/today-md"
assert set(subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()) == {"arm64", "x86_64"}
assert not (app / "Contents/Frameworks/Sparkle.framework").exists()
key=re.search(r'licensePublicKey = "([A-Za-z0-9+/=]+)"', pathlib.Path("today-md/Stores/TodayMdPurchaseManager.swift").read_text())[1]
assert len(base64.b64decode(key, validate=True)) == 32
assert key.encode() in binary.read_bytes(), "The production license key is missing from the built app"
details=subprocess.check_output(["codesign", "-dvvv", str(app)], stderr=subprocess.STDOUT, text=True)
assert "TeamIdentifier=" + os.environ["TEAM_ID"] in details and "runtime" in details
entitlements=plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
assert not entitlements.get("com.apple.security.get-task-allow", False)
assert entitlements.get("com.apple.security.app-sandbox") is True
assert entitlements.get("com.apple.security.network.client") is True
PY
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY_FILE" --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" --wait --timeout 20m --output-format json > "$OUT/diagnostics/notarization.json"
python3 - "$OUT/diagnostics/notarization.json" <<'PY'
import json, sys
result=json.load(open(sys.argv[1]))
if result.get("status") != "Accepted":
    sys.exit("Apple notarization was not Accepted; submission " + str(result.get("id")))
print("Apple notarization accepted: " + result["id"])
PY
stapler_with_retry staple "$APP"
stapler_with_retry validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
rm "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir "$work_dir/unpacked"
ditto -x -k "$ZIP" "$work_dir/unpacked"
codesign --verify --deep --strict --verbose=2 -R="$developer_id_requirement" "$work_dir/unpacked/today-md.app"
stapler_with_retry validate "$work_dir/unpacked/today-md.app"
spctl --assess --type execute --verbose=2 "$work_dir/unpacked/today-md.app"
ditto -c -k --sequesterRsrc --keepParent "$OUT/today-md.xcarchive/dSYMs" "$OUT/today-md-$VERSION.dSYM.zip"
python3 - "$OUT/release.json" <<'PY'
import json, os, subprocess, sys
commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
dirty=bool(subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], text=True))
with open(sys.argv[1], "w") as stream:
    json.dump({"version":os.environ["VERSION"], "build":os.environ["BUILD_NUMBER"], "edition":"licensed",
               "commit":commit, "uncommitted_changes":dirty, "team":os.environ["TEAM_ID"]}, stream, indent=2)
    stream.write("\n")
PY
(cd "$OUT" && shasum -a 256 "today-md-$VERSION.zip" "today-md-$VERSION.dSYM.zip" release.json > SHA256SUMS)

echo "Built, notarized and stapled: $ZIP"
echo "Publish from site/: npm run release:publish -- todaymd $VERSION ../apps/todaymd/apps/macos/$ZIP any"
