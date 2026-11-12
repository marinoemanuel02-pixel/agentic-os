// Cast review sheets (not part of a film): the cast in the pose library, three characters close up, the mouth set and
// the hand set. Render them before a film's people go into shots, and again after any change to the kit:
//   bash tools/still.sh 0 CastSheet CastTrio CastFaces CastHands
// then judge them against frontier.md ("Characters and acting") and, blind, against the last film's cast.
import React from "react";
import { AbsoluteFill } from "remotion";
import { CAST } from "./palette";
import { Person, POSES, walk, type HandPose, type MouthShape } from "./Person";

const MOUTHS: MouthShape[] = ["neutral", "smile", "frown", "A", "E", "O", "M", "F", "L", "surprise"];
const HANDS: HandPose[] = ["relaxed", "open", "wave", "support", "point", "fist", "grip", "hold"];

/** a placeholder chest mark: a star in a 40-unit box */
const Star = () => <path d={`M 0 -18 L 5 -6 L 18 -6 L 8 3 L 12 16 L 0 8 L -12 16 L -8 3 L -18 -6 L -5 -6 Z`} fill={CAST.danger} />;

export const CastSheet: React.FC<{ part?: "cast" | "trio" | "faces" | "hands" }> = ({ part = "cast" }) => (
  <AbsoluteFill style={{ background: `linear-gradient(${CAST.nightMid}, ${CAST.night})` }}>
    <svg viewBox="0 0 1920 1080" width={1920} height={1080}>
      <rect x={0} y={900} width={1920} height={180} fill="#2b2a44" />
      {part === "cast" ? (
        <g>
          <Person x={110} y={1000} scale={1.3} outfit="teal" hair="short" tone={0} hairTone={1} badge={<Star />} pose={POSES.stand} />
          <Person x={330} y={1000} scale={1.3} outfit="coat" hair="bun" tone={2} hairTone={2} glasses build="slim" pose={POSES.explain} />
          <Person x={570} y={1000} scale={1.3} outfit="suit" hair="bald" tone={1} hairTone={0} beard build="broad" pose={POSES.point} />
          <Person x={810} y={1000} scale={1.3} outfit="brick" hair="long" tone={3} hairTone={0} build="slim" pose={POSES.concern} />
          <Person x={1040} y={1000} scale={1.3} outfit="slate" hair="side" tone={1} hairTone={3} pose={POSES.reassure} />
          <Person x={1270} y={1000} scale={1.3} outfit="mustard" hair="pony" tone={0} hairTone={3} pose={{ ...walk(0.15), turn: 0.5 }} />
          <Person x={1500} y={1000} scale={1.3} outfit="teal" hair="curly" tone={2} hairTone={2} build="broad" pose={POSES.wave} />
          <Person x={1700} y={1000} scale={1.3} outfit="mustard" hair="bob" tone={3} hairTone={1} child pose={{ ...POSES.attentive, look: [0.3, -1], wide: 0.4 }} />
        </g>
      ) : part === "trio" ? (
        <g>
          <Person x={330} y={1050} scale={2.45} outfit="teal" hair="short" tone={0} hairTone={1} badge={<Star />} pose={POSES.stand} />
          <Person x={950} y={1050} scale={2.45} outfit="coat" hair="pony" tone={2} hairTone={2} glasses build="slim" pose={{ ...walk(0.2), turn: 0.5 }} />
          <Person x={1580} y={1050} scale={2.45} facing={-1} outfit="suit" hair="bald" beard tone={1} build="broad" pose={POSES.reassure} />
        </g>
      ) : part === "hands" ? (
        <g>
          {[...HANDS].reverse().map((h, j) => {
            const i = HANDS.length - 1 - j;
            return (
              <Person
                key={h}
                x={(i % 4) * 480 + 20}
                y={i < 4 ? 900 : 1410}
                scale={2.2}
                shadow={false}
                outfit={i % 2 ? "slate" : "teal"}
                hair="short"
                tone={(i % 4) as 0 | 1 | 2 | 3}
                pose={{ armR: [90, h === "wave" ? 70 : 0], handR: h, turn: 0 }}
                hold={h === "grip" ? <rect x={-5} y={-30} width={10} height={70} rx={4} fill="#c9a46a" /> : h === "hold" ? <rect x={-16} y={-6} width={32} height={54} rx={6} fill="#1b1c2c" /> : undefined}
              />
            );
          })}
        </g>
      ) : (
        <g>
          {MOUTHS.map((m, i) => (
            <Person
              key={m}
              x={110 + i * 185}
              y={1480}
              scale={2.6}
              shadow={false}
              outfit={i % 2 ? "slate" : "teal"}
              hair={(["short", "bob", "curly", "side", "long"] as const)[i % 5]}
              tone={(i % 4) as 0 | 1 | 2 | 3}
              hairTone={((i + 1) % 4) as 0 | 1 | 2 | 3}
              pose={{ mouth: m, turn: i % 3 === 0 ? 0 : 0.5 }}
            />
          ))}
        </g>
      )}
    </svg>
  </AbsoluteFill>
);
