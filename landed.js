/* Islamia BOS · Landed cost (#/landed): freight, duty, insurance, clearing, loading ... added to the item cost, with every allocation option side by side.
   COST-RIGHT HOLDERS ONLY: every number comes from a server call that refuses without the cost right + the landed_entry / landed_approve grant.
   Server: supabase/phase97.sql (landed_info, landed_preview, landed_recommendation, landed_save, landed_approve, landed_post, landed_void, landed_get, landed_list, landed_reminders,
   landed_return_info, landed_skip, landed_supplier_flag_set, landed_logistics_set, landed_charge_type_save).
   Rules: landed_cost_mode (off by default = the item costs exactly its invoice price), landed_alloc_default, landed_late_mode, landed_cost_requires_approval, landed_reminder_on.
   Nothing is guessed: an unknown weight / volume makes that method unavailable and is listed, never invented.
   Routes: #/landed (list + switches), #/landed/new/<bill id>[,<bill id>...] (new), #/landed/<id> (open), #/landed/rem ("Landed cost not added?" list).
   The purchase bill page is not edited: a guarded "Landed costs" button is added to it from here (a MutationObserver that only looks at #/purchase/<id>).
   Handlers are prefixed lc_. Loaded last. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const num = (v) => { const s = norm(v).replace(/,/g, ''); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q = (n, d = 4) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: d }));
const money = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + q(n, 2));
const unit = (n) => (n === null || n === undefined || !Number.isFinite(Number(n)) ? '—' : '৳ ' + q(n, 4));      // a cost per unit keeps up to 4 decimals (13.125, not 13.13)
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const METHODS = ['value', 'qty', 'weight', 'volume', 'manual', 'equal'];
const LATE = ['split_remaining_and_cogs', 'post_to_remaining_stock', 'variance_account'];
const MODES = ['off', 'manual', 'per_bill', 'per_shipment'];

const X = {
  title: L('Landed cost (মালের সাথে আসা খরচ)', 'Landed cost', 'Landed cost (মালের সাথে আসা খরচ)'),
  intro: L('ভাড়া, শুল্ক, বীমা, clearing, মাল তোলা-নামানো ইত্যাদি মালের দামে যোগ করুন। বন্ধ থাকলে মালের দাম = বিলের দাম।', 'Add freight, duty, insurance, clearing, loading and similar charges to the item cost. When it is off, an item costs exactly its invoice price.', 'Freight, duty, insurance, clearing, loading ইত্যাদি item cost-এ যোগ করুন। Off থাকলে item cost = invoice price।'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  noperm: L('অনুমতি নেই — cost দেখার অধিকার আর Landed cost-এর অনুমতি লাগবে', 'Not allowed — the cost right and the landed cost permission are needed', 'অনুমতি নেই — cost right আর landed cost permission লাগবে'),
  noFn: L('এই অংশের ডেটাবেস এখনও চালু হয়নি (phase97 বাকি)', 'The database part for this is not installed yet (phase97 is missing)', 'এই অংশের database এখনও চালু হয়নি (phase97 বাকি)'),
  mode: L('এখনকার পদ্ধতি', 'Current mode', 'এখনকার mode'),
  m_off: L('বন্ধ — মালের দাম = বিলের দাম', 'Off — item cost = invoice price', 'Off — item cost = invoice price'),
  m_manual: L('হাতে — দরকার হলে নিজে যোগ করবেন', 'Manual — you add it when needed', 'Manual — দরকার হলে নিজে যোগ করবেন'),
  m_per_bill: L('প্রতি বিল — প্রতিটি বিলে একটি', 'Per bill — one per bill', 'Per bill — প্রতিটি bill-এ একটি'),
  m_per_shipment: L('প্রতি চালান — একাধিক বিল / GRN মিলিয়ে একটি', 'Per shipment — one for several bills / GRNs', 'Per shipment — একাধিক bill / GRN মিলিয়ে একটি'),
  isOff: L('Landed cost এখন বন্ধ। কোনো বিলের দামে কিছু যোগ হচ্ছে না। মালিক চালু করতে পারেন।', 'Landed cost is off. Nothing is added to any bill price. The owner can turn it on.', 'Landed cost এখন off। কোনো bill-এর দামে কিছু যোগ হচ্ছে না। Owner চালু করতে পারেন।'),
  settings: L('সেটিং (মালিক)', 'Settings (owner)', 'Setting (owner)'), save: L('সংরক্ষণ', 'Save', 'Save'), close: L('বন্ধ', 'Close', 'Close'), saved: L('সংরক্ষণ হয়েছে', 'Saved', 'Saved'),
  allocDef: L('ভাগ করার ডিফল্ট পদ্ধতি', 'Default allocation', 'ভাগ করার default method'), lateDef: L('দেরিতে আসা খরচ (মাল বিক্রি হয়ে গেলে)', 'Late charge (goods already sold)', 'দেরিতে আসা charge (মাল sold হলে)'),
  reqAppr: L('পোস্টের আগে অনুমোদন', 'Approval before posting', 'Post-এর আগে approval'), a_warn: L('সতর্কতা', 'Warn', 'Warn'), a_required: L('বাধ্যতামূলক', 'Required', 'Required'),
  remSw: L('"Landed cost যোগ হয়নি?" তালিকা', '"Landed cost not added?" list', '"Landed cost যোগ হয়নি?" list'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'),
  newCost: L('নতুন landed cost', 'New landed cost', 'নতুন landed cost'), tabList: L('তালিকা', 'List', 'List'), tabRem: L('যোগ হয়নি?', 'Not added?', 'যোগ হয়নি?'),
  pickBills: L('বিল বাছুন', 'Choose bills', 'Bill বাছুন'), pickHint: L('এক বা একাধিক পোস্ট করা ক্রয় বিল (একই জায়গার)', 'One or more posted purchase bills (one place)', 'এক বা একাধিক posted purchase bill (একই জায়গার)'),
  cont: L('এগিয়ে যান', 'Continue', 'এগিয়ে যান'), nBills: L('বিল', 'bills', 'bills'), st_draft: L('খসড়া', 'Draft', 'Draft'), st_approved: L('অনুমোদিত', 'Approved', 'Approved'), st_posted: L('পোস্ট হয়েছে', 'Posted', 'Posted'), st_void: L('বাতিল', 'Void', 'Void'),
  bills: L('বিল / GRN', 'Bills / GRNs', 'Bill / GRN'), ship: L('চালান / lot রেফারেন্স', 'Shipment / lot reference', 'Shipment / lot reference'), ttl: L('নাম', 'Title', 'Title'), cdate: L('তারিখ (হিসাবে)', 'Date (for the books)', 'Date (books-এর জন্য)'),
  shipNeed: L('এই পদ্ধতিতে চালানের রেফারেন্স লাগে', 'This mode needs a shipment reference', 'এই mode-এ shipment reference লাগে'), addBill: L('আরেকটি বিল যোগ', 'Add another bill', 'আরেকটি bill যোগ'), rmBill: L('বাদ', 'Remove', 'Remove'),
  imported: L('সাপ্লায়ারকে "আমদানি" চিহ্নিত করুন', 'Mark the supplier as "imported"', 'Supplier-কে "imported" চিহ্নিত করুন'), flagged: L('চিহ্নিত হয়েছে', 'Marked', 'Marked'),
  charges: L('খরচ (charges)', 'Charges', 'Charges'), addCh: L('+ খরচ যোগ', '+ Add a charge', '+ Charge যোগ'), rmCh: L('মুছুন', 'Remove', 'Remove'), ctype: L('ধরন', 'Type', 'Type'), amount: L('টাকা (ঋণাত্মক = ফেরত)', 'Amount (negative = refund)', 'Amount (negative = refund)'),
  ccy: L('মুদ্রা', 'Currency', 'Currency'), rate: L('রূপান্তর হার', 'Exchange rate', 'Exchange rate'), inBase: L('টাকায়', 'in base currency', 'base currency-তে'), payMode: L('কীভাবে দেওয়া', 'How it is paid', 'How paid'),
  p_payable: L('বাকি (দেনা)', 'On credit (payable)', 'Credit (payable)'), p_cash: L('নগদ', 'Cash', 'Cash'), p_bank: L('ব্যাংক', 'Bank', 'Bank'), p_mobile: L('মোবাইল', 'Mobile wallet', 'Mobile wallet'),
  sup: L('কাকে (সাপ্লায়ার)', 'To whom (supplier)', 'কাকে (supplier)'), noSup: L('— কেউ নয় —', '— none —', '— কেউ নয় —'), chMeth: L('এই খরচের ভাগ', 'Spread this charge by', 'এই charge-এর ভাগ'), hdrMeth: L('সাধারণ পদ্ধতি', 'The common method', 'Common method'),
  t_capitalise: L('মালের দামে যোগ হবে', 'Added to item cost', 'Item cost-এ যোগ হবে'), t_expense_only: L('শুধু খরচ — মালের দামে নয়', 'Expense only — not in item cost', 'শুধু expense — item cost-এ নয়'), t_recoverable_tax: L('ফেরতযোগ্য কর — মালের দামে নয়', 'Recoverable tax — not in item cost', 'Recoverable tax — item cost-এ নয়'),
  method: L('ভাগের পদ্ধতি', 'How to spread', 'ভাগের method'), recommended: L('প্রস্তাবিত', 'Recommended', 'Recommended'), useReco: L('প্রস্তাবিত প্রয়োগ', 'Use the recommendation', 'Recommended প্রয়োগ'),
  me_value: L('দাম', 'Value', 'Value'), me_qty: L('পরিমাণ', 'Quantity', 'Qty'), me_weight: L('ওজন', 'Weight', 'Weight'), me_volume: L('আয়তন', 'Volume', 'Volume'), me_manual: L('হাতে %', 'Manual %', 'Manual %'), me_equal: L('সমান', 'Equal', 'Equal'),
  unavailable: L('এখনো জানা নেই', 'not known yet', 'এখনো জানা নেই'), why_weight_unknown: L('কিছু লাইনের ওজন জানা নেই', 'the weight of some lines is unknown', 'কিছু line-এর weight জানা নেই'), why_volume_unknown: L('কিছু লাইনের আয়তন জানা নেই', 'the volume of some lines is unknown', 'কিছু line-এর volume জানা নেই'),
  why_manual_missing: L('% লিখুন', 'type the %', '% লিখুন'), why_manual_sum: L('% এর যোগফল ১০০ নয়', 'the % do not add to 100', '% এর sum ১০০ নয়'), why_value_zero: L('দাম শূন্য', 'value is zero', 'value শূন্য'), why_qty_zero: L('পরিমাণ শূন্য', 'quantity is zero', 'qty শূন্য'),
  mixedUnits: L('একক আলাদা (কেজি, পিস ...) — পরিমাণ ধরে ভাগ অর্থহীন হতে পারে', 'units differ (kg, pieces ...) — a split by quantity may be meaningless', 'unit আলাদা (kg, pcs ...) — qty ধরে ভাগ অর্থহীন হতে পারে'),
  basis: L('ওজন / আয়তন / % (প্রতি লাইনে মোট)', 'Weight / volume / % (total per line)', 'Weight / volume / % (প্রতি line-এ total)'), basisNote: L('জানা না থাকলে ফাঁকা রাখুন — অনুমান করা হয় না', 'Leave blank if unknown — it is never guessed', 'জানা না থাকলে ফাঁকা রাখুন — অনুমান করা হয় না'),
  kg: L('ওজন (কেজি)', 'Weight (kg)', 'Weight (kg)'), litre: L('আয়তন (লিটার)', 'Volume (litre)', 'Volume (litre)'), pct: L('ভাগ %', 'Share %', 'Share %'), src_line: L('এই লাইনে লেখা', 'typed on this line', 'এই line-এ লেখা'), src_item: L('আইটেমের ওজন', 'from the item', 'item-এর weight'), src_unit: L('এককের থেকে', 'from the unit', 'unit থেকে'), unknownW: L('অজানা', 'unknown', 'অজানা'),
  itemW: L('আইটেমের এক একক ওজন সেট করুন', 'Set the weight of one unit of the item', 'Item-এর এক unit-এর weight সেট করুন'), perUnit: L('এক একক', 'one unit', 'এক unit'),
  preview: L('প্রতি লাইনে নতুন একক দাম — সব পদ্ধতি পাশাপাশি', 'New unit cost per line — every method side by side', 'প্রতি line-এ নতুন unit cost — সব method পাশাপাশি'), now: L('এখন (ছাড়ের পর)', 'Now (after discount)', 'এখন (discount-এর পর)'),
  alloc: L('ভাগ', 'Share', 'Share'), newUnit: L('নতুন একক দাম', 'New unit cost', 'নতুন unit cost'), toStock: L('stock-এ', 'to stock', 'stock-এ'), toVar: L('বিক্রি হয়ে গেছে (variance)', 'already sold (variance)', 'sold (variance)'),
  totals: L('মোট', 'Totals', 'Totals'), tCap: L('মালের দামে যোগ', 'Added to item cost', 'Item cost-এ যোগ'), tExp: L('শুধু খরচ', 'Expense only', 'Expense only'), tTax: L('ফেরতযোগ্য কর', 'Recoverable tax', 'Recoverable tax'),
  stockEff: L('গড় দামের উপর প্রভাব', 'Effect on the average cost', 'Average cost-এর উপর effect'), onHand: L('এখন আছে', 'On hand', 'On hand'), avgNow: L('গড় এখন', 'Average now', 'Average now'), avgAfter: L('গড় পরে', 'Average after', 'Average after'), lateQty: L('আগেই বিক্রি / ব্যবহার', 'already sold / used', 'আগেই sold / used'),
  late: L('দেরিতে আসা খরচ কীভাবে ধরবেন', 'How to treat a late charge', 'Late charge কীভাবে ধরবেন'), l_split: L('ভাগ করে (প্রস্তাবিত)', 'Split (recommended)', 'Split (recommended)'), l_post: L('সব বাকি stock-এ', 'All to remaining stock', 'সব remaining stock-এ'), l_var: L('variance খাতে', 'Variance account', 'Variance account'),
  saveDraft: L('খসড়া সংরক্ষণ', 'Save draft', 'Draft save'), approve: L('অনুমোদন', 'Approve', 'Approve'), post: L('পোস্ট করুন', 'Post', 'Post'), voidIt: L('বাতিল (void)', 'Void', 'Void'), reason: L('কারণ (কমপক্ষে ৩ অক্ষর)', 'Reason (at least 3 letters)', 'Reason (কমপক্ষে ৩ অক্ষর)'),
  posted: L('পোস্ট হয়েছে', 'Posted', 'Posted'), approvedOk: L('অনুমোদিত', 'Approved', 'Approved'), voided: L('বাতিল হয়েছে', 'Voided', 'Voided'), already: L('আগেই হয়ে গেছে', 'Already done', 'আগেই হয়ে গেছে'),
  postedSum: L('পোস্ট হওয়া ফল', 'Result of the posting', 'Posting-এর ফল'), stockAdded: L('stock-এর দামে যোগ', 'added to stock cost', 'stock cost-এ যোগ'), toVariance: L('variance খাতে', 'to the variance account', 'variance account-এ'),
  confirmPost: L('পোস্ট করলে মালের গড় দাম বদলাবে। নিশ্চিত?', 'Posting changes the average cost of the items. Sure?', 'Post করলে item-এর average cost বদলাবে। নিশ্চিত?'),
  remTitle: L('Landed cost যোগ হয়নি?', 'Landed cost not added?', 'Landed cost যোগ হয়নি?'), remOff: L('এই তালিকা বন্ধ। মালিক "চালু" করলে আমদানি / চিহ্নিত সাপ্লায়ারের বিল এখানে আসবে।', 'This list is off. When the owner turns it on, bills of imported or flagged suppliers appear here.', 'এই list off। Owner "on" করলে imported / flagged supplier-এর bill এখানে আসবে।'),
  remNone: L('সব বিলে landed cost আছে বা দরকার নেই ✓', 'Every bill has a landed cost or does not need one ✓', 'সব bill-এ landed cost আছে বা দরকার নেই ✓'), w_supplier_imported: L('আমদানি সাপ্লায়ার', 'imported supplier', 'imported supplier'), w_supplier_extra_charges: L('বাড়তি খরচের সাপ্লায়ার', 'supplier with extra charges', 'extra charge-এর supplier'), w_every_bill: L('প্রতি বিলে দরকার', 'needed on every bill', 'প্রতি bill-এ দরকার'),
  inProgress: L('খসড়া চলছে', 'draft in progress', 'draft চলছে'), skip: L('দরকার নেই', 'Not needed', 'দরকার নেই'), skipWhy: L('কেন দরকার নেই', 'Why it is not needed', 'কেন দরকার নেই'), skipped: L('তালিকা থেকে বাদ', 'Taken off the list', 'List থেকে বাদ'),
  addBtn: L('Landed cost যোগ', 'Add landed costs', 'Landed cost যোগ'), retTitle: L('ফেরতের মালের landed cost', 'Landed cost of returned goods', 'Return-এর মালের landed cost'), retNone: L('এই বিলে কোনো পোস্ট করা landed cost নেই', 'This bill has no posted landed cost', 'এই bill-এ posted landed cost নেই'), retUnit: L('এক কেজি / এককে landed', 'Landed per unit', 'Landed per unit'), retQty: L('ফেরত', 'Returned', 'Returned'),
  ctypeAdd: L('নতুন খরচের ধরন (মালিক)', 'New charge type (owner)', 'নতুন charge type (owner)'), ctCode: L('কোড (ইংরেজি, ছোট হাতের)', 'Code (letters, lower case)', 'Code (English, lower case)'), ctEn: L('ইংরেজি নাম', 'English name', 'English name'), ctBn: L('বাংলা নাম', 'Bangla name', 'Bangla name'),
  ctTreat: L('কীভাবে ধরবেন', 'Treatment', 'Treatment'), openIt: L('খুলুন', 'Open', 'Open'), billNo: L('বিল', 'Bill', 'Bill'), noBills: L('কোনো পোস্ট করা বিল পাওয়া যায়নি', 'No posted bills found', 'কোনো posted bill পাওয়া যায়নি'),
  notBill: L('এটি ক্রয় বিল নয় বা পোস্ট হয়নি', 'This is not a posted purchase bill', 'এটি purchase bill নয় বা post হয়নি'), noStock: L('এই বিলগুলোতে গোনা ও tracked কোনো আইটেম নেই', 'These bills have no counted, tracked item', 'এই bill-এ counted ও tracked কোনো item নেই'),
  needCharge: L('কমপক্ষে একটি খরচ লিখুন', 'Enter at least one charge', 'কমপক্ষে একটি charge লিখুন'), badNum: L('সংখ্যা ঠিক নয়', 'Number is not valid', 'Number ঠিক নয়'), needRate: L('বিদেশি মুদ্রার জন্য হার লিখুন', 'Type the exchange rate for a foreign currency', 'Foreign currency-র জন্য rate লিখুন'),
  readOnly: L('এই landed cost আর বদলানো যায় না', 'This landed cost can no longer be edited', 'এই landed cost আর বদলানো যায় না'), lines: L('লাইন', 'Lines', 'Lines'),
};
const T = (k) => lab(X[k]);
const ERR = {
  landed_off: L('Landed cost বন্ধ — আগে চালু করুন', 'Landed cost is off — switch it on first', 'Landed cost off — আগে চালু করুন'),
  rate_required: X.needRate, no_charges: X.needCharge, bad_charge_type: L('খরচের ধরন ঠিক নয়', 'The charge type is not valid', 'Charge type ঠিক নয়'), bad_amount: X.badNum, bad_rate: X.badNum, bad_currency: L('মুদ্রার কোড ৩ অক্ষরের হতে হবে', 'The currency code must be 3 letters', 'Currency code ৩ অক্ষরের হতে হবে'),
  per_bill_one_bill: L('"প্রতি বিল" পদ্ধতিতে একটি landed cost-এ একটিই বিল', 'In "per bill" mode one landed cost covers one bill', '"Per bill" mode-এ একটি landed cost-এ একটিই bill'), shipment_ref_needed: X.shipNeed,
  grn_not_linked: L('এই GRN কোনো বিলের সাথে জোড়া নয় — আগে বিলের সাথে জুড়ুন', 'This GRN is not linked to a bill — link it first', 'এই GRN কোনো bill-এর সাথে জোড়া নয় — আগে link করুন'), bill_not_found: X.notBill,
  one_place_only: L('একটি landed cost-এ এক জায়গার বিল', 'One landed cost covers bills of one place', 'একটি landed cost-এ এক জায়গার bill'), approval_required: L('আগে অনুমোদন লাগবে', 'It must be approved first', 'আগে approval লাগবে'), approver_must_differ: L('যিনি বানিয়েছেন তিনি নিজে অনুমোদন করতে পারেন না', 'The person who made it cannot approve it', 'যিনি বানিয়েছেন তিনি নিজে approve করতে পারেন না'),
  method_unavailable: L('এই পদ্ধতির সংখ্যা (ওজন / আয়তন / %) এখনো জানা নেই', 'The numbers for this method (weight / volume / %) are not known yet', 'এই method-এর number (weight / volume / %) এখনো জানা নেই'), landed_cost_posted: L('এই বিলের landed cost আগে বাতিল করুন', 'Void the landed cost of this bill first', 'এই bill-এর landed cost আগে void করুন'),
  mapping_missing: L('হিসাবের একটি account মেলানো নেই', 'An account mapping is missing', 'Account mapping নেই'), no_stock_lines: X.noStock, reason_required: L('কারণ লিখুন (কমপক্ষে ৩ অক্ষর)', 'Write a reason (at least 3 letters)', 'Reason লিখুন (কমপক্ষে ৩ অক্ষর)'), not_editable: X.readOnly, landed_locked: X.readOnly,
  landed_void: L('এটি বাতিল হয়ে গেছে', 'It is already void', 'এটি void হয়ে গেছে'), period_closed: L('এই তারিখের হিসাব বন্ধ', 'This date is closed', 'এই date-এর হিসাব বন্ধ'), nothing_to_post: L('পোস্ট করার মতো কিছু নেই', 'Nothing to post', 'Post করার মতো কিছু নেই'),
};
const errMsg = (e) => { const m = (e && e.message) || ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) return toast(lab(ERR[k])); if (/not allowed/.test(m)) return toast(T('noperm')); if (/function .* does not exist|schema cache|Could not find/i.test(m)) return toast(T('noFn')); return fail(e); };
const call = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };
const D = { info: null, cost: null, id: null, status: null, bills: [], billInfo: {}, ref: '', title: '', note: '', date: today(), method: null, late: null, charges: [], basis: {}, pv: null, client: null, busy: false, timer: null, sups: null, pick: [], pickRows: null, can: {}, got: null };
let seq = 0;

// ---------- small bits ----------
const stLabel = (s) => T('st_' + s);
const stCls = (s) => ({ draft: '', approved: 'info', posted: 'ok', void: 'bad' }[s] || '');
const txt = (o) => (o && typeof o === 'object' ? lab({ bn: o.bn, mix: o.mix || o.bn, en: o.en || o.bn }) : String(o ?? ''));
const typeOf = (code) => ((D.info && D.info.charge_types) || []).find((t) => t.code === code) || null;
const typeName = (t) => lab({ bn: t.name_bn, mix: t.name_mix || t.name_bn, en: t.name_en });
const typeHint = (t) => lab({ bn: t.hint_bn || '', mix: t.hint_mix || t.hint_bn || '', en: t.hint_en || '' });
const baseCcy = () => (D.info && D.info.base_currency) || 'BDT';
const methodName = (m) => T('me_' + m);
const need = async () => { if (!D.info) D.info = await call('landed_info'); return D.info; };
async function loadSups() { if (D.sups === null) { const r = await sb.from('suppliers').select('id,name').order('name'); D.sups = (r && r.data) || []; } return D.sups; }

// ---------- list ----------
async function listView() {
  shell(T('title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, 'home');
  let info; try { info = await need(); } catch (e) { shell(T('title'), `<div class="notice bad">${esc(/not allowed/.test(e.message || '') ? T('noperm') : /does not exist|schema cache|Could not find/i.test(e.message || '') ? T('noFn') : e.message || '')}</div>`, 'home'); return; }
  let rows = []; try { rows = await call('landed_list', { p_status: null, p_bill: null, p_limit: 60 }); } catch (e) { rows = []; }
  const own = !!(S.ctx && S.ctx.is_owner);
  shell(T('title'), `<div class="card stack"><div class="muted">${esc(T('intro'))}</div>
    <div class="row between wrap"><span class="chip ${info.mode === 'off' ? 'warn' : 'ok'}" id="lc_modechip">${esc(T('mode'))}: ${esc(T('m_' + info.mode))}</span>${own ? `<button data-act="lc_settings">${esc(T('settings'))}</button>` : ''}</div>
    ${info.mode === 'off' ? `<div class="notice warn">${esc(T('isOff'))}</div>` : ''}</div>
    <div class="row wrap"><button class="primary" data-act="lc_new" ${info.can_entry && info.mode !== 'off' ? '' : 'disabled'}>${esc(T('newCost'))}</button><button data-act="lc_rem">${esc(T('tabRem'))}</button>${own ? `<button data-act="lc_ctype">${esc(T('ctypeAdd'))}</button>` : ''}</div>
    <div class="card" id="lc_list">${(rows || []).length ? rows.map((r) => `<div class="s2-led"><div><b>${esc(r.title || r.shipment_ref || q(r.n_bills, 0) + ' ' + T('nBills'))}</b><div class="sub">${esc(r.cost_date)} · ${esc(money(r.total))} · ${esc(T('me_' + r.alloc_method))}</div></div>
      <div class="row"><span class="chip ${stCls(r.status)}">${esc(stLabel(r.status))}</span><button data-act="lc_open" data-v="${esc(r.id)}">${esc(T('openIt'))}</button></div></div>`).join('') : `<p class="muted center">${esc(T('none'))}</p>`}</div>`, 'home');
}
async function settingsSheet() {
  const info = await need();
  const sel = (id, cur, vals, f) => `<select id="${id}">${vals.map((v) => `<option value="${v}" ${v === cur ? 'selected' : ''}>${esc(f(v))}</option>`).join('')}</select>`;
  openSheet(`<h2>${esc(T('settings'))}</h2><div class="stack">
    <div><label for="lcs_mode">${esc(T('mode'))}</label>${sel('lcs_mode', info.mode, MODES, (v) => T('m_' + v))}</div>
    <div><label for="lcs_alloc">${esc(T('allocDef'))}</label>${sel('lcs_alloc', info.alloc_default, METHODS, methodName)}</div>
    <div><label for="lcs_late">${esc(T('lateDef'))}</label>${sel('lcs_late', info.late_mode, LATE, (v) => T({ split_remaining_and_cogs: 'l_split', post_to_remaining_stock: 'l_post', variance_account: 'l_var' }[v]))}</div>
    <div><label for="lcs_appr">${esc(T('reqAppr'))}</label>${sel('lcs_appr', info.requires_approval, ['warn', 'required'], (v) => T('a_' + v))}</div>
    <div><label for="lcs_rem">${esc(T('remSw'))}</label>${sel('lcs_rem', info.reminder_on ? 'on' : 'off', ['off', 'on'], (v) => T(v))}</div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="lc_settings_go">${esc(T('save'))}</button></div></div>`);
}
async function settingsGo(a) {
  const v = (id) => ($('#' + id) || {}).value;
  const set = async (k, val) => { const r = await sb.rpc('set_rule', { p_key: k, p_value: val }); if (r.error) throw r.error; };
  await set('landed_cost_mode', v('lcs_mode')); await set('landed_alloc_default', v('lcs_alloc')); await set('landed_late_mode', v('lcs_late'));
  await set('landed_cost_requires_approval', v('lcs_appr')); await set('landed_reminder_on', v('lcs_rem') === 'on');
  closeSheet(); D.info = null; toast(T('saved')); await listView();
}

// ---------- pick bills ----------
async function pickSheet(add) {
  D.pick = add ? D.bills.slice() : []; D.pickRows = null; D.pickAdd = !!add;
  openSheet(`<h2>${esc(add ? T('addBill') : T('pickBills'))}</h2><div class="hint">${esc(T('pickHint'))}</div><div id="lc_pk"><p class="muted center pad">${esc(T('loading'))}</p></div><div id="q4_grn"></div>`);   // bos107 q4: GRN picker slot (landed_q4.js fills it)
  try { if (B.landedQ4) B.landedQ4.mount(); } catch (e) { /* the GRN picker is optional */ }   // bos107 q4
  const r = await sb.rpc('purchase_list', { p_loc: null, p_from: null, p_to: null, p_supplier: null, p_status: 'posted', p_limit: 100 });
  D.pickRows = (r.data || []).filter((x) => x.kind === 'bill'); drawPick();
}
function drawPick() {
  const box = $('#lc_pk'); if (!box) return;
  box.innerHTML = (D.pickRows || []).length ? `<div class="stack">${D.pickRows.map((b) => `<label class="row between lc-pk"><span class="row"><input type="checkbox" data-lcpk="${esc(b.id)}" ${D.pick.includes(b.id) ? 'checked' : ''}><span>${esc(b.supplier_name)} · ${esc(b.bill_no || '—')}<span class="hint"> ${esc(b.bill_date)}</span></span></span><b>${esc(money(b.total))}</b></label>`).join('')}</div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="lc_pickgo">${esc(T('cont'))}</button></div>` : `<p class="muted center pad">${esc(T('noBills'))}</p>`;
}

