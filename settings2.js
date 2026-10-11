/* Islamia BOS · Settings hub (owner): fiscal year & week, VAT, barcode, no-permission display, stock-negative mode, discount modes,
   unit conversions, shelf-life rules (with a "which rule applies today" tester), suppliers, access manager (per-person grants),
   role favourites. Route #/settings2 (sub pages #/settings2/<page>). Everything is a rule or a table row the owner edits; the server enforces. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d));
const pnum = (v) => { const s = norm(v).trim(); if (s === '') return null; const n = Number(s); return Number.isFinite(n) ? n : NaN; };
const pick = (r, k) => (S.lang === 'en' ? r[k + '_en'] : S.lang === 'mix' ? r[k + '_mix'] : r[k + '_bn']) || r[k + '_bn'] || r[k + '_en'] || '';
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const dday = (iso) => (iso ? new Date(iso).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }) : '');

const X = {
  title: L('সেটিংস', 'Settings', 'Settings'), back: L('সব সেটিংস', 'All settings', 'সব Settings'), saved: L('সংরক্ষিত', 'Saved', 'Saved'), save: L('সংরক্ষণ', 'Save', 'Save'),
  on: L('চালু', 'On', 'On'), off: L('বন্ধ', 'Off', 'Off'), need: L('তথ্য লাগবে', 'Data needed', 'Data লাগবে'), badv: L('মান ঠিক নয়', 'The value is not valid', 'মান ঠিক নয়'),
  add: L('＋ যোগ করুন', '＋ Add', '＋ Add'), remove: L('মুছুন', 'Remove', 'Remove'), edit: L('বদলান', 'Edit', 'Edit'), cancel: L('বাতিল', 'Cancel', 'Cancel'), close: L('বন্ধ', 'Close', 'Close'),
  reset: L('ডিফল্টে ফেরান', 'Back to default', 'Default এ ফেরান'), dflt: L('ডিফল্ট', 'default', 'default'), sql: L('এই অংশ চালু করতে নতুন SQL চালাতে হবে।', 'The new SQL must be run to switch this part on.', 'এই অংশ চালু করতে নতুন SQL চালাতে হবে।'),
  all: L('সব', 'All', 'All'), allLoc: L('সব লোকেশন', 'All locations', 'সব Location'), none: L('— নেই —', '— none —', '— নেই —'), up: L('উপরে', 'Up', 'Up'), down: L('নিচে', 'Down', 'Down'),
  // hub cards
  c_fiscal: L('অর্থবছর ও সপ্তাহের শুরু', 'Fiscal year & week start', 'Fiscal year ও Week শুরু'), d_fiscal: L('রিপোর্ট এই সীমা ধরে চলবে', 'Reports follow these boundaries', 'Report এই সীমা ধরে চলবে'),
  c_vat: L('ভ্যাট', 'VAT', 'VAT (ভ্যাট)'), d_vat: L('চালু/বন্ধ ও হার', 'On/off and rate', 'On/Off ও হার'),
  c_barcode: L('বারকোড', 'Barcode', 'Barcode'), d_barcode: L('ক্যামেরা ও ডিভাইস আলাদা', 'Camera and device are separate', 'Camera ও Device আলাদা'),
  c_noperm: L('অনুমতি না থাকলে', 'When there is no permission', 'Permission না থাকলে'), d_noperm: L('তালা কার্ড নাকি লুকানো', 'Lock card or hidden', 'Lock card নাকি Hide'),
  c_stock: L('স্টকের বেশি বিক্রি', 'Selling more than stock', 'Stock এর বেশি Sale'), d_stock: L('অনুমতি / সতর্ক / আটকানো', 'Allow / warn / block', 'Allow / Warn / Block'),
  c_disc: L('ডিসকাউন্টের ধরন', 'Discount modes', 'Discount এর ধরন'), d_disc: L('টাকা ও শতাংশ', 'Amount and percent', 'Amount ও Percent'),
  c_units: L('একক রূপান্তর', 'Unit conversions', 'Unit Conversion'), d_units: L('কেজি, পিস, বক্স, প্যাক… সবার জন্য ও আইটেম ধরে', 'kg, piece, box, pack… global and per item', 'kg, piece, box, pack… সবার জন্য ও Item ধরে'),
  c_shelf: L('মেয়াদের নিয়ম', 'Shelf-life rules', 'Shelf-life নিয়ম'), d_shelf: L('আইটেম / ক্যাটাগরি / সব, মৌসুম অনুযায়ী', 'Item / category / all, by season', 'Item / Category / সব, Season অনুযায়ী'),
  c_sup: L('সাপ্লায়ার', 'Suppliers', 'Supplier'), d_sup: L('তালিকা, যোগ, বদল', 'List, add, edit', 'List, Add, Edit'),
  c_access: L('কে কী দেখতে পারবে', 'Access manager', 'Access Manager'), d_access: L('খরচ, লাভ, রিপোর্ট, এক্সপোর্ট, বেতন, সাপ্লায়ার, ইনভয়েস সেটিংস', 'cost, profit, reports, export, salary, suppliers, invoice settings', 'Cost, Profit, Report, Export, Salary, Supplier, Invoice settings'),
  c_fav: L('ভূমিকা অনুযায়ী প্রিয় তালিকা', 'Role favourites', 'Role অনুযায়ী Favourite'), d_fav: L('যার যে ভূমিকা, তার সামনে যা থাকবে', 'What sits in front for each role', 'যার যে Role, তার সামনে যা থাকবে'),
  c_inv: L('ইনভয়েস ও প্রিন্ট', 'Invoice & print', 'Invoice ও Print'), c_old: L('সাধারণ সেটিংস (পুরনো)', 'General settings (old)', 'সাধারণ Settings (পুরনো)'), c_rules: L('নিয়ম ও অপশন', 'Rules & options', 'নিয়ম ও Option'),
  // fiscal
  fy_m: L('অর্থবছর শুরুর মাস', 'Fiscal year starts in month', 'Fiscal year শুরুর মাস'), fy_d: L('শুরুর দিন', 'Start day', 'শুরুর দিন'), fy_cal: L('খালি = জানুয়ারি থেকে (ক্যালেন্ডার বছর)', 'Empty = January (calendar year)', 'খালি = January থেকে (Calendar year)'),
  fy_now: L('এই অর্থবছর', 'This fiscal year', 'এই Fiscal year'), wk: L('সপ্তাহ শুরু হয় যে দিনে', 'Week starts on', 'Week শুরু হয় যে দিনে'), wk_d: L('খালি = শনিবার', 'Empty = Saturday', 'খালি = Saturday'),
  // vat
  vat_on: L('ভ্যাট চালু', 'VAT is on', 'VAT চালু'), vat_rate: L('ভ্যাটের হার (%)', 'VAT rate (%)', 'VAT হার (%)'), vat_note: L('ভ্যাট ছাপতে এখানে চালু থাকতে হবে, আর ইনভয়েস টেমপ্লেটে ভ্যাট লাইনও চালু থাকতে হবে। হার উপদেষ্টার উত্তরের পর বসান।', 'VAT prints only when it is on here and the template’s VAT line is on. Enter the rate after the adviser answers.', 'VAT print হবে যদি এখানে On থাকে আর template এর VAT line On থাকে। হার adviser এর উত্তরের পর বসান।'),
  // barcode
  bc_cam: L('ক্যামেরা স্ক্যান', 'Camera scan', 'Camera scan'), bc_cam_d: L('মোবাইলের ক্যামেরায় বারকোড পড়া', 'Read barcodes with the phone camera', 'Phone camera দিয়ে barcode পড়া'),
  bc_dev: L('ডিভাইস / স্ক্যানার (টাইপ)', 'Device / hardware scanner (typed)', 'Device / Scanner (typed)'), bc_dev_d: L('হ্যান্ড স্ক্যানার বা কিবোর্ড-ধরনের ডিভাইস, নম্বর টাইপ হয়ে যায়', 'Hand scanner or keyboard-type device that types the number', 'Hand scanner বা keyboard-type device, number type হয়ে যায়'),
  // noperm
  np_lock: L('তালা কার্ড দেখান', 'Show a lock card', 'Lock card দেখান'), np_hide: L('পুরো লুকিয়ে ফেলুন', 'Hide completely', 'পুরো Hide করুন'), np_more: L('মডিউল-ভিত্তিক ও ভূমিকা-ভিত্তিক তালা ঠিক করুন', 'Set lock/hide per module and role', 'Module ও Role অনুযায়ী Lock/Hide ঠিক করুন'),
  // stock
  st_allow: L('বিক্রি হতে দিন', 'Allow', 'Allow'), st_warn: L('সতর্ক করুন', 'Warn', 'Warn'), st_block: L('আটকে দিন', 'Block', 'Block'),
  st_allow_d: L('কিছু বলবে না', 'Says nothing', 'কিছু বলবে না'), st_warn_d: L('সতর্কবার্তা দেখাবে, বিক্রি হবে', 'Shows a warning, the sale goes through', 'Warning দেখাবে, Sale হবে'), st_block_d: L('স্টক কম হলে বিক্রি হবে না', 'The sale is refused when stock is short', 'Stock কম হলে Sale হবে না'),
  costing: L('ক্রয়মূল্য হিসাব পদ্ধতি', 'Costing method', 'Costing method'), costing_d: L('এখন শুধু গড় (average); পরে আরও যোগ হবে', 'Average only for now; more come later', 'এখন শুধু Average; পরে আরও যোগ হবে'),
  // discount
  dm_amt: L('টাকার অঙ্কে ডিসকাউন্ট', 'Discount by amount (৳)', 'Discount by Amount (৳)'), dm_pct: L('শতাংশে ডিসকাউন্ট', 'Discount by percent (%)', 'Discount by Percent (%)'),
  dm_warn: L('দুটোই বন্ধ থাকলে POS-এ ডিসকাউন্ট দেওয়া যাবে না।', 'With both off, no discount can be given at the POS.', 'দুটোই Off থাকলে POS এ Discount দেওয়া যাবে না।'),
  dm_note: L('সীমা একই থাকবে — শতাংশ হলে হিসাব করা টাকার অঙ্কে সীমা যাচাই হয়।', 'The same limits apply — for percent the limit is checked on the computed amount.', 'Limit একই থাকবে — Percent হলে computed amount এ limit check হয়।'),
  // units
  u_scope: L('কোথায় খাটবে', 'Applies to', 'কোথায় খাটবে'), u_global: L('সব আইটেম (সাধারণ)', 'All items (global)', 'সব Item (Global)'), u_from: L('এক একক', '1 unit of', '1 unit'), u_to: L('সমান', 'equals', 'সমান'), u_factor: L('পরিমাণ', 'Amount', 'Amount'),
  u_empty: L('তথ্য লাগবে — এখনও কোনো রূপান্তর নেই। যেমন: ১ কেজি = ১০০০ গ্রাম', 'Data needed — no conversion yet. For example: 1 kg = 1000 gram', 'Data লাগবে — এখনও কোনো conversion নেই। যেমন: 1 kg = 1000 gram'),
  u_new: L('নতুন রূপান্তর', 'New conversion', 'নতুন Conversion'), u_note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'), u_bad: L('একক দুটো আলাদা হতে হবে, পরিমাণ শূন্যের বেশি', 'The two units must differ and the amount must be above zero', 'Unit দুটো আলাদা হতে হবে, amount 0 এর বেশি'),
  u_also: L('সাধারণ রূপান্তরও খাটে', 'global rules also apply', 'Global rule ও খাটে'), u_preset: L('দ্রুত যোগ', 'Quick add', 'Quick add'), u_rev: L('উল্টো দিকেও কাজ করে', 'works the other way too', 'উল্টো দিকেও কাজ করে'),
  // shelf
  sh_scope: L('কোন জিনিসের জন্য', 'Applies to', 'কোন জিনিসের জন্য'), sh_all: L('সব মিষ্টি', 'Everything', 'সব Item'), sh_cat: L('ক্যাটাগরি', 'Category', 'Category'), sh_item: L('একটি আইটেম', 'One item', 'একটি Item'),
  sh_season: L('মৌসুমের নাম (ঐচ্ছিক)', 'Season name (optional)', 'Season নাম (ঐচ্ছিক)'), sh_year: L('সারা বছর', 'Whole year', 'সারা বছর'), sh_from: L('শুরু (মাস/দিন)', 'From (month/day)', 'From (month/day)'), sh_till: L('শেষ (মাস/দিন)', 'To (month/day)', 'To (month/day)'),
  sh_val: L('মেয়াদ', 'Shelf life', 'Shelf life'), sh_hours: L('ঘণ্টা', 'hours', 'hours'), sh_days: L('দিন', 'days', 'days'), sh_empty: L('তথ্য লাগবে — কোনো মেয়াদের নিয়ম নেই। নিয়ম না থাকলে এই সুবিধা বন্ধ থাকে।', 'Data needed — no shelf-life rule yet. With no rule this feature stays off.', 'Data লাগবে — কোনো shelf-life rule নেই। Rule না থাকলে এই feature বন্ধ থাকে।'),
  sh_new: L('নতুন নিয়ম', 'New rule', 'নতুন Rule'), sh_test: L('আজ কোন নিয়ম খাটছে? (পরীক্ষা)', 'Which rule applies? (tester)', 'কোন Rule খাটছে? (Test)'), sh_date: L('তারিখ', 'Date', 'Date'), sh_go: L('দেখুন', 'Check', 'Check'),
  sh_noRule: L('কোনো নিয়ম খাটছে না — তথ্য লাগবে', 'No rule applies — data needed', 'কোনো rule খাটছে না — Data লাগবে'), sh_rule: L('নিয়ম', 'Rule', 'Rule'), sh_bad: L('মেয়াদ শূন্যের বেশি হতে হবে; মাস ১–১২, দিন ১–৩১', 'The value must be above zero; month 1–12, day 1–31', 'Value 0 এর বেশি; month 1–12, day 1–31'),
  sh_wrap: L('বছরের শেষ পার হয়ে গেলেও চলে (যেমন ডিসেম্বর → ফেব্রুয়ারি)', 'May wrap the year end (e.g. December → February)', 'Year end পার হলেও চলে (যেমন Dec → Feb)'), sh_pick: L('আইটেম বাছুন', 'Choose an item', 'Item বাছুন'), sh_catpick: L('ক্যাটাগরি বাছুন', 'Choose a category', 'Category বাছুন'),
  // suppliers
  su_search: L('নাম বা মোবাইল খুঁজুন', 'Search name or mobile', 'নাম বা mobile খুঁজুন'), su_new: L('＋ নতুন সাপ্লায়ার', '＋ New supplier', '＋ নতুন Supplier'), su_empty: L('তথ্য লাগবে — এখনও কোনো সাপ্লায়ার নেই', 'Data needed — no supplier yet', 'Data লাগবে — এখনও কোনো supplier নেই'),
  su_name: L('নাম', 'Name', 'Name'), su_mobile: L('মোবাইল', 'Mobile', 'Mobile'), su_type: L('ধরন', 'Type', 'Type'), su_addr: L('ঠিকানা', 'Address', 'Address'), su_credit: L('বাকির মেয়াদ (দিন)', 'Credit days', 'Credit days'),
  su_open: L('শুরুর বাকি (+ = আমরা দেব)', 'Opening balance (+ = we owe)', 'Opening balance (+ = আমরা দেব)'), su_nid: L('এনআইডি', 'NID', 'NID'), su_tin: L('টিআইএন', 'TIN', 'TIN'), su_note: L('নোট', 'Note', 'Note'), su_active: L('চালু', 'Active', 'Active'),
  su_noacc: L('সাপ্লায়ার দেখতে/বদলাতে অনুমতি বা নতুন SQL লাগবে', 'Permission or the new SQL is needed to see / change suppliers', 'Supplier দেখতে/বদলাতে Permission বা নতুন SQL লাগবে'), su_needname: L('নাম লিখুন', 'Enter the name', 'নাম লিখুন'),
  // access
  ac_person: L('ব্যক্তি', 'Person', 'Person'), ac_role: L('ভূমিকা', 'Role', 'Role'), ac_over: L('কার কী আছে', 'Overview', 'Overview'), ac_give: L('＋ দিন', '＋ Give', '＋ Give'), ac_loc: L('কোন লোকেশনে', 'Which location', 'কোন Location'), ac_until: L('মেয়াদ শেষ (YYYY-MM-DD, ঐচ্ছিক)', 'Valid until (YYYY-MM-DD, optional)', 'Valid until (YYYY-MM-DD, ঐচ্ছিক)'),
  ac_note: L('নোট (ঐচ্ছিক)', 'Note (optional)', 'Note (ঐচ্ছিক)'), ac_forever: L('মেয়াদ নেই', 'no end date', 'no end date'), ac_nobody: L('কেউ নেই', 'nobody', 'কেউ নেই'), ac_hint: L('মালিক সবসময় পারেন। ব্যক্তিকে দিলে লোকেশন ও মেয়াদ ঠিক করা যায়; ভূমিকাকে দিলে সেই ভূমিকার সবাই পায়। আটকে গেলে স্টাফ "জরুরি অনুরোধ" পাঠাতে পারে।', 'The owner always may. A grant to a person can be limited by location and date; a grant to a role covers everyone with that role. A blocked person can send an emergency request.', 'Owner সবসময় পারেন। Person কে দিলে location ও মেয়াদ ঠিক করা যায়; Role কে দিলে সেই role এর সবাই পায়। আটকে গেলে staff "জরুরি request" পাঠাতে পারে।'),
  ac_baddate: L('তারিখ YYYY-MM-DD ফরম্যাটে লিখুন', 'Write the date as YYYY-MM-DD', 'Date YYYY-MM-DD ফরম্যাটে লিখুন'), ac_nopeople: L('তথ্য লাগবে — কোনো সক্রিয় স্টাফ পাওয়া যায়নি', 'Data needed — no active staff found', 'Data লাগবে — কোনো active staff পাওয়া যায়নি'), ac_em: L('জরুরি অনুরোধ দেখুন', 'See emergency requests', 'জরুরি Request দেখুন'),
  g_view_cost: L('ক্রয়মূল্য (কস্ট) দেখা', 'See cost', 'Cost দেখা'), g_view_profit: L('লাভ/ক্ষতি দেখা', 'See profit / loss', 'Profit/Loss দেখা'), g_view_reports: L('রিপোর্ট দেখা', 'See reports', 'Report দেখা'),
  g_export_data: L('ডেটা এক্সপোর্ট', 'Export data', 'Data Export'), g_salary_view: L('বেতন দেখা', 'See salaries', 'Salary দেখা'), g_supplier_manage: L('সাপ্লায়ার পরিচালনা', 'Manage suppliers', 'Supplier পরিচালনা'), g_settings_invoice: L('ইনভয়েস সেটিংস', 'Invoice settings', 'Invoice settings'),
  // role favourites
  rf_role: L('ভূমিকা বাছুন', 'Choose a role', 'Role বাছুন'), rf_add: L('সামনে রাখার মেনু যোগ করুন', 'Add a menu item to the front', 'সামনে রাখার Menu যোগ করুন'), rf_empty: L('তথ্য লাগবে — এই ভূমিকার জন্য কিছু ঠিক করা নেই', 'Data needed — nothing set for this role', 'Data লাগবে — এই role এর জন্য কিছু ঠিক করা নেই'),
  rf_note: L('যতক্ষণ কেউ নিজে প্রিয় না বাছে, ততক্ষণ তার হোমে এগুলো সামনে থাকে।', 'These sit in front on the home screen until the person pins their own.', 'যতক্ষণ কেউ নিজে favourite না বাছে, তার Home এ এগুলো সামনে থাকে।'),
  rf_none: L('যোগ করার মতো মেনু নেই', 'Nothing left to add', 'যোগ করার মতো Menu নেই'),
};
const T = (k) => lab(X[k]);
const DAYS = { sat: L('শনিবার', 'Saturday', 'Saturday'), sun: L('রবিবার', 'Sunday', 'Sunday'), mon: L('সোমবার', 'Monday', 'Monday'), tue: L('মঙ্গলবার', 'Tuesday', 'Tuesday'), wed: L('বুধবার', 'Wednesday', 'Wednesday'), thu: L('বৃহস্পতিবার', 'Thursday', 'Thursday'), fri: L('শুক্রবার', 'Friday', 'Friday') };
const MONTHS = [['জানুয়ারি', 'January'], ['ফেব্রুয়ারি', 'February'], ['মার্চ', 'March'], ['এপ্রিল', 'April'], ['মে', 'May'], ['জুন', 'June'], ['জুলাই', 'July'], ['আগস্ট', 'August'], ['সেপ্টেম্বর', 'September'], ['অক্টোবর', 'October'], ['নভেম্বর', 'November'], ['ডিসেম্বর', 'December']];
const monthName = (m) => (S.lang === 'bn' ? MONTHS[m - 1][0] : MONTHS[m - 1][1]);
const GRANTS = ['view_cost', 'view_profit', 'view_reports', 'export_data', 'salary_view', 'supplier_manage', 'settings_invoice'];
const gLabel = (c) => lab(X['g_' + c]);

// ---------- small helpers ----------
const rawRule = (k) => { const r = B.ENV.rules && B.ENV.rules[k]; return r ? r.value : undefined; };
const tg = (on, act, attrs = '', label) => `<button class="tog ${on ? 'on' : ''}" data-act="${act}" ${attrs} aria-pressed="${!!on}">${esc(label || (on ? T('on') : T('off')))}</button>`;
const needChip = () => `<span class="chip warn">${esc(T('need'))}</span>`;
const frame = (titleKey, html) => shell(T(titleKey), `<div id="s2_body">${html}</div>`, 'settings2');
async function setRule(key, value, redraw = true) {
  const { error } = await sb.rpc('set_rule', { p_key: key, p_value: value });
  if (error) { if (/bad_value/.test(error.message || '')) toast(T('badv')); else fail(error); return false; }
  await B.reloadRules(); toast(T('saved')); if (redraw) view(); return true;
}
const opts = (arr, sel, blank) => (blank !== undefined ? `<option value="">${esc(blank)}</option>` : '') + arr.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(sel) ? 'selected' : ''}>${esc(l)}</option>`).join('');
const dateOk = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s), d = m && new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])); return !!(m && d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3]); };
const stepFor = (v) => (v >= 100 ? 10 : v >= 10 ? 1 : v >= 2 ? 0.5 : v >= 0.5 ? 0.1 : 0.01);
const round6 = (n) => Math.round(n * 1e6) / 1e6;

const Z = { tab: 'person', user: '', role: '', uScope: '', fav: null };
const cache = {};   // per-visit data

// ---------- router ----------
const PAGES = { fiscal: pgFiscal, vat: pgVat, barcode: pgBarcode, noperm: pgNoperm, stock: pgStock, disc: pgDisc, units: pgUnits, shelf: pgShelf, suppliers: pgSuppliers, access: pgAccess, fav: pgFav };
async function view() {
  if (!S.ctx || !S.ctx.is_owner) return (location.hash = '#/home');
  const pg = location.hash.replace(/^#\/?/, '').split('/')[1] || '';
  shell(T('title'), `<p class="muted">${esc(t('loading'))}</p>`, !pg || 'settings2');
  try { await B.loadStatic(); if (!B.ENV.rules) await B.reloadRules(); } catch (e) { /* defaults */ }
  if (pg && PAGES[pg]) { try { await PAGES[pg](); } catch (e) { fail(e); } return; }
  hub();
}
function hub() {
  const R = (k, fb) => B.rule(k, fb);
  const fm = R('fiscal_year_start_month', null), fd = R('fiscal_year_start_day', null), wk = R('week_start', null);
  const sum = {
    fiscal: (fm ? monthName(fm) + ' ' + (fd || 1) : lab(L('জানুয়ারি ১ (ক্যালেন্ডার)', 'January 1 (calendar)', 'January 1 (calendar)'))) + ' · ' + lab(DAYS[wk || 'sat']),
    vat: (R('vat_on', false) ? T('on') : T('off')) + ' · ' + (R('vat_rate', null) !== null ? R('vat_rate', 0) + '%' : T('need')),
    barcode: T('bc_cam') + ': ' + (R('barcode_camera_on', false) ? T('on') : T('off')) + ' · ' + T('bc_dev').split(' ')[0] + ': ' + (R('barcode_device_on', false) ? T('on') : T('off')),
    noperm: R('ui_noperm_mode', 'lock') === 'hide' ? T('np_hide') : T('np_lock'),
    stock: T('st_' + R('stock_negative_mode', 'warn')),
    disc: '৳ ' + (R('discount_mode_amount_on', true) !== false ? T('on') : T('off')) + ' · % ' + (R('discount_mode_percent_on', true) !== false ? T('on') : T('off')),
  };
  const invD = lab(L('টেমপ্লেট, কাগজ, লোগো, বারকোড লেবেল', 'Templates, paper, logo, barcode labels', 'Template, Paper, Logo, Barcode label'));
  const card = (title, desc, to) => `<div class="card item s2card" data-act="go" data-v="${to}" style="cursor:pointer"><div><div class="nm">${esc(title)}</div>${desc ? `<div class="muted" style="font-size:.85rem">${esc(desc)}</div>` : ''}</div><span class="muted" style="font-size:1.4rem">›</span></div>`;
  const keys = ['fiscal', 'vat', 'barcode', 'noperm', 'stock', 'disc', 'units', 'shelf', 'suppliers', 'access', 'fav'];
  shell(T('title'), keys.map((k) => card(T(k === 'suppliers' ? 'c_sup' : 'c_' + k), sum[k] || T(k === 'suppliers' ? 'd_sup' : 'd_' + k), 'settings2/' + k)).join('')
    + card(T('c_inv'), invD, 'invoice') + card(T('c_rules'), '', 'rulehub') + card(T('c_old'), '', 'settings'), true);
}

