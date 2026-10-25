/* Islamia BOS · Options X (phase99, step Opt). Two owner OPTIONS, both OFF by default (= today's behaviour); the screen only shows a recommendation next to each choice.
   Decision 1 - "Record payment now?": rules cost_bill_creates_payment / purchase_bill_creates_payment (off | ask | auto_cash | auto_bank | auto_by_supplier_default),
     bill_void_payment_mode (void | keep_credit), thresholds the owner types. After a cost bill is saved or a purchase bill is posted and the rule is "ask" (or
     "by supplier default" with no default known), a non-blocking sheet offers cash / bank / mobile / other, amount = what is left (editable, part payment allowed).
     The hook wraps sb.rpc for exactly two calls (cost_bill_add, post_purchase); it only READS the answer, never changes it, and any failure is swallowed.
   Decision 2 - inbox masking: rule inbox_pii_mode (off | mask_phone | mask_phone_address | mask_all_pii), grant inbox_unmask, rule inbox_unmask_daily_max.
     #/inboxpii lists masked messages and orders with a "Reveal" button (audited on the server: who, when, which message). inbox.js is not touched.
   Pages: #/optionsx (owner cards + reveal log), #/billpay (Bills without payment), #/inboxpii (reveal). data-act names start with opx_.
   Server: supabase/phase99.sql. Language rule: English mode is all English; Bangla mode keeps common words English; mix = Bng/Eng. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
if (!A || !B) return;
const { sb, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v == null ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };

const X = {
  title: L('অপশন: বিলের পেমেন্ট ও ইনবক্স গোপনীয়তা', 'Options: bill payment and inbox privacy', 'Options: bill payment ও inbox privacy'),
  t_pay: L('বিলের পেমেন্ট', 'Bill payment', 'Bill payment'), t_pii: L('ইনবক্স গোপনীয়তা', 'Inbox privacy', 'Inbox privacy'), t_log: L('খোলার log', 'Reveal log', 'Reveal log'),
  intro: L('দুটি সিদ্ধান্ত আপনি যেকোনো সময় বদলাতে পারবেন। এখন সব বন্ধ (আগের নিয়ম)। সিস্টেম শুধু প্রস্তাব দেখায়, নিজে কিছু বদলায় না।', 'You can change both decisions at any time. Everything is off now (as before). The system only shows a recommendation; it never changes anything by itself.', 'দুটি decision আপনি যেকোনো সময় বদলাতে পারবেন। এখন সব off (আগের নিয়ম)। System শুধু recommendation দেখায়, নিজে কিছু বদলায় না।'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), retry: L('আবার চেষ্টা করুন', 'Try again', 'আবার Try করুন'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'), none: L('কিছু নেই ✓', 'Nothing here ✓', 'কিছু নেই ✓'),
  cur: L('এখন', 'Current', 'Current'), rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'), why: L('কেন', 'Why', 'কেন'), save: L('রাখুন', 'Save', 'Save'), clear: L('ফাঁকা করুন', 'Clear', 'Clear'),
  ownerOnly: L('এটি করতে মালিক লাগবে।', 'Only the owner can do this.', 'এটা করতে owner লাগবে।'), cancel: L('বাদ দিন', 'Cancel', 'Cancel'), close: L('বন্ধ করুন', 'Close', 'Close'),
  // decision 1
  d1: L('সিদ্ধান্ত ১: বিল সেভ বা পোস্ট করলে পেমেন্ট এন্ট্রি নিজে হবে কি?', 'Decision 1: does saving or posting a bill create a payment record?', 'Decision 1: bill save বা post করলে payment entry নিজে হবে কি?'),
  r_cost: L('cost bill (বিদ্যুৎ, গ্যাস, ভাড়া …)', 'Cost bill (electricity, gas, rent ...)', 'Cost bill (electricity, gas, rent …)'),
  r_purchase: L('purchase bill (সাপ্লায়ার)', 'Purchase bill (supplier)', 'Purchase bill (supplier)'),
  r_void: L('বিল ভয়েড হলে এই সুবিধায় লেখা পেমেন্টের কী হবে?', 'When a bill is voided, what happens to a payment made here?', 'Bill void হলে এই feature-এ লেখা payment-এর কী হবে?'),
  o_off: L('বন্ধ (আগের নিয়ম)', 'Off (as before)', 'Off (আগের নিয়ম)'), o_ask: L('জিজ্ঞেস করুন', 'Ask me', 'Ask করুন'),
  o_auto_cash: L('নিজে ক্যাশে লিখুন', 'Record in cash automatically', 'নিজে cash-এ লিখুন'), o_auto_bank: L('নিজে ব্যাংকে লিখুন', 'Record in bank automatically', 'নিজে bank-এ লিখুন'),
  o_auto_by_supplier_default: L('পক্ষের নিজস্ব মোডে নিজে লিখুন', 'Automatic, in the party\'s own mode', 'Party-র নিজস্ব mode-এ নিজে লিখুন'),
  d_off: L('আগের মতো: বিল শুধু তথ্য; পেমেন্ট আলাদা করে লিখতে হবে।', 'As before: the bill is information; the payment is written separately.', 'আগের মতো: bill শুধু তথ্য; payment আলাদা করে লিখতে হবে।'),
  d_ask: L('সেভ বা পোস্টের পর একটি ছোট sheet: "এখনই পেমেন্ট লিখবেন?" ক্যাশ / ব্যাংক / mobile / অন্য; টাকা = বাকি, বদলানো যায়, আংশিক চলে।', 'After saving or posting, a small sheet: "Record payment now?" cash / bank / mobile / other; amount = what is left, editable, part payment allowed.', 'Save বা post-এর পর ছোট sheet: "এখনই payment লিখবেন?" cash / bank / mobile / অন্য; টাকা = বাকি, বদলানো যায়, আংশিক চলে।'),
  d_auto_cash: L('বিল সেভ বা পোস্ট হলেই পুরোটা ক্যাশে লেখা হয়। credit-শর্তের পক্ষ বাদ। কিছু মিলে না গেলে নিজে লেখে না, লাল-হলুদ চিহ্ন রাখে।', 'The whole bill is recorded in cash as soon as it is saved or posted. Parties with credit terms are skipped. If something looks like a duplicate it does not write and leaves a yellow flag.', 'Bill save বা post হলেই পুরোটা cash-এ লেখা হয়। Credit-terms-এর পক্ষ বাদ। কিছু মিলে না গেলে নিজে লেখে না, yellow flag রাখে।'),
  d_auto_bank: L('একই, তবে ব্যাংকে লেখা হয়।', 'The same, but recorded in bank.', 'একই, তবে bank-এ লেখা হয়।'),
  d_auto_by_supplier_default: L('পক্ষের (সাপ্লায়ার বা কস্টের source) নিজস্ব মোড থাকলে সেটাতে নিজে লেখে; না থাকলে জিজ্ঞেস করার জন্য তালিকায় রাখে।', 'If the party (supplier or cost source) has its own mode it is recorded in that mode; otherwise the bill waits in the list to be asked.', 'Party-র (supplier বা cost source) নিজস্ব mode থাকলে সেটাতে নিজে লেখে; না থাকলে জিজ্ঞেস করার জন্য list-এ রাখে।'),
  o_void: L('পেমেন্ট-ও ভয়েড', 'Void the payment too', 'Payment-ও void'), o_keep_credit: L('পেমেন্ট রাখুন (credit)', 'Keep the payment (credit)', 'Payment রাখুন (credit)'),
  d_void: L('বিলের সাথে পেমেন্ট-ও ভয়েড হয় এবং উল্টো এন্ট্রি যায়। কিছুই মোছা হয় না।', 'The payment is voided with the bill and a reversing entry follows. Nothing is deleted.', 'Bill-এর সাথে payment-ও void হয় এবং উল্টো entry যায়। কিছুই মোছা হয় না।'),
  d_keep_credit: L('টাকা সত্যিই দেওয়া হয়ে গেছে ধরা হয়; ক্রয়ে সেটি সাপ্লায়ারের credit হয়ে থাকে, cost bill-এ খরচ হিসেবে থাকে।', 'The money is treated as really paid; for a purchase it stays as supplier credit, for a cost bill it stays as an expense.', 'Money সত্যিই দেওয়া হয়েছে ধরা হয়; purchase-এ supplier credit হয়, cost bill-এ expense হিসেবে থাকে।'),
  creditOk: L('credit-শর্তের পক্ষেও নিজে লেখা চলবে', 'Allow automatic payment for parties with credit terms', 'Credit-terms-এর পক্ষেও auto চলবে'),
  creditOkH: L('বন্ধ রাখাই প্রস্তাব: নইলে "পরে দেব" শর্তটাই অর্থহীন হয়।', 'Keep it off (recommended): otherwise the credit term means nothing.', 'Off রাখাই recommendation: নইলে "পরে দেব" শর্তটাই অর্থহীন হয়।'),
  nLarge: L('বড় বিলের সীমা (টাকা)', 'Large bill amount (money)', 'Large bill-এর সীমা (টাকা)'), nSmall: L('ছোট cash bill-এর সীমা (টাকা)', 'Small cash bill amount (money)', 'Small cash bill-এর সীমা (টাকা)'),
  nHint: L('আপনি লিখবেন; ফাঁকা = সীমা নেই। কোনো সংখ্যা আগে থেকে বসানো নেই।', 'You type it; blank = none. No number is built in.', 'আপনি লিখবেন; ফাঁকা = সীমা নেই। কোনো সংখ্যা আগে থেকে বসানো নেই।'),
  defs: L('পক্ষের নিজস্ব মোড ও credit-শর্ত', 'Own mode and credit terms of a party', 'Party-র নিজস্ব mode ও credit terms'),
  defKind: L('ধরন', 'Kind', 'Kind'), k_supplier: L('সাপ্লায়ার', 'Supplier', 'Supplier'), k_cost_source: L('কস্টের source', 'Cost source', 'Cost source'),
  defParty: L('কোনটা', 'Which one', 'কোনটা'), defMode: L('সাধারণত কীভাবে দেওয়া হয়', 'Usually paid by', 'Usually কীভাবে দেওয়া হয়'), defCredit: L('credit-শর্ত আছে', 'Has credit terms', 'Credit terms আছে'),
  mAny: L('(ঠিক করা নেই)', '(not set)', '(ঠিক করা নেই)'),
  m_cash: L('ক্যাশ', 'Cash', 'Cash'), m_bank: L('ব্যাংক', 'Bank', 'Bank'), m_mobile: L('mobile', 'Mobile', 'Mobile'), m_card: L('কার্ড', 'Card', 'Card'), m_other: L('অন্য', 'Other', 'অন্য'),
  unpaid: L('পেমেন্ট ছাড়া বিল', 'Bills without payment', 'Payment ছাড়া bill'), unpaidN: L('টি বিলে এখনো পেমেন্ট নেই', 'bills have no payment yet', 'টি bill-এ এখনো payment নেই'),
  openList: L('পেমেন্ট ছাড়া বিলের তালিকা', 'Open the list: bills without payment', 'Payment ছাড়া bill-এর list'),
  // decision 2
  d2: L('সিদ্ধান্ত ২: ইনবক্সে কাস্টমারের ফোন ও ঠিকানা ঢাকা', 'Decision 2: mask customer phone and address in the inbox', 'Decision 2: inbox-এ customer-এর phone ও address ঢাকা'),
  p_off: L('বন্ধ (আগের নিয়ম)', 'Off (as before)', 'Off (আগের নিয়ম)'), p_mask_phone: L('শুধু ফোন ঢাকা', 'Mask phone', 'শুধু phone ঢাকা'),
  p_mask_phone_address: L('ফোন ও ঠিকানা ঢাকা', 'Mask phone and address', 'Phone ও address ঢাকা'), p_mask_all_pii: L('সব ব্যক্তিগত তথ্য ঢাকা', 'Mask all personal details', 'সব personal তথ্য ঢাকা'),
  e_off: L('আগের মতো: যার দেখার অধিকার আছে সে সব দেখে।', 'As before: whoever may see the inbox sees everything.', 'আগের মতো: যার দেখার অধিকার আছে সে সব দেখে।'),
  e_mask_phone: L('ফোন নম্বর (এবং ফোন-নম্বরের মতো handle) শুধু শেষ ৩ অক্ষর দেখা যায়।', 'Phone numbers (and handles that look like a phone number) show only their last 3 characters.', 'Phone number (এবং phone-এর মতো handle) শুধু শেষ ৩ অক্ষর দেখা যায়।'),
  e_mask_phone_address: L('ফোন ঢাকা, ঠিকানা পুরো ঢাকা। নাম ও মেসেজের লেখা খোলা।', 'Phone masked, address fully hidden. Name and message text stay visible.', 'Phone ঢাকা, address পুরো ঢাকা। নাম ও message-এর লেখা খোলা।'),
  e_mask_all_pii: L('ফোন, ঠিকানা, নাম, handle, মেসেজের লেখা ও attachment সবই ঢাকা।', 'Phone, address, name, handle, message text and attachment are all hidden.', 'Phone, address, name, handle, message text ও attachment সবই ঢাকা।'),
  piiNote: L('অনুমতি-পাওয়া (অনুমতি: ইনবক্স_unmask) মানুষ একটি একটি করে খুলতে পারেন; প্রতিবার log-এ থাকে: কে, কখন, কোন মেসেজ।', 'People with the inbox_unmask permission can reveal one at a time; every reveal is logged: who, when, which message.', 'Authorised (permission: inbox_unmask) মানুষ একটি একটি করে খুলতে পারেন; প্রতিবার log-এ থাকে: কে, কখন, কোন message।'),
  piiGuard: L('ফোন/ঠিকানার সরাসরি টেবিল-পড়া বন্ধ করতে আলাদা switch "ইনবক্স_pii_guard_on" ব্যবহার করুন; এই মোড শুধু ইনবক্স ও অর্ডারের পর্দা ঢাকে।', 'To block direct table reads of phone and address use the separate switch "inbox_pii_guard_on"; this mode masks the inbox and order screens only.', 'Phone/address-এর সরাসরি table-read বন্ধ করতে আলাদা switch "inbox_pii_guard_on" ব্যবহার করুন; এই mode শুধু inbox ও order-এর screen ঢাকে।'),
  nMax: L('একজন দিনে সর্বোচ্চ কতবার খুলতে পারবে', 'Max reveals per person per day', 'একজন দিনে সর্বোচ্চ কতবার খুলতে পারবে'),
  nMaxH: L('ফাঁকা = সীমা নেই। মালিকের ওপর সীমা খাটে না। কমপক্ষে ১।', 'Blank = no limit. The owner is not limited. At least 1.', 'ফাঁকা = সীমা নেই। Owner-এর ওপর সীমা খাটে না। কমপক্ষে ১।'),
  openPii: L('ইনবক্সের ঢাকা তথ্য খুলুন', 'Reveal masked inbox details', 'Inbox-এর ঢাকা তথ্য খুলুন'),
  revToday: L('আজ খোলা হয়েছে', 'Revealed today', 'আজ খোলা হয়েছে'), blkToday: L('আজ সীমার কারণে আটকেছে', 'Blocked by the limit today', 'আজ limit-এর কারণে আটকেছে'),
  // log
  logIntro: L('কে, কখন, কোন মেসেজ বা অর্ডার খুলেছেন (সর্বশেষ ১০০)।', 'Who revealed which message or order, and when (latest 100).', 'কে, কখন, কোন message বা order খুলেছেন (সর্বশেষ ১০০)।'),
  who: L('কে', 'Who', 'কে'), when: L('কখন', 'When', 'কখন'), what: L('কোনটা', 'What', 'কোনটা'), outc: L('ফল', 'Result', 'Result'), o_revealed: L('খোলা হয়েছে', 'Revealed', 'খোলা হয়েছে'), o_blocked: L('সীমায় আটকেছে', 'Blocked by the limit', 'Limit-এ আটকেছে'),
  k_message: L('মেসেজ', 'Message', 'Message'), k_order: L('অর্ডার', 'Order', 'Order'),
  // sheet
  sheetT: L('এখনই পেমেন্ট লিখবেন?', 'Record payment now?', 'এখনই payment লিখবেন?'), party: L('পক্ষ', 'Party', 'Party'), total: L('বিলের টোটাল', 'Bill total', 'Bill-এর total'), paid: L('দেওয়া হয়েছে', 'Already paid', 'দেওয়া হয়েছে'), left: L('বাকি', 'Left to pay', 'বাকি'),
  mode: L('কীভাবে', 'How', 'কীভাবে'), amount: L('টাকা (বদলানো যায়, আংশিক চলে)', 'Amount (editable, part payment allowed)', 'টাকা (বদলানো যায়, আংশিক চলে)'), note: L('নোট (ইচ্ছা)', 'Note (optional)', 'Note (ইচ্ছা)'),
  recLine: L('প্রস্তাব', 'Suggestion', 'Suggestion'), go: L('পেমেন্ট লিখুন', 'Record payment', 'Payment লিখুন'), notNow: L('এখন নয়', 'Not now', 'এখন নয়'),
  other: L('"অন্য" দিলে এটি শুধু নোট থাকে: cash book বা খাতায় ওঠে না।', '"Other" is kept as a note only: it does not reach the cash book or the journal.', '"অন্য" দিলে এটি শুধু note থাকে: cash book বা journal-এ ওঠে না।'),
  doneLeft: L('লেখা হয়েছে। বাকি:', 'Recorded. Left:', 'লেখা হয়েছে। বাকি:'), done: L('লেখা হয়েছে', 'Recorded', 'লেখা হয়েছে'), dup: L('এটি আগেই লেখা হয়েছে (দ্বিতীয়বার নয়)।', 'This was already recorded (not twice).', 'এটা আগেই লেখা হয়েছে (দ্বিতীয়বার নয়)।'),
  warnT: L('সাবধান: একই কস্ট আগেই লেখা থাকতে পারে', 'Careful: the same cost may already be recorded', 'সাবধান: একই cost আগেই লেখা থাকতে পারে'),
  w_form_10_2_matches: L('একই জায়গা, মাস, খাত ও টাকার একটি ১১-১ voucher আছে।', 'A 11-1 voucher with the same place, month, head and amount exists.', 'একই জায়গা, মাস, খাত ও টাকার একটি 11-1 voucher আছে।'),
  w_quick_expense_similar: L('একই জায়গা, খাত ও টাকার একটি দ্রুত খরচ আগেই আছে।', 'A quick expense with the same place, head and amount already exists.', 'একই জায়গা, খাত ও টাকার একটি quick expense আগেই আছে।'),
  differs: L('এটি আলাদা কস্ট, তবুও লিখুন', 'It is a different cost, record anyway', 'এটা আলাদা cost, তবুও লিখুন'),
  autoLeft: L('নিজে লেখা হয়নি (credit-শর্ত বা মিলে যাওয়া কস্ট)। "পেমেন্ট ছাড়া বিল" তালিকা থেকে লিখুন।', 'Not recorded automatically (credit terms or a matching cost). Record it from "Bills without payment".', 'নিজে লেখা হয়নি (credit terms বা মিলে যাওয়া cost)। "Payment ছাড়া bill" list থেকে লিখুন।'),
  // list page
  lIntro: L('যে বিলের টাকা এখনো পুরো লেখা হয়নি। "পেমেন্ট লিখুন" চাপলে একই sheet খোলে।', 'Bills whose payment is not fully recorded yet. "Record payment" opens the same sheet.', 'যে bill-এর টাকা এখনো পুরো লেখা হয়নি। "Payment লিখুন" চাপলে একই sheet খোলে।'),
  lDue: L('বাকি', 'Due', 'বাকি'), lRule: L('এখনকার নিয়ম', 'Current rule', 'Current rule'),
  // reveal
  rIntro: L('ইনবক্সের মেসেজ ও অনলাইন অর্ডার ঢাকা অবস্থায় আছে। একটি খুলতে "খুলুন" চাপুন; প্রতিবার log-এ থাকে।', 'Inbox messages and online orders are shown masked. Tap "Reveal" to open one; every reveal is logged.', 'Inbox message ও online order ঢাকা অবস্থায় আছে। একটি খুলতে "খুলুন" চাপুন; প্রতিবার log-এ থাকে।'),
  rMsgs: L('inbox message', 'Inbox messages', 'Inbox message'), rOrders: L('অনলাইন অর্ডার', 'Online orders', 'Online order'), reveal: L('খুলুন', 'Reveal', 'খুলুন'),
  rReason: L('কারণ (ইচ্ছা)', 'Reason (optional)', 'Reason (ইচ্ছা)'), rGo: L('খুলুন ও log-এ রাখুন', 'Reveal and log it', 'খুলুন ও log-এ রাখুন'), rLogged: L('এই খোলা log-এ রাখা হয়েছে।', 'This reveal is logged.', 'এই খোলা log-এ রাখা হয়েছে।'),
  rOff: L('এখন কিছু ঢাকা নেই (মোড বন্ধ)।', 'Nothing is masked now (the mode is off).', 'এখন কিছু ঢাকা নেই (mode off)।'),
  f_handle: L('handle', 'Handle', 'Handle'), f_name: L('নাম', 'Name', 'নাম'), f_text: L('মেসেজ', 'Message', 'Message'), f_attachment_ref: L('attachment', 'Attachment', 'Attachment'),
  f_customer_name: L('নাম', 'Name', 'নাম'), f_customer_mobile: L('ফোন', 'Phone', 'Phone'), f_address: L('ঠিকানা', 'Address', 'Address'),
  orderNo: L('অর্ডার', 'Order', 'Order'), loc: L('জায়গা', 'Place', 'Place'),
};
const ERR = {
  rate_limited: L('আজকের খোলার সীমা শেষ। কাল আবার চেষ্টা করুন বা মালিককে বলুন।', 'Today\'s reveal limit is used up. Try tomorrow or ask the owner.', 'আজকের খোলার limit শেষ। কাল আবার চেষ্টা করুন বা owner-কে বলুন।'),
  overpaid: L('বাকির চেয়ে বেশি টাকা দেওয়া যাবে না।', 'You cannot pay more than what is left.', 'বাকির চেয়ে বেশি টাকা দেওয়া যাবে না।'),
  nothing_due: L('এই বিলে আর কিছু বাকি নেই।', 'Nothing is left to pay on this bill.', 'এই bill-এ আর কিছু বাকি নেই।'),
  bad_mode: L('এই মোড এই বিলের জন্য নয়।', 'This mode is not available for this bill.', 'এই mode এই bill-এর জন্য নয়।'),
  bad_amount: L('টাকার অংক ঠিক নয়।', 'The amount is not valid.', 'টাকার অংক ঠিক নয়।'),
  bill_void: L('বিলটি ভয়েড।', 'The bill is void.', 'Bill void।'),
  bill_not_posted: L('বিল এখনো পোস্ট হয়নি।', 'The bill is not posted yet.', 'Bill এখনো post হয়নি।'),
  path_locked: L('এই জায়গায় দ্রুত খরচ বন্ধ (মালিক form ১১-১ কে মূল রেকর্ড করেছেন)।', 'Quick expense is locked here (the owner made form 11-1 the record).', 'এই জায়গায় quick expense বন্ধ (owner form 11-1 কে মূল record করেছেন)।'),
  period_closed: L('হিসাবের সময়কাল বন্ধ।', 'The accounting period is closed.', 'Accounting period বন্ধ।'),
  no_location: L('এই source-এর কোনো জায়গা নেই।', 'This source has no place.', 'এই source-এর কোনো জায়গা নেই।'),
  bad_value: L('মান ঠিক নয়।', 'The value is not valid.', 'Value ঠিক নয়।'),
  bad_input: L('ইনপুট ঠিক নয়।', 'The input is not valid.', 'Input ঠিক নয়।'),
  not_found: L('পাওয়া যায়নি।', 'Not found.', 'পাওয়া যায়নি।'),
  module_off: L('ইনবক্স চালু নেই।', 'The inbox is not switched on.', 'Inbox চালু নেই।'),
  'not allowed': L('এর অনুমতি আপনার নেই।', 'You do not have permission for this.', 'এর অনুমতি আপনার নেই।'),
  'does not exist': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase99 লাগবে)', 'The server does not have this yet (phase99 is needed)', 'Server-এ এটা এখনো নেই (phase99 লাগবে)'),
  'Could not find the function': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase99 লাগবে)', 'The server does not have this yet (phase99 is needed)', 'Server-এ এটা এখনো নেই (phase99 লাগবে)'),
  'Failed to fetch': L('ইন্টারনেট নেই বা সার্ভার পাওয়া যায়নি; আবার চেষ্টা করুন', 'No internet or the server did not answer; try again', 'Internet নেই বা server পাওয়া যায়নি; আবার চেষ্টা করুন'),
};
const T = (k) => (X[k] ? lab(X[k]) : k);
const eText = (e) => {
  const m = String((e && e.message) || e || '');
  const k = Object.keys(ERR).find((x) => m.includes(x));
  return k ? lab(ERR[k]) : (m || 'error');
};
B.opxMsg = (code) => (ERR[code] ? lab(ERR[code]) : null);

/* the recommendations (the server rows of setup_recommendations() win when present; these are the same values) */
const REC = {
  cost_bill_creates_payment: { v: 'ask', why: L('ছোট sheet দিয়ে জিজ্ঞেস করা নিরাপদ: টাকা কখনো ভুলে সরে না, আবার বিল ও পেমেন্ট দুবার type করতে হয় না। পুরোপুরি অটো শুধু ক্যাশে শোধ হওয়া ছোট বিলের জন্য।', 'Asking with a small sheet is the safe middle: money never moves by mistake and you do not type bill and payment twice. Use a fully automatic mode only for small bills paid in cash.', 'ছোট sheet দিয়ে জিজ্ঞেস করা safe: টাকা কখনো ভুলে সরে না, আবার bill ও payment দুবার type করতে হয় না। পুরোপুরি auto শুধু cash-এ শোধ হওয়া ছোট bill-এর জন্য।') },
  purchase_bill_creates_payment: { v: 'ask', why: L('পোস্টের পর জিজ্ঞেস করা নিরাপদ। credit-শর্তের সাপ্লায়ার কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধ চলে।', 'Asking after posting is the safe choice. A supplier with credit terms is never paid automatically, so part payment or paying later stays possible.', 'Post-এর পর জিজ্ঞেস করা safe। Credit-terms-এর supplier কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধ চলে।') },
  bill_void_payment_mode: { v: 'void', why: L('বিলের সাথে পেমেন্ট-ও ভয়েড হওয়াই সাধারণ নিয়ম; নইলে বইয়ে কস্ট থেকে যায় অথচ বিল নেই। টাকা সত্যিই দেওয়া হলে "রাখুন" বাছুন।', 'Voiding the payment with its bill is the normal rule; otherwise the books keep a cost for a bill that is gone. Choose "keep" only when the money really left.', 'Bill-এর সাথে payment-ও void হওয়াই সাধারণ নিয়ম; নইলে বইয়ে cost থেকে যায় অথচ bill নেই। টাকা সত্যিই দেওয়া হলে "রাখুন" বাছুন।') },
  inbox_pii_mode: { v: 'mask_phone_address', why: L('ফোন ও ঠিকানা ঢেকে রাখা ভালো: বেশিরভাগ কাজে পুরো নম্বর লাগে না, আর ফাঁস হলে ক্ষতি বেশি। নাম ও মেসেজের লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে অনুমতি-পাওয়া মানুষ একটি একটি করে খুলবেন।', 'Hiding phone and address is the better default: most work does not need the full number and a leak costs a lot. Name and message text stay visible so work is not blocked. Authorised people reveal one at a time.', 'Phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে পুরো নম্বর লাগে না, আর leak হলে ক্ষতি বেশি। নাম ও message-এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে authorised মানুষ একটি একটি করে খুলবেন।') },
};
const RULE_OPTS = {
  cost_bill_creates_payment: ['off', 'ask', 'auto_cash', 'auto_bank', 'auto_by_supplier_default'],
  purchase_bill_creates_payment: ['off', 'ask', 'auto_cash', 'auto_bank', 'auto_by_supplier_default'],
  bill_void_payment_mode: ['void', 'keep_credit'],
  inbox_pii_mode: ['off', 'mask_phone', 'mask_phone_address', 'mask_all_pii'],
};
const optLabel = (rule, v) => (rule === 'inbox_pii_mode' ? T('p_' + v) : rule === 'bill_void_payment_mode' ? T('o_' + v) : T('o_' + v));
const optDesc = (rule, v) => (rule === 'inbox_pii_mode' ? T('e_' + v) : rule === 'bill_void_payment_mode' ? T('d_' + v) : T('d_' + v));

