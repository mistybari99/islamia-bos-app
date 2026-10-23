# ফোনে মালিকের নিজের করণীয় - ধাপে ধাপে

ফোনের ব্রাউজারে Supabase ও অ্যাপ খুলে যা যা হয়, আর যা ফোনে হয় না।
এই ফাইলের কোনো ধাপ লাইভ প্রজেক্টে বা আসল ফোনে চালিয়ে দেখা হয়নি। চিহ্ন `[যাচাই হয়নি]` সেখানে দেওয়া আছে।

## ০. আগে জানুন (অবস্থা: DB-র সব phase 72 থেকে 98 paste হয়ে গেছে)

- **মালিক নিজে লাইভ ডাটাবেসে phase 72 থেকে 98 সব paste করেছেন।** তাই নিচের ১ নম্বর অংশ এখন শুধু রেকর্ড ও ভবিষ্যতের নিয়ম। নতুন কোনো ফাইল না এলে paste করার কিছু নেই।
- ক্রমের উৎস: `docs/PASTE_ORDER.md`। **ক্রম: 72 থেকে 88, তারপর 90, 91, 89, 92, 93, 95, 94, 96, 97, 98।**
- **নতুন phase সবসময় 98-এর পরে। আগের কোনো phase কখনো আবার paste করবেন না।** (কারণ: কিছু ফাংশন একাধিক phase আবার লেখে; পুরনো phase আবার paste করলে পুরনো রূপ ফিরে আসে। দুর্ঘটনা হলে phase 98 আবার paste করুন।)
- আসছে: **phase 99 (Opt: bill payment option + inbox PII mask), 100 (Cat: category/sub-category), 101 (Rec: advisor সারি)**। প্রতিটি আলাদা ছোট paste, 98-এর পরে। এই তিনটি এই গাইড লেখার সময় আপনার DB-তে নেই। 99 ও 101-এর কোনো ফাইল repo-তে এখনো নেই; 100 আছে `fix/phase-Cat` branch-এ।
- প্রতিটি phase-এর শুরুতে নিজের guard আছে। আগের phase না থাকলে নিজেই থামে, কোন নম্বর নেই লেখে।
- সব ফাইল দুবার paste করলেও ক্ষতি নেই (paste-twice safe)। তবু ওপরের নিয়ম মানুন।
- `*_test.sql` ফাইল paste করবেন না।

### ০.১ কোন phase বসেছে দেখা

1. অ্যাপে `#/setupadvisor` খুলুন। কোনো সারি `not_installed` দেখালে সেই phase বসেনি।
2. `select * from information_schema.routines where routine_name = 'landed_recommendation';` (phase 97 আছে কিনা) বা `opening_stock_check96` (phase 96) ফাংশনের নামে খুঁজে দেখা যায়। `[যাচাই হয়নি: লাইভে চালানো হয়নি]`

## ১. SQL paste - রেকর্ড (সব হয়ে গেছে)

প্রতিবার: Supabase প্রজেক্ট > **SQL Editor** > New query > ফাইলের পুরো লেখা কপি > paste > **Run** > "Success"।

`[যাচাই হয়নি]` ফোনের clipboard ও ব্রাউজারে 50 থেকে 90 KB paste ঠিকঠাক হবে কিনা, আর "Desktop site" লাগবে কিনা। না হলে কম্পিউটারওয়ালা কারও সাহায্য নিন।

| ক্রম | ফাইল | কী করে (এক লাইনে) | guard |
|---|---|---|---|
| 1-8 | `phase72` থেকে `phase79` | rounding/cost source, recipe, costing, cost-ভাগ, channel/inbox, শাখা-ভাগ, জোড়া-ফাইল | 79 সবসময় 72..78 এর পরে |
| 9-10 | `phase80`, `phase81` | free-cost/intake bot; setup advisor | 72..79 |
| 11-17 | `phase82` থেকে `phase88` | GRN/void/unit guard; form বনাম screen; audit; accounting stock move; Telegram; QA ঠিকঠাক; এক report cost source | |
| 18-19 | `phase90`, `phase91` | ছবি থেকে Scan; Show/Hide/Locked | |
| 20 | **`phase89`** | জোড়া ফাইল: ফাংশনের শেষ রূপ ঠিক করে | 72..88, 90, 91 লাগে |
| 21-22 | `phase92`, `phase93` | বিক্রির পর ইনভয়েস; Template পছন্দ | |
| 23 | `phase95` | ক্যাশ ড্রয়ার অপশন | |
| 24 | **`phase94`** | নিরাপত্তা-ধাপ | 76, 80, 81, 85, 86, 89, 90, 92, 93 লাগে |
| 25 | `phase96` | Opening stock সাহায্যকারী + cost-অপেক্ষা | 80, 85, 89 |
| 26 | `phase97` | Landed cost | 72..88, 90, 91, 89 |
| 27 | **`phase98` - শেষ** | `_acct_docs` ও ৪টি ফাংশনের শেষ রূপ | 72..97 |
| 28+ | `phase99`, `phase100`, `phase101` | **আসছে** (আলাদা, 98-এর পরে) | |

