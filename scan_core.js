/* Islamia BOS · recognition core (X5). PURE logic, no DOM, no network: runs in the browser and in node tests.
   - engine selection with honest capability checks (what this phone can do, and which settings are on)
   - label text parsing (price, weight, expiry-like, brand guess) from OCR text, Bangla digits accepted
   - name matching for suggestions (Bangla / English / Banglish, exact / contains / close / token overlap)
   - nearest-neighbour search over item image vectors (cosine distance; no fake percentage is ever produced)
   - image size and type rules for the shared photo helper
   Browser: window.BOS_SCAN_CORE. Node: module.exports. Nothing here writes anything or calls a server. */
(function (root) {
'use strict';

// ---------- settings and capabilities ----------
// settings: { barcode_camera_on, barcode_device_on, recog_ocr_on, recog_image_match_on, recog_vision_on, recog_vision_consent_on,
//             recog_image_threshold (number|null), recog_ocr_max_px (number|null), recog_ocr_langs (string|null), recog_ocr_wifi_only (bool),
//             recog_vision_budget (number|null) }
// caps: { https, native, barcodeDetector, camera, wasm, indexedDb, networkOnline, x1Gate }
// Every engine reports: on (the switch), usable (may run now), reason (one short key, shown to the person).
const REASON = {
  off: 'off', needs_https: 'needs_https', no_camera: 'no_camera', no_native_detector: 'no_native_detector', no_wasm: 'no_wasm',
  setting_needed: 'setting_needed', needs_consent: 'needs_consent', needs_x1: 'needs_x1', no_index: 'no_index', threshold_not_set: 'threshold_not_set',
  budget_not_set: 'budget_not_set', wifi_only: 'wifi_only', ok: 'ok', native: 'native', pwa_engine: 'pwa_engine',
};

function ok(v) { return v === true; }
function isNum(v) { return v !== null && v !== undefined && v !== '' && isFinite(Number(v)); }

function barcodeChoice(settings, caps) {
  const cam = ok(settings.barcode_camera_on), dev = ok(settings.barcode_device_on);
  const out = [];
  if (cam && caps.native && caps.camera) out.push({ engine: 'native_barcode', usable: true, reason: REASON.native });
  if (cam && !caps.native) {
    if (!caps.https) out.push({ engine: 'barcode_detector', usable: false, reason: REASON.needs_https });
    else if (!caps.camera) out.push({ engine: 'barcode_detector', usable: false, reason: REASON.no_camera });
    else if (caps.barcodeDetector) out.push({ engine: 'barcode_detector', usable: true, reason: REASON.ok });
    else out.push({ engine: 'zxing_fallback', usable: !!caps.wasm && caps.https && !!caps.camera, reason: caps.wasm ? REASON.ok : REASON.no_wasm });
  }
  if (dev) out.push({ engine: 'device_typed', usable: true, reason: REASON.ok });
  if (!cam && !dev) out.push({ engine: 'barcode', usable: false, reason: REASON.off });
  return out;
}

// the engine to use for one task: 'barcode' | 'ocr' | 'image' | 'vision'. Returns { engine, usable, reason, tried[] }.
function chooseEngine(task, settings, caps) {
  settings = settings || {}; caps = caps || {};
  let tried;
  if (task === 'barcode') {
    tried = barcodeChoice(settings, caps);
  } else if (task === 'ocr') {
    tried = [{ engine: 'ocr_tesseract', usable: false, reason: REASON.off }];
    if (ok(settings.recog_ocr_on)) {
      let reason = REASON.ok, usable = true;
      if (!caps.https) { usable = false; reason = REASON.needs_https; }
      else if (!caps.wasm) { usable = false; reason = REASON.no_wasm; }
      else if (!(Number(settings.recog_ocr_max_px) > 0)) { usable = false; reason = REASON.setting_needed; }
      else if (!settings.recog_ocr_langs) { usable = false; reason = REASON.setting_needed; }
      else if (ok(settings.recog_ocr_wifi_only) && !caps.onWifi && !caps.cachedLang) { usable = false; reason = REASON.wifi_only; }
      tried = [{ engine: 'ocr_tesseract', usable, reason }];
    }
  } else if (task === 'image') {
    let usable = true, reason = REASON.ok;
    if (!ok(settings.recog_image_match_on)) { usable = false; reason = REASON.off; }
    else if (!caps.https) { usable = false; reason = REASON.needs_https; }
    else if (!caps.indexedDb) { usable = false; reason = REASON.no_index; }
    else if (!isNum(settings.recog_image_threshold) || Number(settings.recog_image_threshold) < 0) { usable = false; reason = REASON.threshold_not_set; }
    else if (!caps.modelLoaded) { usable = false; reason = REASON.no_index; }
    tried = [{ engine: 'image_nn_on_device', usable, reason }];
  } else if (task === 'vision') {
    let usable = true, reason = REASON.ok;
    if (!ok(settings.recog_vision_on)) { usable = false; reason = REASON.off; }
    else if (!ok(settings.recog_vision_consent_on)) { usable = false; reason = REASON.needs_consent; }
    else if (!caps.x1Gate) { usable = false; reason = REASON.needs_x1; }
    else if (!(Number(settings.recog_vision_budget) > 0)) { usable = false; reason = REASON.budget_not_set; }
    else if (!caps.networkOnline) { usable = false; reason = REASON.no_camera; }
    tried = [{ engine: 'vision_proxy', usable, reason }];
  } else {
    throw new Error('unknown task: ' + task);
  }
  const first = tried.find((t) => t.usable) || tried[0] || { engine: null, usable: false, reason: REASON.off };
  return { engine: first.engine, usable: !!first.usable, reason: first.reason, tried };
}

// the list every settings row needs: one entry per engine with on/usable/reason, never a guess
function statusTable(settings, caps) {
  return [
    { id: 'barcode', task: 'barcode', choice: chooseEngine('barcode', settings, caps) },
    { id: 'ocr', task: 'ocr', choice: chooseEngine('ocr', settings, caps) },
    { id: 'image', task: 'image', choice: chooseEngine('image', settings, caps) },
    { id: 'vision', task: 'vision', choice: chooseEngine('vision', settings, caps) },
    { id: 'native', task: 'native', choice: { engine: caps.native ? 'native_wrapper' : null, usable: !!caps.native, reason: caps.native ? REASON.native : REASON.pwa_engine, tried: [] } },
  ];
}

// ---------- text normalisation (Bangla / English / Banglish) ----------
const BN_DIGITS = '০১২৩৪৫৬৭৮৯';
function toAsciiDigits(s) { return String(s == null ? '' : s).replace(/[০-৯]/g, (d) => String(BN_DIGITS.indexOf(d))); }
// comparison key: NFC, no zero-width joiners, no nukta/danda, lower case, digits ascii, no spaces or punctuation
function key(s) {
  let t = String(s == null ? '' : s);
  try { t = t.normalize('NFC'); } catch (e) { /* ignore */ }
  t = t.replace(/[​-‍﻿]/g, '').replace(/য়/g, 'য়').replace(/ড়/g, 'ড়').replace(/ঢ়/g, 'ঢ়').replace(/।/g, '');
  return toAsciiDigits(t.toLowerCase()).replace(/[\s.,;:!?()[\]{}\/_&+\-'"`]+/g, '');
}
// word tokens (spaces and punctuation split), for overlap
function tokens(s) {
  let t = String(s == null ? '' : s).normalize ? String(s).normalize('NFC') : String(s);
  return toAsciiDigits(t.toLowerCase()).split(/[\s.,;:!?()[\]{}\/_&+\-'"`]+/).filter((x) => x.length > 0);
}
function lev1(a, b) {
  const la = a.length, lb = b.length;
  if (Math.abs(la - lb) > 1 || Math.min(la, lb) < 4) return false;
  if (a === b) return true;
  let i = 0; while (i < Math.min(la, lb) && a[i] === b[i]) i++;
  if (la === lb) return a.slice(i + 1) === b.slice(i + 1);
  if (la > lb) return a.slice(i + 1) === b.slice(i);
  return a.slice(i) === b.slice(i + 1);
}

// ---------- label text (OCR) parsing: never saved, only shown for review ----------
const PRICE_RE = /(?:৳|tk\.?|taka|mrp|price|দাম|মূল্য)\s*[:\-]?\s*([0-9]+(?:\.[0-9]{1,2})?)|([0-9]+(?:\.[0-9]{1,2})?)\s*(?:৳|tk\.?|taka|টাকা)/gi;
const WEIGHT_RE = /([0-9]+(?:\.[0-9]+)?)\s*(kilogram|kilo|kg|gram|gm|g|গ্রাম|কেজি|কিলো|ml|ltr|litre|liter|l|লিটার|pcs|pc|piece|পিস)(?![A-Za-z\u0980-\u09FF])/gi;
const EXP_RE = /(?:exp(?:iry)?|use by|best before|মেয়াদ|মেয়াদোত্তীর্ণ)\s*[:\-]?\s*([0-9]{1,2}[\/\-.][0-9]{2,4}|[0-9]{4}[\/\-.][0-9]{1,2}(?:[\/\-.][0-9]{1,2})?)/gi;
const UNIT_MAP = { kg: 'kg', kilo: 'kg', kilogram: 'kg', কেজি: 'kg', কিলো: 'kg', g: 'g', gm: 'g', gram: 'g', গ্রাম: 'g', ml: 'ml', ltr: 'l', l: 'l', litre: 'l', liter: 'l', লিটার: 'l', pcs: 'pc', pc: 'pc', piece: 'pc', পিস: 'pc' };

function parseLabel(text) {
  const raw = String(text == null ? '' : text).slice(0, 4000);
  const t = toAsciiDigits(raw);
  const lines = t.split(/\r?\n/).map((x) => x.trim()).filter(Boolean).slice(0, 40);
  const prices = [], weights = [], expiry = [];
  let m;
  const pr = new RegExp(PRICE_RE.source, 'gi');
  while ((m = pr.exec(t)) !== null) { const v = Number(m[1] || m[2]); if (isFinite(v) && v >= 0 && v <= 1000000) prices.push({ value: v, raw: m[0].trim() }); }
  const wr = new RegExp(WEIGHT_RE.source, 'gi');
  while ((m = wr.exec(t)) !== null) { const u = UNIT_MAP[m[2].toLowerCase()] || UNIT_MAP[m[2]]; if (u) weights.push({ value: Number(m[1]), unit: u, raw: m[0].trim() }); }
  const er = new RegExp(EXP_RE.source, 'gi');
  while ((m = er.exec(t)) !== null) expiry.push({ raw: m[1].trim() });
  // the name guess: the longest line without digits and without a price word, first 80 characters
  const nameLines = lines.filter((x) => /[A-Za-zঀ-৿]/.test(x) && !/\d{2,}/.test(x) && !/^(exp|mrp|price|tk|best|use by|মেয়াদ|দাম|মূল্য)/i.test(x));
  const nameGuess = nameLines.sort((a, b) => b.length - a.length)[0] || '';
  const brandGuess = (lines.find((x) => /^[A-Z][A-Za-z]{2,}$/.test(x)) || '').slice(0, 40);
  return { lines, prices, weights, expiry, nameGuess: nameGuess.slice(0, 80), brandGuess, text: raw };
}

// ---------- suggestion ranking ----------
// rows: [{ code, name_bn, name_en, name_mix, barcode, id }]; sources: [{ source: 'dictionary'|'items'|'label_text'|'barcode'|'photo'|'alias', rows: [...] }]
// query: string. Returns [{ id, code, name_bn, name_en, sources:[...], band: 'exact'|'close'|'partial', why }] (no percentage).
function rankSuggestions(query, sources, limit) {
  const q = key(query);
  const qt = tokens(query);
  const max = limit || 8;
  const byKey = new Map();
  (sources || []).forEach((src) => {
    (src.rows || []).forEach((r) => {
      const id = r.id || r.code || r.key; if (!id) return;
      const names = [r.name_bn, r.name_en, r.name_mix].filter(Boolean);
      let band = null, why = '';
      if (src.source === 'barcode' && r.barcode && query && String(r.barcode).trim() === String(query).trim()) { band = 'exact'; why = 'barcode'; }
      else if (q.length >= 2) {
        for (const n of names) {
          const nk = key(n);
          if (!nk) continue;
          if (nk === q) { band = 'exact'; why = 'name'; break; }
          if (q.length >= 3 && nk.length >= 3 && (nk.indexOf(q) >= 0 || q.indexOf(nk) >= 0)) { if (band !== 'exact') { band = 'close'; why = 'contains'; } }
          else if (lev1(nk, q) && band !== 'close') { band = 'close'; why = 'one letter'; }
        }
        if (!band && qt.length) {
          const nt = tokens(names.join(' '));
          const hit = qt.filter((w) => nt.some((x) => x === w || (w.length >= 3 && x.indexOf(w) >= 0))).length;
          if (hit > 0 && hit / qt.length >= 0.5) { band = 'partial'; why = 'words'; }
        }
      }
      if (!band) return;
      const cur = byKey.get(id) || { id, code: r.code || null, name_bn: r.name_bn || '', name_en: r.name_en || '', sources: [], band: 'partial', why: '' };
      if (!cur.sources.includes(src.source)) cur.sources.push(src.source);
      const rank = { exact: 3, close: 2, partial: 1 };
      if (rank[band] > rank[cur.band] || !cur.why) { cur.band = band; cur.why = why; }
      byKey.set(id, cur);
    });
  });
  const arr = [...byKey.values()];
  arr.sort((a, b) => ({ exact: 3, close: 2, partial: 1 })[b.band] - ({ exact: 3, close: 2, partial: 1 })[a.band] || b.sources.length - a.sources.length || String(a.code || '').localeCompare(String(b.code || '')));
  return arr.slice(0, max);
}

// ---------- nearest neighbours over item image vectors ----------
// index: [{ item_id, vec: number[] }]. Distance = 1 - cosine similarity (0 = same direction). Never shown as a percentage.
function norm(v) { let s = 0; for (let i = 0; i < v.length; i++) s += v[i] * v[i]; return Math.sqrt(s); }
function nearest(vec, index, opts) {
  opts = opts || {};
  const k = opts.k || 5;
  if (!Array.isArray(vec) || !vec.length) throw new Error('bad_vector');
  if (!isNum(opts.threshold) || Number(opts.threshold) < 0) return { hits: [], reason: REASON.threshold_not_set };
  const qn = norm(vec); if (!(qn > 0)) return { hits: [], reason: 'zero_vector' };
  const hits = [];
  for (const row of index || []) {
    const v = row.vec; if (!v || v.length !== vec.length) throw new Error('dim_mismatch');
    const vn = norm(v); if (!(vn > 0)) continue;
    let dot = 0; for (let i = 0; i < v.length; i++) dot += v[i] * vec[i];
    const dist = Math.max(0, Math.min(2, 1 - dot / (qn * vn)));
    if (dist <= Number(opts.threshold)) hits.push({ item_id: row.item_id, distance: Math.round(dist * 1e6) / 1e6 });
  }
  hits.sort((a, b) => a.distance - b.distance || String(a.item_id).localeCompare(String(b.item_id)));
  return { hits: hits.slice(0, k), reason: hits.length ? REASON.ok : 'no_match_within_threshold' };
}

// ---------- photo rules (shared helper) ----------
const PHOTO = { maxBytes: 3145728, types: ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'], outType: 'image/jpeg' };
function validateFile(f) {
  if (!f) return 'no_file';
  if (!PHOTO.types.includes(String(f.type || '').toLowerCase())) return 'bad_type';
  if (!(f.size > 0)) return 'empty';
  if (f.size > PHOTO.maxBytes) return 'too_big';
  return null;
}
// the size to draw: longest side = max, never upscaled, never 0
function fitSize(w, h, max) {
  if (!(w > 0) || !(h > 0)) return { w: 1, h: 1 };
  const k = Math.min(1, (max || 1280) / Math.max(w, h));
  return { w: Math.max(1, Math.round(w * k)), h: Math.max(1, Math.round(h * k)) };
}

const api = {
  REASON, chooseEngine, statusTable, key, tokens, toAsciiDigits, lev1, parseLabel, rankSuggestions, nearest, validateFile, fitSize, PHOTO,
};
if (typeof module !== 'undefined' && module.exports) module.exports = api;
if (root) root.BOS_SCAN_CORE = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
