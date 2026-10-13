/* Islamia BOS · Assistant tool registry (BOS.assistantTools) - the ONLY things the business assistant may run. READ-ONLY.
   Every tool calls an EXISTING read function with the user's own session (so every role / grant / location / cost / salary rule still applies):
     report_run (phase9: sales_summary, sales_combined, sales_trend, item_sales, category_sales, discounts, voids, payment_modes, collections,
       best_customers, hour_weekday, customer_dues, receivable_aging, credit_limit_use)  ·  report_run2 (phase21/24-27: expense_by_head, e2_expense_trend,
       cash_short_over, w1_cash_flow, stock_low, stock_balance, expiry_soon, wastage, transfers_gap, supplier_ageing, purchases_by_supplier,
       attendance_summary, exceptions_summary, k2_count_variance, g2_paper_numbers, x4_compliance, l1_pnl, l2_margin, l3_shop_pnl, t3_payroll, d5_lapsed, item_slow)
     day_book (phase23) · supplier_dues (phase10) · needs_you_oldest (phase28) · number_audit_summary (phase5) · biz_staff / biz_outlook (phase4/6)
     assistant_health / assistant_me (phase47) · optional, only when installed: acct_balance_sheet / acct_income_statement / acct_trial_balance (phase40), partner_overview (44), tier_usage_report (43), backup_status (46)
   No tool takes SQL, a table name, a function name or a sort expression from the user or from an AI; report keys are fixed here AND whitelisted on the server.
   A tool the person may not use is hidden (needs(me)); a server refusal is reported honestly as "not available with your access". */
