# চালু করার নিরাপদ ক্রম - একটা একটা করে

নিয়ম: **একবারে একটা সুইচ।** চালান, ২-৩ দিন সাধারণ কাজ করুন, "চেক" মিলিয়ে নিন, তারপর পরেরটা।
কোনো চেক লাল হলে থামুন, সুইচ আগের মানে ফেরান (সুইচ ফেরালে নতুন কাজ বন্ধ হয়)।

কোডের নাম:
- `setup_readiness(topic)` = চালানোর আগের প্রস্তুতি। Topic: `stock_tracking`, `accounting`, `production`, `cost_sources`, `online`। দেখতে: `#/setupadvisor` > "Before switching on"।
- `setup_flow_check()` = চালানোর পরে "সব ঠিকঠাক বইছে?"। দেখতে: `#/setupadvisor` > "Is it all flowing"। Code-গুলো `flw_*`।

ধাপের লাল/হলুদ/সবুজ: `ok` = ঠিক, `warn` = দেখুন, `info` = জানার জন্য, `na` = ওই সিস্টেম বন্ধ।

**কী ফেরানো যায় না:** একবার খাতায় (journal) post হয়ে গেলে সুইচ বন্ধ করলেও পুরনো entry থেকে যায়। ভুল হলে ওই entry void করতে হয়। [সুইচ বন্ধ করলে ঠিক কী কী হয় তা accounting সুইচগুলোর জন্য পরীক্ষা করা হয়নি। `[যাচাই হয়নি]`]

---

## ধাপ ০ - SQL paste (মালিক সম্পন্ন করেছেন: phase 72 থেকে 98)

DB-র সব phase এখন লাইভ ডাটাবেসে বসানো (ক্রম `docs/PASTE_ORDER.md`)। **নিয়ম: নতুন phase (99, 100, 101) সবসময় 98-এর পরে; আগের কোনো phase কখনো আবার paste নয়।**

| কাজ | চেক |
|---|---|
| `#/setupadvisor` খুলুন। | কোনো সারি `not_installed` নয়। `setup_flow_check()` এ নতুন কিছু লাল নয়। |
| একটা সাধারণ বিক্রি, একটা ক্রয়, দিনের শেষের রিপোর্ট করে দেখুন। `UAT_CHECKLIST.md` এর "ক" অংশ চালান। | সংখ্যা আগের দিনের মতো। (ব্যতিক্রম: ধাপ ২-এ রিপোর্ট cost উৎস বদলে যায়) |

**থামার শর্ত:** নতুন কোনো paste-এ error এলে পরের phase paste করবেন না। প্রতিটি নতুন paste-এর (99, 100, 101) পরে `UAT_CHECKLIST.md` চালান।

---

## ধাপ ১ - শুধু দেখা-সাজানো (ঝুঁকি সবচেয়ে কম)

| সুইচ বা পর্দা | কী করবেন | চেক |
|---|---|---|
| `pos_show_invoice_after_sale` (`#/switchboard`, ডিফল্ট `never`) | আগে `ask`, কয়েকদিন পরে **`always` (সুপারিশ)** | একটা ক্যাশ সেল করুন। ইনভয়েস আসে। নিজের নম্বরে WhatsApp/SMS/Email একবার পাঠিয়ে দেখুন। Offline সেল করে Q-নম্বর আর "Pending sync" দেখুন |
| `#/templates` | একটা ধরনের ডিজাইন বাছুন (পরে বাকিগুলো) | `#/templates`-এ preview ঠিক। বাছা ডিজাইন এখন ইনভয়েস (Print/Download/SMS/WhatsApp/Email), বিক্রি-ফেরত স্লিপ, পে-স্লিপ ও লেবেলে বসে। ক্রয় বিল ও বাকি ধরন এখনো বসেনি (গাইড অংশ 16) |
| মেনু-footer, কীবোর্ড-নিরাপদ sheet | কোনো সুইচ নেই। `UAT_CHECKLIST.md` এর পরীক্ষা চালান | মেনু-footer ডিফল্টে গোটানো। sheet-এ লেখার সময় Save বোতাম দেখা যায় (গাইড অংশ 23) |
| `#/optviews` | প্রথমে একজন পরীক্ষামূলক ব্যবহারকারীর মেনু Hide/Locked করুন | তার ফোনে মেনু বদলেছে। Hide-করা পাতার সরাসরি লিংক এখনো খোলে (জানা)। অনুমতি বদলায়নি |

