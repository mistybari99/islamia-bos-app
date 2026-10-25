/* Islamia BOS · Scan (#/scan): take a PHOTO of a purchase bill / product list / expense slip / report -> a DRAFT -> the person checks and edits every field
   beside the photo -> Confirm sends it through the EXISTING save functions (save_purchase, quick_expense_add, item_new, item_apply), once.
   A photo never posts anything by itself and there is no auto-confirm. The reader is chosen by the rule scan_engine:
     manual      the person types the lines beside the photo (always works, nothing to set up)
     browser_ocr free OCR on the phone (tesseract.js, pinned version, loaded from a CDN on first use). WEAK on Bangla and on handwriting: the screen says so.
     ai_vision   the edge function scan-extract (source in supabase/functions/scan-extract, needs the owner's setup, docs/SCAN_SETUP.md)
   Server: supabase/phase90.sql (scan_create, scan_set_extracted, scan_review_save, scan_confirm, scan_reject, scan_get, scan_list, scan_match_items, scan_match_suppliers).
   Photos: private bucket 'photos', path SCAN/<place>/<client id>.jpg, shown only through a short-lived signed URL, never a public link.
   Offline: the photo is kept on the phone (IndexedDB) with its client id and is sent later; the same client id can never make two drafts. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'c' + Date.now().toString(16) + Math.random().toString(16).slice(2, 10));
const KINDS = ['purchase_bill', 'product_list', 'expense', 'other'];
const CDN_OCR = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js';   // pinned; no key; free
const HEADS = ['staff_meal', 'transport', 'hospitality', 'repair', 'labour', 'sourcing', 'other'];

const X = {
  title: L('ছবি থেকে এন্ট্রি (স্ক্যান)', 'Scan a bill or list', 'ছবি থেকে Entry (Scan)'),
  intro: L('বিল বা তালিকার ছবি তুলুন। আপনি দেখে ঠিক করে কনফার্ম না করা পর্যন্ত কিছুই ঢোকে না।', 'Take a photo of a bill or list. Nothing is entered until you check it and press Confirm.', 'Bill বা list-এর ছবি তুলুন। আপনি দেখে ঠিক করে Confirm না করা পর্যন্ত কিছুই ঢোকে না।'),
  off: L('স্ক্যান এখন বন্ধ। মালিক Switchboard থেকে স্ক্যান সুইচ চালু করলে ব্যবহার করা যাবে।', 'Scan is switched off. The owner can turn on the Scan switch in the Switchboard.', 'Scan এখন বন্ধ। Owner Switchboard থেকে Scan switch চালু করলে ব্যবহার করা যাবে।'),
  newScan: L('নতুন ছবি', 'New photo', 'নতুন photo'), kind: L('কীসের ছবি', 'What is it', 'কীসের photo'), place: L('জায়গা', 'Place', 'Place'),
  k_purchase_bill: L('ক্রয় বিল', 'Purchase bill', 'Purchase bill'), k_product_list: L('পণ্যের তালিকা', 'Product list', 'Product list'), k_expense: L('খরচের রসিদ', 'Expense slip', 'Expense slip'), k_other: L('অন্য কাগজ / রিপোর্ট', 'Other paper / report', 'অন্য paper / report'),
  take: L('ক্যামেরায় ছবি তুলুন', 'Take a photo', 'Camera-য় photo তুলুন'), gallery: L('গ্যালারি থেকে নিন', 'Choose from gallery', 'Gallery থেকে নিন'),
  eng_manual: L('পড়ার পদ্ধতি: নিজে লিখবেন (ছবির পাশে)', 'Reading: you type it beside the photo', 'পড়ার method: নিজে লিখবেন (photo-র পাশে)'),
  eng_browser_ocr: L('পড়ার পদ্ধতি: ফোনে বিনামূল্যে OCR। বাংলা ও হাতের লেখায় দুর্বল, তাই প্রতিটি ঘর মিলিয়ে নিন।', 'Reading: free OCR on the phone. Weak on Bangla and handwriting, so check every field.', 'পড়ার method: phone-এ free OCR। বাংলা ও handwriting-এ দুর্বল, তাই প্রতিটি field মিলিয়ে নিন।'),
  eng_ai_vision: L('পড়ার পদ্ধতি: AI। ভুল করতে পারে, তাই প্রতিটি ঘর মিলিয়ে নিন।', 'Reading: AI. It can be wrong, so check every field.', 'পড়ার method: AI। ভুল করতে পারে, তাই প্রতিটি field মিলিয়ে নিন।'),
  ocrBn: L('বাংলাও পড়ুন (বড় ডাউনলোড)', 'Also read Bangla (bigger download)', 'বাংলাও পড়ুন (বড় download)'),
  working: L('ছবি তৈরি হচ্ছে…', 'Preparing the photo…', 'Photo তৈরি হচ্ছে…'), reading: L('পড়া হচ্ছে… (প্রথমবার একটু সময় লাগে)', 'Reading… (the first time takes a while)', 'পড়া হচ্ছে… (প্রথমবার একটু সময় লাগে)'),
  readFail: L('ছবি থেকে পড়া গেল না। নিজে লিখে নিন।', 'Could not read the photo. Please type it yourself.', 'Photo থেকে পড়া গেল না। নিজে লিখে নিন।'),
  queued: L('ইন্টারনেট নেই: ছবি ফোনে রাখা হয়েছে, পরে পাঠানো হবে', 'No internet: the photo is kept on the phone and will be sent later', 'Internet নেই: photo phone-এ রাখা হয়েছে, পরে পাঠানো হবে'),
  qwait: L('পাঠানো অপেক্ষায় ছবি', 'Photos waiting to be sent', 'পাঠানো অপেক্ষায় photo'), qsend: L('এখন পাঠান', 'Send now', 'এখন পাঠান'), qdrop: L('বাদ দিন', 'Discard', 'Discard'),
  qsent: L('পাঠানো হয়েছে', 'Sent', 'Sent'),
  list: L('আপনার ছবিগুলো', 'Your photos', 'আপনার photo'), all: L('সব', 'All', 'All'), none: L('কোনো ছবি নেই', 'No photos yet', 'কোনো photo নেই'),
  s_uploaded: L('নতুন', 'New', 'New'), s_extracted: L('পড়া হয়েছে', 'Read', 'Read'), s_reviewed: L('দেখা হয়েছে', 'Checked', 'Checked'), s_confirmed: L('ঢোকানো হয়েছে', 'Entered', 'Entered'), s_rejected: L('বাতিল', 'Rejected', 'Rejected'),
  open: L('খুলুন', 'Open', 'Open'), dupn: L('একই বিলের সন্দেহ', 'Possible duplicate', 'Possible duplicate'),
  photo: L('ছবি', 'Photo', 'Photo'), zoom: L('ছবি বড় করে দেখুন', 'View the photo larger', 'Photo বড় করে দেখুন'), nophoto: L('ছবি দেখানো গেল না', 'The photo could not be shown', 'Photo দেখানো গেল না'),
  hidden: L('এই ক্রয় বিলের কস্ট দেখার অনুমতি আপনার নেই।', 'You do not have the right to see the costs of this purchase bill.', 'এই purchase bill-এর cost দেখার right আপনার নেই।'),
  supplier: L('সাপ্লায়ার', 'Supplier', 'Supplier'), billNo: L('বিল নম্বর', 'Bill no.', 'Bill no.'), date: L('ডেট', 'Date', 'Date'), discount: L('ছাড় ৳', 'Discount Tk', 'Discount Tk'),
  paper: L('কাগজের টোটাল ৳', 'Total on paper Tk', 'Paper-এর total ৳'), note: L('নোট', 'Note', 'Note'), titleF: L('শিরোনাম', 'Title', 'Title'),
  head: L('খাত (ইংরেজি কোড)', 'Head (code)', 'Head (code)'), paidTo: L('কাকে / কী বাবদ', 'Paid to / for', 'Paid to / for'), amount: L('টাকা ৳', 'Amount Tk', 'Amount Tk'), mode: L('মাধ্যম', 'Mode', 'Mode'), receipt: L('রসিদ আছে', 'Receipt kept', 'Receipt আছে'),
  lines: L('লাইন', 'Lines', 'Lines'), line: L('লাইন', 'Line', 'Line'), add: L('লাইন যোগ', 'Add a line', 'Line যোগ'), del: L('লাইন মুছুন', 'Remove line', 'Line মুছুন'),
  desc: L('বিবরণ', 'Description', 'Description'), qty: L('Qty', 'Qty', 'Qty'), unit: L('একক', 'Unit', 'Unit'), ucost: L('একক কস্ট ৳', 'Unit cost Tk', 'Unit cost Tk'), price: L('বিক্রয় প্রাইস ৳', 'Sell price Tk', 'Sell price Tk'), lamt: L('লাইনের টাকা', 'Line amount', 'Line amount'),
  decide: L('এই লাইন কী হবে', 'What is this line', 'এই line কী হবে'), choose: L('— বাছুন —', '— choose —', '— বাছুন —'),
  d_map: L('এখনকার আইটেমের সাথে মেলান', 'Match an existing item', 'Existing item-এর সাথে মেলান'), d_create: L('নতুন আইটেম বানান', 'Create a new item', 'নতুন item বানান'),
  d_text: L('শুধু লেখা (স্টক নয়)', 'Plain text (not stock)', 'শুধু text (stock নয়)'), d_skip: L('বাদ দিন', 'Skip this line', 'Skip করুন'),
  sugg: L('মিলতে পারে (ট্যাপ করে বাছুন)', 'Possible matches (tap to choose)', 'মিলতে পারে (tap করে বাছুন)'), nosugg: L('মেলে এমন কিছু নেই', 'No similar existing name', 'মেলে এমন কিছু নেই'),
  chosen: L('বাছা হয়েছে', 'Chosen', 'Chosen'), find: L('খুঁজুন', 'Find', 'Find'), findph: L('নাম লিখে খুঁজুন', 'Type a name to search', 'নাম লিখে খুঁজুন'),
  nameEn: L('নতুন আইটেমের ইংরেজি নাম', 'New item name (English)', 'নতুন item-এর English নাম'), nameBn: L('বাংলা নাম', 'Bangla name', 'বাংলা নাম'), cat: L('ক্যাটাগরি', 'Category', 'Category'),
  newSup: L('নতুন সাপ্লায়ার হিসেবে খুলুন', 'Create as a new supplier', 'নতুন supplier হিসেবে খুলুন'), supNew: L('নতুন সাপ্লায়ার হবে', 'Will be created as a new supplier', 'নতুন supplier হবে'), supUndo: L('বাতিল', 'Undo', 'Undo'),
  supHelp: L('সাপ্লায়ার বাছুন বা নতুন বলে চিহ্নিত করুন', 'Choose a supplier or mark it as new', 'Supplier বাছুন বা নতুন বলে mark করুন'),
  low: L('পাঠক নিশ্চিত ছিল না', 'The reader was not sure', 'Reader sure ছিল না'), lowKey: L('হলুদ ঘর = পাঠক নিশ্চিত ছিল না, আপনি বদলাননি', 'Yellow = the reader was not sure and you have not changed it', 'হলুদ field = reader sure ছিল না, আপনি বদলাননি'),
  save: L('ড্রাফট সেভ', 'Save draft', 'Draft save'), done: L('দেখা শেষ — কনফার্ম', 'Checked — Confirm', 'দেখা শেষ — Confirm'), doneNoRight: L('দেখা শেষ — কনফার্মের জন্য পাঠান', 'Checked — send for confirmation', 'দেখা শেষ — Confirm-এর জন্য পাঠান'),
  confirm: L('কনফার্ম করুন', 'Confirm', 'Confirm করুন'), reject: L('বাতিল করুন', 'Reject', 'Reject'), edit: L('আবার বদলান', 'Edit again', 'আবার edit'),
  cq: L('এটি এখনই ঢোকানো হবে', 'This will now be entered', 'এটি এখনই enter হবে'), ackDup: L('আমি দেখেছি, তবুও ঢোকান', 'I have seen it, enter it anyway', 'আমি দেখেছি, তবুও enter করুন'),
  post: L('বিলটি পোস্টও করুন (স্টকে যাবে)', 'Also post the bill (adds the stock)', 'Bill-টি post-ও করুন (stock-এ যাবে)'), postNo: L('না করলে এটি ড্রাফট ক্রয় বিল হয়ে থাকবে', 'If not ticked it stays a draft purchase bill', 'না করলে এটি draft purchase bill হয়ে থাকবে'),
  rwhy: L('বাতিলের কারণ (কমপক্ষে ৩ অক্ষর)', 'Reason for rejecting (at least 3 letters)', 'Reject-এর reason (কমপক্ষে ৩ অক্ষর)'), cancel: L('থাক', 'Cancel', 'Cancel'),
  saved: L('সেভ হয়েছে', 'Saved', 'Saved'), sent: L('কনফার্মের জন্য পাঠানো হয়েছে', 'Sent for confirmation', 'Confirm-এর জন্য পাঠানো হয়েছে'), done_ok: L('ঢোকানো হয়েছে', 'Entered', 'Entered'), rejected: L('বাতিল হয়েছে', 'Rejected', 'Rejected'),
  seeBill: L('ক্রয় বিল দেখুন', 'Open the purchase bill', 'Purchase bill দেখুন'), seeExp: L('দ্রুত খরচ দেখুন', 'Open quick expenses', 'Quick expense দেখুন'), seeItems: L('আইটেম দেখুন', 'Open items', 'Item দেখুন'),
  w_total: L('লাইনের যোগফল ৳{a}, কাগজের মোট ৳{b}। মিলিয়ে দেখুন (আটকায় না)।', 'Lines add up to Tk {a} but the paper says Tk {b}. Please check (does not block).', 'Lines-এর যোগফল ৳{a}, paper-এর total ৳{b}। মিলিয়ে দেখুন (আটকায় না)।'),
  w_unm: L('{n}টি লাইনের সিদ্ধান্ত বাকি', '{n} line(s) still need a decision', '{n}টি line-এর decision বাকি'),
  w_low: L('{n}টি ঘর পাঠক নিশ্চিত ছিল না', '{n} field(s) the reader was unsure about', '{n}টি field reader sure ছিল না'),
  w_dup: L('সন্দেহ: একই সাপ্লায়ার, বিল নম্বর ও টোটাল আগেই আছে', 'Possible duplicate: the same supplier, bill no. and total already exist', 'সন্দেহ: একই supplier, bill no. ও total আগেই আছে'),
  w_dupx: L('সন্দেহ: একই জায়গা, দিন, খাত ও টাকার খরচ আগেই আছে', 'Possible duplicate: an expense with the same place, day, head and amount exists', 'সন্দেহ: একই place, day, head ও amount-এর খরচ আগেই আছে'),
  e_scan_off: L('স্ক্যান বন্ধ আছে', 'Scan is switched off', 'Scan বন্ধ আছে'), e_not_reviewed: L('আগে "দেখা শেষ" করুন', 'Finish the check first', 'আগে "দেখা শেষ" করুন'), e_already_confirmed: L('এটি আগেই ঢোকানো হয়ে গেছে', 'This was already entered', 'এটি আগেই enter হয়ে গেছে'),
  e_duplicate_suspect: L('একই বিল আগে আছে বলে সন্দেহ। দেখে নিশ্চিত করুন', 'Looks like a duplicate. Look and acknowledge it', 'একই bill আগে আছে বলে সন্দেহ। দেখে নিশ্চিত করুন'), e_duplicate_bill: L('এই সাপ্লায়ারের এই বিল নম্বর আগেই আছে', 'This supplier already has this bill number', 'এই supplier-এর এই bill no. আগেই আছে'),
  e_supplier_not_mapped: L('সাপ্লায়ার বাছুন বা "নতুন" বলে চিহ্নিত করুন', 'Choose a supplier or mark it as new', 'Supplier বাছুন বা "নতুন" mark করুন'), e_similar_supplier_exists: L('একই নামের সাপ্লায়ার আছে। সেটি বাছুন', 'A supplier with almost the same name exists. Choose it', 'প্রায় একই নামের supplier আছে। সেটি বাছুন'),
  e_unmatched_lines: L('সব লাইনের সিদ্ধান্ত দিন', 'Every line needs a decision', 'সব line-এর decision দিন'), e_item_needs_approval: L('নতুন আইটেম বানাতে মালিকের অ্যাপ্রুভ লাগে', 'Creating an item needs the owner', 'নতুন item বানাতে owner-এর approval লাগে'),
  e_bad_number: L('একটি সংখ্যা ঠিক নয়', 'A number is not valid', 'একটি number ঠিক নয়'), e_bad_date: L('ডেট ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'), e_head_needed: L('খাত লিখুন (ইংরেজি কোড, যেমন transport)', 'Enter the head (a code such as transport)', 'Head লিখুন (English code, যেমন transport)'),
  e_bad_amount: L('টাকা লিখুন', 'Enter the amount', 'Amount লিখুন'), e_image_already_used: L('এই ছবি আগেই ব্যবহার হয়েছে', 'This photo was already used', 'এই photo আগেই use হয়েছে'), e_not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
  e_no_lines: L('কমপক্ষে একটি লাইন লাগবে', 'At least one line is needed', 'কমপক্ষে একটি line লাগবে'), e_item_not_found: L('আইটেমটি পাওয়া যায়নি', 'The item was not found', 'Item পাওয়া যায়নি'), e_bad_qty: L('Qty ঠিক নয়', 'The quantity is not valid', 'Qty ঠিক নয়'), e_bad_cost: L('কস্ট ঠিক নয়', 'The cost is not valid', 'Cost ঠিক নয়'),
  e_not_open: L('এটি আর বদলানো যায় না', 'This can no longer be changed', 'এটি আর বদলানো যায় না'), e_note_needed: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'),
  needSup: L('সাপ্লায়ার বাছুন', 'Choose a supplier', 'Supplier বাছুন'), needDate: L('ডেট দিন', 'Enter the date', 'Date দিন'), needLine: L('কমপক্ষে একটি লাইন লিখুন', 'Enter at least one line', 'কমপক্ষে একটি line লিখুন'),
  back: L('তালিকায় ফিরুন', 'Back to the list', 'List-এ ফিরুন'), engine: L('পদ্ধতি', 'Method', 'Method'), by: L('করেছেন', 'by', 'by'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  trail: L('ইতিহাস', 'History', 'History'), nodb: L('ডেটাবেস আপডেট (phase90.sql) বাকি', 'The database update (phase90.sql) is not installed yet', 'Database update (phase90.sql) বাকি'),
};
const T = (k) => lab(X[k]);
const fill = (s, o) => String(s).replace(/\{(\w+)\}/g, (m, k) => (o[k] === undefined ? m : o[k]));
const errText = (e) => {
  const m = String((e && e.message) || e || ''), code = (m.match(/^[a-z_ ]+/) || [''])[0].trim().replace(/ /g, '_');
  if (/schema cache|does not exist|Could not find the function/i.test(m)) return T('nodb');
  const k = 'e_' + code; return X[k] ? T(k) : m;
};

const D = { jobs: [], job: null, ed: null, ex: null, m: {}, sm: {}, lbl: {}, busy: false, pick: { kind: 'purchase_bill', loc: null }, cfg: null, conf: null, cc: null, dupAck: false, post: false, q: [], filter: '' };
const rule = (k, f) => { try { return B.rule ? B.rule(k, f) : f; } catch (e) { return f; } };
const cfg = () => ({ enabled: rule('scan_enabled', false) === true, engine: ['manual', 'browser_ocr', 'ai_vision'].includes(rule('scan_engine', 'manual')) ? rule('scan_engine', 'manual') : 'manual', minc: Number(rule('scan_min_confidence', 0.6)) || 0.6 });
const LOCS = () => { const all = B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []); return S.ctx && (S.ctx.is_owner || (S.ctx.roles || []).includes('management')) ? all : all.filter((l) => ((S.ctx && S.ctx.locations) || []).includes(l.id)); };
const isNet = (e) => { const m = String((e && e.message) || e || ''); return (typeof navigator !== 'undefined' && navigator.onLine === false) || /failed to fetch|networkerror|network request|load failed|fetch failed|offline/i.test(m); };
const num = (v) => { const s = String(v === null || v === undefined ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/[,৳\s]/g, ''); return s === '' ? null : (Number.isFinite(Number(s)) ? Number(s) : NaN); };
const r2 = (n) => Math.round(Number(n) * 100) / 100;
const hasBn = (s) => /[ঀ-৿]/.test(String(s || ''));

/* ---------- image: downscale + compress before upload (a bill photo is ~4 MB straight from the camera) ---------- */
function downscale(file, max, q) {
  max = max || 1600; q = q || 0.74;
  return new Promise((res, rej) => {
    const img = new Image(), u = URL.createObjectURL(file);
    img.onload = () => {
      const k = Math.min(1, max / Math.max(img.width, img.height)), c = document.createElement('canvas');
      c.width = Math.round(img.width * k) || 1; c.height = Math.round(img.height * k) || 1;
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height); URL.revokeObjectURL(u);
      const go = (qq) => c.toBlob((b) => { if (!b) return rej(new Error('image')); if (b.size > 700000 && qq > 0.45) return go(qq - 0.1); res(b); }, 'image/jpeg', qq);
      go(q);
    };
    img.onerror = () => { URL.revokeObjectURL(u); rej(new Error('image')); }; img.src = u;
  });
}
async function sha(blob) {
  try { const buf = await (blob.arrayBuffer ? blob.arrayBuffer() : new Response(blob).arrayBuffer()); const h = await crypto.subtle.digest('SHA-256', buf); return Array.from(new Uint8Array(h)).map((b) => b.toString(16).padStart(2, '0')).join(''); } catch (e) { return null; }
}

