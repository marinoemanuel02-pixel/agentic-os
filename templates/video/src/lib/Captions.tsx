// Captions drawn into the picture, keyed on the measured words (src/data/words.json, the script's words timed against
// each line's WAV). Timing lives in caption-timing.ts (tested); this draws it. Feeds autoplay muted, so social cuts
// need them; a card that carries its own type turns them off for its shot (`off`). Use with either route:
//   explainer (beat plan):  <Captions lines={LINES} shots={SHOTS} words={words} />            (src/data/timeline.ts)
//   word-cut short:         <Captions lines={edit.lines} shots={edit.shots} words={words} />   (src/data/edit.json)
// Style (metacognition-3d v11, 2026-11-15, after what short-form explainers use): bold sans in white with a thick dark
// outline and a soft shadow instead of a box, two short rows at most, the spoken word easing into a warm accent with a
// slight lift. 9:16: about 70 px, the block's bottom above the apps' bottom band (TikTok/Reels UI covers roughly the
// last 480 px and a right-hand column of about 150 px), centred in the free width. 16:9: lower third, 54 px.
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
  outline?: string; // the stroke and shadow behind the text
  font?: string;
  timing?: Partial<CaptionTiming>;
};

// two short rows (3-6 words) read at a glance on a phone; the wide frame takes one longer row pair
// a 0.12 s cross-fade between phrases: a phrase that replaces the last on one frame reads as a snap in the motion check
const TALL_STYLE: Partial<CaptionTiming> = { maxChars: 18, rows: 2, swap: 0.12 };
const WIDE_TIMING: Partial<CaptionTiming> = { maxChars: 32, rows: 2 };

const hex = (c: string) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
const blend = (a: string, b: string, k: number) => {
  const p = hex(a);
  const q = hex(b);
  return `rgb(${p.map((v, i) => Math.round(v + (q[i] - v) * k)).join(",")})`;
};

export const Captions: React.FC<CaptionsProps> = ({
  lines, words, shots = [], off = [], ink = "#FFFFFF", accent = "#FFC15E", outline = "#0B0B12", font = SANS, timing = {},
}) => {
  const f = useCurrentFrame();
  const fmt = useFormat();
  const T: CaptionTiming = { ...TALL_TIMING, ...(fmt.tall ? TALL_STYLE : WIDE_TIMING), ...timing };
  const chunks = React.useMemo(() => buildChunks(lines, words, FPS, T, shots, off), [lines, words, shots, off, fmt.tall, JSON.stringify(timing)]);
  const runs = React.useMemo(() => runsOf(chunks), [chunks]);
  const t = f / FPS;
  const at = shots.find((s) => f >= s.from && f < s.from + s.frames)?.id;
  if (at && off.includes(at)) return null; // the cut to a card ends the captions: no fade runs over it
  const { box: runOpacity, shown } = captionsAt(chunks, runs, t, T);
  if (!shown.length) return null;
  const size = fmt.tall ? 70 : 54;
  const left = fmt.tall ? 90 : 240;
  const right = fmt.tall ? SAFE.right - 10 : fmt.W - 240; // clear of the right-hand button column
  const bottom = fmt.tall ? 1400 : fmt.H - 96; // the block's bottom edge
  const stroke = Math.round(size * 0.3); // drawn behind the fill (paint-order), so half of it shows outside the glyph
  const lead = size * 1.16;
  const cx = (left + right) / 2;
  const lift = size * 0.06; // the spoken word rises this much (a tspan dy; the next word drops back)
  // SVG text (caption words are the narration, checked by the narration ledger; tools/checks/screen-text.mjs reads
  // computed HTML text as unreviewed screen text)
  return (
    <svg width={fmt.W} height={fmt.H} viewBox={`0 0 ${fmt.W} ${fmt.H}`} style={{ position: "absolute", left: 0, top: 0, opacity: runOpacity }}>
      <defs>
        <filter id="cap-shadow" x="-10%" y="-30%" width="120%" height="160%">
          <feDropShadow dx="0" dy={size * 0.06} stdDeviation={size * 0.12} floodColor="#000" floodOpacity="0.55" />
        </filter>
      </defs>
      {shown.map(({ c, o }) => (
        <g key={c.from} opacity={o} filter="url(#cap-shadow)">
          {c.rows.map((r, k) => {
            const y = bottom - (c.rows.length - 1 - k) * lead - size * 0.22;
            let prevLift = 0;
            return (
              <text key={k} x={cx} y={y} textAnchor="middle" fontFamily={font} fontSize={size} fontWeight={700}
                    letterSpacing="0.005em" stroke={outline} strokeWidth={stroke} strokeLinejoin="round" paintOrder="stroke" fill={ink}>
                {r.map((x, j) => {
                  const a = accentAt(t, x.a, x.b, T);
                  const dy = -lift * a - prevLift;
                  prevLift = -lift * a;
                  return <tspan key={j} dy={dy} fill={blend(ink, accent, a)}>{(j ? " " : "") + x.w}</tspan>;
                })}
              </text>
            );
          })}
        </g>
      ))}
    </svg>
  );
};
