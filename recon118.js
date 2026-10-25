/* Islamia BOS · Step B4 (phase118, tag bos118): three READ-ONLY reconciliation screens. NEW file; no existing file is rewritten (ia.js has 3 rec lines, nav.js reads 4 more grant codes, index.html has one script tag).
   #/stockrecon   Stock reconciliation: opening + production + purchases + transfers in + give-backs - used - sales - wastage - transit loss - transfers out +/- adjustments = closing,
                  per item and place, a variance flag (ledger against the cached balance) and the sales lines that did not leave stock as sold. RPC stock_recon_statement + stock_sales_unmatched.
   #/branchstmt   Factory-to-branch statement: sent, received, short, in transit (ageing), returned, sold, wasted, remaining, value at the transferred cost. RPC factory_branch_statement.
   #/netprofit    Net profit per branch and per product: contribution margin, then net profit after overhead, with a plain list of what is included and what is not. RPC net_profit_report.
   Access: the server decides (grants view_stock_recon / view_branch_statement / view_net_profit; cost and profit figures only for cost-right holders). The screens only show what comes back.
   CSV: for the owner or an export_data holder; the export is written to the audit log first (recon_export_log118), the file is built from the rows on screen (formula-injection safe, BOM for Excel).
   Handlers are prefixed rc_. Language rule: English mode is all English; Bangla mode keeps common words in English; the mix is Bangla + English words. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.L || (B.recon118 && B.recon118.loaded)) return;
const { sb, S, esc, toast, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);

const X = {
  // shared
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), place: L('জায়গা', 'Place', 'Place'), allPlaces: L('সব জায়গা', 'All places', 'সব place'),
  show: L('দেখুন', 'Show', 'Show'), csv: L('CSV নামান', 'Download CSV', 'CSV download'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  noaccess: L('এই পাতা দেখার অনুমতি নেই', 'You are not allowed to see this page', 'এই page দেখার permission নেই'),
  fail: L('আনা যায়নি', 'Could not load', 'Load করা যায়নি'), notinstalled: L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part is not installed yet', 'Database অংশ এখনও চালু হয়নি'),
  none: L('এই সময়ে কিছু নেই', 'Nothing in this period', 'এই period-এ কিছু নেই'), item: L('আইটেম', 'Item', 'Item'), unit: L('একক', 'Unit', 'Unit'),
  find: L('আইটেম খুঁজুন', 'Find an item', 'Item খুঁজুন'), only: L('শুধু গরমিল / সতর্কতা', 'Only rows with a flag', 'শুধু গরমিল / flag'), cat: L('ক্যাটাগরি (ঐচ্ছিক)', 'Category (optional)', 'Category (optional)'),
  flags: L('চিহ্ন', 'Flags', 'Flags'), truncated: L('আরও সারি আছে — সীমা ছাড়িয়ে গেছে, ডেট বা জায়গা ছোট করুন', 'More rows exist - narrow the dates or the place', 'আরও row আছে — date বা place ছোট করুন'),
  csvFail: L('CSV হয়নি (অনুমতি লাগবে)', 'CSV not made (permission needed)', 'CSV হয়নি (permission লাগবে)'), csvDone: L('CSV নামানো হয়েছে', 'CSV downloaded', 'CSV নামানো হয়েছে'),
  all: L('সব', 'All', 'All'), total: L('মোট', 'Total', 'Total'), badPeriod: L('ডেটের সীমা ঠিক নয় (সর্বোচ্চ ৩৭০ দিন)', 'The dates are not valid (370 days at most)', 'Date-এর সীমা ঠিক নয় (সর্বোচ্চ ৩৭০ দিন)'),
  // stock reconciliation
  sr_title: L('স্টক মিলানো', 'Stock reconciliation', 'Stock মিলানো'),
  sr_intro: L('প্রতিটি আইটেম ও জায়গার জন্য: শুরু + উৎপাদন + কেনা + আসা + ফেরত − ব্যবহার − বিক্রি − নষ্ট − পথে হারানো − গেছে ± সমন্বয় = শেষ। "বাকি (খাতা)" আর জমা স্টকের মিল না থাকলে ফারাক দেখায়।',
    'For each item and place: opening + production + purchases + transfers in + give-backs - used in production - sales - wastage - transit loss - transfers out +/- adjustments = closing. If the ledger and the stored balance disagree, the difference is flagged.',
    'প্রতিটি item ও place-এর জন্য: opening + production + purchase + transfer in + give-back − used − sales − wastage − transit loss − transfer out ± adjustment = closing। Ledger আর stored balance না মিললে ফারাক flag হয়।'),
  c_open: L('শুরু', 'Opening', 'Opening'), c_prod: L('উৎপাদন', 'Production', 'Production'), c_purch: L('কেনা', 'Purchases', 'Purchases'), c_in: L('আসা', 'Transfers in', 'Transfer in'),
  c_back: L('ফেরত (গ্রাহক)', 'Give-backs', 'Give-back'), c_used: L('ব্যবহার', 'Used', 'Used'), c_sales: L('বিক্রি', 'Sales', 'Sales'), c_waste: L('নষ্ট', 'Wastage', 'Wastage'),
  c_tloss: L('পথে হারানো', 'Transit loss', 'Transit loss'), c_out: L('গেছে', 'Transfers out', 'Transfer out'), c_adj: L('সমন্বয়', 'Adjustments', 'Adjustment'),
  c_close: L('শেষ', 'Closing', 'Closing'), c_bal: L('জমা স্টক', 'Stored balance', 'Stored balance'), c_var: L('ফারাক', 'Variance', 'Variance'),
  c_avg: L('গড় কস্ট', 'Avg cost', 'Avg cost'), c_cval: L('শেষের মূল্য', 'Closing value', 'Closing value'),
  f_variance: L('খাতা ≠ জমা স্টক', 'Ledger ≠ stored balance', 'Ledger ≠ stored balance'), f_unbalanced: L('হিসাব মেলেনি', 'Does not add up', 'হিসাব মেলেনি'),
  f_adjusted: L('গণনা সমন্বয় আছে', 'Has an adjustment', 'Adjustment আছে'), f_negative: L('স্টক ঋণাত্মক', 'Negative stock', 'Negative stock'),
  f_short: L('ঘাটতি', 'Short', 'Short'), f_transit_old: L('পথে অনেক দিন', 'Old in transit', 'পথে অনেক দিন'), f_receive_mismatch: L('গ্রহণ মেলেনি', 'Receipt mismatch', 'Receipt মেলেনি'),
  um_title: L('বিক্রির লাইন যা স্টকে মেলেনি', 'Sales lines not matched in the stock ledger', 'Sale-এর line যা stock ledger-এ মেলেনি'),
  um_intro: L('বিক্রির প্রতিটি লাইন বনাম সেই বিক্রিতে স্টক থেকে যা বাদ গেছে। শুধু সংখ্যা, কস্ট নয়।', 'Each sale line against what actually left stock for that sale. Quantities only, no cost.', 'প্রতিটি sale line বনাম সেই sale-এ stock থেকে যা বাদ গেছে। শুধু সংখ্যা, cost নয়।'),
  um_ok: L('সব বিক্রি স্টকের সাথে মিলেছে ✓', 'Every sale line matches the stock ledger ✓', 'সব sale stock-এর সাথে মিলেছে ✓'),
  k_untracked: L('স্টক রাখা হয় না', 'Item is not stock-tracked', 'Stock রাখা হয় না'), k_unit_unknown: L('একক রূপান্তর নেই — স্টক কমেনি', 'No unit conversion - stock not reduced', 'Unit conversion নেই — stock কমেনি'),
  k_not_posted: L('স্টক থেকে বাদ যায়নি', 'Nothing left stock', 'Stock থেকে বাদ যায়নি'), k_short_posted: L('কম বাদ গেছে', 'Less left stock than sold', 'কম বাদ গেছে'),
  k_over_posted: L('বেশি বাদ গেছে', 'More left stock than sold', 'বেশি বাদ গেছে'),
  u_receipt: L('রসিদ', 'Receipt', 'Receipt'), u_date: L('ডেট', 'Date', 'Date'), u_kind: L('কী হয়েছে', 'What happened', 'কী হয়েছে'), u_sold: L('বিক্রি (মূল একক)', 'Sold (base unit)', 'Sold (base unit)'),
  u_led: L('স্টক থেকে বাদ', 'Left stock', 'Stock থেকে বাদ'), u_diff: L('ফারাক', 'Difference', 'Difference'),
  // branch statement
  bs_title: L('কারখানা থেকে শাখার হিসাব', 'Factory-to-branch statement', 'Factory থেকে branch-এর হিসাব'),
  bs_intro: L('কত পাঠানো হলো, কত পৌঁছাল, কত ঘাটতি, কত পথে (বয়সসহ), কত ফেরত, বিক্রি, নষ্ট, আর কত বাকি। মূল্য পাঠানোর সময়ের কস্টে।',
    'What was sent, what arrived, what is short, what is still on the way (with age), what came back, was sold or wasted, and what remains. Values are at the cost it was sent at.',
    'কত পাঠানো, কত পৌঁছাল, কত short, কত পথে (age সহ), কত ফেরত, sold, wasted, আর কত remaining। Value পাঠানোর সময়ের cost-এ।'),
  b_sent: L('পাঠানো (এসেছে)', 'Sent to here', 'Sent to here'), b_recv: L('পৌঁছেছে', 'Received', 'Received'), b_short: L('ঘাটতি', 'Short', 'Short'), b_shortp: L('ঘাটতি %', 'Short %', 'Short %'),
  b_tr: L('পথে', 'In transit', 'In transit'), b_a0: L('পথে ≤ প্রথম সীমা', 'Transit: young', 'Transit: young'), b_a1: L('পথে মাঝারি', 'Transit: middle', 'Transit: middle'), b_a2: L('পথে পুরনো', 'Transit: old', 'Transit: old'),
  b_ret: L('ফেরত পাঠানো', 'Returned', 'Returned'), b_sold: L('বিক্রি', 'Sold', 'Sold'), b_wasted: L('নষ্ট', 'Wasted', 'Wasted'), b_rem: L('বাকি', 'Remaining', 'Remaining'),
  b_out: L('পাঠিয়েছে (বাইরে)', 'Sent out', 'Sent out'), b_sv: L('পাঠানোর মূল্য', 'Sent value', 'Sent value'), b_rv: L('পৌঁছানোর মূল্য', 'Received value', 'Received value'),
  b_shv: L('ঘাটতির মূল্য', 'Short value', 'Short value'), b_tv: L('পথের মূল্য', 'In-transit value', 'In-transit value'), b_remv: L('বাকির মূল্য', 'Remaining value', 'Remaining value'),
  b_age: L('পথের বয়সের সীমা (ঘণ্টা)', 'Transit age limits (hours)', 'Transit age limit (ঘণ্টা)'), b_loc: L('জায়গা অনুযায়ী', 'By place', 'Place অনুযায়ী'),
  b_nsent: L('চালান', 'Transfers', 'Transfers'), b_nshort: L('ঘাটতির চালান', 'Short transfers', 'Short transfers'), b_ntr: L('পথের চালান', 'On the way', 'On the way'),
  // net profit
  np_title: L('নিট লাভ (পণ্য ও শাখা)', 'Net profit (product and branch)', 'Net profit (product ও branch)'),
  np_intro: L('বিক্রি − কস্ট = মোট লাভ (শুধু কস্ট জানা অংশ); − নষ্ট − কার্ড ফি − ভ্যারিয়েবল খরচ = কন্ট্রিবিউশন মার্জিন; − অন্য খরচ − বেতন − মাসিক ফিক্সড − ভাগ করা বিল = ওভারহেডের পর নিট লাভ।',
    'Sales - cost = gross profit (cost-known part only); - wastage - card fees - variable expenses = contribution margin; - other expenses - salary - monthly fixed cost - shared bills = net profit after overhead.',
    'Sales − cost = gross profit (শুধু cost-জানা অংশ); − wastage − card fee − variable খরচ = contribution margin; − অন্য খরচ − salary − monthly fixed − shared bill = overhead-এর পর net profit।'),
  t_branch: L('শাখা', 'By branch', 'By branch'), t_product: L('পণ্য', 'By product', 'By product'), t_pb: L('পণ্য × শাখা', 'Product × branch', 'Product × branch'),
  p_net: L('নিট বিক্রি', 'Net sales', 'Net sales'), p_unc: L('কস্ট অজানা বিক্রি', 'Sales, cost unknown', 'Sales, cost অজানা'), p_cogs: L('কস্ট (COGS)', 'Cost of goods', 'Cost of goods'),
  p_gp: L('মোট লাভ', 'Gross profit', 'Gross profit'), p_gm: L('মোট লাভ %', 'Gross %', 'Gross %'), p_waste: L('নষ্ট (কস্টে)', 'Wastage at cost', 'Wastage at cost'),
  p_fee: L('কার্ড ফি', 'Card fees', 'Card fees'), p_var: L('ভ্যারিয়েবল খরচ', 'Variable expenses', 'Variable expenses'), p_cm: L('কন্ট্রিবিউশন মার্জিন', 'Contribution margin', 'Contribution margin'),
  p_cmp: L('কন্ট্রিবিউশন %', 'Contribution %', 'Contribution %'), p_oth: L('অন্য খরচ', 'Other expenses', 'Other expenses'), p_sal: L('বেতন (শিট)', 'Salary (sheet)', 'Salary (sheet)'),
  p_fix: L('মাসিক ফিক্সড', 'Monthly fixed', 'Monthly fixed'), p_shr: L('ভাগ করা বিল', 'Shared bills', 'Shared bills'), p_np: L('ওভারহেডের পর নিট লাভ', 'Net profit after overhead', 'Net profit after overhead'),
  p_npp: L('নিট %', 'Net %', 'Net %'), p_qty: L('পরিমাণ', 'Qty', 'Qty'), p_avar: L('ভাগ: ভ্যারিয়েবল', 'Allocated: variable', 'Allocated: variable'), p_aoh: L('ভাগ: ওভারহেড', 'Allocated: overhead', 'Allocated: overhead'),
  p_alloc: L('পণ্যের ফি, ভ্যারিয়েবল খরচ ও ওভারহেড = শাখার অঙ্ক × সেই শাখার নিট বিক্রিতে পণ্যের অংশ (ভাগ করা অঙ্ক, মাপা খরচ নয়)।',
    'Product fees, variable expenses and overhead = the branch amount x the product share of that branch net sales (an allocation, not a measured cost).',
    'Product-এর fee, variable খরচ ও overhead = branch-এর অঙ্ক × সেই branch-এর net sales-এ product-এর অংশ (allocation, মাপা খরচ নয়)।'),
  p_unal: L('কোনো জায়গায় ধরা হয়নি এমন ভাগ করা বিল', 'Shared bills not charged to any place', 'কোনো place-এ ধরা হয়নি এমন shared bill'),
  p_company: L('সব জায়গা মিলিয়ে', 'All places together', 'সব place মিলিয়ে'),
  g_uncosted_sales: L('কস্ট অজানা বিক্রি আছে (লাভে ধরা হয়নি)', 'Sales with unknown cost (not in profit)', 'Cost অজানা sale আছে (profit-এ ধরা হয়নি)'),
  g_salary_not_recorded: L('বেতনের শিট নেই', 'No salary sheet', 'Salary sheet নেই'), g_wastage_uncosted: L('নষ্টের কস্ট অজানা', 'Wastage cost unknown', 'Wastage cost অজানা'),
  g_complete: L('সম্পূর্ণ', 'Complete', 'Complete'),
  inc_h: L('এই হিসাবে যা ধরা হয়েছে', 'Included in these figures', 'এই হিসাবে যা ধরা হয়েছে'), exc_h: L('যা ধরা হয়নি', 'Not included', 'যা ধরা হয়নি'),
  i_net_sales_after_discount_and_returns: L('নিট বিক্রি (ছাড় ও ফেরতের পর)', 'Net sales (after discount and returns)', 'Net sales (discount ও return-এর পর)'),
  i_cogs_from_stock_ledger_cost: L('বিক্রিত মালের কস্ট (স্টক খাতা / সেটিং অনুযায়ী)', 'Cost of goods sold (stock ledger, per the report cost switch)', 'Sold goods-এর cost (stock ledger / setting অনুযায়ী)'),
  i_wastage_and_transit_loss_at_ledger_cost: L('নষ্ট ও পথে হারানো (খাতার কস্টে)', 'Wastage and transit loss at ledger cost', 'Wastage ও transit loss (ledger cost-এ)'),
  i_card_fees_by_settlement_date: L('কার্ড ফি (সেটেলমেন্টের ডেটে)', 'Card fees (by settlement date)', 'Card fee (settlement date-এ)'),
  i_variable_expense_heads: L('ভ্যারিয়েবল খরচের হেড (সেটিং)', 'Variable expense heads (setting)', 'Variable expense head (setting)'),
  i_other_expenses_quick_and_form_10_2: L('অন্য খরচ (দ্রুত খরচ ও ফর্ম 11-1)', 'Other expenses (quick expenses and form 11-1)', 'অন্য খরচ (quick expense ও form 11-1)'),
  i_salary_sheet_02_2: L('বেতন (ফর্ম 21-1 শিট)', 'Salary (form 21-1 sheet)', 'Salary (form 21-1 sheet)'), i_monthly_fixed_cost: L('শাখার মাসিক ফিক্সড খরচ (দিন অনুপাতে)', 'Branch monthly fixed cost (by days)', 'Branch monthly fixed cost (দিন অনুপাতে)'),
  i_shared_bills_attributed_pro_rated_by_days: L('জায়গায় বসানো ভাগ করা বিল (দিন অনুপাতে)', 'Shared bills attributed to a place (pro-rated by days)', 'Place-এ বসানো shared bill (দিন অনুপাতে)'),
  e_profit_on_sales_with_unknown_cost: L('কস্ট অজানা বিক্রির লাভ', 'Profit on sales with unknown cost', 'Cost অজানা sale-এর profit'),
  e_payroll_app_payments: L('পেরোল অ্যাপের বেতন পেমেন্ট', 'Payroll app payments', 'Payroll app-এর salary payment'),
  e_shared_bills_not_attributed_to_a_place: L('কোনো জায়গায় না বসানো ভাগ করা বিল', 'Shared bills not attributed to a place', 'Place-এ না বসানো shared bill'),
  e_online_delivery_charge: L('অনলাইন ডেলিভারি চার্জ', 'Online delivery charge', 'Online delivery charge'),
  e_depreciation_and_other_books_only_entries: L('অবচয় ও শুধু-খাতার অন্য এন্ট্রি', 'Depreciation and other books-only entries', 'Depreciation ও books-only অন্য entry'),
  e_product_conversion_cost_when_factory_costing_is_off: L('কারখানার খরচ হিসাব বন্ধ থাকলে পণ্যের রূপান্তর খরচ', 'Product conversion cost when factory costing is off', 'Factory costing বন্ধ থাকলে conversion cost'),
  vh: L('ভ্যারিয়েবল ধরা হেড', 'Heads counted as variable', 'Variable ধরা head'), vh_none: L('কোনো হেড নয়', 'none', 'কোনো head নয়'),
};
const T = (k) => lab(X[k]);
const TL = (pre, k) => (X[pre + k] ? lab(X[pre + k]) : k);

/* ---------- small helpers ---------- */
const own = () => !!(S.ctx && S.ctx.is_owner);
const flags = () => { try { return (window.BOS_NAV && window.BOS_NAV.grantFlags && window.BOS_NAV.grantFlags()) || {}; } catch (e) { return {}; } };
const canCsv = () => own() || flags().export_data === true;
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const monthStart = () => today().slice(0, 8) + '01';
const fm = (n, d) => (n === null || n === undefined || n === '' || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: d === undefined ? 2 : d }));
const nm = (o, a, b) => lab({ bn: o[a] || o[b], mix: o[a] || o[b], en: o[b] || o[a] });
const days = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 864e5);
let LOCS = null;
async function loadLocs() {
  if (LOCS) return LOCS;
  try { const r = await sb.from('locations').select('id,name_bn,name_en').order('id'); LOCS = (r && r.data) || []; } catch (e) { LOCS = []; }
  return LOCS;
}
const locOpts = (sel) => `<option value="">${esc(T('allPlaces'))}</option>` + (LOCS || []).map((l) => `<option value="${l.id}" ${String(l.id) === String(sel) ? 'selected' : ''}>${esc(nm(l, 'name_bn', 'name_en'))}</option>`).join('');
function errMsg(e) {
  const m = String((e && e.message) || e || '');
  if (/does not exist|schema cache|PGRST202|Could not find the function/i.test(m)) return T('notinstalled');
  if (/not allowed|permission/i.test(m)) return T('noaccess');
  if (/bad_period|period_too_long/i.test(m)) return T('badPeriod');
  return T('fail');
}
const colorNum = (v) => (Number(v) < 0 ? ' style="color:var(--bad,#b3261e)"' : '');
const th = (k, cls) => `<th${cls ? ` class="${cls}"` : ''}>${esc(typeof k === 'string' ? T(k) : lab(k))}</th>`;
const chip = (text, tone) => `<span class="chip ${tone || ''}">${esc(text)}</span>`;
function csvCell(v) {
  if (v === null || v === undefined) return '';
  let s = String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && /[^\d.\-]/.test(s) && s.length > 1)) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