/* ---------- offline queue (IndexedDB; falls back to memory when the browser blocks it) ---------- */
const QDB = { mem: [] };
function qopen() {
  return new Promise((res, rej) => {
    try { const r = indexedDB.open('bos_scan', 1); r.onupgradeneeded = () => { r.result.createObjectStore('q', { keyPath: 'client' }); }; r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); } catch (e) { rej(e); }
  });
}
async function qall() { try { const db = await qopen(); return await new Promise((res, rej) => { const q = db.transaction('q').objectStore('q').getAll(); q.onsuccess = () => res(q.result || []); q.onerror = () => rej(q.error); }); } catch (e) { return QDB.mem.slice(); } }
async function qput(e) { try { const db = await qopen(); await new Promise((res, rej) => { const t = db.transaction('q', 'readwrite'); t.objectStore('q').put(e); t.oncomplete = res; t.onerror = () => rej(t.error); }); } catch (er) { QDB.mem = QDB.mem.filter((x) => x.client !== e.client).concat([e]); } }
async function qdel(client) { try { const db = await qopen(); await new Promise((res, rej) => { const t = db.transaction('q', 'readwrite'); t.objectStore('q').delete(client); t.oncomplete = res; t.onerror = () => rej(t.error); }); } catch (er) { QDB.mem = QDB.mem.filter((x) => x.client !== client); } }

