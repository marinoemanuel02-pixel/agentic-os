// Verify explicitly requested hero compositions in a private runner; no film-specific defaults.
// node tools/verify-hero.mjs Composition:30,90,150 or --stills Composition:30,Other:60
// Outputs live under AOS_VIDEO_MEDIA_ROOT/hero-verify/<branch>/; dependencies remain read-only.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";
import { mediaRoot as resolveMediaRoot } from "./media-root.mjs";

const FPS = 30, WIDTH = 1920, HEIGHT = 1080, CONCURRENCY = 2;
const KEY_FRAMES = {};
const stillsArg = process.argv.indexOf("--stills");
const items = stillsArg > 0 ? (process.argv[stillsArg + 1] || "").split(",") : process.argv.slice(2);
for (const item of items.filter(Boolean)) {
  const [id, numbers] = item.split(":");
  const frames = (numbers || "").split(",").map(Number);
  if (!id || !numbers || frames.some(n => !Number.isInteger(n) || n < 0)) {
    console.error("usage: node tools/verify-hero.mjs Composition:frame,frame [...] or --stills Composition:frame,...");
    process.exit(1);
  }
  KEY_FRAMES[id] = [...(KEY_FRAMES[id] || []), ...frames];
}
if (!Object.keys(KEY_FRAMES).length) {
  console.error("usage: node tools/verify-hero.mjs Composition:frame,frame [...] or --stills Composition:frame,...");
  process.exit(1);
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const sh = (cmd, args, opts = {}) => execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], ...opts });
const here = path.resolve(sh("git", ["rev-parse", "--show-toplevel"], { cwd: scriptDir }).trim());
const branch = sh("git", ["rev-parse", "--abbrev-ref", "HEAD"], { cwd: here }).trim();
const slug = branch.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "detached";

const mediaRoot = resolveMediaRoot(here);
const root = path.join(mediaRoot, "hero-verify", slug);
const app = path.join(root, "app");
const bundle = path.join(root, "bundle");
const media = path.join(root, "media");
const tmp = path.join(root, "tmp");
const shared = process.env.AOS_REMOTION_MODULES || path.join(os.homedir(), ".aos", "scratch", "video-agi-race", "node_modules");

let failures = 0;
const fail = (msg) => { console.error(`FAIL ${msg}`); failures++; };
const ok = (msg) => console.log(`ok   ${msg}`);
const die = (msg) => { console.error(`FAIL ${msg}`); process.exit(1); };

// ---- guards: private, outside the repo and outside AppData ----
for (const p of [root, tmp]) {
  if (/[\\/]AppData[\\/]/i.test(p)) die(`refusing to write under AppData: ${p}`);
  if (path.resolve(p).toLowerCase().startsWith(here.toLowerCase() + path.sep)) die(`refusing to write inside the checkout: ${p}`);
}
if (!fs.existsSync(path.join(shared, "@remotion", "cli"))) die(`shared Remotion install not found: ${shared}`);

// ---- 1. private app folder ----
for (const d of [app, media, tmp]) fs.mkdirSync(d, { recursive: true });
const junction = (target, at) => {
  const st = fs.lstatSync(at, { throwIfNoEntry: false });
  if (st && !st.isSymbolicLink()) die(`${at} exists and is not a junction; not touching it`);
  if (st) fs.unlinkSync(at);
  fs.symlinkSync(target, at, "junction");
};
junction(shared, path.join(app, "node_modules"));
junction(path.join(here, "src"), path.join(app, "src"));
for (const f of ["remotion.config.ts", "package.json", "tsconfig.json"]) fs.copyFileSync(path.join(here, "tools", f), path.join(app, f));
ok(`runner ${root} (src -> ${path.join(here, "src")})`);

