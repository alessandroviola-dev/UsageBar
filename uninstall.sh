#!/bin/bash
# Removes only UsageBar and, by default, credentials created by UsageBar itself.
set -euo pipefail
APP="$HOME/Applications/UsageBar.app"
REMOVE_SECRETS=1
case "${1:-}" in
  --keep-credentials) REMOVE_SECRETS=0 ;;
  --remove-credentials|'') ;;
  *) echo "Usage: $0 [--keep-credentials|--remove-credentials]" >&2; exit 2 ;;
esac
if [[ -t 0 && "${1:-}" == "" ]]; then
  read -r -p "Remove UsageBar-created Keychain credentials? [Y/n] " answer
  [[ "${answer:-Y}" =~ ^[Nn]$ ]] && REMOVE_SECRETS=0
fi
pkill -x UsageBar 2>/dev/null || true
if [[ -x "$APP/Contents/MacOS/UsageBar" ]]; then
  "$APP/Contents/MacOS/UsageBar" --unregister-launch-at-login || true
  if [[ "$REMOVE_SECRETS" == 1 ]]; then
    "$APP/Contents/MacOS/UsageBar" --remove-usagebar-keychain || true
  fi
fi
rm -rf "$APP"
# Selected provider is non-secret, but removing it makes a reinstall clean.
defaults delete com.alessandroviola.usagebar 2>/dev/null || true
echo "Removed UsageBar."
