// B's hands: a broad wrist, a quiet palm and grouped, unequal fingers.
// Master coordinates: wrist (0,0), fingers +x, thumb -y; far reflects y.
// Layer 0 sits behind a prop; the remaining fingers and thumb close over it.
// The prop axis stays at (43,0), matching Toon's existing palm offset.
import type { Pt } from "./pt";

export type HandPose = "relaxed" | "open" | "point" | "fist" | "grip" | "pinch" | "stop" | "thumb" | "wave" | "hold" | "cradle";
export type HandLayer = { d: string; tone: "skin" | "shade" | "none"; ink: string };
export type HandDraw = { layers: HandLayer[]; grip?: { at: Pt; angle: number } };

type Drawing = { outline: string; front?: string[]; marks?: string; palm?: string };

// The resting fingers touch: small changes in tip height suggest the curl,
// rather than cutting four deep slots into the hand. The thumb rests on index.
const REST: Drawing[] = [
  {
    outline: `M-4 -16 Q14 -16 27 -20 Q42 -24 55 -17 L84 -8 Q96 -4 97 2 Q98 7 92 9 Q98 12 94 18 Q92 22 85 22 Q87 27 80 29 Q74 31 65 26 L48 22 Q35 24 24 19 L-4 16Z`,
    front: [`M23 -18 Q34 -29 45 -25 L64 -14 Q70 -10 67 -5 Q64 -1 58 -5 L43 -13 Q37 -10 34 -4`],
    marks: `M91 9 Q77 6 66 3 M85 22 L65 15`,
  },
  {
    outline: `M-4 -16 Q15 -17 28 -19 Q43 -21 56 -13 L81 2 Q91 8 89 14 Q88 18 83 18 Q87 24 81 28 Q77 31 72 28 Q73 34 67 35 Q61 35 54 29 L42 23 Q32 23 23 18 L-4 16Z`,
    front: [`M22 -17 Q35 -26 45 -20 L61 -7 Q66 -2 62 2 Q58 6 53 1 L40 -10 Q36 -8 34 -2`],
    marks: `M83 18 L64 9 M72 28 L57 18`,
  },
];

