// The cast kit's geometry (src/lib/cast/geom.ts): limb outlines, proportions in head units, hand attachment, poses,
// lip-sync and per-character faces. Pure maths, so a regression shows here before it shows in a frame.
import assert from "node:assert/strict";
import { test } from "node:test";
import { armJoints, body, faceFor, GRIP, H_UNIT, handPos, handTilt, limbPath, polar, talk, walk } from "../../src/lib/cast/geom.ts";

type Seg = { cmd: string; n: number[] };
const parse = (d: string): Seg[] =>
  [...d.matchAll(/([MLAZ])([^MLAZ]*)/g)].map((m) => ({ cmd: m[1], n: m[2].trim() ? m[2].trim().split(/[\s,]+/).map(Number) : [] }));

/** The midpoint of an SVG circular arc from p to the arc's end point (endpoint parameterisation, no rotation). */
const arcMid = (p: [number, number], a: number[]): [number, number] => {
  const [r, , , large, sweep, x2, y2] = a;
  const [x1, y1] = p;
  const hx = (x1 - x2) / 2;
  const hy = (y1 - y2) / 2;
  const sign = large !== sweep ? 1 : -1;
  const k = sign * Math.sqrt(Math.max(0, (r * r - hx * hx - hy * hy) / (hx * hx + hy * hy)));
  const cx = k * hy + (x1 + x2) / 2;
  const cy = -k * hx + (y1 + y2) / 2;
  const t1 = Math.atan2(y1 - cy, x1 - cx);
  let dt = Math.atan2(y2 - cy, x2 - cx) - t1;
  if (sweep === 0 && dt > 0) dt -= 2 * Math.PI;
  if (sweep === 1 && dt < 0) dt += 2 * Math.PI;
  return [cx + r * Math.cos(t1 + dt / 2), cy + r * Math.sin(t1 + dt / 2)];
};

/** The end caps of a limb path: [cap at the tip, cap at the root], as arc midpoints. */
const caps = (d: string) => {
  const segs = parse(d);
  let at: [number, number] = [0, 0];
  const mids: [number, number][] = [];
  for (const s of segs) {
    if (s.cmd === "A") {
      mids.push(arcMid(at, s.n));
      at = [s.n[5], s.n[6]];
    } else if (s.cmd !== "Z") at = [s.n[0], s.n[1]];
  }
  return mids;
};

test("limb end caps bulge outward, past the tip and behind the root (a reversed sweep draws a notch)", () => {
  const straight = limbPath([0, 0], [0, 60], [0, 120], 20, 16, 12);
  const [tip, root] = caps(straight);
  assert.ok(tip[1] > 120 + 4, `tip cap at y=${tip[1].toFixed(1)} should be below the tip`);
  assert.ok(root[1] < -6, `root cap at y=${root[1].toFixed(1)} should be above the root`);
  const bent = limbPath([0, 0], [0, 60], [60, 60], 20, 16, 12);
  assert.ok(caps(bent)[0][0] > 60 + 4, "a bent limb's tip cap points along the forearm");
});

test("a limb bent hard stays finite and closed; flat ends replace the tip cap with a straight hem", () => {
  for (const deg of [0, 45, 90, 150, 175]) {
    const [x, y] = polar(0, 60, 60, 90 - deg);
    const d = limbPath([0, 0], [0, 60], [x, y], 24, 18, 14);
    assert.ok(!/NaN|Infinity/.test(d), `bend ${deg}`);
    assert.ok(d.trim().endsWith("Z"));
  }
  const hem = limbPath([0, 0], [0, 60], [0, 120], 30, 23, 21, 26, true);
  assert.equal(caps(hem).length, 1, "only the root keeps its round cap");
});

test("proportions in head units: about 5.5H tall, a short visible neck; a child has a relatively larger head", () => {
  const ratio = (child: boolean) => {
    const b = body("regular", child);
    const crown = b.headY - 37 * b.hs;
    return { tall: -crown / (H_UNIT * b.hs), neck: (b.collarY - b.chinY) / H_UNIT };
  };
  const adult = ratio(false);
  assert.ok(adult.tall >= 5 && adult.tall <= 6, `adult ${adult.tall.toFixed(2)}H`);
  assert.ok(adult.neck >= 0.08 && adult.neck <= 0.18, `neck ${adult.neck.toFixed(2)}H`);
  assert.ok(ratio(true).tall < adult.tall - 0.8, "child in fewer heads");
  const broad = body("broad");
  const slim = body("slim");
  assert.ok(broad.shX > body().shX && body().shX > slim.shX && broad.w > slim.w, "builds change the silhouette");
});

