#!/usr/bin/env bash
# Builds a signed standalone macOS binary, and optionally notarizes and publishes it.
#
#   scripts/release.sh               build + sign + notarize -> dist/*.zip
#   scripts/release.sh --no-notarize build + sign only (local testing)
#   scripts/release.sh --publish     build + sign + notarize, then tag v<version>, create the
#                                    GitHub Release and point the Homebrew tap at it
#
# The version comes from package.json. --publish requires a clean main that matches origin/main
# and a version that has not been released yet.
#
# Env:
#   SIGNING_IDENTITY  codesign identity (default: first "Developer ID Application" in the keychain)
#   NOTARY_PROFILE    notarytool keychain profile (default: discord-apple-music), created once with:
#                     xcrun notarytool store-credentials discord-apple-music --apple-id <id> --team-id <team>
#   TAP_REPO          Homebrew tap updated by --publish (default: Juan-Motta/homebrew-tap)
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
    case "$arg" in
        --no-notarize) NOTARIZE=0 ;;
        --publish) PUBLISH=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
if [[ "$PUBLISH" == 1 && "$NOTARIZE" == 0 ]]; then
    echo "--publish requires notarization; drop --no-notarize." >&2
    exit 2
fi

NAME="discord-apple-music"
VERSION="$(node -p 'require("./package.json").version')"
TAG="v$VERSION"
ARCH="$(uname -m)"
BIN="dist/$NAME"
ZIP_NAME="$NAME-$VERSION-macos-$ARCH.zip"
ZIP="dist/$ZIP_NAME"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
NOTARY_PROFILE="${NOTARY_PROFILE:-discord-apple-music}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"

fail() { echo "$*" >&2; exit 1; }

[[ -n "$SIGNING_IDENTITY" ]] || fail "No 'Developer ID Application' certificate found in the keychain."

# Check everything publishing needs before spending minutes on build and notarization.
if [[ "$PUBLISH" == 1 ]]; then
    echo "==> Checking release preconditions for $TAG"
    [[ -n "$REPO" ]] || fail "Cannot resolve the GitHub repository (is gh logged in?)."
    [[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean; commit first."
    [[ "$(git branch --show-current)" == "main" ]] || fail "Publish from main."
    git fetch -q origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main; push or pull first."
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "Tag $TAG already exists; bump the version in package.json."
    ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || fail "Release $TAG already exists on GitHub."
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
[[ "$(unzip -Z1 "$ZIP")" == "$NAME" ]] || { unzip -l "$ZIP" >&2; fail "Unexpected archive contents"; }

if [[ "$NOTARIZE" == 1 ]]; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)"
    # `--wait` exits 0 even when Apple rejects the upload, so check the final status explicitly.
    STATUS="$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
        --output-format json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).status))')"
    [[ "$STATUS" == "Accepted" ]] || fail "Notarization status: $STATUS (see: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE)"
    # A bare executable cannot be stapled; Gatekeeper fetches the ticket online on first launch.
fi

SHA256="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

if [[ "$PUBLISH" == 1 ]]; then
    echo "==> Tagging $TAG"
    git tag -a "$TAG" -m "$TAG"
    git push -q origin "$TAG"

    echo "==> Creating GitHub Release $TAG"
    NOTES="$(mktemp)"
    trap 'rm -f "$NOTES"' EXIT
    cat > "$NOTES" <<EOF
## Install

\`\`\`bash
brew install juan-motta/tap/$NAME
brew services start $NAME
\`\`\`

Or download \`$ZIP_NAME\` below, move the binary somewhere permanent and run \`$NAME install\`.

Requires macOS on Apple Silicon and the Discord desktop app. Signed with a Developer ID certificate and notarized by Apple.

**SHA-256:** \`$SHA256\`
EOF
    gh release create "$TAG" "$ZIP" --repo "$REPO" --title "$TAG" --notes-file "$NOTES" --verify-tag

    echo "==> Updating Homebrew tap"
    scripts/update-tap.sh "$VERSION" "https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME" "$SHA256"
fi

echo "==> Done"
echo "$SHA256  $ZIP"
