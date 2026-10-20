from contextlib import closing
import importlib.util
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from unittest.mock import MagicMock

TOOLS = Path(__file__).resolve().parents[1] / 'tools'


def load(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RouterPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.database = Path(self.temp.name) / 'storage.sqlite'
        with closing(sqlite3.connect(self.database)) as db, db:
            db.execute('CREATE TABLE api_keys (id TEXT PRIMARY KEY, key TEXT, key_hash TEXT, '
                       'key_prefix TEXT, model_access_mode TEXT, allowed_models TEXT, '
                       'is_active INTEGER, is_banned INTEGER, revoked_at TEXT, expires_at TEXT, '
                       'allow_auto_combos INTEGER, allowed_combos TEXT, no_log INTEGER, auto_resolve INTEGER)')
            db.execute('INSERT INTO api_keys VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                       ('worker', 'old-fixture', hashlib.sha256(b'old-fixture').hexdigest(), 'old',
                        'restricted', '["openrouter/fixture/route:free"]', 1, 0, None, None, 1, '[]', 0, 1))

    def test_rotation_removes_plaintext_and_disables_automatic_routing(self):
        policy = load('omniroute_policy')
        events = []
        policy.harden_key(self.database, 'old-fixture', 'new-fixture',
                          lambda snapshot: events.append(('backup', bool(snapshot))),
                          lambda value: events.append(('store', value)))
        self.assertEqual(events, [('backup', True), ('store', 'new-fixture')])
        with closing(sqlite3.connect(self.database)) as db, db:
            row = db.execute('SELECT key,key_hash,allow_auto_combos,no_log,auto_resolve FROM api_keys').fetchone()
        self.assertNotIn('new-fixture', row)
        self.assertNotIn('old-fixture', row)
        self.assertEqual(row[1], hashlib.sha256(b'new-fixture').hexdigest())
        self.assertEqual(row[2:], (0, 1, 0))
        self.assertEqual(policy.allowed_routes(self.database, 'new-fixture'), ['openrouter/fixture/route:free'])
        with self.assertRaises(ValueError):
            policy.allowed_routes(self.database, 'old-fixture')

    def test_failed_encrypted_store_restores_database(self):
        policy = load('omniroute_policy')
        def store(value):
            if value == 'new-fixture':
                raise OSError('fixture failure')
        with self.assertRaises(OSError):
            policy.harden_key(self.database, 'old-fixture', 'new-fixture', lambda snapshot: None, store)
        with closing(sqlite3.connect(self.database)) as db, db:
            self.assertEqual(db.execute('SELECT key FROM api_keys').fetchone()[0], 'old-fixture')

    def test_hardening_refuses_a_running_gateway_before_loading_credentials(self):
        policy = load('omniroute_policy')
        with patch.object(policy, 'gateway_running', return_value=True), \
                patch.object(policy, 'load_worker') as loader, \
                patch.object(policy.sys, 'argv', ['policy', 'harden']):
            self.assertEqual(policy.main(), 1)
            loader.assert_not_called()

    def test_reenabled_prompt_logging_invalidates_worker_policy(self):
        policy = load('omniroute_policy')
        policy.harden_key(self.database, 'old-fixture', 'new-fixture', lambda s: None, lambda v: None)
        with closing(sqlite3.connect(self.database)) as db, db:
            db.execute('UPDATE api_keys SET no_log=0')
        with self.assertRaises(ValueError):
            policy.allowed_routes(self.database, 'new-fixture')

    def test_empty_wildcard_combo_paid_and_unrestricted_policies_are_refused(self):
        policy = load('omniroute_policy')
        for mode, models in [('all', '[]'), ('restricted', '[]'), ('restricted', '["*"]'),
                             ('restricted', '["auto"]'), ('restricted', '["openrouter/fixture/paid"]')]:
            with closing(sqlite3.connect(self.database)) as db, db:
                db.execute('UPDATE api_keys SET model_access_mode=?,allowed_models=?', (mode, models))
            with self.assertRaises(ValueError):
                policy.harden_key(self.database, 'old-fixture', 'new-fixture', lambda s: None, lambda v: None)

    def test_free_price_validation_requires_known_zero_fees(self):
        run = load('omniroute_run')
        route = 'openrouter/fixture/route:free'
        good = {'data': [{'id': 'fixture/route:free', 'pricing': {'prompt': '0', 'completion': '0', 'request': '0'}}]}
        self.assertEqual(run.verify_free_route(route, [route], good), route)
        for pricing in [{}, {'prompt': None, 'completion': '0'}, {'prompt': '0', 'completion': '0.1'},
                        {'prompt': '0', 'completion': '0', 'request': '1'}, {'prompt': 'NaN', 'completion': '0'}]:
            with self.assertRaises(ValueError):
                run.verify_free_route(route, [route], {'data': [{'id': 'fixture/route:free', 'pricing': pricing}]})
        with self.assertRaises(ValueError):
            run.verify_free_route('openrouter/other:free', [route], good)

    def test_worker_sends_zero_cost_no_fallback_preferences(self):
        worker = load('omniroute_worker')
        from unittest.mock import MagicMock
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            'choices': [{'message': {'content': 'candidate'}, 'finish_reason': 'stop'}]}).encode()
        with patch.object(worker.urllib.request, 'build_opener') as factory:
            factory.return_value.open.return_value = response
            worker.request('http://127.0.0.1:1234/v1', 'fixture-route', 'fixture packet', 'fixture-key')
            body = json.loads(factory.return_value.open.call_args.args[0].data)
            self.assertFalse(body['provider']['allow_fallbacks'])
            self.assertEqual(body['provider']['max_price'], {'prompt': 0, 'completion': 0, 'request': 0})


