#!/usr/bin/env bash
# Builds, notarizes and optionally publishes "Discord Apple Music.app".
#
#   scripts/release.sh               build + sign + notarize -> dist/*.zip
#   scripts/release.sh --no-notarize build + sign only (local testing)
#   scripts/release.sh --publish     build + sign + notarize, then tag v<version>, create the
#                                    GitHub Release and point the Homebrew cask at it
#
# The version comes from the VERSION file. --publish requires a clean main that matches
# origin/main and a version that has not been released yet.
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

fail() { echo "$*" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
ZIP_NAME="DiscordAppleMusic-$VERSION-macos.zip"
ZIP="dist/$ZIP_NAME"

# Check everything publishing needs before spending minutes on build and notarization.
if [[ "$PUBLISH" == 1 ]]; then
    echo "==> Checking release preconditions for $TAG"
    REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
    [[ -n "$REPO" ]] || fail "Cannot resolve the GitHub repository (is gh logged in?)."
    [[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean; commit first."
    [[ "$(git branch --show-current)" == "main" ]] || fail "Publish from main."
    git fetch -q origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main; push or pull first."
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "Tag $TAG already exists; bump VERSION."
    ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || fail "Release $TAG already exists on GitHub."
fi

BUILD_FLAGS=()
[[ "$NOTARIZE" == 0 ]] && BUILD_FLAGS=(--no-notarize)
VERSION="$VERSION" scripts/build-app.sh ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}
[[ -f "$ZIP" ]] || fail "The build did not produce $ZIP"
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
brew trust --cask juan-motta/tap/discord-apple-music
brew install --cask juan-motta/tap/discord-apple-music
\`\`\`

Or download \`$ZIP_NAME\` below and move **Discord Apple Music** to Applications. Open it and turn on "Show in Discord".

Requires macOS 14 or later (Apple Silicon or Intel) and the Discord desktop app. Signed with a Developer ID certificate and notarized by Apple.

**SHA-256:** \`$SHA256\`
EOF
    gh release create "$TAG" "$ZIP" --repo "$REPO" --title "$TAG" --notes-file "$NOTES" --verify-tag

    echo "==> Updating Homebrew cask"
    URL="https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME"
    if gh api "repos/${TAP_REPO:-Juan-Motta/homebrew-tap}/contents/Casks/discord-apple-music.rb" >/dev/null 2>&1; then
        scripts/update-tap.sh "$VERSION" "$URL" "$SHA256"
    else
        echo "The tap has no Casks/discord-apple-music.rb yet; add it with version $VERSION, url $URL, sha256 $SHA256"
    fi
fi

echo "==> Done"
echo "$SHA256  $ZIP"
