/* Islamia BOS · Purchases (#/purchase) and supplier payables (#/payables).
   Bills list with filters, new bill / purchase return editor (draft, then post with payments), bill detail with void,
   supplier dues, supplier ledger with "pay supplier" (oldest bills cleared first) and void payment.
   Server: phase10.sql (save_purchase, post_purchase, void_purchase, pay_supplier, void_supplier_payment, supplier_dues, supplier_ledger, payables_summary, purchase_list, purchase_get).
   Cost figures live only here and on screens the server lets the caller read. Needs stock2.js (B.s2) and pay.js (B.pay). */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const U = B.s2;                                   // shared helpers from stock2.js
const { errToast, rid, grant, nnum, norm, money, dt, optHTML, locSel, LOCS, allLocs, npMode, lists, rowL, unitLabel, LOCK } = U;
const r2 = (n) => Math.round(Number(n) * 100) / 100;
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const days = (iso) => (iso ? Math.max(0, Math.round((new Date(today() + 'T12:00:00Z') - new Date(iso + 'T12:00:00Z')) / 86400000)) : 0);
const dshort = (iso) => (iso ? new Date(iso + 'T12:00:00Z').toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }) : '');

// ---------- labels ----------
const X = {
  title: L('ক্রয়', 'Purchases', 'Purchase'), payables: L('সাপ্লায়ারের পাওনা', 'Supplier payables', 'Supplier-এর Payable'), newBill: L('নতুন ক্রয় বিল', 'New purchase bill', 'নতুন Purchase bill'),
  newRet: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), editBill: L('খসড়া বদলান', 'Edit draft', 'Draft বদলান'), bill: L('বিল', 'Bill', 'Bill'), ret: L('ফেরত', 'Return', 'Return'),
  filter: L('ফিল্টার', 'Filter', 'Filter'), apply: L('প্রয়োগ', 'Apply', 'Apply'), reset: L('মুছে দিন', 'Reset', 'Reset'), all: L('সব', 'All', 'All'),
  supplier: L('সাপ্লায়ার', 'Supplier', 'Supplier'), status: L('অবস্থা', 'Status', 'Status'), from: L('শুরু', 'From', 'From'), to: L('শেষ', 'To', 'To'), location: L('জায়গা', 'Location', 'Location'),
  draft: L('খসড়া', 'Draft', 'Draft'), posted: L('পোস্ট হয়েছে', 'Posted', 'Posted'), void_: L('বাতিল', 'Void', 'Void'), allLoc: L('সব জায়গা', 'All locations', 'সব Location'),
  none: L('কোনো বিল নেই', 'No bills', 'কোনো bill নেই'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), lockedPage: L('ক্রয়ের হিসাব দেখার অনুমতি আপনার নেই', 'You are not allowed to see purchases', 'Purchase দেখার permission নেই'),
  due: L('বাকি', 'Due', 'Due'), paid: L('দেওয়া', 'Paid', 'Paid'), total: L('মোট', 'Total', 'Total'), subtotal: L('উপমোট', 'Subtotal', 'Subtotal'), discount: L('ছাড় ৳', 'Discount ৳', 'Discount ৳'),
  billNo: L('সাপ্লায়ারের বিল নম্বর', "Supplier's bill no.", 'Supplier-এর bill no.'), date: L('বিলের তারিখ', 'Bill date', 'Bill date'), supPh: L('সাপ্লায়ারের নাম লিখুন বা বাছুন', 'Type or choose a supplier', 'Supplier-এর নাম লিখুন বা বাছুন'),
  lines: L('মালের লাইন', 'Lines', 'Lines'), nLines: L('লাইন', 'lines', 'lines'), addLine: L('লাইন যোগ', 'Add line', 'Line যোগ'), item: L('পণ্য', 'Item', 'Item'), itemph: L('কোড বা নাম (ঐচ্ছিক)', 'Code or name (optional)', 'Code বা নাম (ঐচ্ছিক)'),
  desc: L('অথবা লিখে বিবরণ (গ্যাস, ভাড়া…)', 'Or a free-text description (gas, transport…)', 'অথবা description (gas, transport…)'), qty: L('পরিমাণ', 'Qty', 'Qty'), unit: L('একক', 'Unit', 'Unit'), itemUnit: L('(পণ্যের)', '(item)', '(item-এর)'),
  lotNo: L('সাপ্লায়ারের লট / ব্যাচ নম্বর', 'Supplier lot / batch no', 'Supplier lot / batch no'), lotExp: L('লটের মেয়াদ', 'Lot expiry date', 'Lot expiry'),
  lotHint: L('ঐচ্ছিক। এক লাইনে এক লট; দুই লট হলে দুই লাইন করুন। কাগজের ফর্মের কোড: মালিক দেবেন।', 'Optional. One lot per line; for two lots use two lines. Paper form code: to be given by owner.', 'Optional। এক line এ এক lot; দুই lot হলে দুই line। Paper form code: owner দেবেন।'),
  lotNeed: L('এই লাইনে সাপ্লায়ারের লট নম্বর লাগবে (মালিকের নিয়ম)', 'This line needs the supplier lot number (owner setting)', 'এই line এ supplier lot no লাগবে (owner setting)'), expNeed: L('এই লাইনে লটের মেয়াদ লাগবে (মালিকের নিয়ম)', 'This line needs the lot expiry date (owner setting)', 'এই line এ lot expiry লাগবে (owner setting)'),
  lotsTitle: L('সাপ্লায়ারের লট', 'Supplier lots', 'Supplier lots'), lotStaged: L('লট লেখা আছে কিন্তু স্টকে ব্যাচ হয়নি', 'Lot written but no stock batch made yet', 'Lot লেখা আছে কিন্তু batch হয়নি'), lotApply: L('এখনই ব্যাচ বানান', 'Make the batches now', 'এখনই batch বানান'), lotNoStock: L('স্টকে মাল নেই বলে ব্যাচ হয়নি', 'No batch: the stock was no longer there', 'Stock নেই তাই batch হয়নি'), lotNone: L('এই বিলে কোনো লট লেখা হয়নি', 'No lot was written on this bill', 'এই bill এ কোনো lot লেখা হয়নি'), lotBatch: L('ব্যাচ', 'Batch', 'Batch'),
  ucost: L('একক দাম ৳', 'Unit cost ৳', 'Unit cost ৳'), amount: L('টাকা', 'Amount', 'Amount'), note: L('নোট', 'Note', 'Note'), photo: L('বিলের ছবি', 'Bill photo', 'Bill-এর photo'), addPhoto: L('ছবি তুলুন / বাছুন', 'Take / choose photo', 'Photo তুলুন / বাছুন'),
  upl: L('ছবি আপলোড হচ্ছে…', 'Uploading photo…', 'Photo upload হচ্ছে…'), reason: L('ফেরতের কারণ', 'Return reason', 'Return-এর reason'), againstBill: L('কোন বিলের বিপরীতে (ঐচ্ছিক)', 'Against bill (optional)', 'কোন bill-এর বিপরীতে (ঐচ্ছিক)'),
  payNow: L('এখনই পেমেন্ট', 'Pay now', 'Pay now'), payHint: L('কিছু না দিলে পুরো টাকা সাপ্লায়ারের পাওনা থাকবে', 'If you pay nothing the whole amount stays owed to the supplier', 'কিছু না দিলে পুরো amount supplier-এর payable থাকবে'),
  saveDraft: L('খসড়া সংরক্ষণ', 'Save draft', 'Draft save'), post: L('পোস্ট করুন', 'Post bill', 'Post করুন'), postRet: L('ফেরত পোস্ট করুন', 'Post return', 'Return post করুন'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ', 'Close', 'Close'),
  saved: L('খসড়া সংরক্ষিত', 'Draft saved', 'Draft saved'), posted_ok: L('পোস্ট হয়েছে', 'Posted', 'Posted'), dup: L('আগেই সংরক্ষিত — আবার হয়নি', 'Already saved — nothing was added twice', 'আগেই saved — আবার হয়নি'),
  voidBill: L('বিল বাতিল', 'Void bill', 'Bill void'), voidDraft: L('খসড়া বাতিল', 'Cancel draft', 'Draft cancel'), voidWhy: L('বাতিলের কারণ (আবশ্যক)', 'Reason for voiding (required)', 'Void-এর reason (আবশ্যক)'),
  voidWarn: L('মাল স্টক থেকে উল্টে যাবে এবং বিলের সাথের পেমেন্ট বাতিল হবে।', 'The stock is reversed and payments made with the bill are voided.', 'Stock reverse হবে এবং bill-এর payment void হবে।'),
  voided: L('বাতিল হয়েছে', 'Voided', 'Voided'), edit: L('বদলান', 'Edit', 'Edit'), returnVs: L('মাল ফেরত', 'Return goods', 'মাল return'), paySup: L('সাপ্লায়ারকে টাকা দিন', 'Pay the supplier', 'Supplier-কে টাকা দিন'),
  needSup: L('সাপ্লায়ার বাছুন', 'Choose a supplier', 'Supplier বাছুন'), needDate: L('তারিখ লিখুন', 'Enter the date', 'Date লিখুন'), needLine: L('অন্তত একটি পূর্ণ লাইন লিখুন', 'Enter at least one complete line', 'অন্তত একটি complete line লিখুন'),
  badLine: L('লাইনের পরিমাণ বা দাম ঠিক নয়', 'A line has a wrong quantity or cost', 'Line-এর qty বা cost ঠিক নয়'), needReason: L('ফেরতের কারণ বাছুন', 'Choose the return reason', 'Return reason বাছুন'), badDisc: L('ছাড় মোটের বেশি', 'Discount is more than the subtotal', 'Discount subtotal-এর বেশি'),
  needNote: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), by: L('লিখেছেন', 'By', 'By'), mode: { cash: L('নগদ', 'Cash', 'Cash'), mobile: L('মোবাইল', 'Mobile', 'Mobile'), card: L('কার্ড', 'Card', 'Card'), bank: L('ব্যাংক', 'Bank', 'Bank') },
  // payables
  totPay: L('মোট পাওনা', 'Total payable', 'Total payable'), overdue: L('সময় পেরিয়েছে', 'Overdue', 'Overdue'), nSup: L('জন সাপ্লায়ার', 'suppliers', 'suppliers'), oldest: L('সবচেয়ে পুরনো', 'Oldest', 'Oldest'),
  adv: L('সাপ্লায়ারের কাছে অগ্রিম', 'Advance with suppliers', 'Supplier-এর কাছে advance'), noCredit: L('বাকির মেয়াদ বসানো নেই', 'credit days not set', 'credit days বসানো নেই'), noCreditNote: L('যাদের বাকির মেয়াদ (দিন) বসানো নেই তাদের মেয়াদ-পার অঙ্ক হিসাব করা যায় না; ০ নয়, "বসানো নেই" ধরুন।', 'Where credit days are not set the overdue amount cannot be worked out: read it as not set, not as 0.', 'যেখানে credit days বসানো নেই সেখানে overdue হিসাব করা যায় না: ০ নয়, "বসানো নেই"।'),
  creditDays: L('দিন ক্রেডিট', 'credit days', 'credit days'), noDues: L('কোনো সাপ্লায়ারকে দেওয়ার নেই ✓', 'You owe no supplier ✓', 'কোনো supplier-কে দেওয়ার নেই ✓'),
  daysOld: L('দিনের পুরনো', 'days old', 'days old'), ledger: L('সাপ্লায়ারের হিসাব খাতা', 'Supplier ledger', 'Supplier ledger'), balance: L('এখন পাওনা', 'Balance owed', 'Balance owed'), openBills: L('খোলা বিল (পুরনো আগে)', 'Open bills (oldest first)', 'Open bills (পুরনো আগে)'),
  opening: L('শুরুর হিসাব', 'Opening', 'Opening'), kBill: L('বিল', 'Bill', 'Bill'), kReturn: L('ফেরত', 'Return', 'Return'), kPayment: L('পেমেন্ট', 'Payment', 'Payment'), kPaid: L('বিলের সাথে দেওয়া', 'Paid with bill', 'Bill-এর সাথে paid'),
  payTitle: L('সাপ্লায়ারকে পেমেন্ট', 'Pay the supplier', 'Supplier payment'), payOldest: L('টাকা পুরনো বিল থেকে আগে মেটানো হবে।', 'The money clears the oldest bills first.', 'টাকা পুরনো bill থেকে আগে মিটবে।'),
  pay: L('পেমেন্ট নিশ্চিত', 'Confirm payment', 'Payment confirm'), paidOk: L('পেমেন্ট হয়েছে', 'Payment recorded', 'Payment recorded'), enterPay: L('পেমেন্টের টাকা লিখুন', 'Enter the payment amount', 'Payment amount লিখুন'),
  voidPay: L('পেমেন্ট বাতিল', 'Void payment', 'Payment void'), payVoided: L('পেমেন্ট বাতিল হয়েছে', 'Payment voided', 'Payment voided'), walletNeeded: L('মোবাইল পেমেন্টে বিকাশ/নগদ ইত্যাদি বাছুন', 'Choose bKash / Nagad etc.', 'bKash/Nagad বাছুন'),
  addBank: L('ব্যাংক', 'Bank', 'Bank'), sqlMissing: L('ক্রয়ের ডেটাবেস অংশ এখনও চালু হয়নি (phase10)', 'The purchase database part is not installed yet (phase10)', 'Purchase-এর database অংশ চালু হয়নি (phase10)'),
  openPay: L('পেমেন্টের অনুমতি নেই', 'No permission to pay', 'Pay-এর permission নেই'),
  mode_: L('ধরন', 'Mode', 'Mode'), scan: L('স্ক্যান', 'Scan', 'Scan'), more: L('আরও অপশন', 'More options', 'আরও option'), open: L('খুলুন', 'Open', 'Open'),
  // stock-effect preview
  pvUntracked: L('এই পণ্যের স্টক ট্র্যাক বন্ধ — স্টকে প্রভাব নেই', 'Stock tracking is off for this item — no stock effect', 'এই item-এ stock track বন্ধ — stock-এ effect নেই'),
  pvStock: L('স্টক', 'stock', 'stock'), pvAt: L('এ', 'at', 'at'), pvAvg: L('নতুন গড় দাম', 'new average cost', 'নতুন average cost'),
  pvNeed: L('তথ্য লাগবে', 'Data needed', 'Data needed'), pvUnit: L('এককের রূপান্তর জানা নেই', 'unit conversion unknown', 'unit conversion জানা নেই'), pvCost: L('গড় দাম দেখার অনুমতি/তথ্য নেই', 'average cost not available', 'average cost দেখার permission/data নেই'),
  pvLoad: L('স্টক দেখা হচ্ছে…', 'Checking stock…', 'Stock দেখা হচ্ছে…'),
  // supplier refund
  refund: L('সাপ্লায়ারের কাছ থেকে টাকা ফেরত পাওয়া', 'Refund received from the supplier', 'Supplier-এর কাছ থেকে refund পাওয়া'), refundSheet: L('সাপ্লায়ারের টাকা ফেরত', 'Supplier refund', 'Supplier refund'),
  credit: L('সাপ্লায়ারের কাছে জমা', 'Credit held by the supplier', 'Supplier-এর কাছে credit'), creditList: L('যে সাপ্লায়ারের কাছে আমাদের টাকা জমা আছে', 'Suppliers that hold our credit', 'যে supplier-এর কাছে আমাদের credit আছে'),
  refundOk: L('রিফান্ড লেখা হয়েছে', 'Refund recorded', 'Refund recorded'), refundAmt: L('ফেরত পাওয়া টাকা', 'Amount received back', 'ফেরত পাওয়া amount'), refundRef: L('রেফারেন্স / ট্রান্সঅ্যাকশন', 'Reference / transaction', 'Reference / transaction'),
  refundMax: L('জমার চেয়ে বেশি হবে না', 'Cannot be more than the credit', 'Credit-এর বেশি হবে না'), noCredit: L('এই সাপ্লায়ারের কাছে জমা নেই', 'This supplier holds no credit', 'এই supplier-এর কাছে credit নেই'),
  kRefund: L('ফেরত পাওয়া', 'Refund received', 'Refund received'), voidRef: L('রিফান্ড বাতিল', 'Void refund', 'Refund void'), refVoided: L('রিফান্ড বাতিল হয়েছে', 'Refund voided', 'Refund voided'), wallet: L('ওয়ালেট (বিকাশ/নগদ…)', 'Wallet (bKash / Nagad…)', 'Wallet (bKash/Nagad…)'),
  reasonOpt: L('কারণ (ঐচ্ছিক)', 'Reason (optional)', 'Reason (ঐচ্ছিক)'),
};
const T = (k) => lab(X[k]);
const SB = { draft: 'info', posted: 'ok', void: 'bad' };
const stLabel = (s) => T(s === 'void' ? 'void_' : s);
const modeL = (m) => lab(X.mode[m] || L(m, m, m));