(() => {
'use strict';
const B = window.BOS = window.BOS || {};
const L = B.L || ((bn, en, mix) => ({ bn, en, mix }));

// ---------- documented prices for the owner's token counter (USD per 1M tokens, cached 2026-10-06; ESTIMATE only, see docs/ASSISTANT.md) ----------
const PRICES = { 'claude-haiku-5-5': { in: 0.10, out: 0.50 }, 'claude-sonnet-5-5': { in: 2.00, out: 10.00 } };

// ---------- concept lexicon: Bangla, English, Banglish (transliterated) ----------
// Each concept = list of variants. ASCII variants match at a word start; Bangla variants match anywhere (suffixes attach: বিক্রির, বিক্রিতে).
const C = {
  sales: ['sales', 'sale', 'sell', 'sold', 'selling', 'revenue', 'turnover', 'bikri', 'bikroy', 'bikree', 'becha', 'বিক্রি', 'বিক্রয়', 'বিক্রয়', 'বেচা', 'সেল'],
  today: ['today', 'todays', 'aaj', 'aj', 'ajke', 'ajker', 'আজ', 'আজকে', 'আজকের'],
  branch: ['branch', 'branches', 'shop', 'shops', 'showroom', 'showrooms', 'outlet', 'location', 'locations', 'place', 'places', 'store wise', 'shakha', 'dokan', 'শাখা', 'শোরুম', 'দোকান', 'লোকেশন', 'জায়গা', 'জায়গা'],
  item: ['item', 'items', 'product', 'products', 'sweet', 'sweets', 'jinish', 'ponno', 'পণ্য', 'আইটেম', 'জিনিস', 'মিষ্টি'],
  top: ['top', 'best', 'most', 'highest', 'biggest', 'largest', 'leading', 'shera', 'sera', 'সেরা', 'শীর্ষ', 'সবচেয়ে বেশি', 'সবচেয়ে বেশি', 'বেশি বিক্রি', 'সর্বোচ্চ', 'বড়', 'বড়'],
  worst: ['worst', 'poor', 'poorly', 'weak', 'weakest', 'lowest', 'bottom', 'least', 'slow', 'slowest', 'underperform', 'kharap', 'খারাপ', 'দুর্বল', 'সবচেয়ে কম', 'সবচেয়ে কম', 'পিছিয়ে', 'কম চলে', 'ধীর'],
  profit: ['profit', 'profits', 'margin', 'margins', 'gross profit', 'p&l', 'pnl', 'profitable', 'lav', 'labh', 'munafa', 'লাভ', 'মুনাফা', 'লাভজনক'],
  loss: ['loss', 'losses', 'lokshan', 'লোকসান', 'ক্ষতি'],
  expense: ['expense', 'expenses', 'spending', 'spend', 'spent', 'khoroch', 'khorch', 'khoros', 'খরচ', 'ব্যয়', 'ব্যয়'],
  cost: ['cost', 'costs'],
  discount: ['discount', 'discounts', 'price override', 'overrides', 'chhar', 'chaar', 'ছাড়', 'ছাড়', 'ডিসকাউন্ট'],
  void: ['void', 'voids', 'voided', 'cancelled bill', 'canceled bill', 'বাতিল বিল', 'ভয়েড', 'ভয়েড'],
  recv: ['receivable', 'receivables', 'due from', 'customer due', 'customers owe', 'owe us', 'owes us', 'owe me', 'dues', 'due', 'credit customer', 'baki', 'baaki', 'pawna', 'বাকি', 'পাওনা', 'বকেয়া', 'বকেয়া'],
  pay: ['payable', 'payables', 'we owe', 'do we owe', 'owe supplier', 'owe to', 'supplier due', 'supplier dues', 'dena', 'দেনা', 'দায়', 'দায়'],
  customer: ['customer', 'customers', 'client', 'clients', 'buyer', 'khoddar', 'kastomar', 'গ্রাহক', 'খদ্দের', 'ক্রেতা', 'কাস্টমার'],
  supplier: ['supplier', 'suppliers', 'vendor', 'vendors', 'mohajon', 'mahajan', 'সরবরাহকারী', 'মহাজন', 'সাপ্লায়ার', 'সাপ্লায়ার'],
  stock: ['stock', 'stocks', 'inventory', 'mojud', 'mal', 'স্টক', 'মজুত', 'মজুদ', 'মাল '],
  low: ['low', 'short', 'below minimum', 'running out', 'run out', 'finishing', 'reorder', 'shesh', 'kom', 'কম', 'ফুরিয়ে', 'ফুরিয়ে', 'শেষ হয়ে', 'শেষ হয়ে', 'অর্ডার দিতে'],
  expiry: ['expiry', 'expire', 'expires', 'expired', 'expiring', 'meyad', 'mead', 'মেয়াদ', 'মেয়াদ', 'মেয়াদোত্তীর্ণ'],
  wastage: ['wastage', 'waste', 'wasted', 'spoil', 'spoiled', 'spoilage', 'nosto', 'noshto', 'নষ্ট', 'অপচয়', 'অপচয়'],
  count: ['count', 'counts', 'counting', 'variance', 'stock count', 'mismatch', 'gona', 'গণনা', 'গোনা', 'গুনতি'],
  cash: ['cash', 'drawer', 'till', 'nogod', 'nagad cash', 'নগদ', 'ক্যাশ', 'ড্রয়ার', 'ড্রয়ার'],
  shortover: ['short', 'over', 'shortage', 'short/over', 'kom beshi', 'কম-বেশি', 'কমবেশি', 'কম বেশি', 'ঘাটতি'],
  bank: ['bank', 'bkash', 'nagad', 'rocket', 'mobile money', 'ব্যাংক', 'ব্যাঙ্ক', 'বিকাশ', 'নগদ একাউন্ট'],
  position: ['financial position', 'position', 'financial health', 'net worth', 'overall', 'financial state', 'how are we doing', 'how is the business', 'business doing', 'obostha', 'অবস্থা', 'আর্থিক', 'সার্বিক', 'হালচাল'],
  balsheet: ['balance sheet', 'trial balance', 'income statement', 'ব্যালান্স শিট', 'ব্যালেন্স শিট', 'রেওয়ামিল', 'রেওয়ামিল'],
  change: ['change', 'changed', 'changes', 'difference', 'why', 'compare', 'compared', 'comparison', 'vs', 'versus', 'increase', 'increased', 'decrease', 'decreased', 'drop', 'dropped', 'fell', 'grew', 'growth', 'keno', 'কেন', 'পরিবর্তন', 'তুলনা', 'বদল', 'বেড়েছে', 'বেড়েছে', 'কমেছে', 'বাড়ল', 'বাড়ল', 'কমল'],
  unusual: ['unusual', 'anomaly', 'anomalies', 'strange', 'odd', 'suspicious', 'irregular', 'abnormal', 'red flag', 'red flags', 'fraud', 'leak', 'leakage', 'oshabhabik', 'অস্বাভাবিক', 'সন্দেহজনক', 'গরমিল', 'অদ্ভুত', 'চুরি'],
  attention: ['attention', 'pending', 'waiting', 'approval', 'approvals', 'needs me', 'need me', 'needs you', 'to do', 'todo', 'to-do', 'action needed', 'oppekkha', 'অপেক্ষা', 'অনুমোদন', 'বাকি কাজ', 'কী করতে হবে', 'কি করতে হবে', 'জমে আছে'],
  priority: ['priority', 'priorities', 'prioritise', 'prioritize', 'focus', 'most important', 'first thing', 'what should i do', 'ogradhikar', 'অগ্রাধিকার', 'আগে কী', 'আগে কি', 'গুরুত্বপূর্ণ', 'কোনটা আগে'],
  setup: ['setup', 'set up', 'configure', 'configuration', 'how do i', 'how to', 'how can i', 'steps', 'guide', 'switch on', 'turn on', 'enable', 'kivabe', 'kibhabe', 'কীভাবে', 'কিভাবে', 'সেটআপ', 'চালু করব', 'চালু করা', 'ধাপ', 'নিয়ম কী', 'কোথায়'],
  health: ['incomplete', 'missing setup', 'wrong setting', 'wrong settings', 'conflict', 'conflicting', 'health check', 'setup check', 'check setup', 'check my setup', 'what is missing', 'misconfigured', 'ki baki', 'ঘাটতি', 'কী বাকি', 'কি বাকি', 'ভুল সেটিং', 'সেটআপ চেক', 'অসম্পূর্ণ'],
  attendance: ['attendance', 'absent', 'absence', 'late', 'present', 'hajira', 'হাজিরা', 'অনুপস্থিত', 'দেরি', 'দেরিতে'],
  staff: ['staff', 'employee', 'employees', 'cashier', 'cashiers', 'salesman', 'salesmen', 'worker', 'workers', 'karmi', 'কর্মী', 'স্টাফ', 'কর্মচারী', 'বিক্রেতা'],
  salary: ['salary', 'salaries', 'payroll', 'wage', 'wages', 'beton', 'বেতন', 'মজুরি', 'বেতনের'],
  exceptions: ['exception', 'exceptions', 'flag', 'flags', 'red', 'byatikrom', 'ব্যতিক্রম', 'লাল'],
  gaps: ['number gap', 'number gaps', 'missing number', 'missing numbers', 'paper number', 'serial gap', 'serial number', 'duplicate number', 'নম্বর ফাঁক', 'নম্বরের ফাঁক', 'নম্বর বাদ', 'সিরিয়াল'],
  trend: ['trend', 'daily', 'day by day', 'per day', 'by day', 'each day', 'day wise', 'daywise', 'dinwari', 'ধারা', 'প্রতিদিন', 'দিনওয়ারি', 'দিনে দিনে', 'রোজ'],
  hour: ['hour', 'hours', 'busiest', 'busy time', 'peak', 'time of day', 'rush', 'weekday', 'ঘণ্টা', 'ভিড়', 'ভিড়', 'ব্যস্ত সময়', 'ব্যস্ত সময়'],
  category: ['category', 'categories', 'catagory', 'ক্যাটাগরি', 'শ্রেণী', 'ধরন অনুযায়ী', 'ধরন অনুযায়ী'],
  paymode: ['payment mode', 'payment modes', 'payment method', 'payment methods', 'by payment', 'card payment', 'পেমেন্ট', 'কীভাবে টাকা দিয়েছে', 'মাধ্যম'],
  collection: ['collection', 'collections', 'collected', 'recovered', 'aday', 'আদায়', 'আদায়', 'উসুল'],
  purchase: ['purchase', 'purchases', 'buying', 'bought', 'kroy', 'kena', 'kenakata', 'ক্রয়', 'ক্রয়', 'কেনা', 'কিনেছি'],
  transfer: ['transfer', 'transfers', 'not received', 'sent stock', 'ট্রান্সফার', 'পাঠানো মাল', 'পৌঁছায়নি', 'পৌঁছায়নি'],
  value: ['value', 'worth', 'valuation', 'মূল্য', 'দাম কত'],
  outlook: ['forecast', 'outlook', 'next week', 'next 7 days', 'prediction', 'predict', 'expected sales', 'purbabhas', 'পূর্বাভাস', 'সামনের সপ্তাহ', 'আগামী সপ্তাহ'],
  lapsed: ['lapsed', 'inactive customer', 'inactive customers', 'stopped buying', 'lost customers', 'not come back', 'হারানো গ্রাহক', 'আসেনি', 'নিষ্ক্রিয় গ্রাহক'],
  help: ['help', 'what can you do', 'what can i ask', 'how do you work', 'who are you', 'sahajjo', 'সাহায্য', 'কী পারো', 'কি পারো', 'কী জিজ্ঞেস', 'তুমি কে'],
  notes: ['business rule', 'business rules', 'approved rule', 'approved rules', 'owner rule', 'our rules', 'policy', 'policies', 'procedure', 'procedures', 'মালিকের নিয়ম', 'ব্যবসার নিয়ম', 'নীতি', 'পদ্ধতি'],
  compliance: ['compliance', 'late entry', 'late entries', 'missing sheet', 'missing sheets', 'not submitted', 'forms not submitted', 'জমা হয়নি', 'জমা হয়নি', 'শিট বাকি', 'দেরিতে জমা'],
  partner: ['partner', 'partners', 'partnership', 'ongshidar', 'অংশীদার', 'পার্টনার'],
  tier: ['tier', 'tiers', 'loyalty', 'gold customer', 'টিয়ার', 'লয়্যালটি'],
  backup: ['backup', 'backups', 'ব্যাকআপ'],
  report: ['report', 'reports', 'numbers', 'figures', 'figure', 'summary', 'how much', 'koto', 'কত', 'রিপোর্ট', 'হিসাব', 'সংখ্যা'],
  locations: ['which branches', 'list of branches', 'all locations', 'list locations', 'how many branches', 'কয়টি শাখা', 'কয়টি শাখা', 'সব শাখা', 'শাখাগুলো'],
};

// ---------- intents: required concepts (all), optional bonus concepts, excluded concepts. Highest score wins; a tie between tools = clarify ----------
// score = 10 * required + 1 * optional matched + base
const I = (intent, tool, req, opt, no, base) => ({ intent, tool, req, opt: opt || [], no: no || [], base: base || 0 });
const INTENTS = [
  I('sales', 'sales_summary', ['sales'], ['today', 'report'], ['branch', 'item', 'trend', 'change', 'category', 'hour', 'paymode', 'customer', 'top', 'worst']),
  I('sales', 'sales_summary', ['today'], [], ['expense', 'stock', 'cash', 'attendance', 'discount', 'void', 'recv', 'pay', 'purchase', 'wastage', 'exceptions', 'collection'], -6),
  I('sales_branch', 'sales_by_location', ['sales', 'branch'], ['top', 'worst', 'today']),
  I('sales_branch', 'sales_by_location', ['branch', 'worst'], ['sales'], [], 2),
  I('sales_branch', 'sales_by_location', ['branch', 'top'], ['sales'], ['item', 'expense'], 1),
  I('sales_trend', 'sales_trend', ['sales', 'trend']),
  I('sales_trend', 'sales_trend', ['trend'], [], [], -3),
  I('top_items', 'top_items', ['item'], ['sales', 'top', 'worst'], ['profit', 'stock', 'category', 'wastage', 'expiry', 'low']),
  I('top_items', 'top_items', ['sales', 'top'], ['item'], ['branch', 'customer', 'category', 'profit']),
  I('slow_items', 'slow_items', ['item', 'worst'], ['sales'], ['profit', 'branch', 'stock'], 3),
  I('category', 'category_sales', ['category'], ['sales']),
  I('margin', 'item_margin', ['profit', 'item'], ['top', 'worst'], [], 2),
  I('pnl', 'pnl', ['profit'], ['loss', 'branch'], ['item', 'category']),
  I('pnl', 'pnl', ['loss'], [], ['item']),
  I('shop_pnl', 'shop_pnl', ['profit', 'branch'], ['loss', 'worst', 'top'], ['item'], 3),
  I('shop_pnl', 'shop_pnl', ['loss', 'branch'], ['worst'], ['item'], 3),
  I('expenses', 'expenses_by_head', ['expense'], ['top', 'today'], ['change', 'trend']),
  I('expenses', 'expenses_by_head', ['cost', 'top'], [], ['item', 'profit']),
  I('expense_change', 'expense_trend', ['expense', 'change']),
  I('expense_change', 'expense_trend', ['expense', 'trend']),
  I('discounts', 'discounts', ['discount'], ['staff'], [], 1),
  I('voids', 'voids', ['void'], ['staff']),
  I('cash_short', 'cash_short_over', ['cash', 'shortover']),
  I('cash_flow', 'cash_flow', ['cash'], ['trend', 'today'], ['shortover', 'position', 'bank']),
  I('cash_position', 'cash_position', ['cash', 'bank'], ['position']),
  I('cash_position', 'cash_position', ['bank'], [], ['payable'], -1),
  I('paymode', 'payment_modes', ['paymode']),
  I('collections', 'collections', ['collection'], ['recv']),
  I('receivables', 'receivables', ['recv'], ['customer', 'top'], ['pay', 'supplier', 'collection']),
  I('best_customers', 'best_customers', ['customer', 'top'], ['sales'], ['recv', 'pay', 'lapsed', 'tier'], 1),
  I('best_customers', 'best_customers', ['customer', 'sales'], ['top'], ['lapsed', 'recv'], 1),
  I('lapsed', 'lapsed_customers', ['lapsed'], ['customer'], [], 2),
  I('payables', 'payables', ['pay'], ['supplier', 'top']),
  I('payables', 'payables', ['supplier', 'recv'], [], [], 1),
  I('payables', 'payables', ['supplier'], [], ['purchase'], -4),
  I('purchases', 'purchases_by_supplier', ['purchase'], ['supplier', 'top'], ['lapsed']),
  I('stock_low', 'stock_low', ['stock', 'low'], [], ['value']),
  I('stock_low', 'stock_low', ['low'], ['item'], ['sales', 'cash', 'expense', 'value', 'profit', 'branch', 'worst'], -4),
  I('stock_value', 'stock_value', ['stock', 'value']),
  I('stock_value', 'stock_value', ['stock'], [], ['low', 'expiry', 'wastage', 'count', 'transfer'], -3),
  I('expiry', 'expiry_soon', ['expiry']),
  I('wastage', 'wastage', ['wastage']),
  I('count_variance', 'count_variance', ['count'], ['stock', 'unusual']),
  I('transfers', 'transfers_gap', ['transfer']),
  I('exceptions', 'exceptions_summary', ['exceptions'], ['unusual'], ['gaps']),
  I('gaps', 'number_gaps', ['gaps']),
  I('compliance', 'compliance', ['compliance'], [], [], 1),
  I('attendance', 'attendance_summary', ['attendance'], ['staff']),
  I('staff_outliers', 'staff_outliers', ['staff'], ['unusual', 'worst', 'top', 'void'], ['attendance', 'salary', 'branch']),
  I('payroll', 'payroll', ['salary'], ['staff']),
  I('hours', 'hour_weekday', ['hour'], ['sales']),
  I('outlook', 'outlook', ['outlook'], ['sales']),
  I('needs_you', 'needs_you', ['attention'], ['today']),
  I('health', 'health', ['health'], ['setup']),
  I('fin_position', 'fin_position', ['position'], ['cash', 'profit'], ['setup']),
  I('balance_sheet', 'acc_balance_sheet', ['balsheet']),
  I('what_changed', 'what_changed', ['change'], ['sales', 'branch', 'item'], ['expense', 'setup']),
  I('unusual', 'unusual', ['unusual'], ['today', 'stock', 'cash'], ['count', 'exceptions']),
  I('priorities', 'priorities', ['priority']),
  I('partners', 'partners', ['partner']),
  I('tiers', 'tiers', ['tier']),
  I('backup', 'backup', ['backup'], [], ['setup']),
  I('locations', 'locations', ['locations']),
  I('notes', 'notes', ['notes']),
  I('help', 'help', ['help'], [], [], -1),
];

// ---------- helpers for the tools ----------
const lang = () => ((window.BOS_APP && window.BOS_APP.S && window.BOS_APP.S.lang) || 'bn');
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const iso = (d) => d.toISOString().slice(0, 10);
const addDays = (s, n) => { const d = new Date(s + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return iso(d); };
const rule = (k, f) => { try { return B.rule ? B.rule(k, f) : f; } catch (e) { return f; } };
const DOW = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };
// presets -> dates on the client (only for functions that need explicit dates; reports get the preset and the server decides)
function presetDates(p) {
  const t = today(), d = new Date(t + 'T00:00:00Z'), ms = t.slice(0, 8) + '01';
  const ws = DOW[String(rule('week_start', 'sat') || 'sat').slice(0, 3).toLowerCase()]; const wk = addDays(t, -(((d.getUTCDay() - (ws === undefined ? 6 : ws)) + 7) % 7));
  const fm = Number(rule('fiscal_year_start_month', 1)) || 1, fd = Number(rule('fiscal_year_start_day', 1)) || 1;
  let fy = new Date(Date.UTC(d.getUTCFullYear(), fm - 1, fd)); if (fy > d) fy = new Date(Date.UTC(d.getUTCFullYear() - 1, fm - 1, fd));
  const lm = new Date(ms + 'T00:00:00Z'); lm.setUTCMonth(lm.getUTCMonth() - 1);
  const fyp = new Date(fy); fyp.setUTCFullYear(fyp.getUTCFullYear() - 1);
  return ({ today: [t, t], yesterday: [addDays(t, -1), addDays(t, -1)], last_7: [addDays(t, -6), t], last_30: [addDays(t, -29), t], this_month: [ms, t],
    last_month: [iso(lm), addDays(ms, -1)], this_week: [wk, t], last_week: [addDays(wk, -7), addDays(wk, -1)], this_fy: [iso(fy), t], last_fy: [iso(fyp), addDays(iso(fy), -1)] })[p] || [ms, t];
}
const periodDates = (pd) => (pd && pd.from ? [pd.from, pd.to || pd.from] : presetDates((pd && pd.preset) || 'this_month'));
// filters for the report engines: only whitelisted keys, typed values
function flt(p, extra) {
  const f = {};
  if (p.period) { if (p.period.preset) f.preset = p.period.preset; else if (p.period.from) { f.from = p.period.from; f.to = p.period.to || p.period.from; } }
  if (p.locs && p.locs.length) f.locations = p.locs.map(Number).filter((n) => Number.isInteger(n) && n > 0).slice(0, 20);
  if (p.items && p.items.length) f.items = p.items.filter((x) => /^[0-9a-z-]{1,40}$/i.test(x)).slice(0, 20);
  return Object.assign(f, extra || {});
}
// normalise an engine result (report_run / report_run2 share the shape)
function fromReport(d, engine, key, p, args) {
  d = d || {};
  return { ok: true, key, engine, columns: (d.columns || []).filter((c) => c.type !== 'id'), rows: d.rows || [], totals: d.totals || null, compare: d.compare || null,
    notes: d.notes || [], dataNeeded: !!d.data_needed, period: d.meta ? { from: d.meta.from, to: d.meta.to } : null, meta: d.meta || {},
    source: { kind: 'report', name: key, engine, params: args }, asOf: new Date().toISOString(), hasMore: !!d.has_more };
}
const rep1 = (key, o = {}) => async (p, X) => { const args = { p_key: key, p_filters: flt(p, o.extra), p_group: o.group || null, p_sort: o.sort ? o.sort(p) : null, p_page: 1, p_compare: !!(o.compare || p.compare) };
  return fromReport(await X.call('report_run', args), 1, key, p, args); };
const rep2 = (key, o = {}) => async (p, X) => { const args = { p_key: key, p_filters: flt(p, o.extra), p_group: o.group || null, p_sort: o.sort ? o.sort(p) : null, p_page: 1 };
  return fromReport(await X.call('report_run2', args), 2, key, p, args); };
const rowsOf = (data) => (Array.isArray(data) ? data : []);
const col = (key, bn, en, type) => ({ key, label_bn: bn, label_en: en, type });

// ---------- the registry ----------
// needs(me): true, or 'access' (hidden / not available for this person) or 'install' (module not installed)
const TOOLS = {};
const T = (key, o) => { TOOLS[key] = Object.assign({ key, params: ['period', 'locs'], group: 'money', needs: () => true, defPeriod: 'this_month' }, o); };
const R = (g) => (me) => (me.reports && me.reports[g]) ? true : 'access';
const pickOpt = (me, names) => (me.optional || []).find((x) => [].concat(names).includes(x.name));
const opt = (names) => (me) => (pickOpt(me, names) ? true : 'install');

T('sales_summary', { title: L('বিক্রির সারসংক্ষেপ', 'Sales summary', 'Sales summary'), group: 'today', needs: R('sales'), defPeriod: 'today', report: 'sales_summary',
  head: ['net', 'bills', 'avg_bill', 'discount', 'due', 'void_amt'], run: rep1('sales_summary'), link: 'report/sales_summary' });
T('sales_by_location', { title: L('শাখা অনুযায়ী বিক্রি', 'Sales by branch', 'Branch অনুযায়ী sale'), group: 'money', needs: R('sales'), report: 'sales_combined',
  head: ['net', 'bills'], label: 'location', value: 'net', run: rep1('sales_combined', { group: 'location', sort: (p) => (p.worst ? 'net:asc' : 'net:desc') }), link: 'report/sales_combined', params: ['period', 'locs', 'compare', 'worst'] });
T('sales_trend', { title: L('দিনওয়ারি বিক্রি', 'Sales by day', 'দিনওয়ারি sale'), group: 'money', needs: R('sales'), report: 'sales_trend', head: ['net', 'bills'], label: 'day', value: 'net', chart: 'line',
  run: rep1('sales_trend', { group: 'day', sort: () => 'day:asc' }), link: 'report/sales_trend' });
T('top_items', { title: L('সবচেয়ে বেশি বিক্রি হওয়া আইটেম', 'Top-selling items', 'বেশি বিক্রি হওয়া item'), group: 'stock', needs: R('sales'), report: 'item_sales', head: ['net', 'qty'], label: 'item', value: 'net',
  run: rep1('item_sales', { group: 'item', sort: (p) => (p.worst ? 'net:asc' : 'net:desc') }), link: 'report/item_sales', params: ['period', 'locs', 'topN', 'items', 'compare', 'worst'] });
T('slow_items', { title: L('ধীর ও অবিক্রীত আইটেম', 'Slow and unsold items', 'ধীর ও unsold item'), group: 'stock', needs: R('sales'), report: 'item_slow', head: ['items', 'unsold_items', 'net'], label: 'item', value: 'net',
  run: rep2('item_slow'), link: 'report/item_slow', params: ['period', 'locs', 'topN'] });
T('category_sales', { title: L('ক্যাটাগরি অনুযায়ী বিক্রি', 'Sales by category', 'Category অনুযায়ী sale'), needs: R('sales'), report: 'category_sales', head: ['net', 'qty'], label: 'category', value: 'net',
  run: rep1('category_sales', { group: 'category', sort: () => 'net:desc' }), link: 'report/category_sales' });
T('item_margin', { title: L('আইটেম অনুযায়ী লাভ (মার্জিন)', 'Margin by item', 'Item অনুযায়ী margin'), needs: (me) => (me.cost && me.reports && me.reports.profit ? true : 'access'), report: 'l2_margin', head: [], label: 'item', value: 'margin',
  run: rep2('l2_margin', { sort: (p) => (p.worst ? 'margin:asc' : 'margin:desc') }), link: 'report/l2_margin', params: ['period', 'locs', 'topN', 'worst'], cost: true });
T('pnl', { title: L('লাভ-ক্ষতি (মাস ও শাখা)', 'Profit and loss', 'লাভ-ক্ষতি'), needs: (me) => (me.is_owner ? true : 'access'), report: 'l1_pnl', head: ['net_sales', 'cogs', 'expenses', 'salary', 'fixed', 'profit'],
  run: rep2('l1_pnl'), link: 'report/l1_pnl', cost: true });
T('shop_pnl', { title: L('শাখার লাভ-ক্ষতি তুলনা', 'Shop P&L comparison', 'Shop P&L তুলনা'), needs: (me) => (me.is_owner ? true : 'access'), report: 'l3_shop_pnl', head: ['net_sales', 'expenses', 'profit'], label: 'location', value: 'profit',
  run: rep2('l3_shop_pnl', { sort: (p) => (p.worst ? 'profit:asc' : 'profit:desc') }), link: 'report/l3_shop_pnl', cost: true, params: ['period', 'locs', 'worst'] });
T('expenses_by_head', { title: L('খরচ (খাত অনুযায়ী)', 'Expenses by head', 'খরচ (head অনুযায়ী)'), needs: R('expense'), report: 'expense_by_head', head: ['amount', 'lines', 'no_receipt_amount'], label: 'head', value: 'amount',
  run: rep2('expense_by_head', { group: 'head', sort: () => 'amount:desc' }), link: 'report/expense_by_head', params: ['period', 'locs', 'topN'] });
T('expense_trend', { title: L('খরচ: আগের সময়ের সাথে তুলনা', 'Expenses vs previous period', 'খরচ: আগের সময়ের সাথে'), needs: R('expense'), report: 'e2_expense_trend', head: ['current', 'previous', 'change'], label: 'head', value: 'change',
  run: rep2('e2_expense_trend', { sort: () => 'change:desc' }), link: 'report/e2_expense_trend' });
T('discounts', { title: L('ছাড় ও দাম বদল', 'Discounts and price overrides', 'ছাড় ও price override'), group: 'control', needs: R('sales'), report: 'discounts', head: ['discount', 'discount_pct', 'disc_bills', 'over_limit_bills', 'override_lines'], label: 'staff', value: 'discount',
  run: rep1('discounts', { group: 'staff', sort: () => 'discount:desc' }), link: 'report/discounts' });
T('voids', { title: L('বাতিল বিল', 'Voided bills', 'Void bill'), group: 'control', needs: R('pos'), report: 'voids', head: ['void_bills', 'void_amt', 'void_pct'], label: 'staff', value: 'void_amt',
  run: rep1('voids', { group: 'staff', sort: () => 'void_amt:desc' }), link: 'report/voids' });
T('cash_short_over', { title: L('ক্যাশ কম / বেশি', 'Cash short / over', 'Cash কম / বেশি'), group: 'control', needs: R('cash'), report: 'cash_short_over', head: ['net', 'short_amount', 'over_amount', 'short_sheets', 'sheets'], label: 'location', value: 'net',
  run: rep2('cash_short_over', { group: 'location', sort: () => 'net:asc' }), link: 'report/cash_short_over' });
T('cash_flow', { title: L('দৈনিক ক্যাশ প্রবাহ', 'Daily cash flow', 'Daily cash flow'), needs: R('cash'), report: 'w1_cash_flow', head: ['cash_in', 'cash_out', 'net_cash'], label: 'day', value: 'net_cash', chart: 'line',
  run: rep2('w1_cash_flow', { sort: () => 'day:asc' }), link: 'report/w1_cash_flow', defPeriod: 'last_7' });
T('payment_modes', { title: L('পেমেন্টের মাধ্যম', 'By payment mode', 'Payment mode'), needs: R('cash'), report: 'payment_modes', head: ['amount', 'payments'], label: 'mode', value: 'amount',
  run: rep1('payment_modes', { group: 'mode', sort: () => 'amount:desc' }), link: 'report/payment_modes' });
T('collections', { title: L('বাকি আদায়', 'Collections', 'Collection'), needs: R('cash'), report: 'collections', head: ['amount', 'payments', 'cash_amount', 'mobile_amount'], label: 'day', value: 'amount', chart: 'line',
  run: rep1('collections', { group: 'day', sort: () => 'day:asc' }), link: 'report/collections' });
T('receivables', { title: L('গ্রাহকের কাছে পাওনা (বাকি)', 'Due from customers', 'Customer-এর বাকি'), group: 'money', needs: R('customers'), report: 'customer_dues', head: ['balance', 'customers', 'no_limit_set'], label: 'name', value: 'balance',
  run: rep1('customer_dues', { sort: () => 'balance:desc' }), link: 'dues', params: ['topN', 'names'], nodate: true });
T('best_customers', { title: L('সেরা গ্রাহক', 'Best customers', 'সেরা customer'), group: 'people', needs: R('customers'), report: 'best_customers', head: ['net', 'bills'], label: 'customer_name', value: 'net',
  run: rep1('best_customers', { group: 'customer', sort: () => 'net:desc' }), link: 'report/best_customers', params: ['period', 'locs', 'topN'] });
T('lapsed_customers', { title: L('নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক', 'Lapsed, new and repeat customers', 'Lapsed ও নতুন-পুরনো customer'), group: 'people', needs: R('sales'), report: 'd5_lapsed', head: ['orders_period', 'amount_period'], label: 'name', value: 'days_silent',
  run: rep2('d5_lapsed', { sort: () => 'days_silent:desc' }), link: 'report/d5_lapsed' });
T('payables', { title: L('সরবরাহকারীর পাওনা (দেনা)', 'What we owe suppliers', 'Supplier-এর পাওনা'), group: 'money', needs: (me) => (me.purchase ? true : 'access'), nodate: true, label: 'name', value: 'balance', params: ['locs', 'topN', 'names'],
  run: async (p, X) => { const args = { p_loc: p.locs && p.locs.length === 1 ? Number(p.locs[0]) : null }; const rows = rowsOf(await X.call('supplier_dues', args));
    const sum = (k) => Math.round(rows.reduce((s, r) => s + (Number(r[k]) || 0), 0) * 100) / 100;
    return { ok: true, key: 'payables', columns: [col('name', 'সরবরাহকারী', 'Supplier', 'text'), col('balance', 'পাওনা', 'Balance', 'money'), col('overdue', 'মেয়াদোত্তীর্ণ', 'Overdue', 'money'), col('oldest', 'সবচেয়ে পুরনো বিল', 'Oldest bill', 'date'), col('credit_days', 'বাকির দিন', 'Credit days', 'int')],
      rows: rows.slice().sort((a, b) => (Number(b.balance) || 0) - (Number(a.balance) || 0)), totals: { balance: sum('balance'), overdue: sum('overdue'), suppliers: rows.length }, derived: ['balance', 'overdue'],
      source: { kind: 'rpc', name: 'supplier_dues', params: args }, asOf: new Date().toISOString(), dataNeeded: rows.length === 0 }; }, link: 'payables', head: ['balance', 'overdue', 'suppliers'] });
T('purchases_by_supplier', { title: L('ক্রয় (সরবরাহকারী অনুযায়ী)', 'Purchases by supplier', 'Purchase (supplier অনুযায়ী)'), needs: (me) => (me.cost && me.reports && me.reports.purchase ? true : 'access'), report: 'purchases_by_supplier', head: ['total', 'paid', 'due', 'bills'], label: 'supplier', value: 'total',
  run: rep2('purchases_by_supplier', { group: 'supplier', sort: () => 'total:desc' }), link: 'report/purchases_by_supplier', cost: true });
T('stock_low', { title: L('স্টক কম (ন্যূনতমের নিচে)', 'Stock at or below minimum', 'Stock কম'), group: 'stock', needs: R('stock'), report: 'stock_low', head: ['lines', 'at_zero', 'reorder_value'], label: 'item', value: 'short_by', nodate: true,
  run: rep2('stock_low'), link: 'report/stock_low', params: ['locs', 'topN'] });
T('stock_value', { title: L('স্টকের মূল্য', 'Stock value', 'Stock value'), group: 'stock', needs: R('stock'), report: 'stock_balance', head: ['value', 'lines', 'low_lines'], label: 'item', value: 'value', nodate: true,
  run: rep2('stock_balance', { sort: () => 'value:desc' }), link: 'report/stock_balance', params: ['locs', 'topN'] });
T('expiry_soon', { title: L('মেয়াদ শেষ / শিগগির শেষ', 'Expired and expiring soon', 'Expiry শেষ / শিগগির'), group: 'stock', needs: R('stock'), report: 'expiry_soon', head: ['batches', 'expired_batches', 'value'], label: 'item', value: 'qty', nodate: true,
  run: rep2('expiry_soon'), link: 'report/expiry_soon', params: ['locs', 'topN'] });
T('wastage', { title: L('অপচয়', 'Wastage', 'অপচয়'), group: 'stock', needs: R('stock'), report: 'wastage', head: ['value', 'entries'], label: 'reason', value: 'value',
  run: rep2('wastage', { group: 'reason' }), link: 'report/wastage' });
T('count_variance', { title: L('স্টক গণনার গরমিল', 'Stock count variance', 'Stock count variance'), group: 'stock', needs: R('stock'), report: 'k2_count_variance', head: ['counts', 'off_n', 'short_n', 'over_n'], label: 'item', value: 'abs_var',
  run: rep2('k2_count_variance', { sort: () => 'abs_var:desc' }), link: 'report/k2_count_variance' });
T('transfers_gap', { title: L('ট্রান্সফার: পৌঁছায়নি / কম', 'Transfers not received or short', 'Transfer: পৌঁছায়নি / কম'), group: 'stock', needs: R('stock'), report: 'transfers_gap', head: ['transfers', 'not_received', 'short_received'], label: 'item', value: 'diff_qty',
  run: rep2('transfers_gap'), link: 'report/transfers_gap', defPeriod: 'last_30' });
T('exceptions_summary', { title: L('ব্যতিক্রম (গরমিল)', 'Exceptions', 'Exception'), group: 'control', needs: R('control'), report: 'exceptions_summary', head: ['total', 'open', 'red', 'yellow'], label: 'form', value: 'open',
  run: rep2('exceptions_summary', { group: 'form', sort: () => 'open:desc' }), link: 'exceptions' });
T('number_gaps', { title: L('কাগজের নম্বরের ফাঁক', 'Paper number gaps', 'Paper number-এর ফাঁক'), group: 'control', needs: R('control'), nodate: true, label: 'form_code', value: 'missing_count', params: ['locs'],
  run: async (p, X) => { const rows = rowsOf(await X.call('number_audit_summary', {})).filter((r) => Number(r.missing_count) > 0 && (!p.locs || !p.locs.length || p.locs.map(Number).includes(Number(r.location_id))));
    return { ok: true, key: 'number_gaps', columns: [col('form_code', 'ফর্ম', 'Form', 'text'), col('location', 'জায়গা', 'Place', 'text'), col('first_no', 'প্রথম', 'First', 'int'), col('last_no', 'শেষ', 'Last', 'int'), col('missing_count', 'বাদ পড়া', 'Missing', 'int')],
      rows: rows.map((r) => Object.assign({}, r, { location: locName(r.location_id) })).sort((a, b) => b.missing_count - a.missing_count), totals: { missing_count: rows.reduce((s, r) => s + Number(r.missing_count), 0), forms: rows.length }, derived: ['missing_count'],
      source: { kind: 'rpc', name: 'number_audit_summary', params: {} }, asOf: new Date().toISOString(), dataNeeded: false }; }, link: 'numaudit', head: ['missing_count', 'forms'] });
T('compliance', { title: L('ফর্ম জমার নিয়ম-পালন', 'Form submission compliance', 'Form জমার compliance'), group: 'control', needs: R('control'), report: 'x4_compliance', head: ['days', 'submitted_days', 'missing_days', 'late_submits'], label: 'form', value: 'missing_days',
  run: rep2('x4_compliance', { sort: () => 'missing_days:desc' }), link: 'report/x4_compliance', defPeriod: 'last_7' });
T('attendance_summary', { title: L('হাজিরার সারসংক্ষেপ', 'Attendance summary', 'হাজিরার summary'), group: 'people', needs: R('staff'), report: 'attendance_summary', head: ['present', 'absent', 'late'], label: 'person', value: 'absent',
  run: rep2('attendance_summary', { group: 'person', sort: () => 'absent:desc' }), link: 'report/attendance_summary' });
T('staff_outliers', { title: L('স্টাফের সূচক (মধ্যমার সাথে তুলনা)', 'Staff indicators vs the median', 'Staff সূচক vs median'), group: 'people', needs: (me) => (me.biz ? true : 'access'), label: 'staff_id', value: 'revenue',
  run: async (p, X) => { const [f, t] = periodDates(p.period); const args = { p_from: f, p_to: t, p_loc: p.locs && p.locs.length === 1 ? Number(p.locs[0]) : null };
    const rows = rowsOf(await X.call('biz_staff', args));
    return { ok: true, key: 'staff_outliers', columns: [col('staff_id', 'স্টাফ', 'Staff', 'text'), col('n', 'বিল', 'Bills', 'int'), col('revenue', 'বিক্রি', 'Sales', 'money'), col('discount_pct', 'ছাড় %', 'Discount %', 'pct'), col('med_discount_pct', 'মধ্যমা ছাড় %', 'Median discount %', 'pct'), col('void_pct', 'বাতিল %', 'Void %', 'pct'), col('med_void_pct', 'মধ্যমা বাতিল %', 'Median void %', 'pct')],
      rows: rows.slice().sort((a, b) => (Number(b.discount_pct) || 0) - (Number(a.discount_pct) || 0)), totals: null, period: { from: f, to: t }, source: { kind: 'rpc', name: 'biz_staff', params: args }, asOf: new Date().toISOString(), dataNeeded: rows.length === 0 }; }, link: 'biz' });
T('payroll', { title: L('বেতন ও অগ্রিম', 'Payroll and advances', 'বেতন ও advance'), group: 'people', needs: (me) => (me.is_owner ? true : 'access'), report: 't3_payroll', head: ['gross_pay', 'net_pay', 'adv_outstanding'], label: 'person', value: 'net_pay',
  run: rep2('t3_payroll', { sort: () => 'net_pay:desc' }), link: 'report/t3_payroll', salary: true, defPeriod: 'last_month' });
T('hour_weekday', { title: L('কোন সময়ে বেশি বিক্রি', 'Busiest hours', 'কোন সময়ে বেশি sale'), group: 'today', needs: R('sales'), report: 'hour_weekday', head: ['net', 'bills'], label: 'hour', value: 'net',
  run: rep1('hour_weekday', { group: 'hour', sort: () => 'hour:asc' }), link: 'report/hour_weekday', defPeriod: 'last_30' });
T('outlook', { title: L('সামনের ৭ দিনের হিসাব (সার্ভারের গড়)', 'Next 7 days outlook (server average)', 'সামনের ৭ দিন'), group: 'today', needs: (me) => (me.biz ? true : 'access'), nodate: true, params: ['locs'],
  run: async (p, X) => { const args = { p_loc: p.locs && p.locs.length === 1 ? Number(p.locs[0]) : null, p_ahead: 7, p_lookback: 28 }; const d = await X.call('biz_outlook', args) || {};
    const nums = Object.keys(d).filter((k) => typeof d[k] === 'number' || (typeof d[k] === 'string' && /^-?\d+(\.\d+)?$/.test(d[k])));
    return { ok: true, key: 'outlook', columns: [col('k', 'কী', 'What', 'text'), col('v', 'মান', 'Value', 'num')], rows: nums.map((k) => ({ k, v: d[k] })), totals: null, source: { kind: 'rpc', name: 'biz_outlook', params: args }, asOf: new Date().toISOString(), dataNeeded: nums.length === 0, interpretationOnly: true }; }, link: 'biz' });
T('needs_you', { title: L('আপনার অপেক্ষায়', 'Waiting for you', 'আপনার অপেক্ষায়'), group: 'today', nodate: true, params: [],
  run: async (p, X) => { const rows = rowsOf(await X.call('needs_you_oldest', { p_limit: 30 }));
    return { ok: true, key: 'needs_you', columns: [col('kind', 'ধরন', 'Kind', 'text'), col('label', 'কী', 'What', 'text'), col('location', 'জায়গা', 'Place', 'text'), col('since', 'কবে থেকে', 'Since', 'datetime'), col('age_h', 'ঘণ্টা', 'Hours', 'int')],
      rows: rows.map((r) => Object.assign({}, r, { location: r.location_id ? locName(r.location_id) : '', age_h: r.since ? Math.max(0, Math.floor((Date.now() - new Date(r.since).getTime()) / 3600e3)) : null })),
      totals: { waiting: rows.length }, derived: ['waiting'], source: { kind: 'rpc', name: 'needs_you_oldest', params: { p_limit: 30 } }, asOf: new Date().toISOString(), dataNeeded: false, rowLinks: 'route' }; }, link: 'pending', head: ['waiting'] });
T('health', { title: L('সেটআপ-চেক', 'Setup check', 'Setup check'), group: 'setup', needs: (me) => (me.health ? true : 'access'), nodate: true, params: [],
  run: async (p, X) => { const f = rowsOf(await X.call('assistant_health', {}));
    return { ok: true, key: 'health', columns: [col('sev', 'মাত্রা', 'Level', 'text'), col('title', 'কী', 'What', 'text'), col('detail', 'বিস্তারিত', 'Detail', 'text')],
      rows: f.map((x) => ({ sev: x.severity, title: lang() === 'en' ? x.title_en : x.title_bn, detail: x.detail, route: x.route, code: x.code })), findings: f,
      totals: { findings: f.length, bad: f.filter((x) => x.severity === 'bad').length, warn: f.filter((x) => x.severity === 'warn').length }, derived: ['findings', 'bad', 'warn'],
      source: { kind: 'rpc', name: 'assistant_health', params: {} }, asOf: new Date().toISOString(), dataNeeded: false, rowLinks: 'route' }; }, link: 'control', head: ['findings', 'bad', 'warn'] });
T('cash_position', { title: L('ক্যাশ, ব্যাংক ও মোবাইলের ব্যালান্স', 'Cash, bank and mobile balance', 'Cash, bank ও mobile balance'), group: 'money', needs: (me) => (me.daybook ? true : 'access'), nodate: true, params: ['locs'],
  run: async (p, X) => { const t = today(); const args = { p_loc: p.locs && p.locs.length === 1 ? Number(p.locs[0]) : null, p_from: t, p_to: t }; const d = await X.call('day_book', args) || {};
    const tot = d.totals || {}, cl = tot.close && typeof tot.close === 'object' ? tot.close : null;
    return { ok: true, key: 'cash_position', columns: [col('mode', 'কোথায়', 'Where', 'text'), col('amount', 'ব্যালান্স', 'Balance', 'money')],
      rows: cl ? [['cash', L('নগদ', 'Cash', 'Cash')], ['bank', L('ব্যাংক', 'Bank', 'Bank')], ['mobile', L('মোবাইল', 'Mobile', 'Mobile')]].map(([k, lb]) => ({ mode: lb[lang()] || lb.bn, amount: cl[k] })) : [],
      totals: cl ? { total: cl.total } : null, balances: !!d.balances, start: d.start || null, opening_known: !!d.opening_known, salaryHidden: !!d.salary_hidden,
      dataNeeded: !cl, needWhy: !d.start ? 'no_start' : !d.balances ? 'no_opening' : null, source: { kind: 'rpc', name: 'day_book', params: args }, asOf: new Date().toISOString(), period: { from: t, to: t } }; }, link: 'daybook', head: ['total'] });
T('locations', { title: L('জায়গার তালিকা', 'Locations', 'Location তালিকা'), group: 'setup', nodate: true, params: [],
  run: async () => { const ls = ((B.ENV && B.ENV.locs) || []);
    return { ok: true, key: 'locations', columns: [col('code', 'কোড', 'Code', 'text'), col('name', 'নাম', 'Name', 'text'), col('kind', 'ধরন', 'Kind', 'text'), col('status', 'অবস্থা', 'Status', 'text')],
      rows: ls.map((l) => ({ code: l.code, name: lang() === 'en' ? (l.name_en || l.name_bn) : l.name_bn, kind: l.kind || '', status: l.status || 'live' })), totals: { places: ls.length }, derived: ['places'],
      source: { kind: 'table', name: 'locations', params: {} }, asOf: new Date().toISOString(), dataNeeded: ls.length === 0 }; }, link: 'locations', head: ['places'] });
// optional modules: listed only when installed (assistant_me().optional) and executable by this person
const optRun = (names, key) => async (p, X) => { const m = pickOpt(X.me, names) || { name: [].concat(names)[0], args: [] }; const name = m.name; const [f, t] = periodDates(p.period); const args = {};
  (m.args || []).forEach((a) => { if (/as_?of|date$/.test(a)) args[a] = t; else if (/from/.test(a)) args[a] = f; else if (/to$/.test(a)) args[a] = t; else if (/loc/.test(a)) args[a] = p.locs && p.locs.length === 1 ? Number(p.locs[0]) : null; });
  const d = await X.call(name, args); const flat = []; const walk = (o, pre) => { if (!o || typeof o !== 'object' || flat.length > 60) return; Object.keys(o).forEach((k) => { const v = o[k]; if (typeof v === 'number' || (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v))) flat.push({ k: pre + k, v }); else if (typeof v === 'boolean') flat.push({ k: pre + k, v: String(v) }); else if (v && typeof v === 'object' && !Array.isArray(v)) walk(v, pre + k + '.'); }); };
  if (Array.isArray(d)) return { ok: true, key, columns: Object.keys(d[0] || {}).slice(0, 8).map((k) => col(k, k, k, typeof d[0][k] === 'number' ? 'num' : 'text')), rows: d.slice(0, 200), totals: null, source: { kind: 'rpc', name, params: args }, asOf: new Date().toISOString(), dataNeeded: d.length === 0 };
  walk(d, '');
  return { ok: true, key, columns: [col('k', 'কী', 'Item', 'text'), col('v', 'মান', 'Value', 'num')], rows: flat, totals: null, source: { kind: 'rpc', name, params: args }, asOf: new Date().toISOString(), dataNeeded: flat.length === 0 }; };
T('acc_balance_sheet', { title: L('ব্যালান্স শিট', 'Balance sheet', 'Balance sheet'), needs: opt(['acct_balance_sheet', 'balance_sheet']), run: optRun(['acct_balance_sheet', 'balance_sheet'], 'acc_balance_sheet'), link: 'accounts', nodate: true, params: ['locs'] });
T('acc_income_statement', { title: L('আয়-ব্যয় বিবরণী', 'Income statement', 'Income statement'), needs: opt(['acct_income_statement', 'income_statement']), run: optRun(['acct_income_statement', 'income_statement'], 'acc_income_statement'), link: 'accounts' });
T('acc_trial_balance', { title: L('রেওয়ামিল', 'Trial balance', 'Trial balance'), needs: opt(['acct_trial_balance', 'trial_balance']), run: optRun(['acct_trial_balance', 'trial_balance'], 'acc_trial_balance'), link: 'accounts' });
T('partners', { title: L('অংশীদারদের সারসংক্ষেপ', 'Partners overview', 'Partner overview'), needs: (me) => (me.is_owner ? opt('partner_overview')(me) : 'access'), run: optRun('partner_overview', 'partners'), link: 'partners', nodate: true, params: [] });
T('tiers', { title: L('গ্রাহক টিয়ার ব্যবহার', 'Customer tier use', 'Customer tier'), needs: opt('tier_usage_report'), run: optRun('tier_usage_report', 'tiers'), link: 'customers' });
T('backup', { title: L('ব্যাকআপের অবস্থা', 'Backup status', 'Backup status'), group: 'setup', needs: opt('backup_status'), run: optRun('backup_status', 'backup'), link: 'backup', nodate: true, params: [] });

// composite answers (assistant.js composes them from the tools above; they never compute a figure of their own)
const COMPOSITE = {
  fin_position: { title: L('আর্থিক অবস্থা (যতটা ডেটায় আছে)', 'Financial position (as far as the data goes)', 'আর্থিক অবস্থা'), group: 'money', parts: ['cash_position', 'receivables', 'payables', 'stock_value', 'pnl', 'acc_balance_sheet'] },
  what_changed: { title: L('কী বদলেছে ও কেন (সংখ্যা থেকে)', 'What changed and why (from the numbers)', 'কী বদলেছে ও কেন'), group: 'money', parts: ['sales_by_location', 'top_items', 'expense_trend'] },
  unusual: { title: L('অস্বাভাবিক কী আছে', 'Unusual things', 'অস্বাভাবিক কী'), group: 'control', parts: ['exceptions_summary', 'cash_short_over', 'voids', 'discounts', 'count_variance', 'wastage', 'number_gaps', 'transfers_gap'] },
  priorities: { title: L('আগে কী দেখবেন', 'What to look at first', 'আগে কী দেখবেন'), group: 'today', parts: ['health', 'needs_you', 'exceptions_summary', 'cash_short_over', 'payables', 'stock_low'] },
  help: { title: L('আমি কী পারি', 'What I can do', 'আমি কী পারি'), group: 'setup', parts: [] },
  notes: { title: L('মালিকের অনুমোদিত নিয়ম', 'Rules approved by the owner', 'Owner-এর অনুমোদিত নিয়ম'), group: 'setup', parts: [] },
};

// suggested questions per group (shown only when the tool is available to the person)
const SUGGEST = [
  ['today', 'sales_summary', L('আজ বিক্রি কত?', 'How are sales today?', 'আজ sale কত?')],
  ['today', 'needs_you', L('কী আমার অপেক্ষায় আছে?', 'What is waiting for me?', 'কী আমার অপেক্ষায়?')],
  ['today', 'priorities', L('আজ আগে কী দেখব?', 'What should I prioritise today?', 'আজ আগে কী দেখব?')],
  ['today', 'hour_weekday', L('কোন সময়ে বেশি বিক্রি হয়?', 'What are the busiest hours?', 'কোন সময়ে বেশি sale?')],
  ['money', 'fin_position', L('ব্যবসার আর্থিক অবস্থা কেমন?', 'What is our financial position?', 'আর্থিক অবস্থা কেমন?')],
  ['money', 'sales_by_location', L('এই মাসে কোন শাখা দুর্বল?', 'Which branch is weakest this month?', 'কোন branch দুর্বল?')],
  ['money', 'what_changed', L('গত মাসের তুলনায় কী বদলেছে?', 'What changed compared to the previous period?', 'কী বদলেছে?')],
  ['money', 'expenses_by_head', L('এই মাসে সবচেয়ে বড় খরচ কী?', 'Biggest expenses this month?', 'সবচেয়ে বড় খরচ?')],
  ['money', 'receivables', L('গ্রাহকদের কাছে কত বাকি?', 'How much do customers owe us?', 'Customer-দের বাকি কত?')],
  ['money', 'payables', L('সরবরাহকারীদের কত দেনা?', 'How much do we owe suppliers?', 'Supplier দেনা কত?')],
  ['money', 'item_margin', L('কোন আইটেমে লাভ বেশি?', 'Which items are most profitable?', 'কোন item-এ লাভ বেশি?')],
  ['stock', 'stock_low', L('কোন মাল কম আছে?', 'Which stock is low?', 'কোন stock কম?')],
  ['stock', 'top_items', L('এই মাসে সেরা ১০টি আইটেম', 'Top 10 items this month', 'সেরা ১০ item')],
  ['stock', 'expiry_soon', L('কী কী মেয়াদ শেষ হচ্ছে?', 'What is expiring soon?', 'কী expire হচ্ছে?')],
  ['stock', 'unusual', L('অস্বাভাবিক কিছু আছে?', 'Anything unusual?', 'অস্বাভাবিক কিছু?')],
  ['people', 'attendance_summary', L('এই মাসে কে বেশি অনুপস্থিত?', 'Who was absent most this month?', 'কে বেশি absent?')],
  ['people', 'discounts', L('কোন স্টাফের ছাড় বেশি?', 'Which staff give the most discount?', 'কোন staff-এর ছাড় বেশি?')],
  ['people', 'best_customers', L('সেরা গ্রাহক কারা?', 'Who are the best customers?', 'সেরা customer কারা?')],
  ['setup', 'health', L('সেটআপে কী বাকি বা ভুল?', 'What is incomplete or wrong in the setup?', 'Setup-এ কী বাকি?')],
  ['setup', 'kb', L('নতুন শোরুম কীভাবে চালু করব?', 'How do I set up a new location?', 'নতুন showroom কীভাবে চালু?')],
  ['setup', 'kb', L('ব্লাইন্ড কাউন্ট কীভাবে চালু করব?', 'How do I switch on blind count?', 'Blind count কীভাবে চালু?')],
  ['setup', 'help', L('তুমি কী পারো?', 'What can you do?', 'তুমি কী পারো?')],
];

function locName(id) { const l = ((B.ENV && B.ENV.locs) || []).find((x) => Number(x.id) === Number(id)); return l ? (lang() === 'en' ? (l.name_en || l.name_bn) : l.name_bn) : (id == null ? '' : '#' + id); }

B.assistantTools = { TOOLS, COMPOSITE, INTENTS, CONCEPTS: C, SUGGEST, PRICES, presetDates, periodDates, flt, locName, today, addDays };
})();
