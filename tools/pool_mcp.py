"""MCP stdio server for the free-resource layer (pool_core). Standard library only.

Registered for both agents by `aos sync` through config/mcp.json. Messages are newline-delimited
JSON-RPC 2.0 on stdin/stdout; nothing else may be written to stdout.
"""
import json
from pathlib import Path
import sys
import traceback

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pool_core as core

# Versions whose tool surface this server implements (tools/list, tools/call, ping); newest first.
VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05']

PRIVACY = {'type': 'string', 'enum': ['private', 'public'], 'default': 'private',
           'description': 'private = local model only (default; use for anything not already public). '
                          'public = the free API pool may also be used (published sources, scripts meant for release).'}

TOOLS = [
    {'name': 'pool_extract',
     'description': 'Default first step for pulling facts, fields, dates, numbers or quotes out of a document, page, '
                    'transcript or log you were given. Runs on the local model (free API pool as fallback when public) '
                    'and checks the JSON shape and that every value occurs in the source. Use it instead of reading '
                    'the whole text yourself; verdict "review" lists the paths to check.',
     'inputSchema': {'type': 'object', 'required': ['source'], 'properties': {
         'source': {'type': 'string', 'description': 'The text to extract from (under 40,000 chars).'},
         'fields': {'type': 'object', 'additionalProperties': {'type': 'string'},
                    'description': 'Field name -> what it means. Values come back as strings or null.'},
         'schema': {'type': 'object', 'description': 'A JSON schema instead of fields, for nested or typed results. '
                    'Checked keywords: type, properties, required, additionalProperties false, items, enum; '
                    'others (pattern, minLength, ...) are not checked.'},
         'grounded': {'type': 'boolean', 'default': True,
                      'description': 'Check that every value appears in the source (turn off for derived values).'},
         'privacy': PRIVACY}}},
    {'name': 'pool_triage',
     'description': 'Default for sorting many short texts (files, messages, search hits, issues, clips, claims) into '
                    'labels before you read them. Local embeddings plus a local-model tie-break; nothing leaves the '
                    'machine. Low-margin items are listed for a spot check.',
     'inputSchema': {'type': 'object', 'required': ['items', 'labels'], 'properties': {
         'items': {'type': 'array', 'items': {'type': 'string'}, 'description': '1..200 short texts.'},
         'labels': {'type': 'array', 'items': {'type': 'string'},
                    'description': '1..30 labels written as short descriptive phrases.'},
         'privacy': PRIVACY}}},
    {'name': 'pool_variants',
     'description': 'Default for generating options to choose from: titles, hooks, phrasings, names, prompts, test '
                    'ideas, shot ideas. Local model, plus the free API pool when public; duplicates removed. You pick.',
     'inputSchema': {'type': 'object', 'required': ['brief'], 'properties': {
         'brief': {'type': 'string', 'description': 'What to vary and the constraints.'},
         'n': {'type': 'integer', 'minimum': 1, 'maximum': 12, 'default': 5},
         'privacy': PRIVACY}}},
    {'name': 'pool_crosscheck',
     'description': 'Default first pass on whether supplied sources support specific claims (fact checks, script '
                    'claims, citations). Each verdict needs an exact quote found in the cited source or it is '
                    'downgraded to not_found, and a "supported" quote must carry the claim\'s numbers and names or '
                    'it becomes "unclear"; with privacy public the free API pool votes independently and '
                    'disagreements come back as "disputed". You still decide.',
     'inputSchema': {'type': 'object', 'required': ['claims', 'sources'], 'properties': {
         'claims': {'type': 'array', 'items': {'type': 'string'}, 'description': '1..20 claims.'},
         'sources': {'type': 'array', 'items': {'type': 'object', 'required': ['id', 'text'], 'properties': {
             'id': {'type': 'string'}, 'text': {'type': 'string'}, 'url': {'type': 'string'}}}},
         'privacy': PRIVACY}}},
    {'name': 'pool_summarize',
     'description': 'Default for condensing a long text you only need the gist of (logs, transcripts, docs, '
                    'threads). Local model; flags numbers in the summary that are not in the source.',
     'inputSchema': {'type': 'object', 'required': ['text'], 'properties': {
         'text': {'type': 'string', 'description': 'Under 40,000 chars; split longer text.'},
         'focus': {'type': 'string'}, 'max_words': {'type': 'integer', 'default': 150},
         'privacy': PRIVACY}}},
    {'name': 'pool_feedback',
     'description': 'Report whether a pool result was usable (id from the result, accepted true/false), and read '
                    'per-tool acceptance stats. Call it after you used or rejected a pool result.',
     'inputSchema': {'type': 'object', 'properties': {
         'id': {'type': 'string'}, 'accepted': {'type': 'boolean'}, 'note': {'type': 'string'}}}},
]


