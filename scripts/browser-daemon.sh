#!/bin/bash
# browser-daemon.sh — launch ONE persistent headless Chrome daemon per profile,
# idempotently and race-safely.
#
# Usage: browser-daemon.sh <name> <port> [user-data-dir]
#   BROWSER_DIR_ROOT   default ~/.cache/browser-daemons
#   BROWSER_BIN        default: newest playwright chromium, else google-chrome
#   DISPLAY_NUM        default :99 (one shared Xvfb for all daemons)
#
# Why this exists (learned the hard way on a 4 GB VPS):
#   * A second Chrome on the SAME profile doubles RAM instantly. Cron jobs
#     start at :00 together, so the launcher MUST be idempotent + race-safe.
#   * Never `rm Singleton*`. Deleting locks of a running profile is exactly what
#     lets duplicate instances start side-by-side.
#   * If the root process is alive but CDP is not, WAIT for it to bind — never
#     stack another Chrome on top.
# Exit 0 = CDP is up (by us or by someone else).
set -e

NAME="$1"; PORT="$2"; DIR="${3:-}"
[ -z "$NAME" ] || [ -z "$PORT" ] && { echo "usage: $0 <name> <port> [user-data-dir]"; exit 1; }
ROOT="${BROWSER_DIR_ROOT:-$HOME/.cache/browser-daemons}"
DIR="${DIR:-$ROOT/$NAME}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"

CHROME="${BROWSER_BIN:-}"
if [ -z "$CHROME" ]; then
  CHROME=$(ls -d "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | tail -1)
  [ -z "$CHROME" ] && CHROME=$(command -v google-chrome || command -v chromium || true)
fi
[ -z "$CHROME" ] && { echo "no chrome binary"; exit 1; }

cdp_up() { curl -s -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; }

# 1. Fast path — already healthy, never stack a second instance.
if cdp_up; then echo "$NAME:$PORT ALREADY READY"; exit 0; fi

# 2. Per-profile flock: check->launch is one critical section.
LOCK="${TMPDIR:-/tmp}/.browser-daemon-$NAME.lock"
exec 9>"$LOCK"
flock -w 60 9 || { echo "$NAME:$PORT BUSY (lock held >60s)"; exit 1; }

# 3. Re-check after the lock — another caller may have just launched it.
if cdp_up; then echo "$NAME:$PORT ALREADY READY (other caller launched)"; exit 0; fi

# 4. Process alive but CDP dead? Wait for it, don't duplicate it.
if pgrep -f -- "--user-data-dir=$DIR" >/dev/null 2>&1; then
  for _ in $(seq 1 20); do
    cdp_up && { echo "$NAME:$PORT RECOVERED READY"; exit 0; }
    sleep 1
  done
  echo "$NAME:$PORT CDP-DEAD-BUT-PROCESS-ALIVE (no launch; retry later)"
  exit 1
fi

# 5. Shared Xvfb — one display for every daemon, not one per job.
pgrep -f "[X]vfb :$DISPLAY_NUM" >/dev/null 2>&1 || { Xvfb ":$DISPLAY_NUM" -screen 0 1280x900x24 >/dev/null 2>&1 & disown; sleep 1; }

# 6. Lean flags (see docs/chromium-flags.md). No `rm Singleton*`.
DISPLAY=":$DISPLAY_NUM" nohup "$CHROME" \
  --user-data-dir="$DIR" \
  --no-sandbox --no-first-run --no-default-browser-check \
  --disable-gpu --disable-software-rasterizer \
  --disable-dev-shm-usage \
  --disable-background-networking --disable-sync --disable-translate \
  --disable-backgrounding-occluded-windows --disable-renderer-backgrounding \
  --remote-debugging-port="$PORT" \
  --window-size=1280,900 \
  --disk-cache-size=52428800 \
  --disable-features=Translate,OptimizationHints,MediaRouter,DialMediaRouteProvider,ThirdPartyStoragePartitioning,ThirdPartyCookieDeprecationTrial,TrackingProtection3pcd \
  --renderer-process-limit=2 \
  --js-flags=--max-old-space-size=384 \
  about:blank >/dev/null 2>&1 </dev/null & disown

for _ in $(seq 1 20); do
  cdp_up && { echo "$NAME:$PORT LAUNCHED READY"; exit 0; }
  sleep 1
done
echo "$NAME:$PORT FAIL after 20s"
exit 1
