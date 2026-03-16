#!/bin/bash
set -euo pipefail

APP_NAME="today-md"
REPO="arthurliebhardt/today-md"

download_latest_zip() {
    local api_url="https://api.github.com/repos/$REPO/releases/latest"
    local latest_url

    latest_url=$(
        curl -fsSL "$api_url" |
            sed -nE 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]*today-md-v[^"]*-macos\.zip)".*/\1/p' |
            head -n 1
    )

    if [ -z "$latest_url" ]; then
        echo "Error: could not determine the latest release asset from GitHub."
        exit 1
    fi

    ZIP_PATH="$TMPDIR/$(basename "$latest_url")"
    echo "Downloading latest release: $latest_url"
    curl -fL "$latest_url" -o "$ZIP_PATH"
}

# Create a temp directory for extraction and optional download
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ZIP_PATH="${1:-}"

if [ -n "$ZIP_PATH" ]; then
    if [ ! -f "$ZIP_PATH" ]; then
        echo "Error: zip file not found: $ZIP_PATH"
        exit 1
    fi
else
    download_latest_zip
fi

echo "Found $ZIP_PATH"
echo "Installing $APP_NAME..."

# Unzip
EXTRACT_DIR="$TMPDIR/extracted"
mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

# Remove quarantine attribute
APP_PATH="$EXTRACT_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: extracted archive did not contain $APP_NAME.app"
    exit 1
fi

xattr -rd com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# Install to /Applications when writable, otherwise fall back to ~/Applications
if [ -w "/Applications" ]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi

if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Removing existing $APP_NAME from $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

mv "$APP_PATH" "$INSTALL_DIR/"
echo "✓ $APP_NAME installed to $INSTALL_DIR"
echo "  Open it from your Applications folder or Spotlight."
