/* Islamia BOS · Accounts (#/accounts): chart of accounts, double-entry journal, ledger, trial balance, P&L, balance sheet, cash flow,
   customer / supplier sub-ledgers, manual journal, opening balances, mappings.
   Server: supabase/phase40.sql - acct_status, acct_overview, acct_post_pending (dry run first), acct_trial_balance, acct_ledger, acct_journal_book,
   acct_income_statement, acct_balance_sheet, acct_cash_flow, acct_party_ledger, acct_reconcile, acct_journal_post, acct_journal_reverse, acct_opening,
   acct_account_save, acct_mapping_set, acct_set_start (+ set_rule for the two switches). Tables read directly (RLS): coa_accounts, acct_mappings.
   Nothing here edits a posted entry: a correction is a reversing entry. Every report can be printed and exported as CSV. Costs: "cogs missing" is
   shown, never guessed. While the start date is empty every report says "Data needed". */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return 0; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const r2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const money = (n) => '৳ ' + fm(n);
const an = (a) => (S.lang === 'en' ? (a.name_en || a.name_bn) : (a.name_bn || a.name_en)) || '';
const monthStart = () => today().slice(0, 8) + '01';

const X = {
  title: L('হিসাব ও খতিয়ান', 'Accounts & ledger', 'Accounts ও Ledger'),
  t_overview: L('সারসংক্ষেপ', 'Overview', 'Overview'), t_bs: L('ব্যালান্স শিট', 'Balance sheet', 'Balance sheet'), t_pl: L('লাভ-ক্ষতি', 'Profit & loss', 'Profit-Loss'),
  t_cf: L('ক্যাশ প্রবাহ', 'Cash flow', 'Cash flow'), t_tb: L('ট্রায়াল ব্যালান্স', 'Trial balance', 'Trial balance'), t_ledger: L('খতিয়ান (লেজার)', 'Ledger', 'Ledger'),
  t_journal: L('জার্নাল বই', 'Journal book', 'Journal book'), t_parties: L('কাস্টমার / সাপ্লায়ারের খাতা', 'Customer / supplier books', 'Customer / Supplier খাতা'),
  t_chart: L('হিসাবের তালিকা', 'Chart of accounts', 'Hisaber talika (Chart)'), t_new: L('নতুন জার্নাল', 'New journal', 'নতুন Journal'),
  t_opening: L('শুরুর জের', 'Opening balances', 'শুরুর জের (Opening)'), t_settings: L('সেটিংস ও ম্যাপিং', 'Settings & mappings', 'Settings ও Mapping'),
  loc: L('জায়গা', 'Place', 'Place'), all: L('সব জায়গা', 'All places', 'সব Place'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), asof: L('এই তারিখে', 'As of', 'As of'),
  print: L('প্রিন্ট', 'Print', 'Print'), csv: L('CSV', 'CSV', 'CSV'), show: L('দেখান', 'Show', 'Show'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  need: L('তথ্য লাগবে', 'Data needed', 'Data লাগবে'),
  needH: L('হিসাব শুরুর ডেট দেওয়া হয়নি। ডেট দিন, তারপর শুরুর জের লিখুন, তারপর অ্যাকাউন্টিং চালু করুন।', 'The accounting start date has not been set. Set it, enter the opening balances, then switch accounting on.', 'Accounting শুরুর date দেওয়া হয়নি। Date দিন, তারপর opening balance, তারপর accounting on করুন।'),
  noacc: L('এই পাতা দেখার অনুমতি নেই (হিসাব দেখা বা হিসাব পরিচালনার অনুমতি লাগবে)।', 'No permission for this page (it needs the accounts view or accounts manage permission).', 'এই page দেখার অনুমতি নেই।'),
  off: L('অ্যাকাউন্টিং বন্ধ আছে — মালিক সেটিংস থেকে চালু করলে নতুন লেনদেন খতিয়ানে উঠবে।', 'Accounting is switched off - the owner can switch it on in Settings; then new transactions are posted.', 'Accounting off আছে — owner Settings থেকে on করলে নতুন লেনদেন post হবে।'),
  start: L('শুরুর ডেট', 'Start date', 'শুরুর date'), setStart: L('শুরুর ডেট ঠিক করুন', 'Set the start date', 'শুরুর date ঠিক করুন'), save: L('সেভ', 'Save', 'Save'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  assets: L('সম্পদ', 'Assets', 'Assets'), liabs: L('দায়', 'Liabilities', 'Liabilities'), equity: L('মালিকানা', 'Equity', 'Equity'), earn: L('জমা মুনাফা (আয় − খরচ)', 'Earnings to date (income − expense)', 'Earnings (আয় − খরচ)'),
  totA: L('টোটাল সম্পদ', 'Total assets', 'Total assets'), totL: L('টোটাল দায়', 'Total liabilities', 'Total liabilities'), totE: L('টোটাল মালিকানা', 'Total equity', 'Total equity'),
  totLE: L('দায় + মালিকানা', 'Liabilities + equity', 'Liabilities + equity'),
  income: L('আয়', 'Income', 'Income'), expense: L('খরচ', 'Expenses', 'Expenses'), totI: L('টোটাল আয়', 'Total income', 'Total income'), totX: L('টোটাল খরচ', 'Total expenses', 'Total expenses'),
  gross: L('মোট লাভ (আয় − বিক্রীত পণ্যের কস্ট)', 'Gross profit (income − cost of goods)', 'Gross profit'), net: L('নিট লাভ / ক্ষতি', 'Net profit / loss', 'Net profit / loss'),
  cogs: L('বিক্রীত পণ্যের কস্ট', 'Cost of goods sold', 'COGS'), month: L('এই মাস', 'This month', 'এই মাস'),
  unbal: L('ব্যালান্স মিলছে না! সম্পদ ≠ দায় + মালিকানা। পার্থক্য', 'The balance sheet does not balance! Assets ≠ liabilities + equity. Difference', 'Balance মিলছে না! পার্থক্য'),
  bal: L('ব্যালান্স মিলেছে ✓', 'Balanced ✓', 'Balance মিলেছে ✓'),
  cogsM: L('টি সেল/লেনদেনের কস্ট জানা নেই — মুনাফা সেগুলোর কস্ট ছাড়া দেখানো হচ্ছে (আন্দাজ করা হয়নি)।', 'sale(s)/movement(s) have no known cost - profit is shown without their cost (nothing is guessed).', 'টি sale-এর cost জানা নেই — profit সেগুলোর cost ছাড়া (আন্দাজ নয়)।'),
  postNow: L('এখন পোস্ট করুন', 'Post now', 'এখন Post করুন'), dryTitle: L('পোস্টের আগে পরীক্ষা (কিছু লেখা হয়নি)', 'Check before posting (nothing written yet)', 'Post-এর আগে check (কিছু লেখা হয়নি)'),
  willPost: L('নতুন এন্ট্রি', 'New entries', 'নতুন entry'), willRev: L('উল্টো এন্ট্রি (ভয়েড হওয়া)', 'Reversing entries (voided documents)', 'উল্টো entry (void)'),
  locked: L('বন্ধ মাসের কারণে বাদ', 'Skipped: closed period', 'বন্ধ মাসের কারণে বাদ'), waitingCost: L('কস্ট জানা নেই বলে অপেক্ষায়', 'Waiting: cost unknown', 'Cost জানা নেই বলে অপেক্ষায়'),
  errs: L('সমস্যা হয়েছে', 'Problems', 'সমস্যা'), preview: L('কী লেখা হবে (প্রথম কয়েকটি)', 'What would be written (first ones)', 'কী লেখা হবে (প্রথম কয়েকটি)'),
  trialNet: L('মোট প্রভাব (ট্রায়াল হিসাব)', 'Net effect (trial calculation)', 'মোট প্রভাব (trial)'), confirmPost: L('হ্যাঁ, পোস্ট করুন', 'Yes, post', 'হ্যাঁ, Post করুন'),
  nothing: L('পোস্ট করার মতো নতুন কিছু নেই।', 'Nothing new to post.', 'Post করার মতো নতুন কিছু নেই।'),
  posted: L('পোস্ট হয়েছে', 'Posted', 'Post হয়েছে'), more: L('আরও আছে — আবার চাপুন', 'There is more - press again', 'আরও আছে — আবার চাপুন'),
  code: L('কোড', 'Code', 'Code'), account: L('হিসাব', 'Account', 'Account'), dr: L('ডেবিট', 'Debit', 'Debit'), cr: L('ক্রেডিট', 'Credit', 'Credit'), bal2: L('জের', 'Balance', 'Balance'),
  opening: L('শুরুর জের', 'Opening', 'Opening'), closing: L('শেষ জের', 'Closing', 'Closing'), period: L('এই সময়ে', 'In the period', 'এই সময়ে'),
  date: L('ডেট', 'Date', 'Date'), memo: L('বিবরণ', 'Memo', 'Memo'), source: L('উৎস', 'Source', 'Source'),
  totals: L('মোট', 'Totals', 'Totals'), diff: L('পার্থক্য', 'Difference', 'Difference'),
  pickAcc: L('হিসাব বাছুন', 'Choose an account', 'Account বাছুন'), more2: L('আরও দেখান', 'Show more', 'আরও দেখান'),
  reverse: L('উল্টো এন্ট্রি দিন', 'Post a reversing entry', 'উল্টো entry দিন'), why: L('কারণ লিখুন (৩ অক্ষর বা বেশি)', 'Write the reason (3+ characters)', 'কারণ লিখুন'),
  reversed: L('উল্টো এন্ট্রি হয়েছে', 'Reversed', 'উল্টো entry হয়েছে'), isRev: L('উল্টো', 'reversal', 'reversal'), isVoid: L('ভয়েড', 'void', 'void'),
  // chart
  add: L('নতুন হিসাব যোগ', 'Add an account', 'নতুন account যোগ'), ccode: L('কোড (বদলানো যায় না)', 'Code (cannot change later)', 'Code (পরে বদলায় না)'), nbn: L('বাংলা নাম', 'Name (Bangla)', 'বাংলা নাম'),
  nen: L('ইংরেজি নাম', 'Name (English)', 'English নাম'), ctype: L('ধরন', 'Type', 'Type'), parent: L('কোন গ্রুপের নিচে', 'Under which header', 'কোন group-এর নিচে'), contra: L('বিয়োগের হিসাব (উল্টো দিকের)', 'Contra account (opposite side)', 'Contra (উল্টো দিকের)'),
  asset: L('সম্পদ', 'Asset', 'Asset'), liability: L('দায়', 'Liability', 'Liability'), eq: L('মালিকানা', 'Equity', 'Equity'), inc: L('আয়', 'Income', 'Income'), exp: L('খরচ', 'Expense', 'Expense'),
  retired: L('বন্ধ', 'retired', 'বন্ধ'), retire: L('বন্ধ করুন', 'Retire', 'বন্ধ করুন'), reopen: L('আবার চালু', 'Reactivate', 'আবার চালু'), rename: L('নাম বদলান', 'Rename', 'নাম বদলান'),
  sys: L('সিস্টেম', 'system', 'system'), hdr: L('গ্রুপ', 'header', 'group'), noParent: L('(কোনোটিই নয়)', '(none)', '(কোনোটিই নয়)'),
  // new journal
  nj: L('হাতে জার্নাল এন্ট্রি', 'Manual journal entry', 'Hate Journal entry'), jmemo: L('বিবরণ (কেন এই এন্ট্রি)', 'Memo (why this entry)', 'Memo (কেন)'), jreason: L('কারণ-কোড (গার্ড চালু থাকলে লাগে)', 'Reason code (needed when the guard is on)', 'Reason code (guard চালু থাকলে লাগে)'), addLine: L('+ লাইন যোগ', '+ Add a line', '+ Line যোগ'),
  line: L('লাইন', 'Line', 'Line'), debit: L('ডেবিট', 'Debit', 'Debit'), credit: L('ক্রেডিট', 'Credit', 'Credit'), party: L('পক্ষ', 'Party', 'Party'),
  ptNone: L('(কেউ নয়)', '(none)', '(কেউ নয়)'), ptCust: L('কাস্টমার', 'Customer', 'Customer'), ptSup: L('সাপ্লায়ার', 'Supplier', 'Supplier'), ptStaff: L('স্টাফ', 'Staff', 'Staff'), ptPart: L('অংশীদার', 'Partner', 'Partner'),
  custMob: L('কাস্টমারের মোবাইল', 'Customer mobile', 'Customer mobile'), staffId: L('স্টাফ/অংশীদার আইডি', 'Staff / partner id', 'Staff/partner id'),
  photo: L('ছবি (ইচ্ছামত)', 'Photo (optional)', 'Photo (optional)'), check: L('আগে পরীক্ষা করুন', 'Check first', 'আগে check করুন'), dryOk: L('পরীক্ষা ঠিক আছে — কিছু লেখা হয়নি', 'Check passed - nothing was written', 'Check ঠিক আছে — কিছু লেখা হয়নি'),
  place: L('জায়গা (ফাঁকা = প্রতিষ্ঠান)', 'Place (empty = company level)', 'Place (ফাঁকা = company)'), company: L('প্রতিষ্ঠান (কোনো জায়গা নয়)', 'Company level (no place)', 'Company (কোনো place নয়)'),
  // opening
  opH: L('শুরুর জের: হিসাব শুরুর ডেটে প্রতিটি হিসাবে কত ছিল তা লিখুন। একবারই দেওয়া যায়। যে অঙ্ক মিলবে না তা "জমা মুনাফা" দিয়ে মেলানো যাবে।', 'Opening balances: enter what each account held on the start date. Done once. Any difference can be put to "Retained earnings".', 'Opening: start date-এ প্রতিটি account-এ কত ছিল। একবারই। পার্থক্য Retained earnings-এ।'),
  opDone: L('শুরুর জের দেওয়া হয়ে গেছে। ভুল হলে জার্নাল বই থেকে উল্টো এন্ট্রি দিয়ে নতুন করে দিন।', 'The opening balances are already entered. To fix a mistake, post a reversing entry from the journal book and enter them again.', 'Opening দেওয়া আছে। ভুল হলে Journal book থেকে উল্টো entry দিয়ে আবার দিন।'),
  plug: L('অমিল অঙ্ক "জমা মুনাফা" দিয়ে মেলান', 'Put any difference to "Retained earnings"', 'অমিল অঙ্ক Retained earnings-এ'),
  addParty: L('+ পক্ষ অনুযায়ী', '+ By party', '+ Party অনুযায়ী'), amount: L('অঙ্ক', 'Amount', 'Amount'),
  // parties
  who: L('কার খাতা', 'Whose book', 'কার খাতা'), reco: L('বর্তমান হিসাবের সাথে মিলিয়ে দেখুন', 'Compare with the existing customer / supplier balances', 'Existing balance-এর সাথে মেলান'),
  recoOk: L('সব মিলেছে ✓', 'Everything agrees ✓', 'সব মিলেছে ✓'), custs: L('কাস্টমার', 'Customers', 'Customers'), sups: L('সাপ্লায়ার', 'Suppliers', 'Suppliers'),
  inBooks: L('খতিয়ানে', 'In the books', 'Khatiyane'), existing: L('বর্তমান হিসাবে', 'Existing', 'Existing'), unexpl: L('অমিল', 'Unexplained', 'অমিল'), unattr: L('কাস্টমার ছাড়া বাকি', 'Due with no customer', 'Customer ছাড়া বাকি'),
  recoNote: L('অমিল = শুরুর ডেটের আগের কোনো জের এখনো খতিয়ানে নেই (শুরুর জেরে পক্ষ অনুযায়ী দিন)।', 'A difference usually means a balance from before the start date is not in the books yet (enter it by party in the opening balances).', 'অমিল = start date-এর আগের জের এখনো books-এ নেই।'),
  // settings
  swOn: L('অ্যাকাউন্টিং চালু', 'Accounting on', 'Accounting on'), swAuto: L('পাতা খুললে নিজে পোস্ট', 'Auto-post when this page opens', 'Page খুললে নিজে post'),
  on: L('চালু', 'On', 'On'), offT: L('বন্ধ', 'Off', 'Off'), mapH: L('কোন লেনদেন কোন হিসাবে যাবে', 'Which account each kind of transaction goes to', 'কোন লেনদেন কোন account-এ'),
  mapNote: L('বদলালে শুধু পরের পোস্ট থেকে নতুন হিসাব ব্যবহার হবে; আগের এন্ট্রি বদলায় না।', 'A change only applies to entries posted from now on; old entries never change.', 'বদলালে শুধু পরের post থেকে; আগের entry বদলায় না।'),
  ownerOnly: L('শুধু মালিক বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner বদলাতে পারেন'),
  rcpt: L('উৎস দেখুন', 'Open the source', 'Source দেখুন'),
  // phase 72: posting status strip, failed postings, provisional profit, stock-vs-books reconcile
  lastPost: L('শেষ পোস্ট', 'Last post', 'শেষ post'), never: L('এখনও হয়নি', 'not yet', 'এখনও হয়নি'), pending: L('অপেক্ষমাণ', 'Pending', 'অপেক্ষমাণ'),
  errN: L('ত্রুটি', 'Errors', 'ত্রুটি'), heldN: L('বন্ধ মাসের কারণে আটকে', 'Held by a closed period', 'বন্ধ মাসের কারণে আটকে'),
  failN: L('টি এন্ট্রি পোস্ট হয়নি', 'entries were not posted', 'টি entry post হয়নি'), openPost: L('এখন পোস্ট প্যানেল খুলুন', 'Open the Post now panel', 'Post now panel খুলুন'),
  unkCost: L('সাময়িক: খরচহীন সেল', 'Provisional: sales with no known cost', 'সাময়িক: খরচহীন sale'), provis: L('সাময়িক', 'provisional', 'সাময়িক'),
  estMiss: L('বইয়ের কস্ট থেকে অনুমান', 'estimate from the typed cost', 'বইয়ের cost থেকে অনুমান'),
  invH: L('মিলানো: স্টক বনাম খতিয়ান', 'Reconcile: stock vs books', 'মিলানো: stock vs খতিয়ান'),
  invNote: L('পার্থক্য = খতিয়ানে − স্টকের মূল্য। এখানে কিছু পোস্ট হয় না, শুধু দেখানো হয়।', 'Difference = books − stock value. Nothing is posted here, it is only shown.', 'পার্থক্য = খতিয়ানে − stock-এর মূল্য। এখানে কিছু post হয় না।'),
  invGl: L('খতিয়ানে', 'In the books', 'খতিয়ানে'), invVal: L('স্টকের মূল্য', 'Stock value', 'stock-এর মূল্য'), invDiff: L('পার্থক্য', 'Difference', 'পার্থক্য'),
  invUnexpl: L('ব্যাখ্যাহীন', 'Unexplained', 'ব্যাখ্যাহীন'), invOk: L('স্টক ও খতিয়ান মিলেছে ✓', 'Stock and books agree ✓', 'stock ও খতিয়ান মিলেছে ✓'),
  invReplay: L('আগের ডেট: মূল্য লেজার থেকে হিসাব করা (গড় কস্ট নয়)', 'Earlier date: value replayed from the ledger (not the average cost)', 'আগের date: মূল্য ledger থেকে'),
  invT_inv_finished: L('তৈরি পণ্য', 'Finished goods', 'তৈরি পণ্য'), invT_inv_raw: L('কাঁচামাল', 'Raw materials', 'কাঁচামাল'), invT_inv_pack: L('প্যাকেজিং', 'Packaging', 'প্যাকেজিং'),
  rs_valuation_basis: L('গড় কস্ট বনাম লেজারের মান (পূর্ণসংখ্যার হিসাবের তফাত)', 'Average cost vs ledger value', 'গড় cost vs ledger মান'),
  rs_count_adjust: L('গণনায় সমন্বয় (খতিয়ানে ওঠেনি)', 'Stock-count adjustment (not in the books)', 'গণনায় সমন্বয় (খতিয়ানে ওঠেনি)'),
  rs_opening: L('শুরুর স্টক (খতিয়ানে জের দেওয়া হয়নি)', 'Opening stock (not in the opening balances)', 'শুরুর stock (জের দেওয়া হয়নি)'),
  rs_transfer: L('ট্রান্সফার (পথে বা কম পাওয়া সহ)', 'Transfers (in transit or short receipt)', 'ট্রান্সফার (পথে/কম পাওয়া সহ)'),
  rs_issue_out: L('হাতে ইস্যু / ফর্মে ইস্যু', 'Manual or form issue', 'হাতে/ফর্মে ইস্যু'),
  rs_manual_in: L('হাতে বা ফর্মে তোলা মাল', 'Stock added by hand or form', 'হাতে/ফর্মে তোলা মাল'),
  rs_purchase_before_start: L('শুরুর ডেটের আগের কেনা', 'Purchases before the start date', 'শুরুর date-এর আগের কেনা'),
  rs_purchase_return_variance: L('কেনা ফেরতে প্রাইসের পার্থক্য', 'Purchase-return price variance', 'কেনা ফেরতে price-এর পার্থক্য'),
  rs_production_cost_missing: L('কস্ট অজানা উৎপাদন (আংশিক পোস্ট)', 'Production with an unknown cost (partly posted)', 'cost অজানা উৎপাদন'),
  rs_manual_journal: L('হাতে জার্নাল', 'Manual journal on the inventory account', 'হাতে জার্নাল'),
};
const T = (k) => lab(X[k]);
const SRC = { sale: L('সেল', 'Sale', 'Sale'), sale_return: L('সেল ফেরত', 'Sale return', 'Sale return'), collection: L('বাকি আদায়', 'Collection', 'Collection'), purchase: L('ক্রয়', 'Purchase', 'Purchase'),
  supplier_payment: L('সাপ্লায়ারকে দেওয়া', 'Supplier payment', 'Supplier payment'), supplier_refund: L('সাপ্লায়ারের ফেরত', 'Supplier refund', 'Supplier refund'), expense_voucher: L('ব্যয় ভাউচার', 'Expense voucher', 'Expense voucher'),
  cash_move: L('ক্যাশ/ব্যাংক', 'Cash move', 'Cash move'), wastage: L('নষ্ট মাল', 'Wastage', 'Wastage'), production: L('উৎপাদন', 'Production', 'Production'), manual: L('হাতে লেখা', 'Manual', 'Manual'), opening: L('শুরুর জের', 'Opening', 'Opening'),
  stock_adjust: L('স্টক গণনার পার্থক্য', 'Stock count adjustment', 'Stock count adjustment'), stock_opening: L('Opening stock', 'Opening stock', 'Opening stock'), stock_issue: L('নিজের কাজে স্টক', 'Stock issued for own use', 'Stock issued for own use'),
  stock_transfer: L('Stock transfer', 'Stock transfer', 'Stock transfer'), transit_loss: L('পথে কম পৌঁছানো স্টক', 'Stock short in transit', 'Stock short in transit'), purchase_variance: L('ক্রয় ফেরতের প্রাইসের পার্থক্য', 'Purchase price variance', 'Purchase price variance'),
  card_settlement: L('কার্ড settlement', 'Card settlement', 'Card settlement') };
const sl = (k) => (SRC[k] ? lab(SRC[k]) : k);
const LINKS = { sale: '#/pos', sale_return: '#/salereturn', collection: '#/dues', purchase: '#/purchase', supplier_payment: '#/payables', supplier_refund: '#/payables', expense_voucher: '#/daybook', cash_move: '#/cashmoves' };
const link = (st, sid) => (LINKS[st] ? `<a href="${LINKS[st]}" class="ac-src">${esc(sl(st))}</a> <span class="ac-id">${esc(String(sid).slice(0, 8))}</span>` : `<span class="ac-src">${esc(sl(st))}</span>`);

const ERR = {
  reason_required: L('কারণ-কোড বেছে নিন (গার্ড চালু আছে)', 'Pick a reason code (the guard is on)', 'Reason code বেছে নিন (guard চালু)'), bad_reason: L('কারণ-কোড ঠিক নয়', 'That reason code is not valid', 'Reason code ঠিক নয়'),
  party_required: L('payable / receivable লাইনে পক্ষ (party) লাগবে', 'A payable / receivable line needs a party', 'Payable / receivable line-এ party লাগবে'),
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'), data_needed: X.needH, accounting_off: L('অ্যাকাউন্টিং বন্ধ — আগে চালু করুন', 'Accounting is off - switch it on first', 'Accounting off — আগে on করুন'),
  unbalanced: L('ডেবিট আর ক্রেডিট সমান নয়', 'Debit and credit are not equal', 'Debit আর Credit সমান নয়'), line_debit_xor_credit: L('প্রতি লাইনে ডেবিট বা ক্রেডিট — একটিই', 'Each line is either debit or credit, not both', 'প্রতি line-এ Debit বা Credit — একটিই'),
  need_two_lines: L('কমপক্ষে দুটি লাইন লাগবে', 'At least two lines are needed', 'কমপক্ষে দুটি line'), memo_required: L('বিবরণ লিখুন', 'Write a memo', 'Memo লিখুন'), bad_amount: L('অঙ্ক ঠিক নয়', 'An amount is not valid', 'অঙ্ক ঠিক নয়'),
  unknown_account: L('হিসাব পাওয়া যায়নি', 'Account not found', 'Account পাওয়া যায়নি'), account_retired: L('এই হিসাব বন্ধ করা আছে', 'This account is retired', 'এই account বন্ধ'), account_is_group: L('গ্রুপ হিসাবে এন্ট্রি দেওয়া যায় না', 'A header account cannot be posted to', 'Group account-এ entry হয় না'),
  before_start: L('শুরুর ডেটের আগে এন্ট্রি হয় না', 'Nothing can be dated before the start date', 'Start date-এর আগে entry হয় না'), bad_date: L('ডেট ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'),
  period_closed: L('এই মাস বন্ধ — মালিকের অনুমতি লাগবে', 'This period is closed - the owner is needed', 'এই মাস বন্ধ'), opening_exists: L('শুরুর জের আগেই দেওয়া আছে', 'The opening balances are already entered', 'Opening আগেই দেওয়া'),
  postings_before_opening: L('শুরুর ডেটের আগে এন্ট্রি আছে', 'There are entries before the opening date', 'Opening-এর আগে entry আছে'), opening_balance_sheet_only: L('শুরুর জেরে আয়/খরচের হিসাব চলবে না', 'Opening balances cover balance-sheet accounts only', 'Opening-এ income/expense নয়'),
  code_taken: L('এই কোড আগেই আছে', 'That code is already used', 'এই code আছে'), bad_code: L('কোড ঠিক নয় (অক্ষর/সংখ্যা, ১২টির মধ্যে)', 'Code is not valid (letters / digits, up to 12)', 'Code ঠিক নয়'),
  bad_parent: L('গ্রুপ ঠিক নয় (একই ধরনের গ্রুপ লাগবে)', 'Header is not valid (same type needed)', 'Group ঠিক নয়'), account_in_use_by_mapping: L('এই হিসাব ম্যাপিংয়ে ব্যবহার হচ্ছে — আগে ম্যাপিং বদলান', 'This account is used by a mapping - change the mapping first', 'Mapping-এ ব্যবহার হচ্ছে'),
  has_active_children: L('নিচে চালু হিসাব আছে', 'It still has active accounts under it', 'নিচে চালু account আছে'), name_required: L('দুই ভাষায় নাম লিখুন', 'Write the name in both languages', 'দুই ভাষায় নাম'),
  entries_before_start: L('এর আগের ডেটে এন্ট্রি আছে — শুরুর ডেট সামনে নেওয়া যাবে না', 'Entries already exist before that date', 'এর আগে entry আছে'), bad_party: L('পক্ষ ঠিক নয়', 'The party is not valid', 'Party ঠিক নয়'),
  party_id_required: L('পক্ষ বেছে নিলে তার আইডি/মোবাইল লাগবে', 'A party needs its id / mobile', 'Party-র id লাগবে'), already_reversed: L('আগেই উল্টো এন্ট্রি হয়েছে', 'Already reversed', 'আগেই উল্টো হয়েছে'),
  use_source: L('এটি অটো এন্ট্রি — মূল কাগজ (বিক্রি/ক্রয় ইত্যাদি) ভয়েড করুন', 'This is an automatic entry - void the original document instead', 'Auto entry — মূল document void করুন'),
  mapping_missing: L('একটি ম্যাপিং নেই', 'A mapping is missing', 'Mapping নেই'), client_id_taken: L('একই অনুরোধ আরেকজনের', 'That request id belongs to someone else', 'Request id অন্যের'), note_required: X.why,
  bad_key: L('ম্যাপিং-কী ঠিক নয়', 'Mapping key is not valid', 'Mapping key ঠিক নয়'), bad_account: L('হিসাব ঠিক নয় (গ্রুপ বা বন্ধ হিসাব নেওয়া যায় না)', 'Account not valid (not a header or retired account)', 'Account ঠিক নয়'),
  bad_location: L('জায়গা ঠিক নয়', 'The place is not valid', 'Place ঠিক নয়'), bad_range: L('ডেটের সীমা ঠিক নয়', 'The date range is not valid', 'Date range ঠিক নয়'), too_many_lines: L('লাইন বেশি হয়ে গেছে', 'Too many lines', 'Line বেশি'),
  bad_photo: L('ছবির পথ ঠিক নয়', 'The photo path is not valid', 'Photo ঠিক নয়'), account_fixed: L('কোড/ধরন বদলানো যায় না', 'Code and type cannot change', 'Code/type বদলায় না'),
};
const eText = (e) => { const m = String((e && e.message) || e || ''); if (/Cannot read propert|is not a function|is not defined|of undefined|of null/.test(m)) return lab(L('ডেটা পাওয়া যায়নি, আবার চেষ্টা করুন', 'No data came back. Try again.', 'Data পাওয়া যায়নি, আবার চেষ্টা করুন')); /* bos108: a JS error is never shown to the user */ const k = Object.keys(ERR).find((x) => m.includes(x)); let s = k ? lab(ERR[k]) : m || 'error'; if (k === 'unbalanced' && e && e.details) s += ' (' + e.details + ')'; else if (k === 'unbalanced') { const d = m.match(/debit ([\d.]+) credit ([\d.]+)/); if (d) s += ' (' + d[1] + ' / ' + d[2] + ')'; } if (k === 'mapping_missing') { const d = m.match(/mapping_missing:(\S+)/); if (d) s += ': ' + d[1]; } return s; };

const D = { tab: 'overview', st: null, loc: '', from: '', to: '', asof: '', acc: null, accounts: [], maps: [], accId: '', csv: null, rep: '', client: rid(), lines: [], op: { rows: {}, plug: true }, party: { type: 'customer', id: '', mobile: '' },
  sups: null, jl: 0, jlimit: 100, loaded: false, hint: '' };
const TABS = ['overview', 'bs', 'pl', 'cf', 'tb', 'ledger', 'journal', 'parties', 'chart', 'new', 'opening', 'settings'];
const RANGED = new Set(['pl', 'cf', 'tb', 'ledger', 'journal', 'parties']);
const isMgr = () => !!(D.st && D.st.can_manage);
const isOwner = () => !!(D.st && D.st.owner);

const css = document.createElement('style'); css.id = 'accss';
css.textContent = `.ac-bar{display:grid;grid-template-columns:1fr 1fr;gap:8px}.ac-bar .w2{grid-column:1/-1}.ac-t{width:100%;border-collapse:collapse;font-size:.85rem}.ac-t th,.ac-t td{padding:6px 4px;border-bottom:1px solid var(--hair);vertical-align:top}
.ac-t th{text-align:start;color:var(--muted);font-weight:600}.ac-t .n{text-align:end;white-space:nowrap;font-variant-numeric:lining-nums tabular-nums}.ac-t tr.g td{font-weight:700;background:var(--card-2,transparent)}.ac-t tr.tot td{font-weight:700;border-top:2px solid var(--ink)}
.ac-scroll{max-width:100%;overflow-x:auto}.ac-sum{display:grid;grid-template-columns:1fr 1fr;gap:8px}.ac-sum .stat{min-height:64px}.ac-neg{color:var(--sig-bad)}.ac-ok{color:var(--sig-good,#2a7d46)}
.ac-lr{padding:8px 0;border-bottom:1px solid var(--hair)}.ac-lr .r1{display:flex;justify-content:space-between;gap:8px}.ac-lr .r2{display:flex;gap:12px;justify-content:flex-end;font-size:.85rem;font-variant-numeric:lining-nums tabular-nums}.ac-lr .sub{font-size:.8rem;color:var(--muted);overflow-wrap:anywhere}
.ac-id{color:var(--muted);font-size:.75rem}.ac-warn{border-inline-start:4px solid var(--sig-bad);padding:8px 10px;background:var(--card-2,transparent);margin:8px 0}.ac-note{border-inline-start:4px solid var(--hair);padding:6px 10px;margin:8px 0;font-size:.85rem}
.ac-line{border:1px solid var(--hair);border-radius:12px;padding:8px;margin:8px 0}.ac-line .row2{display:grid;grid-template-columns:1fr 1fr;gap:8px}.ac-ind1{padding-inline-start:12px}.ac-ind2{padding-inline-start:24px}.ac-ind3{padding-inline-start:36px}
#ac_print{display:none}@media print{body>*:not(#ac_print){display:none!important}#ac_print{display:block!important;color:#000;background:#fff}#ac_print table{width:100%;border-collapse:collapse;font-size:11px}#ac_print th,#ac_print td{border-bottom:1px solid #999;padding:3px 4px}#ac_print .n{text-align:right}}`;
document.head.appendChild(css);

// ---------- helpers ----------
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };
const locs = () => (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []));
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? (S.lang === 'en' ? (l.name_en || l.name_bn) : (l.name_bn || l.name_en)) : (id == null ? '' : String(id)); };
const locP = () => (D.loc === '' ? null : Number(D.loc));
const depth = (rows, r) => { const m = new Map(rows.map((x) => [x.id, x])); let d = 0, p = r.parent_id; while (p && m.has(p) && d < 6) { d++; p = m.get(p).parent_id; } return d; };
const amtCell = (v) => `<td class="n ${Number(v) < 0 ? 'ac-neg' : ''}">${esc(fm(v))}</td>`;
function sectionRows(rows) {
  return rows.map((r) => `<tr class="${r.is_group ? 'g' : ''}"><td class="ac-ind${Math.min(3, depth(rows, r))}">${esc(r.code)} · ${esc(an(r))}</td>${amtCell(r.amount)}</tr>`).join('');
}
function table(head, body) { return `<div class="ac-scroll"><table class="ac-t"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`; }
function setCsv(name, rows) { D.csv = { name, rows }; }
function download(name, text) {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + text], { type: 'text/csv;charset=utf-8' })); a.download = name;
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
const q = (v) => '"' + String(v ?? '').replace(/"/g, '""') + '"';
function noData() { return `<div class="card"><p><b>${esc(T('need'))}</b></p><p>${esc(T('needH'))}</p>${isOwner() ? startForm() : ''}</div>`; }
function startForm() {
  return `<div class="stack"><label for="ac_start">${esc(T('start'))}</label><input id="ac_start" type="date" value="${esc((D.st && D.st.start) || today())}"><button class="primary full" data-act="ac_setstart">${esc(T('setStart'))}</button></div>`;
}
const warnHtml = (bs) => {
  let h = '';
  if (bs && bs.unbalanced) h += `<div class="ac-warn" role="alert"><b>${esc(T('unbal'))}: ${esc(fm(bs.difference))}</b></div>`;
  if (bs && Number(bs.cogs_missing) > 0) h += `<div class="ac-note">${esc(String(bs.cogs_missing))} ${esc(T('cogsM'))}</div>`;
  if (bs && Number(bs.unknown_cost_rev) > 0) h += `<div class="ac-note">${esc(T('unkCost'))}: ${esc(money(bs.unknown_cost_rev))}${Number(bs.cogs_estimate_missing) > 0 ? ' · ' + esc(T('estMiss')) + ': ' + esc(money(bs.cogs_estimate_missing)) : ''}</div>`;
  return h;
};

// ---------- the common bar ----------
function bar(kind) {
  const ls = locs();
  const lsel = `<div><label for="ac_loc">${esc(T('loc'))}</label><select id="ac_loc"><option value="">${esc(T('all'))}</option>${ls.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.loc) ? 'selected' : ''}>${esc(locName(l.id))}</option>`).join('')}</select></div>`;
  let dates = '';
  if (kind === 'asof') dates = `<div><label for="ac_asof">${esc(T('asof'))}</label><input id="ac_asof" type="date" value="${esc(D.asof)}"></div>`;
  else if (kind === 'range') dates = `<div><label for="ac_from">${esc(T('from'))}</label><input id="ac_from" type="date" value="${esc(D.from)}"></div><div><label for="ac_to">${esc(T('to'))}</label><input id="ac_to" type="date" value="${esc(D.to)}"></div>`;
  return `<div class="ac-bar">${lsel}${dates}</div>`;
}
const exportBar = () => `<div class="row"><button class="full" data-act="ac_print">${esc(T('print'))}</button><button class="full" data-act="ac_csv">${esc(T('csv'))}</button></div>`;
const repHead = (title, period) => `<h3>${esc(title)}</h3><div class="muted">${esc(D.loc === '' ? T('all') : locName(Number(D.loc)))} · ${esc(period || (D.tab === 'bs' ? D.asof : D.from + ' – ' + D.to))}</div>`;

// ---------- tabs ----------
async function tOverview() {
  let [ov, bs, is] = await Promise.all([rpc('acct_overview', { p_loc: locP() }), rpc('acct_balance_sheet', { p_as_of: D.asof, p_loc: locP() }), rpc('acct_income_statement', { p_from: D.from, p_to: D.to, p_loc: locP() })]);
  bs = bs || {}; is = is || {}; /* bos108: a report that returns nothing must not throw a raw JS error */
  if (!ov || ov.data_needed) return noData(); /* bos108 */
  ov.income_month = ov.income_month || {};
  let h = bar('asof');
  h += warnHtml(bs) + warnHtml({ unknown_cost_rev: is.unknown_cost_rev, cogs_estimate_missing: is.cogs_estimate_missing });
  if (!ov.on) h += `<div class="ac-note">${esc(T('off'))}</div>`;
  h += `<div class="ac-sum">
    <div class="card stat"><div class="muted">${esc(T('totA'))}</div><b>${esc(money(bs.total_assets))}</b></div>
    <div class="card stat"><div class="muted">${esc(T('totL'))}</div><b>${esc(money(bs.total_liabilities))}</b></div>
    <div class="card stat"><div class="muted">${esc(T('totE'))} + ${esc(T('earn'))}</div><b>${esc(money(bs.total_equity_and_earnings))}</b></div>
    <div class="card stat"><div class="muted">${esc(T('net'))} (${esc(T('month'))})</div><b class="${Number(ov.income_month.net_profit) < 0 ? 'ac-neg' : ''}">${esc(money(ov.income_month.net_profit))}</b></div>
    <div class="card stat"><div class="muted">${esc(T('totI'))} (${esc(T('month'))})</div><b>${esc(money(ov.income_month.total_income))}</b></div>
    <div class="card stat"><div class="muted">${esc(T('gross'))} (${esc(T('month'))})</div><b>${esc(money(ov.income_month.gross_profit))}</b></div></div>
    <p class="${bs.unbalanced ? 'ac-neg' : 'ac-ok'}">${esc(bs.unbalanced ? T('unbal') + ' ' + fm(bs.difference) : T('bal'))}</p>`;
  if (isMgr()) h += `<button class="primary full" data-act="ac_post">${esc(T('postNow'))}</button>`;
  h += `<div id="ac_rep">${repHead(T('t_bs'), D.asof)}${bsTables(bs)}${repHead(T('t_pl'), D.from + ' – ' + D.to)}${plTables(is)}</div>`;
  D.rep = 'ov'; setCsv(`accounts-overview-${D.asof}.csv`, [['section', 'code', 'name', 'amount'], ...csvSec(bs.assets, 'assets'), ...csvSec(bs.liabilities, 'liabilities'), ...csvSec(bs.equity, 'equity'), ['earnings', '', 'Earnings to date', bs.retained_earnings],
    ...csvSec(is.income, 'income'), ...csvSec(is.expense, 'expense'), ['net', '', 'Net profit', is.net_profit]]);
  return h + exportBar();
}
const csvSec = (rows, sec) => (rows || []).filter((r) => !r.is_group).map((r) => [sec, r.code, r.name_en, r.amount]);
function bsTables(bs) {
  return table(`<th>${esc(T('assets'))}</th><th class="n"></th>`, sectionRows(bs.assets) + `<tr class="tot"><td>${esc(T('totA'))}</td>${amtCell(bs.total_assets)}</tr>`)
    + table(`<th>${esc(T('liabs'))}</th><th class="n"></th>`, sectionRows(bs.liabilities) + `<tr class="tot"><td>${esc(T('totL'))}</td>${amtCell(bs.total_liabilities)}</tr>`)
    + table(`<th>${esc(T('equity'))}</th><th class="n"></th>`, sectionRows(bs.equity) + `<tr><td>${esc(T('earn'))}</td>${amtCell(bs.retained_earnings)}</tr><tr class="tot"><td>${esc(T('totE'))} + ${esc(T('earn'))}</td>${amtCell(bs.total_equity_and_earnings)}</tr>`)
    + `<p class="${bs.unbalanced ? 'ac-neg' : 'ac-ok'}">${esc(T('totLE'))}: ${esc(money(bs.total_liabilities_and_equity))} · ${esc(bs.unbalanced ? T('unbal') + ' ' + fm(bs.difference) : T('bal'))}</p>`;
}
function plTables(p) {
  return table(`<th>${esc(T('income'))}</th><th class="n"></th>`, sectionRows(p.income) + `<tr class="tot"><td>${esc(T('totI'))}</td>${amtCell(p.total_income)}</tr>`)
    + table(`<th>${esc(T('expense'))}</th><th class="n"></th>`, sectionRows(p.expense) + `<tr class="tot"><td>${esc(T('totX'))}</td>${amtCell(p.total_expense)}</tr>`)
    + table('<th></th><th class="n"></th>', `<tr><td>${esc(T('cogs'))}</td>${amtCell(p.cogs)}</tr><tr><td>${esc(T('gross'))}${p.provisional ? ' (' + esc(T('provis')) + ')' : ''}</td>${amtCell(p.gross_profit)}</tr><tr class="tot"><td>${esc(T('net'))}</td>${amtCell(p.net_profit)}</tr>`);
}
async function tBs() {
  const bs = await rpc('acct_balance_sheet', { p_as_of: D.asof, p_loc: locP() });
  if (bs.data_needed) return noData();
  setCsv(`balance-sheet-${D.asof}.csv`, [['section', 'code', 'name', 'amount'], ...csvSec(bs.assets, 'assets'), ...csvSec(bs.liabilities, 'liabilities'), ...csvSec(bs.equity, 'equity'), ['earnings', '', 'Earnings to date', bs.retained_earnings]]);
  return bar('asof') + warnHtml(bs) + `<div id="ac_rep">${repHead(T('t_bs'))}${bsTables(bs)}</div>` + exportBar();
}
async function tPl() {
  const p = await rpc('acct_income_statement', { p_from: D.from, p_to: D.to, p_loc: locP() });
  if (p.data_needed) return noData();
  setCsv(`profit-loss-${D.from}_${D.to}.csv`, [['section', 'code', 'name', 'amount'], ...csvSec(p.income, 'income'), ...csvSec(p.expense, 'expense'), ['cogs', '', 'Cost of goods sold', p.cogs], ['gross', '', 'Gross profit', p.gross_profit], ['net', '', 'Net profit', p.net_profit]]);
  return bar('range') + warnHtml({ cogs_missing: p.cogs_missing, unknown_cost_rev: p.unknown_cost_rev, cogs_estimate_missing: p.cogs_estimate_missing }) + `<div id="ac_rep">${repHead(T('t_pl'))}${plTables(p)}</div>` + exportBar();
}
async function tCf() {
  const c = await rpc('acct_cash_flow', { p_from: D.from, p_to: D.to, p_loc: locP() });
  if (c.data_needed) return noData();
  const body = `<tr><td>${esc(T('opening'))}</td><td class="n"></td><td class="n"></td>${amtCell(c.opening)}</tr>` + (c.rows || []).map((r) => `<tr><td>${esc(sl(r.category) === r.category ? r.category : sl(r.category))}</td>${amtCell(r.in)}${amtCell(r.out)}${amtCell(r.net)}</tr>`).join('')
    + `<tr class="tot"><td>${esc(T('closing'))}</td>${amtCell(c.total_in)}${amtCell(c.total_out)}${amtCell(c.closing)}</tr>`;
  setCsv(`cash-flow-${D.from}_${D.to}.csv`, [['category', 'in', 'out', 'net'], ['opening', '', '', c.opening], ...(c.rows || []).map((r) => [r.category, r.in, r.out, r.net]), ['closing', c.total_in, c.total_out, c.closing]]);
  return bar('range') + `<div id="ac_rep">${repHead(T('t_cf'))}${table(`<th></th><th class="n">+</th><th class="n">−</th><th class="n">${esc(T('bal2'))}</th>`, body)}</div>` + exportBar();
}
async function tTb() {
  const t = await rpc('acct_trial_balance', { p_from: D.from, p_to: D.to, p_loc: locP() });
  if (t.data_needed) return noData();
  const rows = t.rows || [];
  const body = rows.map((r) => `<tr class="${r.is_group ? 'g' : ''}"><td class="ac-ind${Math.min(3, depth(rows, r))}">${esc(r.code)} · ${esc(an(r))}<div class="ac-id">${esc(T('period'))}: ${esc(fm(r.dr))} / ${esc(fm(r.cr))}</div></td>${amtCell(r.close_dr)}${amtCell(r.close_cr)}</tr>`).join('')
    + `<tr class="tot"><td>${esc(T('totals'))}</td>${amtCell(t.total_debit)}${amtCell(t.total_credit)}</tr>`;
  setCsv(`trial-balance-${D.from}_${D.to}.csv`, [['code', 'name', 'open_dr', 'open_cr', 'period_dr', 'period_cr', 'close_dr', 'close_cr'], ...rows.filter((r) => !r.is_group).map((r) => [r.code, r.name_en, r.open_dr, r.open_cr, r.dr, r.cr, r.close_dr, r.close_cr]), ['TOTAL', '', '', '', '', '', t.total_debit, t.total_credit]]);
  return bar('range') + (t.balanced ? '' : `<div class="ac-warn" role="alert"><b>${esc(T('diff'))}: ${esc(fm(t.diff))}</b></div>`)
    + `<div id="ac_rep">${repHead(T('t_tb'))}${table(`<th>${esc(T('account'))}</th><th class="n">${esc(T('dr'))}</th><th class="n">${esc(T('cr'))}</th>`, body)}<p class="${t.balanced ? 'ac-ok' : 'ac-neg'}">${esc(t.balanced ? T('bal') : T('diff') + ' ' + fm(t.diff))}</p></div>` + exportBar();
}
async function loadAccounts() {
  const r = await sb.from('coa_accounts').select('id,code,name_bn,name_en,type,parent_id,normal_side,is_group,is_system,active,sort').order('code');
  D.accounts = r.data || [];
}
async function loadMaps() { const r = await sb.from('acct_mappings').select('key,account_id,label_bn,label_en').order('key'); D.maps = r.data || []; }
const accOpts = (sel, onlyLeaf, onlyActive) => D.accounts.filter((a) => (!onlyLeaf || !a.is_group) && (!onlyActive || a.active)).map((a) => `<option value="${a.id}" ${String(a.id) === String(sel) ? 'selected' : ''}>${esc(a.code)} · ${esc(an(a))}${a.is_group ? ' [' + esc(T('hdr')) + ']' : ''}${a.active ? '' : ' (' + esc(T('retired')) + ')'}</option>`).join('');
async function tLedger() {
  if (!D.accounts.length) await loadAccounts();
  let h = bar('range') + `<div><label for="ac_acc">${esc(T('account'))}</label><select id="ac_acc"><option value="">${esc(T('pickAcc'))}</option>${accOpts(D.accId, false, false)}</select></div>`;
  if (!D.accId) { D.csv = null; return h + `<p class="muted">${esc(T('pickAcc'))}</p>`; }
  const g = await rpc('acct_ledger', { p_account: Number(D.accId), p_from: D.from, p_to: D.to, p_loc: locP(), p_limit: 1000 });
  if (g.data_needed) return noData();
  const rows = g.rows || [];
  const list = `<div class="ac-lr"><div class="r1"><b>${esc(T('opening'))}</b><b>${esc(fm(g.opening))}</b></div></div>` + rows.map((r) => `<div class="ac-lr"><div class="r1"><span>${esc(r.date)} · ${esc(r.memo)}${r.reversal ? ' (' + esc(T('isRev')) + ')' : ''}</span></div>
    <div class="sub">${link(r.source_type, r.source_id)}${r.party_type ? ' · ' + esc(r.party_type) : ''}${r.location_id ? ' · ' + esc(locName(r.location_id)) : ''}</div>
    <div class="r2"><span>${esc(T('dr'))} ${esc(fm(r.debit))}</span><span>${esc(T('cr'))} ${esc(fm(r.credit))}</span><b>${esc(fm(r.balance))}</b></div></div>`).join('')
    + `<div class="ac-lr"><div class="r1"><b>${esc(T('closing'))}</b><b>${esc(fm(g.closing))}</b></div></div>` + (g.truncated ? `<p class="muted">${esc(T('more'))}</p>` : '');
  setCsv(`ledger-${g.account.code}-${D.from}_${D.to}.csv`, [['date', 'entry', 'source', 'source_id', 'memo', 'debit', 'credit', 'balance'], ['', '', '', '', 'opening', '', '', g.opening], ...rows.map((r) => [r.date, r.entry_id, r.source_type, r.source_id, r.memo, r.debit, r.credit, r.balance]), ['', '', '', '', 'closing', '', '', g.closing]]);
  return h + `<div id="ac_rep">${repHead(g.account.code + ' · ' + an(g.account))}${list}</div>` + exportBar();
}
async function tJournal() {
  const j = await rpc('acct_journal_book', { p_from: D.from, p_to: D.to, p_loc: locP(), p_limit: D.jlimit, p_offset: 0 });
  if (j.data_needed) return noData();
  const rows = j.rows || [];
  const card = (e) => `<div class="card"><div class="row between"><b>${esc(e.date)} · #${e.id}</b><span>${link(e.source_type, e.source_id)}</span></div>
    <div>${esc(e.memo)} ${e.reverses_id ? '(' + esc(T('isRev')) + ')' : ''} ${e.status === 'void' ? '(' + esc(T('isVoid')) + ')' : ''}${e.flags ? ' · ' + esc(e.flags) : ''}</div>
    <div class="ac-scroll"><table class="ac-t"><tbody>${(e.lines || []).map((l) => `<tr><td>${esc(l.code)} · ${esc(an(l))}</td><td class="n">${l.debit > 0 ? esc(fm(l.debit)) : ''}</td><td class="n">${l.credit > 0 ? esc(fm(l.credit)) : ''}</td></tr>`).join('')}</tbody></table></div>
    ${isMgr() && (e.source_type === 'manual' || e.source_type === 'opening') && !e.reverses_id && e.status !== 'void' ? `<div class="row"><button class="mini" data-act="ac_rev" data-v="${e.id}">⋮ ${esc(T('reverse'))}</button></div>` : ''}</div>`;
  setCsv(`journal-${D.from}_${D.to}.csv`, [['entry', 'date', 'source', 'source_id', 'memo', 'code', 'debit', 'credit', 'party_type', 'party_id'], ...rows.flatMap((e) => (e.lines || []).map((l) => [e.id, e.date, e.source_type, e.source_id, e.memo, l.code, l.debit, l.credit, l.party_type, l.party_id]))]);
  return bar('range') + `<div id="ac_rep">${repHead(T('t_journal') + ' (' + j.total + ')')}${rows.length ? rows.map(card).join('') : `<p class="muted">${esc(T('none'))}</p>`}</div>` + (j.total > rows.length ? `<button class="full" data-act="ac_morej">${esc(T('more2'))}</button>` : '') + exportBar();
}
async function tParties() {
  if (D.sups === null) { const r = await sb.from('suppliers').select('id,name').order('name'); D.sups = r.data || []; }
  const P = D.party;
  let h = bar('range') + `<div class="ac-bar"><div><label for="ac_ptype">${esc(T('who'))}</label><select id="ac_ptype"><option value="customer" ${P.type === 'customer' ? 'selected' : ''}>${esc(T('ptCust'))}</option><option value="supplier" ${P.type === 'supplier' ? 'selected' : ''}>${esc(T('ptSup'))}</option></select></div>
    <div>${P.type === 'supplier' ? `<label for="ac_pid">${esc(T('ptSup'))}</label><select id="ac_pid"><option value=""></option>${D.sups.map((s) => `<option value="${esc(s.id)}" ${s.id === P.id ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select>`
      : `<label for="ac_pmob">${esc(T('custMob'))}</label><input id="ac_pmob" inputmode="tel" autocomplete="off" value="${esc(P.mobile)}">`}</div></div><button class="full" data-act="ac_pshow">${esc(T('show'))}</button>`;
  if (P.id) {
    const g = await rpc('acct_party_ledger', { p_type: P.type, p_id: P.id, p_from: D.from, p_to: D.to, p_loc: locP() });
    if (g.data_needed) return noData();
    const rows = g.rows || [];
    h += `<div id="ac_rep">${repHead(T(P.type === 'supplier' ? 'ptSup' : 'ptCust'))}<div class="ac-lr"><div class="r1"><b>${esc(T('opening'))}</b><b>${esc(fm(g.opening))}</b></div></div>`
      + rows.map((r) => `<div class="ac-lr"><div class="r1"><span>${esc(r.date)} · ${esc(r.memo)}</span></div><div class="sub">${link(r.source_type, r.source_id)}</div><div class="r2"><span>${esc(T('dr'))} ${esc(fm(r.debit))}</span><span>${esc(T('cr'))} ${esc(fm(r.credit))}</span><b>${esc(fm(r.balance))}</b></div></div>`).join('')
      + `<div class="ac-lr"><div class="r1"><b>${esc(T('closing'))}</b><b>${esc(fm(g.closing))}</b></div></div></div>`;
    setCsv(`party-${P.type}-${D.from}_${D.to}.csv`, [['date', 'source', 'source_id', 'memo', 'debit', 'credit', 'balance'], ...rows.map((r) => [r.date, r.source_type, r.source_id, r.memo, r.debit, r.credit, r.balance])]);
    h += exportBar();
  } else D.csv = null;
  h += `<hr><button class="full" data-act="ac_reco">${esc(T('reco'))}</button><div id="ac_reco"></div>`;
  return h;
}
async function reco() {
  const out = $('#ac_reco'); if (!out) return;
  try {
    const r = await rpc('acct_reconcile', { p_kind: 'all' });
    if (r.data_needed) { out.innerHTML = noData(); return; }
    const one = (title, rows, nm) => `<h4>${esc(title)}</h4>` + (rows.length ? table(`<th>${esc(T('account'))}</th><th class="n">${esc(T('inBooks'))}</th><th class="n">${esc(T('existing'))}</th><th class="n">${esc(T('unexpl'))}</th>`,
      rows.map((x) => `<tr><td>${esc(x.name || x.party_id)}</td>${amtCell(x.journal)}${amtCell(x.existing)}${amtCell(x.unexplained)}</tr>`).join('')) : `<p class="ac-ok">${esc(T('recoOk'))}</p>`);
    out.innerHTML = one(T('custs'), r.customers || []) + one(T('sups'), r.suppliers || []) + (Number(r.unattributed_receivable) ? `<p>${esc(T('unattr'))}: ${esc(fm(r.unattributed_receivable))}</p>` : '') + `<div class="ac-note">${esc(T('recoNote'))}</div>`;
  } catch (e) { out.innerHTML = `<div class="ac-warn">${esc(eText(e))}</div>`; }
  // phase 72: stock vs books ("মিলানো"), read only
  try { out.insertAdjacentHTML('beforeend', invHtml(await rpc('inventory_vs_gl', { p_date: D.asof || today(), p_loc: locP() }))); }
  catch (e) { out.insertAdjacentHTML('beforeend', `<h4>${esc(T('invH'))}</h4><div class="ac-note">${esc(eText(e))}</div>`); }
}
function invHtml(iv) {
  if (!iv || iv.data_needed) return '';
  let h = `<hr><h4>${esc(T('invH'))}</h4><p class="muted">${esc(T('invNote'))}</p>`;
  if (iv.valuation_basis === 'ledger_replay') h += `<div class="ac-note">${esc(T('invReplay'))}</div>`;
  (iv.rows || []).forEach((r) => {
    const rs = (r.reasons || []).map((x) => `<tr><td class="ac-ind1">${esc(X['rs_' + x.code] ? T('rs_' + x.code) : x.code)}</td>${amtCell(x.amount)}</tr>`).join('');
    const un = Number(r.unexplained) ? `<tr><td class="ac-ind1">${esc(T('invUnexpl'))}</td>${amtCell(r.unexplained)}</tr>` : '';
    h += table(`<th>${esc(T('invT_' + r.key))} · ${esc(r.code)}</th><th class="n"></th>`,
      `<tr><td>${esc(T('invGl'))}</td>${amtCell(r.gl)}</tr><tr><td>${esc(T('invVal'))}</td>${amtCell(r.valuation)}</tr><tr class="tot"><td>${esc(T('invDiff'))}</td>${amtCell(r.diff)}</tr>${rs}${un}`);
  });
  h += iv.agree ? `<p class="ac-ok">${esc(T('invOk'))}</p>` : '';
  return h;
}
async function tChart() {
  await loadAccounts();
  const rows = D.accounts;
  const body = rows.map((a) => `<tr class="${a.is_group ? 'g' : ''}"><td class="ac-ind${Math.min(3, depth(rows, a))}">${esc(a.code)} · ${esc(an(a))}<div class="ac-id">${esc(T(a.type === 'liability' ? 'liability' : a.type === 'equity' ? 'eq' : a.type === 'income' ? 'inc' : a.type === 'expense' ? 'exp' : 'asset'))} · ${esc(a.normal_side === 'debit' ? T('dr') : T('cr'))}${a.is_group ? ' · ' + esc(T('hdr')) : ''}${a.is_system ? ' · ' + esc(T('sys')) : ''}${a.active ? '' : ' · ' + esc(T('retired'))}</div></td>
    <td class="n">${isMgr() && !a.is_group ? `<button class="mini" data-act="ac_edit" data-v="${a.id}" aria-label="${esc(T('rename'))}">⋮</button>` : ''}</td></tr>`).join('');
  setCsv('chart-of-accounts.csv', [['code', 'name_bn', 'name_en', 'type', 'side', 'header', 'active'], ...rows.map((a) => [a.code, a.name_bn, a.name_en, a.type, a.normal_side, a.is_group, a.active])]);
  return (isMgr() ? `<button class="primary full" data-act="ac_add">${esc(T('add'))}</button>` : '') + `<div id="ac_rep">${repHead(T('t_chart'))}${table(`<th>${esc(T('account'))}</th><th></th>`, body)}</div>` + exportBar();
}
function typeOpts(sel) { return ['asset', 'liability', 'equity', 'income', 'expense'].map((t) => `<option value="${t}" ${t === sel ? 'selected' : ''}>${esc(T(t === 'liability' ? 'liability' : t === 'equity' ? 'eq' : t === 'income' ? 'inc' : t === 'expense' ? 'exp' : 'asset'))}</option>`).join(''); }
function parentOpts(type, sel) { return `<option value="">${esc(T('noParent'))}</option>` + D.accounts.filter((a) => a.is_group && a.active && a.type === type).map((a) => `<option value="${a.id}" ${String(a.id) === String(sel) ? 'selected' : ''}>${esc(a.code)} · ${esc(an(a))}</option>`).join(''); }

// manual journal
function newLine() { return { acc: '', dr: '', cr: '', pt: '', pid: '', mob: '', memo: '' }; }
function lineHtml(l, i) {
  return `<div class="ac-line" data-i="${i}"><div class="muted">${esc(T('line'))} ${i + 1}</div>
    <label for="ac_l${i}_a">${esc(T('account'))}</label><select id="ac_l${i}_a" data-li="${i}" data-k="acc"><option value="">${esc(T('pickAcc'))}</option>${accOpts(l.acc, true, true)}</select>
    <div class="row2"><div><label for="ac_l${i}_d">${esc(T('debit'))}</label><input id="ac_l${i}_d" data-li="${i}" data-k="dr" inputmode="decimal" autocomplete="off" value="${esc(l.dr)}"></div>
    <div><label for="ac_l${i}_c">${esc(T('credit'))}</label><input id="ac_l${i}_c" data-li="${i}" data-k="cr" inputmode="decimal" autocomplete="off" value="${esc(l.cr)}"></div></div>
    <div class="row2"><div><label for="ac_l${i}_t">${esc(T('party'))}</label><select id="ac_l${i}_t" data-li="${i}" data-k="pt"><option value="">${esc(T('ptNone'))}</option><option value="customer" ${l.pt === 'customer' ? 'selected' : ''}>${esc(T('ptCust'))}</option><option value="supplier" ${l.pt === 'supplier' ? 'selected' : ''}>${esc(T('ptSup'))}</option><option value="staff" ${l.pt === 'staff' ? 'selected' : ''}>${esc(T('ptStaff'))}</option><option value="partner" ${l.pt === 'partner' ? 'selected' : ''}>${esc(T('ptPart'))}</option></select></div>
    <div>${partyInput(l, i, 'ac_l')}</div></div></div>`;
}
function partyInput(l, i, pre) {
  if (l.pt === 'supplier') return `<label for="${pre}${i}_p">${esc(T('ptSup'))}</label><select id="${pre}${i}_p" data-li="${i}" data-k="pid"><option value=""></option>${(D.sups || []).map((s) => `<option value="${esc(s.id)}" ${s.id === l.pid ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select>`;
  if (l.pt === 'customer') return `<label for="${pre}${i}_p">${esc(T('custMob'))}</label><input id="${pre}${i}_p" data-li="${i}" data-k="mob" inputmode="tel" autocomplete="off" value="${esc(l.mob)}">`;
  if (l.pt === 'staff' || l.pt === 'partner') return `<label for="${pre}${i}_p">${esc(T('staffId'))}</label><input id="${pre}${i}_p" data-li="${i}" data-k="pid" autocomplete="off" value="${esc(l.pid)}">`;
  return '';
}
function totals() {
  let d = 0, c = 0; for (const l of D.lines) { d += nnum(l.dr) || 0; c += nnum(l.cr) || 0; }
  return { d: r2(d), c: r2(c), diff: r2(d - c) };
}
function showTotals() { const t = totals(), el = $('#ac_tot'); if (el) { el.textContent = `${T('dr')} ${fm(t.d)} · ${T('cr')} ${fm(t.c)} · ${T('diff')} ${fm(t.diff)}`; el.className = t.diff === 0 && t.d > 0 ? 'ac-ok' : 'ac-neg'; } }
async function custIdByMobile(m) {
  const mob = norm(m); if (!mob) return null;
  const r = await sb.from('customers').select('id').eq('mobile', mob).limit(1);
  return r.data && r.data[0] ? r.data[0].id : false;
}
async function collectLines(lines, withLoc) {
  const out = [];
  for (const l of lines) {
    if (!l.acc && !(nnum(l.dr) || nnum(l.cr))) continue;
    if (!l.acc) throw new Error('unknown_account');
    const d = nnum(l.dr), c = nnum(l.cr);
    if (Number.isNaN(d) || Number.isNaN(c)) throw new Error('bad_amount');
    const o = { account_id: Number(l.acc), debit: r2(d || 0), credit: r2(c || 0) };
    if (l.pt) {
      o.party_type = l.pt;
      if (l.pt === 'customer') { const id = await custIdByMobile(l.mob); if (!id) throw new Error('party_id_required'); o.party_id = id; } else { if (!l.pid) throw new Error('party_id_required'); o.party_id = l.pid; }
    }
    out.push(o);
  }
  return out;
}
async function tNew() {
  if (!D.accounts.length) await loadAccounts();
  if (D.sups === null) { const r = await sb.from('suppliers').select('id,name').order('name'); D.sups = r.data || []; }
  if (!isMgr()) return `<p class="muted">${esc(T('noacc'))}</p>`;
  if (D.reasons === undefined) { try { D.reasons = (await rpc('manual_reasons85')).filter((x) => x.active); } catch (e) { D.reasons = []; } }   // bos85: reason codes for the manual-journal guard (empty when phase85 is not pasted)
  if (!D.lines.length) D.lines = [newLine(), newLine()];
  const ls = locs();
  return `<div class="card stack"><h3>${esc(T('nj'))}</h3>
    <div><label for="ac_jdate">${esc(T('date'))}</label><input id="ac_jdate" type="date" value="${esc(D.jdate || today())}"></div>
    <div><label for="ac_jloc">${esc(T('place'))}</label><select id="ac_jloc"><option value="">${esc(T('company'))}</option>${ls.map((l) => `<option value="${l.id}" ${String(l.id) === String(D.jloc || '') ? 'selected' : ''}>${esc(locName(l.id))}</option>`).join('')}</select></div>
    <div><label for="ac_jmemo">${esc(T('jmemo'))}</label><input id="ac_jmemo" autocomplete="off" value="${esc(D.jmemo || '')}"></div>
    ${D.reasons && D.reasons.length ? `<div><label for="ac_jreason">${esc(T('jreason'))}</label><select id="ac_jreason"><option value="">—</option>${D.reasons.map((x) => `<option value="${esc(x.code)}">${esc(lab(L(x.label_bn, x.label_en, x.label_mix || x.label_bn)))}</option>`).join('')}</select></div>` : ''}
    <div id="ac_lines">${D.lines.map(lineHtml).join('')}</div>
    <button class="full" data-act="ac_addline">${esc(T('addLine'))}</button>
    <div id="ac_tot" role="status"></div>
    <div><label>${esc(T('photo'))}</label><div class="s2-ph" id="ac_ph">${D.jphoto ? '📎 ' + esc(D.jphoto) : ''}</div><label class="phadd">📷 ${esc(T('photo'))}<input type="file" accept="image/*" hidden id="ac_file"></label></div>
    <div class="row"><button class="full" data-act="ac_jdry">${esc(T('check'))}</button><button class="full primary" data-act="ac_jsave">${esc(T('save'))}</button></div><div id="ac_jout" class="muted"></div></div>`;
}
// opening wizard
const OPEN_PARTY = { '1210': 'customer', '2100': 'supplier', '2300': 'customer' };
async function tOpening() {
  if (!D.accounts.length) await loadAccounts();
  if (D.sups === null) { const r = await sb.from('suppliers').select('id,name').order('name'); D.sups = r.data || []; }
  if (D.st && D.st.opening) return `<div class="card"><p>${esc(T('opDone'))}</p></div>`;
  if (!D.st || !D.st.start) return noData();
  if (!isMgr()) return `<p class="muted">${esc(T('noacc'))}</p>`;
  const rows = D.accounts.filter((a) => !a.is_group && a.active && ['asset', 'liability', 'equity'].includes(a.type));
  const O = D.op.rows;
  const line = (a) => {
    const pt = OPEN_PARTY[a.code], parts = (O[a.id] && O[a.id].parts) || [];
    return `<div class="ac-line"><div><b>${esc(a.code)} · ${esc(an(a))}</b> <span class="ac-id">${esc(a.normal_side === 'debit' ? T('dr') : T('cr'))}</span></div>
      <label for="ac_o${a.id}">${esc(T('amount'))}</label><input id="ac_o${a.id}" data-oa="${a.id}" inputmode="decimal" autocomplete="off" ${parts.length ? 'disabled' : ''} value="${esc(parts.length ? fm(parts.reduce((s, p) => s + (nnum(p.amt) || 0), 0)) : ((O[a.id] && O[a.id].amt) || ''))}">
      ${pt ? `<button class="mini" data-act="ac_opparty" data-v="${a.id}">${esc(T('addParty'))}</button>` + parts.map((p, i) => `<div class="row2" style="display:grid;grid-template-columns:1fr 1fr;gap:8px">${pt === 'supplier'
        ? `<select data-op="${a.id}" data-i="${i}" data-k="pid" aria-label="${esc(T('ptSup'))}"><option value=""></option>${D.sups.map((s) => `<option value="${esc(s.id)}" ${s.id === p.pid ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select>`
        : `<input data-op="${a.id}" data-i="${i}" data-k="mob" inputmode="tel" placeholder="${esc(T('custMob'))}" aria-label="${esc(T('custMob'))}" value="${esc(p.mob || '')}">`}<input data-op="${a.id}" data-i="${i}" data-k="amt" inputmode="decimal" aria-label="${esc(T('amount'))}" value="${esc(p.amt || '')}"></div>`).join('') : ''}</div>`;
  };
  return `<div class="card stack"><div class="ac-note">${esc(T('opH'))}</div><div>${esc(T('start'))}: <b>${esc(D.st.start)}</b></div>${rows.map(line).join('')}
    <div id="ac_optot" role="status"></div><label class="row"><input type="checkbox" id="ac_plug" ${D.op.plug ? 'checked' : ''}> ${esc(T('plug'))}</label>
    <div class="row"><button class="full" data-act="ac_opdry">${esc(T('check'))}</button><button class="full primary" data-act="ac_opsave">${esc(T('save'))}</button></div><div id="ac_opout" class="muted"></div></div>`;
}
async function opLines() {
  const out = [];
  for (const a of D.accounts) {
    const e = D.op.rows[a.id]; if (!e) continue;
    const parts = e.parts || [];
    const add = async (amt, party) => {
      const v = nnum(amt); if (Number.isNaN(v)) throw new Error('bad_amount'); if (!v) return;
      const dr = (a.normal_side === 'debit') === (v > 0), o = { account_id: a.id, debit: dr ? r2(Math.abs(v)) : 0, credit: dr ? 0 : r2(Math.abs(v)) };
      if (party) Object.assign(o, party); out.push(o);
    };
    if (parts.length) {
      const pt = OPEN_PARTY[a.code];
      for (const p of parts) {
        let id = p.pid; if (pt === 'customer') { id = await custIdByMobile(p.mob); if (!id && (nnum(p.amt) || 0)) throw new Error('party_id_required'); }
        if (!(nnum(p.amt) || 0)) continue; if (!id) throw new Error('party_id_required');
        await add(p.amt, { party_type: pt, party_id: id });
      }
    } else await add(e.amt);
  }
  return out;
}
async function opTotals() {
  let d = 0, c = 0;
  for (const a of D.accounts) { const e = D.op.rows[a.id]; if (!e) continue; const vals = (e.parts && e.parts.length) ? e.parts.map((p) => nnum(p.amt) || 0) : [nnum(e.amt) || 0];
    for (const v of vals) { const dr = (a.normal_side === 'debit') === (v > 0); if (dr) d += Math.abs(v); else c += Math.abs(v); } }
  const el = $('#ac_optot'); if (el) { el.textContent = `${T('dr')} ${fm(r2(d))} · ${T('cr')} ${fm(r2(c))} · ${T('diff')} ${fm(r2(d - c))}`; el.className = r2(d - c) === 0 ? 'ac-ok' : 'ac-neg'; }
}
async function tSettings() {
  await loadAccounts(); await loadMaps();
  const st = D.st;
  const sw = (key, on, label) => `<div class="row between"><span>${esc(label)}</span>${isOwner() ? `<button class="tog ${on ? 'on' : ''}" data-act="ac_sw" data-v="${key}" data-on="${on ? 1 : 0}">${esc(on ? T('on') : T('offT'))}</button>` : `<b>${esc(on ? T('on') : T('offT'))}</b>`}</div>`;
  const leaf = D.accounts.filter((a) => !a.is_group && a.active);
  return `<div class="card stack">${sw('accounting_on', st.on, T('swOn'))}${sw('accounting_autopost', st.autopost, T('swAuto'))}
    <div><label>${esc(T('start'))}</label><div><b>${esc(st.start || T('need'))}</b></div>${isOwner() ? startForm() : `<div class="muted">${esc(T('ownerOnly'))}</div>`}</div></div>
    <div class="card stack"><h3>${esc(T('mapH'))}</h3><div class="ac-note">${esc(T('mapNote'))}</div>${D.maps.map((m) => `<div><label for="ac_m_${esc(m.key)}">${esc(lab(L(m.label_bn || m.key, m.label_en || m.key, m.label_bn || m.key)))} <span class="ac-id">${esc(m.key)}</span></label>
      <select id="ac_m_${esc(m.key)}" data-mk="${esc(m.key)}" ${isMgr() ? '' : 'disabled'}>${leaf.map((a) => `<option value="${a.id}" ${a.id === m.account_id ? 'selected' : ''}>${esc(a.code)} · ${esc(an(a))}</option>`).join('')}</select></div>`).join('')}</div>`;
}

const RENDER = { overview: tOverview, bs: tBs, pl: tPl, cf: tCf, tb: tTb, ledger: tLedger, journal: tJournal, parties: tParties, chart: tChart, new: tNew, opening: tOpening, settings: tSettings };
const needsBar = (tab) => !['chart', 'new', 'opening', 'settings'].includes(tab);
// phase 72: one line at the top: last post, pending, errors (+ a banner with a way to the Post now panel when something failed to post)
function strip() {
  const st = D.st; if (!st || !st.start) return '';
  const lp = st.last_post_at || st.last_post;
  const when = lp ? new Date(lp).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }) : T('never');
  const pend = Number(st.pending) || 0, errs = Math.max(Number(st.errors) || 0, Number(D.autoErr) || 0), held = Number(st.locked) || 0;
  let h = `<div class="${errs > 0 ? 'ac-warn' : 'ac-note'}" role="status" id="ac_strip">${esc(T('lastPost'))}: ${esc(when)} · ${esc(T('pending'))} ${pend} · ${esc(T('errN'))} ${errs}${held ? ' · ' + esc(T('heldN')) + ' ' + held : ''}</div>`;
  if (D.hint) h += `<div class="ac-warn" role="alert" id="ac_hint">${esc(D.hint)}</div>`;
  if (errs > 0) {
    h += `<div class="ac-warn" role="alert" id="ac_failbanner"><b>${errs} ${esc(T('failN'))}</b>${(st.error_list || []).slice(0, 3).map((e) => `<div class="ac-id">${esc(sl(e.source_type))} ${esc(String(e.source_id).slice(0, 8))}: ${esc(e.error)}</div>`).join('')}`
      + `${isMgr() ? `<button class="full" data-act="ac_post">${esc(T('openPost'))}</button>` : ''}</div>`;
  }
  return h;
}
async function draw() {
  const body = $('#ac_body'); if (!body) return;
  const tabSel = `<div><label for="ac_tab">${esc(T('title'))}</label><select id="ac_tab">${TABS.map((t) => `<option value="${t}" ${t === D.tab ? 'selected' : ''}>${esc(T('t_' + t))}</option>`).join('')}</select></div>`;
  body.innerHTML = strip() + tabSel + '<div id="ac_main"><p class="muted">' + esc(T('loading')) + '</p></div>';
  const main = $('#ac_main');
  try {
    const html = await RENDER[D.tab]();
    if ($('#ac_tab') && $('#ac_tab').value !== D.tab) return;
    main.innerHTML = html;
    if (D.tab === 'new') showTotals();
    if (D.tab === 'opening') opTotals();
  } catch (e) { main.innerHTML = `<div class="ac-warn" role="alert">${esc(eText(e))}</div>`; }
}
async function autopost() {
  if (!(D.st && D.st.can_manage && D.st.on && D.st.autopost && D.st.start)) return;
  D.hint = '';
  try {
    let posted = 0, rev = 0, more = true, n = 0, errs = 0;
    while (more && n < 5) { const r = await rpc('acct_post_pending', { p_dry: false }); posted += r.posted || 0; rev += r.reversed || 0; errs = (r.errors || []).length; more = !!r.more && ((r.posted || 0) + (r.reversed || 0)) > 0; n++; }
    D.autoErr = errs;   // phase 72: failed postings are no longer swallowed; the strip shows them with a link to the Post now panel
    if (posted + rev > 0) toast(T('posted') + ': ' + posted + (rev ? ' + ' + rev : ''));
    if (errs > 0) toast(errs + ' ' + T('failN'));
  } catch (e) { D.hint = eText(e); }
}
async function view() {
  if (B.loadStatic) await B.loadStatic();
  shell(T('title'), `<div id="ac_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  const t0 = today();
  try {
    D.st = await rpc('acct_status');
  } catch (e) { const b = $('#ac_body'); if (b) b.innerHTML = `<div class="card"><p>${esc(/not allowed/.test(String(e && e.message)) ? T('noacc') : eText(e))}</p></div>`; return; }
  const st = D.st.start;
  D.to = t0; D.asof = t0; D.from = st && st > monthStart() ? st : monthStart(); if (D.from > D.to) D.from = D.to;
  if (!D.loaded) { D.loaded = true; }
  await autopost();
  try { D.st = await rpc('acct_status'); } catch (e) { /* keep the first answer */ }
  await draw();
}

// ---------- actions ----------
async function postNow() {
  try {
    const r = await rpc('acct_post_pending', { p_dry: true });
    if (r.data_needed) { toast(T('need')); return; }
    const types = Object.entries(r.by_type || {}).map(([k, v]) => `<tr><td>${esc(k.endsWith('_reversed') ? sl(k.replace('_reversed', '')) + ' ↺' : sl(k))}</td><td class="n">${v}</td></tr>`).join('');
    const total = (r.posted || 0) + (r.reversed || 0);
    const wait = Object.entries(r.waiting || {}).map(([k, v]) => `${esc(k)}: ${v}`).join(', ');
    let h = `<h3>${esc(T('dryTitle'))}</h3>`;
    if (!total) h += `<p>${esc(T('nothing'))}</p>`;
    else h += `<p>${esc(T('willPost'))}: <b>${r.posted}</b> · ${esc(T('willRev'))}: <b>${r.reversed}</b></p>${table('<th></th><th class="n"></th>', types)}`;
    if (r.locked) h += `<p class="ac-note">${esc(T('locked'))}: ${r.locked}</p>`;
    if (wait) h += `<p class="ac-note">${esc(T('waitingCost'))}: ${wait}</p>`;
    if (r.cogs_missing) h += `<p class="ac-note">${r.cogs_missing} ${esc(T('cogsM'))}</p>`;
    if ((r.errors || []).length) h += `<div class="ac-warn"><b>${esc(T('errs'))}: ${r.errors.length}</b>${r.errors.slice(0, 5).map((e) => `<div class="ac-id">${esc(e.source_type)} ${esc(String(e.source_id).slice(0, 8))}: ${esc(e.error)}</div>`).join('')}</div>`;
    if (total) {
      h += `<h4>${esc(T('trialNet'))}</h4>` + table(`<th>${esc(T('account'))}</th><th class="n">${esc(T('dr'))}</th><th class="n">${esc(T('cr'))}</th>`,
        (r.trial || []).map((x) => `<tr><td>${esc(x.code)} · ${esc(S.lang === 'en' ? x.name_en : x.name_bn)}</td>${amtCell(x.debit)}${amtCell(x.credit)}</tr>`).join('') + `<tr class="tot"><td>${esc(T('totals'))}</td>${amtCell(r.total_debit)}${amtCell(r.total_credit)}</tr>`);
      h += `<details data-ctl="off"><summary>${esc(T('preview'))}</summary>${(r.preview || []).map((e) => `<div class="ac-lr"><div class="r1"><span>${esc(e.date)} · ${esc(e.memo)}</span></div><div class="sub">${esc(sl(e.source_type))}</div>${(e.lines || []).map((l) => `<div class="r2"><span>${esc(l.code)}</span><span>${l.debit > 0 ? esc(fm(l.debit)) : ''}</span><span>${l.credit > 0 ? esc(fm(l.credit)) : ''}</span></div>`).join('')}</div>`).join('')}</details>`;
      h += D.st.on ? `<button class="primary full" data-act="ac_postgo">${esc(T('confirmPost'))}</button>` : `<div class="ac-note">${esc(T('off'))}</div>`;
    }
    openSheet(h);
  } catch (e) { toast(eText(e)); }
}
async function postGo() {
  try {
    const r = await rpc('acct_post_pending', { p_dry: false });
    D.autoErr = (r.errors || []).length; closeSheet(); toast(T('posted') + ': ' + (r.posted || 0) + (r.reversed ? ' + ' + r.reversed : '') + (r.more ? ' · ' + T('more') : ''));
    D.st = await rpc('acct_status'); await draw();
  } catch (e) { toast(eText(e)); }
}
function printNow() {
  const src = $('#ac_rep'); if (!src) return;
  const old = $('#ac_print'); if (old) old.remove();
  const d = document.createElement('div'); d.id = 'ac_print'; d.innerHTML = `<h2>${esc(T('title'))}</h2>` + src.innerHTML; document.body.appendChild(d);
  const clean = () => { const e = $('#ac_print'); if (e) e.remove(); window.removeEventListener('afterprint', clean); };
  window.addEventListener('afterprint', clean);
  setTimeout(() => { try { window.print(); } catch (e) { clean(); } }, 80);
}
function csvNow() {
  if (!D.csv) return toast(T('none'));
  download(D.csv.name, D.csv.rows.map((r) => r.map(q).join(',')).join('\n'));
}
async function jSubmit(dry) {
  try {
    const lines = await collectLines(D.lines);
    D.jdate = ($('#ac_jdate') || {}).value; D.jloc = ($('#ac_jloc') || {}).value; D.jmemo = (($('#ac_jmemo') || {}).value || '').trim();
    const t = totals();
    if (t.diff !== 0) return toast(lab(ERR.unbalanced) + ' (' + fm(t.d) + ' / ' + fm(t.c) + ')');
    const r = await rpc('acct_journal_post', { p_date: D.jdate, p_loc: D.jloc ? Number(D.jloc) : null, p_memo: D.jmemo, p_lines: lines, p_client: dry ? null : D.client, p_photo: D.jphoto || null, p_dry: !!dry, ...(($('#ac_jreason') || {}).value ? { p_reason: $('#ac_jreason').value } : {}) });
    if (dry) { $('#ac_jout').textContent = T('dryOk') + ` (${fm(r.total_debit)} = ${fm(r.total_credit)})`; return; }
    toast(T('saved')); D.client = rid(); D.lines = []; D.jmemo = ''; D.jphoto = ''; D.tab = 'journal'; D.st = await rpc('acct_status'); await draw();
  } catch (e) { toast(eText(e)); }
}
async function opSubmit(dry) {
  try {
    const lines = await opLines(); if (!lines.length) return toast(T('none'));
    D.op.plug = !!($('#ac_plug') || {}).checked;
    const r = await rpc('acct_opening', { p_lines: lines, p_plug: D.op.plug, p_memo: null, p_client: dry ? null : D.client, p_dry: !!dry });
    if (dry) { $('#ac_opout').textContent = T('dryOk') + ` (${fm(r.total_debit)} = ${fm(r.total_credit)}${Number(r.plug) ? ' · ' + T('diff') + ' ' + fm(r.plug) : ''})`; return; }
    toast(T('saved')); D.client = rid(); D.st = await rpc('acct_status'); await draw();
  } catch (e) { toast(eText(e)); }
}

Object.assign(H, {
  ac_setstart: async () => { try { await rpc('acct_set_start', { p_date: ($('#ac_start') || {}).value }); toast(T('saved')); D.st = await rpc('acct_status'); const t0 = today(); D.from = D.st.start && D.st.start > monthStart() ? D.st.start : monthStart(); if (D.from > t0) D.from = t0; await draw(); } catch (e) { toast(eText(e)); } },
  ac_post: () => postNow(), ac_postgo: () => postGo(), ac_print: () => printNow(), ac_csv: () => csvNow(),
  ac_morej: async () => { D.jlimit += 100; await draw(); },
  ac_rev: async (a) => { const n = window.prompt(T('why')); if (!n || n.trim().length < 3) return;
    try { await rpc('acct_journal_reverse', { p_id: Number(a.dataset.v), p_note: n.trim(), p_client: rid() }); toast(T('reversed')); D.st = await rpc('acct_status'); await draw(); } catch (e) { toast(eText(e)); } },
  ac_addline: () => { D.lines.push(newLine()); const el = $('#ac_lines'); if (el) el.innerHTML = D.lines.map(lineHtml).join(''); showTotals(); },
  ac_jdry: () => jSubmit(true), ac_jsave: () => jSubmit(false),
  ac_opparty: (a) => { const id = a.dataset.v; const e = D.op.rows[id] = D.op.rows[id] || {}; e.parts = e.parts || []; e.parts.push({ pid: '', mob: '', amt: '' }); draw(); },
  ac_opdry: () => opSubmit(true), ac_opsave: () => opSubmit(false),
  ac_pshow: async () => {
    const P = D.party;
    if (P.type === 'customer') { const m = ($('#ac_pmob') || {}).value; P.mobile = m; const id = await custIdByMobile(m); if (!id) { P.id = ''; toast(T('custMob')); return draw(); } P.id = id; }
    await draw();
  },
  ac_reco: () => reco(),
  ac_add: () => {
    const first = D.accounts[0] ? 'asset' : 'asset';
    openSheet(`<h3>${esc(T('add'))}</h3><div class="stack"><div><label for="ac_nc">${esc(T('ccode'))}</label><input id="ac_nc" autocomplete="off" maxlength="12"></div>
      <div><label for="ac_nbn">${esc(T('nbn'))}</label><input id="ac_nbn" autocomplete="off"></div><div><label for="ac_nen">${esc(T('nen'))}</label><input id="ac_nen" autocomplete="off"></div>
      <div><label for="ac_nt">${esc(T('ctype'))}</label><select id="ac_nt">${typeOpts(first)}</select></div><div><label for="ac_np">${esc(T('parent'))}</label><select id="ac_np">${parentOpts(first, '')}</select></div>
      <label class="row"><input type="checkbox" id="ac_ncontra"> ${esc(T('contra'))}</label><button class="primary full" data-act="ac_addgo">${esc(T('save'))}</button></div>`);
  },
  ac_addgo: async () => {
    try {
      await rpc('acct_account_save', { p_id: null, p_code: ($('#ac_nc').value || '').trim(), p_name_bn: $('#ac_nbn').value, p_name_en: $('#ac_nen').value, p_type: $('#ac_nt').value, p_parent: $('#ac_np').value ? Number($('#ac_np').value) : null, p_active: true, p_sort: null, p_contra: $('#ac_ncontra').checked });
      closeSheet(); toast(T('saved')); await draw();
    } catch (e) { toast(eText(e)); }
  },
  ac_edit: (a) => {
    const x = D.accounts.find((r) => String(r.id) === a.dataset.v); if (!x) return;
    openSheet(`<h3>${esc(x.code)}</h3><div class="stack"><div><label for="ac_ebn">${esc(T('nbn'))}</label><input id="ac_ebn" autocomplete="off" value="${esc(x.name_bn)}"></div><div><label for="ac_een">${esc(T('nen'))}</label><input id="ac_een" autocomplete="off" value="${esc(x.name_en)}"></div>
      <div><label for="ac_ep">${esc(T('parent'))}</label><select id="ac_ep">${parentOpts(x.type, x.parent_id)}</select></div>
      <button class="primary full" data-act="ac_editgo" data-v="${x.id}" data-on="${x.active ? 1 : 0}">${esc(T('rename'))}</button>
      <button class="full" data-act="ac_retire" data-v="${x.id}" data-on="${x.active ? 0 : 1}">${esc(x.active ? T('retire') : T('reopen'))}</button></div>`);
  },
  ac_editgo: async (a) => { try { await rpc('acct_account_save', { p_id: Number(a.dataset.v), p_code: null, p_name_bn: $('#ac_ebn').value, p_name_en: $('#ac_een').value, p_type: null, p_parent: $('#ac_ep').value ? Number($('#ac_ep').value) : null, p_active: a.dataset.on === '1', p_sort: null }); closeSheet(); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); } },
  ac_retire: async (a) => { try { const x = D.accounts.find((r) => String(r.id) === a.dataset.v); await rpc('acct_account_save', { p_id: Number(a.dataset.v), p_code: null, p_name_bn: x.name_bn, p_name_en: x.name_en, p_type: null, p_parent: null, p_active: a.dataset.on === '1', p_sort: null }); closeSheet(); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); } },
  ac_sw: async (a) => { try { await rpc('set_rule', { p_key: a.dataset.v, p_value: a.dataset.on !== '1' }); D.st = await rpc('acct_status'); toast(T('saved')); await draw(); } catch (e) { toast(eText(e)); } },
});
document.addEventListener('change', async (e) => {
  const t = e.target; if (!t || !t.id && !t.dataset) return;
  if (t.id === 'ac_tab') { D.tab = t.value; return draw(); }
  if (t.id === 'ac_loc') { D.loc = t.value; return draw(); }
  if (t.id === 'ac_from') { D.from = t.value || D.from; return draw(); }
  if (t.id === 'ac_to') { D.to = t.value || D.to; return draw(); }
  if (t.id === 'ac_asof') { D.asof = t.value || D.asof; return draw(); }
  if (t.id === 'ac_acc') { D.accId = t.value; return draw(); }
  if (t.id === 'ac_ptype') { D.party = { type: t.value, id: '', mobile: '' }; return draw(); }
  if (t.id === 'ac_pid') { D.party.id = t.value; return draw(); }
  if (t.id === 'ac_nt') { const p = $('#ac_np'); if (p) p.innerHTML = parentOpts(t.value, ''); return; }
  if (t.dataset && t.dataset.mk) { try { await rpc('acct_mapping_set', { p_key: t.dataset.mk, p_account: Number(t.value) }); toast(T('saved')); } catch (er) { toast(eText(er)); await draw(); } return; }
  if (t.dataset && t.dataset.li !== undefined) { const l = D.lines[Number(t.dataset.li)]; if (l) { l[t.dataset.k] = t.value; if (t.dataset.k === 'pt') { l.pid = ''; l.mob = ''; const box = $('#ac_lines'); if (box) box.innerHTML = D.lines.map(lineHtml).join(''); } showTotals(); } return; }
  if (t.dataset && t.dataset.op !== undefined) { const e2 = D.op.rows[t.dataset.op]; if (e2 && e2.parts[Number(t.dataset.i)]) { e2.parts[Number(t.dataset.i)][t.dataset.k] = t.value; if (t.dataset.k === 'amt') { await draw(); } opTotals(); } return; }
  if (t.id === 'ac_file') {
    const f = t.files && t.files[0]; if (!f) return;
    try { const U = B.s2; if (!U || !U.uploadPhoto) throw new Error('photo'); toast('…'); D.jphoto = await U.uploadPhoto(f, ['ACCOUNTS', 'STOCK', '10-2'], Number(($('#ac_jloc') || {}).value) || ((locs()[0] || {}).id)); const el = $('#ac_ph'); if (el) el.textContent = '📎 ' + D.jphoto; } catch (er) { toast(eText(er)); }
  }
});
document.addEventListener('input', (e) => {
  const t = e.target; if (!t || !t.dataset) return;
  if (t.dataset.li !== undefined && (t.dataset.k === 'dr' || t.dataset.k === 'cr' || t.dataset.k === 'mob')) { const l = D.lines[Number(t.dataset.li)]; if (l) { l[t.dataset.k] = t.value; showTotals(); } }
  if (t.dataset.oa !== undefined) { const a = t.dataset.oa; D.op.rows[a] = D.op.rows[a] || {}; D.op.rows[a].amt = t.value; opTotals(); }
  if (t.dataset.op !== undefined && t.dataset.k !== 'amt') { const e2 = D.op.rows[t.dataset.op]; if (e2 && e2.parts[Number(t.dataset.i)]) e2.parts[Number(t.dataset.i)][t.dataset.k] = t.value; }
  if (t.dataset.op !== undefined && t.dataset.k === 'amt') { const e2 = D.op.rows[t.dataset.op]; if (e2 && e2.parts[Number(t.dataset.i)]) { e2.parts[Number(t.dataset.i)].amt = t.value; opTotals(); } }
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { accounts: view });
})();
