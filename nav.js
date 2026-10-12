/* Islamia BOS · UI v2: left drawer, bottom nav, Home v2 (business / accounting, period tabs, favourites).
   Additive: hash routes and data-act handlers are untouched; every page stays reachable. Loaded after rules.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, t, esc, nm, fmt, store, openSheet, closeSheet, fail } = A;
const H = A.H;
const $ = (s, el = document) => el.querySelector(s);
const L = B.L, lab = B.lab;
const BRAND = { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' };   // fixed in every language, never translated

// ---------- labels (3 modes) ----------
const X = {
  menu: L('মেনু', 'Menu', 'Menu'), me: L('আমি', 'Me', 'Me'), search: L('মেনু খুঁজুন…', 'Search menu…', 'Menu খুঁজুন…'), close: L('বন্ধ করুন', 'Close', 'Close'),
  nores: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'), noperm: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), soon: L('শীঘ্রই আসছে', 'Coming soon', 'Coming soon'),
  online: L('অনলাইন', 'Online', 'Online'), offline: L('অফলাইন', 'Offline', 'Offline'), pin: L('প্রিয়তে রাখুন', 'Pin to favourites', 'Favourite-এ রাখুন'), unpin: L('প্রিয় থেকে সরান', 'Unpin', 'Favourite থেকে সরান'),
  g_dash: L('ড্যাশবোর্ড', 'Dashboard', 'Dashboard'), g_acc: L('হিসাব', 'Accounting', 'Accounting (হিসাব)'), g_item: L('আইটেম', 'Items', 'Item'), g_cust: L('কাস্টমার', 'Customers', 'Customer'),
  g_supp: L('সরবরাহকারী', 'Suppliers', 'Supplier'), g_sale: L('বিক্রি', 'Sales', 'Sale (বিক্রি)'), g_purch: L('ক্রয়', 'Purchase', 'Purchase'), g_ops: L('স্টক ও কারখানা', 'Stock & factory', 'Stock ও Factory'),
  g_people: L('মানুষ ও স্টাফ', 'People & staff', 'Staff ও মানুষ'), g_reports: L('রিপোর্ট', 'Reports', 'Report'), g_settings: L('সেটিংস', 'Settings', 'Settings'),
  pending: L('অনুমোদনের অপেক্ষায়', 'Awaiting approval', 'Approval-এর অপেক্ষায়'),
  hi: L('স্বাগতম', 'Welcome', 'স্বাগতম'), biz: L('ব্যবসা', 'Business', 'Business'), acc: L('হিসাব', 'Accounting', 'Accounting'),
  p_day: L('আজ', 'Today', 'Today'), p_week: L('সপ্তাহ', 'Week', 'Week'), p_month: L('মাস', 'Month', 'Month'), p_year: L('বছর', 'Year', 'Year'),
  attn: L('সিদ্ধান্ত দরকার', 'Needs your decision', 'Decision দরকার'), attn_ok: L('এখন কোনো সিদ্ধান্ত বাকি নেই ✓', 'Nothing waiting for a decision ✓', 'এখন কোনো Decision বাকি নেই ✓'),
  fav: L('প্রিয় ও বেশি ব্যবহৃত', 'Favourites & most used', 'Favourite ও Most-used'), fav_empty: L('☆ চেপে যেকোনো মেনু বা ফর্ম এখানে রাখুন। বেশি ব্যবহার করলে নিজে থেকেই উঠে আসবে।', 'Tap ☆ to keep any menu item or form here. The ones you use most also show up by themselves.', '☆ চেপে যেকোনো Menu বা Form এখানে রাখুন। Most-used নিজে থেকেই উঠে আসবে।'),
  add: L('যোগ করুন', 'Add', 'Add'), pick: L('প্রিয়তে যোগ করুন', 'Add to favourites', 'Favourite-এ যোগ করুন'), done: L('হয়েছে', 'Done', 'Done'),
  tiles_biz: L('ব্যবসার কাজ', 'Business work', 'Business-এর কাজ'), tiles_acc: L('হিসাবের কাজ', 'Accounting work', 'Accounting-এর কাজ'),
  forms: L('আপনার সব ফর্ম', 'All your forms', 'আপনার সব Form'), detail: L('আজকের বিস্তারিত সমস্যা ও সংখ্যা', 'Details: problems and numbers', 'Details: Problem ও সংখ্যা'),
  sales: L('বিক্রি', 'Sales', 'Sales'), cnt: L('টি সেল', 'sales', 'sales'), disc: L('ডিসকাউন্ট', 'Discount', 'Discount'), due_p: L('বাকিতে বিক্রি', 'Sold on credit', 'Due-তে বিক্রি'),
  perloc: L('শাখা অনুযায়ী', 'By location', 'Location অনুযায়ী'), total: L('মোট', 'Total', 'Total'),
  cash: L('নগদ গ্রহণ', 'Cash received', 'Cash গ্রহণ'), digital: L('মোবাইল ও কার্ড', 'Mobile & card', 'Mobile ও Card'), due_all: L('গ্রাহকের কাছে মোট বাকি', 'Total owed by customers', 'Customer-এর কাছে মোট Due'),
  salary: L('বেতন রিপোর্ট', 'Salary report', 'Salary report'),
  payables: L('সরবরাহকারীর পাওনা', 'Supplier payables', 'Supplier-এর Payable'), pl: L('লাভ-ক্ষতি', 'Profit & loss', 'Profit-Loss'), daybook: L('দিনের খাতা', 'Day book', 'Day book'), stockbal: L('স্টক ব্যালেন্স', 'Stock balance', 'Stock Balance'),
  today_sheet: L('শোরুমের দৈনিক শিট', 'Showroom daily sheet', 'Showroom-এর Daily Sheet'),
  period_note: L('বছর = অর্থবছরের শুরু থেকে (সেটিংসের নিয়ম; না থাকলে ১ জানুয়ারি)', 'Year = from the fiscal-year start (a setting; 1 January when none is set)', 'Year = fiscal year শুরু থেকে (setting; না থাকলে ১ জানুয়ারি)'),
  sheets: L('আজ যে শিটগুলো পূরণ করতে হবে', "Today's sheets to fill", 'আজ যে Sheet পূরণ করতে হবে'), sheets_none: L('আপনার জন্য কোনো শিট নেই', 'No sheets for you here', 'আপনার জন্য কোনো Sheet নেই'),
  st_done: L('জমা হয়েছে', 'Done', 'Done'), st_pending: L('বাকি', 'Pending', 'Pending'), st_draft: L('খসড়া', 'Draft', 'Draft'), st_rej: L('ফেরত — ঠিক করুন', 'Sent back — fix', 'ফেরত — ঠিক করুন'), st_paper: L('কাগজে', 'On paper', 'কাগজে'),
  sheets_of: L('জমা', 'done', 'done'), sheets_hint: L('মালিক চাইলে সেটিংসে "হোমে দৈনিক শিট" নিয়মে শুধু দৈনিক শিটগুলো বেছে দিতে পারেন', 'The owner can narrow this to the daily sheets with the rule "Daily sheets on home"', 'Owner চাইলে rule-এ শুধু দৈনিক Sheet বেছে দিতে পারেন'),
  locsw: L('লোকেশন', 'Location', 'Location'), all_loc: L('সব লোকেশন', 'All locations', 'সব Location'),
  s_screens: L('পাতা ও ফর্ম', 'Screens & forms', 'Page ও Form'), s_items: L('আইটেম', 'Items', 'Item'), s_cust: L('গ্রাহক', 'Customers', 'Customer'), s_more: L('আইটেম ও গ্রাহক খোঁজা হচ্ছে…', 'Searching items and customers…', 'Item ও Customer খোঁজা হচ্ছে…'),
  reset: L('প্রিয় ও ব্যবহারের হিসাব মুছুন', 'Clear my favourites & usage', 'Favourite ও Usage মুছুন'), logout: L('লগআউট', 'Log out', 'Logout'), roles: L('ভূমিকা', 'Roles', 'Role'),
  modules: L('সব মডিউল', 'All modules', 'সব Module'),
  em: L('জরুরি অনুরোধ', 'Emergency requests', 'জরুরি Request'), addprod: L('নতুন পণ্য যোগ', 'Add product', 'নতুন Product যোগ'), unitconv: L('একক রূপান্তর', 'Unit conversions', 'Unit conversion'),
  ctl: L('কন্ট্রোল সেন্টার', 'Control Center', 'Control Center'), ctl_d: L('লোকেশন, সীমা, তালিকা ও সেটিংস এক জায়গায়', 'Places, limits, lists and settings in one place', 'Location, limit, list ও settings এক জায়গায়'), locs: L('লোকেশন', 'Locations', 'Location'),
  n_loc: L('নতুন লোকেশনের সেটআপ বাকি', 'New places still being set up', 'নতুন Location-এর setup বাকি'), n_sd: L('সেটিংস শিটের খসড়া অনুমোদনের অপেক্ষায়', 'Settings sheet drafts waiting', 'Settings sheet draft approval-এর অপেক্ষায়'), n_wst: L('নষ্টের অনুমোদন বাকি', 'Wastage approvals waiting', 'Wastage approval বাকি'),
  set2: L('সেটিংস (সব অপশন)', 'Settings (all options)', 'Settings (সব Option)'), inv: L('ইনভয়েস ও প্রিন্ট', 'Invoice & print', 'Invoice ও Print'),
};
const T = (k) => lab(X[k]);

// ---------- icons ----------
const sv = (d, extra = '') => `<svg viewBox="0 0 32 32" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
const IC = {
  menu: sv('<path d="M5 9h22M5 16h22M5 23h22"/>'), home: sv('<path d="M4 15L16 5l12 10M7 13v14h18V13"/><path d="M13 27v-8h6v8"/>'),
  me: sv('<circle cx="16" cy="11" r="5.5"/><path d="M5 28c1-6 5.5-9 11-9s10 3 11 9"/>'), pos: sv('<rect x="6" y="3" width="20" height="26" rx="3"/><path d="M10 9h12M10 15h3M16 15h3M10 21h3M16 21h3"/>'),
  doc: sv('<path d="M8 3h11l6 6v20H8z"/><path d="M19 3v6h6M12 15h9M12 20h9M12 25h5"/>'), lock: sv('<rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/>'),
  star: sv('<path d="M16 3.5l3.9 8 8.8 1.2-6.4 6.2 1.6 8.8L16 23.4 8.1 27.7l1.6-8.8L3.3 12.7l8.8-1.2z"/>'),
  starF: sv('<path d="M16 3.5l3.9 8 8.8 1.2-6.4 6.2 1.6 8.8L16 23.4 8.1 27.7l1.6-8.8L3.3 12.7l8.8-1.2z" fill="currentColor"/>'),
  x: sv('<path d="M8 8l16 16M24 8L8 24"/>'), cv: sv('<path d="M12 6l10 10-10 10"/>'), plus: sv('<path d="M16 6v20M6 16h20"/>'),
};
const ico = (k) => (A.ICON && A.ICON[k]) || IC[k] || IC.doc;

// ---------- permission helpers ----------
const ctx = () => S.ctx, perms = () => (S.ctx && S.ctx.perms) || {};
const isOwner = () => !!(S.ctx && S.ctx.is_owner);
const P = (c, k) => isOwner() || !!(perms()[c] && perms()[c][k]);
const anyApprove = () => isOwner() || Object.values(perms()).some((p) => p.approve);
const canPos = () => isOwner() || !!(perms().POS && (perms().POS.enter || perms().POS.view));
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';
const npMode = () => { let m = 'lock'; try { m = B.rule('ui_noperm_mode', 'lock'); } catch (e) { /* rules not loaded yet */ } return m === 'hide' ? 'hide' : 'lock'; };

