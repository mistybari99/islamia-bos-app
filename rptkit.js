/* Islamia BOS · RPT-C3 report kit (marketing, audit and planning pages).
   One small engine for the report pages of campaigns.js, couponuse.js, auditreports.js and forecast.js: filters (dates, place, typed inputs), the server answer drawn as cards
   (a phone-first list, never a wide table), stat boxes, a drill-down sheet, notes and an "assumptions" panel that come from the server, an (i) info sheet, and CSV.
   Rules this kit keeps: a value the server sent as null is shown as "Data not captured" (never 0, never an estimate); the server decides every right (a refused call shows a lock card);
   the CSV is built only AFTER the server logged the export (rptc3_export_log); every visible word has the three modes. Loaded before campaigns.js / couponuse.js / auditreports.js / forecast.js. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS;
const { sb, S, esc, toast, fail, shell, openSheet, closeSheet, nm } = A;
const H = A.H, L = B.L, lab = B.lab;
const $ = (s, el = document) => el.querySelector(s);
const owner = () => !!(S.ctx && S.ctx.is_owner);

const X = {
  from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), place: L('জায়গা', 'Place', 'Place'), allPlaces: L('সব জায়গা', 'All places', 'সব Place'), run: L('দেখান', 'Show', 'Show'),
  csv: L('CSV', 'CSV', 'CSV'), info: L('এটা কী?', 'About this report', 'About this report'), close: L('বন্ধ', 'Close', 'Close'), loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'),
  need: L('তথ্য নেই', 'Data not captured', 'Data নেই'), none: L('কিছু নেই', 'Nothing in this period', 'কিছু নেই'), more: L('বিস্তারিত', 'Details', 'Details'),
  notAllowed: L('এই রিপোর্ট দেখার অনুমতি নেই', 'You are not allowed to see this report', 'এই report দেখার permission নেই'), sqlMissing: L('এই রিপোর্টের ডেটাবেস অংশ এখনও চালু হয়নি', 'The database part of this report is not installed yet', 'এই report-এর database অংশ এখনও চালু হয়নি'),
  badRange: L('ডেট বা সংখ্যা ঠিক নয়', 'The dates or numbers are not valid', 'Date বা সংখ্যা ঠিক নয়'), notes: L('জেনে রাখুন', 'Read this first', 'জেনে রাখুন'), assumptions: L('অনুমান ও তথ্যের পরিধি', 'Assumptions and data coverage', 'অনুমান ও data coverage'),
  basis: L('কীভাবে গোনা', 'How it is counted', 'কীভাবে গোনা'), expDone: L('ফাইল তৈরি হয়েছে', 'File created', 'File তৈরি হয়েছে'), expLock: L('এক্সপোর্টের অনুমতি নেই', 'Export is not allowed', 'Export-এর permission নেই'),
  dataNeeded: L('আগে এই তথ্য দিতে হবে', 'This must be filled in first', 'আগে এই তথ্য দিতে হবে'), prev: L('আগের', 'Previous', 'Previous'), next: L('পরের', 'Next', 'Next'),
  page: L('পাতা', 'Page', 'Page'), of: L('মোট', 'of', 'of'), by: L('কে', 'By', 'By'), at: L('সময়', 'Time', 'Time'), period: L('সময়কাল', 'Period', 'Period'), yes: L('হ্যাঁ', 'Yes', 'Yes'), no: L('না', 'No', 'No'),
  capped: L('CSV-তে সর্বোচ্চ ২০,০০০ সারি', 'The CSV holds up to 20,000 rows', 'CSV-তে সর্বোচ্চ 20,000 row'), drill: L('উৎস দেখুন', 'Show the records behind it', 'উৎস দেখুন'), retry: L('আবার চেষ্টা', 'Try again', 'আবার চেষ্টা'),
};
const T = (k) => lab(X[k]);

// ---------- the "read this first" sentences, by the code the server sends ----------
const N = {};
const n = (c, bn, en) => { N[c] = L(bn, en, en); };
n('spend_paid_only', 'শুধু পরিশোধিত টাকা ধরা হয়েছে', 'Only the paid amount is counted');
n('nonpay_apart', 'টাকা ছাড়া মূল্য (স্যাম্পল) আলাদা, যোগ হয়নি', 'Value without payment (samples) is shown apart and never added');
n('sheets_submitted_and_approved', 'জমা ও অনুমোদিত শিট ধরা হয়েছে, খসড়া নয়', 'Submitted and approved sheets are counted, drafts are not');
n('unassigned_is_not_guessed', 'ক্যাম্পেইন ছাড়া লাইন আন্দাজে কোনো ক্যাম্পেইনে ধরা হয়নি', 'A line with no campaign is not guessed into one');
n('not_in_books_unless_posted', 'হিসাবের খাতায় ওঠে শুধু "মার্কেটিং খরচ পোস্ট" চালু থাকলে', 'This spend is in the books only when "post marketing spend" is switched on');
n('no_causal_claim', 'কোনটা কীসের কারণে হয়েছে — এই রিপোর্ট তা বলে না', 'This report does not say that one thing caused another');
n('same_day_only', 'একই দিনের খরচ ও বিক্রি পাশাপাশি', 'Spend and sales of the same day, side by side');
n('sales_gross_of_returns', 'বিক্রির অঙ্ক ফেরত বাদ দেওয়ার আগের', 'Sales are before returns');
n('tagged_sales_only', 'শুধু ক্যাম্পেইন-চিহ্নিত বিলের বিক্রি', 'Only bills tagged with the campaign');
n('contribution_on_costed_part', 'লাভ ধরা হয়েছে শুধু যেসব পণ্যের খরচ জানা', 'Contribution is on the items whose cost price is known');
n('spend_in_same_period', 'খরচ একই তারিখ-সীমার ১৭-১ লাইন', 'Spend = 17-1 lines in the same dates');
n('cost_hidden', 'খরচের অঙ্ক দেখার অধিকার না থাকায় খরচ ও লাভ দেখানো হয়নি', 'Cost and profit are hidden because you may not see costs');
n('compare_with_baseline_is_not_proof', 'ছাড়-ছাড়া বিলের সাথে তুলনা প্রমাণ নয়', 'Comparing with bills that had no discount is not proof');
n('untagged_discounts_in_blank_row', 'ক্যাম্পেইন ছাড়া ছাড় ফাঁকা সারিতে', 'Discounts with no campaign are in the blank row');
n('crmf_not_installed', 'কুপন মডিউল (CRM-F) চালু নেই, তাই কোনো কুপন যাচাই করা হয়নি', 'The coupon module (CRM-F) is not installed, so no coupon is validated');
n('typed_codes_not_validated', 'বিলে লেখা কোড কোনো তালিকার সাথে মেলানো নয়', 'Codes typed on the bill are not checked against a list');
n('validated_from_crmf', 'যাচাই করা ব্যবহার কুপন মডিউল থেকে', 'Validated uses come from the coupon module');
n('tier_offers_in_customer_tier_report', 'স্তরের অফারের ব্যবহার গ্রাহক-স্তর রিপোর্টে', 'Tier offers are in the customer tier report');
n('source_coverage_shown', 'নতুন গ্রাহকের কতজনের উৎস লেখা — তা সবসময় দেখানো হয়', 'The share of new customers with a source is always shown');
n('cac_all_is_a_blend', 'সব-খরচ ÷ সব-নতুন-গ্রাহক একটি মিশ্র সংখ্যা', 'All spend divided by all new customers is a blend');
n('new_customer_is_date_of_first_record', 'নতুন গ্রাহক = রেকর্ডের তারিখ ওই সময়ে', 'A new customer is one whose record is dated in the period');
n('place_filter_uses_first_sale_place', 'জায়গা বাছলে প্রথম বিক্রির জায়গা ধরা হয়', 'With a place chosen, the place of the first bill is used');
n('only_identified_customers', 'শুধু নাম বা মোবাইল-লেখা বিল ধরা হয়েছে', 'Only bills with a customer on them are counted');
n('incomplete_window_marked', 'যে সময়সীমা এখনও শেষ হয়নি তা চিহ্নিত', 'A window that is not over yet is marked');
n('repeat_means_a_later_bill_not_tagged_to_the_same_campaign', 'পুনরায় কেনা = একই ক্যাম্পেইনের চিহ্নহীন পরের বিল', 'Repeat = a later bill not tagged to the same campaign');
n('window_days_not_set', 'কত দিন ধরা হবে তা লেখা নেই — কিছু ধরে নেওয়া হয়নি', 'The number of days is not set - nothing is assumed');
n('attributable_data_only', 'শুধু চিহ্নিত বিল ও ক্যাম্পেইন-বসানো খরচ ব্যবহার', 'Only tagged bills and campaign-assigned spend are used');
n('unassigned_spend_not_in_roi', 'ক্যাম্পেইন-ছাড়া খরচ কোনো ROI-তে নেই', 'Unassigned spend is in no ROI');
n('untagged_sales_not_counted_roi_may_be_understated', 'চিহ্নহীন বিক্রি গোনা হয়নি, তাই ROI কম দেখাতে পারে', 'Untagged sales are not counted, so ROI may look lower than it is');
n('approved_sheets_only', 'শুধু অনুমোদিত ১৭-১ শিট', 'Only approved 17-1 sheets');
n('imprest_never_posted_here', 'ইমপ্রেস্টের খরচ এখানে কখনো পোস্ট হয় না (১১-১ ভাউচারে আছে)', 'Imprest-paid lines are never posted here (the 11-1 voucher has them)');
n('look_alikes_wait_for_a_decision', 'একই খরচ ১১-১ বা দ্রুত খরচে থাকলে সিদ্ধান্তের অপেক্ষায়', 'A line that looks like a 11-1 voucher or quick expense waits for a decision');
n('owner_money_not_posted', 'মালিকের নিজের টাকার লাইন পোস্ট হয় না (হিসাবের সিদ্ধান্ত বাকি)', 'Lines paid from the owner\'s own money are not posted (an accounting choice is open)');
n('management_profit_view_unchanged', 'ব্যবস্থাপনা-লাভের হিসাব (L1) আগের মতোই', 'The management profit view (L1) is unchanged');
n('owner_only', 'শুধু মালিক দেখতে পারেন', 'Only the owner can open this');
n('append_only', 'লগে কিছু বদলানো বা মোছা যায় না', 'The log cannot be edited or deleted');
n('times_are_asia_dhaka_dates', 'তারিখ ঢাকার সময়ে', 'Dates are Asia/Dhaka');
n('nothing_is_hard_deleted', 'কোথাও কিছু মোছা হয় না — এখানে তা-ই দেখানো হচ্ছে যা মডিউল রাখে', 'Nothing is hard-deleted; this lists what each module keeps');
n('time_not_captured_where_the_module_stores_none', 'যে মডিউল বাতিলের সময় রাখে না, সেখানে সময় ফাঁকা', 'Where a module never stored the time of the void, the time is blank');
n('dates_are_the_void_date_else_the_record_date', 'তারিখ = বাতিলের তারিখ, না থাকলে রেকর্ডের তারিখ', 'Date = the void date, else the record date');
n('salary_modules_hidden', 'বেতন সংক্রান্ত লাইন আপনার অনুমতি না থাকায় বাদ', 'Salary-related lines are left out because you may not see salaries');
n('clock_hours_not_working_hours', 'ঘণ্টা মানে ঘড়ির ঘণ্টা (রাত-ছুটি সহ)', 'Hours are clock hours (nights and holidays included)');
n('no_late_limit_invented', '"দেরি" কত তার কোনো সীমা বসানো হয়নি', 'No limit for "late" has been invented');
n('dated_by_the_day_it_was_asked', 'অনুরোধের দিন ধরে', 'Dated by the day the request was made');
n('direct_wastage_has_no_request', 'সরাসরি নষ্টের অনুরোধ নেই, তাই অনুমোদনকারী নেই', 'Direct wastage had no request, so there is no approver');
n('qty_negative_is_stock_out', 'বিয়োগ চিহ্ন = স্টক কমেছে', 'A minus quantity means stock went out');
n('lists_show_up_to_300_rows_each_total_is_exact', 'প্রতি তালিকায় ৩০০ সারি পর্যন্ত; মোট সংখ্যা সঠিক', 'Each list shows up to 300 rows; the total is exact');
n('no_cost_means_profit_is_only_on_the_costed_part', 'দাম না থাকলে লাভ শুধু খরচ-জানা অংশে', 'Without a cost price, profit covers only the costed part');
n('ingredient_costs_need_the_cost_right', 'কাঁচামালের খরচ দেখতে খরচের অধিকার লাগে', 'Ingredient costs need the right to see costs');
n('override_approver_captured_from_phase464', 'দাম-বদলের অনুমোদনকারী এই আপডেটের পর থেকে রাখা হচ্ছে', 'The approver of a price change is stored from this update onward');
n('older_bills_say_not_captured', 'পুরনো বিলে "রাখা হয়নি" — কাউকে আন্দাজে বসানো হয়নি', 'Older bills say "not captured" - nobody is guessed');
n('no_approver_is_asked_for_while_the_switch_is_off', 'সুইচ বন্ধ থাকলে অনুমোদনকারী চাওয়া হয় না', 'No approver is asked for while the switch is off');
n('a_discount_inside_the_limit_needs_no_approver', 'সীমার মধ্যের ছাড়ে অনুমোদনকারী লাগে না', 'A discount inside the limit needs no approver');
n('events_of_known_kinds_not_a_threshold', 'নির্দিষ্ট ধরনের ঘটনা — কোনো অঙ্কের সীমা দিয়ে বাছা নয়', 'Events of known kinds - not picked by an amount limit');
n('a_refund_is_also_inside_its_return', 'ফেরত-টাকা আলাদা সারিতে, আবার ফেরতের ভেতরেও আছে', 'The refund paid is its own row and also inside its return');
n('payment_void_time_not_stored', 'পেমেন্ট বাতিলের সময় রাখা হয় না', 'The time of a payment void is not stored');
n('business_record_columns', 'ব্যবসার রেকর্ড থেকে গোনা', 'Counted from the business records');
n('places_you_can_see_only', 'শুধু আপনার দেখার জায়গার তথ্য', 'Only the places you may see');
n('login_and_audit_columns_owner_only', 'লগইন ও অডিট-লগের কলাম শুধু মালিকের', 'Login and audit-log columns are for the owner only');
n('owner_enters_every_festival', 'উৎসব মালিক নিজে বসান', 'The owner enters every festival');
n('uplift_is_owner_set_never_guessed', 'বাড়তি % মালিকের দেওয়া, আন্দাজ নয়', 'The uplift % is the owner\'s own, never guessed');
n('nothing_is_deleted_only_retired', 'কিছু মোছা হয় না, শুধু বন্ধ করা যায়', 'Nothing is deleted, only retired');
n('range_is_lowest_and_highest_past_same_weekday_not_a_confidence_interval', 'নিচ–উপর = আগের একই বারের সবচেয়ে কম ও বেশি; এটি পরিসংখ্যানের আস্থা-সীমা নয়', 'Low-high = the smallest and largest of the past same weekday; it is NOT a statistical confidence interval');
n('no_probability_claimed', 'কোনো সম্ভাবনা বা নিশ্চয়তার দাবি নেই', 'No probability or certainty is claimed');
n('days_without_a_bill_are_closed_not_zero', 'বিল-ছাড়া দিন বন্ধ/তথ্যহীন ধরা — শূন্য বিক্রি নয়', 'A day with no bill is closed / no data, not zero sales');
n('festival_days_left_out_of_the_average', 'উৎসবের দিনগুলো সাধারণ গড় থেকে বাদ', 'Festival days are left out of the ordinary average');
n('uplift_only_when_the_owner_typed_one', 'বাড়তি % দেখানো হয় শুধু মালিক দিলে', 'An uplift is shown only when the owner typed one');
n('no_trend_weather_or_price_change', 'ধারা, আবহাওয়া বা দাম বদল ধরা হয়নি', 'No trend, weather or price change is modelled');
n('history_shorter_than_the_window', 'ইতিহাস চাওয়া সময়ের চেয়ে ছোট', 'The history is shorter than the window you asked for');
n('days_out_of_stock_count_as_zero', 'স্টক-শূন্য দিন ০ ধরা, তাই চাহিদা কম আসতে পারে', 'Days out of stock count as zero, so demand may be under-stated');
n('untracked_items_not_covered', 'স্টক-ট্র্যাক-না-হওয়া পণ্য এখানে নেই', 'Items that are not stock-tracked are not covered');
n('the_same_uplift_is_applied_to_every_item', 'সব পণ্যে একই বাড়তি % দেওয়া হয়েছে', 'The same uplift is applied to every item');
n('orders_on_top_may_count_some_demand_twice', 'অর্ডার যোগ করলে কিছু চাহিদা দুবার ধরা হতে পারে', 'Adding orders may count some demand twice');
n('stock_on_hand_is_this_place_only', 'মজুত শুধু এই জায়গার', 'Stock on hand is this place only');
n('items_without_a_recipe_listed_apart', 'রেসিপি-ছাড়া পণ্য আলাদা তালিকায়', 'Items with no recipe are listed apart');
n('nothing_is_ordered_or_produced_by_this_report', 'এই রিপোর্ট কিছু অর্ডার বা উৎপাদন করে না', 'This report orders and produces nothing');
n('need_includes_recipe_waste_percent', 'প্রয়োজনে রেসিপির অপচয় % ধরা', 'Need includes the recipe waste %');
n('waste_percent_missing_means_zero_waste_was_used_and_is_flagged', 'অপচয় % লেখা না থাকলে ০ ধরা হয়েছে ও চিহ্নিত', 'Where the waste % is blank, zero was used and it is flagged');
n('stock_on_hand_counted_once_per_ingredient', 'মজুত প্রতি কাঁচামালে একবারই বাদ', 'Stock on hand is deducted once per ingredient');
n('no_supplier_order_is_placed', 'সরবরাহকারীকে কোনো অর্ডার যায় না', 'No order is sent to a supplier');
n('lead_days_not_set', 'আনার দিন (লিড) লেখা নেই', 'Lead days are not set');
n('due_date_is_bill_date_plus_credit_days', 'শেষ তারিখ = বিলের তারিখ + সরবরাহকারীর বাকির দিন', 'Due date = bill date + the supplier\'s credit days');
n('unknown_date_is_not_placed_on_the_calendar', 'তারিখ অজানা হলে ক্যালেন্ডারে বসানো হয় না', 'An unknown date is not placed on the calendar');
n('payments_already_made_are_taken_off_oldest_bill_first', 'দেওয়া টাকা পুরনো বিল থেকে আগে কাটা', 'Payments already made are taken off the oldest bill first');
n('no_discount_or_penalty_modelled', 'ছাড় বা জরিমানা ধরা হয়নি', 'No discount or penalty is modelled');
n('only_known_future_money', 'শুধু জানা ভবিষ্যৎ টাকা', 'Only future money that is already known');
n('no_opening_balance_no_forecast_sales_no_tax', 'শুরুর জের, ভবিষ্যৎ বিক্রি বা কর এতে নেই', 'No opening balance, no forecast sales, no tax');
n('transfers_between_own_accounts_are_not_in_the_net', 'নিজের হিসাবের মধ্যে ট্রান্সফার নিটে ধরা নেই', 'Transfers between own accounts are not in the net');
n('customers_have_no_credit_days_so_dues_are_undated', 'গ্রাহকের বাকির দিন লেখা নেই, তাই বাকি আদায়ের তারিখ অজানা', 'Customers have no credit days, so dues have no date');
n('salary_hidden', 'বেতনের লাইন আপনার অনুমতি না থাকায় বাদ', 'Salary lines are left out because you may not see salaries');
n('at_risk_is_stock_left_after_expected_sales_not_a_prediction_of_waste', '"ঝুঁকি" = প্রত্যাশিত বিক্রির পর যা থেকে যায়; নষ্টের ভবিষ্যদ্বাণী নয়', '"At risk" = what is left after the expected sales; not a prediction of waste');
n('no_restock_or_price_cut_modelled', 'নতুন মাল বা দাম কমানো ধরা হয়নি', 'No restock or price cut is modelled');
n('batches_without_expiry_are_not_covered', 'মেয়াদ-ছাড়া ব্যাচ এতে নেই', 'Batches with no expiry date are not covered');
n('days_not_set', 'দিন লেখা নেই — কিছু ধরে নেওয়া হয়নি', 'The days are not set - nothing is assumed');
n('arithmetic_on_typed_percents_not_a_forecast', 'আপনার লেখা % দিয়ে অঙ্ক — পূর্বাভাস নয়', 'Arithmetic on the percents you typed - not a forecast');
n('goods_cost_moves_with_volume_and_unit_cost_only', 'পণ্যের খরচ শুধু পরিমাণ ও একক-খরচের সাথে বদলায়', 'Cost of goods moves with volume and unit cost only');
n('no_percent_is_suggested', 'কোনো % সুপারিশ করা হয় না', 'No percent is suggested');
n('result_shown_only_when_every_part_is_captured', 'ফল দেখানো হয় শুধু সব অংশ থাকলে', 'The result is shown only when every part is captured');
n('baseline_is_the_management_view_not_the_journal', 'ভিত্তি = ব্যবস্থাপনার হিসাব, জার্নাল নয়', 'The baseline is the management view, not the journal');
n('no_sales_in_the_period', 'এই সময়ে বিক্রি নেই', 'No sales in this period');
n('observed_differences_are_history_not_promises', 'দেখা পার্থক্য ইতিহাস — ভবিষ্যতের প্রতিশ্রুতি নয়', 'Observed differences are history, not promises');
n('days_behind_each_figure_are_shown', 'প্রতিটি সংখ্যার পেছনের দিন-সংখ্যা দেখানো হয়', 'The number of days behind each figure is shown');
n('baseline_is_ordinary_trading_days_before_the_festival', 'তুলনা = উৎসবের আগের সাধারণ বিক্রির দিন', 'Baseline = ordinary trading days before the festival');
n('owner_uplift_shown_for_comparison_only', 'মালিকের % শুধু তুলনার জন্য', 'The owner\'s % is for comparison only');
const noteText = (c) => (N[c] ? lab(N[c]) : String(c).replace(/_/g, ' '));

// ---------- helpers ----------
const todayS = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const addDays = (s, k) => new Date(new Date(s + 'T12:00:00Z').getTime() + k * 86400e3).toISOString().slice(0, 10);
const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(new Date(s + 'T12:00:00Z').getTime());
const norm = (v) => String(v ?? '').replace(/[০-৯]/g, (d) => '০১২৩৪৫৬৭৮৯'.indexOf(d)).trim();
const isNil = (v) => v === null || v === undefined || v === '';
const money = (v) => (isNil(v) || !Number.isFinite(Number(v)) ? null : '৳ ' + Number(v).toLocaleString('en-IN', { maximumFractionDigits: 2 }));
const numf = (v) => (isNil(v) || !Number.isFinite(Number(v)) ? null : Number(v).toLocaleString('en-IN', { maximumFractionDigits: 4 }));
const LOCS = () => { const all = (B.ENV && B.ENV.locs) || []; return owner() || (S.ctx.roles || []).includes('management') ? all : all.filter((l) => (S.ctx.locations || []).includes(l.id)); };
const allLocs = () => owner() || (S.ctx.roles || []).includes('management') || LOCS().length > 1;
const locName = (id) => { const l = ((B.ENV && B.ENV.locs) || []).find((x) => x.id === id); return l ? nm(l) : (isNil(id) ? '' : '#' + id); };
const missingFn = (e) => !!e && (e.code === 'PGRST202' || /could not find the function|schema cache/i.test(e.message || ''));
const csvCell = (v) => {
  if (v === null || v === undefined) return '';
  let s = typeof v === 'object' ? JSON.stringify(v) : String(v);
  if (/^[=+@\t\r]/.test(s) || (/^-/.test(s) && /[^\d.\-]/.test(s))) s = "'" + s;
  return /[",\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
const download = (name, text) => { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' })); a.download = name; document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1500); };
const getp = (o, p) => (p ? String(p).split('.').reduce((a, k) => (a === null || a === undefined ? a : a[k]), o) : o);

// one cell: returns {t: text or null (not captured), cls}
function cell(col, row) {
  const raw = col.get ? col.get(row) : row[col.k];
  if (isNil(raw)) return { t: null, raw };
  switch (col.fmt) {
    case 'money': return { t: money(raw), raw };
    case 'num': return { t: numf(raw), raw };
    case 'pct': return { t: numf(raw) === null ? null : numf(raw) + ' %', raw };
    case 'date': return { t: String(raw).slice(0, 10), raw };
    case 'dt': { try { return { t: new Date(raw).toLocaleString('en-GB', { timeZone: 'Asia/Dhaka', dateStyle: 'short', timeStyle: 'short' }), raw }; } catch (e) { return { t: String(raw), raw }; } }
    case 'bool': return { t: raw === true || raw === 'true' ? T('yes') : T('no'), raw };
    case 'place': return { t: locName(Number(raw)), raw };
    case 'lab': return { t: col.labels && col.labels[raw] ? lab(col.labels[raw]) : String(raw), raw };
    case 'json': return { t: typeof raw === 'object' ? JSON.stringify(raw) : String(raw), raw };
    default: return { t: String(raw), raw };
  }
}

// ---------- the engine ----------
const PAGES = {};
function make(cfg) {
  const P = PAGES[cfg.id] = { cfg, tab: cfg.tabs[0].k, f: { from: todayS().slice(0, 8) + '01', to: todayS(), loc: undefined }, x: {}, data: null, err: null, busy: 0, page: 0 };
  const tabOf = () => cfg.tabs.find((t) => t.k === P.tab) || cfg.tabs[0];
  const cid = cfg.id;

  function filtersHTML(t) {
    const locs = LOCS(); let h = '';
    if (t.dates) h += `<div class="row wrap" style="align-items:end;gap:8px"><div style="flex:1;min-width:130px"><label for="${cid}_from">${esc(T('from'))}</label><input type="date" id="${cid}_from" value="${esc(P.f.from)}"></div>
      <div style="flex:1;min-width:130px"><label for="${cid}_to">${esc(T('to'))}</label><input type="date" id="${cid}_to" value="${esc(P.f.to)}"></div></div>`;
    if (t.loc && (locs.length > 1 || allLocs())) h += `<div><label for="${cid}_loc">${esc(T('place'))}</label><select id="${cid}_loc">${allLocs() && !t.locReq ? `<option value="">${esc(T('allPlaces'))}</option>` : ''}${locs.map((l) => `<option value="${l.id}" ${String(P.f.loc) === String(l.id) ? 'selected' : ''}>${esc(nm(l))}</option>`).join('')}</select></div>`;
    (t.inputs || []).forEach((i) => {
      const v = P.x[i.k] !== undefined ? P.x[i.k] : (i.def !== undefined ? i.def : '');
      h += `<div style="flex:1;min-width:130px"><label for="${cid}_x_${i.k}">${esc(lab(i.label))}</label>` + (i.opts
        ? `<select id="${cid}_x_${i.k}">${i.opts.map(([ov, ol]) => `<option value="${esc(ov)}" ${String(v) === String(ov) ? 'selected' : ''}>${esc(lab(ol))}</option>`).join('')}</select>`
        : `<input id="${cid}_x_${i.k}" inputmode="${i.type === 'number' ? 'decimal' : 'text'}" autocomplete="off" value="${esc(v)}" ${i.ph ? `placeholder="${esc(i.ph)}"` : ''}>`) + '</div>';
    });
    if ((t.inputs || []).length) h += `<button class="primary full" data-act="${cid}_run">${esc(T('run'))}</button>`;
    return h;
  }
  function argsOf(t) {
    const a = {}, m = t.a || { from: 'p_from', to: 'p_to', loc: 'p_loc' };
    if (t.dates) { a[m.from] = P.f.from; a[m.to] = P.f.to; }
    if (t.locReq && isNil(P.f.loc)) P.f.loc = (LOCS()[0] || {}).id;
    if (t.loc) a[m.loc] = isNil(P.f.loc) ? null : Number(P.f.loc);
    (t.inputs || []).forEach((i) => {
      const raw = norm(P.x[i.k] !== undefined ? P.x[i.k] : (i.def !== undefined ? i.def : ''));
      a[i.arg] = raw === '' ? null : (i.type === 'number' ? Number(raw) : (i.type === 'bool' ? raw === 'true' : raw));
    });
    if (t.pager) { a.p_limit = t.pager; a.p_offset = P.page * t.pager; }
    return t.args ? t.args(a, P) : a;
  }
  async function load() {
    const t = tabOf(), tok = ++P.busy; P.err = null; P.data = null; draw();
    if (t.custom) { P.data = {}; return draw(); }
    for (const i of (t.inputs || [])) if (i.req && norm(P.x[i.k] !== undefined ? P.x[i.k] : (i.def !== undefined ? i.def : '')) === '') { return draw(); }
    const r = await sb.rpc(t.rpc, argsOf(t));
    if (tok !== P.busy) return;
    if (r.error) P.err = r.error; else P.data = r.data;
    draw();
  }
  function errBox(e) {
    const m = (e && e.message) || '';
    if (missingFn(e)) return `<div class="notice warn mk warn" id="${cid}_err">${esc(T('sqlMissing'))}</div>`;
    if (/not allowed/.test(m)) return `<div class="lockcard" id="${cid}_lock"><span>${esc(T('notAllowed'))}</span></div>`;
    if (/bad_range|bad_input|bad_days|bad_basis|bad_search/.test(m)) return `<div class="notice warn mk warn" id="${cid}_err">${esc(T('badRange'))}</div>`;
    return `<div class="notice warn mk warn" id="${cid}_err">${esc(m || 'error')}<br><button data-act="${cid}_retry">${esc(T('retry'))}</button></div>`;
  }
  const chipNeed = () => `<span class="chip warn">${esc(T('need'))}</span>`;
  function statsHTML(t, d) {
    if (!t.stats) return '';
    return `<div class="stats" id="${cid}_stats">${t.stats.map((s) => {
      const raw = s.get ? s.get(d) : getp(d, s.path); const c = cell({ fmt: s.fmt || 'num', get: () => raw }, {});
      return `<div class="stat mk ${s.tone || ''}"><div class="k">${esc(lab(s.label))}</div><div class="v">${c.t === null ? chipNeed() : esc(c.t)}</div></div>`;
    }).join('')}</div>`;
  }
  function rowsOf(tb, d) { const r = tb.rows ? tb.rows(d) : getp(d, tb.path); return Array.isArray(r) ? r : []; }
  function tableHTML(t, tb, ti, d) {
    const rows = rowsOf(tb, d);
    let h = tb.title ? `<h3 style="margin:14px 0 6px">${esc(lab(tb.title))} <small class="muted">(${rows.length})</small></h3>` : '';
    if (!rows.length) return h + `<p class="muted center pad" id="${cid}_empty_${ti}">${esc(tb.empty ? lab(tb.empty) : T('none'))}</p>`;
    const cols = tb.cols;
    return h + `<div class="card" style="padding:4px 12px" id="${cid}_t${ti}">${rows.map((r, ri) => {
      const head = cell(cols[0], r), tone = tb.tone ? tb.tone(r) : '';
      return `<button class="rp-row mk ${tone}" data-act="${cid}_row" data-t="${ti}" data-i="${ri}" style="display:block;width:100%;text-align:start">
        <span class="nm"><b>${head.t === null ? chipNeed() : esc(head.t)}</b>${cols.slice(1).map((c) => { const v = cell(c, r); return `<small style="display:inline-block;margin-inline-end:10px"><span class="muted">${esc(lab(c.label))}:</span> ${v.t === null ? '<span class="muted">—</span>' : esc(v.t)}</small>`; }).join('')}</span></button>`;
    }).join('')}</div>`;
  }
  function panelHTML(t, d) {
    let h = '';
    const nt = (d && d.notes) || [];
    if (nt.length) h += `<details class="card" style="margin-top:12px" id="${cid}_notes"><summary><b>${esc(T('notes'))}</b></summary><ul>${nt.map((c) => `<li>${esc(noteText(c))}</li>`).join('')}</ul></details>`;
    const as = t.panel ? t.panel(d) : null;
    if (as && as.length) h += `<details class="card" style="margin-top:8px" id="${cid}_assum" open><summary><b>${esc(T('assumptions'))}</b></summary><div class="stack" style="gap:2px">${as.map(([k, v]) => `<div class="row between"><span class="muted">${esc(typeof k === 'string' ? k : lab(k))}</span><b>${isNil(v) ? chipNeed() : esc(String(v))}</b></div>`).join('')}</div></details>`;
    if (d && d.basis) h += `<p class="muted" style="font-size:.85rem" id="${cid}_basis"><b>${esc(T('basis'))}:</b> ${esc(d.basis)}</p>`;
    return h;
  }
  function body(t) {
    if (t.custom) return `<div id="${cid}_custom"></div>`;
    if (P.err) return errBox(P.err);
    for (const i of (t.inputs || [])) if (i.req && norm(P.x[i.k] !== undefined ? P.x[i.k] : (i.def !== undefined ? i.def : '')) === '') return `<div class="notice warn mk warn" id="${cid}_ask">${esc(T('dataNeeded'))}: ${esc(lab(i.label))}</div>`;
    const d = P.data; if (!d) return `<p class="muted" id="${cid}_loading">${esc(T('loading'))}</p>`;
    if (d.data_needed && d.data_needed.length) return `<div class="notice warn mk warn" id="${cid}_need">${esc(T('dataNeeded'))}: ${esc(d.data_needed.join(', '))}</div>${panelHTML(t, d)}`;
    let h = statsHTML(t, d) + (t.beforeTables ? t.beforeTables(d) : '') + t.tables.map((tb, ti) => tableHTML(t, tb, ti, d)).join('');
    if (t.pager) { const tot = Number(d.total || 0), pages = Math.max(Math.ceil(tot / t.pager), 1);
      h += `<div class="row between" style="margin-top:8px"><button data-act="${cid}_pg" data-v="-1" ${P.page <= 0 ? 'disabled' : ''}>${esc(T('prev'))}</button><span class="muted" id="${cid}_pg">${esc(T('page'))} ${P.page + 1} ${esc(T('of'))} ${pages} · ${tot}</span><button data-act="${cid}_pg" data-v="1" ${P.page + 1 >= pages ? 'disabled' : ''}>${esc(T('next'))}</button></div>`; }
    return h + panelHTML(t, d);
  }
  function draw() {
    const t = tabOf();
    const tabs = cfg.tabs.length > 1 ? `<div class="row" role="tablist" style="gap:6px;margin:4px 0;overflow-x:auto;flex-wrap:nowrap;padding-bottom:4px">${cfg.tabs.map((x) => `<button class="tog ${x.k === P.tab ? 'on' : ''}" role="tab" style="flex:0 0 auto;white-space:nowrap"data-act="${cid}_tab" data-v="${x.k}" aria-pressed="${x.k === P.tab}">${esc(lab(x.label))}</button>`).join('')}</div>` : '';
    const bar = `<div class="row" style="gap:6px;justify-content:flex-end;margin:4px 0">${t.rpc && !t.custom ? `<button data-act="${cid}_csv" id="${cid}_csvb" ${P.data ? '' : 'disabled'}>${esc(T('csv'))}</button>` : ''}<button data-act="${cid}_info" id="${cid}_infob" aria-label="${esc(T('info'))}">ⓘ ${esc(T('info'))}</button></div>`;
    shell(lab(cfg.title), `${tabs}<div class="stack" id="${cid}_filters">${filtersHTML(t)}</div>${bar}<h2 style="margin:6px 0">${esc(lab(t.label))}</h2><div id="${cid}_body">${body(t)}</div>`, true);
    if (t.custom && P.data) t.custom(document.getElementById(cid + '_custom'), P, { esc, T, money, numf, cell, noteText, reload: load, sb, toast, fail, openSheet, closeSheet, norm, locName, todayS, LOCS, allLocs });
  }
  // drill sheet
  function rowSheet(ti, ri) {
    const t = tabOf(), tb = t.tables[ti], r = rowsOf(tb, P.data)[ri]; if (!r) return;
    const all = tb.cols.map((c) => { const v = cell(c, r); return `<div class="row between"><span class="muted">${esc(lab(c.label))}</span><b>${v.t === null ? chipNeed() : esc(v.t)}</b></div>`; }).join('');
    const extra = tb.detail ? tb.detail(r, { esc, cell, T, noteText }) : '';
    openSheet(`<h2 style="margin-top:0">${esc(cell(tb.cols[0], r).t || '')}</h2><div class="stack" id="${cid}_sheet">${all}${extra}</div>
      <div id="${cid}_drill"></div>${tb.drill ? `<button class="full" style="margin-top:10px" data-act="${cid}_drill" data-t="${ti}" data-i="${ri}">${esc(T('drill'))}</button>` : ''}<button class="full" style="margin-top:8px" data-act="closesheet">${esc(T('close'))}</button>`);
  }
  async function drill(ti, ri) {
    const t = tabOf(), tb = t.tables[ti], r = rowsOf(tb, P.data)[ri], box = document.getElementById(cid + '_drill'); if (!r || !box) return;
    box.innerHTML = `<p class="muted">${esc(T('loading'))}</p>`;
    const res = await sb.rpc(tb.drill.rpc, tb.drill.args(r, argsOf(t), P));
    if (res.error) { box.innerHTML = errBox(res.error); return; }
    const rows = getp(res.data, tb.drill.path || 'rows') || [];
    box.innerHTML = rows.length ? `<div class="card" id="${cid}_dr" style="padding:4px 12px;margin-top:8px">${rows.map((x) => `<div class="rp-row"><span class="nm"><b>${esc(String(cell(tb.drill.cols[0], x).t ?? '—'))}</b>${tb.drill.cols.slice(1).map((c) => { const v = cell(c, x); return `<small style="display:inline-block;margin-inline-end:10px"><span class="muted">${esc(lab(c.label))}:</span> ${v.t === null ? '—' : esc(v.t)}</small>`; }).join('')}</span></div>`).join('')}</div>` : `<p class="muted center pad">${esc(T('none'))}</p>`;
  }
  // info
  function infoSheet() {
    const t = tabOf(), d = P.data;
    openSheet(`<h2 style="margin-top:0">${esc(lab(t.label))}</h2><div class="stack" id="${cid}_infosheet">
      ${t.info ? `<p>${esc(lab(t.info.what))}</p><p class="muted">${esc(lab(t.info.why))}</p>` : ''}
      ${d && d.basis ? `<p><b>${esc(T('basis'))}:</b> ${esc(d.basis)}</p>` : ''}
      ${d && d.notes && d.notes.length ? `<b>${esc(T('notes'))}</b><ul>${d.notes.map((c) => `<li>${esc(noteText(c))}</li>`).join('')}</ul>` : ''}</div>
      <button class="full" data-act="closesheet">${esc(T('close'))}</button>`);
  }
  // CSV (the server logs the export first)
  async function csv() {
    const t = tabOf(); if (!P.data || !t.rpc) return;
    let d = P.data, all = null;
    if (t.pager) {                                         // the whole filtered log, page by page, up to 20,000 rows
      all = []; let off = 0; const per = 500;
      while (all.length < 20000) { const r = await sb.rpc(t.rpc, Object.assign(argsOf(t), { p_limit: per, p_offset: off })); if (r.error) return fail(r.error); const rows = getp(r.data, t.tables[0].path) || []; all = all.concat(rows); off += per; if (rows.length < per) break; }
    }
    const tables = t.tables.filter((tb) => tb.csv !== false);
    const nrows = (all ? all.length : tables.reduce((a, tb) => a + rowsOf(tb, d).length, 0));
    const lg = await sb.rpc('rptc3_export_log', { p_key: t.exportKey, p_kind: 'csv', p_filters: Object.assign({}, argsOf(t), { tab: t.k }), p_rows: nrows });
    if (lg && lg.error) return toast(/not allowed/.test(lg.error.message || '') ? T('expLock') : (lg.error.message || 'error'));
    const out = [];
    tables.forEach((tb, ti) => {
      if (tables.length > 1) out.push(csvCell(tb.title ? lab(tb.title) : 'table ' + (ti + 1)));
      out.push(tb.cols.map((c) => csvCell(c.csvKey || c.k || lab(c.label))).join(','));
      (ti === 0 && all ? all : rowsOf(tb, d)).forEach((r) => out.push(tb.cols.map((c) => { const v = c.get ? c.get(r) : r[c.k]; return csvCell(v); }).join(',')));
      out.push('');
    });
    const p = (S.ctx && S.ctx.profile) || {};
    [[lab(cfg.title) + ' / ' + lab(t.label)], [T('period'), t.dates ? P.f.from + ' - ' + P.f.to : ''], [T('place'), isNil(P.f.loc) ? T('allPlaces') : locName(Number(P.f.loc))], [T('basis'), d.basis || ''],
      [T('notes'), (d.notes || []).map(noteText).join(' | ')], [T('by'), p.full_name || p.staff_id || ''], [T('at'), new Date().toLocaleString('en-GB', { timeZone: 'Asia/Dhaka' }) + ' (Asia/Dhaka)']]
      .forEach((m) => out.push(m.map(csvCell).join(',')));
    download(`${t.exportKey}-${P.f.from || ''}${P.f.to ? '_' + P.f.to : ''}.csv`, '﻿' + out.join('\r\n') + '\r\n'); toast(T('expDone'));
  }
  Object.assign(H, {
    [cid + '_tab']: async (a) => { P.tab = a.dataset.v; P.page = 0; await load(); },
    [cid + '_row']: (a) => rowSheet(Number(a.dataset.t), Number(a.dataset.i)),
    [cid + '_drill']: (a) => drill(Number(a.dataset.t), Number(a.dataset.i)),
    [cid + '_csv']: csv, [cid + '_info']: infoSheet, [cid + '_retry']: load, [cid + '_run']: () => { readInputs(); P.page = 0; return load(); },
    [cid + '_pg']: async (a) => { P.page = Math.max(P.page + Number(a.dataset.v), 0); await load(); },
  });
  function readInputs() { (tabOf().inputs || []).forEach((i) => { const el = document.getElementById(`${cid}_x_${i.k}`); if (el) P.x[i.k] = norm(el.value); }); }
  document.addEventListener('change', (e) => {
    const id = e.target && e.target.id; if (!id || !id.startsWith(cid + '_') || location.hash.replace(/^#\/?/, '').split('/')[0] !== cfg.route) return;
    if (id === cid + '_loc') { P.f.loc = e.target.value === '' ? null : Number(e.target.value); P.page = 0; load(); }
    else if (id === cid + '_from' || id === cid + '_to') { const f = norm($('#' + cid + '_from').value), t2 = norm($('#' + cid + '_to').value); if (isDate(f) && isDate(t2)) { P.f.from = f; P.f.to = t2; P.page = 0; load(); } }
  });
  return async function view() {
    shell(lab(cfg.title), `<p class="muted">${esc(T('loading'))}</p>`, true);
    try { await B.loadStatic(); } catch (e) { /* defaults */ }
    if (P.f.loc === undefined) P.f.loc = allLocs() ? null : (LOCS()[0] || {}).id;
    if (cfg.onOpen) cfg.onOpen(P, location.hash);
    await load();
  };
}
B.rptkit = { make, X, T, N, noteText, money, numf, cell, csvCell, todayS, addDays, isDate, norm, isNil, missingFn, getp, pages: PAGES, owner, LOCS, allLocs, locName };
})();
