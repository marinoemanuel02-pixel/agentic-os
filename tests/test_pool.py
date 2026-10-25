"""Free-resource layer: built-in checks, routing by privacy, ledger and the MCP stdio protocol.
No real model, credentials or network: a fake backend object and a loopback fake Ollama."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import pool_core as core


class Fake:
    def __init__(self, local=None, cloud=None, embed=None):
        self.local, self.cloud, self.embed = list(local or []), list(cloud or []), embed
        self.calls = []

    def local_chat(self, prompt, schema=None, max_tokens=1024):
        self.calls.append('local')
        return self.local.pop(0), {'route': 'local', 'model': 'fake-local'}

    def cloud_text(self, prompt, max_tokens=1024):
        self.calls.append('cloud')
        if not self.cloud:
            raise core.RouteError('no cloud')
        return self.cloud.pop(0), {'route': 'cloud', 'model': 'fake-cloud'}

    def local_embed(self, texts):
        self.calls.append('embed')
        return [self.embed(t) for t in texts], {'route': 'local', 'model': 'fake-embed'}


SOURCE = 'Il deposito di Verona ha 42 casse. La consegna e prevista a marzo.'
FIELDS = {'citta': 'city', 'casse': 'crates', 'data_rilascio': 'release date'}


class PoolTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ['AOS_POOL_DIR'] = self.tmp.name

    def tearDown(self):
        os.environ.pop('AOS_POOL_DIR', None)
        self.tmp.cleanup()

    def test_extract_passes_when_grounded_and_keeps_unknown_null(self):
        fake = Fake(local=['{"citta": "Verona", "casse": "42", "data_rilascio": null}'])
        result = core.extract(fake, SOURCE, FIELDS)
        self.assertEqual(result['verdict'], 'pass')
        self.assertIsNone(result['data']['data_rilascio'])
        self.assertEqual(fake.calls, ['local'])

    def test_extract_flags_invented_value(self):
        fake = Fake(local=['{"citta": "Milano", "casse": "42", "data_rilascio": null}'])
        result = core.extract(fake, SOURCE, FIELDS)
        self.assertEqual(result['verdict'], 'review')
        self.assertEqual(result['checks']['ungrounded'], ['$.citta'])

    def test_private_never_calls_cloud_even_when_local_fails(self):
        fake = Fake(local=['not json'], cloud=['{"citta": "Verona", "casse": "42", "data_rilascio": null}'])
        result = core.extract(fake, SOURCE, FIELDS, privacy='private')
        self.assertNotIn('cloud', fake.calls)
        self.assertEqual(result['verdict'], 'review')

    def test_public_falls_back_to_cloud_and_keeps_better_answer(self):
        fake = Fake(local=['{"citta": "Roma", "casse": "7"}'],
                    cloud=['```json\n{"citta": "Verona", "casse": "42", "data_rilascio": null}\n```'])
        result = core.extract(fake, SOURCE, FIELDS, privacy='public')
        self.assertEqual(fake.calls, ['local', 'cloud'])
        self.assertEqual(result['verdict'], 'pass')
        self.assertEqual(result['model']['route'], 'cloud')

    def test_schema_errors_are_reported(self):
        schema = {'type': 'object', 'required': ['n'], 'properties': {'n': {'type': 'integer'}}}
        fake = Fake(local=['{"n": "quarantadue"}'])
        result = core.extract(fake, SOURCE, schema=schema, grounded=False)
        self.assertEqual(result['verdict'], 'review')
        self.assertTrue(result['checks']['schema_errors'])

    def test_bad_privacy_and_oversize_are_refused(self):
        with self.assertRaises(ValueError):
            core.extract(Fake(), SOURCE, FIELDS, privacy='cloud')
        with self.assertRaises(ValueError):
            core.extract(Fake(), 'x' * (core.LOCAL_MAX_CHARS + 1), FIELDS)

    def test_crosscheck_downgrades_quote_not_in_source(self):
        fake = Fake(local=['{"verdict": "supported", "source_id": "s1", "quote": "Verona ha 99 casse"}'])
        result = core.crosscheck(fake, ['Verona ha 99 casse'], [{'id': 's1', 'text': SOURCE}])
        row = result['claims'][0]
        self.assertEqual(row['verdict'], 'not_found')
        self.assertIn('downgraded', row['local'])

    def test_crosscheck_public_disagreement_is_disputed(self):
        fake = Fake(local=['{"verdict": "supported", "source_id": "s1", "quote": "Il deposito di Verona ha 42 casse."}'],
                    cloud=['{"verdict": "contradicted", "source_id": "s1", "quote": "Il deposito di Verona ha 42 casse."}'])
        result = core.crosscheck(fake, ['Verona ha 42 casse'], [{'id': 's1', 'text': SOURCE}], privacy='public')
        self.assertEqual(result['claims'][0]['verdict'], 'disputed')
        self.assertEqual(result['verdict'], 'review')

    def test_triage_uses_embeddings_and_llm_only_for_ties(self):
        vectors = {'audio': [1, 0], 'fonti': [0, 1], 'voce lenta': [0.9, 0.1], 'boh': [0.5, 0.5]}
        fake = Fake(local=['{"label": "fonti"}'], embed=lambda t: vectors[t])
        result = core.triage(fake, ['voce lenta', 'boh'], ['audio', 'fonti'])
        self.assertEqual([r['label'] for r in result['labels']], ['audio', 'fonti'])
        self.assertEqual(result['labels'][1]['method'], 'embed+llm')
        self.assertEqual(fake.calls.count('local'), 1)

    def test_variants_deduplicate_across_routes(self):
        fake = Fake(local=['{"variants": ["Uno", "Due"]}'], cloud=['{"variants": ["uno ", "Tre"]}'])
        result = core.variants(fake, 'titoli', n=3, privacy='public')
        self.assertEqual([v['text'] for v in result['variants']], ['Uno', 'Due', 'Tre'])
        self.assertEqual(result['verdict'], 'pass')

    def test_summarize_flags_numbers_not_in_source(self):
        fake = Fake(local=['Verona ha 43 casse.'])
        result = core.summarize(fake, SOURCE, max_words=20)
        self.assertEqual(result['checks']['numbers_not_in_source'], ['43'])
        self.assertEqual(result['verdict'], 'review')

    def test_ledger_logs_metadata_only_and_feedback_counts(self):
        fake = Fake(local=['{"citta": "Verona", "casse": "42", "data_rilascio": null}'])
        result = core.extract(fake, SOURCE, FIELDS)
        stats = core.feedback(result['id'], True)['stats']
        self.assertEqual(stats['extract:local']['accept_rate'], 1.0)
        ledger = (Path(self.tmp.name) / 'ledger.jsonl').read_text(encoding='utf-8')
        self.assertNotIn('Verona', ledger)


class FakeOllama(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path == '/api/chat':
            assert body['options']['num_ctx'] >= 16384
            reply = {'message': {'content': '{"citta": "Verona", "casse": "42", "data_rilascio": null}'}}
        else:
            reply = {'embeddings': [[1.0, 0.0] for _ in body['input']]}
        data = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class McpProtocolTests(unittest.TestCase):
    def test_stdio_session_lists_and_calls_tools(self):
        server = HTTPServer(('127.0.0.1', 0), FakeOllama)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, AOS_POOL_DIR=tmp, AOS_OLLAMA_URL='http://127.0.0.1:%d' % server.server_port,
                       PYTHONUTF8='1')
            messages = [
                {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}},
                {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
                {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
                {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
                 'params': {'name': 'pool_extract', 'arguments': {'source': SOURCE, 'fields': FIELDS}}},
                {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call',
                 'params': {'name': 'pool_extract', 'arguments': {'source': SOURCE, 'privacy': 'cloud'}}},
                'not json',
            ]
            stdin = '\n'.join(m if isinstance(m, str) else json.dumps(m) for m in messages) + '\n'
            script = Path(__file__).resolve().parents[1] / 'tools' / 'pool_mcp.py'
            done = subprocess.run([sys.executable, str(script)], input=stdin, capture_output=True,
                                  text=True, encoding='utf-8', env=env, timeout=60)
        server.shutdown()
        replies = [json.loads(line) for line in done.stdout.splitlines()]
        self.assertEqual([r['id'] for r in replies], [1, 2, 3, 4, None])
        self.assertEqual(replies[0]['result']['serverInfo']['name'], 'pool')
        names = {t['name'] for t in replies[1]['result']['tools']}
        self.assertIn('pool_crosscheck', names)
        call = json.loads(replies[2]['result']['content'][0]['text'])
        self.assertEqual(call['verdict'], 'pass')
        self.assertTrue(replies[3]['result']['isError'])
        self.assertEqual(replies[4]['error']['code'], -32700)


if __name__ == '__main__':
    unittest.main()
