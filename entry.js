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
  if (!ENV.items) { const r = await sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,sell_price,is_active').order('code'); ENV.items = r.data || []; ENV.byCode = new Map(ENV.items.map((i) => [i.code, i])); }
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
  return { d: E.data, c: E.check, s: E.settings, env: ENV, v: (E.calc && E.calc.v) || {}, cf: !!E.formRow.count_first, num, has, sum, den: (k) => denTotal(getp(E.data, k)), denC: (k) => denTotal(getp(E.check, k)),
    rows: (id) => (E.data[id] || []).map((r) => r || {}), rowsC: (id) => (E.check[id] || []).map((r) => r || {}), me: S.ctx.profile.staff_id, date: E.date, loc: E.loc, wd: weekday(E.date),
    L, lab, money, needs: [] };
}
function recompute() {
  const x = ctxFor(); const out = E.spec.calc ? E.spec.calc(x) : {};
  E.calc = { v: out.v || {}, rows: out.rows || {}, flags: out.flags || [], needs: [...new Set([...(out.needs || [])])] };
}
function flagsOf(src) { return E.calc.flags.filter((f) => (src === 'check' ? f.src === 'check' : f.src !== 'check')); }

// ---------- rendering ----------
const modeEditable = (fd) => (E.mode === 'edit' && (fd.who || 'maker') === 'maker') || (E.mode === 'check' && fd.who === 'checker');
const curVal = (fd, path, w) => getp(w === 'c' ? E.check : E.data, path);
const optsOf = (fd) => (typeof fd.options === 'function' ? fd.options() : fd.options);
function optsHTML(options, cur, code) { if (cur && code && !options.some((o) => o[0] === cur)) { const old = ((ENV.lists && ENV.lists[code]) || []).find((x) => x.value_code === cur); if (old) options = [...options, [old.value_code, rowL(old)]]; } return options.map(([v, l]) => `<option value="${esc(v)}" ${v === cur ? 'selected' : ''}>${esc(lab(l))}</option>`).join(''); }

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
  const canEditStruct = E.mode === 'edit' && !fd.rows;
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
  const inner = sec.fields.map((f) => fieldHTML(f, f.id, f.who === 'checker' ? 'c' : 'd', ed(f), wrap(f))).join('');
  const checker = sec.who === 'checker';
  const body = `<div class="secbody">${inner}</div>`;
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
  if (canMaker) b.push(`<button data-act="e_save">${esc(t('save_draft'))}</button><button class="primary" data-act="e_submit">${esc(t('submit'))}</button>`);
  if (E.mode === 'check') b.push(`<button class="danger" data-act="e_reject">${esc(t('reject'))}</button><button class="primary" data-act="e_approve">${esc(t('approve'))}</button>`);
  if (E.id && st !== 'draft' && (E.created_by === S.ctx.profile.id || S.ctx.is_owner) && !(st === 'approved' && !S.ctx.is_owner)) b.push(`<button data-act="e_reopen">${esc(t('reopen'))}</button>`);
  return b.length ? `<div class="actionbar">${b.join('')}</div>` : '';
}

const PAPER_NO = { id: 'paper_no', type: 'text', label: L('ছাপা নম্বর (কাগজের বই)', 'Printed paper no.', 'ছাপা Number (কাগজের বই)'),
  hint: L('কাগজের ফর্মে ছাপা ক্রমিক নম্বর। একই নম্বর একবারই নেওয়া যায়, আর বাদ পড়া নম্বর ধরা পড়ে।', 'The serial printed on the paper form. A number can be entered once, and missing numbers are audited.', 'কাগজের form এ ছাপা Serial number। একই number একবারই নেওয়া যায়, বাদ পড়া number ধরা পড়ে।') };
