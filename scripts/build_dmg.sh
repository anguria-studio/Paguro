#!/usr/bin/env bash
#
# Builds a Release Blatta.app and packages it as a disk image for testing.
#
#   scripts/build_dmg.sh                 writes to ~/Desktop
#   scripts/build_dmg.sh /some/dir       writes there instead
#   scripts/build_dmg.sh --test-controls includes the Settings test controls
#
# --test-controls compiles with TEST_CONTROLS defined, which reveals the test
# island alert in Settings. It does not turn on the other debug gates: logging,
# the compatibility fixture and the simulated screen presets stay out. The disk
# image is named with a -test suffix so it cannot be confused with a release.
#
# It signs with a Developer ID Application identity when the keychain holds one,
# and ad hoc otherwise. The difference decides what a recipient has to do:
#
#   Developer ID + notarized   double-click, and macOS opens it.
#   Developer ID, not notarized  right-click Open, once, and confirm.
#   ad hoc                     nothing works until the quarantine flag is
#                              cleared by hand. The failure reads as "the
#                              application cannot be opened", which looks like
#                              a crash rather than a policy.
#
# Notarization runs only when a stored notarytool profile exists. Create one
# once with an app-specific password from appleid.apple.com:
#
#   xcrun notarytool store-credentials blatta \
#       --apple-id <your-apple-id> --team-id L2P2KC4C69 --password <app-specific>
#
# Set BLATTA_NOTARY_PROFILE to use a different profile name.
#
# Two build settings are deliberate:
#
#   CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
#                        drops com.apple.security.get-task-allow, which Xcode
#                        adds on a plain `build`. That entitlement is for
#                        debugging, and with hardened runtime and the sandbox it
#                        stops the app launching on a machine that did not build
#                        it. Notarization also rejects a bundle carrying it.
#   OTHER_CODE_SIGN_FLAGS=--timestamp
#                        a secure timestamp, which notarization requires.
#
# The app icon needs macOS 26 to render. See docs/ERRORS.md.
set -euo pipefail

REPOSITORY_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_CONTROLS=0
OUTPUT_DIR="$HOME/Desktop"
for ARGUMENT in "$@"; do
    case "$ARGUMENT" in
        --test-controls) TEST_CONTROLS=1 ;;
        -*) echo "unknown option: $ARGUMENT" >&2; exit 2 ;;
        *) OUTPUT_DIR="$ARGUMENT" ;;
    esac
done
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$REPOSITORY_DIR/project.yml")
if [ "$TEST_CONTROLS" -eq 1 ]; then
    DMG_PATH="$OUTPUT_DIR/Blatta-$VERSION-test.dmg"
    EXTRA_BUILD_ARGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS="TEST_CONTROLS")
else
    DMG_PATH="$OUTPUT_DIR/Blatta-$VERSION.dmg"
    EXTRA_BUILD_ARGS=()
fi

echo "==> Generating the project"
( cd "$REPOSITORY_DIR" && xcodegen generate >/dev/null )

NOTARY_PROFILE="${BLATTA_NOTARY_PROFILE:-blatta}"
DEVELOPER_ID=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)

if [ -n "$DEVELOPER_ID" ]; then
    TEAM_ID=$(printf '%s' "$DEVELOPER_ID" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
    echo "==> Building Release, signed as $DEVELOPER_ID"
    SIGN_ARGS=(
        CODE_SIGN_IDENTITY="$DEVELOPER_ID"
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM="$TEAM_ID"
        OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
else
    echo "==> Building Release, signed ad hoc (no Developer ID in the keychain)"
    SIGN_ARGS=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM=""
    )
fi

xcodebuild \
    -project "$REPOSITORY_DIR/Blatta.xcodeproj" \
    -scheme Blatta \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    "${SIGN_ARGS[@]}" \
    ${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"} \
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
    -volname "Blatta $VERSION$([ "$TEST_CONTROLS" -eq 1 ] && echo " test")" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

if [ -n "$DEVELOPER_ID" ]; then
    echo "==> Signing the disk image"
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "==> Notarizing (this waits on Apple, usually a few minutes)"
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "==> Stapling the ticket"
        xcrun stapler staple "$DMG_PATH"
    else
        echo "==> Skipping notarization: no '$NOTARY_PROFILE' notarytool profile"
        echo "    Recipients will have to right-click Open the first time."
    fi
fi

echo "==> Done"
echo "    $DMG_PATH"
echo "    $(du -h "$DMG_PATH" | cut -f1), minimum macOS $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"
echo "    sha256 $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo
if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    echo "    Notarized and stapled. Recipients can just open it."
elif [ -n "$DEVELOPER_ID" ]; then
    echo "    Signed but not notarized. Recipients: right-click the app, choose"
    echo "    Open, and confirm once."
else
    echo "    Ad hoc. On the receiving Mac, after dragging it to /Applications:"
    echo "      sudo xattr -dr com.apple.quarantine /Applications/Blatta.app"
fi
