// The stage documents ask for imported material from the start (R35, R39): the brief has a Sourcing section, every
// shot states its need and source, the rubric judges imported material and first-time viewers, and the contract
// names the asset commands. The reference-pack skill exists for both vendors.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {existsSync, readFileSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const TEMPLATE = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = f => readFileSync(join(TEMPLATE, f), 'utf8');

test('the brief has a Sourcing section with the channel policy and the download budget', () => {
  const brief = read('brief.md');
  assert.match(brief, /^## Sourcing$/m);
  for (const words of ['Fair use allowed', 'Acquisitions accepted', 'Reference pack', 'Download budget']) assert.match(brief, new RegExp(words));
});

test('every shot states its need and its source', () => {
  assert.match(read('shots.md'), /^\| Shot \| Line \| Beats \| Need \| Source \|/m);
  assert.match(read('shots.md'), /built, clip, photo, capture, model, lottie, mixed/);
});

test('the rubric judges imported material and what a first-time viewer recognises', () => {
  const rubric = read('rubric.md');
  assert.match(rubric, /Imported material shows its line's specific idea/);
  assert.match(rubric, /first-time viewer recognises every object and term/);
  assert.doesNotMatch(rubric, /^Generic stock look;/m);
});

test('the template contract names the asset commands and the human checks', () => {
  const agents = read('AGENTS.md');
  for (const c of ['aos asset search', 'aos asset fetch', 'aos asset capture', 'aos asset proxy', 'aos asset registry', 'aos asset credits', 'aos asset budget']) assert.ok(agents.includes(c), c);
  assert.match(agents, /asset id/);
  assert.match(agents, /qa\/assets\.md/);
});

test('the reference-pack skill exists with frontmatter', () => {
  const skill = join(TEMPLATE, '..', '..', 'agents-home', 'skills', 'video-references', 'SKILL.md');
  assert.ok(existsSync(skill));
  const text = readFileSync(skill, 'utf8');
  assert.match(text, /^---\nname: video-references\ndescription: .{40,}\n---/);
  assert.match(text, /without downloading/);
});