**নিয়ম:**
- ক্রম ভাঙবেন না। **আগে paste হওয়া কোনো ফাইল আবার paste করবেন না।**
- বিশেষ করে এড়ান: `phase76` (94-এর পর), `phase40`/`ALL_NEW10` (85-এর পর), `phase89`, `phase94`, `phase96`, `phase97` (এগুলো আবার paste হলে phase 98-ও আবার paste করতে হয়)।
- প্রতিটি নতুন paste-এর পর `#/setupadvisor` ও `UAT_CHECKLIST.md`।

## ২. ফোনে সম্ভব - অ্যাপের ভেতরের কাজ

| কাজ | কোথায় |
|---|---|
| সুইচ চালু/বন্ধ | `#/switchboard` |
| প্রস্তাবিত মান apply | `#/setupadvisor`, `#/guards` |
| ব্যক্তি/ভূমিকা অনুযায়ী Show/Hide/Locked | `#/optviews` |
| অধিকার (grant) দেওয়া। Approver role | `#/delegation` |
| Recipe, কারিগর, রূপান্তর rate, pool | `#/recipebook`, `#/costing` |
| Cost source, নিয়ম, বিল | `#/costsources` |
| খরচ কোন শাখার | `#/costattrib` |
| Sales channel যোগ | `#/saleschannels` |
| Telegram channel যোগ, secret token বসানো | `#/inbox` > Channels |
| Free-cost চিহ্ন, intake bot বানানো | `#/s1setup` |
| Template পছন্দ | `#/templates` |
| Scan চালু, grant (`scan_upload`, `scan_confirm`) | `#/switchboard`, `#/delegation` |
| `pos_show_invoice_after_sale` (সুপারিশ `always`) | `#/switchboard` |
| ক্যাশ ড্রয়ার mode/method, Connect, Test open (ড্রয়ার কেনার পর) | `#/cashdrawer` |
| Card settlement, scheduler চালু/বন্ধ (pg_cron থাকলে), books সুইচ | `#/books85` |
| Opening stock সিদ্ধান্ত, cost-অপেক্ষা তালিকা | `#/books96` |
| Landed cost বানানো/approve/post | `#/landed` |
| Category / Sub-category (phase 100 এলে) | `#/categories`, `#/catreport` |
| Phase 94 পরীক্ষা: `pii_exposure_report94()`, `anon_exec_audit94()`, `intake_proof_status94()` | Supabase SQL Editor (ফোনে সম্ভব) |

## ৩. কিছু ধাপ ফোনে সম্ভব, কিন্তু বাইরের অ্যাকাউন্টে

| ধাপ | কোথায় | অবস্থা |
|---|---|---|
| Telegram bot বানানো (BotFather) | Telegram অ্যাপ | ফোনে সম্ভব। Bot token একটা password। চ্যাটে, repo-তে, স্ক্রিনশটে দেবেন না। ফাঁস হলে BotFather-এ `/revoke` |
| Telegram secret token ঠিক করা | আপনি নিজে | ১৬ থেকে ২৫৫ অক্ষর, শুধু অক্ষর, সংখ্যা, `_`, `-`। Password manager দিয়ে বানান। অ্যাপে "Set secret token" দিয়ে বসান। সার্ভারে শুধু hash থাকে |
| Telegram `setWebhook` | ব্রাউজারে লিংক খোলা | ফোনে সম্ভব, কিন্তু আগে Edge function deploy হতে হবে (নিচে, কম্পিউটার লাগে)। লিংকে bot token থাকে, ব্রাউজার history মুছে দিন |
| ওয়েব ফর্মের public URL সেটিং বসানো | `#/switchboard` (`web_form_public_url`) | ফোনে সম্ভব, কিন্তু URL আগে লাগে। URL পাওয়া যায় Edge function deploy-এর পর |
| `ai_vision` এর key বসানো | Supabase Dashboard > Edge Functions > Secrets | `[যাচাই হয়নি]` ফোনের ব্রাউজারে হবে কিনা |
| Anthropic অ্যাকাউন্ট ও খরচের সীমা (spending limit) | Anthropic Console | ফোনে সম্ভব। সীমা অবশ্যই বসান |
| Meta Developer অ্যাপ, Business Verification, App Review, Page/Instagram/WhatsApp সংযোগ, webhook URL নিবন্ধন | Meta-র সাইট | **বাইরের অ্যাকাউন্ট ও অনুমোদন।** কী কী লাগে, বাংলাদেশে প্রাপ্যতা ও খরচ: কিছুই যাচাই হয়নি। আগে নিজে দেখে নিন |
| Captcha পরিষেবার অ্যাকাউন্ট (ঐচ্ছিক) | প্রদানকারীর সাইট | বাইরের সেটআপ |

