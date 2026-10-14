/* Islamia BOS · Finance 2 (#/finance2, owner / accounts_manage): bank statement reconcile, year-end close, VAT report, fixed assets, budgets.
   Server: supabase/phase53.sql - bank_stmt_import, bank_recon_suggest / _candidates / _match / _match_many / _unmatch / _report / _lines,
   year_close_run (dry first) / year_close_reverse / year_close_list, acct_pnl_ex_close, vat_report, fa_asset_save (dry first) / fa_register / fa_schedule /
   fa_depr_post (dry first) / fa_asset_dispose, budget_set (dry first) / budget_list / budget_vs_actual. Switches (bank_recon_on, year_close_on, vat_on + vat_rate,
   fixed_assets_on, budgets_on) are set in #/switchboard (set_rule) - every one is OFF by default and the page says so.
   Nothing here posts to the books by itself: a statement import and a VAT report write nothing to the journal; the close and depreciation show a preview first.
   Pure helpers (CSV/JSON statement parser) are exposed as window.BOS.f2 for tests. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const BN = '০১২৩৪৫৬৭৮৯';
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => String(BN.indexOf(d))).replace(/,/g, '').trim();
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };

/* ---------- pure: statement text -> rows ---------- */
function splitCsv(text) {
  const first = String(text).split(/\r?\n/).find((l) => l.trim()) || '';
  const delim = (first.match(/\t/g) || []).length ? '\t' : (first.match(/;/g) || []).length > (first.match(/,/g) || []).length ? ';' : ',';
  const rows = []; let row = [], cur = '', q = false;
  const s = String(text).replace(/^﻿/, '');
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) { if (c === '"') { if (s[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === delim) { row.push(cur); cur = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && s[i + 1] === '\n') i++; row.push(cur); cur = ''; if (row.some((x) => x.trim() !== '')) rows.push(row); row = []; }
    else cur += c;
  }
  row.push(cur); if (row.some((x) => x.trim() !== '')) rows.push(row);
  return rows;
}
function parseDate(v) {
  const s = norm(v); let m;
  if ((m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/))) return ok3(m[1], m[2], m[3]);
  if ((m = s.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/))) return ok3(m[3], m[2], m[1]);
  return null;
}
function ok3(y, mo, d) { const dt = new Date(Date.UTC(+y, +mo - 1, +d)); if (dt.getUTCFullYear() !== +y || dt.getUTCMonth() !== +mo - 1 || dt.getUTCDate() !== +d) return null; return `${y}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`; }
function parseAmt(v) {
  let s = norm(v).replace(/[৳$\s]|BDT|Tk/gi, ''); if (s === '') return null;
  let neg = false; if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1); }
  if (/(DR|D)$/i.test(s)) { neg = true; s = s.replace(/(DR|D)$/i, ''); } else if (/(CR|C)$/i.test(s)) s = s.replace(/(CR|C)$/i, '');
  if (!/^[-+]?\d+(\.\d+)?$/.test(s)) return NaN;
  const n = Number(s); return neg ? -Math.abs(n) : n;
}
/* in: text (CSV/TSV or JSON). out: { rows:[{date,amount,reference,description,balance}], errors:[{row,why}] }. Money in = positive. */
function parseStatement(text) {
  const out = { rows: [], errors: [] }; const t = String(text || '').trim();
  if (!t) return out;
  let objs = null;
  if (t[0] === '[' || t[0] === '{') {
    try { let j = JSON.parse(t); if (j && !Array.isArray(j)) j = j.rows || j.lines || []; objs = j; } catch (e) { out.errors.push({ row: 0, why: 'json' }); return out; }
  } else {
    const grid = splitCsv(t); if (!grid.length) return out;
    const head = grid[0].map((h) => norm(h).toLowerCase());
    const hasHead = !parseDate(grid[0][0]) && head.some((h) => /date|তারিখ|desc|narr|amount|debit|credit|withdraw|deposit|balance|ref/.test(h));
    const idx = (re) => head.findIndex((h) => re.test(h));
    let c = hasHead ? { date: idx(/date|তারিখ/), ref: idx(/^(ref|reference|chq|cheque|txn|transaction id|voucher)/), desc: idx(/desc|narr|particular|details|বিবরণ/), amt: idx(/^amount|টাকা/), dr: idx(/debit|withdraw|payment|out/), cr: idx(/credit|deposit|receipt|in$/), bal: idx(/balance/) } : { date: 0, desc: 1, amt: 2, ref: -1, dr: -1, cr: -1, bal: 3 };
    if (c.amt < 0 && c.dr < 0 && c.cr < 0) c.amt = hasHead ? -1 : 2;
    objs = grid.slice(hasHead ? 1 : 0).map((r) => {
      const g = (i) => (i >= 0 && i < r.length ? r[i] : '');
      let amount = null;
      if (c.amt >= 0) amount = parseAmt(g(c.amt));
      else { const d = parseAmt(g(c.dr)), k = parseAmt(g(c.cr)); amount = (k !== null && k !== 0 && !Number.isNaN(k)) ? Math.abs(k) : (d !== null && !Number.isNaN(d) ? -Math.abs(d) : (Number.isNaN(d) || Number.isNaN(k) ? NaN : null)); }
      return { date: g(c.date), amount, reference: g(c.ref), description: g(c.desc), balance: g(c.bal) };
    });
  }
  (objs || []).forEach((o, i) => {
    const n = i + 1; if (!o || typeof o !== 'object') return out.errors.push({ row: n, why: 'row' });
    const date = parseDate(o.date), amount = typeof o.amount === 'number' ? o.amount : parseAmt(o.amount);
    if (!date) return out.errors.push({ row: n, why: 'date' });
    if (amount === null || Number.isNaN(amount) || amount === 0) return out.errors.push({ row: n, why: 'amount' });
    const bal = parseAmt(o.balance);
    const r = { date, amount: Math.round(amount * 100) / 100, reference: String(o.reference ?? '').trim().slice(0, 120), description: String(o.description ?? '').trim().slice(0, 300) };
    if (bal !== null && !Number.isNaN(bal)) r.balance = bal;
    out.rows.push(r);
  });
  return out;
}
B.f2 = { parseStatement, parseDate, parseAmt };