// ---------- registry: routes + forms ----------
const ctlOk = () => isOwner() || GF.head_management === true || GF.location_manage === true || GF.settings_approve === true || GF.list_manage === true;
let GF = {};   // grants that open the day book / salary report for non-owners (server still decides on every call)
const GROUPS = ['dash', 'acc', 'item', 'cust', 'sale', 'purch', 'supp', 'ops', 'people', 'reports', 'settings'];
const locOk = () => isOwner() || (S.ctx.roles || []).includes('management') || (S.ctx.locations || []).length > 0;   // stock / purchase pages: the server decides the rest
const AREA_G = { cash: 'acc', stock: 'ops', factory: 'ops', assets: 'ops', purchase: 'purch', sales: 'sale', showroom: 'sale', staff: 'people', owner: 'reports' };
const ROUTES = [
  { k: 'home', g: 'dash', lb: () => t('home'), ic: 'home', ok: () => true },
  { k: 'exceptions', g: 'dash', lb: () => t('exceptions'), ok: () => anyApprove(), cnt: 'ex', tone: 'bad' },
  { k: 'pending', g: 'dash', lb: () => T('pending'), ic: 'doc', ok: () => anyApprove() },
  { k: 'releases', g: 'dash', lb: () => t('releases'), ok: () => isOwner(), cnt: 'rel', tone: 'warn' },
  { k: 'emergency', g: 'dash', lb: () => t('emergency'), ok: () => isOwner(), cnt: 'em', tone: 'warn' },
  { k: 'items', g: 'item', lb: () => t('items'), ok: () => P('ITEMS', 'view') },
  { k: 'items/new', g: 'item', lb: () => T('addprod'), ic: 'plus', ok: () => P('ITEMS', 'enter') },
  { k: 'itemreq', g: 'item', lb: () => t('item_req'), ok: () => P('ITEMS', 'enter') || P('ITEMS', 'approve'), cnt: 'itm', tone: 'info' },
  { k: 'lists', g: 'item', lb: () => t('lists'), ok: () => isOwner() || GF.list_manage === true, cnt: 'lq', tone: 'info' },
  { k: 'settings2/units', g: 'item', lb: () => T('unitconv'), ok: () => isOwner() },
  { k: 'itemimport', g: 'item', lb: () => lab(L('আইটেম মাস্টার ইমপোর্ট', 'Item master import', 'Item master import')), ic: 'doc', ok: () => isOwner() },
  { k: 'itemmap', g: 'item', lb: () => lab(L('পুরনো আইটেম মেলানো', 'Old items to master codes', 'পুরনো Item মেলানো')), ic: 'doc', ok: () => isOwner() || GF.item_create === true },
  { k: 'itemtypes', g: 'item', lb: () => lab(L('আইটেমের ধরন ও ডিফল্ট', 'Item types & defaults', 'Item type ও Default')), ic: 'doc', ok: () => isOwner() },
  { k: 'assets', g: 'ops', lb: () => lab(L('সম্পদ-খাতা', 'Asset register', 'Asset register')), ic: 'doc', ok: () => locOk() },
  { k: 'dues', g: 'cust', lb: () => t('dues'), ok: () => canPos() },
  { k: 'stock', g: 'ops', lb: () => lab(L('স্টক', 'Stock', 'Stock')), ic: 'items', ok: () => locOk() },
  { k: 'recipes', g: 'ops', lb: () => lab(L('রেসিপি ও উৎপাদন', 'Recipes & production', 'Recipe ও Production')), ic: 'doc', ok: () => locOk() },
  { k: 'purchase', g: 'purch', lb: () => lab(L('ক্রয় বিল', 'Purchase bills', 'Purchase Bill')), ic: 'doc', ok: () => locOk() },
  { k: 'purchase/new', g: 'purch', lb: () => lab(L('নতুন ক্রয় বিল', 'New purchase bill', 'নতুন Purchase bill')), ic: 'plus', ok: () => locOk() },
  { k: 'purchase/return', g: 'purch', lb: () => lab(L('ক্রয় ফেরত', 'Purchase return', 'Purchase return')), ic: 'doc', ok: () => locOk() },
  { k: 'daybook', g: 'acc', lb: () => T('daybook'), ic: 'doc', ok: () => isOwner() || GF.view_daybook === true },
  { k: 'salary', g: 'people', lb: () => T('salary'), ic: 'doc', ok: () => isOwner() || GF.salary_view === true },
  { k: 'salereturn', g: 'sale', lb: () => lab(L('বিক্রি ফেরত', 'Sale returns', 'Sale return')), ic: 'doc', ok: () => canPos() },
  { k: 'payables', g: 'supp', lb: () => T('payables'), ic: 'dues', ok: () => locOk() },
  { k: 'pos', g: 'sale', lb: () => t('pos'), ok: () => canPos() },
  { k: 'reports', g: 'reports', lb: () => T('g_reports'), ic: 'doc', ok: () => true },
  { k: 'biz', g: 'reports', lb: () => t('biz'), ok: () => isOwner() || P('POS', 'approve') },
  { k: 'numaudit', g: 'reports', lb: () => t('numaudit'), ok: () => anyApprove() },
  { k: 'logs', g: 'reports', lb: () => t('logs'), ok: () => isOwner() },
  { k: 'staff', g: 'people', lb: () => t('staff'), ok: () => isOwner(), cnt: 'stf', tone: 'info' },
  { k: 'rulehub', g: 'settings', lb: () => t('rulehub'), ok: () => isOwner() },
  { k: 'rules', g: 'settings', lb: () => t('rules'), ok: () => isOwner() },
  { k: 'matrix', g: 'settings', lb: () => t('matrix'), ok: () => isOwner() },
  { k: 'settings', g: 'settings', lb: () => t('settings'), ok: () => isOwner() },
  { k: 'settings2', g: 'settings', lb: () => T('set2'), ok: () => isOwner() },
  { k: 'invoice', g: 'settings', lb: () => T('inv'), ok: () => isOwner() },
  { k: 'locset', g: 'settings', lb: () => t('locset'), ok: () => isOwner() || GF.settings_approve === true || GF.head_management === true },
  { k: 'control', g: 'settings', lb: () => T('ctl'), ic: 'control', ok: () => ctlOk(), cnt: 'ctl', tone: 'info' },
  { k: 'rollout', g: 'settings', lb: () => lab(L('কাগজ / পাশাপাশি / অ্যাপ', 'Paper / Parallel / App', 'Paper / Parallel / App')), ic: 'control', ok: () => isOwner() || GF.rollout_manage === true },
  { k: 'changes', g: 'ops', lb: () => lab(L('বদলের অনুরোধ', 'Change requests', 'Change request')), ic: 'doc', ok: () => isOwner() || GF.change_approve === true, cnt: 'chg', tone: 'info' },
  { k: 'outbox', g: 'ops', lb: () => lab(L('ফোনে জমা (পাঠানো হয়নি)', 'Not sent yet', 'Phone-এ জমা (Not sent yet)')), ic: 'doc', ok: () => true, cnt: 'obx', tone: 'warn' },
  { k: 'locations', g: 'settings', lb: () => T('locs'), ic: 'locations', ok: () => isOwner() || GF.location_manage === true || GF.head_management === true, cnt: 'loc', tone: 'info' },
  { k: 'backup', g: 'settings', lb: () => t('backup'), ok: () => isOwner() },
];
let FORMS = null;   // rows of the forms table, fetched once
function entries() {
  const out = ROUTES.map((r) => ({ key: 'r:' + r.k, route: r.k, g: r.g, label: r.lb(), icon: r.ic || r.k, ok: r.ok(), live: true, cnt: r.cnt, tone: r.tone, kind: 'r' }));
  (FORMS || []).filter((f) => f.area !== 'master' && f.code !== 'POS' && AREA_G[f.area]).forEach((f) => {
    const live = f.code === '0-1' ? isOwner() : !!(B.forms && B.forms[f.code]);
    out.push({ key: 'f:' + f.code, route: 'form/' + f.code, g: AREA_G[f.area], label: f.code + ' · ' + nm(f), icon: 'doc', ok: P(f.code, 'view'), live, kind: 'f', code: f.code });
  });
  return out;
}
const byKey = (k) => entries().find((e) => e.key === k);
function keyOfHash() {
  const p = location.hash.replace(/^#\/?/, '').split('/');
  const page = p[0] || 'home';
  if (page === 'form' && p[1]) return 'f:' + p[1];
  if (page === 'entry' && p[1] === 'new' && p[2]) return 'f:' + p[2];
  if (page === 'report') return 'r:reports';
  return 'r:' + page;
}

// ---------- per-user favourites + usage counter (localStorage only) ----------
const jget = (k, d) => { try { const v = JSON.parse(store.get(k) || 'null'); return v == null ? d : v; } catch (e) { return d; } };
const pins = () => jget('bos_pins_' + uid(), []);
const usage = () => jget('bos_use_' + uid(), {});
const setPins = (a) => store.set('bos_pins_' + uid(), JSON.stringify(a));
const isPinned = (k) => pins().includes(k);
function bump(k) { if (!k || k === 'r:home' || !S.ctx) return; const u = usage(); u[k] = (u[k] || 0) + 1; store.set('bos_use_' + uid(), JSON.stringify(u)); pushUse(k); }
let lastCounted = null;
function countRoute() {
  const h = location.hash;
  if (h === lastCounted) return; lastCounted = h;
  const k = keyOfHash(); if (k && byKey(k)) bump(k);
}

// ---------- server sync: user_favourites / role_favourites. localStorage stays the offline fallback; changes made offline wait in a small queue ----------
const fkOf = (key) => (key.startsWith('f:') ? { kind: 'form', key: key.slice(2) } : { kind: 'route', key: key.replace(/^r:/, '') });
const keyOfFav = (r) => (r.kind === 'form' ? 'f:' : 'r:') + r.key;
const favQ = () => jget('bos_favq_' + uid(), []);
const setFavQ = (a) => store.set('bos_favq_' + uid(), JSON.stringify(a));
const okRes = (p) => Promise.resolve(p).then((r) => (r && r.error ? Promise.reject(r.error) : r));
let RF = [], favSynced = null;
function pushPin(key, pinned) {
  if (!S.ctx) return; const k = fkOf(key);
  okRes(sb.rpc('set_pin', { p_kind: k.kind, p_key: k.key, p_pinned: pinned })).catch(() => { setFavQ([...favQ().filter((x) => x.key !== key), { key, pinned }]); });
}
function pushUse(key) { if (!S.ctx || navigator.onLine === false) return; const k = fkOf(key); okRes(sb.rpc('touch_favourite', { p_kind: k.kind, p_key: k.key })).catch(() => {}); }
async function syncFavs() {
  if (!S.ctx || favSynced === uid()) return; const me = uid(); favSynced = me;
  try {
    for (const q of favQ()) { const k = fkOf(q.key); await okRes(sb.rpc('set_pin', { p_kind: k.kind, p_key: k.key, p_pinned: q.pinned })); }
    setFavQ([]);
    if (store.get('bos_favmig_' + me) !== '1') { for (const key of pins()) { const k = fkOf(key); await okRes(sb.rpc('set_pin', { p_kind: k.kind, p_key: k.key, p_pinned: true })); } store.set('bos_favmig_' + me, '1'); }   // pins made before the sync existed go up once
    const [r, rf] = await Promise.all([sb.from('user_favourites').select('kind,key,pinned,uses'), sb.from('role_favourites').select('role_code,kind,key,sort')]);
    if (rf && !rf.error) RF = rf.data || [];
    if (r && !r.error) {
      const rows = r.data || [], sp = rows.filter((x) => x.pinned).map(keyOfFav), loc = pins(), u = usage();
      setPins([...loc.filter((k) => sp.includes(k)), ...sp.filter((k) => !loc.includes(k))]);
      rows.forEach((x) => { const k = keyOfFav(x); u[k] = Math.max(u[k] || 0, Number(x.uses) || 0); });
      store.set('bos_use_' + me, JSON.stringify(u));
    }
    afterPin();
  } catch (e) { favSynced = null; /* offline or tables missing: local copy keeps working, try again later */ }
}
const roleDefaults = () => { const mine = new Set((S.ctx && S.ctx.roles) || []); return [...new Set(RF.filter((x) => mine.has(x.role_code)).sort((a, b) => a.sort - b.sort).map(keyOfFav))]; };
const effPins = () => { const p = pins(); return p.length ? p : roleDefaults(); };

// ---------- attention counts ----------
let CNT = null, cntAt = 0;
async function counts(force) {
  if (!S.ctx) return {};
  if (CNT && !force && Date.now() - cntAt < 45000) return CNT;
  const q = (x) => x.then((r) => (r && !r.error ? r.count || 0 : 0), () => 0);
  const own = isOwner(), ap = anyApprove(), canDecide = own || P('ITEMS', 'approve');
  const head = (tb, st) => q(sb.from(tb).select('id', { count: 'exact', head: true }).eq('status', st));
  const [ex, rel, em, stf, itm] = await Promise.all([ap ? head('exceptions', 'open') : 0, own ? head('release_requests', 'pending') : 0, own ? head('emergency_requests', 'pending') : 0,
    own ? head('profiles', 'pending') : 0, canDecide ? head('item_changes', 'pending') : 0]);
  let lq = 0;      // list requests + Other entries waiting (owner and list managers; the server returns 0 for everybody else)
  if (own) { try { const r = await sb.rpc('list_queue_counts'); if (r && !r.error && r.data) lq = (Number(r.data.requests) || 0) + (Number(r.data.other) || 0); } catch (e) { /* phase15 not installed */ } }
  let loc = 0, sd = 0, wst = 0;   // phase16 control_counts: places being set up, settings drafts, wastage approvals (the server returns only what the caller may decide)
  if (own || ctlOk()) { try { const r = await sb.rpc('control_counts'); if (r && !r.error && r.data) { loc = Number(r.data.location_setup) || 0; sd = Number(r.data.settings_drafts) || 0; wst = Number(r.data.wastage) || 0; if (!own) lq = Number(r.data.lists) || 0; } } catch (e) { /* phase16 not installed */ } }
  let chg = 0;      // phase17: change requests the caller may decide (0 for everybody else / when not installed)
  if (own || GF.change_approve) { try { const r = await sb.rpc('entry_change_counts'); if (r && !r.error && r.data) chg = Number(r.data.pending) || 0; } catch (e) { /* phase17 not installed */ } }
  const obx = (B.outbox && B.outbox.count) ? B.outbox.count() : 0;      // forms waiting on this phone (offline queue)
  CNT = { ex, rel, em, stf, itm, lq, loc, sd, wst, chg, obx, ctl: (own ? ex + rel + em + stf + itm + lq + wst : 0) + loc + sd + (own ? 0 : lq) }; cntAt = Date.now(); return CNT;
}
async function loadGrantFlags() {
  if (!S.ctx || isOwner()) return;
  const locs = (S.ctx.locations || []).length ? [null, ...S.ctx.locations] : [null];
  const codes = locOk() ? ['view_daybook', 'salary_view', 'item_create', 'head_management', 'location_manage', 'settings_approve', 'list_manage', 'rollout_manage', 'change_approve'] : ['head_management', 'location_manage', 'settings_approve', 'list_manage', 'rollout_manage', 'change_approve'];
  await Promise.all(codes.map(async (code) => {
    let ok = false;
    for (const l of locs) { try { const r = await sb.rpc('has_grant', { p_code: code, p_loc: l }); if (r && !r.error && r.data === true) { ok = true; break; } } catch (e) { /* not granted */ } }
    GF[code] = ok;
  }));
  try { if ($('#hv_tiles')) drawTiles(); if ($('#hv_ctl')) drawCtl(); if (drawerOpen) dr_body(); } catch (e) { /* screens not drawn yet */ }
}
let staticP = null;
function ensureStatic() {
  if (!staticP) staticP = (async () => {
    try { await B.loadStatic(); } catch (e) { /* rules fall back to defaults */ }
    if (!FORMS) { const r = await sb.from('forms').select('code,area,name_bn,name_mix,name_en,sort,enabled').order('sort'); FORMS = r && r.data ? r.data : []; }
    try { if (B.rule('ui_calm', true) === false) document.body.removeAttribute('data-ui'); } catch (e) { /* keep calm */ }
    syncFavs();
    await loadGrantFlags();
  })();
  return staticP;
}

// ---------- current location (drawer footer): one choice per person, followed by every screen that asks B.curLoc() ----------
// null = all the places this person may use (the owner / management see every place; others only their own). A person with exactly one place is fixed to it.
const wideLoc = () => isOwner() || (S.ctx.roles || []).includes('management');
function locChoices() { const all = ((B.ENV && B.ENV.locs) || []).filter((l) => l.is_active !== false && l.status !== 'closed'); return wideLoc() ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); }
function curLoc() {
  if (!S.ctx) return null;
  const ch = locChoices(); if (ch.length === 1) return ch[0].id;
  let v = null; try { v = store.get('bos_curloc_' + uid()); } catch (e) { v = null; }
  const id = v === null || v === '' || v === 'all' ? null : Number(v);
  return id !== null && ch.some((l) => l.id === id) ? id : null;
}
function setCurLoc(id) {
  try { store.set('bos_curloc_' + uid(), id === null || id === undefined ? 'all' : String(id)); } catch (e) { /* private window: the choice lasts until reload */ }
  if (id !== null && id !== undefined) { try { store.set('bos_pos_loc', String(id)); } catch (e) { /* ignore */ } }   // the POS reads its own remembered place
  try { window.dispatchEvent(new CustomEvent('bos:loc', { detail: { id: id === undefined ? null : id } })); } catch (e) { /* old browser */ }
}
function drawLocBox() {
  const box = $('#nav_locbox'); if (!box) return;
  const ch = locChoices(); if (ch.length < 2) { box.innerHTML = ''; return; }
  const cur = curLoc();
  box.innerHTML = `<label for="nav_loc" style="font-size:.85rem;color:var(--muted)">${esc(T('locsw'))}</label>
    <select id="nav_loc" aria-label="${esc(T('locsw'))}" style="width:100%;min-height:44px"><option value="all" ${cur === null ? 'selected' : ''}>${esc(T('all_loc'))}</option>${ch.map((l) => `<option value="${l.id}" ${cur === l.id ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select>`;
}
document.addEventListener('change', (e) => {
  if (!e.target || e.target.id !== 'nav_loc') return;
  setCurLoc(e.target.value === 'all' ? null : Number(e.target.value));
  setDrawer(false);
  HS.data = null;
  if ((location.hash.replace(/^#\/?/, '') || 'home').split('/')[0] === 'home') loadStats(); else window.dispatchEvent(new HashChangeEvent('hashchange'));   // the open screen draws again with the new place
  if ($('#hv_sheets')) loadSheets();
});

// ---------- drawer search over items / customers (the menu itself is searched on the phone, instantly) ----------
const SR = { q: '', items: [], cust: [], busy: false, tm: null };
let ITEMS_ALL = null, ITEMS_AT = 0;
async function itemsAll() {
  if (ITEMS_ALL && Date.now() - ITEMS_AT < 300000) return ITEMS_ALL;
  const r = await window.BOS_ALL(sb.from('items').select('id,code,name_bn,name_en,name_mix,barcode,is_active').order('code'));
  ITEMS_ALL = r && !r.error ? r.data || [] : (ITEMS_ALL || []); ITEMS_AT = Date.now(); return ITEMS_ALL;
}
const normQ = (x) => String(x || '').toLowerCase().trim();
async function searchMore(qq) {
  const ql = normQ(qq);
  if (ql.length < 2) { SR.items = []; SR.cust = []; SR.busy = false; SR.q = ql; return; }
  SR.busy = true;
  const jobs = [];
  if (P('ITEMS', 'view') && window.BOS_ALL) jobs.push(itemsAll().then((a) => a.filter((it) => [it.code, it.name_bn, it.name_en, it.name_mix, it.barcode].some((v) => normQ(v).includes(ql))).slice(0, 8), () => []));
  else jobs.push(Promise.resolve([]));
  if (canPos()) {
    const safe = ql.replace(/[^\p{L}\p{N} ]/gu, ' ').trim();
    jobs.push(safe.length < 2 ? Promise.resolve([]) : (async () => { try { const r = await sb.from('customers').select('id,name,mobile').or(`name.ilike.%${safe}%,mobile.ilike.%${safe}%`).order('name').limit(6); return r && !r.error ? r.data || [] : []; } catch (e) { return []; } })());
  } else jobs.push(Promise.resolve([]));
  const [it, cu] = await Promise.all(jobs);
  if (normQ(q) !== ql) return;      // typed on meanwhile: this answer is stale
  SR.q = ql; SR.items = it; SR.cust = cu; SR.busy = false;
}
function queueSearch() {
  clearTimeout(SR.tm);
  const ql = normQ(q);
  if (ql.length < 2) { SR.items = []; SR.cust = []; SR.busy = false; SR.q = ''; return; }
  SR.busy = SR.q !== ql;
  SR.tm = setTimeout(() => { searchMore(q).then(() => { if (drawerOpen && normQ(q) === ql) dr_body(); }, () => { SR.busy = false; }); }, 250);
}

// ---------- drawer ----------
let drawerOpen = false, pendingRoute = null, openGroups = null, sig = '', q = '';
const el = {};
function mount() {
  if (el.drawer) return;
  const sc = document.createElement('div'); sc.className = 'scrim'; sc.id = 'navScrim'; sc.dataset.act = 'nav_close';
  const dr = document.createElement('aside'); dr.className = 'drawer'; dr.id = 'navDrawer'; dr.setAttribute('role', 'dialog'); dr.setAttribute('aria-modal', 'true');
  const bn = document.createElement('nav'); bn.className = 'bnav'; bn.id = 'bnav';
  document.body.append(sc, dr, bn); el.scrim = sc; el.drawer = dr; el.bnav = bn;
  if (!document.body.dataset.ui && store.get('bos_ui') !== 'off') document.body.dataset.ui = 'calm';
}
const groupOpen = () => { if (!openGroups) { openGroups = jget('bos_navg_' + uid(), null); if (!openGroups) openGroups = { dash: true }; } return openGroups; };
function renderDrawer() {
  if (!el.drawer || !S.ctx) return;
  dr_shell();
  dr_body();
}
function dr_shell() {
  const s = S.lang + '|' + uid(); if (s === sig && el.drawer.firstChild) return; sig = s;
  el.drawer.setAttribute('aria-label', T('menu'));
  el.drawer.innerHTML = `<div class="dr-head"><img src="mark.svg" alt=""><div class="nm"><b>${esc(BRAND.bn)}</b><i>${esc(BRAND.en)}</i></div>
      <button class="hbtn" style="min-height:48px;min-width:48px;border:0;background:transparent;color:var(--ink)" data-act="nav_close" aria-label="${esc(T('close'))}">${IC.x.replace('<svg', '<svg width="22" height="22"')}</button></div>
    <div class="dr-search"><input id="nav_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}" value="${esc(q)}"></div>
    <div class="dr-body" id="nav_body"></div>
    <div class="dr-foot"><div id="nav_locbox"></div><div class="me-lang">${A.langBar()}</div><div class="row"><span class="on-s"><span class="dot ${navigator.onLine === false ? 'bad' : 'ok'}" id="nav_net"></span><span id="nav_nett">${esc(navigator.onLine === false ? T('offline') : T('online'))}</span></span>
      <button class="lo" data-act="logout">${esc(T('logout'))}</button></div></div>`;
}
function dr_body() {
  const body = $('#nav_body'); if (!body) return;
  drawLocBox();
  const all = entries(), mode = npMode(), cur = keyOfHash(), cn = CNT || {}, og = groupOpen(), ql = q.trim().toLowerCase();
  const row = (e) => {
    const on = e.key === cur, pin = isPinned(e.key), c = e.cnt && cn[e.cnt];
    return `<div class="dr-i ${on ? 'on' : ''}"><button class="rb dr-it" data-act="nav_go" data-v="${esc(e.route)}" ${on ? 'aria-current="page"' : ''}>${ico(e.icon)}<span class="lb">${esc(e.label)}</span>${c ? `<span class="ct">${c}</span><span class="dot ${e.tone || 'warn'}"></span>` : ''}</button>
      <button class="st" data-act="nav_pin" data-v="${esc(e.key)}" aria-pressed="${pin}" aria-label="${esc(pin ? T('unpin') : T('pin'))}">${pin ? IC.starF : IC.star}</button></div>`;
  };
  const lockRow = (label) => `<div class="dr-i lock">${IC.lock}<span>${esc(label)}</span></div>`;
  if (ql) {
    const hit = all.filter((e) => e.ok && e.live && (e.label.toLowerCase().includes(ql) || e.route.toLowerCase().includes(ql)));
    const stale = SR.q !== ql;
    const itH = stale ? [] : SR.items.map((it) => `<div class="dr-i"><button class="rb dr-it" data-act="nav_go" data-v="${esc(P('ITEMS', 'enter') ? 'items/edit/' + it.id : 'items')}">${ico('items')}<span class="lb">${esc(it.code)} · ${esc(nm(it))}${it.is_active === false ? ' ·' : ''}</span></button></div>`);
    const cuH = stale ? [] : SR.cust.map((c) => `<div class="dr-i"><button class="rb dr-it" data-act="nav_go" data-v="dues">${ico('dues')}<span class="lb">${esc(c.name || '')}${c.mobile ? ' · ' + esc(c.mobile) : ''}</span></button></div>`);
    const sec = (title, arr) => (arr.length ? `<div class="hsec">${esc(title)}<small>${arr.length}</small></div>${arr.join('')}` : '');
    const loc = hit.map((e) => row({ ...e, label: e.label }));
    body.innerHTML = (loc.length || itH.length || cuH.length ? sec(T('s_screens'), loc) + sec(T('s_items'), itH) + sec(T('s_cust'), cuH) : '')
      + (SR.busy && ql.length >= 2 ? `<p class="muted center pad">${esc(T('s_more'))}</p>` : '')
      + (!loc.length && !itH.length && !cuH.length && !SR.busy ? `<p class="muted center pad">${esc(T('nores'))}</p>` : '');
    return;
  }
  body.innerHTML = GROUPS.map((g) => {
    const list = all.filter((e) => e.g === g && e.live);
    const okL = list.filter((e) => e.ok), bad = list.filter((e) => !e.ok);
    if (!okL.length && !(mode === 'lock' && bad.length)) return '';
    const open = !!og[g] || okL.some((e) => e.key === cur), attn = okL.some((e) => e.cnt && cn[e.cnt]);
    // locked forms collapse to one summary line; locked routes are listed one by one
    const locks = mode === 'lock' ? [...bad.filter((e) => e.kind === 'r').map((e) => lockRow(e.label + ' · ' + T('noperm'))), ...(bad.some((e) => e.kind === 'f') ? [lockRow(T('noperm') + ' (' + bad.filter((e) => e.kind === 'f').length + ')')] : [])] : [];
    return `<div class="dr-grp"><button class="rb dr-g" data-act="nav_grp" data-v="${g}" aria-expanded="${open}"><span class="gl">${esc(T('g_' + g))}${attn ? '<span class="dot warn"></span>' : ''}${!okL.length ? IC.lock.replace('<svg', '<svg width="16" height="16"') : ''}</span>${IC.cv.replace('<svg', '<svg class="cv"')}</button>
      <div class="dr-list" ${open ? '' : 'hidden'}>${okL.map(row).join('')}${locks.join('')}</div></div>`;
  }).join('');
}
function setDrawer(on) {
  mount(); drawerOpen = on;
  el.scrim.classList.toggle('on', on); el.drawer.classList.toggle('on', on);
  syncBnav();
}
async function openDrawer() {
  if (drawerOpen || !S.ctx) return;
  mount(); await ensureStatic(); q = ''; sig = ''; renderDrawer();
  try { history.pushState({ bosNav: 1 }, '', location.href); } catch (e) { /* ignore */ }
  setDrawer(true);
  const cb = $('.dr-head button', el.drawer); if (cb) cb.focus();
  counts().then((c) => { if (drawerOpen) dr_body(); return c; }, () => {});
}
function closeDrawer() {
  if (!drawerOpen) return;
  setDrawer(false);
  try { if (history.state && history.state.bosNav) history.back(); } catch (e) { /* ignore */ }
}
window.addEventListener('popstate', () => {
  if (drawerOpen) setDrawer(false);                 // hardware Back: close the drawer first
  if (pendingRoute) { const r = pendingRoute; pendingRoute = null; location.hash = '#/' + r; }
});
window.addEventListener('hashchange', () => { countRoute(); if (drawerOpen) setDrawer(false); syncBnav(); updatePinBtn(); });
document.addEventListener('keydown', (e) => {
  if (!drawerOpen) return;
  if (e.key === 'Escape') { closeDrawer(); return; }
  if (e.key === 'Tab') {   // keep focus inside the drawer
    const f = [...el.drawer.querySelectorAll('button:not([disabled]),input')].filter((x) => x.offsetParent !== null || x === document.activeElement);
    if (!f.length) return; const a = f[0], z = f[f.length - 1];
    if (e.shiftKey && document.activeElement === a) { e.preventDefault(); z.focus(); } else if (!e.shiftKey && document.activeElement === z) { e.preventDefault(); a.focus(); }
  }
});
document.addEventListener('input', (e) => { if (e.target.id === 'nav_q') { q = e.target.value; queueSearch(); dr_body(); } if (e.target.id === 'pk_q') drawPicker(e.target.value); });
window.addEventListener('online', netDot); window.addEventListener('offline', netDot);
function netDot() { const d = $('#nav_net'), tx = $('#nav_nett'); if (!d) return; const on = navigator.onLine !== false; d.className = 'dot ' + (on ? 'ok' : 'bad'); tx.textContent = on ? T('online') : T('offline'); }

// ---------- bottom nav ----------
function hideBnav() {
  const page = (location.hash.replace(/^#\/?/, '') || 'home').split('/')[0];
  return page === 'pos' || page === 'entry';
}
function syncBnav() {
  if (!el.bnav) return;
  const live = !!(S.ctx && S.ctx.profile && S.ctx.profile.status === 'active');
  const show = live && !hideBnav();
  document.body.classList.toggle('has-bnav', show);
  if (!show) return;
  const page = (location.hash.replace(/^#\/?/, '') || 'home').split('/')[0], pos = canPos(), mode = npMode();
  const cur = drawerOpen ? 'menu' : page === 'home' ? 'home' : '';
  const b = (act, ic, lb, k, extra = '') => `<button data-act="${act}" ${cur === k ? 'aria-current="page"' : ''} ${extra}>${ic}<span>${esc(lb)}</span></button>`;
  const posBtn = pos ? b('go', ico('pos'), t('pos'), 'pos', 'data-v="pos"') : mode === 'lock' ? `<button disabled aria-label="${esc(t('pos') + ' · ' + T('noperm'))}">${IC.lock}<span>${esc(t('pos'))}</span></button>` : '';
  el.bnav.setAttribute('aria-label', T('menu'));
  el.bnav.innerHTML = b('go', IC.home, t('home'), 'home', 'data-v="home"') + b('nav_open', IC.menu, T('menu'), 'menu') + posBtn + b('nav_me', IC.me, T('me'), 'me');
}

// ---------- header bits (called from shell) ----------
function menuBtn() { return `<button class="hbtn" data-act="nav_open" aria-label="${esc(T('menu'))}" aria-haspopup="dialog">${IC.menu}</button>`; }
function headExtra() {
  const k = keyOfHash(), e = k !== 'r:home' ? byKey(k) : null;
  if (!e || !e.ok) return '';
  const pin = isPinned(k);
  return `<button class="hbtn pin" id="hd_pin" data-act="nav_pin" data-v="${esc(k)}" aria-pressed="${pin}" aria-label="${esc(pin ? T('unpin') : T('pin'))}">${pin ? IC.starF : IC.star}</button>`;
}
function updatePinBtn() {
  const b = $('#hd_pin'); if (!b) return; const pin = isPinned(b.dataset.v);
  b.setAttribute('aria-pressed', pin); b.setAttribute('aria-label', pin ? T('unpin') : T('pin')); b.innerHTML = pin ? IC.starF : IC.star;
}
function sync(live) {
  mount();
  if (!live) { setDrawer(false); document.body.classList.remove('has-bnav'); return; }
  countRoute();
  if (!FORMS) ensureStatic().then(() => { renderDrawer(); }, () => {});
  if (drawerOpen) { sig = ''; renderDrawer(); }
  else sig = '';
  syncBnav();
}

// ---------- pin / unpin ----------
function togglePin(k) {
  const p = pins(), i = p.indexOf(k);
  if (i >= 0) p.splice(i, 1); else p.push(k);
  setPins(p); afterPin(); pushPin(k, i < 0);
}
function afterPin() {
  updatePinBtn(); if ($('#nav_body')) dr_body();
  if ($('#hv_fav')) drawFav(); if ($('#pk_list')) drawPicker(($('#pk_q') || {}).value || '');
}
function pickerSheet() {
  openSheet(`<h2>${esc(T('pick'))}</h2><input id="pk_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}"><div id="pk_list" style="margin:8px 0"></div>
    <button class="full" data-act="closesheet">${esc(T('done'))}</button>`);
  drawPicker('');
}
function drawPicker(v) {
  const ql = (v || '').trim().toLowerCase(), box = $('#pk_list'); if (!box) return;
  const list = entries().filter((e) => e.ok && e.live && e.key !== 'r:home' && (!ql || e.label.toLowerCase().includes(ql)));
  box.innerHTML = list.map((e) => { const pin = isPinned(e.key); return `<div class="pk-row"><span class="lb">${esc(e.label)}</span>
    <button class="st" data-act="nav_pin" data-v="${esc(e.key)}" aria-pressed="${pin}" aria-label="${esc(pin ? T('unpin') : T('pin'))}">${pin ? IC.starF : IC.star}</button></div>`; }).join('') || `<p class="muted center">${esc(T('nores'))}</p>`;
}

// ---------- Me sheet ----------
function meSheet() {
  const p = S.ctx.profile;
  openSheet(`<h2>${esc(p.full_name || p.staff_id)} <span class="muted">· ${esc(p.staff_id)}</span></h2>
    <div class="me-lang" style="margin:10px 0">${A.langBar()}</div>
    <div class="stack"><button class="full" data-act="nav_reset">${esc(T('reset'))}</button>
    <button class="full" data-act="logout">${esc(T('logout'))}</button><button class="full" data-act="closesheet">${esc(T('done'))}</button></div>`);
}

// ---------- Home v2 ----------
const HS = { mode: null, period: null, data: null, dataFrom: null };
const dhaka = (d = new Date()) => d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
// first day of the fiscal year that contains iso: the same rule as the server (fiscal_year_start_month / _day; empty = 1 January)
function fyStart(iso) {
  const nn = (k, lo, hi) => { const v = Number(B.rule(k, null)); return B.rule(k, null) !== null && Number.isInteger(v) && v >= lo && v <= hi ? v : 1; };
  const mm = nn('fiscal_year_start_month', 1, 12), dd = nn('fiscal_year_start_day', 1, 31), y = Number(iso.slice(0, 4));
  const mk = (yy) => { const last = new Date(Date.UTC(yy, mm, 0)).getUTCDate(); return yy + '-' + String(mm).padStart(2, '0') + '-' + String(Math.min(dd, last)).padStart(2, '0'); };
  const s0 = mk(y); return iso < s0 ? mk(y - 1) : s0;
}
function periodFrom(p) { const td = dhaka(); return p === 'day' ? td : p === 'week' ? addDays(td, -6) : p === 'month' ? td.slice(0, 8) + '01' : fyStart(td); }
const money = (n) => '৳ ' + fmt(n);
const sumOf = (a, k = 'total') => a.reduce((s, x) => s + Number(x[k] || 0), 0);
const hdef = () => { if (!HS.mode) HS.mode = store.get('bos_hmode_' + uid()) === 'acc' ? 'acc' : 'biz'; if (!HS.period) HS.period = ['day', 'week', 'month', 'year'].includes(store.get('bos_hper_' + uid())) ? store.get('bos_hper_' + uid()) : 'day'; };

async function home() {
  const p = S.ctx.profile, own = isOwner(), ap = anyApprove();
  hdef(); mount();
  A.shell(t('app'), `<div class="hgreet"><b>${esc(T('hi'))}, ${esc(p.full_name || p.staff_id)}</b><span>${esc(p.staff_id)}</span></div>
    <div id="hv_main"><p class="muted">${esc(t('loading'))}</p></div>`);
  await ensureStatic();
  if (!$('#hv_main')) return;
  const cn = await counts(true).catch(() => ({}));
  if (!$('#hv_main')) return;
  const rows = [];
  if (own) rows.push(['em', cn.em, 'warn', t('emergency'), 'emergency']);
  if (ap) rows.push(['ex', cn.ex, 'bad', t('exceptions'), 'exceptions']);
  if (own) rows.push(['rel', cn.rel, 'warn', t('releases'), 'releases'], ['stf', cn.stf, 'info', t('staff'), 'staff']);
  if (P('ITEMS', 'approve')) rows.push(['itm', cn.itm, 'info', t('item_req'), 'itemreq']);
  if (own || GF.list_manage) rows.push(['lq', cn.lq, 'info', t('lists'), 'lists']);
  if (own || ctlOk()) rows.push(['loc', cn.loc, 'info', T('n_loc'), 'locations'], ['sd', cn.sd, 'info', T('n_sd'), 'locset']);
  if (own) rows.push(['wst', cn.wst, 'warn', T('n_wst'), 'stock']);
  if (own || GF.change_approve) rows.push(['chg', cn.chg, 'info', lab(L('বদলের অনুরোধ', 'Change requests', 'Change request')), 'changes']);
  rows.push(['obx', cn.obx, 'warn', lab(L('ফোনে জমা (পাঠানো হয়নি)', 'Not sent yet', 'Phone-এ জমা')), 'outbox']);
  const hot = rows.filter((r) => r[1]).slice(0, 8);
  const attn = ap || own || ctlOk() ? `<div class="hsec">${esc(T('attn'))}${hot.length ? `<small>${hot.reduce((s, r) => s + r[1], 0)}</small>` : ''}</div>
    <div class="card" style="padding:4px 12px">${hot.length ? hot.map((r) => `<button class="hrow mk ${r[2]}" data-act="go" data-v="${r[4]}"><span>${esc(r[3])}</span><span class="n">${r[1]}</span><span class="cv">›</span></button>`).join('')
      : `<div class="dash-ok">${esc(T('attn_ok'))}</div>`}</div>` : '';
  const posBtn = P('POS', 'enter') ? `<button class="primary hbig" data-act="go" data-v="pos">${esc(t('pos'))}</button>` : '';
  $('#hv_main').innerHTML = `${posBtn}${attn}
    <div class="seg" role="group" aria-label="${esc(T('biz') + ' / ' + T('acc'))}"><button data-act="hv_mode" data-v="biz" aria-pressed="${HS.mode === 'biz'}">${esc(T('biz'))}</button><button data-act="hv_mode" data-v="acc" aria-pressed="${HS.mode === 'acc'}">${esc(T('acc'))}</button></div>
    <div class="ptabs" role="tablist" id="hv_pt"></div><div id="hv_stats"></div>
    <div id="hv_sheets"></div>
    <div class="hsec">${esc(T('fav'))}</div><div id="hv_fav"></div>
    <div class="hsec" id="hv_th"></div><div class="qgrid" id="hv_tiles"></div>
    <div class="hsec">${esc(T('modules'))}</div><div class="grid" id="hv_mods"></div><div id="hv_ctl"></div>
    <details class="acc" id="hv_forms"><summary>${esc(T('forms'))}</summary><div class="accb" id="hv_formsb"></div></details>
    ${ap || canPos() ? `<details class="acc" id="hv_dt"><summary>${esc(T('detail'))}</summary><div class="accb"><div id="dash"></div></div></details>` : ''}`;
  drawPeriod(); drawTiles(); drawFav(); drawMods(); drawCtl(); drawForms();
  const dt = $('#hv_dt'); if (dt) dt.addEventListener('toggle', () => { if (dt.open && B.dash) B.dash.render().catch(() => {}); });
  loadStats(); loadSheets();
}
// ---------- staff home: today's sheets to fill (forms I may enter, at my place, in a mode that allows the app) ----------
async function loadSheets() {
  const box = $('#hv_sheets'); if (!box) return;
  if (isOwner() || !FORMS) { box.innerHTML = ''; return; }
  const only = String(B.rule('home_daily_forms', '') || '').split(/[\s,;]+/).filter(Boolean);
  let list = FORMS.filter((f) => f.enabled !== false && f.area !== 'master' && f.code !== 'POS' && f.code !== '0-1' && P(f.code, 'enter') && B.forms && B.forms[f.code]);
  if (only.length) list = list.filter((f) => only.includes(f.code));
  if (!list.length) { box.innerHTML = ''; return; }
  const cl = curLoc(), locs = locChoices().map((l) => l.id), ids = cl !== null ? [cl] : locs;
  if (!ids.length) { box.innerHTML = ''; return; }
  const td = dhaka(), key = td + '|' + ids.join(',');
  let ents = [], roll = [];
  try { const r = await sb.from('entries').select('form_code,location_id,status').eq('entry_date', td).in('location_id', ids).limit(1000); ents = r && !r.error ? r.data || [] : []; } catch (e) { ents = []; }
  try { const r = await sb.from('form_rollout').select('form_code,location_id,mode').in('location_id', ids); roll = r && !r.error ? r.data || [] : []; } catch (e) { roll = []; }   // table missing / not readable: every place counts as app
  if (!$('#hv_sheets') || key !== td + '|' + (cl !== null ? [cl] : locChoices().map((l) => l.id)).join(',')) return;
  const rank = { done: 0, draft: 1, rej: 2, pending: 3, paper: 4 };
  const rows = [];
  list.forEach((f) => ids.forEach((id) => {
    const mode = (roll.find((x) => x.form_code === f.code && x.location_id === id) || {}).mode || 'app';
    const mine = ents.filter((x) => x.form_code === f.code && x.location_id === id);
    let st = mode === 'paper' ? 'paper' : 'pending';
    if (mode !== 'paper') { if (mine.some((x) => x.status === 'submitted' || x.status === 'approved')) st = 'done'; else if (mine.some((x) => x.status === 'draft')) st = 'draft'; else if (mine.some((x) => x.status === 'rejected')) st = 'rej'; }
    rows.push({ f, id, st });
  }));
  rows.sort((a, b) => (a.st === 'done') - (b.st === 'done') || (a.st === 'paper') - (b.st === 'paper') || String(a.f.code).localeCompare(String(b.f.code), 'en', { numeric: true }));
  const done = rows.filter((r) => r.st === 'done').length, app = rows.filter((r) => r.st !== 'paper').length;
  const chipCls = { done: 'ok', pending: 'warn', draft: 'info', rej: 'bad', paper: '' };
  const lname = (id) => { const l = (B.ENV && B.ENV.locs || []).find((x) => x.id === id); return l ? nm(l) : ''; };
  box.innerHTML = `<div class="hsec">${esc(T('sheets'))}<small>${done}/${app} ${esc(T('sheets_of'))}</small></div>
    <div class="card" style="padding:4px 12px">${rows.map((r) => `<button class="hrow" data-act="openform" data-v="${esc(r.f.code)}" ${r.st === 'paper' ? 'style="opacity:.7"' : ''}><span><b>${esc(r.f.code)}</b> · ${esc(nm(r.f))}${ids.length > 1 ? ` <small class="muted">${esc(lname(r.id))}</small>` : ''}</span><span class="chip ${chipCls[r.st]}">${esc(T('st_' + r.st))}</span><span class="cv">›</span></button>`).join('')}
    ${only.length ? '' : `<p class="muted" style="font-size:.85rem;margin:6px 0">${esc(T('sheets_hint'))}</p>`}</div>`;
}
function drawPeriod() {
  const b = $('#hv_pt'); if (!b) return;
  b.innerHTML = [['day', 'p_day'], ['week', 'p_week'], ['month', 'p_month'], ['year', 'p_year']].map(([k, l]) => `<button role="tab" data-act="hv_period" data-v="${k}" aria-selected="${HS.period === k}">${esc(T(l))}</button>`).join('');
}
async function loadStats() {
  const box = $('#hv_stats'); if (!box) return;
  if (!canPos()) { box.innerHTML = ''; return; }
  const from = periodFrom(HS.period), key = from + '|' + uid();
  box.innerHTML = `<p class="muted">${esc(t('loading'))}</p>`;
  if (!HS.data || HS.dataFrom !== key) {
    const qq = (x) => x.then((r) => (r && !r.error ? r.data || [] : []), () => []);
    const [s, pay, dues] = await Promise.all([qq(sb.rpc('sales_summary', { p_from: from })), qq(sb.rpc('payments_summary', { p_from: from })), qq(sb.rpc('customer_dues'))]);
    HS.data = { s, pay, dues }; HS.dataFrom = key;
  }
  drawStats();
}
function drawStats() {
  const box = $('#hv_stats'); if (!box || !HS.data) return;
  const from = periodFrom(HS.period), td = dhaka();
  const rows = (HS.data.s || []).map((r) => ({ ...r, total: Number(r.total || 0), discount: Number(r.discount || 0), n: Number(r.n || 0), due: Number(r.due || 0) })).filter((r) => r.status === 'done' && r.sale_date >= from && r.sale_date <= td && (curLoc() === null || r.location_id === curLoc()));
  const stat = (k, v, s, cls = '', wide = '') => `<div class="stat ${cls ? "mk " + cls : ""} ${wide}"><div class="k">${esc(k)}</div><div class="v">${v}</div>${s ? `<div class="s">${esc(s)}</div>` : ''}</div>`;
  if (HS.mode === 'biz') {
    const locs = ((B.ENV && B.ENV.locs) || []).filter((l) => isOwner() || (S.ctx.roles || []).includes('management') || (S.ctx.locations || []).includes(l.id));
    let h = stat(T('sales'), money(sumOf(rows)), rows.reduce((s, r) => s + r.n, 0) + ' ' + T('cnt'), '', 'wide')
      + stat(T('disc'), money(sumOf(rows, 'discount')), '') + stat(T('due_p'), money(sumOf(rows, 'due')), '', sumOf(rows, 'due') > 0 ? 'warn' : '');
    if (locs.length > 1) h += `<div class="stat wide"><div class="k">${esc(T('perloc'))}</div>${locs.map((l) => `<div class="row" style="justify-content:space-between;min-height:36px"><span>${esc(nm(l))}</span><b>${money(sumOf(rows.filter((r) => r.location_id === l.id)))}</b></div>`).join('')}
      <div class="row" style="justify-content:space-between;border-top:1px solid var(--hair);min-height:36px"><b>${esc(T('total'))}</b><b>${money(sumOf(rows))}</b></div></div>`;
    box.innerHTML = `<div class="stats">${h}</div>`;
  } else {
    const pay = (m) => (HS.data.pay || []).filter((x) => x.mode === m && (!x.pay_date || x.pay_date >= from)).reduce((s, x) => s + Number(x.total || 0), 0);
    const dueAll = (HS.data.dues || []).reduce((s, c) => s + Number(c.balance || 0), 0);
    box.innerHTML = `<div class="stats">${stat(T('cash'), money(pay('cash')), '')}${stat(T('digital'), money(pay('mobile') + pay('card')), '')}
      ${stat(T('due_all'), `<span class="${dueAll > 0 ? 'amt-bad' : ''}">${money(dueAll)}</span>`, '', dueAll > 0 ? 'bad' : '', 'wide')}</div>`;
  }
}
function tileDefs() {
  const f = (code) => ({ key: 'f:' + code });
  return HS.mode === 'biz'
    ? [{ key: 'r:pos' }, { key: 'r:items' }, { key: 'r:itemreq' }, f('14-1'), f('03-1'), f('04-1'), { key: 'r:reports' }, { key: 'r:stock', label: () => T('stockbal') }]
    : [f('10-1'), f('10-2'), f('10-4'), { key: 'r:dues' }, { key: 'r:biz', label: () => T('pl') }, { key: 'r:reports' }, { key: 'r:payables', label: () => T('payables') }, { key: 'r:daybook', label: () => T('daybook') }];
}
function tile(e, o = {}) {
  const pin = isPinned(e.key), c = e.cnt && CNT && CNT[e.cnt];
  return `<div class="qt"><button class="qm" data-act="go" data-v="${esc(e.route)}">${ico(e.icon)}<span class="lb">${esc(o.label || e.label)}</span>${c ? `<span class="dot ${e.tone || 'warn'}"></span>` : ''}</button>
    <button class="st" data-act="nav_pin" data-v="${esc(e.key)}" aria-pressed="${pin}" aria-label="${esc(pin ? T('unpin') : T('pin'))}">${pin ? IC.starF : IC.star}</button></div>`;
}
function drawTiles() {
  const box = $('#hv_tiles'), hd = $('#hv_th'); if (!box) return;
  hd.textContent = T(HS.mode === 'biz' ? 'tiles_biz' : 'tiles_acc');
  const mode = npMode();
  box.innerHTML = tileDefs().map((d) => {
    if (d.soon) return `<div class="qt soon"><div class="qm" aria-disabled="true"><span class="lb">${esc(T(d.soon))}</span><span class="chip">${esc(T('soon'))}</span></div></div>`;
    const e = byKey(d.key);
    if (!e) return mode === 'lock' && d.key.startsWith('f:') ? '' : '';   // form not in the forms table at all: nothing to show
    if (!e.live) return `<div class="qt soon"><div class="qm" aria-disabled="true"><span class="lb">${esc(e.label)}</span><span class="chip">${esc(T('soon'))}</span></div></div>`;
    if (!e.ok) return mode === 'lock' ? `<div class="qt lock"><div class="qm" aria-disabled="true">${IC.lock}<span class="lb">${esc(d.label ? d.label() : e.label)}</span><span class="chip">${esc(T('noperm'))}</span></div></div>` : '';
    return tile(e, d.label ? { label: d.label() } : {});
  }).join('');
}
function drawFav() {
  const box = $('#hv_fav'); if (!box) return;
  const pinned = effPins().map(byKey).filter((e) => e && e.ok && e.live);
  const u = usage(), pk = new Set(pinned.map((e) => e.key));
  const used = Object.keys(u).filter((k) => !pk.has(k)).sort((a, b) => u[b] - u[a]).map(byKey).filter((e) => e && e.ok && e.live && e.key !== 'r:home').slice(0, Math.max(4, 8 - pinned.length));
  const add = `<div class="qt"><button class="qm" data-act="nav_picker">${IC.plus}<span class="lb">${esc(T('add'))}</span></button></div>`;
  box.innerHTML = (pinned.length || used.length ? '' : `<p class="muted" style="margin:0 0 10px">${esc(T('fav_empty'))}</p>`) + `<div class="qgrid">${pinned.map((e) => tile(e)).join('')}${used.map((e) => tile(e)).join('')}${add}</div>`;
}
function drawMods() {
  const box = $('#hv_mods'); if (!box) return;
  const cn = CNT || {}, mode = npMode();
  const order = ['pos', 'dues', 'reports', 'biz', 'items', 'itemreq', 'assets', 'itemimport', 'exceptions', 'numaudit', 'emergency', 'releases', 'staff', 'rulehub'];
  const lockable = new Set(['pos', 'dues', 'biz', 'items']);
  box.innerHTML = order.map((k) => {
    const e = byKey('r:' + k); if (!e) return '';
    if (!e.ok) return mode === 'lock' && lockable.has(k) ? `<div class="lockcard">${IC.lock}<span>${esc(e.label)} · ${esc(T('noperm'))}</span></div>` : '';
    const c = e.cnt && cn[e.cnt];
    return `<button class="tile" data-act="go" data-v="${esc(e.route)}">${ico(e.icon)}<span>${esc(e.label)}</span>${c ? `<span class="badge">${c}</span>` : ''}</button>`;
  }).join('');
}
function drawCtl() {
  const box = $('#hv_ctl'); if (!box) return;
  const e = byKey('r:control'); if (!e || !e.ok) { box.innerHTML = ''; return; }
  const c = (CNT && CNT.ctl) || 0;
  box.innerHTML = `<button class="tile t-ink" data-act="go" data-v="control" style="width:100%;margin-top:12px;min-height:76px;flex-direction:row;align-items:center;justify-content:flex-start">${ico('control')}<span style="flex:1;text-align:start"><b>${esc(T('ctl'))}</b><br><small>${esc(T('ctl_d'))}</small></span>${c ? `<span class="badge">${c}</span>` : ''}</button>`;
}
function drawForms() {
  const box = $('#hv_formsb'); if (!box) return;
  const mine = (FORMS || []).filter((f) => f.area !== 'master' && f.code !== 'POS' && P(f.code, 'view') && !isOwnerFormHidden(f));
  const AREAS = ['showroom', 'cash', 'stock', 'purchase', 'factory', 'sales', 'staff', 'assets', 'owner', 'settings'];
  const by = AREAS.map((a) => [a, mine.filter((f) => f.area === a)]).filter(([, l]) => l.length);
  box.innerHTML = by.length ? by.map(([a, l]) => `<h3 style="margin:12px 0 4px">${esc(t('area_' + a))}</h3>${l.map((f) => {
    const pr = perms()[f.code] || {}, live = f.code === '0-1' ? isOwner() : (B.forms && B.forms[f.code]);
    return `<div class="perm"><div class="row between" ${live ? `data-act="openform" data-v="${f.code}" style="cursor:pointer;min-height:44px"` : 'style="opacity:.6"'}><span><b>${esc(f.code)}</b> · ${esc(nm(f))}</span><span class="row">${
      live ? '' : `<span class="chip">${esc(t('soon'))}</span>`}${pr.enter ? `<span class="chip ok">${esc(t('can_enter'))}</span>` : `<span class="chip">${esc(t('can_view'))}</span>`}${pr.approve ? `<span class="chip warn">${esc(t('can_approve'))}</span>` : ''}</span></div></div>`; }).join('')}`).join('')
    : `<p class="muted">${esc(t('no_forms'))}</p>`;
}
const isOwnerFormHidden = () => false;

// ---------- handlers ----------
Object.assign(H, {
  nav_open: () => openDrawer(),
  nav_close: () => closeDrawer(),
  nav_go: (a) => {
    const r = a.dataset.v;
    if (history.state && history.state.bosNav) { pendingRoute = r; closeDrawer(); } else { setDrawer(false); location.hash = '#/' + r; }
  },
  nav_grp: (a) => { const og = groupOpen(), g = a.dataset.v; og[g] = !og[g]; store.set('bos_navg_' + uid(), JSON.stringify(og)); dr_body(); },
  nav_pin: (a) => togglePin(a.dataset.v),
  nav_picker: pickerSheet,
  nav_me: meSheet,
  nav_reset: () => { store.set('bos_pins_' + uid(), '[]'); store.set('bos_use_' + uid(), '{}'); setFavQ([]); okRes(sb.from('user_favourites').delete().eq('user_id', uid())).catch(() => {}); closeSheet(); afterPin(); },
  hv_mode: (a) => { HS.mode = a.dataset.v; store.set('bos_hmode_' + uid(), HS.mode); document.querySelectorAll('.seg button').forEach((b) => b.setAttribute('aria-pressed', b.dataset.v === HS.mode)); drawTiles(); drawStats(); },
  hv_period: (a) => { HS.period = a.dataset.v; store.set('bos_hper_' + uid(), HS.period); drawPeriod(); loadStats(); },
});
// a language switch re-renders the page (route) but the drawer footer lives outside #app: sync() rebuilds it
const prevLang = H.lang;
H.lang = (a) => { sig = ''; return prevLang(a); };

B.curLoc = curLoc; B.setCurLoc = setCurLoc; B.fyStart = fyStart;
window.BOS_NAV = { loadSheets, curLoc, fyStart, grantFlags: () => GF, ctlOk, menuBtn, headExtra, sync, home, open: openDrawer, close: closeDrawer, pins, usage, togglePin, entries: () => entries().filter((e) => e.live), syncFavs };
})();
