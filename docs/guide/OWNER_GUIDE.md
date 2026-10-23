# মালিকের গাইড - নতুন ফিচার (phase 72 থেকে 98, আর পরে আসা 99, 100, 101)

ফোনে পড়ার জন্য লেখা। বাক্য ছোট। সাধারণ শব্দ English-এ।
সব তথ্য এসেছে কোড (`supabase/phase72..98.sql`, `web/*.js`) আর ধাপের রিপোর্ট (`docs/briefs_p2p3/*_REPORT.md`, `docs/SCAN_SETUP.md`, `docs/TELEGRAM_SETUP.md`) থেকে।
সংখ্যা বানানো হয়নি। যেখানে সংখ্যা আছে, সেটা কোডের ডিফল্ট।

সঙ্গে আরও চারটি ফাইল:
- `docs/guide/PHONE_ONLY_STEPS.md` - ফোনে নিজে কী কী করবেন, আর কোনটা ফোনে হয় না।
- `docs/guide/ROLLOUT_PLAN.md` - একটা একটা করে চালু করার নিরাপদ ক্রম।
- `docs/guide/UAT_CHECKLIST.md` - প্রতি ধাপের পরে ৩০ মিনিটে ফোনে ৪০টা ছোট পরীক্ষা।
- `docs/guide/RECOMMENDED_SETTINGS.md` - প্রতিটি সুইচের সিস্টেম-প্রস্তাবিত মান, এক পাতায়।

**অবস্থা (শেষ হালনাগাদ):** মালিক নিজে লাইভ ডাটাবেসে phase 72 থেকে 98 সব paste করে ফেলেছেন (ক্রম: 72..88, 90, 91, 89, 92, 93, 95, 94, 96, 97, 98, দেখুন `docs/PASTE_ORDER.md`)। তাই আর কোনো পুরনো phase আবার paste করবেন না। নতুন phase (99, 100, 101) আলাদা ছোট paste হিসেবে আসবে (অংশ 18)।

---

## আগে এই ৭টা কথা মনে রাখুন

1. **সব নতুন সুইচের ডিফল্ট = আজকের আচরণ।** SQL paste করলে কিছু বদলায় না। সুইচ চালু করলে তবেই বদলায়।
2. **"প্রস্তাবিত মান" শুধু পরামর্শ।** সিস্টেম নিজে কিছু চালু করে না, কিছু আটকায়ও না। `apply` চাপলে তবেই মান বসে (মালিক-only)।
3. **সংখ্যার সীমা (যেমন cost gap %) সিস্টেম প্রস্তাব করে না।** আপনি নিজের মান লেখেন।
4. **সুইচ কোথায়:** `#/switchboard` (সব চালু/বন্ধ)। প্রস্তাব সহ দেখতে `#/setupadvisor` আর `#/guards`।
5. **Cost (খরচ) গোপন।** Cost দেখার অধিকার (`view_cost`) যাদের নেই, তারা কোনো cost সংখ্যা দেখে না।
6. **নতুন phase সবসময় 98-এর পরে। আগের কোনো phase কখনো আবার paste করবেন না।** (কেন: অংশ 18)
7. **এই গাইডের কিছুই লাইভ ডাটাবেসে বা আসল ফোনে চালিয়ে দেখা হয়নি।** সব পরীক্ষা scratch ডাটাবেসে আর নকল (stub) সার্ভারে হয়েছে। প্রতিটি অংশের শেষে "যাচাই হয়নি" লেখা আছে।

**চিহ্ন:** `[যাচাই হয়নি]` = কোডে বা পরীক্ষায় নিশ্চিত হইনি।

---

## সূচি

| # | ফিচার | Route |
|---|---|---|
| 1 | Recipe, costing, approval | `#/recipebook`, `#/costing`, `#/recipes` |
| 2 | Cost source ও ভাগ | `#/costsources` |
| 3 | খরচ কোন শাখার (attribution) | `#/costattrib` |
| 4 | Sales channel, inbox, web order form, Telegram | `#/saleschannels`, `#/inbox`, `#/packflags` |
| 5 | Guard: purchase, stock, GRN, void, unit | `#/guards` |
| 6 | Form বনাম screen mode | `#/formguard`, `#/unmatched`, `#/expenselink` |
| 7 | Transit shortage (ট্রানজিটে ঘাটতি) | `#/transitshort` |
| 8 | Offline POS failed screen | `#/posfailed` |
| 9 | Audit trail | কোনো পর্দা নেই |
| 10 | Accounting: stock move, card settlement, scheduler | `#/accounts` |
| 11 | Report cost source ও অজানা cost | `#/costunknown`, `#/s1setup` |
| 12 | Setup advisor (চালু করার গাইড) | `#/setupadvisor` |
| 13 | Show / Hide / Locked ও permission পরামর্শ | `#/optviews` |
| 14 | ছবি তুলে Scan | `#/scan` |
| 15 | বিক্রির পর Invoice | `#/invoiceview` |
| 16 | Template (print ও message) | `#/templates` |
| 17 | Phase 72 এর ভিত্তি (rounding, এক cost source) | `#/accounts` |
| 18 | Paste-এর নিয়ম: 98-এর পরে নতুন phase (99, 100, 101) | - |
| 19 | নিরাপত্তা-পরিবর্তন (phase 94): মালিক কী পরীক্ষা করবেন | `#/switchboard` |
| 20 | ক্যাশ ড্রয়ার অপশন (phase 95) | `#/cashdrawer` |
| 21 | Opening stock সাহায্যকারী ও cost-অপেক্ষা তালিকা (phase 96) | `#/books96` |
| 22 | Landed cost (phase 97) আর phase 98 | `#/landed` |
| 23 | কীবোর্ড-নিরাপদ sheet ও গোটানো মেনু-footer | সব পর্দা, মেনু |
| 24 | Category / Sub-category (phase 100, আসছে) | `#/categories`, `#/catreport` |
| 25 | Bill payment option ও inbox PII mask (phase 99, আসছে) | - |
| 26 | Setup advisor-এর advisor সারি (phase 101, আসছে) | `#/setupadvisor` |

---

## 1. Recipe, costing, approval (phase 73, 74)

**এক লাইনে:** কারিগরের নামে recipe বই, ধাপ (steps), approval, আর কারখানার রূপান্তর খরচ (labour, gas, বিদ্যুৎ ...) product cost-এ ঢোকানো।

**কোথায়:**
- `#/recipebook` - কারিগরের recipe বই, ধাপ, approval, print/share।
- `#/costing` - recipe cost sheet, রূপান্তর rate, মাসিক pool, true-up।
- `#/recipes` - পুরনো recipe ও production পর্দা (আগের মতোই)।

**মূল কথা:**
- Artisan-এর নাম শুধু "register" ট্যাবে দেখা যায় (মালিক বা `artisan_manage`)। বাকি সব জায়গায় `artisan-N` আর পদ।
- Approved recipe জমে যায়। বদলাতে হলে নতুন version।
- যে recipe বদলায়, সে নিজে approve করতে পারে না। **মালিক সবসময় পারে** (phase 87)। মালিক নিজের বদল approve করলে হলুদ পরামর্শ আসে: "অন্য কাউকে দিয়ে approve করান"।
- Cost = কাঁচামাল (গড় দাম) + রূপান্তর খরচ। শোরুম ও admin খরচ product cost-এ ঢোকে না।
- ধাপের সময় থেকে "শ্রম-ঘণ্টা" শুধু অনুমান দেখায়। cost-এ নিজে ঢোকে না। ঘণ্টা আপনি হাতে লেখেন।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `recipe_approval_required` | `off` = কিছু হয় না। `warn` = approve ছাড়া production-এ হলুদ লাইন। `on` = approve ছাড়া `recipe_cost` ও `production_post` বন্ধ | `off` | `warn`। কারণ বিদ্যমান সব recipe এখন unapproved। `on` দিলে সবগুলোর cost ও production আটকে যাবে |
| `recipe_self_approve` | চালু হলে যে বদলেছে সে-ই approve করতে পারে | বন্ধ | বন্ধ। দুজন চোখ থাকলে ভুল ধরা পড়ে |
| `artisan_self_view` | চালু হলে artisan শুধু নিজের recipe বই দেখে | বন্ধ | বন্ধ, যতক্ষণ না প্রতিটি artisan-এর login register-এ জোড়া হয় |
| `production_requires_recipe` | চালু হলে recipe ছাড়া হাতে-cost দিয়ে production তোলা যায় না | আগের ডিফল্ট (বন্ধ) | `#/guards` পরামর্শ: চালু। তখন প্রতিটি product cost recipe থেকে আসে। `#/setupadvisor`-এ এটা "info" (মালিক দেখে ঠিক করবেন) |
| `production_manual_needs_reason` | recipe ছাড়া হাতে-তোলা production-এ কারণ (৩+ অক্ষর) বাধ্যতামূলক | বন্ধ | চালু। হাতে-তোলা এন্ট্রি ধরা সহজ হয় |
| `production_requires_cost` | `warn` = উপাদানের cost অজানা থাকলেও production হয়, `cost_complete=false` হয়। `refuse` = অজানা cost থাকলে production বন্ধ (`cost_missing`) | `warn` | `refuse`, কিন্তু শুধু সব উপাদানের cost বসানোর পরে। আগে `warn` |
| `cost_gap_warn_pct` | আজকের কেনা দাম আর গড় খরচের ফারাক এই % ছাড়ালে হলুদ চিহ্ন | ফাঁকা (সতর্কতা নেই) | সংখ্যা প্রস্তাব নেই। কিছু আসল কেনার পর নিজে লিখুন (0 থেকে 1000 এর মধ্যে) |
| `yield_variance_warn_pct` | recipe yield আর আসল yield-এর ফারাক এই % ছাড়ালে হলুদ | ফাঁকা | সংখ্যা প্রস্তাব নেই। কিছু আসল production-এর পর নিজে লিখুন |
| `recipe_waste_required` | waste % বাধ্যতামূলক কিনা | আগের ডিফল্ট | মালিকের সিদ্ধান্ত। প্রস্তাব নেই |

**প্রতি জায়গার খরচ-পদ্ধতি** (`#/costing`, শুধু মালিক): `off` (আজকের মতো) / `recipe` (recipe-র rate) / `pool` (মাসিক আসল খরচ ÷ স্বাভাবিক মাসিক উৎপাদন)।
- Pool পদ্ধতিতে "স্বাভাবিক মাসিক উৎপাদন (kg)" আপনাকে লিখতে হবে। ফাঁকা থাকলে "অসম্পূর্ণ" দেখায়।
- Smoothing (cost type-এর সেটিং): repair 12 মাস, gas 3, electricity 3, licence বছর ÷ 12। এটা ব্রিফ থেকে নেওয়া, আপনি বদলাতে পারেন।

**চালু করলে কী বদলায়:**
- Mode `recipe`: প্রতি ব্যাচে rate যোগ হয়। (পরীক্ষার উদাহরণ: ব্যাচে labour 100, yield 10 kg, কাঁচামাল 444 হলে একক cost 44.4 থেকে 54.4।)
- Journal: Dr finished goods = কাঁচামাল + রূপান্তর, Cr কাঁচামাল, Cr `overhead_absorbed` (নতুন account 5950) = রূপান্তর।
- `#/costing` -এর true-up একটা সারি দেখায় "অনাবশোষিত ওভারহেড" = আসল মোট − absorbed মোট।

**ডিফল্টে যা বদলায় না:** Production-এর cost, সব recipe, পুরনো `#/recipes` পর্দা, পুরনো রিপোর্ট। Mode `off` থাকলে রূপান্তর খরচ যোগ হয় না। Rate, pool, স্বাভাবিক উৎপাদন সব ফাঁকা।

**সাবধান:**
- `recipe_approval_required = on` দিলে অনুমোদনহীন সব recipe-এর cost ও production বন্ধ। আগে approver বানান।
- Approver বানাতে: Staff-এ role `recipe_approver` দিন (`#/delegation`)।
- `production_requires_cost = refuse` দিলে বিনামূল্যের উপাদান (যেমন পানি) ব্যাচ আটকাবে। আগে `#/s1setup`-এ ওই আইটেম "cost শূন্য (free)" চিহ্নিত করুন (অংশ 11 দেখুন)।
- Pool মোডে মিশ্র kg ও পিস product থাকলে পিসের product অসম্পূর্ণ দেখায় (`pool_unit_not_kg`)।
- Paper form 05-3 আর app recipe আলাদা জিনিস। Section A/B/C, card-level সময়/লোক/যন্ত্র app-এ নেই। দুই জায়গায় একই তথ্য টাইপ করতে হতে পারে।
- যা তৈরি হয়নি: production-এর পরে cost সংশোধন (`production_recost`), আর bill-level landed cost (freight ইত্যাদি ভাগ)। মালিকের সিদ্ধান্ত বাকি।

**[যাচাই হয়নি]** লাইভ ডাটাবেসে, আসল ফোনে, Anek Bangla / Hind Siliguri ফন্টে (sandbox-এ system ফন্ট দিয়ে দেখা), আসল প্রিন্টারে। 5950 account ও `overhead_absorbed` mapping accountant-এর সঙ্গে মেলানো হয়নি।

---

## 2. Cost source ও ভাগ (phase 75)

**এক লাইনে:** বিদ্যুৎ, gas, ভাড়া, licence ইত্যাদির বিল আলাদা বা শেয়ার্ড মিটারে লিখে কারখানা, শোরুম, admin-এ ভাগ করা। কারখানার অংশ নিজে নিজে pool-এ যায়।

**কোথায়:** `#/costsources` (cost-দেখার অধিকার লাগে)।

**ভাগের পদ্ধতি:** sub-meter reading / ফিক্সড শতাংশ / floor area / headcount / output kg (production থেকে নিজে) / পুরো বিল এক জায়গায় / হাতে-লেখা অঙ্ক।

**অধিকার (grant):**

| Grant | কী করা যায় |
|---|---|
| `cost_bill_entry` | source, বিল, নিয়ম লেখা |
| `cost_rule_approve` | ভাগের নিয়ম approve (অন্য মানুষ হতে হবে) |

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `cost_rule_self_approve` | চালু হলে যে নিয়ম লেখে সে-ই approve করতে পারে | বন্ধ | বন্ধ। আলাদা মানুষ approve করলে ভুল ধরা পড়ে। (মালিক সবসময় approve করতে পারে) |

