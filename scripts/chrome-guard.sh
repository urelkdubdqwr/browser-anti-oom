#!/bin/bash
# chrome-guard.sh — keep N persistent daemons up; relaunch only genuinely-dead
# ones. Wire it to a systemd timer or cron every 3 minutes and forget it.
#
# Usage: chrome-guard.sh "name:port" ["name:port" ...]
#   chrome-guard.sh "main:9222" "scrape:9223"
#
# Design: one transient CDP check failure is NOT dead — retry once after 1s
# before declaring death, otherwise a busybox blip triggers a relaunch storm.
LOG="${CHROME_GUARD_LOG:-/dev/stdout}"
log() { echo "[$(date -u +%H:%M:%S)] $1" >> "$LOG"; }
cdp_up() { curl -s -m 2 "http://127.0.0.1:$port/json/version" >/dev/null 2>&1; }

for spec in "$@"; do
  IFS=':' read -r name port <<< "$spec"
  [ -z "$name" ] || [ -z "$port" ] && { echo "bad spec: $spec"; continue; }
  if cdp_up; then log "$name:$port READY"; continue; fi
  log "$name:$port RECOVERING (first check failed, retrying)"
  sleep 1
  cdp_up && { log "$name:$port READY (recovered on retry)"; continue; }
  out="$("$(dirname "$0")"/browser-daemon.sh "$name" "$port" 2>&1)" && rc=0 || rc=$?
  if [ $rc -eq 0 ]; then log "$name:$port LAUNCHED :: $out"; else log "$name:$port STILL DOWN :: $out"; fi
done
