// The human cast for 2D (SVG) films: the kit every film starts from (pauseai-it, fourth design, after a director's verdict
// that the cast was "low level" in general quality, not proportions alone). Built from a research spec (Codex, 2026-10-26: studio
// explainer styles, Disney appeal and solid drawing, 2D rigs such as RubberHose, Duik, Spine, Rive, Character Animator):
// - construction in head units (H = 72): about 5.5H tall, a short neck (about 0.12H visible) that starts inside the
//   jaw and ends inside the collar, one closed torso shape per garment that tapers from the shoulders to the waist;
//   three builds and a child body for silhouette variety, three head shapes, eight hair styles;
// - limbs: filled tapered "hoses" through three joints whose bend is a rounded corner (outside arc, tighter inside),
//   with fabric creases at bent elbows and knees; sleeves (short, long with a cuff, jacket with a shirt cuff);
// - hands: an eight-pose library (relaxed, open, wave, support, point, fist, grip, hold) drawn as silhouettes with a
//   few interior marks, not five spokes; held props sit between the palm and the curled fingers or thumb;
// - feet: shoes with heel, instep, toe box and a separate sole; planted feet stay flat, lifted feet tilt with the shin;
//   the near foot sits a little lower than the far one (3/4 depth);
// - face rig: bean eyes with upper lids, a lower lid that rises in a smile, tapered brows, a nose that turns, an
//   eleven-shape mouth set (visemes) plus a continuous smile/open mouth; a 3/4 turn moves and narrows the far features;
// - line and light: coloured outlines (a darker shade of each fill, never black), heavier on the silhouette and light
//   on internal details; cel shadow away from the light, a rim on the lit edge, small ambient-occlusion accents (under
//   the jaw, under the fringe); the far arm passes behind the torso;
// - secondary motion from the frame `t`: breathing, hair that lags the head.
// Local coordinates: soles on y = 0, body centred on x = 0, about 396 units tall at scale 1. Pure function of props.
import React from "react";
import { CAST as P } from "./palette";
import { Cel, Contact } from "./Draw2d";
import { armJoints, bandPath, type Body, body, type Build, capsule, ellipse, f2, type Face, faceFor, FOOT, GRIP, type Hair, hairFront, type HandPose, headPath, type HeadShape, ink, limbPath, mix, type MouthShape, nrm, type Outfit, type PersonPose, polar, type Pt, rrect, sub } from "./geom";

export { POSES, walk, talk, handPos, crowdSpec, limbPath, faceFor } from "./geom";
export type { Outfit, Hair, HandPose, MouthShape, Build, HeadShape, PersonPose } from "./geom";

const OUT: Record<Outfit, [string, string]> = {
  coat: [P.coat, P.coatShade],
  suit: [P.suit, P.suitShade],
  teal: [P.teal, P.tealShade],
  mustard: [P.mustard, P.mustardShade],
  brick: [P.brick, P.brickShade],
  slate: [P.slate, P.slateShade],
};

/** outline weights: silhouette parts, internal details */
const LINE = 2.6;

const LINE_IN = 1.25;

/** A short fabric crease on the inside of a bent joint (u1, u2: directions into and out of the joint). */
const crease = (j: Pt, u1: Pt, u2: Pt, hw: number, color: string) => {
  const cross = u1[0] * u2[1] - u1[1] * u2[0];
  const n: Pt = cross > 0 ? [-u1[1], u1[0]] : [u1[1], -u1[0]];
  const p = (k: number, along: number): Pt => [j[0] + n[0] * k + u1[0] * along, j[1] + n[1] * k + u1[1] * along];
  return <path d={`M ${f2(p(hw - 1, -1))} Q ${f2(p(hw - 4, 2))} ${f2(p(hw - 8, 0))}`} stroke={color} strokeWidth={LINE_IN} fill="none" strokeLinecap="round" />;
};

// ---------------------------------------------------------------- hands (wrist at 0,0, hand points along +y, thumb on -x)
/**
 * Several overlapping shapes drawn as one silhouette: every part stroked at twice the line width first, then every part
 * filled on top, so only the outer contour keeps its line (the union-outline technique of vector rigs). A cel shadow
 * falls away from the light inside the union.
 */
const Union: React.FC<{ parts: string[]; base: string; shade: string; line: string; lw: number; depth?: number }> = ({ parts, base, shade, line, lw, depth = 2.5 }) => {
  const clip = `u${React.useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  return (
    <g>
      <defs>
        <clipPath id={clip}>
          {parts.map((d, i) => (
            <path key={i} d={d} />
          ))}
        </clipPath>
      </defs>
      {parts.map((d, i) => (
        <path key={`o${i}`} d={d} fill={line} stroke={line} strokeWidth={lw * 2} strokeLinejoin="round" />
      ))}
      {parts.map((d, i) => (
        <path key={`s${i}`} d={d} fill={shade} />
      ))}
      <g clipPath={`url(#${clip})`}>
        <g transform={`translate(${-depth * 0.7} ${-depth * 0.7})`}>
          {parts.map((d, i) => (
            <path key={`b${i}`} d={d} fill={base} />
          ))}
        </g>
      </g>
    </g>
  );
};

