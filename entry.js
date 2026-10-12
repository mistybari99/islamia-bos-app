/* Islamia BOS · form engine: renders a form spec for a phone, computes totals and red/yellow flags,
   runs draft -> submit -> approve, exceptions and release requests. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm, fmt, store } = A;
const $ = (s, el = document) => el.querySelector(s);

// ---------- language helpers ----------
const MIXWORDS = [["রিকনসিলিয়েশন","Reconciliation"],["ইনভয়েস","Invoice"],["রেজিস্টার","Register"],["লেজার","Ledger"],["ভাউচার","Voucher"],["স্লিপ","Slip"],["কার্ড","Card"],["শিট","Sheet"],["ফরম","Form"],["রিপোর্ট","Report"],["ক্যাশ","Cash"],["স্টক","Stock"],["স্টোর","Store"],["ডিসকাউন্ট","Discount"],["রিটার্ন","Return"],["অর্ডার","Order"],["পেমেন্ট","Payment"],["ডিজিটাল","Digital"],["বাজেট","Budget"],["হ্যান্ডওভার","Handover"],["ট্রান্সফার","Transfer"],["চালান","Challan"],["শোরুম","Showroom"],["ডেলিভারি","Delivery"],["অনলাইন","Online"],["সাপ্লায়ার","Supplier"],["পারচেজ","Purchase"],["প্রোডাক্ট","Product"],["কারখানা","Factory"],["অ্যাডভান্স","Advance"],["স্টাফ","Staff"],["ডিউটি","Duty"],["লোকেশন","Location"],["সেটিংস","Settings"],["নোট","Note"],["পার্টি","Party"],["কাউন্টার","Counter"],["রেকর্ড","Record"],["কাউন্ট","Count"],["শিফট","Shift"],["রসিদ","Receipt"],["ইস্যু","Issue"],["মালামাল","Goods"],["অনুমোদনকারী","Approver"],["অনুমোদন","Approval"],["ব্যয়","Expense"],["যাচাই","Check"],["তাপমাত্রা","Temperature"],["সীমা","Limit"],["পার্থক্য","Difference"],["গণনা","Count"],["নগদ","Cash"],["মোট","Total"],["ইমপ্রেস্ট","Imprest"],["টাকা","Taka"],["পরিমাণ","Quantity"],["একক","Unit"],["গ্রেড","Grade"],["সময়","Time"],["তারিখ","Date"],["স্বাক্ষর","Signature"],["চাহিদা","Demand"],["সাক্ষী","Witness"],["কম / বেশি","Short / Over"]];
// Bng-Eng: swap a Bangla word for its everyday English word only at a word edge. If a Bangla ending follows (কাউন্টের),
// join it with a hyphen as an independent letter (Count-এর) so nothing renders as a broken mark. Unknown endings leave the Bangla word alone.
const SUFFIX = { 'ের': '-এর', 'কে': '-কে', 'তে': '-তে', 'এ': '-এ', 'ে': '-এ', 'য়ে': '-এ', 'য়ের': '-এর', 'গুলো': '-গুলো', 'গুলি': '-গুলি', 'টি': '-টি', 'টা': '-টা', 'ও': '-ও' };
const BNL = /[\u0980-\u09FF]/;
const MIXSORTED = [...MIXWORDS].sort((a, z) => z[0].length - a[0].length);
const toMix = (bn0) => {
  const bn = bn0.replace(/\u200c/g, '');
  let out = '', i = 0;
  while (i < bn.length) {
    let hit = null;
    if (!i || !BNL.test(bn[i - 1])) {
      for (const [b, e] of MIXSORTED) {
        if (!bn.startsWith(b, i)) continue;
        let j = i + b.length, k = j;
        while (k < bn.length && BNL.test(bn[k])) k++;
        const suf = bn.slice(j, k);
        if (!suf) { hit = [e, j]; break; }
        if (SUFFIX[suf]) { hit = [e + SUFFIX[suf], k]; break; }
      }
    }
    if (hit) { out += hit[0]; i = hit[1]; } else { out += bn[i]; i++; }
  }
  return out;
};
const lab = (x) => !x ? '' : typeof x === 'string' ? x : S.lang === 'en' ? (x.en || x.bn) : S.lang === 'mix' ? (x.mix || toMix(x.bn || '')) : (x.bn || x.en);
const L = (bn, en, mix) => ({ bn, en, mix });
B.L = L; B.lab = lab;
const num = (v) => { if (v === '' || v === null || v === undefined) return 0; const n = Number(String(v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d))); return Number.isFinite(n) ? n : 0; };
const has = (v) => !(v === undefined || v === null || v === '' || v === false);
const sum = (a) => a.reduce((s, x) => s + num(x), 0);
const money = (n) => '৳ ' + fmt(n);
B.num = num; B.has = has; B.sum = sum;

// ---------- field builders (used by forms.js) ----------
const fld = (type) => (id, label, o = {}) => ({ id, type, label, ...o });
B.f = { T: fld('text'), TA: fld('textarea'), N: fld('number'), M: fld('money'), TM: fld('time'), D: fld('date'), CK: fld('ck'), ST: fld('staff'),
  ITEM: fld('item'), LOC: fld('loc'), DEN: fld('denoms'), PHOTO: fld('photo'), SUP: fld('supplier'),
  CH: (id, label, options, o = {}) => ({ id, type: 'choice', label, options, ...o }),
  SEL: (id, label, options, o = {}) => ({ id, type: 'select', label, options, ...o }),
  CALC: (id, label, fm, o = {}) => ({ id, type: 'calc', label, fmt: fm || 'num', ...o }),
  NOTE: (text, tone, o = {}) => ({ type: 'note', text, tone: tone || 'ok', ...o }),
  TABLE: (id, label, cols, o = {}) => ({ id, type: 'table', label, cols, ...o }) };
B.YN = [['yes', L('হ্যাঁ', 'Yes')], ['no', L('না', 'No')]];

// ---------- settings catalogue (location settings sheet 0-1) ----------
const SD = (key, group, bn, en, kind = 'number', unit = '') => ({ key, group, label: L(bn, en), kind, unit });
B.SETTING_DEFS = [
  SD('drawer_float', 'A', 'বিক্রয় ড্রয়ারের স্থায়ী খুচরা টাকা', 'Fixed change float in the sales drawer', 'number', '৳'),
  SD('imprest', 'A', 'ইমপ্রেস্ট (খরচের বাক্স) — নির্ধারিত টাকা', 'Imprest (petty cash) fixed amount', 'number', '৳'),
  SD('expense_max', 'A', 'এককালীন খরচের সর্বোচ্চ সীমা (এর উপরে অনুমোদন)', 'Single expense limit (approval needed above)', 'number', '৳'),
  SD('cash_tol', 'A', 'ক্যাশ গরমিলের গ্রহণযোগ্য সীমা', 'Acceptable cash short/over', 'number', '৳'),
  SD('goods_money_tol_pct', 'A', 'মালামাল বনাম টাকার গ্রহণযোগ্য পার্থক্য (%)', 'Acceptable goods-vs-money gap (%)', 'number', '%'),
  SD('goods_money_tol_max', 'A', 'মালামাল বনাম টাকার সর্বোচ্চ পার্থক্য (৳)', 'Acceptable goods-vs-money gap (max ৳)', 'number', '৳'),
  SD('big_sale', 'A', 'বড় একক বিক্রির সীমা', 'Large single sale threshold', 'number', '৳'),
  SD('avg_daily_sales', 'A', 'দৈনিক গড় বিক্রি (রেফারেন্স)', 'Average daily sales (reference)', 'number', '৳'),
  SD('discount_limit', 'A', 'ডিসকাউন্টের সীমা (এর উপরে অনুমোদন)', 'Discount limit (approval needed above)', 'number', '৳'),
  SD('refund_limit', 'A', 'টাকা ফেরতের সীমা (এর উপরে অনুমোদন)', 'Refund limit (approval needed above)', 'number', '৳'),
  SD('hub_cash_max', 'A', 'হাব — ক্যাশ বাক্সে সর্বোচ্চ নগদ', 'Hub: maximum cash in the box', 'number', '৳'),
  SD('hub_min_cash', 'A', 'হাব — সুরক্ষিত ন্যূনতম নগদ', 'Hub: protected minimum cash', 'number', '৳'),
  SD('order_hold_days', 'A', 'অর্ডারের পণ্য কত দিন রাখা হবে', 'Days an uncollected order is held', 'number', 'দিন'),
  SD('unclaimed_days', 'A', 'কত দিন পর অদাবিকৃত অ্যাডভান্স ব্যবসার আয়ে যাবে', 'Days before unclaimed advance becomes income', 'number', 'দিন'),
  SD('open_time', 'B', 'শোরুম খোলার সময়', 'Showroom opening time', 'time'),
  SD('close_time', 'B', 'শোরুম বন্ধের সময়', 'Showroom closing time', 'time'),
  SD('busy_day_def', 'B', 'ব্যস্ত দিনের সংজ্ঞা', 'What counts as a busy day', 'text'),
  SD('handover_point', 'B', 'মালামাল হ্যান্ডওভারের নির্দিষ্ট জায়গা', 'Fixed goods handover point', 'text'),
  SD('crates', 'B', 'ক্যারেটের মোট সংখ্যা', 'Total crates', 'number'),
  SD('trays', 'B', 'ট্রের মোট সংখ্যা', 'Total trays', 'number'),
  SD('fridge1_name', 'C', 'ফ্রিজ/চিলার ১ — নাম', 'Fridge/chiller 1 — name', 'text'), SD('fridge1_min', 'C', 'ফ্রিজ ১ — সর্বনিম্ন °C', 'Fridge 1 — min °C', 'number', '°C'), SD('fridge1_max', 'C', 'ফ্রিজ ১ — সর্বোচ্চ °C', 'Fridge 1 — max °C', 'number', '°C'),
  SD('fridge2_name', 'C', 'ফ্রিজ/চিলার ২ — নাম', 'Fridge/chiller 2 — name', 'text'), SD('fridge2_min', 'C', 'ফ্রিজ ২ — সর্বনিম্ন °C', 'Fridge 2 — min °C', 'number', '°C'), SD('fridge2_max', 'C', 'ফ্রিজ ২ — সর্বোচ্চ °C', 'Fridge 2 — max °C', 'number', '°C'),
  SD('fridge3_name', 'C', 'ফ্রিজ/চিলার ৩ — নাম', 'Fridge/chiller 3 — name', 'text'), SD('fridge3_min', 'C', 'ফ্রিজ ৩ — সর্বনিম্ন °C', 'Fridge 3 — min °C', 'number', '°C'), SD('fridge3_max', 'C', 'ফ্রিজ ৩ — সর্বোচ্চ °C', 'Fridge 3 — max °C', 'number', '°C'),
  SD('shelf_sweet', 'C', 'মিষ্টি কত দিন বিক্রয়যোগ্য', 'Sweets shelf life (days)', 'number', 'দিন'), SD('shelf_cake', 'C', 'কেক কত দিন বিক্রয়যোগ্য', 'Cake shelf life (days)', 'number', 'দিন'),
  SD('shelf_doi', 'C', 'দই কত দিন বিক্রয়যোগ্য', 'Curd shelf life (days)', 'number', 'দিন'), SD('shelf_bakery', 'C', 'বেকারি কত দিন বিক্রয়যোগ্য', 'Bakery shelf life (days)', 'number', 'দিন'),
  ...['রবি:Sun', 'সোম:Mon', 'মঙ্গল:Tue', 'বুধ:Wed', 'বৃহঃ:Thu', 'শুক্র:Fri', 'শনি:Sat'].map((x, i) => SD('daytag_' + i, 'C', 'দিন-ট্যাগের রং — ' + x.split(':')[0], 'Day-tag colour — ' + x.split(':')[1], 'text')),
  SD('waste_classes', 'C', 'নষ্ট মালামালের শ্রেণি (কারণগুলো)', 'Waste classes (reasons)', 'text'),
  SD('count_tol_pct', 'F', 'গোডাউন/স্টোর কাউন্টের গ্রহণযোগ্য পার্থক্য (%)', 'Acceptable stock count variance (%)', 'number', '%'),
  SD('count_tol_max', 'F', 'গোডাউন/স্টোর কাউন্টের সর্বোচ্চ পার্থক্য (৳)', 'Acceptable stock count variance (max ৳)', 'number', '৳'),
  SD('quote_over', 'F', 'কোটেশন তুলনা বাধ্যতামূলক — এর উপরে', 'Quotation comparison required above', 'number', '৳'),
];
B.GROUPS = { A: L('টাকা ও সীমা', 'Cash & limits'), B: L('সময় ও জায়গা', 'Time & place'), C: L('পণ্য ও সংরক্ষণ', 'Products & storage'), F: L('ক্রয় ও কাউন্ট', 'Purchase & count') };

// ---------- environment (settings, items, staff, locations) ----------
const ENV = { staff: null, items: null, locs: null, byLoc: {}, lists: null, rules: null, grantDefs: null, sup: null, supManage: false };
async function loadStatic() {
  if (!ENV.staff) { const r = await sb.rpc('staff_directory'); ENV.staff = r.data || []; }
  if (!ENV.items) { const r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,sell_price,is_active').order('code')); ENV.items = r.data || []; ENV.byCode = new Map(ENV.items.map((i) => [i.code, i])); }
  if (!ENV.locs) { const r = await sb.from('locations').select('*').order('sort'); ENV.locs = r.data || []; }
  if (!ENV.lists) await loadLists();
  if (!ENV.rules) await loadRules();
  if (!ENV.sup) await loadSuppliers();
}
// supplier picker (forms): active suppliers by name only (supplier_pick); unknown function or no table = empty list, free text still works
async function loadSuppliers() {
  ENV.sup = []; ENV.supManage = false;
  try { const r = await sb.rpc('supplier_pick'); ENV.sup = !r.error && Array.isArray(r.data) ? r.data : []; } catch (e) { /* free text only */ }
  try { const g = await sb.rpc('has_grant', { p_code: 'supplier_manage' }); ENV.supManage = !!(S.ctx.is_owner || (g && !g.error && g.data === true)); } catch (e) { ENV.supManage = !!S.ctx.is_owner; }
}
B.reloadSuppliers = async () => { ENV.sup = null; await loadSuppliers(); };
// business rules (Rules page): the server enforces them; the app reads them only to guide the screen
async function loadRules() {
  const [r, g] = await Promise.all([sb.from('rules').select('*').order('sort'), sb.from('grant_defs').select('*').order('sort')]);
  ENV.rules = {}; (r.error ? [] : r.data || []).forEach((x) => { ENV.rules[x.key] = x; }); ENV.grantDefs = {}; (g.error ? [] : g.data || []).forEach((x) => { ENV.grantDefs[x.grant_code] = x; });
}
B.rule = (key, fallback) => { const r = ENV.rules && ENV.rules[key]; if (!r) return fallback; const v = r.value !== null && r.value !== undefined ? r.value : r.default_value; return v === null || v === undefined ? fallback : v; };
B.reloadRules = async () => { ENV.rules = null; await loadRules(); };
B.grantDefs = () => ENV.grantDefs || {};
// editable option lists (expense heads, marketing heads, wallets ...): the owner edits them, forms read them; the code keeps a fallback
async function loadLists() {
  const r = await sb.from('option_lists').select('*').order('sort');
  ENV.lists = {}; (r.error ? [] : r.data || []).forEach((x) => { (ENV.lists[x.list_code] = ENV.lists[x.list_code] || []).push(x); });
}
const rowL = (r) => ({ bn: r.label_bn, mix: r.label_mix || undefined, en: r.label_en || undefined });
B.opts = (code, fallback) => () => { const rows = ENV.lists && ENV.lists[code]; return rows && rows.length ? rows.filter((r) => r.active).map((r) => [r.value_code, rowL(r)]) : fallback; };
B.optExtra = (code, value) => { const r = ((ENV.lists && ENV.lists[code]) || []).find((x) => x.value_code === value); return r ? r.extra || {} : null; };
B.reloadLists = async () => { ENV.lists = null; await loadLists(); };
async function locSettings(loc, fresh) {
  if (!fresh && ENV.byLoc[loc]) return ENV.byLoc[loc];
  const r = await sb.from('location_settings').select('key,value').eq('location_id', loc);
  const m = {}; (r.data || []).forEach((x) => { m[x.key] = x.value; }); ENV.byLoc[loc] = m; return m;
}
const myLocs = () => (S.ctx.is_owner || S.ctx.roles.includes('management') ? ENV.locs : ENV.locs.filter((l) => S.ctx.locations.includes(l.id)));
const locName = (id) => nm(ENV.locs.find((l) => l.id === Number(id)));
const staffName = (sid) => { const s = ENV.staff.find((x) => x.staff_id === sid); return s ? (s.full_name || s.staff_id) : (sid || ''); };
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const weekday = (d) => new Date(d + 'T12:00:00').getDay();
const WD = [L('রবিবার', 'Sunday'), L('সোমবার', 'Monday'), L('মঙ্গলবার', 'Tuesday'), L('বুধবার', 'Wednesday'), L('বৃহস্পতিবার', 'Thursday'), L('শুক্রবার', 'Friday'), L('শনিবার', 'Saturday')];

