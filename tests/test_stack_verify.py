import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/stack_verify.py'


def load():
    spec = importlib.util.spec_from_file_location('stack_verify', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class VerificationTests(unittest.TestCase):
    def test_selection_is_explicit_and_unknown_tools_fail_before_output_creation(self):
        module = load()
        self.assertEqual(module.select_tools(['watch', 'watch', 'rtk']), ['watch', 'rtk'])
        with self.assertRaisesRegex(ValueError, 'Unknown'):
            module.select_tools(['not-approved'])
        self.assertEqual(len(module.select_tools([])), 14)

    def test_existing_output_is_preserved(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'keep'; target.mkdir()
            (target / 'receipt.json').write_text('preserve')
            with self.assertRaises(FileExistsError):
                module.prepare_output(target)
            self.assertEqual((target / 'receipt.json').read_text(), 'preserve')

    def test_expected_nonzero_exit_requires_content_assertion(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            runner = module.Runner(Path(folder))
            result = runner.command('expected-refusal', [sys.executable, '-c',
                                    'import sys; print("known refusal"); sys.exit(3)'], expected=3)
            self.assertEqual(result['exit'], 3)
            self.assertIn('known refusal', result['stdout'])
            with self.assertRaises(module.CheckFailure):
                runner.command('wrong-exit', [sys.executable, '-c', 'raise SystemExit(7)'])

    def test_timeout_is_failure_not_success_even_if_exit_code_is_zero(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            runner = module.Runner(Path(folder))
            with self.assertRaisesRegex(module.CheckFailure, 'timed out'):
                runner.command('timeout', [sys.executable, '-c', 'import time; time.sleep(20)'], timeout=.1)
            metadata = json.loads((Path(folder) / 'timeout.run.json').read_text())
            self.assertTrue(metadata['timeout'])

    def test_skipped_and_blocked_never_become_passed(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            runner = module.Runner(Path(folder))
            with patch.dict(module.CHECKS, {'composio': lambda r: (_ for _ in ()).throw(module.Blocked('not connected'))}):
                row = runner.check('composio')
            self.assertEqual(row['status'], 'blocked')
            self.assertEqual(module.exit_status([row]), 2)
            self.assertEqual(module.exit_status([{'status': 'skipped'}]), 2)
            self.assertEqual(module.exit_status([{'status': 'failed'}]), 1)

    def test_child_environment_omits_inherited_credentials_and_keeps_home_caches(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            with patch.dict(module.os.environ, {'FAKE_API_KEY': 'fixture-key', 'AUTH_TOKEN': 'fixture-token'}):
                env = module.child_environment(Path(folder))
            self.assertNotIn('FAKE_API_KEY', env)
            self.assertNotIn('AUTH_TOKEN', env)
            self.assertEqual(env['HF_HUB_OFFLINE'], '1')
            self.assertEqual(Path(env['TEMP']), Path(folder) / 'tmp')

    def test_additional_provider_inference_is_explicitly_skipped_without_live(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            row = module.Runner(Path(folder)).check('omniroute')
        self.assertEqual(row['status'], 'skipped')


if __name__ == '__main__':
    unittest.main()
