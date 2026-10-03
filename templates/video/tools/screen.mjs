// Local-model text check: sends each shot's mid frame to the local Ollama model (aos-agent reads images) and asks
// only for the text it can read, to compare with script.md. Its "slop" judgements were noise in agi-race-2 (24 of
// 27 frames flagged while its own notes called them clean), so it is not asked for them. Writes qa/screen.md.
//   node tools/screen.mjs   (after tools/qa.sh has written ~/.aos/video/{{name}}/qa/shots/*.png)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";
import { execFileSync } from "node:child_process";

const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const media = process.env.AOS_VIDEO_MEDIA_ROOT || path.join(os.homedir(), ".aos", "video", "{{name}}");
const dir = path.join(media, "qa", "shots");
const model = process.env.SCREEN_MODEL || "aos-agent";
const prompt = `Read all the text visible in this video frame, exactly as written, line by line. Answer ONLY with JSON: {"text_on_screen": "<the text, lines joined with ' / ', or empty>", "garbled_text": true|false}`;

const rows = [];
const scratch = path.join(media, "tmp", "screen");
fs.mkdirSync(scratch, {recursive: true});
for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".png")).sort()) {
  const small = path.join(scratch, `screen-${f.replace(".png", ".jpg")}`);
  execFileSync("magick", [path.join(dir, f), "-resize", "896x504", "-quality", "85", small]);
  const img = fs.readFileSync(small).toString("base64");
  const t0 = Date.now();
  const res = await fetch("http://127.0.0.1:11434/api/chat", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ model, stream: false, format: "json", think: false, options: { temperature: 0 }, messages: [{ role: "user", content: prompt, images: [img] }] }),
  });
  const j = await res.json();
  let r;
  try { r = JSON.parse(j.message?.content ?? "{}"); } catch { r = { text_on_screen: `unparsed: ${(j.message?.content ?? j.error ?? "").slice(0, 120)}` }; }
  const flags = ["garbled_text"].filter((k) => r[k] === true);
  rows.push(`| ${f.replace(".png", "")} | ${flags.join(", ") || "-"} | ${(r.text_on_screen ?? "").toString().replace(/\|/g, "/").slice(0, 160)} | ${((Date.now() - t0) / 1000).toFixed(1)} s |`);
  console.log(rows[rows.length - 1]);
}
const out = `# Local-model frame screen (${model}: compare with script.md)\n\n| Shot | Flags | Text it read | Time |\n|---|---|---|---|\n${rows.join("\n")}\n`;
fs.writeFileSync(path.join(here, "qa", "screen.md"), out);
