/* Islamia BOS · Business assistant (#/assistant) - READ-ONLY MVP. Router + composer + chat UI. Exposes BOS.assistant.open(question?).
   How it answers (provider "local", free, default): the question is normalised (Bangla / English / Banglish, Bangla digits), matched to ONE approved
   read-only tool of web/assistant_tools.js (or a composite of several), the entities are read (period, place, top-N, item, compare), the tool runs the
   EXISTING server function with the person's own session, and the composer writes the answer from templates + the returned numbers only.
   Server functions used: report_run, report_run2, day_book, supplier_dues, needs_you_oldest, number_audit_summary, biz_staff, biz_outlook (all existing),
   and phase47: assistant_me, assistant_health, assistant_log, assistant_usage_summary, assistant_note_save / assistant_note_retire; table assistant_notes.
   Knowledge: web/data/kb.json (tools/build_kb.py) searched in the browser (BM25). Nothing is written except the usage log (no business content).
   Security: results and typed text are DATA - the router never follows instructions found in them; no SQL, no table names; no write action exists
   (rule assistant_actions_on is reserved and OFF): "do" requests get a refusal + a link to the screen. Provider "llm_proxy" is an adapter that stays
   off unless the owner deploys tools/edge/assistant-proxy.ts and switches assistant_provider; any failure falls back to local silently. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, shell, H } = A;
const L = B.L, lab = B.lab;
const AT = B.assistantTools;
const $ = (s, el = document) => el.querySelector(s);
const CFG = { timeoutMs: 8000, maxPerMinute: 20 };

// ---------- texts ----------
const X = {
  title: L('প্রশ্ন করুন (ব্যবসার সহকারী)', 'Ask (business assistant)', 'Ask (ব্যবসার সহকারী)'),
  ph: L('প্রশ্ন লিখুন… যেমন: আজ বিক্রি কত?', 'Ask… e.g. How are sales today?', 'প্রশ্ন লিখুন… যেমন: আজ sale কত?'),
  send: L('পাঠান', 'Send', 'Send'), mic: L('কথা বলে প্রশ্ন', 'Speak the question', 'Voice-এ প্রশ্ন'),
  hello: L('আমি শুধু পড়ি ও হিসাব দেখাই — কিছু বদলাই না। প্রত্যেক সংখ্যা সার্ভারের রিপোর্ট থেকে আসে; না থাকলে "তথ্য দরকার" বলি।', 'I only read and show figures - I never change anything. Every number comes from a server report; when it is missing I say "data needed".', 'আমি শুধু পড়ি — কিছু বদলাই না। প্রত্যেক number server report থেকে; না থাকলে "Data needed"।'),
  g_today: L('আজ', 'Today', 'আজ'), g_money: L('টাকা', 'Money', 'টাকা'), g_stock: L('স্টক', 'Stock', 'Stock'), g_people: L('মানুষ', 'People', 'মানুষ'), g_setup: L('সেটআপ', 'Setup', 'Setup'), g_control: L('নিয়ন্ত্রণ', 'Control', 'Control'),
  alerts: L('সতর্কতা', 'Alerts', 'Alerts'), waiting: L('অপেক্ষায়', 'waiting', 'অপেক্ষায়'), setupIssues: L('সেটআপ-সমস্যা', 'setup issues', 'setup সমস্যা'),
  off: L('সহকারী বন্ধ আছে (মালিক সুইচবোর্ডে চালু করতে পারেন)।', 'The assistant is switched off (the owner can switch it on in the Switchboard).', 'Assistant বন্ধ (owner Switchboard-এ চালু করতে পারেন)।'),
  noRight: L('আপনার জন্য সহকারী চালু নেই। মালিক "assistant_use" অনুমতি দিতে পারেন।', 'The assistant is not open for you. The owner can give the "assistant_use" right.', 'আপনার জন্য assistant চালু নেই।'),
  src: L('উৎস', 'Source', 'উৎস'), asof: L('সময়', 'As of', 'As of'), period: L('সময়কাল', 'Period', 'সময়কাল'),
  verified: L('যাচাইকৃত (সার্ভারের হিসাব)', 'Verified (computed by the server)', 'Verified (server-এর হিসাব)'), partial: L('আংশিক', 'Partial', 'আংশিক'), dataNeeded: L('তথ্য দরকার', 'Data needed', 'Data needed'),
  na: L('আপনার অনুমতিতে এটা দেখা যায় না', 'Not available with your access', 'আপনার access-এ দেখা যায় না'),
  install: L('এই অংশ এখনও বসানো হয়নি', 'Not installed yet', 'এখনও বসানো হয়নি'),
  offline: L('ইন্টারনেট নেই। সংখ্যা আনতে নেট লাগবে; সেটআপের প্রশ্নের উত্তর এখনও দিতে পারি।', 'You are offline. Figures need the internet; I can still answer setup questions.', 'Internet নেই। Number আনতে নেট লাগবে; setup প্রশ্নের উত্তর দিতে পারি।'),
  timeout: L('সার্ভার দেরি করছে — একটু পরে আবার চেষ্টা করুন।', 'The server is taking too long - try again in a moment.', 'Server দেরি করছে — পরে আবার চেষ্টা করুন।'),
  error: L('উত্তর আনা গেল না', 'Could not get the answer', 'উত্তর আনা গেল না'), dayoff: L('দৈনিক খাতা বন্ধ আছে', 'The day book is switched off', 'Day book বন্ধ'),
  range: L('সময়কাল খুব লম্বা (সর্বোচ্চ ৩৬৬ দিন)', 'The period is too long (366 days at most)', 'সময়কাল খুব লম্বা (max 366 দিন)'),
  empty: L('এই সময়ে কিছু নেই (তথ্য দরকার)', 'Nothing in this period (data needed)', 'এই সময়ে কিছু নেই (Data needed)'),
  r_write: L('আমি কিছু বদলাতে, মুছতে বা অনুমোদন দিতে পারি না — শুধু পড়ি। ঠিক পেজটি খুলে নিজে করুন:', 'I cannot change, delete or approve anything - I only read. Open the right screen and do it there:', 'আমি কিছু বদলাতে/মুছতে/approve করতে পারি না — শুধু পড়ি। ঠিক পেজ খুলুন:'),
  r_sql: L('আমি SQL, টেবিল বা ডাটাবেস দেখাই না। প্রশ্ন সাধারণ ভাষায় করুন, যেমন "আজ বিক্রি কত?"', 'I do not run or show SQL, tables or the database. Ask in plain words, e.g. "How are sales today?"', 'SQL / table / database দেখাই না। সাধারণ ভাষায় প্রশ্ন করুন।'),
  r_secret: L('পাসওয়ার্ড, পিন, টোকেন বা কোনো গোপন তথ্য আমি জানি না ও দেখাই না। পিন ভুলে গেলে মালিককে বলুন।', 'I never know or show passwords, PINs, tokens or any secret. If a PIN is forgotten, ask the owner.', 'Password / PIN / token কখনো দেখাই না।'),
  r_injection: L('এই ধরনের নির্দেশ আমি মানি না। আমার নিয়ম বদলায় না; আপনার অনুমতি অনুযায়ীই উত্তর দিই।', 'I do not follow instructions like that. My rules do not change; I answer only within your access.', 'এমন নির্দেশ মানি না; আপনার access অনুযায়ীই উত্তর দিই।'),
  r_rate: L('একটু ধীরে — এক মিনিটে অনেক প্রশ্ন হয়েছে।', 'Slow down a little - many questions in one minute.', 'একটু ধীরে — এক মিনিটে অনেক প্রশ্ন।'),
  oos: L('এটা ব্যবসার হিসাবের বাইরে। আমি বিক্রি, খরচ, বাকি, স্টক, স্টাফ ও সেটআপ নিয়ে বলতে পারি।', 'That is outside the business data. I can help with sales, expenses, dues, stock, staff and setup.', 'এটা business-এর বাইরে। Sale, খরচ, বাকি, stock, staff, setup নিয়ে বলতে পারি।'),
  clarify: L('কোনটা জানতে চান?', 'Which one do you mean?', 'কোনটা জানতে চান?'),
  exportB: L('CSV ডাউনলোড', 'Export CSV', 'CSV download'), printB: L('প্রিন্ট', 'Print', 'Print'), whyB: L('কেন?', 'Ask why', 'কেন?'), open: L('খুলুন', 'Open', 'Open'),
  noExport: L('ডাউনলোডের অনুমতি নেই (export_data)', 'You have no export right (export_data)', 'Export-এর অনুমতি নেই'), nothingToExport: L('ডাউনলোড করার মতো টেবিল নেই', 'There is no table to export', 'Export করার table নেই'),
  interp: L('ব্যাখ্যা (শুধু উপরের সংখ্যা থেকে)', 'Interpretation (only from the numbers above)', 'ব্যাখ্যা (উপরের number থেকে)'),
  calc: L('হিসাব: উপরের সার্ভার-সংখ্যার যোগ/বিয়োগ', 'Arithmetic on the server figures above', 'হিসাব: server number-এর যোগ/বিয়োগ'),
  kbFrom: L('অ্যাপের নিজের জ্ঞানভান্ডার থেকে', 'From the app’s own knowledge', 'App-এর knowledge থেকে'), kbVer: L('জ্ঞান-সংস্করণ', 'Knowledge version', 'Knowledge version'),
  kbNone: L('এ বিষয়ে জ্ঞানভান্ডারে কিছু পেলাম না।', 'I found nothing about that in the knowledge base.', 'Knowledge base-এ পেলাম না।'),
  stepDone: L('হয়েছে', 'Done', 'Done'), stepTodo: L('বাকি', 'To do', 'বাকি'), stepCheck: L('নিজে দেখুন', 'Check yourself', 'নিজে দেখুন'), stepUnknown: L('জানা নেই', 'Unknown', 'Unknown'), now: L('এখন', 'now', 'এখন'),
  approvedOwner: L('মালিকের অনুমোদিত', 'Approved by the owner', 'Owner অনুমোদিত'), noNotes: L('মালিক এখনও কোনো নিয়ম লেখেননি।', 'The owner has not written any rule yet.', 'Owner এখনও নিয়ম লেখেননি।'),
  engine: L('ইঞ্জিন: ফোনেই (বিনা খরচে)', 'Engine: on the phone (free)', 'Engine: phone-এ (free)'), engineProxy: L('ইঞ্জিন: AI প্রক্সি', 'Engine: AI proxy', 'Engine: AI proxy'),
  settings: L('সহকারীর সেটিংস ও খরচ (মালিক)', 'Assistant settings and usage (owner)', 'Assistant settings ও usage (owner)'),
  usage: L('এই মাসের ব্যবহার', 'Usage this month', 'এই মাসের usage'), questions: L('প্রশ্ন', 'questions', 'প্রশ্ন'), tokens: L('টোকেন', 'tokens', 'tokens'),
  estCost: L('আনুমানিক খরচ (শুধু AI প্রক্সিতে; অনুমান)', 'Estimated cost (AI proxy only; estimate)', 'আনুমানিক খরচ (estimate)'), budget: L('মাসিক সীমা', 'Monthly budget', 'Monthly budget'),
  proxyOff: L('AI প্রক্সি বসানো নেই — কোনো পেইড সার্ভিস চালু নেই। চালু করতে মালিকের অনুমোদন ও Edge Function লাগবে (docs/ASSISTANT.md)।', 'No AI proxy is deployed - no paid service is on. It needs the owner’s approval and an Edge Function (docs/ASSISTANT.md).', 'AI proxy বসানো নেই — কোনো paid service চালু নেই।'),
  notesT: L('মালিকের নিয়ম / পদ্ধতি / তথ্য', 'Owner rules / procedures / facts', 'Owner-এর নিয়ম / পদ্ধতি'), addNote: L('নতুন নিয়ম যোগ', 'Add a rule', 'নতুন নিয়ম'),
  nTitle: L('শিরোনাম', 'Title', 'Title'), nBn: L('বাংলায়', 'In Bangla', 'বাংলায়'), nEn: L('ইংরেজিতে', 'In English', 'English-এ'), save: L('সংরক্ষণ', 'Save', 'Save'), retire: L('বাদ দিন', 'Retire', 'Retire'),
  k_rule: L('নিয়ম', 'Rule', 'নিয়ম'), k_procedure: L('পদ্ধতি', 'Procedure', 'পদ্ধতি'), k_fact: L('তথ্য', 'Fact', 'তথ্য'), saved: L('সংরক্ষিত', 'Saved', 'Saved'),
  e_looks_like_secret: L('গোপন তথ্যের মতো দেখাচ্ছে (পাসওয়ার্ড/পিন/টোকেন) — রাখা হলো না', 'Looks like a secret (password / PIN / token) - not stored', 'Secret-এর মতো — রাখা হলো না'),
  e_title_required: L('শিরোনাম দিন', 'Write a title', 'Title দিন'), e_body_required: L('লেখা দিন', 'Write the text', 'লেখা দিন'), e_reason_required: L('কারণ লিখুন', 'Write a reason', 'কারণ লিখুন'),
  earlier: L('আগের কথোপকথন', 'Earlier in this session', 'আগের কথা'), only: L('শুধু আপনার জায়গার হিসাব', 'Only your places are included', 'শুধু আপনার জায়গা'),
  costHidden: L('খরচ ও লাভের কলাম আপনার জন্য বন্ধ', 'Cost and profit columns are hidden for your role', 'Cost/profit column বন্ধ'),
  defPeriod: L('সময় বলা হয়নি: এই মাসের শুরু থেকে আজ', 'No period given: this month to date', 'সময় বলা হয়নি: এই মাস'),
  truncated: L('৫০০-র বেশি সারি; শুধু প্রথম অংশ', 'More than 500 rows; only the first part', '৫০০-র বেশি row'),
  help1: L('আমি যা দেখাতে পারি (আপনার অনুমতি অনুযায়ী):', 'What I can show (within your access):', 'যা দেখাতে পারি:'), help2: L('যা আপনার জন্য বন্ধ:', 'Closed for you:', 'আপনার জন্য বন্ধ:'),
  help3: L('আমি কিছু লিখি না, বদলাই না, অনুমোদন দিই না; ঠিক পেজের লিংক দিই।', 'I never write, change or approve anything; I give the link to the right screen.', 'আমি কিছু লিখি/বদলাই না; লিংক দিই।'),
  vs: L('আগে', 'before', 'আগে'), highest: L('সবচেয়ে বেশি', 'Highest', 'সবচেয়ে বেশি'), lowest: L('সবচেয়ে কম', 'Lowest', 'সবচেয়ে কম'),
  total: L('মোট', 'Total', 'Total'), status: L('অবস্থা', 'Status', 'Status'), item: L('কী', 'What', 'কী'), amount: L('পরিমাণ', 'Amount', 'Amount'), now2: L('এখন', 'Now', 'এখন'), before: L('আগে', 'Before', 'আগে'), changeH: L('পরিবর্তন', 'Change', 'Change'),
  fp_cash: L('নগদ + ব্যাংক + মোবাইল', 'Cash + bank + mobile', 'Cash + bank + mobile'), fp_recv: L('গ্রাহকের কাছে পাওনা', 'Customers owe us', 'Customer-এর বাকি'), fp_pay: L('সরবরাহকারীর দেনা', 'We owe suppliers', 'Supplier দেনা'),
  fp_stock: L('স্টকের মূল্য (ক্রয়মূল্যে)', 'Stock value (at cost)', 'Stock value'), fp_pnl: L('এই মাসের লাভ (খরচ জানা অংশে)', 'Profit this month (costed part)', 'এই মাসের লাভ'), fp_bs: L('ব্যালান্স শিট (হিসাব মডিউল)', 'Balance sheet (accounting module)', 'Balance sheet'),
  fp_net: L('যাচাইকৃত লাইনগুলোর যোগ-বিয়োগ (নগদ + পাওনা + স্টক − দেনা)', 'Verified lines added up (cash + receivable + stock - payable)', 'Verified line-এর যোগফল'),
  fp_netNote: L('এটা ব্যালান্স শিট নয়: স্থায়ী সম্পদ, ঋণ ও মালিকের মূলধন ডেটায় নেই।', 'This is not a balance sheet: fixed assets, loans and owner capital are not in the data.', 'এটা balance sheet নয়।'),
  noStart: L('দৈনিক খাতার শুরুর তারিখ নেই', 'Day-book start date not set', 'Day book start date নেই'), noOpening: L('শুরুর ব্যালান্স নেই বা সব জায়গা আপনি দেখেন না', 'Opening balances not set, or you do not see every place', 'Opening balance নেই'),
  noCost: L('খরচ জানা নেই', 'No costs entered', 'Cost নেই'),
  sig: L('লক্ষণ', 'Signal', 'Signal'), noUnusual: L('এই সময়ে কোনো সতর্ক-লক্ষণ পাওয়া যায়নি (যে রিপোর্টগুলো দেখা গেল)।', 'No warning signal in this period (in the reports I could see).', 'কোনো warning signal নেই।'),
  detectors: L('এগুলো অ্যাপের বিদ্যমান ধরার নিয়ম থেকে; নতুন কোনো অনুমান-মডেল নয়।', 'These come from the app’s existing detectors - no new guessing model.', 'বিদ্যমান detector থেকে।'),
  prioNote: L('প্রস্তাবিত ক্রম (নিয়ম: আটকে থাকা কাজ ও ঝুঁকিতে থাকা টাকা আগে) — এটা ব্যাখ্যা, হিসাব নয়।', 'Suggested order (rule of thumb: blocked work and money at risk first) - interpretation, not a calculation.', 'প্রস্তাবিত ক্রম — ব্যাখ্যা।'),
  nothingPrio: L('এখন জরুরি কিছু দেখছি না।', 'Nothing urgent right now.', 'এখন জরুরি কিছু নেই।'),
  movers: L('সবচেয়ে বড় পরিবর্তন', 'Biggest movers', 'বড় পরিবর্তন'), cmpPeriod: L('তুলনার সময়', 'Compared with', 'তুলনা'),
  places: L('জায়গা', 'Places', 'Place'), unavailableParts: L('দেখা যায়নি', 'Could not see', 'দেখা যায়নি'),
};
const T = (k) => lab(X[k]);
const LG = () => S.lang || 'bn';
const isEn = () => LG() === 'en';
const lbl = (o) => (o ? (lab(o) || o.en || o.bn) : '');

// ---------- formatting (the ONLY way numbers reach the screen) ----------
const num = (v) => (v === null || v === undefined || v === '' ? null : Number(v));
const fmtN = (v, dec = 2) => { const n = num(v); return n === null || !Number.isFinite(n) ? '—' : n.toLocaleString('en-IN', { maximumFractionDigits: dec }); };
const fmtV = (v, type) => { if (v === null || v === undefined || v === '') return '—';
  if (type === 'money') { const n = num(v); return Number.isFinite(n) ? (n < 0 ? '-৳' + fmtN(-n) : '৳' + fmtN(n)) : '—'; } if (type === 'pct') return fmtN(v) + '%'; if (type === 'int') return fmtN(v, 0); if (type === 'num') return fmtN(v, 3);
  if (type === 'datetime') { try { return new Date(v).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }); } catch (e) { return String(v); } }
  return String(v); };
const MONEYK = /^(net|gross|amount|value|balance|overdue|discount|disc|due|paid|void_amt|total|cash_in|cash_out|net_cash|current|previous|change|profit|net_sales|cogs|expenses|salary|fixed|revenue|margin|short_amount|over_amount|reorder_value|no_receipt_amount|gross_pay|net_pay|adv_outstanding|amount_period|over_total|avg_bill|spend)$/;
const HEADLAB = { lines: L('লাইন', 'Lines', 'Lines'), customers: L('গ্রাহক', 'Customers', 'Customer'), no_limit_set: L('সীমা ছাড়া', 'Without a limit', 'Limit ছাড়া'), at_zero: L('শূন্যে', 'At zero', 'শূন্যে'),
  batches: L('ব্যাচ', 'Batches', 'Batch'), expired_batches: L('মেয়াদোত্তীর্ণ ব্যাচ', 'Expired batches', 'Expired batch'), suppliers: L('সরবরাহকারী', 'Suppliers', 'Supplier'), items: L('আইটেম', 'Items', 'Item'),
  unsold_items: L('অবিক্রীত আইটেম', 'Unsold items', 'Unsold item'), transfers: L('ট্রান্সফার', 'Transfers', 'Transfer'), not_received: L('পৌঁছায়নি', 'Not received', 'পৌঁছায়নি'), short_received: L('কম পৌঁছেছে', 'Short received', 'কম পৌঁছেছে'),
  findings: L('সমস্যা', 'Findings', 'Finding'), bad: L('গুরুতর', 'Serious', 'গুরুতর'), warn: L('সতর্ক', 'Warnings', 'Warning'), waiting: L('অপেক্ষায়', 'Waiting', 'অপেক্ষায়'), places: L('জায়গা', 'Places', 'Place'),
  missing_count: L('বাদ পড়া নম্বর', 'Missing numbers', 'Missing number'), forms: L('ফর্ম', 'Forms', 'Form'), total: L('মোট', 'Total', 'Total'), overdue: L('মেয়াদোত্তীর্ণ', 'Overdue', 'Overdue'),
  balance: L('মোট পাওনা', 'Total balance', 'মোট balance'), low_lines: L('কম-স্টক লাইন', 'Low lines', 'Low line') };
function colOf(res, k) { return (res.columns || []).find((c) => c.key === k); }
function headLabel(res, k) { const c = colOf(res, k); if (c) return isEn() ? (c.label_en || c.label_bn) : (c.label_bn || c.label_en); return HEADLAB[k] ? lab(HEADLAB[k]) : k; }
function headType(res, k) { const c = colOf(res, k); return c ? c.type : (MONEYK.test(k) ? 'money' : 'int'); }

// ---------- normalisation ----------
const BD = '০১২৩৪৫৬৭৮৯';
function norm(s) {
  let t = String(s || '').normalize('NFC').toLowerCase();
  t = t.replace(/[০-৯]/g, (d) => String(BD.indexOf(d)));
  t = t.replace(/য়/g, 'য়').replace(/ড়/g, 'ড়').replace(/ঢ়/g, 'ঢ়');   // য় ড় ঢ় as one form
  t = t.replace(/ী/g, 'ি').replace(/ূ/g, 'ু').replace(/[‘’`´]/g, "'").replace(/[“”]/g, '"');                      // common spelling variants
  t = t.replace(/[^\p{L}\p{M}\p{N}&%/'.\s-]/gu, ' ').replace(/([a-z])[.](\s|$)/g, '$1$2').replace(/[।?!,;:()"]/g, ' ').replace(/\s+/g, ' ').trim();
  return t;
}
const isAscii = (v) => /^[\x00-\x7f]+$/.test(v);
const reEsc = (v) => v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const CONC = {};
Object.keys(AT.CONCEPTS).forEach((k) => { CONC[k] = AT.CONCEPTS[k].map((v) => { const n = norm(v) + (/ $/.test(v) ? ' ' : ''); return isAscii(n) ? { re: new RegExp('(^|[^a-z0-9])' + reEsc(n) + "(s|es|'s)?(?=$|[^a-z0-9])") } : { s: n }; }); });
function concepts(t) { const p = ' ' + t + ' ', has = {}; Object.keys(CONC).forEach((k) => { has[k] = CONC[k].some((v) => (v.re ? v.re.test(t) : p.includes(v.s))); }); return has; }

// ---------- safety (runs before anything else; the router never executes text from data) ----------
const RX = {
  secret: /(password|passcode|pass word|passwd|পাসওয়ার্ড|পাসওয়ার্ড|পাসওয়ার্ড|otp|api ?key|secret|(access|api|auth|jwt|bearer|session|login) token|service.?role|login (details|info)|credential)/,
  pin: /(^|[^a-z])(pin|pins)([^a-z]|$)|পিন/, pinOk: /(sign|signature|সই|স্বাক্ষর|setup|set up|switch|চালু|how)/,
  sql: /(\bsql\b|select .*\bfrom\b|\bdrop table|\btables?\b.*(all|list|show|which|name)|(all|list|show|which) .*\btables?\b|\bdatabase\b|\bschema\b|\bquery\b|\bsupabase\b|\bpostgres|\bpg_|টেবিল|ডাটাবেস|ডেটাবেস|কুয়েরি|কোয়েরি)/,
  inject: /(ignore (all |the |your |any )?(previous|above|prior|earlier|system)|disregard (all|the|your|previous)|you are now|act as|pretend (to be|you)|system prompt|developer mode|jailbreak|override (your|the) (rules|instructions)|forget (your|all|the) (rules|instructions)|new instructions|আগের নির্দেশ|নির্দেশ ভুলে|নিয়ম ভুলে|নির্দেশনা উপেক্ষা)/,
  oos: /(weather|আবহাওয়া|আবহাওয়া|বৃষ্টি হবে|cricket|football|ক্রিকেট|ফুটবল|\bnews\b|খবর|joke|কৌতুক|জোকস|movie|cinema|সিনেমা|\bsong\b|গান শোনাও|poem|কবিতা|politic|রাজনীতি|bitcoin|crypto|stock market|share market|শেয়ার বাজার|শেয়ার বাজার|horoscope|রাশিফল|capital of|translate)/,
  writeVerb: /^(please |pls |plz |can you |could you |would you |kindly |now |just |go |আচ্ছা )*(delete|remove|erase|wipe|drop|truncate|cancel|void|approve|reject|update|edit|change|set|modify|create|add|insert|pay|transfer|send|refund|post|lock|unlock|grant|revoke|disable|enable|make|reset|clear|mark|turn|switch)\b(?! up)/,
  writeBn: /(মুছে|মুছ|ডিলিট|delete|অনুমোদন|approve|বাতিল|cancel|বদলে|বদলা|পরিবর্তন কর|পাঠিয়ে|পাঠিয়ে|পরিশোধ|চালু|বন্ধ|দিয়ে|দিয়ে|বসিয়ে|বসিয়ে|শূন্য|muche|batil|bodle|kore|pathiye|approve kore).{0,12}(করো|করুন|কর|দাও|দিন|ফেলো|ফেলুন|দে|koro|korun|dao|din|felo|de)\s*$/,
  how: /(how|কীভাবে|কিভাবে|kivabe|kibhabe|কোথায়|কোথায়|where|what is|কি করে|কী করে)/,
  all: /(all|every|everything|সব|সমস্ত)/,
};
function safety(t) {
  if (RX.inject.test(t)) return 'injection';
  if (RX.secret.test(t) || (RX.pin.test(t) && !RX.pinOk.test(t))) return 'secret';
  if (RX.sql.test(t)) return 'sql';
  if (!RX.how.test(t) && (RX.writeVerb.test(t) || RX.writeBn.test(t))) return 'write';
  if (RX.oos.test(t)) return 'oos';
  return null;
}
// anything that looks like a secret never reaches the screen history, the session memory or a proxy
function redact(s) {
  return String(s || '').replace(/((password|passcode|পাসওয়ার্ড|pin|পিন|otp|token)\s*(is|হলো|=|:)?\s*)\S+/gi, '$1[•••]')
    .replace(/\b(sk-[A-Za-z0-9_-]{8,}|eyJ[A-Za-z0-9_-]{10,}[A-Za-z0-9._-]*|[A-Za-z0-9_+/=-]{32,})\b/g, '[•••]').replace(/(?<![\d,.])\d{4,6}(?![\d,.])(?=.*(pin|পিন))/gi, '[•••]');
}

// ---------- entities ----------
const MONTHS = [['january', 'jan', 'জানুয়ারি'], ['february', 'feb', 'ফেব্রুয়ারি'], ['march', 'mar', 'মার্চ'], ['april', 'apr', 'এপ্রিল'], ['may', null, 'মে'], ['june', 'jun', 'জুন'], ['july', 'jul', 'জুলাই'],
  ['august', 'aug', 'আগস্ট'], ['september', 'sep', 'সেপ্টেম্বর'], ['october', 'oct', 'অক্টোবর'], ['november', 'nov', 'নভেম্বর'], ['december', 'dec', 'ডিসেম্বর']].map((m) => m.map((x) => (x ? norm(x) : x)));
const validDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !isNaN(new Date(s + 'T00:00:00Z')) && new Date(s + 'T00:00:00Z').toISOString().slice(0, 10) === s;
const pad2 = (n) => String(n).padStart(2, '0');
function period(t) {
  const p = ' ' + t + ' ', td = AT.today();
  const ds = []; let m;
  const re1 = /(\d{4})-(\d{1,2})-(\d{1,2})/g; while ((m = re1.exec(t))) ds.push(`${m[1]}-${pad2(m[2])}-${pad2(m[3])}`);
  const re2 = /(^|[^\d])(\d{1,2})[/.](\d{1,2})[/.](\d{4})/g; while ((m = re2.exec(t))) ds.push(`${m[4]}-${pad2(m[3])}-${pad2(m[2])}`);
  const ok = ds.filter(validDate).sort();
  if (ok.length >= 2) return { from: ok[0], to: ok[ok.length - 1], label: ok[0] + ' → ' + ok[ok.length - 1] };
  if (ok.length === 1) return { from: ok[0], to: ok[0], label: ok[0] };
  for (let i = 0; i < 12; i++) {
    const [full, short, bn] = MONTHS[i]; const ym = t.match(/(20\d{2})/); const year = ym ? Number(ym[1]) : null;
    const hit = new RegExp('(^|[^a-z])(' + full + (short ? '|' + short : '') + ')([^a-z]|$)').test(t) && (full !== 'may' || year || /\bin may\b|may (sales|month|এ)/.test(t)) || (bn && (bn === 'মে' ? (p.includes(' মে ') || p.includes(' মে মাস')) && (year || p.includes('মাস')) : p.includes(bn)));
    if (hit) {
      let y = year || Number(td.slice(0, 4)); if (!year && i + 1 > Number(td.slice(5, 7))) y -= 1;
      const from = `${y}-${pad2(i + 1)}-01`; const last = new Date(Date.UTC(y, i + 1, 0)).toISOString().slice(0, 10);
      return { from, to: last > td ? td : last, label: from.slice(0, 7) };
    }
  }
  const nd = t.match(/(last|past|previous|গত|শেষ|goto|gato)\s*(\d{1,3})\s*(days|day|দিন|din)/);
  if (nd) { const n = Math.min(Math.max(Number(nd[2]), 1), 366); if (n === 7) return { preset: 'last_7' }; if (n === 30) return { preset: 'last_30' }; return { from: AT.addDays(td, -(n - 1)), to: td, label: 'last ' + n + ' days' }; }
  const has = (arr) => arr.some((v) => (isAscii(v) ? new RegExp('(^|[^a-z])' + reEsc(v) + '([^a-z]|$)').test(t) : p.includes(v)));
  if (has(['yesterday', 'gotokal', 'gatokal', 'goto kal', 'গতকাল', 'গতকালের', 'কালকের', 'gotokaler'])) return { preset: 'yesterday' };
  if (has(['last week', 'previous week', 'goto soptah', 'goto saptah', 'গত সপ্তাহ', 'আগের সপ্তাহ'])) return { preset: 'last_week' };
  if (has(['this week', 'ei soptah', 'ei saptah', 'এই সপ্তাহ', 'চলতি সপ্তাহ', 'week to date'])) return { preset: 'this_week' };
  if (has(['last month', 'previous month', 'goto mash', 'gotomash', 'goto mas', 'গত মাস', 'আগের মাস', 'গত মাসে', 'গত মাসের'])) return { preset: 'last_month' };
  if (has(['this month', 'ei mash', 'ei mas', 'এই মাস', 'চলতি মাস', 'month to date', 'mtd'])) return { preset: 'this_month' };
  if (has(['last year', 'previous year', 'last fiscal year', 'গত বছর', 'আগের বছর', 'গত অর্থবছর'])) return { preset: 'last_fy' };
  if (has(['this year', 'fiscal year', 'this fy', 'ei bochor', 'এই বছর', 'চলতি বছর', 'অর্থবছর', 'year to date', 'ytd'])) return { preset: 'this_fy' };
  if (has(['today', 'todays', 'aaj', 'aj', 'ajke', 'ajker', 'আজ', 'আজকে', 'আজকের', 'এখন পর্যন্ত'])) return { preset: 'today' };
  return null;
}
function topN(t) { const m = t.match(/(top|best|worst|bottom|first|lowest|highest|সেরা|শীর্ষ|প্রথম|শেষ)\s*(\d{1,3})/) || t.match(/(\d{1,3})\s*(টি|টা|ta|ti|items|item|products|জন|customers|suppliers)/); return m ? Math.min(Math.max(Number(m[2] && /^\d+$/.test(m[2]) ? m[2] : m[1]), 1), 50) : null; }
let LOCIDX = null;
function locIndex() {
  const ls = (B.ENV && B.ENV.locs) || []; if (LOCIDX && LOCIDX.n === ls.length) return LOCIDX.a;
  const generic = new Set(AT.CONCEPTS.branch.map(norm).concat(['islamia', 'ইসলামিয়া', 'ইসলামিয়া', 'misty', 'mishti', 'মিষ্টি', 'ghar', 'ঘর']));
  const a = ls.map((l) => { const al = new Set();
    [l.name_bn, l.name_en, l.name_mix, l.code].filter(Boolean).forEach((x) => { const n = norm(x); al.add(n); const parts = n.split(' ').filter((w) => !generic.has(w)); if (parts.length && parts.join(' ').length >= 3) al.add(parts.join(' ')); });
    const cd = String(l.code || '').toLowerCase().match(/^([a-z_]+?)_?(\d+)$/); if (cd) { const d = cd[2]; ['branch ' + d, 'branch-' + d, 'shakha ' + d, 'শাখা ' + d, d + 'য় শাখা', d + 'nd branch', d + 'nd shop', 'shop ' + d].forEach((x) => al.add(norm(x))); }
    if (String(l.code) === 'main') ['main', 'মেইন', 'প্রধান', 'main shop', 'main branch'].forEach((x) => al.add(x));
    return { id: Number(l.id), al: [...al].filter((x) => x.length >= 3 && !generic.has(x)) }; });
  LOCIDX = { n: ls.length, a }; return a;
}
function locsIn(t) { const p = ' ' + t + ' '; const out = []; locIndex().forEach((l) => { if (l.al.some((x) => (isAscii(x) ? new RegExp('(^|[^a-z0-9])' + reEsc(x) + '([^a-z0-9]|$)').test(t) : p.includes(x)))) out.push(l.id); }); return out; }
function itemsIn(t) {
  const its = (B.ENV && B.ENV.items) || []; if (!its.length) return [];
  const stop = new Set(Object.values(AT.CONCEPTS).flat().map(norm)); const hits = [];
  for (const it of its) { for (const nmx of [it.name_bn, it.name_en]) { const n = norm(nmx || ''); if (n.length < 3 || stop.has(n)) continue; if ((isAscii(n) ? new RegExp('(^|[^a-z0-9])' + reEsc(n) + '([^a-z0-9]|$)').test(t) : t.includes(n))) { hits.push([it.id, n.length]); break; } } }
  return hits.sort((a, b) => b[1] - a[1]).slice(0, 3).map((h) => h[0]);
}
function understand(raw) {
  const t = norm(raw); const has = concepts(t);
  const ent = { period: period(t), locs: locsIn(t), topN: topN(t), items: itemsIn(t), compare: has.change && /(vs|versus|compare|compared|comparison|তুলনা|সাথে|than)/.test(t), worst: has.worst };
  return { t, has, ent };
}

// ---------- the router ----------
const nonTopic = new Set(['today', 'report', 'top', 'worst', 'help']);
function score(has) {
  const out = [];
  for (const it of AT.INTENTS) {
    if (!it.req.every((c) => has[c])) continue; if (it.no.some((c) => has[c])) continue;
    out.push({ it, s: 10 * it.req.length + it.opt.filter((c) => has[c]).length + it.base });
  }
  return out.sort((a, b) => b.s - a.s);
}
const FOLLOW = /^(and|what about|how about|only|just|same for|now|then|আর|শুধু|কেবল|এবার|তাহলে|আর\s|ar\s|shudhu)/;
function route(raw, ctx, me) {
  const t0 = String(raw || '').trim(); if (!t0) return { kind: 'empty' };
  const U = understand(t0), t = U.t, has = U.has, ent = U.ent; ctx = ctx || {};
  const sf = safety(t); if (sf === 'oos') return { kind: 'out_of_scope' }; if (sf) return { kind: 'refuse', reason: sf, links: sf === 'write' ? writeLinks(has) : [] };
  if (/(^|\s)(export|csv|download|ডাউনলোড|এক্সপোর্ট|excel)(\s|$)/.test(t) && ctx.last) return { kind: 'export' };
  if (/(^|\s)(print|প্রিন্ট|ছাপ)/.test(t) && ctx.last) return { kind: 'print' };
  if (has.setup && !has.health) return { kind: 'kb', q: t };
  const sc = score(has); const best = sc[0];
  const params = { period: ent.period, locs: ent.locs, topN: ent.topN, items: ent.items, compare: !!ent.compare, worst: !!ent.worst, q: t };
  const why = /(^|\s)(why|keno|কেন)(\s|$)/.test(t);
  const topicCount = Object.keys(has).filter((k) => has[k] && !nonTopic.has(k)).length;
  // follow-ups: no new subject, only a period / place / top-N / "why" -> reuse the last tool (memory)
  if (ctx.last && (topicCount === 0 || (FOLLOW.test(t) && (!best || best.s < 20))) && (why || ent.period || ent.locs.length || ent.topN || ent.compare || FOLLOW.test(t))) {
    if (why) return plan('what_changed', merge(ctx.last.params, params, true), 'what_changed', true);
    return plan(ctx.last.tool, merge(ctx.last.params, params), ctx.last.intent, true);
  }
  if (!best) {
    if (why && ctx.last) return plan('what_changed', merge(ctx.last.params, params, true), 'what_changed', true);
    if (ent.locs.length) return plan('sales_summary', params, 'sales');
    if (has.report || has.cost || has.value) return { kind: 'clarify', options: clarifyOptions(has) };
    if (has.help) return plan('help', params, 'help');
    return { kind: 'out_of_scope' };
  }
  const second = sc.find((x) => x.it.tool !== best.it.tool);
  if (second && second.s === best.s) return { kind: 'clarify', options: [best.it.tool, second.it.tool].map((k) => optionFor(k)) };
  if (has.cost && !has.expense && !has.profit && best.it.tool === 'expenses_by_head') return { kind: 'clarify', options: clarifyOptions(has) };
  let tool = best.it.tool;
  // one named place and no ranking -> that place's own sales summary
  if (tool === 'sales_by_location' && ent.locs.length === 1 && !has.worst && !has.top && !ent.compare) tool = 'sales_summary';
  // "what changed compared to last month" = this period against the previous one
  if (tool === 'what_changed' && params.period && /(compared|than|vs|versus|তুলনায়|চেয়ে|চেয়ে|থেকে|সাথে)/.test(t)) { const sh = { last_month: 'this_month', last_week: 'this_week', yesterday: 'today', last_fy: 'this_fy' }[params.period.preset]; if (sh) params.period = { preset: sh }; }
  return plan(tool, params, best.it.intent);
}
function merge(a, b, keepPeriod) { const m = Object.assign({}, a || {}); ['period', 'compare', 'worst'].forEach((k) => { if (b[k]) m[k] = b[k]; }); if (b.locs && b.locs.length) m.locs = b.locs; if (b.topN) m.topN = b.topN; if (b.items && b.items.length) m.items = b.items; m.q = b.q; if (keepPeriod && !b.period) m.period = (a || {}).period; return m; }
function plan(tool, params, intent, follow) {
  const tl = AT.TOOLS[tool], cp = AT.COMPOSITE[tool];
  const p = Object.assign({}, params);
  if (tl && !tl.nodate && !p.period) p.period = { preset: tl.defPeriod || 'this_month' };
  if (cp && !p.period && tool !== 'help' && tool !== 'notes') p.period = { preset: tool === 'priorities' ? 'today' : 'this_month' };
  return { kind: cp ? 'composite' : 'tool', tool, intent: intent || tool, params: p, follow: !!follow };
}
function optionFor(k) { const tl = AT.TOOLS[k] || AT.COMPOSITE[k]; return { tool: k, label: tl ? lbl(tl.title) : k }; }
function clarifyOptions(has) { const o = has.cost ? ['expenses_by_head', 'item_margin', 'purchases_by_supplier'] : ['sales_summary', 'expenses_by_head', 'receivables', 'stock_low']; return o.map(optionFor); }
function writeLinks(has) {
  const r = []; const add = (route, l) => { if (!r.some((x) => x.route === route)) r.push({ route, label: l }); };
  if (has.sales || has.void) add('pos', L('বিক্রি (POS)', 'Sales (POS)', 'Sale (POS)')); if (has.attention || has.discount) add('pending', L('অপেক্ষমাণ', 'Pending', 'Pending'));
  if (has.item || has.stock) add('items', L('আইটেম ও দাম', 'Items & prices', 'Item ও price')); if (has.pay || has.supplier) add('payables', L('সরবরাহকারীর পাওনা', 'Supplier payables', 'Supplier payable'));
  if (has.staff || has.salary) add('staff', L('স্টাফ', 'Staff', 'Staff'));
  if (!r.length) add('switchboard', L('সুইচবোর্ড', 'Switchboard', 'Switchboard'));
  return r;
}

// ---------- running tools: own session, cache, timeout, honest errors ----------
const CACHE = new Map();
const err = (code, message) => Object.assign(new Error(message || code), { code });
function classify(e) {
  const m = String((e && (e.message || e.details || e.hint)) || e || ''); const c = String((e && e.code) || '');
  if (/not allowed|permission|denied|row-level|42501|not_allowed/i.test(m) || c === '42501') return err('access', m);
  if (/could not find the function|does not exist|PGRST202|unknown_report|schema cache/i.test(m) || c === 'PGRST202' || c === '42883') return err('install', m);
  if (/daybook_off/.test(m)) return err('off', m);
  if (/bad_range/.test(m)) return err('range', m);
  if (/failed to fetch|networkerror|network request|load failed|offline/i.test(m)) return err('offline', m);
  return err('error', m);
}
function mkX(me) {
  return { me, call: async (fn, args) => {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) throw err('offline');
    const key = fn + '|' + JSON.stringify(args || {}); const ttl = Math.max(0, Number(me.cache_seconds == null ? 60 : me.cache_seconds)) * 1000; const hit = CACHE.get(key);
    if (hit && Date.now() - hit.at < ttl) return hit.data;
    let timer; const to = new Promise((_, rej) => { timer = setTimeout(() => rej(err('timeout')), CFG.timeoutMs); });
    let r; try { r = await Promise.race([sb.rpc(fn, args || {}), to]); } catch (e) { clearTimeout(timer); throw e.code ? e : classify(e); }
    clearTimeout(timer);
    if (!r || r.error) throw classify(r && r.error);
    CACHE.set(key, { at: Date.now(), data: r.data }); return r.data;
  } };
}
async function runTool(key, params, me) {
  const tl = AT.TOOLS[key]; if (!tl) return { ok: false, code: 'install', key };
  const n = tl.needs(me); if (n !== true) return { ok: false, code: n, key };
  try { const res = await tl.run(sanitize(tl, params), mkX(me)); return Object.assign({ key }, res); } catch (e) { return { ok: false, code: e.code || 'error', message: e.message, key }; }
}
// only whitelisted, typed parameters ever reach a tool (also for anything an AI proxy might propose)
const PRESETS = ['today', 'yesterday', 'last_7', 'last_30', 'this_month', 'last_month', 'this_week', 'last_week', 'this_fy', 'last_fy'];
function sanitize(tl, p) {
  p = p || {}; const o = {}; const allow = new Set(tl.params || []);
  if (!tl.nodate && p.period) { if (p.period.preset && PRESETS.includes(p.period.preset)) o.period = { preset: p.period.preset };
    else if (validDate(p.period.from || '') && validDate(p.period.to || p.period.from || '')) { const f = p.period.from, t = p.period.to || p.period.from; if (t >= f && (new Date(t) - new Date(f)) / 864e5 <= 365) o.period = { from: f, to: t }; } }
  if (!tl.nodate && !o.period) o.period = { preset: tl.defPeriod || 'this_month' };
  const known = new Set(((B.ENV && B.ENV.locs) || []).map((l) => Number(l.id)));
  if (allow.has('locs') && Array.isArray(p.locs)) o.locs = p.locs.map(Number).filter((x) => Number.isInteger(x) && known.has(x)).slice(0, 20);
  if (allow.has('topN') && p.topN) o.topN = Math.min(Math.max(parseInt(p.topN, 10) || 10, 1), 50);
  if (allow.has('items') && Array.isArray(p.items)) { const ids = new Set(((B.ENV && B.ENV.items) || []).map((i) => i.id)); o.items = p.items.filter((x) => ids.has(x)).slice(0, 20); }
  if (allow.has('compare')) o.compare = !!p.compare; if (allow.has('worst')) o.worst = !!p.worst;
  if (allow.has('names') && typeof p.q === 'string') o.q = p.q.slice(0, 300);
  return o;
}

// ---------- composer: answers from templates + the returned numbers only ----------
const periodLabel = (res, p) => { const pr = (res && res.period) || null; if (pr && pr.from) return pr.from === pr.to ? pr.from : pr.from + ' → ' + pr.to; if (p && p.period) { const [f, t] = AT.periodDates(p.period); return f === t ? f : f + ' → ' + t; } return ''; };
const locLabel = (p) => (p && p.locs && p.locs.length ? p.locs.map((id) => AT.locName(id)).join(', ') : '');
function labelOf(row, k) {
  if (!row || !k) return '';
  const pairs = { location: ['location_bn', 'location_en', 'location'], item: ['item_name', 'item_name_en', 'item_bn'], head: ['head_bn', 'head_en', 'head'], reason: ['reason_bn', 'reason_en', 'reason'] };
  const pr = pairs[k]; if (pr) { const v = isEn() ? (row[pr[1]] || row[pr[0]] || row[pr[2]]) : (row[pr[0]] || row[pr[2]] || row[pr[1]]); return v == null ? '' : String(v); }
  const v = row[k]; return v == null ? '' : String(v);
}
function noteText(n) {
  const c = n && n.code; if (c === 'location_scope') return T('only'); if (c === 'cost_hidden') return T('costHidden'); if (c === 'default_period') return T('defPeriod'); if (c === 'truncated') return T('truncated');
  if (c === 'no_data') return T('empty'); if (n && (n.text_en || n.text_bn)) return isEn() ? (n.text_en || n.text_bn) : (n.text_bn || n.text_en); return null;
}
function statusOf(res) { if (!res || !res.ok) return 'na'; if (res.dataNeeded) return 'data_needed'; if ((res.notes || []).some((n) => n.code === 'cost_hidden' || n.code === 'truncated')) return 'partial'; return 'verified'; }
function failText(res) { const c = res && res.code; return c === 'access' ? T('na') : c === 'install' ? T('install') : c === 'offline' ? T('offline') : c === 'timeout' ? T('timeout') : c === 'off' ? T('dayoff') : c === 'range' ? T('range') : T('error') + (res && res.message ? ' · ' + String(res.message).slice(0, 80) : ''); }
function visibleCols(res) {
  const cs = res.columns || []; const keys = new Set(cs.map((c) => c.key));
  return cs.filter((c) => { if (c.type === 'id') return false; const k = c.key;
    if (/_en$/.test(k) && (keys.has(k.replace(/_en$/, '_bn')) || keys.has(k.replace(/_en$/, '')))) return isEn();
    if (/_bn$/.test(k) && keys.has(k.replace(/_bn$/, '_en'))) return !isEn();
    if (!/_(bn|en)$/.test(k) && keys.has(k + '_en')) return !isEn();
    return true; }).slice(0, 7);
}
function cardForTool(tl, res, p) {
  const title = lbl(tl.title);
  if (!res.ok) return { title, status: 'na', summary: failText(res), links: tl.link ? [{ route: tl.link, label: title }] : [], tools: [tl.key], ok: false, code: res.code };
  const parts = []; const tot = res.totals || {}; const d = (res.compare && res.compare.delta) || {};
  (tl.head || []).forEach((k) => { if (tot[k] === undefined || tot[k] === null) return; let s = headLabel(res, k) + ': ' + fmtV(tot[k], headType(res, k));
    if (d[k] && d[k].previous !== undefined && d[k].previous !== null) s += ' (' + T('vs') + ' ' + fmtV(d[k].previous, headType(res, k)) + (d[k].pct !== null && d[k].pct !== undefined ? ', ' + (Number(d[k].pct) > 0 ? '+' : '') + fmtN(d[k].pct) + '%' : '') + ')';
    parts.push(s); });
  const rows = res.rows || []; const n = p.topN || (tl.label ? 10 : 50);
  if (tl.label && tl.value && rows.length) {
    const f = rows[0], lst = rows[rows.length - 1], vt = headType(res, tl.value);
    if (rows.length > 1 && !tl.chart) parts.push((p.worst ? T('lowest') : T('highest')) + ': ' + labelOf(f, tl.label) + ' ' + fmtV(f[tl.value], vt) + (rows.length > 2 && !res.hasMore ? ' · ' + (p.worst ? T('highest') : T('lowest')) + ': ' + labelOf(lst, tl.label) + ' ' + fmtV(lst[tl.value], vt) : ''));
    else if (rows.length === 1 && !(tl.head || []).length) parts.push(labelOf(f, tl.label) + ' ' + fmtV(f[tl.value], vt));
  }
  if (res.key === 'cash_position' && res.dataNeeded) parts.push(T('dataNeeded') + ': ' + (res.needWhy === 'no_start' ? T('noStart') : T('noOpening')));
  let rws = rows; if (tl.params.includes('names') && p.q) { const named = rows.filter((r) => { const nmx = norm(r.name || r.customer_name || ''); return nmx.length >= 3 && (' ' + p.q + ' ').includes(nmx); }); if (named.length) rws = named; }
  const notes = (res.notes || []).map(noteText).filter(Boolean);
  const summary = parts.length ? parts.join(' · ') : (res.dataNeeded || !rows.length ? T('empty') : '');
  const cols = visibleCols(res);
  const card = { title, summary, status: statusOf(res), period: tl.nodate ? '' : periodLabel(res, p), loc: locLabel(p), notes, tools: [tl.key], ok: true,
    table: rws.length ? { columns: cols, rows: rws.slice(0, n), all: rws } : null, source: res.source, asOf: res.asOf, links: [], findings: res.findings || null };
  if (res.compare && res.compare.from) card.cmp = res.compare.from + ' → ' + res.compare.to;
  if (tl.link) card.links.push({ route: tl.link, label: title });
  if (res.rowLinks && rws.length) rws.slice(0, 6).forEach((r) => { if (r.route) card.links.push({ route: r.route, label: r.label || r.title || r.route }); });
  if (tl.label && tl.value && rws.length > 1) card.chart = { type: tl.chart || 'bar', points: rws.slice(0, tl.chart === 'line' ? 62 : 12).map((r) => ({ l: labelOf(r, tl.label), v: num(r[tl.value]) })).filter((x) => x.v !== null), vtype: headType(res, tl.value) };
  if (res.interpretationOnly) card.notes.push(lbl(L('সার্ভারের সাধারণ গড় থেকে; নিশ্চিত হিসাব নয়।', 'From the server’s simple average; not a certain figure.', 'Server-এর গড় থেকে।')));
  if (res.derived && res.derived.length) card.notes.push(T('calc') + ' (' + res.derived.map((k) => headLabel(res, k)).join(', ') + ')');
  return card;
}

// ---------- composite answers ----------
async function composite(key, p, me) {
  const cp = AT.COMPOSITE[key];
  if (key === 'help') return helpCard(me);
  if (key === 'notes') return notesCard();
  if (key === 'fin_position') return finPosition(p, me);
  if (key === 'what_changed') return whatChanged(p, me);
  if (key === 'unusual') return unusual(p, me);
  if (key === 'priorities') return priorities(p, me);
  return { title: lbl(cp.title), summary: T('install'), status: 'na' };
}
function factRow(label, value, type, st, src, why) { return { item: label, amount: value === null || value === undefined ? null : value, _type: type || 'money', status: st, source: src || '', why: why || '' }; }
const ST = (s) => (s === 'verified' ? T('verified') : s === 'partial' ? T('partial') : s === 'data_needed' ? T('dataNeeded') : s === 'install' ? T('install') : T('na'));
async function finPosition(p, me) {
  const tm = { period: { preset: 'this_month' } };
  const keys = ['cash_position', 'receivables', 'payables', 'stock_value', 'pnl'].concat(AT.TOOLS.acc_balance_sheet.needs(me) === true ? ['acc_balance_sheet'] : []);
  const rs = await Promise.all(keys.map((k) => runTool(k, k === 'pnl' ? tm : Object.assign({}, p, { period: null }), me))); const R = {}; keys.forEach((k, i) => { R[k] = rs[i]; });
  const rows = [], ver = {};
  const line = (k, label, val, src, missingWhy) => { const r = R[k]; let st, v = null, why = '';
    if (!r || !r.ok) { st = r && r.code === 'install' ? 'install' : 'na'; why = r ? failText(r) : ''; }
    else if (val(r) === null || val(r) === undefined) { st = 'data_needed'; why = missingWhy ? missingWhy(r) : T('dataNeeded'); }
    else { st = 'verified'; v = num(val(r)); ver[k] = v; }
    rows.push(factRow(label, v, 'money', st, src, why)); };
  line('cash_position', T('fp_cash'), (r) => (r.totals ? r.totals.total : null), 'day_book', (r) => (r.needWhy === 'no_start' ? T('noStart') : T('noOpening')));
  line('receivables', T('fp_recv'), (r) => (r.totals ? r.totals.balance : null), 'report customer_dues');
  line('payables', T('fp_pay'), (r) => (r.totals ? r.totals.balance : null), 'supplier_dues');
  line('stock_value', T('fp_stock'), (r) => (r.totals && r.totals.value !== null && r.totals.value !== undefined ? r.totals.value : null), 'report stock_balance', () => (me.cost ? T('noCost') : T('na')));
  line('pnl', T('fp_pnl'), (r) => (r.totals ? r.totals.profit : null), 'report l1_pnl');
  if (R.acc_balance_sheet) { const r = R.acc_balance_sheet; rows.push(factRow(T('fp_bs'), null, 'text', r.ok ? 'verified' : (r.code === 'install' ? 'install' : 'na'), 'balance_sheet', r.ok ? (r.rows || []).slice(0, 6).map((x) => x.k + ' ' + fmtN(x.v)).join(' · ') : failText(r))); }
  else rows.push(factRow(T('fp_bs'), null, 'text', 'install', 'phase40', T('install')));
  const allV = ['cash_position', 'receivables', 'payables', 'stock_value'].every((k) => ver[k] !== undefined);
  const s = []; rows.filter((r) => r.status === 'verified' && r.amount !== null).forEach((r) => s.push(r.item + ': ' + fmtV(r.amount, 'money')));
  const notes = [];
  if (allV) { const net = Math.round((ver.cash_position + ver.receivables + ver.stock_value - ver.payables) * 100) / 100; rows.push(factRow(T('fp_net'), net, 'money', 'verified', T('calc'))); notes.push(T('fp_netNote')); }
  const missing = rows.filter((r) => r.status !== 'verified').map((r) => r.item + ' (' + ST(r.status) + ')');
  if (missing.length) notes.push(T('unavailableParts') + ': ' + missing.join(', '));
  const cols = [{ key: 'item', label_bn: 'কী', label_en: 'What', type: 'text' }, { key: 'amount', label_bn: 'টাকা', label_en: 'Amount', type: 'money' }, { key: 'status_t', label_bn: 'অবস্থা', label_en: 'Status', type: 'text' }, { key: 'source', label_bn: 'উৎস', label_en: 'Source', type: 'text' }];
  const trows = rows.map((r) => Object.assign({}, r, { status_t: ST(r.status) + (r.why ? ' · ' + r.why : '') }));
  return { title: lbl(AT.COMPOSITE.fin_position.title), summary: s.join(' · ') || T('dataNeeded'), status: rows.every((r) => r.status === 'verified') ? 'verified' : (s.length ? 'partial' : 'data_needed'),
    period: AT.today(), table: { columns: cols, rows: trows, all: trows }, notes, tools: keys, ok: true, links: [{ route: 'daybook', label: lbl(L('দৈনিক খাতা', 'Day book', 'Day book')) }, { route: 'dues', label: lbl(L('বাকি', 'Dues', 'Dues')) }, { route: 'payables', label: lbl(L('দেনা', 'Payables', 'Payable')) }], source: { kind: 'composite', name: 'fin_position' } };
}
function pctCalc(cur, prev) { if (prev === null || prev === undefined || Number(prev) === 0) return null; return Math.round(10000 * (cur - prev) / Math.abs(prev)) / 100; }
async function whatChanged(p, me) {
  const pc = Object.assign({}, p, { compare: true, topN: 50 });
  const [loc, items, exp] = await Promise.all([runTool('sales_by_location', pc, me), runTool('top_items', pc, me), runTool('expense_trend', p, me)]);
  const facts = [], movers = [], interp = []; let cmpLbl = '';
  if (loc.ok && loc.compare && loc.compare.delta && loc.compare.delta.net) {
    const dn = loc.compare.delta.net; cmpLbl = loc.compare.from + ' → ' + loc.compare.to;
    facts.push(lbl(L('নিট বিক্রি', 'Net sales', 'Net sale')) + ': ' + fmtV(dn.current, 'money') + ' (' + T('vs') + ' ' + fmtV(dn.previous, 'money') + (dn.pct !== null && dn.pct !== undefined ? ', ' + (dn.pct > 0 ? '+' : '') + fmtN(dn.pct) + '%' : '') + ')');
    const prev = new Map((loc.compare.rows || []).map((r) => [String(r.location_id), num(r.net)]));
    const lm = (loc.rows || []).map((r) => { const pv = prev.has(String(r.location_id)) ? prev.get(String(r.location_id)) : 0; const cu = num(r.net) || 0; return { what: labelOf(r, 'location'), now: cu, before: pv, change: Math.round((cu - pv) * 100) / 100, pct: pctCalc(cu, pv) }; });
    (loc.compare.rows || []).forEach((r) => { if (!(loc.rows || []).some((x) => String(x.location_id) === String(r.location_id))) lm.push({ what: labelOf(r, 'location'), now: 0, before: num(r.net) || 0, change: -(num(r.net) || 0), pct: -100 }); });
    lm.sort((a, b) => Math.abs(b.change) - Math.abs(a.change)); movers.push(...lm.slice(0, 5).map((m) => Object.assign({ kind: T('places') }, m)));
    if (lm.length && dn.previous !== null && Number(dn.current) !== Number(dn.previous)) { const top = lm[0]; interp.push(lbl(L('বিক্রি', 'Sales', 'Sale')) + ' ' + (dn.pct !== null && dn.pct !== undefined ? (dn.pct > 0 ? '+' : '') + fmtN(dn.pct) + '%' : '') + ': ' + lbl(L('সবচেয়ে বড় পরিবর্তন', 'the biggest change is', 'বড় পরিবর্তন')) + ' ' + top.what + ' ' + (top.change > 0 ? '+' : '') + fmtV(top.change, 'money') + (top.pct !== null ? ' (' + (top.pct > 0 ? '+' : '') + fmtN(top.pct) + '%)' : '')); }
  }
  if (items.ok && items.compare) {
    const prev = new Map((items.compare.rows || []).map((r) => [String(r.item_id), num(r.net)]));
    const im = (items.rows || []).filter((r) => prev.has(String(r.item_id))).map((r) => { const cu = num(r.net) || 0, pv = prev.get(String(r.item_id)) || 0; return { kind: lbl(L('আইটেম', 'Item', 'Item')), what: labelOf(r, 'item'), now: cu, before: pv, change: Math.round((cu - pv) * 100) / 100, pct: pctCalc(cu, pv) }; });
    im.sort((a, b) => Math.abs(b.change) - Math.abs(a.change)); movers.push(...im.slice(0, 5));
    if (im.length) interp.push(lbl(L('আইটেমে সবচেয়ে বড় পরিবর্তন', 'Biggest item change', 'Item-এ বড় পরিবর্তন')) + ': ' + im[0].what + ' ' + (im[0].change > 0 ? '+' : '') + fmtV(im[0].change, 'money'));
  }
  if (exp.ok && (exp.rows || []).length) {
    const er = exp.rows.slice().sort((a, b) => Math.abs(num(b.change) || 0) - Math.abs(num(a.change) || 0));
    movers.push(...er.slice(0, 5).map((r) => ({ kind: lbl(L('খরচ', 'Expense', 'খরচ')), what: String(r.head || ''), now: num(r.current), before: num(r.previous), change: num(r.change), pct: num(r.change_pct) })));
    if (exp.totals) facts.push(lbl(L('খরচ', 'Expenses', 'খরচ')) + ': ' + fmtV(exp.totals.current, 'money') + ' (' + T('vs') + ' ' + fmtV(exp.totals.previous, 'money') + ')');
    if (num(er[0].change)) interp.push(lbl(L('খরচে সবচেয়ে বড় পরিবর্তন', 'Biggest expense change', 'খরচে বড় পরিবর্তন')) + ': ' + er[0].head + ' ' + (num(er[0].change) > 0 ? '+' : '') + fmtV(er[0].change, 'money'));
  }
  const fails = [loc, items, exp].filter((r) => !r.ok).map((r) => lbl((AT.TOOLS[r.key] || {}).title) + ': ' + failText(r));
  const cols = [{ key: 'kind', label_bn: 'ধরন', label_en: 'Kind', type: 'text' }, { key: 'what', label_bn: 'কী', label_en: 'What', type: 'text' }, { key: 'now', label_bn: 'এখন', label_en: 'Now', type: 'money' }, { key: 'before', label_bn: 'আগে', label_en: 'Before', type: 'money' }, { key: 'change', label_bn: 'পরিবর্তন', label_en: 'Change', type: 'money' }, { key: 'pct', label_bn: '%', label_en: '%', type: 'pct' }];
  return { title: lbl(AT.COMPOSITE.what_changed.title), summary: facts.join(' · ') || T('dataNeeded'), status: facts.length ? (fails.length ? 'partial' : 'verified') : 'data_needed', period: periodLabel(loc.ok ? loc : null, p), cmp: cmpLbl, loc: locLabel(p),
    table: movers.length ? { columns: cols, rows: movers, all: movers } : null, interp, notes: fails.concat(movers.length ? [T('calc') + ' (' + T('changeH') + ', %)'] : []), tools: ['sales_by_location', 'top_items', 'expense_trend'], ok: true,
    links: [{ route: 'report/sales_combined', label: lbl(AT.TOOLS.sales_by_location.title) }, { route: 'report/e2_expense_trend', label: lbl(AT.TOOLS.expense_trend.title) }], source: { kind: 'composite', name: 'what_changed' } };
}
async function unusual(p, me) {
  const keys = AT.COMPOSITE.unusual.parts; const rs = await Promise.all(keys.map((k) => runTool(k, Object.assign({}, p), me))); const R = {}; keys.forEach((k, i) => { R[k] = rs[i]; });
  const sig = []; const add = (k, label, v, type, route) => { if (num(v) && num(v) > 0) sig.push({ signal: label, value: num(v), _type: type, money: type === 'money' ? num(v) : 0, route, src: k }); };
  const t = (k) => (R[k] && R[k].ok && R[k].totals) || {};
  add('cash_short_over', lbl(L('ক্যাশ কম পড়েছে', 'Cash short', 'Cash কম')), t('cash_short_over').short_amount, 'money', 'report/cash_short_over');
  add('voids', lbl(L('বাতিল বিলের টাকা', 'Voided bills (amount)', 'Void amount')), t('voids').void_amt, 'money', 'report/voids');
  add('wastage', lbl(L('অপচয়ের মূল্য', 'Wastage value', 'অপচয় value')), t('wastage').value, 'money', 'report/wastage');
  add('discounts', lbl(L('সীমার বেশি ছাড়ের বিল', 'Bills with a discount over the limit', 'Limit-এর বেশি ছাড়')), t('discounts').over_limit_bills, 'int', 'report/discounts');
  add('discounts', lbl(L('দাম বদলানো লাইন', 'Price-override lines', 'Price override line')), t('discounts').override_lines, 'int', 'report/discounts');
  add('exceptions_summary', lbl(L('খোলা লাল ব্যতিক্রম', 'Open red exceptions', 'খোলা red exception')), t('exceptions_summary').red, 'int', 'exceptions');
  add('exceptions_summary', lbl(L('খোলা ব্যতিক্রম', 'Open exceptions', 'খোলা exception')), t('exceptions_summary').open, 'int', 'exceptions');
  add('count_variance', lbl(L('গণনায় গরমিল', 'Counts off', 'Count গরমিল')), t('count_variance').off_n, 'int', 'report/k2_count_variance');
  add('number_gaps', lbl(L('কাগজের নম্বর বাদ', 'Missing paper numbers', 'Paper number বাদ')), t('number_gaps').missing_count, 'int', 'numaudit');
  add('transfers_gap', lbl(L('পৌঁছায়নি এমন ট্রান্সফার', 'Transfers not received', 'পৌঁছায়নি transfer')), t('transfers_gap').not_received, 'int', 'report/transfers_gap');
  sig.sort((a, b) => (b.money - a.money) || (b.value - a.value));
  const seen = keys.filter((k) => R[k].ok).length; const fails = keys.filter((k) => !R[k].ok).map((k) => lbl(AT.TOOLS[k].title) + ': ' + failText(R[k]));
  const cols = [{ key: 'signal', label_bn: 'লক্ষণ', label_en: 'Signal', type: 'text' }, { key: 'shown', label_bn: 'পরিমাণ', label_en: 'Amount / count', type: 'text' }];
  const rows = sig.map((x) => Object.assign({}, x, { shown: fmtV(x.value, x._type) }));
  const links = []; sig.slice(0, 4).forEach((x) => { if (!links.some((l) => l.route === x.route)) links.push({ route: x.route, label: x.signal }); });
  return { title: lbl(AT.COMPOSITE.unusual.title), summary: sig.length ? sig.slice(0, 3).map((x) => x.signal + ': ' + fmtV(x.value, x._type)).join(' · ') : (seen ? T('noUnusual') : T('na')), status: seen === keys.length ? 'verified' : (seen ? 'partial' : 'na'),
    period: periodLabel(null, p), loc: locLabel(p), table: rows.length ? { columns: cols, rows, all: rows } : null, notes: [T('detectors')].concat(fails), tools: keys, ok: true, links, source: { kind: 'composite', name: 'unusual' } };
}
async function priorities(p, me) {
  const keys = ['health', 'needs_you', 'exceptions_summary', 'cash_short_over', 'payables', 'stock_low']; const rs = await Promise.all(keys.map((k) => runTool(k, Object.assign({}, p), me))); const R = {}; keys.forEach((k, i) => { R[k] = rs[i]; });
  const list = [];
  if (R.health.ok) { const f = R.health.findings || []; f.filter((x) => x.severity === 'bad').forEach((x) => list.push({ w: 100, text: (isEn() ? x.title_en : x.title_bn) + (x.detail ? ' — ' + x.detail : ''), route: x.route })); }
  if (R.needs_you.ok) { const old = (R.needs_you.rows || []).filter((r) => r.age_h !== null && r.age_h >= 24); if (old.length) list.push({ w: 90, text: lbl(L('২৪ ঘণ্টার বেশি অপেক্ষায়', 'Waiting more than 24 hours', '২৪ ঘণ্টার বেশি অপেক্ষায়')) + ': ' + old.length, route: 'pending' });
    else if ((R.needs_you.rows || []).length) list.push({ w: 60, text: lbl(L('অপেক্ষায়', 'Waiting for you', 'অপেক্ষায়')) + ': ' + R.needs_you.rows.length, route: 'pending' }); }
  if (R.exceptions_summary.ok && num((R.exceptions_summary.totals || {}).red)) list.push({ w: 80, text: lbl(L('লাল ব্যতিক্রম', 'Red exceptions', 'Red exception')) + ': ' + fmtN(R.exceptions_summary.totals.red, 0), route: 'exceptions' });
  if (R.cash_short_over.ok && num((R.cash_short_over.totals || {}).short_amount)) list.push({ w: 75, text: lbl(L('ক্যাশ কম', 'Cash short', 'Cash কম')) + ': ' + fmtV(R.cash_short_over.totals.short_amount, 'money'), route: 'report/cash_short_over' });
  if (R.payables.ok && num((R.payables.totals || {}).overdue)) list.push({ w: 70, text: lbl(L('মেয়াদোত্তীর্ণ দেনা', 'Overdue to suppliers', 'Overdue দেনা')) + ': ' + fmtV(R.payables.totals.overdue, 'money'), route: 'payables' });
  if (R.stock_low.ok && num((R.stock_low.totals || {}).lines)) list.push({ w: 50, text: lbl(L('কম-স্টক লাইন', 'Low-stock lines', 'Low stock line')) + ': ' + fmtN(R.stock_low.totals.lines, 0), route: 'report/stock_low' });
  if (R.health.ok) { const wn = (R.health.findings || []).filter((x) => x.severity === 'warn'); if (wn.length) list.push({ w: 40, text: lbl(L('সেটআপ-সতর্কতা', 'Setup warnings', 'Setup warning')) + ': ' + wn.length, route: 'assistant' }); }
  list.sort((a, b) => b.w - a.w);
  const rows = list.map((x, i) => ({ n: i + 1, text: x.text, route: x.route }));
  const fails = keys.filter((k) => !R[k].ok && R[k].code !== 'access').map((k) => lbl(AT.TOOLS[k].title) + ': ' + failText(R[k]));
  return { title: lbl(AT.COMPOSITE.priorities.title), summary: rows.length ? rows.slice(0, 3).map((r) => r.n + '. ' + r.text).join(' · ') : T('nothingPrio'), status: 'verified', period: periodLabel(null, p),
    table: rows.length ? { columns: [{ key: 'n', label_bn: '#', label_en: '#', type: 'int' }, { key: 'text', label_bn: 'কী', label_en: 'What', type: 'text' }], rows, all: rows } : null,
    interp: [T('prioNote')], notes: fails, tools: keys, ok: true, links: rows.slice(0, 5).map((r) => ({ route: r.route, label: r.text.slice(0, 40) })), source: { kind: 'composite', name: 'priorities' } };
}
function helpCard(me) {
  const yes = [], no = [];
  Object.values(AT.TOOLS).forEach((tl) => { const n = tl.needs(me); if (n === true) yes.push(lbl(tl.title)); else if (n === 'access') no.push(lbl(tl.title)); });
  return { title: lbl(AT.COMPOSITE.help.title), summary: T('help3'), status: 'verified', ok: true, tools: [], blocks: [[T('help1'), yes], [T('help2'), no]], links: [], source: { kind: 'local', name: 'registry' } };
}
async function notesCard() {
  const r = await sb.from('assistant_notes').select('*').eq('status', 'approved').order('id');
  const rows = (r.data || []).map((n) => ({ kind: n.kind, title: n.title, text: redact(isEn() ? (n.body_en || n.body_bn) : (n.body_bn || n.body_en)) }));
  return { title: lbl(AT.COMPOSITE.notes.title), summary: rows.length ? T('approvedOwner') + ': ' + rows.length : T('noNotes'), status: 'verified', ok: !r.error, tools: [],
    table: rows.length ? { columns: [{ key: 'kind', label_bn: 'ধরন', label_en: 'Kind', type: 'text' }, { key: 'title', label_bn: 'শিরোনাম', label_en: 'Title', type: 'text' }, { key: 'text', label_bn: 'নিয়ম', label_en: 'Rule', type: 'text' }], rows, all: rows } : null, links: [], source: { kind: 'table', name: 'assistant_notes' } };
}

// ---------- knowledge base (kb.json, BM25 in the browser) ----------
const KB = { data: null, idx: null, loading: null };
const toks = (s) => norm(s).split(/[\s/&-]+/).filter((w) => w.length >= 2);
async function loadKB() {
  if (KB.data) return KB.data; if (KB.loading) return KB.loading;
  KB.loading = (async () => { try { const r = await fetch('data/kb.json', { cache: 'no-cache' }); if (!r.ok) throw new Error('kb ' + r.status); KB.data = await r.json(); } catch (e) { KB.data = { version: null, chunks: [], playbooks: [], error: true }; }
    let notes = []; try { const n = await sb.from('assistant_notes').select('*').eq('status', 'approved'); notes = (n.data || []).map((x) => ({ id: 'note:' + x.id, kind: 'note', title_bn: x.title, title_en: x.title, text: redact((x.body_bn || '') + ' ' + (x.body_en || '')) })); } catch (e) { /* notes optional */ }
    const docs = KB.data.chunks.concat(notes).map((c) => { const tk = toks((c.title_bn || '') + ' ' + (c.title_en || '') + ' ' + (c.title_en || '') + ' ' + (c.text || '')); const tf = new Map(); tk.forEach((w) => tf.set(w, (tf.get(w) || 0) + 1)); return { c, tf, len: tk.length }; });
    const df = new Map(); docs.forEach((d) => d.tf.forEach((_, w) => df.set(w, (df.get(w) || 0) + 1)));
    KB.idx = { docs, df, avg: docs.reduce((s, d) => s + d.len, 0) / Math.max(docs.length, 1) }; return KB.data; })();
  return KB.loading;
}
function searchKB(q, n = 4) {
  if (!KB.idx) return []; const { docs, df, avg } = KB.idx; const N = docs.length; const qt = [...new Set(toks(q))]; const k1 = 1.4, b = 0.75;
  const boost = { playbook: 2.2, note: 2, screen: 1.4, rule: 1.2, grant: 1, form: 1, doc: 0.7 };
  return docs.map((d) => { let s = 0; qt.forEach((w) => { const f = d.tf.get(w); if (!f) return; const idf = Math.log(1 + (N - df.get(w) + 0.5) / (df.get(w) + 0.5)); s += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * d.len / avg)); }); return { c: d.c, s: s * (boost[d.c.kind] || 1) }; })
    .filter((x) => x.s > 0.5).sort((a, b2) => b2.s - a.s).slice(0, n);
}
let HEALTH = null;
async function healthOnce(me) { if (HEALTH) return HEALTH; if (!me.health) return null; const r = await runTool('health', {}, me); HEALTH = r.ok ? r.findings || [] : null; return HEALTH; }
function ruleNow(k) { const r = B.ENV && B.ENV.rules && B.ENV.rules[k]; if (!r) return { exists: false }; const v = r.value !== null && r.value !== undefined ? r.value : r.default_value; return { exists: true, v, kind: r.kind }; }
const showVal = (x) => (x.v === null || x.v === undefined || x.v === '' ? lbl(L('ফাঁকা', 'blank', 'blank')) : x.v === true || x.v === 'true' ? 'ON' : x.v === false || x.v === 'false' ? 'OFF' : String(x.v));
async function kbCard(q, me) {
  await loadKB(); const hits = searchKB(q); const ver = KB.data && KB.data.version;
  if (!hits.length) return { title: T('kbFrom'), summary: T('kbNone'), status: 'data_needed', ok: true, tools: ['kb'], kbVer: ver, links: [{ route: 'switchboard', label: 'Switchboard' }], source: { kind: 'kb', name: 'kb.json' } };
  const top = hits[0].c; const card = { title: T('kbFrom'), status: 'verified', ok: true, tools: ['kb'], kbVer: ver, links: [], source: { kind: 'kb', name: 'kb.json' } };
  if (top.kind === 'playbook') {
    const pb = (KB.data.playbooks || []).find((x) => x.id === top.key); const hf = await healthOnce(me); const steps = [];
    (pb ? pb.steps : []).forEach((st, i) => { const [kind, val] = String(st.check || 'none').split(':'); let s = 'check', now = '';
      if (kind === 'rule' || kind === 'rule_set' || kind === 'rule_on') { const x = ruleNow(val); if (!x.exists) s = 'unknown'; else { now = T('now') + ': ' + showVal(x); s = kind === 'rule' ? 'info' : kind === 'rule_set' ? (x.v === null || x.v === undefined || x.v === '' ? 'todo' : 'done') : (x.v === true || x.v === 'true' ? 'done' : 'todo'); } }
      else if (kind === 'health') { if (hf === null) s = 'unknown'; else { const f = hf.filter((x) => x.code === val); s = f.length ? 'todo' : 'done'; if (f.length) now = f.map((x) => x.detail).join('; ').slice(0, 160); } }
      steps.push({ n: i + 1, text: isEn() ? st.en : st.bn, route: st.route, s, now }); card.links.push({ route: st.route, label: (i + 1) + '. ' + (isEn() ? st.en : st.bn).slice(0, 28) }); });
    card.title = isEn() ? top.title_en : top.title_bn; card.steps = steps; card.summary = (pb && pb.body) || ''; card.links = card.links.filter((l, i, a) => a.findIndex((z) => z.route === l.route) === i).slice(0, 6);
  } else {
    card.summary = hits.slice(0, 3).map((h) => (isEn() ? h.c.title_en : h.c.title_bn) + (h.c.kind === 'note' ? ' (' + T('approvedOwner') + ')' : '')).join(' · ');
    card.kbHits = hits.slice(0, 3).map((h) => ({ title: isEn() ? h.c.title_en : h.c.title_bn, kind: h.c.kind, text: String(h.c.text || '').slice(0, 260), route: h.c.route, key: h.c.key }));
    hits.forEach((h) => { if (h.c.route) card.links.push({ route: h.c.route, label: (isEn() ? h.c.title_en : h.c.title_bn).slice(0, 36) }); });
    const rk = hits.find((h) => h.c.kind === 'rule'); if (rk) { const x = ruleNow(rk.c.key); if (x.exists) card.summary += ' — ' + rk.c.key + ' ' + T('now') + ': ' + showVal(x); }
  }
  return card;
}

