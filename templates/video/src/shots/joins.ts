import type {Pose} from '../lib/shot-camera.ts';
// Author one start/end pair per shot after the framing is reviewed. No example film poses are shipped.
export const JOINS: Record<string, {start: Pose; end: Pose}> = {};
