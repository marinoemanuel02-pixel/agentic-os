"""Validated home-folder account registry and in-memory Windows secret access."""
import base64
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

PROVIDERS = {'openrouter', 'omniroute', 'gemini', 'mistral', 'cohere', 'groq'}
CAPABILITIES = {'text', 'research', 'embed', 'rerank', 'vision', 'transcribe'}
SUPPORT = {'openrouter': {'text', 'research'}, 'omniroute': {'text', 'research'},
           'gemini': {'text', 'research', 'embed', 'vision', 'transcribe'},
           'mistral': {'text', 'research'}, 'cohere': {'text', 'research', 'embed', 'rerank'},
           'groq': {'text', 'research', 'vision', 'transcribe'}}


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}', value):
        raise ValueError('Invalid identifier')
    if value.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL', *('COM' + str(n) for n in range(10)),
                                     *('LPT' + str(n) for n in range(10))}:
        raise ValueError('Reserved identifier')
    return value


def root():
    return Path.home() / '.aos/swarm'


def validate_registry(data):
    r = copy.deepcopy(data)
    if (not isinstance(r, dict) or set(r) != {'version', 'max_active', 'provider_active', 'accounts'}
            or r['version'] != 1 or not isinstance(r['accounts'], list) or len(r['accounts']) > 128):
        raise ValueError('Invalid registry schema')
    for field in ('max_active', 'provider_active'):
        if type(r[field]) is not int or not 1 <= r[field] <= 8:
            raise ValueError('Concurrency must be 1..8')
    ids = set()
    fields = {'id', 'provider', 'secret', 'quota_group', 'enabled', 'priority', 'free', 'routes', 'limits'}
    for a in r['accounts']:
        if not isinstance(a, dict) or set(a) != fields:
            raise ValueError('Unknown or missing account field')
        for field in ('id', 'secret', 'quota_group'): identifier(a[field])
        if a['id'] in ids: raise ValueError('Duplicate account ID')
        ids.add(a['id'])
        if a['provider'] not in PROVIDERS or type(a['enabled']) is not bool or type(a['priority']) is not int:
            raise ValueError('Invalid provider or account controls')
        free = a['free']
        if not isinstance(free, dict) or free.get('kind') not in ('zero_price', 'free_tier'):
            raise ValueError('Paid or unknown billing mode refused')
        if a['provider'] in ('openrouter', 'omniroute'):
            if free != {'kind': 'zero_price'}: raise ValueError('Zero-price enforcement required')
        elif (set(free) != {'kind', 'confirmed_until', 'paid_disabled', 'evidence'}
              or free['kind'] != 'free_tier' or free['paid_disabled'] is not True
              or type(free['confirmed_until']) not in (int, float)
              or not isinstance(free['evidence'], str) or not free['evidence']):
            raise ValueError('Free-tier account needs expiring billing-disabled evidence')
        if not isinstance(a['routes'], dict) or not a['routes'] or set(a['routes']) - SUPPORT[a['provider']]:
            raise ValueError('Unsupported capability')
        for capability, route in a['routes'].items():
            if (not isinstance(route, dict) or set(route) != {'model'}
                    or not isinstance(route['model'], str) or not re.fullmatch(r'[A-Za-z0-9_./:-]{1,200}', route['model'])
                    or '..' in route['model']): raise ValueError('Invalid model route')
            if a['provider'] in ('openrouter', 'omniroute') and not route['model'].endswith(':free'):
                raise ValueError('Explicit free model required')
        limits = a['limits']
        if not isinstance(limits, list) or not 1 <= len(limits) <= 16: raise ValueError('Limits required')
        seen = set()
        for limit in limits:
            if (not isinstance(limit, dict) or set(limit) != {'unit', 'seconds', 'amount'}
                    or limit['unit'] not in ('requests', 'tokens', 'audio_seconds')
                    or type(limit['seconds']) is not int or not 1 <= limit['seconds'] <= 32 * 86400
                    or type(limit['amount']) is not int or not 1 <= limit['amount'] <= 100000000):
                raise ValueError('Invalid local quota ceiling')
            pair = (limit['unit'], limit['seconds'])
            if pair in seen: raise ValueError('Duplicate quota limit')
            seen.add(pair)
        if not {'requests', 'tokens'} <= {x['unit'] for x in limits}: raise ValueError('Request and token limits required')
        if 'transcribe' in a['routes'] and 'audio_seconds' not in {x['unit'] for x in limits}:
            raise ValueError('Transcription requires audio-second quota')
    return r


def load_registry(path=None):
    return validate_registry(json.loads(Path(path or root() / 'accounts.json').read_text(encoding='utf-8-sig')))


def admitted(a):
    return a['enabled'] and (a['free']['kind'] == 'zero_price' or a['free']['confirmed_until'] > time.time())


SECRET_SCRIPT = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$module = Import-Module (Join-Path $env:AOS_POOL_REPO 'aos.psm1') -Force -PassThru -DisableNameChecking
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
& $module { param($r)
    if ($r.operation -eq 'read') {
        $value = Get-AosSecret -Name $r.name
        if ([string]::IsNullOrWhiteSpace($value)) { throw 'Secret unavailable' }
        [Console]::Out.Write((ConvertTo-Json -InputObject @{value=$value} -Compress))
    } elseif ($r.operation -eq 'store-new') {
        if (@(Get-AosSecretNames) -contains $r.name) { throw 'Secret already exists' }
        $value = ConvertTo-SecureString $r.value -AsPlainText -Force
        if (-not (Set-AosSecret -Name $r.name -Value $value)) { throw 'Store failed' }
        [Console]::Out.Write('{}')
    } else { throw 'Unknown operation' }
} $request
'''


def secret(name, *, store=None):
    identifier(name)
    env = dict(os.environ, AOS_POOL_REPO=str(Path(__file__).resolve().parents[1]))
    script = base64.b64encode(SECRET_SCRIPT.encode('utf-16-le')).decode('ascii')
    request = {'operation': 'read' if store is None else 'store-new', 'name': name}
    if store is not None: request['value'] = store
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive',
                             '-EncodedCommand', script], input=json.dumps(request), env=env,
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
    if result.returncode: raise ValueError('Encrypted secret operation failed; details suppressed')
    try:
        value = json.loads(result.stdout).get('value', '')
        if store is None and (not value or any(ord(c) < 33 or ord(c) > 126 for c in value)):
            raise ValueError()
        return value
    except (ValueError, TypeError, AttributeError):
        raise ValueError('Invalid encrypted secret response; contents suppressed') from None
