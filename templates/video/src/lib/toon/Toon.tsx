// Parametric B cast: approved profile masters, flat clothes and thin even ink.
// A single fixed-segment rig supplies the drawn joints and every prop anchor.
// Shoulder elevation and protraction happen before IK; sleeve caps and the torso
// share those moving roots, eliminating the old stationary shoulder corners.
import React from "react";
import type { Pt } from "./pt";
import { handShape, type HandPose } from "./hands";
import { ToonHead, type Identity } from "./ToonHead";

export const LINE = "#172124";
export const PAPER = "#d0d1bf";
export const SKIN = {
  fair: ["#c3c7b5", "#818b79"],
  light: ["#b9b7a4", "#7f8775"],
  tan: ["#a29d87", "#757d6a"],
  brown: ["#898b78", "#646f5e"],
  deep: ["#747c6b", "#536354"],
} as const;
export type Skin = keyof typeof SKIN;
export type Hair = "bob" | "pony" | "bun" | "short" | "curly" | "long" | "bald" | "side" | "crop";
export type Outfit = "coat" | "suit" | "shirt" | "tee" | "dress" | "overalls" | "sweater" | "jacket";
export type Nose = "hook" | "round" | "long" | "button";
export type ToonSpec = {
  height?: number;
  build?: number;
  head?: "egg" | "long" | "broad" | "round";
  shoulders?: number;
  legs?: number;
  skin: Skin;
  hair: Hair;
  hairColor: string;
  outfit: Outfit;
  top: string;
  bottom: string;
  shoes?: string;
  under?: string;
  accent?: string;
  tie?: boolean;
  sleeves?: "long" | "short";
  glasses?: "round" | "square";
  beard?: boolean;
  blush?: boolean;
  lashes?: boolean;
  nose?: Nose;
  identity?: Identity;
  child?: boolean;
};
/** bend is the signed joint pole; target distance determines flexion. */
export type Arm = { hand: Pt; bend?: number; grip?: boolean; pose?: HandPose };
export type Leg = { foot: Pt; bend?: number };
export type ToonPose = {
  lean?: number;
  tilt?: number;
  nod?: number;
  look?: Pt;
  lid?: number;
  brow?: number;
  browSkew?: number;
  smile?: number;
  skew?: number;
  open?: number;
  /** Palm targets in arm lengths, relative to each moving shoulder. */
  armF?: Arm;
  armB?: Arm;
  /** Sole targets in leg lengths, relative to each hip. */
  legF?: Leg;
  legB?: Leg;
  breath?: number;
  chest?: number;
  hip?: number;
  shrug?: number;
  /** the front hip drops this much (in 600-unit adult units) when that leg relaxes and the weight is on the other */
  hipDrop?: number;
  /** the same for the back hip, when the weight is on the front leg */
  hipDropB?: number;
};

const STAND = {
  armF: { hand: [0.08, 0.98], bend: -0.06 } as Arm,
  armB: { hand: [-0.07, 0.98], bend: 0.06 } as Arm,
  legF: { foot: [0.07, 1], bend: -0.02 } as Leg,
  legB: { foot: [-0.08, 1], bend: 0.02 } as Leg,
};
const clamp = (x: number, a: number, b: number) => Math.max(a, Math.min(b, x));
const add = (a: Pt, b: Pt): Pt => [a[0] + b[0], a[1] + b[1]];
const mul = (a: Pt, n: number): Pt => [a[0] * n, a[1] * n];
const mix = (a: Pt, b: Pt, t: number): Pt => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
const unit = (a: Pt, b: Pt): Pt => {
  const d = Math.hypot(b[0] - a[0], b[1] - a[1]);
  return d < 1e-8 ? [0, 1] : [(b[0] - a[0]) / d, (b[1] - a[1]) / d];
};
const normal = (v: Pt): Pt => [-v[1], v[0]];
const xy = (p: Pt) => `${p[0]} ${p[1]}`;

/** Two rigid segments; impossible targets clamp to reach instead of stretching. */
const chain = (root: Pt, target: Pt, upper: number, lower: number, bend: number) => {
  const d = clamp(Math.hypot(target[0] - root[0], target[1] - root[1]), Math.abs(upper - lower) + 0.01, upper + lower - 0.01);
  const u = unit(root, target);
  const n = normal(u);
  const along = (upper * upper - lower * lower + d * d) / (2 * d);
  const across = Math.sqrt(Math.max(0, upper * upper - along * along)) * (bend < 0 ? -1 : 1);
  return { joint: add(root, add(mul(u, along), mul(n, across))), end: add(root, mul(u, d)) };
};

