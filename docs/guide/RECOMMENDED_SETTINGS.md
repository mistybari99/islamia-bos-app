# প্রস্তাবিত সেটিং - এক পাতায়

প্রতিটি সুইচের **সিস্টেম-প্রস্তাবিত মান** আর এক লাইনের কারণ। সব মান নেওয়া হয়েছে কোডের আসল প্রস্তাব-সারি আর ফাংশন থেকে। কোনো সংখ্যা বানানো হয়নি।

**পড়ার নিয়ম:**
- প্রস্তাব শুধু পরামর্শ। সিস্টেম নিজে কিছু চালু করে না, আটকায়ও না। Apply (মালিক) চাপলে তবেই বসে।
- **"নেই"** = সিস্টেম কোনো মান প্রস্তাব করে না। সংখ্যা বা সিদ্ধান্ত আপনার। এই গাইডের অন্য ফাইল যা বলে, সেটা গাইডের লেখকের পরামর্শ, সিস্টেমের নয়, এবং সেখানে আলাদা করে লেখা।
- সুইচ বদলান `#/switchboard`-এ। প্রস্তাবসহ দেখুন `#/setupadvisor` ও `#/guards`। চালু করার ক্রম `ROLLOUT_PLAN.md`-এ।
- **উৎস কোড:** S81 = `setup_rec_defs81` (phase 81), S94 = ওই টেবিলে phase 94-এর সারি, G82 = `guard_recommendations()` (phase 82), F83 = `form_guard_recommendations()` (phase 83), P87 = `production_recommendations()` (phase 87), V91 = permission পরামর্শ (phase 91), L97 = `landed_recommendation` (phase 97), B85 = `#/books85` পর্দার হিসাব (SQL-এ নেই), H = সুইচের নিজের hint-লেখা (SQL-এ প্রস্তাব-সারি নেই), I = Inv রিপোর্টের সুপারিশ।
- Phase 99 (Opt) ও 101 (Rec) এখনো আসেনি। 100 (Cat) এর প্রস্তাব নিচে।

## হিসাব ও রিপোর্ট

| সুইচ | প্রস্তাব | কেন (এক লাইনে) | উৎস |
|---|---|---|---|
| `accounting_on` | চালু | বিক্রি, ক্রয়, উৎপাদন নিজে খাতায় যায়; শুধু শুরুর তারিখ, mapping, opening ঠিক হলে | S81 |
| `accounting_autopost` | চালু | হাতে post করতে হয় না, pending জমে না | S81 |
| `reports_net_of_returns` | চালু | ফেরত বাদ দিলে বিক্রি ও লাভ বাস্তবের কাছাকাছি | S81 |
| `report_cost_source` | নেই | ডিফল্ট `ledger_then_item_costs` রাখাই গাইডের পরামর্শ, সিস্টেম-প্রস্তাব-সারি নেই | - |
| `acct_count_adjust` | চালু | না হলে স্টকের মান আর খাতা আলাদা হয়ে যায় | B85 |
| `acct_stock_opening` | **বন্ধ** (আগে `acct_opening` দেখুন) | opening স্টক জেরে থাকলে দুবার গোনা হবে; এখন `#/books96`-এ সিদ্ধান্ত নিন | B85 |
| `acct_issue_out` | চালু | না হলে issue স্টক কমায় কিন্তু খরচ আসে না | B85 |
| `acct_transfer_mode` | একের বেশি জায়গা হলে `location_tagged`, নইলে `off` | জায়গা-ভিত্তিক জোড়া ভালো; এক জায়গায় দরকার নেই | B85 |
| `acct_transit_loss` | transfer_mode `off` না হলে চালু | transfer হিসাব চালু থাকলে এটাও চালু ভালো | B85 |
| `acct_transit_loss_at` | `receiver` | সাধারণ পছন্দ | B85 |
| `acct_purchase_variance` | চালু | না হলে return-এর পর স্টক-মূল্য ও খাতা মেলে না | B85 |
| `acct_stock_moves_from` | ফাঁকা | দেরিতে সুইচ চালালে backlog এড়াতে তারিখ দিন; তারিখ আপনার | B85 |
| `manual_journal_guard` | নেই | accountant-এর সঙ্গে ঠিক করুন | - |
| `acct_scheduler_on` | নেই | pg_cron লাগে, ফোনে হয় না | - |
| `acct_pending_alert_days` | নেই | সংখ্যা আপনার (0 থেকে 365) | - |
| `acct_cost_wait_alert_days` (96) | নেই | ফাঁকা = alert নেই; সংখ্যা আপনার | - |
| Opening stock অপশন (96) | জায়গা-ভিত্তিক: cost বাকি হলে `wait_for_cost`, journal পুরো ধরলে `skip`, আংশিক হলে `difference`, journal-এ নেই হলে `owner_capital` | একই স্টক দুবার না গোনার জন্য, সংখ্যা দেখে; নিজে apply হয় না | `opening_stock_recommend96` |
| Cost-অপেক্ষার পদ্ধতি (96) | recipe standard > item average > last purchase > manual | জানা সবচেয়ে ভালো উৎস; কিছু না জানলে manual, সংখ্যা বানায় না | `cost_wait_recommend96` |