function toCSV(head, rows) { return '﻿' + [head.map(csvCell).join(','), ...rows.map((r) => r.map(csvCell).join(','))].join('\r\n') + '\r\n'; }
function download(name, text) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
async function exportCsv(key, head, rows, filters) {
  if (!canCsv()) return;
  try {
    const r = await sb.rpc('recon_export_log118', { p_key: key, p_rows: rows.length, p_filters: filters || {} });
    if (r && r.error) throw r.error;
  } catch (e) { toast(T('csvFail')); return; }
  download(`${key}-${filters.from || ''}_${filters.to || ''}.csv`, toCSV(head, rows));
  toast(T('csvDone'));
}
function filterBar(st, extra) {
  return `<div class="row wrap"><label>${esc(T('from'))}<input type="date" id="rc_f" value="${esc(st.from)}"></label><label>${esc(T('to'))}<input type="date" id="rc_t" value="${esc(st.to)}"></label>
    <select id="rc_l" aria-label="${esc(T('place'))}">${locOpts(st.loc)}</select>${extra || ''}</div>
    <div class="row wrap"><button class="primary" data-act="rc_go">${esc(T('show'))}</button>${canCsv() ? `<button data-act="rc_csv">${esc(T('csv'))}</button>` : ''}</div>`;
}
function readBar(st) {
  const f = $('#rc_f'), t = $('#rc_t'), l = $('#rc_l'), c = $('#rc_c');
  if (f && f.value) st.from = f.value; if (t && t.value) st.to = t.value; if (l) st.loc = l.value; if (c) st.cat = c.value.trim();
}
const rpcArgs = (st, extra) => Object.assign({ p_from: st.from, p_to: st.to, p_loc: st.loc === '' ? null : Number(st.loc) }, extra || {});
const flagChips = (arr) => (arr || []).map((f) => chip(TL('f_', f), f === 'adjusted' || f === 'short' ? 'info' : 'warn')).join(' ');

