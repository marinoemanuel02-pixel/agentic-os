"""Launch VoiceStudio with its existing verified local backend, without running setup.

The app's documented OMNIVOICE_BACKEND_CMD override bypasses stale managed-runtime
metadata; Electron still owns its spawned backend and preserves an already-ready one.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def plan(*, home=None, environment=None):
    home = Path(home or Path.home())
    root = home / '.aos/tools/stack/voicestudio'
    project = root / 'profile/runtime/project'
    python = project / '.venv/Scripts/python.exe'
    executable = root / 'app/VoiceStudio.exe'
    if not all(p.is_file() for p in (executable, python, project / 'backend/main.py')):
        raise ValueError('Existing cached VoiceStudio runtime is missing or incomplete; no installer was run')
    env = {k: v for k, v in (os.environ if environment is None else environment).items()
           if k not in ('ELECTRON_RUN_AS_NODE', 'VOICESTUDIO_SKIP_BACKEND') and not any(
               token in k.upper() for token in ('API_KEY', 'ACCESS_TOKEN', 'AUTH_TOKEN', '_PROXY'))}
    env.update(OMNIVOICE_DATA_DIR=str(root / 'data'), OMNIVOICE_CACHE_DIR=str(root / 'models'),
               HF_HOME=str(root / 'models'), HF_HUB_CACHE=str(root / 'models'),
               HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', TORCH_COMPILE_DISABLE='1',
               TEMP=str(home / '.aos/tmp'), TMP=str(home / '.aos/tmp'),
               PYTHONUTF8='1', PYTHONIOENCODING='utf-8', OMNIVOICE_PORT='3900',
               OMNIVOICE_FRONTEND_DIST=str(root / 'app/resources/frontend/dist'))
    # Absolute app-dir is necessary because the documented custom command runs
    # from the packaged resources directory, not the cached project directory.
    env['OMNIVOICE_BACKEND_CMD'] = json.dumps([str(python), '-m', 'uvicorn', 'main:app',
        '--app-dir', str(project / 'backend'), '--host', '127.0.0.1', '--port', '3900'])
    return [str(executable), '--user-data-dir=' + str(root / 'profile')], env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check the cached interpreter without opening the app')
    args = parser.parse_args()
    try:
        command, env = plan()
        Path(env['TEMP']).mkdir(parents=True, exist_ok=True)
        backend = json.loads(env['OMNIVOICE_BACKEND_CMD'])
        probe = subprocess.run([backend[0], '-c',
            'import fastapi, uvicorn, omnivoice, faster_whisper, sentencepiece, torch, torchaudio, torchvision'],
            cwd=Path(backend[0]).parents[2], env=env, capture_output=True, text=True,
            encoding='utf-8', errors='replace', timeout=180, shell=False)
        if probe.returncode:
            raise ValueError('Cached backend import check failed; no installer or model download was attempted')
        if args.check:
            print('Cached local backend imports passed; no app launched.')
            return 0
        return subprocess.run(command, env=env, shell=False).returncode
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print('VoiceStudio launch failed: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
