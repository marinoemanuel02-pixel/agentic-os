// Sound events per shot, frames relative to the shot start. Pure data: tools/audio.mts imports it.
// Kinds: impact (pitch 0.7-1.3, gain 0-1), hit, tick, whoosh (gain), glass. Builders working in parallel each
// own one file (e.g. batchA.events.ts) and are spread in here, so they never edit the same file.
export type SfxEvent = { frame: number; kind: string; gain?: number; pitch?: number };

export const EVENTS: Record<string, SfxEvent[]> = {};
// Author word-timed events with cue(shotId, lineId, word, occurrence). Picture and audio share cue-core.
export const buildEvents = (cue: (shot: string, line: string, word: string, nth?: number) => number): Record<string, SfxEvent[]> => EVENTS;