## Landed cost (phase 97)

| সুইচ / পরিস্থিতি | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `landed_cost_mode` | নেই (ডিফল্ট `off`) | আমদানি বা বড় ভাড়া না থাকলে `off`; থাকলে `per_shipment` (নিচের সারি) | L97 |
| `landed_alloc_default`, `landed_late_mode`, `landed_reminder_*` | নেই | ডিফল্ট `value` / `split_remaining_and_cogs` / বন্ধ রাখা যায় | - |
| `landed_cost_requires_approval` | বড় অঙ্কে `required` | যে বানায় সে নিজে approve পারে না; "বড়" কত তা আপনার | L97 |
| আমদানি করা মাল | `per_shipment` | একাধিক বিল এক lot; প্রতি charge-এ নিজের পদ্ধতি | L97 |
| ভাড়া / transport | ওজন (সব লাইনে জানা থাকলে), নইলে দাম | ওজনেই ভাড়ার ন্যায্য ভাগ | L97 |
| মাল তোলা-নামানো, packaging, স্থানীয় delivery | পরিমাণ | একক এক রকম হলে | L97 |
| শুল্ক, বীমা, clearing, bank/LC | দাম | দামের অনুপাতে | L97 |
| ফেরত-অযোগ্য কর / ফেরতযোগ্য কর | `vat_nonrec` (cost-এ যায়) / `vat_recov` (যায় না) | যেটা সত্যি সেটা বাছুন | L97 |
| আগেই বিক্রি হওয়া মাল | ভাগ (সব বিক্রি হলে variance) | বিক্রি ও বাকি স্টকের মধ্যে ন্যায্য ভাগ | L97 |

## Recipe, production, costing

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `production_requires_cost` | `refuse` (সব উপাদানের cost বসার পর; তার আগে `warn`) | অজানা cost-এ ভুল বা শূন্য cost-এর মাল তৈরি হবে না | S81, P87 |
| `production_requires_recipe` | চালু (P87)। S81-এ প্রস্তাব নেই | recipe থাকলে কাঁচামাল একবার কাটে, cost ধরা পড়ে | P87 |
| `production_double_issue_guard` | `warn` | recipe আর stock issue দুবার কাটলে সতর্ক করে, আটকায় না | P87 |
| `production_negative_reason` | `required` | কাঁচামাল ছাড়া উৎপাদনে কারণ লেখা থাকে | G82 |
| `production_manual_needs_reason` | চালু | recipe ছাড়া হাতে-তোলা এন্ট্রি ধরা সহজ | S81 |
| `recipe_approval_required` | `warn` | আটকায় না, শুধু হলুদ সতর্কতা; পরে চাইলে `on` | S81 |
| `recipe_self_approve` | বন্ধ | যে বদলায় সে approve না করলে ভুল ধরা পড়ে | S81 |
| `artisan_self_view` | বন্ধ (কারিগরের নিজের login হলে চালু) | তার আগে দরকার নেই | S81 |
| `cost_rule_self_approve` | বন্ধ | যে ভাগের নিয়ম লিখেছে সে approve না করলে ভুল ধরা পড়ে | S81 |
| `cost_attrib_in_pl` | চালু (কোন খরচ কোন শোরুমের তা বসার পর) | শাখার লাভ-ক্ষতিতে আলাদা সারি | S81 |
| `recipe_waste_required` | নেই | অপচয় % বাধ্যতামূলক কিনা আপনার সিদ্ধান্ত | S81 |
| `cost_gap_warn_pct`, `yield_variance_warn_pct` | নেই | কিছু বাস্তব কেনা/উৎপাদনের পর আপনি সংখ্যা লিখবেন | S81 |

