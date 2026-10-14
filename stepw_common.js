/* Islamia BOS · Step W shared helpers (new screens for the phase 72-84 backend): readable error labels, a "system recommends" card for every switch,
   place names. Loaded BEFORE formscreens.js / chanedit.js / costboard.js / packflags.js. Optional: nothing else depends on it.
   Language rule: English mode is ALL English; Bangla mode keeps common words in English; the mix is Bangla + English words. Handlers are prefixed wx_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A) return;
const { sb, S, esc, toast, fail } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const X = {
  rec: L('সিস্টেমের পরামর্শ', 'System recommends', 'System-এর পরামর্শ'),
  now: L('এখন', 'Now', 'এখন'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), blank: L('ফাঁকা (বসানো নেই)', 'Blank (not set)', 'Blank (বসানো নেই)'),
  advice: L('শুধু পরামর্শ — আপনি না চাপলে কিছু বদলায় না।', 'Advice only - nothing changes unless you press a button.', 'শুধু advice — আপনি না চাপলে কিছু বদলায় না।'),
  ownerOnly: L('শুধু মালিক বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner বদলাতে পারেন'),
  save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), useRec: L('পরামর্শ মানুন', 'Use the recommendation', 'পরামর্শ মানুন'),
  noRec: L('কোনো নির্দিষ্ট সংখ্যা দেওয়া নেই — আপনি বসান', 'No fixed number is given - you decide', 'কোনো fixed সংখ্যা নেই — আপনি বসান'),
  loading: L('লোড হচ্ছে…', 'Loading...', 'Loading…'), none: L('কিছু নেই ✓', 'Nothing here ✓', 'কিছু নেই ✓'),
  noperm: L('এই পাতা দেখার অনুমতি নেই', 'You are not allowed to see this page', 'এই page দেখার permission নেই'),
  place: L('জায়গা', 'Place', 'Place'), allPlaces: L('সব জায়গা', 'All places', 'সব place'), back: L('ফিরে যান', 'Back', 'Back'), close: L('বন্ধ', 'Close', 'Close'),
  badNum: L('সংখ্যা ঠিক নয়', 'Number is not valid', 'Number ঠিক নয়'),
};
// server error text -> readable label (first match wins; most specific first)
const ERRS = [
  [/function .* does not exist|schema cache|Could not find the function|PGRST202/i, L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part is not installed yet', 'Database অংশ এখনও চালু হয়নি')],
  [/not allowed for this location/i, L('এই জায়গার জন্য অনুমতি নেই', 'Not allowed for this place', 'এই place-এর জন্য permission নেই')],
  [/not_fully_covered/i, L('ভাউচারের কিছু লাইনের সাথে মিলে এমন quick খরচ নেই — লিংক হবে না', 'Some voucher lines have no matching quick expense - cannot link', 'Voucher-এর কিছু line-এর সাথে মিলে এমন quick expense নেই — link হবে না')],
  [/not_a_voucher/i, L('এটা 10-2 ভাউচার নয়', 'This is not a 10-2 voucher', 'এটা 10-2 voucher নয়')],
  [/entry_is_a_primary/i, L('এই ভাউচার আগেই অন্য রেকর্ডের মূল — লিংক করা যায় না', 'This voucher is already the main record of another link', 'এই voucher আগেই অন্য record-এর primary — link করা যায় না')],
  [/bad_status/i, L('বর্তমান অবস্থায় এটা করা যায় না', 'Not possible in the current status', 'বর্তমান status-এ এটা করা যায় না')],
  [/note_needed|reason_required/i, L('কারণ লিখতে হবে (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 letters)', 'কারণ লিখতে হবে (কমপক্ষে ৩ অক্ষর)')],
  [/not_short/i, L('এই চালানে ঘাটতি নেই', 'This transfer has no shortage', 'এই transfer-এ ঘাটতি নেই')],
  [/period.*(closed|lock)|locked/i, L('হিসাবের মাস বন্ধ (lock) — মালিককে বলুন', 'The accounting period is locked - ask the owner', 'Period lock করা — owner-কে বলুন')],
  [/bad_range/i, L('তারিখের সীমা ঠিক নয় (সর্বোচ্চ ৩৬৬ দিন)', 'Date range is not valid (366 days at most)', 'তারিখের range ঠিক নয় (সর্বোচ্চ ৩৬৬ দিন)')],
  [/bad_kind/i, L('চ্যানেলের ধরন ঠিক নয়', 'Channel type is not valid', 'Channel type ঠিক নয়')],
  [/other_text_required/i, L('"অন্য" হলে নাম লিখতে হবে', 'For "Other" write what it is', '"Other" হলে নাম লিখতে হবে')],
  [/name_required/i, L('নাম লিখুন (সর্বোচ্চ ৬০ অক্ষর)', 'Enter a name (60 letters at most)', 'নাম লিখুন (সর্বোচ্চ ৬০ অক্ষর)')],
  [/bad_code/i, L('কোড: ছোট ইংরেজি অক্ষর, সংখ্যা বা _ (২-৩০ অক্ষর)', 'Code: lowercase letters, digits or _ (2-30 characters)', 'Code: ছোট English letter, digit বা _ (২-৩০ অক্ষর)')],
  [/duplicate key|unique/i, L('এই কোড আগেই আছে', 'This code is already used', 'এই code আগেই আছে')],
  [/location_not_found/i, L('জায়গা পাওয়া যায়নি', 'Place not found', 'Place পাওয়া যায়নি')],
  [/role_not_found/i, L('ভূমিকা পাওয়া যায়নি', 'Role not found', 'Role পাওয়া যায়নি')],
  [/cost_missing/i, L('কোনো উপকরণের দাম অজানা (ফাঁকা বা ০) — আগে দাম বসান, তারপর উৎপাদন', 'An ingredient cost is unknown (empty or 0) - fill the cost first, then produce', 'কোনো ingredient-এর cost অজানা (ফাঁকা বা ০) — আগে cost বসান, তারপর production')],
  [/not_found|not found/i, L('রেকর্ড পাওয়া যায়নি', 'Record not found', 'Record পাওয়া যায়নি')],
  [/bad_value/i, L('মান ঠিক নয়', 'Value is not valid', 'Value ঠিক নয়')],
  [/not allowed/i, L('অনুমতি নেই', 'Not allowed', 'Permission নেই')],
];
function errText(e) {
  const m = ((e && e.message) || String(e || '')) + ' ' + ((e && e.details) || '');
  const hit = ERRS.find((x) => x[0].test(m));
  if (!hit) return null;
  const t = lab(hit[1]);
  return /cost_missing/i.test(m) && e && e.details ? t + ' (' + String(e.details).slice(0, 120) + ')' : t;
}
const err = (e) => { const t = errText(e); return t ? toast(t) : fail(e); };
const T = (k) => lab(X[k]);
const own = () => !!(S.ctx && S.ctx.is_owner);
const nm = (o, a, b) => lab({ bn: o[a] || o[b], mix: o[a] || o[b], en: o[b] || o[a] });
const nmItem = (x) => (x ? (x.code ? x.code + ' · ' : '') + nm(x, 'name_bn', 'name_en') : '—') ;
const num = (v) => { const s = String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim(); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const day = (v) => (v ? String(v).slice(0, 10) : '—');
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
let LOCS = null;
async function locs() {
  if (LOCS) return LOCS;
  try { const r = await sb.from('locations').select('id,name_bn,name_en').order('id'); LOCS = r.data || []; } catch (e) { LOCS = []; }
  return LOCS;
}
const locName = (id) => { const l = (LOCS || []).find((z) => z.id === id); return l ? nm(l, 'name_bn', 'name_en') : '#' + id; };
const locOpts = (sel, withAll) => (withAll ? `<option value="">${esc(T('allPlaces'))}</option>` : '') + (LOCS || []).map((l) => `<option value="${l.id}" ${String(l.id) === String(sel) ? 'selected' : ''}>${esc(nm(l, 'name_bn', 'name_en'))}</option>`).join('');
const shown = (v, kind, choices) => {
  if (v === null || v === undefined || v === '') return T('blank');
  if (kind === 'switch') return v === true || v === 'true' ? T('on') : T('off');
  const c = (choices || []).find((z) => z.v === v); return c ? lab(c.l) : String(v);
};

// ---- the "system recommends" card. spec = { key, kind: switch|choice|number, label, current, recommended, reason, choices:[{v,l}], unit } ----
let REDRAW = null;
const setRedraw = (fn) => { REDRAW = fn; };
function recCard(sp) {
  const same = sp.recommended !== null && sp.recommended !== undefined && String(sp.current) === String(sp.recommended);
  const recTxt = sp.recommended === null || sp.recommended === undefined ? T('noRec') : shown(sp.recommended, sp.kind, sp.choices);
  let ctl = '';
  if (own()) {
    if (sp.kind === 'switch') ctl = [[true, 'on'], [false, 'off']].map(([v, k]) => `<button class="${String(sp.current) === String(v) ? 'primary ' : ''}full" data-act="wx_set" data-k="${esc(sp.key)}" data-v="${v}">${esc(T(k))}</button>`).join('');
    else if (sp.kind === 'choice') ctl = (sp.choices || []).map((c) => `<button class="${String(sp.current) === c.v ? 'primary ' : ''}full" data-act="wx_set" data-k="${esc(sp.key)}" data-v="${esc(c.v)}">${esc(lab(c.l))}</button>`).join('');
    else ctl = `<div class="row"><input id="wx_n_${esc(sp.key)}" inputmode="decimal" value="${esc(sp.current ?? '')}" placeholder="${esc(sp.unit || '')}"><button class="primary" data-act="wx_set_num" data-k="${esc(sp.key)}">${esc(T('save'))}</button></div>`;
  } else ctl = `<p class="muted">${esc(T('ownerOnly'))}</p>`;
  return `<div class="card" data-rule="${esc(sp.key)}"><b>${esc(sp.label)}</b>
    <div class="muted">${esc(T('now'))}: <b>${esc(shown(sp.current, sp.kind, sp.choices))}</b>${same ? ' ✓' : ''}</div>
    <div class="notice info">${esc(T('rec'))}: <b>${esc(recTxt)}</b>${sp.reason ? '<br>' + esc(sp.reason) : ''}</div>
    <div class="muted">${esc(T('advice'))}</div>
    <div class="row wrap">${ctl}</div></div>`;
}
async function setRule(key, value) {
  const { error } = await sb.rpc('set_rule', { p_key: key, p_value: value });
  if (error) { err(error); return false; }
  try { if (B.reloadRules) await B.reloadRules(); } catch (e) { /* rules refresh is best effort */ }
  toast(T('saved')); if (REDRAW) REDRAW(); return true;
}
const parseV = (s) => (s === 'true' ? true : s === 'false' ? false : s);
A.H = A.H || {};
Object.assign(A.H, {
  wx_set: (a) => setRule(a.dataset.k, parseV(a.dataset.v)),
  wx_set_num: (a) => { const n = num(($('#wx_n_' + a.dataset.k) || {}).value); if (n === null) return setRule(a.dataset.k, null); if (Number.isNaN(n) || n < 0) return toast(T('badNum')); return setRule(a.dataset.k, n); },
});
// a one-line "back to" link row used by the boards
const links = (arr) => `<div class="row wrap" style="margin:6px 0">${arr.map(([r, t]) => `<a class="btn" href="#/${r}">${esc(lab(t))}</a>`).join('')}</div>`;
B.w = { X, T, ERRS, errText, err, own, nm, nmItem, num, q, day, today, locs, locName, locOpts, shown, recCard, setRule, setRedraw, links };
})();
