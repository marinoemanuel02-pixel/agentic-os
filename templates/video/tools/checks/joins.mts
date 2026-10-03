// Camera joins between shots (rule in src/shots/joins.ts): dissolves join matched poses; cuts are match cuts or
// clearly different framings, never a small jump. Exit 1 on any violation.
//   node --no-warnings tools/checks/joins.mts
import { SHOT_BEATS } from "../../src/data/plan.ts";
import path from "node:path";
import {fileURLToPath} from "node:url";
import { JOINS } from "../../src/shots/joins.ts";
import { validPose, DEFAULT_FOV, type Pose } from "../../src/lib/shot-camera.ts";

const dist = (a: number[], b: number[]) => Math.hypot(...a.map((x, i) => x - b[i]));
/** "same" | "different" | "jump" for the pose before and after a join. */
export const classify = (a: Pose, b: Pose): "same" | "different" | "jump" => {
  if (!validPose(a) || !validPose(b)) throw new Error("invalid pose: finite 3-vectors required");
  const dp = dist(a.pos, b.pos), dt = dist(a.target, b.target), df = Math.abs((a.fov ?? DEFAULT_FOV) - (b.fov ?? DEFAULT_FOV));
  if (dp < 1e-6 && dt < 1e-6 && df < 1e-6) return "same";
  // a different framing moves the camera or its subject by a good part of the frame, or changes the lens a lot
  if (dp >= 1.0 || dt >= 0.8 || df >= 6) return "different";
  return "jump";
};

export const checkJoins = (beats: typeof SHOT_BEATS, joins: typeof JOINS): string[] => {
  const errors: string[] = [];
  for (const [id] of beats) if (!joins[id]) errors.push(`${id}: no start/end poses in src/shots/joins.ts`);
  for (const [id] of beats) if (joins[id] && (!validPose(joins[id].start) || !validPose(joins[id].end))) errors.push(`${id}: invalid pose (finite 3-vectors required)`);
  for (let i = 1; i < beats.length; i++) {
    const [prev] = beats[i - 1];
    const [id, , tr] = beats[i];
    if (!joins[prev] || !joins[id]) continue;
    if (![joins[prev].end, joins[id].start].every(validPose)) continue;
    const kind = classify(joins[prev].end, joins[id].start);
    if (tr === "x" && kind !== "same") errors.push(`${prev} -> ${id}: dissolve between different framings (${kind}); match the poses or cut`);
    if (tr === "c" && kind === "jump") errors.push(`${prev} -> ${id}: jump cut (framing changes only slightly); match it exactly or reframe`);
  }
  return errors;
};

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const errors = checkJoins(SHOT_BEATS, JOINS);
  for (const e of errors) console.error("FAIL " + e);
  if (errors.length) process.exit(1);
  console.log(`joins ok: ${SHOT_BEATS.length - 1} joins (dissolves matched, no jump cuts)`);
}
