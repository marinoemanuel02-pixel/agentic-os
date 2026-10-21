"""Recover selected account keys directly into DPAPI and build a current home registry."""
import argparse
import ast
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import re
import time
import uuid

from swarm_config import load_registry, root, secret, validate_registry
from swarm_providers import auth, BASES, catalog, request_json
from swarm_pool import save_new


@contextmanager
def registry_write():
    root().mkdir(parents=True, exist_ok=True)
    lock = root() / 'accounts.lock'
    with lock.open('x', encoding='ascii') as handle: handle.write(str(__import__('os').getpid()))
    try: yield
    finally: lock.unlink()


def persist_registry(r, backup_dir=None):
    validate_registry(r)
    backup = Path(backup_dir or Path.home() / '.aos-backups/swarm') / (uuid.uuid4().hex + '.accounts.json')
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root() / 'accounts.json', backup)
    temp = root() / (uuid.uuid4().hex + '.accounts.tmp')
    save_new(temp, r); temp.replace(root() / 'accounts.json')


def add_account(path, *, free_confirmed=False, backup_dir=None):
    if Path(path).stat().st_size > 16384: raise ValueError('Account record too large')
    a = json.loads(Path(path).read_text(encoding='utf-8-sig')); r = load_registry(root() / 'accounts.json')
    if a.get('provider') not in ('openrouter', 'omniroute') and not free_confirmed:
        raise ValueError('Confirm free/evaluation and paid usage disabled')
    candidate = dict(r, accounts=r['accounts'] + [a]); validate_registry(candidate)
    key = secret(a['secret']); data = catalog(a, key)
    if a['provider'] in ('openrouter', 'omniroute'):
        from omniroute_run import verify_free_route
        for route in a['routes'].values():
            verify_free_route('openrouter/' + route['model'], ['openrouter/' + route['model']], data)
        request_json(BASES['openrouter'] + '/key', auth('openrouter', key))
    persist_registry(candidate, backup_dir)
    return {'changed': True, 'account': a['id'], 'metadata_checked': True, 'inference_requests': 0}


def renew_free(ids, *, free_confirmed=False):
    if not free_confirmed: raise ValueError('Explicit free/evaluation billing-disabled confirmation required')
    r = load_registry(); found = set()
    for a in r['accounts']:
        if a['id'] in ids:
            if a['free']['kind'] != 'free_tier': raise ValueError('Zero-price routes do not need an attestation')
            a['free'].update(confirmed_until=int(time.time()+7*86400), paid_disabled=True,
                             evidence='operator billing-disabled confirmation; renewed ' + time.strftime('%Y-%m-%d'))
            found.add(a['id'])
    if found != set(ids): raise ValueError('Unknown account')
    persist_registry(r)
    return {'changed': True, 'accounts': sorted(found), 'valid_days': 7}


def pick_models(provider, data, previous=None):
    if provider == 'gemini':
        rows = data.get('models', [])
        generation = [r for r in rows if 'generateContent' in r.get('supportedGenerationMethods', [])
                      and not any(s in r['name'].lower() for s in ('preview', 'experimental', 'image', 'tts', 'robotics', 'research', 'computer'))]
        generation.sort(key=lambda r: ('latest' not in r['name'].lower(), 'flash' not in r['name'].lower(),
                                      'lite' not in r['name'].lower(), tuple(-int(n) for n in re.findall(r'\d+', r['name'])), r['name']))
        embeddings = [r for r in rows if 'embedContent' in r.get('supportedGenerationMethods', [])
                      and not any(s in r['name'] for s in ('preview', 'experimental'))]
        if not generation: raise ValueError('No current generation model')
        model = generation[0]['name'].removeprefix('models/')
        result = {k: {'model': model} for k in ('text', 'research', 'vision', 'transcribe')}
        if embeddings: result['embed'] = {'model': sorted(embeddings, key=lambda r: tuple(int(n) for n in re.findall(r'\d+', r['name'])))[-1]['name'].removeprefix('models/')}
        return result
    if provider == 'mistral':
        rows = [r for r in data.get('data', []) if r.get('capabilities', {}).get('completion_chat')]
        if not rows: raise ValueError('No current chat model')
        selected = next((r for r in rows if r['id'] == previous), None)
        if not selected:
            rows.sort(key=lambda r: ('small' not in r['id'].lower(), 'latest' not in r['id'].lower(), r['id']))
            selected = rows[0]
        return {k: {'model': selected['id']} for k in ('text', 'research')}
    if provider == 'cohere':
        rows = [r for r in data.get('models', []) if not r.get('is_deprecated') and not r.get('finetuned')]
        result = {}
        for capability, endpoint in [('text', 'chat'), ('research', 'chat'), ('embed', 'embed'), ('rerank', 'rerank')]:
            options = [r for r in rows if endpoint in r.get('endpoints', [])]
            options.sort(key=lambda r: (endpoint not in r.get('default_endpoints', []),
                                       'multilingual' not in r['name'], r['name']))
            if options: result[capability] = {'model': options[0]['name']}
        if not result: raise ValueError('No current Cohere routes')
        return result
    raise ValueError('Unsupported discovery provider')


