#!/usr/bin/env bash
set -euo pipefail

readonly app_name="CmdTab"
readonly install_dir="/Applications"
readonly app_path="${install_dir}/${app_name}.app"
readonly download_url="https://github.com/sadn1ck/cmdtab/releases/latest/download/${app_name}.zip"
readonly checksum_url="${download_url}.sha256"

tmp_dir="$(mktemp -d -t cmdtab-install)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

archive_path="${tmp_dir}/${app_name}.zip"
checksum_path="${archive_path}.sha256"
echo "Downloading ${app_name} from GitHub..."
curl --fail --location --silent --show-error "$download_url" --output "$archive_path"
curl --fail --location --silent --show-error "$checksum_url" --output "$checksum_path"

echo "Verifying SHA-256 checksum..."
(cd "$tmp_dir" && shasum --algorithm 256 --check "${app_name}.zip.sha256")

ditto -x -k "$archive_path" "$tmp_dir"
downloaded_app="${tmp_dir}/${app_name}.app"

if [[ ! -d "$downloaded_app" ]]; then
    echo "Installer error: ${app_name}.app was not found in the release archive." >&2
    exit 1
fi

if pgrep -x "$app_name" >/dev/null 2>&1; then
    echo "${app_name} is running. Asking it to quit before reinstalling..."
    if ! osascript \
        -e 'tell application "System Events"' \
        -e 'display dialog "CmdTab is running and must quit before it can be updated." buttons {"Cancel", "Quit CmdTab"} default button "Quit CmdTab" with title "CmdTab Installer"' \
        -e 'end tell' >/dev/null; then
        echo "Installation cancelled; ${app_name} is still running." >&2
        exit 1
    fi

    osascript -e 'tell application "CmdTab" to quit'
    for _ in {1..20}; do
        if ! pgrep -x "$app_name" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    if pgrep -x "$app_name" >/dev/null 2>&1; then
        echo "Installation stopped; ${app_name} did not quit." >&2
        exit 1
    fi
fi

if [[ -e "$app_path" ]]; then
    echo "Replacing ${app_path}"
    rm -rf "$app_path"
fi

echo "Installing ${app_name} to ${install_dir}..."
ditto "$downloaded_app" "$app_path"
echo "Installed ${app_name}. Quit and reopen it if it was already running."