const Hand: React.FC<{ pose: HandPose; skin: [string, string]; mirror: boolean; k: number; hold?: React.ReactNode; detail: boolean }> = ({
  pose,
  skin,
  mirror,
  k,
  hold,
  detail,
}) => {
  const line = ink(skin[0]);
  const U = (parts: string[]) => <Union parts={parts} base={skin[0]} shade={skin[1]} line={line} lw={LINE_IN + 0.3} />;
  const fg = (x1: number, y1: number, x2: number, y2: number, r: number) => capsule(x1, y1, x2, y2, r, r * 0.86);
  const marks = (m: [number, number, number, number][]) =>
    detail ? (
      <g stroke={line} strokeWidth={1.2} strokeLinecap="round" opacity={0.75}>
        {m.map(([a, b, c, d], i) => (
          <path key={i} d={`M ${a} ${b} L ${c} ${d}`} />
        ))}
      </g>
    ) : null;
  const palmLight = (cy: number) => <ellipse cx={0} cy={cy} rx={6.5} ry={4.5} fill={mix(skin[0], "#ffffff", 0.35)} opacity={0.4} />;
  const PALM = `M -12 -1 C -14 8 -13 18 -8 22 C -2 26 8 25 12 20 C 15 12 13 3 11 -2 C 4 -5 -6 -5 -12 -1 Z`;
  const MITTEN = `M -11 -2 C -13 6 -13 14 -11 22 C -10 29 -7 34 -1 35 C 5 36 10 33 12 27 C 14 20 13 8 11 -2 C 4 -5 -4 -5 -11 -2 Z`;
  let back: React.ReactNode = null;
  let front: React.ReactNode = null;
  switch (pose) {
    case "open":
      front = (
        <g>
          {U([PALM, fg(-8, 15, -13, 34, 3.6), fg(-3, 17, -4, 39, 3.8), fg(3, 17, 4, 38, 3.7), fg(8, 15, 11, 32, 3.3), fg(-11, 5, -22, 13, 3.9)])}
          {palmLight(11)}
        </g>
      );
      break;
    case "wave":
      front = (
        <g>
          {U([`M -13 -1 C -15 8 -14 19 -8 23 C -2 27 9 26 13 20 C 16 12 14 3 12 -2 C 4 -5 -6 -5 -13 -1 Z`, fg(-8, 15, -14, 31, 3.6), fg(-2, 17, -4, 35, 3.8), fg(4, 17, 5, 35, 3.7), fg(9, 15, 14, 29, 3.3), fg(-12, 6, -23, 6, 3.9)])}
          {palmLight(11)}
        </g>
      );
      break;
    case "support":
      // palm up, foreshortened: a wide palm and short fingers fanned forward
      front = (
        <g>
          {U([
            `M -13 0 C -16 6 -15 14 -9 17 C -2 20 9 19 13 14 C 16 8 14 2 12 -2 C 5 -5 -6 -5 -13 0 Z`,
            fg(-8, 13, -10, 25, 3.5),
            fg(-2, 15, -2, 28, 3.7),
            fg(4, 15, 6, 27, 3.6),
            fg(10, 12, 13, 22, 3.2),
            fg(-12, 4, -21, 8, 3.8),
          ])}
          {palmLight(8)}
        </g>
      );
      break;
    case "point":
      front = (
        <g>
          {U([`M -12 -2 C -14 6 -13 16 -9 23 L 9 23 C 12 16 13 8 12 -2 C 5 -5 -5 -5 -12 -2 Z`, fg(3, 14, 4, 43, 3.7), fg(-11, 5, -4, 15, 3.8)])}
          {marks([
            [-6, 16, -6, 23],
            [0, 16, 0, 23],
          ])}
        </g>
      );
      break;
    case "fist":
      front = (
        <g>
          {U([rrect(-12, -3, 25, 26, 10), fg(-11, 8, 3, 12, 4)])}
          {marks([
            [-4, 15, -4, 23],
            [2, 15, 2, 23],
            [8, 14, 8, 22],
          ])}
        </g>
      );
      break;
    case "grip":
      back = U([rrect(-12, -3, 25, 22, 10)]);
      front = (
        <g>
          {U([rrect(-12, 9, 25, 13, 6), fg(-12, 3, -7, 14, 4)])}
          {marks([
            [-4, 12, -4, 20],
            [2, 12, 2, 20],
            [8, 12, 8, 19],
          ])}
        </g>
      );
      break;
    case "hold":
      // a flat object (phone, clipboard): fingers behind it, the thumb across its face
      back = U([MITTEN]);
      front = U([fg(-10, 6, -1, 20, 4)]);
      break;
    default:
      // relaxed: fingers together and softly curled, the thumb hanging in front
      front = (
        <g>
          {U([MITTEN, fg(-10, 4, -15, 17, 4)])}
          {marks([
            [-4, 26, -4, 33],
            [2, 27, 2, 35],
            [7, 25, 7, 32],
          ])}
        </g>
      );
  }
  return (
    <g transform={mirror ? "scale(-1 1)" : undefined}>
      {back ? <g transform={`scale(${k})`}>{back}</g> : null}
      {hold ? <g transform={`translate(0 ${GRIP * k})`}>{hold}</g> : null}
      <g transform={`scale(${k})`}>{front}</g>
    </g>
  );
};

type Sleeve = "short" | "long" | "jacket" | "coat";

const Arm: React.FC<{
  bd: Body;
  side: -1 | 1;
  a: [number, number];
  cloth: [string, string];
  skin: [string, string];
  rim: string;
  hand: HandPose;
  hold?: React.ReactNode;
  sleeve: Sleeve;
  detail: boolean;
}> = ({ bd, side, a, cloth, skin, rim, hand, hold, sleeve, detail }) => {
  const j = armJoints(bd, side, a);
  const w = bd.w;
  const S: Pt = [j.sx, j.sy];
  const E: Pt = [j.ex, j.ey];
  const W: Pt = [j.wx, j.wy];
  const u1 = nrm(sub(E, S));
  const u2 = nrm(sub(W, E));
  const at = (p: Pt, u: Pt, k: number): Pt => [p[0] + u[0] * k, p[1] + u[1] * k];
  const bent = Math.abs(a[1] + 10) > 28;
  const clothLine = ink(cloth[0]);
  // jacket sleeves stop short of the wrist so the shirt cuff shows
  const end = sleeve === "jacket" ? at(W, u2, -6) : W;
  const limb = limbPath(S, E, end, 25 * w, 16.5 * w, (sleeve === "short" ? 12 : 14) * w, 22);
  return (
    <g>
      {/* the hand first, so the cuff overlaps the wrist */}
      <g transform={`translate(${j.wx} ${j.wy}) rotate(${j.d2 - 90 + (hand === "relaxed" ? side * 10 : 0)})`}>
        <Hand pose={hand} skin={skin} mirror={side < 0} k={bd.hand} hold={hold} detail={detail} />
      </g>
      {sleeve === "jacket" ? <path d={bandPath(at(W, u2, -9), at(W, u2, 1), 6.5 * w, 6.5 * w)} fill="#f2efe8" stroke={ink("#f2efe8")} strokeWidth={LINE_IN} /> : null}
      {sleeve === "short" ? (
        <g>
          <Cel d={limb} base={skin[0]} shade={skin[1]} shadeDepth={5} rim={rim} rimW={2.5} line={LINE} ink={ink(skin[0])} />
          <Cel d={bandPath(S, at(S, u1, bd.upper * 0.48), 14.5 * w, 12.5 * w)} base={cloth[0]} shade={cloth[1]} shadeDepth={5} rim={rim} rimW={2.5} line={LINE} ink={clothLine} />
        </g>
      ) : (
        <g>
          <Cel d={limb} base={cloth[0]} shade={cloth[1]} shadeDepth={5} rim={rim} rimW={2.5} line={LINE} ink={clothLine} />
          {sleeve !== "jacket" ? (
            <path d={bandPath(at(W, u2, -6), W, 7.3 * w, 7.3 * w)} fill={sleeve === "coat" ? cloth[1] : mix(cloth[1], "#000000", 0.08)} stroke={clothLine} strokeWidth={LINE_IN} />
          ) : null}
          {detail && bent ? crease(E, u1, u2, 7.5 * w, clothLine) : null}
        </g>
      )}
    </g>
  );
};

