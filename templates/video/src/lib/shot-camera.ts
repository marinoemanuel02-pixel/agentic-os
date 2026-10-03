// Frame-keyed cameras hold their join poses through incoming/outgoing dissolves.
// Use the film frame for breathing drift and lighting so held poses also render identically.
export type Pose = {pos: [number, number, number]; target: [number, number, number]; fov?: number};
export type Key = {f: number; pose: Pose};
export const DEFAULT_FOV = 30;
export const validPose = (p: Pose): boolean => !!p &&
  [p.pos, p.target].every(v => Array.isArray(v) && v.length === 3 && v.every(Number.isFinite)) &&
  Number.isFinite(p.fov ?? DEFAULT_FOV);

export const shotCamera = (
  shot: {id: string; frames: number; xin: number}, join: {start: Pose; end: Pose}, inner: Key[], f: number,
): Pose => {
  if (![f, shot.frames, shot.xin].every(Number.isFinite) || shot.frames <= shot.xin || shot.xin < 0) {
    throw new Error(`${shot.id}: camera frame/slot must be finite and leave room after the dissolve`);
  }
  const keys: Key[] = [{f: 0, pose: join?.start}];
  if (shot.xin) keys.push({f: shot.xin, pose: join.start});
  for (const k of inner) {
    if (!Number.isFinite(k.f)) throw new Error(`${shot.id}: camera key is not finite`);
    if (k.f <= keys.at(-1)!.f) throw new Error(`${shot.id}: camera key at ${k.f} is not after ${keys.at(-1)!.f}`);
    keys.push(k);
  }
  if (keys.at(-1)!.f >= shot.frames) throw new Error(`${shot.id}: camera key must come before the slot end ${shot.frames}`);
  keys.push({f: shot.frames, pose: join?.end});
  for (const k of keys) if (!validPose(k.pose)) throw new Error(`${shot.id}: camera key pose is not finite or malformed`);
  if (f <= 0) return keys[0].pose;
  if (f >= shot.frames) return keys.at(-1)!.pose;
  const i = keys.findIndex((k, n) => n > 0 && f <= k.f);
  const a = keys[i - 1], b = keys[i];
  const x = (f - a.f) / (b.f - a.f), t = x * x * (3 - 2 * x);
  const vector = (u: number[], v: number[]) => u.map((n, j) => n + (v[j] - n) * t) as [number, number, number];
  return {pos: vector(a.pose.pos, b.pose.pos), target: vector(a.pose.target, b.pose.target),
    fov: (a.pose.fov ?? DEFAULT_FOV) + ((b.pose.fov ?? DEFAULT_FOV) - (a.pose.fov ?? DEFAULT_FOV)) * t};
};
