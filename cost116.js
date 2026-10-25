/* Islamia BOS · Step C1 (phases 116/117, tags bos116/bos117): FIVE manufacturing-cost screens. NEW file; no existing file is rewritten
   (ia.js has 5 rec lines, nav.js reads one more grant code, index.html has one script tag).
   #/cost116var    Standard vs actual per run, in money: price / usage / conversion variance and the yield loss. RPC production_variance116 (read only).
   #/cost116queue  Runs still waiting for a real cost (ingredient cost unknown, provisional or incomplete overhead).
                   Re-price a month of pool-mode runs: production_reprice116 (DRY run first, then a second confirm to apply).
                   Re-cost one run whose ingredient had no cost: production_recost116 (DRY first, then confirm).
   #/cost116gl     Pool vs books: pool_vs_gl117 and overhead_trueup117 (what the factory overhead pool, the absorbed part and the expense in the books say). Read only.
   #/cost116drv    Overhead driver per place (loc_cost_driver_set116) and per cost type (cost_type_driver_set116). Owner only (the server decides).
   #/cost116stage  Semi-finished stage split of one recipe: recipe_stage_cost116 (read only).
   Access: cost right only (owner, ITEM_COST view or the view_cost grant); the server checks the same on every call. Each screen says plainly when the rule
   that makes it useful is off (read with B.rule). Nothing is ever applied without a dry run shown first and a second "Yes, apply" tap.
   Handlers are prefixed c6_. Language rule: English mode is all English; Bangla mode keeps common words in English; the mix is Bangla + English words. */
