/* Islamia BOS · What's new (#/whatsnew). A static, phone-width list of recent features grouped by area, in plain words.
   Each item has one Open button that goes to its screen (A.go = location.hash). Routes are the ones registered in web/ia.js.
   "Seen" marks live in localStorage (per browser; try/catch). An item shows a New dot until its Open button has been tapped once.
   Handlers are prefixed wn_. English mode has no Bangla letters; Bangla mode keeps common English words in Bangla letters. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.L) return;
const { esc, shell, H } = A;
const L = B.L, lab = B.lab;
const T = (k) => lab(X[k]);
const KEY = 'bos_whatsnew_seen';
const X = {
  title: L('নতুন কী আছে', "What's new", "What's new"),
  intro: L('সাম্প্রতিক নতুন ফিচারগুলো এক জায়গায়। "খুলুন" চাপলে সেই স্ক্রিন খুলবে।', 'Recent new features in one place. Tap Open to go to that screen.', 'Recent নতুন feature এক জায়গায়। Open চাপলে সেই screen খুলবে।'),
  new: L('নতুন', 'New', 'New'), seen: L('দেখা হয়েছে', 'Seen', 'Seen'), open: L('খুলুন', 'Open', 'Open'),
};
// areas, in the order they are shown
const AREAS = [
  ['sale', L('বিক্রি ও POS', 'Sales & POS', 'Sale ও POS')],
  ['cust', L('গ্রাহক ও টেমপ্লেট', 'Customers & templates', 'Customer ও Template')],
  ['item', L('আইটেম ও ক্যাটাগরি', 'Items & categories', 'Item ও Category')],
  ['purch', L('ক্রয় ও স্ক্যান', 'Purchasing & scan', 'Purchase ও Scan')],
  ['factory', L('কারখানা ও খরচ', 'Factory & costs', 'Factory ও Cost')],
  ['settings', L('সেটিংস ও সেটআপ', 'Settings & setup', 'Settings ও Setup')],
];
// one row per feature: id (also the seen key), area, route (must exist in ia.js), title, one-line benefit
const ITEMS = [
  { id: 'invoice', g: 'sale', route: 'invoiceview',
    t: L('বিক্রির পরে ইনভয়েস', 'Invoice after a sale', 'Sale-এর পরে Invoice'),
    b: L('বিক্রি শেষে ইনভয়েস খুলে প্রিন্ট করুন বা পাঠান।', 'After a sale, open the invoice and print it or send it.', 'Sale শেষে invoice খুলে print করুন বা পাঠান।') },
  { id: 'cashdrawer', g: 'sale', route: 'cashdrawer',
    t: L('ক্যাশ ড্রয়ার', 'Cash drawer', 'Cash drawer'),
    b: L('ড্রয়ারের টাকা ও প্রতিটি লেনদেনের হিসাব এক জায়গায়।', 'The cash in the drawer and each movement, in one place.', 'Drawer-এর cash ও প্রতিটি movement এক জায়গায়।') },
  { id: 'inbox', g: 'sale', route: 'inbox',
    t: L('বার্তা ইনবক্স', 'Message inbox', 'Message inbox'),
    b: L('ফেসবুক, ইনস্টাগ্রাম ও ওয়েবের বার্তা এক জায়গায়।', 'Messages from Facebook, Instagram and the web, in one place.', 'Facebook, Instagram ও web-এর message এক জায়গায়।') },
  { id: 'templates', g: 'cust', route: 'templates',
    t: L('রসিদ ও বার্তার টেমপ্লেট', 'Receipt and message templates', 'Receipt ও message template'),
    b: L('রসিদ, ইনভয়েস ও বার্তার লেখা নিজের মতো সাজান।', 'Shape receipts, invoices and messages the way you want.', 'Receipt, invoice ও message নিজের মতো সাজান।') },
  { id: 'categories', g: 'item', route: 'categories',
    t: L('ক্যাটাগরি ও সাব-ক্যাটাগরি', 'Categories and sub-categories', 'Category ও Sub-category'),
    b: L('পণ্যগুলো ক্যাটাগরিতে ভাগ করে গুছিয়ে রাখুন।', 'Sort your items into categories and sub-categories.', 'Item-গুলো category-তে ভাগ করে গুছিয়ে রাখুন।') },
  { id: 'itemimg', g: 'item', route: 'itemimg',
    t: L('আইটেমের ছবি', 'Item photos', 'Item-এর photo'),
    b: L('পণ্যের ছবি যোগ করুন, যাতে বিক্রির সময় ছবি দেখা যায়।', 'Add product photos so they show up while selling.', 'Product-এর photo যোগ করুন, sale-এর সময় দেখা যাবে।') },
  { id: 'billpay', g: 'purch', route: 'billpay',
    t: L('পেমেন্ট ছাড়া বিল', 'Bills without payment', 'Payment ছাড়া bill'),
    b: L('যে ক্রয় বিলের টাকা এখনও দেওয়া হয়নি, সেগুলো একসাথে দেখুন।', 'See all purchase bills still waiting for payment.', 'যে purchase bill-এর payment বাকি, সব একসাথে দেখুন।') },
  { id: 'purchaseprint', g: 'purch', route: 'purchaseprint',
    t: L('ক্রয় বিল প্রিন্ট ও পাঠান', 'Print and send purchase bills', 'Purchase bill print ও পাঠান'),
    b: L('ক্রয় বিল প্রিন্ট করুন বা সরবরাহকারীকে পাঠান।', 'Print a purchase bill or send it to the supplier.', 'Purchase bill print করুন বা supplier-কে পাঠান।') },
  { id: 'scan', g: 'purch', route: 'scan',
    t: L('ছবি থেকে এন্ট্রি', 'Scan a bill or list', 'ছবি থেকে entry'),
    b: L('বিল বা পণ্যের তালিকার ছবি তুলে এন্ট্রি করুন।', 'Take a photo of a bill or item list and make the entries.', 'Bill বা item list-এর photo তুলে entry করুন।') },
  { id: 'landed', g: 'purch', route: 'landed',
    t: L('মাল আনার খরচ (Landed cost)', 'Landed cost (freight, duty)', 'Landed cost (freight, duty)'),
    b: L('ফ্রেইট ও ডিউটির মতো খরচ মালের কস্টে যোগ করুন।', 'Add freight, duty and similar costs to the cost of the goods.', 'Freight ও duty-র মতো খরচ মালের cost-এ যোগ করুন।') },
  { id: 'recipebook', g: 'factory', route: 'recipebook',
    t: L('কারিগরের রেসিপি বই', 'Artisan recipe book', 'Artisan-এর recipe book'),
    b: L('কারিগরদের রেসিপি এক জায়গায় দেখুন।', 'See the artisans\' recipes in one place.', 'Artisan-দের recipe এক জায়গায় দেখুন।') },
  { id: 'costing', g: 'factory', route: 'costing',
    t: L('খরচ ও ওভারহেড', 'Costing and overhead', 'Costing ও overhead'),
    b: L('উৎপাদনের খরচ ও ওভারহেড হিসাব করে দেখুন।', 'Work out the production cost and overheads.', 'Production-এর cost ও overhead হিসাব করে দেখুন।') },
  { id: 'switchboard', g: 'settings', route: 'switchboard',
    t: L('সুইচবোর্ডের প্রস্তাব', 'Switchboard recommendations', 'Switchboard-এর recommendation'),
    b: L('কোন সুইচ কোন অবস্থায় থাকবে, তার প্রস্তাব দেখে ঠিক করুন।', 'See the suggested setting for each switch and decide.', 'প্রতিটি switch-এর recommended অবস্থা দেখে ঠিক করুন।') },
  { id: 'setupadvisor', g: 'settings', route: 'setupadvisor',
    t: L('চালু করার গাইড', 'Setup advisor', 'Setup advisor'),
    b: L('কোন সেটিং বাকি আর কোনটা প্রস্তাবিত, ধাপে ধাপে দেখুন।', 'See which settings are missing or suggested, step by step.', 'কোন setting বাকি ও কোনটা recommended, step by step দেখুন।') },
  { id: 'optviews', g: 'settings', route: 'optviews',
    t: L('কে কী দেখবে (দেখান / লুকান / তালা)', 'Who sees what (Show / Hide / Locked)', 'কে কী দেখবে (Show / Hide / Locked)'),
    b: L('কোন স্ক্রিন কাকে দেখাবে, লুকাবে বা তালা দেবে, ঠিক করুন।', 'Choose which screens each person sees, which are hidden and which are locked.', 'কোন screen কাকে দেখাবে, লুকাবে বা লক করবে ঠিক করুন।') },
];
// seen marks: a Set of item ids, read and written defensively (private window, blocked storage)
function seenSet() {
  try { const v = JSON.parse(localStorage.getItem(KEY) || '[]'); return new Set(Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []); } catch (e) { return new Set(); }
}
function markSeen(id) {
  try { const s = seenSet(); s.add(id); localStorage.setItem(KEY, JSON.stringify([...s])); } catch (e) { /* storage blocked: the New dot stays until the next visit */ }
}
const DOT = 'display:inline-block;background:var(--ruby);color:#fff;border-radius:999px;padding:2px 10px;font-size:.75rem;font-weight:700;line-height:1.6';
function item(x, seen) {
  const badge = seen.has(x.id)
    ? `<span class="chip">✓ ${esc(T('seen'))}</span>`
    : `<span class="wn_dot" data-state="new" style="${DOT}">${esc(T('new'))}</span>`;
  return `<div class="card stack" data-wn="${esc(x.id)}">
    <div class="row between wrap"><b>${esc(lab(x.t))}</b>${badge}</div>
    <div class="muted">${esc(lab(x.b))}</div>
    <button type="button" class="btn primary full" style="min-height:44px" data-act="wn_open" data-k="${esc(x.id)}">${esc(T('open'))}</button>
  </div>`;
}
function view() {
  const seen = seenSet();
  const body = AREAS.map(([g, name]) => {
    const rows = ITEMS.filter((x) => x.g === g).map((x) => item(x, seen)).join('');
    return rows ? `<h3 style="margin:18px 0 8px">${esc(lab(name))}</h3>${rows}` : '';
  }).join('');
  shell(T('title'), `<p class="muted">${esc(T('intro'))}</p>${body}`, true);
}
Object.assign(H, {
  wn_open: (a) => {
    const id = a.dataset.k, it = ITEMS.find((x) => x.id === id);
    if (!it) return;
    markSeen(id);
    A.go(it.route);
  },
});
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { whatsnew: view });
})();
