import React from "react";
import { Composition } from "remotion";
import { FPS } from "./lib/look";
import { SHOTS, TOTAL_FRAMES } from "./data/timeline";
import { SHOT_COMPONENTS } from "./shots/registry";
import { Main } from "./Main";
import { CastSheet } from "./lib/cast/CastSheet";

const HD = { fps: FPS, width: 1920, height: 1080 };

// Each shot's composition includes its tail: the frames it keeps playing under the next shot's dissolve.
export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Main" component={Main} durationInFrames={TOTAL_FRAMES} {...HD} />
    {SHOTS.filter((s) => SHOT_COMPONENTS[s.id]).map((s) => (
      <Composition key={s.id} id={s.id} component={SHOT_COMPONENTS[s.id]} durationInFrames={s.frames + s.tail} {...HD} />
    ))}
    {/* cast review sheets (src/lib/cast): render before people go into shots and after any change to the kit */}
    {(["cast", "trio", "faces", "hands"] as const).map((part) => (
      <Composition key={part} id={`Cast${part === "cast" ? "Sheet" : part[0].toUpperCase() + part.slice(1)}`} component={CastSheet} durationInFrames={1} defaultProps={{ part }} {...HD} />
    ))}
  </>
);
