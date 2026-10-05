// The studio every shot is filmed in: renderer settings, image-based reflections, fog, floor, key and rim
// light, and the post chain (MSAA, bloom, tone mapping, grade with vignette and film grain).
import React, { useEffect, useMemo } from "react";
import { QA } from "./qa";
import { ThreeCanvas } from "@remotion/three";
import { useFrame, useThree } from "@react-three/fiber";
import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";
import { ShaderPass } from "three/examples/jsm/postprocessing/ShaderPass.js";
import { RectAreaLightUniformsLib } from "three/examples/jsm/lights/RectAreaLightUniformsLib.js";
import { useCurrentFrame, useVideoConfig } from "remotion";
import type { Look } from "./look";

RectAreaLightUniformsLib.init();

export type CameraPose = { pos: [number, number, number]; target: [number, number, number]; fov?: number; roll?: number };

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uFrame: { value: 0 },
    uGrain: { value: 0.04 },
    uVignette: { value: 0.4 },
    uRes: { value: new THREE.Vector2(1920, 1080) },
  },
  vertexShader: /* glsl */ `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse; uniform float uFrame; uniform float uGrain; uniform float uVignette; uniform vec2 uRes;
    varying vec2 vUv;
    float hash(vec2 p){ p = fract(p*vec2(443.897,441.423)); p += dot(p, p.yx+19.19); return fract((p.x+p.y)*p.x); }
    void main(){
      vec2 c = vUv - 0.5;
      float r = length(c);
      // one sample for all channels: lateral chromatic aberration fringed every edge with orange/blue, which
      // viewers read as outlines around objects (alignment-now v7 verdict)
      vec3 col = texture2D(tDiffuse, vUv).rgb;
      float vig = smoothstep(0.85, 0.2, r * (1.0 + uVignette));
      col *= mix(1.0 - uVignette, 1.0, vig);
      float g = hash(floor(vUv * uRes) + mod(uFrame, 97.0) * 17.0) - 0.5;
      float luma = dot(col, vec3(0.299,0.587,0.114));
      col += g * uGrain * (1.0 - luma * 0.6);
      gl_FragColor = vec4(col, 1.0);
    }`,
};

const Studio: React.FC<{ look: Look; camera: CameraPose; dof?: boolean }> = ({ look, camera }) => {
  const { gl, scene, camera: cam, size } = useThree();
  const frame = useCurrentFrame();

  // Renderer and scene setup happen during render (not in an effect) so the very first advanced frame has them.
  useMemo(() => {
    gl.toneMapping = THREE.ACESFilmicToneMapping;
    gl.toneMappingExposure = look.exposure;
    gl.shadowMap.enabled = true;
    gl.shadowMap.type = THREE.VSMShadowMap;
    scene.background = new THREE.Color(look.bg);
    scene.fog = new THREE.Fog(look.bg, look.fogNear, look.fogFar);
    const pm = new THREE.PMREMGenerator(gl);
    scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environmentIntensity = look.env;
    pm.dispose();
  }, [gl, scene, look]);

  const { composer, grade } = useMemo(() => {
    const rt = new THREE.WebGLRenderTarget(size.width, size.height, { type: THREE.HalfFloatType, samples: 4 });
    const c = new EffectComposer(gl, rt);
    c.setPixelRatio(1);
    c.setSize(size.width, size.height);
    c.addPass(new RenderPass(scene, cam));
    c.addPass(new UnrealBloomPass(new THREE.Vector2(size.width, size.height), look.bloom.strength, look.bloom.radius, look.bloom.threshold));
    c.addPass(new OutputPass());
    const g = new ShaderPass(GradeShader);
    g.uniforms.uGrain.value = QA ? 0 : look.grain; // no per-frame grain in the QA proxy
    g.uniforms.uVignette.value = look.vignette;
    g.uniforms.uRes.value.set(size.width, size.height);
    c.addPass(g);
    return { composer: c, grade: g };
  }, [gl, scene, cam, size.width, size.height, look]);
  useEffect(() => () => composer.dispose(), [composer]);

  // Camera pose for this frame.
  const pc = cam as THREE.PerspectiveCamera;
  pc.position.set(...camera.pos);
  pc.fov = camera.fov ?? 30;
  pc.near = 0.1;
  pc.far = 120;
  pc.up.set(Math.sin(camera.roll ?? 0), Math.cos(camera.roll ?? 0), 0);
  pc.lookAt(...camera.target);
  pc.updateProjectionMatrix();

  useFrame(() => {
    grade.uniforms.uFrame.value = frame;
    composer.render();
  }, 1);
  return null;
};

/** Floor that catches shadows and a soft env sheen; it fades into the fog, so the studio has no visible edge. */
export const Floor: React.FC<{ look: Look }> = ({ look }) => (
  <mesh rotation-x={-Math.PI / 2} receiveShadow>
    <planeGeometry args={[200, 200]} />
    <meshPhysicalMaterial color={look.floor.color} roughness={look.floor.roughness} metalness={look.floor.metalness} />
  </mesh>
);

/** Key (warm spot, soft shadows) and rim (cool, from behind). Positions are per shot. */
export const Lights: React.FC<{
  look: Look;
  keyPos?: [number, number, number];
  keyTarget?: [number, number, number];
  rim?: [number, number, number];
  rimTarget?: [number, number, number];
  keyScale?: number;
}> = ({ look, keyPos = [6, 9, 5], keyTarget = [0, 0, 0], rim = [-6, 5, -10], rimTarget, keyScale = 1 }) => {
  const spot = useMemo(() => {
    const s = new THREE.SpotLight(look.key.color, look.key.intensity * keyScale, 0, Math.PI / 6, 0.9, 2);
    s.castShadow = true;
    s.shadow.mapSize.set(2048, 2048);
    s.shadow.radius = 12;
    s.shadow.blurSamples = 16;
    s.shadow.bias = -0.0004;
    s.shadow.normalBias = 0.02;
    s.shadow.camera.near = 1;
    s.shadow.camera.far = 40;
    return s;
  }, [look, keyScale]);
  // Rim: a narrow spot from behind aimed at the subject, so it outlines edges without a floor glare.
  const rimSpot = useMemo(() => new THREE.SpotLight(look.rim.color, look.rim.intensity * 60, 0, 0.22, 1, 2), [look]);
  rimSpot.position.set(...rim);
  rimSpot.target.position.set(...(rimTarget ?? keyTarget));
  rimSpot.target.updateMatrixWorld();
  spot.position.set(...keyPos);
  spot.target.position.set(...keyTarget);
  spot.target.updateMatrixWorld();
  return (
    <>
      <primitive object={spot} />
      <primitive object={spot.target} />
      <primitive object={rimSpot} />
      <primitive object={rimSpot.target} />
      <hemisphereLight args={[look.key.color, look.bg, 0.08]} />
    </>
  );
};

export const Stage: React.FC<{ look: Look; camera: CameraPose; children: React.ReactNode }> = ({ look, camera, children }) => {
  const { width, height } = useVideoConfig();
  return (
    <ThreeCanvas width={width} height={height} dpr={1} gl={{ antialias: false, powerPreference: "high-performance" }} shadows>
      <Studio look={look} camera={camera} />
      {children}
    </ThreeCanvas>
  );
};
