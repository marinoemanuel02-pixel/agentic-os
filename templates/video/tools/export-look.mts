// The film's look for the engines (R56): src/lib/look.ts stays the one place the style lives; this writes it to
// engines/look.json, which Godot, Manim, Unity and Unreal read, with the frame rate and the calm curve's control points.
//   node --no-warnings tools/export-look.mts            write engines/look.json
//   node --no-warnings tools/export-look.mts --check    fail if engines/look.json is stale (render-shot runs this)
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {FPS, LOOKS, SERIF, SANS} from "../src/lib/look.ts";
import {SOFT_POINTS} from "../src/lib/ease.ts";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(root, "engines", "look.json");
const text = JSON.stringify({fps: FPS, softPoints: SOFT_POINTS, fonts: {serif: SERIF, sans: SANS}, looks: LOOKS}, null, 1) + "\n";

if (process.argv.includes("--check")) {
  // a Windows checkout may turn the committed file's line endings into CRLF; only the content counts
  const have = fs.existsSync(out) ? fs.readFileSync(out, "utf8").replace(/\r\n/g, "\n") : "";
  if (have !== text) {
    console.error("engines/look.json is stale: run node --no-warnings tools/export-look.mts");
    process.exit(1);
  }
  console.log("PASS: engines/look.json matches src/lib/look.ts");
} else {
  fs.mkdirSync(path.dirname(out), {recursive: true});
  fs.writeFileSync(out, text);
  console.log(`wrote ${path.relative(root, out)}`);
}
