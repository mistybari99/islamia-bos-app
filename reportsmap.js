/* Islamia BOS · Reports map (#/reports/map): the 14 sections of the report master list, one row per report, a status badge and ONE link per report to the route that already exists.
   STATIC REGISTRY, not live data: the statuses come from the audits in docs/REPORTS_AUDIT_*.md (section 1 to 4 from docs/REPORTS_AUDIT_1.md) and from the packages built since (docs/integration/RPT-B1.md).
   Nothing here decides who may see a report: a link opens the report page and the server answers (a person without the right sees the lock text there). The map only greys the link when it already knows.

   HOW TO EXTEND (sections 5 to 14 are placeholders until their audit exists):
     * edit REGISTRY below (one object per section, one row per report), or
     * from another script loaded after this one:   BOS.reportsMap.extend([{ id: 5, title: [bn, en, mix], reports: [ ...rows... ] }])   (a section with the same id is replaced)
     * or set window.BOS_REPORT_MAP_EXT = [ ...sections ] before this file loads.
   A row:  { n: 11, name: [bn, en, mix], status: 'implemented'|'incomplete'|'unavailable'|'unverified', route: 'report/sales_summary' | 'costing' | null,
             group: '<one of the 13 ia.js groups, the audit "Report placement">', note: [bn, en, mix] (optional: what changed / what is still open), needs: [bn, en, mix] (optional: the form or field that is missing), pkg: 'R3' (optional: the package that will build it), more: [route, ...] (optional) }
   route 'report/<key>' = a report of the report hub (#/report/<key>); any other value = a page registered in web/ia.js. route null = nothing to open yet (status unavailable): the row says what is needed.
   Text: [বাংলা, English, Mix] like web/ia.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const uid = () => (S.ctx && S.ctx.profile && S.ctx.profile.id) || 'anon';

const STATUS = ['implemented', 'incomplete', 'unavailable', 'unverified'];
const X = {
  title: L('রিপোর্ট মানচিত্র', 'Reports map', 'Report map'),
  intro: L('রিপোর্টের মাস্টার তালিকার ১৪টি বিভাগ। প্রতিটি রিপোর্টের অবস্থা ও খোলার লিংক। এটি একটি স্থির তালিকা (অডিট থেকে), সরাসরি ডেটা নয়।', 'The 14 sections of the report master list: the state of every report and one link to open it. This is a fixed list (from the audits), not live data.', 'Report master list-এর ১৪টি section: প্রতিটি report-এর অবস্থা ও খোলার link। এটি fixed list (audit থেকে), live data নয়।'),
  all: L('সব', 'All', 'All'), search: L('রিপোর্ট খুঁজুন…', 'Search reports…', 'Report খুঁজুন…'),
  implemented: L('চালু', 'Implemented', 'Implemented'), incomplete: L('অসম্পূর্ণ', 'Incomplete', 'Incomplete'), unavailable: L('নেই', 'Unavailable', 'Unavailable'), unverified: L('যাচাই বাকি', 'Unverified', 'Unverified'),
  pending: L('অডিট বাকি', 'Not audited yet', 'Audit বাকি'),
  pendingText: L('এই বিভাগের অডিট এখনও হয়নি। হলে এখানে রিপোর্টগুলো বসবে।', 'This section has not been audited yet. Its reports will be listed here after the audit.', 'এই section-এর audit এখনও হয়নি। হলে report-গুলো এখানে বসবে।'),
  open: L('খুলুন', 'Open', 'Open'), locked: L('অনুমতি নেই', 'Not allowed', 'Permission নেই'), none: L('কিছু পাওয়া যায়নি', 'Nothing found', 'কিছু পাওয়া যায়নি'),
  needs: L('দরকার', 'Needed', 'দরকার'), nobuild: L('এখনও তৈরি হয়নি', 'Not built yet', 'এখনও তৈরি হয়নি'), pkg: L('পরিকল্পনা', 'Planned', 'Planned'),
  count: L('টি রিপোর্ট', 'reports', 'reports'), csv: L('CSV', 'CSV', 'CSV'), csvDone: L('ফাইল তৈরি', 'File ready', 'File তৈরি'),
  hub: L('সব রিপোর্টের তালিকা', 'All reports (hub)', 'সব Report (hub)'), static: L('স্থির তালিকা', 'Static list', 'Static list'),
  secH: L('বিভাগ', 'Section', 'Section'), repH: L('রিপোর্ট', 'Report', 'Report'), stH: L('অবস্থা', 'Status', 'Status'), grpH: L('মেনু গ্রুপ', 'Menu group', 'Menu group'), rtH: L('রুট', 'Route', 'Route'),
  noteH: L('নোট', 'Note', 'Note'), needH: L('দরকার', 'Needed', 'Needed'), numH: L('নং', 'No.', 'No.'),
  extra: L('মাস্টার তালিকার বাইরে (মিষ্টির ব্যবসার জন্য)', 'Beyond the master list (for a sweets business)', 'Master list-এর বাইরে (মিষ্টির ব্যবসার জন্য)'),
};
const T = (k) => lab(X[k]);
const tx = (a) => (a ? lab(L(a[0], a[1], a[2] || a[0])) : '');

// ---------- the registry (sections 1 to 4: docs/REPORTS_AUDIT_1.md; 5 to 14: to be filled) ----------
const R = (n, bn, en, mix, status, route, group, o) => Object.assign({ n, name: [bn, en, mix], status, route, group }, o || {});
const N = (bn, en, mix) => [bn, en, mix || bn];
const REGISTRY = [
  { id: 1, title: N('নির্বাহী সারসংক্ষেপ', 'Executive', 'Executive সারসংক্ষেপ'), reports: [
    R(1, 'নির্বাহী ড্যাশবোর্ড', 'Executive dashboard', 'Executive dashboard', 'incomplete', 'home', 'dash', { more: ['owner', 'biz'], needs: N('আউটলেট/ব্র্যান্ড তুলনা, লাভ, উৎপাদন ও লক্ষ্যের টাইল নেই', 'Missing: outlet / brand comparison, profit, production and target tiles') }),
    R(2, 'দৈনিক ব্যবসার সারসংক্ষেপ', 'Daily business summary', 'Daily business summary', 'implemented', 'report/pos_day_close', 'sale', { note: N('ফেরত দেওয়া ক্যাশ ও ফেরতের পর ড্রয়ারের ক্যাশ যোগ হয়েছে (phase 400)', 'Cash handed back and the drawer cash after refunds added (phase 400)') }),
    R(3, 'মাসিক ব্যবসার সারসংক্ষেপ', 'Monthly business summary', 'Monthly business summary', 'incomplete', 'report/l1_pnl', 'acc', { more: ['monthclose'], note: N('লাভে ধরা নেই এমন ক্ষতি gaps কলামে ও নোটে নাম ধরে দেখানো হয় (phase 401)', 'Losses left out of the profit are named in the gaps column and a note (phase 401)'), needs: N('খরচ শুধু ১০-২ ভাউচার থেকে আসে', 'Expenses come only from 10-2 vouchers') }),
    R(4, 'বিক্রি, গ্রস ও নিট লাভের সারসংক্ষেপ', 'Sales, gross and net profit overview', 'Sales, gross ও net profit overview', 'incomplete', 'biz', 'acc', { more: ['report/l1_pnl', 'profitcheck'], needs: N('বেতন/খরচ/স্থির খরচ না থাকলে লাভ অসম্পূর্ণ; খরচহীন বিক্রি আলাদা দেখানো হয়', 'Profit is partial while salary / expenses / fixed cost are blank; sales with unknown cost are shown apart') }),
    R(5, 'আউটলেট তুলনা', 'Outlet comparison', 'Outlet comparison', 'implemented', 'report/l3_shop_pnl', 'dash', { more: ['report/sales_combined'] }),
    R(6, 'ব্র্যান্ড তুলনা', 'Brand comparison', 'Brand comparison', 'implemented', 'brandpnl', 'dash', { more: ['report/sales_combined'] }),
    R(7, 'কারখানা বনাম খুচরা', 'Factory vs retail', 'Factory vs retail', 'unavailable', null, 'dash', { pkg: 'R9', needs: N('ইউনিটের মধ্যে চালানের মূল্য ও কারখানার খরচ-কেন্দ্রের ফল', 'Inter-unit transfer valuation and a factory cost-centre result') }),
    R(8, 'বাজেট বনাম বাস্তব', 'Budget vs actual', 'Budget vs actual', 'unverified', 'finance2', 'acc', { needs: N('বাজেট চালু ও বাজেট লেখা থাকলে তবেই যাচাই করা যায়', 'Can be checked only when budgets are on and entered') }),
    R(9, 'লক্ষ্য বনাম অর্জন', 'Target vs achievement', 'Target vs achievement', 'unavailable', null, 'dash', { pkg: 'R5', needs: N('আউটলেট ও মাস অনুযায়ী বিক্রির লক্ষ্য লেখার ঘর', 'A place to enter the sales target per outlet and month') }),
    R(10, 'KPI ধারা ও ব্যতিক্রম সতর্কতা', 'KPI trends and exception alerts', 'KPI trends ও exception alerts', 'incomplete', 'owner', 'dash', { more: ['report/x5_staff_trend'], needs: N('দৈনিক KPI ইতিহাস রাখা হয় না', 'No daily KPI history is stored') }),
  ] },
  { id: 2, title: N('বিক্রি ও POS', 'Sales and POS', 'Sales ও POS'), reports: [
    R(11, 'বিক্রির সারসংক্ষেপ', 'Sales summary', 'Sales সারসংক্ষেপ', 'implemented', 'report/sales_summary', 'sale', { note: N('ফেরত ও ফেরত বাদে বিক্রি কলাম যোগ হয়েছে (phase 400)', 'Returns and sales-after-returns columns added (phase 400)') }),
    R(12, 'ধারা ও সময় তুলনা', 'Trend and period comparison', 'Trend ও period comparison', 'implemented', 'report/sales_trend', 'sale', { note: N('ফেরত বাদে বিক্রি কলাম যোগ হয়েছে (phase 400)', 'Sales-after-returns column added (phase 400)') }),
    R(13, 'আউটলেট/ব্র্যান্ড অনুযায়ী বিক্রি', 'Sales by outlet / brand', 'Sales by outlet / brand', 'implemented', 'report/sales_combined', 'sale', { more: ['brandpnl'] }),
    R(14, 'আইটেম অনুযায়ী বিক্রি', 'Item-wise sales', 'Item-wise sales', 'implemented', 'report/item_sales', 'sale', { note: N('ফেরত কলাম ও সেটিং "Report cost basis" (phase 400, 402)', 'Returns columns and the setting "Report cost basis" (phases 400, 402)') }),
    R(15, 'ক্যাটাগরি অনুযায়ী বিক্রি', 'Category-wise sales', 'Category-wise sales', 'implemented', 'report/category_sales', 'sale'),
    R(16, 'ঘণ্টা ও বার অনুযায়ী বিক্রি', 'Sales by hour and weekday', 'Sales by hour ও weekday', 'implemented', 'report/hour_weekday', 'sale'),
    R(17, 'খুচরা বনাম পাইকারি', 'Retail vs wholesale', 'Retail vs wholesale', 'implemented', 'report/retail_wholesale', 'sale'),
    R(18, 'রসিদ / ইনভয়েস তালিকা', 'Receipt / invoice register', 'Receipt / invoice register', 'implemented', 'report/receipt_register', 'sale'),
    R(19, 'পেমেন্ট মাধ্যম', 'Payment method', 'Payment method', 'implemented', 'report/payment_modes', 'sale', { more: ['report/wallet_recon', 'report/collections'], note: N('মাধ্যম অনুযায়ী ফেরতে দেওয়া টাকা যোগ হয়েছে (phase 400)', 'Refund payout by payment mode added (phase 400)') }),
    R(20, 'ডিসকাউন্ট ও দাম বদল', 'Discounts and price overrides', 'Discounts ও price overrides', 'incomplete', 'report/discounts', 'sale', { more: ['discounts'], needs: N('বিক্রির সময়ের তালিকা-দাম রাখা হয় না, তাই দাম বদলের টাকা বের হয় না', 'The list price at the time of sale is not stored, so the value of a price override cannot be shown') }),
    R(21, 'বাতিল, ফেরত ও রিটার্ন', 'Voids, refunds, returns', 'Voids, refunds, returns', 'implemented', 'report/voids', 'sale', { more: ['report/q3_complaints', 'salereturn'] }),
    R(22, 'কুইক ও তালিকা-বহির্ভূত বিক্রি', 'Quick / unlisted sales', 'Quick / unlisted sales', 'implemented', 'report/quick_unlisted', 'sale'),
    R(23, 'গড় বিল ও বিলে আইটেম', 'Average ticket and items per bill', 'Average ticket ও items per bill', 'incomplete', 'report/sales_summary', 'sale', { needs: N('বিলে আইটেমের সংখ্যা কলাম নেই (গড় বিল আছে)', 'Items per bill is missing (average bill exists)') }),
    R(24, 'আউটলেট অনুযায়ী বিক্রির লক্ষ্য', 'Sales target by outlet', 'Sales target by outlet', 'unavailable', null, 'sale', { pkg: 'R5', needs: N('নং ৯-এর মতোই লক্ষ্য লেখার ঘর', 'The same target entry as report 9') }),
    R(25, 'সেরা / কম / কমতি পণ্য', 'Top / low / declining products', 'Top / low / declining products', 'implemented', 'report/item_sales', 'sale', { more: ['report/item_slow'] }),
    R(26, 'বিক্রয়কর্মী / ক্যাশিয়ার অনুযায়ী বিক্রি', 'Sales by salesperson / cashier', 'Sales by salesperson / cashier', 'implemented', 'report/sales_summary', 'sale', { more: ['report/x5_staff_trend'] }),
    R(27, 'বিক্রির চ্যানেল বিশ্লেষণ', 'Sales channel analysis', 'Sales channel analysis', 'incomplete', 'report/s10_orders', 'sale', { needs: N('POS ও অনলাইন বিক্রি চ্যানেল অনুযায়ী ভাগ করা নেই (শুধু ২০-১ কাগজের অর্ডার)', 'POS and online sales are not grouped by channel (only the 20-1 paper orders)') }),
    R(28, 'ফেরত ও রিফান্ডের কারণ', 'Returns and refund reasons', 'Returns ও refund reasons', 'implemented', 'report/q3_complaints', 'sale'),
  ] },
  { id: 3, title: N('পণ্যের লাভজনকতা', 'Product profitability', 'Product profitability'), reports: [
    R(29, 'আইটেম অনুযায়ী লাভ ও মার্জিন', 'GP and margin by item', 'GP ও margin by item', 'implemented', 'report/l2_margin', 'reports'),
    R(30, 'ক্যাটাগরি অনুযায়ী লাভ', 'Profitability by category', 'Profitability by category', 'implemented', 'report/l2_margin', 'reports'),
    R(31, 'আউটলেট অনুযায়ী লাভ', 'Profitability by outlet', 'Profitability by outlet', 'implemented', 'report/l3_shop_pnl', 'reports', { more: ['report/l1_pnl'], note: N('ক্ষতি লাভে ধরা না থাকলে নাম ধরে দেখানো হয় (phase 401)', 'Losses left out of the profit are named (phase 401)') }),
    R(32, 'বিক্রয়মূল্য বনাম বর্তমান খরচ', 'Selling price vs current cost', 'Selling price vs current cost', 'incomplete', 'items', 'reports', { needs: N('সব বিক্রয়যোগ্য আইটেমের দাম, বর্তমান খরচ ও মার্জিনের একটি তালিকা', 'One list of every sellable item with price, current cost and margin %') }),
    R(33, 'স্ট্যান্ডার্ড বনাম আসল খরচের পার্থক্য', 'Standard vs actual cost variance', 'Standard vs actual cost variance', 'incomplete', 'costing', 'reports', { pkg: 'R3', note: N('"আসল" না থাকলে এখন "ধরা হয়নি" দেখায় (phase 401)', '"Actual" now says "not captured" when it is only the standard (phase 401)'), needs: N('উৎপাদন পোস্টে আসল ফলন লেখার ঘর', 'The actual yield field of production posting') }),
    R(34, 'পণ্য অনুযায়ী কন্ট্রিবিউশন লাভ', 'Contribution profit by product', 'Contribution profit by product', 'implemented', 'report/l2_margin', 'reports'),
    R(35, 'পণ্যের লাভের র‍্যাংকিং', 'Product profitability ranking', 'Product profitability ranking', 'implemented', 'report/l2_margin', 'reports', { more: ['biz'] }),
    R(36, 'দাম বদলের ইতিহাস ও প্রভাব', 'Price change history and impact', 'Price change history ও impact', 'incomplete', 'items', 'item', { pkg: 'R6', needs: N('দাম বদলের আগে-পরের প্রভাব রিপোর্ট নেই', 'No before / after impact report') }),
    R(37, 'লাভে ডিসকাউন্টের প্রভাব', 'Discount impact on profit', 'Discount impact on profit', 'implemented', 'report/item_sales', 'reports', { more: ['report/discounts'] }),
    R(38, 'কম মার্জিন ও লোকসানি পণ্য', 'Low-margin and loss-making products', 'Low-margin ও loss-making products', 'incomplete', 'report/l2_margin', 'reports', { pkg: 'R6', needs: N('মালিকের সেটিং low_margin_pct ও একটি চিহ্ন কলাম', 'An owner setting low_margin_pct and a flag column') }),
    R(39, 'বিক্রি বনাম লাভের ম্যাট্রিক্স', 'Portfolio: high sales vs high profit', 'Portfolio: high sales vs high profit', 'incomplete', 'biz', 'reports', { pkg: 'R6', needs: N('লাভের সাথে মিলিয়ে ২ অক্ষের শ্রেণি (এখন শুধু বিক্রির ABC)', 'A 2-axis class with profit (today only the sales ABC)') }),
  ] },
  { id: 4, title: N('উৎপাদন', 'Production', 'Production'), reports: [
    R(40, 'পরিকল্পনা বনাম আসল উৎপাদন', 'Plan vs actual', 'Plan vs actual', 'unavailable', null, 'factory', { pkg: 'R3', needs: N('উৎপাদন পরিকল্পনা (তারিখ, আউটলেট, আইটেম, ব্যাচ) লেখার ঘর', 'A production plan (date, outlet, item, batches) entry') }),
    R(41, 'ব্যাচ তালিকা', 'Batch register', 'Batch register', 'implemented', 'report/f1_production', 'factory', { more: ['costing'] }),
    R(42, 'রেসিপি / BOM খরচ', 'Recipe / BOM costing', 'Recipe / BOM costing', 'implemented', 'costing', 'factory', { more: ['recipebook'] }),
    R(43, 'স্ট্যান্ডার্ড বনাম আসল উৎপাদন খরচ', 'Standard vs actual manufacturing cost', 'Standard vs actual manufacturing cost', 'incomplete', 'costing', 'factory', { pkg: 'R3', note: N('রূপান্তর খরচ না ধরা থাকলে "ধরা হয়নি" ও CSV যোগ হয়েছে (phase 401)', '"Not captured" for an uncosted conversion and a CSV added (phase 401)'), needs: N('আসল ফলন ও আসল উপকরণ ইস্যু', 'Actual yield and actual material issue') }),
    R(44, 'রেসিপি অনুযায়ী কাঁচামালের ব্যবহার', 'Raw material use vs recipe', 'Raw material use vs recipe', 'unavailable', 'report/f3_raw_vs_recipe', 'stock', { pkg: 'R3', note: N('আর "০.০০%" দেখায় না; "ধরা হয়নি" ও কী দরকার তা দেখায় (phase 401)', 'No longer shows a false 0.00 %; says "not captured" and what is needed (phase 401)'), needs: N('প্রতি ব্যাচের আসল ইস্যু (ইস্যু স্লিপ ০৪-২ বা আসল-ব্যবহার ঘর)', 'The real issue of each batch (issue slip 04-2 or an actual-use field)') }),
    R(45, 'স্ট্যান্ডার্ডের তুলনায় ফলন', 'Yield vs standard', 'Yield vs standard', 'incomplete', 'report/f2_yield', 'factory', { pkg: 'R3', needs: N('ব্যাচ অনুযায়ী আসল ফলন', 'Run-level actual yield') }),
    R(46, 'ব্যাচ অনুযায়ী উৎপাদন খরচ', 'Batch-wise production cost', 'Batch-wise production cost', 'implemented', 'costing', 'factory', { note: N('উৎপাদনের খরচ ট্যাবে CSV যোগ হয়েছে (phase 401)', 'CSV added on the Runs tab (phase 401)') }),
    R(47, 'শ্রম ও ওভারহেড খরচ', 'Labour and overhead cost', 'Labour ও overhead cost', 'incomplete', 'costing', 'factory', { needs: N('কারখানার বেতন শ্রম-পুলের সাথে যুক্ত নয়', 'Factory payroll is not linked to the labour pool') }),
    R(48, 'শ্রম-ঘণ্টা অনুযায়ী উৎপাদন', 'Output per labour hour', 'Output per labour hour', 'unavailable', null, 'factory', { pkg: 'R8', needs: N('প্রতি ব্যাচে শ্রম-ঘণ্টা', 'Labour hours per run') }),
    R(49, 'বাতিল, পুনঃকাজ ও উৎপাদনের ক্ষতি', 'Rejection, rework, production loss', 'Rejection, rework, production loss', 'incomplete', 'report/f2_yield', 'factory', { pkg: 'R3', needs: N('ব্যাচ অনুযায়ী বাতিল/পুনঃকাজের পরিমাণ ও কারণ', 'Reject and rework quantity and reason per run') }),
    R(50, 'কারণ / পণ্য / ব্যাচ অনুযায়ী অপচয়', 'Wastage by reason / product / batch', 'Wastage by reason / product / batch', 'implemented', 'report/wastage', 'stock', { more: ['stockx'], needs: N('উৎপাদন-ব্যাচ অনুযায়ী ভাগ নেই', 'No production-run split') }),
    R(51, 'ক্ষমতার ব্যবহার', 'Capacity utilization', 'Capacity utilization', 'unavailable', null, 'factory', { pkg: 'R8', needs: N('আউটলেট/লাইন অনুযায়ী রেটেড ক্ষমতা', 'Rated capacity per outlet / line') }),
    R(52, 'উৎপাদন অর্ডারের অবস্থা', 'Production order status and pending orders', 'Production order status ও pending orders', 'unavailable', null, 'factory', { pkg: 'R3', needs: N('উৎপাদন অর্ডার ও তার অবস্থা', 'Production orders with a status') }),
    R(53, 'উৎপাদন থেকে চালান মিলান', 'Production-to-dispatch reconciliation', 'Production-to-dispatch reconciliation', 'incomplete', 'report/f1_production', 'stock', { more: ['report/transfers_gap'], pkg: 'R4', needs: N('তৈরি − পাঠানো − গৃহীত − পথে − কম = হাতে, আইটেম ও দিন অনুযায়ী', 'Made - sent - received - in transit - short = on hand, per item and day') }),
    R(54, 'তৈরি পণ্য: তৈরি বনাম বিক্রি বনাম বাকি', 'Finished goods produced vs sold vs remaining', 'FG produced vs sold vs remaining', 'implemented', 'report/k3_store_ledger', 'stock', { more: ['report/stock_balance', 'report/y1_daily_sellout'] }),
    R(55, 'উৎপাদন খরচের পার্থক্য বিশ্লেষণ', 'Manufacturing cost variance analysis', 'Manufacturing cost variance analysis', 'unavailable', null, 'factory', { pkg: 'R4', needs: N('দাম/ব্যবহার/ফলনের ভাগ করতে আসল ব্যবহার ও আসল ফলন', 'Actual consumption and actual yield for a price / usage / yield split') }),
  ] },
  { id: 5, pending: true, title: N('বিভাগ ৫', 'Section 5', 'Section 5'), reports: [] },
  { id: 6, pending: true, title: N('বিভাগ ৬', 'Section 6', 'Section 6'), reports: [] },
  { id: 7, pending: true, title: N('বিভাগ ৭', 'Section 7', 'Section 7'), reports: [] },
  { id: 8, pending: true, title: N('বিভাগ ৮', 'Section 8', 'Section 8'), reports: [] },
  { id: 9, pending: true, title: N('বিভাগ ৯', 'Section 9', 'Section 9'), reports: [] },
  { id: 10, pending: true, title: N('বিভাগ ১০', 'Section 10', 'Section 10'), reports: [] },
  { id: 11, pending: true, title: N('বিভাগ ১১', 'Section 11', 'Section 11'), reports: [] },
  { id: 12, pending: true, title: N('বিভাগ ১২', 'Section 12', 'Section 12'), reports: [] },
  { id: 13, pending: true, title: N('বিভাগ ১৩', 'Section 13', 'Section 13'), reports: [] },
  { id: 14, pending: true, title: N('বিভাগ ১৪', 'Section 14', 'Section 14'), reports: [] },
  // reports added beyond the master list (docs/integration/RPT-B1.md, phase 403)
  { id: 'x', extra: true, title: N('মাস্টার তালিকার বাইরে (মিষ্টির ব্যবসার জন্য)', 'Beyond the master list (for a sweets business)', 'Master list-এর বাইরে (মিষ্টির ব্যবসার জন্য)'), reports: [
    R('x1', 'দৈনিক বিক্রি-শেষ / অবিক্রীত (আউটলেট ও আইটেম অনুযায়ী)', 'Daily sell-out / unsold at closing (per outlet and item)', 'Daily sell-out / unsold at closing', 'implemented', 'report/y1_daily_sellout', 'stock', { more: ['report/k3_store_ledger'], note: N('তৈরি + গৃহীত বনাম বিক্রি বনাম বাকি, অপচয়ের খরচসহ; সারিতে চাপলে মূল লেনদেন (phase 403)', 'Produced + received vs sold vs left, with the waste cost; tap a row for the transactions (phase 403)') }),
    R('x2', 'উৎসব / মৌসুম তুলনা (গত বছরের সাথে)', 'Festival / season comparison (vs last year)', 'Festival / season comparison', 'implemented', 'report/y2_festival_compare', 'sale', { more: ['report/item_sales'], note: N('একই আইটেমের বিক্রি বাছা সময়ে বনাম গত বছর; আগের তথ্য না থাকলে তা বলে (phase 403)', 'The same items over the chosen dates vs last year; says so when there is no earlier data (phase 403)') }),
    R('x3', 'সেরা গ্রাহকরা কী কেনেন', 'What the top customers buy', 'What the top customers buy', 'implemented', 'report/y3_customer_items', 'cust', { more: ['report/best_customers'], note: N('সেরা গ্রাহক ও তাঁদের আইটেম; সারিতে চাপলে মূল বিক্রি (phase 403)', 'Top customers and their items; tap a row for the sales (phase 403)') }),
  ] },
];

// ---------- extension: later audits add sections without touching this file's code ----------
let SECTIONS = REGISTRY.slice();
function extend(list) {
  (list || []).forEach((s) => {
    if (!s || s.id === undefined || s.id === null) return;
    const i = SECTIONS.findIndex((x) => String(x.id) === String(s.id));
    const sec = { id: s.id, title: s.title, reports: (s.reports || []).map((r) => Object.assign({}, r)), pending: !(s.reports && s.reports.length), extra: !!s.extra };
    if (i >= 0) SECTIONS[i] = sec; else SECTIONS.push(sec);
  });
}
if (Array.isArray(window.BOS_REPORT_MAP_EXT)) extend(window.BOS_REPORT_MAP_EXT);

// ---------- ONE list of all 193 reports: web/data/report_registry.json (RPT-HUB; built from the audits by tools/build_report_registry.py) ----------
// Integration: sections 5 to 14 of this map come from it, and the status / route of the reports of sections 1 to 4 follow it (the notes written here stay).
const AREA_GROUP = { exec: 'dash', sales: 'sale', product: 'acc', production: 'factory', stock: 'stock', quality: 'stock', purchase: 'purch', cash: 'acc', customer: 'cust', staff: 'people', orders: 'sale', marketing: 'reports', audit: 'appr', planning: 'reports', unaudited: 'reports' };
let synced = false;
async function syncRegistry() {
  if (synced) return;
  try {
    const r = await fetch('data/report_registry.json'); if (!r.ok) return;
    const d = await r.json(), reps = d && Array.isArray(d.reports) ? d.reports : [];
    if (!reps.length) return;
    const byNo = new Map(reps.map((x) => [x.no, x]));
    SECTIONS.forEach((sec) => { if (sec.extra) return; (sec.reports || []).forEach((row) => { const g = byNo.get(row.n); if (g && g.status !== 'unaudited') { row.status = g.status; if (g.route) row.route = g.route; } }); });
    (d.sections || []).forEach((sd) => {
      if (!sd.range || sd.no < 5) return;
      const rows = reps.filter((x) => x.section === sd.no && x.status !== 'unaudited').map((x) => {
        const g = (x.route && B.ia && B.ia.byRoute && B.ia.byRoute(x.route.split('/')[0]) && B.ia.byRoute(x.route.split('/')[0]).group) || AREA_GROUP[x.area] || 'reports';
        const note = x.note ? [x.note, x.note, x.note] : undefined;
        return Object.assign({ n: x.no, name: [x.name.bn, x.name.en, x.name.mix || x.name.en], status: x.status, route: x.route || null, group: g }, note ? { note } : {});
      });
      if (!rows.length) return;
      const cur = SECTIONS.find((x) => String(x.id) === String(sd.no));
      if (cur && cur.reports && cur.reports.length) return;      // a section written by hand in this file or by BOS.reportsMap.extend() wins
      extend([{ id: sd.no, title: [sd.name.bn, sd.name.en, sd.name.mix || sd.name.en], reports: rows }]);
    });
    synced = true;
  } catch (e) { /* offline or no file: the map shows what it has */ }
}

