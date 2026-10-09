# Isolation: contexts, not profiles

You want cron jobs and automation to stop stepping on your main browser sessions.
The instinct is "one Chrome profile per job". Don't.

## Why not one profile per cron job

- 50 profiles = 50× disk (100 MB–1 GB each) and 50× logins to maintain.
- **Profiles don't save RAM. Processes do.** Fifty profiles with on-demand
  browsers still means zero idle processes — but fifty profiles' worth of disk
  and login churn for nothing.

## The right architecture

- **A few persistent profiles, for logins that must survive**: e.g. `main`,
  `social`, `airdrop`. Launched with `launchPersistentContext(profileDir)`
  **once per task**, closed in `finally`.
- **One shared `cron` profile** for all cron jobs that need a persistent login.
- **Ephemeral contexts** (`browser.newContext()`) for everything that doesn't
  need a login. Thrown away after each task. Zero disk cost.

A browser context is free isolation: cookies, `localStorage`, session storage,
and cache are fully separated per context, inside a single browser process.

```js
import { chromium } from 'playwright';
import { LEAN_ARGS } from '../examples/playwright-ondemand.mjs';

// A: task NEEDS a persistent login (e.g. X session)
const ctxA = await chromium.launchPersistentContext('/home/you/.browser-profiles/cron', {
  headless: true,
  args: LEAN_ARGS,
});
try {
  const page = await ctxA.newPage();
  // ... work ...
} finally {
  await ctxA.close(); // closes the whole browser too
}

// B: task needs NO login — ephemeral context, zero disk
const browser = await chromium.launch({ headless: true, args: LEAN_ARGS });
try {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  // ... work ...
  await ctx.close();
} finally {
  await browser.close();
}
```

## Practical rules

1. Automation cron jobs **never** touch the profile you browse with interactively.
   Give them the shared `cron` profile or ephemeral contexts.
2. Need a login in a cron job? Log in **once**, manually, into the `cron` profile.
   Every job reuses it (one at a time, via the pool).
3. Don't fear `launchPersistentContext` — fear *leaving it open*. Per-task launch,
   `close()` in `finally`, same as everything else.
4. Measure: after all tasks idle for 5 minutes, `ps -C chrome --no-headers | wc -l`
   must print `0`. If it doesn't, something isn't closing.
