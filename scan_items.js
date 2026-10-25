/* Islamia BOS · Camera & Recognition (X5). Engines, name suggestions and the settings screen (#/camrec).
   Pure decisions live in scan_core.js (chooseEngine, parseLabel, rankSuggestions, nearest). This file does the browser part:
     B.scanitems.caps() / status()         what this phone can do right now (detected, never assumed)
     B.scanitems.fallbackDetector()        ZXing (vendored) barcode reader used by barcode.js when BarcodeDetector is missing
     B.scanitems.ocrRead(blob)             on-device OCR (Tesseract.js, vendored core; language data downloaded once, cached)
     B.scanitems.matchPhoto(blob)          photo to nearest approved item photos; needs an embedder (none is vendored yet) and a threshold
     B.scanitems.suggest(input, opts)      Item Name suggestions under a text field (dictionary, items, aliases, scan results)
     B.scanitems.selfTest()                runs each engine on a sample and reports works / not supported / needs https / needs permission / needs setting
   Nothing here saves an item. A recognised text or photo only fills a suggestion list; the person chooses. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, H } = A;
const L = B.L, lab = B.lab;
const core = window.BOS_SCAN_CORE;
const T = (bn, en, mix) => lab(L(bn, en, mix));

// language data is downloaded once (only when OCR is ON and the language is not cached). Change the host here if the owner hosts it.
const LANG_URL = 'https://tessdata.projectnaptha.com/4.0.0_fast/';
const CACHE = 'bos-x5-recog-v1';
const loaded = {};

function rule(k) { try { return B.rule ? B.rule(k, null) : null; } catch (e) { return null; } }
function settings() {
  const num = (k) => { const v = rule(k); return v === null || v === '' || v === undefined || !isFinite(Number(v)) ? null : Number(v); };
  const txt = (k) => { const v = rule(k); return typeof v === 'string' && v.trim() ? v.trim() : null; };
  const on = (k) => rule(k) === true || rule(k) === 'true';
  return {
    barcode_camera_on: on('barcode_camera_on'), barcode_device_on: on('barcode_device_on'),
    recog_ocr_on: on('recog_ocr_on'), recog_image_match_on: on('recog_image_match_on'), recog_vision_on: on('recog_vision_on'),
    recog_vision_consent_on: on('recog_vision_consent_on'), recog_image_threshold: num('recog_image_threshold'),
    recog_ocr_max_px: num('recog_ocr_max_px'), recog_ocr_langs: txt('recog_ocr_langs'), recog_ocr_wifi_only: rule('recog_ocr_wifi_only') !== false,
    recog_vision_budget: num('recog_vision_budget'),
  };
}
function caps() {
  const nav = navigator || {};
  const native = !!(window.BOS_SCAN_NATIVE && window.BOS_SCAN_NATIVE.available && window.BOS_SCAN_NATIVE.available());
  const conn = nav.connection || {};
  return {
    https: location.protocol === 'https:' || location.hostname === 'localhost', native,
    barcodeDetector: 'BarcodeDetector' in window, camera: !!(nav.mediaDevices && nav.mediaDevices.getUserMedia),
    wasm: typeof WebAssembly === 'object', indexedDb: !!window.indexedDB, networkOnline: nav.onLine !== false,
    onWifi: conn.type === 'wifi' || conn.type === 'ethernet', cachedLang: !!loaded.langCached,
    modelLoaded: !!(embedder && indexRows && indexRows.length), x1Gate: !!(window.BOS && window.BOS.x1 && window.BOS.x1.gate === true),
  };
}
function status() { return core.statusTable(settings(), caps()); }

// ---------- script loading (vendored files only) ----------
function loadScript(src) {
  if (loaded[src]) return loaded[src];
  loaded[src] = new Promise((res, rej) => {
    const s = document.createElement('script'); s.src = src; s.async = true;
    s.onload = () => res(); s.onerror = () => { delete loaded[src]; rej(new Error('script')); };
    document.head.appendChild(s);
  });
  return loaded[src];
}

// ---------- barcode fallback (ZXing, vendored): used by barcode.js only when BarcodeDetector is missing ----------
async function fallbackDetector() {
  if (!core.chooseEngine('barcode', { barcode_camera_on: true }, { https: true, camera: true, barcodeDetector: false, wasm: true }).usable) return null;
  try { await loadScript('vendor/zxing/zxing-library-0.21.3.min.js'); } catch (e) { return null; }
  const Z = window.ZXing; if (!Z || !Z.MultiFormatReader) return null;
  const reader = new Z.MultiFormatReader();
  const canvas = document.createElement('canvas'), ctx = canvas.getContext('2d', { willReadFrequently: true });
  return {
    async detect(video) {
      const w = video.videoWidth, h = video.videoHeight; if (!w || !h) return [];
      canvas.width = Math.min(640, w); canvas.height = Math.round(canvas.width * h / w);
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const px = ctx.getImageData(0, 0, canvas.width, canvas.height).data, lum = new Uint8ClampedArray(canvas.width * canvas.height);
      for (let i = 0, j = 0; i < px.length; i += 4, j++) lum[j] = (px[i] * 3 + px[i + 1] * 6 + px[i + 2]) / 10;
      try {
        const src = new Z.RGBLuminanceSource(lum, canvas.width, canvas.height), bmp = new Z.BinaryBitmap(new Z.HybridBinarizer(src));
        const r = reader.decode(bmp); return [{ rawValue: r.getText() }];
      } catch (e) { return []; }
    },
  };
}

// ---------- OCR (Tesseract.js, vendored core; language data from LANG_URL once) ----------
let ocrWorker = null, ocrLangs = null;
async function ocrRead(blob) {
  const s = settings(), c = caps(), choice = core.chooseEngine('ocr', s, c);
  if (!choice.usable) throw new Error(choice.reason);
  await loadScript('vendor/tesseract/tesseract.min.js');
  const Tes = window.Tesseract; if (!Tes) throw new Error('no_engine');
  const langs = s.recog_ocr_langs;
  if (!ocrWorker || ocrLangs !== langs) {
    if (ocrWorker) { try { await ocrWorker.terminate(); } catch (e) { /* ignore */ } }
    ocrWorker = await Tes.createWorker(langs, 1, { workerPath: 'vendor/tesseract/worker.min.js', corePath: 'vendor/tesseract/', langPath: LANG_URL, cacheMethod: 'write', logger: () => {} });
    ocrLangs = langs; loaded.langCached = true;
  }
  const img = await B.photo.shrink(blob, { max: s.recog_ocr_max_px, q: 0.85 });
  const r = await ocrWorker.recognize(img);
  return core.parseLabel(r && r.data ? r.data.text : '');
}