/** A shoe in side view: heel, instep, toe box, a separate sole; the ankle sits at (0, 0), the sole at y = FOOT. */
const Shoe: React.FC<{ color: string; sole: string; toward: 1 | -1; detail: boolean; fore?: number }> = ({ color, sole, toward, detail, fore = 1 }) => (
  <g transform={`translate(0 ${FOOT - 16 * 1.06}) scale(${toward * 1.06 * fore} 1.06)`}>
    <Cel
      d={`M -11 -6 C -14 0 -14 8 -12 12 L 28 12 C 35 12 37 6 34 1 C 30 -4 21 -6 13 -7 C 8 -8 5 -10 4 -12 L -8 -12 C -10 -10 -11 -8 -11 -6 Z`}
      base={color}
      shade={mix(color, "#000000", 0.35)}
      shadeDepth={4}
      line={LINE}
      ink={ink(color)}
    />
    <path d={`M -13 10 L 30 10 C 35 10 37 12 34 16 L -10 16 C -14 16 -15 12 -13 10 Z`} fill={sole} stroke={ink(sole)} strokeWidth={LINE_IN} strokeLinejoin="round" />
    {detail ? (
      <g stroke={mix(color, "#ffffff", 0.35)} strokeWidth={1.8} strokeLinecap="round">
        <path d={`M 7 -5 L 12 -1`} />
        <path d={`M 12 -6 L 17 -2`} />
        <path d={`M -9 2 Q -6 6 -9 10`} fill="none" opacity={0.6} />
      </g>
    ) : null}
  </g>
);

const Leg: React.FC<{
  bd: Body;
  side: -1 | 1;
  a: number;
  knee?: number;
  cloth: [string, string];
  shoe: string;
  sole: string;
  rim: string;
  toward: 1 | -1;
  dy: number;
  detail: boolean;
  /** foot length factor: < 1 for a foot turned toward the camera */
  fore?: number;
}> = ({ bd, side, a, knee, cloth, shoe, sole, rim, toward, dy, detail, fore = 1 }) => {
  const H0: Pt = [side * bd.hipX, bd.hipY + dy];
  const d1 = 90 - a;
  const K = polar(H0[0], H0[1], bd.thigh, d1) as Pt;
  // knees keep a slight bend and the shins splay a little, so standing legs are not rigid poles
  const kn = knee ?? a * 0.6 + (side < 0 ? 3 : -3);
  const d2 = d1 + kn;
  const A = polar(K[0], K[1], bd.shin, d2) as Pt;
  // a planted foot stays flat; a lifted one tilts with the shin (continuous, so no snap)
  const lift = Math.max(0, Math.min(1, (-FOOT + dy - A[1]) / 14));
  const footRot = (d2 - 90) * 0.7 * lift * toward;
  const w = bd.w;
  const line = ink(cloth[0]);
  return (
    <g>
      <g transform={`translate(${A[0]} ${A[1]}) rotate(${footRot})`}>
        <Shoe color={shoe} sole={sole} toward={toward} detail={detail} fore={fore} />
      </g>
      <Cel d={limbPath(H0, K, [A[0], A[1] + 3], 30 * w, 23 * w, 21 * w, 26, true)} base={cloth[0]} shade={cloth[1]} shadeDepth={6} rim={rim} rimW={2.5} line={LINE} ink={line} />
      {detail && Math.abs(kn) > 20 ? crease(K, nrm(sub(K, H0)), nrm(sub(A, K)), 9.5 * w, line) : null}
    </g>
  );
};

/** Hair behind the head and body (long hair, bob, bun, ponytail): drawn before the torso. */
const HairBack: React.FC<{ kind: Hair; color: string; sway: number }> = ({ kind, color, sway }) => {
  const C = (d: string) => <Cel d={d} base={mix(color, "#000000", 0.1)} shade={mix(color, "#000000", 0.3)} shadeDepth={5} line={LINE} ink={ink(color)} />;
  if (kind === "long") return C(`M -34 -22 C -41 8 ${-39 + sway} 42 ${-31 + sway} 64 C -10 68 10 68 ${31 + sway} 64 C ${39 + sway} 42 41 8 34 -22 Z`);
  if (kind === "bob") return C(`M -35 -18 C -39 4 -37 24 -29 31 C -12 35 12 35 29 31 C 37 24 39 4 35 -18 Z`);
  if (kind === "bun") return C(ellipse(sway * 0.3, -45, 12.5, 11.5));
  if (kind === "pony")
    return (
      <g>
        {C(`M -24 -40 C -44 -40 ${-52 + sway} -8 ${-46 + sway * 1.6} 30 C ${-42 + sway} 34 ${-38 + sway} 30 ${-38 + sway} 24 C ${-40 + sway} 0 -36 -22 -20 -32 Z`)}
        <ellipse cx={-27} cy={-36} rx={4.5} ry={5.5} fill={P.danger} stroke={ink(P.danger)} strokeWidth={LINE_IN} />
      </g>
    );
  return null;
};