/* ---------- texts ---------- */
const X = {
  title: L('আর্থিক হিসাব ২ (ব্যাংক, বছর শেষ, ভ্যাট, সম্পদ, বাজেট)', 'Finance 2 (bank, year-end, VAT, assets, budgets)', 'Finance 2 (bank, year-end, VAT, assets, budget)'),
  tabs: { bank: L('ব্যাংক মেলানো', 'Bank reconcile', 'Bank মেলানো'), close: L('বছর শেষের ক্লোজ', 'Year-end close', 'Year-end close'), vat: L('ভ্যাট খাতা', 'VAT ledger', 'VAT খাতা'), fa: L('স্থায়ী সম্পদ', 'Fixed assets', 'Fixed assets'), budget: L('বাজেট', 'Budgets', 'Budget') },
  noacc: L('এই পাতা শুধু মালিক বা হিসাব-পরিচালনার অনুমতিওয়ালার জন্য।', 'This page is for the owner or someone with the accounts-manage right.', 'এই page শুধু owner বা accounts manage right-ওয়ালার জন্য।'),
  off: L('এই সুবিধা বন্ধ আছে। মালিক #/switchboard থেকে চালু করলে ব্যবহার করা যাবে।', 'This feature is switched off. The owner can turn it on in #/switchboard.', 'এই feature বন্ধ। Owner #/switchboard থেকে চালু করুন।'),
  needdata: L('হিসাব শুরুর ডেট না থাকলে এটি চলবে না — আগে Accounts পাতায় ডেট দিন।', 'Needs the accounting start date first (Accounts page).', 'Accounts page-এ আগে start date দিন।'),
  dry: L('আগে যাচাই (কিছু লেখা হয় না)', 'Check first (writes nothing)', 'আগে check (কিছু লেখা হয় না)'), go: L('নিশ্চিত — সেভ', 'Confirm - save', 'Confirm — save'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), show: L('দেখান', 'Show', 'Show'),
  why: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'), note: L('নোট', 'Note', 'Note'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), place: L('জায়গা', 'Place', 'Place'), all: L('সব জায়গা', 'All places', 'সব place'),
  /* bank */
  b_acc: L('ব্যাংক/ক্যাশ হিসাব', 'Bank / cash account', 'Bank/cash account'), b_paste: L('স্টেটমেন্ট পেস্ট করুন (CSV বা JSON)। টাকা ঢুকলে +, বের হলে −। কলাম: ডেট, টাকা, রেফারেন্স, বিবরণ।', 'Paste the statement (CSV or JSON). Money in is +, out is −. Columns: date, amount, reference, description.', 'Statement paste করুন (CSV/JSON)। ঢুকলে +, বের হলে −। Column: date, amount, reference, description।'),
  b_check: L('যাচাই করুন', 'Check', 'Check'), b_import: L('ইমপোর্ট (নিশ্চিত)', 'Import (confirm)', 'Import (confirm)'), b_new: L('নতুন', 'New', 'নতুন'), b_dup: L('আগেই আছে', 'Already there', 'আগেই আছে'), b_bad: L('ভুল লাইন', 'Bad rows', 'ভুল line'),
  b_sugg: L('মিল প্রস্তাব দেখুন', 'Show match suggestions', 'Match suggestion দেখুন'), b_accept: L('বাছাইকৃত প্রস্তাব মানুন', 'Accept the ticked suggestions', 'Tick করা suggestion মানুন'), b_conf: L('নিশ্চিত মিল', 'Confident', 'Confident'), b_amb: L('একাধিক সম্ভাবনা', 'Several candidates', 'একাধিক candidate'),
  b_unm: L('স্টেটমেন্টে আছে, খাতায় মেলেনি', 'On the statement, not matched in the books', 'Statement-এ আছে, books-এ মেলেনি'), b_book: L('খাতায় আছে, স্টেটমেন্টে নেই', 'In the books, not on the statement', 'Books-এ আছে, statement-এ নেই'),
  b_find: L('মিল খুঁজুন', 'Find a match', 'Match খুঁজুন'), b_match: L('মেলান', 'Match', 'মেলান'), b_unmatch: L('মিল ভাঙুন', 'Unmatch', 'Unmatch'), b_cand: L('সম্ভাব্য খাতার লাইন (একই টাকা)', 'Possible book lines (same amount)', 'সম্ভাব্য book line (একই টাকা)'),
  b_nocand: L('একই টাকার কোনো লাইন নেই। স্টেটমেন্টের জন্য আলাদা জার্নাল Accounts পাতায় লিখুন।', 'No book line with this exact amount. Post the journal on the Accounts page first.', 'একই টাকার line নেই। আগে Accounts page-এ journal লিখুন।'),
  b_sum: L('সারসংক্ষেপ', 'Summary', 'Summary'), b_stt: L('স্টেটমেন্ট টোটাল', 'Statement total', 'Statement total'), b_bkt: L('খাতা টোটাল', 'Books total', 'Books total'), b_diff: L('পার্থক্য', 'Difference', 'Difference'), b_matched: L('মিলেছে', 'Matched', 'Matched'),
  b_nopost: L('কিছু নিজে পোস্ট হয় না — মেলানো শুধু চিহ্ন।', 'Nothing is posted by itself - matching only marks lines.', 'কিছু auto post হয় না — match শুধু চিহ্ন।'),
  /* close */
  c_help: L('আগে হিসাব-বন্ধের ডেট (Rules) বছর শেষ পর্যন্ত দিন। প্রিভিউ দেখে নিশ্চিত করুন। ভুল হলে উল্টানো যায়।', 'First set the books-closed date (Rules) to the year end. Preview, then confirm. It can be reversed.', 'আগে books-closed date বছর শেষ পর্যন্ত দিন। Preview দেখে confirm। ভুল হলে reverse করা যায়।'),
  c_prev: L('প্রিভিউ', 'Preview', 'Preview'), c_run: L('বছর বন্ধ করুন', 'Close the year', 'Year close করুন'), c_inc: L('টোটাল আয়', 'Total income', 'Total income'), c_exp: L('টোটাল খরচ', 'Total expense', 'Total expense'), c_net: L('নিট মুনাফা (জমা মুনাফায় যাবে)', 'Net profit (goes to retained earnings)', 'Net profit (retained earnings-এ যাবে)'),
  c_past: L('আগের ক্লোজ', 'Earlier closes', 'আগের close'), c_rev: L('উল্টান (বছর আবার খুলুন)', 'Reverse (reopen the year)', 'Reverse (year reopen)'), c_closed: L('বন্ধ', 'Closed', 'Closed'), c_reop: L('আবার খোলা', 'Reopened', 'Reopened'), c_owner: L('শুধু মালিক ক্লোজ করতে পারেন।', 'Only the owner can close a year.', 'শুধু owner close করতে পারেন।'),
  c_lockto: L('হিসাব-বন্ধের তারিখ এখন', 'Books closed until', 'Books closed until'), c_lines: L('ক্লোজিং লাইন', 'Closing lines', 'Closing line'),
  /* vat */
  v_off: L('ভ্যাট বন্ধ আছে (সুইচবোর্ডে vat_on)। পরামর্শদাতার সাথে কথা বলে মালিক চালু করবেন।', 'VAT is OFF (vat_on in the switchboard). The owner turns it on after talking to the adviser.', 'VAT বন্ধ (vat_on)। Adviser-এর সাথে কথা বলে owner on করবেন।'),
  v_need: L('ভ্যাটের হার দেওয়া হয়নি। হার মালিককে দিতে হবে (vat_rate) — অ্যাপ নিজে কোনো হার ধরে না।', 'No VAT rate is set. The owner must enter it (vat_rate) - the app never assumes one.', 'VAT rate দেওয়া নেই। Owner দেবেন (vat_rate) — app নিজে ধরে না।'),
  v_out: L('আউটপুট ভ্যাট (সেল)', 'Output VAT (sales)', 'Output VAT (sales)'), v_in: L('ইনপুট ভ্যাট (কেনা)', 'Input VAT (purchases)', 'Input VAT (purchases)'), v_net: L('নিট ভ্যাট দেয় (− হলে ফেরতযোগ্য)', 'Net VAT payable (− = refundable)', 'Net VAT দেয় (− = ফেরতযোগ্য)'),
  v_tax: L('করযোগ্য মূল্য', 'Taxable value', 'Taxable value'), v_und: L('ভ্যাট-অনির্ধারিত আইটেমের মূল্য (ধরা হয়নি)', 'Value of items with undecided VAT (not counted)', 'VAT অনির্ধারিত item (ধরা হয়নি)'), v_rate: L('হার', 'Rate', 'Rate'), v_incl: L('প্রাইসে ভ্যাট ধরা আছে', 'Prices include VAT', 'Price-এ VAT ধরা'),
  v_month: L('মাস ধরে', 'By month', 'মাস ধরে'), v_only: L('শুধু রিপোর্ট — খাতায় কিছু ওঠে না।', 'Report only - nothing is posted.', 'শুধু report — books-এ কিছু ওঠে না।'),
  /* fa */
  f_add: L('নতুন সম্পদ', 'New asset', 'নতুন asset'), f_code: L('কোড', 'Code', 'Code'), f_name: L('নাম', 'Name', 'Name'), f_cost: L('কেনা কস্ট', 'Cost', 'Cost'), f_salv: L('অবশিষ্ট মূল্য', 'Salvage value', 'Salvage value'), f_life: L('আয়ু (মাস)', 'Life (months)', 'Life (মাস)'),
  f_acq: L('কেনার তারিখ', 'Acquired on', 'Acquired on'), f_start: L('ডেপ্রিসিয়েশন শুরুর মাস', 'Depreciation starts', 'Depreciation start'), f_method: L('পদ্ধতি: সরল রেখা (প্রতি মাসে সমান)', 'Method: straight line (equal each month)', 'Method: straight line (প্রতি মাসে সমান)'),
  f_reg: L('সম্পদের তালিকা', 'Asset register', 'Asset register'), f_acc: L('জমা ডেপ্রিসিয়েশন', 'Accumulated', 'Accumulated'), f_bv: L('বর্তমান মূল্য', 'Book value', 'Book value'), f_sched: L('সূচি', 'Schedule', 'Schedule'), f_disp: L('বাদ দিন', 'Dispose', 'Dispose'),
  f_post: L('মাসিক ডেপ্রিসিয়েশন পোস্ট', 'Post monthly depreciation', 'Monthly depreciation post'), f_thru: L('এই মাস পর্যন্ত (সম্পূর্ণ হওয়া মাস)', 'Through this month (a completed month)', 'এই মাস পর্যন্ত (completed)'), f_prev: L('প্রিভিউ', 'Preview', 'Preview'),
  f_nopost: L('সম্পদ কেনার এন্ট্রি এখানে হয় না — কেনা/শুরুর জেরে আগেই খতিয়ানে থাকে।', 'Buying the asset is not posted here - it is already in the books (purchase / opening balance).', 'Asset কেনার entry এখানে হয় না — purchase/opening-এ আগেই আছে।'),
  f_rows: L('পোস্ট হবে', 'Will post', 'Post হবে'), f_skip: L('বাদ', 'Skipped', 'Skipped'), f_dispnote: L('বাদ দেওয়ার কারণ', 'Reason for disposal', 'Disposal-এর কারণ'),
  /* budget */
  u_acct: L('হিসাব (আয়/খরচ)', 'Account (income / expense)', 'Account (income/expense)'), u_month: L('মাস', 'Month', 'মাস'), u_amt: L('বাজেট টাকা', 'Budget amount', 'Budget amount'), u_months: L('কতগুলো মাসে একই টাকা', 'Same amount for how many months', 'কত মাস একই টাকা'),
  u_set: L('বাজেট দিন', 'Set budget', 'Budget দিন'), u_rep: L('বাজেট বনাম আসল', 'Budget vs actual', 'Budget vs actual'), u_bud: L('বাজেট', 'Budget', 'Budget'), u_act: L('আসল', 'Actual', 'Actual'), u_var: L('পার্থক্য (+ ভালো)', 'Variance (+ = good)', 'Variance (+ = ভালো)'), u_pct: L('ব্যবহার %', 'Used %', 'Used %'),
  u_new: L('নতুন', 'New', 'নতুন'), u_chg: L('বদল', 'Changed', 'বদল'), u_same: L('একই', 'Unchanged', 'একই'), u_pro: L('লাভ', 'Profit', 'Profit'),
};
const T = (k) => lab(X[k]);
const TT = (k) => lab(X.tabs[k]);
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), 'switch_off': X.off, data_needed: X.needdata, bad_account: L('হিসাব ঠিক নয় (ব্যাংক/ক্যাশ বা আয়/খরচের হিসাব লাগবে)', 'Account not valid (a bank / cash or income / expense account is needed)', 'Account ঠিক নয়'),
  invalid_rows: L('কিছু লাইন ভুল — আগে ঠিক করুন', 'Some rows are invalid - fix them first', 'কিছু line ভুল'), no_rows: L('কোনো লাইন নেই', 'No rows', 'কোনো line নেই'), too_many_rows: L('একবারে অনেক লাইন', 'Too many rows at once', 'একবারে অনেক line'),
  amount_mismatch: L('টাকা হুবহু এক নয়', 'The amounts are not exactly equal', 'টাকা exact সমান নয়'), wrong_account: L('অন্য হিসাবের লাইন', 'That line belongs to another account', 'অন্য account-এর line'), line_already_matched: L('স্টেটমেন্ট লাইন আগেই মেলানো', 'Statement line already matched', 'Statement line আগেই matched'),
  journal_already_matched: L('খাতার লাইন আগেই মেলানো', 'Book line already matched', 'Book line আগেই matched'), note_required: X.why, not_matched: L('এটি মেলানো নেই', 'It is not matched', 'এটি matched নয়'), entry_not_posted: L('এন্ট্রি ভয়েড', 'That entry is void', 'Entry void'),
  period_not_locked: L('আগে হিসাব-বন্ধের ডেট বছর শেষ পর্যন্ত দিন (Rules)', 'Set the books-closed date to the year end first (Rules)', 'আগে books-closed date বছর শেষ পর্যন্ত দিন'), already_closed: L('এই সময় আগেই বন্ধ', 'This period is already closed', 'এই সময় আগেই closed'),
  nothing_to_close: L('বন্ধ করার মতো আয়/খরচ নেই', 'No income / expense to close', 'Close করার মতো কিছু নেই'), before_start: L('হিসাব শুরুর আগের ডেট', 'Before the accounting start date', 'Start date-এর আগে'), bad_range: L('ডেটের সীমা ঠিক নয় (শেষ হয়নি এমন বছর নেওয়া যায় না)', 'Date range not valid (a year that has not ended cannot be closed)', 'Date range ঠিক নয়'),
  already_reopened: L('আগেই উল্টানো হয়েছে', 'Already reversed', 'আগেই reverse'), later_close_exists: L('পরের বছর বন্ধ আছে — আগে সেটি উল্টান', 'A later year is closed - reverse that first', 'পরের বছর closed — আগে সেটি reverse'),
  no_retained_mapping: L('জমা মুনাফার ম্যাপিং নেই', 'No retained-earnings mapping', 'Retained mapping নেই'), month_not_complete: L('মাস এখনো শেষ হয়নি', 'The month is not complete yet', 'মাস শেষ হয়নি'), depreciation_already_posted: L('ডেপ্রিসিয়েশন পোস্ট হয়ে গেছে — কস্ট/আয়ু বদলানো যায় না', 'Depreciation is posted - cost / life cannot change', 'Depreciation post হয়েছে'),
  code_taken: L('এই কোড আগেই আছে', 'That code is taken', 'Code আছে'), bad_code: L('কোড ঠিক নয়', 'Code not valid', 'Code ঠিক নয়'), bad_salvage: L('অবশিষ্ট মূল্য কস্টের চেয়ে কম হতে হবে', 'Salvage must be below the cost', 'Salvage < cost'), bad_life: L('আয়ু ১–১২০০ মাস', 'Life must be 1-1200 months', 'Life 1–1200'),
  bad_amount: L('টাকা ঠিক নয়', 'Amount not valid', 'Amount ঠিক নয়'), bad_date: L('ডেট ঠিক নয়', 'Date not valid', 'Date ঠিক নয়'), bad_depr_start: L('ডেপ্রিসিয়েশন কেনার মাসের আগে শুরু হয় না', 'Depreciation cannot start before the acquisition month', 'Depreciation start আগে হয় না'),
  bad_location: L('জায়গা ঠিক নয়', 'Place not valid', 'Place ঠিক নয়'), no_mapping: L('ডেপ্রিসিয়েশনের ম্যাপিং নেই', 'Depreciation mapping missing', 'Mapping নেই'), period_closed: L('এই মাস বন্ধ — মালিকের অনুমতি লাগবে', 'Period closed - owner needed', 'Period closed'),
  bad_month: L('মাস ঠিক নয়', 'Month not valid', 'Month ঠিক নয়'), asset_disposed: L('সম্পদ আগেই বাদ', 'Asset already disposed', 'Asset disposed'),
};
const eText = (e) => { const m = String((e && e.message) || e || ''); const k = Object.keys(ERR).find((x) => m.includes(x)); return k ? lab(ERR[k]) : (m || 'error'); };
const WHY = { date: L('ডেট', 'date', 'date'), amount: L('টাকা', 'amount', 'amount'), json: L('JSON পড়া যায়নি', 'JSON not readable', 'JSON read হয়নি'), row: L('লাইন', 'row', 'row') };

