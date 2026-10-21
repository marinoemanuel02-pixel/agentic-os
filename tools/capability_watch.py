"""Discover candidate capabilities without installing or starting external tools."""
import argparse
from contextlib import contextmanager, nullcontext
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / 'config/capabilities.schema.json'
HOSTS = {'api.github.com', 'raw.githubusercontent.com', 'github.com', 'miles990.github.io',
         'glama.ai', 'pypi.org', 'registry.npmjs.org'}
MAX_BYTES = 8 * 1024 * 1024
CHECKS = ('source', 'license', 'windows_build', 'windows_execution', 'security', 'artifact')
PATTERNS = {
    'windows': r'\bwindows\b|\bwin32\b|\bwin64\b',
    'cli': r'\bcli\b|command.line',
    'mcp': r'\bmcp\b|model context protocol',
    'stdio': r'\bstdio\b|standard input.output',
    'json_rpc': r'json[ _-]?rpc',
    'headless': r'\bheadless\b|without (?:a |the )?(?:window|gui)',
    'live_gui_attach': r'live[ _-]?(?:gui|app|bridge)|attach.{0,60}(?:gui|running|desktop)|running.{0,30}(?:gui|app)',
    'inspectable_state': r'inspect(?:able|ion)?[ _-]?state|structured[ _-]?state|scene inspection|document inspection',
    'render_feedback': r'\brender(?:ing|ed)?\b|\bscreenshot\b|preview',
    'filesystem_scoping': r'--root\b|filesystem[ _-]?(?:scop|confin)|read[ _-]?root|write[ _-]?root|automation.{0,30}roots',
    'revision_guards': r'expected[ _-]?revision|revision[ _-]?guard|stale[ _-]?(?:edit|revision)',
    'rollback': r'\brollback\b|\bundo\b|\bcheckpoint\b',
    'transactional_edits': r'\btransaction(?:al|s)?\b|\batomic\b',
}
REPO_LINK = re.compile(r'https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)')


def load_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def validate_value(value, schema, root, where='$'):
    """Enforce the keywords used by our bundled JSON Schema; no runtime dependency."""
    if '$ref' in schema:
        schema = root['$defs'][schema['$ref'].split('/')[-1]]
    types = {'object': dict, 'array': list, 'string': str, 'boolean': bool, 'null': type(None),
             'integer': int}
    if 'type' in schema:
        allowed = schema['type'] if isinstance(schema['type'], list) else [schema['type']]
        if not any(type(value) is types[t] for t in allowed):
            raise ValueError(where + ': invalid type')
    if 'const' in schema and (type(value) is not type(schema['const']) or value != schema['const']):
        raise ValueError(where + ': invalid constant')
    if 'enum' in schema and value not in schema['enum']:
        raise ValueError(where + ': invalid value')
    if isinstance(value, dict):
        props = schema.get('properties', {})
        if set(schema.get('required', [])) - value.keys():
            raise ValueError(where + ': missing required fields')
        if schema.get('additionalProperties') is False and value.keys() - props.keys():
            raise ValueError(where + ': unknown fields')
        for key, item in value.items():
            if key in props:
                validate_value(item, props[key], root, where + '.' + key)
    if isinstance(value, list):
        if len(value) < schema.get('minItems', 0):
            raise ValueError(where + ': too few items')
        if schema.get('uniqueItems') and len({json.dumps(x, sort_keys=True) for x in value}) != len(value):
            raise ValueError(where + ': duplicate items')
        for index, item in enumerate(value):
            validate_value(item, schema.get('items', {}), root, where + '[' + str(index) + ']')
    if isinstance(value, str):
        if len(value.strip()) < schema.get('minLength', 0):
            raise ValueError(where + ': empty string')
        if 'pattern' in schema and not re.search(schema['pattern'], value):
            raise ValueError(where + ': invalid pattern')
        if schema.get('format') == 'date-time':
            try:
                stamp = datetime.fromisoformat(value.replace('Z', '+00:00'))
                if 'T' not in value or stamp.tzinfo is None:
                    raise ValueError('timezone required')
            except ValueError as exc:
                raise ValueError(where + ': invalid timestamp') from exc
        if schema.get('format') == 'uri':
            check_url(value)


def production_ready(candidate):
    records = [r for r in candidate['verification'] if r['version'] == candidate['pinned_version']]
    return bool(candidate['pinned_version'] and records and
                all(records[-1]['checks'].get(k) == 'pass' for k in CHECKS))