---

## ধাপ ২ - রিপোর্ট ও অজানা cost

| সুইচ | কী করবেন | চেক |
|---|---|---|
| `report_cost_source` | ডিফল্ট `ledger_then_item_costs` রাখুন | `#/costunknown` খুলুন। "খরচহীন বিক্রি" ও cost-ছাড়া আইটেম তালিকা দেখুন। কিছু সংখ্যা আগের চেয়ে আলাদা হতে পারে, সেটাই উদ্দেশ্য |
| Free-cost চিহ্ন (`#/s1setup`) | পানির মতো সত্যিই শূন্য-দামের আইটেম চিহ্নিত করুন (কারণ লিখে) | `cost_unknown_items()` তালিকা ছোট হয়। `setup_readiness('stock_tracking')` এর `stk_cost` |

---

## ধাপ ৩ - Stock tracking ও guard

**আগে প্রস্তুতি:** `setup_readiness('stock_tracking')` - `stk_tracked`, `stk_unit`, `stk_opening`, `stk_conv`, `stk_cost`, `stk_neg` সব `ok` বা কারণ বোঝা।

এক এক করে (প্রতিটির পরে চেক):

| ক্রম | সুইচ | মান | চেক |
|---|---|---|---|
| 3.1 | `neg_grant_log` | চালু | মাইনাসে বিক্রি করলে হলুদ লাইন আসে। কিছু আটকায় না |
| 3.2 | `production_double_issue_guard` | `warn` | কিছু আটকায় না। হলুদ আসলে কারণ দেখুন |
| 3.3 | `purchase_void_guard` | আগে `warn`, পরে `refuse` | `warn` এ লাল `purchase_void_unsafe` কতবার আসে দেখুন। কম হলে `refuse` |
| 3.4 | `purchase_void_payments` | `keep` | একটা পরীক্ষামূলক বিল void করে দেখুন payment থাকে, `supplier_credits()` এ credit দেখায় |
| 3.5 | `purchase_grn_guard` | স্টকের উৎস GRN হলে `skip` | একটা GRN ও একই বিল করুন। স্টক একবারই বাড়ে। `grn_pending_report()` খালি বা বোধগম্য |
| 3.6 | `unit_conv_required` | `unit_unknown_items()` = 0 হলে `refuse`; নইলে `warn` রাখুন | অনলাইন বিক্রি ইউনিট-অজানা আইটেমে ফেরত আসে না, কারণ সব ঠিক। `flw_neg` সবুজ |
| 3.7 | `production_negative_reason` | `required` | স্টক মাইনাস হবে এমন production কারণ ছাড়া হয় না |
| 3.8 | `stock_negative_mode` | প্রথম stock count/opening হয়ে গেলে block বিবেচনা | `flw_neg` কমে, মাইনাস বিক্রি নিয়ে অভিযোগ আসছে কিনা |
| 3.9 | `expiry_sale_guard` | `warn` (আগে), `refuse` (বিবেচনা) | মেয়াদোত্তীর্ণ মাল বিক্রি হলে লাল লাইনে batch দেখায় |
| 3.10 | `purchase_backdate_flag` | `warn` | পুরনো তারিখের বিল হলুদ হয় |

**থামার শর্ত:** কোনো `refuse` এ দিনের স্বাভাবিক কাজ আটকালে ওই সুইচ `warn`-এ ফেরান।

---

## ধাপ ৪ - Recipe ও approval

**আগে প্রস্তুতি:** `setup_readiness('production')` - `prd_recipes`, `prd_lines`, `prd_yield`, `prd_icost`, `prd_unit`। `prd_approve` info।

