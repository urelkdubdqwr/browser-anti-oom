#!/usr/bin/env bash
# pool.sh — a tiny global slot pool so N cron jobs never spawn N browsers.
#
# Usage:
#   source /path/to/pool.sh
#   until acquire_slot; do sleep 5; done
#   # ... spawn browser, do work, browser.close() ...
#   # slot releases automatically when this shell exits (even on kill -9)
#
# Config via env:
#   BROWSER_POOL_DIR    default /tmp/browser-pool
#   BROWSER_POOL_SLOTS  default 2

BROWSER_POOL_DIR="${BROWSER_POOL_DIR:-/tmp/browser-pool}"
BROWSER_POOL_SLOTS="${BROWSER_POOL_SLOTS:-2}"

# Try to grab one slot. Returns 0 on success, 1 if all slots are busy.
# On success, the lock is held on an open fd that dies with the shell.
acquire_slot() {
  mkdir -p "$BROWSER_POOL_DIR"
  local i lock fd
  for i in $(seq 1 "$BROWSER_POOL_SLOTS"); do
    lock="$BROWSER_POOL_DIR/slot-$i.lock"
    # shellcheck disable=SC2086
    exec {fd}>"$lock" || continue
    if flock -n "$fd"; then
      # Keep the fd open in the caller's shell; closing it releases the slot.
      eval "BROWSER_POOL_FD_$i=$fd"
      return 0
    fi
    eval "exec $fd>&-"
  done
  return 1
}

# Block until a slot is free.
wait_for_slot() {
  until acquire_slot; do sleep 5; done
}
