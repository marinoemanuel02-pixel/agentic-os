"""Launch explicitly installed optional tools without changing vendor settings or PATH."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def plan(name, arguments, registry, *, home=None):
    if name not in registry:
        raise ValueError('Unknown tool: ' + name)
    if name == 'watch' and any(a.split('=', 1)[0] in ('--engine', '--whisper') for a in arguments):
        raise ValueError('watch uses the local engine and existing captions; use footage for offline ASR')
    if name == 'anydoc':
        for index, argument in enumerate(arguments):
            if argument == '--ocr' and (index + 1 == len(arguments) or arguments[index + 1] != 'reject'):
                raise ValueError('Hosted OCR is not enabled in this local launcher')
            if argument.startswith('--ocr=') and argument != '--ocr=reject':
                raise ValueError('Hosted OCR is not enabled in this local launcher')
    entry = registry[name]
    values = {'home': str(home or Path.home()), 'repo': str(Path(__file__).resolve().parents[1]),
              'python': sys.executable, 'node': shutil.which('node') or 'node',
              'path': os.environ.get('PATH', '')}
    command = [part.format_map(values) for part in entry['command']]
    command += list(arguments) + entry.get('fixed_args', [])
    environment = dict(os.environ)
    environment.update({key: value.format_map(values) for key, value in entry.get('env', {}).items()})
    environment['PYTHONUTF8'] = '1'
    cwd = entry.get('cwd')
    return command, environment, cwd.format_map(values) if cwd else None


def run(name, arguments, registry):
    command, environment, cwd = plan(name, arguments, registry)
    return subprocess.run(command, env=environment, cwd=cwd, shell=False).returncode


def main():
    registry_path = Path(__file__).resolve().parents[1] / 'config' / 'stack-tools.json'
    registry = json.loads(registry_path.read_text(encoding='utf-8'))['tools']
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tool', nargs='?', default='list')
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.tool == 'list':
        for name, entry in registry.items():
            print(name + ': ' + entry['purpose'])
        return 0
    try:
        return run(args.tool, args.arguments, registry)
    except (ValueError, KeyError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
