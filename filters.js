/* Islamia BOS · reusable filter sheet (B.filters). Used by the report viewer; any list page can bind to it.
   State is a plain object in the shape report_run() accepts:
     { preset | from,to, locations:[int], brands:[text], staff:[text], items:[uuid], categories:[text], modes:[text],
       customer:[uuid], sale_type, min_amount, max_amount, status, search, _n:{names for chips, never sent} }
   Dates: a preset name (resolved by the server from report_presets, null = "Data needed") or a custom from/to.
   Nothing is fixed here: week start and fiscal-year start come from rules; a preset whose rule is empty says "Data needed". */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, openSheet, closeSheet, nm } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));

// ---------- labels (3 modes, Bng-Eng hyphenated) ----------
const X = {
  title: L('ফিল্টার', 'Filters', 'Filter'), apply: L('প্রয়োগ করুন', 'Apply', 'Apply করুন'), reset: L('রিসেট', 'Reset', 'Reset'), cancel: L('বন্ধ', 'Close', 'Close'),
  clear: L('সব মুছুন', 'Clear all', 'সব Clear'), remove: L('বাদ দিন', 'Remove', 'Remove'),
  s_date: L('তারিখ', 'Date', 'Date (তারিখ)'), s_loc: L('লোকেশন', 'Location', 'Location'), s_brand: L('ব্র্যান্ড', 'Brand', 'Brand'), s_staff: L('কর্মী', 'Staff', 'Staff (কর্মী)'),
  s_itype: L('আইটেমের ধরন', 'Item type', 'Item type'), s_item: L('আইটেম', 'Item', 'Item'), s_cat: L('ক্যাটাগরি', 'Category', 'Category'), s_mode: L('পেমেন্ট ধরন', 'Payment mode', 'Payment mode'),
  s_cust: L('গ্রাহক', 'Customer', 'Customer (গ্রাহক)'), s_type: L('খুচরা / পাইকারি', 'Sale type', 'Sale type (খুচরা/পাইকারি)'), s_amt: L('টাকার পরিমাণ', 'Amount range', 'Amount (টাকা)'),
  s_status: L('অবস্থা', 'Status', 'Status'), s_search: L('খুঁজুন', 'Search', 'Search'),
  from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), min: L('সর্বনিম্ন', 'Min', 'Min'), max: L('সর্বোচ্চ', 'Max', 'Max'),
  need: L('তথ্য দরকার', 'Data needed', 'Data দরকার'),
  need_fy: L('অর্থবছর শুরুর মাস নিয়মে (Rules) বসান', 'Set the fiscal-year start month in Rules', 'Rules-এ fiscal-year শুরুর মাস বসান'),
  need_wk: L('সপ্তাহ শুরুর বার নিয়মে (Rules) বসান', 'Set the week-start day in Rules', 'Rules-এ week শুরুর বার বসান'),
  nobrand: L('ব্র্যান্ড ঠিক করা নেই — তথ্য দরকার', 'No brand mapped yet — data needed', 'Brand ঠিক করা নেই — Data দরকার'),
  find: L('খুঁজুন…', 'Search…', 'খুঁজুন…'), none: L('কিছু নেই', 'Nothing', 'কিছু নেই'),
  m_cash: L('নগদ', 'Cash', 'Cash (নগদ)'), m_mobile: L('মোবাইল', 'Mobile', 'Mobile'), m_card: L('কার্ড', 'Card', 'Card'), m_due: L('বাকি', 'Due', 'Due (বাকি)'), m_split: L('ভাগ করা', 'Split', 'Split'),
  m_collection: L('বাকি আদায়', 'Collection', 'Collection'),
  t_retail: L('খুচরা', 'Retail', 'Retail (খুচরা)'), t_wholesale: L('পাইকারি', 'Wholesale', 'Wholesale (পাইকারি)'),
  st_done: L('সম্পন্ন', 'Done', 'Done'), st_void: L('বাতিল', 'Void', 'Void (বাতিল)'),
  searchph: L('রসিদ নং বা নাম', 'Receipt no. or name', 'Receipt no. বা নাম'),
  other: L('অন্যান্য', 'Other', 'Other'),
};
const T = (k) => lab(X[k]);
const PRESETS = [
  ['today', L('আজ', 'Today', 'Today (আজ)')], ['yesterday', L('গতকাল', 'Yesterday', 'Yesterday (গতকাল)')],
  ['last_7', L('শেষ ৭ দিন', 'Last 7 days', 'Last 7 দিন')], ['last_30', L('শেষ ৩০ দিন', 'Last 30 days', 'Last 30 দিন')],
  ['this_week', L('এই সপ্তাহ', 'This week', 'This week')], ['last_week', L('গত সপ্তাহ', 'Last week', 'Last week')],
  ['this_month', L('এই মাস', 'This month', 'This month')], ['last_month', L('গত মাস', 'Last month', 'Last month')],
  ['this_fy', L('এই অর্থবছর', 'This fiscal year', 'This fiscal year')], ['last_fy', L('গত অর্থবছর', 'Last fiscal year', 'Last fiscal year')],
];
const CATN = {
  sweet_kg: L('মিষ্টি (কেজি)', 'Sweets (KG)', 'মিষ্টি (KG)'), sweet_pc: L('মিষ্টি (পিস)', 'Sweets (Piece)', 'মিষ্টি (Piece)'), doi: L('দই', 'Doi (Curd)', 'Doi (দই)'),
  cake_lb: L('কেক (পাউন্ড)', 'Cake (Pound)', 'Cake (Pound)'), cake_pc: L('কেক (পিস)', 'Cake (Piece)', 'Cake (Piece)'),
};
const DEFAULT_PRESET = 'this_month';
const presetName = (k) => { const p = PRESETS.find((x) => x[0] === k); return p ? lab(p[1]) : k; };
const dhaka = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const shortDate = (iso) => (iso ? new Date(iso + 'T12:00:00Z').toLocaleDateString('en-GB', { day: '2-digit', month: 'short', timeZone: 'UTC' }) : '');
const catLabel = (c) => (CATN[c] ? lab(CATN[c]) : c);
const modeLabel = (m) => (X['m_' + m] ? T('m_' + m) : m);

