// Pure easing maths (no imports), shared by motion.ts and code that Node tests import directly. SOFT_POINTS are the
// control points of the template's calm in-out curve (R17); cubicBezier solves a CSS-style curve for a progress t.
export const SOFT_POINTS = [0.45, 0, 0.55, 1] as const;

export const cubicBezier = (x1: number, y1: number, x2: number, y2: number) => {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sampleX = (t: number) => ((ax * t + bx) * t + cx) * t;
  const sampleY = (t: number) => ((ay * t + by) * t + cy) * t;
  const slopeX = (t: number) => (3 * ax * t + 2 * bx) * t + cx;
  return (x: number): number => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let t = x;
    for (let i = 0; i < 8; i++) {
      const err = sampleX(t) - x;
      if (Math.abs(err) < 1e-7) break;
      const d = slopeX(t);
      if (Math.abs(d) < 1e-7) break;
      t -= err / d;
    }
    return sampleY(Math.min(1, Math.max(0, t)));
  };
};

export const softEase = cubicBezier(...SOFT_POINTS);
