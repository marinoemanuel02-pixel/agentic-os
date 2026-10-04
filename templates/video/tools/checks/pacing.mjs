// Measure edit rhythm, visible change, words, and loudness for reviewer judgment.
// Thresholds are descriptive; this report never gates QA on a pacing target.
import {spawn, spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {basename, dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const WIDTH = 160;
const HEIGHT = 90;
const FRAME_BYTES = WIDTH * HEIGHT;
const SCENE_THRESHOLD = 0.3;
const HOLD_THRESHOLD = 0.6;
const AUDIO_DIP_LU = 6;
const AUDIO_MEDIAN_SECONDS = 10;
const STOPWORDS = new Set('a an and are as at be by for from has have in into is it its of on or our that the their this to was we were what when where which who why will with you your'.split(' '));

function command(name, args) {
  const result = spawnSync(name, args, {encoding:'utf8', maxBuffer:32 * 1024 * 1024});
  if (result.error || result.status !== 0) throw new Error(`${name} failed: ${result.error?.message ?? result.stderr?.slice(-800)}`);
  return result.stdout + result.stderr;
}

function probe(film) {
  const result = JSON.parse(command('ffprobe', ['-v','error','-show_entries','format=duration:stream=avg_frame_rate','-select_streams','v:0','-of','json',film]));
  const [numerator, denominator] = result.streams[0].avg_frame_rate.split('/').map(Number);
  return {duration:Number(result.format.duration), fps:numerator / denominator};
}

function cuts(film, duration) {
  const output = command('ffmpeg', ['-hide_banner','-nostats','-i',film,'-vf',`select='gt(scene,${SCENE_THRESHOLD})',showinfo`,'-an','-f','null','-']);
  const times = [...output.matchAll(/pts_time:([\d.]+)/g)].map(match => Number(match[1]));
  return {threshold:SCENE_THRESHOLD, count:times.length, timesSeconds:times,
    perMinute:times.length * 60 / duration, shotsPerMinute:(times.length + 1) * 60 / duration};
}

function visual(film, fps, duration) {
  return new Promise((resolveResult, reject) => {
    const child = spawn('ffmpeg', ['-v','error','-i',film,'-an','-vf',`scale=${WIDTH}:${HEIGHT},format=gray`,'-f','rawvideo','-pix_fmt','gray','-']);
    let pending = Buffer.alloc(0);
    let previous = null;
    let frame = 0;
    let holdFrames = 0;
    let longestFrames = 0;
    let longestEndFrame = 0;
    const changedSeconds = new Set();
    let stderr = '';
    child.stderr.on('data', chunk => stderr += chunk);
    child.stdout.on('data', chunk => {
      pending = Buffer.concat([pending, chunk]);
      while (pending.length >= FRAME_BYTES) {
        const current = pending.subarray(0, FRAME_BYTES);
        pending = pending.subarray(FRAME_BYTES);
        if (previous) {
          let sum = 0;
          for (let i = 0; i < FRAME_BYTES; i++) sum += Math.abs(current[i] - previous[i]);
          const difference = sum / FRAME_BYTES;
          if (difference < HOLD_THRESHOLD) holdFrames++;
          else {
            changedSeconds.add(Math.floor(frame / fps));
            if (holdFrames > longestFrames) { longestFrames = holdFrames; longestEndFrame = frame; }
            holdFrames = 0;
          }
        }
        previous = Buffer.from(current);
        frame++;
      }
    });
    child.on('error', reject);
    child.on('close', code => {
      if (code !== 0) return reject(new Error(`ffmpeg visual decode failed: ${stderr.slice(-800)}`));
      if (holdFrames > longestFrames) { longestFrames = holdFrames; longestEndFrame = frame; }
      const start = Math.max(0, (longestEndFrame - longestFrames - 1) / fps);
      resolveResult({width:WIDTH, height:HEIGHT, holdThresholdGrayLevels:HOLD_THRESHOLD,
        longestHoldSeconds:longestFrames / fps, longestHoldFromSeconds:start,
        longestHoldToSeconds:(longestEndFrame - 1) / fps,
        secondsWithChange:changedSeconds.size, shareSecondsWithChange:changedSeconds.size / Math.ceil(duration)});
    });
  });
}

function practices(shots) {
  if (!shots) return null;
  const names = shots.map(shot => shot.practice);
  const firstHook = shots.find(shot => shot.hook === true);
  return {changes:names.slice(1).filter((name, i) => name !== names[i]).length,
    distinct:new Set(names).size, firstHookSeconds:firstHook?.from ?? null};
}

function tokens(text) {
  return String(text).toLowerCase().match(/[a-z0-9]+/g)?.filter(word => !STOPWORDS.has(word)) ?? [];
}

function words(claims, lines) {
  if (!claims || !lines) return null;
  const narration = new Set((Array.isArray(lines) ? lines : lines.lines ?? []).flatMap(line => tokens(line.text)));
  const screen = (claims.screen ?? []).flatMap(entry => (entry.texts ?? (entry.text ? [entry.text] : [])).flatMap(tokens));
  const novel = screen.filter(word => !narration.has(word));
  return {screenWords:screen.length, novelWords:novel.length, novelShare:screen.length ? novel.length / screen.length : null};
}

function median(values) {
  const sorted = [...values].sort((a,b) => a-b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle-1] + sorted[middle]) / 2;
}

function audio(film, duration) {
  const output = command('ffmpeg', ['-hide_banner','-nostats','-loglevel','verbose','-i',film,'-vn','-af','ebur128=framelog=verbose','-f','null','-']);
  const samples = new Map();
  for (const match of output.matchAll(/t:\s*([\d.]+)\s+TARGET:[^\r\n]*?M:\s*(-?[\d.]+)/g)) {
    const time = Number(match[1]);
    const second = Math.floor(time);
    samples.set(second, {second, momentaryLUFS:Number(match[2])});
  }
  const curve = Array.from({length:Math.ceil(duration)}, (_, second) => samples.get(second) ?? {second, momentaryLUFS:null});
  const valid = curve.map(row => row.momentaryLUFS).filter(Number.isFinite);
  const mean = valid.length ? valid.reduce((sum, n) => sum+n, 0) / valid.length : null;
  const standardDeviation = valid.length ? Math.sqrt(valid.reduce((sum, n) => sum + (n-mean)**2, 0) / valid.length) : null;
  let dips = 0;
  let inDip = false;
  for (let i = 0; i < curve.length; i++) {
    const prior = curve.slice(Math.max(0, i - AUDIO_MEDIAN_SECONDS), i).map(row => row.momentaryLUFS).filter(Number.isFinite);
    const dipped = prior.length > 0 && Number.isFinite(curve[i].momentaryLUFS) && curve[i].momentaryLUFS <= median(prior) - AUDIO_DIP_LU;
    if (dipped && !inDip) dips++;
    inDip = dipped;
  }
  return {sampleSeconds:1, dipThresholdLU:AUDIO_DIP_LU, runningMedianSeconds:AUDIO_MEDIAN_SECONDS,
    meanLUFS:mean, standardDeviationLU:standardDeviation, dips, curve};
}

function compare(report, baseline) {
  const fields = ['cuts.count','cuts.perMinute','cuts.shotsPerMinute','visual.longestHoldSeconds','visual.shareSecondsWithChange',
    'practices.changes','practices.distinct','practices.firstHookSeconds','words.novelShare',
    'audio.meanLUFS','audio.standardDeviationLU','audio.dips'];
  const deltas = {};
  for (const field of fields) {
    const path = field.split('.');
    const current = path.reduce((value, key) => value?.[key], report);
    const old = path.reduce((value, key) => value?.[key], baseline);
    if (Number.isFinite(current) && Number.isFinite(old)) deltas[field] = {baseline:old, current, delta:current-old};
  }
  return deltas;
}

function markdown(report) {
  const na = value => value === null || value === undefined ? 'not available' : Number.isFinite(value) ? Number(value.toFixed(3)) : value;
  const rows = [
    ['Duration (s)', na(report.durationSeconds)],
    ['Cuts (scene threshold 0.3)', report.cuts.count],
    ['Cuts per minute', na(report.cuts.perMinute)],
    ['Shots per minute', na(report.cuts.shotsPerMinute)],
    ['Longest hold (s; difference below 0.6 gray levels)', na(report.visual.longestHoldSeconds)],
    ['Longest hold interval (s)', `${na(report.visual.longestHoldFromSeconds)}–${na(report.visual.longestHoldToSeconds)}`],
    ['Share of seconds with visual change', na(report.visual.shareSecondsWithChange)],
    ['Practice changes', na(report.practices?.changes)],
    ['Distinct practices', na(report.practices?.distinct)],
    ['First hook (s)', na(report.practices?.firstHookSeconds)],
    ['On-screen words absent from narration', na(report.words?.novelShare)],
    ['Audio mean momentary LUFS', na(report.audio.meanLUFS)],
    ['Audio standard deviation (LU)', na(report.audio.standardDeviationLU)],
    ['Audio dips ≥6 LU below running 10 s median', report.audio.dips],
  ];
  let content = `# Pacing report: ${report.film}\n\n| Measure | Value |\n|---|---:|\n${rows.map(([key,value]) => `| ${key} | ${value} |`).join('\n')}\n`;
  if (report.compare) content += `\n## Change from baseline\n\n| Measure | Delta |\n|---|---:|\n${Object.entries(report.compare).map(([key,value]) => `| ${key} | ${na(value.delta)} |`).join('\n')}\n`;
  return content;
}

async function main(args) {
  const film = args[0];
  if (!film || film.startsWith('--')) throw new Error('usage: pacing.mjs <film.mp4> [--shots file] [--claims file --lines file] [--out prefix] [--compare baseline.json]');
  const options = {};
  for (let i = 1; i < args.length; i++) {
    if (['--shots','--claims','--lines','--out','--compare'].includes(args[i])) options[args[i].slice(2)] = args[++i];
    else throw new Error(`unknown option: ${args[i]}`);
  }
  if (Boolean(options.claims) !== Boolean(options.lines)) throw new Error('--claims and --lines must be used together');
  const read = file => file ? JSON.parse(readFileSync(file, 'utf8')) : null;
  const meta = probe(film);
  const report = {film:basename(film), durationSeconds:meta.duration, frameRate:meta.fps,
    cuts:cuts(film, meta.duration), visual:await visual(film, meta.fps, meta.duration),
    practices:practices(read(options.shots)), words:words(read(options.claims), read(options.lines)),
    audio:audio(film, meta.duration)};
  const curve = report.audio.curve;
  delete report.audio.curve;
  if (options.compare) report.compare = compare(report, read(options.compare));
  const out = options.out ?? 'qa/pacing';
  mkdirSync(dirname(out), {recursive:true});
  writeFileSync(`${out}.json`, JSON.stringify(report, null, 2) + '\n');
  writeFileSync(`${out}.md`, markdown(report));
  writeFileSync(`${out}.csv`, `second,momentary_lufs\n${curve.map(row => `${row.second},${row.momentaryLUFS ?? ''}`).join('\n')}\n`);
  console.log(markdown(report));
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch(error => {console.error(error.message); process.exitCode = 1;});
}
