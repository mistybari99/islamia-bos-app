-- ============================================================================
-- FRESH part 7 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase507 phase508 phase509 phase510 phase511 phase512 phase513 phase514 phase516 phase517
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase507.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase81.sql there and is already pasted on the live database under that name.
-- Renumbered to phase507.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 507 (bos81) - Step S2: RECOMMENDATIONS + ACTIVATION GUIDE ("চালু করার গাইড"). Run AFTER phase79 (phase506 is NOT needed).
-- Additive + idempotent (paste twice = no error). Strictly ADVISORY: nothing here blocks, changes or re-routes any sale, purchase, production,
-- journal or order. The only write path is the owner's own tap on "recommended apply".
--   1. setup_recommendations()      every rule / switch added in phases 72..79 (+ the base switches the guide needs) with the recommended value,
--                                   the reason (bn / mix / en), the current value and a status:
--                                     ok (already the recommended value) | recommended (not yet; one tap) | owner_chosen (the owner set another value: left alone)
--                                     | info (no value is recommended: the owner types it, or it needs an outside setup) | not_installed (rule row missing)
--                                   DATA-DRIVEN: rows live in setup_rec_defs81 (seeded additively with ON CONFLICT DO NOTHING). Later phases (e.g. phase506) add their
--                                   rules by plain INSERT into that table; a row whose rule does not exist yet is simply shown as not_installed.
--   2. setup_recommend_apply()      owner only. Applies the recommended value of the chosen codes (or all) through set_rule. NEVER overwrites a value the
--                                   owner already chose unless p_overwrite=true AND the code is named in p_codes. Rows whose readiness checks are not clean are
--                                   skipped (reason not_ready) unless p_ignore_ready=true. Idempotent by client id. Append-only trail + audit_log.
--   3. setup_readiness([topic])     "before you switch it on": checks per topic (stock tracking, accounting, production, cost sources, online orders).
--                                   Counts only - never an amount or a cost value (cost secrecy). Result is advice; the switch itself is never blocked.
--   4. setup_flow_check()           after a system is on: "does the data flow where it should?" (documents waiting to be posted, posting errors, negative stock,
--                                   productions with unknown cost, unseen messages, failed intakes, open order flags ...). Systems that are off show 'na'.
--   5. setup_apply_history()        the owner's own trail of what was applied.
-- No rule default, rate, limit or amount is changed or invented here. Numbers (rate limits, hours, tries) are shown as "keep the shipped default or type your own":
-- the recommendation for a number is always "info".
-- ============================================================

do $$ begin
  if to_regclass('public.sales_channels') is null or to_regclass('public.location_cost_attribution') is null or to_regclass('public.recipe_versions') is null
     or to_regclass('public.online_order_flags') is null then
    raise exception 'phase507 needs phases 72..79 pasted first';
  end if;
end $$;

-- ---------- tables ----------
-- the recommendation list (one row per rule); texts in 3 modes
create table if not exists public.setup_rec_defs81 (
  code text primary key,
  rule_key text not null,                     -- the row in public.rules this is about
  phase text not null,                        -- the phase that added the rule ('72'..'79', 'base' = older switch the guide needs)
  module text not null default 'general',
  rec_value jsonb,                            -- the recommended value; null = no value recommended (info only)
  ready_checks text[] not null default '{}',  -- check codes that should show 0 problems before the one-tap apply
  reason_bn text not null, reason_mix text, reason_en text not null,
  sort int not null default 0,
  active boolean not null default true
);
-- the readiness / flow checks (texts only; the counting lives in _setup_chk81)
create table if not exists public.setup_check_defs81 (
  code text primary key,
  topic text not null,
  kind text not null default 'ready' check (kind in ('ready', 'flow')),
  gate_rule text,                             -- flow checks apply only while this switch is on (null = always)
  level text not null default 'warn' check (level in ('warn', 'info')),
  label_bn text not null, label_mix text, label_en text not null,
  fix_bn text, fix_mix text, fix_en text,
  nav text,                                   -- web screen key that fixes it (optional)
  sort int not null default 0,
  active boolean not null default true
);
create table if not exists public.setup_topic_defs81 (
  topic text primary key,
  gate_rule text,                             -- the switch this topic prepares (null = no single switch)
  label_bn text not null, label_mix text, label_en text not null,
  sort int not null default 0
);
-- what the owner applied (append-only)
create table if not exists public.setup_apply_batches81 (
  client_id uuid primary key,
  applied_by uuid not null, applied_at timestamptz not null default now(),
  overwrite boolean not null default false, ignore_ready boolean not null default false,
  result jsonb not null
);
create table if not exists public.setup_apply_lines81 (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.setup_apply_batches81(client_id),
  code text not null, rule_key text not null,
  old_value jsonb,                            -- null = the rule had no own value (was on its default)
  new_value jsonb not null,
  overwrote boolean not null default false,   -- true only when the owner asked to replace a value he had chosen
  created_at timestamptz not null default now()
);
create or replace function public._setup_ro81() returns trigger language plpgsql as $$
begin raise exception 'append_only: the setup trail is never changed or deleted'; end $$;
drop trigger if exists setup_batches_ro81 on public.setup_apply_batches81;
create trigger setup_batches_ro81 before update or delete on public.setup_apply_batches81 for each row execute function public._setup_ro81();
drop trigger if exists setup_lines_ro81 on public.setup_apply_lines81;
create trigger setup_lines_ro81 before update or delete on public.setup_apply_lines81 for each row execute function public._setup_ro81();
drop trigger if exists audit_setup_batches81 on public.setup_apply_batches81;
create trigger audit_setup_batches81 after insert on public.setup_apply_batches81 for each row execute function public.log_change('client_id');

-- ---------- seed: topics ----------
insert into public.setup_topic_defs81 (topic, gate_rule, label_bn, label_mix, label_en, sort) values
 ('stock_tracking', null, 'স্টক ট্র্যাকিং চালু করার আগে', 'Stock tracking চালু করার আগে', 'Before you start stock tracking', 10),
 ('accounting', 'accounting_on', 'হিসাব (অ্যাকাউন্টিং) চালু করার আগে', 'Accounting চালু করার আগে', 'Before you switch accounting on', 20),
 ('production', null, 'উৎপাদন (production) শুরুর আগে', 'Production শুরুর আগে', 'Before you start production', 30),
 ('cost_sources', 'cost_attrib_in_pl', 'খরচের বিল ভাগ করার আগে', 'Cost bill ভাগ করার আগে', 'Before you split cost bills', 40),
 ('online', 'online_orders_on', 'অনলাইন অর্ডার ও মেসেজ চালুর আগে', 'Online order ও message চালুর আগে', 'Before you start online orders and messages', 50)
 on conflict (topic) do nothing;

-- ---------- seed: checks ----------
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort) values
 ('stk_tracked', 'stock_tracking', 'ready', null, 'warn', 'কোনো আইটেম "ট্র্যাক" করা নেই', 'কোনো item "tracked" করা নেই', 'No item is marked as tracked', 'যে আইটেমের স্টক গুনতে চান সেগুলো ট্র্যাক করুন', 'যে item এর stock গুনতে চান সেগুলো track করুন', 'Mark the items whose stock you want to count', 'items', 10),
 ('stk_unit', 'stock_tracking', 'ready', null, 'warn', 'ট্র্যাক করা আইটেমে বেস ইউনিট নেই', 'Tracked item এ base unit নেই', 'Tracked items without a base unit', 'প্রতিটি আইটেমের বেস ইউনিট বসান', 'প্রতিটি item এর base unit বসান', 'Set the base unit of each item', 'items', 11),
 ('stk_opening', 'stock_tracking', 'ready', null, 'warn', 'ট্র্যাক করা আইটেমের শুরুর স্টক (opening) তোলা হয়নি', 'Tracked item এর opening stock তোলা হয়নি', 'Tracked items with no opening stock entered', 'গুনে প্রতিটি জায়গার শুরুর স্টক তুলুন', 'গুনে প্রতিটি জায়গার opening stock তুলুন', 'Count and enter the opening stock of each place', 'stock', 12),
 ('stk_conv', 'stock_tracking', 'ready', null, 'warn', 'বিক্রির ইউনিটের রূপান্তর (conversion) নেই', 'Sell unit এর conversion নেই', 'Sell units with no unit conversion', 'কেজি/গ্রাম/পিস ইত্যাদির রূপান্তর বসান', 'কেজি/গ্রাম/পিস এর conversion বসান', 'Add the conversion between selling and base units', 'items', 13),
 ('stk_cost', 'stock_tracking', 'ready', null, 'warn', 'স্টক আছে কিন্তু খরচ জানা নেই (ফাঁকা বা ০ = অজানা)', 'Stock আছে কিন্তু cost জানা নেই (blank বা 0 = অজানা)', 'Items in stock whose cost is unknown (blank or 0 = unknown)', 'কেনা বা শুরুর দাম বসান; সত্যিই বিনা খরচ হলে আলাদা করে চিহ্নিত করুন', 'কেনা বা opening দাম বসান; সত্যিই free হলে আলাদা mark করুন', 'Enter the purchase or opening cost; mark a truly free item separately', 'costsources', 14),
 ('stk_neg', 'stock_tracking', 'ready', null, 'warn', 'মাইনাস স্টক আছে', 'Minus stock আছে', 'Negative stock balances exist', 'কেন মাইনাস হলো দেখে গুনে ঠিক করুন', 'কেন minus হলো দেখে count করে ঠিক করুন', 'Find out why and fix with a count', 'stock', 15),
 ('acc_start', 'accounting', 'ready', null, 'warn', 'হিসাব শুরুর তারিখ বসানো নেই', 'Accounting start date বসানো নেই', 'No accounting start date', 'শুরুর তারিখ বসান', 'Start date বসান', 'Set the start date', 'accounts', 20),
 ('acc_coa', 'accounting', 'ready', null, 'warn', 'অ্যাকাউন্টের তালিকা (chart) ফাঁকা', 'Chart of accounts ফাঁকা', 'The chart of accounts is empty', 'অ্যাকাউন্টের তালিকা তৈরি করুন', 'Chart of accounts তৈরি করুন', 'Create the chart of accounts', 'accounts', 21),
 ('acc_map', 'accounting', 'ready', null, 'warn', 'দরকারি অ্যাকাউন্ট ম্যাপিং নেই বা বন্ধ অ্যাকাউন্টে', 'দরকারি account mapping নেই বা বন্ধ account এ', 'Required account mappings missing or pointing to an inactive account', 'ম্যাপিং ঠিক করুন', 'Mapping ঠিক করুন', 'Fix the mappings', 'accounts', 22),
 ('acc_opening', 'accounting', 'ready', null, 'warn', 'শুরুর ব্যালান্স (opening entry) নেই', 'Opening balance entry নেই', 'No opening balance entry', 'শুরুর জের এন্ট্রি দিন', 'Opening balance entry দিন', 'Post the opening balances', 'accounts', 23),
 ('acc_wait', 'accounting', 'ready', null, 'info', 'কিছু কাগজ খরচ অজানা বলে অপেক্ষায় আছে', 'কিছু document cost অজানা বলে অপেক্ষায় আছে', 'Documents waiting because a cost is unknown', 'খরচ বসালে এগুলো নিজে থেকে ঢুকবে', 'Cost বসালে এগুলো নিজে থেকে ঢুকবে', 'They post by themselves once the cost is entered', 'accounts', 24),
 ('acc_err', 'accounting', 'ready', null, 'warn', 'অটো-পোস্টে ভুল জমে আছে', 'Autopost এ error জমে আছে', 'Auto-posting errors are waiting', 'ভুলের তালিকা দেখে ঠিক করুন', 'Error list দেখে ঠিক করুন', 'Open the error list and fix', 'accounts', 25),
 ('prd_recipes', 'production', 'ready', null, 'warn', 'কোনো চালু রেসিপি নেই', 'কোনো active recipe নেই', 'No active recipe', 'রেসিপি লিখুন', 'Recipe লিখুন', 'Write the recipes', 'recipes', 30),
 ('prd_lines', 'production', 'ready', null, 'warn', 'উপাদান ছাড়া রেসিপি', 'Ingredient ছাড়া recipe', 'Recipes with no ingredient line', 'উপাদান যোগ করুন', 'Ingredient যোগ করুন', 'Add the ingredients', 'recipes', 31),
 ('prd_yield', 'production', 'ready', null, 'warn', 'রেসিপির ফলন (yield) নেই', 'Recipe এর yield নেই', 'Recipes with no yield', 'এক ব্যাচে কত হয় বসান', 'এক batch এ কত হয় বসান', 'Enter what one batch makes', 'recipes', 32),
 ('prd_approve', 'production', 'ready', null, 'info', 'অনুমোদন (approve) হয়নি এমন রেসিপি', 'Approve হয়নি এমন recipe', 'Recipes not approved yet', 'মালিক নিজে বা অনুমতি পাওয়া কেউ অনুমোদন দিন', 'Owner নিজে বা অনুমতি পাওয়া কেউ approve করুন', 'The owner or a person granted the right approves', 'recipebook', 33),
 ('prd_icost', 'production', 'ready', null, 'warn', 'উপাদানের খরচ অজানা (ফাঁকা বা ০)', 'Ingredient এর cost অজানা (blank বা 0)', 'Ingredients whose cost is unknown (blank or 0)', 'কেনা দাম বা শুরুর দাম বসান', 'কেনা দাম বা opening দাম বসান', 'Enter the purchase or opening cost', 'costing', 34),
 ('prd_unit', 'production', 'ready', null, 'warn', 'রেসিপির ইউনিটের রূপান্তর নেই', 'Recipe unit এর conversion নেই', 'Recipe lines whose unit has no conversion', 'রূপান্তর বসান', 'Conversion বসান', 'Add the conversion', 'items', 35),
 ('prd_conv', 'production', 'ready', null, 'warn', 'কারখানার খরচের পদ্ধতি অসম্পূর্ণ (pool-এ স্বাভাবিক মাসিক উৎপাদন নেই / recipe-এ খরচের ধরন নেই)', 'Factory cost method অসম্পূর্ণ (pool এ normal monthly output নেই / recipe এ cost component নেই)', 'Factory cost method incomplete (pool without normal monthly output / recipe mode without cost components)', 'অসম্পূর্ণ জায়গার তথ্য বসান', 'অসম্পূর্ণ জায়গার তথ্য বসান', 'Complete the missing figures for that place', 'costing', 36),
 ('cs_sources', 'cost_sources', 'ready', null, 'info', 'কোনো খরচের উৎস (বিল) বসানো নেই', 'কোনো cost source (bill) বসানো নেই', 'No cost source entered', 'বিদ্যুৎ, ভাড়া ইত্যাদির উৎস যোগ করুন', 'Electricity, rent ইত্যাদির source যোগ করুন', 'Add the sources such as electricity and rent', 'costsources', 40),
 ('cs_rule', 'cost_sources', 'ready', null, 'warn', 'অনুমোদিত ভাগের নিয়ম নেই এমন উৎস', 'Approved allocation rule নেই এমন source', 'Active sources with no approved allocation rule', 'ভাগের নিয়ম লিখে অন্য একজনকে দিয়ে অনুমোদন করান', 'Rule লিখে অন্য একজনকে দিয়ে approve করান', 'Write the rule and let another person approve it', 'costsources', 41),
 ('cs_attrib', 'cost_sources', 'ready', null, 'info', 'কোন খরচ কোন শোরুমের তা এখনো ঠিক করা নেই', 'কোন cost কোন showroom এর তা এখনো ঠিক করা নেই', 'No cost-to-showroom assignment yet', 'জায়গাভিত্তিক বরাদ্দ বসান', 'Place অনুযায়ী assignment বসান', 'Set the assignment per place', 'costattrib', 42),
 ('onl_channels', 'online', 'ready', null, 'warn', 'কোনো চালু বিক্রির চ্যানেল নেই', 'কোনো active sales channel নেই', 'No active sales channel', 'ওয়েব ফর্ম, ফোন, কাউন্টার চ্যানেল যোগ করুন', 'Web form, phone, walk-in channel যোগ করুন', 'Add the web form, phone and walk-in channels', 'inbox', 50),
 ('onl_url', 'online', 'ready', null, 'info', 'ওয়েব ফর্ম চালু কিন্তু পাবলিক ঠিকানা (URL) বসানো নেই', 'Web form on কিন্তু public URL বসানো নেই', 'Web form is on but the public URL is empty', 'ঠিকানা বসান (বাইরের সেটআপ লাগে)', 'URL বসান (বাইরের setup লাগে)', 'Enter the URL (needs an outside setup)', 'inbox', 51),
 ('onl_bot', 'online', 'ready', null, 'info', 'মেসেজ ইনটেক চালু কিন্তু কোনো চালু ইনটেক ইউজার নেই', 'Message intake on কিন্তু active intake user নেই', 'Message intake is on but no active intake user', 'ফোনে করা যায় না — আলাদা সেটআপ', 'Phone থেকে করা যায় না — আলাদা setup', 'Cannot be done from the phone - separate setup', null, 52),
 ('flw_acc_old', 'accounting', 'flow', 'accounting_on', 'warn', 'আগের দিনের কাগজ এখনো হিসাবে ঢোকেনি', 'আগের দিনের document এখনো books এ ঢোকেনি', 'Documents from earlier days are not in the books yet', 'অটো-পোস্ট চালু আছে কিনা দেখুন; না হলে পেন্ডিং পোস্ট করুন', 'Autopost on আছে কিনা দেখুন; না হলে pending post করুন', 'Check autopost is on; otherwise post the pending list', 'accounts', 60),
 ('flw_acc_err', 'accounting', 'flow', 'accounting_on', 'warn', 'অটো-পোস্টে ভুল জমে আছে', 'Autopost এ error জমে আছে', 'Auto-posting errors are waiting', 'ভুলের তালিকা দেখুন', 'Error list দেখুন', 'Open the error list', 'accounts', 61),
 ('flw_acc_wait', 'accounting', 'flow', 'accounting_on', 'info', 'খরচ অজানা বলে কাগজ অপেক্ষায়', 'Cost অজানা বলে document অপেক্ষায়', 'Documents waiting for a cost', 'খরচ বসালে ঢুকবে', 'Cost বসালে ঢুকবে', 'They post once the cost is entered', 'accounts', 62),
 ('flw_neg', 'stock_tracking', 'flow', null, 'warn', 'মাইনাস স্টক আছে', 'Minus stock আছে', 'Negative stock balances exist', 'কারণ খুঁজে গুনে ঠিক করুন', 'কারণ খুঁজে count করে ঠিক করুন', 'Find the reason and fix with a count', 'stock', 63),
 ('flw_prod_cost', 'production', 'flow', null, 'warn', 'খরচ অসম্পূর্ণ রেখে হওয়া উৎপাদন', 'Cost অসম্পূর্ণ রেখে হওয়া production', 'Productions made with an incomplete cost', 'অজানা খরচ বসান', 'অজানা cost বসান', 'Enter the unknown costs', 'costing', 64),
 ('flw_inbox_new', 'online', 'flow', 'inbox_on', 'warn', 'আগের দিনের মেসেজ এখনো দেখা হয়নি', 'আগের দিনের message এখনো দেখা হয়নি', 'Messages from earlier days not seen yet', 'ইনবক্স খুলে দেখুন', 'Inbox খুলে দেখুন', 'Open the inbox', 'inbox', 65),
 ('flw_inbox_silent', 'online', 'flow', 'inbox_on', 'warn', 'নির্ধারিত সময়ের বেশি কোনো মেসেজ আসেনি (সংযোগ ঠিক আছে তো?)', 'নির্ধারিত সময়ের বেশি কোনো message আসেনি (connection ঠিক আছে তো?)', 'No message for longer than the set silence hours (is the connection fine?)', 'সংযোগ পরীক্ষা করুন', 'Connection check করুন', 'Check the connection', 'inbox', 66),
 ('flw_intake_fail', 'online', 'flow', 'inbox_on', 'warn', 'ইনটেক ব্যর্থ হয়ে আছে', 'Intake fail হয়ে আছে', 'Failed intakes are waiting', 'ব্যর্থ তালিকা দেখুন', 'Failed list দেখুন', 'Open the failed list', 'inbox', 67),
 ('flw_oo_flags', 'online', 'flow', 'online_orders_on', 'warn', 'অনলাইন অর্ডারের খোলা ফ্ল্যাগ (বাতিল বিক্রি) আছে', 'Online order এর open flag (voided sale) আছে', 'Open online-order flags (voided sale)', 'ফ্ল্যাগ দেখে রিভিউ করুন', 'Flag দেখে review করুন', 'Review the flags', 'onlineorders', 68),
 ('flw_pool', 'production', 'flow', null, 'warn', 'pool পদ্ধতির জায়গায় এই মাসের খরচ বসানো নেই', 'Pool method এর জায়গায় এই মাসের cost বসানো নেই', 'Pool-method places with no pool figures this month', 'এই মাসের খরচ বসান', 'এই মাসের cost বসান', 'Enter this month''s figures', 'costing', 69)
 on conflict (code) do nothing;

-- ---------- seed: recommendations (one row per rule) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('production_requires_cost', 'production_requires_cost', '72', 'stock', '"refuse"', '{prd_icost}',
  'কোনো উপাদানের খরচ অজানা থাকলে উৎপাদন আটকে যাবে, তাই ভুল বা শূন্য খরচের মাল তৈরি হবে না। সব উপাদানের খরচ বসানোর পরই চালু করা ভালো; তার আগে "সতর্কতা" (warn) থাকুক।',
  'কোনো ingredient এর cost অজানা থাকলে production আটকে যাবে, তাই ভুল বা শূন্য cost এর মাল তৈরি হবে না। সব ingredient এর cost বসানোর পরই চালু করা ভালো; তার আগে warn থাকুক।',
  'Production stops when an ingredient cost is unknown, so goods are never made at a wrong or zero cost. Switch to refuse only after every ingredient cost is entered; until then keep warn.', 10),
 ('accounting_on', 'accounting_on', 'base', 'books', 'true', '{acc_start,acc_coa,acc_map,acc_opening,stk_opening}',
  'হিসাব চালু করলে বিক্রি, ক্রয়, উৎপাদন নিজে থেকে খাতায় ঢোকে। শুরুর তারিখ, অ্যাকাউন্ট ম্যাপিং, শুরুর ব্যালান্স ও শুরুর স্টক ঠিক হলে তবেই চালু করুন। কখন চালু হবে সেটা মালিকের সিদ্ধান্ত।',
  'Accounting on করলে sale, purchase, production নিজে থেকে books এ ঢোকে। Start date, account mapping, opening balance ও opening stock ঠিক হলে তবেই on করুন। কখন on হবে সেটা owner এর সিদ্ধান্ত।',
  'With accounting on, sales, purchases and production post to the books by themselves. Switch on only when the start date, account mappings, opening balances and opening stock are in place. When to start is the owner''s decision.', 20),
 ('accounting_autopost', 'accounting_autopost', '72', 'books', 'true', '{}',
  'অটো-পোস্ট চালু থাকলে আজকের কাগজ হাতে পোস্ট করতে হয় না এবং "পেন্ডিং" জমে না।',
  'Autopost on থাকলে আজকের document হাতে post করতে হয় না এবং pending জমে না।',
  'With autopost on nobody has to post documents by hand and nothing piles up as pending.', 21),
 ('reports_net_of_returns', 'reports_net_of_returns', '72', 'reports', 'true', '{}',
  'ফেরত বাদ দিয়ে রিপোর্ট দেখালে বিক্রি ও লাভ বাস্তবের কাছাকাছি থাকে।',
  'Return বাদ দিয়ে report দেখালে sale ও profit বাস্তবের কাছাকাছি থাকে।',
  'Reports net of returns keep sales and profit close to what really happened.', 22),
 ('recipe_approval_required', 'recipe_approval_required', '73', 'stock', '"warn"', '{}',
  'অনুমোদনের আগে রেসিপি ব্যবহার হলে হলুদ সতর্কতা দেখায় কিন্তু কাজ আটকায় না। মালিক চাইলে নিজে অনুমোদন দিতে পারেন বা অন্যকে অনুমতি দিতে পারেন; পরে চাইলে "on" (আটকানো) করা যায়।',
  'Approve এর আগে recipe ব্যবহার হলে yellow warning দেখায় কিন্তু কাজ আটকায় না। Owner চাইলে নিজে approve করতে পারেন বা অন্যকে অনুমতি দিতে পারেন; পরে চাইলে on (আটকানো) করা যায়।',
  'A recipe used before approval shows a yellow warning and nothing is blocked. The owner may approve himself or grant the right to another person; later you may switch to on (refuse).', 30),
 ('recipe_self_approve', 'recipe_self_approve', '73', 'stock', 'false', '{}',
  'যে রেসিপি বদলায় সে নিজে অনুমোদন না দিলে ভুল ধরা পড়ার সুযোগ থাকে। মালিক সবসময় নিজে অনুমোদন দিতে পারেন।',
  'যে recipe বদলায় সে নিজে approve না দিলে ভুল ধরা পড়ার সুযোগ থাকে। Owner সবসময় নিজে approve দিতে পারেন।',
  'When the person who changed a recipe cannot approve it, mistakes get caught. The owner can always approve himself.', 31),
 ('artisan_self_view', 'artisan_self_view', '73', 'stock', 'false', '{}',
  'কারিগরদের নিজস্ব লগইন হওয়ার পর শুধু নিজের রেসিপি দেখানোর জন্য চালু করুন; তার আগে বন্ধ থাকুক।',
  'Artisan দের নিজস্ব login হওয়ার পর শুধু নিজের recipe দেখানোর জন্য on করুন; তার আগে off থাকুক।',
  'Switch on to show an artisan only his own recipes after artisans have their own logins; keep off until then.', 32),
 ('production_manual_needs_reason', 'production_manual_needs_reason', '74', 'stock', 'true', '{}',
  'রেসিপি ছাড়া সরাসরি উৎপাদন তোলার সময় কারণ লিখতে বললে হাতে-তোলা এন্ট্রি ধরা সহজ হয়।',
  'Recipe ছাড়া direct production তোলার সময় reason লিখতে বললে হাতে-তোলা entry ধরা সহজ হয়।',
  'Asking for a reason on a direct production-in makes hand-typed entries easy to trace.', 33),
 ('production_requires_recipe', 'production_requires_recipe', '74', 'stock', null, '{}',
  'কে কীভাবে উৎপাদন তুলবে তা মালিক মাঠের অবস্থা দেখে ঠিক করবেন; কোনো মান প্রস্তাব করা হয়নি।',
  'কে কীভাবে production তুলবে তা owner মাঠের অবস্থা দেখে ঠিক করবেন; কোনো value প্রস্তাব করা হয়নি।',
  'Who records production and how is the owner''s call in the field; no value is recommended.', 34),
 ('recipe_waste_required', 'recipe_waste_required', '73', 'stock', null, '{}',
  'অপচয়ের শতাংশ বাধ্যতামূলক করা হবে কিনা মালিক ঠিক করবেন; কোনো মান প্রস্তাব করা হয়নি।',
  'Waste % বাধ্যতামূলক করা হবে কিনা owner ঠিক করবেন; কোনো value প্রস্তাব করা হয়নি।',
  'Whether the waste percentage is mandatory is the owner''s call; no value is recommended.', 35),
 ('cost_gap_warn_pct', 'cost_gap_warn_pct', '74', 'stock', null, '{}',
  'আজকের কেনা দামের সঙ্গে গড় খরচের ফারাকের সীমা প্রথম কিছু বাস্তব কেনার পর মালিক নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'আজকের কেনা দাম আর average cost এর ফারাকের limit প্রথম কিছু বাস্তব কেনার পর owner নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'The owner types the gap limit between today''s purchase price and the average cost after the first real purchases. No number is recommended.', 36),
 ('yield_variance_warn_pct', 'yield_variance_warn_pct', '74', 'stock', null, '{}',
  'রেসিপির ফলন আর আসল ফলনের ফারাকের সীমা কিছু বাস্তব উৎপাদনের পর মালিক নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Recipe yield আর actual yield এর ফারাকের limit কিছু বাস্তব production এর পর owner নিজে লিখবেন। কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'The owner types the limit for the gap between recipe yield and actual yield after some real productions. No number is recommended.', 37),
 ('cost_rule_self_approve', 'cost_rule_self_approve', '75', 'stock', 'false', '{}',
  'যে ভাগের নিয়ম লিখেছে সে নিজে অনুমোদন না দিলে ভুল ধরা পড়ে। অন্য একজনকে অনুমোদনের অনুমতি দিন।',
  'যে allocation rule লিখেছে সে নিজে approve না দিলে ভুল ধরা পড়ে। অন্য একজনকে approve এর অনুমতি দিন।',
  'When the person who wrote an allocation rule cannot approve it, errors get caught. Grant the approval right to another person.', 40),
 ('cost_attrib_in_pl', 'cost_attrib_in_pl', '78', 'stock', 'true', '{cs_attrib}',
  'শোরুম ও অ্যাডমিন খরচের ভাগ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখায়। কোন খরচ কোন শোরুমের তা বসানোর পর চালু করুন।',
  'Showroom ও admin cost এর ভাগ branch P&L এ আলাদা row তে দেখায়। কোন cost কোন showroom এর তা বসানোর পর on করুন।',
  'Shows the showroom and admin cost shares as separate rows in the branch P&L. Switch on after the cost-to-showroom assignment is set.', 41),
 ('online_orders_on', 'online_orders_on', 'base', 'pos', 'true', '{onl_channels}',
  'অনলাইন অর্ডারের খাতা চালু রাখুন: ওয়েব ফর্ম, ফোন ও কাউন্টার দিয়ে শুরু করা সহজ।',
  'Online order এর খাতা on রাখুন: web form, phone ও walk-in দিয়ে শুরু করা সহজ।',
  'Keep the online-order book on; the web form, phone and walk-in are the easy way to start.', 50),
 ('inbox_on', 'inbox_on', '76', 'pos', 'true', '{onl_channels}',
  'সব বার্তা এক জায়গায় দেখতে ইনবক্স চালু রাখুন। ওয়েব ফর্ম, ফোন ও কাউন্টার দিয়ে শুরু করুন।',
  'সব message এক জায়গায় দেখতে inbox on রাখুন। Web form, phone ও walk-in দিয়ে শুরু করুন।',
  'Keep the inbox on to see every message in one place. Start with the web form, phone and walk-in.', 51),
 ('web_form_on', 'web_form_on', '76', 'pos', 'true', '{onl_channels}',
  'ওয়েব ফর্ম থেকে অর্ডার নিতে চালু করুন। দাম সার্ভারে ঠিক হয়, ডুপ্লিকেট আটকানো থাকে। পাবলিক ঠিকানা বসানো বাইরের সেটআপ।',
  'Web form থেকে order নিতে on করুন। দাম server এ ঠিক হয়, duplicate আটকানো থাকে। Public URL বসানো বাইরের setup।',
  'Switch on to take orders from the web form. Prices are fixed on the server and duplicates are caught. The public URL is an outside setup.', 52),
 ('meta_intake_on', 'meta_intake_on', '76', 'pos', 'false', '{}',
  'Messenger, Instagram, WhatsApp-এর সংযোগ না হওয়া পর্যন্ত বন্ধ থাকুক। সংযোগ ফোন থেকে করা যায় না, আলাদা সেটআপ লাগে।',
  'Messenger, Instagram, WhatsApp এর connection না হওয়া পর্যন্ত off থাকুক। Connection phone থেকে করা যায় না, আলাদা setup লাগে।',
  'Keep Messenger, Instagram and WhatsApp off until the connection exists. The connection cannot be made from the phone; it is a separate setup.', 53),
 ('inbox_autodraft_on', 'inbox_autodraft_on', '76', 'pos', 'false', '{}',
  'মেসেজ থেকে অর্ডারের খসড়া নিজে নিজে হওয়া শুরুতে বন্ধ থাকুক; প্রথমে স্টাফ হাতে যাচাই করুক।',
  'Message থেকে order draft নিজে নিজে হওয়া শুরুতে off থাকুক; প্রথমে staff হাতে check করুক।',
  'Keep automatic order drafts from messages off at the start; staff check them by hand first.', 54),
 ('inbox_pii_guard_on', 'inbox_pii_guard_on', '76', 'pos', 'true', '{}',
  'গ্রাহকের ফোন ও ঠিকানা শুধু অনুমতি পাওয়া মানুষ দেখবে; প্রতিটি দেখা লগে থাকে। অনুমতি দিন সেই শাখার বিক্রয়কর্মী ও মালিককে।',
  'Customer এর phone ও address শুধু অনুমতি পাওয়া মানুষ দেখবে; প্রতিটি দেখা log এ থাকে। অনুমতি দিন সেই branch এর POS staff ও owner কে।',
  'Customer phone and address are seen only by authorised people, and every view is logged. Grant the right to the POS staff of that branch and to the owner.', 55),
 ('web_form_captcha_on', 'web_form_captcha_on', '76', 'pos', null, '{}',
  'ক্যাপচা চালাতে বাইরের চাবি লাগে (ফোন থেকে করা যায় না)। সেটআপ হলে মালিক চালু করবেন।',
  'Captcha চালাতে বাইরের key লাগে (phone থেকে করা যায় না)। Setup হলে owner on করবেন।',
  'The captcha needs an outside key (not possible from the phone). The owner switches it on once that is set up.', 56),
 ('web_form_rate_max', 'web_form_rate_max', '76', 'pos', null, '{}',
  'প্রতি ডিভাইসে সর্বোচ্চ ফর্ম সংখ্যা: দেওয়া সীমার ভেতরে নিজের সংখ্যা লিখুন, বা পাঠানো ডিফল্ট রাখুন। নতুন কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Per device max form সংখ্যা: দেওয়া range এর ভেতরে নিজের সংখ্যা লিখুন, বা shipped default রাখুন। নতুন কোনো সংখ্যা প্রস্তাব করা হয়নি।',
  'Maximum forms per device: type your own number inside the shown range, or keep the shipped default. No new number is recommended.', 57),
 ('web_form_rate_window_min', 'web_form_rate_window_min', '76', 'pos', null, '{}',
  'ফর্ম সীমার সময়-জানালা: দেওয়া সীমার ভেতরে নিজের মান লিখুন, বা পাঠানো ডিফল্ট রাখুন।',
  'Form limit এর time window: দেওয়া range এর ভেতরে নিজের value লিখুন, বা shipped default রাখুন।',
  'Time window of the form limit: type your own value inside the shown range, or keep the shipped default.', 58),
 ('inbox_silence_hours', 'inbox_silence_hours', '76', 'pos', null, '{}',
  'কত ঘণ্টা মেসেজ না এলে সতর্ক করবে: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'কত ঘণ্টা message না এলে warn করবে: নিজের value লিখুন বা shipped default রাখুন।',
  'After how many hours without a message to warn: type your own value or keep the shipped default.', 59),
 ('intake_max_tries', 'intake_max_tries', '76', 'pos', null, '{}',
  'ব্যর্থ ইনটেক কয়বার আবার চেষ্টা হবে: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'Failed intake কয়বার retry হবে: নিজের value লিখুন বা shipped default রাখুন।',
  'How many times a failed intake is retried: type your own value or keep the shipped default.', 60),
 ('intake_retry_min', 'intake_retry_min', '76', 'pos', null, '{}',
  'আবার চেষ্টার মধ্যে কত মিনিট অপেক্ষা: নিজের মান লিখুন বা পাঠানো ডিফল্ট রাখুন।',
  'Retry এর মধ্যে কত minute অপেক্ষা: নিজের value লিখুন বা shipped default রাখুন।',
  'Minutes to wait between retries: type your own value or keep the shipped default.', 61),
 ('web_form_public_url', 'web_form_public_url', '76', 'pos', null, '{}',
  'ওয়েব ফর্মের পাবলিক ঠিকানা বাইরের সেটআপ শেষ হলে বসবে; ফোন থেকে তৈরি করা যায় না।',
  'Web form এর public URL বাইরের setup শেষ হলে বসবে; phone থেকে তৈরি করা যায় না।',
  'The public URL of the web form is entered once the outside setup is done; it cannot be created from the phone.', 62),
 ('online_pack_warn_on', 'online_pack_warn_on', '77', 'pos', 'true', '{}',
  'প্যাক করার সময় স্টক কম থাকলে সতর্ক করে, কিন্তু কিছু আটকায় না।',
  'Pack করার সময় stock কম থাকলে warn করে, কিন্তু কিছু আটকায় না।',
  'Warns at pack time when stock is short; nothing is blocked.', 70),
 ('online_pack_reserve_on', 'online_pack_reserve_on', '77', 'pos', null, '{}',
  'প্যাক হওয়া অন্য অর্ডারের স্টক সতর্কতার হিসাব থেকে বাদ দেয় (কাউন্টার আটকায় না)। কোনো মান প্রস্তাব করা হয়নি — মালিক দেখে ঠিক করবেন।',
  'Packed অন্য order এর stock warning এর হিসাব থেকে বাদ দেয় (counter আটকায় না)। কোনো value প্রস্তাব করা হয়নি — owner দেখে ঠিক করবেন।',
  'Deducts the stock of other packed orders in the warning (the counter is not blocked). No value is recommended; the owner decides.', 71),
 ('online_keep_order_price', 'online_keep_order_price', '77', 'pos', 'true', '{}',
  'অর্ডারে যে দাম বলা হয়েছিল ডেলিভারিতে সেটাই থাকে; ভিন্ন দাম হলে ম্যানেজারের অনুমতি ও হলুদ এক্সেপশন লাগে।',
  'Order এ যে দাম বলা হয়েছিল delivery তে সেটাই থাকে; ভিন্ন দাম হলে manager এর approval ও yellow exception লাগে।',
  'The price quoted on the order is kept at delivery; a different price needs the manager''s approval and logs a yellow exception.', 72)
 on conflict (code) do nothing;

-- ---------- internal: one check -> {n problems, total, applies} (counts only, never amounts) ----------
create or replace function public._setup_chk81(p_code text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare n bigint := 0; tot bigint := 0; ap boolean := true; st date := public._acct_start(); td date := public._acct_today(); h numeric; last_in timestamptz;
        req text[] := array['sales', 'cogs', 'inv_finished', 'inv_raw', 'inv_pack', 'payable', 'receivable', 'pay_cash', 'owner_capital', 'overhead_absorbed'];
begin
  case p_code
  when 'stk_tracked' then
    select count(*) into tot from public.items where tracked and coalesce(is_active, true);
    n := case when tot = 0 then 1 else 0 end;
  when 'stk_unit' then
    select count(*), count(*) filter (where nullif(btrim(coalesce(base_unit, '')), '') is null) into tot, n from public.items where tracked and coalesce(is_active, true);
  when 'stk_opening' then
    select count(*), count(*) filter (where not exists (select 1 from public.stock_ledger l where l.item_id = i.id)) into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_conv' then
    select count(*), count(*) filter (where exists (select 1 from unnest(coalesce(i.sell_units, '{}'::text[])) u where u is not null and u <> '' and public._unit_factor_base(i.id, u) is null))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true);
  when 'stk_cost' then   -- stock on hand with no known cost; blank or 0 = unknown
    select count(*), count(*) filter (where not exists (select 1 from public.stock_balance b where b.item_id = i.id and b.avg_cost > 0)
                                      and not exists (select 1 from public.item_costs c where c.item_id = i.id and c.cost_price > 0))
      into tot, n from public.items i where i.tracked and coalesce(i.is_active, true) and exists (select 1 from public.stock_balance b2 where b2.item_id = i.id and b2.qty > 0);
  when 'stk_neg', 'flw_neg' then
    select count(*) into n from public.stock_balance where qty < 0;
    select count(*) into tot from public.stock_balance;
  when 'acc_start' then
    n := case when st is null then 1 else 0 end; tot := 1;
  when 'acc_coa' then
    select count(*) into tot from public.coa_accounts where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'acc_map' then
    tot := array_length(req, 1);
    select count(*) into n from unnest(req) k where not exists (select 1 from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k and a.active);
  when 'acc_opening' then
    tot := 1;
    n := case when exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)) then 0 else 1 end;
  when 'acc_wait', 'flw_acc_wait' then
    if st is null then ap := false; else select count(*) into n from public._acct_docs(st) d where d.waiting is not null; end if;
  when 'acc_err', 'flw_acc_err' then
    if st is null then ap := false; else
      select count(*) into n from public.acct_post_errors72 x where exists (select 1 from public._acct_docs(st) dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null);
    end if;
  when 'flw_acc_old' then   -- not yet in the books and dated before today (no invented age limit: "earlier than today")
    if st is null then ap := false; else
      select count(*) into n from public._acct_docs(st) d where d.waiting is null and d.entry_date < td;
    end if;
  when 'prd_recipes' then
    select count(*) into tot from public.recipes where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'prd_lines' then
    select count(*), count(*) filter (where not exists (select 1 from public.recipe_lines l where l.recipe_id = r.id and l.active)) into tot, n from public.recipes r where r.active;
  when 'prd_yield' then
    select count(*), count(*) filter (where r.yield_qty is null or r.yield_qty <= 0) into tot, n from public.recipes r where r.active;
  when 'prd_approve' then
    select count(*), count(*) filter (where r.approved_at is null) into tot, n from public.recipes r where r.active;
  when 'prd_icost' then
    select count(distinct l.ingredient_item_id), count(distinct l.ingredient_item_id) filter (where not exists (select 1 from public.stock_balance b where b.item_id = l.ingredient_item_id and b.avg_cost > 0)
                                                              and not exists (select 1 from public.item_costs c where c.item_id = l.ingredient_item_id and c.cost_price > 0))
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_unit' then
    select count(*), count(*) filter (where nullif(l.unit, '') is not null and public._unit_factor_base(l.ingredient_item_id, l.unit) is null)
      into tot, n from public.recipe_lines l join public.recipes r on r.id = l.recipe_id and r.active where l.active;
  when 'prd_conv' then
    select count(*), count(*) filter (where (c.mode = 'pool' and coalesce(c.normal_monthly_output, 0) <= 0)
                                         or (c.mode = 'recipe' and not exists (select 1 from public.recipe_cost_components x where x.active)))
      into tot, n from public.location_cost_cfg c where c.mode <> 'off';
  when 'flw_prod_cost' then
    select count(*) into tot from public.production_runs where status is distinct from 'void';
    select count(*) into n from public.production_runs where status is distinct from 'void' and cost_complete is false;
  when 'flw_pool' then
    select count(*), count(*) filter (where not exists (select 1 from public.factory_cost_pools p where p.location_id = c.location_id and p.active and p.month = date_trunc('month', td)::date))
      into tot, n from public.location_cost_cfg c where c.mode = 'pool';
    ap := tot > 0;
  when 'cs_sources' then
    select count(*) into tot from public.cost_sources where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'cs_rule' then
    select count(*), count(*) filter (where not exists (select 1 from public.cost_source_rules r where r.source_id = s.id and r.status = 'approved')) into tot, n from public.cost_sources s where s.active;
  when 'cs_attrib' then
    select count(*) into tot from public.location_cost_attribution where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_channels' then
    select count(*) into tot from public.sales_channels where active;
    n := case when tot = 0 then 1 else 0 end;
  when 'onl_url' then
    ap := public.rule_on('web_form_on'); n := case when ap and coalesce(public.rule_txt('web_form_public_url'), '') = '' then 1 else 0 end; tot := 1;
  when 'onl_bot' then
    ap := public.rule_on('meta_intake_on'); n := case when ap and not exists (select 1 from public.intake_bots where active) then 1 else 0 end; tot := 1;
  when 'flw_inbox_new' then
    select count(*) into n from public.inbound_messages where status = 'new' and (received_at at time zone 'Asia/Dhaka')::date < td;
    select count(*) into tot from public.inbound_messages;
  when 'flw_inbox_silent' then
    h := public.rule_num('inbox_silence_hours');
    if coalesce(h, 0) <= 0 then ap := false; else
      select max(received_at) into last_in from public.inbound_messages;
      n := case when last_in is not null and last_in < now() - make_interval(hours => h::int) then 1 else 0 end; tot := 1;
    end if;
  when 'flw_intake_fail' then
    select count(*) into n from public.intake_failures where state = 'failed';
    select count(*) into tot from public.intake_failures;
  when 'flw_oo_flags' then
    select count(*) into n from public.online_order_flags where state = 'open';
    select count(*) into tot from public.online_order_flags;
  else
    return jsonb_build_object('n', null, 'total', null, 'applies', false, 'unknown_check', true);
  end case;
  return jsonb_build_object('n', n, 'total', tot, 'applies', ap);
