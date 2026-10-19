import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools' / 'stack.py'


class LauncherTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('stack_launcher', MODULE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_arguments_stay_literal_and_parent_environment_is_unchanged(self):
        before = dict(os.environ)
        registry = {'sample': {'command': ['{python}', '{home}/folder with spaces/tool.py'],
                               'env': {'SAMPLE': 'child-only'}}}
        command, env, cwd = self.module.plan('sample', ['a; echo injected', '$(no)'], registry,
                                              home=Path('fixture-home'))
        self.assertEqual(command[-2:], ['a; echo injected', '$(no)'])
        self.assertEqual(command[0], sys.executable)
        self.assertEqual(env['SAMPLE'], 'child-only')
        self.assertEqual(dict(os.environ), before)
        self.assertIsNone(cwd)

    def test_unknown_tool_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unknown tool'):
            self.module.plan('unknown', [], {})

    def test_unreviewed_router_entry_only_runs_help_or_version(self):
        registry = {'omniroute': {'command': ['node', 'omniroute.mjs']}}
        for arguments in [[], ['serve'], ['auth'], ['setup-codex'], ['providers', 'add']]:
            with self.assertRaisesRegex(ValueError, 'review'):
                self.module.plan('omniroute', arguments, registry)
        for arguments in [['--help'], ['--version'], ['serve', '--help']]:
            command, _, _ = self.module.plan('omniroute', arguments, registry)
            self.assertEqual(command[-len(arguments):], arguments)

    def test_watch_never_selects_an_inherited_cloud_backend(self):
        registry = {'watch': {'command': ['{python}', 'watch.py'],
                              'fixed_args': ['--engine', 'local', '--no-whisper']}}
        command, _, _ = self.module.plan('watch', ['movie.mp4'], registry)
        self.assertEqual(command[-3:], ['--engine', 'local', '--no-whisper'])
        for args in [['movie.mp4', '--engine', 'gemini'], ['movie.mp4', '--engine=auto'],
                     ['movie.mp4', '--whisper', 'openai']]:
            with self.assertRaisesRegex(ValueError, 'local'):
                self.module.plan('watch', args, registry)

    def test_document_conversion_refuses_hosted_ocr(self):
        registry = {'anydoc': {'command': ['anydoc']}}
        for args in [['scan.pdf', '--ocr', 'hosted'], ['scan.pdf', '--ocr=hosted']]:
            with self.assertRaisesRegex(ValueError, 'OCR'):
                self.module.plan('anydoc', args, registry)

    def test_child_exit_and_stderr_are_preserved(self):
        registry = {'failure': {'command': ['{python}', '-c',
                    'import sys; print("expected diagnostic", file=sys.stderr); sys.exit(17)']}}
        result = self.module.run('failure', [], registry)
        self.assertEqual(result, 17)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('route_worker', MODULE.with_name('omniroute_worker.py'))
        self.worker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.worker)

    def test_worker_refuses_non_loopback_and_credential_urls(self):
        for endpoint in ['https://example.com/v1', 'http://user:pass@127.0.0.1/v1',
                         'http://127.0.0.1/v1?key=abc']:
            with self.assertRaises(ValueError):
                self.worker.validate_endpoint(endpoint)

    def test_worker_needs_reviewed_activation_and_explicit_credential(self):
        for env in [{}, {'OMNIROUTE_WORKER_ENABLED': '1'}, {'OMNIROUTE_WORKER_KEY': 'fixture'}]:
            with self.assertRaises(ValueError):
                self.worker.activation_key(env)

    def test_worker_handles_one_response_without_tools_or_retries(self):
        import json
        received = []
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                received.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
                data = json.dumps({'model': 'fixture-route', 'choices': [{'message': {'content': 'candidate answer'},
                                   'finish_reason': 'stop'}], 'usage': {'total_tokens': 3}}).encode()
                self.send_response(200); self.end_headers(); self.wfile.write(data)
        with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            try:
                result = self.worker.request(f'http://127.0.0.1:{server.server_port}/v1',
                                             'fixture-route', 'bounded fixture', 'public-fixture')
                self.assertEqual(result['text'], 'candidate answer')
                self.assertTrue(result['complete'])
                self.assertEqual(len(received), 1)
                self.assertNotIn('tools', received[0])
            finally: server.shutdown(); thread.join()

    def test_worker_rejects_tool_calls_and_incomplete_payloads(self):
        for message in [{'content': '', 'tool_calls': [{'id': 'x'}]}, {'content': None}, {}]:
            with self.assertRaises(ValueError):
                self.worker.parse_response({'choices': [{'message': message, 'finish_reason': 'stop'}]})

    def test_worker_preserves_an_existing_candidate(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'candidate.json'; target.write_text('keep', encoding='utf-8')
            with self.assertRaises(FileExistsError): self.worker.save_candidate(target, {'text': 'replace'})
            self.assertEqual(target.read_text(encoding='utf-8'), 'keep')


if __name__ == '__main__':
    unittest.main()
