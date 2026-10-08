#!/bin/bash
# Builds an arm64, ad-hoc-signed UsageBar.app at the canonical system path only.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$ROOT/scripts/common.sh"

[[ $(uname -m) == arm64 ]] || fail 'Run from a native Apple Silicon terminal (not Rosetta).'
command -v swift >/dev/null || fail 'Swift is required (install Xcode or Command Line Tools).'
command -v codesign >/dev/null || fail 'codesign is required.'
check_existing_app
check_existing_app "$LEGACY_APP"
[[ -d /Applications && -w /Applications ]] || fail '/Applications must be writable; no per-user fallback is permitted.'

cd "$ROOT"
swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)
[[ -x "$BIN/UsageBar" ]] || fail 'Release executable was not produced.'

STAGE=$(mktemp -d "/Applications/.UsageBar-install.XXXXXX")
BACKUP="$STAGE/previous.app"
LEGACY_BACKUP="$STAGE/legacy.app"
NEW="$STAGE/UsageBar.app"
LEGACY_MOVED=0
REPLACED=0
COMMITTED=0
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    if [[ $COMMITTED == 0 ]]; then
        if [[ $REPLACED == 1 ]]; then
            stop_installed_app
            rm -rf -- "$APP" || { printf 'Recovery files retained: %s\n' "$STAGE" >&2; exit 1; }
            if [[ -d "$BACKUP" ]]; then
                mv -- "$BACKUP" "$APP" || { printf 'Recovery files retained: %s\n' "$STAGE" >&2; exit 1; }
                /usr/bin/open "$APP" || true
            fi
        fi
        if [[ $LEGACY_MOVED == 1 ]]; then
            mv -- "$LEGACY_BACKUP" "$LEGACY_APP" || { printf 'Recovery files retained: %s\n' "$STAGE" >&2; exit 1; }
            /usr/bin/open "$LEGACY_APP" || true
        fi
    fi
    rm -rf -- "$STAGE"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$NEW/Contents/Info.plist"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$NEW/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/Resources/AppIcon.icns" "$NEW/Contents/Resources/AppIcon.icns"
cp "$BIN/UsageBar" "$NEW/Contents/MacOS/UsageBar"
chmod 755 "$NEW/Contents/MacOS/UsageBar"
plutil -lint "$NEW/Contents/Info.plist" "$NEW/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
codesign --force --deep --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$NEW"
codesign --verify --deep --strict "$NEW"
check_existing_app "$NEW"

# Revalidate immediately before modifying either installation.
check_existing_app
check_existing_app "$LEGACY_APP"
stop_installed_app
stop_installed_app "$LEGACY_APP"
if [[ -e "$LEGACY_APP" ]]; then
    mv -- "$LEGACY_APP" "$LEGACY_BACKUP"
    LEGACY_MOVED=1
fi
# Canonical replacement and backup share the destination filesystem.
if [[ -e "$APP" ]]; then mv -- "$APP" "$BACKUP"; fi
REPLACED=1
mv -- "$NEW" "$APP"
codesign --verify --deep --strict "$APP"
/usr/bin/open -gj "$APP"
sleep 2
[[ -n $(installed_pids) ]] || fail 'The installed application did not remain running.'
plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
cmp -s "$ROOT/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" \
    || fail 'Installed privacy manifest differs from source.'
COMMITTED=1
printf 'UsageBar installed and running: %s\n' "$APP"
