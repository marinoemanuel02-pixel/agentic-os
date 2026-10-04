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
// The render script's encoder flags shape every segment, so its bytes are part of the environment too.
const flags = fs.readFileSync(path.join(root, "tools/render-cached.sh"), "utf8");
const env = envDigest(JSON.parse(fs.readFileSync(manifestFile, "utf8")), flags);
const segs = segments(SHOT_BEATS, BEAT);
const keys = segmentKeys(root, segs, env);
segs.forEach((s, i) => console.log(`${keys[i]} ${s.from} ${s.to - 1} ${s.shots.join(",")}`));
