"""Real host task contract bridge in disposable repositories and AOS_COORD."""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'tools'))
from swarm_pool import bridge


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'repo'; self.repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                        'commit', '--allow-empty', '-qm', 'fixture'], check=True, capture_output=True)
        self.old = os.environ.get('AOS_COORD'); os.environ['AOS_COORD'] = str(Path(self.tmp.name) / 'coord')
        self.addCleanup(self.restore)
        self.contract = {'version': 1, 'id': 'fixture-task', 'objective': 'Return a supplied fact.',
            'task_class': 'mechanical', 'depends_on': [], 'allow': [],
            'verify': '$c=Get-Content -LiteralPath $env:AOS_SWARM_CANDIDATE -Raw | ConvertFrom-Json; if ($c.text -ne "candidate") {exit 1}; Set-Content -LiteralPath fact.txt -Value "verified"; exit 0',
            'artifacts': ['fact.txt'], 'context': [], 'budget': {'timeout_minutes': 1}}
        self.setup(self.contract)

    def restore(self):
        if self.old is None: os.environ.pop('AOS_COORD', None)
        else: os.environ['AOS_COORD'] = self.old

    def ps(self, code, value):
        env = dict(os.environ, FIXTURE_MODULE=str(REPO / 'aos.psm1'))
        script = "$ErrorActionPreference='Stop';$m=Import-Module $env:FIXTURE_MODULE -Force -PassThru -DisableNameChecking;$inputJson=[Console]::In.ReadToEnd(); & $m {param($json) $r=ConvertTo-AosHashtable (ConvertFrom-Json $json);" + code + '} $inputJson'
        return subprocess.run([shutil.which('pwsh') or 'powershell', '-NoProfile', '-NonInteractive', '-EncodedCommand',
            base64.b64encode(script.encode('utf-16-le')).decode()], input=json.dumps(value), text=True,
            capture_output=True, encoding='utf-8', errors='replace', env=env, timeout=45, check=True).stdout

    def setup(self, contract):
        path = Path(self.tmp.name) / 'contract.json'; path.write_text(json.dumps(contract))
        self.ps("$null=Register-AosTaskContract $r.path $r.repo; $null=Invoke-AosClaim -Path $r.repo -Agent codex -Session fixture-session", {'path': str(path), 'repo': str(self.repo)})

    def prepare(self):
        return bridge('prepare', {'id': 'fixture-task', 'repo': str(self.repo), 'owner_session': 'fixture-session', 'process_id': os.getpid()})

    def test_host_check_accepts_declared_artifact_without_native_actor(self):
        data = self.prepare()
        path = Path(self.tmp.name) / 'candidate.json'; path.write_text(json.dumps({'text': 'candidate', 'accepted': False}))
        receipt = bridge('verify', dict(data, candidate=str(path), candidate_sha256='fixture-binding',
                                        candidate_file_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        self.assertIs(receipt['accepted'], True)
        self.assertEqual((self.repo / 'fact.txt').read_text().strip(), 'verified')
        actors = Path(os.environ['AOS_COORD']) / 'actors.json'
        if actors.exists(): self.assertEqual(json.loads(actors.read_text())['actors'], {})

    def test_real_bridge_executes_under_windows_powershell_51(self):
        with patch('swarm_pool.shutil.which', lambda name: 'powershell'):
            data = self.prepare()
            path = Path(self.tmp.name) / 'candidate.json'; path.write_text(json.dumps({'text': 'candidate'}))
            receipt = bridge('verify', dict(data, candidate=str(path), candidate_sha256='fixture-binding',
                                            candidate_file_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        self.assertIs(receipt['accepted'], True)

    def test_failed_host_check_does_not_accept_task(self):
        data = self.prepare()
        path = Path(self.tmp.name) / 'candidate.json'; path.write_text(json.dumps({'text': 'wrong'}))
        with self.assertRaises(ValueError): bridge('verify', dict(data, candidate=str(path), candidate_sha256='fixture',
                                                                candidate_file_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        record = json.loads((Path(os.environ['AOS_COORD']) / 'tasks/fixture-task.json').read_text())
        self.assertEqual(record['state'], 'failed')

    def test_missing_dependency_blocks_before_any_provider_or_lease(self):
        c = dict(self.contract, id='blocked', depends_on=['unknown'])
        self.setup(c)
        with self.assertRaises(ValueError):
            bridge('prepare', {'id': 'blocked', 'repo': str(self.repo), 'owner_session': 'fixture-session', 'process_id': os.getpid()})

    def test_existing_contract_without_optional_budget_is_supported(self):
        c = dict(self.contract, id='without-budget'); c.pop('budget')
        self.setup(c)
        result = bridge('prepare', {'id': 'without-budget', 'repo': str(self.repo),
                                  'owner_session': 'fixture-session', 'process_id': os.getpid()})
        self.assertEqual(result['timeout_seconds'], 300)

    def test_host_cancel_prevents_verification_and_acceptance(self):
        data = self.prepare()
        self.ps("$null=Set-AosRunState -Id $r.id -State preparing -Cancel", {'id': data['run']})
        path = Path(self.tmp.name) / 'candidate.json'; path.write_text(json.dumps({'text': 'candidate'}))
        with self.assertRaises(ValueError): bridge('verify', dict(data, candidate=str(path), candidate_sha256='fixture'))
        self.assertFalse((self.repo / 'fact.txt').exists())


if __name__ == '__main__': unittest.main()