(() => {
'use strict';
const A = window.BOS_APP, B = window.BOS = window.BOS || {};
if (!A || !B.L || (B.cost116 && B.cost116.loaded)) return;
const { sb, S, esc, toast, shell } = A;
const L = B.L, lab = B.lab;
const $ = (s, el) => (el || document).querySelector(s);

const X = {
  loading: L('লোড হচ্ছে…', 'Loading…', 'Loading…'), place: L('জায়গা', 'Place', 'Place'), from: L('থেকে', 'From', 'From'), to: L('পর্যন্ত', 'To', 'To'), month: L('মাস', 'Month', 'Month'),
  show: L('দেখুন', 'Show', 'Show'), none: L('কিছু নেই', 'Nothing to show', 'কিছু নেই'), item: L('আইটেম', 'Item', 'Item'), date: L('ডেট', 'Date', 'Date'), total: L('মোট', 'Total', 'Total'),
  nocost: L('খরচের হিসাব দেখার অনুমতি নেই', 'You do not have the cost right to see this page', 'Cost দেখার permission নেই'),
  noaccess: L('এই কাজের অনুমতি নেই', 'You are not allowed to do this', 'এই কাজের permission নেই'),
  fail: L('আনা যায়নি', 'Could not load', 'Load করা যায়নি'), notinstalled: L('এই অংশের ডেটাবেস এখনও চালু হয়নি', 'The database part is not installed yet', 'Database অংশ এখনও চালু হয়নি'),
  actFail: L('কাজটি হয়নি', 'It did not go through', 'কাজটি হয়নি'), done: L('হয়ে গেছে', 'Done', 'Done'),
  off: L('এই সুইচ বন্ধ আছে', 'This switch is off', 'এই switch বন্ধ আছে'), offHow: L('মালিক "চালু করার গাইড" বা নিয়ম পাতা থেকে চালু করতে পারেন। বন্ধ থাকলে আগের মতোই চলে।', 'The owner can turn it on in the Setup advisor or the Rules page. While it is off everything works as before.', 'Owner "Setup advisor" বা Rules page থেকে চালু করতে পারেন। বন্ধ থাকলে আগের মতোই চলে।'),
  // tabs
  t_var: L('স্ট্যান্ডার্ড বনাম আসল', 'Standard vs actual', 'Standard বনাম actual'), t_queue: L('খরচের অপেক্ষা', 'Cost queue', 'Cost-এর অপেক্ষা'), t_gl: L('পুল বনাম খাতা', 'Pool vs books', 'Pool বনাম books'),
  t_drv: L('ভাগের ভিত্তি', 'Overhead drivers', 'Overhead driver'), t_stage: L('ধাপ অনুযায়ী খরচ', 'Stage cost', 'Stage cost'),
  // switches
  sw_var: L('স্ট্যান্ডার্ড নিজে থেকে সেভ (std_snapshot_auto116)', 'Automatic standard snapshot (std_snapshot_auto116)', 'Standard নিজে থেকে save (std_snapshot_auto116)'),
  sw_varHow: L('বন্ধ থাকলে নতুন রান-এর স্ট্যান্ডার্ড নিজে সেভ হয় না; শুধু হাতে সংরক্ষিত স্ট্যান্ডার্ডের রান তুলনা হবে।', 'While it is off no standard is stored by itself; only runs that have a standard saved by hand can be compared.', 'বন্ধ থাকলে standard নিজে save হয় না; শুধু হাতে save করা standard-এর run তুলনা হবে।'),
  sw_queue: L('অস্থায়ী ওভারহেড (conv_provisional116)', 'Provisional overhead (conv_provisional116)', 'Provisional overhead (conv_provisional116)'),
  sw_queueHow: L('বন্ধ থাকলে পুল না থাকা মাসের রান অস্থায়ী দামে যায় না; অপূর্ণ রানগুলোই তালিকায় আসবে।', 'While it is off a month with no pool is not given a provisional cost; only runs with an incomplete cost are listed.', 'বন্ধ থাকলে pool না থাকা মাসের run provisional দামে যায় না; অপূর্ণ run-ই তালিকায় আসবে।'),
  sw_recost: L('খরচ সরবরাহ গড়ে যাক (cost_supply_to_avg116)', 'Supplied cost reaches the average (cost_supply_to_avg116)', 'Supplied cost গড়ে যাক (cost_supply_to_avg116)'),
  sw_recostHow: L('বন্ধ থাকলে অপেক্ষার তালিকা থেকে দেওয়া খরচ স্টকের গড়ে যায় না, তাই রান নতুন করে খরচ করলে ঠিক সংখ্যা নাও আসতে পারে।', 'While it is off a cost supplied from the waiting list does not move the stock average, so a re-cost may not give the real number.', 'বন্ধ থাকলে waiting list থেকে দেওয়া cost stock-এর গড়ে যায় না, তাই re-cost-এ ঠিক সংখ্যা নাও আসতে পারে।'),
  sw_gl: L('পুল খাতায় পোস্ট (pool_gl_post117)', 'Pool posted to the books (pool_gl_post117)', 'Pool books-এ post (pool_gl_post117)'),
  sw_glHow: L('বন্ধ থাকলে ওভারহেড পুল খাতায় খরচ হিসেবে যায় না; "খাতায় খরচ" শূন্য দেখালে এটাই কারণ হতে পারে।', 'While it is off the overhead pool is not an expense in the books; that may be why "expense in books" shows zero.', 'বন্ধ থাকলে overhead pool books-এ expense হয় না; "books-এ খরচ" শূন্য দেখালে এটাই কারণ হতে পারে।'),
  sw_drv: L('পুলের ভাগের ভিত্তি (pool_drivers116)', 'Pool drivers (pool_drivers116)', 'Pool driver (pool_drivers116)'),
  sw_drvHow: L('বন্ধ থাকলে নিচের পছন্দ সেভ হয় কিন্তু হিসাবে কাজ করে না; ওভারহেড আগের নিয়মেই ভাগ হয়।', 'While it is off your choice below is saved but not used; overhead is spread the old way.', 'বন্ধ থাকলে নিচের choice save হয় কিন্তু কাজ করে না; overhead আগের নিয়মেই ভাগ হয়।'),
  sw_stage: L('তৈরি পণ্য উপকরণ (semi_finished_ingredient116)', 'Semi-finished as ingredient (semi_finished_ingredient116)', 'Semi-finished ingredient (semi_finished_ingredient116)'),
  sw_stageHow: L('বন্ধ থাকলে তৈরি পণ্য রেসিপির উপকরণ হতে পারে না, তাই ধাপ ভাগ সাধারণত খালি।', 'While it is off a finished good cannot be an ingredient, so the stage split is normally empty.', 'বন্ধ থাকলে finished good ingredient হতে পারে না, তাই stage split সাধারণত খালি।'),
  // variance
  v_intro: L('প্রতিটি রানের আসল খরচ বনাম তখনকার স্ট্যান্ডার্ড খরচ, টাকায়। ধনাত্মক = স্ট্যান্ডার্ডের চেয়ে বেশি খরচ।', 'Actual cost of each run against the standard that was stored when it was made, in money. Positive = dearer than the standard.', 'প্রতিটি run-এর actual cost বনাম তখনকার standard cost, টাকায়। ধনাত্মক = standard-এর চেয়ে বেশি খরচ।'),
  v_latest: L('সবচেয়ে নতুন স্ট্যান্ডার্ড ধরুন (পুরনো রান দেখতে)', 'Use the newest standard (to look back at old runs)', 'সবচেয়ে নতুন standard ধরুন (পুরনো run দেখতে)'),
  v_price: L('দামের ফারাক', 'Price variance', 'Price variance'), v_usage: L('ব্যবহারের ফারাক', 'Usage variance', 'Usage variance'), v_conv: L('রূপান্তরের ফারাক', 'Conversion variance', 'Conversion variance'),
  v_tvar: L('মোট ফারাক', 'Total variance', 'Total variance'), v_act: L('আসল খরচ', 'Actual cost', 'Actual cost'), v_std: L('স্ট্যান্ডার্ড খরচ', 'Standard cost', 'Standard cost'),
  v_yl: L('ফলনের ক্ষতি (টাকায়)', 'Yield loss (money)', 'Yield loss (টাকায়)'), v_batches: L('ব্যাচ', 'Batches', 'Batches'), v_theo: L('সম্ভাব্য আউটপুট', 'Theoretical output', 'Theoretical output'),
  v_out: L('আসল আউটপুট', 'Output', 'Output'), v_runs: L('রান', 'Runs', 'Runs'), v_withstd: L('স্ট্যান্ডার্ড আছে এমন রান', 'Runs with a standard', 'Standard আছে এমন run'),
  v_ylnote: L('ফলনের ক্ষতি আসল খরচে মাপা একটি মেমো; এটি ব্যবহারের ফারাকের ভেতরেই আছে, আলাদা করে যোগ করবেন না।', 'Yield loss is a memo at actual cost; it is already inside the usage variance, do not add it again.', 'Yield loss actual cost-এ মাপা memo; এটি usage variance-এর ভেতরেই আছে, আলাদা যোগ করবেন না।'),
  w_ingredient_cost_unknown: L('উপকরণের খরচ অজানা', 'Ingredient cost unknown', 'Ingredient cost অজানা'), w_no_standard: L('স্ট্যান্ডার্ড নেই', 'No standard stored', 'Standard নেই'),
  w_standard_incomplete: L('স্ট্যান্ডার্ড অপূর্ণ', 'Standard incomplete', 'Standard অপূর্ণ'), w_ok: L('তুলনা হয়েছে', 'Compared', 'Compared'), w_prov: L('অস্থায়ী ওভারহেড', 'Provisional overhead', 'Provisional overhead'),
  // queue
  q_intro: L('যেসব রানের আসল খরচ এখনও ঠিক হয়নি: উপকরণের দাম অজানা, বা ওভারহেড অস্থায়ী/অপূর্ণ।', 'Runs whose real cost is not settled yet: an ingredient with no cost, or overhead that is provisional or incomplete.', 'যেসব run-এর real cost এখনও ঠিক হয়নি: ingredient-এর দাম অজানা, বা overhead provisional/অপূর্ণ।'),
  q_output: L('আউটপুট', 'Output', 'Output'), q_unit: L('একক খরচ', 'Unit cost', 'Unit cost'), q_mode: L('ওভারহেড পদ্ধতি', 'Overhead mode', 'Overhead mode'), q_reason: L('কারণ', 'Reason', 'Reason'),
  r_ingredient_cost_unknown: L('উপকরণের খরচ অজানা', 'Ingredient cost unknown', 'Ingredient cost অজানা'), r_conversion_provisional: L('ওভারহেড অস্থায়ী', 'Overhead provisional', 'Overhead provisional'),
  r_conversion_incomplete: L('ওভারহেড অপূর্ণ', 'Overhead incomplete', 'Overhead অপূর্ণ'),
  q_recost: L('নতুন করে খরচ', 'Re-cost', 'Re-cost'), q_none: L('অপেক্ষায় কোনো রান নেই ✓', 'No run is waiting ✓', 'অপেক্ষায় কোনো run নেই ✓'),
  rp_title: L('মাসের ওভারহেড নতুন করে ধরুন', 'Re-price the overhead of a month', 'মাসের overhead নতুন করে ধরুন'),
  rp_intro: L('শুধু ওই মাসের পুল-পদ্ধতির রান। প্রথমে "পরীক্ষা" চাপুন: কিছুই বদলায় না, কী হবে তা দেখায়। ঠিক মনে হলে "প্রয়োগ করুন" চাপুন, তারপর আবার নিশ্চিত করুন।', 'Only the pool-mode runs of that month. Press "Check first": nothing changes, it shows what would happen. If it looks right press "Apply", then confirm once more.', 'শুধু ওই মাসের pool-mode run। আগে "Check first" চাপুন: কিছুই বদলায় না, কী হবে দেখায়। ঠিক মনে হলে "Apply" চাপুন, তারপর আবার confirm করুন।'),
  rp_check: L('পরীক্ষা করুন (কিছু বদলাবে না)', 'Check first (changes nothing)', 'Check first (কিছু বদলাবে না)'), rp_apply: L('প্রয়োগ করুন', 'Apply', 'Apply'),
  rp_dryTag: L('শুধু পরীক্ষা: কিছু বদলায়নি', 'Dry run only: nothing was changed', 'Dry run: কিছু বদলায়নি'), rp_doneTag: L('প্রয়োগ হয়েছে', 'Applied', 'Applied'),
  rp_old: L('আগের ওভারহেড', 'Old overhead', 'Old overhead'), rp_new: L('নতুন ওভারহেড', 'New overhead', 'New overhead'), rp_delta: L('ফারাক', 'Difference', 'Difference'),
  rp_inv: L('স্টকে যাবে', 'To stock', 'To stock'), rp_cogs: L('বিক্রিত মালের খরচে', 'To cost of goods sold', 'To cost of goods sold'), rp_runs: L('রান', 'Runs', 'Runs'),
  rp_skipped: L('বাদ গেছে', 'Skipped', 'Skipped'), rp_nothing: L('এই মাসে নতুন করে ধরার মতো রান নেই', 'No run to re-price in this month', 'এই মাসে re-price করার মতো run নেই'),
  rp_ask: L('সত্যিই প্রয়োগ করবেন? স্টকের গড় ও খাতা বদলাবে।', 'Really apply? The stock average and the books will change.', 'সত্যিই apply করবেন? Stock-এর গড় ও books বদলাবে।'),
  rp_yes: L('হ্যাঁ, প্রয়োগ করুন', 'Yes, apply', 'হ্যাঁ, apply করুন'), rp_no: L('না, থামুন', 'No, stop', 'না, থামুন'), rp_stale: L('মাস বা জায়গা বদলেছে; আবার পরীক্ষা করুন', 'The month or place changed; check again first', 'মাস বা place বদলেছে; আবার check করুন'),
  s_period_closed_or_before_start: L('হিসাবের মাস বন্ধ বা শুরুর আগে', 'Period closed or before the books start', 'Period বন্ধ বা books শুরুর আগে'), s_ingredient_cost_unknown: L('উপকরণের খরচ অজানা', 'Ingredient cost unknown', 'Ingredient cost অজানা'),
  s_pool_missing: L('এই মাসের পুল নেই', 'No pool for the month', 'এই মাসের pool নেই'),
  rc_title: L('একটি রান নতুন করে খরচ করুন', 'Re-cost one run', 'একটি run re-cost করুন'), rc_lines: L('উপকরণ', 'Ingredients', 'Ingredients'), rc_qty: L('পরিমাণ', 'Qty', 'Qty'), rc_cost: L('একক দাম', 'Unit cost', 'Unit cost'),
  rc_amt: L('টাকা', 'Amount', 'Amount'), rc_known: L('জানা উপকরণ খরচ', 'Known material cost', 'Known material cost'), rc_added: L('নতুন যোগ', 'Added', 'Added'), rc_new: L('নতুন উপকরণ খরচ', 'New material cost', 'New material cost'),
  rc_conv: L('ওভারহেড', 'Overhead', 'Overhead'), rc_ucn: L('নতুন একক খরচ', 'New unit cost', 'New unit cost'), rc_ask: L('সত্যিই প্রয়োগ করবেন? রানের খরচ ও খাতার এন্ট্রি বদলাবে।', 'Really apply? The run cost and its books entry will change.', 'সত্যিই apply করবেন? Run-এর cost ও books entry বদলাবে।'),
  rc_nothing: L('এই রানের খরচ আগেই সম্পূর্ণ; কিছু করার নেই', 'This run is already fully costed; nothing to do', 'এই run-এর cost আগেই সম্পূর্ণ; কিছু করার নেই'), rc_close: L('বন্ধ করুন', 'Close', 'Close'),
  rc_posted: L('খাতার এন্ট্রি আবার পোস্ট হয়েছে', 'Books entry re-posted', 'Books entry re-post হয়েছে'),
  // pool vs books
  g_intro: L('ওভারহেড পুলে কত, পণ্যের খরচে কত ধরা হয়েছে, আর খাতায় খরচ হিসেবে কত গেছে — পাশাপাশি।', 'What the overhead pool holds, what was charged to products, and what is an expense in the books, side by side.', 'Overhead pool-এ কত, product-এর cost-এ কত ধরা হয়েছে, আর books-এ expense হিসেবে কত গেছে — পাশাপাশি।'),
  g_type: L('খরচের ধরন', 'Cost type', 'Cost type'), g_pool: L('পুল', 'Pool', 'Pool'), g_posted: L('খাতায় পোস্ট', 'Posted to books', 'Books-এ post'), g_poolTot: L('পুল মোট', 'Pool total', 'Pool total'),
  g_postedTot: L('পোস্ট মোট', 'Posted total', 'Posted total'), g_abs: L('পণ্যে ধরা (খাতা)', 'Absorbed into products (books)', 'Product-এ ধরা (books)'), g_exp: L('খাতায় খরচ', 'Expense in books', 'Books-এ expense'),
  g_expPool: L('তার মধ্যে পুল থেকে', 'of which from the pool', 'তার মধ্যে pool থেকে'), g_expOther: L('অন্য খরচ', 'of which other', 'তার মধ্যে অন্য'), g_unabs: L('P&L-এ অশোষিত', 'Unabsorbed in the P&L', 'P&L-এ unabsorbed'),
  g_warn: L('সতর্কতা: পণ্যে যত ওভারহেড ধরা হয়েছে, খাতায় তত খরচ নেই। পুল খাতায় পোস্ট চালু করুন, অথবা খরচটি এক্সপেন্স হিসেবে লিখুন।', 'Warning: products were charged more overhead than is an expense in the books. Turn on the pool posting, or enter the cost as an expense.', 'Warning: product-এ যত overhead ধরা হয়েছে books-এ তত expense নেই। Pool posting চালু করুন, অথবা cost-টি expense হিসেবে লিখুন।'),
  g_ok: L('পণ্যে ধরা অঙ্ক খাতার খরচের মধ্যেই আছে ✓', 'The overhead charged to products is covered by expense in the books ✓', 'Product-এ ধরা অঙ্ক books-এর expense-এর মধ্যেই আছে ✓'),
  g_tu: L('মাসের হিসাব: প্রকৃত বনাম ধরা', 'Month true-up: actual against absorbed', 'মাসের true-up: actual বনাম absorbed'), g_act: L('প্রকৃত', 'Actual', 'Actual'), g_absorbed: L('ধরা হয়েছে', 'Absorbed', 'Absorbed'),
  g_unabsorbed: L('ধরা হয়নি', 'Unabsorbed', 'Unabsorbed'), g_over: L('বেশি ধরা হয়েছে (স্টকের দামে থেকে যায়)', 'Over-absorbed (stays in stock value)', 'বেশি ধরা হয়েছে (stock value-তে থাকে)'),
  // drivers
  d_intro: L('কারখানার ওভারহেড কিসের ভিত্তিতে ভাগ হবে: আউটপুট কেজি, আউটপুটের সংখ্যা, ব্যাচ, বা শ্রম ঘণ্টা। শুধু মালিক বদলাতে পারেন।', 'What the factory overhead is spread by: output kg, output units, batches or labour hours. Only the owner can change it.', 'Factory overhead কিসের ভিত্তিতে ভাগ হবে: output kg, output unit, batch, বা labour hour। শুধু owner বদলাতে পারেন।'),
  d_ownerOnly: L('শুধু মালিক এটি বদলাতে পারেন', 'Only the owner can change this', 'শুধু owner এটি বদলাতে পারেন'),
  d_none: L('(কোনোটি নয়)', '(none)', '(কোনোটি নয়)'), d_output_kg: L('আউটপুট কেজি', 'Output kg', 'Output kg'), d_output_units: L('আউটপুট সংখ্যা', 'Output units', 'Output units'),
  d_batches: L('ব্যাচ', 'Batches', 'Batches'), d_labour_hours: L('শ্রম ঘণ্টা', 'Labour hours', 'Labour hours'),
  d_byPlace: L('জায়গা অনুযায়ী', 'By place', 'Place অনুযায়ী'), d_byType: L('খরচের ধরন অনুযায়ী', 'By cost type', 'Cost type অনুযায়ী'), d_driver: L('ভিত্তি', 'Driver', 'Driver'),
  d_nUnits: L('স্বাভাবিক মাসিক সংখ্যা', 'Normal monthly units', 'Normal monthly units'), d_nBatches: L('স্বাভাবিক মাসিক ব্যাচ', 'Normal monthly batches', 'Normal monthly batches'), d_nHours: L('স্বাভাবিক মাসিক ঘণ্টা', 'Normal monthly hours', 'Normal monthly hours'),
  d_save: L('সেভ', 'Save', 'Save'), d_saved: L('সংরক্ষিত', 'Saved', 'Saved'), d_bad: L('সংখ্যা ঠিক নয়', 'The number is not valid', 'সংখ্যা ঠিক নয়'),
  // stage
  st_intro: L('একটি রেসিপির উপকরণ খরচ: কতটা তৈরি-পণ্য (আগের ধাপ) থেকে, কতটা অন্য উপকরণ থেকে, আর আগের ধাপের শেষ রানের খরচ কত।', 'The material cost of one recipe: how much comes from semi-finished goods (an earlier stage), how much from other ingredients, and what the earlier stage cost on its last run.', 'একটি recipe-এর material cost: কত semi-finished (আগের stage) থেকে, কত অন্য ingredient থেকে, আর আগের stage-এর শেষ run-এর cost কত।'),
  st_recipe: L('রেসিপি', 'Recipe', 'Recipe'), st_pick: L('রেসিপি বাছুন', 'Pick a recipe', 'Recipe বাছুন'), st_semi: L('তৈরি-পণ্য থেকে', 'From semi-finished', 'Semi-finished থেকে'), st_other: L('অন্য উপকরণ', 'Other ingredients', 'Other ingredients'),
  st_unknown: L('কিছু উপকরণের খরচ অজানা, তাই অঙ্ক কম হতে পারে', 'Some ingredient has no cost, so the amounts may be too low', 'কিছু ingredient-এর cost অজানা, তাই অঙ্ক কম হতে পারে'),
  st_kind: L('ধরন', 'Kind', 'Kind'), st_avg: L('গড় দাম', 'Avg cost', 'Avg cost'), st_semiTag: L('তৈরি-পণ্য', 'Semi-finished', 'Semi-finished'), st_lastRun: L('আগের ধাপের শেষ রান', 'Last run of that stage', 'Last run of that stage'),
  st_mat: L('উপকরণ খরচ', 'Material', 'Material'), st_conv: L('ওভারহেড', 'Overhead', 'Overhead'), st_unit: L('একক খরচ', 'Unit cost', 'Unit cost'), st_noRecipe: L('কোনো রেসিপি নেই', 'No recipe', 'কোনো recipe নেই'),
};
const T = (k) => lab(X[k]);
const TL = (pre, k) => (X[pre + k] ? lab(X[pre + k]) : String(k || ''));

/* ---------- helpers ---------- */
const own = () => !!(S.ctx && S.ctx.is_owner);
const rule = (k) => { try { return B.rule ? B.rule(k, false) === true : false; } catch (e) { return false; } };
const today = () => new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const thisMonth = () => today().slice(0, 7);
const fm = (n, d) => (n === null || n === undefined || n === '' || !Number.isFinite(Number(n)) ? '—' : Number(n).toLocaleString('en-IN', { maximumFractionDigits: d === undefined ? 2 : d }));
const nm = (o, a, b) => lab({ bn: o[a] || o[b], mix: o[a] || o[b], en: o[b] || o[a] });
const colorNum = (v) => (Number(v) > 0 ? ' style="color:var(--bad,#b3261e)"' : '');   // for a variance a positive number is the bad direction
const th = (k, cls) => `<th${cls ? ` class="${cls}"` : ''}>${esc(T(k))}</th>`;
const chip = (text, tone) => `<span class="chip ${tone || ''}">${esc(text)}</span>`;
const monthRange = (ym) => { const f = ym + '-01', d = new Date(Date.UTC(+ym.slice(0, 4), +ym.slice(5, 7), 0)); return [f, d.toISOString().slice(0, 10)]; };
async function costRight() {
  if (own()) return true;
  try { const p = S.ctx && S.ctx.perms && S.ctx.perms.ITEM_COST; if (p && p.view) return true; } catch (e) { /* fall through */ }
  try { return !!(await A.hasAnyGrant(['view_cost'])); } catch (e) { return false; }
}
function errMsg(e) {
  const m = String((e && e.message) || e || '');
  if (/does not exist|schema cache|PGRST202|Could not find the function/i.test(m)) return T('notinstalled');
  if (/not allowed|permission/i.test(m)) return T('noaccess');
  return T('fail');
}
const actMsg = (e) => { const m = errMsg(e); return m === T('fail') ? T('actFail') + (e && e.message ? ' (' + String(e.message).slice(0, 80) + ')' : '') : m; };
let LOCS = null, RECS = null;
async function loadLocs() {
  if (LOCS) return LOCS;
  try { const r = await sb.from('locations').select('id,name_bn,name_en,kind').order('id'); LOCS = (r && r.data) || []; } catch (e) { LOCS = []; }
  return LOCS;
}
const defLoc = () => { const f = (LOCS || []).find((l) => l.kind === 'factory') || (LOCS || [])[0]; return f ? f.id : ''; };
const locSel = (sel) => `<select id="c6_l" aria-label="${esc(T('place'))}">${(LOCS || []).map((l) => `<option value="${l.id}" ${String(l.id) === String(sel) ? 'selected' : ''}>${esc(nm(l, 'name_bn', 'name_en'))}</option>`).join('')}</select>`;
const TABS = [['cost116var', 't_var'], ['cost116queue', 't_queue'], ['cost116gl', 't_gl'], ['cost116drv', 't_drv'], ['cost116stage', 't_stage']];
const tabBar = (cur) => `<div class="row wrap">${TABS.map(([r, k]) => `<a class="tog ${r === cur ? 'on' : ''}" href="#/${r}" ${r === cur ? 'aria-current="page"' : ''}>${esc(T(k))}</a>`).join('')}</div>`;
const swBanner = (key, nameK, howK) => (rule(key) ? '' : `<div class="notice warn" data-c6-off="${esc(key)}"><b>${esc(T(nameK))}</b> — ${esc(T('off'))}.<br>${esc(T(howK))}<br><span class="muted">${esc(T('offHow'))}</span></div>`);
// one gate for every screen: rules loaded, cost right checked, then the screen paints into #c6_res
async function open(route, titleK, introK, sw, head, run) {
  shell(T(titleK), `<p class="muted center pad">${esc(T('loading'))}</p>`, true);
  try { if (B.loadStatic) await B.loadStatic(); } catch (e) { /* rules fall back to defaults */ }
  if (!(await costRight())) { shell(T(titleK), `<div class="notice bad" id="c6_nocost">${esc(T('nocost'))}</div>`, true); return; }
  await loadLocs();
  shell(T(titleK), `${tabBar(route)}<p class="muted">${esc(T(introK))}</p>${sw ? swBanner(sw[0], sw[1], sw[2]) : ''}${head}<div id="c6_res"></div>`, true);
  await run();
}
const res = (html) => { const el = $('#c6_res'); if (el) el.innerHTML = html; };
const val = (id) => { const e = $('#' + id); return e ? e.value : ''; };

/* ======================= 1. standard vs actual ======================= */
const V = { loc: '', from: null, to: null, latest: false, data: null };
function vHTML() {
  const d = V.data; if (!d) return '';
  const t = d.totals || {}, rows = d.rows || [];
  const card = (k, v, strong) => `<div class="card"><div class="muted">${esc(T(k))}</div><div${strong ? ' style="font-weight:700"' : ''}><span${k === 'v_act' || k === 'v_std' ? '' : colorNum(v)}>${esc(fm(v))}</span></div></div>`;
  const head = `<tr>${th('date')}${th('item')}${th('v_batches', 'n')}${th('v_theo', 'n')}${th('v_out', 'n')}${th('v_act', 'n')}${th('v_std', 'n')}${th('v_price', 'n')}${th('v_usage', 'n')}${th('v_conv', 'n')}${th('v_tvar', 'n')}${th('v_yl', 'n')}<th></th></tr>`;
  const body = rows.map((r) => {
    const st = r.complete ? chip(T('w_ok'), 'ok') : chip(TL('w_', r.why || 'no_standard'), 'warn');
    return `<tr><td>${esc(String(r.made_at || '').slice(0, 10))}</td><td style="text-align:left"><b>${esc(r.code)}</b></td><td class="n">${esc(fm(r.batches, 3))}</td><td class="n">${esc(fm(r.theoretical_output, 3))}</td><td class="n">${esc(fm(r.output, 3))}</td>`
      + `<td class="n">${esc(fm(r.actual_total))}</td><td class="n">${esc(fm(r.standard_total))}</td><td class="n"${colorNum(r.price_var)}>${esc(fm(r.price_var))}</td><td class="n"${colorNum(r.usage_var)}>${esc(fm(r.usage_var))}</td>`
      + `<td class="n"${colorNum(r.conv_var)}>${esc(fm(r.conv_var))}</td><td class="n"${colorNum(r.total_var)}><b>${esc(fm(r.total_var))}</b></td><td class="n">${esc(fm(r.yield_loss_money))}</td><td>${st}${r.conversion_provisional ? ' ' + chip(T('w_prov'), 'info') : ''}</td></tr>`;
  }).join('');
  return `<div class="row wrap">${chip(T('v_runs') + ': ' + fm(d.runs, 0))} ${chip(T('v_withstd') + ': ' + fm(d.runs_with_standard, 0))}</div>
    <div class="stack" id="c6_tot">${card('v_price', t.price_var)}${card('v_usage', t.usage_var)}${card('v_conv', t.conv_var)}${card('v_tvar', t.total_var, true)}${card('v_act', t.actual_total)}${card('v_std', t.standard_total)}${card('v_yl', t.yield_loss_money)}</div>
    <p class="muted">${esc(T('v_ylnote'))}</p>
    ${rows.length ? `<div class="scrollx"><table class="bz" id="c6_tbl"><thead>${head}</thead><tbody>${body}</tbody></table></div>` : `<p class="muted center pad">${esc(T('none'))}</p>`}`;
}
async function loadV() {
  res(`<p class="muted center pad">${esc(T('loading'))}</p>`);
  try {
    const r = await sb.rpc('production_variance116', { p_loc: Number(V.loc), p_from: V.from, p_to: V.to, p_use_latest: V.latest });
    if (r && r.error) throw r.error;
    V.data = r.data; res(vHTML());
  } catch (e) { V.data = null; res(`<div class="notice bad">${esc(errMsg(e))}</div>`); }
}
async function viewVar() {
  V.from = V.from || thisMonth() + '-01'; V.to = V.to || today();
  await open('cost116var', 't_var', 'v_intro', ['std_snapshot_auto116', 'sw_var', 'sw_varHow'], '', async () => {
    V.loc = V.loc || defLoc();
    const h = $('#c6_res'); if (h) h.insertAdjacentHTML('beforebegin', `<div class="row wrap">${locSel(V.loc)}<label>${esc(T('from'))}<input type="date" id="c6_f" value="${esc(V.from)}"></label><label>${esc(T('to'))}<input type="date" id="c6_t" value="${esc(V.to)}"></label></div>
      <label class="row"><input type="checkbox" id="c6_latest" ${V.latest ? 'checked' : ''}> ${esc(T('v_latest'))}</label><div class="row wrap"><button class="primary" data-act="c6_vgo">${esc(T('show'))}</button></div>`);
    await loadV();
  });
}

/* ======================= 2. cost queue, re-price, re-cost ======================= */
const Q = { loc: '', month: null, rows: null, dry: null, dryKey: '', confirm: false, rc: null };
function qHTML() {
  const rows = Q.rows;
  if (!rows) return '';
  const body = rows.map((r) => `<tr><td>${esc(String(r.made_at || '').slice(0, 10))}</td><td style="text-align:left"><b>${esc(r.code)}</b></td><td class="n">${esc(fm(r.output, 3))}</td><td class="n">${esc(fm(r.unit_cost, 4))}</td><td>${esc(r.conversion_mode || '—')}</td>`
    + `<td>${chip(TL('r_', r.reason), r.reason === 'conversion_provisional' ? 'info' : 'warn')}</td><td>${r.reason === 'ingredient_cost_unknown' ? `<button data-act="c6_recost" data-v="${esc(r.run_id)}">${esc(T('q_recost'))}</button>` : ''}</td></tr>`).join('');
  return rows.length ? `<div class="scrollx"><table class="bz" id="c6_qtbl"><thead><tr>${th('date')}${th('item')}${th('q_output', 'n')}${th('q_unit', 'n')}${th('q_mode')}${th('q_reason')}<th></th></tr></thead><tbody>${body}</tbody></table></div>`
    : `<div class="notice ok">${esc(T('q_none'))}</div>`;
}
function rpHTML() {
  const d = Q.dry; if (!d) return '';
  const rows = d.rows || [], sk = d.skipped || [];
  const body = rows.map((r) => `<tr><td>${esc(String(r.made_at || '').slice(0, 10))}</td><td class="n">${esc(fm(r.old_conversion))}</td><td class="n">${esc(fm(r.new_conversion))}</td><td class="n"${colorNum(r.delta)}>${esc(fm(r.delta))}</td><td class="n">${esc(fm(r.to_inventory))}</td><td class="n">${esc(fm(r.to_cogs))}</td></tr>`).join('');
  const skipped = sk.length ? `<p class="muted">${esc(T('rp_skipped'))}: ${sk.map((s) => esc(TL('s_', s.why))).join(', ')} (${sk.length})</p>` : '';
  const tag = d.dry ? chip(T('rp_dryTag'), 'info') : chip(T('rp_doneTag'), 'ok');
  const act = d.dry && Number(d.runs) > 0 ? (Q.confirm
    ? `<div class="notice warn" id="c6_rpask">${esc(T('rp_ask'))} <b>${esc(fm(d.total_delta))}</b><div class="row wrap"><button class="primary" data-act="c6_rp_yes">${esc(T('rp_yes'))}</button><button data-act="c6_rp_no">${esc(T('rp_no'))}</button></div></div>`
    : `<div class="row wrap"><button class="primary" data-act="c6_rp_apply">${esc(T('rp_apply'))}</button></div>`) : '';
  return `<div class="card" id="c6_rp">${tag} <b>${esc(T('rp_runs'))}: ${esc(fm(d.runs, 0))}</b> · ${esc(T('total'))} ${esc(T('rp_delta'))}: <b>${esc(fm(d.total_delta))}</b>
    ${rows.length ? `<div class="scrollx"><table class="bz"><thead><tr>${th('date')}${th('rp_old', 'n')}${th('rp_new', 'n')}${th('rp_delta', 'n')}${th('rp_inv', 'n')}${th('rp_cogs', 'n')}</tr></thead><tbody>${body}</tbody></table></div>` : `<p class="muted">${esc(T('rp_nothing'))}</p>`}
    ${skipped}${act}</div>`;
}
function rcHTML() {
  const d = Q.rc; if (!d) return '';
  if (d.nothing_to_do) return `<div class="card" id="c6_rc"><div class="notice ok">${esc(T('rc_nothing'))}</div><div class="row wrap"><button data-act="c6_rc_close">${esc(T('rc_close'))}</button></div></div>`;
  const lines = (d.lines || []).map((l) => `<tr><td style="text-align:left"><b>${esc(l.code)}</b></td><td class="n">${esc(fm(l.qty, 3))}</td><td class="n">${esc(fm(l.unit_cost, 4))}</td><td class="n">${esc(fm(l.amount))}</td></tr>`).join('');
  const tag = d.dry ? chip(T('rp_dryTag'), 'info') : chip(T('rp_doneTag'), 'ok');
  const sums = d.dry ? `<div class="muted">${esc(T('rc_known'))}: ${esc(fm(d.material_known))} · ${esc(T('rc_added'))}: ${esc(fm(d.material_added))} · ${esc(T('rc_new'))}: <b>${esc(fm(d.material_new))}</b> · ${esc(T('rc_conv'))}: ${esc(fm(d.conversion))} · ${esc(T('rc_ucn'))}: <b>${esc(fm(d.unit_cost_new, 4))}</b></div>`
    : `<div class="muted">${esc(T('rc_new'))}: <b>${esc(fm(d.material_new))}</b> · ${esc(T('rc_conv'))}: ${esc(fm(d.conversion))} · ${esc(T('rc_ucn'))}: <b>${esc(fm(d.unit_cost, 4))}</b>${d.journal_reposted ? ' · ' + esc(T('rc_posted')) : ''}</div>`;
  const act = d.dry ? (Q.rcAsk
    ? `<div class="notice warn" id="c6_rcask">${esc(T('rc_ask'))}<div class="row wrap"><button class="primary" data-act="c6_rc_yes">${esc(T('rp_yes'))}</button><button data-act="c6_rc_close">${esc(T('rp_no'))}</button></div></div>`
    : `<div class="row wrap"><button class="primary" data-act="c6_rc_apply">${esc(T('rp_apply'))}</button><button data-act="c6_rc_close">${esc(T('rc_close'))}</button></div>`)
    : `<div class="row wrap"><button data-act="c6_rc_close">${esc(T('rc_close'))}</button></div>`;
  return `<div class="card" id="c6_rc"><h3>${esc(T('rc_title'))}</h3>${tag}<div class="scrollx"><table class="bz"><thead><tr>${th('rc_lines')}${th('rc_qty', 'n')}${th('rc_cost', 'n')}${th('rc_amt', 'n')}</tr></thead><tbody>${lines}</tbody></table></div>${sums}${act}</div>`;
}
const qPaint = () => { const e = $('#c6_qres'); if (e) e.innerHTML = `${rcHTML()}${qHTML()}`; const p = $('#c6_rpres'); if (p) p.innerHTML = rpHTML(); };
async function loadQ() {
  const e = $('#c6_qres'); if (e) e.innerHTML = `<p class="muted center pad">${esc(T('loading'))}</p>`;
  try {
    const [f, t] = monthRange(Q.month);
    const r = await sb.rpc('production_cost_queue116', { p_loc: Number(Q.loc), p_from: f, p_to: t });
    if (r && r.error) throw r.error;
    Q.rows = Array.isArray(r.data) ? r.data : []; qPaint();
  } catch (er) { Q.rows = null; if (e) e.innerHTML = `<div class="notice bad">${esc(errMsg(er))}</div>`; }
}
async function viewQueue() {
  Q.month = Q.month || thisMonth();
  await open('cost116queue', 't_queue', 'q_intro', ['conv_provisional116', 'sw_queue', 'sw_queueHow'], '', async () => {
    Q.loc = Q.loc || defLoc();
    const h = $('#c6_res'); if (!h) return;
    h.innerHTML = `<div class="row wrap">${locSel(Q.loc)}<label>${esc(T('month'))}<input type="month" id="c6_m" value="${esc(Q.month)}"></label><button class="primary" data-act="c6_qgo">${esc(T('show'))}</button></div>
      <div id="c6_qres"></div>
      <h3>${esc(T('rp_title'))}</h3><p class="muted">${esc(T('rp_intro'))}</p>
      <div class="row wrap"><button class="primary" data-act="c6_rp_check">${esc(T('rp_check'))}</button></div><div id="c6_rpres"></div>`;
    await loadQ();
  });
}
const rpKey = () => Q.loc + '|' + Q.month;
async function runRp(dry) {
  const r = await sb.rpc('production_reprice116', { p_loc: Number(Q.loc), p_month: Q.month + '-01', p_dry: dry });
  if (r && r.error) throw r.error;
  return r.data;
}

/* ======================= 3. pool vs books ======================= */
const G = { loc: '', month: null, gl: null, tu: null };
function gHTML() {
  const g = G.gl, tu = G.tu; if (!g) return '';
  const rows = g.rows || [];
  const body = rows.map((r) => `<tr><td style="text-align:left">${esc(lab({ bn: r.label_en || r.type, mix: r.label_en || r.type, en: r.label_en || r.type }))} <span class="muted">${esc(r.type)}</span></td><td class="n">${esc(fm(r.pool))}</td><td class="n">${esc(fm(r.posted))}</td></tr>`).join('');
  const kv = (k, v, bold) => `<div class="card"><div class="muted">${esc(T(k))}</div><div${bold ? ' style="font-weight:700"' : ''}>${esc(fm(v))}</div></div>`;
  const warn = g.absorbed_exceeds_expense ? `<div class="notice warn" id="c6_glwarn">${esc(T('g_warn'))}</div>` : `<div class="notice ok">${esc(T('g_ok'))}</div>`;
  let tuH = '';
  if (tu && !tu.error) {
    const tr = (tu.rows || []).map((r) => `<tr><td style="text-align:left">${esc(r.label_en ? lab({ bn: r.label_bn || r.label_en, mix: r.label_bn || r.label_en, en: r.label_en }) : r.type)}</td><td class="n">${esc(fm(r.actual))}</td><td class="n">${esc(fm(r.absorbed))}</td><td class="n"${colorNum(r.unabsorbed)}>${esc(fm(r.unabsorbed))}</td></tr>`).join('');
    const over = (tu.over_absorbed_types || []).map((o) => `${esc(o.type)}: ${esc(fm(o.over_absorbed))}`).join(' · ');
    tuH = `<h3>${esc(T('g_tu'))}</h3><div class="scrollx"><table class="bz" id="c6_tu"><thead><tr>${th('g_type')}${th('g_act', 'n')}${th('g_absorbed', 'n')}${th('g_unabsorbed', 'n')}</tr></thead><tbody>${tr}</tbody>`
      + `<tfoot><tr><td><b>${esc(T('total'))}</b></td><td class="n">${esc(fm(tu.actual_total))}</td><td class="n">${esc(fm(tu.absorbed_total))}</td><td></td></tr></tfoot></table></div>${over ? `<p class="muted">${esc(T('g_over'))}: ${over}</p>` : ''}`;
  }
  return `${warn}<div class="stack" id="c6_glk">${kv('g_poolTot', g.pool_total)}${kv('g_postedTot', g.posted_total)}${kv('g_abs', g.absorbed_gl)}${kv('g_exp', g.expense_gl, true)}${kv('g_expPool', g.expense_gl_from_pool)}${kv('g_expOther', g.expense_gl_other)}${kv('g_unabs', g.unabsorbed_in_pnl)}</div>
    ${rows.length ? `<div class="scrollx"><table class="bz" id="c6_gl"><thead><tr>${th('g_type')}${th('g_pool', 'n')}${th('g_posted', 'n')}</tr></thead><tbody>${body}</tbody></table></div>` : `<p class="muted center pad">${esc(T('none'))}</p>`}${tuH}`;
}
async function loadG() {
  res(`<p class="muted center pad">${esc(T('loading'))}</p>`);
  try {
    const args = { p_loc: Number(G.loc), p_month: G.month + '-01' };
    const [a, b] = await Promise.all([sb.rpc('pool_vs_gl117', args), sb.rpc('overhead_trueup117', args)]);
    if (a && a.error) throw a.error;
    G.gl = a.data; G.tu = b && !b.error ? b.data : null; res(gHTML());
  } catch (e) { G.gl = null; res(`<div class="notice bad">${esc(errMsg(e))}</div>`); }
}
async function viewGl() {
  G.month = G.month || thisMonth();
  await open('cost116gl', 't_gl', 'g_intro', ['pool_gl_post117', 'sw_gl', 'sw_glHow'], '', async () => {
    G.loc = G.loc || defLoc();
    const h = $('#c6_res'); if (h) h.insertAdjacentHTML('beforebegin', `<div class="row wrap">${locSel(G.loc)}<label>${esc(T('month'))}<input type="month" id="c6_m" value="${esc(G.month)}"></label><button class="primary" data-act="c6_ggo">${esc(T('show'))}</button></div>`);
    await loadG();
  });
}

/* ======================= 4. drivers ======================= */
const DRV = ['output_kg', 'output_units', 'batches', 'labour_hours'];
const D = { cfg: {}, types: [] };
const drvOpts = (sel) => `<option value="">${esc(T('d_none'))}</option>` + DRV.map((d) => `<option value="${d}" ${d === sel ? 'selected' : ''}>${esc(TL('d_', d))}</option>`).join('');
function dHTML() {
  const ed = own();
  const locs = (LOCS || []).map((l) => {
    const c = D.cfg[l.id] || {};
    return `<div class="card" data-c6-loc="${l.id}"><b>${esc(nm(l, 'name_bn', 'name_en'))}</b>
      <label>${esc(T('d_driver'))}<select data-f="driver" ${ed ? '' : 'disabled'}>${drvOpts(c.driver116 || '')}</select></label>
      <div class="row wrap"><label>${esc(T('d_nUnits'))}<input data-f="u" inputmode="decimal" value="${esc(c.normal_units116 ?? '')}" ${ed ? '' : 'disabled'}></label>
      <label>${esc(T('d_nBatches'))}<input data-f="b" inputmode="decimal" value="${esc(c.normal_batches116 ?? '')}" ${ed ? '' : 'disabled'}></label>
      <label>${esc(T('d_nHours'))}<input data-f="h" inputmode="decimal" value="${esc(c.normal_labour_hours116 ?? '')}" ${ed ? '' : 'disabled'}></label></div>
      ${ed ? `<button class="primary" data-act="c6_dloc" data-v="${l.id}">${esc(T('d_save'))}</button>` : ''}</div>`;
  }).join('');
  const types = D.types.map((t) => `<div class="card" data-c6-type="${esc(t.code)}"><b>${esc(lab({ bn: t.label_bn || t.label_en || t.code, mix: t.label_bn || t.label_en || t.code, en: t.label_en || t.code }))}</b> <span class="muted">${esc(t.code)}</span>
      <label>${esc(T('d_driver'))}<select data-f="driver" ${ed ? '' : 'disabled'}>${drvOpts(t.driver116 || '')}</select></label>${ed ? `<button class="primary" data-act="c6_dtype" data-v="${esc(t.code)}">${esc(T('d_save'))}</button>` : ''}</div>`).join('');
  return `${ed ? '' : `<div class="notice info">${esc(T('d_ownerOnly'))}</div>`}<h3>${esc(T('d_byPlace'))}</h3><div class="stack">${locs}</div><h3>${esc(T('d_byType'))}</h3><div class="stack">${types || `<p class="muted">${esc(T('none'))}</p>`}</div>`;
}
async function viewDrv() {
  await open('cost116drv', 't_drv', 'd_intro', ['pool_drivers116', 'sw_drv', 'sw_drvHow'], '', async () => {
    try {
      const [cf, ty] = await Promise.all([sb.from('location_cost_cfg').select('*'), sb.from('cost_component_types').select('*').eq('active', true).order('code')]);
      D.cfg = Object.fromEntries(((cf && cf.data) || []).map((c) => [c.location_id, c])); D.types = (ty && ty.data) || [];
      res(dHTML());
    } catch (e) { res(`<div class="notice bad">${esc(errMsg(e))}</div>`); }
  });
}
const numOrNull = (v) => { const s = String(v || '').trim(); if (!s) return null; const n = Number(s); return Number.isFinite(n) && n > 0 ? n : NaN; };

/* ======================= 5. stage cost ======================= */
const ST = { loc: '', recipe: '', data: null };
async function loadRecs() {
  if (RECS) return RECS;
  try {
    const [r, i] = await Promise.all([sb.from('recipes').select('id,item_id,version,active').order('item_id').order('version', { ascending: false }), sb.from('items').select('id,code,name_bn,name_en').eq('item_type', 'finished_good')]);
    const im = Object.fromEntries(((i && i.data) || []).map((x) => [x.id, x]));
    RECS = ((r && r.data) || []).filter((x) => x.active !== false).map((x) => ({ id: x.id, version: x.version, item: im[x.item_id] || null }));
  } catch (e) { RECS = []; }
  return RECS;
}
const recName = (r) => (r.item ? r.item.code + ' · ' + nm(r.item, 'name_bn', 'name_en') : String(r.id).slice(0, 8)) + ' v' + (r.version || 1);
function stHTML() {
  const d = ST.data; if (!d) return '';
  const body = (d.lines || []).map((l) => {
    const s = l.stage;
    return `<tr><td style="text-align:left"><b>${esc(l.code)}</b> ${l.semi_finished ? chip(T('st_semiTag'), 'info') : ''}</td><td>${esc(l.kind || '')}</td><td class="n">${esc(fm(l.qty, 4))}</td><td class="n">${esc(fm(l.avg_cost, 4))}</td><td class="n">${esc(fm(l.amount))}</td>`
      + `<td class="n">${s ? esc(T('st_mat') + ' ' + fm(s.material_cost) + ' + ' + T('st_conv') + ' ' + fm(s.conversion_cost) + ' = ' + T('st_unit') + ' ' + fm(s.unit_cost, 4)) : ''}</td></tr>`;
  }).join('');
  return `${d.unknown_cost ? `<div class="notice warn">${esc(T('st_unknown'))}</div>` : ''}<div class="stack" id="c6_stk"><div class="card"><div class="muted">${esc(T('st_semi'))}</div><div style="font-weight:700">${esc(fm(d.semi_finished_amount))}</div></div>
    <div class="card"><div class="muted">${esc(T('st_other'))}</div><div style="font-weight:700">${esc(fm(d.other_amount))}</div></div></div>
    ${(d.lines || []).length ? `<div class="scrollx"><table class="bz" id="c6_sttbl"><thead><tr>${th('item')}${th('st_kind')}${th('rc_qty', 'n')}${th('st_avg', 'n')}${th('rc_amt', 'n')}${th('st_lastRun', 'n')}</tr></thead><tbody>${body}</tbody></table></div>` : `<p class="muted center pad">${esc(T('none'))}</p>`}`;
}
async function loadSt() {
  if (!ST.recipe) { res(''); return; }
  res(`<p class="muted center pad">${esc(T('loading'))}</p>`);
  try {
    const r = await sb.rpc('recipe_stage_cost116', { p_recipe: ST.recipe, p_loc: Number(ST.loc) });
    if (r && r.error) throw r.error;
    ST.data = r.data; res(stHTML());
  } catch (e) { ST.data = null; res(`<div class="notice bad">${esc(errMsg(e))}</div>`); }
}
async function viewStage() {
  await open('cost116stage', 't_stage', 'st_intro', ['semi_finished_ingredient116', 'sw_stage', 'sw_stageHow'], '', async () => {
    ST.loc = ST.loc || defLoc(); const recs = await loadRecs();
    if (!ST.recipe && recs.length) ST.recipe = recs[0].id;
    const h = $('#c6_res'); if (!h) return;
    h.insertAdjacentHTML('beforebegin', `<div class="row wrap">${locSel(ST.loc)}<select id="c6_r" aria-label="${esc(T('st_recipe'))}">${recs.length ? recs.map((r) => `<option value="${esc(r.id)}" ${r.id === ST.recipe ? 'selected' : ''}>${esc(recName(r))}</option>`).join('') : `<option value="">${esc(T('st_noRecipe'))}</option>`}</select>
      <button class="primary" data-act="c6_stgo">${esc(T('show'))}</button></div>`);
    await loadSt();
  });
}

/* ---------- handlers ---------- */
A.H = A.H || {};
Object.assign(A.H, {
  c6_vgo: () => { V.loc = val('c6_l'); V.from = val('c6_f') || V.from; V.to = val('c6_t') || V.to; const c = $('#c6_latest'); V.latest = !!(c && c.checked); return loadV(); },
  c6_qgo: () => { Q.loc = val('c6_l'); Q.month = val('c6_m') || Q.month; Q.dry = null; Q.confirm = false; Q.rc = null; return loadQ().then(qPaint); },
  c6_ggo: () => { G.loc = val('c6_l'); G.month = val('c6_m') || G.month; return loadG(); },
  c6_stgo: () => { ST.loc = val('c6_l'); ST.recipe = val('c6_r'); return loadSt(); },
  // re-price: dry first, then a second confirm
  c6_rp_check: async () => {
    Q.loc = val('c6_l') || Q.loc; Q.month = val('c6_m') || Q.month; Q.confirm = false;
    try { Q.dry = await runRp(true); Q.dryKey = rpKey(); } catch (e) { Q.dry = null; toast(actMsg(e)); }
    qPaint();
  },
  c6_rp_apply: () => { if (!Q.dry || !Q.dry.dry) return; if (Q.dryKey !== (val('c6_l') || Q.loc) + '|' + (val('c6_m') || Q.month)) { Q.dry = null; qPaint(); toast(T('rp_stale')); return; } Q.confirm = true; qPaint(); },
  c6_rp_no: () => { Q.confirm = false; qPaint(); },
  c6_rp_yes: async () => {
    if (!Q.dry || !Q.dry.dry || !Q.confirm) return;
    Q.confirm = false;
    try { Q.dry = await runRp(false); toast(T('done')); } catch (e) { toast(actMsg(e)); }
    qPaint(); await loadQ();
  },
  // re-cost one run: dry first, then a second confirm
  c6_recost: async (a) => {
    Q.runId = a.dataset.v; Q.rcAsk = false;
    try { const r = await sb.rpc('production_recost116', { p_run: Q.runId, p_dry: true }); if (r && r.error) throw r.error; Q.rc = Object.assign({ dry: true }, r.data); } catch (e) { Q.rc = null; toast(actMsg(e)); }
    qPaint();
  },
  c6_rc_apply: () => { Q.rcAsk = true; qPaint(); },
  c6_rc_close: () => { Q.rc = null; Q.rcAsk = false; qPaint(); },
  c6_rc_yes: async () => {
    if (!Q.rc || !Q.rc.dry || !Q.rcAsk) return;
    Q.rcAsk = false;
    try { const r = await sb.rpc('production_recost116', { p_run: Q.runId, p_dry: false }); if (r && r.error) throw r.error; Q.rc = Object.assign({ dry: false }, r.data); toast(T('done')); } catch (e) { toast(actMsg(e)); }
    qPaint(); await loadQ();
  },
  // drivers (owner only; the server checks again)
  c6_dloc: async (a) => {
    const card = a.closest('[data-c6-loc]'); const g = (f) => card.querySelector(`[data-f="${f}"]`).value;
    const u = numOrNull(g('u')), b = numOrNull(g('b')), h = numOrNull(g('h'));
    if ([u, b, h].some((x) => Number.isNaN(x))) { toast(T('d_bad')); return; }
    try {
      const r = await sb.rpc('loc_cost_driver_set116', { p_loc: Number(a.dataset.v), p_driver: g('driver') || null, p_normal_units: u, p_normal_batches: b, p_normal_hours: h });
      if (r && r.error) throw r.error; toast(T('d_saved'));
    } catch (e) { toast(actMsg(e)); }
  },
  c6_dtype: async (a) => {
    const card = a.closest('[data-c6-type]');
    try {
      const r = await sb.rpc('cost_type_driver_set116', { p_code: a.dataset.v, p_driver: card.querySelector('[data-f="driver"]').value || null });
      if (r && r.error) throw r.error; toast(T('d_saved'));
    } catch (e) { toast(actMsg(e)); }
  },
});

window.BOS_PAGES = Object.assign(window.BOS_PAGES || {}, { cost116var: viewVar, cost116queue: viewQueue, cost116gl: viewGl, cost116drv: viewDrv, cost116stage: viewStage });
B.cost116 = { loaded: true, X, costRight, monthRange };
})();
