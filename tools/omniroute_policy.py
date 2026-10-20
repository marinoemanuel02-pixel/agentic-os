"""Keep the restricted gateway worker credential hashed at rest and encrypted for use."""
import argparse
import base64
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import sqlite3
import subprocess
import sys
import uuid

SECRET_SCRIPT = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
if ($env:AOS_WORKER_OPERATION -eq 'backup') {
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String([Console]::In.ReadToEnd())
    $cipher = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $stream = [System.IO.File]::Open($env:AOS_WORKER_BACKUP, [System.IO.FileMode]::CreateNew)
    try { $stream.Write($cipher, 0, $cipher.Length) } finally { $stream.Dispose() }
    exit 0
}
$modulePath = Join-Path $env:AOS_WORKER_REPO 'aos.psm1'
Import-Module $modulePath -Force -WarningAction SilentlyContinue
if ($env:AOS_WORKER_OPERATION -eq 'read') {
    $value = aos secret get omniroute-worker-key
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'Worker key unavailable' }
    [Console]::Out.Write($value)
} elseif ($env:AOS_WORKER_OPERATION -eq 'write') {
    $plain = [Console]::In.ReadToEnd()
    $secure = ConvertTo-SecureString $plain -AsPlainText -Force
    $module = @(Get-Module aos | Where-Object { $_.Path -eq $modulePath })[0]
    & $module { param($value)
        if (-not (Set-AosSecret -Name 'omniroute-worker-key' -Value $value)) { throw 'Store failed' }
    } $secure
} else { throw 'Unknown credential operation' }
'''


def secret_call(operation, value='', target=None):
    env = dict(os.environ, AOS_WORKER_OPERATION=operation,
               AOS_WORKER_REPO=str(Path(__file__).resolve().parents[1]), AOS_WORKER_BACKUP=str(target or ''))
    script = base64.b64encode(SECRET_SCRIPT.encode('utf-16-le')).decode('ascii')
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive',
                             '-EncodedCommand', script], input=value, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', env=env, timeout=45, shell=False)
    if result.returncode:
        raise ValueError('Encrypted worker credential operation failed; no secret output logged')
    return result.stdout.strip()


def load_worker():
    value = secret_call('read')
    if not value or any(ord(c) < 33 or ord(c) > 126 for c in value):
        raise ValueError('Invalid encrypted worker credential response')
    return value


def gateway_running():
    # This installed gateway is a Node application. Query process metadata without printing it.
    script = ("$ErrorActionPreference='Stop'; $found=@(Get-CimInstance Win32_Process -Filter \"Name='node.exe'\" "
              "| Where-Object { $_.CommandLine -like '*omniroute*' }); if ($found.Count) { exit 2 }; exit 0")
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive',
                             '-Command', script], capture_output=True, timeout=20, shell=False)
    if result.returncode not in (0, 2):
        raise ValueError('Could not establish that the gateway is stopped')
    return result.returncode == 2


def policy_routes(row):
    routes = json.loads(row['allowed_models'] or '[]')
    if (row['model_access_mode'] != 'restricted' or not isinstance(routes, list) or not routes
            or any(not isinstance(r, str) or not r.startswith('openrouter/') or not r.endswith(':free')
                   or any(c in r for c in ('*', '?', '\\', ' ')) for r in routes)):
        raise ValueError('Worker key must allow only explicit OpenRouter free routes')
    if not row['is_active'] or row['is_banned'] or row['revoked_at']:
        raise ValueError('Worker key is inactive, revoked or banned')
    if row['expires_at']:
        expiry = datetime.fromisoformat(row['expires_at'].replace('Z', '+00:00'))
        if expiry.tzinfo is None or expiry <= datetime.now(timezone.utc):
            raise ValueError('Worker key has expired')
    return routes


def key_row(db, key):
    rows = db.execute('SELECT * FROM api_keys WHERE key_hash=? OR key=?',
                      (hashlib.sha256(key.encode()).hexdigest(), key)).fetchall()
    if len(rows) != 1:
        raise ValueError('Saved worker key does not match one local policy')
    return rows[0]


def allowed_routes(database, key):
    with closing(sqlite3.connect(Path(database).resolve().as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        row = key_row(db, key)
        routes = policy_routes(row)
        if (row['allow_auto_combos'] or json.loads(row['allowed_combos'] or '[]') or row['auto_resolve']
                or row['key'] == key or not row['no_log']):
            raise ValueError('Harden the worker policy before running tasks')
        return routes


def harden_key(database, old_key, new_key, backup, store):
    """Rotate without writing the new plaintext key into SQLite; callbacks encrypt recovery/use."""
    if not new_key or new_key == old_key:
        raise ValueError('A distinct worker key is required')
    with closing(sqlite3.connect(database)) as db:
        db.row_factory = sqlite3.Row
        db.execute('BEGIN IMMEDIATE')
        row = key_row(db, old_key)
        policy_routes(row)
        backup(db.serialize())
        digest = hashlib.sha256(new_key.encode()).hexdigest()
        try:
            db.execute('UPDATE api_keys SET key=?, key_hash=?, key_prefix=?, allow_auto_combos=0, '
                       'allowed_combos=?, no_log=1, auto_resolve=0 WHERE id=?',
                       ('sha256:' + digest, digest, new_key[:6], '[]', row['id']))
            store(new_key)
            db.commit()
        except BaseException:
            db.rollback()
            store(old_key)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'harden'])
    args = parser.parse_args()
    try:
        if args.action == 'harden' and gateway_running():
            raise ValueError('Stop the gateway before changing its worker policy')
        database = Path.home() / '.aos/tools/stack/omniroute/data/storage.sqlite'
        key = load_worker()
        if args.action == 'harden':
            try:
                routes = allowed_routes(database, key)
                with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True)) as db:
                    clear = db.execute('SELECT 1 FROM api_keys WHERE key=?', (key,)).fetchone()
                if clear is None:
                    print(json.dumps({'changed': False, 'routes': routes, 'plaintext_duplicate': False}))
                    return 0
            except ValueError:
                pass
            target = Path.home() / '.aos-backups/omniroute' / (uuid.uuid4().hex + '.sqlite.dpapi')
            target.parent.mkdir(parents=True, exist_ok=True)
            harden_key(database, key, secrets.token_urlsafe(36),
                       lambda snapshot: secret_call('backup', base64.b64encode(snapshot).decode('ascii'), target),
                       lambda value: secret_call('write', value))
            print(json.dumps({'changed': True, 'encrypted_backup': str(target), 'plaintext_duplicate': False}))
        else:
            print(json.dumps({'routes': allowed_routes(database, key), 'plaintext_export': False}))
        return 0
    except (OSError, ValueError, sqlite3.Error, subprocess.SubprocessError):
        print('Worker policy operation failed; original state or encrypted recovery retained. No credentials printed.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