// ---------- provider adapters ----------
let PROXY_DOWN = false;
const PROVIDERS = {
  local: { plan: (q, ctx, me) => Promise.resolve(route(q, ctx, me)) },
  // DISABLED by default: only when the owner sets assistant_provider = llm_proxy AND deploys tools/edge/assistant-proxy.ts. The AI only CHOOSES a tool
  // (validated against this registry); the browser runs it with the user's session; numbers still come only from the tools.
  llm_proxy: { enabled: (me) => me.provider === 'llm_proxy' && !PROXY_DOWN && sb.functions && typeof sb.functions.invoke === 'function',
    plan: async (q, ctx, me) => {
      const pre = route(q, ctx, me); if (pre.kind === 'refuse' || pre.kind === 'export' || pre.kind === 'print') return pre;   // safety always runs locally first
      const tools = Object.values(AT.TOOLS).filter((tl) => tl.needs(me) === true).map((tl) => ({ name: tl.key, description: lbl(tl.title), params: tl.params }));
      const r = await sb.functions.invoke('assistant-proxy', { body: { question: redact(q).slice(0, 500), lang: LG(), tools, last: ctx.last ? { tool: ctx.last.tool } : null } });
      if (r.error || !r.data || !r.data.tool || !(AT.TOOLS[r.data.tool] || AT.COMPOSITE[r.data.tool])) throw new Error('proxy');
      const tl = AT.TOOLS[r.data.tool]; if (tl && tl.needs(me) !== true) return plan(r.data.tool, {}, r.data.tool);
      const pr = r.data.params || {}; const p = { period: pr.preset ? { preset: pr.preset } : (pr.from ? { from: pr.from, to: pr.to } : null), topN: pr.top_n, compare: !!pr.compare, locs: (pr.location_codes || []).map((c) => ((B.ENV.locs || []).find((l) => l.code === c) || {}).id).filter(Boolean) };
      const pl = plan(r.data.tool, p, 'llm_' + r.data.tool); pl.tokens = r.data.usage || null; return pl; } },
};