// ---------- state ----------
const PL = { f: { loc: '', supplier: '', status: '', from: '', to: '' }, rows: [], shown: 60, err: null };
let ITEMS_ALL = null, F = null;
async function allItems() {
  if (ITEMS_ALL) return ITEMS_ALL;
  let r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,barcode,tracked,is_active,item_type,hidden').order('code'));
  if (r.error) r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,barcode,tracked,is_active').order('code'));      // database without the item master
  ITEMS_ALL = r.error ? [] : (r.data || []).filter((i) => i.is_active !== false && !i.hidden); return ITEMS_ALL;
}
const sups = () => (B.ENV && B.ENV.sup) || [];
const supById = (id) => sups().find((s) => s.id === id);
const supByName = (n) => sups().find((s) => s.name.trim().toLowerCase() === String(n || '').trim().toLowerCase());
const locName = (id) => nm(((B.ENV && B.ENV.locs) || []).find((l) => l.id === id) || { name_bn: '#' + id });
const defLoc = () => (LOCS()[0] || {}).id;
const missingFn = (e) => e && /could not find the function|does not exist|schema cache|404/i.test(e.message || '');
const lockPage = (title, back) => shell(title, `<div class="lockcard">${LOCK}<span>${esc(T('lockedPage'))}</span></div>`, back || true);

// bank as a 4th payment mode on purchase screens only (pay.js stays untouched): wrap B.pay.html for states flagged st.bank
(() => {
  const pay = B.pay; if (!pay || pay.__bank) return; pay.__bank = true; const h0 = pay.html;
  pay.html = function (st) {
    let h = h0.call(this, st); if (!st.bank) return h;
    const parts = h.split('<div class="payrow">');
    for (let i = 1; i < parts.length; i++) if (st.rows[i - 1] && st.rows[i - 1].mode === 'bank') parts[i] = parts[i].replace('<b></b>', '<b>' + esc(modeL('bank')) + '</b>');
    h = parts.join('<div class="payrow">').replace(/<div style="flex:1"><label>[^<]*<\/label><input data-pay="\d+\.given"[^>]*><\/div>/g, '');
    return h.replace('<button type="button" class="tog ', `<button type="button" class="tog" data-act="pay_add" data-m="bank">＋ ${esc(T('addBank'))}</button><button type="button" class="tog `);
  };
})();
const newPay = (getTotal) => { const st = B.pay.create(getTotal); st.rows = []; st.bank = true; st.moneyEvent = 'purchase_payment'; if (B.moneySrc) B.moneySrc.prefetch('purchase_payment', null); return st; };       // purchases start "all on credit"

