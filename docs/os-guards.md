# OS guards: the last line of defense

Even with on-demand browsers and lean flags, memory pressure happens.
These three guards decide **what dies** when it does — and buy you time instead
of a hard crash.

## 1. Swap file (2 GB)

Gives the kernel somewhere to page instead of invoking the OOM killer immediately.
On a 4 GB VPS, 2 GB of swap turns a spike into a slowdown instead of a kill.

```bash
# Skip if you already have swap:
swapon --show | grep -q /swapfile || {
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
}
```

Verify: `swapon --show` and `free -m`.

## 2. earlyoom — kill the browser first, not your agent

The kernel OOM killer picks victims by a heuristic that doesn't know your agent
is more important than a scraper tab. `earlyoom` runs in userspace, reacts
*before* the kernel does, and lets you bias the choice.

```bash
sudo apt install -y earlyoom
sudo systemctl enable --now earlyoom
```

Default config kills the largest process when RAM < 10% and swap < 10%.
That's almost always the browser — which is exactly what you want, because the
browser is disposable and your agent isn't. Tune thresholds in
`/etc/default/earlyoom` if needed (`EARLYOOM_ARGS="-m 5 -s 10"` etc.).

## 3. systemd limits (for browser-as-a-service setups)

If you run a persistent browser service (browserless-style) instead of on-demand,
cage it:

```ini
[Service]
MemoryMax=1G
MemorySwapMax=512M
Restart=on-failure
```

The service gets killed and restarted at the limit instead of taking the box down.
But note: **on-demand (no persistent browser at all) beats a caged persistent
browser.** Use this only for the rare task that genuinely needs a browser every
1–2 minutes.

## Priority order

1. On-demand browsers (nothing persistent to kill in the first place)
2. Lean flags (`--disable-dev-shm-usage`, renderer cap, heap cap)
3. Concurrency pool (`scripts/pool.sh`)
4. Swap + earlyoom (this page)

Each layer catches what the previous one missed.