**চালু করলে কী বদলায়:**
- বিল ভাগ হয়ে কারখানার অংশ `factory_cost_pools`-এ যায় (source `allocated`)। Pool মোড চালু থাকলে product cost বদলায়।
- শোরুম ও admin অংশ `cost_bill_shares`-এ থাকে। `branch_overhead()` সেটা পড়ে।
- ভাগ হওয়ার পর বদলায় না। পরে নতুন নিয়ম বা back-dated নিয়ম এলেও পুরনো ভাগ একই থাকে।
- "বিল বাকি" তালিকা: কোন source-এ এই মাসের বিল নেই। মাস ফাঁকা থাকলে গড় ধরা হয় না, ফাঁকা দেখায়।

**ডিফল্টে যা বদলায় না:** কিছুই seed হয়নি। Source, rule, বিল, শতাংশ, মিটার, area সব ফাঁকা।

**সাবধান:**
- **শতাংশ ১০০ না হলে সেভ হয় না** (`percent_not_100`)। ফাঁকা ঘর থাকলে শুধু খসড়া হয়, approve হয় না।
- হাতে-লেখা অঙ্ক বিলের বেশি হলে নেয় না। কম হলে বাকিটা "অভাগিত" সারি।
- **Cost bill মানে তথ্য, payment নয়।** কোনো cash/bank/payable এন্ট্রি হয় না। Payment আগের জায়গাতেই (supplier payment, 10-2) লিখতে হবে। তাই একই বিল দুবার (এখানে বিস্তারিত, ওখানে payment) লেখা হতে পারে।
- 10-2 duplicate সতর্কতা শুধু একই জায়গা + মাস + head + অঙ্ক মিললে ধরে। Bill number দিয়ে না।
- Output-kg ভাগ শুধু kg-ভিত্তিক আইটেম গোনে। পিসের product হলে `no_output`।
- **Branch P&L ও journal এখনো এই ভাগ পড়ে না** (অংশ 3 দেখুন)।
- `cost_bill_creates_payment` (বিল থেকে payment/payable বানানো) তৈরি হয়নি। Accountant-এর সঙ্গে ঠিক করে করতে হবে।

**[যাচাই হয়নি]** লাইভ ডাটা, ফোন। শুধু "cost right আছে/নেই" এর বাইরে place-অনুযায়ী দৃশ্যমানতা (শুধু কোড পড়া)।

---

## 3. খরচ কোন শাখার (attribution) (phase 78)

**এক লাইনে:** শোরুম ও admin খরচের ভাগ কোন শাখার লাভ-ক্ষতিতে যাবে তা ঠিক করা, আর পরে হাতে সরানো (কারণসহ)।

**কোথায়:** `#/costattrib`। Grant: `cost_attrib_manage`।

**গন্তব্য:** `showroom` (ওই জায়গার P&L) / `main_centre` (মূল কেন্দ্র) / `unallocated` (কোথাও না)।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `cost_attrib_in_pl` | চালু হলে `l1_pnl` ও `l3_shop_pnl` রিপোর্টে আলাদা সারি (`cost_share`) যোগ হয়, profit কমে | বন্ধ | চালু, কিন্তু শুধু কোন খরচ কোন শোরুমের তা বসানোর পরে |
| `recipe_approval_required`, `production_requires_recipe` | এই পাতায় বোতাম সহ বাংলা ব্যাখ্যা আছে (অংশ 1 দেখুন) | - | - |

**চালু করলে কী বদলায়:**
- Branch P&L-এ নতুন সারি: "<জায়গা> · খরচ ভাগ: <type>"। মূল সারি অপরিবর্তিত।
- Unallocated ভাগ কখনো P&L-এ ঢোকে না।
- সেটিং শুধু এই মাস বা পরের মাস থেকে। আগের মাস বদলায় না (back-date নিষেধ)। বদলাতে চাইলে কারণ লাগে।
- হাতে সরানো (`cost_share_reassign`): কারণ ৩+ অক্ষর। ইতিহাস মোছা যায় না। বন্ধ (closed) মাসে শুধু মালিক পারে, আর হলুদ exception আসে।

**ডিফল্টে যা বদলায় না:** সব ভাগ "কোথাও না"। `cost_attrib_in_pl` বন্ধ থাকলে রিপোর্ট হুবহু আগের মতো (পরীক্ষায় jsonb সমান মিলেছে)।

**সাবধান:**
- `l4` মালিক-শিট, break-even (`l5`), partner profit এই ভাগ **দেখে না**, সুইচ চালু থাকলেও। ইচ্ছাকৃত। এগুলো দেখুক কিনা মালিকের সিদ্ধান্ত।
- **দুবার গোনার ঝুঁকি:** একই বিল যদি 10-2 voucher-এও থাকে, P&L-এ দুবার আসতে পারে।
- Journal/GL-এ কিছু post হয় না। এটা শুধু management রিপোর্ট।
- Approval separation পরামর্শ: একই মানুষকে `recipe_manage` + `recipe_approve`, বা `cost_bill_entry` + `cost_rule_approve` দিলে `#/delegation`-এ হলুদ পরামর্শ আসে। আটকায় না।
- P&L ON থাকলে মাসের পুরো ভাগ ধরা হয়। মাঝ-মাসের রিপোর্টে দিন-হিসাবে কাটা হয় না।

**[যাচাই হয়নি]** লাইভ ডাটা, ফোন। শুধু কোড পড়া: যাদের সব জায়গা দেখার অধিকার নেই তাদের place-scoping।

---

## 4. Sales channel, inbox, web order form, Telegram (phase 76, 77, 80, 86)

**এক লাইনে:** ফোন, walk-in, ওয়েব ফর্ম, Facebook/Instagram/WhatsApp, Telegram থেকে আসা অর্ডার ও বার্তা এক inbox-এ আনা। বার্তা নিজে অর্ডার হয় না। স্টাফ যাচাই করে অর্ডার বানায়।

**কোথায়:**
- `#/saleschannels` - channel বানানো (মালিক)।
- `#/inbox` - বার্তা ইনবক্স, অর্ডার বানানো, Telegram chat জোড়া।
- `#/packflags` - প্যাক-করা অর্ডার, বাতিল-বিক্রির flag, duplicate-order flag।
- `#/s1setup` - intake bot বানানো ও যাচাই।

**সুইচ (phase 76):**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `online_orders_on` | অনলাইন অর্ডারের খাতা | (আগের ডিফল্ট) | চালু। web form, ফোন, walk-in দিয়ে শুরু করা সহজ |
| `inbox_on` | বার্তা ইনবক্স | বন্ধ | চালু |
| `web_form_on` | ওয়েব অর্ডার ফর্ম। দাম সার্ভারে ঠিক হয়, ক্লায়েন্টের দাম বাদ | বন্ধ | চালু (কিন্তু public URL বাইরের সেটআপ) |
| `meta_intake_on` | Facebook/Instagram/WhatsApp বার্তা ঢোকা | বন্ধ | **বন্ধ**, সংযোগ না হওয়া পর্যন্ত। সংযোগ ফোনে হয় না |
| `telegram_intake_on` (phase 86) | Telegram বার্তা ঢোকা। `inbox_on`-ও লাগে | বন্ধ | সিস্টেম প্রস্তাব দেয়নি। Telegram চাইলে সেটআপের পর চালু করুন |
| `inbox_autodraft_on` | বার্তা থেকে অর্ডার খসড়া। AI নেই | বন্ধ | বন্ধ। প্রথমে স্টাফ হাতে যাচাই করুক |
| `inbox_pii_guard_on` | চালু হলে ফোন/ঠিকানা শুধু মালিক ও `inbox_contact_view` ধারক দেখে। প্রতিটি দেখা log-এ | বন্ধ | চালু। শাখার POS স্টাফ ও মালিককে অধিকার দিন |
| `web_form_captcha_on` | ওয়েব ফর্মে captcha | বন্ধ | প্রস্তাব নেই। বাইরের key লাগে, setup হলে মালিক চালাবেন |
| `web_form_rate_max` | এক device সর্বোচ্চ কতবার জমা দিতে পারবে | 10 (বার) | সংখ্যা প্রস্তাব নেই। 0 থেকে 1000 এর মধ্যে নিজে লিখুন |
| `web_form_rate_window_min` | ওই সীমার সময়-জানালা (মিনিট) | 60 | সংখ্যা প্রস্তাব নেই। 1 থেকে 1440 |
| `inbox_silence_hours` | এত ঘণ্টা বার্তা না এলে সতর্কতা। 0 = বন্ধ | 24 | সংখ্যা প্রস্তাব নেই। 0 থেকে 720 |
| `intake_max_tries` | ব্যর্থ intake কতবার retry | 5 | সংখ্যা প্রস্তাব নেই। 1 থেকে 20 |
| `intake_retry_min` | retry-র বিরতি (মিনিট, প্রতিবার try নম্বর দিয়ে গুণ) | 5 | সংখ্যা প্রস্তাব নেই। 1 থেকে 1440 |
| `web_form_public_url` | Edge function-এর URL | ফাঁকা | বাইরের সেটআপ শেষে বসবে |

**সুইচ (phase 77, অনলাইন অর্ডারের ফাঁক):**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `online_pack_warn_on` | প্যাক করার সময় স্টক কম হলে `warn:true` + কত কম। **আটকায় না** | বন্ধ | চালু। সতর্কতা মাত্র |
| `online_pack_reserve_on` | অন্য প্যাক-করা অর্ডারের পরিমাণ সতর্কতার হিসাব থেকে বাদ। কাউন্টার আটকায় না | বন্ধ | প্রস্তাব নেই। মালিক দেখে ঠিক করবেন |
| `online_keep_order_price` | ডেলিভারিতে অর্ডারের দামই থাকে। ভিন্ন দাম হলে manager অনুমতি (`price_override`) ও হলুদ exception | বন্ধ | চালু। কথা দেওয়া দাম রক্ষা হয় |

**সুইচ (phase 80):**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `packaging_return_mode` | পণ্য ফেরতে packaging: `none` = কিছু না। `restore` = বিক্রিতে কাটা packaging স্টকে ফেরত। `wastage` = শুধু নষ্ট হিসাবে রেকর্ড, স্টক বাড়ে না | `none` | S1 রিপোর্টে প্রস্তাবিত `wastage` (আগে এটা, নিরাপদ)। কিন্তু `#/setupadvisor`-এ এটা এখনো নেই, আর প্রয়োগও হয়নি |
| `partner_base_estimate` | `warn` = অংশীদার লাভের ভিত্তিতে অনুমানের cost থাকলে সতর্কতা। `refuse` = অনুমানের cost সহ লাভ-ভিত্তিক হিসাব সেভ হয় না (হাতে টাইপ করা ভিত্তি চলে) | `warn` | S1 রিপোর্টে `refuse` প্রস্তাবিত, কিন্তু প্রয়োগ হয়নি। মালিকের সিদ্ধান্ত |

**Telegram (phase 94-এর পর):** `TELEGRAM_SECRET_TOKEN` Edge function-এ **বাধ্যতামূলক**; সেট না থাকলে সব অনুরোধ 403 (অংশ 19)। Edge function deploy কম্পিউটার ছাড়া হয় না। **Telegram:** আলাদা গাইড `docs/TELEGRAM_SETUP.md`। শুধু বার্তা ঢোকে। উত্তর, ছবি ডাউনলোড, গ্রুপ নেই।

**চালু করলে কী বদলায়:**
- Inbox-এ বার্তা জমে। "অর্ডার বানাও" চাপলে অর্ডার ফর্ম নাম ও চ্যানেল ভরা অবস্থায় খোলে। পণ্য-পরিমাণ-ঠিকানা স্টাফ লেখে।
- বিক্রি void হলে অর্ডারে flag পড়ে (মোছা যায় না) আর লাল exception। অর্ডারের status চুপচাপ বদলায় না।
- একই ফোন + একই পণ্য + একই দিন + ভিন্ন channel = duplicate flag (মার্জ নয়)।
- ওয়েব ফর্মে একই জমা দুবার = ১ অর্ডার।
- `intake_bot_create`: bot-এর কাছে POS অধিকার থাকে না। সে শুধু অর্ডার তৈরি করতে পারে।

**ডিফল্টে যা বদলায় না:** সব সুইচ বন্ধ। পুরনো `online_order_*` ফাংশন, ডেলিভারি = ১ বিক্রি, স্টক একবার কাটা।

**সাবধান:**
- **"ফেসবুক/ইনস্টাগ্রাম/হোয়াটসঅ্যাপ বার্তা আসছে" - এটা এখন চলছে না।** শুধু ডাটাবেস দিক তৈরি ও পরীক্ষিত। Edge function deploy হয়নি। এটা ফোনে হয় না (`PHONE_ONLY_STEPS.md`)।
- Telegram-ও কখনো আসল Telegram-এর সঙ্গে চালানো হয়নি।
- ভুল signature/token-এর প্রতিটি অনুরোধে একটা "rejected" সারি জমে। rate limit নেই। বন্যা হলে channel বন্ধ করুন।
- Intake bot-এর password ফাঁস হলে ঝুঁকি। `intake_bot_create` দিয়ে বানালে POS অধিকার থাকে না, তাই ঝুঁকি কম। পুরনো ধরনের bot (flag + POS role) চলে, কিন্তু সে বিক্রিও করতে পারে।
- Meta-র Business Verification, App Review, বাংলাদেশে প্রাপ্যতা ও খরচ, Messenger উত্তরের সময়সীমা: কিছুই যাচাই হয়নি।
- Packaging ফেরত: `sale_return` শুধু `sale_out` ফেরত দেয়, `sale_pack` নয়। `packaging_return_mode` ঠিক করলে তবেই এটা মেটে।
- ফর্মের অর্ডারে delivery charge/advance নেই। স্টাফ পরে বদলায়।
- Channel বানানোর পর্দা (`#/saleschannels`) পরে যোগ হয়েছে (Step W)। এটা আসল ফোনে খুলে দেখা হয়নি।

**[যাচাই হয়নি]** Meta/Telegram payload-এর ক্ষেত্রের নাম (স্মৃতি থেকে লেখা), captcha প্রদানকারীর verify URL, ফোনে inbox কেমন দেখায়, `intake_retry_due` নিয়মিত চালানোর cron (লেখাই হয়নি)।

---

## 5. Guard: purchase, stock, GRN, void, unit (phase 82, 87)

**এক লাইনে:** কেনা, মাল গ্রহণ (GRN), বিল void, ইউনিট রূপান্তর, মাইনাস স্টক নিয়ে ভুল ঠেকানোর সুইচ। সিস্টেম শুধু প্রস্তাব দেয়, জোর করে না।