## ৪. ফোনে অসম্ভব (কম্পিউটার বা কম্পিউটারওয়ালা সাহায্যকারী লাগবে)

নিচের প্রতিটা ফোনে হয় না বলে ধরে নিন। কারণ আলাদা করে লেখা আছে।

| # | ধাপ | কেন ফোনে হয় না | কোন ফিচারের জন্য |
|---|---|---|---|
| 1 | **Edge function deploy** (`supabase functions deploy web-order --no-verify-jwt`) | Supabase CLI লাগে। Meta/Telegram/ওয়েব ফর্ম Supabase login token পাঠাতে পারে না, তাই `--no-verify-jwt` লাগে | ওয়েব অর্ডার ফর্ম |
| 2 | **Edge function deploy** (`meta-webhook --no-verify-jwt`) | একই কারণ | Facebook/Instagram/WhatsApp |
| 3 | **Edge function deploy** (`telegram-webhook --no-verify-jwt`) | একই কারণ | Telegram |
| 4 | **Edge function deploy** (`scan-extract`), JWT যাচাই চালু রেখে (`--no-verify-jwt` দেবেন না) | CLI লাগে। Dashboard editor ফোনে হতে পারে (Desktop site) `[যাচাই হয়নি]` | Scan `ai_vision` (ঐচ্ছিক। `manual` ও `browser_ocr`-এ লাগে না) |
| 5 | **Secrets সেট** (নিচে নামের তালিকা) | CLI (`supabase secrets set`) সবচেয়ে নিশ্চিত। Dashboard থেকে ফোনে হয় কিনা `[যাচাই হয়নি]` | সংশ্লিষ্ট Edge function |
| 6 | **Intake bot-এর login ব্যবহারকারী বানানো** (Supabase Auth) | Supabase Auth-এ নতুন ব্যবহারকারী বানাতে dashboard লাগে। ফোনে হতে পারে `[যাচাই হয়নি]`। রিপোর্টে এটাকে "ফোনে সম্ভব নয়" ধরা হয়েছে। এরপর `#/s1setup` (`intake_bot_create`) দিয়ে চিহ্নিত করা ফোনে হয় | ওয়েব ফর্ম, Meta, Telegram |
| 7 | **Scheduler চালু করা** (`acct_scheduler_enable`) | Postgres-এর `pg_cron` extension থাকতে হবে। সেটা সার্ভারের সেটিং। কোড কিছু install করে না। extension না থাকলে কিছু schedule হয় না | নিজে নিজে হিসাব post |
| 8 | **`intake_retry_due` নিয়মিত চালানো** | কেউ cron লেখেনি (GitHub Actions বা Supabase scheduled function)। এই cron-ও বানানো হয়নি | ব্যর্থ intake আবার চেষ্টা |
| 9 | **Meta Developer অ্যাপের webhook-callback নিবন্ধন** | Meta-র ওয়েবসাইট। ফোনে ব্রাউজারে সম্ভব হতে পারে, কিন্তু Edge function আগে deploy না হলে URL নেই | Meta |
| 10 | **ছবির (Scan) পুরনো orphan সাফ করা** | স্ক্রিপ্ট বানানো হয়নি | Scan |
| 11 | **আসল প্রিন্টারে পরীক্ষা** (থার্মাল 58/80 mm, A4/A5, লেবেল রোল) | প্রিন্টার ও ফোন জোড়া লাগাতে হয়। কখনো পরীক্ষা হয়নি | Template, ইনভয়েস |
| 12 | **আসল ক্যাশ ড্রয়ারে পরীক্ষা** (RJ11 ড্রয়ার + kick-পোর্টওয়ালা ESC/POS প্রিন্টার) | হার্ডওয়্যার কিনতে ও লাগাতে হয়। কখনো পরীক্ষা হয়নি। **iPhone/iPad-এ web_serial/web_usb/bluetooth চলে না** | ক্যাশ ড্রয়ার |
| 13 | **Scan-এর ছবি পড়া (`ai_vision`) ও Telegram**: Edge function deploy + secrets | কম্পিউটার লাগে (ওপরের 3, 4, 5 নম্বর)। `manual` মোডে Scan কম্পিউটার ছাড়াই চলে | Scan, Telegram |

