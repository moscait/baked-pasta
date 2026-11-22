#!/usr/bin/env bash
# Records a captioned demo video of the Access Canvas and the "Set up a service" wizard.
#
# It starts a throwaway OpenZiti controller and router plus the console in Docker, seeds a small
# example network, drives the console with Playwright, and writes an MP4 with captions in a strip
# below the picture. The containers are removed afterwards. Nothing touches a real controller.
#
# Usage: scripts/console-demo/run-demo.sh [--console DIR] [--out FILE] [--dry] [--keep]
#   --console DIR  console build to serve (default: infrastructure/console)
#   --out FILE     video to write (default: access-canvas-demo.mp4 in the current directory)
#   --dry          stop before Apply and save a screenshot per step instead of a video
#   --keep         leave the containers running (console at http://127.0.0.1:8099)
#
# Needs: Docker, Node.js, ffmpeg. Keep the machine awake: if it sleeps mid-run, the recording stalls.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CONSOLE="$REPO/infrastructure/console"
OUT="$PWD/access-canvas-demo.mp4"
MODE=full
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --console) CONSOLE="$(cd "$2" && pwd)"; shift 2 ;;
    --out) OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
    --dry) MODE=dry; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

QUICKSTART=docker.io/openziti/quickstart:2.0.8@sha256:a73d81b46a526a46a677f9f3ee8c2a31c6672935357b08312e99adda94e02bd3
NGINX=docker.io/nginxinc/nginx-unprivileged:1.31.7-alpine3.24@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

for c in docker node ffmpeg; do command -v "$c" >/dev/null || { echo "Missing: $c" >&2; exit 1; }; done
[ -f "$CONSOLE/index.html" ] || { echo "No console build in $CONSOLE" >&2; exit 1; }

WORK="$(mktemp -d)"
cleanup() {
  if [ "$KEEP" = 0 ]; then
    docker rm -f zdemo-ctrl zdemo-web >/dev/null 2>&1 || true
    docker network rm zdemo >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# A random password that only this run knows.
DEMO_ADMIN_PW="Demo-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
export DEMO_ADMIN_PW
if [ "$KEEP" = 1 ]; then echo "admin password: $DEMO_ADMIN_PW"; fi

echo "Starting the demo controller and console..."
docker rm -f zdemo-ctrl zdemo-web >/dev/null 2>&1 || true
docker network create zdemo >/dev/null 2>&1 || true
docker run -d --name zdemo-ctrl --network zdemo -e ZITI_PWD="$DEMO_ADMIN_PW" --entrypoint bash "$QUICKSTART" -c \
  'exec /var/openziti/ziti-bin/ziti edge quickstart --home /persistent --instance-id instance-1 --ctrl-address zdemo-ctrl --router-address zdemo-ctrl --username admin --password "$ZITI_PWD"' >/dev/null
docker run -d --name zdemo-web --network zdemo -p 127.0.0.1:8099:8080 \
  -v "$CONSOLE":/usr/share/nginx/html:ro -v "$HERE/nginx.conf":/etc/nginx/conf.d/default.conf:ro "$NGINX" >/dev/null

echo "Seeding the example network..."
docker cp "$HERE/seed.sh" zdemo-ctrl:/tmp/seed.sh >/dev/null
docker exec -e ZITI_PWD="$DEMO_ADMIN_PW" zdemo-ctrl bash /tmp/seed.sh

echo "Installing Playwright..."
(cd "$HERE" && npm install --silent --no-audit --no-fund && npx --no-install playwright install chromium >/dev/null)

echo "Recording ($MODE)..."
CAFF=(); command -v caffeinate >/dev/null && CAFF=(caffeinate -dimsu)
${CAFF[@]+"${CAFF[@]}"} node "$HERE/record.js" "$MODE" "$WORK"

if [ "$MODE" = dry ]; then
  SHOTS="$PWD/console-demo-screenshots"
  rm -rf "$SHOTS"; cp -R "$WORK/out-dry" "$SHOTS"
  echo "Screenshots: $SHOTS"
else
  node "$HERE/make-video.js" "$WORK/out-full" "$OUT"
  echo "Video: $OUT"
fi
