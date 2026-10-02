// Verify a checkout (this project or a delegate worktree) without writing into it:
//   node tools/verify.mjs S01 S02 ...
// 1. the shot plan fills the line plan exactly (tools/check-plan.mts);
// 2. the Remotion bundle builds from this checkout's src/;
// 3. each named composition renders three stills (first, middle, last frame) without errors.
// Stills go to ~/.aos/video/{{name}}/verify/<checkout-name>/ for review. Exit code 0 only if all pass.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const here = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const H = path.join(os.homedir(), ".aos", "video", "{{name}}");
// The shared Remotion + three.js install (about 480 MB, made once); aos video new links every project to it.
const shared = process.env.AOS_REMOTION_MODULES || path.join(os.homedir(), ".aos", "scratch", "video-agi-race", "node_modules");
const name = path.basename(here);
const app = path.join(H, "verify-app", name);
const out = path.join(H, "verify", name);
const ids = process.argv.slice(2);

const run = (args, opts = {}) => execFileSync(process.execPath, args, { stdio: ["ignore", "pipe", "pipe"], encoding: "utf8", ...opts });

// 1. plan
const plan = run(["--no-warnings", path.join(here, "tools", "check-plan.mts")], { cwd: here });
if (!plan.includes("plan ok")) { console.error(plan); process.exit(1); }
console.log("plan ok");

// 2. a throwaway app folder that points at this checkout's src/
fs.mkdirSync(app, { recursive: true });
fs.mkdirSync(out, { recursive: true });
const link = (target, at) => {
  if (fs.existsSync(at)) fs.rmSync(at, { recursive: false, force: true });
  fs.symlinkSync(target, at, "junction");
};
link(shared, path.join(app, "node_modules"));
link(path.join(here, "src"), path.join(app, "src"));
for (const f of ["remotion.config.ts", "package.json", "tsconfig.json"]) fs.copyFileSync(path.join(here, "tools", f), path.join(app, f));
const cli = path.join(app, "node_modules", "@remotion", "cli", "remotion-cli.js");
const bundle = path.join(app, "bundle");
try {
  run([cli, "bundle", "src/index.ts", "--out-dir", bundle, "--log=error"], { cwd: app });
} catch (e) {
  console.error("bundle failed:\n" + (e.stderr || e.stdout || e.message));
  process.exit(1);
}
console.log("bundle ok");

// 3. stills
const listed = run([cli, "compositions", bundle, "--quiet"], { cwd: app }).trim().split(/\s+/);
const { buildShots } = await import(new URL("../src/data/plan.ts", import.meta.url));
const comps = buildShots().filter((s) => listed.includes(s.id)).map((s) => ({ id: s.id, durationInFrames: s.frames }));
let failed = 0;
for (const id of ids) {
  const c = comps.find((x) => x.id === id);
  if (!c) { console.error(`${id}: no such composition`); failed++; continue; }
  for (const f of [0, Math.floor(c.durationInFrames / 2), c.durationInFrames - 1]) {
    const png = path.join(out, `${id}-${f}.png`);
    try {
      run([cli, "still", bundle, id, png, `--frame=${f}`, "--gl=angle", "--log=error"], { cwd: app, timeout: 180000 });
      console.log(`${id} frame ${f}: ok`);
    } catch (e) {
      console.error(`${id} frame ${f}: FAILED\n${(e.stderr || e.stdout || e.message).slice(-1500)}`);
      failed++;
    }
  }
}
// One contact sheet (first / middle / last frame per row) for the director's review of a delegated batch.
try {
  const pngs = ids.flatMap((id) => fs.readdirSync(out).filter((f) => f.startsWith(id + "-") && f.endsWith(".png"))
    .sort((a, b) => Number(a.split("-")[1]) - Number(b.split("-")[1])).map((f) => path.join(out, f)));
  if (pngs.length) {
    execFileSync("magick", ["montage", ...pngs, "-tile", "3x", "-geometry", "560x315+4+4", "-background", "#333", path.join(out, "sheet.jpg")]);
    console.log(`contact sheet: ${path.join(out, "sheet.jpg")}`);
  }
} catch (e) { console.error("contact sheet failed (ImageMagick): " + e.message); }
console.log(failed ? `${failed} failure(s)` : `all stills ok -> ${out}`);
process.exit(failed ? 1 : 0);
