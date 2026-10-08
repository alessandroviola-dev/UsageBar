#!/bin/bash
# Shared safety checks; sourced by install.sh and uninstall.sh.
set -euo pipefail

fail() { printf 'UsageBar: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || fail 'macOS is required.'
[[ -n ${HOME:-} && $HOME == /* && $HOME != / ]] || fail 'HOME must be an absolute user directory.'
APP="/Applications/UsageBar.app"
LEGACY_APP="$HOME/Applications/UsageBar.app"
BUNDLE_ID=com.alessandroviola.usagebar

check_existing_app() {
    local app=${1:-$APP} identifier
    [[ ! -L /Applications && ! -L "$HOME/Applications" ]] || fail 'Refusing a symlinked Applications directory.'
    [[ ! -L "$app" ]] || fail "Refusing to replace/remove symlink: $app"
    if [[ -e "$app" ]]; then
        [[ -d "$app" && -x "$app/Contents/MacOS/UsageBar" ]] || fail "Incomplete bundle: $app"
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null) || fail "Not a valid UsageBar bundle: $app"
        [[ $identifier == "$BUNDLE_ID" ]] || fail "An unrelated application occupies $app"
        codesign --verify --deep --strict "$app" || fail "Invalid signature: $app"
    fi
}

# Use the full executable path, never a broad 'killall' that could affect other apps.
installed_pids() {
    local app=${1:-$APP} pid command
    for pid in $(/usr/bin/pgrep -x UsageBar || true); do
        command=$(/bin/ps -p "$pid" -o command= 2>/dev/null || true)
        case "$command" in
            "$app/Contents/MacOS/UsageBar"|"$app/Contents/MacOS/UsageBar "*) printf '%s\n' "$pid" ;;
        esac
    done
}

stop_installed_app() {
    local app=${1:-$APP} pids pid attempt
    pids=$(installed_pids "$app")
    [[ -n $pids ]] || return 0
    for pid in $pids; do
        # Recheck the exact path before signalling a possibly reused PID.
        if installed_pids "$app" | /usr/bin/grep -qx "$pid"; then kill -TERM "$pid" 2>/dev/null || true; fi
        for attempt in {1..50}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then fail "Could not stop UsageBar (PID $pid); installation unchanged."; fi
    done
}
