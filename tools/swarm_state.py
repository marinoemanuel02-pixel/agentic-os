"""SQLite worker admission, charged attempts, queue and host acceptance."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import time
import uuid

from swarm_config import admitted, identifier


class Unavailable(ValueError): pass


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode('utf-8')).hexdigest()


class State:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS attempts(
                  id TEXT PRIMARY KEY, account TEXT, provider TEXT, quota_group TEXT,
                  credential TEXT, started REAL, active INTEGER, outcome TEXT,
                  units TEXT, task TEXT, run TEXT, pid INTEGER);
                CREATE TABLE IF NOT EXISTS cooldowns(bucket TEXT PRIMARY KEY, until REAL);
                CREATE TABLE IF NOT EXISTS ceilings(
                  credential TEXT, unit TEXT, seconds INTEGER, amount INTEGER,
                  PRIMARY KEY(credential,unit,seconds));
                CREATE TABLE IF NOT EXISTS leases(
                  run TEXT PRIMARY KEY, account TEXT, provider TEXT, quota_group TEXT);
                CREATE TABLE IF NOT EXISTS holders(run TEXT PRIMARY KEY, pid INTEGER);
                CREATE TABLE IF NOT EXISTS tasks(
                  id TEXT PRIMARY KEY, packet TEXT, packet_hash TEXT, status TEXT,
                  cancelled INTEGER DEFAULT 0, candidate TEXT, candidate_hash TEXT,
                  check_receipt TEXT, inputs TEXT, run TEXT, error TEXT);
            ''')

    @contextmanager
    def db(self, write=False):
        db = sqlite3.connect(self.path, timeout=30, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            if write: db.execute('BEGIN IMMEDIATE')
            yield db
            if write: db.commit()
        except BaseException:
            if write: db.rollback()
            raise
        finally: db.close()

    def _check(self, db, r, a, units, key_hash=None, now=None):
        now = time.time() if now is None else now
        if not admitted(a): raise Unavailable('Account disabled or free attestation expired')
        buckets = ['provider:' + a['provider'], 'group:' + a['quota_group']]
        if key_hash: buckets.append('credential:' + key_hash)
        for bucket in buckets:
            row = db.execute('SELECT until FROM cooldowns WHERE bucket=?', (bucket,)).fetchone()
            if row and row[0] > now: raise Unavailable('Quota bucket cooling down')
        rows = db.execute('SELECT * FROM attempts WHERE active=1 OR started>?', (now - 32 * 86400,)).fetchall()
        active = [x for x in rows if x['active']]
        if (len(active) >= r['max_active']
                or sum(x['provider'] == a['provider'] for x in active) >= r['provider_active']
                or any(x['account'] == a['id'] or x['quota_group'] == a['quota_group']
                       or (key_hash and x['credential'] == key_hash) for x in active)):
            raise Unavailable('Worker concurrency is occupied')
        if a['provider'] == 'omniroute' and any(x['provider'] == 'omniroute' for x in active):
            raise Unavailable('Gateway admits one worker')
        relevant = [x for x in rows if x['quota_group'] == a['quota_group']
                    or (key_hash and x['credential'] == key_hash)]
        # The strictest configured ceiling wins for shared account/credential identities.
        limits = list(a['limits'])
        if key_hash:
            limits += [dict(row) for row in db.execute('SELECT unit,seconds,amount FROM ceilings WHERE credential=?', (key_hash,))]
        for other in r['accounts']:
            if other['id'] != a['id'] and other['quota_group'] == a['quota_group']:
                limits += other['limits']
        for limit in limits:
            used = sum(json.loads(x['units']).get(limit['unit'], 0) for x in relevant
                       if x['started'] > now - limit['seconds'] or x['active'])
            if used + units.get(limit['unit'], 0) > limit['amount']:
                raise Unavailable('Local quota ceiling reached')
        # Conservative cross-account OpenRouter traffic ceiling; accounts do not bypass it.
        if a['provider'] in ('openrouter', 'omniroute'):
            n = sum(x['provider'] in ('openrouter', 'omniroute') and x['started'] > now - 60 for x in rows)
            if n >= 10: raise Unavailable('Shared OpenRouter minute ceiling reached')
            daily = sum(x['provider'] in ('openrouter', 'omniroute') and
                        (x['started'] > now - 86400 or x['active']) for x in rows)
            if daily >= 30: raise Unavailable('Shared OpenRouter daily ceiling reached')

    def eligible(self, registry, capability):
        result = []
        with self.db() as db:
            for a in sorted(registry['accounts'], key=lambda a: (a['priority'], a['id'])):
                if capability not in a['routes']: continue
                try: self._check(db, registry, a, {'requests': 1})
                except Unavailable: continue
                result.append(a)
        return result

    def reserve(self, registry, account, key, units, *, task='', run='', now=None):
        if (not isinstance(units, dict) or units.get('requests') != 1
                or any(k not in ('requests', 'tokens', 'audio_seconds') or type(v) is not int or v < 0
                       for k, v in units.items())): raise ValueError('Invalid quota reservation')
        identifier(account['id'])
        key_hash = hashlib.sha256(key.encode()).hexdigest()
        now = time.time() if now is None else now
        with self.db(True) as db:
            for limit in account['limits']:
                db.execute('INSERT INTO ceilings VALUES(?,?,?,?) ON CONFLICT(credential,unit,seconds) '
                           'DO UPDATE SET amount=MIN(amount,excluded.amount)',
                           (key_hash, limit['unit'], limit['seconds'], limit['amount']))
            self._check(db, registry, account, units, key_hash, now)
            if task:
                row = db.execute('SELECT cancelled,status,run FROM tasks WHERE id=?', (task,)).fetchone()
                if not row or row['cancelled'] or row['status'] != 'running' or row['run'] != run:
                    raise Unavailable('Task is cancelled or not owned by this run')
            attempt = uuid.uuid4().hex
            db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,1,?,?,?,?,?)',
                       (attempt, account['id'], account['provider'], account['quota_group'], key_hash,
                        now, 'reserved', canonical(units), task, run, os.getpid()))
            return attempt

    def finish(self, attempt, outcome, *, retry_after=0):
        with self.db(True) as db:
            row = db.execute('SELECT * FROM attempts WHERE id=? AND active=1', (attempt,)).fetchone()
            if not row: raise ValueError('Attempt is not active')
            db.execute('UPDATE attempts SET active=0,outcome=? WHERE id=?', (outcome, attempt))
            if retry_after:
                until = time.time() + min(max(retry_after, 1), 86400)
                buckets = ['group:' + row['quota_group'], 'credential:' + row['credential']]
                if outcome == 'rate': buckets += ['provider:' + row['provider']]
                for bucket in buckets:
                    db.execute('INSERT INTO cooldowns VALUES(?,?) ON CONFLICT(bucket) DO UPDATE SET until=MAX(until,excluded.until)',
                               (bucket, until))

    def attempts(self):
        with self.db() as db:
            return [dict(x) for x in db.execute('SELECT id,account,provider,started,active,outcome,units,task,run,pid FROM attempts ORDER BY started')]

    def submit(self, packet):
        encoded = canonical(packet)
        with self.db(True) as db:
            old = db.execute('SELECT packet_hash FROM tasks WHERE id=?', (packet['id'],)).fetchone()
            if old:
                if old[0] != digest(packet): raise ValueError('Task ID already used for different input')
                return packet['id']
            # Forward dependencies are allowed, but cycles are refused.
            def visit(node, trail):
                if node in trail: raise ValueError('Task dependency cycle')
                row = db.execute('SELECT packet FROM tasks WHERE id=?', (node,)).fetchone()
                deps = packet.get('depends_on', []) if node == packet['id'] else (json.loads(row[0]).get('depends_on', []) if row else [])
                for dep in deps: visit(dep, trail + [node])
            visit(packet['id'], [])
            db.execute('INSERT INTO tasks(id,packet,packet_hash,status) VALUES(?,?,?,?)',
                       (packet['id'], encoded, digest(packet), 'queued'))
        return packet['id']

    def _inputs(self, db, packet):
        result = []
        for name in packet.get('depends_on', []):
            row = db.execute('SELECT * FROM tasks WHERE id=?', (name,)).fetchone()
            if not row or row['status'] != 'accepted' or not row['candidate'] or digest(json.loads(row['candidate'])) != row['candidate_hash']:
                raise Unavailable('Dependency has no current host acceptance')
            receipt = json.loads(row['check_receipt'])
            for item in receipt.get('artifacts', []):
                p = Path(item['path'])
                if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != item['sha256']:
                    raise Unavailable('Accepted dependency artifact changed')
            result.append({'task': name, 'sha256': row['candidate_hash']})
        return result

    def claim(self, only=None, registry=None):
        with self.db(True) as db:
            leases = db.execute('SELECT * FROM leases').fetchall()
            if registry and len(leases) >= registry['max_active']: return None
            rows = db.execute('SELECT * FROM tasks WHERE status=? ORDER BY rowid', ('queued',)).fetchall()
            for row in rows:
                if only and row['id'] != only: continue
                packet = json.loads(row['packet'])
                try: inputs = self._inputs(db, packet)
                except Unavailable: continue
                selected = None
                if registry:
                    for a in sorted(registry['accounts'], key=lambda x: (x['priority'], x['id'])):
                        if packet['capability'] not in a['routes'] or (packet.get('account') and packet['account'] != a['id']): continue
                        if (sum(x['provider'] == a['provider'] for x in leases) >= registry['provider_active']
                                or any(x['account'] == a['id'] or x['quota_group'] == a['quota_group'] for x in leases)):
                            continue
                        try: self._check(db, registry, a, {'requests': 1})
                        except Unavailable: continue
                        selected = a; break
                    if selected is None: continue
                run = 'swarm-' + uuid.uuid4().hex
                db.execute('UPDATE tasks SET status=?,run=?,inputs=? WHERE id=?',
                           ('running', run, canonical(inputs), row['id']))
                if selected:
                    db.execute('INSERT INTO leases VALUES(?,?,?,?)', (run, selected['id'], selected['provider'], selected['quota_group']))
                    db.execute('INSERT INTO holders VALUES(?,?)', (run, os.getpid()))
                    return packet, run, selected['id']
                return packet, run
        return None

    def task(self, name):
        with self.db() as db:
            row = db.execute('SELECT * FROM tasks WHERE id=?', (identifier(name),)).fetchone()
            if not row: raise ValueError('Unknown task')
            result = dict(row)
            for field in ('packet', 'candidate', 'check_receipt', 'inputs'):
                result[field] = json.loads(result[field]) if result[field] else None
            result['candidate_sha256'] = result.pop('candidate_hash')
            return result

    def cancelled(self, name): return bool(self.task(name)['cancelled'])

    def cancel(self, name):
        with self.db(True) as db:
            row = db.execute('SELECT status FROM tasks WHERE id=?', (identifier(name),)).fetchone()
            if not row or row[0] not in ('queued', 'running'): raise ValueError('Task is not pending')
            db.execute('UPDATE tasks SET cancelled=1,status=CASE WHEN status=? THEN ? ELSE status END WHERE id=?',
                       ('queued', 'cancelled', name))

    def complete(self, name, run, candidate=None, error=None):
        with self.db(True) as db:
            row = db.execute('SELECT * FROM tasks WHERE id=?', (name,)).fetchone()
            if not row or row['status'] != 'running' or row['run'] != run: raise ValueError('Run does not own task')
            status = 'cancelled' if row['cancelled'] else ('candidate' if candidate else 'failed')
            if status == 'candidate':
                if self._inputs(db, json.loads(row['packet'])) != json.loads(row['inputs']):
                    raise ValueError('Dependency changed during execution')
            if status != 'candidate': candidate = None
            db.execute('UPDATE tasks SET status=?,candidate=?,candidate_hash=?,error=? WHERE id=?',
                       (status, canonical(candidate) if candidate else None, digest(candidate) if candidate else None, error, name))
            db.execute('DELETE FROM leases WHERE run=?', (run,))
            db.execute('DELETE FROM holders WHERE run=?', (run,))

    def reconcile(self, run, *, stopped):
        identifier(run)
        with self.db(True) as db:
            task = db.execute('SELECT * FROM tasks WHERE run=? AND status=?', (run, 'running')).fetchone()
            holder = db.execute('SELECT pid FROM holders WHERE run=?', (run,)).fetchone()
            if not task or not holder or not stopped(holder['pid']):
                raise ValueError('Run is unknown or process exit is unconfirmed')
            attempts = db.execute('SELECT pid FROM attempts WHERE run=? AND active=1', (run,)).fetchall()
            if any(not stopped(x['pid']) for x in attempts): raise ValueError('An attempt owner is still active')
            # Retain all request/token/audio reservations: remote completion remains unknown.
            db.execute('UPDATE attempts SET active=0,outcome=? WHERE run=? AND active=1', ('interrupted_unknown', run))
            db.execute('UPDATE tasks SET status=?,error=? WHERE run=?', ('failed', 'reconciled_after_confirmed_process_exit', run))
            db.execute('DELETE FROM leases WHERE run=?', (run,))
            db.execute('DELETE FROM holders WHERE run=?', (run,))

    def accept(self, name, candidate_hash, receipt):
        with self.db(True) as db:
            row = db.execute('SELECT * FROM tasks WHERE id=?', (name,)).fetchone()
            if (not row or row['status'] != 'candidate' or row['candidate_hash'] != candidate_hash
                    or digest(json.loads(row['candidate'])) != candidate_hash or receipt.get('exit_code') != 0
                    or not receipt.get('argv')): raise ValueError('Host verification does not match candidate')
            if self._inputs(db, json.loads(row['packet'])) != json.loads(row['inputs']):
                raise ValueError('Dependency changed before acceptance')
            db.execute('UPDATE tasks SET status=?,check_receipt=? WHERE id=?', ('accepted', canonical(receipt), name))

    def tasks(self):
        with self.db() as db: return [dict(x) for x in db.execute('SELECT id,status,run,error,cancelled FROM tasks ORDER BY rowid')]