def validate_registry(data):
    schema = load_json(SCHEMA)
    validate_value(data, schema, schema)
    for key in ('tools', 'sources', 'research_inputs'):
        ids = [item['id'] for item in data[key]]
        if len(ids) != len(set(ids)):
            raise ValueError('Duplicate ' + key + ' id')
    repos = [t['repository'].lower() for t in data['tools'] if t['repository']]
    if len(repos) != len(set(repos)):
        raise ValueError('Duplicate candidate repository')
    tool_ids = {t['id'] for t in data['tools']}
    for source in data['sources']:
        if source['tool'] is not None and source['tool'] not in tool_ids:
            raise ValueError('Unknown source tool: ' + source['tool'])
    for tool in data['tools']:
        for path in tool['watch_paths']:
            if not re.fullmatch(r'[A-Za-z0-9_./-]+', path) or '..' in path.split('/') or path.startswith('/'):
                raise ValueError('Invalid repository watch path')
        if tool['status'] == 'production' and not production_ready(tool):
            raise ValueError('Production requires passing evidence at the pinned version: ' + tool['id'])


def record_evidence(candidate, evidence):
    schema = load_json(SCHEMA)
    validate_value(evidence, schema['$defs']['evidence'], schema)
    if candidate['verification'] and datetime.fromisoformat(evidence['checked_at'].replace('Z', '+00:00')) < datetime.fromisoformat(candidate['verification'][-1]['checked_at'].replace('Z', '+00:00')):
        raise ValueError('Evidence must be appended in evaluation order')
    candidate['verification'].append(copy.deepcopy(evidence))
    candidate['last_evaluated'] = evidence['checked_at']


def set_status(candidate, status, reason):
    if status not in ('ignore', 'watch', 'sandbox', 'production') or not reason.strip():
        raise ValueError('A valid status and reason are required')
    if status == 'production' and not production_ready(candidate):
        raise ValueError('Production requires passing evidence at the pinned version')
    candidate['status'] = status
    candidate['status_reason'] = reason


def check_url(url):
    parts = urlsplit(url)
    if (parts.scheme != 'https' or parts.hostname not in HOSTS or parts.username or parts.password
            or parts.port not in (None, 443) or parts.fragment):
        raise ValueError('URL must use an allowed public HTTPS origin')


class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_text(url):
    check_url(url)
    headers = {'User-Agent': 'agentic-os-capability-watch',
               'Accept': 'application/vnd.github.raw+json' if url.endswith('/readme') else 'application/json'}
    with build_opener(SafeRedirect()).open(Request(url, headers=headers), timeout=20) as response:
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError('Source exceeds 8 MiB response limit')
    return raw.decode('utf-8', errors='strict')


def repository_links(text):
    found = {}
    for match in REPO_LINK.finditer(text):
        owner, repo = match.groups()
        repo = repo.removesuffix('.git').rstrip('.')
        if owner.lower() in ('orgs', 'topics', 'sponsors', 'features', 'settings') or repo in ('', '.', '..'):
            continue
        url = 'https://github.com/' + owner.lower() + '/' + repo.lower()
        found.setdefault(url, text[max(0, match.start() - 160):match.end() + 160])
    return found


def sources_for(registry, tool_ids, source_ids):
    sources = []
    ids = {s['id'] for s in registry['sources']}
    if source_ids is not None and set(source_ids) - ids:
        raise ValueError('Unknown discovery/release source')
    for source in registry['sources']:
        if ((source_ids is None and not tool_ids and source['enabled']) or
                (source_ids is not None and source['id'] in source_ids)):
            if source['id'] == 'glama':
                raise ValueError('Glama API requires a separately authorized authentication adapter')
            sources.append(source)
    tools = {t['id']: t for t in registry['tools']}
    for tool_id in dict.fromkeys(tool_ids):
        if tool_id not in tools or not tools[tool_id]['repository']:
            raise ValueError('Unknown tool or unresolved original repository: ' + tool_id)
        tool = tools[tool_id]
        repo = tool['repository'].split('github.com/')[1]
        api = 'https://api.github.com/repos/' + repo
        for suffix, kind in (('', 'github_metadata'), ('/readme', 'document'),
                             ('/releases/latest', 'github_release')):
            sources.append({'id': tool_id + ':' + kind, 'url': api + suffix, 'kind': kind,
                            'role': 'verification_lead', 'tool': tool_id})
        for path in tool['watch_paths']:
            sources.append({'id': tool_id + ':' + path, 'kind': 'document', 'tool': tool_id,
                            'role': 'verification_lead',
                            'url': 'https://raw.githubusercontent.com/' + repo + '/HEAD/' + path})
    return sources