class RouterLifecycleTests(unittest.TestCase):
    def test_existing_server_is_never_stopped(self):
        run = load('omniroute_run')
        with patch.object(run, 'listening', return_value=True), patch.object(run, 'json_get', return_value={}), \
                patch.object(run.subprocess, 'Popen') as start, patch.object(run.subprocess, 'run') as stop:
            with run.gateway('http://127.0.0.1:20128/v1', 'fixture-key') as owned:
                self.assertFalse(owned)
            start.assert_not_called()
            stop.assert_not_called()

    def test_owned_server_is_stopped_when_startup_fails(self):
        run = load('omniroute_run')
        process = MagicMock(pid=12345)
        process.poll.return_value = None
        with patch.object(run, 'listening', return_value=False), \
                patch.object(run.omniroute_env, 'plan', return_value=(['fixture-command'], {})), \
                patch.object(run.subprocess, 'Popen', return_value=process), \
                patch.object(run.subprocess, 'run') as stop, \
                patch.object(run.time, 'monotonic', side_effect=[0, 181]):
            with self.assertRaisesRegex(ValueError, 'startup timed out'):
                with run.gateway('http://127.0.0.1:20128/v1', 'fixture-key'):
                    self.fail('Must not yield an unready gateway')
            if run.os.name == 'nt':
                self.assertEqual(stop.call_args.args[0], ['taskkill', '/PID', '12345', '/T', '/F'])
            else:
                process.terminate.assert_called_once()
            process.wait.assert_called_once()

    def test_existing_output_refuses_before_credentials_or_network(self):
        run = load('omniroute_run')
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'candidate.json'
            output.write_text('keep', encoding='utf-8')
            with patch.object(run.omniroute_policy, 'load_worker') as secret, patch.object(run, 'json_get') as network:
                with self.assertRaises(FileExistsError):
                    run.execute(Path('missing-packet'), output, 'http://127.0.0.1:20128/v1')
                secret.assert_not_called()
                network.assert_not_called()
            self.assertEqual(output.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
