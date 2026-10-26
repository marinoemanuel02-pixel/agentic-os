// The cast kit's pure part: skeleton in head units, limb outlines, poses, lip-sync, per-character face proportions.
// No React and no imports, so `node --test` can check the geometry directly (tools/checks/cast.test.mts).
// Drawing lives in Person.tsx; the design notes (what each choice comes from) are in its header.

/** Point at distance `len` from (x, y) at angle `deg` (0 = right, 90 = down). */
export const polar = (x: number, y: number, len: number, deg: number): [number, number] => [
  x + len * Math.cos((deg * Math.PI) / 180),
  y + len * Math.sin((deg * Math.PI) / 180),
];

/** A path through two points with radius r at each end (r2 at the second): a finger, a stalk. */
export const capsule = (x1: number, y1: number, x2: number, y2: number, r1: number, r2 = r1) => {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const l = Math.max(0.001, Math.hypot(dx, dy));
  const nx = -dy / l;
  const ny = dx / l;
  return `M ${x1 + nx * r1} ${y1 + ny * r1} L ${x2 + nx * r2} ${y2 + ny * r2} A ${r2} ${r2} 0 0 0 ${x2 - nx * r2} ${y2 - ny * r2} L ${x1 - nx * r1} ${y1 - ny * r1} A ${r1} ${r1} 0 0 0 ${x1 + nx * r1} ${y1 + ny * r1} Z`;
};

/** An ellipse as a path. */
export const ellipse = (cx: number, cy: number, rx: number, ry = rx) =>
  `M ${cx - rx} ${cy} a ${rx} ${ry} 0 1 0 ${rx * 2} 0 a ${rx} ${ry} 0 1 0 ${-rx * 2} 0 Z`;

/** A rounded rectangle as a path. */
export const rrect = (x: number, y: number, w: number, h: number, r: number) => {
  const q = Math.min(r, w / 2, h / 2);
  return `M ${x + q} ${y} H ${x + w - q} Q ${x + w} ${y} ${x + w} ${y + q} V ${y + h - q} Q ${x + w} ${y + h} ${x + w - q} ${y + h} H ${x + q} Q ${x} ${y + h} ${x} ${y + h - q} V ${y + q} Q ${x} ${y} ${x + q} ${y} Z`;
};

/** head unit: crown to chin, in local units */
export const H_UNIT = 72;

export type Outfit = "coat" | "suit" | "teal" | "mustard" | "brick" | "slate";

export type Hair = "short" | "bun" | "curly" | "bald" | "long" | "side" | "bob" | "pony";

export type HandPose = "relaxed" | "open" | "wave" | "support" | "point" | "fist" | "grip" | "hold";

export type MouthShape = "neutral" | "smile" | "frown" | "A" | "E" | "O" | "M" | "F" | "L" | "surprise";

export type Build = "slim" | "regular" | "broad";

export type HeadShape = "egg" | "round" | "square";

export type PersonPose = {
  /** degrees, the whole body about the feet (+ = leans right) */
  lean?: number;
  /** -0.12..0.12: + squashes, - stretches */
  squash?: number;
  /** head tilt in degrees */
  tilt?: number;
  /** head turn toward screen right (+) or left (-), -1..1 (1 = about 45 degrees): features shift for a 3/4 view */
  turn?: number;
  /** where the eyes look, -1..1 per axis */
  look?: [number, number];
  /** 0 open .. 1 closed */
  lids?: number;
  /** -1 worried .. 1 determined */
  brow?: number;
  /** -1 frown .. 1 smile */
  smile?: number;
  /** 0..1, a continuous open mouth (ignored when `mouth` names a shape) */
  mouthOpen?: number;
  /** a named mouth shape (viseme or expression); see `talk()` */
  mouth?: MouthShape;
  /** [shoulder, elbow] degrees. Shoulder 0 = hanging down, + = raised outward/forward. Elbow + bends outward/up. */
  armL?: [number, number];
  armR?: [number, number];
  /** hand shapes; the right hand defaults to "grip" when it holds something */
  handL?: HandPose;
  handR?: HandPose;
  /** hip swing degrees (+ forward) */
  legL?: number;
  legR?: number;
  /** knee bend degrees (+ folds the shin back); default follows the hip swing */
  kneeL?: number;
  kneeR?: number;
  /** wide eyes (fear, surprise) 0..1 */
  wide?: number;
  /** which arm is drawn in front of the torso (-1 left, 1 right); default: the near arm, or the one holding a prop */
  front?: -1 | 1;
};

