// The look: palettes, type and timing shared by every shot. One place to change the style lock.
export const FPS = 30;
export const BPM = 100;
export const BEAT = Math.round((60 / BPM) * FPS); // 18 frames: cuts land on multiples of this

export type Look = {
  name: string;
  bg: string; // studio background and fog colour
  fogNear: number;
  fogFar: number;
  floor: { color: string; roughness: number; metalness: number };
  block: "obsidian" | "ceramic" | "aluminium";
  accent: string; // the line of light and the protagonist block
  accentGain: number; // HDR multiplier on the line: how hard it blooms
  key: { color: string; intensity: number };
  rim: { color: string; intensity: number };
  env: number; // environment (reflection) intensity
  exposure: number;
  bloom: { strength: number; radius: number; threshold: number };
  ink: string; // type colour
  inkSoft: string; // secondary type colour
  grain: number;
  vignette: number;
};

// One example look (the dark studio of agi-race-2). Replace or add looks per video; shots read them from here.
export const LOOKS: Record<string, Look> = {
  studio: {
    name: "Studio",
    bg: "#09090a",
    fogNear: 9,
    fogFar: 34,
    floor: { color: "#0d0d0e", roughness: 0.42, metalness: 0 },
    block: "obsidian",
    accent: "#ff7a1f",
    accentGain: 9,
    key: { color: "#ffd8b0", intensity: 260 },
    rim: { color: "#9cb8ff", intensity: 2.5 },
    env: 0.6,
    exposure: 1.0,
    bloom: { strength: 0.55, radius: 0.55, threshold: 0.95 },
    ink: "#ede7db",
    inkSoft: "#8d877c",
    grain: 0.045,
    vignette: 0.42,
  },
};

export const SERIF = '"Sitka Display", "Sitka Heading", Georgia, serif';
export const SANS = 'Bahnschrift, "Segoe UI", sans-serif';

// The film grade as a CSS filter for imported 2D material (clips, photos, captures), so stock sits inside the look:
// contrast follows the vignette's weight, exposure the look's exposure; saturation is held down a little.
export const gradeFilter = (look: Look): string => {
  const contrast = (1 + look.vignette * 0.25).toFixed(3);
  const saturate = (0.86 - look.grain).toFixed(3);
  const brightness = (0.92 * look.exposure).toFixed(3);
  return `contrast(${contrast}) saturate(${saturate}) brightness(${brightness})`;
};
