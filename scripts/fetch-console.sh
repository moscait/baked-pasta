#!/usr/bin/env bash
# Install the admin console for the sandbox or the routable infrastructure. Two consoles are
# supported, and both are served at the same paths:
#
#   zac  OpenZiti Admin Console (default). A pinned build is downloaded and its SHA-256 verified.
#   bpc  Baked Pasta Console, a ZAC-compatible console with the Access Canvas and guided service
#        wizards. Until it has a published release, build it from a local checkout (BPC_DIR) or
#        install an archive you built (BPC_ZIP).
#
#   scripts/fetch-console.sh sandbox                  # -> menu/zac/               (stock upstream ZAC)
#   scripts/fetch-console.sh infrastructure           # -> infrastructure/console/ (ZAC + Access Canvas)
#   scripts/fetch-console.sh <target> --console bpc   # Baked Pasta Console instead
#   scripts/fetch-console.sh <target> --force         # replace an existing console, e.g. a custom build
#
#   BPC_DIR=../baked-pasta-console   build BPC from that checkout (npm, Node 20+), then install it
#   BPC_ZIP=path/to/console.zip      install a BPC archive built with `npm run package:zac`
#   BAKED_PASTA_CONSOLE=bpc          default for --console
#
# Each install writes .console-source, recording which console it is. A console of the requested
# kind is left alone unless --force is given (or a BPC source is passed), so a ZAC built with
# scripts/build-console.sh is never overwritten by accident; switching between zac and bpc
# replaces it. Called automatically by `make sandbox-up` and by deploy-ziti.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { sed -n '2,24p' "$0"; }

TARGET=""
CONSOLE="${BAKED_PASTA_CONSOLE:-zac}"
FORCE=false
while [ $# -gt 0 ]; do
    case "$1" in
        sandbox|infrastructure) TARGET="$1"; shift ;;
        --console) CONSOLE="${2:-}"; shift 2 ;;
        --console=*) CONSOLE="${1#*=}"; shift ;;
        --force) FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument '$1'" >&2; usage >&2; exit 1 ;;
    esac
done
[ -n "$TARGET" ] || { usage >&2; exit 1; }

case "$TARGET" in
    sandbox) DEST="$ROOT/menu/zac" ;;
    infrastructure) DEST="$ROOT/infrastructure/console" ;;
esac
REL_DEST="${DEST#"$ROOT"/}"

# Pinned downloads. URL and SHA-256 must change together.
case "$CONSOLE:$TARGET" in
    zac:sandbox)
        # Unmodified upstream release: app-ziti-console-v4.8.0, ziti-console.zip
        URL="https://github.com/openziti/ziti-console/releases/download/app-ziti-console-v4.8.0/ziti-console.zip"
        SHA256="359f65466ffea40fd1ec58a502323b5e045d266d586ff14c099f01d3fd681a72"
        LABEL="OpenZiti Admin Console 4.8.0"
        ;;
    zac:infrastructure)
        # Build of https://github.com/moscait/ziti-console (main @ 35f72f9, ZAC 4.8.1) that adds
        # the Access Canvas view. Published as a release asset of this repository; see NOTICE.
        URL="https://github.com/moscait/baked-pasta/releases/download/console-4.8.1-access-canvas-35f72f9/ziti-console-4.8.1-access-canvas-35f72f9.zip"
        SHA256="0e640a8433c79f206c4e2d503947b4a1978ef12cd9818681ae6f19315b914bac"
        LABEL="OpenZiti Admin Console 4.8.1 + Access Canvas (35f72f9)"
        ;;
    bpc:*)
        # Baked Pasta Console has no published release yet. When it does, pin it here (one build
        # serves both targets: it is built for /zac/ and the infrastructure serves /zac/ too).
        URL=""
        SHA256=""
        LABEL="Baked Pasta Console"
        ;;
    *)
        echo "Unknown console '$CONSOLE' (expected: zac or bpc)" >&2
        exit 1
        ;;
esac

# What is installed now: the recorded console, "zac" for a console without a record (the pinned
# ZAC from before records existed, or a build from scripts/build-console.sh), or nothing.
INSTALLED=""
if [ -f "$DEST/index.html" ]; then
    [ -f "$DEST/.console-source" ] && INSTALLED="$(sed -n 's/^console=//p' "$DEST/.console-source" | head -n 1)"
    INSTALLED="${INSTALLED:-zac}"
