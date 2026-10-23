#!/usr/bin/env python3
"""Tests for the backup coverage work (phase547, backup_dump extras, backup_photos --all-buckets, backup_seal, restore_backup checks, verify_restore, restore_accounts,
restore_storage).

    python3 tools/test_backup_coverage.py -v

* Unit tests need nothing but Python 3 (fake Storage, fake Auth admin API).
* The END-TO-END test needs the local throwaway Postgres (default: psql -h /tmp -p 5544 -U postgres, env BOS_PG_CMD) and builds a template database with every phase
  (tests/sql/final_build.sh, about 40 s). It seeds ONLY neutral test_* rows, makes a backup (encrypted) through the real SQL functions, wipes (drops) the source database,
  restores into a fresh copy of the schema (logins first, then the data, then the photos) and compares counts and checksums. It never talks to a network or to Supabase.
  Set BOS_COV_REPORT=<file> to also write the proof (counts, checksums) as JSON.
Database names used: bkcov_tpl, bkcov_src, bkcov_new (dropped and re-created each run). Passphrases and keys here are test strings.
"""
import contextlib
import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import backup_crypto as bc  # noqa: E402
import backup_dump as bd  # noqa: E402
import backup_photos as bp  # noqa: E402
import backup_seal as bs  # noqa: E402
import ops_common as oc  # noqa: E402
import restore_accounts as ra  # noqa: E402
import restore_backup as rb  # noqa: E402
import restore_storage as rs  # noqa: E402
import test_restore_drill as TR  # noqa: E402
import verify_restore as vr  # noqa: E402

PW = 'test passphrase: green-river-lamp-77'
OWNER, BOT, CLERK = '00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-00000000c0b0', '00000000-0000-0000-0000-00000000c002'
PHOTOS = {'photos': {'ITEM/test_a.jpg': b'\xff\xd8test-a', 'EXP/test_voucher.jpg': b'\xff\xd8test-voucher', 'GRN/test_grn.jpg': b'\xff\xd8test-grn', 'MAINT/test_m.jpg': b'\xff\xd8test-m'},
          'web-refs': {'ref/test_ref.jpg': b'\xff\xd8test-ref'}, 'payproof': {'pay/1/test_pay.jpg': b'\xff\xd8test-pay'}, 'web-public': {'pub/test_pub.jpg': b'\xff\xd8test-pub'}}


class FakeStorage:
    """Just enough of the Storage API: listing (folders have no id), download, upload."""

    def __init__(self, buckets):
        self.b = {k: dict(v) for k, v in buckets.items()}

    def storage_list(self, bucket, prefix='', limit=1000, offset=0):
        seen, out = set(), []
        for path, data in sorted(self.b.get(bucket, {}).items()):
            if prefix and not path.startswith(prefix + '/'):
                continue
            rest = path[len(prefix) + 1:] if prefix else path
            head, _, tail = rest.partition('/')
            if tail:
                if head not in seen:
                    seen.add(head)
                    out.append({'name': head, 'id': None})
            else:
                out.append({'name': head, 'id': 'x', 'metadata': {'size': len(data)}})
        return out[offset:offset + limit]

    def storage_get(self, bucket, path):
        return self.b[bucket][path]

    def request(self, method, path, body=None, headers=None, raw=False):
        parts = path.split('/storage/v1/object/')[1].split('/', 1)
        bucket, p = parts[0], urllib_unquote(parts[1])
        if method == 'POST':
            if p in self.b.setdefault(bucket, {}):
                raise oc.ApiError(400, 'Duplicate: the resource already exists')
            self.b[bucket][p] = bytes(body)
            return {}
        raise AssertionError(method)


def urllib_unquote(s):
    import urllib.parse
    return urllib.parse.unquote(s)


class CovApi(TR.PgApi):
    """The real SQL functions of a local database, as the backup bot; storage from a FakeStorage."""

    def __init__(self, db, uid, storage):
        super().__init__(db, uid)
        self.fs = storage

    def storage_list(self, *a, **k):
        return self.fs.storage_list(*a, **k)

    def storage_get(self, *a, **k):
        return self.fs.storage_get(*a, **k)


