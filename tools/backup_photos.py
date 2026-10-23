#!/usr/bin/env python3
"""Copies the private Storage bucket "photos" (receipts, item and staff pictures) next to the database dump. Python 3 standard library only.

The database dump (tools/backup_dump.py) does NOT contain the photo files: they live in Supabase Storage. This script lists the bucket through the Storage API
with the backup bot's login (the bot may only READ that bucket - policy ops_photos_read in supabase/phase46.sql) and downloads files that are not yet saved.
Photos never change once uploaded, so a file that already exists with the same size is skipped and the repository only grows by the new pictures.

Where the files go:
  * total size of all photos <= --git-limit-mb (default 80)  -> --git-dir   (the backups branch of the PRIVATE repo)
  * bigger                                                    -> --drive-dir (copied to Google Drive by the workflow, only when --drive is given); without
                                                                 --drive nothing is copied and the manifest says so - the owner is told to set up Drive.
Always written: <git-dir>/../photos_manifest.json  (every path, size, whether it is saved and where) so a missing photo is visible.
Env (never printed): SUPABASE_URL, SUPABASE_ANON_KEY, BOT_EMAIL, BOT_PASSWORD.   Exit code 1 when any download failed.

With --all-buckets (phase547) every other bucket the bot may read goes to <parent of git-dir>/buckets/<bucket>/ with its own storage_manifest_<bucket>.json, and
storage_buckets.json lists all buckets (also the ones NOT copied, with the reason). Every saved file carries its sha256 in the manifest.

Usage: python3 tools/backup_photos.py --git-dir out/photos --drive-dir drive_extra/photos [--drive] [--git-limit-mb 80] [--max-new 2000] [--all-buckets]
"""
import argparse
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ops_common as oc  # noqa: E402

SAFE_BUCKET = re.compile(r'^[a-z0-9][a-z0-9_-]{0,62}$')


def walk(api, bucket, prefix='', depth=0, limit=1000):
    """Yields (path, size) for every file under prefix (folders have no id in the Storage listing)."""
    if depth > 8:
        return
    offset = 0
    while True:
        items = api.storage_list(bucket, prefix, limit, offset) or []
        for it in items:
            name = it.get('name')
            if not name or '..' in name or name.startswith('/'):
                continue
            path = f'{prefix}/{name}' if prefix else name
            if it.get('id') is None:                      # a folder
                yield from walk(api, bucket, path, depth + 1, limit)
            else:
                yield path, int((it.get('metadata') or {}).get('size') or 0)
        if len(items) < limit:
            return
        offset += limit