// ---------- conversation state (sessionStorage, per user; never secrets) ----------
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const SK = () => 'bos_asst:' + uid();
const ST8 = { ctx: {}, hist: [], times: [], last: null };
function loadState() { try { const v = JSON.parse(sessionStorage.getItem(SK()) || 'null'); if (v) { ST8.ctx = v.ctx || {}; ST8.hist = v.hist || []; } } catch (e) { /* private mode */ } }
function saveState() { try { sessionStorage.setItem(SK(), JSON.stringify({ ctx: ST8.ctx, hist: ST8.hist.slice(-12) })); } catch (e) { /* private mode */ } }

// ---------- the main entry: ask ----------
let ME = null;
async function loadMe() {
  if (ME) return ME;
  try { const r = await sb.rpc('assistant_me'); if (r.error) throw r.error; ME = r.data && typeof r.data === 'object' ? r.data : { allowed: false, reason: 'install' }; }
  catch (e) { const c = classify(e).code; ME = c === 'install' ? fallbackMe() : { allowed: false, reason: c === 'offline' ? 'offline' : 'error' }; }
  return ME;
}
// phase47 not pasted yet: owner-only, read tools still guarded by every server function
function fallbackMe() { const own = !!(S.ctx && S.ctx.is_owner); if (!own) return { allowed: false, reason: 'install' }; const g = {}; ['sales', 'pos', 'cash', 'customers', 'stock', 'purchase', 'expense', 'staff', 'control', 'profit', 'orders', 'marketing', 'quality'].forEach((k) => { g[k] = true; });
  return { allowed: true, is_owner: true, health: false, cost: true, biz: true, salary: true, daybook: true, purchase: true, pos: true, reports: g, optional: [], provider: 'local', cache_seconds: 60, phase47: false }; }