// ---------- fiscal year / week ----------
function fyPreview(m, d) {
  const td = today(), y = Number(td.slice(0, 4));
  const mk = (yy) => { const last = new Date(Date.UTC(yy, m, 0)).getUTCDate(); return new Date(Date.UTC(yy, m - 1, Math.min(d, last))); };
  let st = mk(y); if (td < st.toISOString().slice(0, 10)) st = mk(y - 1);
  const en = new Date(mk(st.getUTCFullYear() + 1).getTime() - 86400000);
  return st.toISOString().slice(0, 10) + ' → ' + en.toISOString().slice(0, 10);
}
function pgFiscal() {
  const m = B.rule('fiscal_year_start_month', null), d = B.rule('fiscal_year_start_day', null), wk = B.rule('week_start', null);
  frame('c_fiscal', `<div class="card stack"><b>${esc(T('c_fiscal'))}</b>
      <div><label>${esc(T('fy_m'))}</label><select id="fy_m">${opts(MONTHS.map((_, i) => [i + 1, monthName(i + 1)]), m, T('fy_cal'))}</select></div>
      <div><label>${esc(T('fy_d'))}</label><input id="fy_d" inputmode="numeric" value="${d === null ? '' : esc(d)}" placeholder="1"></div>
      <div class="notice ok" id="fy_prev">${esc(T('fy_now'))}: ${esc(fyPreview(m || 1, d || 1))}</div>
      <div class="row"><button class="primary full" data-act="s2_fy_save">${esc(T('save'))}</button><button class="full" data-act="s2_fy_reset">${esc(T('reset'))}</button></div></div>
    <div class="card stack"><b>${esc(T('wk'))}</b><div class="muted" style="font-size:.85rem">${esc(T('wk_d'))}</div>
      <div class="row wrap">${Object.keys(DAYS).map((k) => tg((wk || 'sat') === k, 's2_wk', `data-v="${k}"`, lab(DAYS[k]))).join('')}</div></div>`);
}
// ---------- VAT ----------
function pgVat() {
  const on = B.rule('vat_on', false) === true, rate = B.rule('vat_rate', null);
  frame('c_vat', `<div class="card stack"><div class="row between"><b>${esc(T('vat_on'))}</b>${tg(on, 's2_sw', 'data-k="vat_on"')}</div></div>
    <div class="card stack"><b>${esc(T('vat_rate'))}</b>${rate === null ? needChip() : ''}<div class="row"><input id="vat_rate" inputmode="decimal" value="${rate === null ? '' : esc(rate)}" placeholder="%" style="flex:1"><button class="mini" data-act="s2_num_step" data-k="vat_rate" data-d="-0.5" aria-label="-">−</button><button class="mini" data-act="s2_num_step" data-k="vat_rate" data-d="0.5" aria-label="+">＋</button></div>
      <div class="row"><button class="primary full" data-act="s2_num_save" data-k="vat_rate" data-max="100">${esc(T('save'))}</button></div></div>
    <div class="notice ok">${esc(T('vat_note'))}</div>`);
}
// ---------- barcode ----------
function pgBarcode() {
  frame('c_barcode', ['cam', 'dev'].map((k) => `<div class="card stack"><div class="row between"><b>${esc(T('bc_' + k))}</b>${tg(B.rule('barcode_' + (k === 'cam' ? 'camera' : 'device') + '_on', false) === true, 's2_sw', `data-k="barcode_${k === 'cam' ? 'camera' : 'device'}_on"`)}</div>
    <div class="muted" style="font-size:.88rem">${esc(T('bc_' + k + '_d'))}</div></div>`).join(''));
}
// ---------- no-permission display ----------
function pgNoperm() {
  const m = B.rule('ui_noperm_mode', 'lock') === 'hide' ? 'hide' : 'lock';
  frame('c_noperm', `<div class="card stack"><b>${esc(T('c_noperm'))}</b><div class="row wrap">${tg(m === 'lock', 's2_choice', 'data-k="ui_noperm_mode" data-v="lock"', T('np_lock'))}${tg(m === 'hide', 's2_choice', 'data-k="ui_noperm_mode" data-v="hide"', T('np_hide'))}</div></div>
    <button class="full" data-act="go" data-v="matrix">${esc(T('np_more'))} ›</button>`);
}
// ---------- stock negative + costing ----------
function pgStock() {
  const m = B.rule('stock_negative_mode', 'warn');
  frame('c_stock', `<div class="card stack"><b>${esc(T('c_stock'))}</b>${['allow', 'warn', 'block'].map((k) => `<div class="row between"><div><div><b>${esc(T('st_' + k))}</b></div><div class="muted" style="font-size:.82rem">${esc(T('st_' + k + '_d'))}</div></div>${tg(m === k, 's2_choice', `data-k="stock_negative_mode" data-v="${k}"`, m === k ? T('on') : T('off'))}</div>`).join('')}</div>
    <div class="card stack"><b>${esc(T('costing'))}</b><select data-s2sel="costing_method">${opts([['avg', lab(L('গড় (average)', 'Average', 'Average'))]], B.rule('costing_method', 'avg'))}</select><div class="muted" style="font-size:.85rem">${esc(T('costing_d'))}</div></div>`);
}
// ---------- discount modes ----------
function pgDisc() {
  const a = B.rule('discount_mode_amount_on', true) !== false, p = B.rule('discount_mode_percent_on', true) !== false;
  frame('c_disc', `<div class="card stack"><div class="row between"><b>${esc(T('dm_amt'))}</b>${tg(a, 's2_sw', 'data-k="discount_mode_amount_on"')}</div></div>
    <div class="card stack"><div class="row between"><b>${esc(T('dm_pct'))}</b>${tg(p, 's2_sw', 'data-k="discount_mode_percent_on"')}</div></div>
    ${!a && !p ? `<div class="notice bad">${esc(T('dm_warn'))}</div>` : ''}<div class="notice ok">${esc(T('dm_note'))}</div>`);
}

