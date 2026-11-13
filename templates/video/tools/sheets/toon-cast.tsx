// Film looks through the production adapter, B expressions and six acted poses.
import React from "react";
import { Toon, toonRig, type ToonPose, type ToonSpec } from "../../src/lib/toon/Toon";
import { specFor } from "../../src/lib/toon/ToonPerson";

const CAST: Record<string, ToonSpec> = {
  researcher: specFor({ outfit: "coat", hair: "bun", tone: 1, hairTone: 2, glasses: true }),
  lawmaker: specFor({ outfit: "slate", hair: "side", tone: 0, hairTone: 1, glasses: true, tie: true }),
  execA: specFor({ outfit: "suit", hair: "short", tone: 2, hairTone: 0 }),
  execB: specFor({ outfit: "suit", hair: "bob", tone: 0, hairTone: 3 }),
  worker: specFor({ outfit: "brick", hair: "curly", tone: 3, hairTone: 0, beard: true, build: "broad" }),
  young: specFor({ outfit: "mustard", hair: "long", tone: 1, hairTone: 1 }),
  elder: specFor({ outfit: "teal", hair: "bald", tone: 0, hairTone: 0, glasses: true }),
  child: specFor({ outfit: "teal", hair: "pony", tone: 1, hairTone: 1, child: true }),
};
const FACES: ToonPose[] = [
  { lid: 0.3, brow: 0, smile: 0 },
  { lid: 0.15, brow: 0.9, smile: -0.5, look: [0.6, -0.4] },
  { lid: 0, brow: 1, open: 0.9, look: [0.5, -0.8] },
  { lid: 0.5, brow: -0.4, browSkew: 1, smile: -0.2, skew: 0.8, look: [0.8, 0] },
];
const POSES: [string, string, ToonPose][] = [
  ["researcher", "Holding the line", { hip: -0.35, chest: -4, armF: { hand: [0.9, 0.02], bend: 0.1, pose: "grip" }, armB: { hand: [-0.05, 0.92], bend: 0.1 }, legF: { foot: [0.12, 1], bend: -0.04 }, legB: { foot: [-0.12, 1], bend: 0.02 }, look: [0.8, 0.2], brow: 0.3 }],
  ["researcher", "Losing balance", { lean: 10, chest: 6, shrug: 0.5, armF: { hand: [0.55, -0.8], bend: 0.05, pose: "grip" }, armB: { hand: [-0.65, 0.35], bend: -0.25, pose: "open" }, legF: { foot: [0.3, 0.95], bend: -0.08 }, legB: { foot: [-0.3, 0.9], bend: 0.18 }, look: [0.6, -0.9], lid: 0, brow: 1, open: 0.7 }],
  ["lawmaker", "Explaining", { hip: 0.3, chest: 3, armF: { hand: [0.62, 0.05], bend: 0.2, pose: "open" }, armB: { hand: [-0.08, 0.95], bend: 0.05 }, look: [0.6, 0], smile: 0.4 }],
  ["execA", "A doubtful shrug", { shrug: 1, chest: -3, tilt: -6, armF: { hand: [0.5, 0.12], bend: 0.45, pose: "open" }, armB: { hand: [-0.48, 0.15], bend: -0.45, pose: "open" }, look: [0.2, 0], lid: 0.5, brow: 0.6, browSkew: 0.6, smile: -0.3, skew: 0.6 }],
  ["young", "Reaching forward", { lean: 4, hip: -0.4, chest: 4, armF: { hand: [0.94, -0.2], bend: 0.04, pose: "point" }, armB: { hand: [-0.2, 0.8], bend: -0.1, pose: "fist" }, legF: { foot: [0.3, 0.96], bend: -0.05 }, legB: { foot: [-0.18, 0.98], bend: 0.05 }, look: [1, -0.2], lid: 0.1, brow: -0.6, open: 0.35 }],
  ["lawmaker", "Running with a book", { lean: 14, chest: 4, armF: { hand: [-0.12, 0.5], bend: -0.35, pose: "grip" }, armB: { hand: [0.45, 0.05], bend: 0.4, pose: "fist" }, legF: { foot: [0.55, 0.75], bend: -0.3 }, legB: { foot: [-0.5, 0.78], bend: 0.3 }, look: [1, 0], brow: 0.6, open: 0.5 }],
];

export default function CastSheet() {
  return <svg width={1920} height={2900} viewBox="0 0 1920 2900">
    <rect width={1920} height={2900} fill="#1c2244" />
    <g fill="#b9c0b5" fontFamily="Arial, sans-serif">
      <text x={65} y={75} fontSize={30}>Toon cast (src/lib/toon)</text>
      <text x={65} y={115} fontSize={18}>Profile faces, long exposed necks, flat clothes and articulated limbs</text>
      <text x={65} y={185} fontSize={17}>01 / Film looks</text>
      <rect y={900} width={1920} height={60} fill="#161a33" />
      {Object.entries(CAST).map(([role, spec], i) => <g key={role}>
        <Toon x={120 + i * 230} y={900} scale={1.1} spec={spec} pose={{ look: [0.5, 0] }} />
        <text x={120 + i * 230} y={940} fontSize={16} textAnchor="middle">{role}</text>
      </g>)}
      <text x={65} y={995} fontSize={17}>02 / Same contour, four expressions</text>
      {["Neutral", "Worried", "Shocked", "Sceptical"].map((name, j) => <text key={name} x={j * 480 + 210} y={1030} fontSize={16} textAnchor="middle">{name}</text>)}
      {["researcher", "lawmaker", "young", "worker"].map((role, i) => FACES.map((pose, j) => {
        const top = 1045 + i * 255;
        return <g key={`${role}-${j}`}>
          <clipPath id={`c${i}${j}`}><rect x={j * 480 + 8} y={top} width={464} height={245} /></clipPath>
          <g clipPath={`url(#c${i}${j})`}>
            <Toon x={j * 480 + 205} y={top + 90 - 2.6 * toonRig(CAST[role], pose).head[1]} scale={2.6} spec={CAST[role]} pose={pose} shadow={false} />
          </g>
        </g>;
      }))}
      <text x={65} y={2150} fontSize={17}>03 / Weight, resistance and conversation</text>
      <rect y={2820} width={1920} height={80} fill="#161a33" />
      {POSES.map(([role, label, pose], i) => <g key={label}>
        <Toon x={i === 5 ? 1690 : 155 + i * 315} y={2820} scale={0.9} spec={CAST[role]} pose={pose}
          holdF={i < 2 ? <path d={i === 0 ? "M0 0 L90 -36" : "M0 0 L60 -95"} stroke="#aa9c7f" strokeWidth={2} /> : i === 5 ? <g stroke="#172124" strokeWidth={1.8}>
            <path d="M-18 -48 L26 -42 L23 16 L-22 10Z" fill="#95876a" />
            <path d="M-13 -42 L21 -37 L18 10 L-17 5Z" fill="#d0d1bf" />
          </g> : undefined} />
        <text x={155 + i * 315} y={2860} fontSize={16} textAnchor="middle">{label}</text>
      </g>)}
    </g>
  </svg>;
}