// ---------------------------------------------------------------- colour helpers
export const hex = (c: string) => {
  const h = c.replace("#", "");
  const n = parseInt(h.length === 3 ? h.split("").map((x) => x + x).join("") : h, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
};

export const mix = (c: string, to: string, k: number) => {
  const a = hex(c);
  const b = hex(to);
  const v = a.map((x, i) => Math.round(x + (b[i] - x) * k));
  return `#${v.map((x) => x.toString(16).padStart(2, "0")).join("")}`;
};

/** The outline colour of a fill: the same hue, much darker (coloured ink, never black). */
export const ink = (c: string) => mix(c, "#140f22", 0.62);

// ---------------------------------------------------------------- skeleton (head units, H = 72)
/** ankle height above the sole */
export const FOOT = 14;

export type Body = {
  child: boolean;
  /** width factor (shoulders, hips, torso) */
  b: number;
  /** limb thickness factor */
  w: number;
  hs: number;
  hipY: number;
  hipX: number;
  shY: number;
  shX: number;
  collarY: number;
  chinY: number;
  headY: number;
  upper: number;
  fore: number;
  thigh: number;
  shin: number;
  /** hand scale */
  hand: number;
};

export const body = (build: Build = "regular", child = false): Body => {
  const k = child ? 0.74 : 1;
  const b = (build === "slim" ? 0.9 : build === "broad" ? 1.14 : 1) * (child ? 0.8 : 1);
  const w = (build === "slim" ? 0.88 : build === "broad" ? 1.16 : 1) * (child ? 0.85 : 1);
  const thigh = 80 * k;
  const shin = 76 * k;
  const hipY = -FOOT - thigh - shin;
  const shY = hipY - 126 * k;
  const collarY = shY - 18 * (child ? 0.75 : 1);
  const chinY = collarY - 8 * k;
  const hs = child ? 1.24 : 1;
  return { child, b, w, hs, hipY, hipX: 18 * b, shY, shX: 42 * b, collarY, chinY, headY: chinY - 36 * hs, upper: 68 * k, fore: 61 * k, thigh, shin, hand: child ? 0.82 : 0.94 };
};

/** Shoulder, elbow and wrist of one arm in body coordinates. */
export const armJoints = (bd: Body, side: -1 | 1, a: [number, number]) => {
  const sx = side * (bd.shX - 2);
  const sy = bd.shY + 5;
  const d1 = 90 - side * a[0];
  const [ex, ey] = polar(sx, sy, bd.upper, d1);
  // a relaxed elbow always keeps a little bend, so resting arms never read as straight sticks
  const d2 = d1 - side * (a[1] + 10);
  const [wx, wy] = polar(ex, ey, bd.fore, d2);
  return { sx, sy, ex, ey, wx, wy, d1, d2 };
};

/** where a held prop sits, along the hand from the wrist (hand units) */
export const GRIP = 13;

/** Where a hand grips, in the parent's coordinates (same maths as the arm), so props and leashes attach to it. */
export const handPos = (
  side: -1 | 1,
  a: [number, number],
  x: number,
  y: number,
  scale = 1,
  facing: 1 | -1 = 1,
  lean = 0,
  opts: { build?: Build; child?: boolean } = {},
): [number, number] => {
  const bd = body(opts.build, opts.child);
  const j = armJoints(bd, side, a);
  const [hx, hy] = polar(j.wx, j.wy, GRIP * bd.hand, j.d2);
  const lx = hx * facing;
  const ly = hy;
  const r = (lean * Math.PI) / 180;
  return [x + scale * (lx * Math.cos(r) - ly * Math.sin(r)), y + scale * (lx * Math.sin(r) + ly * Math.cos(r))];
};

// ---------------------------------------------------------------- tapered limb ("hose")
export type Pt = [number, number];

export const sub = (a: Pt, b: Pt): Pt => [a[0] - b[0], a[1] - b[1]];

export const len = (a: Pt) => Math.hypot(a[0], a[1]) || 1e-6;

export const nrm = (a: Pt): Pt => [a[0] / len(a), a[1] / len(a)];

export const f2 = (p: Pt) => `${p[0].toFixed(2)} ${p[1].toFixed(2)}`;

/**
 * A filled limb through three joints with widths at each: the joint is a rounded corner (radius `bend`, never
 * tighter than the limb's half width, so the inside never folds over itself) and the limb swells a little at a bent
 * joint, like a hose that keeps its volume; the ends are round caps. Returns an SVG path.
 */
export const limbPath = (p0: Pt, p1: Pt, p2: Pt, w0: number, w1: number, w2: number, bend = 26, flatEnd = false) => {
  const d1 = nrm(sub(p1, p0));
  const d2 = nrm(sub(p2, p1));
  const turnK = Math.min(1, Math.acos(Math.max(-1, Math.min(1, d1[0] * d2[0] + d1[1] * d2[1]))) / (Math.PI / 2));
  const r = Math.min(Math.max(bend, w1 * 0.5 + 3), len(sub(p1, p0)) * 0.45, len(sub(p2, p1)) * 0.45);
  const a: Pt = [p1[0] - d1[0] * r, p1[1] - d1[1] * r];
  const b: Pt = [p1[0] + d2[0] * r, p1[1] + d2[1] * r];
  const spine: Pt[] = [];
  const N = 10;
  for (let i = 0; i <= N; i++) spine.push([p0[0] + (a[0] - p0[0]) * (i / N), p0[1] + (a[1] - p0[1]) * (i / N)]);
  for (let i = 1; i <= N; i++) {
    const t = i / N;
    const u = 1 - t;
    spine.push([u * u * a[0] + 2 * u * t * p1[0] + t * t * b[0], u * u * a[1] + 2 * u * t * p1[1] + t * t * b[1]]);
  }
  for (let i = 1; i <= N; i++) spine.push([b[0] + (p2[0] - b[0]) * (i / N), b[1] + (p2[1] - b[1]) * (i / N)]);
  const n = spine.length;
  const mid = N + N / 2;
  const wj = w1 * (1 + 0.1 * turnK);
  // width along the spine: w0 -> wj at the joint (middle of the corner) -> w2, eased so the taper reads as muscle
  const width = (i: number) => {
    if (i <= mid) {
      const t = i / mid;
      return w0 + (wj - w0) * (t * t * (3 - 2 * t));
    }
    const t = (i - mid) / (n - 1 - mid);
    return wj + (w2 - wj) * t;
  };
  const left: Pt[] = [];
  const right: Pt[] = [];
  for (let i = 0; i < n; i++) {
    const p = spine[i];
    const q = spine[Math.min(n - 1, i + 1)];
    const o = spine[Math.max(0, i - 1)];
    const t = nrm(sub(q, o));
    const w = width(i) / 2;
    left.push([p[0] - t[1] * w, p[1] + t[0] * w]);
    right.push([p[0] + t[1] * w, p[1] - t[0] * w]);
  }
  const e = w2 / 2;
  const s = w0 / 2;
  return `M ${f2(left[0])} L ${left.slice(1).map(f2).join(" L ")} ${flatEnd ? "L" : `A ${e} ${e} 0 0 0`} ${f2(right[n - 1])} L ${right
    .slice(0, -1)
    .reverse()
    .map(f2)
    .join(" L ")} A ${s} ${s} 0 0 0 ${f2(left[0])} Z`;
};

/** A sleeve or band along p0 -> p1: a rounded cap at p0, a straight hem at p1. */
export const bandPath = (p0: Pt, p1: Pt, r0: number, r1: number) => {
  const d = nrm(sub(p1, p0));
  const nx = -d[1];
  const ny = d[0];
  const A: Pt = [p0[0] + nx * r0, p0[1] + ny * r0];
  const B: Pt = [p1[0] + nx * r1, p1[1] + ny * r1];
  const C: Pt = [p1[0] - nx * r1, p1[1] - ny * r1];
  const D: Pt = [p0[0] - nx * r0, p0[1] - ny * r0];
  const back: Pt = [p0[0] - d[0] * r0, p0[1] - d[1] * r0];
  return `M ${f2(A)} L ${f2(B)} L ${f2(C)} L ${f2(D)} Q ${f2([D[0] - d[0] * r0, D[1] - d[1] * r0])} ${f2(back)} Q ${f2([A[0] - d[0] * r0, A[1] - d[1] * r0])} ${f2(A)} Z`;
};

// ---------------------------------------------------------------- head (local: centre 0,0, crown -37, chin +36)
export const headPath = (shape: HeadShape, j: number, jw = 1) =>
  shape === "round"
    ? `M 0 -37 C 20 -37 31 -23 31 -3 C 31 18 ${17 * jw + j} 35 ${j} 35 C ${-17 * jw + j} 35 -31 18 -31 -3 C -31 -23 -20 -37 0 -37 Z`
    : shape === "square"
      ? `M 0 -37 C 20 -37 30 -25 30 -6 L ${30 * jw} 12 C ${30 * jw} 26 ${18 * jw + j} 35 ${2 + j} 36 C ${-14 * jw + j} 36 ${-29 * jw} 27 ${-29 * jw} 12 L -30 -6 C -30 -25 -20 -37 0 -37 Z`
      : `M 0 -37 C 19 -37 30 -24 30 -5 C 30 11 ${24 * jw + j} 26 ${8 * jw + j} 34 C ${3 * jw + j} 37 ${-4 * jw + j} 37 ${-9 * jw + j} 34 C ${-24 * jw} 27 -30 12 -30 -5 C -30 -24 -19 -37 0 -37 Z`;

/** The hair that frames the face, as paths (also used for the fringe's shadow on the forehead). */
export const hairFront = (kind: Hair, t: number): string[] => {
  switch (kind) {
    case "bald":
      return [`M -30 -15 C -32 -7 -31 1 -28.5 6 C -27.8 0 -27.6 -7 -27.5 -13 Z`, `M 30 -15 C 32 -7 31 1 28.5 6 C 27.8 0 27.6 -7 27.5 -13 Z`];
    case "curly":
      return [
        `M -32 0 C -34 -26 -20 -44 0 -44 C 20 -44 34 -26 32 0 C 29 -14 18 -22 ${t} -21 C -18 -22 -29 -14 -32 0 Z`,
        ...[196, 218, 242, 266, 290, 314, 338].map((ang, i) => {
          const [cx, cy] = polar(t * 0.4, -8, 33, ang);
          return ellipse(cx, cy, 11 + (i % 2), 10.5);
        }),
      ];
    case "long":
      return [`M -32 8 C -37 -24 -20 -46 0 -46 C 21 -46 37 -24 32 8 C 29 -9 22 -23 ${3 + t} -30 C ${-13 + t} -23 -27 -11 -32 8 Z`];
    case "side":
      return [`M -31 1 C -36 -22 -23 -45 1 -46 C 25 -47 38 -30 32 -1 C 30 -11 27 -17 23 -21 C ${12 + t} -11 ${-10 + t} -12 -23 -21 C -27 -15 -29 -8 -31 1 Z`];
    case "bob":
      return [`M -34 22 C -39 -20 -22 -46 0 -46 C 22 -46 39 -20 34 22 C 31 12 30 0 28 -16 C 10 -13 -10 -13 -28 -16 C -30 0 -31 12 -34 22 Z`];
    case "bun":
    case "pony":
      return [`M -31 -1 C -33 -28 -18 -44 0 -44 C 18 -44 33 -28 31 -1 C 29 -13 22 -22 ${8 + t} -25 C ${-2 + t} -28 -18 -25 -26 -16 C -29 -11 -30 -6 -31 -1 Z`];
    case "short":
    default:
      return [`M -31 3 C -35 -12 -34 -28 -23 -38 C -12 -46 12 -47 23 -40 C 34 -33 35 -16 31 3 C 29 -6 28 -13 25 -19 C ${15 + t} -19 ${5 + t} -22 ${-2 + t} -28 C ${-8 + t} -21 -17 -18 -25 -18 C -28 -12 -29 -5 -31 3 Z`];
  }
};

// ---------------------------------------------------------------- pose library and helpers
/** Starting poses (facing right); spread one into `pose` and override what the shot needs. */
export const POSES: Record<"stand" | "attentive" | "explain" | "point" | "hold" | "concern" | "reassure" | "wave", PersonPose> = {
  stand: { armL: [8, 6], armR: [8, 6], smile: 0.2 },
  attentive: { lean: 3, tilt: 4, armL: [8, 6], armR: [18, 30], handR: "open", brow: 0.2, smile: 0.3 },
  explain: { lean: 2, armR: [42, 28], handR: "support", armL: [10, -34], handL: "relaxed", smile: 0.4, mouth: "E" },
  point: { lean: -2, armR: [72, 8], handR: "point", armL: [8, 6], brow: 0.5, smile: 0.1 },
  hold: { armR: [22, 62], handR: "grip", armL: [8, 6] },
  concern: { tilt: -5, armL: [4, -46], armR: [4, -46], handL: "fist", handR: "fist", brow: -0.7, smile: -0.3 },
  reassure: { lean: 4, tilt: 5, armR: [46, 16], handR: "support", armL: [8, 6], smile: 0.6, brow: -0.1 },
  wave: { armR: [140, 34], handR: "wave", armL: [8, 6], smile: 0.8, mouth: "A" },
};

/** A walk cycle (phase in turns, amp in degrees): legs, knees that lift on the swing, arms opposite, a small lean. */
export const walk = (phase: number, amp = 22): PersonPose => {
  const p = phase * Math.PI * 2;
  const sw = Math.sin(p);
  const c = Math.cos(p);
  return {
    lean: 4,
    legL: amp * sw,
    legR: -amp * sw,
    kneeL: 6 + 26 * Math.max(0, c),
    kneeR: 6 + 26 * Math.max(0, -c),
    armL: [8 + amp * 0.7 * sw, 18],
    armR: [8 + amp * 0.7 * sw, 18],
  };
};

/** Lip-sync chatter: a deterministic sequence of mouth shapes, one every 4 frames. */
export const talk = (f: number, seed = 0): MouthShape => {
  const seq: MouthShape[] = ["A", "M", "E", "O", "L", "A", "F", "E", "M", "O", "neutral", "A"];
  return seq[(Math.floor(f / 4) + seed * 7) % seq.length];
};

/** A crowd of small people, deterministic, for scale shots. Each entry: x, y, scale, outfit, hair, tone, build. */
export const crowdSpec = (n: number, seed: number, x0: number, x1: number, y0: number, y1: number) => {
  let s = seed >>> 0;
  const r = () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
  const outs: Outfit[] = ["teal", "mustard", "brick", "slate", "coat"];
  const hairs: Hair[] = ["short", "bun", "curly", "long", "side", "bald", "bob", "pony"];
  const builds: Build[] = ["slim", "regular", "broad"];
  return Array.from({ length: n }, () => {
    const y = y0 + r() * (y1 - y0);
    return {
      x: x0 + r() * (x1 - x0),
      y,
      scale: 0.18 + ((y - y0) / Math.max(1, y1 - y0)) * 0.12,
      outfit: outs[Math.floor(r() * outs.length)],
      hair: hairs[Math.floor(r() * hairs.length)],
      tone: Math.floor(r() * 4) as 0 | 1 | 2 | 3,
      hairTone: Math.floor(r() * 4) as 0 | 1 | 2 | 3,
      phase: r(),
      facing: (r() > 0.5 ? 1 : -1) as 1 | -1,
      build: builds[Math.floor(r() * builds.length)],
    };
  }).sort((a, b) => a.y - b.y);
};

/** Per-character face proportions, so the cast is not one face with different hair. */
export type Face = { eyeGap: number; eyeSize: number; jaw: number; nose: number };

/** A stable identity from a character's look (any string): eye spacing +-0.05H, eye size, jaw width +-0.08, nose length. */
export const faceFor = (key: string): Face => {
  const seed = [...key].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7);
  const v = (k: number) => (((seed >>> (k * 5)) & 31) / 31) * 2 - 1;
  return { eyeGap: 11.5 + v(0) * 3.5, eyeSize: 1 + v(1) * 0.12, jaw: 1 + v(2) * 0.08, nose: 1 + v(3) * 0.28 };
};