// ---------- editor ----------
function newState(bills) {
  Object.assign(D, { id: null, status: 'draft', cost: null, got: null, bills: bills.slice(), ref: '', title: '', note: '', date: today(), method: null, late: null, charges: [blankCharge()], basis: {}, pv: null, client: rid(), billInfo: D.billInfo, can: {} });
}
const blankCharge = () => ({ type: 'freight', amount: '', ccy: baseCcy(), rate: '', pay: 'payable', sup: '', meth: '' });
async function loadBillInfo(ids) {
  for (const id of ids) {
    if (D.billInfo[id]) continue;
    try { const b = await call('purchase_get', { p_id: id }); D.billInfo[id] = { id, bill_no: b.bill_no, supplier: b.supplier_name, supplier_id: b.supplier_id, total: b.total, date: b.bill_date, kind: b.kind, status: b.status }; } catch (e) { D.billInfo[id] = { id, bill_no: '—', supplier: '—', total: null, kind: null, status: null }; }
  }
}
async function openNew(ids) {
  shell(T('title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, 'landed');
  const info = await need(); await loadSups(); await loadBillInfo(ids);
  const ret = ids.map((i) => D.billInfo[i]).find((b) => b && b.kind === 'return');
  if (ret) return returnView(ret.id);
  if (info.mode === 'off') { shell(T('title'), `<div class="notice warn">${esc(T('isOff'))}</div><button data-act="go" data-v="landed">${esc(T('tabList'))}</button>`, 'landed'); return; }
  newState(ids); D.method = info.alloc_default; D.late = null; D.charges[0].ccy = baseCcy(); draw(); runPreview();
}
async function openCost(id) {
  shell(T('title'), `<p class="muted center pad">${esc(T('loading'))}</p>`, 'landed');
  const info = await need(); await loadSups();
  let g; try { g = await call('landed_get', { p_id: id }); } catch (e) { errMsg(e); shell(T('title'), `<div class="notice bad">${esc(T('noperm'))}</div>`, 'landed'); return; }
  const h = g.header; D.billInfo = D.billInfo || {};
  g.docs.forEach((d) => { D.billInfo[d.bill_id] = { id: d.bill_id, bill_no: d.bill_no, supplier: d.supplier, total: d.total, date: d.bill_date, kind: 'bill', status: 'posted' }; });
  Object.assign(D, { id: h.id, status: h.status, got: g, bills: g.docs.map((d) => d.bill_id), ref: h.shipment_ref || '', title: h.title || '', note: h.note || '', date: h.cost_date, method: h.alloc_method, late: h.late_mode || null, client: rid(), can: g.can, pv: null,
    charges: g.lines.map((l) => ({ type: l.charge_type, amount: String(l.amount_ccy), ccy: l.ccy, rate: l.ccy === baseCcy() ? '' : String(l.rate), pay: l.pay_mode, sup: l.supplier_id || '', meth: l.alloc_method || '' })),
    basis: Object.fromEntries((g.basis || []).map((b) => [b.bill_line_id, { weight: b.weight_kg ?? '', volume: b.volume_l ?? '', pct: b.manual_pct ?? '' }])) });
  draw(); if (h.status === 'draft' || h.status === 'approved') runPreview(); else { D.pv = null; drawPv(); }
}
const editable = () => D.status === 'draft' || D.status === 'approved';
function billsHtml() {
  const own = D.bills.map((id) => D.billInfo[id] || { id, bill_no: '—', supplier: '—' });
  return own.map((b) => `<div class="row between wrap"><span><b>${esc(b.supplier)}</b> · ${esc(b.bill_no || '—')}<span class="hint"> ${esc(b.date || '')} ${b.total != null ? money(b.total) : ''}</span></span>
    <span class="row">${editable() && b.supplier_id ? `<button data-act="lc_flag" data-v="${esc(b.supplier_id)}">${esc(T('imported'))}</button>` : ''}${editable() && D.bills.length > 1 ? `<button data-act="lc_billrm" data-v="${esc(b.id)}">${esc(T('rmBill'))}</button>` : ''}</span></div>`).join('');
}
function chargeHtml(c, i) {
  const t = typeOf(c.type); const types = ((D.info && D.info.charge_types) || []).filter((x) => x.active !== false || x.code === c.type);
  const ro = editable() ? '' : 'disabled';
  const foreign = String(c.ccy || '').toUpperCase() !== baseCcy();
  const sups = D.sups || [];
  return `<div class="lc-ch card" data-i="${i}"><div class="stack">
    <div><label>${esc(T('ctype'))}</label><select data-lc="type" data-i="${i}" ${ro}>${types.map((x) => `<option value="${esc(x.code)}" ${x.code === c.type ? 'selected' : ''}>${esc(typeName(x))}</option>`).join('')}</select>
      <div class="hint" id="lc_th${i}">${t ? esc(T('t_' + t.treatment)) + (typeHint(t) ? ' · ' + esc(typeHint(t)) : '') : ''}</div></div>
    <div class="row wrap"><div style="flex:2;min-width:120px"><label>${esc(T('amount'))}</label><input data-lc="amount" data-i="${i}" inputmode="decimal" autocomplete="off" value="${esc(c.amount)}" ${ro}></div>
      <div style="flex:1;min-width:70px"><label>${esc(T('ccy'))}</label><input data-lc="ccy" data-i="${i}" maxlength="3" autocomplete="off" value="${esc(c.ccy)}" ${ro}></div>
      <div style="flex:1;min-width:90px" data-ratebox="${i}" ${foreign ? '' : 'hidden'}><label>${esc(T('rate'))}</label><input data-lc="rate" data-i="${i}" inputmode="decimal" autocomplete="off" value="${esc(c.rate)}" ${ro}></div></div>
    <div class="row wrap"><div style="flex:1;min-width:130px"><label>${esc(T('payMode'))}</label><select data-lc="pay" data-i="${i}" ${ro}>${['payable', 'cash', 'bank', 'mobile'].map((m) => `<option value="${m}" ${m === c.pay ? 'selected' : ''}>${esc(T('p_' + m))}</option>`).join('')}</select></div>
      <div style="flex:1;min-width:130px" data-supbox="${i}" ${c.pay === 'payable' ? '' : 'hidden'}><label>${esc(T('sup'))}</label><select data-lc="sup" data-i="${i}" ${ro}><option value="">${esc(T('noSup'))}</option>${sups.map((s) => `<option value="${esc(s.id)}" ${s.id === c.sup ? 'selected' : ''}>${esc(s.name)}</option>`).join('')}</select></div>
      <div style="flex:1;min-width:130px"><label>${esc(T('chMeth'))}</label><select data-lc="meth" data-i="${i}" ${ro}><option value="">${esc(T('hdrMeth'))}</option>${METHODS.map((m) => `<option value="${m}" ${m === c.meth ? 'selected' : ''}>${esc(methodName(m))}</option>`).join('')}</select></div></div>
    ${editable() && D.charges.length > 1 ? `<button data-act="lc_chrm" data-i="${i}">${esc(T('rmCh'))}</button>` : ''}</div></div>`;
}
function draw() {
  const mode = (D.info && D.info.mode) || 'off';
  const ro = editable() ? '' : 'disabled';
  shell(T('title'), `<div class="card stack"><div class="row between wrap"><h3 style="margin:0">${esc(T('bills'))}</h3><span class="chip ${stCls(D.status)}">${esc(stLabel(D.status))}</span></div>
      <div id="lc_bills">${billsHtml()}</div>${editable() && mode !== 'per_bill' ? `<button data-act="lc_billadd">${esc(T('addBill'))}</button>` : ''}
      ${mode !== 'per_bill' ? `<div><label for="lc_ref">${esc(T('ship'))}${mode === 'per_shipment' ? ' *' : ''}</label><input id="lc_ref" autocomplete="off" maxlength="80" value="${esc(D.ref)}" ${ro}>${mode === 'per_shipment' && !D.ref ? `<div class="hint">${esc(T('shipNeed'))}</div>` : ''}</div>` : ''}
      <div class="row wrap"><div style="flex:2;min-width:140px"><label for="lc_ttl">${esc(T('ttl'))}</label><input id="lc_ttl" autocomplete="off" maxlength="120" value="${esc(D.title)}" ${ro}></div><div style="flex:1;min-width:130px"><label for="lc_dt">${esc(T('cdate'))}</label><input id="lc_dt" type="date" value="${esc(D.date)}" ${ro}></div></div></div>
    <div class="card"><h3 style="margin-top:0">${esc(T('charges'))}</h3><div id="lc_ch">${D.charges.map(chargeHtml).join('')}</div>${editable() ? `<button data-act="lc_chadd">${esc(T('addCh'))}</button>` : ''}</div>
    <div id="lc_basis"></div><div id="lc_pv"></div><div class="lc-bar" id="lc_bar"></div>`, 'landed');
  drawBar(); drawPv();
}
function drawBar() {
  const bar = $('#lc_bar'); if (!bar) return;
  const req = D.info && D.info.requires_approval === 'required';
  const can = D.info || {}; const b = [];
  if (editable()) {
    b.push(`<button data-act="lc_save" ${D.busy ? 'disabled' : ''}>${esc(T('saveDraft'))}</button>`);
    if (D.status === 'draft' && can.can_approve) b.push(`<button data-act="lc_approve" ${D.busy ? 'disabled' : ''}>${esc(T('approve'))}</button>`);
    if (D.status === 'approved' || !req) b.push(`<button class="primary" data-act="lc_post" ${D.busy ? 'disabled' : ''}>${esc(T('post'))}</button>`);
    if (D.id && can.can_approve) b.push(`<button class="danger" data-act="lc_void">${esc(T('voidIt'))}</button>`);
  } else if (D.status === 'posted' && can.can_approve) b.push(`<button class="danger" data-act="lc_void">${esc(T('voidIt'))}</button>`);
  bar.innerHTML = b.join('');
}

// ---------- the live preview (only #lc_pv is redrawn, so the keyboard stays open) ----------
function payload() {
  const lines = []; let bad = null;
  D.charges.forEach((c) => {
    const a = num(c.amount); if (a === null) return;
    if (Number.isNaN(a) || a === 0) { bad = bad || 'badNum'; return; }
    const ccy = String(c.ccy || baseCcy()).toUpperCase(); const o = { charge_type: c.type, amount_ccy: a, ccy, pay_mode: c.pay, alloc_method: c.meth || null, supplier_id: c.sup || null };
    if (ccy !== baseCcy()) { const r = num(c.rate); if (r === null || Number.isNaN(r) || r <= 0) { bad = bad || 'needRate'; return; } o.rate = r; }
    lines.push(o);
  });
  const ok0 = (n) => (n === null || Number.isNaN(n) || n < 0 ? null : n);
  const basis = Object.entries(D.basis).map(([id, v]) => ({ bill_line_id: Number(id), weight_kg: ok0(num(v.weight)), volume_l: ok0(num(v.volume)), manual_pct: (() => { const n = ok0(num(v.pct)); return n !== null && n <= 100 ? n : null; })() }))
    .filter((x) => x.weight_kg || x.volume_l || x.manual_pct !== null).map((x) => ({ bill_line_id: x.bill_line_id, weight_kg: x.weight_kg || null, volume_l: x.volume_l || null, manual_pct: x.manual_pct }));
  return { lines, basis, bad };
}
function schedule() { clearTimeout(D.timer); D.timer = setTimeout(runPreview, 350); }
async function runPreview() {
  const mine = ++seq; const p = payload();
  if (p.bad) { D.pv = { _bad: p.bad }; return drawPv(); }
  if (!p.lines.length) { D.pv = null; return drawPv(); }
  try {
    const r = await sb.rpc('landed_preview', { p_bills: D.bills, p_charges: p.lines, p_basis: p.basis, p_method: D.method, p_late: D.late });
    if (mine !== seq) return;
    D.pv = r.error ? { _err: r.error } : r.data;
  } catch (e) { if (mine !== seq) return; D.pv = { _err: e }; }
  drawBasis(); drawPv();
}
function methodChips(pv) {
  const av = pv.avail || {}; const reco = (pv.recommendation || {}).method;
  return `<div class="row wrap lc-chips">${METHODS.map((m) => {
    const ok = !av[m] || av[m].ok !== false; const on = D.method === m; const why = av[m] && av[m].why ? lab(X['why_' + av[m].why] || { bn: '', mix: '', en: '' }) : '';
    return `<button class="tog ${on ? 'on' : ''}" data-act="lc_method" data-v="${m}" aria-pressed="${on}" ${ok || !editable() ? '' : 'data-na="1"'} ${editable() ? '' : 'disabled'} title="${esc(why)}">${esc(methodName(m))}${m === reco ? ' ★' : ''}${ok ? '' : ' ?'}</button>`;
  }).join('')}</div>${METHODS.some((m) => av[m] && av[m].ok === false) ? `<div class="hint">? ${esc(T('unavailable'))}: ${esc(METHODS.filter((m) => av[m] && av[m].ok === false).map((m) => methodName(m) + ' (' + lab(X['why_' + av[m].why] || { bn: '', mix: '', en: '' }) + ')').join('; '))}</div>` : ''}${(av.qty && av.qty.mixed_units) ? `<div class="hint">${esc(T('mixedUnits'))}</div>` : ''}`;
}
function drawPv() {
  const box = $('#lc_pv'); if (!box) return;
  const pv = D.pv;
  if (D.status === 'posted' || D.status === 'void') { box.innerHTML = postedHtml(); return; }
  if (!pv) { box.innerHTML = `<div class="card muted center">${esc(T('needCharge'))}</div>`; return; }
  if (pv._bad) { box.innerHTML = `<div class="notice bad">${esc(T(pv._bad))}</div>`; return; }
  if (pv._err) { const m = (pv._err && pv._err.message) || ''; let msg = ''; for (const k of Object.keys(ERR)) if (m.indexOf(k) >= 0) { msg = lab(ERR[k]); break; } box.innerHTML = `<div class="notice bad">${esc(msg || (/not allowed/.test(m) ? T('noperm') : /does not exist|Could not find/i.test(m) ? T('noFn') : m))}</div>`; return; }
  const reco = pv.recommendation || {}; const lines = (pv.lines || []);
  const rec = `<div class="card stack"><h3 style="margin:0">${esc(T('method'))}</h3>${methodChips(pv)}
    ${(reco.reasons || []).length ? `<div class="notice ok lc-reco">★ ${esc(T('recommended'))}: ${esc(methodName(reco.method))}<br>${(reco.reasons || []).map((r) => esc(txt(r))).join('<br>')}${editable() && reco.method && reco.method !== D.method ? `<br><button data-act="lc_usereco">${esc(T('useReco'))}</button>` : ''}</div>` : ''}
    ${(reco.warnings || []).map((w) => `<div class="notice warn lc-warn" data-w="${esc(w.code || '')}">${esc(txt(w))}</div>`).join('')}</div>`;
  const per = lines.filter((l) => l.in_scope).map((l) => {
    const ms = METHODS.filter((m) => l.methods && l.methods[m]);
    return `<div class="card lc-line"><div class="row between"><b>${esc(l.code || '—')} · ${esc(lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }))}</b><span class="hint">${esc(q(l.base_qty))} ${esc(l.unit || '')}</span></div>
      <div class="row between"><span class="muted">${esc(T('now'))}</span><b>${esc(unit(l.ucb_net))}</b></div>
      ${ms.map((m) => `<div class="row between lc-m ${m === D.method ? 'on' : ''}"><span>${m === D.method ? '▸ ' : ''}${esc(methodName(m))}</span><span>${esc(T('alloc'))} ${esc(money(l.methods[m].alloc))}</span><b>${esc(unit(l.methods[m].new_unit_cost))}${l.methods[m].pct_up != null ? ` <span class="hint">+${esc(q(l.methods[m].pct_up, 2))}%</span>` : ''}</b></div>`).join('')}
      ${l.chosen && Number(l.chosen.cogs) ? `<div class="hint">${esc(T('toStock'))} ${esc(money(l.chosen.stock))} · ${esc(T('toVar'))} ${esc(money(l.chosen.cogs))}</div>` : ''}</div>`;
  }).join('');
  const items = (pv.items || []).map((it) => `<div class="row between wrap"><span>${esc(itemLabel(lines, it.item_id))}</span><span class="hint">${esc(T('onHand'))} ${esc(q(it.on_hand))}${Number(it.late_qty) > 0 ? ' · ' + esc(T('lateQty')) + ' ' + esc(q(it.late_qty)) : ''}</span><span>${esc(T('avgNow'))} ${esc(it.avg == null ? '—' : unit(it.avg))} → <b>${esc(it.avg_after == null ? '—' : unit(it.avg_after))}</b></span></div>`).join('');
  const hasLate = (pv.items || []).some((it) => Number(it.late_qty) > 0);
  const lateBox = `<div class="card stack"><h3 style="margin:0">${esc(T('late'))}</h3><div class="row wrap lc-chips">${LATE.map((m) => `<button class="tog ${(D.late || pv.late_mode) === m ? 'on' : ''}" data-act="lc_late" data-v="${m}" aria-pressed="${(D.late || pv.late_mode) === m}" ${editable() ? '' : 'disabled'}>${esc(T({ split_remaining_and_cogs: 'l_split', post_to_remaining_stock: 'l_post', variance_account: 'l_var' }[m]))}${m === reco.late_mode && hasLate ? ' ★' : ''}</button>`).join('')}</div></div>`;
  const tot = pv.totals || {};
  box.innerHTML = rec + `<h3>${esc(T('preview'))}</h3>${per || `<div class="card muted">${esc(T('noStock'))}</div>`}
    <div class="card stack"><h3 style="margin:0">${esc(T('totals'))}</h3><div class="row between"><span>${esc(T('tCap'))}</span><b>${esc(money(tot.capitalised))}</b></div>${Number(tot.expense_only) ? `<div class="row between"><span>${esc(T('tExp'))}</span><b>${esc(money(tot.expense_only))}</b></div>` : ''}${Number(tot.recoverable_tax) ? `<div class="row between"><span>${esc(T('tTax'))}</span><b>${esc(money(tot.recoverable_tax))}</b></div>` : ''}
      ${items ? `<h4 style="margin:8px 0 0">${esc(T('stockEff'))}</h4>${items}` : ''}</div>` + lateBox;
}
const itemLabel = (lines, id) => { const l = lines.find((x) => x.item_id === id); return l ? (l.code || '') + ' · ' + lab({ bn: l.name_bn, mix: l.name_bn, en: l.name_en || l.name_bn }) : '—'; };
// weights / volumes / % per line: drawn from the last preview, kept while typing
function drawBasis() {
  const box = $('#lc_basis'); if (!box || !D.pv || !D.pv.lines) return;
  if (!editable()) { box.innerHTML = ''; return; }
  if (box.dataset.sig === D.bills.join(',') && $('#lc_basis input')) { refreshSrc(); return; }
  const ls = D.pv.lines.filter((l) => l.in_scope); box.dataset.sig = D.bills.join(',');
  box.innerHTML = ls.length ? `<div class="card stack"><h3 style="margin:0">${esc(T('basis'))}</h3><div class="hint">${esc(T('basisNote'))}</div>${ls.map((l) => { const v = D.basis[l.bill_line_id] || {};
    return `<div class="lc-bl" data-bl="${l.bill_line_id}"><b>${esc(l.code || '')}</b> <span class="hint">${esc(q(l.base_qty))} ${esc(l.unit || '')}</span>
      <div class="row wrap"><div style="flex:1;min-width:90px"><label>${esc(T('kg'))}</label><input data-lcb="${l.bill_line_id}" data-k="weight" inputmode="decimal" autocomplete="off" value="${esc(v.weight ?? '')}" placeholder="${l.weight != null ? esc(q(l.weight)) : ''}"></div>
        <div style="flex:1;min-width:90px"><label>${esc(T('litre'))}</label><input data-lcb="${l.bill_line_id}" data-k="volume" inputmode="decimal" autocomplete="off" value="${esc(v.volume ?? '')}" placeholder="${l.volume != null ? esc(q(l.volume)) : ''}"></div>
        <div style="flex:1;min-width:70px"><label>${esc(T('pct'))}</label><input data-lcb="${l.bill_line_id}" data-k="pct" inputmode="decimal" autocomplete="off" value="${esc(v.pct ?? '')}"></div></div>
      <div class="hint" data-src="${l.bill_line_id}"></div></div>`; }).join('')}</div>` : '';
  refreshSrc();
}
function refreshSrc() {
  if (!D.pv || !D.pv.lines) return;
  D.pv.lines.filter((l) => l.in_scope).forEach((l) => { const el = $(`[data-src="${l.bill_line_id}"]`); if (!el) return;
    const w = l.weight == null ? T('unknownW') : q(l.weight) + ' kg (' + T('src_' + l.weight_src) + ')'; const v = l.volume == null ? T('unknownW') : q(l.volume) + ' l (' + T('src_' + l.volume_src) + ')';
    el.textContent = T('me_weight') + ': ' + w + ' · ' + T('me_volume') + ': ' + v; });
}
function postedHtml() {
  const g = D.got; if (!g) return '';
  const grp = {}; (g.alloc || []).forEach((a) => { const k = a.bill_line_id || ('c' + a.charge_line_id); const o = grp[k] = grp[k] || { post: 0, void: 0 }; o[a.kind] += Number(a.amount); });
  const st = (g.stock || []).filter((s) => s.kind === 'post');
  return `<div class="card stack"><h3 style="margin:0">${esc(T('postedSum'))}</h3>${g.lines.map((l) => `<div class="row between"><span>${esc(typeName(typeOf(l.charge_type) || { name_bn: l.charge_type, name_en: l.charge_type }))}</span><b>${esc(money(l.amount))}</b></div>`).join('')}
    <div class="row between"><span>${esc(T('totals'))}</span><b>${esc(money(g.header.total))}</b></div>
    ${st.map((s) => `<div class="hint">${esc(T('avgNow'))} ${esc(s.avg_before == null ? '—' : unit(s.avg_before))} → <b>${esc(s.avg_after == null ? '—' : unit(s.avg_after))}</b> · ${esc(T('stockAdded'))} ${esc(money(s.stock_value))} · ${esc(T('toVariance'))} ${esc(money(s.cogs_value))}</div>`).join('')}
    ${g.header.status === 'void' ? `<div class="notice bad">${esc(T('voided'))}: ${esc(g.header.void_reason || '')}</div>` : ''}</div>`;
}

// ---------- save / approve / post / void ----------
function headerObj() { return { shipment_ref: D.ref || null, title: D.title || null, note: D.note || null, cost_date: D.date, alloc_method: D.method, late_mode: D.late }; }
async function doSave() {
  const p = payload(); if (p.bad) { toast(T(p.bad)); return false; } if (!p.lines.length) { toast(T('needCharge')); return false; }
  const docs = D.bills.map((id) => ({ type: 'bill', id }));
  const r = await call('landed_save', { p_client: D.id ? null : D.client, p_id: D.id, p_header: headerObj(), p_docs: docs, p_lines: p.lines, p_basis: p.basis });
  D.id = r.id; D.status = r.status; return true;
}
async function busy(f) { if (D.busy) return; D.busy = true; drawBar(); try { await f(); } catch (e) { errMsg(e); } finally { D.busy = false; drawBar(); } }
Object.assign(H, {
  lc_new: () => pickSheet(false),
  lc_open: (a) => { location.hash = '#/landed/' + a.dataset.v; },
  lc_rem: () => { location.hash = '#/landed/rem'; },
  lc_settings: () => settingsSheet(), lc_settings_go: (a) => busy(() => settingsGo(a)),
  lc_pickgo: () => { if (!D.pick.length) return; closeSheet(); if (D.pickAdd && D.bills.length) { D.bills = D.pick.slice(); loadBillInfo(D.bills).then(() => { D.basis = {}; $('#lc_basis') && ($('#lc_basis').dataset.sig = ''); draw(); runPreview(); }); } else location.hash = '#/landed/new/' + D.pick.join(','); },
  lc_billadd: () => pickSheet(true),
  lc_billrm: (a) => { D.bills = D.bills.filter((x) => x !== a.dataset.v); $('#lc_basis') && ($('#lc_basis').dataset.sig = ''); draw(); runPreview(); },
  lc_flag: (a) => busy(async () => { await call('landed_supplier_flag_set', { p_supplier: a.dataset.v, p_kind: 'imported', p_active: true, p_note: null }); toast(T('flagged')); }),
  lc_chadd: () => { D.charges.push(blankCharge()); const b = $('#lc_ch'); if (b) b.innerHTML = D.charges.map(chargeHtml).join(''); },
  lc_chrm: (a) => { D.charges.splice(Number(a.dataset.i), 1); const b = $('#lc_ch'); if (b) b.innerHTML = D.charges.map(chargeHtml).join(''); schedule(); },
  lc_method: (a) => { if (!editable()) return; D.method = a.dataset.v; drawPv(); schedule(); },
  lc_late: (a) => { if (!editable()) return; D.late = a.dataset.v; schedule(); drawPv(); },
  lc_usereco: () => { const r = (D.pv && D.pv.recommendation) || {}; if (r.method) D.method = r.method; D.charges.forEach((c, i) => { c.meth = ''; });
    const pc = r.per_charge || []; let k = 0; D.charges.forEach((c) => { if (num(c.amount) === null) return; const p = pc[k++]; if (p && p.method && p.method !== D.method) c.meth = p.method; });
    if (r.late_mode && (D.pv.items || []).some((it) => Number(it.late_qty) > 0)) D.late = r.late_mode; const b = $('#lc_ch'); if (b) b.innerHTML = D.charges.map(chargeHtml).join(''); runPreview(); },
  lc_save: () => busy(async () => { if (await doSave()) { toast(T('saved')); if (location.hash.indexOf(D.id) < 0) history.replaceState(null, '', '#/landed/' + D.id); await openCost(D.id); } }),
  lc_approve: () => busy(async () => { if (!(await doSave())) return; await call('landed_approve', { p_id: D.id }); toast(T('approvedOk')); await openCost(D.id); }),
  lc_post: () => busy(async () => { if (!window.confirm || window.confirm(T('confirmPost'))) { if (!(await doSave())) return; const r = await call('landed_post', { p_id: D.id, p_client: rid() }); toast(r.dup ? T('already') : T('posted')); await openCost(D.id); } }),
  lc_void: () => openSheet(`<h2>${esc(T('voidIt'))}</h2><div><label for="lc_vwhy">${esc(T('reason'))}</label><input id="lc_vwhy" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="lc_voidgo">${esc(T('voidIt'))}</button></div>`),
  lc_voidgo: () => busy(async () => { const w = (($('#lc_vwhy') || {}).value || '').trim(); if (w.length < 3) return toast(lab(ERR.reason_required)); await call('landed_void', { p_id: D.id, p_reason: w }); closeSheet(); toast(T('voided')); await openCost(D.id); }),
  lc_add: (a) => { location.hash = '#/landed/new/' + a.dataset.b; },
  lc_skip: (a) => openSheet(`<h2>${esc(T('skip'))}</h2><div><label for="lc_swhy">${esc(T('skipWhy'))}</label><input id="lc_swhy" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="lc_skipgo" data-v="${esc(a.dataset.v)}">${esc(T('skip'))}</button></div>`),
  lc_skipgo: (a) => busy(async () => { const w = (($('#lc_swhy') || {}).value || '').trim(); if (w.length < 3) return toast(lab(ERR.reason_required)); await call('landed_skip', { p_bill: a.dataset.v, p_reason: w }); closeSheet(); toast(T('skipped')); await remView(); }),
  lc_remopen: (a) => { location.hash = '#/landed/new/' + a.dataset.v; },
  lc_ctype: () => openSheet(`<h2>${esc(T('ctypeAdd'))}</h2><div class="stack"><div><label for="lct_code">${esc(T('ctCode'))}</label><input id="lct_code" autocomplete="off" maxlength="32"></div><div><label for="lct_en">${esc(T('ctEn'))}</label><input id="lct_en" autocomplete="off"></div><div><label for="lct_bn">${esc(T('ctBn'))}</label><input id="lct_bn" autocomplete="off"></div>
    <div><label for="lct_tr">${esc(T('ctTreat'))}</label><select id="lct_tr">${['capitalise', 'expense_only', 'recoverable_tax'].map((v) => `<option value="${v}">${esc(T('t_' + v))}</option>`).join('')}</select></div>
    <div><label for="lct_me">${esc(T('method'))}</label><select id="lct_me"><option value="">${esc(T('hdrMeth'))}</option>${['value', 'qty', 'weight', 'volume', 'equal'].map((v) => `<option value="${v}">${esc(methodName(v))}</option>`).join('')}</select></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="lc_ctypego">${esc(T('save'))}</button></div></div>`),
  lc_ctypego: () => busy(async () => { const v = (id) => (($('#' + id) || {}).value || '').trim(); const code = v('lct_code').toLowerCase(); const en = v('lct_en'); const bn = v('lct_bn') || en;
    await call('landed_charge_type_save', { p_code: code, p_name_bn: bn, p_name_en: en, p_name_mix: en, p_treatment: v('lct_tr'), p_expense_key: null, p_default_alloc: v('lct_me') || null, p_active: true }); closeSheet(); D.info = null; toast(T('saved')); }),
});

// ---------- reminders and returns ----------
async function remView() {
  shell(T('remTitle'), `<p class="muted center pad">${esc(T('loading'))}</p>`, 'landed');
  let r; try { r = await call('landed_reminders', {}); } catch (e) { errMsg(e); shell(T('remTitle'), `<div class="notice bad">${esc(T('noperm'))}</div>`, 'landed'); return; }
  const own = !!(S.ctx && S.ctx.is_owner);
  shell(T('remTitle'), `${!r.on ? `<div class="notice warn">${esc(T('remOff'))}</div>${own ? `<button data-act="lc_settings">${esc(T('settings'))}</button>` : ''}` :
    `<div class="card">${(r.rows || []).length ? r.rows.map((x) => `<div class="s2-led"><div><b>${esc(x.supplier)}</b> · ${esc(x.bill_no || '—')}<div class="sub">${esc(x.bill_date)} · ${esc(money(x.total))} · ${esc(T('w_' + x.why))}${x.in_progress ? ' · ' + esc(T('inProgress')) : ''}</div></div>
      <div class="row"><button class="primary" data-act="lc_remopen" data-v="${esc(x.bill_id)}">${esc(T('addBtn'))}</button><button data-act="lc_skip" data-v="${esc(x.bill_id)}">${esc(T('skip'))}</button></div></div>`).join('') : `<p class="muted center">${esc(T('remNone'))}</p>`}</div>`}`, 'landed');
}
async function returnView(id) {
  let r; try { r = await call('landed_return_info', { p_bill: id }); } catch (e) { errMsg(e); return; }
  shell(T('retTitle'), `<div class="card stack">${r.has_landed ? r.items.map((x) => `<div class="row between wrap"><span>${esc(x.code)}</span><span class="hint">${esc(T('retQty'))} ${esc(q(x.returned_qty))}</span><span>${esc(T('retUnit'))} ${esc(unit(x.landed_per_unit))}</span><b>${esc(money(x.landed_on_returned))}</b></div>`).join('') + `<div class="row between"><span>${esc(T('totals'))}</span><b>${esc(money(r.total))}</b></div><div class="notice warn">${esc(txt(r.note))}</div>` : `<p class="muted center">${esc(T('retNone'))}</p>`}</div>`, 'landed');
}

// ---------- typing updates the working copy only ----------
document.addEventListener('input', (e) => {
  const t = e.target; if (!t || !t.dataset) return;
  if (t.dataset.lc && D.charges[Number(t.dataset.i)]) { const c = D.charges[Number(t.dataset.i)]; c[t.dataset.lc === 'meth' ? 'meth' : t.dataset.lc] = t.value; if (t.dataset.lc === 'ccy') { const rb = $(`[data-ratebox="${t.dataset.i}"]`); if (rb) rb.hidden = String(t.value || '').toUpperCase() === baseCcy() || String(t.value || '').trim() === ''; }
    if (t.dataset.lc === 'amount' || t.dataset.lc === 'rate' || t.dataset.lc === 'ccy') schedule(); return; }
  if (t.dataset.lcb) { const o = D.basis[t.dataset.lcb] = D.basis[t.dataset.lcb] || {}; o[t.dataset.k] = t.value; schedule(); return; }
  if (t.id === 'lc_ref') D.ref = t.value; if (t.id === 'lc_ttl') D.title = t.value; if (t.id === 'lc_dt') D.date = t.value;
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t) return;
  if (t.dataset && t.dataset.lcpk !== undefined) { const id = t.dataset.lcpk; D.pick = t.checked ? D.pick.concat(id) : D.pick.filter((x) => x !== id); return; }
  if (t.dataset && t.dataset.lc && D.charges[Number(t.dataset.i)]) { const c = D.charges[Number(t.dataset.i)]; c[t.dataset.lc] = t.value;
    // never redraw the list here: a redraw on blur would swallow the next tap / keystroke. Only small parts are toggled in place.
    if (t.dataset.lc === 'type') { const x = typeOf(t.value), h = $(`#lc_th${t.dataset.i}`); if (h) h.textContent = x ? T('t_' + x.treatment) + (typeHint(x) ? ' · ' + typeHint(x) : '') : ''; }
    if (t.dataset.lc === 'pay') { const sb2 = $(`[data-supbox="${t.dataset.i}"]`); if (sb2) sb2.hidden = t.value !== 'payable'; }
    schedule(); }
});

// ---------- route ----------
async function view() {
  const p = location.hash.replace(/^#\/?/, '').split('/').slice(1);
  if (!p[0]) return listView();
  if (p[0] === 'rem') return remView();
  if (p[0] === 'new') { const ids = (p[1] || '').split(',').filter((x) => UUID.test(x)); if (!ids.length) return listView(); return openNew(ids); }
  if (UUID.test(p[0])) return openCost(p[0]);
  return listView();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { landed: view });
B.landed = { X, T, ERR, METHODS, LATE, view, payload, num, errMsg, D, _state: () => D };

// the menu entry shows for people who hold the landed grants: nav.js only probes a fixed list of grant codes, so the two codes of this screen are probed here (server still decides on every call)
async function probeGrants() {
  try { const GF = window.BOS_NAV && window.BOS_NAV.grantFlags && window.BOS_NAV.grantFlags(); if (!GF || !S.ctx || S.ctx.is_owner || !A.hasAnyGrant) return true;
    for (const c of ['landed_entry', 'landed_approve']) GF[c] = await A.hasAnyGrant([c]); return true; } catch (e) { return false; }
}
let probes = 0; const probeTimer = setInterval(() => { if (++probes > 40) return clearInterval(probeTimer); if (S.ctx) { clearInterval(probeTimer); probeGrants(); } }, 1500);

// ---------- guarded link on the purchase bill page (purchase.js is not edited) ----------
let linkBusy = false;
async function addLink() {
  if (linkBusy) return; const m = location.hash.match(/^#\/purchase\/([0-9a-f-]{36})$/i); if (!m) return;
  const bar = document.querySelector('.s2-bar'); if (!bar || bar.querySelector('[data-act="lc_add"]') || bar.querySelector('[data-act="pu_postd"]')) return;
  linkBusy = true;
  try { const info = await need(); if (!info || !info.can_entry) return; if (!document.querySelector('.s2-bar') || document.querySelector('[data-act="lc_add"]')) return;
    const btn = document.createElement('button'); btn.setAttribute('data-act', 'lc_add'); btn.setAttribute('data-b', m[1]); btn.textContent = T('addBtn'); document.querySelector('.s2-bar').appendChild(btn); } catch (e) { /* the link is optional: no database part or no right = no link */ } finally { linkBusy = false; }
}
try { if (window.MutationObserver && document.body) new MutationObserver(() => { if (/^#\/purchase\/[0-9a-f-]{36}$/i.test(location.hash)) addLink(); }).observe(document.body, { childList: true, subtree: true }); } catch (e) { /* no observer: no link, the menu entry still works */ }

const css = document.createElement('style'); css.id = 'lccss';
css.textContent = `.lc-ch{margin:8px 0}.lc-ch select,.lc-ch input,.lc-bl input{width:100%;box-sizing:border-box}.lc-chips button{min-height:44px}.lc-m{padding:4px 6px;border-radius:8px;flex-wrap:wrap;gap:4px}.lc-m.on{background:var(--chip-on);font-weight:700}
.lc-reco,.lc-warn{overflow-wrap:anywhere}.lc-pk{min-height:48px;gap:8px}.lc-pk input{width:22px;height:22px;flex:none}.lc-bar{position:sticky;bottom:0;z-index:4;display:flex;gap:8px;padding:10px 0;background:var(--bg);border-top:1px solid var(--line);flex-wrap:wrap}
.lc-bar button{flex:1;min-height:44px}body.has-bnav .lc-bar{bottom:58px}.lc-line{overflow-wrap:anywhere}`;
document.head.appendChild(css);
})();
