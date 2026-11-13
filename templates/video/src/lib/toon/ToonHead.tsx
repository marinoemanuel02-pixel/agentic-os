// B's original profile masters, carried unchanged from the approved SVG drawings.
// Expressions act inside the silhouette. The neck and its single flat jaw shadow
// belong to the profile, so there is no separate cheek or nose pasted onto a head.
import React from "react";
import type { ToonPose, ToonSpec } from "./Toon";

export type Identity = "researcher" | "lawmaker" | "executive" | "woman" | "worker" | "young" | "older" | "child";

const PROFILES: Record<Identity, string> = {
  researcher: `M-28 28 C-30 8 -12 -3 9 2 C29 4 35 18 34 33 L33 44 C34 50 38 59 41 64 C39 66 36 66 32 66 L32 70 C34 72 34 74 32 75 L28 77 C26 86 15 88 -2 80 L12 128 L-24 128 L-23 70 C-37 73 -44 63 -40 55 C-38 51 -33 51 -29 54Z`,
  lawmaker: `M-32 31 C-34 10 -16 -1 4 1 C27 0 36 15 35 33 L34 41 L39 62 C40 64 38 65 34 65 L29 66 L31 72 L35 74 C33 77 29 78 28 80 L27 88 C18 92 9 90 -1 84 L6 128 L-29 128 L-26 71 C-40 74 -46 63 -41 54 C-39 50 -34 51 -30 54Z`,
  executive: `M-32 31 C-34 10 -16 -1 4 1 C27 0 36 15 35 33 L35 43 C38 50 45 57 49 61 L36 66 L36 71 L40 73 C38 76 33 77 32 78 L31 86 C24 92 12 92 3 87 L6 128 L-29 128 L-26 71 C-40 74 -46 63 -41 54 C-39 50 -34 51 -30 54Z`,
  woman: `M-30 31 C-32 11 -14 1 5 2 C23 3 34 17 33 33 L32 44 C33 50 36 57 39 63 L31 66 L31 69 C33 71 34 72 32 74 L28 76 C25 83 14 86 -2 78 L11 128 L-24 128 L-23 70 C-37 71 -43 61 -39 53 C-37 50 -31 51 -28 54Z`,
  young: `M-30 31 C-32 11 -14 1 5 2 C23 3 34 17 33 33 L32 44 C33 50 36 57 39 63 L31 66 L31 69 C33 71 34 72 32 74 L28 76 C25 83 14 86 -2 78 L11 128 L-24 128 L-23 70 C-37 71 -43 61 -39 53 C-37 50 -31 51 -28 54Z`,
  worker: `M-34 31 C-37 8 -16 0 8 1 C31 2 40 18 38 34 L38 46 L52 63 C49 66 43 67 38 67 L38 74 L42 77 C39 83 35 88 27 91 L9 88 L12 128 L-33 128 L-29 73 C-43 76 -50 65 -45 56 C-42 52 -37 52 -33 55Z`,
  older: `M-34 34 C-37 14 -22 -2 -3 -3 C20 -6 35 6 36 25 L35 43 C38 51 46 58 49 62 L36 67 L36 72 L40 74 L33 79 L30 87 C22 91 10 90 2 86 L7 128 L-29 128 L-27 72 C-42 76 -47 64 -42 55 C-39 51 -34 51 -31 55Z`,
  child: `M-26 29 C-26 11 -10 1 6 4 C23 4 31 16 29 31 L29 40 L40 54 L30 59 L29 63 L32 66 L28 69 C25 77 15 80 5 77 L8 107 L-23 107 L-22 65 C-34 67 -40 58 -35 51 C-33 48 -29 49 -26 51Z`,
};

const SHADOWS: Record<Identity, string> = {
  researcher: `M-21 72 C-14 77 -7 81 -2 80 L3 98 C-5 93 -14 91 -22 86Z`,
  lawmaker: `M-24 72 C-16 80 -8 84 -1 84 L2 103 C-7 97 -18 93 -26 90Z`,
  executive: `M-24 72 C-16 82 -8 86 3 87 L4 103 C-7 97 -18 93 -26 90Z`,
  woman: `M-22 71 C-15 76 -7 79 -2 78 L3 98 C-5 93 -14 91 -22 86Z`,
  young: `M-22 71 C-15 76 -7 79 -2 78 L3 98 C-5 93 -14 91 -22 86Z`,
  worker: `M-28 73 L9 88 L10 104 L-31 91Z`,
  older: `M-25 73 C-16 82 -8 86 2 86 L4 104 L-26 92Z`,
  child: `M-22 65 C-14 72 -3 76 5 76 L6 88 L-22 80Z`,
};

