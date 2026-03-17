#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/today-md.app"

xcodebuild \
  -project "$ROOT_DIR/today-md.xcodeproj" \
  -scheme today-md \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

open "$APP_PATH"
