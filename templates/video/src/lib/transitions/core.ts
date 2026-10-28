// Transition timing shared by every transition and media component: the calm in-out curve of motion.ts, from ease.ts (R17),
// a use's window in frames of its media, and the layer geometry of push and wipe.
import { softEase } from "../ease.ts";

export const transitionProgress = (frame: number, durationFrames: number): number => {
  if (frame <= 0) return 0;
  if (frame >= durationFrames) return 1;
  return softEase(frame / durationFrames);
};

export const clipWindow = (use: { mediaFrom: number; mediaTo: number }, fps: number) => {
  const startFrom = Math.round(use.mediaFrom * fps);
  const endAt = Math.round(use.mediaTo * fps);
  return { startFrom, endAt, frames: endAt - startFrom };
};

export const pushOffsets = (p: number, width: number) => ({ from: 0 - p * width, to: (1 - p) * width });

export const wipeInset = (p: number) => `inset(0 ${Math.round((1 - p) * 100)}% 0 0)`;