// ================= bills list =================
async function listView() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  const loc = PL.f.loc === '' ? null : Number(PL.f.loc);
  const r = await sb.rpc('purchase_list', { p_loc: loc, p_from: PL.f.from || null, p_to: PL.f.to || null, p_supplier: PL.f.supplier || null, p_status: PL.f.status || null, p_limit: 100 });
  PL.err = r.error; PL.rows = r.error ? [] : (r.data || []);
  const [ge, gr] = await Promise.all([grant('purchase_entry', defLoc()), grant('purchase_return', defLoc())]); PL.ge = ge; PL.gr = gr;
  if (r.error && !missingFn(r.error) && /not allowed/.test(r.error.message || '')) return lockPage(T('title'));
  drawList(ge, gr, missingFn(r.error));
}
function drawList(ge, gr, missing) {
  const mode = npMode(), fc = Object.values(PL.f).filter(Boolean).length;
  const btn = (ok, act, label, primary) => ok ? `<button class="${primary ? 'primary' : ''}" data-act="${act}">${esc(label)}</button>` : mode === 'lock' ? `<button disabled aria-label="${esc(label + ' · ' + T('noperm'))}">${LOCK.replace('<svg', '<svg width="16" height="16"')} ${esc(label)}</button>` : '';
  shell(T('title'), `<div class="p2-bar"><button id="pl_fb" class="p2-fb" data-act="pu_filter" style="flex:1">⎚ ${esc(T('filter'))}${fc ? `<span class="cnt">${fc}</span>` : ''}</button><button data-act="go" data-v="payables">${esc(T('payables'))}</button></div>
    ${missing ? `<div class="notice bad">${esc(T('sqlMissing'))}</div>` : ''}
    <div id="pl_list">${PL.rows.slice(0, PL.shown).map((b, i) => {
      const bar = b.status === 'void' ? 'bad' : b.status === 'draft' ? 'info' : b.kind === 'bill' && Number(b.due) > 0 ? 'warn' : 'ok';
      return `<div class="card item mk ${bar}" data-act="pu_open" data-v="${esc(b.id)}" role="button" tabindex="0"><div><div class="nm">${esc(b.supplier_name)}</div>
        <div class="muted" style="font-size:.85rem">${esc(b.bill_no || '—')} · ${esc(dshort(b.bill_date))}${LOCS().length > 1 ? ' · ' + esc(locName(b.location_id)) : ''} · ${b.n_lines} ${esc(T('nLines'))}</div>
        <span class="chip ${SB[b.status] || ''}">${esc(stLabel(b.status))}</span>${b.kind === 'return' ? ` <span class="chip">${esc(T('ret'))}</span>` : ''}</div>
        <div class="pr"><button type="button" class="mini s2-dots" data-act="pu_menu" data-i="${i}" aria-label="${esc(T('more'))}">⋮</button><b>${esc(money(b.total))}</b>${b.kind === 'bill' && b.status === 'posted' && Number(b.due) > 0 ? `<div class="amt-bad" style="font-size:.85rem">${esc(T('due'))} ${esc(money(b.due))}</div>` : ''}</div></div>`; }).join('')
      || `<p class="muted center">${esc(T('none'))}</p>`}${PL.rows.length > PL.shown ? `<button class="full" data-act="pu_more">…</button>` : ''}</div>
    <div class="s2-bar">${btn(gr, 'pu_new_ret', T('newRet'), false)}${btn(ge, 'pu_new', T('newBill'), true)}</div>`, true);
}
function filterSheet() {
  const sp = sups().map((s) => [s.id, s.name]);
  openSheet(`<h2>${esc(T('filter'))}</h2><div class="stack">
    <div><label for="pf_sup">${esc(T('supplier'))}</label><select id="pf_sup"><option value="">${esc(T('all'))}</option>${optHTML(sp, PL.f.supplier)}</select></div>
    <div><label for="pf_st">${esc(T('status'))}</label><select id="pf_st"><option value="">${esc(T('all'))}</option>${optHTML([['draft', T('draft')], ['posted', T('posted')], ['void', T('void_')]], PL.f.status)}</select></div>
    ${LOCS().length > 1 || allLocs() ? `<div><label for="pf_loc">${esc(T('location'))}</label><select id="pf_loc"><option value="">${esc(T('allLoc'))}</option>${optHTML(LOCS().map((l) => [l.id, nm(l)]), PL.f.loc)}</select></div>` : ''}
    <div class="row"><div style="flex:1"><label for="pf_from">${esc(T('from'))}</label><input id="pf_from" type="date" value="${esc(PL.f.from)}"></div><div style="flex:1"><label for="pf_to">${esc(T('to'))}</label><input id="pf_to" type="date" value="${esc(PL.f.to)}"></div></div>
    <div class="row"><button class="full" data-act="pu_freset">${esc(T('reset'))}</button><button class="primary full" data-act="pu_fapply">${esc(T('apply'))}</button></div></div>`);
}

