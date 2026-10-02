// The master timeline for the Remotion code: line slots from the measured voice lengths, then shots.
import vo from "./vo.json";
import { BEAT } from "../lib/look";
import { buildLines, buildShots, totalBeats, type LineSlot, type ShotSlot } from "./plan";

export const LINES: LineSlot[] = buildLines(vo);
export const SHOTS: ShotSlot[] = buildShots();
export const TOTAL_BEATS = totalBeats(LINES);
export const TOTAL_FRAMES = TOTAL_BEATS * BEAT;

const find = <T extends { id: string }>(xs: T[], id: string) => {
  const x = xs.find((v) => v.id === id);
  if (!x) throw new Error(`unknown id ${id}`);
  return x;
};
export const line = (id: string) => find(LINES, id);
export const shot = (id: string) => find(SHOTS, id);
