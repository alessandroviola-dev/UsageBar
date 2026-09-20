#!/bin/bash
# Removes only UsageBar. UsageBar does not create or manage provider credentials.
set -euo pipefail
APP="$HOME/Applications/UsageBar.app"
case "${1:-}" in
  '') ;;
  *) echo "Usage: $0" >&2; exit 2 ;;
esac
pkill -x UsageBar 2>/dev/null || true
if [[ -x "$APP/Contents/MacOS/UsageBar" ]]; then
  "$APP/Contents/MacOS/UsageBar" --unregister-launch-at-login || true
fi
rm -rf "$APP"
# The selected provider is non-secret; removing it makes a reinstall clean.
defaults delete com.alessandroviola.usagebar 2>/dev/null || true
echo "Removed UsageBar."