// ---------- path helpers ----------
const getp = (o, p) => p.split('.').reduce((a, k) => (a === undefined || a === null ? undefined : a[k]), o);
const setp = (o, p, v) => { const ks = p.split('.'); let c = o; ks.forEach((k, i) => { if (i === ks.length - 1) c[k] = v; else { if (c[k] === undefined || c[k] === null) c[k] = /^\d+$/.test(ks[i + 1]) ? [] : {}; c = c[k]; } }); };
const DENOMS = [1000, 500, 200, 100, 50, 20, 10, 5, 2, 1];
const denTotal = (o) => (o ? DENOMS.reduce((s, d) => s + d * num(o['n' + d]), 0) + num(o.coin) : 0);

// ---------- editor state ----------
let E = null;
const FIELD_ID = (() => { let n = 0; return () => 'x' + (n++); })();

function ctxFor() {
  return { d: E.data, c: E.check, s: E.settings, env: ENV, v: (E.calc && E.calc.v) || {}, cf: !!E.formRow.count_first, num, has, sum, pin: !!(E.pin && E.pin.on), den: (k) => denTotal(getp(E.data, k)), denC: (k) => denTotal(getp(E.check, k)),
    rows: (id) => (E.data[id] || []).map((r) => r || {}), rowsC: (id) => (E.check[id] || []).map((r) => r || {}), me: S.ctx.profile.staff_id, date: E.date, loc: E.loc, wd: weekday(E.date),
    L, lab, money, needs: [] };
}
function recompute() {
  const x = ctxFor(); const out = E.spec.calc ? E.spec.calc(x) : {};
  E.calc = { v: out.v || {}, rows: out.rows || {}, flags: out.flags || [], needs: [...new Set([...(out.needs || [])])] };
  blindMask();
}
function flagsOf(src) { return E.calc.flags.filter((f) => (src === 'check' ? f.src === 'check' : f.src !== 'check')); }

