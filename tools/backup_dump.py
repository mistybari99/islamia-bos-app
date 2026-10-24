#!/usr/bin/env python3
"""Full data backup of the Islamia BOS database, run by GitHub Actions (.github/workflows/backup.yml) with no person and no sandbox involved.

How it works (Python 3 standard library only):
  1. Logs in to Supabase Auth as the dedicated "ops bot" user (NOT the owner, NOT the service_role key) with the PUBLIC anon key.
  2. backup_manifest()  -> the list of tables the server allows, their row counts and a schema fingerprint.
  3. backup_dump(table, cursor, limit) page by page (keyset pagination) -> out/<table>.ndjson.gz (one JSON row per line, sorted by primary key,
     gzip with a fixed timestamp so an unchanged table gives byte-identical output and the git history only grows by real changes).
  4. backup_manifest() again. A table passes only if  rows_at_start <= rows_dumped <= rows_at_end  (rows may be added while we read, never lost) and the
     schema fingerprint did not change during the run. Any mismatch = failure.
  5. out/manifest.json (counts, sha256 of every file, schema version/fingerprint, started/finished) and backup_log('ok'|'failed', ...) so the owner's app shows
     the run and warns when the last good backup is too old.
Exit code 0 only when everything is complete. Secrets come from the environment only: SUPABASE_URL, SUPABASE_ANON_KEY, BOT_EMAIL, BOT_PASSWORD. Nothing secret is printed.

Encryption (item U-12, phase98 rule backup_encrypt_on, default OFF): --encrypt auto|on|off (default auto = follow the rule; an old database without phase98 means off).
When ON the files are written ONLY in encrypted form (<table>.ndjson.gz.enc, format BOSENC1, tools/backup_crypto.py), no plain copy is left in --out, and
manifest.json gets an "encryption" block (no secret in it). The passphrase comes from the environment variable BACKUP_PASSPHRASE (and optionally BACKUP_KDF_SALT).
ON without a usable passphrase makes the run FAIL (and be logged as failed); it never falls back to plain files. To restore: tools/backup_crypto.py decrypt, then the
normal restore_drill.py / restore_backup.py. See docs/integration/W1-G.md.

Usage:  python3 tools/backup_dump.py [--out out] [--page 2000] [--tables a,b] [--no-log] [--destination github] [--encrypt auto|on|off]
"""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backup_crypto as bc  # noqa: E402
import ops_common as oc  # noqa: E402

BIG_FILE_BYTES = 90 * 1024 * 1024        # GitHub refuses single files above 100 MB: warn early


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def rows_digest(line_digests):
    """Order-independent digest of a table: sha256 over the sorted per-row sha256 values. Two databases that hold the same rows give the same digest
    whatever their sort order or compression (used by tools/verify_restore.py to compare a restored database with the backup)."""
    return hashlib.sha256(b''.join(sorted(line_digests))).hexdigest()


def line_digest(line):
    return hashlib.sha256(line.encode('utf-8')).digest()


def gz_bytes(lines, digests=None):
    """Deterministic gzip (mtime 0, no file name) of the given text lines, in memory. Returns (rows, data). When a list is given, the sha256 of every line is appended to it."""
    buf = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=buf, mtime=0, compresslevel=9) as z:
        n = 0
        for ln in lines:
            z.write(ln.encode('utf-8'))
            z.write(b'\n')
            if digests is not None:
                digests.append(line_digest(ln))
            n += 1
    return n, buf.getvalue()


def write_gz(path, lines, digests=None):
    """Deterministic gzip (mtime 0, no file name) of the given text lines. Returns (rows, bytes, sha256-of-the-file)."""
    n, data = gz_bytes(lines, digests)
    with open(path, 'wb') as f:
        f.write(data)
    return n, len(data), hashlib.sha256(data).hexdigest()


def write_enc(path, lines, keys, label, digests=None):
    """Same gzip, encrypted (BOSENC1, deterministic: unchanged content = identical bytes). Only the encrypted file is written. Returns (rows, plain_gz_bytes,
    sha256-of-the-plain-gz, encrypted_bytes, sha256-of-the-encrypted-file)."""
    n, data = gz_bytes(lines, digests)
    blob = bc.encrypt_bytes(keys, label, data)
    with open(path, 'wb') as f:
        f.write(blob)
    return n, len(data), hashlib.sha256(data).hexdigest(), len(blob), hashlib.sha256(blob).hexdigest()


