#!/usr/bin/env bash
# Pin a Baked Pasta Console (BPC) release: look it up on GitHub, download its ziti-console.zip,
# check it against the SHA-256 GitHub recorded for the asset, and rewrite the pin in
# scripts/fetch-console.sh, NOTICE and README.md. Nothing is deployed; review and commit the
# change, then deploy with the usual command.
#
#   scripts/pin-bpc.sh latest        # newest published (non-draft, non-prerelease) release
#   scripts/pin-bpc.sh v0.1.2        # a specific release tag
#   make bpc-pin [VERSION=v0.1.2]    # same; VERSION defaults to latest
#
# Then, for a routable host:  make console-update TARGET=user@host CONSOLE=bpc
# The changed pin makes that replace the installed console; no --force is needed.
#
# Requires curl, jq and unzip. Set GITHUB_TOKEN to avoid the anonymous API rate limit.
set -euo pipefail

REPO="moscait/baked-pasta-console"
ASSET="ziti-console.zip"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FETCH="$ROOT/scripts/fetch-console.sh"

VERSION="${1:-latest}"
case "$VERSION" in
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    latest) ;;
    v[0-9]*.[0-9]*.[0-9]*) ;;
    [0-9]*.[0-9]*.[0-9]*) VERSION="v$VERSION" ;;
    *) echo "Error: expected 'latest' or a release tag like v0.1.2 (got '$VERSION')." >&2; exit 1 ;;
esac

for tool in curl jq unzip; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Error: '$tool' is required." >&2; exit 1; }
done
if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
    sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

api() {
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    # ${auth[@]+...}: bash 3.2 (macOS) treats an empty array as unset under set -u.
    curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$REPO/$1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$VERSION" = latest ]; then
    api releases/latest > "$WORK/release.json"
else
    api "releases/tags/$VERSION" > "$WORK/release.json" ||
        { echo "Error: no published release '$VERSION' in $REPO." >&2; exit 1; }
fi

TAG="$(jq -r '.tag_name' "$WORK/release.json")"
[ "$(jq -r '.draft or .prerelease' "$WORK/release.json")" = false ] ||
    { echo "Error: $TAG is a draft or prerelease; not pinning it." >&2; exit 1; }
URL="$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .browser_download_url' "$WORK/release.json")"
DIGEST="$(jq -r --arg a "$ASSET" '.assets[] | select(.name == $a) | .digest // ""' "$WORK/release.json")"
[ -n "$URL" ] || { echo "Error: release $TAG has no $ASSET asset." >&2; exit 1; }
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Error: unexpected tag name '$TAG'." >&2; exit 1; }
[[ "$URL" == "https://github.com/$REPO/releases/download/$TAG/$ASSET" ]] ||
    { echo "Error: unexpected asset URL '$URL'." >&2; exit 1; }

CURRENT_URL="$(sed -n "s|^ *URL=\"\(https://github.com/$REPO/releases/download/[^\"]*\)\"|\1|p" "$FETCH")"
if [ "$CURRENT_URL" = "$URL" ]; then
    echo "✔ BPC $TAG is already pinned."
    exit 0
fi

echo "▶ Downloading BPC $TAG ..."
curl -fsSL --retry 3 -o "$WORK/$ASSET" "$URL"
SHA="$(sha256 "$WORK/$ASSET")"
if [ -n "$DIGEST" ]; then
    [ "sha256:$SHA" = "$DIGEST" ] || {
        echo "Error: checksum mismatch: GitHub records $DIGEST, the download is sha256:$SHA." >&2
        exit 1
    }
else
    echo "Warning: GitHub has no recorded digest for this asset; pinning the downloaded file's checksum." >&2
fi

unzip -q "$WORK/$ASSET" -d "$WORK/console"
[ -f "$WORK/console/index.html" ] || { echo "Error: the archive has no index.html at its root." >&2; exit 1; }
grep -q '/zac/' "$WORK/console/index.html" ||
    { echo "Error: this build was not made for /zac/ (npm run package:zac)." >&2; exit 1; }

# The tag may be annotated; resolve it to the commit for the record.
REF="$(api "git/ref/tags/$TAG")"
COMMIT="$(jq -r '.object.sha' <<< "$REF")"
if [ "$(jq -r '.object.type' <<< "$REF")" = tag ]; then
    COMMIT="$(api "git/tags/$COMMIT" | jq -r '.object.sha')"
fi
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Error: could not resolve $TAG to a commit." >&2; exit 1; }
SHORT="${COMMIT:0:7}"
VER="${TAG#v}"

# Rewrite the pin. Each pattern matches exactly one line; check that it did.
OLD_SHA="$(awk -v u="$CURRENT_URL" 'found && /SHA256="/ { sub(/.*SHA256="/, ""); sub(/".*/, ""); print; exit } index($0, u) { found = 1 }' "$FETCH")"
[[ "$OLD_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "Error: could not find the current BPC pin in $FETCH." >&2; exit 1; }

replace() { # file, sed expression, description
    local before
    before="$(cksum < "$1")"
    sed -i.bak "$2" "$1" && rm -f "$1.bak"
    [ "$(cksum < "$1")" != "$before" ] || { echo "Error: did not update $3 in ${1#"$ROOT"/}." >&2; exit 1; }
}
replace "$FETCH" "s|# Release v[0-9.]* of https://github.com/$REPO (tag at [0-9a-f]*)|# Release $TAG of https://github.com/$REPO (tag at $SHORT)|" "the release comment"
replace "$FETCH" "s|$CURRENT_URL|$URL|" "the URL"
replace "$FETCH" "s|$OLD_SHA|$SHA|" "the SHA-256"
replace "$FETCH" "s|LABEL=\"Baked Pasta Console [0-9.]*\"|LABEL=\"Baked Pasta Console $VER\"|" "the label"
replace "$ROOT/NOTICE" "s|release v[0-9.]*, $ASSET,|release $TAG, $ASSET,|; s|$OLD_SHA|$SHA|" "the BPC entry"
replace "$ROOT/README.md" "s|\[Release [0-9.]*\](https://github.com/$REPO/releases/tag/v[0-9.]*)|[Release $VER](https://github.com/$REPO/releases/tag/$TAG)|" "the BPC release link"

echo "✔ Pinned BPC $TAG (commit $SHORT, sha256 $SHA)."
echo "  Changed: scripts/fetch-console.sh, NOTICE, README.md. Review, commit, then deploy, e.g.:"
echo "  make console-update TARGET=user@host CONSOLE=bpc"
