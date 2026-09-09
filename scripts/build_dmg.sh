#!/usr/bin/env bash
#
# Builds a Release Paguro.app and packages it as a disk image for testing.
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
#   Developer ID + notarized   double-click, and macOS opens it, with or
#                              without a network.
#   Developer ID, not notarized  right-click Open, once, and confirm.
#   ad hoc                     nothing works until the quarantine flag is
#                              cleared by hand. The failure reads as "the
#                              application cannot be opened", which looks like
#                              a crash rather than a policy.
#
# Notarization runs only when a stored notarytool profile exists, and it runs in
# two rounds. The first round submits the app and staples the ticket into the
# bundle, before the disk image is created. The second round submits the signed
# disk image and staples that ticket too. Each round waits on Apple, so the two
# rounds together add a few minutes to the build.
#
# The app round is necessary because a stapled ticket travels inside the bundle.
# Gatekeeper asks Apple for the ticket when the bundle does not carry one. A Mac
# that cannot reach that service, such as a managed Mac or a Mac with no network,
# then reports "Apple could not verify ... is free of malware", although Apple
# accepted the app. An app with its own ticket passes the check offline.
#
# Create the notarytool profile once with an app-specific password from
# appleid.apple.com:
#
#   xcrun notarytool store-credentials paguro \
#       --apple-id <your-apple-id> --team-id L2P2KC4C69 --password <app-specific>
#
# Set PAGURO_NOTARY_PROFILE to use a different profile name.
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
# The Icon Composer app icon needs macOS 26 to render.
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
    DMG_PATH="$OUTPUT_DIR/Paguro-$VERSION-test.dmg"
    EXTRA_BUILD_ARGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS="TEST_CONTROLS")
else
    DMG_PATH="$OUTPUT_DIR/Paguro-$VERSION.dmg"
    EXTRA_BUILD_ARGS=()
fi

echo "==> Generating the project"
( cd "$REPOSITORY_DIR" && xcodegen generate >/dev/null )

NOTARY_PROFILE="${PAGURO_NOTARY_PROFILE:-paguro}"
DEVELOPER_ID=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)

# The profile decides both notarization rounds. Test it before the build, so
# that a missing profile is reported at once and not after a long compile.
NOTARIZE=0
if [ -n "$DEVELOPER_ID" ]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        NOTARIZE=1
    else
        echo "==> Skipping notarization: no '$NOTARY_PROFILE' notarytool profile"
        echo "    Recipients will have to right-click Open the first time."
    fi
fi

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
    -project "$REPOSITORY_DIR/Paguro.xcodeproj" \
    -scheme Paguro \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    "${SIGN_ARGS[@]}" \
    ${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"} \
    PROVISIONING_PROFILE_SPECIFIER="" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build >/dev/null

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/Paguro.app"
[ -d "$APP_PATH" ] || { echo "ERROR: no Paguro.app was produced" >&2; exit 1; }

if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
    echo "ERROR: the debug entitlement survived; the app will not launch elsewhere" >&2
    exit 1
fi

if [ "$NOTARIZE" -eq 1 ]; then
    echo "==> Notarizing the app (this waits on Apple, usually a few minutes)"
    ZIP_PATH="$BUILD_DIR/Paguro.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    NOTARY_RESULT=$(xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || {
        echo "ERROR: the app notarization request failed" >&2
        exit 1
    }
    rm -f "$ZIP_PATH"

    # notarytool ends with status 0 even when Apple rejects the app, so read the
    # result. plutil reads the JSON report, and no other tool is needed.
    SUBMISSION_ID=$(printf '%s' "$NOTARY_RESULT" | plutil -extract id raw -o - - 2>/dev/null || true)
    NOTARY_STATUS=$(printf '%s' "$NOTARY_RESULT" | plutil -extract status raw -o - - 2>/dev/null || true)
    echo "    submission ${SUBMISSION_ID:-unknown}: ${NOTARY_STATUS:-unknown}"
    if [ "$NOTARY_STATUS" != "Accepted" ]; then
        echo "ERROR: Apple did not accept the app, so no disk image was written" >&2
        if [ -n "$SUBMISSION_ID" ]; then
            xcrun notarytool log "$SUBMISSION_ID" \
                --keychain-profile "$NOTARY_PROFILE" >&2 || true
        fi
        exit 1
    fi

    echo "==> Stapling the app ticket"
    xcrun stapler staple "$APP_PATH" || {
        echo "ERROR: the app ticket could not be stapled" >&2
        exit 1
    }
    xcrun stapler validate "$APP_PATH" >/dev/null || {
        echo "ERROR: the app carries no valid ticket after the staple" >&2
        exit 1
    }
fi

echo "==> Staging"
STAGE_DIR="$BUILD_DIR/stage"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Writing $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Paguro $VERSION$([ "$TEST_CONTROLS" -eq 1 ] && echo " test")" \
    -srcfolder "$STAGE_DIR" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

if [ -n "$DEVELOPER_ID" ]; then
    echo "==> Signing the disk image"
    codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

    if [ "$NOTARIZE" -eq 1 ]; then
        echo "==> Notarizing the disk image (this waits on Apple, usually a few minutes)"
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "==> Stapling the disk image ticket"
        xcrun stapler staple "$DMG_PATH"
    fi
fi

echo "==> Done"
echo "    $DMG_PATH"
echo "    $(du -h "$DMG_PATH" | cut -f1), minimum macOS $(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP_PATH/Contents/Info.plist")"
echo "    sha256 $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo
if xcrun stapler validate "$APP_PATH" >/dev/null 2>&1 \
    && xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    echo "    App and disk image notarized and stapled. Recipients can just open"
    echo "    it, online or offline."
elif [ -n "$DEVELOPER_ID" ]; then
    echo "    Signed but not notarized. Recipients: right-click the app, choose"
    echo "    Open, and confirm once."
else
    echo "    Ad hoc. On the receiving Mac, after dragging it to /Applications:"
    echo "      sudo xattr -dr com.apple.quarantine /Applications/Paguro.app"
fi
