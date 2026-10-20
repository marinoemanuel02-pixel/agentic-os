"""Repeatable, bounded checks of the fourteen approved on-demand stack products.

Uses disposable generated inputs. No installation, account writes, model downloads or paid calls.
An incomplete receipt exits 2; correctness failures exit 1. Only an all-passed receipt exits zero.
"""
import argparse
import array
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import wave
import zipfile

REPO = Path(__file__).resolve().parents[1]
HOME = Path.home()
APPROVED = ('watch', 'anydoc', 'frontend-design', 'ui-ux', 'repomix', 'rtk', 'graphify',
            'serena', 'kdenlive', 'openmontage', 'open-design', 'voicestudio', 'composio', 'omniroute')
MARKERS = ('Verona', 'Amber', '42', 'Cobalt', '17')


class CheckFailure(Exception):
    pass


class Blocked(Exception):
    pass


class Skipped(Exception):
    pass


def select_tools(names):
    unknown = set(names) - set(APPROVED)
    if unknown:
        raise ValueError('Unknown approved tool selection: ' + ', '.join(sorted(unknown)))
    return list(dict.fromkeys(names or APPROVED))


def prepare_output(path):
    path = Path(path).expanduser().resolve()
    path.mkdir(parents=True, exist_ok=False)
    return path


def child_environment(output):
    env = {k: v for k, v in os.environ.items() if not any(s in k.upper() for s in
           ('API_KEY', 'AUTH_TOKEN', 'ACCESS_TOKEN', 'JWT_SECRET', 'ENCRYPTION_KEY', '_PROXY'))}
    env.update(PYTHONUTF8='1', PYTHONIOENCODING='utf-8', HF_HUB_OFFLINE='1',
               TEMP=str(output / 'tmp'), TMP=str(output / 'tmp'),
               UV_CACHE_DIR=str(HOME / '.aos/uv/cache'), npm_config_cache=str(HOME / '.aos/npm/cache'),
               NO_UPDATE_NOTIFIER='1')
    return env


def redacted(text):
    return re.sub(r'\b(?:sk[-_]|ck_|ak_)[A-Za-z0-9_-]{12,}', '[redacted credential]', text)


def require(condition, reason):
    if not condition:
        raise CheckFailure(reason)


def exit_status(rows):
    return 1 if any(r['status'] == 'failed' for r in rows) else 2 if any(r['status'] != 'passed' for r in rows) else 0


