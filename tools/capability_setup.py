"""Explicit pinned optional-tool setup and on-demand launch; never called by refresh."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tarfile
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import uuid
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capability_watch import load_json, locked, write_json

REPO = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = Path.home() / '.aos/tools/capabilities'
ORIGINS = {'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com',
           'codeload.github.com', 'registry.npmjs.org'}


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe_path(name):
    path = PurePosixPath(name.replace('\\', '/'))
    if path.is_absolute() or any(p in ('..', '') or ':' in p for p in path.parts):
        raise ValueError('Archive or manifest path escapes its root')
    return path


def validate_entry(entry):
    if entry['kind'] not in ('archive', 'wheel', 'npm', 'python-source'):
        raise ValueError('Unsupported installation kind')
    if not re.fullmatch(r'[A-Za-z0-9_.+-]+', entry['version']) or '..' in entry['version']:
        raise ValueError('Invalid pinned version')
    if not re.fullmatch(r'[a-f0-9]{64}', entry['sha256']):
        raise ValueError('A pinned SHA-256 is required')
    safe_path(entry['entrypoint'])
    safe_path(entry['filename'])
    origin(entry['url'])


def origin(url):
    parts = urlsplit(url)
    if (parts.scheme != 'https' or parts.hostname not in ORIGINS or parts.username or parts.password
            or parts.port not in (None, 443)):
        raise ValueError('Download origin is not permitted')


class Redirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        origin(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(url, path):
    origin(url)
    size = 0
    with build_opener(Redirect()).open(Request(url, headers={'User-Agent': 'agentic-os'}), timeout=30) as response:
        with path.open('wb') as stream:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 1024 ** 3:
                    raise ValueError('Artifact exceeds the 1 GiB download bound')
                stream.write(chunk)


def unpack(archive, target):
    target = Path(target)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as handle:
            items = handle.infolist()
            if len(items) > 100000 or sum(x.file_size for x in items) > 8 * 1024 ** 3:
                raise ValueError('Archive exceeds expansion bounds')
            for item in items:
                safe_path(item.filename)
                if stat.S_ISLNK(item.external_attr >> 16):
                    raise ValueError('Archive links are refused')
            handle.extractall(target)
    else:
        with tarfile.open(archive) as handle:
            items = handle.getmembers()
            if len(items) > 100000 or sum(x.size for x in items) > 8 * 1024 ** 3:
                raise ValueError('Archive exceeds expansion bounds')
            for item in items:
                safe_path(item.name)
                if not (item.isdir() or item.isfile()):
                    raise ValueError('Archive links and special files are refused')
            handle.extractall(target, filter='data')


def environment(runtime):
    env = {k: v for k, v in os.environ.items() if not re.search(
        r'(TOKEN|SECRET|PASSWORD|API_KEY|AUTHORIZATION|ANTHROPIC_|OPENAI_)', k, re.I)}
    profile = Path(runtime) / 'profile'
    env.update({'APPDATA': str(profile / 'roaming'), 'LOCALAPPDATA': str(profile / 'local'),
                'TEMP': str(profile / 'tmp'), 'TMP': str(profile / 'tmp'), 'PYTHONUTF8': '1',
                'AGENT_DESKTOP_HOME': str(profile / 'state'),
                'UV_CACHE_DIR': str(Path.home() / '.aos/uv/cache'),
                'npm_config_cache': str(Path.home() / '.aos/npm/cache')})
    return env


def validate_receipt(tool, entry, root, receipt):
    validate_entry(entry)
    runtime = (Path(root) / tool / entry['version']).resolve()
    executable = Path(receipt['entrypoint']).resolve()
    fingerprint = hashlib.sha256(json.dumps(entry, sort_keys=True).encode()).hexdigest()
    if (receipt.get('installed') is not True or receipt['tool'] != tool
            or receipt['version'] != entry['version'] or receipt['spec_sha256'] != fingerprint
            or receipt['artifact_sha256'] != entry['sha256'] or receipt['source'] != entry['url']
            or Path(receipt['runtime']).resolve() != runtime
            or not executable.is_relative_to(runtime)
            or executable not in [p.resolve() for p in runtime.glob(entry['entrypoint'])]
            or digest(executable) != receipt['entrypoint_sha256']):
        raise ValueError('Installed pin, location or entrypoint changed; inspect before replacing it')
    return receipt


def install(tool, entry, root, *, apply=False, fetch=download, execute=subprocess.run):
    validate_entry(entry)
    if not re.fullmatch(r'[a-z][a-z0-9-]+', tool):
        raise ValueError('Invalid tool identifier')
    root = Path(root).resolve()
    runtime = root / tool / entry['version']
    if not apply:
        return {'installed': False, 'tool': tool, 'version': entry['version'], 'target': str(runtime),
                'source': entry['url'], 'sha256': entry['sha256']}
    with locked(runtime):
        receipt_file = runtime / 'receipt.json'
        if receipt_file.exists():
            return validate_receipt(tool, entry, root, load_json(receipt_file))
        if runtime.exists():
            raise ValueError('Unreceipted installation exists; preserve and inspect it before retrying')
        cache = root / 'downloads' / entry['sha256'][:16] / entry['filename']
        cache.parent.mkdir(parents=True, exist_ok=True)
        with locked(cache):
            if not cache.exists():
                partial = Path(str(cache) + '.part')
                fetch(entry['url'], partial)
                if digest(partial) != entry['sha256']:
                    raise ValueError('Downloaded artifact does not match its pinned SHA-256')
                os.replace(partial, cache)
            elif digest(cache) != entry['sha256']:
                raise ValueError('Cached artifact changed; refusing to use it')
        stage = runtime.parent / (runtime.name + '.staging-' + uuid.uuid4().hex[:8])
        if entry['kind'] == 'archive':
            unpack(cache, stage)
            stage.rename(runtime)
        else:
            runtime.mkdir(parents=True)
            env = environment(runtime)
            for folder in ('TEMP', 'APPDATA', 'LOCALAPPDATA'):
                Path(env[folder]).mkdir(parents=True, exist_ok=True)
            if entry['kind'] == 'npm':
                npm = Path(shutil.which('npm.cmd') or shutil.which('npm') or '')
                cli = npm.parent / 'node_modules/npm/bin/npm-cli.js'
                if not cli.is_file():
                    raise ValueError('Cannot locate npm-cli.js; refusing a Windows batch shim')
                command = [shutil.which('node') or 'node', str(cli), 'install',
                           '--prefix', str(runtime), '--ignore-scripts', '--no-audit', '--no-fund', str(cache)]
                execute(command, check=True, env=env, cwd=runtime, timeout=600)
            else:
                uv = shutil.which('uv') or 'uv'
                execute([uv, 'venv', '--python', sys.executable, str(runtime / 'venv')],
                        check=True, env=env, timeout=120)
                python = runtime / 'venv/Scripts/python.exe'
                execute([uv, 'pip', 'install', '--python', str(python), str(cache)],
                        check=True, env=env, timeout=600)
        matches = list(runtime.glob(entry['entrypoint']))
        if len(matches) != 1 or not matches[0].is_file():
            raise ValueError('Pinned installation did not produce one expected entrypoint')
        receipt = {'installed': True, 'tool': tool, 'version': entry['version'],
                   'spec_sha256': hashlib.sha256(json.dumps(entry, sort_keys=True).encode()).hexdigest(),
                   'artifact_sha256': entry['sha256'],
                   'entrypoint': str(matches[0]), 'entrypoint_sha256': digest(matches[0]),
                   'runtime': str(runtime), 'source': entry['url']}
        write_json(receipt_file, receipt)
        return receipt


def launch_plan(receipt, entry, arguments, dependencies=None):
    if Path(receipt['entrypoint']).suffix.lower() in ('.bat', '.cmd'):
        raise ValueError('Direct Windows batch launch is refused; use the REA Ghidra provider')
    runtime = Path(receipt['runtime'])
    env = environment(runtime)
    values = {'home': str(Path.home()), 'runtime': str(runtime), 'repo': str(REPO)}
    values.update(dependencies or {})
    blender = sorted((Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Blender Foundation').glob('Blender */blender.exe'))
    if blender:
        values['blender'] = str(blender[-1])
    env.update({k: v.format_map(values) for k, v in entry.get('env', {}).items()})
    prefix = [shutil.which('node') or 'node'] if entry['kind'] == 'npm' else []
    return prefix + [receipt['entrypoint']] + entry.get('arguments', []) + list(arguments), env


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=DEFAULT_ROOT)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('list')
    for action in ('install', 'check', 'run'):
        p = sub.add_parser(action)
        p.add_argument('tool')
        if action == 'install': p.add_argument('--apply', action='store_true')
        if action == 'run': p.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        manifest = load_json(REPO / 'config/capability-tools.json')['tools']
        if args.action == 'list':
            print(json.dumps(manifest, indent=2))
            return 0
        if args.tool not in manifest:
            raise ValueError('Unknown prepared tool')
        entry = manifest[args.tool]
        dependencies = {}
        for name in entry.get('dependencies', []):
            dep = manifest[name]
            receipt = install(name, dep, args.root, apply=args.action == 'install' and args.apply)
            if not receipt['installed']:
                receipt_path = args.root / name / dep['version'] / 'receipt.json'
                if not receipt_path.exists():
                    if args.action != 'install': raise ValueError('Dependency is not installed: ' + name)
                    continue
                receipt = load_json(receipt_path)
            if receipt['installed']:
                validate_receipt(name, dep, args.root, receipt)
            dependencies[name] = str(Path(receipt['entrypoint']).parents[dep.get('root_parents', 2) - 1])
        if args.action == 'install':
            result = install(args.tool, entry, args.root, apply=args.apply)
        else:
            receipt_path = args.root / args.tool / entry['version'] / 'receipt.json'
            if not receipt_path.exists(): raise ValueError('Tool is not installed; use explicit install --apply')
            receipt = validate_receipt(args.tool, entry, args.root, load_json(receipt_path))
            result = receipt
            if args.action == 'run':
                command, env = launch_plan(receipt, entry, args.arguments, dependencies)
                for folder in ('TEMP', 'APPDATA', 'LOCALAPPDATA'):
                    Path(env[folder]).mkdir(parents=True, exist_ok=True)
                return subprocess.run(command, env=env, cwd=receipt['runtime'], shell=False).returncode
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print('Capability setup failed: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
