"""Pool failure paths: no real model, credentials or external network."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import pool_core as core
import test_pool as fixtures
from test_pool import Fake, SOURCE, FIELDS


@contextmanager
def endpoint(response, redirect=False):
    hits = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            hits.append(self.rfile.read(int(self.headers.get('Content-Length', 0))))
            if redirect:
                self.send_response(302)
                self.send_header('Location', '/redirected')
                self.end_headers()
            else:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode('utf-8'))

        def do_GET(self):
            hits.append(b'redirect followed')
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"message":{"content":"redirected"}}')

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield 'http://127.0.0.1:%d' % server.server_port, hits
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


class TransportTests(unittest.TestCase):
    def backend(self, url):
        backend = core.Backends()
        backend.config.update(url=url, model='test-only')
        return backend

    def test_private_transport_never_follows_redirect(self):
        with endpoint({}, redirect=True) as (url, hits):
            with self.assertRaises(core.RouteError):
                self.backend(url).local_chat('private input')
            self.assertEqual(len(hits), 1)

    def test_private_transport_bypasses_environment_proxy(self):
        with endpoint({'message': {'content': 'direct'}}) as (url, hits):
            with endpoint({'message': {'content': 'proxy'}}) as (proxy, proxy_hits):
                env = {key: proxy for key in ('http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY')}
                env.update(no_proxy='', NO_PROXY='')
                with patch.dict(os.environ, env):
                    answer, _ = self.backend(url).local_chat('private input')
                self.assertEqual(answer, 'direct')
                self.assertEqual(len(hits), 1)
                self.assertEqual(proxy_hits, [])

    def test_malformed_chat_response_is_route_error(self):
        for response in ({}, {'message': {}}, {'message': {'content': None}}, []):
            with self.subTest(response=response), endpoint(response) as (url, _):
                with self.assertRaises(core.RouteError):
                    self.backend(url).local_chat('input')

    def test_malformed_embedding_response_is_route_error(self):
        for response in ({}, {'embeddings': []}, {'embeddings': [[1], [1, 2]]},
                         {'embeddings': [[True], [1]]}, {'embeddings': [[float('nan')], [1]]}):
            with self.subTest(response=response), endpoint(response) as (url, _):
                with self.assertRaises(core.RouteError):
                    self.backend(url).local_embed(['one', 'two'])

    def test_cloud_admission_failure_is_route_error(self):
        with patch('swarm_config.load_registry', side_effect=ValueError('test invalid registry')):
            with self.assertRaises(core.RouteError):
                core.Backends().cloud_text('public input')


class ValidationTests(unittest.TestCase):
    setUp = fixtures.PoolTests.setUp
    tearDown = fixtures.PoolTests.tearDown
    def test_public_variants_preserve_local_candidate_on_cloud_failure(self):
        class Broken(Fake):
            def cloud_text(self, *args, **kwargs):
                return core.Backends().cloud_text('public input')
        with patch('swarm_config.load_registry', side_effect=ValueError('invalid registry')):
            result = core.variants(Broken(local=['{"variants":["one"]}']), 'brief', n=1, privacy='public')
        self.assertEqual(result['variants'][0]['text'], 'one')
        self.assertTrue(result['checks']['errors'])

    def test_variant_string_is_not_a_list_of_candidates(self):
        with self.assertRaises(core.RouteError):
            core.variants(Fake(local=['{"variants":"abc"}']), 'brief', n=2)

    def test_triage_never_silently_omits_inputs(self):
        class Short(Fake):
            def local_embed(self, texts):
                return [[1, 0], [0, 1]], {'route': 'local'}
        with self.assertRaises(core.RouteError):
            core.triage(Short(), ['missing'], ['one', 'two'])

    def test_triage_skips_oversize_tie_break_prompt(self):
        fake = Fake(local=['{"label":"b"}'], embed=lambda _: [1, 0])
        result = core.triage(fake, ['x'], ['"' * 39000, 'b'])
        self.assertEqual(fake.calls, ['embed'])
        self.assertEqual(result['checks']['low_margin_items'], [0])

    def test_local_transport_budget_includes_system_and_format(self):
        backend = core.Backends()
        backend.config['model'] = 'test-only'
        with patch.object(backend, '_post', return_value={'message': {'content': 'answer'}}) as posted:
            with self.assertRaises(ValueError):
                backend.local_chat('x' * (core.LOCAL_MAX_CHARS - 100))
            posted.assert_not_called()

    def test_local_budget_includes_schema_and_prompt(self):
        fake = Fake(local=['{"x":null}'])
        with self.assertRaises(ValueError):
            core.extract(fake, 'x' * (core.LOCAL_MAX_CHARS - 5), fields={'x': 'x' * 100})
        self.assertEqual(fake.calls, [])

    def test_cloud_budget_uses_complete_utf8_packet(self):
        fake = Fake(local=['not json'], cloud=['{"x":null}'])
        result = core.extract(fake, '\u754c' * 15000, fields={'x': 'absent'}, privacy='public')
        self.assertEqual(fake.calls, ['local'])
        self.assertEqual(result['verdict'], 'review')

    def test_empty_summary_requires_review(self):
        self.assertEqual(core.summarize(Fake(local=['']), SOURCE)['verdict'], 'review')

    def test_feedback_rejects_non_boolean_and_unknown_results(self):
        call = core.extract(Fake(local=['{"citta":"Verona","casse":"42","data_rilascio":null}']), SOURCE, FIELDS)
        with self.assertRaises(ValueError):
            core.feedback(call['id'], 'false')
        with self.assertRaises(ValueError):
            core.feedback('unknown-result', True)
        self.assertEqual(core.feedback()['stats']['extract:local']['judged'], 0)


if __name__ == '__main__':
    unittest.main()
