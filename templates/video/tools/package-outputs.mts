// Writes the upload package text files to exports/: {{name}}.srt (script text, timed to the voice slots),
// chapters.txt (YouTube chapters) and description.md (sources). node --no-warnings tools/package-outputs.mts
import fs from "node:fs";
import path from "node:path";
import { buildLines, buildShots, CHAPTERS, totalBeats } from "../src/data/plan.ts";
import { FPS } from "../src/lib/look.ts";

const root = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const read = (f: string) => JSON.parse(fs.readFileSync(path.join(root, f), "utf8"));
const vo = read("src/data/vo.json");
const text: { id: string; caption: string }[] = read("src/data/lines.json");
const lines = buildLines(vo);
const shots = buildShots();
const end = (totalBeats(lines) * 18) / FPS;
fs.mkdirSync(path.join(root, "exports"), { recursive: true });

// Captions: split each line at sentence ends (then commas) into cues of at most 84 characters (2 x 42), timed
// in proportion to their length inside the measured voice clip (Kokoro reads at an even rate).
const ts = (s: number) => {
  const ms = Math.round(s * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, sec = Math.floor(ms / 1000) % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")},${String(ms % 1000).padStart(3, "0")}`;
};
const wrap = (s: string) => {
  if (s.length <= 42) return s;
  // Break at the space that keeps both lines within 42 characters, preferring one right after punctuation
  // (so names and phrases stay together), then the one closest to the middle.
  const spaces = [...s.matchAll(/ /g)].map((m) => m.index!);
  const fits = spaces.filter((i) => i <= 42 && s.length - i - 1 <= 42);
  const pool = fits.length ? fits : spaces;
  const score = (i: number) => Math.abs(i - s.length / 2) - (/[.,:;]/.test(s[i - 1]) ? 12 : 0);
  const cut = pool.sort((a, b) => score(a) - score(b))[0];
  return s.slice(0, cut) + "\n" + s.slice(cut + 1);
};
const split = (s: string): string[] => {
  if (s.length <= 84) return [s];
  const parts = s.match(/[^.!?]+[.!?]+[”"]?\s*/g) ?? [s];
  if (parts.length > 1) return parts.flatMap((p) => split(p.trim()));
  const i = s.lastIndexOf(", ", Math.ceil(s.length / 2) + 10);
  if (i > 10) return [...split(s.slice(0, i + 1)), ...split(s.slice(i + 2))];
  const j = s.lastIndexOf(" ", Math.ceil(s.length / 2));
  return [...split(s.slice(0, j)), ...split(s.slice(j + 1))];
};
let n = 0;
const cues: string[] = [];
for (const l of lines) {
  const cap = text.find((t) => t.id === l.id)!.caption;
  const parts = split(cap);
  const total = parts.reduce((a, p) => a + p.length, 0);
  const lead = 0.05 + 0.12; // the voice is placed 0.05 s into its slot; Kokoro adds ~0.1 s of silence
  let t = l.from / FPS + lead;
  const dur = l.seconds - 0.25;
  for (const p of parts) {
    const d = (dur * p.length) / total;
    cues.push(`${++n}\n${ts(t)} --> ${ts(Math.min(t + d, end - 0.05))}\n${wrap(p)}\n`);
    t += d;
  }
}
fs.writeFileSync(path.join(root, "exports", "{{name}}.srt"), cues.join("\n"));

// Chapters: YouTube needs the first at 0:00, at least three, each at least 10 s long.
const at = (id: string) => shots.find((s) => s.id === id)!.from / FPS;
const chapters: [number, string][] = CHAPTERS.map(([id, name]) => [at(id), name]);
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
chapters.forEach(([t], i) => {
  const next = i + 1 < chapters.length ? chapters[i + 1][0] : end;
  if (next - t < 10) throw new Error(`chapter ${i} is shorter than 10 s`);
});
fs.writeFileSync(path.join(root, "exports", "chapters.txt"), chapters.map(([t, name]) => `${mmss(t)} ${name}`).join("\n") + "\n");
console.log(`srt: ${n} cues, last ends before ${end.toFixed(2)} s; chapters: ${chapters.length}`);
