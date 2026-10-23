#!/usr/bin/env python3
"""Seals one backup run: puts the Storage (photo) manifests next to the database dump and records them, with their sha256, in out/manifest.json.

Run by .github/workflows/backup.yml after tools/backup_dump.py and tools/backup_photos.py. Python 3 standard library only. No network, no secrets.

    python3 tools/backup_seal.py --out out --storage-dir data/latest [--photos-failed]

* Reads <storage-dir>/photos_manifest.json, <storage-dir>/storage_manifest_<bucket>.json and <storage-dir>/storage_buckets.json (written by tools/backup_photos.py).
* Copies them into --out (so the dated folder and latest/ carry them) and adds a "storage" block to manifest.json: per bucket the number of files, bytes, destination and
  the sha256 of its manifest file; the per-file sha256 sit inside that manifest. manifest_version stays 2.
* Verifies on disk that every file a manifest says is saved exists under <storage-dir>/photos/ (bucket photos) or <storage-dir>/buckets/<bucket>/ with the same sha256.
  A missing or changed file makes the seal FAIL (exit 1), so the workflow turns red and the owner is told. Photos that live only on Google Drive (destination "drive") or are
  "left for the next run" are counted, not checked on disk.
* Never deletes or changes a database file. Exit 0 = sealed and verified, 1 = a problem (the manifest still gets the block, with status "problem").
"""
import argparse
import hashlib
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def check_manifest(storage_dir, bucket, man):
    """Returns (problems, counted, checked) for one bucket manifest."""
    root = os.path.join(storage_dir, 'photos') if bucket == 'photos' else os.path.join(storage_dir, 'buckets', bucket)
    problems, checked = [], 0
    for e in man.get('entries', []):
        if e.get('error'):
            problems.append(f"{bucket}/{e['path']}: download failed")
            continue
        if man.get('destination') != 'git' or not e.get('saved'):
            continue
        p = os.path.normpath(os.path.join(root, e['path']))
        if not p.startswith(os.path.normpath(root) + os.sep):
            problems.append(f"{bucket}/{e['path']}: unsafe path")
            continue
        if not os.path.isfile(p):
            problems.append(f"{bucket}/{e['path']}: file missing in the backup folder")
            continue
        checked += 1
        if e.get('sha256') and sha256_file(p) != e['sha256']:
            problems.append(f"{bucket}/{e['path']}: sha256 does not match the manifest")
    return problems, len(man.get('entries', [])), checked


def seal(out_dir, storage_dir, photos_failed=False):
    mpath = os.path.join(out_dir, 'manifest.json')
    manifest = load(mpath)
    block = {'status': 'ok', 'buckets': {}, 'problems': []}
    names = {}
    pm = os.path.join(storage_dir, 'photos_manifest.json')
    if os.path.isfile(pm):
        names['photos'] = pm
    if os.path.isdir(storage_dir):
        for f in sorted(os.listdir(storage_dir)):
            if f.startswith('storage_manifest_') and f.endswith('.json'):
                names[f[len('storage_manifest_'):-len('.json')]] = os.path.join(storage_dir, f)
    if not names:
        block['status'] = 'problem' if photos_failed else 'none'
        block['problems'].append('the photo step produced no manifest' if photos_failed else 'no storage manifest found')
    for bucket, path in sorted(names.items()):
        man = load(path)
        problems, counted, checked = check_manifest(storage_dir, bucket, man)
        fname = os.path.basename(path)
        shutil.copyfile(path, os.path.join(out_dir, fname))
        block['buckets'][bucket] = {'manifest': fname, 'manifest_sha256': sha256_file(path), 'files': man.get('files', counted), 'total_bytes': man.get('total_bytes'),
                                    'destination': man.get('destination'), 'saved_checked_on_disk': checked, 'failed': man.get('failed', 0)}
        if man.get('warning'):
            block['problems'].append(f'{bucket}: {man["warning"]}')
        block['problems'] += problems
    sb = os.path.join(storage_dir, 'storage_buckets.json')
    if os.path.isfile(sb):
        shutil.copyfile(sb, os.path.join(out_dir, 'storage_buckets.json'))
        info = load(sb)
        block['bucket_list'] = {'file': 'storage_buckets.json', 'sha256': sha256_file(sb), 'warnings': info.get('warnings', []), 'available': info.get('available')}
    if block['problems']:
        block['status'] = 'problem'
    manifest['storage'] = block
    with open(mpath, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')
    return block


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default='out')
    ap.add_argument('--storage-dir', default='data/latest')
    ap.add_argument('--photos-failed', action='store_true', help='the photo step failed: seal anyway but report a problem')
    a = ap.parse_args(argv)
    try:
        b = seal(a.out, a.storage_dir, a.photos_failed)
    except (OSError, ValueError, KeyError) as e:
        oc.log('SEAL FAILED:', type(e).__name__, str(e)[:300])
        return 1
    for k, v in b['buckets'].items():
        oc.log(f"storage {k}: {v['files']} file(s), {v['saved_checked_on_disk']} checked on disk, destination {v['destination']}")
    for p in b['problems'][:20]:
        oc.log('PROBLEM:', p)
    oc.log('storage status:', b['status'])
    return 0 if b['status'] in ('ok', 'none') else 1


if __name__ == '__main__':
    sys.exit(main())
