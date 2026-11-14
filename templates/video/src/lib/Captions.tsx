// Captions drawn into the picture, keyed on the measured words (src/data/words.json, the script's words timed against
// each line's WAV). Timing lives in caption-timing.ts (tested); this draws it: the spoken word eases into the accent
// colour, text on a soft box. Feeds autoplay muted, so social cuts need them; a card that carries its own type turns
// them off for its shot (`off`). Use with either route:
//   explainer (beat plan):  <Captions lines={LINES} shots={SHOTS} words={words} />            (src/data/timeline.ts)
//   word-cut short:         <Captions lines={edit.lines} shots={edit.shots} words={words} />   (src/data/edit.json)
// 9:16 layout and timing are huggingface-it v6's (judged on the film); the 16:9 layout is a starting point that no
// film has been judged on yet.
import React from "react";
import { useCurrentFrame } from "remotion";
import { accentAt, buildChunks, captionsAt, runsOf, TALL_TIMING, type CaptionTiming, type LineAt, type ShotAt, type WordTuple } from "./caption-timing";
import { SAFE, useFormat } from "./format";
import { FPS, SANS } from "./look";

export type CaptionsProps = {
  lines: LineAt[];
  words: Record<string, WordTuple[]>;
  shots?: ShotAt[];
  off?: string[]; // shot ids whose own type replaces the captions
  ink?: string; // text colour
  accent?: string; // the spoken word
  box?: string; // the box behind the text
  font?: string;
  timing?: Partial<CaptionTiming>;
};

const WIDE_TIMING: Partial<CaptionTiming> = { maxChars: 34 };

const hex = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
const blend = (a: string, b: string, k: number) => {
  const p = hex(a);
  const q = hex(b);
  return `rgb(${p.map((v, i) => Math.round(v + (q[i] - v) * k)).join(",")})`;
};

export const Captions: React.FC<CaptionsProps> = ({
  lines, words, shots = [], off = [], ink = "#F4EBDD", accent = "#F2B544", box = "#14161C", font = SANS, timing = {},
}) => {
  const f = useCurrentFrame();
  const fmt = useFormat();
  const T: CaptionTiming = { ...TALL_TIMING, ...(fmt.tall ? {} : WIDE_TIMING), ...timing };
  const chunks = React.useMemo(() => buildChunks(lines, words, FPS, T, shots, off), [lines, words, shots, off, fmt.tall, JSON.stringify(timing)]);
  const runs = React.useMemo(() => runsOf(chunks), [chunks]);
  const t = f / FPS;
  const at = shots.find((s) => f >= s.from && f < s.from + s.frames)?.id;
  if (at && off.includes(at)) return null; // the cut to a card ends the captions: no fade runs over it
  const { box: boxOpacity, shown } = captionsAt(chunks, runs, t, T);
  if (!shown.length) return null;
  const size = fmt.tall ? 84 : 60;
  const lead = size * 1.18;
  const pad = 28;
  const height = (rows: number) => rows * lead + pad * 1.4;
  const left = fmt.tall ? 100 : 260;
  const width = fmt.tall ? SAFE.right - 100 : fmt.W - 2 * left;
  const cx = left + width / 2;
  const hBox = height(T.rows);
  const top = fmt.tall ? SAFE.bottom + 10 : fmt.H - 70 - hBox;
  return (
    <svg width={fmt.W} height={fmt.H} viewBox={`0 0 ${fmt.W} ${fmt.H}`} style={{ position: "absolute", left: 0, top: 0 }}>
      <rect x={cx - width / 2} y={top} width={width} height={hBox} rx={30} fill={box} opacity={0.72 * boxOpacity} />
      {shown.map(({ c, o }) => (
        <g key={c.from} opacity={o}>
          {c.rows.map((r, k) => (
            <text key={k} x={cx} y={top + (hBox - height(c.rows.length)) / 2 + pad + size * 0.82 + k * lead}
                  textAnchor="middle" fontFamily={font} fontSize={fmt.tall ? 84 : 60} fontWeight={700} fill={ink}>
              {r.map((x, j) => (
                <tspan key={j} fill={blend(ink, accent, accentAt(t, x.a, x.b, T))}>{(j ? " " : "") + x.w}</tspan>
              ))}
            </text>
          ))}
        </g>
      ))}
    </svg>
  );
};
