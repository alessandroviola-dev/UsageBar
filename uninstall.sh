#!/bin/bash
# Removes only verified UsageBar bundles, never provider credentials.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$ROOT/scripts/common.sh"
DELETE_PREFERENCES=0
case "${1:-}" in
    '') ;;
    --delete-preferences) DELETE_PREFERENCES=1 ;;
    *) printf 'Usage: %s [--delete-preferences]\n' "$0" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || fail 'Too many arguments.'
check_existing_app
check_existing_app "$LEGACY_APP"
for app in "$APP" "$LEGACY_APP"; do
    [[ ! -e "$app" || -w $(dirname "$app") ]] || fail "Directory is not writable: $(dirname "$app")"
done
for app in "$APP" "$LEGACY_APP"; do
    [[ -e "$app" ]] || continue
    stop_installed_app "$app"
    "$app/Contents/MacOS/UsageBar" --unregister-launch-at-login || fail "Launch at Login could not be removed; retained: $app"
    rm -rf -- "$app"
done
# Preserve user settings unless deletion was explicitly requested.
if [[ $DELETE_PREFERENCES == 1 ]]; then
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
fi
printf 'Removed UsageBar. Provider credentials were left untouched.\n'
