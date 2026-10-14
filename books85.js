/* Islamia BOS · Books 85 (#/books85): screens for the phase85 backend that had no UI.
   Tabs: (1) card settlement (card_settle, card_settle_void, card_settlement_list), (2) auto posting (acct_autopost_tick, acct_scheduler_enable / disable,
   acct_pending_alert85, runs), (3) books switches (acct_count_adjust, acct_stock_opening, acct_issue_out, acct_transfer_mode, acct_transit_loss,
   acct_transit_loss_at, acct_purchase_variance, acct_stock_moves_from) with a recommendation and a warning before a switch is turned ON.
   Owner-gated where the backend is (switches, scheduler, run now). Recommendations never block. Nothing here posts by itself; the owner taps.
   Server: supabase/phase85.sql. data-act names start with dg_. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rid = () => (window.crypto && crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3) | 8).toString(16); }));
const norm = (v) => String(v == null ? '' : v).replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).replace(/,/g, '').trim();
const nnum = (v) => { const s = norm(v); if (s === '') return 0; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const fm = (n) => { const v = Number(n); if (!Number.isFinite(v)) return '-'; return (v < 0 ? '-' : '') + Math.abs(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); };
const money = (n) => '৳ ' + fm(n);

const X = {
  title: L('কার্ড, অটো পোস্ট, সুইচ', 'Cards, auto post, switches', 'Card, Auto post, Switch'),
  t_card: L('কার্ড সেটেলমেন্ট', 'Card settlement', 'Card settlement'), t_auto: L('অটো পোস্ট', 'Auto posting', 'Auto post'), t_sw: L('হিসাবের সুইচ', 'Books switches', 'Books switch'),
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), retry: L('আবার চেষ্টা করুন', 'Try again', 'আবার Try করুন'), saved: L('সেভ হয়েছে', 'Saved', 'Saved'),
  place: L('জায়গা', 'Place', 'Place'), show: L('দেখান', 'Show', 'Show'), date: L('ডেট', 'Date', 'Date'), note: L('নোট', 'Note', 'Note'), none: L('কিছু নেই', 'Nothing here', 'কিছু নেই'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), cur: L('এখন', 'Now', 'Now'), rec: L('প্রস্তাবিত', 'Recommended', 'Recommended'),
  recNote: L('প্রস্তাব মানা জরুরি নয়; আপনি যা চান সেটাই রাখতে পারেন।', 'A recommendation never blocks you; keep whatever you prefer.', 'Recommendation মানা জরুরি নয়; আপনার পছন্দই থাকবে।'),
  ownerOnly: L('এটি বদলাতে মালিক লাগবে।', 'Only the owner can change this.', 'এটা বদলাতে owner লাগবে।'),
  // card
  cardIntro: L('ব্যাংক বা মোবাইল অ্যাকাউন্টে কার্ডের টাকা এলে এখানে লিখুন। কার্ডের পাওনা কমবে, ফি খরচে যাবে।', 'Record card money that reached the bank or mobile account. The card receivable goes down and the fee is booked as a charge.', 'Card-এর টাকা bank বা mobile account-এ এলে এখানে লিখুন। Card receivable কমবে, fee খরচে যাবে।'),
  unsettled: L('এখনো না আসা কার্ডের টাকা', 'Card money not settled yet', 'এখনো না আসা card টাকা'),
  gross: L('মোট (কার্ডে কাটা)', 'Gross (charged on cards)', 'Gross (card-এ কাটা)'), fee: L('ব্যাংকের ফি', 'Bank fee', 'Bank fee'),
  mode: L('কোথায় এলো', 'Received in', 'কোথায় এলো'), bank: L('ব্যাংক', 'Bank', 'Bank'), mobile: L('মোবাইল ব্যাংকিং', 'Mobile banking', 'Mobile banking'),
  settle: L('সেটেল লিখুন', 'Record settlement', 'Settlement লিখুন'), over: L('মোট অংক না-আসা কার্ডের টাকার চেয়ে বেশি। সেভ হয়েছে হয়েছে, একবার মিলিয়ে দেখুন।', 'The gross is more than the unsettled card money. It was saved; please double check it.', 'Gross অংক unsettled card টাকার চেয়ে বেশি। Save হয়েছে, একবার মিলিয়ে দেখুন।'),
  dup: L('এটি আগেই লেখা হয়েছে (দ্বিতীয়বার নয়)।', 'This was already recorded (not twice).', 'এটা আগেই লেখা হয়েছে (দ্বিতীয়বার নয়)।'),
  hist: L('আগের সেটেলমেন্ট', 'Past settlements', 'আগের settlement'), voided: L('ভয়েড', 'Void', 'Void'), voidB: L('ভয়েড করুন', 'Void', 'Void করুন'),
  voidWhy: L('ভয়েডের কারণ লিখুন', 'Write why you void it', 'Void-এর কারণ লিখুন'), voidGo: L('হ্যাঁ, ভয়েড করুন', 'Yes, void it', 'হ্যাঁ, void করুন'),
  cancel: L('বাদ দিন', 'Cancel', 'Cancel'), voidDone: L('ভয়েড হয়েছে', 'Voided', 'Void হয়েছে'),
  // auto
  autoIntro: L('অপেক্ষায় কাগজ নিজে নিজে খাতায় তোলা। এখানে অপেক্ষায় থাকা কাগজ, বন্ধ মাসে আটকে থাকা কাগজ ও চালানোর ইতিহাস দেখা যায়।', 'Posts waiting documents to the books by itself. See what is waiting, what is held by a closed period, and the run history.', 'অপেক্ষায় document নিজে নিজে books-এ তোলা। Waiting, locked ও run history এখানে।'),
  alertOld: L('টি কাগজ নির্ধারিত দিনের বেশি অপেক্ষায়', 'documents wait longer than the alert days', 'টি document alert দিনের বেশি অপেক্ষায়'),
  alertOk: L('পুরোনো অপেক্ষায় থাকা কাগজ নেই ✓', 'No old waiting documents ✓', 'পুরোনো waiting document নেই ✓'),
  oldest: L('সবচেয়ে পুরোনো', 'Oldest', 'Oldest'), days: L('সতর্কতার দিন', 'Alert after days', 'Alert-এর দিন'),
  lockedL: L('বন্ধ মাসে আটকে', 'Held by a closed period', 'Closed period-এ আটকে'), waitCost: L('কস্ট জানা নেই বলে অপেক্ষায়', 'Waiting: cost unknown', 'Cost জানা নেই বলে অপেক্ষায়'),
  forceNote: L('বন্ধ মাসের কাগজ শুধু মালিক জোর করে পোস্ট করতে পারেন (এখনই চালান)।', 'Only the owner can force documents of a closed period (Run now).', 'Closed period-এর document শুধু owner force post করতে পারেন (Run now)।'),
  schedL: L('শিডিউলার', 'Scheduler', 'Scheduler'), lastRun: L('শেষ চালানো', 'Last run', 'Last run'), never: L('এখনো চলেনি', 'Never ran', 'এখনো চলেনি'),
  runNow: L('এখনই চালান', 'Run now', 'Run now'), cron: L('সময়সূচি (cron, ৫ ঘর)', 'Schedule (cron, 5 fields)', 'Schedule (cron, ৫ ঘর)'),
  schedOn: L('শিডিউলার চালু করুন', 'Enable scheduler', 'Scheduler চালু করুন'), schedOff: L('শিডিউলার বন্ধ করুন', 'Disable scheduler', 'Scheduler বন্ধ করুন'),
  serverNote: L('শিডিউলার সার্ভারের pg_cron লাগে। সেটি না থাকলে এখানে চালু হবে না; তখন সার্ভারে একবার সেট করতে হবে।', 'The scheduler needs pg_cron on the server. Without it this cannot start; it is a one-time server setup.', 'Scheduler-এর জন্য server-এ pg_cron লাগে। না থাকলে চালু হবে না; server-এ একবার setup করতে হবে।'),
  tickDone: L('চালানো শেষ', 'Run finished', 'Run শেষ'), posted: L('পোস্ট', 'Posted', 'Posted'), reversed: L('উল্টো', 'Reversed', 'Reversed'), errors: L('সমস্যা', 'Problems', 'সমস্যা'),
  locked: L('আটকে', 'Held', 'Held'), waiting: L('অপেক্ষায়', 'Waiting', 'Waiting'), more: L('আরও আছে — আবার চালান', 'There is more - run again', 'আরও আছে — আবার run করুন'),
  skipped: L('শিডিউলার বন্ধ, তাই কিছু চালানো হয়নি।', 'The scheduler is off, so nothing ran.', 'Scheduler বন্ধ, তাই কিছু চলেনি।'),
  noCron: L('সার্ভারে pg_cron নেই, শিডিউল করা যায়নি।', 'pg_cron is not on the server, so nothing was scheduled.', 'Server-এ pg_cron নেই, schedule হয়নি।'),
  scheduled: L('শিডিউল হয়েছে', 'Scheduled', 'Schedule হয়েছে'), unscheduled: L('শিডিউল বন্ধ হয়েছে', 'Schedule stopped', 'Schedule বন্ধ হয়েছে'),
  runsL: L('চালানোর ইতিহাস', 'Run history', 'Run history'), runsNo: L('ইতিহাস পড়ার অনুমতি এই স্ক্রিনে নেই; শেষ চালানোর সময় ওপরে দেখা যায়।', 'The run history cannot be read from this screen; the last run time is shown above.', 'Run history এই screen থেকে পড়া যায় না; শেষ run-এর সময় ওপরে আছে।'),
  // switches
  swIntro: L('সুইচ বন্ধ থাকলে আগের মতোই চলে। চালু করলে পুরোনো লেনদেনও খাতায় উঠে যেতে পারে, তাই চালুর আগে সতর্কতা দেখানো হয়।', 'A switch that is off keeps today’s behaviour. Turning one on can also post old movements, so a warning is shown before it is turned on.', 'Switch বন্ধ থাকলে আগের মতোই চলে। চালু করলে পুরোনো movement-ও post হতে পারে, তাই আগে warning দেখানো হয়।'),
  warnH: L('সতর্কতা', 'WARNING', 'সতর্কতা'), turnOn: L('চালু করুন', 'Turn on', 'Turn on'), turnOff: L('বন্ধ করুন', 'Turn off', 'Turn off'), goOn: L('বুঝেছি, চালু করুন', 'I understand, turn on', 'বুঝেছি, চালু করুন'),
  fromHint: L('YYYY-MM-DD, ফাঁকা = হিসাব শুরু থেকে', 'YYYY-MM-DD, blank = from the accounting start', 'YYYY-MM-DD, ফাঁকা = accounting start থেকে'), setB: L('ঠিক করুন', 'Set', 'Set'),
  badDate: L('ডেট ঠিক নয় (YYYY-MM-DD)', 'The date is not valid (YYYY-MM-DD)', 'Date ঠিক নয় (YYYY-MM-DD)'),
  mOff: L('বন্ধ', 'Off', 'Off'), mTag: L('স্থানভিত্তিক জোড়া', 'Location-tagged pair', 'Location-tagged pair'), mCo: L('পুরো কোম্পানি', 'Company-wide', 'Company-wide'),
  mRecv: L('গ্রহণকারী', 'Receiver', 'Receiver'), mSend: L('প্রেরক', 'Sender', 'Sender'),
};
const T = (k) => lab(X[k]);

/* the warning texts of docs/briefs_p2p3/step_D_REPORT.md, in 3 languages (English has no Bangla) */
const W = {
  backlog: L('সতর্কতা: সুইচ চালু করলে হিসাব শুরুর তারিখ (বা নিচের শুরুর তারিখ) পর্যন্ত পুরোনো stock movement আসল তারিখে খাতায় উঠে যায়। বন্ধ মাসের তারিখ আটকে থাকে (মালিক ছাড়া)। তা না চাইলে আগে নিচের শুরুর তারিখ দিন।',
    'WARNING: turning a switch on posts the backlog back to the accounting start (or the "stock movements from" date) at the original dates. Dates inside a closed period are held (locked) except for the owner. Set the from-date below first if that is not wanted.',
    'সতর্কতা: Switch চালু করলে accounting start (বা নিচের from-date) পর্যন্ত backlog আসল তারিখে post হয়। Closed period-এর তারিখ আটকে থাকে (owner ছাড়া)। না চাইলে আগে নিচের from-date দিন।'),
  opening: L('সতর্কতা: স্টক যদি আগেই শুরুর জের (acct_opening) এর মধ্যে থাকে, এটি চালু রাখবেন না; নইলে একই স্টক দুইবার গোনা হবে। শুধু হিসাব শুরুর তারিখ বা তার পরের opening ধরা হয়।',
    'WARNING: keep this OFF if the opening stock is already inside the opening balance (acct_opening), or it is counted twice. Only openings dated on or after the accounting start are posted.',
    'সতর্কতা: Opening stock আগেই acct_opening-এ থাকলে এটা OFF রাখুন, নইলে দুইবার গোনা হবে। শুধু accounting start-এর পরের opening ধরা হয়।'),
  transit: L('সতর্কতা: "গ্রহণকারী" দিলে ক্ষতি গ্রহণকারীর জায়গায় বসে; মালিক মিটিয়ে না দেওয়া পর্যন্ত clearing খাতায় প্রেরক +V ও গ্রহণকারী −V দেখা যাবে। "প্রেরক" একটি বিকল্প।',
    'WARNING: "receiver" books the loss at the receiving place, so the clearing account shows sender +V and receiver -V until the owner settles it. "Sender" is the alternative.',
    'সতর্কতা: "receiver" দিলে loss গ্রহণকারী place-এ বসে; owner না মেটানো পর্যন্ত clearing-এ sender +V ও receiver -V দেখা যাবে। "sender" বিকল্প।'),
  variance: L('সতর্কতা: যে পণ্যের ধরন কেনার সময় ভোগ্য খরচে যায় (stock-tracked হলেও), সেটি এই পার্থক্যের বাইরে থাকে।',
    'WARNING: an item type that is stock-tracked but booked to consumable purchases is left out of the variance.',
    'সতর্কতা: Stock-tracked হলেও যে item type কেনার সময় consumable purchase-এ যায়, সেটি variance-এর বাইরে থাকে।'),
  cost: L('খরচ (cost) জানা না থাকা সারি আন্দাজ করা হয় না; সেগুলো "খরচ জানা নেই" হিসেবে অপেক্ষায় থাকে।',
    'Rows with no known cost are never guessed; they wait as cost missing.',
    'Cost জানা না থাকা row আন্দাজ হয় না; সেগুলো cost missing হিসেবে অপেক্ষায় থাকে।'),
  tag: L('স্থানভিত্তিক জোড়া দিলে পাঠানো ও গ্রহণ আলাদা entry হয়, মাঝখানে inter-location clearing থাকে। "পুরো কোম্পানি" দিলে জোড়া পোস্ট হয় না।',
    'Location-tagged posts a send entry and a receive entry through the inter-location clearing account. Company-wide posts no pair.',
    'Location-tagged দিলে send ও receive আলাদা entry হয়, মাঝে inter-location clearing থাকে। Company-wide দিলে pair post হয় না।'),
};
const WT = (k) => lab(W[k]);