## স্টক guard

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `purchase_grn_guard` | GRN উৎস হলে `skip`, নইলে `off` | নইলে একই মাল দুবার গোনা হয় | G82 |
| `purchase_void_guard` | `refuse` | ফেরত/ব্যবহার হওয়া মালের বিল void করলে স্টক ঋণাত্মক হয় | G82 |
| `purchase_void_payments` | `keep` | টাকা সত্যিই বেরিয়েছে; payment void করলে day book ভুল | G82 |
| `unit_conv_required` | `unit_unknown_items()` = 0 হলে `refuse`, নইলে `warn` | conversion না থাকলে block বিপজ্জনক | G82 |
| `neg_grant_log` | চালু | অনুমতিতে মাইনাসে বিক্রি হলে মালিক জানেন | G82 |
| `stock_negative_mode` | প্রথম count/opening হয়ে গেলে `block`, নইলে বর্তমান মান | তার আগে block করলে বিক্রি আটকে যেতে পারে | G82 |
| `expiry_sale_guard`, `purchase_backdate_flag` | নেই | কোনো প্রস্তাব-তালিকায় নেই | - |

## Form, transit, offline POS

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `form_051_mode` | 05-1 শিটই production-record হলে `post`, নইলে `reference` | `post` না হলে তৈরি মাল বিনা cost-এ ঢোকে | F83 |
| `transit_short_mode` | `loss` | কম পৌঁছানো মাল তখন cost সহ ledger-এ থাকে | F83 |
| `transit_open_hours` | নেই | আপনার delivery-র সাধারণ সময়ের একটু বেশি লিখুন | F83 |
| `offline_soft_stock` | চালু | offline বিক্রিতে মাল দেওয়া হয়ে গেছে; আটকালে বিক্রি হারায় | F83 |
| `offline_sale_max_age` | নেই | ফোন সর্বোচ্চ কত ঘণ্টা offline থাকে তার সংখ্যা আপনার | S94 |

## অনলাইন, inbox, Telegram

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `online_orders_on` | চালু | ওয়েব ফর্ম, ফোন, walk-in দিয়ে শুরু সহজ | S81 |
| `inbox_on` | চালু | সব বার্তা এক জায়গায় | S81 |
| `web_form_on` | চালু (public URL বাইরের সেটআপ) | দাম সার্ভারে ঠিক হয়, ডুপ্লিকেট আটকায় | S81 |
| `meta_intake_on` | বন্ধ | সংযোগ ফোনে হয় না | S81 |
| `inbox_autodraft_on` | বন্ধ | আগে স্টাফ হাতে যাচাই করুক | S81 |
| `inbox_pii_guard_on` | **চালু** (ডিফল্ট বন্ধ) | ফোন/ঠিকানা শুধু অনুমতিধারী দেখে, প্রতিটি দেখা লগে | S81, S94 |
| `online_pack_warn_on` | চালু | প্যাকের সময় স্টক কম হলে সতর্ক, আটকায় না | S81 |
| `online_keep_order_price` | চালু | অর্ডারের দাম ডেলিভারিতে থাকে; ভিন্ন দামে manager-এর অনুমতি | S81 |
| `online_pack_reserve_on` | নেই | আপনার সিদ্ধান্ত | S81 |
| `telegram_intake_on` | নেই | সেটআপ শেষে চালু করুন | - |
| `web_form_captcha_on`, `web_form_public_url` | নেই | বাইরের key/URL লাগে | S81 |
| `web_form_rate_max`, `web_form_rate_window_min`, `inbox_silence_hours`, `intake_max_tries`, `intake_retry_min` | নেই | নিজের সংখ্যা লিখুন বা ডিফল্ট রাখুন | S81 |
| `inbox_rate_max_per_min`, `intake_reject_max_per_min` | নেই | সংখ্যা আপনার; ফাঁকা = সীমাহীন | S94 |
| `TELEGRAM_SECRET_TOKEN` (Edge secret) | সেট থাকা বাধ্যতামূলক | না থাকলে সব অনুরোধ 403 | phase 94 |

