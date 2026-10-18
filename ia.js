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
const ruleOn = (k) => { try { return !!(B.rule && B.rule(k, false) === true); } catch (e) { return false; } };   // R2: a screen whose owner switch is OFF is not offered at all (the server decides every call)

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
  rec('recipebook', 'factory', ['কারিগরের রেসিপি বই', 'Artisan recipe book', 'Artisan-এর recipe book'], { icon: 'doc', ok: (c) => c.own || c.GF.recipe_view === true || c.GF.recipe_manage === true, kw: ['artisan', 'recipe book', 'steps', 'karigor', 'কারিগর', 'রেসিপি বই', 'ধাপ', 'শেফ'] }),
  rec('costing', 'factory', ['খরচ ও ওভারহেড', 'Costing & overhead', 'Costing ও overhead'], { icon: 'money', ok: (c) => c.own || c.GF.view_cost === true, kw: ['cost', 'overhead', 'conversion', 'gas', 'electricity', 'labour', 'pool', 'absorbed', 'খরচ', 'ওভারহেড', 'গ্যাস', 'বিদ্যুৎ', 'রূপান্তর'] }),
  rec('costsources', 'factory', ['খরচের সোর্স ও ভাগ', 'Cost sources & allocation', 'Cost source ও ভাগ'], { icon: 'money', ok: (c) => c.own || c.GF.view_cost === true, kw: ['electricity', 'gas', 'rent', 'licence', 'bill', 'allocation', 'shared meter', 'বিদ্যুৎ', 'গ্যাস', 'ভাড়া', 'বিল', 'ভাগ', 'অভাগিত'] }),
  rec('costattrib', 'factory', ['খরচ কোন শাখার', 'Which showroom a cost belongs to', 'খরচ কোন শাখার'], { icon: 'money', ok: (c) => c.own || c.GF.view_cost === true, kw: ['attribution', 'branch cost', 'main centre', 'allocate', 'reassign', 'approval', 'শাখা', 'মূল কেন্দ্র', 'খরচ ভাগ', 'অনুমোদন', 'ঝুঁকি'] }),
  // RPT-B4 (docs/integration/RPT-B4.md): production capture and reports, targets and KPI, capacity and labour. Placement per docs/REPORTS_AUDIT_1.md "Report placement": #40-#43 #45-#49 #51 #52 #55 = factory; #44 #50 #53 = stock; #7 #9 #10 = dashboard.
  rec('prodplan', 'factory', ['উৎপাদন: পরিকল্পনা, অর্ডার ও রান', 'Production: plan, orders & runs', 'Production: plan, order ও run'], { icon: 'doc', ok: locOk, kw: ['production plan', 'plan', 'production order', 'order', 'pending order', 'real use', 'actual use', 'reject', 'rework', 'labour hours', 'run capture', 'উৎপাদন পরিকল্পনা', 'অর্ডার', 'আসল ব্যবহার', 'বাতিল', 'পুনঃকাজ', 'শ্রম-ঘণ্টা'], verbs: ['plan production', 'record real use', 'record reject'] }),
  rec('prodreports', 'factory', ['উৎপাদন রিপোর্ট', 'Production reports', 'Production report'], { icon: 'doc', ok: locOk, also: ['stock', 'reports'], kw: ['plan vs actual', 'order status', 'pending orders', 'dispatch', 'reconciliation', 'cost variance', 'price variance', 'usage variance', 'yield', 'reject', 'rework', 'wastage by batch', 'consumption', 'পরিকল্পনা বনাম আসল', 'অর্ডারের অবস্থা', 'ফলন', 'খরচের পার্থক্য', 'নষ্ট', 'ব্যাচ'], verbs: ['plan vs actual', 'cost variance'] }),
  rec('capacity', 'factory', ['শ্রম ও ক্ষমতা', 'Labour & capacity', 'Labour ও capacity'], { icon: 'doc', ok: locOk, also: ['reports'], kw: ['output per labour hour', 'labour hours', 'capacity', 'utilization', 'rated capacity', 'production line', 'শ্রম-ঘণ্টা', 'ক্ষমতা', 'লাইন'], verbs: ['set rated capacity'] }),
  rec('targets', 'dash', ['লক্ষ্য, KPI ও তুলনা', 'Targets, KPI & comparison', 'Target, KPI ও comparison'], { icon: 'biz', ok: locOk, also: ['sale', 'reports'], kw: ['target', 'sales target', 'achievement', 'kpi', 'alert', 'trend', 'factory vs retail', 'transfer value', 'লক্ষ্য', 'বিক্রির লক্ষ্য', 'অর্জন', 'কারখানা', 'খুচরা', 'তুলনা'], verbs: ['set a sales target', 'factory vs retail'] }),
  // Sales & POS
  rec('pos', 'sale', 't:pos', { ok: pos, mob: 1, mod: 1, home: { biz: 1 }, kw: ['pos', 'sell', 'sale', 'cashier', 'receipt', 'বিক্রি', 'সেল', 'ক্যাশ', 'রসিদ'] }),
  rec('salereturn', 'sale', ['বিক্রি ফেরত', 'Sale returns', 'Sale return'], { icon: 'doc', ok: pos, kw: ['return', 'refund', 'ফেরত', 'রিফান্ড', 'বিক্রি ফেরত'] }),
  // Customers, orders, invoices
  rec('dues', 'cust', 't:dues', { ok: pos, mob: 2, mod: 2, home: { acc: 4 }, kw: ['customer', 'due', 'credit', 'baki', 'বাকি', 'গ্রাহক', 'কাস্টমার', 'ধার'] }),
  rec('invoice', 'cust', ['ইনভয়েস ও প্রিন্ট', 'Invoice & print', 'Invoice ও Print'], { icon: 'doc', ok: owner, kw: ['invoice', 'print', 'template', 'label', 'logo', 'ইনভয়েস', 'প্রিন্ট', 'ছাপা', 'লেবেল'] }),
  // Accounting & finance
  rec('daybook', 'acc', ['দিনের খাতা', 'Day book', 'Day book'], { icon: 'doc', ok: (c) => c.own || c.GF.view_daybook === true, home: { acc: 8 }, kw: ['day book', 'cash book', 'ledger', 'expense', 'দিনের খাতা', 'ক্যাশবুক', 'খরচ', 'হিসাব'] }),
  rec('finance2', 'acc', ['আর্থিক হিসাব ২ (ব্যাংক, বছর শেষ, ভ্যাট, সম্পদ, বাজেট)', 'Finance 2 (bank, year-end, VAT, assets, budgets)', 'Finance 2 (bank, year-end, VAT, assets, budget)'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_manage === true, kw: ['bank reconcile', 'bank statement', 'year end', 'closing', 'vat', 'fixed asset', 'depreciation', 'budget', 'ব্যাংক স্টেটমেন্ট', 'বছর শেষ', 'ভ্যাট', 'অবচয়', 'বাজেট'] }),
  rec('attend2', 'people', ['হাজিরা ২ (পাঞ্চ, লেখা, একবার গোনা)', 'Attendance 2 (punch, mark, counted once)', 'Attendance 2 (punch, mark, একবার গোনা)'], { icon: 'check', ok: (c) => true, kw: ['punch', 'check in', 'passkey', 'face', 'finger', 'gps', 'mark others', 'self punch', 'lock', 'হাজিরা', 'পাঞ্চ', 'আঙুল', 'মুখ'] }),
  rec('eqcheck', 'appr', ['সার্ভারে হিসাব মেলানো', 'Server re-check of totals', 'Server-এ হিসাব মেলানো'], { icon: 'check', ok: (c) => c.own || c.anyApprove(), kw: ['equation', 'total', 'recompute', 'mismatch', '10-2', '02-2', 'হিসাব', 'মেলানো'] }),
  rec('stockx', 'stock', ['স্টক রিপোর্ট ও কোয়ালিটি', 'Stock reports & quality', 'Stock report ও quality'], { icon: 'items', ok: locOk, kw: ['reorder', 'expiry', 'batch', 'fefo', 'wastage reason', 'quality', 'qc', 'রিঅর্ডার', 'মেয়াদ', 'ব্যাচ', 'নষ্টের কারণ', 'কোয়ালিটি'] }),
  rec('stockrep/ledger', 'stock', ['স্টক নড়াচড়ার খাতা', 'Stock movement ledger', 'Stock নড়াচড়ার খাতা'], { icon: 'doc', ok: locOk, drawer: true, also: ['reports'], kw: ['ledger', 'movement', 'running balance', 'opening', 'closing', 'খাতা', 'নড়াচড়া', 'ব্যালান্স'] }),
  rec('stockrep/recon', 'stock', ['সময়ের স্টক মিলান', 'Stock reconciliation for a period', 'সময়ের Stock মিলান'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports','appr'], kw: ['reconcile', 'reconciliation', 'opening in out closing', 'in transit', 'short', 'মিলান', 'গরমিল', 'পথে'] }),
  rec('batchrep/batches', 'stock', ['ব্যাচ অনুযায়ী স্টক ও মেয়াদ', 'Stock by batch and expiry', 'Batch অনুযায়ী Stock ও মেয়াদ'], { icon: 'doc', ok: locOk, drawer: true, also: ['reports'], kw: ['batch', 'lot', 'expiry', 'fefo', 'unbatched', 'ব্যাচ', 'মেয়াদ'] }),
  rec('batchrep/ageing', 'stock', ['তৈরি পণ্যের বয়স', 'Finished goods ageing', 'তৈরি পণ্যের বয়স'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['ageing', 'aging', 'age', 'old stock', 'finished goods', 'বয়স', 'পুরনো'] }),
  rec('batchrep/unsold', 'stock', ['ব্যাচ অনুযায়ী অবিক্রীত', 'Unsold by production batch', 'Batch অনুযায়ী Unsold'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports','factory'], kw: ['unsold', 'production batch', 'অবিক্রীত', 'উৎপাদন ব্যাচ'] }),
  rec('batchrep/distribution', 'stock', ['আউটলেট ও ব্যাচ বিতরণ', 'Distribution by outlet and batch', 'Outlet ও Batch বিতরণ'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports','factory'], kw: ['distribution', 'outlet', 'batch', 'বিতরণ', 'আউটলেট'] }),
  rec('batchrep/expired', 'stock', ['মেয়াদ শেষ / নষ্ট / অবিক্রীত', 'Expired, damaged and unsold', 'মেয়াদ শেষ / নষ্ট / Unsold'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['expired', 'damaged', 'unsold', 'wastage', 'মেয়াদ শেষ', 'নষ্ট', 'অবিক্রীত'] }),
  rec('batchrep/trace', 'stock', ['ব্যাচের পথ', 'Batch trace', 'Batch trace'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['trace', 'batch trace', 'ব্যাচ'] }),
  rec('report/stock_balance', 'stock', ['স্টক ব্যালান্স ও মূল্য', 'Stock levels and value', 'Stock balance ও মূল্য'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['stock balance', 'stock value', 'raw', 'packaging', 'item type', 'স্টক', 'মূল্য'] }),
  rec('report/expiry_soon', 'stock', ['মেয়াদ শেষ / শিগগির শেষ', 'Expired and expiring soon', 'Expiry শেষ / শিগগির শেষ'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['expiry', 'expired', 'expiring', 'মেয়াদ'] }),
  rec('report/transfers_register', 'stock', ['সব ট্রান্সফার', 'All transfers', 'সব Transfer'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['transfer', 'register', 'in transit', 'short', 'ট্রান্সফার'] }),
  rec('report/transfers_gap', 'stock', ['ট্রান্সফার: পৌঁছায়নি / কম', 'Transfers not received or short', 'Transfer: পৌঁছায়নি / কম'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['transfer', 'short', 'not received'] }),
  rec('report/k2_count_variance', 'stock', ['স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['count', 'variance', 'stock count', 'গণনা'] }),
  rec('report/stock_adjustments', 'stock', ['স্টক সমন্বয়ের ইতিহাস', 'Stock adjustment history', 'Stock সমন্বয়ের ইতিহাস'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['adjustment', 'count adjust', 'who', 'why', 'সমন্বয়'] }),
  rec('report/wastage', 'stock', ['অপচয় (কারণ / আইটেম অনুযায়ী)', 'Wastage by reason / item', 'অপচয় (reason / item)'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['wastage', 'waste', 'অপচয়', 'নষ্ট'] }),
  rec('report/wastage_rate', 'stock', ['অপচয় %', 'Wastage % of stock handled', 'অপচয় %'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['wastage percent', 'waste rate', 'অপচয় শতাংশ'] }),
  rec('report/stock_integrity', 'stock', ['ঋণাত্মক স্টক ও হিসাবের গরমিল', 'Negative stock and integrity', 'ঋণাত্মক Stock ও গরমিল'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports','appr'], kw: ['negative stock', 'integrity', 'mismatch', 'ঋণাত্মক', 'গরমিল'] }),
  rec('report/daily_closing', 'stock', ['দিনের শেষের স্টক বনাম পরের দিনের বিক্রি', 'Closing stock vs next-day sales and loss', 'দিনের শেষের Stock বনাম পরের দিন'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['closing stock', 'next day', 'daily'] }),
  rec('report/item_turnover', 'stock', ['টার্নওভার ও কত দিনের মাল', 'Turnover and days on hand', 'Turnover ও কত দিনের মাল'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['turnover', 'days on hand', 'cover', 'টার্নওভার'] }),
  rec('report/item_slow', 'stock', ['ধীর ও অবিক্রীত আইটেম', 'Slow and non-moving items', 'ধীর ও non-moving Item'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports','sale'], kw: ['slow', 'non moving', 'unsold items', 'ধীর'] }),
  rec('report/p4_supplier_score', 'purch', ['সরবরাহকারী স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['supplier score', 'scorecard', 'returns', 'quality'] }),
  rec('report/supplier_ageing', 'purch', ['সরবরাহকারীকে দেনার বয়স', 'Supplier payables ageing', 'Supplier-কে দেনার বয়স'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['payables ageing', 'overdue', 'credit days', 'দেনা'] }),
  // RPT-B3 (docs/integration/RPT-B3.md): traceability and recall, stockout log, purchasing reports. Placement per docs/REPORTS_AUDIT_2.md "Report placement": stock = Traceability and recall / Stockout; purch = Purchases and prices / Suppliers.
  rec('trace', 'stock', ['ব্যাচ ট্রেস (কোথা থেকে এলো, কোথায় গেলো)', 'Trace a batch', 'Batch trace'], { icon: 'items', ok: locOk, also: ['reports'], kw: ['trace', 'traceability', 'batch', 'lot', 'supplier lot', 'raw lot', 'where did it go', 'ট্রেস', 'ব্যাচ', 'লট', 'কোথায় গেছে', 'উৎস'], verbs: ['trace a batch'] }),
  rec('recall', 'stock', ['রিকল কেস', 'Recall cases', 'Recall case'], { icon: 'doc', ok: locOk, also: ['reports'], kw: ['recall', 'withdraw', 'bad batch', 'affected stock', 'food safety', 'রিকল', 'ফেরত নেওয়া', 'ক্ষতিকর', 'খারাপ ব্যাচ'], verbs: ['open a recall'] }),
  rec('stockout', 'stock', ['স্টক শেষ (চাহিদা পূরণ হয়নি)', 'Stockout log', 'Stockout log (চাহিদা পূরণ হয়নি)'], { icon: 'items', ok: locOk, also: ['reports'], kw: ['stockout', 'out of stock', 'unmet demand', 'missed sale', 'customer asked', 'স্টক শেষ', 'মাল নেই', 'চাহিদা', 'বিক্রি হয়নি'], verbs: ['log a stockout'] }),
  rec('purchrep', 'purch', ['ক্রয় রিপোর্ট ও সাপ্লায়ার', 'Purchasing reports & suppliers', 'Purchase report ও supplier'], { icon: 'doc', ok: locOk, also: ['reports'], kw: ['supplier return', 'rejection', 'delivery', 'agreed price', 'standard price', 'preferred supplier', 'dependency', 'purchase adjustment', 'সাপ্লায়ার ফেরত', 'নির্ধারিত দাম', 'ডেলিভারি', 'সাপ্লায়ার নির্ভরতা'] }),
  rec('report/p2_rate_trend', 'purch', ['দামের ধারা (মূল্যসহ)', 'Price trend (with value)', 'দামের trend (value সহ)'], { icon: 'doc', ok: locOk, drawer: false, also: ['reports'], kw: ['price trend', 'rate trend', 'purchase rate', 'দামের ধারা', 'ক্রয় দর'] }),
  rec('onlineorders', 'sale', ['অনলাইন অর্ডার', 'Online orders', 'Online অর্ডার'], { icon: 'doc', ok: pos, kw: ['online order', 'facebook', 'whatsapp', 'delivery', 'advance', 'অনলাইন', 'অর্ডার', 'ডেলিভারি'] }),
  rec('inbox', 'sale', ['বার্তা ইনবক্স', 'Message inbox', 'Message inbox'], { icon: 'doc', ok: pos, kw: ['inbox', 'message', 'facebook', 'messenger', 'instagram', 'whatsapp', 'web form', 'বার্তা', 'ইনবক্স', 'অর্ডার'] }),
  rec('website', 'sale', ['ওয়েবসাইট', 'Website', 'Website'], { icon: 'doc', ok: owner, mob: 3, kw: ['website', 'web', 'site', 'online shop', 'catalogue', 'publish', 'ওয়েবসাইট', 'ওয়েব', 'দোকান', 'অনলাইন শপ', 'ক্যাটালগ', 'পাবলিশ'], verbs: ['publish item', 'web orders', 'website settings'] }),
  rec('saleforms', 'settings', ['ফর্ম 20-১/২/৪ ↔ বিক্রি', 'Forms 20-1/2/4 <-> sales', 'Form 20-1/2/4 ↔ sale'], { icon: 'doc', ok: owner, kw: ['20-1', '20-2', '20-4', 'link', 'shadow', 'order form', 'invoice', 'জোড়া'] }),
  rec('benefitsx', 'people', ['কর্মীর সুবিধা (রিপোর্ট)', 'Employee benefits (report)', 'Employee সুবিধা (report)'], { icon: 'users', ok: (c) => c.own || c.GF.employee_manage === true || c.GF.salary_view === true, kw: ['benefit', 'allowance', 'eligible', 'festival', 'সুবিধা', 'ভাতা'] }),
  rec('orderreports', 'sale', ['অর্ডার ও ডেলিভারি রিপোর্ট', 'Order and delivery reports', 'Order ও delivery report'], { icon: 'doc', ok: pos, also: ['factory'], kw: ['order register', 'cake order', 'delayed order', 'on time delivery', 'fulfilment', 'cancelled order', 'refund', 'delivery cost', 'order profit', 'advance balance', 'অর্ডার রিপোর্ট', 'ডেলিভারি', 'কেক অর্ডার', 'বাতিল অর্ডার'] }),
  rec('custinsight', 'cust', ['গ্রাহক বিশ্লেষণ', 'Customer insight', 'Customer insight'], { icon: 'users', ok: pos, kw: ['credit risk', 'overdue', 'lifetime value', 'customer returns', 'complaints', 'cake history', 'credit days', 'বাকির ঝুঁকি', 'মেয়াদোত্তীর্ণ', 'গ্রাহকের অভিযোগ'] }),
  rec('staffreports', 'people', ['কর্মী রিপোর্ট', 'Staff reports', 'Staff report'], { icon: 'check', ok: (c) => c.own || c.GF.attendance_manage === true || c.GF.employee_view === true || c.GF.employee_manage === true || c.GF.stock_production === true || c.GF.salary_view === true || c.GF.view_reports === true || c.GF.report_staff === true, also: ['acc'],
    kw: ['attendance summary', 'overtime', 'late', 'sales per labour hour', 'output per hour', 'cashier variance', 'cash short', 'salary basis', 'হাজিরা সারাংশ', 'ওভারটাইম', 'ক্যাশিয়ার'] }),
  rec('biexport', 'reports', ['BI এক্সপোর্ট', 'BI export', 'BI export'], { icon: 'doc', ok: (c) => c.own || c.GF.export_data === true, kw: ['export', 'csv', 'json', 'bi', 'power bi', 'sheet', 'এক্সপোর্ট'] }),
  rec('integrations', 'settings', ['সংযোগ ও এক্সপোর্ট', 'Integrations & export', 'Integrations ও export'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_manage === true || c.GF.customer_manage === true, kw: ['sms', 'whatsapp', 'gateway', 'bkash', 'reconcile', 'export', 'csv', 'journal', 'trial balance', 'এসএমএস', 'হোয়াটসঅ্যাপ', 'মিলান', 'এক্সপোর্ট', 'জার্নাল'] }),
  rec('restoredrill', 'settings', ['রিস্টোর ড্রিল', 'Restore drill', 'Restore drill'], { icon: 'settings', ok: owner, kw: ['restore', 'drill', 'backup test', 'recovery', 'রিস্টোর', 'ড্রিল', 'ব্যাকআপ যাচাই'] }),
  rec('twofa', 'settings', ['দুই-ধাপ যাচাই (2FA)', 'Two-factor sign-in (2FA)', 'Two-factor (2FA)'], { icon: 'settings', ok: () => true, kw: ['2fa', 'otp', 'authenticator', 'totp', 'security', 'দুই ধাপ', 'নিরাপত্তা', 'কোড'] }),
  rec('quickexp', 'acc', ['দ্রুত খরচ এন্ট্রি', 'Quick expense', 'Quick expense'], { icon: 'money', ok: (c) => c.own || c.P('10-2', 'enter'), kw: ['quick expense', 'day book expense', 'expense', 'imprest', 'voucher', 'দ্রুত খরচ', 'খরচ', 'ভাউচার', 'ইমপ্রেস্ট'], verbs: ['add expense', 'খরচ লিখুন'] }),
  rec('paths', 'settings', ['পথ সুইচ ও শ্যাডো কপি', 'Path switches & shadow copies', 'Path switch ও shadow copy'], { icon: 'settings', ok: owner, kw: ['shadow', 'duplicate', 'double count', 'lock', 'payroll mode', 'primary', 'শ্যাডো', 'ডুপ্লিকেট', 'দুবার গোনা', 'লক', 'সুইচ'] }),
  rec('cashmoves', 'acc', ['ক্যাশ ও ব্যাংকের লেনদেন', 'Cash & bank moves', 'Cash ও Bank লেনদেন'], { icon: 'money', ok: (c) => c.own || c.GF.cash_move === true, kw: ['bank deposit', 'deposit', 'owner', 'advance', 'top up', 'hub', 'ব্যাংক জমা', 'অগ্রিম', 'অ্যাডভান্স', 'মালিক', 'ক্যাশ'] }),
  rec('shortages', 'acc', ['কম / বেশি ও পথে কম মাল', 'Shortages', 'কম / বেশি ও পথে কম'], { icon: 'money', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['short', 'over', 'cash short', 'cash over', 'transit', 'carrier', 'claim', 'write off', 'lost in transit', 'shortage', 'কম', 'বেশি', 'ক্যাশ কম', 'পথে কম', 'বাহক', 'ক্ষতি', 'দাবি'], verbs: ['approve cash short', 'claim from carrier', 'write off lost goods'] }),
  rec('wallets', 'acc', ['মোবাইল ওয়ালেট (বিকাশ/নগদ/রকেট)', 'Mobile wallets', 'Mobile ওয়ালেট'], { icon: 'money', ok: (c) => c.own || c.P('10-3', 'view') || c.P('10-3', 'enter') || c.GF.accounts_view === true, kw: ['wallet', 'bkash', 'nagad', 'rocket', 'upay', 'mobile money', 'wallet fee', 'cash out', 'digital payment', '10-3', 'reconcile', 'বিকাশ', 'নগদ', 'রকেট', 'উপায়', 'ওয়ালেট', 'মোবাইল ব্যাংকিং', 'ডিজিটাল পেমেন্ট'], verbs: ['count wallet', 'add wallet fee', 'move wallet money'], aliases: ['bkash', 'nagad'] }),
  rec('ledgerlinks', 'acc', ['খাতায় পোস্ট (লিংক)', 'Ledger links', 'Ledger links'], { icon: 'doc', ok: owner, kw: ['ledger', 'post', 'journal', 'link', 'খাতা', 'পোস্ট', 'লেজার'] }),
  // Approvals & exceptions
  rec('exceptions', 'appr', 't:exceptions', { ok: approver, cnt: 'ex', tone: 'bad', mob: 1, mod: 9, kw: ['exception', 'problem', 'red', 'alert', 'গরমিল', 'সমস্যা', 'লাল'] }),
  rec('pending', 'appr', ['অনুমোদনের অপেক্ষায়', 'Awaiting approval', 'Approval-এর অপেক্ষায়'], { icon: 'doc', ok: approver, kw: ['pending', 'approve', 'অনুমোদন', 'অপেক্ষা'] }),
  rec('itemreq', 'appr', 't:item_req', { ok: (c) => c.P('ITEMS', 'enter') || c.P('ITEMS', 'approve'), cnt: 'itm', tone: 'info', mod: 4, home: { biz: 3 }, also: ['item'], kw: ['item request', 'price change', 'আইটেম অনুরোধ', 'দাম বদল', 'অনুমোদন'] }),
  rec('releases', 'appr', 't:releases', { ok: (c) => c.own || c.GF.release_decide === true, cnt: 'rel', tone: 'warn', mod: 10, kw: ['release', 'unlock', 'red control', 'ছাড়', 'মুক্তি'] }),
  rec('emergency', 'appr', 't:emergency', { ok: owner, cnt: 'em', tone: 'warn', mod: 11, kw: ['emergency', 'override', 'জরুরি'] }),
  rec('changes', 'appr', ['বদলের অনুরোধ', 'Change requests', 'Change request'], { icon: 'doc', ok: (c) => c.own || c.GF.change_approve === true, cnt: 'chg', tone: 'info', kw: ['change', 'revision', 'edit request', 'বদল', 'সংশোধন'] }),
  rec('numaudit', 'appr', 't:numaudit', { ok: approver, mod: 12, kw: ['audit', 'gap', 'serial', 'number', 'অডিট', 'ফাঁক', 'সিরিয়াল'] }),
  rec('outbox', 'appr', ['ফোনে জমা (পাঠানো হয়নি)', 'Not sent yet', 'Phone-এ জমা (Not sent yet)'], { icon: 'doc', cnt: 'obx', tone: 'warn', kw: ['outbox', 'offline', 'unsent', 'queue', 'জমা', 'পাঠানো হয়নি', 'অফলাইন'] }),
  // Reports & analytics
  rec('reports', 'reports', ['রিপোর্ট', 'Reports', 'Report'], { icon: 'doc', mob: 3, mod: 3, home: { biz: 7, acc: 6 }, kw: ['report', 'sales report', 'stock report', 'export', 'csv', 'রিপোর্ট', 'প্রতিবেদন', 'এক্সপোর্ট'] }),
  rec('reports/hub', 'reports', ['বিজনেস মেমোরি (কী ঘটেছিল)', 'Business Memory (what happened)', 'Business Memory (কী ঘটেছিল)'], { icon: 'doc', also: ['reports'], ok: any, mob: 3, kw: ['what happened', 'replay', 'day replay', 'timeline', 'why did', 'compare', 'spend', 'how much paid', 'electricity', 'meals', 'audit trail', 'who voided', 'কী ঘটেছিল', 'কী হয়েছিল', 'ইতিহাস', 'খরচ খুঁজুন', 'তুলনা', 'বিদ্যুৎ বিল', 'কে বাতিল করেছে'], verbs: ['see what happened', 'find a spend', 'compare two periods'] }),
  rec('reports/map', 'reports', ['রিপোর্ট মানচিত্র', 'Reports map', 'Report map'], { icon: 'doc', kw: ['reports map', 'report list', 'master list', 'which reports', 'report status', 'রিপোর্ট মানচিত্র', 'রিপোর্টের তালিকা', 'অবস্থা', 'কোন রিপোর্ট'] }),
  rec('biz', 'reports', 't:biz', { ok: (c) => c.own || c.P('POS', 'approve'), mod: 4.5, home: { acc: 5 }, also: ['acc'], kw: ['profit', 'loss', 'p&l', 'analysis', 'margin', 'লাভ', 'ক্ষতি', 'বিশ্লেষণ', 'ব্যবসা'] }),
  rec('profitcheck', 'acc', ['Profit check', 'Profit check', 'Profit check'], { icon: 'biz', also: ['reports'], ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true,
    kw: ['profit', 'one profit number', 'loss', 'wastage', 'shortage', 'partner profit', 'reconcile', 'journal profit', 'brand', 'parity', 'expense report', 'salary'],
    verbs: ['compare profit', 'leave a loss out of profit', 'change brand'], aliases: ['profit check'] }),
  rec('brandpnl', 'dash', ['ব্র্যান্ড অনুযায়ী লাভ-ক্ষতি', 'Brand profit & loss', 'Brand Profit-Loss'], { icon: 'biz', also: ['reports'], ok: (c) => c.own || c.P('POS', 'approve'), kw: ['brand', 'profit', 'ব্র্যান্ড', 'লাভ'] }),
  rec('discounts', 'sale', ['ডিসকাউন্ট রিপোর্ট', 'Discounts report', 'Discount report'], { icon: 'doc', ok: (c) => c.own || c.P('POS', 'approve'), also: ['reports'], kw: ['discount', 'offer', 'ডিসকাউন্ট', 'ছাড়'] }),
  rec('expenseregister', 'reports', ['Expense register', 'Expense register', 'Expense register'], { icon: 'money', also: ['acc'], ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true,
    kw: ['expense register', 'expenses', 'voucher', 'expense list', 'quick expense', 'bank charge', 'wallet fee', 'marketing spend', 'three totals', 'expense report vs journal', 'খরচের তালিকা', 'ভাউচার', 'খরচ'],
    verbs: ['list expenses', 'compare expense totals'], aliases: ['expense register'] }),
  rec('statements', 'reports', ['Statements (P&L by month, cash flow, working capital)', 'Statements (P&L by month, cash flow, working capital)', 'Statements (P&L by month, cash flow, working capital)'], { icon: 'biz', also: ['acc'], ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true,
    kw: ['statement', 'p&l by month', 'profit and loss by outlet', 'cash flow', 'cash flow statement', 'operating investing financing', 'working capital', 'account classes', 'journal profit', 'আর্থিক বিবরণী', 'ক্যাশ ফ্লো', 'ওয়ার্কিং ক্যাপিটাল'],
    verbs: ['see cash flow', 'see working capital', 'class an account'], aliases: ['statements', 'cash flow statement'] }),
  rec('report', 'reports', ['রিপোর্ট', 'Reports', 'Report'], { icon: 'doc', drawer: false, status: 'hidden', alias: 'reports' }),
  // RPT-C3: marketing, audit and planning reports (reports stay open to the existing report grants; the server decides)
  rec('campaigns', 'reports', ['মার্কেটিং ক্যাম্পেইন ও রিপোর্ট', 'Marketing campaigns & reports', 'Marketing campaign ও report'], { icon: 'doc', ok: (c) => c.own || c.P('POS', 'approve') || c.GF.view_reports === true || c.GF.report_marketing === true, also: ['acc'],
    kw: ['campaign', 'marketing', 'spend', 'roi', 'cac', 'acquisition', 'promotion', 'offer', 'coupon', '18-1', 'ক্যাম্পেইন', 'মার্কেটিং', 'প্রচার', 'অফার'], verbs: ['see marketing spend by campaign', 'post marketing spend to the books'] }),
  rec('couponuse', 'reports', ['কুপন ও অফারের ব্যবহার', 'Coupon & offer usage', 'Coupon ও offer usage'], { icon: 'doc', ok: (c) => c.own || c.P('POS', 'approve') || c.GF.view_reports === true || c.GF.report_marketing === true, drawer: false, parent: 'campaigns',
    kw: ['coupon', 'voucher', 'offer code', 'কুপন', 'অফার কোড'] }),
  rec('auditreports', 'appr', ['অডিট ও নিয়ন্ত্রণ রিপোর্ট', 'Audit & control reports', 'Audit ও control report'], { icon: 'check', ok: (c) => c.own || c.anyApprove() || c.GF.view_reports === true || c.GF.report_control === true, also: ['item'],
    kw: ['audit log', 'void', 'reversal', 'correction', 'approval delay', 'override', 'activity', 'missing cost', 'অডিট', 'বাতিল', 'সংশোধন', 'অনুমোদন'], verbs: ['read the audit log', 'see all voids'] }),
  rec('market', 'reports', ['বাজার ও বৃদ্ধি', 'Market & growth', 'বাজার ও growth'], { icon: 'chart', kw: ['market', 'competitor', 'research', 'opportunity', 'growth', 'price', 'festival', 'বাজার', 'প্রতিযোগী', 'সুযোগ', 'বৃদ্ধি'], verbs: ['add a finding', 'record a competitor price', 'review an opportunity'], ok: (c) => c.own || c.GF.market_view === true || c.GF.market_manage === true, also: ['campaigns'] }),
  rec('forecast', 'reports', ['পরিকল্পনা ও পূর্বাভাস', 'Planning & forecasts', 'Planning ও forecast'], { icon: 'biz', ok: (c) => c.own || c.P('POS', 'approve') || c.GF.view_reports === true || c.GF.report_sales === true || c.GF.report_stock === true || c.GF.report_cash === true, also: ['factory', 'purch', 'stock'],
    kw: ['forecast', 'demand', 'festival', 'scenario', 'what if', 'production requirement', 'cash calendar', 'expiry risk', 'পূর্বাভাস', 'চাহিদা', 'উৎসব', 'পরিকল্পনা'], verbs: ['forecast sales', 'plan production', 'see expected cash'] }),
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
  rec('owner', 'dash', ['মালিকের বোর্ড', 'Owner mode board', 'Owner mode board'], { icon: 'control', also: ['settings'], ok: owner, kw: ['owner', 'board', 'must check', 'daily check', 'morning', 'মালিক', 'বোর্ড', 'প্রতিদিন', 'দেখুন'] }),
  rec('connect', 'settings', ['সংযোগ কেন্দ্র', 'Connect Center', 'Connect Center'], { icon: 'settings', ok: owner, kw: ['connect', 'connection', 'integration', 'api key', 'secret', 'website', 'domain', 'facebook', 'whatsapp', 'sms', 'ai', 'সংযোগ', 'ডোমেইন', 'ওয়েবসাইট', 'সংযুক্ত'] }),
  rec('x1health', 'dash', ['স্বয়ংক্রিয় কাজ ও সংযোগের স্বাস্থ্য', 'Automation & integration health', 'Automation ও integration health'], { icon: 'check', ok: owner, kw: ['health', 'automation', 'job', 'status', 'stale', 'failed', 'স্বাস্থ্য', 'স্বয়ংক্রিয়', 'কাজ', 'অবস্থা'] }),
  rec('switchboard', 'settings', ['সুইচবোর্ড (সব চালু/বন্ধ)', 'Switchboard (all on/off)', 'Switchboard (সব on/off)'], { icon: 'settings', ok: owner, kw: ['switch', 'on off', 'toggle', 'blind', 'pin', 'flag', 'সুইচ', 'চালু', 'বন্ধ', 'অন', 'অফ', 'সেটিংস'] }),
  rec('parallel', 'settings', ['পাশাপাশি মাস: তুলনা ও পাস/ফেল', 'Parallel month: compare & pass/fail', 'Parallel মাস: compare ও pass/fail'], { icon: 'doc', ok: (c) => c.own || c.GF.rollout_manage === true, parent: 'rollout', kw: ['parallel', 'compare', 'pass', 'fail', 'paper', 'পাশাপাশি', 'তুলনা', 'পাস', 'ফেল'] }),
  rec('printbooks', 'settings', ['ছাপা ও বই', 'Print & books', 'Print ও books'], { icon: 'print', ok: (c) => c.own || c.GF.head_management === true || c.GF.print_books === true, kw: ['print', 'book', 'serial', 'paper', 'ছাপা', 'বই', 'সিরিয়াল'] }),
  rec('flow', 'sale', ['দিনের কাজ (ধাপে ধাপে)', 'Guided routines', 'দিনের কাজ (ধাপে ধাপে)'], { icon: 'check', ok: locOk, kw: ['open shop', 'close day', 'checklist', 'routine', 'month end', 'factory day', 'দোকান খোলা', 'দিন শেষ', 'মাস শেষ', 'ধাপ', 'চেকলিস্ট'] }),
  rec('delegation', 'settings', ['দায়িত্ব বণ্টন', 'Delegation board', 'Delegation board'], { icon: 'users', ok: owner, kw: ['delegate', 'grant', 'right', 'permission', 'who holds', 'দায়িত্ব', 'অধিকার', 'অনুমতি'] }),
  rec('returnrules', 'settings', ['Return & exit rules', 'Return & exit rules', 'Return & exit rules'], { icon: 'settings', ok: (c) => c.own || c.GF.employee_manage === true || c.GF.sale_return === true || c.GF.return_override === true, kw: ['return', 'sale return', 'restock', 'write off', 'return window', 'receipt', 'perishable', 'exit', 'resign', 'revoke login', 'leave', 'dismiss', 'staff exit', 'keep access'], verbs: ['set return rules', 'staff exit rules'] }),
  rec('accounts', 'acc', ['হিসাব ও খতিয়ান', 'Accounts & ledger', 'Accounts ও Ledger'], { icon: 'doc', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['accounts', 'ledger', 'journal', 'balance sheet', 'trial balance', 'profit', 'chart of accounts', 'হিসাব', 'খতিয়ান', 'জার্নাল', 'ব্যালান্স শিট'] }),
  rec('monthclose', 'acc', ['মাস শেষের হিসাব', 'Monthly Close', 'Monthly Close (মাস শেষ)'], { icon: 'book', ok: (c) => c.own || c.GF.accounts_manage === true, home: { acc: 11 }, kw: ['month close', 'monthly close', 'month end', 'salary accrual', 'accrued salary', 'payroll accrual', 'partner share', 'profit split', 'close the month', 'মাস শেষ', 'মাসিক ক্লোজ', 'বেতন জমা', 'মাসের হিসাব', 'অংশীদারের ভাগ'], verbs: ['mark the month reviewed', 'মাস দেখা হয়েছে চিহ্ন দিন', 'close the month'] }),
  rec('moneyaccounts', 'acc', ['Money Accounts', 'Money Accounts', 'Money Accounts'], { icon: 'money', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['money accounts', 'payment source', 'cash drawer', 'bank account', 'mobile wallet', 'wallet', 'bkash', 'nagad', 'rocket', 'transfer', 'deposit', 'default source', 'statement', 'account statement', 'negative balance', 'real balance', 'reconcile', 'exceptions', 'approver', 'bank charge', 'interest'], verbs: ['add money account', 'transfer between accounts', 'account statement', 'set payment source', 'choose approver'], aliases: ['payment sources', 'accounts of money'] }),
  rec('balancecheck', 'acc', ['হিসাব মেলানো (ব্যালান্স চেক)', 'Balance check', 'Balance check (হিসাব মেলানো)'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['balance check', 'books agree', 'trial balance', 'equation', 'assets liabilities equity', 'unbalanced', 'stock identity', 'red green', 'test reset', 'হিসাব মেলানো', 'ব্যালান্স চেক', 'মেলে না', 'ট্রায়াল ব্যালান্স'] }),
  rec('openparties', 'acc', ['Opening dues and payables', 'Opening dues and payables', 'Opening dues and payables'], { icon: 'dues', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['opening dues', 'opening balance', 'old dues', 'customer due', 'supplier payable', 'import dues', 'sub-ledger', 'party gate'] }),
  rec('periodlock', 'acc', ['Period lock', 'Period lock', 'Period lock'], { icon: 'book', ok: (c) => c.own || c.GF.accounts_manage === true, kw: ['period lock', 'lock books', 'close month', 'closed period', 'override', 'back date', 'late sale', 'offline sale', 'lock date', 'reopen'], verbs: ['lock the books', 'open an override window', 'set back-date limit', 'decide a held sale'] }),
  rec('moneycontrols', 'acc', ['Money controls', 'Money controls', 'Money controls'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true || c.GF.cash_move === true || c.GF.supplier_pay === true, kw: ['money controls', 'owner draw', 'bank slip', 'duplicate payment', 'control account', 'waiting for approver', 'exceptions', 'mapping type'] }),
  rec('otherincome', 'acc', ['Other income', 'Other income', 'Other income'], { icon: 'money', ok: (c) => c.own || c.GF.cash_move === true || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['other income', 'scrap', 'old oil', 'rent received', 'chart', 'expense heads'] }),
  rec('freshness', 'acc', ['Books freshness', 'Books freshness', 'Books freshness'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['books freshness', 'last posted', 'scheduled posting', 'journal', 'posted to books', 'books up to date'] }),
  rec('employees', 'acc', ['কর্মচারী', 'Employees', 'Employees'], { icon: 'users', ok: (c) => c.own || c.GF.employee_view === true || c.GF.employee_manage === true, kw: ['employee', 'staff', 'worker', 'register', 'salary', 'deed', 'photo', 'কর্মচারী', 'স্টাফ', 'কর্মী', 'নিবন্ধন', 'বেতন', 'ডিড'] }),
  rec('employees/new', 'acc', ['নতুন কর্মচারী নিবন্ধন', 'Register an employee', 'নতুন Employee নিবন্ধন'], { icon: 'plus', ok: (c) => c.own || c.GF.employee_manage === true, kw: ['new employee', 'add staff', 'registration', 'নতুন কর্মচারী', 'নিবন্ধন'] }),
  rec('deeds', 'acc', ['ডিড ও চুক্তি', 'Deeds & agreements', 'Deed ও চুক্তি'], { icon: 'doc', ok: (c) => c.own || c.GF.deed_manage === true || c.GF.employee_manage === true, kw: ['deed', 'agreement', 'contract', 'guarantor', 'security deposit', 'ডিড', 'চুক্তি', 'জামিন', 'জামানত'] }),
  rec('attendance', 'people', ['হাজিরা', 'Attendance', 'Attendance'], { icon: 'check', ok: (c) => c.own || c.GF.attendance_manage === true || c.GF.employee_view === true || c.GF.employee_manage === true, kw: ['attendance', 'present', 'absent', 'late', 'overtime', 'fingerprint', 'device', 'punch', 'shift', 'holiday', 'হাজিরা', 'উপস্থিত', 'অনুপস্থিত', 'দেরি', 'ওভারটাইম', 'ফিঙ্গারপ্রিন্ট', 'শিফট', 'ছুটির দিন'] }),
  rec('leave', 'people', ['ছুটি', 'Leave', 'Leave'], { icon: 'doc', ok: (c) => c.own || c.GF.attendance_manage === true || c.GF.employee_view === true, kw: ['leave', 'holiday request', 'sick', 'casual', 'balance', 'ছুটি', 'অসুস্থ', 'নৈমিত্তিক', 'ছুটির আবেদন'] }),
  // R2 (docs/integration/R2.md): announcements, to-do list, shift schedule. Each is offered only while its owner switch is ON; who may post / assign / schedule is a grant the server checks.
  rec('announce', 'people', ['ঘোষণা ও নির্দেশ', 'Announcements', 'Announcements (ঘোষণা)'], { icon: 'doc', ok: (c) => ruleOn('announce_on'), kw: ['announcement', 'notice', 'instruction', 'message to staff', 'headline', 'ticker', 'broadcast', 'seen', 'read receipt', 'ঘোষণা', 'নির্দেশ', 'নোটিশ', 'বার্তা', 'জরুরি'], verbs: ['post an announcement', 'ঘোষণা দিন'] }),
  // XC (docs/integration/XC.md): unsold stock and markdown; owner summary recipients. Main features are always visible at their place; their own switches default OFF and the server decides every call.
  rec('xcunsold', 'stock', 't:xc_unsold_title', { icon: 'items', ok: (c) => c.own || c.canPos(), kw: ['unsold', 'markdown', 'expiry', 'expire', 'end of day', 'leftover', 'discount', 'বিক্রি না হওয়া', 'ছাড়', 'মেয়াদ', 'বাকি মাল'] }),
  rec('xcsummary', 'settings', 't:xc_sum_title', { icon: 'settings', ok: (c) => c.own, kw: ['owner summary', 'daily summary', 'recipient', 'send history', 'summary email', 'telegram', 'সারাংশ', 'প্রাপক', 'ইতিহাস'] }),
  // XB (docs/integration/XB.md): mobile payment capture, custom cake jobs, riders and COD. Main features are always visible at their place; their switches default OFF and the server decides every call.
  rec('paycapture', 'acc', 't:xb_pay_title', { icon: 'money', ok: (c) => c.own || c.canPos(), kw: ['bkash', 'nagad', 'rocket', 'trx', 'transaction', 'mobile payment', 'verify', 'বিকাশ', 'নগদ', 'রকেট', 'মোবাইল পেমেন্ট', 'Trx', 'যাচাই'] }),
  rec('cakejobs', 'cust', 't:xb_cake_title', { icon: 'doc', ok: (c) => c.own || c.canPos(), kw: ['cake', 'custom cake', 'due tomorrow', 'cake job', 'কেক', 'কাস্টম কেক', 'কাল যাবে'] }),
  rec('riders', 'cust', 't:xb_rd_title', { icon: 'doc', ok: (c) => c.own || c.canPos(), kw: ['rider', 'delivery', 'cod', 'cash on delivery', 'courier', 'রাইডার', 'ডেলিভারি', 'COD', 'ক্যাশ'] }),
  rec('todo', 'people', ['করণীয় তালিকা', 'To-do list', 'To-do list (করণীয়)'], { icon: 'check', ok: (c) => ruleOn('todo_on'), kw: ['to-do', 'todo', 'task', 'duty', 'extra work', 'assign', 'overdue', 'repeat', 'করণীয়', 'কাজ', 'দায়িত্ব', 'অতিরিক্ত কাজ', 'দেরি'], verbs: ['give a task', 'my tasks', 'কাজ দিন'] }),
  rec('shifts', 'people', ['শিফট রোস্টার', 'Shift schedule', 'Shift roster'], { icon: 'check', ok: (c) => ruleOn('shift_on'), kw: ['shift', 'roster', 'schedule', 'duty', 'off day', 'swap', 'rota', 'who is on', 'শিফট', 'রোস্টার', 'ডিউটি', 'অফ ডে', 'ছুটি', 'কে ডিউটিতে'], verbs: ['my shifts', 'set the roster', 'আমার শিফট'] }),
  rec('payroll', 'people', ['বেতন শিট', 'Payroll', 'Payroll'], { icon: 'money', ok: (c) => c.own || c.GF.payroll_manage === true || c.GF.salary_view === true, home: { acc: 10 }, kw: ['payroll', 'salary', 'payslip', 'wage', 'bonus', 'advance', 'settlement', 'বেতন', 'বেতন শিট', 'পে-স্লিপ', 'বোনাস', 'অগ্রিম', 'মজুরি'] }),
  rec('payrequest', 'people', ['বেতন / অগ্রিমের অনুরোধ', 'Ask for salary or advance', 'বেতন / Advance চাওয়া'], { icon: 'money', kw: ['salary request', 'advance request', 'ask for advance', 'ask for salary', 'need money', 'pay request', 'অগ্রিম চাওয়া', 'বেতন চাওয়া', 'অনুরোধ', 'টাকা লাগবে'], verbs: ['ask for advance', 'ask for salary', 'অগ্রিম চাই', 'বেতন চাই'] }),
  rec('partyrequest', 'purch', ['সরবরাহকারীকে টাকা দেওয়ার অনুরোধ', 'Ask to pay a supplier', 'Supplier payment request'], { icon: 'dues', ok: locOk, kw: ['supplier payment request', 'pay supplier request', 'request to pay', 'due request', 'সরবরাহকারী', 'পেমেন্টের অনুরোধ', 'বাকি পরিশোধ'], verbs: ['ask to pay supplier', 'supplier payment request'] }),
  rec('payapprovals', 'appr', ['টাকা দেওয়ার অনুরোধ - সিদ্ধান্ত', 'Pay requests to decide', 'Pay request - সিদ্ধান্ত'], { icon: 'check', ok: (c) => c.own || c.anyApprove() || !!(window.BOS.payRequests && window.BOS.payRequests.approver), cnt: 'prq', tone: 'info', kw: ['pay request', 'approve advance', 'approve salary', 'due today', 'pay date', 'অনুরোধ', 'অগ্রিম অনুমোদন', 'আজ দেওয়ার'], verbs: ['approve pay request', 'due today list'] }),
  rec('payreqsettings', 'settings', ['অনুরোধের সিদ্ধান্তদাতা ও নিয়ম', 'Pay request settings', 'Pay request settings'], { icon: 'settings', ok: owner, parent: 'payapprovals', kw: ['pay request settings', 'who decides', 'verbal request policy', 'advance ceiling', 'request limit', 'সিদ্ধান্তদাতা', 'মুখের কথা'] }),
  rec('crmleads', 'cust', ['Party and gift enquiries', 'Party and gift enquiries', 'Party and gift enquiries'], { icon: 'doc', ok: (c) => c.own || c.GF.crm_lead_manage === true || c.GF.crm_lead_all === true || c.canPos(), kw: ['enquiry', 'enquiries', 'lead', 'quote', 'quotation', 'party order', 'wholesale', 'corporate', 'gift box', 'hamper', 'follow up', 'won', 'lost', 'pipeline'], verbs: ['new enquiry', 'send a quote', 'follow up an enquiry'] }),
  rec('crmtasks', 'cust', ['My tasks', 'My tasks', 'My tasks'], { icon: 'doc', kw: ['task', 'tasks', 'to do', 'reminder', 'follow up', 'overdue', 'snooze'], verbs: ['see my tasks', 'add a task'] }),
  rec('customers', 'cust', ['গ্রাহক তালিকা ও স্তর', 'Customers & tiers', 'Customer list ও Tier'], { icon: 'users', ok: pos, mob: 3, kw: ['customer', 'tier', 'gold', 'elite', 'walk-in', 'regular', 'loyalty', 'points', 'gift', 'birthday', 'গ্রাহক', 'কাস্টমার', 'স্তর', 'গোল্ড', 'এলিট', 'উপহার', 'পয়েন্ট', 'জন্মদিন'] }),
  rec('bankreceipt', 'cust', ['Bank & cheque receipts', 'Bank & cheque receipts', 'Bank & cheque receipts'], { icon: 'money', ok: pos, kw: ['bank receipt', 'cheque', 'bank transfer', 'customer payment'] }),
  rec('crm360', 'cust', ['Customer 360', 'Customer 360', 'Customer 360'], { icon: 'users', ok: pos, drawer: false, kw: ['customer 360', 'customer profile', 'customer history', 'timeline', 'favourite items', 'birthday', 'family date', 'delivery point', 'extra phone', 'tags', 'language'] }),
  rec('crmconsent', 'cust', ['Customer consent and privacy', 'Customer consent and privacy', 'Customer consent and privacy'], { icon: 'lock', ok: (c) => c.own || c.canPos() || c.GF.customer_manage === true, kw: ['consent', 'opt in', 'opt out', 'do not contact', 'sms', 'whatsapp', 'privacy', 'phone number', 'hide', 'export', 'access log', 'paper list', 'messages'] }),
  rec('crmdupes', 'cust', ['Duplicate customers', 'Duplicate customers', 'Duplicate customers'], { icon: 'users', ok: (c) => c.own || c.GF.customer_manage === true || c.GF.crm_merge === true, kw: ['duplicate', 'same person', 'merge', 'link', 'second number', 'double customer'] }),
  rec('crmlists', 'cust', ['Customer lists', 'Customer lists', 'Customer lists'], { icon: 'users', ok: (c) => c.own || c.GF.crm_view === true || c.GF.crm_settings_edit === true || c.GF.customer_manage === true, kw: ['customer list', 'segment', 'saved list', 'not seen', 'lapsed', 'birthday', 'high spender', 'by outlet', 'by tier', 'bought item', 'audience'], verbs: ['make a customer list', 'count customers'] }),
  rec('crmvalue', 'cust', ['Customer value', 'Customer value', 'Customer value'], { icon: 'users', ok: (c) => c.own || c.GF.crm_view === true || c.GF.crm_settings_edit === true || c.GF.customer_manage === true, kw: ['rfm', 'lifetime value', 'repeat rate', 'repeat customers', 'champion', 'at risk', 'lapsed customers', 'best customers', 'customer profit', 'churn'], verbs: ['see best customers', 'see lapsed customers'] }),
  rec('crmfeedback', 'cust', ['Feedback and complaints', 'Feedback and complaints', 'Feedback and complaints'], { icon: 'users', ok: (c) => c.own || c.GF.crm_complaint_log === true || c.GF.crm_complaint_manage === true || c.GF.crm_feedback_view === true || c.canPos(), kw: ['complaint', 'feedback', 'rating', 'stars', 'review', 'food safety', 'overdue complaint', 'customer complaint', 'unhappy customer', 'refund complaint', 'repeat complaint'] }),
  rec('crmloyalty', 'cust', ['Loyalty extras', 'Loyalty extras', 'Loyalty extras'], { icon: 'users', ok: (c) => c.own || c.GF.customer_manage === true || c.GF.crm_loyalty_manage === true, kw: ['loyalty', 'points', 'expiry', 'expire', 'referral', 'birthday bonus', 'anniversary', 'festival', 'points statement', 'loyalty summary'], verbs: ['expire points', 'see points statement'] }),
  rec('crmcoupons', 'cust', ['Coupons & vouchers', 'Coupons & vouchers', 'Coupons & vouchers'], { icon: 'settings', ok: (c) => c.own || c.GF.customer_manage === true || c.GF.crm_loyalty_manage === true || c.GF.crm_voucher_issue === true || c.GF.crm_coupon_override === true, kw: ['coupon', 'voucher', 'discount code', 'promo', 'offer', 'redemption', 'liability'], verbs: ['make a coupon', 'check a coupon'] }),
  rec('tiers', 'cust', ['গ্রাহকের স্তর ও সুবিধা', 'Customer tiers & benefits', 'Customer tier ও সুবিধা'], { icon: 'settings', ok: owner, kw: ['tier', 'discount', 'gift', 'loyalty', 'points', 'auto upgrade', 'স্তর', 'ডিসকাউন্ট', 'উপহার', 'লয়্যালটি', 'পয়েন্ট'] }),
  rec('partners', 'settings', ['অংশীদারি ও বিনিয়োগ', 'Partners & investment', 'অংশীদারি ও Investment'], { icon: 'money', ok: (c) => c.own, kw: ['partner', 'partnership', 'investor', 'investment', 'franchise', 'royalty', 'profit share', 'profit sharing', 'deed', 'agreement', 'capital', 'loan', 'settlement', 'অংশীদার', 'বিনিয়োগ', 'ফ্র্যাঞ্চাইজ', 'রয়্যালটি', 'লাভ ভাগ', 'চুক্তি', 'পুঁজি', 'দলিল'] }),
  rec('notifications', 'appr', ['নোটিফিকেশন', 'Notifications', 'Notification'], { icon: 'doc', kw: ['notification', 'alert', 'bell', 'urgent', 'backup', 'warning', 'নোটিফিকেশন', 'সতর্কতা', 'ঘণ্টা', 'ব্যাকআপ'] }),
  rec('assistant', 'reports', ['প্রশ্ন করুন (সহকারী)', 'Ask (assistant)', 'Ask (সহকারী)'], { icon: 'doc', ok: (c) => c.own || c.GF.assistant_use === true, kw: ['ask', 'assistant', 'question', 'help', 'ai', 'chat', 'how much', 'why', 'প্রশ্ন', 'সহকারী', 'জিজ্ঞেস', 'সাহায্য', 'কত', 'কেন', 'হিসাব'] }),
  rec('rules', 'settings', 't:rules', { ok: owner, kw: ['form rule', 'count first', 'red block', 'ফর্মের নিয়ম'] }),
  rec('settings', 'settings', 't:settings', { ok: owner, kw: ['settings', 'config', 'সেটিংস'] }),
  rec('camrec', 'settings', ['ক্যামেরা ও স্ক্যান', 'Camera & Recognition', 'Camera & Recognition'], { icon: 'settings', ok: owner, kw: ['camera', 'scan', 'barcode', 'ocr', 'label', 'photo match', 'recognition', 'ক্যামেরা', 'স্ক্যান', 'বারকোড', 'লেখা পড়া', 'ছবি মেলানো'], verbs: ['test scanner', 'check camera'] }),
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
  'purchase/return': 'swap', payables: 'money', recipes: 'chef', pos: 'pos', salereturn: 'swap', dues: 'dues', invoice: 'print', daybook: 'book', cashmoves: 'money', parallel: 'swap', flow: 'check', delegation: 'users', accounts: 'book', employees: 'users', 'employees/new': 'plus', deeds: 'doc', attendance: 'check', announce: 'bell', todo: 'check', shifts: 'calendar', leave: 'calendar', payroll: 'money', customers: 'users', tiers: 'star', notifications: 'bell', partners: 'money', assistant: 'info', printbooks: 'print', switchboard: 'settings', ledgerlinks: 'link', exceptions: 'warn', pending: 'stamp', itemreq: 'swap', releases: 'unlock',
  emergency: 'alert', changes: 'edit', numaudit: 'hash', outbox: 'upload', reports: 'chart', biz: 'pie', brandpnl: 'pie', discounts: 'tag', staff: 'users', matrix: 'matrix', salary: 'money', locations: 'pin', locset: 'pinset', locsheet: 'pinset',
  'purchase/return': 'swap', payables: 'money', recipes: 'chef', pos: 'pos', salereturn: 'swap', dues: 'dues', invoice: 'print', daybook: 'book', cashmoves: 'money', parallel: 'swap', flow: 'check', delegation: 'users', accounts: 'book', employees: 'users', 'employees/new': 'plus', deeds: 'doc', attendance: 'check', leave: 'calendar', payroll: 'money', customers: 'users', tiers: 'star', notifications: 'bell', partners: 'money', assistant: 'info', printbooks: 'print', switchboard: 'settings', ledgerlinks: 'link', exceptions: 'warn', pending: 'stamp', itemreq: 'swap', releases: 'unlock',
  emergency: 'alert', changes: 'edit', numaudit: 'hash', outbox: 'upload', reports: 'chart', biz: 'pie', brandpnl: 'pie', discounts: 'tag', campaigns: 'chart', couponuse: 'tag', auditreports: 'history', forecast: 'pie', staff: 'users', matrix: 'matrix', salary: 'money', locations: 'pin', locset: 'pinset', locsheet: 'pinset',
  rollout: 'sliders', control: 'sliders', rulehub: 'shield', owner: 'sliders', rules: 'rules', settings: 'gear', settings2: 'sliders', logs: 'history', backup: 'download', home: 'home' };
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
