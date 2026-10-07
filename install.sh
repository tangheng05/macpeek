#!/bin/sh
# Downloads the latest Macpeek release and installs it into Applications.
set -e

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
    echo "Macpeek needs macOS 26 or later." >&2
    exit 1
fi

dest=/Applications
[ -w "$dest" ] || dest="$HOME/Applications"
mkdir -p "$dest"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Macpeek..."
curl -fsSL https://github.com/tangheng05/macpeek/releases/latest/download/Macpeek.zip -o "$tmp/Macpeek.zip"
ditto -x -k "$tmp/Macpeek.zip" "$tmp"

pkill -x MacpeekApp 2>/dev/null || true
rm -rf "$dest/Macpeek.app"
mv "$tmp/Macpeek.app" "$dest/"
xattr -dr com.apple.quarantine "$dest/Macpeek.app" 2>/dev/null || true
open "$dest/Macpeek.app"

echo "Installed to $dest. Look for the CPU and RAM bars in your menu bar."
