**[urelkdubdqwr](https://github.com/urelkdubdqwr)** · [website](https://studiopinggirkasur.xyz/)

<img src="assets/header.svg" alt="browser-anti-oom — on-demand headless browser recipe: stop OOM kills on small VPSes" width="100%">

**Stop letting headless browsers eat your VPS — keep a browser alive only while a task runs, and sweep the leaked tabs when it doesn't.**

## What it is

A small kit of shell + Python scripts for running Chromium as an on-demand tool
for AI agents, cron jobs, and scrapers on a 2–8 GB VPS. The rule the whole repo
is built around: a browser should exist only while a task is running — spawn it,
do the work, close it in `finally`. Idle means `ps -C chrome` prints **0**.

The enemy is the leak you don't notice: one tab you forgot to close = one live
renderer, and 50 cron jobs firing at minute `:00` all spawning a browser = a
stampede that ends in a 3 AM OOM kill. Everything here is a guard against one
of those two. *Hemat RAM, no drama.*

## How it works

![browser-anti-oom architecture](assets/ecosystem.png)

- **One task, one browser.** `scripts/browser-run.sh` dumps a page's DOM with a
  throwaway headless Chromium, watchdog-kills it on timeout, and deletes the
  ephemeral profile on exit.
- **The slot pool caps concurrency.** `scripts/pool.sh` is a 20-line `flock`
  pool (default 2 slots) — the rest queue instead of spawning. Slots release
  automatically when the shell exits, even if the process gets `kill -9`'d.
- **Lean flags cap the per-tab cost.** `--disable-dev-shm-usage`,
  `--renderer-process-limit=2`, `--js-flags=--max-old-space-size=384`, headless,
  no GPU, no extensions. Every flag explained in
  [`docs/chromium-flags.md`](docs/chromium-flags.md).
- **Persistent daemons need a tab sweep.** Flags cap memory per tab; they do
  nothing about tabs that never close. Measured on a 4 GB VPS: 57 leaked tabs on
  one daemon = **815 MB** of zombie renderers, and unrelated jobs start dying
  with `Target crashed`. `scripts/tab-sweep.py` on a 30-min cron closes the
  oldest tabs over `keep=N` (default 2) — and never the last page, because that
  kills the browser. ([`docs/tab-hygiene.md`](docs/tab-hygiene.md))
- **Race-safe relaunch, or you get two Chromes on one profile.**
  `scripts/browser-daemon.sh` is idempotent: per-profile `flock`, a re-check
  after the lock, and if the process is alive but CDP isn't bound it *waits*
  for it — it never stacks a second instance and never `rm Singleton*`.
  `scripts/chrome-guard.sh` runs every 3 min and only relaunches genuinely-dead
  daemons, retrying once after 1 s first so a transient blip doesn't trigger a
  relaunch storm.
- **OS guards are the last line.** Swap file + `earlyoom` so that if memory
  still runs out, the *browser* dies — not your agent.
  ([`docs/os-guards.md`](docs/os-guards.md))

Impact order: on-demand (1) > tab hygiene, the moment you run any daemon (2) >
lean flags (2) > concurrency cap (3) > OS guards (4).

## Quickstart

```bash
git clone https://github.com/urelkdubdqwr/browser-anti-oom.git
cd browser-anti-oom

# One-shot: fetch a page's DOM with a throwaway headless Chromium,
# auto-killed on timeout, profile cleaned up afterwards.
./scripts/browser-run.sh https://example.com 60
```

Needs `chromium`, `chromium-browser`, or `google-chrome` on `PATH`.

Running a persistent daemon instead (the case where tasks share a login
session)? Launch it, sweep it, then let the guard babysit it:

```bash
./scripts/browser-daemon.sh main 9222          # idempotent: exit 0 = CDP is up
python3 scripts/tab-sweep.py --port 9222 --keep 2
./scripts/chrome-guard.sh "main:9222"          # wire to cron/systemd every 3 min
```

The canonical in-process pattern (Playwright) — `close()` in `finally`, always:

```js
import { chromium } from 'playwright';
import { LEAN_ARGS } from './examples/playwright-ondemand.mjs';

const browser = await chromium.launch({ headless: true, args: LEAN_ARGS });
try {
  const ctx = await browser.newContext(); // ephemeral — no persistent profile
  const page = await ctx.newPage();
  await page.goto(url, { timeout: 60_000 });
  // ... do the work ...
  await ctx.close();
} finally {
  await browser.close(); // ALWAYS. Even on error. Especially on error.
}
```

Puppeteer is the same shape:
`puppeteer.launch({ args })` … `finally { await browser.close() }`.
A full example lives in [`examples/playwright-ondemand.mjs`](examples/playwright-ondemand.mjs),
and [`examples/cron-wrapper.sh`](examples/cron-wrapper.sh) shows how to compose
`pool.sh` with your task so 50 cron jobs never stampede the box.

Two rules worth keeping even if you adopt nothing else: **spread cron
schedules** (`:07`, `:23`, `:41` — not 50 jobs at `:00`), and **measure first**:

```bash
ps -o rss,comm -C chrome | awk 'NR>1{sum+=$2} END{print sum/1024 " MB"}'
```

## What's inside

| Path | What it is |
|---|---|
| `scripts/browser-run.sh` | One-shot headless Chromium: dumps DOM, watchdog-kills on timeout, ephemeral profile in `/tmp`, self-cleaning. |
| `scripts/browser-daemon.sh` | Persistent-daemon launcher: idempotent + race-safe (flock per profile). Never stacks a second Chrome on one profile, never `rm Singleton*`. |
| `scripts/tab-sweep.py` | Close leaked tabs on persistent daemons via CDP, keep N newest. The fix for tab-leak renderers (see `docs/tab-hygiene.md`). |
| `scripts/chrome-guard.sh` | Every-3-min health check: revive genuinely-dead daemons, one retry before declaring death (no relaunch storms). |
| `scripts/pool.sh` | `source`-able slot pool (`acquire_slot`, default 2 slots) built on `flock`. Slots release automatically on shell exit. |
| `examples/playwright-ondemand.mjs` | The canonical Playwright pattern: launch → work → `close()` in `finally`. |
| `examples/cron-wrapper.sh` | Compose `pool.sh` + your task so 50 cron jobs never stampede the box. |
| `docs/chromium-flags.md` | Every flag explained: what it does, why it saves RAM, when to skip it. |
| `docs/tab-hygiene.md` | The leak flags can't fix: tab-leak renderers, sweep scheduling, impact order for daemons. |
| `docs/os-guards.md` | Swap file, `earlyoom`, and systemd `MemoryMax` — the last line of defense. |
| `docs/profile-strategy.md` | Contexts vs. profiles: how to isolate logins without 50 disk-hungry profiles. |

Who it's for: agent operators, cron farmers, and scraper authors on small VPSes
who are tired of babysitting `chrome --headless` processes.

## License

MIT — see [LICENSE](LICENSE). Steal it, ship it, stay OOM-free.

*Worked from the edge of the bed. → [studiopinggirkasur.xyz](https://studiopinggirkasur.xyz/)*
