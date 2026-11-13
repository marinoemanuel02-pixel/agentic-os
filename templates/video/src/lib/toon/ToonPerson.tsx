// The existing shot API adapted to the B cast. Angles become palm/sole targets;
// the same solved rig drives the person and handPos. Identities and muted colours
// follow B's approved sheets while retaining the shots' standing-height range.
import React from "react";
import { Toon, toonPoint, toonRig, type Hair as ToonHair, type Skin, type ToonPose, type ToonSpec } from "./Toon";
import type { HandPose as ToonHand } from "./hands";
import type { Build, Hair, HandPose, Outfit, PersonPose } from "../cast/Person";

const SKINS: Skin[] = ["fair", "light", "tan", "brown"];
const HAIR_COLORS = ["#343e3b", "#343e3b", "#596052", "#a39e86"];
// muted, from the film's night palette: people sit in the set; the hot colours belong to the danger and the pause
const SUITS = [
  ["#303e43", "#485364", "#414e61"],
  ["#414e61", "#485364", "#795a56"],
  ["#303e43", "#485364", "#414e61"],
  ["#586577", "#414e61", "#95876a"],
];
const FEMININE: Hair[] = ["bob", "pony", "bun", "long"];

/** A Person's look as a drawn cast member. */
export const specFor = (p: {
  outfit?: Outfit;
  hair?: Hair;
  tone?: 0 | 1 | 2 | 3;
  hairTone?: 0 | 1 | 2 | 3;
  glasses?: boolean;
  tie?: boolean;
  /** a plain tee in this colour (pull it into the film's muted family); the look for someone wearing a badge */
  tee?: string;
  build?: Build;
  child?: boolean;
  beard?: boolean;
}): ToonSpec => {
  const outfit = p.outfit ?? "teal";
  const tone = p.tone ?? 0;
  const hair = p.hair ?? "short";
  // bodies differ underneath: a stable pick per look (outfit, hair, tones)
  const key = (outfit.length * 7 + hair.length * 13 + tone * 5 + (p.hairTone ?? 0) * 3 + (p.tee ? 66 : 0)) % 12;
  const build = [0.3, 0.15, 0.55, 0.4][key % 4];
  const fem = FEMININE.includes(hair);
  const worker = !p.tee && outfit === "brick" && (p.beard || p.build === "broad");
  const identity = p.child ? "child" : hair === "bald" ? "older" : worker || p.beard ? "worker" :
    hair === "bun" ? "researcher" : hair === "long" || hair === "pony" ? "young" :
    hair === "bob" ? "woman" : outfit === "suit" ? "executive" : "lawmaker";
  const skin: Skin = SKINS[tone];
  const hairColor = hair === "bald" ? "#92998b" : hair === "long" ? "#a39e86" :
    hair === "bun" || hair === "bob" ? "#343e3b" : HAIR_COLORS[p.hairTone ?? 0];
  const jeans = identity === "woman" || identity === "young" ? "#303e43" : "#485364";
  let look: Pick<ToonSpec, "outfit" | "top" | "bottom" | "under" | "accent" | "tie">;
  if (p.tee) look = { outfit: "tee", top: p.tee, bottom: jeans };
  else if (p.child) look = { outfit: "sweater", top: "#795a56", bottom: "#586577" };
  else if (worker) look = { outfit: "overalls", top: "#b9b7a4", bottom: "#586577" };
  else if (outfit === "coat") look = { outfit: "coat", top: "#d0d1bf", under: "#95876a", bottom: jeans };
  else if (identity === "older") look = { outfit: "coat", top: "#95876a", bottom: jeans };
  else if (outfit === "suit" || outfit === "slate") {
    const [top, bottom, accent] = outfit === "slate" ? ["#586577", "#485364", "#795a56"] : SUITS[tone];
    look = { outfit: fem ? "jacket" : "suit", top: fem ? "#795a56" : top, bottom, accent, tie: p.tie || !fem };
  } else if (outfit === "mustard") look = { outfit: "sweater", top: hair === "long" ? "#526d68" : "#95876a", bottom: jeans };
  else if (outfit === "brick") look = { outfit: "jacket", top: "#795a56", bottom: jeans };
  else look = { outfit: "sweater", top: "#526d68", bottom: jeans };
  return {
    ...look,
    identity,
    child: p.child,
    skin,
    hair: hair as ToonHair,
    hairColor,
    glasses: p.glasses ? "square" : undefined,
    beard: p.beard,
    nose: identity === "executive" || identity === "older" ? "long" : identity === "researcher" ? "hook" : "button",
    build: p.build === "broad" ? 0.7 : p.build === "slim" ? 0.1 : build,
    head: p.child ? "round" : identity === "worker" ? "broad" : identity === "lawmaker" ? "long" : "egg",
    shoulders: identity === "worker" ? 1.12 : identity === "executive" || identity === "lawmaker" ? 1.05 : 1,
    legs: p.child ? 0.44 : 0.49,
    height: p.child ? 360 : 500 + ((key * 17) % 5) * 12,
  };
};