// ---------- rendering ----------
const isEd = () => E.mode === 'edit' || E.mode === 'change';    // 'change' = a locked entry opened to ask for a change (W5)
const modeEditable = (fd) => !(E.blind && E.blind.saved && fd.id === BLIND_FIELD[E.code]) && (isEd() && (fd.who || 'maker') === 'maker') || (E.mode === 'check' && fd.who === 'checker');
const curVal = (fd, path, w) => getp(w === 'c' ? E.check : E.data, path);
const optsOf = (fd) => (typeof fd.options === 'function' ? fd.options() : fd.options);
function optsHTML(options, cur, code) { if (cur && String(cur).startsWith('other:') && !options.some((o) => o[0] === cur)) options = [...options, [cur, { bn: 'অন্যান্য: ' + String(cur).slice(6), en: 'Other: ' + String(cur).slice(6) }]]; if (cur && code && !options.some((o) => o[0] === cur)) { const old = ((ENV.lists && ENV.lists[code]) || []).find((x) => x.value_code === cur); if (old) options = [...options, [old.value_code, rowL(old)]]; } return options.map(([v, l]) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(lab(l))}</option>`).join(''); }

const SUPX = { ph: L('সাপ্লায়ার বাছুন বা লিখুন', 'Pick or type a supplier', 'Supplier বাছুন বা লিখুন'), add: L('নতুন সাপ্লায়ার', 'New supplier', 'নতুন Supplier'),
  listed: L('তালিকার সাপ্লায়ার ✓', 'Listed supplier ✓', 'তালিকার Supplier ✓'), free: L('তালিকায় নেই — লেখা নামই থাকবে', 'Not in the list — the typed name is kept', 'তালিকায় নেই — typed নামই থাকবে'),
  title: L('নতুন সাপ্লায়ার', 'New supplier', 'নতুন Supplier'), name: L('নাম', 'Name', 'নাম'), mobile: L('মোবাইল (ঐচ্ছিক)', 'Mobile (optional)', 'Mobile (ঐচ্ছিক)'), save: L('সংরক্ষণ', 'Save', 'Save'), need: L('নাম লিখুন', 'Enter the name', 'নাম লিখুন') };
function inputHTML(fd, path, w, ed) {
  const val = curVal(fd, path, w), a = `data-w="${w}" data-p="${esc(path)}" ${ed ? '' : 'disabled'}`;
  switch (fd.type) {
    case 'text': return `<input ${a} value="${esc(val)}" autocomplete="off">`;
    case 'textarea': return `<textarea ${a} rows="2">${esc(val)}</textarea>`;
    case 'number': case 'money': return `<div class="numwrap">${fd.type === 'money' ? '<span>৳</span>' : ''}<input ${a} data-num="1" inputmode="decimal" value="${esc(val)}" autocomplete="off"></div>`;
    case 'time': return `<input type="time" ${a} value="${esc(val)}">`;
    case 'date': return `<input type="date" ${a} value="${esc(val)}">`;
    case 'ck': return `<label class="ckrow"><input type="checkbox" ${a} ${val ? 'checked' : ''}><span>${esc(lab(fd.label))}${fd.req ? ' <b class="req">*</b>' : ''}</span></label>`;
    case 'choice': return `<div class="row wrap">${optsOf(fd).map(([v, l]) => `<button type="button" class="tog ${val === v ? 'on' : ''}" ${ed ? '' : 'disabled'} data-act="pick" ${a} data-v="${esc(v)}">${esc(lab(l))}</button>`).join('')}</div>`;
    case 'select': return `<select ${a}><option value=""></option>${optsHTML(optsOf(fd), val, fd.list)}</select>`;
    case 'staff': return `<select ${a}><option value=""></option>${ENV.staff.map((s) => `<option value="${esc(s.staff_id)}" ${s.staff_id === val ? 'selected' : ''}>${esc(s.full_name || s.staff_id)} · ${esc(s.staff_id)}</option>`).join('')}</select>`;
    case 'loc': return `<select ${a}><option value=""></option>${ENV.locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(val) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}<option value="other" ${val === 'other' ? 'selected' : ''}>${esc(t('other'))}</option></select>`;
    case 'item': { const it = ENV.byCode && ENV.byCode.get(val); return `<input ${a} data-item="1" list="dl_items" placeholder="${esc(t('item_pick'))}" value="${esc(it ? it.code + ' · ' + nm(it) : (val || ''))}" autocomplete="off">`; }
    case 'supplier': { const sid = getp(w === 'c' ? E.check : E.data, path + '_id'); const known = sid && ENV.sup.some((x) => x.id === sid);
      return `<div class="supwrap"><input ${a} data-sup="1" list="dl_sup" placeholder="${esc(lab(SUPX.ph))}" value="${esc(val)}" autocomplete="off">${ed && ENV.supManage ? `<button type="button" class="mini supnew" data-act="sup_new" data-w="${w}" data-p="${esc(path)}" aria-label="${esc(lab(SUPX.add))}">＋</button>` : ''}</div><div class="hint">${val ? esc(lab(known ? SUPX.listed : SUPX.free)) : ''}</div>`; }
    case 'denoms': return `<div class="den">${DENOMS.map((d) => `<label><span>${d}</span><input data-w="${w}" data-p="${esc(path)}.n${d}" data-num="1" inputmode="numeric" ${ed ? '' : 'disabled'} value="${esc(getp(w === 'c' ? E.check : E.data, path + '.n' + d))}"></label>`).join('')}
      <label><span>${esc(t('coins'))} ৳</span><input data-w="${w}" data-p="${esc(path)}.coin" data-num="1" inputmode="decimal" ${ed ? '' : 'disabled'} value="${esc(getp(w === 'c' ? E.check : E.data, path + '.coin'))}"></label></div>`;
    case 'photo': { const arr = Array.isArray(val) ? val : [];
      return `<div class="photos">${arr.map((p, i) => `<span class="ph"><img data-path="${esc(p)}" alt="" data-act="photo_view" data-src="${esc(p)}">${ed ? `<button type="button" class="mini" data-act="photo_del" data-w="${w}" data-p="${esc(path)}" data-i="${i}" aria-label="${esc(t('delete_row'))}">✕</button>` : ''}</span>`).join('')}
        ${ed ? `<label class="phadd">📷 ${esc(t('photo_add'))}<input type="file" accept="image/*" capture="environment" hidden data-photo="1" data-w="${w}" data-p="${esc(path)}"></label>` : (arr.length ? '' : '<span class="muted">—</span>')}</div>`; }
    default: return '';
  }
}
function calcHTML(fd, key) { return `<div class="calc ${fd.big ? 'big' : ''}" data-calc="${esc(key)}" data-fmt="${fd.fmt}">—</div>`; }

function fieldHTML(fd, path, w, ed, wrapAttrs = '') {
  if (fd.type === 'note') return `<div class="notice ${fd.tone}" ${wrapAttrs}>${esc(lab(fd.text))}</div>`;
  if (fd.type === 'table') return tableHTML(fd, wrapAttrs);
  const key = fd.type === 'calc' ? path : null;
  const labelHTML = fd.type === 'ck' || !fd.label ? '' : `<label>${esc(lab(fd.label))}${fd.req ? ' <b class="req">*</b>' : ''}</label>`;
  const hint = fd.hint ? `<div class="hint">${esc(lab(fd.hint))}</div>` : '';
  return `<div class="fld ${fd.type === 'calc' ? 'calcf' : ''}" ${wrapAttrs}>${labelHTML}${fd.type === 'calc' ? calcHTML(fd, key) : inputHTML(fd, path, w, ed)}${hint}</div>`;
}
function wrap(fd, ed) { const id = FIELD_ID(); if (fd.show) E.shows[id] = fd.show; return `data-sid="${id}"`; }

function tableHTML(fd, wrapAttrs) {
  const w = (fd.cols.some((c) => c.who === 'checker') && !fd.cols.some((c) => !c.who || c.who === 'maker')) ? 'c' : 'd';
  const n = fd.rows ? fd.rows.length : Math.max((E.data[fd.id] || []).length, fd.min || 1, (E.check[fd.id] || []).length);
  const canEditStruct = isEd() && !fd.rows;
  let h = `<div class="tbl" ${wrapAttrs}>${fd.label ? `<label>${esc(lab(fd.label))}</label>` : ''}`;
  for (let i = 0; i < n; i++) {
    h += `<div class="rowcard"><div class="rc-h"><b>${fd.rows ? esc(lab(fd.rows[i])) : (i + 1)}</b>${canEditStruct && n > (fd.min || 1) ? `<button type="button" class="mini" data-act="delrow" data-t="${fd.id}" data-i="${i}" aria-label="${esc(t('delete_row'))}">✕</button>` : ''}</div><div class="rc-g">`;
    fd.cols.forEach((c) => {
      const cw = c.who === 'checker' ? 'c' : 'd', ed = modeEditable(c);
      const cid = FIELD_ID(); if (c.show) E.rshows[cid] = [c.show, fd.id, i];
      const path = `${fd.id}.${i}.${c.id}`;
      h += c.type === 'calc' ? `<div class="fld calcf" data-rsid="${cid}"><label>${esc(lab(c.label))}</label>${calcHTML(c, `rows.${fd.id}.${i}.${c.id}`)}</div>`
        : `<div class="fld ${c.wide ? 'wide' : ''}" data-rsid="${cid}">${c.type === 'ck' ? '' : `<label>${esc(lab(c.label))}${c.req ? ' <b class="req">*</b>' : ''}</label>`}${inputHTML(c, path, cw, ed)}</div>`;
    });
    h += '</div></div>';
  }
  if (canEditStruct && (!fd.max || n < fd.max)) h += `<button type="button" class="full" data-act="addrow" data-t="${fd.id}">＋ ${esc(t('add_row'))}</button>`;
  return h + '</div>';
}

function sectionHTML(sec, idx) {
  const ed = (f) => modeEditable(f);
  const sid = FIELD_ID(); if (sec.show) E.shows[sid] = sec.show;
  const checker = sec.who === 'checker';
  if (blindPending() && E.code === '10-1' && !checker) return `<section class="card panel sec" data-sid="${sid}"><h3>${esc(lab(sec.title))}</h3><div class="notice warn" id="blind_hidden">${esc(lab(X18.hub_hidden))}</div></section>`;
  const inner = sec.fields.map((f) => fieldHTML(f, f.id, f.who === 'checker' ? 'c' : 'd', ed(f), wrap(f))).join('');
  const body = `<div class="secbody">${inner}${blindBoxHTML(sec)}</div>`;
  return `<section class="card panel sec ${checker ? 'checker' : ''}" data-sid="${sid}">
    ${sec.collapsed ? `<details ${E.openSecs.has(idx) ? 'open' : ''} data-sec="${idx}"><summary>${esc(lab(sec.title))}</summary>${body}</details>`
      : `<h3>${esc(lab(sec.title))}${checker ? ` <span class="chip warn">${esc(t('checker_part'))}</span>` : ''}</h3>${body}`}</section>`;
}

function flagsHTML() {
  const fl = E.calc.flags; if (!fl.length && !E.calc.needs.length) return '';
  const rel = E.releases || {};
  const items = fl.map((f) => {
    const r = rel[f.code]; const st = f.level === 'red' ? (r ? `<span class="chip ${r.status === 'approved' ? 'ok' : r.status === 'rejected' ? 'bad' : 'warn'}">${esc(t('rel_' + r.status))}</span>` : '') : '';
    return `<div class="flag ${f.level}"><b>${f.level === 'red' ? '●' : '▲'}</b> <span>${esc(lab(f.text))}${f.amount !== undefined && f.amount !== null && f.amount !== '' ? ' · ' + esc(f.unit === 'qty' ? fmt(f.amount) : money(f.amount)) : ''}</span> ${st}</div>`; }).join('');
  const needs = E.calc.needs.length ? `<div class="notice warn">${esc(t('need_settings'))}: ${E.calc.needs.map((k) => esc(lab((B.SETTING_DEFS.find((d) => d.key === k) || {}).label || k))).join(' · ')}${S.ctx.is_owner ? ` · <a href="#/locset">${esc(t('locset'))}</a>` : ''}</div>` : '';
  return `${needs}<div class="flags">${items}</div>`;
}

const STATUS_CLS = { draft: '', submitted: 'warn', approved: 'ok', rejected: 'bad' };
function actionsHTML() {
  const b = []; const canMaker = E.mode === 'edit', st = E.status;
  if (E.mode === 'change') return `<div class="actionbar"><button data-act="e_chg_cancel">${esc(t('cancel'))}</button><button class="primary" data-act="e_chg_send">${esc(lab(X17.chg_send))}</button></div>`;
  if (canMaker) b.push(`<button data-act="e_save">${esc(t('save_draft'))}</button><button class="primary" data-act="e_submit">${esc(t('submit'))}</button>`);
  if (E.mode === 'check') b.push(`<button class="danger" data-act="e_reject">${esc(t('reject'))}</button><button class="primary" data-act="e_approve">${esc(t('approve'))}</button>`);
  if (E.id && st !== 'draft' && (E.created_by === S.ctx.profile.id || S.ctx.is_owner) && !(st === 'approved' && !S.ctx.is_owner)) b.push(`<button data-act="e_reopen">${esc(t('reopen'))}</button>`);
  return b.length ? `<div class="actionbar">${b.join('')}</div>` : '';
}

const PAPER_NO = { id: 'paper_no', type: 'text', label: L('ছাপা নম্বর (কাগজের বই)', 'Printed paper no.', 'ছাপা Number (কাগজের বই)'),
  hint: L('কাগজের ফর্মে ছাপা ক্রমিক নম্বর। একই নম্বর একবারই নেওয়া যায়, আর বাদ পড়া নম্বর ধরা পড়ে।', 'The serial printed on the paper form. A number can be entered once, and missing numbers are audited.', 'কাগজের form এ ছাপা Serial number। একই number একবারই নেওয়া যায়, বাদ পড়া number ধরা পড়ে।') };

// ---------- W5: entered later from paper · rollout chips · change requests · form offline queue (supabase/phase17.sql) ----------
const X17 = {
  later_on: L('কাগজ থেকে পরে তোলা হচ্ছে', 'Entered later from paper', 'কাগজ থেকে পরে তোলা (Entered later)'),
  later_ps: L('কাগজের ছাপা নম্বর (আবশ্যক)', 'Paper serial (required)', 'কাগজের ছাপা Number (আবশ্যক)'),
  later_at: L('কাগজে লেখার আসল তারিখ ও সময় (আবশ্যক)', 'Original date and time on the paper (required)', 'কাগজে লেখার আসল Date ও Time (আবশ্যক)'),
  later_hint: L('বাইরে কাজ করে কাগজে লিখেছিলেন? এখানে তুলুন — কাগজের নম্বর অ্যাপের নম্বর থেকে আলাদা, আর অনুমোদনে যাবে।', 'Worked outside and filled the paper? Enter it here — the paper number is separate from the app number and it goes to approval.', 'বাইরে কাজ করে paper-এ লিখেছিলেন? এখানে তুলুন — paper number app number থেকে আলাদা, approval-এ যাবে।'),
  chip_later: L('পরে তোলা (কাগজ)', 'Entered later (paper)', 'পরে তোলা (Paper)'), chip_notsent: L('এখনও পাঠানো হয়নি', 'Not sent yet', 'এখনও পাঠানো হয়নি'),
  chip_paper: L('কাগজ', 'Paper', 'Paper'), chip_parallel: L('পাশাপাশি', 'Parallel', 'Parallel'), chip_rev: L('সংস্করণ', 'Rev', 'Rev'), chip_chg: L('বদলের অনুরোধ অপেক্ষায়', 'Change requested', 'Change request অপেক্ষায়'),
  banner_parallel: L('এই মাসে কাগজই আসল রেকর্ড — অ্যাপের এন্ট্রি পাশাপাশি মিলিয়ে দেখার জন্য', 'Paper is the record this month — the app entry runs beside it', 'এই মাসে paper-ই record — app entry পাশাপাশি'),
  banner_paper: L('এই ফর্ম এখানে কাগজে চলছে — নতুন এন্ট্রি শুধু “কাগজ থেকে পরে তোলা” হিসেবে', 'This form is on paper here — new entries only as “entered later from paper”', 'এই form এখানে paper-এ — নতুন entry শুধু “paper থেকে পরে তোলা”'),
  need_later: L('কাগজের নম্বর ও আসল সময় দিন', 'Enter the paper serial and the original time', 'Paper number ও আসল time দিন'),
  queued: L('নেট নেই — এই ফোনে রাখা আছে (এখনও পাঠানো হয়নি), নেট এলে নিজে থেকে যাবে', 'No network — kept on this phone (Not sent yet), it will be sent automatically', 'Net নেই — এই phone-এ আছে (Not sent yet), net এলে নিজে যাবে'),
  queue_fail_t: L('ফোনে রাখা গেল না', 'Could not keep it on this phone', 'Phone-এ রাখা গেল না'),
  queue_fail: L('নেট নেই আর ফোনের মেমরিতেও লেখা গেল না (জায়গা নেই বা প্রাইভেট মোড)। এন্ট্রি এই পাতায় আছে — পাতা বন্ধ করবেন না; নেট এলে আবার “সংরক্ষণ” চাপুন, না হলে সংখ্যাগুলো কাগজে লিখে রাখুন।', 'No network, and this phone would not store it either (storage full or private mode). The entry is still on this page — do not close it; press Save again when you are online, or write the figures down on paper.', 'Net নেই, phone-এও save করা গেল না (storage full বা private mode)। Entry এই page-এ আছে — page বন্ধ করবেন না; online হলে আবার Save চাপুন, না হলে কাগজে লিখে রাখুন।'),
  queued_submit: L('জমা দেওয়ার অনুরোধ ফোনে রাখা আছে — নেট এলে যাবে', 'Submit kept on this phone — it goes when you are online', 'Submit phone-এ আছে — online হলে যাবে'),
  sent_ok: L('পাঠানো হয়েছে', 'Sent', 'পাঠানো হয়েছে'),
  menu_title: L('এই এন্ট্রি', 'This entry', 'এই Entry'), m_chg: L('বদলের অনুরোধ', 'Request change', 'Change request'), m_rev: L('সংস্করণের ইতিহাস', 'Revision history', 'Revision history'), m_reopen: L('আবার খুলুন (মালিক)', 'Reopen (owner)', 'আবার খুলুন (Owner)'), m_outbox: L('ফোনে জমা (পাঠানো হয়নি)', 'Waiting on this phone', 'Phone-এ জমা'),
  chg_send: L('বদলের অনুরোধ পাঠান', 'Send change request', 'Change request পাঠান'), chg_why: L('কেন বদলাতে চান?', 'Why do you want the change?', 'কেন বদলাতে চান?'), chg_sent: L('অনুরোধ পাঠানো হয়েছে — অনুমোদন পেলে নতুন সংস্করণ হবে', 'Request sent — approval makes a new revision', 'Request গেছে — approve হলে নতুন revision'),
  chg_hint: L('অনুমোদিত এন্ট্রি বদলানো যায় না। যা বদলাতে চান লিখুন, তারপর অনুরোধ পাঠান; মালিক বা অনুমতিপ্রাপ্ত কেউ অনুমোদন করলে পুরনোটা সংস্করণ হিসেবে থাকবে।', 'An approved entry cannot be edited. Change what is wrong, then send the request; when the owner or a delegate approves, the old version stays as a revision.', 'Approved entry বদলানো যায় না। যা বদলাতে চান লিখুন, request পাঠান; approve হলে পুরনোটা revision হিসেবে থাকবে।'),
  e_rollout_paper: L('এই ফর্ম এখানে কাগজে চলছে — “কাগজ থেকে পরে তোলা” দিয়ে তুলুন', 'This form is on paper here — use “entered later from paper”', 'এই form এখানে paper-এ — “paper থেকে পরে তোলা” দিয়ে তুলুন'),
  e_paper_serial_in_use: L('এই কাগজের নম্বর আগেই নেওয়া হয়েছে', 'This paper serial was already entered', 'এই paper number আগেই নেওয়া হয়েছে'), e_paper_serial_required: L('কাগজের নম্বর লাগবে', 'The paper serial is required', 'Paper number লাগবে'),
  e_paper_time_required: L('আসল সময় লাগবে', 'The original time is required', 'আসল time লাগবে'), e_paper_time_future: L('আসল সময় ভবিষ্যতের হতে পারে না', 'The original time cannot be in the future', 'আসল time future-এর হতে পারে না'),
  e_entered_later_off: L('“পরে তোলা” এখন বন্ধ আছে', '“Entered later” is switched off', '“পরে তোলা” এখন off'), e_change_pending: L('এই এন্ট্রির একটি অনুরোধ আগেই অপেক্ষায় আছে', 'A change request is already waiting for this entry', 'এই entry-র একটি request আগেই আছে'),
  e_change_requests_off: L('বদলের অনুরোধ এখন বন্ধ আছে', 'Change requests are switched off', 'Change request এখন off'), e_stale_request: L('এন্ট্রি এর মধ্যে বদলে গেছে — নতুন অনুরোধ করুন', 'The entry changed meanwhile — ask again', 'Entry বদলে গেছে — নতুন request করুন'),
  e_self_approval: L('নিজের অনুরোধ নিজে অনুমোদন করা যায় না', 'You cannot approve your own request', 'নিজের request নিজে approve করা যায় না'), e_not_locked: L('অনুমোদিত এন্ট্রির জন্য শুধু', 'Only for approved entries', 'শুধু approved entry-র জন্য'),
  e_entered_later_too_old: L('কাগজের তারিখ সীমার চেয়ে পুরনো — শুধু মালিক তুলতে পারবেন', 'The paper date is older than the limit - only the owner may enter it', 'Paper-এর date limit-এর চেয়ে পুরনো — শুধু owner তুলতে পারবেন'),
  e_client_id_mismatch: L('এই পাঠানোর আইডি অন্য ফর্মের', 'That send id belongs to another form', 'এই send id অন্য form-এর'),
  e_client_id_in_use: L('এই পাঠানোর আইডি অন্যের', 'That send id belongs to someone else', 'এই send id অন্যের'),
};
const t17 = (k) => lab(X17[k]);
const err17 = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X17).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? t17(k) : null; };
const fail17 = (e) => { const m = err17(e); if (m) return toast(m); return fail(e); };
B.X17 = X17;
// Bangladesh time (no daylight saving): the original paper time is typed as Dhaka local time
const dhakaNow = () => new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Dhaka' }).replace(' ', 'T').slice(0, 16);
const toDhaka = (iso) => (iso ? new Date(iso).toLocaleString('sv-SE', { timeZone: 'Asia/Dhaka' }).replace(' ', 'T').slice(0, 16) : '');
const laterOn = () => B.rule('entered_later_on', true) !== false;
const metaOf = () => {
  const m = {};
  if (E.cid && !E.id) m.client_id = E.cid;
  if (E.later) { m.entered_later = true; m.paper_serial = String(E.ps || '').trim(); m.paper_at = E.pat ? E.pat + ':00+06:00' : ''; }
  else if (E.hadLater) m.entered_later = false;
  return Object.keys(m).length ? m : null;
};
const laterOk = () => !E.later || (String(E.ps || '').trim() && E.pat);

// --- the form offline queue (rule 12): a record that cannot be sent waits here, shows Not sent yet, is retried on 'online' and at start. Discard is local only.
const uidQ = () => (S.ctx && S.ctx.profile ? S.ctx.profile.id : 'anon');
const QK = () => 'bos_eq_' + uidQ();
const qlist = () => { try { const v = JSON.parse(store.get(QK()) || '[]'); return Array.isArray(v) ? v : []; } catch (e) { return []; } };
const qsave = (a) => { try { const v = JSON.stringify(a); localStorage.setItem(QK(), v); return localStorage.getItem(QK()) === v; } catch (e) { return false; } };   // true only when it was written AND read back
const isAuth = (m) => /jwt|token|401|not authenticated|unauthor|expired/i.test(String(m || ''));
const qfind = (k) => qlist().find((x) => x.k === k);
const qput = (it) => { const a = qlist().filter((x) => x.k !== it.k); a.push(it); const ok = qsave(a); if (ok) notifyQ(); return ok; };
const qdel = (k) => { qsave(qlist().filter((x) => x.k !== k)); notifyQ(); };
const qkey = () => (E.id ? 'e:' + E.id : 'c:' + E.cid);
const isNet = (e) => !navigator.onLine || (!!e && !e.code && /fetch|network|load failed|timeout|offline/i.test(e.message || ''));
const subs = new Set(); const notifyQ = () => { subs.forEach((f) => { try { f(); } catch (e) { /* ignore */ } }); };
async function callSave(args, meta) {
  const go = (a) => sb.rpc('save_entry', a).then((r) => r, (e) => ({ data: null, error: e || { message: 'Failed to fetch' } }));
  let r = await go(meta ? { ...args, p_meta: meta } : args);
  if (r.error && meta && !meta.entered_later && /Could not find the function|PGRST202/.test((r.error.message || '') + (r.error.code || ''))) r = await go(args);   // phase17 not installed: plain save
  return r;
}
async function callSubmit(id) { return sb.rpc('submit_entry', { p_id: id }).then((r) => r, (e) => ({ data: null, error: e || { message: 'Failed to fetch' } })); }
function queueEntry(args, meta, submit) {
  const k = qkey(), prev = qfind(k);
  const ok = qput({ k, kind: 'entry', cid: E.cid || null, id: E.id || null, code: E.code, loc: E.loc, date: E.date, args, meta, submit: !!submit, at: (prev && prev.at) || new Date().toISOString(), state: 'wait', msg: '', ps: E.later ? E.ps : '' });
  E.queued = ok; return ok;
}
function queueSubmit(id) { const ok = qput({ k: 'e:' + id, kind: 'submit', id, code: E.code, loc: E.loc, date: E.date, submit: true, at: new Date().toISOString(), state: 'wait', msg: '' }); E.queued = ok; return ok; }
const queueFailSheet = () => openSheet(`<h2>${esc(t17('queue_fail_t'))}</h2><div class="notice bad">${esc(t17('queue_fail'))}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
let flushing = false;
async function sendItem(it) {
  let id = it.id;
  if (it.kind === 'entry') {
    const r = await callSave({ ...it.args, p_id: id || null }, it.meta);
    if (r.error) { if (isNet(r.error) || isAuth(r.error.message)) return 'net'; qput({ ...it, state: 'refused', msg: String(r.error.message || r.error) }); return 'refused'; }      // lost network or an expired login: keep waiting, never mark refused
    id = r.data && r.data.id; it = { ...it, id, serial: r.data && r.data.serial, meta: it.meta && it.meta.client_id ? { ...it.meta } : it.meta };
    if (!it.submit) { qdel(it.k); afterSent(it, false); return 'done'; }
    qput({ ...it, k: 'e:' + id, kind: 'submit' }); if (it.k !== 'e:' + id) qdel(it.k); it = { ...it, k: 'e:' + id, kind: 'submit' };
  }
  const r2 = await callSubmit(id);
  if (r2.error) {
    const m = String(r2.error.message || '');
    if (isNet(r2.error) || isAuth(m)) return 'net';
    if (/locked/.test(m)) { const g = await sb.from('entries').select('status').eq('id', id).maybeSingle(); if (g && g.data && g.data.status !== 'draft') { qdel(it.k); afterSent(it, true); return 'done'; } }
    qput({ ...it, state: 'refused', msg: m }); return 'refused';
  }
  qdel(it.k); afterSent(it, true); return 'done';
}
function afterSent(it, submitted) {
  try { const tmp = JSON.parse(store.get('bos_tmp_' + it.code + '_' + it.loc) || 'null'); if (tmp && tmp.cid && tmp.cid === it.cid) store.set('bos_tmp_' + it.code + '_' + it.loc, ''); } catch (e) { /* ignore */ }
  if (!E || !/^#\/entry/.test(location.hash)) return;
  const same = (it.cid && E.cid === it.cid && !E.id) || (it.id && E.id === it.id);
  if (!same) return;
  if (!E.id) { E.id = it.id; E.serial = it.serial; history.replaceState(null, '', '#/entry/' + E.id); }
  E.queued = false; E.dirty = false;
  if (submitted) reloadEntry(E.id); else draw();
}
async function flushOutbox() {
  if (flushing || !S.ctx || !navigator.onLine) return;
  const q = qlist().filter((x) => x.state !== 'refused' || isAuth(x.msg)).sort((a, z) => (a.at > z.at ? 1 : -1)); if (!q.length) return;
  flushing = true; let sent = 0;
  try { for (const it of q) { const r = await sendItem(it); if (r === 'net') break; if (r === 'done') sent++; } } finally { flushing = false; }
  if (sent) toast(t17('sent_ok') + ' · ' + sent);
  notifyQ();
}
const othersQ = () => { let n = 0; try { for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && k.startsWith('bos_eq_') && k !== QK()) { const v = JSON.parse(localStorage.getItem(k) || '[]'); if (Array.isArray(v)) n += v.length; } } } catch (e) { /* ignore */ } return n; };
B.outbox = { others: othersQ, list: qlist, count: () => qlist().length, flush: flushOutbox, discard: (k) => qdel(k), retry: (k) => { const it = qfind(k); if (it) qput({ ...it, state: 'wait', msg: '' }); return flushOutbox(); }, subscribe: (f) => { subs.add(f); return () => subs.delete(f); } };
window.addEventListener('online', flushOutbox);
{ let tries = 0; const iv = setInterval(() => { if (S.ctx) { clearInterval(iv); flushOutbox(); } else if (++tries > 90) clearInterval(iv); }, 1000); }   // at app start, once the person is signed in
setInterval(flushOutbox, 60000);