### Phase 94 (নিরাপত্তা) এর deploy-ক্রম

1. **আগে SQL** (phase 94, আপনার DB-তে হয়ে গেছে)।
2. **তারপর Edge code** deploy। উল্টো হলে `scan-extract` উত্তর দেয় 409।
3. `TELEGRAM_SECRET_TOKEN` সেট করুন (ওপরে)। নইলে Telegram থেমে যায়।
4. SQL Editor-এ (ফোনে সম্ভব) মালিক হিসেবে চালান: `select pii_exposure_report94();`, `select anon_exec_audit94();`, `select intake_proof_status94();`। অচেনা সারি কম্পিউটারওয়ালাকে দেখান। বিস্তারিত: `OWNER_GUIDE.md` অংশ 19।
5. `INTAKE_BOT_PASSWORD` সন্দেহ হলেই বদলান।

### Secrets-এর নাম (মান কখনো এখানে বা চ্যাটে লিখবেন না)

| Secret নাম | কোন function-এ |
|---|---|
| `INTAKE_BOT_EMAIL`, `INTAKE_BOT_PASSWORD` | web-order, meta-webhook, telegram-webhook |
| `WEB_FORM_SALT` | web-order |
| `CAPTCHA_SECRET`, `CAPTCHA_VERIFY_URL` | web-order (ঐচ্ছিক) |
| `META_APP_SECRET`, `META_VERIFY_TOKEN` | meta-webhook |
| `TELEGRAM_SECRET_TOKEN` | telegram-webhook (**phase 94-এর পর বাধ্যতামূলক**; সেট না থাকলে সব অনুরোধ 403। মান হুবহু `setWebhook` ও অ্যাপের `telegram_secret_set`-এর সঙ্গে এক) |
| `INTAKE_PROOF_SECRET` | meta-webhook, web-order (ঐচ্ছিক; পরে মালিক `intake_proof_set94(...)` দিয়ে একই মান বসান) |
| `ANTHROPIC_API_KEY`, `SCAN_AI_MODEL` | scan-extract (শুধু `ai_vision`) |

কোড থেকে নাম মিলিয়ে দেখা: ওপরের নামগুলো `tools/edge/*.ts` ও `supabase/functions/*/index.ts` এ আছে। `ASSISTANT_MODEL` নামে আরও একটা আছে `assistant-proxy.ts`-এ, এই গাইডের বাইরে।
`SUPABASE_URL` ও `SUPABASE_ANON_KEY` Supabase নিজে দেয়।

কখনো যা করবেন না:
- `service_role` key কোথাও বসাবেন না। কোনো ফাংশনের তা লাগে না।
- Secret repo-তে, চ্যাটে, ছবিতে, SQL-এ দেবেন না।
- Telegram `setWebhook` লিংক ব্রাউজারে খোলার পর history মুছুন।

## ৫. প্রতিটি কম্পিউটার-লাগা ধাপে কারও কাছে কী চাইবেন

কম্পিউটারওয়ালা সাহায্যকারীকে বলুন: "ডিরেক্টরি `supabase/functions/` ও `tools/edge/` থেকে উপরের তালিকার function deploy করুন। secret আমি নিজে Supabase dashboard-এ বসাব (অথবা আপনার সামনে বসে বসাব)। আমার কোনো password বা key আপনাকে পাঠাব না।"

## ৬. যা এই গাইডে যাচাই হয়নি

- লাইভ ডাটাবেসে কোন phase আগে paste হয়েছে।
- ফোনে বড় SQL ফাইল paste করা।
- Supabase dashboard ফোনের ব্রাউজারে Edge function / Secrets / Auth user বানানো।
- Phase 94-এর Edge কোড কখনো চালানো হয়নি (শুধু TypeScript সিনট্যাক্স যাচাই), ড্রয়ার/প্রিন্টার হার্ডওয়্যার, আপনার লাইভে anon-অনুমতির আসল তালিকা।
- Meta ও Telegram-এর বর্তমান নিয়ম। রিপোর্টের সব লিংক ও ক্ষেত্রের নাম স্মৃতি থেকে লেখা।
