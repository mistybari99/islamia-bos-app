/* Islamia BOS · Owner dashboard metric catalogue (#/dashx, step Dash). NEW file; no existing file is edited for it.
   Every metric is built ONLY on a function / table that already exists in supabase (sales_summary, payments_summary, biz_daily, biz_items, biz_items_by_category,
   stock_valuation_by_category, acct_income_statement, stock_levels, customer_dues, payables_summary, online_orders_list, inbox_board, ledger_problem_count,
   cost_wait_list96, drawer_report, expiry_list, exceptions, production_runs). Nothing is guessed: no source / no data / refused / slower than 2 s = the tile says "No data".
   Metric = { id, group, label, needs:{owner?, cost?, grant?[]}, shape:'series'|'slices'|'value', type (default chart), fmt:'money'|'num'|'pct', fetch(ctx) }.
   Cost secrecy: every cost / profit / COGS metric has needs.cost and is hidden (never fetched) unless the person is the owner or holds the cost right.
   One server call per source and range is shared by every tile that needs it and kept 60 seconds (B.dashx_metrics.cache). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, S } = A;
const duesFn = () => { try { return B.rule && B.rule('dues_net_advance', 'off') === 'on' ? 'customer_dues_net113' : 'customer_dues'; } catch (e) { return 'customer_dues'; } };   // bos113: rule dues_net_advance = on -> the list net of the advance already used
const L = B.L, lab = B.lab;

// ---------- small helpers ----------
const CAP_MS = () => Number(window.__DX_CAP_MS) || 2000;
const TTL_MS = () => (window.__DX_TTL_MS === 0 ? 0 : Number(window.__DX_TTL_MS) || 60000);
const N = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
const arr = (d) => (Array.isArray(d) ? d : d && Array.isArray(d.rows) ? d.rows : []);
const dhaka = (d = new Date()) => d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const daysBetween = (a, b) => Math.round((new Date(b + 'T12:00:00Z') - new Date(a + 'T12:00:00Z')) / 86400000);
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dlabel = (iso) => Number(iso.slice(8, 10)) + ' ' + MON[Number(iso.slice(5, 7)) - 1];
const money = (n) => (S.lang === 'en' ? 'Tk ' : '৳ ') + A.fmt(Math.round(N(n) * 100) / 100);
const compact = (n) => { const a = Math.abs(N(n)), s = N(n) < 0 ? '-' : ''; const f = (v, u) => s + (Math.round(v * 10) / 10) + u; return a >= 1e7 ? f(a / 1e7, 'Cr') : a >= 1e5 ? f(a / 1e5, 'L') : a >= 1e3 ? f(a / 1e3, 'k') : s + (Math.round(a * 10) / 10); };
const FORMAT = { money: (n) => money(n), num: (n) => A.fmt(Math.round(N(n) * 100) / 100), pct: (n) => (Math.round(N(n) * 10) / 10) + '%' };
const FORMAT_C = { money: (n) => compact(n), num: (n) => compact(n), pct: (n) => (Math.round(N(n) * 10) / 10) + '%' };
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => String(x.id) === String(id)); return l ? A.nm(l) : String(id); };
const dayList = (from, to) => { const out = []; for (let d = from, i = 0; d <= to && i < 400; d = addDays(d, 1), i++) out.push(d); return out; };

// ---------- period ----------
const PERIODS = [
  { id: 'today', label: L('আজ', 'Today', 'আজ') }, { id: '7d', label: L('৭ দিন', '7 days', '7 দিন') }, { id: '30d', label: L('৩০ দিন', '30 days', '30 দিন') },
  { id: 'month', label: L('এই মাস', 'This month', 'এই মাস') }, { id: 'custom', label: L('নিজের পছন্দ', 'Custom', 'Custom') },
];
function range(key, custom) {
  const td = dhaka(); let from = td, to = td;
  if (key === '7d') from = addDays(td, -6);
  else if (key === '30d') from = addDays(td, -29);
  else if (key === 'month') from = td.slice(0, 8) + '01';
  else if (key === 'custom' && custom && /^\d{4}-\d{2}-\d{2}$/.test(custom.from || '') && /^\d{4}-\d{2}-\d{2}$/.test(custom.to || '')) { from = custom.from; to = custom.to; if (to < from) { const t = from; from = to; to = t; } if (daysBetween(from, to) > 366) from = addDays(to, -366); }
  const days = daysBetween(from, to) + 1, pto = addDays(from, -1), pfrom = addDays(pto, -(days - 1));
  return { key: key || 'today', from, to, days, pfrom, pto, td };
}

// ---------- calls: capped at 2 s, shared per source+args for 60 s ----------
const CACHE = new Map();
const uid = () => (S && S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const cap = (p, signal) => new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('dx_timeout')), CAP_MS());
  const ab = () => { clearTimeout(t); rej(Object.assign(new Error('dx_aborted'), { aborted: true })); };
  if (signal) { if (signal.aborted) return ab(); signal.addEventListener('abort', ab, { once: true }); }
  Promise.resolve(p).then((v) => { clearTimeout(t); res(v); }, (e) => { clearTimeout(t); rej(e); });
});
function shared(key, make, signal) {
  const k = uid() + '|' + key, now = Date.now(), c = CACHE.get(k);
  if (c && now - c.at < TTL_MS()) return cap(c.p, signal);
  const p = Promise.resolve().then(make).then((r) => { if (r && r.error) throw r.error; return r ? (r.count !== undefined && r.data === undefined ? r : r.data) : null; });
  const e = { at: now, p }; CACHE.set(k, e); p.catch(() => { if (CACHE.get(k) === e) CACHE.delete(k); });
  return cap(p, signal);
}
const rpc = (fn, args, signal) => shared(fn + JSON.stringify(args || {}), () => sb.rpc(fn, args || {}), signal);
const count = (key, qb, signal) => shared(key, async () => { const r = await qb(); if (r && r.error) throw r.error; return { data: (r && r.count) || 0 }; }, signal);
const clearCache = () => CACHE.clear();

// ---------- shared shapes ----------
const top = (rows, n, other) => {
  const s = rows.filter((r) => N(r.value) > 0).sort((a, z) => z.value - a.value);
  if (s.length <= n) return s;
  const rest = s.slice(n - 1).reduce((a, r) => a + r.value, 0);
  return s.slice(0, n - 1).concat([{ label: lab(other), value: rest }]);
};
const OTHER = L('অন্যান্য', 'Other', 'Other');
const inR = (d, a, b) => d >= a && d <= b;
// daily buckets: day by day up to 45 days, then 7-day chunks (so a chart never has hundreds of points)
function buckets(from, to) {
  const ds = dayList(from, to);
  if (ds.length <= 45) return ds.map((d) => ({ x: dlabel(d), from: d, to: d }));
  const out = []; for (let i = 0; i < ds.length; i += 7) out.push({ x: dlabel(ds[i]), from: ds[i], to: ds[Math.min(i + 6, ds.length - 1)] });
  return out;
}
const sumBy = (rows, key, a, b, f) => rows.reduce((s, r) => (inR(r[key], a, b) ? s + f(r) : s), 0);
function seriesOf(name, rows, key, range_, f) { return { name, points: buckets(range_.from, range_.to).map((bk) => ({ x: bk.x, y: sumBy(rows, key, bk.from, bk.to, f) })) }; }
const valueOf = (rows, key, r, f) => ({ value: sumBy(rows, key, r.from, r.to, f), prev: sumBy(rows, key, r.pfrom, r.pto, f), spark: seriesOf('', rows, key, r, f).points });
const nameOf = (o, bn, en, code) => (S.lang === 'en' ? (o[en] || o[code] || o[bn] || '') : (o[bn] || o[en] || o[code] || ''));

// sources (each one server call, shared)
const salesRows = async (c) => {
  const d = arr(await rpc('sales_summary', { p_from: c.r.pfrom }, c.signal));
  return d.filter((x) => !c.loc || String(x.location_id) === String(c.loc)).map((x) => ({ d: x.sale_date, loc: x.location_id, st: x.status, mode: x.pay_mode, n: N(x.n), total: N(x.total), disc: N(x.discount) }));
};
const done = (rows) => rows.filter((x) => x.st === 'done');
const bizDaily = async (c) => arr(await rpc('biz_daily', { p_from: c.r.pfrom, p_to: c.r.to, p_loc: c.loc || null }, c.signal));
const income = (c) => rpc('acct_income_statement', { p_from: c.r.from, p_to: c.r.to, p_loc: c.loc || null }, c.signal);
const payRows = async (c) => arr(await rpc('payments_summary', { p_from: c.r.pfrom }, c.signal)).filter((x) => !c.loc || String(x.location_id) === String(c.loc));
const custDues = async (c) => arr(await rpc(duesFn(), {}, c.signal));
const orders = async (c) => arr(await rpc('online_orders_list', { p_loc: c.loc || null, p_status: null, p_from: c.r.from, p_to: c.r.to, p_limit: 500 }, c.signal));

// ---------- the catalogue ----------
const G = {
  sales: L('বিক্রি', 'Sales', 'Sales'), profit: L('লাভ ও খরচ (কস্ট)', 'Profit & cost', 'Profit ও cost'), stock: L('স্টক', 'Stock', 'Stock'),
  money: L('টাকা, বাকি ও পাওনা', 'Cash, dues & payables', 'Cash, due ও payable'), orders: L('অর্ডার ও বার্তা', 'Orders & messages', 'Order ও message'),
  alerts: L('সতর্কতা', 'Alerts', 'Alerts'), factory: L('কারখানা', 'Factory', 'Factory'),
};
const CATALOGUE = [];
const M = (id, group, label, shape, type, fmt, needs, fetch) => CATALOGUE.push({ id, group, label, shape, type, fmt, needs: needs || {}, fetch });
const REP = ['view_reports'];

// -- sales (sales_summary: any person who may see POS) --
M('sales_total', 'sales', L('মোট বিক্রি', 'Total sales', 'Total sales'), 'value', 'kpi', 'money', {}, async (c) => valueOf(done(await salesRows(c)), 'd', c.r, (x) => x.total));
M('sales_trend', 'sales', L('দিনের বিক্রি', 'Sales by day', 'দিনের sales'), 'series', 'line', 'money', {}, async (c) => ({ series: [seriesOf(lab(L('বিক্রি', 'Sales', 'Sales')), done(await salesRows(c)), 'd', c.r, (x) => x.total)] }));
M('sales_by_loc', 'sales', L('শোরুম অনুযায়ী বিক্রি', 'Sales by location', 'Location অনুযায়ী sales'), 'slices', 'donut', 'money', {}, async (c) => {
  const m = {}; done(await salesRows(c)).filter((x) => inR(x.d, c.r.from, c.r.to)).forEach((x) => { m[x.loc] = (m[x.loc] || 0) + x.total; });
  return { slices: top(Object.keys(m).map((k) => ({ label: locName(k), value: m[k] })), 8, OTHER) }; });
M('sales_by_pay', 'sales', L('পেমেন্ট ধরন অনুযায়ী বিক্রি', 'Sales by payment type', 'Payment type অনুযায়ী sales'), 'slices', 'pie', 'money', {}, async (c) => {
  const m = {}; done(await salesRows(c)).filter((x) => inR(x.d, c.r.from, c.r.to)).forEach((x) => { const k = x.mode || '-'; m[k] = (m[k] || 0) + x.total; });
  return { slices: top(Object.keys(m).map((k) => ({ label: k, value: m[k] })), 8, OTHER) }; });
M('orders_count', 'sales', L('বিলের সংখ্যা', 'Number of bills', 'Bill-এর সংখ্যা'), 'value', 'kpi', 'num', {}, async (c) => valueOf(done(await salesRows(c)), 'd', c.r, (x) => x.n));
M('avg_bill', 'sales', L('গড় বিল', 'Average bill', 'গড় bill'), 'value', 'kpi', 'money', {}, async (c) => {
  const rows = done(await salesRows(c)), t = sumBy(rows, 'd', c.r.from, c.r.to, (x) => x.total), n = sumBy(rows, 'd', c.r.from, c.r.to, (x) => x.n);
  const pt = sumBy(rows, 'd', c.r.pfrom, c.r.pto, (x) => x.total), pn = sumBy(rows, 'd', c.r.pfrom, c.r.pto, (x) => x.n);
  return { value: n ? t / n : 0, prev: pn ? pt / pn : 0, spark: [] }; });
M('discounts', 'sales', L('ডিসকাউন্ট', 'Discounts given', 'Discount'), 'value', 'kpi', 'money', {}, async (c) => valueOf(done(await salesRows(c)), 'd', c.r, (x) => x.disc));
M('voids', 'sales', L('বাতিল বিল', 'Voided bills', 'Void bill'), 'value', 'kpi', 'num', {}, async (c) => valueOf((await salesRows(c)).filter((x) => x.st === 'void'), 'd', c.r, (x) => x.n));
M('sales_by_cat', 'sales', L('ক্যাটাগরি অনুযায়ী বিক্রি', 'Sales by category', 'Category অনুযায়ী sales'), 'slices', 'donut', 'money', { grant: REP }, async (c) => {
  const d = arr(await rpc('biz_items_by_category', { p_from: c.r.from, p_to: c.r.to, p_loc: c.loc || null, p_level: 'category' }, c.signal));
  return { slices: top(d.map((x) => ({ label: nameOf(x, 'cat_name_bn', 'cat_name_en', 'category') || lab(L('অন্য', 'Uncategorised', 'Uncategorised')), value: N(x.revenue) })), 8, OTHER) }; });
M('top_items', 'sales', L('সেরা বিক্রির আইটেম', 'Top selling items', 'সেরা selling item'), 'slices', 'bar', 'money', { grant: REP }, async (c) => {
  const d = arr(await rpc('biz_items', { p_from: c.r.from, p_to: c.r.to, p_loc: c.loc || null }, c.signal));
  return { slices: d.filter((x) => N(x.revenue) > 0).sort((a, z) => N(z.revenue) - N(a.revenue)).slice(0, 8).map((x) => ({ label: nameOf(x, 'name_bn', 'name_en', 'code'), value: N(x.revenue) })) }; });

// -- profit and cost (COST RIGHT ONLY: owner, ITEM_COST or the view_cost grant) --
const dailyGp = (rows) => rows.map((x) => ({ d: x.sale_date, gp: N(x.costed_rev) - N(x.cogs), rev: N(x.costed_rev), cogs: N(x.cogs) }));
M('gross_profit', 'profit', L('মোট লাভ (খরচ জানা অংশে)', 'Gross profit', 'Gross profit'), 'value', 'kpi', 'money', { cost: true }, async (c) => valueOf(dailyGp(await bizDaily(c)), 'd', c.r, (x) => x.gp));
M('gross_profit_trend', 'profit', L('দিনের মোট লাভ', 'Gross profit by day', 'দিনের gross profit'), 'series', 'area', 'money', { cost: true }, async (c) => ({ series: [seriesOf(lab(L('মোট লাভ', 'Gross profit', 'Gross profit')), dailyGp(await bizDaily(c)), 'd', c.r, (x) => x.gp)] }));
M('cogs', 'profit', L('বিক্রিত মালের খরচ (COGS)', 'Cost of goods sold', 'COGS'), 'value', 'kpi', 'money', { cost: true }, async (c) => valueOf(dailyGp(await bizDaily(c)), 'd', c.r, (x) => x.cogs));
M('gross_margin', 'profit', L('লাভের হার', 'Gross margin %', 'Gross margin %'), 'value', 'gauge', 'pct', { cost: true }, async (c) => {
  const rows = dailyGp(await bizDaily(c)), p = (a, b) => { const rv = sumBy(rows, 'd', a, b, (x) => x.rev), g = sumBy(rows, 'd', a, b, (x) => x.gp); return rv > 0 ? 100 * g / rv : 0; };
  return { value: p(c.r.from, c.r.to), prev: p(c.r.pfrom, c.r.pto), min: 0, max: 100, spark: [] }; });
// bos112: rule profit_truth_mode = on -> the ONE net profit (profit_truth112: wastage, card fees, payroll, shared bills included, unknown-cost sales left out) and a "provisional" note; off = the books figure as before
const truthOn = () => { try { return B.rule ? B.rule('profit_truth_mode', 'off') === 'on' : false; } catch (e) { return false; } };
const PROV = L('অস্থায়ী: কিছু বিক্রির খরচ জানা নেই বা কিছু শেয়ার্ড বিল ভাগ হয়নি', 'Provisional: some sales have no known cost or some shared bills are not allocated', 'Provisional: কিছু বিক্রির cost জানা নেই বা কিছু shared bill ভাগ হয়নি');
M('net_profit', 'profit', L('নিট লাভ (হিসাব খাতা)', 'Net profit (books)', 'Net profit (books)'), 'value', 'kpi', 'money', { cost: true, grant: ['accounts_view'] }, async (c) => {
  if (truthOn()) {
    const t = await rpc('profit_truth112', { p_from: c.r.from, p_to: c.r.to, p_loc: c.loc || null }, c.signal);
    if (t && t.company) return { value: N(t.company.net_profit), spark: [], note: t.provisional ? lab(PROV) : '' };
  }
  const d = await income(c); if (!d || d.data_needed) return null; return { value: N(d.net_profit), spark: [], note: truthOn() && d.provisional ? lab(PROV) : '' }; });
M('stock_value_cat', 'profit', L('ক্যাটাগরি অনুযায়ী স্টকের মূল্য', 'Stock value by category', 'Category অনুযায়ী stock value'), 'slices', 'treemap', 'money', { cost: true }, async (c) => {
  const d = arr(await rpc('stock_valuation_by_category', { p_loc: c.loc || null, p_level: 'category' }, c.signal));
  return { slices: top(d.map((x) => ({ label: nameOf(x, 'cat_name_bn', 'cat_name_en', 'category') || lab(L('অন্য', 'Uncategorised', 'Uncategorised')), value: N(x.value) })), 10, OTHER) }; });
M('stock_value_total', 'profit', L('মোট স্টকের মূল্য', 'Total stock value', 'Total stock value'), 'value', 'kpi', 'money', { cost: true }, async (c) => {
  const d = arr(await rpc('stock_valuation_by_category', { p_loc: c.loc || null, p_level: 'category' }, c.signal)); return { value: d.reduce((s, x) => s + N(x.value), 0), spark: [] }; });
M('cost_wait', 'profit', L('খরচের অপেক্ষায় নথি', 'Documents waiting for cost', 'Cost-এর অপেক্ষায় document'), 'value', 'kpi', 'num', { cost: true }, async (c) => {
  const d = await rpc('cost_wait_list96', { p_loc: c.loc || null, p_limit: 1 }, c.signal); return { value: N(d && d.total), spark: [] }; });

// -- expenses (accounts) --
const COGSISH = /cogs|cost of goods|cost of sales|purchase/i;
M('expense_by_head', 'money', L('খাত অনুযায়ী খরচ', 'Expenses by head', 'Head অনুযায়ী expense'), 'slices', 'pie', 'money', { grant: ['accounts_view'] }, async (c) => {
  const d = await income(c); if (!d || d.data_needed) return null;
  const costOk = await c.caps.cost;
  const rows = arr(d.expense).filter((x) => !x.is_group && N(x.amount) > 0 && (costOk || !COGSISH.test((x.name_en || '') + ' ' + (x.code || ''))));
  return { slices: top(rows.map((x) => ({ label: nameOf(x, 'name_bn', 'name_en', 'code'), value: N(x.amount) })), 8, OTHER) }; });
M('total_expense', 'money', L('মোট খরচ', 'Total expenses', 'Total expense'), 'value', 'kpi', 'money', { grant: ['accounts_view'], cost: true }, async (c) => {
  const d = await income(c); if (!d || d.data_needed) return null; return { value: N(d.total_expense), spark: [] }; });
// -- cash collected --
M('collections_by_mode', 'money', L('টাকা জমা: ধরন অনুযায়ী', 'Money collected by mode', 'Money collected: mode অনুযায়ী'), 'slices', 'donut', 'money', {}, async (c) => {
  const m = {}; (await payRows(c)).filter((x) => inR(x.pay_date, c.r.from, c.r.to)).forEach((x) => { const k = x.mode || '-'; m[k] = (m[k] || 0) + N(x.total); });
  return { slices: top(Object.keys(m).map((k) => ({ label: k, value: m[k] })), 8, OTHER) }; });
M('collections_trend', 'money', L('দিনের টাকা জমা', 'Money collected by day', 'দিনের money collected'), 'series', 'column', 'money', {}, async (c) => ({ series: [seriesOf(lab(L('জমা', 'Collected', 'Collected')), await payRows(c), 'pay_date', c.r, (x) => N(x.total))] }));
// -- dues and payables --
const OD_DAYS = 30;
M('cust_dues', 'money', L('গ্রাহকের বাকি', 'Customer dues', 'Customer due'), 'value', 'kpi', 'money', {}, async (c) => {
  const d = await custDues(c); return { value: d.reduce((s, x) => s + Math.max(0, N(x.balance)), 0), spark: [] }; });
M('cust_dues_top', 'money', L('সবচেয়ে বেশি বাকি (গ্রাহক)', 'Top customer dues', 'Top customer due'), 'slices', 'bar', 'money', {}, async (c) => {
  const d = await custDues(c); return { slices: d.filter((x) => N(x.balance) > 0).sort((a, z) => N(z.balance) - N(a.balance)).slice(0, 8).map((x) => ({ label: x.name || '-', value: N(x.balance) })) }; });
M('supp_dues', 'money', L('সরবরাহকারীর পাওনা', 'Supplier payables', 'Supplier payable'), 'value', 'kpi', 'money', {}, async (c) => {
  const d = arr(await rpc('payables_summary', { p_loc: c.loc || null }, c.signal))[0]; return d ? { value: N(d.total_payable), spark: [] } : null; });
M('dues_mix', 'money', L('বাকি ও পাওনা (মোট ও মেয়াদোত্তীর্ণ)', 'Dues and payables (total & overdue)', 'Due ও payable (total ও overdue)'), 'series', 'stacked_bar', 'money', {}, async (c) => {
  const [cd, ps] = await Promise.all([custDues(c), rpc('payables_summary', { p_loc: c.loc || null }, c.signal).then(arr)]);
  const old = addDays(c.r.td, -OD_DAYS), cTot = cd.reduce((s, x) => s + Math.max(0, N(x.balance)), 0), cOd = cd.filter((x) => x.oldest && x.oldest < old).reduce((s, x) => s + Math.max(0, N(x.balance)), 0);
  const p = ps[0] || {}, T1 = lab(L('মোট', 'Not yet due', 'Not yet due')), T2 = lab(L('মেয়াদোত্তীর্ণ', 'Overdue', 'Overdue'));
  return { series: [{ name: lab(L('গ্রাহক', 'Customers', 'Customers')), points: [{ x: T1, y: cTot - cOd }, { x: T2, y: cOd }] }, { name: lab(L('সরবরাহকারী', 'Suppliers', 'Suppliers')), points: [{ x: T1, y: N(p.total_payable) - N(p.overdue) }, { x: T2, y: N(p.overdue) }] }] }; });
// -- orders and messages --
M('orders_by_channel', 'orders', L('চ্যানেল অনুযায়ী অনলাইন অর্ডার', 'Online orders by channel', 'Channel অনুযায়ী online order'), 'slices', 'column', 'num', {}, async (c) => {
  const m = {}; (await orders(c)).forEach((x) => { const k = x.channel || '-'; m[k] = (m[k] || 0) + 1; });
  return { slices: top(Object.keys(m).map((k) => ({ label: k, value: m[k] })), 8, OTHER) }; });
M('online_orders', 'orders', L('অনলাইন অর্ডার', 'Online orders', 'Online order'), 'value', 'kpi', 'num', {}, async (c) => ({ value: (await orders(c)).length, spark: [] }));
M('inbox_new', 'orders', L('নতুন বার্তা', 'New messages', 'নতুন message'), 'value', 'kpi', 'num', {}, async (c) => {
  const d = await rpc('inbox_board', { p_loc: c.loc || null }, c.signal); if (d && d.on === false) return null; return { value: N(d && d.new_count), spark: [] }; });
// -- alerts --
M('exceptions_open', 'alerts', L('খোলা গরমিল', 'Open exceptions', 'Open exception'), 'value', 'kpi', 'num', {}, async (c) => ({ value: await count('exceptions_open', () => sb.from('exceptions').select('id', { count: 'exact', head: true }).eq('status', 'open'), c.signal), spark: [] }));
M('ledger_problems', 'alerts', L('খাতায় পোস্ট সমস্যা', 'Ledger problems', 'Ledger post সমস্যা'), 'value', 'kpi', 'num', { grant: ['accounts_view'] }, async (c) => ({ value: N(await rpc('ledger_problem_count', { p_loc: c.loc || null }, c.signal)), spark: [] }));
M('low_stock', 'alerts', L('ন্যূনতমের নিচে স্টক', 'Items below minimum stock', 'Min-এর নিচে stock'), 'value', 'kpi', 'num', {}, async (c) => ({ value: arr(await rpc('stock_levels', { p_loc: c.loc || null, p_filters: {} }, c.signal)).filter((x) => x.below_min).length, spark: [] }));
M('no_sale', 'alerts', L('"বিক্রি ছাড়া" ড্রয়ার খোলা', 'Drawer opened with no sale', 'No-sale drawer open'), 'value', 'kpi', 'num', { grant: REP }, async (c) => {
  const d = await rpc('drawer_report', { p_from: c.r.from, p_to: c.r.to }, c.signal); return { value: N(d && d.totals && d.totals.no_sale_open), spark: [] }; });
M('alerts_overview', 'alerts', L('সতর্কতার সংখ্যা', 'Alert counts', 'Alert count'), 'slices', 'bar', 'num', {}, async (c) => {
  const T = (a, b) => lab(L(a, b, a)); const one = (f) => f().then((v) => v, () => null);
  const g = (id) => CATALOGUE.find((m) => m.id === id).fetch(c);
  const [ex, lg, lo, ib] = await Promise.all([one(() => g('exceptions_open')), one(() => g('ledger_problems')), one(() => g('low_stock')), one(() => g('inbox_new'))]);
  const rows = [[ex, T('গরমিল', 'Exceptions')], [lg, T('খাতা সমস্যা', 'Ledger')], [lo, T('কম স্টক', 'Low stock')], [ib, T('বার্তা', 'Messages')]].filter((r) => r[0]).map((r) => ({ label: r[1], value: N(r[0].value) }));
  return rows.length ? { slices: rows.map((r) => ({ label: r.label, value: r.value })), keepZero: true } : null; });
// -- factory --
M('production_trend', 'factory', L('দিনের উৎপাদন (ব্যাচ)', 'Production batches by day', 'দিনের production (batch)'), 'series', 'column', 'num', {}, async (c) => {
  const rows = (await shared('production_runs' + c.r.from + c.r.to + (c.loc || ''), async () => {
    let q = sb.from('production_runs').select('made_at,batches,status,location_id').gte('made_at', c.r.from + 'T00:00:00+06:00').lt('made_at', addDays(c.r.to, 1) + 'T00:00:00+06:00'); if (c.loc) q = q.eq('location_id', Number(c.loc)); return q;
  }, c.signal) || []).filter((x) => x.status !== 'void').map((x) => ({ d: dhaka(new Date(x.made_at)), b: N(x.batches) }));
  return { series: [seriesOf(lab(L('ব্যাচ', 'Batches', 'Batches')), rows, 'd', c.r, (x) => x.b)] }; });
// the 'expiring' count reuses the existing expiry_list
M('expiring', 'alerts', L('মেয়াদ শেষের কাছে', 'Expiring soon', 'Expiring soon'), 'value', 'kpi', 'num', {}, async (c) => ({ value: arr(await rpc('expiry_list', {}, c.signal)).filter((x) => x.expired || N(x.hours_left) <= 24).length, spark: [] }));

// ---------- who may see what ----------
// caps: promises are cached per person; the server stays the authority on every call (this only keeps the picker and the fetches honest)
let CAPS = null;
const grant = (codes) => { try { return A.hasAnyGrant(codes).then((v) => !!v, () => false); } catch (e) { return Promise.resolve(false); } };
function caps() {
  if (CAPS && CAPS.uid === uid()) return CAPS;
  const own = !!(S.ctx && S.ctx.is_owner), perms = (S.ctx && S.ctx.perms) || {};
  const g = {}; ['view_reports', 'accounts_view', 'view_cost'].forEach((k) => { g[k] = own ? Promise.resolve(true) : grant([k]); });
  CAPS = { uid: uid(), own, g,
    cost: own ? Promise.resolve(true) : (perms.ITEM_COST && perms.ITEM_COST.view ? Promise.resolve(true) : g.view_cost),
    reports: own ? Promise.resolve(true) : (perms.POS && perms.POS.approve ? Promise.resolve(true) : g.view_reports) };
  return CAPS;
}
async function resolved() {
  const c = caps(); const [cost, reports, accounts] = await Promise.all([c.cost, c.reports, c.g.accounts_view]);
  return { own: c.own, cost, reports, accounts, g: { view_reports: reports, accounts_view: accounts, view_cost: cost } };
}
const allowed = (m, r) => {
  if (r.own) return true;
  const n = m.needs || {};
  if (n.owner) return false;
  if (n.cost && !r.cost) return false;
  if (n.grant && !n.grant.some((k) => r.g[k])) return false;
  return true;
};
const list = (r) => CATALOGUE.filter((m) => allowed(m, r));
const get = (id) => CATALOGUE.find((m) => m.id === id) || null;
const fmtOf = (m, compactMode) => (compactMode ? FORMAT_C : FORMAT)[(m && m.fmt) || 'num'];

async function run(m, r, loc, signal) {
  const rs = await resolved();
  if (!allowed(m, rs)) throw new Error('dx_denied');
  const c = { r, loc: loc || null, signal, caps: { cost: Promise.resolve(rs.cost) } };
  return cap(m.fetch(c), signal);
}

B.dashx_metrics = { CATALOGUE, GROUPS: G, PERIODS, range, list, get, allowed, resolved, caps: resolved, run, fmtOf, FORMAT, money, compact, clearCache, cache: CACHE, dhaka, addDays, dlabel };
})();