const HAIR = {
  bun: `M-30 55 C-31 44 -32 35 -26 22 C-15 24 2 23 16 12 C22 19 28 23 34 26 L34 16 C28 3 12 -3 -5 -3 C-26 -2 -38 12 -37 29 C-37 40 -34 48 -30 55Z`,
  short: `M-31 56 C-36 50 -36 40 -39 29 C-44 9 -30 -7 -14 -8 C-1 -14 13 -5 18 0 C29 -2 38 6 40 18 L34 27 C26 26 19 22 12 14 C5 21 -9 24 -22 23 L-25 52Z`,
  bob: `M-31 56 C-37 50 -40 43 -43 32 C-50 12 -38 4 -30 -2 L-6 -9 L18 -4 L38 16 L30 30 L10 15 C4 26 -12 31 -28 29 L-28 46Z`,
  long: `M-28 58 C-32 57 -36 59 -38 66 L-44 89 L-54 101 C-48 77 -47 59 -47 38 C-46 11 -31 -7 -9 -8 C15 -12 32 1 37 18 L40 24 C29 27 19 25 10 22 L5 9 C-5 21 -19 24 -29 23 L-29 45 C-22 47 -23 55 -28 58Z`,
  curly: `M-34 55 C-39 47 -40 35 -41 23 C-40 10 -28 -1 -15 -3 L-7 -9 L4 -4 L14 -7 L25 0 C37 3 43 15 41 28 L27 30 L16 20 C2 30 -16 31 -29 29 L-29 53Z`,
  child: `M-26 52 C-31 50 -33 41 -35 31 C-39 15 -25 0 -11 -2 C4 -8 24 -1 32 13 L30 26 L12 17 L3 24 L-5 19 L-24 29 L-24 49Z`,
};

export const identityFor = (s: ToonSpec): Identity => s.identity ?? (
  s.child || (s.height ?? 520) < 420 ? "child" : s.hair === "bald" ? "older" :
  s.beard || s.outfit === "overalls" ? "worker" : s.hair === "bun" ? "researcher" :
  s.hair === "long" || s.hair === "pony" ? "young" : s.hair === "bob" ? "woman" :
  s.nose === "long" || s.head === "broad" ? "executive" : "lawmaker"
);

const clamp = (n: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, n));