/* switches: key, kind, label, one-line effect, recommendation (function of context), why, warnings shown before ON */
const SW = [
  { key: 'acct_count_adjust', kind: 'switch', label: L('স্টক গণনার পার্থক্য খাতায়', 'Post stock count differences', 'Stock count difference খাতায়'),
    what: L('গণনায় কম বা বেশি হলে লাভ-ক্ষতির খাতায় একটি এন্ট্রি।', 'A count gain or loss becomes one entry (stock adjust account).', 'Count gain/loss-এ একটি entry (stock adjust)।'),
    rec: () => true, why: L('গণনার পার্থক্য খাতায় না উঠলে স্টকের মান আর খাতা আলাদা হয়ে যায়।', 'Without it the stock value and the books drift apart.', 'না থাকলে stock value ও books আলাদা হয়ে যায়।'), warn: ['backlog', 'cost'] },
  { key: 'acct_stock_opening', kind: 'switch', label: L('শুরুর স্টক খাতায়', 'Post opening stock', 'Opening stock খাতায়'),
    what: L('শুরুর স্টক মালিকের মূলধনের বিপরীতে খাতায়।', 'Opening stock goes to the books against owner capital.', 'Opening stock owner capital-এর against-এ।'),
    rec: () => false, why: L('শুরুর জের (acct_ওপেনিং) এ স্টক আগেই দিয়ে থাকলে বন্ধ রাখুন। আগে সেটা মিলিয়ে দেখুন।', 'Keep it off if the stock is already in the opening balance (acct_opening). Check that first.', 'Stock acct_opening-এ আগেই থাকলে off রাখুন। আগে সেটা মিলিয়ে নিন।'), warn: ['opening', 'backlog'] },
  { key: 'acct_issue_out', kind: 'switch', label: L('নিজের কাজে স্টক বের করা', 'Post own-use stock issues', 'Own-use stock issue'),
    what: L('স্টক issue-এ খরচ ধরা হয়, স্টক কমে।', 'An issue is booked as an expense and lowers the stock.', 'Issue-এ expense ধরা হয়, stock কমে।'),
    rec: () => true, why: L('না হলে issue শুধু স্টক কমায়, খরচ হিসাবে আসে না।', 'Otherwise an issue lowers stock but never shows as an expense.', 'না হলে issue শুধু stock কমায়, expense আসে না।'), warn: ['backlog', 'cost'] },
  { key: 'acct_transfer_mode', kind: 'choice', choices: [['off', 'mOff'], ['location_tagged', 'mTag'], ['company_wide', 'mCo']], label: L('স্টক ট্রান্সফারের হিসাব', 'Stock transfer accounting', 'Stock transfer accounting'),
    what: L('জায়গা থেকে জায়গায় মাল পাঠালে খাতায় কী হবে।', 'What the books do when stock moves between places.', 'Place থেকে place-এ stock গেলে books-এ কী হবে।'),
    rec: (c) => (c.places > 1 ? 'location_tagged' : 'off'), why: L('একের বেশি জায়গা থাকলে জায়গা-ভিত্তিক জোড়া ভালো; একটাই জায়গা হলে দরকার নেই।', 'With more than one place, location-tagged is the usual choice; with one place it is not needed.', 'একের বেশি place থাকলে location_tagged ভালো; একটাই হলে দরকার নেই।'), warn: ['tag', 'backlog'] },
  { key: 'acct_transit_loss', kind: 'switch', label: L('পথে কম পৌঁছানো মাল', 'Post stock short in transit', 'Transit-এ কম পৌঁছানো stock'),
    what: L('গ্রহণের সময় কম পেলে কমতির কস্ট আলাদা খাতে।', 'A short receipt puts the missing cost to the transit loss account.', 'Short receipt-এ missing cost transit loss খাতে।'),
    rec: (c) => c.mode !== 'off', why: L('ট্রান্সফারের হিসাব চালু থাকলে এটিও চালু রাখা ভালো।', 'Best on when transfer accounting is on.', 'Transfer accounting চালু থাকলে এটাও on রাখা ভালো।'), warn: ['transit', 'backlog'] },
  { key: 'acct_transit_loss_at', kind: 'choice', choices: [['receiver', 'mRecv'], ['sender', 'mSend']], label: L('পথে ক্ষতি কোন জায়গার', 'Which place carries a transit loss', 'Transit loss কোন place-এর'),
    what: L('শুধু পথের ক্ষতি চালু থাকলে কাজ করে।', 'Used only when transit loss posting is on.', 'শুধু transit loss on থাকলে কাজ করে।'),
    rec: () => 'receiver', why: L('সাধারণ পছন্দ: গ্রহণকারী।', 'The usual choice: receiver.', 'সাধারণ পছন্দ: receiver।'), warn: ['transit'] },
  { key: 'acct_purchase_variance', kind: 'switch', label: L('কেনা ফেরতের দামের পার্থক্য', 'Post purchase return variance', 'Purchase return variance'),
    what: L('ফেরতে গড় কস্ট আর বিলের প্রাইসের পার্থক্য আলাদা খাতে।', 'The difference between average cost and bill price on a return goes to its own account.', 'Return-এ avg cost ও bill price-এর difference আলাদা খাতে।'),
    rec: () => true, why: L('না হলে ফেরতের পর স্টকের মান আর খাতা মিলবে না।', 'Without it, stock value and books differ after a return.', 'না হলে return-এর পর stock value ও books মিলবে না।'), warn: ['variance', 'backlog'] },
  { key: 'acct_stock_moves_from', kind: 'text', label: L('স্টক এন্ট্রি শুরুর তারিখ', 'Stock movements from', 'Stock movement শুরুর date'),
    what: L('এর আগের stock movement খাতায় তোলা হবে না।', 'Older stock movements are left out.', 'এর আগের stock movement তোলা হবে না।'),
    rec: () => '', why: L('সুইচ দেরিতে চালালে বড় backlog এড়াতে একটা ডেট দিন। না দিলে হিসাব শুরু থেকে।', 'If you turn switches on late, set a date to avoid a big backlog. Blank = from the accounting start.', 'দেরিতে switch চালালে backlog এড়াতে date দিন। ফাঁকা = accounting start থেকে।'), warn: [] },
];