const DRAWINGS: Record<Exclude<HandPose, "relaxed">, Drawing> = {
  open: {
    outline: `M-4 -16 Q14 -16 28 -18 L43 -30 Q49 -34 53 -29 Q55 -25 49 -21 L43 -17 Q56 -19 68 -12 L92 -6 Q102 -3 100 2 Q99 6 93 5 Q103 7 101 12 Q100 16 94 15 Q96 19 91 22 Q87 24 81 22 Q82 27 76 28 Q71 29 66 25 L46 17 Q33 21 24 17 L-4 16Z`,
    marks: `M43 -17 Q35 -12 37 -3 M93 5 L77 0 M94 15 L76 9 M81 22 L68 16`,
    palm: `M47 5 Q55 -1 65 1`,
  },
  point: {
    outline: `M-4 -16 Q15 -17 29 -21 Q42 -24 55 -22 L96 -23 Q105 -23 105 -17 Q105 -12 97 -12 L62 -10 Q69 -5 70 2 Q73 8 68 12 Q70 18 64 22 Q60 28 50 26 L29 19 L-4 16Z`,
    front: [`M21 -17 Q29 -28 39 -25 L57 -15 Q64 -11 61 -6 Q59 -2 53 -5 L39 -13 L33 -5`],
    marks: `M67 12 L53 9 M64 22 L51 18`,
  },
  fist: {
    outline: `M-4 -16 L22 -20 Q30 -30 40 -28 Q47 -34 55 -28 Q65 -29 69 -20 Q77 -18 77 -8 L76 15 Q73 29 60 31 L39 29 Q29 25 22 19 L-4 16Z`,
    front: [`M20 -18 Q27 -30 37 -26 L60 -12 Q66 -8 63 -2 Q60 3 53 -1 L36 -11 Q32 -5 31 2`],
    marks: `M65 3 L65 15 M54 9 L54 22 M43 10 L43 21`,
  },
  grip: {
    outline: `M-4 -16 Q15 -18 25 -23 Q40 -30 54 -24 L64 -20 Q73 -16 74 -7 L72 17 Q70 29 59 32 L36 31 Q28 30 22 19 L-4 16Z`,
    // Four fingertips cross the cylinder, with knuckles on its far edge.
    // The shaft emerges above and below them on x=43, not beside the palm.
    front: [
      `M64 -20 Q73 -16 74 -7 L72 17 Q70 29 59 32 L36 31 Q29 30 29 24 Q29 20 35 19 L50 18 L31 17 Q24 16 24 10 Q24 5 30 5 L50 5 L27 3 Q21 1 22 -5 Q23 -10 29 -10 L52 -8 L32 -11 Q26 -14 28 -19 Q30 -24 36 -22Z`,
      `M18 -17 Q27 -34 39 -33 Q45 -33 51 -27 L64 -14 Q69 -9 65 -4 Q61 1 55 -4 L40 -17 Q31 -13 29 -3`,
    ],
  },
  pinch: {
    outline: `M-4 -16 L24 -20 Q40 -35 58 -37 Q74 -38 86 -28 Q95 -21 89 -12 Q84 -5 71 -2 L72 7 Q78 14 71 20 Q64 28 52 27 L26 19 L-4 16Z M48 -17 Q54 -8 64 -11 L76 -15 Q81 -17 76 -21 L64 -26 Q54 -29 48 -17Z`,
    marks: `M27 -17 Q37 -15 48 -17 M71 -2 Q64 1 56 -1 M70 11 L57 7 M67 21 L54 16`,
  },
  stop: {
    outline: `M-4 -16 L21 -20 L34 -45 Q38 -53 44 -50 Q49 -47 46 -39 L43 -27 L87 -33 Q97 -34 98 -28 Q99 -24 95 -22 Q104 -24 105 -17 Q106 -11 99 -10 Q105 -9 104 -2 Q104 4 97 5 Q100 8 97 14 Q95 19 86 19 L58 21 Q40 26 24 18 L-4 16Z`,
    marks: `M43 -27 Q31 -14 35 -3 M95 -22 L67 -18 M99 -10 L67 -6 M97 5 L66 6`,
    palm: `M44 6 Q48 -4 58 -5`,
  },
  thumb: {
    outline: `M-4 -16 L21 -20 Q29 -26 34 -42 L37 -62 Q38 -70 44 -69 Q50 -68 50 -60 L49 -40 Q49 -30 44 -23 L61 -23 Q70 -23 72 -15 Q79 -12 78 -4 L76 17 Q73 29 61 31 L39 28 L23 19 L-4 16Z`,
    marks: `M44 -23 Q37 -14 38 -4 M72 -8 L54 -9 M74 4 L55 3 M71 16 L54 14`,
  },
  wave: {
    outline: `M-4 -16 L22 -22 L32 -48 Q35 -56 41 -53 Q46 -51 43 -43 L39 -28 L65 -56 Q71 -63 76 -58 Q80 -54 75 -48 L58 -25 L94 -43 Q102 -47 105 -41 Q107 -36 100 -32 L65 -12 L103 -18 Q112 -19 112 -13 Q112 -8 104 -6 L67 0 L95 12 Q103 15 100 21 Q97 26 90 22 L58 11 Q43 24 26 18 L-4 16Z`,
    marks: `M39 -28 Q30 -14 35 -4`,
    palm: `M43 6 Q48 -4 58 -4`,
  },
  hold: {
    outline: `M-4 -16 Q15 -18 28 -10 L45 4 L83 5 Q94 6 97 12 Q98 18 88 19 L63 20 L86 24 Q93 26 89 31 Q84 36 70 32 L51 28 Q36 25 25 20 L-4 16Z`,
    front: [`M14 -13 Q21 -30 35 -28 L62 -24 Q70 -23 68 -17 Q67 -13 59 -14 L39 -15 L30 -3`],
    marks: `M88 19 L61 14`,
  },
  // a phone seen from its screen side: the whole hand, thumb included, lies behind it (layer 0 only), so nothing
  // crosses the screen; the fingertips curl out past its far edge (operator on 9:16 v4: "a finger passes through")
  cradle: {
    outline: `M-4 -16 Q15 -18 28 -10 L45 4 L83 5 Q94 6 97 12 Q98 18 88 19 L63 20 L86 24 Q93 26 89 31 Q84 36 70 32 L51 28 Q36 25 25 20 L-4 16Z M14 -13 Q21 -30 35 -28 L62 -24 Q70 -23 68 -17 Q67 -13 59 -14 L39 -15 L30 -3Z`,
    marks: `M88 19 L61 14`,
  },
};

/** The caller supplies the thin, even stroke; w remains part of the public API. */
export const handShape = (pose: HandPose, L: number, _w: number, side: "near" | "far" = "near", seed = 0): HandDraw => {
  const drawing = pose === "relaxed" ? REST[Math.abs(Math.trunc(seed)) % 2] : DRAWINGS[pose];
  const k = L / 100;
  const flip = side === "far" ? -1 : 1;
  // All master commands use absolute coordinate pairs (no arcs or scalar H/V).
  const scaled = (d: string) => {
    let ordinate = 0;
    return d.replace(/-?\d+(?:\.\d+)?/g, (n) => String(Number(n) * k * (ordinate++ % 2 === 1 ? flip : 1)));
  };
  const layer = (d: string, tone: HandLayer["tone"]): HandLayer => ({ d: scaled(d), tone, ink: "" });
  const layers = [layer(drawing.outline, "skin"), ...(drawing.front ?? []).map((d) => layer(d, "skin"))];
  if (drawing.marks) layers.push(layer(drawing.marks, "none"));
  // A far presenting hand exposes the palm; the near hand shows fewer creases.
  if (side === "far" && drawing.palm) layers.push(layer(drawing.palm, "none"));
  return { layers, grip: { at: [43 * k, 0], angle: 0 } };
};
