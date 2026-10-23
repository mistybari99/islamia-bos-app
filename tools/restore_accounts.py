#!/usr/bin/env python3
"""Re-creates the staff LOGINS of a backup in a (new) Supabase project, and resets one person's PIN. Run by the OWNER on his own computer. Python 3 standard library only.

    python3 tools/restore_accounts.py plan   <backup_folder>
    python3 tools/restore_accounts.py create <backup_folder> --url https://<new-project>.supabase.co [--only staff1,staff2] [--follow-up followups.sql]
    python3 tools/restore_accounts.py reset-pin <staff_id> --url https://<new-project>.supabase.co [--email-domain staff.example.app]

What it does
  plan       prints who would be created (staff id, name, roles, locations, grants, 2FA yes/no). Changes nothing.
  create     for every login in <backup_folder>/accounts.json (the file made by the nightly backup when the rule backup_accounts_on is ON; decrypt the folder first when it is
             encrypted) it calls the Supabase Auth admin API (POST /auth/v1/admin/users) with the SAME user id and the same e-mail, e-mail already confirmed and a RANDOM
             password that is thrown away (nobody can sign in with it). The database trigger of the app then makes the profile row; the data restore afterwards
             (tools/restore_backup.py --truncate) puts the real profile / role / location / grant rows back, keyed by the same ids. A login that already exists is skipped.
             It also writes follow-up SQL (--follow-up): the bot marks of ops_accounts (backup / notify) and a list of attendance devices that must be enrolled again.
  reset-pin  sets a NEW PIN for one person: the app signs in with the password "<PIN>-bos" (web/app.js pwOf), so this sets that password through the admin API.
             The PIN is typed hidden (or read from the environment variable named by --pin-env). 4 to 6 digits, like the app. Works for any person at any time,
             also for a PIN that was forgotten. A person who is locked after 5 wrong tries is unlocked in the app (Staff -> unlock) or by waiting 10 minutes.
Secrets: the admin API needs the project's secret key (service_role). It is read ONLY from the environment variable SUPABASE_SERVICE_KEY on your own computer, is never printed or
written anywhere, and must never be put into GitHub or this repository. Passwords and PIN hashes are not in any backup, so nothing here can restore them: every person gets a new PIN.
Not restored by any tool: second-factor (2FA) enrolments (the person enrols again), active sessions, device tokens of attendance machines.
"""
import argparse
import getpass
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

PIN_RE = re.compile(r'^\d{4,6}$')
UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')


class Admin:
    """Tiny Supabase Auth admin client (service key from the environment)."""

    def __init__(self, base, key, opener=None):
        u = urllib.parse.urlparse(base)
        if u.scheme != 'https' and u.hostname not in ('localhost', '127.0.0.1', '::1'):
            raise SystemExit('the project URL must be https://...')
        self.base, self.key = base.rstrip('/'), key
        self.opener = opener or urllib.request.urlopen
        oc.REDACT.add(key)

    def call(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={'apikey': self.key, 'Authorization': 'Bearer ' + self.key, 'Content-Type': 'application/json'})
        try:
            with self.opener(req, timeout=60) as r:
                payload = r.read()
            return r.status, (json.loads(payload) if payload else None)
        except urllib.error.HTTPError as e:
            msg = e.read().decode('utf-8', 'replace')[:300]
            return e.code, {'error': oc.REDACT(msg)}

    def find_user(self, email):
        email = email.lower()
        page = 1
        while page < 500:
            st, r = self.call('GET', f'/auth/v1/admin/users?page={page}&per_page=200')
            if st != 200:
                raise RuntimeError(f'listing users failed (HTTP {st}): {(r or {}).get("error")}')
            users = r.get('users', r) if isinstance(r, dict) else r
            for u in users or []:
                if (u.get('email') or '').lower() == email:
                    return u
            if not users or len(users) < 200:
                return None
            page += 1


def load_accounts(folder):
    p = os.path.join(folder, 'accounts.json')
    if os.path.isfile(p + '.enc') and not os.path.isfile(p):
        raise SystemExit('accounts.json.enc is encrypted: run  python3 tools/backup_crypto.py decrypt <folder> <plain_folder>  first')
    if not os.path.isfile(p):
        raise SystemExit(f'no accounts.json in {folder}: that backup was made with the rule backup_accounts_on OFF (or before phase547). The logins must be created by hand '
                         '(docs/BACKUP_AND_RESTORE_GUIDE.md, section "if there is no accounts.json").')
    with open(p, encoding='utf-8') as f:
        d = json.load(f)
    m = os.path.join(folder, 'manifest.json')
    if os.path.isfile(m):                                   # the file must be the one the manifest vouches for
        import hashlib
        with open(m, encoding='utf-8') as f:
            info = (json.load(f).get('extras') or {}).get('accounts')
        with open(p, 'rb') as f:
            if info and hashlib.sha256(f.read()).hexdigest() != info['sha256']:
                raise SystemExit('accounts.json does not match manifest.json (damaged or changed): stopping')
    return d