def call_tool(name, args, backends):
    privacy = args.get('privacy', 'private')
    if name == 'pool_extract':
        return core.extract(backends, args['source'], args.get('fields'), args.get('schema'), privacy, args.get('grounded', True))
    if name == 'pool_triage':
        return core.triage(backends, args['items'], args['labels'], privacy)
    if name == 'pool_variants':
        return core.variants(backends, args['brief'], args.get('n', 5), privacy)
    if name == 'pool_crosscheck':
        return core.crosscheck(backends, args['claims'], args['sources'], privacy)
    if name == 'pool_summarize':
        return core.summarize(backends, args['text'], args.get('focus', ''), args.get('max_words', 150), privacy)
    if name == 'pool_feedback':
        return core.feedback(args.get('id'), args.get('accepted'), args.get('note', ''))
    raise KeyError(name)


def handle(message, backends):
    method, mid = message.get('method'), message.get('id')
    if 'id' not in message:
        return None                                   # notification
    if method == 'initialize':
        version = (message.get('params') or {}).get('protocolVersion')
        if version not in VERSIONS:
            version = VERSIONS[0]
        result = {'protocolVersion': version, 'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'aos-pool', 'version': '1.0.0'}}
    elif method == 'ping':
        result = {}
    elif method == 'tools/list':
        result = {'tools': TOOLS}
    elif method == 'tools/call':
        params = message.get('params') or {}
        try:
            output = call_tool(params.get('name'), params.get('arguments') or {}, backends)
            result = {'content': [{'type': 'text', 'text': json.dumps(output, ensure_ascii=False, indent=1)}],
                      'isError': False}
        except KeyError as error:
            if params.get('name') not in {t['name'] for t in TOOLS}:
                return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32602, 'message': 'unknown tool'}}
            result = {'content': [{'type': 'text', 'text': 'missing argument: ' + str(error)}], 'isError': True}
        except (ValueError, TypeError, core.RouteError) as error:
            result = {'content': [{'type': 'text', 'text': str(error)}], 'isError': True}
    else:
        return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': 'method not found'}}
    return {'jsonrpc': '2.0', 'id': mid, 'result': result}


def main():
    stdin = open(sys.stdin.fileno(), 'r', encoding='utf-8', errors='replace', newline='\n', closefd=False)
    stdout = open(sys.stdout.fileno(), 'w', encoding='utf-8', newline='\n', closefd=False)
    backends = core.Backends()
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            message = None
        if not isinstance(message, dict):
            reply = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'parse error'}}
        else:
            try:
                reply = handle(message, backends)
            except Exception:                         # keep serving; the trace goes to stderr only
                traceback.print_exc(file=sys.stderr)
                reply = None if message.get('id') is None else {
                    'jsonrpc': '2.0', 'id': message['id'], 'error': {'code': -32603, 'message': 'internal error'}}
        if reply is not None:
            stdout.write(json.dumps(reply, ensure_ascii=False) + '\n')
            stdout.flush()


if __name__ == '__main__':
    main()