const rad = (d: number) => (d * Math.PI) / 180;

/** An old arm ([shoulder, elbow] degrees; 0 = hanging, + raises outward) as a hand position and elbow bow. */
const armOf = (a: [number, number] | undefined, side: 1 | -1, grip: boolean): { hand: [number, number]; bend: number; grip: boolean } => {
  const [s0, e] = a ?? [12, 14];
  // The old figure was frontal, so "outward" for the far arm meant sideways; seen in 3/4 that angle points the arm
  // straight back like a wing (operator on v15). A low far swing is halved; a raised far arm keeps its height.
  const s = side === -1 && s0 > 0 ? (s0 <= 60 ? s0 * 0.55 : s0 >= 110 ? s0 : 33 + ((s0 - 60) / 50) * (s0 - 33)) : s0;
  const d1 = 90 - side * s;
  // The forearm folds forward from a hanging far arm (its elbow back, so the arm stays visible past the back: operator
  // on v16) and up and forward from a raised one (its elbow under the reach). Between the two the fold passes through
  // a straight arm, so a swinging arm never snaps from one side to the other.
  const fold = side === -1 ? (s0 <= 70 ? 1 : s0 >= 110 ? -1 : 1 - (2 * (s0 - 70)) / 40) : 1;
  const d2 = d1 - (e + 10) * fold;
  const u1: [number, number] = [Math.cos(rad(d1)), Math.sin(rad(d1))];
  const u2: [number, number] = [Math.cos(rad(d2)), Math.sin(rad(d2))];
  const hand: [number, number] = [0.5 * u1[0] + 0.5 * u2[0], 0.5 * u1[1] + 0.5 * u2[1]];
  // in 3/4 the far arm swings mostly behind the body, so its reach toward screen left is damped
  if (side === -1) hand[0] *= 0.55;
  // the elbow goes to the side the folded arm puts it on (it changes side only where the arm is straight)
  const elbow = [0.5 * u1[0] * (side === -1 ? 0.55 : 1), 0.5 * u1[1]];
  const bend = side === -1 ? (hand[0] * elbow[1] - hand[1] * elbow[0] >= 0 ? 1 : -1) : 1;
  return { hand, bend, grip };
};
const HANDS: Record<HandPose, ToonHand> = { relaxed: "relaxed", open: "open", wave: "wave", support: "hold", point: "point", fist: "fist", grip: "grip", hold: "grip" };

/** An old hip swing (+ forward) and knee as a foot position and knee bow. */
const legOf = (swing: number | undefined, knee: number | undefined) => {
  const t = swing ?? 0;
  // a knee is never locked straight (blind review of v18: "rigid trouser legs, little knee articulation")
  const k = knee ?? Math.max(8, -t * 0.6);
  const foot: [number, number] = [Math.sin(rad(t)) * (1 - k / 400), Math.cos(rad(t)) * (1 - k / 300)];
  // A knee never changes its folding side when hip swing crosses zero.
  return { foot, bend: -1 };
};

const clamp = (x: number, a: number, b: number) => Math.max(a, Math.min(b, x));
const smooth = (x: number, a: number, b: number) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

/** How far the chest turns about the hips (degrees, + toward the facing side) to answer the arms (blind review of
 * v17: "the torso contributes little twist to either action", "shoulders, rib cage and hips remain neutral"). A
 * forward reach pulls the chest after the hand; an arm going overhead lifts the ribcage and arches it back, more when
 * both go up. Continuous in every angle, so animated arms never snap the body. */
const chestFor = (p: PersonPose) => {
  const sF = p.armR?.[0] ?? 12;
  const sB = p.armL?.[0] ?? 12;
  // the reach eases in from a hanging arm, so a swinging arm (S10's runners) rocks the chest smoothly instead of
  // holding it still and then starting it abruptly (the QA motion check read that as a snap)
  const reachF = smooth(sF, 0, 100) * (1 - smooth(sF, 110, 165));
  const reachB = smooth(sB, 0, 105) * (1 - smooth(sB, 110, 165));
  const upF = smooth(sF, 110, 170);
  const upB = smooth(sB, 100, 170);
  return 6 * reachF + 3 * reachB - 3 * upF - 4 * upB - 2 * upF * upB - (p.lean ?? 0) * 0.15 + 1.5;
};