end $$;

-- may the caller read the guide (owner, or a person who may see costs)?
create or replace function public._setup_view81() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.biz_cost_ok());
$$;

-- ---------- 1. the recommendation list ----------
create or replace function public.setup_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; d record; r public.rules; eff jsonb; st text; chosen boolean; iss jsonb; c record; cj jsonb;
        cnt_ok int := 0; cnt_rec int := 0; cnt_own int := 0; cnt_info int := 0; cnt_ni int := 0; ready boolean;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for d in select * from public.setup_rec_defs81 where active order by sort, code loop
    select * into r from public.rules where key = d.rule_key;
    iss := '[]'::jsonb; ready := true;
    if not found then
      st := 'not_installed'; cnt_ni := cnt_ni + 1; eff := null; chosen := false;
    else
      eff := coalesce(r.value, r.default_value); chosen := r.value is not null;
      if d.rec_value is null then st := 'info'; cnt_info := cnt_info + 1;
      elsif eff is not distinct from d.rec_value then st := 'ok'; cnt_ok := cnt_ok + 1;
      elsif chosen then st := 'owner_chosen'; cnt_own := cnt_own + 1;
      else st := 'recommended'; cnt_rec := cnt_rec + 1; end if;
      for c in select x.code, x.label_bn, x.label_mix, x.label_en from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then
          ready := false;
          iss := iss || jsonb_build_object('code', c.code, 'n', (cj->>'n')::bigint, 'label_bn', c.label_bn, 'label_mix', c.label_mix, 'label_en', c.label_en);
        end if;
      end loop;
    end if;
    out_ := out_ || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'phase', d.phase, 'module', d.module, 'kind', r.kind,
      'status', st, 'recommended', d.rec_value, 'current', eff, 'default', r.default_value, 'owner_chosen', chosen,
      'min', r.min_value, 'max', r.max_value, 'unit', r.unit, 'choices', r.choices,
      'ready', ready, 'ready_issues', iss,
      'rule_label_bn', r.label_bn, 'rule_label_mix', r.label_mix, 'rule_label_en', r.label_en,
      'reason_bn', d.reason_bn, 'reason_mix', coalesce(d.reason_mix, d.reason_bn), 'reason_en', d.reason_en, 'sort', d.sort);
  end loop;
  return jsonb_build_object('advisory', true, 'can_apply', public.is_owner(),
    'summary', jsonb_build_object('total', jsonb_array_length(out_), 'ok', cnt_ok, 'recommended', cnt_rec, 'owner_chosen', cnt_own, 'info', cnt_info, 'not_installed', cnt_ni),
    'items', out_);
end $$;

-- ---------- 2. the one-tap recommended apply (owner only, audited, never over an owner's choice unless asked) ----------
create or replace function public.setup_recommend_apply(p_client uuid, p_codes text[] default null, p_overwrite boolean default false, p_ignore_ready boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if d.rec_value is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from d.rec_value then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
    owr := r.value is not null;                       -- the owner already chose another value
    if owr and not (p_overwrite and p_codes is not null) then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'owner_chosen'); continue; end if;
    ready := true;
    if not p_ignore_ready then
      for c in select x.code from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then ready := false; end if;
      end loop;
    end if;
    if not ready then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_ready'); continue; end if;
    begin
      perform public.set_rule(d.rule_key, d.rec_value);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', d.rec_value, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $$;

-- ---------- 3. readiness: "before you switch it on" (advice only) ----------
create or replace function public.setup_readiness(p_topic text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; t record; c record; cj jsonb; cl jsonb; nprob int; napp int;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for t in select * from public.setup_topic_defs81 where p_topic is null or topic = p_topic order by sort loop
    cl := '[]'::jsonb; nprob := 0; napp := 0;
    for c in select * from public.setup_check_defs81 where topic = t.topic and kind = 'ready' and active order by sort loop
      cj := public._setup_chk81(c.code);
      if coalesce((cj->>'applies')::boolean, false) then
        napp := napp + 1;
        if coalesce((cj->>'n')::bigint, 0) > 0 then nprob := nprob + 1; end if;
      end if;
      cl := cl || jsonb_build_object('code', c.code, 'level', c.level, 'applies', coalesce((cj->>'applies')::boolean, false), 'problems', cj->'n', 'total', cj->'total',
        'ok', coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) = 0,
        'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en,
        'fix_bn', c.fix_bn, 'fix_mix', coalesce(c.fix_mix, c.fix_bn), 'fix_en', c.fix_en, 'nav', c.nav);
    end loop;
    out_ := out_ || jsonb_build_object('topic', t.topic, 'gate_rule', t.gate_rule, 'gate_on', case when t.gate_rule is null then null else public.rule_on(t.gate_rule) end,
      'label_bn', t.label_bn, 'label_mix', coalesce(t.label_mix, t.label_bn), 'label_en', t.label_en,
      'ready', nprob = 0, 'problem_checks', nprob, 'checks', cl);
  end loop;
  return jsonb_build_object('advisory', true, 'topics', out_);
end $$;

-- ---------- 4. post-activation flow checks: "is everything flowing?" ----------
create or replace function public.setup_flow_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; c record; cj jsonb; on_ boolean; lvl text; nwarn int := 0;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for c in select * from public.setup_check_defs81 where kind = 'flow' and active order by sort loop
    on_ := case when c.gate_rule is null then true else public.rule_on(c.gate_rule) end;
    if not on_ then
      out_ := out_ || jsonb_build_object('code', c.code, 'topic', c.topic, 'level', 'na', 'gate_rule', c.gate_rule, 'problems', 0,
        'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en, 'nav', c.nav);
      continue;
    end if;
    cj := public._setup_chk81(c.code);
    lvl := case when not coalesce((cj->>'applies')::boolean, false) then 'na' when coalesce((cj->>'n')::bigint, 0) = 0 then 'ok' else c.level end;
    if lvl = 'warn' then nwarn := nwarn + 1; end if;
    out_ := out_ || jsonb_build_object('code', c.code, 'topic', c.topic, 'level', lvl, 'gate_rule', c.gate_rule, 'problems', cj->'n', 'total', cj->'total',
      'label_bn', c.label_bn, 'label_mix', coalesce(c.label_mix, c.label_bn), 'label_en', c.label_en,
      'fix_bn', c.fix_bn, 'fix_mix', coalesce(c.fix_mix, c.fix_bn), 'fix_en', c.fix_en, 'nav', c.nav);
  end loop;
  return jsonb_build_object('advisory', true, 'warnings', nwarn, 'checks', out_);
end $$;

-- ---------- 5. the owner's trail ----------
create or replace function public.setup_apply_history(p_limit int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('client_id', b.client_id, 'applied_at', b.applied_at, 'applied_by', b.applied_by, 'overwrite', b.overwrite, 'ignore_ready', b.ignore_ready,
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', l.code, 'rule_key', l.rule_key, 'old', l.old_value, 'new', l.new_value, 'overwrote', l.overwrote) order by l.id), '[]'::jsonb) from public.setup_apply_lines81 l where l.batch_id = b.client_id)) order by b.applied_at desc)
    from (select * from public.setup_apply_batches81 order by applied_at desc limit greatest(1, least(coalesce(p_limit, 30), 200))) b), '[]'::jsonb);
end $$;

-- ---------- RLS + privileges ----------
alter table public.setup_rec_defs81 enable row level security;
alter table public.setup_check_defs81 enable row level security;
alter table public.setup_topic_defs81 enable row level security;
alter table public.setup_apply_batches81 enable row level security;
alter table public.setup_apply_lines81 enable row level security;
revoke all on public.setup_rec_defs81, public.setup_check_defs81, public.setup_topic_defs81, public.setup_apply_batches81, public.setup_apply_lines81 from public, anon, authenticated;
grant select on public.setup_rec_defs81, public.setup_check_defs81, public.setup_topic_defs81 to authenticated;
grant select on public.setup_apply_batches81, public.setup_apply_lines81 to authenticated;
drop policy if exists setup_rec_defs81_sel on public.setup_rec_defs81;
create policy setup_rec_defs81_sel on public.setup_rec_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_check_defs81_sel on public.setup_check_defs81;
create policy setup_check_defs81_sel on public.setup_check_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_topic_defs81_sel on public.setup_topic_defs81;
create policy setup_topic_defs81_sel on public.setup_topic_defs81 for select to authenticated using (public._setup_view81());
drop policy if exists setup_apply_batches81_sel on public.setup_apply_batches81;
create policy setup_apply_batches81_sel on public.setup_apply_batches81 for select to authenticated using (public.is_owner());
drop policy if exists setup_apply_lines81_sel on public.setup_apply_lines81;
create policy setup_apply_lines81_sel on public.setup_apply_lines81 for select to authenticated using (public.is_owner());
revoke usage, select on sequence public.setup_apply_lines81_id_seq from public, anon, authenticated;
revoke all on function public.setup_recommendations(), public.setup_recommend_apply(uuid, text[], boolean, boolean), public.setup_readiness(text), public.setup_flow_check(), public.setup_apply_history(int),
  public._setup_chk81(text), public._setup_view81(), public._setup_ro81() from public, anon, authenticated;
grant execute on function public._setup_view81() to authenticated;   -- used by the read policies
grant execute on function public.setup_recommendations(), public.setup_recommend_apply(uuid, text[], boolean, boolean), public.setup_readiness(text), public.setup_flow_check(), public.setup_apply_history(int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase508.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase82.sql there and is already pasted on the live database under that name.
-- Renumbered to phase508.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 508 - Part 1 step E (first half): stock-side guards. Run AFTER phase78 (phase72 lives on another branch; this file does not need it).
-- Idempotent (paste twice = no error). Nothing is deleted. EVERY new switch defaults to today's behaviour; the app only RECOMMENDS (guard_recommendations()), never forces.
--   E1 GRN vs purchase page   purchase_grn_guard off|skip|link, grn_bill_link(), grn_pending_report() ("bill-less receive" list)
--   E2 void of a posted bill  purchase_void_guard off|warn|refuse (return / negative stock / live GRN batch), purchase_void_payments void|keep (keep = supplier credit, use supplier_refund)
--   E3 unit conversion        unit_conv_required off|warn|refuse, item editor guard (trigger), unit_unknown_items()
--   E4 negative stock         neg_grant_log, production_negative_reason off|warn|required, never_opened_negative_items()
-- Re-created from their latest definitions (only lines tagged bos82 differ): _post_purchase_p13, _void_purchase_p13, _sale_stock_out, stock_post.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('purchase_grn_guard', 'stock', 'choice', '"off"', null, '["off","skip","link"]'::jsonb, null, null,
  'GRN উৎস হলে ক্রয় bill stock বাড়াবে কি: বন্ধ / বাদ / link লাগবে', 'GRN source হলে purchase bill stock বাড়াবে কি: off / skip / link লাগবে', 'When GRN is the stock source, does the purchase bill add stock: off, skip or link required',
  'বন্ধ = আগের মতো (দুটোই stock বাড়ায়, দুবার গোনা হতে পারে)। বাদ = bill শুধু টাকা/বাকি ধরে, stock GRN থেকে। link = bill-এর সাথে GRN জুড়তে হবে, না হলে পোস্ট হবে না। শুধু "কেনা মালের উৎস = GRN" হলে কাজ করে।',
  'off = আগের মতো (দুটোই stock বাড়ায়)। skip = bill শুধু টাকা/বাকি ধরে, stock আসে GRN থেকে। link = bill-এর সাথে GRN জুড়তে হবে। শুধু "কেনা মালের source = GRN" হলে কাজ করে।',
  'off = as before (both add stock, goods can be counted twice). skip = the bill only records money / dues, stock comes from the GRN. link = the bill must be linked to its GRN before posting. Works only when the bought-goods source is GRN.', 74),
 ('purchase_void_guard', 'stock', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'পোস্ট করা ক্রয় bill বাতিলে সুরক্ষা: বন্ধ / warn / block', 'Posted purchase bill void-এ সুরক্ষা: off / warn / refuse', 'Voiding a posted purchase bill: off, warn or refuse',
  'ফেরত bill থাকলে, মাল ব্যবহার হয়ে stock ঋণাত্মক হলে, বা চালু GRN batch থাকলে বাতিল block (বা red warning)। বন্ধ = আগের মতো।',
  'Return থাকলে, মাল ব্যবহার হয়ে stock negative হলে, বা live GRN batch থাকলে void block (বা red warning)। off = আগের মতো।',
  'Refuse (or flag red) when a posted return refers to the bill, voiding would make stock negative, or a live GRN batch exists. off = as before.', 75),
 ('purchase_void_payments', 'stock', 'choice', '"void"', null, '["void","keep"]'::jsonb, null, null,
  'bill বাতিলে supplierকে দেওয়া টাকা: বাতিল ধরা / রেখে দেওয়া (credit)', 'Bill void-এ supplier payment: void ধরা / রেখে দেওয়া (credit)', 'Supplier payments when a bill is voided: void them or keep them as credit',
  'default = আগের মতো (payment-ও বাতিল, day book-এ টাকা ফিরে আসে)। রেখে দেওয়া = টাকা সত্যিই বেরিয়েছে, তাই payment থাকে এবং supplier-এর কাছে credit হয়; টাকা ফেরত পেলে "supplier refund" লিখুন।',
  'Default = আগের মতো (payment-ও void, day book-এ টাকা ফিরে আসে)। keep = টাকা সত্যিই বেরিয়েছে, তাই payment থাকে আর supplier credit হয়; টাকা ফেরত পেলে "supplier refund" লিখুন।',
  'Default = as before (payments are voided too, the day book shows the cash back). keep = the money really left, so the payment stays and becomes supplier credit; record a supplier refund when the money comes back.', 76),
 ('unit_conv_required', 'stock', 'choice', '"warn"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'stock-tracked পণ্যে unit-এর conversion না থাকলে বিক্রি: বন্ধ / warn / block', 'Tracked item-এ unit conversion না থাকলে sale: off / warn / refuse', 'Sale of a tracked item with no unit conversion: off, warn or refuse',
  'warn = আগের মতো (বিক্রি হয়, stock কমে না, yellow warning)। block = online বিক্রি "unit_unknown" দিয়ে ফেরত; offline থেকে দেরিতে আসা বিক্রি নেওয়া হয় কিন্তু red চিহ্ন; item editorও tracked করতে দেয় না।',
  'warn = আগের মতো (sale হয়, stock কমে না, yellow warning)। refuse = online sale "unit_unknown" দিয়ে ফেরত; offline থেকে দেরিতে আসা sale নেওয়া হয় কিন্তু red flag; item editor-ও tracked করতে দেয় না।',
  'warn = as before (the sale goes through, stock is not reduced, yellow warning). refuse = an online sale is refused with unit_unknown; a late offline sale is accepted but flagged red; the item editor also refuses tracked.', 77),
 ('neg_grant_log', 'stock', 'switch', 'false', null, null, null, null,
  '"stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হলে yellow warning', '"Sell below zero" permission ব্যবহার হলে yellow warning', 'Yellow warning when the sell-below-zero permission is used',
  'চালু = ব্লক মোডে যে অনুমতির জোরে stock-এর নিচে গেলে কে, কোন পণ্য, কত — লেখা থাকে। বন্ধ = আগের মতো।',
  'On = block mode-এ permission-এর জোরে stock-এর নিচে গেলে কে, কোন item, কত — লেখা থাকে। Off = আগের মতো।',
  'On = in block mode, going below zero by that permission logs who, which item and how much. Off = as before.', 78),
 ('production_negative_reason', 'stock', 'choice', '"off"', null, '["off","warn","required"]'::jsonb, null, null,
  'উৎপাদনে কাঁচামাল ঋণাত্মক হলে কারণ: বন্ধ / warn / required', 'Production-এ ingredient negative হলে reason: off / warn / required', 'Production taking an ingredient below zero: off, warn or reason required',
  'বন্ধ = আগের মতো। warn = yellow warning। required = উৎপাদনের নোটে কারণ না লিখলে আটকে যায়।',
  'off = আগের মতো। warn = yellow warning। required = production note-এ reason না লিখলে আটকে যায়।',
  'off = as before. warn = yellow warning. required = refused unless the production note gives a reason.', 79)
 on conflict (key) do nothing;

-- the GRN <-> bill link uses the existing shadow engine, domain 'grn' (primary = the GRN form, shadow = the bill). Only a link: it has no a/b lock.
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('grn', 'ক্রয় bill (টাকা / বাকি)', 'Purchase bill (money / dues)', 'form 04-1 (GRN, মাল গ্রহণ)', 'Form 04-1 (GRN, goods received)', 'a',
  'শুধু bill ও GRN জোড়া লাগানোর link; কোনটা stock বাড়াবে তা "কেনা মালের উৎস" switch-এ ঠিক হয়।', 'Link between a bill and its GRN only; which one adds stock is decided by the bought-goods source switch.', 80)
 on conflict (domain) do nothing;

-- ---------- re-created functions (latest definitions; only lines tagged bos82 differ) ----------
CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb; gm text; skipst boolean := false;   -- bos82
begin
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if pb.status = 'posted' then          -- a re-sent request: answered only to someone who may see purchases (or who posted it)
    if not (public._pur_ok(pb.location_id) or pb.posted_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true);
  end if;
  if not (public.has_grant(gcode, pb.location_id) or public._use_em(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  if pb.kind = 'return' then
    if pb.ref_bill_id is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
      perform public._stock_exc(pb.location_id, 'purchase_return_unreferenced', 'red', 'বিল ছাড়া ক্রয় ফেরত (বিল ' || coalesce(pb.bill_no, '-') || ')',
        'A purchase return was posted without the original bill (return ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE', pb.total);
    else
      perform 1 from public.purchase_bills where id = pb.ref_bill_id for update;
      select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'description', l.description, 'qty', l.qty, 'unit', l.unit, 'unit_cost', l.unit_cost)), '[]'::jsonb) into norm
        from public.purchase_lines l where l.bill_id = pb.id;
      if not exists (select 1 from public.purchase_bills where id = pb.ref_bill_id and status = 'posted') then raise exception 'bad_ref_bill'; end if;
      perform public._return_check(pb.ref_bill_id, pb.id, norm, true);
    end if;
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  -- bos82: GRN exclusivity. Source = GRN and guard on: the bill keeps money / supplier balance, the GRN holds the stock (no second purchase_in)
  gm := coalesce(public.rule_txt('purchase_grn_guard'), 'off');   -- bos82
  if pb.kind = 'bill' and gm in ('skip', 'link') and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then   -- bos82
    if gm = 'link' and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void') then   -- bos82
      raise exception 'grn_link_required' using detail = 'GRN is the stock source: link this bill to its GRN before posting', hint = 'grn_bill_link';   -- bos82
    end if;   -- bos82
    skipst := true;   -- bos82
  end if;   -- bos82
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one); a return is checked the same way
    if pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ' || case when pb.kind = 'return' then 'ফেরতের' else 'ক্রয়' end || 'মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': ' || case when pb.kind = 'return' then 'return ' else '' end || 'unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked and not (skipst and pb.kind = 'bill') then   -- bos82: stock comes from the GRN
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        -- out at the current average cost (cost null = the average); what the supplier credits beyond / below that is the variance of this return
        lid := public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, null, null, now(), null, null, 'full');
        select unit_cost into av from public.stock_ledger where id = lid;
        var := var + round(bq * (round(ucb * net, 6) - coalesce(av, round(ucb * net, 6))), 2);
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now(), variance = case when pb.kind = 'return' then var end where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum) || case when skipst then jsonb_build_object('stock_from_grn', true) else '{}'::jsonb end;   -- bos82
end $function$;

CREATE OR REPLACE FUNCTION public._void_purchase_p13(p_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; r public.stock_ledger; gmode text; why text; shorts text := ''; kept numeric := 0; z record;   -- bos82
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if pb.status = 'void' then          -- a re-sent request: answered only to someone who may see purchases (or who voided it)
    if not (public._pur_ok(pb.location_id) or pb.void_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true);
  end if;
  if pb.status = 'draft' then
    if not (public.has_grant(case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end, pb.location_id)) then raise exception 'not allowed'; end if;
  elsif not (public.has_grant('purchase_void', pb.location_id) or public._use_em('purchase_void', pb.location_id, 'void_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed';
  end if;
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  perform public.lock_check(pb.bill_date);
  -- bos82: a posted bill that others depend on cannot simply disappear (switch purchase_void_guard: off | warn | refuse)
  gmode := coalesce(public.rule_txt('purchase_void_guard'), 'off');   -- bos82
  if gmode <> 'off' and pb.kind = 'bill' then   -- bos82
    if exists (select 1 from public.purchase_bills x where x.ref_bill_id = pb.id and x.kind = 'return' and x.status = 'posted') then why := 'void_has_return';   -- bos82
    elsif exists (select 1 from public.grn_batch_links gl join public.stock_batches b on b.id = gl.batch_id where gl.source_type = 'purchase' and gl.source_id = pb.id and b.qty_remaining > 0) then why := 'void_has_grn_batch';   -- bos82
    else   -- bos82
      for z in select o.item_id, o.location_id, sum(o.qty_delta) q from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason = 'purchase_in'   -- bos82
               and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) group by 1, 2 order by 1, 2 loop   -- bos82
        perform 1 from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id for update;   -- bos82
        if coalesce((select sb.qty from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id), 0) - z.q < 0 then   -- bos82
          why := 'void_would_go_negative'; shorts := shorts || case when shorts = '' then '' else ', ' end || coalesce((select code from public.items where id = z.item_id), '?');   -- bos82
        end if;   -- bos82
      end loop;   -- bos82
    end if;   -- bos82
    if why is not null then   -- bos82
      if gmode = 'refuse' then raise exception '%', why using detail = case why when 'void_has_return' then 'A posted purchase return refers to this bill: void the return first' when 'void_has_grn_batch' then 'GRN batches with stock left exist for this bill' else 'Stock used or sold already: voiding would make it negative: ' || shorts end, hint = 'purchase_void_guard'; end if;   -- bos82
      perform public._stock_exc(pb.location_id, 'purchase_void_unsafe', 'red', 'ক্রয় bill বাতিল (ঝুঁকিপূর্ণ): ' || why || ' ' || shorts, 'Purchase bill voided although: ' || why || ' ' || shorts, null, pb.bill_date, 'PURCHASE', pb.total);   -- bos82
    end if;   -- bos82
  end if;   -- bos82
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  if coalesce(public.rule_txt('purchase_void_payments'), 'void') = 'keep' then   -- bos82: cash really left; the payment stays and becomes supplier credit (use supplier_refund to take the money back)
    select coalesce(sum(amount), 0) into kept from public.supplier_payments where bill_id = pb.id and not voided;   -- bos82
    if kept > 0 then perform public._stock_exc(pb.location_id, 'purchase_void_credit', 'yellow', 'বাতিল bill-এর পরিশোধ রাখা হয়েছে, supplier-এর কাছে credit: ' || kept::text, 'Voided bill payment kept as supplier credit: ' || kept::text, null, pb.bill_date, 'PURCHASE', kept); end if;   -- bos82
  else   -- bos82
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  end if;   -- bos82
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void') || case when kept > 0 then jsonb_build_object('payments_kept', kept) else '{}'::jsonb end;   -- bos82
end $function$;

CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text;   -- bos82
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false; pm text; who text;   -- bos82
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale'); end if;           -- (12) read once
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    -- bos82: production that takes an ingredient below zero: reason needed (production_negative_reason: off | warn | required)
    if p_reason = 'issue_out' and p_ref_type = 'production' then   -- bos82
      pm := coalesce(public.rule_txt('production_negative_reason'), 'off');   -- bos82
      if pm <> 'off' then   -- bos82
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      if mode = 'block' and p_neg = 'full' and public.rule_on('neg_grant_log') and public.has_grant('sell_below_zero', p_loc) then   -- bos82: the grant was used to go below zero: tell the owner who / what / how much
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        perform public._stock_exc(p_loc, 'sell_below_zero_used', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): "stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): the sell-below-zero permission was used, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $function$;

-- ---------- E3: item editor refuses tracked while the unit has no conversion (only when unit_conv_required = refuse) ----------
create or replace function public._items_unit_conv82() returns trigger
language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if not new.tracked or coalesce(public.rule_txt('unit_conv_required'), 'warn') <> 'refuse' then return new; end if;
  if tg_op = 'UPDATE' and old.tracked and old.unit is not distinct from new.unit and old.base_unit is not distinct from new.base_unit then return new; end if;
  b := coalesce(nullif(btrim(new.base_unit), ''), nullif(btrim(new.unit), ''));
  if nullif(btrim(coalesce(new.unit, '')), '') is not null and b is not null and new.unit <> b and public.unit_factor(new.id, new.unit, b) is null then
    raise exception 'unit_unknown' using detail = 'Cannot track ' || new.code || ': add the conversion from ' || new.unit || ' to ' || b || ' first', hint = new.code;
  end if;
  return new;
end $$;
drop trigger if exists items_unit_conv82 on public.items;
create trigger items_unit_conv82 after insert or update of tracked, unit, base_unit on public.items for each row execute function public._items_unit_conv82();
revoke all on function public._items_unit_conv82() from public, anon, authenticated;

-- ---------- E3: owner board count ----------
create or replace function public.unit_unknown_items() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'unit', i.unit, 'base_unit', coalesce(nullif(btrim(i.base_unit), ''), i.unit)) order by i.code), '[]'::jsonb) into r
    from public.items i
   where i.tracked and i.is_active and nullif(btrim(coalesce(i.unit, '')), '') is not null
     and i.unit <> coalesce(nullif(btrim(i.base_unit), ''), nullif(btrim(i.unit), ''))
     and public.unit_factor(i.id, i.unit, coalesce(nullif(btrim(i.base_unit), ''), nullif(btrim(i.unit), ''))) is null;
  return jsonb_build_object('count', jsonb_array_length(r), 'items', r);
end $$;

-- ---------- E4: tracked stock that went negative with no opening / receipt ever ----------
create or replace function public.never_opened_negative_items() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'location_id', b.location_id, 'qty', b.qty) order by i.code, b.location_id), '[]'::jsonb) into r
    from public.stock_balance b join public.items i on i.id = b.item_id
   where b.qty < 0 and i.tracked
     and not exists (select 1 from public.stock_ledger l where l.item_id = b.item_id and l.location_id = b.location_id and l.qty_delta > 0
                        and l.reverses_id is null and l.reason not in ('sale_void_in', 'sale_return', 'reversal'));
  return jsonb_build_object('count', jsonb_array_length(r), 'items', r);
end $$;

-- ---------- E1: link a GRN (04-1) to the bill that pays for it ----------
create or replace function public.grn_bill_link(p_entry uuid, p_bill uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; b public.purchase_bills; lk bigint;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '04-1' or e.status not in ('submitted', 'approved') then raise exception 'grn_not_found'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found or b.kind <> 'bill' or b.status = 'void' then raise exception 'bill_not_found'; end if;
  if b.location_id <> e.location_id then raise exception 'location_mismatch'; end if;
  if not (public.is_owner() or (public.can_loc(b.location_id) and (public.has_grant('purchase_entry', b.location_id) or public._pur_ok(b.location_id)))) then raise exception 'not allowed'; end if;
  lk := public.shadow_link_add('grn', b.location_id, 'entries', e.id::text, 'purchase_bills', b.id::text, coalesce(left(btrim(p_note), 200), 'GRN linked to bill'));
  return jsonb_build_object('link', lk, 'entry', e.id, 'bill', b.id);
end $$;

-- ---------- E1: pending lists ("bill-বিহীন রিসিভ" / receives with no bill, and bills with no GRN when GRN is the source) ----------
create or replace function public.grn_pending_report(p_days int default 60) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare src text := coalesce(public.rule_txt('grn_receipt_source'), 'purchase'); a jsonb; c jsonb; d0 date := (now() at time zone 'Asia/Dhaka')::date - greatest(coalesce(p_days, 60), 1);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'date', e.entry_date, 'location_id', e.location_id, 'supplier', e.data->>'supplier',
           'stock_from', case when src = 'grn' then 'grn' else 'purchase_page' end) order by e.entry_date desc), '[]'::jsonb) into a
    from public.entries e
   where e.form_code = '04-1' and e.status = 'approved' and e.entry_date >= d0 and (public.is_owner() or public.can_loc(e.location_id))
     and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.primary_type = 'entries' and x.primary_id = e.id::text and x.state <> 'void');
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', pb.id, 'bill_no', pb.bill_no, 'date', pb.bill_date, 'location_id', pb.location_id, 'supplier_id', pb.supplier_id) order by pb.bill_date desc), '[]'::jsonb) into c
    from public.purchase_bills pb
   where src = 'grn' and pb.kind = 'bill' and pb.status = 'posted' and pb.bill_date >= d0 and public._pur_ok(pb.location_id)
     and exists (select 1 from public.purchase_lines l join public.items i on i.id = l.item_id where l.bill_id = pb.id and i.tracked)
     and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void');
  return jsonb_build_object('source', src, 'guard', coalesce(public.rule_txt('purchase_grn_guard'), 'off'),
    'receipts_without_bill', a, 'bills_without_receipt', c);
end $$;