def recover(source, *, free_confirmed=False):
    source = Path(source).resolve(strict=True)
    target = root() / 'accounts.json'
    if target.exists():
        # Never silently replace later operator additions or reset quota history.
        return {'changed': False, 'accounts': len(load_registry(target)['accounts']), 'registry': str(target)}
    if not free_confirmed: raise ValueError('Operator confirmation of billing-disabled free tiers required')
    names = {'OPENROUTER_API_KEY_2', 'MISTRAL_API_KEY', 'MISTRAL_API_KEY_2',
             'GEMINI_API_KEY', 'GEMINI_API_KEY_2', 'COHERE_API_KEY', 'COHERE_API_KEY_2'}
    keys = {}
    for raw in (source / 'secrets.env').read_text(encoding='utf-8').splitlines():
        if '=' not in raw or raw.lstrip().startswith('#'): continue
        name, value = raw.split('=', 1)
        if name.strip() in names: keys[name.strip()] = value.strip().strip('"').strip("'")
    previous = {}
    for node in ast.walk(ast.parse((source / 'swarm/config.py').read_text(encoding='utf-8'))):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'Profile':
            fields = {k.arg: k.value.value for k in node.keywords if isinstance(k.value, ast.Constant)}
            if 'env_key' in fields and 'model' in fields: previous[fields['env_key']] = fields['model']
    # Reuse the explicit route the operator already approved in OmniRoute.
    from omniroute_policy import load_worker, allowed_routes
    routes = allowed_routes(Path.home() / '.aos/tools/stack/omniroute/data/storage.sqlite', load_worker())
    if len(routes) != 1: raise ValueError('Select one checked gateway model before recovery')
    model = routes[0].removeprefix('openrouter/')
    records = []; observations = []
    specs = [('current-openrouter', 'openrouter', 'openrouter-api-key', None, 'current-openrouter'),
             ('recovered-openrouter', 'openrouter', 'swarm-openrouter-recovered', 'OPENROUTER_API_KEY_2', 'recovered-openrouter'),
             ('current-omniroute', 'omniroute', 'openrouter-api-key', None, 'current-openrouter')]
    for provider in ('gemini', 'mistral', 'cohere'):
        for n in (1, 2):
            name = provider.upper() + '_API_KEY' + ('_2' if n == 2 else '')
            # Unknown project/org relationships share a conservative bucket until verified.
            group = provider + '-recovered' + ('-' + str(n) if provider == 'cohere' else '')
            specs.append((provider + '-' + str(n), provider, 'swarm-' + provider + '-' + str(n), name, group))
    for identity, provider, ref, archived, group in specs:
        try:
            key = keys[archived] if archived else secret(ref)
            if archived:
                try: saved = secret(ref)
                except ValueError:
                    secret(ref, store=key); saved = secret(ref)
                if saved != key: raise ValueError('Existing encrypted credential differs; not overwritten')
            a = {'id': identity, 'provider': provider, 'secret': ref, 'quota_group': group,
                 'enabled': True, 'priority': 1 if provider == 'mistral' else (2 if provider == 'gemini' else 3),
                 'free': {'kind': 'zero_price'} if provider in ('openrouter', 'omniroute') else
                         {'kind': 'free_tier', 'paid_disabled': True, 'confirmed_until': int(time.time() + 7 * 86400),
                          'evidence': 'operator confirmation 2026-10-21; paid usage disabled'},
                 'limits': [{'unit': 'requests', 'seconds': 60, 'amount': 4},
                            {'unit': 'requests', 'seconds': 86400, 'amount': 30},
                            {'unit': 'tokens', 'seconds': 60, 'amount': 30000},
                            {'unit': 'tokens', 'seconds': 86400, 'amount': 200000}], 'routes': {}}
            data = catalog(a, key)
            if provider in ('openrouter', 'omniroute'):
                from omniroute_run import verify_free_route
                verify_free_route('openrouter/' + model, ['openrouter/' + model], data)
                # Also establish authenticated access, not just public catalog access.
                request_json(BASES['openrouter'] + '/key', auth('openrouter', key))
                a['routes'] = {cap: {'model': model} for cap in ('text', 'research')}
                a['priority'] = 4 if provider == 'openrouter' else 5
            else: a['routes'] = pick_models(provider, data, previous.get(archived))
            if 'transcribe' in a['routes']:
                a['limits'].append({'unit': 'audio_seconds', 'seconds': 86400, 'amount': 600})
            records.append(a)
            observations.append({'account': identity, 'metadata': 'passed', 'capabilities': list(a['routes'])})
        except (ValueError, OSError, KeyError):
            observations.append({'account': identity, 'metadata': 'blocked', 'details': 'credentials/provider response suppressed'})
    result = validate_registry({'version': 1, 'max_active': 4, 'provider_active': 2, 'accounts': records})
    if not records: raise ValueError('No verified account; registry not created')
    save_new(target, result)
    save_new(root() / 'recovery.json', {'accounts': observations, 'source_unchanged': True,
              'billing_evidence': 'operator attestation; expires after seven days',
              'excluded': {'groq': 'prior metadata access returned 403; not proof of invalid keys',
                           'cerebras': 'no verified recurring free eligibility',
                           'huggingface': 'no verified included free inference credit'}})
    return {'changed': True, 'accounts': observations, 'registry': str(target)}