| ক্রম | কাজ | চেক |
|---|---|---|
| 4.1 | Approver: Staff-এ role `recipe_approver` দিন (`#/delegation`)। হলুদ পরামর্শ আসে যদি একজনকে entry আর approve দুটোই দেন | approver আলাদা জন। `recipe_approve` পারে |
| 4.2 | Artisan যোগ (`#/recipebook` > register)। Recipe-তে artisan বসান | "কারিগর নির্ধারিত নয়" তালিকা ছোট হয় |
| 4.3 | Recipe approve করুন | `prd_approve` কমে |
| 4.4 | `recipe_approval_required` = `warn` | production-এ হলুদ `recipe_not_approved` কমে। বাকিরা approve করুন |
| 4.5 | `production_manual_needs_reason` = চালু | হাতে-তোলা production-এ কারণ চায় |
| 4.6 | `production_requires_recipe` = চালু | recipe ছাড়া production তোলা যায় না। `flw_prod_cost` এর সংখ্যা দেখুন |
| 4.7 | `production_requires_cost` = `refuse`, **শুধু** `prd_icost` পরিষ্কার হলে | সব উপাদানের cost জানা। একটা production করে দেখুন। `flw_prod_cost` সবুজ |
| 4.8 | `recipe_approval_required` = `on` (বিবেচনা) | **সব অ-approved recipe আটকে যাবে**, তাই শুধু যখন সব approve হয়ে গেছে |

---

## ধাপ ৫ - Costing, cost source, শাখা-ভাগ

**ক্রম: এই চার ধাপের কোনোটা না করে পরেরটা নয়।**

| ক্রম | কাজ | আগে প্রস্তুতি | চেক |
|---|---|---|---|
| 5.1 | রূপান্তর খরচ rate (`#/costing`)। জায়গার পদ্ধতি `recipe` | `prd_conv` | একটা production করুন। একক cost হাতে হিসাব করা সংখ্যার সঙ্গে মেলে। `overhead_trueup` এ "অনাবশোষিত ওভারহেড" সারি |
| 5.2 | `cost_gap_warn_pct`, `yield_variance_warn_pct`: কিছু আসল কেনা/production-এর পর নিজের সংখ্যা | - | ফারাক বড় হলে হলুদ চিহ্ন |
| 5.3 | Pool পদ্ধতি (পরে): স্বাভাবিক মাসিক উৎপাদন (kg) লিখুন, তারপর `pool` | `prd_conv`; `flw_pool` | `flw_pool` সবুজ (এই মাসের খরচ বসানো আছে) |
| 5.4 | Cost source বানান (`#/costsources`), নিয়ম লিখুন, আলাদা মানুষ approve | `cs_sources`, `cs_rule` | "ভাগ নির্ধারিত নয়" তালিকা ও "বিল বাকি" তালিকা খালি বা বোধগম্য |
| 5.5 | শাখা-ভাগ ঠিক করুন (`#/costattrib`): কোন খরচ কোন শোরুমের | `cs_attrib` | `branch_cost_view` এ প্রতিটি ভাগ ঠিক জায়গায়। "unallocated" শূন্য বা জেনে-বুঝে |
| 5.6 | `cost_attrib_in_pl` = চালু | 5.5 শেষ | শাখার P&L এ নতুন "খরচ ভাগ" সারি। **সতর্ক:** একই বিল 10-2 voucher-এও থাকলে দুবার আসে। `l4`/`l5`/partner অপরিবর্তিত |

---

## ধাপ ৬ - অনলাইন অর্ডার ও বার্তা

**আগে প্রস্তুতি:** `setup_readiness('online')` - `onl_channels`, `onl_url`, `onl_bot`।

| ক্রম | কাজ | চেক |
|---|---|---|
| 6.1 | `online_orders_on` = চালু। Channel বানান: ফোন, walk-in (`#/saleschannels`) | `onl_channels` ok |
| 6.2 | `inbox_on` = চালু | একটা হাতে-বানানো অর্ডার inbox/অর্ডার-তালিকায় দেখা যায় |
| 6.3 | `inbox_pii_guard_on` = চালু। শাখার POS স্টাফ ও মালিককে `inbox_contact_view` দিন | অনুমতিহীন একজনের ফোনে নম্বর ঢাকা। অনুমতিধারীর দেখা audit-এ যায় |
| 6.4 | `online_pack_warn_on` = চালু | প্যাক করার সময় স্টক কম থাকলে সতর্কতা। কিছু আটকায় না। `#/packflags` |
| 6.5 | `online_keep_order_price` = চালু। কে `price_override` দেবে ঠিক করুন | ভিন্ন দামে ডেলিভারি করলে manager অনুমতি চায়, হলুদ exception |
| 6.6 | Web form: Edge function deploy (**কম্পিউটার**), intake bot বানান, `web_form_public_url` বসান, `web_form_on` = চালু | `onl_url`, `onl_bot` ok। একটা পরীক্ষামূলক ফর্ম জমা দিন। দুবার জমা দিলে ১ অর্ডার |
| 6.7 | `flw_inbox_new`, `flw_inbox_silent`, `flw_intake_fail`, `flw_oo_flags` | সব সবুজ বা বোধগম্য |
| 6.8 | (শেষে, ঐচ্ছিক) Telegram: `docs/TELEGRAM_SETUP.md` অনুসরণ। `telegram_intake_on` | নিজের Telegram থেকে "test" পাঠান। inbox-এ আসে |
| 6.9 | (শেষে, ঐচ্ছিক, কঠিন) Meta: `meta_intake_on` | **এখনো যাচাই হয়নি।** আগে নিজে দেখুন বাংলাদেশে কী লাগে |