// ---------- shared data ----------
async function loadItems() {
  const r = await sb.from('items').select('id,code,name_bn,name_en,name_mix,unit,category,category_bn').order('code');
  cache.items = r.data || []; return cache.items;
}
const itemName = (id) => { const i = (cache.items || []).find((x) => x.id === id); return i ? i.code + ' · ' + nm(i) : id; };
async function loadUnits() {
  const r = await sb.from('option_lists').select('value_code,label_bn,label_en,label_mix,active').eq('list_code', 'units').order('sort');
  const rows = (r.data || []).filter((x) => x.active !== false).map((x) => x.value_code);
  cache.units = rows.length ? rows : ['kg', 'piece', 'box', 'pack', 'pound', 'gram'];
}

// ---------- unit conversions ----------
async function pgUnits() {
  await Promise.all([loadItems(), loadUnits()]);
  const r = await sb.from('unit_conversions').select('*').order('id');
  if (r.error) return frame('c_units', `<div class="notice bad">${esc(T('sql'))}</div>`);
  cache.conv = r.data || []; drawUnits();
}
function convRow(c) {
  return `<div class="card stack s2conv"><div class="row between"><b>1 ${esc(c.from_unit)} = ${esc(String(c.factor))} ${esc(c.to_unit)}</b><button class="mini" data-act="s2_cv_del" data-id="${c.id}" aria-label="${esc(T('remove'))}">✕</button></div>
    <div class="row"><button class="mini" data-act="s2_cv_step" data-id="${c.id}" data-d="-1" aria-label="−">−</button><input id="cv_f_${c.id}" inputmode="decimal" value="${esc(String(c.factor))}" style="flex:1"><button class="mini" data-act="s2_cv_step" data-id="${c.id}" data-d="1" aria-label="+">＋</button>
      <button class="primary" data-act="s2_cv_save" data-id="${c.id}">${esc(T('save'))}</button></div>
    ${c.note ? `<div class="muted" style="font-size:.82rem">${esc(c.note)}</div>` : ''}</div>`;
}
function drawUnits() {
  const sc = Z.uScope || null, rows = (cache.conv || []).filter((c) => (c.item_id || null) === sc), glob = (cache.conv || []).filter((c) => !c.item_id).length;
  const U = cache.units;
  frame('c_units', `<datalist id="s2_units">${U.map((u) => `<option value="${esc(u)}"></option>`).join('')}</datalist>
    <div class="card stack"><label>${esc(T('u_scope'))}</label><select id="u_scope">${opts([['', T('u_global')], ...cache.items.map((i) => [i.id, i.code + ' · ' + nm(i)])], Z.uScope)}</select>
      ${sc && glob ? `<div class="muted" style="font-size:.82rem">${glob} ${esc(T('u_also'))}</div>` : ''}</div>
    ${rows.map(convRow).join('') || `<div class="notice warn">${esc(T('u_empty'))}</div>`}
    <div class="card stack"><b>${esc(T('u_new'))}</b><div class="muted" style="font-size:.82rem">${esc(T('u_rev'))}</div>
      <div class="row"><div style="flex:1"><label>${esc(T('u_from'))}</label><input id="cv_from" list="s2_units" autocomplete="off"></div><div style="flex:1"><label>${esc(T('u_to'))}</label><input id="cv_to" list="s2_units" autocomplete="off"></div></div>
      <div><label>${esc(T('u_factor'))}</label><input id="cv_fac" inputmode="decimal"></div><div><label>${esc(T('u_note'))}</label><input id="cv_note"></div>
      <button class="primary full" data-act="s2_cv_add">${esc(T('add'))}</button>
      ${sc ? '' : `<div class="muted" style="font-size:.82rem">${esc(T('u_preset'))}</div><div class="row wrap"><button class="tog" data-act="s2_cv_preset" data-f="kg" data-t="gram" data-n="1000">1 kg = 1000 gram</button><button class="tog" data-act="s2_cv_preset" data-f="pound" data-t="kg" data-n="0.45359237">1 pound = 0.4536 kg</button></div>`}</div>`);
}
async function cvSet(item, from, to, factor, note) {
  const { error } = await sb.rpc('set_unit_conversion', { p_item: item, p_from: from, p_to: to, p_factor: factor, p_note: note || null });
  if (error) { if (/bad_factor/.test(error.message || '')) toast(T('u_bad')); else fail(error); return false; }
  return true;
}
async function cvReload() { const r = await sb.from('unit_conversions').select('*').order('id'); cache.conv = r.data || []; drawUnits(); }

