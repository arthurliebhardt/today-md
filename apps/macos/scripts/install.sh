#!/bin/bash
set -euo pipefail

APP_NAME="today-md"
REPO="arthurliebhardt/today-md"
BUNDLE_ID="com.today-md.app"
LEGACY_DATA_DIR="$HOME/Library/Application Support/$APP_NAME"
SANDBOX_DATA_DIR="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/$APP_NAME"
SHOWCASE_TITLE_SQL="'Book dentist appointment','Buy groceries for dinner party','Plan weekend trip to Hamburg','Declutter photo library','Review onboarding polish PR','Draft release notes for v1.2','Prepare Q2 roadmap outline','Evaluate new analytics vendor'"

sqlite_scalar() {
    local database_path="$1"
    local query="$2"

    if ! command -v sqlite3 >/dev/null 2>&1; then
        return 1
    fi

    sqlite3 "$database_path" "$query" 2>/dev/null
}

database_task_count() {
    local database_path="$1"
    sqlite_scalar "$database_path" "SELECT COUNT(*) FROM tasks;"
}

database_is_empty() {
    local database_path="$1"
    local count

    count=$(database_task_count "$database_path") || return 1
    [ "${count:-0}" -eq 0 ]
}

database_has_non_showcase_tasks() {
    local database_path="$1"
    local count

    count=$(sqlite_scalar "$database_path" "SELECT COUNT(*) FROM tasks WHERE title NOT IN ($SHOWCASE_TITLE_SQL);") || return 1
    [ "${count:-0}" -gt 0 ]
}

database_looks_like_showcase_seed() {
    local database_path="$1"
    local task_count
    local non_showcase_task_count
    local list_count
    local expected_list_count

    task_count=$(sqlite_scalar "$database_path" "SELECT COUNT(*) FROM tasks;") || return 1
    non_showcase_task_count=$(sqlite_scalar "$database_path" "SELECT COUNT(*) FROM tasks WHERE title NOT IN ($SHOWCASE_TITLE_SQL);") || return 1
    list_count=$(sqlite_scalar "$database_path" "SELECT COUNT(*) FROM task_lists;") || return 1
    expected_list_count=$(sqlite_scalar "$database_path" "SELECT COUNT(*) FROM task_lists WHERE name IN ('Private', 'Work');") || return 1

    [ "${task_count:-0}" -gt 0 ] &&
        [ "${non_showcase_task_count:-0}" -eq 0 ] &&
        [ "${list_count:-0}" -eq 2 ] &&
        [ "${expected_list_count:-0}" -eq 2 ]
}

replace_sandbox_data_with_legacy_copy() {
    local backup_dir

    backup_dir="$HOME/Library/Application Support/${APP_NAME}-sandbox-backup-$(date +%Y%m%d-%H%M%S)"
    echo "Backing up current sandbox data to $backup_dir"
    mkdir -p "$(dirname "$backup_dir")"
    mv "$SANDBOX_DATA_DIR" "$backup_dir"

    echo "Restoring legacy task data into the sandbox container..."
    mkdir -p "$SANDBOX_DATA_DIR"
    ditto "$LEGACY_DATA_DIR" "$SANDBOX_DATA_DIR"
}

migrate_existing_data_if_needed() {
    local legacy_db="$LEGACY_DATA_DIR/$APP_NAME.sqlite"
    local sandbox_db="$SANDBOX_DATA_DIR/$APP_NAME.sqlite"

    if [ ! -f "$legacy_db" ]; then
        if [ -f "$sandbox_db" ]; then
            echo "Preserving existing app data in $SANDBOX_DATA_DIR"
        fi
        return
    fi

    if [ -f "$sandbox_db" ]; then
        if database_is_empty "$sandbox_db"; then
            replace_sandbox_data_with_legacy_copy
            return
        fi

        if database_looks_like_showcase_seed "$sandbox_db" && database_has_non_showcase_tasks "$legacy_db"; then
            replace_sandbox_data_with_legacy_copy
            return
        fi

        echo "Preserving existing app data in $SANDBOX_DATA_DIR"
        return
    fi

    echo "Migrating existing app data into the sandbox container..."
    mkdir -p "$SANDBOX_DATA_DIR"
    ditto "$LEGACY_DATA_DIR" "$SANDBOX_DATA_DIR"
}

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

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "Error: please quit $APP_NAME before installing."
    exit 1
fi

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

migrate_existing_data_if_needed

mv "$APP_PATH" "$INSTALL_DIR/"
echo "✓ $APP_NAME installed to $INSTALL_DIR"
echo "  Open it from your Applications folder or Spotlight."
