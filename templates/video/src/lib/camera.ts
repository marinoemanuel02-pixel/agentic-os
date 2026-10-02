// Camera paths: Catmull-Rom splines through key poses, driven by an eased 0..1 progress, so moves are
// continuous (no velocity jumps at keyframes) and land softly.
import * as THREE from "three";
import { Easing, interpolate } from "remotion";
import type { CameraPose } from "./Stage";

type V3 = [number, number, number];
export type CamKey = { pos: V3; target: V3; fov?: number };

export const cameraPath = (keys: CamKey[], f: number, frames: number, ease = Easing.bezier(0.45, 0, 0.2, 1)): CameraPose => {
  const t = interpolate(f, [0, frames - 1], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });
  const curve = (pick: (k: CamKey) => V3) => new THREE.CatmullRomCurve3(keys.map((k) => new THREE.Vector3(...pick(k))), false, "centripetal");
  const p = curve((k) => k.pos).getPoint(t);
  const q = curve((k) => k.target).getPoint(t);
  const fovs = keys.map((k) => k.fov ?? 32);
  const fi = t * (fovs.length - 1);
  const i = Math.min(fovs.length - 2, Math.floor(fi));
  const fov = fovs[i] + (fovs[i + 1] - fovs[i]) * (fi - i);
  return { pos: [p.x, p.y, p.z], target: [q.x, q.y, q.z], fov };
};

/** Frames at which events happen (impacts), for sound and for light pulses. */
export const pulse = (f: number, events: number[], decay = 6) =>
  events.reduce((a, e) => (f >= e ? a + Math.exp(-(f - e) / decay) : a), 0);
