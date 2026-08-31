#!/usr/bin/env bash
#
# Builds a Release Blatta.app and packages it as a disk image for testing.
#
#   scripts/build_dmg.sh                 writes to ~/Desktop
#   scripts/build_dmg.sh /some/dir       writes there instead
#
# This produces a TEST build, not a release. It is signed ad hoc, because the
# project has no Developer ID yet, so macOS refuses to launch it on any machine
# it did not come from until the quarantine flag is cleared. The README says
# how. Do not hand this to anyone without that instruction; the failure reads
# as "the application cannot be opened", which looks like a crash rather than a
# policy.
#
# Two build settings are deliberate:
#
#   CODE_SIGN_IDENTITY=-                 sign ad hoc, since no Developer ID
#                                        identity exists to sign with.
#   CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
#                                        drop com.apple.security.get-task-allow,
#                                        which Xcode adds on a plain `build`.
#                                        That entitlement is for debugging, and
#                                        with hardened runtime and the sandbox
#                                        it stops the app launching on a machine
#                                        that did not build it.
#
# The app icon needs macOS 26 to render. See docs/ERRORS.md.
set -euo pipefail

REPOSITORY_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$HOME/Desktop}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$REPOSITORY_DIR/project.yml")
DMG_PATH="$OUTPUT_DIR/Blatta-$VERSION.dmg"

echo "==> Generating the project"
( cd "$REPOSITORY_DIR" && xcodegen generate >/dev/null )

echo "==> Building Release"
xcodebuild \
    -project "$REPOSITORY_DIR/Blatta.xcodeproj" \
    -scheme Blatta \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build >/dev/null

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/Blatta.app"
[ -d "$APP_PATH" ] || { echo "ERROR: no Blatta.app was produced" >&2; exit 1; }

if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
    echo "ERROR: the debug entitlement survived; the app will not launch elsewhere" >&2
    exit 1
fi

echo "==> Staging"
STAGE_DIR="$BUILD_DIR/stage"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Writing $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Blatta $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

echo "==> Done"
echo "    $DMG_PATH"
echo "    $(du -h "$DMG_PATH" | cut -f1), minimum macOS $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"
echo "    sha256 $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo
echo "    On the receiving Mac, after dragging it to /Applications:"
echo "      sudo xattr -dr com.apple.quarantine /Applications/Blatta.app"