/** All drawing coordinates before placement/lean/chest rotation. Feet stand at y=0. */
export const toonRig = (spec: Pick<ToonSpec, "height" | "build" | "head" | "shoulders" | "legs" | "child">, pose: ToonPose = {}) => {
  const Ht = spec.height ?? 520;
  const child = spec.child ?? Ht < 420;
  const k = Ht / (child ? 380 : 600);
  const b = spec.build ?? 0.3;
  const headH = (child ? 70 : 76) * k;
  const headW = (child ? 64 : spec.head === "broad" ? 80 : 72) * k;
  const legLen = Ht * (spec.legs ?? (child ? 0.44 : 0.49));
  const hipY = -legLen;
  const shY = -Ht + (child ? 102 : 118) * k - (pose.breath ?? 0);
  const torso = hipY - shY;
  const neck = (child ? 25 : 40) * k;
  const chinY = shY - neck;
  const sw = (child ? 94 : 126 + b * 24) * k * (spec.shoulders ?? 1);
  const hw = (child ? 65 : 84 + b * 25) * k;
  const armW = (child ? 23 : 29 + b * 8) * k;
  const wristW = (child ? 9.5 : 12 + b * 1.5) * k;
  const legW = (child ? 26 : 37 + b * 10) * k;
  const ankleW = (child ? 17 : 22 + b * 3) * k;
  const upperArm = (child ? 58 : 94 + b * 3) * k;
  const forearm = (child ? 56 : 89 + b * 2) * k;
  // a quarter bigger than v16, then a third more in v18 (blind reviews: "tiny hands"); the palm offset follows it
  const handL = (child ? 42 : 57) * k;
  const palmOffset = handL * 0.43;
  const armLen = upperArm + forearm + palmOffset;
  const shoeH = (child ? 16 : 21) * k;
  const legReach = legLen - shoeH + 0.5 * k;
  const thigh = legReach * 0.49;
  const shin = legReach * 0.51;
  const hipShift = (pose.hip ?? 0) * hw * 0.35;
  const shrug = pose.shrug ?? 0;
  const armF = pose.armF ?? STAND.armF;
  const armB = pose.armB ?? STAND.armB;
  const legF = pose.legF ?? STAND.legF;
  const legB = pose.legB ?? STAND.legB;
  const shoulder = (a: Arm, front: boolean): Pt => {
    const u = unit([0, 0], a.hand);
    const elevation = (1 - u[1]) * 0.5;
    const across = front ? Math.max(0, -u[0]) : Math.max(0, u[0]);
    // The clavicle rotates up with the reach and slides toward it. An across-body
    // reach rolls inward gently; the far shoulder retains its visible back edge.
    return [(front ? sw * 0.34 : -sw * 0.46) + u[0] * 10 * k + (front ? -1 : 1) * across * armW * 0.3,
      shY + (front ? 15 : 13) * k - (25 * elevation + shrug * 10) * k];
  };
  const shF = shoulder(armF, true);
  const shB = shoulder(armB, false);
  // the far arm hangs behind the body; a low far arm must stay at least half visible past the back's outline, never
  // tucked under the torso with only a hand showing (operator on v16)
  const waistY = hipY - torso * 0.3;
  const backEdge = (y: number) =>
    y <= waistY ? -sw * 0.46 - armW * 0.5 + ((y - shY) / (waistY - shY)) * (sw * 0.46 + armW * 0.5 - hw * 0.48) : -hw * 0.56;
  const solveArm = (sh: Pt, a: Arm, front: boolean) => {
    let target = add(sh, mul(a.hand, armLen));
    if (!front && target[1] > sh[1] + armLen * 0.25) {
      // swing the arm back about the shoulder (same reach, so the elbow does not fold into a hand-on-hip)
      const R = Math.hypot(target[0] - sh[0], target[1] - sh[1]);
      const x = Math.min(target[0], backEdge(target[1]) + hipShift - armW * 0.25);
      if (x < target[0] && Math.abs(x - sh[0]) < R) target = [x, sh[1] + Math.sqrt(R * R - (x - sh[0]) ** 2)];
    }
    // First find the forearm direction, then back the palm off along that exact
    // direction. This keeps the palm centre on the requested target when reachable.
    const preliminary = chain(sh, target, upperArm, forearm + palmOffset, a.bend ?? (front ? -1 : 1));
    const direction = unit(preliminary.joint, preliminary.end);
    const solved = chain(sh, add(preliminary.end, mul(direction, -palmOffset)), upperArm, forearm, a.bend ?? (front ? -1 : 1));
    const dir = unit(solved.joint, solved.end);
    return { elbow: solved.joint, wrist: solved.end, hand: add(solved.end, mul(dir, palmOffset)), dir };
  };
  const af = solveArm(shF, armF, true);
  const ab = solveArm(shB, armB, false);
  const hipF: Pt = [hw * 0.23 + hipShift, hipY + (pose.hipDrop ?? 0) * k];
  const hipB: Pt = [-hw * 0.27 + hipShift, hipY + (pose.hipDropB ?? 0) * k];
  const solveLeg = (hip: Pt, l: Leg, front: boolean) => {
    const foot = add(hip, [l.foot[0] * legLen, l.foot[1] * legLen]);
    // a sole never goes below the floor: a dropped hip bends that knee instead
    foot[1] = Math.min(foot[1], 0);
    const solved = chain(hip, add(foot, [0, -shoeH]), thigh, shin, l.bend ?? (front ? -1 : 1));
    return { knee: solved.joint, ankle: solved.end, foot: add(solved.end, [0, shoeH]) };
  };
  const lf = solveLeg(hipF, legF, true);
  const lb = solveLeg(hipB, legB, false);
  const tilt = pose.tilt ?? 0;
  const headRoot: Pt = [0, -Ht + (pose.nod ?? 0) * headH * 0.1 - (pose.breath ?? 0)];
  const tiltRad = tilt * Math.PI / 180;
  const pivotY = child ? 101 : 118;
  const head: Pt = [(-6 + 6 * Math.cos(tiltRad) - (44 - pivotY) * Math.sin(tiltRad)) * k,
    headRoot[1] + (pivotY + 6 * Math.sin(tiltRad) + (44 - pivotY) * Math.cos(tiltRad)) * k];
  const chest: Pt = [sw * 0.08, shY + torso * 0.42];
  return {
    k, b, Ht, child, headH, headW, legLen, torso, neck, hipY, shY, chinY, sw, hw, armW, wristW, legW, ankleW,
    armLen, handL, upperArm, forearm, thigh, shin, shoeH, palmOffset, hipShift, shrug, tilt, head, headRoot, chest,
    shF, shB, hipF, hipB, armF, armB, legF, legB,
    elbowF: af.elbow, wristF: af.wrist, handF: af.hand, dirF: af.dir,
    elbowB: ab.elbow, wristB: ab.wrist, handB: ab.hand, dirB: ab.dir,
    kneeF: lf.knee, ankleF: lf.ankle, footF: lf.foot,
    kneeB: lb.knee, ankleB: lb.ankle, footB: lb.foot,
  };
};
export type ToonRig = ReturnType<typeof toonRig>;

