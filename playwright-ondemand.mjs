// playwright-ondemand.mjs — the canonical on-demand pattern.
//
// One task = one browser = close() in `finally`.
// Idle state of your machine: ZERO browser processes.
//
// Run:  node playwright-ondemand.mjs https://example.com
// Needs: npm i playwright && npx playwright install chromium

import { chromium } from 'playwright';

// Lean flags for small machines. Annotated reference: docs/chromium-flags.md
export const LEAN_ARGS = [
  '--disable-dev-shm-usage', // /dev/shm is tiny on small VPSes; without this: crashes/OOM
  '--disable-gpu',
  '--disable-software-rasterizer',
  '--disable-extensions',
  '--disable-background-networking',
  '--disable-sync',
  '--disable-translate',
  '--disable-features=Translate,OptimizationHints,MediaRouter,DialMediaRouteProvider',
  '--disable-backgrounding-occluded-windows',
  '--disable-renderer-backgrounding',
  '--renderer-process-limit=2', // default can spawn a dozen renderers
  '--js-flags=--max-old-space-size=384', // cap JS heap per process (MB)
];

const url = process.argv[2] ?? 'https://example.com';

const browser = await chromium.launch({ headless: true, args: LEAN_ARGS });
try {
  // Ephemeral context: cookies/storage isolated, thrown away afterwards.
  // If you need a PERSISTENT login, use launchPersistentContext(profileDir)
  // once per task instead — and still close it in `finally`.
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  try {
    await page.goto(url, { timeout: 60_000 });
    console.log(await page.title());
    // ... your work here. Keep it to 1-2 tabs; page.close() when done.
  } finally {
    await ctx.close();
  }
} finally {
  await browser.close(); // ALWAYS. Even on error. Especially on error.
}