**কোথায়:** `#/guards` (মালিক)। প্রস্তাব ও "apply recommended" আছে। প্রস্তাবের ফাংশন: `guard_recommendations()`, `production_recommendations()`।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `purchase_grn_guard` | `off` = আজকের মতো, GRN আর বিল দুটোই স্টক বাড়ায় (পরীক্ষায় 10 kg GRN + 10 kg বিল = +20, এটাই audit-এ ধরা সমস্যা)। `skip` = GRN থাকলে বিল স্টক বাড়ায় না, কিন্তু টাকা ও supplier balance ঠিকই লেখে। `link` = GRN-এর সঙ্গে না জুড়লে বিল পোস্ট হয় না (`grn_link_required`) | `off` | `skip`, যখন স্টকের উৎস GRN। নইলে `off`। `link` বিবেচনা: GRN না আসা পর্যন্ত বিল আটকে যায় |
| `purchase_void_guard` | `off` / `warn` = void হয়, লাল `purchase_void_unsafe` লাইন / `refuse` = ফেরত আছে (`void_has_return`), স্টক মাইনাস হবে (`void_would_go_negative`), GRN batch আছে (`void_has_grn_batch`) হলে void বন্ধ | `off` | `refuse` |
| `purchase_void_payments` | `void` = বিল void হলে payment-ও void (আজকের মতো)। `keep` = payment থাকে, supplier credit হিসাবে দেখা যায়, `supplier_refund()` দিয়ে টাকা ফেরত নেওয়া যায় | `void` | `keep` |
| `unit_conv_required` | `off` / `warn` = ইউনিট অজানা হলে বিক্রি হয় কিন্তু স্টক কমে না, হলুদ / `refuse` = অনলাইন বিক্রি `unit_unknown` দিয়ে ফেরত। দেরিতে আসা offline বিক্রি (২ মিনিটের বেশি পুরনো) নেওয়া হয় আর লাল `stock_unit_unknown_late`। আইটেম editor-ও রূপান্তর ছাড়া tracked করতে দেয় না | `warn` | `refuse`, কিন্তু শুধু `unit_unknown_items()` = 0 হলে। নইলে `warn` |
| `neg_grant_log` | চালু হলে `sell_below_zero` অধিকার দিয়ে মাইনাসে বিক্রি করলে হলুদ লাইন (আইটেম, পরিমাণ, কে) | বন্ধ | চালু |
| `production_negative_reason` | `off` / `warn` / `required` = স্টক মাইনাস হয়ে production-এ কারণ (note) ছাড়া হবে না (`production_negative_reason_needed`) | `off` | `required` |
| `stock_negative_mode` (পুরনো সুইচ) | মাইনাস স্টকে কী হবে | `warn` | প্রথম stock count বা opening হওয়ার পর block। মালিকের সিদ্ধান্ত |
| `expiry_sale_guard` (phase 87) | `off` = আজকের মতো (লাল `sold_expired`)। `warn` = বিক্রি হয়, লাল লাইনে batch id ও মেয়াদ। `refuse` = `expired_stock_blocked`, কিছু post হয় না | `off` | সিস্টেম প্রস্তাব দেয়নি। `refuse` দিলে যে আইটেমের স্টক শুধু মেয়াদোত্তীর্ণ তা আর বিক্রি হবে না, লাইন-ভিত্তিক override নেই |
| `production_double_issue_guard` | `off` / `warn` = একই আইটেম, জায়গা, দিনে production আর stock issue দুটোই হলে হলুদ `production_double_issue`। কখনো আটকায় না | `off` | `warn` |
| `purchase_backdate_flag` | `off` / `warn` = পুরনো তারিখের বিল পোস্ট হয়, হলুদ `purchase_backdated`। স্টক stamp এখনো "আজ" | `off` | সিস্টেম প্রস্তাব দেয়নি |

**চালু করলে কী বদলায়:** উপরের টেবিলের "অপশন ও মানে" কলাম দেখুন। `refuse` মানে কাজ আটকে যাবে। প্রথমে `warn` রেখে হলুদ লাইন দেখে নিন।

**ডিফল্টে যা বদলায় না:** সব ডিফল্ট আজকের আচরণ। একটা ব্যতিক্রম নেই।

**সাবধান:**
- GRN আর বিল দুটোই স্টক বাড়ালে স্টক দ্বিগুণ হয়। `purchase_grn_guard` না দিলে এটা চলতেই থাকবে।
- `purchase_void_guard = refuse`: ইতিমধ্যে ব্যবহার হয়ে যাওয়া GRN batch (qty_remaining 0) `void_has_grn_batch` ধরে না। শুধু মাইনাস-স্টকের পরীক্ষা ধরে। মালিকের সিদ্ধান্ত।
- `link` মোডে GRN এখনো না এলে বিল আটকে যায়।
- `never_opened_negative_items()`: কখনো opening না-হওয়া আইটেম `warn` মোডে মাইনাসে গেলে `stock_negative` লাইন আসে না। এই তালিকা দেখুন।
- `client_id` একই ব্যবহারকারী ভিন্ন কার্টে আবার পাঠালে পুরনো বিক্রিই ফেরে (আসল retry আর ভুল reuse আলাদা করা যায় না)। অন্য ব্যবহারকারী পুনর্ব্যবহার করলে `client_id_taken`।
- `phase82` এর `[যাচাই হয়নি]`: পূর্ণ build-এ phase 88 এর পর phase82 test 53 পাস / 4 ফেল (phase 73-78-এর উপর লেখা ছিল বলে)। কারণ খোঁজা হয়নি।

**[যাচাই হয়নি]** `#/guards` পাতা আসল ব্রাউজারে; "apply recommended" বোতাম ব্রাউজারে; bill void-এর পর day book/GL-এ payment-এর আচরণ; offline POS replay আসল ফোনে।

---

## 6. Form বনাম screen mode (phase 83)

**এক লাইনে:** কাগজের ফর্ম (05-1 production, 10-2 খরচ) আর স্ক্রিন-এন্ট্রি একই জিনিস দুবার গুনলে তা ধরা বা ঠেকানো।

**কোথায়:**
- `#/formguard` - চারটা সুইচ ও প্রস্তাব (মালিক)।
- `#/unmatched` - স্ক্রিন-রেকর্ডহীন ফর্ম-লাইন।
- `#/expenselink` - দ্রুত খরচ আর 10-2 voucher একসঙ্গে জোড়া।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `form_051_mode` | `reference` = আজকের মতো (ফর্ম শুধু রেফারেন্স, আইটেম +, cost ফাঁকা, কাঁচামাল কাটে না। হলুদ `form051_cost_null`)। `post` = কাঁচামাল গড় দামে কাটে, তৈরি মাল cost সহ ঢোকে। recipe না থাকলে বা মাল কম হলে পুরো লাইন ব্যর্থ, কিছু অর্ধেক হয় না। `refuse` = লাইন skip (`form051_not_a_source`) | `reference` | `post`, যদি 05-1 ই আসল production রেকর্ড হয়। নইলে `reference` |

**টেবিলের পরের তিনটা সুইচ `form_guard_recommendations()` দেখায়:** `transit_short_mode`, `transit_open_hours`, `offline_soft_stock` (পরের দুই অংশে)।

**অন্যান্য:**
- `dup_suspects`: একই দিন একই আইটেমে production run আর `stock_production_in` থাকলে সন্দেহ flag।
- `expense_link_apply`: voucher-এর **প্রতিটি লাইন** দ্রুত খরচে মিললে তবেই জোড়া লাগে (day book একবার গোনে)। একটাও না মিললে `not_fully_covered`।

**চালু করলে কী বদলায়:** `post` মোডে 05-1 অনুমোদনে স্টক ও cost সত্যি বদলায়। এটা বড় বদল।

**ডিফল্টে যা বদলায় না:** `reference` = আজকের আচরণ।

**সাবধান:**
- ফর্মের 05-3 / 10-2 আর app-এর recipe/cost একই তথ্য দুই জায়গায় রাখে। সব মিল মেলানো হয়নি।
- যে voucher আগেই auto-post হয়ে গেছে তা পরে shadow হলে GL-এ কী হয়, কোড পড়ে বোঝা। চালিয়ে দেখা হয়নি।
- 10-2 অনুমোদনের সময় "জোড়া লাগান" প্রস্তাব ফর্মের ভেতরে বসানো হয়নি। আলাদা পর্দা `#/expenselink`।

**[যাচাই হয়নি]** আসল ফোন, লাইভ ডাটা, GL-এ shadow voucher-এর প্রভাব।

---

## 7. Transit shortage (ট্রানজিটে ঘাটতি) (phase 83, 85)

**এক লাইনে:** এক জায়গা থেকে 10 পাঠালে অন্য জায়গা 6 পেলে, বাকি 4 কোথায় গেল তা দেখা ও হিসাবে বসানো।

**কোথায়:** `#/transitshort`। অনুমানিক হিসাব: `transit_short_open()`। মূল্য শুধু cost-অধিকারীরা দেখে।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `transit_short_mode` | `keep_in_transit` = ঘাটতি কিছু লেখে না, তালিকায় থাকে (আজকের মতো)। `loss` = ঘাটতি sender-এর cost-এ `transit_loss` হিসাবে লেখে | `keep_in_transit` | `loss`। নইলে ঘাটতি অনির্দিষ্ট কাল পড়ে থাকে |
| `transit_open_hours` | এত ঘণ্টার বেশি খোলা transfer `urgent_alerts`-এ। ফাঁকা = সতর্কতা নেই | ফাঁকা | সংখ্যা প্রস্তাব নেই। আপনি লিখবেন (1 থেকে 8760) |
| `acct_transit_loss` | হিসাবের খাতায় ঘাটতি Dr `transit_loss` (5130) | বন্ধ | অংশ 10 দেখুন |
| `acct_transit_loss_at` | `receiver` = যে পেয়েছে তার জায়গায় লোকসান। `sender` = পাঠানো জায়গায় | `receiver` | প্রস্তাব নেই। `receiver` হলে clearing account-এ sender +V ও receiver −V থাকে, যতক্ষণ না মালিক মেটায় |

**চালু করলে কী বদলায়:** `loss` মোডে ঘাটতির টাকা sender-এর cost-এ খরচ হিসাবে ledger-এ যায়। পুরো পেলে কিছু লেখে না। `transit_short_resolve()` দিয়ে পরে নিষ্পত্তি (কারণ লাগে, একবারই)।

**ডিফল্টে যা বদলায় না:** ঘাটতি কোথাও লেখা হয় না।

**সাবধান:** `loss` লেখার সময় cost ফাঁকা থাকে ও গড় বদলায় না। ঘাটতি `transit_loss` ledger কারণ এখন আছে, কিন্তু journal-এ যেতে `acct_transit_loss` লাগে।

**[যাচাই হয়নি]** আসল transfer-এ পর্দা, urgent alert-এর email পথ (`tools/notify_digest.py` চালানো হয়নি)।

---

## 8. Offline POS failed screen (phase 83)

**এক লাইনে:** offline বিক্রি পরে sync-এ আটকে গেলে (যেমন স্টক নেই) তা হারায় না। "আটকে যাওয়া sale" তালিকায় থাকে।

**কোথায়:** `#/posfailed`। বোর্ডে ব্যাজ।

**সুইচ ও অধিকার:**

| নাম | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `offline_soft_stock` | চালু হলে দেরিতে sync হওয়া offline বিক্রি স্টক কম থাকলেও নেয় (হলুদ `offline_soft_stock`)। অনলাইন পথে এখনো `insufficient_stock` | বন্ধ | চালু। মাল তো আগেই ক্রেতার হাতে |
| grant `pos_replay_override` | manager কারণসহ (৩+ অক্ষর) আটকানো sale জোর করে পাঠাতে পারে। এক log সারি + হলুদ exception। বন্ধ period এখনো আটকায় | কারও নেই | ম্যানেজারদের দিন। মালিকের সিদ্ধান্ত: ক্যাশিয়ারের ফোনে জরুরি approval link বানানো হবে কিনা |

**চালু করলে কী বদলায়:** আটকে যাওয়া sale-এর কার্ড ফোনে থাকে, সার্ভারে সারাংশ (গ্রাহকের তথ্য ছাড়া) যায়। "বাতিল"-এ সার্ভারের কার্ডও বন্ধ হয়। কার্ড কখনো মোছা হয় না।

**ডিফল্টে যা বদলায় না:** সুইচ বন্ধ = অফলাইন sale-ও `record_sale2` নিয়মে (স্টক নেই = refuse)। `pos.js` এ পাঁচ লাইনের বদল `posfail.js` না থাকলে কিছু করে না।

**সাবধান:**
- দেরিতে নেওয়া sale-এ স্টক মাইনাস হতে পারে (পরীক্ষা: 2−5 = −3)।
- আটকে যাওয়া কার্ড শুধু ওই ফোনের localStorage-এ থাকে। ফোন বদলালে/মুছলে কার্ড যায়, সার্ভারে শুধু সারাংশ।
- ক্যাশিয়ার নিজের ফোন থেকে override করতে পারে না, যদি না তার `pos_replay_override` থাকে বা manager ওই ফোনে login করে।

**[যাচাই হয়নি]** আসল ফোন/ব্রাউজারে বোতাম, আসল offline replay, concurrent override + original replay race।

---

## 9. Audit trail (phase 84)

**এক লাইনে:** স্টকের মূল টেবিল চুপচাপ মুছে বা বদলে ফেলা বন্ধ, আর বদল হলে `audit_log`-এ কে কী বদলাল লেখা।

**কোথায়:** কোনো পর্দা বা সুইচ নেই। ডাটাবেসের trigger। SQL paste করলেই চালু।

**কী ঘটে:**

| টেবিল | কী নিষেধ | কী log হয় |
|---|---|---|
| `stock_balance` | মোছা (শুধু একদম খালি ভুতুড়ে সারি ছাড়া), item/জায়গা বদল | হাতে qty/avg_cost বদল |
| `stock_batches` | মোছা, item/জায়গা/qty_made/made_at বদল | qty_remaining, মেয়াদ, note বদল |
| `stock_transfers` | মোছা | status বদল |
| `purchase_lines` | পোস্ট-করা বিলের লাইন মোছা বা qty/দাম/বিল বদল | description বদল |
| `production_runs` | - | status/void বদল (void হলে একটি সারি) |
| `stock_reconcile(true)` | - | সংশোধিত প্রতিটি balance-এর জন্য ঠিক একটি `reconcile_fix` সারি |

**ডিফল্টে যা বদলায় না:** বিক্রি, receive ইত্যাদি স্বাভাবিক পথ। **ইচ্ছাকৃতভাবে** `stock_balance`-এর যেসব বদল ledger থেকে আসে (বিক্রি, receive) তা log হয় না, কারণ ledger থেকেই বের করা যায়। সব log করলে প্রতি বিক্রি ~19% ধীর হতো (scratch DB মাপ)।