class Runner:
    def __init__(self, output, live=False):
        self.output, self.live = Path(output), live
        self.env = child_environment(self.output)
        (self.output / 'tmp').mkdir(exist_ok=True)

    def command(self, name, args, expected=0, timeout=90, cwd=None, env=None):
        args = [str(a) for a in args]
        started = time.monotonic()
        process = subprocess.Popen(args, cwd=cwd or self.output, env=env or self.env,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        timed = False
        try:
            out, err = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed = True
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               capture_output=True, timeout=20)
            else:
                process.kill()
            out, err = process.communicate(timeout=20)
        text = [redacted(value.decode('utf-8', 'replace')) for value in (out, err)]
        for suffix, value in zip(('stdout', 'stderr'), text):
            (self.output / (name + '.' + suffix + '.txt')).write_text(value[:2 * 1024 * 1024], encoding='utf-8')
        meta = {'exit': process.returncode, 'timeout': timed, 'seconds': round(time.monotonic() - started, 3),
                'expected_exit': expected, 'command': args, 'output_truncated': any(len(v) > 2 * 1024 * 1024 for v in text)}
        (self.output / (name + '.run.json')).write_text(json.dumps(meta, indent=2), encoding='utf-8')
        if timed:
            raise CheckFailure(name + ' timed out; owned process stopped')
        require(process.returncode == expected, name + ' returned ' + str(process.returncode) + ', expected ' + str(expected))
        return dict(meta, stdout=text[0], stderr=text[1])

    def tool(self, name, tool, arguments, **kwargs):
        return self.command(name, [sys.executable, REPO / 'tools/stack.py', tool, *arguments], **kwargs)

    def check(self, name):
        started = time.monotonic()
        try:
            evidence = CHECKS[name](self)
            require(isinstance(evidence, dict) and bool(evidence.get('scope')), 'Check supplied no assertion scope')
            row = dict(tool=name, status='passed', **evidence)
        except Skipped as error:
            row = dict(tool=name, status='skipped', reason=str(error))
        except Blocked as error:
            row = dict(tool=name, status='blocked', reason=str(error))
        except (CheckFailure, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            row = dict(tool=name, status='failed', reason=redacted(str(error)))
        row['seconds'] = round(time.monotonic() - started, 3)
        return row

    def code_fixture(self, name):
        folder = self.output / name; folder.mkdir()
        files = {'maths.py': 'def double(value):\n    return value * 2\n',
                 'main.py': 'from maths import double\ndef calculate():\n    return double(21)\n',
                 'calc.ts': 'export function triple(value: number) { return value * 3; }\n',
                 'Maths.ps1': 'function Get-Double { param($Value) return $Value * 2 }\n',
                 '.env': 'STACK_VERIFY_PRIVATE_CANARY_8197\n'}
        for file, text in files.items():
            (folder / file).write_text(text, encoding='utf-8')
        return folder

    def video_fixture(self):
        target = self.output / 'captioned.mp4'
        if target.exists():
            return target
        self.command('fixture-video', ['ffmpeg', '-nostdin', '-v', 'error', '-f', 'lavfi', '-i',
                     'testsrc2=size=320x180:rate=10', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
                     '-t', '1.2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', self.output / 'source.mp4'])
        srt = self.output / 'captions.srt'
        srt.write_text('1\n00:00:00,000 --> 00:00:01,100\nSTACK_VERIFY_CAPTION_42\n', encoding='utf-8')
        self.command('fixture-captions', ['ffmpeg', '-nostdin', '-v', 'error', '-i', self.output / 'source.mp4',
                     '-i', srt, '-map', '0', '-map', '1', '-c', 'copy', '-c:s', 'mov_text', target])
        return target


def anydoc(r):
    doc = r.output / 'fixture.docx'
    with zipfile.ZipFile(doc, 'x') as archive:
        archive.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        archive.writestr('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        archive.writestr('word/document.xml', '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Integration fixture Verona Amber 42 Cobalt 17</w:t></w:r></w:p></w:body></w:document>')
    result = r.tool('anydoc-docx', 'anydoc', [doc])
    require(all(marker in result['stdout'] for marker in MARKERS), 'DOCX lost expected fixture text')
    return {'scope': 'Generated local DOCX text conversion; complex layout and scanned OCR not established'}


def repomix(r):
    folder = r.code_fixture('repomix-code'); target = r.output / 'selected.xml'
    r.tool('repomix-export', 'repomix', [folder, '--include', '*.py,*.ts,*.ps1', '--output', target, '--quiet'])
    text = target.read_text(encoding='utf-8')
    require(all(marker in text for marker in ('double(21)', 'triple', 'Get-Double')), 'Selected code was omitted')
    require('STACK_VERIFY_PRIVATE_CANARY_8197' not in text, 'Excluded fixture canary leaked into export')
    return {'scope': 'Selected multilingual export preserves source markers and excludes synthetic .env canary'}


def rtk(r):
    result = r.tool('rtk-refusal', 'rtk', ['git', '--definitely-invalid-option'], expected=129)
    require('unknown option' in result['stdout'] + result['stderr'], 'Original Git error was lost')
    return {'scope': 'Invalid Git command preserves diagnostic and original exit 129'}


def watch(r):
    result = r.tool('watch-caption-frames', 'watch', [r.video_fixture(), '--detail', 'efficient', '--timestamps', '.5',
                    '--out-dir', r.output / 'watch'])
    require('STACK_VERIFY_CAPTION_42' in result['stdout'], 'Embedded fixture caption missing')
    paths = re.findall(r'`([^`]+\.(?:jpg|png))`', result['stdout'])
    require(paths and all(Path(p).is_file() for p in paths), 'Reported frames missing')
    require(len(paths) <= 30, 'Frame cap exceeded')
    return {'scope': 'Real local frames and embedded text captions; paths checked, visual content not human-inspected', 'frames': len(paths)}


def frontend(r):
    source = REPO / 'agents-home/skills/frontend-design/SKILL.md'
    canonical = HOME / '.agents/skills/frontend-design/SKILL.md'
    claude = HOME / '.claude/skills/frontend-design/SKILL.md'
    require(source.is_file() and canonical.is_file() and claude.is_file(), 'Shared skill link/source missing')
    normal = lambda p: p.read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    require(normal(source) == normal(canonical) == normal(claude), 'Shared frontend sources diverged')
    return {'scope': 'Shared source/link/content integration only; no aesthetic effectiveness claim',
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()}


def ui_ux(r):
    result = r.tool('ui-ux-search', 'ui-ux', ['keyboard navigation accessibility', '--domain', 'ux', '-n', '3'])
    require('keyboard' in result['stdout'].lower() and len(result['stdout']) > 200, 'Expected UX search result absent')
    return {'scope': 'Offline UX reference lookup returns relevant keyboard guidance; product design quality not measured'}


def graphify(r):
    folder = r.code_fixture('graphify-code')
    r.tool('graphify-index', 'graphify', ['update', folder, '--no-cluster'], timeout=150)
    graphs = list(folder.rglob('graph.json'))
    require(len(graphs) == 1, 'Expected one code graph')
    graph = json.loads(graphs[0].read_text(encoding='utf-8'))
    labels = {n.get('label', '').removesuffix('()') for n in graph.get('nodes', [])}
    require({'double', 'calculate'} <= labels, 'Known Python symbols missing')
    require(graph.get('input_tokens') == 0 and graph.get('output_tokens') == 0, 'Code-only token assertion failed')
    require(any(link.get('relation') == 'calls' and link.get('source_file') == 'main.py' for link in graph.get('links', [])), 'Cross-file Python call evidence missing')
    return {'scope': 'Code-only Python symbols/cross-file caller; zero reported model tokens; TS call accuracy not established'}


def open_design(r):
    folder = r.output / 'design'; folder.mkdir()
    entry = folder / 'index.html'
    entry.write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>Verification</title><h1>STACK_EXPORT_42</h1><button onclick="this.textContent=\'CHANGED\'">Try</button></html>', encoding='utf-8')
    entry.with_name('index.html.artifact.json').write_text(json.dumps({'version': 1, 'kind': 'html', 'title': 'Verification',
        'entry': 'index.html', 'renderer': 'html', 'exports': ['html'], 'supportingFiles': []}), encoding='utf-8')
    r.tool('open-design-export', 'open-design', ['export', entry, '--format', 'standalone', '--workspace', folder], cwd=folder)
    target = folder / 'exports/index.html'
    require(target.is_file() and 'STACK_EXPORT_42' in target.read_text(encoding='utf-8'), 'Standalone export missing expected content')
    return {'scope': 'Registered HTML exported with expected content; browser interaction not exercised by this check', 'artifact': str(target.relative_to(r.output))}


def kdenlive(r):
    project = r.output / 'fixture.kdenlive-cli.json'; source = r.video_fixture()
    r.tool('kdenlive-new', 'kdenlive', ['--json', 'project', 'new', '--name', 'Verification', '--width', '320', '--height', '180',
           '--fps-num', '10', '--fps-den', '1', '--output', project])
    clip = json.loads(r.tool('kdenlive-import', 'kdenlive', ['--json', '--project', project, 'bin', 'import', source, '--duration', '1.2'])['stdout'])
    track = json.loads(r.tool('kdenlive-track', 'kdenlive', ['--json', '--project', project, 'timeline', 'add-track', '--name', 'V1'])['stdout'])
    r.tool('kdenlive-clip', 'kdenlive', ['--json', '--project', project, 'timeline', 'add-clip', str(track['id']), str(clip['id']), '--out', '1.2'])
    xml = r.output / 'fixture.kdenlive'
    r.tool('kdenlive-xml', 'kdenlive', ['--json', '--project', project, 'export', 'xml', '--output', xml])
    output = r.output / 'kdenlive.mp4'
    r.tool('kdenlive-render', 'kdenlive-render', [xml, '--output', output, '--timeout', '30'], timeout=60)
    probe = json.loads(r.command('kdenlive-probe', ['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', output])['stdout'])
    require(any(s['codec_type'] == 'video' for s in probe['streams']) and .9 <= float(probe['format']['duration']) <= 1.5, 'Rendered stream/duration mismatch')
    r.command('kdenlive-decode', ['ffmpeg', '-nostdin', '-v', 'error', '-i', output, '-f', 'null', '-'])
    return {'scope': 'New harness project/import/timeline/XML/native checked-subset export and decode; editor UI/effects unverified'}


def openmontage(r):
    source = r.video_fixture(); target = r.output / 'montage.mp4'
    code = 'from tools.video.video_trimmer import VideoTrimmer; r=VideoTrimmer().execute(' + repr({
        'operation': 'cut', 'input_path': str(source), 'output_path': str(target), 'start_seconds': .2,
        'end_seconds': .8, 'codec': 'libx264'}) + '); print(r); assert r.success'
    r.command('openmontage-trim', [HOME / '.aos/venvs/openmontage/Scripts/python.exe', '-c', code],
              cwd=HOME / '.aos/tools/stack/openmontage/source')
    data = json.loads(r.command('openmontage-probe', ['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', target])['stdout'])
    require({'video', 'audio'} <= {s['codec_type'] for s in data['streams']} and abs(float(data['format']['duration']) - .6) < .2, 'Trim stream/duration mismatch')
    return {'scope': 'Local audio/video trim with checked duration; stock-provider calls/cloud generation not exercised'}


def voicestudio(r):
    # Use an already configured local backend only; never start installers or download models.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open('http://127.0.0.1:3900/health', timeout=5) as response:
            health = json.load(response)
    except (OSError, urllib.error.URLError):
        raise Blocked('Configured local VoiceStudio backend is not ready; open the shared launcher and retry') from None
    require(isinstance(health, dict), 'Invalid local health response')
    clips = []
    for language, text in [('it', 'Questa e una prova sintetica locale. Il deposito e Verona.'),
                           ('en', 'This is synthetic local speech. The depot is Verona.')]:
        body = urllib.parse.urlencode({'text': text, 'language': language, 'engine': 'supertonic3', 'effect_preset': 'raw', 'seed': 12345}).encode()
        with opener.open(urllib.request.Request('http://127.0.0.1:3900/generate', data=body,
                         headers={'Content-Type': 'application/x-www-form-urlencoded'}), timeout=120) as response:
            audio = response.read(20 * 1024 * 1024 + 1)
        require(len(audio) <= 20 * 1024 * 1024, 'Speech response exceeded size bound')
        path = r.output / ('synthetic-' + language + '.wav'); path.write_bytes(audio)
        with wave.open(str(path), 'rb') as stream:
            duration = stream.getnframes() / stream.getframerate()
            require(stream.getsampwidth() == 2, 'Expected PCM16 speech')
            samples = array.array('h', stream.readframes(stream.getnframes()))
        require(duration > 1 and max(map(abs, samples), default=0) > 100, 'Speech clip is empty/silent')
        clips.append({'language': language, 'duration': duration})
    return {'scope': 'Existing cached local engine generated decoded non-silent Italian/English clips; listening quality not judged', 'clips': clips}


def composio(r):
    if not r.live:
        raise Skipped('Live connector discovery not selected; use --live for the existing authenticated consumer route')
    data = json.loads(r.tool('composio-tools', 'composio', ['tools'])['stdout'])
    names = {t['name'] for t in data.get('tools', [])}
    require({'COMPOSIO_SEARCH_TOOLS', 'COMPOSIO_MULTI_EXECUTE_TOOL'} <= names, 'Expected consumer MCP discovery tools missing')
    return {'scope': 'Authenticated consumer MCP tool discovery only; no account writes or messages', 'tool_count': len(names)}


def omniroute(r):
    if not r.live:
        raise Skipped('Additional-provider inference not selected; use --live for one free text-worker check')
    entry = REPO / 'tools/omniroute_run.py'
    if not entry.is_file():
        raise Blocked('OmniRoute task lifecycle helper is not integrated into this checkout')
    packet, output = r.output / 'worker-packet.txt', r.output / 'worker-candidate.json'
    packet.write_text('Given only these facts: depot is Verona; there are 17 amber crates and 25 cobalt crates. '
                      'Return the depot and total crate count as JSON with keys depot and total. Do not use tools.', encoding='utf-8')
    r.command('omniroute-task', [sys.executable, entry, '--packet', packet, '--output', output], timeout=300)
    data = json.loads(output.read_text(encoding='utf-8'))
    require(data.get('complete') is True and data.get('accepted') is False, 'Worker output is incomplete or incorrectly auto-accepted')
    require(data.get('pricing_verified_zero') is True and data.get('automatic_fallback') is False, 'Free-route/fallback assertions missing')
    text = data.get('text', '').strip()
    if text.startswith('```'):
        text = re.sub(r'^```(?:json)?\s*|\s*```$', '', text)
    answer = json.loads(text)
    require(answer.get('depot') == 'Verona' and answer.get('total') == 42, 'Worker failed the supplied fact/arithmetic task')
    return {'scope': 'One actual free text worker extracts supplied facts and total; candidate remains unaccepted', 'requests': data.get('requests')}


def serena(r):
    project = r.code_fixture('serena-code'); (project / '.serena').mkdir()
    (project / '.serena/project.yml').write_text('project_name: stack-verification\nlanguage_servers:\n  - python\n  - typescript\n  - powershell\nencoding: utf-8\n', encoding='utf-8')
    script = r.output / 'serena-check.py'
    script.write_text('''import asyncio,json,os,sys
from mcp import ClientSession,StdioServerParameters
from mcp.client.stdio import stdio_client
async def main():
 params=StdioServerParameters(command=sys.argv[1],args=['start-mcp-server','--project',sys.argv[2],'--context',sys.argv[3],'--agent-interface','tools','--transport','stdio','--enable-web-dashboard','false','--enable-gui-log-window','false','--open-web-dashboard','false','--tool-timeout','120'],env=dict(os.environ))
 async with stdio_client(params) as (read,write):
  async with ClientSession(read,write) as session:
   await session.initialize()
   names={t.name for t in (await session.list_tools()).tools}
   assert names=={'get_symbols_overview','find_symbol','find_referencing_symbols','search_for_pattern','read_file','list_dir'}
   for file,symbol,body in [('main.py','calculate','double(21)'),('calc.ts','triple','value * 3'),('Maths.ps1','Get-Double','Value * 2')]:
    result=await asyncio.wait_for(session.call_tool('find_symbol',{'name_path_pattern':symbol,'relative_path':file,'include_body':True}),timeout=150)
    assert not result.is_error and body in result.model_dump_json(),file
   print('SERENA_THREE_LANGUAGES_VERIFIED')
asyncio.run(asyncio.wait_for(main(),timeout=240))
''', encoding='utf-8')
    result = r.command('serena-symbols', [HOME / '.aos/uv/tools/serena-agent/Scripts/python.exe', script,
        HOME / '.aos/uv/tools/serena-agent/Scripts/serena.exe', project, REPO / 'config/serena-readonly.yml'], timeout=260,
        env=dict(r.env, SERENA_HOME=str(HOME / '.aos/tools/stack/serena')))
    require('SERENA_THREE_LANGUAGES_VERIFIED' in result['stdout'], 'Semantic navigation assertions missing')
    return {'scope': 'Six-tool allowlist and real Python/TypeScript/PowerShell symbol bodies with cached dependencies'}


CHECKS = {'watch': watch, 'anydoc': anydoc, 'frontend-design': frontend, 'ui-ux': ui_ux, 'repomix': repomix,
          'rtk': rtk, 'graphify': graphify, 'serena': serena, 'kdenlive': kdenlive, 'openmontage': openmontage,
          'open-design': open_design, 'voicestudio': voicestudio, 'composio': composio, 'omniroute': omniroute}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New exclusive evidence directory')
    parser.add_argument('--tool', action='append', default=[], choices=APPROVED)
    parser.add_argument('--live', action='store_true', help='Allow authenticated Composio discovery, no write actions')
    args = parser.parse_args()
    try:
        selected = select_tools(args.tool)
        output = prepare_output(args.output)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr); return 2
    runner = Runner(output, args.live); rows = []
    started = datetime.now(timezone.utc).isoformat()
    identities = {str(path.relative_to(REPO)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in (Path(__file__), REPO / 'tools/stack.py', REPO / 'config/stack-tools.json')}
    for name in selected:
        row = runner.check(name); rows.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        receipt = {'started_at_utc': started, 'source_sha256': identities,
                   'selected': selected, 'live': args.live, 'results': rows,
                   'complete': len(rows) == len(selected), 'all_passed': len(rows) == len(selected) and exit_status(rows) == 0}
        (output / 'receipt.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    return exit_status(rows)


if __name__ == '__main__':
    raise SystemExit(main())