export const poseFor = (p: PersonPose = {}, holding: boolean): ToonPose => {
  const open = p.mouth === "O" || p.mouth === "surprise" || p.mouth === "A" ? 0.8 : p.mouth === "E" ? 0.4 : (p.mouthOpen ?? 0);
  const smile = p.mouth === "smile" ? 0.8 : p.mouth === "frown" ? -0.6 : (p.smile ?? 0);
  const wide = p.wide ?? 0;
  const idle = p.legR === undefined && p.legL === undefined && p.kneeR === undefined && p.kneeL === undefined;
  // which hip drops: standing still the weight rests on the back leg; in a stride, on the more upright leg, and the
  // other side of the pelvis sinks in proportion (blind review of v17: "the pelvis gives little indication of
  // receiving his weight")
  const swingF = Math.abs(p.legR ?? 0) + (p.kneeR ?? 0) * 0.3;
  const swingB = Math.abs(p.legL ?? 0) + (p.kneeL ?? 0) * 0.3;
  const shift = idle ? 1 : clamp((swingF - swingB) / 14, -1, 1);
  return {
    lean: p.lean,
    // the pelvis slides over the supporting leg
    hip: -0.3 * shift,
    chest: chestFor(p),
    tilt: p.tilt,
    look: p.look ? [p.look[0], p.look[1]] : [0.5, 0],
    lid: Math.max(0.3 * (1 - wide * 0.9), p.lids ?? 0),
    brow: -(p.brow ?? 0),
    smile,
    open,
    // a flat prop (a phone) asks for "hold": the whole hand behind it, fingertips past its far edge; anything else
    // held closes the fingers around it
    armF: { ...armOf(p.armR, 1, false), pose: holding ? (p.handR === "hold" ? "cradle" : "grip") : HANDS[p.handR ?? "relaxed"] },
    armB: { ...armOf(p.armL, -1, false), pose: HANDS[p.handL ?? "relaxed"] },
    // standing still, the weight rests on the back leg and the front one relaxes, knee forward, foot ahead (blind
    // review of v16: "long, nearly straight legs with weak knee articulation", "little weight shift")
    legF: idle ? { foot: [0.12, 1], bend: -1 } : legOf(p.legR, p.kneeR),
    legB: idle ? { foot: [-0.05, 1], bend: -1 } : legOf(p.legL, p.kneeL),
    hipDrop: Math.max(0, shift) * 13,
    hipDropB: Math.max(0, -shift) * 13,
  };
};

/** Where a hand grips, in the parent's coordinates (the old handPos signature, plus the person's look so the body
 * template and the chest bend match the drawn person). */
export const handPos = (
  side: -1 | 1,
  a: [number, number],
  x: number,
  y: number,
  scale = 1,
  facing: 1 | -1 = 1,
  lean = 0,
  look: Parameters<typeof specFor>[0] = {},
  /** the person's whole pose, so the chest answers the other arm and the legs exactly as in the drawn person */
  whole: PersonPose = {},
): [number, number] => {
  const pose = poseFor(side === 1 ? { ...whole, armR: a, lean } : { ...whole, armL: a, lean }, side === 1);
  const r = toonRig(specFor(look), pose);
  return toonPoint(r, side === 1 ? "handF" : "handB", { x, y, scale, facing, lean }, pose.chest ?? 0);
};

export const Person: React.FC<{
  x: number;
  y: number;
  scale?: number;
  facing?: 1 | -1;
  outfit?: Outfit;
  hair?: Hair;
  tone?: 0 | 1 | 2 | 3;
  hairTone?: 0 | 1 | 2 | 3;
  pose?: PersonPose;
  shadow?: boolean;
  rim?: string;
  glasses?: boolean;
  tie?: boolean;
  beard?: boolean;
  tee?: string;
  /** drawn on the chest, centred at 0,0 (the film used a round badge of radius 20), where a logo or badge sits */
  badge?: React.ReactNode;
  shirt?: [string, string];
  hold?: React.ReactNode;
  t?: number;
  build?: Build;
  child?: boolean;
}> = ({ x, y, scale = 1, facing = 1, pose, shadow = true, hold, badge, ...look }) => {
  const spec = specFor(look);
  return (
    <Toon
      x={x}
      y={y}
      scale={scale}
      facing={facing}
      spec={spec}
      pose={poseFor(pose, !!hold)}
      shadow={shadow}
      holdF={hold}
      chestMark={badge}
    />
  );
};