const D = { tab: 'pay', st: null, rec: {}, defs: [], parties: { supplier: [], cost_source: [] }, log: null, ready: false, err: null, kind: 'supplier',
  list: null, listErr: null, pii: null, piiErr: null, rev: null };
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };

/* ---------- Page 1: owner cards ---------- */
function recFor(rule) {
  const s = D.rec[rule]; const f = REC[rule] || {};
  return { v: s && s.recommended != null ? s.recommended : f.v, why: s && (s.reason_en || s.reason_bn) ? lab({ bn: s.reason_bn, mix: s.reason_mix || s.reason_bn, en: s.reason_en }) : (f.why ? lab(f.why) : '') };
}
function ruleCard(rule, titleKey) {
  const cur = D.st ? D.st[rule] : null; const rc = recFor(rule);
  const rows = RULE_OPTS[rule].map((v) => `<button type="button" class="card stack opx-opt" data-opx="opt" data-rule="${rule}" data-v="${v}" aria-pressed="${cur === v}" data-act="opx_set" data-k="${rule}" data-val="${v}">
      <span class="row wrap"><b>${esc(optLabel(rule, v))}</b>${cur === v ? `<span class="chip">${esc(T('cur'))}</span>` : ''}${rc.v === v ? `<span class="chip ok">${esc(T('rec'))}</span>` : ''}</span>
      <span class="muted" style="font-size:.85rem">${esc(optDesc(rule, v))}</span></button>`).join('');
  return `<div class="card stack" data-opx="rule" data-rule="${rule}"><b>${esc(T(titleKey))}</b>${rows}<div class="muted" style="font-size:.85rem" data-opx="why"><b>${esc(T('why'))}:</b> ${esc(rc.why)}</div></div>`;
}
function numBox(rule, labelKey, hintKey) {
  const v = D.st ? D.st[rule] : null;
  return `<div class="card stack" data-opx="num" data-rule="${rule}"><label for="opx_n_${rule}">${esc(T(labelKey))}</label><div class="muted" style="font-size:.85rem">${esc(T(hintKey))}</div>
    <div class="row"><input id="opx_n_${rule}" inputmode="decimal" autocomplete="off" value="${esc(v == null ? '' : v)}"><button type="button" class="mini primary" data-act="opx_num" data-k="${rule}">${esc(T('save'))}</button><button type="button" class="mini" data-act="opx_numclr" data-k="${rule}">${esc(T('clear'))}</button></div></div>`;
}
function defsCard() {
  const rows = D.defs.map((d) => `<div class="row wrap" data-opx="def"><b>${esc(d.name || d.id)}</b><span class="chip">${esc(T('k_' + d.kind))}</span><span class="chip">${esc(d.mode ? T('m_' + d.mode) : T('mAny'))}</span>${d.credit ? `<span class="chip warn">${esc(T('defCredit'))}</span>` : ''}</div>`).join('') || `<div class="muted">${esc(T('none'))}</div>`;
  const ps = (D.parties[D.kind] || []).map((p) => `<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');
  return `<div class="card stack" data-opx="defs"><b>${esc(T('defs'))}</b>${rows}
    <label for="opx_dk">${esc(T('defKind'))}</label><select id="opx_dk" data-act="opx_dkind"><option value="supplier" ${D.kind === 'supplier' ? 'selected' : ''}>${esc(T('k_supplier'))}</option><option value="cost_source" ${D.kind === 'cost_source' ? 'selected' : ''}>${esc(T('k_cost_source'))}</option></select>
    <label for="opx_dp">${esc(T('defParty'))}</label><select id="opx_dp">${ps}</select>
    <label for="opx_dm">${esc(T('defMode'))}</label><select id="opx_dm"><option value="">${esc(T('mAny'))}</option>${['cash', 'bank', 'mobile', 'card'].map((m) => `<option value="${m}">${esc(T('m_' + m))}</option>`).join('')}</select>
    <label class="row"><input type="checkbox" id="opx_dc"> ${esc(T('defCredit'))}</label>
    <button type="button" class="mini primary" data-act="opx_defsave">${esc(T('save'))}</button></div>`;
}
function payTab() {
  const s = D.st || {};
  return `<p class="muted">${esc(T('intro'))}</p><h3>${esc(T('d1'))}</h3>`
    + ruleCard('cost_bill_creates_payment', 'r_cost') + ruleCard('purchase_bill_creates_payment', 'r_purchase') + ruleCard('bill_void_payment_mode', 'r_void')
    + `<div class="card stack" data-opx="credit"><label class="row"><input type="checkbox" id="opx_cr" ${s.bill_pay_auto_credit_ok ? 'checked' : ''} data-act="opx_credit"> <b>${esc(T('creditOk'))}</b></label><div class="muted" style="font-size:.85rem">${esc(T('creditOkH'))}</div></div>`
    + numBox('bill_pay_large_amount', 'nLarge', 'nHint') + numBox('bill_pay_small_cash_max', 'nSmall', 'nHint') + defsCard()
    + `<div class="card stack" data-opx="unpaid"><b>${esc(T('unpaid'))}: ${esc((s.unpaid_cost || 0) + (s.unpaid_purchase || 0))} ${esc(T('unpaidN'))}</b><a class="btn opx-lnk" href="#/billpay">${esc(T('openList'))}</a></div>`;
}
function piiTab() {
  const s = D.st || {};
  return `<p class="muted">${esc(T('intro'))}</p><h3>${esc(T('d2'))}</h3>` + ruleCard('inbox_pii_mode', 'd2')
    + `<div class="notice" data-opx="piinote">${esc(T('piiNote'))}</div><div class="notice" data-opx="piiguard">${esc(T('piiGuard'))}</div>`
    + numBox('inbox_unmask_daily_max', 'nMax', 'nMaxH')
    + `<div class="card stack"><span class="chip">${esc(T('revToday'))}: ${esc(s.reveals_today || 0)}</span><span class="chip">${esc(T('blkToday'))}: ${esc(s.blocked_today || 0)}</span><a class="btn opx-lnk" href="#/inboxpii">${esc(T('openPii'))}</a></div>`;
}
function logTab() {
  const rows = (D.log || []).map((r) => `<div class="card stack" data-opx="logrow"><div class="row between"><b>${esc(r.staff || String(r.user_id || '').slice(0, 8))}</b><span class="chip ${r.outcome === 'blocked' ? 'warn' : ''}">${esc(T('o_' + r.outcome))}</span></div>
    <div class="muted">${esc(String(r.at || '').replace('T', ' ').slice(0, 16))} · ${esc(T('k_' + r.kind))} #${esc(String(r.ref).slice(0, 8))}${r.reason ? ' · ' + esc(r.reason) : ''}</div></div>`).join('');
  return `<p class="muted">${esc(T('logIntro'))}</p>${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function tabsBar() {
  return `<div class="row wrap" role="tablist">${[['pay', 't_pay'], ['pii', 't_pii'], ['log', 't_log']].map(([k, l]) => `<button type="button" role="tab" class="mini ${D.tab === k ? 'primary' : ''}" aria-selected="${D.tab === k}" data-act="opx_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
}
function drawMain() {
  const el = $('#opx_body'); if (!el) return;
  if (D.err) { el.innerHTML = `${tabsBar()}<div class="notice bad" data-state="error">${esc(D.err)}</div><button type="button" class="full" data-act="opx_retry">${esc(T('retry'))}</button>`; return; }
  if (!D.ready) { el.innerHTML = `${tabsBar()}<p class="muted center pad" data-state="loading">${esc(T('loading'))}</p>`; return; }
  el.innerHTML = tabsBar() + (D.tab === 'pay' ? payTab() : D.tab === 'pii' ? piiTab() : logTab());
}
async function loadMain() {
  D.err = null;
  try {
    D.st = await rpc('options99_state');
    try { const r = await rpc('setup_recommendations'); D.rec = {}; ((r && r.items) || []).forEach((i) => { D.rec[i.rule_key] = i; }); } catch (e) { D.rec = {}; }
    try { D.defs = (await rpc('bill_pay_defaults_list99')) || []; } catch (e) { D.defs = []; }
    await loadParties();
    if (D.tab === 'log') D.log = (await rpc('inbox_unmask_log_list99', { p_limit: 100, p_user: null })) || [];
    D.ready = true;
  } catch (e) { D.err = eText(e); }
  drawMain();
}
async function loadParties() {
  try { const r = await sb.from('suppliers').select('id,name').order('name'); D.parties.supplier = (r && r.data) || []; } catch (e) { D.parties.supplier = []; }
  try { const r = await sb.from('cost_sources').select('id,code,provider').order('id'); D.parties.cost_source = ((r && r.data) || []).map((c) => ({ id: String(c.id), name: c.provider || c.code })); } catch (e) { D.parties.cost_source = []; }
}

/* ---------- Page 2: Bills without payment ---------- */
async function loadList() {
  D.listErr = null;
  try { D.list = await rpc('bills_without_payment99', { p_kind: null, p_loc: null, p_limit: 200 }); } catch (e) { D.listErr = eText(e); }
  drawList();
}
function drawList() {
  const el = $('#opx_list'); if (!el) return;
  if (D.listErr) { el.innerHTML = `<div class="notice bad" data-state="error">${esc(D.listErr)}</div><button type="button" class="full" data-act="opx_lretry">${esc(T('retry'))}</button>`; return; }
  if (!D.list) { el.innerHTML = `<p class="muted center pad" data-state="loading">${esc(T('loading'))}</p>`; return; }
  const rows = (D.list.rows || []).map((r) => `<div class="card stack" data-opx="bill" data-kind="${esc(r.kind)}">
      <div class="row between"><b>${esc(r.party || '')}</b><span class="chip">${esc(r.kind === 'cost' ? T('r_cost') : T('r_purchase'))}</span></div>
      <div class="muted">${esc(r.bill_no || '')} ${esc(String(r.date || '').slice(0, 10))}</div>
      <div class="row between"><span>${esc(T('total'))}: ${esc(fm(r.total))}</span><b>${esc(T('lDue'))}: ${esc(fm(r.due))}</b></div>
      <button type="button" class="mini primary" data-act="opx_lpay" data-k="${esc(r.kind)}" data-r="${esc(r.ref)}">${esc(T('go'))}</button></div>`).join('');
  el.innerHTML = `<p class="muted">${esc(T('lIntro'))}</p><div class="muted" data-opx="rules">${esc(T('lRule'))}: ${esc(T('r_cost'))} = ${esc(D.list.cost_rule)} · ${esc(T('r_purchase'))} = ${esc(D.list.purchase_rule)}</div>${rows || `<p class="muted">${esc(T('none'))}</p>`}`;
}

/* ---------- the "Record payment now?" sheet ---------- */
const SH = { info: null, kind: null, ref: null, mode: null, cid: null, warn: null, msg: null, left: null };
function modeFor(info) {
  const rec = info.recommendation || {};
  const fromRec = rec.mode === 'auto_cash' ? 'cash' : rec.mode === 'auto_bank' ? 'bank' : null;
  const pick = [info.suggest_mode, fromRec, 'cash'].find((m) => m && (info.modes || []).includes(m));
  return pick || (info.modes || [])[0];
}
function sheetHTML() {
  const i = SH.info; if (!i) return '';
  const rec = i.recommendation || {};
  const recText = lab({ bn: rec.reason_bn, mix: rec.reason_mix || rec.reason_bn, en: rec.reason_en });
  const modes = (i.modes || []).map((m) => `<button type="button" class="mini ${SH.mode === m ? 'primary' : ''}" aria-pressed="${SH.mode === m}" data-act="opx_mode" data-v="${m}">${esc(T('m_' + m))}</button>`).join('');
  const warn = SH.warn ? `<div class="notice warn" data-opx="warn"><b>${esc(T('warnT'))}</b>${SH.warn.map((w) => `<div>${esc(X['w_' + w] ? T('w_' + w) : w)}</div>`).join('')}<button type="button" class="mini" data-act="opx_pay" data-confirm="1">${esc(T('differs'))}</button></div>` : '';
  return `<div class="stack" data-opx="sheet"><h3>${esc(T('sheetT'))}</h3>
    <div class="muted">${esc(T('party'))}: <b>${esc(i.party || '')}</b></div>
    <div class="row between"><span>${esc(T('total'))}: ${esc(fm(i.total))}</span><span>${esc(T('paid'))}: ${esc(fm(i.paid))}</span><b data-opx="left">${esc(T('left'))}: ${esc(fm(i.remaining))}</b></div>
    <div class="notice" data-opx="rec"><b>${esc(T('recLine'))}:</b> ${esc(rec.mode ? (X['o_' + rec.mode] ? T('o_' + rec.mode) : rec.mode) : '')}<div class="muted" style="font-size:.85rem">${esc(recText)}</div></div>
    <div class="row wrap" role="group" aria-label="${esc(T('mode'))}">${modes}</div>
    ${SH.mode === 'other' ? `<div class="muted" style="font-size:.85rem" data-opx="othernote">${esc(T('other'))}</div>` : ''}
    <label for="opx_amt">${esc(T('amount'))}</label><input id="opx_amt" inputmode="decimal" autocomplete="off" value="${esc(i.remaining)}">
    <label for="opx_note">${esc(T('note'))}</label><input id="opx_note" autocomplete="off">
    ${warn}${SH.msg ? `<div class="notice ${SH.msg.ok ? 'ok' : 'bad'}" data-opx="msg" aria-live="polite">${esc(SH.msg.t)}</div>` : ''}
    <div class="row"><button type="button" class="full" data-act="opx_skip">${esc(SH.msg && SH.msg.ok && !(SH.left > 0.004) ? T('close') : T('notNow'))}</button>${SH.left == null || SH.left > 0.004 ? `<button type="button" class="full primary" data-act="opx_pay">${esc(T('go'))}</button>` : ''}</div></div>`;
}
function drawSheet() { openSheet(sheetHTML()); }
async function openPaySheet(kind, ref) {
  try {
    const info = await rpc('bill_pay_info99', { p_kind: kind, p_ref: ref });
    if (!info || !(Number(info.remaining) > 0.004)) return false;
    SH.info = info; SH.kind = kind; SH.ref = ref; SH.mode = modeFor(info); SH.cid = rid(); SH.warn = null; SH.msg = null; SH.left = null;
    drawSheet(); return true;
  } catch (e) { return false; }
}
async function afterSave(kind, ref, rule) {
  try {
    const info = await rpc('bill_pay_info99', { p_kind: kind, p_ref: ref });
    if (!info || !(Number(info.remaining) > 0.004)) return;
    if (info.rule === 'ask' || info.rule === 'auto_by_supplier_default') { SH.info = info; SH.kind = kind; SH.ref = ref; SH.mode = modeFor(info); SH.cid = rid(); SH.warn = null; SH.msg = null; SH.left = null; drawSheet(); }
    else if (info.rule === 'auto_cash' || info.rule === 'auto_bank') toast(T('autoLeft'));
  } catch (e) { /* the option is optional: a failure here never disturbs the screen that saved the bill */ }
}
/* the only hook: READ the result of the two save calls, never change it. Off (default rule) = one cheap check and nothing else. */
const HOOKS = {
  cost_bill_add: (r) => { if (r && !r.error && r.data && r.data.id && !r.data.dup) return afterSave('cost', String(r.data.id)); },
  post_purchase: (r, args) => { if (r && !r.error && r.data && !r.data.dup && args && args.p_id) return afterSave('purchase', String(args.p_id)); },
};
function installHook() {
  try {
    if (!sb || typeof sb.rpc !== 'function' || sb.rpc.__opx) return;
    const orig = sb.rpc.bind(sb);
    const wrapped = function (name, args, opts) {
      const h = HOOKS[name];
      if (!h) return orig(name, args, opts);
      const p = Promise.resolve(orig(name, args, opts));          // one real promise; the builder is awaited exactly once (never sent twice)
      p.then((r) => { setTimeout(() => { try { const x = h(r, args); if (x && x.catch) x.catch(() => {}); } catch (e) { /* ignore */ } }, 700); }, () => {});
      return p;
    };
    wrapped.__opx = true; sb.rpc = wrapped;
  } catch (e) { /* no hook: the pages still work */ }
}

/* ---------- Page 3: reveal ---------- */
async function loadPii() {
  D.piiErr = null;
  try {
    const [m, o] = await Promise.all([sb.rpc('inbox_list', { p_loc: null, p_status: null, p_limit: 100 }), sb.rpc('online_orders_list', { p_loc: null, p_status: null, p_from: null, p_to: null, p_limit: 100 })]);
    D.pii = { msgs: m.error ? [] : (m.data || []), orders: o.error ? [] : (o.data || []), merr: m.error ? eText(m.error) : null };
  } catch (e) { D.piiErr = eText(e); }
  drawPii();
}
function drawPii() {
  const el = $('#opx_pii'); if (!el) return;
  if (D.piiErr) { el.innerHTML = `<div class="notice bad" data-state="error">${esc(D.piiErr)}</div><button type="button" class="full" data-act="opx_pretry">${esc(T('retry'))}</button>`; return; }
  if (!D.pii) { el.innerHTML = `<p class="muted center pad" data-state="loading">${esc(T('loading'))}</p>`; return; }
  const mode = ((D.pii.msgs[0] || {}).pii_mode) || ((D.pii.orders[0] || {}).pii_mode) || 'off';
  const msgs = D.pii.msgs.map((m) => `<div class="card stack" data-opx="msg" data-id="${esc(m.id)}"><div class="row between"><b>${esc(m.name || m.handle || '#' + m.id)}</b><span class="chip">#${esc(m.id)}</span></div>
      <div class="muted">${esc(m.handle || '')}</div><div class="muted">${esc(m.text || '')}</div>
      <button type="button" class="mini primary" data-act="opx_reveal" data-k="message" data-r="${esc(m.id)}">${esc(T('reveal'))}</button></div>`).join('');
  const ords = D.pii.orders.map((o) => `<div class="card stack" data-opx="ord" data-id="${esc(o.id)}"><div class="row between"><b>${esc(o.customer_name || '')}</b><span class="chip">${esc(T('orderNo'))} #${esc(o.order_no)}</span></div>
      <div class="muted">${esc(o.customer_mobile || '')}</div>
      <button type="button" class="mini primary" data-act="opx_reveal" data-k="order" data-r="${esc(o.id)}">${esc(T('reveal'))}</button></div>`).join('');
  el.innerHTML = `<p class="muted">${esc(T('rIntro'))}</p>${mode === 'off' ? `<div class="notice" data-opx="off">${esc(T('rOff'))}</div>` : ''}
    <h3>${esc(T('rMsgs'))}</h3>${msgs || `<p class="muted">${esc(T('none'))}</p>`}<h3>${esc(T('rOrders'))}</h3>${ords || `<p class="muted">${esc(T('none'))}</p>`}`;
}
function revealHTML() {
  const R = SH.rev; if (!R) return '';
  if (R.data) {
    const d = R.data; const keys = R.kind === 'message' ? ['handle', 'name', 'text', 'attachment_ref'] : ['customer_name', 'customer_mobile', 'address'];
    return `<div class="stack" data-opx="revealed"><h3>${esc(T(R.kind === 'message' ? 'k_message' : 'k_order'))} #${esc(R.ref).slice(0, 8)}</h3>
      ${keys.map((k) => `<div><span class="muted">${esc(T('f_' + k))}</span><div data-f="${k}">${esc(d[k] == null ? '-' : d[k])}</div></div>`).join('')}
      <div class="notice" data-opx="logged">${esc(T('rLogged'))}</div><button type="button" class="full" data-act="opx_skip">${esc(T('close'))}</button></div>`;
  }
  return `<div class="stack" data-opx="revform"><h3>${esc(T('reveal'))}</h3><div class="muted">${esc(T('rLogged'))}</div>
    <label for="opx_rr">${esc(T('rReason'))}</label><input id="opx_rr" autocomplete="off">
    ${R.err ? `<div class="notice bad" data-opx="rerr" aria-live="polite">${esc(R.err)}</div>` : ''}
    <div class="row"><button type="button" class="full" data-act="opx_skip">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="opx_revealgo">${esc(T('rGo'))}</button></div></div>`;
}

/* ---------- handlers ---------- */
Object.assign(H, {
  opx_tab: async (a) => { D.tab = a.dataset.v; if (D.tab === 'log') { try { D.log = (await rpc('inbox_unmask_log_list99', { p_limit: 100, p_user: null })) || []; } catch (e) { D.err = eText(e); } } drawMain(); },
  opx_retry: async () => { D.ready = false; drawMain(); await loadMain(); },
  opx_set: async (a) => {
    const k = a.dataset.k, v = a.dataset.val;
    try { await rpc('set_rule', { p_key: k, p_value: v }); toast(T('saved')); await loadMain(); } catch (e) { toast(eText(e)); }
  },
  opx_credit: async () => { const on = !!($('#opx_cr') || {}).checked; try { await rpc('set_rule', { p_key: 'bill_pay_auto_credit_ok', p_value: on }); toast(T('saved')); await loadMain(); } catch (e) { toast(eText(e)); } },
  opx_num: async (a) => {
    const k = a.dataset.k; const v = nnum(($('#opx_n_' + k) || {}).value);
    if (!Number.isFinite(v) || v < 0 || (k === 'inbox_unmask_daily_max' && v < 1)) return toast(lab(ERR.bad_value));
    try { await rpc('set_rule', { p_key: k, p_value: v }); toast(T('saved')); await loadMain(); } catch (e) { toast(eText(e)); }
  },
  opx_numclr: async (a) => { try { await rpc('set_rule', { p_key: a.dataset.k, p_value: null }); toast(T('saved')); await loadMain(); } catch (e) { toast(eText(e)); } },
  opx_dkind: (a) => { D.kind = a.value || (($('#opx_dk') || {}).value) || 'supplier'; drawMain(); },
  opx_defsave: async () => {
    const id = ($('#opx_dp') || {}).value; if (!id) return;
    try { await rpc('bill_pay_default_set99', { p_kind: D.kind, p_id: id, p_mode: ($('#opx_dm') || {}).value || null, p_credit: !!($('#opx_dc') || {}).checked, p_note: null }); toast(T('saved')); await loadMain(); } catch (e) { toast(eText(e)); }
  },
  opx_lretry: async () => { D.list = null; drawList(); await loadList(); },
  opx_lpay: async (a) => { const ok = await openPaySheet(a.dataset.k, a.dataset.r); if (!ok) toast(lab(ERR.nothing_due)); },
  opx_mode: (a) => { SH.mode = a.dataset.v; const amt = ($('#opx_amt') || {}).value; SH.msg = null; drawSheet(); const el = $('#opx_amt'); if (el && amt != null) el.value = amt; },
  opx_skip: () => { SH.info = null; SH.rev = null; closeSheet(); if (D.list) loadList(); },
  opx_pay: async (a) => {
    if (!SH.info) return;
    const amt = nnum(($('#opx_amt') || {}).value);
    if (!Number.isFinite(amt) || amt <= 0) { SH.msg = { ok: false, t: lab(ERR.bad_amount) }; drawSheet(); return; }
    const confirm = !!(a && a.dataset && a.dataset.confirm);
    try {
      const r = await rpc('bill_pay_record', { p_kind: SH.kind, p_ref: SH.ref, p_mode: SH.mode, p_amount: amt, p_client: SH.cid, p_note: (($('#opx_note') || {}).value || '').trim() || null, p_confirm_dup: confirm });
      if (r && r.needs_confirm) { SH.warn = r.warnings || []; SH.msg = null; drawSheet(); return; }
      SH.warn = null;
      if (r && r.dup) { SH.msg = { ok: true, t: T('dup') }; SH.left = 0; drawSheet(); return; }
      SH.left = Number(r.remaining);
      SH.info.paid = Number(SH.info.paid) + Number(r.amount); SH.info.remaining = Math.max(0, Number(r.remaining)); SH.cid = rid();
      SH.msg = { ok: true, t: SH.left > 0.004 ? T('doneLeft') + ' ' + fm(SH.left) : T('done') };
      drawSheet(); toast(T('done'));
      if (D.list) loadList();
    } catch (e) { SH.msg = { ok: false, t: eText(e) }; drawSheet(); }
  },
  opx_pretry: async () => { D.pii = null; drawPii(); await loadPii(); },
  opx_reveal: (a) => { SH.rev = { kind: a.dataset.k, ref: a.dataset.r, data: null, err: null }; openSheet(revealHTML()); },
  opx_revealgo: async () => {
    const R = SH.rev; if (!R) return;
    try {
      const r = await rpc('inbox_unmask', { p_kind: R.kind, p_id: String(R.ref), p_reason: (($('#opx_rr') || {}).value || '').trim() || null });
      if (r && r.ok === false) { R.err = r.error === 'rate_limited' ? lab(ERR.rate_limited) : (r.error || 'error'); openSheet(revealHTML()); return; }
      R.data = r.data; openSheet(revealHTML());
    } catch (e) { R.err = eText(e); openSheet(revealHTML()); }
  },
});

async function viewOptionsX() {
  D.ready = false; D.err = null; D.tab = D.tab || 'pay';
  shell(T('title'), '<div id="opx_body"></div>', true);
  drawMain(); await loadMain();
}
async function viewBillPay() {
  D.list = null; D.listErr = null;
  shell(T('unpaid'), '<div id="opx_list"></div>', true);
  drawList(); await loadList();
}
async function viewInboxPii() {
  D.pii = null; D.piiErr = null;
  shell(T('openPii'), '<div id="opx_pii"></div>', true);
  drawPii(); await loadPii();
}
installHook();
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { optionsx: viewOptionsX, billpay: viewBillPay, inboxpii: viewInboxPii });
B.optionsx = { X, ERR, REC, RULE_OPTS, SH, D, HOOKS, sheetHTML, revealHTML, payTab, piiTab, logTab, drawList, drawPii, installHook, eText };
})();