// ---------- shelf life ----------
async function pgShelf() {
  await loadItems();
  const r = await sb.from('shelf_life_rules').select('*').order('id');
  if (r.error) return frame('c_shelf', `<div class="notice bad">${esc(T('sql'))}</div>`);
  cache.shelf = r.data || []; drawShelf();
}
const cats = () => [...new Set((cache.items || []).map((i) => i.category).filter(Boolean))];
const catName = (c) => { const i = (cache.items || []).find((x) => x.category === c); return (i && i.category_bn && S.lang === 'bn' ? i.category_bn : c); };
const scopeText = (r) => (r.item_id ? itemName(r.item_id) : r.category ? T('sh_cat') + ': ' + catName(r.category) : T('sh_all'));
const seasonText = (r) => (r.start_month ? `${r.season_label ? r.season_label + ' · ' : ''}${monthName(r.start_month)} ${r.start_day} → ${monthName(r.end_month)} ${r.end_day}` : (r.season_label ? r.season_label + ' · ' : '') + T('sh_year'));
function shelfCard(r) {
  return `<div class="card stack" id="sh_${r.id}" style="${r.active ? '' : 'opacity:.6'}"><div class="row between"><b>${esc(scopeText(r))}</b>${tg(r.active, 's2_sh_act', `data-id="${r.id}"`)}</div>
    <div class="muted" style="font-size:.88rem">${esc(seasonText(r))}</div>
    <div class="row wrap"><button class="mini" data-act="s2_sh_step" data-id="${r.id}" data-d="-1" aria-label="−">−</button><b style="min-width:96px;text-align:center">${esc(String(r.value))} ${esc(T('sh_' + r.unit))}</b><button class="mini" data-act="s2_sh_step" data-id="${r.id}" data-d="1" aria-label="+">＋</button>
      <button data-act="s2_sh_edit" data-id="${r.id}" style="padding:0 12px">${esc(T('edit'))}</button><button class="mini" data-act="s2_sh_del" data-id="${r.id}" aria-label="${esc(T('remove'))}">✕</button></div></div>`;
}
function drawShelf() {
  frame('c_shelf', `${cache.shelf.map(shelfCard).join('') || `<div class="notice warn">${esc(T('sh_empty'))}</div>`}
    <button class="full" data-act="s2_sh_new">${esc(T('sh_new'))}</button>
    <h2 style="margin-top:18px">${esc(T('sh_test'))}</h2>
    <div class="card stack"><div><label>${esc(T('sh_pick'))}</label><select id="sh_t_item">${opts(cache.items.map((i) => [i.id, i.code + ' · ' + nm(i)]), '', T('none'))}</select></div>
      <div><label>${esc(T('sh_date'))}</label><input id="sh_t_date" value="${today()}" inputmode="numeric"></div>
      <button class="primary full" data-act="s2_sh_test">${esc(T('sh_go'))}</button><div id="sh_t_out"></div></div>`);
}
function shelfSheet(r) {
  const sc = r ? (r.item_id ? 'item' : r.category ? 'cat' : 'all') : 'all', yr = r ? !r.start_month : true;
  const md = (id, m, d) => `<div class="row"><select id="${id}_m" style="flex:2">${opts(MONTHS.map((_, i) => [i + 1, monthName(i + 1)]), m || 1)}</select><input id="${id}_d" inputmode="numeric" value="${d || 1}" style="flex:1"></div>`;
  openSheet(`<h2>${esc(r ? T('edit') : T('sh_new'))}</h2><div class="stack">
    <div><label>${esc(T('sh_scope'))}</label><select id="sh_scope">${opts([['all', T('sh_all')], ['cat', T('sh_cat')], ['item', T('sh_item')]], sc)}</select></div>
    <div id="sh_cat_w"><label>${esc(T('sh_catpick'))}</label><select id="sh_cat">${opts(cats().map((c) => [c, catName(c)]), r && r.category, T('none'))}</select></div>
    <div id="sh_item_w"><label>${esc(T('sh_pick'))}</label><select id="sh_item">${opts(cache.items.map((i) => [i.id, i.code + ' · ' + nm(i)]), r && r.item_id, T('none'))}</select></div>
    <div class="row between"><b>${esc(T('sh_year'))}</b>${tg(yr, 'sheettog', 'id="sh_year"')}</div>
    <div id="sh_season_w"><div><label>${esc(T('sh_season'))}</label><input id="sh_label" value="${esc(r && r.season_label || '')}"></div>
      <label>${esc(T('sh_from'))}</label>${md('sh_s', r && r.start_month, r && r.start_day)}<label>${esc(T('sh_till'))}</label>${md('sh_e', r && r.end_month, r && r.end_day)}<div class="muted" style="font-size:.8rem">${esc(T('sh_wrap'))}</div></div>
    <div class="row"><div style="flex:1"><label>${esc(T('sh_val'))}</label><input id="sh_val" inputmode="decimal" value="${r ? esc(String(r.value)) : ''}"></div><div style="flex:1"><label>&nbsp;</label><select id="sh_unit">${opts([['hours', T('sh_hours')], ['days', T('sh_days')]], r ? r.unit : 'days')}</select></div></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="s2_sh_save" data-id="${r ? r.id : ''}">${esc(T('save'))}</button></div></div>`);
  shelfToggle();
}
function shelfToggle() {
  const sc = ($('#sh_scope') || {}).value, yr = $('#sh_year') && $('#sh_year').classList.contains('on');
  const show = (id, on) => { const e = $(id); if (e) e.style.display = on ? '' : 'none'; };
  show('#sh_cat_w', sc === 'cat'); show('#sh_item_w', sc === 'item'); show('#sh_season_w', !yr);
}

