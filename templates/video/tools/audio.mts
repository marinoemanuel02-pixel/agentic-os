// Builds the soundtrack from code (no samples, no downloads): music on the 100 BPM grid, effects from each
// shot's event list, and the voice placed on its beat. Writes three stems (48 kHz stereo, 16-bit) to
// ~/.aos/video/{{name}}/audio: music.wav, sfx.wav, vo.wav. Mixing and loudness are done by tools/mix.sh.
//   node tools/audio.mts
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { buildLines, buildShots, totalBeats } from "../src/data/plan.ts";
import { BEAT, FPS } from "../src/lib/look.ts";
import { EVENTS, type SfxEvent } from "../src/shots/events.ts";
import { MUSIC } from "../src/data/music.ts";

const SR = 48000;
const ROOT = path.join(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const OUT = path.join(os.homedir(), ".aos/video/{{name}}/audio");
const PUBLIC = path.join(os.homedir(), ".aos/video/{{name}}/app/public");
fs.mkdirSync(OUT, { recursive: true });

const vo = JSON.parse(fs.readFileSync(path.join(ROOT, "src/data/vo.json"), "utf8"));
const lines = buildLines(vo);
const shots = buildShots();
const BEATS = totalBeats(lines);
const SPB = 60 / 100; // seconds per beat
const N = Math.ceil((BEATS * SPB + 2.5) * SR); // + ring-out tail, trimmed by the mix to the picture
const beatT = (b: number) => b * SPB;

// Shot event lists (frames relative to the shot), registered in src/shots/events.ts.
const SHOT_EVENTS: Record<string, SfxEvent[]> = EVENTS;

// ---------------------------------------------------------------- tiny DSP kit
let seed = 1234567;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const noise = () => rnd() * 2 - 1;
const midi = (m: number) => 440 * Math.pow(2, (m - 69) / 12);
const blep = (t: number, dt: number) => {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
};
class Svf { // Chamberlin-style TPT state-variable filter
  ic1 = 0; ic2 = 0;
  run(x: number, fc: number, q: number) {
    const g = Math.tan((Math.PI * Math.min(fc, SR * 0.45)) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - this.ic2, v1 = a1 * this.ic1 + a2 * v3, v2 = this.ic2 + a2 * this.ic1 + a3 * v3;
    this.ic1 = 2 * v1 - this.ic1; this.ic2 = 2 * v2 - this.ic2;
    return { lp: v2, bp: v1, hp: x - k * v1 - v2 };
  }
}
type Stereo = [Float32Array, Float32Array];
const stereo = (): Stereo => [new Float32Array(N), new Float32Array(N)];
const add = (dst: Stereo, i: number, l: number, r: number) => { if (i >= 0 && i < N) { dst[0][i] += l; dst[1][i] += r; } };

class Reverb { // Schroeder/Freeverb-ish: 4 combs + 2 allpasses per channel, slightly different lengths L/R
  combs: { buf: Float32Array; i: number; f: number }[][]; aps: { buf: Float32Array; i: number }[][];
  constructor(size = 1) {
    const cl = [1557, 1617, 1491, 1422].map((x) => Math.round(x * size * SR / 44100));
    const al = [556, 441].map((x) => Math.round(x * SR / 44100));
    this.combs = [0, 23].map((s) => cl.map((l) => ({ buf: new Float32Array(l + s), i: 0, f: 0 })));
    this.aps = [0, 23].map((s) => al.map((l) => ({ buf: new Float32Array(l + s), i: 0 })));
  }
  run(x: number, ch: number, fb = 0.84, damp = 0.3) {
    let o = 0;
    for (const c of this.combs[ch]) {
      const y = c.buf[c.i]; c.f = y * (1 - damp) + c.f * damp; c.buf[c.i] = x + c.f * fb; c.i = (c.i + 1) % c.buf.length; o += y;
    }
    for (const a of this.aps[ch]) { const b = a.buf[a.i]; const y = -o + b; a.buf[a.i] = o + b * 0.5; a.i = (a.i + 1) % a.buf.length; o = y; }
    return o * 0.25;
  }
}

// ---------------------------------------------------------------- music
// Sections in beats and the chord loop come from src/data/music.ts (edit them per video).
const SEC = MUSIC.sections;
const inSec = (b: number, a: number, z: number) => b >= a && b < z;
const CHORDS = MUSIC.chords;
const chordAt = (b: number) => CHORDS[Math.floor(b / 8) % 4];

const music = (): Stereo => {
  const m = stereo();
  const rev = new Reverb(1.1);
  const padF = [new Svf(), new Svf()];
  const phases = new Float64Array(64);
  const delayL = new Float32Array(SR * 2), delayR = new Float32Array(SR * 2);
  const dly = Math.round(SPB * 0.75 * SR); // dotted-eighth echo
  for (let i = 0; i < N; i++) {
    const t = i / SR, b = t / SPB;
    const bar = b % 4, beatFrac = b % 1;
    // pad: 3 detuned saws per chord tone + root an octave down; crossfade chords over half a beat
    const ch = chordAt(b), prev = chordAt(Math.max(0, b - 8));
    const into = Math.min(1, (b % 8) / 0.5);
    let pl = 0, pr = 0, k = 0;
    const voices = (notes: number[], w: number) => {
      for (const n of [...notes, notes[0] - 12]) for (const d of [-0.07, 0, 0.07]) {
        const f = midi(n + d), dt = f / SR;
        phases[k] = (phases[k] + dt) % 1;
        const s = (2 * phases[k] - 1 - blep(phases[k], dt)) * w;
        if (d <= 0) pl += s; if (d >= 0) pr += s; k++;
      }
    };
    voices(prev, 1 - into); voices(ch, into);
    // filter brightness by section; swell in the close; dark in the rivals section
    const bright = b < SEC.pulse ? 380 + 220 * (b / SEC.pulse)
      : b < SEC.build ? 750 : b < SEC.peak ? 1100 : b < SEC.sparse ? 1700 : b < SEC.lift ? 650 : b < SEC.end ? 900 + 1400 * ((b - SEC.lift) / 11) : 500;
    const lfo = 1 + 0.12 * Math.sin(t * 0.7);
    let padGain = b < 2 ? b / 2 : 1;
    if (b >= SEC.end) padGain = Math.max(0, 1 - (b - SEC.end) / 4);
    const L = padF[0].run(pl, bright * lfo, 0.9).lp * 0.045 * padGain;
    const R = padF[1].run(pr, bright * lfo, 0.9).lp * 0.045 * padGain;
    let outL = L, outR = R;
    const root = midi(ch[0] - 24);
    // sub pulse on eighths (from 'agree'), ducked like a sidechain
    if (b >= SEC.pulse && b < SEC.end) {
      const e = (b * 2) % 1;
      const env = Math.exp(-e * 5) * (b < SEC.build ? 0.5 : 0.8);
      const s = Math.sin(2 * Math.PI * root * t) * env * 0.16;
      outL += s; outR += s;
    }
    // kick on beats 1 and 3 in accel, fuel and engines
    if ((inSec(b, SEC.drive, SEC.sparse) || inSec(b, SEC.lift + 4, SEC.end)) && Math.floor(bar) % 2 === 0) {
      const kt = beatFrac * SPB;
      const f = 42 + 110 * Math.exp(-kt * 28);
      const s = Math.sin(2 * Math.PI * f * kt) * Math.exp(-kt * 7) * 0.32 + (kt < 0.004 ? noise() * 0.05 : 0);
      outL += s; outR += s;
    }
    // hats on the off-eighth
    if (inSec(b, SEC.pulse, SEC.end) && !inSec(b, SEC.build - 1, SEC.build)) {
      const e = ((b + 0.5) * 2) % 2; // 0 at the off-eighth
      if (e < 1) { const ht = e * SPB / 2; const s = noise() * Math.exp(-ht * 90) * 0.035; outL += s * 0.8; outR += s; }
    }
    // arp in 'engines': sixteenths over chord tones, two octaves up, with echoes
    let arp = 0;
    if (inSec(b, SEC.peak, SEC.sparse)) {
      const step = Math.floor(b * 4), at = (b * 4 - step) * SPB / 4;
      const n = ch[[0, 1, 2, 1][step % 4]] + 12 + (step % 8 >= 4 ? 12 : 0);
      arp = Math.sin(2 * Math.PI * midi(n) * at) * Math.exp(-at * 22) * 0.07;
    }
    const di = i % delayL.length, dj = (i - dly + delayL.length) % delayL.length;
    const echoL = delayR[dj] * 0.45, echoR = delayL[dj] * 0.45;
    delayL[di] = arp + echoL; delayR[di] = echoR;
    outL += arp + echoL * 0.6; outR += arp * 0.7 + echoR * 0.8;
    // reverb send
    outL += rev.run(L * 1.5 + arp, 0) * 0.9; outR += rev.run(R * 1.5 + arp, 1) * 0.9;
    m[0][i] = outL; m[1][i] = outR;
  }
  // the last hit at 'end'
  hit(m, beatT(SEC.end), 1);
  return m;
};

// ---------------------------------------------------------------- effects
function impact(o: Stereo, t0: number, gain = 1, pitch = 1) {
  const i0 = Math.round(t0 * SR), bp = new Svf(), pan = (rnd() - 0.5) * 0.3;
  for (let j = 0; j < SR * 0.5; j++) {
    const t = j / SR;
    const f = (58 + 50 * Math.exp(-t * 40)) * pitch;
    const thump = Math.sin(2 * Math.PI * f * t) * Math.exp(-t * 16);
    const click = bp.run(noise(), 2600 * pitch, 2.5).bp * Math.exp(-t * 120);
    const tock = Math.sin(2 * Math.PI * 880 * pitch * t) * Math.exp(-t * 55) * 0.25;
    const s = (thump * 0.55 + click * 0.7 + tock) * gain * 0.5;
    add(o, i0 + j, s * (1 - pan), s * (1 + pan));
  }
}
function hit(o: Stereo, t0: number, gain = 1) {
  const i0 = Math.round(t0 * SR), lp = new Svf(), rev = new Reverb(1.4);
  for (let j = 0; j < SR * 3; j++) {
    const t = j / SR;
    const f = 40 + 90 * Math.exp(-t * 20);
    const body = Math.sin(2 * Math.PI * f * t) * Math.exp(-t * 3.5);
    const air = lp.run(noise(), 1800, 0.7).lp * Math.exp(-t * 6) * 0.6;
    const s = (body + air) * 0.45 * gain;
    add(o, i0 + j, s + rev.run(air * 0.4, 0), s + rev.run(air * 0.4, 1));
  }
}
function tick(o: Stereo, t0: number, gain = 1) {
  const i0 = Math.round(t0 * SR), bp = new Svf();
  for (let j = 0; j < SR * 0.05; j++) { const t = j / SR; const s = bp.run(noise(), 5200, 4).bp * Math.exp(-t * 160) * gain * 0.6; add(o, i0 + j, s, s); }
}
function whoosh(o: Stereo, t0: number, dur = 0.6, gain = 1, up = true) {
  const i0 = Math.round(t0 * SR), f1 = new Svf(), f2 = new Svf();
  const n = Math.round(dur * SR);
  for (let j = 0; j < n; j++) {
    const x = j / n, env = Math.sin(Math.PI * Math.pow(x, up ? 1.6 : 0.6)) ** 2;
    const fc = up ? 300 + 3500 * x * x : 3800 - 3400 * x;
    const s = noise();
    add(o, i0 + j, f1.run(s, fc, 1.4).bp * env * gain * 0.35, f2.run(noise(), fc * 1.08, 1.4).bp * env * gain * 0.35);
  }
}
function glass(o: Stereo, t0: number, gain = 1) {
  const i0 = Math.round(t0 * SR);
  const partials = [[2093, 1], [3371, 0.6], [5210, 0.35], [7020, 0.2]];
  for (let j = 0; j < SR * 2; j++) {
    const t = j / SR; let s = 0;
    for (const [f, a] of partials) s += Math.sin(2 * Math.PI * f * t) * a * Math.exp(-t * (1.4 + f / 4000));
    s *= gain * 0.08; add(o, i0 + j, s, s * 0.9);
  }
}
const SFX: Record<string, (o: Stereo, t: number, g?: number, p?: number) => void> = { impact, hit, tick, whoosh, glass };

const sfx = (): Stereo => {
  const o = stereo();
  for (const s of shots) {
    for (const e of SHOT_EVENTS[s.id] ?? []) {
      const fn = SFX[e.kind];
      if (!fn) throw new Error(`unknown sfx kind ${e.kind} in ${s.id}`);
      fn(o, (s.from + e.frame) / FPS, e.gain ?? 1, e.pitch ?? 1);
    }
  }
  return o;
};

// ---------------------------------------------------------------- voice
const readWav = (file: string) => {
  const b = fs.readFileSync(file);
  let p = 12, fmt: { ch: number; sr: number; bits: number; f: number } | null = null, data: Buffer | null = null;
  while (p < b.length) {
    const id = b.toString("ascii", p, p + 4), size = b.readUInt32LE(p + 4);
    if (id === "fmt ") fmt = { f: b.readUInt16LE(p + 8), ch: b.readUInt16LE(p + 10), sr: b.readUInt32LE(p + 12), bits: b.readUInt16LE(p + 22) };
    if (id === "data") data = b.subarray(p + 8, p + 8 + size);
    p += 8 + size + (size % 2);
  }
  if (!fmt || !data) throw new Error(`bad wav ${file}`);
  const n = data.length / (fmt.bits / 8) / fmt.ch, x = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const o = i * fmt.ch * (fmt.bits / 8);
    x[i] = fmt.f === 3 ? data.readFloatLE(o) : data.readInt16LE(o) / 32768;
  }
  return { x, sr: fmt.sr };
};
const voice = (): Stereo => {
  const o = stereo();
  for (const l of lines) {
    const { x, sr } = readWav(path.join(PUBLIC, l.file));
    const t0 = l.from / FPS + 0.05;
    for (let j = 0; j < (x.length * SR) / sr; j++) {
      const pos = (j * sr) / SR, k = Math.floor(pos), fr = pos - k;
      const s = (x[k] ?? 0) * (1 - fr) + (x[k + 1] ?? 0) * fr; // linear resample to 48 kHz
      add(o, Math.round(t0 * SR) + j, s, s);
    }
  }
  return o;
};

// ---------------------------------------------------------------- write
const writeWav = (file: string, s: Stereo) => {
  const n = s[0].length, b = Buffer.alloc(44 + n * 4);
  b.write("RIFF", 0); b.writeUInt32LE(36 + n * 4, 4); b.write("WAVEfmt ", 8); b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20); b.writeUInt16LE(2, 22); b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 4, 28);
  b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34); b.write("data", 36); b.writeUInt32LE(n * 4, 40);
  let peak = 0;
  for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(s[0][i]), Math.abs(s[1][i]));
  const g = peak > 0.98 ? 0.98 / peak : 1;
  for (let i = 0; i < n; i++) {
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s[0][i] * g)) * 32767), 44 + i * 4);
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s[1][i] * g)) * 32767), 46 + i * 4);
  }
  fs.writeFileSync(file, b);
  console.log(`${path.basename(file)}: ${(n / SR).toFixed(2)} s, peak ${peak.toFixed(2)}${g < 1 ? " (normalised)" : ""}`);
};

const t0 = Date.now();
writeWav(path.join(OUT, "music.wav"), music());
writeWav(path.join(OUT, "sfx.wav"), sfx());
writeWav(path.join(OUT, "vo.wav"), voice());
fs.writeFileSync(path.join(OUT, "plan.json"), JSON.stringify({ beats: BEATS, seconds: BEATS * SPB, frames: BEATS * BEAT, lines, shots }, null, 2));
console.log(`done in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
