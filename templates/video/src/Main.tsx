// The full film: every shot in edit order. A shot marked "x" in plan.ts dissolves in over its first `xin` frames
// while the previous shot keeps playing underneath (that shot's Sequence runs `tail` frames past its slot).
// A shot that is not built yet shows a slate.
import React from "react";
import { AbsoluteFill, interpolate, Sequence, useCurrentFrame } from "remotion";
import { SHOTS } from "./data/timeline";
import { SANS } from "./lib/look";
import { SOFT } from "./lib/motion";
import { useFonts } from "./lib/Type";
import { SHOT_COMPONENTS } from "./shots/registry";
import { Captions } from "./lib/Captions";
import { FormatProvider, TALL } from "./lib/format";
import { LINES } from "./data/timeline";
import words from "./data/words.json";
import lines from "./data/lines.json";
import type { WordTuple } from "./lib/caption-timing";

const Slate: React.FC<{ id: string }> = ({ id }) => (
  <AbsoluteFill style={{ backgroundColor: "#2a211c", justifyContent: "center", alignItems: "center", fontFamily: SANS, fontSize: 64, color: "#c9b79f" }}>
    {id} (not built)
  </AbsoluteFill>
);

const FadeIn: React.FC<{ frames: number; children: React.ReactNode }> = ({ frames, children }) => {
  const f = useCurrentFrame();
  const o = frames > 0 ? interpolate(f, [0, frames], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: SOFT }) : 1;
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

export const Main: React.FC = () => {
  useFonts();
  return (
    <AbsoluteFill style={{ backgroundColor: "#000" }}>
      {SHOTS.map((s) => {
        const C = SHOT_COMPONENTS[s.id];
        return (
          <Sequence key={s.id} from={s.from} durationInFrames={s.frames + s.tail} name={s.id}>
            <FadeIn frames={s.xin}>{C ? <C /> : <Slate id={s.id} />}</FadeIn>
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

// The captions show the script's own words (its `caption` text) on Whisper's timings: when a line has the same word
// count in both, the n-th measured word gets the n-th script word (spelling and punctuation from the script).
const CAPTION_WORDS: Record<string, WordTuple[]> = Object.fromEntries(
  (lines as { id: string; caption?: string; text: string }[]).map((l) => {
    const timed = (words as Record<string, WordTuple[]>)[l.id] ?? [];
    const script = (l.caption ?? l.text).split(/\s+/).filter(Boolean);
    return [l.id, timed.map(([w, a, b], i) => [script.length === timed.length ? script[i] : w, a, b] as WordTuple)];
  }),
);

/** The native 9:16 film for TikTok, Reels and Shorts: every shot staged for the tall frame, captions drawn in. */
export const MainTall: React.FC = () => (
  <FormatProvider format={TALL}>
    <Main />
    <Captions lines={LINES} shots={SHOTS} words={CAPTION_WORDS} />
  </FormatProvider>
);