`inbox_autodraft_on`: শুরুতে বন্ধ রাখুন।

---

## ধাপ ৭ - Form বনাম screen, transit, offline POS

| ক্রম | সুইচ | মান | চেক |
|---|---|---|---|
| 7.1 | `offline_soft_stock` | চালু | offline-এ বিক্রি পরে sync হলে আসে, হলুদ লাইনে। `#/posfailed` ফাঁকা বা বোধগম্য |
| 7.2 | অধিকার `pos_replay_override` | ম্যানেজারদের | আটকে যাওয়া sale কারণসহ পাঠানো যায় |
| 7.3 | `transit_short_mode` | `loss` | transfer-এ ঘাটতি হলে `#/transitshort` এ ঘাটতি আসে |
| 7.4 | `transit_open_hours` | আপনার সংখ্যা | পুরনো খোলা transfer alert-এ আসে |
| 7.5 | `form_051_mode` | আগে `reference` রাখুন। 05-1 যদি আসল production রেকর্ড হয়, তখন `post` | `#/unmatched` তালিকা। `post` এ একটা লাইন চালান: কাঁচামাল কমে, তৈরি মাল cost সহ বাড়ে। recipe না থাকলে লাইন ব্যর্থ, অর্ধেক হয় না |

---

## ধাপ ৮ - Accounting (সবচেয়ে সাবধানে)

**আগে প্রস্তুতি:** `setup_readiness('accounting')` সব `ok`: `acc_start`, `acc_coa`, `acc_map`, `acc_opening`। `acc_wait` ও `acc_err` শূন্য।

**একবারে একটা সুইচ। প্রতিটির আগে dry run (`#/accounts`)।**

| ক্রম | সুইচ | মান | চেক ও সতর্কতা |
|---|---|---|---|
| 8.1 | `accounting_on` | চালু (আপনার সিদ্ধান্ত কখন) | `flw_acc_old`, `flw_acc_err`, `flw_acc_wait` |
| 8.2 | `accounting_autopost` | চালু | pending জমে না। `acct_status` ঠিক |
| 8.3 | `acct_stock_moves_from` | **আগে একটা শুরুর তারিখ লিখুন**, পরের সুইচগুলোর আগে | backlog বাঁচাতে |
| 8.4 | `acct_count_adjust` | চালু | dry run দেখুন। `inventory_vs_gl` এ পার্থক্য কমে |
| 8.5 | `acct_issue_out` | চালু | একইভাবে |
| 8.6 | `acct_purchase_variance` | চালু | একইভাবে |
| 8.7 | `acct_transfer_mode` | `location_tagged` বা `company_wide` | clearing (1230) শূন্যে মেলে। কোনটা হবে accountant-এর সঙ্গে ঠিক করুন |
| 8.8 | `acct_transit_loss` ও `acct_transit_loss_at` | চালু, `receiver` বা `sender` | clearing account মিটমাটের হিসাব বুঝুন |
| 8.9 | `acct_stock_opening` | **শুধু যদি** opening stock শুরুর জের (`acct_opening`) এর ভেতরে নেই | **নইলে দুবার গোনা হবে।** `inventory_vs_gl` এ আগে-পরে |
| 8.10 | `manual_journal_guard` | `on` | হাতে-journal-এ কারণ-কোড চায়। accountant কে বলে রাখুন |
| 8.11 | Card settlement: `#/books85` > Card settlement | দরকার হলে ব্যবহার | অমীমাংসিত card receivable তালিকা কমে। (পর্দা আছে) |
| 8.12 | `acct_scheduler_on` | শেষে | **কম্পিউটার ও pg_cron লাগে।** `acct_autopost_runs85` এ প্রতি run-এর সারি |

