// Image-based lighting from an HDRI asset (R35): sets the scene's environment (reflections and soft fill) and,
// optionally, its background. Lights in Stage.tsx still shape the key.
import React, { useEffect } from "react";
import { staticFile } from "remotion";
import { useLoader, useThree } from "@react-three/fiber";
import * as THREE from "three";
import { RGBELoader } from "three/examples/jsm/loaders/RGBELoader.js";
import { ASSETS } from "../../data/assets";

type Props = { asset: keyof typeof ASSETS & string; background?: boolean; intensity?: number };

export const Environment: React.FC<Props> = ({ asset, background = false, intensity = 1 }) => {
  const hdr = useLoader(RGBELoader, staticFile(ASSETS[asset].src));
  const { scene } = useThree();
  useEffect(() => {
    hdr.mapping = THREE.EquirectangularReflectionMapping;
    scene.environment = hdr;
    scene.environmentIntensity = intensity;
    if (background) scene.background = hdr;
    return () => {
      scene.environment = null;
      if (background) scene.background = null;
    };
  }, [hdr, scene, background, intensity]);
  return null;
};