test("handPos is the grip point of the drawn arm, mirrored by facing and scaled", () => {
  const a: [number, number] = [30, 40];
  const b = body();
  const j = armJoints(b, 1, a);
  const [gx, gy] = polar(j.wx, j.wy, GRIP * b.hand, j.d2);
  const [hx, hy] = handPos(1, a, 100, 200, 2, 1, 0);
  assert.ok(Math.abs(hx - (100 + 2 * gx)) < 1e-9 && Math.abs(hy - (200 + 2 * gy)) < 1e-9);
  const [mx] = handPos(1, a, 0, 0, 1, -1, 0);
  assert.ok(Math.abs(mx + gx) < 1e-9, "facing -1 mirrors x");
  const [cx] = handPos(1, a, 0, 0, 1, 1, 0, { child: true });
  assert.notEqual(cx, gx, "a child's arm is shorter");
});

test("handPos follows the drawn hand: a relaxed hand's tilt toward the body, and the pose's squash (Codex review)", () => {
  const a: [number, number] = [20, 10];
  const b = body();
  for (const side of [-1, 1] as const) {
    const j = armJoints(b, side, a);
    const [gx, gy] = polar(j.wx, j.wy, GRIP * b.hand, j.d2 + handTilt("relaxed", side));
    const [hx, hy] = handPos(side, a, 0, 0, 1, 1, 0, { hand: "relaxed" });
    assert.ok(Math.abs(hx - gx) < 1e-9 && Math.abs(hy - gy) < 1e-9, `side ${side}`);
  }
  assert.notEqual(handTilt("relaxed", 1), 0);
  assert.equal(handTilt("grip", 1), 0, "a gripping hand follows the forearm");
  const [px, py] = handPos(1, a, 0, 0);
  const [sx, sy] = handPos(1, a, 0, 0, 1, 1, 0, { squash: 0.1 });
  assert.ok(Math.abs(sx - px * 1.1) < 1e-9 && Math.abs(sy - py * 0.9) < 1e-9, "squash scales x by 1+s and y by 1-s");
});

test("walk: legs swing opposite, the swinging knee lifts, arms counter-swing", () => {
  const p = walk(0.25, 20);
  assert.equal(p.legL, 20);
  assert.equal(p.legR, -20);
  for (const ph of [0, 0.1, 0.5, 0.9]) {
    const q = walk(ph);
    assert.ok((q.kneeL ?? 0) >= 6 && (q.kneeR ?? 0) >= 6, "knees never lock straight");
  }
  assert.ok((walk(0).kneeL ?? 0) > (walk(0).kneeR ?? 0), "the leg moving forward is the one that lifts");
  // arm angles are "raised outward": + on the left arm (side -1) swings it back, + on the right arm swings it forward,
  // so each arm swings opposite to the leg on its own side
  for (const ph of [0.25, 0.75]) {
    const q = walk(ph, 20);
    const back = (q.armL?.[0] ?? 0) - 8;
    const fwd = (q.armR?.[0] ?? 0) - 8;
    assert.ok(Math.sign(back) === Math.sign(q.legL ?? 0) && back !== 0, `left arm back while the left leg is forward (phase ${ph})`);
    assert.ok(Math.sign(fwd) === Math.sign(q.legL ?? 0) && fwd !== 0, `right arm forward with the left leg (phase ${ph})`);
  }
});

test("talk is deterministic, changes every few frames and varies with the seed", () => {
  assert.equal(talk(37, 2), talk(37, 2));
  const shapes = new Set(Array.from({ length: 48 }, (_, f) => talk(f)));
  assert.ok(shapes.size >= 5, `${shapes.size} mouth shapes in 48 frames`);
  assert.notEqual(talk(0, 0), talk(0, 1));
});

test("faces vary per character and stay stable for the same look", () => {
  assert.deepEqual(faceFor("short01teal"), faceFor("short01teal"));
  const keys = ["short01teal", "bob32slate", "curly21mustard", "bald10suit", "long30brick", "side13coat", "pony03teal", "bun22coat"];
  const faces = keys.map(faceFor);
  assert.ok(new Set(faces.map((f) => JSON.stringify(f))).size === keys.length, "no two looks share a face");
  for (const f of faces) {
    assert.ok(f.eyeGap >= 8 && f.eyeGap <= 15 && f.eyeSize >= 0.88 && f.eyeSize <= 1.12 && f.jaw >= 0.92 && f.jaw <= 1.08 && f.nose >= 0.72 && f.nose <= 1.28);
  }
});