/** Mirrors and rotates in exactly the same order as the SVG placement groups. */
export const toonPoint = (rig: ToonRig, which: "handF" | "handB" | "head" | "chest", place: { x: number; y: number; scale: number; facing?: 1 | -1; lean?: number }, chest = 0): Pt => {
  const p0: Pt = rig[which];
  const cb = chest * Math.PI / 180;
  const p: Pt = [p0[0] * Math.cos(cb) - (p0[1] - rig.hipY) * Math.sin(cb), rig.hipY + p0[0] * Math.sin(cb) + (p0[1] - rig.hipY) * Math.cos(cb)];
  const a = (place.lean ?? 0) * Math.PI / 180;
  const x = p[0] * place.scale * (place.facing ?? 1);
  const y = p[1] * place.scale;
  return [place.x + x * Math.cos(a) - y * Math.sin(a), place.y + x * Math.sin(a) + y * Math.cos(a)];
};

/** Tapered straight segments joined by an elbow/knee with a defined point outside and a soft fold inside (blind review
 * of v17: elbows were "sharp corners" or "broad tube bends"). A straight limb has the same plain join on both sides, so
 * the shape stays continuous while the joint swings through straight. */
const limbPath = (a: Pt, j: Pt, b: Pt, w0: number, wj: number, w1: number, cap = 0.42) => {
  const u = unit(a, j);
  const v = unit(j, b);
  const n = normal(u);
  const m = normal(v);
  const bisector = unit([0, 0], add(n, m));
  const dot = Math.max(0.2, bisector[0] * n[0] + bisector[1] * n[1]);
  const miter = wj * 0.5 / dot;
  // how bent the joint is (0 straight, 1 at about a right angle), and which side is the outside: the limb turns toward
  // +n when cross > 0, so then the L side (+n) is the inside
  const cross = u[0] * v[1] - u[1] * v[0];
  const t = clamp(Math.abs(cross) / 0.7, 0, 1);
  const outsideL = cross <= 0;
  const plain = { radius: Math.min(miter, wj * 0.8), corner: 0.12 };
  // outside: the full miter (the elbow's point) with a tight round; inside: pulled in short of the miter, a long soft fold
  const sharp = { radius: Math.min(miter * 0.82, wj * 0.86), corner: 0.2 };
  const fold = { radius: wj * 0.5 * (1 - 0.18 * t), corner: 0.26 };
  const side = (outside: boolean) => {
    const s = outside ? sharp : fold;
    return { radius: plain.radius + (s.radius - plain.radius) * t, corner: plain.corner + (s.corner - plain.corner) * t };
  };
  const L = side(outsideL);
  const R = side(!outsideL);
  const aL = add(a, mul(n, w0 * 0.5));
  const aR = add(a, mul(n, -w0 * 0.5));
  const jL = add(j, mul(bisector, L.radius));
  const jR = add(j, mul(bisector, -R.radius));
  // the forearm/shin carries its width a little past the joint before it tapers to the wrist/ankle
  const swell = (sign: number) => add(mix(j, b, 0.3), mul(m, sign * wj * 0.5 * 1.08));
  const bL = add(b, mul(m, w1 * 0.5));
  const bR = add(b, mul(m, -w1 * 0.5));
  const sL = swell(1);
  const sR = swell(-1);
  return `M${xy(aL)} L${xy(mix(aL, jL, 1 - L.corner))} Q${xy(jL)} ${xy(mix(jL, sL, L.corner * 1.6))} Q${xy(sL)} ${xy(mix(sL, bL, 0.5))} L${xy(bL)} L${xy(bR)} L${xy(mix(sR, bR, 0.5))} Q${xy(sR)} ${xy(mix(jR, sR, R.corner * 1.6))} Q${xy(jR)} ${xy(mix(jR, aR, R.corner))} L${xy(aR)} Q${xy(add(a, mul(u, -w0 * cap)))} ${xy(aL)}Z`;
};