async function ask(q, opts = {}) {
  const me = await loadMe(); const t0 = performance.now();
  if (!me.allowed) return addCard({ title: T('title'), summary: me.reason === 'assistant_off' ? T('off') : T('noRight'), status: 'na', ok: false });
  const now = Date.now(); ST8.times = ST8.times.filter((x) => now - x < 60000); if (ST8.times.length >= CFG.maxPerMinute) return addCard({ title: T('title'), summary: T('r_rate'), status: 'na', ok: false }); ST8.times.push(now);
  const shown = redact(q); addUser(shown);
  let pl = null; let provider = 'local';
  if (opts.tool) pl = plan(opts.tool, Object.assign({}, (ST8.ctx.last || {}).params, { q: norm(q) }), opts.tool);
  if (!pl && PROVIDERS.llm_proxy.enabled(me)) { try { pl = await PROVIDERS.llm_proxy.plan(q, ST8.ctx, me); provider = 'llm_proxy'; } catch (e) { PROXY_DOWN = true; pl = null; } }
  if (!pl) pl = await PROVIDERS.local.plan(q, ST8.ctx, me);
  const card = await answer(pl, me);
  card.ms = Math.round(performance.now() - t0); addCard(card);
  if (pl.kind === 'tool' || pl.kind === 'composite') { ST8.ctx.last = { tool: pl.tool, intent: pl.intent, params: Object.assign({}, pl.params, { q: undefined }) }; }
  if (card.table || card.steps) ST8.last = card;
  ST8.hist.push({ q: shown.slice(0, 200), title: card.title, summary: redact(String(card.summary || '')).slice(0, 300) }); saveState();
  if (me.phase47 !== false && provider === 'local') { try { sb.rpc('assistant_log', { p_provider: provider, p_intent: String(pl.intent || pl.kind || 'x').replace(/[^a-z0-9_]/g, '_').slice(0, 40) || 'x', p_tools: (card.tools || []).filter((k) => /^[a-z0-9_]{1,40}$/.test(k)).slice(0, 12), p_ms: Math.min(card.ms, 600000), p_tokens_in: (pl.tokens && pl.tokens.in) || 0, p_tokens_out: (pl.tokens && pl.tokens.out) || 0, p_ok: card.status !== 'na' })
    .then((r) => { if (r && r.data && r.data.limited) toastOnce(T('r_rate')); }).catch(() => {}); } catch (e) { /* log is best effort */ } }
  return card;
}
let toasted = false; const toastOnce = (m) => { if (!toasted && A.toast) { toasted = true; A.toast(m); } };
async function answer(pl, me) {
  if (pl.kind === 'empty') return { title: T('title'), summary: T('clarify'), status: 'na', ok: false };
  if (pl.kind === 'refuse') return { title: T('title'), summary: T('r_' + pl.reason), status: 'refused', ok: false, refused: pl.reason, links: pl.links || [], tools: [] };
  if (pl.kind === 'out_of_scope') return { title: T('title'), summary: T('oos'), status: 'refused', ok: false, refused: 'oos', tools: [], chipsAfter: true };
  if (pl.kind === 'clarify') return { title: T('clarify'), summary: '', status: 'clarify', ok: true, options: pl.options, tools: [] };
  if (pl.kind === 'export') { exportLast(); return { title: T('exportB'), summary: ST8.last ? '✓' : T('nothingToExport'), status: 'verified', ok: true, tools: [] }; }
  if (pl.kind === 'print') { printLast(); return { title: T('printB'), summary: '✓', status: 'verified', ok: true, tools: [] }; }
  if (pl.kind === 'kb') return kbCard(pl.q, me);
  if (pl.kind === 'composite') return composite(pl.tool, pl.params, me);
  const tl = AT.TOOLS[pl.tool]; const res = await runTool(pl.tool, pl.params, me); return cardForTool(tl, res, sanitize(tl, pl.params));
}

