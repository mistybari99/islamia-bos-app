/* Islamia BOS · Customers and customer tiers (#/customers, #/tiers).
   #/customers: the customer master (search, collapsed filters, tier chips), add / edit with duplicate-mobile handling, a ⋮ menu per customer
   (change tier + reason, issue gift, adjust points, open dues, call / WhatsApp, switch off) and the customer profile (totals, last purchase, tier history, gifts, points, dues).
   #/tiers (owner): manage the tiers (add / edit / reorder / retire), the benefits of each tier (discount, cap, points multiplier, perks, birthday gift), the automatic-upgrade
   thresholds with a PREVIEW (dry run) before applying, the loyalty / gift / tier-discount switches and numbers, gift rules, and a tier-usage report.
   Server (supabase/phase43.sql): customer_directory, customer_profile, customer_save, customer_set_tier, customer_points_adjust, customer_points_redeem, gifts_due, gift_claim,
   gift_issue, tier_save, tier_reorder, gift_rule_save, customer_tier_refresh, tier_usage_report, set_rule. The page only shows; the server decides every right and every number. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell, openSheet, closeSheet, fmt, H } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const r2 = (n) => Math.round(Number(n) * 100) / 100;
const money = (n) => '৳ ' + fmt(r2(n));
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const rid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }));
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const dshort = (iso) => (iso ? String(iso).slice(0, 10) : '—');
const tn = (t) => (!t ? '' : S.lang === 'en' ? (t.name_en || t.name_bn) : (t.name_bn || t.name_en));

const X = {
  title: L('গ্রাহক', 'Customers', 'Customer'), tiersTitle: L('গ্রাহকের স্তর ও সুবিধা', 'Customer tiers & benefits', 'Customer tier ও সুবিধা'),
  search: L('নাম বা মোবাইল দিয়ে খুঁজুন', 'Search by name or mobile', 'নাম বা mobile দিয়ে খুঁজুন'), add: L('＋ নতুন গ্রাহক', '＋ New customer', '＋ নতুন Customer'),
  filters: L('ফিল্টার', 'Filters', 'Filter'), allTiers: L('সব স্তর', 'All tiers', 'সব tier'), allTypes: L('খুচরা ও পাইকারি', 'Retail & wholesale', 'Retail ও Wholesale'),
  retail: L('খুচরা', 'Retail', 'Retail'), wholesale: L('পাইকারি', 'Wholesale', 'Wholesale'), hasDue: L('বাকি আছে', 'Has a due', 'Due আছে'), bdayMonth: L('এই মাসে জন্মদিন', 'Birthday this month', 'এই মাসে birthday'),
  stActive: L('চালু গ্রাহক', 'Active customers', 'Active customer'), stInactive: L('বন্ধ গ্রাহক', 'Switched-off customers', 'বন্ধ customer'), stAll: L('সব', 'All', 'সব'),
  count: L('জন', 'customers', 'জন'), more: L('আরও দেখান', 'Show more', 'আরও দেখান'), none: L('কোনো গ্রাহক মেলেনি', 'No customer matches', 'কোনো customer মেলেনি'),
  due: L('বাকি', 'Due', 'Due'), spent: L('মোট কেনা', 'Spent', 'মোট কেনা'), last: L('শেষ কেনা', 'Last purchase', 'শেষ কেনা'), orders: L('অর্ডার', 'Orders', 'Order'), avg: L('গড় বিল', 'Average bill', 'গড় bill'),
  mobile: L('মোবাইল নম্বর', 'Mobile number', 'Mobile নম্বর'), name: L('নাম', 'Name', 'নাম'), tier: L('স্তর', 'Tier', 'Tier'), type: L('ধরন', 'Type', 'ধরন'),
  birthday: L('জন্মদিন', 'Birthday', 'Birthday'), anniv: L('বার্ষিকী', 'Anniversary', 'Anniversary'), address: L('ঠিকানা', 'Address', 'ঠিকানা'), notes: L('নোট', 'Notes', 'Note'),
  source: L('কীভাবে এলো', 'How they came', 'কীভাবে এলো'), wa: L('হোয়াটসঅ্যাপ নম্বর', 'WhatsApp number', 'WhatsApp নম্বর'), limit: L('বাকির সীমা (৳)', 'Credit limit (৳)', 'Due limit (৳)'),
  lock: L('স্তর তালা দিন (নিজে থেকে বদলাবে না)', 'Lock the tier (no automatic change)', 'Tier lock (auto বদলাবে না)'), locked: L('তালা দেওয়া', 'Locked', 'Locked'),
  save: L('সংরক্ষণ', 'Save', 'Save'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ', 'Close', 'Close'), edit: L('সম্পাদনা', 'Edit', 'Edit'),
  newTitle: L('নতুন গ্রাহক', 'New customer', 'নতুন Customer'), editTitle: L('গ্রাহক সম্পাদনা', 'Edit customer', 'Customer Edit'),
  dupOpen: L('এই মোবাইল আগে থেকেই আছে — খুলে দিলাম', 'This mobile is already registered — opened it', 'এই mobile আগেই আছে — খুলে দিলাম'),
  menuChangeTier: L('স্তর বদলান', 'Change tier', 'Tier বদলান'), menuGift: L('উপহার দিন', 'Issue a gift', 'Gift দিন'), menuPoints: L('পয়েন্ট ঠিক করুন', 'Adjust points', 'Points ঠিক করুন'),
  menuDues: L('বাকির খাতা খুলুন', 'Open dues', 'Due খাতা'), menuCall: L('ফোন করুন', 'Call', 'Call'), menuWa: L('হোয়াটসঅ্যাপ', 'WhatsApp', 'WhatsApp'), menuOff: L('গ্রাহক বন্ধ করুন', 'Switch customer off', 'Customer বন্ধ'),
  menuOn: L('গ্রাহক চালু করুন', 'Switch customer on', 'Customer চালু'), menuOpen: L('প্রোফাইল দেখুন', 'Open profile', 'Profile দেখুন'),
  reason: L('কারণ (অন্তত ৩ অক্ষর)', 'Reason (at least 3 characters)', 'কারণ (অন্তত ৩ অক্ষর)'), history: L('স্তরের ইতিহাস', 'Tier history', 'Tier ইতিহাস'), gifts: L('উপহার', 'Gifts', 'Gift'),
  points: L('পয়েন্ট', 'Points', 'Points'), recent: L('সাম্প্রতিক বিক্রি', 'Recent sales', 'সাম্প্রতিক sale'), since: L('গ্রাহক হয়েছেন', 'Customer since', 'Customer since'),
  auto: L('নিজে থেকে', 'automatic', 'auto'), manual: L('হাতে', 'by hand', 'হাতে'), by: L('করেছেন', 'by', 'করেছেন'),
  giftDue: L('উপহার পাওনা', 'Gifts due', 'Gift পাওনা'), claim: L('হাতে দিলাম', 'Handed over', 'হাতে দিলাম'), claimed: L('দেওয়া হয়েছে', 'Given', 'দেওয়া হয়েছে'), valid: L('মেয়াদ', 'valid until', 'মেয়াদ'),
  giftBn: L('উপহারের নাম (বাংলা)', 'Gift (Bangla)', 'Gift (বাংলা)'), giftEn: L('উপহারের নাম (ইংরেজি)', 'Gift (English)', 'Gift (English)'), giftVal: L('মূল্য (৳, ঐচ্ছিক)', 'Value (৳, optional)', 'Value (৳, optional)'),
  giftUntil: L('কবে পর্যন্ত (ঐচ্ছিক)', 'Valid until (optional)', 'Valid until (optional)'), issue: L('দিন', 'Issue', 'Issue'),
  delta: L('পয়েন্ট বাড়ান (+) বা কমান (−)', 'Points to add (+) or remove (−)', 'Points add (+) / remove (−)'), balance: L('এখন পয়েন্ট', 'Points now', 'এখন Points'),
  redeem: L('পয়েন্ট ভাঙান', 'Redeem points', 'Points ভাঙান'), redeemN: L('কত পয়েন্ট', 'How many points', 'কত points'), preview: L('আগে দেখুন', 'Preview first', 'আগে দেখুন'),
  worth: L('সমান টাকা', 'worth', 'সমান টাকা'), redeemed: L('পয়েন্ট খরচ হয়েছে', 'Points redeemed', 'Points খরচ হয়েছে'), tierChanged: L('স্তর বদলেছে', 'Tier changed', 'Tier বদলেছে'),
  // tiers page
  tHint: L('স্তরের নাম বসানো আছে, কিন্তু ডিসকাউন্ট ও শর্ত সব ফাঁকা — আপনি ঠিক করুন। কিছুই নিজে থেকে চালু হয় না।', 'The tier names are in place but every discount and threshold is blank — you decide the policy. Nothing switches on by itself.', 'Tier নাম আছে, কিন্তু discount ও শর্ত ফাঁকা — আপনি ঠিক করুন। কিছু নিজে চালু হয় না।'),
  tNew: L('＋ নতুন স্তর', '＋ New tier', '＋ নতুন Tier'), tDefault: L('ডিফল্ট (ওয়াক-ইন)', 'Default (walk-in)', 'Default (walk-in)'), tRetired: L('বন্ধ', 'retired', 'বন্ধ'),
  tDisc: L('ডিসকাউন্ট %', 'Discount %', 'Discount %'), tCap: L('প্রতি বিলে সর্বোচ্চ ছাড় (৳)', 'Max discount per bill (৳)', 'প্রতি bill সর্বোচ্চ ছাড় (৳)'), tCredit: L('নতুন গ্রাহকের বাকির সীমা (৳)', 'Credit limit for new customers (৳)', 'নতুন customer Due limit (৳)'),
  tMult: L('পয়েন্ট গুণক', 'Points multiplier', 'Points গুণক'), tPerks: L('সুবিধা (স্টাফ দেখবে)', 'Perks (shown to staff)', 'Perks (staff দেখবে)'), tBgift: L('জন্মদিনের উপহার', 'Birthday gift', 'Birthday gift'),
  tSpend: L('অটো-আপগ্রেড: মোট কেনা কমপক্ষে (৳)', 'Auto-upgrade: lifetime spend at least (৳)', 'Auto-upgrade: মোট কেনা কমপক্ষে (৳)'), tOrders: L('কমপক্ষে অর্ডার', 'At least orders', 'কমপক্ষে order'),
  tOrders12: L('গত ১২ মাসে কমপক্ষে অর্ডার', 'At least orders in 12 months', 'গত ১২ মাসে কমপক্ষে order'), tMonths: L('কমপক্ষে কত মাস ধরে গ্রাহক', 'At least months as a customer', 'কমপক্ষে কত মাস'),
  tCode: L('কোড (ইংরেজি ছোট হরফ, বদলানো যায় না)', 'Code (lower case, cannot be changed later)', 'Code (lowercase, পরে বদলানো যায় না)'), tColor: L('রং', 'Colour', 'Colour'), tBadge: L('ব্যাজ (ইমোজি)', 'Badge (emoji)', 'Badge (emoji)'),
  tMakeDefault: L('এটাই ডিফল্ট স্তর (নতুন গ্রাহক এখানে)', 'Make this the default tier (new customers start here)', 'এটাই default tier'), tRetire: L('বন্ধ করুন', 'Retire', 'বন্ধ করুন'), tRestore: L('আবার চালু', 'Restore', 'আবার চালু'),
  tUp: L('উপরে', 'Up', 'Up'), tDown: L('নিচে', 'Down', 'Down'),
  swTitle: L('সুইচ ও সংখ্যা', 'Switches and numbers', 'Switch ও সংখ্যা'), swTierDisc: L('স্তরের ডিসকাউন্ট POS-এ আগে-থেকে-অনুমোদিত', 'Tier discount is pre-approved at the POS', 'Tier discount POS-এ pre-approved'),
  swAuto: L('স্তর নিজে থেকে বাড়ান', 'Move customers up automatically', 'Tier নিজে থেকে upgrade'), swDown: L('স্বয়ংক্রিয় রিফ্রেশে নামানোও চলবে', 'Automatic refresh may also move down', 'Auto refresh-এ নামানোও'),
  swPts: L('লয়্যালটি পয়েন্ট', 'Loyalty points', 'Loyalty points'), swGifts: L('গ্রাহকের উপহার', 'Customer gifts', 'Customer gifts'), on: L('চালু', 'ON', 'ON'), off: L('বন্ধ', 'OFF', 'OFF'),
  nPer100: L('প্রতি ১০০ টাকায় পয়েন্ট', 'Points per 100 taka', 'প্রতি 100 টাকায় points'), nValue: L('প্রতি পয়েন্টের মূল্য (৳)', 'Value of a point (৳)', 'প্রতি point value (৳)'), nMin: L('ভাঙাতে কমপক্ষে পয়েন্ট', 'Minimum points to redeem', 'ভাঙাতে কমপক্ষে points'),
  nWin: L('জন্মদিনের আগে-পরে কত দিন', 'Days around a birthday', 'Birthday এর আগে-পরে দিন'), nValid: L('উপহার কত দিন বৈধ', 'Days a gift stays valid', 'Gift কত দিন valid'),
  refresh: L('স্বয়ংক্রিয় স্তর রিফ্রেশ', 'Automatic tier refresh', 'Auto tier refresh'), dry: L('পরীক্ষা (কিছু লেখা হবে না)', 'Preview (writes nothing)', 'Preview (কিছু লেখা হবে না)'),
  apply: L('প্রয়োগ করুন', 'Apply these changes', 'Apply করুন'), applied: L('প্রয়োগ হয়েছে', 'Applied', 'Applied'), noChange: L('কারও স্তর বদলাবে না', 'Nobody changes tier', 'কারও tier বদলাবে না'),
  willMove: L('জনের স্তর বদলাবে', 'customers would change tier', 'জনের tier বদলাবে'), autoOffNote: L('প্রয়োগ করতে আগে "স্তর নিজে থেকে বাড়ান" চালু করুন', 'Turn "Move customers up automatically" on to apply', 'Apply করতে আগে auto সুইচ চালু করুন'),
  confirmApply: L('এই পরিবর্তনগুলো সত্যিই প্রয়োগ করবেন?', 'Really apply these changes?', 'এই পরিবর্তনগুলো সত্যিই apply করবেন?'),
  gRules: L('উপহারের নিয়ম', 'Gift rules', 'Gift নিয়ম'), gNew: L('＋ নতুন নিয়ম', '＋ New rule', '＋ নতুন নিয়ম'), gTrig: L('কখন', 'When', 'কখন'), gTier: L('কোন স্তর', 'Which tier', 'কোন tier'), gAll: L('সব স্তর', 'All tiers', 'সব tier'),
  gThr: L('সংখ্যা (বার / টাকা)', 'Number (purchases / taka)', 'সংখ্যা (বার / টাকা)'), gDays: L('বৈধ কত দিন (ঐচ্ছিক)', 'Valid days (optional)', 'Valid days (optional)'),
  usage: L('এই মাসে স্তর অনুযায়ী বিক্রি', 'This month by tier', 'এই মাসে tier অনুযায়ী'), uSales: L('বিক্রি', 'sales', 'sales'), uDisc: L('স্তরের ছাড়', 'tier discount', 'tier ছাড়'),
  ownerOnly: L('শুধু মালিক এই পাতা দেখতে পারেন', 'Only the owner can open this page', 'শুধু মালিক এই পাতা দেখতে পারেন'), noPerm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'),
};
const TRIG = { birthday: L('জন্মদিনে', 'Birthday', 'Birthday'), anniversary: L('বার্ষিকীতে', 'Anniversary', 'Anniversary'), first_purchase: L('প্রথম কেনায়', 'First purchase', 'প্রথম কেনা'),
  every_n_purchases: L('প্রতি N-তম কেনায়', 'Every N-th purchase', 'প্রতি N-তম কেনা'), spend_threshold: L('মোট কেনা এত টাকা হলে', 'Total spend reaches', 'মোট কেনা এত হলে'), manual: L('হাতে দেওয়া', 'Manual only', 'হাতে দেওয়া') };
const T = (k) => lab(X[k]);
const ERR = {
  not_allowed: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), bad_mobile: L('মোবাইল নম্বর ঠিক নয় (01XXXXXXXXX)', 'The mobile number is not valid (01XXXXXXXXX)', 'Mobile নম্বর ঠিক নয় (01XXXXXXXXX)'),
  customer_name_required: L('নাম লিখুন', 'Write the name', 'নাম লিখুন'), bad_date: L('তারিখ ঠিক নয় (ভবিষ্যতের তারিখ হয় না)', 'The date is not valid (not in the future)', 'Date ঠিক নয়'),
  bad_number: L('সংখ্যাটি ঠিক নয়', 'The number is not valid', 'সংখ্যাটি ঠিক নয়'), bad_code: L('কোড: ২-৩০টি ছোট ইংরেজি হরফ/সংখ্যা/_', 'Code: 2-30 lower-case letters, digits or _', 'Code: 2-30 ছোট হরফ/সংখ্যা/_'),
  name_required: L('একটি নাম লিখুন', 'Write a name', 'একটি নাম লিখুন'), code_exists: L('এই কোড আগেই আছে', 'This code already exists', 'এই code আগেই আছে'), tier_not_found: L('স্তর পাওয়া যায়নি', 'Tier not found', 'Tier পাওয়া যায়নি'),
  default_tier_active: L('ডিফল্ট স্তর বন্ধ করা যায় না — আগে অন্য স্তরকে ডিফল্ট করুন', 'The default tier cannot be retired — make another tier the default first', 'Default tier বন্ধ করা যায় না'),
  note_required: L('কারণ লিখুন (অন্তত ৩ অক্ষর)', 'Write a reason (at least 3 characters)', 'কারণ লিখুন (অন্তত ৩ অক্ষর)'), not_enough_points: L('এত পয়েন্ট নেই', 'Not enough points', 'এত points নেই'),
  below_min_points: L('ভাঙাতে আরও পয়েন্ট লাগবে (সর্বনিম্ন সীমা)', 'More points are needed (minimum to redeem)', 'ভাঙাতে আরও points লাগবে'), loyalty_off: L('লয়্যালটি পয়েন্ট বন্ধ আছে', 'Loyalty points are switched off', 'Loyalty points বন্ধ আছে'),
  gifts_off: L('উপহার সুবিধা বন্ধ আছে', 'Gifts are switched off', 'Gift সুবিধা বন্ধ আছে'), gift_not_due: L('এই উপহার এখন পাওনা নয়', 'This gift is not due now', 'এই gift এখন পাওনা নয়'),
  gift_expired: L('উপহারের মেয়াদ শেষ', 'This gift has expired', 'Gift এর মেয়াদ শেষ'), gift_not_found: L('উপহার পাওয়া যায়নি', 'Gift not found', 'Gift পাওয়া যায়নি'), gift_text_required: L('উপহারের নাম লিখুন', 'Write the gift', 'Gift এর নাম লিখুন'),
  threshold_required: L('এই নিয়মের জন্য একটি সংখ্যা লাগবে', 'This rule needs a number', 'এই নিয়মে একটি সংখ্যা লাগবে'), tier_auto_off: L('আগে "স্তর নিজে থেকে বাড়ান" সুইচ চালু করুন', 'Turn the automatic-upgrade switch on first', 'আগে auto সুইচ চালু করুন'),
  customer_not_found: L('গ্রাহক পাওয়া যায়নি', 'Customer not found', 'Customer পাওয়া যায়নি'), bad_color: L('রং ঠিক নয়', 'The colour is not valid', 'Colour ঠিক নয়'), bad_sale_type: L('ধরন ঠিক নয়', 'Type is not valid', 'ধরন ঠিক নয়'),
};
const eText = (e) => { const m = String((e && e.message) || ''); const k = Object.keys(ERR).find((x) => m.includes(x) || m.includes(x.replace(/_/g, ' '))); if (k) return lab(ERR[k]); if (/permission|row-level|denied/i.test(m)) return lab(ERR.not_allowed); return m || 'error'; };
const NOFN = /Could not find the function|PGRST202|schema cache|does not exist/i;

const D = { rows: [], tiers: [], q: '', fTier: '', fType: '', fDue: false, fBday: false, fStatus: 'active', shown: 50, mgr: false, canEnter: false, owner: false, cur: null, sql: true,
  loyal: false, gifts: false, rules: {}, tab: null };
const tier = (id) => D.tiers.find((t) => String(t.id) === String(id));
const chip = (t, extra) => (!t ? '' : `<span class="chip cu-tier" style="border-color:${esc(t.color)};color:${esc(t.color)}">${t.badge ? esc(t.badge) + ' ' : ''}${esc(tn(t))}</span>${extra || ''}`);

async function loadCommon() {
  if (B.loadStatic) await B.loadStatic();
  D.owner = !!(S.ctx && S.ctx.is_owner);
  D.canEnter = D.owner || !!(S.ctx && S.ctx.perms && S.ctx.perms.POS && S.ctx.perms.POS.enter);
  D.mgr = D.owner || (await A.hasAnyGrant(['customer_manage']));
  D.loyal = B.rule('loyalty_points_on', false) === true; D.gifts = B.rule('customer_gifts_on', false) === true;
  const t = await sb.from('customer_tiers').select('*').order('rank'); D.tiers = t.data || [];
}
async function loadDirectory() {
  const r = await (B.crmConsent ? B.crmConsent.directory() : sb.rpc('customer_directory')); if (r.error) { D.sql = !NOFN.test(r.error.message || ''); D.rows = []; D.err = r.error; return; }
  D.sql = true; D.err = null; D.rows = r.data || [];
}

// ---------- list ----------
function visible() {
  const q = norm(D.q).trim().toLowerCase(), mon = today().slice(5, 7);
  return D.rows.filter((c) => (D.fStatus === 'all' || (D.fStatus === 'active' ? c.active : !c.active)) && (!D.fTier || String(c.tier_id) === String(D.fTier)) && (!D.fType || c.type === D.fType)
    && (!D.fDue || Number(c.balance) > 0) && (!D.fBday || (c.birthday && String(c.birthday).slice(5, 7) === mon)) && (!q || String(c.name).toLowerCase().includes(q) || String(c.mobile).includes(q)));
}
function rowHTML(c) {
  const t = tier(c.tier_id), dueN = Number(c.balance);
  return `<div class="card item cu-row ${c.active ? '' : 'muted'}" data-act="cu_open" data-v="${esc(c.id)}"><div style="min-width:0;flex:1"><div class="nm">${esc(c.name)} ${c.type === 'wholesale' ? '◆' : ''} ${c.tier_locked ? '🔒' : ''}${c.active ? '' : ` <span class="chip bad">${esc(T('stInactive'))}</span>`}</div>
      <div class="row wrap" style="gap:6px;align-items:center">${chip(t)}<span class="muted" style="font-size:.85rem">${esc(c.mobile)}</span></div>
      <div class="muted" style="font-size:.8rem">${esc(T('spent'))}: ${money(c.spend)} · ${esc(T('last'))}: ${esc(dshort(c.last_sale))}${D.loyal ? ` · ${esc(T('points'))}: ${Number(c.points) || 0}` : ''}</div></div>
    <div class="pr">${dueN > 0 ? `<span class="chip bad">${esc(T('due'))} ${money(dueN)}</span>` : ''}<button type="button" class="mini" data-act="cu_menu" data-v="${esc(c.id)}" aria-label="menu" style="min-width:40px;min-height:40px">⋮</button></div></div>`;
}
function drawList() {
  const el = $('#cu_list'); if (!el) return;
  const rows = visible(), part = rows.slice(0, D.shown);
  const cnt = $('#cu_count'); if (cnt) cnt.textContent = `${rows.length} ${T('count')}`;
  el.innerHTML = (part.map(rowHTML).join('') || `<p class="muted center">${esc(T('none'))}</p>`) + (rows.length > part.length ? `<button class="full" data-act="cu_more">${esc(T('more'))}</button>` : '');
}
function drawPage() {
  const owing = D.rows.reduce((a, c) => a + Math.max(0, Number(c.balance) || 0), 0);
  const opts = (arr, cur) => arr.map(([v, l]) => `<option value="${esc(v)}" ${String(cur) === String(v) ? 'selected' : ''}>${esc(l)}</option>`).join('');
  shell(T('title'), `<div class="plate"><div class="pl-k">${esc(T('title'))}</div><div class="pl-v" id="cu_count">${D.rows.length} ${esc(T('count'))}</div><div class="pl-s">${esc(T('due'))}: ${money(owing)}</div></div>
    ${D.sql ? '' : `<div class="notice warn">phase43.sql</div>`}
    <div class="row" style="margin:8px 0"><input id="cu_q" type="search" placeholder="${esc(T('search'))}" value="${esc(D.q)}" style="flex:1" autocomplete="off">${D.canEnter ? `<button class="primary" data-act="cu_add">${esc(T('add'))}</button>` : ''}</div>
    <details data-ctl="off" id="cu_filters" ${D.fOpen ? 'open' : ''} style="margin-bottom:8px"><summary><b>${esc(T('filters'))}</b></summary><div class="card stack">
      <select id="cu_ftier" aria-label="${esc(T('tier'))}"><option value="">${esc(T('allTiers'))}</option>${D.tiers.map((t) => `<option value="${t.id}" ${String(D.fTier) === String(t.id) ? 'selected' : ''}>${esc(tn(t))}</option>`).join('')}</select>
      <select id="cu_ftype" aria-label="${esc(T('type'))}">${opts([['', T('allTypes')], ['retail', T('retail')], ['wholesale', T('wholesale')]], D.fType)}</select>
      <select id="cu_fstat" aria-label="${esc(T('stActive'))}">${opts([['active', T('stActive')], ['inactive', T('stInactive')], ['all', T('stAll')]], D.fStatus)}</select>
      <label class="row"><input type="checkbox" id="cu_fdue" ${D.fDue ? 'checked' : ''}> ${esc(T('hasDue'))}</label>
      <label class="row"><input type="checkbox" id="cu_fbday" ${D.fBday ? 'checked' : ''}> ${esc(T('bdayMonth'))}</label></div></details>
    <div id="cu_list"></div>`, true);
  drawList();
}
async function viewCustomers() {
  shell(T('title'), '<p class="muted">…</p>', true);
  try { await loadCommon(); await loadDirectory(); } catch (e) { return toast(eText(e)); }
  if (D.err && D.sql) toast(eText(D.err));
  D.shown = 50; drawPage();
}

// ---------- add / edit ----------
function formSheet(c) {
  const e = c || {}, edit = !!c;
  const tierSel = D.mgr ? `<div><label for="cf_tier">${esc(T('tier'))}</label><select id="cf_tier">${D.tiers.filter((t) => t.active || String(t.id) === String(e.tier_id)).map((t) => `<option value="${t.id}" ${String(e.tier_id) === String(t.id) ? 'selected' : ''}>${esc((t.badge || '') + ' ' + tn(t))}</option>`).join('')}</select></div>` : '';
  openSheet(`<h2>${esc(edit ? T('editTitle') : T('newTitle'))}</h2><div class="stack" id="cf_form" data-id="${esc(e.id || '')}">
    <div><label for="cf_mobile">${esc(T('mobile'))}</label><input id="cf_mobile" inputmode="tel" autocomplete="off" value="${esc(e.mobile || '')}" placeholder="01XXXXXXXXX" ${edit ? 'disabled' : ''}></div>
    <div><label for="cf_name">${esc(T('name'))}</label><input id="cf_name" autocomplete="off" value="${esc(e.name || '')}"></div>
    ${tierSel}
    <div><label for="cf_type">${esc(T('type'))}</label><select id="cf_type"><option value="retail" ${e.type !== 'wholesale' ? 'selected' : ''}>${esc(T('retail'))}</option><option value="wholesale" ${e.type === 'wholesale' ? 'selected' : ''}>${esc(T('wholesale'))}</option></select></div>
    <div class="row"><div style="flex:1"><label for="cf_bday">${esc(T('birthday'))}</label><input id="cf_bday" type="date" max="${today()}" value="${esc(e.birthday || '')}"></div>
      <div style="flex:1"><label for="cf_anniv">${esc(T('anniv'))}</label><input id="cf_anniv" type="date" max="${today()}" value="${esc(e.anniversary || '')}"></div></div>
    <div><label for="cf_addr">${esc(T('address'))}</label><input id="cf_addr" value="${esc(e.address || '')}"></div>
    <div><label for="cf_wa">${esc(T('wa'))}</label><input id="cf_wa" inputmode="tel" value="${esc(e.whatsapp || '')}"></div>
    <div><label for="cf_source">${esc(T('source'))}</label><input id="cf_source" value="${esc(e.source || '')}"></div>
    <div><label for="cf_note">${esc(T('notes'))}</label><input id="cf_note" value="${esc(e.note || '')}"></div>
    ${D.mgr ? `<div><label for="cf_limit">${esc(T('limit'))}</label><input id="cf_limit" inputmode="decimal" value="${e.credit_limit === null || e.credit_limit === undefined ? '' : esc(e.credit_limit)}"></div>
      <label class="row"><input type="checkbox" id="cf_lock" ${e.tier_locked ? 'checked' : ''}> ${esc(T('lock'))}</label>` : ''}
    ${edit && B.crm && B.crm.openEdit && B.rule('crm_on', false) === true ? `<button type="button" class="full" data-act="crm_more" data-v="${esc(e.id)}">More profile details</button>` : ''}
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cu_save">${esc(T('save'))}</button></div></div>`);
  setTimeout(() => { const f = $(edit ? '#cf_name' : '#cf_mobile'); if (f) f.focus(); }, 60);
}
const val = (id) => (($(id) || {}).value || '').trim();
async function saveCustomer() {
  const id = ($('#cf_form') || {}).dataset ? $('#cf_form').dataset.id : '';
  const p = { name: val('#cf_name'), type: val('#cf_type'), birthday: val('#cf_bday'), anniversary: val('#cf_anniv'), address: val('#cf_addr'), whatsapp: norm(val('#cf_wa')), source: val('#cf_source'), note: val('#cf_note') };
  if (!id) p.mobile = norm(val('#cf_mobile'));
  if (D.mgr) {
    if ($('#cf_limit')) p.credit_limit = norm(val('#cf_limit'));
    if ($('#cf_lock')) p.tier_locked = $('#cf_lock').checked;
    if ($('#cf_tier')) { const old = id ? (D.rows.find((x) => x.id === id) || {}).tier_id : null; if (!id || String(old) !== $('#cf_tier').value) p.tier_id = $('#cf_tier').value; if (id && p.tier_id) p.tier_reason = 'edited'; }
  }
  if (!p.name) return toast(lab(ERR.customer_name_required));
  const r = await sb.rpc('customer_save', { p_id: id || null, p, p_client: rid() });
  if (r.error) return toast(eText(r.error));
  closeSheet();
  if (r.data && r.data.dup) { toast(T('dupOpen')); await loadDirectory(); return openProfile(r.data.id); }
  toast(T('saved')); await loadDirectory(); if (r.data && r.data.id && !id) { drawPage(); return openProfile(r.data.id); } drawPage();
}

// ---------- ⋮ menu ----------
function menuSheet(id) {
  const c = D.rows.find((x) => x.id === id); if (!c) return;
  const wa = 'https://wa.me/880' + String(c.whatsapp || c.mobile).replace(/^0/, '');
  const b = (act, label, extra) => `<button class="full" data-act="${act}" data-v="${esc(id)}" ${extra || ''}>${esc(label)}</button>`;
  openSheet(`<h2>${esc(c.name)}</h2><div class="muted">${esc(c.mobile)}</div><div class="stack" style="margin-top:10px">
    ${b('cu_open', T('menuOpen'))}${D.canEnter || D.mgr ? b('cu_edit', T('edit')) : ''}
    ${D.mgr ? b('cu_tier', T('menuChangeTier')) : ''}${D.mgr && D.gifts ? b('cu_gift', T('menuGift')) : ''}${D.mgr && D.loyal ? b('cu_pts', T('menuPoints')) : ''}
    <button class="full" data-act="cu_dues">${esc(T('menuDues'))}</button>
    ${B.crmConsent ? B.crmConsent.callHTML(c, T('menuCall')) : `<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T('menuCall'))}</a>`}
    ${c.masked ? '' : `<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T('menuWa'))}</a>`}
    ${D.mgr ? b('cu_active', c.active ? T('menuOff') : T('menuOn')) : ''}${B.crmConsent ? B.crmConsent.menuHTML(c) : ''}${B.crmDupes ? B.crmDupes.menuHTML(c) : ''}
    <button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}

// ---------- profile ----------
async function openProfile(id) {
  if (B.crm && B.crm.open360 && B.rule('crm_on', false) === true) return B.crm.open360(id);      // CRM-A (integration: only while the owner has switched crm_on ON; at the default the old profile sheet opens)
  const r = await (B.crmConsent ? B.crmConsent.profile(id) : sb.rpc('customer_profile', { p_customer: id })); if (r.error) return toast(eText(r.error));
  const d = r.data || {}, c = d.customer || {}; D.cur = { id, c, d };
  const t = tier(c.tier_id);
  let due = [];
  if (D.gifts) { const g = await sb.rpc('gifts_due', { p_customer: id }); due = g.error ? [] : (g.data || []); }
  D.cur.due = due;
  const histRow = (h) => { const a = tier(h.from_tier), z = tier(h.to_tier); return `<div class="muted" style="font-size:.85rem">${esc(dshort(h.at))} · ${esc(a ? tn(a) : '—')} → <b>${esc(z ? tn(z) : '—')}</b> · ${esc(h.reason === 'auto' ? T('auto') : T('manual'))}${h.note ? ' · ' + esc(h.note) : ''}${h.by ? ' · ' + esc(T('by')) + ' ' + esc(h.by) : ''}</div>`; };
  const giftRow = (g) => `<div class="muted" style="font-size:.85rem">🎁 ${esc(S.lang === 'en' ? (g.text_en || g.text_bn) : (g.text_bn || g.text_en))}${g.value ? ' · ' + money(g.value) : ''} · ${g.claimed_at ? esc(T('claimed')) + ' ' + esc(dshort(g.claimed_at)) : esc(T('valid')) + ' ' + esc(dshort(g.valid_until))}</div>`;
  const dueRow = (g) => `<div class="row between" style="align-items:center"><span>🎁 ${esc(S.lang === 'en' ? (g.text_en || g.text_bn) : (g.text_bn || g.text_en))}${g.value_taka ? ' · ' + money(g.value_taka) : ''}</span>
      ${D.canEnter || D.mgr ? `<button class="mini" data-act="cu_claim" data-g="${esc(g.gift_id || '')}" data-r="${esc(g.rule_id || '')}" data-o="${esc(g.occasion || '')}">${esc(T('claim'))}</button>` : ''}</div>`;
  openSheet(`<h2>${esc(c.name)} ${c.type === 'wholesale' ? '◆' : ''}</h2>
    <div class="row wrap" style="gap:6px;align-items:center">${chip(t)}${c.tier_locked ? `<span class="chip">🔒 ${esc(T('locked'))}</span>` : ''}${c.active ? '' : `<span class="chip bad">${esc(T('stInactive'))}</span>`}<span class="muted">${esc(c.mobile)}</span></div>
    ${t && t.perks ? `<div class="notice ok" style="margin-top:6px">${esc(t.perks)}</div>` : ''}
    <div class="card" style="margin-top:8px"><div class="row between"><span>${esc(T('spent'))}</span><b>${money(d.spend)}</b></div>
      <div class="row between"><span>${esc(T('orders'))}</span><b>${Number(d.orders) || 0}</b></div>
      <div class="row between"><span>${esc(T('avg'))}</span><b>${d.avg_bill === null || d.avg_bill === undefined ? '—' : money(d.avg_bill)}</b></div>
      <div class="row between"><span>${esc(T('last'))}</span><b>${esc(dshort(d.last_sale))}</b></div>
      <div class="row between"><span>${esc(T('due'))}</span><b>${Number(d.balance) > 0 ? money(d.balance) : '—'}</b></div>
      ${D.loyal ? `<div class="row between"><span>${esc(T('points'))}</span><b>${Number(d.points) || 0}</b></div>` : ''}
      <div class="row between"><span>${esc(T('since'))}</span><b>${esc(dshort(c.customer_since))}</b></div></div>
    ${c.birthday || c.anniversary || c.address || c.note ? `<div class="muted" style="font-size:.85rem;margin-top:6px">${c.birthday ? '🎂 ' + esc(c.birthday) + ' ' : ''}${c.anniversary ? '💍 ' + esc(c.anniversary) + ' ' : ''}${c.address ? '· ' + esc(c.address) : ''}${c.note ? '<br>' + esc(c.note) : ''}</div>` : ''}
    ${due.length ? `<h3>${esc(T('giftDue'))}</h3><div class="card stack">${due.map(dueRow).join('')}</div>` : ''}
    ${D.loyal && (D.canEnter || D.mgr) ? `<div class="row" style="margin-top:8px"><button class="full" data-act="cu_redeem" data-v="${esc(id)}">${esc(T('redeem'))}</button></div>` : ''}
    <h3>${esc(T('history'))}</h3>${(d.history || []).map(histRow).join('') || '<p class="muted">—</p>'}
    ${D.gifts && (d.gifts || []).length ? `<h3>${esc(T('gifts'))}</h3>${d.gifts.map(giftRow).join('')}` : ''}
    <h3>${esc(T('recent'))}</h3>${(d.recent_sales || []).map((s) => `<div class="row between muted" style="font-size:.85rem"><span>#${esc(s.receipt)} · ${esc(dshort(s.date))}${s.status === 'void' ? ' (void)' : ''}</span><b>${money(s.total)}</b></div>`).join('') || '<p class="muted">—</p>'}
    <div class="row" style="margin-top:12px"><button class="full" data-act="cu_menu" data-v="${esc(id)}">⋮</button><button class="full" data-act="closesheet">${esc(T('close'))}</button></div>`);
}

// ---------- tier change / gift / points ----------
function tierSheet(id) {
  const c = D.rows.find((x) => x.id === id); if (!c) return;
  openSheet(`<h2>${esc(T('menuChangeTier'))}: ${esc(c.name)}</h2><div class="stack" data-id="${esc(id)}" id="tc_form">
    <div><label for="tc_tier">${esc(T('tier'))}</label><select id="tc_tier">${D.tiers.filter((t) => t.active || String(t.id) === String(c.tier_id)).map((t) => `<option value="${t.id}" ${String(c.tier_id) === String(t.id) ? 'selected' : ''}>${esc((t.badge || '') + ' ' + tn(t))}</option>`).join('')}</select></div>
    <div><label for="tc_reason">${esc(T('reason'))}</label><input id="tc_reason" autocomplete="off"></div>
    <label class="row"><input type="checkbox" id="tc_lock" checked> ${esc(T('lock'))}</label>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cu_tier_ok">${esc(T('save'))}</button></div></div>`);
}
function giftSheet(id) {
  const c = D.rows.find((x) => x.id === id); if (!c) return;
  openSheet(`<h2>${esc(T('menuGift'))}: ${esc(c.name)}</h2><div class="stack" id="gf_form" data-id="${esc(id)}" data-key="${rid()}">
    <div><label for="gf_bn">${esc(T('giftBn'))}</label><input id="gf_bn"></div><div><label for="gf_en">${esc(T('giftEn'))}</label><input id="gf_en"></div>
    <div><label for="gf_val">${esc(T('giftVal'))}</label><input id="gf_val" inputmode="decimal"></div><div><label for="gf_until">${esc(T('giftUntil'))}</label><input id="gf_until" type="date" min="${today()}"></div>
    <div><label for="gf_note">${esc(T('notes'))}</label><input id="gf_note"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cu_gift_ok">${esc(T('issue'))}</button></div></div>`);
}
function ptsSheet(id) {
  const c = D.rows.find((x) => x.id === id); if (!c) return;
  openSheet(`<h2>${esc(T('menuPoints'))}: ${esc(c.name)}</h2><div class="muted">${esc(T('balance'))}: <b>${Number(c.points) || 0}</b></div><div class="stack" id="pt_form" data-id="${esc(id)}" data-key="${rid()}">
    <div><label for="pt_delta">${esc(T('delta'))}</label><input id="pt_delta" inputmode="numeric"></div><div><label for="pt_note">${esc(T('reason'))}</label><input id="pt_note"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="cu_pts_ok">${esc(T('save'))}</button></div></div>`);
}
function redeemSheet(id) {
  const c = D.rows.find((x) => x.id === id) || (D.cur && D.cur.id === id ? D.cur.c : null); if (!c) return;
  openSheet(`<h2>${esc(T('redeem'))}: ${esc(c.name)}</h2><div class="stack" id="rd_form" data-id="${esc(id)}" data-key="${rid()}">
    <div><label for="rd_n">${esc(T('redeemN'))}</label><input id="rd_n" inputmode="numeric"></div><div id="rd_out" class="muted"></div>
    <div class="row"><button class="full" data-act="cu_redeem_dry">${esc(T('preview'))}</button><button class="primary full" data-act="cu_redeem_ok">${esc(T('redeem'))}</button></div></div>`);
}

Object.assign(H, {
  cu_open: (a) => { closeSheet(); openProfile(a.dataset.v); },
  cu_dues: () => { closeSheet(); location.hash = '#/dues'; },
  cu_menu: (a) => menuSheet(a.dataset.v),
  cu_more: () => { D.shown += 50; drawList(); },
  cu_add: () => formSheet(null),
  cu_edit: (a) => { const c = D.rows.find((x) => x.id === a.dataset.v); if (c) formSheet(c); },
  cu_save: () => saveCustomer(),
  cu_tier: (a) => tierSheet(a.dataset.v),
  cu_gift: (a) => giftSheet(a.dataset.v),
  cu_pts: (a) => ptsSheet(a.dataset.v),
  cu_redeem: (a) => redeemSheet(a.dataset.v),
  cu_active: async (a) => { const c = D.rows.find((x) => x.id === a.dataset.v); if (!c) return;
    const r = await sb.rpc('customer_save', { p_id: c.id, p: { active: !c.active } }); if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); await loadDirectory(); drawPage(); },
  cu_tier_ok: async () => { const f = $('#tc_form'); const r = await sb.rpc('customer_set_tier', { p_customer: f.dataset.id, p_tier: Number($('#tc_tier').value), p_reason: val('#tc_reason'), p_lock: $('#tc_lock').checked });
    if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('tierChanged')); await loadDirectory(); drawPage(); },
  cu_gift_ok: async () => { const f = $('#gf_form'); const v = norm(val('#gf_val'));
    const r = await sb.rpc('gift_issue', { p_customer: f.dataset.id, p_text_bn: val('#gf_bn') || null, p_text_en: val('#gf_en') || null, p_value: v === '' ? null : Number(v), p_valid_until: val('#gf_until') || null, p_note: val('#gf_note') || null, p_client: f.dataset.key });
    if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); },
  cu_pts_ok: async () => { const f = $('#pt_form'); const n = Number(norm(val('#pt_delta')));
    if (!Number.isInteger(n) || n === 0) return toast(lab(ERR.bad_number));
    const r = await sb.rpc('crmf_points_adjust', { p_customer: f.dataset.id, p_delta: n, p_note: val('#pt_note'), p_client: f.dataset.key });
    if (r.error) return toast(eText(r.error)); closeSheet(); toast(T('saved')); await loadDirectory(); drawPage(); },
  cu_redeem_dry: async () => { const f = $('#rd_form'); const n = Number(norm(val('#rd_n'))); if (!Number.isInteger(n) || n <= 0) return toast(lab(ERR.bad_number));
    const r = await sb.rpc('crmf_points_redeem', { p_customer: f.dataset.id, p_points: n, p_bill: null, p_note: null, p_client: null, p_dry: true, p_override: null }); if (r.error) return toast(eText(r.error));
    $('#rd_out').textContent = `${n} ${T('points')} ${T('worth')} ${money(r.data.value_taka)} · ${T('balance')}: ${r.data.balance} → ${r.data.balance_after}`; },
  cu_redeem_ok: async () => { const f = $('#rd_form'); const n = Number(norm(val('#rd_n'))); if (!Number.isInteger(n) || n <= 0) return toast(lab(ERR.bad_number));
    const r = await sb.rpc('crmf_points_redeem', { p_customer: f.dataset.id, p_points: n, p_bill: null, p_note: null, p_client: f.dataset.key, p_dry: false, p_override: null }); if (r.error) return toast(eText(r.error));
    closeSheet(); toast(`${T('redeemed')}: ${n} = ${money(r.data.value_taka)}`); await loadDirectory(); drawPage(); },
  cu_claim: async (a) => { const cur = D.cur; if (!cur) return;
    const args = a.dataset.g ? { p_customer: cur.id, p_gift: a.dataset.g } : { p_customer: cur.id, p_rule: Number(a.dataset.r), p_occasion: a.dataset.o };
    const r = await sb.rpc('gift_claim', args); if (r.error) return toast(eText(r.error)); toast(T('claimed')); openProfile(cur.id); },
});

document.addEventListener('input', (e) => { if (e.target.id === 'cu_q') { D.q = e.target.value; D.shown = 50; const pos = e.target.selectionStart; drawList(); try { e.target.setSelectionRange(pos, pos); } catch (x) { /* type=search */ } } });
document.addEventListener('change', (e) => {
  const id = e.target.id;
  if (id === 'cu_ftier') { D.fTier = e.target.value; D.fOpen = true; D.shown = 50; drawList(); }
  if (id === 'cu_ftype') { D.fType = e.target.value; D.fOpen = true; D.shown = 50; drawList(); }
  if (id === 'cu_fstat') { D.fStatus = e.target.value; D.fOpen = true; D.shown = 50; drawList(); }
  if (id === 'cu_fdue') { D.fDue = e.target.checked; D.fOpen = true; D.shown = 50; drawList(); }
  if (id === 'cu_fbday') { D.fBday = e.target.checked; D.fOpen = true; D.shown = 50; drawList(); }
});
document.addEventListener('toggle', (e) => { if (e.target && e.target.id === 'cu_filters') D.fOpen = e.target.open; }, true);