// ---------- suppliers ----------
async function pgSuppliers() {
  const [r] = await Promise.all([sb.from('suppliers').select('*').order('name'), loadUnits()]);
  if (r.error) return frame('c_sup', `<div class="notice bad">${esc(T('su_noacc'))}</div>`);
  cache.sup = r.data || []; cache.supq = ''; cache.stypes = (B.ENV.lists && B.ENV.lists.supplier_types || []).filter((x) => x.active !== false); drawSuppliers();
}
const typeName = (c) => { const x = (cache.stypes || []).find((y) => y.value_code === c); return x ? pick(x, 'label') : c || ''; };
function drawSuppliers() {
  const q = (cache.supq || '').toLowerCase(), list = cache.sup.filter((s) => !q || (s.name || '').toLowerCase().includes(q) || (s.mobile || '').includes(q));
  frame('c_sup', `<div class="row"><input id="su_q" type="search" placeholder="${esc(T('su_search'))}" value="${esc(cache.supq || '')}" style="flex:1"></div>
    <div id="su_list">${list.map((s) => `<div class="card item" data-act="s2_su_edit" data-id="${s.id}" style="cursor:pointer;${s.active ? '' : 'opacity:.55'}"><div><div class="nm">${esc(s.name)}</div>
      <div class="muted" style="font-size:.85rem">${s.type_code ? esc(typeName(s.type_code)) : ''}${s.mobile ? ' · ' + esc(s.mobile) : ''}${s.credit_days !== null && s.credit_days !== undefined ? ' · ' + s.credit_days + 'd' : ''}</div></div>
      <div class="pr">${s.opening_balance === null || s.opening_balance === undefined ? needChip() : '৳ ' + esc(String(s.opening_balance))}</div></div>`).join('') || `<div class="notice warn">${esc(T('su_empty'))}</div>`}</div>
    <button class="primary full" data-act="s2_su_new" style="margin-top:10px">${esc(T('su_new'))}</button>`);
}
function supSheet(s) {
  const v = (k) => esc(s && s[k] !== null && s[k] !== undefined ? String(s[k]) : '');
  openSheet(`<h2>${esc(s ? s.name : T('su_new'))}</h2><div class="stack">
    <div><label>${esc(T('su_name'))} *</label><input id="su_name" value="${v('name')}"></div>
    <div class="row"><div style="flex:1"><label>${esc(T('su_mobile'))}</label><input id="su_mobile" inputmode="tel" value="${v('mobile')}"></div>
      <div style="flex:1"><label>${esc(T('su_type'))}</label><select id="su_type">${opts((cache.stypes || []).map((x) => [x.value_code, pick(x, 'label')]), s && s.type_code, T('none'))}</select></div></div>
    <div><label>${esc(T('su_addr'))}</label><input id="su_addr" value="${v('address')}"></div>
    <div class="row"><div style="flex:1"><label>${esc(T('su_credit'))}</label><input id="su_credit" inputmode="numeric" value="${v('credit_days')}" placeholder="${esc(T('need'))}"></div>
      <div style="flex:1"><label>${esc(T('su_open'))}</label><input id="su_open" inputmode="decimal" value="${v('opening_balance')}" placeholder="${esc(T('need'))}"></div></div>
    <div class="row"><div style="flex:1"><label>${esc(T('su_nid'))}</label><input id="su_nid" value="${v('nid')}"></div><div style="flex:1"><label>${esc(T('su_tin'))}</label><input id="su_tin" value="${v('tin')}"></div></div>
    <div><label>${esc(T('su_note'))}</label><input id="su_note" value="${v('note')}"></div>
    <div class="row between"><b>${esc(T('su_active'))}</b>${tg(!s || s.active, 'sheettog', 'id="su_active"')}</div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="s2_su_save" data-id="${s ? s.id : ''}">${esc(T('save'))}</button></div></div>`);
}

