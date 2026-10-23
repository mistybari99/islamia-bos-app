#!/usr/bin/env python3
"""Restore drill: prove that a backup made by tools/backup_dump.py can really be restored, into a SCRATCH local Postgres only.

    python3 tools/restore_drill.py <backup_folder> --dsn postgresql://postgres@localhost:5432/bos_scratch [--report drill.json] [--no-restore]
    (a unix socket works too:  --dsn "postgresql://postgres@/bos_scratch?host=/tmp&port=5544")

<backup_folder> is either one backup (has manifest.json) or a folder that holds several (the NEWEST by finished_at is used).
The scratch database must already contain the app schema (build it from the phase SQL files, see docs/RESTORE_DRILL.md) and be run by a Postgres
superuser (the restore switches foreign keys and the append-only guards off for its own session only).

SAFETY: the tool REFUSES (exit 2, nothing is run) unless the DSN host is localhost / 127.0.0.1 / ::1 / a unix socket AND the database name contains the word
"scratch". It never reads SUPABASE_* variables and never talks to the live project. After connecting it checks again that the server really is local.

What it checks after the restore (each is one line of the JSON report):
  backup_intact   every file matches manifest.json (sha256 + row count)             tables_list     manifest table list == the scratch schema's _backup_tables()
  functions       key functions exist                                               rls             row level security is on for EVERY public table
  row_counts      rows per table in the scratch DB == rows in the manifest           journal         every journal entry has debit = credit
  stock           per item+place: sum(stock_ledger.qty_delta) == stock_balance.qty
The report also lists what the dump skips by design (skipped_by_dump) and reminds that auth users and Storage photos are not in the backup.
Output: ONE JSON document on stdout (PASS / FAIL), progress on stderr. Exit 0 = PASS, 1 = FAIL, 2 = refused / cannot run. Python 3 standard library + the psql client.
"""
import argparse
import contextlib
import decimal
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402
import restore_backup as rb  # noqa: E402

LOCAL_HOSTS = {'localhost', '127.0.0.1', '::1', '[::1]'}
KEY_FUNCTIONS = ['is_owner', 'is_active', 'can_loc', 'rule_num', 'set_rule', 'backup_manifest', 'backup_dump', 'backup_log', 'backup_status', '_backup_tables',
                 'save_entry', 'stock_opening', 'stock_issue', 'path_switch_set', 'no_hard_delete', 'log_change']
OPTIONAL_FUNCTIONS = ['restore_drill_record', 'restore_drill_status', 'backup_coverage106']          # phase70: reported but never a failure
SKIP_REASONS = [                                                                   # why the dump leaves a table out (mirrors public._backup_tables())
    (r'_secret', 'name contains _secret (credentials)'), (r'^ops_', 'ops_* (bot accounts; listed in the staff manifest)'),
    (r'^(login_failures|login_attempts|login_throttle)$', 'login throttle data (re-created by use)'),
    (r'^(backup_runs|notifications|notification_reads)$', 'run-time table of the backup / notification module (re-created by the app)'),
]
NOT_IN_BACKUP = ['auth users (logins): the nightly backup holds a staff / login LIST (accounts.json, when the rule backup_accounts_on is ON) - tools/restore_accounts.py re-creates them with the same ids; passwords and PINs are never saved: every person gets a new PIN',
                 'Storage photos and files: tools/backup_photos.py (+ tools/restore_storage.py); not part of this drill',
                 'passwords / PIN hashes / device token hashes / 2FA enrolments / edge function secret VALUES (deliberately excluded; the names are in manifest.json)',
                 'run tools/verify_restore.py on the restored database to compare the CONTENT (row checksums), not only the counts']


class Refused(Exception):
    pass


