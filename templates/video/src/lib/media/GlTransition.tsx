// Shader transitions between two imported stills (photo assets or held frames), drawn on a full-frame quad with
// @remotion/three. The shaders are our own, in the style of the gl-transitions catalogue (no vendored files).
import React, { useMemo } from "react";
import { AbsoluteFill, staticFile, useVideoConfig } from "remotion";
import { ThreeCanvas } from "@remotion/three";
import { useLoader } from "@react-three/fiber";
import * as THREE from "three";
import { ASSETS } from "../../data/assets";
import { USES } from "../../data/asset-uses";
import { SourceTag } from "./SourceTag";

const VERTEX = `varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

// Each body defines vec4 transition(vec2 uv) using getFrom(uv), getTo(uv) and progress.
export const SHADERS: Record<"crosswarp" | "directionalWarp", string> = {
  crosswarp: `
    vec4 transition(vec2 p) {
      float x = progress;
      x = smoothstep(0.0, 1.0, x * 2.0 + p.x - 1.0);
      return mix(getFrom((p - 0.5) * (1.0 - x) + 0.5), getTo((p - 0.5) * x + 0.5), x);
    }`,
  directionalWarp: `
    const vec2 direction = vec2(-1.0, 1.0);
    const float smoothness = 0.5;
    vec4 transition(vec2 uv) {
      vec2 v = normalize(direction);
      v /= abs(v.x) + abs(v.y);
      float d = v.x * 0.5 + v.y * 0.5;
      float m = 1.0 - smoothstep(-smoothness, 0.0, v.x * uv.x + v.y * uv.y - (d - 0.5 + progress * (1.0 + smoothness)));
      return mix(getFrom((uv - 0.5) * (1.0 - m) + 0.5), getTo((uv - 0.5) * m + 0.5), m);
    }`,
};

const fragment = (body: string) => `
  uniform sampler2D from; uniform sampler2D to; uniform float progress; varying vec2 vUv;
  vec4 getFrom(vec2 uv) { return texture2D(from, uv); }
  vec4 getTo(vec2 uv) { return texture2D(to, uv); }
  ${body}
  void main() { gl_FragColor = transition(vUv); }`;

const Quad: React.FC<{ fromSrc: string; toSrc: string; progress: number; shader: keyof typeof SHADERS }> = ({ fromSrc, toSrc, progress, shader }) => {
  const [a, b] = useLoader(THREE.TextureLoader, [fromSrc, toSrc]);
  const material = useMemo(() => {
    // The textures stay in their stored sRGB values and the raw shader writes them back unchanged; decoding them as
    // sRGB here without re-encoding in the shader darkened every colour (smoke render, 2026-10-06).
    return new THREE.ShaderMaterial({ vertexShader: VERTEX, fragmentShader: fragment(SHADERS[shader]),
      uniforms: { from: { value: a }, to: { value: b }, progress: { value: 0 } } });
  }, [a, b, shader]);
  material.uniforms.progress.value = progress;
  return (
    <mesh material={material}>
      <planeGeometry args={[2, 2]} />
    </mesh>
  );
};

// Each still is placed through its ledger use (fromUse/toUse), so the asset gate counts it (R35).
type Props = {
  fromAsset: keyof typeof ASSETS & string;
  fromUse: string;
  toAsset: keyof typeof ASSETS & string;
  toUse: string;
  progress: number;
  shader: keyof typeof SHADERS;
};

export const GlTransition: React.FC<Props> = ({ fromAsset, fromUse, toAsset, toUse, progress, shader }) => {
  const { width, height } = useVideoConfig();
  // The source tag of whichever still dominates the frame (fair-use and capture rows carry one, R35).
  const credit = progress < 0.5 ? USES[fromAsset][fromUse].credit : USES[toAsset][toUse].credit;
  return (
    <AbsoluteFill>
      <ThreeCanvas width={width} height={height} gl={{ antialias: true }}>
        <Quad fromSrc={staticFile(ASSETS[fromAsset].src)} toSrc={staticFile(ASSETS[toAsset].src)} progress={progress} shader={shader} />
      </ThreeCanvas>
      {credit ? <SourceTag text={credit} /> : null}
    </AbsoluteFill>
  );
};
