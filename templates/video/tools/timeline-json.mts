// The film's timeline in frames for the asset gate (R35): shots and line starts from src/data/plan.ts and the measured
// voice in src/data/vo.json. build.sh and qa.sh write it to $H/qa/timeline.json.   node --no-warnings tools/timeline-json.mts
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildLines, buildShots, totalBeats } from "../src/data/plan.ts";
import { BEAT, FPS } from "../src/lib/look.ts";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const vo = JSON.parse(fs.readFileSync(path.join(ROOT, "src/data/vo.json"), "utf8"));
const lines = buildLines(vo);
const timeline = {
  fps: FPS,
  frames: totalBeats(lines) * BEAT,
  shots: buildShots().map((s) => ({ id: s.id, from: s.from, frames: s.frames })),
  lines: lines.map((l) => ({ id: l.id, from: l.from })),
};
process.stdout.write(JSON.stringify(timeline, null, 2) + "\n");