def _function_missing(e):
    """True only for 'this function does not exist' (PostgREST PGRST202 / HTTP 404): a database older than phase98. Anything else is a real error."""
    return getattr(e, 'status', None) == 404 or 'PGRST202' in str(e)


def resolve_encryption(api, mode, env=None):
    """Returns the Keys to encrypt with, or None for a plain backup. mode: 'on' | 'off' | 'auto' (follow the server rule backup_encrypt_on; only a MISSING function (no phase98) means off, any other error stops the run).
    Raises when encryption is wanted but the passphrase is missing or too short (never a silent plain backup)."""
    mode = (mode or 'auto').lower()
    if mode == 'off':
        return None
    if mode == 'auto':
        try:
            st = api.rpc('_w1g_backup_settings')
        except oc.ApiError as e:
            if not _function_missing(e):
                # network trouble, 5xx, expired login, no permission: we cannot tell whether the owner switched encryption ON.
                # Failing is safe (the night's backup is retried and the failure is logged); a plain file pushed by mistake is not.
                raise RuntimeError('cannot read the encryption setting (' + str(e) + '): backup stopped instead of risking a plain copy; fix the cause or set the mode to off/on explicitly') from e
            oc.log('encryption setting not found on the server (no phase98 yet): plain backup, as before')
            return None
        if not isinstance(st, dict):
            raise RuntimeError('the encryption setting gave an unexpected answer: backup stopped instead of risking a plain copy')
        if not st.get('encrypt_on'):
            return None
    try:
        return bc.keys_from_env(env)
    except bc.CryptoError as e:
        raise RuntimeError('encryption is switched on but cannot be used: ' + str(e) + ' (set the secret BACKUP_PASSPHRASE, or switch backup_encrypt_on OFF)')


def dump_table(api, table, page):
    """Yields every row of one table as a compact JSON line, following the server cursor until it is exhausted."""
    cursor, seen, pages = None, set(), 0
    while True:
        r = api.rpc('backup_dump', {'p_table': table, 'p_after_id': cursor, 'p_limit': page})
        if not isinstance(r, dict) or 'rows' not in r:
            raise RuntimeError(f'{table}: unexpected answer from backup_dump')
        for row in r['rows']:
            yield oc.dumps_exact(row)
        cursor = r.get('next')
        pages += 1
        if cursor is None:
            return
        if cursor in seen or pages > 100000:
            raise RuntimeError(f'{table}: the cursor did not advance (stopping to avoid a loop)')
        seen.add(cursor)


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_RE = re.compile(r'Deno\.env\.get\(\s*[\'"]([A-Za-z0-9_]+)[\'"]')
PLATFORM_ENV = {'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_DB_URL'}      # set by Supabase itself in every edge function


def edge_secret_names(root=None):
    """NAMES (never values) of the secrets the edge functions in supabase/functions read with Deno.env.get. A static list from the source code: the anon-key
    bot cannot read the real secrets of the project, so this is what the owner has to set again in a new project (supabase secrets set NAME=...)."""
    base = os.path.join(root or REPO_ROOT, 'supabase', 'functions')
    found = {}
    if os.path.isdir(base):
        for fn in sorted(os.listdir(base)):
            p = os.path.join(base, fn, 'index.ts')
            if os.path.isfile(p):
                with open(p, encoding='utf-8', errors='replace') as f:
                    for name in ENV_RE.findall(f.read()):
                        found.setdefault(name, set()).add(fn)
    return {k: {'functions': sorted(v), 'set_by_supabase': k in PLATFORM_ENV} for k, v in sorted(found.items())}


