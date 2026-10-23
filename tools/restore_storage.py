#!/usr/bin/env python3
"""Uploads the photos / files of a backup into the Storage buckets of a (new) Supabase project, and checks that they arrived. Run by the OWNER on his own computer.

    python3 tools/restore_storage.py <backup_folder> --url https://<new-project>.supabase.co [--root <latest_folder>] [--dry-run] [--buckets photos,web-refs]

* <backup_folder> holds manifest.json (a "storage" block, manifest version 2). The files themselves are under <root>/photos/ and <root>/buckets/<bucket>/ (--root defaults to
  <backup_folder>; for a dated folder pass the latest/ folder of the backups branch, where the files accumulate).
* Every file is checked against its sha256 in the storage manifest BEFORE it is uploaded; a file that does not match is NOT uploaded and counts as a failure.
* The buckets must exist already (the phase SQL creates photos, web-refs, web-public, payproof). An object that already exists is left alone (never overwritten).
* Afterwards every bucket is listed and the number of objects is compared with the manifest. Exit 0 only when everything arrived; 1 on any failure; 2 when it could not run.
* The admin key (service_role) is read only from the environment variable SUPABASE_SERVICE_KEY on your own computer. Never put it into GitHub or this repository.
* UNVERIFIED against a real Supabase project: tested only with a fake Storage API (tools/test_backup_coverage.py).
"""
import argparse
import hashlib
import json
import mimetypes
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import backup_photos as bp  # noqa: E402
import ops_common as oc  # noqa: E402
import restore_backup as rb  # noqa: E402


def bucket_dir(root, bucket):
    return os.path.join(root, 'photos') if bucket == 'photos' else os.path.join(root, 'buckets', bucket)


def upload_all(api, folder, root, only=None, dry=False, log=oc.log):
    """Returns the report dict. api: an ops_common.Api whose token is the admin key."""
    m = rb.load_manifest(folder)
    st = m.get('storage')
    if not st:
        raise SystemExit('this backup has no storage block (made before manifest version 2): nothing to restore from it')
    report = {'result': 'FAIL', 'buckets': {}}
    ok_all = True
    for bucket, info in sorted((st.get('buckets') or {}).items()):
        if only and bucket not in only:
            continue
        mp = os.path.join(folder, info['manifest'])
        with open(mp, 'rb') as f:
            raw = f.read()
        if hashlib.sha256(raw).hexdigest() != info['manifest_sha256']:
            raise SystemExit(f'{info["manifest"]} does not match manifest.json: stopping')
        man = json.loads(raw)
        d = bucket_dir(root, bucket)
        r = {'files': len(man.get('entries', [])), 'uploaded': 0, 'existed': 0, 'failed': [], 'not_in_git': man.get('destination') != 'git'}
        if r['not_in_git']:
            r['failed'].append(f"files are not in git (destination {man.get('destination')}): fetch them from Google Drive and use --root")
        for e in man.get('entries', []) if not r['not_in_git'] else []:
            p = os.path.normpath(os.path.join(d, e['path']))
            if not e.get('saved') or not p.startswith(os.path.normpath(d) + os.sep) or not os.path.isfile(p):
                r['failed'].append(f"{e['path']}: file missing")
                continue
            with open(p, 'rb') as f:
                data = f.read()
            if e.get('sha256') and hashlib.sha256(data).hexdigest() != e['sha256']:
                r['failed'].append(f"{e['path']}: sha256 does not match (NOT uploaded)")
                continue
            if dry:
                r['uploaded'] += 1
                continue
            ct = mimetypes.guess_type(e['path'])[0] or 'application/octet-stream'
            try:
                api.request('POST', f"/storage/v1/object/{urllib.parse.quote(bucket)}/{urllib.parse.quote(e['path'])}", body=data, headers={'Content-Type': ct, 'x-upsert': 'false'})
                r['uploaded'] += 1
            except oc.ApiError as ex:
                if ex.status in (400, 409) and 'xist' in str(ex).lower() or 'Duplicate' in str(ex):
                    r['existed'] += 1
                else:
                    r['failed'].append(f"{e['path']}: {oc.REDACT(str(ex))[:120]}")
        if not dry and not r['not_in_git']:
            have = len(list(bp.walk(api, bucket)))
            r['objects_in_bucket_now'] = have
            if have < r['files']:
                r['failed'].append(f"the bucket holds {have} object(s) but the backup has {r['files']}")
        log(f"{bucket}: {r['uploaded']} uploaded, {r['existed']} already there, {len(r['failed'])} problem(s)")
        ok_all = ok_all and not r['failed']
        report['buckets'][bucket] = r
    report['result'] = 'PASS' if ok_all and report['buckets'] else 'FAIL'
    report['dry_run'] = dry
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('folder')
    ap.add_argument('--url', required=True)
    ap.add_argument('--root', default='')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--buckets', default='')
    a = ap.parse_args(argv)
    try:
        key = oc.env('SUPABASE_SERVICE_KEY', required=not a.dry_run)
        api = oc.Api(a.url, key or 'dry-run')
        api.token = key
        rep = upload_all(api, a.folder, a.root or a.folder, [x for x in a.buckets.split(',') if x.strip()] or None, a.dry_run)
    except (OSError, ValueError, KeyError, oc.ApiError) as e:
        print(json.dumps({'result': 'ERROR', 'reason': oc.REDACT(str(e))}, indent=1))
        return 2
    print(json.dumps(rep, ensure_ascii=False, indent=1))
    return 0 if rep['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())
