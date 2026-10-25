/* Islamia BOS · Verified reports, Stage 1 (#/reports131). NEW file, sweets business. Server: supabase/phase131.sql (rule rpt131_on, default OFF).
   Seven read-only reports, each one server call (the browser only sends filters and draws what comes back):
     rpt131_sales        sales net of voids and returns by day / week / month / outlet / hour / weekday / staff / sale type / payment method
     rpt131_sales_recon  every sale and return with its status (posted / unposted / void / reversed / not reversed) and the tie-out to the books
     rpt131_item_profit  item / category / outlet profit with the real ledger cost (cost columns only for people who may see cost)
     rpt131_stock_recon  opening + in - out + adjustments = closing, check and variance per item and place
     rpt131_wastage      wastage by reason / item / outlet / day / status / document
     rpt131_cash_close   cash book and day close per outlet and day
     rpt131_ageing       receivable and payable ageing (age buckets come from the rule report_aging_buckets) with the books tie-out
   Every answer carries generated_at, the filters used, notes and totals worked out on the server over ALL matching rows. Empty = "data needed", never zeros.
   Drill-down: a row opens the next level (day -> documents, document -> the receipt, stock line -> ledger rows, customer / supplier -> ledger).
   CSV export (BOM, filters and time in the footer lines) is logged on the server through rpt131_log_export. Nothing here is a business number. data-act prefix: r131_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S, esc, toast, fail, shell, openSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const monthStart = (iso) => iso.slice(0, 8) + '01';
const monthEnd = (iso) => { const d = new Date(iso.slice(0, 8) + '01T12:00:00Z'); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0); return d.toISOString().slice(0, 10); };
const jget = (k, d) => { try { const v = JSON.parse(A.store.get(k) || 'null'); return v == null ? d : v; } catch (e) { return d; } };
const jset = (k, v) => { try { A.store.set(k, JSON.stringify(v)); } catch (e) { /* storage blocked */ } };
const fmt2 = (n) => Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtQ = (n) => Number(n).toLocaleString('en-US', { maximumFractionDigits: 4 });

const X = {
  title: L('যাচাই করা রিপোর্ট', 'Verified reports', 'Verified report'),
  intro: L('প্রতিটি হিসাব খাতার (জার্নাল) সাথে মেলানো। খালি জায়গা মানে "তথ্য দরকার" — শূন্য নয়।', 'Every figure is tied to the books (journal). A dash means "data needed", not zero.', 'প্রতিটি হিসাব books-এর সাথে মেলানো। "—" মানে data দরকার, শূন্য নয়।'),
  off: L('এই রিপোর্টগুলো এখন বন্ধ। মালিক সুইচবোর্ড থেকে "rpt131_on" চালু করলে খুলবে।', 'These reports are switched off. The owner turns on "rpt131_on" in the switchboard.', 'এই report এখন বন্ধ। মালিক switchboard-এ "rpt131_on" চালু করলে খুলবে।'),
  noperm: L('এই রিপোর্ট দেখার অনুমতি নেই', 'You are not allowed to see this report', 'এই report দেখার permission নেই'),
  report: L('রিপোর্ট', 'Report', 'Report'), filters: L('ফিল্টার', 'Filters', 'Filter'), from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), asof: L('এই ডেট পর্যন্ত', 'As of', 'As of'),
  outlet: L('আউটলেট', 'Outlet', 'Outlet'), alloutlets: L('সব (আমার)', 'All (mine)', 'সব (আমার)'), group: L('ভাগ করুন', 'Group by', 'Group by'), status: L('স্ট্যাটাস', 'Status', 'Status'),
  category: L('ক্যাটাগরি', 'Category', 'Category'), anycat: L('সব ক্যাটাগরি', 'All categories', 'সব category'), item: L('আইটেম', 'Item', 'Item'), itemph: L('কোড বা নাম লিখুন…', 'Type code or name…', 'Code বা নাম লিখুন…'),
  search: L('খুঁজুন', 'Search', 'Search'), searchph: L('এই ফলাফলে খুঁজুন…', 'Search these results…', 'এই result-এ খুঁজুন…'), apply: L('দেখান', 'Show', 'Show'), clear: L('মুছুন', 'Clear', 'Clear'),
  p_today: L('আজ', 'Today', 'Today'), p_yday: L('গতকাল', 'Yesterday', 'Yesterday'), p_7: L('৭ দিন', 'Last 7 days', 'Last 7 days'), p_month: L('এই মাস', 'This month', 'This month'), p_last: L('গত মাস', 'Last month', 'Last month'),
  issues: L('শুধু সমস্যা', 'Only problems', 'Only problems'), kind: L('ধরন', 'Kind', 'Kind'), recv: L('বাকি (গ্রাহক)', 'Receivable (customers)', 'বাকি (customer)'), pay: L('পাওনা (সরবরাহকারী)', 'Payable (suppliers)', 'পাওনা (supplier)'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), empty: L('তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই', 'Data needed: nothing matches this period / these filters', 'Data দরকার: এই সময়/ফিল্টারে কিছু নেই'),
  total: L('মোট', 'Total', 'Total'), page: L('পাতা', 'Page', 'Page'), of: L('মোট সারি', 'rows', 'rows'), prev: L('আগে', 'Prev', 'Prev'), next: L('পরে', 'Next', 'Next'),
  csv: L('CSV', 'CSV', 'CSV'), print: L('প্রিন্ট', 'Print', 'Print'), exp_busy: L('তৈরি হচ্ছে…', 'Preparing…', 'তৈরি হচ্ছে…'), exp_done: L('ফাইল তৈরি', 'File ready', 'File তৈরি'),
  exp_lock: L('এক্সপোর্টের অনুমতি নেই', 'Export is not allowed for you', 'Export-এর permission নেই'),
  gen: L('তৈরি', 'Generated', 'Generated'), by: L('যিনি বের করেছেন', 'By', 'By'), flt: L('ফিল্টার', 'Filters', 'Filters'), tie: L('খাতার সাথে মিল', 'Tie-out to the books', 'Books-এর সাথে মিল'),
  nodrill: L('এই সারিতে আর গভীরে যাওয়া যায় না', 'No deeper view for this row', 'এই row-তে আর deeper view নেই'), tapdrill: L('সারিতে চাপলে বিস্তারিত', 'Tap a row for details', 'Row-তে চাপলে details'),
  costhid: L('খরচের কলাম আপনার জন্য লুকানো', 'Cost columns are hidden for you', 'Cost column আপনার জন্য লুকানো'), close: L('বন্ধ', 'Close', 'Close'),
  e_range: L('সময়ের পরিসর ঠিক নয় বা খুব বড়', 'The date range is not valid or too long', 'Date range ঠিক নয় বা খুব বড়'), e_loc: L('এই লোকেশন আপনার জন্য নয়', 'That place is not open to you', 'এই location আপনার জন্য নয়'),
  e_off: L('ইন্টারনেট নেই — রিপোর্ট দেখতে অনলাইন লাগবে', 'You are offline — reports need a connection', 'Internet নেই — report দেখতে online লাগবে'),
  e_nope: L('এই রিপোর্টের অনুমতি নেই', 'Not allowed for this report', 'এই report-এর permission নেই'), e_gen: L('রিপোর্ট আনা যায়নি', 'The report could not be loaded', 'Report আনা যায়নি'),
  open: L('খুলুন', 'Open', 'Open'), ledger: L('লেজার', 'Ledger', 'Ledger'), nodata: L('কিছু নেই', 'Nothing', 'কিছু নেই'),
};
const T = (k) => lab(X[k]);