const Eye: React.FC<{ cx: number; cy: number; lids: number; look: [number, number]; wide: number; skin: string; squeeze: number; squint: number }> = ({
  cx,
  cy,
  lids,
  look,
  wide,
  skin,
  squeeze,
  squint,
}) => {
  const clip = `e${React.useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const rx = 4.3 * squeeze + wide * 1.6;
  const ry = 5.9 + wide * 2;
  const px = cx + look[0] * 1.6;
  const py = cy + look[1] * 1.5;
  const lidY = py - ry - 1 + Math.min(1, lids) * (ry * 2 + 2);
  const lowY = py + ry + 1 - squint * ry * 0.9;
  return (
    <g>
      {wide > 0.25 ? <ellipse cx={px} cy={py} rx={rx + 2.6} ry={ry + 2.6} fill="#fffaf1" opacity={Math.min(1, (wide - 0.25) * 2)} /> : null}
      <clipPath id={clip}>
        <ellipse cx={px} cy={py} rx={rx} ry={ry} />
      </clipPath>
      <ellipse cx={px} cy={py} rx={rx} ry={ry} fill="#1d1626" />
      <g clipPath={`url(#${clip})`}>
        <circle cx={px - rx * 0.32} cy={py - ry * 0.4} r={1.7} fill="#ffffff" />
        <circle cx={px + rx * 0.3} cy={py + ry * 0.35} r={0.8} fill="#ffffff" opacity={0.7} />
        <rect x={px - rx - 2} y={py - ry - 3} width={rx * 2 + 4} height={Math.max(0, lidY - (py - ry - 3))} fill={skin} />
        {squint > 0 ? <ellipse cx={px} cy={lowY + ry} rx={rx * 1.6} ry={ry} fill={skin} /> : null}
      </g>
      {/* the upper lid line follows the eye and thickens toward the outer corner */}
      {lids > 0.05 ? (
        <path d={`M ${px - rx - 1} ${Math.min(lidY, py) - 0.4} Q ${px} ${Math.min(lidY, py) - ry * 0.22 - 1} ${px + rx + 1.4} ${Math.min(lidY, py) - 1.3}`} stroke="#1d1626" strokeWidth={lids > 0.5 ? 2.2 : 1.5} fill="none" strokeLinecap="round" />
      ) : null}
    </g>
  );
};

const Mouth: React.FC<{ x: number; y: number; shape?: MouthShape; smile: number; open: number }> = ({ x, y, shape, smile, open }) => {
  const dark = "#4a1d2a";
  const lip = "#3a1a26";
  const tongue = "#d9707a";
  const teeth = "#fffaf1";
  const stroke = (d: string, w = 2.3) => <path d={d} fill="none" stroke={lip} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round" />;
  const hole = (w: number, h: number, top = 0) => `M ${x - w} ${y} Q ${x} ${y - 2 + top} ${x + w} ${y} Q ${x + w * 0.75} ${y + h} ${x} ${y + h} Q ${x - w * 0.75} ${y + h} ${x - w} ${y} Z`;
  const holeFill = (d: string) => <path d={d} fill={dark} stroke={lip} strokeWidth={1.4} strokeLinejoin="round" />;
  switch (shape) {
    case "neutral":
      return stroke(`M ${x - 6} ${y} Q ${x} ${y + 1.4} ${x + 6} ${y - 0.4}`);
    case "smile":
      return stroke(`M ${x - 8} ${y - 1.5} Q ${x} ${y + 6} ${x + 8} ${y - 2.5}`);
    case "frown":
      return stroke(`M ${x - 7} ${y + 2} Q ${x} ${y - 3.5} ${x + 7} ${y + 2}`);
    case "M":
      return stroke(`M ${x - 5.5} ${y} Q ${x} ${y - 0.8} ${x + 5.5} ${y}`, 2.8);
    case "A":
      return (
        <g>
          {holeFill(hole(6.5, 8.5))}
          <path d={`M ${x - 4} ${y + 6.8} Q ${x} ${y + 4.3} ${x + 4} ${y + 6.8} Q ${x} ${y + 8.5} ${x - 4} ${y + 6.8} Z`} fill={tongue} />
          <path d={`M ${x - 4.8} ${y + 0.3} L ${x + 4.8} ${y + 0.3} L ${x + 4.2} ${y + 2.3} L ${x - 4.2} ${y + 2.3} Z`} fill={teeth} />
        </g>
      );
    case "E":
      return (
        <g>
          {holeFill(hole(8, 4.5, 1))}
          <path d={`M ${x - 6.2} ${y + 0.4} L ${x + 6.2} ${y + 0.4} L ${x + 5.6} ${y + 2} L ${x - 5.6} ${y + 2} Z`} fill={teeth} />
        </g>
      );
    case "O":
      return (
        <g>
          <ellipse cx={x} cy={y + 2.5} rx={4} ry={5} fill={dark} stroke={lip} strokeWidth={1.6} />
          <ellipse cx={x} cy={y + 5} rx={2.3} ry={1.6} fill={tongue} />
        </g>
      );
    case "surprise":
      return (
        <g>
          <ellipse cx={x} cy={y + 3} rx={4.6} ry={6} fill={dark} stroke={lip} strokeWidth={1.4} />
          <ellipse cx={x} cy={y + 6.5} rx={2.6} ry={1.8} fill={tongue} />
        </g>
      );
    case "F":
      return (
        <g>
          {holeFill(hole(6.5, 3.5))}
          <rect x={x - 4.5} y={y - 0.2} width={9} height={2.6} rx={0.8} fill={teeth} />
          {stroke(`M ${x - 6} ${y + 3.4} Q ${x} ${y + 4.6} ${x + 6} ${y + 3.4}`, 1.8)}
        </g>
      );
    case "L":
      return (
        <g>
          {holeFill(hole(6.5, 8))}
          <path d={`M ${x - 3.5} ${y + 1.5} Q ${x} ${y - 0.5} ${x + 3.5} ${y + 1.5} L ${x + 3} ${y + 6} Q ${x} ${y + 7.5} ${x - 3} ${y + 6} Z`} fill={tongue} />
        </g>
      );
    default:
      break;
  }
  // continuous mouth: a smile curve that opens smoothly
  if (open > 0.06) {
    const w = 7 + open * 2;
    const h = 1 + open * 10;
    return (
      <g>
        {holeFill(`M ${x - w} ${y} Q ${x} ${y - 2 + smile * 2} ${x + w} ${y} Q ${x + w * 0.7} ${y + h} ${x} ${y + h} Q ${x - w * 0.7} ${y + h} ${x - w} ${y} Z`)}
        {h > 5 ? <path d={`M ${x - w * 0.5} ${y + h * 0.78} Q ${x} ${y + h * 0.48} ${x + w * 0.5} ${y + h * 0.78}`} fill={tongue} /> : null}
        {smile > 0.3 && h > 3 ? <path d={`M ${x - w * 0.65} ${y + 0.6} L ${x + w * 0.65} ${y + 0.6} L ${x + w * 0.55} ${y + 2.6} L ${x - w * 0.55} ${y + 2.6} Z`} fill={teeth} /> : null}
      </g>
    );
  }
  const w = 7;
  return stroke(`M ${x - w} ${y - Math.max(0, smile) * 1.2} Q ${x} ${y + smile * 6} ${x + w} ${y - Math.max(0, smile) * 2}`);
};

