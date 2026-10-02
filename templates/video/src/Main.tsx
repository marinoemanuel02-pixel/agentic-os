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