def describe(a):
    return (f"{a['staff_id']:<14} {a.get('status', ''):<9} roles={','.join(a.get('roles') or []) or '-'} locations={a.get('locations') or '-'} "
            f"grants={len(a.get('grants') or [])}{' 2FA(re-enrol)' if a.get('has_2fa') else ''}{' BOT:' + ','.join(a['bot_purposes']) if a.get('bot_purposes') else ''}")


def followup_sql(d):
    out = ['-- Follow-up after tools/restore_accounts.py create, from the backup list. Paste in the Supabase SQL editor AFTER the data restore. Safe to paste twice.']
    for o in d.get('ops_accounts', []):
        if UUID_RE.match(o['user_id']) and o['purpose'] in ('backup', 'notify'):
            out.append(f"insert into public.ops_accounts (user_id, purpose, active) values ('{o['user_id']}', '{o['purpose']}', {'true' if o.get('active') else 'false'}) on conflict (user_id, purpose) do nothing;")
    devs = d.get('attendance_devices') or []
    out.append(f'-- {len(devs)} attendance device(s) must be enrolled again in the app (their token hashes are not in any backup):')
    for x in devs:
        out.append('--   ' + json.dumps({k: x.get(k) for k in ('name', 'vendor', 'serial', 'location_id', 'active')}, ensure_ascii=False))
    out.append('-- The bot users get a RANDOM password here: set a new long password for each bot in Authentication -> Users and put it into the GitHub secret (BOT_PASSWORD).')
    return '\n'.join(out) + '\n'


def cmd_plan(a):
    d = load_accounts(a.folder)
    print(f"{len(d['accounts'])} login(s) in the backup:")
    for x in d['accounts']:
        print('  ' + describe(x))
    return 0


def cmd_create(a):
    d = load_accounts(a.folder)
    key = oc.env('SUPABASE_SERVICE_KEY', required=True)
    adm = Admin(a.url, key)
    only = {x.strip().lower() for x in a.only.split(',') if x.strip()}
    made = skipped = failed = 0
    for x in d['accounts']:
        if only and x['staff_id'].lower() not in only:
            continue
        if not UUID_RE.match(x['id']) or not EMAIL_RE.match(x.get('email') or ''):
            print(f"SKIP {x.get('staff_id')}: no usable id / e-mail in the backup (create this one by hand)")
            failed += 1
            continue
        st, r = adm.call('POST', '/auth/v1/admin/users', {'id': x['id'], 'email': x['email'], 'password': secrets.token_urlsafe(24) + '-bos', 'email_confirm': True,
                                                          'user_metadata': {'full_name': x.get('full_name') or ''}})
        if st in (200, 201):
            made += 1
            print(f"created  {x['staff_id']}")
        elif st == 422 or (r and 'already' in json.dumps(r).lower()):
            skipped += 1
            print(f"exists   {x['staff_id']} (skipped)")
        else:
            failed += 1
            print(f"FAILED   {x['staff_id']}: HTTP {st} {(r or {}).get('error')}")
    if a.follow_up:
        with open(a.follow_up, 'w', encoding='utf-8') as f:
            f.write(followup_sql(d))
        print('follow-up SQL written to', a.follow_up)
    print(f'done: {made} created, {skipped} already there, {failed} failed. Next: restore the data with tools/restore_backup.py --truncate, then give everybody a new PIN (reset-pin).')
    return 1 if failed else 0


def cmd_reset_pin(a):
    key = oc.env('SUPABASE_SERVICE_KEY', required=True)
    pin = os.environ.get(a.pin_env) if a.pin_env else getpass.getpass('New PIN (4 to 6 digits, typed hidden): ')
    if not pin or not PIN_RE.match(pin):
        print('the PIN must be 4 to 6 digits')
        return 2
    oc.REDACT.add(pin)
    adm = Admin(a.url, key)
    email = a.email or f'{a.staff_id.lower()}@{a.email_domain}'
    u = adm.find_user(email)
    if not u:
        print(f'no login with e-mail {email} in this project (create it first, or give --email-domain / --email)')
        return 1
    st, r = adm.call('PUT', f"/auth/v1/admin/users/{u['id']}", {'password': pin + '-bos'})
    if st != 200:
        print(f'FAILED: HTTP {st} {(r or {}).get("error")}')
        return 1
    print(f'new PIN set for {a.staff_id}. Tell the person; they sign in with the staff id and this PIN. Unlock them in the app if they were locked.')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('plan')
    p.add_argument('folder')
    c = sub.add_parser('create')
    c.add_argument('folder')
    c.add_argument('--url', required=True)
    c.add_argument('--only', default='')
    c.add_argument('--follow-up', default='')
    r = sub.add_parser('reset-pin')
    r.add_argument('staff_id')
    r.add_argument('--url', required=True)
    r.add_argument('--email-domain', default='staff.islamia-bos.app', help='the emailDomain of web/config.js')
    r.add_argument('--email', default='')
    r.add_argument('--pin-env', default='', help='read the PIN from this environment variable instead of asking')
    a = ap.parse_args(argv)
    try:
        return {'plan': cmd_plan, 'create': cmd_create, 'reset-pin': cmd_reset_pin}[a.cmd](a)
    except (OSError, ValueError, RuntimeError) as e:
        print('FAILED:', oc.REDACT(str(e)))
        return 1


if __name__ == '__main__':
    sys.exit(main())
