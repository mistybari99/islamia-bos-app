/* Islamia BOS · Information architecture: the ONE list of screens (BOS.IA). Loaded before nav.js / control.js.
   Drawer, Home tiles, bottom nav, global search, Control Center extras, breadcrumbs and "Recent" all read this file.
   To add a screen: add one record below (see docs/IA_RULES.md). Visibility predicates take the context object that nav.js builds (c.own, c.P, c.GF ...)
   and only reuse the checks nav.js always had; the server stays the authority on every call (hiding is a convenience). No colours / fonts here. */
(() => {
'use strict';
const B = window.BOS, L = B.L, lab = B.lab;

// ---------- 13 categories (ids kept from the old drawer where the meaning is the same: dash, item, purch, sale, acc, people, reports, settings) ----------
const GROUPS = [
  { id: 'dash', label: L('ড্যাশবোর্ড', 'Dashboard', 'Dashboard') },
  { id: 'item', label: L('আইটেম ও মাস্টার ডেটা', 'Items & Master Data', 'Item ও Master Data') },
  { id: 'stock', label: L('ইনভেন্টরি ও স্টক', 'Inventory & Stock', 'Inventory ও Stock') },
  { id: 'purch', label: L('ক্রয় ও সরবরাহকারী', 'Purchasing & Suppliers', 'Purchase ও Supplier') },
  { id: 'factory', label: L('কারখানা ও উৎপাদন', 'Factory & Production', 'Factory ও Production') },
  { id: 'sale', label: L('বিক্রি ও POS', 'Sales & POS', 'Sale ও POS') },
  { id: 'cust', label: L('গ্রাহক, অর্ডার ও ইনভয়েস', 'Customers, Orders & Invoices', 'Customer, Order ও Invoice') },
  { id: 'acc', label: L('হিসাব ও অর্থ', 'Accounting & Finance', 'Accounting ও Finance') },
  { id: 'appr', label: L('অনুমোদন ও ব্যতিক্রম', 'Approvals & Exceptions', 'Approval ও Exception') },
  { id: 'reports', label: L('রিপোর্ট ও বিশ্লেষণ', 'Reports & Analytics', 'Report ও Analytics') },
  { id: 'people', label: L('স্টাফ, ভূমিকা ও অনুমতি', 'Staff, Roles & Permissions', 'Staff, Role ও Permission') },
  { id: 'loc', label: L('লোকেশন', 'Locations', 'Location') },
  { id: 'settings', label: L('প্রশাসন ও সেটিংস', 'Administration & Settings', 'Administration ও Settings') },
];
const GID = GROUPS.map((g) => g.id);
// paper-form areas (forms table) -> category
const AREA_G = { cash: 'acc', stock: 'stock', factory: 'factory', assets: 'stock', purchase: 'purch', sales: 'sale', showroom: 'sale', staff: 'people', owner: 'reports' };

// ---------- predicates (c = context from nav.js: own, P(code, 'view|enter|approve'), GF grant flags, locOk(), canPos(), anyApprove(), ctlOk()) ----------
const any = () => true;
const owner = (c) => c.own;
const locOk = (c) => c.locOk();
const pos = (c) => c.canPos();
const approver = (c) => c.anyApprove();

// t:<key> = reuse the i18n.js text; otherwise [bn, en, mix]. kw = Bangla + English search words. mob 1..3 = bottom-bar priority (1 best). cnt = attention-count key in nav.js. mod = order in Home "modules". home = order on Home tiles per mode.
const rec = (id, group, label, o) => Object.assign({ id, route: id, group, label, kw: [], verbs: [], aliases: [], quick: null, flow: null, icon: id, ok: any, mob: 3, qa: [], status: 'live', drawer: true }, o || {});
const IA = [
  // Dashboard
  rec('home', 'dash', 't:home', { icon: 'home', kw: ['dashboard', 'হোম', 'ড্যাশবোর্ড', 'শুরু'], mob: 0 }),
  // Items & master data
  rec('items', 'item', 't:items', { ok: (c) => c.P('ITEMS', 'view'), kw: ['item', 'product', 'price', 'আইটেম', 'পণ্য', 'দাম', 'মূল্য', 'barcode', 'বারকোড'], mob: 2, mod: 5, home: { biz: 2 }, qa: [{ route: 'items/new', label: ['নতুন পণ্য', 'Add product', 'নতুন Product'], ok: (c) => c.P('ITEMS', 'enter') }] }),
  rec('items/new', 'item', ['নতুন পণ্য যোগ', 'Add product', 'নতুন Product যোগ'], { icon: 'plus', ok: (c) => c.P('ITEMS', 'enter'), kw: ['new item', 'add item', 'নতুন আইটেম', 'নতুন পণ্য'] }),
  rec('lists', 'item', 't:lists', { ok: (c) => c.own || c.GF.list_manage === true, cnt: 'lq', tone: 'info', kw: ['list', 'options', 'dropdown', 'category', 'তালিকা', 'অপশন', 'ক্যাটাগরি', 'ধরন'] }),
  rec('settings2/units', 'item', ['একক রূপান্তর', 'Unit conversions', 'Unit conversion'], { icon: 'doc', ok: owner, kw: ['unit', 'kg', 'pound', 'convert', 'একক', 'ইউনিট', 'কেজি'] }),
  rec('itemimport', 'item', ['আইটেম মাস্টার ইমপোর্ট', 'Item master import', 'Item master import'], { icon: 'doc', ok: owner, mod: 8, kw: ['import', 'csv', 'master', 'ইমপোর্ট', 'আমদানি', 'মাস্টার'] }),
  rec('itemmap', 'item', ['পুরনো আইটেম মেলানো', 'Old items to master codes', 'পুরনো Item মেলানো'], { icon: 'doc', ok: (c) => c.own || c.GF.item_create === true, kw: ['map', 'match', 'old item', 'link', 'মেলানো', 'পুরনো', 'কোড'] }),
  rec('bulkitems', 'item', ['আইটেম একসাথে বদল', 'Bulk item editor', 'Item একসাথে বদল'], { icon: 'items', ok: (c) => c.own || c.GF.item_bulk === true || c.GF.item_create === true || c.P('ITEMS', 'enter'), kw: ['bulk', 'price list', 'mass edit', 'একসাথে', 'দাম বসানো', 'বাল্ক', 'দাম'] }),
  rec('itemtypes', 'item', ['আইটেমের ধরন ও ডিফল্ট', 'Item types & defaults', 'Item type ও Default'], { icon: 'doc', ok: owner, kw: ['type', 'class', 'default', 'ধরন', 'ডিফল্ট', 'কাঁচামাল', 'raw material'] }),
  rec('products', 'item', 't:items', { ok: (c) => c.P('ITEMS', 'view'), drawer: false, status: 'hidden', alias: 'items' }),
  // Inventory & stock
  rec('stock', 'stock', ['স্টক', 'Stock', 'Stock'], { icon: 'items', ok: locOk, mob: 2, mod: 6, home: { biz: 8 }, kw: ['stock', 'inventory', 'balance', 'wastage', 'count', 'transfer', 'স্টক', 'মজুত', 'নষ্ট', 'গণনা', 'হস্তান্তর'] }),
  rec('assets', 'stock', ['সম্পদ-খাতা', 'Asset register', 'Asset register'], { icon: 'doc', ok: locOk, mod: 7, kw: ['asset', 'equipment', 'machine', 'সম্পদ', 'যন্ত্র', 'সরঞ্জাম'] }),
  // Purchasing & suppliers
  rec('purchase', 'purch', ['ক্রয় বিল', 'Purchase bills', 'Purchase Bill'], { icon: 'doc', ok: locOk, mob: 2, kw: ['purchase', 'bill', 'buy', 'grn', 'ক্রয়', 'কেনা', 'বিল', 'মাল গ্রহণ'], qa: [{ route: 'purchase/new', label: ['নতুন ক্রয় বিল', 'New purchase bill', 'নতুন Purchase bill'], ok: locOk }] }),
  rec('purchase/new', 'purch', ['নতুন ক্রয় বিল', 'New purchase bill', 'নতুন Purchase bill'], { icon: 'plus', ok: locOk, kw: ['new purchase', 'নতুন ক্রয়'] }),
  rec('purchase/return', 'purch', ['ক্রয় ফেরত', 'Purchase return', 'Purchase return'], { icon: 'doc', ok: locOk, kw: ['return', 'supplier return', 'ফেরত', 'ক্রয় ফেরত'] }),
  rec('payables', 'purch', ['সরবরাহকারীর পাওনা', 'Supplier payables', 'Supplier-এর Payable'], { icon: 'dues', ok: locOk, home: { acc: 7 }, kw: ['supplier', 'payable', 'owe', 'pay supplier', 'সরবরাহকারী', 'পাওনা', 'বাকি', 'পরিশোধ'] }),
  rec('settings2/suppliers', 'purch', ['সরবরাহকারী (সেটিংস)', 'Suppliers (settings)', 'Supplier (settings)'], { icon: 'settings', ok: owner, drawer: false, parent: 'settings2', kw: ['supplier', 'সরবরাহকারী'] }),
  // Factory & production
  rec('recipes', 'factory', ['রেসিপি ও উৎপাদন', 'Recipes & production', 'Recipe ও Production'], { icon: 'doc', ok: locOk, kw: ['recipe', 'bom', 'production', 'factory', 'produce', 'রেসিপি', 'উৎপাদন', 'কারখানা', 'তৈরি'] }),
  // Sales & POS
  rec('pos', 'sale', 't:pos', { ok: pos, mob: 1, mod: 1, home: { biz: 1 }, kw: ['pos', 'sell', 'sale', 'cashier', 'receipt', 'বিক্রি', 'সেল', 'ক্যাশ', 'রসিদ'] }),
  rec('salereturn', 'sale', ['বিক্রি ফেরত', 'Sale returns', 'Sale return'], { icon: 'doc', ok: pos, kw: ['return', 'refund', 'ফেরত', 'রিফান্ড', 'বিক্রি ফেরত'] }),
  // Customers, orders, invoices
  rec('dues', 'cust', 't:dues', { ok: pos, mob: 2, mod: 2, home: { acc: 4 }, kw: ['customer', 'due', 'credit', 'baki', 'বাকি', 'গ্রাহক', 'কাস্টমার', 'ধার'] }),
  rec('invoice', 'cust', ['ইনভয়েস ও প্রিন্ট', 'Invoice & print', 'Invoice ও Print'], { icon: 'doc', ok: owner, kw: ['invoice', 'print', 'template', 'label', 'logo', 'ইনভয়েস', 'প্রিন্ট', 'ছাপা', 'লেবেল'] }),
  // Accounting & finance
  rec('daybook', 'acc', ['দিনের খাতা', 'Day book', 'Day book'], { icon: 'doc', ok: (c) => c.own || c.GF.view_daybook === true, home: { acc: 8 }, kw: ['day book', 'cash book', 'ledger', 'expense', 'দিনের খাতা', 'ক্যাশবুক', 'খরচ', 'হিসাব'] }),
  rec('cashmoves', 'acc', ['ক্যাশ ও ব্যাংকের লেনদেন', 'Cash & bank moves', 'Cash ও Bank লেনদেন'], { icon: 'money', ok: (c) => c.own || c.GF.cash_move === true, kw: ['bank deposit', 'deposit', 'owner', 'advance', 'top up', 'hub', 'ব্যাংক জমা', 'অগ্রিম', 'অ্যাডভান্স', 'মালিক', 'ক্যাশ'] }),
  rec('ledgerlinks', 'acc', ['খাতায় পোস্ট (লিংক)', 'Ledger links', 'Ledger links'], { icon: 'doc', ok: owner, kw: ['ledger', 'post', 'journal', 'link', 'খাতা', 'পোস্ট', 'লেজার'] }),
  // Approvals & exceptions
  rec('exceptions', 'appr', 't:exceptions', { ok: approver, cnt: 'ex', tone: 'bad', mob: 1, mod: 9, kw: ['exception', 'problem', 'red', 'alert', 'গরমিল', 'সমস্যা', 'লাল'] }),
  rec('pending', 'appr', ['অনুমোদনের অপেক্ষায়', 'Awaiting approval', 'Approval-এর অপেক্ষায়'], { icon: 'doc', ok: approver, kw: ['pending', 'approve', 'অনুমোদন', 'অপেক্ষা'] }),
  rec('itemreq', 'appr', 't:item_req', { ok: (c) => c.P('ITEMS', 'enter') || c.P('ITEMS', 'approve'), cnt: 'itm', tone: 'info', mod: 4, home: { biz: 3 }, also: ['item'], kw: ['item request', 'price change', 'আইটেম অনুরোধ', 'দাম বদল', 'অনুমোদন'] }),
  rec('releases', 'appr', 't:releases', { ok: owner, cnt: 'rel', tone: 'warn', mod: 10, kw: ['release', 'unlock', 'red control', 'ছাড়', 'মুক্তি'] }),
  rec('emergency', 'appr', 't:emergency', { ok: owner, cnt: 'em', tone: 'warn', mod: 11, kw: ['emergency', 'override', 'জরুরি'] }),
  rec('changes', 'appr', ['বদলের অনুরোধ', 'Change requests', 'Change request'], { icon: 'doc', ok: (c) => c.own || c.GF.change_approve === true, cnt: 'chg', tone: 'info', kw: ['change', 'revision', 'edit request', 'বদল', 'সংশোধন'] }),
  rec('numaudit', 'appr', 't:numaudit', { ok: approver, mod: 12, kw: ['audit', 'gap', 'serial', 'number', 'অডিট', 'ফাঁক', 'সিরিয়াল'] }),
  rec('outbox', 'appr', ['ফোনে জমা (পাঠানো হয়নি)', 'Not sent yet', 'Phone-এ জমা (Not sent yet)'], { icon: 'doc', cnt: 'obx', tone: 'warn', kw: ['outbox', 'offline', 'unsent', 'queue', 'জমা', 'পাঠানো হয়নি', 'অফলাইন'] }),
  // Reports & analytics
  rec('reports', 'reports', ['রিপোর্ট', 'Reports', 'Report'], { icon: 'doc', mob: 3, mod: 3, home: { biz: 7, acc: 6 }, kw: ['report', 'sales report', 'stock report', 'export', 'csv', 'রিপোর্ট', 'প্রতিবেদন', 'এক্সপোর্ট'] }),
  rec('biz', 'reports', 't:biz', { ok: (c) => c.own || c.P('POS', 'approve'), mod: 4.5, home: { acc: 5 }, kw: ['profit', 'loss', 'p&l', 'analysis', 'margin', 'লাভ', 'ক্ষতি', 'বিশ্লেষণ', 'ব্যবসা'] }),
  rec('brandpnl', 'reports', ['ব্র্যান্ড অনুযায়ী লাভ-ক্ষতি', 'Brand profit & loss', 'Brand Profit-Loss'], { icon: 'biz', ok: (c) => c.own || c.P('POS', 'approve'), kw: ['brand', 'profit', 'ব্র্যান্ড', 'লাভ'] }),
  rec('discounts', 'reports', ['ডিসকাউন্ট রিপোর্ট', 'Discounts report', 'Discount report'], { icon: 'doc', ok: (c) => c.own || c.P('POS', 'approve'), also: ['sale'], kw: ['discount', 'offer', 'ডিসকাউন্ট', 'ছাড়'] }),
  rec('report', 'reports', ['রিপোর্ট', 'Reports', 'Report'], { icon: 'doc', drawer: false, status: 'hidden', alias: 'reports' }),
  // Staff, roles, permissions
  rec('staff', 'people', 't:staff', { ok: owner, cnt: 'stf', tone: 'info', mod: 13, kw: ['staff', 'employee', 'user', 'approve user', 'স্টাফ', 'কর্মী', 'ব্যবহারকারী'] }),
  rec('matrix', 'people', 't:matrix', { ok: owner, kw: ['role', 'permission', 'access', 'ভূমিকা', 'অনুমতি', 'রোল'] }),
  rec('salary', 'people', ['বেতন রিপোর্ট', 'Salary report', 'Salary report'], { icon: 'doc', ok: (c) => c.own || c.GF.salary_view === true, home: { acc: 9 }, kw: ['salary', 'payroll', 'wage', 'বেতন', 'মজুরি'] }),
  // Locations
  rec('locations', 'loc', ['লোকেশন', 'Locations', 'Location'], { ok: (c) => c.own || c.GF.location_manage === true || c.GF.head_management === true, cnt: 'loc', tone: 'info', kw: ['location', 'showroom', 'godown', 'branch', 'লোকেশন', 'শোরুম', 'গোডাউন', 'শাখা'] }),
  rec('locset', 'loc', 't:locset', { ok: (c) => c.own || c.GF.settings_approve === true || c.GF.head_management === true, cnt: 'sd', tone: 'info', kw: ['limit', 'settings sheet', 'সীমা', 'সেটিংস শিট'] }),
  rec('locsheet', 'loc', ['লোকেশন সেটিংস শিট', 'Location settings sheet', 'Location settings sheet'], { icon: 'locset', ok: (c) => c.own || c.GF.settings_approve === true || c.GF.head_management === true || c.GF.location_manage === true, drawer: false, parent: 'locset', kw: ['sheet', 'version', 'শিট'] }),
  rec('rollout', 'loc', ['কাগজ / পাশাপাশি / অ্যাপ', 'Paper / Parallel / App', 'Paper / Parallel / App'], { icon: 'control', ok: (c) => c.own || c.GF.rollout_manage === true, kw: ['rollout', 'paper', 'parallel', 'go live', 'কাগজ', 'পাশাপাশি', 'অ্যাপ'] }),
  // Administration & settings
  rec('control', 'settings', ['কন্ট্রোল সেন্টার', 'Control Center', 'Control Center'], { icon: 'control', ok: (c) => c.ctlOk(), cnt: 'ctl', tone: 'info', kw: ['control', 'admin', 'কন্ট্রোল', 'নিয়ন্ত্রণ'] }),
  rec('rulehub', 'settings', 't:rulehub', { ok: owner, mod: 14, kw: ['rules', 'switch', 'grants', 'নিয়ম', 'অপশন', 'অনুমতি'] }),
  rec('switchboard', 'settings', ['সুইচবোর্ড (সব চালু/বন্ধ)', 'Switchboard (all on/off)', 'Switchboard (সব on/off)'], { icon: 'settings', ok: owner, kw: ['switch', 'on off', 'toggle', 'blind', 'pin', 'flag', 'সুইচ', 'চালু', 'বন্ধ', 'অন', 'অফ', 'সেটিংস'] }),
  rec('rules', 'settings', 't:rules', { ok: owner, kw: ['form rule', 'count first', 'red block', 'ফর্মের নিয়ম'] }),
  rec('settings', 'settings', 't:settings', { ok: owner, kw: ['settings', 'config', 'সেটিংস'] }),
  rec('settings2', 'settings', ['সেটিংস (সব অপশন)', 'Settings (all options)', 'Settings (সব Option)'], { ok: owner, kw: ['fiscal', 'vat', 'barcode', 'tax', 'বছর', 'ভ্যাট', 'সেটিংস'] }),
  rec('logs', 'settings', 't:logs', { ok: owner, kw: ['log', 'audit trail', 'history', 'লগ', 'পরিবর্তন', 'ইতিহাস'] }),
  rec('backup', 'settings', 't:backup', { ok: owner, kw: ['backup', 'download', 'export all', 'ব্যাকআপ', 'ডাউনলোড'] }),
];
// settings2 sub pages: searchable and listed on the Administration page, not in the drawer
[['fiscal', ['অর্থবছর ও সপ্তাহ', 'Fiscal year & week', 'Fiscal year ও week'], ['fiscal', 'year', 'week', 'অর্থবছর', 'বছর']], ['vat', ['ভ্যাট', 'VAT', 'VAT'], ['vat', 'tax', 'ভ্যাট', 'কর']],
  ['barcode', ['বারকোড', 'Barcode', 'Barcode'], ['barcode', 'scanner', 'camera', 'বারকোড', 'স্ক্যান']], ['noperm', ['অনুমতি না থাকলে', 'No-permission display', 'Permission না থাকলে'], ['lock', 'hide', 'permission', 'লুকানো', 'তালা']],
  ['stock', ['স্টক নিয়ম', 'Stock rules', 'Stock rule'], ['negative stock', 'স্টক']], ['disc', ['ডিসকাউন্ট নিয়ম', 'Discount rules', 'Discount rule'], ['discount', 'ডিসকাউন্ট']],
  ['shelf', ['শেলফ লাইফ', 'Shelf life', 'Shelf life'], ['expiry', 'shelf', 'মেয়াদ']], ['access', ['প্রবেশাধিকার', 'Access', 'Access'], ['access', 'login', 'pin']], ['fav', ['প্রিয় ডিফল্ট', 'Favourite defaults', 'Favourite default'], ['favourite', 'প্রিয়']]]
  .forEach(([k, l, kw]) => IA.push(rec('settings2/' + k, 'settings', l, { icon: 'settings', ok: owner, drawer: false, parent: 'settings2', kw })));

// Control Center extras (owner only): screens that sit next to the 12 built-in tiles
[['bulkitems', 'lists'], ['itemmap', 'lists'], ['itemimport', 'lists'], ['itemtypes', 'lists'], ['settings2', 'rules'], ['invoice', 'rules'], ['rulehub', 'rules'], ['changes', 'places']].forEach(([r, g]) => { const x = IA.find((y) => y.route === r); if (x) x.cc = g; });
// 3D icon key per screen (icons3d.js). The old r.icon stays for the Classic theme; i3 is used by the Premium themes. Unknown routes fall back to icon, then doc.
const I3 = { items: 'bag', 'items/new': 'plus', lists: 'list', 'settings2/units': 'scale', itemimport: 'download', itemmap: 'link', bulkitems: 'bag', itemtypes: 'tag', stock: 'box', assets: 'tool', purchase: 'cart', 'purchase/new': 'plus',
  'purchase/return': 'swap', payables: 'money', recipes: 'chef', pos: 'pos', salereturn: 'swap', dues: 'dues', invoice: 'print', daybook: 'book', cashmoves: 'money', switchboard: 'settings', ledgerlinks: 'link', exceptions: 'warn', pending: 'stamp', itemreq: 'swap', releases: 'unlock',
  emergency: 'alert', changes: 'edit', numaudit: 'hash', outbox: 'upload', reports: 'chart', biz: 'pie', brandpnl: 'pie', discounts: 'tag', staff: 'users', matrix: 'matrix', salary: 'money', locations: 'pin', locset: 'pinset', locsheet: 'pinset',
  rollout: 'sliders', control: 'sliders', rulehub: 'shield', rules: 'rules', settings: 'gear', settings2: 'sliders', logs: 'history', backup: 'download', home: 'home' };
IA.forEach((r) => { r.i3 = I3[r.route] || (r.route.startsWith('settings2/') ? 'gear' : r.icon); });
const byRoute = new Map(IA.map((r) => [r.route, r]));

// ---------- Increment A: verbs (the "Do" part of search), quick actions per persona, bottom slots per persona. flow stays null (guided flows come later). ----------
// form codes used below were checked against the forms table (schema.sql seed): 03-1 04-1 04-2 04-3 05-1 06-1 10-1 10-2 10-3 11-1 14-1 (05-3 / 05-4 / 06-2 / 06-3 exist too, form pages for them are reached from the category page, no verb bound).
const FORM_I3 = { cashcount: 'money', stockcount: 'box', grn: 'download', issue: 'upload', expense: 'money', transfer: 'truck', daily: 'factory', reqmat: 'chef', handover: 'swap', digital: 'money', hubcash: 'money' };
const FORM = (code) => (c) => c.P(code, 'enter') && c.formLive(code);
const V = (route, verbs, aliases) => { const r = IA.find((x) => x.route === route); if (r) { r.verbs = verbs; r.aliases = aliases || []; } };
V('pos', ['sell', 'sale', 'pos', 'বিক্রি', 'বিক্রয়', 'সেল'], ['cashier']); V('dues', ['collect', 'due', 'baki', 'বাকি', 'আদায়'], ['credit']);
V('items/new', ['new item', 'add item', 'add product', 'নতুন আইটেম', 'নতুন পণ্য'], []); V('purchase/new', ['new purchase', 'purchase bill', 'bill', 'ক্রয় বিল', 'নতুন ক্রয়'], []);
V('payables', ['pay supplier', 'payables', 'সরবরাহকারী পেমেন্ট', 'পরিশোধ'], ['supplier payment']); V('salereturn', ['return', 'sale return', 'ফেরত'], ['refund']);
V('pending', ['approve', 'approval', 'pending', 'অনুমোদন'], []); V('stock', ['wastage', 'waste', 'stock', 'নষ্ট', 'স্টক'], ['low stock']); V('exceptions', ['exception', 'red', 'গরমিল', 'ব্যতিক্রম'], []);
// form-bound actions: id, form route, label, verbs
const DOF = [
  ['cashcount', 'form/14-1', ['ক্যাশ গণনা', 'Cash count', 'Cash count'], ['cash count', '14-1', 'ক্যাশ গণনা', 'ক্যাশ']], ['stockcount', 'form/04-3', ['স্টক গণনা', 'Stock count', 'Stock count'], ['count stock', 'stock count', '04-3', 'স্টক গণনা']],
  ['grn', 'form/04-1', ['মাল গ্রহণ', 'Receive goods', 'মাল গ্রহণ (GRN)'], ['receive', 'grn', '04-1', 'মাল গ্রহণ']], ['issue', 'form/04-2', ['সরবরাহ দেওয়া', 'Issue material', 'Issue'], ['issue', '04-2', 'সরবরাহ']],
  ['expense', 'form/10-2', ['খরচ', 'Expense', 'খরচ'], ['expense', 'খরচ', '10-2']], ['transfer', 'form/03-1', ['স্থানান্তর', 'Transfer', 'Transfer'], ['transfer', 'challan', '03-1', 'স্থানান্তর']],
  ['daily', 'form/05-1', ['দৈনিক উৎপাদন শিট', 'Daily production sheet', 'Daily sheet'], ['daily sheet', '05-1', 'উৎপাদন']], ['reqmat', 'form/06-1', ['কাঁচামাল চাওয়া', 'Request material', 'Material request'], ['request material', '06-1']],
  ['handover', 'form/11-1', ['হস্তান্তর', 'Handover', 'Handover'], ['handover', '11-1', 'হস্তান্তর']], ['digital', 'form/10-3', ['ডিজিটাল মেলানো', 'Digital reconcile', 'Digital reconcile'], ['reconcile', '10-3', 'digital']],
  ['hubcash', 'form/10-1', ['হাব ক্যাশ', 'Hub cash', 'Hub cash'], ['hub cash', '10-1']],
].map(([id, route, label, verbs]) => ({ id, route, label, verbs, aliases: [], icon: 'doc', i3: FORM_I3[id] || 'doc', ok: FORM(route.slice(5)), form: route.slice(5) }));
const doRecs = () => IA.filter((r) => r.verbs.length && r.status === 'live').map((r) => ({ id: r.id, route: r.route, label: r.label, verbs: r.verbs, aliases: r.aliases, icon: r.icon, i3: r.i3, ok: r.ok, rec: r })).concat(DOF);
const doLabel = (d) => (d.rec ? labelOf(d.rec) : lab(L(d.label[0], d.label[1], d.label[2])));
// persona from what the person may do (no new permission logic: the same P / GF / canPos checks)
function persona(c) {
  if (c.own) return 'owner';
  if (c.roles && c.roles.includes('management')) return 'manager';
  if (c.P('05-1', 'enter')) return 'factory';
  if (c.P('04-1', 'enter') || c.P('04-2', 'enter')) return 'store';
  if (c.GF.view_daybook || c.GF.salary_view || c.P('10-3', 'enter')) return 'accountant';
  if (c.P('10-1', 'enter')) return 'hub';
  return 'cashier';
}
// quick actions (2.5) and bottom slots (3.1) by persona; ids are DO ids / record routes. Unavailable ones are skipped and the next candidate fills in.
const QUICK_BY = {
  owner: ['pos', 'control', 'biz', 'dues', 'items', 'reports'], manager: ['pos', 'cashcount', 'grn', 'stockcount', 'expense', 'stock'], cashier: ['pos', 'dues', 'salereturn', 'cashcount', 'outbox'],
  store: ['grn', 'issue', 'transfer', 'stockcount', 'stock'], factory: ['daily', 'recipes', 'reqmat', 'transfer', 'handover'], accountant: ['daybook', 'payables', 'purchase', 'digital', 'reports', 'salary'], hub: ['hubcash', 'payables', 'daybook', 'transfer', 'dues'],
};
const SLOTS_BY = {
  owner: ['home', 'ctl', 'reports', 'me'], manager: ['home', 'pos', 'cashcount', 'menu'], cashier: ['pos', 'dues', 'cashcount', 'me'], store: ['home', 'stock', 'grn', 'menu'],
  factory: ['home', 'daily', 'recipes', 'menu'], accountant: ['home', 'daybook', 'payables', 'menu'], hub: ['home', 'hubcash', 'payables', 'menu'],
};
const slotTarget = (id, c) => {   // id -> {route,label,icon} when this person may open it
  if (id === 'ctl') { const r = byRoute.get('control'); if (r && visible(r, c)) return { route: 'control', label: labelOf(r), icon: r.icon, i3: r.i3 }; const p = byRoute.get('pending'); return p && visible(p, c) ? { route: 'pending', label: labelOf(p), icon: p.icon, i3: p.i3 } : null; }
  const d = doRecs().find((x) => x.id === id) || (byRoute.get(id) ? { id, route: id, rec: byRoute.get(id), icon: byRoute.get(id).icon, i3: byRoute.get(id).i3, ok: byRoute.get(id).ok } : null); if (!d) return null; let ok = false; try { ok = !!d.ok(c); } catch (e) { ok = false; }
  return ok ? { route: d.route, label: doLabel(d), icon: d.icon, i3: d.i3 || (d.rec && d.rec.i3) } : null;
};
function quickActions(c) {
  const out = [], seen = new Set();
  for (const id of QUICK_BY[persona(c)]) { const t0 = slotTarget(id, c); if (t0 && !seen.has(t0.route) && out.length < 6) { seen.add(t0.route); out.push(t0); } }
  return out;
}
function slots(c) {   // exactly 4 entries: {kind:'home'|'menu'|'me'} or {route,label,icon}; a slot the person cannot open is replaced from the persona's quick list, then Home / Menu / Me
  const want = SLOTS_BY[persona(c)], res = [], used = new Set();
  for (const id of want) {
    if (id === 'home' || id === 'menu' || id === 'me') { res.push({ kind: id }); continue; }
    const t0 = slotTarget(id, c); if (t0) { res.push(t0); used.add(t0.route); } else res.push(null);
  }
  const spare = quickActions(c).filter((x) => !used.has(x.route)), fall = [{ kind: 'home' }, { kind: 'menu' }, { kind: 'me' }];
  return res.map((x) => x || spare.shift() || fall.find((f) => !res.some((y) => y && y.kind === f.kind)) || { kind: 'menu' }).slice(0, 4);
}
// bottom bar for the Premium layout: [2 slots] [centre Sell orb] [2 slots] when the person may sell; otherwise the plain 4 slots. Sell is never repeated in the side slots.
function barSlots(c) {
  const all = slots(c), sell = slotTarget('pos', c);
  if (!sell) return { left: all.slice(0, 2), centre: null, right: all.slice(2, 4) };
  const rest = all.filter((x) => x.route !== 'pos'), used = new Set(rest.map((x) => x.route || x.kind));
  const spare = quickActions(c).filter((x) => x.route !== 'pos' && !used.has(x.route)), fall = [{ kind: 'home' }, { kind: 'menu' }, { kind: 'me' }];
  while (rest.length < 4) rest.push(spare.shift() || fall.find((f) => !rest.some((y) => y.kind === f.kind)) || { kind: 'menu' });
  return { left: rest.slice(0, 2), centre: sell, right: rest.slice(2, 4) };
}
function searchSections(q, c) {
  const w = norm(q); if (w.length < 2) return { do: [], go: [], settings: [] };
  const hits = search(q, c), dos = doRecs().filter((d) => { let ok = false; try { ok = !!d.ok(c); } catch (e) { ok = false; } return ok && d.verbs.concat(d.aliases).map(norm).some((v) => v === w || v.startsWith(w) || (w.length >= 3 && w.includes(v) && v.length >= 3)); });
  return { do: dos.map((d) => ({ route: d.route, label: doLabel(d), icon: d.icon })), go: hits.filter((r) => r.group !== 'settings'), settings: hits.filter((r) => r.group === 'settings') };
}

const labelOf = (r) => (typeof r.label === 'string' ? (() => { const x = window.BOS_APP.t(r.label.slice(2)); return x; })() : lab(L(r.label[0], r.label[1], r.label[2])));
const groupOf = (id) => GROUPS.find((g) => g.id === id);
const groupLabel = (id) => { const g = groupOf(id); return g ? lab(g.label) : ''; };
// hash path -> record (two segments first: settings2/units, purchase/new; then the first)
function resolve(path) {
  const p = String(path || '').replace(/^#?\/?/, '').split('/').filter(Boolean);
  if (!p.length) return byRoute.get('home');
  return (p[1] && byRoute.get(p[0] + '/' + p[1])) || byRoute.get(p[0]) || null;
}
const visible = (r, c) => { try { return !!r.ok(c); } catch (e) { return false; } };

// ---------- search: label > keyword > route > category; every word of the query must hit something ----------
const norm = (x) => String(x || '').toLowerCase().trim();
function score(r, q, c) {
  const words = norm(q).split(/\s+/).filter(Boolean); if (!words.length) return 0;
  const title = labelOf(r).toLowerCase(), lbs = (Array.isArray(r.label) ? r.label.join(' ') : '').toLowerCase(), kws = r.kw.map(norm);
  const g = groupOf(r.group), gl = (g.label.bn + ' ' + g.label.en + ' ' + g.label.mix).toLowerCase();
  let total = 0;
  for (const w of words) {
    let s = 0;
    if (title.startsWith(w)) s = 100; else if (title.includes(w)) s = 70; else if (lbs.includes(w)) s = 60;
    else if (kws.some((k) => k === w)) s = 55; else if (kws.some((k) => k.startsWith(w))) s = 45; else if (kws.some((k) => k.includes(w))) s = 30;
    else if (r.route.toLowerCase().includes(w)) s = 20; else if (gl.includes(w)) s = 8;
    if (!s) return 0; total += s;
  }
  return total;
}
function search(q, c) {
  return IA.filter((r) => r.status === 'live' && visible(r, c)).map((r) => ({ r, s: score(r, q, c) })).filter((x) => x.s > 0).sort((a, b) => b.s - a.s).map((x) => x.r);
}

// ---------- recent screens (last 5 per person, localStorage only; always inside try/catch) ----------
const RK = (uid) => 'bos_recent_' + uid;
function recent(uid) { try { const v = JSON.parse(window.BOS_APP.store.get(RK(uid)) || '[]'); return Array.isArray(v) ? v.filter((x) => typeof x === 'string').slice(0, 5) : []; } catch (e) { return []; } }
function pushRecent(uid, route) {
  if (!route || route === 'home') return;
  try { const a = [route, ...recent(uid).filter((x) => x !== route)].slice(0, 5); window.BOS_APP.store.set(RK(uid), JSON.stringify(a)); } catch (e) { /* private window: no recent list */ }
}

// ---------- bottom bar: Home, POS slot, the best other shortcut for this role, Menu, Me ----------
function bottom(c) {
  return IA.filter((r) => r.status === 'live' && r.mob >= 1 && r.mob <= 2 && r.id !== 'pos' && visible(r, c)).sort((a, b) => a.mob - b.mob).slice(0, 1);
}
// ---------- Home tiles: base list per mode, topped up with role-relevant live screens (priority) ----------
const HOME_FORMS = { biz: [['f:14-1', 4], ['f:03-1', 5], ['f:04-1', 6]], acc: [['f:10-1', 1], ['f:10-2', 2], ['f:10-4', 3]] };
const HOME_LABEL = { 'r:stock': { biz: 'stockbal' }, 'r:biz': { acc: 'pl' }, 'r:payables': { acc: 'payables' }, 'r:daybook': { acc: 'daybook' } };
function homeKeys(mode) {
  const base = IA.filter((r) => r.home && r.home[mode]).map((r) => [r.home[mode], 'r:' + r.route]).concat(HOME_FORMS[mode].map(([k, n]) => [n, k])).sort((a, b) => a[0] - b[0]);
  return base.map((x) => x[1]);
}
function topUp(mode, c, have, max) {
  const out = []; if (have >= max) return out;
  IA.filter((r) => r.status === 'live' && r.drawer && r.id !== 'home' && !(r.home && r.home[mode]) && r.mob <= 2 && r.mob >= 1 && visible(r, c)).sort((a, b) => a.mob - b.mob).forEach((r) => { if (have + out.length < max) out.push('r:' + r.route); });
  return out;
}
const modules = () => IA.filter((r) => r.mod).sort((a, b) => a.mod - b.mod);

// ---------- shared loading / empty / error / offline block (existing classes only) ----------
function state(kind, msg, retry) {
  const A = window.BOS_APP, t = A.t, esc = A.esc;
  const txt = msg || (kind === 'loading' ? t('loading') : '');
  if (kind === 'loading') return `<p class="muted center pad" data-state="loading">${esc(txt)}</p>`;
  if (kind === 'empty') return `<p class="muted center pad" data-state="empty">${esc(txt)}</p>`;
  const cls = kind === 'offline' ? 'warn' : 'bad';
  return `<div class="notice ${cls}" data-state="${kind}">${esc(txt)}</div>${retry ? `<button class="full" data-act="ia_retry">${esc(lab(L('আবার চেষ্টা করুন', 'Try again', 'আবার Try করুন')))}</button>` : ''}`;
}

B.IA = IA;
B.ui = Object.assign(B.ui || {}, { state });
B.ia = { persona, quickActions, slots, barSlots, searchSections, doRecs, QUICK_BY, SLOTS_BY, DOF, GROUPS, GID, AREA_G, byRoute: (r) => byRoute.get(r) || null, resolve, label: labelOf, groupLabel, groupOf, visible, search, score, recent, pushRecent, bottom, homeKeys, topUp, modules, HOME_LABEL, state };
})();