def parse_dsn(dsn):
    """Returns (host, dbname). host '' = default unix socket. Handles URL form and 'key=value key=value' form."""
    dsn = (dsn or '').strip()
    if not dsn:
        raise Refused('no --dsn given')
    if re.match(r'^postgres(ql)?://', dsn):
        u = urllib.parse.urlparse(dsn)
        q = urllib.parse.parse_qs(u.query)
        host = (q.get('host') or [u.hostname or ''])[0]
        db = urllib.parse.unquote((u.path or '').lstrip('/')) or (q.get('dbname') or [''])[0]
        if ',' in (u.netloc.split('@')[-1]):
            raise Refused('several hosts in one DSN are not allowed')
    else:
        kv = dict(re.findall(r"(\w+)\s*=\s*('(?:[^'\\]|\\.)*'|\S+)", dsn))
        kv = {k: v.strip("'") for k, v in kv.items()}
        host, db = kv.get('host', ''), kv.get('dbname', '')
        if ',' in host:
            raise Refused('several hosts in one DSN are not allowed')
    return host, db


def check_target(dsn):
    host, db = parse_dsn(dsn)
    if not (host == '' or host.startswith('/') or host.lower() in LOCAL_HOSTS):
        raise Refused(f'host {host!r} is not local (only localhost / 127.0.0.1 / ::1 / a unix socket may be used)')
    if 'supabase' in dsn.lower() or 'pooler' in dsn.lower():
        raise Refused('this looks like a Supabase address - never run a drill against the live project')
    if not db or 'scratch' not in db.lower():
        raise Refused(f'database name {db!r} does not contain "scratch" - create a database named like bos_scratch and use that')
    return host, db


class Pg:
    """Thin psql wrapper (no driver needed)."""

    def __init__(self, dsn, psql='psql'):
        self.dsn, self.psql = dsn, shlex.split(psql)

    def run(self, sql=None, file=None):
        cmd = self.psql + ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', self.dsn]
        cmd += ['-c', sql] if sql is not None else ['-f', file]
        p = subprocess.run(cmd, capture_output=True, text=True)
        if p.returncode != 0:
            raise RuntimeError(oc.REDACT((p.stderr or p.stdout).strip()[:1500]))
        return p.stdout

    def json(self, sql):
        out = self.run(sql).strip()
        return oc.loads_exact(out) if out else None


def newest_backup(folder):
    if os.path.isfile(os.path.join(folder, 'manifest.json')):
        return folder
    best = None
    for d in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        p = os.path.join(folder, d)
        if os.path.isfile(os.path.join(p, 'manifest.json')):
            try:
                fin = rb.load_manifest(p).get('finished_at') or ''
            except (OSError, ValueError):
                continue
            if best is None or fin > best[0]:
                best = (fin, p)
    if best is None:
        raise Refused(f'no backup (manifest.json) found in {folder}')
    return best[1]


def chk(name, ok, detail=None):
    return {'name': name, 'ok': bool(ok), 'detail': detail if detail is not None else ''}


def skipped_by_dump(db, expected):
    rows = db.json("select coalesce(jsonb_agg(jsonb_build_object('table', c.relname, 'bad_columns', (select coalesce(jsonb_agg(a.attname order by a.attnum), '[]'::jsonb) "
                   "from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attname ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)' "
                   "and a.attname !~ '^(tokens_(in|out)|token_[ab])$')) order by c.relname), '[]'::jsonb) from pg_class c where c.relnamespace = 'public'::regnamespace "
                   "and c.relkind in ('r', 'p') and not c.relispartition")
    out = []
    for r in rows or []:
        if r['table'] in expected:
            continue
        why = next((w for pat, w in SKIP_REASONS if re.search(pat, r['table'])), None)
        if why is None and r['bad_columns']:
            why = 'has secret-looking column(s): ' + ', '.join(r['bad_columns'])
        out.append({'table': r['table'], 'reason': why or 'not in _backup_tables()'})
    return out