def observe(source, body, checked_at):
    if len(body.encode('utf-8')) > MAX_BYTES:
        raise ValueError('Source exceeds 8 MiB response limit')
    kind = source['kind']
    metadata = {}
    if kind in ('json', 'npm', 'pypi', 'github_metadata', 'github_release'):
        data = json.loads(body)
        if not isinstance(data, (dict, list)):
            raise ValueError('Expected a JSON object or list')
        if kind in ('npm', 'pypi', 'github_metadata', 'github_release') and not isinstance(data, dict):
            raise ValueError('Expected metadata object')
        if kind == 'npm':
            metadata = {'version': data['version']}
        if kind == 'pypi':
            version = data['info']['version']
            metadata = {'version': version, 'files': [x['filename'] for x in data.get('urls', [])],
                        'published_at': [x.get('upload_time_iso_8601') for x in data.get('urls', [])]}
        if kind == 'github_metadata':
            metadata = {k: data.get(k) for k in ('created_at', 'pushed_at', 'fork', 'archived',
                                                'default_branch', 'license', 'parent')}
            # Do not persist an entire nested parent repository object.
            metadata['parent'] = (data.get('parent') or {}).get('html_url')
        if kind == 'github_release':
            metadata = {'version': data['tag_name'], 'published_at': data.get('published_at'),
                        'assets': [x['name'] for x in data.get('assets', [])]}
    elif kind == 'rss':
        root = ET.fromstring(body)
        if root.tag not in ('rss', '{http://www.w3.org/2005/Atom}feed'):
            raise ValueError('Expected RSS or Atom feed')
    elif kind not in ('markdown', 'document'):
        raise ValueError('Unsupported source kind')
    if kind in ('markdown', 'document') and (not body.strip() or body.lstrip().lower().startswith(('<html', '<!doctype html'))):
        raise ValueError('Expected a nonempty document, not an HTML error page')
    signals = {}
    if kind == 'document':
        for key, pattern in PATTERNS.items():
            match = re.search(pattern, body, flags=re.I)
            signals[key] = {'present': bool(match), 'snippet': body[max(0, match.start() - 60):match.end() + 100] if match else None}
    return {'url': source['url'], 'kind': kind, 'tool': source['tool'], 'checked_at': checked_at,
            'sha256': hashlib.sha256(body.encode('utf-8')).hexdigest(), 'metadata': metadata,
            'signals': signals,
            'repositories': repository_links(body) if source['role'] == 'discovery' else {}}


def refresh(registry, previous, *, fetch=fetch_text, tool_ids=(), source_ids=None,
            checked_at=None, limit=50, match=''):
    validate_registry(registry)
    if not 1 <= limit <= 500:
        raise ValueError('Discovery limit must be between 1 and 500')
    if not isinstance(previous, dict) or not isinstance(previous.get('sources'), dict):
        raise ValueError('Invalid previous state; preserve it and inspect manually')
    for saved in previous['sources'].values():
        required = {'url', 'kind', 'sha256', 'metadata', 'signals', 'repositories', 'checked_at', 'tool'}
        if (not isinstance(saved, dict) or required - saved.keys() or
                not all(isinstance(saved[k], dict) for k in ('metadata', 'signals', 'repositories'))):
            raise ValueError('Invalid saved source; preserve state and inspect manually')
        for signal in saved['signals'].values():
            if not isinstance(signal, dict) or type(signal.get('present')) is not bool:
                raise ValueError('Invalid saved signal; preserve state and inspect manually')
    state = copy.deepcopy(previous)
    checked_at = checked_at or datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    report = {'checked_at': checked_at, 'confidence': 'unverified_signal', 'baselines': [],
              'transitions': [], 'discoveries': [], 'errors': [], 'source_changes': []}
    discovered = {}
    known = {t['repository'].lower() for t in registry['tools'] if t['repository']}
    seen = set(previous.get('seen_repositories', []))
    for source in sources_for(registry, tool_ids, source_ids):
        source_id = source['id']
        old = previous['sources'].get(source_id)
        try:
            check_url(source['url'])
            try:
                body = fetch(source['url'])
            except HTTPError as exc:
                if source['kind'] != 'github_release' or exc.code != 404:
                    raise
                body = '{"tag_name": null, "published_at": null, "assets": []}'
            current = observe(source, body, checked_at)
        except (OSError, ValueError, KeyError, TypeError, ET.ParseError) as exc:
            # Do not log response bodies, credentials or externally supplied exception strings.
            report['errors'].append({'source': source_id, 'error': type(exc).__name__,
                                     'http_status': exc.code if isinstance(exc, HTTPError) else None})
            continue
        state['sources'][source_id] = current
        if old is None:
            report['baselines'].append(source_id)
        elif old['url'] == current['url'] and old['kind'] == current['kind']:
            if old['sha256'] != current['sha256']:
                report['source_changes'].append(source_id)
            for key, value in current['signals'].items():
                if key in old['signals'] and old['signals'][key]['present'] != value['present']:
                    report['transitions'].append({'source': source_id, 'tool': source['tool'],
                        'kind': 'signal_appeared' if value['present'] else 'signal_disappeared',
                        'field': key, 'before': old['signals'][key], 'after': value,
                        'confidence': 'unverified_signal'})
            if old['metadata'] != current['metadata']:
                report['transitions'].append({'source': source_id, 'tool': source['tool'],
                    'kind': 'release_changed' if source['kind'] in ('github_release', 'npm', 'pypi') else 'repository_changed',
                    'field': 'metadata', 'before': old['metadata'], 'after': current['metadata'],
                    'confidence': 'unverified_signal'})
        else:
            report['baselines'].append(source_id)
        for repo, context in current['repositories'].items():
            if repo in known or repo in seen or (match and match.casefold() not in context.casefold()):
                continue
            discovered.setdefault(repo, {'repository': repo, 'discovered_at': checked_at,
                                         'sources': [], 'context': context[:320]})['sources'].append(source_id)
    report['discovery_count'] = len(discovered)
    report['discoveries'] = sorted(discovered.values(), key=lambda x: x['repository'])[:limit]
    for item in report['discoveries']:
        item['sources'] = sorted(set(item['sources']))
    if report['discoveries']:
        state['seen_repositories'] = sorted(seen | {d['repository'] for d in report['discoveries']})
    return state, report


