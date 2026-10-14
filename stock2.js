/* Islamia BOS · Stock hub (#/stock): levels, item ledger, expiring soon, goods in transit, and the stock actions
   (opening balance, wastage, count adjust, issue, production in, transfer) as bottom sheets.
   Server does the work (phase10.sql RPCs); this screen only guides. Cost figures are shown ONLY when the server returns them (null = hidden).
   Also exports B.s2: small helpers shared with purchase.js (client ids, photos, grants, error text). Loaded after items2.js / nav.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const q4 = (n) => (n === null || n === undefined ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const money = (n) => '৳ ' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const dt = (iso) => new Date(iso).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Dhaka' });
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));

// ---------- labels (3 modes) ----------
const X = {
  title: L('স্টক', 'Stock', 'Stock'), levels: L('মজুত', 'On hand', 'Stock (মজুত)'), expiring: L('মেয়াদ শেষের পথে', 'Expiring soon', 'Expiry (মেয়াদ)'), transit: L('পথে আছে', 'In transit', 'Transit (পথে)'),
  search: L('নাম বা কোড খুঁজুন', 'Search name or code', 'নাম বা code খুঁজুন'), filter: L('ফিল্টার', 'Filter', 'Filter'), apply: L('প্রয়োগ', 'Apply', 'Apply'), reset: L('মুছে দিন', 'Reset', 'Reset'),
  all: L('সব', 'All', 'All'), allLoc: L('সব জায়গা', 'All locations', 'সব Location'), category: L('ক্যাটাগরি', 'Category', 'Category'), location: L('জায়গা', 'Location', 'Location'),
  belowMin: L('শুধু ন্যূনতমের নিচে', 'Only below minimum', 'শুধু Minimum-এর নিচে'), showZero: L('শূন্য মজুতও দেখান', 'Show zero stock too', 'Zero stock-ও দেখান'),
  nItems: L('টি পণ্য', 'items', 'items'), nBelow: L('ন্যূনতমের নিচে', 'Below minimum', 'Minimum-এর নিচে'), totalValue: L('মজুতের মূল্য', 'Stock value', 'Stock-এর value'),
  avg: L('গড় দাম', 'avg cost', 'avg cost'), chipOut: L('শেষ', 'Out', 'Out'), chipLow: L('ন্যূনতমের নিচে', 'Below min', 'Min-এর নিচে'), min: L('ন্যূনতম', 'min', 'min'),
  none: L('কোনো স্টক নেই', 'No stock to show', 'কোনো stock নেই'), noneHint: L('শুধু "স্টক ট্র্যাক" করা পণ্য এখানে আসে। পণ্যের অ্যাডভান্স অপশনে চালু করুন।', 'Only items marked "track stock" appear here. Turn it on in the product advance options.', 'শুধু "Stock track" করা product এখানে আসে। Product-এর Advance Option-এ চালু করুন।'),
  more: L('আরও দেখুন', 'Show more', 'আরও দেখুন'), actions: L('স্টকের কাজ', 'Stock actions', 'Stock-এর কাজ'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  a_open: L('প্রারম্ভিক স্টক বসান', 'Opening balance', 'Opening balance'), a_waste: L('নষ্ট মাল বাদ দিন', 'Write off wastage', 'Wastage write-off'), a_count: L('গণনা অনুযায়ী ঠিক করুন', 'Adjust to a count', 'Count অনুযায়ী ঠিক'),
  a_issue: L('উৎপাদনে কাঁচামাল দিন', 'Issue to production', 'Production-এ issue'), a_prod: L('উৎপাদিত মাল স্টকে তুলুন', 'Production in', 'Production-এর মাল Stock-এ'), a_xfer: L('অন্য জায়গায় পাঠান', 'Transfer out', 'Transfer (পাঠান)'),
  item: L('পণ্য', 'Item', 'Item'), itemph: L('কোড বা নাম লিখুন', 'Type code or name', 'Code বা নাম লিখুন'), unit: L('একক', 'Unit', 'Unit'), baseUnit: L('— বেস একক —', '— base unit —', '— base unit —'),
  baseIs: L('বেস একক', 'Base unit', 'Base unit'), qty: L('পরিমাণ', 'Quantity', 'Quantity'), counted: L('গুনে পাওয়া পরিমাণ', 'Counted quantity', 'Count করা quantity'),
  cost: L('একক দাম ৳ (বেছে নেওয়া এককে)', 'Unit cost ৳ (per chosen unit)', 'Unit cost ৳ (chosen unit-এ)'), note: L('নোট', 'Note', 'Note'), noteReq: L('নোট (আবশ্যক)', 'Note (required)', 'Note (আবশ্যক)'),
  reason: L('কারণ', 'Reason', 'Reason'), photo: L('ছবি', 'Photo', 'Photo'), photoReq: L('এই পরিমাণে ছবি লাগবে', 'A photo is needed for this quantity', 'এই quantity-তে photo লাগবে'),
  addPhoto: L('ছবি তুলুন / বাছুন', 'Take / choose photo', 'Photo তুলুন / বাছুন'), upl: L('ছবি আপলোড হচ্ছে…', 'Uploading photo…', 'Photo upload হচ্ছে…'),
  madeAt: L('তৈরির সময়', 'Made at', 'Made at (তৈরির সময়)'), toLoc: L('কোথায় পাঠাবেন', 'Send to', 'কোথায় পাঠাবেন'), fromLoc: L('কোথা থেকে', 'From', 'From'),
  save: L('সংরক্ষণ', 'Save', 'Save'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ', 'Close', 'Close'), done: L('হয়েছে', 'Done', 'Done'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  dup: L('আগেই সংরক্ষিত — আবার হয়নি', 'Already saved — nothing was added twice', 'আগেই saved — আবার হয়নি'),
  ledger: L('স্টকের খাতা', 'Stock ledger', 'Stock ledger'), noMoves: L('কোনো লেনদেন নেই', 'No movements', 'কোনো movement নেই'), onHand: L('এখন আছে', 'On hand now', 'এখন আছে'),
  expH: L('ঘণ্টার মধ্যে', 'hours ahead', 'hours-এর মধ্যে'), hLeft: L('ঘণ্টা বাকি', 'h left', 'h বাকি'), expiredAgo: L('মেয়াদ গেছে', 'Expired', 'Expired'), hAgo: L('ঘণ্টা আগে', 'h ago', 'h আগে'),
  expEmpty: L('এই সময়ে কোনো মাল মেয়াদ শেষ হচ্ছে না', 'Nothing expires in this window', 'এই সময়ে কোনো মাল expire হচ্ছে না'),
  expOff: L('মেয়াদ বন্ধ — শেলফ-লাইফের নিয়ম নেই', 'Expiry is off — no shelf-life rule', 'Expiry বন্ধ — shelf-life rule নেই'),
  expOffHint: L('শুধু শেলফ-লাইফের নিয়ম থাকা পণ্যের ব্যাচে মেয়াদ বসে। নিয়ম ছাড়া পণ্যে মেয়াদের সুবিধা বন্ধ।', 'Only batches of items that have a shelf-life rule get an expiry. Items without a rule have expiry switched off.', 'Shelf-life rule থাকা item-এর batch-এ expiry বসে। Rule ছাড়া item-এ expiry বন্ধ।'),
  writeOff: L('বাদ দিন', 'Write off', 'Write off'), batchQty: L('ব্যাচে বাকি', 'In batch', 'Batch-এ বাকি'),
  trEmpty: L('পথে কোনো মাল নেই', 'Nothing in transit', 'Transit-এ কোনো মাল নেই'), receive: L('গ্রহণ', 'Receive', 'Receive'), cancelX: L('ফিরিয়ে নিন', 'Take back', 'Take back'),
  recvQty: L('কত পেলেন (বেস এককে)', 'Quantity received (base unit)', 'কত পেলেন (base unit)'), sent: L('পাঠানো', 'Sent', 'Sent'), shortBy: L('কম পড়েছে — মালিককে জানানো হবে', 'Short — the owner will be told', 'কম — Owner-কে জানানো হবে'),
  confirmCancel: L('পাঠানো বাতিল করে মাল ফিরিয়ে নেবেন?', 'Cancel the transfer and take the goods back?', 'Transfer cancel করে মাল ফিরিয়ে নেবেন?'),
  recon: L('খাতা মেলান', 'Reconcile', 'Ledger মেলান'), reconOk: L('সব মিলেছে ✓', 'Everything matches ✓', 'সব মিলেছে ✓'), reconBad: L('মিলছে না', 'Mismatch', 'মিলছে না'),
  reconFix: L('ক্যাশ ঠিক করুন (খাতা বদলাবে না)', 'Repair the cache (ledger is never changed)', 'Cache ঠিক করুন (ledger বদলাবে না)'), ledgerQty: L('খাতা', 'ledger', 'ledger'), cachedQty: L('ক্যাশ', 'cache', 'cache'),
  needItem: L('পণ্য বাছুন', 'Choose an item', 'Item বাছুন'), needQty: L('পরিমাণ ঠিক নয়', 'Quantity is not valid', 'Quantity ঠিক নয়'), needNote: L('নোট লিখুন', 'Write a note', 'Note লিখুন'),
  needReason: L('কারণ বাছুন', 'Choose a reason', 'Reason বাছুন'), needTo: L('গন্তব্য বাছুন', 'Choose where to send', 'গন্তব্য বাছুন'), badCost: L('দাম ঠিক নয়', 'Cost is not valid', 'Cost ঠিক নয়'),
  delta: L('পার্থক্য', 'Difference', 'Difference'), countDone: L('গণনা মেলানো হয়েছে', 'Count posted', 'Count posted'), sentOk: L('পাঠানো হয়েছে — গ্রহণের অপেক্ষায়', 'Sent — waiting to be received', 'Sent — receive-এর অপেক্ষায়'),
  wa: L('অনুমোদন', 'Approvals', 'Approval'), waEmpty: L('অনুমোদনের অপেক্ষায় কিছু নেই ✓', 'Nothing waiting for approval ✓', 'Approval-এর অপেক্ষায় কিছু নেই ✓'),
  waTitle: L('বড় নষ্ট মাল বাদ — অনুমোদন', 'Large wastage write-off — approval', 'বড় wastage write-off — approval'), approve: L('অনুমোদন', 'Approve', 'Approve'), reject: L('নামঞ্জুর', 'Reject', 'Reject'),
  takeBack: L('আমার অনুরোধ ফিরিয়ে নিন', 'Take my request back', 'আমার request ফিরিয়ে নিন'), sentApproval: L('অনুমোদনের জন্য পাঠানো হয়েছে — অনুমোদন হলে স্টক কমবে', 'Sent for approval — the stock falls when it is approved', 'Approval-এর জন্য পাঠানো — approve হলে stock কমবে'),
  waNote: L('নামঞ্জুরের কারণ (আবশ্যক)', 'Reason for rejecting (required)', 'Reject-এর reason (আবশ্যক)'), waMine: L('আমার অনুরোধ', 'My request', 'আমার request'), waBy: L('অনুরোধ', 'Requested by', 'Request করেছেন'),
  waDone: L('সিদ্ধান্ত হয়েছে', 'Decision saved', 'Decision saved'), waWho: L('অন্য কেউ অনুমোদন দেবেন', 'Someone else must approve', 'অন্য কেউ approve করবেন'), more2: L('আরও অপশন', 'More options', 'আরও option'),
  scan: L('স্ক্যান', 'Scan', 'Scan'), buyU: L('কেনা', 'Buy', 'Buy'), sellU: L('বিক্রি', 'Sell', 'Sell'), ledgerOpen: L('স্টকের খাতা দেখুন', 'Open the ledger', 'Ledger দেখুন'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), sqlMissing: L('স্টকের ডেটাবেস অংশ এখনও চালু হয়নি (phase10)', 'The stock database part is not installed yet (phase10)', 'Stock-এর database অংশ চালু হয়নি (phase10)'),
};
const T = (k) => lab(X[k]);
// ledger reasons
const RS = { opening: L('প্রারম্ভিক', 'Opening', 'Opening'), purchase_in: L('কেনা', 'Purchase', 'Purchase'), purchase_return: L('ক্রয় ফেরত', 'Purchase return', 'Purchase return'), sale_out: L('বিক্রি', 'Sale', 'Sale'),
  sale_void_in: L('বিক্রি বাতিল', 'Sale voided', 'Sale void'), sale_return: L('বিক্রি ফেরত', 'Sale return', 'Sale return'), issue_out: L('উৎপাদনে দেওয়া', 'Issued', 'Issued'), production_in: L('উৎপাদন', 'Production', 'Production'),
  transfer_out: L('পাঠানো', 'Transfer out', 'Transfer out'), transfer_in: L('গ্রহণ', 'Transfer in', 'Transfer in'), wastage: L('নষ্ট', 'Wastage', 'Wastage'), count_adjust: L('গণনা ঠিক', 'Count', 'Count adjust'), reversal: L('উল্টানো', 'Reversal', 'Reversal') };
// server error text -> friendly (shared with purchase.js). Order matters little: keys are whole words.
const ERR = {
  item_not_counted: L('এই আইটেম ব্যবসার হিসাবে ধরা নয় (সম্পদ / ভোগ্য / যন্ত্রপাতি) — স্টকে আসে না', 'This item is not counted in the business (asset / consumable / tool) — it has no stock', 'এই Item business-এর হিসাবে ধরা নয় — stock-এ আসে না'),
  asset_qty_too_large: L('এক লাইনে ২০০-র বেশি সম্পদ হয় না — লাইন ভাগ করুন', 'More than 200 assets on one line is not allowed — split the line', 'এক line-এ ২০০-র বেশি asset হয় না — line ভাগ করুন'),
  unit_unknown: L('এই এককের রূপান্তর জানা নেই — পণ্যের বেস এককে লিখুন বা রূপান্তর বসান', 'This unit has no conversion for the item — use the base unit or add a conversion', 'এই unit-এর conversion জানা নেই — base unit-এ লিখুন বা conversion বসান'),
  insufficient_stock: L('মজুতে এত নেই', 'Not enough stock on hand', 'Stock-এ এত নেই'), item_not_tracked: L('এই পণ্যের স্টক ট্র্যাক বন্ধ', 'Stock tracking is off for this item', 'এই item-এ stock track বন্ধ'),
  item_not_found: L('পণ্য পাওয়া যায়নি', 'Item not found', 'Item পাওয়া যায়নি'), bad_qty: L('পরিমাণ ঠিক নয়', 'Quantity is not valid', 'Quantity ঠিক নয়'), bad_cost: L('দাম ঠিক নয়', 'Cost is not valid', 'Cost ঠিক নয়'),
  bad_reason: L('কারণ ঠিক নয়', 'Reason is not valid', 'Reason ঠিক নয়'), photo_required: L('এই পরিমাণে ছবি লাগবে', 'A photo is required for this quantity', 'এই quantity-তে photo লাগবে'), bad_photo: L('ছবির পথ ঠিক নয়', 'Photo path is not valid', 'Photo path ঠিক নয়'),
  opening_exists: L('এই পণ্যের প্রারম্ভিক স্টক আগেই বসানো — ভুল হলে "গণনা অনুযায়ী ঠিক" করুন', 'Opening stock is already set — fix mistakes with "Adjust to a count"', 'Opening stock আগেই set — ভুল হলে "Count adjust" করুন'),
  note_required: L('নোট আবশ্যক', 'A note is required', 'Note আবশ্যক'), bad_location: L('গন্তব্য ঠিক নয়', 'Destination is not valid', 'গন্তব্য ঠিক নয়'), over_received: L('পাঠানোর চেয়ে বেশি গ্রহণ করা যায় না', 'Cannot receive more than was sent', 'পাঠানোর চেয়ে বেশি receive হয় না'),
  not_in_transit: L('এটি আর পথে নেই', 'This is no longer in transit', 'এটি আর transit-এ নেই'), batch_empty: L('ব্যাচে কিছু বাকি নেই', 'The batch is empty', 'Batch-এ কিছু নেই'), batch_not_found: L('ব্যাচ পাওয়া যায়নি', 'Batch not found', 'Batch পাওয়া যায়নি'),
  batch_short: L('ব্যাচে এত নেই', 'Not enough in that batch', 'Batch-এ এত নেই'), bad_date: L('তারিখ ঠিক নয়', 'Date is not valid', 'Date ঠিক নয়'),
  duplicate_bill: L('এই সাপ্লায়ারের এই বিল নম্বর আগেই আছে', 'This supplier already has this bill number', 'এই supplier-এর এই bill no. আগেই আছে'), client_id_taken: L('এই অনুরোধ অন্য কারও — আবার চেষ্টা করুন', 'This request belongs to someone else — try again', 'এই request অন্য কারও — আবার চেষ্টা করুন'),
  supplier_not_found: L('সাপ্লায়ার পাওয়া যায়নি', 'Supplier not found', 'Supplier পাওয়া যায়নি'), no_lines: L('অন্তত একটি লাইন লাগবে', 'Add at least one line', 'অন্তত একটি line লাগবে'), bad_discount: L('ছাড় ঠিক নয়', 'Discount is not valid', 'Discount ঠিক নয়'),
  description_required: L('লাইনে পণ্য বা বিবরণ লাগবে', 'Each line needs an item or a description', 'প্রতি line-এ item বা description লাগবে'), reason_required: L('ফেরতের কারণ বাছুন', 'Choose the return reason', 'Return reason বাছুন'),
  bad_ref_bill: L('মূল বিল ঠিক নয়', 'The original bill is not valid', 'মূল bill ঠিক নয়'), not_draft: L('এটি আর খসড়া নয়', 'This is no longer a draft', 'এটি আর draft নয়'),
  poster_must_differ: L('যে বিল লিখেছে সে নিজে পোস্ট করতে পারবে না', 'The person who wrote the bill cannot post it', 'যে bill লিখেছে সে নিজে post করতে পারবে না'),
  overpaid: L('টাকা বাকির চেয়ে বেশি হতে পারে না', 'Payment cannot be more than what is owed', 'Payment due-এর বেশি হতে পারে না'), no_payments: L('পেমেন্ট লিখুন', 'Enter a payment', 'Payment লিখুন'), bad_mode: L('পেমেন্টের ধরন ঠিক নয়', 'Payment mode is not valid', 'Payment mode ঠিক নয়'),
  bad_amount: L('টাকার অঙ্ক ঠিক নয়', 'Amount is not valid', 'Amount ঠিক নয়'), void_the_bill: L('বিলের সাথে দেওয়া পেমেন্ট বিল বাতিল করলে যাবে', 'A payment made with a bill goes when the bill is voided', 'Bill-এর সাথের payment, bill void করলে যাবে'),
  no_payment_on_return: L('ফেরতে পেমেন্ট চলে না', 'A return cannot carry a payment', 'Return-এ payment চলে না'), cannot_change_kind_or_location: L('খসড়ার ধরন বা জায়গা বদলানো যায় না', 'Cannot change the kind or location of a draft', 'Draft-এর kind বা location বদলায় না'),
  return_needs_bill: L('ফেরতের জন্য মূল বিল বাছুন', 'Choose the original bill for a return', 'Return-এর জন্য মূল bill বাছুন'), return_exceeds_bill: L('ফেরত পরিমাণ মূল বিলের বাকির চেয়ে বেশি', 'The return is more than what is left on the original bill', 'Return quantity মূল bill-এর বাকির চেয়ে বেশি'),
  return_cost_above_bill: L('ফেরতের দাম মূল বিলের দামের চেয়ে বেশি', 'The return cost is above the bill cost', 'Return-এর দাম মূল bill-এর দামের চেয়ে বেশি'), purchase_return_unreferenced: L('এই ফেরতের মূল বিল নেই', 'This return has no original bill', 'এই return-এর মূল bill নেই'),
  bad_kind: L('ধরন ঠিক নয়', 'Kind is not valid', 'Kind ঠিক নয়'), already_void: L('আগেই বাতিল', 'Already voided', 'আগেই void'),
  own_request: L('নিজের অনুরোধ নিজে অনুমোদন করা যায় না', 'You cannot approve your own request', 'নিজের request নিজে approve করা যায় না'), already_decided: L('এর সিদ্ধান্ত আগেই হয়ে গেছে', 'This was already decided', 'এর decision আগেই হয়ে গেছে'),
  client_id_taken: L('এই অনুরোধের নম্বর অন্য কেউ ব্যবহার করেছে — আবার চেষ্টা করুন', 'Another user already used this request id — try again', 'এই request id অন্য user আগেই use করেছে — আবার চেষ্টা করুন'),
  grn_link_required: L('GRN source চালু: এই bill-এর সাথে GRN জুড়ুন, তারপর post করুন', 'GRN is the stock source: link this bill to its GRN before posting', 'GRN source চালু: bill-এর সাথে GRN জুড়ে তারপর post করুন'),
  void_has_return: L('এই bill-এর বিপরীতে return আছে; আগে return বাতিল করুন', 'A posted return refers to this bill; void the return first', 'এই bill-এর return আছে; আগে return void করুন'),
  void_would_go_negative: L('মাল ব্যবহার/বিক্রি হয়ে গেছে, bill বাতিল করলে stock negative হবে', 'The goods were used or sold; voiding would make stock negative', 'মাল use/sale হয়ে গেছে, void করলে stock negative হবে'),
  void_has_grn_batch: L('এই bill-এর চালু GRN batch আছে', 'Live GRN batches exist for this bill', 'এই bill-এর live GRN batch আছে'),
  production_negative_reason_needed: L('stock-এর বেশি কাঁচামাল নিতে কারণ লিখুন', 'Write a reason to use more ingredient than the stock on hand', 'Stock-এর বেশি ingredient নিতে reason লিখুন'),
  expired_stock_blocked: L('মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ আছে (মালিকের সেটিং)', 'Selling expired stock is blocked (owner setting)', 'মেয়াদোত্তীর্ণ মাল বিক্রি বন্ধ (owner setting)'),
  refund_exceeds_credit: L('সাপ্লায়ারের কাছে এত জমা নেই', 'The supplier does not hold that much credit', 'Supplier-এর কাছে এত credit নেই'), sale_has_returns: L('এই বিক্রির ফেরত আছে — আগে ফেরত বাতিল করুন', 'This sale has returns — void the return first', 'এই sale-এর return আছে — আগে return void করুন'),
  return_exceeds_sale: L('ফেরত পরিমাণ বিক্রির বাকির চেয়ে বেশি', 'More than what is left to return', 'Return quantity বাকির চেয়ে বেশি'), line_not_in_sale: L('এই পণ্য ওই বিক্রিতে নেই', 'That item is not in the sale', 'এই item ওই sale-এ নেই'),
  sale_not_found: L('বিক্রি পাওয়া যায়নি', 'Sale not found', 'Sale পাওয়া যায়নি'), sale_not_done: L('এই বিক্রি বাতিল', 'This sale is voided', 'এই sale void'),
  refund_mode_required: L('ফেরতের টাকা কীভাবে দিলেন বাছুন', 'Choose how the money was handed back', 'Refund কীভাবে দিলেন বাছুন'),
};
const NOPERM = L('এই কাজের অনুমতি নেই', 'You are not allowed to do this', 'এই কাজের permission নেই');
// show the server error nicely. ctx = { grant, loc, context } lets "not allowed" offer the emergency request when the owner switched it on.
function errToast(e, ctx) {
  const m = String((e && e.message) || ''), hint = (e && (e.hint || e.details)) || '';
  if (/period_closed/.test(m)) return fail(e);
  for (const k of Object.keys(ERR)) if (new RegExp('\\b' + k + '\\b').test(m)) return toast(lab(ERR[k]) + (k === 'insufficient_stock' && hint ? ' · ' + String(hint).slice(0, 60) : ''));
  if (/already void/.test(m)) return toast(lab(ERR.already_void));
  if (/not allowed for this location/.test(m)) return toast(t('err_perm'));
  if (/not allowed|permission denied|row-level/i.test(m)) {
    if (ctx && ctx.grant && B.emergency && B.emergency.allowed(ctx.grant)) return B.emergency.offer({ grant: ctx.grant, loc: ctx.loc === undefined ? null : ctx.loc, context: ctx.context || {}, message: lab(NOPERM) });
    return toast(lab(NOPERM));
  }
  return fail(e);
}

// ---------- shared helpers ----------
const lists = (c) => ((B.ENV && B.ENV.lists && B.ENV.lists[c]) || []).filter((r) => r.active !== false);
const rowL = (r) => ({ bn: r.label_bn, en: r.label_en || undefined, mix: r.label_mix || undefined });
const unitLabel = (code) => { const r = lists('units').find((x) => x.value_code === code); return r ? lab(rowL(r)) : (code || ''); };
const npMode = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* default */ } return m === 'hide' ? 'hide' : 'lock'; };
const LOCS = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); return S.ctx.is_owner || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const allLocs = () => S.ctx.is_owner || (S.ctx.roles || []).includes('management');
const GR = new Map();
async function grant(code, loc) {
  if (S.ctx.is_owner) return true;
  const k = code + '|' + (loc === null || loc === undefined ? '' : loc); if (GR.has(k)) return GR.get(k);
  let v = false;
  try { const r = await sb.rpc('has_grant', { p_code: code, p_loc: loc === undefined ? null : loc }); v = !!(r && !r.error && r.data === true); } catch (e) { v = false; }
  GR.set(k, v); return v;
}
const costOk = async (loc) => !!(S.ctx.is_owner || (S.ctx.perms.ITEM_COST && S.ctx.perms.ITEM_COST.view) || await grant('view_cost', loc));
// photos: stored as a Storage path "<form>/<location>/<id>.jpg" (the bucket policy reads the first two parts); the database keeps only that path (<= 300 chars)
function shrink(file, max = 1280, q = 0.72) {
  return new Promise((res, rej) => { const img = new Image(), u = URL.createObjectURL(file);
    img.onload = () => { const k = Math.min(1, max / Math.max(img.width, img.height)), c = document.createElement('canvas'); c.width = Math.round(img.width * k) || 1; c.height = Math.round(img.height * k) || 1;
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(u); c.toBlob((b) => (b ? res(b) : rej(new Error('image'))), 'image/jpeg', q); };
    img.onerror = () => rej(new Error('image')); img.src = u; });
}
const photoForm = (cands) => (S.ctx.is_owner ? cands[0] : (cands.find((c) => S.ctx.perms[c] && S.ctx.perms[c].enter) || cands[0]));
// cands = storage prefixes in order of preference: the dedicated ones first (STOCK / PURCHASE, grant based, phase12), then the old form codes
// (kept so a database that has not run phase12 yet keeps working: the first prefix the server accepts wins)
async function uploadPhoto(file, cands, loc) {
  const blob = await shrink(file); let last = null;
  for (const c of cands) {
    const path = `${c}/${loc}/${rid()}.jpg`;
    const up = await sb.storage.from('photos').upload(path, blob, { contentType: 'image/jpeg' });
    if (!up.error) return path; last = up.error;
  }
  throw last || new Error('photo');
}
async function thumb(img, path) {
  try { const r = await sb.storage.from('photos').createSignedUrls([path], 3600); const u = r && r.data && r.data[0] && r.data[0].signedUrl; if (u) img.src = u; } catch (e) { /* thumbnail optional */ }
}
const css = document.createElement('style'); css.id = 's2css';
css.textContent = `.s2-bar{position:sticky;bottom:0;z-index:4;display:flex;gap:8px;padding:10px 0 calc(10px + env(safe-area-inset-bottom));background:var(--bg);border-top:1px solid var(--hair);margin-top:14px}
.s2-bar button{flex:1}body.has-bnav .s2-bar{bottom:58px}
.s2-row .sub,.s2-led .sub{font-size:.85rem;color:var(--muted);overflow-wrap:anywhere}.s2-row .nm{overflow-wrap:anywhere}
.s2-row .pr b{display:block;font:700 1.12rem var(--display);color:var(--ink);font-variant-numeric:lining-nums tabular-nums}.s2-row .pr small{display:block;font-size:.8rem;color:var(--muted)}
.s2-led{display:flex;justify-content:space-between;gap:10px;padding:8px 0;border-bottom:1px solid var(--hair)}.s2-led:last-child{border-bottom:0}
.s2-led .q{font:700 1.02rem var(--display);white-space:nowrap;font-variant-numeric:lining-nums tabular-nums}.s2-led .q.neg{color:var(--sig-bad)}
.s2-act{display:flex;align-items:center;gap:10px;width:100%;justify-content:flex-start;text-align:start}.s2-act svg{width:20px;height:20px;flex:none}
.s2-act[disabled]{opacity:.55}.s2-ph{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.s2-ph img{width:84px;height:84px;object-fit:cover;border-radius:10px;border:1px solid var(--hair)}
.s2-ph label.phadd{display:inline-flex;align-items:center;min-height:48px;padding:0 14px;border:1px dashed var(--hair);border-radius:12px;cursor:pointer;margin:0}
.s2-need{color:var(--sig-bad)}.s2-sum{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px}.s2-sum .stat{min-height:64px}
.s2-lockrow svg,.s2-act svg{width:20px;height:20px;flex:none}.ptabs.s2t button{padding:0 8px;flex:1}.s2-bar .sec{flex:0 0 auto}
.s2-dots{min-width:44px;min-height:44px;margin:-8px -8px 0 auto;display:block;font-size:1.25rem;line-height:1;background:none;border:0;color:var(--muted);box-shadow:none}.ptabs .cnt{display:inline-block;min-width:18px;padding:0 5px;border-radius:9px;background:var(--sig-warn,#b26a00);color:#fff;font-size:.75rem}
.s2-lockrow{display:flex;align-items:center;gap:10px;min-height:48px;padding:0 12px;border:1px solid var(--hair);border-radius:12px;color:var(--muted);margin-top:8px}`;
document.head.appendChild(css);
const LOCK = '<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';