/* ---------- state ---------- */
const D = { tab: 'bank', locs: [], accts: [], pl: [], sw: {}, bank: { acct: '', text: '', parsed: null, dry: null, rep: null, lines: null, sugg: null, client: rid() }, close: { from: '', to: '', prev: null, list: null },
  vat: { from: '', to: '', rep: null }, fa: { reg: null, form: { code: '', name: '', cost: '', salv: '0', life: '', acq: '', start: '', loc: '' }, formDry: null, post: null, thru: '' },
  bud: { from: '', to: '', rep: null, acct: '', month: '', amt: '', n: 1, dry: null, client: rid() }, ctx: null };
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };
const mstart = (d) => d.slice(0, 8) + '01';
const addMonths = (d, n) => { const [y, m] = d.split('-').map(Number); const t = new Date(Date.UTC(y, m - 1 + n, 1)); return t.toISOString().slice(0, 10); };
const locName = (id) => { const l = D.locs.find((x) => x.id === id); return l ? (S.lang === 'en' ? (l.name_en || l.name_bn) : (l.name_bn || l.name_en)) : (id == null ? '' : String(id)); };
const an = (a) => (S.lang === 'en' ? (a.name_en || a.name_bn) : (a.name_bn || a.name_en)) || '';
const chip = (t, c) => `<span class="chip ${c || ''}">${esc(t)}</span>`;
const sw = (key) => D.sw[key] === true;
const offNote = (key) => (sw(key) ? '' : `<div class="notice warn" data-f2="off">${esc(T('off'))}</div>`);
const tbl = (head, body) => `<div class="f2-scroll"><table class="f2-t"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
const th = (...c) => c.map((x) => `<th>${esc(x)}</th>`).join('');
const css = document.createElement('style'); css.id = 'f2css';
css.textContent = '.f2-scroll{overflow-x:auto}.f2-t{width:100%;border-collapse:collapse;font-size:.82rem}.f2-t th,.f2-t td{padding:6px 4px;border-bottom:1px solid var(--hair);text-align:left;vertical-align:top}.f2-t td.n,.f2-t th.n{text-align:right;font-variant-numeric:lining-nums tabular-nums}.f2-good{color:var(--ok,#1a7f37)}.f2-bad{color:var(--bad,#c62828)}.f2 textarea{width:100%;min-height:96px;font-size:.85rem}.f2 .row.wrap>*{min-width:0}.f2 input,.f2 select{max-width:100%}.f2-pre{white-space:pre-wrap;font-size:.8rem}';
document.head.appendChild(css);
const lbl = (k, inner) => `<label class="stack">${esc(T(k))}${inner}</label>`;

/* ---------- loading ---------- */
async function loadBase() {
  if (B.loadStatic) await B.loadStatic();
  D.locs = (B.liveLocs && B.ENV ? B.liveLocs(B.ENV.locs) : (B.ENV && B.ENV.locs) || []);
  const [acc, rules] = await Promise.all([sb.from('coa_accounts').select('id,code,name_bn,name_en,type,is_group,active,parent_id').order('code'), sb.from('rules').select('key,value,default_value').in('key', ['bank_recon_on', 'year_close_on', 'fixed_assets_on', 'budgets_on', 'vat_on', 'vat_rate', 'period_closed_until'])]);
  D.accts = (acc.data || []).filter((a) => a.active !== false);
  const sv = {}; (rules.data || []).forEach((r) => { const v = r.value != null ? r.value : r.default_value; sv[r.key] = v; });
  D.sw = { bank_recon_on: sv.bank_recon_on === true, year_close_on: sv.year_close_on === true, fixed_assets_on: sv.fixed_assets_on === true, budgets_on: sv.budgets_on === true, vat_on: sv.vat_on === true, vat_rate: sv.vat_rate, lock: sv.period_closed_until };
  const y = Number(today().slice(0, 4)); const t0 = today();
  D.close.from = D.close.from || `${y - 1}-01-01`; D.close.to = D.close.to || `${y - 1}-12-31`;
  D.vat.from = D.vat.from || mstart(t0); D.vat.to = D.vat.to || t0;
  D.bud.from = D.bud.from || mstart(t0); D.bud.to = D.bud.to || t0; D.bud.month = D.bud.month || mstart(t0);
  D.fa.form.acq = D.fa.form.acq || t0; D.fa.form.start = D.fa.form.start || mstart(t0);
  D.fa.thru = D.fa.thru || addMonths(mstart(t0), -1);
}
const bankAccts = () => D.accts.filter((a) => a.type === 'asset' && !a.is_group && /^11\d\d$/.test(a.code));
const plAccts = () => D.accts.filter((a) => (a.type === 'income' || a.type === 'expense') && !a.is_group);

/* ---------- page ---------- */
const tabBar = () => `<label class="stack">${esc(lab(L('বিভাগ', 'Section', 'Section')))}<select id="f2_tab">${Object.keys(X.tabs).map((k) => `<option value="${k}" ${D.tab === k ? 'selected' : ''}>${esc(TT(k))}</option>`).join('')}</select></label>`;
async function draw() {
  const el = $('#f2_body'); if (!el) return;
  try {
    let h = '';
    if (D.tab === 'bank') h = await drawBank(); else if (D.tab === 'close') h = await drawClose(); else if (D.tab === 'vat') h = await drawVat(); else if (D.tab === 'fa') h = await drawFa(); else h = await drawBud();
    el.innerHTML = h;
  } catch (e) { el.innerHTML = B.ui.state('error', eText(e), true); }
}

/* ---------- #1 bank ---------- */
async function drawBank() {
  const b = D.bank, accts = bankAccts(); if (!b.acct && accts[0]) b.acct = String(accts[0].id);
  let h = offNote('bank_recon_on') + `<div class="card stack"><div class="muted">${esc(T('b_nopost'))}</div>
    ${lbl('b_acc', `<select id="f2_bacct">${accts.map((a) => `<option value="${a.id}" ${String(a.id) === b.acct ? 'selected' : ''}>${esc(a.code)} · ${esc(an(a))}</option>`).join('')}</select>`)}
    <label class="stack">${esc(T('b_paste'))}<textarea id="f2_btext" spellcheck="false">${esc(b.text)}</textarea></label>
    <div class="row wrap"><button type="button" class="btn" data-act="f2_bcheck">${esc(T('b_check'))}</button>${b.dry && b.dry.new > 0 ? `<button type="button" class="btn primary" data-act="f2_bimport">${esc(T('b_import'))} (${b.dry.new})</button>` : ''}</div>`;
  if (b.parsed && b.parsed.errors.length) h += `<div class="notice bad">${esc(T('b_bad'))}: ${b.parsed.errors.slice(0, 8).map((e) => `#${e.row} ${esc(lab(WHY[e.why] || WHY.row))}`).join(' · ')}</div>`;
  if (b.dry) h += `<div class="row wrap" data-f2="drysum">${chip(T('b_new') + ': ' + b.dry.new, 'ok')}${chip(T('b_dup') + ': ' + b.dry.duplicate)}${b.dry.invalid ? chip(T('b_bad') + ': ' + b.dry.invalid, 'bad') : ''}<span>+${esc(fm(b.dry.sum_in))} / ${esc(fm(b.dry.sum_out))}</span></div>`;
  h += '</div>';
  if (b.acct) {
    const [rep, lines] = await Promise.all([rpc('bank_recon_report', { p_account: Number(b.acct), p_from: null, p_to: null }), rpc('bank_recon_lines', { p_account: Number(b.acct), p_status: 'matched', p_limit: 100 })]);
    b.rep = rep; b.lines = lines;
    h += `<div class="card stack"><b>${esc(T('b_sum'))}</b><div class="row wrap">${chip(T('b_matched') + ': ' + rep.matched_count, 'ok')}${chip(T('b_unm') + ': ' + rep.statement_unmatched_count, rep.statement_unmatched_count ? 'warn' : '')}${chip(T('b_book') + ': ' + rep.book_unmatched_count, rep.book_unmatched_count ? 'warn' : '')}</div>
      <div class="muted">${esc(T('b_stt'))}: ${esc(fm(rep.statement_total))} · ${esc(T('b_bkt'))}: ${esc(fm(rep.book_total))} · ${esc(T('b_diff'))}: ${esc(fm(rep.difference))}</div>
      <button type="button" class="btn" data-act="f2_bsugg">${esc(T('b_sugg'))}</button><div id="f2_sugg">${suggHtml()}</div></div>`;
    h += `<div class="card stack"><b>${esc(T('b_unm'))}</b>${rep.statement_unmatched.length ? tbl(th('', '', '') , rep.statement_unmatched.map((r) => `<tr><td>${esc(r.date)}</td><td>${esc(r.reference || r.description || '')}</td><td class="n">${esc(fm(r.amount))}</td><td><button type="button" class="mini" data-act="f2_bfind" data-id="${r.id}">${esc(T('b_find'))}</button></td></tr>`).join('')) : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
    h += `<div class="card stack"><b>${esc(T('b_book'))}</b>${rep.book_unmatched.length ? tbl('', rep.book_unmatched.map((r) => `<tr><td>${esc(r.date)}</td><td>${esc(r.memo || '')}</td><td class="n">${esc(fm(r.amount))}</td></tr>`).join('')) : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
    h += `<div class="card stack"><b>${esc(T('b_matched'))}</b>${lines.length ? tbl('', lines.map((r) => `<tr><td>${esc(r.date)}</td><td>${esc(r.reference || r.description || '')}</td><td class="n">${esc(fm(r.amount))}</td><td><button type="button" class="mini" data-act="f2_bunm" data-id="${r.id}">${esc(T('b_unmatch'))}</button></td></tr>`).join('')) : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
  }
  return h;
}
function suggHtml() {
  const s = D.bank.sugg; if (!s) return '';
  if (!s.suggestions.length) return `<p class="muted">${esc(T('none'))}</p>`;
  return tbl('', s.suggestions.map((x, i) => `<tr><td><input type="checkbox" data-f2-sg="${i}" ${x.confident ? 'checked' : ''} aria-label="accept"></td><td>${esc(x.line_date)} ${esc(x.reference || '')}<br><span class="muted">→ ${esc(x.entry_date)} ${esc(x.memo || '')}</span></td><td class="n">${esc(fm(x.amount))}</td><td>${chip(x.confident ? T('b_conf') : T('b_amb') + ' ×' + x.candidates, x.confident ? 'ok' : 'warn')}</td></tr>`).join(''))
    + `<button type="button" class="btn primary" data-act="f2_baccept">${esc(T('b_accept'))}</button>`;
}
Object.assign(H, {
  f2_bcheck: async () => {
    const b = D.bank; b.text = $('#f2_btext').value; b.acct = $('#f2_bacct').value; b.parsed = parseStatement(b.text);
    try {
      if (!b.parsed.rows.length) { b.dry = null; return draw(); }
      b.dry = await rpc('bank_stmt_import', { p_account: Number(b.acct), p_rows: b.parsed.rows, p_client: null, p_dry: true });
      await draw();
    } catch (e) { toast(eText(e)); }
  },
  f2_bimport: async () => {
    const b = D.bank;
    try { const r = await rpc('bank_stmt_import', { p_account: Number(b.acct), p_rows: b.parsed.rows, p_client: b.client, p_dry: false }); b.client = rid(); b.dry = null; b.text = ''; b.parsed = null; toast(T('saved') + ' ×' + (r.imported || 0)); await draw(); } catch (e) { toast(eText(e)); }
  },
  f2_bsugg: async () => { try { D.bank.sugg = await rpc('bank_recon_suggest', { p_account: Number(D.bank.acct), p_from: null, p_to: null, p_days: 3 }); const el = $('#f2_sugg'); if (el) el.innerHTML = suggHtml(); } catch (e) { toast(eText(e)); } },
  f2_baccept: async () => {
    const s = D.bank.sugg; if (!s) return;
    const pairs = [...document.querySelectorAll('[data-f2-sg]')].filter((c) => c.checked).map((c) => s.suggestions[Number(c.dataset.f2Sg)]).map((x) => ({ line_id: x.line_id, entry_id: x.entry_id, line_no: x.line_no }));
    if (!pairs.length) return toast(T('none'));
    try {
      const d = await rpc('bank_recon_match_many', { p_pairs: pairs, p_dry: true });
      const r = await rpc('bank_recon_match_many', { p_pairs: pairs, p_dry: false });
      toast(T('b_match') + ': ' + r.ok + (r.failed ? ' / ' + T('b_bad') + ': ' + r.failed : '') + (d.failed ? '' : '')); D.bank.sugg = null; await draw();
    } catch (e) { toast(eText(e)); }
  },
  f2_bfind: async (a) => {
    try {
      const c = await rpc('bank_recon_candidates', { p_line: Number(a.dataset.id), p_days: 10 });
      openSheet(`<h2>${esc(T('b_cand'))}</h2><div class="stack f2">${c.length ? c.map((x) => `<div class="card stack"><div>${esc(x.date)} · ${esc(x.memo || '')}</div><div class="muted">${esc(x.source_type)} · ${esc(fm(x.amount))} · ${x.days_off > 0 ? '+' : ''}${x.days_off}d ${x.ref_hit ? '· ref ✓' : ''}</div><button type="button" class="btn primary" data-act="f2_bmatch" data-id="${esc(a.dataset.id)}" data-e="${x.entry_id}" data-n="${x.line_no}">${esc(T('b_match'))}</button></div>`).join('') : `<p class="muted">${esc(T('b_nocand'))}</p>`}</div>`);
    } catch (e) { toast(eText(e)); }
  },
  f2_bmatch: async (a) => {
    try { await rpc('bank_recon_match', { p_line: Number(a.dataset.id), p_entry: Number(a.dataset.e), p_line_no: Number(a.dataset.n), p_note: null }); closeSheet(); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); }
  },
  f2_bunm: async (a) => {
    const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return;
    try { await rpc('bank_recon_unmatch', { p_line: Number(a.dataset.id), p_note: n.trim() }); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); }
  },
});