// ---------- what the person may open (best effort; the server decides on every call) ----------
const MAP = { q: '', st: '', allowed: null, pages: null };
async function loadAllowed() {
  const set = new Map();
  try { const r = await sb.rpc('report_catalog'); if (!r.error && Array.isArray(r.data)) r.data.forEach((c) => set.set(c.key, !!c.allowed)); } catch (e) { /* offline: links stay open */ }
  try { if (B.reports2 && B.reports2.catalog) { const more = await B.reports2.catalog(); (more || []).forEach((c) => set.set(c.key, !!c.allowed)); } } catch (e) { /* first engine only */ }
  MAP.allowed = set.size ? set : null;
  try { MAP.pages = window.BOS_NAV && window.BOS_NAV.entries ? new Set(window.BOS_NAV.entries().filter((e) => e.kind === 'r' && e.ok).map((e) => e.route)) : null; } catch (e) { MAP.pages = null; }
}
function canOpen(route) {
  if (!route) return false;
  if (route.startsWith('report/')) return !MAP.allowed || !MAP.allowed.has(route.slice(7)) || MAP.allowed.get(route.slice(7)) === true;
  return !MAP.pages || !B.ia || !B.ia.byRoute(route) || MAP.pages.has(route) || route === 'home';
}
const groupName = (g) => (B.ia && B.ia.groupLabel ? B.ia.groupLabel(g) : g);
const LOCK = '<svg viewBox="0 0 32 32" aria-hidden="true" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="14" width="20" height="14" rx="3"/><path d="M10 14V9a6 6 0 0 1 12 0v5"/></svg>';