// ---------- presets (server: report_presets; null value = a rule is missing) ----------
let PRE = null, preAt = 0;
async function loadPresets(force) {
  if (PRE && !force && Date.now() - preAt < 300000) return PRE;
  let p = null;
  try { const r = await sb.rpc('report_presets'); if (!r.error && r.data && typeof r.data === 'object') p = r.data; } catch (e) { /* offline */ }
  if (!p) {      // server unreachable: only the presets that need no rule can be worked out here
    const td = dhaka(), ms = td.slice(0, 8) + '01', lm = addDays(ms, -1);
    p = { today: { from: td, to: td }, yesterday: { from: addDays(td, -1), to: addDays(td, -1) }, last_7: { from: addDays(td, -6), to: td }, last_30: { from: addDays(td, -29), to: td },
      this_month: { from: ms, to: td }, last_month: { from: lm.slice(0, 8) + '01', to: lm }, this_week: null, last_week: null, this_fy: null, last_fy: null };
  }
  PRE = p; preAt = Date.now(); return p;
}
const presetRange = (k) => (PRE && PRE[k]) || null;

// ---------- option sources (cached for the session) ----------
const OPT = { brands: null, cats: null, custs: null, types: null };
const accessLocs = () => ((B.ENV && B.ENV.locs) || []).filter((l) => S.ctx.is_owner || (S.ctx.roles || []).includes('management') || (S.ctx.locations || []).includes(l.id));
async function preload(allow) {
  const a = new Set(allow || []);
  const jobs = [B.loadStatic ? B.loadStatic() : null, loadPresets()];
  if (a.has('brands') && !OPT.brands) jobs.push(sb.from('report_brand_map').select('*').then((r) => {
    const m = new Map(); (r.data || []).forEach((x) => { if (!m.has(x.brand_code)) m.set(x.brand_code, x); }); OPT.brands = [...m.values()]; }, () => { OPT.brands = []; }));
  if (a.has('categories') && !OPT.cats) jobs.push(window.BOS_ALL(sb.from('items').select('category,category_bn').order('code')).then((r) => {
    const m = new Map(); (r.data || []).forEach((x) => { if (x.category && !m.has(x.category)) m.set(x.category, x.category_bn || null); }); OPT.cats = [...m.entries()].map(([c, bn]) => ({ code: c, bn })); }, () => { OPT.cats = []; }));
  if (a.has('item_types') && !OPT.types) jobs.push(sb.from('item_types').select('code,label_bn,label_en,sort').eq('active', true).order('sort').then((r) => { OPT.types = r.data || []; }, () => { OPT.types = []; }));
  if (a.has('customer') && !OPT.custs) jobs.push(sb.from('customers').select('id,name,mobile').order('name').limit(1000).then((r) => { OPT.custs = r.data || []; }, () => { OPT.custs = []; }));
  await Promise.all(jobs.map((j) => Promise.resolve(j).catch(() => null)));
}
const brandName = (b) => (S.lang === 'en' ? (b.brand_en || b.brand_bn) : b.brand_bn);
const staffList = () => (B.ENV && B.ENV.staff) || [];
const itemList = () => (B.ENV && B.ENV.items) || [];
const staffName = (id) => { const s = staffList().find((x) => x.staff_id === id); return s ? (s.full_name || s.staff_id) : id; };
const nameOf = (st, k, id) => (st._n && st._n[k] && st._n[k][id]) || id;
const setName = (st, k, id, name) => { st._n = st._n || {}; st._n[k] = st._n[k] || {}; if (name) st._n[k][id] = name; };

