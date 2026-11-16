#!/usr/bin/env bash
# Points the Homebrew formula at a published release asset and commits it to the tap repo.
#
#   scripts/update-tap.sh <version> <asset-url> <sha256> [--dry-run]
#
# Edits the formula through the GitHub API, so no local clone of the tap is needed.
# --dry-run prints the diff and changes nothing.
#
# Env:
#   TAP_REPO      tap repository (default: Juan-Motta/homebrew-tap)
#   FORMULA_PATH  formula path inside the tap (default: Formula/discord-apple-music.rb)
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <version> <asset-url> <sha256> [--dry-run]" >&2
    exit 2
fi

VERSION="$1"
ASSET_URL="$2"
SHA256="$3"
DRY_RUN=0
[[ "${4:-}" == "--dry-run" ]] && DRY_RUN=1

TAP_REPO="${TAP_REPO:-Juan-Motta/homebrew-tap}"
FORMULA_PATH="${FORMULA_PATH:-Formula/discord-apple-music.rb}"

[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid sha256: $SHA256" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FILE_SHA="$(gh api "repos/$TAP_REPO/contents/$FORMULA_PATH" --jq .sha)"
gh api "repos/$TAP_REPO/contents/$FORMULA_PATH" --jq .content | base64 -d > "$WORK/current.rb"

# Replace only the first top-level `url` and `sha256` lines (the release asset).
awk -v url="$ASSET_URL" -v sha="$SHA256" '
    !u && /^  url "/    { print "  url \"" url "\""; u = 1; next }
    !s && /^  sha256 "/ { print "  sha256 \"" sha "\""; s = 1; next }
    { print }
    END { if (!u || !s) exit 3 }
' "$WORK/current.rb" > "$WORK/next.rb" || { echo "Formula has no url/sha256 line to update" >&2; exit 1; }

if cmp -s "$WORK/current.rb" "$WORK/next.rb"; then
    echo "Tap already points at $VERSION; nothing to do."
    exit 0
fi

diff -u "$WORK/current.rb" "$WORK/next.rb" | sed '1,2d' || true

if [[ "$DRY_RUN" == 1 ]]; then
    echo "(dry run: tap not changed)"
    exit 0
fi

gh api --method PUT "repos/$TAP_REPO/contents/$FORMULA_PATH" \
    -f message="feat: update discord-apple-music to $VERSION" \
    -f content="$(base64 < "$WORK/next.rb" | tr -d '\n')" \
    -f sha="$FILE_SHA" \
    --jq '"Tap updated: " + .commit.html_url'