def paste_order_sha256(root=None):
    p = os.path.join(root or REPO_ROOT, 'tests', 'sql', 'paste_order.env')
    try:
        with open(p, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


def fetch_accounts(api):
    """The staff / login manifest (phase547 backup_accounts_manifest). Returns (dict or None, note). None = not available or switched OFF: the run goes on, the
    manifest says so. Any other error is a failure (a half backup of the logins must not look like a good one)."""
    try:
        r = api.rpc('backup_accounts_manifest')
    except oc.ApiError as e:
        if _function_missing(e):
            return None, 'phase547 is not pasted yet (no backup_accounts_manifest): staff logins are NOT in this backup'
        raise RuntimeError('staff / login manifest failed: ' + str(e)) from e
    if not isinstance(r, dict):
        raise RuntimeError('staff / login manifest: unexpected answer')
    if not r.get('enabled'):
        return None, 'rule backup_accounts_on is OFF: staff logins are NOT in this backup'
    r.pop('generated_at', None)                         # keeps an unchanged list byte-identical from night to night
    return r, 'ok'


def write_extra(out_dir, name, obj, keys):
    """Writes one small JSON document (canonical, sorted keys) plain or, when keys are given, only encrypted. Returns the manifest entry."""
    data = (oc.dumps_exact(obj) + '\n').encode('utf-8')
    plain, enc = os.path.join(out_dir, name), os.path.join(out_dir, name + '.enc')
    for stale in (plain, enc):
        if os.path.exists(stale):
            os.remove(stale)
    entry = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    if keys is None:
        with open(plain, 'wb') as f:
            f.write(data)
        entry['file'] = name
    else:
        blob = bc.encrypt_bytes(keys, name, data)
        with open(enc, 'wb') as f:
            f.write(blob)
        entry.update({'file': name + '.enc', 'enc_bytes': len(blob), 'enc_sha256': hashlib.sha256(blob).hexdigest(), 'encrypted': True})
    return entry


def run(api, out_dir, page=2000, only=None, log_run=True, destination='github', clock=now_iso, encrypt='auto', env=None):
    """Returns the manifest dict. Raises on any failure (after trying to record the failure with backup_log)."""
    started = clock()
    os.makedirs(out_dir, exist_ok=True)
    try:
        keys = resolve_encryption(api, encrypt, env)
        m0 = api.rpc('backup_manifest')
        names = [t['name'] for t in m0['tables']]
        start_rows = {t['name']: int(t['rows']) for t in m0['tables']}
        if only:
            unknown = [t for t in only if t not in start_rows]
            if unknown:
                raise RuntimeError('tables not allowed or unknown: ' + ', '.join(unknown))
            names = list(only)
        # remove files of tables that no longer exist, so the folder is an exact picture of this run
        for f in ([] if only else os.listdir(out_dir)):
            base = f[:-len('.enc')] if f.endswith('.ndjson.gz.enc') else f
            if base.endswith('.ndjson.gz') and base[:-len('.ndjson.gz')] not in names:
                os.remove(os.path.join(out_dir, f))
        files, warnings, total_rows, total_bytes = {}, [], 0, 0
        for t in names:
            plain_name = t + '.ndjson.gz'
            for stale in (plain_name, plain_name + '.enc'):      # the folder is an exact picture of this run: no plain copy next to an encrypted one, and the other way round
                if os.path.exists(os.path.join(out_dir, stale)):
                    os.remove(os.path.join(out_dir, stale))
            digests = []
            if keys is None:
                n, size, sha = write_gz(os.path.join(out_dir, plain_name), dump_table(api, t, page), digests)
                files[t] = {'file': plain_name, 'rows': n, 'bytes': size, 'sha256': sha}
            else:
                n, size, sha, esize, esha = write_enc(os.path.join(out_dir, plain_name + '.enc'), dump_table(api, t, page), keys, plain_name, digests)
                files[t] = {'file': plain_name + '.enc', 'rows': n, 'bytes': size, 'sha256': sha, 'enc_bytes': esize, 'enc_sha256': esha, 'encrypted': True}
                size = esize                                       # the size on disk decides the git warning
            files[t]['rows_sha256'] = rows_digest(digests)
            total_rows += n
            total_bytes += size
            if size > BIG_FILE_BYTES:
                warnings.append(f'{t}: file is {size} bytes - too big for a normal git push; use the Drive copy')
            oc.log(f'{t}: {n} rows')
        m1 = api.rpc('backup_manifest')
        end_rows = {t['name']: int(t['rows']) for t in m1['tables']}
        problems = []
        if m0.get('fingerprint') != m1.get('fingerprint'):
            problems.append('the database schema changed while the backup ran')
        for t in names:
            lo, hi, got = start_rows[t], end_rows.get(t, start_rows[t]), files[t]['rows']
            if not (lo <= got <= max(lo, hi)):
                problems.append(f'{t}: dumped {got} rows but the server counted {lo}..{hi}')
        if problems:
            raise RuntimeError('; '.join(problems))
        extras, extra_notes = {}, []
        if not only:
            accts, note = fetch_accounts(api)
            for stale in ('accounts.json', 'accounts.json.enc'):
                if os.path.exists(os.path.join(out_dir, stale)):
                    os.remove(os.path.join(out_dir, stale))
            if accts is None:
                extra_notes.append('accounts: ' + note)
                oc.log('accounts:', note)
            else:
                e = write_extra(out_dir, 'accounts.json', accts, keys)
                e['items'] = int(accts.get('logins') or 0)
                extras['accounts'] = e
                oc.log(f"accounts: {e['items']} login(s) (no passwords, no PIN hashes)")
        finished = clock()
        manifest = {
            'tool': 'backup_dump.py', 'format': 2, 'manifest_version': 2, 'extras': extras, 'extra_notes': extra_notes,
            'edge_function_secret_names_expected': edge_secret_names(),
            'code': {'commit': os.environ.get('GITHUB_SHA'), 'paste_order_sha256': paste_order_sha256()}, 'schema_version': m0.get('schema_version'), 'schema_fingerprint': m0.get('fingerprint'),
            'started_at': started, 'finished_at': finished, 'table_count': len(names), 'rows': total_rows, 'bytes': total_bytes,
            'tables': {t: {**files[t], 'rows_at_start': start_rows[t], 'rows_at_end': end_rows.get(t)} for t in names},
            'warnings': warnings,
        }
        if keys is not None:
            manifest['encryption'] = keys.describe()
        with open(os.path.join(out_dir, 'manifest.json'), 'w', encoding='utf-8') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')
        if log_run:
            api.rpc('backup_log', {'p_status': 'ok', 'p_detail': {'warnings': warnings, 'schema_fingerprint': m0.get('fingerprint'), 'encrypted': keys is not None},
                                   'p_tables': len(names), 'p_rows': total_rows, 'p_bytes': total_bytes, 'p_destination': destination})
        return manifest
    except Exception as e:
        if log_run:
            try:
                api.rpc('backup_log', {'p_status': 'failed', 'p_detail': {'error': oc.REDACT(str(e))[:1500]}, 'p_destination': destination})
            except Exception as e2:  # the failure itself is what matters
                oc.log('could not record the failure:', e2)
        raise


def main(argv=None, api=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='out')
    ap.add_argument('--page', type=int, default=2000)
    ap.add_argument('--tables', default='', help='comma list (for a partial test run)')
    ap.add_argument('--no-log', action='store_true', help='do not call backup_log')
    ap.add_argument('--destination', default='github')
    ap.add_argument('--encrypt', choices=['auto', 'on', 'off'], default='auto', help='auto = follow the rule backup_encrypt_on (default OFF); on = always (needs BACKUP_PASSPHRASE)')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('BOT_EMAIL', required=True), oc.env('BOT_PASSWORD', required=True))
        only = [t for t in a.tables.split(',') if t.strip()] or None
        m = run(api, a.out, page=max(1, min(a.page, 5000)), only=only, log_run=not a.no_log, destination=a.destination, encrypt=a.encrypt)
        oc.log(f"backup OK: {m['table_count']} tables, {m['rows']} rows, {m['bytes']} bytes" + (' (encrypted)' if m.get('encryption') else ''))
        gh = os.environ.get('GITHUB_OUTPUT')
        if gh:
            with open(gh, 'a') as f:
                f.write(f"rows={m['rows']}\ntables={m['table_count']}\n")
        return 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('BACKUP FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