**সাবধান:**
- খসড়া বিলের লাইন এখনো বদলানো যায়। পোস্ট-করা লাইন জমে যায়।
- `phase21`/`phase22` এর পুরনো টেস্ট-ফিক্সচার `delete from stock_balance` করে, নতুন নিয়মে ফেল করে। এটা পণ্যের সমস্যা নয়, টেস্ট ফাইলের। (`phase22b_test.sql` ঠিক করা কপি আছে।)
- যেসব জিনিসে audit/no-delete যোগ হয়নি: `production_runs` মোছা, `entry_ledger_posts`, `serials`, `item_price_history`। মালিকের সিদ্ধান্ত।
- অন্য trigger-এর ভেতর থেকে `stock_balance` বদলালে (depth > 1) log বাদ যায়। আজ এমন কোড নেই।

**[যাচাই হয়নি]** service_role / Edge function পথে (শুধু `postgres` ব্যবহারকারীতে পরীক্ষা), লাইভ audit_log বৃদ্ধি, গতির সংখ্যা Supabase প্ল্যানে ভিন্ন হতে পারে।

---

## 10. Accounting: stock move, card settlement, scheduler (phase 85)

**এক লাইনে:** স্টক গণনার পার্থক্য, opening stock, issue, transfer, ঘাটতি, ক্রয়-ফেরত পার্থক্য খাতায় তোলা; হাতে-journal-এ কারণ চাওয়া; card-এর টাকা bank-এ মেলানো; scheduler দিয়ে নিজে নিজে post।

**কোথায়:** `#/accounts`। সুইচ `#/switchboard`-এ। Card settlement, scheduler, pending alert আর ৮টা books সুইচের জন্য **আলাদা পর্দা আছে: `#/books85`** (মেনুর Accounts group, মালিক ও accounts-অধিকারীর জন্য)। তিন ট্যাব: Card settlement (জায়গা বেছে, তারিখ/gross/fee/bank, বাতিল করতে কারণ লাগে), Auto posting (pending/locked সতর্কতা, Run now, scheduler চালু/বন্ধ, run-এর ইতিহাস), Books switches (প্রতিটির পাশে Now ও Recommended; ON করার আগে সতর্কতা-sheet আসে, OFF সঙ্গে সঙ্গে হয়)। শুধু মালিক সুইচ বদলায়। Scheduler চালাতে সার্ভারে `pg_cron` লাগে, ফোনে হয় না।

**`#/books85`-এর "Recommended" পর্দায় হিসাব করা (SQL-এ নেই), কোডের নিয়ম:** count_adjust ON, issue_out ON, purchase_variance ON, stock_opening OFF (আগে `acct_opening` দেখুন), transfer_mode `location_tagged` যদি একের বেশি জায়গা, নইলে `off`, transit_loss ON যদি transfer_mode `off` না হয়, transit_loss_at `receiver`, from-date ফাঁকা। এগুলো লেখকের বিচার, accountant নিশ্চিত করেননি।

**গুরুত্বপূর্ণ:** `accounting_on` আগে চালু থাকতে হবে। শুরুর তারিখ, chart, mapping, opening balance ঠিক থাকতে হবে (অংশ 12-এর readiness দেখুন)।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `accounting_on` | হিসাব চালু | বন্ধ | চালু, কিন্তু শুধু শুরুর তারিখ, mapping, opening ঠিক হলে। কখন চালু হবে তা মালিকের সিদ্ধান্ত |
| `accounting_autopost` | আজকের কাগজ নিজে post | (আগের) | চালু। হাতে post করতে হয় না, pending জমে না |
| `acct_count_adjust` | গণনার পার্থক্য Dr/Cr `stock_adjust` (5110) | বন্ধ | সিস্টেম প্রস্তাব দেয়নি |
| `acct_stock_opening` | Opening stock Dr inventory / Cr owner capital (3100, বদলানো যায়)। শুধু হিসাব-শুরুর তারিখ বা তার পরের opening | বন্ধ | সিস্টেম প্রস্তাব দেয়নি। **সাবধান নিচে** |
| `acct_issue_out` | নিজের কাজে issue: Dr `stock_issue_use` (5120) / Cr inventory | বন্ধ | সিস্টেম প্রস্তাব দেয়নি |
| `acct_transfer_mode` | `off` = কিছু না। `location_tagged` = পাঠানো আর পাওয়ার আলাদা এন্ট্রি, নিজ নিজ জায়গার ট্যাগে, `interloc_clearing` (1230) দিয়ে। `company_wide` = মালিক ধরেছে খাতা পুরো কোম্পানির, জোড়া এন্ট্রি হয় না | `off` | সিস্টেম প্রস্তাব দেয়নি |
| `acct_transit_loss` | ঘাটতি Dr `transit_loss` (5130) | বন্ধ | সিস্টেম প্রস্তাব দেয়নি |
| `acct_purchase_variance` | ক্রয়-ফেরতের পার্থক্য `purchase_variance` (5140) | বন্ধ | সিস্টেম প্রস্তাব দেয়নি |
| `acct_stock_moves_from` | তারিখ (ফাঁকা = সব)। এর আগের স্টক move বাদ | ফাঁকা | **backlog বাঁচাতে** দেরিতে সুইচ চালালে একটা তারিখ দিন |
| `manual_journal_guard` | `off` / `on` = ইনভেন্টরি, COGS, বিক্রি, payable, receivable ইত্যাদি account-এ হাতে-লাইনে কারণ-কোড লাগে। payable/receivable-এ party লাগে | `off` | সিস্টেম প্রস্তাব দেয়নি |
| `acct_scheduler_on` | `acct_autopost_tick()` মানুষ ছাড়া চলতে পারে | বন্ধ | সিস্টেম প্রস্তাব দেয়নি। pg_cron লাগে, ফোনে হয় না |
| `acct_pending_alert_days` | এত দিনের পুরনো pending কাগজ alert | 1 | সংখ্যা প্রস্তাব নেই। 0 থেকে 365 |

**Card settlement:** `card_settle(জায়গা, তারিখ, gross, fee, note, client_id, bank_mode)` = Dr bank (net) + Dr bank_charges (fee) / Cr card receivable (gross)। `card_settle_void` বাতিল, `card_settlement_list` অসমাপ্ত দেখায়। শুধু আপনার টাইপ করা অঙ্ক post হয়। `gross` অমীমাংসিতের বেশি হলে "over" ইঙ্গিত দেয়, আটকায় না।
10-2 voucher-এ ঐচ্ছিক "কীভাবে দিলেন" (cash/bank/mobile)। ফাঁকা = cash (আগের মতো)।

**চালু করলে কী বদলায়:**
- সুইচ চালালে **আগের সব ঘটনা** হিসাব-শুরুর তারিখ (বা `acct_stock_moves_from`) পর্যন্ত পিছিয়ে মূল তারিখে post হয়। বন্ধ period-এর তারিখ আটকে থাকে (locked), শুধু মালিক জোর করে post করতে পারে।
- Reports == journals: trial balance ও রিপোর্ট journal-এর সঙ্গে মেলে (পরীক্ষায় 7050 = 7050)। `inventory_vs_gl` ব্যাখ্যা করে কেন ledger আর GL-এ পার্থক্য।
- Cost অজানা (NULL) থাকলে সারি `cost_missing` হয়ে অপেক্ষায় থাকে। কিছু বানানো হয় না।

**ডিফল্টে যা বদলায় না:** সব সুইচ বন্ধ থাকলে কিছুই নতুন post হয় না (পরীক্ষা A)।

**সাবধান:**
- **`acct_stock_opening` চালাবেন না, যদি opening stock আগেই শুরুর জের (`acct_opening`)-এ থাকে। নইলে দুইবার গোনা হবে।**
- **Backlog:** সুইচ চালু করার সঙ্গে সঙ্গে পুরনো ঘটনার সব entry এসে যায়। আগে `acct_stock_moves_from` তারিখ দিন, `#/accounts`-এ dry run দেখুন।
- `acct_transit_loss_at = receiver` হলে clearing account নিষ্পত্তি না হওয়া পর্যন্ত sender +V ও receiver −V দেখায়।
- Account 5110 থেকে 5140 ও owner capital (3100) ডিফল্ট। আপনি `acct_mapping_set` দিয়ে বদলাতে পারেন। accountant-এর সঙ্গে মেলানো হয়নি।
- **পুরনো `phase40.sql` / `ALL_NEW10.sql` phase 85 এর পরে আবার paste করবেন না।** এতে `acct_journal_post`-এর পুরনো রূপ ফিরে ambiguity হয়।
- Form-path (04-2/05-1) থেকে আসা count gain/transfer-in-এর cost ledger-এ NULL থাকলে `cost_missing` হয়ে অপেক্ষায় থাকে। D2 (opening stock সাহায্যকারী) ও D3 (cost-অপেক্ষা তালিকা) phase 96-এ বানানো হয়েছে (অংশ 21)।
- `purchase_variance` শুধু purchase-এর item-type key ধরে। `purch_consumable`-এ বুক হওয়া stock-tracked item বাদ।

**[যাচাই হয়নি]** আসল Supabase, আসল pg_cron (শুধু ছদ্ম schema), card/bank আসল অঙ্ক, concurrent poster, `#/books85`-এর ফোনের চেহারা (360px দেখা হয়নি, শুধু নকল DOM-এ 351 চেক), `<select>` ট্যাপ।

---

## 11. Report cost source ও অজানা cost (phase 72, 80, 88)

**এক লাইনে:** সব রিপোর্টে বিক্রিত মালের cost একই উৎস থেকে নেওয়া (journal যা বুক করে সেটাই), আর অজানা cost 0 ধরা হয় না।

**কোথায়:** `#/costunknown` (রিপোর্ট group), `#/s1setup` (free-cost চিহ্ন)।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `report_cost_source` | `ledger_then_item_costs` = বিক্রিত মালের cost স্টক ledger থেকে (journal যা বুক করে), ledger-এ cost না থাকলে হাতে-দেওয়া `item_costs` (অনুমান হিসাবে চিহ্নিত)। `ledger_avg` = শুধু ledger, না থাকলে **অজানা**। `item_costs` = শুধু হাতে-দেওয়া cost (পুরনো `biz_items`/report-builder আচরণ, আর `biz_daily`-ও এতে বদলে যায়) | `ledger_then_item_costs` | ডিফল্ট রাখুন (journal-এর সঙ্গে মেলে)। Journal সবসময় ledger ব্যবহার করে, এই সুইচে বদলায় না |

**বদল যা ডিফল্টেও হয়:** আগে `biz_daily` ledger-first ছিল কিন্তু `biz_items`, report builder, `items_with_cost` শুধু হাতে-দেওয়া cost পড়ত। এখন সবগুলো ledger-first। যেখানে ledger cost আর হাতে-দেওয়া cost আলাদা, সেখানে সংখ্যা **বদলে যাবে**। পুরনো সংখ্যা ফেরাতে `item_costs` দিন।

**অজানা cost:**
- Cost ফাঁকা বা 0 = অজানা। রিপোর্টে `unknown_cost_rev` (খরচহীন বিক্রি) আলাদা দেখায়, আয়কে "সাময়িক" বলে চিহ্নিত করে। বিক্রি বন্ধ হয় না।
- `biz_items`-এর cogs অংশ-অজানা হলে NULL (শূন্য নয়)। Report builder-এ cogs ফাঁকা থাকে।
- **Free-cost চিহ্ন** (`#/s1setup`, phase 80): যেসব আইটেমের cost সত্যিই শূন্য (যেমন পানি), সেগুলোকে "জানা শূন্য" চিহ্নিত করুন। কারণ ৩+ অক্ষর লাগে। `cost_unknown_items()` তালিকা দেখায় কোনগুলো এখনো অজানা। Production, রিপোর্ট ও posting তখন তাদের "খরচহীন" ধরে না।

**ডিফল্টে যা বদলায় না:** Journal/GL। রাউন্ডিং ঠিক করা হয়েছে (সব entry balanced)। Partner profit-এ অনুমান-ভিত্তি থাকলে সতর্কতা (`estimated_base`)।

**সাবধান:**
- Free-cost চিহ্ন রিপোর্টের সময় পড়া হয়। চিহ্ন দিলে পুরনো বিক্রি/production-ও "জানা শূন্য" হিসাবে পড়া হবে (আগে post-করা journal আবার post হয় না)। চিহ্ন তুললে পতাকা ফিরে আসে।
- `recipe_cost` এখনো ফাঁকা উপাদান-cost অজানা ধরে কিন্তু 0 জানা ধরে। phase 72 শুধু production ও রিপোর্টে 0 = অজানা করেছে।
- Phase 72 এর পর `biz_daily` প্রায় 3 গুণ ধীর (synthetic ৬০,০০০ বিক্রিতে 0.44 সেকেন্ড থেকে 1.37 সেকেন্ড)। আজকের ডাটা-আকারে সমস্যা নয়।
- Biz/Reports পাতায় `cost_missing` বা `item_cost_status88` এর কোনো পর্দা বানানো হয়নি। শুধু `#/costunknown`।

**[যাচাই হয়নি]** লাইভ ডাটা, বড় ledger-এ গতি, আসল ফোন। phase 82 test পূর্ণ build-এ 4 ফেল (কারণ খোঁজা হয়নি)।

---

## 12. Setup advisor - চালু করার গাইড (phase 81)

**এক লাইনে:** কোন সুইচ কী মানে রাখা ভালো, চালু করার আগে কী কী ঠিক থাকতে হবে, আর এখন সব ঠিকঠাক চলছে কিনা, এক পর্দায়।

**কোথায়:** `#/setupadvisor` (মালিক বা cost-দেখার অধিকার)। চারটা ট্যাব:

| ট্যাব | কাজ | ফাংশন |
|---|---|---|
| Recommended | ৩০টা সুইচের প্রস্তাবিত মান, কারণ, এখনকার মান | `setup_recommendations()` |
| Before switching on | চালু করার আগের প্রস্তুতি। শুধু সংখ্যা, কোনো টাকার অঙ্ক নয় | `setup_readiness(topic)` |
| Is it all flowing | সব ঠিকঠাক বইছে কিনা | `setup_flow_check()` |
| History | কে কবে কী apply করেছে | `setup_apply_history()` |

**স্ট্যাটাস:** `ok` (ইতিমধ্যে প্রস্তাবিত মানে) / `recommended` (প্রস্তাব আছে, মান ভিন্ন) / `owner_chosen` (আপনি আগেই বেছেছেন, **কখনো উপরে লেখে না**) / `info` (সংখ্যা বা মালিকের সিদ্ধান্ত, কোনো মান প্রস্তাব নেই) / `not_installed` (SQL এখনো paste হয়নি)।

**Apply:** মালিক-only। `Apply` প্রতি সারিতে, `Apply all`, `Replace my value` (নিশ্চিত করতে হয়), `Apply anyway` (প্রস্তুতি ঠিক না থাকলেও, নিশ্চিত করতে হয়)। প্রস্তুতি ঠিক না থাকলে সারি `not_ready` বলে skip হয়। একই `client_id` দ্বিতীয়বার = আগের উত্তরই। ইতিহাস মোছা যায় না।