/** A limb's outline without its closing edge at the root (the last command, a Q back to the start, then Z). */
const openLimb = (d: string) => d.slice(0, d.lastIndexOf(" Q"));

const JointCrease: React.FC<{ a: Pt; joint: Pt; end: Pt; width: number }> = ({ a, joint, end, width }) => {
  const u = unit(a, joint);
  const v = unit(joint, end);
  const cross = u[0] * v[1] - u[1] * v[0];
  if (Math.abs(cross) < 0.18) return null;
  const edge = add(joint, mul(normal(v), (cross > 0 ? 1 : -1) * width * 0.38));
  return <path d={`M${xy(edge)} l${-v[0] * width * 0.28} ${-v[1] * width * 0.28}`} fill="none" strokeWidth={0.8} />;
};

/** The torso's dimensions, shared by its silhouette and its details. */
const torsoFrame = (r: ToonRig, spec: ToonSpec) => {
  const { k, hw, shY, hipY, torso: T } = r;
  const o = spec.outfit;
  const coat = o === "coat";
  return {
    coat,
    tailored: coat || o === "suit" || o === "jacket",
    hem: hipY + (coat ? T * 0.29 : o === "dress" ? T * 0.65 : T * 0.05),
    waist: hipY - T * 0.3,
    hemW: hw * (coat ? 1.15 : o === "dress" ? 1.5 : 1.02),
    left: -22 * k,
    right: 10 * k,
    // the neck's base rises with a shrug, so raised shoulders stay one line with it
    top: shY - 2 * k - r.shrug * 9 * k - Math.max(0, shY + 13 * k - Math.min(r.shF[1], r.shB[1])) * 0.16,
    closure: -6 * k,
    lapelY: shY + T * (coat ? 0.43 : 0.55),
  };
};

/** A clavicle flows into a tapered upper arm, with no closed shoulder socket.
 * The open sleeve end fills implicitly but never inks a transverse cap seam. */