/* ======================= 1. stock reconciliation ======================= */
const SR = { from: null, to: null, loc: '', cat: '', q: '', only: false, data: null, um: null, kind: '', busy: false, err: null };
function srRows() {
  const q = SR.q.trim().toLowerCase();
  return ((SR.data && SR.data.rows) || []).filter((r) => (!SR.only || (r.flags || []).length) && (!q || (String(r.item_code) + ' ' + String(r.item_bn || '') + ' ' + String(r.item_en || '')).toLowerCase().includes(q)));
}
const SR_COLS = [['c_open', 'opening_qty'], ['c_prod', 'production_qty'], ['c_purch', 'purchases_qty'], ['c_in', 'transfer_in_qty'], ['c_back', 'give_back_qty'], ['c_used', 'used_qty'], ['c_sales', 'sales_qty'],
  ['c_waste', 'wastage_qty'], ['c_tloss', 'transit_loss_qty'], ['c_out', 'transfer_out_qty'], ['c_adj', 'adjustments_qty'], ['c_close', 'closing_qty'], ['c_bal', 'balance_qty'], ['c_var', 'variance_qty']];
function srHTML() {
  if (SR.busy && !SR.data) return `<p class="muted center pad">${esc(T('loading'))}</p>`;
  if (SR.err) return `<div class="notice bad">${esc(SR.err)}</div>`;
  const d = SR.data; if (!d) return '';
  const cost = d.cost_visible === true, rows = srRows(), sm = d.summary || {};
  const head = `<tr>${th('place')}${th('item')}${th('unit')}${SR_COLS.map((c) => th(c[0], 'n')).join('')}${cost ? th('c_avg', 'n') + th('c_cval', 'n') : ''}${th('flags')}</tr>`;
  const body = rows.map((r) => `<tr><td>${esc(nm(r, 'location_bn', 'location_en'))}</td><td style="text-align:left"><b>${esc(r.item_code)}</b> ${esc(nm(r, 'item_bn', 'item_en'))}</td><td>${esc(r.unit || '')}</td>`
    + SR_COLS.map((c) => `<td class="n"${c[1] === 'variance_qty' && Number(r[c[1]]) !== 0 ? ' style="font-weight:700;color:var(--bad,#b3261e)"' : colorNum(r[c[1]])}>${esc(fm(r[c[1]], 3))}</td>`).join('')
    + (cost ? `<td class="n">${esc(fm(r.avg_cost))}</td><td class="n">${esc(fm(r.closing_value))}</td>` : '') + `<td>${flagChips(r.flags)}</td></tr>`).join('');
  return `<div class="row wrap">${chip(`${fm(sm.items, 0)} ${T('item')}`)} ${sm.with_variance ? chip(`${sm.with_variance} · ${TL('f_', 'variance')}`, 'warn') : ''} ${sm.unbalanced ? chip(`${sm.unbalanced} · ${TL('f_', 'unbalanced')}`, 'warn') : ''} ${sm.adjusted ? chip(`${sm.adjusted} · ${TL('f_', 'adjusted')}`, 'info') : ''}</div>
    ${d.truncated ? `<div class="notice warn">${esc(T('truncated'))}</div>` : ''}
    ${rows.length ? `<div class="scrollx"><table class="bz" id="rc_tbl"><thead>${head}</thead><tbody>${body}</tbody></table></div>` : `<p class="muted center pad">${esc(T('none'))}</p>`}`;
}
function umHTML() {
  const u = SR.um; if (!u) return '';
  const counts = u.counts || {}, kinds = Object.keys(counts);
  const rows = (u.rows || []).filter((r) => !SR.kind || r.kind === SR.kind);
  const tone = (k) => (k === 'untracked' ? 'info' : 'warn');
  const chips = `<div class="row wrap"><button type="button" class="tog ${SR.kind === '' ? 'on' : ''}" data-act="rc_kind" data-v="" aria-pressed="${SR.kind === ''}">${esc(T('all'))} · ${fm(u.total, 0)}</button>`
    + kinds.map((k) => `<button type="button" class="tog ${SR.kind === k ? 'on' : ''}" data-act="rc_kind" data-v="${esc(k)}" aria-pressed="${SR.kind === k}">${esc(TL('k_', k))} · ${counts[k]}</button>`).join('') + '</div>';
  const body = rows.map((r) => `<tr><td>${esc(String(r.receipt))}</td><td>${esc(String(r.sale_date).slice(0, 10))}</td><td>${esc(nm(r, 'location_bn', 'location_en'))}</td><td style="text-align:left"><b>${esc(r.item_code)}</b> ${esc(nm(r, 'item_bn', 'item_en'))}</td>`
    + `<td style="text-align:left">${chip(TL('k_', r.kind), tone(r.kind))}</td><td class="n">${esc(fm(r.sold_base_qty ?? r.sold_qty, 3))} ${esc(r.base_unit || '')}</td><td class="n">${esc(fm(r.ledger_qty, 3))}</td><td class="n"${colorNum(r.diff_qty)}>${esc(fm(r.diff_qty, 3))}</td></tr>`).join('');
  return `<h3>${esc(T('um_title'))}</h3><p class="muted">${esc(T('um_intro'))}</p>
    ${u.total ? chips + `<div class="scrollx"><table class="bz"><thead><tr>${th('u_receipt')}${th('u_date')}${th('place')}${th('item')}${th('u_kind')}${th('u_sold', 'n')}${th('u_led', 'n')}${th('u_diff', 'n')}</tr></thead><tbody>${body}</tbody></table></div>`
      : `<div class="notice ok">${esc(T('um_ok'))}</div>`}`;
}
function paintSR() { const el = $('#rc_res'); if (el) el.innerHTML = srHTML() + umHTML(); }
async function loadSR() {
  SR.busy = true; SR.err = null; paintSR();
  try {
    const [a, b] = await Promise.all([
      sb.rpc('stock_recon_statement', rpcArgs(SR, { p_category: SR.cat || null })),
      sb.rpc('stock_sales_unmatched', rpcArgs(SR)),
    ]);
    if (a && a.error) throw a.error; if (b && b.error) throw b.error;
    SR.data = a.data; SR.um = b.data;
  } catch (e) { SR.err = errMsg(e); SR.data = null; SR.um = null; }
  SR.busy = false; paintSR();
}
async function viewStock() {
  await loadLocs(); SR.from = SR.from || monthStart(); SR.to = SR.to || today();
  shell(T('sr_title'), `<p class="muted">${esc(T('sr_intro'))}</p>${filterBar(SR, `<input id="rc_c" placeholder="${esc(T('cat'))}" value="${esc(SR.cat)}" autocomplete="off">`)}
    <div class="row wrap"><input id="rc_q" placeholder="${esc(T('find'))}" value="${esc(SR.q)}" autocomplete="off"><button type="button" class="tog ${SR.only ? 'on' : ''}" data-act="rc_only" aria-pressed="${SR.only}">${esc(T('only'))}</button></div>
    <div id="rc_res"></div>`, true);
  if (SR.data) paintSR(); else loadSR();
}
function csvSR() {
  const d = SR.data; if (!d) return;
  const cost = d.cost_visible === true;
  const head = [T('place'), T('item'), T('unit'), ...SR_COLS.map((c) => T(c[0])), ...(cost ? [T('c_avg'), T('c_cval')] : []), T('flags')];
  const rows = srRows().map((r) => [nm(r, 'location_bn', 'location_en'), r.item_code + ' ' + nm(r, 'item_bn', 'item_en'), r.unit || '', ...SR_COLS.map((c) => r[c[1]]), ...(cost ? [r.avg_cost, r.closing_value] : []), (r.flags || []).map((f) => TL('f_', f)).join('; ')]);
  return exportCsv('stock_recon', head, rows, { from: SR.from, to: SR.to, loc: SR.loc, category: SR.cat });
}

