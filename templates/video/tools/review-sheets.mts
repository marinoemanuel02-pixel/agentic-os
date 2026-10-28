// Review sheets from a finished (or review-cut) export: what the director and the independent reviewer look at.
//   node --no-warnings tools/review-sheets.mts <video.mp4> [out-dir] [--dry]
// - shots sheets: every shot at 20, 50 and 85 % of its slot (three frames per row), eight shots per sheet;
// - dissolves.jpg: one row per dissolve, just before it starts and 10 and 22 frames into it (ghosting, double
//   exposure, text crossing text);
// - full-size frames in <out-dir>/frames for anything that needs a closer look.
// A cut shorter than the plan (a hero, a partial animatic) is sampled only where it has frames; the rest is reported.
// Hand the sheets to a reviewer as images (codex exec -i ...). Frames cannot establish playback, pacing or sound
// (rule R14): say so in the brief. --dry prints the frame list without running ffmpeg.
// Output goes under $AOS_VIDEO_MEDIA_ROOT/frames (default ~/.aos/video/<name>/frames); an out-dir outside the media
// root, or inside this checkout, is refused (rule R25: private media roots, nothing generated in the repo).
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { FPS } from "../src/lib/look.ts";

type Slot = { id: string; from: number; frames: number; xin: number; tail: number };
export type Sample = { shot: string; name: string; frame: number };
export type Plan = { shots: Sample[]; dissolves: Sample[] };

const SHOT_FRACTIONS = [20, 50, 85];
const DISSOLVE_OFFSETS: [string, number][] = [["pre", -2], ["mid", 10], ["late", 22]];

export const sampleFrames = (shots: Slot[]): Plan => {
  if (!shots.length) throw new Error("no shots in the plan");
  const out: Plan = { shots: [], dissolves: [] };
  for (const s of shots) {
    for (const p of SHOT_FRACTIONS) out.shots.push({ shot: s.id, name: `${s.id}-${p}`, frame: s.from + Math.floor((s.frames * p) / 100) });
    if (s.xin > 0) for (const [label, off] of DISSOLVE_OFFSETS) out.dissolves.push({ shot: s.id, name: `${s.id}-${label}`, frame: s.from + off });
  }
  return out;
};

/** Keep only samples the cut actually has (frame < totalFrames); report what was left out. */
export const limitToFrames = (plan: Plan, totalFrames: number) => {
  const keep = (xs: Sample[]) => xs.filter((s) => s.frame < totalFrames);
  const skipped = [...plan.shots, ...plan.dissolves].filter((s) => s.frame >= totalFrames).map((s) => s.name);
  return { plan: { shots: keep(plan.shots), dissolves: keep(plan.dissolves) } as Plan, skipped };
};

/** Seek time in seconds for a frame: the middle of the frame, so it never lands on the edge of its neighbour. */
export const timestamp = (frame: number, fps: number) => ((frame + 0.5) / fps).toFixed(4);

const inside = (parent: string, child: string) => {
  const rel = path.relative(path.resolve(parent), path.resolve(child));
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
};

/** Where the sheets go: always under the media root, never inside the checkout. */
export const resolveOutDir = (media: string, repoRoot: string, outArg: string | undefined, label: string) => {
  const out = path.resolve(outArg ?? path.join(media, "frames", "review-" + label));
  if (!inside(media, out)) throw new Error(`out-dir ${out} is outside the media root ${media}`);
  if (inside(repoRoot, out)) throw new Error(`out-dir ${out} is inside the checkout ${repoRoot}`);
  return out;
};

/** True when this module is the script node was started with (paths with spaces and drive letters included). */
export const isMain = (metaUrl: string, argv1: string | undefined) =>
  !!argv1 && path.resolve(fileURLToPath(metaUrl)).toLowerCase() === path.resolve(argv1).toLowerCase();

const main = async () => {
  const args = process.argv.slice(2);
  const dry = args.includes("--dry");
  const [video, outArg] = args.filter((a) => !a.startsWith("--"));
  if (!video) { console.error("usage: node --no-warnings tools/review-sheets.mts <video.mp4> [out-dir] [--dry]"); process.exit(2); }
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const { buildShots } = await import("file:///" + path.join(root, "src/data/plan.ts").replace(/\\/g, "/"));
  const { mediaRoot } = await import("file:///" + path.join(root, "tools/media-root.mjs").replace(/\\/g, "/"));
  const media = mediaRoot(root);
  const outDir = resolveOutDir(media, root, outArg, path.basename(video, path.extname(video)));
  let plan = sampleFrames(buildShots());
  if (!dry || fs.existsSync(video)) {
    const seconds = Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video], { encoding: "utf8" }).trim());
    const cut = limitToFrames(plan, Math.floor(seconds * FPS));
    plan = cut.plan;
    if (cut.skipped.length) console.error(`cut ends at frame ${Math.floor(seconds * FPS)}; ${cut.skipped.length} samples beyond it are skipped (${cut.skipped[0]} ... ${cut.skipped[cut.skipped.length - 1]})`);
  }
  if (dry) { for (const s of [...plan.shots, ...plan.dissolves]) console.log(`${s.name}\t${s.frame}\t${timestamp(s.frame, FPS)}`); return; }
  const frames = path.join(outDir, "frames");
  fs.mkdirSync(frames, { recursive: true });
  for (const s of [...plan.shots, ...plan.dissolves]) {
    // -nostdin: ffmpeg reads the terminal otherwise and swallows the rest of a shell loop
    execFileSync("ffmpeg", ["-nostdin", "-v", "error", "-y", "-ss", timestamp(s.frame, FPS), "-i", video, "-frames:v", "1", path.join(frames, s.name + ".png")]);
  }
  const ids = [...new Set(plan.shots.map((s) => s.shot))];
  for (let i = 0; i * 8 < ids.length; i++) {
    const files = plan.shots.filter((s) => ids.slice(i * 8, i * 8 + 8).includes(s.shot)).map((s) => path.join(frames, s.name + ".png"));
    execFileSync("magick", ["montage", ...files, "-tile", "3x", "-geometry", "640x360+3+3", "-background", "#222", path.join(outDir, `sheet-${i + 1}.jpg`)]);
  }
  if (plan.dissolves.length) {
    const files = plan.dissolves.map((s) => path.join(frames, s.name + ".png"));
    execFileSync("magick", ["montage", ...files, "-tile", "3x", "-geometry", "640x360+3+3", "-background", "#222", path.join(outDir, "dissolves.jpg")]);
  }
  console.log(outDir);
};

if (isMain(import.meta.url, process.argv[1])) await main();