// ================= editor (new bill / return / edit draft) =================
async function editor(o) {
  shell(T(o.kind === 'return' ? 'newRet' : 'newBill'), `<p class="muted">${esc(T('loading'))}</p>`, 'purchase');
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  await allItems();
  try { if (B.itemMaster) await B.itemMaster.init(); } catch (e) { /* item master not installed */ }
  let b = null;
  if (o.id) { const r = await sb.rpc('purchase_get', { p_id: o.id }); if (r.error) { if (/not allowed/.test(r.error.message || '')) return lockPage(T('title'), 'purchase'); return errToast(r.error); } b = r.data; if (b.status !== 'draft') { location.hash = '#/purchase/' + o.id; return; } }
  const kind = b ? b.kind : o.kind;
  let stagedLots = []; if (b && b.kind === 'bill') { try { const lr = await sb.rpc('receipt_lots_get', { p_bill: b.id }); if (lr && !lr.error) stagedLots = (lr.data || []).filter((x) => x.status === 'staged'); } catch (e) { stagedLots = []; } }
  F = { id: b ? b.id : null, client: b ? null : rid(), kind, loc: b ? b.location_id : defLoc(), supplier: b ? b.supplier_id : '', supName: b ? ((supById(b.supplier_id) || {}).name || b.supplier_name || '') : '', billNo: b ? b.bill_no || '' : '', date: b ? b.bill_date : today(),
    discount: b ? String(b.discount || '') : '', note: b ? b.note || '' : '', photo: b ? b.photo || null : null, reason: b ? b.reason_code || '' : '', ref: b ? b.ref_bill_id || '' : (o.ref || ''), busy: false, refBills: [],
    lines: b ? (b.lines || []).map((l) => { const it = ITEMS_ALL.find((i) => i.id === l.item_id); const lt = stagedLots.find((x, ix) => x.line_no === (b.lines || []).indexOf(l) + 1); return { item_id: l.item_id || null, item: it ? U.itemText(it) : '', desc: l.description || '', qty: String(l.qty), unit: l.unit || '', cost: String(l.unit_cost), lot: lt ? lt.lot_no || '' : '', lotexp: lt && lt.expiry ? String(lt.expiry).slice(0, 10) : '' }; }) : [{ item_id: null, item: '', desc: '', qty: '', unit: '', cost: '' }] };
  F.canPay = kind === 'bill' && await grant('supplier_pay', F.loc);
  F.pay = newPay(() => totals().total);
  await loadConvP();
  if (F.ref && !F.supplier) { const r = await sb.rpc('purchase_get', { p_id: F.ref }); if (!r.error && r.data) { F.supplier = r.data.supplier_id; F.supName = (supById(r.data.supplier_id) || {}).name || r.data.supplier_name; F.loc = r.data.location_id; } }
  if (B.pay.loadWallets) B.pay.loadWallets();
  drawEditor(); loadRefBills();
}
const totals = () => { const sub = r2(F.lines.reduce((s, l) => s + (nnum(l.qty) > 0 && nnum(l.cost) >= 0 ? r2(nnum(l.qty) * nnum(l.cost)) : 0), 0)); const d = nnum(F.discount); const disc = d > 0 ? d : 0; return { sub, disc, total: r2(Math.max(0, sub - disc)) }; };
function lineHTML(l, i) {
  const items = ITEMS_ALL, it = l.item_id ? items.find((x) => x.id === l.item_id) : null; l._ri = !!it;
  return `<div class="rowcard" data-li="${i}"><div class="rc-h"><b>#${i + 1}</b>${F.lines.length > 1 ? `<button type="button" class="mini" data-act="pu_delline" data-i="${i}" aria-label="✕">✕</button>` : ''}</div><div class="stack">
    <div><label>${esc(T('item'))}</label><div class="p2-inl"><input data-ln="${i}.item" list="pu_dl" autocomplete="off" value="${esc(l.item)}" placeholder="${esc(T('itemph'))}">${scanOn() ? `<button type="button" class="mini" data-act="pu_scan" data-i="${i}" aria-label="${esc(T('scan'))}">▮▮ ${esc(T('scan'))}</button>` : ''}</div></div>
    ${it && it.item_type === 'asset' ? `<div class="hint">${esc(lab(L('সম্পদ: স্টকে নয়, সম্পদ-খাতায় যোগ হবে', 'Asset: goes to the asset register, not to stock', 'Asset: stock এ নয়, asset register এ যোগ হবে')))}</div>` : ''}
    ${it ? '' : `<div><label>${esc(T('desc'))}</label><input data-ln="${i}.desc" autocomplete="off" value="${esc(l.desc)}"></div>`}
    <div class="row"><div style="flex:1"><label>${esc(T('qty'))}</label><input data-ln="${i}.qty" inputmode="decimal" value="${esc(l.qty)}"></div>
      <div style="flex:1"><label>${esc(T('unit'))}</label><select data-ln="${i}.unit"><option value="">${esc(it ? unitLabel(it.unit) || T('itemUnit') : T('itemUnit'))}</option>${optHTML(lists('units').map((r) => [r.value_code, lab(rowL(r))]), l.unit)}</select></div>
      <div style="flex:1"><label>${esc(T('ucost'))}</label><input data-ln="${i}.cost" inputmode="decimal" value="${esc(l.cost)}"></div></div>
    ${it && F.kind === 'bill' && it.tracked && it.item_type !== 'asset' ? `<div class="row"><div style="flex:1"><label>${esc(T('lotNo'))}${B.rule('receipt_lot_required', false) === true ? ' *' : ''}</label><input data-ln="${i}.lot" maxlength="40" autocomplete="off" value="${esc(l.lot || '')}"></div>
      <div style="flex:1"><label>${esc(T('lotExp'))}${B.rule('receipt_expiry_required', false) === true ? ' *' : ''}</label><input data-ln="${i}.lotexp" type="date" value="${esc(l.lotexp || '')}"></div></div><div class="hint">${esc(T('lotHint'))}</div>` : ''}
    <div class="row between"><span class="muted">${esc(T('amount'))}</span><b data-amt="${i}">${nnum(l.qty) > 0 && nnum(l.cost) >= 0 ? esc(money(r2(nnum(l.qty) * nnum(l.cost)))) : '—'}</b></div>
    <div class="hint s2-pv" data-pv="${i}" aria-live="polite"></div></div></div>`;
}
function drawEditor() {
  const ret = F.kind === 'return', locs = LOCS(), tt = totals();
  const reasons = lists('return_reasons').length ? lists('return_reasons').map((r) => [r.value_code, lab(rowL(r))]) : [['damaged', 'Damaged'], ['wrong_item', 'Wrong item'], ['quality', 'Poor quality'], ['excess', 'Excess delivered'], ['other', 'Other']];
  shell(T(ret ? 'newRet' : F.id ? 'editBill' : 'newBill'), `<div class="stack">
    ${locs.length > 1 ? locSel('pe_loc', T('location'), F.loc, locs) : `<input type="hidden" id="pe_loc" value="${F.loc ?? ''}">`}
    <div><label for="pe_sup">${esc(T('supplier'))} *</label><input id="pe_sup" list="pe_sup_dl" autocomplete="off" value="${esc(F.supName)}" placeholder="${esc(T('supPh'))}"><datalist id="pe_sup_dl">${sups().map((s) => `<option value="${esc(s.name)}"></option>`).join('')}</datalist></div>
    <div class="row"><div style="flex:1"><label for="pe_no">${esc(T('billNo'))}</label><input id="pe_no" autocomplete="off" value="${esc(F.billNo)}"></div><div style="flex:1"><label for="pe_date">${esc(T('date'))}</label><input id="pe_date" type="date" value="${esc(F.date)}"></div></div>
    ${ret ? `<div><label for="pe_reason">${esc(T('reason'))} *</label><select id="pe_reason"><option value="">—</option>${optHTML(reasons, F.reason)}</select></div><div><label for="pe_ref">${esc(T('againstBill'))}</label><select id="pe_ref"><option value="">—</option></select></div>` : ''}
    <datalist id="pu_dl">${ITEMS_ALL.map((i) => `<option value="${esc(U.itemText(i))}"></option>`).join('')}</datalist>
    <h3 style="margin:6px 0 0">${esc(T('lines'))}</h3><div id="pe_lines">${F.lines.map(lineHTML).join('')}</div><button type="button" class="full" data-act="pu_addline">＋ ${esc(T('addLine'))}</button>${!ret && B.itemMaster && B.itemMaster.canNew() ? `<button type="button" class="full" data-act="pu_newitem">＋ ${esc(lab(L('নতুন আইটেম (সম্পদ) তালিকায় যোগ', 'New item (asset) added to the item list', 'নতুন Item (Asset) list এ যোগ')))}</button>` : ''}
    <div><label for="pe_disc">${esc(T('discount'))}</label><input id="pe_disc" inputmode="decimal" value="${esc(F.discount)}"></div>
    <div class="card stack" id="pe_tot">${totHTML(tt)}</div>
    ${F.canPay && !ret ? `<h3 style="margin:6px 0 0">${esc(T('payNow'))}</h3><div id="pe_pay">${B.pay.html(F.pay)}</div><div class="hint">${esc(T('payHint'))}</div>` : ''}
    <div><label for="pe_note">${esc(T('note'))}</label><input id="pe_note" autocomplete="off" value="${esc(F.note)}"></div>
    <div><label>${esc(T('photo'))}</label><div class="s2-ph" id="pe_ph"></div></div>
    <div class="s2-bar"><button data-act="pu_save" id="pe_save">${esc(T('saveDraft'))}</button><button class="primary" data-act="pu_post" id="pe_post">${esc(T(ret ? 'postRet' : 'post'))}</button></div></div>`, 'purchase');
  drawEdPhoto(); const rs = $('#pe_ref'); if (rs) fillRef();
  wireUnits(); if (ret) wireReason('pe_reason', false);
  drawPreviews();
}
// shared editable lists on the pickers (units per line, return reasons); old arrays stay the fallback when the list table is missing
function wireUnits() { const lc = B.listctl; if (!lc) return; document.querySelectorAll('#pe_lines select[data-ln$=".unit"]').forEach((s) => lc.enhance(s, 'units', { otherBlank: true, form: 'PURCHASE', ctx: { field: 'purchase_unit' } })); }
function wireReason(id, optional) {
  const lc = B.listctl, sel = $('#' + id); if (!lc || !sel) return;
  const oth = lists('return_reasons').some((r) => r.value_code === 'other' && r.active);
  lc.enhance(sel, 'return_reasons', optional ? { otherBlank: true, form: 'PURCHASE', ctx: { field: 'return_reason' } } : oth ? { otherValue: 'other', form: 'PURCHASE', ctx: { field: 'return_reason' } } : { noOther: true, form: 'PURCHASE' });
}
const totHTML = (tt) => `<div class="row between"><span>${esc(T('subtotal'))}</span><b>${esc(money(tt.sub))}</b></div>${tt.disc ? `<div class="row between"><span>${esc(T('discount'))}</span><b>− ${esc(money(tt.disc))}</b></div>` : ''}<div class="row between"><span>${esc(T('total'))}</span><b class="mnum">${esc(money(tt.total))}</b></div>`;
// ---- stock-effect preview per line (client side from stock_levels + the unit conversions; nothing is invented) ----
const scanOn = () => { try { return !!(B.barcode && B.barcode.enabled()); } catch (e) { return false; } };
let CONVP = null; const PV = { stock: new Map(), pend: new Set() };
async function loadConvP() { if (CONVP) return; try { const r = await sb.from('unit_conversions').select('*'); CONVP = r.error ? [] : (r.data || []).filter((c) => c.active !== false); } catch (e) { CONVP = []; } }
function hop(itemId, from, to) {            // same rule as the server: an item rule beats a global one, direct beats inverse
  const rows = (CONVP || []).filter((c) => (c.item_id === itemId || !c.item_id) && ((c.from_unit === from && c.to_unit === to) || (c.from_unit === to && c.to_unit === from)));
  rows.sort((a, b) => (a.item_id ? 0 : 1) - (b.item_id ? 0 : 1) || (a.from_unit === from ? 0 : 1) - (b.from_unit === from ? 0 : 1));
  const c = rows[0]; return c ? (c.from_unit === from ? Number(c.factor) : 1 / Number(c.factor)) : null;
}
function factorBase(it, unit) { const b = it.base_unit || it.unit, u = unit || it.unit; if (!u || !b || u === b) return 1; return hop(it.id, u, b); }
async function ensureStock(itemId) {
  const k = F.loc + '|' + itemId; if (PV.stock.has(k) || PV.pend.has(k)) return; PV.pend.add(k);
  let row = null;
  try { const r = await sb.rpc('stock_levels', { p_loc: F.loc, p_filters: { item_ids: [itemId], include_zero: true } }); row = r && !r.error && r.data && r.data[0]; } catch (e) { row = null; }
  PV.pend.delete(k); PV.stock.set(k, row ? { qty: Number(row.qty), avg: row.avg_cost === null || row.avg_cost === undefined ? null : Number(row.avg_cost), base: row.base_unit } : { none: true }); drawPreviews();
}
function pvText(l, run, net) {
  const it = l.item_id ? ITEMS_ALL.find((x) => x.id === l.item_id) : null; if (!it) return '';
  if (!it.tracked) return T('pvUntracked');
  const q = nnum(l.qty); if (!(q > 0)) return '';
  const f = factorBase(it, l.unit); if (f === null || !(f > 0)) return T('pvNeed') + ': ' + T('pvUnit');
  const st = PV.stock.get(F.loc + '|' + it.id); if (!st) { ensureStock(it.id); return T('pvLoad'); }
  if (st.none) return '';
  const base = st.base || it.base_unit || it.unit, sign = F.kind === 'return' ? -1 : 1, cur = run.get(it.id) || { qty: st.qty, avg: st.avg }, bq = q * f, nq = cur.qty + sign * bq;
  let txt = `${sign > 0 ? '+' : '−'}${U.q4(bq)} ${unitLabel(base)} → ${T('pvStock')} ${U.q4(nq)} ${unitLabel(base)} ${T('pvAt')} ${locName(F.loc)}`, navg = cur.avg;
  if (sign > 0) {
    const c = nnum(l.cost);
    if (c >= 0) {
      const ucb = c / f * net;
      navg = cur.qty <= 0 ? ucb : cur.avg === null ? null : (cur.qty * cur.avg + bq * ucb) / (cur.qty + bq);
      txt += ' · ' + T('pvAvg') + ': ' + (navg === null ? T('pvNeed') + ' (' + T('pvCost') + ')' : money(Math.round(navg * 100) / 100));
    }
  }
  run.set(it.id, { qty: nq, avg: navg }); return txt;
}
function drawPreviews() {
  if (!F) return; const run = new Map(), tt = totals(), net = tt.sub > 0 ? (tt.sub - tt.disc) / tt.sub : 1;
  F.lines.forEach((l, i) => { const el = document.querySelector(`[data-pv="${i}"]`); if (el) el.textContent = pvText(l, run, net); });
}
function drawEdPhoto() {
  const box = $('#pe_ph'); if (!box) return;
  box.innerHTML = (F.photo ? `<img alt="" width="84" height="84" id="pe_img">` : '') + `<label class="phadd">📷 ${esc(T('addPhoto'))}<input type="file" accept="image/*" hidden id="pe_file"></label>`;
  if (F.photo) U.thumb($('#pe_img'), F.photo);
}
async function loadRefBills() {
  if (F.kind !== 'return' || !F.supplier) { F.refBills = []; fillRef(); return; }
  const r = await sb.rpc('purchase_list', { p_loc: null, p_from: null, p_to: null, p_supplier: F.supplier, p_status: 'posted', p_limit: 100 });
  F.refBills = r.error ? [] : (r.data || []).filter((x) => x.kind === 'bill'); fillRef();
}
function fillRef() { const s = $('#pe_ref'); if (!s) return; s.innerHTML = `<option value="">—</option>` + optHTML(F.refBills.map((b) => [b.id, (b.bill_no || '—') + ' · ' + dshort(b.bill_date) + ' · ' + money(b.total)]), F.ref); }
function syncFixed() {
  if (!F) return;
  F.loc = Number(($('#pe_loc') || {}).value) || F.loc; F.billNo = (($('#pe_no') || {}).value || '').trim(); F.date = ($('#pe_date') || {}).value || ''; F.note = (($('#pe_note') || {}).value || '').trim(); F.discount = ($('#pe_disc') || {}).value || '';
  F.reason = ($('#pe_reason') || {}).value || ''; F.ref = ($('#pe_ref') || {}).value || '';
  F.supName = (($('#pe_sup') || {}).value || '').trim(); const s = supByName(F.supName); F.supplier = s ? s.id : '';
}
function payload() {
  syncFixed();
  if (!F.supplier) { toast(T('needSup')); return null; } if (!F.date) { toast(T('needDate')); return null; }
  if (F.kind === 'return' && !F.reason) { toast(T('needReason')); return null; }
  const lines = [], lotsOut = [];
  for (const l of F.lines) {
    const it = l.item_id ? ITEMS_ALL.find((x) => x.id === l.item_id) : null, hasAny = l.item_id || l.desc.trim() || l.qty || l.cost; if (!hasAny) continue;
    const q = nnum(l.qty), c = nnum(l.cost);
    if (!(q > 0) || !(c >= 0)) { toast(T('badLine')); return null; }
    if (!it && !l.desc.trim()) { toast(T('needLine')); return null; }
    const o = { qty: q, unit_cost: c }; if (it) o.item_id = it.id; else o.description = l.desc.trim(); if (l.unit) o.unit = l.unit; lines.push(o);
    if (F.kind === 'bill' && it && it.tracked && it.item_type !== 'asset') {          // RPT-B3: the supplier lot and expiry of this stock line (optional unless the owner switched them on)
      const lot = (l.lot || '').trim(), lx = l.lotexp || '';
      if (B.rule('receipt_lot_required', false) === true && !lot) { toast(T('lotNeed') + ' · ' + it.code); return null; }
      if (B.rule('receipt_expiry_required', false) === true && !lx) { toast(T('expNeed') + ' · ' + it.code); return null; }
      if (lot || lx) lotsOut.push({ line_no: lines.length, lot_no: lot || null, expiry: lx || null });
    }
  }
  if (!lines.length) { toast(T('needLine')); return null; }
  const tt = totals(); if (tt.disc > tt.sub) { toast(T('badDisc')); return null; }
  F._lots = lotsOut;
  return lines;
}
async function saveDraft(post) {
  const lines = payload(); if (!lines) return null;
  const r = await sb.rpc('save_purchase', { p_client: F.client, p_id: F.id, p_supplier: F.supplier, p_loc: F.loc, p_bill_no: F.billNo || null, p_bill_date: F.date, p_lines: lines, p_discount: totals().disc, p_note: F.note || null, p_photo: F.photo,
    p_kind: F.kind, p_ref_bill: F.kind === 'return' ? (F.ref || null) : null, p_reason: F.kind === 'return' ? F.reason : null });
  if (r.error) { errToast(r.error, { grant: F.kind === 'return' ? 'purchase_return' : 'purchase_entry', loc: F.loc, context: { action: 'save_purchase' } }); return null; }
  F.id = r.data.id; F.client = null;            // later saves are updates of this draft by id (a client id would just return the old draft)
  if (F.kind === 'bill') {                      // RPT-B3: stage the lots (an empty list clears old ones); a database without phase 430 simply has no such function
    try {
      const lr = await sb.rpc('receipt_lots_stage', { p_bill: F.id, p_lots: F._lots || [] });
      if (lr && lr.error && !/PGRST202|Could not find|does not exist/i.test(String(lr.error.code || '') + ' ' + (lr.error.message || ''))) { toast((lr.error.message || '').replace(/^.*?:\s*/, '')); return null; }
    } catch (e) { /* lots are optional */ }
  }
  return r.data;
}
async function doSave(btn) {
  if (F.busy) return; F.busy = true; btn.disabled = true;
  try { const d = await saveDraft(); if (d) { toast(d.dup ? T('dup') : T('saved')); location.hash = '#/purchase/' + F.id; } } catch (e) { fail(e); } finally { F.busy = false; btn.disabled = false; }
}
async function doPost(btn) {
  if (F.busy) return; if (F.canPay && F.kind === 'bill') { const pe = B.pay.check(F.pay); if (pe) return toast(pe === 'overpaid' ? lab(U.ERR.overpaid) : T('walletNeeded')); }
  F.busy = true; btn.disabled = true;
  try {
    const d = await saveDraft(); if (!d) return;
    await postBill(F.id, F.canPay && F.kind === 'bill' ? B.pay.list(F.pay) : [], F.kind, F.loc);
  } catch (e) { fail(e); } finally { F.busy = false; btn.disabled = false; }
}
async function postBill(id, list, kind, loc) {
  const r = await sb.rpc('post_purchase', { p_id: id, p_payments: list.length ? list : null });
  if (r.error) { errToast(r.error, { grant: list.length && /not allowed/.test(r.error.message || '') && kind === 'bill' ? 'supplier_pay' : kind === 'return' ? 'purchase_return' : 'purchase_entry', loc, context: { action: 'post_purchase', bill: id } }); return false; }
  if (kind === 'bill') { try { await sb.rpc('receipt_lots_apply', { p_bill: id }); } catch (e) { /* phase 430 not installed, or nothing staged */ } }      // RPT-B3: makes the stock batches of the lots (idempotent; the server hook may already have)
  toast(r.data && r.data.dup ? T('dup') : T('posted_ok')); closeSheet(); const target = '#/purchase/' + id, same = location.hash === target; location.hash = target; if (same) detail(id); return true;
}