def run_drill(backup_dir, dsn, psql='psql', restore=True, log=oc.log):
    """Returns the report dict. Raises Refused when the target is not an acceptable scratch DB."""
    host, dbname = check_target(dsn)
    folder = newest_backup(backup_dir)
    man = rb.load_manifest(folder)
    names = sorted(man['tables'])
    db = Pg(dsn, psql)
    checks = []
    report = {'tool': 'restore_drill.py', 'result': 'FAIL', 'backup': {'name': os.path.basename(os.path.abspath(folder)), 'finished_at': man.get('finished_at'),
              'tables': len(names), 'rows': sum(man['tables'][t]['rows'] for t in names), 'schema_fingerprint': man.get('schema_fingerprint')},
              'scratch': {'host': host or '(default socket)', 'database': dbname}, 'checks': checks, 'not_in_backup': NOT_IN_BACKUP}
    # 1. the backup itself
    bad = rb.verify(folder, man, names)
    checks.append(chk('backup_intact', not bad, bad or f'{len(names)} files match manifest.json'))
    if bad:
        return finish(report)
    # 2. the target really is a local scratch server
    who = db.json("select jsonb_build_object('db', current_database(), 'addr', inet_server_addr()::text, 'super', (select rolsuper from pg_roles where rolname = current_user))")
    addr = (who.get('addr') or '').split('/')[0]
    if who['db'] != dbname or (addr and addr not in ('127.0.0.1', '::1')):
        raise Refused(f"connected to {who['db']!r} at {addr!r}: not the local scratch database - stopping")
    if not who['super']:
        raise Refused('the scratch connection must use a Postgres superuser (the restore needs session_replication_role)')
    if not db.run("select to_regprocedure('public._backup_tables()') is not null").strip().startswith('t'):
        raise Refused('the scratch database has no app schema (public._backup_tables() missing): build it from the phase SQL files first (docs/RESTORE_DRILL.md)')
    expected = db.json("select to_jsonb(public._backup_tables())")
    # 3. restore
    if restore:
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, 'restore.sql')
            with contextlib.redirect_stdout(sys.stderr):                       # stdout stays pure JSON
                rc = rb.main([folder, '--out', out, '--truncate', '--split-mb', '64'])
            if rc != 0:
                checks.append(chk('restore', False, 'restore_backup.py refused the backup'))
                return finish(report)
            parts = sorted(f for f in os.listdir(tmp) if f.endswith('.sql'))
            try:
                for f in parts:
                    log(f'restoring {f} ...')
                    db.run(file=os.path.join(tmp, f))
            except RuntimeError as e:
                checks.append(chk('restore', False, str(e)))
                return finish(report)
        checks.append(chk('restore', True, f'{len(parts)} sql file(s) applied'))
    # 4. table list
    missing = sorted(set(expected) - set(names))
    extra = sorted(set(names) - set(expected))
    checks.append(chk('tables_list', not missing and not extra, {'expected': len(expected), 'in_backup': len(names), 'missing_from_backup': missing, 'not_in_scratch_schema': extra}))
    report['skipped_by_dump'] = skipped_by_dump(db, set(expected))
    # 5. functions
    have = set(db.json("select coalesce(jsonb_agg(distinct p.proname), '[]'::jsonb) from pg_proc p where p.pronamespace = 'public'::regnamespace") or [])
    miss = [f for f in KEY_FUNCTIONS if f not in have]
    checks.append(chk('functions', not miss, {'checked': len(KEY_FUNCTIONS), 'missing': miss, 'optional_missing': [f for f in OPTIONAL_FUNCTIONS if f not in have]}))
    # 6. row level security
    norls = db.json("select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb) from pg_class c where c.relnamespace = 'public'::regnamespace "
                    "and c.relkind in ('r', 'p') and not c.relispartition and not c.relrowsecurity")
    total = int(db.run("select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind in ('r', 'p') and not relispartition").strip())
    checks.append(chk('rls', not norls, {'tables': total, 'without_rls': norls}))
    # 7. row counts
    counts = db.json("select coalesce(jsonb_object_agg(c.relname, (xpath('/row/n/text()', query_to_xml(format('select count(*) n from public.%I', c.relname), false, true, '')))[1]::text::bigint), '{}'::jsonb) "
                     "from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relispartition")
    diffs = {t: {'backup': man['tables'][t]['rows'], 'restored': counts.get(t)} for t in names if counts.get(t) != man['tables'][t]['rows']}
    checks.append(chk('row_counts', not diffs, {'tables_compared': len(names), 'rows': report['backup']['rows'], 'different': diffs}))
    # 8. journal debit = credit
    if 'journal_lines' in counts:
        j = db.json("select jsonb_build_object('entries', (select count(distinct entry_id) from public.journal_lines), 'debit', coalesce(sum(debit), 0), 'credit', coalesce(sum(credit), 0), "
                    "'unbalanced_entries', (select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) x)) from public.journal_lines")
        checks.append(chk('journal', j['unbalanced_entries'] == 0 and decimal.Decimal(str(j['debit'])) == decimal.Decimal(str(j['credit'])), j))
    else:
        checks.append(chk('journal', False, 'journal_lines table is missing'))
    # 9. stock ledger vs balances
    if 'stock_ledger' in counts and 'stock_balance' in counts:
        s = db.json("select jsonb_build_object('pairs', count(*), 'mismatch', count(*) filter (where coalesce(l.q, 0) <> coalesce(b.qty, 0)), "
                    "'examples', coalesce(jsonb_agg(jsonb_build_object('item', coalesce(l.item_id, b.item_id), 'place', coalesce(l.location_id, b.location_id), 'ledger', l.q, 'balance', b.qty)) "
                    "filter (where coalesce(l.q, 0) <> coalesce(b.qty, 0)), '[]'::jsonb)) from (select item_id, location_id, sum(qty_delta) q from public.stock_ledger group by 1, 2) l "
                    "full join public.stock_balance b on b.item_id = l.item_id and b.location_id = l.location_id")
        s['examples'] = s['examples'][:5]
        checks.append(chk('stock', s['mismatch'] == 0, s))
    else:
        checks.append(chk('stock', False, 'stock_ledger / stock_balance table is missing'))
    return finish(report)


