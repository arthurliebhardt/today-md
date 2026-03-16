#!/bin/bash
set -e

APP_NAME="today-md"

# Find the newest matching zip in common locations
ZIP_PATH=""
for dir in "$HOME/Downloads" "$(pwd)"; do
    CANDIDATE=$(find "$dir" -maxdepth 1 -type f -name 'today-md-v*-macos.zip' | sort | tail -n 1)
    if [ -n "$CANDIDATE" ]; then
        ZIP_PATH="$CANDIDATE"
        break
    fi
done

if [ -z "$ZIP_PATH" ]; then
    echo "Error: no today-md release zip found in ~/Downloads or current directory."
    echo "Usage: place the zip in ~/Downloads and re-run, or run from the same directory."
    exit 1
fi

echo "Found $ZIP_PATH"
echo "Installing $APP_NAME..."

# Create a temp directory for extraction
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Unzip
ditto -x -k "$ZIP_PATH" "$TMPDIR"

# Remove quarantine attribute
xattr -rd com.apple.quarantine "$TMPDIR/$APP_NAME.app"

# Move to /Applications
if [ -d "/Applications/$APP_NAME.app" ]; then
    echo "Removing existing $APP_NAME from /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
fi

mv "$TMPDIR/$APP_NAME.app" /Applications/
echo "✓ $APP_NAME installed to /Applications"
echo "  Open it from your Applications folder or Spotlight."
