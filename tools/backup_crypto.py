#!/usr/bin/env python3
"""Client-side encryption for the nightly backup files (item U-12). Python 3 standard library only, so it runs on the GitHub runner and on the owner's computer
with nothing to install. The passphrase is held by the owner (GitHub secret BACKUP_PASSPHRASE, and the owner's own safe copy). Lose it and the backups cannot be read.

Format "BOSENC1" (one file = one encrypted table file):   b"BOSENC1\\n" | 16-byte tag | ciphertext
  * key      : scrypt(passphrase, salt, N=2^15, r=8, p=1) -> 96 bytes = encryption key | tag key | check key. The salt is a fixed public application salt unless
               BACKUP_KDF_SALT (hex) is set: the passphrase itself is the secret, so it must be long (at least 16 characters; a random 5-word phrase is fine).
  * per file : sub-keys are HMAC(key, file label), so a file cannot be swapped into another table's place without detection.
  * tag      : HMAC-SHA256(tag key, plaintext)[:16]  (a synthetic IV, SIV style). The ciphertext is the plaintext XOR a SHAKE-256 keystream keyed with
               (encryption key, tag, block counter). Decrypting recomputes the tag and compares it in constant time: a wrong passphrase or any changed byte fails.
  * why a synthetic IV: the same table content gives the SAME encrypted bytes every night, so the git history of the backups branch grows only by real changes
               (the plain backup is already byte-for-byte deterministic for the same reason). The cost: someone with the repository can see WHICH tables changed on
               which night (not what is in them).
This container is built only from standard primitives (scrypt, HMAC-SHA256, SHAKE-256) and has not had an independent cryptography review. For a stronger guarantee
use an audited tool instead (for example `age` or `gpg --symmetric`) and keep this file as the dependency-free fallback.

CLI (the passphrase is read from the environment variable BACKUP_PASSPHRASE or from a file, never from the command line):
  python3 tools/backup_crypto.py decrypt <encrypted_dir> <plain_dir> [--passphrase-file F]
      writes the original <table>.ndjson.gz files and a manifest.json that points at them; then run tools/restore_drill.py on <plain_dir> as usual.
  python3 tools/backup_crypto.py check <encrypted_dir> [--passphrase-file F]        verifies the passphrase and every file without writing anything.
Exit code 0 = fine, 1 = wrong passphrase or damaged file, 2 = could not run.
"""
import argparse
import hashlib
import hmac
import json
import os
import shutil
import sys

MAGIC = b'BOSENC1\n'
TAG_LEN = 16
CHUNK = 1 << 20
DEFAULT_SALT = b'islamia-bos-backup-v1'
MIN_PASSPHRASE = 16
SCRYPT = {'n': 2 ** 15, 'r': 8, 'p': 1}
ENC_SUFFIX = '.enc'


class CryptoError(Exception):
    """Bad passphrase, damaged or foreign file, or a missing setting. The text never contains the passphrase."""


class Keys:
    def __init__(self, enc, tag, check, salt_id):
        self.enc, self.tag, self.check, self.salt_id = enc, tag, check, salt_id

    def key_check(self):
        return hmac.new(self.check, b'bos-backup-key-check', hashlib.sha256).hexdigest()[:16]

    def describe(self):
        return {'format': 'BOSENC1', 'kdf': 'scrypt', **{k: v for k, v in SCRYPT.items()}, 'salt_id': self.salt_id, 'key_check': self.key_check()}


def derive(passphrase, salt_hex=None):
    if not isinstance(passphrase, str) or len(passphrase) < MIN_PASSPHRASE:
        raise CryptoError(f'the passphrase must be at least {MIN_PASSPHRASE} characters')
    salt = bytes.fromhex(salt_hex) if salt_hex else DEFAULT_SALT
    raw = hashlib.scrypt(passphrase.encode('utf-8'), salt=salt, n=SCRYPT['n'], r=SCRYPT['r'], p=SCRYPT['p'], dklen=96, maxmem=256 * 1024 * 1024)
    return Keys(raw[:32], raw[32:64], raw[64:96], hashlib.sha256(salt).hexdigest()[:8])


def keys_from_env(env=None):
    env = os.environ if env is None else env
    pw = env.get('BACKUP_PASSPHRASE', '')
    if not pw:
        raise CryptoError('BACKUP_PASSPHRASE is not set')
    return derive(pw, env.get('BACKUP_KDF_SALT') or None)


def _subkeys(keys, label):
    lb = label.encode('utf-8')
    return hmac.new(keys.enc, b'enc:' + lb, hashlib.sha256).digest(), hmac.new(keys.tag, b'tag:' + lb, hashlib.sha256).digest()