// ---------- rendering ----------
const chipCls = (s) => (s === 'verified' ? 'ok' : s === 'partial' || s === 'data_needed' || s === 'clarify' ? 'warn' : 'bad');
function svgChart(ch) {
  const pts = (ch.points || []).filter((x) => Number.isFinite(x.v)); if (pts.length < 2) return '';
  if (ch.type === 'line') {
    const W = 320, Hh = 110, pad = 6, mx = Math.max(...pts.map((p) => p.v)), mn = Math.min(0, ...pts.map((p) => p.v)), sp = (mx - mn) || 1;
    const xy = pts.map((p, i) => [pad + i * (W - 2 * pad) / (pts.length - 1), Hh - pad - (p.v - mn) * (Hh - 2 * pad) / sp]);
    return `<svg class="asst-svg" viewBox="0 0 ${W} ${Hh}" role="img" aria-label="${esc(pts.map((p) => p.l + ' ' + fmtV(p.v, ch.vtype)).join(', '))}"><polyline fill="none" stroke="currentColor" stroke-width="2" points="${xy.map((p) => p[0].toFixed(1) + ',' + p[1].toFixed(1)).join(' ')}"/>${xy.map((p, i) => `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="2.2"><title>${esc(pts[i].l + ': ' + fmtV(pts[i].v, ch.vtype))}</title></circle>`).join('')}</svg>
      <div class="row between muted asst-axis"><span>${esc(pts[0].l)}</span><span>${esc(pts[pts.length - 1].l)}</span></div>`;
  }
  const mx = Math.max(...pts.map((p) => Math.abs(p.v))) || 1;
  return `<div class="asst-bars" role="img" aria-label="${esc(pts.map((p) => p.l + ' ' + fmtV(p.v, ch.vtype)).join(', '))}">${pts.map((p) => `<div class="asst-bar"><span class="asst-bl">${esc(p.l)}</span><span class="asst-bt"><i style="width:${Math.max(2, Math.round(100 * Math.abs(p.v) / mx))}%" class="${p.v < 0 ? 'neg' : ''}"></i></span><span class="asst-bv">${esc(fmtV(p.v, ch.vtype))}</span></div>`).join('')}</div>`;
}
function tableHtml(tb, id) {
  const cols = tb.columns; const hl = (c) => (isEn() ? (c.label_en || c.label_bn) : (c.label_bn || c.label_en));
  return `<div class="asst-tw"><table class="asst-t" data-tid="${id}"><thead><tr>${cols.map((c, i) => `<th><button type="button" data-act="asst_sort" data-t="${id}" data-c="${i}" aria-label="${esc(hl(c))}">${esc(hl(c))}</button></th>`).join('')}</tr></thead><tbody>${tb.rows.map((r) => `<tr>${cols.map((c) => `<td class="${['money', 'int', 'num', 'pct'].includes(c.type) ? 'n' : ''}">${esc(fmtV(r[c.key], r._type && c.key === 'amount' ? r._type : c.type))}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}
let CID = 0; const CARDS = {};
function cardHtml(c) {
  const id = 'c' + (++CID); CARDS[id] = c;
  const st = c.status === 'verified' ? T('verified') : c.status === 'partial' ? T('partial') : c.status === 'data_needed' ? T('dataNeeded') : c.status === 'clarify' ? '' : c.status === 'refused' ? '' : T('na');
  const opts = c.options ? `<div class="row wrap asst-chips">${c.options.map((o) => `<button type="button" class="asst-chip" data-act="asst_pick" data-v="${esc(o.tool)}">${esc(o.label)}</button>`).join('')}</div>` : '';
  const blocks = (c.blocks || []).map(([h, list]) => list.length ? `<div class="asst-sub"><b>${esc(h)}</b><div class="muted">${list.map(esc).join(' · ')}</div></div>` : '').join('');
  const steps = c.steps ? `<ol class="asst-steps">${c.steps.map((s) => `<li><a href="#/${esc(s.route)}">${esc(s.text)}</a> <span class="chip ${s.s === 'done' ? 'ok' : s.s === 'todo' ? 'warn' : ''}">${esc(s.s === 'done' ? T('stepDone') : s.s === 'todo' ? T('stepTodo') : s.s === 'unknown' ? T('stepUnknown') : s.s === 'info' ? 'ⓘ' : T('stepCheck'))}</span>${s.now ? `<div class="muted asst-small">${esc(s.now)}</div>` : ''}</li>`).join('')}</ol>` : '';
  const hits = c.kbHits ? c.kbHits.map((h) => `<div class="asst-sub"><b>${esc(h.title)}</b> <span class="muted asst-small">${esc(h.kind)}</span><div class="muted asst-small">${esc(h.text)}</div></div>`).join('') : '';
  const interp = c.interp && c.interp.length ? `<div class="asst-sub"><b>${esc(T('interp'))}</b><ul>${c.interp.map((x) => `<li>${esc(x)}</li>`).join('')}</ul></div>` : '';
  const links = (c.links || []).length ? `<div class="row wrap asst-chips">${c.links.map((l) => `<a class="asst-chip" href="#/${esc(l.route)}">${esc(T('open'))}: ${esc(l.label)}</a>`).join('')}</div>` : '';
  const btns = c.table || c.steps ? `<div class="row wrap asst-acts">${c.table ? `<button type="button" data-act="asst_csv" data-v="${id}">${esc(T('exportB'))}</button>` : ''}<button type="button" data-act="asst_print" data-v="${id}">${esc(T('printB'))}</button>${c.tools && c.tools.length && !c.steps ? `<button type="button" data-act="asst_why" data-v="${id}">${esc(T('whyB'))}</button>` : ''}</div>` : '';
  const foot = c.status === 'refused' || c.status === 'clarify' ? '' : `<div class="muted asst-foot">${st ? `<span class="chip ${chipCls(c.status)}">${esc(st)}</span> ` : ''}${c.source && c.source.name ? esc(T('src')) + ': ' + esc(c.source.name) + ' · ' : ''}${c.period ? esc(T('period')) + ': ' + esc(c.period) + ' · ' : ''}${c.cmp ? esc(T('cmpPeriod')) + ': ' + esc(c.cmp) + ' · ' : ''}${c.loc ? esc(c.loc) + ' · ' : ''}${c.kbVer ? esc(T('kbVer')) + ': ' + esc(c.kbVer) + ' · ' : ''}${esc(T('asof'))}: ${esc(new Date().toLocaleTimeString('en-GB', { timeZone: 'Asia/Dhaka', hour: '2-digit', minute: '2-digit' }))}${c.ms !== undefined ? ' · ' + c.ms + ' ms' : ''}</div>`;
  return `<div class="card asst-card asst-print-target" id="${id}" data-status="${esc(c.status || '')}" data-refused="${esc(c.refused || '')}"><b class="asst-h">${esc(c.title || '')}</b>${c.summary ? `<p class="asst-sum">${esc(c.summary)}</p>` : ''}${opts}${blocks}${steps}${hits}
    ${c.chart ? svgChart(c.chart) : ''}${c.table ? tableHtml(c.table, id) : ''}${interp}${(c.notes || []).length ? `<ul class="muted asst-notes">${c.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>` : ''}${links}${btns}${foot}</div>`;
}
function addUser(text) { const log = $('#asst_log'); if (!log) return; log.insertAdjacentHTML('beforeend', `<div class="asst-me"><span>${esc(text)}</span></div>`); log.scrollTop = log.scrollHeight; }
function addCard(c) { const log = $('#asst_log'); if (log) { log.insertAdjacentHTML('beforeend', cardHtml(c)); const el = log.lastElementChild; if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' }); } return c; }

// ---------- export / print ----------
function csvOf(c) { const cols = c.table.columns; const q = (v) => { let s = v === null || v === undefined ? '' : String(v); if (/^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = "'" + s; /* spreadsheet formula guard */ return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
  return [cols.map((x) => q(isEn() ? x.label_en : x.label_bn)).join(',')].concat((c.table.all || c.table.rows).map((r) => cols.map((x) => q(r[x.key])).join(','))).join('\n'); }
async function exportCard(c) {
  if (!c || !c.table) return A.toast && A.toast(T('nothingToExport'));
  const okx = (S.ctx && S.ctx.is_owner) || (A.hasAnyGrant && await A.hasAnyGrant(['export_data'])); if (!okx) return A.toast && A.toast(T('noExport'));
  const blob = new Blob(['﻿' + csvOf(c)], { type: 'text/csv;charset=utf-8' }); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'assistant_' + (c.source && c.source.name ? c.source.name : 'answer') + '_' + AT.today() + '.csv'; document.body.appendChild(a); a.click(); a.remove();
  window.__asLastCsv = csvOf(c);
  if (c.source && c.source.kind === 'report') { try { await sb.rpc('log_report_export2', { p_key: c.source.name, p_kind: 'csv_assistant', p_filters: (c.source.params && c.source.params.p_filters) || {}, p_rows: (c.table.all || []).length }); } catch (e) { /* audit is best effort */ } }
}
const exportLast = () => exportCard(ST8.last);
function printCard(id) { document.body.classList.add('asst-printing'); const el = id && document.getElementById(id); if (el) el.classList.add('asst-print-on'); try { window.print(); } finally { setTimeout(() => { document.body.classList.remove('asst-printing'); if (el) el.classList.remove('asst-print-on'); }, 300); } }
const printLast = () => { const cs = document.querySelectorAll('.asst-card'); printCard(cs.length ? cs[cs.length - 1].id : null); };

// ---------- page ----------
const CSS = `.asst-log{display:flex;flex-direction:column;gap:6px;min-height:120px}.asst-me{align-self:flex-end;max-width:85%;background:var(--ruby-grad,#7a1f2b);color:#fff4df;border-radius:14px 14px 2px 14px;padding:8px 12px;font-size:.95rem;overflow-wrap:anywhere}
.asst-card{overflow:hidden;font-size:.9rem}.asst-h{display:block;margin-bottom:4px}.asst-sum{margin:4px 0 8px;overflow-wrap:anywhere}.asst-chips{gap:6px;margin:6px 0}.asst-chip{display:inline-flex;align-items:center;min-height:40px;padding:4px 12px;border-radius:20px;border:1px solid var(--line);background:var(--card);color:inherit;text-decoration:none;font-size:.85rem;max-width:100%;overflow-wrap:anywhere}
.asst-tw{max-width:100%;overflow-x:auto;margin:6px 0}.asst-t{border-collapse:collapse;width:100%;font-size:.8rem}.asst-t th,.asst-t td{border-bottom:1px solid var(--line);padding:4px 6px;text-align:left;vertical-align:top}.asst-t td.n{text-align:right;white-space:nowrap}.asst-card .asst-t th>button{all:unset!important;cursor:pointer!important;font-weight:700!important;font-size:.8rem!important;min-height:32px!important;display:inline-flex!important;align-items:center!important;color:inherit!important}
.asst-bars{display:flex;flex-direction:column;gap:3px;margin:6px 0}.asst-bar{display:grid;grid-template-columns:minmax(0,38%) 1fr auto;gap:6px;align-items:center;font-size:.78rem}.asst-bl{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.asst-bt{background:var(--line);border-radius:4px;height:10px;overflow:hidden}.asst-bt i{display:block;height:100%;background:var(--gold,#c9a227)}.asst-bt i.neg{background:var(--bad,#b00)}.asst-bv{white-space:nowrap}
.asst-svg{width:100%;height:auto;color:var(--gold,#c9a227);margin-top:6px}.asst-axis{font-size:.72rem}.asst-foot{font-size:.75rem;margin-top:8px;overflow-wrap:anywhere}.asst-notes{font-size:.78rem;margin:6px 0;padding-left:18px}.asst-sub{margin:6px 0}.asst-small{font-size:.78rem}.asst-steps{padding-left:20px;margin:6px 0}.asst-steps li{margin:6px 0}
.asst-acts{gap:6px;margin-top:6px}.asst-acts button{min-height:40px}.asst-in{position:sticky;bottom:0;z-index:8;background:var(--bg,#fff);padding:8px 0;display:flex;gap:6px}body.has-bnav .asst-in{bottom:calc(60px + env(safe-area-inset-bottom))}.asst-in input{flex:1;min-width:0;min-height:44px}.asst-in button{min-height:44px;min-width:44px}
.asst-grp{margin:4px 0}.asst-grp b{font-size:.8rem}.asst-alert{display:flex;gap:6px;flex-wrap:wrap}
@media print{body.asst-printing *{visibility:hidden}body.asst-printing .asst-print-on,body.asst-printing .asst-print-on *{visibility:visible}body.asst-printing .asst-print-on{position:absolute;left:0;top:0;width:100%}}`;
function css() { if (!document.getElementById('asst_css')) { const s = document.createElement('style'); s.id = 'asst_css'; s.textContent = CSS; document.head.appendChild(s); } }
function chipsHtml(me) {
  const ok = (k) => { if (k === 'kb') return true; if (AT.COMPOSITE[k]) return k === 'help' || k === 'notes' || AT.COMPOSITE[k].parts.some((x) => AT.TOOLS[x] && AT.TOOLS[x].needs(me) === true); return AT.TOOLS[k] && AT.TOOLS[k].needs(me) === true; };
  const groups = ['today', 'money', 'stock', 'people', 'setup'];
  return groups.map((g) => { const qs = AT.SUGGEST.filter((s) => s[0] === g && ok(s[1])); return qs.length ? `<div class="asst-grp"><b>${esc(T('g_' + g))}</b><div class="row wrap asst-chips">${qs.map((s) => `<button type="button" class="asst-chip" data-act="asst_ask" data-q="${esc(lbl(s[2]))}">${esc(lbl(s[2]))}</button>`).join('')}</div></div>` : ''; }).join('');
}
async function alerts(me) {
  const box = $('#asst_alerts'); if (!box) return; const parts = [];
  try { const n = await runTool('needs_you', {}, me); if (n.ok) parts.push(`<button type="button" class="asst-chip" data-act="asst_ask" data-q="${esc(lbl(AT.SUGGEST[1][2]))}">${esc(T('waiting'))}: ${fmtN(n.rows.length, 0)}</button>`); } catch (e) { /* optional */ }
  if (me.health) { try { const h = await runTool('health', {}, me); if (h.ok) { HEALTH = h.findings; const bad = h.findings.filter((x) => x.severity !== 'info').length; parts.push(`<button type="button" class="asst-chip" data-act="asst_tool" data-v="health">${esc(T('setupIssues'))}: ${fmtN(bad, 0)}</button>`); } } catch (e) { /* optional */ } }
  box.innerHTML = parts.length ? `<b>${esc(T('alerts'))}</b> ${parts.join('')}` : '';
}
async function ownerPanel(me) {
  const box = $('#asst_owner'); if (!box || !me.is_owner) return;
  let u = null; try { const r = await sb.rpc('assistant_usage_summary', {}); u = r.error ? null : r.data; } catch (e) { u = null; }
  const est = u ? Object.entries(AT.PRICES).map(([m, p]) => m + ': $' + ((Number(u.tokens_in || 0) * p.in + Number(u.tokens_out || 0) * p.out) / 1e6).toFixed(4)).join(' · ') : '—';
  let notes = []; try { const r = await sb.from('assistant_notes').select('*').order('id'); notes = r.data || []; } catch (e) { notes = []; }
  box.innerHTML = `<details data-ctl="off" class="card"><summary><b>${esc(T('settings'))}</b></summary>
    <p class="muted">${esc(me.provider === 'llm_proxy' ? T('engineProxy') : T('engine'))}. ${esc(T('proxyOff'))}</p>
    <p>${esc(T('usage'))}: ${u ? `${fmtN(u.questions, 0)} ${esc(T('questions'))} · ${fmtN(u.avg_ms, 0)} ms · ${esc(T('tokens'))} ${fmtN(u.tokens_in, 0)} / ${fmtN(u.tokens_out, 0)} · ${esc(T('budget'))}: ${u.budget === null || u.budget === undefined ? esc(T('dataNeeded')) : fmtN(u.budget, 0)}` : '—'}</p>
    <p class="muted asst-small">${esc(T('estCost'))}: ${esc(est)}</p>
    <b>${esc(T('notesT'))}</b>${notes.length ? notes.map((n) => `<div class="row between asst-sub"><span>${esc(n.status === 'retired' ? '✕ ' : '')}<b>${esc(n.title)}</b> <span class="muted asst-small">${esc(lab(X['k_' + n.kind] || L(n.kind, n.kind)))}</span><div class="muted asst-small">${esc(redact(n.body_bn || n.body_en || ''))}</div></span>${n.status === 'approved' ? `<button type="button" data-act="asst_nretire" data-v="${esc(n.id)}">${esc(T('retire'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('noNotes'))}</p>`}
    <div class="stack"><label for="asst_nkind" class="muted asst-small">${esc(T('addNote'))}</label><select id="asst_nkind">${['rule', 'procedure', 'fact'].map((k) => `<option value="${k}">${esc(T('k_' + k))}</option>`).join('')}</select>
    <input id="asst_ntitle" placeholder="${esc(T('nTitle'))}" aria-label="${esc(T('nTitle'))}" autocomplete="off" maxlength="120"><textarea id="asst_nbn" rows="2" placeholder="${esc(T('nBn'))}" aria-label="${esc(T('nBn'))}" maxlength="2000"></textarea><textarea id="asst_nen" rows="2" placeholder="${esc(T('nEn'))}" aria-label="${esc(T('nEn'))}" maxlength="2000"></textarea>
    <button type="button" class="primary" data-act="asst_nsave">${esc(T('save'))}</button></div></details>`;
}
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(X).filter((x) => x.startsWith('e_')).find((x) => m.includes(x.slice(2))); return k ? T(k) : (/not allowed/.test(m) ? T('na') : m); };
let PENDING = null;
async function view() {
  css(); shell(T('title'), `<div id="asst_body"><p class="muted">…</p></div>`, true);
  if (B.loadStatic) { try { await B.loadStatic(); } catch (e) { /* offline: KB questions still work */ } }
  ME = null; HEALTH = null; const me = await loadMe(); loadState();
  const body = $('#asst_body'); if (!body) return;
  if (!me.allowed) { body.innerHTML = `<div class="card"><p>${esc(me.reason === 'assistant_off' ? T('off') : me.reason === 'offline' ? T('offline') : T('noRight'))}</p></div>`; return; }
  const voice = me.voice_on && (window.SpeechRecognition || window.webkitSpeechRecognition);
  body.innerHTML = `<div id="asst_alerts" class="asst-alert"></div><div class="card muted asst-small">${esc(T('hello'))}</div>
    ${ST8.hist.length ? `<details data-ctl="off"><summary class="muted">${esc(T('earlier'))} (${ST8.hist.length})</summary>${ST8.hist.map((h) => `<div class="asst-me"><span>${esc(h.q)}</span></div><div class="card asst-small"><b>${esc(h.title)}</b><div>${esc(h.summary)}</div></div>`).join('')}</details>` : ''}
    <div id="asst_chips">${chipsHtml(me)}</div><div id="asst_log" class="asst-log" aria-live="polite"></div>
    <div class="asst-in"><input id="asst_q" type="text" enterkeyhint="send" autocomplete="off" maxlength="500" placeholder="${esc(T('ph'))}" aria-label="${esc(T('ph'))}">${voice ? `<button type="button" data-act="asst_mic" aria-label="${esc(T('mic'))}">🎤</button>` : ''}<button type="button" class="primary" data-act="asst_send">${esc(T('send'))}</button></div>
    <div id="asst_owner"></div><p class="muted asst-small" id="asst_ver">${esc(me.provider === 'llm_proxy' ? T('engineProxy') : T('engine'))}</p>`;
  alerts(me); ownerPanel(me);
  loadKB().then((k) => { const v = $('#asst_ver'); if (v && k && k.version) v.textContent += ' · ' + T('kbVer') + ': ' + k.version; });
  if (PENDING) { const q = PENDING; PENDING = null; await ask(q); }
}
Object.assign(H, {
  asst_send: async () => { const i = $('#asst_q'); if (!i) return; const q = i.value.trim(); if (!q) return; i.value = ''; await ask(q); },
  asst_ask: async (a) => { await ask(a.dataset.q || ''); },
  asst_tool: async (a) => { const k = a.dataset.v; const t = AT.TOOLS[k] || AT.COMPOSITE[k]; await ask(t ? lbl(t.title) : k, { tool: k }); },
  asst_pick: async (a) => { const k = a.dataset.v; const t = AT.TOOLS[k] || AT.COMPOSITE[k]; await ask(t ? lbl(t.title) : k, { tool: k }); },
  asst_why: async () => { await ask(isEn() ? 'why?' : 'কেন?'); },
  asst_csv: async (a) => { await exportCard(CARDS[a.dataset.v]); },
  asst_print: (a) => printCard(a.dataset.v),
  asst_sort: (a) => { const c = CARDS[a.dataset.t]; if (!c || !c.table) return; const col = c.table.columns[Number(a.dataset.c)]; const dir = c._sortK === col.key && c._sortD === 1 ? -1 : 1; c._sortK = col.key; c._sortD = dir;
    const isN = ['money', 'int', 'num', 'pct'].includes(col.type); c.table.rows = c.table.rows.slice().sort((x, y) => { const p = x[col.key], q = y[col.key]; return dir * (isN ? (num(p) || 0) - (num(q) || 0) : String(p || '').localeCompare(String(q || ''))); });
    const el = document.getElementById(a.dataset.t); const tw = el && el.querySelector('.asst-tw'); if (tw) tw.outerHTML = tableHtml(c.table, a.dataset.t); },
  asst_mic: () => { const R = window.SpeechRecognition || window.webkitSpeechRecognition; if (!R) return; const r = new R(); r.lang = LG() === 'en' ? 'en-US' : 'bn-BD'; r.onresult = (e) => { const i = $('#asst_q'); if (i) i.value = e.results[0][0].transcript; }; r.start(); },
  asst_nsave: async () => { const r = await sb.rpc('assistant_note_save', { p_id: null, p_client: (crypto.randomUUID ? crypto.randomUUID() : String(Date.now())), p_kind: $('#asst_nkind').value, p_title: $('#asst_ntitle').value, p_body_bn: $('#asst_nbn').value, p_body_en: $('#asst_nen').value });
    if (r.error) return A.toast(eText(r.error)); A.toast(T('saved')); KB.data = null; KB.loading = null; await ownerPanel(ME); },
  asst_nretire: async (a) => { const why = window.prompt(T('e_reason_required')); if (!why) return; const r = await sb.rpc('assistant_note_retire', { p_id: Number(a.dataset.v), p_reason: why }); if (r.error) return A.toast(eText(r.error)); KB.data = null; KB.loading = null; await ownerPanel(ME); },
});
document.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target && e.target.id === 'asst_q') { e.preventDefault(); H.asst_send(); } });
window.addEventListener('online', () => { CACHE.clear(); });
function open(q) { if (q) PENDING = String(q); if ((location.hash.replace(/^#\/?/, '') || '').split('/')[0] === 'assistant') { if (PENDING) { const x = PENDING; PENDING = null; ask(x); } } else location.hash = '#/assistant'; }

B.assistant = { open, ask, route, understand, norm, safety, redact, sanitize, runTool, answer, cardForTool, fmtV, fmtN, loadKB, searchKB, _cfg: CFG, _state: ST8, _reset: () => { ME = null; HEALTH = null; CACHE.clear(); ST8.ctx = {}; ST8.times = []; ST8.last = null; toasted = false; PROXY_DOWN = false; }, _me: () => ME };
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { assistant: view });
})();