@contextmanager
def locked(path):
    lock = Path(str(path) + '.lock')
    lock.parent.mkdir(parents=True, exist_ok=True)
    try:
        stream = lock.open('x', encoding='utf-8')
    except FileExistsError as exc:
        raise ValueError('Another operation holds this file lock; inspect before removing a stale lock') from exc
    try:
        with stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        lock.unlink()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix=path.name + '.', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, indent=2, ensure_ascii=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--registry', type=Path, default=ROOT / 'config/capabilities.json')
    parser.add_argument('--state', type=Path, default=Path.home() / '.aos/capability-watch/state.json')
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('validate')
    sub.add_parser('list')
    refresh_parser = sub.add_parser('refresh', help='Default: discovery feeds; select original repositories with --tool')
    refresh_parser.add_argument('--tool', action='append', default=[])
    refresh_parser.add_argument('--source', action='append')
    refresh_parser.add_argument('--limit', type=int, default=50)
    refresh_parser.add_argument('--match', default='')
    refresh_parser.add_argument('--apply', action='store_true')
    record_parser = sub.add_parser('record', help='Import evaluator-authored evidence; never execute it')
    record_parser.add_argument('tool')
    record_parser.add_argument('--evidence', required=True, type=Path)
    record_parser.add_argument('--pin', action='store_true')
    record_parser.add_argument('--apply', action='store_true')
    status_parser = sub.add_parser('status')
    status_parser.add_argument('tool')
    status_parser.add_argument('status', choices=['ignore', 'watch', 'sandbox', 'production'])
    status_parser.add_argument('--reason', required=True)
    status_parser.add_argument('--apply', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.registry.resolve() == args.state.resolve():
            raise ValueError('Registry and observation state must be separate files')
        apply = getattr(args, 'apply', False)
        target = args.state if args.command == 'refresh' else args.registry
        with locked(target) if apply else nullcontext():
            registry = load_json(args.registry)
            validate_registry(registry)
            if args.command == 'validate':
                result = {'valid': True, 'candidates': len(registry['tools']), 'sources': len(registry['sources'])}
            elif args.command == 'list':
                result = registry
            elif args.command == 'refresh':
                previous = load_json(args.state) if args.state.exists() else {'sources': {}}
                state, result = refresh(registry, previous, tool_ids=args.tool, source_ids=args.source,
                                        limit=args.limit, match=args.match)
                if apply:
                    write_json(args.state, state)
            else:
                tool = next((t for t in registry['tools'] if t['id'] == args.tool), None)
                if tool is None:
                    raise ValueError('Unknown candidate')
                if args.command == 'record':
                    evidence = load_json(args.evidence)
                    record_evidence(tool, evidence)
                    if args.pin:
                        tool['pinned_version'] = evidence['version']
                else:
                    set_status(tool, args.status, args.reason)
                validate_registry(registry)
                if apply:
                    original = load_json(args.registry)
                    digest = hashlib.sha256(args.registry.read_bytes()).hexdigest()
                    write_json(args.state.parent / 'registry-backups' / (digest + '.json'), original)
                    write_json(args.registry, registry)
                result = {'applied': apply, 'candidate': tool}
        print(json.dumps(result, indent=2, ensure_ascii=True))
        return 1 if result.get('errors') else 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print('Capability workflow failed: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
