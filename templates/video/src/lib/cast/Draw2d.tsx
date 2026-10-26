// The two drawing primitives the cast is built from (from pauseai-it's 2D kit): a cel-shaded shape and a contact shadow.
import React, { useId } from "react";
import { polar } from "./geom";

/**
 * A cel-shaded shape: a hard shadow (the base shifted toward the light leaves shadow on the far side), a rim of
 * light on the lit edge, an optional outline in `ink`.
 * light = direction the light comes FROM, in degrees (225 = top-left).
 */
export const Cel: React.FC<{
  d: string;
  base: string;
  shade: string;
  light?: number;
  shadeDepth?: number;
  rim?: string;
  rimW?: number;
  ink?: string;
  line?: number;
  opacity?: number;
  children?: React.ReactNode;
}> = ({ d, base, shade, light = 225, shadeDepth = 14, rim, rimW = 4, ink = "#3b2c3f", line = 0, opacity, children }) => {
  const uid = useId().replace(/[^a-zA-Z0-9]/g, "");
  const clip = `c${uid}`;
  const mask = `m${uid}`;
  // the base moves toward the light, so the uncovered far side shows the shadow tone
  const [lx, ly] = polar(0, 0, shadeDepth, light);
  // the rim is the band of the shape whose neighbour toward the light lies outside it
  const [rx, ry] = polar(0, 0, rimW, light + 180);
  return (
    <g opacity={opacity}>
      <defs>
        <clipPath id={clip}>
          <path d={d} />
        </clipPath>
        {rim ? (
          <mask id={mask} maskUnits="userSpaceOnUse" x={-4000} y={-4000} width={8000} height={8000}>
            <path d={d} fill="#fff" />
            <path d={d} fill="#000" transform={`translate(${rx} ${ry})`} />
          </mask>
        ) : null}
      </defs>
      <path d={d} fill={shade} />
      <g clipPath={`url(#${clip})`}>
        <path d={d} fill={base} transform={`translate(${lx} ${ly})`} />
        {children}
      </g>
      {rim ? <path d={d} fill={rim} mask={`url(#${mask})`} opacity={0.9} /> : null}
      {line > 0 ? <path d={d} fill="none" stroke={ink} strokeWidth={line} strokeLinejoin="round" strokeLinecap="round" /> : null}
    </g>
  );
};

/** A soft contact shadow on the ground under something. */
export const Contact: React.FC<{ x: number; y: number; rx: number; ry?: number; opacity?: number; color?: string }> = ({
  x,
  y,
  rx,
  ry = rx * 0.22,
  opacity = 0.4,
  color = "#070917",
}) => {
  const g = `g${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  return (
    <g>
      <defs>
        <radialGradient id={g}>
          <stop offset="0%" stopColor={color} stopOpacity={opacity} />
          <stop offset="100%" stopColor={color} stopOpacity={0} />
        </radialGradient>
      </defs>
      <ellipse cx={x} cy={y} rx={rx} ry={ry} fill={`url(#${g})`} />
    </g>
  );
};