const Head: React.FC<{
  face: Face;
  shape: HeadShape;
  turn: number;
  look: [number, number];
  lids: number;
  brow: number;
  smile: number;
  mouth?: MouthShape;
  mouthOpen: number;
  wide: number;
  skin: [string, string];
  hair: Hair;
  hairCol: string;
  glasses: boolean;
  beard: boolean;
  rim: string;
  detail: boolean;
}> = ({ face, shape, turn, look, lids, brow, smile, mouth, mouthOpen, wide, skin, hair, hairCol, glasses, beard, rim, detail }) => {
  const clip = `h${React.useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const tq = Math.max(-1, Math.min(1, turn));
  const s = tq >= 0 ? 1 : -1;
  const at = Math.abs(tq);
  const j = tq * 6;
  const ox = tq * 7;
  const t = tq * 6;
  const head = headPath(shape, j, face.jaw);
  const fronts = hairFront(hair, t);
  const hairShade = mix(hairCol, "#000000", 0.28);
  // the far eye moves toward the nose and narrows; the near one stays full
  const nearX = ox - s * face.eyeGap;
  const farX = ox + s * face.eyeGap * (1 - 0.35 * at);
  const ey = 1;
  const squint = Math.max(0, Math.min(0.55, (smile - 0.45) * 1.1));
  const browCol = mix(hairCol, "#000000", 0.25);
  const noseX = ox + tq * 6;
  return (
    <g>
      <defs>
        <clipPath id={clip}>
          <path d={head} />
        </clipPath>
      </defs>
      <Cel d={head} base={skin[0]} shade={skin[1]} shadeDepth={6} rim={rim} rimW={2.5} line={LINE} ink={ink(skin[0])} />
      {/* ambient occlusion: the fringe's shadow on the forehead */}
      {hair !== "bald" ? (
        <g clipPath={`url(#${clip})`} opacity={0.5}>
          {fronts.map((d, i) => (
            <path key={i} d={d} fill={skin[1]} transform="translate(1.5 3.5)" />
          ))}
        </g>
      ) : null}
      {/* cheeks: the far one smaller */}
      <ellipse cx={nearX - s * 5} cy={13} rx={6} ry={3.8} fill={P.danger} opacity={0.16} />
      <ellipse cx={farX + s * 3} cy={13} rx={6 * (1 - 0.4 * at)} ry={3.8} fill={P.danger} opacity={0.16} />
      <g transform={`translate(${nearX} ${ey}) scale(${face.eyeSize}) translate(${-nearX} ${-ey})`}>
        <Eye cx={nearX} cy={ey} lids={lids} look={look} wide={wide} skin={skin[0]} squeeze={1} squint={squint} />
      </g>
      <g transform={`translate(${farX} ${ey}) scale(${face.eyeSize}) translate(${-farX} ${-ey})`}>
        <Eye cx={farX} cy={ey} lids={lids} look={look} wide={wide} skin={skin[0]} squeeze={1 - 0.55 * at} squint={squint} />
      </g>
      {glasses ? (
        <g fill="none" stroke="#2a2030" strokeWidth={2.2}>
          <rect x={nearX - 8.5} y={ey - 7.5} width={17} height={15} rx={6} />
          <rect x={farX - 8.5 * (1 - 0.4 * at)} y={ey - 7.5} width={17 * (1 - 0.4 * at)} height={15} rx={6} />
          <path d={`M ${Math.min(nearX, farX) + 8.5 * (s > 0 ? 1 : 1 - 0.4 * at)} ${ey - 2} L ${Math.max(nearX, farX) - 8.5 * (s > 0 ? 1 - 0.4 * at : 1)} ${ey - 2}`} />
        </g>
      ) : null}
      {/* nose: a soft rounded wedge toward the turn; only its underside is inked */}
      <g transform={`translate(${noseX} 0) scale(1 ${face.nose}) translate(${-noseX} 0)`}>
      <path d={`M ${noseX - 1.5} 0 C ${noseX + 0.5 + tq * 2} 5 ${noseX + 5 + tq * 2} 8 ${noseX + 4.5 + tq * 2} 11.5 C ${noseX + 4 + tq * 2} 14 ${noseX - 1} 14 ${noseX - 3.5} 12 C ${noseX - 2} 9 ${noseX - 1} 5 ${noseX - 1.5} 0 Z`} fill={skin[1]} />
      <path d={`M ${noseX + 4.5 + tq * 2} 11.5 C ${noseX + 4 + tq * 2} 14 ${noseX - 1} 14 ${noseX - 3.5} 12`} stroke={ink(skin[0])} strokeWidth={LINE_IN} fill="none" strokeLinecap="round" />
      </g>
      {beard ? (
        <Cel
          d={`M -29 4 C -29 20 -18 36 ${2 + j} 39 C 22 36 29 20 29 4 C 26 12 22 16 ${12 + j} 16 C ${8 + j} 28 ${-4 + j} 28 ${-8 + j} 16 C -18 16 -26 12 -29 4 Z`}
          base={hairCol}
          shade={hairShade}
          shadeDepth={4}
          line={LINE_IN + 0.6}
          ink={ink(hairCol)}
        />
      ) : null}
      <Mouth x={ox + tq * 3 + 1} y={22} shape={mouth} smile={smile} open={mouthOpen} />
      {/* hair over the cranium */}
      {fronts.map((d, i) => (
        <Cel key={i} d={d} base={hairCol} shade={hairShade} shadeDepth={4} line={LINE} ink={ink(hairCol)} />
      ))}
      {detail && hair !== "bald" && hair !== "curly" ? (
        <path d={`M ${-14 + t} -38 Q ${-2 + t} -44 ${12 + t} -40`} stroke="#ffffff" strokeWidth={2.6} opacity={0.2} fill="none" strokeLinecap="round" />
      ) : null}
      {detail && (hair === "short" || hair === "side" || hair === "long") ? (
        <path d={`M ${-2 + t} -28 C ${4 + t} -36 ${12 + t} -39 ${20 + t} -38`} stroke={hairShade} strokeWidth={LINE_IN} fill="none" strokeLinecap="round" />
      ) : null}
      {hair === "bald" ? <path d={`M ${-12 + t} -32 Q ${t} -36 ${12 + t} -33`} stroke="#ffffff" strokeWidth={3} opacity={0.25} fill="none" strokeLinecap="round" /> : null}
      {/* tapered brows: worried lifts the inner ends, determined lowers them */}
      {[-1, 1].map((k) => {
        const cx = k === -s ? nearX : farX;
        const sc = k === -s ? 1 : 1 - 0.4 * at;
        const inner = -10 - (brow < 0 ? -brow * 4 : 0) + (brow > 0 ? brow * 2.6 : 0) - wide * 3.5;
        const outer = -9.5 + (brow < 0 ? -brow * 1.6 : 0) - (brow > 0 ? brow * 1.6 : 0) - wide * 3.5;
        const x1 = cx - k * 6 * sc;
        const x2 = cx + k * 8 * sc;
        const my = Math.min(inner, outer) - 2.4;
        return <path key={k} d={`M ${x1} ${inner - 1.7} Q ${(x1 + x2) / 2} ${my - 1.4} ${x2} ${outer} Q ${(x1 + x2) / 2} ${my + 1.6} ${x1} ${inner + 1.7} Z`} fill={browCol} stroke={browCol} strokeWidth={0.8} strokeLinejoin="round" />;
      })}
    </g>
  );
};

