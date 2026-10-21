"""Admission and host acceptance regressions; no real credentials or network."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from swarm_config import validate_registry
from swarm_state import State, Unavailable
from swarm_providers import build_request, parse_result, ProviderError
from swarm_pool import Pool


def registry():
    return {'version': 1, 'max_active': 2, 'provider_active': 2, 'accounts': [
        {'id': 'first', 'provider': 'openrouter', 'secret': 'fixture-first',
         'quota_group': 'owner-first', 'enabled': True, 'priority': 1,
         'free': {'kind': 'zero_price'},
         'routes': {'text': {'model': 'fixture:free'}},
         'limits': [{'unit': 'requests', 'seconds': 86400, 'amount': 10},
                    {'unit': 'tokens', 'seconds': 86400, 'amount': 100000}]}]}


def packet(task='one', **extra):
    return dict(id=task, capability='text', prompt='Return the supplied facts.',
                cloud_allowed=True, **extra)


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = State(Path(self.tmp.name) / 'pool.sqlite')
        self.reg = validate_registry(registry())
        self.account = self.reg['accounts'][0]

    def reserve(self, account=None, key='fixture-secret', **kw):
        return self.state.reserve(self.reg, account or self.account, key,
                                  {'requests': 1, 'tokens': 10}, **kw)

    def test_hard_cap_never_becomes_degraded_fallback(self):
        self.account['limits'][0]['amount'] = 1
        self.state.finish(self.reserve(), 'ok')
        self.assertEqual(self.state.eligible(self.reg, 'text'), [])
        with self.assertRaises(Unavailable):
            self.reserve()

    def test_permanent_cooldown_excludes_only_route(self):
        self.state.finish(self.reserve(), 'permanent', retry_after=21600)
        self.assertEqual(self.state.eligible(self.reg, 'text'), [])
        with self.assertRaises(Unavailable):
            self.reserve()

    def test_each_actual_retry_is_accounted(self):
        for _ in range(3):
            self.state.finish(self.reserve(), 'transient', retry_after=0)
        self.assertEqual(len(self.state.attempts()), 3)

    def test_duplicate_secret_cannot_create_capacity(self):
        self.account['limits'][0]['amount'] = 1
        self.state.finish(self.reserve(), 'ok')
        second = copy.deepcopy(self.account)
        second.update(id='second', secret='other-name', quota_group='other-owner')
        with self.assertRaises(Unavailable):
            self.reserve(second)

    def test_duplicate_alias_with_a_larger_limit_cannot_raise_original_ceiling(self):
        self.account['limits'][0]['amount'] = 1
        self.state.finish(self.reserve(), 'ok')
        second = copy.deepcopy(self.account)
        second.update(id='second', secret='other-name', quota_group='other-owner')
        second['limits'][0]['amount'] = 100
        with self.assertRaises(Unavailable): self.reserve(second)

    def test_shared_org_blocks_different_keys(self):
        self.account['limits'][0]['amount'] = 1
        self.state.finish(self.reserve(), 'ok')
        second = copy.deepcopy(self.account)
        second.update(id='second', secret='other-name')
        with self.assertRaises(Unavailable):
            self.reserve(second, key='different-fixture-key')

    def test_concurrent_process_boundary_reserves_one_remaining_slot(self):
        self.account['limits'][0]['amount'] = 1
        barrier = threading.Barrier(2)
        def run(_):
            state = State(self.state.path)
            barrier.wait(timeout=5)
            try:
                return state.reserve(self.reg, self.account, 'same-fixture', {'requests': 1, 'tokens': 10})
            except Unavailable:
                return None
        with ThreadPoolExecutor(2) as pool:
            got = list(pool.map(run, range(2)))
        self.assertEqual(sum(x is not None for x in got), 1)

    def test_crashed_lease_is_not_silently_reclaimed(self):
        self.reserve(now=1)
        with self.assertRaises(Unavailable):
            self.reserve(now=1000000)

    def test_provider_and_global_concurrency(self):
        self.reserve()
        other = copy.deepcopy(self.account)
        other.update(id='two', quota_group='two')
        self.reserve(other, 'key-two')
        third = copy.deepcopy(other)
        third.update(id='three', quota_group='three')
        with self.assertRaises(Unavailable):
            self.reserve(third, 'key-three')

    def test_capability_units_are_reserved(self):
        self.account['limits'].append({'unit': 'audio_seconds', 'seconds': 86400, 'amount': 3})
        with self.assertRaises(Unavailable):
            self.state.reserve(self.reg, self.account, 'key', {'requests': 1, 'audio_seconds': 4})


class WireTests(unittest.TestCase):
    def test_system_payload_is_always_valid_text(self):
        url, headers, body = build_request(registry()['accounts'][0], packet(), 'fixture-key')
        self.assertTrue(all(isinstance(m['content'], str) for m in body['messages']))
        self.assertNotIn('fixture-key', url)

    def test_free_guard_has_no_paid_fallback(self):
        _, _, body = build_request(registry()['accounts'][0], packet(), 'fixture-key')
        self.assertIs(body['provider']['allow_fallbacks'], False)
        self.assertEqual(set(body['provider']['max_price'].values()), {0})

    def test_tool_calls_and_truncation_are_rejected(self):
        account = registry()['accounts'][0]
        for choice in [dict(message={'content': 'x', 'tool_calls': [{}]}, finish_reason='stop'),
                       dict(message={'content': 'x'}, finish_reason='length')]:
            with self.assertRaises(ProviderError):
                parse_result(account, packet(), {'choices': [choice]})

    def test_rerank_indices_must_be_unique_and_in_range(self):
        p = packet(capability_override='unused')
        p.update(capability='rerank', documents=['a', 'b'], query='q')
        a = dict(provider='cohere', routes={'rerank': {'model': 'fixture'}})
        for results in [[{'index': 2, 'relevance_score': .5}],
                        [{'index': 0, 'relevance_score': .5}] * 2]:
            with self.assertRaises(ProviderError):
                parse_result(a, p, {'results': results})

    def test_embedding_shape_and_finite_values(self):
        a = dict(provider='cohere', routes={'embed': {'model': 'fixture'}})
        p = dict(capability='embed', texts=['a', 'b'], input_type='search_document')
        for vectors in [[[1, 2]], [[1, 2], [1]], [[1, 2], [float('nan'), 0]]]:
            with self.assertRaises(ProviderError):
                parse_result(a, p, {'embeddings': {'float': vectors}})

    def test_unknown_expired_or_paid_registry_is_rejected(self):
        for mutate in [lambda a: a.update(provider='unknown'),
                       lambda a: a.update(free={'kind': 'paid'}),
                       lambda a: a.update(endpoint='https://untrusted.invalid')]:
            r = registry(); mutate(r['accounts'][0])
            with self.assertRaises(ValueError): validate_registry(r)

    def test_arbitrary_more_than_two_accounts_are_supported(self):
        r = registry()
        for i in range(5):
            a = copy.deepcopy(r['accounts'][0]); a.update(id='extra' + str(i), quota_group='extra' + str(i))
            r['accounts'].append(a)
        self.assertEqual(len(validate_registry(r)['accounts']), 6)


class TaskTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.state = State(Path(self.tmp.name) / 'state.sqlite')
        self.calls = []
        def call(account, task, key):
            self.calls.append((account['id'], task['id']))
            return {'text': 'candidate', 'complete': True, 'usage': {}}
        self.pool = Pool(registry(), self.state, secret=lambda name: 'fixture-key',
                         check=lambda *args: None, call=call)

    def test_direct_and_queue_use_same_unaccepted_candidate(self):
        self.pool.submit(packet())
        self.pool.drain()
        row = self.state.task('one')
        self.assertEqual(row['status'], 'candidate')
        self.assertIs(row['candidate']['accepted'], False)
        self.pool.drain()
        self.assertEqual(len(self.calls), 1)

    def test_dependency_requires_host_verification_and_detects_drift(self):
        self.pool.submit(packet()); self.pool.submit(packet('two', depends_on=['one']))
        self.pool.drain()
        self.assertEqual(self.state.task('two')['status'], 'queued')
        one = self.state.task('one')
        with self.assertRaises(ValueError):
            self.state.accept('one', 'wrong-hash', {'exit_code': 0})
        self.state.accept('one', one['candidate_sha256'], {'exit_code': 0, 'argv': ['fixture-check']})
        self.pool.drain()
        self.assertEqual(self.state.task('two')['status'], 'candidate')

    def test_cancel_queued_and_running_tasks(self):
        self.pool.submit(packet())
        self.state.cancel('one'); self.pool.drain()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.state.task('one')['status'], 'cancelled')
        self.pool.submit(packet('two'))
        def cancel_inside(a, p, k):
            self.state.cancel('two')
            return {'text': 'late', 'complete': True, 'usage': {}}
        self.pool.call = cancel_inside; self.pool.drain()
        self.assertEqual(self.state.task('two')['status'], 'cancelled')
        self.assertIsNone(self.state.task('two')['candidate'])

    def test_failover_records_every_attempt(self):
        r = registry(); a = copy.deepcopy(r['accounts'][0]); a.update(id='second', quota_group='other', secret='other')
        a.update(provider='mistral', free={'kind': 'free_tier', 'confirmed_until': 9999999999,
                                         'paid_disabled': True, 'evidence': 'fixture'})
        r['accounts'].append(a)
        def call(a, p, k):
            if a['id'] == 'first': raise ProviderError('rate', 10)
            return {'text': 'ok', 'complete': True, 'usage': {}}
        pool = Pool(r, self.state, secret=lambda n: n, check=lambda *x: None, call=call)
        pool.submit(packet()); pool.drain()
        self.assertEqual(len(self.state.attempts()), 2)
        self.assertEqual(self.state.task('one')['status'], 'candidate')

    def test_provider_rate_limit_is_not_bypassed_with_another_account(self):
        r = registry(); a = copy.deepcopy(r['accounts'][0]); a.update(id='second', quota_group='other', secret='other')
        r['accounts'].append(a)
        def call(a, p, k): raise ProviderError('rate', 60)
        pool = Pool(r, self.state, secret=lambda n: n, check=lambda *x: None, call=call)
        pool.submit(packet()); pool.drain()
        self.assertEqual(len(self.state.attempts()), 1)
        self.assertEqual(self.state.task('one')['status'], 'failed')

    def test_preflight_errors_are_quarantined_without_an_inference_attempt(self):
        def check(*args): raise ProviderError('permanent', 21600)
        self.pool.check = check
        self.pool.submit(packet()); self.pool.drain()
        self.assertEqual(self.calls, [])

    def test_actual_host_verifier_failure_does_not_accept(self):
        from swarm_pool import verify_candidate
        self.pool.submit(packet()); self.pool.drain()
        with self.assertRaises(ValueError):
            verify_candidate(self.state, 'one', [sys.executable, '-c', 'raise SystemExit(1)'])
        self.assertEqual(self.state.task('one')['status'], 'candidate')

    def test_actual_host_verifier_accepts_and_artifact_drift_blocks_dependents(self):
        from swarm_pool import verify_candidate
        self.pool.submit(packet()); self.pool.drain()
        artifact = Path(self.tmp.name) / 'fact.txt'; artifact.write_text('verified')
        verify_candidate(self.state, 'one', [sys.executable, '-c', 'import json,sys; assert json.load(open(sys.argv[1]))["text"]=="candidate"', '{candidate}'], artifacts=[artifact])
        artifact.write_text('changed')
        self.pool.submit(packet('two', depends_on=['one'])); self.pool.drain()
        self.assertEqual(self.state.task('two')['status'], 'queued')

    def test_packets_cannot_request_tools_or_unapproved_cloud(self):
        for p in [packet(tools=['shell']), dict(packet(), cloud_allowed=False)]:
            with self.assertRaises(ValueError): self.pool.submit(p)

    def test_task_id_cannot_be_reused_for_different_input(self):
        self.pool.submit(packet())
        with self.assertRaises(ValueError): self.pool.submit(dict(packet(), prompt='different'))

    def test_embedding_retry_cannot_switch_vector_space(self):
        with self.assertRaises(ValueError):
            self.pool.submit(dict(id='embedding', capability='embed', texts=['a'], cloud_allowed=True))


if __name__ == '__main__': unittest.main()