/* server error codes (and Postgres / network messages) -> readable 3-language text. English has no Bangla. */
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'),
  'not allowed': L('অনুমতি নেই', 'Not allowed', 'অনুমতি নেই'),   // the server raises it with a space
  bad_amount: L('অংক ঠিক নয় (০ এর বেশি লাগবে)', 'The amount is not valid (it must be above 0)', 'Amount ঠিক নয় (০-র বেশি লাগবে)'),
  bad_fee: L('ফি ঠিক নয় (০ বা বেশি, মোটের চেয়ে কম)', 'The fee is not valid (0 or more, less than the gross)', 'Fee ঠিক নয় (০ বা বেশি, gross-এর কম)'),
  bad_mode: L('কোথায় এলো তা ঠিক নয়', 'The receiving account type is not valid', 'Mode ঠিক নয়'),
  bad_date: L('ডেট ঠিক নয় (ভবিষ্যতের ডেট হয় না)', 'The date is not valid (not in the future)', 'Date ঠিক নয় (future হয় না)'),
  bad_cron: L('সময়সূচি ঠিক নয় (৫ ঘর, যেমন */15 * * * *)', 'The schedule is not valid (5 fields, like */15 * * * *)', 'Schedule ঠিক নয় (৫ ঘর, যেমন */15 * * * *)'),
  bad_location: L('জায়গা ঠিক নয়', 'The place is not valid', 'Place ঠিক নয়'),
  client_id_taken: L('একই অনুরোধ আরেকজনের', 'That request belongs to someone else', 'Request অন্য কারও'),
  not_found: L('পাওয়া যায়নি', 'Not found', 'পাওয়া যায়নি'),
  note_needed: L('কারণ লিখুন', 'Write the reason', 'কারণ লিখুন'),
  data_needed: L('হিসাব শুরুর ডেট দেওয়া হয়নি; আগে Accounts পাতায় ডেট দিন', 'The accounting start date is not set; set it on the Accounts page first', 'Accounting start date দেওয়া হয়নি; আগে Accounts পাতায় date দিন'),
  accounting_off: L('অ্যাকাউন্টিং বন্ধ আছে', 'Accounting is switched off', 'Accounting বন্ধ আছে'),
  period_closed: L('এই মাস বন্ধ; মালিকের অনুমতি লাগবে', 'This period is closed; the owner is needed', 'এই মাস বন্ধ; owner লাগবে'),
  locked: L('এই মাস বন্ধ; মালিকের অনুমতি লাগবে', 'This period is closed; the owner is needed', 'এই মাস বন্ধ; owner লাগবে'),
  scheduler_off: L('শিডিউলার বন্ধ', 'The scheduler is off', 'Scheduler বন্ধ'),
  pg_cron_missing: L('সার্ভারে pg_cron নেই', 'pg_cron is not on the server', 'Server-এ pg_cron নেই'),
  'does not exist': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase85 লাগবে)', 'The server does not have this yet (phase85 is needed)', 'Server-এ এটা এখনো নেই (phase85 লাগবে)'),
  'Could not find the function': L('সার্ভারে এই সুবিধা এখনো বসানো হয়নি (phase85 লাগবে)', 'The server does not have this yet (phase85 is needed)', 'Server-এ এটা এখনো নেই (phase85 লাগবে)'),
  'Failed to fetch': L('ইন্টারনেট নেই বা সার্ভার পাওয়া যায়নি; আবার চেষ্টা করুন', 'No internet or the server did not answer; try again', 'Internet নেই বা server পাওয়া যায়নি; আবার try করুন'),
  NetworkError: L('ইন্টারনেট নেই বা সার্ভার পাওয়া যায়নি; আবার চেষ্টা করুন', 'No internet or the server did not answer; try again', 'Internet নেই বা server পাওয়া যায়নি; আবার try করুন'),
};
const eText = (e) => {
  const m = String((e && e.message) || e || '');
  const k = Object.keys(ERR).find((x) => m.includes(x));
  return k ? lab(ERR[k]) : (m || 'error');
};

