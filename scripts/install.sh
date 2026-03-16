#!/bin/bash
set -e

APP_NAME="today-md"
ZIP_NAME="today-md-v1.0-macos.zip"

# Find the zip in common locations
ZIP_PATH=""
for dir in "$HOME/Downloads" "$(pwd)"; do
    if [ -f "$dir/$ZIP_NAME" ]; then
        ZIP_PATH="$dir/$ZIP_NAME"
        break
    fi
done

if [ -z "$ZIP_PATH" ]; then
    echo "Error: $ZIP_NAME not found in ~/Downloads or current directory."
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