/* ---------- #2 year-end close ---------- */
const PROB = { period_not_locked: 'period_not_locked', already_closed: 'already_closed', nothing_to_close: 'nothing_to_close', before_start: 'before_start', data_needed: 'data_needed', no_retained_mapping: 'no_retained_mapping' };
async function drawClose() {
  const c = D.close; let h = offNote('year_close_on');
  const list = await rpc('year_close_list'); c.list = list;
  if (!list.owner) h += `<div class="notice warn">${esc(T('c_owner'))}</div>`;
  h += `<div class="card stack"><div class="muted">${esc(T('c_help'))}</div><div class="muted">${esc(T('c_lockto'))}: <b>${esc(list.period_closed_until || '—')}</b></div>
    <div class="row wrap"><label class="stack">${esc(T('from'))}<input type="date" id="f2_cfrom" value="${esc(c.from)}"></label><label class="stack">${esc(T('to'))}<input type="date" id="f2_cto" value="${esc(c.to)}"></label></div>
    <button type="button" class="btn" data-act="f2_cprev">${esc(T('c_prev'))}</button>`;
  if (c.prev) {
    const p = c.prev;
    h += `<div data-f2="closeprev" class="stack"><div>${esc(T('c_inc'))}: <b>${esc(fm(p.income_total))}</b></div><div>${esc(T('c_exp'))}: <b>${esc(fm(p.expense_total))}</b></div><div>${esc(T('c_net'))}: <b>${esc(fm(p.net_profit))}</b></div>
      ${(p.problems || []).map((x) => `<div class="notice bad">${esc(lab(ERR[PROB[x]] || L(x, x, x)))}</div>`).join('')}
      <details data-ctl="off"><summary>${esc(T('c_lines'))} (${(p.lines || []).length})</summary>${tbl(th('', '', 'Dr', 'Cr'), (p.lines || []).map((l) => `<tr><td>${esc(l.code)}</td><td>${esc(l.name)}${l.location_id ? ' @' + esc(locName(l.location_id)) : ''}</td><td class="n">${l.debit > 0 ? esc(fm(l.debit)) : ''}</td><td class="n">${l.credit > 0 ? esc(fm(l.credit)) : ''}</td></tr>`).join(''))}</details>
      ${p.ok && list.owner && sw('year_close_on') ? `<button type="button" class="btn primary" data-act="f2_crun">${esc(T('c_run'))}</button>` : ''}</div>`;
  }
  h += '</div>';
  h += `<div class="card stack"><b>${esc(T('c_past'))}</b>${list.rows.length ? tbl('', list.rows.map((r) => `<tr><td>${esc(r.fiscal_from)} → ${esc(r.fiscal_to)}</td><td class="n">${esc(fm(r.net_profit))}</td><td>${chip(r.status === 'closed' ? T('c_closed') : T('c_reop'), r.status === 'closed' ? 'ok' : 'warn')}</td><td>${r.status === 'closed' && list.owner ? `<button type="button" class="mini" data-act="f2_crev" data-id="${r.id}">${esc(T('c_rev'))}</button>` : ''}</td></tr>`).join('')) : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
  return h;
}
Object.assign(H, {
  f2_cprev: async () => {
    const c = D.close; c.from = $('#f2_cfrom').value; c.to = $('#f2_cto').value;
    try { c.prev = await rpc('year_close_run', { p_from: c.from, p_to: c.to, p_note: null, p_client: null, p_dry: true }); await draw(); } catch (e) { toast(eText(e)); }
  },
  f2_crun: async () => {
    const c = D.close; const n = window.prompt(T('note')); if (!n || n.trim().length < 3) return;
    try { await rpc('year_close_run', { p_from: c.from, p_to: c.to, p_note: n.trim(), p_client: rid(), p_dry: false }); c.prev = null; toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); }
  },
  f2_crev: async (a) => {
    const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return;
    try { await rpc('year_close_reverse', { p_id: Number(a.dataset.id), p_note: n.trim(), p_client: rid() }); D.close.prev = null; toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); }
  },
});

/* ---------- #3 VAT ---------- */
async function drawVat() {
  const v = D.vat;
  let h = `<div class="card stack"><div class="muted">${esc(T('v_only'))}</div><div class="row wrap"><label class="stack">${esc(T('from'))}<input type="date" id="f2_vfrom" value="${esc(v.from)}"></label><label class="stack">${esc(T('to'))}<input type="date" id="f2_vto" value="${esc(v.to)}"></label></div>
    <button type="button" class="btn" data-act="f2_vshow">${esc(T('show'))}</button></div>`;
  const r = await rpc('vat_report', { p_from: v.from, p_to: v.to, p_loc: null }); v.rep = r;
  if (r.off) return h + `<div class="notice warn" data-f2="vatoff">${esc(T('v_off'))}</div>`;
  if (r.data_needed) return h + `<div class="notice warn" data-f2="vatneed">${esc(T('v_need'))}</div>`;
  const o = r.output, i = r.input;
  h += `<div class="card stack" data-f2="vatrep"><div class="muted">${esc(T('v_rate'))}: <b>${esc(String(r.rate))}%</b> · ${esc(T('v_incl'))}: <b>${r.prices_include_vat ? '✓' : '✗'}</b></div>
    <b>${esc(T('v_out'))}</b><div>${esc(T('v_tax'))}: ${esc(fm(o.taxable_sales))} · VAT: <b>${esc(fm(o.vat))}</b></div>${Number(o.undecided_amount) ? `<div class="muted">${esc(T('v_und'))}: ${esc(fm(o.undecided_amount))}</div>` : ''}
    <b>${esc(T('v_in'))}</b><div>${esc(T('v_tax'))}: ${esc(fm(i.taxable_purchases))} · VAT: <b>${esc(fm(i.vat))}</b></div>${Number(i.undecided_amount) ? `<div class="muted">${esc(T('v_und'))}: ${esc(fm(i.undecided_amount))}</div>` : ''}
    <div class="${Number(r.net_vat_payable) > 0 ? 'f2-bad' : 'f2-good'}">${esc(T('v_net'))}: <b>${esc(fm(r.net_vat_payable))}</b></div>
    ${(r.months || []).length ? `<details data-ctl="off"><summary>${esc(T('v_month'))}</summary>${tbl(th(T('u_month'), 'Out', 'In'), r.months.map((m) => `<tr><td>${esc(String(m.month).slice(0, 7))}</td><td class="n">${esc(fm(m.output_vat))}</td><td class="n">${esc(fm(m.input_vat))}</td></tr>`).join(''))}</details>` : ''}</div>`;
  return h;
}
Object.assign(H, { f2_vshow: async () => { D.vat.from = $('#f2_vfrom').value; D.vat.to = $('#f2_vto').value; await draw(); } });

/* ---------- #4 fixed assets ---------- */
async function drawFa() {
  const f = D.fa, fm_ = f.form; let h = offNote('fixed_assets_on');
  const reg = await rpc('fa_register', { p_as_of: null }); f.reg = reg;
  h += `<div class="card stack"><b>${esc(T('f_add'))}</b><div class="muted">${esc(T('f_method'))}. ${esc(T('f_nopost'))}</div>
    <div class="row wrap">${lbl('f_code', `<input id="f2_fcode" maxlength="20" value="${esc(fm_.code)}">`)}${lbl('f_name', `<input id="f2_fname" maxlength="120" value="${esc(fm_.name)}">`)}</div>
    <div class="row wrap">${lbl('f_cost', `<input id="f2_fcost" inputmode="decimal" value="${esc(fm_.cost)}">`)}${lbl('f_salv', `<input id="f2_fsalv" inputmode="decimal" value="${esc(fm_.salv)}">`)}${lbl('f_life', `<input id="f2_flife" inputmode="numeric" value="${esc(fm_.life)}">`)}</div>
    <div class="row wrap">${lbl('f_acq', `<input type="date" id="f2_facq" value="${esc(fm_.acq)}">`)}${lbl('f_start', `<input type="date" id="f2_fstart" value="${esc(fm_.start)}">`)}${lbl('place', `<select id="f2_floc"><option value="">—</option>${D.locs.map((l) => `<option value="${l.id}" ${String(l.id) === String(fm_.loc) ? 'selected' : ''}>${esc(locName(l.id))}</option>`).join('')}</select>`)}</div>
    <button type="button" class="btn" data-act="f2_fdry">${esc(T('dry'))}</button>
    ${f.formDry ? `<div data-f2="fadry">${chip(lab(L('মাসে', 'Monthly', 'মাসে')) + ': ' + fm(f.formDry.monthly), 'ok')} ${esc(String(f.formDry.depr_from))} → ${esc(String(f.formDry.depr_to))} <button type="button" class="btn primary" data-act="f2_fsave">${esc(T('go'))}</button></div>` : ''}</div>`;
  h += `<div class="card stack"><b>${esc(T('f_reg'))}</b>${reg.rows.length ? tbl(th('', T('f_cost'), T('f_acc'), T('f_bv'), ''), reg.rows.map((r) => `<tr><td>${esc(r.code)} · ${esc(r.name)}${r.status === 'disposed' ? ' ' + chip('x', 'warn') : ''}<br><span class="muted">${esc(r.life_months)}m · ${esc(String(r.depr_from).slice(0, 7))}</span></td><td class="n">${esc(fm(r.cost))}</td><td class="n">${esc(fm(r.accumulated))}</td><td class="n">${esc(fm(r.book_value))}</td>
      <td><button type="button" class="mini" data-act="f2_fsched" data-id="${esc(r.id)}">${esc(T('f_sched'))}</button>${r.status === 'active' ? ` <button type="button" class="mini" data-act="f2_fdisp" data-id="${esc(r.id)}">${esc(T('f_disp'))}</button>` : ''}</td></tr>`).join('')) : `<p class="muted">${esc(T('none'))}</p>`}</div>`;
  h += `<div class="card stack"><b>${esc(T('f_post'))}</b><label class="stack">${esc(T('f_thru'))}<input type="date" id="f2_fthru" value="${esc(f.thru)}"></label><button type="button" class="btn" data-act="f2_fpdry">${esc(T('f_prev'))}</button>`;
  if (f.post) {
    h += `<div data-f2="fpost">${chip(T('f_rows') + ': ' + f.post.count, 'ok')} <b>${esc(fm(f.post.total))}</b>${(f.post.skipped || []).length ? ' ' + chip(T('f_skip') + ': ' + f.post.skipped.length, 'warn') : ''}
      ${f.post.rows.length ? tbl('', f.post.rows.slice(0, 40).map((r) => `<tr><td>${esc(r.code)}</td><td>${esc(String(r.month).slice(0, 7))}</td><td class="n">${esc(fm(r.amount))}</td></tr>`).join('')) : ''}
      ${(f.post.skipped || []).slice(0, 10).map((s) => `<div class="muted">${esc(s.code)} ${esc(String(s.month).slice(0, 7))}: ${esc(lab(ERR[s.why] || L(s.why, s.why, s.why)))}</div>`).join('')}
      ${f.post.count > 0 ? `<button type="button" class="btn primary" data-act="f2_fpgo">${esc(T('go'))}</button>` : ''}</div>`;
  }
  return h + '</div>';
}
const faArgs = () => {
  const f = D.fa.form;
  f.code = $('#f2_fcode').value.trim(); f.name = $('#f2_fname').value.trim(); f.cost = $('#f2_fcost').value; f.salv = $('#f2_fsalv').value; f.life = $('#f2_flife').value; f.acq = $('#f2_facq').value; f.start = $('#f2_fstart').value; f.loc = $('#f2_floc').value;
  return { p_id: null, p_code: f.code, p_name: f.name, p_category: null, p_loc: f.loc === '' ? null : Number(f.loc), p_acquired: f.acq, p_cost: Number(norm(f.cost)), p_salvage: Number(norm(f.salv || '0')), p_life_months: Number(norm(f.life)), p_depr_from: mstart(f.start), p_note: null };
};
Object.assign(H, {
  f2_fdry: async () => { try { const a = faArgs(); if (!(a.p_cost > 0) || !(a.p_life_months > 0)) return toast(lab(ERR.bad_amount)); D.fa.formDry = await rpc('fa_asset_save', Object.assign(a, { p_client: null, p_dry: true })); await draw(); } catch (e) { toast(eText(e)); } },
  f2_fsave: async () => { try { const a = faArgs(); await rpc('fa_asset_save', Object.assign(a, { p_client: rid(), p_dry: false })); D.fa.formDry = null; Object.assign(D.fa.form, { code: '', name: '', cost: '', salv: '0', life: '' }); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); } },
  f2_fsched: async (a) => {
    try { const s = await rpc('fa_schedule', { p_id: a.dataset.id }); openSheet(`<h2>${esc(s.code)} · ${esc(s.name)}</h2><div class="f2">${tbl(th('#', T('u_month'), '৳', T('f_bv')), s.rows.map((r) => `<tr><td>${r.k}</td><td>${esc(String(r.month).slice(0, 7))}${r.posted ? ' ✓' : ''}</td><td class="n">${esc(fm(r.amount))}</td><td class="n">${esc(fm(r.book_value))}</td></tr>`).join(''))}</div>`); } catch (e) { toast(eText(e)); }
  },
  f2_fdisp: async (a) => {
    const n = window.prompt(T('f_dispnote')); if (!n || n.trim().length < 3) return;
    try { await rpc('fa_asset_dispose', { p_id: a.dataset.id, p_date: today(), p_note: n.trim() }); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); }
  },
  f2_fpdry: async () => { D.fa.thru = $('#f2_fthru').value; try { D.fa.post = await rpc('fa_depr_post', { p_through: D.fa.thru, p_dry: true }); await draw(); } catch (e) { toast(eText(e)); } },
  f2_fpgo: async () => { try { const r = await rpc('fa_depr_post', { p_through: D.fa.thru, p_dry: false }); D.fa.post = null; toast(T('saved') + ' ×' + r.count); await draw(); } catch (e) { toast(eText(e)); } },
});

/* ---------- #5 budgets ---------- */
async function drawBud() {
  const u = D.bud; let h = offNote('budgets_on'); const accts = plAccts(); if (!u.acct && accts[0]) u.acct = String(accts[0].id);
  h += `<div class="card stack"><b>${esc(T('u_set'))}</b>
    ${lbl('u_acct', `<select id="f2_uacct">${accts.map((a) => `<option value="${a.id}" ${String(a.id) === u.acct ? 'selected' : ''}>${esc(a.code)} · ${esc(an(a))}</option>`).join('')}</select>`)}
    <div class="row wrap">${lbl('u_month', `<input type="date" id="f2_umonth" value="${esc(u.month)}">`)}${lbl('u_amt', `<input id="f2_uamt" inputmode="decimal" value="${esc(u.amt)}">`)}${lbl('u_months', `<input id="f2_un" inputmode="numeric" value="${esc(String(u.n))}" style="max-width:5rem">`)}</div>
    <button type="button" class="btn" data-act="f2_udry">${esc(T('dry'))}</button>
    ${u.dry ? `<div data-f2="budry">${chip(T('u_new') + ': ' + u.dry.new, 'ok')} ${chip(T('u_chg') + ': ' + u.dry.changed)} ${chip(T('u_same') + ': ' + u.dry.unchanged)} <button type="button" class="btn primary" data-act="f2_usave">${esc(T('go'))}</button></div>` : ''}</div>`;
  h += `<div class="card stack"><b>${esc(T('u_rep'))}</b><div class="row wrap"><label class="stack">${esc(T('from'))}<input type="date" id="f2_ufrom" value="${esc(u.from)}"></label><label class="stack">${esc(T('to'))}<input type="date" id="f2_uto" value="${esc(u.to)}"></label></div>
    <button type="button" class="btn" data-act="f2_ushow">${esc(T('show'))}</button>`;
  const r = await rpc('budget_vs_actual', { p_from: u.from, p_to: u.to, p_loc: null, p_by_month: false }); u.rep = r;
  h += r.rows.length ? tbl(th('', T('u_bud'), T('u_act'), T('u_var'), T('u_pct')), r.rows.map((x) => `<tr><td>${esc(x.code)} · ${esc(an(x))}</td><td class="n">${esc(fm(x.budget))}</td><td class="n">${esc(fm(x.actual))}</td><td class="n ${Number(x.variance) < 0 ? 'f2-bad' : 'f2-good'}">${esc(fm(x.variance))}</td><td class="n">${x.pct_used == null ? '' : esc(String(x.pct_used))}</td></tr>`).join(''))
    + `<div class="muted">${esc(T('c_inc'))}: ${esc(fm(r.income_budget))} / ${esc(fm(r.income_actual))} · ${esc(T('c_exp'))}: ${esc(fm(r.expense_budget))} / ${esc(fm(r.expense_actual))} · ${esc(T('u_pro'))}: ${esc(fm(r.profit_budget))} / ${esc(fm(r.profit_actual))}</div>` : `<p class="muted">${esc(T('none'))}</p>`;
  return h + '</div>';
}
function budRows() {
  const u = D.bud; u.acct = $('#f2_uacct').value; u.month = $('#f2_umonth').value; u.amt = $('#f2_uamt').value; u.n = Math.max(1, Math.min(36, Number(norm($('#f2_un').value)) || 1));
  const amt = norm(u.amt); if (!/^\d+(\.\d+)?$/.test(amt) || !u.month) return null;
  return Array.from({ length: u.n }, (_, i) => ({ account_id: Number(u.acct), month: addMonths(mstart(u.month), i), amount: Number(amt) }));
}
Object.assign(H, {
  f2_udry: async () => { const rows = budRows(); if (!rows) return toast(lab(ERR.bad_amount)); try { D.bud.dry = await rpc('budget_set', { p_rows: rows, p_note: null, p_dry: true }); await draw(); } catch (e) { toast(eText(e)); } },
  f2_usave: async () => { const rows = budRows(); if (!rows) return; try { await rpc('budget_set', { p_rows: rows, p_note: null, p_dry: false }); D.bud.dry = null; toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); } },
  f2_ushow: async () => { D.bud.from = $('#f2_ufrom').value; D.bud.to = $('#f2_uto').value; await draw(); },
});

/* ---------- shell ---------- */
document.addEventListener('change', (e) => { if (e.target && e.target.id === 'f2_tab') { D.tab = e.target.value; draw(); } if (e.target && e.target.id === 'f2_bacct') { D.bank.acct = e.target.value; D.bank.sugg = null; D.bank.dry = null; draw(); } });
async function viewFinance2() {
  shell(lab(X.title), B.ui.state('loading'), true);
  try {
    await loadBase();
    const owner = !!(S.ctx && S.ctx.is_owner);
    let mgr = owner;
    if (!owner) { try { mgr = await A.hasAnyGrant(['accounts_manage']); } catch (e) { mgr = false; } }
    if (!mgr) return shell(lab(X.title), B.ui.state('error', T('noacc')), true);
    shell(lab(X.title), `<div class="stack f2">${tabBar()}<div id="f2_body">${B.ui.state('loading')}</div></div>`, true);
    await draw();
  } catch (e) { shell(lab(X.title), B.ui.state('error', eText(e), true), true); }
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { finance2: viewFinance2 });
})();
