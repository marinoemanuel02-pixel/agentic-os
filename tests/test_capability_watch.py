"""Offline acceptance checks for discovery, evidence and registry changes."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/capability_watch.py'
NOW = '2026-10-21T20:00:00Z'


class CapabilityWatchTests(unittest.TestCase):
    def module(self):
        self.assertTrue(SCRIPT.exists(), 'capability registry workflow has not been implemented')
        spec = importlib.util.spec_from_file_location('capability_watch', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def registry(self):
        self.assertTrue((ROOT / 'config/capabilities.json').exists(), 'candidate registry has not been added')
        return json.loads((ROOT / 'config/capabilities.json').read_text(encoding='utf-8'))

    def fixture(self):
        registry = self.registry()
        registry['tools'] = [copy.deepcopy(next(t for t in registry['tools'] if t['id'] == 'pdfcraft'))]
        registry['sources'] = [{'id': 'cases', 'kind': 'json', 'role': 'discovery',
                                'url': 'https://miles990.github.io/rea-case-rankings/api/records.json',
                                'enabled': True, 'tool': None, 'notes': 'offline fixture'}]
        return registry

    def evidence(self, version='0.10.1'):
        return {'checked_at': NOW, 'version': version, 'checks': {
            key: 'pass' for key in ('source', 'license', 'windows_build', 'windows_execution',
                                   'security', 'artifact')},
            'references': ['fixture://corpus/report'], 'notes': 'Independent reopen and render checked.'}

    def run_refresh(self, registry, previous=None, document='MCP over stdio. Windows. Headless.', **kwargs):
        module = self.module()

        def fetch(url):
            if url.endswith('/releases/latest'):
                return json.dumps({'tag_name': 'v0.10.1', 'published_at': NOW,
                                   'assets': [{'name': 'pdfcraft-windows-x64.msi'}]})
            if url.endswith('/repos/storytold/pdfcraft'):
                return json.dumps({'created_at': NOW, 'pushed_at': NOW, 'fork': False,
                                   'license': {'spdx_id': 'MIT'}, 'default_branch': 'main'})
            return document

        return module.refresh(registry, previous or {'sources': {}}, fetch=fetch,
                              tool_ids=['pdfcraft'], source_ids=[], checked_at=NOW, **kwargs)

    def test_seed_validates_unknowns_and_required_candidates(self):
        module = self.module()
        registry = self.registry()
        module.validate_registry(registry)
        ids = {t['id'] for t in registry['tools']}
        self.assertTrue({'rea', 'pdfcraft', 'blender-agent-sdk', 'blender-mcp', 'logisheets',
                         'filmcraft', 'photocraft', 'agent-desktop', 'mcp-pc', 'anis',
                         'inkscape-live-mcp', 'kordoc', 'audacity4mcp', 'solidcraft'} <= ids)
        self.assertFalse(any(t['status'] == 'production' for t in registry['tools']))
        self.assertTrue(all(t['verification'] == [] for t in registry['tools']))
        self.assertIsNone(registry['tools'][0]['latest_functional_commit_at'])

    def test_invalid_status_extra_fields_duplicates_and_sources_are_rejected(self):
        module = self.module()
        for mutation in ('status', 'extra', 'duplicate', 'source', 'boolean', 'date'):
            registry = self.fixture()
            tool = registry['tools'][0]
            if mutation == 'status': tool['status'] = 'installed'
            if mutation == 'extra': tool['typo'] = True
            if mutation == 'duplicate': registry['tools'].append(copy.deepcopy(tool))
            if mutation == 'source': registry['sources'].append(copy.deepcopy(registry['sources'][0]))
            if mutation == 'boolean': tool['interfaces']['mcp'] = 'yes'
            if mutation == 'date': tool['discovered_at'] = 'yesterday'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                module.validate_registry(registry)

    def test_first_observation_is_baseline_repeat_is_quiet(self):
        state, report = self.run_refresh(self.fixture())
        self.assertEqual(report['transitions'], [])
        self.assertTrue(report['baselines'])
        again, report = self.run_refresh(self.fixture(), state)
        self.assertEqual(report['transitions'], [])
        self.assertEqual(state, again)

    def test_detects_all_required_signals_without_verifying_claims(self):
        registry = self.fixture()
        state, _ = self.run_refresh(registry, document='A document editor.')
        _, report = self.run_refresh(registry, state, document=(
            'Windows MCP stdio JSON-RPC CLI headless live GUI attach. inspectable state. '
            'render screenshot --root filesystem scope expected_revision revision guard '
            'rollback undo transactional atomic edits.'))
        gained = {t['field'] for t in report['transitions'] if t['kind'] == 'signal_appeared'}
        self.assertTrue({'windows', 'mcp', 'stdio', 'json_rpc', 'headless', 'live_gui_attach',
                         'render_feedback', 'filesystem_scoping', 'revision_guards', 'rollback',
                         'transactional_edits'} <= gained)
        self.assertEqual(registry['tools'][0]['verification'], [])
        self.assertEqual(registry['tools'][0]['status'], 'watch')
        self.assertTrue(all(t['confidence'] == 'unverified_signal' for t in report['transitions']))

    def test_documentation_signal_loss_is_not_verified_removal(self):
        state, _ = self.run_refresh(self.fixture())
        _, report = self.run_refresh(self.fixture(), state, document='No protocol documented here.')
        self.assertTrue(any(t['kind'] == 'signal_disappeared' and t['field'] == 'mcp'
                            for t in report['transitions']))

    def test_failed_fetch_retains_last_good_source_and_no_false_loss(self):
        module = self.module()
        state, _ = self.run_refresh(self.fixture())
        def fail(url): raise OSError('offline')
        updated, report = module.refresh(self.fixture(), state, fetch=fail,
                                        tool_ids=['pdfcraft'], source_ids=[], checked_at=NOW)
        self.assertEqual(state, updated)
        self.assertTrue(report['errors'])
        self.assertEqual(report['transitions'], [])

    def test_discovery_deduplicates_links_tracks_sources_and_never_promotes(self):
        module = self.module()
        registry = self.fixture()
        registry['sources'].append(dict(registry['sources'][0], id='other'))
        body = json.dumps([{'url': 'https://github.com/Acme/Editor.git', 'added': '1999-01-01'},
                           {'repo': 'https://github.com/acme/editor/tree/main'},
                           {'url': 'https://github.com/storytold/pdfcraft'}])
        state, report = module.refresh(registry, {'sources': {}}, fetch=lambda url: body,
                                       tool_ids=[], source_ids=None, checked_at=NOW)
        self.assertEqual(len(report['discoveries']), 1)
        self.assertEqual(report['discoveries'][0]['repository'], 'https://github.com/acme/editor')
        self.assertEqual(report['discoveries'][0]['sources'], ['cases', 'other'])
        self.assertEqual(report['discoveries'][0]['discovered_at'], NOW)
        _, repeat = module.refresh(registry, state, fetch=lambda url: body,
                                   tool_ids=[], source_ids=None, checked_at=NOW)
        self.assertEqual(repeat['discoveries'], [])
        self.assertEqual(len(registry['tools']), 1)

    def test_malformed_json_fails_instead_of_looking_like_empty_feed(self):
        module = self.module()
        _, report = module.refresh(self.fixture(), {'sources': {}}, fetch=lambda url: '<html>error</html>',
                                   tool_ids=[], source_ids=None, checked_at=NOW)
        self.assertTrue(report['errors'])

    def test_release_change_and_metadata_are_separate_from_functional_commit(self):
        module = self.module()
        registry = self.fixture()
        state, _ = self.run_refresh(registry)
        def fetch(url):
            if url.endswith('/releases/latest'):
                return json.dumps({'tag_name': 'v0.11.0', 'published_at': NOW, 'assets': []})
            return json.dumps({'default_branch': 'main'}) if '/repos/' in url else 'MCP stdio Windows headless'
        _, report = module.refresh(registry, state, fetch=fetch, tool_ids=['pdfcraft'],
                                   source_ids=[], checked_at=NOW)
        self.assertTrue(any(t['kind'] == 'release_changed' for t in report['transitions']))
        self.assertIsNone(registry['tools'][0]['latest_functional_commit_at'])

    def test_package_release_metadata_is_not_an_install(self):
        module = self.module()
        registry = self.fixture()
        registry['sources'] = [dict(registry['sources'][0], id='package', kind='npm', role='release',
                                    tool='pdfcraft', url='https://registry.npmjs.org/example/latest')]
        state, report = module.refresh(registry, {'sources': {}}, fetch=lambda url: json.dumps(
            {'version': '1.2.3', 'repository': {'url': 'git+https://github.com/acme/editor.git'}}),
            tool_ids=[], source_ids=None, checked_at=NOW)
        self.assertEqual(state['sources']['package']['metadata']['version'], '1.2.3')
        self.assertEqual(registry['tools'][0]['verification'], [])
        self.assertFalse(report['errors'])

    def test_production_requires_complete_passes_at_pinned_version(self):
        module = self.module()
        tool = self.fixture()['tools'][0]
        for status in ('ignore', 'watch', 'sandbox'):
            module.set_status(tool, status, 'fixture evaluation')
        with self.assertRaises(ValueError): module.set_status(tool, 'production', 'not tested')
        tool['pinned_version'] = '0.10.1'
        module.record_evidence(tool, self.evidence('old'))
        with self.assertRaises(ValueError): module.set_status(tool, 'production', 'stale version')
        record = self.evidence()
        record['checks']['artifact'] = 'fail'
        module.record_evidence(tool, record)
        with self.assertRaises(ValueError): module.set_status(tool, 'production', 'failed artifact')
        module.record_evidence(tool, self.evidence())
        module.set_status(tool, 'production', 'corpus passed')
        self.assertEqual(tool['status'], 'production')
        self.assertEqual(tool['last_evaluated'], NOW)
        module.record_evidence(tool, record)
        with self.assertRaises(ValueError): module.validate_registry(dict(self.fixture(), tools=[tool]))

    def test_evidence_is_data_and_rejects_empty_or_unknown_checks(self):
        module = self.module()
        for invalid in ({}, dict(self.evidence(), references=[]),
                        dict(self.evidence(), checks={'source': 'yes'})):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                module.record_evidence(self.fixture()['tools'][0], invalid)

    def test_network_boundary_and_redirects_reject_untrusted_targets(self):
        module = self.module()
        for url in ('http://api.github.com/x', 'https://localhost/x', 'file:///tmp/x',
                    'https://api.github.com.evil.test/x', 'https://user:secret@api.github.com/x',
                    'https://api.github.com:444/x'):
            with self.subTest(url=url), self.assertRaises(ValueError): module.check_url(url)
        module.check_url('https://api.github.com/repos/storytold/pdfcraft')
        with self.assertRaises(ValueError):
            module.SafeRedirect().redirect_request(None, None, 302, 'redirect', {}, 'http://127.0.0.1/')

    def test_atomic_writes_lock_and_preserve_existing_bytes(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            module.write_json(path, {'before': True})
            before = path.read_bytes()
            with module.locked(path):
                with self.assertRaises(ValueError):
                    with module.locked(path): pass
            self.assertEqual(path.read_bytes(), before)
            module.write_json(path, {'after': True})
            self.assertEqual(json.loads(path.read_text()), {'after': True})

    def test_schema_version_cannot_be_a_boolean(self):
        module = self.module()
        registry = self.fixture()
        registry['schema_version'] = True
        with self.assertRaises(ValueError): module.validate_registry(registry)

    def test_evaluation_order_compares_instants_across_timezones(self):
        module = self.module()
        tool = self.fixture()['tools'][0]
        module.record_evidence(tool, self.evidence())
        older = self.evidence()
        older['checked_at'] = '2026-10-21T21:00:00+02:00'
        with self.assertRaises(ValueError): module.record_evidence(tool, older)

    def test_rss_and_pypi_are_parsed_without_running_their_content(self):
        module = self.module()
        registry = self.fixture()
        source = registry['sources'][0]
        source['kind'] = 'rss'
        state, report = module.refresh(registry, {'sources': {}}, fetch=lambda url:
            '<rss><channel><item><link>https://github.com/acme/editor</link></item></channel></rss>',
            checked_at=NOW)
        self.assertFalse(report['errors'])
        self.assertEqual(len(report['discoveries']), 1)
        source.update(kind='pypi', role='release', tool='pdfcraft')
        state, report = module.refresh(registry, {'sources': {}}, fetch=lambda url: json.dumps(
            {'info': {'version': '2.0'}, 'urls': [{'filename': 'example.whl',
              'upload_time_iso_8601': NOW}]}), checked_at=NOW)
        self.assertEqual(state['sources']['cases']['metadata']['version'], '2.0')

    def test_limits_filtering_and_missing_sources_are_explicit(self):
        module = self.module()
        registry = self.fixture()
        body = json.dumps([{'url': 'https://github.com/acme/editor'},
                           {'url': 'https://github.com/acme/second'}])
        state, report = module.refresh(registry, {'sources': {}}, fetch=lambda url: body,
                                       checked_at=NOW, limit=1)
        self.assertEqual(len(report['discoveries']), 1)
        self.assertEqual(report['discovery_count'], 2)
        _, report = module.refresh(registry, state, fetch=lambda url: body, checked_at=NOW)
        self.assertEqual(len(report['discoveries']), 1)
        with self.assertRaises(ValueError):
            module.refresh(registry, {'sources': {}}, limit=0)
        with self.assertRaises(ValueError):
            module.refresh(registry, {'sources': {}}, source_ids=['missing'])
        module.MAX_BYTES = 8
        _, report = module.refresh(registry, {'sources': {}}, fetch=lambda url: body, checked_at=NOW)
        self.assertTrue(report['errors'])

    def test_malformed_saved_source_is_rejected_before_refresh(self):
        module = self.module()
        with self.assertRaises(ValueError):
            module.refresh(self.fixture(), {'sources': {'cases': {}}}, fetch=lambda url: '[]',
                           checked_at=NOW)

    def test_malformed_github_metadata_retains_the_last_good_observation(self):
        module = self.module()
        registry = self.fixture()
        baseline, _ = self.run_refresh(registry)
        for payload in ({}, {'default_branch': 'main'}, {'default_branch': 'main', 'parent': 'invalid'},
                        {'default_branch': 'main', 'license': 'MIT'},
                        {'default_branch': 'main', 'fork': 'false'}):
            def fetch(url):
                if url.endswith('/repos/storytold/pdfcraft'):
                    return json.dumps(payload)
                if url.endswith('/releases/latest'):
                    return json.dumps({'tag_name': 'v0.10.1', 'published_at': NOW,
                                       'assets': [{'name': 'pdfcraft-windows-x64.msi'}]})
                return 'MCP over stdio. Windows. Headless.'
            with self.subTest(payload=payload):
                state, report = module.refresh(registry, baseline, fetch=fetch,
                    tool_ids=['pdfcraft'], source_ids=[], checked_at=NOW)
                self.assertEqual(state, baseline)
                self.assertEqual(report['transitions'], [])
                self.assertEqual(report['errors'][0]['source'], 'pdfcraft:github_metadata')

    def test_escaped_json_urls_are_equivalent_to_plain_urls(self):
        module = self.module()
        body = r'[{"url":"https:\/\/github.com\/acme\/editor"}]'
        state, report = module.refresh(self.fixture(), {'sources': {}}, fetch=lambda url: body,
                                       checked_at=NOW)
        self.assertFalse(report['errors'])
        self.assertEqual(len(report['discoveries']), 1)
        self.assertEqual(report['discoveries'][0]['repository'], 'https://github.com/acme/editor')

    def test_cli_preview_then_apply_changes_only_requested_registry(self):
        self.module()
        with tempfile.TemporaryDirectory() as folder:
            registry = Path(folder) / 'registry.json'
            state = Path(folder) / 'state.json'
            registry.write_text(json.dumps(self.fixture()), encoding='utf-8')
            before = registry.read_bytes()
            command = [sys.executable, str(SCRIPT), '--registry', str(registry), '--state', str(state),
                       'status', 'pdfcraft', 'sandbox', '--reason', 'fixture test']
            preview = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace')
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertEqual(registry.read_bytes(), before)
            self.assertFalse(state.exists())
            applied = subprocess.run(command + ['--apply'], capture_output=True, text=True,
                                     encoding='utf-8', errors='replace')
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertEqual(json.loads(registry.read_text())['tools'][0]['status'], 'sandbox')
            self.assertTrue(list((Path(folder) / 'registry-backups').glob('*.json')))


if __name__ == '__main__':
    unittest.main()