/* ======================= 2. factory-to-branch statement ======================= */
const BS = { from: null, to: null, loc: '', cat: '', q: '', only: false, data: null, busy: false, err: null };
const BS_COLS = [['c_open', 'opening_qty'], ['b_sent', 'sent_in_qty'], ['b_recv', 'received_qty'], ['b_short', 'short_qty'], ['b_shortp', 'short_pct'], ['b_tr', 'in_transit_qty'], ['b_a0', 'in_transit_age_0_qty'],
  ['b_a1', 'in_transit_age_1_qty'], ['b_a2', 'in_transit_age_2_qty'], ['b_out', 'sent_out_qty'], ['b_ret', 'returned_qty'], ['b_sold', 'sold_qty'], ['b_wasted', 'wasted_qty'], ['b_rem', 'remaining_qty']];
const BS_COST = [['b_sv', 'sent_value'], ['b_rv', 'received_value'], ['b_shv', 'short_value'], ['b_tv', 'in_transit_value'], ['b_remv', 'remaining_value']];
function bsRows() {
  const q = BS.q.trim().toLowerCase();
  return ((BS.data && BS.data.rows) || []).filter((r) => (!BS.only || (r.flags || []).length) && (!q || (String(r.item_code) + ' ' + String(r.item_bn || '') + ' ' + String(r.item_en || '')).toLowerCase().includes(q)));
}
function bsHTML() {
  if (BS.busy && !BS.data) return `<p class="muted center pad">${esc(T('loading'))}</p>`;
  if (BS.err) return `<div class="notice bad">${esc(BS.err)}</div>`;
  const d = BS.data; if (!d) return '';
  const cost = d.cost_visible === true, rows = bsRows(), ag = d.ageing_hours || [];
  const byLoc = (d.by_location || []).map((x) => `<div class="card"><b>${esc(nm(x, 'location_bn', 'location_en'))}</b><div class="muted">${esc(T('b_nsent'))}: ${fm(x.transfers_sent, 0)} · ${esc(T('b_nshort'))}: ${fm(x.transfers_short, 0)} · ${esc(T('b_ntr'))}: ${fm(x.transfers_in_transit, 0)}</div>`
    + (cost ? `<div class="muted">${esc(T('b_sv'))}: ${esc(fm(x.sent_value))} · ${esc(T('b_rv'))}: ${esc(fm(x.received_value))} · ${esc(T('b_shv'))}: ${esc(fm(x.short_value))}${x.short_pct_of_value !== undefined ? ' (' + esc(fm(x.short_pct_of_value)) + '%)' : ''} · ${esc(T('b_tv'))}: ${esc(fm(x.in_transit_value))}</div>` : '') + '</div>').join('');
  const head = `<tr>${th('place')}${th('item')}${th('unit')}${BS_COLS.map((c) => th(c[0], 'n')).join('')}${cost ? BS_COST.map((c) => th(c[0], 'n')).join('') : ''}${th('flags')}</tr>`;
  const body = rows.map((r) => `<tr><td>${esc(nm(r, 'location_bn', 'location_en'))}</td><td style="text-align:left"><b>${esc(r.item_code)}</b> ${esc(nm(r, 'item_bn', 'item_en'))}</td><td>${esc(r.unit || '')}</td>`
    + BS_COLS.map((c) => `<td class="n"${c[1] === 'short_qty' && Number(r.short_qty) > 0 ? ' style="font-weight:700;color:var(--warn,#8a5a00)"' : colorNum(r[c[1]])}>${esc(fm(r[c[1]], c[1] === 'short_pct' ? 2 : 3))}</td>`).join('')
    + (cost ? BS_COST.map((c) => `<td class="n">${esc(fm(r[c[1]]))}</td>`).join('') : '') + `<td>${flagChips(r.flags)}</td></tr>`).join('');
  return `${ag.length === 2 ? `<p class="muted">${esc(T('b_age'))}: ${esc(String(ag[0]))} / ${esc(String(ag[1]))}</p>` : ''}
    ${byLoc ? `<h3>${esc(T('b_loc'))}</h3><div class="stack">${byLoc}</div>` : ''}
    ${d.truncated ? `<div class="notice warn">${esc(T('truncated'))}</div>` : ''}
    ${rows.length ? `<div class="scrollx"><table class="bz" id="rc_tbl"><thead>${head}</thead><tbody>${body}</tbody></table></div>` : `<p class="muted center pad">${esc(T('none'))}</p>`}`;
}
function paintBS() { const el = $('#rc_res'); if (el) el.innerHTML = bsHTML(); }
async function loadBS() {
  BS.busy = true; BS.err = null; paintBS();
  try {
    const r = await sb.rpc('factory_branch_statement', rpcArgs(BS, { p_category: BS.cat || null }));
    if (r && r.error) throw r.error;
    BS.data = r.data;
  } catch (e) { BS.err = errMsg(e); BS.data = null; }
  BS.busy = false; paintBS();
}
async function viewBranch() {
  await loadLocs(); BS.from = BS.from || monthStart(); BS.to = BS.to || today();
  shell(T('bs_title'), `<p class="muted">${esc(T('bs_intro'))}</p>${filterBar(BS, `<input id="rc_c" placeholder="${esc(T('cat'))}" value="${esc(BS.cat)}" autocomplete="off">`)}
    <div class="row wrap"><input id="rc_q" placeholder="${esc(T('find'))}" value="${esc(BS.q)}" autocomplete="off"><button type="button" class="tog ${BS.only ? 'on' : ''}" data-act="rc_only" aria-pressed="${BS.only}">${esc(T('only'))}</button></div>
    <div id="rc_res"></div>`, true);
  if (BS.data) paintBS(); else loadBS();
}
function csvBS() {
  const d = BS.data; if (!d) return;
  const cost = d.cost_visible === true;
  const head = [T('place'), T('item'), T('unit'), ...BS_COLS.map((c) => T(c[0])), ...(cost ? BS_COST.map((c) => T(c[0])) : []), T('flags')];
  const rows = bsRows().map((r) => [nm(r, 'location_bn', 'location_en'), r.item_code + ' ' + nm(r, 'item_bn', 'item_en'), r.unit || '', ...BS_COLS.map((c) => r[c[1]]), ...(cost ? BS_COST.map((c) => r[c[1]]) : []), (r.flags || []).map((f) => TL('f_', f)).join('; ')]);
  return exportCsv('factory_branch', head, rows, { from: BS.from, to: BS.to, loc: BS.loc, category: BS.cat });
}