## Partner, packaging, scan

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `partner_base_estimate` | `refuse` (ledger cost বসার পর; তার আগে `warn`) | অনুমানের cost ভিত্তিতে লাভ ভাগ হয় না | S94 |
| `packaging_return_mode` | `wastage` | ফেরত মোড়ক সাধারণত আর বিক্রিতে লাগে না | S94 |
| `scan_enabled` | নেই | গাইডের পরামর্শ: চালু, `manual` দিয়ে শুরু | - |
| `scan_engine` | নেই | গাইডের পরামর্শ: `manual`, পরে `browser_ocr`, সবশেষে `ai_vision` | - |
| `scan_min_confidence` | নেই | ডিফল্ট 0.6; সংখ্যা আপনার | - |
| `scan_ai_max_per_job`, `scan_ai_max_per_user_day` | নেই | AI-তে প্রতিবার খরচ; সংখ্যা আপনার (ফাঁকা = সীমাহীন) | S94 |

## ইনভয়েস, template, drawer, category

| সুইচ | প্রস্তাব | কেন | উৎস |
|---|---|---|---|
| `pos_show_invoice_after_sale` | **`always`** (ডিফল্ট `never`) | সেল শেষে ইনভয়েস পর্দায়; কিছু না করলে আগের মতো থাকে বলে ডিফল্ট `never` | I (Inv রিপোর্ট ও phase 92 hint) |
| `invoice_own_sales_only` | চালু | ক্যাশিয়ার শুধু নিজের বিক্রির ইনভয়েস দেখে | S94 |
| Template ডিজাইন (`#/templates`) | "Suggested" চিহ্নিত ডিজাইন (রসিদ `thermal80_slip`, pay_slip `a5_classic` ইত্যাদি) | picker-এ প্রস্তাব; কারণ আলাদা লেখা নেই | phase 93 seed |
| `cash_drawer_mode` | ড্রয়ার লাগানোর পর `on_cash_sale` | শুধু ক্যাশ নিলে খোলে | H |
| `cash_drawer_when` | `after_payment` | বিক্রি সেভ হলে তবেই খোলে | H |
| `cash_drawer_method` | USB/সিরিয়াল প্রিন্টারে `web_serial` | সরাসরি ESC/POS, কম্পিউটার বা Android Chrome; iPhone-এ চলে না | H |
| `cash_drawer_no_sale_requires_reason` | চালু | বিক্রি ছাড়া খোলা মানেই চুরির ঝুঁকির সংকেত | H |
| `category_required_on_item` (phase 100, আসছে) | `warn` | Category ছাড়া আইটেম ধরা যায়, আটকায় না | phase 100 recommendation row |

## Permission (V91, প্রতিটি ব্যক্তির জন্য `permission_recommendations(user)`)

| বিষয় | প্রস্তাব | কেন |
|---|---|---|
| ভূমিকায় সাধারণত দরকারি কিন্তু নেই এমন grant (`recommended_missing`) | দিন (Apply) | ভূমিকার ডিফল্ট grant ও কয়েকটা সাধারণ যোগ থেকে |
| একসঙ্গে না থাকা ভালো ১৫টা জোড়া | আলাদা মানুষকে দিন | ক্রয় লেখা + supplier payment/void, recipe বদল + approve, বিক্রি void + stock count adjust, cost দেখা + price/discount, payroll + salary structure, `intake_bot` + POS ইত্যাদি |
| অনুমতিহীন ফর্ম/মেনু (`unused`) | Hide | মেনু গোছানো, অনুমতি বদলায় না |

(ব্যবহার-ইতিহাস থেকে "কেউ ব্যবহার করেনি" ধরনের প্রস্তাব বানানো হয় না। কারণ-বাক্য সাধারণ; আপনি `reco_role_set` দিয়ে বদলাতে পারেন।)

---
**যাচাই হয়নি:** এই প্রস্তাবগুলো আপনার লাইভ ডাটার ওপর ব্যবসায়িকভাবে যাচাই হয়নি; `B85`-এর মান লেখকের বিচার, accountant নিশ্চিত করেননি; `G82`-এর `stock_negative_mode` ও `unit_conv_required` আপনার ডাটা দেখে বদলায় (এখানে শর্তসহ লেখা)।
