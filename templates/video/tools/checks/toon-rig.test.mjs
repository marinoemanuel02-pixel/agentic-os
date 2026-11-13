// Behavioral checks for articulation and the prop attachment contract. Visual craft
// is reviewed separately on the cast and shoulder sheets.
import assert from "node:assert/strict";
import { test } from "node:test";
// The kit (src/lib/toon/) is bundled with esbuild from TOON_NODE_MODULES or ~/.aos/scratch/video-agi-race/node_modules;
// without esbuild, react and react-dom there every check skips and says why.
import { resolve, join, dirname } from "node:path";
import { mkdtempSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildToon, toonModules } from "../toon-build.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const req = createRequire(join(toonModules, "noop.js"));
const missing = ["esbuild", "react", "react-dom/server"].filter((m) => { try { req.resolve(m); return false; } catch { return true; } });
const skip = missing.length > 0 && `${missing.join(", ")} not resolvable from ${toonModules} (set TOON_NODE_MODULES)`;
let kit = {};
if (!skip) {
  const base = process.env.AOS_VIDEO_TEST_ROOT || tmpdir();
  mkdirSync(base, { recursive: true });
  const outfile = join(mkdtempSync(join(base, "toon-rig-")), "kit.mjs");
  await buildToon({
    stdin: { contents: 'import React from "react"; import {renderToStaticMarkup} from "react-dom/server"; import {Toon} from "./src/lib/toon/Toon"; export * from "./src/lib/toon/Toon"; export * from "./src/lib/toon/ToonPerson"; export * from "./src/lib/toon/hands"; export const renderProbe = (props) => renderToStaticMarkup(<svg><Toon {...props} holdF={<circle id="held-probe" r={2}/>} /></svg>);', resolveDir: root, loader: "tsx" },
    outfile,
  });
  kit = await import(pathToFileURL(outfile));
}
const { toonRig, toonPoint, specFor, poseFor, handPos, handShape, renderProbe } = kit;
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const close = (a, b, label) => assert.ok(Math.abs(a - b) < 1e-6, `${label}: ${a} != ${b}`);
const spec = skip ? undefined : specFor({ outfit: "coat", hair: "bun", tone: 1, glasses: true });

test("shoulders follow elevation on both sides without joint-length drift", { skip }, () => {
  for (const side of ["F", "B"]) {
    let previous;
    const hanging = toonRig(spec, { [`arm${side}`]: { hand: [0, 1] } });
    const raised = toonRig(spec, { [`arm${side}`]: { hand: [0, -1] } });
    assert.ok(raised[`sh${side}`][1] < hanging[`sh${side}`][1] - 4, "raised shoulder must lift");
    for (let degrees = -180; degrees <= 180; degrees += 2) {
      const a = degrees * Math.PI / 180;
      const r = toonRig(spec, { [`arm${side}`]: { hand: [Math.sin(a) * 0.94, Math.cos(a) * 0.94], bend: side === "F" ? -0.2 : 0.2 } });
      for (const key of [`sh${side}`, `elbow${side}`, `wrist${side}`, `hand${side}`]) {
        assert.ok(r[key]?.every(Number.isFinite), `${key} must be finite`);
      }
      close(distance(r[`sh${side}`], r[`elbow${side}`]), r.upperArm, "upper arm");
      close(distance(r[`elbow${side}`], r[`wrist${side}`]), r.forearm, "forearm");
      if (previous) assert.ok(distance(r[`sh${side}`], previous) < 3, "shoulder sweep must be continuous");
      previous = r[`sh${side}`];
    }
  }
});

test("folded and overextended targets keep anatomical segment lengths", { skip }, () => {
  for (const hand of [[0, 0], [0.1, 0.2], [0.5, -0.6], [2, -2]]) {
    const r = toonRig(spec, { armF: { hand, bend: -0.5 }, legF: { foot: [0.5, 0.65], bend: -0.3 } });
    assert.ok(r.elbowF && r.wristF && r.kneeF && r.ankleF, "rig exposes actual joints");
    close(distance(r.shF, r.elbowF), r.upperArm, "upper arm");
    close(distance(r.elbowF, r.wristF), r.forearm, "forearm");
    close(distance(r.hipF, r.kneeF), r.thigh, "thigh");
    close(distance(r.kneeF, r.ankleF), r.shin, "shin");
  }
});

test("an unposed adapter person plants both soles at its placement origin", { skip }, () => {
  for (const child of [false, true]) {
    const r = toonRig(specFor({ child }), poseFor({}, false));
    close(r.footF[1], 0, "near sole");
    close(r.footB[1], 0, "far sole");
  }
});

test("walking knees remain continuous across zero hip swing", { skip }, () => {
  for (const field of ["legR", "legL"]) {
    const a = toonRig(spec, poseFor({ [field]: -0.001 }, false));
    const b = toonRig(spec, poseFor({ [field]: 0 }, false));
    const joint = field === "legR" ? "kneeF" : "kneeB";
    assert.ok(distance(a[joint], b[joint]) < 1, `${joint} must not snap`);
  }
});

test("the S11 far arm remains continuous through its full shoulder sweep", { skip }, () => {
  let previous;
  for (let angle = 20; angle <= 50; angle += 0.1) {
    const r = toonRig(spec, poseFor({ armL: [angle, 20] }, false));
    if (previous) assert.ok(distance(previous, r.elbowB) < 2, `far elbow snaps at ${angle}`);
    previous = r.elbowB;
  }
});