const deltoid = (r: ToonRig, spec: ToonSpec, front: boolean) => {
  const sh = front ? r.shF : r.shB;
  const elbow = front ? r.elbowF : r.elbowB;
  const side = front ? 1 : -1;
  const u = unit(sh, elbow);
  const n = mul(normal(u), -side);
  const { left, right, top } = torsoFrame(r, spec);
  const neck: Pt = [front ? right : left, top];
  const crown = add(add(sh, mul(n, r.armW * 0.5)), mul(u, -r.armW * 0.12));
  const end = mix(sh, elbow, 0.43);
  const outer = add(end, mul(n, r.armW * 0.46));
  const inner = add(end, mul(n, -r.armW * 0.46));
  // the armpit sits under the arm, on the side away from the crown, so it moves round to the outside as the arm goes
  // overhead (fixed beside the chest it left a flap between the raised arm and the torso)
  // it lies on the arm's inner edge, so the torso's side meets the underside of the arm there and no line crosses the
  // sleeve
  const innerRoot = add(sh, mul(n, -r.armW * 0.46));
  const along = r.armW * (0.4 + 0.42 * Math.max(0, u[1]));
  const pit = add(innerRoot, mul(u, along));
  const inboard: Pt = [sh[0] - side * r.armW * 0.48, sh[1] - r.armW * 0.36];
  const outerEdge = `M${xy(neck)} C${neck[0] + (crown[0] - neck[0]) * 0.52} ${neck[1]} ${xy(add(crown, mul(u, -r.armW * 0.32)))} ${xy(crown)} Q${xy(add(crown, mul(u, r.armW * 0.3)))} ${xy(outer)}`;
  // the arm's inner edge continues straight back along the arm to the shoulder; a seam from it to the armpit cut
  // across the sleeve whenever the arm hung or reached back (operator on v18: "manica antiestetica e non naturale")
  const innerEdge = `M${xy(inner)} L${xy(pit)}`;
  return {
    crown, pit,
    path: `${outerEdge} M${xy(neck)} L${xy(inboard)} L${xy(pit)} L${xy(inner)} L${xy(outer)}`,
    // the cover hides the sleeve's start and the torso's line under the shoulder, and stays inside the arm's edges
    cover: `M${xy(inboard)} L${xy(crown)} Q${xy(add(crown, mul(u, r.armW * 0.3)))} ${xy(outer)} L${xy(inner)} L${xy(pit)}Z`,
    edge: `${outerEdge} ${innerEdge}`,
    outerEdge,
    innerEdge,
  };
};

/** Torso and upper-arm tapers share the same moving clavicles. */
const torsoOutline = (r: ToonRig, spec: ToonSpec) => {
  const { k, hw, hipShift: hs } = r;
  const { hem, waist, hemW, left, right, top } = torsoFrame(r, spec);
  const back = deltoid(r, spec, false);
  const front = deltoid(r, spec, true);
  return `M${left} ${top} L${xy(back.crown)} L${xy(back.pit)} Q${-hw * 0.48 + hs} ${(back.pit[1] + waist) / 2} ${-hw * 0.48 + hs} ${waist} L${-hemW * 0.55 + hs} ${hem} Q${-hw * 0.1 + hs} ${hem + 6 * k} ${hw * 0.05 + hs} ${hem + 2 * k} L${hemW * 0.48 + hs} ${hem} L${hw * 0.43 + hs} ${waist} Q${hw * 0.43 + hs} ${(front.pit[1] + waist) / 2} ${xy(front.pit)} L${xy(front.crown)} L${right} ${top}Z`;
};

