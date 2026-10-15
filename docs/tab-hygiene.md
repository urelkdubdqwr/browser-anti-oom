# Tab hygiene — the leak flags can't fix

Lean Chromium flags cap memory *per tab*. They do nothing about the leak that
actually takes boxes down: **tabs that never get closed**.

## The measured case

One persistent daemon on a 4 GB VPS, left to its own devices:

- cron jobs open tabs, finish, and forget to close them (browser automation
  helpers especially love to leave the last tab open)
- each leaked tab keeps its own **renderer process** alive — a full Chrome
  process, not just a handle
- 57 leaked tabs on one daemon = **815 MB RSS** of pure zombie renderers
- meanwhile other crons spawn their own browsers → swappiness climbs → the
  OOM killer arrives → and it doesn't pick the tab you wanted it to

Symptom signature: an unrelated job dies with `Target crashed` (the renderer
was killed), while `free -h` looks "fine" because swap is absorbing the creep.

## The fix: sweep on a schedule

`scripts/tab-sweep.py` is 70 lines of CDP API calls:

```bash
# every daemon, keep 2 newest tabs (cron every 30 min is plenty)
*/30 * * * * /usr/bin/python3 scripts/tab-sweep.py >> /tmp/tab-sweep.log 2>&1

# single daemon, keep only the newest
scripts/tab-sweep.py --port 9222 --keep 1

# report only
scripts/tab-sweep.py --list
```

Rules baked into the script:

1. **Never close the last page.** CDP lets you close it — which kills the whole
   browser. `keep` is clamped to ≥ 1 for this reason.
2. **Oldest first.** `/json/list` returns pages oldest-first (documented
   behavior via target ordering); sweep trims the head, keeps the head.
3. **Unreachable daemon = skip, don't fail.** A dead daemon needs a guard to
   relaunch it (`chrome-guard.sh`), not a sweep error.

## Impact order, revised

1. on-demand (zero idle browsers) — for any task WITHOUT a login state
2. tab hygiene (`tab-sweep.py`) — the moment you run ANY persistent daemon
3. lean flags — caps per-tab cost
4. race-safe launcher (`browser-daemon.sh`) — one Chrome per profile, ever
5. OS guards — last line of defense

If you run one persistent daemon and adopt only one item from this whole repo,
make it the sweep. It's the difference between "stable for months" and
"mysterious 3 AM renderer crashes".
