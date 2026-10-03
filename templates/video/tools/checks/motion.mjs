// Motion check (rule R17 in ~/.agents/video/video-rules.md): finds "snappy" motion, the user's complaint about
// two earlier videos. Two parts:
//  1. source: easing curves in src/ that start at full speed (expo-out) or overshoot (back-out, elastic);
//  2. picture: in a texture-free proxy render (inputProps {qa: true}: no line boil, no grain), each frame is cut
//     into tiles; a tile "snaps" when it goes from rest to near its peak change within one or two frames and
//     then keeps moving (a travelling move). A soft move starts slowly, so its first frames change little.
//     Cuts and dissolve windows from src/data/plan.ts are excluded; short accents (blinks, sparkles) are not
//     travelling moves and are ignored. It is a locator: every hit names a time and a shot to look at.
// Usage: node --no-warnings tools/checks/motion.mjs <proxy.mp4> [report.md]
//   exit 0 = no unwaived snap and no banned curve; 1 = findings (see the report); 2 = usage or tool error.
// Waivers: qa/motion-waivers.txt, one per line "<shot> <seconds> <reason>" (a deliberate hit, e.g. a slam).
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath, pathToFileURL} from "node:url";

export const OPTS = {
  w: 160, // proxy analysis size (16:9)
  h: 90,
  cols: 8,
  rows: 6,
  rest: 0.6, // grey levels above a tile's baseline that still count as rest
  peak: 3.0, // a snap's first moving frame changes at least this much (grey levels, tile mean)
  ratio: 0.55, // ... and at least this share of the move's peak over the next frames
  look: 8, // frames after the onset that define the move's peak
  sustain: 8, // a travelling move stays above rest for at least this many frames
  edge: 2, // frames excluded on each side of a cut
};

/** Banned easing curves in source text: [line, text] for each hit. */
export const scanSource = (text) => {
  const hits = [];
  const lines = text.split(/\r?\n/);
  lines.forEach((line, i) => {
    for (const m of line.matchAll(/Easing\.bezier\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)/g)) {
      const [x1, y1, x2, y2] = m.slice(1).map(Number);
      const fastStart = x1 <= 0.25 && y1 >= 0.8; // expo-out-like: most of the move in the first frames
      const overshoot = y1 > 1.05 || y2 > 1.05 || y1 < -0.05 || y2 < -0.05;
      if (fastStart || overshoot) hits.push([i + 1, m[0]]);
    }
    for (const m of line.matchAll(/Easing\.(out|inOut)\(\s*Easing\.(exp|back|elastic|bounce)/g)) hits.push([i + 1, m[0]]);
    for (const m of line.matchAll(/Easing\.(back|elastic|bounce)\(/g)) hits.push([i + 1, m[0]]);
  });
  return hits;
};

/** Frames (inclusive ranges) where change comes from the edit, not from motion. */
export const excluded = (windows, edge = OPTS.edge) => (t) => windows.some(([a, b]) => t >= a - edge && t <= b + edge);

/**
 * Snaps in one tile's series of frame differences d[t] (change between frame t-1 and t).
 * Returns the onset frames. base = the tile's resting level (its median change).
 */
export const snapsInSeries = (d, base, isEdit, o = OPTS, isAfterCut = (t) => isEdit(t - 1)) => {
  const out = [];
  for (let t = 3; t < d.length - o.sustain; t++) {
    if (isEdit(t)) continue;
    // Right after a cut there is no "before" inside the shot. A camera already drifting at the cut is normal; a
    // move that starts at full speed and then decays (an expo-out start) is a snap.
    if (isEdit(t - 1)) {
      if (!isAfterCut(t)) continue; // the end of a dissolve: the fading picture settles, nothing starts
      const first = d[t] - base;
      const later = d[t + Math.min(6, o.sustain - 1)] - base;
      let moving = 0;
      for (let k = 0; k < o.sustain; k++) if (d[t + k] > base + o.rest) moving++;
      if (first >= o.peak && later < 0.5 * first && moving >= o.sustain) out.push(t);
      continue;
    }
    const rest = base + o.rest;
    const before = Math.max(d[t - 1], d[t - 2], d[t - 3]);
    if (before > rest) continue; // not starting from rest
    if (d[t] - base < o.peak) continue; // the first frame barely moves: a soft start
    let peak = 0;
    for (let k = 0; k < o.look; k++) peak = Math.max(peak, d[t + k] - base);
    if ((d[t] - base) / peak < o.ratio) continue; // the move accelerates after its onset: soft
    let moving = 0;
    for (let k = 0; k < o.sustain; k++) if (d[t + k] > rest) moving++;
    if (moving < o.sustain) continue; // a short accent (a blink, a sparkle), not a travelling move
    out.push(t);
  }
  return out;
};

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : 0;
};

/** Per-tile difference series from raw grey frames (Uint8 buffers of w*h). */
export const tileSeries = (frames, o = OPTS) => {
  const tw = Math.floor(o.w / o.cols);
  const th = Math.floor(o.h / o.rows);
  const series = Array.from({ length: o.cols * o.rows }, () => [0]);
  for (let t = 1; t < frames.length; t++) {
    const a = frames[t - 1];
    const b = frames[t];
    for (let r = 0; r < o.rows; r++) {
      for (let c = 0; c < o.cols; c++) {
        let sum = 0;
        for (let y = r * th; y < (r + 1) * th; y++) {
          const row = y * o.w;
          for (let x = c * tw; x < (c + 1) * tw; x++) sum += Math.abs(a[row + x] - b[row + x]);
        }
        series[r * o.cols + c].push(sum / (tw * th));
      }
    }
  }
  return series;
};