// tracked items (for pickers): fetched once
let ITEMS = null;
async function trackedItems() {
  if (ITEMS) return ITEMS;
  // item master: only items counted in the business can be tracked (the server forces tracked off for assets, consumables, tools ...); hidden items stay out of the pickers
  let r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,sell_units,barcode,tracked,is_active,count_in_business,hidden').eq('tracked', true).order('code'));
  if (r.error) r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,base_unit,sell_units,barcode,tracked,is_active').eq('tracked', true).order('code'));
  ITEMS = r.error ? [] : (r.data || []).filter((i) => i.is_active !== false && i.tracked !== false && i.count_in_business !== false && !i.hidden);
  return ITEMS;
}
const itemText = (i) => i.code + ' · ' + nm(i);
const baseOf = (i) => (i && (i.base_unit || i.unit)) || '';
const itemFrom = (items, v) => { const s = String(v || '').trim(); if (!s) return null; const c = s.split(' · ')[0].trim().toLowerCase(); return items.find((i) => i.code.toLowerCase() === c) || items.find((i) => nm(i).toLowerCase() === s.toLowerCase()) || null; };
const optHTML = (rows, cur) => rows.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(cur) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const unitSel = (id, cur) => `<div><label for="${id}">${esc(T('unit'))}</label><select id="${id}"><option value="">${esc(T('baseUnit'))}</option>${optHTML(lists('units').map((r) => [r.value_code, lab(rowL(r))]), cur || '')}</select></div>`;
const locSel = (id, label, cur, rows) => (rows.length > 1 ? `<div><label for="${id}">${esc(label)}</label><select id="${id}">${optHTML(rows.map((l) => [l.id, nm(l)]), cur)}</select></div>` : `<input type="hidden" id="${id}" value="${rows[0] ? rows[0].id : ''}">`);
const scanOn = () => { try { return !!(B.barcode && B.barcode.enabled()); } catch (e) { return false; } };
const itemFld = (items, id, preset, label) => `<div><label for="${id}">${esc(label || T('item'))}</label><div class="p2-inl"><input id="${id}" list="${id}_dl" autocomplete="off" value="${esc(preset ? itemText(preset) : '')}" placeholder="${esc(T('itemph'))}">${scanOn() ? `<button type="button" class="mini" data-act="s2_scan" data-t="${id}" aria-label="${esc(T('scan'))}">▮▮ ${esc(T('scan'))}</button>` : ''}</div><datalist id="${id}_dl">${items.map((i) => `<option value="${esc(itemText(i))}"></option>`).join('')}</datalist><div class="hint" id="${id}_h">${preset ? esc(T('baseIs') + ': ' + unitLabel(baseOf(preset))) : ''}</div></div>`;
document.addEventListener('change', (e) => {
  const el = e.target; if (!el.id || !/^[a-z]+_item$/.test(el.id) || !ITEMS) return;
  const it = itemFrom(ITEMS, el.value), h = $('#' + el.id + '_h'); if (h) h.textContent = it ? T('baseIs') + ': ' + unitLabel(baseOf(it)) : '';
});
// one client id per open sheet: a double tap or a retry after a network error can never post twice; a NEW id only after success
const SH = { client: null, busy: false, photo: null, kind: null };
function sheetStart(kind) { SH.client = rid(); SH.busy = false; SH.photo = null; SH.kind = kind; }
async function submit(btn, call, onOk, ctx) {
  if (SH.busy) return; SH.busy = true; if (btn) btn.disabled = true;
  try {
    const r = await call();
    if (r.error) { if (ctx && ctx.onErr) ctx.onErr(r.error); errToast(r.error, ctx); return; }
    SH.client = rid(); closeSheet();
    if (r.data && r.data.dup) toast(T('dup')); else onOk(r.data || {});
  } catch (e) { fail(e); } finally { SH.busy = false; if (btn) btn.disabled = false; }
}
function readItem(items, id) { const it = itemFrom(items, ($('#' + id) || {}).value); if (!it) { toast(T('needItem')); return null; } return it; }
function readQty(id) { const q = nnum(($('#' + id) || {}).value); if (!(q > 0)) { toast(T('needQty')); return NaN; } return q; }
const optNum = (id) => { const v = ($('#' + id) || {}).value; if (!v || !String(v).trim()) return null; const n = nnum(v); return n; };