def _xor_stream(enc_key, tag, data):
    out = bytearray()
    for i in range(0, len(data), CHUNK):
        part = data[i:i + CHUNK]
        ks = hashlib.shake_256(b'BOSENC1-ks' + enc_key + tag + (i // CHUNK).to_bytes(8, 'big')).digest(len(part))
        out += (int.from_bytes(part, 'big') ^ int.from_bytes(ks, 'big')).to_bytes(len(part), 'big')
    return bytes(out)


def encrypt_bytes(keys, label, data):
    enc_key, tag_key = _subkeys(keys, label)
    tag = hmac.new(tag_key, data, hashlib.sha256).digest()[:TAG_LEN]
    return MAGIC + tag + _xor_stream(enc_key, tag, data)


def decrypt_bytes(keys, label, blob):
    if len(blob) < len(MAGIC) + TAG_LEN or not blob.startswith(MAGIC):
        raise CryptoError(f'{label}: not a BOSENC1 file')
    tag, body = blob[len(MAGIC):len(MAGIC) + TAG_LEN], blob[len(MAGIC) + TAG_LEN:]
    enc_key, tag_key = _subkeys(keys, label)
    data = _xor_stream(enc_key, tag, body)
    if not hmac.compare_digest(hmac.new(tag_key, data, hashlib.sha256).digest()[:TAG_LEN], tag):
        raise CryptoError(f'{label}: wrong passphrase, or the file is damaged or was changed')
    return data


def label_of(enc_name):
    """'sales.ndjson.gz.enc' -> 'sales.ndjson.gz' (the label that is bound into the encryption)."""
    return enc_name[:-len(ENC_SUFFIX)] if enc_name.endswith(ENC_SUFFIX) else enc_name


def _load_manifest(d):
    p = os.path.join(d, 'manifest.json')
    if not os.path.isfile(p):
        raise CryptoError(f'{d}: no manifest.json')
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def decrypt_dir(src, dst, keys, write=True):
    """Decrypts every file listed in src/manifest.json. Verifies the key check, the plaintext sha256 and the file list. Returns the plain manifest."""
    m = _load_manifest(src)
    enc = m.get('encryption')
    if not enc:
        raise CryptoError('this backup is not encrypted (no "encryption" block in manifest.json)')
    if enc.get('key_check') != keys.key_check():
        raise CryptoError('wrong passphrase (or wrong BACKUP_KDF_SALT) for this backup')
    if write:
        os.makedirs(dst, exist_ok=True)
    out = json.loads(json.dumps(m))
    out.pop('encryption', None)
    for t, info in m['tables'].items():
        name = info['file']
        with open(os.path.join(src, name), 'rb') as f:
            blob = f.read()
        if info.get('enc_sha256') and hashlib.sha256(blob).hexdigest() != info['enc_sha256']:
            raise CryptoError(f'{name}: the stored file does not match the manifest (damaged)')
        plain = decrypt_bytes(keys, label_of(name), blob)
        if hashlib.sha256(plain).hexdigest() != info['sha256']:
            raise CryptoError(f'{name}: decrypted content does not match the manifest sha256')
        plain_name = label_of(name)
        if write:
            with open(os.path.join(dst, plain_name), 'wb') as f:
                f.write(plain)
        e = out['tables'][t]
        e['file'] = plain_name
        for k in ('enc_sha256', 'enc_bytes', 'encrypted'):
            e.pop(k, None)
    for name_, info in (m.get('extras') or {}).items():           # accounts.json.enc etc.: same rules as a table file
        if not info.get('encrypted'):
            continue
        fname = info['file']
        with open(os.path.join(src, fname), 'rb') as f:
            blob = f.read()
        if info.get('enc_sha256') and hashlib.sha256(blob).hexdigest() != info['enc_sha256']:
            raise CryptoError(f'{fname}: the stored file does not match the manifest (damaged)')
        plain = decrypt_bytes(keys, label_of(fname), blob)
        if hashlib.sha256(plain).hexdigest() != info['sha256']:
            raise CryptoError(f'{fname}: decrypted content does not match the manifest sha256')
        if write:
            with open(os.path.join(dst, label_of(fname)), 'wb') as f:
                f.write(plain)
        e = out['extras'][name_]
        e['file'] = label_of(fname)
        for k in ('enc_sha256', 'enc_bytes', 'encrypted'):
            e.pop(k, None)
    if write:
        for f_ in sorted(os.listdir(src)):                             # the plain storage manifests travel with the backup
            if f_.endswith('.json') and f_ != 'manifest.json' and (f_ == 'photos_manifest.json' or f_.startswith('storage_')):
                shutil.copyfile(os.path.join(src, f_), os.path.join(dst, f_))
        with open(os.path.join(dst, 'manifest.json'), 'w', encoding='utf-8') as f:
            json.dump(out, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')
    return out


def main(argv=None, env=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    d = sub.add_parser('decrypt')
    d.add_argument('src')
    d.add_argument('dst')
    d.add_argument('--passphrase-file')
    c = sub.add_parser('check')
    c.add_argument('src')
    c.add_argument('--passphrase-file')
    a = ap.parse_args(argv)
    env = dict(os.environ if env is None else env)
    try:
        if a.passphrase_file:
            with open(a.passphrase_file, encoding='utf-8') as f:
                env['BACKUP_PASSPHRASE'] = f.read().strip('\r\n')
        keys = keys_from_env(env)
        m = decrypt_dir(a.src, getattr(a, 'dst', None), keys, write=(a.cmd == 'decrypt'))
        print(f"OK: {len(m['tables'])} files {'decrypted' if a.cmd == 'decrypt' else 'verified'}", file=sys.stderr)
        return 0
    except CryptoError as e:
        print('FAILED:', e, file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError) as e:
        print('could not run:', type(e).__name__, str(e)[:200], file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