// ---------- access manager ----------
async function pgAccess() {
  const [pr, ug, ro, rg, gd] = await Promise.all([sb.from('profiles').select('id,staff_id,full_name,status').order('staff_id'), sb.from('user_grants').select('*'), sb.from('roles').select('*').order('sort'), sb.from('rule_grants').select('*'), sb.from('grant_defs').select('*')]);
  if (ug.error) return frame('c_access', `<div class="notice bad">${esc(T('sql'))}</div>`);
  cache.people = (pr.data || []).filter((p) => p.status === 'active' || p.status === undefined); cache.ug = ug.data || []; cache.roles = (ro.data || []).filter((x) => x.active !== false && x.code !== 'owner'); cache.rg = rg.data || [];
  cache.gdef = {}; (gd.data || []).forEach((g) => { cache.gdef[g.grant_code] = g; });
  if (!Z.user && cache.people[0]) Z.user = cache.people[0].id;
  if (!cache.locs) cache.locs = B.ENV.locs || [];
  drawAccess();
}
const personName = (id) => { const p = (cache.people || []).find((x) => x.id === id); return p ? (p.full_name || p.staff_id) + ' (' + p.staff_id + ')' : id; };
const locName = (id) => (id ? nm((B.ENV.locs || []).find((l) => l.id === id) || { name_bn: '#' + id }) : T('allLoc'));
const grantChip = (g, withName) => `<span class="chip">${withName ? esc(personName(g.user_id)) + ' · ' : ''}${esc(locName(g.location_id))} · ${g.valid_until ? esc(dday(g.valid_until)) : esc(T('ac_forever'))}
  ${withName ? '' : `<button class="mini" style="min-height:28px;min-width:28px;margin-inline-start:6px" data-act="s2_ac_del" data-g="${esc(g.grant_code)}" data-l="${g.location_id === null ? '' : g.location_id}" aria-label="${esc(T('remove'))}">✕</button>`}</span>`;