-- ---------- recommendations: key, current, recommended, reason in 3 languages. Read-only. The owner may choose anything. ----------
create or replace function public.guard_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; nu int; counted boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  nu := (public.unit_unknown_items() ->> 'count')::int;
  counted := exists (select 1 from public.stock_ledger where reason in ('count_adjust', 'opening'));
  out_ := out_ || jsonb_build_array(
   jsonb_build_object('key', 'purchase_grn_guard', 'current', public.rule_txt('purchase_grn_guard'),
     'recommended', case when coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then 'skip' else 'off' end,
     'reason_bn', 'GRN-কে উৎস করলে bill stock বাড়ালে একই মাল দুবার গোনা হয়; "বাদ" দিলে bill শুধু টাকা ধরে।',
     'reason_mix', 'GRN source হলে bill-ও stock বাড়ালে একই মাল দুবার গোনা হয়; skip দিলে bill শুধু টাকা ধরে।',
     'reason_en', 'If GRN is the source and the bill also adds stock, the same goods are counted twice; skip makes the bill record money only.'),
   jsonb_build_object('key', 'purchase_void_guard', 'current', public.rule_txt('purchase_void_guard'), 'recommended', 'refuse',
     'reason_bn', 'ফেরত দেওয়া বা ব্যবহার হয়ে যাওয়া মালের bill বাতিল করলে stock ঋণাত্মক ও হিসাব ভুল হয়।',
     'reason_mix', 'Return হয়ে যাওয়া বা use হয়ে যাওয়া মালের bill void করলে stock negative ও হিসাব ভুল হয়।',
     'reason_en', 'Voiding a bill whose goods were returned or used makes stock negative and the books wrong.'),
   jsonb_build_object('key', 'purchase_void_payments', 'current', public.rule_txt('purchase_void_payments'), 'recommended', 'keep',
     'reason_bn', 'টাকা সত্যিই বেরিয়ে গেছে; payment বাতিল করলে day book-এ টাকা ফিরে আসার ভুল দেখায়।',
     'reason_mix', 'টাকা সত্যিই বেরিয়ে গেছে; payment void করলে day book-এ টাকা ফিরে আসার ভুল দেখায়।',
     'reason_en', 'The money really left; voiding the payment makes the day book show cash that never came back.'),
   jsonb_build_object('key', 'unit_conv_required', 'current', public.rule_txt('unit_conv_required'),
     'recommended', case when nu = 0 then 'refuse' else 'warn' end, 'unknown_unit_items', nu,
     'reason_bn', case when nu = 0 then 'সব stock-tracked পণ্যের conversion আছে, তাই block নিরাপদ।' else nu::text || 'টি পণ্যের conversion নেই; আগে সেগুলো ঠিক করুন, তারপর block চালু করুন।' end,
     'reason_mix', case when nu = 0 then 'সব tracked item-এর conversion আছে, তাই refuse করা নিরাপদ।' else nu::text || 'টি item-এর conversion নেই; আগে ঠিক করুন, তারপর refuse চালু করুন।' end,
     'reason_en', case when nu = 0 then 'Every tracked item has its conversion, so refusing is safe.' else nu::text || ' item(s) have no conversion; fix them first, then switch refuse on.' end),
   jsonb_build_object('key', 'neg_grant_log', 'current', to_jsonb(public.rule_on('neg_grant_log')), 'recommended', to_jsonb(true),
     'reason_bn', 'যার অনুমতি আছে সে stock-এর নিচে বিক্রি করলে মালিক যেন জানতে পারেন।',
     'reason_mix', 'যার permission আছে সে stock-এর নিচে sell করলে owner যেন জানতে পারেন।',
     'reason_en', 'The owner should know whenever someone with the permission sells below zero.'),
   jsonb_build_object('key', 'production_negative_reason', 'current', public.rule_txt('production_negative_reason'), 'recommended', 'required',
     'reason_bn', 'কাঁচামাল না থাকা অবস্থায় উৎপাদন করলে খরচ ভুল হয়; কারণ লিখে রাখা ভালো।',
     'reason_mix', 'Ingredient না থাকা অবস্থায় production করলে cost ভুল হয়; reason লিখে রাখা ভালো।',
     'reason_en', 'Producing without enough ingredient stock gives wrong costs; a written reason keeps a trace.'),
   jsonb_build_object('key', 'stock_negative_mode', 'current', public.rule_txt('stock_negative_mode'),
     'recommended', case when counted then 'block' else coalesce(public.rule_txt('stock_negative_mode'), 'warn') end,
     'reason_bn', case when counted then 'প্রথম stock count/opening হয়ে গেছে, তাই stock-এর চেয়ে বেশি বিক্রি block যুক্তিসঙ্গত।' else 'প্রথম stock count বা opening stock এখনো হয়নি; তার পরে "block" বেছে নিন।' end,
     'reason_mix', case when counted then 'প্রথম stock count/opening হয়ে গেছে, তাই stock-এর বেশি sale block করা যুক্তিসঙ্গত।' else 'প্রথম stock count বা opening এখনো হয়নি; তার পরে block বেছে নিন।' end,
     'reason_en', case when counted then 'The first stock count / opening is done, so blocking sales above stock is reasonable.' else 'No stock count or opening yet; choose block after the first one.' end));
  return out_;
end $$;

revoke all on function public.unit_unknown_items(), public.never_opened_negative_items(), public.grn_bill_link(uuid, uuid, text), public.grn_pending_report(int), public.guard_recommendations() from public, anon;
grant execute on function public.unit_unknown_items(), public.never_opened_negative_items(), public.grn_bill_link(uuid, uuid, text), public.grn_pending_report(int), public.guard_recommendations() to authenticated;

-- ---------------------------------------------------------------- phase509.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase83.sql there and is already pasted on the live database under that name.
-- Renumbered to phase509.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 509 (bos83) - STEP E-b: form vs screen (E5), expense double count (E6), transit shortage (E7), offline POS failed sales (E8).
--   Needs phase8 ... phase71 (phase72 is on another branch and is NOT needed). Additive; paste-twice safe. No old phase file is edited. Nothing is posted by this file.
--   NEW SWITCHES - every default is today's behaviour; the app shows a RECOMMENDED value with a reason (form_guard_recommendations()) but never forces it:
--     form_051_mode        reference | post | refuse   default reference = unchanged (form 05-1 behaves exactly as before; a NULL-cost finished line is now FLAGGED)
--                          post   = a posted 05-1 line also takes the recipe ingredients OUT of stock at the average cost and costs the finished goods
--                          refuse = 05-1 is never a posting source (lines kept as 'skipped: form051_not_a_source')
--     transit_short_mode   keep_in_transit | loss   default keep_in_transit = unchanged (a short receipt books nothing, only the yellow flag as before)
--                          loss = the shortfall is booked in the ledger as reason transit_loss (cost = the sender's cost)
--     transit_open_hours   blank (no limit written in code); a number = open transit older than that many hours becomes an urgent notification
--     offline_soft_stock   off (default) | on : a sale replayed from the offline queue that is refused only for 'insufficient_stock' is accepted and flagged instead
--   E5 : unmatched_forms() ; pending shadow link when a form is skipped because the screen is the record ; dup_suspects 'production_screens' branch
--   E6 : dup_suspects 'expense' branch ; suggest_expense_link(entry) ; expense_link_apply(entry, note)
--   E7 : transit_loss ledger reason ; transit_short_open() ; transit_short_resolve() ; transit_open_list() ; urgent_alerts() also scans old open transit
--   E8 : record_sale_offline() (same arguments as record_sale2) ; pos_replay_override() manager override with the ORIGINAL client_id ; pos_failed_* board table
--   RE-CREATED from their LATEST definition (only lines marked bos83 differ): _elp_post_line, dup_suspects, stock_receive_transfer, urgent_alerts, _sale_stock_out.
--   NOT re-created (another agent owns them): production_post, recipe_cost, _acct_docs, _p27_pl, biz_daily, acct_status, post_purchase, void_purchase.
-- ============================================================

-- ---------- 1. switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('form_051_mode', 'stock', 'choice', '"reference"', null, '["reference","post","refuse"]'::jsonb, null, null,
  'কারখানা দৈনিক শিট (05-1): stock-এ কীভাবে ধরা হবে', 'Factory daily sheet (05-1): stock-এ কীভাবে ধরা হবে', 'Factory daily sheet (05-1): how it reaches stock',
  'reference = আগের মতোই (ডিফল্ট)। post = শিট stock-এ গেলে recipe-র ingredientও গড় দামে বের হবে ও তৈরি মালের cost বসবে। refuse = 05-1 কখনো stock পোস্ট করবে না।',
  'reference = আগের মতোই (default)। post = sheet stock-এ গেলে recipe-র ingredient-ও average cost-এ বের হবে ও finished goods-এর cost বসবে। refuse = 05-1 কখনো stock post করবে না।',
  'reference = exactly as before (default). post = when the sheet posts to stock, the recipe ingredients also go out at the average cost and the finished goods get a cost. refuse = 05-1 never posts to stock.', 840),
 ('transit_short_mode', 'stock', 'choice', '"keep_in_transit"', null, '["keep_in_transit","loss"]'::jsonb, null, null,
  'transfer-এ কম পৌঁছালে ঘাটতি কীভাবে ধরা হবে', 'Transfer-এ কম পৌঁছালে ঘাটতি কীভাবে ধরা হবে', 'How a short transfer receipt is booked',
  'keep_in_transit = আগের মতোই (ডিফল্ট; শুধু হলুদ সতর্কতা, ঘাটতি তালিকায় থাকে)। loss = ঘাটতি stock খাতায় "পথে ক্ষতি" হিসেবে ওঠে।',
  'keep_in_transit = আগের মতোই (default; শুধু yellow flag, ঘাটতি list-এ থাকে)। loss = ঘাটতি stock ledger-এ transit loss হিসেবে ওঠে।',
  'keep_in_transit = as before (default; only the yellow flag, the shortfall stays on a list). loss = the shortfall is booked in the stock ledger as a transit loss.', 841),
 ('transit_open_hours', 'stock', 'number', null, 'hours', null, 1, 8760,
  'পথে থাকা transfer কত ঘণ্টা পর জরুরি সতর্কতা', 'Transit-এ থাকা transfer কত ঘণ্টা পর urgent alert', 'Open transfers older than this many hours raise an urgent alert',
  'ঘর খালি = কোনো সতর্কতা নয় (ডিফল্ট)। সংখ্যা দিলে সেই ঘণ্টার বেশি "পাঠানো হয়েছে, গ্রহণ হয়নি" থাকলে জরুরি বার্তা আসে।',
  'ঘর খালি = কোনো alert নয় (default)। সংখ্যা দিলে সেই ঘণ্টার বেশি sent-but-not-received থাকলে urgent notification আসে।',
  'Blank = no alert (default). A number: a transfer that stays sent but not received for longer than that raises an urgent notification.', 842),
 ('offline_soft_stock', 'pos', 'switch', 'false', null, null, null, null,
  'offline-এ করা sale stock-এ না কুলালেও গ্রহণ', 'Offline-এ করা sale stock-এ না কুলালেও গ্রহণ', 'Accept offline sales even when stock is short',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু = offline সারি থেকে আবার পাঠানো sale শুধু stock কম বলে আটকালে সেটা গ্রহণ হয় ও হলুদ সতর্কতা থাকে (পণ্য আগেই দেওয়া হয়ে গেছে)। অনলাইন sale বদলায় না।',
  'Off = আগের মতোই (default)। On = offline queue থেকে replay করা sale শুধু stock কম বলে আটকালে accept হয় ও yellow flag থাকে (goods আগেই দেওয়া হয়ে গেছে)। Online sale বদলায় না।',
  'Off = as before (default). On = a sale re-sent from the offline queue that is refused only because stock is short is accepted and flagged yellow (the goods were already handed over). Online sales do not change.', 843)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('pos_replay_override', 'pos', 84, 'offline sale manager override-এ আবার পাঠানো', 'Offline sale manager override-এ আবার পাঠানো', 'Re-send a refused offline sale on manager override', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- 2. ledger reason transit_loss (merge-safe: the current list is read and one value added) ----------
do $$
declare d text; vals text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.stock_ledger'::regclass and conname = 'stock_ledger_reason_check';
  if d is not null and d not like '%transit_loss%' then
    vals := substring(d from 'ARRAY\[(.*)\]\)');
    alter table public.stock_ledger drop constraint stock_ledger_reason_check;
    execute 'alter table public.stock_ledger add constraint stock_ledger_reason_check check (reason = any (array[' || regexp_replace(vals, '::text', '', 'g') || ', ''transit_loss'']))';
  end if;
end $$;

-- ---------- 3. E7 helpers ----------
-- the shortfall of a received transfer is written off: +short (cost blank, so the average does not move) then -short as transit_loss at the SENDER's cost. Net balance change 0.
create or replace function public._transit_loss83(p_transfer uuid, p_short numeric, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; cost numeric; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_transfer;
  if not found or p_short is null or p_short <= 0 then return null; end if;
  if exists (select 1 from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transit_loss') then return null; end if;
  select case when sum(-qty_delta) > 0 then sum(-qty_delta * unit_cost) / sum(-qty_delta) end into cost
    from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' and unit_cost is not null;
  perform public.stock_post(t.item_id, t.to_location_id, p_short, 'transfer_in', 'transfer', t.id::text, null, null, now(), left('transit short: counted in to be written off ' || coalesce(p_note, ''), 200), null, 'none', null, md5(t.id::text || ':tl_in')::uuid);
  lid := public.stock_post(t.item_id, t.to_location_id, -p_short, 'transit_loss', 'transfer', t.id::text, case when cost is null then null else round(cost, 6) end, null, now(), left('transit loss ' || coalesce(p_note, ''), 200), null, 'none', null, md5(t.id::text || ':tl')::uuid);
  return lid;
end $$;

-- open transit older than the owner's limit -> an urgent notification (once per transfer per day). Blank limit = nothing happens.
create or replace function public._transit_open_scan83() returns int
language plpgsql security definer set search_path = public as $$
declare h numeric := public.rule_num('transit_open_hours'); r record; n int := 0;
begin
  if h is null or h <= 0 then return 0; end if;
  for r in select t.id, t.qty, t.from_location_id, t.to_location_id, t.sent_at, i.name_bn, i.name_en, i.code
             from public.stock_transfers t join public.items i on i.id = t.item_id
            where t.status = 'sent' and t.sent_at < now() - make_interval(secs => (h * 3600)::double precision) order by t.sent_at limit 200 loop
    if public._notif_add('transit_open', 'bad', 'পথে থাকা transfer এখনো গ্রহণ হয়নি', 'A transfer is still in transit',
         r.name_bn || ' ' || r.qty::text || ': পাঠানো হয়েছে, গ্রহণ হয়নি', coalesce(r.name_en, r.code) || ' ' || r.qty::text || ': sent, not yet received',
         'stock', r.id::text, 'owner', r.to_location_id) then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---------- 4. re-created functions (latest definitions; lines marked bos83 differ) ----------
CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
        fmode text; rc public.recipes; nr record; tot numeric := 0; cok boolean := true; av numeric; yf numeric;   -- bos83
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
    -- bos83: the slip has no screen record yet: a PENDING link (form -> screen record owed) so unmatched_forms() can list it
    begin perform public.shadow_link_add(public._entry_domain(e.form_code), e.location_id, 'entries', e.id::text, 'stock_screen', null, 'form ' || e.form_code || ' skipped: the screen is the record, screen record owed'); exception when others then null; end;
    return;
  end if;
  -- bos83: owner switch form_051_mode = refuse: the factory daily sheet is not a posting source at all (kept as a reference, line shown as skipped)
  fmode := coalesce(public.rule_txt('form_051_mode'), 'reference');
  if l->>'skip' is null and kind = 'prod' and e.form_code = '05-1' and fmode = 'refuse' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'form051_not_a_source', ref, auth.uid());
    return;
  end if;
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item';
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    ucb := null;
    if e.form_code = '05-1' and fmode = 'post' then      -- bos83: the finished goods are made FROM the recipe's ingredients, taken out at the average cost
      select r.* into rc from public.recipes r where r.item_id = it.id and r.active and exists (select 1 from public.recipe_lines x where x.recipe_id = r.id and x.active) order by r.version desc limit 1;
      if not found then raise exception 'no_recipe_for_051: %', it.code; end if;
      perform public._recipe_gate73(rc.id);
      yf := public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit);
      if yf is null or not (yf > 0) then raise exception 'unit_unknown: %', it.code; end if;
      for nr in select * from public._recipe_need(rc.id, bq / yf, e.location_id) order by item_id loop
        if not nr.tracked then raise exception 'ingredient_not_tracked: %', coalesce(nr.code, ''); end if;
        if not nr.unit_ok then raise exception 'unit_unknown: %', coalesce(nr.code, ''); end if;
        if nr.need < 0.0001 then continue; end if;
        select b.avg_cost into av from public.stock_balance b where b.item_id = nr.item_id and b.location_id = e.location_id;
        if av is null then cok := false; else tot := tot + nr.need * av; end if;
        perform public.stock_post(nr.item_id, e.location_id, -nr.need, 'issue_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
      end loop;
      ucb := case when cok and bq > 0 then round(tot / bq, 6) end;
    end if;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, ucb, bid, at_, left(note, 200), null, 'none');
    if ucb is null and e.form_code = '05-1' and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'form051_cost_null' and x.status = 'open') then      -- bos83
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (e.id, e.form_code, e.location_id, e.entry_date, 'form051_cost_null', 'yellow', null,
          jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || it.name_bn || ' তৈরি মাল cost ছাড়া stock-এ ঢুকেছে (cost অজানা)',
                             'en', e.form_code || '-' || e.serial || ': ' || coalesce(it.name_en, it.name_bn) || ' entered stock with NO cost (cost unknown)'));
    end if;
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $function$;
CREATE OR REPLACE FUNCTION public.dup_suspects(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb),
    -- bos83 F10: two finished-goods screens for the same item, place and day - a recipe run (production_post) and a plain finished-goods entry (stock_production_in)
    'production_screens', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.item_id, r.location_id, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.id as run_id, s.id as plain_ledger_id, s.qty_delta as plain_qty, r.yield_base as run_qty
          from public.production_runs r join public.stock_ledger s on s.item_id = r.item_id and s.location_id = r.location_id and s.reason = 'production_in' and s.ref_type = 'production'
            and s.reverses_id is null and s.id is distinct from r.ledger_in_id and (s.made_at at time zone 'Asia/Dhaka')::date = (r.made_at at time zone 'Asia/Dhaka')::date
         where r.status = 'done' and r.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and r.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and not exists (select 1 from public.production_runs r2 where r2.ledger_in_id = s.id) order by r.made_at limit 200) z), '[]'::jsonb),
    -- bos83 E6 (a4-F5): a quick expense and an approved 10-2 voucher line for the same place, day, head and amount that are NOT linked as a shadow
    'expense', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select q.id as quick_id, q.location_id, q.exp_date as day, q.head, q.amount, e.id as entry_id, e.serial
          from public.quick_expenses q
          join public.entries e on e.form_code = '10-2' and e.status = 'approved' and e.location_id = q.location_id and e.entry_date = q.exp_date
            and jsonb_typeof(e.data -> 'lines') = 'array' and not public.is_shadow('entries', e.id::text)
          join lateral jsonb_array_elements(e.data -> 'lines') ln on lower(btrim(ln ->> 'head')) = q.head and public._db_num(ln -> 'amount') = q.amount
         where q.status = 'done' and q.exp_date between p_from and p_to
           and not exists (select 1 from public.shadow_links x where x.primary_type = 'quick_expenses' and x.primary_id = q.id::text and x.state = 'confirmed')
         order by q.exp_date, q.id limit 200) z), '[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; cost numeric; ob public.stock_batches; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty then raise exception 'over_received'; end if;
  rem := rq;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    take := least(-o.qty_delta, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || rq::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || rq::text || ' — short in transit');
  end if;
  if rq < t.qty and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss
    perform public._transit_loss83(t.id, t.qty - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', rq, 'short', t.qty - rq);
end $function$;
CREATE OR REPLACE FUNCTION public.urgent_alerts(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._transit_open_scan83();      -- bos83: open transit older than the owner's limit becomes an urgent notification (blank limit = nothing)
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $function$;
CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; soft83 boolean := false; bal83 numeric;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, stock কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

-- ============================================================
-- E5 : form vs screen
-- ============================================================
-- forms that were skipped because the screen is the record, and for which NO screen record exists (same item, place, day, same kind of action). Read-only.
create or replace function public.unmatched_forms(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); own boolean := public.is_owner(); rows jsonb; tot int; unm int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 366 then raise exception 'bad_range'; end if;
  with lg as (select entry_id, max(gen) g from public.entry_ledger_posts group by entry_id),
  sk as (
    select e.id as entry_id, e.form_code, e.serial, e.location_id, e.entry_date, p.line_no, p.item_id, p.item_code, p.qty_base
      from public.entries e join lg on lg.entry_id = e.id
      join public.entry_ledger_posts p on p.entry_id = e.id and p.gen = lg.g and p.status = 'skipped' and p.reason = 'covered_by_screen'
     where e.status = 'approved' and e.form_code in ('04-2', '03-1', '04-3', '05-1') and e.entry_date between f and t and (p_loc is null or e.location_id = p_loc)
       and (own or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
  ), m as (
    select sk.*, exists (select 1 from public.stock_ledger s where s.item_id = sk.item_id and s.location_id = sk.location_id and s.reverses_id is null
                 and (s.made_at at time zone 'Asia/Dhaka')::date = sk.entry_date
                 and ((sk.form_code = '04-2' and s.reason = 'issue_out' and s.ref_type = 'issue') or (sk.form_code = '04-3' and s.reason = 'count_adjust' and s.ref_type = 'count')
                   or (sk.form_code = '03-1' and s.reason = 'transfer_out' and s.ref_type = 'transfer') or (sk.form_code = '05-1' and s.reason = 'production_in' and s.ref_type = 'production'))) as matched
      from sk
  )
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', m.entry_id, 'form_code', m.form_code, 'serial', m.serial, 'location_id', m.location_id, 'entry_date', m.entry_date,
           'line_no', m.line_no, 'item_code', m.item_code, 'qty', m.qty_base,
           'link_id', (select l.id from public.shadow_links l where l.primary_type = 'entries' and l.primary_id = m.entry_id::text and l.shadow_type = 'stock_screen' and l.state <> 'void' limit 1)) order by m.entry_date, m.form_code, m.serial, m.line_no)
           filter (where not m.matched), '[]'::jsonb), count(*), count(*) filter (where not m.matched)
    into rows, tot, unm from m;
  return jsonb_build_object('from', f, 'to', t, 'label_bn', 'স্ক্রিন-রেকর্ডহীন ফর্ম', 'label_mix', 'Screen record ছাড়া form', 'label_en', 'Forms with no screen record',
    'lines_checked', tot, 'lines_unmatched', unm, 'rows', rows,
    'note_en', 'A count slip whose counted figure equals the book figure creates no ledger row on the screen either, so it can show here without being wrong.');
end $$;

-- owner: confirm the pending links whose slip now has a screen record for every skipped line (the last 366 days)
create or replace function public.unmatched_forms_sync() returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0; u jsonb; lid bigint; d date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  u := public.unmatched_forms(d - 366, d, null);
  for l in select s.id, s.primary_id from public.shadow_links s where s.primary_type = 'entries' and s.shadow_type = 'stock_screen' and s.state = 'pending' order by s.id limit 500 loop
    if not exists (select 1 from jsonb_array_elements(coalesce(u -> 'rows', '[]'::jsonb)) r where r ->> 'entry_id' = l.primary_id) then
      select min(x.id) into lid from public.entry_ledger_posts p join public.entries e on e.id = p.entry_id
        join public.stock_ledger x on x.item_id = p.item_id and x.location_id = p.location_id and x.reverses_id is null and x.ref_type in ('issue', 'count', 'transfer', 'production')
         and (x.made_at at time zone 'Asia/Dhaka')::date = e.entry_date
       where p.entry_id = l.primary_id::uuid and p.status = 'skipped' and p.reason = 'covered_by_screen';
      if lid is not null then
        update public.shadow_links set state = 'confirmed', shadow_id = lid::text, confirmed_by = auth.uid(), confirmed_at = now() where id = l.id and state = 'pending';
        n := n + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('confirmed', n);
end $$;

-- RECOMMENDATIONS (never forced): key, current, recommended, reason in 3 languages
create or replace function public.form_guard_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prim text; fm text := coalesce(public.rule_txt('form_051_mode'), 'reference'); rec jsonb := '[]'::jsonb; rfm text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  prim := public.path_primary('production', 0);
  rfm := case when public.rule_on('forms_post_to_ledger') and prim = 'b' then 'post' else 'reference' end;
  rec := rec || jsonb_build_object('key', 'form_051_mode', 'current', fm, 'recommended', rfm,
    'reason_bn', case rfm when 'post' then 'এখন 05-1 শিটই production-এর record; তাই শিট stock-এ গেলে ingredient-ও বের হওয়া দরকার, নইলে তৈরি মাল বিনা cost-এ stock-এ ঢোকে।'
                                  else 'এখন recipe production screen-ই record; 05-1 শুধু রেফারেন্স। বদলানোর দরকার নেই।' end,
    'reason_mix', case rfm when 'post' then 'এখন 05-1 sheet-ই production-এর record; তাই sheet stock-এ গেলে ingredient-ও বের হওয়া দরকার, নইলে finished goods বিনা cost-এ stock-এ ঢোকে।'
                                  else 'এখন recipe production screen-ই record; 05-1 শুধু reference। বদলানোর দরকার নেই।' end,
    'reason_en', case rfm when 'post' then 'The 05-1 sheet is the production record here, so when it posts to stock the ingredients must go out too; otherwise finished goods enter stock with no cost.'
                                  else 'The recipe production screen is the record here and 05-1 is only a reference. No change is needed.' end);
  rec := rec || jsonb_build_object('key', 'transit_short_mode', 'current', coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit'), 'recommended', 'loss',
    'reason_bn', 'কম পৌঁছানো মাল এখন কোনো খাতায় নেই। loss ধরলে ঘাটতি ledger-এ cost সহ থাকে, পরে accounts-এ নেওয়া যায়।',
    'reason_mix', 'কম পৌঁছানো মাল এখন কোনো খাতায় নেই। loss ধরলে ঘাটতি ledger-এ cost সহ থাকে, পরে accounts-এ নেওয়া যায়।',
    'reason_en', 'Goods that arrive short are in no book today. With loss, the shortfall stays in the ledger with its cost and can be taken into accounts later.');
  rec := rec || jsonb_build_object('key', 'transit_open_hours', 'current', public.rule_num('transit_open_hours'), 'recommended', null,
    'reason_bn', 'কোনো সংখ্যা কোডে দেওয়া নেই। আপনার ডেলিভারি সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি লিখুন।',
    'reason_mix', 'কোনো সংখ্যা code-এ দেওয়া নেই। আপনার delivery সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি লিখুন।',
    'reason_en', 'No number is built in. Enter a little more than the hours a delivery normally takes to arrive.');
  rec := rec || jsonb_build_object('key', 'offline_soft_stock', 'current', public.rule_on('offline_soft_stock'), 'recommended', true,
    'reason_bn', 'offline-এ sale করার সময় মাল ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে sale হারিয়ে যায়। চালু থাকলে sale রেকর্ড হয় ও yellow flag থাকে।',
    'reason_mix', 'Offline-এ sale করার সময় goods ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে sale হারিয়ে যায়। On থাকলে sale record হয় ও yellow flag থাকে।',
    'reason_en', 'An offline sale has already handed the goods over; if stock being short refuses it, the sale is lost. When on, the sale is recorded and flagged yellow.');
  return rec;
end $$;

