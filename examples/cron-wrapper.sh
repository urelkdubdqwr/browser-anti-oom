#!/usr/bin/env bash
# cron-wrapper.sh — run any browser task under the global slot pool.
#
# This is the piece that stops 50 cron jobs from spawning 50 browsers
# at minute :00 and OOM-ing the box.
#
# Usage: ./cron-wrapper.sh <task-script> [args...]
# Example crontab (note the SPREAD minutes — never all at :00):
#   7  * * * * /path/to/cron-wrapper.sh /path/to/task-a.sh
#   23 * * * * /path/to/cron-wrapper.sh /path/to/task-b.sh
#   41 * * * * /path/to/cron-wrapper.sh /path/to/task-c.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/pool.sh
source "$SCRIPT_DIR/../scripts/pool.sh"

TASK="${1:?usage: cron-wrapper.sh <task-script> [args...]}"
shift

echo "[pool] waiting for a browser slot (max $BROWSER_POOL_SLOTS concurrent)..."
wait_for_slot
echo "[pool] slot acquired, running task."

# The task itself must follow the on-demand rule:
# spawn its browser, close it in `finally`, leave zero processes behind.
exec "$TASK" "$@"
# Slot auto-releases when this shell exits — even on kill -9.
