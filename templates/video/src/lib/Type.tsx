// Type helpers: wait for the system fonts before a frame is captured, and animate type with the scene.
import React, { useEffect, useState } from "react";
import { continueRender, delayRender, Easing, interpolate, useCurrentFrame } from "remotion";
import { SANS, SERIF } from "./look";
import { SOFT } from "./motion";

export const useFonts = () => {
  const [handle] = useState(() => delayRender("system fonts"));
  useEffect(() => {
    Promise.all([
      document.fonts.load(`400 100px ${SERIF}`),
      document.fonts.load(`italic 400 100px ${SERIF}`),
      document.fonts.load(`300 100px ${SANS}`),
      document.fonts.load(`600 100px ${SANS}`),
    ]).finally(() => continueRender(handle));
  }, [handle]);
};

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** A line of type that rises out of a mask with a slight de-blur: starts at `at`, lasts `dur` frames. */
export const Reveal: React.FC<{ at: number; dur?: number; children: React.ReactNode; style?: React.CSSProperties; out?: number }> = ({
  at,
  dur = 24,
  children,
  style,
  out,
}) => {
  const f = useCurrentFrame();
  const t = interpolate(f, [at, at + dur], [0, 1], { ...clamp, easing: SOFT });
  const o = out === undefined ? 1 : interpolate(f, [out, out + 20], [1, 0], { ...clamp, easing: Easing.in(Easing.cubic) });
  return (
    <div style={{ overflow: "hidden", paddingBottom: "0.08em", ...style }}>
      <div style={{ transform: `translateY(${(1 - t) * 105}%)`, opacity: Math.min(1, t * 1.4) * o, filter: `blur(${(1 - t) * 6}px)` }}>
        {children}
      </div>
    </div>
  );
};

/** Small all-caps label in the numerals face. */
export const Label: React.FC<{ color: string; children: React.ReactNode; style?: React.CSSProperties }> = ({ color, children, style }) => (
  <div style={{ fontFamily: SANS, fontWeight: 400, fontSize: 22, letterSpacing: "0.22em", textTransform: "uppercase", color, fontStretch: "condensed", ...style }}>
    {children}
  </div>
);
