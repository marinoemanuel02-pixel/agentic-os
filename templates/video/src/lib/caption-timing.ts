// Caption timing, pure (no React): the words as measured (words.json, per line, seconds from the line's start) become
// chunks of at most `rows` rows, chunks close together share one box (a run), the box fades at the ends of a run and,
// inside it, the next chunk replaces the last on the same frame. Ported from huggingface-it v6 (2026-10-30, the
// frontier's best captions); the run boxes and smootherstep fades come from pauseai-it-allineamento, the only caption
// timing that passed the motion check. Captions.tsx draws it; tools/checks/captions.test.mts holds it.

export type WordTuple = [string, number, number];
export type Word = { w: string; a: number; b: number };
export type Chunk = { rows: Word[][]; from: number; to: number };
export type LineAt = { id: string; from: number };
export type ShotAt = { id: string; from: number; frames: number };

export type CaptionTiming = {
  maxChars: number; // characters per row
  rows: number; // rows per chunk
  boxFade: number; // s; shorter box fades read as snaps in the motion check
  gap: number; // s; chunks closer than this share one box
  swap: number; // s, each half of a word swap inside a run (out, then in); 0 = the next chunk replaces the last on one frame
  swapLead: number; // s; the swap lands this much before the next chunk's first word
  accentFade: number; // s; the spoken word's colour eases in and out
  tail: number; // s a chunk stays after its last word when nothing follows
};

/** huggingface-it's values (9:16, 84 px, narration at about 250 words a minute). */
export const TALL_TIMING: CaptionTiming = {
  maxChars: 20, rows: 2, boxFade: 0.5, gap: 0.9, swap: 0, swapLead: 0.05, accentFade: 0.16, tail: 0.6,
};
// huggingface-it used swap 0.001 s: a handover that fell exactly on a frame left that frame empty (both halves at 0).
// 0 is now an exact switch at the handover instant.

/** Smootherstep on 0..1: no velocity jump at either end. */
export const smooth = (x: number): number => {
  const t = Math.min(1, Math.max(0, x));
  return t * t * t * (t * (6 * t - 15) + 10);
};

/** Rows of at most maxChars characters; a chunk ends at `rows` rows or after punctuation that closes a phrase. */
export const chunksOf = (ws: Word[], timing: CaptionTiming): Chunk[] => {
  const out: Chunk[] = [];
  let rows: Word[][] = [[]];
  const len = (r: Word[]) => r.map((x) => x.w).join(" ").length;
  const flush = () => {
    if (rows[0].length) out.push({ rows, from: rows[0][0].a, to: 0 });
    rows = [[]];
  };
  for (const x of ws) {
    let r = rows[rows.length - 1];
    if (r.length && len([...r, x]) > timing.maxChars) {
      if (rows.length >= timing.rows) flush();
      else rows.push([]);
      r = rows[rows.length - 1];
    }
    r.push(x);
    if (/[.?!:]$/.test(x.w) || (/,$/.test(x.w) && rows.length === timing.rows)) flush();
  }
  flush();
  return out;
};

/** The shot playing at `sec`, if any. */
export const shotAt = (shots: ShotAt[], sec: number, fps: number): string | undefined =>
  shots.find((s) => sec * fps >= s.from && sec * fps < s.from + s.frames)?.id;

/**
 * Every chunk of the film in time order, in seconds from the film's start. A chunk whose first word falls on a shot in
 * `off` (a card carrying its own type) is dropped; each chunk's `to` is the next chunk's start when they are closer
 * than `gap` (same box), otherwise its last word's end plus `tail`.
 */
export const buildChunks = (lines: LineAt[], words: Record<string, WordTuple[]>, fps: number, timing: CaptionTiming,
                            shots: ShotAt[] = [], off: string[] = []): Chunk[] => {
  const all: Chunk[] = [];
  for (const l of lines) {
    const ws = (words[l.id] ?? []).map(([w, a, b]) => ({ w, a: l.from / fps + a, b: l.from / fps + b }));
    all.push(...chunksOf(ws, timing));
  }
  all.sort((p, q) => p.from - q.from);
  const kept = all.filter((c) => !off.includes(shotAt(shots, c.from, fps) ?? ""));
  kept.forEach((c, i) => {
    const lastRow = c.rows[c.rows.length - 1];
    const lastWord = lastRow[lastRow.length - 1];
    const next = kept[i + 1];
    c.to = next && next.from - lastWord.b < timing.gap ? next.from : lastWord.b + timing.tail;
  });
  return kept;
};

/** Runs of chunks that share one box: each follows the previous with no gap (to >= next.from). */
export const runsOf = (chunks: Chunk[]): [number, number][] => {
  const out: [number, number][] = [];
  chunks.forEach((c, i) => {
    const r = out[out.length - 1];
    if (r && chunks[i - 1].to >= c.from) r[1] = i;
    else out.push([i, i]);
  });
  return out;
};

export type Shown = { c: Chunk; o: number };

/** What is on screen at `t` seconds: the box opacity and every chunk with its opacity. */
export const captionsAt = (chunks: Chunk[], runs: [number, number][], t: number, timing: CaptionTiming): { box: number; shown: Shown[] } => {
  const { boxFade, swap, swapLead } = timing;
  const live = runs
    .map(([a, b]) => ({ a, b, box: Math.min(smooth((t - (chunks[a].from - boxFade)) / boxFade), smooth((chunks[b].to + boxFade - t) / boxFade)) }))
    .filter((r) => r.box > 0);
  if (!live.length) return { box: 0, shown: [] };
  const box = Math.max(...live.map((r) => r.box));
  // swap halves: the outgoing chunk is gone at the handover instant h = next.from - swapLead, the incoming one starts there
  const fadeIn = (h: number) => (swap > 0 ? smooth((t - h) / swap) : t >= h ? 1 : 0);
  const fadeOut = (h: number) => (swap > 0 ? smooth((h - t) / swap) : t < h ? 1 : 0);
  const shown = live
    .flatMap((r) => chunks.slice(r.a, r.b + 1).map((c, k) => ({
      c,
      o: r.box * Math.min(k === 0 ? 1 : fadeIn(c.from - swapLead), r.a + k === r.b ? 1 : fadeOut(c.to - swapLead)),
    })))
    .filter((x) => x.o > 0);
  return { box, shown };
};

/** The spoken word's accent strength at `t` (0 = text colour, 1 = accent colour). */
export const accentAt = (t: number, a: number, b: number, timing: CaptionTiming): number =>
  Math.min(smooth((t - (a - timing.accentFade)) / timing.accentFade), smooth((b + timing.accentFade - t) / timing.accentFade));

/**
 * Readable time (the frontier's next caption target): the share of narrated frames, frames inside a measured word,
 * that show one whole chunk at full opacity. 1 means a viewer can always read what is being said.
 */
export const readableShare = (chunks: Chunk[], timing: CaptionTiming, fps: number): number => {
  const runs = runsOf(chunks);
  let narrated = 0;
  let readable = 0;
  for (const c of chunks) {
    for (const w of c.rows.flat()) {
      for (let f = Math.ceil(w.a * fps); f < w.b * fps; f++) {
        narrated++;
        const { shown } = captionsAt(chunks, runs, f / fps, timing);
        if (shown.some((s) => s.o >= 0.99)) readable++;
      }
    }
  }
  return narrated ? readable / narrated : 1;
};