// scan a barcode into an item field (stock actions); the purchase editor has its own per-line button
async function scanInto(id) {
  const items = await trackedItems(), it = await B.barcode.scanItem(items); if (!it) return;
  const el = $('#' + id); if (!el) return; el.value = itemText(it); el.dispatchEvent(new Event('change', { bubbles: true }));
}
B.s2 = { X, T, ERR, scanInto, errToast, rid, shrink, uploadPhoto, thumb, grant, costOk, lists, rowL, unitLabel, unitSel, optHTML, locSel, LOCS, allLocs, npMode, trackedItems, itemFrom, itemFld, itemText, baseOf, nnum, norm, money, q4, dt, LOCK, SH, sheetStart, submit, photoForm };

// ---------- hub state ----------
const D = { loc: undefined, tab: 'levels', rows: [], cats: [], q: '', f: { category: '', below: false, zero: false }, shown: 50, expH: 24, exp: [], tr: [], wa: [], acts: null, sqlMissing: false, canApprove: false, nPending: 0 };
let CONV = [];
const ACTS = [['open', 'stock_opening', 'a_open'], ['waste', 'wastage_write_off', 'a_waste'], ['count', 'stock_count_adjust', 'a_count'], ['issue', 'stock_issue', 'a_issue'], ['prod', 'stock_production', 'a_prod'], ['xfer', 'stock_transfer', 'a_xfer']];
const actLoc = () => (D.loc !== undefined && D.loc !== null ? D.loc : (LOCS()[0] || {}).id);
const locName = (id) => nm(((B.ENV && B.ENV.locs) || []).find((l) => l.id === id) || { name_bn: '#' + id });
const missingFn = (e) => e && /could not find the function|does not exist|schema cache|404/i.test(e.message || '');

