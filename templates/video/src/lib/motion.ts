// Motion rules for this film: everything moves slowly and lands softly (the user called v1/v2 "too snappy").
// Every move goes through these helpers, so the motion check (tools/checks/motion.mjs) can trust the source:
// no expo-out or back-out curves, no move shorter than MIN_MOVE_FRAMES, holds that breathe.
import { Easing, interpolate, spring } from "remotion";
import { FPS } from "./look";
import { SOFT_POINTS } from "./ease";

export { mix } from "./ease";

/** The shortest move allowed for anything that travels (0.6 s at 30 fps). Small accents (blinks) use `blink`. */
export const MIN_MOVE_FRAMES = 18;

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Sine-like in-out: starts and ends at rest. The default for every move. */
export const SOFT = Easing.bezier(...SOFT_POINTS);
/** Gentle arrival for things that enter already moving (a boat, a running Pip). Zero slope at the end only. */
export const ARRIVE = Easing.bezier(0.3, 0.2, 0.4, 1);
/** Gentle departure: zero slope at the start only. */
export const LEAVE = Easing.bezier(0.6, 0, 0.7, 0.8);

/** 0..1 over [at, at + dur] with SOFT. `dur` is raised to MIN_MOVE_FRAMES. */
export const move = (f: number, at: number, dur: number, ease = SOFT) =>
  interpolate(f, [at, at + Math.max(dur, MIN_MOVE_FRAMES)], [0, 1], { ...clamp, easing: ease });

/** Linear map with SOFT easing between two values. */
export const tween = (f: number, at: number, dur: number, from: number, to: number, ease = SOFT) =>
  from + (to - from) * move(f, at, dur, ease);

/** A heavy, slow settle with a small overshoot (about 4 %): for things that land (Pip hopping down, a coin set). */
export const settle = (f: number, at: number) =>
  spring({ frame: f - at, fps: FPS, config: { damping: 16, mass: 1.4, stiffness: 55 } });

/** Breathing for holds: a slow sine of amplitude `amp`, period `period` frames, phase in turns. */
export const breathe = (f: number, amp: number, period = 96, phase = 0) => amp * Math.sin(((f / period) + phase) * Math.PI * 2);

/** A blink: 0 = open, 1 = closed, 6 frames down and 8 up, centred on `at`. Blinks may be quick: lids, not travel. */
export const blink = (f: number, at: number) => {
  const d = f - at;
  if (d < -6 || d > 8) return 0;
  return d < 0 ? 1 + d / 6 : 1 - d / 8;
};

/** Blinks at a natural rhythm: a fixed list of frames per character, so shots stay deterministic. */
export const blinks = (f: number, at: number[]) => Math.max(0, ...at.map((a) => blink(f, a)));

/** Line boil: the seed for hand-drawn lines changes every 4 frames (7.5 fps), motion itself stays at 30 fps. */
export const boilSeed = (f: number) => Math.floor(f / 4) % 7;

/** Follow-through for an appendage that trails a moving body: the lagged value of a signal. */
export const lag = (signal: (f: number) => number, f: number, frames = 5) => signal(f - frames);