// Remotion and Chrome write frames to the temp dir: keep that private too.
const env = { ...process.env, TEMP: tmp, TMP: tmp, TMPDIR: tmp };
const cli = path.join(app, "node_modules", "@remotion", "cli", "remotion-cli.js");
const remotion = (args, timeout = 1800000) => sh(process.execPath, [cli, ...args], { cwd: app, env, timeout, maxBuffer: 64 * 1024 * 1024 });

// ---- 2. fresh private bundle ----
fs.rmSync(bundle, { recursive: true, force: true });
try {
  remotion(["bundle", "src/index.ts", "--out-dir", bundle, "--bundle-cache=false", "--log=error"]);
} catch (e) {
  die(`bundle:\n${(e.stderr || e.stdout || e.message).slice(-3000)}`);
}
ok("bundle");

// Composition durations as Remotion itself reports them.
const listing = remotion(["compositions", bundle, "--log=info"]);
const durationOf = (id) => {
  const m = listing.match(new RegExp(`^\\s*${id}\\s+\\d+\\s+\\d+x\\d+\\s+(\\d+)`, "m"));
  return m ? Number(m[1]) : null;
};

// ---- quick stills mode ----
if (stillsArg > 0) {
  const outDir = path.join(media, "stills");
  fs.mkdirSync(outDir, { recursive: true });
  for (const item of (process.argv[stillsArg + 1] || "").split(",").filter(Boolean)) {
    const [id, frame] = item.split(":");
    const png = path.join(outDir, `${id}-${frame}.png`);
    try {
      remotion(["still", bundle, id, png, `--frame=${frame}`, "--gl=angle", "--log=error", "--overwrite"], 300000);
      ok(`still ${png}`);
    } catch (e) {
      fail(`still ${id}:${frame}\n${(e.stderr || e.stdout || e.message).slice(-2000)}`);
    }
  }
  process.exit(failures ? 1 : 0);
}

// ---- 3. render, probe, extract ----
const probe = (file) => JSON.parse(sh("ffprobe", ["-v", "error", "-show_format", "-show_streams", "-of", "json", file]));
const indices = (count, total) => Array.from({ length: count }, (_, i) => Math.round((i * (total - 1)) / (count - 1)));
const extract = (mp4, frames, outPattern) => {
  const select = frames.map((n) => `eq(n,${n})`).join("+"); // commas are literal inside the quoted filter
  sh("ffmpeg", ["-nostdin", "-y", "-v", "error", "-i", mp4, "-vf", `select='${select}'`, "-fps_mode", "passthrough", outPattern]);
};
const report = { branch, root, renders: {} };