function laterHTML() {
  if (!E.later && !(laterOn() && (E.mode === 'edit' && E.status === 'draft'))) return '';
  if (E.mode !== 'edit') return `<div class="notice ok" style="margin-top:8px"><b>${esc(t17('chip_later'))}</b> · № ${esc(E.ps || '')} · ${esc((E.pat || '').replace('T', ' '))}</div>`;
  return `<div class="stack" style="margin-top:10px"><label class="ckrow"><input type="checkbox" id="el_on" ${E.later ? 'checked' : ''}><span>${esc(t17('later_on'))}</span></label>
    ${E.later ? `<div class="fld"><label>${esc(t17('later_ps'))}</label><input id="el_ps" value="${esc(E.ps || '')}" autocomplete="off" maxlength="40"></div>
      <div class="fld"><label>${esc(t17('later_at'))}</label><input type="datetime-local" id="el_at" value="${esc(E.pat || '')}" max="${esc(dhakaNow())}"></div>` : `<div class="hint">${esc(t17('later_hint'))}</div>`}</div>`;
}
function rolloutHTML() {
  if (E.rmode === 'parallel') return `<div class="notice warn" style="margin-top:8px">${esc(t17('banner_parallel'))}</div>`;
  if (E.rmode === 'paper' && E.status === 'draft' && E.mode === 'edit') return `<div class="notice warn" style="margin-top:8px">${esc(t17('banner_paper'))}</div>`;
  return '';
}
async function loadRollout() {
  E.rmode = 'app';
  try { const r = await sb.from('form_rollout').select('mode').eq('form_code', E.code).eq('location_id', E.loc).maybeSingle(); if (r && !r.error && r.data && r.data.mode) E.rmode = r.data.mode; } catch (e) { /* phase17 not installed: app */ }
}
async function loadPendingChange() {
  E.chgPending = false;
  if (!E.id || E.status !== 'approved') return;
  try { const r = await sb.from('entry_change_requests').select('id').eq('entry_id', E.id).eq('status', 'pending').limit(1); E.chgPending = !!(r && !r.error && r.data && r.data.length); } catch (e) { /* ignore */ }
}