-- ============================================================
-- E6 : expense double count
-- ============================================================
-- which pending quick entries cover which lines of a 10-2 voucher (same place, day, head, amount; each quick entry used once)
create or replace function public._expense_cover83(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; ln record; q uuid; used uuid[] := '{}'; out jsonb := '[]'::jsonb;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '10-2' or jsonb_typeof(e.data -> 'lines') <> 'array' then return '[]'::jsonb; end if;
  for ln in select x.o as n, lower(btrim(x.v ->> 'head')) as head, public._db_num(x.v -> 'amount') as amt from jsonb_array_elements(e.data -> 'lines') with ordinality x(v, o) loop
    continue when ln.amt is null or ln.amt <= 0;
    select qe.id into q from public.quick_expenses qe
      join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = qe.id::text and l.shadow_type = 'entries' and l.state = 'pending'
     where qe.status = 'done' and qe.location_id = e.location_id and qe.exp_date = e.entry_date and qe.head = ln.head and qe.amount = ln.amt and not (qe.id = any (used)) order by qe.created_at, qe.id limit 1;
    if q is not null then used := used || q; end if;
    out := out || jsonb_build_object('n', ln.n, 'head', ln.head, 'amount', ln.amt, 'quick_id', q);
    q := null;
  end loop;
  return out;
end $$;

-- offered on the approval screen of a 10-2 voucher: does a same-day quick entry already count this money?
create or replace function public.suggest_expense_link(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; c jsonb;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '10-2' then raise exception 'not_a_voucher'; end if;
  if not (public.is_owner() or (public.can_do('10-2', 'approve') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  c := public._expense_cover83(p_entry);
  return jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'is_shadow', public.is_shadow('entries', e.id::text), 'lines', c,
    'matched', (select count(*) from jsonb_array_elements(c) x where x ->> 'quick_id' is not null),
    'fully_covered', jsonb_array_length(c) > 0 and not exists (select 1 from jsonb_array_elements(c) x where x ->> 'quick_id' is null));
end $$;

-- the owner / approver accepts the offer: the voucher becomes the locked copy of those quick entries (counted once). Only when EVERY line is covered.
create or replace function public.expense_link_apply(p_entry uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; c jsonb; x jsonb; n int := 0;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.form_code <> '10-2' then raise exception 'not_a_voucher'; end if;
  if not (public.is_owner() or (public.can_do('10-2', 'approve') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  if e.status not in ('submitted', 'approved') then raise exception 'bad_status'; end if;
  if public.is_shadow('entries', e.id::text) then return jsonb_build_object('entry_id', e.id, 'noop', true); end if;
  if exists (select 1 from public.shadow_links s where s.primary_type = 'entries' and s.primary_id = e.id::text and s.state <> 'void') then raise exception 'entry_is_a_primary'; end if;
  c := public._expense_cover83(p_entry);
  if jsonb_array_length(c) = 0 or exists (select 1 from jsonb_array_elements(c) y where y ->> 'quick_id' is null) then raise exception 'not_fully_covered: some voucher lines have no matching quick entry'; end if;
  for x in select * from jsonb_array_elements(c) loop
    update public.shadow_links set state = 'confirmed', shadow_id = e.id::text, confirmed_by = auth.uid(), confirmed_at = now(), note = left(coalesce(note || ' | ', '') || 'linked at approval ' || coalesce(btrim(p_note), ''), 300)
     where primary_type = 'quick_expenses' and primary_id = x ->> 'quick_id' and shadow_type = 'entries' and state = 'pending';
    n := n + 1;
  end loop;
  return jsonb_build_object('entry_id', e.id, 'linked', n);
end $$;

-- ============================================================
-- E7 : transit shortage
-- ============================================================
create or replace function public.transit_short_open(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('transfer_id', t.id, 'item_id', t.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'from_location_id', t.from_location_id,
        'to_location_id', t.to_location_id, 'sent', t.qty, 'received', t.received_qty, 'short', t.qty - t.received_qty, 'received_at', t.received_at,
        'value', case when public._cost_ok(t.to_location_id) then (select round(sum(-l.qty_delta * l.unit_cost), 2) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_out' and l.unit_cost is not null) / nullif(t.qty, 0) * (t.qty - t.received_qty) end)
        order by t.received_at)
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status = 'received' and t.received_qty < t.qty and (p_loc is null or t.to_location_id = p_loc or t.from_location_id = p_loc)
       and (own or public.can_loc(t.to_location_id) or public.can_loc(t.from_location_id))
       and not exists (select 1 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transit_loss')), '[]'::jsonb);
end $$;

-- book an older short receipt as a loss now (a reason is required)
create or replace function public.transit_short_resolve(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(t.to_location_id) then raise exception 'not allowed'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_needed'; end if;
  if t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then raise exception 'not_short'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'transit_loss:' || t.id::text, t.qty - t.received_qty) then raise exception 'not allowed'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  lid := public._transit_loss83(t.id, t.qty - t.received_qty, p_note);
  if lid is null then return jsonb_build_object('id', t.id, 'dup', true); end if;
  return jsonb_build_object('id', t.id, 'ledger_id', lid, 'short', t.qty - t.received_qty);
end $$;

create or replace function public.transit_open_list(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h numeric := public.rule_num('transit_open_hours');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('limit_hours', h, 'rows', coalesce((select jsonb_agg(jsonb_build_object('transfer_id', t.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', t.qty,
        'from_location_id', t.from_location_id, 'to_location_id', t.to_location_id, 'sent_at', t.sent_at, 'hours', round((extract(epoch from now() - t.sent_at) / 3600)::numeric, 1),
        'over_limit', h is not null and t.sent_at < now() - make_interval(secs => (h * 3600)::double precision)) order by t.sent_at)
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status = 'sent' and (p_loc is null or t.to_location_id = p_loc or t.from_location_id = p_loc)
       and (public.is_owner() or public.can_loc(t.to_location_id) or public.can_loc(t.from_location_id))), '[]'::jsonb));
end $$;

-- ============================================================
-- E8 : offline POS failed sales
-- ============================================================
-- (a) same arguments as record_sale2; the queue replay calls this one. With offline_soft_stock off it is exactly record_sale2.
create or replace function public.record_sale_offline(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text,
    p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null, p_discount_kind text default null, p_discount_input numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform set_config('bos.offline_replay', '1', true);
  r := public.record_sale2(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input);
  perform set_config('bos.offline_replay', '', true);
  return r;
end $$;

-- (b) device-reported failed cards (summary only; the full sale stays on the device and in its JSON export) so the owner board can count them
create table if not exists public.pos_failed_cards (
  client_id uuid primary key,
  location_id int not null references public.locations(id),
  total numeric, err text check (err is null or length(err) <= 300), sold_at timestamptz, lines_n int,
  status text not null default 'open' check (status in ('open', 'resent', 'discarded')),
  reported_by uuid, reported_staff text, reported_at timestamptz not null default now(),
  closed_by uuid, closed_at timestamptz, close_note text check (close_note is null or length(close_note) <= 300)
);
create index if not exists pos_failed_open on public.pos_failed_cards (location_id) where status = 'open';
drop trigger if exists audit_pos_failed_cards on public.pos_failed_cards;
create trigger audit_pos_failed_cards after insert or update on public.pos_failed_cards for each row execute function public.log_change('client_id');
create or replace function public._pf83_nodel() returns trigger language plpgsql as $$ begin raise exception 'append_only: this trail cannot be deleted'; end $$;
drop trigger if exists pos_failed_nodel on public.pos_failed_cards;
create trigger pos_failed_nodel before delete on public.pos_failed_cards for each row execute function public._pf83_nodel();

create table if not exists public.pos_replay_log (
  id bigint generated always as identity primary key,
  client_id uuid not null, location_id int not null, reason text not null check (length(reason) between 3 and 300), refused_with text,
  sale_id uuid, result text not null check (result in ('sold', 'dup')),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create or replace function public._pf83_ro() returns trigger language plpgsql as $$ begin raise exception 'append_only: the override trail cannot be changed or deleted'; end $$;
drop trigger if exists pos_replay_log_ro on public.pos_replay_log;
create trigger pos_replay_log_ro before update or delete on public.pos_replay_log for each row execute function public._pf83_ro();

do $$ declare t text; begin
  foreach t in array array['pos_failed_cards', 'pos_replay_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
create policy pos_failed_cards_sel on public.pos_failed_cards for select to authenticated
  using (public.is_owner() or reported_by = auth.uid() or (public.can_loc(location_id) and public.has_grant('pos_replay_override', location_id)));
create policy pos_replay_log_sel on public.pos_replay_log for select to authenticated
  using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('pos_replay_override', location_id)));

-- p_items: [{client_id, loc, total, err, sold_at, lines_n}] ; idempotent per client_id
create or replace function public.pos_failed_note(p_items jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0; sid text; cid uuid; loc int;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for x in select * from jsonb_array_elements(p_items) loop
    begin cid := (x ->> 'client_id')::uuid; loc := (x ->> 'loc')::int; exception when others then continue; end;
    continue when cid is null or loc is null or not public.can_loc(loc);
    insert into public.pos_failed_cards (client_id, location_id, total, err, sold_at, lines_n, status, reported_by, reported_staff)
      values (cid, loc, nullif(x ->> 'total', '')::numeric, left(x ->> 'err', 300), nullif(x ->> 'sold_at', '')::timestamptz, nullif(x ->> 'lines_n', '')::int,
              case when exists (select 1 from public.sales s where s.client_id = cid) then 'resent' else 'open' end, auth.uid(), sid)
      on conflict (client_id) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

create or replace function public.pos_failed_close(p_client uuid, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.pos_failed_cards;
begin
  select * into c from public.pos_failed_cards where client_id = p_client for update;
  if not found then return jsonb_build_object('client_id', p_client, 'noop', true); end if;
  if p_status not in ('resent', 'discarded') then raise exception 'bad_status'; end if;
  if not (public.is_owner() or c.reported_by = auth.uid() or (public.can_loc(c.location_id) and public.has_grant('pos_replay_override', c.location_id))) then raise exception 'not allowed'; end if;
  if c.status <> 'open' then return jsonb_build_object('client_id', p_client, 'status', c.status, 'noop', true); end if;
  update public.pos_failed_cards set status = p_status, closed_by = auth.uid(), closed_at = now(), close_note = left(btrim(p_note), 300) where client_id = p_client;
  return jsonb_build_object('client_id', p_client, 'status', p_status);
end $$;

-- the owner-board count: open failed cards per place (a card whose sale now exists is closed first)
create or replace function public.pos_failed_board() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  update public.pos_failed_cards c set status = 'resent', closed_at = now(), close_note = 'sale found'
   where c.status = 'open' and exists (select 1 from public.sales s where s.client_id = c.client_id);
  return jsonb_build_object('open', (select count(*) from public.pos_failed_cards c where c.status = 'open' and (public.is_owner() or public.can_loc(c.location_id))),
    'by_location', coalesce((select jsonb_agg(jsonb_build_object('location_id', z.location_id, 'n', z.n, 'total', z.t) order by z.location_id)
        from (select c.location_id, count(*) n, coalesce(sum(c.total), 0) t from public.pos_failed_cards c where c.status = 'open' and (public.is_owner() or public.can_loc(c.location_id)) group by 1) z), '[]'::jsonb));
end $$;

-- (c) manager override: send the refused sale again with its ORIGINAL client_id (so it can never become a second sale). Reason required.
-- Stock being short is the thing it overrides (the goods are already with the customer); every other rule (closed period, credit limit, customer rules) still applies and its error is returned.
create or replace function public.pos_replay_override(p_payload jsonb, p_reason text, p_err text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid uuid; loc int; r jsonb; sid text; s public.sales; res text := 'sold';
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'bad_payload'; end if;
  begin cid := (p_payload ->> 'p_client')::uuid; loc := (p_payload ->> 'p_loc')::int; exception when others then raise exception 'bad_payload'; end;
  if cid is null or loc is null then raise exception 'bad_payload'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_needed'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed'; end if;
  if not public.has_grant('pos_replay_override', loc) then raise exception 'replay_override_needs_approval'; end if;
  select * into s from public.sales where client_id = cid;
  if found then
    update public.pos_failed_cards set status = 'resent', closed_by = auth.uid(), closed_at = now(), close_note = 'already recorded' where client_id = cid and status = 'open';
    return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true);
  end if;
  perform set_config('bos.offline_replay', '1', true);
  perform set_config('bos.replay_override', '1', true);
  r := public.record_sale2(cid, loc, p_payload -> 'p_lines', coalesce(nullif(p_payload ->> 'p_discount', '')::numeric, 0), p_payload -> 'p_payments',
         nullif(p_payload ->> 'p_customer_mobile', ''), nullif(p_payload ->> 'p_customer_name', ''), coalesce(nullif(p_payload ->> 'p_sale_type', ''), 'retail'),
         left('manager override: ' || btrim(p_reason) || coalesce(' | ' || nullif(p_payload ->> 'p_note', ''), ''), 200), coalesce((p_payload ->> 'p_quick')::boolean, false),
         nullif(p_payload ->> 'p_sold_at', '')::timestamptz, nullif(p_payload ->> 'p_discount_kind', ''), nullif(p_payload ->> 'p_discount_input', '')::numeric);
  perform set_config('bos.offline_replay', '', true);
  perform set_config('bos.replay_override', '', true);
  select staff_id into sid from public.profiles where id = auth.uid();
  if (r ->> 'dup')::boolean is true then res := 'dup'; end if;
  insert into public.pos_replay_log (client_id, location_id, reason, refused_with, sale_id, result, by_user, by_staff)
    values (cid, loc, left(btrim(p_reason), 300), left(p_err, 300), (r ->> 'id')::uuid, res, auth.uid(), sid);
  if res = 'sold' then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, (r ->> 'id')::uuid, 'POS', loc, (now() at time zone 'Asia/Dhaka')::date, 'pos_replay_override', 'yellow', (r ->> 'total')::numeric,
        jsonb_build_object('bn', 'রসিদ ' || (r ->> 'receipt') || ': refused sale manager override-এ আবার পাঠানো হয়েছে — ' || left(btrim(p_reason), 120),
                           'en', 'Receipt ' || (r ->> 'receipt') || ': a refused sale was re-sent on manager override - ' || left(btrim(p_reason), 120)));
  end if;
  update public.pos_failed_cards set status = 'resent', closed_by = auth.uid(), closed_at = now(), close_note = 'manager override' where client_id = cid and status = 'open';
  return r;
end $$;

-- ---------- privileges ----------
revoke all on function public._transit_loss83(uuid, numeric, text), public._transit_open_scan83(), public._expense_cover83(uuid) from public, anon, authenticated;
revoke all on function public.unmatched_forms(date, date, int), public.unmatched_forms_sync(), public.form_guard_recommendations(), public.suggest_expense_link(uuid), public.expense_link_apply(uuid, text),
  public.transit_short_open(int), public.transit_short_resolve(uuid, text), public.transit_open_list(int),
  public.record_sale_offline(uuid, integer, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric),
  public.pos_failed_note(jsonb), public.pos_failed_close(uuid, text, text), public.pos_failed_board(), public.pos_replay_override(jsonb, text, text),
  public._pf83_nodel(), public._pf83_ro() from public, anon;
grant execute on function public.unmatched_forms(date, date, int), public.unmatched_forms_sync(), public.form_guard_recommendations(), public.suggest_expense_link(uuid), public.expense_link_apply(uuid, text),
  public.transit_short_open(int), public.transit_short_resolve(uuid, text), public.transit_open_list(int),
  public.record_sale_offline(uuid, integer, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric),
  public.pos_failed_note(jsonb), public.pos_failed_close(uuid, text, text), public.pos_failed_board(), public.pos_replay_override(jsonb, text, text) to authenticated;
revoke all on function public._pf83_nodel(), public._pf83_ro() from authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase510.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase84.sql there and is already pasted on the live database under that name.
-- Renumbered to phase510.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 510 (bos84) - STEP F: audit trail for the stock cache, batches, transfers, purchase lines, production void; reconcile fixes are logged.
--   Needs phase8 ... phase78 (phase72 is another branch and is NOT needed). Additive; paste-twice safe. No amount / threshold is hard-coded. Old phases are NOT edited.
--   1. stock_balance : (a) BEFORE DELETE refused (nothing is deleted) - only an EMPTY phantom row (qty 0, no cost, no ledger row at all) may go;
--                      (b) BEFORE UPDATE refuses a change of item_id / location_id (identity);
--                      (c) AFTER UPDATE audit_log row (who / when / old / new) for qty and avg_cost, EXCEPT the updates that come from a ledger insert
--                          (stock_post -> _ledger_to_balance, trigger depth > 1): those are fully derivable from the immutable ledger, so logging them would only
--                          slow every sale. Everything else (a SECURITY DEFINER function, the SQL editor, service_role) IS logged.
--   2. stock_batches : BEFORE DELETE refused; BEFORE UPDATE refuses a change of item_id / location_id / qty_made / made_at (identity, never edited by any code);
--                      AFTER UPDATE audit row for every other change (qty_remaining by stock_post, expires_at, note, batch_no ...).
--   3. stock_transfers : BEFORE DELETE refused (insert / update were already audited since phase10).
--   4. purchase_lines : BEFORE DELETE refused unless the bill is still a DRAFT (save_purchase replaces the lines of a draft); on a posted / void bill the
--                      identity + amounts (bill_id, line_no, item_id, qty, unit_cost, amount) cannot be changed. base_qty / unit_cost_base (set at posting) stay writable.
--   5. stock_wastage : already immutable since phase10 (stock_wastage_no_update refuses UPDATE and DELETE) - nothing to add, tested here.
--   6. production_runs : AFTER UPDATE audit, only when status / void_by / void_at / void_note change (the void). The normal post-time update of ledger_in_id etc. is not logged.
--   7. stock_reconcile(true) : writes ONE audit_log row per balance it corrects (action 'reconcile_fix', old + new qty / avg_cost, who). Only this function is re-created (-- bos84).
--   Not covered (cannot be tested here): service_role / direct-DB. Triggers do fire for them, but only a real Supabase project can prove it. See step_F_REPORT.md.
-- ============================================================

-- ---------- one audit function (same row shape as log_change; skip switches) ----------
-- tg_argv[0] = id columns (comma list); tg_argv[1] = '' | 'nested' (nested = skip when fired from inside another trigger, i.e. the ledger insert);
-- tg_argv[2] = optional comma list of columns to watch (default all). set_config('bos.audit_skip84','1',true) silences it (reconcile writes its own row).
create or replace function public._aud84() returns trigger language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}'; cols text[] := string_to_array(tg_argv[0], ','); c text; rid text := ''; sid text;
  watch text[] := case when coalesce(tg_argv[2], '') = '' then null else string_to_array(tg_argv[2], ',') end;
begin
  if coalesce(tg_argv[1], '') = 'nested' and pg_trigger_depth() > 1 then return new; end if;
  if coalesce(current_setting('bos.audit_skip84', true), '') = '1' then return new; end if;
  o := to_jsonb(old); n := to_jsonb(new);
  foreach c in array cols loop rid := rid || case when rid = '' then '' else ':' end || coalesce(n->>c, ''); end loop;
  for k in select jsonb_object_keys(n) loop
    if watch is not null and not (k = any (watch)) then continue; end if;
    if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
  end loop;
  if newd = '{}'::jsonb then return new; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'update', tg_table_name, rid,
            jsonb_build_object('old', oldd, 'new', newd, 'db_user', session_user, 'src', 'phase84'));
  return new;
end $$;
revoke all on function public._aud84() from public, anon, authenticated;

-- ---------- identity guards ----------
create or replace function public._sb_guard84() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.qty = 0 and old.avg_cost is null and not exists (select 1 from public.stock_ledger l where l.item_id = old.item_id and l.location_id = old.location_id) then
      return old;                                                                  -- an empty phantom row (never had a movement) may go
    end if;
    raise exception 'nothing is deleted – retire instead' using hint = 'stock_balance is the cache of the ledger; fix it with stock_reconcile';
  end if;
  if new.item_id is distinct from old.item_id or new.location_id is distinct from old.location_id then
    raise exception 'identity_immutable' using hint = 'stock_balance item / place cannot be changed';
  end if;
  return new;
end $$;
revoke all on function public._sb_guard84() from public, anon, authenticated;

create or replace function public._batch_guard84() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire instead' using hint = 'a batch is closed by qty_remaining = 0'; end if;
  if new.item_id is distinct from old.item_id or new.location_id is distinct from old.location_id
     or new.qty_made is distinct from old.qty_made or new.made_at is distinct from old.made_at then
    raise exception 'identity_immutable' using hint = 'batch item / place / quantity made / date made cannot be changed';
  end if;
  return new;
end $$;
revoke all on function public._batch_guard84() from public, anon, authenticated;

create or replace function public._pl_guard84() returns trigger language plpgsql set search_path = public as $$
declare st text;
begin
  select status into st from public.purchase_bills where id = coalesce(old.bill_id, new.bill_id);
  if tg_op = 'DELETE' then
    if st = 'draft' then return old; end if;                                      -- save_purchase replaces the lines of a draft
    raise exception 'nothing is deleted – retire instead' using hint = 'lines of a posted / void bill stay; void the bill';
  end if;
  if st is distinct from 'draft' and (new.bill_id is distinct from old.bill_id or new.line_no is distinct from old.line_no or new.item_id is distinct from old.item_id
        or new.qty is distinct from old.qty or new.unit_cost is distinct from old.unit_cost or new.amount is distinct from old.amount) then
    raise exception 'identity_immutable' using hint = 'lines of a posted / void bill cannot be edited';
  end if;
  return new;
end $$;
revoke all on function public._pl_guard84() from public, anon, authenticated;

-- ---------- triggers ----------
drop trigger if exists stock_balance_guard84 on public.stock_balance;
create trigger stock_balance_guard84 before update or delete on public.stock_balance for each row execute function public._sb_guard84();
drop trigger if exists audit_stock_balance84 on public.stock_balance;
create trigger audit_stock_balance84 after update on public.stock_balance for each row
  when (old.qty is distinct from new.qty or old.avg_cost is distinct from new.avg_cost)
  execute function public._aud84('item_id,location_id', 'nested', 'qty,avg_cost');

drop trigger if exists stock_batches_guard84 on public.stock_batches;
create trigger stock_batches_guard84 before update or delete on public.stock_batches for each row execute function public._batch_guard84();
drop trigger if exists audit_stock_batches84 on public.stock_batches;
create trigger audit_stock_batches84 after update on public.stock_batches for each row execute function public._aud84('id', '', '');

drop trigger if exists stock_transfers_no_delete84 on public.stock_transfers;
create trigger stock_transfers_no_delete84 before delete on public.stock_transfers for each row execute function public.no_hard_delete();

drop trigger if exists purchase_lines_guard84 on public.purchase_lines;
create trigger purchase_lines_guard84 before update or delete on public.purchase_lines for each row execute function public._pl_guard84();

drop trigger if exists audit_production_runs_void84 on public.production_runs;
create trigger audit_production_runs_void84 after update on public.production_runs for each row
  when (old.status is distinct from new.status or old.void_by is distinct from new.void_by or old.void_at is distinct from new.void_at or old.void_note is distinct from new.void_note)
  execute function public._aud84('id', '', 'status,void_by,void_at,void_note');

-- ---------- stock_reconcile: latest definition (phase10) + audit row per fixed balance ----------
create or replace function public.stock_reconcile(p_fix boolean default false)
 returns table(item_id uuid, location_id integer, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric;
        sid text;                                                                                            -- bos84
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in
    select k.iid, k.lid from (select x.item_id iid, x.location_id lid from public.stock_ledger x group by 1, 2
                              union select y.item_id, y.location_id from public.stock_balance y) k order by 1, 2 loop
    if p_fix then
      insert into public.stock_balance (item_id, location_id) values (r.iid, r.lid) on conflict do nothing;
      perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update;     -- nobody can post to this pair until we are done
    end if;
    select z.qty, z.avg_cost into bq, bavg from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid;
    bq := coalesce(bq, 0);
    q := 0; a := null;
    for l in select x.qty_delta, x.unit_cost, x.reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if q <> bq or bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := q; cached_qty := bq; qty_diff := bq - q; cached_avg := bavg; replay_avg := a;
      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;
      return next;
    end if;
  end loop;
end $function$;

-- ---------------------------------------------------------------- phase511.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase85.sql there and is already pasted on the live database under that name.
-- Renumbered to phase511.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- Phase 511 (Phase D of the audit fixes): stock movements that missed the books, manual-journal guard, autopost scheduler, card settlement, expense payment mode.
-- Additive, paste-twice safe. Paste AFTER phase79 (it re-creates functions from their LATEST definition, phase79 bodies included). Every new switch defaults to today's behaviour:
-- with all of them at their default nothing new is posted and no existing report changes.
--
--   D1 STOCK MOVES   _acct_docs gets one entry per stock-ledger row (source_id = ledger id, so je_source_uq keeps it once) for
--                      count adjustment  (rule acct_count_adjust)       Dr/Cr stock_adjust (5110)          against the inventory account of the item type
--                      opening stock     (rule acct_stock_opening)      Dr inventory / Cr stock_opening_equity (owner capital 3100 by default)
--                      own-use issue     (rule acct_issue_out)          Dr stock_issue_use (5120) / Cr inventory   (stock_issue and 04-2 form lines)
--                      transfers         (rule acct_transfer_mode: off | location_tagged | company_wide)
--                                        location_tagged = a pair of entries, each tagged with its own place and each balanced alone, through the inter-location clearing account
--                                        (interloc_clearing = 1230); company_wide = the owner decided the books are company-wide, nothing is posted for the pair
--                      short receipt     (rule acct_transit_loss + acct_transit_loss_at sender|receiver) Dr transit_loss (5130) / Cr clearing (location_tagged) or inventory
--                      purchase return   (rule acct_purchase_variance)  stock left at average cost, the supplier credit was at bill price: the difference goes to purchase_variance (5140)
--                    A reversal row of the stock ledger (entry revised / transfer cancelled) is posted as the mirror entry. A row without a known cost is NOT posted: it waits
--                    as cost_missing (nothing is invented). Optional rule acct_stock_moves_from (date): older rows are left out.
--                    stock_count_adjust (screen) records a gain at the current average cost when acct_count_adjust is on, so the gain has a known cost (average does not move).
--                    inventory_vs_gl: the reasons now count the new entries, so a posted movement is no longer "unexplained".
--   D4 GUARD         rule manual_journal_guard (off | on). on: a manual journal that touches an inventory / COGS / sales / payable / receivable / stock-adjust account needs a reason code
--                    (table manual_reason_codes85, owner can add) and payable / receivable lines need a party. acct_journal_post gets an optional p_reason.
--   D5 SCHEDULER     acct_autopost_tick() = the same posting as acct_post_pending, callable without a signed-in person by a scheduler (pg_cron / edge schedule) when the rule
--                    acct_scheduler_on is on; each run is kept in acct_autopost_runs85. acct_scheduler_enable(cron) / acct_scheduler_disable() schedule it through pg_cron WHEN the
--                    extension exists. acct_pending_alert85(): documents waiting longer than the alert days and the list of period-locked documents. Locks are respected.
--   D6 CARD / EXPENSE card_settle(...) books a card settlement (Dr bank, Dr bank charges, Cr card receivable) from numbers the person types; card_settle_void; card_settlement_list.
--                    The 10-2 expense voucher credits the account of data.pay_mode (cash | bank | mobile | card -> bank); no value = cash as before.
-- Tag: bos85 marks every changed line inside a re-created function.

-- ---------- guard ----------
do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public.production_post(integer, uuid, numeric, uuid, timestamp with time zone, text, numeric)') is null then
    raise exception 'phase511 needs phases 72..79 pasted first';
  end if;
  if position('bos72' in pg_get_functiondef('public.production_post(integer, uuid, numeric, uuid, timestamp with time zone, text, numeric)'::regprocedure)) = 0
     or position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0
     or position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase511 needs phase79 pasted (final merged function bodies)';
  end if;
end $g$;

-- ---------- rules (all default = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('acct_count_adjust', 'books', 'switch', 'false', null, null, null,
  'Stock গণনার পার্থক্য journal এ তোলা (stock gain / loss)', 'Stock count এর difference journal এ post করা', 'Post stock count differences to the books (stock gain / loss)',
  'বন্ধ থাকলে আগের মতোই: গণনার পার্থক্য শুধু stock এ যায়, হিসাবের খাতায় নয়।', 'Off = as before: a count difference changes the stock only, not the books. On = one entry per count adjustment against the stock gain / loss account.', 950),
 ('acct_stock_opening', 'books', 'switch', 'false', null, null, null,
  'Opening stock journal এ তোলা (owner capital এর বিপরীতে)', 'Opening stock journal এ post করা (owner capital এর against এ)', 'Post opening stock to the books (against owner capital)',
  'শুধু হিসাব শুরুর তারিখ বা তার পরের opening ধরা হয়। শুরুর জের (acct_opening) এ stock আগেই দিলে এটি চালাবেন না, নইলে দুইবার গোনা হবে।', 'Only openings dated on or after the accounting start are posted. If the stock is already inside the opening balance (acct_opening) leave this off, it would count twice.', 951),
 ('acct_issue_out', 'books', 'switch', 'false', null, null, null,
  'নিজের কাজে stock issue journal এ তোলা', 'Own-use stock issue journal এ post করা', 'Post own-use stock issues to the books',
  'বন্ধ থাকলে আগের মতোই: issue শুধু stock কমায়, খরচ হিসাবে আসে না।', 'Off = as before: an issue lowers the stock only. On = Dr stock issued for own use / Cr inventory at the ledger cost.', 952),
 ('acct_transfer_mode', 'books', 'choice', '"off"', '["off","location_tagged","company_wide"]', null, null,
  'Stock transfer এর হিসাব: বন্ধ / স্থানভিত্তিক জোড়া / পুরো কোম্পানি', 'Stock transfer এর accounting: off / location-tagged pair / company-wide', 'Stock transfer accounting: off, location-tagged pair, or company-wide',
  'স্থানভিত্তিক জোড়া = পাঠানো ও গ্রহণ আলাদা entry, প্রতিটি নিজের স্থানের ট্যাগসহ, মাঝখানে inter-location clearing। পুরো কোম্পানি = balance sheet শুধু কোম্পানি-ব্যাপী, জোড়া আলাদা করে তোলা হবে না।', 'location_tagged = a send entry and a receive entry, each tagged with its own place, through the inter-location clearing account. company_wide = the books are company-wide only, the pair is not posted. off = as before.', 953),
 ('acct_transit_loss', 'books', 'switch', 'false', null, null, null,
  'পথে কম পৌঁছানো মাল (transit loss) journal এ তোলা', 'Transit এ কম পৌঁছানো stock journal এ post করা', 'Post stock short in transit to the books',
  'Transfer গ্রহণের সময় কম পেলে কমতির খরচ transit loss খাতে যায়।', 'When a transfer is received short, the missing cost goes to the transit loss account.', 954),
 ('acct_transit_loss_at', 'books', 'choice', '"receiver"', '["receiver","sender"]', null, null,
  'Transit loss কোন স্থানের খরচ: গ্রহণকারী / প্রেরক', 'Transit loss কোন place এর cost: receiver / sender', 'Which place carries a transit loss: receiver or sender',
  null, 'Used only when transit loss posting is on.', 955),
 ('acct_purchase_variance', 'books', 'switch', 'false', null, null, null,
  'Purchase return এর দামের পার্থক্য journal এ তোলা', 'Purchase return এর price variance journal এ post করা', 'Post the price variance of purchase returns to the books',
  'Return এ stock গড় খরচে বের হয়, সরবরাহকারীর credit বিলের দামে; পার্থক্য purchase variance খাতে যায়।', 'A return takes the stock out at average cost while the supplier credit is at bill price. On = the difference goes to the purchase variance account.', 956),
 ('acct_stock_moves_from', 'books', 'text', '""', null, null, null,
  'Stock movement journal এর শুরুর তারিখ (ফাঁকা = হিসাব শুরু থেকে)', 'Stock movement journal এর start date (ফাঁকা = accounting start থেকে)', 'Stock movement posting from this date (blank = from the accounting start)',
  'YYYY-MM-DD। এর আগের তারিখের movement আর তোলা হবে না।', 'Format YYYY-MM-DD. Older stock movements are left out.', 957),
 ('manual_journal_guard', 'books', 'choice', '"off"', '["off","on"]', null, null,
  'হাতে লেখা journal এর পাহারা: বন্ধ / চালু', 'Manual journal guard: off / on', 'Manual journal guard: off or on',
  'চালু হলে inventory, COGS, sales, payable, receivable ইত্যাদি খাতে হাতে লিখতে কারণ-কোড লাগবে, আর payable / receivable লাইনে party লাগবে।', 'On = a manual journal on an inventory, COGS, sales, payable, receivable or stock-adjust account needs a reason code, and payable / receivable lines need a party.', 958),
 ('acct_scheduler_on', 'books', 'switch', 'false', null, null, null,
  'নির্ধারিত সময়ে নিজে নিজে posting (scheduler)', 'Scheduled auto posting (scheduler)', 'Scheduled auto posting (scheduler)',
  'চালু হলে scheduler acct_autopost_tick() ডাকলে বাকি document গুলো journal এ উঠবে। scheduler চালু করা server এর কাজ।', 'On = a scheduler calling acct_autopost_tick() posts the waiting documents. Starting the scheduler itself is a server setup.', 959),
 ('acct_pending_alert_days', 'books', 'number', '1', null, 0, 365, 
  'কত দিনের বেশি পুরোনো বাকি document এ সতর্কতা', 'কত দিনের বেশি পুরোনো pending document এ alert', 'Alert for documents waiting longer than this many days',
  null, 'A document dated before (today minus this many days) that is still not in the books is counted as waiting too long.', 960)
on conflict (key) do nothing;

-- ---------- accounts and mapping keys (additive; the owner may re-point any key with acct_mapping_set) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort) values
 ('5110', 'স্টক গণনার লাভ / ক্ষতি', 'Stock count gain / loss', 'expense', 'debit', false, true, 4110),
 ('5120', 'নিজের কাজে stock issue', 'Stock issued for own use', 'expense', 'debit', false, true, 4120),
 ('5130', 'পথে কম পৌঁছানো মাল (transit loss)', 'Stock short in transit', 'expense', 'debit', false, true, 4130),
 ('5140', 'ক্রয় ফেরতের দামের পার্থক্য', 'Purchase price variance', 'expense', 'debit', false, true, 4140)
on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select v.k, a.id, v.bn, v.en from (values
    ('stock_adjust', '5110', 'স্টক গণনার লাভ / ক্ষতি', 'Stock count gain / loss'),
    ('stock_issue_use', '5120', 'নিজের কাজে stock issue', 'Stock issued for own use'),
    ('transit_loss', '5130', 'পথে কম পৌঁছানো মাল', 'Stock short in transit'),
    ('purchase_variance', '5140', 'ক্রয় ফেরতের দামের পার্থক্য', 'Purchase price variance'),
    ('stock_opening_equity', '3100', 'Opening stock এর বিপরীত (owner capital)', 'Opening stock counterpart (owner capital)'),
    ('interloc_clearing', '1230', 'স্থানান্তরের inter-location clearing', 'Inter-location clearing for transfers'),
    ('bank_charges', '5810', 'ব্যাংক / কার্ড চার্জ', 'Bank / card charges')) v(k, code, bn, en)
  join public.coa_accounts a on a.code = v.code
  on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.acct_autopost_runs85 (
  id bigint generated always as identity primary key, ran_at timestamptz not null default now(),
  posted int not null default 0, reversed int not null default 0, errors int not null default 0, locked int not null default 0, waiting int not null default 0,
  more boolean not null default false, note text);
alter table public.acct_autopost_runs85 enable row level security;
revoke all on public.acct_autopost_runs85 from public, anon, authenticated;

create table if not exists public.manual_reason_codes85 (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,39}$'), label_bn text not null, label_mix text, label_en text not null,
  active boolean not null default true, sort int not null default 0, updated_at timestamptz not null default now(), updated_by uuid);
alter table public.manual_reason_codes85 enable row level security;
revoke all on public.manual_reason_codes85 from public, anon, authenticated;
grant select on public.manual_reason_codes85 to authenticated;
drop policy if exists manual_reason_codes85_sel on public.manual_reason_codes85;
create policy manual_reason_codes85_sel on public.manual_reason_codes85 for select to authenticated using (public._acct_view());
insert into public.manual_reason_codes85 (code, label_bn, label_mix, label_en, sort) values
 ('correction', 'আগের entry সংশোধন', 'আগের entry এর correction', 'Correction of an earlier entry', 10),
 ('reclass', 'অন্য খাতে সরানো', 'অন্য account এ reclass', 'Moved to another account', 20),
 ('audit_adjust', 'অডিটরের সমন্বয়', 'Auditor এর adjustment', 'Auditor adjustment', 30),
 ('other', 'অন্য কারণ (note এ লিখুন)', 'অন্য reason (memo তে লিখুন)', 'Other reason (write it in the memo)', 90)
on conflict (code) do nothing;
drop trigger if exists audit_manual_reason_codes85 on public.manual_reason_codes85;
create trigger audit_manual_reason_codes85 after insert or update on public.manual_reason_codes85 for each row execute function public.log_change('code');

create table if not exists public.card_settlements85 (
  id uuid primary key default gen_random_uuid(), client_id uuid unique, location_id int not null references public.locations(id),
  settle_date date not null, gross numeric(14,2) not null check (gross > 0), fee numeric(14,2) not null default 0 check (fee >= 0 and fee < gross),
  bank_mode text not null default 'bank' check (bank_mode in ('bank', 'mobile')), note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_note text);
create index if not exists card_settlements85_loc on public.card_settlements85 (location_id, settle_date);
alter table public.card_settlements85 enable row level security;
revoke all on public.card_settlements85 from public, anon, authenticated;
grant select on public.card_settlements85 to authenticated;
drop policy if exists card_settlements85_sel on public.card_settlements85;
create policy card_settlements85_sel on public.card_settlements85 for select to authenticated using (public._acct_view() and public.can_loc(location_id));
create or replace function public._card_settle_ro85() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.status = 'done' and new.status = 'void' and (to_jsonb(new) - 'status' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'status' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: a card settlement cannot be changed or deleted (void it)';
end $$;
drop trigger if exists card_settle_ro85 on public.card_settlements85;
create trigger card_settle_ro85 before update or delete on public.card_settlements85 for each row execute function public._card_settle_ro85();
drop trigger if exists audit_card_settlements85 on public.card_settlements85;
create trigger audit_card_settlements85 after insert or update on public.card_settlements85 for each row execute function public.log_change('id');

-- ---------- helpers ----------
create or replace function public._acct_from85() returns date language plpgsql stable security definer set search_path = public as $$
declare v text := public.rule_txt('acct_stock_moves_from');
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  begin return v::date; exception when others then return null; end;
end $$;

-- one row per stock-ledger row that belongs to a movement the books did not have; only the movements whose rule is on
create or replace function public._acct_stock_moves85(p_start date)
returns table(lid bigint, cls text, d date, loc int, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
language sql stable security definer set search_path = public as $$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer' end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal')
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$$;

-- purchase return: stock left at ledger cost, supplier credit was at bill price (per inventory account); the lines that fix the books
create or replace function public._pvar85(p_bill uuid)
returns table(nulls int, nonzero boolean, lines jsonb) language sql stable security definer set search_path = public as $$
  with lo as (select public._acct_buy_key(it.item_type) k, sum(round(-l.qty_delta * coalesce(l.unit_cost, 0), 2)) a, count(*) filter (where coalesce(l.unit_cost, 0) = 0) n
                from public.stock_ledger l join public.items it on it.id = l.item_id
               where l.ref_type = 'purchase' and l.reason = 'purchase_return' and l.ref_id = p_bill::text and public._acct_buy_key(it.item_type) in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       jc as (select al.k, sum(al.amt) a from public._acct_purchase_alloc(p_bill) al where al.k in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       dd as (select coalesce(lo.k, jc.k) k, round(coalesce(lo.a, 0) - coalesce(jc.a, 0), 2) df from lo full join jc on jc.k = lo.k),
       nz as (select * from dd where df <> 0),
       tot as (select coalesce(sum(df), 0) net from nz)
  select coalesce((select sum(n) from lo), 0)::int, exists (select 1 from nz),
         (select jsonb_agg(j) from (
            select jsonb_build_object('a', k, case when df > 0 then 'c' else 'd' end, abs(df)) j from nz
            union all select jsonb_build_object('a', 'purchase_variance', case when net > 0 then 'd' else 'c' end, abs(net)) from tot where net <> 0) x);
$$;

-- reserved accounts for the manual-journal guard (mapping keys) and the check itself
create or replace function public._manual_guard_keys85() returns text[] language sql immutable as $$
  select array['inv_finished', 'inv_raw', 'inv_pack', 'cogs', 'sales', 'sales_returns', 'sales_discount', 'payable', 'receivable', 'wastage', 'stock_adjust', 'stock_issue_use', 'transit_loss',
               'purchase_variance', 'overhead_absorbed']::text[];
$$;
create or replace function public._manual_guard85(p_lines jsonb, p_reason text) returns void language plpgsql stable security definer set search_path = public as $$
declare res bigint[]; par bigint[]; x jsonb; touched boolean := false; aid bigint;
begin
  res := array(select account_id from public.acct_mappings where key = any (public._manual_guard_keys85()));
  par := array(select account_id from public.acct_mappings where key in ('payable', 'receivable'));
  for x in select * from jsonb_array_elements(p_lines) loop
    aid := (x->>'account_id')::bigint;
    if aid = any (res) then touched := true; end if;
    if aid = any (par) and (nullif(x->>'party_type', '') is null or nullif(x->>'party_id', '') is null) then raise exception 'party_required'; end if;
  end loop;
  if touched then
    if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
    if not exists (select 1 from public.manual_reason_codes85 c where c.code = p_reason and c.active) then raise exception 'bad_reason'; end if;
  end if;
end $$;


-- ---------- re-created functions (latest definitions = phase79 bodies; changed lines carry bos85) ----------

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._acct_paykey(v.pm, true) /* bos85 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' else 'Stock transfer' end) || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' else 'stock_transfer' end)::text st) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');
end $function$
;

CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]';
begin
  if not (public._acct_manage() or (auth.uid() is null and coalesce(current_setting('bos.autopost85', true), '') = 'on')) then raise exception 'not allowed'; end if;   -- bos85: the scheduler entry point has no signed-in person
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;   -- bos72: solved
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      if not p_dry then   -- bos72: keep the failure so the status strip and the accounts page can show it (the browser used to drop it)
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped);
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$
;

CREATE OR REPLACE FUNCTION public.stock_count_adjust(p_item uuid, p_loc integer, p_counted numeric, p_note text, p_unit text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; bal public.stock_balance; d numeric; lid bigint; tol numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_count_adjust', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'count_adjust' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_counted is null or not (p_counted between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  bq := public._base_qty(p_item, p_counted, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_count_adjust', p_loc, 'count:' || p_item::text) then raise exception 'not allowed'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;
  d := round(bq - bal.qty, 4);
  if d = 0 then return jsonb_build_object('ledger_id', null, 'delta', 0, 'qty', bal.qty); end if;
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, case when d > 0 and public.rule_on('acct_count_adjust') then bal.avg_cost end /* bos85: a gain is recorded at the average cost so it has a known cost; the average does not move */, null, now(), left(p_note, 200), null, 'none', null, p_client);
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $function$
;

CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null then
    if not public._acct_all() or exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  elsif not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  basis := case when d >= t then 'average_cost' else 'ledger_replay' end;
  foreach k in array array['inv_finished', 'inv_raw', 'inv_pack'] loop
    select m.account_id, a.code, a.name_bn, a.name_en into acct, acode, anbn, anen from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
    if acct is null then continue; end if;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(x.v), 0) as lv_all, coalesce(sum(x.v) filter (where x.cib), 0) as lv_cib,
           coalesce(sum(x.v) filter (where x.reason = 'count_adjust'), 0) as g_count,
           coalesce(sum(x.v) filter (where x.reason = 'opening'), 0) as g_opening,
           coalesce(sum(x.v) filter (where x.reason in ('transfer_out', 'transfer_in') or x.ref_type = 'transfer'), 0) as g_transfer,
           coalesce(sum(x.v) filter (where x.reason = 'issue_out' and x.ref_type in ('issue', 'entry')), 0) as g_issue,
           coalesce(sum(x.v) filter (where (x.reason = 'production_in' and not x.has_run) or (x.reason = 'purchase_in' and x.ref_type = 'entry') or (x.reason = 'reversal' and x.ref_type = 'entry')), 0) as g_manual_in,
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger sl join public.items it on it.id = sl.item_id
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening') /* bos85 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger sl join public.items it on it.id = sl.item_id
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in, 2)),
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret + j_var, 2)),   -- bos85
      jsonb_build_object('code', 'production_cost_missing', 'amount', round(g_prod, 2)),
      jsonb_build_object('code', 'manual_journal', 'amount', round(g_man, 2)));
    ex := df - (select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(rs) x);
    rows_ := rows_ || jsonb_build_object('key', k, 'code', acode, 'name_bn', anbn, 'name_en', anen, 'gl', round(gl, 2), 'valuation', round(v, 2), 'ledger_value', round(rw.lv_all, 2),
                'diff', df, 'reasons', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(rs) x where abs((x->>'amount')::numeric) >= 0.005), 'unexplained', round(ex, 2));
    tg := tg + gl; tv := tv + v; tx := tx + ex;
  end loop;
  ok := abs(tg - tv) < 0.05;
  return jsonb_build_object('as_of', d, 'location_id', p_loc, 'start', st, 'accounting_on', public.rule_on('accounting_on'), 'valuation_basis', basis, 'rows', rows_,
    'total', jsonb_build_object('gl', round(tg, 2), 'valuation', round(tv, 2), 'diff', round(tg - tv, 2), 'unexplained', round(tx, 2)), 'agree', ok,
    'note', 'Read only: nothing is posted. Reasons are movements the books or the stock ledger do not have; "unexplained" is what is left.');
end $function$
;

CREATE OR REPLACE FUNCTION public.acct_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); pend int := 0; lck int := 0; wt int := 0; er int := 0; erl jsonb := '[]'::jsonb;   -- bos72
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is not null then   -- bos72: documents not yet in the books (the same list acct_post_pending would work through)
    with dd as materialized (select * from public._acct_docs(st)),
    e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null),
           (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries, 'last_at', y.last_at) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, er, erl;
  end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', st,
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),
    'last_post_at', (select max(created_at) from public.journal_entries where (created_by is not null or exists (select 1 from public.acct_autopost_runs85)) and source_type not in ('manual', 'opening')),   -- bos72 bos85: a scheduler run has no person
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl,   -- bos72
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));   -- bos85
end $function$
;

