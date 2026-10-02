// Pure timeline maths (no imports besides look.ts), shared by the Remotion code and the Node tools.
// Fill LINE_SLOTS from the measured voice (tools/make-voice.cjs writes vo.json): a slot is
// ceil((seconds + PAD) / 0.6) beats, plus one beat of music before a new chapter. Freeze the slots once picture
// work starts; a new voice must then fit inside them (tools/check-plan.mts fails if it does not).
import { BEAT, FPS } from "../lib/look.ts";

export const INTRO_BEATS = 2;
export const OUTRO_BEATS = 4;
export const LINE_SLOTS: [string, number, number][] = [
  // id, start beat, beats
  ["L1", 2, 8],
];
export const PAD = 0.1; // seconds of air a line needs at the end of its slot

/** Edit order and length in beats (2-4 s = 4-6 beats per shot). Must sum to the line plan's total. */
export const SHOT_BEATS: [string, number][] = [
  ["S01", 6], ["S02", 8],
];

/** YouTube chapters: [first shot of the chapter, title]. The first must be the first shot; each lasts >= 10 s. */
export const CHAPTERS: [string, string][] = [["S01", "Opening"]];

/** Shots that must start exactly with a line (the hero, chapter openers): [shot, line]. */
export const ANCHORS: [string, string][] = [];

export type Vo = { id: string; file: string; seconds: number };
export type LineSlot = Vo & { startBeat: number; beats: number; from: number; fits: boolean };

export const buildLines = (vo: Vo[]): LineSlot[] =>
  LINE_SLOTS.map(([id, startBeat, beats]) => {
    const v = vo.find((x) => x.id === id) ?? { id, file: `vo/${id}.wav`, seconds: 0 };
    return { ...v, startBeat, beats, from: startBeat * BEAT, fits: v.seconds + PAD <= (beats * BEAT) / FPS };
  });

export type ShotSlot = { id: string; startBeat: number; beats: number; from: number; frames: number };
export const buildShots = (): ShotSlot[] => {
  let b = 0;
  return SHOT_BEATS.map(([id, beats]) => {
    const s = { id, startBeat: b, beats, from: b * BEAT, frames: beats * BEAT };
    b += beats;
    return s;
  });
};

export const totalBeats = (lines: LineSlot[]) => lines[lines.length - 1].startBeat + lines[lines.length - 1].beats + OUTRO_BEATS;
