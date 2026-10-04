// Print the render plan for the cache: one line per segment, "<key> <first frame> <last frame> <shots>",
// keyed on the segment's transitive src/ dependencies and the input manifest's environment (fonts, public, config).
//   node --no-warnings tools/cache/plan.mts <input-manifest.json>
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {SHOT_BEATS} from "../../src/data/plan.ts";
import {BEAT} from "../../src/lib/look.ts";
import {segments} from "./segments.mjs";
import {segmentKeys, envDigest} from "./keys.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const manifestFile = process.argv[2];
if (!manifestFile) throw new Error("usage: plan.mts <input-manifest.json>");
const env = envDigest(JSON.parse(fs.readFileSync(manifestFile, "utf8")));
const segs = segments(SHOT_BEATS, BEAT);
const keys = segmentKeys(root, segs, env);
segs.forEach((s, i) => console.log(`${keys[i]} ${s.from} ${s.to - 1} ${s.shots.join(",")}`));