drop function if exists public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean);   -- bos85: one function with the optional reason code (callers with named or fewer arguments are unaffected)
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_memo is null or length(btrim(p_memo)) < 3 then raise exception 'memo_required'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  ln := public._acct_resolve(p_lines, p_loc);
  if coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' then perform public._manual_guard85(ln, p_reason); end if;   -- bos85
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', p_date, 'total_debit', td, 'total_credit', tc, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $function$
;

-- ---------- D5: scheduler entry point, pending alert ----------
create or replace function public.acct_autopost_tick() returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; i int := 0; posted int := 0; rev int := 0; er int := 0; lk int := 0; wt int := 0; mr boolean := false;
begin
  if auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;      -- a scheduler has no signed-in person; a person must be the owner
  if auth.uid() is null and not public.rule_on('acct_scheduler_on') then return jsonb_build_object('skipped', 'scheduler_off'); end if;
  perform set_config('bos.autopost85', 'on', true);
  begin
    loop
      i := i + 1;
      r := public.acct_post_pending(false, 1500);
      if r ? 'data_needed' then insert into public.acct_autopost_runs85 (note) values ('data_needed'); perform set_config('bos.autopost85', '', true); return r; end if;
      posted := posted + coalesce((r->>'posted')::int, 0); rev := rev + coalesce((r->>'reversed')::int, 0); lk := lk + coalesce((r->>'locked')::int, 0);
      er := er + jsonb_array_length(coalesce(r->'errors', '[]'::jsonb));
      wt := (select coalesce(sum(value::int), 0) from jsonb_each_text(coalesce(r->'waiting', '{}'::jsonb)));
      mr := coalesce((r->>'more')::boolean, false);
      exit when not mr or i >= 5;
    end loop;
  exception when others then
    insert into public.acct_autopost_runs85 (note) values (left(sqlerrm, 200));
    perform set_config('bos.autopost85', '', true);
    return jsonb_build_object('error', sqlerrm);
  end;
  insert into public.acct_autopost_runs85 (posted, reversed, errors, locked, waiting, more) values (posted, rev, er, lk, wt, mr);
  perform set_config('bos.autopost85', '', true);
  return jsonb_build_object('posted', posted, 'reversed', rev, 'errors', er, 'locked', lk, 'waiting', wt, 'more', mr, 'runs', i);
end $$;

create or replace function public.acct_pending_alert85(p_limit int default 50) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); t date := public._acct_today(); days int; oc int; od date; lc int; wc int; ll jsonb; cl date; cv text := public.rule_txt('period_closed_until');
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  days := coalesce(public.rule_num('acct_pending_alert_days'), 1)::int;
  if cv ~ '^\d{4}-\d{2}-\d{2}$' then begin cl := cv::date; exception when others then cl := null; end; end if;   -- who sees the list is not asked: the owner bypasses the lock, everyone else (and the scheduler) is held by it
  with p as materialized (select d.source_type, d.source_id, case when d.live then d.entry_date else coalesce(d.void_date, t) end eff, d.memo, d.live, d.waiting from public._acct_docs(st) d)
  select count(*) filter (where waiting is null and eff < t - days), min(eff) filter (where waiting is null and eff < t - days),
         count(*) filter (where waiting is null and (cl is not null and eff <= cl)), count(*) filter (where waiting is not null),
         (select coalesce(jsonb_agg(jsonb_build_object('source_type', z.source_type, 'source_id', z.source_id, 'date', z.eff, 'memo', z.memo, 'reversal', not z.live) order by z.eff, z.source_type, z.source_id), '[]'::jsonb)
            from (select * from p where waiting is null and (cl is not null and eff <= cl) order by eff, source_type, source_id limit least(greatest(coalesce(p_limit, 50), 1), 500)) z)
    into oc, od, lc, wc, ll from p;
  return jsonb_build_object('days', days, 'old_count', oc, 'oldest', od, 'alert', oc > 0, 'locked_count', lc, 'locked', ll, 'force_by', 'owner', 'waiting_cost', wc,
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));
end $$;

-- schedule through pg_cron only when the extension exists (starting it is a server setting; nothing here installs it)
create or replace function public.acct_scheduler_enable(p_cron text) returns jsonb language plpgsql security definer set search_path = public as $$
declare jid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_cron is null or btrim(p_cron) !~ '^[0-9*/,\-]+( [0-9*/,\-]+){4}$' then raise exception 'bad_cron'; end if;
  if to_regnamespace('cron') is null then return jsonb_build_object('scheduled', false, 'reason', 'pg_cron_missing'); end if;
  execute format('select cron.schedule(%L, %L, %L)', 'bos_acct_autopost', btrim(p_cron), 'select public.acct_autopost_tick()') into jid;
  update public.rules set value = 'true'::jsonb, updated_at = now(), updated_by = auth.uid() where key = 'acct_scheduler_on';
  return jsonb_build_object('scheduled', true, 'job', jid, 'cron', btrim(p_cron));
end $$;
create or replace function public.acct_scheduler_disable() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.rules set value = 'false'::jsonb, updated_at = now(), updated_by = auth.uid() where key = 'acct_scheduler_on';
  if to_regnamespace('cron') is not null then execute format('select cron.unschedule(%L)', 'bos_acct_autopost'); end if;
  return jsonb_build_object('scheduled', false);
end $$;

-- ---------- D4: reason codes ----------
create or replace function public.manual_reason_set(p_code text, p_bn text, p_mix text, p_en text, p_active boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(p_bn), '') is null or nullif(btrim(p_en), '') is null then raise exception 'label_required'; end if;
  insert into public.manual_reason_codes85 (code, label_bn, label_mix, label_en, active, updated_by) values (p_code, btrim(p_bn), nullif(btrim(p_mix), ''), btrim(p_en), coalesce(p_active, true), auth.uid())
    on conflict (code) do update set label_bn = excluded.label_bn, label_mix = excluded.label_mix, label_en = excluded.label_en, active = excluded.active, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('code', p_code);
end $$;
create or replace function public.manual_reasons85() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'label_bn', c.label_bn, 'label_mix', c.label_mix, 'label_en', c.label_en, 'active', c.active) order by c.sort, c.code) from public.manual_reason_codes85 c), '[]'::jsonb);
end $$;

-- ---------- D6: card settlement ----------
create or replace function public.card_settle(p_loc int, p_date date, p_gross numeric, p_fee numeric default 0, p_note text default null, p_client uuid default null, p_bank_mode text default 'bank') returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.card_settlements85; sid text; t date := public._acct_today(); d date := coalesce(p_date, public._acct_today()); fee numeric := coalesce(p_fee, 0); bal numeric;
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.card_settlements85 where client_id = p_client;
    if found then
      if c.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', c.id, 'dup', true);
    end if;
  end if;
  if p_gross is null or not (p_gross > 0 and p_gross <= 1000000000000) then raise exception 'bad_amount'; end if;
  if not (fee >= 0 and fee < p_gross) then raise exception 'bad_fee'; end if;
  if coalesce(p_bank_mode, 'bank') not in ('bank', 'mobile') then raise exception 'bad_mode'; end if;
  if d > t then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  select coalesce(sum(jl.debit - jl.credit), 0) into bal from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc;
  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)
    values (p_client, p_loc, d, round(p_gross, 2), round(fee, 2), coalesce(p_bank_mode, 'bank'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid) returning * into c;
  return jsonb_build_object('id', c.id, 'unsettled', bal, 'over', round(p_gross, 2) > bal);
end $$;

create or replace function public.card_settle_void(p_id uuid, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.card_settlements85;
begin
  select * into c from public.card_settlements85 where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._acct_manage() and public.can_loc(c.location_id)) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  if c.status = 'void' then return jsonb_build_object('id', c.id, 'noop', true); end if;
  perform public.lock_check(c.settle_date);
  update public.card_settlements85 set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', c.id, 'status', 'void');
end $$;

create or replace function public.card_settlement_list(p_loc int, p_from date default null, p_to date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._acct_view() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return jsonb_build_object('location_id', p_loc,
    'unsettled', (select coalesce(sum(jl.debit - jl.credit), 0) from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'date', c.settle_date, 'gross', c.gross, 'fee', c.fee, 'net', c.gross - c.fee, 'bank_mode', c.bank_mode, 'note', c.note, 'status', c.status) order by c.settle_date desc, c.created_at desc)
                       from public.card_settlements85 c where c.location_id = p_loc and (p_from is null or c.settle_date >= p_from) and (p_to is null or c.settle_date <= p_to)), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
revoke all on function public._acct_from85(), public._acct_stock_moves85(date), public._pvar85(uuid), public._manual_guard_keys85(), public._manual_guard85(jsonb, text), public._card_settle_ro85() from public, anon, authenticated;
revoke all on function public.acct_autopost_tick(), public.acct_pending_alert85(int), public.acct_scheduler_enable(text), public.acct_scheduler_disable(), public.manual_reason_set(text, text, text, text, boolean), public.manual_reasons85(),
  public.card_settle(int, date, numeric, numeric, text, uuid, text), public.card_settle_void(uuid, text), public.card_settlement_list(int, date, date),
  public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean, text) from public, anon;
grant execute on function public.acct_autopost_tick(), public.acct_pending_alert85(int), public.acct_scheduler_enable(text), public.acct_scheduler_disable(), public.manual_reason_set(text, text, text, text, boolean), public.manual_reasons85(),
  public.card_settle(int, date, numeric, numeric, text, uuid, text), public.card_settle_void(uuid, text), public.card_settlement_list(int, date, date),
  public.acct_journal_post(date, int, text, jsonb, uuid, text, boolean, text) to authenticated;
do $s$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then grant execute on function public.acct_autopost_tick() to service_role; end if;
end $s$;

-- ---------------------------------------------------------------- phase512.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase86.sql there and is already pasted on the live database under that name.
-- Renumbered to phase512.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 512 (bos86) - Step Tg: Telegram as a sales / message channel (pull-in only, no auto-reply).
-- Run AFTER phase76 (and 77..79). Additive + idempotent (paste twice = no error). No old phase file is changed.
-- Re-created (latest definition = phase76, only bos86 lines changed): sales_channel_save, inbox_board.
--
--   Tg1 sales_channels.kind accepts 'telegram' (old check dropped and re-added in one block). A telegram channel needs an account ref (the bot's id/name, never shown to staff).
--   Tg2 telegram_message_receive(): intake into inbound_messages (same table, same inbox_list / inbox_get / inbox_set_status, same PII mask + view audit).
--       Idempotent on (channel, update_id) = (channel_id, external_id). Chat id is kept as handle 'tg:<chat_id>'. NO reply to the customer, NO order made, NO AI call.
--   Tg3 verification: Telegram sends the secret_token in header X-Telegram-Bot-Api-Secret-Token. Only its SHA-256 is stored (telegram_secrets, closed table);
--       the Edge function hashes the header and the database compares (constant time). A wrong / missing token is logged as a 'rejected' bad_signature line (no body).
--   Tg4 telegram_chat_link / telegram_chat_unlink / telegram_chat_info: link a Telegram chat to a customer and / or an order (inbox actions, audited, mask-aware).
--       An order made from a telegram message (online_order_save2 p_msg_id) links its chat automatically.
--   Tg5 intake-bot role compatibility: the receiver accepts an intake_bots user OR (if it ever exists) a user with role code 'intake_bot'. The receiver itself needs no POS permission,
--       so a role that can create orders but cannot enter POS works. Nothing here depends on that role existing.
-- Switch (default OFF): telegram_intake_on (also needs inbox_on).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('telegram_intake_on', 'pos', 'switch', 'false', null, null, null, null, 'টেলিগ্রাম বার্তা ঢোকা চালু', 'Telegram বার্তা intake চালু', 'Telegram message intake is on',
  'বাইরের সংযোগ (Edge ফাংশন + বট) তৈরি না হওয়া পর্যন্ত এটি চালু করলেও কিছু আসবে না। উত্তর নিজে থেকে যায় না।', 'Nothing arrives until the Edge function and the bot are set up. No reply is ever sent automatically.', 640)
 on conflict (key) do nothing;

-- =====================================================================
-- Tg1 channel kind
-- =====================================================================
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.sales_channels'::regclass and contype = 'c' and conname <> 'sales_channels_kind_tg86' and pg_get_constraintdef(oid) like '%web_form%' loop
    execute format('alter table public.sales_channels drop constraint %I', c.conname);
  end loop;
  if not exists (select 1 from pg_constraint where conrelid = 'public.sales_channels'::regclass and conname = 'sales_channels_kind_tg86') then
    alter table public.sales_channels add constraint sales_channels_kind_tg86
      check (kind in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other'));
  end if;
end $$;

create or replace function public.sales_channel_save(p_id int, p_code text, p_kind text, p_other text, p_name text, p_loc int, p_role text, p_account_ref text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;   -- bos86: + telegram
  if p_kind = 'telegram' and nullif(btrim(p_account_ref), '') is null then raise exception 'account_ref_required'; end if;                           -- bos86
  if p_kind = 'other' and nullif(btrim(p_other), '') is null then raise exception 'other_text_required'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 60 then raise exception 'name_required'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_role is not null and not exists (select 1 from public.roles where code = p_role) then raise exception 'role_not_found'; end if;
  if p_id is null then
    insert into public.sales_channels (code, kind, other_text, name_bn, location_id, role_code, account_ref, active, created_by)
      values (p_code, p_kind, case when p_kind = 'other' then left(btrim(p_other), 60) end, btrim(p_name), p_loc, p_role, nullif(btrim(p_account_ref), ''), coalesce(p_active, true), auth.uid()) returning * into c;
  else
    update public.sales_channels set code = p_code, kind = p_kind, other_text = case when p_kind = 'other' then left(btrim(p_other), 60) end, name_bn = btrim(p_name), location_id = p_loc,
        role_code = p_role, account_ref = nullif(btrim(p_account_ref), ''), active = coalesce(p_active, true), updated_at = now() where id = p_id returning * into c;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', c.id, 'code', c.code, 'active', c.active);
end $$;

-- =====================================================================
-- Tg3 secret token (only the SHA-256 is stored)
-- =====================================================================
create table if not exists public.telegram_secrets (
  channel_id int primary key references public.sales_channels(id),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  set_by uuid, set_at timestamptz not null default now()
);

create or replace function public._tg_hash(p text) returns text language sql immutable set search_path = public as $$
  select encode(sha256(convert_to(coalesce(p, ''), 'UTF8')), 'hex');
$$;

-- constant-time compare of two hex hashes
create or replace function public._tg_hash_eq(p_a text, p_b text) returns boolean language plpgsql immutable set search_path = public as $$
declare diff int := 0; i int;
begin
  if p_a is null or p_b is null or p_a !~ '^[0-9a-f]{64}$' or p_b !~ '^[0-9a-f]{64}$' then return false; end if;
  for i in 1..64 loop diff := diff | (ascii(substr(p_a, i, 1)) # ascii(substr(p_b, i, 1))); end loop;
  return diff = 0;
end $$;

create or replace function public._tg_actor_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public._inb_is_bot() or public.is_owner()
      or (public.is_active() and exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_code = 'intake_bot'));   -- Tg5: only if such a role is ever created
$$;

-- owner sets (or rotates) the secret_token of one telegram channel; the database keeps only its hash. Do not log the argument.
create or replace function public.telegram_secret_set(p_channel int, p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into ch from public.sales_channels where id = p_channel and kind = 'telegram';
  if not found then raise exception 'channel_not_found'; end if;
  if p_secret is null or p_secret !~ '^[A-Za-z0-9_-]{16,255}$' then raise exception 'bad_secret: 16-255 characters, letters, digits, _ and - only'; end if;
  insert into public.telegram_secrets (channel_id, secret_hash, set_by) values (ch.id, public._tg_hash(p_secret), auth.uid())
    on conflict (channel_id) do update set secret_hash = excluded.secret_hash, set_by = excluded.set_by, set_at = now();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_secrets', ch.id::text, jsonb_build_object('channel_id', ch.id, 'event', 'secret_set'));
  return jsonb_build_object('channel_id', ch.id, 'set', true);
end $$;

-- owner's health view: which telegram channels exist, is a secret set, last message, wrong-token count in 24h
create or replace function public.telegram_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('switch_on', public.rule_on('telegram_intake_on') and public.rule_on('inbox_on'),
    'rejected_24h', (select count(*) from public.intake_failures where kind = 'bad_signature' and state = 'rejected' and created_at > now() - interval '24 hours'
                       and coalesce(payload->>'kind', '') = 'telegram'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name_bn, 'active', c.active, 'location_id', c.location_id,
        'secret_set', exists (select 1 from public.telegram_secrets s where s.channel_id = c.id),
        'last_at', (select max(received_at) from public.inbound_messages m where m.channel_id = c.id)) order by c.id)
        from public.sales_channels c where c.kind = 'telegram'), '[]'::jsonb));
end $$;

-- =====================================================================
-- Tg2 intake (called by the Edge function logged in as the intake bot)
-- =====================================================================
create or replace function public.telegram_message_receive(p_channel_code text, p_secret_hash text, p_update_id bigint, p_chat_id bigint, p_username text, p_name text,
                                                           p_text text, p_msg_time timestamptz, p_attachment text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; sh text; pl jsonb; res jsonb; fid bigint; nm text;
begin
  if not public._tg_actor_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') or not public.rule_on('telegram_intake_on') then return jsonb_build_object('off', true); end if;
  if p_update_id is null or p_update_id < 0 or p_chat_id is null or char_length(coalesce(p_channel_code, '')) not between 1 and 30
     or char_length(coalesce(p_text, '')) > 20000 or char_length(coalesce(p_attachment, '')) > 500 then raise exception 'bad_input'; end if;
  select * into ch from public.sales_channels where code = p_channel_code and kind = 'telegram' and active;
  if not found then
    fid := public._intake_fail('bad_signature', null, p_update_id::text, 'channel_not_found', jsonb_build_object('kind', 'telegram'), 'rejected');
    return jsonb_build_object('rejected', 'channel_not_found', 'failure_id', fid);
  end if;
  select secret_hash into sh from public.telegram_secrets where channel_id = ch.id;
  if sh is null or not public._tg_hash_eq(sh, p_secret_hash) then
    -- a wrong / missing secret_token is never stored as a message; only the fact (no body, no chat id) goes to the failed list
    fid := public._intake_fail('bad_signature', ch.id, p_update_id::text, case when sh is null then 'secret_not_set' else 'bad_signature' end, jsonb_build_object('kind', 'telegram'), 'rejected');
    return jsonb_build_object('rejected', case when sh is null then 'secret_not_set' else 'bad_signature' end, 'failure_id', fid);
  end if;
  nm := nullif(btrim(coalesce(p_name, '')), '');
  if nm is null and nullif(btrim(coalesce(p_username, '')), '') is not null then nm := '@' || btrim(p_username); end if;
  pl := jsonb_build_object('kind', 'telegram', 'account_ref', ch.account_ref, 'external_id', p_update_id::text, 'handle', 'tg:' || p_chat_id::text, 'name', nm, 'text', p_text,
                           'msg_time', p_msg_time, 'attachment', p_attachment);
  begin
    res := public._inb_insert_message(pl);
  exception when others then
    fid := public._intake_fail('message', ch.id, p_update_id::text, sqlerrm, pl);
    return jsonb_build_object('failed', true, 'queued', true, 'failure_id', fid);
  end;
  return res;
end $$;

-- =====================================================================
-- Tg4 link a telegram chat to a customer / an order
-- =====================================================================
create table if not exists public.telegram_chat_links (
  id bigint generated always as identity primary key,
  channel_id int not null references public.sales_channels(id),
  chat_id text not null check (chat_id ~ '^-?[0-9]{1,20}$'),
  customer_id uuid references public.customers(id),
  order_id uuid references public.online_orders(id),
  note text check (note is null or char_length(note) <= 300),
  linked_by uuid, linked_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unlinked_at timestamptz, unlink_note text,
  unique (channel_id, chat_id)
);

create or replace function public._tg_chat_of(p_handle text) returns text language sql immutable set search_path = public as $$
  select case when p_handle ~ '^tg:-?[0-9]{1,20}$' then substr(p_handle, 4) end;
$$;

create or replace function public.telegram_chat_link(p_msg_id bigint, p_customer uuid default null, p_order uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; c public.sales_channels; chat text; o public.online_orders; l public.telegram_chat_links;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  select * into c from public.sales_channels where id = m.channel_id;
  chat := public._tg_chat_of(m.customer_handle);
  if c.kind <> 'telegram' or chat is null then raise exception 'not_telegram'; end if;
  if p_customer is null and p_order is null then raise exception 'bad_input'; end if;
  if p_customer is not null and not exists (select 1 from public.customers where id = p_customer and active) then raise exception 'customer_not_found'; end if;
  if p_order is not null then
    select * into o from public.online_orders where id = p_order;
    if not found or o.location_id <> m.location_id then raise exception 'order_not_found'; end if;
  end if;
  insert into public.telegram_chat_links (channel_id, chat_id, customer_id, order_id, note, linked_by)
    values (m.channel_id, chat, p_customer, p_order, left(nullif(btrim(p_note), ''), 300), auth.uid())
    on conflict (channel_id, chat_id) do update set customer_id = coalesce(excluded.customer_id, case when public.telegram_chat_links.unlinked_at is null then public.telegram_chat_links.customer_id end),
        order_id = coalesce(excluded.order_id, case when public.telegram_chat_links.unlinked_at is null then public.telegram_chat_links.order_id end),
        note = coalesce(excluded.note, public.telegram_chat_links.note), linked_by = auth.uid(), updated_at = now(), unlinked_at = null, unlink_note = null
    returning * into l;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_chat_links', l.id::text,
            jsonb_build_object('event', 'link', 'channel_id', l.channel_id, 'msg_id', m.id, 'customer_id', l.customer_id, 'order_id', l.order_id));
  return jsonb_build_object('id', l.id, 'customer_id', l.customer_id, 'order_id', l.order_id);
end $$;

create or replace function public.telegram_chat_unlink(p_msg_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; l public.telegram_chat_links;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  update public.telegram_chat_links set unlinked_at = now(), unlink_note = left(btrim(p_reason), 300), updated_at = now(), linked_by = auth.uid()
    where channel_id = m.channel_id and chat_id = public._tg_chat_of(m.customer_handle) and unlinked_at is null returning * into l;
  if not found then raise exception 'not_found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'telegram_chat_links', l.id::text, jsonb_build_object('event', 'unlink', 'channel_id', l.channel_id, 'msg_id', m.id));
  return jsonb_build_object('id', l.id, 'unlinked', true);
end $$;

-- what is known about the chat of one message: link, customer, orders made from this chat, how many messages. Customer name / mobile only for people allowed to see contacts (audited).
create or replace function public.telegram_chat_info(p_msg_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages; c public.sales_channels; chat text; l public.telegram_chat_links; ok boolean; cu public.customers; oo public.online_orders;
begin
  select * into m from public.inbound_messages where id = p_msg_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  chat := public._tg_chat_of(m.customer_handle);
  if c.kind <> 'telegram' or chat is null then raise exception 'not_telegram'; end if;
  ok := public._inb_contact_ok(m.location_id);
  select * into l from public.telegram_chat_links where channel_id = m.channel_id and chat_id = chat and unlinked_at is null;
  if found and l.customer_id is not null then select * into cu from public.customers where id = l.customer_id; end if;
  if found and l.order_id is not null then select * into oo from public.online_orders where id = l.order_id; end if;
  if ok and found and l.customer_id is not null then
    perform public._inb_audit_view('telegram_chat_links', l.id::text, jsonb_build_object('fields', 'customer_name,customer_mobile'));
  end if;
  return jsonb_build_object('msg_id', m.id, 'linked', l.id is not null, 'masked', not ok,
    'customer_id', l.customer_id, 'customer_name', case when ok then cu.name end, 'customer_mobile', case when ok then cu.mobile end,
    'order_id', l.order_id, 'order_no', oo.order_no, 'note', l.note,
    'message_count', (select count(*) from public.inbound_messages x where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_no', o2.order_no, 'status', o2.status) order by o2.created_at)
                          from public.online_orders o2 where o2.id in (select x.linked_order_id from public.inbound_messages x
                                                                        where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle and x.linked_order_id is not null)), '[]'::jsonb));
end $$;

-- an order made from a telegram message links its chat to that order automatically
create or replace function public._tg_autolink86() returns trigger language plpgsql security definer set search_path = public as $$
declare chat text;
begin
  if new.linked_order_id is not null and new.linked_order_id is distinct from old.linked_order_id
     and exists (select 1 from public.sales_channels c where c.id = new.channel_id and c.kind = 'telegram') then
    chat := public._tg_chat_of(new.customer_handle);
    if chat is not null then
      insert into public.telegram_chat_links (channel_id, chat_id, order_id, linked_by) values (new.channel_id, chat, new.linked_order_id, auth.uid())
        on conflict (channel_id, chat_id) do update set order_id = excluded.order_id, updated_at = now(), unlinked_at = null, unlink_note = null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists inbound_messages_tg86 on public.inbound_messages;
create trigger inbound_messages_tg86 after update on public.inbound_messages for each row execute function public._tg_autolink86();

-- =====================================================================
-- re-created: inbox_board (latest = phase76) + bos86: telegram channels shown beside Meta channels
-- =====================================================================
create or replace function public.inbox_board(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l int[]; last_at timestamptz; hrs numeric := coalesce(public.rule_num('inbox_silence_hours'), 0); hs numeric; fcount int := 0;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('on', false); end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select max(received_at) into last_at from public.inbound_messages where location_id = any (l);
  hs := case when last_at is null then null else round(extract(epoch from now() - last_at) / 3600, 1) end;
  if public.is_owner() or public.can_do('POS', 'approve') then select count(*) into fcount from public.intake_failures where state = 'failed'; end if;
  return jsonb_build_object('on', true,
    'new_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'new'),
    'seen_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'seen'),
    'last_at', last_at, 'hours_since', hs, 'silence_hours', hrs,
    'silent', hrs > 0 and hs is not null and hs > hrs,
    'failed_count', fcount,
    'dup_open', (select count(*) from public.order_dup_flags where location_id = any (l) and state = 'open'),
    'drafts', (select count(*) from public.online_orders where location_id = any (l) and is_draft and status = 'new'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_bn, 'kind', c.kind,
        'last_at', (select max(received_at) from public.inbound_messages m where m.channel_id = c.id),
        'new_count', (select count(*) from public.inbound_messages m where m.channel_id = c.id and m.status = 'new')) order by c.id)
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp', 'telegram') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));   -- bos86: + telegram
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['telegram_secrets', 'telegram_chat_links'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke usage, select on sequence public.telegram_chat_links_id_seq from public, anon, authenticated;

revoke all on function public.telegram_secret_set(int, text), public.telegram_status(), public.telegram_message_receive(text, text, bigint, bigint, text, text, text, timestamptz, text),
  public.telegram_chat_link(bigint, uuid, uuid, text), public.telegram_chat_unlink(bigint, text), public.telegram_chat_info(bigint) from public, anon;
grant execute on function public.telegram_secret_set(int, text), public.telegram_status(), public.telegram_message_receive(text, text, bigint, bigint, text, text, text, timestamptz, text),
  public.telegram_chat_link(bigint, uuid, uuid, text), public.telegram_chat_unlink(bigint, text), public.telegram_chat_info(bigint) to authenticated;
revoke all on function public._tg_hash(text), public._tg_hash_eq(text, text), public._tg_actor_ok(), public._tg_chat_of(text), public._tg_autolink86() from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase513.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase87.sql there and is already pasted on the live database under that name.
-- Renumbered to phase513.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 513 (bos87) - STEP X: fixes from the independent QA (docs/briefs_p2p3/QA_COVERAGE.md). Additive; paste-twice safe. Defaults = today's behaviour.
-- Paste order: 72 ... 79, 82, 84, then this file LAST. It re-creates functions from their LATEST definition (all bos72..bos84 lines kept); lines it changes carry "-- bos87".
--   1. Owner decision: the OWNER can always approve (recipe_approve, cost_rule_approve). No self_approve_refused for the owner. The approval is kept as an audit_log
--      row (action 'self_approved') and the return value carries a NON-BLOCKING suggestion (suggestion = 'ask_another_approver' + suggestion_bn/mix/en).
--      A non-owner is unchanged: refused unless the switch recipe_self_approve / cost_rule_self_approve is ON (then also logged + suggestion).
--   2. a2-F8  expiry_sale_guard off|warn|refuse (default off). off = today (block_expired_sale decides). warn = sale goes through, the red alert names batch + expiry date.
--             refuse = refuse the sale from an expired batch (same effect as block_expired_sale = on; late offline syncs are still never refused).
--      a2-F9  record_sale2: a client_id already used by ANOTHER user is refused with 'client_id_taken' (was a raw unique violation). Same user = unchanged (the old sale is returned).
--      a4-F11 purchase_backdate_flag off|warn (default off): posting a bill whose bill_date is not today raises a yellow 'purchase_backdated' line (stock is stamped now(), the journal bill_date).
--             The stock timing itself is NOT changed (owner decision, see report).
--      a4-F12 ledger_problem_count(): number of approved forms whose stock-ledger posting failed (for a badge). The failure already becomes a yellow exception line and never blocks approval.
--   3. production_double_issue_guard off|warn (default off): a stock_issue / form out-line and a recipe production run that take the SAME item from the SAME place on the SAME day
--      -> yellow 'production_double_issue' line (never blocks). production_recommendations() (owner) lists key / current / recommended / reason (production_requires_recipe ON ...).
-- Needs phases 72..79, 82, 84. No table, no data change; three new rules (all off).
-- ============================================================

do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public._recipe_gate73(uuid)') is null
     or to_regprocedure('public._conv_cost(uuid, integer, numeric, numeric, date, text)') is null
     or to_regprocedure('public._cs_alloc(bigint)') is null
     or to_regprocedure('public._inb_audit76()') is null
     or to_regprocedure('public._oo_flag_ro77()') is null
     or to_regprocedure('public._c78_rows(date, date)') is null
     or (select p.prosrc not like '%bos72%' from pg_proc p where p.proname = 'production_post' and p.pronargs = 7 and p.pronamespace = 'public'::regnamespace limit 1) is not false      -- phase79 applied
     or to_regprocedure('public.guard_recommendations()') is null                                                                                                       -- phase82
     or to_regprocedure('public._aud84()') is null then                                                                                                                 -- phase84
    raise exception 'phase513 needs phases 72, 73, 74, 75, 76, 77, 78, 79, 508 and 510 pasted first (in that order)';
  end if;
end $g$;

-- ---------- new switches (all default to today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('expiry_sale_guard', 'stock', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'মেয়াদোত্তীর্ণ মাল বিক্রি: বন্ধ / warn / block', 'Expired মাল বিক্রি: off / warn / refuse', 'Selling expired stock: off, warn or refuse',
  'বন্ধ = আগের মতো ("মেয়াদোত্তীর্ণ মাল বিক্রি আটকানো" switch যা ঠিক করে)। warn = বিক্রি হয়, red warning-এ batch ও মেয়াদের তারিখ থাকে। block = মেয়াদোত্তীর্ণ batch থেকে বিক্রি ফেরত।',
  'off = আগের মতো ("Expired মাল বিক্রি আটকানো" switch যা ঠিক করে)। warn = sale হয়, red warning-এ batch ও expiry date থাকে। refuse = expired batch থেকে sale ফেরত।',
  'off = as before (the "block expired sale" switch decides). warn = the sale goes through, the red warning names the batch and its expiry date. refuse = a sale that would take expired stock is refused (late offline syncs are still accepted, with the red warning).', 85),
 ('production_double_issue_guard', 'stock', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'উৎপাদন ও stock issue-তে একই মাল দুবার: বন্ধ / warn', 'Production আর stock issue-তে একই মাল দুবার: off / warn', 'Same stock taken by production and by an issue: off or warn',
  'warn = একই দিনে একই জায়গায় একই পণ্য উৎপাদন (recipe) এবং stock issue / form-এর out-line দুটোতেই বেরোলে yellow warning (কিছু আটকায় না)। বন্ধ = আগের মতো।',
  'warn = একই দিনে একই জায়গায় একই item production (recipe) আর stock issue / form out-line দুটোতেই বেরোলে yellow warning (কিছু আটকায় না)। off = আগের মতো।',
  'warn = a yellow warning when the same item leaves the same place on the same day both through a recipe production run and through a stock issue / form out-line (nothing is blocked). off = as before.', 86),
 ('purchase_backdate_flag', 'stock', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'আগের তারিখের ক্রয় bill পোস্ট হলে warning: বন্ধ / warn', 'Backdated purchase bill post হলে warning: off / warn', 'Posting a purchase bill with a date other than today: off or warn',
  'warn = bill-এর তারিখ আজ না হলে yellow warning: stock আজকের সময়ে ঢোকে, হিসাবের journal bill-এর তারিখে। বন্ধ = আগের মতো।',
  'warn = bill date আজ না হলে yellow warning: stock আজকের time-এ ঢোকে, journal bill date-এ। off = আগের মতো।',
  'warn = a yellow warning when the bill date is not today: the stock is stamped now, the journal uses the bill date. off = as before.', 87)
 on conflict (key) do nothing;

-- ---------- 1. approvals: the owner can always approve (audit row + non-blocking suggestion) ----------
create or replace function public.recipe_approve(p_recipe uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb; selfap boolean := false; sid text;   -- bos87
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch recipe_self_approve)
    if public.is_owner() or public.rule_on('recipe_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'recipes', r.id::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('recipe_id', r.id, 'approved', true) || public._self_approve_hint87(selfap);   -- bos87
end $$;

-- the non-blocking suggestion that rides on a self-approval (empty object when it was not a self-approval)
create or replace function public._self_approve_hint87(p_self boolean) returns jsonb language sql immutable set search_path = public as $$
  select case when coalesce(p_self, false) then jsonb_build_object('self_approved', true, 'suggestion', 'ask_another_approver',
    'suggestion_bn', 'আপনি নিজের করা পরিবর্তন নিজেই অনুমোদন করেছেন। অন্য একজন অনুমোদনকারীকে দিয়ে দেখিয়ে নিন।',
    'suggestion_mix', 'আপনি নিজের change নিজেই approve করেছেন। আরেকজন approver-কে দিয়ে দেখিয়ে নিন।',
    'suggestion_en', 'You approved your own change. Consider asking another approver to review it.') else '{}'::jsonb end
$$;
revoke all on function public._self_approve_hint87(boolean) from public, anon, authenticated;

create or replace function public.cost_rule_approve(p_rule bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cost_source_rules; b record; n int := 0; selfap boolean := false; sid text;   -- bos87
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch cost_rule_self_approve)
    if public.is_owner() or public.rule_on('cost_rule_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'cost_source_rules', p_rule::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n) || public._self_approve_hint87(selfap);   -- bos87
end $$;

-- ---------- 2. a2-F8 expiry_sale_guard: stock_post (latest = phase508; bos10..bos82 lines kept) ----------
CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false; pm text; who text;   -- bos82
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale') or coalesce(public.rule_txt('expiry_sale_guard'), 'off') = 'refuse'; end if;           -- (12) read once; bos87: expiry_sale_guard = refuse acts like the block_expired_sale switch
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    -- bos82: production that takes an ingredient below zero: reason needed (production_negative_reason: off | warn | required)
    if p_reason = 'issue_out' and p_ref_type = 'production' then   -- bos82
      pm := coalesce(public.rule_txt('production_negative_reason'), 'off');   -- bos82
      if pm <> 'off' then   -- bos82
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      if mode = 'block' and p_neg = 'full' and public.rule_on('neg_grant_log') and public.has_grant('sell_below_zero', p_loc) then   -- bos82: the grant was used to go below zero: tell the owner who / what / how much
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        perform public._stock_exc(p_loc, 'sell_below_zero_used', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): "stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): the sell-below-zero permission was used, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', মেয়াদ ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end,   -- bos87
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', expired ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end, p_sale, d, form);   -- bos87
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $function$;

-- ---------- a2-F9 record_sale2 (latest = phase43): a client_id used by another user is refused with client_id_taken ----------
CREATE OR REPLACE FUNCTION public.record_sale2(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_discount_kind text DEFAULT NULL::text, p_discount_input numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; dkind text; dinput numeric; credit_over boolean := false; em text; ov_ok boolean;
  tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
begin
  perform set_config('bos.em_used', '', true);
  perform set_config('bos.tier_use', '', true);   -- bos43
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: another user already used this client_id
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  -- discount given as an AMOUNT (default, also every old call) or as a PERCENT of the subtotal (computed here, 2 decimals)
  dkind := coalesce(nullif(btrim(p_discount_kind), ''), 'amount');
  if dkind not in ('amount', 'percent') then raise exception 'bad_discount_kind'; end if;
  if dkind = 'percent' then
    dinput := p_discount_input;
    if dinput is null or dinput = 'NaN'::numeric or dinput < 0 or dinput > 100 then raise exception 'bad_discount'; end if;
    disc := 0;                                        -- computed after the subtotal is known
  else
    dinput := coalesce(p_discount_input, p_discount, 0);
    if dinput = 'NaN'::numeric then raise exception 'bad_discount'; end if;
    dinput := round(dinput, 2); disc := dinput;
  end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found then raise exception 'item_not_found'; end if; /* bos22-late */ if not it.is_active and not (at_ < now() - interval '2 minutes' and it.updated_at > at_) then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        if public.rule_on('pos_override_manager') then
          if ov_ok is null then ov_ok := public.rule_ok('price_override', p_loc, null, null, 'sale'); end if;      -- one approval covers every price change in this sale
          if not ov_ok then raise exception 'override_needs_approval'; end if;
        end if;
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        shown := nullif(ln->>'price', '')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit, 'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    elsif ln ? 'qty' and ln ? 'price' then            -- an item that is not in the list
      qty := (ln->>'qty')::numeric; pr := (ln->>'price')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      if pr is null or pr = 'NaN'::numeric or pr <= 0 then raise exception 'bad_price'; end if;
      if nullif(btrim(ln->>'name'), '') is null then raise exception 'name_required'; end if;
      if public.rule_txt('pos_unlisted') = 'block' then raise exception 'unlisted_blocked'; end if;
      amt := round(qty * pr, 2); any_custom := coalesce(public.rule_txt('pos_unlisted'), 'flag') = 'flag';
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(btrim(ln->>'name'), 80), 'unit', left(coalesce(ln->>'unit', ''), 20), 'qty', qty, 'price', pr, 'amount', amt, 'override', false, 'custom', true);
    else                                              -- quick sale
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name', ''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if dkind = 'percent' then
    disc := round(sub * dinput / 100, 2);
    -- the phone shows the discount it computed from the percent; a half-cent case can round the other way here. Within one paisa (0.01) the amount the
    -- customer was shown wins, so the bill never asks for a paisa more or less than the screen said (never beyond 0.01, never outside 0..subtotal).
    if p_discount is not null and abs(p_discount - disc) <= 0.01 and p_discount between 0 and sub then disc := round(p_discount, 2); end if;
  end if;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if disc > 0 and not public.rule_on(case dkind when 'percent' then 'discount_mode_percent_on' else 'discount_mode_amount_on' end) then raise exception 'discount_mode_off'; end if;
  -- bos43: the customer's tier discount is pre-approved (switch tier_discount_on): the part of the discount up to the tier percent (and the tier cap) needs no manager approval
  if disc > 0 and public.rule_on('tier_discount_on') and nullif(btrim(p_customer_mobile), '') is not null then
    select t.id, t.discount_percent, t.discount_cap_amount into tier_id43, tier_pct43, tier_cap43
      from public.customers cu join public.customer_tiers t on t.id = cu.tier_id
      where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0;
    if found then tier_amt43 := least(disc, round(sub * tier_pct43 / 100, 2), coalesce(tier_cap43, disc)); end if;
  end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > tier_amt43 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    amt := (pay->>'amount')::numeric;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    amt := round(amt, 2); paid_sum := paid_sum + amt;
    if not pm = any (modes) then modes := modes || pm; end if;
  end loop;
  if paid_sum > sub - disc then raise exception 'overpaid'; end if;
  due := sub - disc - paid_sum;
  -- customer
  mob := case when nullif(btrim(p_customer_mobile), '') is not null then public.norm_mobile(p_customer_mobile) end;
  needcust := (due > 0 and public.rule_on('pos_customer_on_due')) or (stype = 'wholesale' and public.rule_on('pos_customer_on_wholesale')) or (disc > 0 and public.rule_on('pos_customer_on_discount'));
  if needcust and mob is null and not public.rule_ok('sale_without_customer', p_loc, null, null, 'sale') then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null and coalesce(public.rule_txt('pos_credit_mode'), 'block') <> 'off' then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit then
        credit_over := true;
        if coalesce(public.rule_txt('pos_credit_mode'), 'block') = 'block' and not public.rule_ok('credit_over_limit', p_loc, due, null, 'sale') then raise exception 'over_credit_limit'; end if;
      end if;
    end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if tier_amt43 > 0 then perform set_config('bos.tier_use', tier_id43 || '|' || tier_pct43 || '|' || tier_amt43, true); end if;   -- bos43
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount, discount_kind, discount_input)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due, case when disc > 0 then dkind end, case when disc > 0 then dinput end)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if p_client is not null and exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: a race with another user
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
  end loop;
  -- exceptions for the owner (nothing is blocked here except the customer / credit rules above)
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  if any_custom then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unlisted_item', 'yellow', s.total,
        jsonb_build_object('bn', 'রসিদ ' || n || ': তালিকায় নেই এমন আইটেম বিক্রি — আইটেম তালিকায় যোগ করুন', 'en', 'Receipt ' || n || ': an item that is not in the list was sold — add it to the item list'));
  end if;
  if disc > tier_amt43 then   -- bos43 (was: disc > 0)
    if lim is null or jsonb_typeof(lim) = 'null' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_no_limit', 'yellow', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট দেওয়া হয়েছে কিন্তু ডিসকাউন্টের সীমা সেটিংসে নেই', 'en', 'Receipt ' || n || ': a discount was given but no discount limit is set'));
    elsif disc > (lim #>> '{}')::numeric then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_over_limit', 'red', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট সীমার উপরে', 'en', 'Receipt ' || n || ': discount above the limit'));
    end if;
  end if;
  if due > 0 and cust.id is null then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unattributed_due', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': বাকি আছে কিন্তু কোনো গ্রাহক নেই — এই বাকি কোনো গ্রাহকের খাতায় নেই', 'en', 'Receipt ' || n || ': an amount is due but there is no customer — it is on nobody’s ledger'));
  end if;
  if credit_over then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
  for em in select unnest(string_to_array(nullif(current_setting('bos.em_used', true), ''), ',')) loop
    if em <> '' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'emergency_used', 'yellow', s.total,
          jsonb_build_object('bn', 'রসিদ ' || n || ': জরুরি অনুমোদনে সেল (' || split_part(em, ':', 2) || ')', 'en', 'Receipt ' || n || ': sold on an emergency approval (' || split_part(em, ':', 2) || ')'));
    end if;
  end loop;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id, 'discount', disc);
end $function$;

-- ---------- a4-F11 _post_purchase_p13 (latest = phase508; bos82 lines kept): optional backdate flag ----------
CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb; gm text; skipst boolean := false;   -- bos82
begin
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if pb.status = 'posted' then          -- a re-sent request: answered only to someone who may see purchases (or who posted it)
    if not (public._pur_ok(pb.location_id) or pb.posted_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true);
  end if;
  if not (public.has_grant(gcode, pb.location_id) or public._use_em(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.bill_date is distinct from (now() at time zone 'Asia/Dhaka')::date and coalesce(public.rule_txt('purchase_backdate_flag'), 'off') = 'warn' then   -- bos87 (a4-F11): stock is stamped now(), the journal uses bill_date
    perform public._stock_exc(pb.location_id, 'purchase_backdated', 'yellow', 'বিল ' || coalesce(pb.bill_no, '-') || ': তারিখ ' || pb.bill_date::text || ' (আজ নয়) — stock আজকের সময়ে ঢুকেছে, হিসাবের journal বিলের তারিখে',
      'Bill ' || coalesce(pb.bill_no, '-') || ': dated ' || pb.bill_date::text || ' (not today) — the stock is stamped now, the journal uses the bill date', null, pb.bill_date, 'PURCHASE', pb.total);   -- bos87
  end if;   -- bos87
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  if pb.kind = 'return' then
    if pb.ref_bill_id is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
      perform public._stock_exc(pb.location_id, 'purchase_return_unreferenced', 'red', 'বিল ছাড়া ক্রয় ফেরত (বিল ' || coalesce(pb.bill_no, '-') || ')',
        'A purchase return was posted without the original bill (return ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE', pb.total);
    else
      perform 1 from public.purchase_bills where id = pb.ref_bill_id for update;
      select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'description', l.description, 'qty', l.qty, 'unit', l.unit, 'unit_cost', l.unit_cost)), '[]'::jsonb) into norm
        from public.purchase_lines l where l.bill_id = pb.id;
      if not exists (select 1 from public.purchase_bills where id = pb.ref_bill_id and status = 'posted') then raise exception 'bad_ref_bill'; end if;
      perform public._return_check(pb.ref_bill_id, pb.id, norm, true);
    end if;
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  -- bos82: GRN exclusivity. Source = GRN and guard on: the bill keeps money / supplier balance, the GRN holds the stock (no second purchase_in)
  gm := coalesce(public.rule_txt('purchase_grn_guard'), 'off');   -- bos82
  if pb.kind = 'bill' and gm in ('skip', 'link') and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then   -- bos82
    if gm = 'link' and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void') then   -- bos82
      raise exception 'grn_link_required' using detail = 'GRN is the stock source: link this bill to its GRN before posting', hint = 'grn_bill_link';   -- bos82
    end if;   -- bos82
    skipst := true;   -- bos82
  end if;   -- bos82
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one); a return is checked the same way
    if pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ' || case when pb.kind = 'return' then 'ফেরতের' else 'ক্রয়' end || 'মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': ' || case when pb.kind = 'return' then 'return ' else '' end || 'unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked and not (skipst and pb.kind = 'bill') then   -- bos82: stock comes from the GRN
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        -- out at the current average cost (cost null = the average); what the supplier credits beyond / below that is the variance of this return
        lid := public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, null, null, now(), null, null, 'full');
        select unit_cost into av from public.stock_ledger where id = lid;
        var := var + round(bq * (round(ucb * net, 6) - coalesce(av, round(ucb * net, 6))), 2);
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now(), variance = case when pb.kind = 'return' then var end where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum) || case when skipst then jsonb_build_object('stock_from_grn', true) else '{}'::jsonb end;   -- bos82
end $function$;

