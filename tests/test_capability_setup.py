"""Offline setup controls; never download or install real tools in tests."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/capability_setup.py'


class SetupTests(unittest.TestCase):
    def module(self):
        self.assertTrue(SCRIPT.exists(), 'explicit candidate setup has not been implemented')
        spec = importlib.util.spec_from_file_location('capability_setup', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def archive(self, name='tool.exe', content=b'fixture tool'):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr(name, content)
        return buffer.getvalue()

    def entry(self, payload):
        return {'version': '1.0', 'kind': 'archive', 'url': 'https://github.com/acme/tool/releases/download/v1/tool.zip',
                'sha256': hashlib.sha256(payload).hexdigest(), 'filename': 'tool.zip',
                'entrypoint': 'tool.exe', 'arguments': [], 'dependencies': [], 'env': {}}

    def test_preview_has_no_download_or_directory_side_effects(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'absent'
            result = module.install('fixture', self.entry(self.archive()), root, apply=False)
            self.assertFalse(root.exists())
            self.assertFalse(result['installed'])

    def test_pinned_archive_install_is_repeatable_and_detects_changed_executable(self):
        module = self.module()
        payload = self.archive()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def fetch(url, path): path.write_bytes(payload)
            first = module.install('fixture', self.entry(payload), root, apply=True, fetch=fetch)
            second = module.install('fixture', self.entry(payload), root, apply=True, fetch=fetch)
            self.assertEqual(first, second)
            executable = Path(first['entrypoint'])
            executable.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                module.install('fixture', self.entry(payload), root, apply=True, fetch=fetch)

    def test_wrong_digest_never_creates_a_ready_receipt(self):
        module = self.module()
        payload = self.archive()
        with tempfile.TemporaryDirectory() as folder:
            def fetch(url, path): path.write_bytes(b'incorrect')
            with self.assertRaises(ValueError):
                module.install('fixture', self.entry(payload), Path(folder), apply=True, fetch=fetch)
            self.assertFalse(list(Path(folder).rglob('receipt.json')))

    def test_archive_traversal_windows_drives_and_links_are_rejected(self):
        module = self.module()
        for name in ('../outside', '/outside', 'C:/outside', 'safe/../../outside', 'safe\\..\\outside'):
            with tempfile.TemporaryDirectory() as folder, self.subTest(name=name):
                archive = Path(folder) / 'fixture.zip'
                archive.write_bytes(self.archive(name))
                with self.assertRaises(ValueError): module.unpack(archive, Path(folder) / 'target')
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'fixture.zip'
            with zipfile.ZipFile(archive, 'w') as handle:
                info = zipfile.ZipInfo('symlink')
                info.create_system = 3
                info.external_attr = 0o120777 << 16
                handle.writestr(info, '../outside')
            with self.assertRaises(ValueError): module.unpack(archive, Path(folder) / 'target')

    def test_failed_package_install_is_not_ready(self):
        module = self.module()
        payload = b'package'
        entry = dict(self.entry(payload), kind='npm', filename='fixture.tgz', entrypoint='node_modules/fixture/cli.js')
        with tempfile.TemporaryDirectory() as folder:
            def fetch(url, path): path.write_bytes(payload)
            def execute(*args, **kwargs): raise OSError('fixture package manager failed')
            with self.assertRaises(OSError):
                module.install('fixture', entry, Path(folder), apply=True, fetch=fetch, execute=execute)
            self.assertFalse(list(Path(folder).rglob('receipt.json')))

    def test_launch_uses_literal_arguments_and_child_only_profile(self):
        module = self.module()
        payload = self.archive()
        with tempfile.TemporaryDirectory() as folder:
            def fetch(url, path): path.write_bytes(payload)
            receipt = module.install('fixture', self.entry(payload), Path(folder), apply=True, fetch=fetch)
            command, environment = module.launch_plan(receipt, self.entry(payload), ['literal;echo nope'])
            self.assertEqual(command[-1], 'literal;echo nope')
            self.assertIn('profile', environment['LOCALAPPDATA'])
            self.assertEqual(environment['AGENT_DESKTOP_HOME'], str(Path(receipt['runtime']) / 'profile/state'))
            self.assertEqual(command[0], receipt['entrypoint'])

    def test_wheel_cache_preserves_the_installable_distribution_filename(self):
        module = self.module()
        payload = b'wheel fixture'
        entry = dict(self.entry(payload), kind='wheel', filename='example-1.0-py3-none-any.whl',
                     entrypoint='venv/Scripts/tool.exe')
        commands = []
        with tempfile.TemporaryDirectory() as folder:
            def fetch(url, path): path.write_bytes(payload)
            def execute(command, **kwargs):
                commands.append(command)
                if command[1] == 'venv':
                    scripts = Path(command[-1]) / 'Scripts'
                    scripts.mkdir(parents=True)
                    (scripts / 'tool.exe').write_bytes(b'fixture')
            module.install('fixture', entry, Path(folder), apply=True, fetch=fetch, execute=execute)
            self.assertEqual(Path(commands[-1][-1]).name, entry['filename'])

    def test_manifest_rejects_unknown_kinds_unpinned_hashes_and_paths(self):
        module = self.module()
        for mutation in ('kind', 'hash', 'path', 'version'):
            entry = self.entry(self.archive())
            if mutation == 'kind': entry['kind'] = 'shell'
            if mutation == 'hash': entry['sha256'] = 'latest'
            if mutation == 'path': entry['entrypoint'] = '../outside.exe'
            if mutation == 'version': entry['version'] = '../../outside'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): module.validate_entry(entry)

    def test_check_rejects_changed_manifest_and_escaped_receipt(self):
        module = self.module()
        payload = self.archive()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            entry = self.entry(payload)
            def fetch(url, path): path.write_bytes(payload)
            receipt = module.install('fixture', entry, root, apply=True, fetch=fetch)
            config = root / 'config'
            config.mkdir()
            (config / 'capability-tools.json').write_text(json.dumps({'tools': {'fixture': dict(entry, sha256='0'*64)}}))
            with patch.object(module, 'REPO', root):
                self.assertEqual(module.main(['--root', str(root), 'check', 'fixture']), 2)
            escaped = dict(receipt, entrypoint=str(root / 'outside.exe'))
            (root / 'outside.exe').write_bytes(b'fixture tool')
            with self.assertRaises(ValueError):
                module.validate_receipt('fixture', entry, root, escaped)

    def test_windows_batch_launch_is_refused_before_shell_interpretation(self):
        module = self.module()
        for suffix in ('.bat', '.cmd', '.BAT'):
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                module.launch_plan({'runtime': 'fixture', 'entrypoint': 'fixture' + suffix},
                                   self.entry(self.archive()), ['x&echo.SETUP_ARGUMENT_EXECUTED'])

    def test_npm_setup_does_not_launch_a_windows_batch_shim(self):
        module = self.module()
        payload = b'package'
        entry = dict(self.entry(payload), kind='npm', filename='fixture.tgz', entrypoint='node_modules/fixture/cli.js')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            npm = root / 'node_modules/npm/bin/npm-cli.js'
            npm.parent.mkdir(parents=True)
            npm.write_text('fixture')
            def fetch(url, path): path.write_bytes(payload)
            def execute(command, **kwargs):
                self.assertFalse(command[0].endswith('.cmd'))
                self.assertIn(str(npm), command)
                output = root / 'fixture/1.0/node_modules/fixture/cli.js'
                output.parent.mkdir(parents=True)
                output.write_text('fixture')
            with patch.object(module.shutil, 'which', side_effect=lambda name: str(root / 'npm.cmd') if name.startswith('npm') else 'node.exe'):
                module.install('fixture', entry, root, apply=True, fetch=fetch, execute=execute)

    def test_prepared_routes_use_checked_on_demand_launcher(self):
        module = self.module()
        routes = json.loads((SCRIPT.parents[1] / 'config/stack-tools.json').read_text())['tools']
        manifest = json.loads((SCRIPT.parents[1] / 'config/capability-tools.json').read_text())['tools']
        for tool in ('rea', 'pdfcraft', 'blender-agent-sdk', 'logisheets', 'filmcraft', 'photocraft', 'agent-desktop'):
            module.validate_entry(manifest[tool])
            self.assertEqual(routes[tool]['command'][-2:], ['run', tool])
            self.assertIn('{repo}/tools/capability_setup.py', routes[tool]['command'])

    def test_dependency_receipt_cannot_disable_validation(self):
        module = self.module()
        payload = self.archive()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            dep = self.entry(payload)
            app = dict(dep, dependencies=['dependency'])
            def fetch(url, path): path.write_bytes(payload)
            receipt = module.install('dependency', dep, root, apply=True, fetch=fetch)
            module.install('fixture', app, root, apply=True, fetch=fetch)
            receipt['installed'] = False
            Path(receipt['entrypoint']).write_bytes(b'altered')
            (Path(receipt['runtime']) / 'receipt.json').write_text(json.dumps(receipt))
            (root / 'config').mkdir()
            (root / 'config/capability-tools.json').write_text(json.dumps({'tools':{'fixture':app,'dependency':dep}}))
            with patch.object(module, 'REPO', root):
                self.assertEqual(module.main(['--root',str(root),'check','fixture']),2)

    def test_windows_path_normalization_cannot_hide_parent_components(self):
        module = self.module()
        for name in ('safe/.. /outside', 'safe/. /outside', 'safe/folder./outside'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                module.safe_path(name)

    def test_blender_discovery_uses_numeric_versions(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for version in ('4.9', '4.10', '10.0'):
                executable = root / 'Blender Foundation' / ('Blender ' + version) / 'blender.exe'
                executable.parent.mkdir(parents=True)
                executable.touch()
            self.assertEqual(module.find_blender(root).parent.name, 'Blender 10.0')
            (root / 'Blender Foundation/Blender 10.0/blender.exe').unlink()
            self.assertEqual(module.find_blender(root).parent.name, 'Blender 4.10')
            with patch.dict(module.os.environ, {'ProgramFiles': str(root / 'missing')}):
                with self.assertRaisesRegex(ValueError, 'Blender was not found'):
                    module.launch_plan({'runtime':str(root),'entrypoint':'fixture.exe'},
                                       dict(self.entry(self.archive()), env={'BLENDER':'{blender}'}), [])

    def test_corrupt_pinned_archive_returns_a_controlled_failure(self):
        module = self.module()
        payload = b'not an archive, but the expected pinned bytes'
        entry = self.entry(payload)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'config').mkdir()
            (root / 'config/capability-tools.json').write_text(json.dumps({'tools':{'fixture':entry}}))
            def fetch(url, path): path.write_bytes(payload)
            original = module.install
            def install(*args, **kwargs): return original(*args, **kwargs, fetch=fetch)
            with patch.object(module, 'REPO', root), patch.object(module, 'install', side_effect=install):
                self.assertEqual(module.main(['--root',str(root),'install','fixture','--apply']),2)
            self.assertFalse(list((root / 'fixture').rglob('receipt.json')))


if __name__ == '__main__':
    unittest.main()
