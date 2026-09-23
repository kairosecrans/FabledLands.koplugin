#!/usr/bin/env bash
# Builds the release archive.
#
#   ./build-release.sh            # version from _meta.lua
#   ./build-release.sh 0.3.0      # override
#
# The archive extracts to a directory named FabledLands.koplugin, which is
# what KOReader needs -- it ignores any plugin directory whose name does not
# end in .koplugin. GitHub's own "Source code (zip)" unpacks to
# FabledLands.koplugin-<tag>/ instead, so it cannot be installed as-is. That
# is the whole reason this script exists.

set -euo pipefail
cd "$(dirname "$0")"

PLUGIN="FabledLands.koplugin"
# Shipped to users: the plugin itself, plus the licence (GPL-3.0 requires it
# to travel with the code) and the README. The test suite stays in the repo.
FILES=(_meta.lua main.lua fl_*.lua README.md LICENSE)

# --- version -----------------------------------------------------------------
if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION=$(sed -n 's/.*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' _meta.lua | head -1)
fi
if [ -z "${VERSION:-}" ]; then
    echo "error: no version given and none found in _meta.lua" >&2
    exit 1
fi

OUT="${PLUGIN}-v${VERSION}.zip"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# --- sanity ------------------------------------------------------------------
for f in "${FILES[@]}"; do
    [ -e "$f" ] || { echo "error: missing $f" >&2; exit 1; }
done

if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain -- "${FILES[@]}")" ]; then
        echo "warning: shipped files have uncommitted changes; the archive will"
        echo "         not match any tag."
    fi
fi

# --- build -------------------------------------------------------------------
mkdir -p "$STAGE/$PLUGIN"
cp "${FILES[@]}" "$STAGE/$PLUGIN/"

rm -f "$OUT"
( cd "$STAGE" && zip -rq "$OUT" "$PLUGIN" -x '.*' '*/.*' )
mv "$STAGE/$OUT" .

# --- verify ------------------------------------------------------------------
# Every shipped file must be byte-identical to the tag of the same name, so the
# archive and the source people can read cannot drift apart.
TAG="v${VERSION}"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    drift=0
    for f in "${FILES[@]}"; do
        if ! git show "$TAG:$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1; then
            echo "  DIFFERS FROM TAG: $f"
            drift=1
        fi
    done
    if [ "$drift" -eq 0 ]; then
        echo "verified: contents match tag $TAG"
    else
        echo "warning: contents do not match tag $TAG -- retag or bump the version"
    fi
else
    echo "note: no tag $TAG yet; create it with"
    echo "      git tag -a $TAG -m \"$TAG\" && git push origin $TAG"
fi

echo
echo "built $OUT"
unzip -l "$OUT" | tail -n +4 | head -n -2 | awk '{printf "  %8s  %s\n", $1, $4}'
command -v sha256sum >/dev/null && echo && sha256sum "$OUT"