/** All snaps in a film: [{frame, tile}] sorted by frame, merged across tiles within 3 frames. */
export const findSnaps = (series, windows, o = OPTS) => {
  const isEdit = excluded(windows, o.edge);
  // windows of one or two frames are cuts; longer ones are dissolves
  const isAfterCut = excluded(windows.filter(([a, b]) => b - a <= 2), o.edge);
  const afterCut = (t) => isAfterCut(t - 1);
  const hits = [];
  series.forEach((d, tile) => {
    const base = median(d);
    for (const t of snapsInSeries(d, base, isEdit, o, afterCut)) hits.push({ frame: t, tile });
  });
  hits.sort((a, b) => a.frame - b.frame);
  const merged = [];
  for (const h of hits) {
    const last = merged[merged.length - 1];
    if (last && h.frame - last.frame <= 3) last.tiles.push(h.tile);
    else merged.push({ frame: h.frame, tiles: [h.tile] });
  }
  return merged;
};

const readFrames = (video, o) =>
  new Promise((resolve, reject) => {
    const size = o.w * o.h;
    const frames = [];
    let buf = Buffer.alloc(0);
    const p = spawn("ffmpeg", ["-v", "error", "-i", video, "-vf", `scale=${o.w}:${o.h}:flags=area,format=gray`, "-f", "rawvideo", "-"]);
    p.stdout.on("data", (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      while (buf.length >= size) {
        frames.push(new Uint8Array(buf.subarray(0, size)));
        buf = buf.subarray(size);
      }
    });
    p.on("error", reject);
    p.on("close", (code) => (code === 0 ? resolve(frames) : reject(new Error(`ffmpeg exited ${code}`))));
  });

const walk = (dir) =>
  fs.existsSync(dir)
    ? fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]))
    : [];

const main = async () => {
  const [video, reportArg] = process.argv.slice(2);
  if (!video || !fs.existsSync(video)) {
    console.error("usage: node tools/checks/motion.mjs <proxy.mp4> [report.md]");
    process.exit(2);
  }
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
  const report = reportArg || path.join(root, "qa", "motion.md");
  const plan = await import(pathToFileURL(path.join(root, "src", "data", "plan.ts")));
  const shots = plan.buildShots();
  // older plans (hard cuts only) have no editWindows(): every shot start is a cut
  const windows = plan.editWindows ? plan.editWindows() : shots.map((s) => [s.from, s.from + 1]);
  const fps = Number(execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", video], { encoding: "utf8" }).replace(/[,\s]/g, "").split("/").reduce((a, b) => Number(a) / Number(b)));
  const shotAt = (fr) => (shots.find((s) => fr >= s.from && fr < s.from + s.frames) || { id: "?" }).id;
  // 1. source
  const sourceHits = [];
  for (const f of walk(path.join(root, "src")).filter((f) => /\.(tsx?|mjs)$/.test(f))) {
    for (const [line, text] of scanSource(fs.readFileSync(f, "utf8"))) sourceHits.push(`${path.relative(root, f)}:${line} ${text}`);
  }
  // 2. picture
  const frames = await readFrames(video, OPTS);
  const snaps = findSnaps(tileSeries(frames, OPTS), windows, OPTS);
  const waiverFile = path.join(root, "qa", "motion-waivers.txt");
  const waivers = fs.existsSync(waiverFile)
    ? fs.readFileSync(waiverFile, "utf8").split(/\r?\n/).filter((l) => l.trim() && !l.startsWith("#")).map((l) => {
        const [shot, sec, ...why] = l.trim().split(/\s+/);
        return { shot, sec: Number(sec), why: why.join(" ") };
      })
    : [];
  const rows = snaps.map((s) => {
    const sec = s.frame / fps;
    const shot = shotAt(s.frame);
    const w = waivers.find((x) => x.shot === shot && Math.abs(x.sec - sec) <= 0.5);
    return { sec, shot, tiles: s.tiles.length, waived: w ? w.why : "" };
  });
  const open = rows.filter((r) => !r.waived);
  const avgShot = shots.reduce((a, s) => a + s.frames, 0) / shots.length / fps;
  const lines = [
    `# Motion check: ${path.basename(video)}`,
    "",
    `- ${frames.length} frames, ${shots.length} shots, average shot ${avgShot.toFixed(1)} s`,
    `- banned curves in src/: ${sourceHits.length}`,
    ...sourceHits.map((h) => `  - ${h}`),
    `- snaps (abrupt starts of a travelling move): ${rows.length}, waived ${rows.length - open.length}`,
    ...rows.map((r) => `  - ${r.sec.toFixed(2)} s, ${r.shot}, ${r.tiles} tile(s)${r.waived ? `, waived: ${r.waived}` : ""}`),
    "",
    open.length || sourceHits.length ? "**Motion check FAILED.**" : "**Motion check passed.**",
  ];
  fs.mkdirSync(path.dirname(report), { recursive: true });
  fs.writeFileSync(report, lines.join("\n") + "\n");
  console.log(lines.join("\n"));
  process.exit(open.length || sourceHits.length ? 1 : 0);
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(2);
  });
}