// ---------- drawing ----------
const norm = (x) => String(x || '').toLowerCase();
const rowText = (r) => [r.n, ...(r.name || []), r.route, r.group, ...(r.note || []), ...(r.needs || [])].map(norm).join(' ');
const chipCls = (s) => (s === 'implemented' ? 'ok' : s === 'incomplete' ? 'warn' : s === 'unavailable' ? 'bad' : 'info');
function counts() {
  const c = { implemented: 0, incomplete: 0, unavailable: 0, unverified: 0, pending: 0 };
  SECTIONS.forEach((s) => { if (s.extra) return; if (s.pending) c.pending += 1; else s.reports.forEach((r) => { c[r.status] = (c[r.status] || 0) + 1; }); });
  return c;
}
function rowHTML(r) {
  const open = canOpen(r.route), name = tx(r.name);
  const link = r.route ? (open ? `<button class="rm-open" data-act="go" data-v="${esc(r.route)}" aria-label="${esc(T('open') + ': ' + name)}">${esc(T('open'))} ›</button>` : `<span class="chip rm-lock">${LOCK} ${esc(T('locked'))}</span>`) : `<span class="muted rm-nb">${esc(T('nobuild'))}</span>`;
  const extras = (r.more || []).map((m) => `<button class="rm-more" data-act="go" data-v="${esc(m)}" ${canOpen(m) ? '' : 'disabled'}>${esc(m.replace(/^report\//, ''))}</button>`).join('');
  return `<div class="rm-row" data-n="${esc(String(r.n))}" data-status="${esc(r.status)}" data-route="${esc(r.route || '')}">
    <div class="rm-top"><span class="rm-n">${typeof r.n === 'number' ? '#' + r.n : esc(String(r.n))}</span><span class="nm">${esc(name)}</span><span class="chip ${chipCls(r.status)} rm-st">${esc(T(r.status))}</span></div>
    <div class="rm-sub"><span class="chip rm-g">${esc(groupName(r.group))}</span>${r.pkg && !r.route ? `<span class="chip info">${esc(T('pkg'))}: ${esc(r.pkg)}</span>` : ''}</div>
    ${r.note ? `<div class="rm-note">${esc(tx(r.note))}</div>` : ''}${r.needs && r.status !== 'implemented' ? `<div class="rm-need"><b>${esc(T('needs'))}:</b> ${esc(tx(r.needs))}</div>` : ''}${r.needs && r.status === 'implemented' ? `<div class="rm-need muted">${esc(tx(r.needs))}</div>` : ''}
    <div class="rm-act">${link}${extras}</div></div>`;
}
function draw() {
  const c = counts(), q = norm(MAP.q).trim();
  const secs = SECTIONS.map((s) => {
    const rows = s.reports.filter((r) => (!MAP.st || r.status === MAP.st) && (!q || rowText(r).includes(q)));
    if (s.pending) { if (MAP.st || q) return ''; return `<section class="rm-sec pend" data-sec="${esc(String(s.id))}"><div class="rm-sh"><b>${esc(tx(s.title))}</b><span class="chip info">${esc(T('pending'))}</span></div><div class="muted rm-pt">${esc(T('pendingText'))}</div></section>`; }
    if (!rows.length) return '';
    return `<details class="rm-sec" data-sec="${esc(String(s.id))}" ${MAP.st || q || s.id === 1 ? 'open' : ''}><summary><b>${typeof s.id === 'number' ? s.id + '. ' : ''}${esc(tx(s.title))}</b><span class="chip">${rows.length} ${esc(T('count'))}</span></summary>${rows.map(rowHTML).join('')}</details>`;
  }).join('');
  const box = $('#rm_body'); if (!box) return;
  box.innerHTML = `<div class="stats rm-stats">${STATUS.map((k) => `<button class="stat rm-stat ${MAP.st === k ? 'on' : ''}" data-act="rm_st" data-v="${k}" aria-pressed="${MAP.st === k}"><div class="k">${esc(T(k))}</div><div class="v">${c[k]}</div></button>`).join('')}
      <div class="stat rm-stat static"><div class="k">${esc(T('pending'))}</div><div class="v">${c.pending}</div></div></div>
    ${secs || `<p class="muted center pad">${esc(T('none'))}</p>`}
    <div class="rp-foot rm-foot"><button data-act="rm_csv">${esc(T('csv'))}</button><button data-act="go" data-v="reports">${esc(T('hub'))}</button></div>`;
}
async function viewMap() {
  shell(T('title'), `<p class="muted">${esc(lab(L('লোড হচ্ছে…', 'Loading…', 'Loading…')))}</p>`, 'reports');
  await Promise.all([loadAllowed(), syncRegistry()]);
  shell(T('title'), `<p class="muted rm-intro">${esc(T('intro'))}</p><p class="rm-hublink"><button type="button" class="mini" data-act="go" data-v="reports/hub">${esc(lab(L('বিজনেস মেমোরি: কী ঘটেছিল', 'Business Memory: what happened', 'Business Memory: কী ঘটেছিল')))} ›</button></p>
    <input id="rm_q" type="search" autocomplete="off" placeholder="${esc(T('search'))}" aria-label="${esc(T('search'))}" value="${esc(MAP.q)}"><div id="rm_body"></div>`, 'reports');
  draw();
}

