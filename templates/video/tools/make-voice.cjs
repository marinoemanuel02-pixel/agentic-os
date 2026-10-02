// Voice-over with the local Kokoro v1.0 model (sherpa-onnx, CPU), one WAV per line.
// Usage: node tools/make-voice.cjs [sid] [speed] [only-id]   (sid 3 = af_heart; ids in the model's speaker_names)  -> ~/.aos/video/{{name}}/app/public/vo/<id>.wav
// and src/data/vo.json (id, file, seconds).
const fs = require("fs");
const path = require("path");
const home = process.env.USERPROFILE;
const sherpa = require(path.join(home, ".npm-global/node_modules/@getpaseo/cli/node_modules/sherpa-onnx-node"));
const m = path.join(home, ".aos/models/kokoro-multi-lang-v1_0");
const tts = new sherpa.OfflineTts({
  model: {
    kokoro: { model: path.join(m, "model.onnx"), voices: path.join(m, "voices.bin"), tokens: path.join(m, "tokens.txt"), dataDir: path.join(m, "espeak-ng-data"),
      dictDir: path.join(m, "dict"), lexicon: [path.join(m, "lexicon-us-en.txt"), path.join(m, "lexicon-zh.txt")].join(","), lang: "en-us" },
    numThreads: 4, provider: "cpu", debug: false,
  },
  maxNumSentences: 1,
});
const sid = Number(process.argv[2] ?? 3);
const speed = Number(process.argv[3] ?? 1.0);
const outDir = process.env.VO_OUT;
const only = process.argv[4];
const root = path.join(__dirname, "..");
const out = outDir || path.join(home, ".aos/video/{{name}}/app/public/vo");
fs.mkdirSync(out, { recursive: true });
const lines = JSON.parse(fs.readFileSync(path.join(root, "src/data/lines.json"), "utf8"));
const voPath = path.join(root, "src/data/vo.json");
const prev = fs.existsSync(voPath) ? JSON.parse(fs.readFileSync(voPath, "utf8")) : [];
const result = [];
for (const l of lines) {
  if (only && l.id !== only) { const p = prev.find((x) => x.id === l.id); if (p) result.push(p); continue; }
  const a = tts.generate({ text: l.text, sid, speed });
  const file = `vo/${l.id}.wav`;
  sherpa.writeWave(path.join(out, `${l.id}.wav`), { samples: a.samples, sampleRate: a.sampleRate });
  const seconds = Math.round((a.samples.length / a.sampleRate) * 1000) / 1000;
  result.push({ id: l.id, file, seconds, sid, speed });
  console.log(`${l.id}: ${seconds.toFixed(2)} s`);
}
fs.writeFileSync(voPath, JSON.stringify(result, null, 2) + "\n");
console.log(`total ${result.reduce((s, x) => s + x.seconds, 0).toFixed(1)} s`);