def sha(b):
    return hashlib.sha256(b).hexdigest()


class Unit(unittest.TestCase):
    def test_edge_secret_names_are_names_only(self):
        names = bd.edge_secret_names()
        self.assertIn('ANTHROPIC_API_KEY', names)
        self.assertTrue(names['SUPABASE_ANON_KEY']['set_by_supabase'])
        for v in names.values():
            self.assertEqual(sorted(v), ['functions', 'set_by_supabase'])

    def test_rows_digest_ignores_order(self):
        a = [bd.line_digest(x) for x in ('{"a":1}', '{"b":2}', '{"c":3}')]
        self.assertEqual(bd.rows_digest(a), bd.rows_digest(list(reversed(a))))
        self.assertNotEqual(bd.rows_digest(a), bd.rows_digest(a[:2]))

    def test_other_buckets_listing_copy_and_warnings(self):
        class A(FakeStorage):
            def rpc(self, fn, args=None):
                assert fn == 'backup_storage_buckets'
                return {'buckets': [{'id': 'photos', 'objects': 4, 'bot_can_read': True}, {'id': 'web-refs', 'objects': 1, 'bot_can_read': True},
                                    {'id': 'payproof', 'objects': 1, 'bot_can_read': False}, {'id': 'web-public', 'objects': 1, 'bot_can_read': False}]}
        with tempfile.TemporaryDirectory() as w:
            api = A(PHOTOS)
            gd = os.path.join(w, 'latest', 'photos')
            m = bp.run(api, gd, os.path.join(w, 'drive', 'photos'))
            self.assertEqual((m['files'], m['failed']), (4, 0))
            self.assertTrue(all(e.get('sha256') for e in m['entries']))
            summary, failed = bp.run_other_buckets(api, gd, os.path.join(w, 'drive', 'photos'))
            self.assertEqual(failed, 0)
            self.assertTrue(os.path.isfile(os.path.join(w, 'latest', 'buckets', 'web-refs', 'ref', 'test_ref.jpg')))
            self.assertFalse(os.path.exists(os.path.join(w, 'latest', 'buckets', 'payproof')))
            self.assertEqual(len(summary['warnings']), 2, summary)
            self.assertTrue(os.path.isfile(os.path.join(w, 'latest', 'storage_manifest_web-refs.json')))
            self.assertTrue(os.path.isfile(os.path.join(w, 'latest', 'storage_buckets.json')))
            # a second run adds nothing and still reports every checksum
            m2 = bp.run(api, gd, os.path.join(w, 'drive', 'photos'))
            self.assertEqual(m2['new'], 0)
            self.assertEqual([e['sha256'] for e in m['entries']], [e['sha256'] for e in m2['entries']])

    def test_seal_verifies_and_detects_a_changed_photo(self):
        with tempfile.TemporaryDirectory() as w:
            api = FakeStorage(PHOTOS)
            latest, out = os.path.join(w, 'latest'), os.path.join(w, 'out')
            os.makedirs(out)
            bp.run(api, os.path.join(latest, 'photos'), os.path.join(w, 'd'))
            with open(os.path.join(out, 'manifest.json'), 'w') as f:
                json.dump({'tables': {}}, f)
            with T_quiet():
                self.assertEqual(bs.main(['--out', out, '--storage-dir', latest]), 0)
            man = json.load(open(os.path.join(out, 'manifest.json')))
            self.assertEqual(man['storage']['status'], 'ok')
            self.assertEqual(man['storage']['buckets']['photos']['files'], 4)
            self.assertTrue(os.path.isfile(os.path.join(out, 'photos_manifest.json')))
            with open(os.path.join(latest, 'photos', 'ITEM', 'test_a.jpg'), 'wb') as f:      # same size, other content
                f.write(b'\xff\xd8test-X')
            with T_quiet():
                self.assertEqual(bs.main(['--out', out, '--storage-dir', latest]), 1)
            self.assertEqual(json.load(open(os.path.join(out, 'manifest.json')))['storage']['status'], 'problem')

    def test_accounts_create_never_sends_a_password_hash_and_skips_existing(self):
        sent = []

        class R:
            def __init__(self, st, body):
                self.status, self._b = st, json.dumps(body).encode()

            def read(self):
                return self._b

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        def opener(req, timeout=0):
            body = json.loads(req.data)
            sent.append((req.get_method(), req.full_url, body))
            if body['email'] == 'test_b@test.invalid':
                raise urllib.error.HTTPError(req.full_url, 422, 'x', {}, io.BytesIO(b'{"msg":"email already registered"}'))
            return R(200, {'id': body['id']})
        with tempfile.TemporaryDirectory() as w:
            acc = {'enabled': True, 'logins': 2, 'accounts': [
                {'id': CLERK, 'staff_id': 'test_a', 'email': 'test_a@test.invalid', 'full_name': 'test_a', 'roles': ['storekeeper'], 'locations': [1], 'grants': [], 'status': 'active'},
                {'id': OWNER, 'staff_id': 'test_b', 'email': 'test_b@test.invalid', 'full_name': 'test_b', 'roles': [], 'locations': [], 'grants': [], 'status': 'active'}],
                'ops_accounts': [{'user_id': BOT, 'purpose': 'backup', 'active': True}], 'attendance_devices': [{'name': 'test_dev', 'location_id': 1}]}
            data = (oc.dumps_exact(acc) + '\n').encode()
            open(os.path.join(w, 'accounts.json'), 'wb').write(data)
            json.dump({'extras': {'accounts': {'file': 'accounts.json', 'sha256': sha(data), 'items': 2}}}, open(os.path.join(w, 'manifest.json'), 'w'))
            old = os.environ.get('SUPABASE_SERVICE_KEY')
            os.environ['SUPABASE_SERVICE_KEY'] = 'test-admin-key-not-real'
            try:
                adm_orig = ra.Admin
                ra.Admin = lambda base, key: adm_orig(base, key, opener=opener)
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    rc = ra.main(['create', w, '--url', 'https://x.example.test', '--follow-up', os.path.join(w, 'f.sql')])
            finally:
                ra.Admin = adm_orig
                if old is None:
                    os.environ.pop('SUPABASE_SERVICE_KEY')
                else:
                    os.environ['SUPABASE_SERVICE_KEY'] = old
            self.assertEqual(rc, 0, buf.getvalue())
            self.assertIn('created  test_a', buf.getvalue())
            self.assertIn('exists   test_b', buf.getvalue())
            first = sent[0][2]
            self.assertEqual(first['id'], CLERK)
            self.assertTrue(first['email_confirm'])
            self.assertNotIn('encrypted_password', first)
            self.assertTrue(first['password'].endswith('-bos') and len(first['password']) > 20)       # random, thrown away
            self.assertNotIn(first['password'], buf.getvalue())
            self.assertIn("insert into public.ops_accounts", open(os.path.join(w, 'f.sql')).read())
            # a tampered list is refused
            open(os.path.join(w, 'accounts.json'), 'ab').write(b' ')
            with self.assertRaises(SystemExit):
                ra.load_accounts(w)

    def test_reset_pin_rules(self):
        old = os.environ.get('SUPABASE_SERVICE_KEY')
        os.environ['SUPABASE_SERVICE_KEY'] = 'test-admin-key-not-real'
        os.environ['T_PIN'] = '12'
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(ra.main(['reset-pin', 'test_a', '--url', 'https://x.example.test', '--pin-env', 'T_PIN']), 2)
        finally:
            os.environ.pop('T_PIN')
            if old is None:
                os.environ.pop('SUPABASE_SERVICE_KEY')
            else:
                os.environ['SUPABASE_SERVICE_KEY'] = old

    def test_restore_storage_checks_sha_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as w:
            src = FakeStorage(PHOTOS)
            latest, out = os.path.join(w, 'latest'), os.path.join(w, 'out')
            os.makedirs(out)
            bp.run(src, os.path.join(latest, 'photos'), os.path.join(w, 'd'))
            json.dump({'tables': {}}, open(os.path.join(out, 'manifest.json'), 'w'))
            with T_quiet():
                bs.main(['--out', out, '--storage-dir', latest])
            dst = FakeStorage({'photos': {}})
            dst.b['photos']['ITEM/test_a.jpg'] = b'already-there'
            with T_quiet():
                rep = rs.upload_all(dst, out, latest)
            self.assertEqual(rep['result'], 'PASS', rep)
            self.assertEqual(rep['buckets']['photos']['existed'], 1)
            self.assertEqual(dst.b['photos']['ITEM/test_a.jpg'], b'already-there')
            self.assertEqual(dst.b['photos']['EXP/test_voucher.jpg'], PHOTOS['photos']['EXP/test_voucher.jpg'])
            with open(os.path.join(latest, 'photos', 'GRN', 'test_grn.jpg'), 'wb') as f:
                f.write(b'\xff\xd8test-XXX')
            dst2 = FakeStorage({'photos': {}})
            with T_quiet():
                rep = rs.upload_all(dst2, out, latest)
            self.assertEqual(rep['result'], 'FAIL')
            self.assertNotIn('GRN/test_grn.jpg', dst2.b['photos'])

    def test_restore_sql_ends_with_the_count_check(self):
        sql = rb.verify_sql(['items', 'sales'], {'items': 3, 'sales': 0}, True)
        self.assertIn("('items', 3)", sql)
        self.assertIn('n <> r.want', sql)
        self.assertIn('n < r.want', rb.verify_sql(['items'], {'items': 1}, False))
        with self.assertRaises(SystemExit):
            rb.verify_sql(['x; drop table y'], {'x; drop table y': 1}, True)