**Readiness-এর topic (তালিকা):**

| Topic | কী দেখে (check code) |
|---|---|
| `stock_tracking` | tracked আইটেম (`stk_tracked`), base unit (`stk_unit`), opening stock (`stk_opening`), unit conversion (`stk_conv`), অজানা cost (`stk_cost`), মাইনাস স্টক (`stk_neg`) |
| `accounting` | শুরুর তারিখ (`acc_start`), chart (`acc_coa`), mapping (`acc_map`), opening entry (`acc_opening`), cost-এর জন্য অপেক্ষায় (`acc_wait`), posting ভুল (`acc_err`) |
| `production` | চালু recipe (`prd_recipes`), উপাদান (`prd_lines`), yield (`prd_yield`), approve (`prd_approve`), উপাদানের cost (`prd_icost`), recipe-ইউনিট conversion (`prd_unit`), খরচ-পদ্ধতি সম্পূর্ণ (`prd_conv`) |
| `cost_sources` | source (`cs_sources`), approved নিয়ম (`cs_rule`), শোরুম ভাগ (`cs_attrib`) |
| `online` | চালু channel (`onl_channels`), public URL (`onl_url`), intake user (`onl_bot`) |

**Flow check-এর তালিকা ("সব ঠিকঠাক বইছে?"):**

| Code | কী দেখে | কোন সুইচ চালু থাকলে |
|---|---|---|
| `flw_acc_old` | আগের দিনের কাগজ এখনো খাতায় ঢোকেনি | `accounting_on` |
| `flw_acc_err` | auto-post ভুল জমে আছে | `accounting_on` |
| `flw_acc_wait` | cost অজানা বলে কাগজ অপেক্ষায় | `accounting_on` |
| `flw_neg` | মাইনাস স্টক | সবসময় |
| `flw_prod_cost` | cost অসম্পূর্ণ রেখে production | সবসময় |
| `flw_pool` | pool পদ্ধতির জায়গায় এই মাসের খরচ নেই | সবসময় |
| `flw_inbox_new` | আগের দিনের বার্তা দেখা হয়নি | `inbox_on` |
| `flw_inbox_silent` | সীমার বেশি কোনো বার্তা আসেনি (সংযোগ ঠিক আছে?) | `inbox_on` |
| `flw_intake_fail` | intake ব্যর্থ হয়ে আছে | `inbox_on` |
| `flw_oo_flags` | অনলাইন অর্ডারের খোলা flag | `online_orders_on` |

বন্ধ থাকা সিস্টেমের সারি `na` দেখায়।

**ডিফল্টে যা বদলায় না:** কিছু আটকায় না। সব উপদেশ। বিক্রি, ক্রয়, production, journal, অর্ডার সব আগের মতো।

**সাবধান:**
- সংখ্যার সুইচের (cost gap %, rate limit, silence hours ইত্যাদি) মান সিস্টেম কখনো প্রস্তাব করে না।
- `recipe_approval_required = warn` আর `cost_attrib_in_pl = on` এর প্রস্তাব রিপোর্ট লেখকের পড়া, মালিকের স্পষ্ট উত্তর নয়।
- `acc_map`-এর দরকারি key তালিকা (sales, cogs, inv_finished, inv_raw, inv_pack, payable, receivable, pay_cash, owner_capital, overhead_absorbed) বাছাই করা। phase 85 এর নতুন key (stock_adjust ইত্যাদি) এতে যাচাই হয় না।
- **Phase 80 (S1) এর দুটো সুইচ (`partner_base_estimate`, `packaging_return_mode`) এই তালিকায় নেই** (phase 81 আলাদা শাখায় লেখা)। একইভাবে phase 82 থেকে 93-এর সুইচগুলোও এখানে নেই (অংশ 5, 6, 7, 10 এর `#/guards`, `#/formguard` এ দেখুন)। [কোডে যাচাই: `setup_rec_defs81`-এ সারি যোগ করে শুধু `phase81.sql`। phase 80, 82..93 কেউ যোগ করেনি।]
- `expiry_sale_guard`, `purchase_backdate_flag` কোনো প্রস্তাব-তালিকায় নেই।

**[যাচাই হয়নি]** ফোনের চওড়ায় আসল রেন্ডার (stub DOM-এ পরীক্ষা), দুই মালিক একসঙ্গে apply।

---

## 13. Show / Hide / Locked ও permission পরামর্শ (phase 91)

**এক লাইনে:** প্রতিটি মেনু/ফর্ম ব্যক্তি বা ভূমিকা অনুযায়ী দেখানো, লুকানো বা তালা দেওয়া। আর কার কোন অধিকার দরকার বা কোন দুটো এক মানুষের না থাকাই ভালো, সেই পরামর্শ।

**কোথায়:** `#/optviews` (শুধু মালিক)।

**অপশন:**

| Mode | মানে |
|---|---|
| `show` | দেখায় (ডিফল্ট) |
| `hide` | মেনু, search, bottom bar থেকে বাদ |
| `locked` | থাকে, " · locked" চিহ্ন। ট্যাপে "মালিককে জিজ্ঞেস করুন" |
| `default` | আপনার পছন্দ মুছে ডিফল্টে |

ব্যক্তি-সারি ভূমিকার সারিকে হারায়। একাধিক ভূমিকায় কম-নিষেধ জেতে: show > locked > hide।

**বাল্ক বোতাম:** Hide all not granted / Show all / Locked for not granted / Reset all to default। প্রতিটির পাশে "Granted / Not granted"।

**Permission পরামর্শ** (`permission_recommendations(user)`, শুধু উপদেশ):
- `recommended_missing` - এই ভূমিকায় সাধারণত দরকারি, কিন্তু নেই এমন grant।
- `not_recommended_combo` - একসঙ্গে না থাকাই ভালো জোড়া (১৫টা seed)। যেমন ক্রয় লেখা + supplier payment/void, recipe বদল + approve, বিক্রি void + stock count adjust, cost দেখা + price/discount, payroll + salary structure, `intake_bot` + যেকোনো POS অধিকার।
- `unused` - অনুমতিহীন ফর্ম, Hide প্রস্তাব।
- এক-ট্যাপ `Apply` / `Ignore` / `Undo`। Apply কেবল মালিক পারে, audit হয়। ভূমিকা থেকে আসা অধিকার ব্যক্তিগতভাবে ফেরত নেওয়া যায় না (`not_personal_grant`)।

**সুইচ:** নেই। মান ভাগ করা তালিকা (`user_option_view`, `role_option_view`)।

**চালু করলে কী বদলায়:** নেভিগেশনে Hide করা অপশন উধাও। Locked এ তালা চিহ্ন।

**ডিফল্টে যা বদলায় না:** কোনো সারি না থাকলে কারও view বদলায় না।

**সাবধান (খুব গুরুত্বপূর্ণ):**
- **Hide/Locked কোনো অনুমতি দেয় না বা কাড়ে না।** এটা শুধু UI গোছানো।
- অনুমতি আছে এমন hidden পাতা সরাসরি লিংকে এখনো খোলে।
- অনুমতি নেই এমন locked পাতা সার্ভার নিজেই refuse করে।
- Locked ট্যাপ ধরা শুধু `nav_go` ও `go` বোতামে। অন্য কোনো লিংক বা বোতাম থেকে সরাসরি hash বদলালে locked পাতাও খুলতে পারে (অনুমতি থাকলে)।
- `r:home` ও `r:optviews` hide/locked করা যায় না। মালিক নিজেকে বন্ধ করতে পারবে না।
- "কখনো ব্যবহার করেনি" ধরণের পরামর্শ ব্যবহার-ইতিহাস থেকে বানানো হয়নি।
- Hide একবার লাগালে পরামর্শ-তালিকার বদল দ্বিতীয়বার paste করলেও থাকে (`ON CONFLICT DO NOTHING`)।
- পরামর্শের কারণ-বাক্য আজকের default থেকে নেওয়া সাধারণ বাক্য। ব্যবসায়িক কারণ আপনি `reco_role_set` দিয়ে লিখতে পারেন।

**[যাচাই হয়নি]** আসল ফোন বা লাইভ ডাটা; Home-এর বড় কার্ড বা অন্য ফাইলের নিজস্ব `location.hash=` বোতাম `entries()` ব্যবহার না করলে Hide দেখায় না।

---

## 14. ছবি তুলে Scan (phase 90)

**এক লাইনে:** বিল, পণ্যের তালিকা, খরচের রসিদের ছবি তুলুন। সিস্টেম খসড়া বানায়। আপনি দেখে ঠিক করে Confirm চাপলে তবেই ঢোকে। নিজে থেকে কিছু ঢোকে না।

**কোথায়:** `#/scan` (মেনু: "ছবি থেকে এন্ট্রি (Scan)")। বিস্তারিত: `docs/SCAN_SETUP.md`।

**সুইচ ও অধিকার:**

| নাম | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `scan_enabled` | Scan চালু | বন্ধ | চালু করুন, `manual` দিয়ে শুরু |
| `scan_engine` | `manual` = ছবির পাশে নিজে লেখা (কিছু সেট করতে হয় না)। `browser_ocr` = ফোনেই বিনামূল্যে পড়া (tesseract.js)। `ai_vision` = AI দিয়ে পড়া (key ও deploy লাগে) | `manual` | `manual` দিয়ে শুরু, পরে `browser_ocr` আসল বিলে পরীক্ষা, `ai_vision` সবশেষে |
| `scan_min_confidence` | এর নিচে নিশ্চিত হলে ঘর হলুদ (শুধু সতর্কতা, Confirm আটকায় না) | 0.6 | সংখ্যা প্রস্তাব নেই। 0 থেকে 1 |
| grant `scan_upload` | ছবি তুলে খসড়া বানানো | seeded: purchasing, storekeeper, showroom_manager, management | যাদের কেনা/স্টকের কাজ |
| grant `scan_confirm` | Confirm / Reject | seeded: management। মালিক সবসময় পারে | কম মানুষকে |

**চালু করলে কী বদলায়:**
- প্রতিটি লাইনের জন্য **আপনি** সিদ্ধান্ত নেন: বিদ্যমান আইটেমে মেলান / নতুন আইটেম / শুধু লেখা / বাদ। কিছু নিজে মেলানো হয় না।
- Confirm একটি লেনদেনে চলে: `save_purchase` / `quick_expense_add` / `item_new` / `item_apply` / `save_supplier`। কোনো ধাপ ব্যর্থ হলে সব ফেরত (পরীক্ষায় দেখা)।
- ক্রয় বিল ডিফল্টে **খসড়া** হয়। "বিলটি পোস্টও করুন" টিক দিলে স্টকে যায়।
- সদৃশ ধরা: একই supplier + bill no + total, বা একই জায়গা + দিন + head + অঙ্ক। স্বীকার না করলে Confirm হয় না।
- বিলের টোটাল না মিললে সতর্কতা (আটকায় না)।
- Offline হলে ছবি ফোনে জমে, নেট এলে যায়। একই ছবি দুবার গেলেও একটাই খসড়া।

**ডিফল্টে যা বদলায় না:** Scan বন্ধ। পুরনো ক্রয়, খরচ, আইটেম পথ অপরিবর্তিত।

**সাবধান:**
- ক্রয় বিলের দাম দেখেন মালিক, যিনি ছবি তুলেছেন, আর cost-দেখার অধিকারী। অন্যরা সংখ্যা পান না, Confirm-ও করতে পারেন না (`cost_hidden`)।
- Confirm-এ আগের অনুমতিও লাগে (যেমন ক্রয়ে `purchase_entry`)।
- খরচের `head` ইংরেজি ছোট কোড হতে হয় (যেমন `transport`)। বাংলা লিখলে বাদ পড়ে।
- `browser_ocr`: প্রথমবার ফোন ইন্টারনেট থেকে OCR লাইব্রেরি ও ভাষার ডেটা নামায়। **বাংলা ও হাতের লেখায় দুর্বল**। প্রতিটি ঘর মিলিয়ে নিন।
- `ai_vision`: Anthropic API key লাগে, খরচের সীমা (spending limit) বসান। key চ্যাটে বা repo-তে দেবেন না। Edge function deploy করতে কম্পিউটার লাগতে পারে (`PHONE_ONLY_STEPS.md`)। AI ভুল করে, হলুদ ঘর আপনাকেই দেখতে হবে।
- ছবিতে ব্যক্তিগত তথ্য থাকতে পারে। Bucket private। কিন্তু আপলোড হয়ে খসড়া বানানো না গেলে ছবি bucket-এ পড়ে থাকে, সাফ করার স্ক্রিপ্ট নেই।

**[যাচাই হয়নি]** আসল Supabase, আসল ফোন, `scan-extract` Edge function (কখনো deploy বা AI-তে চালানো হয়নি), OCR-এর পাঠ-মান আসল/বাংলা/হাতের লেখা বিলে, ছবি `tools/backup_photos.py` ব্যাকআপে ঢোকে কিনা।

---

## 15. বিক্রির পর Invoice (phase 92)

**এক লাইনে:** ক্যাশ সেল শেষ হলেই ইনভয়েস ফোনের পর্দায় (রসিদ-আকারে)। নিচে Print, SMS, WhatsApp, Email, Share, Copy, Download।

**কোথায়:** বিক্রির পরে নিজে থেকে। আজকের তালিকায় "View / send invoice"। যেকোনো তারিখের বিক্রি: `#/invoiceview`।

**সুইচ কোথায় বদলাবেন:** `#/switchboard` > POS অংশ > "pos_show_invoice_after_sale" (শুধু মালিক)। **সুপারিশ: `always`।** ডিফল্ট `never`, তাই এটা না বদলালে ইনভয়েস পর্দায় আসবে না, শুধু পুরনো ছোট "Print receipt" বার থাকবে। নিরাপদ ক্রম: আগে `ask`, দুই-তিন দিন পরে `always`।

**সুইচ:**

| সুইচ | অপশন ও মানে | ডিফল্ট | সিস্টেমের প্রস্তাব ও কেন |
|---|---|---|---|
| `pos_show_invoice_after_sale` | `never` = আজকের মতো কিছু বদলায় না। `ask` = সেলের পরে "Show invoice" বার। `always` = নিজে থেকে খোলে | `never` | `always`। ডিফল্ট `never` রাখা হয়েছে যাতে কিছু না করলে আগের মতো থাকে |
| `invoice_own_sales_only` (phase 94) | চালু = ইনভয়েসের ডাটা ও share-log শুধু নিজের বিক্রির। মালিক ও POS approve সব দেখেন | বন্ধ | চালু (সিস্টেমের প্রস্তাব-সারি আছে, `value` সহ) |