/* ---------- send one photo: upload (deterministic path = idempotent) -> scan_create (idempotent on client id) -> reader ---------- */
async function send(en) {
  const path = 'SCAN/' + en.loc + '/' + en.client + '.jpg';
  const up = await sb.storage.from('photos').upload(path, en.blob, { contentType: 'image/jpeg', upsert: false });
  if (up.error && !/exist|duplicate|409/i.test(String(up.error.message || up.error.statusCode || ''))) throw up.error;
  const r = await sb.rpc('scan_create', { p_client: en.client, p_kind: en.kind, p_loc: en.loc, p_image_path: path, p_image_hash: en.hash || null, p_note: null });
  if (r.error) throw r.error;
  return r.data;
}
async function runReader(job, blob) {
  if (!job || job.dup) return;
  if (job.engine === 'browser_ocr') return ocrJob(job.id, blob);
  if (job.engine === 'ai_vision') return aiJob(job.id);
}
async function flushQueue(silent) {
  const list = await qall(); let n = 0;
  for (const en of list) {
    try { const job = await send(en); await qdel(en.client); n++; try { await runReader(job, en.blob); } catch (e) { /* the person types it */ } } catch (e) { if (isNet(e)) break; if (!silent) toast(errText(e)); await qdel(en.client); }
  }
  D.q = await qall(); if (n && !silent) toast(T('qsent') + ' ×' + n);
  return n;
}
window.addEventListener && window.addEventListener('online', () => { flushQueue(true).then(() => { if (/^#\/scan\/?$/.test(location.hash)) viewList(); }).catch(() => {}); });

/* ---------- reader 1: OCR in the browser ---------- */
function loadOcr() {
  return new Promise((res, rej) => {
    if (window.Tesseract) return res(window.Tesseract);
    const s = document.createElement('script'); s.src = CDN_OCR; s.async = true; s.crossOrigin = 'anonymous';
    const t = setTimeout(() => rej(new Error('ocr_load')), 30000);
    s.onload = () => { clearTimeout(t); window.Tesseract ? res(window.Tesseract) : rej(new Error('ocr_load')); }; s.onerror = () => { clearTimeout(t); rej(new Error('ocr_load')); };
    document.head.appendChild(s);
  });
}
const UNITS = 'kg|gm|g|ltr|l|pcs|pc|piece|dz|dozen|box|bag|pound|lb|bottle|packet|pkt';
function parseOcr(kind, data) {
  const raw = (data && data.lines && data.lines.length) ? data.lines.map((l) => ({ t: String(l.text || '').trim(), c: Math.max(0, Math.min(1, (Number(l.confidence) || 0) / 100)) }))
    : String((data && data.text) || '').split(/\r?\n/).map((t) => ({ t: t.trim(), c: 0.5 }));
  const ls = raw.filter((l) => l.t).map((l) => ({ t: l.t.replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)), c: l.c }));
  const clean = (s) => String(s).replace(/,/g, '');
  const out = {}, cf = {}; const NUM = '(\\d[\\d,]*(?:\\.\\d+)?)';
  const skip = /total|discount|vat|paid|due|balance|date|invoice|phone|mobile|tel\b|address|thank/i;
  const find = (re) => { let hit = null; for (const l of ls) { const m = l.t.match(re); if (m) hit = { v: m[1], c: l.c }; } return hit; };
  const dm = ls.map((l) => ({ m: l.t.match(/(\d{4}-\d{1,2}-\d{1,2})|(\d{1,2}[/.-]\d{1,2}[/.-]\d{4})/), c: l.c })).find((x) => x.m);
  if (dm) { out.date = dm.m[0]; cf.date = dm.c * 0.9; }
  if (kind === 'purchase_bill') {
    const bn = find(/(?:invoice|inv|bill|memo|challan)\s*(?:no|number|#)?\s*[:.#-]*\s*([A-Za-z0-9][A-Za-z0-9\-/]{1,30})/i); if (bn) { out.bill_no = bn.v; cf.bill_no = bn.c * 0.8; }
    const dc = find(new RegExp('discount\\s*[:\\-]?\\s*(?:tk|bdt)?\\s*' + NUM, 'i')); if (dc) { out.discount = clean(dc.v); cf.discount = dc.c * 0.8; }
    const first = ls.find((l) => !/^[\d\s.,:/-]+$/.test(l.t) && !skip.test(l.t) && l.t.length > 2); if (first) { out.supplier = { name: first.t }; cf.supplier = first.c * 0.6; }
  }
  const tot = find(new RegExp('(?:grand\\s*total|net\\s*(?:payable|amount)|total|amount)\\s*[:\\-]?\\s*(?:tk|bdt|৳)?\\s*' + NUM, 'i'));
  if (kind === 'expense') {
    const nums = ls.flatMap((l) => (l.t.match(/\d[\d,]*(?:\.\d+)?/g) || []).map((n) => ({ n: Number(clean(n)), c: l.c })));
    if (tot) { out.amount = clean(tot.v); cf.amount = tot.c * 0.8; } else if (nums.length) { const mx = nums.reduce((a, b) => (b.n > a.n ? b : a)); out.amount = String(mx.n); cf.amount = mx.c * 0.5; }
    const f = ls.find((l) => !/^[\d\s.,:/-]+$/.test(l.t)); if (f) { out.paid_to = f.t.slice(0, 120); cf.paid_to = f.c * 0.6; }
    return { extracted: out, confidence: cf };
  }
  if (kind === 'purchase_bill' && tot) { out.total = clean(tot.v); cf.total = tot.c * 0.85; }
  if (kind === 'other') { out.title = (ls[0] || { t: '' }).t.slice(0, 120); out.lines = ls.slice(1, 200).map((l) => ({ desc: l.t.slice(0, 200) })); cf.lines = ls.slice(1, 200).map((l) => ({ desc: l.c })); return { extracted: out, confidence: cf }; }
  const full = new RegExp('^(.{2,}?)\\s+(\\d+(?:\\.\\d+)?)\\s*(' + UNITS + ')?\\s*[x@*]?\\s*' + NUM + '\\s+' + NUM + '$', 'i'), two = new RegExp('^(.{2,}?)\\s+' + NUM + '$');
  const lines = [], lc = [];
  for (const l of ls) {
    if (skip.test(l.t)) continue;
    let m = kind === 'purchase_bill' ? l.t.match(full) : null;
    if (m) { lines.push({ desc: m[1].trim(), qty: m[2], unit: (m[3] || '').toLowerCase() || undefined, unit_cost: clean(m[4]), amount: clean(m[5]) }); lc.push({ desc: l.c, qty: l.c * 0.9, unit: l.c * 0.8, unit_cost: l.c * 0.9, amount: l.c * 0.9 }); continue; }
    m = l.t.match(two);
    if (m && !/^[\d\s.,:/-]+$/.test(m[1])) {
      if (kind === 'product_list') { lines.push({ desc: m[1].trim(), price: clean(m[2]) }); lc.push({ desc: l.c, price: l.c * 0.8 }); } else { lines.push({ desc: m[1].trim(), amount: clean(m[2]) }); lc.push({ desc: l.c, amount: l.c * 0.7 }); }
    }
  }
  out.lines = lines.slice(0, 300); cf.lines = lc.slice(0, 300);
  return { extracted: out, confidence: cf };
}
async function ocrJob(id, blob) {
  try {
    const Tz = await loadOcr(); const kind = (D.job && D.job.id === id ? D.job.kind : null) || D.pick.kind;
    const res = await Tz.recognize(blob, D.pick.bn ? 'eng+ben' : 'eng');
    const p = parseOcr(kind, res && res.data);
    const r = await sb.rpc('scan_set_extracted', { p_id: id, p_extracted: p.extracted, p_confidence: p.confidence, p_engine: 'browser_ocr', p_error: null }); if (r.error) throw r.error;
  } catch (e) { try { await sb.rpc('scan_set_extracted', { p_id: id, p_extracted: null, p_confidence: null, p_engine: 'browser_ocr', p_error: 'ocr: ' + String((e && e.message) || e).slice(0, 200) }); } catch (e2) { /* ignore */ } toast(T('readFail')); }
}

/* ---------- reader 2: AI through the edge function (the key lives only in the function's secrets) ---------- */
async function aiJob(id) {
  try {
    const ses = await sb.auth.getSession(); const tok = ses && ses.data && ses.data.session && ses.data.session.access_token; const C = window.BOS_CONFIG || {};
    const res = await fetch(String(C.url).replace(/\/$/, '') + '/functions/v1/scan-extract', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + tok, apikey: C.key }, body: JSON.stringify({ job_id: id }) });
    const j = await res.json().catch(() => ({}));
    if (!res.ok || j.ok === false) throw new Error(j.error || ('http ' + res.status));
  } catch (e) { try { await sb.rpc('scan_set_extracted', { p_id: id, p_extracted: null, p_confidence: null, p_engine: 'ai_vision', p_error: 'ai: ' + String((e && e.message) || e).slice(0, 200) }); } catch (e2) { /* ignore */ } toast(T('readFail')); }
}

/* ---------- list page ---------- */
const stChip = (s) => `<span class="chip ${s === 'confirmed' ? 'ok' : s === 'rejected' ? '' : 'warn'}">${esc(T('s_' + (s === 'confirmed' ? 'confirmed' : s)))}</span>`;
function pickHTML() {
  const c = D.cfg, locs = LOCS(); if (!D.pick.loc && locs[0]) D.pick.loc = locs[0].id;
  const nmL = (l) => (B.lab ? lab({ bn: l.name_bn, en: l.name_en || l.name_bn, mix: l.name_mix || l.name_bn }) : l.name_bn);
  return `<div class="card stack"><b>${esc(T('newScan'))}</b>
    <label for="sc_kind">${esc(T('kind'))}</label><select id="sc_kind">${KINDS.map((k) => `<option value="${k}" ${D.pick.kind === k ? 'selected' : ''}>${esc(T('k_' + k))}</option>`).join('')}</select>
    ${locs.length > 1 ? `<label for="sc_loc">${esc(T('place'))}</label><select id="sc_loc">${locs.map((l) => `<option value="${l.id}" ${l.id === D.pick.loc ? 'selected' : ''}>${esc(nmL(l))}</option>`).join('')}</select>` : ''}
    <p class="muted sc-eng">${esc(T('eng_' + c.engine))}</p>
    ${c.engine === 'browser_ocr' ? `<label class="row"><input type="checkbox" id="sc_bn" ${D.pick.bn ? 'checked' : ''}> ${esc(T('ocrBn'))}</label>` : ''}
    <div class="row wrap"><label class="btn primary sc-pick">📷 ${esc(T('take'))}<input type="file" accept="image/*" capture="environment" id="sc_cam" hidden></label>
      <label class="btn sc-pick">🖼 ${esc(T('gallery'))}<input type="file" accept="image/*" id="sc_gal" hidden></label></div>
    <div id="sc_busy" class="muted"></div></div>`;
}
async function viewList() {
  shell(T('title'), `<div id="sc_body"><p class="muted">${esc(T('loading'))}</p></div>`, true);
  D.cfg = cfg(); D.q = await qall();
  let rows = [], err = null;
  try { if (B.loadStatic) { await B.loadStatic(); D.cfg = cfg(); } const r = await sb.rpc('scan_list', { p_status: D.filter || null, p_loc: null, p_limit: 100 }); if (r.error) err = r.error; else rows = r.data || []; } catch (e) { err = e; }
  D.jobs = rows;
  const el = $('#sc_body'); if (!el) return;
  const q = D.q.length ? `<div class="card stack"><b>${esc(T('qwait'))}: ${D.q.length}</b><div class="row wrap"><button type="button" class="btn primary" data-act="scan_flush">${esc(T('qsend'))}</button><button type="button" class="btn" data-act="scan_qdrop">${esc(T('qdrop'))}</button></div></div>` : '';
  el.innerHTML = `<p class="muted">${esc(T('intro'))}</p>${D.cfg.enabled ? pickHTML() : `<div class="card"><p>${esc(T('off'))}</p></div>`}${q}
    <div class="row between"><b>${esc(T('list'))}</b><select id="sc_filter" aria-label="${esc(T('list'))}"><option value="">${esc(T('all'))}</option>${['uploaded', 'extracted', 'reviewed', 'confirmed', 'rejected'].map((s) => `<option value="${s}" ${D.filter === s ? 'selected' : ''}>${esc(T('s_' + s))}</option>`).join('')}</select></div>
    ${err ? `<p class="sc-err">${esc(errText(err))}</p>` : ''}
    ${rows.length ? rows.map((j) => `<div class="card sc-row"><div class="row between"><span><b>${esc(T('k_' + j.kind))}</b> ${stChip(j.status)} ${j.dups ? `<span class="chip warn">${esc(T('dupn'))}</span>` : ''}</span><button type="button" class="mini" data-act="scan_open" data-id="${esc(j.id)}">${esc(T('open'))}</button></div>
      <div class="muted" style="font-size:.8rem">${esc(String(j.created_at || '').slice(0, 16).replace('T', ' '))} · ${esc(j.created_staff || '')}</div></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`}`;
}

/* ---------- pick -> prepare -> send ---------- */
async function onPick(file) {
  if (!file) return; const busy = $('#sc_busy'); const say = (k) => { if (busy) busy.textContent = k ? T(k) : ''; };
  const kind = D.pick.kind, loc = Number(D.pick.loc) || (LOCS()[0] || {}).id; if (!loc) return toast(T('e_not_allowed'));
  try {
    say('working'); const blob = await downscale(file); const en = { client: rid(), kind, loc, hash: await sha(blob), blob, ts: Date.now() };
    let job;
    try { say('working'); job = await send(en); } catch (e) { if (isNet(e)) { await qput(en); D.q = await qall(); say(''); toast(T('queued')); return viewList(); } throw e; }
    if (job.engine !== 'manual') say('reading');
    try { await runReader(job, blob); } catch (e) { /* the person types it */ }
    say(''); go('scan/' + job.id);
  } catch (e) { say(''); toast(errText(e)); }
}
function go(h) { location.hash = '#/' + h; }

/* ---------- review page ---------- */
const blankLine = (kind) => (kind === 'other' ? { desc: '', amount: '' } : kind === 'product_list' ? { desc: '', unit: '', price: '' } : { desc: '', qty: '', unit: '', unit_cost: '' });
const clone = (o) => JSON.parse(JSON.stringify(o || {}));
function startEdit(job) {
  const base = clone(job.edited || job.extracted || {});
  if (!Array.isArray(base.lines) && job.kind !== 'expense') base.lines = [blankLine(job.kind)];
  if (job.kind === 'purchase_bill' && !base.supplier) base.supplier = { name: '' };
  D.ed = base; D.ex = clone(job.extracted || {}); D.conf = job.confidence || null; D.m = {}; D.sm = {}; D.cc = null; D.dupAck = false; D.post = false;
}
const same = (a, b) => String(a === undefined || a === null ? '' : a) === String(b === undefined || b === null ? '' : b);
// a field is "low" when the reader was unsure AND the person has not changed it
function isLow(key, idx) {
  if (!D.conf || !D.ex) return false; const min = D.cfg.minc;
  if (idx === null || idx === undefined) { const c = D.conf[key]; if (typeof c !== 'number' || c >= min) return false; return key === 'supplier' ? same((D.ed.supplier || {}).name, (D.ex.supplier || {}).name) : same(D.ed[key], D.ex[key]); }
  const lc = D.conf.lines && D.conf.lines[idx]; if (!lc || typeof lc[key] !== 'number' || lc[key] >= min) return false;
  return same(((D.ed.lines || [])[idx] || {})[key], ((D.ex.lines || [])[idx] || {})[key]);
}
const lowAttr = (low, conf) => (low ? ` class="sc-low" title="${esc(T('low'))}${conf !== undefined ? ' ' + Math.round(conf * 100) + '%' : ''}"` : '');
function inp(id, label, val, o) {
  o = o || {}; const low = o.low;
  return `<div${low ? ' class="sc-low"' : ''}${low ? ` title="${esc(T('low'))}"` : ''}><label for="${id}">${esc(label)}</label><input id="${id}" ${o.attrs || ''} value="${esc(val === undefined || val === null ? '' : val)}"></div>`;
}
function supHTML() {
  const s = D.ed.supplier || {}, sg = D.sm.list || [];
  return `<div class="card stack"><b>${esc(T('supplier'))}</b>${isLow('supplier') ? `<div class="sc-low"><span class="muted">${esc(T('low'))}</span></div>` : ''}
    <div class="row"><input id="sc_sup" value="${esc(s.name || '')}" placeholder="${esc(T('supplier'))}" style="flex:1"><button type="button" class="btn" data-act="scan_supfind">${esc(T('find'))}</button></div>
    ${s.id ? `<div class="chip ok">${esc(T('chosen'))}: ${esc(D.lbl['s:' + s.id] || s.name || '')}</div>` : s.create ? `<div class="chip warn">${esc(T('supNew'))}: ${esc(s.name || '')} <button type="button" class="mini" data-act="scan_supundo">${esc(T('supUndo'))}</button></div>` : `<div class="muted">${esc(T('supHelp'))}</div>`}
    <div class="row wrap">${sg.map((x) => `<button type="button" class="chip sc-sugg" data-act="scan_suppick" data-id="${esc(x.supplier_id)}" data-n="${esc(x.name)}">${esc(x.name)} · ${Math.round(x.score * 100)}%</button>`).join('')}
      ${(s.name && !s.create) ? `<button type="button" class="chip sc-sugg" data-act="scan_supnew">+ ${esc(T('newSup'))}</button>` : ''}</div></div>`;
}
function lineHTML(l, i, kind) {
  const c = D.conf && D.conf.lines && D.conf.lines[i] || {}, lo = (k) => isLow(k, i);
  const dec = l.decision || '', opts = kind === 'purchase_bill' ? ['map', 'create', 'text', 'skip'] : kind === 'product_list' ? ['map', 'create', 'skip'] : [];
  let body = inp(`sc_l${i}_desc`, T('desc'), l.desc, { low: lo('desc'), attrs: `data-l="${i}" data-k="desc"` });
  if (kind === 'purchase_bill') body += `<div class="sc-grid">${inp(`sc_l${i}_qty`, T('qty'), l.qty, { low: lo('qty'), attrs: `data-l="${i}" data-k="qty" inputmode="decimal"` })}${inp(`sc_l${i}_unit`, T('unit'), l.unit, { low: lo('unit'), attrs: `data-l="${i}" data-k="unit"` })}${inp(`sc_l${i}_uc`, T('ucost'), l.unit_cost, { low: lo('unit_cost'), attrs: `data-l="${i}" data-k="unit_cost" inputmode="decimal"` })}</div>
      <div class="muted">${esc(T('lamt'))}: ৳ ${esc(String(num(l.qty) > 0 && num(l.unit_cost) >= 0 ? r2(num(l.qty) * num(l.unit_cost)) : '—'))}${l.amount ? ' · ' + esc(String(l.amount)) : ''}</div>`;
  else if (kind === 'product_list') body += `<div class="sc-grid">${inp(`sc_l${i}_unit`, T('unit'), l.unit, { low: lo('unit'), attrs: `data-l="${i}" data-k="unit"` })}${inp(`sc_l${i}_price`, T('price'), l.price, { low: lo('price'), attrs: `data-l="${i}" data-k="price" inputmode="decimal"` })}</div>`;
  else body += inp(`sc_l${i}_amount`, T('amount'), l.amount, { low: lo('amount'), attrs: `data-l="${i}" data-k="amount" inputmode="decimal"` });
  let dh = '';
  if (opts.length) {
    dh = `<label for="sc_l${i}_dec">${esc(T('decide'))}</label><select id="sc_l${i}_dec" data-l="${i}" data-k="decision"><option value="">${esc(T('choose'))}</option>${opts.map((o) => `<option value="${o}" ${dec === o ? 'selected' : ''}>${esc(T('d_' + o))}</option>`).join('')}</select>`;
    if (dec === 'map') {
      const ms = D.m[i] || [];
      dh += (l.item_id ? `<div class="chip ok">${esc(T('chosen'))}: ${esc(D.lbl['i:' + l.item_id] || l.item_id)}</div>` : '') +
        `<div class="muted">${esc(T('sugg'))}</div><div class="row wrap">${ms.length ? ms.map((m) => `<button type="button" class="chip sc-sugg ${l.item_id === m.item_id ? 'on' : ''}" data-act="scan_itempick" data-l="${i}" data-id="${esc(m.item_id)}" data-n="${esc(m.code + ' · ' + (m.name_en || m.name_bn || ''))}">${esc(m.code)} · ${esc(m.name_en || m.name_bn || '')} · ${Math.round(m.score * 100)}%</button>`).join('') : `<span class="muted">${esc(T('nosugg'))}</span>`}</div>
        <div class="row"><input id="sc_l${i}_q" placeholder="${esc(T('findph'))}" style="flex:1" value=""><button type="button" class="btn" data-act="scan_itemfind" data-l="${i}">${esc(T('find'))}</button></div>`;
    } else if (dec === 'create') {
      const bn = hasBn(l.desc);
      dh += inp(`sc_l${i}_nen`, T('nameEn'), l.name_en !== undefined ? l.name_en : (bn ? '' : l.desc), { attrs: `data-l="${i}" data-k="name_en"` }) + inp(`sc_l${i}_nbn`, T('nameBn'), l.name_bn !== undefined ? l.name_bn : (bn ? l.desc : ''), { attrs: `data-l="${i}" data-k="name_bn"` }) + (B.catpick && B.catpick.catOptions ? `<div><label for="sc_l${i}_cat">${esc(T('cat'))}</label><select id="sc_l${i}_cat" data-l="${i}" data-k="category">${B.catpick.catOptions(l.category, '—')}</select></div>` : inp(`sc_l${i}_cat`, T('cat'), l.category, { attrs: `data-l="${i}" data-k="category"` }));   // bos100: pick, do not type
    }
  }
  return `<div class="card stack sc-line${dec === 'skip' ? ' sc-skip' : ''}"><div class="row between"><b>${esc(T('line'))} ${i + 1}</b><button type="button" class="mini" data-act="scan_delline" data-l="${i}">${esc(T('del'))}</button></div>${body}${dh}</div>`;
}
function warnHTML(job) {
  const w = job.warnings || [], out = [];
  w.forEach((x) => { if (x.code === 'total_mismatch') out.push(fill(T('w_total'), { a: x.lines_total, b: x.paper_total })); });
  const un = w.find((x) => x.code === 'unmatched_lines'); if (un) out.push(fill(T('w_unm'), { n: un.n }));
  const lo = w.filter((x) => x.code === 'low_confidence').length; if (lo) out.push(fill(T('w_low'), { n: lo }));
  (job.dups || []).forEach((d) => out.push(job.kind === 'expense' ? T('w_dupx') : T('w_dup')));
  return out.length ? `<div class="card sc-warn">${out.map((s) => `<div>⚠ ${esc(s)}</div>`).join('')}</div>` : '';
}
function resultLink(job) {
  if (job.result_type === 'purchase_bills') return `<a class="btn" href="#/purchase/${esc(job.result_id)}">${esc(T('seeBill'))}</a>`;
  if (job.result_type === 'quick_expenses') return `<a class="btn" href="#/quickexp">${esc(T('seeExp'))}</a>`;
  if (job.result_type === 'items') return `<a class="btn" href="#/items">${esc(T('seeItems'))}</a>`;
  return '';
}
function editorHTML(job) {
  const e = D.ed, k = job.kind; let h = '';
  const dt = (e.date || '').slice(0, 10);
  if (k === 'purchase_bill') h += supHTML() + `<div class="card stack">${inp('sc_h_bill_no', T('billNo'), e.bill_no, { low: isLow('bill_no'), attrs: 'data-h="bill_no"' })}${inp('sc_h_date', T('date'), dt, { low: isLow('date'), attrs: 'data-h="date" type="date"' })}
    <div class="sc-grid">${inp('sc_h_discount', T('discount'), e.discount, { low: isLow('discount'), attrs: 'data-h="discount" inputmode="decimal"' })}${inp('sc_h_total', T('paper'), e.total, { low: isLow('total'), attrs: 'data-h="total" inputmode="decimal"' })}</div></div>`;
  else if (k === 'expense') h += `<div class="card stack"><div${isLow('head') ? ' class="sc-low"' : ''}><label for="sc_h_head">${esc(T('head'))}</label><input id="sc_h_head" data-h="head" list="sc_heads" value="${esc(e.head || '')}"><datalist id="sc_heads">${HEADS.map((x) => `<option value="${x}">`).join('')}</datalist></div>
    ${inp('sc_h_paid_to', T('paidTo'), e.paid_to, { low: isLow('paid_to'), attrs: 'data-h="paid_to"' })}<div class="sc-grid">${inp('sc_h_amount', T('amount'), e.amount, { low: isLow('amount'), attrs: 'data-h="amount" inputmode="decimal"' })}${inp('sc_h_date', T('date'), dt, { low: isLow('date'), attrs: 'data-h="date" type="date"' })}</div>
    <label for="sc_h_mode">${esc(T('mode'))}</label><select id="sc_h_mode" data-h="mode">${['cash', 'bank', 'mobile'].map((m) => `<option value="${m}" ${(e.mode || 'cash') === m ? 'selected' : ''}>${m}</option>`).join('')}</select>
    <label class="row"><input type="checkbox" id="sc_h_receipt" data-h="receipt" ${e.receipt ? 'checked' : ''}> ${esc(T('receipt'))}</label></div>`;
  else if (k === 'other') h += `<div class="card stack">${inp('sc_h_title', T('titleF'), e.title, { attrs: 'data-h="title"' })}</div>`;
  if (k !== 'expense') h += `<div class="row between"><b>${esc(T('lines'))} (${(e.lines || []).length})</b></div>` + (e.lines || []).map((l, i) => lineHTML(l, i, k)).join('') + `<button type="button" class="btn full" data-act="scan_addline">+ ${esc(T('add'))}</button>`;
  h += `<div class="card stack">${inp('sc_h_note', T('note'), e.note, { attrs: 'data-h="note"' })}</div>`;
  return h;
}
async function photoHTML(job) {
  let u = null; if (D.photoFor === job.image_path && D.photo && Date.now() - D.photoAt < 480000) u = D.photo;
  else try { const r = await sb.storage.from('photos').createSignedUrl(job.image_path, 600); u = r && r.data && (r.data.signedUrl || r.data.signedURL); } catch (e) { u = null; }
  D.photo = u; D.photoFor = job.image_path; D.photoAt = Date.now(); return u ? `<div class="card sc-photo"><img id="sc_img" src="${esc(u)}" alt="${esc(T('photo'))}" data-act="scan_zoom"><button type="button" class="mini" data-act="scan_zoom">🔍 ${esc(T('zoom'))}</button></div>` : `<div class="card muted">${esc(T('nophoto'))}</div>`;
}
async function viewJob(id) {
  shell(T('title'), `<div id="sc_body"><p class="muted">${esc(T('loading'))}</p></div>`, 'scan');
  D.cfg = cfg(); const r = await sb.rpc('scan_get', { p_id: id }); if (r.error) { const el = $('#sc_body'); if (el) el.innerHTML = `<p class="sc-err">${esc(errText(r.error))}</p>`; return; }
  D.job = r.data; if (!D.ed || D.edId !== id) { startEdit(D.job); D.edId = id; }
  await draw();
}
async function draw() {
  const job = D.job, el = $('#sc_body'); if (!el) return;
  const open = ['uploaded', 'extracted', 'reviewed'].includes(job.status), photo = await photoHTML(job);
  let bodyH;
  if (job.cost_hidden) bodyH = `<div class="card"><p>${esc(T('hidden'))}</p></div>`;
  else if (open) bodyH = (D.cfg.engine !== 'manual' && job.engine !== 'manual' ? `<p class="muted">${esc(T('eng_' + job.engine))}</p>` : '') + (job.extracted ? `<p class="muted">${esc(T('lowKey'))}</p>` : '') + warnHTML(job) + editorHTML(job) +
    `<div class="s2-bar sc-bar"><button type="button" class="btn" data-act="scan_save">${esc(T('save'))}</button><button type="button" class="btn primary" data-act="scan_done">${esc(job.can_confirm ? T('done') : T('doneNoRight'))}</button><button type="button" class="btn" data-act="scan_reject">${esc(T('reject'))}</button></div>`;
  else bodyH = `<div class="card stack">${job.status === 'confirmed' ? resultLink(job) : `<p>${esc(T('s_rejected'))}: ${esc(job.reject_reason || '')}</p>`}</div>` + (job.edited ? `<pre class="muted sc-pre">${esc(JSON.stringify(job.edited, null, 1).slice(0, 4000))}</pre>` : '');
  const trail = (job.events || []).map((x) => `<div class="muted" style="font-size:.78rem">${esc(String(x.at || '').slice(0, 16).replace('T', ' '))} · ${esc(x.action)} ${x.by ? '· ' + esc(x.by) : ''}</div>`).join('');
  el.innerHTML = `<div class="row between"><span><b>${esc(T('k_' + job.kind))}</b> ${stChip(job.status)}</span><a href="#/scan" class="mini">${esc(T('back'))}</a></div>
    <div class="sc-split"><div class="sc-left">${photo}</div><div class="sc-right">${bodyH}</div></div><details data-ctl="off"><summary>${esc(T('trail'))}</summary>${trail}</details>`;
  if (open && !job.cost_hidden) ensureMatches();
}
async function ensureMatches() {
  const k = D.job.kind; if (k === 'expense' || k === 'other') return;
  const lines = D.ed.lines || []; let changed = false;
  for (let i = 0; i < Math.min(lines.length, 60); i++) {
    const l = lines[i]; if (D.m[i] || !l.desc || l.decision === 'skip' || l.decision === 'text' || l.decision === 'create') continue;
    changed = true; D.m[i] = []; try { const r = await sb.rpc('scan_match_items', { p_text: String(l.desc).slice(0, 200), p_limit: 5 }); D.m[i] = r.error ? [] : (r.data || []); } catch (e) { D.m[i] = []; }
  }
  if (k === 'purchase_bill' && D.ed.supplier && D.ed.supplier.name && !D.sm.list) { changed = true; await supFind(false); }
  if (changed && location.hash.indexOf('#/scan/') === 0 && D.job && D.job.id === (D.edId || '') && !D.busy) redrawKeepFocus();
}
function redrawKeepFocus() { const a = document.activeElement && document.activeElement.id; if (a && /^sc_/.test(a) && /input|textarea/i.test(document.activeElement.tagName)) return; draw(); }
async function supFind(redraw) {
  const nameV = ((D.ed.supplier || {}).name || '').slice(0, 200); if (!nameV) { D.sm.list = []; return; }
  try { const r = await sb.rpc('scan_match_suppliers', { p_text: nameV, p_limit: 5 }); D.sm.list = r.error ? [] : (r.data || []); } catch (e) { D.sm.list = []; }
  if (redraw !== false) draw();
}

/* ---------- payload / validation / save ---------- */
function payload() {
  const e = clone(D.ed); const k = D.job.kind;
  (e.lines || []).forEach((l) => { Object.keys(l).forEach((x) => { if (l[x] === '' || l[x] === null) delete l[x]; }); });
  if (Array.isArray(e.lines)) e.lines = e.lines.filter((l) => Object.keys(l).some((x) => x !== 'decision') || l.decision);
  Object.keys(e).forEach((x) => { if (e[x] === '' || e[x] === null) delete e[x]; });
  if (e.supplier && !e.supplier.name && !e.supplier.id) delete e.supplier;
  if (k === 'expense') delete e.lines;
  return e;
}
function check(e, k) {
  if (k === 'purchase_bill') { if (!e.supplier || !(e.supplier.id || (e.supplier.create && e.supplier.name))) return T('needSup'); if (!e.date) return T('needDate'); if (!(e.lines || []).length) return T('needLine'); }
  if (k === 'expense') { if (!e.date) return T('needDate'); if (!e.head) return T('e_head_needed'); if (!(num(e.amount) > 0)) return T('e_bad_amount'); }
  if (k === 'product_list' && !(e.lines || []).length) return T('needLine');
  return null;
}
async function saveDraft(final) {
  const e = payload(); const r = await sb.rpc('scan_review_save', { p_id: D.job.id, p_edited: e, p_final: !!final });
  if (r.error) throw r.error;
  return r.data;
}
async function reload() { const r = await sb.rpc('scan_get', { p_id: D.job.id }); if (r.error) throw r.error; D.job = r.data; if (D.job.status === 'confirmed' || D.job.status === 'rejected') { D.ed = null; D.edId = null; } await draw(); }

/* ---------- confirm sheet ---------- */
function confirmSheet(res) {
  const j = D.job, e = payload(), dups = res.dups || [];
  D.cc = D.cc || rid();
  const lines = (e.lines || []).filter((l) => l.decision !== 'skip').length;
  const sum = j.kind === 'purchase_bill' ? `${esc(((e.supplier || {}).name) || '')} · ${esc(e.bill_no || '')} · ${esc(e.date || '')} · ${lines} ${esc(T('lines'))}` : j.kind === 'expense' ? `${esc(e.head || '')} · ৳ ${esc(String(e.amount || ''))} · ${esc(e.date || '')}` : `${lines} ${esc(T('lines'))}`;
  openSheet(`<div class="stack"><h3>${esc(T('cq'))}</h3><div><b>${esc(T('k_' + j.kind))}</b><br>${sum}</div>
    ${dups.length ? `<div class="sc-warn">⚠ ${esc(j.kind === 'expense' ? T('w_dupx') : T('w_dup'))}<label class="row"><input type="checkbox" id="sc_ack"> ${esc(T('ackDup'))}</label></div>` : ''}
    ${j.kind === 'purchase_bill' ? `<label class="row"><input type="checkbox" id="sc_post"> ${esc(T('post'))}</label><div class="muted">${esc(T('postNo'))}</div>` : ''}
    <div class="row wrap"><button type="button" class="btn primary" data-act="scan_confirm_go">${esc(T('confirm'))}</button><button type="button" class="btn" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`);
}

Object.assign(H, {
  scan_open: (a) => go('scan/' + a.dataset.id),
  scan_flush: async () => { const n = await flushQueue(false); if (!n) toast(T('queued')); viewList(); },
  scan_qdrop: async () => { for (const x of await qall()) await qdel(x.client); viewList(); },
  scan_zoom: () => { if (D.photo) openSheet(`<div class="sc-zoom"><img src="${esc(D.photo)}" alt="${esc(T('photo'))}"></div>`); },
  scan_addline: () => { (D.ed.lines = D.ed.lines || []).push(blankLine(D.job.kind)); draw(); },
  scan_delline: (a) => { const i = Number(a.dataset.l); D.ed.lines.splice(i, 1); D.m = {}; if (!D.ed.lines.length) D.ed.lines.push(blankLine(D.job.kind)); draw(); },
  scan_itempick: (a) => { const i = Number(a.dataset.l), l = D.ed.lines[i]; l.item_id = a.dataset.id; l.decision = 'map'; D.lbl['i:' + a.dataset.id] = a.dataset.n; draw(); },
  scan_itemfind: async (a) => { const i = Number(a.dataset.l), q = (($('#sc_l' + i + '_q') || {}).value || D.ed.lines[i].desc || '').trim(); if (!q) return; const r = await sb.rpc('scan_match_items', { p_text: q.slice(0, 200), p_limit: 8 }); D.m[i] = r.error ? [] : (r.data || []); draw(); },
  scan_supfind: () => supFind(true),
  scan_suppick: (a) => { D.ed.supplier = { id: a.dataset.id, name: a.dataset.n }; D.lbl['s:' + a.dataset.id] = a.dataset.n; draw(); },
  scan_supnew: () => { D.ed.supplier = { name: (D.ed.supplier || {}).name, create: true }; draw(); },
  scan_supundo: () => { D.ed.supplier = { name: (D.ed.supplier || {}).name }; draw(); },
  scan_save: async () => { if (D.busy) return; D.busy = true; try { await saveDraft(false); toast(T('saved')); await reload(); } catch (e) { toast(errText(e)); } finally { D.busy = false; } },
  scan_done: async () => {
    if (D.busy) return; const msg = check(payload(), D.job.kind); if (msg) return toast(msg);
    D.busy = true;
    try { const res = await saveDraft(true); if (!D.job.can_confirm) { toast(T('sent')); await reload(); return; } confirmSheet(res); } catch (e) { toast(errText(e)); } finally { D.busy = false; }
  },
  scan_confirm_go: async () => {
    if (D.busy) return; D.busy = true;
    try {
      const ack = !!($('#sc_ack') || {}).checked, post = !!($('#sc_post') || {}).checked;
      const r = await sb.rpc('scan_confirm', { p_id: D.job.id, p_client: D.cc, p_ack_dup: ack, p_post: post });
      if (r.error) { toast(errText(r.error)); return; }
      closeSheet(); D.cc = null; toast(T('done_ok')); await reload();
    } catch (e) { toast(errText(e)); } finally { D.busy = false; }
  },
  scan_reject: () => openSheet(`<div class="stack"><h3>${esc(T('reject'))}</h3><label for="sc_why">${esc(T('rwhy'))}</label><textarea id="sc_why" rows="3" maxlength="300"></textarea>
    <div class="row wrap"><button type="button" class="btn primary" data-act="scan_reject_go">${esc(T('reject'))}</button><button type="button" class="btn" data-act="closesheet">${esc(T('cancel'))}</button></div></div>`),
  scan_reject_go: async () => {
    const why = (($('#sc_why') || {}).value || '').trim(); if (why.length < 3) return toast(T('e_note_needed'));
    const r = await sb.rpc('scan_reject', { p_id: D.job.id, p_reason: why }); if (r.error) return toast(errText(r.error));
    closeSheet(); toast(T('rejected')); await reload();
  },
});
// typing updates the working copy only (no redraw, so the keyboard stays open)
document.addEventListener('input', (e) => {
  const t = e.target; if (!t || !D.ed) return;
  if (t.id === 'sc_sup') { D.ed.supplier = { name: t.value }; D.sm.list = null; return; }
  if (t.dataset && t.dataset.h) { D.ed[t.dataset.h] = t.type === 'checkbox' ? t.checked : t.value; return; }
  if (t.dataset && t.dataset.l !== undefined && t.dataset.k && t.dataset.k !== 'decision') { const l = D.ed.lines && D.ed.lines[Number(t.dataset.l)]; if (l) { l[t.dataset.k] = t.value; if (t.dataset.k === 'desc') delete D.m[Number(t.dataset.l)]; } }
});
document.addEventListener('change', (e) => {
  const t = e.target; if (!t) return;
  if (t.id === 'sc_kind') D.pick.kind = t.value;
  if (t.id === 'sc_loc') D.pick.loc = Number(t.value);
  if (t.id === 'sc_bn') D.pick.bn = !!t.checked;
  if (t.id === 'sc_filter') { D.filter = t.value; viewList(); }
  if (t.id === 'sc_cam' || t.id === 'sc_gal') { const f = t.files && t.files[0]; t.value = ''; onPick(f); }
  if (t.dataset && t.dataset.h === 'receipt' && D.ed) D.ed.receipt = !!t.checked;
  if (t.dataset && t.dataset.k === 'decision' && D.ed) { const l = D.ed.lines[Number(t.dataset.l)]; l.decision = t.value || undefined; if (t.value !== 'map') delete l.item_id; draw(); }
});

async function view() {
  const sub = location.hash.replace(/^#\/?/, '').split('/').slice(1).join('/');
  if (sub && /^[0-9a-f-]{36}$/i.test(sub)) return viewJob(sub);
  return viewList();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { scan: view });
B.scan = { X, T, view, errText, parseOcr, payload, check, isLow, startEdit, send, flushQueue, qall, qput, qdel, QDB, downscale, D, cfg, num, _set: (job, ed) => { D.job = job; D.ed = ed; D.cfg = D.cfg || cfg(); } };

const css = document.createElement('style'); css.id = 'sccss';
css.textContent = `.sc-split{display:block}.sc-photo img{width:100%;max-height:42vh;object-fit:contain;border-radius:10px;border:1px solid var(--line);background:#000}
@media (min-width:760px){.sc-split{display:grid;grid-template-columns:1fr 1fr;gap:12px;align-items:start}.sc-left{position:sticky;top:8px}.sc-photo img{max-height:80vh}}
.sc-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(90px,1fr));gap:8px}.sc-low input,.sc-low select{border-color:var(--sig-warn);background:var(--warn-bg)}
.sc-low{border-radius:8px}.sc-warn{border-color:var(--sig-warn);background:var(--warn-bg)}.sc-err{color:var(--sig-bad)}.sc-skip{opacity:.55}
.sc-sugg{cursor:pointer;min-height:40px;max-width:100%;overflow-wrap:anywhere;text-align:start}.sc-sugg.on{border-color:var(--ok);background:var(--ok-bg)}
.sc-pick{display:inline-flex;align-items:center;min-height:48px;cursor:pointer;margin:0}.sc-bar{position:sticky;bottom:0;z-index:4;display:flex;gap:8px;padding:10px 0;background:var(--bg);border-top:1px solid var(--line);flex-wrap:wrap}
.sc-bar button{flex:1;min-height:44px}.sc-zoom{max-height:80vh;overflow:auto}.sc-zoom img{width:220%;max-width:none}.sc-pre{white-space:pre-wrap;font-size:.75rem;overflow-wrap:anywhere}
.sc-line input,.sc-line select{width:100%;box-sizing:border-box}body.has-bnav .sc-bar{bottom:58px}`;
document.head.appendChild(css);
})();
