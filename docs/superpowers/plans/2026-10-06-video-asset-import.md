# Video asset import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Tasks marked **[Codex]** go through `aos delegate codex --write` in their own worktree; tasks marked **[Claude]** are done in this session or by a Claude subagent. **[User]** steps need the user.

**Goal:** Films import real material (clips first, photos, page captures, 3D, transitions) found for each shot's need from any source, with every file's rights recorded, checked and credited; plus reference packs, consolidated rules, two template bug fixes and a token budget on Codex delegations.

**Architecture:** One Node tool for both vendors in `agents-home/video/assets/` (cache, budget, ledger, fetch, capture, proxy, registry, credits, search adapters) behind `aos asset` PowerShell wrappers that read API keys from the Windows secret store into the child's environment. Each film keeps `assets.json` (ledger) and `sourcing.json` (policy and budget); the template gets a gate `tools/checks/assets.mjs` wired into build and QA, a timeline exporter, media components and a transitions library. `aos delegate` gains a best-effort `--max-input` that follows the Codex rollout named by the run's own `thread_id`.

**Tech Stack:** Node 24 (ESM, `node --test`, type stripping for `.mts`), Remotion 4.0.529 + react-three-fiber + three.js (shared install), ffmpeg/ffprobe, yt-dlp, Playwright 1.63 (installed), PowerShell 5.1 + 7 (aos.psm1, Pester 5).

**Spec:** `docs/superpowers/specs/2026-10-06-video-asset-import-design.md` (with `...-codex-critique.md`). Read both.

## Global Constraints

- `aos.psm1` and `bootstrap.ps1` stay ASCII-only and parse under Windows PowerShell 5.1 and PowerShell 7: no `??`, no ternary, no `&&`/`||`. Run `aos test` after every edit to them.
- Tests never touch the network, the real profile, registry or `~/.aos`: Pester uses `$TestDrive`; Node tests use `mkdtempSync(tmpdir())` and a loopback HTTP server or injected `getJson`.
- New behaviour gets a test seen failing before the code. Fair-use and license refusals: Claude writes the failing tests (Task 2), Codex writes the gate (Task 3).
- No model names in the repo. No paid dependency. No new download without the user's consent with source and size (`@remotion/lottie` is optional Task 11).
- Every writable media path resolves through `AOS_VIDEO_MEDIA_ROOT`, else `~/.aos/video/<project folder name>` (Task 1). The asset cache `~/.aos/assets` is read-only to builds.
- Rights basis enum, exactly: `license`, `public-domain`, `cc0`, `fair-use`, `capture`, `own`. Acquisition enum, exactly: `api`, `direct-file`, `platform-feature`, `download-tool`.
- License allowlist ids, exactly: `cc0-1.0`, `pd`, `cc-by-3.0`, `cc-by-4.0`, `pexels`, `pixabay`, `mit`, `bsd-3-clause`, `lottie-simple`. Denied: anything else (NC, ND, CC-BY-SA, unknown).
- Fair-use limits: one use <= 8.0 s; fair-use + capture total <= 10 % of the film; sound kept only with `audio: "subject"` and <= 5.0 s; narration words overlap >= 50 % of the use; non-empty `rationale`; a generated source tag.
- The gate's success line is exactly `asset policy checks passed` (never "fair use").
- `docs/decisions.md` is append-only; a changed decision gets a new dated entry on top. Rule ids are never renumbered.
- Secrets: read with `Get-AosSecret` in PowerShell and passed only as child-process environment variables `AOS_KEY_PEXELS`, `AOS_KEY_PIXABAY`, `AOS_KEY_FREESOUND`; never written to files, logs, receipts or test output.
- Remotion stays pinned at 4.x. `@remotion/transitions` is not used.
- Do not touch `1-Projects/videos/alignment-now-it` or `~/.aos/video/alignment-now*` (another live session).

## Review Focus

1. A clip whose real downloaded length differs from the requested excerpt (yt-dlp cuts on keyframes): the ledger must record the ffprobe-measured `media.start/duration`, and the gate must use measured, not requested, times. Test in Task 4 (`measureMedia`) and Task 2 (`media.duration` shorter than `mediaTo` is refused).
2. A cache hit for a URL fetched by another film: costs 0 bytes, but the new film still needs its own ledger row and rights evidence. Test in Task 4.
3. A shot that uses the same asset twice (two `uses`): totals must sum both, and each use is checked alone. Covered by the Task 2 valid fixture (`a05` has two uses).
4. A Windows path with spaces or backslashes in `staticFile` literals or in the cache path: the gate scanner and the registry must use forward-slash relative paths. Test in Task 2 (`src` fixture path with a space) and Task 4 (`registryText` emits `/`).
5. The Codex rollout file appears seconds after the run starts or never (exec without a session file): `--max-input` must report `observed: false`, not kill. Test in Task 8.

---

## File map

| Path | Responsibility | Task |
|---|---|---|
| `templates/video/tools/media-root.mjs` | resolve the media root for Node tools | 1 |
| `templates/video/tools/media-root.sh` | same for shell tools (sourced) | 1 |
| `templates/video/tools/checks/media-root.test.mjs` | resolver + no-hard-coded-fallback tests | 1 |
| `templates/video/tools/checks/assets.test.mjs` + `fixtures/assets/` | gate contract (failing first) | 2 |
| `templates/video/tools/checks/assets.mjs` | the gate | 3 |
| `templates/video/tools/timeline-json.mts` | plan.ts + vo.json -> timeline JSON | 3 |
| `templates/video/sourcing.json`, `templates/video/assets.json` | empty policy and ledger | 3 |
| `agents-home/video/assets/asset.mjs` | CLI entry (`search fetch capture proxy registry credits budget`) | 4 |
| `agents-home/video/assets/lib/*.mjs` | cache, budget, ledger, fetch, measure, proxy, registry, credits | 4 |
| `agents-home/video/assets/adapters/*.mjs` + `test/fixtures/*.json` | search adapters | 5 |
| `aos.psm1` (`Invoke-AosAsset`), `tests/aos.Tests.ps1` | wrappers, secrets to env | 6 |
| `templates/video/src/lib/media/*.tsx`, `src/lib/transitions/*` | components and transitions | 7 |
| `aos.psm1` (`Start-AosProcessCore`, `Invoke-AosDelegate`, `Read-AosRolloutUsage`) | `--max-input` | 8 |
| `agents-home/skills/video-references/SKILL.md`, `agents-home/video/refs/` | reference packs | 9 |
| `templates/video/brief.md`, `shots.md`, `rubric.md`, `AGENTS.md` | pipeline text | 9 |
| `agents-home/video/video-rules.md`, `docs/decisions.md`, `aos.psm1` preflight | consolidation | 10 |

## Sequencing and vendor split

| Order | Task | Who | Needs | Est. tokens |
|---|---|---|---|---|
| 1 | Task 1 media root | Claude | - | 40 K |
| 2 | Task 2 gate tests (red) | Claude | - | 50 K |
| 3 | Task 3 gate | Codex (after its reset) | Task 2 | 40-70 K |
| 3 | Task 4 asset core | Claude (parallel with 3) | - | 120 K |
| 4 | Task 5 adapters | Codex | Task 4 interface | 60-100 K |
| 4 | Task 6 wrappers | Claude | Task 4 | 40 K |
| 5 | Task 7 components/transitions | Claude | Tasks 3, 4 | 120 K |
| 5 | Task 8 `--max-input` | Codex | - | 20-35 K |
| 6 | Task 9 references + pipeline text | Claude | Task 3 | 60 K |
| 6 | Task 10 consolidation | Claude, Codex bounded review | Tasks 1-9 | 60 K + 20 K |
| 7 | Task 11 Lottie (optional) | Claude | user consent | 20 K |
| 7 | Task 12 end-to-end on a 60 s test film | Claude | user keys + budget | 80 K |
| 8 | Task 13 close-out (memory, cleanup rest, notes) | Claude | Task 12 | 20 K |

At every row: `aos capacity`, `aos who`, read notes; write the split in an `aos note`. A limited vendor's next task goes to the other one at once, in its own worktree (R34). Each Codex task file has a `Read only:` line and a `Done =` line (enforced once Task 8 lands). Each Codex task is one `aos delegate codex --write --task <file> --verify "<command>" --idle 15` (plus `--max-input` once Task 8 lands); Claude reads the diff and runs the verify command on the host before merging.