/** What the outfit draws on the torso: collars, lapels, ties, plackets, pockets, bibs. */
const Torso: React.FC<{ r: ToonRig; spec: ToonSpec }> = ({ r, spec }) => {
  const { k, sw, hw, shY, hipY, torso: T, hipShift: hs } = r;
  const o = spec.outfit;
  const { coat, tailored, hem, hemW, left, right, top, closure, lapelY } = torsoFrame(r, spec);
  return <g fill={spec.top}>
    {tailored ? <g>
      <path d={`M${left} ${top} L${right} ${top} L${22 * k} ${shY + T * 0.16} L${closure} ${lapelY} L${-36 * k} ${shY + T * 0.14}Z`} fill={spec.under ?? "#b9c1b5"} />
      {spec.tie ? <path d={`M${closure - 5 * k} ${shY + 17 * k} L${closure + 5 * k} ${shY + 16 * k} L${closure + 8 * k} ${shY + 25 * k} L${closure + 2 * k} ${shY + 31 * k} L${closure + 9 * k} ${lapelY - 16 * k} L${closure} ${lapelY - 2 * k} L${closure - 8 * k} ${lapelY - 17 * k} L${closure - 3 * k} ${shY + 31 * k} L${closure - 10 * k} ${shY + 25 * k}Z`} fill={spec.accent ?? "#795a56"} /> : null}
      <path d={`M${left} ${top} L${-42 * k} ${shY + 15 * k} L${-29 * k} ${shY + 38 * k} L${-37 * k} ${shY + 46 * k} L${closure} ${lapelY}Z`} />
      <path d={`M${right} ${top} L${30 * k} ${shY + 12 * k} L${22 * k} ${shY + 35 * k} L${30 * k} ${shY + 45 * k} L${closure} ${lapelY}Z`} />
      <path d={`M${closure} ${lapelY} L${closure + hs * 0.5} ${hem - 14 * k} M${hw * 0.1 + hs} ${hipY - 9 * k} l${hw * 0.23} ${-5 * k}`} fill="none" />
      {[0.65, 0.84].map((t) => <path key={t} d={`M${closure + hs * 0.5} ${shY + T * t} h${3 * k}`} />)}
      {coat ? <path d={`M${-hw * 0.52 + hs} ${hipY - 20 * k} h${hw * 0.28} l${-2 * k} ${24 * k} h${-hw * 0.28}`} fill="none" /> : null}
    </g> : <g>
      <path d={`M${left} ${top} Q${-4 * k} ${shY + 11 * k} ${right} ${top} L${20 * k} ${shY + 13 * k} Q${-5 * k} ${shY + 30 * k} ${-34 * k} ${shY + 12 * k}Z`} fill={spec.under ?? "#b9c1b5"} />
      <path d={`M${-hemW * 0.53 + hs} ${hem - 8 * k} Q${hs} ${hem - 3 * k} ${hemW * 0.48 + hs} ${hem - 8 * k}`} fill="none" />
    </g>}
    {o === "shirt" ? <path d={`M${closure} ${shY + 24 * k} L${closure} ${hem - 10 * k} M${-24 * k} ${shY} l${18 * k} ${22 * k} l${-18 * k} ${14 * k} M${10 * k} ${shY} l${-16 * k} ${22 * k} l${18 * k} ${12 * k}`} fill="none" /> : null}
    {o === "overalls" ? <g fill={spec.bottom}>
      <path d={`M${-sw * 0.35} ${shY + 8 * k} l${12 * k} ${-3 * k} L${-sw * 0.18} ${shY + T * 0.5} L${-sw * 0.3} ${shY + T * 0.52}Z M${sw * 0.27} ${shY + 5 * k} l${12 * k} ${4 * k} L${sw * 0.28} ${shY + T * 0.52} L${sw * 0.16} ${shY + T * 0.5}Z`} />
      <path d={`M${-sw * 0.21} ${shY + T * 0.43} L${sw * 0.22} ${shY + T * 0.43} L${hw * 0.52 + hs} ${hem} Q${hs} ${hem + 12 * k} ${-hw * 0.55 + hs} ${hem}Z`} />
      <path d={`M${-sw * 0.13} ${shY + T * 0.59} h${sw * 0.26} l${-2 * k} ${26 * k} h${-sw * 0.26}`} fill="none" />
      <circle cx={-sw * 0.21} cy={shY + T * 0.47} r={1.7 * k} fill={LINE} stroke="none" />
      <circle cx={sw * 0.22} cy={shY + T * 0.47} r={1.7 * k} fill={LINE} stroke="none" />
    </g> : null}
  </g>;
};

