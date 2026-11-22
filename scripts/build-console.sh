#!/usr/bin/env bash
# Build the OpenZiti Admin Console (ZAC) from source and install it as this repo's
# infrastructure/console/ bundle, e.g. to try a fork or a feature branch.
#
#   scripts/build-console.sh [--repo URL] [--ref BRANCH|TAG|SHA] [--from-dir PATH]
#
#   --repo      Git URL to clone (default: https://github.com/openziti/ziti-console.git)
#   --ref       Branch, tag or commit to build (default: main)
#   --from-dir  Build an existing local checkout instead of cloning (its current state)
#
# Then push it to a running deployment without touching the controller:
#   ./deploy-ziti.sh --ssh user@host --update-console     (or: make console-update TARGET=user@host)
#
# To return to the pinned, checksum-verified build:
#   scripts/fetch-console.sh infrastructure --force
set -euo pipefail

REPO="https://github.com/openziti/ziti-console.git"
REF="main"
FROM_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --ref) REF="$2"; shift 2 ;;
        --from-dir) FROM_DIR="$2"; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/infrastructure/console"
command -v node >/dev/null || { echo "node (>= 18) is required" >&2; exit 1; }
command -v npm >/dev/null || { echo "npm is required" >&2; exit 1; }

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

if [ -n "$FROM_DIR" ]; then
    SRC="$(cd "$FROM_DIR" && pwd)"
    SOURCE_DESC="local checkout $SRC"
    if git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1; then
        SOURCE_DESC="$(git -C "$SRC" remote get-url origin 2>/dev/null || echo "$SRC")@$(git -C "$SRC" rev-parse --abbrev-ref HEAD)"
        SHA="$(git -C "$SRC" rev-parse --short HEAD)"
        [ -n "$(git -C "$SRC" status --porcelain)" ] && SHA="$SHA (with uncommitted changes)"
    else
        SHA="unknown"
    fi
else
    WORK="$(mktemp -d)"
    SRC="$WORK/ziti-console"
    echo "▶ Cloning $REPO ($REF)..."
    git clone --quiet --filter=blob:none "$REPO" "$SRC"
    git -C "$SRC" checkout --quiet "$REF"
    SOURCE_DESC="$REPO@$REF"
    SHA="$(git -C "$SRC" rev-parse --short HEAD)"
fi

echo "▶ Installing dependencies (npm ci; its postinstall builds ziti-console-lib)..."
(cd "$SRC" && npm ci --no-audit --no-fund --loglevel=error)
# The app copies its icons, fonts, scripts and settings from node_modules/ziti-console-lib/assets,
# which only exists in the built library (dist/ziti-console-lib). ZAC 4.8.1 points the dependency
# at the library's source (projects/ziti-console-lib) instead, so those assets would silently be
# left out. Point it back at the built library, as in 4.8.0 and earlier.
if [ ! -d "$SRC/node_modules/ziti-console-lib/assets" ] && [ -d "$SRC/dist/ziti-console-lib/assets" ]; then
    echo "▶ Linking node_modules/ziti-console-lib to the built library (dist/ziti-console-lib)..."
    rm -rf "$SRC/node_modules/ziti-console-lib"
    ln -s ../dist/ziti-console-lib "$SRC/node_modules/ziti-console-lib"
fi
# Same steps as the upstream release (build.sh used by .github/workflows/releases.yml):
# a production app build with relative base/deploy URLs, then the bundle CSS url() rewrite.
echo "▶ Building the console (production)..."
(cd "$SRC" \
    && { [ ! -f scripts/check-route-segments.mjs ] || node scripts/check-route-segments.mjs; } \
    && npx ng build ziti-console --base-href ./ --deploy-url ./ --configuration production \
    && node ./scripts/rewrite-bundle-css.mjs)

OUT="$SRC/dist/app-ziti-console"
[ -f "$OUT/index.html" ] || { echo "Build output not found in $OUT" >&2; exit 1; }
# A build can succeed with the library's assets missing; refuse to install one that would run without them.
for f in assets/data/settings.json assets/fonts assets/icons/favicon.ico assets/scripts/components/leaflet/leaflet.js; do
    [ -e "$OUT/$f" ] || { echo "Build output is missing $f (library assets not copied); not installing it." >&2; exit 1; }
done

echo "▶ Installing into infrastructure/console/ ..."
find "$DEST" -mindepth 1 -delete 2>/dev/null || mkdir -p "$DEST"
# Source maps are large and not needed to run the console.
(cd "$OUT" && find . -type f ! -name '*.map' -print0 | while IFS= read -r -d '' f; do
    mkdir -p "$DEST/$(dirname "$f")"; cp "$f" "$DEST/$f"
done)

VERSION="$(node -p "require('$SRC/package.json').version" 2>/dev/null || echo unknown)"
cat > "$DEST/BUILD-INFO.txt" <<EOF
Built from: $SOURCE_DESC
Commit: $SHA
ZAC package version: $VERSION
Built at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
This console was built from source by scripts/build-console.sh; it is not the pinned build from scripts/fetch-console.sh.
EOF

echo "✔ Console built from $SOURCE_DESC ($SHA): $(du -sh "$DEST" | cut -f1)"
echo "  Deploy it with: ./deploy-ziti.sh --ssh user@host --update-console"