// ================= bill detail =================
let redrawing = false, CUR = null; const PS = { st: null, ok: false };
async function detail(id) {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, 'purchase');
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  await allItems();
  const r = await sb.rpc('purchase_get', { p_id: id });
  if (r.error) { if (/not allowed/.test(r.error.message || '')) return lockPage(T('title'), 'purchase'); errToast(r.error); return; }
  const b = r.data; CUR = b;
  let lots = []; if (b.kind === 'bill') { try { const lr = await sb.rpc('receipt_lots_get', { p_bill: b.id }); if (lr && !lr.error) lots = lr.data || []; } catch (e) { lots = []; } }
  const [gv, gr, ge, gp] = await Promise.all([grant('purchase_void', b.location_id), grant('purchase_return', b.location_id), grant('purchase_entry', b.location_id), grant('supplier_pay', b.location_id)]);
  const mode = npMode(), ret = b.kind === 'return';
  const act = (ok, a, label, cls, extra = '') => ok ? `<button class="${cls || ''}" data-act="${a}" ${extra}>${esc(label)}</button>` : mode === 'lock' ? `<button disabled>${LOCK.replace('<svg', '<svg width="16" height="16"')} ${esc(label)}</button>` : '';
  const bar = [];
  if (b.status === 'draft') { bar.push(act(ge || (ret && gr), 'pu_vdraft', T('voidDraft'), 'danger'), act(ge || (ret && gr), 'pu_edit', T('edit'), ''), act(ge || (ret && gr), 'pu_postd', T(ret ? 'postRet' : 'post'), 'primary')); }
  else if (b.status === 'posted') { bar.push(act(gv, 'pu_void', T('voidBill'), 'danger'), gp ? `<button data-act="pu_mrefund" data-s="${esc(b.supplier_id)}" data-n="${esc(b.supplier_name)}">${esc(T('refund'))}</button>` : ''); if (!ret) { bar.push(act(gr, 'pu_retvs', T('returnVs'), ''), gp && Number(b.due) > 0 ? `<button class="primary" data-act="pu_paysup">${esc(T('paySup'))}</button>` : ''); } }
  shell(`${b.supplier_name}`, `<div class="card stack mk ${SB[b.status] || ''}"><div class="row between"><span class="chip ${SB[b.status] || ''}">${esc(stLabel(b.status))}</span>${ret ? `<span class="chip">${esc(T('ret'))}</span>` : ''}</div>
      <div class="muted">${esc(b.bill_no || '—')} · ${esc(dshort(b.bill_date))} · ${esc(locName(b.location_id))}${b.created_staff ? ' · ' + esc(T('by')) + ' ' + esc(b.created_staff) : ''}</div>
      ${b.reason_code ? `<div class="muted">${esc(T('reason'))}: ${esc(lab(rowL(lists('return_reasons').find((x) => x.value_code === b.reason_code) || { label_bn: b.reason_code })))}</div>` : ''}
      ${b.note ? `<div>${esc(b.note)}</div>` : ''}${b.void_note ? `<div class="notice bad">${esc(T('voided'))}: ${esc(b.void_note)}</div>` : ''}</div>
    <div class="card">${(b.lines || []).map((l) => { const it = ITEMS_ALL && l.item_id ? ITEMS_ALL.find((x) => x.id === l.item_id) : null;
      return `<div class="s2-led"><div>${esc(it ? nm(it) : l.description || '—')}<div class="sub">${U.q4(l.qty)} ${esc(unitLabel(l.unit))} × ${esc(money(l.unit_cost))}</div></div><div class="q">${esc(money(l.amount))}</div></div>`; }).join('')}
      <div class="row between" style="margin-top:8px"><span>${esc(T('subtotal'))}</span><b>${esc(money(b.subtotal))}</b></div>
      ${Number(b.discount) ? `<div class="row between"><span>${esc(T('discount'))}</span><b>− ${esc(money(b.discount))}</b></div>` : ''}
      <div class="row between"><span>${esc(T('total'))}</span><b class="mnum">${esc(money(b.total))}</b></div>
      ${b.status === 'posted' && !ret ? `<div class="row between"><span>${esc(T('paid'))}</span><b>${esc(money(b.paid))}</b></div><div class="row between"><span>${esc(T('due'))}</span><b class="${Number(b.due) > 0 ? 'amt-bad' : ''}">${esc(money(b.due))}</b></div>` : ''}</div>
    ${lots.length ? `<div class="card" data-lots="1"><h3>${esc(T('lotsTitle'))}</h3>${lots.map((x) => { const li = (b.lines || [])[x.line_no - 1], it2 = li && ITEMS_ALL && li.item_id ? ITEMS_ALL.find((y) => y.id === li.item_id) : null;
        return `<div class="s2-led"><div>${esc(it2 ? nm(it2) : '#' + x.line_no)}<div class="sub">${x.lot_no ? esc(x.lot_no) : esc(lab(L('লট নম্বর লেখা নেই', 'lot number: data not captured', 'lot no লেখা নেই')))} · ${x.expiry ? esc(String(x.expiry).slice(0, 10)) : esc(lab(L('মেয়াদ লেখা নেই', 'expiry: data not captured', 'expiry লেখা নেই')))}${x.status === 'applied' ? ' · ' + esc(T('lotBatch')) + ' #' + esc(x.batch_id) : x.status === 'no_stock' ? ' · ' + esc(T('lotNoStock')) : ' · ' + esc(T('lotStaged'))}</div></div><div class="q">${x.qty_base ? U.q4(x.qty_base) : ''}</div></div>`; }).join('')}
      ${b.status === 'posted' && lots.some((x) => x.status === 'staged') ? `<button class="full" data-act="pu_lotapply" data-v="${esc(b.id)}">${esc(T('lotApply'))}</button>` : ''}</div>` : (b.status === 'posted' && b.kind === 'bill' ? `<div class="muted">${esc(T('lotNone'))}</div>` : '')}
    ${(b.payments || []).length ? `<div class="card"><h3>${esc(T('paid'))}</h3>${b.payments.map((p) => `<div class="s2-led"><div>${esc(modeL(p.mode))}${p.wallet ? ' · ' + esc(p.wallet) : ''}${p.voided ? ` <span class="chip bad">${esc(T('void_'))}</span>` : ''}<div class="sub">${esc(dt(p.paid_at))}${p.ref ? ' · ' + esc(p.ref) : ''}</div></div><div class="q">${esc(money(p.amount))}</div></div>`).join('')}</div>` : ''}
    ${b.photo ? `<div class="card"><img id="pd_img" alt="" style="width:100%;border-radius:12px"></div>` : ''}
    <div class="s2-bar" style="flex-wrap:wrap">${bar.join('')}</div>`, 'purchase');
  if (b.photo) U.thumb($('#pd_img'), b.photo);
}
function noteSheet(title, warn, act, label, danger) {
  U.sheetStart('note');
  openSheet(`<h2>${esc(title)}</h2>${warn ? `<div class="notice warn">${esc(warn)}</div>` : ''}<div><label for="vn_note">${esc(T('voidWhy'))}</label><input id="vn_note" autocomplete="off"></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="${danger ? 'danger' : 'primary'} full" id="vn_go" data-act="${act}">${esc(label)}</button></div>`);
}
function postSheet() {
  const b = CUR; U.sheetStart('post'); const canPay = b.kind === 'bill', st = newPay(() => Number(b.total));
  grant('supplier_pay', b.location_id).then((ok) => {
    PS.st = st; PS.ok = ok && canPay;
    openSheet(`<h2>${esc(T(b.kind === 'return' ? 'postRet' : 'post'))} · ${esc(money(b.total))}</h2>${ok && canPay ? `<h3>${esc(T('payNow'))}</h3><div id="pp_pay">${B.pay.html(st)}</div><div class="hint">${esc(T('payHint'))}</div>` : ''}
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" id="pp_go" data-act="pu_postgo">${esc(T(b.kind === 'return' ? 'postRet' : 'post'))}</button></div>`);
  });
}