// ---------- state helpers ----------
const ARR = ['locations', 'brands', 'staff', 'items', 'categories', 'item_types', 'modes', 'customer'];
const clone = (o) => JSON.parse(JSON.stringify(o || {}));
const defaults = (needsDate = true) => (needsDate ? { preset: DEFAULT_PRESET } : {});
function clean(st) {            // what the server may see
  const o = {};
  Object.keys(st || {}).forEach((k) => {
    if (k[0] === '_') return; const v = st[k];
    if (v === undefined || v === null || v === '') return; if (Array.isArray(v) && !v.length) return; o[k] = v;
  });
  return o;
}
function chipList(st, allow, needsDate = true) {
  const a = new Set(allow || []), out = [];
  if (needsDate && (st.preset || st.from || st.to)) {
    const r = st.preset ? presetRange(st.preset) : { from: st.from, to: st.to };
    const rt = r && r.from ? ` · ${shortDate(r.from)}${r.to && r.to !== r.from ? ' – ' + shortDate(r.to) : ''}` : '';
    out.push({ k: 'date', v: '', text: `${T('s_date')}: ${st.preset ? presetName(st.preset) : ''}${st.preset ? rt : `${shortDate(st.from) || '…'} – ${shortDate(st.to) || '…'}`}` });
  }
  const arr = (k, label, f) => { if (a.has(k) && Array.isArray(st[k]) && st[k].length) st[k].forEach((v) => out.push({ k, v: String(v), text: `${label}: ${f(v)}` })); };
  arr('locations', T('s_loc'), (v) => nm((B.ENV.locs || []).find((l) => l.id === Number(v))) || v);
  arr('brands', T('s_brand'), (v) => { const b = (OPT.brands || []).find((x) => x.brand_code === v); return b ? brandName(b) : v; });
  arr('staff', T('s_staff'), staffName);
  arr('items', T('s_item'), (v) => { const i = itemList().find((x) => x.id === v); return nameOf(st, 'items', v) !== v ? nameOf(st, 'items', v) : i ? nm(i) : v; });
  arr('categories', T('s_cat'), catLabel);
  arr('item_types', T('s_itype'), (v) => { const t = (OPT.types || []).find((x) => x.code === v); return t ? (S.lang === 'en' ? (t.label_en || t.label_bn) : t.label_bn) : v; });
  arr('modes', T('s_mode'), modeLabel);
  arr('customer', T('s_cust'), (v) => nameOf(st, 'customer', v));
  if (a.has('sale_type') && st.sale_type) out.push({ k: 'sale_type', v: '', text: `${T('s_type')}: ${X['t_' + st.sale_type] ? T('t_' + st.sale_type) : st.sale_type}` });
  if (a.has('status') && st.status) out.push({ k: 'status', v: '', text: `${T('s_status')}: ${X['st_' + st.status] ? T('st_' + st.status) : st.status}` });
  if (a.has('min_amount') && (st.min_amount !== undefined || st.max_amount !== undefined)) out.push({ k: 'amount', v: '', text: `${T('s_amt')}: ${st.min_amount ?? '…'} – ${st.max_amount ?? '…'}` });
  if (a.has('search') && st.search) out.push({ k: 'search', v: '', text: `${T('s_search')}: ${st.search}` });
  return out;
}
const isDefaultDate = (st) => st.preset === DEFAULT_PRESET && !st.from && !st.to;
const activeCount = (st, allow, needsDate = true) => chipList(st, allow, needsDate).filter((c) => !(c.k === 'date' && isDefaultDate(st))).length;
const summary = (st, allow, needsDate = true) => chipList(st, allow, needsDate).map((c) => c.text).join('; ');