fi

BPC_SOURCE_GIVEN=false
[ "$CONSOLE" = bpc ] && { [ -n "${BPC_DIR:-}" ] || [ -n "${BPC_ZIP:-}" ]; } && BPC_SOURCE_GIVEN=true

if [ "$INSTALLED" = "$CONSOLE" ] && [ "$FORCE" = false ] && [ "$BPC_SOURCE_GIVEN" = false ]; then
    echo "✔ $(echo "$CONSOLE" | tr '[:lower:]' '[:upper:]') already present in $REL_DEST (use --force to replace it)."
    exit 0
fi

if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi
need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' is required to $2." >&2; exit 1; }; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/console"

if [ "$CONSOLE" = bpc ] && [ -n "${BPC_DIR:-}" ]; then
    need npm "build the Baked Pasta Console"
    BPC_DIR="$(cd "$BPC_DIR" && pwd)"
    [ -f "$BPC_DIR/package.json" ] || { echo "Error: $BPC_DIR has no package.json." >&2; exit 1; }
    echo "▶ Building the Baked Pasta Console from $BPC_DIR ..."
    if [ ! -d "$BPC_DIR/node_modules" ]; then
        (cd "$BPC_DIR" && npm ci --no-audit --no-fund)
    fi
    (cd "$BPC_DIR" && npm run --silent build:zac)
    cp -R "$BPC_DIR/dist/." "$WORK/console/"
    VERSION="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$BPC_DIR/package.json" | head -n 1)"
    COMMIT="$(git -C "$BPC_DIR" rev-parse --short HEAD 2>/dev/null || echo "not a git checkout")"
    DETAIL="local build of version ${VERSION:-unknown} (commit: $COMMIT)"
else
    need unzip "unpack the console"
    if [ "$CONSOLE" = bpc ] && [ -n "${BPC_ZIP:-}" ]; then
        [ -f "$BPC_ZIP" ] || { echo "Error: BPC_ZIP '$BPC_ZIP' does not exist." >&2; exit 1; }
        cp "$BPC_ZIP" "$WORK/console.zip"
        DETAIL="local archive, sha256 $(sha256 "$WORK/console.zip")"
        echo "▶ Installing the Baked Pasta Console from $BPC_ZIP (not checksum-pinned) ..."
    elif [ -n "$URL" ]; then
        need curl "download the console"
        echo "▶ Downloading $LABEL for the $TARGET ..."
        curl -fsSL --retry 3 -o "$WORK/console.zip" "$URL"
        ACTUAL="$(sha256 "$WORK/console.zip")"
        if [ "$ACTUAL" != "$SHA256" ]; then
            echo "Error: checksum mismatch for $URL" >&2
            echo "  expected $SHA256" >&2
            echo "  got      $ACTUAL" >&2
            exit 1
        fi
        DETAIL="$URL, sha256 $SHA256 (verified)"
    else
        echo "Error: the Baked Pasta Console (BPC) has no published release yet." >&2
        echo "  Build it from a checkout:  BPC_DIR=../baked-pasta-console $0 $TARGET --console bpc" >&2
        echo "  or install an archive:     BPC_ZIP=path/to/baked-pasta-console.zip $0 $TARGET --console bpc" >&2
        exit 1
    fi
    unzip -q "$WORK/console.zip" -d "$WORK/console"
fi

[ -f "$WORK/console/index.html" ] || { echo "Error: the console has no index.html at its root." >&2; exit 1; }
if [ "$CONSOLE" = bpc ] && ! grep -q '/zac/' "$WORK/console/index.html"; then
    echo "Error: this BPC build was not made for /zac/. Build it with 'npm run package:zac'." >&2
    exit 1
fi
printf 'console=%s\nname=%s\nsource=%s\n' "$CONSOLE" "$LABEL" "$DETAIL" > "$WORK/console/.console-source"

# Replace the destination only after a complete, verified unpack.
mkdir -p "$(dirname "$DEST")"
if [ -d "$DEST" ]; then
    mv "$DEST" "$WORK/previous"
fi
mv "$WORK/console" "$DEST"
echo "✔ $LABEL installed in $REL_DEST."