// ---------- CSV (the whole registry; a blank cell is a real blank) ----------
function csvCell(v) {
  if (v === null || v === undefined) return '';
  let s = String(v); if (/^[=+@\t\r]/.test(s)) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}
function buildCSV() {
  const en = (a) => (a ? a[1] : ''), head = [T('secH'), T('numH'), T('repH'), T('stH'), T('grpH'), T('rtH'), T('noteH'), T('needH')];
  const out = [head.map(csvCell).join(',')];
  SECTIONS.forEach((s) => {
    if (s.pending) { out.push([en(s.title), '', '', 'pending', '', '', '', ''].map(csvCell).join(',')); return; }
    s.reports.forEach((r) => out.push([en(s.title), r.n, en(r.name), r.status, r.group, r.route || '', en(r.note), en(r.needs)].map(csvCell).join(',')));
  });
  out.push(''); out.push(csvCell(T('static') + ': docs/REPORTS_AUDIT_1.md, docs/integration/RPT-B1.md'));
  return '﻿' + out.join('\r\n') + '\r\n';
}
function exportCSV() {
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([buildCSV()], { type: 'text/csv;charset=utf-8' })); a.download = 'reports-map.csv'; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); toast(T('csvDone'));
}

Object.assign(A.H, {
  rm_st: (a) => { MAP.st = MAP.st === a.dataset.v ? '' : a.dataset.v; draw(); },
  rm_csv: exportCSV,
});
document.addEventListener('input', (e) => { if (e.target.id === 'rm_q') { MAP.q = e.target.value; draw(); } });

