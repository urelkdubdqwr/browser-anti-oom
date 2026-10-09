# Chromium flags that actually save RAM

These are tuned for **headless agent workloads on small VPSes** (2–8 GB RAM).
Copy the whole block into your launcher; the notes explain what each one buys you
and when to drop it.

```text
--headless=new
--disable-dev-shm-usage
--disable-gpu --disable-software-rasterizer
--disable-extensions
--disable-background-networking --disable-sync --disable-translate
--disable-features=Translate,OptimizationHints,MediaRouter,DialMediaRouteProvider
--disable-backgrounding-occluded-windows --disable-renderer-backgrounding
--renderer-process-limit=2
--js-flags=--max-old-space-size=384
```

## Flag by flag

| Flag | Why it matters |
|---|---|
| `--headless=new` | No X server, no compositor. The single biggest saver vs. headed mode. |
| `--disable-dev-shm-usage` | **The #1 crash fix on small VPSes.** `/dev/shm` is often 64 MB in Docker/small VMs; Chromium renders into shared memory and dies without this. Non-negotiable. |
| `--disable-gpu`, `--disable-software-rasterizer` | No GPU on a VPS; the software rasterizer still burns CPU/RAM. Headless rendering doesn't need either for DOM work. |
| `--disable-extensions` | Extensions are background processes you didn't ask for. |
| `--disable-background-networking` | Stops component updates, telemetry pings, and other background chatter. |
| `--disable-sync`, `--disable-translate` | Kills two more background services. |
| `--disable-features=Translate,OptimizationHints,MediaRouter,DialMediaRouteProvider` | Same idea, feature-flag level: no translate bubble, no on-device ML hints, no Chromecast discovery daemons. |
| `--disable-backgrounding-occluded-windows`, `--disable-renderer-backgrounding` | In headless mode "occluded" heuristics misfire; these keep renderers from being throttled into weird states mid-task. |
| `--renderer-process-limit=2` | Chromium defaults to roughly one renderer per core — and spawns more per site. Cap it. Two is plenty for 1–2 tabs. |
| `--js-flags=--max-old-space-size=384` | Caps the V8 heap per process at 384 MB instead of letting a leaky page grow unbounded. Tune 256–512 to taste. |

## Situational flags

- `--no-sandbox --disable-setuid-sandbox` — **required** when running as root or in
  Docker (Chrome refuses to start otherwise). It's a security trade-off: fine for
  agent scraping of known sites; don't browse hostile content as root.
- `--single-process` — the most RAM-frugal mode, but one tab crash kills everything.
  Prefer `--renderer-process-limit=2` unless you're truly desperate.
- `--user-data-dir=/tmp/...` — always point at a throwaway dir for one-shot tasks,
  and delete it afterwards. Never reuse `/tmp` dirs across tasks.
- `--virtual-time-budget=15000` — fast-forwards virtual time; great for
  `--dump-dom` one-shots so pages "settle" without a real 15 s wait.
- `--disable-images` — if you only need the DOM/text, skipping images saves
  both RAM and bandwidth. (Can break lazy-load-dependent layouts; test.)

## What NOT to do

- Don't open 10 tabs "because it's one browser". Each tab is renderer processes.
  One task, 1–2 tabs, `page.close()` when done.
- Don't copy-paste a 40-flag "ultimate" list from a blog. Every flag is a
  behavior change; the list above is the minimal set with measured impact.
- Don't run with `--no-sandbox` as a non-root user "just in case". Keep the
  sandbox when you can.