// ---------------------------------------------------------------- torso and clothing
const Torso: React.FC<{ bd: Body; outfit: Outfit; cloth: [string, string]; rim: string; tie: boolean; badge?: React.ReactNode; ox: number; detail: boolean }> = ({
  bd,
  outfit,
  cloth,
  rim,
  tie,
  badge,
  ox,
  detail,
}) => {
  const b = bd.b;
  const s = bd.shY;
  const c = bd.collarY;
  const T = bd.hipY - s;
  const line = ink(cloth[0]);
  const shirt = (hem: number) =>
    `M -13 ${c} C -6 ${c + 6} 6 ${c + 6} 13 ${c} L ${36 * b} ${s - 9} C ${49 * b} ${s - 7} ${55 * b} ${s + 1} ${55 * b} ${s + 12} L ${46 * b} ${s + 0.5 * T} C ${43 * b} ${s + 0.66 * T} ${42 * b} ${hem - 14} ${43 * b} ${hem} C ${18 * b} ${hem + 6} ${-18 * b} ${hem + 6} ${-43 * b} ${hem} C ${-42 * b} ${hem - 14} ${-43 * b} ${s + 0.66 * T} ${-46 * b} ${s + 0.5 * T} L ${-55 * b} ${s + 12} C ${-55 * b} ${s + 1} ${-49 * b} ${s - 7} ${-36 * b} ${s - 9} Z`;
  const hem = bd.hipY - 2;
  const crew = (y: number, w: number) => <path d={`M -13 ${y} C -6 ${y + 6} 6 ${y + 6} 13 ${y}`} stroke={cloth[1]} strokeWidth={w} fill="none" strokeLinecap="round" />;
  const hemBand = (y: number, w: number) => <path d={`M ${-42 * b} ${y - 5} C ${-18 * b} ${y + 1} ${18 * b} ${y + 1} ${42 * b} ${y - 5}`} stroke={cloth[1]} strokeWidth={w} fill="none" strokeLinecap="round" />;
  const Tie = () => (
    <g>
      <path d={`M ${ox - 4} ${c + 4} L ${ox + 4} ${c + 4} L ${ox + 3} ${c + 10} L ${ox - 3} ${c + 10} Z`} fill={P.dangerDeep} stroke={ink(P.danger)} strokeWidth={LINE_IN} strokeLinejoin="round" />
      <path d={`M ${ox - 3} ${c + 10} L ${ox + 3} ${c + 10} L ${ox + 7} ${s + 0.55 * T} L ${ox} ${s + 0.62 * T} L ${ox - 7} ${s + 0.55 * T} Z`} fill={P.danger} stroke={ink(P.danger)} strokeWidth={LINE_IN} strokeLinejoin="round" />
    </g>
  );
  let body: React.ReactNode;
  if (outfit === "coat") {
    const hemC = bd.hipY + 44 * (bd.child ? 0.74 : 1);
    const v = s + 0.55 * T;
    const coat = `M -15 ${c - 1} L ${38 * b} ${s - 9} C ${51 * b} ${s - 6} ${57 * b} ${s + 2} ${57 * b} ${s + 13} L ${53 * b} ${v} C ${53 * b} ${hemC - 40} ${55 * b} ${hemC - 20} ${58 * b} ${hemC} L ${ox + 4} ${hemC} L ${ox + 1} ${v + 4} L ${ox - 1} ${v + 4} L ${ox - 4} ${hemC} L ${-58 * b} ${hemC} C ${-55 * b} ${hemC - 20} ${-53 * b} ${hemC - 40} ${-53 * b} ${v} L ${-57 * b} ${s + 13} C ${-57 * b} ${s + 2} ${-51 * b} ${s - 6} ${-38 * b} ${s - 9} Z`;
    body = (
      <g>
        <Cel d={coat} base={cloth[0]} shade={cloth[1]} shadeDepth={12} rim={rim} rimW={3.5} line={LINE} ink={line} />
        {/* the shirt in the open front, then the lapels */}
        <path d={`M -13 ${c} L ${ox - 1} ${v} L ${ox + 1} ${v} L 13 ${c} C 6 ${c + 6} -6 ${c + 6} -13 ${c} Z`} fill="#6f7fa6" stroke={ink("#6f7fa6")} strokeWidth={LINE_IN} strokeLinejoin="round" />
        <path d={`M -15 ${c - 1} L ${-6 + ox} ${s + 0.22 * T} L ${-19 * b} ${s + 0.18 * T} M 15 ${c - 1} L ${6 + ox} ${s + 0.22 * T} L ${19 * b} ${s + 0.18 * T}`} stroke={line} strokeWidth={LINE_IN + 0.5} fill="none" strokeLinejoin="round" strokeLinecap="round" />
        {detail ? (
          <g stroke={line} strokeWidth={LINE_IN} fill="none" strokeLinecap="round">
            <path d={`M ${-44 * b} ${s + 0.38 * T} L ${-26 * b} ${s + 0.38 * T}`} />
            <path d={`M ${30 * b} ${v + 30} L ${48 * b} ${v + 30} L ${48 * b} ${v + 46} L ${30 * b} ${v + 46} Z`} />
            <path d={`M ${-38 * b} ${s + 0.38 * T - 9} L ${-38 * b} ${s + 0.38 * T + 1}`} stroke={P.danger} strokeWidth={2.4} />
          </g>
        ) : null}
        {tie ? <Tie /> : null}
      </g>
    );
  } else if (outfit === "suit") {
    const jh = hem + 10;
    body = (
      <g>
        <Cel d={shirt(jh)} base={cloth[0]} shade={cloth[1]} shadeDepth={12} rim={rim} rimW={3.5} line={LINE} ink={line} />
        <path d={`M -13 ${c} L ${ox} ${s + 0.42 * T} L 13 ${c} C 6 ${c + 6} -6 ${c + 6} -13 ${c} Z`} fill="#f2efe8" stroke={ink("#f2efe8")} strokeWidth={LINE_IN} strokeLinejoin="round" />
        <Tie />
        <path d={`M -15 ${c - 1} L ${ox - 2} ${s + 0.46 * T} L ${ox - 2} ${jh + 4} M 15 ${c - 1} L ${ox + 2} ${s + 0.46 * T}`} stroke={line} strokeWidth={LINE_IN + 0.5} fill="none" strokeLinejoin="round" strokeLinecap="round" />
        <path d={`M -15 ${c} L ${-9 + ox} ${s + 0.24 * T} L ${-21 * b} ${s + 0.2 * T} M 15 ${c} L ${9 + ox} ${s + 0.24 * T} L ${21 * b} ${s + 0.2 * T}`} stroke={line} strokeWidth={LINE_IN} fill="none" strokeLinejoin="round" />
        {detail ? <circle cx={ox - 6} cy={s + 0.66 * T} r={2} fill={line} /> : null}
      </g>
    );
  } else if (outfit === "slate") {
    // a collared, buttoned shirt
    body = (
      <g>
        <Cel d={shirt(hem)} base={cloth[0]} shade={cloth[1]} shadeDepth={12} rim={rim} rimW={3.5} line={LINE} ink={line} />
        <path d={`M ${ox} ${c + 5} L ${ox} ${hem + 3}`} stroke={line} strokeWidth={LINE_IN} />
        {detail ? [0.12, 0.36, 0.6, 0.84].map((k) => <circle key={k} cx={ox + 3} cy={s + k * T} r={1.7} fill={mix(cloth[0], "#ffffff", 0.5)} />) : null}
        <path d={`M -14 ${c - 2} L ${ox - 2} ${c + 9} L -18 ${c + 12} Z M 14 ${c - 2} L ${ox + 2} ${c + 9} L 18 ${c + 12} Z`} fill={mix(cloth[0], "#ffffff", 0.15)} stroke={line} strokeWidth={LINE_IN} strokeLinejoin="round" />
        {tie ? <Tie /> : null}
      </g>
    );
  } else if (outfit === "brick") {
    // a sweater: rib collar, ribbed hem band
    body = (
      <g>
        <Cel d={shirt(hem + 4)} base={cloth[0]} shade={cloth[1]} shadeDepth={12} rim={rim} rimW={3.5} line={LINE} ink={line} />
        {crew(c + 1, 6)}
        {hemBand(hem + 4, 7)}
        {detail ? [-30, -15, 0, 15, 30].map((x) => <path key={x} d={`M ${x * b} ${hem - 3} L ${x * b} ${hem + 3}`} stroke={line} strokeWidth={1.1} opacity={0.5} />) : null}
        {tie ? <Tie /> : null}
      </g>
    );
  } else {
    // a t-shirt
    body = (
      <g>
        <Cel d={shirt(hem)} base={cloth[0]} shade={cloth[1]} shadeDepth={12} rim={rim} rimW={3.5} line={LINE} ink={line} />
        {crew(c + 0.5, 4)}
        {tie ? <Tie /> : null}
      </g>
    );
  }
  return (
    <g>
      {body}
      {badge ? (
        <g transform={`translate(${outfit === "coat" ? -34 * b + ox : ox} ${outfit === "coat" ? s + 0.28 * T : s + 0.3 * T})`}>
          <circle r={outfit === "coat" ? 10 : 19 * b} fill="#ffffff" />
          <g transform={`scale(${(outfit === "coat" ? 10 : 19 * b) / 20 * 0.72})`}>{badge}</g>
        </g>
      ) : null}
    </g>
  );
};

