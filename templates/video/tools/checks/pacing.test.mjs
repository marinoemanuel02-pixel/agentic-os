// Synthetic media gives known scene cuts, static spans, and an audio gap.
// The report is descriptive; these tests pin its measurements and files.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync, readFileSync, writeFileSync, rmSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const SCRIPT = fileURLToPath(new URL('./pacing.mjs', import.meta.url));

test('reports cuts, holds, practices, words and audio dips from a short film', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pacing-test-'));
  try {
    const film = join(dir, 'film.mp4');
    const render = spawnSync('ffmpeg', [
      '-v','error','-y',
      '-filter_complex',"color=c=red:s=320x180:r=10:d=3[v0];color=c=blue:s=320x180:r=10:d=3[v1];color=c=green:s=320x180:r=10:d=3[v2];[v0][v1][v2]concat=n=3:v=1:a=0[v];sine=frequency=440:sample_rate=48000:duration=9,volume=0:enable='between(t,3,5)'[a]",
      '-map','[v]','-map','[a]','-c:v','mpeg4','-q:v','2','-c:a','aac',film,
    ], {encoding:'utf8'});
    assert.equal(render.status, 0, render.stderr);
    const shots = join(dir, 'shots.json');
    const claims = join(dir, 'claims.json');
    const lines = join(dir, 'lines.json');
    const out = join(dir, 'pacing');
    writeFileSync(shots, JSON.stringify([
      {id:'S01',from:0,to:3,practice:'scene'},
      {id:'S02',from:3,to:6,practice:'scene',hook:true},
      {id:'S03',from:6,to:9,practice:'chart'},
    ]));
    writeFileSync(claims, JSON.stringify({screen:[{texts:['Red evidence and blue']},{texts:['New chart']}]}));
    writeFileSync(lines, JSON.stringify([{text:'The red evidence appears on a chart.'}]));
    const result = spawnSync(process.execPath, [SCRIPT, film, '--shots', shots, '--claims', claims, '--lines', lines, '--out', out], {encoding:'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(readFileSync(`${out}.json`));
    assert.ok(Math.abs(report.cuts.count - 2) <= 1, JSON.stringify(report.cuts));
    assert.ok(Math.abs(report.cuts.shotsPerMinute - 20) < 0.5, JSON.stringify(report.cuts));
    assert.ok(report.visual.longestHoldSeconds >= 2.5 && report.visual.longestHoldSeconds <= 3.1);
    assert.equal(report.practices.changes, 1);
    assert.equal(report.practices.distinct, 2);
    assert.equal(report.practices.firstHookSeconds, 3);
    assert.ok(report.words.novelShare > 0 && report.words.novelShare < 1);
    assert.ok(report.audio.dips >= 1, JSON.stringify(report.audio));
    assert.ok(existsSync(`${out}.md`) && existsSync(`${out}.csv`));
    const compared = spawnSync(process.execPath, [SCRIPT, film, '--out', join(dir, 'compared'), '--compare', `${out}.json`], {encoding:'utf8'});
    assert.equal(compared.status, 0, compared.stderr);
    assert.match(compared.stdout, /Change from baseline/);
    const comparison = JSON.parse(readFileSync(join(dir, 'compared.json')));
    assert.equal(comparison.compare['cuts.count'].delta, 0);
  } finally {
    rmSync(dir, {recursive:true, force:true});
  }
});
