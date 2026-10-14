/* Islamia BOS · Books 96 (#/books96): screens for the phase96 backend (step D23).
   Tab 1 "Opening stock": the opening-stock helper. Per place: opening stock value, what the opening journal already carries, GL inventory, stock valuation and the
     difference; the double-count warning; a RECOMMENDED way (card) and four ways (owner capital / existing opening account / skip / only the difference), each with a dry-run
     preview (no writes). Apply is owner only. Nothing is ever applied by itself.
   Tab 2 "Cost waiting": the list of documents that wait for a cost (wastage, production ingredients, count differences, openings, transfers, purchase returns), oldest first,
     the aging alert (the owner types the number, blank = none) and a sheet to supply the cost: item average / last purchase / recipe standard / manual with a reason,
     with the RECOMMENDED choice and a dry-run before the write. The document then posts once.
   Gates are the server's: owner or cost right (and place) for the cost side, owner for the apply. Language rule: English mode all English, Bangla mode keeps common words English.
   Server: supabase/phase96.sql. data-act names start with d23_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v == null ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return NaN; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const money = (n) => '৳ ' + fm(n);

const X = {
  title: L('শুরুর স্টক ও খরচের অপেক্ষা', 'Opening stock and cost waiting', 'Opening stock ও cost-এর অপেক্ষা'),
  t_ob: L('শুরুর স্টক', 'Opening stock', 'Opening stock'), t_cw: L('খরচের অপেক্ষা', 'Cost waiting', 'Cost-এর অপেক্ষা'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), retry: L('আবার চেষ্টা করুন', 'Try again', 'আবার Try করুন'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  place: L('জায়গা', 'Place', 'Place'), allPlaces: L('সব জায়গা', 'All places', 'সব place'), show: L('দেখান', 'Show', 'Show'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'), recNote: L('প্রস্তাব মানা বাধ্যতামূলক নয়; সিস্টেম নিজে থেকে কিছু করে না, আপনি যা চান সেটাই বেছে নিন।', 'A recommendation never blocks you and nothing is applied by itself; choose what you want.', 'Recommendation মানা বাধ্যতামূলক নয়; system নিজে কিছু করে না, আপনার পছন্দই চলবে।'),
  ownerOnly: L('এটি করতে মালিক লাগবে।', 'Only the owner can do this.', 'এটা করতে owner লাগবে।'), cancel: L('বাদ দিন', 'Cancel', 'Cancel'), close: L('বন্ধ করুন', 'Close', 'Close'),
  reason: L('কারণ', 'Reason', 'Reason'), dryNote: L('এটি শুধু দেখা (dry run): কিছু লেখা হয়নি।', 'This is a dry run: nothing was written.', 'এটা শুধু dry run: কিছু লেখা হয়নি।'),
  // opening stock
  obIntro: L('শুরুর স্টক খাতায় তোলার আগে দেখে নিন, শুরুর জের (opening journal) এ stock আগেই আছে কি না। থাকলে আবার তুললে দুইবার গোনা হবে।',
    'Before opening stock goes to the books, see whether the stock is already inside the opening journal. If it is, posting it again counts it twice.',
    'Opening stock খাতায় তোলার আগে দেখুন opening journal এ stock আগেই আছে কি না। থাকলে আবার তুললে দুইবার গোনা হবে।'),
  openVal: L('শুরুর স্টকের মূল্য', 'Opening stock value', 'Opening stock-এর value'), inJournal: L('শুরুর জের এ আগেই আছে', 'Already in the opening journal', 'Opening journal-এ আগেই আছে'),
  glInv: L('খাতায় stock', 'Stock in the books (GL)', 'Books-এ stock (GL)'), valuation: L('stock এর মূল্য', 'Stock valuation', 'Stock valuation'), diff: L('পার্থক্য', 'Difference', 'Difference'),
  rows: L('সারি', 'rows', 'row'), uncosted: L('খরচ ছাড়া সারি', 'rows without cost', 'cost ছাড়া row'), byswitch: L('সুইচ দিয়ে আগেই তোলা', 'Already posted by the switch', 'Switch দিয়ে আগেই তোলা'),
  decided: L('সিদ্ধান্ত নেওয়া হয়েছে', 'Decision taken', 'Decision নেওয়া হয়েছে'), switchL: L('শুরুর স্টক পোস্টিং সুইচ', 'Opening stock posting switch', 'Opening stock posting switch'), on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'),
  risk: L('দুইবার গোনার ঝুঁকি আছে', 'Double count risk', 'Double count-এর ঝুঁকি আছে'), noRisk: L('দুইবার গোনার ঝুঁকি দেখা যায়নি ✓', 'No double count risk found ✓', 'Double count-এর ঝুঁকি পাওয়া যায়নি ✓'),
  recL: L('সিস্টেমের প্রস্তাব', 'System recommendation', 'System-এর recommendation'), why: L('কেন', 'Why', 'কেন'),
  o_owner_capital: L('মালিকের মূলধনের বিপরীতে', 'Against owner capital', 'Owner capital-এর against-এ'), o_existing_account: L('আগের একটি শুরুর জের খাতের বিপরীতে', 'Against an existing opening balance account', 'আগের একটা opening balance account-এর against-এ'),
  o_skip: L('বাদ: খাতায় আগেই আছে', 'Skip: already in the books', 'Skip: books-এ আগেই আছে'), o_difference: L('শুধু পার্থক্যটুকু', 'Only the difference', 'শুধু difference-টুকু'),
  o_none: L('কিছু করার নেই', 'Nothing to do', 'কিছু করার নেই'), o_wait_for_cost: L('আগে খরচ দিন', 'Supply the cost first', 'আগে cost দিন'),
  d_owner_capital: L('Dr stock / Cr মালিকের মূলধন: পুরো শুরুর স্টক।', 'Dr stock / Cr owner capital for the whole opening stock.', 'Dr stock / Cr owner capital: পুরো opening stock।'),
  d_existing_account: L('Dr stock / Cr আপনার দেওয়া একটি equity বা liability খাত।', 'Dr stock / Cr an equity or liability account you name.', 'Dr stock / Cr আপনার দেওয়া একটা equity বা liability account।'),
  d_skip: L('কিছু তোলা হয় না; শুধু সিদ্ধান্ত লেখা থাকে। সুইচ চালু থাকলেও এই stock আবার তোলা হবে না।', 'Nothing is posted; only the decision is kept. Even with the switch on, this stock is not posted again.', 'কিছু post হয় না; শুধু decision লেখা থাকে। Switch on থাকলেও এই stock আবার post হবে না।'),
  d_difference: L('শুরুর জের এ যতটা নেই শুধু ততটা তোলা হয়।', 'Posts only what the opening journal does not carry yet.', 'Opening journal-এ যতটা নেই শুধু ততটা post হয়।'),
  acct: L('খাতের কোড (শুধু "আগের খাত" ও "পার্থক্য" এর জন্য)', 'Account code (only for "existing account" and "difference")', 'Account code (শুধু "existing account" ও "difference"-এর জন্য)'),
  acctHint: L('যেমন শুরুর জের এর equity খাত। ফাঁকা থাকলে মালিকের মূলধন।', 'An equity or liability account. Blank = owner capital.', 'একটা equity বা liability account। ফাঁকা = owner capital।'),
  preview: L('আগে দেখুন (dry run)', 'Preview (dry run)', 'আগে দেখুন (dry run)'), apply: L('প্রয়োগ করুন', 'Apply', 'Apply করুন'), applyGo: L('বুঝেছি, প্রয়োগ করুন', 'I understand, apply', 'বুঝেছি, apply করুন'),
  applyWarn: L('এটি খাতায় একটি এন্ট্রি লেখে (বা সিদ্ধান্ত রাখে), নিজে নিজে ফেরানো যায় না। এক জায়গায় একবারই হয়।', 'This writes a journal entry (or keeps a decision) and cannot be undone here. It happens once per place.', 'এটা খাতায় একটা entry লেখে (বা decision রাখে), এখানে থেকে ফেরানো যায় না। এক place-এ একবারই হয়।'),
  amount: L('অংক', 'Amount', 'Amount'), lines: L('লাইন', 'Lines', 'Lines'), debit: L('ডেবিট', 'Debit', 'Debit'), credit: L('ক্রেডিট', 'Credit', 'Credit'),
  w_opening_journal_has_inventory: L('শুরুর জের এ stock আগেই ধরা আছে।', 'The opening journal already carries stock.', 'Opening journal-এ stock আগেই ধরা আছে।'),
  w_switch_would_double_count: L('এই অবস্থায় শুরুর স্টক পোস্টিং সুইচ চালালে একই stock দুইবার গোনা হবে।', 'Turning the opening stock posting switch on now would count the same stock twice.', 'এখন opening stock posting switch চালালে একই stock দুইবার গোনা হবে।'),
  w_switch_on_double_count: L('শুরুর স্টক পোস্টিং সুইচ চালু, আর শুরুর জের এ stock আছে: দুইবার গোনার ঝুঁকি!', 'The opening stock posting switch is ON and the opening journal carries stock: double count risk!', 'Opening stock posting switch ON, আর opening journal-এ stock আছে: double count-এর ঝুঁকি!'),
  w_opening_journal_not_split_by_place: L('শুরুর জের জায়গা অনুযায়ী ভাগ করা নেই; তাই "পার্থক্য" পুরো কোম্পানির হিসাবে করুন।', 'The opening journal is not split by place; use "difference" for the whole company.', 'Opening journal place অনুযায়ী ভাগ করা নেই; তাই "difference" পুরো company-তে করুন।'),
  w_uncosted_openings: L('কিছু শুরুর স্টকের খরচ জানা নেই; সেগুলো ধরা হয়নি, খরচ দিলে আলাদা করে উঠবে।', 'Some opening stock has no cost; it is left out and can be posted once its cost is supplied.', 'কিছু opening stock-এর cost জানা নেই; সেগুলো ধরা হয়নি, cost দিলে আলাদা করে উঠবে।'),
  w_skip_but_not_in_opening_journal: L('বাদ দিলেন, কিন্তু শুরুর জের এ এই stock পুরোটা নেই; খাতায় stock কম থাকতে পারে।', 'You skip it, but the opening journal does not carry all of this stock; the books may show less stock.', 'Skip করছেন, কিন্তু opening journal-এ এই stock পুরোটা নেই; books-এ stock কম থাকতে পারে।'),
  w_switch_on: L('শুরুর স্টক পোস্টিং সুইচ চালু আছে; এই সিদ্ধান্তের পর ঢাকা stock সুইচ আর তুলবে না।', 'The opening stock posting switch is on; after this decision the switch no longer posts the covered stock.', 'Opening stock posting switch on আছে; এই decision-এর পর covered stock switch আর post করবে না।'),
  // cost waiting
  cwIntro: L('যে stock movement এর খরচ জানা নেই সেগুলো এখানে অপেক্ষায় থাকে। খরচ দিলে কাগজটি একবারই খাতায় উঠবে। কিছু ধরে নেওয়া হয় না।',
    'Stock movements with no known cost wait here. Once a cost is supplied the document posts once. Nothing is assumed.',
    'যে stock movement-এর cost জানা নেই সেগুলো এখানে অপেক্ষায় থাকে। Cost দিলে document একবারই খাতায় উঠবে। কিছু ধরে নেওয়া হয় না।'),
  waitN: L('টি কাগজ খরচের অপেক্ষায়', 'documents wait for a cost', 'টি document cost-এর অপেক্ষায়'), oldest: L('সবচেয়ে পুরোনো', 'Oldest', 'Oldest'), daysU: L('দিন', 'days', 'দিন'),
  alertDays: L('সতর্কতার দিন (আপনি সংখ্যা লিখবেন, ফাঁকা = সতর্কতা নেই)', 'Alert after days (you type the number, blank = no alert)', 'Alert-এর দিন (আপনি সংখ্যা লিখবেন, ফাঁকা = alert নেই)'),
  save: L('রাখুন', 'Save', 'Save'), clear: L('মুছুন', 'Clear', 'Clear'), alertOn: L('টি কাগজ সতর্কতার দিনের চেয়ে বেশি অপেক্ষায়', 'documents wait longer than the alert days', 'টি document alert-এর দিনের চেয়ে বেশি অপেক্ষায়'),
  alertOk: L('সতর্কতার দিন পার হওয়া কাগজ নেই ✓', 'No document is past the alert days ✓', 'Alert-এর দিন পার হওয়া document নেই ✓'), alertOffL: L('সতর্কতা বন্ধ (সংখ্যা দেওয়া নেই)', 'Alert is off (no number typed)', 'Alert বন্ধ (সংখ্যা দেওয়া নেই)'),
  badDays: L('সংখ্যা ঠিক নয় (০ থেকে ৩৬৫০)', 'The number is not valid (0 to 3650)', 'সংখ্যা ঠিক নয় (০ থেকে ৩৬৫০)'),
  k_wastage: L('নষ্ট / বাদ (wastage)', 'Wastage', 'Wastage'), k_production: L('উৎপাদন (ingredient)', 'Production ingredients', 'Production (ingredient)'), k_transfer: L('স্টক ট্রান্সফার', 'Stock transfer', 'Stock transfer'),
  k_purchase_return: L('কেনা ফেরত', 'Purchase return', 'Purchase return'), k_ledger: L('স্টক movement', 'Stock movement', 'Stock movement'),
  m_count_adjust: L('গণনার পার্থক্য', 'Count difference', 'Count difference'), m_opening: L('শুরুর স্টক', 'Opening stock', 'Opening stock'), m_issue_out: L('নিজের কাজে issue', 'Own-use issue', 'Own-use issue'),
  willPost: L('খরচ দিলে খাতায় উঠবে', 'Posts when costed', 'Cost দিলে post হবে'), noPost: L('এখন খাতায় উঠবে না (সুইচ বন্ধ)', 'Will not post now (switch off)', 'এখন post হবে না (switch off)'),
  ageL: L('দিন আগের', 'days old', 'দিন আগের'), supply: L('খরচ দিন', 'Supply cost', 'Cost দিন'), supplyGo: L('এই খরচ দিন', 'Supply this cost', 'এই cost দিন'),
  method: L('কোন উপায়ে', 'Method', 'Method'), m_item_average: L('গড় খরচ (average)', 'Item average cost', 'Item average cost'), m_last_purchase: L('শেষ কেনা দাম', 'Last purchase cost', 'Last purchase cost'),
  m_recipe_standard: L('রেসিপির standard খরচ', 'Recipe standard cost', 'Recipe standard cost'), m_manual: L('নিজে লিখব (কারণসহ)', 'Type it myself (with a reason)', 'নিজে লিখব (reason সহ)'),
  unitCost: L('প্রতি একক খরচ', 'Cost per unit', 'Per unit cost'), qty: L('পরিমাণ', 'Qty', 'Qty'), total: L('মোট', 'Total', 'Total'), notKnown: L('জানা নেই', 'not known', 'জানা নেই'),
  manualWhy: L('নিজে লিখলে কারণ লিখতে হবে', 'A manual cost needs a reason', 'Manual cost-এ reason লিখতে হবে'), derived: L('তৈরি পণ্যের প্রতি একক খরচও রেকর্ড হবে', 'The finished good gets a cost record too', 'তৈরি পণ্যের per unit cost-ও record হবে'),
  derivedNote: L('(stock এর গড় খরচ বদলায় না)', '(the stock average cost is not changed)', '(stock-এর average cost বদলায় না)'),
  posted: L('খাতায় উঠেছে', 'Posted to the books', 'Books-এ উঠেছে'), notPosted: L('খরচ রাখা হয়েছে; খাতায় তোলা হবে পরের posting এ (বা যিনি posting করেন তাঁর হাতে)।', 'The cost is kept; the document posts at the next posting run (by someone who posts).', 'Cost রাখা হয়েছে; document পরের posting run-এ উঠবে (যিনি post করেন তাঁর হাতে)।'),
  dup: L('এটি আগেই রাখা হয়েছে (দ্বিতীয়বার নয়)।', 'This was already recorded (not twice).', 'এটা আগেই রাখা হয়েছে (দ্বিতীয়বার নয়)।'),
  needRight: L('খরচ দেখা ও দেওয়ার অনুমতি (মালিক বা cost right) লাগবে।', 'Seeing and supplying costs needs the owner or the cost right.', 'Cost দেখা ও দেওয়ার জন্য owner বা cost right লাগবে।'),
};
const T = (k) => lab(X[k]);

/* server error codes (and Postgres / network messages) -> readable 3-language text. English has no Bangla. */
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'),
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'),
  client_id_needed: L('অনুরোধের পরিচয় নেই; আবার চেষ্টা করুন', 'The request has no id; try again', 'Request-এর id নেই; আবার try করুন'),
  bad_option: L('এই উপায়টি ঠিক নয়', 'That option is not valid', 'এই option ঠিক নয়'),
  place_needed: L('একটি জায়গা বেছে নিন', 'Choose a place', 'একটা place বেছে নিন'),
  account_needed: L('খাতের কোড দিন', 'Give the account code', 'Account code দিন'),
  bad_account: L('এই খাতটি চলবে না (equity বা liability লাগবে, stock খাত নয়)', 'That account cannot be used (it must be an equity or liability account, not a stock account)', 'এই account চলবে না (equity বা liability লাগবে, stock account নয়)'),
  bad_location: L('জায়গা ঠিক নয়', 'The place is not valid', 'Place ঠিক নয়'),
  already_applied: L('এই জায়গার জন্য আগেই সিদ্ধান্ত নেওয়া হয়েছে', 'A decision was already taken for this place', 'এই place-এর জন্য আগেই decision নেওয়া হয়েছে'),
  nothing_to_post: L('তোলার মতো শুরুর স্টক নেই', 'There is no opening stock to post', 'Post করার মতো opening stock নেই'),
  untagged_opening_inventory: L('শুরুর জের জায়গা অনুযায়ী ভাগ করা নেই; "সব জায়গা" বেছে করুন', 'The opening journal is not split by place; choose "All places"', 'Opening journal place অনুযায়ী ভাগ করা নেই; "সব place" বেছে করুন'),
  before_start: L('হিসাব শুরুর আগের তারিখ হয় না', 'The date is before the accounting start', 'Accounting start-এর আগের date হয় না'),
  bad_date: L('তারিখ ঠিক নয়', 'The date is not valid', 'Date ঠিক নয়'),
  period_closed: L('এই মাস বন্ধ; মালিকের অনুমতি লাগবে', 'This period is closed', 'এই মাস বন্ধ'),
  data_needed: L('হিসাব শুরুর তারিখ দেওয়া হয়নি; আগে Accounts পাতায় তারিখ দিন', 'The accounting start date is not set; set it on the Accounts page first', 'Accounting start date দেওয়া হয়নি; আগে Accounts পাতায় date দিন'),
  mapping_missing: L('হিসাবের খাত ঠিক করা নেই (mapping)', 'An account mapping is missing', 'Account mapping ঠিক করা নেই'),
  reason_needed: L('কারণ লিখুন', 'Write the reason', 'Reason লিখুন'),
  bad_method: L('এই উপায়টি ঠিক নয়', 'That method is not valid', 'এই method ঠিক নয়'),
  bad_kind: L('কাগজের ধরন ঠিক নয়', 'The document type is not valid', 'Document type ঠিক নয়'),
  nothing_waiting: L('এখন আর খরচের অপেক্ষায় কিছু নেই', 'Nothing waits for a cost any more', 'এখন আর cost-এর অপেক্ষায় কিছু নেই'),
  cost_unavailable: L('এই উপায়ে খরচ জানা নেই; অন্য উপায় বা নিজে লিখুন', 'No cost is known by this method; use another one or type it', 'এই method-এ cost জানা নেই; অন্য method বা নিজে লিখুন'),
  bad_manual: L('লেখা খরচ ঠিক নয় (০ এর বেশি লাগবে)', 'The typed cost is not valid (it must be above 0)', 'লেখা cost ঠিক নয় (০-র বেশি লাগবে)'),
  already_posted: L('কাগজটি আগেই খাতায় উঠে গেছে', 'The document is already in the books', 'Document আগেই books-এ উঠে গেছে'),
  bad_value: L('সংখ্যা ঠিক নয়', 'The value is not valid', 'Value ঠিক নয়'),
  'does not exist': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase96 লাগবে)', 'The server does not have this yet (phase96 is needed)', 'Server-এ এটা এখনো নেই (phase96 লাগবে)'),
  'Could not find the function': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase96 লাগবে)', 'The server does not have this yet (phase96 is needed)', 'Server-এ এটা এখনো নেই (phase96 লাগবে)'),
  'Failed to fetch': L('ইন্টারনেট নেই বা সার্ভার পাওয়া যায়নি; আবার চেষ্টা করুন', 'No internet or the server did not answer; try again', 'Internet নেই বা server পাওয়া যায়নি; আবার try করুন'),
  NetworkError: L('ইন্টারনেট নেই বা সার্ভার পাওয়া যায়নি; আবার চেষ্টা করুন', 'No internet or the server did not answer; try again', 'Internet নেই বা server পাওয়া যায়নি; আবার try করুন'),
};
const eText = (e) => {
  const m = String((e && e.message) || e || '');
  const k = Object.keys(ERR).find((x) => m.includes(x));
  return k ? lab(ERR[k]) : (m || 'error');
};