// ---------- chips row bound to a host ----------
const HOSTS = {};
function bind(id, cfg) { HOSTS[id] = cfg; }
function chips(id) {
  const h = HOSTS[id]; if (!h) return '';
  const st = h.get(), list = chipList(st, h.allow, h.needsDate !== false);
  if (!list.length) return '';
  const any = list.some((c) => !(c.k === 'date' && isDefaultDate(st)));
  return `<div class="fl-chips" role="list">${list.map((c) => `<button class="fl-chip" role="listitem" data-act="fl_rm" data-h="${esc(id)}" data-k="${esc(c.k)}" data-v="${esc(c.v)}" aria-label="${esc(T('remove') + ': ' + c.text)}"><span>${esc(c.text)}</span><b aria-hidden="true">×</b></button>`).join('')}
    ${any ? `<button class="fl-clear" data-act="fl_clear" data-h="${esc(id)}">${esc(T('clear'))}</button>` : ''}</div>`;
}
function removeFrom(st, k, v, needsDate) {
  if (k === 'date') { delete st.from; delete st.to; if (needsDate) st.preset = DEFAULT_PRESET; else delete st.preset; }
  else if (k === 'amount') { delete st.min_amount; delete st.max_amount; }
  else if (Array.isArray(st[k])) { st[k] = st[k].filter((x) => String(x) !== String(v)); if (!st[k].length) delete st[k]; }
  else delete st[k];
  return st;
}

