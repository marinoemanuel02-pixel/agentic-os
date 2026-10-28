// The transition library. Each takes the outgoing and incoming layers and a progress 0..1 (from transitionProgress,
// the calm R17 curve). Dissolves and match cuts stay the default join; the others are allowed only as the film's
// declared transition language in style.md and must appear in the hero (spec section 4, R28).
import React from "react";
import { AbsoluteFill } from "remotion";
import { pushOffsets, wipeInset } from "./core";

export type TransitionProps = { from: React.ReactNode; to: React.ReactNode; progress: number };
type T = React.FC<TransitionProps>;

const Layer: React.FC<{ style?: React.CSSProperties; children: React.ReactNode }> = ({ style, children }) => (
  <AbsoluteFill style={style}>{children}</AbsoluteFill>
);

export const Dissolve: T = ({ from, to, progress }) => (
  <AbsoluteFill>
    <Layer>{from}</Layer>
    <Layer style={{ opacity: progress }}>{to}</Layer>
  </AbsoluteFill>
);

export const Push: T = ({ from, to, progress }) => {
  const o = pushOffsets(progress, 1920);
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <Layer style={{ transform: `translateX(${o.from}px)` }}>{from}</Layer>
      <Layer style={{ transform: `translateX(${o.to}px)` }}>{to}</Layer>
    </AbsoluteFill>
  );
};

export const Wipe: T = ({ from, to, progress }) => (
  <AbsoluteFill>
    <Layer>{from}</Layer>
    <Layer style={{ clipPath: wipeInset(progress) }}>{to}</Layer>
  </AbsoluteFill>
);

// A soft-edged wipe: the incoming layer is revealed behind a moving gradient edge 20 % of the frame wide.
export const LumaWipe: T = ({ from, to, progress }) => {
  const edge = -20 + progress * 140;
  const mask = `linear-gradient(100deg, #000 ${edge - 20}%, transparent ${edge}%)`;
  return (
    <AbsoluteFill>
      <Layer>{from}</Layer>
      <Layer style={{ WebkitMaskImage: mask, maskImage: mask }}>{to}</Layer>
    </AbsoluteFill>
  );
};

// The camera flies into the outgoing frame while the incoming one settles from slightly large.
export const ZoomThrough: T = ({ from, to, progress }) => (
  <AbsoluteFill style={{ overflow: "hidden" }}>
    <Layer style={{ transform: `scale(${1 + progress * 0.6})`, opacity: 1 - progress }}>{from}</Layer>
    <Layer style={{ transform: `scale(${1.15 - progress * 0.15})`, opacity: progress }}>{to}</Layer>
  </AbsoluteFill>
);

// A whip pan: both layers travel with motion blur that peaks mid-move and is gone at both ends.
export const WhipBlur: T = ({ from, to, progress }) => {
  const o = pushOffsets(progress, 1920);
  const blur = Math.sin(progress * Math.PI) * 28;
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <Layer style={{ transform: `translateX(${o.from}px)`, filter: `blur(${blur}px)` }}>{from}</Layer>
      <Layer style={{ transform: `translateX(${o.to}px)`, filter: `blur(${blur}px)` }}>{to}</Layer>
    </AbsoluteFill>
  );
};

export const TRANSITIONS: Record<"dissolve" | "push" | "wipe" | "lumaWipe" | "zoomThrough" | "whipBlur", T> = {
  dissolve: Dissolve,
  push: Push,
  wipe: Wipe,
  lumaWipe: LumaWipe,
  zoomThrough: ZoomThrough,
  whipBlur: WhipBlur,
};

export { GlTransition, SHADERS } from "../media/GlTransition";