/* ======================= 3. net profit ======================= */
const NP = { from: null, to: null, loc: '', cat: '', tab: 'branch', q: '', data: null, busy: false, err: null };
const NP_BR = [['p_net', 'net_sales'], ['p_unc', 'uncosted_sales'], ['p_cogs', 'cogs'], ['p_gp', 'gross_profit'], ['p_gm', 'gross_margin_pct'], ['p_waste', 'wastage_cost'], ['p_fee', 'card_fees'], ['p_var', 'variable_expenses'],
  ['p_cm', 'contribution_margin'], ['p_cmp', 'contribution_pct'], ['p_oth', 'other_expenses'], ['p_sal', 'salary'], ['p_fix', 'fixed_monthly'], ['p_shr', 'shared_costs'], ['p_np', 'net_profit'], ['p_npp', 'net_profit_pct']];
const NP_PR = [['p_qty', 'qty'], ['p_net', 'net_sales'], ['p_unc', 'uncosted_sales'], ['p_cogs', 'cogs'], ['p_gp', 'gross_profit'], ['p_gm', 'gross_margin_pct'], ['p_waste', 'wastage_cost'], ['p_avar', 'allocated_variable'],
  ['p_cm', 'contribution_margin'], ['p_cmp', 'contribution_pct'], ['p_aoh', 'allocated_overhead'], ['p_np', 'net_profit'], ['p_npp', 'net_profit_pct']];
