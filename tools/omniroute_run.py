"""Run one verified-free text task with the saved restricted key and owned gateway lifecycle."""
import argparse
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request

# Standalone invocation and test loading resolve the same colocated modules.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import omniroute_env
import omniroute_policy
import omniroute_worker as worker

CATALOG = 'https://openrouter.ai/api/v1/models'


def json_get(url, key=None, timeout=15):
    headers = {'Accept': 'application/json'}
    if key:
        headers['Authorization'] = 'Bearer ' + key
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), worker.NoRedirect())
    try:
        with opener.open(urllib.request.Request(url, headers=headers), timeout=timeout) as response:
            raw = response.read(8 * 1024 * 1024 + 1)
        if len(raw) > 8 * 1024 * 1024:
            raise ValueError('Catalog exceeded size limit')
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError('Invalid catalog response')
        return data
    except urllib.error.HTTPError as exc:
        raise ValueError('Catalog returned HTTP ' + str(exc.code)) from None
    except (OSError, urllib.error.URLError):
        raise ValueError('Catalog connection failed; no retry or inference attempted') from None


def verify_free_route(route, allowed, catalog):
    if route not in allowed or not route.startswith('openrouter/') or not route.endswith(':free'):
        raise ValueError('Choose an explicit free route allowed by the saved restricted key')
    model = route[len('openrouter/'):]
    rows = catalog.get('data', [])
    entry = next((r for r in rows if isinstance(r, dict) and r.get('id') == model), None)
    pricing = entry.get('pricing') if entry else None
    if not isinstance(pricing, dict) or not {'prompt', 'completion'} <= set(pricing):
        raise ValueError('Free route has no current complete pricing evidence')
    try:
        values = [Decimal(str(v)) for v in pricing.values()]
        if not values or any(not v.is_finite() or v != 0 for v in values):
            raise ValueError('Only known zero-priced routes are enabled')
    except (InvalidOperation, TypeError):
        raise ValueError('Unknown route price; inference refused') from None
    return route


def listening(endpoint):
    url = urllib.parse.urlsplit(endpoint)
    try:
        with socket.create_connection((url.hostname, url.port or 80), timeout=1):
            return True
    except OSError:
        return False


@contextmanager
def gateway(endpoint, key, startup_timeout=180):
    endpoint = worker.validate_endpoint(endpoint)
    process = None
    try:
        if not listening(endpoint):
            port = urllib.parse.urlsplit(endpoint).port or 80
            command, env = omniroute_env.plan(['serve', '--port', str(port)])
            process = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                       creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            deadline = time.monotonic() + startup_timeout
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise ValueError('Owned gateway exited before readiness')
                try:
                    json_get(endpoint + '/models', key, timeout=5)
                    break
                except ValueError:
                    time.sleep(0.5)
            else:
                raise ValueError('Owned gateway startup timed out')
        else:
            # Never stop or replace a pre-existing listener. It must accept the saved key.
            json_get(endpoint + '/models', key, timeout=10)
        yield process is not None
    finally:
        if process is not None and process.poll() is None:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               capture_output=True, timeout=15, shell=False)
            else:
                process.terminate()
            process.wait(timeout=15)


@contextmanager
def worker_lock(home=None):
    path = Path(home or Path.home()) / '.aos/tools/stack/omniroute/worker.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x', encoding='ascii') as handle:
        handle.write(str(os.getpid()))
    try:
        yield
    finally:
        path.unlink()


def execute(packet, output, endpoint, model=None, check=False):
    endpoint = worker.validate_endpoint(endpoint)
    if not check:
        if output.exists():
            raise FileExistsError('Candidate output already exists')
        if packet.stat().st_size > worker.MAX_PROMPT:
            raise ValueError('Task packet exceeds 32 KiB')
        prompt = packet.read_text(encoding='utf-8-sig')
        if not prompt.strip():
            raise ValueError('Task packet is empty')
    key = omniroute_policy.load_worker()
    database = Path.home() / '.aos/tools/stack/omniroute/data/storage.sqlite'
    allowed = omniroute_policy.allowed_routes(database, key)
    if model is None and len(allowed) != 1:
        raise ValueError('Multiple allowed routes; select one explicitly with --model')
    route = verify_free_route(model or allowed[0], allowed, json_get(CATALOG))
    with worker_lock(), gateway(endpoint, key) as owned:
        if check:
            return {'status': 'ready', 'route': route, 'pricing_verified_zero': True,
                    'owned_server': owned, 'inference_requests': 0}
        result = worker.request(endpoint, route, prompt, key, timeout=90)
        result.update(provider='openrouter', pricing_verified_zero=True, automatic_fallback=False,
                      owned_server=owned, actor_scope='one text-only candidate; no native writer admission')
        worker.save_candidate(output, result)
    return result


def execute_managed(packet, output, endpoint, model=None):
    """Use the shared admission ledger after swarm activation; keep the plain-text CLI."""
    from swarm_config import load_registry, root
    from swarm_state import State
    from swarm_pool import Pool, export_candidate
    endpoint = worker.validate_endpoint(endpoint)
    if endpoint != 'http://127.0.0.1:20128/v1': raise ValueError('Managed gateway uses its registered endpoint')
    if output.exists() or packet.stat().st_size > worker.MAX_PROMPT: raise ValueError('Output exists or packet exceeds bound')
    registry = load_registry()
    account = next((a for a in registry['accounts'] if a['id'] == 'current-omniroute'), None)
    if account is None: raise ValueError('Managed gateway account unavailable')
    route = account['routes']['text']['model']
    if model is not None and model != 'openrouter/' + route: raise ValueError('Choose the managed explicit free route')
    state = State(root() / 'state.sqlite'); pool = Pool(registry, state)
    name = 'omniroute-' + uuid.uuid4().hex
    pool.submit({'id': name, 'capability': 'text', 'account': account['id'],
                 'cloud_allowed': True, 'prompt': packet.read_text(encoding='utf-8-sig'), 'max_attempts': 1})
    pool.drain(only=name)
    return export_candidate(state, name, output)['candidate']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', default='http://127.0.0.1:20128/v1')
    parser.add_argument('--model', help='Optional when the saved restricted policy permits one route')
    parser.add_argument('--packet', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--check', action='store_true', help='Readiness and free-price check without inference')
    args = parser.parse_args()
    if not args.check and (args.packet is None or args.output is None):
        parser.error('--packet and --output are required for a worker task')
    try:
        from swarm_config import root
        if not args.check and (root() / 'accounts.json').exists():
            result = execute_managed(args.packet, args.output, args.endpoint, args.model)
        else:
            result = execute(args.packet, args.output, args.endpoint, args.model, args.check)
        if args.check:
            print(json.dumps(result, indent=2))
        else:
            lifecycle = 'owned gateway stopped' if result.get('owned_server') else 'existing gateway kept running'
            print('Candidate saved. Verify its facts before use; ' + lifecycle + '.')
        return 0 if args.check or result.get('complete') else 1
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError):
        print('Worker task failed. Check policy/readiness, route availability and output path. No retry or paid fallback.', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