// ---------- image matching: an embedder (model) is plugged in later; the index lives on this phone (IndexedDB) ----------
let embedder = null, indexRows = null;
function setEmbedder(fn) { embedder = typeof fn === 'function' ? fn : null; }
async function matchPhoto(blob, opts) {
  const s = settings(), c = caps(), choice = core.chooseEngine('image', s, c);
  if (!choice.usable) return { hits: [], reason: choice.reason };
  const vec = await embedder(blob);
  return core.nearest(vec, indexRows || [], { k: (opts && opts.k) || 5, threshold: s.recog_image_threshold });
}

// ---------- name suggestions under a text field ----------
const DICT_URL = 'data/item_dictionary.json';
let dictRows = null;
async function dictionary() {
  if (dictRows) return dictRows;
  try { const r = await fetch(DICT_URL, { cache: 'force-cache' }); dictRows = r.ok ? (await r.json()).map((x) => ({ id: 'dict:' + x.code, code: x.code, name_bn: x.name_bn, name_en: x.name_en, source: 'dictionary' })) : []; }
  catch (e) { dictRows = []; }
  return dictRows;
}
const SOURCE_LABEL = { barcode: () => T('বারকোড', 'Barcode', 'Barcode'), label_text: () => T('লেবেল লেখা', 'Label text', 'Label text'), photo: () => T('ছবি মিল', 'Photo match', 'Photo match'), alias: () => T('আগের অনুমোদন', 'Approved before', 'আগের approve'), items: () => T('আছে এমন আইটেম', 'Existing item', 'আছে এমন item'), dictionary: () => T('অভিধান', 'Dictionary', 'Dictionary') };
const BAND_LABEL = { exact: () => T('হুবহু মিল', 'Exact', 'Exact'), close: () => T('কাছাকাছি', 'Close', 'কাছাকাছি'), partial: () => T('আংশিক', 'Partial', 'আংশিক') };