/* state */
const D = { tab: 'card', st: null, rules: {}, loc: null, card: null, alert: null, runs: undefined, clientId: null, tickOut: null, ready: false, err: null };
const locs = () => (B.liveLocs ? B.liveLocs((B.ENV && B.ENV.locs) || []) : ((B.ENV && B.ENV.locs) || []));
const locName = (l) => (S.lang === 'en' ? (l.name_en || l.name_bn) : (l.name_bn || l.name_en)) || String(l.id);
const isOwner = () => !!((D.st && D.st.owner) || (S.ctx && S.ctx.is_owner));
const isMgr = () => !!((D.st && D.st.can_manage) || isOwner());
const rv = (k) => { const r = D.rules[k]; if (!r) return undefined; return r.value === null || r.value === undefined ? r.default_value : r.value; };
const rvTxt = (k) => { let v = rv(k); if (typeof v === 'string' && /^".*"$|^(true|false)$/.test(v)) { try { v = JSON.parse(v); } catch (e) { /* plain text */ } } return v; };
const asOn = (v) => v === true || v === 'true';
const rpc = async (fn, args) => { const r = await sb.rpc(fn, args || {}); if (r.error) throw r.error; return r.data; };
const ctxNow = () => ({ places: locs().length, mode: rvTxt('acct_transfer_mode') || 'off' });

