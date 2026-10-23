#!/usr/bin/env python3
"""Guard for the single-repo Pages publish (docs/SINGLE_REPO.md). Run by .github/workflows/pages.yml between the build and the upload.

    python3 tools/check_pages_dist.py <dist_folder> [--web web]

Refuses (exit 1) when the folder that would be published:
  * is missing index.html / sw.js / config.js, or its config.js (url, key, emailDomain) differs from web/config.js,
  * web/config.js holds anything but the public Supabase URL and a sb_publishable_ key (no service_role, no sb_secret_),
  * contains a file type or folder that must never be published: sql, markdown, csv, env, keys, sources maps, scripts, workflows, tests, docs, supabase, tools, .git;
  * contains a data/ file that is not a .json file that also exists in web/data/ (the repository-root data/ folder, with item costs and prices, can never get in),
  * contains a secret value (sb_secret_, sk-ant-, sk_live_, AIza, a private key block, a bot token), a JWT-like token, or a git conflict marker,
  * contains a .js file that node --check rejects (skipped with a warning when node is missing).
Standard library only. Never writes anything.
"""
import os
import re
import subprocess
import sys

BAD_EXT = {'.sql', '.md', '.csv', '.env', '.pem', '.key', '.map', '.sh', '.py', '.yml', '.yaml', '.zip', '.tar', '.gz', '.bak', '.log', '.ndjson'}
BAD_DIRS = {'tests', 'docs', 'supabase', 'tools', '.git', '.github', 'node_modules', 'android', 'backups', 'sqlparts'}
TEXT_EXT = {'.js', '.css', '.html', '.json', '.svg', '.txt', '.webmanifest'}
SECRET_RE = re.compile(r'sb_secret_[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|sk_live_[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY|bot[0-9]{6,}:[A-Za-z0-9_-]{30,}')
JWT_RE = re.compile(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}')
CONFLICT_RE = re.compile(r'^(<<<<<<< |=======$|>>>>>>> )', re.M)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    dist = argv[1]
    web = 'web'
    if '--web' in argv:
        web = argv[argv.index('--web') + 1]
    bad = []

    def fail(msg):
        bad.append(msg)

    for need in ('index.html', 'sw.js', 'config.js'):
        if not os.path.isfile(os.path.join(dist, need)):
            fail('missing ' + need)
    cfg_src = os.path.join(web, 'config.js')
    cfg_dst = os.path.join(dist, 'config.js')
    if os.path.isfile(cfg_src) and os.path.isfile(cfg_dst):
        # the build minifies config.js, so compare the three values, not the bytes
        def vals(path):
            t = open(path, encoding='utf-8', errors='replace').read()
            t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
            t = re.sub(r'(?m)^\s*//.*$', '', t)
            return t, [re.search(k + r'\s*:\s*"([^"]*)"', t) for k in ('url', 'key', 'emailDomain')]
        ts, vs = vals(cfg_src)
        td, vd = vals(cfg_dst)
        if [m and m.group(1) for m in vs] != [m and m.group(1) for m in vd]:
            fail('config.js in the build has different values from web/config.js')
        for name, t in (('web/config.js', ts), ('built config.js', td)):
            if re.search(r'service_role|sb_secret', t):
                fail(name + ' mentions service_role / sb_secret')
        if not (vd[0] and re.fullmatch(r'https://[a-z0-9]+\.supabase\.co', vd[0].group(1))):
            fail('config.js url is not a https://<ref>.supabase.co address')
        if not (vd[1] and re.fullmatch(r'sb_publishable_[A-Za-z0-9_-]+', vd[1].group(1))):
            fail('config.js key is not a sb_publishable_ key')
    jsfiles = []
    for root, dirs, files in os.walk(dist):
        rel_root = os.path.relpath(root, dist)
        parts = [] if rel_root == '.' else rel_root.split(os.sep)
        for d in list(dirs):
            if d in BAD_DIRS:
                fail('forbidden folder: ' + os.path.join(rel_root, d))
                dirs.remove(d)
        for f in files:
            rel = os.path.normpath(os.path.join(rel_root, f))
            ext = os.path.splitext(f)[1].lower()
            if ext in BAD_EXT or f.startswith('.env'):
                fail('forbidden file type: ' + rel)
                continue
            if parts and parts[0] == 'data':
                if ext != '.json' or len(parts) != 1 or not os.path.isfile(os.path.join(web, 'data', f)):
                    fail('data/ file not allowed (only .json files that exist in web/data): ' + rel)
            if ext in TEXT_EXT:
                full = os.path.join(root, f)
                txt = open(full, encoding='utf-8', errors='replace').read()
                if SECRET_RE.search(txt):
                    fail('secret value in ' + rel)
                if JWT_RE.search(txt):
                    fail('JWT-like token in ' + rel)
                if ext in ('.js', '.css', '.html') and CONFLICT_RE.search(txt):
                    fail('conflict marker in ' + rel)
                if ext == '.js':
                    jsfiles.append(full)
    try:
        for full in jsfiles:
            r = subprocess.run(['node', '--check', full], capture_output=True)
            if r.returncode != 0:
                fail('node --check failed: ' + os.path.relpath(full, dist))
    except FileNotFoundError:
        print('WARN: node not found, syntax check skipped')
    if bad:
        for b in bad:
            print('FAIL: ' + b)
        print('PAGES GUARD: FAIL (%d problem(s)); nothing may be published' % len(bad))
        return 1
    print('PAGES GUARD: PASS (%d js files checked)' % len(jsfiles))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