export const Toon: React.FC<{
  x: number; y: number; scale?: number; facing?: 1 | -1; spec: ToonSpec; pose?: ToonPose;
  holdF?: React.ReactNode; chestMark?: React.ReactNode; shadow?: boolean; outline?: boolean;
}> = ({ x, y, scale = 1, facing = 1, spec, pose = {}, holdF, chestMark, shadow = true, outline = false }) => {
  const r = toonRig(spec, pose);
  const [skin, shade] = SKIN[spec.skin];
  const w = 1.8 * r.k;
  const handSeed = [...(spec.hairColor + spec.top + spec.hair)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 997, 7);
  const uid = React.useId().replace(/[^a-zA-Z0-9]/g, "");
  const torso = torsoOutline(r, spec);
  const backShoulder = deltoid(r, spec, false);
  const body = [torso, deltoid(r, spec, true).path, backShoulder.path];
  // the far shoulder's region is filled with the body but not outlined: its closing edge ran across the far sleeve
  // (operator on v18: "manica antiestetica e non naturale"); its outer edge is inked after the fills
  const outlined = [torso, deltoid(r, spec, true).path];
  const longSleeves = (spec.sleeves ?? (["tee", "overalls", "dress"].includes(spec.outfit) ? "short" : "long")) === "long";
  const arm = (front: boolean) => {
    const sh = front ? r.shF : r.shB;
    const elbow = front ? r.elbowF : r.elbowB;
    const wrist = front ? r.wristF : r.wristB;
    const hand = front ? r.handF : r.handB;
    const dir = front ? r.dirF : r.dirB;
    const a = front ? r.armF : r.armB;
    const upperDir = unit(sh, elbow);
    const n = normal(upperDir);
    const capW = r.armW;
    const sleeveEnd = longSleeves ? wrist : mix(sh, elbow, 0.53);
    const sleeveJoint = longSleeves ? elbow : mix(sh, elbow, 0.25);
    const sleeveW = longSleeves ? r.wristW * 1.3 : r.armW * 0.9;
    // a stable variant per person and side, so two neighbours do not show the same relaxed hand
    const shape = handShape(a.pose ?? (a.grip ? "grip" : "relaxed"), r.handL, w * 0.7, front ? "near" : "far", handSeed + (front ? 0 : 1));
    const handTransform = `translate(${xy(wrist)}) rotate(${Math.atan2(dir[1], dir[0]) * 180 / Math.PI})`;
    const layer = (i: number) => shape.layers[i] ? <path key={i} d={shape.layers[i].d} fill={shape.layers[i].tone === "none" ? "none" : skin} strokeWidth={w * 0.72} /> : null;
    return <g data-arm={front ? "near" : "far"}>
      {!longSleeves ? <path d={limbPath(sh, elbow, wrist, r.armW * 0.76, r.armW * 0.66, r.wristW * 1.05)} fill={skin} /> : null}
      {/* the sleeve starts in the deltoid with a cap of the same radius, so its seam follows the shoulder */}
      {/* filled whole, but inked without its start edge: a line across the sleeve at the shoulder is never drawn */}
      <path d={limbPath(sh, sleeveJoint, sleeveEnd, capW, r.armW * 0.82, sleeveW, 0)} fill={spec.top} stroke="none" />
      {/* near the shoulder, where the near sleeve lies on the torso, it grows out of it: no edge is inked there */}
      <path d={openLimb(limbPath(sh, sleeveJoint, sleeveEnd, capW, r.armW * 0.82, sleeveW, 0))} fill="none" mask={front ? `url(#pit${uid})` : undefined} />
      <path d={deltoid(r, spec, front).cover} fill={spec.top} stroke="none" />
      <path d={deltoid(r, spec, front).outerEdge} fill="none" />
      <path d={deltoid(r, spec, front).innerEdge} fill="none" mask={front ? `url(#pit${uid})` : undefined} />
      {longSleeves ? <JointCrease a={sh} joint={elbow} end={wrist} width={r.armW} /> : null}
      <g transform={handTransform}>{layer(0)}</g>
      {front && holdF ? <g transform={`translate(${xy(hand)}) scale(${facing} 1)`} stroke="none">{holdF}</g> : null}
      <g transform={handTransform}>
        {shape.layers.slice(1).map((_, i) => layer(i + 1))}
      </g>
    </g>;
  };
  const leg = (front: boolean) => {
    const hip = front ? r.hipF : r.hipB;
    const knee = front ? r.kneeF : r.kneeB;
    const ankle = front ? r.ankleF : r.ankleB;
    const foot = front ? r.footF : r.footB;
    const [ax, ay] = ankle;
    const s = r.ankleW;
    const tilt = foot[1] < -r.k * 12 ? clamp(Math.atan2(ankle[0] - knee[0], ankle[1] - knee[1]) * -180 / Math.PI, -28, 32) : 0;
    return <g>
      <path d={limbPath(hip, knee, ankle, r.legW, r.legW * 0.78, s)} fill={spec.outfit === "dress" ? skin : spec.bottom} />
      <JointCrease a={hip} joint={knee} end={ankle} width={r.legW * 0.85} />
      <g transform={`rotate(${tilt} ${ax} ${ay})`} fill={spec.shoes ?? "#283136"}>
        <path d={`M${ax - s * 0.55} ${ay - 2 * r.k} L${ax + s * 0.48} ${ay - 1 * r.k} L${ax + s * 0.8} ${ay + r.shoeH * 0.55} L${ax + s * 1.85} ${ay + r.shoeH * 0.82} L${ax + s * 1.88} ${ay + r.shoeH} L${ax - s * 0.7} ${ay + r.shoeH} Q${ax - s * 0.7} ${ay + r.shoeH * 0.5} ${ax - s * 0.55} ${ay - 2 * r.k}Z`} />
      </g>
    </g>;
  };
  return <g transform={`translate(${x} ${y}) scale(${scale * facing} ${scale})`} stroke={LINE} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round">
    {outline ? <filter id={`ol${uid}`} x="-30%" y="-30%" width="160%" height="160%"><feMorphology in="SourceAlpha" operator="dilate" radius={3 * r.k} result="d" /><feFlood floodColor={PAPER} /><feComposite in2="d" operator="in" /><feMerge><feMergeNode /><feMergeNode in="SourceGraphic" /></feMerge></filter> : null}
    {shadow ? <ellipse cx={0} cy={2} rx={r.hw * 0.8} ry={4 * r.k} fill="#0b1024" stroke="none" opacity={0.3} /> : null}
    <g transform={`rotate(${(pose.lean ?? 0) * facing})`} filter={outline ? `url(#ol${uid})` : undefined}>
      {leg(false)}
      {leg(true)}
      {/* the pelvis tilts with the hips: the side over the relaxed leg sinks */}
      <path d={`M${r.hipB[0] - r.legW * 0.48} ${r.hipB[1] - 15 * r.k} L${r.hipF[0] + r.legW * 0.48} ${r.hipF[1] - 15 * r.k} L${r.hipF[0] + r.legW * 0.4} ${r.hipF[1] + 17 * r.k} L${r.hipShift} ${(r.hipF[1] + r.hipB[1]) / 2 + 27 * r.k} L${r.hipB[0] - r.legW * 0.4} ${r.hipB[1] + 17 * r.k}Z`} fill={spec.bottom} stroke="none" />
      <g transform={`rotate(${pose.chest ?? 0} 0 ${r.hipY})`}>
        {arm(false)}
        <g transform={`translate(${xy(r.headRoot)}) scale(${r.k}) rotate(${r.tilt} -6 ${r.child ? 101 : 118})`}>
          <ToonHead spec={spec} pose={pose} skin={skin} shade={shade} ink={LINE} />
        </g>
        {/* torso and deltoids are one silhouette: every outline first, then every fill over the inner seams */}
        {outlined.map((d, i) => <path key={`o${i}`} d={d} fill={LINE} strokeWidth={w * 2} />)}
        {body.map((d, i) => <path key={`f${i}`} d={d} fill={spec.top} stroke="none" />)}
        <path d={backShoulder.outerEdge} fill="none" />
        {/* the underside of the arm near the shoulder is inked only where it is off the torso */}
        <clipPath id={`shz${uid}`}>
          <circle cx={r.shF[0]} cy={r.shF[1]} r={r.upperArm * 0.42} />
        </clipPath>
        <mask id={`pit${uid}`} maskUnits="userSpaceOnUse" x={-4000} y={-4000} width={8000} height={8000}>
          <rect x={-4000} y={-4000} width={8000} height={8000} fill="#fff" stroke="none" />
          <path d={torso} fill="#000" stroke="none" clipPath={`url(#shz${uid})`} />
        </mask>
        <Torso r={r} spec={spec} />
        {chestMark ? <g transform={`translate(${xy(r.chest)}) scale(${facing} 1)`} stroke="none">{chestMark}</g> : null}
        {arm(true)}
      </g>
    </g>
  </g>;
};

