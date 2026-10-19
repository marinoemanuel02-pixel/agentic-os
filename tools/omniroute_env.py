"""Run the isolated router with process-only keys from the Windows aos secret store."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

# Only this public script is encoded in the command line. Values travel through an
# in-memory pipe and child environment; never through arguments, files or printed output.
SECRET_SCRIPT = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$modulePath = Join-Path $env:AOS_ROUTER_REPO 'aos.psm1'
Import-Module $modulePath -Force -WarningAction SilentlyContinue
$module = @(Get-Module aos | Where-Object { $_.Path -eq $modulePath })[0]
if (-not $module) { throw 'Setup module not loaded' }
$result = & $module {
    $mapping = [ordered]@{
        STORAGE_ENCRYPTION_KEY = 'omniroute-storage-encryption'
        JWT_SECRET = 'omniroute-jwt-signing'
        API_KEY_SECRET = 'omniroute-api-signing'
        INITIAL_PASSWORD = 'omniroute-admin-password'
    }
    $names = @(Get-AosSecretNames)
    $values = [ordered]@{}
    foreach ($entry in $mapping.GetEnumerator()) {
        if ($names -notcontains $entry.Value) {
            $bytes = New-Object byte[] 32
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
            $plain = -join ($bytes | ForEach-Object { $_.ToString('x2') })
            $secure = ConvertTo-SecureString $plain -AsPlainText -Force
            if (-not (Set-AosSecret -Name $entry.Value -Value $secure)) { throw 'Could not store router secret' }
        }
        $value = Get-AosSecret -Name $entry.Value
        if ([string]::IsNullOrWhiteSpace($value)) { throw 'Could not decrypt router secret' }
        $values[$entry.Key] = $value
    }
    ConvertTo-Json -InputObject $values -Compress
}
[Console]::Out.Write($result)
'''


def load_secrets(repo):
    env = dict(os.environ, AOS_ROUTER_REPO=str(repo))
    encoded = base64.b64encode(SECRET_SCRIPT.encode('utf-16-le')).decode('ascii')
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive',
                             '-EncodedCommand', encoded], env=env, capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=30, shell=False)
    if result.returncode != 0:
        raise ValueError('Could not load the router keys from aos secret; no key output was logged')
    try:
        values = json.loads(result.stdout)
        required = {'STORAGE_ENCRYPTION_KEY', 'JWT_SECRET', 'API_KEY_SECRET', 'INITIAL_PASSWORD'}
        if not isinstance(values, dict) or set(values) != required:
            raise ValueError()
        if any(not isinstance(value, str) or not value.strip() for value in values.values()):
            raise ValueError()
        return values
    except (ValueError, TypeError):
        raise ValueError('Invalid secret-store response; its contents were not logged') from None


def plan(arguments, *, home=None):
    if arguments and arguments[0].lower() == 'auth':
        raise ValueError('Credential export is not available through this launcher')
    if any(arg.split('=', 1)[0] in ('--daemon', '--tray', '--api-key') for arg in arguments):
        raise ValueError('Use foreground operation and process-only credentials')
    home = Path(home or Path.home())
    repo = Path(__file__).resolve().parents[1]
    env = {key: value for key, value in os.environ.items()
           if not any(word in key.upper() for word in ('API_KEY', 'AUTH_TOKEN', 'ACCESS_TOKEN',
                                                        'JWT_SECRET', 'ENCRYPTION_KEY', '_PROXY'))}
    env.update(DATA_DIR=str(home / '.aos/tools/stack/omniroute/data'),
               OMNIROUTE_SERVER_HOST='127.0.0.1', REQUIRE_API_KEY='true',
               NO_UPDATE_NOTIFIER='1', NEXT_TELEMETRY_DISABLED='1', PYTHONUTF8='1',
               TEMP=str(home / '.aos/tmp'), TMP=str(home / '.aos/tmp'))
    informational = any(arg in ('--help', '-h', '--version', '-v', '-V') for arg in arguments)
    if not informational:
        env.update(load_secrets(repo))
    args = list(arguments or ['serve'])
    if not informational and args[0] == 'serve':
        args += ['--no-open', '--no-tray', '--no-recovery']
    entry = home / '.aos/tools/omniroute-3.8.51/node_modules/omniroute/bin/omniroute.mjs'
    return [shutil.which('node') or 'node', str(entry), *args], env


def main():
    try:
        command, env = plan(sys.argv[1:])
        return subprocess.run(command, env=env, shell=False).returncode
    except (ValueError, OSError, subprocess.TimeoutExpired):
        print('Router launch failed; check installation and aos secret access. No credentials were printed.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
