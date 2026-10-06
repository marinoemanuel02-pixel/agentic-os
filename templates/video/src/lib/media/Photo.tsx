// An imported still by asset id (R35), graded into the look, with a calm pan and zoom between two framings
// (scale and offset in percent of the frame) over the shot.
import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ASSETS } from "../../data/assets";
import { USES } from "../../data/asset-uses";
import { gradeFilter, type Look } from "../look";
import { tween } from "../motion";
import { SourceTag } from "./SourceTag";

type Framing = { scale: number; x: number; y: number };
type Props = { asset: keyof typeof ASSETS & string; use?: string; look: Look; from?: Framing; to?: Framing };

const STILL: Framing = { scale: 1.04, x: 0, y: 0 };

export const Photo: React.FC<Props> = ({ asset, use, look, from = STILL, to = { scale: 1.12, x: -2, y: -1 } }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const s = tween(frame, 0, durationInFrames, from.scale, to.scale);
  const x = tween(frame, 0, durationInFrames, from.x, to.x);
  const y = tween(frame, 0, durationInFrames, from.y, to.y);
  const credit = use ? USES[asset][use].credit : null;
  return (
    <AbsoluteFill style={{ overflow: "hidden", background: look.bg }}>
      <Img
        src={staticFile(ASSETS[asset].src)}
        style={{ width: "100%", height: "100%", objectFit: "cover", transform: `translate(${x}%, ${y}%) scale(${s})`, filter: gradeFilter(look) }}
      />
      {credit ? <SourceTag text={credit} ink={look.ink} /> : null}
    </AbsoluteFill>
  );
};