**চালু করলে কী বদলায়:**
- Email/SMS/WhatsApp **শুধু ডিভাইসের deep link** (`mailto:`, `sms:`, `wa.me`)। পাঠানো হয় আপনার নিজের ফোনের অ্যাপ থেকে, সেখানে Send চাপলে। সার্ভার থেকে নিজে নিজে SMS/WhatsApp যায় না (provider account ও secret লাগত, তৈরি হয়নি)।
- Offline হলে ইনভয়েস কার্ট থেকে আঁকা হয়, নম্বর `Q-xxxxxx` (সাময়িক), "Pending sync"। সার্ভারে গেলে চূড়ান্ত নম্বর আসে।
- কে কোন channel-এ পাঠাল `invoice_shares`-এ log হয় (গ্রাহকের নম্বর/ইমেইল ছাড়া, মোছা যায় না)।
- ইনভয়েসের ডাটায় কোনো cost নেই (শুধু সাদা-তালিকার key)। গ্রাহকের মোবাইল কেবল মালিক, POS approve, `view_customer_mobile` বা ওই sale-এর নিজের বিক্রেতা দেখে। অন্যরা নাম পায়, নম্বর `null`।

**ডিফল্টে যা বদলায় না:** `never` = পুরনো Print-বার অক্ষত।

**সাবধান:**
- ইনভয়েসের কোনো public লিংক নেই। বার্তায় শুধু লেখা যায়।
- Download মানে `.html` ফাইল (খুলে "Save as PDF")। সরাসরি PDF/ছবি হয় না।
- ইমেইল customers টেবিলে নেই, তাই প্রতিবার লিখতে হয়।
- Print না চললে নরম বার্তা, তখন Share বা Download ব্যবহার করুন।
- phase 92 paste না করলেও ওয়েব অংশ কার্ট-কপি দিয়ে চলে। শুধু share-log, VAT, ইংরেজি নাম আসে না।
- বাংলাদেশি `01XXXXXXXXX` নম্বরের নিয়মটাই যাচাই হয়েছে। অন্য দেশের নম্বর `+` দিয়ে।

**[যাচাই হয়নি]** আসল থার্মাল/A4 প্রিন্টার; আসল ফোনে WhatsApp/SMS/Email অ্যাপে বার্তা সত্যিই বসে কিনা; `sms:` লিংকের Android/iOS ভেদ; দীর্ঘ বার্তা কোনো অ্যাপ ছেঁটে দেয় কিনা। দ্রষ্টব্য: পরীক্ষায় phase 87 `T0` একটি পুরনো fail ছিল (phase 92 ছাড়া build-এও একই)।

---

## 16. Template - print ও message (phase 93)

**এক লাইনে:** ২০ ধরনের কাগজ/বার্তার প্রতিটির জন্য ৫-৬টা ডিজাইন থেকে আপনার পছন্দেরটা বেছে রাখা।

**কোথায়:** `#/templates` (মালিক)। জায়গা-অনুযায়ী (location) আলাদা পছন্দও দেওয়া যায়। জায়গার পছন্দ "সব জায়গা"-র পছন্দকে হারায়। পছন্দ মুছে ফেলা যায় (null)।

**মোট ধরন:** রসিদ (pos_receipt), sale_return, order_confirm, delivery_challan, purchase_bill, GRN, stock_transfer, stock_count, wastage_sheet, production_slip, recipe_card, pay_slip, partner_statement, daily_report, pnl, balance_sheet, barcode_label, price_tag, msg_invoice, msg_due।
সাইজ: Thermal 80 mm / 58 mm, A4, A5, A6, লেবেল (50x30, 38x25, 40x20, 58x40, 100x50, A4 শিট 3x8), প্রাইস ট্যাগ (45x30, 60x40, 70x35 shelf, 30x50 hanging, 50x30 sale, A4 শিট 2x6)।
বার্তার ধরন: short, medium, detailed, friendly, formal, bilingual (SMS/WhatsApp/Email)।

**সুইচ:** নেই। পছন্দ `doc_template_choice` টেবিলে (শুধু মালিক বসায়, audit হয়)।

**সিস্টেমের প্রস্তাবিত ডিজাইন (picker-এ "Suggested"):** রসিদ `thermal80_slip`, order_confirm `a5_split`, delivery_challan `a4_formal`, purchase_bill `a4_formal`, GRN `a4_classic`, stock_transfer `a4_classic`, stock_count `a4_boxed`, wastage_sheet `a4_classic`, production_slip `a5_classic`, recipe_card `a5_boxed`, pay_slip `a5_classic`, partner_statement `a4_formal`, daily_report `thermal80_slip`, pnl `a4_classic`, balance_sheet `a4_formal`, label `label_50x30`, price_tag `shelf_70x35`, msg_invoice `medium`, msg_due `friendly`। (sale_return-এ `thermal80_slip`।) কারণ আলাদা করে লেখা নেই, শুধু "suggested" চিহ্ন।

**চালু করলে কী বদলায়:** আপনি কিছু না বাছলে আজকের ছাপা অপরিবর্তিত (`BOS.tpl.render` `null` ফেরত দেয়, মানে পুরনো ছাপাই চলে)।

**সাবধান:**
- **ডিজাইনগুলো এখন চারটি জায়গায় বসানো (bos98, `tpl_registry.js` `B.tpl.ensure`):**
  - **ইনভয়েস (`invoiceview.js`):** Print আর Download বাছাই করা `pos_receipt` ডিজাইনে। SMS / WhatsApp / Email বাছাই করা `msg_invoice` লেখায়। পর্দার কার্ড সবার জন্য একই থাকে (A4 ডিজাইন 360px-এ ধরে না)।
  - **বিক্রি-ফেরত (`salereturn.js`):** ফেরত রেকর্ড হলে `sale_return` ডিজাইন বাছা থাকলে স্লিপ ছাপে; না বাছলে আগের মতো কিছু ছাপে না।
  - **পে-স্লিপ (`payroll.js`):** `pay_slip` ডিজাইন।
  - **লেবেল (`invoice.js` লেবেল ছাপা):** `barcode_label` ডিজাইন (নাম, barcode, বিক্রয়মূল্য, কপি)।
  - **বার্তা** (SMS/WhatsApp/Email) উপরের ইনভয়েসেই। একই `msg_due` ইত্যাদি অন্য বার্তা-পর্দায় বসেছে কিনা যাচাই হয়নি।
  - **ক্রয় বিল ছাপা: বসানো হয়নি** (`purchase.js`-এ ছাপার পথই নেই)। বাকি ধরন (order_confirm, delivery_challan, GRN ইত্যাদি) এখনো কোনো পর্দা ডাকে না।
  - নিয়ম: কিছু না বাছলে, `B.tpl` না থাকলে, ডিজাইন ফেরত না এলে বা কিছু ভাঙলে, **আজকের ছাপাই চলে**। পছন্দ আনা ২ সেকেন্ডের বেশি লাগলে ছেড়ে পুরনো ছাপায় যায়। গ্রাহকমুখী ডাটায় cost থাকে না।
  - **[যাচাই হয়নি]** salereturn, pay slip, label-এর হুকে বাছা ডিজাইন দিয়ে পুরো ছাপা আসল ডিভাইসে; আসল প্রিন্টার।
- Shop-এর নাম, logo, footer, tax id আসে settings key থেকে (`business_name` আছে, বাকি `shop_logo`, `invoice_footer`, `tax_id`, `shop_address`, `shop_phone` অনুমানে বসানো)। না পেলে `[Shop name]`, `[Tax ID]` ও "Thank you" বসে।
- নমুনা ডাটা (`tpl_samples.js`) বানানো। আসল ডাটা নয়।
- বাংলা লেবেলের শব্দ লেখকের। মালিক পড়ে দেখুন।

**[যাচাই হয়নি]** আসল থার্মাল প্রিন্টার, A4/A5 প্রিন্ট, লেবেল রোল, barcode স্ক্যান, ফোনে carousel ও dark mode, SMS Unicode খরচ।

---

## 17. Phase 72 এর ভিত্তি (rounding, এক cost source)

**এক লাইনে:** হিসাবের ছোট ভুল ঠিক করা, যাতে সব journal balanced থাকে, আর রিপোর্ট ও journal এক cost দেখায়।

**কী ঠিক হয়েছে:**
- **B1:** একই বিক্রিতে দুই item-type (মিষ্টি + বক্স) থাকলে rounding-এ entry unbalanced হতো, `acct_post_pending` ব্যর্থ হতো। এখন balanced (পরীক্ষায় 68.86 = 59.15 + 9.71 এর হিসাব মেলে)।
- **B2:** `biz_daily`, `_p27_pl`, l1, l2, l3, `brand_pnl` সব ledger cost পড়ে। হাতে-দেওয়া `item_costs` শুধু ledger-এ cost না থাকলে অনুমান হিসাবে (আলাদা দেখানো)।
- **B3:** ফেরতসহ margin ঠিক (ডিসকাউন্টে বিক্রি + ফেরতে revenue ও cost অনুপাতে)।
- **B4:** cost অজানা (ফাঁকা বা 0) = অজানা। রিপোর্টে "সাময়িক: খরচহীন বিক্রি"। বিক্রি তবু post হয়, journal-এ `cogs_missing` flag।
- **B5:** `inventory_vs_gl(তারিখ, জায়গা)` ledger আর খাতার পার্থক্যের কারণ দেখায় (read-only, কিছু post করে না)।
- **B6:** `acct_status` - শেষ post, pending, locked, error তালিকা। `#/accounts`-এ স্ট্রিপ।

**সুইচ:** `production_requires_cost`, `reports_net_of_returns` (অংশ 1 ও 12 দেখুন)।

**সাবধান:**
- Phase 74, 75, 78 এর পরে `_acct_docs`, `production_post`, `l1`, `l3` ফাংশন আবার লেখা হয়। phase 79 এগুলো একসঙ্গে জোড়ে। **Phase 79 অবশ্যই 72 থেকে 78 এর পরে paste করতে হবে** (`PHONE_ONLY_STEPS.md`)।
- Phase 72 এর নিজের test `phase72_test.sql T0` একটা জানা fail দেয় (bos72 লাইন এখন 7-argument core-এ, 6-argument wrapper-এ নয়)। পণ্যের সমস্যা নয়।
- বিনামূল্যের উপাদান (পানি) 0 = অজানা, তাই `refuse` মোডে ব্যাচ আটকায়। `#/s1setup`-এ চিহ্নিত করুন।

**[যাচাই হয়নি]** লাইভ ডাটাবেসের কোন phase কোন ক্রমে paste হয়েছে তা জানা নেই। phase 79 এর প্রভাব লাইভে পরীক্ষিত নয়। Biz/Reports পাতায় "খরচহীন বিক্রি" ও status strip (শুধু `#/accounts` ও `#/costunknown`-এ আছে)।

---

## 18. Paste-এর নিয়ম: 98-এর পরে নতুন phase (99, 100, 101)

**এক লাইনে:** DB-র সব phase 72 থেকে 98 আপনার লাইভ ডাটাবেসে বসে গেছে। নতুন phase ছোট করে একটা একটা আসবে, সবসময় 98-এর **পরে**।

**ক্রম যা paste হয়েছে:** 72 থেকে 88, তারপর 90, 91, **89**, 92, 93, 95, **94**, 96, 97, 98। (89 আর 94 ইচ্ছা করে ক্রমের বাইরে: 89 হলো জোড়া-ফাইল, 94 নিরাপত্তা-ধাপ। উৎস: `docs/PASTE_ORDER.md`।)

**নিয়ম (মুখস্থ রাখুন):**
1. **নতুন phase সবসময় 98-এর পরে paste হবে।**
2. **আগের কোনো phase আবার paste করবেন না।** বিশেষ করে 89, 94, 96, 97, 76, 40, `ALL_NEW10`।
3. কারণ: কিছু ফাংশন একাধিক phase আবার লেখে। পুরনো phase আবার paste করলে ফাংশনের পুরনো রূপ ফিরে আসে এবং পরের phase-এর কাজ মুছে যায়। যেমন phase 97 একা paste করলে phase 96-এর লাইন মুছে যায়; phase 89 একা paste করলে `_acct_docs` ও `inventory_vs_gl` পুরনো হয়ে যায়। দুর্ঘটনায় এমন হলে phase 98 আবার paste করলে সব ঠিক হয়ে যায় (phase 98 শুধু ওই ৫টা ফাংশন ঠিক করে, কোনো টেবিল বা ডাটা ছোঁয় না)।
4. প্রতিটি নতুন ফাইলের শুরুতে guard আছে। আগের phase না থাকলে নিজেই থামে ও কোন নম্বর নেই তা লেখে।
5. `*_test.sql` ফাইল paste করবেন না।

**যা আসছে (আলাদা ছোট paste, 98-এর পরে):**

| Phase | নাম | কী | অবস্থা |
|---|---|---|---|
| 99 | Opt | Bill payment option + inbox PII mask | **আসছে।** এখনো কোনো branch বা ফাইল নেই। এই গাইডে বিস্তারিত নেই |
| 100 | Cat | Category / Sub-category | কোড আছে `fix/phase-Cat` branch-এ, রিপোর্ট অসম্পূর্ণ (সংখ্যার ঘর খালি)। **আসছে** (অংশ 24) |
| 101 | Rec | Advisor সারি (setup advisor-এ নতুন সারি) | **আসছে।** এখনো কোনো branch বা ফাইল নেই |

প্রতিটি paste-এর পর `UAT_CHECKLIST.md`-এর ছোট পরীক্ষা চালান।

**[যাচাই হয়নি]** আপনার লাইভ ডাটাবেসে `phase98_test` বা guard-এর আসল ফল; ফোনে সত্যিই কতটা ঠিকঠাক paste হয়েছে তা আপনিই জানেন।

---

## 19. নিরাপত্তা-পরিবর্তন (phase 94): মালিক কী পরীক্ষা করবেন

**এক লাইনে:** নিরাপত্তা পর্যালোচনায় পাওয়া ফাঁক বন্ধ। সব নতুন সীমা ফাঁকা বা বন্ধ = আজকের আচরণ। **সংখ্যা সব আপনার সিদ্ধান্ত, কোডে বানানো কিছু নেই।** (উৎস: `docs/briefs_p2p3/step_Sec_REPORT.md`)

**কী ঠিক হয়েছে (কোনো কাজ লাগে না):** ছবির পথ (`image_path`) এখন শুধু যিনি আসল বিষয়বস্তু দেখার অধিকারী তিনিই পান। Meta-র ভুল সই 403। ছবি-পড়ার ডাটাবেস-ত্রুটির লেখা আর বাইরে যায় না (`save_failed`)। `anon` ব্যবহারকারীর কিছু ফাংশন চালানোর অনুমতি তোলা হয়েছে।