/** Standalone sample specs; shots use the adapter's specFor. */
export const CAST: Record<string, ToonSpec> = {
  researcher: { skin: "fair", hair: "bun", hairColor: "#343e3b", outfit: "coat", top: PAPER, under: "#95876a", bottom: "#485364", glasses: "square", identity: "researcher" },
  lawmaker: { skin: "fair", hair: "side", hairColor: "#343e3b", outfit: "suit", top: "#586577", bottom: "#485364", tie: true, glasses: "square", identity: "lawmaker" },
  execA: { skin: "tan", hair: "short", hairColor: "#343e3b", outfit: "suit", top: "#303e43", bottom: "#485364", tie: true, identity: "executive" },
  execB: { skin: "light", hair: "bob", hairColor: "#343e3b", outfit: "jacket", top: "#795a56", bottom: "#303e43", identity: "woman" },
  worker: { skin: "tan", hair: "curly", hairColor: "#343e3b", outfit: "overalls", top: "#b9b7a4", bottom: "#586577", build: 0.7, beard: true, identity: "worker" },
  young: { skin: "fair", hair: "long", hairColor: "#a39e86", outfit: "sweater", top: "#526d68", bottom: "#303e43", identity: "young" },
  elder: { skin: "light", hair: "bald", hairColor: "#92998b", outfit: "coat", top: "#95876a", bottom: "#485364", glasses: "square", identity: "older" },
  child: { skin: "light", hair: "pony", hairColor: "#343e3b", outfit: "sweater", top: "#795a56", bottom: "#586577", height: 360, child: true, identity: "child" },
};