প্রতিটি 8.x এর পরে: `#/accounts` এ trial balance balanced, `flw_acc_old` সবুজ, `flw_acc_err` শূন্য।

**থামার শর্ত:** trial balance না মিললে, বা `flw_acc_err` বাড়লে থামুন। সুইচ ফেরান। accountant-কে দেখান।

---

## ধাপ ৯ - Scan, partner, packaging

| সুইচ | কী করবেন | চেক |
|---|---|---|
| `scan_enabled` + `scan_engine = manual` | চালু। `scan_upload` ও `scan_confirm` কাকে দেবেন ঠিক করুন | একটা আসল বিল ছবি তুলে খসড়া, Confirm। ক্রয় বিল খসড়া হিসাবে আসে। দুবার Confirm = ১ বিল |
| `scan_engine = browser_ocr` | পরীক্ষা | আসল বিলে পাঠ-মান আপনার চোখে ঠিক কিনা |
| `scan_engine = ai_vision` | **শেষে।** key, খরচ-সীমা, Edge function লাগে (কম্পিউটার) | প্রথমে কয়েকটা ছবি |
| `partner_base_estimate` | `refuse` বিবেচনা (আপনার সিদ্ধান্ত) | অংশীদার হিসাব সেভে `base_estimated` আসে, অনুমানের ভিত্তি থাকলে |
| `packaging_return_mode` | `wastage` দিয়ে শুরু (S1 রিপোর্টের প্রস্তাব), পরে চাইলে `restore` | একটা ফেরত করে দেখুন প্যাকেজিং-রেকর্ড |

---

## ধাপ ১০ - নিরাপত্তা-পরীক্ষা (phase 94, আগেই করা ভালো)

| কাজ | চেক |
|---|---|
| SQL Editor-এ: `select pii_exposure_report94();` `select anon_exec_audit94();` `select intake_proof_status94();` | অচেনা `anon`-ফাংশন নেই (আশা: `login_precheck`, `login_failed`, `attendance_punch_push`, পুরনো helper)। বাকিটা কম্পিউটারওয়ালাকে দেখান |
| `inbox_pii_guard_on` = চালু (সিস্টেম প্রস্তাব) | অনুমতিহীন ফোনে নম্বর ঢাকা |
| `invoice_own_sales_only` = চালু (সিস্টেম প্রস্তাব) | একজন স্টাফ অন্যের বিক্রির ইনভয়েস পায় না। মালিক পায় |
| সীমা: `scan_ai_max_per_job`, `scan_ai_max_per_user_day`, `offline_sale_max_age`, `inbox_rate_max_per_min`, `intake_reject_max_per_min` | **আপনার নিজের সংখ্যা** (সিস্টেম দেয় না)। ফাঁকা = আগের মতো |
| Telegram চালু থাকলে: `TELEGRAM_SECRET_TOKEN` | না থাকলে Telegram থেমে যায় (403)। কম্পিউটার লাগে |

**থামার শর্ত:** কেউ আগে যা পারত, এখন বৈধ কাজে পারছে না (যেমন ইনভয়েস দেখা) - সুইচ ফেরান।

## ধাপ ১১ - Opening stock ও cost-অপেক্ষা (phase 96)

**আগে:** ধাপ ৮-এর 8.9 (`acct_stock_opening`) **এই ধাপের আগে চালাবেন না।**

| ক্রম | কাজ | চেক |
|---|---|---|
| 11.1 | `#/books96` > Opening stock: প্রতি জায়গার সংখ্যা ও সতর্কতা পড়ুন | journal-এর সংখ্যা আর valuation-এর পার্থক্য বুঝুন |
| 11.2 | সিস্টেমের প্রস্তাব পড়ুন, Preview (dry run) দেখুন | কী post হবে ঠিক জানেন |
| 11.3 | accountant-এর সঙ্গে ঠিক করে একটা অপশন apply (`owner_capital` / `existing_account` / `skip` / `difference`) | `inventory_vs_gl` পার্থক্য শূন্য বা ব্যাখ্যাত। trial balance balanced |
| 11.4 | Cost waiting তালিকা: প্রতিটির প্রস্তাবিত পদ্ধতির preview দেখে cost বসান। `acct_cost_wait_alert_days` আপনার সংখ্যা | তালিকা ছোট হয়। manual cost-এ কারণ লেখা |