// ---------- W5b: server-side blind count (14-1 drawer, 10-1 hub) and PIN signatures (supabase/phase18.sql) ----------
// Rule 9: the person counts first; the expected figure is hidden until the count is saved on the server (count_save) and only then shown.
// Rule 10: a second signature is another login with its own PIN (web/pinsign.js signs that person in on a throw-away client).
// Both are OFF until the owner switches them on (rules blind_count_on, pin_signature_on). If phase18 is not installed every RPC fails and the old screen stays.
const X18 = {
  blind_t: L('গণনা — আগে গুনুন, তারপর সেভ', 'Count first, then save', 'Count — আগে গুনুন, তারপর save'),
  blind_hint: L('গণনা সেভ করার পরেই প্রত্যাশিত অঙ্ক ও কম/বেশি দেখা যাবে। সেভ করলে গণনা আর বদলানো যায় না।', 'The expected figure and the short/over appear only after you save the count. A saved count cannot be changed.', 'Count save করার পরেই expected ও কম/বেশি দেখা যাবে। Save করলে count আর বদলানো যায় না।'),
  save_count: L('গণনা সেভ করুন', 'Save count', 'Count save করুন'), peek: L('আগে প্রত্যাশিত দেখুন (লগ হবে)', 'Show expected first (logged)', 'আগে expected দেখুন (log হবে)'),
  need_count: L('আগে নোট ধরে গণনা লিখুন', 'Enter the count by notes first', 'আগে note ধরে count লিখুন'), need_net: L('গণনা সেভ করতে নেট লাগবে', 'Saving the count needs a connection', 'Count save করতে net লাগবে'),
  later: L('প্রত্যাশিত অঙ্ক ও কম/বেশি জমা দেওয়ার পর যাচাইকারীর কাছে দেখা যাবে', 'The expected figure and the short/over are shown to the approver after you submit', 'Expected ও কম/বেশি submit করার পর approver দেখবেন'),
  saved_t: L('গণনা সেভ হয়েছে', 'Count saved', 'Count save হয়েছে'), counted: L('গণনায় প্রাপ্ত', 'Counted', 'Count'), expected: L('প্রত্যাশিত', 'Expected', 'Expected'),
  so: L('কম / বেশি', 'Short / over', 'কম / বেশি'), matches: L('মিলেছে', 'matches', 'মিলেছে'), seen_early: L('প্রত্যাশিত অঙ্ক গণনার আগে দেখা হয়েছিল', 'The expected figure was seen before the count', 'Expected count-এর আগে দেখা হয়েছিল'),
  hub_hidden: L('লেখকের গণনা ও হ্যান্ডওভার অঙ্ক আপনার গণনা সেভ হওয়া পর্যন্ত লুকানো', "The sender's count and handover amount stay hidden until your count is saved", 'Sender-এর count ও handover আপনার count save হওয়া পর্যন্ত লুকানো'),
  pin_t: L('স্বাক্ষর — অন্য লগইন, নিজের পিন', 'Signatures - another login, own PIN', 'Signature — অন্য login, নিজের PIN'),
  pin_hint: L('দ্বিতীয় স্বাক্ষরকারী এই ফোনেই নিজের স্টাফ আইডি ও পিন দিয়ে স্বাক্ষর করবেন। লেখক নিজে স্বাক্ষর করতে পারবেন না।', 'The second person signs on this phone with their own staff ID and PIN. The writer cannot sign.', 'দ্বিতীয় signer এই phone-এই নিজের staff ID ও PIN দিয়ে sign করবেন। লেখক নিজে sign করতে পারবেন না।'),
  r_witness: L('সাক্ষী (দ্বিতীয়বার গণনা)', 'Witness (second count)', 'Witness (দ্বিতীয়বার count)'), r_second_sig: L('দ্বিতীয় স্বাক্ষর', 'Second signature', 'দ্বিতীয় signature'), r_hub_pair: L('হাব জোড়া — দ্বিতীয় জন', 'Hub pair - second person', 'Hub pair — দ্বিতীয় জন'),
  sign: L('পিন দিয়ে স্বাক্ষর', 'Sign with PIN', 'PIN দিয়ে sign'), signed_by: L('স্বাক্ষর করেছেন', 'Signed by', 'Sign করেছেন'), notsigned: L('এখনও স্বাক্ষর হয়নি', 'Not signed yet', 'এখনও sign হয়নি'),
  e_count_already_saved: L('এই গণনা আগেই সেভ হয়েছে — বদলানো যায় না', 'This count is already saved - it cannot change', 'এই count আগেই save হয়েছে — বদলানো যায় না'),
  e_count_locked: L('সেভ করা গণনা এন্ট্রিতে বদলানো যায় না', 'The saved count cannot be changed in the entry', 'Save করা count entry-তে বদলানো যায় না'),
  e_count_mismatch: L('লেখা গণনা আর সেভ করা গণনা মিলছে না', 'The typed count differs from the count being saved', 'লেখা count আর save করা count মিলছে না'),
  e_count_not_open: L('এখন এই গণনা নেওয়ার সময় নয়', 'This count cannot be taken at this stage', 'এখন এই count নেওয়ার সময় নয়'),
  e_bad_count: L('গণনার অঙ্ক ঠিক নয়', 'The count figures are not valid', 'Count-এর অঙ্ক ঠিক নয়'),
  e_signer_is_maker: L('লেখক নিজে স্বাক্ষর করতে পারবেন না', 'The writer cannot sign', 'লেখক নিজে sign করতে পারবেন না'),
  e_signer_already_signed: L('এই লগইন এই ফর্মে আগেই স্বাক্ষর করেছে', 'This login already signed this form', 'এই login এই form-এ আগেই sign করেছে'),
  e_role_already_signed: L('এই স্বাক্ষর আগেই হয়ে গেছে', 'This signature is already done', 'এই signature আগেই হয়ে গেছে'),
  e_signer_locked: L('এই লগইন ভুল পিনে তালাবদ্ধ — কিছুক্ষণ পরে', 'This login is locked after wrong PINs - try later', 'এই login ভুল PIN-এ locked — কিছুক্ষণ পরে'),
  e_pin_signature_required: L('পিন স্বাক্ষর বাকি আছে', 'A PIN signature is still missing', 'PIN signature বাকি আছে'),
  e_signature_mismatch: L('ফর্মের নাম আর স্বাক্ষরকারী মিলছে না', 'The name on the form does not match the signer', 'Form-এর নাম আর signer মিলছে না'),
  e_count_missing: L('আগে নোট ধরে গণনা এন্ট্রিতে লিখে সেভ করুন', 'Type the count in the sheet and save it first', 'আগে count sheet-এ লিখে save করুন'),
  e_count_draft_limit: L('আজ এই লোকেশনে আপনার একটি গণনা-করা খসড়া আগেই আছে — সেটা জমা দিন', 'You already have a counted draft here today - submit it first', 'আজ এই location-এ আপনার একটি counted draft আছে — আগে সেটা submit করুন'),
  e_login_not_fresh: L('স্বাক্ষরকারীকে এখনই আবার পিন দিয়ে ঢুকতে হবে', 'The signer must sign in again just now', 'Signer-কে এখনই আবার PIN দিয়ে ঢুকতে হবে'),
  e_pin_signature_stale: L('স্বাক্ষরের পর শিট বদলেছে — আবার স্বাক্ষর করান', 'The sheet changed after the signature - sign again', 'Signature-এর পর sheet বদলেছে — আবার sign করান'),
  e_pin_signature_off: L('পিন স্বাক্ষর এখন বন্ধ আছে', 'PIN signature is switched off', 'PIN signature এখন off'),
};
Object.assign(X17, X18);
const BLIND_SEC = { '14-1': 'drawer', '10-1': 'hub' };
const BLIND_FIELD = { '14-1': 'cash_count', '10-1': 'rcount' };
const BLIND_HIDE = { '14-1': ['expected', 'short_over'], '10-1': ['counted_total', 'handover', 'diff'] };
const BLIND_V = { '14-1': ['expected', 'short_over', 'so_nonzero'], '10-1': ['counted_total', 'handover', 'diff', 'diff_nonzero'] };
const BLIND_FLAG = { '14-1': 'cash_short_over', '10-1': 'hub_diff' };
const PIN_ROLES = { '14-1': ['witness', 'second_sig'], '10-1': ['hub_pair'] };
const blindStage = () => !!E && ((E.code === '14-1' && E.mode === 'edit') || (E.code === '10-1' && E.mode === 'check'));
const blindRevealed = () => !!(E.blind.peeked || (E.blind.saved && E.blind.res && E.blind.res.expected !== undefined));    // the maker's own count_save answer carries no figures (server side blind)
const blindPending = () => !!(E && E.blind && E.blind.on && blindStage() && !blindRevealed());
function blindMask() {
  if (!blindPending()) return;
  BLIND_V[E.code].forEach((k) => { delete E.calc.v[k]; });
  E.calc.flags = E.calc.flags.filter((f) => f.code !== BLIND_FLAG[E.code]);
}
async function loadW5b() {
  E.blind = null; E.pin = null;
  if (!BLIND_SEC[E.code]) return;
  try {
    const [b, p] = await Promise.all([sb.rpc('blind_active', { p_form: E.code, p_loc: E.loc }), sb.rpc('pin_sig_active', { p_form: E.code })]);
    const bon = !b.error && b.data === true, pon = !p.error && p.data === true;
    if (bon) {
      E.blind = { on: true, saved: false, res: null, peeked: false, canPeek: false };
      if (E.id) { const g = await sb.rpc('count_get', { p_entry: E.id, p_section: BLIND_SEC[E.code] }); if (!g.error && g.data && g.data.saved) { E.blind.saved = true; E.blind.res = g.data; } }
      E.blind.canPeek = S.ctx.is_owner ? B.rule('owner_sees_expected_first', true) !== false : await A.hasAnyGrant(['see_expected']);
    }
    if (pon) {
      E.pin = { on: true, sigs: {} };
      if (E.id) { const s = await sb.from('entry_signatures').select('role,signer_staff').eq('entry_id', E.id); (s.data || []).forEach((r) => { E.pin.sigs[r.role] = r.signer_staff; }); }
    }
  } catch (e) { E.blind = null; E.pin = null; }
}
function blindBoxHTML(sec) {
  if (!E.blind || !E.blind.on || !blindStage() || !sec.fields.some((f) => f.id === BLIND_FIELD[E.code])) return '';
  const b = E.blind;
  if (b.saved && b.res && b.res.expected === undefined) return `<div class="notice ok" id="blindbox"><b>${esc(lab(X18.saved_t))}</b> · ${esc(lab(X18.counted))}: ${esc(money(b.res.counted))}<div class="muted" style="font-size:.85rem" id="blind_later">${esc(lab(X18.later))}</div></div>`;
  if (b.saved && b.res) {
    const r = b.res, d = Number(r.diff);
    return `<div class="notice ${d === 0 ? 'ok' : 'warn'}" id="blindbox"><b>${esc(lab(X18.saved_t))}</b><div>${esc(lab(X18.counted))}: ${esc(money(r.counted))} · ${esc(lab(X18.expected))}: ${esc(money(r.expected))}</div>
      <div class="calc big ${d < 0 ? 'neg' : ''}" id="blind_diff">${esc(lab(X18.so))}: ${esc(d === 0 ? '0 (' + lab(X18.matches) + ')' : money(d))}</div>${r.seen_before_count ? `<div class="muted" style="font-size:.85rem">${esc(lab(X18.seen_early))}</div>` : ''}</div>`;
  }
  if (b.peeked) return `<div class="notice warn" id="blindbox">${esc(lab(X18.expected))}: ${esc(money(b.peekExpected))} · ${esc(lab(X18.seen_early))}</div><button class="primary full" data-act="e_count_save" id="blind_save">${esc(lab(X18.save_count))}</button>`;
  return `<div class="notice warn" id="blindbox">${esc(lab(X18.blind_hint))}</div><button class="primary full" data-act="e_count_save" id="blind_save">${esc(lab(X18.save_count))}</button>${b.canPeek ? `<button class="full" data-act="e_count_peek" id="blind_peek" style="margin-top:6px">${esc(lab(X18.peek))}</button>` : ''}`;
}
async function countSave() {
  if (!E || !E.blind || !blindStage()) return;
  const sec = BLIND_SEC[E.code], obj = sec === 'drawer' ? getp(E.data, 'cash_count') : getp(E.check, 'rcount');
  if (!obj || denTotal(obj) <= 0) return toast(lab(X18.need_count));
  if (sec === 'drawer' && (E.dirty || !E.id || E.queued)) { const ok = await saveDraft(); if (!ok) return; }
  const { data, error } = await sb.rpc('count_save', { p_entry: E.id, p_section: sec, p_counted: obj });
  if (error) { if (isNet(error)) return toast(lab(X18.need_net)); return fail17(error); }
  E.blind.saved = true; E.blind.res = { ...data, seen_before_count: E.blind.peeked };
  toast(lab(X18.saved_t)); const sc = window.scrollY; draw(); window.scrollTo(0, sc);
}
async function countPeek() {
  if (!E || !E.blind || !blindStage()) return;
  if (!E.id || E.dirty || E.queued) { const ok = await saveDraft(); if (!ok) return; }
  const { data, error } = await sb.rpc('count_peek', { p_entry: E.id, p_section: BLIND_SEC[E.code] });
  if (error) return fail17(error);
  E.blind.peeked = true; E.blind.peekExpected = data.expected;
  const sc = window.scrollY; draw(); window.scrollTo(0, sc);
}
function pinBoxHTML() {
  if (!E.pin || !E.pin.on || !PIN_ROLES[E.code]) return '';
  const rows = PIN_ROLES[E.code].map((r) => { const who = E.pin.sigs[r];
    return `<div class="row between" data-pinrole="${r}"><span>${esc(lab(X18['r_' + r]))}</span>${who ? `<span class="chip ok">${esc(lab(X18.signed_by))}: ${esc(staffName(who))}</span>` : E.mode === 'edit' ? `<button data-act="e_pin_sign" data-v="${r}">${esc(lab(X18.sign))}</button>` : `<span class="chip warn">${esc(lab(X18.notsigned))}</span>`}</div>`; }).join('');
  return `<div class="notice" id="pinbox" style="margin-top:10px"><b>${esc(lab(X18.pin_t))}</b><div class="muted" style="font-size:.85rem">${esc(lab(X18.pin_hint))}</div><div class="stack" style="margin-top:6px">${rows}</div></div>`;
}
async function pinSignClick(role) {
  if (!E || !E.pin || !E.pin.on || E.mode !== 'edit') return;
  if (!E.id || E.dirty || E.queued) { const ok = await saveDraft(); if (!ok) return; }
  if (!B.pinSign) return;
  B.pinSign({ entryId: E.id, role, exclude: Object.values(E.pin.sigs), onDone: async (staff) => {
    E.pin.sigs[role] = staff;
    if (role === 'witness') E.data.witness = staff; else if (role === 'second_sig') E.data.second_sig = staff; else E.data.pair_by = staff;
    E.dirty = true; await saveDraft(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); } });
}
function draw() {
  B.curDate = E.date;
  E.shows = {}; E.rshows = {}; recompute();
  const spec = E.spec, head = [E.later ? null : PAPER_NO, ...(spec.head || [])].filter(Boolean).map((f) => fieldHTML(f, f.id, 'd', modeEditable(f), wrap(f))).join('');
  const serial = E.serial ? `${E.code}-${(ENV.locs.find((l) => l.id === E.loc) || {}).code || E.loc}-${E.serial}` : t('new_entry');
  const wdv = lab(WD[weekday(E.date)]);
  const tag = E.settings['daytag_' + weekday(E.date)];
  shell(lab(spec.title), `<datalist id="dl_sup">${(ENV.sup || []).map((x) => `<option value="${esc(x.name)}"></option>`).join('')}</datalist><datalist id="dl_items">${ENV.items.filter((i) => i.is_active).map((i) => `<option value="${esc(i.code)} · ${esc(nm(i))}"></option>`).join('')}</datalist>
    <div class="entry" id="entry">
    <div class="card panel"><div class="row between"><b class="serial">${esc(serial)}</b><span class="row"><span class="chip ${STATUS_CLS[E.status]}">${esc(t('est_' + E.status))}</span>${E.queued ? `<span class="chip warn" id="e_notsent">${esc(t17('chip_notsent'))}</span>` : ''}${E.id || E.queued ? `<button class="mini" data-act="e_menu" aria-label="More" style="min-width:36px">⋮</button>` : ''}</span></div>
      <div class="row wrap" style="margin-top:6px"><span class="chip">${esc(locName(E.loc))}</span>
      ${E.mode === 'edit' && !E.later ? `<input type="date" id="e_date" value="${esc(E.date)}" style="width:auto">` : `<span class="chip">${esc(E.date)}</span>`}
      ${E.later ? `<span class="chip info" id="e_later_chip">${esc(t17('chip_later'))}</span>` : ''}${E.rmode === 'paper' ? `<span class="chip warn">${esc(t17('chip_paper'))}</span>` : E.rmode === 'parallel' ? `<span class="chip warn">${esc(t17('chip_parallel'))}</span>` : ''}${E.rev > 1 ? `<span class="chip" id="e_rev_chip">${esc(t17('chip_rev'))} ${E.rev}</span>` : ''}${E.chgPending ? `<span class="chip warn">${esc(t17('chip_chg'))}</span>` : ''}
      <span class="chip">${esc(wdv)}</span>${tag ? `<span class="chip warn">${esc(t('tag'))}: ${esc(tag)}</span>` : ''}</div>
      ${E.checked_staff ? `<div class="muted" style="font-size:.85rem;margin-top:6px">${esc(t('checked_by'))}: ${esc(staffName(E.checked_staff))}${E.check_note ? ' · ' + esc(E.check_note) : ''}</div>` : ''}
      ${rolloutHTML()}${laterHTML()}${E.mode === 'change' ? `<div class="notice warn" style="margin-top:8px">${esc(t17('chg_hint'))}</div>` : ''}
      ${head ? `<div class="stack" style="margin-top:10px">${head}</div>` : ''}${pinBoxHTML()}</div>
    <div id="flagsbox">${flagsHTML()}</div>
    ${spec.sections.map(sectionHTML).join('')}</div>${actionsHTML()}`, 'form/' + E.code);
  refresh(); hydratePhotos();
}