-- ---------- a4-F12: how many approved forms have a failed / skipped stock-ledger posting (for a badge). The failure itself already never blocks the approval
--            (trigger _entries_post_ledger swallows it into a yellow exception line); this only counts what ledger_post_problems() lists, for the people allowed to see it ----------
create or replace function public.ledger_problem_count(p_loc int default null) returns int
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return (select count(*)::int from public.ledger_post_problems(p_loc));
end $$;
revoke all on function public.ledger_problem_count(int) from public, anon;
grant execute on function public.ledger_problem_count(int) to authenticated;

-- ---------- 3. production double-deduction guard (never blocks: any error inside is swallowed) ----------
-- fires for every issue_out ledger row (stock_issue 'issue', form out-line 'entry', recipe production 'production') when the switch is not off
create or replace function public._prod_double_issue87() returns trigger
language plpgsql security definer set search_path = public as $$
declare d date; t0 timestamptz; t1 timestamptz; other bigint; ic text; nm text; ne text; en text; bn text;
begin
  if coalesce(public.rule_txt('production_double_issue_guard'), 'off') = 'off' then return null; end if;
  if new.ref_type not in ('production', 'issue', 'entry') then return null; end if;
  begin
    d := (new.made_at at time zone 'Asia/Dhaka')::date;
    t0 := d::timestamp at time zone 'Asia/Dhaka'; t1 := (d + 1)::timestamp at time zone 'Asia/Dhaka';
    select x.id into other from public.stock_ledger x
     where x.item_id = new.item_id and x.location_id = new.location_id and x.reason = 'issue_out' and x.id <> new.id
       and x.made_at >= t0 and x.made_at < t1
       and ((new.ref_type = 'production' and x.ref_type in ('issue', 'entry')) or (new.ref_type in ('issue', 'entry') and x.ref_type = 'production'))
       and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id)
     order by x.id limit 1;
    if other is null then return null; end if;
    select code, name_bn, name_en into ic, nm, ne from public.items where id = new.item_id;
    en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): taken out by a recipe production run and also by a stock issue / form out-line on the same day — it may be deducted twice';
    bn := coalesce(nm, '') || ' (' || coalesce(ic, '') || '): একই দিনে recipe উৎপাদন আর stock issue / form-এর out-line দুটোতেই বেরিয়েছে — দুবার কাটা হয়ে থাকতে পারে';
    if not exists (select 1 from public.exceptions e where e.flag_code = 'production_double_issue' and e.location_id = new.location_id and e.entry_date = d and e.text->>'en' = en) then
      perform public._stock_exc(new.location_id, 'production_double_issue', 'yellow', bn, en, null, d, 'STOCK');
    end if;
  exception when others then null;
  end;
  return null;
end $$;
revoke all on function public._prod_double_issue87() from public, anon, authenticated;
drop trigger if exists stock_ledger_dbl87 on public.stock_ledger;
create trigger stock_ledger_dbl87 after insert on public.stock_ledger for each row when (new.reason = 'issue_out') execute function public._prod_double_issue87();

-- recommendations only (the owner decides; nothing is changed here). Same row shape as guard_recommendations().
create or replace function public.production_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_array(
   jsonb_build_object('key', 'production_requires_recipe', 'current', to_jsonb(public.rule_on('production_requires_recipe')), 'recommended', to_jsonb(true),
     'reason_bn', 'recipe ছাড়া হাতে-লেখা উৎপাদন কাঁচামাল না কেটে তৈরি মাল যোগ করে; recipe বাধ্যতামূলক হলে কাঁচামাল একবারই কাটে ও খরচ ধরা পড়ে।',
     'reason_mix', 'Recipe ছাড়া manual production কাঁচামাল না কেটে finished মাল যোগ করে; recipe বাধ্যতামূলক হলে কাঁচামাল একবারই কাটে ও cost ধরা পড়ে।',
     'reason_en', 'A manual production entry adds finished goods without deducting ingredients; requiring a recipe deducts the ingredients once and captures the cost.'),
   jsonb_build_object('key', 'production_double_issue_guard', 'current', public.rule_txt('production_double_issue_guard'), 'recommended', 'warn',
     'reason_bn', 'একই দিনে একই মাল উৎপাদন (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে সতর্কবার্তা আসে, কিছু আটকায় না।',
     'reason_mix', 'একই দিনে একই মাল production (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে warning আসে, কিছু আটকায় না।',
     'reason_en', 'If the same goods are deducted by a recipe production run and by a stock issue or form on the same day, they may be deducted twice; warn flags it and blocks nothing.'),
   jsonb_build_object('key', 'production_requires_cost', 'current', public.rule_txt('production_requires_cost'), 'recommended', 'refuse',
     'reason_bn', 'কাঁচামালের দাম অজানা থাকলে উৎপাদনের খরচ ভুল/ফাঁকা থাকে; refuse দিলে আগে দাম বসাতে হয় (আগে সব কাঁচামালের দাম দিয়ে নিন)।',
     'reason_mix', 'Ingredient-এর cost অজানা থাকলে production cost ভুল/ফাঁকা থাকে; refuse দিলে আগে cost বসাতে হয় (আগে সব ingredient-এর cost দিয়ে নিন)।',
     'reason_en', 'With an unknown ingredient cost the production cost is wrong or blank; refuse forces the cost to be entered first (fill in every ingredient cost before switching it on).'));
end $$;
revoke all on function public.production_recommendations() from public, anon;
grant execute on function public.production_recommendations() to authenticated;

-- ---------------------------------------------------------------- phase514.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase88.sql there and is already pasted on the live database under that name.
-- Renumbered to phase514.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 514 (bos88) - STEP R: ONE cost source for every report (audit a1-F6, a2-F5, a3-F1).
--   Needs phases 72..79, 82, 83, 84 pasted first. Additive, paste-twice safe: one rule, helper functions, create or replace only. No table, no data change.
--
--   Problem: the journal COGS is the stock-ledger unit_cost (weighted average), and since phase72 biz_daily / _p27_pl / l1 / l2 / l3 / brand_pnl / partner bases use that
--   cost first. But biz_items, the report builder (rpt_meas "cogs / gp / gp_pct" through rpt_agg_sql) and items_with_cost still read the hand-typed item_costs.
--   So one product showed one cost on one screen and another cost on the next.
--
--   Switch  report_cost_source  (owner rule, kind choice):
--     ledger_then_item_costs  DEFAULT. Stock-ledger cost of the units sold; item_costs only for quantity whose ledger cost is blank or 0 (shown as an estimate).
--                             This is what biz_daily / _p27_pl already did, so the main P&L numbers are unchanged. biz_items, the report builder and
--                             items_with_cost now follow it too (they read item_costs only before).
--     ledger_avg              Only the stock ledger. Anything without a ledger cost is UNKNOWN (never replaced by a typed cost).
--     item_costs              Only the hand-typed cost (the old behaviour of biz_items / report builder). The ledger is ignored by the reports.
--   The journal (GL) COGS always comes from the ledger: it is NOT switched. profit_source_check shows report vs journal.
--   Unknown cost is NEVER 0: biz_items cogs is NULL when part of an item's sales has no cost (revenue of that part = unknown_cost_rev in biz_daily /
--   biz_items_cost88), the report builder cogs stays blank (uncosted_pct / costed_net say how much), items_with_cost has no row for an item without a cost
--   (item_cost_status88 lists it with cost_missing = true).
--   Re-created (latest definition, only bos88 lines changed): _cogs_lines72 (so biz_daily, _p27_pl, l1/l2/l3, brand_pnl, partner base, profit_source_check,
--   acct_income_statement follow the switch), biz_items, items_with_cost, rpt_agg_sql. New: _rcs88, _item_cost_eff88, _line_cost88 (closed), item_cost_status88,
--   biz_items_cost88 (cost-grant holders only).
--   Cost secrecy / RLS / grants: unchanged. Cost columns only for biz_cost_ok() / view_cost holders; new internals are closed to the browser.
--   Other bosNN tags inside the re-created bodies (bos14 count_in_business filter, bos72 return share) are kept.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._cogs_lines72(date, date, int[])') is null          -- 72
     or to_regprocedure('public._recipe_gate73(uuid)') is null                    -- 73
     or to_regprocedure('public._conv_cost(uuid, integer, numeric, numeric, date, text)') is null   -- 74
     or to_regprocedure('public._cs_alloc(bigint)') is null                       -- 75
     or to_regprocedure('public._inb_audit76()') is null                          -- 76
     or to_regprocedure('public._oo_flag_ro77()') is null                         -- 77
     or to_regprocedure('public._c78_rows(date, date)') is null                   -- 78
     or position('bos72' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure)) = 0   -- 79
     or to_regprocedure('public._items_unit_conv82()') is null                -- 82
     or to_regprocedure('public._transit_loss83(uuid, numeric, text)') is null                       -- 83
     or to_regprocedure('public._aud84()') is null then                           -- 84
    raise exception 'phase514 needs phases 72..79, 82, 83 and 84 pasted first';
  end if;
end $g$;

-- ---------- the switch ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('report_cost_source', 'stock', 'choice', '"ledger_then_item_costs"', '["ledger_avg","item_costs","ledger_then_item_costs"]', null, null,
  'রিপোর্টে পণ্যের খরচ কোথা থেকে: স্টক খাতার গড় / হাতে লেখা খরচ / আগে স্টক খাতা, না থাকলে হাতে লেখা', 'Report এ product cost কোথা থেকে: ledger average / হাতে লেখা item cost / আগে ledger, না থাকলে item cost', 'Where every report takes the product cost from: stock-ledger average, typed item cost, or ledger first then typed item cost',
  'ledger_then_item_costs (default) = the cost the journal uses, typed item cost only where the ledger has none (marked as estimate). ledger_avg = ledger only, no ledger cost = unknown. item_costs = typed cost only. The journal itself always uses the ledger.', 195)
on conflict (key) do nothing;

-- the effective switch value (anything unknown falls back to the default)
create or replace function public._rcs88() returns text language sql stable security definer set search_path = public as $$
  select case when public.rule_txt('report_cost_source') in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then public.rule_txt('report_cost_source') else 'ledger_then_item_costs' end $$;
revoke all on function public._rcs88() from public, anon, authenticated;

-- effective CURRENT cost per item under the switch. ledger = quantity-weighted average of the stock balances (the same average the next issue would take);
-- an item with no known cost has no row.
create or replace function public._item_cost_eff88() returns table(item_id uuid, cost_price numeric, src text) language sql stable security definer set search_path = public as $$
  with m as (select public._rcs88() as m),
  lg as (
    select b.item_id as iid,
           coalesce(sum(b.qty * b.avg_cost) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0) / nullif(sum(b.qty) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0), 0),
                    (select l.unit_cost from public.stock_ledger l where l.item_id = b.item_id and coalesce(l.unit_cost, 0) > 0 and l.qty_delta > 0 order by l.id desc limit 1)) as c
    from public.stock_balance b group by b.item_id),
  ic as (select x.item_id as iid, x.cost_price as c from public.item_costs x where x.cost_price is not null)
  select z.iid, z.cp, z.s from (
    select coalesce(lg.iid, ic.iid) as iid,
           case m.m when 'item_costs' then ic.c when 'ledger_avg' then lg.c else coalesce(lg.c, ic.c) end as cp,
           case m.m when 'item_costs' then 'item_costs' when 'ledger_avg' then 'ledger' else (case when lg.c is not null then 'ledger' else 'item_costs' end) end as s
    from lg full join ic on ic.iid = lg.iid cross join m) z
  where z.cp is not null;
$$;
revoke all on function public._item_cost_eff88() from public, anon, authenticated;

-- cost per unit of ONE sale line for the report builder. Ledger: the cost the journal booked for that sale and item / the units on the sale lines
-- (so qty x cost = the journal figure); only when EVERY ledger row of that sale+item has a cost > 0. item_costs: the typed cost (count_in_business items).
-- NULL = unknown.
create or replace function public._line_cost88(p_sale uuid, p_item uuid) returns numeric language plpgsql stable security definer set search_path = public as $$
declare m text := public._rcs88(); lc numeric; lq numeric; allc boolean; n int; q numeric; v numeric;
begin
  if p_item is null then return null; end if;
  if m <> 'item_costs' and p_sale is not null then
    select count(*), bool_and(coalesce(l.unit_cost, 0) > 0), coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0), coalesce(sum(-l.qty_delta), 0) into n, allc, lc, lq
    from public.stock_ledger l where l.ref_type in ('sale', 'sale_pack') and l.ref_id = p_sale::text and l.item_id = p_item and l.reason in ('sale_out', 'issue_out');
    if n > 0 and allc and lq > 0 then
      select coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) into q
      from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
      where s.id = p_sale and e->>'item_id' = p_item::text;
      return lc / coalesce(nullif(q, 0), lq);
    end if;
  end if;
  if m <> 'ledger_avg' then
    select ic.cost_price into v from public.item_costs ic join public.items i on i.id = ic.item_id where ic.item_id = p_item and i.count_in_business;
    return v;
  end if;
  return null;
end $$;
revoke all on function public._line_cost88(uuid, uuid) from public, anon, authenticated;

-- ---------- re-created from the latest definitions (bos88 lines only) ----------
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as (select public._rcs88() as m),   -- bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
  cst as (select ic.item_id as iid, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  docs as (
    select 'sale'::text as src, x.id as doc, x.sale_date as d, x.location_id as loc, (case when x.subtotal > 0 then x.total / x.subtotal else 1 end) as f, x.lines
    from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)
    union all
    select 'return'::text, r.id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, (case when la.s > 0 then r.amount / la.s else 1 end), r.lines
    from public.sale_returns r cross join net_on
    cross join lateral (select coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end), 0) as s
                        from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e) la
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  ln as (
    select docs.src, docs.doc,
           coalesce(case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end, '00000000-0000-0000-0000-000000000000'::uuid) as k,
           coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end * docs.f), 0) as rev,
           coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as qty
    from docs cross join lateral jsonb_array_elements(case when jsonb_typeof(docs.lines) = 'array' then docs.lines else '[]'::jsonb end) e group by 1, 2, 3),
  led as (
    select docs.src, docs.doc, l.item_id as k,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0) as lc,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0) as lq,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0) as uq
    from public.stock_ledger l
    join docs on l.ref_id = docs.doc::text
             and ((docs.src = 'sale' and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out'))
               or (docs.src = 'return' and l.ref_type = 'sale_return' and l.reason = 'sale_return'))
    group by 1, 2, 3),
  keys as (select src, doc, k from ln union select src, doc, k from led),
  j as (
    select docs.src, docs.doc, docs.d, docs.loc, keys.k, coalesce(ln.qty, 0) as jq, coalesce(ln.rev, 0) as rev,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.lc, 0) end as lc, case when rcs.m = 'item_costs' then 0 else coalesce(led.lq, 0) end as lq,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.uq, 0) end as uq, ((led.lq is not null or led.uq is not null) and rcs.m <> 'item_costs') as hl,
           (case when rcs.m = 'ledger_avg' then null else c.cost_price end) as cost_price, rcs.m as m   -- bos88
    from keys join docs on docs.src = keys.src and docs.doc = keys.doc cross join rcs
    left join ln on ln.src = keys.src and ln.doc = keys.doc and ln.k = keys.k
    left join led on led.src = keys.src and led.doc = keys.doc and led.k = keys.k
    left join cst c on c.iid = keys.k),
  q as (select j.*, (case when hl then uq else jq end) as unk_q, (case when hl then lq + uq else jq end) as tot_q from j),
  w as (select q.*, (case when tot_q > 0 then rev * lq / tot_q else 0 end) as lrev from q)
  select w.src, w.doc, w.d, w.loc, nullif(w.k, '00000000-0000-0000-0000-000000000000'::uuid), w.jq, w.rev,
         w.lc + (case when w.m = 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),   -- bos88: item_costs mode = item_costs IS the primary source (no fallback flag)
         w.lrev + (case when w.m = 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.cost_price is null then w.rev - w.lrev else 0 end)
  from w;
$function$;

CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join lateral (select public._line_cost88(' || p_al || '.sale_id, ' || p_al || '.item_id) as cost_price) c on true /* bos14 count_in_business filter lives in _line_cost88 ; bos88: one cost source, see report_cost_source */' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$;

CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[];   -- bos88
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum(h.led_cogs + h.fb_cogs) as c, sum(h.unk_rev) as u from public._cogs_lines72(p_from, p_to, locs) h where h.src = 'sale' and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$;

CREATE OR REPLACE FUNCTION public.items_with_cost()
 RETURNS TABLE(item_id uuid, cost_price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.item_id, c.cost_price from public._item_cost_eff88() c   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$function$;

-- ---------- new read-only reports (cost-grant holders only) ----------
-- every active counted item with its effective cost, the source and cost_missing (true = no cost known: show "unknown", never 0)
create or replace function public.item_cost_status88() returns table(item_id uuid, code text, cost_price numeric, source text, cost_missing boolean)
language sql stable security definer set search_path = public as $$
  select i.id, i.code, e.cost_price, coalesce(e.src, 'none'), e.cost_price is null
  from public.items i left join public._item_cost_eff88() e on e.item_id = i.id
  where i.is_active and i.count_in_business and public.is_active()
    and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
         or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())))
  order by i.code;
$$;
revoke all on function public.item_cost_status88() from public, anon;
grant execute on function public.item_cost_status88() to authenticated;

-- per sold item: cost of what was sold under the switch, the part that is an estimate (typed cost used as fallback), the revenue with NO known cost, cost_missing
create or replace function public.biz_items_cost88(p_from date, p_to date, p_loc int default null)
returns table(item_id uuid, cogs numeric, fallback_cogs numeric, unknown_cost_rev numeric, cost_missing boolean)
language plpgsql stable security definer set search_path = public as $$
declare locs int[];
begin
  if not public.biz_ok() or not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  return query
    select h.item_id, round(sum(h.led_cogs + h.fb_cogs), 2), round(sum(h.fb_cogs), 2), round(sum(h.unk_rev), 2), sum(h.unk_rev) > 0.004
    from public._cogs_lines72(p_from, p_to, locs) h where h.src = 'sale' and h.item_id is not null group by h.item_id;
end $$;
revoke all on function public.biz_items_cost88(date, date, int) from public, anon;
grant execute on function public.biz_items_cost88(date, date, int) to authenticated;

-- ---------------------------------------------------------------- phase516.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase90.sql there and is already pasted on the live database under that name.
-- Renumbered to phase516.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 516 (bos90) - SCAN: photo of a bill / product list / expense slip -> DRAFT -> human review -> existing save functions.
--   Needs phase8 ... phase510 (tested on 8..84 incl. 72-79, 82, 83). Additive; paste-twice safe. No old phase file is edited. No old function is re-created.
--   Rule of the feature: a photo NEVER posts anything by itself. extract -> DRAFT (scan_jobs.extracted) -> the person edits (scan_jobs.edited) -> a person with
--   the grant scan_confirm presses Confirm -> scan_confirm() calls the EXISTING functions (save_purchase / post_purchase / quick_expense_add / item_new / item_apply
--   / save_supplier) in ONE transaction. There is no auto-confirm anywhere (no such switch, no such function). scan_min_confidence only WARNS.
--   Tables : scan_jobs (one row per photo, status uploaded|extracted|reviewed|confirmed|rejected), scan_events (append-only trail).
--   Settings (rules) : scan_enabled (switch, OFF), scan_engine (manual | browser_ocr | ai_vision, default manual), scan_min_confidence (0..1, warn-only).
--   Grants : scan_upload (take a photo + draft + review own), scan_confirm (confirm / reject others'; what it posts still needs purchase_entry etc.).
--   Functions (browser): scan_create, scan_set_extracted, scan_review_save, scan_confirm, scan_reject, scan_get, scan_list, scan_match_items, scan_match_suppliers.
--   Photos: private bucket 'photos', path SCAN/<place id>/<uuid>.jpg, signed URLs only; policies below let only the uploader / owner / scan_confirm holder read it.
-- ============================================================

-- ---------- 0. guard ----------
do $$
declare miss text := '';
begin
  if to_regprocedure('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)') is null then miss := miss || ' phase10(save_purchase)'; end if;
  if to_regprocedure('public.post_purchase(uuid,jsonb)') is null then miss := miss || ' phase10(post_purchase)'; end if;
  if to_regprocedure('public.item_new(jsonb,text)') is null then miss := miss || ' phase14(item_new)'; end if;
  if to_regprocedure('public.item_apply(uuid,jsonb,text)') is null then miss := miss || ' phase14(item_apply)'; end if;
  if to_regprocedure('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)') is null then miss := miss || ' phase50(quick_expense_add)'; end if;
  if to_regprocedure('public.save_supplier(uuid,jsonb)') is null then miss := miss || ' phase8(save_supplier)'; end if;
  if to_regprocedure('public._append_only23()') is null then miss := miss || ' phase23(_append_only23)'; end if;
  if to_regprocedure('public.rpt_cost_ok()') is null then miss := miss || ' phase21(rpt_cost_ok)'; end if;
  if to_regprocedure('public._client_lock(uuid)') is null then miss := miss || ' phase10(_client_lock)'; end if;
  if to_regclass('public.rule_grants') is null then miss := miss || ' phase8(rule_grants)'; end if;
  if miss <> '' then raise exception 'phase516 needs the earlier phases pasted first, missing:%', miss; end if;
end $$;

-- ---------- 1. settings + grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('scan_enabled', 'purchase', 'switch', 'false', null, null, null, null,
  'ছবি তুলে বিল / তালিকা ঢোকানো (Scan)', 'ছবি তুলে bill / list ঢোকানো (Scan)', 'Scan a photo of a bill or list',
  'বন্ধ = ডিফল্ট। চালু করলে ছবি তুলে খসড়া হয়; মানুষ দেখে Confirm না করলে কিছুই ঢোকে না।',
  'বন্ধ = default। চালু করলে ছবি তুলে draft হয়; মানুষ দেখে Confirm না করলে কিছুই ঢোকে না।',
  'Off = default. On: a photo becomes a DRAFT; nothing is entered until a person reviews and confirms.', 900),
 ('scan_engine', 'purchase', 'choice', '"manual"', null, '["manual","browser_ocr","ai_vision"]'::jsonb, null, null,
  'Scan-এর পাঠ-পদ্ধতি', 'Scan-এর পাঠ-method', 'Scan reading method',
  'manual = ছবির পাশে নিজে লিখবেন (সব সময় চলে)। browser_ocr = ফোনেই বিনামূল্যে পড়া (বাংলা / হাতের লেখায় দুর্বল)। ai_vision = AI (আলাদা সেটআপ ও চাবি লাগে, docs/SCAN_SETUP.md)।',
  'manual = ছবির পাশে নিজে লিখবেন (সব সময় চলে)। browser_ocr = phone-এই free পড়া (বাংলা / handwriting-এ দুর্বল)। ai_vision = AI (আলাদা setup ও key লাগে, docs/SCAN_SETUP.md)।',
  'manual = you type the lines beside the photo (always works). browser_ocr = free reading on the phone (weak on Bangla and handwriting). ai_vision = an AI service (needs the separate setup and key, see docs/SCAN_SETUP.md).', 901),
 ('scan_min_confidence', 'purchase', 'number', '0.6', 'ratio', null, 0, 1,
  'Scan: এর নিচে নিশ্চয়তা হলে সতর্কতা (আটকায় না)', 'Scan: এর নিচে confidence হলে সতর্কতা (আটকায় না)', 'Scan: warn below this confidence (never blocks)',
  'শুধু সতর্কতা। যে ঘর পাঠ-যন্ত্র কম নিশ্চিত ছিল ও আপনি বদলাননি, সেটি হলুদ হয়। Confirm আটকায় না।',
  'শুধু warning। যে field reader কম sure ছিল ও আপনি বদলাননি, সেটি হলুদ হয়। Confirm আটকায় না।',
  'Warning only. A field the reader was unsure about and you did not change is shown yellow. It never blocks Confirm.', 902)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('scan_upload', 'purchase', 90, 'বিল / তালিকার ছবি তুলে খসড়া করা', 'Bill / list-এর ছবি তুলে draft করা', 'Photograph a bill or list and prepare a draft', 'once', null),
   ('scan_confirm', 'purchase', 91, 'ছবি থেকে করা খসড়া Confirm / বাতিল করা', 'ছবি থেকে করা draft Confirm / reject করা', 'Confirm or reject a draft made from a photo', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('scan_upload', 'purchasing'), ('scan_upload', 'storekeeper'), ('scan_upload', 'showroom_manager'), ('scan_upload', 'management'),
    ('scan_confirm', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- 2. tables ----------
create table if not exists public.scan_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique,
  kind text not null check (kind in ('purchase_bill', 'product_list', 'expense', 'other')),
  location_id int not null references public.locations(id),
  image_path text not null check (length(image_path) <= 300 and image_path ~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$'),
  image_hash text check (image_hash is null or image_hash ~ '^[0-9a-f]{16,128}$'),
  status text not null default 'uploaded' check (status in ('uploaded', 'extracted', 'reviewed', 'confirmed', 'rejected')),
  engine text not null default 'manual' check (engine in ('manual', 'browser_ocr', 'ai_vision')),
  extracted jsonb,                       -- what the reader produced (never carries item / supplier ids or decisions)
  confidence jsonb,                      -- per field 0..1 (same shape as extracted; lines = array of objects)
  edited jsonb,                          -- what the person typed / corrected (this is what Confirm uses)
  extract_error text check (extract_error is null or length(extract_error) <= 300),
  note text check (note is null or length(note) <= 300),
  fp text,                               -- duplicate fingerprint (supplier|bill no|total, or place|date|head|amount)
  dups jsonb,                            -- duplicates found at the last review save
  result_type text check (result_type is null or result_type in ('purchase_bills', 'quick_expenses', 'items', 'none')),
  result_id text,                        -- id of the record the existing save function made
  result jsonb,                          -- small summary of what Confirm did
  confirm_client uuid,
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  reviewed_by uuid, reviewed_at timestamptz,
  confirmed_by uuid, confirmed_at timestamptz,
  reject_reason text check (reject_reason is null or length(reject_reason) <= 300), rejected_by uuid, rejected_at timestamptz,
  check (status <> 'confirmed' or (result_type is not null and confirmed_by is not null)),
  check (status <> 'rejected' or reject_reason is not null)
);
create unique index if not exists scan_jobs_image_uq on public.scan_jobs (image_path);
create unique index if not exists scan_jobs_result_uq on public.scan_jobs (result_type, result_id) where result_id is not null;
create index if not exists scan_jobs_status on public.scan_jobs (status, location_id, created_at desc);
create index if not exists scan_jobs_fp on public.scan_jobs (fp) where fp is not null;
create index if not exists scan_jobs_hash on public.scan_jobs (image_hash) where image_hash is not null;

create table if not exists public.scan_events (
  id bigserial primary key,
  job_id uuid not null references public.scan_jobs(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  action text not null check (action in ('created', 'extracted', 'extract_failed', 'saved', 'reviewed', 'confirmed', 'confirm_replay', 'rejected')),
  from_status text, to_status text,
  detail jsonb
);
create index if not exists scan_events_job on public.scan_events (job_id, id);

-- terminal rows never change; identity never changes; nothing is deleted
create or replace function public._scan_jobs_guard90() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – reject it instead'; end if;
  if old.status in ('confirmed', 'rejected') then raise exception 'append_only: a % scan cannot be changed', old.status; end if;
  if new.id <> old.id or new.client_id <> old.client_id or new.kind <> old.kind or new.location_id <> old.location_id or new.image_path <> old.image_path
     or new.created_by <> old.created_by or new.created_at <> old.created_at then raise exception 'identity_immutable'; end if;
  return new;
end $$;
drop trigger if exists scan_jobs_guard90 on public.scan_jobs;
create trigger scan_jobs_guard90 before update or delete on public.scan_jobs for each row execute function public._scan_jobs_guard90();
drop trigger if exists scan_jobs_guard90_t on public.scan_jobs;
create trigger scan_jobs_guard90_t before truncate on public.scan_jobs for each statement execute function public._append_only23();
drop trigger if exists scan_events_ro on public.scan_events;
create trigger scan_events_ro before update or delete on public.scan_events for each row execute function public._append_only23();
drop trigger if exists scan_events_ro_t on public.scan_events;
create trigger scan_events_ro_t before truncate on public.scan_events for each statement execute function public._append_only23();
drop trigger if exists audit_scan_jobs on public.scan_jobs;
create trigger audit_scan_jobs after insert or update on public.scan_jobs for each row execute function public.log_change('id');

alter table public.scan_jobs enable row level security;
alter table public.scan_events enable row level security;
revoke all on public.scan_jobs, public.scan_events from public, anon, authenticated;
grant select on public.scan_jobs, public.scan_events to authenticated;
revoke all on sequence public.scan_events_id_seq from public, anon, authenticated;
-- direct table reads: the owner and the person who took the photo. Reviewers use scan_get / scan_list (they hide purchase costs from people without the cost right).
drop policy if exists scan_jobs_sel on public.scan_jobs;
create policy scan_jobs_sel on public.scan_jobs for select to authenticated using (public.is_owner() or created_by = auth.uid());
drop policy if exists scan_events_sel on public.scan_events;
create policy scan_events_sel on public.scan_events for select to authenticated
  using (public.is_owner() or exists (select 1 from public.scan_jobs j where j.id = job_id and j.created_by = auth.uid()));

-- ---------- 3. visibility + photo policies ----------
create or replace function public._scan_can_see(j public.scan_jobs) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or j.created_by = auth.uid() or (public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id)));
$$;
-- purchase costs: owner, the person who typed it, or a cost-right holder (same rule as the rest of the app)
create or replace function public._scan_content_ok(j public.scan_jobs) returns boolean language sql stable security definer set search_path = public as $$
  select public._scan_can_see(j) and (j.kind <> 'purchase_bill' or public.is_owner() or j.created_by = auth.uid() or public.rpt_cost_ok());
$$;

create or replace function public._scan_photo_ok(p_name text, p_action text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare loc int;
begin
  if p_name is null or p_name !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or not public.is_active() then return false; end if;
  loc := split_part(p_name, '/', 2)::int;
  if p_action = 'enter' then return public.can_loc(loc) and public.has_grant('scan_upload', loc); end if;
  return exists (select 1 from public.scan_jobs j where j.image_path = p_name and public._scan_can_see(j));
end $$;

do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists scan_photos_insert on storage.objects';
    execute 'create policy scan_photos_insert on storage.objects for insert to authenticated with check (bucket_id = ''photos'' and public._scan_photo_ok(name, ''enter''))';
    execute 'drop policy if exists scan_photos_read on storage.objects';
    execute 'create policy scan_photos_read on storage.objects for select to authenticated using (bucket_id = ''photos'' and public._scan_photo_ok(name, ''view''))';
  end if;
  if to_regclass('storage.buckets') is not null then        -- a photo may hold personal data: the bucket must stay private
    execute 'update storage.buckets set public = false where id = ''photos'' and public is distinct from false';
  end if;
end $$;

-- ---------- 4. small parsers (everything typed by a person or read by a machine goes through these) ----------
create or replace function public._scan_txt(p text, p_len int) returns text language sql immutable set search_path = public as $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '[[:cntrl:]]+', ' ', 'g')), p_len), '');
$$;

