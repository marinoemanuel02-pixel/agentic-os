import React from "react";
import { Composition } from "remotion";
import { FPS } from "./lib/look";
import { SHOTS, TOTAL_FRAMES } from "./data/timeline";
import { SHOT_COMPONENTS } from "./shots/registry";
import { Main } from "./Main";

const HD = { fps: FPS, width: 1920, height: 1080 };

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Main" component={Main} durationInFrames={TOTAL_FRAMES} {...HD} />
    {SHOTS.filter((s) => SHOT_COMPONENTS[s.id]).map((s) => (
      <Composition key={s.id} id={s.id} component={SHOT_COMPONENTS[s.id]} durationInFrames={s.frames} {...HD} />
    ))}
  </>
);