function draw() {
  B.curDate = E.date;
  E.shows = {}; E.rshows = {}; recompute();
  const spec = E.spec, head = [PAPER_NO, ...(spec.head || [])].map((f) => fieldHTML(f, f.id, 'd', modeEditable(f), wrap(f))).join('');
  const serial = E.serial ? `${E.code}-${(ENV.locs.find((l) => l.id === E.loc) || {}).code || E.loc}-${E.serial}` : t('new_entry');
  const wdv = lab(WD[weekday(E.date)]);
  const tag = E.settings['daytag_' + weekday(E.date)];
  shell(lab(spec.title), `<datalist id="dl_sup">${(ENV.sup || []).map((x) => `<option value="${esc(x.name)}"></option>`).join('')}</datalist><datalist id="dl_items">${ENV.items.filter((i) => i.is_active).map((i) => `<option value="${esc(i.code)} · ${esc(nm(i))}"></option>`).join('')}</datalist>
    <div class="entry" id="entry">
    <div class="card panel"><div class="row between"><b class="serial">${esc(serial)}</b><span class="chip ${STATUS_CLS[E.status]}">${esc(t('est_' + E.status))}</span></div>
      <div class="row wrap" style="margin-top:6px"><span class="chip">${esc(locName(E.loc))}</span>
      ${E.mode === 'edit' ? `<input type="date" id="e_date" value="${esc(E.date)}" style="width:auto">` : `<span class="chip">${esc(E.date)}</span>`}
      <span class="chip">${esc(wdv)}</span>${tag ? `<span class="chip warn">${esc(t('tag'))}: ${esc(tag)}</span>` : ''}</div>
      ${E.checked_staff ? `<div class="muted" style="font-size:.85rem;margin-top:6px">${esc(t('checked_by'))}: ${esc(staffName(E.checked_staff))}${E.check_note ? ' · ' + esc(E.check_note) : ''}</div>` : ''}
      ${head ? `<div class="stack" style="margin-top:10px">${head}</div>` : ''}</div>
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
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2));
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
function touch() { E.dirty = true; if (!E.id) store.set('bos_tmp_' + E.code + '_' + E.loc, JSON.stringify({ d: E.data, date: E.date })); }
document.addEventListener('input', onEdit);
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
  return miss;
}

// ---------- save / submit / decide ----------
async function ensureLoaded() { await loadStatic(); }
async function saveDraft(note) {
  const flags = flagsOf('maker');
  const { data, error } = await sb.rpc('save_entry', { p_id: E.id || null, p_form: E.code, p_loc: E.loc, p_date: E.date, p_data: E.data, p_flags: flags, p_note: note || null });
  if (error) { if (/note_required/.test(error.message)) { askNote(t('note_overwrite'), (n) => saveDraft(n).then(() => { if (E && E.afterSave) { const f = E.afterSave; E.afterSave = null; f(); } })); return false; } fail(error); return false; }
  if (!E.id) { E.id = data.id; E.serial = data.serial; store.set('bos_tmp_' + E.code + '_' + E.loc, ''); history.replaceState(null, '', '#/entry/' + E.id); }
  E.dirty = false; E.created_by = E.created_by || S.ctx.profile.id; toast(t('saved')); return true;
}
function askNote(title, cb, required = true) {
  openSheet(`<h2>${esc(title)}</h2><textarea id="note_in" rows="3" placeholder="${esc(t('reason_note'))}"></textarea>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(t('cancel'))}</button><button class="primary full" data-act="note_ok">${esc(t('confirm'))}</button></div>`);
  A.noteCb = () => { const v = ($('#note_in').value || '').trim(); if (required && !v) return toast(t('note_needed')); closeSheet(); cb(v); };
}
async function submit() {
  if (E.dirty || !E.id) { const ok = await saveDraft(); if (!ok) { E.afterSave = submit; return; } }
  const miss = missingRequired();
  if (miss.length) return openSheet(`<h2>${esc(t('missing_title'))}</h2><div class="stack">${miss.map((m) => `<div class="notice bad">${esc(m)}</div>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(t('done'))}</button>`);
  const { error } = await sb.rpc('submit_entry', { p_id: E.id });
  if (error) { if (/red_blocked/.test(error.message)) return releaseSheet(); return fail(error); }
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
  if (error) return /own entry/.test(error.message) ? toast(t('err_own_entry')) : fail(error);
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
  E = { code, spec, formRow: fr.data, loc, date: today(), status: 'draft', mode: 'edit', data: {}, check: {}, flags: [], settings, serial: null, id: null, dirty: false, created_by: S.ctx.profile.id, openSecs: new Set(), releases: {} };
  try { const tmp = JSON.parse(store.get('bos_tmp_' + code + '_' + loc) || 'null'); if (tmp && tmp.d && Object.keys(tmp.d).length) { E.data = tmp.d; E.date = tmp.date || E.date; E.dirty = true; toast(t('restored')); } } catch (e) { /* ignore */ }
  if (spec.init) spec.init(ctxFor(), E.data);
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
    created_by: e.created_by, checked_staff: e.checked_staff, check_note: e.check_note, openSecs: keep, releases: {} };
  await loadReleases(); draw();
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
  const r = await sb.from('entries').select('id,serial,entry_date,status,flags,created_staff,checked_staff,paper_no:data->>paper_no').eq('form_code', code).eq('location_id', S.formLoc).order('entry_date', { ascending: false }).order('serial', { ascending: false }).limit(60);
  if (r.error) return fail(r.error);
  const lc = (ENV.locs.find((l) => l.id === S.formLoc) || {}).code || '';
  $('#fl_body').innerHTML = r.data.map((e) => {
    const reds = (e.flags || []).filter((f) => f.level === 'red').length, ys = (e.flags || []).filter((f) => f.level === 'yellow').length;
    return `<div class="card item" data-act="openentry" data-v="${e.id}"><div><div class="nm">${esc(code)}-${esc(lc)}-${e.serial}</div><div class="muted" style="font-size:.85rem">${esc(e.entry_date)} · ${esc(staffName(e.created_staff))}${e.paper_no ? ' · № ' + esc(e.paper_no) : ''}</div></div>
      <div class="row"><span class="chip ${STATUS_CLS[e.status]}">${esc(t('est_' + e.status))}</span>${reds ? `<span class="chip bad">● ${reds}</span>` : ''}${ys ? `<span class="chip warn">▲ ${ys}</span>` : ''}</div></div>`; }).join('') || `<p class="muted center">${esc(t('no_entries'))}</p>`;
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
  e_save: () => saveDraft(),
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
