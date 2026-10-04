// Camera joins between shots: dissolves join matched poses; cuts are match cuts or clearly different framings, never
// a small jump. Each shot's start/end poses live in src/shots/poses/<id>.ts (`export const poses`), imported only by
// that shot's module, so one pose edit changes one shot's cache key. Exit 1 on any violation.
//   node --no-warnings tools/checks/joins.mts
import { SHOT_BEATS } from "../../src/data/plan.ts";
import path from "node:path";
import fs from "node:fs";
import {fileURLToPath, pathToFileURL} from "node:url";
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

type Joins = Record<string, {start: Pose; end: Pose}>;

/** The poses of every listed shot that has a src/shots/poses/<id>.ts; missing files are left for checkJoins. */
export const loadPoses = async (root: string, ids: string[]): Promise<Joins> => {
  const joins: Joins = {};
  for (const id of ids) {
    const file = path.join(root, "src/shots/poses", `${id}.ts`);
    if (fs.existsSync(file)) joins[id] = (await import(pathToFileURL(file).href)).poses;
  }
  return joins;
};

const IMPORT = /(?:(?:import|export)\s+(?:[^'"]*?\sfrom\s+)?|import\s*\(\s*)["'](\.{1,2}\/[^"']+)["']/g;
const sources = (dir: string): string[] => fs.readdirSync(dir, {withFileTypes: true}).flatMap((e) =>
  e.isDirectory() ? sources(path.join(dir, e.name)) : /\.(tsx?|mts)$/.test(e.name) ? [path.join(dir, e.name)] : []);

/** Only a shot module imports poses, and only its own; a shared pose table would tie every shot's cache key together. */
export const poseImportErrors = (root: string): string[] => {
  const errors: string[] = [];
  const rel = (f: string) => path.relative(root, f).split(path.sep).join("/");
  for (const file of sources(path.join(root, "src"))) {
    const name = rel(file);
    const text = fs.readFileSync(file, "utf8");
    const targets = [...text.matchAll(IMPORT)].map((m) => rel(path.resolve(path.dirname(file), m[1])).replace(/\.(tsx?|mts)$/, ""));
    if (name.startsWith("src/shots/poses/")) {
      // a pose file that pulls in other poses is a barrel: whatever imports it depends on all of them
      if (targets.some((t) => t === "src/shots/poses" || t.startsWith("src/shots/poses/"))) errors.push(`${name} imports other pose files; a pose file holds one shot's poses`);
      continue;
    }
    const own = new Set([...text.matchAll(/export const (S\d\d)[A-Za-z0-9_]*\s*[:=]/g)].map((m) => m[1]));
    for (const target of targets) {
      const pose = /^src\/shots\/poses\/(S\d\d)$/.exec(target);
      if (target === "src/shots/joins") errors.push(`${name} imports the shared pose table src/shots/joins.ts; import poses/<id> per shot`);
      else if (!pose && (target === "src/shots/poses" || target.startsWith("src/shots/poses/"))) errors.push(`${name} imports a pose barrel (${target}); import poses/<id> per shot`);
      else if (pose && !own.size) errors.push(`${name} imports poses/${pose[1]}; only shot modules import poses (pass them to the stage)`);
      else if (pose && !own.has(pose[1])) errors.push(`${name} imports poses/${pose[1]}, which belongs to another shot`);
    }
  }
  return errors;
};

export const checkJoins = (beats: typeof SHOT_BEATS, joins: Joins): string[] => {
  const errors: string[] = [];
  for (const [id] of beats) if (!joins[id]) errors.push(`${id}: no start/end poses in src/shots/poses/${id}.ts`);
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
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
  const errors = [...poseImportErrors(root), ...checkJoins(SHOT_BEATS, await loadPoses(root, SHOT_BEATS.map(([id]) => id)))];
  for (const e of errors) console.error("FAIL " + e);
  if (errors.length) process.exit(1);
  console.log(`joins ok: ${SHOT_BEATS.length - 1} joins (dissolves matched, no jump cuts)`);
}