@contextlib.contextmanager
def T_quiet():
    with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
        yield


SEED = f"""
insert into auth.users (id, email, raw_user_meta_data) values ('{OWNER}', 'test_owner_cov@test.invalid', '{{"full_name":"test_owner_cov"}}'),
  ('{BOT}', 'test_bot_cov@test.invalid', '{{}}'), ('{CLERK}', 'test_clerk_cov@test.invalid', '{{"full_name":"test_clerk_cov"}}') on conflict do nothing;
update profiles set status = 'active' where id in ('{OWNER}', '{CLERK}');
insert into user_roles values ('{OWNER}', 'owner'), ('{CLERK}', 'storekeeper') on conflict do nothing;
insert into user_locations values ('{CLERK}', 1), ('{CLERK}', 2) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id, note) values ('{CLERK}', 'price_override', 1, 'test_grant_cov');
insert into ops_accounts (user_id, purpose) values ('{BOT}', 'backup');
insert into attendance_devices (name, location_id, token_hash) values ('test_device_cov', 1, 'test_hash_must_not_leave');
select set_config('request.jwt.claim.sub', '{OWNER}', false);
select set_rule('backup_accounts_on', 'true'::jsonb);
select set_rule('backup_buckets_on', 'true'::jsonb);
select set_rule('backup_encrypt_on', 'true'::jsonb);
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('test_cov_a', 'test_cov_a', 'test_cov_a', 'kg', 'kg', 'raw_material', true, 0),
  ('test_cov_b', 'test_cov_b', 'test_cov_b', 'kg', 'kg', 'finished_good', true, 55.50);
select stock_opening((select id from items where code = 'test_cov_a'), 1, 100, 10, null, 'test seed');
select stock_issue((select id from items where code = 'test_cov_a'), 1, 3, null, 'test issue');
insert into customers (mobile, name, credit_limit, note) values ('test_mobile_1', 'test_customer_cov_1', 1000.50, 'line one
line two with "quotes" and bangla: ব্যাকআপ'), ('test_mobile_2', 'test_customer_cov_2', 0, null);
insert into suppliers (name, note) values ('test_supplier_cov', 'x');
begin;
insert into journal_entries (entry_date, source_type, source_id, memo) values (current_date, 'test', '1', 'test_cov');
insert into journal_lines select (select max(id) from journal_entries), 1, (select min(id) from coa_accounts), 100, 0;
insert into journal_lines select (select max(id) from journal_entries), 2, (select max(id) from coa_accounts), 0, 100;
commit;
"""