// ================= payables =================
const PY = { loc: undefined, rows: [], credits: [], sum: null, cur: null, st: null, client: null, rclient: null, ledger: [], busy: false };
async function payables() {
  shell(T('payables'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  if (PY.loc === undefined) PY.loc = allLocs() ? null : defLoc();
  const [d, s] = await Promise.all([sb.rpc('supplier_dues', { p_loc: PY.loc }), sb.rpc('payables_summary', { p_loc: PY.loc })]);
  if ((d.error && /not allowed/.test(d.error.message || '')) || (s.error && /not allowed/.test(s.error.message || ''))) return lockPage(T('payables'));
  const miss = missingFn(d.error) || missingFn(s.error);
  if ((d.error || s.error) && !miss) return errToast(d.error || s.error);
  PY.rows = d.error ? [] : (d.data || []); const sm = s.data; PY.sum = Array.isArray(sm) ? sm[0] : sm;
  PY.credits = []; if (PY.loc === null || PY.loc === undefined) { try { const c = await sb.rpc('supplier_credits'); PY.credits = c && !c.error && c.data ? c.data : []; } catch (e) { PY.credits = []; } }     // phase12; company-wide only
  drawPayables(miss);
}
function drawPayables(miss) {
  const s = PY.sum || {}, locs = LOCS();
  shell(T('payables'), `${locs.length > 1 || allLocs() ? `<div style="margin-bottom:8px"><select id="py_loc" aria-label="${esc(T('location'))}">${allLocs() ? `<option value="">${esc(T('allLoc'))}</option>` : ''}${optHTML(locs.map((l) => [l.id, nm(l)]), PY.loc)}</select></div>` : ''}
    ${miss ? `<div class="notice bad">${esc(T('sqlMissing'))}</div>` : ''}
    <div class="plate"><div class="pl-k">${esc(T('totPay'))}</div><div class="pl-v"><span class="cur">৳</span>${Number(s.total_payable || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}</div><div class="pl-s">${s.suppliers_owed || 0} ${esc(T('nSup'))}${s.oldest ? ' · ' + esc(T('oldest')) + ' ' + esc(dshort(s.oldest)) : ''}</div></div>
    <div class="s2-sum">${Number(s.overdue) > 0 ? `<div class="stat mk bad"><div class="k">${esc(T('overdue'))} · ${s.overdue_suppliers || 0}</div><div class="v amt-bad">${esc(money(s.overdue))}</div></div>` : ''}${Number(s.credit_total) > 0 ? `<div class="stat"><div class="k">${esc(T('adv'))}</div><div class="v">${esc(money(s.credit_total))}</div></div>` : ''}</div>
    ${PY.rows.some((x) => x.credit_days === null || x.credit_days === undefined) ? `<div class="notice warn" id="py_nocredit">${esc(T('noCreditNote'))}</div>` : ''}
    <div id="py_list">${PY.rows.map((x, i) => { const od = Number(x.overdue) > 0;
      return `<div class="card item mk ${od ? 'bad' : ''}" data-act="py_open" data-i="${i}" role="button" tabindex="0"><div><div class="nm">${esc(x.name)}</div>
        <div class="muted" style="font-size:.85rem">${esc(x.mobile || '')}${x.oldest ? ` · ${days(x.oldest)} ${esc(T('daysOld'))}` : ''}</div>
        <div>${x.credit_days !== null && x.credit_days !== undefined ? `<span class="chip">${x.credit_days} ${esc(T('creditDays'))}</span> ` : `<span class="chip warn">${esc(T('noCredit'))}</span> `}${od ? `<span class="chip bad">${esc(T('overdue'))} ${esc(money(x.overdue))}</span>` : ''}</div></div>
        <div class="pr"><button type="button" class="mini s2-dots" data-act="py_menu" data-i="${i}" aria-label="${esc(T('more'))}">⋮</button><b>${esc(money(x.balance))}</b></div></div>`; }).join('') || `<p class="muted center">${esc(T('noDues'))}</p>`}</div>
    ${PY.credits.length ? `<h3 style="margin:14px 0 6px">${esc(T('creditList'))}</h3><div id="py_credits">${PY.credits.map((x, i) => `<div class="card item mk ok" data-act="py_copen" data-i="${i}" role="button" tabindex="0"><div><div class="nm">${esc(x.name)}</div><div class="muted" style="font-size:.85rem">${esc(x.mobile || '')}</div></div>
      <div class="pr"><button type="button" class="mini s2-dots" data-act="py_cmenu" data-i="${i}" aria-label="${esc(T('more'))}">⋮</button><b>${esc(money(x.credit))}</b></div></div>`).join('')}</div>` : ''}`, true);
}
async function ledger(i, fromCredit) {
  const x = fromCredit ? (PY.credits[i] ? { supplier_id: PY.credits[i].supplier_id, name: PY.credits[i].name, mobile: PY.credits[i].mobile, balance: -Number(PY.credits[i].credit) } : null) : PY.rows[i]; if (!x) return; PY.cur = x; PY.client = rid(); PY.rclient = rid(); PY.busy = false;
  const loc = PY.loc === undefined ? null : PY.loc;
  const [lr, ob, gp] = await Promise.all([sb.rpc('supplier_ledger', { p_supplier: x.supplier_id, p_loc: loc }), sb.rpc('supplier_open_bills', { p_supplier: x.supplier_id, p_loc: loc }), grant('supplier_pay', loc === null ? defLoc() : loc)]);
  if (lr.error) return errToast(lr.error);
  const rows = lr.data || [], open = ob.error ? [] : (ob.data || []);
  const canVoid = {}; for (const l of [...new Set(rows.filter((e) => e.kind === 'payment' || e.kind === 'refund').map((e) => e.location_id))]) canVoid[l] = await grant('purchase_void', l);
  const bal = Number(x.balance), mode = npMode();
  PY.st = B.pay.create(() => bal); PY.st.rows = [{ mode: 'cash', amount: '', wallet: '', ref: '', given: '', auto: false }]; PY.st.bank = true; PY.st.moneyEvent = 'supplier_payment'; if (B.moneySrc) await B.moneySrc.prefetch('supplier_payment', null);
  if (B.pay.loadWallets) B.pay.loadWallets();
  const KL = { opening: 'opening', bill: 'kBill', return: 'kReturn', payment: 'kPayment', paid: 'kPaid', refund: 'kRefund' };
  openSheet(`<h2>${esc(x.name)}</h2><div class="muted">${esc(x.mobile || '')}</div>
    <div class="row between" style="margin:8px 0"><span>${esc(T('balance'))}</span><b class="mnum">${esc(money(bal))}</b></div>
    ${gp && bal > 0 ? `<h3>${esc(T('payTitle'))}</h3><div class="notice ok">${esc(T('payOldest'))}</div>
      ${locs2()}<div id="py_pay">${B.pay.html(PY.st)}</div><div><label for="py_note">${esc(T('note'))}</label><input id="py_note" autocomplete="off"></div>
      <button class="primary full" style="margin-top:10px" data-act="py_pay">${esc(T('pay'))}</button>` : bal > 0 && mode === 'lock' ? `<div class="s2-lockrow">${LOCK}<span>${esc(T('payTitle'))} · ${esc(T('noperm'))}</span></div>` : ''}
    ${bal < 0 && gp ? `<button class="primary full" style="margin-top:10px" data-act="py_refund_open">${esc(T('refund'))}</button>` : bal < 0 && mode === 'lock' ? `<div class="s2-lockrow">${LOCK}<span>${esc(T('refund'))} · ${esc(T('noperm'))}</span></div>` : ''}
    ${open.length ? `<h3 style="margin-top:14px">${esc(T('openBills'))}</h3>${open.map((o) => `<div class="s2-led"><div>${esc(o.bill_no || T('opening'))}<div class="sub">${esc(o.bill_date ? dshort(o.bill_date) : '')}${o.location_id ? ' · ' + esc(locName(o.location_id)) : ''}</div></div><div class="q">${esc(money(o.open_amt))}</div></div>`).join('')}` : ''}
    <h3 style="margin-top:14px">${esc(T('ledger'))}</h3><div>${rows.slice().reverse().map((e) => `<div class="s2-led"><div>${esc(lab(X[KL[e.kind]] || L(e.kind, e.kind, e.kind)))}${e.ref ? ' · ' + esc(e.ref) : ''}<div class="sub">${e.at && !/^-/.test(e.at) ? esc(dt(e.at)) : ''}${e.note ? ' · ' + esc(e.note) : ''}</div></div>
      <div style="text-align:end">${Number(e.debit) ? `<b>+${esc(money(e.debit))}</b>` : `<b style="color:var(--sig-ok)">−${esc(money(e.credit))}</b>`}<div class="sub">${esc(money(e.balance))}</div>
      ${e.kind === 'payment' && e.pid && canVoid[e.location_id] ? `<button class="mini" data-act="py_void" data-v="${e.pid}" aria-label="${esc(T('voidPay'))}">✕</button>` : ''}${e.kind === 'refund' && e.pid && canVoid[e.location_id] ? `<button class="mini" data-act="py_voidref" data-v="${e.pid}" aria-label="${esc(T('voidRef'))}">✕</button>` : ''}</div></div>`).join('')}</div>
    <button class="full" style="margin-top:10px" data-act="closesheet">${esc(T('close'))}</button>`);
}
const locs2 = () => (LOCS().length > 1 ? `<div style="margin-bottom:8px"><label for="py_loc2">${esc(T('location'))}</label><select id="py_loc2">${optHTML(LOCS().map((l) => [l.id, nm(l)]), PY.loc !== null && PY.loc !== undefined ? PY.loc : defLoc())}</select></div>` : `<input type="hidden" id="py_loc2" value="${defLoc() ?? ''}">`);
async function doPaySupplier(btn) {
  if (PY.busy) return; const pe = B.pay.check(PY.st); if (pe) return toast(pe === 'overpaid' ? lab(U.ERR.overpaid) : T('walletNeeded'));
  const list = B.pay.list(PY.st); if (!list.length) return toast(T('enterPay'));
  const loc = Number(($('#py_loc2') || {}).value) || defLoc();
  PY.busy = true; btn.disabled = true;
  try {
    const r = await sb.rpc('pay_supplier', { p_supplier: PY.cur.supplier_id, p_loc: loc, p_payments: list, p_client: PY.client, p_note: (($('#py_note') || {}).value || '').trim() || null });
    if (r.error) { errToast(r.error, { grant: 'supplier_pay', loc, context: { supplier: PY.cur.supplier_id } }); return; }
    PY.client = rid(); closeSheet(); toast(r.data && r.data.pending ? B.lab(B.L('অনুমোদনের অপেক্ষায়', 'Waiting for the approver', 'Approver-এর অপেক্ষায়')) : r.data && r.data.dup ? T('dup') : T('paidOk') + (r.data && r.data.balance !== undefined ? ' · ' + T('balance') + ' ' + money(r.data.balance) : '')); payables();
  } catch (e) { fail(e); } finally { PY.busy = false; btn.disabled = false; }
}

// ---- supplier refund (cash back from a supplier; phase12) ----
function refundSheet(sup, credit) {
  PY.rclient = PY.rclient || rid(); PY.cur = sup;
  const reasons = lists('return_reasons').map((r) => [r.value_code, lab(rowL(r))]);
  openSheet(`<h2>${esc(T('refundSheet'))} · ${esc(sup.name)}</h2><div class="row between"><span class="muted">${esc(T('credit'))}</span><b class="mnum">${esc(money(credit))}</b></div><div class="stack" style="margin-top:8px">
    ${locs2()}
    <div><label for="rf_amt">${esc(T('refundAmt'))}</label><input id="rf_amt" inputmode="decimal" autocomplete="off"><div class="hint">${esc(T('refundMax'))}</div></div>
    <div><label for="rf_mode">${esc(T('mode_'))}</label><select id="rf_mode">${['cash', 'mobile', 'card', 'bank'].map((m) => `<option value="${m}">${esc(modeL(m))}</option>`).join('')}</select></div>
    ${B.moneySrc ? B.moneySrc.slot('rf', 'supplier_refund', { locSel: '#py_loc2' }) : ''}
    <div id="rf_w" hidden><label for="rf_wallet">${esc(T('wallet'))}</label><input id="rf_wallet" autocomplete="off"></div>
    <div><label for="rf_ref">${esc(T('refundRef'))}</label><input id="rf_ref" autocomplete="off"></div>
    ${reasons.length ? `<div><label for="rf_reason">${esc(T('reasonOpt'))}</label><select id="rf_reason"><option value="">—</option>${optHTML(reasons, '')}</select></div>` : ''}
    <div><label for="rf_note">${esc(T('note'))}</label><input id="rf_note" autocomplete="off"></div></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="primary full" data-act="py_refund_go" data-credit="${esc(String(credit))}">${esc(T('refundSheet'))}</button></div>`);
  wireReason('rf_reason', true);
}
async function doRefund(btn) {
  const amt = nnum(($('#rf_amt') || {}).value), credit = Number(btn.dataset.credit);
  if (!(amt > 0) || !(amt <= credit + 0.00001)) return toast(T('refundMax'));
  const mode = ($('#rf_mode') || {}).value, wallet = (($('#rf_wallet') || {}).value || '').trim();
  if (mode === 'mobile' && !wallet && !(B.moneySrc && B.moneySrc.get('rf'))) return toast(T('walletNeeded'));
  const loc = Number(($('#py_loc2') || {}).value) || defLoc(), sup = PY.cur;
  await U.submit(btn, () => sb.rpc('supplier_refund', { p_supplier: sup.supplier_id, p_loc: loc, p_amount: r2(amt), p_mode: mode, p_wallet: (B.moneySrc ? B.moneySrc.tag('rf', wallet || null) : wallet) || null, p_ref: (($('#rf_ref') || {}).value || '').trim() || null,
    p_reason: (($('#rf_reason') || {}).value) || null, p_note: (($('#rf_note') || {}).value || '').trim() || null, p_client: PY.rclient }),
    () => { PY.rclient = rid(); toast(T('refundOk')); payables(); }, { grant: 'supplier_pay', loc, context: { supplier: sup.supplier_id } });
}
// open the refund sheet for a supplier of the bills list (looks the credit up first; none = nothing to refund)
async function refundFor(supplierId, name) {
  const c = await sb.rpc('supplier_credits'); const row = c && !c.error && c.data ? c.data.find((x) => x.supplier_id === supplierId) : null;
  if (!row) return toast(T('noCredit')); PY.rclient = rid(); refundSheet({ supplier_id: row.supplier_id, name: row.name || name }, Number(row.credit));
}
function menuSheet(title, items) {
  openSheet(`<h2>${esc(title)}</h2><div class="stack" style="margin-top:10px">${items.filter(Boolean).map(([act, label, attrs]) => `<button class="s2-act" data-act="${act}" ${attrs || ''}>${esc(label)}</button>`).join('')}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ================= events =================
async function view() {
  const p = location.hash.replace(/^#\/?/, '').split('/');
  if (!p[1]) return listView();
  if (p[1] === 'new') return editor({ kind: 'bill' });
  if (p[1] === 'return') return editor({ kind: 'return', ref: p[2] || '' });
  if (p[1] === 'edit') return editor({ id: p[2] });
  return detail(p[1]);
}
Object.assign(H, {
  pu_filter: filterSheet,
  pu_menu: async (a) => { const b = PL.rows[Number(a.dataset.i)]; if (!b) return;
    const [ge, gr, gp] = await Promise.all([grant('purchase_entry', b.location_id), grant('purchase_return', b.location_id), grant('supplier_pay', b.location_id)]);
    menuSheet(b.supplier_name + ' · ' + (b.bill_no || '—'), [['pu_open', T('open'), `data-v="${esc(b.id)}"`],
      b.status === 'draft' && (b.kind === 'return' ? gr : ge) ? ['pu_medit', T('edit'), `data-v="${esc(b.id)}"`] : null,
      b.status === 'posted' && b.kind === 'bill' && gr ? ['pu_mret', T('returnVs'), `data-v="${esc(b.id)}"`] : null,
      b.status === 'posted' && b.kind === 'bill' && Number(b.due) > 0 && gp ? ['pu_mpay', T('paySup')] : null,
      b.status === 'posted' && gp ? ['pu_mrefund', T('refund'), `data-s="${esc(b.supplier_id)}" data-n="${esc(b.supplier_name)}"`] : null]); },
  pu_medit: (a) => { closeSheet(); location.hash = '#/purchase/edit/' + a.dataset.v; },
  pu_mret: (a) => { closeSheet(); location.hash = '#/purchase/return/' + a.dataset.v; },
  pu_mpay: () => { closeSheet(); location.hash = '#/payables'; },
  pu_mrefund: (a) => { closeSheet(); refundFor(a.dataset.s, a.dataset.n); },
  py_menu: async (a) => { const x = PY.rows[Number(a.dataset.i)]; if (!x) return; const gp = await grant('supplier_pay', PY.loc === null || PY.loc === undefined ? defLoc() : PY.loc);
    menuSheet(x.name, [['py_open', T('ledger'), `data-i="${a.dataset.i}"`], gp ? ['py_mrefund', T('refund'), `data-s="${esc(x.supplier_id)}" data-n="${esc(x.name)}"`] : null]); },
  py_cmenu: async (a) => { const x = PY.credits[Number(a.dataset.i)]; if (!x) return; const gp = await grant('supplier_pay', defLoc());
    menuSheet(x.name, [['py_copen', T('ledger'), `data-i="${a.dataset.i}"`], gp ? ['py_mrefund', T('refund'), `data-s="${esc(x.supplier_id)}" data-n="${esc(x.name)}"`] : null]); },
  py_mrefund: (a) => { closeSheet(); refundFor(a.dataset.s, a.dataset.n); },
  py_copen: (a) => ledger(Number(a.dataset.i), true),
  py_refund_open: async () => { const x = PY.cur; if (!x) return; const credit = -Number(x.balance); if (!(credit > 0)) return toast(T('noCredit')); closeSheet(); refundSheet(x, credit); },
  py_refund_go: doRefund,
  py_voidref: (a) => { U.sheetStart('rvoid'); const pid = Number(a.dataset.v);
    openSheet(`<h2>${esc(T('voidRef'))}</h2><div><label for="vn_note">${esc(T('voidWhy'))}</label><input id="vn_note" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="py_voidrefgo" data-v="${pid}">${esc(T('voidRef'))}</button></div>`); },
  py_voidrefgo: async (a) => { const note = (($('#vn_note') || {}).value || '').trim(); if (!note) return toast(T('needNote')); const pid = Number(a.dataset.v);
    await U.submit(a, () => sb.rpc('void_supplier_refund', { p_id: pid, p_note: note }), () => { toast(T('refVoided')); payables(); }, { grant: 'purchase_void', loc: PY.loc === undefined ? null : PY.loc, context: { refund: pid } }); },
  pu_fapply: () => { PL.f = { supplier: $('#pf_sup').value, status: $('#pf_st').value, loc: ($('#pf_loc') || {}).value || '', from: $('#pf_from').value, to: $('#pf_to').value }; closeSheet(); listView(); },
  pu_freset: () => { PL.f = { loc: '', supplier: '', status: '', from: '', to: '' }; closeSheet(); listView(); },
  pu_more: () => { PL.shown += 60; drawList(PL.ge, PL.gr, false); },
  pu_open: (a) => { location.hash = '#/purchase/' + a.dataset.v; },
  pu_new: () => { location.hash = '#/purchase/new'; }, pu_new_ret: () => { location.hash = '#/purchase/return'; },
  pu_addline: () => { syncFixed(); F.lines.push({ item_id: null, item: '', desc: '', qty: '', unit: '', cost: '' }); $('#pe_lines').innerHTML = F.lines.map(lineHTML).join(''); wireUnits(); drawPreviews(); },
  pu_newitem: () => B.itemMaster.newItemSheet({ type: 'asset', onCreated: async (it) => { if (!F || !it) return; syncFixed(); ITEMS_ALL = null; await allItems();
    const row = ITEMS_ALL.find((x) => x.id === it.item_id) || it; const l = F.lines.length === 1 && !F.lines[0].item_id && !F.lines[0].desc && !F.lines[0].qty ? F.lines[0] : null;
    const nl = l || { item_id: null, item: '', desc: '', qty: '', unit: '', cost: '' }; nl.item_id = row.id; nl.item = U.itemText(row); if (!l) F.lines.push(nl);
    drawEditor(); } }),
  pu_delline: (a) => { F.lines.splice(Number(a.dataset.i), 1); $('#pe_lines').innerHTML = F.lines.map(lineHTML).join(''); wireUnits(); refreshTot(); drawPreviews(); },
  pu_scan: async (a) => { const i = Number(a.dataset.i), l = F && F.lines[i]; if (!l) return; const it = await B.barcode.scanItem(ITEMS_ALL); if (!it || !F) return;
    l.item_id = it.id; l.item = U.itemText(it); $('#pe_lines').innerHTML = F.lines.map(lineHTML).join(''); wireUnits(); drawPreviews(); },
  pu_save: (a) => doSave(a), pu_post: (a) => doPost(a),
  pu_edit: () => { location.hash = '#/purchase/edit/' + CUR.id; },
  pu_retvs: () => { location.hash = '#/purchase/return/' + CUR.id; },
  pu_paysup: () => { location.hash = '#/payables'; },
  pu_postd: postSheet,
  pu_postgo: async (a) => { if (a.disabled) return; const b = CUR, st = PS.st, ok = PS.ok;
    if (ok) { const pe = B.pay.check(st); if (pe) return toast(pe === 'overpaid' ? lab(U.ERR.overpaid) : T('walletNeeded')); }
    a.disabled = true; try { await postBill(b.id, ok ? B.pay.list(st) : [], b.kind, b.location_id); } finally { a.disabled = false; } },
  pu_void: () => noteSheet(T('voidBill'), T('voidWarn'), 'pu_voidgo', T('voidBill'), true),
  pu_vdraft: () => noteSheet(T('voidDraft'), '', 'pu_voidgo', T('voidDraft'), true),
  pu_voidgo: async (a) => { const note = (($('#vn_note') || {}).value || '').trim(); if (!note) return toast(T('needNote')); const b = CUR;
    await U.submit(a, () => sb.rpc('void_purchase', { p_id: b.id, p_note: note }), () => { toast(T('voided')); detail(b.id); }, { grant: 'purchase_void', loc: b.location_id, context: { bill: b.id } }); },
  py_open: (a) => ledger(Number(a.dataset.i)),
  py_pay: doPaySupplier,
  py_void: (a) => { U.sheetStart('pvoid'); const pid = Number(a.dataset.v);
    openSheet(`<h2>${esc(T('voidPay'))}</h2><div><label for="vn_note">${esc(T('voidWhy'))}</label><input id="vn_note" autocomplete="off"></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="py_voidgo" data-v="${pid}">${esc(T('voidPay'))}</button></div>`); },
  pu_lotapply: async (a) => { const r = await sb.rpc('receipt_lots_apply', { p_bill: a.dataset.v }); if (r.error) return errToast(r.error); toast(T('saved')); detail(a.dataset.v); },
  py_voidgo: async (a) => { const note = (($('#vn_note') || {}).value || '').trim(); if (!note) return toast(T('needNote')); const pid = Number(a.dataset.v);
    await U.submit(a, () => sb.rpc('void_supplier_payment', { p_id: pid, p_note: note }), () => { toast(T('payVoided')); payables(); }, { grant: 'purchase_void', loc: PY.loc === undefined ? null : PY.loc, context: { payment: pid } }); },
});
function refreshTot() { const el = $('#pe_tot'); if (el) el.innerHTML = totHTML(totals()); drawPreviews(); const ps = $('#pay_sum'); if (ps && B.pay.cur) B.pay.refreshSum(); }
document.addEventListener('input', (e) => {
  const el = e.target;
  if (el.dataset && el.dataset.ln && F) {
    const [i, f] = el.dataset.ln.split('.'), l = F.lines[Number(i)]; if (!l) return;
    if (f === 'item') { l.item = el.value; const it = U.itemFrom(ITEMS_ALL, el.value); l.item_id = it ? it.id : null; return; }      // the line is redrawn on change (blur), never while typing
    l[f] = el.value;
    const am = document.querySelector(`[data-amt="${i}"]`); if (am) am.textContent = nnum(l.qty) > 0 && nnum(l.cost) >= 0 ? money(r2(nnum(l.qty) * nnum(l.cost))) : '—';
    refreshTot();
  }
  if (el.id === 'pe_disc' && F) { F.discount = el.value; refreshTot(); }
  if (el.id === 'pe_sup' && F) { const s = supByName(el.value); const nid = s ? s.id : ''; if (nid !== F.supplier) { F.supplier = nid; F.ref = ''; loadRefBills(); } }
});
document.addEventListener('change', (e) => {
  const el = e.target;
  if (el.dataset && el.dataset.ln && F) { const [i, f] = el.dataset.ln.split('.'), l = F.lines[Number(i)]; if (l && f !== 'item') l[f] = el.value; if (l && f === 'item') { const it = U.itemFrom(ITEMS_ALL, el.value); l.item_id = it ? it.id : null; l.item = it ? U.itemText(it) : el.value; if (!!l.item_id !== l._ri) { if (!redrawing) { redrawing = true; try { $('#pe_lines').innerHTML = F.lines.map(lineHTML).join(''); wireUnits(); } finally { redrawing = false; } } } else { el.value = l.item; const us = document.querySelector(`[data-ln="${i}.unit"]`); if (us) us.options[0].textContent = (it && unitLabel(it.unit)) || T('itemUnit'); } } }
  if (el.dataset && el.dataset.ln && F) setTimeout(drawPreviews, 0);
  if (el.id === 'rf_mode') { const w = $('#rf_w'); if (w) w.hidden = el.value !== 'mobile'; }
  if (el.id === 'pe_loc' && F) { F.loc = Number(el.value) || F.loc; drawPreviews(); }
  if (el.id === 'py_loc') { PY.loc = el.value === '' ? null : Number(el.value); payables(); }
  if (el.id === 'pe_file' && F) { const f = el.files && el.files[0]; if (f) { toast(T('upl')); U.uploadPhoto(f, ['PURCHASE', '06-4', '04-1', '06-3'], F.loc).then((p) => { F.photo = p; drawEdPhoto(); }, fail); } }
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { purchase: view, payables });
})();