// ---------- the sheet ----------
let W = null;      // working copy while the sheet is open
const has = (k) => W.allow.has(k);
const tog = (on, attrs, label) => `<button class="tog fl-t ${on ? 'on' : ''}" aria-pressed="${on ? 'true' : 'false'}" ${attrs}>${esc(label)}</button>`;
const isOn = (k, v) => Array.isArray(W.st[k]) && W.st[k].some((x) => String(x) === String(v));
const sec = (id, title, count, inner, open) => `<details class="fl-sec" data-sec="${id}" ${open ? 'open' : ''}><summary><b>${esc(title)}</b><span class="fl-cnt" data-cnt="${id}">${count || ''}</span></summary><div class="fl-b">${inner}</div></details>`;
const cnt = (k) => (Array.isArray(W.st[k]) ? W.st[k].length : 0);
function dateSec() {
  const st = W.st, pre = PRE || {};
  const chipsH = PRESETS.map(([k, l]) => {
    const r = pre[k], missing = !r;
    if (missing) {
      const why = (k === 'this_fy' || k === 'last_fy') ? T('need_fy') : (k === 'this_week' || k === 'last_week') ? T('need_wk') : T('need');
      return `<button class="tog fl-t fl-na" data-act="fl_na" data-v="${esc(why)}" aria-disabled="true"><span>${esc(lab(l))}</span><small>${esc(T('need'))}</small></button>`;
    }
    return tog(st.preset === k, `data-act="fl_p" data-v="${k}"`, lab(l));
  }).join('');
  return `<div class="fl-chipset" id="fl_presets">${chipsH}</div>
    <div class="row" style="margin-top:10px"><div style="flex:1"><label for="fl_from">${esc(T('from'))}</label><input type="date" id="fl_from" value="${esc(st.from || (st.preset && pre[st.preset] ? pre[st.preset].from : '') || '')}"></div>
      <div style="flex:1"><label for="fl_to">${esc(T('to'))}</label><input type="date" id="fl_to" value="${esc(st.to || (st.preset && pre[st.preset] ? pre[st.preset].to : '') || '')}"></div></div>`;
}
function listSec(k, rows, q) {       // searchable multi-select: rows = [{v,label,sub}]
  const sel = new Set((W.st[k] || []).map(String));
  const ordered = [...rows.filter((r) => sel.has(String(r.v))), ...rows.filter((r) => !sel.has(String(r.v)))].slice(0, 400);
  return `${q ? `<input class="fl-q" data-for="${k}" type="search" autocomplete="off" placeholder="${esc(T('find'))}" aria-label="${esc(T('find'))}">` : ''}
    <div class="fl-list" data-list="${k}">${ordered.map((r) => `<button class="fl-r ${sel.has(String(r.v)) ? 'on' : ''}" aria-pressed="${sel.has(String(r.v))}" data-act="fl_t" data-k="${k}" data-v="${esc(String(r.v))}" data-name="${esc(r.label)}" data-n="${esc((r.label + ' ' + (r.sub || '')).toLowerCase())}">
      <i class="bx" aria-hidden="true"></i><span>${esc(r.label)}${r.sub ? ` <small>${esc(r.sub)}</small>` : ''}</span></button>`).join('') || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}
function bodyHTML() {
  const s = [];
  if (W.needsDate) s.push(sec('date', T('s_date'), '', dateSec(), true));
  if (has('locations')) s.push(sec('locations', T('s_loc'), cnt('locations'), `<div class="fl-chipset">${accessLocs().map((l) => tog(isOn('locations', l.id), `data-act="fl_t" data-k="locations" data-v="${l.id}"`, nm(l))).join('') || `<span class="muted">${esc(T('none'))}</span>`}</div>`, true));
  if (has('brands')) s.push(sec('brands', T('s_brand'), cnt('brands'), (OPT.brands || []).length ? `<div class="fl-chipset">${OPT.brands.map((b) => tog(isOn('brands', b.brand_code), `data-act="fl_t" data-k="brands" data-v="${esc(b.brand_code)}"`, brandName(b))).join('')}</div>` : `<div class="notice warn mk warn">${esc(T('nobrand'))}</div>`, true));
  if (has('modes')) s.push(sec('modes', T('s_mode'), cnt('modes'), `<div class="fl-chipset">${['cash', 'mobile', 'card', 'due', 'split'].map((m) => tog(isOn('modes', m), `data-act="fl_t" data-k="modes" data-v="${m}"`, modeLabel(m))).join('')}</div>`, false));
  if (has('sale_type')) s.push(sec('sale_type', T('s_type'), W.st.sale_type ? 1 : '', `<div class="fl-chipset">${['retail', 'wholesale'].map((m) => tog(W.st.sale_type === m, `data-act="fl_one" data-k="sale_type" data-v="${m}"`, T('t_' + m))).join('')}</div>`, false));
  if (has('staff')) s.push(sec('staff', T('s_staff'), cnt('staff'), listSec('staff', staffList().map((x) => ({ v: x.staff_id, label: x.full_name || x.staff_id, sub: x.staff_id })), staffList().length > 6), false));
  if (has('categories')) s.push(sec('categories', T('s_cat'), cnt('categories'), `<div class="fl-chipset">${(OPT.cats || []).map((c) => tog(isOn('categories', c.code), `data-act="fl_t" data-k="categories" data-v="${esc(c.code)}"`, CATN[c.code] ? lab(CATN[c.code]) : (c.bn || c.code))).join('') || `<span class="muted">${esc(T('none'))}</span>`}</div>`, false));
  if (has('item_types')) s.push(sec('item_types', T('s_itype'), cnt('item_types'), `<div class="fl-chipset">${(OPT.types || []).map((x) => tog(isOn('item_types', x.code), `data-act="fl_t" data-k="item_types" data-v="${esc(x.code)}"`, S.lang === 'en' ? (x.label_en || x.label_bn) : x.label_bn)).join('') || `<span class="muted">${esc(T('none'))}</span>`}</div>`, true));
  if (has('items')) s.push(sec('items', T('s_item'), cnt('items'), listSec('items', itemList().map((i) => ({ v: i.id, label: nm(i), sub: i.code })), true), false));
  if (has('customer')) s.push(sec('customer', T('s_cust'), cnt('customer'), listSec('customer', (OPT.custs || []).map((c) => ({ v: c.id, label: c.name, sub: c.mobile || '' })), true), false));
  if (has('min_amount')) s.push(sec('amount', T('s_amt'), (W.st.min_amount !== undefined || W.st.max_amount !== undefined) ? 1 : '', `<div class="row"><div style="flex:1"><label for="fl_min">${esc(T('min'))}</label><input id="fl_min" inputmode="decimal" value="${esc(W.st.min_amount ?? '')}"></div>
    <div style="flex:1"><label for="fl_max">${esc(T('max'))}</label><input id="fl_max" inputmode="decimal" value="${esc(W.st.max_amount ?? '')}"></div></div>`, false));
  if (has('status')) s.push(sec('status', T('s_status'), W.st.status ? 1 : '', `<div class="fl-chipset">${['done', 'void'].map((m) => tog(W.st.status === m, `data-act="fl_one" data-k="status" data-v="${m}"`, T('st_' + m))).join('')}</div>`, false));
  if (has('search')) s.push(sec('search', T('s_search'), W.st.search ? 1 : '', `<input id="fl_search" type="search" autocomplete="off" placeholder="${esc(T('searchph'))}" value="${esc(W.st.search || '')}">`, false));
  return s.join('');
}
function paint() {
  openSheet(`<div class="fl-wrap"><h2 style="margin-top:0">${esc(W.title || T('title'))}</h2><div class="fl-body">${bodyHTML()}</div>
    <div class="fl-foot"><button data-act="fl_reset" class="fl-textbtn">${esc(T('reset'))}</button><button data-act="closesheet">${esc(T('cancel'))}</button><button class="primary" data-act="fl_apply">${esc(T('apply'))}</button></div></div>`);
}
async function open(o) {
  await preload(o.allow);
  const needsDate = o.needsDate !== false;
  W = { st: clone(o.state), allow: new Set(o.allow || []), needsDate, onApply: o.onApply, title: o.title };
  if (needsDate && !W.st.preset && !W.st.from && !W.st.to) W.st.preset = DEFAULT_PRESET;
  paint();
}
function syncCounts() {
  document.querySelectorAll('#sheet .fl-cnt').forEach((c) => {
    const k = c.dataset.cnt, v = k === 'amount' ? ((W.st.min_amount !== undefined || W.st.max_amount !== undefined) ? 1 : 0) : k === 'date' ? 0 : Array.isArray(W.st[k]) ? W.st[k].length : (W.st[k] ? 1 : 0);
    c.textContent = v ? String(v) : '';
  });
}
const numOrNone = (v) => { const s = norm(v).trim(); if (s === '') return undefined; const n = Number(s); return Number.isFinite(n) ? n : undefined; };

const H = A.H;
Object.assign(H, {
  fl_t: (a) => {
    if (!W) return; const k = a.dataset.k; let v = a.dataset.v; if (k === 'locations') v = Number(v);
    const arr = W.st[k] || (W.st[k] = []), i = arr.findIndex((x) => String(x) === String(v));
    if (i >= 0) arr.splice(i, 1); else { arr.push(v); if (k === 'customer' || k === 'items') setName(W.st, k, v, a.dataset.name); }
    if (!arr.length) delete W.st[k];
    const on = i < 0; a.classList.toggle('on', on); a.setAttribute('aria-pressed', on ? 'true' : 'false'); syncCounts();
  },
  fl_one: (a) => {
    if (!W) return; const k = a.dataset.k, v = a.dataset.v;
    if (W.st[k] === v) delete W.st[k]; else W.st[k] = v;
    a.parentElement.querySelectorAll('.tog').forEach((b) => { const on = W.st[k] === b.dataset.v; b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); }); syncCounts();
  },
  fl_p: (a) => {
    if (!W) return; W.st.preset = a.dataset.v; delete W.st.from; delete W.st.to;
    const r = presetRange(a.dataset.v); if ($('#fl_from') && r) { $('#fl_from').value = r.from; $('#fl_to').value = r.to; }
    document.querySelectorAll('#fl_presets .tog').forEach((b) => { const on = b.dataset.v === W.st.preset; b.classList.toggle('on', on); b.setAttribute('aria-pressed', on ? 'true' : 'false'); });
  },
  fl_na: (a) => toast(T('need') + ' · ' + a.dataset.v),
  fl_reset: () => { if (!W) return; W.st = defaults(W.needsDate); paint(); },
  fl_apply: () => {
    if (!W) return;
    if (W.st.from && W.st.to && W.st.to < W.st.from) { const x = W.st.from; W.st.from = W.st.to; W.st.to = x; }
    const st = W.st, cb = W.onApply; W = null; closeSheet(); if (cb) cb(st);
  },
  fl_rm: (a) => {
    const h = HOSTS[a.dataset.h]; if (!h) return;
    h.set(removeFrom(clone(h.get()), a.dataset.k, a.dataset.v, h.needsDate !== false));
  },
  fl_clear: (a) => { const h = HOSTS[a.dataset.h]; if (!h) return; h.set(defaults(h.needsDate !== false)); },
});
document.addEventListener('change', (e) => {
  if (!W) return; const id = e.target.id;
  if (id === 'fl_from' || id === 'fl_to') {
    if (W.st.preset && !W.st.from && !W.st.to) { const r = presetRange(W.st.preset); if (r) { W.st.from = r.from; W.st.to = r.to; } }
    if (e.target.value) W.st[id === 'fl_from' ? 'from' : 'to'] = e.target.value; else delete W.st[id === 'fl_from' ? 'from' : 'to'];
    delete W.st.preset; document.querySelectorAll('#fl_presets .tog').forEach((b) => { b.classList.remove('on'); b.setAttribute('aria-pressed', 'false'); });
  } else if (id === 'fl_min' || id === 'fl_max') {
    const n = numOrNone(e.target.value), k = id === 'fl_min' ? 'min_amount' : 'max_amount'; if (n === undefined) delete W.st[k]; else W.st[k] = n; syncCounts();
  } else if (id === 'fl_search') { const v = e.target.value.trim(); if (v) W.st.search = v; else delete W.st.search; syncCounts(); }
});
document.addEventListener('input', (e) => {
  if (!W) return;
  if (e.target.id === 'fl_search') { const v = e.target.value.trim(); if (v) W.st.search = v; else delete W.st.search; syncCounts(); }
  if (e.target.classList && e.target.classList.contains('fl-q')) {
    const q = e.target.value.trim().toLowerCase(), list = document.querySelector(`#sheet [data-list="${e.target.dataset.for}"]`);
    if (list) list.querySelectorAll('.fl-r').forEach((r) => { r.hidden = !!q && !r.dataset.n.includes(q); });
  }
});

