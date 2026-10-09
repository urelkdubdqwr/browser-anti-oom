#!/usr/bin/env bash
# browser-run.sh — one-shot headless Chromium, anti-OOM edition.
#
# Principle: the browser exists ONLY while the task runs.
#   spawn -> dump DOM -> kill on timeout -> delete profile -> exit.
# Idle = zero chrome processes.
#
# Usage: ./browser-run.sh <url> [timeout-seconds]
# Example: ./browser-run.sh https://example.com 60
#
# Needs one of: chromium, chromium-browser, google-chrome on PATH.
set -u

URL="${1:?usage: browser-run.sh <url> [timeout-seconds]}"
TIMEOUT="${2:-120}"
PROFILE="$(mktemp -d /tmp/chrome-ondemand.XXXXXX)"

CHROME_BIN="$(command -v chromium || command -v chromium-browser || command -v google-chrome || echo chromium)"

cleanup() { rm -rf "$PROFILE"; }
trap cleanup EXIT INT TERM

"$CHROME_BIN" \
  --headless=new \
  --disable-dev-shm-usage \
  --disable-gpu --disable-software-rasterizer \
  --disable-extensions \
  --disable-background-networking \
  --disable-sync --disable-translate \
  --disable-features=Translate,OptimizationHints,MediaRouter,DialMediaRouteProvider \
  --disable-backgrounding-occluded-windows --disable-renderer-backgrounding \
  --renderer-process-limit=2 \
  --js-flags=--max-old-space-size=384 \
  --user-data-dir="$PROFILE" \
  --virtual-time-budget=15000 \
  --dump-dom "$URL" 2>/dev/null | head -c 200000 &

CPID=$!
# Watchdog: force-kill if we exceed the timeout.
( sleep "$TIMEOUT"; kill -9 "$CPID" 2>/dev/null ) &
WDOG=$!
wait "$CPID" 2>/dev/null
kill "$WDOG" 2>/dev/null

# NOTE on --no-sandbox: add "--no-sandbox --disable-setuid-sandbox" if you run
# as root or inside Docker. It's a security trade-off; fine for agent scraping,
# not for browsing untrusted content as a privileged user.
