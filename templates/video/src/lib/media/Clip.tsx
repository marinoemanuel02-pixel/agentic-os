// An imported clip by asset id and use (R35): the silent proxy trimmed in media seconds, the film's grade, an
// optional calm push through motion.ts (R17), and the generated source tag for fair-use and capture rows.
// Media paths come only from src/data/assets.ts; sound, when a use keeps it, is mixed by tools/audio.mts.
import React from "react";
import { AbsoluteFill, OffthreadVideo, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ASSETS } from "../../data/assets";
import { USES } from "../../data/asset-uses";
import { clipWindow } from "../transitions/core";
import { gradeFilter, type Look } from "../look";
import { tween } from "../motion";
import { SourceTag } from "./SourceTag";

type Props = { asset: keyof typeof ASSETS & string; use: string; look: Look; push?: number };

export const Clip: React.FC<Props> = ({ asset, use, look, push = 0 }) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const u = USES[asset][use];
  const w = clipWindow(u, fps);
  const scale = tween(frame, 0, durationInFrames, 1, 1 + push);
  return (
    <AbsoluteFill style={{ overflow: "hidden", background: look.bg }}>
      <OffthreadVideo
        src={staticFile(ASSETS[asset].src)}
        startFrom={w.startFrom}
        endAt={w.endAt}
        muted
        style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${scale})`, filter: gradeFilter(look) }}
      />
      {u.credit ? <SourceTag text={u.credit} ink={look.ink} /> : null}
    </AbsoluteFill>
  );
};