// ---------- styles (calm: edge bars and outlines only) ----------
if (!document.getElementById('fl_css')) {
  const st = document.createElement('style'); st.id = 'fl_css';
  st.textContent = `
.fl-chips{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0}
.fl-chip{display:inline-flex;align-items:center;gap:8px;min-height:40px;max-width:100%;padding:0 6px 0 12px;border:1px solid var(--hair);border-radius:20px;background:var(--card);color:var(--ink);font:600 .85rem/1.3 var(--text-font)}
.fl-chip span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:62vw}
.fl-chip b{display:grid;place-items:center;width:28px;height:28px;border-radius:50%;color:var(--muted);font-size:1.1rem}
body[data-ui="calm"] .fl-chip{background:var(--chip-on);border-color:var(--hair);color:var(--ink)}
.fl-clear{min-height:40px;border:0;background:transparent;color:var(--ink-2);text-decoration:underline;font:600 .85rem var(--text-font);padding:0 8px}
.fl-wrap{display:flex;flex-direction:column;min-height:60vh}
.fl-body{flex:1}
.fl-sec{border-bottom:1px solid var(--hair)}
.fl-sec>summary{list-style:none;display:flex;justify-content:space-between;align-items:center;gap:8px;min-height:52px;cursor:pointer;font:700 1rem var(--display)}
.fl-sec>summary::-webkit-details-marker{display:none}
.fl-sec>summary::after{content:"›";font-size:1.4rem;color:var(--muted);transition:transform .16s;margin-inline-start:auto}
.fl-sec[open]>summary::after{transform:rotate(90deg)}
.fl-cnt:not(:empty){display:inline-grid;place-items:center;min-width:24px;height:24px;border-radius:12px;background:var(--chip-on);font:700 .8rem var(--text-font);padding:0 6px}
.fl-b{padding:2px 0 14px}
.fl-b .row>div{min-width:0}.fl-b input[type=date]{min-width:0;padding:0 8px;font-size:.95rem}
.fl-chipset{display:flex;flex-wrap:wrap;gap:8px}
.fl-t{min-width:0}
.fl-t.fl-na{opacity:.6;border-style:dashed;flex-direction:column;gap:0;line-height:1.25;padding:4px 12px}
.fl-t.fl-na small{font:600 .68rem var(--text-font);color:var(--sig-warn)}
.fl-list{max-height:240px;overflow:auto;border:1px solid var(--hair);border-radius:12px;margin-top:8px}
.fl-r{display:flex;align-items:center;gap:10px;width:100%;min-height:48px;border:0;border-bottom:1px solid var(--hair);border-radius:0;background:transparent;text-align:start;padding:6px 12px;color:var(--ink);font:500 .95rem/1.35 var(--text-font)}
.fl-r:last-child{border-bottom:0}
.fl-r[hidden]{display:none}
.fl-r small{color:var(--muted)}
.fl-r .bx{width:20px;height:20px;border:2px solid var(--ink-2);border-radius:5px;flex:none;position:relative}
.fl-r.on .bx{background:var(--ink);border-color:var(--ink)}
.fl-r.on .bx::after{content:"";position:absolute;left:5px;top:1px;width:5px;height:10px;border:solid var(--card);border-width:0 2px 2px 0;transform:rotate(45deg)}
.fl-foot{position:sticky;bottom:-16px;margin:12px -16px -16px;padding:10px 16px calc(10px + env(safe-area-inset-bottom));background:var(--bg);border-top:1px solid var(--hair);display:flex;gap:8px;align-items:center}
.fl-foot .primary{flex:1}
.fl-textbtn{border:0!important;background:transparent!important;text-decoration:underline;padding:0 10px}
`;
  document.head.appendChild(st);
}

B.filters = { open, chips, bind, clean, chipList, summary, activeCount, defaults, loadPresets, preload, presetName, presetRange, shortDate, removeFrom, catLabel, modeLabel, PRESETS, DEFAULT_PRESET, brandName,
  brands: () => OPT.brands || [], T };
})();
