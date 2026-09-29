# Places: every repo and knowledge base known to every agent, and an inbox for the phone

Date: 2026-09-29. Status: design approved in conversation; this spec awaits the user's review.

## Where this fits

On 2026-09-29, after the phone setup (Paseo, Pi on the local model, the aos plugin) worked, the user
asked to complete the harness: the three models (Claude, Codex, the local model) working together with
better tooling; a video editing and production suite (animated explainers, short social clips, editing
their own footage, AI-generated scenes: all four); pointing the harness at multiple local repos; and
creating or saving files on the go into an inbox or knowledge bases. That became four sub-projects
(multiple repos and capture merged into Places), each with its own spec, plan and build, in the order the
user chose:

1. **Places** (this spec): one list of repos and knowledge bases known to every agent and the phone, and
   capture into a global inbox.
2. **Orchestration**: Claude plans and delegates to Codex and the local model, in parallel, with reviews.
3. **Shared tooling**: the Docker MCP tool gateway (plan `docs/superpowers/plans/2026-09-29-tool-gateway.md`)
   plus curated plugins and skills.
4. **Video suite**: script, voice, animation, edit, export, run by agents (all four kinds of video).

## Goal and success criteria

The user can open any of their repos and knowledge bases from the phone with Claude, Codex or Pi, and
can save a thought, a link, a photo or a file from the phone without starting an agent; later an agent
files the inbox into the right vault, and only after the user confirms.

1. `aos sync` makes every existing place appear as a Paseo project on the phone; a second run changes
   nothing.
2. A note saved from the agentic-os panel on the phone lands in `Desktop\Inbox` within seconds, with no
   model call.
3. In a Pi session, "file my inbox" proposes a destination for each item, waits for the user's OK,
   moves the confirmed items and logs each move; nothing in a vault changes without that OK.

## What the user said, and what was assumed