for (const id of Object.keys(KEY_FRAMES)) {
  const frames = durationOf(id);
  if (!frames) { fail(`${id}: not listed by remotion compositions`); continue; }
  const dir = path.join(media, id);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  const mp4 = path.join(dir, `${id}.mp4`);
  const t0 = Date.now();
  try {
    remotion(["render", bundle, id, mp4, `--concurrency=${CONCURRENCY}`, "--gl=angle", "--muted", "--codec=h264", "--log=error", "--overwrite"]);
  } catch (e) {
    fail(`${id} render:\n${(e.stderr || e.stdout || e.message).slice(-3000)}`);
    continue;
  }
  const seconds = (Date.now() - t0) / 1000;
  ok(`${id} rendered ${frames} frames in ${seconds.toFixed(0)} s`);

  // probe: 1080p30 H.264, no audio, duration matches the composition
  const p = probe(mp4);
  const video = p.streams.filter((s) => s.codec_type === "video");
  const audio = p.streams.filter((s) => s.codec_type === "audio");
  const v = video[0] || {};
  const duration = Number(p.format.duration);
  const expected = frames / FPS;
  const checks = [
    [video.length === 1, `one video stream (found ${video.length})`],
    [audio.length === 0, `no audio stream (found ${audio.length})`],
    [v.codec_name === "h264", `codec h264 (found ${v.codec_name})`],
    [v.width === WIDTH && v.height === HEIGHT, `size ${WIDTH}x${HEIGHT} (found ${v.width}x${v.height})`],
    [v.r_frame_rate === `${FPS}/1`, `rate ${FPS}/1 (found ${v.r_frame_rate})`],
    [Math.abs(duration - expected) <= 1.5 / FPS, `duration ${expected.toFixed(3)} s (found ${duration.toFixed(3)} s)`],
  ];
  for (const [pass, what] of checks) (pass ? ok : fail)(`${id} ${what}`);

  // chronological strip frames and full-size key frames
  const stripCount = 12;
  const stripAt = indices(stripCount, frames);
  const keyAt = [...new Set(KEY_FRAMES[id].filter((n) => n < frames))].sort((a, b) => a - b);
  try {
    extract(mp4, stripAt, path.join(dir, "strip-%02d.png"));
    extract(mp4, keyAt, path.join(dir, "keytmp-%02d.png"));
    keyAt.forEach((n, i) => fs.renameSync(path.join(dir, `keytmp-${String(i + 1).padStart(2, "0")}.png`), path.join(dir, `key-${String(n).padStart(3, "0")}.png`)));
  } catch (e) {
    fail(`${id} frame extraction: ${(e.stderr || e.message).slice(-1500)}`);
    continue;
  }
  const stripPngs = stripAt.map((_, i) => path.join(dir, `strip-${String(i + 1).padStart(2, "0")}.png`));
  const keyPngs = keyAt.map((n) => path.join(dir, `key-${String(n).padStart(3, "0")}.png`));
  const missing = [...stripPngs, ...keyPngs].filter((f) => !fs.existsSync(f));
  if (missing.length) fail(`${id} missing extracted frames: ${missing.map((f) => path.basename(f)).join(" ")}`);
  else ok(`${id} extracted ${stripPngs.length} strip frames (${stripAt.join(" ")}) and ${keyPngs.length} full-size key frames`);
  for (const f of keyPngs.filter((x) => fs.existsSync(x))) {
    const size = sh("magick", ["identify", "-format", "%wx%h", f]).trim();
    if (size !== `${WIDTH}x${HEIGHT}`) fail(`${id} ${path.basename(f)} is ${size}`);
  }
  // first and last strip frames must differ (a frozen render passes every probe above)
  if (!missing.length) {
    let rmse = "";
    try { sh("magick", ["compare", "-metric", "RMSE", stripPngs[0], stripPngs.at(-1), "null:"]); } catch (e) { rmse = String(e.stderr || ""); }
    const normalised = Number((rmse.match(/\(([\d.e-]+)\)/) || [])[1]);
    if (!(normalised > 0.01)) fail(`${id} first and last strip frames are (nearly) identical: ${rmse.trim() || "0"}`);
    else ok(`${id} first/last frames differ (RMSE ${normalised.toFixed(3)})`);
    try {
      sh("magick", ["montage", ...stripPngs, "-tile", "4x", "-geometry", "640x360+4+4", "-background", "#333", path.join(dir, "strip.jpg")]);
      sh("magick", ["montage", ...keyPngs, "-tile", "3x", "-geometry", "960x540+4+4", "-background", "#333", path.join(dir, "keys.jpg")]);
      ok(`${id} review sheets ${path.join(dir, "strip.jpg")} and keys.jpg`);
    } catch (e) {
      fail(`${id} montage: ${(e.stderr || e.message).slice(-800)}`);
    }
  }
  report.renders[id] = { mp4, frames, renderSeconds: seconds, probe: { codec: v.codec_name, width: v.width, height: v.height, rate: v.r_frame_rate, duration, audioStreams: audio.length }, strip: stripAt, keyFrames: keyAt };
}

fs.writeFileSync(path.join(media, "verify-report.json"), JSON.stringify({ ...report, failures }, null, 2));
console.log(failures ? `${failures} failure(s); report ${path.join(media, "verify-report.json")}` : `all checks passed -> ${media}`);
process.exit(failures ? 1 : 0);
