// A stand-in for yt-dlp in tests: writes a growing "<dest>.part" (50 KB every 30 ms) and, by FAKE_YTDLP_MODE,
// fails after FAKE_YTDLP_BYTES ("fail"), keeps growing until killed ("grow"), or finishes into <dest> ("ok").
import {appendFileSync, renameSync} from 'node:fs';

const args = process.argv.slice(2);
const dest = args[args.indexOf('-o') + 1];
const mode = process.env.FAKE_YTDLP_MODE || 'ok';
const limit = Number(process.env.FAKE_YTDLP_BYTES || 200000);
const chunk = Buffer.alloc(50000, 7);
let written = 0;
const timer = setInterval(() => {
  appendFileSync(`${dest}.part`, chunk);
  written += chunk.length;
  if (mode !== 'grow' && written >= limit) {
    clearInterval(timer);
    if (mode === 'ok') { renameSync(`${dest}.part`, dest); process.exit(0); }
    process.stderr.write('ERROR: fragment 3 not found\n');
    process.exit(1);
  }
}, 30);