create or replace function public._scan_num(p text, p_strict boolean, p_what text, p_max numeric default 999999999) returns numeric
language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if p is null then return null; end if;
  s := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯,৳', '0123456789'), '\s+', '', 'g');       -- Bangla digits -> ASCII; ',' the taka sign and spaces are dropped
  if s = '' then return null; end if;
  if s !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$' or s::numeric > p_max then
    if p_strict then raise exception 'bad_number: %', p_what; end if;
    return null;
  end if;
  return s::numeric;
end $$;

create or replace function public._scan_date(p text, p_strict boolean) returns date language plpgsql stable set search_path = public as $$
declare s text := translate(btrim(coalesce(p, '')), '০১২৩৪৫৬৭৮৯', '0123456789'); d date; t text;
begin
  if s = '' then return null; end if;
  begin
    if s ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$' then d := make_date(split_part(s, '-', 1)::int, split_part(s, '-', 2)::int, split_part(s, '-', 3)::int);
    elsif s ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}$' then
      t := regexp_replace(s, '[/.]', '-', 'g');
      d := make_date(split_part(t, '-', 3)::int, split_part(t, '-', 2)::int, split_part(t, '-', 1)::int);
    end if;
  exception when others then d := null;
  end;
  if d is null or d < date '2000-01-01' or d > (now() at time zone 'Asia/Dhaka')::date + 1 then
    if p_strict then raise exception 'bad_date'; end if;
    return null;
  end if;
  return d;
end $$;

create or replace function public._scan_uuid(p text) returns uuid language sql immutable set search_path = public as $$
  select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end;
$$;

-- p_human = true : a person's own corrections (may carry item_id / supplier id / decisions; bad numbers raise)
-- p_human = false: machine output (AI / OCR): ids and decisions are DROPPED (a reader can never pick an item), bad values become null, unknown keys are dropped
create or replace function public._scan_clean(p_kind text, p jsonb, p_human boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare o jsonb := '{}'::jsonb; s jsonb; ln jsonb; ls jsonb := '[]'::jsonb; sup jsonb; sid uuid; dec text; m text; hd text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_payload'; end if;
  if length(p::text) > 300000 then raise exception 'payload_too_large'; end if;
  if p ? 'supplier' then
    s := p -> 'supplier';
    if jsonb_typeof(s) = 'string' then s := jsonb_build_object('name', p ->> 'supplier'); end if;
    if jsonb_typeof(s) = 'object' then
      sup := jsonb_build_object('name', public._scan_txt(s ->> 'name', 120));
      if p_human then
        sid := public._scan_uuid(s ->> 'id');
        if sid is not null then sup := sup || jsonb_build_object('id', sid); end if;
        if (s ->> 'create') = 'true' then sup := sup || jsonb_build_object('create', true); end if;
      end if;
      o := o || jsonb_build_object('supplier', sup);
    end if;
  end if;
  o := o || jsonb_strip_nulls(jsonb_build_object(
      'bill_no', public._scan_txt(p ->> 'bill_no', 40),
      'date', public._scan_date(p ->> 'date', p_human),
      'discount', public._scan_num(p ->> 'discount', p_human, 'discount'),
      'total', public._scan_num(p ->> 'total', p_human, 'total'),
      'note', public._scan_txt(p ->> 'note', 300),
      'title', public._scan_txt(p ->> 'title', 120),
      'paid_to', public._scan_txt(p ->> 'paid_to', 120),
      'amount', public._scan_num(p ->> 'amount', p_human, 'amount')));
  hd := lower(btrim(coalesce(p ->> 'head', '')));
  hd := trim(both '_' from left(regexp_replace(hd, '[^a-z0-9_]+', '_', 'g'), 30));
  if length(hd) >= 2 then o := o || jsonb_build_object('head', hd); end if;
  m := lower(btrim(coalesce(p ->> 'mode', '')));
  if m in ('cash', 'bank', 'mobile') then o := o || jsonb_build_object('mode', m); end if;
  if (p ->> 'receipt') in ('true', 'false') then o := o || jsonb_build_object('receipt', (p ->> 'receipt')::boolean); end if;
  if p ? 'lines' then
    if jsonb_typeof(p -> 'lines') <> 'array' then raise exception 'bad_payload'; end if;
    if jsonb_array_length(p -> 'lines') > 300 then raise exception 'too_many_lines'; end if;
    for ln in select * from jsonb_array_elements(p -> 'lines') loop
      if jsonb_typeof(ln) <> 'object' then continue; end if;
      s := jsonb_strip_nulls(jsonb_build_object(
        'desc', public._scan_txt(ln ->> 'desc', 200),
        'qty', public._scan_num(ln ->> 'qty', p_human, 'qty'),
        'unit', public._scan_txt(ln ->> 'unit', 20),
        'unit_cost', public._scan_num(ln ->> 'unit_cost', p_human, 'unit_cost'),
        'amount', public._scan_num(ln ->> 'amount', p_human, 'amount')));
      if p_human then
        sid := public._scan_uuid(ln ->> 'item_id');
        dec := lower(btrim(coalesce(ln ->> 'decision', '')));
        s := s || jsonb_strip_nulls(jsonb_build_object(
          'item_id', sid,
          'decision', case when dec in ('map', 'create', 'text', 'skip') then dec end,
          'name_bn', public._scan_txt(ln ->> 'name_bn', 120),
          'name_en', public._scan_txt(ln ->> 'name_en', 120),
          'category', public._scan_txt(ln ->> 'category', 60),
          'price', public._scan_num(ln ->> 'price', true, 'price')));
      end if;
      ls := ls || jsonb_build_array(s);
    end loop;
    o := o || jsonb_build_object('lines', ls);
  end if;
  return o;
end $$;

-- confidence: numbers 0..1 only, same shape (header keys + lines array of objects); everything else dropped
create or replace function public._scan_conf(p jsonb) returns jsonb language plpgsql stable set search_path = public as $$
declare o jsonb := '{}'::jsonb; k text; v numeric; ln jsonb; ls jsonb := '[]'::jsonb; s jsonb; kk text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  if length(p::text) > 100000 then return null; end if;
  for k in select jsonb_object_keys(p) loop
    if k = 'lines' then
      if jsonb_typeof(p -> 'lines') = 'array' then
        for ln in select * from jsonb_array_elements(p -> 'lines') limit 300 loop
          s := '{}'::jsonb;
          if jsonb_typeof(ln) = 'object' then
            for kk in select jsonb_object_keys(ln) loop
              if kk in ('desc', 'qty', 'unit', 'unit_cost', 'amount') and jsonb_typeof(ln -> kk) = 'number' then
                v := (ln ->> kk)::numeric; s := s || jsonb_build_object(kk, least(1, greatest(0, v)));
              end if;
            end loop;
          end if;
          ls := ls || jsonb_build_array(s);
        end loop;
        o := o || jsonb_build_object('lines', ls);
      end if;
    elsif k in ('supplier', 'bill_no', 'date', 'discount', 'total', 'note', 'title', 'paid_to', 'amount', 'head', 'mode') and jsonb_typeof(p -> k) = 'number' then
      v := (p ->> k)::numeric; o := o || jsonb_build_object(k, least(1, greatest(0, v)));
    end if;
  end loop;
  return o;
end $$;

-- ---------- 5. fuzzy matching (existing names only; nothing is ever invented) ----------
create or replace function public._scan_norm(p text) returns text language sql immutable set search_path = public as $$
  select btrim(regexp_replace(lower(translate(coalesce(p, ''), '০১২৩৪৫৬৭৮৯', '0123456789')), '[^[:alnum:]ঀ-৿]+', ' ', 'g'));
$$;

-- 0..1 : best of (a) character-pair similarity, (b) share of the shorter name's words found in the other (0.85 max)
create or replace function public._scan_sim(a text, b text) returns numeric language plpgsql immutable set search_path = public as $$
declare na text := public._scan_norm(a); nb text := public._scan_norm(b); ba text[]; bb text[]; common int; d numeric := 0; ta text[]; tb text[]; tc int; c numeric := 0;
begin
  if na = '' or nb = '' then return 0; end if;
  if na = nb then return 1; end if;
  ba := array(select distinct substr(na, i, 2) from generate_series(1, length(na) - 1) i);
  bb := array(select distinct substr(nb, i, 2) from generate_series(1, length(nb) - 1) i);
  if cardinality(ba) > 0 and cardinality(bb) > 0 then
    common := (select count(*) from (select unnest(ba) intersect select unnest(bb)) z);
    d := 2.0 * common / (cardinality(ba) + cardinality(bb));
  end if;
  ta := array(select distinct x from unnest(string_to_array(na, ' ')) x where length(x) > 1);
  tb := array(select distinct x from unnest(string_to_array(nb, ' ')) x where length(x) > 1);
  if cardinality(ta) > 0 and cardinality(tb) > 0 then
    tc := (select count(*) from (select unnest(ta) intersect select unnest(tb)) z);
    c := 0.85 * tc / least(cardinality(ta), cardinality(tb));
  end if;
  return round(greatest(d, c), 3);
end $$;

create or replace function public.scan_match_items(p_text text, p_limit int default 5) returns table (item_id uuid, code text, name_bn text, name_en text, unit text, sell_price numeric, score numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('scan_upload') or public.has_grant('scan_confirm'))) then raise exception 'not allowed'; end if;
  if length(coalesce(p_text, '')) > 200 then raise exception 'too_long'; end if;
  return query
    select z.id, z.icode, z.nbn, z.nen, z.iunit, z.price, z.sc from (
      select i.id, i.code icode, i.name_bn nbn, i.name_en nen, i.unit iunit, i.sell_price price,
             greatest(public._scan_sim(p_text, i.name_bn), public._scan_sim(p_text, i.name_en), public._scan_sim(p_text, i.code)) sc
      from public.items i where i.is_active and not coalesce(i.hidden, false)) z
    where z.sc >= 0.35 order by z.sc desc, z.icode limit least(greatest(coalesce(p_limit, 5), 1), 10);
end $$;

create or replace function public.scan_match_suppliers(p_text text, p_limit int default 5) returns table (supplier_id uuid, name text, score numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.has_grant('scan_upload') or public.has_grant('scan_confirm'))) then raise exception 'not allowed'; end if;
  if length(coalesce(p_text, '')) > 200 then raise exception 'too_long'; end if;
  return query
    select z.id, z.sname, z.sc from (select s.id, s.name sname, public._scan_sim(p_text, s.name) sc from public.suppliers s where s.active) z
    where z.sc >= 0.35 order by z.sc desc, lower(z.sname) limit least(greatest(coalesce(p_limit, 5), 1), 10);
end $$;

-- ---------- 6. internals: totals, duplicates, warnings, trail ----------
create or replace function public._scan_sum(p_edited jsonb) returns numeric language sql immutable set search_path = public as $$
  select coalesce(sum(round(coalesce((l ->> 'qty')::numeric, 0) * coalesce((l ->> 'unit_cost')::numeric, 0), 2)), 0)
         from jsonb_array_elements(coalesce(p_edited -> 'lines', '[]'::jsonb)) l where coalesce(l ->> 'decision', '') <> 'skip';
$$;

create or replace function public._scan_event(p_job uuid, p_action text, p_from text, p_to text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.scan_events (job_id, by_user, by_staff, action, from_status, to_status, detail) values (p_job, auth.uid(), sid, p_action, p_from, p_to, p_detail);
end $$;

-- fingerprint + duplicate list for a job (same supplier + bill no + total ; same place + day + head + amount)
create or replace function public._scan_fp(j public.scan_jobs, p_edited jsonb) returns text language plpgsql stable security definer set search_path = public as $$
declare tot numeric; sid text; bn text;
begin
  if j.kind = 'purchase_bill' then
    sid := p_edited #>> '{supplier,id}';
    if sid is null then return null; end if;
    tot := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    bn := lower(coalesce(p_edited ->> 'bill_no', ''));
    return 'p|' || sid || '|' || case when bn <> '' then bn else coalesce(p_edited ->> 'date', '') end || '|' || tot::text;
  elsif j.kind = 'expense' then
    if p_edited ->> 'date' is null or p_edited ->> 'head' is null or p_edited ->> 'amount' is null then return null; end if;
    return 'e|' || j.location_id || '|' || (p_edited ->> 'date') || '|' || (p_edited ->> 'head') || '|' || ((p_edited ->> 'amount')::numeric)::text;
  end if;
  return null;
end $$;

create or replace function public._scan_dups(j public.scan_jobs, p_edited jsonb, p_fp text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '[]'::jsonb; x record; tot numeric; bn text;
begin
  if j.kind = 'purchase_bill' and p_fp is not null then
    tot := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    bn := nullif(lower(coalesce(p_edited ->> 'bill_no', '')), '');
    for x in select b.id, b.bill_no, b.total, b.status from public.purchase_bills b
             where b.kind = 'bill' and b.status <> 'void' and b.supplier_id::text = (p_edited #>> '{supplier,id}') and b.total = tot
               and (bn is null or lower(coalesce(b.bill_no, '')) = bn) and (bn is not null or b.bill_date::text = p_edited ->> 'date') loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'purchase_bill', 'id', x.id, 'bill_no', x.bill_no, 'total', x.total, 'status', x.status));
    end loop;
  elsif j.kind = 'expense' and p_fp is not null then
    for x in select q.id, q.amount from public.quick_expenses q
             where q.location_id = j.location_id and q.exp_date::text = p_edited ->> 'date' and q.head = p_edited ->> 'head' and q.amount = (p_edited ->> 'amount')::numeric and q.status = 'done' loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'quick_expense', 'id', x.id, 'amount', x.amount));
    end loop;
  end if;
  if p_fp is not null then
    for x in select s.id, s.status from public.scan_jobs s where s.fp = p_fp and s.id <> j.id and s.status <> 'rejected' loop
      r := r || jsonb_build_array(jsonb_build_object('type', 'scan', 'id', x.id, 'status', x.status));
    end loop;
  end if;
  return r;
end $$;