def finish(report):
    by = {c['name']: c['ok'] for c in report['checks']}
    report['tables_ok'] = all(by.get(k) for k in ('backup_intact', 'restore', 'tables_list', 'functions', 'rls')) if 'restore' in by else False
    report['rows_ok'] = all(by.get(k) for k in ('row_counts', 'journal', 'stock'))
    report['result'] = 'PASS' if report['checks'] and all(c['ok'] for c in report['checks']) else 'FAIL'
    report['record_hint'] = {'p_backup_name': report['backup']['name'], 'p_result': report['result'].lower(), 'p_tables_ok': report['tables_ok'], 'p_rows_ok': report['rows_ok']}
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('backup', help='a backup folder (manifest.json inside) or a folder of backups (newest is used)')
    ap.add_argument('--dsn', required=True, help='scratch database only, e.g. postgresql://postgres@localhost:5432/bos_scratch')
    ap.add_argument('--psql', default=os.environ.get('BOS_PSQL', 'psql'), help='psql command (default: psql)')
    ap.add_argument('--report', default='', help='also write the JSON report to this file')
    ap.add_argument('--no-restore', action='store_true', help='only verify what is already in the scratch database (no restore)')
    a = ap.parse_args(argv)
    try:
        rep = run_drill(a.backup, a.dsn, a.psql, restore=not a.no_restore)
    except Refused as e:
        print(json.dumps({'tool': 'restore_drill.py', 'result': 'REFUSED', 'reason': oc.REDACT(str(e))}, ensure_ascii=False, indent=1))
        return 2
    except (RuntimeError, OSError, ValueError) as e:
        print(json.dumps({'tool': 'restore_drill.py', 'result': 'ERROR', 'reason': oc.REDACT(str(e))}, ensure_ascii=False, indent=1))
        return 2
    text = json.dumps(rep, ensure_ascii=False, indent=1, default=str)
    if a.report:
        with open(a.report, 'w', encoding='utf-8') as f:
            f.write(text + '\n')
    print(text)
    return 0 if rep['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