// ---- the seven reports
const GROUPS = {
  day: L('দিন', 'Day', 'Day'), week: L('সপ্তাহ', 'Week', 'Week'), month: L('মাস', 'Month', 'Month'), outlet: L('আউটলেট', 'Outlet', 'Outlet'), hour: L('ঘণ্টা', 'Hour', 'Hour'), weekday: L('বার', 'Weekday', 'Weekday'),
  staff: L('কর্মী', 'Staff', 'Staff'), sale_type: L('খুচরা/পাইকারি', 'Retail / wholesale', 'Retail / wholesale'), pay_mode: L('পেমেন্ট পদ্ধতি', 'Payment method', 'Payment method'),
  item: L('আইটেম', 'Item', 'Item'), category: L('ক্যাটাগরি', 'Category', 'Category'), reason: L('কারণ', 'Reason', 'Reason'), status: L('স্ট্যাটাস', 'Status', 'Status'), doc: L('প্রতিটি এন্ট্রি', 'Each entry', 'Each entry'),
};
const ST = {
  all: L('সব', 'All', 'All'), posted: L('খাতায় আছে', 'Posted', 'Posted'), unposted: L('খাতায় যায়নি', 'Unposted', 'Unposted'), void: L('বাতিল', 'Void', 'Void'), reversed: L('বাতিল ও খাতায় উল্টানো', 'Reversed', 'Reversed'),
  void_not_reversed: L('বাতিল কিন্তু খাতায় আছে', 'Void, still in books', 'Void, খাতায় আছে'), refunded: L('ফেরত আছে', 'Refunded', 'Refunded'), problems: L('সমস্যা', 'Problems', 'Problems'),
  pending: L('অপেক্ষায়', 'Pending', 'Pending'), rejected: L('না-মঞ্জুর', 'Rejected', 'Rejected'), cancelled: L('বাতিল করা', 'Cancelled', 'Cancelled'),
  done: L('সম্পন্ন', 'Done', 'Done'), none: L('নেই', 'None', 'None'), partial: L('আংশিক', 'Partial', 'Partial'), full: L('পুরো', 'Full', 'Full'),
  ok: L('ঠিক', 'OK', 'OK'), variance: L('ভেরিয়েন্স', 'Variance', 'Variance'), unbalanced: L('মেলেনি', 'Unbalanced', 'Unbalanced'), negative: L('ঋণাত্মক', 'Negative', 'Negative'),
  books_differ: L('খাতার সাথে পার্থক্য', 'Differs from books', 'Books-এর সাথে পার্থক্য'), no_sheet: L('শিট নেই', 'No sheet', 'No sheet'), short: L('কম', 'Short', 'Short'), over: L('বেশি', 'Over', 'Over'),
  books_not_reversed: L('বাতিল, খাতায় উল্টানো হয়নি', 'Void, not reversed in books', 'Void, books-এ উল্টানো হয়নি'), amount_differs: L('অঙ্ক মেলেনি', 'Amount differs', 'Amount মেলেনি'),
  sale: L('বিক্রি', 'Sale', 'Sale'), return: L('ফেরত', 'Return', 'Return'),
};
const stLab = (v) => (v == null || v === '' ? '' : ST[v] ? lab(ST[v]) : String(v));
const REPORTS = [
  { key: 'rpt131_sales', grp: 'sales', name: L('বিক্রি (বাতিল ও ফেরত বাদে)', 'Sales, net of voids and returns', 'Sales (void ও return বাদে)'), fields: ['range', 'outlet', 'group'],
    groups: ['day', 'week', 'month', 'outlet', 'hour', 'weekday', 'staff', 'sale_type', 'pay_mode'], defg: 'day' },
  { key: 'rpt131_sales_recon', grp: 'sales', name: L('বিক্রির স্ট্যাটাস ও খাতার মিল', 'Sales status and books tie-out', 'Sales status ও books-এর মিল'), fields: ['range', 'outlet', 'status'],
    statuses: ['all', 'posted', 'unposted', 'void', 'reversed', 'void_not_reversed', 'refunded', 'problems'], defs: 'all', maxDays: 92 },
  { key: 'rpt131_item_profit', grp: 'profit', name: L('আইটেম / ক্যাটাগরি / আউটলেট লাভ', 'Item / category / outlet profit', 'Item / category / outlet profit'), fields: ['range', 'outlet', 'group', 'category', 'item'],
    groups: ['item', 'category', 'outlet'], defg: 'item' },
  { key: 'rpt131_stock_recon', grp: 'stock', name: L('স্টক মিলানো', 'Stock reconciliation', 'Stock মিলানো'), fields: ['range', 'outlet', 'category', 'item', 'issues'] },
  { key: 'rpt131_wastage', grp: 'stock', name: L('অপচয়', 'Wastage', 'Wastage'), fields: ['range', 'outlet', 'group', 'status', 'category', 'item'],
    groups: ['reason', 'item', 'outlet', 'day', 'status', 'doc'], defg: 'reason', statuses: ['all', 'posted', 'pending', 'rejected', 'cancelled', 'reversed'], defs: 'all' },
  { key: 'rpt131_cash_close', grp: 'cash', name: L('ক্যাশ বই ও দিনশেষ', 'Cash book and day close', 'Cash book ও day close'), fields: ['range', 'outlet'] },
  { key: 'rpt131_ageing', grp: 'customers', name: L('বাকি ও পাওনার বয়স', 'Receivable and payable ageing', 'বাকি ও পাওনার age'), fields: ['kind', 'asof', 'outlet'] },
];
const BY = Object.fromEntries(REPORTS.map((r) => [r.key, r]));

