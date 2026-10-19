import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

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

    def test_router_uses_its_isolated_wrapper_after_user_review_exception(self):
        registry = {'omniroute': {'command': ['node', 'omniroute.mjs']}}
        for arguments in [['serve'], ['--help'], ['--version'], ['serve', '--help']]:
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

    def test_worker_needs_an_explicit_scoped_credential(self):
        for env in [{}, {'OMNIROUTE_WORKER_KEY': 'bad\nheader'}]:
            with self.assertRaises(ValueError):
                self.worker.activation_key(env)
        self.assertEqual(self.worker.activation_key({'OMNIROUTE_WORKER_KEY': 'public-fixture'}), 'public-fixture')

    def test_worker_handles_one_response_without_tools_or_retries(self):
        import json
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            'model': 'fixture-route', 'choices': [{'message': {'content': 'candidate answer'},
            'finish_reason': 'stop'}], 'usage': {'total_tokens': 3}}).encode()
        with patch.object(self.worker.urllib.request, 'build_opener') as factory:
            factory.return_value.open.return_value = response
            result = self.worker.request('http://127.0.0.1:1234/v1',
                                         'fixture-route', 'bounded fixture', 'public-fixture')
            self.assertEqual(result['text'], 'candidate answer')
            self.assertTrue(result['complete'])
            factory.return_value.open.assert_called_once()
            sent = factory.return_value.open.call_args.args[0]
            self.assertNotIn('tools', json.loads(sent.data))
            self.assertEqual(sent.full_url, 'http://127.0.0.1:1234/v1/chat/completions')

    def test_worker_http_failure_does_not_retry_or_echo_credentials(self):
        import urllib.error
        with patch.object(self.worker.urllib.request, 'build_opener') as factory:
            factory.return_value.open.side_effect = urllib.error.HTTPError(
                'http://127.0.0.1/v1', 401, 'private fixture details', {}, None)
            with self.assertRaisesRegex(ValueError, 'HTTP 401') as caught:
                self.worker.request('http://127.0.0.1/v1', 'fixture-route', 'packet', 'fixture-credential')
            self.assertNotIn('private fixture', str(caught.exception))
            self.assertNotIn('fixture-credential', str(caught.exception))
            factory.return_value.open.assert_called_once()

    def test_worker_rejects_tool_calls_and_incomplete_payloads(self):
        for message in [{'content': '', 'tool_calls': [{'id': 'x'}]}, {'content': None}, {}]:
            with self.assertRaises(ValueError):
                self.worker.parse_response({'choices': [{'message': message, 'finish_reason': 'stop'}]})
        for payload in [None, [], {'choices': [None]}, {'choices': [{'message': []}]}]:
            with self.assertRaises(ValueError): self.worker.parse_response(payload)

    def test_worker_preserves_an_existing_candidate(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'candidate.json'; target.write_text('keep', encoding='utf-8')
            with self.assertRaises(FileExistsError): self.worker.save_candidate(target, {'text': 'replace'})
            self.assertEqual(target.read_text(encoding='utf-8'), 'keep')


class RouterEnvironmentTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('router_env', MODULE.with_name('omniroute_env.py'))
        self.router = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.router)

    def test_help_does_not_open_the_secret_store(self):
        with patch.object(self.router, 'load_secrets') as secrets:
            _, env = self.router.plan(['--help'], home=Path('fixture-home'))
            secrets.assert_not_called()
            self.assertEqual(env['REQUIRE_API_KEY'], 'true')
            self.assertEqual(env['OMNIROUTE_SERVER_HOST'], '127.0.0.1')

    def test_server_uses_child_only_keys_and_no_daemon(self):
        before = dict(os.environ)
        with patch.object(self.router, 'load_secrets', return_value={'JWT_SECRET': 'public-fixture'}):
            command, env = self.router.plan(['serve'], home=Path('fixture-home'))
        self.assertEqual(env['JWT_SECRET'], 'public-fixture')
        self.assertIn('--no-open', command)
        self.assertIn('--no-tray', command)
        self.assertIn('--no-recovery', command)
        self.assertEqual(dict(os.environ), before)
        self.assertNotIn('public-fixture', ' '.join(command))

    def test_export_and_background_options_are_refused(self):
        for args in [['auth'], ['serve', '--daemon'], ['serve', '--tray']]:
            with self.assertRaises(ValueError): self.router.plan(args)

    def test_corrupt_secret_output_is_not_echoed(self):
        result = MagicMock(returncode=0, stdout='sensitive fixture invalid JSON', stderr='')
        with patch.object(self.router.subprocess, 'run', return_value=result):
            with self.assertRaises(ValueError) as caught: self.router.load_secrets(Path('repo'))
        self.assertNotIn('sensitive fixture', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