async function view() {
  shell(T('title'), `<p class="muted">${esc(T('loading'))}</p>`, true);
  try { await B.loadStatic(); } catch (e) { /* defaults */ }
  if (D.loc === undefined) D.loc = (LOCS()[0] || {}).id;       // one location first (zero-stock items show there); "all" is one tap away
  D.acts = null; GR.clear();
  await Promise.all([trackedItems(), refreshActs(), loadConv()]);
  await loadPendingCount();
  draw();
}
async function refreshActs() {
  const loc = actLoc(); const res = await Promise.all([...ACTS.map(([, g]) => grant(g, loc)), grant('wastage_approve', loc)]);
  D.acts = {}; ACTS.forEach(([k], i) => { D.acts[k] = res[i]; }); D.canApprove = !!res[ACTS.length];
}
async function loadConv() { try { const r = await sb.from('unit_conversions').select('*'); CONV = r.error ? [] : (r.data || []).filter((c) => c.active !== false); } catch (e) { CONV = []; } }
// waiting wastage approvals (phase12): the tab shows only for an approver or for someone who has a request waiting
async function loadPendingCount() {
  try { const r = await sb.rpc('wastage_pending', { p_loc: D.loc === undefined ? null : D.loc, p_status: 'pending' }); D.wa = r && !r.error && r.data ? r.data : []; } catch (e) { D.wa = []; }
  D.nPending = D.wa.length;
}
// category label from the editable list (the code is only a fallback); units of an item from the conversions
const catLabel = (code) => { if (!code) return ''; const r = lists('item_categories').find((x) => x.value_code === code); return r ? lab(rowL(r)) : code; };
function unitLine(itemId, base) {
  const it = (ITEMS || []).find((i) => i.id === itemId) || {}, b = base || baseOf(it), buy = [b];
  CONV.forEach((c) => { if (c.item_id && c.item_id !== itemId) return; const o = c.to_unit === b ? c.from_unit : c.from_unit === b ? c.to_unit : null; if (o && !buy.includes(o)) buy.push(o); });
  const sell = (it.sell_units || []).filter(Boolean);
  return T('buyU') + ': ' + buy.map(unitLabel).join(', ') + (sell.length ? ' · ' + T('sellU') + ': ' + sell.map(unitLabel).join(', ') : '');
}
// one search for the list: code, Bangla / English / Bng-Eng name, category label (Bangla digits accepted)
function rowsFor() {
  const q = norm(D.q).toLowerCase(); if (!q) return D.rows;
  return D.rows.filter((r) => { const it = (ITEMS || []).find((i) => i.id === r.item_id) || {}; return [r.code, r.name_bn, r.name_en, it.name_mix, catLabel(r.category), it.barcode].some((x) => String(x || '').toLowerCase().includes(q)); });
}
function draw() {
  const locs = LOCS(), filters = (D.f.category ? 1 : 0) + (D.f.below ? 1 : 0) + (D.f.zero ? 1 : 0);
  const anyAct = D.acts && Object.values(D.acts).some(Boolean), showActs = anyAct || npMode() === 'lock';
  shell(T('title'), `${locs.length > 1 || allLocs() ? `<div style="margin-bottom:8px"><select id="s2_loc" aria-label="${esc(T('location'))}">${allLocs() ? `<option value="">${esc(T('allLoc'))}</option>` : ''}${optHTML(locs.map((l) => [l.id, nm(l)]), D.loc)}</select></div>` : ''}
    <div class="ptabs s2t" role="tablist">${[['levels', 'levels'], ['exp', 'expiring'], ['tr', 'transit'], ...(D.canApprove || D.nPending ? [['wa', 'wa']] : [])].map(([k, l]) => `<button role="tab" data-act="s2_tab" data-v="${k}" aria-selected="${D.tab === k}">${esc(T(l))}${k === 'wa' && D.nPending ? ` <span class="cnt">${D.nPending}</span>` : ''}</button>`).join('')}</div>
    <div id="s2_main"></div>
    <div class="s2-bar">${showActs ? `<button class="primary" data-act="s2_actions">${esc(T('actions'))}</button>` : ''}${S.ctx.is_owner ? `<button class="sec" data-act="s2_recon">${esc(T('recon'))}</button>` : ''}</div>`, true);
  void filters; drawTab();
}
function drawTab() { if (D.tab === 'levels') loadLevels(); else if (D.tab === 'exp') loadExpiry(); else if (D.tab === 'wa') loadApprovals(); else loadTransit(); }