const D = { cat: null, key: jget('r131_key', 'rpt131_sales'), f: null, res: null, busy: false, cats: null, locs: [], pick: [], err: '' };
function defaults(key) {
  const r = BY[key], t = today();
  return { from: monthStart(t), to: t, asof: t, loc: '', group: r.defg || '', status: r.defs || 'all', category: '', item: '', itemLabel: '', issues: false, kind: 'receivable', search: '', sort: '', page: 1, size: 50 };
}
D.f = defaults(D.key);

// ---- helpers for cells
const locName = (l) => lab(L(l.name_bn, l.name_en || l.name_bn, l.name_mix || l.name_bn));
const rowLabel = (r) => lab(L(r.label_bn || r.label_en || r.dim || '', r.label_en || r.label_bn || r.dim || '', r.label_en || r.label_bn || r.dim || ''));
function cellVal(c, r) {
  const k = c.k;
  if (k === 'label') return rowLabel(r);
  if (k === 'outlet') return lab(L(r.outlet_bn || r.outlet_en || '', r.outlet_en || r.outlet_bn || '', r.outlet_en || r.outlet_bn || ''));
  if (k === 'item') return (r.item_code ? r.item_code + ' · ' : '') + lab(L(r.item_bn || r.item_en || '', r.item_en || r.item_bn || '', r.item_en || r.item_bn || ''));
  if (k === 'name') return r.name != null ? r.name : lab(L(r.name_bn || r.name_en || '', r.name_en || r.name_bn || '', r.name_en || r.name_bn || ''));
  if (k === 'doc_type') return stLab(r.doc_type);
  return r[k];
}
const SORTKEY = { label: 'dim', outlet: 'outlet_en', item: 'item_code', name: 'name', doc_type: 'doc_type' };
function cellHTML(c, r) {
  const v = cellVal(c, r);
  if (v == null || v === '') return '<span class="muted" title="data needed">—</span>';
  switch (c.t) {
    case 'money': return fmt2(v);
    case 'int': return String(Math.round(Number(v)));
    case 'qty': return fmtQ(v);
    case 'pct': return fmt2(v) + '%';
    case 'status': return `<span class="r131-chip r131-${esc(String(v).replace(/[^a-z_]/g, ''))}">${esc(stLab(v))}</span>`;
    default: return esc(String(v));
  }
}
const visibleCols = (res) => (res.columns || []).filter((c) => !(c.cost && res.cost_visible === false));

// ---- data
async function loadCatalog() {
  const r = await sb.rpc('rpt131_catalog');
  if (r.error) { D.cat = { enabled: false, reports: [], missing: true }; return; }
  D.cat = r.data || { enabled: false, reports: [] };
}
async function loadCats() {
  if (D.cats) return;
  try { const r = await sb.from('items').select('category').not('category', 'is', null).limit(5000); const s = new Set((r.data || []).map((x) => x.category).filter(Boolean)); D.cats = [...s].sort(); }
  catch (e) { D.cats = []; }
}
function params(page, size) {
  const f = D.f, r = BY[D.key], p = {};
  const locs = f.loc ? [Number(f.loc)] : null;
  const base = { p_search: f.search || null, p_sort: f.sort || null, p_page: page, p_size: size };
  switch (D.key) {
    case 'rpt131_sales': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs, p_group: f.group });
    case 'rpt131_sales_recon': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs, p_status: f.status });
    case 'rpt131_item_profit': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs, p_group: f.group, p_category: f.category || null, p_item: f.item || null });
    case 'rpt131_stock_recon': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs, p_category: f.category || null, p_item: f.item || null, p_issues_only: !!f.issues });
    case 'rpt131_wastage': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs, p_group: f.group, p_status: f.status, p_category: f.category || null, p_item: f.item || null });
    case 'rpt131_cash_close': return Object.assign(base, { p_from: f.from, p_to: f.to, p_locs: locs });
    default: return Object.assign(base, { p_kind: f.kind, p_as_of: f.kind === 'receivable' ? f.asof : null, p_locs: locs });
  }
}
function errText(e) {
  const m = String((e && e.message) || e || '');
  if (/not allowed for this location/.test(m)) return T('e_loc');
  if (/bad_range/.test(m)) return T('e_range');
  if (/not allowed/.test(m)) return T('e_nope');
  if (/Failed to fetch|NetworkError|offline/i.test(m)) return T('e_off');
  return T('e_gen');
}
async function run() {
  if (D.busy) return;
  D.busy = true; D.err = ''; paintBusy();
  try {
    const r = await sb.rpc(D.key, params(D.f.page, D.f.size));
    if (r.error) throw r.error;
    D.res = r.data;
  } catch (e) { D.res = null; D.err = errText(e); }
  D.busy = false; paintResult();
}