function fmtCalc(val, fm) {
  if (val === undefined || val === null || (typeof val === 'number' && !Number.isFinite(val))) return '—';
  if (fm === 'money') return money(val);
  if (fm === 'text') return typeof val === 'object' ? lab(val) : String(val);
  if (fm === 'bool') return val ? '✓' : '✗';
  return fmt(val);
}
function refresh() {
  recompute();
  const x = ctxFor();
  document.querySelectorAll('[data-calc]').forEach((el) => {
    const key = el.dataset.calc; let v;
    if (key.startsWith('rows.')) { const [, tid, i, cid] = key.split('.'); v = ((E.calc.rows[tid] || [])[Number(i)] || {})[cid]; } else v = E.calc.v[key];
    el.textContent = fmtCalc(v, el.dataset.fmt); el.classList.toggle('neg', typeof v === 'number' && v < 0 && el.dataset.fmt === 'money');
  });
  Object.entries(E.shows).forEach(([id, fn]) => { const el = document.querySelector(`[data-sid="${id}"]`); if (el) el.hidden = !fn(x); });
  Object.entries(E.rshows).forEach(([id, [fn, tid, i]]) => { const el = document.querySelector(`[data-rsid="${id}"]`); if (el) el.hidden = !fn({ ...x, row: (E.data[tid] || [])[i] || {}, rowC: (E.check[tid] || [])[i] || {} }); });
  if (blindPending()) document.querySelectorAll('[data-calc]').forEach((el) => { if (BLIND_HIDE[E.code].includes(el.dataset.calc)) { const w = el.closest('.fld'); if (w) w.hidden = true; } });
  const fb = $('#flagsbox'); if (fb) fb.innerHTML = flagsHTML();
}

// ---------- editing events ----------
const norm = (s) => String(s).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
// ---------- photos (Supabase Storage bucket "photos") ----------
function shrink(file, max = 1280, q = 0.72) {
  return new Promise((res, rej) => { const img = new Image(), u = URL.createObjectURL(file);
    img.onload = () => { const k = Math.min(1, max / Math.max(img.width, img.height)), c = document.createElement('canvas'); c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(u); c.toBlob((b) => (b ? res(b) : rej(new Error('image'))), 'image/jpeg', q); };
    img.onerror = () => rej(new Error('image')); img.src = u; });
}
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
async function addPhoto(el) {
  const f = el.files && el.files[0]; if (!f) return;
  toast(t('photo_up'));
  try {
    const blob = await shrink(f), path = `${E.code}/${E.loc}/${rid()}.jpg`;
    const up = await sb.storage.from('photos').upload(path, blob, { contentType: 'image/jpeg' }); if (up.error) throw up.error;
    const o = el.dataset.w === 'c' ? E.check : E.data, cur = getp(o, el.dataset.p); setp(o, el.dataset.p, [...(Array.isArray(cur) ? cur : []), path]);
    touch(); const sc = window.scrollY; draw(); window.scrollTo(0, sc);
  } catch (e) { fail(e); }
}
async function hydratePhotos() {
  const imgs = [...document.querySelectorAll('img[data-path]')]; if (!imgs.length) return;
  const paths = [...new Set(imgs.map((i) => i.dataset.path))];
  const r = await sb.storage.from('photos').createSignedUrls(paths, 3600); if (r.error || !r.data) return;
  const m = new Map(r.data.map((x) => [x.path, x.signedUrl]));
  imgs.forEach((i) => { const u = m.get(i.dataset.path); if (u) i.src = u; });
}
function onEdit(e) {
  if (!E) return; const el = e.target; if (!el.dataset || !el.dataset.p || !el.dataset.w) return;
  if (el.dataset.photo) { if (e.type === 'change') addPhoto(el); return; }
  if (el.dataset.sup) { const o = el.dataset.w === 'c' ? E.check : E.data, name = el.value.trim(), m = ENV.sup.find((x) => x.name.trim().toLowerCase() === name.toLowerCase());
    setp(o, el.dataset.p, el.value); setp(o, el.dataset.p + '_id', m ? m.id : ''); touch(); refresh(); if (e.type === 'change') { const h = el.closest('.fld') && el.closest('.fld').querySelector('.hint'); if (h) h.textContent = name ? lab(m ? SUPX.listed : SUPX.free) : ''; } return; }
  if (el.dataset.item) { if (e.type !== 'change') return; const code = el.value.split(' · ')[0].trim(); const it = ENV.byCode.get(code); setp(el.dataset.w === 'c' ? E.check : E.data, el.dataset.p, it ? code : ''); el.value = it ? it.code + ' · ' + nm(it) : ''; touch(); refresh(); return; }
  let v = el.type === 'checkbox' ? el.checked : el.value;
  if (el.dataset.num) { v = norm(v); if (v !== el.value) el.value = v; }
  setp(el.dataset.w === 'c' ? E.check : E.data, el.dataset.p, v); touch(); refresh();
}
function touch() { E.dirty = true; if (!E.id) store.set('bos_tmp_' + E.code + '_' + E.loc, JSON.stringify({ d: E.data, date: E.date, cid: E.cid, later: !!E.later, ps: E.ps || '', pat: E.pat || '' })); }
document.addEventListener('input', (e) => { if (E && e.target.id === 'el_ps') { E.ps = e.target.value; E.data.paper_no = E.ps; touch(); } else onEdit(e); });
document.addEventListener('change', (e) => {
  if (!E) return; const id = e.target.id;
  if (id === 'el_on') { E.later = e.target.checked; if (E.later) { E.pat = E.pat || dhakaNow(); E.date = E.pat.slice(0, 10); E.ps = E.ps || String((E.data || {}).paper_no || ''); E.data.paper_no = E.ps; } touch(); draw(); }
  else if (id === 'el_at') { E.pat = e.target.value; if (E.pat) E.date = E.pat.slice(0, 10); touch(); draw(); }
});
document.addEventListener('change', (e) => { if (e.target.id === 'e_date' && E) { E.date = e.target.value; touch(); draw(); } else onEdit(e); });
document.addEventListener('toggle', (e) => { if (E && e.target.dataset && e.target.dataset.sec !== undefined) { const i = Number(e.target.dataset.sec); if (e.target.open) E.openSecs.add(i); else E.openSecs.delete(i); } }, true);

// ---------- validation ----------
function missingRequired() {
  const x = ctxFor(), miss = [];
  const check = (f, obj, path, ctx, pre = '') => {
    if (f.type === 'note' || f.type === 'calc') return;
    const vis = (!f.show || f.show(ctx)); if (!vis) return;
    const req = typeof f.req === 'function' ? f.req(ctx) : f.req; if (!req) return;
    const v = getp(obj, path);
    if (!has(v) || (f.type === 'denoms' && denTotal(v) === 0)) miss.push(pre + lab(f.label));
  };
  E.spec.head && E.spec.head.forEach((f) => check(f, E.data, f.id, x));
  E.spec.sections.forEach((sec) => {
    if (sec.show && !sec.show(x)) return;
    const mine = (sec.who || 'maker') === (E.mode === 'check' ? 'checker' : 'maker');
    sec.fields.forEach((f) => {
      if (f.type === 'table') {
        const n = f.rows ? f.rows.length : (E.data[f.id] || []).length;
        for (let i = 0; i < n; i++) {
          const row = (E.data[f.id] || [])[i] || {}, rowC = (E.check[f.id] || [])[i] || {};
          const any = Object.values(row).some(has) || Object.values(rowC).some(has);
          if (!any && !f.rows) continue;
          f.cols.forEach((c) => { const isC = c.who === 'checker'; if ((E.mode === 'check') !== isC) return; check(c, isC ? E.check : E.data, `${f.id}.${i}.${c.id}`, { ...x, row, rowC }, (f.rows ? lab(f.rows[i]) : String(i + 1)) + ' · '); });
        }
      } else if ((E.mode === 'check') === ((f.who || sec.who) === 'checker')) check(f, f.who === 'checker' || sec.who === 'checker' ? E.check : E.data, f.id, x);
    });
  });
  if (E.pin && E.pin.on && E.mode === 'edit') (PIN_ROLES[E.code] || []).forEach((r) => { if (!E.pin.sigs[r]) miss.push(lab(X18['r_' + r]) + ' — ' + lab(X18.notsigned)); });
  return miss;
}