def safe_join(root, rel):
    p = os.path.normpath(os.path.join(root, rel))
    if not p.startswith(os.path.normpath(root) + os.sep):
        raise ValueError('unsafe path ' + rel)
    return p


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def run(api, git_dir, drive_dir, use_drive=False, git_limit_mb=80, max_new=2000, bucket='photos', manifest_dir=None, manifest_name='photos_manifest.json'):
    files = sorted(walk(api, bucket))
    total = sum(s for _, s in files)
    to_git = total <= git_limit_mb * 1024 * 1024
    target = git_dir if to_git else (drive_dir if use_drive else None)
    manifest = {'bucket': bucket, 'files': len(files), 'total_bytes': total, 'destination': 'git' if to_git else ('drive' if use_drive else 'none'), 'entries': []}
    failed, new = 0, 0
    for path, size in files:
        e = {'path': path, 'size': size, 'saved': False}
        if target:
            dest = safe_join(target, path)
            if os.path.isfile(dest) and (size == 0 or os.path.getsize(dest) == size):
                e['saved'] = True
                e['sha256'] = file_sha256(dest)            # every saved file carries its checksum (the restore tools verify it)
            elif new >= max_new:
                e['note'] = 'left for the next run'
            else:
                try:
                    data = api.storage_get(bucket, path)
                    os.makedirs(os.path.dirname(dest), exist_ok=True)
                    tmp = dest + '.part'
                    with open(tmp, 'wb') as f:
                        f.write(data)
                    os.replace(tmp, dest)
                    e['saved'], e['sha256'] = True, hashlib.sha256(data).hexdigest()
                    new += 1
                except Exception as ex:
                    failed += 1
                    e['error'] = oc.REDACT(str(ex))[:200]
        manifest['entries'].append(e)
    manifest['new'], manifest['failed'] = new, failed
    if not target:
        manifest['warning'] = 'photos are larger than the git limit and Google Drive is not set up: NOT copied'
    mp = os.path.join(manifest_dir or os.path.dirname(os.path.normpath(git_dir)) or '.', manifest_name)
    os.makedirs(os.path.dirname(mp) or '.', exist_ok=True)
    with open(mp, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')
    return manifest


def run_other_buckets(api, git_dir, drive_dir, use_drive=False, git_limit_mb=80, max_new=2000):
    """Every other bucket the server lists (rpc backup_storage_buckets, phase547) that the bot may read -> <parent of git_dir>/buckets/<bucket>/ plus one manifest
    storage_manifest_<bucket>.json each, and storage_buckets.json = the whole list with what was done (a bucket that holds objects but is not readable is a WARNING,
    not a failure: the owner switches rule backup_buckets_on ON to include it). Returns (summary dict, failed_count)."""
    parent = os.path.dirname(os.path.normpath(git_dir)) or '.'
    try:
        listing = api.rpc('backup_storage_buckets')
    except oc.ApiError as e:
        if getattr(e, 'status', None) == 404 or 'PGRST202' in str(e):
            summary = {'available': False, 'note': 'phase547 is not pasted yet: only the photos bucket is backed up'}
            _write_json(os.path.join(parent, 'storage_buckets.json'), summary)
            return summary, 0
        raise
    summary = {'available': True, 'buckets': [], 'warnings': []}
    failed = 0
    for b in (listing or {}).get('buckets') or []:
        item = {'id': b['id'], 'public': b.get('public'), 'objects': b.get('objects'), 'bytes': b.get('bytes'), 'bot_can_read': b.get('bot_can_read')}
        if b['id'] == 'photos':
            item['copied_by'] = 'photos step'
        elif not b.get('bot_can_read'):
            item['copied'] = False
            if (b.get('objects') or 0) > 0:
                summary['warnings'].append(f"bucket {b['id']}: {b.get('objects')} object(s) NOT in the backup (switch backup_buckets_on is OFF)")
        else:
            if not SAFE_BUCKET.match(b['id']):
                raise RuntimeError('unsafe bucket name ' + repr(b['id']))
            m = run(api, os.path.join(parent, 'buckets', b['id']), os.path.join(os.path.dirname(os.path.normpath(drive_dir)) or '.', 'buckets', b['id']), use_drive,
                    git_limit_mb, max_new, b['id'], parent, f"storage_manifest_{b['id']}.json")
            item.update({'copied': m['destination'] != 'none', 'files': m['files'], 'failed': m['failed'], 'destination': m['destination']})
            failed += m['failed']
            if m['files'] != (b.get('objects') or 0):
                summary['warnings'].append(f"bucket {b['id']}: the server counts {b.get('objects')} object(s) but {m['files']} were listed")
        summary['buckets'].append(item)
    _write_json(os.path.join(parent, 'storage_buckets.json'), summary)
    return summary, failed


def _write_json(path, obj):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write('\n')


def main(argv=None, api=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--git-dir', default='out/photos')
    ap.add_argument('--drive-dir', default='drive_extra/photos')
    ap.add_argument('--drive', action='store_true')
    ap.add_argument('--git-limit-mb', type=float, default=80)
    ap.add_argument('--max-new', type=int, default=2000)
    ap.add_argument('--bucket', default='photos')
    ap.add_argument('--all-buckets', action='store_true', help='also copy every other bucket the backup bot may read (phase547, rule backup_buckets_on)')
    a = ap.parse_args(argv)
    try:
        if api is None:
            api = oc.Api(oc.env('SUPABASE_URL', required=True), oc.env('SUPABASE_ANON_KEY', required=True))
            api.login(oc.env('BOT_EMAIL', required=True), oc.env('BOT_PASSWORD', required=True))
        m = run(api, a.git_dir, a.drive_dir, a.drive, a.git_limit_mb, a.max_new, a.bucket)
        oc.log(f"photos: {m['files']} file(s), {m['total_bytes']} bytes, destination {m['destination']}, new {m['new']}, failed {m['failed']}")
        if m.get('warning'):
            oc.log('WARNING:', m['warning'])
        failed = m['failed']
        if a.all_buckets:
            summary, f2 = run_other_buckets(api, a.git_dir, a.drive_dir, a.drive, a.git_limit_mb, a.max_new)
            failed += f2
            for w in summary.get('warnings', []):
                oc.log('WARNING:', w)
            oc.log('other buckets:', json.dumps([{k: x.get(k) for k in ('id', 'objects', 'copied', 'files', 'failed')} for x in summary.get('buckets', [])]) if summary.get('available') else summary.get('note'))
        return 1 if failed else 0
    except SystemExit:
        raise
    except Exception as e:
        oc.log('PHOTO BACKUP FAILED:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
