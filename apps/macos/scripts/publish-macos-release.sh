#!/usr/bin/env bash
# Upload all files to a draft, verify the uploaded bytes, then publish the feed.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/../../.." && pwd)
cd "$repo_dir/dist/macos"
: "${RELEASE_TAG:?Set RELEASE_TAG}"
python3 - "$RELEASE_TAG" "$(git rev-parse HEAD)" <<'PY'
import json,sys
release=json.load(open("release.json"))
if release["tag"] != sys.argv[1] or release["commit"] != sys.argv[2]:
    sys.exit("Artifacts must come from this exact release tag and commit")
PY
shasum -a 256 -c SHA256SUMS
build=$(python3 -c 'import json; print(json.load(open("release.json"))["build"])')
bash "$script_dir/verify-sparkle-release.sh" appcast.xml "today-md-$RELEASE_TAG-macos.zip" "$RELEASE_TAG" "$build"
release_repo=arthurliebhardt/today-md
if gh release view "$RELEASE_TAG" --repo "$release_repo" >/dev/null 2>&1; then
  echo 'This release already exists. Published assets are never replaced; investigate an unfinished draft before retrying.' >&2
  exit 1
fi
work_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/today-md-publish.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
cat > "$work_dir/notes.md" <<'NOTES'
Download the macOS ZIP, unzip it, and move today-md.app to Applications.

This build is signed with Developer ID, notarized by Apple, and includes in-app updates. Users of releases that predate the updater must install this version manually once. App Store users continue to update through the App Store.
NOTES
# The draft has no publicly reachable feed. Every upload is complete before promotion.
gh release create "$RELEASE_TAG" --repo "$release_repo" --verify-tag --draft \
  --title "today-md $RELEASE_TAG" --notes-file "$work_dir/notes.md" --generate-notes \
  "today-md-$RELEASE_TAG-macos.zip" "today-md-$RELEASE_TAG-macos.dSYM.zip" release.json SHA256SUMS
gh release upload "$RELEASE_TAG" appcast.xml --repo "$release_repo"
mkdir "$work_dir/downloaded"
gh release download "$RELEASE_TAG" --repo "$release_repo" --dir "$work_dir/downloaded"
(cd "$work_dir/downloaded" && shasum -a 256 -c SHA256SUMS)
cmp SHA256SUMS "$work_dir/downloaded/SHA256SUMS"
bash "$script_dir/verify-sparkle-release.sh" "$work_dir/downloaded/appcast.xml" \
  "$work_dir/downloaded/today-md-$RELEASE_TAG-macos.zip" "$RELEASE_TAG" "$build"
gh release edit "$RELEASE_TAG" --repo "$release_repo" --draft=false --latest
# Confirm the stable feed URL now serves the bytes that were verified in the draft.
feed_matches=0
for attempt in 1 2 3 4 5 6 7 8; do
  if curl --fail --silent --show-error --location \
      https://github.com/arthurliebhardt/today-md/releases/latest/download/appcast.xml \
      -o "$work_dir/published-appcast.xml" && \
      cmp -s appcast.xml "$work_dir/published-appcast.xml"; then
    feed_matches=1
    break
  fi
  echo "Waiting for the verified stable feed (attempt $attempt of 8)"
  sleep 5
done
[[ "$feed_matches" == 1 ]] || { echo 'The latest feed URL has not served the verified release yet' >&2; exit 1; }
echo "Published https://github.com/$release_repo/releases/tag/$RELEASE_TAG"