if (!document.getElementById('rm_css')) {
  const st = document.createElement('style'); st.id = 'rm_css';
  st.textContent = `
#rm_q{margin:6px 0 8px;width:100%}
.rm-intro{margin:0 0 6px}
.rm-stats{margin:6px 0 10px;grid-template-columns:1fr 1fr 1fr}
.rm-stat{min-height:64px;text-align:start;cursor:pointer;padding:8px 10px} .rm-stat .v{font:700 1.3rem var(--text-font)} .rm-stat.on{outline:2px solid var(--ink-2)} .rm-stat.static{cursor:default}
.rm-sec{border:1px solid var(--hair);border-radius:14px;background:var(--card);margin:0 0 10px;overflow:hidden}
.rm-sec>summary,.rm-sh{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:10px 12px;min-height:48px;cursor:pointer;list-style:none}
.rm-sec>summary::-webkit-details-marker{display:none} .rm-sec.pend{padding:0} .rm-pt{padding:0 12px 12px;font-size:.9rem}
.rm-row{padding:10px 12px;border-top:1px solid var(--hair)}
.rm-top{display:flex;align-items:flex-start;gap:8px} .rm-top .nm{flex:1;min-width:0;overflow-wrap:anywhere;font-weight:600} .rm-n{color:var(--muted);font:600 .82rem var(--text-font);min-width:34px;padding-top:2px}
.rm-st{flex:none} .rm-sub{display:flex;flex-wrap:wrap;gap:6px;margin:4px 0 0 42px}
.rm-note,.rm-need{font-size:.86rem;margin:4px 0 0 42px;color:var(--ink-2);overflow-wrap:anywhere}
.rm-act{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 0 42px} .rm-open{min-height:44px;padding:0 14px} .rm-more{min-height:36px;padding:0 10px;font-size:.82rem;opacity:.9}
.rm-nb{font-size:.88rem;align-self:center} .rm-lock svg{margin-inline-end:4px} .rm-foot{margin:12px 0}
`;
  document.head.appendChild(st);
}

// #/reports/map is a second view of the page route "reports"; the reports hub (reports.js) keeps every other path
const prev = (window.BOS_PAGES || {}).reports;
const sub = () => location.hash.replace(/^#\/?/, '').split('?')[0].split('/')[1] || '';
window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { reports: () => (sub() === 'map' ? viewMap() : (prev ? prev() : viewMap())) });
B.reportsMap = { sections: () => SECTIONS, extend, STATUS, buildCSV, counts };
// the hub lists the map under "Other pages"
B.reportLinks = B.reportLinks || [];
B.reportLinks.push({ key: 'reportsmap', route: 'reports/map', label: () => T('title'), allowed: true });
})();