const STRONG = new Set(['contribution_margin', 'net_profit']);
const PCT = new Set(['gross_margin_pct', 'contribution_pct', 'net_profit_pct']);
function npHTML() {
  if (NP.busy && !NP.data) return `<p class="muted center pad">${esc(T('loading'))}</p>`;
  if (NP.err) return `<div class="notice bad">${esc(NP.err)}</div>`;
  const d = NP.data; if (!d) return '';
  const cell = (r, k, strong) => `<td class="n"${strong || STRONG.has(k) ? ' style="font-weight:700' + (Number(r[k]) < 0 ? ';color:var(--bad,#b3261e)' : '') + '"' : colorNum(r[k])}>${esc(fm(r[k]))}${PCT.has(k) && r[k] !== undefined ? '%' : ''}</td>`;
  const inc = (d.included || []).map((k) => `<li>${esc(TL('i_', k))}</li>`).join(''), exc = (d.not_included || []).map((k) => `<li>${esc(TL('e_', k))}</li>`).join('');
  const vh = (d.variable_heads || []).length ? d.variable_heads.join(', ') : T('vh_none');
  const box = `<details class="card" open><summary><b>${esc(T('inc_h'))}</b></summary><ul>${inc}</ul><b>${esc(T('exc_h'))}</b><ul>${exc}</ul>
    <div class="muted">${esc(T('vh'))}: ${esc(vh)}</div><div class="muted">${esc(T('p_alloc'))}</div></details>`;
  let tbl;
  if (NP.tab === 'branch') {
    const rows = d.branches || [], co = d.company || {};
    tbl = `<div class="scrollx"><table class="bz" id="rc_tbl"><thead><tr>${th('place')}${NP_BR.map((c) => th(c[0], 'n')).join('')}${th('flags')}</tr></thead><tbody>${rows.map((r) => `<tr><td>${esc(nm(r, 'location_bn', 'location_en'))}</td>${NP_BR.map((c) => cell(r, c[1])).join('')}`
      + `<td>${(r.gaps || []).map((g) => chip(TL('g_', g), 'warn')).join(' ') || chip(T('g_complete'), 'ok')}</td></tr>`).join('')}</tbody>
      <tfoot><tr><td><b>${esc(T('p_company'))}</b></td>${NP_BR.map((c) => (co[c[1]] !== undefined ? cell(co, c[1], true) : '<td></td>')).join('')}<td></td></tr></tfoot></table></div>
      ${Number(co.unallocated_shared_costs) > 0 ? `<div class="notice warn">${esc(T('p_unal'))}: <b>${esc(fm(co.unallocated_shared_costs))}</b></div>` : ''}`;
  } else {
    const q = NP.q.trim().toLowerCase(), src = NP.tab === 'product' ? d.products || [] : d.product_branch || [];
    const rows = src.filter((r) => !q || (String(r.item_code) + ' ' + String(r.item_bn || '') + ' ' + String(r.item_en || '')).toLowerCase().includes(q));
    const pb = NP.tab === 'pb';
    tbl = `<div class="row wrap"><input id="rc_q" placeholder="${esc(T('find'))}" value="${esc(NP.q)}" autocomplete="off"></div><div class="scrollx"><table class="bz" id="rc_tbl"><thead><tr>${pb ? th('place') : ''}${th('item')}${NP_PR.map((c) => th(c[0], 'n')).join('')}${th('flags')}</tr></thead>`
      + `<tbody>${rows.map((r) => `<tr>${pb ? `<td>${esc(nm(r, 'location_bn', 'location_en'))}</td>` : ''}<td style="text-align:left"><b>${esc(r.item_code)}</b> ${esc(nm(r, 'item_bn', 'item_en'))}</td>${NP_PR.map((c) => cell(r, c[1])).join('')}`
        + `<td>${r.cost_complete === false ? chip(TL('g_', 'uncosted_sales'), 'warn') : ''}</td></tr>`).join('')}</tbody></table></div>`;
  }
  return `${box}<div class="row wrap">${['branch', 'product', 'pb'].map((k) => `<button type="button" class="tog ${NP.tab === k ? 'on' : ''}" data-act="rc_tab" data-v="${k}" aria-pressed="${NP.tab === k}">${esc(T('t_' + (k === 'pb' ? 'pb' : k)))}</button>`).join('')}</div>${tbl}`;
}
function paintNP() { const el = $('#rc_res'); if (el) el.innerHTML = npHTML(); }
async function loadNP() {
  NP.busy = true; NP.err = null; paintNP();
  try {
    if (days(NP.from, NP.to) > 370 || days(NP.from, NP.to) < 0) throw new Error('bad_period');
    const r = await sb.rpc('net_profit_report', { p_from: NP.from, p_to: NP.to, p_loc: NP.loc === '' ? null : Number(NP.loc), p_category: NP.cat || null });
    if (r && r.error) throw r.error;
    NP.data = r.data;
  } catch (e) { NP.err = errMsg(e); NP.data = null; }
  NP.busy = false; paintNP();
}
async function viewProfit() {
  await loadLocs(); NP.from = NP.from || monthStart(); NP.to = NP.to || today();
  shell(T('np_title'), `<p class="muted">${esc(T('np_intro'))}</p>${filterBar(NP, `<input id="rc_c" placeholder="${esc(T('cat'))}" value="${esc(NP.cat)}" autocomplete="off">`)}<div id="rc_res"></div>`, true);
  if (NP.data) paintNP(); else loadNP();
}
function csvNP() {
  const d = NP.data; if (!d) return;
  const br = NP.tab === 'branch', pb = NP.tab === 'pb', cols = br ? NP_BR : NP_PR;
  const src = br ? d.branches || [] : NP.tab === 'product' ? d.products || [] : d.product_branch || [];
  const head = [...(br || pb ? [T('place')] : []), ...(br ? [] : [T('item')]), ...cols.map((c) => T(c[0])), T('flags')];
  const rows = src.map((r) => [...(br || pb ? [nm(r, 'location_bn', 'location_en')] : []), ...(br ? [] : [r.item_code + ' ' + nm(r, 'item_bn', 'item_en')]), ...cols.map((c) => r[c[1]]),
    br ? (r.gaps || []).map((g) => TL('g_', g)).join('; ') : (r.cost_complete === false ? TL('g_', 'uncosted_sales') : '')]);
  return exportCsv(br ? 'net_profit_branch' : 'net_profit_product', head, rows, { from: NP.from, to: NP.to, loc: NP.loc, category: NP.cat, view: NP.tab });
}

