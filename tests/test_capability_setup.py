"""Offline setup controls; never download or install real tools in tests."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
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
            self.assertEqual(command[0], receipt['entrypoint'])

    def test_manifest_rejects_unknown_kinds_unpinned_hashes_and_paths(self):
        module = self.module()
        for mutation in ('kind', 'hash', 'path', 'version'):
            entry = self.entry(self.archive())
            if mutation == 'kind': entry['kind'] = 'shell'
            if mutation == 'hash': entry['sha256'] = 'latest'
            if mutation == 'path': entry['entrypoint'] = '../outside.exe'
            if mutation == 'version': entry['version'] = '../../outside'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): module.validate_entry(entry)


if __name__ == '__main__':
    unittest.main()