def refresh(account_ids):
    """Refresh explicitly selected models; clear rejection cooldown only after a working metadata probe."""
    from swarm_state import State
    r = load_registry(); changed = []; clear = []
    for identity in account_ids:
        a = next((x for x in r['accounts'] if x['id'] == identity), None)
        if not a or a['provider'] not in ('gemini', 'mistral', 'cohere'): raise ValueError('No refreshable account')
        key = secret(a['secret']); routes = pick_models(a['provider'], catalog(a, key))
        if routes == a['routes']: continue
        if a['provider'] == 'gemini':
            request_json(BASES['gemini'] + '/models/' + routes['text']['model'] + ':countTokens',
                         auth('gemini', key), {'contents': [{'role': 'user', 'parts': [{'text': 'readiness'}]}]})
            clear.append((a['quota_group'], hashlib.sha256(key.encode()).hexdigest()))
        changed.append({'account': identity, 'previous_routes': a['routes'], 'new_routes': routes})
        a['routes'] = routes
        if 'transcribe' in routes and not any(x['unit'] == 'audio_seconds' for x in a['limits']):
            a['limits'].append({'unit': 'audio_seconds', 'seconds': 86400, 'amount': 600})
    if changed:
        persist_registry(r)
        state = State(root() / 'state.sqlite')
        with state.db(True) as db:
            for group, fingerprint in clear:
                if db.execute('SELECT 1 FROM attempts WHERE active=1 AND (quota_group=? OR credential=?)', (group, fingerprint)).fetchone():
                    raise ValueError('Active account retained; cooldown not reconciled')
                db.execute('DELETE FROM cooldowns WHERE bucket IN (?,?)', ('group:' + group, 'credential:' + fingerprint))
        save_new(root() / 'changes' / (uuid.uuid4().hex + '.json'), {'changes': changed, 'metadata_revalidated': True,
                 'attempts_and_quota_history_preserved': True})
    return {'changed': bool(changed), 'accounts': [x['account'] for x in changed]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--refresh-account', action='append')
    parser.add_argument('--add-account', type=Path)
    parser.add_argument('--renew-free', action='append')
    parser.add_argument('--free-confirmed-paid-disabled', action='store_true')
    args = parser.parse_args()
    try:
        if sum(bool(x) for x in (args.source,args.refresh_account,args.add_account,args.renew_free)) != 1:
            raise ValueError('Choose exactly one account action')
        with registry_write():
            if args.refresh_account: result = refresh(args.refresh_account)
            elif args.add_account: result = add_account(args.add_account, free_confirmed=args.free_confirmed_paid_disabled)
            elif args.renew_free: result = renew_free(args.renew_free, free_confirmed=args.free_confirmed_paid_disabled)
            else: result = recover(args.source, free_confirmed=args.free_confirmed_paid_disabled)
        print(json.dumps(result, indent=2)); return 0
    except (ValueError, OSError, KeyError):
        print('Account recovery failed safely; existing secrets and backup were retained.', file=__import__('sys').stderr); return 2


if __name__ == '__main__': raise SystemExit(main())
