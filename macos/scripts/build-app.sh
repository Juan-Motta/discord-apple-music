#!/usr/bin/env bash
# Builds "Discord Apple Music.app" (universal: Apple Silicon + Intel), signed with a Developer ID.
#
#   macos/scripts/build-app.sh               build + sign + notarize + staple -> macos/dist/*.zip
#   macos/scripts/build-app.sh --no-notarize build + sign only (local testing)
#
# Env:
#   VERSION           app version (default: version in the repo's package.json)
#   SIGNING_IDENTITY  codesign identity (default: first "Developer ID Application" in the keychain)
#   NOTARY_PROFILE    notarytool keychain profile (default: discord-apple-music)
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=1
for arg in "$@"; do
    case "$arg" in
        --no-notarize) NOTARIZE=0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

fail() { echo "$*" >&2; exit 1; }

APP_NAME="Discord Apple Music"
VERSION="${VERSION:-$(node -p 'require("../package.json").version' 2>/dev/null || sed -n 's/.*"version": "\(.*\)".*/\1/p' ../package.json)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-discord-apple-music}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
[[ -n "$SIGNING_IDENTITY" ]] || fail "No 'Developer ID Application' certificate found in the keychain."

DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/DiscordAppleMusic-$VERSION-macos.zip"
PRODUCTS=".build/out/Products/Release"

echo "==> Testing"
# With only the Command Line Tools, the build system sometimes fails to load swift-testing's
# macro plugin ("plugin for module 'TestingMacros' not found"); pointing at it explicitly fixes it.
TEST_FLAGS=()
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
[[ -d "$PLUGINS" ]] && TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
if ! TEST_LOG="$(swift test ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"} 2>&1)"; then
    echo "$TEST_LOG" | tail -30 >&2
    fail "Tests failed."
fi
echo "$TEST_LOG" | grep -E "Test run with" | tail -1 || true

echo "==> Building universal binaries"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
for bin in DiscordAppleMusic DiscordAppleMusicAgent; do
    [[ "$(lipo -archs "$PRODUCTS/$bin")" == *arm64* && "$(lipo -archs "$PRODUCTS/$bin")" == *x86_64* ]] \
        || fail "$bin is not universal"
done

echo "==> Assembling $APP_NAME.app $VERSION"
rm -rf "$DIST"
HELPER="$APP/Contents/Library/LoginItems/DiscordAppleMusicAgent.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" "$HELPER/Contents/MacOS"
cp "$PRODUCTS/DiscordAppleMusic" "$APP/Contents/MacOS/"
cp "$PRODUCTS/DiscordAppleMusicAgent" "$HELPER/Contents/MacOS/"
sed "s/__VERSION__/$VERSION/g" Bundle/Info.plist > "$APP/Contents/Info.plist"
sed "s/__VERSION__/$VERSION/g" Bundle/AgentInfo.plist > "$HELPER/Contents/Info.plist"
cp Bundle/AppIcon.icns "$APP/Contents/Resources/"
cp Bundle/dev.discord-apple-music.agent.plist "$APP/Contents/Library/LaunchAgents/"
plutil -lint -s "$APP/Contents/Info.plist" "$HELPER/Contents/Info.plist" "$APP/Contents/Library/LaunchAgents/"*.plist

echo "==> Signing as: $SIGNING_IDENTITY"
# Inside-out: nested code first, then the bundle that seals it.
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements Bundle/Agent.entitlements "$HELPER"
# macOS attributes the agent's Apple Events to this app (its "responsible" process), so it needs
# the entitlement too; without it the request is denied with no prompt (-1743).
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements Bundle/Agent.entitlements "$APP"
codesign --verify --deep --strict "$APP"

if [[ "$NOTARIZE" == 1 ]]; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)"
    ditto -c -k --keepParent --norsrc "$APP" "$ZIP"
    # `--wait` exits 0 even when Apple rejects the upload, so check the final status explicitly.
    STATUS="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json \
        | plutil -extract status raw -)"
    [[ "$STATUS" == "Accepted" ]] || fail "Notarization status: $STATUS"
    # Apps (unlike bare binaries) can carry the ticket, so they open offline on first launch.
    xcrun stapler staple -q "$APP"
    spctl --assess --type execute "$APP" || fail "Gatekeeper rejected the app"
fi

echo "==> Packaging"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc "$APP" "$ZIP"

echo "==> Done ($(du -sh "$APP" | cut -f1) app, $(du -h "$ZIP" | cut -f1) zip)"
echo "$(shasum -a 256 "$ZIP" | cut -d' ' -f1)  $ZIP"