// ----- levels -----
async function loadLevels() {
  const box = $('#s2_main'); if (!box) return; box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`;
  const f = {}; if (D.f.category) f.category = D.f.category; if (D.f.below) f.below_min = true; if (D.f.zero) f.include_zero = true;
  const r = await sb.rpc('stock_levels', { p_loc: D.loc === undefined ? null : D.loc, p_filters: f });
  if (r.error) { if (missingFn(r.error)) { box.innerHTML = `<div class="notice bad">${esc(T('sqlMissing'))}</div>`; return; } return errToast(r.error); }
  D.rows = r.data || [];
  if (!D.f.category) D.cats = [...new Set(D.rows.map((x) => x.category).filter(Boolean))];
  D.shown = 50; paintLevels();
}
function paintLevels() {
  const box = $('#s2_main'); if (!box) return;
  const list = rowsFor();
  const below = D.rows.filter((r) => r.below_min).length;
  const costs = D.rows.filter((r) => r.value !== null && r.value !== undefined), total = costs.reduce((s, r) => s + Number(r.value), 0);
  const fc = (D.f.category ? 1 : 0) + (D.f.below ? 1 : 0) + (D.f.zero ? 1 : 0);
  box.innerHTML = `<div class="p2-bar"><input id="s2_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" value="${esc(D.q)}" aria-label="${esc(T('search'))}"><button id="s2_fb" class="p2-fb" data-act="s2_filter" aria-label="${esc(T('filter'))}">⎚ ${esc(T('filter'))}${fc ? `<span class="cnt">${fc}</span>` : ''}</button></div>
    <div class="s2-sum"><div class="stat ${below ? 'mk warn' : ''}"><div class="k">${esc(T('nBelow'))}</div><div class="v">${below}</div></div>
      ${costs.length ? `<div class="stat" id="s2_val"><div class="k">${esc(T('totalValue'))}</div><div class="v">${esc(money(total))}</div></div>` : `<div class="stat"><div class="k">${esc(T('nItems'))}</div><div class="v">${D.rows.length}</div></div>`}</div>
    <div id="s2_list"></div>`;
  paintRows(list);
}
function paintRows(list) {
  const box = $('#s2_list'); if (!box) return;
  const showLoc = D.loc === null || D.loc === undefined;
  const html = list.slice(0, D.shown).map((r) => {
    const i = D.rows.indexOf(r), out = Number(r.qty) <= 0, bar = out ? 'bad' : r.below_min ? 'warn' : '';
    return `<div class="card item s2-row mk ${bar}" data-act="s2_item" data-i="${i}" role="button" tabindex="0"><div><div class="nm">${esc(nm(r))}</div>
      <div class="sub">${esc(r.code)}${r.category ? ' · ' + esc(catLabel(r.category)) : ''}${showLoc ? ' · ' + esc(locName(r.location_id)) : ''}${r.min_stock !== null && r.min_stock !== undefined ? ' · ' + esc(T('min')) + ' ' + q4(r.min_stock) : ''}</div>
      <div class="sub">${esc(unitLine(r.item_id, r.base_unit))}</div>
      ${out ? `<span class="chip bad">${esc(T('chipOut'))}</span>` : r.below_min ? `<span class="chip warn">${esc(T('chipLow'))}</span>` : ''}</div>
      <div class="pr"><button type="button" class="mini s2-dots" data-act="s2_rowmenu" data-i="${i}" aria-label="${esc(T('more2'))}">⋮</button><b>${q4(r.qty)} ${esc(unitLabel(r.base_unit))}</b>${r.avg_cost !== null && r.avg_cost !== undefined ? `<small>${esc(T('avg'))} ${esc(money(r.avg_cost))}</small>` : ''}${r.value !== null && r.value !== undefined ? `<small>${esc(money(r.value))}</small>` : ''}</div></div>`;
  }).join('');
  box.innerHTML = (html || `<div class="card center"><p class="muted">${esc(T('none'))}</p><p class="muted" style="font-size:.85rem">${esc(T('noneHint'))}</p></div>`)
    + (list.length > D.shown ? `<button class="full" data-act="s2_more">${esc(T('more'))}</button>` : '');
}

// ----- expiring -----
async function loadExpiry() {
  const box = $('#s2_main'); if (!box) return; box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`;
  const r = await sb.rpc('expiry_list', { p_loc: D.loc === undefined ? null : D.loc, p_hours_ahead: D.expH });
  if (r.error) { if (missingFn(r.error)) { box.innerHTML = `<div class="notice bad">${esc(T('sqlMissing'))}</div>`; return; } return errToast(r.error); }
  D.exp = r.data || [];
  const canW = {}; for (const l of [...new Set(D.exp.map((x) => x.location_id))]) canW[l] = await grant('wastage_write_off', l);
  const hs = [24, 48, 72];
  box.innerHTML = `<div class="muted" style="font-size:.85rem">${esc(T('expH'))}</div><div class="seg" role="group" style="margin-top:4px">${hs.map((h) => `<button data-act="s2_exph" data-v="${h}" aria-pressed="${D.expH === h}">${h} h</button>`).join('')}</div>
    <div style="margin-top:10px">${D.exp.map((x) => {
      const it = (ITEMS || []).find((i) => i.id === x.item_id), hl = Number(x.hours_left), ex = x.expired === true || hl <= 0;
      return `<div class="card item s2-row mk ${ex ? 'bad' : 'warn'}"><div><div class="nm">${esc(nm(x))}</div><div class="sub">${esc(x.code)} · ${esc(dt(x.made_at))} → ${esc(dt(x.expires_at))}${D.loc === null || D.loc === undefined ? ' · ' + esc(locName(x.location_id)) : ''}</div>
        <span class="chip ${ex ? 'bad' : 'warn'}">${ex ? esc(T('expiredAgo')) + ' ' + q4(Math.abs(hl)) + ' ' + esc(T('hAgo')) : q4(hl) + ' ' + esc(T('hLeft'))}</span></div>
        <div class="pr"><b>${q4(x.qty_remaining)} ${esc(unitLabel(baseOf(it)))}</b>${canW[x.location_id] ? `<button class="mini" style="margin-top:6px;min-width:76px;border-radius:12px" data-act="s2_expwo" data-i="${D.exp.indexOf(x)}">${esc(T('writeOff'))}</button>` : ''}</div></div>`; }).join('')
      || `<div class="card"><b>${esc(T('expEmpty'))}</b><p class="muted" style="margin:6px 0 0"><span class="chip">${esc(T('expOff'))}</span><br>${esc(T('expOffHint'))}</p></div>`}</div>`;
}