// ---- drawing
const CSS = `.r131 .row{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end}.r131 .row>div{flex:1 1 140px;min-width:120px}.r131 select,.r131 input{min-height:44px;width:100%;box-sizing:border-box}
.r131 button{min-height:44px}.r131-wrap{overflow-x:auto;max-width:100%;border:1px solid var(--line,#0002);border-radius:10px}.r131-t{border-collapse:collapse;width:100%;font-size:12px}
.r131-t th,.r131-t td{padding:8px 8px;border-bottom:1px solid var(--line,#0001);text-align:right;white-space:nowrap}.r131-t th:first-child,.r131-t td:first-child{text-align:left;position:sticky;left:0;background:var(--card,#fff)}
.r131-t th{cursor:pointer;font-weight:600}.r131-t tr.r131-row{cursor:pointer}.r131-t tfoot td{font-weight:700;border-top:2px solid var(--line,#0003)}.r131-chip{display:inline-block;padding:1px 8px;border-radius:99px;background:#0001;font-size:11px}
.r131-unposted,.r131-books_differ,.r131-void_not_reversed,.r131-books_not_reversed,.r131-amount_differs,.r131-variance,.r131-unbalanced,.r131-short,.r131-no_sheet,.r131-pending{background:#f5a62333}.r131-posted,.r131-ok{background:#2e9e5b22}
.r131-kv{display:grid;grid-template-columns:1fr auto;gap:2px 12px;font-size:13px}.r131-kv b{text-align:right}.r131-foot{font-size:12px}.r131 .tap{min-height:44px;padding:0 14px}
@media print{.r131 .noprint{display:none!important}}`;
function opts(list, sel, labf) { return list.map((v) => `<option value="${esc(v)}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(labf(v))}</option>`).join(''); }
function filtersHTML() {
  const r = BY[D.key], f = D.f, has = (k) => r.fields.includes(k);
  const out = [];
  if (has('range')) out.push(`<div><label for="r131_from">${esc(T('from'))}</label><input id="r131_from" type="date" value="${esc(f.from)}"></div><div><label for="r131_to">${esc(T('to'))}</label><input id="r131_to" type="date" value="${esc(f.to)}"></div>`);
  if (has('asof')) out.push(`<div><label for="r131_asof">${esc(T('asof'))}</label><input id="r131_asof" type="date" value="${esc(f.asof)}" ${f.kind === 'payable' ? 'disabled' : ''}></div>`);
  if (has('kind')) out.push(`<div><label for="r131_kind">${esc(T('kind'))}</label><select id="r131_kind"><option value="receivable" ${f.kind === 'receivable' ? 'selected' : ''}>${esc(T('recv'))}</option><option value="payable" ${f.kind === 'payable' ? 'selected' : ''}>${esc(T('pay'))}</option></select></div>`);
  if (has('outlet')) out.push(`<div><label for="r131_loc">${esc(T('outlet'))}</label><select id="r131_loc"><option value="">${esc(T('alloutlets'))}</option>${D.locs.map((l) => `<option value="${esc(l.id)}" ${String(l.id) === String(f.loc) ? 'selected' : ''}>${esc(locName(l))}</option>`).join('')}</select></div>`);
  if (has('group')) out.push(`<div><label for="r131_group">${esc(T('group'))}</label><select id="r131_group">${opts(r.groups, f.group, (v) => lab(GROUPS[v]))}</select></div>`);
  if (has('status')) out.push(`<div><label for="r131_status">${esc(T('status'))}</label><select id="r131_status">${opts(r.statuses, f.status, stLab)}</select></div>`);
  if (has('category')) out.push(`<div><label for="r131_cat">${esc(T('category'))}</label><select id="r131_cat"><option value="">${esc(T('anycat'))}</option>${opts(D.cats || [], f.category, (v) => v)}</select></div>`);
  if (has('item')) out.push(`<div><label for="r131_item">${esc(T('item'))}</label>${f.item ? `<div class="row" style="flex-wrap:nowrap"><span class="r131-chip" style="flex:1;padding:10px 12px">${esc(f.itemLabel)}</span><button class="tap" data-act="r131_itemx" aria-label="${esc(T('clear'))}">✕</button></div>` : `<input id="r131_item" autocomplete="off" placeholder="${esc(T('itemph'))}"><div id="r131_pick"></div>`}</div>`);
  if (has('issues')) out.push(`<div><label for="r131_issues">${esc(T('issues'))}</label><select id="r131_issues"><option value="0" ${f.issues ? '' : 'selected'}>${esc(lab(ST.all))}</option><option value="1" ${f.issues ? 'selected' : ''}>${esc(T('issues'))}</option></select></div>`);
  return out.join('');
}
function presets() {
  const r = BY[D.key]; if (!r.fields.includes('range')) return '';
  const b = (k, t) => `<button class="tap" data-act="r131_preset" data-v="${k}">${esc(T(t))}</button>`;
  return `<div class="row" style="margin:6px 0">${b('today', 'p_today')}${b('yday', 'p_yday')}${b('7', 'p_7')}${b('month', 'p_month')}${b('last', 'p_last')}</div>`;
}
function paintAll() {
  const el = $('#r131_body'); if (!el) return;
  const cat = D.cat || { enabled: false, reports: [] };
  const allowed = new Set((cat.reports || []).filter((x) => x.allowed).map((x) => x.key));
  const sel = REPORTS.map((r) => `<option value="${r.key}" ${r.key === D.key ? 'selected' : ''} ${allowed.size && !allowed.has(r.key) ? 'disabled' : ''}>${esc(lab(r.name))}${allowed.size && !allowed.has(r.key) ? ' 🔒' : ''}</option>`).join('');
  el.innerHTML = `<div class="r131">
    <p class="muted">${esc(T('intro'))}</p>
    ${cat.enabled === false ? `<div class="card" id="r131_off"><p>${esc(T('off'))}</p></div>` : ''}
    <div><label for="r131_key">${esc(T('report'))}</label><select id="r131_key">${sel}</select></div>
    <details open data-ctl="off" class="card"><summary><b>${esc(T('filters'))}</b></summary>${presets()}<div class="row" id="r131_filters">${filtersHTML()}</div>
      <div class="row" style="margin-top:8px"><div style="flex:3 1 200px"><label for="r131_q">${esc(T('search'))}</label><input id="r131_q" type="search" autocomplete="off" placeholder="${esc(T('searchph'))}" value="${esc(D.f.search)}"></div>
      <div style="flex:1 1 100px"><button class="full primary" data-act="r131_go">${esc(T('apply'))}</button></div></div></details>
    <div id="r131_res"><p class="muted">${esc(T('loading'))}</p></div></div>`;
  paintResult();
}
function paintBusy() { const el = $('#r131_res'); if (el) el.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`; }
function noteText(n) { return lab(L(n.text_bn || n.text_en || '', n.text_en || n.text_bn || '', n.text_en || n.text_bn || '')); }
function fltText(res) {
  const f = res.filters || {}, parts = [];
  if (f.from) parts.push(`${f.from} → ${f.to}`);
  if (f.as_of) parts.push(`${T('asof')} ${f.as_of}`);
  if (f.kind) parts.push(f.kind === 'payable' ? T('pay') : T('recv'));
  const loc = D.locs.find((l) => String(l.id) === String(D.f.loc)); parts.push(`${T('outlet')}: ${loc ? locName(loc) : T('alloutlets')}`);
  if (f.group) parts.push(`${T('group')}: ${GROUPS[f.group] ? lab(GROUPS[f.group]) : f.group}`);
  if (f.status && f.status !== 'all') parts.push(`${T('status')}: ${stLab(f.status)}`);
  if (f.category) parts.push(`${T('category')}: ${f.category}`);
  if (f.item) parts.push(`${T('item')}: ${D.f.itemLabel || f.item}`);
  if (f.issues_only) parts.push(T('issues'));
  if (f.search) parts.push(`${T('search')}: ${f.search}`);
  return parts.join(' · ');
}
function genText(res) {
  let at = ''; try { at = new Date(res.generated_at).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', hour12: false }); } catch (e) { at = String(res.generated_at || ''); }
  return `${T('gen')}: ${at}${res.generated_by ? ' · ' + T('by') + ': ' + res.generated_by : ''}`;
}
function tieHTML(res) {
  const t = res.tie_out, s = res.summary; const kv = [];
  const add = (k, v, tx) => { if (v !== undefined && v !== null) kv.push(`<span>${esc(tx)}</span><b>${typeof v === 'number' ? fmt2(v) : esc(v)}</b>`); };
  const E = (en, bn, mix) => lab(L(bn, en, mix || en));
  if (res.report === 'rpt131_sales_recon' && t) {
    add('r', t.register_net_total, E('Register (sales − returns)', 'রেজিস্টার (বিক্রি − ফেরত)')); add('b', t.docs_books_net_total, E('Books, by document', 'খাতা (ডকুমেন্ট ধরে)')); add('j', t.journal_by_entry_date, E('Journal, by entry date', 'জার্নাল (এন্ট্রির তারিখ ধরে)'));
    add('u', t.unposted_value, E('Not yet in the books', 'খাতায় যায়নি')); add('n', t.not_reversed_docs, E('Void but still in the books (documents)', 'বাতিল অথচ খাতায় আছে (সংখ্যা)')); add('g', t.explained_gap, E('Register − books', 'রেজিস্টার − খাতা'));
  } else if (res.report === 'rpt131_ageing' && t) {
    add('1', t.register_dues, E('Register dues', 'রেজিস্টারে বাকি')); add('2', t.advances, E('Advances', 'অগ্রিম')); add('3', t.register_net, E('Register net', 'রেজিস্টার নিট')); add('4', t.books_receivable, E('Books: receivable', 'খাতায় বাকি'));
    add('5', t.register_open, E('Register: open bills', 'রেজিস্টারে খোলা বিল')); add('6', t.books_payable, E('Books: payable', 'খাতায় পাওনা')); add('7', t.gap, E('Gap', 'পার্থক্য'));
    add('8', t.unposted_bills, E('Unposted bills', 'খাতায় যায়নি এমন বিল')); add('9', t.unposted_value, E('Unposted bills value', 'টাকা')); add('10', t.unposted_collections_value, E('Unposted collections', 'খাতায় যায়নি এমন আদায়'));
    add('11', t.unexplained, E('Unexplained', 'ব্যাখ্যাহীন'));
  } else if (res.report === 'rpt131_wastage' && t) {
    add('1', t.posted_value, E('Posted value (register)', 'পোস্ট করা দাম')); add('2', t.books_wastage_loss, E('Wastage loss in the books', 'খাতায় অপচয় খরচ')); add('3', t.gap, E('Gap', 'পার্থক্য'));
  } else if (res.report === 'rpt131_cash_close' && s) {
    add('1', s.opening_total, E('Opening cash (books)', 'শুরুর ক্যাশ (খাতা)')); add('2', s.net_movement, E('Net movement', 'নিট নড়াচড়া')); add('3', s.closing_total, E('Closing cash (books)', 'শেষ ক্যাশ (খাতা)'));
  } else if (res.report === 'rpt131_stock_recon' && s) {
    add('1', s.lines, E('Lines', 'লাইন')); add('2', s.unbalanced, E('Unbalanced', 'মেলেনি')); add('3', s.with_variance, E('With variance', 'ভেরিয়েন্স আছে'));
  }
  if (res.report === 'rpt131_sales_recon' && s && s.by_status) {
    Object.keys(s.by_status).sort().forEach((k) => { const [st, ty] = k.split('/'); const v = s.by_status[k]; kv.push(`<span>${esc(stLab(st))} · ${esc(stLab(ty))} (${v.docs})</span><b>${fmt2(v.register_net)}${v.books_net != null ? ' / ' + fmt2(v.books_net) : ''}</b>`); });
  }
  return kv.length ? `<details open data-ctl="off" class="card"><summary><b>${esc(T('tie'))}</b></summary><div class="r131-kv">${kv.join('')}</div></details>` : '';
}
function paintResult() {
  const el = $('#r131_res'); if (!el) return;
  if (D.err) { el.innerHTML = `<div class="card"><p class="bad" role="alert">${esc(D.err)}</p><button class="tap" data-act="r131_go">${esc(T('apply'))}</button></div>`; return; }
  const res = D.res; if (!res) { el.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`; return; }
  if (res.off) { el.innerHTML = `<div class="card"><p>${esc(T('off'))}</p></div>`; return; }
  const cols = visibleCols(res), rows = res.rows || [], notes = (res.notes || []).map((n) => `<li>${esc(noteText(n))}</li>`).join('');
  const sortSpec = String(res.sort || D.f.sort || '').split(':'), sk = sortSpec[0], sd = sortSpec[1];
  const th = cols.map((c) => { const key = SORTKEY[c.k] || c.k; return `<th data-act="r131_sort" data-k="${esc(key)}" title="${esc(lab(L(c.bn, c.en, c.en)))}">${esc(lab(L(c.bn, c.en, c.en)))}${sk === key ? (sd === 'asc' ? ' ▲' : ' ▼') : ''}</th>`; }).join('');
  const body = rows.map((r, i) => `<tr class="r131-row" data-act="r131_drill" data-i="${i}">${cols.map((c) => `<td>${cellHTML(c, r)}</td>`).join('')}</tr>`).join('');
  const tot = res.totals; const foot = tot ? `<tfoot><tr>${cols.map((c, i) => `<td>${i === 0 ? esc(T('total')) : c.sum ? (tot[c.k] == null ? '<span class="muted">—</span>' : (c.t === 'int' ? String(Math.round(Number(tot[c.k]))) : fmt2(tot[c.k]))) : ''}</td>`).join('')}</tr></tfoot>` : '';
  const pages = Math.max(1, Math.ceil((res.row_count || 0) / (res.size || 50)));
  el.innerHTML = `${tieHTML(res)}
    ${res.data_needed ? `<div class="card"><p>${esc(T('empty'))}</p></div>` : `<div class="r131-wrap" tabindex="0"><table class="r131-t"><thead><tr>${th}</tr></thead><tbody>${body}</tbody>${foot}</table></div>
    <div class="row noprint" style="margin-top:8px;align-items:center"><button class="tap" data-act="r131_page" data-d="-1" ${res.page <= 1 ? 'disabled' : ''}>◀ ${esc(T('prev'))}</button>
      <div class="muted center">${esc(T('page'))} ${res.page} / ${pages} · ${res.row_count} ${esc(T('of'))}</div><button class="tap" data-act="r131_page" data-d="1" ${res.has_more ? '' : 'disabled'}>${esc(T('next'))} ▶</button></div>
    <p class="muted noprint r131-foot">${esc(T('tapdrill'))}</p>`}
    <div class="row noprint"><button class="tap" data-act="r131_csv">${esc(T('csv'))}</button><button class="tap" data-act="r131_print">${esc(T('print'))}</button></div>
    ${res.cost_visible === false && (res.columns || []).some((c) => c.cost) ? `<p class="muted r131-foot">${esc(T('costhid'))}</p>` : ''}
    ${notes ? `<ul class="muted r131-foot">${notes}</ul>` : ''}
    <p class="muted r131-foot" id="r131_stamp">${esc(genText(res))}<br>${esc(T('flt'))}: ${esc(fltText(res))}</p>`;
}