export const ToonHead: React.FC<{
  spec: ToonSpec; pose: ToonPose; skin: string; shade: string; ink: string;
}> = ({ spec, pose, skin, shade, ink }) => {
  const who = identityFor(spec);
  const child = who === "child";
  const lid = clamp(pose.lid ?? 0.3, 0, 1);
  const brow = clamp(pose.brow ?? 0, -1, 1);
  const skew = pose.browSkew ?? 0;
  const open = clamp(pose.open ?? 0, 0, 1);
  const smile = clamp(pose.smile ?? 0, -1, 1);
  const eyeY = child ? 37 : 41;
  const eyeX = who === "worker" ? 13 : 11;
  const gazeX = clamp(pose.look?.[0] ?? 0.5, -1, 1) * 2;
  const gazeY = clamp(pose.look?.[1] ?? 0, -1, 1) * 1.5;
  const aperture = Math.max(0, 1 - lid);
  const startled = Math.max(0, (0.2 - lid) * 5) * open;
  const mouthY = child ? 65 : who === "lawmaker" || who === "executive" || who === "older" ? 74 : 72;
  const hair = child ? HAIR.child : spec.hair === "bun" ? HAIR.bun :
    spec.hair === "long" ? HAIR.long : spec.hair === "bob" ? HAIR.bob :
    spec.hair === "curly" ? HAIR.curly : HAIR.short;
  return (
    <g transform="translate(0 10) scale(.9 .85)" stroke={ink} strokeWidth={1.3} strokeLinecap="round" strokeLinejoin="round">
      {spec.hair === "bun" && !child ? <path d={`M-31 20 C-47 24 -57 12 -53 1 C-52 -10 -36 -13 -30 -4 C-25 2 -27 12 -31 20Z`} fill={spec.hairColor} /> : null}
      {spec.hair === "pony" && !child ? <path d={`M-33 24 C-58 19 -54 49 -61 82 L-49 105 C-44 80 -31 57 -30 38Z`} fill={spec.hairColor} /> : null}
      <path d={PROFILES[who]} fill={skin} />
      <path d={SHADOWS[who]} fill={shade} stroke="none" />
      {spec.hair === "bald" ? <g fill={spec.hairColor}>
        <path d={`M-33 55 L-30 47 L-29 30 L-36 24 C-41 34 -41 46 -36 54Z`} />
        <path d={`M31 18 C34 22 35 29 34 34 L29 32Z`} stroke="none" />
      </g> : <path d={hair} fill={spec.hairColor} />}
      {spec.hair === "bob" ? <path d={`M-37 61 C-41 77 -39 87 -27 94 L-12 90 C-25 84 -25 73 -24 65Z`} fill={spec.hairColor} /> : null}
      {spec.hair === "long" ? <path d={`M-39 63 C-39 78 -36 88 -31 95 L-23 86 L-25 69Z`} fill={spec.hairColor} /> : null}
      {spec.beard ? <path d={`M-31 49 L-24 49 L-20 65 C-5 71 9 67 14 62 L25 65 L38 69 L39 78 C34 92 22 98 7 93 L-20 84 L-30 69Z`} fill={spec.hairColor} /> : null}
      <path d={child ? `M-30 53 C-35 51 -34 59 -29 60` : `M-34 57 C-40 54 -39 63 -33 65`} fill="none" />
      <g fill="none" strokeWidth={1.05}>
        <path d={`M9 ${eyeY - 8 - brow * 5 - skew * 2} C15 ${eyeY - 11 - brow * 4 - skew * 2} 23 ${eyeY - 10 - brow + skew} 28 ${eyeY - 9 + brow * 2 + skew}`} />
        <path d={`M${eyeX} ${eyeY + lid * 2} C16 ${eyeY - 4 * aperture - 3 * startled} 23 ${eyeY - 3 * aperture - 4 * startled} 27 ${eyeY + lid * 2} C24 ${eyeY + 7 * startled} 16 ${eyeY + 7 * startled} ${eyeX} ${eyeY + lid * 2}Z`} fill="#b9c1b5" stroke="none" opacity={startled} />
        <path d={`M${eyeX} ${eyeY + lid * 2} C16 ${eyeY - 4 * aperture - 3 * startled} 23 ${eyeY - 3 * aperture - 4 * startled} 27 ${eyeY + lid * 2}`} />
        <path d={`M${eyeX} ${eyeY + lid * 2} C16 ${eyeY + 7 * startled} 24 ${eyeY + 7 * startled} 27 ${eyeY + lid * 2}`} opacity={startled} />
        {lid < 0.96 ? <ellipse cx={21 + gazeX} cy={eyeY + gazeY + lid} rx={1.65} ry={Math.max(0.45, 2.6 * aperture + startled)} fill={ink} stroke="none" /> : null}
        {brow > 0.5 || lid > 0.45 ? <path d={`M14 ${eyeY + 6} C18 ${eyeY + 7} 23 ${eyeY + 7} 26 ${eyeY + 6}`} /> : null}
        {spec.glasses ? <path d={`M32 ${eyeY} Q35 ${eyeY - 3 * aperture} 37 ${eyeY}`} /> : null}
        {open > 0.1 ? <ellipse cx={26} cy={mouthY} rx={1.2 + open * 2} ry={1 + open * 3.4} fill={spec.beard ? skin : ink} stroke="none" /> :
          <path d={`M20 ${mouthY + (pose.skew ?? 0) * 1.5} C24 ${mouthY - 1 + smile * 5} 28 ${mouthY - 1 + smile * 4} 32 ${mouthY - 2 - (pose.skew ?? 0) * 2}`} />}
        {who === "older" ? <path d={`M8 23 C14 21 22 22 28 23 M9 49 C16 52 23 51 27 49`} /> : null}
      </g>
      {spec.glasses ? <g fill="none" strokeWidth={1.25}>
        <path d={spec.glasses === "round" ? `M4 36 C9 33 23 33 28 37 L27 47 C21 51 10 51 5 47Z` : `M2 35 L27 35 L26 48 C17 50 8 50 3 47Z`} />
        <path d={`M31 36 L39 37 L38 47 L31 48Z M28 39 Q30 37 31 39 M3 39 C-9 39 -20 44 -30 54`} />
      </g> : null}
    </g>
  );
};