// ---------------------------------------------------------------- the person
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
  /** rim light colour on the lit edge */
  rim?: string;
  glasses?: boolean;
  tie?: boolean;
  beard?: boolean;
  /** a mark printed on the shirt (logo, badge), authored in a 40-unit box centred on 0,0, drawn on a white roundel */
  badge?: React.ReactNode;
  /** shirt colours [base, shade], overriding the outfit (a brand's colour) */
  shirt?: [string, string];
  /** something held in the right hand, drawn in hand space (y along the forearm), inside the grip */
  hold?: React.ReactNode;
  /** the frame, for breathing and hair sway; omit for a still pose */
  t?: number;
  /** body type: shoulders, hips and limb thickness (silhouette variety across the cast) */
  build?: Build;
  /** a child's body: shorter limbs and torso, a relatively larger, rounder head */
  child?: boolean;
  head?: HeadShape;
}> = ({
  x,
  y,
  scale = 1,
  facing = 1,
  outfit = "teal",
  hair = "short",
  tone = 0,
  hairTone = 0,
  pose = {},
  shadow = true,
  rim = P.glowWarm,
  glasses = false,
  tie = false,
  beard = false,
  badge,
  shirt,
  hold,
  t = 0,
  build = "regular",
  child = false,
  head,
}) => {
  const {
    lean = 0,
    squash = 0,
    tilt = 0,
    turn = 0.25,
    look = [0, 0],
    lids = 0,
    brow = 0,
    smile = 0.2,
    mouthOpen = 0,
    mouth,
    armL = [8, 6],
    armR = [8, 6],
    handL = "relaxed",
    handR = hold ? "grip" : "relaxed",
    legL = 0,
    legR = 0,
    kneeL,
    kneeR,
    wide = 0,
    front,
  } = pose;
  const bd = body(build, child);
  const detail = scale >= 0.35;
  // a stable identity from the character's look: eye spacing, eye size, jaw width, nose length
  const face = faceFor(`${hair}${tone}${hairTone}${outfit}${build}${head ?? ""}`);
  const cloth = shirt ?? OUT[outfit];
  const skin: [string, string] = [P.skin[tone], P.skinShade[tone]];
  const hairCol = P.hair[hairTone];
  const trousers: [string, string] = outfit === "suit" ? [P.suit, P.suitShade] : outfit === "coat" ? ["#5d6680", "#454c64"] : outfit === "slate" ? ["#3f4a5e", "#2e3646"] : ["#56443f", "#3c2e2b"];
  const formal = outfit === "suit" || outfit === "coat" || outfit === "slate";
  const shoe = outfit === "suit" ? "#1c1820" : outfit === "coat" ? "#3a3340" : formal ? "#4a3226" : outfit === "brick" ? "#2f3a52" : "#3b2c2a";
  const sole = formal ? "#241c22" : "#ebe5d8";
  const sleeve: Sleeve = outfit === "coat" ? "coat" : outfit === "suit" ? "jacket" : outfit === "teal" || outfit === "mustard" ? "short" : "long";
  const sx = (1 + squash) * facing;
  const sy = 1 - squash;
  const breath = 0.006 * Math.sin((t * Math.PI * 2) / 105);
  const sway = Math.sin(t / 30) * 1.2 - tilt * 0.25;
  const far: -1 | 1 = turn >= 0 ? 1 : -1;
  const near: -1 | 1 = far === 1 ? -1 : 1;
  const frontArm: -1 | 1 = front ?? (hold ? 1 : near);
  const shape: HeadShape = head ?? (child ? "round" : hair === "bald" || beard ? "square" : "egg");
  const legs = { [-1]: { a: legL, knee: kneeL }, [1]: { a: legR, knee: kneeR } } as Record<-1 | 1, { a: number; knee?: number }>;
  const arms = {
    [-1]: { a: armL, hand: handL, hold: undefined as React.ReactNode },
    [1]: { a: armR, hand: handR, hold },
  } as Record<-1 | 1, { a: [number, number]; hand: HandPose; hold?: React.ReactNode }>;
  const leg = (side: -1 | 1) => (
    <Leg
      bd={bd}
      side={side}
      a={legs[side].a}
      knee={legs[side].knee}
      cloth={trousers}
      shoe={shoe}
      sole={sole}
      rim={rim}
      toward={turn >= -0.05 ? 1 : -1}
      dy={side === far ? -3 : 4}
      fore={side === far ? 1 : 1 - 0.3 * Math.min(1, Math.abs(turn) * 2)}
      detail={detail}
    />
  );
  const arm = (side: -1 | 1) => (
    <Arm bd={bd} side={side} a={arms[side].a} cloth={cloth} skin={skin} rim={rim} hand={arms[side].hand} hold={arms[side].hold} sleeve={sleeve} detail={detail} />
  );
  const headT = `rotate(${tilt} 0 ${bd.chinY}) translate(0 ${bd.headY}) scale(${bd.hs})`;
  const ox = Math.max(-1, Math.min(1, turn)) * 5;
  return (
    <g transform={`translate(${x} ${y}) scale(${scale})`}>
      {shadow ? <Contact x={8} y={2} rx={52 * bd.b + 8} ry={10} opacity={0.55} /> : null}
      <g transform={`rotate(${lean}) scale(${sx} ${sy})`}>
        {leg(far)}
        {leg(near)}
        {/* hips: the trousers' seat joins the legs to the torso */}
        <Cel
          d={`M ${-38 * bd.b} ${bd.hipY - 24} L ${38 * bd.b} ${bd.hipY - 24} C ${39 * bd.b} ${bd.hipY - 12} ${37 * bd.b} ${bd.hipY} ${34 * bd.b} ${bd.hipY + 6} Q 0 ${bd.hipY + 16} ${-34 * bd.b} ${bd.hipY + 6} C ${-37 * bd.b} ${bd.hipY} ${-39 * bd.b} ${bd.hipY - 12} ${-38 * bd.b} ${bd.hipY - 24} Z`}
          base={trousers[0]}
          shade={trousers[1]}
          shadeDepth={5}
          line={LINE}
          ink={ink(trousers[0])}
        />
        {/* the upper body breathes about the hips */}
        <g transform={`translate(0 ${bd.hipY}) scale(1 ${1 + breath}) translate(0 ${-bd.hipY})`}>
          <g transform={headT}>
            <HairBack kind={hair} color={hairCol} sway={sway} />
          </g>
          {frontArm === far ? null : arm(far)}
          {/* short neck (about 0.12H visible): it starts inside the jaw and ends inside the collar */}
          <Cel
            d={`M -9.5 ${bd.chinY - 14} L -10.5 ${bd.collarY + 8} Q 0 ${bd.collarY + 12} 10.5 ${bd.collarY + 8} L 9.5 ${bd.chinY - 14} Z`}
            base={skin[1]}
            shade={mix(skin[1], "#000000", 0.15)}
            shadeDepth={3}
            line={LINE_IN + 0.5}
            ink={ink(skin[0])}
          />
          <ellipse cx={ox * 0.6} cy={bd.chinY + 1} rx={9} ry={3.5} fill={mix(skin[1], "#000000", 0.18)} opacity={0.7} />
          <Torso bd={bd} outfit={outfit} cloth={cloth} rim={rim} tie={tie} badge={badge} ox={ox} detail={detail} />
          <g transform={headT}>
            <Head
              face={face}
              shape={shape}
              turn={turn}
              look={look}
              lids={lids}
              brow={brow}
              smile={smile}
              mouth={mouth}
              mouthOpen={mouthOpen}
              wide={wide}
              skin={skin}
              hair={hair}
              hairCol={hairCol}
              glasses={glasses}
              beard={beard}
              rim={rim}
              detail={detail}
            />
          </g>
          {frontArm === far ? arm(far) : null}
          {arm(near)}
        </g>
      </g>
    </g>
  );
};