// =====================================================================================================================
// #/tiers (owner)
// =====================================================================================================================
const TD = { rules: {}, gr: [], usage: [], dry: null, open: {} };
const RULES = ['tier_discount_on', 'customer_tier_auto_on', 'customer_tier_allow_downgrade', 'loyalty_points_on', 'customer_gifts_on', 'points_per_100_taka', 'point_value_taka', 'redeem_min_points', 'gift_window_days', 'gift_valid_days'];
const rv = (k) => { const r = TD.rules[k]; if (!r) return null; return r.value !== null && r.value !== undefined ? r.value : r.default_value; };
const rOn = (k) => rv(k) === true || rv(k) === 'true';
async function loadTiers() {
  const mon = today().slice(0, 8) + '01';
  const [t, r, g, u] = await Promise.all([sb.from('customer_tiers').select('*').order('rank'), sb.from('rules').select('key,value,default_value').in('key', RULES), sb.from('gift_rules').select('*').order('id'), sb.rpc('tier_usage_report', { p_from: mon, p_to: today() })]);
  D.tiers = t.data || []; TD.rules = {}; (r.data || []).forEach((x) => { TD.rules[x.key] = x; }); TD.gr = g.data || []; TD.usage = u.error ? [] : (u.data || []);
}
function tierCard(t, i, n) {
  const th = [t.min_lifetime_spend !== null && t.min_lifetime_spend !== undefined ? `≥ ${money(t.min_lifetime_spend)}` : '', t.min_orders ? `${t.min_orders} ${T('orders')}` : '', t.min_orders_12m ? `${t.min_orders_12m} / 12m` : '', t.min_months_active ? `${t.min_months_active} m` : ''].filter(Boolean).join(' · ');
  return `<div class="card ${t.active ? '' : 'muted'}"><div class="row between"><div>${chip(t)} ${t.is_default ? `<span class="chip ok">${esc(T('tDefault'))}</span>` : ''}${t.active ? '' : ` <span class="chip bad">${esc(T('tRetired'))}</span>`}</div><b>${Number(t.discount_percent)}%</b></div>
    <div class="muted" style="font-size:.85rem">${esc(T('tDisc'))}: ${Number(t.discount_percent)}%${t.discount_cap_amount !== null ? ' (≤ ' + money(t.discount_cap_amount) + ')' : ''} · ${esc(T('tMult'))}: ×${Number(t.points_multiplier)}${th ? '<br>' + esc(th) : ''}${t.perks ? '<br>' + esc(t.perks) : ''}</div>
    <div class="row wrap" style="margin-top:6px"><button class="mini" data-act="ti_edit" data-v="${t.id}">${esc(T('edit'))}</button><button class="mini" data-act="ti_move" data-v="${t.id}" data-d="-1" ${i === 0 ? 'disabled' : ''} aria-label="${esc(T('tUp'))}">▲</button>
      <button class="mini" data-act="ti_move" data-v="${t.id}" data-d="1" ${i === n - 1 ? 'disabled' : ''} aria-label="${esc(T('tDown'))}">▼</button>
      ${t.is_default ? '' : `<button class="mini" data-act="ti_active" data-v="${t.id}" data-a="${t.active ? '0' : '1'}">${esc(t.active ? T('tRetire') : T('tRestore'))}</button>`}</div></div>`;
}
function swRow(k, label) {
  return `<div class="row between" style="align-items:center"><span>${esc(label)}</span><button type="button" class="tog ${rOn(k) ? 'on' : ''}" role="switch" aria-checked="${rOn(k)}" data-act="ti_sw" data-k="${k}" data-v="${rOn(k) ? '0' : '1'}">${esc(rOn(k) ? T('on') : T('off'))}</button></div>`;
}
function numRow(k, label) {
  return `<div class="row" style="align-items:flex-end"><div style="flex:1"><label for="nr_${k}">${esc(label)}</label><input id="nr_${k}" inputmode="decimal" value="${rv(k) === null ? '' : esc(rv(k))}"></div><button class="mini" data-act="ti_num" data-k="${k}">${esc(T('save'))}</button></div>`;
}
function dryHTML() {
  const d = TD.dry; if (!d) return '';
  const rows = (d.changes || []).map((c) => { const a = D.tiers.find((t) => t.code === c.from_code), z = D.tiers.find((t) => t.code === c.to_code);
    return `<div class="row between" style="font-size:.85rem"><span>${esc(c.name)} <span class="muted">${esc(c.mobile)}</span></span><span>${esc(a ? tn(a) : '—')} ${c.direction === 'down' ? '↓' : '→'} <b>${esc(z ? tn(z) : '—')}</b></span></div>`; }).join('');
  return `<div class="card stack" id="ti_dry"><b>${d.count ? `${d.count} ${esc(T('willMove'))}` : esc(T('noChange'))}</b>${rows}
    ${d.count ? (rOn('customer_tier_auto_on') ? `<button class="primary full" data-act="ti_apply">${esc(T('apply'))}</button>` : `<div class="notice warn">${esc(T('autoOffNote'))}</div>`) : ''}</div>`;
}
function grCard(g) {
  const t = g.tier_id ? tier(g.tier_id) : null;
  return `<div class="card ${g.active ? '' : 'muted'}"><div class="row between"><b>${esc(lab(TRIG[g.trigger]))}${g.threshold ? ' · ' + esc(g.threshold) : ''}</b><span class="chip">${esc(t ? tn(t) : T('gAll'))}</span></div>
    <div class="muted" style="font-size:.85rem">🎁 ${esc(S.lang === 'en' ? (g.gift_text_en || g.gift_text_bn) : (g.gift_text_bn || g.gift_text_en))}${g.value_taka ? ' · ' + money(g.value_taka) : ''}</div>
    <div class="row" style="margin-top:6px"><button class="mini" data-act="gr_edit" data-v="${g.id}">${esc(T('edit'))}</button><button class="mini" data-act="gr_active" data-v="${g.id}" data-a="${g.active ? '0' : '1'}">${esc(g.active ? T('tRetire') : T('tRestore'))}</button></div></div>`;
}
function drawTiers() {
  const el = $('#ti_body'); if (!el) return;
  const n = D.tiers.length;
  el.innerHTML = `<div class="notice">${esc(T('tHint'))}</div>
    <div class="row" style="margin:8px 0"><button class="primary full" data-act="ti_edit" data-v="">${esc(T('tNew'))}</button></div>
    <div id="ti_list">${D.tiers.map((t, i) => tierCard(t, i, n)).join('')}</div>
    <h3>${esc(T('swTitle'))}</h3><div class="card stack">
      ${swRow('tier_discount_on', T('swTierDisc'))}${swRow('customer_tier_auto_on', T('swAuto'))}${swRow('customer_tier_allow_downgrade', T('swDown'))}
      ${swRow('loyalty_points_on', T('swPts'))}${numRow('points_per_100_taka', T('nPer100'))}${numRow('point_value_taka', T('nValue'))}${numRow('redeem_min_points', T('nMin'))}
      ${swRow('customer_gifts_on', T('swGifts'))}${numRow('gift_window_days', T('nWin'))}${numRow('gift_valid_days', T('nValid'))}</div>
    <h3>${esc(T('refresh'))}</h3><div class="row"><button class="full" data-act="ti_dry">${esc(T('dry'))}</button></div>${dryHTML()}
    <h3>${esc(T('gRules'))}</h3><div class="row" style="margin-bottom:6px"><button class="full" data-act="gr_edit" data-v="">${esc(T('gNew'))}</button></div>${TD.gr.map(grCard).join('')}
    ${TD.usage.length ? `<h3>${esc(T('usage'))}</h3><div class="card">${TD.usage.map((u) => `<div class="row between" style="font-size:.9rem"><span>${esc(S.lang === 'en' ? u.name_en : u.name_bn)}</span><span>${u.sales} ${esc(T('uSales'))} · ${money(u.revenue)} · ${esc(T('uDisc'))} ${money(u.tier_discount)}</span></div>`).join('')}</div>` : ''}`;
}
async function viewTiers() {
  shell(T('tiersTitle'), '<div id="ti_body"><p class="muted">…</p></div>', true);
  if (B.loadStatic) await B.loadStatic();
  if (!(S.ctx && S.ctx.is_owner)) { const el = $('#ti_body'); if (el) el.innerHTML = `<div class="notice bad">${esc(T('ownerOnly'))}</div>`; return; }
  try { await loadTiers(); drawTiers(); } catch (e) { toast(eText(e)); }
}
function tierForm(id) {
  const t = id ? tier(id) : {};
  const f = (k, label, extra) => `<div><label for="tf_${k}">${esc(label)}</label><input id="tf_${k}" value="${t[k] === null || t[k] === undefined ? '' : esc(t[k])}" ${extra || ''}></div>`;
  openSheet(`<h2>${esc(id ? tn(t) : T('tNew'))}</h2><div class="stack" id="tf_form" data-id="${esc(id || '')}">
    ${id ? '' : f('code', T('tCode'), 'autocapitalize="off"')}
    <div class="row"><div style="flex:1"><label for="tf_name_bn">${esc(T('name'))} (বাংলা)</label><input id="tf_name_bn" value="${esc(t.name_bn || '')}"></div><div style="flex:1"><label for="tf_name_en">${esc(T('name'))} (English)</label><input id="tf_name_en" value="${esc(t.name_en || '')}"></div></div>
    <div class="row"><div style="flex:1"><label for="tf_badge">${esc(T('tBadge'))}</label><input id="tf_badge" value="${esc(t.badge || '')}"></div><div style="flex:1"><label for="tf_color">${esc(T('tColor'))}</label><input id="tf_color" type="color" value="${esc(t.color || '#64748b')}"></div></div>
    ${f('discount_percent', T('tDisc'), 'inputmode="decimal"')}${f('discount_cap_amount', T('tCap'), 'inputmode="decimal"')}${f('credit_limit_default', T('tCredit'), 'inputmode="decimal"')}${f('points_multiplier', T('tMult'), 'inputmode="decimal"')}
    ${f('perks', T('tPerks'))}${f('birthday_gift', T('tBgift'))}
    ${f('min_lifetime_spend', T('tSpend'), 'inputmode="decimal"')}${f('min_orders', T('tOrders'), 'inputmode="numeric"')}${f('min_orders_12m', T('tOrders12'), 'inputmode="numeric"')}${f('min_months_active', T('tMonths'), 'inputmode="numeric"')}
    <label class="row"><input type="checkbox" id="tf_default" ${t.is_default ? 'checked disabled' : ''}> ${esc(T('tMakeDefault'))}</label>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="ti_save">${esc(T('save'))}</button></div></div>`);
}
function grForm(id) {
  const g = id ? (TD.gr.find((x) => String(x.id) === String(id)) || {}) : {};
  openSheet(`<h2>${esc(T('gRules'))}</h2><div class="stack" id="gr_form" data-id="${esc(id || '')}">
    <div><label for="gr_trig">${esc(T('gTrig'))}</label><select id="gr_trig">${Object.keys(TRIG).map((k) => `<option value="${k}" ${g.trigger === k ? 'selected' : ''}>${esc(lab(TRIG[k]))}</option>`).join('')}</select></div>
    <div><label for="gr_tier">${esc(T('gTier'))}</label><select id="gr_tier"><option value="">${esc(T('gAll'))}</option>${D.tiers.map((t) => `<option value="${t.id}" ${String(g.tier_id) === String(t.id) ? 'selected' : ''}>${esc(tn(t))}</option>`).join('')}</select></div>
    <div><label for="gr_thr">${esc(T('gThr'))}</label><input id="gr_thr" inputmode="decimal" value="${g.threshold === null || g.threshold === undefined ? '' : esc(g.threshold)}"></div>
    <div><label for="gr_bn">${esc(T('giftBn'))}</label><input id="gr_bn" value="${esc(g.gift_text_bn || '')}"></div><div><label for="gr_en">${esc(T('giftEn'))}</label><input id="gr_en" value="${esc(g.gift_text_en || '')}"></div>
    <div><label for="gr_val">${esc(T('giftVal'))}</label><input id="gr_val" inputmode="decimal" value="${g.value_taka === null || g.value_taka === undefined ? '' : esc(g.value_taka)}"></div>
    <div><label for="gr_days">${esc(T('gDays'))}</label><input id="gr_days" inputmode="numeric" value="${g.valid_days === null || g.valid_days === undefined ? '' : esc(g.valid_days)}"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="gr_save">${esc(T('save'))}</button></div></div>`);
}
async function after(r, msg) { if (r.error) { toast(eText(r.error)); return false; } toast(msg || T('saved')); await loadTiers(); drawTiers(); return true; }
Object.assign(H, {
  ti_edit: (a) => tierForm(a.dataset.v ? Number(a.dataset.v) : null),
  ti_save: async () => { const id = $('#tf_form').dataset.id, g = (k) => norm(val('#tf_' + k));
    const p = { name_bn: val('#tf_name_bn'), name_en: val('#tf_name_en'), badge: val('#tf_badge'), color: val('#tf_color'), discount_percent: g('discount_percent') || '0', discount_cap_amount: g('discount_cap_amount'), credit_limit_default: g('credit_limit_default'),
      points_multiplier: g('points_multiplier') || '1', perks: val('#tf_perks'), birthday_gift: val('#tf_birthday_gift'), min_lifetime_spend: g('min_lifetime_spend'), min_orders: g('min_orders'), min_orders_12m: g('min_orders_12m'), min_months_active: g('min_months_active') };
    if (!id) p.code = val('#tf_code').toLowerCase();
    if ($('#tf_default') && $('#tf_default').checked && !$('#tf_default').disabled) p.is_default = true;
    const r = await sb.rpc('tier_save', { p_id: id ? Number(id) : null, p, p_client: rid() }); if (await after(r)) closeSheet(); },
  ti_move: async (a) => { const ids = D.tiers.map((t) => t.id), i = ids.indexOf(Number(a.dataset.v)), j = i + Number(a.dataset.d); if (i < 0 || j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]]; await after(await sb.rpc('tier_reorder', { p_ids: ids })); },
  ti_active: async (a) => { await after(await sb.rpc('tier_save', { p_id: Number(a.dataset.v), p: { active: a.dataset.a === '1' } })); },
  ti_sw: async (a) => { const r = await sb.rpc('set_rule', { p_key: a.dataset.k, p_value: a.dataset.v === '1' }); if (!r.error && B.reloadRules) await B.reloadRules(); await after(r); },
  ti_num: async (a) => { const v = Number(norm(val('#nr_' + a.dataset.k))); if (!Number.isFinite(v) || v < 0) return toast(lab(ERR.bad_number));
    const r = await sb.rpc('set_rule', { p_key: a.dataset.k, p_value: v }); if (!r.error && B.reloadRules) await B.reloadRules(); await after(r); },
  ti_dry: async () => { const r = await sb.rpc('customer_tier_refresh', { p_dry: true }); if (r.error) return toast(eText(r.error)); TD.dry = r.data; drawTiers(); },
  ti_apply: async () => { if (!window.confirm(T('confirmApply'))) return; const r = await sb.rpc('customer_tier_refresh', { p_dry: false }); if (r.error) return toast(eText(r.error)); TD.dry = null; await after(r, `${T('applied')}: ${r.data.count}`); },
  gr_edit: (a) => grForm(a.dataset.v || null),
  gr_save: async () => { const id = $('#gr_form').dataset.id;
    const p = { trigger: val('#gr_trig'), tier_id: val('#gr_tier'), threshold: norm(val('#gr_thr')), gift_text_bn: val('#gr_bn'), gift_text_en: val('#gr_en'), value_taka: norm(val('#gr_val')), valid_days: norm(val('#gr_days')) };
    const r = await sb.rpc('gift_rule_save', { p_id: id ? Number(id) : null, p }); if (await after(r)) closeSheet(); },
  gr_active: async (a) => { await after(await sb.rpc('gift_rule_save', { p_id: Number(a.dataset.v), p: { active: a.dataset.a === '1' } })); },
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { customers: viewCustomers, tiers: viewTiers });
})();