function drawAccess() {
  const tabs = [['person', 'ac_person'], ['role', 'ac_role'], ['over', 'ac_over']];
  let body = '';
  if (Z.tab === 'person') {
    body = !cache.people.length ? `<div class="notice warn">${esc(T('ac_nopeople'))}</div>` : `<div class="card"><label>${esc(T('ac_person'))}</label><select id="ac_user">${opts(cache.people.map((p) => [p.id, (p.full_name || p.staff_id) + ' (' + p.staff_id + ')']), Z.user)}</select></div>` +
      GRANTS.map((c) => { const mine = cache.ug.filter((g) => g.user_id === Z.user && g.grant_code === c);
        return `<div class="card stack"><div class="row between"><b>${esc(gLabel(c))}</b><button data-act="s2_ac_give" data-g="${c}">${esc(T('ac_give'))}</button></div>
          <div class="row wrap">${mine.map((g) => grantChip(g)).join('') || `<span class="muted" style="font-size:.85rem">${esc(T('none'))}</span>`}</div></div>`; }).join('');
  } else if (Z.tab === 'role') {
    body = GRANTS.map((c) => `<div class="card stack"><b>${esc(gLabel(c))}</b>${cache.gdef[c] ? '' : needChip()}<div class="row wrap">${cache.roles.map((ro) => tg(cache.rg.some((g) => g.grant_code === c && g.role_code === ro.code && g.allowed), 's2_ac_role', `data-g="${c}" data-r="${esc(ro.code)}"`, nm(ro))).join('') || `<span class="muted">${esc(T('none'))}</span>`}</div></div>`).join('');
  } else {
    body = GRANTS.map((c) => { const rs = cache.roles.filter((ro) => cache.rg.some((g) => g.grant_code === c && g.role_code === ro.code && g.allowed)), us = cache.ug.filter((g) => g.grant_code === c);
      return `<div class="card stack"><b>${esc(gLabel(c))}</b><div class="row wrap">${rs.map((ro) => `<span class="chip ok">${esc(nm(ro))}</span>`).join('')}${us.map((g) => grantChip(g, true)).join('')}${!rs.length && !us.length ? `<span class="muted" style="font-size:.85rem">${esc(T('ac_nobody'))}</span>` : ''}</div></div>`; }).join('');
  }
  frame('c_access', `<div class="notice ok">${esc(T('ac_hint'))}</div><div class="row wrap" style="margin-bottom:10px">${tabs.map(([k, l]) => `<button class="tog ${Z.tab === k ? 'on' : ''}" data-act="s2_ac_tab" data-v="${k}">${esc(T(l))}</button>`).join('')}</div>${body}
    <button class="full" data-act="go" data-v="emergency" style="margin-top:8px">${esc(T('ac_em'))} ›</button>`);
}
function giveSheet(code) {
  openSheet(`<h2>${esc(gLabel(code))}</h2><p class="muted">${esc(personName(Z.user))}</p><div class="stack">
    <div><label>${esc(T('ac_loc'))}</label><select id="ac_loc">${opts((B.ENV.locs || []).map((l) => [l.id, nm(l)]), '', T('allLoc'))}</select></div>
    <div><label>${esc(T('ac_until'))}</label><input id="ac_until" inputmode="numeric" placeholder="2026-12-31"></div>
    <div><label>${esc(T('ac_note'))}</label><input id="ac_note"></div>
    <div class="row"><button class="full" data-act="closesheet">${esc(T('cancel'))}</button><button class="primary full" data-act="s2_ac_save" data-g="${code}">${esc(T('save'))}</button></div></div>`);
}

// ---------- role favourites ----------
async function pgFav() {
  const [ro, rf] = await Promise.all([sb.from('roles').select('*').order('sort'), sb.from('role_favourites').select('*').order('sort')]);
  if (rf.error) return frame('c_fav', `<div class="notice bad">${esc(T('sql'))}</div>`);
  cache.froles = (ro.data || []).filter((x) => x.active !== false && x.code !== 'owner'); cache.rf = rf.data || [];
  if (!Z.role || !cache.froles.find((r) => r.code === Z.role)) Z.role = (cache.froles[0] || {}).code || '';
  drawFav();
}
const navEntries = () => (window.BOS_NAV && window.BOS_NAV.entries ? window.BOS_NAV.entries() : []);
const favKey = (e) => (e.kind === 'f' ? { kind: 'form', key: e.code } : { kind: 'route', key: e.route });
function drawFav() {
  const mine = cache.rf.filter((x) => x.role_code === Z.role).sort((a, b) => a.sort - b.sort), E = navEntries();
  const lbl = (x) => { const e = E.find((y) => { const k = favKey(y); return k.kind === x.kind && k.key === x.key; }); return e ? e.label : x.key; };
  const free = E.filter((e) => e.key !== 'r:home' && !mine.some((x) => { const k = favKey(e); return x.kind === k.kind && x.key === k.key; }));
  frame('c_fav', `<div class="notice ok">${esc(T('rf_note'))}</div><div class="card"><label>${esc(T('rf_role'))}</label><select id="rf_role">${opts(cache.froles.map((r) => [r.code, nm(r)]), Z.role)}</select></div>
    ${mine.map((x, i) => `<div class="card item"><b>${i + 1}. ${esc(lbl(x))}</b><div class="row"><button class="mini" data-act="s2_rf_move" data-k="${esc(x.kind)}" data-key="${esc(x.key)}" data-d="-1" aria-label="${esc(T('up'))}">↑</button><button class="mini" data-act="s2_rf_move" data-k="${esc(x.kind)}" data-key="${esc(x.key)}" data-d="1" aria-label="${esc(T('down'))}">↓</button><button class="mini" data-act="s2_rf_del" data-k="${esc(x.kind)}" data-key="${esc(x.key)}" aria-label="${esc(T('remove'))}">✕</button></div></div>`).join('') || `<div class="notice warn">${esc(T('rf_empty'))}</div>`}
    ${Z.role ? `<div class="card stack"><label>${esc(T('rf_add'))}</label>${free.length ? `<select id="rf_new">${opts(free.map((e) => [e.key, e.label]), '')}</select><button class="primary full" data-act="s2_rf_add">${esc(T('add'))}</button>` : `<div class="muted">${esc(T('rf_none'))}</div>`}</div>` : ''}`);
}