-- warnings only (never block): total that does not add up, unmatched lines, fields the reader was unsure about and nobody changed
create or replace function public._scan_warn(j public.scan_jobs, p_edited jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare w jsonb := '[]'::jsonb; mn numeric := coalesce(public.rule_num('scan_min_confidence'), 0.6); k text; i int; f text; ex jsonb := j.extracted; cf jsonb := j.confidence; calc numeric; ln jsonb; n int := 0; pth text[];
begin
  if j.kind = 'purchase_bill' and p_edited ? 'total' then
    calc := public._scan_sum(p_edited) - round(coalesce((p_edited ->> 'discount')::numeric, 0), 2);
    if abs(calc - (p_edited ->> 'total')::numeric) > 0.5 then
      w := w || jsonb_build_array(jsonb_build_object('code', 'total_mismatch', 'lines_total', calc, 'paper_total', (p_edited ->> 'total')::numeric));
    end if;
  end if;
  if j.kind in ('purchase_bill', 'product_list') then
    for ln in select * from jsonb_array_elements(coalesce(p_edited -> 'lines', '[]'::jsonb)) loop
      if coalesce(ln ->> 'decision', '') = '' then n := n + 1; end if;
    end loop;
    if n > 0 then w := w || jsonb_build_array(jsonb_build_object('code', 'unmatched_lines', 'n', n)); end if;
  end if;
  if cf is not null and ex is not null then
    for k in select jsonb_object_keys(cf) loop
      if k = 'lines' then
        for i in 0 .. coalesce(jsonb_array_length(cf -> 'lines'), 0) - 1 loop
          for f in select jsonb_object_keys(cf -> 'lines' -> i) loop
            if (cf -> 'lines' -> i ->> f)::numeric < mn and (p_edited -> 'lines' -> i ->> f) is not distinct from (ex -> 'lines' -> i ->> f) and (p_edited -> 'lines' -> i ->> f) is not null
              and coalesce(p_edited -> 'lines' -> i ->> 'decision', '') <> 'skip' then
              w := w || jsonb_build_array(jsonb_build_object('code', 'low_confidence', 'line', i + 1, 'field', f, 'confidence', (cf -> 'lines' -> i ->> f)::numeric));
            end if;
          end loop;
        end loop;
      else
        pth := case when k = 'supplier' then array['supplier', 'name'] else array[k] end;
        if (cf ->> k)::numeric < mn and (p_edited #>> pth) is not distinct from (ex #>> pth) and (p_edited #>> pth) is not null then
          w := w || jsonb_build_array(jsonb_build_object('code', 'low_confidence', 'field', k, 'confidence', (cf ->> k)::numeric));
        end if;
      end if;
    end loop;
  end if;
  return w;
end $$;

-- ---------- 7. browser functions ----------
-- create the job after the photo is uploaded (the client sends the Storage path it just uploaded). Idempotent on p_client.
create or replace function public.scan_create(p_client uuid, p_kind text, p_loc int, p_image_path text, p_image_hash text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; sid text; same jsonb := '[]'::jsonb; x record;
begin
  if p_client is null then raise exception 'client_required'; end if;
  perform public._client_lock(p_client);
  if not (public.is_active() and public.can_loc(p_loc) and public.has_grant('scan_upload', p_loc)) then raise exception 'not allowed'; end if;
  select * into j from public.scan_jobs where client_id = p_client;
  if found then
    if j.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('id', j.id, 'status', j.status, 'engine', j.engine, 'dup', true);
  end if;
  if not public.rule_on('scan_enabled') then raise exception 'scan_off'; end if;
  if p_kind not in ('purchase_bill', 'product_list', 'expense', 'other') then raise exception 'bad_kind'; end if;
  if p_image_path is null or p_image_path !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or length(p_image_path) > 300 then raise exception 'bad_image_path'; end if;
  if split_part(p_image_path, '/', 2)::int <> p_loc then raise exception 'bad_image_path'; end if;
  if exists (select 1 from public.scan_jobs where image_path = p_image_path) then raise exception 'image_already_used'; end if;
  if p_image_hash is not null and p_image_hash !~ '^[0-9a-f]{16,128}$' then raise exception 'bad_hash'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.scan_jobs (client_id, kind, location_id, image_path, image_hash, engine, note, created_by, created_staff)
    values (p_client, p_kind, p_loc, p_image_path, p_image_hash, coalesce(public.rule_txt('scan_engine'), 'manual'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid)
    returning * into j;
  perform public._scan_event(j.id, 'created', null, 'uploaded', jsonb_build_object('kind', p_kind, 'engine', j.engine));
  if p_image_hash is not null then       -- the same picture twice is only a warning
    for x in select s.id, s.status from public.scan_jobs s where s.image_hash = p_image_hash and s.id <> j.id and s.status <> 'rejected' and public._scan_can_see(s) loop
      same := same || jsonb_build_array(jsonb_build_object('id', x.id, 'status', x.status));
    end loop;
  end if;
  return jsonb_build_object('id', j.id, 'status', j.status, 'engine', j.engine, 'same_photo', same);
end $$;

-- the reader's result (called by the edge function with the USER'S own login, or by the browser for OCR). It can only ever make a DRAFT.
create or replace function public.scan_set_extracted(p_id uuid, p_extracted jsonb, p_confidence jsonb default null, p_engine text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ex jsonb; cf jsonb; eng text;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted') then raise exception 'not_open: %', j.status; end if;
  eng := coalesce(p_engine, j.engine);
  if eng not in ('manual', 'browser_ocr', 'ai_vision') then raise exception 'bad_engine'; end if;
  if p_error is not null then          -- the reader failed: the job stays open, the person types it by hand
    update public.scan_jobs set extract_error = left(btrim(p_error), 300), updated_at = now() where id = p_id;
    perform public._scan_event(p_id, 'extract_failed', j.status, j.status, jsonb_build_object('engine', eng, 'error', left(btrim(p_error), 300)));
    return jsonb_build_object('id', p_id, 'status', j.status, 'failed', true);
  end if;
  ex := public._scan_clean(j.kind, p_extracted, false);
  cf := public._scan_conf(p_confidence);
  update public.scan_jobs set extracted = ex, confidence = cf, engine = eng, status = 'extracted', extract_error = null, updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'extracted', j.status, 'extracted', jsonb_build_object('engine', eng, 'lines', coalesce(jsonb_array_length(ex -> 'lines'), 0)));
  return jsonb_build_object('id', p_id, 'status', 'extracted', 'extracted', case when public._scan_content_ok(j) then ex else null end);
end $$;

-- save the person's edits. p_final = false: keep working (status goes back to extracted / uploaded). p_final = true: mark as REVIEWED (ready for Confirm).
create or replace function public.scan_review_save(p_id uuid, p_edited jsonb, p_final boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ed jsonb; v_fp text; v_dups jsonb; wn jsonb; st text; prev text;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if not public._scan_content_ok(j) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted', 'reviewed') then raise exception 'not_open: %', j.status; end if;
  ed := public._scan_clean(j.kind, p_edited, true);
  v_fp := public._scan_fp(j, ed); v_dups := public._scan_dups(j, ed, v_fp); wn := public._scan_warn(j, ed);
  prev := j.status;
  st := case when coalesce(p_final, false) then 'reviewed' when j.extracted is not null then 'extracted' else 'uploaded' end;
  update public.scan_jobs set edited = ed, fp = v_fp, dups = v_dups, status = st, updated_at = now(),
         reviewed_by = case when st = 'reviewed' then auth.uid() else null end, reviewed_at = case when st = 'reviewed' then now() else null end where id = p_id;
  perform public._scan_event(p_id, case when st = 'reviewed' then 'reviewed' else 'saved' end, prev, st, jsonb_build_object('edited', ed, 'dups', jsonb_array_length(v_dups)));
  return jsonb_build_object('id', p_id, 'status', st, 'dups', v_dups, 'warnings', wn);
end $$;

-- CONFIRM: the only place where a scan becomes a record, and only through the existing save functions, in this one transaction.
create or replace function public.scan_confirm(p_id uuid, p_client uuid, p_ack_dup boolean default false, p_post boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; ed jsonb; ln jsonb; lines jsonb := '[]'::jsonb; sup uuid; supn text; r jsonb; pb jsonb; ck uuid; it uuid; patch jsonb; res jsonb := '{}'::jsonb;
        created_n int := 0; updated_n int := 0; made jsonb := '[]'::jsonb; nm text; v_dups jsonb; v_fp text; wn jsonb; dt date; qty numeric; uc numeric; kept int := 0; rid text; rtype text; simsup numeric;
begin
  if p_client is null then raise exception 'client_required'; end if;
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if j.status = 'confirmed' then
    if j.confirm_client = p_client then
      perform public._scan_event(p_id, 'confirm_replay', 'confirmed', 'confirmed', null);
      return jsonb_build_object('id', p_id, 'status', 'confirmed', 'dup', true, 'result_type', j.result_type, 'result_id', j.result_id, 'result', j.result);
    end if;
    raise exception 'already_confirmed';
  end if;
  if not (public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if not public._scan_content_ok(j) then raise exception 'not allowed'; end if;
  if j.status <> 'reviewed' or j.edited is null then raise exception 'not_reviewed'; end if;
  ed := j.edited;
  ck := md5('scan-confirm:' || j.id::text)::uuid;                  -- the same key goes to the existing save function: a replay can never save twice
  v_fp := public._scan_fp(j, ed); v_dups := public._scan_dups(j, ed, v_fp);
  if jsonb_array_length(v_dups) > 0 and not coalesce(p_ack_dup, false) then
    raise exception 'duplicate_suspect: %', v_dups::text;
  end if;
  wn := public._scan_warn(j, ed);

  if j.kind = 'purchase_bill' then
    -- supplier: picked, or created by an explicit owner action (never silently)
    sup := public._scan_uuid(ed #>> '{supplier,id}');
    if sup is null then
      supn := public._scan_txt(ed #>> '{supplier,name}', 120);
      if supn is null or (ed #>> '{supplier,create}') is distinct from 'true' then raise exception 'supplier_not_mapped'; end if;
      select coalesce(max(public._scan_sim(supn, s.name)), 0) into simsup from public.suppliers s where s.active;
      if simsup >= 0.9 then raise exception 'similar_supplier_exists'; end if;
      sup := public.save_supplier(null, jsonb_build_object('name', supn));
    end if;
    dt := public._scan_date(ed ->> 'date', true);
    if dt is null then raise exception 'bad_date'; end if;
    for ln in select * from jsonb_array_elements(coalesce(ed -> 'lines', '[]'::jsonb)) loop
      case coalesce(ln ->> 'decision', '')
        when '' then raise exception 'unmatched_lines';
        when 'skip' then continue;
        when 'map' then
          it := public._scan_uuid(ln ->> 'item_id');
          if it is null or not exists (select 1 from public.items where id = it and is_active) then raise exception 'item_not_found'; end if;
        when 'text' then
          it := null; if public._scan_txt(ln ->> 'desc', 200) is null then raise exception 'description_required'; end if;
        when 'create' then
          nm := coalesce(public._scan_txt(ln ->> 'name_en', 120), public._scan_txt(ln ->> 'name_bn', 120), public._scan_txt(ln ->> 'desc', 120));
          if nm is null then raise exception 'name_required'; end if;
          patch := jsonb_strip_nulls(jsonb_build_object('name_en', coalesce(public._scan_txt(ln ->> 'name_en', 120), case when nm !~ '[ঀ-৿]' then nm end),
                      'name_bn', coalesce(public._scan_txt(ln ->> 'name_bn', 120), case when nm ~ '[ঀ-৿]' then nm end),
                      'unit', public._scan_txt(ln ->> 'unit', 20), 'category', public._scan_txt(ln ->> 'category', 60)));
          r := public.item_new(patch, 'scan ' || left(j.id::text, 8));
          if r ->> 'status' <> 'created' then raise exception 'item_needs_approval'; end if;
          it := (r ->> 'item_id')::uuid; created_n := created_n + 1; made := made || jsonb_build_array(r);
        else raise exception 'bad_decision';
      end case;
      qty := public._scan_num(ln ->> 'qty', true, 'qty'); uc := public._scan_num(ln ->> 'unit_cost', true, 'unit_cost');
      if qty is null or qty <= 0 then raise exception 'bad_qty'; end if;
      if uc is null then raise exception 'bad_cost'; end if;
      lines := lines || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('item_id', it, 'description', case when it is null then public._scan_txt(ln ->> 'desc', 120) end,
                 'qty', qty, 'unit', public._scan_txt(ln ->> 'unit', 20), 'unit_cost', uc)));
      kept := kept + 1;
    end loop;
    if kept = 0 then raise exception 'no_lines'; end if;
    pb := public.save_purchase(ck, null, sup, j.location_id, ed ->> 'bill_no', dt, lines, coalesce((ed ->> 'discount')::numeric, 0), left('scan ' || left(j.id::text, 8) || coalesce(' | ' || (ed ->> 'note'), ''), 300), null, 'bill', null, null);
    rid := pb ->> 'id'; rtype := 'purchase_bills';
    res := jsonb_build_object('purchase', pb, 'items_created', created_n);
    if coalesce(p_post, false) then res := res || jsonb_build_object('posted', public.post_purchase(rid::uuid, null)); end if;

  elsif j.kind = 'expense' then
    dt := public._scan_date(ed ->> 'date', true);
    if dt is null then raise exception 'bad_date'; end if;
    if ed ->> 'head' is null then raise exception 'head_needed'; end if;
    if (ed ->> 'amount') is null then raise exception 'bad_amount'; end if;
    r := public.quick_expense_add(j.location_id, dt, ed ->> 'head', ed ->> 'paid_to', (ed ->> 'amount')::numeric, coalesce(ed ->> 'mode', 'cash'),
                                  coalesce((ed ->> 'receipt')::boolean, false), left('scan ' || left(j.id::text, 8) || coalesce(' | ' || (ed ->> 'note'), ''), 300), ck);
    rid := r ->> 'id'; rtype := 'quick_expenses'; res := jsonb_build_object('expense', r);

  elsif j.kind = 'product_list' then
    for ln in select * from jsonb_array_elements(coalesce(ed -> 'lines', '[]'::jsonb)) loop
      case coalesce(ln ->> 'decision', '')
        when '' then raise exception 'unmatched_lines';
        when 'skip' then continue;
        when 'text' then continue;
        when 'map' then
          it := public._scan_uuid(ln ->> 'item_id');
          if it is null or not exists (select 1 from public.items where id = it) then raise exception 'item_not_found'; end if;
          if (ln ->> 'price') is not null then
            r := public.item_apply(it, jsonb_build_object('sell_price', round((ln ->> 'price')::numeric, 2)::text), 'scan ' || left(j.id::text, 8));
            updated_n := updated_n + 1; made := made || jsonb_build_array(r);
          end if;
        when 'create' then
          nm := coalesce(public._scan_txt(ln ->> 'name_en', 120), public._scan_txt(ln ->> 'name_bn', 120), public._scan_txt(ln ->> 'desc', 120));
          if nm is null then raise exception 'name_required'; end if;
          patch := jsonb_strip_nulls(jsonb_build_object('name_en', coalesce(public._scan_txt(ln ->> 'name_en', 120), case when nm !~ '[ঀ-৿]' then nm end),
                      'name_bn', coalesce(public._scan_txt(ln ->> 'name_bn', 120), case when nm ~ '[ঀ-৿]' then nm end),
                      'unit', public._scan_txt(ln ->> 'unit', 20), 'category', public._scan_txt(ln ->> 'category', 60),
                      'sell_price', case when (ln ->> 'price') is not null then round((ln ->> 'price')::numeric, 2)::text end));
          r := public.item_new(patch, 'scan ' || left(j.id::text, 8));
          created_n := created_n + 1; made := made || jsonb_build_array(r);
        else raise exception 'bad_decision';
      end case;
    end loop;
    if created_n + updated_n = 0 then raise exception 'no_lines'; end if;
    rid := j.id::text; rtype := 'items'; res := jsonb_build_object('created', created_n, 'updated', updated_n, 'items', made);

  else                                   -- 'other' (a report / any paper): kept as a reviewed record, nothing is posted
    rid := null; rtype := 'none'; res := jsonb_build_object('note', 'archived, nothing posted');
  end if;

  update public.scan_jobs set status = 'confirmed', result_type = rtype, result_id = rid, result = res, confirm_client = p_client, confirmed_by = auth.uid(), confirmed_at = now(),
         fp = v_fp, dups = v_dups, updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'confirmed', 'reviewed', 'confirmed', jsonb_build_object('result_type', rtype, 'result_id', rid, 'ack_dup', coalesce(p_ack_dup, false), 'warnings', wn));
  return jsonb_build_object('id', p_id, 'status', 'confirmed', 'result_type', rtype, 'result_id', rid, 'result', res, 'warnings', wn);
end $$;

create or replace function public.scan_reject(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if j.status = 'rejected' then return jsonb_build_object('id', p_id, 'status', 'rejected', 'noop', true); end if;
  if j.status = 'confirmed' then raise exception 'already_confirmed'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if length(coalesce(btrim(p_reason), '')) < 3 then raise exception 'note_needed'; end if;
  update public.scan_jobs set status = 'rejected', reject_reason = left(btrim(p_reason), 300), rejected_by = auth.uid(), rejected_at = now(), updated_at = now() where id = p_id;
  perform public._scan_event(p_id, 'rejected', j.status, 'rejected', jsonb_build_object('reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', p_id, 'status', 'rejected');
end $$;

create or replace function public.scan_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j public.scan_jobs; ok boolean; ev jsonb;
begin
  select * into j from public.scan_jobs where id = p_id;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  ok := public._scan_content_ok(j);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'action', e.action, 'from', e.from_status, 'to', e.to_status, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev from public.scan_events e where e.job_id = j.id;
  return jsonb_build_object('id', j.id, 'kind', j.kind, 'location_id', j.location_id, 'status', j.status, 'engine', j.engine, 'image_path', j.image_path, 'note', j.note,
    'extract_error', j.extract_error, 'created_at', j.created_at, 'created_staff', j.created_staff, 'mine', j.created_by = auth.uid(),
    'cost_hidden', not ok, 'extracted', case when ok then j.extracted end, 'confidence', case when ok then j.confidence end, 'edited', case when ok then j.edited end,
    'dups', case when ok then j.dups end, 'warnings', case when ok and j.status in ('extracted', 'reviewed') then public._scan_warn(j, coalesce(j.edited, j.extracted, '{}'::jsonb)) end,
    'result_type', j.result_type, 'result_id', j.result_id, 'reject_reason', j.reject_reason, 'events', ev,
    'can_confirm', public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id) and ok);
end $$;

create or replace function public.scan_list(p_status text default null, p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'kind', z.kind, 'location_id', z.location_id, 'status', z.status, 'engine', z.engine, 'created_at', z.created_at,
      'created_staff', z.created_staff, 'mine', z.created_by = auth.uid(), 'dups', coalesce(jsonb_array_length(z.dups), 0), 'result_type', z.result_type) order by z.created_at desc)
    from (select j.* from public.scan_jobs j where public._scan_can_see(j) and (p_status is null or j.status = p_status) and (p_loc is null or j.location_id = p_loc)
          order by j.created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 8. privileges ----------
revoke all on function public._scan_can_see(public.scan_jobs), public._scan_content_ok(public.scan_jobs), public._scan_photo_ok(text, text),
  public._scan_txt(text, int), public._scan_num(text, boolean, text, numeric), public._scan_date(text, boolean), public._scan_uuid(text),
  public._scan_clean(text, jsonb, boolean), public._scan_conf(jsonb), public._scan_norm(text), public._scan_sim(text, text), public._scan_sum(jsonb),
  public._scan_event(uuid, text, text, text, jsonb), public._scan_fp(public.scan_jobs, jsonb), public._scan_dups(public.scan_jobs, jsonb, text), public._scan_warn(public.scan_jobs, jsonb),
  public._scan_jobs_guard90() from public, anon, authenticated;
-- storage policies run as the caller, so the photo check must stay callable by authenticated
grant execute on function public._scan_photo_ok(text, text) to authenticated;
revoke all on function public.scan_create(uuid, text, int, text, text, text), public.scan_set_extracted(uuid, jsonb, jsonb, text, text), public.scan_review_save(uuid, jsonb, boolean),
  public.scan_confirm(uuid, uuid, boolean, boolean), public.scan_reject(uuid, text), public.scan_get(uuid), public.scan_list(text, int, int),
  public.scan_match_items(text, int), public.scan_match_suppliers(text, int) from public, anon;
grant execute on function public.scan_create(uuid, text, int, text, text, text), public.scan_set_extracted(uuid, jsonb, jsonb, text, text), public.scan_review_save(uuid, jsonb, boolean),
  public.scan_confirm(uuid, uuid, boolean, boolean), public.scan_reject(uuid, text), public.scan_get(uuid), public.scan_list(text, int, int),
  public.scan_match_items(text, int), public.scan_match_suppliers(text, int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase517.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase91.sql there and is already pasted on the live database under that name.
-- Renumbered to phase517.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 517 (bos91) - Step Vis: per-user (and per-role default) VISIBILITY of every option / menu item / page.
-- Run AFTER phase512 (needs phase8 grants, audit_log, roles). Additive + idempotent (paste twice = no error). No old phase file is changed.
--
--   Vis1 user_option_view  (user_id, option_key, mode show|hide|locked, set_by, set_at)  one row = an owner choice for ONE person and ONE option.
--        role_option_view  (role_code, option_key, mode, set_by, set_at)                  the DEFAULT for everybody holding that role (a user row wins).
--        option_key is the same key nav.js already uses for favourites: 'r:<ia route>' (e.g. r:items) or 'f:<form code>' (e.g. f:10-1).
--   Vis2 Modes:  show   = as today (visible and usable when permitted)               <- default when no row exists: nobody's view changes
--                hide   = not shown at all (drawer, Home, search, bottom bar), even if permitted
--                locked = shown but disabled; tapping it opens an "ask the owner" sheet instead of the page
--   Vis3 RPCs (owner only to set): set_option_view, set_option_view_bulk, set_role_option_view, set_role_option_view_bulk.
--        my_option_views()  - the caller's own effective views (user row, else role default). option_views_for_user(user) - owner, or a person for themself.
--        client_id makes a retried call a no-op (same actor) and a clash with someone else's id an error.
--   Vis4 Audit: every real change writes one audit_log line (old -> new, by whom). set_by / set_at are kept on the row.
--
-- SECURITY NOTE (by design): this is UI tidiness ONLY. No row here grants or removes any permission. has_grant / can_do / RLS never read these tables.
-- A hidden option that the person is permitted to use still works by its direct route; a locked option the person is NOT permitted to use is still refused by the server.
-- r:home and r:optviews can never be hidden or locked (the owner cannot lock himself out of this screen).
-- ============================================================

do $$
begin
  if to_regclass('public.user_grants') is null or to_regclass('public.rule_grants') is null or to_regclass('public.audit_log') is null
     or to_regclass('public.roles') is null or to_regclass('public.role_form_perms') is null or to_regclass('public.telegram_secrets') is null then
    raise exception 'phase517 needs phase8 .. phase512 applied first (user_grants, rule_grants, audit_log, roles, telegram_secrets missing)';
  end if;
end $$;

-- =====================================================================
-- Vis1 tables
-- =====================================================================
create table if not exists public.user_option_view (
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_key text not null check (option_key ~ '^[rf]:[A-Za-z0-9_./-]{1,80}$'),
  mode text not null check (mode in ('show', 'hide', 'locked')),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (user_id, option_key)
);
create table if not exists public.role_option_view (
  role_code text not null references public.roles(code) on delete cascade,
  option_key text not null check (option_key ~ '^[rf]:[A-Za-z0-9_./-]{1,80}$'),
  mode text not null check (mode in ('show', 'hide', 'locked')),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (role_code, option_key)
);
-- remembers client_ids so a retried call does nothing twice (closed table, written only by the functions below)
create table if not exists public.option_view_ops (
  client_id uuid primary key, actor uuid not null, kind text not null, result jsonb, at timestamptz not null default now()
);

-- =====================================================================
-- helpers (not callable from the browser)
-- =====================================================================
create or replace function public._ov_mode(p_mode text) returns text language plpgsql immutable set search_path = public as $$
begin
  if p_mode is null or lower(btrim(p_mode)) = 'default' then return 'default'; end if;
  if lower(btrim(p_mode)) not in ('show', 'hide', 'locked') then raise exception 'bad_mode'; end if;
  return lower(btrim(p_mode));
end $$;

create or replace function public._ov_key(p_key text, p_mode text) returns void language plpgsql immutable set search_path = public as $$
begin
  if p_key is null or p_key !~ '^[rf]:[A-Za-z0-9_./-]{1,80}$' then raise exception 'bad_option_key'; end if;
  if p_key in ('r:home', 'r:optviews') and p_mode in ('hide', 'locked') then raise exception 'protected_option'; end if;
end $$;

-- one user choice. returns {changed, old, new}. 'default' removes the row.
create or replace function public._ov_put_user(p_user uuid, p_key text, p_mode text) returns jsonb language plpgsql security definer set search_path = public as $$
declare m text := public._ov_mode(p_mode); o text;
begin
  perform public._ov_key(p_key, m);
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  select mode into o from public.user_option_view where user_id = p_user and option_key = p_key;
  if m = 'default' then
    delete from public.user_option_view where user_id = p_user and option_key = p_key;
  else
    insert into public.user_option_view (user_id, option_key, mode, set_by, set_at) values (p_user, p_key, m, auth.uid(), now())
      on conflict (user_id, option_key) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now() where public.user_option_view.mode is distinct from excluded.mode;
  end if;
  return jsonb_build_object('key', p_key, 'old', o, 'new', case when m = 'default' then null else m end, 'changed', o is distinct from case when m = 'default' then null else m end);
end $$;

create or replace function public._ov_put_role(p_role text, p_key text, p_mode text) returns jsonb language plpgsql security definer set search_path = public as $$
declare m text := public._ov_mode(p_mode); o text;
begin
  perform public._ov_key(p_key, m);
  if not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  select mode into o from public.role_option_view where role_code = p_role and option_key = p_key;
  if m = 'default' then
    delete from public.role_option_view where role_code = p_role and option_key = p_key;
  else
    insert into public.role_option_view (role_code, option_key, mode, set_by, set_at) values (p_role, p_key, m, auth.uid(), now())
      on conflict (role_code, option_key) do update set mode = excluded.mode, set_by = excluded.set_by, set_at = now() where public.role_option_view.mode is distinct from excluded.mode;
  end if;
  return jsonb_build_object('key', p_key, 'old', o, 'new', case when m = 'default' then null else m end, 'changed', o is distinct from case when m = 'default' then null else m end);
end $$;

-- client_id: a stored result for the same actor and kind = replay it; someone else's id = error
create or replace function public._ov_replay(p_client uuid, p_kind text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.option_view_ops;
begin
  if p_client is null then return null; end if;
  select * into r from public.option_view_ops where client_id = p_client;
  if not found then return null; end if;
  if r.actor is distinct from auth.uid() or r.kind <> p_kind then raise exception 'client_id_taken'; end if;
  return coalesce(r.result, '{}'::jsonb) || jsonb_build_object('dup', true);
end $$;

create or replace function public._ov_remember(p_client uuid, p_kind text, p_result jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_client is null then return; end if;
  insert into public.option_view_ops (client_id, actor, kind, result) values (p_client, auth.uid(), p_kind, p_result) on conflict (client_id) do nothing;
end $$;

create or replace function public._ov_audit(p_table text, p_record text, p_changes jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_changes is null or jsonb_array_length(p_changes) = 0 then return; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', p_table, p_record, jsonb_build_object('changes', p_changes, 'event', 'option_view'));
end $$;

-- the effective mode of every option that has a row for this user: the user row, else the role defaults.
-- Several roles with different defaults: the LEAST restrictive wins (show > locked > hide), so a second role never takes an option away by accident.
create or replace function public._ov_effective(p_user uuid) returns table (option_key text, mode text, src text) language sql stable security definer set search_path = public as $$
  select u.option_key, u.mode, 'user'::text from public.user_option_view u where u.user_id = p_user
  union all
  select d.option_key, (array_agg(d.mode order by case d.mode when 'show' then 1 when 'locked' then 2 else 3 end))[1], 'role'::text
    from public.role_option_view d
    join public.user_roles ur on ur.role_code = d.role_code and ur.user_id = p_user
    join public.roles r on r.code = d.role_code and r.active
   where not exists (select 1 from public.user_option_view u2 where u2.user_id = p_user and u2.option_key = d.option_key)
   group by d.option_key;
$$;

-- =====================================================================
-- Vis3 setters (owner only)
-- =====================================================================
create or replace function public.set_option_view(p_user uuid, p_key text, p_mode text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user'); if rp is not null then return rp; end if;
  res := public._ov_put_user(p_user, p_key, p_mode);
  if (res->>'changed')::boolean then perform public._ov_audit('user_option_view', p_user::text, jsonb_build_array(res)); end if;
  res := res || jsonb_build_object('user_id', p_user);
  perform public._ov_remember(p_client, 'user', res);
  return res;
end $$;

-- p_items = [{"key":"r:items","mode":"hide"}, ...] (mode 'default' = remove the choice). All or nothing. At most 500.
create or replace function public.set_option_view_bulk(p_user uuid, p_items jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := public._ov_put_user(p_user, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('user_option_view', p_user::text, ch);
  res := jsonb_build_object('user_id', p_user, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'user_bulk', res);
  return res;
end $$;

create or replace function public.set_role_option_view(p_role text, p_key text, p_mode text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role'); if rp is not null then return rp; end if;
  res := public._ov_put_role(p_role, p_key, p_mode);
  if (res->>'changed')::boolean then perform public._ov_audit('role_option_view', p_role, jsonb_build_array(res)); end if;
  res := res || jsonb_build_object('role_code', p_role);
  perform public._ov_remember(p_client, 'role', res);
  return res;
end $$;

create or replace function public.set_role_option_view_bulk(p_role text, p_items jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    r := public._ov_put_role(p_role, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('role_option_view', p_role, ch);
  res := jsonb_build_object('role_code', p_role, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'role_bulk', res);
  return res;
end $$;

-- =====================================================================
-- readers
-- =====================================================================
-- the caller's own effective choices: [{"key","mode","src"}]. Empty = nothing changes for this person.
create or replace function public.my_option_views() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null or not public.is_active() then '[]'::jsonb
    else coalesce((select jsonb_agg(jsonb_build_object('key', e.option_key, 'mode', e.mode, 'src', e.src) order by e.option_key) from public._ov_effective(auth.uid()) e), '[]'::jsonb) end;
$$;

-- everything the owner screen needs for ONE person: their choices, role defaults, and what they may use today (to show granted / not granted).
-- Owner: any person. Anybody else: only themself.
create or replace function public.option_views_for_user(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; own boolean; perms jsonb; roles_ jsonb; locs jsonb; gr jsonb;
begin
  if not (public.is_owner() or (p_user is not null and p_user = auth.uid())) then raise exception 'not allowed'; end if;
  select * into p from public.profiles where id = p_user;
  if not found then raise exception 'unknown user'; end if;
  own := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  select coalesce(jsonb_agg(role_code order by role_code), '[]') into roles_ from public.user_roles where user_id = p.id;
  select coalesce(jsonb_agg(location_id order by location_id), '[]') into locs from public.user_locations where user_id = p.id;
  if p.status <> 'active' then perms := '{}'::jsonb;
  elsif own then select coalesce(jsonb_object_agg(code, jsonb_build_object('view', true, 'enter', true, 'approve', true)), '{}') into perms from public.forms;
  else
    select coalesce(jsonb_object_agg(form_code, jsonb_build_object('view', v, 'enter', e, 'approve', a)), '{}') into perms from (
      select pf.form_code, bool_or(pf.can_view) v, bool_or(pf.can_enter) e, bool_or(pf.can_approve) a
        from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p.id group by pf.form_code) x;
  end if;
  if p.status <> 'active' then gr := '[]'::jsonb;
  elsif own then select coalesce(jsonb_agg(grant_code order by grant_code), '[]') into gr from public.grant_defs;
  else
    select coalesce(jsonb_agg(c order by c), '[]') into gr from (
      select g.grant_code c from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p.id
      union
      select ug.grant_code from public.user_grants ug where ug.user_id = p.id and (ug.valid_until is null or ug.valid_until > now())) z;
  end if;
  return jsonb_build_object('user', jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'name', p.full_name, 'status', p.status),
    'is_owner', own, 'roles', roles_, 'locations', locs, 'perms', perms, 'grants', gr,
    'overrides', coalesce((select jsonb_agg(jsonb_build_object('key', u.option_key, 'mode', u.mode, 'set_at', u.set_at) order by u.option_key) from public.user_option_view u where u.user_id = p.id), '[]'::jsonb),
    'role_defaults', coalesce((select jsonb_agg(jsonb_build_object('role', d.role_code, 'key', d.option_key, 'mode', d.mode) order by d.role_code, d.option_key)
        from public.role_option_view d join public.user_roles ur on ur.role_code = d.role_code and ur.user_id = p.id), '[]'::jsonb),
    'effective', coalesce((select jsonb_agg(jsonb_build_object('key', e.option_key, 'mode', e.mode, 'src', e.src) order by e.option_key) from public._ov_effective(p.id) e), '[]'::jsonb));
end $$;

-- owner: the role defaults of one role (or all roles when null)
create or replace function public.role_option_views(p_role text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('role', d.role_code, 'key', d.option_key, 'mode', d.mode, 'set_at', d.set_at) order by d.role_code, d.option_key)
    from public.role_option_view d where p_role is null or d.role_code = p_role), '[]'::jsonb);
end $$;

-- =====================================================================
-- Vis5 permission RECOMMENDATIONS (advice only: nothing here blocks, grants or removes anything by itself)
--   perm_reco_role      role -> grants usually appropriate for it (seeded from today's rule_grants + a few plain additions; the owner can edit)
--   perm_conflict       two tokens a person should usually NOT hold together (segregation of duties). Token = a grant code | 'role:<code>' | 'module:<grant module>' | 'form:<code>' (any enter / approve right)
--   perm_reco_ignore    items the owner chose to ignore for one person
-- =====================================================================
create table if not exists public.perm_reco_role (
  role_code text not null references public.roles(code) on delete cascade,
  grant_code text not null references public.grant_defs(grant_code) on delete cascade,
  reason_bn text not null, reason_mix text not null, reason_en text not null,
  primary key (role_code, grant_code)
);
create table if not exists public.perm_conflict (
  token_a text not null, token_b text not null, check (token_a <> token_b),
  reason_bn text not null, reason_mix text not null, reason_en text not null,
  active boolean not null default true,
  primary key (token_a, token_b)
);
create table if not exists public.perm_reco_ignore (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_key text not null check (char_length(item_key) between 3 and 200),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (user_id, item_key)
);

-- seed 1: what each role already gets today is "usual for the role"
insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
  select g.role_code, g.grant_code, 'এই ভূমিকায় সাধারণত দরকার (আজকের ডিফল্ট)', 'এই role-এ সাধারণত দরকার (আজকের default)', 'Usually needed by this role (today''s default)'
    from public.rule_grants g where g.allowed and exists (select 1 from public.roles r where r.code = g.role_code) and exists (select 1 from public.grant_defs d where d.grant_code = g.grant_code)
  on conflict do nothing;
-- seed 2: a few plain additions for roles that have no default grants
insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
  select v.r, v.g, v.bn, v.mx, v.en from (values
    ('cash_controller', 'cash_move', 'ক্যাশ নিয়ন্ত্রকের কাজ: জমা ও টাকা ঢোকানো লেখা', 'Cash controller-এর কাজ: deposit ও টাকা ঢোকানো লেখা', 'A cash controller records deposits and top-ups'),
    ('cash_controller', 'view_daybook', 'দিনের খাতা মেলাতে দেখতে হয়', 'Day book মেলাতে দেখতে হয়', 'Needs the day book to tally cash'),
    ('cash_controller', 'report_cash', 'পেমেন্ট ও ওয়ালেটের রিপোর্ট দেখা', 'Payment ও wallet report দেখা', 'Needs the payments and wallets report'),
    ('party_coordinator', 'sale_without_customer', 'পার্টি/পাইকারি বিক্রিতে মোবাইল ছাড়া বাকি লাগতে পারে', 'Party/wholesale sale-এ mobile ছাড়া due লাগতে পারে', 'Party and wholesale sales may need a due sale without a mobile'),
    ('party_coordinator', 'report_orders', 'অর্ডার ও ডেলিভারির রিপোর্ট দেখা', 'Order ও delivery report দেখা', 'Needs the orders and delivery report')
  ) v(r, g, bn, mx, en)
  where exists (select 1 from public.roles r where r.code = v.r) and exists (select 1 from public.grant_defs d where d.grant_code = v.g)
  on conflict do nothing;

-- seed 3: do-not-combine pairs (the owner can switch any off or add his own)
insert into public.perm_conflict (token_a, token_b, reason_bn, reason_mix, reason_en) values
 ('purchase_entry', 'supplier_pay', 'একই লোক ক্রয় বিল লিখলে আবার সরবরাহকারীকে টাকা দেওয়ার অনুমতি না থাকাই ভালো', 'একই লোক purchase bill লিখলে আবার supplier-কে payment-এর অনুমতি না থাকাই ভালো', 'The person who enters purchase bills should not also pay suppliers'),
 ('purchase_entry', 'purchase_void', 'যে বিল লেখে সে-ই বাতিল করতে পারলে ভুল/গড়বড় ধরা কঠিন', 'যে bill লেখে সে-ই void করতে পারলে ভুল/গড়বড় ধরা কঠিন', 'If the same person enters and voids a bill, mistakes are hard to catch'),
 ('recipe_manage', 'recipe_approve', 'যে রেসিপি বদলায় সে-ই অনুমোদন করা ঠিক নয়', 'যে recipe বদলায় সে-ই approve করা ঠিক নয়', 'The person who edits a recipe should not approve it'),
 ('wastage_write_off', 'wastage_approve', 'যে নষ্ট লেখে সে-ই বড় নষ্টের অনুমোদন দেবে না', 'যে wastage লেখে সে-ই বড় wastage approve করবে না', 'The person who writes off wastage should not approve large write-offs'),
 ('sale_void', 'stock_count_adjust', 'বিক্রি বাতিল ও স্টক গণনা সমন্বয় একসাথে থাকলে ঘাটতি লুকানো যায়', 'Sale void ও stock count adjust একসাথে থাকলে ঘাটতি লুকানো যায়', 'Voiding sales and adjusting stock counts together can hide a shortage'),
 ('sell_below_zero', 'stock_count_adjust', 'স্টকের চেয়ে বেশি বিক্রি ও গণনা সমন্বয় একসাথে থাকলে হিসাব ঢাকা পড়ে', 'Stock-এর চেয়ে বেশি sale ও count adjust একসাথে থাকলে হিসাব ঢাকা পড়ে', 'Selling beyond stock and adjusting counts together can cover up differences'),
 ('cash_move', 'accounts_manage', 'যে টাকা ঢোকায়/জমা লেখে সে-ই খাতা (জার্নাল) বদলালে নজরদারি থাকে না', 'যে cash move লেখে সে-ই journal বদলালে নজরদারি থাকে না', 'The person who records cash moves should not also edit the ledger or journal'),
 ('supplier_pay', 'accounts_manage', 'সরবরাহকারীকে টাকা দেওয়া ও খাতা বদলানো একজনের হাতে ঠিক নয়', 'Supplier payment ও ledger edit একজনের হাতে ঠিক নয়', 'Paying suppliers and editing the ledger should not be in one person''s hands'),
 ('closed_period_edit', 'accounts_manage', 'বন্ধ সময়ে বদল ও খাতা বদল একসাথে থাকা ঝুঁকিপূর্ণ', 'Closed period edit ও ledger edit একসাথে থাকা ঝুঁকিপূর্ণ', 'Editing closed periods together with the ledger is risky'),
 ('view_cost', 'price_override', 'ক্রয়মূল্য দেখা ও দাম বদলানো একসাথে থাকলে ইচ্ছামতো দাম ঠিক করা যায়', 'Cost দেখা ও price বদলানো একসাথে থাকলে ইচ্ছামতো দাম ঠিক করা যায়', 'Seeing cost and changing prices together makes it easy to set prices privately'),
 ('view_cost', 'discount_over_limit', 'ক্রয়মূল্য দেখা ও সীমার বেশি ছাড় দেওয়া একসাথে না থাকাই ভালো', 'Cost দেখা ও limit-এর বেশি discount দেওয়া একসাথে না থাকাই ভালো', 'Seeing cost and giving discounts above the limit should not go together'),
 ('item_bulk', 'change_approve', 'যে একসাথে বদলায় সে-ই পরিবর্তন অনুমোদন করা ঠিক নয়', 'যে bulk বদলায় সে-ই change approve করা ঠিক নয়', 'The person who changes items in bulk should not approve changes'),
 ('payroll_manage', 'salary_manage', 'বেতন কাঠামো বানানো ও বেতন দেওয়া একজনের হাতে ঠিক নয়', 'Pay structure বানানো ও salary দেওয়া একজনের হাতে ঠিক নয়', 'Setting pay structures and paying salaries should be two people'),
 ('role:intake_bot', 'module:pos', 'ইনটেক বটের কোনো POS অধিকার থাকা উচিত নয়', 'Intake bot-এর কোনো POS right থাকা উচিত নয়', 'An intake bot should hold no POS right'),
 ('role:intake_bot', 'form:POS', 'ইনটেক বট POS-এ ঢুকতে বা বিক্রি করতে পারবে না', 'Intake bot POS-এ ঢুকতে বা sell করতে পারবে না', 'An intake bot should not enter or use POS')
on conflict do nothing;

-- all grant codes a person holds right now (role grants + personal grants not expired). The owner holds everything.
create or replace function public._ov_grants(p_user uuid) returns text[] language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id and ur.role_code = 'owner' where p.id = p_user and p.status = 'active')
      then coalesce((select array_agg(grant_code) from public.grant_defs), '{}')
    when not exists (select 1 from public.profiles where id = p_user and status = 'active') then '{}'
    else coalesce((select array_agg(c) from (
      select g.grant_code c from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p_user
      union
      select ug.grant_code from public.user_grants ug where ug.user_id = p_user and (ug.valid_until is null or ug.valid_until > now())) z), '{}') end;
$$;

-- does the person hold this token?
create or replace function public._ov_holds(p_user uuid, p_tok text, p_grants text[]) returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_tok like 'role:%' then exists (select 1 from public.user_roles where user_id = p_user and role_code = substr(p_tok, 6))
    when p_tok like 'module:%' then exists (select 1 from public.grant_defs d where d.module = substr(p_tok, 8) and d.grant_code = any (p_grants))
    when p_tok like 'form:%' then exists (select 1 from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
         join public.roles r on r.code = ur.role_code and r.active where ur.user_id = p_user and pf.form_code = substr(p_tok, 6) and (pf.can_enter or pf.can_approve))
    else p_tok = any (p_grants) end;
$$;

-- owner: advice for ONE person (never blocks anything). Items the owner ignored are listed apart, not hidden.
create or replace function public.permission_recommendations(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; gr text[]; own boolean; miss jsonb; combo jsonb; unu jsonb; ign jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into p from public.profiles where id = p_user;
  if not found then raise exception 'unknown user'; end if;
  own := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  if own then return jsonb_build_object('is_owner', true, 'recommended_missing', '[]'::jsonb, 'not_recommended_combo', '[]'::jsonb, 'unused', '[]'::jsonb, 'ignored', '[]'::jsonb); end if;
  gr := public._ov_grants(p.id);
  select coalesce(jsonb_agg(ig.item_key), '[]'::jsonb) into ign from public.perm_reco_ignore ig where ig.user_id = p.id;
  select coalesce(jsonb_agg(jsonb_build_object('item', 'miss:' || x.grant_code, 'grant', x.grant_code, 'role', x.role_code,
         'label', jsonb_build_object('bn', d.label_bn, 'mix', d.label_mix, 'en', d.label_en),
         'reason', jsonb_build_object('bn', x.reason_bn, 'mix', x.reason_mix, 'en', x.reason_en), 'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'miss:' || x.grant_code))
         order by x.grant_code), '[]'::jsonb) into miss
    from (select distinct on (r.grant_code) r.* from public.perm_reco_role r join public.user_roles ur on ur.role_code = r.role_code and ur.user_id = p.id
           join public.roles ro on ro.code = r.role_code and ro.active where not (r.grant_code = any (gr)) order by r.grant_code, r.role_code) x
    join public.grant_defs d on d.grant_code = x.grant_code;
  select coalesce(jsonb_agg(jsonb_build_object('item', 'combo:' || c.token_a || '|' || c.token_b, 'a', c.token_a, 'b', c.token_b,
         'reason', jsonb_build_object('bn', c.reason_bn, 'mix', c.reason_mix, 'en', c.reason_en), 'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'combo:' || c.token_a || '|' || c.token_b))
         order by c.token_a, c.token_b), '[]'::jsonb) into combo
    from public.perm_conflict c where c.active and public._ov_holds(p.id, c.token_a, gr) and public._ov_holds(p.id, c.token_b, gr);
  -- unused / never needed: forms the person cannot even view and has no Hide choice for yet (screens are judged by the app, which knows the screen list)
  select coalesce(jsonb_agg(jsonb_build_object('item', 'unused:f:' || f.code, 'key', 'f:' || f.code, 'suggest', 'hide',
         'reason', jsonb_build_object('bn', 'এই ফর্মের অনুমতি নেই; দরকার না হলে লুকিয়ে রাখুন', 'mix', 'এই form-এর permission নেই; দরকার না হলে hide করুন', 'en', 'No permission for this form; hide it if never needed'),
         'ignored', exists (select 1 from public.perm_reco_ignore ig where ig.user_id = p.id and ig.item_key = 'unused:f:' || f.code)) order by f.code), '[]'::jsonb) into unu
    from public.forms f
   where f.code <> 'POS' and p.status = 'active'
     and not exists (select 1 from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code join public.roles r on r.code = ur.role_code and r.active
                      where ur.user_id = p.id and pf.form_code = f.code and pf.can_view)
     and not exists (select 1 from public._ov_effective(p.id) e where e.option_key = 'f:' || f.code and e.mode = 'hide');
  return jsonb_build_object('is_owner', false, 'recommended_missing', miss, 'not_recommended_combo', combo, 'unused', unu, 'ignored', ign);
end $$;

-- owner: ignore (or stop ignoring) one advice item for one person
create or replace function public.reco_ignore_set(p_user uuid, p_item text, p_ignore boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'reco_ignore'); if rp is not null then return rp; end if;
  if p_item is null or p_item !~ '^(miss|combo|unused):.{1,190}$' then raise exception 'bad_item'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if coalesce(p_ignore, true) then
    insert into public.perm_reco_ignore (user_id, item_key, set_by) values (p_user, p_item, auth.uid()) on conflict do nothing;
  else delete from public.perm_reco_ignore where user_id = p_user and item_key = p_item; end if;
  perform public._ov_audit('perm_reco_ignore', p_user::text, jsonb_build_array(jsonb_build_object('item', p_item, 'ignore', coalesce(p_ignore, true))));
  res := jsonb_build_object('user_id', p_user, 'item', p_item, 'ignored', coalesce(p_ignore, true));
  perform public._ov_remember(p_client, 'reco_ignore', res);
  return res;
end $$;

-- owner: apply ONE advice item with one tap (audited).  miss:<grant> = give the personal grant; unused:<key> = Hide that option;
--        combo:<a>|<b> = take back the PERSONAL grant b (or a) if that one was given personally; a grant that comes from the role must be changed in the role.
create or replace function public.reco_apply(p_user uuid, p_item text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rp jsonb; res jsonb; k text; a text; b text; n int := 0;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'reco_apply'); if rp is not null then return rp; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_item like 'miss:%' then
    k := substr(p_item, 6);
    if not exists (select 1 from public.perm_reco_role r join public.user_roles ur on ur.role_code = r.role_code and ur.user_id = p_user where r.grant_code = k) then raise exception 'not_recommended'; end if;
    perform public.set_user_grant(p_user, k, null, null, true, 'recommended (bos91)');
    res := jsonb_build_object('applied', 'grant', 'grant', k);
  elsif p_item like 'unused:%' then
    k := substr(p_item, 8);
    res := jsonb_build_object('applied', 'hide') || public._ov_put_user(p_user, k, 'hide');
    if (res->>'changed')::boolean then perform public._ov_audit('user_option_view', p_user::text, jsonb_build_array(res - 'applied')); end if;
  elsif p_item like 'combo:%' then
    a := split_part(substr(p_item, 7), '|', 1); b := split_part(substr(p_item, 7), '|', 2);
    if not exists (select 1 from public.perm_conflict where token_a = a and token_b = b) then raise exception 'unknown_combo'; end if;
    delete from public.user_grants where user_id = p_user and grant_code = b and (select count(*) from public.grant_defs where grant_code = b) = 1; get diagnostics n = row_count;
    if n = 0 then delete from public.user_grants where user_id = p_user and grant_code = a and (select count(*) from public.grant_defs where grant_code = a) = 1; get diagnostics n = row_count; end if;
    if n = 0 then raise exception 'not_personal_grant'; end if;
    res := jsonb_build_object('applied', 'revoke_personal', 'removed', n);
  else raise exception 'bad_item'; end if;
  perform public._ov_audit('perm_reco_apply', p_user::text, jsonb_build_array(jsonb_build_object('item', p_item, 'result', res)));
  res := res || jsonb_build_object('user_id', p_user, 'item', p_item);
  perform public._ov_remember(p_client, 'reco_apply', res);
  return res;
end $$;

-- owner edits the advice lists
create or replace function public.reco_role_set(p_role text, p_grant text, p_on boolean, p_bn text default null, p_mix text default null, p_en text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if coalesce(p_on, true) then
    insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
      values (p_role, p_grant, coalesce(nullif(btrim(p_bn), ''), 'মালিক যোগ করেছেন'), coalesce(nullif(btrim(p_mix), ''), 'Owner যোগ করেছেন'), coalesce(nullif(btrim(p_en), ''), 'Added by the owner'))
      on conflict (role_code, grant_code) do update set reason_bn = coalesce(nullif(btrim(p_bn), ''), perm_reco_role.reason_bn), reason_mix = coalesce(nullif(btrim(p_mix), ''), perm_reco_role.reason_mix), reason_en = coalesce(nullif(btrim(p_en), ''), perm_reco_role.reason_en);
  else delete from public.perm_reco_role where role_code = p_role and grant_code = p_grant; end if;
  perform public._ov_audit('perm_reco_role', p_role, jsonb_build_array(jsonb_build_object('grant', p_grant, 'on', coalesce(p_on, true))));
end $$;

create or replace function public.reco_conflict_set(p_a text, p_b text, p_active boolean, p_bn text default null, p_mix text default null, p_en text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_a is null or p_b is null or p_a = p_b or p_a !~ '^[a-z_]+(:[A-Za-z0-9_.-]+)?$' or p_b !~ '^[a-z_]+(:[A-Za-z0-9_.-]+)?$' then raise exception 'bad_token'; end if;
  insert into public.perm_conflict (token_a, token_b, reason_bn, reason_mix, reason_en, active)
    values (p_a, p_b, coalesce(nullif(btrim(p_bn), ''), 'মালিকের নিয়ম'), coalesce(nullif(btrim(p_mix), ''), 'Owner-এর নিয়ম'), coalesce(nullif(btrim(p_en), ''), 'Owner rule'), coalesce(p_active, true))
    on conflict (token_a, token_b) do update set active = coalesce(p_active, true), reason_bn = coalesce(nullif(btrim(p_bn), ''), perm_conflict.reason_bn),
      reason_mix = coalesce(nullif(btrim(p_mix), ''), perm_conflict.reason_mix), reason_en = coalesce(nullif(btrim(p_en), ''), perm_conflict.reason_en);
  perform public._ov_audit('perm_conflict', p_a || '|' || p_b, jsonb_build_array(jsonb_build_object('active', coalesce(p_active, true))));
end $$;

alter table public.perm_reco_role enable row level security;
alter table public.perm_conflict enable row level security;
alter table public.perm_reco_ignore enable row level security;
revoke all on public.perm_reco_role, public.perm_conflict, public.perm_reco_ignore from public, anon, authenticated;
grant select on public.perm_reco_role, public.perm_conflict, public.perm_reco_ignore to authenticated;
drop policy if exists perm_reco_role_read on public.perm_reco_role;
create policy perm_reco_role_read on public.perm_reco_role for select to authenticated using (public.is_owner());
drop policy if exists perm_conflict_read on public.perm_conflict;
create policy perm_conflict_read on public.perm_conflict for select to authenticated using (public.is_owner());
drop policy if exists perm_reco_ignore_read on public.perm_reco_ignore;
create policy perm_reco_ignore_read on public.perm_reco_ignore for select to authenticated using (public.is_owner());
revoke all on function public.permission_recommendations(uuid), public.reco_ignore_set(uuid, text, boolean, uuid), public.reco_apply(uuid, text, uuid),
  public.reco_role_set(text, text, boolean, text, text, text), public.reco_conflict_set(text, text, boolean, text, text, text) from public, anon;
grant execute on function public.permission_recommendations(uuid), public.reco_ignore_set(uuid, text, boolean, uuid), public.reco_apply(uuid, text, uuid),
  public.reco_role_set(text, text, boolean, text, text, text), public.reco_conflict_set(text, text, boolean, text, text, text) to authenticated;
revoke all on function public._ov_grants(uuid), public._ov_holds(uuid, text, text[]) from public, anon, authenticated;

-- =====================================================================
-- RLS + privileges (the browser can read its own rows; every write goes through the functions)
-- =====================================================================
alter table public.user_option_view enable row level security;
alter table public.role_option_view enable row level security;
alter table public.option_view_ops enable row level security;
revoke all on public.user_option_view, public.role_option_view, public.option_view_ops from public, anon, authenticated;
grant select on public.user_option_view, public.role_option_view to authenticated;
drop policy if exists user_option_view_read on public.user_option_view;
create policy user_option_view_read on public.user_option_view for select to authenticated using (user_id = auth.uid() or public.is_owner());
drop policy if exists role_option_view_read on public.role_option_view;
create policy role_option_view_read on public.role_option_view for select to authenticated using (public.is_owner());

revoke all on function public.set_option_view(uuid, text, text, uuid), public.set_option_view_bulk(uuid, jsonb, uuid), public.set_role_option_view(text, text, text, uuid),
  public.set_role_option_view_bulk(text, jsonb, uuid), public.my_option_views(), public.option_views_for_user(uuid), public.role_option_views(text) from public, anon;
grant execute on function public.set_option_view(uuid, text, text, uuid), public.set_option_view_bulk(uuid, jsonb, uuid), public.set_role_option_view(text, text, text, uuid),
  public.set_role_option_view_bulk(text, jsonb, uuid), public.my_option_views(), public.option_views_for_user(uuid), public.role_option_views(text) to authenticated;
revoke all on function public._ov_mode(text), public._ov_key(text, text), public._ov_put_user(uuid, text, text), public._ov_put_role(text, text, text), public._ov_replay(uuid, text),
  public._ov_remember(uuid, text, jsonb), public._ov_audit(text, text, jsonb), public._ov_effective(uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ============================================================================
-- End of FRESH part 7 of 21.
