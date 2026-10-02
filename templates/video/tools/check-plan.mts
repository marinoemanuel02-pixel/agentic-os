// node tools/check-plan.ts : prints the line and shot plan and fails if the shots do not fill the lines exactly.
import fs from "node:fs";
import { ANCHORS, buildLines, buildShots, totalBeats } from "../src/data/plan.ts";
import { BEAT, FPS } from "../src/lib/look.ts";
const SPB = BEAT / FPS; // seconds per beat
const vo = JSON.parse(fs.readFileSync(new URL("../src/data/vo.json", import.meta.url), "utf8"));
const lines = buildLines(vo);
const shots = buildShots();
const total = totalBeats(lines);
const shotTotal = shots.reduce((a, s) => a + s.beats, 0);
for (const l of lines) console.log(`${l.id.padEnd(4)} beat ${String(l.startBeat).padStart(3)} +${l.beats}  (${l.seconds.toFixed(2)} s of ${(l.beats * SPB).toFixed(1)})${l.fits ? "" : "  DOES NOT FIT"}`);
console.log(`lines end at beat ${total}; shots sum to ${shotTotal}; ${(total * SPB).toFixed(1)} s`);
const anchorsOk = ANCHORS.every(([shotId, lineId]) => {
  const s = shots.find((x) => x.id === shotId), l = lines.find((x) => x.id === lineId);
  const ok = !!s && !!l && s.startBeat === l.startBeat;
  if (!ok) console.error(`anchor ${shotId} / ${lineId} does not start on the same beat`);
  return ok;
});
if (total !== shotTotal || !anchorsOk || lines.some((l) => !l.fits)) { console.error("PLAN MISMATCH"); process.exit(1); }
console.log("plan ok");