const OPTS = ['owner_capital', 'existing_account', 'skip', 'difference'];
const METHODS = ['item_average', 'last_purchase', 'recipe_standard', 'manual'];

/* state */
const D = { tab: 'ob', st: null, rules: {}, loc: '', ob: null, obRec: null, obPrev: null, obPrevOpt: null, cw: null, doc: null, docRec: null, docPrev: null, method: null, ready: false, err: null, ids: {}, msg: null };
const locs = () => (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []));
const locName = (id) => { const l = locs().find((x) => String(x.id) === String(id)); return l ? ((S.lang === 'en' ? (l.name_en || l.name_bn) : (l.name_bn || l.name_en)) || String(id)) : String(id); };
const isOwner = () => !!((D.st && D.st.owner) || (S.ctx && S.ctx.is_owner));
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };
const locArg = () => (D.loc === '' || D.loc == null ? null : Number(D.loc));
const cid = (key) => { if (!D.ids[key]) D.ids[key] = rid(); return D.ids[key]; };   // kept until the call succeeds, so a repeated tap or a retry never records twice

/* ---------- render pieces ---------- */
function tabs() {
  return `<div class="row wrap" role="tablist">${[['ob', 't_ob'], ['cw', 't_cw']].map(([k, l]) => `<button type="button" role="tab" class="mini ${D.tab === k ? 'primary' : ''}" aria-selected="${D.tab === k}" data-act="d23_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
}
function picker() {
  return `<label for="d23_loc">${esc(T('place'))}</label><div class="row"><select id="d23_loc"><option value=""${D.loc === '' ? ' selected' : ''}>${esc(T('allPlaces'))}</option>${locs().map((l) => `<option value="${esc(l.id)}"${String(l.id) === String(D.loc) ? ' selected' : ''}>${esc(S.lang === 'en' ? (l.name_en || l.name_bn) : (l.name_bn || l.name_en))}</option>`).join('')}</select><button type="button" class="mini" data-act="d23_show">${esc(T('show'))}</button></div>`;
}
const warnLine = (c) => (X['w_' + c] ? `<div class="notice warn" data-d23="warn" data-code="${esc(c)}">${esc(T('w_' + c))}</div>` : '');
function obRows() {
  const rows = ((D.ob && D.ob.rows) || []).filter((r) => r.opening_rows > 0 || r.decision || Number(r.gl_inventory) !== 0 || Number(r.valuation) !== 0);
  return rows.length ? rows.map((r) => `<div class="card stack" data-d23="obrow" data-loc="${esc(r.location_id)}"><b>${esc(locName(r.location_id))}</b>
    <div class="row between"><span class="muted">${esc(T('openVal'))}</span><b>${esc(money(r.opening_value))}</b></div>
    <div class="muted">${esc(r.opening_rows)} ${esc(T('rows'))}${r.uncosted_rows ? ' · ' + esc(r.uncosted_rows) + ' ' + esc(T('uncosted')) : ''}${Number(r.posted_by_switch) ? ' · ' + esc(T('byswitch')) + ' ' + esc(money(r.posted_by_switch)) : ''}</div>
    <div class="row between"><span class="muted">${esc(T('inJournal'))}</span><span>${esc(money(r.opening_journal_inventory))}</span></div>
    <div class="row between"><span class="muted">${esc(T('glInv'))}</span><span>${esc(money(r.gl_inventory))}</span></div>
    <div class="row between"><span class="muted">${esc(T('valuation'))}</span><span>${esc(money(r.valuation))}</span></div>
    <div class="row between"><span class="muted">${esc(T('diff'))}</span><b class="${Number(r.diff) === 0 ? '' : 'warn'}">${esc(money(r.diff))}</b></div>
    ${r.decision ? `<span class="chip" data-d23="decided">${esc(T('decided'))}: ${esc(X['o_' + r.decision] ? T('o_' + r.decision) : r.decision)}</span>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
}
function recCard() {
  const r = D.obRec; if (!r || r.data_needed) return '';
  const nm = r.numbers || {};
  return `<div class="card stack" data-d23="orec"><div class="row between"><b>${esc(T('recL'))}</b><span class="chip">${esc(T('rec'))}: ${esc(X['o_' + r.recommended] ? T('o_' + r.recommended) : r.recommended)}</span></div>
    <div class="muted">${esc(T('why'))}: ${esc(lab(r.reason || {}))}</div>
    <div class="muted">${esc(T('openVal'))} ${esc(money(nm.opening_value))} · ${esc(T('inJournal'))} ${esc(money(nm.already_in_opening_journal))}</div><div class="muted">${esc(T('recNote'))}</div></div>`;
}
function optCards() {
  const rec = D.obRec && D.obRec.recommended; const alts = (D.obRec && D.obRec.alternatives) || [];
  const own = isOwner();
  let h = `<label for="d23_acct">${esc(T('acct'))}</label><input id="d23_acct" autocomplete="off" inputmode="numeric" placeholder="${esc(T('acctHint'))}">`;
  h += OPTS.map((o) => {
    const alt = alts.find((x) => x.option === o);
    return `<div class="card stack" data-d23="opt" data-opt="${o}"><div class="row between"><b>${esc(T('o_' + o))}</b>${rec === o ? `<span class="chip" data-d23="optrec">${esc(T('rec'))}</span>` : ''}</div>
      <div class="muted">${esc(T('d_' + o))}</div>${alt && alt.possible ? `<div class="muted">${esc(T('amount'))}: ${esc(money(alt.amount))}</div>` : ''}
      <div class="row"><button type="button" class="mini" data-act="d23_oprev" data-v="${o}">${esc(T('preview'))}</button>${own ? `<button type="button" class="mini primary" data-act="d23_oapply" data-v="${o}">${esc(T('apply'))}</button>` : ''}</div></div>`;
  }).join('');
  if (!own) h += `<div class="muted">${esc(T('ownerOnly'))}</div>`;
  return h;
}
function previewBox() {
  const p = D.obPrev; if (!p) return '<div id="d23_pv"></div>';
  if (p.error) return `<div id="d23_pv" class="notice bad" data-d23="pv">${esc(eText(p.error))}</div>`;
  const ls = (p.lines || []).map((x) => `<div class="row between" data-d23="pvline"><span>${esc(x.code)} ${esc(S.lang === 'en' ? (x.name_en || x.name_bn) : (x.name_bn || x.name_en))}</span><span>${Number(x.debit) ? esc(T('debit')) + ' ' + esc(fm(x.debit)) : esc(T('credit')) + ' ' + esc(fm(x.credit))}</span></div>`).join('');
  return `<div id="d23_pv" class="card stack" data-d23="pv"><b>${esc(T('o_' + p.option))}</b><div class="muted">${esc(T('dryNote'))}</div><div>${esc(T('amount'))}: <b>${esc(money(p.amount))}</b></div>${ls}${(p.warnings || []).map(warnLine).join('')}</div>`;
}
function obTab() {
  const o = D.ob;
  let h = `<p class="muted">${esc(T('obIntro'))}</p>${picker()}`;
  if (o && o.data_needed) return h + `<div class="notice warn">${esc(lab(ERR.data_needed))}</div>`;
  if (o) {
    h += `<div class="notice ${o.risk ? 'warn' : 'ok'}" data-d23="risk">${esc(o.risk ? T('risk') : T('noRisk'))} · ${esc(T('switchL'))}: ${esc(o.switch_on ? T('on') : T('off'))}</div>`;
    h += (o.warnings || []).map(warnLine).join('');
    h += obRows();
  }
  h += recCard() + `<h3>${esc(T('lines'))}</h3>` + optCards() + previewBox();
  return h;
}
function ageChip(it) { return `<span class="chip ${it.over_alert ? 'warn' : ''}">${esc(it.age_days)} ${esc(T('ageL'))}</span>`; }
function itemsLine(it) { return (it.items || []).map((x) => `${esc(x.code)} × ${esc(x.qty)}${x.unit ? ' ' + esc(x.unit) : ''}`).join(', '); }
function cwTab() {
  const c = D.cw;
  let h = `<p class="muted">${esc(T('cwIntro'))}</p>`;
  if (D.cwErr) return h + `<div class="notice bad" data-state="error">${esc(D.cwErr)}</div>`;
  if (!c) return h;
  h += `<div class="card stack" data-d23="alertbox"><div class="muted">${esc(T('alertDays'))}</div>`;
  if (isOwner()) h += `<div class="row"><input id="d23_days" inputmode="numeric" autocomplete="off" value="${esc(c.alert_days == null ? '' : c.alert_days)}"><button type="button" class="mini" data-act="d23_daysset">${esc(T('save'))}</button><button type="button" class="mini" data-act="d23_daysclr">${esc(T('clear'))}</button></div>`;
  else h += `<b>${esc(c.alert_days == null ? '-' : c.alert_days)}</b>`;
  h += `</div>`;
  const old = c.old_count;
  h += c.alert_enabled ? (old > 0 ? `<div class="notice warn" data-d23="alert">${esc(old)} ${esc(T('alertOn'))}</div>` : `<div class="notice ok" data-d23="alert">${esc(T('alertOk'))}</div>`) : `<div class="notice" data-d23="alert">${esc(T('alertOffL'))}</div>`;
  h += `<div class="muted" data-d23="count">${esc(c.total)} ${esc(T('waitN'))} · ${esc(T('oldest'))}: ${esc(c.oldest_days)} ${esc(T('daysU'))}</div>`;
  h += (c.items || []).length ? c.items.map((it) => `<div class="card stack" data-d23="doc" data-kind="${esc(it.kind)}">
    <div class="row between"><b>${esc(T('k_' + it.kind))}${it.move && X['m_' + it.move] ? ' · ' + esc(T('m_' + it.move)) : ''}</b>${ageChip(it)}</div>
    <div class="muted">${esc(locName(it.location_id))} · ${esc(String(it.date))}</div><div>${itemsLine(it)}</div>
    <span class="chip ${it.gl_post ? '' : 'warn'}">${esc(it.gl_post ? T('willPost') : T('noPost'))}</span>
    <button type="button" class="mini primary" data-act="d23_cwopen" data-k="${esc(it.kind)}" data-r="${esc(it.ref)}">${esc(T('supply'))}</button></div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return h;
}
function body() {
  if (D.err) return `${tabs()}<div class="notice bad" data-state="error">${esc(D.err)}</div><button type="button" class="full" data-act="d23_retry">${esc(T('retry'))}</button>`;
  if (!D.ready) return `${tabs()}<p class="muted center pad" data-state="loading">${esc(T('loading'))}</p>`;
  return tabs() + (D.tab === 'ob' ? obTab() : cwTab());
}
function draw() { const el = $('#d23_body'); if (el) el.innerHTML = body(); }

/* ---------- the supply-cost sheet ---------- */
function methodCost(it, m) { return it.candidates ? (m === 'manual' ? null : it.candidates[m]) : null; }
function sheetBody() {
  const r = D.docRec; if (!r) return '';
  if (!r.ok) return `<div class="notice bad">${esc(eText(r.error || 'error'))}</div>`;
  const m = D.method;
  const its = r.items || [];
  let h = `<div class="stack"><h3>${esc(T('supply'))}: ${esc(T('k_' + D.doc.kind))}</h3><div class="muted">${esc(T('recNote'))}</div>`;
  h += its.map((it, i) => `<div class="card stack" data-d23="sitem"><b>${esc(it.code)}</b> <span class="muted">${esc(T('qty'))} ${esc(it.qty)}${it.unit ? ' ' + esc(it.unit) : ''}</span>
    <span class="chip" data-d23="irec">${esc(T('rec'))}: ${esc(T('m_' + it.recommended))}</span><div class="muted">${esc(T('why'))}: ${esc(lab(it.reason || {}))}</div>
    ${METHODS.filter((x) => x !== 'manual').map((x) => { const c = methodCost(it, x); return `<div class="row between" data-d23="mrow" data-m="${x}"><span>${esc(T('m_' + x))}</span><span>${c == null ? esc(T('notKnown')) : esc(fm(c)) + ' → ' + esc(fm(c * it.qty))}</span></div>`; }).join('')}
    ${m === 'manual' ? `<label for="d23_mc${i}">${esc(T('unitCost'))}</label><input id="d23_mc${i}" data-item="${esc(it.item_id)}" inputmode="decimal" autocomplete="off">` : ''}</div>`).join('');
  h += `<label>${esc(T('method'))}</label><div class="row wrap">${METHODS.map((x) => `<button type="button" class="mini ${m === x ? 'primary' : ''}" data-act="d23_pick" data-m="${x}">${esc(T('m_' + x))}</button>`).join('')}</div>`;
  if (m === 'manual') h += `<label for="d23_reason">${esc(T('reason'))}</label><input id="d23_reason" autocomplete="off"><div class="muted">${esc(T('manualWhy'))}</div>`;
  const p = D.docPrev;
  if (p) h += p.error || p.ok === false ? `<div class="notice warn" data-d23="spv">${esc(eText(p.error || 'error'))}${p.detail ? ': ' + esc(p.detail) : ''}</div>`
    : `<div class="notice ok" data-d23="spv">${esc(T('dryNote'))} ${esc(T('total'))}: <b>${esc(money(p.total))}</b> · ${esc(p.gl_post ? T('willPost') : T('noPost'))}${(p.derived || []).length ? '<br>' + esc(T('derived')) + ' ' + esc(T('derivedNote')) : ''}</div>`;
  h += `<div id="d23_sout" class="muted" aria-live="polite">${D.msg ? esc(D.msg) : ''}</div><div class="row"><button type="button" class="full" data-act="d23_sclose">${esc(T('close'))}</button><button type="button" class="full primary" data-act="d23_supply">${esc(T('supplyGo'))}</button></div></div>`;
  return h;
}
function manualArg() {
  const out = [];
  const items = (D.docRec && D.docRec.items) || [];
  items.forEach((it, i) => { const el = $('#d23_mc' + i); const v = nnum(el && el.value); out.push({ item_id: it.item_id, cost: Number.isFinite(v) ? v : 0 }); });
  return out;
}
async function previewNow() {
  D.docPrev = null;
  try { D.docPrev = await rpc('cost_wait_preview96', { p_kind: D.doc.kind, p_ref: D.doc.ref, p_method: D.method, p_manual: D.method === 'manual' ? manualArg() : null }); } catch (e) { D.docPrev = { error: (e && e.message) || String(e) }; }
}
function drawSheet() { openSheet(sheetBody()); }

/* ---------- loading ---------- */
async function loadRules() {
  try { const r = await sb.from('rules').select('key,value,default_value').in('key', ['acct_cost_wait_alert_days', 'acct_stock_opening']); D.rules = {}; ((r && r.data) || []).forEach((x) => { D.rules[x.key] = x; }); } catch (e) { D.rules = {}; }
}
async function loadOb() {
  D.obPrev = null;
  D.ob = await rpc('opening_stock_check96', { p_loc: locArg() });
  try { D.obRec = await rpc('opening_stock_recommend96', { p_loc: locArg() }); } catch (e) { D.obRec = null; }   // advice: a failure must not hide the numbers
}
async function loadCw() {
  D.cwErr = null;
  try { D.cw = await rpc('cost_wait_list96', { p_loc: locArg(), p_limit: 100 }); } catch (e) { D.cw = null; D.cwErr = /not allowed/.test(String((e && e.message) || e)) ? T('needRight') : eText(e); }
}
async function loadAll() {
  D.err = null;
  try { D.st = await rpc('acct_status'); } catch (e) { /* owner is also read from the session */ }
  if (D.tab === 'ob') await loadOb(); else await loadCw();
  D.ready = true;
}
async function refresh() { try { await loadAll(); } catch (e) { D.err = /not allowed/.test(String((e && e.message) || e)) ? T('needRight') : eText(e); } draw(); }

/* ---------- actions ---------- */
Object.assign(H, {
  d23_tab: async (a) => { D.tab = a.dataset.v; D.ready = false; draw(); await refresh(); },
  d23_retry: async () => { D.ready = false; D.err = null; draw(); await refresh(); },
  d23_show: async () => { D.loc = ($('#d23_loc') || {}).value || ''; D.ready = false; draw(); await refresh(); },
  d23_oprev: async (a) => {
    const o = a.dataset.v; const acct = (($('#d23_acct') || {}).value || '').trim();
    try { D.obPrev = await rpc('opening_stock_preview96', { p_option: o, p_loc: locArg(), p_account: acct || null, p_date: null }); if (D.obPrev && D.obPrev.ok === false) D.obPrev = { error: D.obPrev.error }; } catch (e) { D.obPrev = { error: (e && e.message) || String(e) }; }
    draw();
  },
  d23_oapply: (a) => {
    const o = a.dataset.v;
    openSheet(`<div class="stack"><h3>${esc(T('o_' + o))}</h3><div class="notice warn" data-d23="awarn">${esc(T('applyWarn'))}</div><div class="muted">${esc(T('d_' + o))}</div>
      <label for="d23_areason">${esc(T('reason'))}</label><input id="d23_areason" autocomplete="off"><div id="d23_aout" class="muted" aria-live="polite"></div>
      <div class="row"><button type="button" class="full" data-act="d23_sclose">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="d23_ago" data-v="${o}">${esc(T('applyGo'))}</button></div></div>`);
  },
  d23_ago: async (a) => {
    const o = a.dataset.v; const out = $('#d23_aout'); const acct = (($('#d23_acct') || {}).value || '').trim();
    const key = 'ob:' + o + ':' + (D.loc === '' ? 'all' : D.loc);
    try {
      const r = await rpc('opening_stock_apply96', { p_option: o, p_loc: locArg(), p_account: acct || null, p_date: null, p_reason: (($('#d23_areason') || {}).value || '').trim() || null, p_client: cid(key) });
      delete D.ids[key]; closeSheet(); toast(r && r.dup ? T('dup') : T('saved')); D.ready = false; draw(); await refresh();
    } catch (e) { if (out) out.textContent = eText(e); }
  },
  d23_sclose: () => { D.docRec = null; D.docPrev = null; D.msg = null; closeSheet(); },
  d23_daysset: async () => {
    const v = nnum(($('#d23_days') || {}).value);
    if (!(Number.isFinite(v) && v >= 0 && v <= 3650)) return toast(T('badDays'));
    try { await rpc('set_rule', { p_key: 'acct_cost_wait_alert_days', p_value: v }); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); }
  },
  d23_daysclr: async () => { try { await rpc('set_rule', { p_key: 'acct_cost_wait_alert_days', p_value: null }); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); } },
  d23_cwopen: async (a) => {
    D.doc = { kind: a.dataset.k, ref: a.dataset.r }; D.docRec = null; D.docPrev = null; D.msg = null; D.method = null;
    try {
      D.docRec = await rpc('cost_wait_recommend96', { p_kind: D.doc.kind, p_ref: D.doc.ref });
      const its = (D.docRec && D.docRec.items) || [];
      D.method = its.length ? its[0].recommended : 'manual';
      if (D.docRec && D.docRec.ok !== false && D.method !== 'manual') await previewNow();
    } catch (e) { D.docRec = { ok: false, error: (e && e.message) || String(e) }; }
    drawSheet();
  },
  d23_pick: async (a) => { D.method = a.dataset.m; D.msg = null; if (D.method !== 'manual') await previewNow(); else D.docPrev = null; drawSheet(); },
  d23_supply: async () => {
    if (!D.doc || !D.method) return;
    const reason = (($('#d23_reason') || {}).value || '').trim();
    if (D.method === 'manual' && !reason) { D.msg = lab(ERR.reason_needed); return drawSheet(); }
    const key = 'cw:' + D.doc.kind + ':' + D.doc.ref + ':' + D.method;
    try {
      const r = await rpc('cost_wait_supply96', { p_kind: D.doc.kind, p_ref: D.doc.ref, p_method: D.method, p_manual: D.method === 'manual' ? manualArg() : null, p_reason: reason || null, p_client: cid(key), p_post: true });
      delete D.ids[key]; D.docRec = null; D.docPrev = null; D.msg = null; closeSheet();
      toast(r && r.dup ? T('dup') : (r && r.posted ? T('posted') : T('notPosted')));
      D.ready = false; draw(); await refresh();
    } catch (e) { D.msg = eText(e); drawSheet(); }
  },
});

async function viewBooks96() {
  D.ready = false; D.err = null; D.ids = {};
  shell(T('title'), '<div id="d23_body"></div>', true);
  draw(); await loadRules(); await refresh();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { books96: viewBooks96 });
B.books96 = { X, ERR, OPTS, METHODS, eText, D, body, tabs, obTab, cwTab, sheetBody, recCard, optCards, previewBox };
})();
