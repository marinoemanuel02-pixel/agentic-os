import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/voicestudio_run.py'


def load():
    spec = importlib.util.spec_from_file_location('voicestudio_run', SCRIPT)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


class VoiceLauncherTests(unittest.TestCase):
    def fixture(self, folder):
        home = Path(folder); root = home / '.aos/tools/stack/voicestudio'
        for file in ('app/VoiceStudio.exe', 'profile/runtime/project/.venv/Scripts/python.exe',
                     'profile/runtime/project/backend/main.py'):
            path = root / file; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('fixture')
        return home, root

    def test_existing_cached_runtime_is_explicit_and_environment_is_child_only(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            home, root = self.fixture(folder)
            original = {'ELECTRON_RUN_AS_NODE': '1', 'VOICESTUDIO_SKIP_BACKEND': '1', 'FAKE_API_KEY': 'private-fixture'}
            command, env = module.plan(home=home, environment=original)
            self.assertNotIn('ELECTRON_RUN_AS_NODE', env)
            self.assertNotIn('VOICESTUDIO_SKIP_BACKEND', env)
            self.assertNotIn('FAKE_API_KEY', env)
            self.assertEqual(original['ELECTRON_RUN_AS_NODE'], '1')
            backend = json.loads(env['OMNIVOICE_BACKEND_CMD'])
            self.assertEqual(backend[:3], [str(root / 'profile/runtime/project/.venv/Scripts/python.exe'), '-m', 'uvicorn'])
            self.assertEqual(backend[backend.index('--app-dir') + 1], str(root / 'profile/runtime/project/backend'))
            self.assertEqual(backend[-4:], ['--host', '127.0.0.1', '--port', '3900'])
            self.assertIn('--user-data-dir=' + str(root / 'profile'), command)
            self.assertEqual(env['HF_HUB_OFFLINE'], '1')

    def test_unknown_or_partial_runtime_is_refused_without_installing_or_marking_it(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'cached'):
                module.plan(home=Path(folder), environment={})
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_plan_does_not_set_fake_runtime_or_model_markers(self):
        module = load()
        with tempfile.TemporaryDirectory() as folder:
            home, root = self.fixture(folder)
            before = sorted(str(p.relative_to(home)) for p in home.rglob('*'))
            module.plan(home=home, environment={})
            self.assertEqual(before, sorted(str(p.relative_to(home)) for p in home.rglob('*')))


if __name__ == '__main__':
    unittest.main()
