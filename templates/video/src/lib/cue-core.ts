// Word cues as a pure function of data (no JSON imports), so the picture (src/lib/cues.ts) and the soundtrack
// (tools/audio.mts) compute the very same frames from the measured voice.
export type WordTimes = Record<string, [string, number, number][]>;
type Slot = { id: string; from: number; seconds?: number };

const norm = (w: string) => w.toLowerCase().replace(/[^a-z0-9']/g, "");

export const makeCues = (words: WordTimes, lines: Slot[], shots: Slot[], fps: number, aliases: Record<string, string> = {}) => {
  /** Seconds into line `id` where `word` (its `nth` occurrence, 1-based) starts. */
  const wordAt = (id: string, word: string, nth = 1): number => {
    const list = words[id];
    if (!list) throw new Error(`no word times for ${id}`);
    // the script's spelling first, then the recognizer's (it may write a spelled acronym as "a GI" or as "AGI")
    for (const want of [norm(word), aliases[norm(word)]].filter(Boolean)) {
      let seen = 0;
      for (const [w, start] of list) if (norm(w) === want && ++seen === nth) return start;
    }
    throw new Error(`word "${word}" (#${nth}) not found in ${id}`);
  };
  const find = (shotId: string, id: string) => {
    const line = lines.find((l) => l.id === id);
    const shot = shots.find((s) => s.id === shotId);
    if (!line || !shot) throw new Error(`unknown ${shotId}/${id}`);
    return { line, shot };
  };
  /** Frame inside shot `shotId` at which `word` of line `id` starts. */
  const cue = (shotId: string, id: string, word: string, nth = 1): number => {
    const { line, shot } = find(shotId, id);
    return line.from - shot.from + Math.round(wordAt(id, word, nth) * fps);
  };
  /** Frame inside shot `shotId` at which line `id` ends (its measured length). */
  const lineEnd = (shotId: string, id: string): number => {
    const { line, shot } = find(shotId, id);
    return line.from - shot.from + Math.round((line.seconds ?? 0) * fps);
  };
  return { wordAt, cue, lineEnd };
};