test("handPos matches rig and SVG placement for mirrored, leaning reaches", { skip }, () => {
  for (const side of [-1, 1]) for (const facing of [-1, 1]) for (const lean of [-14, 0, 16]) {
    const angles = [135, 25];
    const look = { outfit: "coat", hair: "bun", tone: 1, glasses: true };
    const pose = poseFor({ [side === 1 ? "armR" : "armL"]: angles, lean }, side === 1);
    const r = toonRig(specFor(look), pose);
    const expected = toonPoint(r, side === 1 ? "handF" : "handB", { x: 510, y: 820, scale: 1.1, facing, lean }, pose.chest);
    const actual = handPos(side, angles, 510, 820, 1.1, facing, lean, look);
    close(actual[0], expected[0], "hand x");
    close(actual[1], expected[1], "hand y");
    // Independent evaluation of SVG transform order: chest, facing, lean, place.
    const p = r[side === 1 ? "handF" : "handB"];
    const c = pose.chest * Math.PI / 180;
    const x = (p[0] * Math.cos(c) - (p[1] - r.hipY) * Math.sin(c)) * facing * 1.1;
    const y = (r.hipY + p[0] * Math.sin(c) + (p[1] - r.hipY) * Math.cos(c)) * 1.1;
    const a = lean * Math.PI / 180;
    close(actual[0], 510 + x * Math.cos(a) - y * Math.sin(a), "SVG x");
    close(actual[1], 820 + x * Math.sin(a) + y * Math.cos(a), "SVG y");
  }
});

// Evaluate the actual emitted SVG transforms, independently of toonPoint.
const identity = () => [1, 0, 0, 1, 0, 0];
const multiply = (p, q) => [
  p[0] * q[0] + p[2] * q[1], p[1] * q[0] + p[3] * q[1],
  p[0] * q[2] + p[2] * q[3], p[1] * q[2] + p[3] * q[3],
  p[0] * q[4] + p[2] * q[5] + p[4], p[1] * q[4] + p[3] * q[5] + p[5],
];
const translation = (x = 0, y = 0) => [1, 0, 0, 1, x, y];
const svgTransform = (text) => {
  let m = identity();
  for (const [, name, args] of text.matchAll(/(translate|scale|rotate)\(([^)]*)\)/g)) {
    const n = args.trim().split(/[ ,]+/).map(Number);
    let t;
    if (name === "translate") t = translation(n[0], n[1]);
    if (name === "scale") t = [n[0], 0, 0, n[1] ?? n[0], 0, 0];
    if (name === "rotate") {
      const a = n[0] * Math.PI / 180;
      t = multiply(multiply(translation(n[1], n[2]), [Math.cos(a), Math.sin(a), -Math.sin(a), Math.cos(a), 0, 0]), translation(-(n[1] ?? 0), -(n[2] ?? 0)));
    }
    m = multiply(m, t);
  }
  return m;
};
const probeOrigin = (svg) => {
  const stack = [{ tag: "root", matrix: identity() }];
  for (const [token, tag, attrs, selfClosing] of svg.matchAll(/<\/?([\w:-]+)\b([^>]*?)(\/?)>/g)) {
    if (token.startsWith("</")) { stack.pop(); continue; }
    const transform = /transform="([^"]+)"/.exec(attrs)?.[1] ?? "";
    const matrix = multiply(stack.at(-1).matrix, svgTransform(transform));
    if (attrs.includes('id="held-probe"')) return [matrix[4], matrix[5]];
    if (!selfClosing) stack.push({ tag, matrix });
  }
  throw new Error("missing prop probe");
};

test("the emitted prop group and the drawn palm share the rig anchor", { skip }, () => {
  for (const facing of [-1, 1]) for (const lean of [-15, 13]) for (const chest of [-9, 11]) {
    const pose = { lean, chest, armF: { hand: [0.6, -0.7], bend: 0.2, pose: "grip" } };
    const props = { x: 320, y: 880, scale: 1.23, facing, spec, pose };
    const r = toonRig(spec, pose);
    const actual = probeOrigin(renderProbe(props));
    const expected = toonPoint(r, "handF", { ...props, lean }, chest);
    close(actual[0], expected[0], "emitted prop x");
    close(actual[1], expected[1], "emitted prop y");
    for (const side of ["F", "B"]) {
      const grip = handShape("grip", r.handL, 1, side === "F" ? "near" : "far").grip.at;
      const wrist = r[`wrist${side}`];
      const dir = r[`dir${side}`];
      const palm = [wrist[0] + dir[0] * grip[0] - dir[1] * grip[1], wrist[1] + dir[1] * grip[0] + dir[0] * grip[1]];
      close(palm[0], r[`hand${side}`][0], "drawn palm x");
      close(palm[1], r[`hand${side}`][1], "drawn palm y");
    }
    // Negative control: a ten-unit prop drift must be caught by this check.
    const moved = renderProbe(props).replace('id="held-probe"', 'transform="translate(10 0)" id="held-probe"');
    assert.ok(distance(probeOrigin(moved), expected) > 10, "SVG probe detects a displaced prop");
  }
});