// ----- in transit -----
async function loadTransit() {
  const box = $('#s2_main'); if (!box) return; box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`;
  const r = await sb.rpc('stock_in_transit', { p_loc: D.loc === undefined ? null : D.loc });
  if (r.error) { if (missingFn(r.error)) { box.innerHTML = `<div class="notice bad">${esc(T('sqlMissing'))}</div>`; return; } return errToast(r.error); }
  D.tr = r.data || [];
  const g = {}; for (const l of [...new Set(D.tr.flatMap((x) => [x.from_location_id, x.to_location_id]))]) g[l] = await grant('stock_transfer', l);
  const me = (S.ctx.profile || {}).staff_id;
  box.innerHTML = D.tr.map((x, i) => {
    const it = (ITEMS || []).find((y) => y.id === x.item_id), u = unitLabel(baseOf(it));
    const canR = g[x.to_location_id] && (allLocs() || (S.ctx.locations || []).includes(x.to_location_id)), canC = g[x.from_location_id] || x.sent_staff === me || S.ctx.is_owner;
    return `<div class="card stack mk info"><div class="row between"><b>${esc(nm(x))}</b><b>${q4(x.qty)} ${esc(u)}</b></div>
      <div class="sub muted" style="font-size:.85rem">${esc(x.code)} · ${esc(locName(x.from_location_id))} → ${esc(locName(x.to_location_id))} · ${esc(dt(x.sent_at))}${x.sent_staff ? ' · ' + esc(x.sent_staff) : ''}${x.note ? ' · ' + esc(x.note) : ''}</div>
      <div class="row">${canC ? `<button class="full" data-act="s2_xcancel" data-i="${i}">${esc(T('cancelX'))}</button>` : ''}${canR ? `<button class="full" data-act="s2_xrecv" data-i="${i}">${esc(T('receive'))}</button>` : ''}</div></div>`;
  }).join('') || `<p class="muted center">${esc(T('trEmpty'))}</p>`;
}

// ---------- filter sheet ----------
function filterSheet() {
  openSheet(`<h2>${esc(T('filter'))}</h2><div class="stack">
    <div><label for="sf_cat">${esc(T('category'))}</label><select id="sf_cat"><option value="">${esc(T('all'))}</option>${optHTML(D.cats.map((c) => [c, catLabel(c)]), D.f.category)}</select></div>
    ${LOCS().length > 1 || allLocs() ? `<div><label for="sf_loc">${esc(T('location'))}</label><select id="sf_loc">${allLocs() ? `<option value="">${esc(T('allLoc'))}</option>` : ''}${optHTML(LOCS().map((l) => [l.id, nm(l)]), D.loc)}</select></div>` : ''}
    <button class="tog ${D.f.below ? 'on' : ''}" id="sf_below" data-act="sheettog" style="width:100%;justify-content:flex-start">${esc(T('belowMin'))}</button>
    <button class="tog ${D.f.zero ? 'on' : ''}" id="sf_zero" data-act="sheettog" style="width:100%;justify-content:flex-start">${esc(T('showZero'))}</button>
    <div class="row"><button class="full" data-act="s2_freset">${esc(T('reset'))}</button><button class="primary full" data-act="s2_fapply">${esc(T('apply'))}</button></div></div>`);
}

// ---------- item drill ----------
async function drill(r) {
  const loc = r.location_id;
  openSheet(`<h2>${esc(nm(r))}</h2><p class="muted">${esc(T('loading'))}</p>`);
  const lr = await sb.rpc('stock_ledger_rows', { p_loc: loc, p_item: r.item_id, p_from: null, p_to: null, p_limit: 100 });
  if (lr.error) { closeSheet(); return errToast(lr.error); }
  const acts = []; for (const [k, g, l] of ACTS) { const ok = await grant(g, loc); if (ok) acts.push([k, l]); else if (npMode() === 'lock') acts.push([k, l, true]); }
  const rows = lr.data || [];
  openSheet(`<h2>${esc(nm(r))}</h2><div class="muted">${esc(r.code)} · ${esc(locName(loc))}</div>
    <div class="row between" style="margin:8px 0"><span>${esc(T('onHand'))}</span><b class="mnum">${q4(r.qty)} ${esc(unitLabel(r.base_unit))}</b></div>
    ${r.avg_cost !== null && r.avg_cost !== undefined ? `<div class="row between"><span class="muted">${esc(T('avg'))}</span><span>${esc(money(r.avg_cost))}</span></div>` : ''}
    ${r.value !== null && r.value !== undefined ? `<div class="row between"><span class="muted">${esc(T('totalValue'))}</span><span>${esc(money(r.value))}</span></div>` : ''}
    <div class="row wrap" style="margin:10px 0">${acts.map(([k, l, lk]) => `<button class="mini" style="border-radius:12px;padding:0 12px;width:auto" ${lk ? 'disabled' : `data-act="s2_do" data-v="${k}" data-i="${D.rows.indexOf(r)}"`}>${lk ? LOCK.replace('<svg', '<svg width="14" height="14"') + ' ' : ''}${esc(T(l))}</button>`).join('')}</div>
    <h3>${esc(T('ledger'))}</h3><div>${rows.map((e) => { const d = Number(e.qty_delta);
      return `<div class="s2-led"><div><div>${esc(RS[e.reason] ? lab(RS[e.reason]) : e.reason)}${e.reverses_id ? ' ↩' : ''}</div><div class="sub">${esc(dt(e.made_at))}${e.note ? ' · ' + esc(e.note) : ''}${e.unit_cost !== null && e.unit_cost !== undefined ? ' · ' + esc(money(e.unit_cost)) : ''}</div></div>
      <div class="q ${d < 0 ? 'neg' : ''}">${d > 0 ? '+' : '−'}${q4(Math.abs(d))}</div></div>`; }).join('') || `<p class="muted center">${esc(T('noMoves'))}</p>`}</div>
    <button class="full" style="margin-top:10px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ---------- actions sheet ----------
async function actionsSheet() {
  await refreshActs(); const mode = npMode();
  const rows = ACTS.map(([k, , l]) => D.acts[k] ? `<button class="s2-act" data-act="s2_do" data-v="${k}">${esc(T(l))}</button>` : mode === 'lock' ? `<div class="s2-lockrow">${LOCK}<span>${esc(T(l))} · ${esc(T('noperm'))}</span></div>` : '').join('');
  openSheet(`<h2>${esc(T('actions'))}</h2><div class="stack" id="s2_acts">${rows}</div><button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}
async function openAction(kind, preset) {
  const items = await trackedItems(), locs = LOCS(), loc = (preset && preset.loc) || actLoc(), pit = preset && preset.item_id ? items.find((i) => i.id === preset.item_id) : null;
  sheetStart(kind);
  const foot = (act) => `<div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" id="a_go" data-act="${act}">${esc(T('save'))}</button></div>`;
  const note = (req) => `<div><label for="a_note">${esc(T(req ? 'noteReq' : 'note'))}</label><input id="a_note" autocomplete="off"></div>`;
  const cost = (await costOk(loc)) ? `<div><label for="a_cost">${esc(T('cost'))}</label><input id="a_cost" inputmode="decimal"></div>` : '';
  const head = (l) => `<h2>${esc(T(l))}</h2>`;
  let body = '';
  if (kind === 'open') body = head('a_open') + `<div class="stack">${locSel('a_loc', T('location'), loc, locs)}${itemFld(items, 'a_item', pit)}<div class="row"><div style="flex:1"><label for="a_qty">${esc(T('counted'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>${cost}${note(false)}</div>${foot('s2_go_open')}`;
  else if (kind === 'waste') {
    const reasons = lists('wastage_reasons').length ? lists('wastage_reasons').map((r) => [r.value_code, lab(rowL(r))]) : [['expired', 'Expired'], ['spoiled', 'Spoiled'], ['burnt', 'Burnt'], ['broken', 'Broken'], ['sample', 'Sample / free'], ['staff_meal', 'Staff meal'], ['unknown', 'Unknown reason']];
    body = head('a_waste') + `<div class="stack">${locSel('a_loc', T('location'), loc, locs)}${itemFld(items, 'a_item', pit)}<div class="row"><div style="flex:1"><label for="a_qty">${esc(T('qty'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>
      <div><label for="a_reason">${esc(T('reason'))}</label><select id="a_reason"><option value="">—</option>${optHTML(reasons, '')}</select></div>${note(false)}${photoFld()}</div>${foot('s2_go_waste')}`;
  } else if (kind === 'count') body = head('a_count') + `<div class="stack">${locSel('a_loc', T('location'), loc, locs)}${itemFld(items, 'a_item', pit)}<div class="row"><div style="flex:1"><label for="a_qty">${esc(T('counted'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>${note(true)}</div>${foot('s2_go_count')}`;
  else if (kind === 'issue') body = head('a_issue') + `<div class="stack">${locSel('a_loc', T('location'), loc, locs)}${itemFld(items, 'a_item', pit)}<div class="row"><div style="flex:1"><label for="a_qty">${esc(T('qty'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>${note(false)}</div>${foot('s2_go_issue')}`;
  else if (kind === 'prod') {
    const now = new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Dhaka' }).replace(' ', 'T').slice(0, 16);
    body = head('a_prod') + (B.recipes ? B.recipes.prodButton() : '') + `<div class="stack">${locSel('a_loc', T('location'), loc, locs)}${itemFld(items, 'a_item', pit)}<div class="row"><div style="flex:1"><label for="a_qty">${esc(T('qty'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>
      <div><label for="a_made">${esc(T('madeAt'))}</label><input id="a_made" type="datetime-local" value="${now}"></div>${cost}${note(false)}</div>${foot('s2_go_prod')}`;
  } else if (kind === 'xfer') {
    const others = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []);
    body = head('a_xfer') + `<div class="stack">${locSel('a_loc', T('fromLoc'), loc, locs)}<div><label for="a_to">${esc(T('toLoc'))}</label><select id="a_to"><option value="">—</option>${optHTML(others.filter((l) => l.id !== loc).map((l) => [l.id, nm(l)]), '')}</select></div>${itemFld(items, 'a_item', pit)}
      <div class="row"><div style="flex:1"><label for="a_qty">${esc(T('qty'))}</label><input id="a_qty" inputmode="decimal"></div><div style="flex:1">${unitSel('a_unit')}</div></div>${note(false)}</div>${foot('s2_go_xfer')}`;
  }
  openSheet(body);
  if (kind === 'waste') { drawPhoto(); wireReason(); }
  if (B.listctl && $('#a_unit')) B.listctl.enhance('#a_unit', 'units', { otherBlank: true, form: 'STOCK', ctx: { field: 'stock_unit' } });
}
const photoFld = () => `<div><label>${esc(T('photo'))}</label><div class="s2-ph" id="a_ph"></div><div class="hint" id="a_ph_h"></div></div>`;
function drawPhoto() {
  const box = $('#a_ph'); if (!box) return;
  box.innerHTML = (SH.photo ? `<img alt="" width="84" height="84" id="a_ph_img">` : '') + `<label class="phadd">📷 ${esc(T('addPhoto'))}<input type="file" accept="image/*" hidden id="a_file"></label>`;
  if (SH.photo) thumb($('#a_ph_img'), SH.photo);
}
async function pickPhoto(file) {
  if (!file) return; toast(T('upl'));
  try { SH.photo = await uploadPhoto(file, ['STOCK', '04-1', '04-2', '04-4'], Number(($('#a_loc') || {}).value) || actLoc()); drawPhoto(); const h = $('#a_ph_h'); if (h) { h.textContent = ''; h.classList.remove('s2-need'); } } catch (e) { fail(e); }
}
document.addEventListener('change', (e) => { if (e.target.id === 'a_file') pickPhoto(e.target.files && e.target.files[0]); });

const gloc = () => Number(($('#a_loc') || {}).value) || actLoc();
const unitVal = () => (($('#a_unit') || {}).value || null);
const noteVal = () => ((($('#a_note') || {}).value) || '').trim() || null;
// shared list control on the wastage / return reason pickers: + Add new follows the list's rule; "Other" stores the reason 'unknown' and the typed words go into the note
// (and into the Other queue for the owner). If 'unknown' is not an active reason, "Other" is not offered here.
function wireReason(form) {
  const lc = B.listctl; if (!lc || !$('#a_reason')) return;
  const unk = lists('wastage_reasons').some((r) => r.value_code === 'unknown' && r.active);
  lc.enhance('#a_reason', 'wastage_reasons', unk ? { otherValue: 'unknown', form: form || 'WASTAGE', ctx: () => ({ field: 'wastage_reason', item_id: (($('#a_item') || {}).value || '').slice(0, 40) }) } : { noOther: true, form: form || 'WASTAGE' });
  if (!unk) { const sel = $('#a_reason'); if (sel && sel.parentNode && !sel.parentNode.querySelector('.s2-nootherhint')) sel.insertAdjacentHTML('afterend', '<div class="hint s2-nootherhint">' + esc(lab(L('"অন্যান্য" এখানে বন্ধ: "কারণ অজানা" চালু নেই', '"Other" is off here: the "unknown" reason is not active', '"Other" এখানে বন্ধ: "unknown" reason চালু নেই'))) + '</div>'); }
}
const reasonNote = (n) => n;       // the typed Other words are kept in the owner's Other queue (with the item), the note is sent as typed
async function goOpen(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = readQty('a_qty'); if (isNaN(q)) return;
  const c = optNum('a_cost'); if (c !== null && (isNaN(c) || c < 0)) return toast(T('badCost'));
  const loc = gloc();
  await submit(btn, () => sb.rpc('stock_opening', { p_item: it.id, p_loc: loc, p_qty: q, p_unit_cost: c, p_unit: unitVal(), p_note: noteVal(), p_client: SH.client }), () => { toast(T('saved')); afterWrite(); }, { grant: 'stock_opening', loc, context: { item: it.code } });
}
async function goWaste(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = readQty('a_qty'); if (isNaN(q)) return;
  const reason = ($('#a_reason') || {}).value; if (!reason) return toast(T('needReason'));
  const lim = B.rule('wastage_photo_above', null), loc = gloc();
  if (lim !== null && lim !== undefined && !unitVal() && q > Number(lim) && !SH.photo) { const h = $('#a_ph_h'); if (h) { h.textContent = T('photoReq'); h.classList.add('s2-need'); } return toast(T('photoReq')); }
  await submit(btn, () => sb.rpc('stock_wastage', { p_item: it.id, p_loc: loc, p_qty: q, p_reason: reason, p_note: reasonNote(noteVal()), p_photo: SH.photo, p_unit: unitVal(), p_client: SH.client, p_batch: null }),
    (d) => { toast(d && d.pending ? T('sentApproval') : T('saved')); if (d && d.pending) loadPendingCount().then(() => { if ($('#s2_main')) draw(); }); else afterWrite(); }, { grant: 'wastage_write_off', loc, context: { item: it.code }, onErr: (e) => { if (/photo_required/.test(e.message || '')) { const h = $('#a_ph_h'); if (h) { h.textContent = T('photoReq'); h.classList.add('s2-need'); } } } });
}
async function goCount(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = nnum(($('#a_qty') || {}).value); if (!(q >= 0)) return toast(T('needQty'));
  const note = noteVal(); if (!note) return toast(T('needNote')); const loc = gloc();
  await submit(btn, () => sb.rpc('stock_count_adjust', { p_item: it.id, p_loc: loc, p_counted: q, p_note: note, p_unit: unitVal(), p_client: SH.client }),
    (d) => { toast(T('countDone') + ' · ' + T('delta') + ' ' + (Number(d.delta) > 0 ? '+' : '') + q4(d.delta)); afterWrite(); }, { grant: 'stock_count_adjust', loc, context: { item: it.code } });
}
async function goIssue(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = readQty('a_qty'); if (isNaN(q)) return; const loc = gloc();
  await submit(btn, () => sb.rpc('stock_issue', { p_item: it.id, p_loc: loc, p_qty: q, p_unit: unitVal(), p_note: noteVal(), p_client: SH.client }), () => { toast(T('saved')); afterWrite(); }, { grant: 'stock_issue', loc, context: { item: it.code } });
}
async function goProd(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = readQty('a_qty'); if (isNaN(q)) return;
  const c = optNum('a_cost'); if (c !== null && (isNaN(c) || c < 0)) return toast(T('badCost'));
  const m = ($('#a_made') || {}).value, loc = gloc(); const madeAt = m ? m + ':00+06:00' : null;
  await submit(btn, () => sb.rpc('stock_production_in', { p_item: it.id, p_loc: loc, p_qty: q, p_made_at: madeAt, p_unit: unitVal(), p_note: noteVal(), p_client: SH.client, p_unit_cost: c }), () => { toast(T('saved')); afterWrite(); }, { grant: 'stock_production', loc, context: { item: it.code } });
}
async function goXfer(btn) {
  const items = await trackedItems(), it = readItem(items, 'a_item'); if (!it) return; const q = readQty('a_qty'); if (isNaN(q)) return;
  const to = Number(($('#a_to') || {}).value); if (!to) return toast(T('needTo')); const from = gloc();
  await submit(btn, () => sb.rpc('stock_transfer', { p_from: from, p_to: to, p_item: it.id, p_qty: q, p_unit: unitVal(), p_note: noteVal(), p_client: SH.client }), () => { toast(T('sentOk')); afterWrite(); }, { grant: 'stock_transfer', loc: from, context: { item: it.code } });
}
function afterWrite() { if ($('#s2_main')) drawTab(); }

// ----- wastage approvals (maker-checker, phase12) -----
async function loadApprovals() {
  const box = $('#s2_main'); if (!box) return; box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`;
  const r = await sb.rpc('wastage_pending', { p_loc: D.loc === undefined ? null : D.loc, p_status: 'pending' });
  if (r.error) { if (missingFn(r.error)) { box.innerHTML = `<div class="notice bad">${esc(T('sqlMissing'))}</div>`; return; } return errToast(r.error); }
  D.wa = r.data || []; D.nPending = D.wa.length;
  box.innerHTML = `<h3 style="margin:4px 0 8px">${esc(T('waTitle'))}</h3>` + (D.wa.map((x, i) => `<div class="card item s2-row mk warn"><div><div class="nm">${esc(nm(x))}</div>
      <div class="sub">${esc(x.code)} · ${esc(locName(x.location_id))} · ${esc(T('waBy'))} ${esc(x.requested_staff || '?')} · ${esc(dt(x.requested_at))}</div>
      <div class="sub">${esc(wasteReason(x.reason_code))}${x.note ? ' · ' + esc(x.note) : ''}</div>${x.mine ? `<span class="chip info">${esc(T('waMine'))}</span>` : !x.can_decide ? '' : ''}</div>
      <div class="pr"><button type="button" class="mini s2-dots" data-act="s2_wamenu" data-i="${i}" aria-label="${esc(T('more2'))}">⋮</button><b>${q4(x.qty)} ${esc(unitLabel(x.base_unit))}</b></div></div>`).join('')
    || `<div class="card center"><p class="muted">${esc(T('waEmpty'))}</p></div>`);
}
const wasteReason = (code) => { const r = lists('wastage_reasons').find((x) => x.value_code === code); return r ? lab(rowL(r)) : code; };
function waMenu(x) {
  sheetStart('wamenu');
  openSheet(`<h2>${esc(nm(x))}</h2><div class="muted">${q4(x.qty)} ${esc(unitLabel(x.base_unit))} · ${esc(wasteReason(x.reason_code))}</div>${x.photo ? `<div class="s2-ph" style="margin:8px 0"><img alt="" width="84" height="84" id="wa_img"></div>` : ''}
    <div class="stack" style="margin-top:10px">${x.can_decide ? `<button class="primary s2-act" data-act="s2_wa_yes" data-i="${D.wa.indexOf(x)}">${esc(T('approve'))}</button><button class="s2-act" data-act="s2_wa_no" data-i="${D.wa.indexOf(x)}">${esc(T('reject'))}</button>`
      : x.mine ? `<div class="notice warn">${esc(T('waWho'))}</div>` : ''}
      ${x.mine ? `<button class="s2-act" data-act="s2_wa_cancel" data-i="${D.wa.indexOf(x)}">${esc(T('takeBack'))}</button>` : ''}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
  if (x.photo) thumb($('#wa_img'), x.photo);
}
async function rowMenu(r) {
  const acts = []; for (const [k, g, l] of ACTS) { const ok = await grant(g, r.location_id); if (ok) acts.push([k, l]); }
  openSheet(`<h2>${esc(nm(r))}</h2><div class="muted">${esc(r.code)} · ${esc(locName(r.location_id))}</div><div class="stack" style="margin-top:10px">
    <button class="s2-act" data-act="s2_item" data-i="${D.rows.indexOf(r)}">${esc(T('ledgerOpen'))}</button>
    ${acts.map(([k, l]) => `<button class="s2-act" data-act="s2_do" data-v="${k}" data-i="${D.rows.indexOf(r)}">${esc(T(l))}</button>`).join('')}</div>
    <button class="full" style="margin-top:12px" data-act="closesheet">${esc(T('close'))}</button>`);
}

// ---------- expire a batch / receive / cancel / reconcile ----------
function expireSheet(x) {
  sheetStart('expwo');
  const reasons = lists('wastage_reasons').length ? lists('wastage_reasons').map((r) => [r.value_code, lab(rowL(r))]) : [['expired', 'Expired']];
  openSheet(`<h2>${esc(T('writeOff'))} · ${esc(nm(x))}</h2><p class="muted">${esc(T('batchQty'))}: ${q4(x.qty_remaining)}</p><input type="hidden" id="a_loc" value="${x.location_id}"><div class="stack">
    <div><label for="a_reason">${esc(T('reason'))}</label><select id="a_reason">${optHTML(reasons, 'expired')}</select></div>${`<div><label for="a_note">${esc(T('note'))}</label><input id="a_note" autocomplete="off"></div>`}${photoFld()}</div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="s2_go_expwo" data-i="${D.exp.indexOf(x)}">${esc(T('writeOff'))}</button></div>`);
  drawPhoto();
  wireReason('EXPIRY');
}
function recvSheet(x) {
  sheetStart('recv'); const it = (ITEMS || []).find((y) => y.id === x.item_id), u = unitLabel(baseOf(it));
  openSheet(`<h2>${esc(T('receive'))} · ${esc(nm(x))}</h2><p class="muted">${esc(T('sent'))}: ${q4(x.qty)} ${esc(u)} · ${esc(locName(x.from_location_id))} → ${esc(locName(x.to_location_id))}</p><div class="stack">
    <div><label for="r_qty">${esc(T('recvQty'))}</label><input id="r_qty" inputmode="decimal" value="${esc(String(x.qty))}" data-sent="${esc(String(x.qty))}"></div><div class="notice warn" id="r_short" hidden>${esc(T('shortBy'))}</div>
    <div><label for="a_note">${esc(T('note'))}</label><input id="a_note" autocomplete="off"></div></div>
    <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="s2_go_recv" data-i="${D.tr.indexOf(x)}">${esc(T('receive'))}</button></div>`);
}
document.addEventListener('input', (e) => {
  if (e.target.id === 's2_q') { D.q = e.target.value; D.shown = 50; paintRows(rowsFor()); }
  if (e.target.id === 'r_qty') { const v = nnum(e.target.value), s = Number(e.target.dataset.sent); const w = $('#r_short'); if (w) w.hidden = !(v >= 0 && v < s); }
});
document.addEventListener('change', (e) => { if (e.target.id === 's2_loc') { D.loc = e.target.value === '' ? null : Number(e.target.value); refreshActs().then(draw); } });

async function reconSheet() {
  const r = await sb.rpc('stock_reconcile', { p_fix: false }); if (r.error) return errToast(r.error);
  const rows = r.data || [], items = await trackedItems();
  openSheet(`<h2>${esc(T('recon'))}</h2>${rows.length ? `<div class="notice bad">${esc(T('reconBad'))}: ${rows.length}</div>${rows.map((x) => { const it = items.find((i) => i.id === x.item_id);
    return `<div class="s2-led"><div>${esc(it ? nm(it) : x.item_id)}<div class="sub">${esc(locName(x.location_id))}</div></div><div class="q">${esc(T('ledgerQty'))} ${q4(x.ledger_qty)} / ${esc(T('cachedQty'))} ${q4(x.cached_qty)}</div></div>`; }).join('')}
    <button class="danger full" style="margin-top:10px" data-act="s2_fix">${esc(T('reconFix'))}</button>` : `<div class="notice ok">${esc(T('reconOk'))}</div>`}
    <button class="full" style="margin-top:10px" data-act="closesheet">${esc(T('close'))}</button>`);
}

Object.assign(H, {
  s2_tab: (a) => { D.tab = a.dataset.v; document.querySelectorAll('.ptabs button').forEach((b) => b.setAttribute('aria-selected', b.dataset.v === D.tab)); drawTab(); },
  s2_more: () => { D.shown += 50; paintRows(rowsFor()); },
  s2_filter: filterSheet,
  s2_freset: () => { D.f = { category: '', below: false, zero: false }; closeSheet(); loadLevels(); },
  s2_fapply: () => { D.f.category = ($('#sf_cat') || {}).value || ''; D.f.below = $('#sf_below').classList.contains('on'); D.f.zero = $('#sf_zero').classList.contains('on');
    const l = $('#sf_loc'); closeSheet(); if (l) { D.loc = l.value === '' ? null : Number(l.value); const s = $('#s2_loc'); if (s) s.value = l.value; refreshActs(); } loadLevels(); },
  s2_item: (a) => { const r = D.rows[Number(a.dataset.i)]; if (r) drill(r); },
  s2_actions: actionsSheet,
  s2_do: (a) => { const r = a.dataset.i !== undefined ? D.rows[Number(a.dataset.i)] : null; openAction(a.dataset.v, r ? { item_id: r.item_id, loc: r.location_id } : null); },
  s2_go_open: goOpen, s2_go_waste: goWaste, s2_go_count: goCount, s2_go_issue: goIssue, s2_go_prod: goProd, s2_go_xfer: goXfer,
  s2_exph: (a) => { D.expH = Number(a.dataset.v); loadExpiry(); },
  s2_expwo: (a) => { const x = D.exp[Number(a.dataset.i)]; if (x) expireSheet(x); },
  s2_go_expwo: async (a) => { const x = D.exp[Number(a.dataset.i)]; if (!x) return;
    await submit(a, () => sb.rpc('stock_expire_batch', { p_batch: x.batch_id, p_reason: ($('#a_reason') || {}).value || 'expired', p_note: reasonNote(noteVal()), p_photo: SH.photo }), () => { toast(T('saved')); afterWrite(); }, { grant: 'wastage_write_off', loc: x.location_id, context: { batch: x.batch_id } }); },
  s2_xrecv: (a) => { const x = D.tr[Number(a.dataset.i)]; if (x) recvSheet(x); },
  s2_go_recv: async (a) => { const x = D.tr[Number(a.dataset.i)]; if (!x) return; const v = nnum(($('#r_qty') || {}).value); if (!(v >= 0)) return toast(T('needQty'));
    await submit(a, () => sb.rpc('stock_receive_transfer', { p_id: x.id, p_received_qty: v, p_note: noteVal() }), () => { toast(T('saved')); afterWrite(); }, { grant: 'stock_transfer', loc: x.to_location_id, context: { transfer: x.id } }); },
  s2_xcancel: (a) => { const x = D.tr[Number(a.dataset.i)]; if (!x) return; sheetStart('xcancel');
    openSheet(`<h2>${esc(T('cancelX'))} · ${esc(nm(x))}</h2><div class="notice warn">${esc(T('confirmCancel'))}</div><div><label for="a_note">${esc(T('note'))}</label><input id="a_note" autocomplete="off"></div>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="s2_go_xcancel" data-i="${a.dataset.i}">${esc(T('cancelX'))}</button></div>`); },
  s2_go_xcancel: async (a) => { const x = D.tr[Number(a.dataset.i)]; if (!x) return;
    await submit(a, () => sb.rpc('stock_cancel_transfer', { p_id: x.id, p_note: noteVal() }), () => { toast(T('saved')); afterWrite(); }, { grant: 'stock_transfer', loc: x.from_location_id, context: { transfer: x.id } }); },
  s2_scan: (a) => scanInto(a.dataset.t),
  s2_rowmenu: (a) => { const r = D.rows[Number(a.dataset.i)]; if (r) rowMenu(r); },
  s2_wamenu: (a) => { const x = D.wa[Number(a.dataset.i)]; if (x) waMenu(x); },
  s2_wa_yes: async (a) => { const x = D.wa[Number(a.dataset.i)]; if (!x) return;
    await submit(a, () => sb.rpc('wastage_decide', { p_id: x.id, p_approve: true, p_note: null }), () => { toast(T('waDone')); loadPendingCount().then(() => { if ($('#s2_main')) draw(); }); }, { grant: 'wastage_approve', loc: x.location_id, context: { request: x.id } }); },
  s2_wa_no: (a) => { const x = D.wa[Number(a.dataset.i)]; if (!x) return; sheetStart('wano');
    openSheet(`<h2>${esc(T('reject'))} · ${esc(nm(x))}</h2><div><label for="a_note">${esc(T('waNote'))}</label><input id="a_note" autocomplete="off"></div>
      <div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">${esc(T('close'))}</button><button class="danger full" data-act="s2_wa_go_no" data-i="${a.dataset.i}">${esc(T('reject'))}</button></div>`); },
  s2_wa_go_no: async (a) => { const x = D.wa[Number(a.dataset.i)]; if (!x) return; const n = noteVal(); if (!n) return toast(T('needNote'));
    await submit(a, () => sb.rpc('wastage_decide', { p_id: x.id, p_approve: false, p_note: n }), () => { toast(T('waDone')); loadPendingCount().then(() => { if ($('#s2_main')) draw(); }); }, { grant: 'wastage_approve', loc: x.location_id, context: { request: x.id } }); },
  s2_wa_cancel: async (a) => { const x = D.wa[Number(a.dataset.i)]; if (!x) return;
    await submit(a, () => sb.rpc('wastage_cancel', { p_id: x.id }), () => { toast(T('waDone')); loadPendingCount().then(() => { if ($('#s2_main')) draw(); }); }, { context: { request: x.id } }); },
  s2_recon: reconSheet,
  s2_fix: async () => { const r = await sb.rpc('stock_reconcile', { p_fix: true }); if (r.error) return errToast(r.error); closeSheet(); toast(T('saved')); afterWrite(); },
});

// exception flag codes -> readable titles (3 modes). Shown by the exceptions page next to the server text.
const FLAGS = {
  stock_negative: L('স্টক ঋণাত্মক', 'Negative stock', 'Stock ঋণাত্মক'), stock_unit_unknown: L('এককের রূপান্তর অজানা', 'Unit conversion unknown', 'Unit conversion অজানা'),
  wastage_unknown: L('নষ্ট মাল, কারণ অজানা', 'Wastage, reason unknown', 'Wastage, reason অজানা'), stock_count_variance: L('গণনায় পার্থক্য', 'Count variance', 'Count variance'),
  sold_expired: L('মেয়াদোত্তীর্ণ মাল বিক্রি', 'Expired stock was sold', 'মেয়াদোত্তীর্ণ মাল বিক্রি'), emergency_used: L('জরুরি অনুমোদনে কাজ', 'Emergency approval used', 'Emergency approval ব্যবহার'),
  purchase_return_unreferenced: L('বিল ছাড়া ক্রয় ফেরত', 'Purchase return without a bill', 'Bill ছাড়া purchase return'),
  transit_short: L('পথে মাল কম', 'Short in transit', 'Transit-এ মাল কম'), purchase_price_jump: L('ক্রয়মূল্যে বড় বদল', 'Purchase price jump', 'Purchase price jump'),
  purchase_void: L('ক্রয় বিল বাতিল', 'Purchase voided', 'Purchase void'), supplier_payment_void: L('সাপ্লায়ার পেমেন্ট বাতিল', 'Supplier payment voided', 'Supplier payment void'),
  emergency_window_used: L('জরুরি অনুমোদনে কাজ', 'Emergency window used', 'Emergency window ব্যবহার'),
  wastage_pending: L('বড় নষ্ট মাল — অনুমোদনের অপেক্ষায়', 'Large wastage — waiting for approval', 'বড় wastage — approval-এর অপেক্ষায়'), wastage_rejected: L('বড় নষ্ট মাল নামঞ্জুর', 'Large wastage rejected', 'বড় wastage reject'),
  sale_return: L('বিক্রি ফেরত', 'Sale return', 'Sale return'), sale_return_void: L('বিক্রি ফেরত বাতিল', 'Sale return voided', 'Sale return void'), supplier_refund_void: L('সাপ্লায়ার রিফান্ড বাতিল', 'Supplier refund voided', 'Supplier refund void'),
};
B.flagChip = (code) => (FLAGS[code] ? `<span class="chip" style="margin-inline-end:6px">${esc(lab(FLAGS[code]))}</span>` : '');
B.FLAGS_STOCK = FLAGS;

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { stock: view });
})();
