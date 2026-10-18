/* Islamia BOS · shared photo helper (X5). One place for: type and size checks, EXIF orientation (createImageBitmap from-image),
   shrink to a JPEG of at most `max` pixels on the longest side (WebP / PNG / HEIC input becomes JPEG), and upload with retry.
   Used by entry.js, items2.js and stock2.js (their old shrink() copies now call this). Output is the same as before: JPEG, q 0.72. */
(() => {
'use strict';
const core = window.BOS_SCAN_CORE;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function decode(file) {
  if (typeof createImageBitmap === 'function') {
    try { return await createImageBitmap(file, { imageOrientation: 'from-image' }); } catch (e) { /* older browser: fall back to <img> */ }
  }
  return new Promise((res, rej) => {
    const img = new Image(), u = URL.createObjectURL(file);
    img.onload = () => { URL.revokeObjectURL(u); res(img); };
    img.onerror = () => { URL.revokeObjectURL(u); rej(new Error('image')); };
    img.src = u;
  });
}

// file -> JPEG Blob. Throws Error('bad_type' | 'too_big' | 'empty' | 'image') so the caller can show a plain message.
async function shrink(file, opts) {
  const o = opts || {};
  const bad = core.validateFile(file);
  if (bad) throw new Error(bad);
  const src = await decode(file);
  const w = src.width || src.naturalWidth, h = src.height || src.naturalHeight;
  const s = core.fitSize(w, h, o.max || 1280);
  const c = document.createElement('canvas'); c.width = s.w; c.height = s.h;
  c.getContext('2d').drawImage(src, 0, 0, s.w, s.h);
  if (src.close) { try { src.close(); } catch (e) { /* ignore */ } }
  return new Promise((res, rej) => c.toBlob((b) => (b ? res(b) : rej(new Error('image'))), 'image/jpeg', o.q || 0.72));
}

// upload with retry (network blips on a phone): 3 tries, growing pause. Returns the stored path; throws the last error.
async function upload(sb, bucket, path, blob, opts) {
  const tries = (opts && opts.tries) || 3;
  let last = null;
  for (let i = 1; i <= tries; i++) {
    try {
      const up = await sb.storage.from(bucket).upload(path, blob, { contentType: 'image/jpeg' });
      if (!up.error) return path;
      last = up.error;
      // a refusal from the server (not allowed, too big) is not retried
      if (/not allowed|policy|too large|403|413/i.test(String(up.error.message || up.error.statusCode || ''))) break;
    } catch (e) { last = e; }
    if (i < tries) await sleep(600 * i);
  }
  throw last || new Error('upload');
}

window.BOS = window.BOS || {};
window.BOS.photo = { shrink, upload, validate: core.validateFile, fitSize: core.fitSize, version: 1 };
})();
