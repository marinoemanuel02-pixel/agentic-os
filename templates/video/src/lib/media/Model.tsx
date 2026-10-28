// A scanned or authored 3D model by asset id (R35), for props at real scale inside the template's Stage (answers
// "miniatures" and "not recognisable object" from the v9 verdict). Models must be self-contained .glb files.
import React from "react";
import { staticFile } from "remotion";
import { useLoader } from "@react-three/fiber";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { ASSETS } from "../../data/assets";

type Props = {
  asset: keyof typeof ASSETS & string;
  position?: [number, number, number];
  rotation?: [number, number, number];
  scale?: number;
};

export const Model: React.FC<Props> = ({ asset, position = [0, 0, 0], rotation = [0, 0, 0], scale = 1 }) => {
  const gltf = useLoader(GLTFLoader, staticFile(ASSETS[asset].src));
  return <primitive object={gltf.scene.clone(true)} position={position} rotation={rotation} scale={scale} />;
};