**আপনি এই ৫টা পরীক্ষা করুন (SQL Editor-এ মালিক হিসেবে):**

| # | কী চালাবেন | কী দেখবেন | কেন |
|---|---|---|---|
| 1 | `select pii_exposure_report94();` | guard চালু আছে কিনা, লগইন-করা ব্যবহারকারী সরাসরি ফোন/ঠিকানা কলাম পড়তে পারে কিনা, কতজনের POS view আছে | গ্রাহকের ফোন/ঠিকানা ফাঁসের ঝুঁকি। `inbox_pii_guard_on` ডিফল্ট **বন্ধ**; সিস্টেম প্রস্তাব **চালু** |
| 2 | `select anon_exec_audit94();` | তালিকা। আশা করা হয়: `login_precheck`, `login_failed`, `attendance_punch_push` ও পুরনো কিছু helper। অচেনা কিছু থাকলে সেটা কম্পিউটারওয়ালা কাউকে দেখান | রিপোর্টে 24টা পুরনো ফাংশন পাওয়া গিয়েছিল যেগুলো `anon` চালাতে পারে; আপনার লাইভে একই কিনা **যাচাই হয়নি** |
| 3 | `select intake_proof_status94();` | web_form আর meta-র proof ঠিক কী অবস্থায় | proof বসানো না থাকলে আগের মতো চলে |
| 4 | proof বসানো (ঐচ্ছিক, কম্পিউটার লাগে): মালিক হিসেবে `select intake_proof_set94('meta', '<গোপন মান>');` ও `('web_form', ...)`, আর Edge function-এ `INTAKE_PROOF_SECRET` (একই মান) | `intake_proof_status94()` এ সেট দেখায় | ভুয়া "সই ঠিক আছে" দাবি আটকায়। গোপন মান চ্যাটে বা এই গাইডে লিখবেন না |
| 5 | সীমা বসানো (ঐচ্ছিক) | নিচের সুইচ | বন্যা ও খরচ আটকাতে |

**নতুন সুইচ/সীমা (ফাঁকা বা বন্ধ ডিফল্ট):**

| নাম | মানে | ডিফল্ট | প্রস্তাব |
|---|---|---|---|
| `inbox_pii_guard_on` | গ্রাহকের ফোন/ঠিকানা শুধু অনুমতিধারী দেখেন, প্রতিটি দেখা লগে | বন্ধ | **চালু** |
| `invoice_own_sales_only` | ইনভয়েস ও share-log শুধু নিজের বিক্রির | বন্ধ | **চালু** |
| `scan_ai_max_per_job` | এক ছবিতে AI কতবার পড়বে | ফাঁকা = সীমাহীন | সংখ্যা আপনার (পর্যালোচনার ইঙ্গিত: 5)। সিস্টেম মান বসায় না |
| `scan_ai_max_per_user_day` | একজন ২৪ ঘণ্টায় কতবার | ফাঁকা | আপনার সংখ্যা |
| `offline_sale_max_age` (ঘণ্টা, 1..8760) | এর চেয়ে পুরনো তারিখের বিক্রি আর স্টক-পাহারা এড়াতে পারে না (ম্যানেজারের override পারে) | ফাঁকা | ফোন সাধারণত সর্বোচ্চ কত ঘণ্টা offline থাকে, তার সংখ্যা |
| `inbox_rate_max_per_min` | এক channel-এ মিনিটে কত বার্তা রাখা হবে। বেশি হলে retry-তালিকায় | ফাঁকা | আপনার সংখ্যা (ইঙ্গিত: 120) |
| `intake_reject_max_per_min` | ভুল সই/টোকেনের লাইন মিনিটে কত রাখা হবে | ফাঁকা | আপনার সংখ্যা |
| `partner_base_estimate` | `refuse` = অনুমানের cost ভিত্তিতে partner হিসাব সেভ হবে না | `warn` | `refuse`, তবে আগে ledger cost বসান |
| `packaging_return_mode` | `wastage` = ফেরত আসা মোড়ক কারণসহ নষ্ট | `none` | `wastage` |

আরও: `select intake_purge(<দিন>);` (মালিক) শেষ হওয়া/বাতিল intake লাইন আর পুরনো rate রেকর্ড মোছে। ব্যর্থ/dead লাইন ও audit log রাখে। দিনের সংখ্যা আপনার সিদ্ধান্ত।

**Deploy-এর ক্রম (কম্পিউটার লাগে, `PHONE_ONLY_STEPS.md` দেখুন):**
1. **আগে SQL** (phase 94, আপনার ডাটাবেসে হয়ে গেছে)।
2. **তারপর Edge code** deploy। উল্টো করলে `scan-extract` উত্তর দেবে 409, কারণ সে `scan_ai_gate94` ডাকে যা SQL-এ আগে থাকতে হয়।
3. **`TELEGRAM_SECRET_TOKEN` এখন বাধ্যতামূলক।** Telegram-এর Edge function এখন প্রতিটি অনুরোধে এটা খোঁজে; সেট না থাকলে **সব অনুরোধ 403** পায় (ঐচ্ছিক ছিল, আর নেই)। মান হবে হুবহু তাই, যা `setWebhook`-এ ও অ্যাপের "Set secret token"-এ (`telegram_secret_set`) দিয়েছেন।

**সাবধান:**
- `phase 76` আর কখনো paste করবেন না (পুরনো signature ফিরে আসে)।
- `inbound_message_receive` ও `web_order_submit` একটা বাড়তি ঐচ্ছিক argument পেয়েছে; পুরনো ডাক চলে।
- সরাসরি কলাম-পড়া ডাটাবেস লগ করতে পারে না (রিপোর্টে লেখা আছে)।

**যা বানানো হয়নি (রিপোর্ট থেকে):** print template key allow-list (L3), client_id replay-এ payload hash (L4), ছবির পথে uid (L5), payload মুছে ফেলা (L7), `online_order_get` পুরো সারি (L10), সব ফাংশনের anon-sweep, পুরনো তারিখের বিক্রিতে "অধিকার লাগবে" নিয়ম।

**[যাচাই হয়নি]** লাইভ ACL; Edge ফাংশন চালানো (শুধু TypeScript সিনট্যাক্স যাচাই); iOS-এ 16px input ও tap-size আসল ফোনে; আসল storage policy-তে ছবি।

---

## 20. ক্যাশ ড্রয়ার অপশন (phase 95)

**এক লাইনে:** ড্রয়ার এখনো কেনা হয়নি। সফটওয়্যারে একটা অপশন বসানো আছে, ড্রয়ার লাগালে শুধু সেটিং বদলালেই চলবে। ডিফল্ট বন্ধ = আজকের মতো।

**কোথায়:** `#/cashdrawer`। সেটিং বদলান শুধু মালিক। Connect device ও Test open কাউন্টারের ডিভাইসে যেকোনো POS ব্যবহারকারী পারেন।

**নিয়ম (সুইচ):**

| নাম | অপশন | ডিফল্ট | প্রস্তাব |
|---|---|---|---|
| `cash_drawer_mode` | `off` / `on_cash_sale` / `on_any_sale` / `manual_only` | `off` | ড্রয়ার লাগানোর পর `on_cash_sale` |
| `cash_drawer_when` | `before_payment` / `after_payment` | `after_payment` | `after_payment` (বিক্রি সফল হলে তবেই খোলে) |
| `cash_drawer_method` | `none` / `browser_print_pulse` / `web_serial` / `web_usb` / `bluetooth` / `kiosk_url` | `none` | USB/সিরিয়াল প্রিন্টারে `web_serial` (কম্পিউটার বা Android Chrome)। `kiosk_url` **পরিকল্পিত, বানানো হয়নি** |
| `cash_drawer_no_sale_requires_reason` | চালু/বন্ধ | চালু | চালু। বিক্রি ছাড়া খোলা মানেই চুরির ঝুঁকির সংকেত |
| grant `drawer_nosale` | বিক্রি ছাড়া ড্রয়ার খোলা | মালিকের সবসময় | কম মানুষকে |

**কী কিনবেন (রিপোর্ট থেকে):**
1. **RJ11/RJ12 পোর্টওয়ালা ক্যাশ ড্রয়ার** (12V বা 24V, প্রিন্টারের সঙ্গে মেলানো)।
2. **রসিদ প্রিন্টারে "cash drawer kick" পোর্ট** আছে এমন ESC/POS থার্মাল প্রিন্টার (80mm প্রস্তাবিত), USB বা Bluetooth। কেনার আগে বিক্রেতাকে জিজ্ঞেস করুন: "ESC/POS, cash drawer port, Android-এ Chrome দিয়ে চলে?"
3. কাউন্টারের ডিভাইস: **কম্পিউটার বা Android ফোন/ট্যাবে Chrome**।
4. এড়িয়ে চলুন: ড্রয়ার পোর্ট ছাড়া ছোট ব্লুটুথ প্রিন্টার; শুধু নিজস্ব অ্যাপ-নির্ভর (স্ট্যান্ডার্ড ESC/POS নেই) প্রিন্টার।
5. কেনার পর: প্রিন্টার USB-তে লাগান > `#/cashdrawer` > method `web_serial` > Connect device > Test open > খুললে mode `on_cash_sale`।

**iPhone/iPad-এর সীমা (গুরুত্বপূর্ণ):** iPhone বা iPad-এর কোনো ব্রাউজারে `web_serial`, `web_usb`, `bluetooth` চলে না (পেজ "not supported" দেখায়)। সেখানে শুধু `browser_print_pulse` (কম নির্ভরযোগ্য, প্রিন্টার ড্রাইভারে "print করলে drawer খোলো" চালু থাকতে হয়, ডায়ালগে ট্যাপ লাগতে পারে)। কাউন্টারের ডিভাইস iPhone হলে ড্রয়ার ঠিকঠাক নাও চলতে পারে।

**ব্যর্থ হলে কী হয়:** ড্রয়ার না থাকলে বা লেখা ব্যর্থ হলে টোস্ট "Drawer not connected", **বিক্রি আটকায় না**, `failed` ইভেন্ট লগ। অফলাইন কিউ replay-তে ড্রয়ার কখনো খোলে না।

**রিপোর্ট:** `#/cashdrawer` এ No-sale রিপোর্ট (৭/৩০/৯০ দিন): স্টাফ-ভিত্তিক সংখ্যা, দিনভিত্তিক, কারণ। এটা সংকেত, চুরির প্রমাণ নয়; কাউকে দোষ দেওয়ার আগে ক্যাশ মেলান ও কথা বলুন। ইভেন্টে টাকার অঙ্ক বা গ্রাহকের তথ্য থাকে না, মোছা যায় না।

**[যাচাই হয়নি]** আসল ড্রয়ার/প্রিন্টারে কিছুই চালানো হয়নি (নকল Serial/USB/Bluetooth API-তে bytes `27,112,0,25,250` ঠিক)। পালসের মেয়াদ ড্রয়ার-ভেদে বদলাতে হতে পারে; pin 2 বনাম pin 5 তারের উপর নির্ভর। Bluetooth প্রিন্টারের service ভিন্ন হতে পারে, তাই "experimental"। Android Chrome-এর কোন সংস্করণে Serial চলে তা যাচাই হয়নি।

---

## 21. Opening stock সাহায্যকারী ও cost-অপেক্ষা তালিকা (phase 96)

**এক লাইনে:** (D2) শুরুর স্টক খাতায় ঠিকভাবে তোলার সাহায্যকারী, যাতে একই স্টক দুবার না গোনা হয়। (D3) cost অজানা বলে যে নষ্ট/উৎপাদন/ট্রান্সফার/ফেরত খাতায় ওঠেনি, তার অপেক্ষা-তালিকা ও cost বসানোর পথ। **কিছু নিজে post বা apply হয় না।**

**কোথায়:** `#/books96` (Accounts group)। দুই ট্যাব: Opening stock, Cost waiting।

**D2 Opening stock:**
- প্রতি জায়গার সংখ্যা: opening stock-এর মূল্য, cost-ছাড়া সারি, শুরুর জের (journal) যা ধরেছে, খাতার inventory (GL), valuation, পার্থক্য। সতর্কতা: journal-এ আগেই স্টক আছে, সুইচ চালালে দুবার গোনা হবে, ইত্যাদি।
- **Preview (dry run)** আগে দেখায় কোন লাইন post হবে, কিছু লেখে না।
- ৪টি অপশন (শুধু **মালিক** apply করে):
  - `owner_capital`: Dr inventory / Cr মালিকের মূলধন (3100)।
  - `existing_account`: আপনার বলা equity বা liability account-এ।
  - `skip`: শুধু সিদ্ধান্ত, কিছু post হয় না (journal-এ আগেই আছে)।
  - `difference`: journal-এ যতটা নেই শুধু ততটা।
- **সিস্টেমের প্রস্তাব** (`opening_stock_recommend96`, সংখ্যা দেখে): `wait_for_cost` (cost বাকি), `skip` (journal পুরো ধরে), `difference` (আংশিক), `owner_capital` (journal-এ স্টক নেই), `none`। কখনো নিজে apply করে না।
- প্রতি জায়গায় একটাই সিদ্ধান্ত। এক entry (idempotent), audit হয়। সিদ্ধান্তের পর `acct_stock_opening` সুইচ আর ওই স্টক দ্বিতীয়বার post করে না।
- পরে যোগ হওয়া opening সারি সিদ্ধান্তে ঢোকে না; সেগুলো সুইচ একবার post করে।

**D3 Cost waiting:**
- তালিকা: পুরনো আগে। wastage, production-এর উপাদান, transfer, purchase return, ledger move (opening, গণনার পার্থক্য, নিজের কাজে issue)।
- Cost বসানোর পদ্ধতি: `item_average`, `last_purchase`, `recipe_standard`, `manual` (কারণ লেখা বাধ্যতামূলক)। সিস্টেম প্রস্তাব: recipe standard > item average > last purchase > manual। কিছুই জানা না থাকলে manual; **কোনো সংখ্যা বানায় না**।
- ledger বদলায় না। cost আলাদা টেবিলে যায় (মোছা যায় না), খাতা তা পড়ে। একবারই post হয়। cost-অধিকারী বা মালিক দেন (জায়গা অনুযায়ী)।
- সুইচ: `acct_cost_wait_alert_days`: দিনের সংখ্যা আপনি লিখবেন; ফাঁকা = alert নেই (কোনো ডিফল্ট সংখ্যা নেই)।

