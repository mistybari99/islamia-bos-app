#!/usr/bin/env python3
"""Compares a RESTORED database with the backup it came from: row counts AND a checksum of the rows of every table. READ ONLY (only SELECT).

    python3 tools/verify_restore.py <backup_folder> --dsn postgresql://postgres@localhost:5432/mydb [--report verify.json] [--tables a,b] [--allow-remote]

<backup_folder> is a (decrypted) backup folder with manifest.json (tools/backup_crypto.py decrypt first when it is encrypted).
For every table in the manifest it reads the rows of the database (to_jsonb(t), session time zone UTC), writes each row in the same canonical form as tools/backup_dump.py,
takes the sha256 of every row line, sorts them and hashes them (rows_sha256: independent of the row order and of compression). That must equal the rows_sha256 of the backup
(computed from the backup file when an older manifest has none) and the row count must be equal. Also checked, when the backup has accounts.json: every login of the list
exists in auth.users with the same id and e-mail, and no profile is without a login (a profile without login cannot sign in).
Safety: without --allow-remote the target must be localhost / 127.0.0.1 / ::1 / a unix socket. With --allow-remote you may check a new Supabase project through its
database connection string; the tool still only runs SELECT statements. It never reads SUPABASE_* variables and never prints a password.
Output: ONE JSON document on stdout (PASS / FAIL). Exit 0 = PASS, 1 = FAIL, 2 = could not run. Python 3 standard library + the psql client.
"""
import argparse
import gzip
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402
import restore_backup as rb  # noqa: E402
import restore_drill as rd  # noqa: E402

SAFE = re.compile(r'^[a-z_][a-z0-9_]{0,62}$')


def line_digest(line):
    return hashlib.sha256(line.encode('utf-8')).digest()


def digest_of(digests):
    return hashlib.sha256(b''.join(sorted(digests))).hexdigest()


def backup_digest(folder, info):
    """(rows, rows_sha256) of one backup file, computed from the file itself (the manifest value is compared separately)."""
    ds = [line_digest(ln) for ln in rb.iter_lines(os.path.join(folder, info['file']))]
    return len(ds), digest_of(ds)


def db_digest(dsn, psql, table):
    """(rows, rows_sha256) of one table of the database, streamed through psql."""
    if not SAFE.match(table):
        raise ValueError('unsafe table name ' + repr(table))
    cmd = shlex.split(psql) + ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', dsn, '-c', f'select to_jsonb(t)::text from public.{table} t']
    env = dict(os.environ, PGOPTIONS='-c timezone=UTC', PGCLIENTENCODING='UTF8')
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    ds = []
    for raw in p.stdout:
        line = raw.decode('utf-8').rstrip('\n')
        if line:
            ds.append(line_digest(oc.dumps_exact(oc.loads_exact(line))))
    err = p.stderr.read().decode('utf-8', 'replace')
    if p.wait() != 0:
        raise RuntimeError(oc.REDACT(err.strip()[:400]))
    return len(ds), digest_of(ds)


def verify(folder, dsn, psql='psql', only=None, allow_remote=False, log=oc.log):
    host, _db = rd.parse_dsn(dsn)
    if not allow_remote and not (host == '' or host.startswith('/') or host.lower() in rd.LOCAL_HOSTS):
        raise rd.Refused(f'host {host!r} is not local; add --allow-remote to read from a remote database (SELECT only)')
    m = rb.load_manifest(folder)
    names = sorted(only) if only else sorted(m['tables'])
    checks = []
    report = {'tool': 'verify_restore.py', 'result': 'FAIL', 'backup': {'finished_at': m.get('finished_at'), 'tables': len(names),
              'rows': sum(m['tables'][t]['rows'] for t in names), 'manifest_version': m.get('manifest_version', 1)}, 'checks': checks}
    bad = rb.verify(folder, m, names)
    checks.append({'name': 'backup_intact', 'ok': not bad, 'detail': bad or f'{len(names)} files match manifest.json (sha256, rows, row checksum)'})
    if bad:
        return finish(report)
    diffs, same = {}, 0
    for t in names:
        info = m['tables'][t]
        want_rows, want_sha = info['rows'], info.get('rows_sha256') or backup_digest(folder, info)[1]
        got_rows, got_sha = db_digest(dsn, psql, t)
        if got_rows != want_rows:
            diffs[t] = {'rows_backup': want_rows, 'rows_database': got_rows}
        elif got_sha != want_sha:
            diffs[t] = {'rows': got_rows, 'problem': 'same number of rows but different content (checksum differs)'}
        else:
            same += 1
        log(f'{t}: {"ok" if t not in diffs else "DIFFERENT"}')
    checks.append({'name': 'tables_match', 'ok': not diffs, 'detail': {'tables_compared': len(names), 'identical': same, 'different': diffs}})
    ex = (m.get('extras') or {}).get('accounts')
    if ex and not only:
        with open(os.path.join(folder, ex['file']), encoding='utf-8') as f:
            accts = json.load(f)['accounts']
        db = rd.Pg(dsn, psql)
        have = {r['id']: r['email'] for r in (db.json("select coalesce(jsonb_agg(jsonb_build_object('id', id, 'email', lower(email))), '[]'::jsonb) from auth.users") or [])}
        missing = [a['staff_id'] for a in accts if a['id'] not in have]
        wrong = [a['staff_id'] for a in accts if a['id'] in have and a.get('email') and have[a['id']] != a['email']]
        checks.append({'name': 'logins', 'ok': not missing and not wrong, 'detail': {'in_list': len(accts), 'missing_in_auth': missing, 'email_differs': wrong}})
        orphan = int(db.run('select count(*) from public.profiles p where not exists (select 1 from auth.users u where u.id = p.id)').strip() or 0)
        checks.append({'name': 'profiles_have_login', 'ok': orphan == 0, 'detail': {'profiles_without_login': orphan}})
    elif not only:
        report['note'] = 'this backup has no staff / login list (rule backup_accounts_on was OFF): logins were not checked'
    return finish(report)


def finish(report):
    report['result'] = 'PASS' if report['checks'] and all(c['ok'] for c in report['checks']) else 'FAIL'
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('backup')
    ap.add_argument('--dsn', required=True)
    ap.add_argument('--psql', default=os.environ.get('BOS_PSQL', 'psql'))
    ap.add_argument('--report', default='')
    ap.add_argument('--tables', default='')
    ap.add_argument('--allow-remote', action='store_true')
    a = ap.parse_args(argv)
    try:
        rep = verify(a.backup, a.dsn, a.psql, [x for x in a.tables.split(',') if x.strip()] or None, a.allow_remote)
    except rd.Refused as e:
        print(json.dumps({'tool': 'verify_restore.py', 'result': 'REFUSED', 'reason': oc.REDACT(str(e))}, indent=1))
        return 2
    except (RuntimeError, OSError, ValueError, KeyError) as e:
        print(json.dumps({'tool': 'verify_restore.py', 'result': 'ERROR', 'reason': oc.REDACT(str(e))}, indent=1))
        return 2
    text = json.dumps(rep, ensure_ascii=False, indent=1, default=str)
    if a.report:
        with open(a.report, 'w', encoding='utf-8') as f:
            f.write(text + '\n')
    print(text)
    return 0 if rep['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