- Said: one **global** Inbox (not one per vault); capture approach **A** (a panel for instant capture,
  agents for saving and filing, OneDrive's share for photos and files); the places list and sync as
  presented; failure handling and tests as presented.
- Found on the PC (2026-09-29): git repos `agentic-os` and `1-Projects\nar-tools`; Obsidian vaults
  `duda15` (diario generale, immagini, link, trascrizioni audio) and `tala` (diario generale, Inglese,
  Master log, Metacognizione, Mine recordings, Progetto tala, Test ai, WE CLEAN); plain folders
  `meta-cognizione`, `weclean`, `file audio`, `useful logs`. No inbox folder exists yet.
- Assumed, to verify during the build: Claude Code and Codex, started by Paseo in a folder they have not
  seen, may ask to trust it once.

## Design

### 1. The places list

`config/places.json` in agentic-os lists the places. Paths use placeholders resolved on this PC at run
time (`{{desktop}}` = the user's Desktop folder, OneDrive-redirected; `{{projects}}` = `Desktop\1-Projects`
or `$env:AOS_PROJECTS`; `{{home}}`), so the repo holds no absolute paths.

```json
{
  "places": [
    { "name": "agentic-os",      "kind": "repo",   "path": "{{desktop}}\\agentic-os" },
    { "name": "nar-tools",       "kind": "repo",   "path": "{{projects}}\\nar-tools" },
    { "name": "tala",            "kind": "vault",  "path": "{{desktop}}\\tala" },
    { "name": "duda15",          "kind": "vault",  "path": "{{desktop}}\\duda15" },
    { "name": "meta-cognizione", "kind": "folder", "path": "{{desktop}}\\meta-cognizione" },
    { "name": "inbox",           "kind": "inbox",  "path": "{{desktop}}\\Inbox" }
  ]
}
```

- Kinds: `repo` (has `.git`), `vault` (has `.obsidian`), `folder` (anything else), `inbox` (exactly one).
- `aos sync` (`Sync-AosPlaces`, in the brain layer):
  - creates the inbox folder if it is missing (the only folder aos ever creates);
  - registers every place whose folder exists as a Paseo project (`paseo project create <path>`),
    skipping those `paseo project ls --json` already lists; Paseo missing -> skipped with an info line;
  - writes the resolved list to `~\.aos\places.json` (name, kind, path, exists), the file other tools
    read (the plugin, the inbox skill), like `~\.aos\local.json`;
  - warns about places whose folder is missing, and creates nothing for them.
- `aos place ls [--json]` prints the list with each place's state; `aos place add <folder> [--name <n>]
  [--kind <k>]` detects the kind when not given, appends to `config/places.json` (the user commits it),
  and syncs; `aos new <name>` adds the new project as a `repo` place.
- `aos status` gets a Places section: each place ok / missing, and whether Paseo knows it.
- Left out for now: `weclean`, `file audio`, `useful logs` (`aos place add` brings any of them in).

### 2. Capture and filing

**The Inbox panel** (a new section of the agentic-os Paseo plugin, `nar-tools/paseo-plugin`):

- A text box (the phone keyboard's microphone dictates, Italian included), an optional link field, and
  Save. The panel then lists the ten newest inbox items so the user sees the capture landed.
- RPC `inbox.save`, strict input `{ text: string (at most 100,000 characters), link?: http(s) URL (at
  most 2,048 characters) }`, at least one of them non-empty. The phone never sends a path or a file name.
- The PC writes one Markdown note per capture into the inbox path from `~\.aos\places.json`:
  - name `YYYY-MM-DD HHmm <slug>.md` in local time; slug = the first words of the text or the link's
    host, reduced to letters, digits, spaces, `-` and `_`, at most 50 characters, never a Windows
    reserved name; a clash gets ` (2)`, ` (3)`, and so on; never an overwrite;
  - content: a small YAML header, then the text:

    ```markdown
    ---
    captured: 2026-09-29T14:05:12+02:00
    source: phone
    type: note        # or: link
    link: https://...  # links only
    ---
    <text>
    ```
  - UTF-8 without BOM.
- RPC `inbox.recent` returns the newest ten `.md` names and their capture times, read from the inbox
  folder only (`_filed.md` excluded).

**Photos and files**: from any Android app, Share -> OneDrive -> `Desktop/Inbox`; OneDrive syncs them to
the PC. Nothing to build; the README documents it.

**The inbox skill** (`agents-home/skills/inbox/SKILL.md`, the shared skills folder that Claude Code,
Codex and Pi all read; Pi reads `~/.agents/skills`):

- "save this to the inbox": writes the same note format.
- "file my inbox":
  1. read `~\.aos\places.json` for the inbox and the vaults;
  2. for each inbox item (notes, photos, files; not `_filed.md`) propose a vault and a folder in it; when
     the choice is among known folders and the `nar_choose` tool is available (Claude Code, Codex), use
     it to score the folders; otherwise judge;
  3. show the whole proposal as a list and wait for the user's explicit confirmation (all, some, or
     changed destinations);
  4. move only the confirmed items; never overwrite (suffix instead); never edit or delete a vault note;
  5. append one line per move to `Inbox\_filed.md` (date, item, destination).
- The skill's description is short: Pi lists every skill's description in its 16K prompt.

### 3. Failure handling

- A place whose folder disappeared (a renamed vault): `aos sync` and `aos status` warn; nothing is created
  in its place; the plugin and the skill skip it.
- The PC or Paseo is off: the panel cannot reach the PC, says the note was not saved, and keeps the text
  in the box.
- `~\.aos\places.json` missing (aos not synced yet): the panel says to run `aos sync`; nothing is written.
- A name clash: numbered suffix. A destination the skill cannot decide: it asks.
- OneDrive not yet synced: captures are written on the PC's disk first; OneDrive uploads them later.

## Security

- The panel writes only inside the inbox folder, only new files, only text; the file name is built on
  the PC; the input is size-limited and schema-checked (the same boundary as the existing feedback RPC).
- The inbox skill moves files into vaults only after explicit confirmation, never deletes, never edits
  existing notes, and keeps a log.
- `config/places.json` names folders only; no note content ever enters the repo.

## Testing

- Pester (`tests/aos.Tests.ps1`): placeholder resolution including `{{desktop}}`; `Sync-AosPlaces`
  creates only the inbox, registers only missing Paseo projects, writes `~\.aos\places.json`, warns on a
  missing folder, changes nothing on a second run, and changes nothing in DryRun; `aos place add` kind
  detection and duplicate refusal; `aos new` adds its project; `aos status` lines.
- Vitest (`paseo-plugin/server`): `inbox.save` input schema (empty, oversized, non-http links, extra
  fields refused); the file name built on the PC (slug rules, reserved names, clash suffix, no
  overwrite); header and UTF-8 content (Italian text and emoji); `inbox.recent` reads only the inbox
  folder; a missing `places.json` refuses to write.
- The skill: its frontmatter is valid and it is listed by `pi` (skills discovery) and by Claude Code.
- Live, with the user: a note saved from the phone lands in `Desktop\Inbox`; in a Pi session on the
  phone, "file my inbox" proposes, waits, moves one confirmed item and logs it.

## Out of scope here

Orchestration, the tool gateway and the video suite (their own specs); editing or reorganising the
vaults' existing notes; Obsidian mobile sync (the vaults stay on the PC and OneDrive); uploading
photos through the panel (OneDrive's share covers it).