## ধাপ ১২ - Landed cost (phase 97, শুধু আমদানি বা বড় ভাড়ার জন্য)

| ক্রম | কাজ | চেক |
|---|---|---|
| 12.1 | `landed_cost_mode` = `manual` (বা আমদানিতে `per_shipment`)। grant `landed_entry`/`landed_approve` কাকে | `#/landed` খোলে |
| 12.2 | একটা পুরনো posted বিলে `Preview` (লেখে না)। সব পদ্ধতি পাশাপাশি | হাতে-হিসাবের সঙ্গে মেলে |
| 12.3 | একটা সত্যিকারের বিলে save > approve > post | আইটেমের গড় cost বাড়ে। `inventory_vs_gl` মেলে |
| 12.4 | `landed_cost_requires_approval` = `required` (বড় অঙ্কে) | যে বানায় সে নিজে approve পারে না |
| 12.5 | (ঐচ্ছিক) `landed_reminder_on` | `#/landed/rem` তালিকা |

**না লাগলে `off` রাখুন; কিছু বদলাবে না।**

## ধাপ ১৩ - ক্যাশ ড্রয়ার (phase 95, ড্রয়ার কেনার পর)

| ক্রম | কাজ | চেক |
|---|---|---|
| 13.1 | প্রিন্টার USB-তে লাগান, `#/cashdrawer` > method (`web_serial`) > Connect device > Test open | ড্রয়ার খোলে। না খুললে টোস্ট "Drawer not connected", বিক্রি আটকায় না |
| 13.2 | `cash_drawer_mode` = `on_cash_sale`, `cash_drawer_when` = `after_payment` | ক্যাশ বিক্রির পর খোলে; কার্ড বিক্রিতে খোলে না |
| 13.3 | `cash_drawer_no_sale_requires_reason` চালু রাখুন; `drawer_nosale` অল্প মানুষকে | No sale-এ কারণ চায়। রিপোর্টে দেখায় |

iPhone/iPad-এ সরাসরি সংযোগ চলে না (গাইড অংশ 20)।

## ধাপ ১৪ - Category / Sub-category (phase 100, আসছে)

Paste 98-এর পরে। তারপর `#/categories`-এ তালিকা মিলিয়ে নিন, `category_required_on_item` আগে `warn` (সিস্টেম প্রস্তাব), পরে চাইলে `required`। চেক: POS/ক্রয়/স্টকে Category বেছে নেওয়া যায়, `#/catreport` মোট = সাধারণ রিপোর্টের মোট। **এখনো পরীক্ষার ফল নেই (রিপোর্ট অসম্পূর্ণ)।** Phase 99 ও 101 এলে এখানে ধাপ যুক্ত হবে।

---

## প্রতি সপ্তাহে

1. `#/setupadvisor` > "Is it all flowing" - সব `flw_*` সবুজ।
2. `#/costunknown` - খরচহীন বিক্রির সংখ্যা কমছে।
3. `#/posfailed`, `#/packflags`, `#/unmatched`, `#/transitshort` - খোলা তালিকা পরিষ্কার।
4. `#/accounts` - pending ও error শূন্য।

## যা এখনো তৈরি হয়নি (তাই এই ক্রমে নেই)

- `production_recost` (production পরে cost সংশোধন)।
- `cost_bill_creates_payment`।
- Meta (Facebook/Instagram/WhatsApp) এর আসল সংযোগ ও Telegram এর আসল পরীক্ষা।
- Phase 99 (bill payment option + inbox PII mask) ও 101 (advisor সারি): কোনো কোড এখনো নেই।
- `kiosk_url` ড্রয়ার পদ্ধতি; ক্রয় বিল ছাপায় template; landed cost-এ GRN বাছার পর্দা।

(আগের তালিকা থেকে সরানো: বিল-স্তরের landed cost ও card settlement/scheduler পর্দা, দুটোই এখন আছে।)

সব ধাপ `[যাচাই হয়নি]`: লাইভ ডাটাবেস ও আসল ফোনে এই ক্রম চালানো হয়নি।
