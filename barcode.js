/* Islamia BOS · barcode scanning. Two SEPARATE options (Rules): barcode_camera_on (phone camera, BarcodeDetector API)
   and barcode_device_on (hardware scanner that types the code + Enter, or a typed code). B.barcode.scan() offers whichever is on:
   both -> two buttons, one -> straight to it, none -> "Data needed: enable in Settings". Resolves with the code, or null if cancelled.
   The overlay is its own layer, so it can open on top of a form or sheet without closing it. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { t, esc, toast, S } = A;
const L = B.L, lab = B.lab;
const FORMATS = ['ean_13', 'ean_8', 'code_128', 'code_39', 'qr_code', 'upc_a'];
const X = {
  title: L('বারকোড স্ক্যান', 'Scan barcode', 'Barcode স্ক্যান'),
  cam: L('ক্যামেরা দিয়ে স্ক্যান', 'Scan with the camera', 'Camera দিয়ে scan'), dev: L('স্ক্যানার / কোড টাইপ', 'Scanner / type the code', 'Scanner / code type'),
  cancel: L('বাতিল', 'Cancel', 'Cancel'), back: L('পিছনে', 'Back', 'Back'), use: L('ব্যবহার করুন', 'Use this code', 'Use this code'),
  point: L('বারকোডটি ফ্রেমের মধ্যে ধরুন', 'Hold the barcode inside the frame', 'Barcode frame-এর মধ্যে ধরুন'),
  nosupport: L('এই ফোনের ব্রাউজারে ক্যামেরা-স্ক্যান চলে না। স্ক্যানার বা টাইপ করে কোড দিন।', 'Camera scan is not supported on this phone or browser. Use a scanner or type the code.', 'এই phone-এর browser-এ camera scan চলে না। Scanner বা type করে code দিন।'),
  nocam: L('ক্যামেরা চালু করা গেল না (অনুমতি দেননি?)।', 'Could not start the camera (permission denied?).', 'Camera চালু করা গেল না (permission দেননি?)।'),
  devhint: L('স্ক্যানারে স্ক্যান করুন, অথবা কোড টাইপ করে Enter চাপুন।', 'Scan with the scanner, or type the code and press Enter.', 'Scanner-এ scan করুন, অথবা code type করে Enter চাপুন।'),
  code: L('বারকোড', 'Barcode', 'Barcode'),
  none: L('তথ্য লাগবে: সেটিংসে ক্যামেরা স্ক্যান বা ডিভাইস স্ক্যান চালু করুন।', 'Data needed: enable camera scan or device scan in Settings.', 'তথ্য লাগবে: Settings-এ camera scan বা device scan চালু করুন।'),
  open: L('সেটিংস খুলুন', 'Open settings', 'Settings খুলুন'), nomatch: L('এই বারকোডের কোনো পণ্য নেই', 'No product has this barcode', 'এই barcode-এর কোনো product নেই'),
};
const T = (k) => lab(X[k]);
let cur = null;

const rule = (k) => { try { return B.rule(k, false) === true; } catch (e) { return false; } };
function modes() { return { cam: rule('barcode_camera_on'), dev: rule('barcode_device_on') }; }

function scan() {
  if (cur) cur.finish(null);
  return new Promise((resolve) => {
    let done = false, stream = null, timer = null, root = null, screen = null;
    const teardown = () => {
      if (timer) { clearInterval(timer); timer = null; }
      if (stream) { stream.getTracks().forEach((tr) => { try { tr.stop(); } catch (e) { /* already stopped */ } }); stream = null; }
      const v = root && root.querySelector('video'); if (v) { try { v.pause(); v.srcObject = null; } catch (e) { /* ignore */ } }
      document.removeEventListener('keydown', onKey, true); window.removeEventListener('hashchange', onHash);
      if (root) root.remove(); root = null;
    };
    const finish = (code) => { if (done) return; done = true; teardown(); cur = null; resolve(code ? String(code).trim() : null); };
    const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); finish(null); } };
    const onHash = () => finish(null);
    cur = { finish };
    root = document.createElement('div'); root.className = 'bc-bg'; root.id = 'bcOverlay';
    root.addEventListener('click', (e) => { if (e.target === root) finish(null); });
    document.body.appendChild(root);
    document.addEventListener('keydown', onKey, true); window.addEventListener('hashchange', onHash);
    const card = (html) => { root.innerHTML = `<div class="bc-card" role="dialog" aria-modal="true" aria-label="${esc(T('title'))}"><button type="button" class="sheet-x bc-x" aria-label="${esc(T('cancel'))}">✕</button><h2>${esc(T('title'))}</h2>${html}</div>`; const xb = root.querySelector('.bc-x'); if (xb) xb.addEventListener('click', () => finish(null)); return root.firstChild; };
    const on = (sel, fn) => { const el = root && root.querySelector(sel); if (el) el.addEventListener('click', fn); };

    const showNone = () => {
      screen = 'none'; const own = S.ctx && S.ctx.is_owner;
      card(`<div class="notice warn" data-bc="none">${esc(T('none'))}</div><div class="stack">${own ? `<button class="primary" data-bc="settings">${esc(T('open'))}</button>` : ''}<button data-bc="cancel">${esc(T('cancel'))}</button></div>`);
      on('[data-bc=cancel]', () => finish(null)); on('[data-bc=settings]', () => { finish(null); location.hash = '#/settings2/barcode'; });
    };
    const showDevice = (m, msg) => {
      screen = 'dev';
      const c = card(`${msg ? `<div class="notice warn">${esc(msg)}</div>` : ''}<label for="bc_in">${esc(T('code'))}</label><input id="bc_in" class="bc-in" inputmode="text" autocomplete="off" autocapitalize="off" spellcheck="false" aria-describedby="bc_h">
        <div class="hint" id="bc_h">${esc(T('devhint'))}</div>
        <div class="stack" style="margin-top:12px"><button class="primary" data-bc="use">${esc(T('use'))}</button>${m.cam ? `<button data-bc="cam">${esc(T('cam'))}</button>` : ''}<button data-bc="cancel">${esc(T('cancel'))}</button></div>`);
      const inp = c.querySelector('#bc_in');
      const submit = () => { const v = inp.value.trim(); if (v) finish(v); };
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
      inp.addEventListener('blur', () => { setTimeout(() => { if (root && screen === 'dev' && !(document.activeElement && root.contains(document.activeElement))) inp.focus(); }, 60); });   // a scanner types into whatever has focus
      on('[data-bc=use]', submit); on('[data-bc=cancel]', () => finish(null)); on('[data-bc=cam]', () => showCamera(m));
      setTimeout(() => { if (inp.isConnected) inp.focus(); }, 30);
    };
    const showCamera = async (m) => {
      screen = 'cam';
      const c = card(`<p class="muted" id="bc_msg">${esc(T('point'))}</p><div class="bc-view"><video playsinline muted autoplay></video></div>
        <div class="stack">${m.dev ? `<button data-bc="dev">${esc(T('dev'))}</button>` : ''}<button data-bc="cancel">${esc(T('cancel'))}</button></div>`);
      on('[data-bc=cancel]', () => finish(null)); on('[data-bc=dev]', () => { teardownMedia(); showDevice(m); });
      const fallback = (key) => { if (m.dev) { teardownMedia(); showDevice(m, T(key)); } else { const el = c.querySelector('#bc_msg'); if (el) { el.textContent = T(key); el.className = 'notice warn'; } } };
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return fallback('nosupport');
      let det;
      if (!('BarcodeDetector' in window)) {
        // X5: the vendored ZXing reader (web/scan_items.js) when this browser has no BarcodeDetector; OFF unless the camera switch is on
        try { det = B.scanitems && B.scanitems.fallbackDetector ? await B.scanitems.fallbackDetector() : null; } catch (e) { det = null; }
        if (!det) return fallback('nosupport');
      } else {
        try {
          let f = FORMATS;
          if (window.BarcodeDetector.getSupportedFormats) { const sup = await window.BarcodeDetector.getSupportedFormats(); const ok = FORMATS.filter((x) => sup.includes(x)); if (ok.length) f = ok; }
          det = new window.BarcodeDetector({ formats: f });
        } catch (e) { return fallback('nosupport'); }
      }
      try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false }); } catch (e) { return fallback('nocam'); }
      if (done || screen !== 'cam' || !root) { if (stream) stream.getTracks().forEach((tr) => tr.stop()); stream = null; return; }
      const v = root.querySelector('video'); v.srcObject = stream; v.play().catch(() => {});
      let busy = false;
      timer = setInterval(async () => {
        if (busy || !v.isConnected || v.readyState < 2) return; busy = true;
        try { const r = await det.detect(v); if (r && r.length && r[0].rawValue) finish(r[0].rawValue); } catch (e) { /* frame not ready */ }
        busy = false;
      }, 220);
    };
    function teardownMedia() { if (timer) { clearInterval(timer); timer = null; } if (stream) { stream.getTracks().forEach((tr) => { try { tr.stop(); } catch (e) { /* ignore */ } }); stream = null; } }

    (async () => {
      try { await B.loadStatic(); } catch (e) { /* rules default off */ }
      if (done) return;
      const m = modes();
      if (!m.cam && !m.dev) return showNone();
      if (m.cam && m.dev) {
        screen = 'pick';
        card(`<div class="stack"><button class="primary" data-bc="cam">${esc(T('cam'))}</button><button class="primary" data-bc="dev">${esc(T('dev'))}</button><button data-bc="cancel">${esc(T('cancel'))}</button></div>`);
        on('[data-bc=cam]', () => showCamera(m)); on('[data-bc=dev]', () => showDevice(m)); on('[data-bc=cancel]', () => finish(null));
      } else if (m.cam) showCamera(m); else showDevice(m);
    })();
  });
}
// find the item with this exact barcode in a list of items
const find = (code, items) => { const c = String(code || '').trim(); return c ? ((items || []).find((i) => i.barcode && String(i.barcode).trim() === c) || null) : null; };
// scan and resolve to an item of `items` (rows with a barcode column); a code with no product shows "No product has this barcode" and gives null.
// Used by the purchase bill lines and the stock actions. Does nothing visible when both scan options are off (scan() then explains where to enable them).
async function scanItem(items) {
  const code = await scan(); if (!code) return null;
  const it = find(code, items); if (!it) toast(T('nomatch') + ' · ' + code);
  return it;
}
const enabled = () => { const m = modes(); return !!(m.cam || m.dev); };
B.barcode = { scan, modes, find, scanItem, enabled, label: (k) => T(k) };
})();