// ---------- save / submit / decide ----------
async function ensureLoaded() { await loadStatic(); }
async function saveDraft(note) {
  if (!laterOk()) { toast(t17('need_later')); return false; }
  const flags = flagsOf('maker'), meta = metaOf();
  const args = { p_id: E.id || null, p_form: E.code, p_loc: E.loc, p_date: E.date, p_data: E.data, p_flags: flags, p_note: note || null };
  const { data, error } = await callSave(args, meta);
  if (error && isNet(error)) { if (!queueEntry(args, meta, false)) { E.queued = false; queueFailSheet(); return false; } E.dirty = false; toast(t17('queued')); const sc = window.scrollY; draw(); window.scrollTo(0, sc); return true; }
  if (error) { if (/note_required/.test(error.message)) { askNote(t('note_overwrite'), (n) => saveDraft(n).then(() => { if (E && E.afterSave) { const f = E.afterSave; E.afterSave = null; f(); } })); return false; } fail17(error); return false; }
  if (E.queued) { qdel(qkey()); E.queued = false; }
  if (!E.id) { E.id = data.id; E.serial = data.serial; store.set('bos_tmp_' + E.code + '_' + E.loc, ''); history.replaceState(null, '', '#/entry/' + E.id); }
  E.dirty = false; E.hadLater = !!E.later; E.created_by = E.created_by || S.ctx.profile.id; toast(t('saved')); return true;
}
function askNote(title, cb, required = true) {
  openSheet(`<h2>${esc(title)}</h2><textarea id="note_in" rows="3" placeholder="${esc(t('reason_note'))}"></textarea>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="note_ok">${esc(t('confirm'))}</button></div>`);
  A.noteCb = () => { const v = ($('#note_in').value || '').trim(); if (required && !v) return toast(t('note_needed')); closeSheet(); cb(v); };
}
async function submit() {
  if (E.dirty || !E.id || E.queued) { const ok = await saveDraft(); if (!ok) { E.afterSave = submit; return; } }
  const miss = missingRequired();
  if (miss.length) return openSheet(`<h2>${esc(t('missing_title'))}</h2><div class="stack">${miss.map((m) => `<div class="notice bad">${esc(m)}</div>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
  if (E.queued) { const it = qfind(qkey()); if (it && !qput({ ...it, submit: true })) return queueFailSheet(); toast(t17('queued_submit')); return draw(); }
  const { error } = await callSubmit(E.id);
  if (error && isNet(error)) { if (!queueSubmit(E.id)) return queueFailSheet(); toast(t17('queued_submit')); return draw(); }
  if (error) { if (/red_blocked/.test(error.message)) return releaseSheet(); if (/pin_signature_stale/.test(error.message) && E.pin) { E.pin.sigs = {}; fail17(error); return draw(); } return fail17(error); }
  toast(t('submitted_ok')); await reloadEntry(E.id);
}
async function loadReleases() {
  if (!E.id) { E.releases = {}; return; }
  const r = await sb.from('release_requests').select('*').eq('entry_id', E.id).order('id');
  E.releases = {}; (r.data || []).forEach((x) => { E.releases[x.flag_code] = x; });
}
async function releaseSheet() {
  await loadReleases();
  const reds = flagsOf('maker').filter((f) => f.level === 'red');
  openSheet(`<h2>${esc(t('red_title'))}</h2><div class="notice bad">${esc(t('red_text'))}</div><div class="stack">${reds.map((f) => {
    const r = E.releases[f.code];
    return `<div class="card"><div class="flag red"><b>●</b> ${esc(lab(f.text))}${f.amount !== undefined ? ' · ' + esc(f.unit === 'qty' ? fmt(f.amount) : money(f.amount)) : ''}</div>
      ${r && r.status === 'approved' ? `<span class="chip ok">${esc(t('rel_approved'))}</span>` : r && r.status === 'pending' ? `<span class="chip warn">${esc(t('rel_pending'))}</span>` : `<textarea id="rr_${esc(f.code)}" rows="2" placeholder="${esc(t('release_reason'))}"></textarea><button class="primary full" data-act="e_release" data-code="${esc(f.code)}">${esc(t('release_ask'))}</button>`}
      ${r && r.status === 'rejected' ? `<div class="notice bad">${esc(t('rel_rejected'))}${r.decision_note ? ': ' + esc(r.decision_note) : ''}</div>` : ''}</div>`; }).join('')}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
}
async function decide(approve, note) {
  const missing = approve ? missingRequired() : [];
  if (missing.length) return openSheet(`<h2>${esc(t('missing_title'))}</h2><div class="stack">${missing.map((m) => `<div class="notice bad">${esc(m)}</div>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
  const cflags = flagsOf('check').map((f) => ({ ...f, src: 'check' }));
  const { error } = await sb.rpc('decide_entry', { p_id: E.id, p_approve: approve, p_note: note || null, p_check: E.check, p_flags: cflags });
  if (error) return /own entry/.test(error.message) ? toast(t('err_own_entry')) : fail17(error);
  toast(approve ? t('approved_ok') : t('rejected_ok')); await reloadEntry(E.id);
}
async function reopen(note) {
  const { error } = await sb.rpc('reopen_entry', { p_id: E.id, p_note: note }); if (error) return fail(error);
  toast(t('reopened_ok')); await reloadEntry(E.id);
}

// ---------- open an entry ----------
async function viewEntry() {
  const parts = location.hash.replace(/^#\/?/, '').split('/'); // entry/<id>  or entry/new/<form>/<loc>
  shell(t('loading'), `<p class="muted center pad">${esc(t('loading'))}</p>`, true);
  await ensureLoaded();
  if (parts[1] === 'new') return startNew(parts[2], Number(parts[3]));
  await reloadEntry(parts[1]);
}
async function startNew(code, loc) {
  const spec = B.forms[code]; if (!spec) return location.hash = '#/home';
  const fr = await sb.from('forms').select('*').eq('code', code).single();
  const settings = await locSettings(loc);
  E = { code, spec, formRow: fr.data, loc, date: today(), status: 'draft', mode: 'edit', data: {}, check: {}, flags: [], settings, serial: null, id: null, dirty: false, created_by: S.ctx.profile.id, openSecs: new Set(), releases: {}, cid: rid(), later: false, ps: '', pat: '', rev: 1 };
  try { const tmp = JSON.parse(store.get('bos_tmp_' + code + '_' + loc) || 'null'); if (tmp && ((tmp.d && Object.keys(tmp.d).length) || tmp.cid)) { E.data = tmp.d || {}; E.date = tmp.date || E.date; E.dirty = true; if (tmp.cid) E.cid = tmp.cid; E.later = !!tmp.later; E.ps = tmp.ps || ''; E.pat = tmp.pat || ''; toast(t('restored')); } } catch (e) { /* ignore */ }
  E.queued = !!qfind('c:' + E.cid);
  await loadRollout(); await loadW5b();
  if (spec.init) spec.init(ctxFor(), E.data);
  if (E.rmode === 'paper' && laterOn() && !E.later) { E.later = true; E.pat = dhakaNow(); E.date = E.pat.slice(0, 10); }   // Paper here: the only way in is “entered later from paper”
  draw();
}
async function reloadEntry(id) {
  const r = await sb.from('entries').select('*').eq('id', id).single();
  if (r.error || !r.data) { toast(t('err_generic')); return location.hash = '#/home'; }
  const e = r.data, spec = B.forms[e.form_code];
  const fr = await sb.from('forms').select('*').eq('code', e.form_code).single();
  const settings = await locSettings(e.location_id, true);
  const me = S.ctx.profile.id, perms = S.ctx.perms[e.form_code] || {};
  const maker = e.created_by === me || S.ctx.is_owner;
  const mode = e.status === 'draft' && maker && perms.enter ? 'edit' : e.status === 'submitted' && perms.approve ? 'check' : 'view';
  const keep = E && E.id === id ? E.openSecs : new Set();
  E = { id: e.id, code: e.form_code, spec, formRow: fr.data, loc: e.location_id, date: e.entry_date, status: e.status, mode, data: e.data || {}, check: e.check_data || {}, flags: e.flags || [], settings, serial: e.serial, dirty: false,
    created_by: e.created_by, checked_staff: e.checked_staff, check_note: e.check_note, openSecs: keep, releases: {},
    later: !!e.entered_later, hadLater: !!e.entered_later, ps: e.paper_serial || '', pat: toDhaka(e.paper_at), rev: e.rev_no || 1, cid: e.client_id || null };
  E.queued = !!qfind('e:' + e.id);
  await Promise.all([loadReleases(), loadRollout(), loadPendingChange(), loadW5b()]); draw();
}

// ---------- form list ----------
async function viewFormList() {
  const code = location.hash.replace(/^#\/?/, '').split('/')[1];
  if (code === '0-1') return (location.hash = '#/locset');
  const spec = B.forms[code]; if (!spec) return location.hash = '#/home';
  await ensureLoaded();
  const perms = S.ctx.perms[code] || {}, locs = myLocs();
  if (!S.formLoc || !locs.find((l) => l.id === S.formLoc)) S.formLoc = (locs[0] || {}).id;
  shell(lab(spec.title), `<div class="row"><select id="fl_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === S.formLoc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>
      ${perms.enter && S.formLoc ? `<button class="primary" data-act="newentry" data-v="${code}">＋ ${esc(t('new_entry'))}</button>` : S.formLoc && !perms.enter ? `<button data-act="em_form" data-v="${code}">${esc(t('em_access'))}</button>` : ''}</div>
    ${!locs.length ? `<div class="notice warn">${esc(t('no_location'))}</div>` : ''}<div id="fl_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  if (!S.formLoc) return;
  const q60 = (sel) => sb.from('entries').select(sel).eq('form_code', code).eq('location_id', S.formLoc).order('entry_date', { ascending: false }).order('serial', { ascending: false }).limit(60);
  const SEL0 = 'id,serial,entry_date,status,flags,created_staff,checked_staff,paper_no:data->>paper_no';
  let r = await q60(SEL0 + ',entered_later,rev_no'); if (r.error) r = await q60(SEL0);     // phase17 columns missing: the plain list
  if (r.error) return fail(r.error);
  const waiting = qlist().filter((x) => x.code === code && x.loc === S.formLoc && x.kind === 'entry' && !x.id);
  const lc = (ENV.locs.find((l) => l.id === S.formLoc) || {}).code || '';
  $('#fl_body').innerHTML = waiting.map((x) => `<div class="card item" data-act="go" data-v="outbox"><div><div class="nm">${esc(code)} · ${esc(x.date || '')}</div><div class="muted" style="font-size:.85rem">${esc(x.ps ? '№ ' + x.ps : '')}</div></div><div class="row"><span class="chip warn">${esc(t17('chip_notsent'))}</span></div></div>`).join('') + r.data.map((e) => {
    const reds = (e.flags || []).filter((f) => f.level === 'red').length, ys = (e.flags || []).filter((f) => f.level === 'yellow').length;
    return `<div class="card item" data-act="openentry" data-v="${e.id}"><div><div class="nm">${esc(code)}-${esc(lc)}-${e.serial}</div><div class="muted" style="font-size:.85rem">${esc(e.entry_date)} · ${esc(staffName(e.created_staff))}${e.paper_no ? ' · № ' + esc(e.paper_no) : ''}</div></div>
      <div class="row">${e.entered_later ? `<span class="chip info">${esc(t17('chip_later'))}</span>` : ''}${e.rev_no > 1 ? `<span class="chip">${esc(t17('chip_rev'))} ${e.rev_no}</span>` : ''}<span class="chip ${STATUS_CLS[e.status]}">${esc(t('est_' + e.status))}</span>${reds ? `<span class="chip bad">● ${reds}</span>` : ''}${ys ? `<span class="chip warn">▲ ${ys}</span>` : ''}</div></div>`; }).join('') || `<p class="muted center">${esc(t('no_entries'))}</p>`;
}

// ---------- exceptions ----------
async function viewExceptions() {
  shell(t('exceptions'), `<div class="row"><select id="ex_st"><option value="open">${esc(t('ex_open'))}</option><option value="resolved">${esc(t('ex_resolved'))}</option></select></div><div id="ex_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  await ensureLoaded(); drawExceptions('open');
}
async function drawExceptions(st) {
  const r = await sb.from('exceptions').select('*').eq('status', st).order('created_at', { ascending: false }).limit(100); if (r.error) return fail(r.error);
  const ids = [...new Set(r.data.map((x) => x.entry_id).filter(Boolean))]; const en = ids.length ? await sb.from('entries').select('id,serial,form_code,location_id').in('id', ids) : { data: [] };
  const em = new Map((en.data || []).map((x) => [x.id, x]));
  $('#ex_body').innerHTML = r.data.map((x) => { const e = em.get(x.entry_id) || {};
    return `<div class="card stack"><div class="row between"><span class="chip ${x.level === 'red' ? 'bad' : 'warn'}">${x.level === 'red' ? '●' : '▲'} ${esc(x.level)}</span><span class="muted" style="font-size:.82rem">${esc(x.entry_date)} · ${esc(locName(x.location_id))}</span></div>
      <div>${window.BOS.flagChip ? window.BOS.flagChip(x.flag_code) : ''}<b>${esc(lab(x.text) || x.flag_code)}</b>${x.amount !== null ? ' · ' + esc(money(x.amount)) : ''}</div>
      <div class="muted" style="font-size:.85rem">${x.entry_id ? `${esc(x.form_code)}-${esc((ENV.locs.find((l) => l.id === e.location_id) || {}).code || '')}-${e.serial || ''}` : esc(x.form_code)}</div>
      ${x.status === 'open' ? `<div class="row">${x.entry_id ? `<button class="full" data-act="openentry" data-v="${x.entry_id}">${esc(t('open_entry'))}</button>` : `<button class="full" data-act="go" data-v="pos">POS</button>`}<button class="primary full" data-act="ex_resolve" data-v="${x.id}">${esc(t('resolve'))}</button></div>`
        : `<div class="muted" style="font-size:.85rem">${esc(staffName(x.resolved_staff))} · ${esc(x.resolved_note || '')}</div>`}</div>`; }).join('') || `<p class="muted center">${esc(t('ex_none'))}</p>`;
}
document.addEventListener('change', (e) => { if (e.target.id === 'ex_st') drawExceptions(e.target.value); if (e.target.id === 'fl_loc') { S.formLoc = Number(e.target.value); viewFormList(); } if (e.target.id === 'ls_loc') { S.lsLoc = Number(e.target.value); viewLocSet(); } });

// ---------- release requests (owner) ----------
async function viewReleases() {
  shell(t('releases'), `<div id="rl_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  await ensureLoaded();
  const r = await sb.from('release_requests').select('*').order('id', { ascending: false }).limit(60); if (r.error) return fail(r.error);
  const ids = [...new Set(r.data.map((x) => x.entry_id))]; const en = ids.length ? await sb.from('entries').select('id,serial,form_code,location_id,flags,entry_date').in('id', ids) : { data: [] };
  const em = new Map((en.data || []).map((x) => [x.id, x]));
  $('#rl_body').innerHTML = r.data.map((x) => { const e = em.get(x.entry_id) || {}; const fl = (e.flags || []).find((f) => f.code === x.flag_code) || {};
    return `<div class="card stack"><div class="row between"><b>${esc(e.form_code || '')}-${esc((ENV.locs.find((l) => l.id === e.location_id) || {}).code || '')}-${e.serial || ''}</b><span class="chip ${x.status === 'approved' ? 'ok' : x.status === 'rejected' ? 'bad' : 'warn'}">${esc(t('rel_' + x.status))}</span></div>
      <div class="flag red"><b>●</b> ${esc(lab(fl.text) || x.flag_code)}${x.flag_amount !== null ? ' · ' + esc(money(x.flag_amount)) : ''}</div>
      <div><span class="muted">${esc(staffName(x.requested_staff))}:</span> ${esc(x.reason)}</div>
      ${x.status === 'pending' ? `<input id="rn_${x.id}" placeholder="${esc(t('reason_note'))}"><div class="row"><button class="danger full" data-act="rl_decide" data-v="${x.id}" data-ok="0">${esc(t('reject'))}</button><button class="primary full" data-act="rl_decide" data-v="${x.id}" data-ok="1">${esc(t('approve'))}</button><button data-act="openentry" data-v="${x.entry_id}">↗</button></div>`
        : `<div class="muted" style="font-size:.85rem">${esc(x.decision_note || '')}</div>`}</div>`; }).join('') || `<p class="muted center">${esc(t('no_requests'))}</p>`;
}

// ---------- location settings (owner) ----------
// repeated settings are shown as ONE compact table instead of a long repeated list
const FAMILIES = {
  fridge: { title: L('ফ্রিজ / চিলার — নাম ও তাপমাত্রার সীমা', 'Fridges / chillers — name and temperature limits', 'Fridge / Chiller — নাম ও Temperature limit'), group: 'C', rows: [1, 2, 3], re: /^fridge(\d)_(name|min|max)$/,
    cols: [['name', L('নাম', 'Name'), 'text'], ['min', L('সর্বনিম্ন °C', 'Min °C'), 'number'], ['max', L('সর্বোচ্চ °C', 'Max °C'), 'number']], key: (i, c) => 'fridge' + i + '_' + c, rowLabel: (i) => L('ফ্রিজ / চিলার ' + i, 'Fridge / chiller ' + i) },
  daytag: { title: L('বারের ট্যাগ (দিনের রং)', 'Day tags (colour of the day)', 'বারের Tag (দিনের রং)'), group: 'C', rows: [0, 1, 2, 3, 4, 5, 6], re: /^daytag_(\d)$/,
    cols: [['', L('ট্যাগ / রং', 'Tag / colour'), 'text']], key: (i) => 'daytag_' + i, rowLabel: (i) => L(['রবিবার', 'সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার'][i], ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][i]) },
};
const famOf = (key) => Object.keys(FAMILIES).find((f) => FAMILIES[f].re.test(key));
function famHTML(f, m) {
  const F = FAMILIES[f];
  return `<div class="card stack"><b>${esc(lab(F.title))}</b>${F.rows.map((i) => `<div class="perm"><div><b>${esc(lab(F.rowLabel(i)))}</b></div><div class="row wrap">${F.cols.map(([c, l, kind]) => {
      const key = F.key(i, c), v = m[key];
      return `<div style="flex:1;min-width:110px"><label>${esc(lab(l))}</label><input id="lv_${key}" ${kind === 'number' ? 'inputmode="decimal"' : ''} value="${esc(v === null || v === undefined ? '' : v)}"></div>`; }).join('')}</div></div>`).join('')}
    <button class="primary full" data-act="ls_savefam" data-v="${f}">${esc(t('save'))}</button></div>`;
}
async function viewLocSet() {
  await ensureLoaded();
  const locs = ENV.locs; if (!S.lsLoc) S.lsLoc = locs[0].id;
  shell(t('locset'), `<div class="notice warn">${esc(t('locset_hint'))}</div><select id="ls_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === S.lsLoc ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select><div id="ls_body"><p class="muted">${esc(t('loading'))}</p></div>`, true);
  const m = await locSettings(S.lsLoc, true);
  $('#ls_body').innerHTML = Object.keys(B.GROUPS).map((g) => `<h2>${esc(lab(B.GROUPS[g]))}</h2>` + Object.keys(FAMILIES).filter((f) => FAMILIES[f].group === g).map((f) => famHTML(f, m)).join('') + B.SETTING_DEFS.filter((d) => d.group === g && !d.hidden && !famOf(d.key)).map((d) => {
    const v = m[d.key];
    return `<div class="card stack"><div class="row between"><b>${esc(lab(d.label))}</b>${v === null || v === undefined ? `<span class="chip warn">${esc(t('need_data'))}</span>` : ''}</div>
      <div class="row"><input id="lv_${d.key}" ${d.kind === 'time' ? 'type="time"' : d.kind === 'number' ? 'inputmode="decimal"' : ''} value="${esc(v === null || v === undefined ? '' : v)}">${d.unit ? `<span class="muted">${esc(d.unit)}</span>` : ''}
      <button class="primary" data-act="ls_save" data-v="${d.key}">${esc(t('save'))}</button></div></div>`; }).join('')).join('');
}
async function saveFamily(f) {
  const F = FAMILIES[f], rows = [];
  for (const i of F.rows) for (const [c, , kind] of F.cols) {
    const key = F.key(i, c), raw = norm(($('#lv_' + key).value || '').trim()); let v = null;
    if (raw !== '') { if (kind === 'number') { v = Number(raw); if (!Number.isFinite(v)) return toast(t('err_price')); } else v = raw; }
    rows.push({ location_id: S.lsLoc, key, value: v, updated_by: S.ctx.profile.id, updated_at: new Date().toISOString() });
  }
  const { error } = await sb.from('location_settings').upsert(rows, { onConflict: 'location_id,key' });
  if (error) return fail(error); delete ENV.byLoc[S.lsLoc]; toast(t('saved')); viewLocSet();
}
async function saveLocSetting(key) {
  const d = B.SETTING_DEFS.find((x) => x.key === key); let raw = norm(($('#lv_' + key).value || '').trim()), v = null;
  if (raw !== '') { if (d.kind === 'number') { v = Number(raw); if (!Number.isFinite(v) || v < 0) return toast(t('err_price')); } else v = raw; }
  const { error } = await sb.from('location_settings').upsert({ location_id: S.lsLoc, key, value: v, updated_by: S.ctx.profile.id, updated_at: new Date().toISOString() }, { onConflict: 'location_id,key' });
  if (error) return fail(error); delete ENV.byLoc[S.lsLoc]; toast(t('saved')); viewLocSet();
}

// ---------- handlers ----------
Object.assign(A.H, {
  sup_new: (a) => { E.supT = { w: a.dataset.w, p: a.dataset.p }; openSheet(`<h2>${esc(lab(SUPX.title))}</h2><div class="stack"><div><label>${esc(lab(SUPX.name))}</label><input id="sn_name" autocomplete="off"></div><div><label>${esc(lab(SUPX.mobile))}</label><input id="sn_mob" inputmode="tel"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="sup_save">${esc(lab(SUPX.save))}</button></div></div>`); },
  sup_save: async () => { const name = ($('#sn_name').value || '').trim(), mob = ($('#sn_mob').value || '').trim(); if (!name) return toast(lab(SUPX.need));
    const patch = { name }; if (mob) patch.mobile = mob; const r = await sb.rpc('save_supplier', { p_id: null, p_patch: patch }); if (r.error) return fail(r.error);
    ENV.sup = (ENV.sup || []).concat([{ id: r.data, name, type_code: null }]); const T0 = E.supT; if (T0) { const o = T0.w === 'c' ? E.check : E.data; setp(o, T0.p, name); setp(o, T0.p + '_id', r.data); touch(); }
    closeSheet(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); },
  openform: (a) => { location.hash = '#/form/' + a.dataset.v; },
  newentry: (a) => { location.hash = '#/entry/new/' + a.dataset.v + '/' + S.formLoc; },
  openentry: (a) => { location.hash = '#/entry/' + a.dataset.v; },
  pick: (a) => { setp(a.dataset.w === 'c' ? E.check : E.data, a.dataset.p, getp(a.dataset.w === 'c' ? E.check : E.data, a.dataset.p) === a.dataset.v ? '' : a.dataset.v); touch(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); },
  addrow: (a) => { const k = a.dataset.t; E.data[k] = E.data[k] || []; E.data[k].push({}); touch(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); },
  delrow: (a) => { const k = a.dataset.t, i = Number(a.dataset.i); (E.data[k] || []).splice(i, 1); touch(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); },
  photo_del: (a) => { const o = a.dataset.w === 'c' ? E.check : E.data, cur = [...(getp(o, a.dataset.p) || [])]; cur.splice(Number(a.dataset.i), 1); setp(o, a.dataset.p, cur.length ? cur : undefined); touch(); const sc = window.scrollY; draw(); window.scrollTo(0, sc); },
  photo_view: async (a) => { const r = await sb.storage.from('photos').createSignedUrl(a.dataset.src, 3600); if (r.data) openSheet(`<img src="${esc(r.data.signedUrl)}" alt="" style="width:100%;border-radius:12px"><button class="full" style="margin-top:10px" data-act="closesheet">${esc(t('done'))}</button>`); },
  e_menu: () => {
    const perms = S.ctx.perms[E.code] || {}, canReq = E.status === 'approved' && (perms.enter || S.ctx.is_owner) && !E.chgPending && B.rule('change_requests_on', true) !== false;
    openSheet(`<h2>${esc(t17('menu_title'))}</h2><div class="stack">
      ${canReq ? `<button class="full" data-act="e_chg_start">${esc(t17('m_chg'))}</button>` : ''}
      ${E.id && (E.status === 'approved' || E.rev > 1) ? `<button class="full" data-act="e_rev">${esc(t17('m_rev'))}${E.rev > 1 ? ' · ' + E.rev : ''}</button>` : ''}
      ${E.id && E.status !== 'draft' && S.ctx.is_owner ? `<button class="full" data-act="e_reopen_m">${esc(t17('m_reopen'))}</button>` : ''}
      ${B.outbox.count() ? `<button class="full" data-act="e_to_outbox">${esc(t17('m_outbox'))} · ${B.outbox.count()}</button>` : ''}
      <button class="full" data-act="closesheet">${esc(t('done'))}</button></div>`); },
  e_chg_start: () => { closeSheet(); E.mode = 'change'; draw(); window.scrollTo(0, 0); },
  e_chg_cancel: () => reloadEntry(E.id),
  e_chg_send: () => {
    const miss = missingRequired();
    if (miss.length) return openSheet(`<h2>${esc(t('missing_title'))}</h2><div class="stack">${miss.map((m) => `<div class="notice bad">${esc(m)}</div>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
    askNote(t17('chg_why'), async (reason) => {
      const flags = [...flagsOf('maker'), ...(E.flags || []).filter((f) => f.src === 'check')];
      const r = await sb.rpc('entry_change_request', { p_entry: E.id, p_reason: reason, p_patch: { data: E.data, flags } });
      if (r.error) return fail17(r.error);
      toast(t17('chg_sent')); await reloadEntry(E.id); }); },
  e_rev: () => { closeSheet(); if (B.showRevisions) B.showRevisions(E.id); },
  e_reopen_m: () => { closeSheet(); askNote(t('reopen'), (n) => reopen(n)); },
  e_to_outbox: () => { closeSheet(); location.hash = '#/outbox'; },
  e_save: () => saveDraft(),
  e_count_save: () => countSave(),
  e_count_peek: () => countPeek(),
  e_pin_sign: (a) => pinSignClick(a.dataset.v),
  e_submit: submit,
  e_approve: () => decide(true),
  e_reject: () => askNote(t('reject'), (n) => decide(false, n)),
  e_reopen: () => askNote(t('reopen'), (n) => reopen(n)),
  note_ok: () => A.noteCb && A.noteCb(),
  e_release: async (a) => { const code = a.dataset.code, reason = ($('#rr_' + code).value || '').trim(); if (!reason) return toast(t('note_needed'));
    if (E.dirty) { const ok = await saveDraft(); if (!ok) return; }
    const { error } = await sb.rpc('request_release', { p_entry: E.id, p_flag: code, p_reason: reason }); if (error) return fail(error); toast(t('release_sent')); await loadReleases(); releaseSheet(); },
  ex_resolve: (a) => askNote(t('resolve'), async (n) => { const { error } = await sb.rpc('resolve_exception', { p_id: Number(a.dataset.v), p_note: n }); if (error) return fail(error); toast(t('saved')); drawExceptions($('#ex_st').value); }),
  rl_decide: async (a) => { const id = Number(a.dataset.v), ok = a.dataset.ok === '1'; const { error } = await sb.rpc('decide_release', { p_id: id, p_approve: ok, p_note: ($('#rn_' + id).value || '').trim() || null }); if (error) return fail(error); toast(t('saved')); viewReleases(); },
  ls_save: (a) => saveLocSetting(a.dataset.v),
  ls_savefam: (a) => saveFamily(a.dataset.v),
});
window.BOS_PAGES = { form: viewFormList, entry: viewEntry, exceptions: viewExceptions, releases: viewReleases, locset: viewLocSet };
B.ENV = ENV; B.loadStatic = loadStatic;
})();
