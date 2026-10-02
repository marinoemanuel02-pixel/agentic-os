// The full film: every shot in edit order, hard cuts on the beat. A shot that is not built yet shows a slate.
import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { SHOTS } from "./data/timeline";
import { SANS } from "./lib/look";
import { useFonts } from "./lib/Type";
import { SHOT_COMPONENTS } from "./shots/registry";

const Slate: React.FC<{ id: string }> = ({ id }) => (
  <AbsoluteFill style={{ backgroundColor: "#111", justifyContent: "center", alignItems: "center", fontFamily: SANS, fontSize: 64, color: "#8d877c" }}>
    {id} (not built)
  </AbsoluteFill>
);

export const Main: React.FC = () => {
  useFonts();
  return (
    <AbsoluteFill style={{ backgroundColor: "#000" }}>
      {SHOTS.map((s) => {
        const C = SHOT_COMPONENTS[s.id];
        return (
          <Sequence key={s.id} from={s.from} durationInFrames={s.frames} name={s.id}>
            {C ? <C /> : <Slate id={s.id} />}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
