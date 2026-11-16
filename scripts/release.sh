#!/usr/bin/env bash
# Builds a signed (and optionally notarized) standalone macOS binary.
#
#   scripts/release.sh               build + sign + notarize -> dist/*.zip
#   scripts/release.sh --no-notarize build + sign only (local testing)
#
# Env:
#   SIGNING_IDENTITY  codesign identity (default: first "Developer ID Application" in the keychain)
#   NOTARY_PROFILE    notarytool keychain profile (default: discord-apple-music), created once with:
#                     xcrun notarytool store-credentials discord-apple-music --apple-id <id> --team-id <team>
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

NAME="discord-apple-music"
VERSION="$(node -p 'require("./package.json").version')"
ARCH="$(uname -m)"
BIN="dist/$NAME"
ZIP="dist/$NAME-$VERSION-macos-$ARCH.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-discord-apple-music}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "No 'Developer ID Application' certificate found in the keychain." >&2
    exit 1
fi

echo "==> Testing"
npm test --silent

echo "==> Bundling"
rm -rf dist
npx esbuild src/cli.ts --bundle --platform=node --target=node24 --format=cjs \
    --outfile=dist/cli.cjs --log-level=warning

echo "==> Building single executable ($ARCH)"
node --build-sea sea-config.json

echo "==> Signing as: $SIGNING_IDENTITY"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
    --entitlements build/entitlements.plist --identifier "dev.$NAME" "$BIN"
codesign --verify --strict "$BIN"
"$BIN" --help >/dev/null # an invalid signature makes macOS kill the process here

echo "==> Packaging"
# Zip only the binary at the archive root, without AppleDouble (._*) resource files.
ditto -c -k --norsrc "$BIN" "$ZIP"
[[ "$(unzip -Z1 "$ZIP")" == "$NAME" ]] || { echo "Unexpected archive contents" >&2; unzip -l "$ZIP" >&2; exit 1; }

if [[ "$NOTARIZE" == 1 ]]; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    # A bare executable cannot be stapled; Gatekeeper fetches the ticket online on first launch.
fi

echo "==> Done"
shasum -a 256 "$ZIP"
