// Capture live article pages at phone width for the headline cards (src/lib/Headline.tsx crops these).
// Usage: node tools/capture.mjs [name...]
//   -> <media>/app/public/captures/<name>.png and research/captures.json (URL, capture time, SHA-256 of the PNG)
// Cookie and consent banners are hidden by CSS only; nothing is clicked or accepted.
import { createRequire } from "module";
import { createHash } from "crypto";
import fs from "fs";
import os from "os";
import path from "path";

const require = createRequire(import.meta.url);
const { chromium } = require(path.join(os.homedir(), ".npm-global/node_modules/playwright"));
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const media = process.env.AOS_VIDEO_MEDIA_ROOT ?? path.join(os.homedir(), ".aos/video/{{name}}");
const out = path.join(media, "app/public/captures");
fs.mkdirSync(out, { recursive: true });

const PAGES = JSON.parse(fs.readFileSync(path.join(root, "research/capture-pages.json"), "utf8")); // {"name": "https://..."}
const HIDE = `[id*="cookie" i],[class*="cookie" i],[id*="consent" i],[class*="consent" i],[class*="paywall" i],
  [id*="onetrust" i],.fc-consent-root,.fc-dialog-overlay,[role="dialog"],[aria-modal="true"],[class*="fc-" i],[class*="newsletter" i],[class*="modal" i],[class*="overlay" i],[class*="sticky" i],iframe
  { display: none !important; } html, body { overflow: visible !important; }`;

const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(PAGES);
const browser = await chromium.launch();
const ctx = await browser.newContext({ viewport: { width: 412, height: 1100 }, deviceScaleFactor: 2.6, colorScheme: "light",
  userAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36" });
const ledgerPath = path.join(root, "research/captures.json");
const ledger = fs.existsSync(ledgerPath) ? JSON.parse(fs.readFileSync(ledgerPath, "utf8")) : {};
for (const name of names) {
  const page = await ctx.newPage();
  await page.goto(PAGES[name], { waitUntil: "load", timeout: 90000 });
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
  const file = path.join(out, `${name}.png`);
  await page.screenshot({ path: file, clip: { x: 0, y: 0, width: 412, height: 1100 } });
  const sha = createHash("sha256").update(fs.readFileSync(file)).digest("hex");
  ledger[name] = { url: PAGES[name], captured: new Date().toISOString(), png: `captures/${name}.png`, sha256: sha };
  console.log(`${name}: ${file}`);
  await page.close();
}
await browser.close();
fs.writeFileSync(ledgerPath, JSON.stringify(ledger, null, 1) + "\n");
