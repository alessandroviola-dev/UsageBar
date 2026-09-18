#!/bin/bash
# Creates an arm64, ad-hoc-signed app bundle and a source-free distributable ZIP.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP_NAME="UsageBar"
BUNDLE_ID="com.alessandroviola.usagebar"
INFO_PLIST="$ROOT/Resources/Info.plist"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
# Leave these unset for the reproducible ad-hoc path used by CI. A future release
# can set SIGNING_IDENTITY to a Developer ID Application identity and NOTARY_PROFILE
# to a notarytool keychain profile; neither credential is stored in this repository.
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

fail() { printf '%s\n' "build-release: $*" >&2; exit 1; }
[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required."
command -v swift >/dev/null || fail "Swift is required only to build a release. End users install the ZIP."
command -v codesign >/dev/null || fail "codesign is required."
command -v ditto >/dev/null || fail "ditto is required."
[[ -f "$INFO_PLIST" && -f "$ROOT/Resources/AppIcon.icns" ]] || fail "Missing bundle metadata or application icon."

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
[[ -n "$version" && -n "$build" ]] || fail "Bundle version is missing."

cd "$ROOT"
# Do not serialize the builder's absolute source path into the shipped executable.
swift build -c release --arch arm64 -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/Source"
bin_path=$(swift build -c release --arch arm64 --show-bin-path)
executable="$bin_path/$APP_NAME"
[[ -x "$executable" ]] || fail "Release executable was not produced: $executable"

stage=$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-release.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/$APP_NAME.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$INFO_PLIST" "$app/Contents/Info.plist"
cp "$ROOT/Resources/PrivacyInfo.xcprivacy" "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$executable" "$app/Contents/MacOS/$APP_NAME"
chmod 755 "$app/Contents/MacOS/$APP_NAME"

plutil -lint "$app/Contents/Info.plist" "$app/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == "$BUNDLE_ID" ]] || fail "Unexpected bundle identifier."
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist") == "$APP_NAME" ]] || fail "Unexpected executable name."
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$app/Contents/Info.plist") == "AppIcon" ]] || fail "App icon is not declared."

# Keep the release portable: it must not load a product from SwiftPM's build directory.
if otool -L "$app/Contents/MacOS/$APP_NAME" | grep -E '/\.build/|SwiftTerm\.framework' >/dev/null; then
    fail "The executable has a SwiftPM build-directory runtime dependency."
fi
[[ -z "$NOTARY_PROFILE" || "$SIGNING_IDENTITY" != "-" ]] || fail "Notarization requires a Developer ID signing identity."
codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

# The archive whitelist makes it impossible to ship repository sources or local build data.
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$APP_NAME.app"
cp -R "$app" "$OUTPUT_DIR/$APP_NAME.app"
zip="$OUTPUT_DIR/$APP_NAME-v$version-macOS.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/$APP_NAME.app" "$zip"
if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$OUTPUT_DIR/$APP_NAME.app"
    rm -f "$zip"
    ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/$APP_NAME.app" "$zip"
fi
entries=$(unzip -Z1 "$zip")
if printf '%s\n' "$entries" | grep -Ev "^${APP_NAME}\.app(/|$)" >/dev/null; then
    fail "ZIP contains files outside the application bundle."
fi
if printf '%s\n' "$entries" | grep -E '(^|/)(\.build|DerivedData|\.env|.*\.(pem|p12|cer|key)|.*\.log)(/|$)' >/dev/null; then
    fail "ZIP contains excluded local or credential material."
fi
if unzip -p "$zip" | grep -a -F '$HOME' >/dev/null; then
    fail "ZIP contains an absolute local user path."
fi

extract="$stage/extracted"
mkdir "$extract"
unzip -q "$zip" -d "$extract"
extracted="$extract/$APP_NAME.app"
[[ -x "$extracted/Contents/MacOS/$APP_NAME" && -s "$extracted/Contents/Resources/AppIcon.icns" ]] || fail "Extracted bundle is incomplete."
plutil -lint "$extracted/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$extracted"
printf 'Built %s (version %s, build %s)\nZIP: %s\n' "$OUTPUT_DIR/$APP_NAME.app" "$version" "$build" "$zip"
