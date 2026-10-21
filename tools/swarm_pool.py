"""Shared bounded API workers: direct tasks, queue, verification and contract bridge."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import wave

from swarm_config import CAPABILITIES, identifier, load_registry, root, secret, validate_registry
from swarm_state import State, Unavailable, canonical, digest
import swarm_providers as providers


def validate_packet(value, registry, *, managed_contract=False):
    p = json.loads(canonical(value))
    allowed = {'id', 'capability', 'prompt', 'cloud_allowed', 'depends_on', 'account', 'max_tokens',
               'max_attempts', 'texts', 'input_type', 'documents', 'query', 'sources', 'mime_type',
               'image_base64', 'audio_base64', 'audio_seconds', 'language', 'contract', 'image_file', 'audio_file'}
    if not isinstance(p, dict) or set(p) - allowed: raise ValueError('Unknown task field; tool access refused')
    if 'contract' in p:
        if not managed_contract: raise ValueError('Contract supervision is host-only metadata')
        c = p['contract']
        if (not isinstance(c, dict) or set(c) != {'id','repo','run','run_path','packet','owner_session','timeout_seconds'}
                or type(c['timeout_seconds']) is not int or not 60 <= c['timeout_seconds'] <= 300):
            raise ValueError('Invalid host contract metadata')
    identifier(p.get('id')); cap = p.get('capability')
    if cap not in CAPABILITIES or p.get('cloud_allowed') is not True: raise ValueError('Capability and cloud permission required')
    if (type(p.get('max_tokens', 1024)) is not int or not 16 <= p.get('max_tokens', 1024) <= 2048
            or type(p.get('max_attempts', 2)) is not int or not 1 <= p.get('max_attempts', 2) <= 3):
        raise ValueError('Task output/attempt budget exceeded')
    deps = p.get('depends_on', [])
    if not isinstance(deps, list) or len(deps) > 16 or len(set(deps)) != len(deps): raise ValueError('Invalid dependencies')
    for dep in deps: identifier(dep)
    if p.get('account'):
        identifier(p['account'])
        if not any(a['id'] == p['account'] and cap in a['routes'] for a in registry['accounts']):
            raise ValueError('Unknown account/capability')
    if cap == 'embed':
        if not p.get('account'): raise ValueError('Embedding requires one account/model space; no cross-model failover')
        if p.get('input_type') not in ('search_document', 'search_query'): raise ValueError('Embedding input type required')
    for field in ('texts', 'documents'):
        if field in p and (not isinstance(p[field], list) or not 1 <= len(p[field]) <= 32
                          or any(not isinstance(x, str) or not x.strip() for x in p[field])):
            raise ValueError('Supply 1..32 nonempty texts')
    if cap == 'embed' and 'texts' not in p: raise ValueError('Embedding texts required')
    if cap == 'rerank' and ('documents' not in p or not isinstance(p.get('query'), str) or not p['query'].strip()):
        raise ValueError('Reranking needs documents and query')
    if cap in ('text', 'research', 'vision') and (not isinstance(p.get('prompt'), str) or not p['prompt'].strip()):
        raise ValueError('Task prompt required')
    if cap == 'research':
        sources = p.get('sources')
        if not isinstance(sources, list) or not 1 <= len(sources) <= 16: raise ValueError('Supplied sources required')
        ids = set()
        for s in sources:
            if (not isinstance(s, dict) or set(s) != {'id', 'url', 'text'} or not isinstance(s['text'], str)
                    or not s['text'].strip() or not isinstance(s['url'], str) or not s['url'].startswith('https://')):
                raise ValueError('Invalid supplied source')
            identifier(s['id'])
            if s['id'] in ids: raise ValueError('Duplicate source ID')
            ids.add(s['id'])
    if cap in ('vision', 'transcribe'):
        field = 'image_base64' if cap == 'vision' else 'audio_base64'
        local = 'image_file' if cap == 'vision' else 'audio_file'
        if local in p:
            if field in p: raise ValueError('Choose media file or inline bytes')
            with Path(p.pop(local)).open('rb') as handle: raw = handle.read(10 * 1024 * 1024 + 1)
            if len(raw) > 10 * 1024 * 1024: raise ValueError('Media size exceeded')
            p[field] = base64.b64encode(raw).decode('ascii')
            if cap == 'vision': p.setdefault('mime_type', 'image/png' if raw.startswith(b'\x89PNG') else 'image/jpeg')
        try: data = base64.b64decode(p[field], validate=True)
        except (ValueError, KeyError, TypeError): raise ValueError('Media bytes required') from None
        if not data or len(data) > (2 * 1024 * 1024 if cap == 'vision' else 10 * 1024 * 1024):
            raise ValueError('Media size exceeded')
        if cap == 'vision':
            kind = p.get('mime_type')
            if not ((kind == 'image/png' and data.startswith(b'\x89PNG\r\n\x1a\n'))
                    or (kind == 'image/jpeg' and data.startswith(b'\xff\xd8\xff'))):
                raise ValueError('Only local PNG/JPEG bytes accepted')
        else:
            try:
                with wave.open(io.BytesIO(data)) as audio:
                    seconds = audio.getnframes() / audio.getframerate()
                    if audio.getnchannels() not in (1, 2) or audio.getsampwidth() != 2: raise ValueError()
                if not 0 < seconds <= 120: raise ValueError()
                p['audio_seconds'] = math.ceil(seconds)
            except (ValueError, wave.Error, EOFError): raise ValueError('Use PCM16 WAV up to 120 seconds') from None
            if p.get('language') and not re.fullmatch('[a-z]{2}', p['language']): raise ValueError('Invalid language')
    if 'image_file' in p or 'audio_file' in p: raise ValueError('Media file does not match capability')
    small = {k: v for k, v in p.items() if k not in ('image_base64', 'audio_base64')}
    if len(canonical(small).encode()) > 32 * 1024: raise ValueError('Text packet exceeds 32 KiB')
    return p


class Pool:
    def __init__(self, registry, state, *, secret=secret, check=providers.check_route, call=providers.call):
        self.registry, self.state = validate_registry(registry), state
        self.secret, self.check, self.call = secret, check, call

    def submit(self, packet, *, managed_contract=False):
        return self.state.submit(validate_packet(packet, self.registry, managed_contract=managed_contract))

    def _cancelled(self, packet):
        if self.state.cancelled(packet['id']): return True
        if packet.get('contract'):
            path = Path(packet['contract']['run_path'])
            try: cancelled = json.loads(path.read_text(encoding='utf-8-sig')).get('cancel_requested') is True
            except (OSError, ValueError): raise ValueError('Host supervision state unavailable') from None
            if cancelled: self.state.cancel(packet['id']); return True
        return False

    def run_claimed(self, packet, run, first_account=None):
        providers.DEADLINE.set(time.monotonic() + (packet.get('contract', {}).get('timeout_seconds', 300)))
        errors = []; count = 0
        text = canonical({k: v for k, v in packet.items() if k not in ('image_base64', 'audio_base64')})
        units = {'requests': 1, 'tokens': len(text.encode()) + packet.get('max_tokens', 1024)}
        if packet['capability'] == 'vision': units['tokens'] += 8192
        if packet['capability'] == 'transcribe':
            units.update(audio_seconds=packet['audio_seconds'], tokens=packet['audio_seconds'] * 32 + 1024)
        accounts = self.state.eligible(self.registry, packet['capability'])
        accounts.sort(key=lambda a: a['id'] != first_account)
        for a in accounts:
            if packet.get('account') and packet['account'] != a['id']: continue
            if count >= packet.get('max_attempts', 2) or self._cancelled(packet): break
            attempt = None
            try:
                key = self.secret(a['secret'])
                self.check(a, packet, key)
                if self._cancelled(packet): break
                attempt = self.state.reserve(self.registry, a, key, units, task=packet['id'], run=run)
                count += 1
                result = self.call(a, packet, key)
                self.state.finish(attempt, 'ok'); attempt = None
                candidate = dict(result, accepted=False, task_id=packet['id'], run_id=run,
                                 worker_kind='api-pool', account=a['id'], provider=a['provider'],
                                 model=a['routes'][packet['capability']]['model'],
                                 packet_sha256=digest(packet), attempts=count,
                                 free_admission=a['free']['kind'])
                if a['provider'] in ('openrouter', 'omniroute'):
                    candidate.update(pricing_verified_zero=True, automatic_fallback=False, requests=count)
                self._cancelled(packet)
                self.state.complete(packet['id'], run, candidate)
                return
            except providers.ProviderError as error:
                if attempt: self.state.finish(attempt, error.kind, retry_after=error.retry_after)
                errors.append(':'.join(str(x) for x in (error.kind, error.http_status, error.reason) if x is not None))
            except Unavailable: errors.append('no_capacity')
            except (ValueError, OSError, subprocess.SubprocessError):
                if attempt: self.state.finish(attempt, 'local_failure', retry_after=30)
                errors.append('local_failure')
        self.state.complete(packet['id'], run, error=','.join(errors) or 'no_admitted_route')

    def drain(self, *, only=None, workers=None):
        n = workers or self.registry['max_active']
        if type(n) is not int or not 1 <= n <= self.registry['max_active']: raise ValueError('Worker count exceeds configured admission')
        def work():
            while True:
                claim = self.state.claim(only, self.registry)
                if claim is None: return
                self.run_claimed(*claim)
                if only: return
        with ThreadPoolExecutor(max_workers=n) as executor:
            list(executor.map(lambda _: work(), range(n)))


def save_new(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='utf-8') as handle: handle.write(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n')


def export_candidate(state, task_id, path):
    row = state.task(task_id)
    if row['status'] not in ('candidate', 'accepted') or not row['candidate']: raise ValueError('No complete candidate')
    save_new(path, row['candidate'])
    return row


def verify_candidate(state, task_id, argv, *, cwd=None, artifacts=()):
    if not isinstance(argv, list) or not argv or any(not isinstance(x, str) or not x for x in argv):
        raise ValueError('Verifier must be an explicit nonempty argument array')
    row = state.task(task_id)
    if row['status'] != 'candidate': raise ValueError('Task has no unaccepted candidate')
    # Verify dependency evidence before executing even a host command.
    with state.db() as db: state._inputs(db, row['packet'])
    with tempfile.TemporaryDirectory(prefix='verify-', dir=state.path.parent) as temp:
        path = Path(temp) / 'candidate.json'; save_new(path, row['candidate'])
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        command = [x.replace('{candidate}', str(path)) for x in argv]
        result = subprocess.run(command, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120, shell=False)
        if result.returncode != 0 or hashlib.sha256(path.read_bytes()).hexdigest() != before:
            raise ValueError('Host verifier failed or modified its candidate')
        manifest = []
        for item in artifacts:
            p = Path(item).resolve(strict=True)
            if not p.is_file(): raise ValueError('Host artifact missing')
            manifest.append({'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
        receipt = {'exit_code': 0, 'argv': argv, 'artifacts': manifest,
                   'candidate_sha256': row['candidate_sha256'], 'verified_at': time.time()}
        state.accept(task_id, row['candidate_sha256'], receipt)
    return receipt


def bridge(action, payload):
    exe = shutil.which('pwsh') or 'powershell'
    result = subprocess.run([exe, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
        str(Path(__file__).with_name('swarm_contract.ps1')), action], input=json.dumps(payload),
        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=150)
    if result.returncode: raise ValueError('Native task bridge failed; inspect task state, no provider details logged')
    try: return json.loads(result.stdout)
    except ValueError: raise ValueError('Invalid task bridge response') from None


def process_stopped(pid):
    if type(pid) is not int or pid <= 0: return False
    if os.name != 'nt':
        try: os.kill(pid, 0); return False
        except ProcessLookupError: return True
        except OSError: return False
    script = ("$ErrorActionPreference='Stop'; try { $p=Get-Process -Id ([int]$env:AOS_POOL_OWNER_PID) "
              "-ErrorAction SilentlyContinue; if ($p) {exit 0}; exit 1 } catch {exit 2}")
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive', '-Command', script],
                            env=dict(os.environ, AOS_POOL_OWNER_PID=str(pid)), capture_output=True, timeout=15)
    return result.returncode == 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', type=Path)
    parser.add_argument('--state', type=Path)
    sub = parser.add_subparsers(dest='action', required=True)
    for action in ('task', 'submit'):
        p = sub.add_parser(action); p.add_argument('--packet', required=True, type=Path)
        p.add_argument('--output', type=Path, required=action == 'task')
    p = sub.add_parser('drain'); p.add_argument('--workers', type=int)
    for action in ('status', 'cancel', 'export'):
        p = sub.add_parser(action); p.add_argument('id');
        if action == 'export': p.add_argument('--output', required=True, type=Path)
    p = sub.add_parser('verify'); p.add_argument('id'); p.add_argument('--argv', required=True, help='JSON argument array; use {candidate}')
    p.add_argument('--cwd', type=Path); p.add_argument('--artifact', action='append', default=[])
    p = sub.add_parser('contract'); p.add_argument('id'); p.add_argument('--repo', required=True, type=Path)
    p.add_argument('--account'); p.add_argument('--cloud-allowed', action='store_true', required=True)
    p.add_argument('--owner-session', required=True, help='Existing host checkout claim session')
    p = sub.add_parser('reconcile'); p.add_argument('run'); p.add_argument('--confirmed-stopped', required=True, action='store_true')
    sub.add_parser('list'); sub.add_parser('attempts'); sub.add_parser('accounts')
    args = parser.parse_args()
    try:
        r = load_registry(args.registry); state = State(args.state or root() / 'state.sqlite'); pool = Pool(r, state)
        if args.action in ('task', 'submit'):
            if args.output and args.output.exists(): raise ValueError('Output already exists')
            if args.packet.stat().st_size > 16 * 1024 * 1024: raise ValueError('Packet file too large')
            name = pool.submit(json.loads(args.packet.read_text(encoding='utf-8-sig')))
            if args.action == 'task': pool.drain(only=name); export_candidate(state, name, args.output)
            print(json.dumps({'id': name, 'status': state.task(name)['status']}))
        elif args.action == 'drain': pool.drain(workers=args.workers); print(json.dumps(state.tasks()))
        elif args.action == 'status':
            row = state.task(args.id)
            row['packet'] = {k: v for k, v in row['packet'].items() if k in
                             ('id', 'capability', 'account', 'depends_on', 'max_attempts', 'max_tokens', 'cloud_allowed')}
            if row['candidate']:
                row['candidate'] = {k: v for k, v in row['candidate'].items() if k not in
                                    ('text', 'vectors', 'segments', 'claims', 'ranking')}
            print(json.dumps(row, indent=2))
        elif args.action == 'cancel': state.cancel(args.id); print(json.dumps({'cancel_requested': True, 'id': args.id}))
        elif args.action == 'export': export_candidate(state, args.id, args.output)
        elif args.action == 'verify': print(json.dumps(verify_candidate(state, args.id, json.loads(args.argv), cwd=args.cwd, artifacts=args.artifact)))
        elif args.action == 'list': print(json.dumps(state.tasks(), indent=2))
        elif args.action == 'attempts': print(json.dumps(state.attempts(), indent=2))
        elif args.action == 'reconcile':
            state.reconcile(args.run, stopped=process_stopped)
            print(json.dumps({'run': args.run, 'reconciled': True, 'charged_attempts_preserved': True,
                              'native_contract': 'inspect host task if this was a registered contract'}))
        elif args.action == 'accounts':
            from swarm_config import admitted
            print(json.dumps([{'id': a['id'], 'provider': a['provider'], 'admitted': admitted(a),
                               'capabilities': list(a['routes']), 'quota_group': a['quota_group']} for a in r['accounts']], indent=2))
        elif args.action == 'contract':
            data = bridge('prepare', {'id': args.id, 'repo': str(args.repo.resolve()),
                                      'owner_session': args.owner_session, 'process_id': os.getpid()})
            p = {'id': data['run'], 'capability': 'text', 'prompt': data['packet'], 'cloud_allowed': True,
                 'contract': data}
            if args.account: p['account'] = args.account
            try:
                name = pool.submit(p, managed_contract=True); pool.drain(only=name)
                row = state.task(name)
                if row['status'] != 'candidate': raise ValueError('API contract has no complete candidate')
                candidate_path = state.path.parent / 'candidates' / (name + '.json')
                export_candidate(state, name, candidate_path)
                # The declared verifier is host configuration, never model output.
                done = bridge('verify', dict(data, candidate=str(candidate_path), candidate_sha256=row['candidate_sha256'],
                                             candidate_file_sha256=hashlib.sha256(candidate_path.read_bytes()).hexdigest()))
                state.accept(name, row['candidate_sha256'], done['verify'])
                print(json.dumps(done))
            except BaseException:
                bridge('fail', data)
                raise
        return 0
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError):
        print('Swarm operation failed. Inspect task/attempt status and account readiness. Provider bodies and credentials suppressed.', file=sys.stderr)
        return 2


if __name__ == '__main__': raise SystemExit(main())
