#!/bin/bash
# Builds an arm64, ad-hoc-signed UsageBar.app and replaces only this app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="UsageBar.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/usagebar-install.XXXXXX")"
BACKUP=""
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
[[ "$(uname)" == "Darwin" ]] || { echo "UsageBar installs on macOS only." >&2; exit 1; }
command -v swift >/dev/null || { echo "Swift is required (install Xcode or Command Line Tools)." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "This v0.1.0 installer builds arm64 only." >&2; exit 1; }
cd "$ROOT"
swift build -c release --arch arm64
BINARY="$(find .build -type f -path '*/release/UsageBar' -perm -111 | head -n 1)"
[[ -n "$BINARY" && -x "$BINARY" ]] || { echo "Release binary was not produced." >&2; exit 1; }
NEW="$WORK/$APP_NAME"
mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources"
cp "$BINARY" "$NEW/Contents/MacOS/UsageBar"
cp Resources/Info.plist "$NEW/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$NEW/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$NEW/Contents/Info.plist" >/dev/null
plutil -lint "$NEW/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
codesign --force --deep --sign - "$NEW" >/dev/null
codesign --verify --deep --strict "$NEW"
mkdir -p "$DEST_DIR"
pkill -x UsageBar 2>/dev/null || true
if [[ -e "$DEST" ]]; then
  BACKUP="$WORK/previous.app"
  mv "$DEST" "$BACKUP"
fi
if ! mv "$NEW" "$DEST" || ! codesign --verify --deep --strict "$DEST"; then
  rm -rf "$DEST"
  [[ -n "$BACKUP" && -e "$BACKUP" ]] && mv "$BACKUP" "$DEST"
  echo "Installation failed; previous app was restored." >&2
  exit 1
fi
open -gj "$DEST"
sleep 1
pgrep -x UsageBar >/dev/null || { echo "Installed, but UsageBar did not launch." >&2; exit 1; }
rm -rf "$BACKUP"
echo "Installed $DEST"
