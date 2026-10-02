// Type that lives in the 3D scene: a camera-facing plane with text drawn on a canvas texture, so it sits in
// depth, takes fog and parallax, and is occluded like the objects it labels.
import React, { useMemo } from "react";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";

export const Tag: React.FC<{
  text: string;
  position: [number, number, number];
  color: string;
  height?: number; // world units of the text cap height
  font?: string; // CSS font without size
  opacity?: number;
}> = ({ text, position, color, height = 0.28, font = '600 {px}px Bahnschrift', opacity = 1 }) => {
  const ready = typeof document !== "undefined" && document.fonts.check(font.replace("{px}", "64"));
  const { tex, aspect } = useMemo(() => {
    const px = 160;
    const c = document.createElement("canvas");
    const ctx = c.getContext("2d")!;
    ctx.font = font.replace("{px}", String(px));
    const w = Math.ceil(ctx.measureText(text).width) + 40;
    c.width = w;
    c.height = Math.ceil(px * 1.3);
    ctx.font = font.replace("{px}", String(px));
    ctx.fillStyle = color;
    ctx.textBaseline = "middle";
    ctx.fillText(text, 20, c.height / 2);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return { tex: t, aspect: c.width / c.height };
  }, [text, color, font, ready]);
  const ref = React.useRef<THREE.Mesh>(null);
  useFrame(({ camera }) => {
    if (ref.current) ref.current.quaternion.copy(camera.quaternion);
  }, 0);
  const h = height * 1.3;
  return (
    <mesh ref={ref} position={position}>
      <planeGeometry args={[h * aspect, h]} />
      <meshBasicMaterial map={tex} transparent opacity={opacity} depthWrite={false} toneMapped={false} />
    </mesh>
  );
};