@unittest.skipUnless(TR.pg_available(), 'needs the local Postgres (psql -h /tmp -p 5544 -U postgres)')
class EndToEnd(unittest.TestCase):
    def test_backup_wipe_restore_compare(self):
        proof = {}
        with tempfile.TemporaryDirectory() as w:
            # 1. schema template and the "old project"
            for db in ('bkcov_src', 'bkcov_new'):
                TR.dropdb(db)
            p = subprocess.run(['bash', os.path.join(ROOT, 'tests', 'sql', 'final_build.sh'), 'bkcov_tpl'], capture_output=True, text=True, env=dict(os.environ, PGPORT='5544'))
            self.assertIn('built bkcov_tpl', p.stdout, p.stdout[-500:] + p.stderr[-500:])
            TR.psql('postgres', 'create database bkcov_src template bkcov_tpl')
            TR.psql('bkcov_src', SEED)
            TR.psql('bkcov_src', f"insert into storage.buckets (id, name, public) values ('payproof', 'payproof', false), ('web-refs', 'web-refs', false), ('web-public', 'web-public', true) on conflict (id) do nothing")
            for b, files in PHOTOS.items():
                for path in files:
                    TR.psql('bkcov_src', f"insert into storage.objects (bucket_id, name) values ('{b}', '{path}')")
            counts_src = {t: int(TR.psql('bkcov_src', f'select count(*) from public.{t}').strip()) for t in ('items', 'customers', 'stock_ledger', 'journal_lines', 'user_grants', 'profiles', 'ai_agents', 'rules')}
            # 2. the nightly backup, as the workflow does it
            api = CovApi('bkcov_src', BOT, FakeStorage(PHOTOS))
            out, latest = os.path.join(w, 'out'), os.path.join(w, 'data', 'latest')
            with T_quiet():
                man = bd.run(api, out, encrypt='on', env={'BACKUP_PASSPHRASE': PW})
                pm = bp.run(api, os.path.join(latest, 'photos'), os.path.join(w, 'drive', 'photos'))
                summary, failed = bp.run_other_buckets(api, os.path.join(latest, 'photos'), os.path.join(w, 'drive', 'photos'))
                self.assertEqual(bs.main(['--out', out, '--storage-dir', latest]), 0)
            self.assertEqual((pm['failed'], failed), (0, 0))
            self.assertIn('ai_agents', man['tables'], 'AI settings are now in the dump')
            self.assertNotIn('attendance_devices', man['tables'])
            self.assertIn('accounts', man['extras'])
            for f in os.listdir(out):                       # the workflow copies out/* to latest/
                if os.path.isfile(os.path.join(out, f)):
                    shutil.copyfile(os.path.join(out, f), os.path.join(latest, f))
            blob = b''.join(open(os.path.join(latest, f), 'rb').read() for f in os.listdir(latest) if os.path.isfile(os.path.join(latest, f)))
            for secret in (b'test_hash_must_not_leave', b'test_customer_cov_1', b'test_clerk_cov'):
                self.assertNotIn(secret, blob, 'encrypted: no readable test data in the backup files')
            sealed = json.load(open(os.path.join(latest, 'manifest.json')))
            self.assertEqual(sealed['storage']['status'], 'ok')
            self.assertEqual(sorted(sealed['storage']['buckets']), ['payproof', 'photos', 'web-public', 'web-refs'])
            # 3. decrypt (needs the passphrase), check
            plain = os.path.join(w, 'plain')
            with T_quiet():
                bc.decrypt_dir(latest, plain, bc.derive(PW))
            with self.assertRaises(bc.CryptoError):
                bc.decrypt_dir(latest, os.path.join(w, 'x'), bc.derive(PW + 'x'))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(rb.main([plain, '--dry-run', '--photos-root', latest]), 0)
            self.assertIn(b'test_clerk_cov', open(os.path.join(plain, 'accounts.json'), 'rb').read())
            acc = json.load(open(os.path.join(plain, 'accounts.json')))
            self.assertNotIn('test_hash_must_not_leave', json.dumps(acc))
            # 4. WIPE: the old project is gone; a new empty project (schema only)
            TR.dropdb('bkcov_src')
            TR.psql('postgres', 'create database bkcov_new template bkcov_tpl')
            self.assertEqual(TR.psql('bkcov_new', "select count(*) from public.items where code like 'test%'").strip(), '0', 'the new project holds none of the old test rows')
            # 5. restore: logins first (fake Auth admin API that writes into the new database)
            def opener(req, timeout=0):
                body = json.loads(req.data)
                TR.psql('bkcov_new', f"insert into auth.users (id, email, raw_user_meta_data) values ('{body['id']}', '{body['email']}', '{json.dumps({'full_name': body['user_metadata']['full_name']})}')")

                class R:
                    status = 200

                    def read(self):
                        return b'{}'

                    def __enter__(self):
                        return self

                    def __exit__(self, *a):
                        return False
                return R()
            old = os.environ.get('SUPABASE_SERVICE_KEY')
            os.environ['SUPABASE_SERVICE_KEY'] = 'test-admin-key-not-real'
            adm = ra.Admin
            ra.Admin = lambda base, key: adm(base, key, opener=opener)
            try:
                with T_quiet():
                    self.assertEqual(ra.main(['create', plain, '--url', 'https://x.example.test', '--follow-up', os.path.join(w, 'follow.sql')]), 0)
            finally:
                ra.Admin = adm
                if old is None:
                    os.environ.pop('SUPABASE_SERVICE_KEY')
                else:
                    os.environ['SUPABASE_SERVICE_KEY'] = old
            self.assertEqual(int(TR.psql('bkcov_new', 'select count(*) from auth.users').strip()), len(acc['accounts']))
            # then the data
            with T_quiet():
                self.assertEqual(rb.main([plain, '--out', os.path.join(w, 'restore.sql'), '--truncate', '--split-mb', '64']), 0)
            for f in sorted(x for x in os.listdir(w) if x.startswith('restore') and x.endswith('.sql')):
                TR.psql('bkcov_new', file=os.path.join(w, f))
            # 6. compare: counts and checksums
            with T_quiet():
                rep = vr.verify(plain, TR.dsn('bkcov_new'))
            self.assertEqual(rep['result'], 'PASS', json.dumps(rep, indent=1)[:2000])
            names = {c['name']: c for c in rep['checks']}
            self.assertEqual(names['tables_match']['detail']['identical'], len(man['tables']))
            self.assertTrue(names['logins']['ok'] and names['profiles_have_login']['ok'])
            # the follow-up SQL (bot marks) comes AFTER the comparison: it is itself logged in audit_log
            TR.psql('bkcov_new', file=os.path.join(w, 'follow.sql'))
            self.assertEqual(TR.psql('bkcov_new', "select count(*) from ops_accounts where user_id = '%s'" % BOT).strip(), '1')
            counts_new = {t: int(TR.psql('bkcov_new', f'select count(*) from public.{t}').strip()) for t in counts_src}
            self.assertEqual(counts_src, counts_new)
            # 7. photos back into (fake) new Storage
            new_store = FakeStorage({b: {} for b in PHOTOS})
            with T_quiet():
                srep = rs.upload_all(new_store, plain, latest)
            self.assertEqual(srep['result'], 'PASS', srep)
            self.assertEqual(new_store.b, PHOTOS)
            # 8. the checks really catch damage
            TR.psql('bkcov_new', "update public.customers set note = 'changed' where mobile = 'test_mobile_2'")
            with T_quiet():
                self.assertEqual(vr.verify(plain, TR.dsn('bkcov_new'))['result'], 'FAIL')
            proof = {'tables_in_backup': len(man['tables']), 'rows_in_backup': man['rows'], 'logins': len(acc['accounts']), 'row_counts_source_vs_new': counts_src,
                     'identical_tables': names['tables_match']['detail']['identical'], 'photos_buckets': {k: v['files'] for k, v in sealed['storage']['buckets'].items()},
                     'tables_fingerprint_sample': {t: man['tables'][t]['rows_sha256'][:16] for t in ('customers', 'items', 'journal_lines')}}
        if os.environ.get('BOS_COV_REPORT'):
            with open(os.environ['BOS_COV_REPORT'], 'w') as f:
                json.dump(proof, f, indent=1, sort_keys=True)
        print('PROOF', json.dumps(proof, sort_keys=True), file=sys.stderr)


if __name__ == '__main__':
    unittest.main()