// opts: { field: 'bn' | 'en', getItems: () => rows, scanHits?: rows with source 'barcode' | 'label_text', onPick?: fn }
function suggest(input, opts) {
  const el = typeof input === 'string' ? document.querySelector(input) : input;
  if (!el || el.dataset.x5 === '1') return;
  el.dataset.x5 = '1';
  const box = document.createElement('div'); box.className = 'x5-sg'; box.setAttribute('role', 'listbox');
  box.style.cssText = 'display:none;border:1px solid var(--hair,#ccc);border-radius:8px;margin-top:4px;max-height:220px;overflow:auto;background:var(--card,#fff)';
  el.insertAdjacentElement('afterend', box);
  let timer = null, seq = 0, current = [];
  const draw = (list) => {
    current = list;
    if (!list.length) { box.style.display = 'none'; box.innerHTML = ''; return; }
    box.innerHTML = list.map((s, i) => `<button type="button" class="x5-sg-i" data-i="${i}" style="display:block;width:100%;text-align:start;padding:8px 10px;border:0;border-bottom:1px solid var(--hair,#ddd);background:none;min-height:44px">
      <b>${esc(s.name_bn || s.name_en || '')}</b>${s.name_en && s.name_bn ? ` <span class="muted">${esc(s.name_en)}</span>` : ''}
      <div class="muted" style="font-size:.8rem">${esc(s.sources.map((x) => (SOURCE_LABEL[x] ? SOURCE_LABEL[x]() : x)).join(' · '))} · ${esc(BAND_LABEL[s.band] ? BAND_LABEL[s.band]() : '')}</div></button>`).join('');
    box.style.display = 'block';
  };
  const run = async () => {
    const q = el.value.trim(); const my = ++seq;
    if (q.length < 2) return draw([]);
    const items = (opts.getItems && opts.getItems()) || [];
    const dict = await dictionary();
    let alias = [];
    try { const r = await sb.rpc('item_alias_find', { p_text: q }); if (!r.error && Array.isArray(r.data)) alias = r.data.map((x) => ({ id: x.item_id, code: x.code, name_bn: x.name_bn, name_en: x.name_en, barcode: null })); } catch (e) { /* no alias table yet */ }
    if (my !== seq) return;
    const hits = opts.scanHits || [];
    draw(core.rankSuggestions(q, [
      { source: 'barcode', rows: hits.filter((x) => x.source === 'barcode') },
      { source: 'items', rows: items.map((x) => ({ id: x.id, code: x.code, name_bn: x.name_bn, name_en: x.name_en, name_mix: x.name_mix, barcode: x.barcode })) },
      { source: 'alias', rows: alias },
      { source: 'dictionary', rows: dict },
      { source: 'label_text', rows: hits.filter((x) => x.source === 'label_text') },
    ], 8));
  };
  el.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(run, 180); });
  el.addEventListener('focus', () => { dictionary(); });
  el.addEventListener('blur', () => setTimeout(() => { box.style.display = 'none'; }, 200));
  box.addEventListener('click', (e) => {
    const b = e.target.closest('.x5-sg-i'); if (!b) return;
    const s = current[Number(b.dataset.i)]; if (!s) return;
    el.value = (opts.field === 'en' ? (s.name_en || s.name_bn) : (s.name_bn || s.name_en)) || '';
    box.style.display = 'none'; box.innerHTML = ''; current = [];
    if (opts.onPick) { try { opts.onPick(s); } catch (err) { /* the field is filled anyway */ } }
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

// ---------- self test: each engine, honest result (sample image generated here; no network except the language file) ----------
async function selfTest() {
  const s = settings(), c = caps(), rows = core.statusTable(s, c), out = [];
  for (const r of rows) {
    const ch = r.choice;
    let state = ch.usable ? 'works' : (ch.reason === 'needs_https' ? 'needs_https' : (ch.reason === 'off' ? 'off' : (/no_camera|no_wasm|no_native|no_index/.test(ch.reason) ? 'not_supported' : (/setting|budget|threshold|consent|x1/.test(ch.reason) ? 'needs_setting' : 'not_supported'))));
    let ran = null;
    if (r.id === 'ocr' && ch.usable) {
      try {
        const cv = document.createElement('canvas'); cv.width = 320; cv.height = 120; const g = cv.getContext('2d');
        g.fillStyle = '#fff'; g.fillRect(0, 0, 320, 120); g.fillStyle = '#000'; g.font = '28px sans-serif'; g.fillText('SAMPLE 120', 20, 70);
        const blob = await new Promise((res) => cv.toBlob(res, 'image/png'));
        const p = await ocrRead(blob); ran = { ok: p.lines.length > 0, prices: p.prices.length };
        state = ran.ok ? 'works' : 'ran_no_text';
      } catch (e) { state = 'needs_permission_or_download'; ran = { error: String(e && e.message || e) }; }
    }
    if (r.id === 'barcode' && ch.usable && ch.engine === 'zxing_fallback') {
      const d = await fallbackDetector(); state = d ? 'works' : 'not_supported';
    }
    out.push({ id: r.id, engine: ch.engine, usable: ch.usable, reason: ch.reason, state, ran, at: new Date().toISOString() });
  }
  try { localStorage.setItem('x5_last_test', JSON.stringify(out)); } catch (e) { /* storage blocked: the result is still shown */ }
  return out;
}

// ---------- the screen #/camrec ----------
const X = {
  title: ['ক্যামেরা ও স্ক্যান', 'Camera & Recognition', 'Camera & Recognition'],
  intro: ['প্রতিটি সুবিধা আলাদা। সব বন্ধ অবস্থায় আগের মতোই কাজ হয়। ছবি ফোন থেকে বাইরে যায় না, যদি না মালিক সার্ভার ভিশন চালু করে সম্মতি দেন।', 'Each option is separate. With everything off the app works as before. Photos stay on the phone unless the owner turns on the server vision option and consents.', 'প্রতিটি option আলাদা। সব off থাকলে আগের মতোই চলে। Photo phone এ থাকে, owner server vision চালু ও consent না দিলে বাইরে যায় না।'],
  selftest: ['নিজে পরীক্ষা করুন', 'Run self-test', 'Self-test চালান'],
  state: { works: ['চলে', 'Works', 'চলে'], not_supported: ['এই ফোনে নেই', 'Not supported on this phone', 'এই phone-এ নেই'], needs_https: ['https দরকার', 'Needs https', 'https দরকার'], needs_setting: ['সেটিং বাকি', 'Setting needed', 'Setting বাকি'], off: ['বন্ধ', 'Off', 'Off'], needs_permission_or_download: ['অনুমতি বা ফাইল নামানো দরকার', 'Needs permission or language download', 'Permission বা file download দরকার'], ran_no_text: ['চলেছে, লেখা পাওয়া যায়নি', 'Ran, no text found', 'চলেছে, লেখা পাওয়া যায়নি'] },
  engine: { barcode: ['বারকোড', 'Barcode', 'Barcode'], ocr: ['লেখা পড়া (OCR, ফোনে)', 'Label text (OCR, on phone)', 'লেখা পড়া (OCR, phone এ)'], image: ['ছবি মিলানো (ফোনে)', 'Photo match (on phone)', 'Photo match (phone এ)'], vision: ['সার্ভার ভিশন (খরচ, সম্মতি লাগে)', 'Server vision (paid, consent)', 'Server vision (খরচ, consent লাগে)'], native: ['অ্যান্ড্রয়েড অ্যাপের ভেতরে', 'Inside the Android wrapper', 'Android app এর ভেতরে'] },
  reason: { off: ['বন্ধ', 'off', 'off'], ok: ['প্রস্তুত', 'ready', 'প্রস্তুত'], needs_https: ['https দরকার', 'needs https', 'https দরকার'], no_camera: ['ক্যামেরা নেই বা অনুমতি নেই', 'no camera or no permission', 'ক্যামেরা নেই/অনুমতি নেই'], no_native_detector: ['না', 'no', 'না'], no_wasm: ['এই ব্রাউজারে নেই', 'not in this browser', 'এই browser এ নেই'], setting_needed: ['সেটিং খালি (টাইপ করুন)', 'blank setting (type a value)', 'সেটিং খালি (type করুন)'], needs_consent: ['মালিকের সম্মতি লাগে', 'owner consent needed', 'Owner consent লাগে'], needs_x1: ['X1 সংযোগ লাগে (এখনো নেই)', 'needs the X1 connection (not yet)', 'X1 connection লাগে (এখনো নেই)'], no_index: ['ছবির সূচি নেই', 'no photo index yet', 'Photo index নেই'], threshold_not_set: ['সীমা খালি', 'threshold not set', 'সীমা খালি'], budget_not_set: ['মাসিক সীমা খালি', 'monthly cap not set', 'মাসিক সীমা খালি'], wifi_only: ['ওয়াই-ফাই এর অপেক্ষা', 'waiting for Wi-Fi', 'Wi-Fi এর অপেক্ষা'], native: ['ভেতরে চলছে', 'running inside the app', 'app এর ভেতরে চলছে'], pwa_engine: ['ব্রাউজারে (অ্যাপ নেই)', 'in the browser (no app)', 'browser এ (app নেই)'] },
};
const stateLabel = (k) => (X.state[k] ? lab(L(...X.state[k])) : k);
const reasonLabel = (k) => (X.reason[k] ? lab(L(...X.reason[k])) : k);
const engineLabel = (k) => (X.engine[k] ? lab(L(...X.engine[k])) : k);
function rowHTML(r) {
  const ch = r.choice;
  return `<div class="card stack x5-row" data-engine="${esc(r.id)}"><div class="row between"><b>${esc(engineLabel(r.id))}</b><span class="chip ${ch.usable ? 'ok' : ''}">${esc(reasonLabel(ch.reason))}</span></div>
    <div class="muted" style="font-size:.85rem">${esc(ch.engine || '-')}</div></div>`;
}
function screenHTML(s, res) {
  const rows = core.statusTable(s, caps()).map((r) => rowHTML(r)).join('');
  const last = res ? `<div class="card stack" id="x5_last"><b>${esc(T('শেষ পরীক্ষা', 'Last self-test', 'শেষ self-test'))}</b>${res.map((x) => `<div class="row between"><span>${esc(engineLabel(x.id))}</span><span class="chip ${x.state === 'works' ? 'ok' : ''}">${esc(stateLabel(x.state))}</span></div>`).join('')}</div>` : '';
  return `<p class="muted">${esc(lab(L(...X.intro)))}</p>${rows}${last}
    <div class="card stack"><button type="button" class="primary" data-act="x5_test" id="x5_test_btn">${esc(lab(L(...X.selftest)))}</button></div>`;
}
let lastTest = null;
async function viewCamRec() {
  A.shell(lab(L(...X.title)), '<div id="x5_body"><p class="muted">…</p></div>', true);
  try { if (B.loadStatic) await B.loadStatic(); } catch (e) { /* rules default off */ }
  try { lastTest = JSON.parse(localStorage.getItem('x5_last_test') || 'null'); } catch (e) { lastTest = null; }
  const body = document.getElementById('x5_body'); if (body) body.innerHTML = screenHTML(settings(), lastTest);
}
H.x5_test = async () => {
  const btn = document.getElementById('x5_test_btn'); if (btn) btn.disabled = true;
  try { lastTest = await selfTest(); } catch (e) { fail(e); }
  if (btn) btn.disabled = false;
  const body = document.getElementById('x5_body'); if (body) body.innerHTML = screenHTML(settings(), lastTest);
};

window.BOS = window.BOS || {};
window.BOS.scanitems = { caps, settings, status, fallbackDetector, ocrRead, matchPhoto, setEmbedder, suggest, selfTest, dictionary, LANG_URL, version: 1 };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { camrec: viewCamRec });
})();
