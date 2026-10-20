"""On-demand Composio Connect calls using the encrypted consumer key, never SDK auth."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ENDPOINT = 'https://connect.composio.dev/mcp'
MAX_RESPONSE = 4 * 1024 * 1024
SECRET_SCRIPT = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Import-Module (Join-Path $env:AOS_CONNECT_REPO 'aos.psm1') -Force -WarningAction SilentlyContinue
$value = aos secret get composio-api-key
if ([string]::IsNullOrWhiteSpace($value)) { throw 'Consumer key unavailable' }
[Console]::Out.Write($value)
'''


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def load_key():
    encoded = base64.b64encode(SECRET_SCRIPT.encode('utf-16-le')).decode('ascii')
    result = subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive',
                             '-EncodedCommand', encoded], capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=30, shell=False,
                            env=dict(os.environ, AOS_CONNECT_REPO=str(Path(__file__).resolve().parents[1])))
    key = result.stdout.strip()
    if result.returncode or not key or any(ord(c) < 33 or ord(c) > 126 for c in key):
        raise ValueError('Could not load composio-api-key from aos secret; no key output was logged')
    return key


def parse_response(raw, request_id):
    if len(raw) > MAX_RESPONSE:
        raise ValueError('Composio response exceeded the local size limit')
    try:
        text = raw.decode('utf-8')
        if text.lstrip().startswith('{'):
            messages = [json.loads(text)]
        else:
            messages = []
            for event in text.replace('\r\n', '\n').split('\n\n'):
                data = '\n'.join(line[5:].lstrip() for line in event.splitlines() if line.startswith('data:'))
                if data:
                    messages.append(json.loads(data))
        for message in messages:
            if isinstance(message, dict) and message.get('id') == request_id:
                if 'error' in message:
                    raise ValueError('Composio returned a JSON-RPC error; response details suppressed')
                result = message.get('result')
                if isinstance(result, dict):
                    return result
    except (UnicodeError, json.JSONDecodeError):
        pass
    raise ValueError('Invalid Composio MCP response; response details suppressed')


def request(method, params, key):
    payload = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}).encode('utf-8')
    req = urllib.request.Request(ENDPOINT, data=payload, headers={
        'x-consumer-api-key': key, 'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream', 'MCP-Protocol-Version': '2025-03-26'})
    # A redirect must not carry the account credential to a different host.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(req, timeout=60) as response:
            raw = response.read(MAX_RESPONSE + 1)
    except urllib.error.HTTPError as exc:
        raise ValueError('Composio Connect returned HTTP ' + str(exc.code) + '; response details suppressed') from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ValueError('Composio Connect request failed; no credential or response details logged') from None
    return parse_response(raw, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    commands.add_parser('tools', help='List live MCP tools and their schemas')
    call = commands.add_parser('call', help='Execute one explicit MCP tool; authorize its effects first')
    call.add_argument('tool')
    call.add_argument('--input', required=True, type=Path, help='UTF-8 JSON object; no credentials')
    args = parser.parse_args()
    try:
        params = {}
        if args.action == 'call':
            raw = args.input.read_bytes()
            if len(raw) > 32768:
                raise ValueError('Tool input exceeds 32 KiB')
            arguments = json.loads(raw.decode('utf-8-sig'))
            if not isinstance(arguments, dict):
                raise ValueError('Tool input must be a JSON object')
            params = {'name': args.tool, 'arguments': arguments}
        key = load_key()
        request('initialize', {'protocolVersion': '2025-03-26', 'capabilities': {},
                              'clientInfo': {'name': 'aos-connect', 'version': '1.0'}}, key)
        result = request('tools/list' if args.action == 'tools' else 'tools/call', params, key)
        print(json.dumps(result, ensure_ascii=False, indent=2).replace(key, '[redacted]'))
        return 1 if result.get('isError') else 0
    except (ValueError, OSError, subprocess.TimeoutExpired):
        # Do not echo arbitrary input paths, server messages or secret-store stderr.
        print('Composio call failed. Check input, account connection and consumer-key access; no secrets logged.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