/* ---------- handlers ---------- */
const cur = () => { const r = (location.hash.replace(/^#\/?/, '') || '').split(/[?\/]/)[0]; return r === 'branchstmt' ? 'bs' : r === 'netprofit' ? 'np' : 'sr'; };
const STATE = { sr: [SR, loadSR, paintSR, csvSR], bs: [BS, loadBS, paintBS, csvBS], np: [NP, loadNP, paintNP, csvNP] };
A.H = A.H || {};
Object.assign(A.H, {
  rc_go: () => { const [st, load] = STATE[cur()]; readBar(st); st.data = null; load(); },
  rc_csv: () => { const [st, , , csv] = STATE[cur()]; readBar(st); return csv(); },
  rc_only: (a) => { const [st, , paint] = STATE[cur()]; st.only = !st.only; a.classList.toggle('on', st.only); a.setAttribute('aria-pressed', String(st.only)); paint(); },
  rc_kind: (a) => { SR.kind = a.dataset.v || ''; paintSR(); },
  rc_tab: (a) => { NP.tab = a.dataset.v; paintNP(); },
});
// live item filter (no server call)
document.addEventListener('input', (e) => {
  const t = e.target; if (!t || t.id !== 'rc_q') return;
  const [st, , paint] = STATE[cur()]; st.q = t.value; paint();
  const q = $('#rc_q'); if (q && document.activeElement !== q) { q.focus(); try { q.setSelectionRange(q.value.length, q.value.length); } catch (er) { /* ignore */ } }
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stockrecon: viewStock, branchstmt: viewBranch, netprofit: viewProfit });
B.recon118 = { loaded: true, X, srRows, bsRows, toCSV, csvCell, cur };
})();