// ---- drill-down
function goReport(key, patch) {
  const keep = { from: D.f.from, to: D.f.to, loc: D.f.loc };
  D.key = key; jset('r131_key', key); D.f = Object.assign(defaults(key), keep, patch || {}); D.res = null; D.err = '';
  if (key === 'rpt131_sales_recon') { const span = (new Date(D.f.to) - new Date(D.f.from)) / 864e5; if (span > 92) D.f.from = addDays(D.f.to, -92); }
  paintAll(); run();
}
function detailSheet(title, pairs) {
  openSheet(`<h3>${esc(title)}</h3><div class="r131-kv">${pairs.filter((p) => p[1] != null && p[1] !== '').map((p) => `<span>${esc(p[0])}</span><b>${esc(p[1])}</b>`).join('')}</div>`);
}
async function ledgerSheet(title, rpc, args, cols) {
  openSheet(`<h3>${esc(title)}</h3><p class="muted">${esc(T('loading'))}</p>`);
  const r = await sb.rpc(rpc, args);
  const rows = (r.data || []).slice(0, 200);
  const html = r.error ? `<p class="bad">${esc(errText(r.error))}</p>` : rows.length ? `<div class="r131-wrap"><table class="r131-t"><thead><tr>${cols.map((c) => `<th>${esc(c[0])}</th>`).join('')}</tr></thead><tbody>${rows.map((x) => `<tr>${cols.map((c) => `<td>${esc(c[1](x) == null ? '' : c[1](x))}</td>`).join('')}</tr>`).join('')}</tbody></table></div>` : `<p class="muted">${esc(T('nodata'))}</p>`;
  if ($('#sheet')) openSheet(`<h3>${esc(title)}</h3>${html}`);
}
const dt = (v) => { try { return new Date(v).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', hour12: false }); } catch (e) { return v; } };
function drill(i) {
  const res = D.res, r = res && res.rows && res.rows[i]; if (!r) return;
  const f = D.f, key = D.key;
  if (key === 'rpt131_sales') {
    if (f.group === 'day') return goReport('rpt131_sales_recon', { from: r.dim, to: r.dim, status: 'all' });
    if (f.group === 'week') return goReport('rpt131_sales_recon', { from: r.dim, to: addDays(r.dim, 6), status: 'all' });
    if (f.group === 'month') return goReport('rpt131_sales_recon', { from: r.dim + '-01', to: monthEnd(r.dim + '-01'), status: 'all' });
    if (f.group === 'outlet') return goReport('rpt131_sales_recon', { loc: r.dim, status: 'all' });
    return toast(T('nodrill'));
  }
  if (key === 'rpt131_sales_recon') {
    if (r.doc_type === 'sale' && B.invoiceview && B.invoiceview.openSale) return B.invoiceview.openSale(r.doc_id);
    return detailSheet(`${stLab(r.doc_type)} · ${r.ref}`, [[T('outlet'), lab(L(r.outlet_bn || '', r.outlet_en || '', r.outlet_en || ''))], ['Date', r.d], [lab(L('গ্রাহক', 'Customer', 'Customer')), r.party], [lab(L('রেজিস্টার', 'Register', 'Register')), r.register_net == null ? '' : fmt2(r.register_net)],
      [lab(L('খাতা', 'Books', 'Books')), r.books_net == null ? '' : fmt2(r.books_net)], [T('status'), stLab(r.status)], [lab(L('চিহ্ন', 'Flag', 'Flag')), stLab(r.flag)]]);
  }
  if (key === 'rpt131_item_profit') {
    if (f.group === 'item') return goReport('rpt131_stock_recon', { item: r.key, itemLabel: lab(L(r.name_bn, r.name_en, r.name_en)) });
    if (f.group === 'category') return goReport('rpt131_item_profit', { group: 'item', category: r.key === '-' ? '' : r.key });
    if (f.group === 'outlet') return goReport('rpt131_item_profit', { group: 'item', loc: r.key });
  }
  if (key === 'rpt131_stock_recon') {
    return ledgerSheet(`${r.item_code} · ${lab(L(r.item_bn || '', r.item_en || '', r.item_en || ''))}`, 'stock_ledger_rows', { p_loc: r.location_id, p_item: r.item_id, p_from: f.from, p_to: f.to, p_limit: 200 },
      [['Time', (x) => dt(x.made_at)], [lab(L('ধরন', 'Reason', 'Reason')), (x) => x.reason], [lab(L('পরিমাণ', 'Qty', 'Qty')), (x) => fmtQ(x.qty_delta)], [lab(L('খরচ', 'Cost', 'Cost')), (x) => (x.unit_cost == null ? '' : fmt2(x.unit_cost))], [lab(L('নোট', 'Note', 'Note')), (x) => x.note]]);
  }
  if (key === 'rpt131_wastage') {
    if (f.group === 'reason') return goReport('rpt131_wastage', { group: 'doc', search: r.dim });
    if (f.group === 'item') return goReport('rpt131_wastage', { group: 'doc', item: r.dim, itemLabel: rowLabel(r) });
    if (f.group === 'outlet') return goReport('rpt131_wastage', { group: 'reason', loc: r.dim });
    if (f.group === 'day') return goReport('rpt131_wastage', { group: 'doc', from: r.dim, to: r.dim });
    if (f.group === 'status') return goReport('rpt131_wastage', { group: 'doc', status: r.dim });
    return detailSheet(rowLabel(r), [['Time', dt(r.at)], [T('status'), stLab(r.status)], [lab(L('পরিমাণ', 'Qty', 'Qty')), r.qty == null ? '' : fmtQ(r.qty) + ' ' + (r.unit || '')], [lab(L('দাম', 'Value', 'Value')), r.value == null ? '' : fmt2(r.value)],
      [lab(L('কর্মী', 'Staff', 'Staff')), r.staff], [lab(L('নোট', 'Note', 'Note')), r.note], [lab(L('কারণ', 'Reason', 'Reason')), r.reason]]);
  }
  if (key === 'rpt131_cash_close') return goReport('rpt131_sales_recon', { from: r.d, to: r.d, loc: r.loc, status: 'all' });
  if (key === 'rpt131_ageing') {
    if (f.kind === 'receivable') return ledgerSheet(String(r.name), 'customer_ledger', { p_customer: r.id }, [['Time', (x) => dt(x.at)], [lab(L('ধরন', 'Kind', 'Kind')), (x) => x.kind], [lab(L('রসিদ', 'Ref', 'Ref')), (x) => x.ref], ['Dr', (x) => fmt2(x.debit)], ['Cr', (x) => fmt2(x.credit)], [lab(L('ব্যালেন্স', 'Balance', 'Balance')), (x) => fmt2(x.balance)]]);
    return ledgerSheet(String(r.name), 'supplier_ledger', { p_supplier: r.id, p_loc: f.loc ? Number(f.loc) : null }, [['Time', (x) => dt(x.at)], [lab(L('ধরন', 'Kind', 'Kind')), (x) => x.kind], [lab(L('রসিদ', 'Ref', 'Ref')), (x) => x.ref], ['Dr', (x) => fmt2(x.debit)], ['Cr', (x) => fmt2(x.credit)], [lab(L('ব্যালেন্স', 'Balance', 'Balance')), (x) => fmt2(x.balance)]]);
  }
  toast(T('nodrill'));
}

// ---- CSV
const csvCell = (v) => { let s = v == null ? '' : String(v); if (/^[=+\-@\t\r]/.test(s) && !/^-?[0-9]+(\.[0-9]+)?$/.test(s)) s = "'" + s; return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
async function exportCSV() {
  const r0 = D.res; if (!r0 || r0.off) return;
  toast(T('exp_busy'));
  let all = [], res = r0, pg = 1;
  try {
    for (; pg <= 200; pg++) {
      const r = await sb.rpc(D.key, params(pg, 200)); if (r.error) throw r.error; res = r.data; all = all.concat(res.rows || []);
      if (!res.has_more) break;
    }
  } catch (e) { return toast(errText(e)); }
  const cols = visibleCols(res);
  const out = [cols.map((c) => csvCell(lab(L(c.bn, c.en, c.en)))).join(',')];
  all.forEach((r) => out.push(cols.map((c) => { const v = cellVal(c, r); return csvCell(c.t === 'status' ? stLab(v) : v); }).join(',')));
  if (res.totals) out.push(cols.map((c, i) => (i === 0 ? csvCell(T('total')) : c.sum && res.totals[c.k] != null ? csvCell(res.totals[c.k]) : '')).join(','));
  out.push(''); out.push(csvCell(genText(res))); out.push(csvCell(T('flt') + ': ' + fltText(res)));
  if (res.cost_visible === false) out.push(csvCell(T('costhid')));
  (res.notes || []).forEach((n) => out.push(csvCell(noteText(n))));
  const blob = new Blob(['﻿' + out.join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `${D.key}-${D.f.from || D.f.asof || ''}${D.f.to && D.f.to !== D.f.from ? '_' + D.f.to : ''}.csv`;
  document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  try { const l = await sb.rpc('rpt131_log_export', { p_key: D.key, p_kind: 'csv', p_filters: res.filters || {}, p_rows: all.length }); if (l.error) toast(T('exp_lock')); else toast(T('exp_done')); } catch (e) { toast(T('exp_lock')); }
}

// ---- events
function readFilters() {
  const f = D.f, v = (id) => { const e = $(id); return e ? e.value : undefined; };
  if (v('#r131_from') !== undefined) f.from = v('#r131_from'); if (v('#r131_to') !== undefined) f.to = v('#r131_to'); if (v('#r131_asof') !== undefined) f.asof = v('#r131_asof');
  if (v('#r131_loc') !== undefined) f.loc = v('#r131_loc'); if (v('#r131_group') !== undefined) f.group = v('#r131_group'); if (v('#r131_status') !== undefined) f.status = v('#r131_status');
  if (v('#r131_cat') !== undefined) f.category = v('#r131_cat'); if (v('#r131_issues') !== undefined) f.issues = v('#r131_issues') === '1';
  if (v('#r131_kind') !== undefined) f.kind = v('#r131_kind'); if (v('#r131_q') !== undefined) f.search = v('#r131_q').trim();
}
Object.assign(H, {
  r131_go: () => { readFilters(); D.f.page = 1; run(); },
  r131_sort: (a) => { const k = a.dataset.k, cur = String((D.res && D.res.sort) || D.f.sort || '').split(':'); D.f.sort = k + ':' + (cur[0] === k && cur[1] === 'desc' ? 'asc' : 'desc'); D.f.page = 1; run(); },
  r131_page: (a) => { D.f.page = Math.max(1, (D.res ? D.res.page : 1) + Number(a.dataset.d)); run(); },
  r131_drill: (a) => drill(Number(a.dataset.i)),
  r131_csv: () => exportCSV(),
  r131_print: () => window.print(),
  r131_itemx: () => { D.f.item = ''; D.f.itemLabel = ''; const e = $('#r131_filters'); if (e) e.innerHTML = filtersHTML(); },
  r131_itempick: (a) => { D.f.item = a.dataset.id; D.f.itemLabel = a.dataset.t; const e = $('#r131_filters'); if (e) e.innerHTML = filtersHTML(); },
  r131_preset: (a) => {
    const t = today(), v = a.dataset.v;
    const p = v === 'today' ? [t, t] : v === 'yday' ? [addDays(t, -1), addDays(t, -1)] : v === '7' ? [addDays(t, -6), t] : v === 'month' ? [monthStart(t), t] : [monthStart(addDays(monthStart(t), -1)), addDays(monthStart(t), -1)];
    D.f.from = p[0]; D.f.to = p[1]; const a1 = $('#r131_from'), b1 = $('#r131_to'); if (a1) a1.value = p[0]; if (b1) b1.value = p[1]; D.f.page = 1; run();
  },
});
let pickTimer = 0;
document.addEventListener('input', (e) => {
  if (!e.target || e.target.id !== 'r131_item') return;
  clearTimeout(pickTimer); const q = e.target.value.replace(/[,()%*\\]/g, ' ').trim();
  pickTimer = setTimeout(async () => {
    const box = $('#r131_pick'); if (!box) return; if (q.length < 2) { box.innerHTML = ''; return; }
    try {
      const r = await sb.from('items').select('id,code,name_bn,name_en').or(`code.ilike.%${q}%,name_en.ilike.%${q}%,name_bn.ilike.%${q}%`).limit(8);
      box.innerHTML = (r.data || []).map((x) => { const t = x.code + ' · ' + lab(L(x.name_bn || x.name_en || '', x.name_en || x.name_bn || '', x.name_en || x.name_bn || '')); return `<button class="full tap" style="text-align:left" data-act="r131_itempick" data-id="${esc(x.id)}" data-t="${esc(t)}">${esc(t)}</button>`; }).join('');
    } catch (err) { box.innerHTML = ''; }
  }, 250);
});
document.addEventListener('change', (e) => {
  const id = e.target && e.target.id; if (!id || !id.startsWith('r131_')) return;
  if (id === 'r131_key') { D.key = e.target.value; jset('r131_key', D.key); const keep = { from: D.f.from, to: D.f.to, loc: D.f.loc }; D.f = Object.assign(defaults(D.key), keep); D.res = null; paintAll(); run(); return; }
  if (id === 'r131_q') return;   // the search runs on "Show" / Enter
  readFilters(); D.f.page = 1;
  if (id === 'r131_kind') { const as = $('#r131_asof'); if (as) as.disabled = D.f.kind === 'payable'; }
  if (id === 'r131_group' || id === 'r131_status' || id === 'r131_loc' || id === 'r131_kind' || id === 'r131_cat' || id === 'r131_issues') run();
});
document.addEventListener('keydown', (e) => { if (e.target && e.target.id === 'r131_q' && e.key === 'Enter') { e.preventDefault(); readFilters(); D.f.page = 1; run(); } });

async function view() {
  if (B.loadStatic) await B.loadStatic();
  if (!document.getElementById('r131css')) { const st = document.createElement('style'); st.id = 'r131css'; st.textContent = CSS; document.head.appendChild(st); }
  D.locs = (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []));
  shell(T('title'), '<div id="r131_body"><p class="muted">…</p></div>', true);
  try { await loadCatalog(); await loadCats(); } catch (e) { fail(e); }
  if (!BY[D.key]) { D.key = 'rpt131_sales'; D.f = defaults(D.key); }
  paintAll();
  if (D.cat && D.cat.enabled) run();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { reports131: view });
})();