**সাবধান:**
- ভুল cost মুছে ফেলা যায় না। শুধরাতে হাতে-journal।
- অংশ-cost দিয়ে আগেই post হওয়া কাগজ তালিকায় আসে না।
- cost বসালে খাতা ঠিক হয়, কিন্তু গড় cost (valuation) এই সারির জন্য হালনাগাদ হয় না। পরীক্ষায় 54 পার্থক্য এভাবে এসেছিল এবং ব্যাখ্যাত।
- "last purchase" সব সরবরাহকারী মিলিয়ে, সরবরাহকারী-ভিত্তিক নয়।
- accountant অ্যাকাউন্টগুলো (3100, 5110 ইত্যাদি) নিশ্চিত করেননি।

**[যাচাই হয়নি]** লাইভ ডাটাবেস, ফোনে 360px চেহারা, accountant-এর নিশ্চয়তা, একসঙ্গে দুজনের cost বসানো (lock আছে, চাপ-পরীক্ষা হয়নি)।

---

## 22. Landed cost (phase 97) আর phase 98

**এক লাইনে:** মাল কিনতে বিলের দামের বাইরে যে খরচ হয় (ভাড়া, শুল্ক, বীমা, ক্লিয়ারিং, লোড-আনলোড) তা আইটেমের cost-এ যোগ করা। (উৎস: `docs/briefs_p2p3/step_Land_REPORT.md`)

**কোথায়:** `#/landed` (Purchase group) আর posted বিলের পাতায় "Landed cost যোগ" বোতাম। মালিকের সেটিং ওই পর্দাতেই। "যোগ হয়নি?" তালিকা: `#/landed/rem`।

**কখন দরকার:**
- আমদানি করা মাল (ভাড়া, শুল্ক, বীমা, clearing, bank/LC)।
- বিলের বাইরে আলাদা ভাড়া বা মাল তোলা-নামানোর খরচ, যা মালের দামের অংশ হওয়া উচিত।
- না লাগলে (সব খরচ বিলের দামেই ধরা বা খরচ খুব ছোট), `off` রাখুন। তখন item cost = বিলের দাম, কিছু বদলায় না।

**সুইচ:**

| নাম | অপশন | ডিফল্ট |
|---|---|---|
| `landed_cost_mode` | `off` / `manual` / `per_bill` / `per_shipment` | `off` |
| `landed_alloc_default` | `value` / `qty` / `weight` / `volume` / `manual` / `equal` | `value` |
| `landed_late_mode` | `split_remaining_and_cogs` / `post_to_remaining_stock` / `variance_account` | `split_remaining_and_cogs` |
| `landed_cost_requires_approval` | `warn` / `required` | `warn` |
| `landed_reminder_on` / `landed_reminder_days` | মনে করানোর তালিকা | বন্ধ |

`off` থাকলে সংরক্ষণ/post প্রত্যাখ্যাত (`landed_off`), শুধু preview চলে।

**ভাগের পদ্ধতি:** `value` (দাম অনুপাতে), `qty`, `weight`, `volume`, `manual %`, `equal`; প্রতি charge-এ আলাদা পদ্ধতি দেওয়া যায়। **ওজন/আয়তন অনুমান হয় না:** এককে kg/g/ton বা l/ml থাকলে সেখান থেকে, নইলে আইটেম/লাইনে লিখতে হয়; জানা না থাকলে পদ্ধতির পাশে "?" ও কোন আইটেম তা দেখায়।

**সিস্টেমের প্রস্তাব (পরিস্থিতি থেকে, `landed_recommendation`):**

| পরিস্থিতি | প্রস্তাবিত |
|---|---|
| আমদানি করা মাল | `per_shipment`, প্রতি charge-এ নিজের পদ্ধতি |
| ভাড়া / transport in | ওজন (সব লাইনে জানা থাকলে), নইলে দাম |
| মাল তোলা-নামানো | পরিমাণ (একক এক রকম হলে) |
| শুল্ক | দাম |
| বীমা, clearing, bank/LC | দাম (সাধারণ bank fee হলে `bank_exp` = শুধু খরচ, আইটেমে নয়) |
| lot-এর জন্য কেনা packaging | পরিমাণ |
| ফেরত-অযোগ্য কর | `vat_nonrec` (আইটেম cost-এ যায়)। ফেরতযোগ্য = `vat_recov` (যায় না)। যেটা সত্যি সেটা বাছুন |
| স্থানীয় কেনায় delivery | `manual` মোড, পরিমাণ |
| মাল আগেই বিক্রি/ব্যবহার, bill দেরিতে | ভাগ (সব বিক্রি হয়ে গেলে variance) |
| এমন কেনার return | `acct_purchase_variance` চালু। supplier ভাড়া ফেরত দিলে ঋণাত্মক charge |
| বিদেশি মুদ্রা | charge-এ মুদ্রা + rate (rate নিজে লিখতে হয়, অনুমান নয়), `fx_diff` |
| bill বনাম lot | আমদানিতে `per_shipment`; ১ বিল হলে `per_bill` |
| অনুমোদন | বড় অঙ্কে `required` (যে বানায় সে নিজে approve পারে না, মালিক পারে) |

"বড় অঙ্ক" কত, সিস্টেম সংখ্যা দেয় না, আপনি ঠিক করবেন।

**নিরাপত্তা:** cost-দেখার অধিকার (`view_cost`) + grant `landed_entry` / `landed_approve` (ডিফল্ট ভূমিকা: purchasing, management)। posted বিলে landed cost থাকলে সেই বিল void আটকায়। accounting শুরুর আগের তারিখে post হয় না। পোস্ট হলে ledger-এ `cost_adjust` জোড়া যায় (ledger বদলায় না, replay করা যায়)। Re-post = 0।

**সীমা:** একটা landed cost = এক জায়গার বিল। GRN শুধু linked বিল হয়ে আসে; GRN বাছার UI নেই (বিল বাছুন)। production-এ ব্যবহৃত অংশ finished goods-এ যায় না, variance খাতে যায়। lot-এর "কতটা বাকি" = min(on-hand, lot qty), FIFO অনুমান নয়।

**Phase 98:** শেষ ফাইল। শুধু `_acct_docs` ও আরও ৪টা ফাংশন ঠিক রাখে যাতে phase 96 আর 97-এর লাইন একসঙ্গে থাকে। কোনো টেবিল, নিয়ম, ডাটা, privilege বা trigger বদলায় না। **Phase 89, 94, 96 বা 97 কখনো আবার paste হলে phase 98-ও আবার paste করুন।** (অংশ 18)

**[যাচাই হয়নি]** আসল ফোন ও ধীর নেটে debounce preview; accountant-এর account (1240, 2150, 5150) নিশ্চয়তা; আসল আমদানি-বিলে পুরো প্রবাহ।

---

## 23. কীবোর্ড-নিরাপদ sheet ও গোটানো মেনু-footer

**কীবোর্ড-নিরাপদ sheet (bos102, `web/kbdfix.js`):** নিচ থেকে ওঠা sheet-এ লিখতে গেলে স্ক্রিন-কীবোর্ড আর Save/Confirm বোতাম ঢাকবে না। Sheet-এর বোতামের সারি নিচে আটকে থাকে (sticky), sheet-এর উচ্চতা কীবোর্ডসহ দৃশ্যমান জায়গা (visual viewport) অনুযায়ী হয়, যে ঘরে লিখছেন সেটা দৃশ্যে থাকে, সংখ্যার ঘরে Enter চাপলে প্রধান বোতাম চাপা হয়। কোনো সেটিং নেই। কোনো লেখা বা ডাটা বদলায়নি, শুধু layout।
- `visualViewport` সমর্থন না থাকলে পুরনো আকারেই থাকে, কিছু ভাঙে না।
- **[যাচাই হয়নি]** আসল iPhone Safari (পরীক্ষায় iOS-ধরনের অবস্থা শুধু নকল করা হয়েছে, কোড আসল object পড়ে, তাই সেটা শুধু "ভাঙে না" দেখে); আসল Android কীবোর্ড (Gboard-এর ভেদ)।

**গোটানো মেনু-footer (bos101, `web/nav.js`):** মেনুর নিচের অংশ (Online দাগ, ভাষা, theme, Log out) এখন **ডিফল্টে গোটানো**; শুধু ছোট বার (তীর + Online ডট) দেখা যায়। তাতে মেনু-তালিকা বেশি জায়গা পায়। তীরে ট্যাপ করলে খোলে/গোটে (ট্যাপ-এলাকা কমপক্ষে 40px)। অবস্থা ফোনে মনে থাকে (`bos_navfoot`)। Log out ও ভাষা বদলাতে আগে footer খুলুন।
- **[যাচাই হয়নি]** আসল Android Chrome; খুব পুরনো WebView-এ `inert` না থাকলে শুধু চোখে গোটানো দেখায়।

---

## 24. Category / Sub-category (phase 100, আসছে)

**অবস্থা: আসছে।** কোড আছে `fix/phase-Cat` branch-এ (এখনো আপনার ডাটাবেসে paste হয়নি)। রিপোর্ট `docs/briefs_p2p3/step_Cat_REPORT.md` (ওই branch-এ) অসম্পূর্ণ: পরীক্ষার সংখ্যার ঘরগুলো এখনো ফাঁকা। তাই নিচে যা লেখা, তা রিপোর্টের পরিকল্পনা ও ডিজাইন-অংশ থেকে, **পরীক্ষার ফল অজানা**।

**ডিজাইন:** যেখানেই আইটেম আছে (POS, ক্রয়, স্টক, recipe, scan, bulk, অনলাইন অর্ডার, কাগজের ফর্ম) সেখানে Category ও Sub-category **বেছে** নেওয়া যাবে (হাতে লেখা নয়) এবং ফিল্টার করা যাবে। পুরনো `items.category` / `sub_category` লেখা কলাম যেমন ছিল তেমন থাকে। Phase 100 কোনো পুরনো ফাংশন আবার লেখে না, তাই 98-এর পরে paste করলে কিছু মুছে যায় না।
- মাস্টার টেবিল `item_categories` (কোড ধরে রাখা, bn/en/mix নাম, merge, ক্রম)। শুরুর তথ্য আপনার আইটেমে থাকা নাম থেকে, কিছু বানানো হয়নি (রিপোর্টে দোকানের ডাটায় 5 Category, 57 আইটেম লিঙ্কড)।
- নিয়ম `category_required_on_item`: `off` (ডিফল্ট) / `warn` / `required`। সিস্টেম প্রস্তাব-সারি: `warn`। `required` হলে নতুন আইটেমে Category লাগে (Sub থাকলে Sub-ও); পুরনো আইটেম সম্পাদনা চলে।
- পর্দা: `#/categories` (যোগ, নাম বদল, merge, ক্রম, বন্ধ, আইটেম সরানো), `#/catreport` (বিক্রি বা স্টক-মূল্য Category/Sub অনুযায়ী, CSV; cost কেবল cost-অধিকারীর)।
- বানানো হয়নি (রিপোর্ট): scan-এ Sub-category, label/price tag-এ Category ছাপা, রিপোর্ট-builder-এ Sub, costboard/costing, GRN, landed.

**নিরাপত্তা-নোট:** আপনি paste করার পর `UAT_CHECKLIST.md`-এর Category সারি চালান।

---

## 25. Bill payment option ও inbox PII mask (phase 99, আসছে)

**অবস্থা: আসছে।** এই গাইড লেখার সময় repo-তে এর কোনো কোড, branch বা রিপোর্ট নেই। কী করবে তা এখানে লেখা হয়নি, কারণ অনুমান করে লেখা হবে না। ফাইল এলে অংশ আপডেট হবে। Paste-এর নিয়ম: 98-এর পরে (অংশ 18)। Inbox-এর PII-সম্পর্কিত বর্তমান সুইচ: `inbox_pii_guard_on` (অংশ 19, 4)।

---

## 26. Setup advisor-এর advisor সারি (phase 101, আসছে)

**অবস্থা: আসছে।** এই গাইড লেখার সময় repo-তে কোনো কোড, branch বা রিপোর্ট নেই; কী সারি আসবে তা এখানে লেখা হয়নি। ফাইল এলে `#/setupadvisor` ও `RECOMMENDED_SETTINGS.md` আপডেট হবে। Paste-এর নিয়ম: 98-এর পরে (অংশ 18)।

---

## শেষের কথা: কী কী এখনো মালিকের সিদ্ধান্ত

| # | সিদ্ধান্ত | কোথায় |
|---|---|---|
| 1 | Recipe approver কে | অংশ 1 |
| 2 | `recipe_approval_required` off/warn/on | অংশ 1 |
| 3 | প্রতি জায়গার খরচ-পদ্ধতি ও স্বাভাবিক মাসিক উৎপাদন | অংশ 1 |
| 4 | Utility source ও ভাগের পদ্ধতি | অংশ 2 |
| 5 | কোন খরচ কোন শোরুমের, মূল কেন্দ্র কোনটি | অংশ 3 |
| 6 | `l4`/`l5`/partner profit-এ ভাগ দেখাবে কিনা | অংশ 3 |
| 7 | Cost bill থেকে payment/payable বানানো কিনা (তৈরি হয়নি) | অংশ 2, 3 |
| 8 | কোন channel চালু। Meta আদৌ নেবেন কিনা | অংশ 4 |
| 9 | `partner_base_estimate`, `packaging_return_mode` | অংশ 4 |
| 10 | GRN `skip` না `link`। void-এ consumed GRN batch আটকাবে কিনা | অংশ 5 |
| 11 | `form_051_mode`, `transit_short_mode`, `offline_soft_stock` | অংশ 6, 7, 8 |
| 12 | `stock_balance` audit ledger-driven বদল বাদ রাখা ঠিক কিনা | অংশ 9 |
| 13 | Accounting সুইচ ও account (5110-5140, 3100) | অংশ 10 |
| 14 | Scan engine ও কে confirm করবে | অংশ 14 |
| 15 | `pos_show_invoice_after_sale` | অংশ 15 |
| 16 | `inbox_pii_guard_on`, `invoice_own_sales_only` চালু করবেন কিনা; phase 94-এর সীমার সংখ্যা (scan AI, offline বয়স, inbox rate) | অংশ 19 |
| 17 | `TELEGRAM_SECRET_TOKEN` (এখন বাধ্যতামূলক) আর proof secret বসানো (কম্পিউটারওয়ালার সঙ্গে) | অংশ 19 |
| 18 | ক্যাশ ড্রয়ার কেনা ও `cash_drawer_*` | অংশ 20 |
| 19 | Opening stock: প্রতি জায়গায় কোন অপশন (accountant-এর সঙ্গে)। `acct_cost_wait_alert_days` সংখ্যা | অংশ 21 |
| 20 | Landed cost কি লাগবে; `landed_cost_mode`, অনুমোদনের অঙ্কসীমা | অংশ 22 |
| 21 | Category: `category_required_on_item` (phase 100 এলে) | অংশ 24 |