Work happens on branch `video-assets` in worktree `~\.aos\worktrees\agentic-os-video-assets` (the shared checkout has another session's untracked files):

```bash
git -C "$HOME/OneDrive/Desktop/agentic-os" worktree add "$HOME/.aos/worktrees/agentic-os-video-assets" -b video-assets phone-orchestration-design
```

---

### Task 1: One media-root resolver for every template tool [Claude]

Copied projects keep a hard-coded fallback (`alignment-now-it` renders into `~/.aos/video/alignment-now` when the variable is unset), and running a template tool from the template itself created `~/.aos/video/{{name}}`.

**Files:**
- Create: `templates/video/tools/media-root.mjs`, `templates/video/tools/media-root.sh`, `templates/video/tools/checks/media-root.test.mjs`
- Modify (replace the fallback line only): `tools/build.sh:6`, `frames.sh:6`, `mix.sh:7`, `qa.sh:7`, `render-cached.sh:8`, `render.sh:6`, `still.sh:5`, `sync-app.sh:5`, `audio.mts:18`, `make-voice.cjs:22`, `screen.mjs:12`, `verify.mjs:14`, `word-times.py:34`, `checks/input-manifest.mjs:89`, and the `AOS_VIDEO_MEDIA_ROOT` fallbacks in `review-sheets.mts`, `verify-hero.mjs`
- Test: `tests/aos.Tests.ps1` (Describe 'Video template node checks': one `It` running the new test file)

**Interfaces:**
- Produces: `mediaRoot(projectDir: string): string` (throws `Error` with message starting `media root:` when refused); shell `source "$P/tools/media-root.sh"` sets `H` or exits 2.

- [ ] **Step 1: Write the failing test**

```js
// templates/video/tools/checks/media-root.test.mjs
// One resolver for every tool: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<project folder>; the template itself is refused.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, cpSync} from 'node:fs';
import {tmpdir, homedir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const TOOLS = dirname(dirname(fileURLToPath(import.meta.url)));
const {mediaRoot} = await import(join(TOOLS, 'media-root.mjs'));

function project(name) {
  const dir = join(mkdtempSync(join(tmpdir(), 'mr-')), name);
  mkdirSync(join(dir, 'tools'), {recursive: true});
  cpSync(join(TOOLS, 'media-root.sh'), join(dir, 'tools', 'media-root.sh'));
  return dir;
}

test('falls back to ~/.aos/video/<project folder name>', () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  delete process.env.AOS_VIDEO_MEDIA_ROOT;
  try { assert.equal(mediaRoot(project('my film')), join(homedir(), '.aos', 'video', 'my film')); }
  finally { if (saved !== undefined) process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test('AOS_VIDEO_MEDIA_ROOT wins', () => {
  const saved = process.env.AOS_VIDEO_MEDIA_ROOT;
  process.env.AOS_VIDEO_MEDIA_ROOT = join(tmpdir(), 'private-root');
  try { assert.equal(mediaRoot(project('x')), join(tmpdir(), 'private-root')); }
  finally { if (saved === undefined) delete process.env.AOS_VIDEO_MEDIA_ROOT; else process.env.AOS_VIDEO_MEDIA_ROOT = saved; }
});

test('refuses the template folder and unsubstituted placeholders', () => {
  const tpl = project('video');
  writeFileSync(join(tpl, '_gitignore'), '');
  assert.throws(() => mediaRoot(tpl), /^Error: media root: refusing the video template/);
  assert.throws(() => mediaRoot(project('{{name}}')), /^Error: media root: unsubstituted/);
});

test('the shell resolver agrees and refuses with exit 2', () => {
  const dir = project('shell film');
  const env = {...process.env}; delete env.AOS_VIDEO_MEDIA_ROOT;
  const ok = spawnSync('bash', ['-c', 'P="$1"; . "$P/tools/media-root.sh"; printf %s "$H"', '_', dir], {encoding: 'utf8', env});
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout.replaceAll('\\', '/'), /\/\.aos\/video\/shell film$/);
  writeFileSync(join(dir, '_gitignore'), '');
  const bad = spawnSync('bash', ['-c', 'P="$1"; . "$P/tools/media-root.sh"; echo unreachable', '_', dir], {encoding: 'utf8', env});
  assert.equal(bad.status, 2);
  assert.doesNotMatch(bad.stdout, /unreachable/);
});

test('no tool keeps a hard-coded film fallback', () => {
  const offenders = [];
  const walk = d => { for (const n of readdirSync(d)) { const p = join(d, n);
    if (statSync(p).isDirectory()) { if (n !== 'fixtures' && n !== 'node_modules') walk(p); continue; }
    if (!/\.(sh|mjs|mts|cjs|py|ts)$/.test(n) || n.endsWith('.test.mjs')) continue;
    const code = readFileSync(p, 'utf8').split('\n').filter(l => !/^\s*(#|\/\/)/.test(l)).join('\n');
    if (/\.aos[\\/"', ]+video[\\/"', ]+(\{\{name\}\}|["'][A-Za-z0-9])/.test(code)) offenders.push(p); } };
  walk(TOOLS);
  assert.deepEqual(offenders, []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --no-warnings --test templates/video/tools/checks/media-root.test.mjs`
Expected: FAIL, `Cannot find module ... media-root.mjs`.

- [ ] **Step 3: Write minimal implementation**

```js
// templates/video/tools/media-root.mjs
// Where a film's heavy media lives: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<project folder name>. A copied project
// therefore never writes into the film it was copied from, and the template itself is refused (no ~/.aos/video/{{name}}).
import {existsSync} from 'node:fs';
import {homedir} from 'node:os';
import {basename, join, resolve} from 'node:path';

export function mediaRoot(projectDir) {
  if (process.env.AOS_VIDEO_MEDIA_ROOT) return resolve(process.env.AOS_VIDEO_MEDIA_ROOT);
  const dir = resolve(projectDir);
  const name = basename(dir);
  if (name.includes('{{')) throw new Error(`media root: unsubstituted project name "${name}"`);
  if (existsSync(join(dir, '_gitignore'))) throw new Error('media root: refusing the video template; run tools from a project made by aos video new, or set AOS_VIDEO_MEDIA_ROOT');
  return join(homedir(), '.aos', 'video', name);
}
```

```bash
# templates/video/tools/media-root.sh  (sourced after P is set to the project folder)
# Sets H: AOS_VIDEO_MEDIA_ROOT, else ~/.aos/video/<project folder name>. Refuses the template and placeholders (exit 2).
if [ -n "${AOS_VIDEO_MEDIA_ROOT:-}" ]; then H="$AOS_VIDEO_MEDIA_ROOT"
else
  _mr_name="$(basename "$P")"
  case "$_mr_name" in *'{{'*) echo "media root: unsubstituted project name \"$_mr_name\"" >&2; exit 2;; esac
  if [ -f "$P/_gitignore" ]; then echo "media root: refusing the video template; set AOS_VIDEO_MEDIA_ROOT" >&2; exit 2; fi
  H="$HOME/.aos/video/$_mr_name"
fi
```

In each shell tool replace the fallback line with (P must already be set; in `render.sh`, `still.sh`, `frames.sh`, `mix.sh`, `sync-app.sh`, `qa.sh`, `render-cached.sh` add `P="$(cd "$(dirname "$0")/.." && pwd)"` above it if missing):

```bash
. "$P/tools/media-root.sh"
```

(`sync-app.sh` then uses `"$H/app"` where it used the old `.../app` value.) In Node tools replace the fallback expression with `mediaRoot(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'))` (for `checks/input-manifest.mjs` the project root it already computes; for `make-voice.cjs` use `require` of a small CJS twin is not needed: inline the same three checks). In `word-times.py`:

```python
def media_root(project: Path) -> Path:
    env = os.environ.get("AOS_VIDEO_MEDIA_ROOT")
    if env:
        return Path(env)
    if "{{" in project.name or (project / "_gitignore").exists():
        sys.exit("media root: refusing the template or an unsubstituted name; set AOS_VIDEO_MEDIA_ROOT")
    return Path.home() / ".aos" / "video" / project.name

media = media_root(Path(__file__).resolve().parent.parent)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --no-warnings --test templates/video/tools/checks/media-root.test.mjs templates/video/tools/checks/pipeline.test.mjs templates/video/tools/checks/input-manifest.test.mjs`
Expected: PASS (pipeline/input-manifest fixtures set `AOS_VIDEO_MEDIA_ROOT`; if a fixture relied on the old fallback, set the variable in the fixture, never weaken the resolver).

- [ ] **Step 5: Wire into Pester, run `aos test`, commit**

Add to `tests/aos.Tests.ps1` inside `Describe 'Video template node checks'`:

```powershell
    It 'resolves the media root from the project folder and refuses the template (node --test)' {
        $result = & node --no-warnings --test (Join-Path $PSScriptRoot '..\templates\video\tools\checks\media-root.test.mjs') 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $result
    }
```

```bash
pwsh -NoProfile -Command "Import-Module ./aos.psm1 -Force; aos test"
git add templates/video/tools tests/aos.Tests.ps1
git commit -m "video template: one media-root resolver (project folder name, template refused); no film-specific fallbacks"
```

Then `aos note "alignment-now-it: its tools fall back to ~/.aos/video/alignment-now when AOS_VIDEO_MEDIA_ROOT is unset (copied from alignment-now). Fixed in the template (video-assets branch, tools/media-root.*); port it or always set the variable." --as claude`.

---

### Task 2: The asset gate contract, failing first [Claude]

**Files:**
- Create: `templates/video/tools/checks/assets.test.mjs`
- Create: `templates/video/tools/checks/fixtures/assets/valid/` with `assets.json`, `sourcing.json`, `timeline.json`, `words.json`, `description.md`, `claims.json`, `research/rights/*.json`, `public/assets/*`, `src/shots/S03 Clip.tsx`, `src/data/assets.ts`

**Interfaces:**
- Produces (for Task 3): `checkAssets(dir: string, opts?: {timeline?: string}) -> {ok: boolean, errors: string[], report: {perBasis: Record<string, number>, fairUseSeconds: number, filmSeconds: number, share: number, bySearchStep: Record<string, number>}}`. Every error string starts with the asset id or file it concerns, then `: `. CLI: `node tools/checks/assets.mjs <projectDir> [--timeline <json>] [--report <qa/assets.md>]` exits 0 printing `asset policy checks passed`, else exit 1 and one error per line.
- Fixture layout (the gate reads these paths relative to `dir`): `assets.json` `{schema:1, rows:[...]}`; `sourcing.json` `{schema:1, fairUse:true, acquisition:{"youtube":["api","platform-feature"],"*":["api","direct-file","platform-feature","download-tool"]}, budget:{approvedMB:2000, approvedAt:"...", approvedBy:"user"}}`; `timeline.json` `{fps:30, frames:1800, shots:[{id,from,frames}], lines:[{id,from}]}` (frames); `words.json` (per line, `[word, startS, endS]` relative to the line start, as written by `word-times.py`); derivatives under `public/assets/`; `src/` scanned for literals.

- [ ] **Step 1: Build the valid fixture**

Timeline: 60 s at 30 fps (1800 frames). Shots: `S01` 0-300, `S02` 300-600, `S03` 600-900, `S04` 900-1200, `S05` 1200-1500, `S06` 1500-1800. Lines: `L01` from 0, `L02` from 600, `L03` from 1200. `words.json`: `L02` has words covering 0.0-6.0 s continuously (so film 20.0-26.0 s); `L03` covers 0.0-2.0 s (film 40.0-42.0 s); `L01` covers 0-10 s.

`assets.json` rows (derivative bytes are tiny text files; hashes are their real sha256, computed by a fixture builder script `fixtures/assets/build.mjs` that writes the files and the hashes, so the fixture is regenerated, not hand-hashed):

| id | basis | license | uses (shot, shotFrom, mediaFrom-mediaTo) | notes |
|---|---|---|---|---|
| a01 | license | pexels | S01, 0, 0-8 | credit "Video by Ana on Pexels" |
| a02 | cc0 | cc0-1.0 | S02, 0, 0-5 | Poly Haven model `.glb` |
| a03 | public-domain | pd | S04, 0, 0-4 | NASA clip, `clearance: null`, `subjects: []` |
| a04 | own | null | S06, 0, 0-3 | |
| a05 | fair-use | null | S03, 0, 0-3 **and** S03, 90, 3-5 | `acquisition: "direct-file"`, `platform: "lab-site"`, rationale filled, film 20-23 s and 23-25 s, words cover both |
| a06 | capture | null | S05, 0, 0-1 | `acquisition: "platform-feature"`, film 40-41 s, words cover |

Fair-use + capture = 3 + 2 + 1 = 6.0 s = 10.0 % of 60 s (at the cap). `description.md` contains a `## Credits` section with "Video by Ana on Pexels" and "Powered by Poly Haven". `claims.json` `screen` has a generated `label` entry for each fair-use/capture `credit`. `src/shots/S03 Clip.tsx` uses `<Clip asset="a05" use="u1" />` only; `src/lib/media/Clip.tsx` contains the one allowed form `staticFile(ASSETS[asset].src)`; `src/data/assets.ts` is the registry text from Task 4's format:

```ts
// generated by aos asset registry; do not edit
export const ASSETS = {
  "a01": { "src": "assets/a01.mp4", "kind": "clip" },
  "a02": { "src": "assets/a02.glb", "kind": "model" }
} as const;
```

(all six ids listed).

- [ ] **Step 2: Write the failing tests**

```js
// templates/video/tools/checks/assets.test.mjs
// The asset gate (R35): every imported file has a rights row, a known license or a bounded fair-use/capture use,
// credits, evidence and an accepted acquisition. Each refusal mutates one field of the valid 60 s fixture.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {cpSync, mkdtempSync, readFileSync, writeFileSync, rmSync, mkdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const HERE = dirname(fileURLToPath(import.meta.url));
const VALID = join(HERE, 'fixtures', 'assets', 'valid');
const GATE = join(HERE, 'assets.mjs');
const {checkAssets} = await import(GATE);

function copy() { const d = join(mkdtempSync(join(tmpdir(), 'assets-gate-')), 'film one'); cpSync(VALID, d, {recursive: true}); return d; }
const read = (d, f) => JSON.parse(readFileSync(join(d, f), 'utf8'));
const write = (d, f, v) => writeFileSync(join(d, f), typeof v === 'string' ? v : JSON.stringify(v, null, 2));
function mutate(fn) { const d = copy(); const led = read(d, 'assets.json'); fn(led, d); write(d, 'assets.json', led); return d; }
const row = (led, id) => led.rows.find(r => r.id === id);
function refused(d, pattern) {
  const r = checkAssets(d);
  assert.equal(r.ok, false, 'expected a refusal');
  assert.ok(r.errors.some(e => pattern.test(e)), `no error matched ${pattern}: ${r.errors.join(' | ')}`);
}

test('the valid fixture passes at exactly the 10 % fair-use cap', () => {
  const r = checkAssets(copy());
  assert.deepEqual(r.errors, []);
  assert.equal(r.ok, true);
  assert.equal(r.report.fairUseSeconds, 6);
  assert.equal(r.report.filmSeconds, 60);
  assert.deepEqual(r.report.perBasis, {license: 1, cc0: 1, 'public-domain': 1, own: 1, 'fair-use': 1, capture: 1});
});

test('CLI prints the policy line, never "fair use"', () => {
  const out = spawnSync(process.execPath, [GATE, copy()], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stderr);
  assert.match(out.stdout, /^asset policy checks passed$/m);
  assert.doesNotMatch(out.stdout, /fair use/i);
});

test('a public/assets file without a row is refused', () => { const d = copy(); write(d, 'public/assets/stray.mp4', 'x'); refused(d, /^public\/assets\/stray\.mp4: no ledger row/); });
test('a changed derivative is refused', () => { const d = copy(); write(d, 'public/assets/a01.mp4', 'changed'); refused(d, /^a01: derivative hash mismatch/); });
test('a license outside the allowlist is refused', () => refused(mutate(l => { row(l, 'a01').license = 'cc-by-nc-4.0'; }), /^a01: license cc-by-nc-4.0 not allowed/));
test('CC-BY-SA is refused', () => refused(mutate(l => { row(l, 'a01').license = 'cc-by-sa-4.0'; }), /^a01: license cc-by-sa-4.0 not allowed/));
test('a CC-BY row without credit is refused', () => refused(mutate(l => { const r = row(l, 'a01'); r.license = 'cc-by-4.0'; r.credit = ''; }), /^a01: credit required/));
test('a credit missing from description.md is refused', () => { const d = copy(); write(d, 'description.md', '# Film\n\n## Credits\n\nPowered by Poly Haven\n'); refused(d, /^a01: credit missing from description\.md/); });
test('a fair-use use over 8 s is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].mediaTo = 8.1; row(l, 'a05').media.duration = 9; }), /^a05: use u1 is 8\.1 s/));
test('fair-use + capture over 10 % is refused', () => refused(mutate(l => { row(l, 'a06').uses[0].mediaTo = 1.1; row(l, 'a06').media.duration = 2; }), /fair-use and capture total 6\.1 s/));
test('kept sound without audio subject is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].audio = 'kept'; }), /^a05: use u1 keeps sound/));
test('audio subject over 5 s is refused', () => refused(mutate(l => { const u = row(l, 'a05').uses[0]; u.audio = 'subject'; u.mediaTo = 5.5; row(l, 'a05').media.duration = 9; row(l, 'a05').uses[1].mediaFrom = 5.5; row(l, 'a05').uses[1].mediaTo = 6.0; }), /^a05: use u1 audio subject 5\.5 s over 5 s/));
test('no overlapping narration is refused', () => { const d = copy(); const w = read(d, 'words.json'); w.L02 = [['late', 7.0, 9.0]]; write(d, 'words.json', w); refused(d, /^a05: use u1 has narration over 0 % of its 3 s/); });
test('an empty rationale is refused', () => refused(mutate(l => { row(l, 'a05').uses[0].rationale = ' '; }), /^a05: use u1 needs a rationale/));
test('missing rights evidence is refused', () => { const d = copy(); rmSync(join(d, 'research', 'rights', 'a05.json')); refused(d, /^a05: rights evidence missing/); });
test('an acquisition the brief refuses is refused', () => refused(mutate(l => { const r = row(l, 'a05'); r.acquisition = 'download-tool'; r.platform = 'youtube'; }), /^a05: acquisition download-tool from youtube not accepted by sourcing\.json/));
test('a NASA person without clearance is refused', () => refused(mutate(l => { row(l, 'a03').subjects = ['person']; }), /^a03: needs clearance for person/));
test('a use past the measured media is refused', () => refused(mutate(l => { row(l, 'a01').media.duration = 7.5; }), /^a01: use u1 ends at 8 s past the measured 7\.5 s/));
test('a missing generated source tag is refused', () => { const d = copy(); const c = read(d, 'claims.json'); c.screen = c.screen.filter(s => !s.asset || s.asset !== 'a05'); write(d, 'claims.json', c); refused(d, /^a05: no generated source tag in claims\.json/); });
test('a dynamic staticFile path is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'const n = "a05"; export const X = () => staticFile(`assets/${n}.mp4`);\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('a literal staticFile path outside the registry is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => staticFile("assets/a05.mp4");\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('staticFile(ASSETS[...].src) outside src/lib/media is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => staticFile(ASSETS["a05"].src);\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: dynamic or literal media path/); });
test('a remote media URL in src is refused', () => { const d = copy(); write(d, 'src/shots/S03 Clip.tsx', 'export const X = () => <OffthreadVideo src="https://example.com/a.mp4" />;\n'); refused(d, /^src\/shots\/S03 Clip\.tsx: remote media URL/); });
test('a .gltf with external resources is refused', () => { const d = copy(); write(d, 'public/assets/a02.gltf', JSON.stringify({buffers: [{uri: 'scene.bin'}]})); const l = read(d, 'assets.json'); row(l, 'a02').derivatives.push({path: 'assets/a02.gltf', sha256: 'x', ffmpeg: null}); write(d, 'assets.json', l); refused(d, /^a02: assets\/a02\.gltf references external resources/); });
test('an unknown basis is refused', () => refused(mutate(l => { row(l, 'a04').basis = 'probably-fine'; }), /^a04: unknown basis probably-fine/));
test('a fair-use row when the film disallows fair use is refused', () => { const d = copy(); const s = read(d, 'sourcing.json'); s.fairUse = false; write(d, 'sourcing.json', s); refused(d, /^a05: fair use disabled in sourcing\.json/); });
test('report file is written', () => {
  const d = copy(); const rep = join(d, 'qa', 'assets.md'); mkdirSync(join(d, 'qa'));
  const out = spawnSync(process.execPath, [GATE, d, '--report', rep], {encoding: 'utf8'});
  assert.equal(out.status, 0, out.stderr);
  const text = readFileSync(rep, 'utf8');
  assert.match(text, /fair-use and capture: 6\.0 s of 60\.0 s \(10\.0 %\)/);
  assert.match(text, /Content ID/);
  assert.match(text, /supporting evidence/);
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `node --no-warnings --test templates/video/tools/checks/assets.test.mjs`
Expected: FAIL, `Cannot find module ... assets.mjs` (every test).

- [ ] **Step 4: Commit the red contract**

```bash
git add templates/video/tools/checks/assets.test.mjs templates/video/tools/checks/fixtures/assets
git commit -m "video template: asset gate contract (R35), failing first; valid 60 s fixture at the 10 % cap and one mutation per refusal"
```

---

### Task 3: The asset gate and its wiring [Codex]

Delegate with this task file (`tasks/codex-asset-gate.md` in the worktree, not committed to the template):

```markdown
Implement templates/video/tools/checks/assets.mjs so that `node --no-warnings --test templates/video/tools/checks/assets.test.mjs` passes. Do not edit the test file or the fixture (except regenerating hashes with fixtures/assets/build.mjs if you change nothing else). Read only: the spec sections 3 and 4 (docs/superpowers/specs/2026-10-06-video-asset-import-design.md), the test file, the fixture, tools/checks/currency.mjs (style), tools/checks/input-manifest.mjs, tools/build.sh, tools/qa.sh, src/data/plan.ts. Then: (1) tools/timeline-json.mts prints {fps, frames, shots:[{id,from,frames}], lines:[{id,from}]} from src/data/plan.ts + src/data/vo.json; (2) build.sh and qa.sh run `node --no-warnings tools/timeline-json.mts > "$H/qa/timeline.json"` then `node tools/checks/assets.mjs "$P" --timeline "$H/qa/timeline.json" --report "$P/qa/assets.md"` before rendering / before decoding; (3) input-manifest.mjs adds assets.json, sourcing.json and every research/rights/*.json to projectInputs files (public/assets is already inside the public tree); (4) empty templates/video/assets.json {"schema":1,"rows":[]} and sourcing.json {"schema":1,"fairUse":false,"acquisition":{"youtube":["api","platform-feature"],"*":["api","direct-file","platform-feature"]},"budget":null}; an empty ledger passes. Done = the verify command passes.
```

```bash
aos delegate codex --write --task tasks/codex-asset-gate.md --verify "node --no-warnings --test templates/video/tools/checks/assets.test.mjs templates/video/tools/checks/input-manifest.test.mjs templates/video/tools/checks/pipeline.test.mjs" --idle 15 --repo "$HOME/.aos/worktrees/agentic-os-video-assets"
```

**Interfaces:**
- Consumes: Task 2's `checkAssets` contract and fixture layout; Task 1's `mediaRoot`.
- Produces: `checkAssets`, CLI, `tools/timeline-json.mts`, wiring.

Implementation notes for the delegate (the contract is the test; these pin choices the test leaves open):
- Film seconds of a use: `(shot.from + use.shotFrom) / fps` to that plus `mediaTo - mediaFrom`.
- Narration overlap: union of word intervals `line.from/fps + start .. + end` intersected with the use interval, divided by the use length; refuse below 0.5 and print the percentage rounded down.
- Source scanning: every `.ts/.tsx/.mts` under `src/` except `src/data/assets.ts`; refuse every `staticFile(` except the exact form `staticFile(ASSETS[<identifier>].src)` inside `src/lib/media/` (all media goes through the registry and the media components), `useGLTF(` with a string or template argument, `src=` or `"src":` with `http://`/`https://` ending in a media extension (`mp4|webm|mov|png|jpe?g|webp|gif|glb|gltf|json|lottie|mp3|wav|ogg`).
- Credits: each `license` row with `cc-by-*` needs `credit`; every non-empty `credit` of a `license`/`cc0` row must appear verbatim under `## Credits` in `description.md`; Poly Haven rows (`url` host `polyhaven.com`) need the line `Powered by Poly Haven`.
- Report (`--report`): counts per basis, `fair-use and capture: X s of Y s (Z %)` with one decimal, a "Human checks" list (commentary relevance, credit legibility, excerpt takes no more than needed) and the Content ID paragraph: "Stock footage and sound effects are sometimes claimed by Content ID in error. The ledger and rights evidence are supporting evidence for a dispute, not proof."

- [ ] **Step 1:** Write the task file and run the delegate command above (check `aos capacity` first; Codex must not be `limited`).
- [ ] **Step 2:** Read the receipt (`aos coord show <id>`), grep the output for "usage limit", read the full diff.
- [ ] **Step 3:** On the host: run the verify command; then `pwsh -NoProfile -Command "Import-Module ./aos.psm1 -Force; aos test"`.
- [ ] **Step 4:** Add the Pester `It` (same shape as Task 1 Step 5) for `assets.test.mjs`; merge the delegate branch; commit:

```bash
git commit -m "video template: asset gate (R35) wired into build, QA and the input manifest; timeline exporter (Codex, reviewed)"
```

---

### Task 4: The asset tool core [Claude]

**Files:**
- Create: `agents-home/video/assets/asset.mjs`, `lib/types.mjs`, `lib/cache.mjs`, `lib/budget.mjs`, `lib/ledger.mjs`, `lib/fetch.mjs`, `lib/measure.mjs`, `lib/proxy.mjs`, `lib/registry.mjs`, `lib/credits.mjs`, `lib/capture.mjs`
- Test: `agents-home/video/assets/test/core.test.mjs`, `test/capture.test.mjs`

**Interfaces:**
- Produces (used by Tasks 5, 6, 7, 12):
  - `lib/types.mjs` JSDoc `Candidate = {source: string, id: string, kind: 'clip'|'photo'|'model'|'hdri'|'texture'|'sfx', title: string, page: string, download: string, license: string|null, licenseUrl: string|null, author: string, credit: string, duration: number|null, width: number|null, height: number|null, bytes: number|null}`
  - `cachePaths(root?: string) -> {root, objects, index}` (default `~/.aos/assets`, `AOS_ASSET_CACHE` overrides)
  - `budgetFor(filmDir) -> {approvedBytes: number|null, usedBytes: number}`; `reserve(filmDir, bytes) -> {ok: boolean, remaining: number}`; `charge(filmDir, bytes, url, outcome)` appends to `<mediaRoot>/assets-budget.jsonl`
  - `withFilmLock(filmDir, fn)` serializes fetches (lock file `<mediaRoot>/assets.lock`, stale after 30 min)
  - `fetchHttp(url, {capBytes, dest, headers}) -> {bytes, complete: boolean}` streaming with abort at cap
  - `fetchExcerpt(url, {sourceIn, sourceOut, capBytes, dest}) -> {bytes, complete}` via `yt-dlp --download-sections "*IN-OUT" --force-keyframes-at-cuts --max-filesize <cap> -o dest`
  - `measureMedia(file) -> {duration: number|null, width, height, hasAudio: boolean}` (ffprobe)
  - `addRow(filmDir, row)`, `readLedger(filmDir)`; `registryText(rows) -> string` (format in Task 2 fixture); `creditsBlock(rows) -> string`
  - `makeProxy(cacheFile, outFile) -> {sha256, ffmpeg: string}` and `makeAudio(cacheFile, outFile, fromS, toS)`
  - `capture(url, {mode: 'shot'|'scroll'|'record', seconds, dest}) -> {file, bytes}` (Playwright Chromium from `PLAYWRIGHT_BROWSERS_PATH`)

- [ ] **Step 1: Write the failing tests**

```js
// agents-home/video/assets/test/core.test.mjs
// Cache, budget and fetch against a loopback server; ffmpeg-made media for measure/proxy. No network.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import http from 'node:http';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync, statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {budgetFor, reserve, charge} from '../lib/budget.mjs';
import {fetchHttp} from '../lib/fetch.mjs';
import {measureMedia} from '../lib/measure.mjs';
import {makeProxy} from '../lib/proxy.mjs';
import {registryText} from '../lib/registry.mjs';
import {creditsBlock} from '../lib/credits.mjs';
import {storeObject, lookupUrl} from '../lib/cache.mjs';

function film() {
  const dir = join(mkdtempSync(join(tmpdir(), 'asset-core-')), 'film');
  mkdirSync(dir, {recursive: true});
  process.env.AOS_VIDEO_MEDIA_ROOT = join(dir, '..', 'media');
  process.env.AOS_ASSET_CACHE = join(dir, '..', 'cache');
  writeFileSync(join(dir, 'sourcing.json'), JSON.stringify({schema: 1, fairUse: true, acquisition: {'*': ['direct-file']}, budget: {approvedMB: 1, approvedAt: '2026-10-07', approvedBy: 'user'}}));
  return dir;
}
function server(bytes) {
  return new Promise(res => { const s = http.createServer((q, r) => { r.writeHead(200, {'content-type': 'video/mp4'}); r.end(Buffer.alloc(bytes, 7)); });
    s.listen(0, '127.0.0.1', () => res({url: `http://127.0.0.1:${s.address().port}/x.mp4`, close: () => s.close()})); });
}

test('budget: 1 MB approved, reservations and charges count network bytes', () => {
  const d = film();
  assert.deepEqual(budgetFor(d), {approvedBytes: 1048576, usedBytes: 0});
  assert.equal(reserve(d, 600000).ok, true);
  charge(d, 600000, 'http://a', 'complete');
  assert.equal(reserve(d, 600000).ok, false);
  charge(d, 1000, 'http://b', 'failed');
  assert.equal(budgetFor(d).usedBytes, 601000);
});

test('budget: no approval means nothing may be fetched', () => {
  const d = film();
  writeFileSync(join(d, 'sourcing.json'), JSON.stringify({schema: 1, fairUse: false, acquisition: {}, budget: null}));
  assert.equal(reserve(d, 1).ok, false);
});

test('fetchHttp aborts at the cap and reports an incomplete transfer', async () => {
  const s = await server(300000);
  try {
    const dest = join(mkdtempSync(join(tmpdir(), 'f-')), 'x.mp4');
    const r = await fetchHttp(s.url, {capBytes: 100000, dest});
    assert.equal(r.complete, false);
    assert.ok(r.bytes <= 100000 + 65536, `read ${r.bytes}`);
    const ok = await fetchHttp(s.url, {capBytes: 400000, dest});
    assert.equal(ok.complete, true);
    assert.equal(ok.bytes, 300000);
  } finally { s.close(); }
});

test('a cache hit is free and keeps one object for two films', async () => {
  film();
  const src = join(mkdtempSync(join(tmpdir(), 'o-')), 'a.bin');
  writeFileSync(src, 'same bytes');
  const one = storeObject(src, {url: 'http://x/a', retrieved: '2026-10-07T10:00:00Z'});
  const two = lookupUrl('http://x/a');
  assert.equal(two.sha256, one.sha256);
  assert.ok(existsSync(one.path));
});

test('fetchAsset: a cache hit charges nothing but still writes this film's row and evidence', async () => {
  const {fetchAsset} = await import('../asset.mjs');
  const s = await server(1000);
  try {
    const a = film(), b = film();
    const shared = mkdtempSync(join(tmpdir(), 'shared-cache-'));
    const use = d => { process.env.AOS_VIDEO_MEDIA_ROOT = join(d, '..', 'media'); process.env.AOS_ASSET_CACHE = shared; };
    const opts = {url: s.url, id: 'a01', basis: 'cc0', license: 'cc0-1.0', acquisition: 'direct-file', platform: 'test', why: 'test need', kind: 'clip', credit: ''};
    use(a); await fetchAsset(a, opts, {fetchPage: async () => 'license page'});
    use(b); const before = budgetFor(b).usedBytes;
    await fetchAsset(b, opts, {fetchPage: async () => 'license page'});
    assert.equal(budgetFor(b).usedBytes, before);
    assert.ok(existsSync(join(b, 'research', 'rights', 'a01.json')));
    assert.equal(JSON.parse(readFileSync(join(b, 'assets.json'), 'utf8')).rows[0].id, 'a01');
  } finally { s.close(); }
});

test('measureMedia reads the real duration of a cut excerpt', () => {
  const f = join(mkdtempSync(join(tmpdir(), 'm-')), 'c.mp4');
  const r = spawnSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=d=2.4:s=160x90:r=30', '-c:v', 'libx264', f]);
  assert.equal(r.status, 0);
  const m = measureMedia(f);
  assert.ok(Math.abs(m.duration - 2.4) < 0.05, `duration ${m.duration}`);
  assert.equal(m.hasAudio, false);
});

test('makeProxy writes a silent 1080p30 H.264 file and returns its hash and settings', () => {
  const dir = mkdtempSync(join(tmpdir(), 'p-'));
  const f = join(dir, 'in.mp4');
  spawnSync('ffmpeg', ['-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=d=1:s=320x180:r=25', '-f', 'lavfi', '-i', 'sine=d=1', '-shortest', f]);
  const out = join(dir, 'a01.mp4');
  const p = makeProxy(f, out);
  const m = measureMedia(out);
  assert.equal(m.hasAudio, false);
  assert.equal(m.width, 1920);
  assert.match(p.sha256, /^[0-9a-f]{64}$/);
  assert.match(p.ffmpeg, /-crf 18/);
});

test('registryText uses forward slashes and sorted ids', () => {
  const t = registryText([{id: 'b2', kind: 'clip', derivatives: [{path: 'assets/b2.mp4'}]}, {id: 'a1', kind: 'model', derivatives: [{path: 'assets\\a1.glb'}]}]);
  assert.match(t, /"a1": \{ "src": "assets\/a1\.glb", "kind": "model" \},\n  "b2"/);
});

test('creditsBlock lists required credits once and the Poly Haven line', () => {
  const t = creditsBlock([
    {basis: 'license', license: 'cc-by-4.0', credit: 'Photo by X (CC BY 4.0)', url: 'https://commons.wikimedia.org/f'},
    {basis: 'cc0', license: 'cc0-1.0', credit: 'Model: Y', url: 'https://polyhaven.com/a/y'},
    {basis: 'fair-use', credit: 'Source: Lab, 2026-09-09', url: 'https://lab.example/demo'}]);
  assert.match(t, /^## Credits\n/);
  assert.match(t, /Photo by X \(CC BY 4\.0\)/);
  assert.match(t, /Powered by Poly Haven/);
  assert.match(t, /Source: Lab, 2026-09-09/);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `node --no-warnings --test agents-home/video/assets/test/core.test.mjs`
Expected: FAIL, modules not found.

- [ ] **Step 3: Implement the modules**

```js
// agents-home/video/assets/lib/budget.mjs
// The film's download budget counts network bytes received (failed and partial transfers too); a cache hit is free.
import {readFileSync, appendFileSync, existsSync, mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {filmMediaRoot} from './paths.mjs';

export function budgetFor(filmDir) {
  const s = JSON.parse(readFileSync(join(filmDir, 'sourcing.json'), 'utf8'));
  const approvedBytes = s.budget && s.budget.approvedBy === 'user' ? Math.round(s.budget.approvedMB * 1048576) : null;
  const log = join(filmMediaRoot(filmDir), 'assets-budget.jsonl');
  let usedBytes = 0;
  if (existsSync(log)) for (const l of readFileSync(log, 'utf8').split('\n')) if (l.trim()) usedBytes += JSON.parse(l).bytes;
  return {approvedBytes, usedBytes};
}

export function reserve(filmDir, bytes) {
  const {approvedBytes, usedBytes} = budgetFor(filmDir);
  if (approvedBytes === null) return {ok: false, remaining: 0};
  const remaining = approvedBytes - usedBytes;
  return {ok: bytes <= remaining, remaining};
}

export function charge(filmDir, bytes, url, outcome) {
  const root = filmMediaRoot(filmDir);
  mkdirSync(root, {recursive: true});
  appendFileSync(join(root, 'assets-budget.jsonl'), JSON.stringify({ts: new Date().toISOString(), bytes, url, outcome}) + '\n');
}
```

```js
// agents-home/video/assets/lib/paths.mjs
import {homedir} from 'node:os';
import {basename, join, resolve} from 'node:path';
export const filmMediaRoot = filmDir => process.env.AOS_VIDEO_MEDIA_ROOT ? resolve(process.env.AOS_VIDEO_MEDIA_ROOT) : join(homedir(), '.aos', 'video', basename(resolve(filmDir)));
export const cacheRoot = () => process.env.AOS_ASSET_CACHE ? resolve(process.env.AOS_ASSET_CACHE) : join(homedir(), '.aos', 'assets');
```

```js
// agents-home/video/assets/lib/fetch.mjs
// Streams a URL to dest and stops at capBytes: an unknown size is allowed only under the cap.
import {createWriteStream} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {statSync, existsSync} from 'node:fs';

export async function fetchHttp(url, {capBytes, dest, headers = {}}) {
  const ctl = new AbortController();
  const res = await fetch(url, {headers: {'user-agent': 'agentic-os-video-assets/1 (personal video pipeline)', ...headers}, signal: ctl.signal});
  if (!res.ok) throw new Error(`fetch ${url}: HTTP ${res.status}`);
  const out = createWriteStream(dest);
  let bytes = 0, complete = true;
  try {
    for await (const chunk of res.body) {
      if (bytes + chunk.length > capBytes) { complete = false; ctl.abort(); break; }
      bytes += chunk.length;
      if (!out.write(chunk)) await new Promise(r => out.once('drain', r));
    }
  } catch (e) { if (e.name !== 'AbortError') throw e; complete = false; }
  await new Promise(r => out.end(r));
  return {bytes, complete};
}

export function fetchExcerpt(url, {sourceIn, sourceOut, capBytes, dest}) {
  const r = spawnSync('yt-dlp', ['--no-playlist', '--download-sections', `*${sourceIn}-${sourceOut}`, '--force-keyframes-at-cuts',
    '--max-filesize', String(capBytes), '-f', 'bv*[height<=1080]+ba/b[height<=1080]', '--merge-output-format', 'mp4', '-o', dest, url],
    {encoding: 'utf8', env: {...process.env, PYTHONUTF8: '1', PYTHONIOENCODING: 'utf-8'}});
  const bytes = existsSync(dest) ? statSync(dest).size : 0;
  return {bytes, complete: r.status === 0 && bytes > 0 && bytes <= capBytes, log: (r.stderr || '').slice(-2000)};
}
```

```js
// agents-home/video/assets/lib/measure.mjs
import {spawnSync} from 'node:child_process';
export function measureMedia(file) {
  const r = spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration:stream=codec_type,width,height', '-of', 'json', file], {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`ffprobe ${file}: ${r.stderr}`);
  const j = JSON.parse(r.stdout);
  const v = (j.streams || []).find(s => s.codec_type === 'video') || {};
  const d = j.format && j.format.duration ? Number(j.format.duration) : null;
  return {duration: d, width: v.width ?? null, height: v.height ?? null, hasAudio: (j.streams || []).some(s => s.codec_type === 'audio')};
}
```

```js
// agents-home/video/assets/lib/proxy.mjs
// One silent, seek-friendly proxy per asset; sound is a separate per-use derivative (makeAudio).
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
const VIDEO_ARGS = ['-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p', '-c:v', 'libx264', '-crf', '18', '-preset', 'medium', '-g', '30', '-an'];
export const sha256File = f => createHash('sha256').update(readFileSync(f)).digest('hex');
export function makeProxy(input, out) {
  mkdirSync(dirname(out), {recursive: true});
  const r = spawnSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', '-i', input, ...VIDEO_ARGS, out], {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`proxy ${input}: ${r.stderr}`);
  return {sha256: sha256File(out), ffmpeg: VIDEO_ARGS.join(' ')};
}
export function makeAudio(input, out, fromS, toS) {
  const args = ['-ss', String(fromS), '-to', String(toS), '-vn', '-ac', '2', '-ar', '48000', '-c:a', 'pcm_s16le'];
  const r = spawnSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', '-i', input, ...args, out], {encoding: 'utf8'});
  if (r.status !== 0) throw new Error(`audio ${input}: ${r.stderr}`);
  return {sha256: sha256File(out), ffmpeg: args.join(' ')};
}
```

```js
// agents-home/video/assets/lib/cache.mjs
// Content-addressed objects shared by every film, plus an index by URL (read-only to builds).
import {copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {extname, join} from 'node:path';
import {cacheRoot} from './paths.mjs';
import {sha256File} from './proxy.mjs';
const indexPath = () => join(cacheRoot(), 'index.json');
const readIndex = () => existsSync(indexPath()) ? JSON.parse(readFileSync(indexPath(), 'utf8')) : {schema: 1, byUrl: {}};
export function storeObject(file, {url, retrieved, license = null}) {
  const sha256 = sha256File(file);
  const dir = join(cacheRoot(), 'objects');
  mkdirSync(dir, {recursive: true});
  const path = join(dir, sha256 + extname(file).toLowerCase());
  if (!existsSync(path)) copyFileSync(file, path);
  const idx = readIndex();
  idx.byUrl[url] = {sha256, path, retrieved, license};
  writeFileSync(indexPath(), JSON.stringify(idx, null, 1));
  return {sha256, path};
}
export const lookupUrl = url => readIndex().byUrl[url] || null;
```

```js
// agents-home/video/assets/lib/registry.mjs
export function registryText(rows) {
  const items = [...rows].sort((a, b) => a.id.localeCompare(b.id)).map(r => {
    const d = (r.derivatives || [])[0];
    return `  "${r.id}": { "src": "${String(d ? d.path : '').replaceAll('\\', '/')}", "kind": "${r.kind}" }`;
  });
  return `// generated by aos asset registry; do not edit\nexport const ASSETS = {\n${items.join(',\n')}\n} as const;\n`;
}
```

```js
// agents-home/video/assets/lib/credits.mjs
export function creditsBlock(rows) {
  const lines = [];
  for (const r of rows) if (r.credit && r.credit.trim() && !lines.includes(r.credit.trim())) lines.push(r.credit.trim());
  if (rows.some(r => /(^|\.)polyhaven\.com/.test(new URL(r.url || 'http://x').hostname))) lines.push('Powered by Poly Haven');
  return `## Credits\n\n${lines.map(l => `- ${l}`).join('\n')}\n`;
}
```

`lib/ledger.mjs`: `readLedger(filmDir)` returns `{schema:1, rows:[]}` when the file is missing; `addRow(filmDir, row)` refuses a duplicate `id`, writes 2-space JSON. `lib/capture.mjs`: launch `chromium` from `playwright` (resolved from the global npm prefix `~/.npm-global/node_modules/playwright`), viewport 1920x1080; `shot` = `page.screenshot({fullPage:false})`; `scroll` = record video while scrolling `seconds` with `page.mouse.wheel(0, 400)` every 500 ms; `record` = record video for `seconds`; returns the file and its size; tested in `test/capture.test.mjs` against a page served by a loopback server (skip with a reason when Playwright's browser folder is missing).

`asset.mjs`: subcommands `search|fetch|capture|proxy|registry|credits|budget`, argument parsing with `node:util` `parseArgs`; it exports `fetchAsset(filmDir, opts, io = {fetchPage})` (the `fetch` subcommand calls it; the CLI runs only when the file is the entry point) and the film's media root comes from `lib/paths.mjs` per film (the cache-hit test points both films at one shared cache and gives each its own media root, so they share objects, not a budget). `fetchAsset` flow inside `withFilmLock`: cache `lookupUrl` hit -> no charge; else `reserve(capBytes = remaining)`, fetch (excerpt when `--source-in/--source-out` given, else HTTP), `charge` the received bytes with outcome, refuse on incomplete, `storeObject`, `measureMedia`, write the rights evidence file `research/rights/<id>.json` (`{url, page, retrieved, licenseUrl, pageSha256, excerpt}` from fetching the page or license URL with the same cap rules, never the article body beyond 300 characters) and `addRow`. `budget --approve <MB>` refuses unless `--by-user` is passed (the agent passes it only after the user said so in chat).

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --no-warnings --test agents-home/video/assets/test/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add agents-home/video/assets
git commit -m "video assets: shared tool core (cache, byte budget, capped fetch, excerpt via yt-dlp, measure, silent proxy, registry, credits, capture)"
```

---

### Task 5: Search adapters behind one interface [Codex]

**Files:**
- Create: `agents-home/video/assets/adapters/{index,pexels,pixabay,openverse,wikimedia,nasa,archive,polyhaven,ambientcg,freesound}.mjs`, `test/adapters.test.mjs`, `test/fixtures/<adapter>-<kind>.json`

**Interfaces:**
- Consumes: `Candidate` (Task 4 `lib/types.mjs`).
- Produces: each module `export default {id: string, kinds: string[], needsKey: string|null, search(query: string, {kind, limit}, io: {getJson(url, headers?): Promise<any>, key: string|null}): Promise<Candidate[]>}`; `adapters/index.mjs` exports `ADAPTERS` (array) and `searchAll(query, {kind, limit, sources}, io)` that skips adapters whose `needsKey` env var (`AOS_KEY_PEXELS`...) is empty and returns `{candidates, skipped: [{id, reason}]}`.

Endpoints and field mapping (the one real call per adapter in Task 12 records the fixture; if a field differs, the fixture and mapping follow the real response):

| Adapter | Request | Map to Candidate |
|---|---|---|
| pexels clip | `GET https://api.pexels.com/videos/search?query=&per_page=` header `Authorization: <key>` | `videos[]`: id, `url` -> page, best `video_files[]` with height <= 1080 -> download/width/height, `duration`, `user.name` -> author, license `pexels`, credit `Video by <name> on Pexels` |
| pexels photo | `GET https://api.pexels.com/v1/search?query=&per_page=` | `photos[]`: `src.large2x` -> download, `photographer`, credit `Photo by <name> on Pexels` |
| pixabay clip | `GET https://pixabay.com/api/videos/?key=&q=&per_page=` | `hits[]`: `pageURL`, `videos.large` or `medium` (url, width, height, size -> bytes), `duration`, `user`; license `pixabay`; responses cached 24 h in `<cache>/http/` |
| pixabay photo | `GET https://pixabay.com/api/?key=&q=&image_type=photo` | `hits[]`: `largeImageURL`, `pageURL`, `user` |
| openverse photo | `GET https://api.openverse.org/v1/images/?q=&license_type=commercial,modification&page_size=` | `results[]`: `url`, `foreign_landing_url`, `creator`, `license`+`license_version` -> `cc-by-4.0` etc. (drop `by-sa`, `by-nd`, `by-nc*`), `attribution` -> credit |
| wikimedia photo/clip | `GET https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrsearch=<q> filetype:bitmap` (clip: `filetype:video`)`&prop=imageinfo&iiprop=url|size|mime|extmetadata` | `pages.*.imageinfo[0]`: `url`, `descriptionurl`, `extmetadata.LicenseShortName.value` normalized (`CC BY 4.0` -> `cc-by-4.0`, `Public domain` -> `pd`, `CC0` -> `cc0-1.0`, anything else -> dropped), `Artist.value` stripped of HTML |
| nasa clip/photo | `GET https://images-api.nasa.gov/search?q=&media_type=video` (or `image`) | `collection.items[]`: `data[0].nasa_id/title/center/date_created`, `href` (asset manifest: pick `~orig.mp4`/`~large.jpg`), license `pd`, credit `NASA/<center>`, candidate gets `subjects: []` for the director to fill |
| archive clip | `GET https://archive.org/advancedsearch.php?q=<q> AND mediatype:movies&fl[]=identifier&fl[]=title&fl[]=licenseurl&fl[]=rights&rows=&output=json` | `response.docs[]`; license only from `licenseurl` (publicdomain/zero -> `cc0-1.0`, publicdomain/mark -> `pd`, by/4.0 -> `cc-by-4.0`); no licenseurl -> dropped (Prelinger is not blanket PD) |
| polyhaven model/hdri/texture | `GET https://api.polyhaven.com/assets?t=models` (`hdris`, `textures`), filter by query words in name/tags/categories client-side; files `GET https://api.polyhaven.com/files/<id>` | license `cc0-1.0`, credit `Poly Haven: <name>`, download = `gltf` 1k or `hdri` 2k; header `User-Agent: agentic-os-video-assets/1` |
| ambientcg texture/hdri | `GET https://ambientcg.com/api/v2/full_json?q=&type=Material&include=downloadData&limit=` | `foundAssets[]`: `assetId`, 2K-JPG zip from `downloadFolders`, license `cc0-1.0` |
| freesound sfx | `GET https://freesound.org/apiv2/search/text/?query=&filter=license:("Creative Commons 0" OR "Attribution")&fields=id,name,username,license,previews,url,duration&token=` | `results[]`: `previews["preview-hq-mp3"]` -> download, license `cc0-1.0` or `cc-by-4.0`/`cc-by-3.0` by URL, credit `"<name>" by <username> (freesound.org)` |

- [ ] **Step 1: Failing test first (in the task file the delegate writes these before code):**

```js
// agents-home/video/assets/test/adapters.test.mjs (pattern; one block per adapter/kind with its fixture)
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {ADAPTERS, searchAll} from '../adapters/index.mjs';
const fixture = name => JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'));
const io = (name, key = 'k') => ({key, getJson: async (url, headers) => { io.last = {url, headers}; return fixture(name); }});

test('every adapter returns only allowlisted licenses and full Candidates', async () => {
  const ALLOWED = new Set(['cc0-1.0', 'pd', 'cc-by-3.0', 'cc-by-4.0', 'pexels', 'pixabay']);
  for (const a of ADAPTERS) for (const kind of a.kinds) {
    const got = await a.search('robot arm', {kind, limit: 5}, io(`${a.id}-${kind}`));
    assert.ok(got.length > 0, `${a.id} ${kind} returned nothing from its fixture`);
    for (const c of got) {
      assert.ok(ALLOWED.has(c.license), `${a.id}: ${c.license}`);
      for (const k of ['source', 'id', 'kind', 'page', 'download', 'author', 'credit']) assert.ok(c[k], `${a.id}.${k}`);
    }
  }
});

test('openverse drops share-alike and non-commercial results present in its fixture', async () => {
  const a = ADAPTERS.find(x => x.id === 'openverse');
  const got = await a.search('x', {kind: 'photo', limit: 20}, io('openverse-photo'));
  assert.ok(got.every(c => !/sa|nc|nd/.test(c.license)));
  assert.ok(fixture('openverse-photo').results.some(r => /sa|nc/.test(r.license)), 'fixture must contain a rejected row');
});

test('archive drops items without a license URL', async () => {
  const a = ADAPTERS.find(x => x.id === 'archive');
  const got = await a.search('x', {kind: 'clip', limit: 20}, io('archive-clip'));
  assert.ok(fixture('archive-clip').response.docs.some(d => !d.licenseurl));
  assert.ok(got.every(c => c.licenseUrl));
});

test('searchAll skips keyed adapters without a key and says why', async () => {
  delete process.env.AOS_KEY_PEXELS;
  const r = await searchAll('x', {kind: 'clip', limit: 1, sources: ['pexels']}, {getJson: async () => { throw new Error('must not call'); }});
  assert.deepEqual(r.skipped, [{id: 'pexels', reason: 'no key (aos secret set pexels)'}]);
});

test('the key never appears in a URL for header-auth adapters', async () => {
  const a = ADAPTERS.find(x => x.id === 'pexels');
  const i = io('pexels-clip', 'SECRET-KEY');
  await a.search('x', {kind: 'clip', limit: 1}, i);
  assert.doesNotMatch(io.last.url, /SECRET-KEY/);
});
```

Fixtures are synthetic but shaped like the documented responses (2-4 items each, including one rejected row where a filter applies); Task 12 replaces each with a trimmed real response.

- [ ] **Step 2: Delegate**

```bash
aos delegate codex --write --task tasks/codex-asset-adapters.md --verify "node --no-warnings --test agents-home/video/assets/test/adapters.test.mjs" --idle 15 --max-input 250000 --repo "$HOME/.aos/worktrees/agentic-os-video-assets"
```

(`--max-input` only once Task 8 is merged; otherwise omit.) The task file contains: the table above, the interface, the test file above verbatim, "write the tests and fixtures first and show them failing, then implement", "read only Task 4's lib/types.mjs and lib/fetch.mjs".

- [ ] **Step 3:** Review the diff, run the verify command on the host, merge, commit `video assets: search adapters (10 sources, one interface, license filters; Codex, reviewed)`.

---

### Task 6: `aos asset` wrappers [Claude]

**Files:**
- Modify: `aos.psm1` (new `#region video assets` after `Write-AosVideoPreflight`; dispatch `'asset'` next to `'video'`; usage text)
- Test: `tests/aos.Tests.ps1` (new `Describe 'aos asset'`)

**Interfaces:**
- Consumes: `asset.mjs` CLI (Task 4), secrets `pexels`, `pixabay`, `freesound`.
- Produces: `aos asset <search|fetch|capture|proxy|registry|credits|budget> ...` passing arguments through; `Invoke-AosAsset([string[]]$Arguments)`; `Get-AosAssetEnv` returns a hashtable of `AOS_KEY_*` for the secrets that exist (no warning noise for missing ones).

- [ ] **Step 1: Failing Pester tests**

```powershell
Describe 'aos asset' {
    It 'passes arguments to the shared tool and keys only through the environment' {
        Mock Get-AosSecretNames -ModuleName aos { @('pexels') }
        Mock Get-AosSecret -ModuleName aos { 'KEY-123' }
        Mock Invoke-AosProcess -ModuleName aos {
            $script:seen = @{ Exe = $Exe; Args = ($Arguments -join ' '); Env = $Environment }
            @{ Code = 0; TimedOut = $false; KillFailed = $false; Out = ''; Err = '' }
        }
        InModuleScope aos { Invoke-AosAsset @('search', 'robot arm', '--kind', 'clip') }
        $s = InModuleScope aos { $script:seen }
        $s.Exe | Should -Be 'node'
        $s.Args | Should -Match 'video[\\/]assets[\\/]asset\.mjs search'
        $s.Args | Should -Not -Match 'KEY-123'
        $s.Env['AOS_KEY_PEXELS'] | Should -Be 'KEY-123'
        $s.Env.ContainsKey('AOS_KEY_PIXABAY') | Should -BeFalse
    }
    It 'refuses budget --approve without --by-user' {
        { InModuleScope aos { Invoke-AosAsset @('budget', '--film', 'x', '--approve', '500') } } | Should -Throw '*--by-user*'
    }
}
```

- [ ] **Step 2:** Run `pwsh -NoProfile -Command "Import-Module ./aos.psm1 -Force; aos test"` -> FAIL (`Invoke-AosAsset` not found).

- [ ] **Step 3: Implement (ASCII, PS 5.1-safe)**

```powershell
#region video assets -----------------------------------------------------------------------
# aos asset: the shared Node tool in agents-home/video/assets. API keys go to the child as environment variables
# only (never arguments, files or logs); missing keys just make their adapters skip.

$script:AssetKeys = @('pexels', 'pixabay', 'freesound')

function Get-AosAssetEnv {
    $env = @{}
    $have = @(Get-AosSecretNames)
    foreach ($k in $script:AssetKeys) {
        if ($have -contains $k) {
            $v = Get-AosSecret $k
            if ($v) { $env['AOS_KEY_' + $k.ToUpperInvariant()] = $v }
        }
    }
    return $env
}

function Invoke-AosAsset([string[]]$Arguments) {
    if (-not $Arguments -or $Arguments.Count -eq 0) { throw 'usage: aos asset <search|fetch|capture|proxy|registry|credits|budget> ...' }
    if ($Arguments[0] -eq 'budget' -and ($Arguments -contains '--approve') -and -not ($Arguments -contains '--by-user')) {
        throw 'aos asset budget --approve records the user''s approval: add --by-user only after the user approved the amount'
    }
    $tool = Join-Path $script:Root 'agents-home\video\assets\asset.mjs'
    $r = Invoke-AosProcess -Exe 'node' -Arguments (@('--no-warnings', $tool) + $Arguments) -WorkingDirectory (Get-Location).Path -TimeoutSeconds 3600 -Environment (Get-AosAssetEnv)
    if ($r.Out) { Write-Host $r.Out }
    if ($r.Err) { Write-Host $r.Err }
    $global:LASTEXITCODE = $r.Code
}
#endregion
```

Dispatch: in the main `switch` add `'asset' { Invoke-AosAsset @($Rest) }`; usage line `  aos asset <search|fetch|capture|proxy|registry|credits|budget>  import real material for a film (rights ledger, budget)`.

- [ ] **Step 4:** `aos test` -> green in both shells (count +2).
- [ ] **Step 5:** Commit `aos asset: wrappers for the shared asset tool; keys only through the child environment`.

---

### Task 7: Media components and transitions [Claude]

**Files:**
- Create: `templates/video/src/lib/media/{Clip,Photo,Capture,Model,Environment,SourceTag}.tsx`, `src/lib/media/use.ts`, `src/lib/transitions/{index.ts,core.ts,Dissolve.tsx,Push.tsx,Wipe.tsx,ZoomThrough.tsx,WhipBlur.tsx,GlShader.tsx}`, `src/lib/transitions/gl/` (vendored `.glsl` with license headers + `LICENSE-gl-transitions.md`), `src/data/assets.ts` (empty registry), `src/data/asset-uses.ts` (generated alongside the registry: `USES[asset][use] = {mediaFrom, mediaTo, audio, credit, basis}`)
- Test: `templates/video/tools/checks/transitions.test.mts` (pure maths), `tools/checks/media-uses.test.mjs` (registry/uses generation), a still-render smoke in `tools/checks/pipeline.test.mjs`

**Interfaces:**
- Consumes: `ASSETS` (Task 4 registry), `USES` (generated by `aos asset registry`, Task 4 extended here), `motion.ts` curves, the grade in `look.ts`.
- Produces: `<Clip asset use [push] [pan]>`, `<Photo asset [from] [to]>`, `<Capture asset use>`, `<Model asset scale>`, `<Environment asset>`; transitions: `transitionProgress(frame, durationFrames) -> number` (soft in-out from `motion.ts`), `TRANSITIONS: Record<'dissolve'|'push'|'wipe'|'zoomThrough'|'whipBlur'|`gl:${string}`, Component<{from: ReactNode, to: ReactNode, progress: number}>>`; `style.md` gains a "Transition language" line read by nothing but reviewers.

- [ ] **Step 1: Failing tests**

```ts
// templates/video/tools/checks/transitions.test.mts
import assert from "node:assert/strict";
import { test } from "node:test";
import { transitionProgress, clipWindow } from "../../src/lib/transitions/core.ts";

test("progress is 0 at the start, 1 at the end, monotonic and soft at both ends", () => {
  const d = 24;
  const xs = Array.from({ length: d + 1 }, (_, f) => transitionProgress(f, d));
  assert.equal(xs[0], 0);
  assert.equal(xs[d], 1);
  for (let i = 1; i <= d; i++) assert.ok(xs[i] >= xs[i - 1]);
  assert.ok(xs[1] < 0.02 && 1 - xs[d - 1] < 0.02, "soft in and out (R17)");
});

test("a use maps shot frames to media seconds without trimming twice", () => {
  const w = clipWindow({ mediaFrom: 3, mediaTo: 5 }, 30);
  assert.deepEqual(w, { startFrom: 90, endAt: 150, frames: 60 });
});
```

`media-uses.test.mjs`: `usesText(rows)` (new export in `agents-home/video/assets/lib/registry.mjs`) emits `USES` with `credit` only for `fair-use`/`capture`, and `screenEntries(rows)` returns `[{texts:[credit], kind:'label', asset:id, sources:[], reviewed:false, generated:true}]` for those rows (consumed by `aos asset registry`, which merges them into `claims.json` `screen` replacing older `generated: true` entries only).

- [ ] **Step 2:** Run `node --no-warnings --test templates/video/tools/checks/transitions.test.mts templates/video/tools/checks/media-uses.test.mjs` -> FAIL.

- [ ] **Step 3: Implement**

```ts
// templates/video/src/lib/transitions/core.ts
// Transition timing shared by every transition: the calm in-out curve of motion.ts (R17), and use windows in frames.
import { SOFT } from "../motion";

export const transitionProgress = (frame: number, durationFrames: number): number => {
  if (frame <= 0) return 0;
  if (frame >= durationFrames) return 1;
  return SOFT(frame / durationFrames);
};

export const clipWindow = (use: { mediaFrom: number; mediaTo: number }, fps: number) => {
  const startFrom = Math.round(use.mediaFrom * fps);
  const endAt = Math.round(use.mediaTo * fps);
  return { startFrom, endAt, frames: endAt - startFrom };
};
```

(`SOFT` is the template's calm in-out bezier; no new curve is added.)

```tsx
// templates/video/src/lib/media/Clip.tsx
// An imported clip by asset id and use: the silent proxy trimmed in media seconds, the film grade, an optional
// calm push, and the generated source tag for fair-use and capture rows. Paths come only from the registry (R35).
import { OffthreadVideo, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { ASSETS } from "../../data/assets";
import { USES } from "../../data/asset-uses";
import { clipWindow } from "../transitions/core";
import { SourceTag } from "./SourceTag";
import { gradeFilter, type Look } from "../look";

type Props = { asset: keyof typeof ASSETS; use: string; look: Look; push?: number };

export const Clip = ({ asset, use, look, push = 0 }: Props) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const u = USES[asset][use];
  const w = clipWindow(u, fps);
  const scale = 1 + push * (frame / durationInFrames);
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", filter: gradeFilter(look) }}>
      <OffthreadVideo src={staticFile(ASSETS[asset].src)} startFrom={w.startFrom} endAt={w.endAt} muted
        style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${scale})` }} />
      {u.credit ? <SourceTag text={u.credit} /> : null}
    </div>
  );
};
```

(`staticFile(ASSETS[asset].src)` is the one form the gate accepts, and only inside `src/lib/media/` (Task 2 fixture, Task 3 rule). Add to `look.ts`: `export const gradeFilter = (look: Look): string` returning a CSS filter (contrast, saturation, sepia/hue toward the look's palette) derived from the existing `Look` fields, with a unit test in `transitions.test.mts` that two different looks give two different strings; shots pass the `Look` they already use.)

`Photo.tsx`: `<Img>` with a calm pan/zoom between `from` and `to` rectangles via `motion.ts`. `Capture.tsx`: a `Clip` inside a neutral browser frame with the URL host as a literal `text` prop resolved from the registry (screen-text covers it through the generated claim). `Model.tsx`: `useGLTF(staticFile(ASSETS[asset].src))` inside the existing `Stage.tsx` conventions. `Environment.tsx`: drei `Environment files={staticFile(ASSETS[asset].src)}` for HDRIs. Transitions render `from` and `to` layers with CSS transforms/opacity from `transitionProgress`; `GlShader.tsx` renders two frames as textures on a full-screen three.js quad with a vendored gl-transitions fragment (start with `fade`, `directionalwarp`, `crosswarp`, `luminance_melt`; each file keeps its `// License:` header; `LICENSE-gl-transitions.md` copies the repo MIT text and the BSD-3 notice).

- [ ] **Step 4:** Run the unit tests (PASS), then the pipeline smoke: in a scaffold fixture with a 2 s testsrc proxy registered as `a01`, render one still of a 60-frame composition using `<Clip asset="a01" use="u1" />` and `TRANSITIONS.dissolve` at its midpoint with `tools/still.sh`; assert the PNG exists and is not uniform (ImageMagick `identify -format %[standard-deviation]` > 0). Expected: PASS.
- [ ] **Step 5:** Commit `video template: media components (Clip, Photo, Capture, Model, Environment) and transitions (calm core, five own, four gl-transitions under MIT/BSD-3)`.

---

### Task 8: `aos delegate --max-input` [Codex]

**Files:**
- Modify: `aos.psm1` (`Start-AosProcessCore`: optional `[scriptblock]$Watch` called at most every 5 s in the idle loop with the stdout text so far; returns a non-empty string to kill with that reason; result gains `Watched`), `Invoke-AosDelegate` (`[int]$MaxInput`), the CLI option `max-input`, new `Read-AosRolloutUsage([string]$ThreadId, [long]$FromOffset)`
- Test: `tests/aos.Tests.ps1` (`Describe 'aos delegate --max-input'`)

**Interfaces:**
- `Read-AosRolloutUsage -ThreadId <id> -FromOffset <n>` -> `@{ Found = bool; Offset = long; Input = long; Cached = long; Output = long }`: finds `~/.codex/sessions/**/rollout-*-<ThreadId>.jsonl` (`Get-AosCodexHome`), reads from `FromOffset`, returns the last `token_count` `info.total_token_usage` (`input_tokens`, `cached_input_tokens`, `output_tokens`).
- Counted value: `Input - Cached` (non-cached input). Receipt gains `budget = @{ max_input = n; observed = bool; last_input = n; last_cached = n; overshoot = n }` and outcome `over-budget` with error category `over-budget` when killed.
- `Invoke-AosDelegate` refuses (before any process starts, outcome `refused`, category `task-file`) a task file without a line starting `Read only:` (the exact files to read) and a line starting `Done =` (the one command or condition that proves done).
- `ThreadId` comes from the first `{"type":"thread.started","thread_id":...}` line of the run's own stdout (exact binding, no folder guessing).

- [ ] **Step 1: Failing tests** (fake rollout under `$TestDrive\codex\sessions\2026\10\07\rollout-2026-10-07T10-00-00-thread-1.jsonl`, `Get-AosCodexHome` mocked to `$TestDrive\codex`; `Start-AosProcessCore` exercised with a real child `pwsh -NoProfile -Command` script that prints `thread.started` then sleeps and appends `token_count` lines to the fake rollout):
  - over budget: lines with non-cached 50 000 then 120 000, `-MaxInput 100000` -> process tree killed (child PID gone), receipt `outcome = 'over-budget'`, `budget.overshoot = 20000`, `budget.observed = $true`;
  - under budget: final 80 000 -> accepted, `observed = $true`;
  - no rollout file ever: run completes normally, `observed = $false`, no kill;
  - delayed rollout (appears after 6 s): still bound and counted;
  - another thread's rollout with a huge count in the same folder: ignored;
  - `-MaxInput 0` (default): the watch is not installed;
  - a task file without `Read only:` or without `Done =` is refused with category `task-file` and no process start (`Invoke-AosProcess` mock asserts zero calls).
  Existing delegate tests write task files with both lines (update their fixture text `'Write a fixture file'` to `"Write a fixture file`nRead only: none`nDone = the file exists"`).
- [ ] **Step 2:** Run `aos test` -> FAIL.
- [ ] **Step 3:** Delegate:

```bash
aos delegate codex --write --task tasks/codex-max-input.md --verify "pwsh -NoProfile -Command \"Import-Module ./aos.psm1 -Force; aos test\"" --idle 15 --timeout 60 --repo "$HOME/.aos/worktrees/agentic-os-video-assets"
```

The task file holds the interface above, the tests (Codex writes them first and shows them red), the rule "ASCII, PS 5.1-safe, no `??`/ternary/`&&`", and "read only: aos.psm1 lines 2476-2600 and 3188-3500, tests/aos.Tests.ps1 Describe 'aos delegate'". Note: Codex's sandbox has only Pester 3.4 (memory note), so Claude runs `aos test` on the host before merging.
- [ ] **Step 4:** Host verification, merge, commit `aos delegate --max-input: best-effort budget on non-cached input from the run's own rollout (thread_id bound), kills the tree, receipt records overshoot (Codex, reviewed)`.

---

### Task 9: Reference packs and pipeline text [Claude]

**Files:**
- Create: `agents-home/skills/video-references/SKILL.md`, `agents-home/video/refs/README.md`
- Modify: `templates/video/brief.md` (Sourcing section), `shots.md` (need/source columns), `rubric.md` (two criteria), `AGENTS.md` (assets commands and R35), `templates/video/_gitignore` if needed (never ignore `assets.json`/`sourcing.json`)
- Test: `tests/aos.Tests.ps1` 'Video rules format' already checks skills have frontmatter; add `It 'the template brief asks for sourcing and the shot list for need and source'` asserting the literal headings `## Sourcing`, `| need |`, `| source |`.

- [ ] **Step 1:** Failing Pester `It` (above) -> run `aos test` -> FAIL.
- [ ] **Step 2:** Write `SKILL.md`:

```markdown
---
name: video-references
description: Build or refresh a reference pack for a video's niche - 3-5 strong channels, 2 recent videos each, watched in the built-in browser without downloading, notes per beat (cut rate, b-roll share, imported material, overlays, transitions, sound). Use at the brief stage of any film, or when the user names a new niche or channel.
---

# Video references

1. Read `~/.agents/video/refs/<niche>.md` if it exists; refresh it when older than 30 days.
2. Find channels: search for the niche's most-viewed recent explainers (this year), prefer channels with consistent craft over one viral video. Note each channel's URL and subscriber/view counts with the date.
3. Watch without downloading: open each video in the built-in browser, sample frames from the page's `<video>` element onto a canvas every 3 s for the first 60 s and around one mid-video sequence; save sheets to `~/.aos/refs-cache/<niche>/` (never a repo). Decline cookie banners.
4. Write per video, per beat: shots per minute, longest hold, share of imported real material (stock, archival, news, screen captures) vs. built graphics, kinds of overlays and labels, transition types, sound (music bed, SFX, silence), how a source is credited on screen.
5. Write `~/.agents/video/refs/<niche>.md` (dated; one section per channel; a "What works" and a "What not to copy" list). The film's `refs.md` picks what this film borrows. Never copy a channel's characters, palette or signature metaphors.
6. Report what frames cannot establish (voice, pacing in motion) per rule R14.
```

- [ ] **Step 3:** Template text. `brief.md` gains:

```markdown
## Sourcing

- Reference pack: `~/.agents/video/refs/<niche>.md` (built with the video-references skill) and this film's `refs.md`.
- Fair use allowed for this channel: yes/no (sets `sourcing.json` `fairUse`).
- Acquisitions accepted per platform (sets `sourcing.json` `acquisition`; YouTube downloads are refused by default because YouTube's terms forbid them).
- Planned sources per chapter, in the order: the subject's own material, coverage excerpts, open libraries, built.
- Download budget the user approved: ___ MB (`aos asset budget --film <name> --approve <MB> --by-user`, only after the user said so).
```

`shots.md` header row becomes `| shot | line | need | source | practice | notes |` with the note "source: built, clip, photo, capture, model, lottie, mixed". `rubric.md` adds "Imported material shows this line's specific idea (a generic clip scores 0)" and "A first-time viewer recognises every object and term on screen (retro 45)". `AGENTS.md` adds a "Imported material (R35)" section listing `aos asset search|fetch|capture|proxy|registry|credits|budget`, the rule that components take asset ids only, and the human checks.
- [ ] **Step 4:** `aos test` -> green; `aos sync -DryRun` shows the new skill link for Claude.
- [ ] **Step 5:** Commit `video: reference packs skill; brief sourcing section, shot need/source, rubric criteria, template contract for imported material`.

---

### Task 10: Rules consolidation and decisions [Claude, Codex bounded review]

**Files:**
- Modify: `agents-home/video/video-rules.md`, `docs/decisions.md` (new entry on top), `aos.psm1` (`Write-AosVideoPreflight` adds a "Capacity and split" checklist line), `tests/aos.Tests.ps1`

- [ ] **Step 1: Failing tests:** in 'Video rules format' add assertions that (a) ids R01-R34 still exist exactly once, (b) the file has the stage headings `## Brief`, `## Look`, `## Structure`, `## Production`, `## QA`, `## Delivery`, `## Orchestration`, (c) R35 is `[check: assets]` and `tools/qa.sh` calls `checks/assets.mjs` (the existing wiring test enforces this once R35 says `[check: assets]`), (d) PREFLIGHT output contains `Capacity and split: aos capacity` . Run `aos test` -> FAIL.
- [ ] **Step 2:** Rewrite `video-rules.md`: group rules under the seven stage headings in id order within each; merge duplicate wording without changing ids; rewrite R03 to "No generic generated imagery: generative engines are opt-in and must pass the anti-slop gate. Imported real material (clips, photos, captures, scanned models) is allowed when it shows its line's specific idea and is graded into the design system." and R04 to "Anti-slop gate: reject generic generated or generic stock visuals that do not carry their line, AI artifacts, style drift, motion that goes nowhere." Append:
  - R35 [check: assets] the asset gate rules (spec section 3, one paragraph).
  - R36 [manual] Where two boxes meet, review three adjacent frames, not one still (retro 44).
  - R37 [manual] Reviewer briefs ask "what would a first-time viewer not recognise or not know?" and "which sentence argues with the viewer?" (retro 45).
  - R38 [manual] On OneDrive trees use `git archive <commit> | tar -x` into scratch to test old code; never `git stash -u`; git cannot delete folders there (retro 46, cleanup 2026-10-06).
  - R39 [manual] Source each shot by need: the subject's own material, then coverage excerpts, then open libraries, then built (spec section 1).
  - R40 [manual] A delegated Codex run has a token budget (`--max-input`) and a task file naming the exact files to read and the one command that proves done.
- [ ] **Step 3:** `docs/decisions.md` entry dated 2026-10-06 on top: real imported material allowed (R03/R04 rewrite), fair use within limits with acquisition as a separate decision, Codex critique adopted, reasons quoting the user. Preflight line: `Capacity and split: aos capacity; aos who; write the split (who builds what until when) in an aos note and HANDOFF.md`.
- [ ] **Step 4:** `aos test` -> green. Bounded Codex review: `codex exec --profile review -m gpt-6-astra "<read only git diff phone-orchestration-design...video-assets -- agents-home/video/video-rules.md docs/decisions.md; list contradictions with the template AGENTS.md, max 300 words>" </dev/null`; grep for "usage limit"; record the verdict in `docs/superpowers/specs/2026-10-06-video-asset-import-codex-critique.md` under a new heading; respond to each finding.
- [ ] **Step 5:** Commit `video rules: grouped by stage (ids kept), R03/R04 allow real imported material, R35-R40, decision entry, preflight capacity line`.

---

### Task 11 (optional): Lottie support [Claude, needs consent]

- [ ] **Step 1 [User]:** Ask: "Install `@remotion/lottie@4.0.529` and `lottie-web` into the shared Remotion install (`~/.aos/scratch/video-agi-race/node_modules`)? Size measured with `npm view @remotion/lottie@4.0.529 dist.unpackedSize` and `npm view lottie-web dist.unpackedSize` before asking." Proceed only on yes.
- [ ] **Step 2:** Failing test: a scaffold still with `<LottieLayer asset="l01" />` from a 1-layer fixture JSON renders a non-uniform PNG. Run -> FAIL.
- [ ] **Step 3:** `src/lib/media/Lottie.tsx` wrapping `@remotion/lottie` `Lottie` with `animationData` loaded via `staticFile(ASSETS[asset].src)` + `delayRender`; the gate (Task 3) already refuses Lottie files with external images.
- [ ] **Step 4:** Test passes; the input manifest's `dependencies/package-lock.json` changes (expected; note it in the commit).
- [ ] **Step 5:** Commit `video template: Lottie layer (@remotion/lottie 4.0.529, installed with consent)`.

---

### Task 12: End to end on a 60 s test film [Claude, needs the user]

- [ ] **Step 1 [User]:** Create the free keys and store them: run `aos secret set pexels`, `aos secret set pixabay`, `aos secret set freesound` (the user types each key; it never appears in chat). Signup pages: pexels.com/api, pixabay.com/api/docs, freesound.org/apiv2/apply.
- [ ] **Step 2 [User]:** Approve the test budget (proposal: 300 MB). Then `aos video new asset-e2e`, fill `sourcing.json` (`fairUse: true`, YouTube acquisitions refused), `aos asset budget --film asset-e2e --approve 300 --by-user`.
- [ ] **Step 3:** One real call per adapter (R08): `aos asset search "<topic word>" --kind <kind> --source <id> --json > test/fixtures/<id>-<kind>.real.json`; trim each to 3 items and replace the synthetic fixture if fields differ; re-run `node --test agents-home/video/assets/test/adapters.test.mjs`.
- [ ] **Step 4:** Fetch one asset per basis within the caps: a Pexels clip (license), a Poly Haven model (cc0), a NASA clip without people or logos (public-domain), our own render (own), a 5 s excerpt of a lab's directly hosted demo video (fair-use, `direct-file`), a 1 s scroll capture of a public product page (capture). `aos asset proxy`, `aos asset registry`, `aos asset credits >> description.md`.
- [ ] **Step 5:** Build a 60 s plan with two transitions (`dissolve`, `gl:crosswarp`), render, run QA. Expected: `asset policy checks passed`, `qa/assets.md` shows 6.0 s of 60.0 s; full QA green; review sheet frames show every imported asset graded and the source tags legible. Send the 480p preview and the report to the user (SendUserFile) and record their verdict with `aos video verdict asset-e2e "<their words>"`.

---

### Task 13: Close-out [Claude]

- [ ] **Step 1:** `anthropic-skills:consolidate-memory`: merge `video-orchestration-efficiency`, `vendor-capacity-allocation`, `ask-before-allocating-quota`, `codex-plus-limit-pacing` into one orchestration note plus links; keep `video-import-real-material`; update `MEMORY.md`.
- [ ] **Step 2:** When `aos who` shows no live claim on `alignment-now-it` and the user confirms that session is done: recycle `~/.aos/video/alignment-now/renders` (16 GB) with the same junction-safe script (`~\.aos\logs\cleanup-2026-10-06.txt` lists the method); list the 24 kept worktrees for the user's decision.
- [ ] **Step 3:** Push branch `video-assets` (ask the user first), merge into `phone-orchestration-design` after `aos test` green and both reviews recorded; `aos sync`; final `aos note` with capacity and what is next.