/* ---------- render pieces (tested with mocked data) ---------- */
function tabs() {
  return `<div class="row wrap" role="tablist">${[['card', 't_card'], ['auto', 't_auto'], ['sw', 't_sw']].map(([k, l]) => `<button type="button" role="tab" class="mini ${D.tab === k ? 'primary' : ''}" aria-selected="${D.tab === k}" data-act="dg_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>`;
}
function alertLine(a) {
  if (!a || a.data_needed) return '';
  return a.alert ? `<div class="notice warn" data-dg="alert">${esc(a.old_count + ' ' + T('alertOld'))} · ${esc(T('oldest'))}: ${esc(a.oldest || '-')}</div>`
    : `<div class="notice ok" data-dg="alert">${esc(T('alertOk'))}</div>`;
}
function cardTab() {
  const ls = locs();
  let h = `<p class="muted">${esc(T('cardIntro'))}</p>`;
  h += `<label for="dg_loc">${esc(T('place'))}</label><div class="row"><select id="dg_loc">${ls.map((l) => `<option value="${esc(l.id)}"${String(l.id) === String(D.loc) ? ' selected' : ''}>${esc(locName(l))}</option>`).join('')}</select><button type="button" class="mini" data-act="dg_lshow">${esc(T('show'))}</button></div>`;
  if (D.card) h += `<div class="card"><div class="muted">${esc(T('unsettled'))}</div><b data-dg="unsettled">${esc(money(D.card.unsettled))}</b></div>`;
  if (isMgr()) {
    h += `<div class="card stack"><label for="dg_cdate">${esc(T('date'))}</label><input id="dg_cdate" type="date" value="${esc(today())}" max="${esc(today())}">
      <label for="dg_cgross">${esc(T('gross'))}</label><input id="dg_cgross" inputmode="decimal" autocomplete="off">
      <label for="dg_cfee">${esc(T('fee'))}</label><input id="dg_cfee" inputmode="decimal" autocomplete="off" value="0">
      <label for="dg_cmode">${esc(T('mode'))}</label><select id="dg_cmode"><option value="bank">${esc(T('bank'))}</option><option value="mobile">${esc(T('mobile'))}</option></select>
      <label for="dg_cnote">${esc(T('note'))}</label><input id="dg_cnote" autocomplete="off">
      <button type="button" class="primary full" data-act="dg_csettle">${esc(T('settle'))}</button><div id="dg_cout" class="muted" aria-live="polite"></div></div>`;
  }
  const rows = (D.card && D.card.rows) || [];
  h += `<h3>${esc(T('hist'))}</h3>` + (rows.length ? rows.slice(0, 50).map((r) => `<div class="card stack" data-dg="crow"><div class="row between"><b>${esc(String(r.date))}</b><span class="chip ${r.status === 'void' ? 'warn' : ''}">${esc(r.status === 'void' ? T('voided') : money(r.net))}</span></div>
    <div class="muted">${esc(T('gross'))} ${esc(fm(r.gross))} · ${esc(T('fee'))} ${esc(fm(r.fee))} · ${esc(r.bank_mode === 'mobile' ? T('mobile') : T('bank'))}</div>${r.note ? `<div class="muted">${esc(r.note)}</div>` : ''}
    ${isMgr() && r.status !== 'void' ? `<button type="button" class="mini" data-act="dg_cvoid" data-v="${esc(r.id)}">${esc(T('voidB'))}</button>` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`);
  return h;
}
function tickBox(o) {
  if (!o) return '';
  if (o.skipped) return `<div class="notice warn">${esc(T('skipped'))}</div>`;
  if (o.data_needed) return `<div class="notice bad">${esc(lab(ERR.data_needed))}</div>`;
  if (o.error) return `<div class="notice bad">${esc(eText(o.error))}</div>`;
  return `<div class="notice ok" data-dg="tick"><b>${esc(T('tickDone'))}</b><br>${esc(T('posted'))} ${esc(o.posted)} · ${esc(T('reversed'))} ${esc(o.reversed)} · ${esc(T('errors'))} ${esc(o.errors)} · ${esc(T('locked'))} ${esc(o.locked)} · ${esc(T('waiting'))} ${esc(o.waiting)}${o.more ? `<br>${esc(T('more'))}` : ''}</div>`;
}
function autoTab() {
  const a = D.alert || {}; const sch = a.scheduler || {};
  let h = `<p class="muted">${esc(T('autoIntro'))}</p>`;
  if (a.data_needed) h += `<div class="notice warn">${esc(lab(ERR.data_needed))}</div>`;
  else {
    h += alertLine(a);
    h += `<div class="card stack"><div class="muted">${esc(T('days'))}: ${esc(a.days)}</div><div>${esc(T('lockedL'))}: <b>${esc(a.locked_count || 0)}</b></div><div>${esc(T('waitCost'))}: <b>${esc(a.waiting_cost || 0)}</b></div>`;
    (a.locked || []).slice(0, 20).forEach((x) => { h += `<div class="muted" data-dg="lockrow">${esc(String(x.date))} · ${esc(x.source_type)} ${x.reversal ? '↩ ' : ''}${esc(x.memo || '')}</div>`; });
    if ((a.locked_count || 0) > 0) h += `<div class="muted">${esc(T('forceNote'))}</div>`;
    h += '</div>';
  }
  h += `<div class="card stack"><div class="row between"><b>${esc(T('schedL'))}</b><span class="chip ${sch.on ? '' : 'warn'}">${esc(sch.on ? T('on') : T('off'))}</span></div><div class="muted">${esc(T('lastRun'))}: ${esc(sch.last_run ? String(sch.last_run).replace('T', ' ').slice(0, 16) : T('never'))}</div><div class="muted">${esc(T('serverNote'))}</div>`;
  if (isOwner()) {
    h += `<label for="dg_cron">${esc(T('cron'))}</label><input id="dg_cron" autocomplete="off" value="*/15 * * * *">
      <div class="row"><button type="button" class="full primary" data-act="dg_schedon">${esc(T('schedOn'))}</button><button type="button" class="full" data-act="dg_schedoff">${esc(T('schedOff'))}</button></div>
      <button type="button" class="full" data-act="dg_tick">${esc(T('runNow'))}</button>`;
  } else h += `<div class="muted">${esc(T('ownerOnly'))}</div>`;
  h += `<div id="dg_tout" aria-live="polite">${tickBox(D.tickOut)}</div></div>`;
  h += `<h3>${esc(T('runsL'))}</h3>`;
  if (D.runs === null) h += `<p class="muted" data-dg="runsno">${esc(T('runsNo'))}</p>`;
  else if (Array.isArray(D.runs)) h += D.runs.length ? D.runs.map((r) => `<div class="card" data-dg="run"><b>${esc(String(r.ran_at).replace('T', ' ').slice(0, 16))}</b> · ${esc(T('posted'))} ${esc(r.posted)} · ${esc(T('reversed'))} ${esc(r.reversed)} · ${esc(T('errors'))} ${esc(r.errors)} · ${esc(T('locked'))} ${esc(r.locked)}${r.note ? ` · ${esc(r.note)}` : ''}</div>`).join('') : `<p class="muted">${esc(T('none'))}</p>`;
  return h;
}
function curShow(s) {
  const v = rvTxt(s.key);
  if (s.kind === 'switch') return asOn(v) ? T('on') : T('off');
  if (s.kind === 'choice') { const c = s.choices.find((x) => x[0] === v); return c ? T(c[1]) : String(v == null ? '' : v); }
  return v ? String(v) : '-';
}
function recShow(s, r) {
  if (s.kind === 'switch') return r ? T('on') : T('off');
  if (s.kind === 'choice') { const c = s.choices.find((x) => x[0] === r); return c ? T(c[1]) : String(r); }
  return r ? String(r) : '-';
}
function swTab() {
  const c = ctxNow(); const own = isOwner();
  let h = `<p class="muted">${esc(T('swIntro'))}</p><p class="muted">${esc(T('recNote'))}</p>`;
  if (!own) h += `<div class="notice warn">${esc(T('ownerOnly'))}</div>`;
  h += SW.map((s) => {
    const r = s.rec(c); const v = rvTxt(s.key);
    const same = s.kind === 'switch' ? asOn(v) === r : s.kind === 'choice' ? v === r : (v || '') === (r || '');
    let ctl = '';
    if (own) {
      if (s.kind === 'switch') ctl = `<button type="button" class="tog ${asOn(v) ? 'on' : ''}" data-act="dg_sw" data-v="${s.key}" data-on="${asOn(v) ? 1 : 0}">${esc(asOn(v) ? T('turnOff') : T('turnOn'))}</button>`;
      else if (s.kind === 'choice') ctl = `<div class="row wrap">${s.choices.map(([val, lk]) => `<button type="button" class="mini ${v === val ? 'primary' : ''}" data-act="dg_choice" data-v="${s.key}" data-c="${val}">${esc(T(lk))}</button>`).join('')}</div>`;
      else ctl = `<label for="dg_t_${s.key}">${esc(T('fromHint'))}</label><div class="row"><input id="dg_t_${s.key}" inputmode="numeric" placeholder="YYYY-MM-DD" value="${esc(v || '')}"><button type="button" class="mini" data-act="dg_text" data-v="${s.key}">${esc(T('setB'))}</button></div>`;
    }
    const wn = s.key === 'acct_stock_opening' ? `<div class="notice warn" data-dg="warn">${esc(WT('opening'))}</div>` : '';
    return `<div class="card stack" data-dg="sw" data-key="${s.key}"><b>${esc(lab(s.label))}</b><div class="muted">${esc(lab(s.what))}</div>
      <div class="row wrap"><span class="chip">${esc(T('cur'))}: ${esc(curShow(s))}</span><span class="chip ${same ? '' : 'warn'}">${esc(T('rec'))}: ${esc(recShow(s, r))}</span></div>
      <div class="muted">${esc(lab(s.why))}</div>${wn}${ctl}</div>`;
  }).join('');
  return h;
}
function body() {
  if (D.err) return `${tabs()}<div class="notice bad" data-state="error">${esc(D.err)}</div><button type="button" class="full" data-act="dg_retry">${esc(T('retry'))}</button>`;
  if (!D.ready) return `${tabs()}<p class="muted center pad" data-state="loading">${esc(T('loading'))}</p>`;
  return tabs() + (D.tab !== 'auto' ? alertLine(D.alert).replace(/data-dg="alert"/, 'data-dg="alert-top"') : '') + (D.tab === 'card' ? cardTab() : D.tab === 'auto' ? autoTab() : swTab());
}
function draw() { const el = $('#dg_body'); if (el) el.innerHTML = body(); }

/* ---------- loading ---------- */
async function loadCard() {
  if (D.loc == null) { const l = locs()[0]; D.loc = l ? l.id : null; }
  D.card = D.loc == null ? { unsettled: 0, rows: [] } : await rpc('card_settlement_list', { p_loc: Number(D.loc), p_from: null, p_to: null });
}
async function loadAlert() { try { D.alert = await rpc('acct_pending_alert85', { p_limit: 50 }); } catch (e) { D.alert = null; } }   // the alert is advice: a failure must not hide the screen
async function loadAuto() {
  await loadAlert();
  D.runs = null;
  try { const f = await sb.rpc('acct_autopost_runs_list', { p_limit: 20 }); if (!f.error && Array.isArray(f.data)) D.runs = f.data; } catch (e) { /* bos94: phase94 not pasted yet - fall back to the table read below */ }
  if (D.runs === null) { try { const r = await sb.from('acct_autopost_runs85').select('*').order('ran_at', { ascending: false }).limit(20); D.runs = r.error ? null : (r.data || []); } catch (e) { D.runs = null; } }
}
async function loadRules() {
  const r = await sb.from('rules').select('key,value,default_value').in('key', SW.map((s) => s.key).concat(['acct_scheduler_on']));
  if (r.error) throw r.error;
  D.rules = {}; (r.data || []).forEach((x) => { D.rules[x.key] = x; });
}
async function loadAll() {
  D.err = null;
  try { D.st = await rpc('acct_status'); } catch (e) { /* the screen still works; owner is also read from the session */ }
  const jobs = [loadRules()];
  if (D.tab === 'card') jobs.push(loadCard(), loadAlert());
  if (D.tab === 'auto') jobs.push(loadAuto());
  if (D.tab === 'sw') jobs.push(loadAlert());
  await Promise.all(jobs);
  D.ready = true;
}
async function refresh() { try { await loadAll(); } catch (e) { D.err = eText(e); } draw(); }

/* ---------- actions ---------- */
async function setRule(key, value) { await rpc('set_rule', { p_key: key, p_value: value }); D.rules[key] = Object.assign(D.rules[key] || { key }, { value }); }
function warnSheet(s, goAct, extra) {
  const ws = (s.warn || []).map((k) => `<div class="notice warn" data-dg="warn">${esc(WT(k))}</div>`).join('');
  openSheet(`<div class="stack"><h3>${esc(T('warnH'))}: ${esc(lab(s.label))}</h3>${ws}
    <div class="row"><button type="button" class="full" data-act="dg_swcancel">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="${goAct}" data-v="${s.key}"${extra || ''}>${esc(T('goOn'))}</button></div></div>`);
}
Object.assign(H, {
  dg_tab: async (a) => { D.tab = a.dataset.v; D.ready = false; draw(); await refresh(); },
  dg_retry: async () => { D.ready = false; D.err = null; draw(); await refresh(); },
  dg_lshow: async () => { D.loc = ($('#dg_loc') || {}).value || D.loc; D.clientId = null; try { await loadCard(); } catch (e) { D.err = eText(e); } draw(); },
  dg_csettle: async () => {
    const out = $('#dg_cout'); const say = (m) => { if (out) out.textContent = m; };
    const gross = nnum(($('#dg_cgross') || {}).value), fee = nnum(($('#dg_cfee') || {}).value);
    if (!(gross > 0)) return say(lab(ERR.bad_amount));
    if (!(fee >= 0 && fee < gross)) return say(lab(ERR.bad_fee));
    if (!D.clientId) D.clientId = rid();   // kept until it succeeds, so a repeated tap or a retry never records twice
    try {
      const r = await rpc('card_settle', { p_loc: Number(D.loc), p_date: ($('#dg_cdate') || {}).value || today(), p_gross: gross, p_fee: fee, p_note: (($('#dg_cnote') || {}).value || '').trim() || null, p_client: D.clientId, p_bank_mode: ($('#dg_cmode') || {}).value || 'bank' });
      D.clientId = null;
      toast(r && r.dup ? T('dup') : T('saved'));
      await loadCard(); draw();
      const o2 = $('#dg_cout'); if (o2 && r && r.over) o2.textContent = T('over');
    } catch (e) { say(eText(e)); }
  },
  dg_cvoid: (a) => {
    openSheet(`<div class="stack"><h3>${esc(T('voidB'))}</h3><label for="dg_vnote">${esc(T('voidWhy'))}</label><input id="dg_vnote" autocomplete="off"><div id="dg_vout" class="muted"></div>
      <div class="row"><button type="button" class="full" data-act="dg_swcancel">${esc(T('cancel'))}</button><button type="button" class="full primary" data-act="dg_cvgo" data-v="${esc(a.dataset.v)}">${esc(T('voidGo'))}</button></div></div>`);
  },
  dg_cvgo: async (a) => {
    const note = (($('#dg_vnote') || {}).value || '').trim(); const out = $('#dg_vout');
    if (!note) { if (out) out.textContent = lab(ERR.note_needed); return; }
    try { await rpc('card_settle_void', { p_id: a.dataset.v, p_note: note }); closeSheet(); toast(T('voidDone')); await loadCard(); draw(); } catch (e) { if (out) out.textContent = eText(e); }
  },
  dg_swcancel: () => closeSheet(),
  dg_tick: async () => {
    try { D.tickOut = await rpc('acct_autopost_tick'); await loadAuto(); } catch (e) { D.tickOut = { error: (e && e.message) || String(e) }; }
    draw();
  },
  dg_schedon: async () => {
    const cron = (($('#dg_cron') || {}).value || '').trim();
    try {
      const r = await rpc('acct_scheduler_enable', { p_cron: cron });
      if (r && r.scheduled === false) toast(r.reason === 'pg_cron_missing' ? T('noCron') : T('skipped')); else toast(T('scheduled'));
      await refresh();
    } catch (e) { toast(eText(e)); }
  },
  dg_schedoff: async () => { try { await rpc('acct_scheduler_disable'); toast(T('unscheduled')); await refresh(); } catch (e) { toast(eText(e)); } },
  dg_sw: async (a) => {
    const s = SW.find((x) => x.key === a.dataset.v); if (!s) return;
    if (a.dataset.on === '1') { try { await setRule(s.key, false); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); } return; }
    warnSheet(s, 'dg_swgo');   // turning ON asks first: a backlog may post
  },
  dg_swgo: async (a) => { try { await setRule(a.dataset.v, true); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); } },
  dg_choice: async (a) => {
    const s = SW.find((x) => x.key === a.dataset.v); if (!s) return;
    const c = a.dataset.c;
    if (s.key === 'acct_transfer_mode' && c !== 'off' && rvTxt(s.key) === 'off') return warnSheet(s, 'dg_chgo', ` data-c="${esc(c)}"`);
    try { await setRule(s.key, c); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); }
  },
  dg_chgo: async (a) => { try { await setRule(a.dataset.v, a.dataset.c); closeSheet(); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); } },
  dg_text: async (a) => {
    const el = $('#dg_t_' + a.dataset.v); const v = ((el || {}).value || '').trim();
    if (v && !/^\d{4}-\d{2}-\d{2}$/.test(v)) return toast(T('badDate'));
    try { await setRule(a.dataset.v, v); toast(T('saved')); await refresh(); } catch (e) { toast(eText(e)); }
  },
});

async function viewBooks85() {
  D.ready = false; D.err = null; D.clientId = null;
  shell(T('title'), '<div id="dg_body"></div>', true);
  draw(); await refresh();
}
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { books85: viewBooks85 });
B.books85 = { SW, ERR, W, X, eText, D, body, tabs, cardTab, autoTab, swTab, tickBox, rec: (key, ctx) => { const s = SW.find((x) => x.key === key); return s ? s.rec(ctx || ctxNow()) : undefined; } };
})();
