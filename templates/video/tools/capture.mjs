// Capture live article pages at phone width for the headline cards (src/lib/Headline.tsx crops these).
// Usage: node tools/capture.mjs [name...]
//   -> <media>/app/public/captures/<name>.png and research/captures.json (URL, capture time, SHA-256 of the PNG)
// Cookie and consent banners are hidden by CSS only; nothing is clicked or accepted.
import { createRequire } from "module";
import { createHash } from "crypto";
import fs from "fs";
import os from "os";
import path from "path";
import { mediaRoot } from "./media-root.mjs";

const require = createRequire(import.meta.url);
const { chromium } = require(path.join(os.homedir(), ".npm-global/node_modules/playwright"));
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const media = mediaRoot(root); // one resolver for every tool: AOS_VIDEO_MEDIA_ROOT, film folder, worktrees
const out = path.join(media, "app/public/captures");
fs.mkdirSync(out, { recursive: true });

// {"name": "https://..."} or {"name": {"url": "https://...", "anchor": "exact sentence"}}: with an anchor the page is
// scrolled so that sentence sits mid-screen, and its line boxes (capture pixels) go to the ledger for crops and marks
const PAGES = JSON.parse(fs.readFileSync(path.join(root, "research/capture-pages.json"), "utf8"));
const SCALE = 2.6;
const HIDE = `[id*="cookie" i],[class*="cookie" i],[id*="consent" i],[class*="consent" i],[class*="paywall" i],
  [id*="onetrust" i],.fc-consent-root,.fc-dialog-overlay,[role="dialog"],[aria-modal="true"],[class*="fc-" i],[class*="newsletter" i],[class*="modal" i],[class*="overlay" i],[class*="sticky" i],iframe
  { display: none !important; } html, body { overflow: visible !important; }`;

const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(PAGES);
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 412, height: 1100 }, deviceScaleFactor: SCALE, colorScheme: "light",
  userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36" });
const ledgerPath = path.join(root, "research/captures.json");
const ledger = fs.existsSync(ledgerPath) ? JSON.parse(fs.readFileSync(ledgerPath, "utf8")) : {};
for (const name of names) {
  const spec = typeof PAGES[name] === "string" ? { url: PAGES[name] } : PAGES[name];
  const page = await ctx.newPage();
  await page.goto(spec.url, { waitUntil: "load", timeout: 90000 });
  await page.waitForTimeout(9000);
  await page.mouse.wheel(0, 300);  // lazy-loaded heroes render once the page has scrolled
  await page.waitForTimeout(1500);
  await page.mouse.wheel(0, -300);
  await page.waitForTimeout(800);
  await page.addStyleTag({ content: HIDE });
  // remove whatever still floats over the article (fixed or sticky layers, consent walls); nothing is clicked
  await page.evaluate(() => {
    for (const el of [...document.querySelectorAll("body *")]) {
      const cs = getComputedStyle(el);
      if ((cs.position === "fixed" || cs.position === "sticky") && el.getBoundingClientRect().height > 40) el.remove();
    }
    document.documentElement.style.filter = "none";
    document.body.style.filter = "none";
  });
  await page.waitForTimeout(500);
  let lines = null;
  if (spec.anchor) {
    // the text node holding the sentence; scroll it to mid-screen, then measure its line boxes in the viewport
    lines = await page.evaluate(async (anchor) => {
      const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (let n = walk.nextNode(); n; n = walk.nextNode()) {
        const at = n.data.indexOf(anchor);
        if (at < 0) continue;
        const range = document.createRange();
        range.setStart(n, at);
        range.setEnd(n, at + anchor.length);
        const box = range.getBoundingClientRect();
        window.scrollBy(0, box.top + box.height / 2 - window.innerHeight / 2);
        await new Promise((r) => setTimeout(r, 800));
        return [...range.getClientRects()].map((r) => ({ x: r.x, y: r.y, w: r.width, h: r.height }));
      }
      return null;
    }, spec.anchor);
    if (!lines) throw new Error(`${name}: anchor not found on the page: ${spec.anchor}`);
    lines = lines.map((r) => ({ x: Math.round(r.x * SCALE), y: Math.round(r.y * SCALE), w: Math.round(r.w * SCALE), h: Math.round(r.h * SCALE) }));
  }
  const file = path.join(out, `${name}.png`);
  await page.screenshot({ path: file, clip: spec.anchor ? undefined : { x: 0, y: 0, width: 412, height: 1100 } });
  const sha = createHash("sha256").update(fs.readFileSync(file)).digest("hex");
  ledger[name] = { url: spec.url, captured: new Date().toISOString(), png: `captures/${name}.png`, sha256: sha,
    ...(spec.anchor ? { anchor: spec.anchor, lines } : {}) };
  console.log(`${name}: ${file}`);
  await page.close();
}
await browser.close();
fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 1) + "\n");