// ---------- handlers ----------
const val = (id) => ($(id) || {}).value;
const idv = (x) => (/^\d+$/.test(x) ? Number(x) : x);   // numeric ids stay numbers
Object.assign(A.H, {
  s2_sw: (a) => setRule(a.dataset.k, !(B.rule(a.dataset.k, a.dataset.k.startsWith('discount_mode')) === true)),
  s2_choice: (a) => setRule(a.dataset.k, a.dataset.v),
  s2_num_step: (a) => { const e = $('#' + a.dataset.k); const v = (pnum(e.value) || 0) + Number(a.dataset.d); e.value = String(Math.max(0, round6(v))); },
  s2_num_save: (a) => { const n = pnum(val('#' + a.dataset.k)); if (Number.isNaN(n) || (n !== null && (n < 0 || n > Number(a.dataset.max || 1e9)))) return toast(T('badv')); return setRule(a.dataset.k, n); },
  s2_fy_save: async () => { const m = pnum(val('#fy_m')), d = pnum(val('#fy_d'));
    if (Number.isNaN(d) || (d !== null && (d < 1 || d > 31 || d % 1))) return toast(T('badv'));
    if (m === null && d !== null) return toast(T('fy_cal'));
    if (await setRule('fiscal_year_start_month', m, false)) await setRule('fiscal_year_start_day', m === null ? null : d, true); },
  s2_fy_reset: async () => { if (await setRule('fiscal_year_start_month', null, false)) await setRule('fiscal_year_start_day', null, true); },
  s2_wk: (a) => setRule('week_start', a.dataset.v),
  // units
  s2_cv_add: async () => { const from = val('#cv_from').trim(), to = val('#cv_to').trim(), f = pnum(val('#cv_fac'));
    if (!from || !to || from === to || !(f > 0)) return toast(T('u_bad'));
    if (await cvSet(Z.uScope || null, from, to, f, val('#cv_note'))) { toast(T('saved')); await cvReload(); } },
  s2_cv_preset: async (a) => { if (await cvSet(null, a.dataset.f, a.dataset.t, Number(a.dataset.n), null)) { toast(T('saved')); await cvReload(); } },
  s2_cv_save: async (a) => { const c = cache.conv.find((x) => String(x.id) === a.dataset.id), f = pnum(val('#cv_f_' + c.id)); if (!(f > 0)) return toast(T('u_bad'));
    if (await cvSet(c.item_id, c.from_unit, c.to_unit, f, c.note)) { toast(T('saved')); await cvReload(); } },
  s2_cv_step: async (a) => { const c = cache.conv.find((x) => String(x.id) === a.dataset.id), cur = pnum(val('#cv_f_' + c.id)) || Number(c.factor), n = round6(cur + Number(a.dataset.d) * stepFor(cur)); if (!(n > 0)) return toast(T('u_bad'));
    if (await cvSet(c.item_id, c.from_unit, c.to_unit, n, c.note)) await cvReload(); },
  s2_cv_del: async (a) => { const c = cache.conv.find((x) => String(x.id) === a.dataset.id); if (await cvSet(c.item_id, c.from_unit, c.to_unit, null, null)) await cvReload(); },
  // shelf life
  s2_sh_new: () => shelfSheet(null),
  s2_sh_edit: (a) => shelfSheet(cache.shelf.find((x) => String(x.id) === a.dataset.id)),
  s2_sh_act: async (a) => { const r = cache.shelf.find((x) => String(x.id) === a.dataset.id); const { error } = await sb.from('shelf_life_rules').update({ active: !r.active }).eq('id', r.id); if (error) return fail(error); r.active = !r.active; drawShelf(); },
  s2_sh_step: async (a) => { const r = cache.shelf.find((x) => String(x.id) === a.dataset.id), n = round6(Number(r.value) + Number(a.dataset.d)); if (!(n > 0)) return toast(T('sh_bad'));
    const { error } = await sb.from('shelf_life_rules').update({ value: n }).eq('id', r.id); if (error) return fail(error); r.value = n; drawShelf(); },
  s2_sh_del: async (a) => { const { error } = await sb.from('shelf_life_rules').delete().eq('id', idv(a.dataset.id)); if (error) return fail(error); cache.shelf = cache.shelf.filter((x) => String(x.id) !== a.dataset.id); drawShelf(); },
  s2_sh_save: async (a) => {
    const sc = val('#sh_scope'), yr = $('#sh_year').classList.contains('on'), v = pnum(val('#sh_val')), row = { value: v, unit: val('#sh_unit'), season_label: (val('#sh_label') || '').trim() || null, item_id: null, category: null };
    if (!(v > 0)) return toast(T('sh_bad'));
    if (sc === 'item') { row.item_id = val('#sh_item') || null; if (!row.item_id) return toast(T('sh_pick')); } else if (sc === 'cat') { row.category = val('#sh_cat') || null; if (!row.category) return toast(T('sh_catpick')); }
    if (yr) Object.assign(row, { start_month: null, start_day: null, end_month: null, end_day: null, season_label: null });
    else { const sm = pnum(val('#sh_s_m')), sd = pnum(val('#sh_s_d')), em = pnum(val('#sh_e_m')), ed = pnum(val('#sh_e_d'));
      if (![sm, em].every((x) => x >= 1 && x <= 12) || ![sd, ed].every((x) => x >= 1 && x <= 31)) return toast(T('sh_bad')); Object.assign(row, { start_month: sm, start_day: sd, end_month: em, end_day: ed }); }
    const q = a.dataset.id ? sb.from('shelf_life_rules').update(row).eq('id', idv(a.dataset.id)) : sb.from('shelf_life_rules').insert(row);
    const { error } = await q; if (error) return fail(error); closeSheet(); toast(T('saved')); await pgShelf(); },
  s2_sh_test: async () => { const id = val('#sh_t_item'), d = val('#sh_t_date').trim(); if (!id) return toast(T('sh_pick')); if (!dateOk(d)) return toast(T('ac_baddate'));
    const { data, error } = await sb.rpc('shelf_life_for', { p_item: id, p_date: d }); if (error) return fail(error);
    $('#sh_t_out').innerHTML = data ? `<div class="notice ok"><b>${esc(String(data.value))} ${esc(T('sh_' + data.unit))}</b> (= ${esc(String(Math.round(Number(data.hours) * 100) / 100))} ${esc(T('sh_hours'))})<br>${esc(T('sh_rule'))} #${esc(String(data.rule_id))} · ${esc(data.scope === 'item' ? T('sh_item') : data.scope === 'category' ? T('sh_cat') : T('sh_all'))}${data.season ? ' · ' + esc(data.season) : ''}</div>` : `<div class="notice warn">${esc(T('sh_noRule'))}</div>`; },
  // suppliers
  s2_su_new: () => supSheet(null),
  s2_su_edit: (a) => supSheet(cache.sup.find((x) => x.id === a.dataset.id)),
  s2_su_save: async (a) => { const name = val('#su_name').trim(); if (!name) return toast(T('su_needname'));
    const cd = pnum(val('#su_credit')), ob = pnum(val('#su_open')); if (Number.isNaN(cd) || Number.isNaN(ob) || (cd !== null && (cd < 0 || cd % 1))) return toast(T('badv'));
    const patch = { name, mobile: val('#su_mobile').trim(), type_code: val('#su_type'), address: val('#su_addr').trim(), credit_days: cd === null ? '' : cd, opening_balance: ob === null ? '' : ob, nid: val('#su_nid').trim(), tin: val('#su_tin').trim(), note: val('#su_note').trim(), active: $('#su_active').classList.contains('on') };
    const { error } = await sb.rpc('save_supplier', { p_id: a.dataset.id || null, p_patch: patch }); if (error) return fail(error); closeSheet(); toast(T('saved')); await pgSuppliers(); },
  // access
  s2_ac_tab: (a) => { Z.tab = a.dataset.v; drawAccess(); },
  s2_ac_give: (a) => giveSheet(a.dataset.g),
  s2_ac_save: async (a) => { const u = (val('#ac_until') || '').trim(); if (u && !dateOk(u)) return toast(T('ac_baddate')); const loc = val('#ac_loc');
    const { error } = await sb.rpc('set_user_grant', { p_user: Z.user, p_code: a.dataset.g, p_loc: loc === '' ? null : Number(loc), p_until: u ? u + 'T23:59:59+06:00' : null, p_allowed: true, p_note: (val('#ac_note') || '').trim() || null });
    if (error) return fail(error); closeSheet(); toast(T('saved')); await pgAccess(); },
  s2_ac_del: async (a) => { const { error } = await sb.rpc('set_user_grant', { p_user: Z.user, p_code: a.dataset.g, p_loc: a.dataset.l === '' ? null : Number(a.dataset.l), p_until: null, p_allowed: false, p_note: null }); if (error) return fail(error); await pgAccess(); },
  s2_ac_role: async (a) => { const on = cache.rg.some((g) => g.grant_code === a.dataset.g && g.role_code === a.dataset.r && g.allowed);
    const { error } = await sb.rpc('set_grant', { p_code: a.dataset.g, p_role: a.dataset.r, p_allowed: !on }); if (error) return fail(error); await pgAccess(); },
  // role favourites
  s2_rf_add: async () => { const e = navEntries().find((x) => x.key === val('#rf_new')); if (!e) return; const k = favKey(e), mx = cache.rf.filter((x) => x.role_code === Z.role).reduce((m, x) => Math.max(m, x.sort), 0);
    const { error } = await sb.from('role_favourites').upsert({ role_code: Z.role, kind: k.kind, key: k.key, sort: mx + 1 }, { onConflict: 'role_code,kind,key' }); if (error) return fail(error); await pgFav(); },
  s2_rf_del: async (a) => { const { error } = await sb.from('role_favourites').delete().eq('role_code', Z.role).eq('kind', a.dataset.k).eq('key', a.dataset.key); if (error) return fail(error); await pgFav(); },
  s2_rf_move: async (a) => { const mine = cache.rf.filter((x) => x.role_code === Z.role).sort((p, q) => p.sort - q.sort), i = mine.findIndex((x) => x.kind === a.dataset.k && x.key === a.dataset.key), j = i + Number(a.dataset.d);
    if (j < 0 || j >= mine.length) return; [mine[i], mine[j]] = [mine[j], mine[i]];
    const { error } = await sb.from('role_favourites').upsert(mine.map((x, n) => ({ role_code: x.role_code, kind: x.kind, key: x.key, sort: n + 1 })), { onConflict: 'role_code,kind,key' }); if (error) return fail(error); await pgFav(); },
});
document.addEventListener('change', async (e) => {
  const id = e.target.id, ds = e.target.dataset || {};
  if (id === 'u_scope') { Z.uScope = e.target.value; drawUnits(); }
  else if (id === 'ac_user') { Z.user = e.target.value; drawAccess(); }
  else if (id === 'rf_role') { Z.role = e.target.value; drawFav(); }
  else if (id === 'sh_scope') shelfToggle();
  else if (ds.s2sel) await setRule(ds.s2sel, e.target.value);
  else if (id === 'fy_m' || id === 'fy_d') { const m = pnum(val('#fy_m')), d = pnum(val('#fy_d')); const p = $('#fy_prev'); if (p) p.textContent = T('fy_now') + ': ' + fyPreview(m || 1, d >= 1 && d <= 31 ? d : 1); }
});
document.addEventListener('click', (e) => { if (e.target.closest && e.target.closest('#sh_year')) setTimeout(shelfToggle, 0); });
document.addEventListener('input', (e) => { if (e.target.id === 'su_q') { cache.supq = e.target.value; drawSuppliers(); const i = $('#su_q'); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } } });
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { settings2: view });
})();
