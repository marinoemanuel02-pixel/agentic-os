// Shot registry: id -> component. Builders working in parallel each own one batch file and are spread in here.
import type React from "react";

export const SHOT_COMPONENTS: Record<string, React.FC> = {};
