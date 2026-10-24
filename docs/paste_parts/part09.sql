-- ============================================================================
-- FRESH part 9 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase523 phase524 phase525 phase100 phase101 phase102 phase103 phase104
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase523.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase97.sql there and is already pasted on the live database under that name.
-- Renumbered to phase523.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 523 (bos97) - STEP Land: LANDED COST with every practical option (audit finding a1-F9).
--   Needs phases 72..88, 90, 91 and phase515 (the final merged bodies) pasted first - guard below. Paste order: ... phase515, phase523.
--   If phase515 is ever pasted AGAIN, paste phase523 again after it (phase515 re-creates _acct_docs without the landed-cost block).
--   Additive, paste-twice safe. Exactly ONE existing function is re-created: _acct_docs (phase515 body + two bos97 blocks at the end). One table check constraint is widened
--   (stock_ledger.reason gets 'cost_adjust'). Nothing else existing is changed. No old phase file is edited.
--
--   WHEN landed cost matters (each has a built-in option; with the mode OFF - the default - an item costs exactly its invoice price, as today):
--     imported goods; freight / transport in; loading and unloading; customs duty; insurance; clearing agent fee; bank / LC charges; packaging bought for the lot;
--     non-recoverable tax; a local purchase with a delivery charge; a late bill that arrives after the goods were already sold or consumed; returns of such a
--     purchase; a charge billed in a foreign currency (currency conversion); exchange-rate difference.
--   Rules (module purchase):
--     landed_cost_mode               off (default) | manual | per_bill | per_shipment
--     landed_alloc_default           value (default) | qty | weight | volume | manual | equal            how a charge is spread over the item lines
--     landed_late_mode               split_remaining_and_cogs (default) | post_to_remaining_stock | variance_account     what to do with the part of the lot already sold / consumed
--     landed_cost_requires_approval  warn (default) | required
--     landed_reminder_on             switch, default off  ("Landed cost not added?" list for bills of imported / flagged suppliers)
--     landed_reminder_days           number, how many days back the reminder list looks
--     landed_base_currency           text, default BDT
--   Tables (closed to the browser; every read / write is a SECURITY DEFINER function; cost-right + grant needed):
--     cost_charge_types  freight, duty, insurance, clearing, loading, unloading, bank, packaging, vat_nonrec (capitalise) / vat_recov (recoverable tax) /
--                        freight_exp, bank_exp (expense only) / delivery, fx_diff, other ... the owner can add more (landed_charge_type_save)
--     landed_costs (header: draft|approved|posted|void), landed_cost_docs (bill / GRN refs), landed_cost_lines (charges, currency + rate), landed_cost_basis (weight / volume / %
--     per purchase line), landed_cost_alloc + landed_cost_stock (APPEND-ONLY: what was spread where, what the stock ledger got), item_logistics (weight / volume per base unit),
--     landed_supplier_flags (imported / extra charges), landed_skips (append-only "no landed cost needed" notes).
--   Stock: a posted cost is added to the average cost through ledger rows with reason 'cost_adjust' (a pair: the on-hand quantity out at the old average, back in at the new
--     average, ref_type 'landed'). The ledger stays immutable and replayable (stock_reconcile and inventory_vs_gl need no change); the value of the pair is exactly the amount added.
--   Journal: _acct_docs gets 'landed_cost' (Dr inventory raw / pack / finished for the stock share, Dr landed_variance for the sold share, Dr expense / vat_input for charges that are
--     not capitalised; Cr landed_payable / pay_cash / pay_bank / pay_mobile) and 'landed_cost_void' (the counter entry). New mapping keys: vat_input, landed_payable, landed_variance.
--   RPCs: landed_preview, landed_recommendation, landed_save, landed_approve, landed_post, landed_void, landed_get, landed_list, landed_reminders, landed_return_info,
--     landed_charge_types, landed_charge_type_save, landed_logistics_set, landed_supplier_flag_set, landed_skip.
--   A posted purchase bill that has a posted landed cost cannot be voided until the landed cost is voided (trigger).
-- Tag: bos97 marks every added line inside the re-created function.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := '';
begin
  if to_regclass('public.purchase_bills') is null or to_regclass('public.purchase_lines') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.stock_balance') is null
     or to_regclass('public.journal_entries') is null or to_regclass('public.rules') is null or to_regclass('public.shadow_links') is null or to_regclass('public.suppliers') is null then
    miss := miss || ' base-tables';
  end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null or to_regprocedure('public._acct_need(text,text,boolean)') is null
     or to_regprocedure('public._acct_inv_key(text)') is null or to_regprocedure('public._acct_paykey(text,boolean)') is null or to_regprocedure('public._acct_merge(jsonb)') is null
     or to_regprocedure('public._cost_ok(integer)') is null or to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null
     or to_regprocedure('public._item_base(uuid)') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public.log_change()') is null then
    miss := miss || ' functions';
  end if;
  if to_regprocedure('public._acct_docs(date)') is null
     or (pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos89%' and pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos97%') then
    miss := miss || ' phase89';
  end if;
  if miss <> '' then
    raise exception 'phase523 needs phases 72..88, 90, 91 and phase515 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- accounts and mapping keys (additive; the owner can re-map every key) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, parent_id, normal_side, is_group, is_system, sort)
select v.code, v.bn, v.en, v.ty, (select id from public.coa_accounts where code = v.par), v.side, false, true, v.srt
from (values
  ('1240', 'VAT / কর ফেরতযোগ্য (input)', 'VAT input recoverable', 'asset', '1200', 'debit', 24),
  ('2150', 'Landed cost খরচ — দেনা', 'Landed cost charges payable', 'liability', '2000', 'credit', 102),
  ('5150', 'বিক্রি হয়ে যাওয়া মালের landed cost', 'Landed cost on goods already sold', 'expense', null, 'debit', 4150)
) v(code, bn, en, ty, par, side, srt)
on conflict (code) do nothing;
update public.coa_accounts set parent_id = (select parent_id from public.coa_accounts where code = '2100') where code = '2150' and parent_id is null and exists (select 1 from public.coa_accounts where code = '2100');

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.bn, v.en from (values
  ('vat_input', '1240', 'ফেরতযোগ্য VAT / কর (input)', 'Recoverable VAT / tax (input)'),
  ('landed_payable', '2150', 'Landed cost খরচের দেনা (পরিবহন, শুল্ক, clearing ...)', 'Landed cost charges payable (freight, duty, clearing ...)'),
  ('landed_variance', '5150', 'বিক্রি হয়ে যাওয়া মালের landed cost', 'Landed cost on goods already sold')) v(k, code, bn, en)
join public.coa_accounts a on a.code = v.code
on conflict (key) do nothing;

-- ---------- rules (every default = today's behaviour: the whole feature is OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('landed_cost_mode', 'purchase', 'choice', '"off"', null, '["off","manual","per_bill","per_shipment"]'::jsonb, null, null,
  'Landed cost (মালের সাথে আসা খরচ) যোগ করা: বন্ধ / হাতে / প্রতি বিল / প্রতি চালান', 'Landed cost (মালের সাথে আসা খরচ) যোগ করা: off / manual / per bill / per shipment', 'Landed cost (freight, duty ...) added to item cost: off / manual / per bill / per shipment',
  'বন্ধ = আজকের মতো, মালের দাম = বিলের দাম। হাতে = দরকার হলে নিজে যোগ করবেন। প্রতি বিল = প্রতিটি বিলের জন্য একটি করে। প্রতি চালান = একাধিক বিল / GRN মিলিয়ে একটি চালান (lot)। সুপারিশ: আমদানি করলে প্রতি চালান, স্থানীয় ভাড়া দিলে হাতে।',
  'off = আগের মতো, item cost = bill-এর price। manual = দরকার হলে নিজে add করবেন। per bill = প্রতি bill-এ একটি। per shipment = একাধিক bill / GRN মিলিয়ে একটি shipment (lot)। Recommended: import হলে per shipment, local ভাড়া হলে manual।',
  'off = as today, item cost = the invoice price. manual = you add it when you need it. per bill = one landed cost per bill. per shipment = one landed cost spread over several bills / GRNs of one shipment (lot). Recommended: per shipment for imports, manual for a local delivery charge.', 970),
 ('landed_alloc_default', 'purchase', 'choice', '"value"', null, '["value","qty","weight","volume","manual","equal"]'::jsonb, null, null,
  'খরচ ভাগ করার ডিফল্ট পদ্ধতি: দাম / পরিমাণ / ওজন / আয়তন / হাতে % / সমান', 'খরচ ভাগ করার default method: value / qty / weight / volume / manual % / equal', 'Default way to spread a charge over the item lines: value / qty / weight / volume / manual % / equal',
  'দাম = দামি মালের উপর বেশি। পরিমাণ = প্রতি একক সমান। ওজন বা আয়তন = ভাড়ার জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (অনুমান করা হয় না)। হাতে % = আপনি ভাগ বলে দেবেন। সমান = প্রতি লাইনে সমান। সুপারিশ: দাম, আর ভাড়ার জন্য ওজন যদি সব লাইনে জানা থাকে।',
  'value = দামি মালে বেশি। qty = প্রতি unit সমান। weight বা volume = ভাড়ার জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (অনুমান করা হয় না)। manual % = আপনি ভাগ বলে দেবেন। equal = প্রতি line-এ সমান। Recommended: value, আর freight-এর জন্য weight যদি সব line-এ জানা থাকে।',
  'value = costly goods take more. qty = the same per unit. weight or volume = best for freight, but the weight must be known (it is never guessed). manual % = you give the shares. equal = the same per line. Recommended: value, and weight for freight when every line has a known weight.', 971),
 ('landed_late_mode', 'purchase', 'choice', '"split_remaining_and_cogs"', null, '["split_remaining_and_cogs","post_to_remaining_stock","variance_account"]'::jsonb, null, null,
  'দেরিতে আসা খরচ, মাল আগেই বিক্রি হয়ে গেলে: ভাগ করে / বাকি স্টকে / variance খাতে', 'দেরিতে আসা খরচ, মাল আগেই বিক্রি হলে: split remaining + COGS / সব remaining stock-এ / variance account-এ', 'A charge that arrives after part of the lot was sold or used: split remaining stock and COGS / all to remaining stock / variance account',
  'ভাগ করে = যে অংশ এখনো আছে সেটা স্টকের দামে, যে অংশ বিক্রি হয়ে গেছে সেটা লাভ-ক্ষতির খরচে (landed variance)। বাকি স্টকে = পুরো খরচ যা আছে তার দামে জোড়া (দাম বেশি দেখাবে)। variance খাতে = স্টক ছোঁবে না, পুরোটা খরচ। সুপারিশ: ভাগ করে।',
  'split = যে অংশ এখনো আছে সেটা stock cost-এ, যে অংশ বিক্রি হয়ে গেছে সেটা landed variance-এ (P&L)। remaining stock = পুরো charge যা আছে তার cost-এ জোড়া (cost বেশি দেখাবে)। variance account = stock ছোঁবে না, পুরোটা খরচ। Recommended: split।',
  'split = the part still on the shelf goes into stock cost, the part already sold goes to the landed-cost variance (profit and loss). remaining stock = the whole charge is added to what is left (its cost looks higher). variance account = stock is not touched, the whole charge is an expense. Recommended: split.', 972),
 ('landed_cost_requires_approval', 'purchase', 'choice', '"warn"', null, '["warn","required"]'::jsonb, null, null,
  'Landed cost পোস্টের আগে অনুমোদন: সতর্কতা / বাধ্যতামূলক', 'Landed cost post-এর আগে approval: warn / required', 'Approval before a landed cost is posted: warn / required',
  'সতর্কতা = অনুমোদন ছাড়া পোস্ট করা যায়, কিন্তু একটি হলুদ সতর্কবার্তা জমে। বাধ্যতামূলক = অনুমোদিত না হলে পোস্ট হয় না, আর যিনি বানিয়েছেন তিনি নিজে অনুমোদন করতে পারেন না (মালিক পারেন)। সুপারিশ: বড় লেনদেনে বাধ্যতামূলক।',
  'warn = approval ছাড়া post করা যায়, কিন্তু একটি yellow সতর্কবার্তা জমে। required = approved না হলে post হয় না, আর যিনি বানিয়েছেন তিনি নিজে approve করতে পারেন না (owner পারেন)। Recommended: বড় amount-এ required।',
  'warn = it can be posted without approval, but a yellow warning is kept. required = it cannot be posted until approved, and the person who made it cannot approve it (the owner can). Recommended: required for big amounts.', 973),
 ('landed_reminder_on', 'purchase', 'switch', 'false', null, null, null, null,
  '"Landed cost যোগ হয়নি?" মনে করিয়ে দেওয়ার তালিকা', '"Landed cost যোগ হয়নি?" reminder list', '"Landed cost not added?" reminder list',
  'চালু করলে আমদানি / চিহ্নিত সাপ্লায়ারের বিল, যেগুলোর landed cost নেই, একটি তালিকায় দেখা যায়। বন্ধ = কোনো তালিকা নেই। সুপারিশ: আমদানি করলে চালু।',
  'চালু করলে imported / flagged supplier-এর bill, যেগুলোর landed cost নেই, একটি list-এ দেখা যায়। off = কোনো list নেই। Recommended: import করলে on।',
  'When on, bills of imported or flagged suppliers that have no landed cost are listed. Off = no list. Recommended: on if you import.', 974),
 ('landed_reminder_days', 'purchase', 'number', '30', 'days', null, 1, 3650,
  'মনে করানোর তালিকা কত দিন পিছনে দেখবে', 'Reminder list কত দিন পিছনে দেখবে', 'How many days back the reminder list looks',
  'এর চেয়ে পুরোনো বিল তালিকায় আসে না।', 'এর চেয়ে পুরোনো bill list-এ আসে না।', 'Older bills do not appear in the list.', 975),
 ('landed_base_currency', 'purchase', 'text', '"BDT"', null, null, null, null,
  'Landed cost-এর মূল মুদ্রা (কোড)', 'Landed cost-এর base currency (code)', 'Base currency of landed costs (code)',
  'অন্য মুদ্রার খরচ এই মুদ্রায় রূপান্তরিত হয়ে বসে; রূপান্তরের হার আপনি নিজে লেখেন।', 'অন্য currency-র charge এই currency-তে convert হয়ে বসে; rate আপনি নিজে লেখেন।', 'A charge in another currency is converted to this one; you type the rate yourself.', 976)
on conflict (key) do nothing;

-- ---------- grants (module purchase; the owner can always do everything) ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('landed_entry', 'purchase', 95, 'Landed cost লেখা ও পোস্ট করা', 'Landed cost লেখা ও post করা', 'Write and post landed costs (freight, duty ...)', 'once', null),
   ('landed_approve', 'purchase', 96, 'Landed cost অনুমোদন ও বাতিল (void)', 'Landed cost approve ও void করা', 'Approve and void landed costs', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('landed_entry', 'purchasing'), ('landed_entry', 'management'), ('landed_approve', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
on conflict do nothing;

-- phase517 (per-user permission recommendations) lists what each role usually needs: add the two new grants so a later paste of phase517 changes nothing
do $r$ begin
  if to_regclass('public.perm_reco_role') is not null then
    insert into public.perm_reco_role (role_code, grant_code, reason_bn, reason_mix, reason_en)
      select g.role_code, g.grant_code, 'এই ভূমিকায় সাধারণত দরকার (আজকের ডিফল্ট)', 'এই role-এ সাধারণত দরকার (আজকের default)', 'Usually needed by this role (today''s default)'
        from public.rule_grants g where g.allowed and g.grant_code in ('landed_entry', 'landed_approve') and exists (select 1 from public.roles r where r.code = g.role_code) and exists (select 1 from public.grant_defs d where d.grant_code = g.grant_code)
      on conflict do nothing;
  end if;
end $r$;

-- ---------- the stock ledger may carry a cost adjustment ----------
do $c$
declare def text; lst text;
begin
  select pg_get_constraintdef(oid) into def from pg_constraint where conname = 'stock_ledger_reason_check' and conrelid = 'public.stock_ledger'::regclass;
  if def is not null and def not like '%cost_adjust%' then
    select string_agg(quote_literal(m[1]), ',') into lst from regexp_matches(def, '''([a-z_]+)''::text', 'g') m;
    execute 'alter table public.stock_ledger drop constraint stock_ledger_reason_check';
    execute 'alter table public.stock_ledger add constraint stock_ledger_reason_check check (reason = any (array[' || lst || ',''cost_adjust'']))';
  end if;
end $c$;

-- ---------- tables ----------
create table if not exists public.cost_charge_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,32}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (length(btrim(name_en)) between 1 and 80),
  name_mix text,
  treatment text not null check (treatment in ('capitalise', 'expense_only', 'recoverable_tax')),
  expense_key text check (expense_key is null or expense_key ~ '^[a-z0-9_]{2,48}$'),
  default_alloc text check (default_alloc is null or default_alloc in ('qty', 'value', 'weight', 'volume', 'equal')),
  hint_bn text, hint_mix text, hint_en text,
  sort int not null default 0,
  active boolean not null default true,
  is_system boolean not null default false,
  created_by uuid, created_at timestamptz not null default now()
);
alter table public.cost_charge_types enable row level security;
drop policy if exists cct_read97 on public.cost_charge_types;
create policy cct_read97 on public.cost_charge_types for select to authenticated using (public.is_active());
revoke all on table public.cost_charge_types from public, anon, authenticated;
grant select on table public.cost_charge_types to authenticated;

insert into public.cost_charge_types (code, name_bn, name_en, name_mix, treatment, expense_key, default_alloc, hint_bn, hint_mix, hint_en, sort, is_system) values
 ('freight', 'পরিবহন / ভাড়া (মাল আনা)', 'Freight / transport in', 'Freight / পরিবহন ভাড়া', 'capitalise', null, 'weight', 'ওজন জানা থাকলে ওজন ধরে ভাগ করা ভালো', 'weight জানা থাকলে weight ধরে ভাগ করা ভালো', 'Best spread by weight when the weights are known', 10, true),
 ('duty', 'আমদানি শুল্ক (customs duty)', 'Customs duty', 'Customs duty / শুল্ক', 'capitalise', null, 'value', 'শুল্ক সাধারণত দামের হারে ধরা হয়', 'Duty সাধারণত value-র হারে ধরা হয়', 'Duty is normally charged on value', 20, true),
 ('insurance', 'বীমা (insurance)', 'Insurance', 'Insurance / বীমা', 'capitalise', null, 'value', 'বীমা দামের হারে', 'Insurance value-র হারে', 'Insurance follows value', 30, true),
 ('clearing', 'Clearing agent ফি', 'Clearing agent fee', 'Clearing agent fee', 'capitalise', null, 'value', 'দামের হারে, বা সমান', 'Value-র হারে, বা equal', 'By value, or equal', 40, true),
 ('loading', 'মাল তোলা (loading)', 'Loading', 'Loading / মাল তোলা', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 50, true),
 ('unloading', 'মাল নামানো (unloading)', 'Unloading', 'Unloading / মাল নামানো', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 60, true),
 ('bank', 'ব্যাংক / LC খরচ', 'Bank / LC charges', 'Bank / LC charges', 'capitalise', null, 'value', 'দামের হারে। শুধু ব্যাংকের সাধারণ চার্জ হলে "bank_exp" ব্যবহার করুন', 'Value-র হারে। শুধু সাধারণ bank charge হলে "bank_exp" ব্যবহার করুন', 'By value. For an ordinary bank fee that is not part of this lot use "bank_exp"', 70, true),
 ('packaging', 'এই চালানের জন্য কেনা প্যাকেজিং', 'Packaging bought for the lot', 'Packaging (এই lot-এর জন্য)', 'capitalise', null, 'qty', 'পরিমাণ ধরে', 'qty ধরে', 'By quantity', 80, true),
 ('vat_nonrec', 'ফেরত-অযোগ্য VAT / কর', 'Non-recoverable tax', 'Non-recoverable VAT / tax', 'capitalise', null, 'value', 'ফেরত পাওয়া যায় না, তাই মালের দামে যোগ হয়', 'ফেরত পাওয়া যায় না, তাই item cost-এ যোগ হয়', 'Cannot be claimed back, so it is part of the item cost', 90, true),
 ('vat_recov', 'ফেরতযোগ্য VAT / কর (input)', 'Recoverable tax (input)', 'Recoverable VAT / tax (input)', 'recoverable_tax', null, null, 'মালের দামে যোগ হয় না; ফেরতযোগ্য সম্পদ হিসেবে থাকে', 'Item cost-এ যোগ হয় না; recoverable asset হিসেবে থাকে', 'Not added to item cost; kept as a recoverable asset', 100, true),
 ('delivery', 'স্থানীয় ডেলিভারি চার্জ', 'Local delivery charge', 'Local delivery charge', 'capitalise', null, 'qty', 'স্থানীয় কেনায় গাড়ি / ডেলিভারি ভাড়া', 'Local purchase-এ গাড়ি / delivery ভাড়া', 'Van or delivery fee on a local purchase', 110, true),
 ('fx_diff', 'বিনিময় হারের পার্থক্য', 'Exchange-rate difference', 'Exchange-rate difference', 'capitalise', null, 'value', 'বিলের হার আর পরিশোধের হারের পার্থক্য (ঋণাত্মক হতে পারে)', 'Bill rate আর payment rate-এর পার্থক্য (negative হতে পারে)', 'Difference between the bill rate and the payment rate (may be negative)', 120, true),
 ('freight_exp', 'ভাড়া — খরচ হিসেবে (মালের দামে যোগ নয়)', 'Freight — expense only (not added to cost)', 'Freight — expense only', 'expense_only', 'exp_transport', null, 'মালের দামে যোগ হয় না; সোজা পরিবহন খরচ', 'Item cost-এ যোগ হয় না; সোজা transport expense', 'Not added to item cost; goes straight to transport expense', 130, true),
 ('bank_exp', 'ব্যাংক চার্জ — খরচ হিসেবে', 'Bank charge — expense only', 'Bank charge — expense only', 'expense_only', 'bank_charges', null, 'মালের দামে যোগ হয় না; সোজা ব্যাংক চার্জ খরচ', 'Item cost-এ যোগ হয় না; সোজা bank charge expense', 'Not added to item cost; goes straight to bank charges', 140, true),
 ('other', 'অন্যান্য landed খরচ', 'Other landed charge', 'Other landed charge', 'capitalise', null, 'value', 'যেটা অন্য কোনোটায় পড়ে না', 'যেটা অন্য কোনোটায় পড়ে না', 'Anything that fits none of the above', 900, true)
on conflict (code) do nothing;

create table if not exists public.landed_costs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  status text not null default 'draft' check (status in ('draft', 'approved', 'posted', 'void')),
  location_id int not null references public.locations(id),
  shipment_ref text check (shipment_ref is null or length(shipment_ref) <= 80),
  title text check (title is null or length(title) <= 120),
  note text check (note is null or length(note) <= 500),
  cost_date date not null default ((now() at time zone 'Asia/Dhaka')::date),
  alloc_method text not null default 'value' check (alloc_method in ('qty', 'value', 'weight', 'volume', 'manual', 'equal')),
  late_mode text check (late_mode is null or late_mode in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account')),
  late_mode_used text,
  mode_at_save text,
  total numeric not null default 0,
  post_client uuid,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  posted_by uuid, posted_at timestamptz,
  void_by uuid, void_at timestamptz, void_reason text
);
create unique index if not exists landed_costs_client97 on public.landed_costs (client_id) where client_id is not null;
create unique index if not exists landed_costs_postclient97 on public.landed_costs (post_client) where post_client is not null;
create index if not exists landed_costs_status97 on public.landed_costs (status, location_id, cost_date);

create table if not exists public.landed_cost_docs (
  cost_id uuid not null references public.landed_costs(id),
  bill_id uuid not null references public.purchase_bills(id),
  doc_type text not null default 'bill' check (doc_type in ('bill', 'grn')),
  doc_id uuid not null,
  primary key (cost_id, bill_id)
);
create index if not exists landed_cost_docs_bill97 on public.landed_cost_docs (bill_id);

create table if not exists public.landed_cost_lines (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  line_no int not null,
  charge_type text not null references public.cost_charge_types(code),
  amount_ccy numeric not null check (amount_ccy <> 0 and abs(amount_ccy) <= 1000000000000),
  ccy text not null default 'BDT' check (ccy ~ '^[A-Z]{3}$'),
  rate numeric not null default 1 check (rate > 0 and rate <= 1000000000),
  amount numeric not null check (amount <> 0 and abs(amount) <= 1000000000000),
  alloc_method text check (alloc_method is null or alloc_method in ('qty', 'value', 'weight', 'volume', 'manual', 'equal')),
  pay_mode text not null default 'payable' check (pay_mode in ('payable', 'cash', 'bank', 'mobile')),
  supplier_id uuid references public.suppliers(id),
  ref_no text check (ref_no is null or length(ref_no) <= 60),
  note text check (note is null or length(note) <= 200),
  unique (cost_id, line_no)
);

create table if not exists public.landed_cost_basis (
  cost_id uuid not null references public.landed_costs(id),
  bill_line_id bigint not null references public.purchase_lines(id),
  weight_kg numeric check (weight_kg is null or weight_kg >= 0),
  volume_l numeric check (volume_l is null or volume_l >= 0),
  manual_pct numeric check (manual_pct is null or (manual_pct >= 0 and manual_pct <= 100)),
  primary key (cost_id, bill_line_id)
);

create table if not exists public.landed_cost_alloc (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  kind text not null check (kind in ('post', 'void')),
  charge_line_id bigint not null references public.landed_cost_lines(id),
  bill_line_id bigint references public.purchase_lines(id),
  item_id uuid references public.items(id),
  location_id int not null,
  part text not null check (part in ('stock', 'cogs', 'expense', 'tax')),
  amount numeric not null,
  dr_key text not null,
  method text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists landed_cost_alloc_cost97 on public.landed_cost_alloc (cost_id, kind);
create index if not exists landed_cost_alloc_line97 on public.landed_cost_alloc (bill_line_id);

create table if not exists public.landed_cost_stock (
  id bigint generated always as identity primary key,
  cost_id uuid not null references public.landed_costs(id),
  kind text not null check (kind in ('post', 'void')),
  item_id uuid not null references public.items(id),
  location_id int not null,
  lot_qty numeric not null,
  on_hand_before numeric not null,
  avg_before numeric,
  avg_after numeric,
  stock_value numeric not null,
  cogs_value numeric not null,
  ledger_out bigint, ledger_in bigint,
  flags text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists landed_cost_stock_cost97 on public.landed_cost_stock (cost_id, kind);

create table if not exists public.item_logistics (
  item_id uuid primary key references public.items(id),
  unit_weight_kg numeric check (unit_weight_kg is null or unit_weight_kg > 0),
  unit_volume_l numeric check (unit_volume_l is null or unit_volume_l > 0),
  note text check (note is null or length(note) <= 200),
  set_by uuid, set_at timestamptz not null default now()
);

create table if not exists public.landed_supplier_flags (
  supplier_id uuid primary key references public.suppliers(id),
  kind text not null check (kind in ('imported', 'extra_charges')),
  active boolean not null default true,
  note text check (note is null or length(note) <= 200),
  set_by uuid, set_at timestamptz not null default now()
);

create table if not exists public.landed_skips (
  id bigint generated always as identity primary key,
  bill_id uuid not null references public.purchase_bills(id),
  reason text not null check (length(btrim(reason)) between 3 and 200),
  by_user uuid default auth.uid(), at timestamptz not null default now()
);
create unique index if not exists landed_skips_bill97 on public.landed_skips (bill_id);

do $t$
declare t text;
begin
  foreach t in array array['landed_costs', 'landed_cost_docs', 'landed_cost_lines', 'landed_cost_basis', 'landed_cost_alloc', 'landed_cost_stock', 'item_logistics', 'landed_supplier_flags', 'landed_skips'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);      -- the browser never touches these tables: functions only
  end loop;
end $t$;

-- ---------- triggers: append-only, locked after posting, audit ----------
create or replace function public._landed_ro97() returns trigger language plpgsql as $$
begin raise exception 'landed_append_only' using hint = 'This table is append-only: a mistake is fixed with a void, never by editing'; end $$;
revoke all on function public._landed_ro97() from public, anon, authenticated;
do $t$
declare t text;
begin
  foreach t in array array['landed_cost_alloc', 'landed_cost_stock', 'landed_skips'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro97', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public._landed_ro97()', t || '_ro97', t);
    execute format('drop trigger if exists %I on public.%I', t || '_rot97', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._landed_ro97()', t || '_rot97', t);
  end loop;
end $t$;

create or replace function public._landed_hdr_guard97() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'landed_no_delete' using hint = 'Void it instead'; end if;
  if old.status = 'void' then raise exception 'landed_locked' using hint = 'A voided landed cost cannot change'; end if;
  if old.status = 'posted' then
    if new.status <> 'void' and new.status <> 'posted' then raise exception 'landed_locked'; end if;
    if new.status = 'posted' then raise exception 'landed_locked'; end if;
    if new.location_id is distinct from old.location_id or new.total is distinct from old.total or new.cost_date is distinct from old.cost_date or new.alloc_method is distinct from old.alloc_method
       or new.late_mode_used is distinct from old.late_mode_used or new.posted_at is distinct from old.posted_at then raise exception 'landed_locked'; end if;
  end if;
  if new.status = 'draft' and old.status not in ('draft', 'approved') then raise exception 'landed_locked'; end if;
  return new;
end $$;
revoke all on function public._landed_hdr_guard97() from public, anon, authenticated;
drop trigger if exists landed_costs_guard97 on public.landed_costs;
create trigger landed_costs_guard97 before update or delete on public.landed_costs for each row execute function public._landed_hdr_guard97();

create or replace function public._landed_child_guard97() returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid := coalesce(case when tg_op = 'DELETE' then old.cost_id else new.cost_id end, null); st text;
begin
  select status into st from public.landed_costs where id = cid;
  if st is distinct from 'draft' then raise exception 'landed_locked' using hint = 'Only a draft landed cost can be edited'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke all on function public._landed_child_guard97() from public, anon, authenticated;
do $t$
declare t text;
begin
  foreach t in array array['landed_cost_docs', 'landed_cost_lines', 'landed_cost_basis'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_g97', t);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public._landed_child_guard97()', t || '_g97', t);
  end loop;
end $t$;

do $t$
declare r record;
begin
  for r in select * from (values ('landed_costs', 'id'), ('landed_cost_lines', 'id'), ('landed_cost_alloc', 'id'), ('landed_cost_stock', 'id'), ('cost_charge_types', 'code'),
                                 ('item_logistics', 'item_id'), ('landed_supplier_flags', 'supplier_id'), ('landed_skips', 'id')) v(t, k) loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || r.t || '97', r.t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || r.t || '97', r.t, r.k);
  end loop;
end $t$;

-- a posted bill that carries a posted landed cost cannot be voided before that landed cost is voided
create or replace function public._landed_bill_void_guard97() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' and exists (
       select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = old.id and c.status = 'posted') then
    raise exception 'landed_cost_posted' using hint = 'Void the landed cost of this bill first';
  end if;
  return new;
end $$;
revoke all on function public._landed_bill_void_guard97() from public, anon, authenticated;
drop trigger if exists purchase_bills_landed_guard97 on public.purchase_bills;
create trigger purchase_bills_landed_guard97 before update of status on public.purchase_bills for each row execute function public._landed_bill_void_guard97();

-- ============================================================
-- helpers (internal: closed to the browser)
-- ============================================================
create or replace function public._landed_ok97(p_loc integer, p_need text default 'entry') returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and public.can_loc(p_loc) and public._cost_ok(p_loc)
     and (public.is_owner() or case p_need when 'approve' then public.has_grant('landed_approve', p_loc)
                                  else public.has_grant('landed_entry', p_loc) or public.has_grant('landed_approve', p_loc) end);
$$;

-- weight in kg / volume in litres of ONE base unit, only when the unit itself says so (never a guess)
create or replace function public._landed_unit_w97(p_unit text) returns numeric language sql immutable as $$
  select case lower(btrim(coalesce(p_unit, ''))) when 'kg' then 1 when 'kilogram' then 1 when 'g' then 0.001 when 'gm' then 0.001 when 'gram' then 0.001
                                                 when 'ton' then 1000 when 'tonne' then 1000 when 'mt' then 1000 end;
$$;
create or replace function public._landed_unit_v97(p_unit text) returns numeric language sql immutable as $$
  select case lower(btrim(coalesce(p_unit, ''))) when 'l' then 1 when 'ltr' then 1 when 'litre' then 1 when 'liter' then 1 when 'ml' then 0.001 end;
$$;

-- exact proportional split (2 dp); the rounding remainder goes to the biggest share, so the parts always add up to the amount
create or replace function public._landed_split97(p_amt numeric, p_w numeric[]) returns numeric[]
language plpgsql immutable as $$
declare n int := coalesce(array_length(p_w, 1), 0); r numeric[] := '{}'; i int; tot numeric := 0; s numeric := 0; big int := 1;
begin
  if n = 0 then return r; end if;
  for i in 1 .. n loop
    if p_w[i] < 0 then raise exception 'bad_weight'; end if;
    tot := tot + p_w[i]; if p_w[i] > p_w[big] then big := i; end if;
  end loop;
  if tot <= 0 then raise exception 'weights_zero'; end if;
  for i in 1 .. n loop r[i] := round(p_amt * p_w[i] / tot, 2); s := s + r[i]; end loop;
  r[big] := r[big] + (p_amt - s);
  return r;
end $$;

-- the purchase lines of the chosen bills, with everything a method needs (cost data: closed to the browser)
create or replace function public._landed_rows97(p_bills uuid[], p_basis jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(z) order by z.bill_date, z.bill_no, z.line_no), '[]'::jsonb) from (
    select pl.id as bill_line_id, b.id as bill_id, b.bill_no, b.bill_date, pl.line_no, pl.item_id, it.code, it.name_bn, it.name_en, it.item_type,
           coalesce(it.base_unit, it.unit) as unit, b.location_id as loc, pl.base_qty,
           round(coalesce(pl.unit_cost_base, 0) * case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end, 6) as ucb_net,
           round(coalesce(pl.base_qty, 0) * coalesce(pl.unit_cost_base, 0) * case when b.subtotal > 0 then (b.subtotal - b.discount) / b.subtotal else 1 end, 2) as value,
           coalesce(nullif(bx.weight_kg, 0), case when lg.unit_weight_kg is not null then round(pl.base_qty * lg.unit_weight_kg, 4) end,
                    case when public._landed_unit_w97(coalesce(it.base_unit, it.unit)) is not null then round(pl.base_qty * public._landed_unit_w97(coalesce(it.base_unit, it.unit)), 4) end) as weight,
           case when nullif(bx.weight_kg, 0) is not null then 'line' when lg.unit_weight_kg is not null then 'item' when public._landed_unit_w97(coalesce(it.base_unit, it.unit)) is not null then 'unit' end as weight_src,
           coalesce(nullif(bx.volume_l, 0), case when lg.unit_volume_l is not null then round(pl.base_qty * lg.unit_volume_l, 4) end,
                    case when public._landed_unit_v97(coalesce(it.base_unit, it.unit)) is not null then round(pl.base_qty * public._landed_unit_v97(coalesce(it.base_unit, it.unit)), 4) end) as volume,
           case when nullif(bx.volume_l, 0) is not null then 'line' when lg.unit_volume_l is not null then 'item' when public._landed_unit_v97(coalesce(it.base_unit, it.unit)) is not null then 'unit' end as volume_src,
           bx.manual_pct as pct,
           (pl.item_id is not null and coalesce(it.tracked, false) and coalesce(it.count_in_business, false) and coalesce(pl.base_qty, 0) > 0) as in_scope,
           case when pl.item_id is null then 'no_item' when not coalesce(it.tracked, false) then 'not_tracked' when not coalesce(it.count_in_business, false) then 'not_counted' when coalesce(pl.base_qty, 0) <= 0 then 'no_qty' end as why_out
    from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id left join public.items it on it.id = pl.item_id
    left join lateral (select x.weight_kg, x.volume_l, x.manual_pct from jsonb_to_recordset(coalesce(p_basis, '[]'::jsonb)) as x(bill_line_id bigint, weight_kg numeric, volume_l numeric, manual_pct numeric)
                        where x.bill_line_id = pl.id limit 1) bx on true
    left join public.item_logistics lg on lg.item_id = pl.item_id
    where b.id = any (p_bills) and b.kind = 'bill' and b.status = 'posted') z;
$$;

-- charges: validate, convert the currency, add the charge type (treatment, expense key, default method)
create or replace function public._landed_norm_charges97(p_charges jsonb, p_check_active boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e jsonb; n int := 0; out jsonb := '[]'::jsonb; t public.cost_charge_types; base text := upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT'));
        cc text; rt numeric; ac numeric; am numeric; meth text; pm text; sup uuid;
begin
  if p_charges is null or jsonb_typeof(p_charges) <> 'array' then return '[]'::jsonb; end if;
  for e in select * from jsonb_array_elements(p_charges) loop
    n := n + 1;
    if jsonb_typeof(e) <> 'object' then raise exception 'bad_charge'; end if;
    select * into t from public.cost_charge_types where code = e->>'charge_type' and (active or not p_check_active);
    if not found then raise exception 'bad_charge_type'; end if;
    cc := upper(coalesce(nullif(btrim(e->>'ccy'), ''), base));
    if cc !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
    begin ac := coalesce(nullif(e->>'amount_ccy', ''), nullif(e->>'amount', ''))::numeric; exception when others then raise exception 'bad_amount'; end;
    if ac is null or ac = 0 or abs(ac) > 1000000000000 then raise exception 'bad_amount'; end if;
    if cc = base then rt := 1;
    else
      begin rt := nullif(e->>'rate', '')::numeric; exception when others then raise exception 'bad_rate'; end;
      if rt is null then raise exception 'rate_required' using hint = 'Type the exchange rate for ' || cc; end if;
      if not (rt > 0 and rt <= 1000000000) then raise exception 'bad_rate'; end if;
    end if;
    am := round(ac * rt, 2);
    if am = 0 then raise exception 'bad_amount'; end if;
    meth := nullif(e->>'alloc_method', '');
    if meth is not null and meth not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
    pm := coalesce(nullif(e->>'pay_mode', ''), 'payable');
    if pm not in ('payable', 'cash', 'bank', 'mobile') then raise exception 'bad_pay_mode'; end if;
    begin sup := nullif(e->>'supplier_id', '')::uuid; exception when others then raise exception 'bad_supplier'; end;
    if sup is not null and not exists (select 1 from public.suppliers where id = sup) then raise exception 'supplier_not_found'; end if;
    out := out || jsonb_build_object('i', n, 'charge_type', t.code, 'treatment', t.treatment, 'expense_key', coalesce(t.expense_key, 'exp_other'), 'default_alloc', t.default_alloc,
      'name_bn', t.name_bn, 'name_en', t.name_en, 'name_mix', coalesce(t.name_mix, t.name_en), 'amount_ccy', ac, 'ccy', cc, 'rate', rt, 'amount', am, 'alloc_method', meth, 'pay_mode', pm,
      'supplier_id', sup, 'ref_no', left(nullif(btrim(e->>'ref_no'), ''), 60), 'note', left(nullif(btrim(e->>'note'), ''), 200));
  end loop;
  return out;
end $$;

-- which allocation methods can be used for these (stocked) lines; unknown weight / volume / % is reported, never guessed
create or replace function public._landed_avail97(p_rows jsonb) returns jsonb
language plpgsql immutable as $$
declare r jsonb; n int := 0; q numeric := 0; v numeric := 0; w numeric := 0; vo numeric := 0; p numeric := 0;
        nw int := 0; nv int := 0; np int := 0; units text[] := '{}'; mixed boolean := false; wl jsonb := '[]'::jsonb; vl jsonb := '[]'::jsonb; pl jsonb := '[]'::jsonb; out jsonb := '{}'::jsonb;
begin
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop
    n := n + 1; q := q + coalesce((r->>'base_qty')::numeric, 0); v := v + coalesce((r->>'value')::numeric, 0);
    if not (coalesce(r->>'unit', '') = any (units)) then units := units || coalesce(r->>'unit', ''); end if;
    if r->>'weight' is null then wl := wl || to_jsonb(coalesce(r->>'code', '?')); else nw := nw + 1; w := w + (r->>'weight')::numeric; end if;
    if r->>'volume' is null then vl := vl || to_jsonb(coalesce(r->>'code', '?')); else nv := nv + 1; vo := vo + (r->>'volume')::numeric; end if;
    if r->>'pct' is null then pl := pl || to_jsonb(coalesce(r->>'code', '?')); else np := np + 1; p := p + (r->>'pct')::numeric; end if;
  end loop;
  mixed := coalesce(array_length(units, 1), 0) > 1;
  out := jsonb_build_object(
    'lines', n,
    'qty', jsonb_build_object('ok', n = 1 or q > 0, 'why', case when n > 1 and q <= 0 then 'qty_zero' end, 'mixed_units', mixed),
    'value', jsonb_build_object('ok', n = 1 or v > 0, 'why', case when n > 1 and v <= 0 then 'value_zero' end),
    'weight', jsonb_build_object('ok', n = 1 or (nw = n and w > 0), 'why', case when n > 1 and nw < n then 'weight_unknown' when n > 1 and w <= 0 then 'weight_zero' end, 'missing', case when n > 1 and nw < n then wl else '[]'::jsonb end),
    'volume', jsonb_build_object('ok', n = 1 or (nv = n and vo > 0), 'why', case when n > 1 and nv < n then 'volume_unknown' when n > 1 and vo <= 0 then 'volume_zero' end, 'missing', case when n > 1 and nv < n then vl else '[]'::jsonb end),
    'manual', jsonb_build_object('ok', n = 1 or (np = n and abs(p - 100) <= 0.01), 'why', case when n > 1 and np < n then 'manual_missing' when n > 1 and abs(p - 100) > 0.01 then 'manual_sum' end, 'sum', p, 'missing', case when n > 1 and np < n then pl else '[]'::jsonb end),
    'equal', jsonb_build_object('ok', n >= 1, 'why', case when n < 1 then 'no_lines' end));
  return out;
end $$;

-- the weights of one method over the stocked lines (error method_unavailable:<m> when a number is unknown)
create or replace function public._landed_weights97(p_rows jsonb, p_method text, p_avail jsonb) returns numeric[]
language plpgsql immutable as $$
declare r jsonb; w numeric[] := '{}'; n int := 0;
begin
  if p_method not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  if not coalesce((p_avail->p_method->>'ok')::boolean, false) then raise exception 'method_unavailable:%', p_method using detail = coalesce(p_avail->p_method->>'why', ''); end if;
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop
    n := n + 1;
    if (p_avail->>'lines')::int = 1 then w[n] := 1;
    else w[n] := case p_method when 'qty' then (r->>'base_qty')::numeric when 'value' then (r->>'value')::numeric when 'weight' then (r->>'weight')::numeric
                               when 'volume' then (r->>'volume')::numeric when 'manual' then (r->>'pct')::numeric else 1 end;
    end if;
  end loop;
  return w;
end $$;

-- spread every charge: [{ci, bl (bill line id or null), amt, method}] . method_force replaces every method (used for the side-by-side preview)
create or replace function public._landed_spread97(p_rows jsonb, p_charges jsonb, p_header_method text, p_force text, p_avail jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; out jsonb := '[]'::jsonb; ids bigint[] := '{}'; r jsonb; n int := 0; w numeric[]; parts numeric[]; m text; i int;
begin
  for r in select * from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean loop n := n + 1; ids[n] := (r->>'bill_line_id')::bigint; end loop;
  for c in select * from jsonb_array_elements(p_charges) loop
    if c->>'treatment' <> 'capitalise' then
      out := out || jsonb_build_object('ci', (c->>'i')::int, 'bl', null, 'amt', (c->>'amount')::numeric, 'method', null);
      continue;
    end if;
    if n = 0 then raise exception 'no_stock_lines' using hint = 'None of the lines is a counted, tracked item'; end if;
    m := coalesce(p_force, nullif(c->>'alloc_method', ''), p_header_method);
    w := public._landed_weights97(p_rows, m, p_avail);
    parts := public._landed_split97((c->>'amount')::numeric, w);
    for i in 1 .. n loop
      out := out || jsonb_build_object('ci', (c->>'i')::int, 'bl', ids[i], 'amt', parts[i], 'method', m);
    end loop;
  end loop;
  return out;
end $$;

-- the stock plan: per item and place, how much of the capitalised charge goes into the stock cost and how much is already sold (variance). Reads balances (the poster locks them first).
create or replace function public._landed_plan97(p_rows jsonb, p_charges jsonb, p_spread jsonb, p_late text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g record; items jsonb := '[]'::jsonb; rowsout jsonb := '[]'::jsonb; a record; bal public.stock_balance; on_hand numeric; av numeric; q numeric; amt numeric; stk numeric; flag text; late_q numeric;
        phi numeric; s numeric; sum_s numeric; ik text; ct jsonb; avg_after numeric; mode_ text := coalesce(p_late, 'split_remaining_and_cogs');
begin
  if mode_ not in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account') then raise exception 'bad_late_mode'; end if;
  -- charges that are not capitalised: one row each, no stock
  for a in select s2 from jsonb_array_elements(p_spread) s2 where (s2->>'bl') is null loop
    ct := (select c from jsonb_array_elements(p_charges) c where (c->>'i')::int = (a.s2->>'ci')::int);
    rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', null, 'item_id', null, 'loc', (select (x->>'loc')::int from jsonb_array_elements(p_rows) x limit 1),
      'part', case when ct->>'treatment' = 'recoverable_tax' then 'tax' else 'expense' end, 'amount', (a.s2->>'amt')::numeric,
      'dr_key', case when ct->>'treatment' = 'recoverable_tax' then 'vat_input' else ct->>'expense_key' end, 'method', null);
  end loop;
  -- stocked items
  for g in
    select (x->>'item_id')::uuid as item_id, (x->>'loc')::int as loc, max(x->>'item_type') as item_type, sum((x->>'base_qty')::numeric) as q
      from jsonb_array_elements(p_rows) x where (x->>'in_scope')::boolean group by 1, 2 order by 1, 2 loop
    select * into bal from public.stock_balance where item_id = g.item_id and location_id = g.loc;
    on_hand := greatest(coalesce(bal.qty, 0), 0); av := bal.avg_cost; q := g.q; flag := null;
    select coalesce(sum((s2->>'amt')::numeric), 0) into amt from jsonb_array_elements(p_spread) s2
      where (s2->>'bl') is not null and (s2->>'bl')::bigint in (select (x->>'bill_line_id')::bigint from jsonb_array_elements(p_rows) x where (x->>'item_id')::uuid = g.item_id and (x->>'loc')::int = g.loc and (x->>'in_scope')::boolean);
    late_q := greatest(q - on_hand, 0);
    if amt = 0 then stk := 0;
    elsif late_q <= 0.0005 then stk := amt;
    elsif mode_ = 'post_to_remaining_stock' then stk := case when on_hand > 0 then amt else 0 end;
    elsif mode_ = 'split_remaining_and_cogs' then stk := round(amt * on_hand / q, 2);
    else stk := 0; end if;
    if stk <> 0 and (on_hand <= 0 or av is null) then stk := 0; flag := case when av is null and on_hand > 0 then 'avg_unknown' else 'no_stock_left' end; end if;
    if stk < 0 and on_hand > 0 and av is not null then
      if -stk > round(on_hand * av, 2) then stk := -round(on_hand * av, 2); flag := 'credit_capped'; end if;
    end if;
    if late_q > 0.0005 then flag := coalesce(flag || ',', '') || 'late'; end if;
    phi := case when amt = 0 then 0 else stk / amt end; sum_s := 0;
    ik := public._acct_inv_key(g.item_type);
    for a in select s2, x from jsonb_array_elements(p_spread) s2 join jsonb_array_elements(p_rows) x on (s2->>'bl') is not null and (s2->>'bl')::bigint = (x->>'bill_line_id')::bigint
               where (x->>'item_id')::uuid = g.item_id and (x->>'loc')::int = g.loc and (x->>'in_scope')::boolean loop
      s := round((a.s2->>'amt')::numeric * phi, 2); sum_s := sum_s + s;
      if s <> 0 then
        rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', (a.s2->>'bl')::bigint, 'item_id', g.item_id, 'loc', g.loc, 'part', 'stock', 'amount', s, 'dr_key', ik, 'method', a.s2->>'method');
      end if;
      if (a.s2->>'amt')::numeric - s <> 0 then
        rowsout := rowsout || jsonb_build_object('ci', (a.s2->>'ci')::int, 'bl', (a.s2->>'bl')::bigint, 'item_id', g.item_id, 'loc', g.loc, 'part', 'cogs', 'amount', (a.s2->>'amt')::numeric - s, 'dr_key', 'landed_variance', 'method', a.s2->>'method');
      end if;
    end loop;
    avg_after := case when sum_s <> 0 and on_hand > 0 and av is not null then round((on_hand * av + sum_s) / on_hand, 6) end;
    items := items || jsonb_build_object('item_id', g.item_id, 'loc', g.loc, 'lot_qty', q, 'on_hand', on_hand, 'avg', av, 'late_qty', late_q, 'amount', amt, 'stock', sum_s, 'cogs', amt - sum_s, 'avg_after', avg_after, 'flags', flag);
  end loop;
  return jsonb_build_object('items', items, 'rows', rowsout, 'late_mode', mode_);
end $$;
revoke all on function public._landed_ok97(integer, text), public._landed_unit_w97(text), public._landed_unit_v97(text), public._landed_split97(numeric, numeric[]), public._landed_rows97(uuid[], jsonb),
  public._landed_norm_charges97(jsonb, boolean), public._landed_avail97(jsonb), public._landed_weights97(jsonb, text, jsonb), public._landed_spread97(jsonb, jsonb, text, text, jsonb),
  public._landed_plan97(jsonb, jsonb, jsonb, text) from public, anon, authenticated;

-- ============================================================
-- messages (bn / mix / en) used by the recommendation. English strings carry no Bangla character.
-- ============================================================
create or replace function public._landed_msg97(p_code text, p_a text default null, p_b text default null) returns jsonb
language sql immutable as $$
  select case p_code
    when 'm_weight' then jsonb_build_object('bn', 'Freight ওজন ধরে ভাগ করাই ভালো: সব line-এর ওজন জানা আছে।', 'mix', 'Freight weight ধরে ভাগ করাই ভালো: সব line-এর weight জানা আছে।', 'en', 'Freight is best spread by weight: every line has a known weight.')
    when 'm_volume' then jsonb_build_object('bn', 'আয়তন ধরে ভাগ করা ভালো: সব line-এর আয়তন জানা আছে।', 'mix', 'Volume ধরে ভাগ করা ভালো: সব line-এর volume জানা আছে।', 'en', 'Best spread by volume: every line has a known volume.')
    when 'm_value' then jsonb_build_object('bn', 'দাম ধরে ভাগ: দামি মালের উপর খরচ বেশি পড়ে।', 'mix', 'Value ধরে ভাগ: দামি মালে charge বেশি পড়ে।', 'en', 'Spread by value: costly goods carry more of the charge.')
    when 'm_qty' then jsonb_build_object('bn', 'পরিমাণ ধরে ভাগ: প্রতি একক সমান খরচ।', 'mix', 'Qty ধরে ভাগ: প্রতি unit সমান charge।', 'en', 'Spread by quantity: every unit carries the same.')
    when 'm_equal' then jsonb_build_object('bn', 'প্রতি line-এ সমান ভাগ।', 'mix', 'প্রতি line-এ equal ভাগ।', 'en', 'The same share for every line.')
    when 'm_weight_fallback' then jsonb_build_object('bn', 'ওজন ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর ওজন জানা নেই (অনুমান করা হয়নি), তাই দাম ধরা হলো। ওজন লিখলে ওজন ধরে ভাগ হবে।', 'mix', 'Weight ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর weight জানা নেই (অনুমান করা হয়নি), তাই value ধরা হলো। Weight লিখলে weight ধরে ভাগ হবে।', 'en', 'Weight would be best, but the weight of some lines is unknown (it is never guessed), so value is used. Enter the weights to spread by weight.')
    when 'm_volume_fallback' then jsonb_build_object('bn', 'আয়তন ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর আয়তন জানা নেই (অনুমান করা হয়নি), তাই দাম ধরা হলো।', 'mix', 'Volume ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর volume জানা নেই (অনুমান করা হয়নি), তাই value ধরা হলো।', 'en', 'Volume would be best, but the volume of some lines is unknown (it is never guessed), so value is used.')
    when 'm_qty_mixed' then jsonb_build_object('bn', 'Line গুলোর একক আলাদা (কেজি, পিস ...), তাই পরিমাণ ধরে ভাগ অর্থহীন; দাম ধরা হলো।', 'mix', 'Line গুলোর unit আলাদা (kg, pcs ...), তাই qty ধরে ভাগ অর্থহীন; value ধরা হলো।', 'en', 'The lines use different units (kg, pieces ...), so a split by quantity is not meaningful; value is used.')
    when 'm_single' then jsonb_build_object('bn', 'শুধু একটি stock line আছে: পুরো খরচ সেটার উপরই পড়বে, পদ্ধতি যাই হোক।', 'mix', 'শুধু একটি stock line আছে: পুরো charge সেটার উপরই পড়বে, method যাই হোক।', 'en', 'There is only one stocked line: the whole charge goes to it, whatever the method.')
    when 'w_late' then jsonb_build_object('bn', 'এই lot-এর ' || coalesce(p_a, '?') || ' একক আগেই বিক্রি বা ব্যবহার হয়ে গেছে। "ভাগ করে" পদ্ধতিতে বিক্রি হওয়া অংশ লাভ-ক্ষতিতে (landed variance) যাবে, শুধু বাকিটা stock cost-এ।', 'mix', 'এই lot-এর ' || coalesce(p_a, '?') || ' unit আগেই sold বা used হয়ে গেছে। Split করলে sold অংশ P&L-এ (landed variance) যাবে, শুধু বাকিটা stock cost-এ।', 'en', coalesce(p_a, '?') || ' units of this lot are already sold or used. With a split, the sold part goes to the landed-cost variance (profit and loss) and only the rest into stock cost.')
    when 'w_late_all' then jsonb_build_object('bn', 'এই lot-এর সব মাল বিক্রি হয়ে গেছে, stock-এ কিছু নেই: পুরো খরচ variance খাতে যাওয়াই যুক্তিসঙ্গত।', 'mix', 'এই lot-এর সব মাল sold, stock-এ কিছু নেই: পুরো charge variance account-এ যাওয়াই যুক্তিসঙ্গত।', 'en', 'All of this lot is already sold and nothing is left in stock: the whole charge belongs in the variance account.')
    when 'w_weight_unknown' then jsonb_build_object('bn', 'ওজন জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না — line-এর ওজন বা item-এর ওজন লিখুন।', 'mix', 'Weight জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না — line-এর weight বা item-এর weight লিখুন।', 'en', 'Weight is unknown for: ' || coalesce(p_a, '') || '. It is not guessed: enter the line weight or the item weight.')
    when 'w_volume_unknown' then jsonb_build_object('bn', 'আয়তন জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না।', 'mix', 'Volume জানা নেই: ' || coalesce(p_a, '') || '। অনুমান করা হয় না।', 'en', 'Volume is unknown for: ' || coalesce(p_a, '') || '. It is not guessed.')
    when 'w_fx' then jsonb_build_object('bn', 'কোনো খরচ বিদেশি মুদ্রায়: আপনার লেখা রূপান্তর হার (rate) আবার দেখে নিন।', 'mix', 'কোনো charge foreign currency-তে: আপনার লেখা rate আবার দেখে নিন।', 'en', 'A charge is in a foreign currency: check the exchange rate you typed.')
    when 'w_avg_unknown' then jsonb_build_object('bn', 'কোনো item-এর গড় cost জানা নেই, তাই তার ভাগ stock-এ যোগ হবে না (variance খাতে যাবে)।', 'mix', 'কোনো item-এর average cost জানা নেই, তাই তার ভাগ stock-এ যোগ হবে না (variance account-এ যাবে)।', 'en', 'The average cost of an item is unknown, so its share is not added to stock (it goes to the variance account).')
    when 'w_no_stock' then jsonb_build_object('bn', 'এই বিলগুলোতে গোনা ও tracked কোনো item নেই: stock-এ কিছু যোগ করার নেই।', 'mix', 'এই bill গুলোতে counted ও tracked কোনো item নেই: stock-এ কিছু যোগ করার নেই।', 'en', 'There is no counted, tracked item in these bills: nothing can be added to stock.')
    when 'w_untracked' then jsonb_build_object('bn', coalesce(p_a, '0') || 'টি line stock item নয়, সেগুলো ভাগ পায় না।', 'mix', coalesce(p_a, '0') || 'টি line stock item নয়, সেগুলো ভাগ পায় না।', 'en', coalesce(p_a, '0') || ' line(s) are not stock items, so they take no share.')
    when 'w_noncap' then jsonb_build_object('bn', 'কিছু খরচ মালের দামে যোগ হয় না (শুধু খরচ বা ফেরতযোগ্য কর): সেগুলো সরাসরি হিসাবে যায়।', 'mix', 'কিছু charge item cost-এ যোগ হয় না (expense only বা recoverable tax): সেগুলো সরাসরি accounts-এ যায়।', 'en', 'Some charges are not added to item cost (expense only or recoverable tax): they go straight to the accounts.')
    when 'w_credit_capped' then jsonb_build_object('bn', 'ঋণাত্মক খরচ (ফেরত) stock-এর মূল্যের চেয়ে বেশি ছিল, তাই বাকিটা variance খাতে গেছে।', 'mix', 'Negative charge (refund) stock value-র চেয়ে বেশি ছিল, তাই বাকিটা variance account-এ গেছে।', 'en', 'A negative charge (refund) was larger than the stock value, so the rest goes to the variance account.')
    when 'w_nocap' then jsonb_build_object('bn', 'কোনো খরচ মালের দামে যোগ হচ্ছে না, তাই এখানে ভাগ করার কিছু নেই।', 'mix', 'কোনো charge item cost-এ যোগ হচ্ছে না, তাই এখানে ভাগ করার কিছু নেই।', 'en', 'No charge is added to item cost, so there is nothing to spread.')
    else jsonb_build_object('bn', coalesce(p_code, ''), 'mix', coalesce(p_code, ''), 'en', coalesce(p_code, ''))
  end;
$$;
revoke all on function public._landed_msg97(text, text, text) from public, anon, authenticated;

-- the recommendation, from the numbers only
create or replace function public._landed_reco97(p_rows jsonb, p_charges jsonb, p_avail jsonb, p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; n int := (p_avail->>'lines')::int; per jsonb := '[]'::jsonb; reasons jsonb := '[]'::jsonb; warns jsonb := '[]'::jsonb; pref text; m text; rc text; big numeric := -1; hdr text;
        it jsonb; late_total numeric := 0; late_all boolean := true; any_late boolean := false; late_rec text; miss text; ncap int := 0; nuntr int; fx boolean := false; nonc boolean := false;
        flags text; rule_late text := coalesce(public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs');
begin
  select count(*) into nuntr from jsonb_array_elements(p_rows) x where not (x->>'in_scope')::boolean;
  if n = 0 then
    warns := warns || (public._landed_msg97('w_no_stock') || jsonb_build_object('code', 'no_stock_lines'));
    return jsonb_build_object('method', null, 'per_charge', '[]'::jsonb, 'late_mode', rule_late, 'reasons', reasons, 'warnings', warns);
  end if;
  for c in select * from jsonb_array_elements(p_charges) loop
    if c->>'ccy' <> upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT')) then fx := true; end if;
    if c->>'treatment' <> 'capitalise' then nonc := true; continue; end if;
    ncap := ncap + 1;
    pref := coalesce(c->>'default_alloc', public.rule_txt('landed_alloc_default'), 'value'); if pref = 'manual' then pref := 'value'; end if;
    m := pref; rc := 'm_' || pref;
    if n = 1 then m := 'value'; rc := 'm_single';
    elsif pref in ('weight', 'volume') and not coalesce((p_avail->pref->>'ok')::boolean, false) then
      m := 'value'; rc := 'm_' || pref || '_fallback';
      miss := (select string_agg(v, ', ') from jsonb_array_elements_text(p_avail->pref->'missing') v);
      if not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_' || pref || '_unknown') then
        warns := warns || (public._landed_msg97('w_' || pref || '_unknown', coalesce(miss, '')) || jsonb_build_object('code', 'w_' || pref || '_unknown', 'items', p_avail->pref->'missing'));
      end if;
    elsif pref = 'qty' and coalesce((p_avail->'qty'->>'mixed_units')::boolean, false) then m := 'value'; rc := 'm_qty_mixed';
    end if;
    if m = 'value' and not coalesce((p_avail->'value'->>'ok')::boolean, false) then m := 'equal'; rc := 'm_equal'; end if;
    per := per || jsonb_build_object('i', (c->>'i')::int, 'charge_type', c->>'charge_type', 'method', m, 'reason', public._landed_msg97(rc) || jsonb_build_object('code', rc));
    if abs((c->>'amount')::numeric) > big then big := abs((c->>'amount')::numeric); hdr := m; end if;
  end loop;
  if hdr is null then
    hdr := coalesce(public.rule_txt('landed_alloc_default'), 'value');
    if hdr = 'manual' or not coalesce((p_avail->hdr->>'ok')::boolean, false) then hdr := 'value'; end if;
    if jsonb_array_length(p_charges) > 0 and ncap = 0 then warns := warns || (public._landed_msg97('w_nocap') || jsonb_build_object('code', 'w_nocap')); end if;
  end if;
  -- the chosen header method explained once (the reason of the biggest capitalised charge)
  select p->'reason' into it from jsonb_array_elements(per) p where p->>'method' = hdr order by (case when (p->>'i')::int is not null then 0 end) limit 1;
  if it is not null then reasons := reasons || it; end if;
  -- late goods
  for it in select * from jsonb_array_elements(p_items) loop
    if (it->>'late_qty')::numeric > 0.0005 then any_late := true; late_total := late_total + (it->>'late_qty')::numeric; if (it->>'on_hand')::numeric > 0 then late_all := false; end if; end if;
  end loop;
  late_rec := rule_late;
  if any_late then
    late_rec := case when late_all then 'variance_account' else 'split_remaining_and_cogs' end;
    warns := warns || (public._landed_msg97(case when late_all then 'w_late_all' else 'w_late' end, trim_scale(late_total)::text) || jsonb_build_object('code', case when late_all then 'late_all_sold' else 'late_goods_sold' end, 'qty', late_total));
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    flags := it->>'flags';
    if flags like '%avg_unknown%' and not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_avg_unknown') then warns := warns || (public._landed_msg97('w_avg_unknown') || jsonb_build_object('code', 'w_avg_unknown')); end if;
    if flags like '%credit_capped%' and not exists (select 1 from jsonb_array_elements(warns) w where w->>'code' = 'w_credit_capped') then warns := warns || (public._landed_msg97('w_credit_capped') || jsonb_build_object('code', 'w_credit_capped')); end if;
  end loop;
  if fx then warns := warns || (public._landed_msg97('w_fx') || jsonb_build_object('code', 'w_fx')); end if;
  if nuntr > 0 then warns := warns || (public._landed_msg97('w_untracked', nuntr::text) || jsonb_build_object('code', 'w_untracked', 'count', nuntr)); end if;
  if nonc then warns := warns || (public._landed_msg97('w_noncap') || jsonb_build_object('code', 'w_noncap')); end if;
  return jsonb_build_object('method', hdr, 'per_charge', per, 'late_mode', late_rec, 'reasons', reasons, 'warnings', warns, 'late_qty', late_total);
end $$;
revoke all on function public._landed_reco97(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;

-- the whole picture for a set of bills + charges (no writes)
create or replace function public._landed_calc97(p_bills uuid[], p_charges jsonb, p_basis jsonb, p_method text, p_late text, p_check boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; chg jsonb; av jsonb; hm text; lm text; sp jsonb; pl jsonb; mx jsonb := '{}'::jsonb; m text; sx jsonb; lines_ jsonb := '[]'::jsonb; r jsonb; per jsonb; chosen jsonb;
        cap numeric := 0; exp_ numeric := 0; tax numeric := 0; err text := null; reco jsonb; nb int; c jsonb; la numeric; uadd numeric;
begin
  rows_ := public._landed_rows97(p_bills, p_basis);
  select count(distinct x->>'bill_id') into nb from jsonb_array_elements(rows_) x;
  if nb <> (select count(distinct b) from unnest(p_bills) b) then raise exception 'bill_not_found' using hint = 'Only posted purchase bills (not returns) can take a landed cost'; end if;
  chg := public._landed_norm_charges97(p_charges, p_check);
  av := public._landed_avail97(rows_);
  hm := coalesce(p_method, public.rule_txt('landed_alloc_default'), 'value');
  if hm not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  lm := coalesce(p_late, public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs');
  for c in select * from jsonb_array_elements(chg) loop
    if c->>'treatment' = 'capitalise' then cap := cap + (c->>'amount')::numeric; elsif c->>'treatment' = 'expense_only' then exp_ := exp_ + (c->>'amount')::numeric; else tax := tax + (c->>'amount')::numeric; end if;
  end loop;
  -- every method side by side (all capitalised charges spread by that one method)
  if cap <> 0 or exists (select 1 from jsonb_array_elements(chg) x where x->>'treatment' = 'capitalise') then
    foreach m in array array['qty', 'value', 'weight', 'volume', 'manual', 'equal'] loop
      if coalesce((av->m->>'ok')::boolean, false) and (av->>'lines')::int > 0 then
        sx := public._landed_spread97(rows_, chg, hm, m, av);
        mx := mx || jsonb_build_object(m, (select coalesce(jsonb_object_agg(bl::text, a), '{}'::jsonb) from (select (e->>'bl')::bigint bl, sum((e->>'amt')::numeric) a from jsonb_array_elements(sx) e where (e->>'bl') is not null group by 1) q));
      end if;
    end loop;
  end if;
  -- the saved / chosen way (charge overrides honoured)
  begin
    sp := public._landed_spread97(rows_, chg, hm, null, av);
    pl := public._landed_plan97(rows_, chg, sp, lm);
  exception when others then
    err := sqlerrm; sp := '[]'::jsonb; pl := jsonb_build_object('items', '[]'::jsonb, 'rows', '[]'::jsonb, 'late_mode', lm);
  end;
  for r in select * from jsonb_array_elements(rows_) loop
    per := '{}'::jsonb;
    if (r->>'in_scope')::boolean then
      foreach m in array array['qty', 'value', 'weight', 'volume', 'manual', 'equal'] loop
        if mx ? m then
          la := coalesce((mx->m->>(r->>'bill_line_id'))::numeric, 0); uadd := round(la / (r->>'base_qty')::numeric, 6);
          per := per || jsonb_build_object(m, jsonb_build_object('alloc', la, 'unit_add', uadd, 'new_unit_cost', round((r->>'ucb_net')::numeric + uadd, 6),
                   'pct_up', case when (r->>'ucb_net')::numeric > 0 then round(uadd / (r->>'ucb_net')::numeric * 100, 2) end));
        end if;
      end loop;
      la := coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint), 0);
      uadd := round(la / (r->>'base_qty')::numeric, 6);
      chosen := jsonb_build_object('alloc', la, 'unit_add', uadd, 'new_unit_cost', round((r->>'ucb_net')::numeric + uadd, 6),
                   'stock', coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint and e->>'part' = 'stock'), 0),
                   'cogs', coalesce((select sum((e->>'amount')::numeric) from jsonb_array_elements(pl->'rows') e where (e->>'bl') is not null and (e->>'bl')::bigint = (r->>'bill_line_id')::bigint and e->>'part' = 'cogs'), 0));
    else chosen := null; end if;
    lines_ := lines_ || (r - 'item_type' || jsonb_build_object('methods', per, 'chosen', chosen));
  end loop;
  reco := public._landed_reco97(rows_, chg, av, pl->'items');
  return jsonb_build_object('ok', err is null, 'error', err, 'method', hm, 'late_mode', lm, 'avail', av, 'lines', lines_, 'items', pl->'items',
    'charges', (select coalesce(jsonb_agg(ch - 'name_mix' - 'expense_key' - 'default_alloc'), '[]'::jsonb) from jsonb_array_elements(chg) ch),
    'totals', jsonb_build_object('capitalised', cap, 'expense_only', exp_, 'recoverable_tax', tax, 'all', cap + exp_ + tax),
    'recommendation', reco, '_plan', pl, '_chg', chg, '_rows', rows_, '_spread', sp);
end $$;
revoke all on function public._landed_calc97(uuid[], jsonb, jsonb, text, text, boolean) from public, anon, authenticated;

-- ============================================================
-- public RPCs
-- ============================================================
create or replace function public.landed_preview(p_bills uuid[], p_charges jsonb default '[]'::jsonb, p_basis jsonb default '[]'::jsonb, p_method text default null, p_late text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int; locs int[]; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_bills is null or coalesce(array_length(p_bills, 1), 0) = 0 then raise exception 'no_bills'; end if;
  select array_agg(distinct location_id) into locs from public.purchase_bills where id = any (p_bills);
  if locs is null or array_length(locs, 1) <> 1 then raise exception 'bill_not_found' using hint = 'The bills must exist and belong to one place'; end if;
  loc := locs[1];
  if not public._landed_ok97(loc, 'entry') then raise exception 'not allowed'; end if;
  r := public._landed_calc97(p_bills, p_charges, p_basis, p_method, p_late);
  return (r - '_plan' - '_chg' - '_rows' - '_spread') || jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'location_id', loc);
end $$;

create or replace function public.landed_recommendation(p_bills uuid[] default null, p_cost uuid default null, p_charges jsonb default null, p_basis jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bills uuid[] := p_bills; chg jsonb := p_charges; bs jsonb := p_basis; h public.landed_costs; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_cost is not null then
    select * into h from public.landed_costs where id = p_cost;
    if not found then raise exception 'not found'; end if;
    if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
    bills := array(select bill_id from public.landed_cost_docs where cost_id = p_cost);
    chg := coalesce(chg, (select coalesce(jsonb_agg(jsonb_build_object('charge_type', l.charge_type, 'amount_ccy', l.amount_ccy, 'ccy', l.ccy, 'rate', l.rate, 'alloc_method', l.alloc_method, 'pay_mode', l.pay_mode, 'supplier_id', l.supplier_id) order by l.line_no), '[]'::jsonb) from public.landed_cost_lines l where l.cost_id = p_cost));
    bs := coalesce(bs, (select coalesce(jsonb_agg(jsonb_build_object('bill_line_id', b.bill_line_id, 'weight_kg', b.weight_kg, 'volume_l', b.volume_l, 'manual_pct', b.manual_pct)), '[]'::jsonb) from public.landed_cost_basis b where b.cost_id = p_cost));
  end if;
  if bills is null or coalesce(array_length(bills, 1), 0) = 0 then raise exception 'no_bills'; end if;
  if p_cost is null and not exists (select 1 from public.purchase_bills b where b.id = any (bills) and public._landed_ok97(b.location_id, 'entry')) then raise exception 'not allowed'; end if;
  r := public._landed_calc97(bills, coalesce(chg, '[]'::jsonb), coalesce(bs, '[]'::jsonb), case when p_cost is not null then h.alloc_method end, case when p_cost is not null then h.late_mode end);
  return r->'recommendation' || jsonb_build_object('avail', r->'avail', 'totals', r->'totals');
end $$;


-- bills / GRNs the person picked -> the posted purchase bills they stand for (a GRN counts through the bill it is linked to)
create or replace function public._landed_resolve97(p_docs jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; ty text; did uuid; bid uuid; bills uuid[] := '{}'; docrows jsonb := '[]'::jsonb;
begin
  if p_docs is null or jsonb_typeof(p_docs) <> 'array' or jsonb_array_length(p_docs) = 0 then raise exception 'no_bills'; end if;
  for d in select * from jsonb_array_elements(p_docs) loop
    ty := coalesce(d->>'type', 'bill');
    begin did := (d->>'id')::uuid; exception when others then raise exception 'bill_not_found'; end;
    if ty = 'bill' then bid := did;
    elsif ty = 'grn' then
      select x.shadow_id::uuid into bid from public.shadow_links x where x.domain = 'grn' and x.primary_type = 'entries' and x.primary_id = did::text and x.shadow_type = 'purchase_bills' and x.state <> 'void' and x.shadow_id is not null order by x.id limit 1;
      if bid is null then raise exception 'grn_not_linked' using hint = 'Link the GRN to its purchase bill first'; end if;
    else raise exception 'bad_doc_type'; end if;
    if not exists (select 1 from public.purchase_bills where id = bid and kind = 'bill' and status = 'posted') then raise exception 'bill_not_found' using hint = 'Only posted purchase bills (not returns) can take a landed cost'; end if;
    if not (bid = any (bills)) then bills := bills || bid; docrows := docrows || jsonb_build_object('type', ty, 'doc_id', did, 'bill_id', bid); end if;
  end loop;
  return jsonb_build_object('bills', to_jsonb(bills), 'docrows', docrows);
end $$;
revoke all on function public._landed_resolve97(jsonb) from public, anon, authenticated;

create or replace function public.landed_resolve_docs(p_docs jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rs jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  rs := public._landed_resolve97(p_docs);
  if not exists (select 1 from public.purchase_bills b where b.id in (select (x)::uuid from jsonb_array_elements_text(rs->'bills') x) and public._landed_ok97(b.location_id, 'entry')) then raise exception 'not allowed'; end if;
  return rs->'docrows';
end $$;
revoke all on function public.landed_resolve_docs(jsonb) from public, anon;
grant execute on function public.landed_resolve_docs(jsonb) to authenticated;

-- save a draft (also edits a draft / re-opens an approved one). Idempotent on p_client.
create or replace function public.landed_save(p_client uuid, p_id uuid, p_header jsonb, p_docs jsonb, p_lines jsonb, p_basis jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); h public.landed_costs; d jsonb; bills uuid[] := '{}'; docrows jsonb := '[]'::jsonb; loc int; locs int[]; chg jsonb; c jsonb; b jsonb; sid text;
        meth text; late text; cdate date; tot numeric := 0; nid uuid := p_id; n int := 0; ref text; ttl text; nt text; rs jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if mode_ = 'off' then raise exception 'landed_off' using hint = 'Switch landed_cost_mode on first'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and p_id is null then
    select * into h from public.landed_costs where client_id = p_client;
    if found then
      if h.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', h.id, 'status', h.status, 'total', h.total, 'dup', true);
    end if;
  end if;
  if p_docs is null or jsonb_typeof(p_docs) <> 'array' or jsonb_array_length(p_docs) = 0 then raise exception 'no_bills'; end if;
  rs := public._landed_resolve97(p_docs); bills := array(select (x)::uuid from jsonb_array_elements_text(rs->'bills') x); docrows := rs->'docrows';
  select array_agg(distinct location_id) into locs from public.purchase_bills where id = any (bills);
  if array_length(locs, 1) <> 1 then raise exception 'one_place_only' using hint = 'One landed cost covers bills of one place'; end if;
  loc := locs[1];
  if not public._landed_ok97(loc, 'entry') then raise exception 'not allowed'; end if;
  ref := left(nullif(btrim(p_header->>'shipment_ref'), ''), 80);
  if mode_ = 'per_bill' and array_length(bills, 1) <> 1 then raise exception 'per_bill_one_bill' using hint = 'In per_bill mode one landed cost covers one bill'; end if;
  if mode_ = 'per_shipment' and ref is null then raise exception 'shipment_ref_needed' using hint = 'Give the shipment / lot a reference'; end if;
  meth := coalesce(nullif(p_header->>'alloc_method', ''), public.rule_txt('landed_alloc_default'), 'value');
  if meth not in ('qty', 'value', 'weight', 'volume', 'manual', 'equal') then raise exception 'bad_method'; end if;
  late := nullif(p_header->>'late_mode', '');
  if late is not null and late not in ('post_to_remaining_stock', 'split_remaining_and_cogs', 'variance_account') then raise exception 'bad_late_mode'; end if;
  begin cdate := coalesce(nullif(p_header->>'cost_date', '')::date, (now() at time zone 'Asia/Dhaka')::date); exception when others then raise exception 'bad_date'; end;
  if cdate > (now() at time zone 'Asia/Dhaka')::date + 1 then raise exception 'bad_date'; end if;
  ttl := left(nullif(btrim(p_header->>'title'), ''), 120); nt := left(nullif(btrim(p_header->>'note'), ''), 500);
  chg := public._landed_norm_charges97(p_lines);
  if jsonb_array_length(chg) = 0 then raise exception 'no_charges'; end if;
  for c in select * from jsonb_array_elements(chg) loop tot := tot + (c->>'amount')::numeric; end loop;
  if p_basis is null or jsonb_typeof(p_basis) <> 'array' then p_basis := '[]'::jsonb; end if;
  for b in select * from jsonb_array_elements(p_basis) loop
    if jsonb_typeof(b) <> 'object' or not exists (select 1 from public.purchase_lines l where l.id = nullif(b->>'bill_line_id', '')::bigint and l.bill_id = any (bills)) then raise exception 'bad_basis_line'; end if;
    begin
      if (nullif(b->>'weight_kg', '') is not null and (b->>'weight_kg')::numeric < 0) or (nullif(b->>'volume_l', '') is not null and (b->>'volume_l')::numeric < 0)
         or (nullif(b->>'manual_pct', '') is not null and not ((b->>'manual_pct')::numeric between 0 and 100)) then raise exception 'bad_basis_value'; end if;
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'bad_basis_value'; end;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_id is not null then
    select * into h from public.landed_costs where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    if h.status not in ('draft', 'approved') then raise exception 'not_editable'; end if;
    if h.location_id <> loc then raise exception 'one_place_only'; end if;
    if h.status = 'approved' then update public.landed_costs set status = 'draft', approved_by = null, approved_at = null where id = p_id; end if;
    delete from public.landed_cost_docs where cost_id = p_id; delete from public.landed_cost_lines where cost_id = p_id; delete from public.landed_cost_basis where cost_id = p_id;
    update public.landed_costs set shipment_ref = ref, title = ttl, note = nt, cost_date = cdate, alloc_method = meth, late_mode = late, total = tot, mode_at_save = mode_ where id = p_id;
  else
    insert into public.landed_costs (client_id, location_id, shipment_ref, title, note, cost_date, alloc_method, late_mode, mode_at_save, total, created_by, created_staff)
      values (p_client, loc, ref, ttl, nt, cdate, meth, late, mode_, tot, auth.uid(), sid) returning id into nid;
  end if;
  for d in select * from jsonb_array_elements(docrows) loop
    insert into public.landed_cost_docs (cost_id, bill_id, doc_type, doc_id) values (nid, (d->>'bill_id')::uuid, d->>'type', (d->>'doc_id')::uuid);
  end loop;
  for c in select * from jsonb_array_elements(chg) loop
    n := n + 1;
    insert into public.landed_cost_lines (cost_id, line_no, charge_type, amount_ccy, ccy, rate, amount, alloc_method, pay_mode, supplier_id, ref_no, note)
      values (nid, n, c->>'charge_type', (c->>'amount_ccy')::numeric, c->>'ccy', (c->>'rate')::numeric, (c->>'amount')::numeric, c->>'alloc_method', c->>'pay_mode', nullif(c->>'supplier_id', '')::uuid, c->>'ref_no', c->>'note');
  end loop;
  for b in select * from jsonb_array_elements(p_basis) loop
    insert into public.landed_cost_basis (cost_id, bill_line_id, weight_kg, volume_l, manual_pct)
      values (nid, (b->>'bill_line_id')::bigint, nullif(b->>'weight_kg', '')::numeric, nullif(b->>'volume_l', '')::numeric, nullif(b->>'manual_pct', '')::numeric)
      on conflict (cost_id, bill_line_id) do update set weight_kg = excluded.weight_kg, volume_l = excluded.volume_l, manual_pct = excluded.manual_pct;
  end loop;
  return jsonb_build_object('id', nid, 'status', 'draft', 'total', tot, 'dup', false);
end $$;

-- what the stored draft looks like now (helper for approve / post / get)
create or replace function public._landed_saved97(p_id uuid, p_check_active boolean default true) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h public.landed_costs; bills uuid[]; chg jsonb; bs jsonb;
begin
  select * into h from public.landed_costs where id = p_id;
  if not found then raise exception 'not found'; end if;
  bills := array(select bill_id from public.landed_cost_docs where cost_id = p_id order by bill_id);
  select coalesce(jsonb_agg(jsonb_build_object('charge_type', l.charge_type, 'amount_ccy', l.amount_ccy, 'ccy', l.ccy, 'rate', l.rate, 'alloc_method', l.alloc_method, 'pay_mode', l.pay_mode,
           'supplier_id', l.supplier_id, 'ref_no', l.ref_no, 'note', l.note) order by l.line_no), '[]'::jsonb) into chg from public.landed_cost_lines l where l.cost_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('bill_line_id', b.bill_line_id, 'weight_kg', b.weight_kg, 'volume_l', b.volume_l, 'manual_pct', b.manual_pct)), '[]'::jsonb) into bs from public.landed_cost_basis b where b.cost_id = p_id;
  return public._landed_calc97(bills, chg, bs, h.alloc_method, h.late_mode, p_check_active) || jsonb_build_object('_bills', to_jsonb(bills));
end $$;
revoke all on function public._landed_saved97(uuid, boolean) from public, anon, authenticated;

-- ---------- journal lines of a landed cost (used by _acct_docs; closed to the browser) ----------
create or replace function public._landed_jlines97(p_id uuid, p_kind text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(j), '[]'::jsonb) from (
    select jsonb_build_object('a', a.dr_key, 'd', a.amount) as j from public.landed_cost_alloc a where a.cost_id = p_id and a.kind = p_kind
    union all
    select jsonb_build_object('a', case l.pay_mode when 'payable' then 'landed_payable' when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'pay_mobile' end, 'c', sum(a.amount),
             'pt', case when l.pay_mode = 'payable' and l.supplier_id is not null then 'supplier' end, 'pid', case when l.pay_mode = 'payable' then l.supplier_id::text end)
      from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id where a.cost_id = p_id and a.kind = p_kind group by l.id, l.pay_mode, l.supplier_id) z;
$$;
revoke all on function public._landed_jlines97(uuid, text) from public, anon, authenticated;

-- the journal of a landed cost lives in _acct_docs (bos97). If phase515 was pasted again after phase523, that block is gone: refuse to post rather than change the stock without the books
create or replace function public._landed_journal_ready97() returns boolean language sql stable security definer set search_path = public as $$
  select position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0;
$$;
revoke all on function public._landed_journal_ready97() from public, anon, authenticated;

-- ---------- approve ----------
create or replace function public.landed_approve(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; s jsonb; req text := coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'approve') then raise exception 'not allowed'; end if;
  if h.status = 'approved' then return jsonb_build_object('id', h.id, 'status', 'approved', 'dup', true); end if;
  if h.status <> 'draft' then raise exception 'not_draft'; end if;
  if req = 'required' and h.created_by = auth.uid() and not public.is_owner() then raise exception 'approver_must_differ' using hint = 'Somebody else approves what you made'; end if;
  s := public._landed_saved97(p_id, false);
  if not (s->>'ok')::boolean then raise exception '%', s->>'error'; end if;      -- e.g. method_unavailable:weight (the weight of some line is unknown)
  update public.landed_costs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'approved');
end $$;

-- ---------- post: spread, add to the stock cost (ledger pair), keep the rows (the journal follows through _acct_docs) ----------
create or replace function public.landed_post(p_id uuid, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); req text := coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn');
        s jsonb; pl jsonb; it jsonb; rw jsonb; stk numeric; q numeric; av numeric; na numeric; lo bigint; li bigint; k text; late_any boolean := false; nrows int := 0; nstock int := 0; sum_stock numeric := 0; sum_cogs numeric := 0;
        cl bigint; cnt int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if h.status = 'posted' then return jsonb_build_object('id', h.id, 'status', 'posted', 'dup', true, 'posted', 0, 'total', h.total); end if;     -- a second press posts nothing
  if p_client is not null and exists (select 1 from public.landed_costs x where x.post_client = p_client and x.id <> h.id) then raise exception 'client_id_taken'; end if;
  if h.status = 'void' then raise exception 'landed_void'; end if;
  if mode_ = 'off' then raise exception 'landed_off' using hint = 'Switch landed_cost_mode on first'; end if;
  if req = 'required' and h.status <> 'approved' then raise exception 'approval_required'; end if;
  perform public.lock_check(h.cost_date);
  if public.rule_on('accounting_on') and not public._landed_journal_ready97() then raise exception 'journal_not_ready' using hint = 'Paste phase523 again (phase515 was pasted after it)'; end if;
  if public.rule_on('accounting_on') and public._acct_start() is not null and h.cost_date < public._acct_start() then raise exception 'before_start' using hint = 'The date is before the accounting start: the entry could never be posted. Use a later date'; end if;
  perform 1 from public.stock_balance b where b.location_id = h.location_id
      and b.item_id in (select pl2.item_id from public.landed_cost_docs d join public.purchase_lines pl2 on pl2.bill_id = d.bill_id where d.cost_id = p_id and pl2.item_id is not null) order by b.item_id for update;
  s := public._landed_saved97(p_id, false);
  if not (s->>'ok')::boolean then raise exception '%', s->>'error'; end if;
  pl := s->'_plan';
  if jsonb_array_length(pl->'rows') = 0 then raise exception 'nothing_to_post'; end if;
  if public.rule_on('accounting_on') then       -- the journal needs these accounts; fail now, not later
    for k in select distinct x from (select r->>'dr_key' x from jsonb_array_elements(pl->'rows') r
               union select case l.pay_mode when 'payable' then 'landed_payable' when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'pay_mobile' end from public.landed_cost_lines l where l.cost_id = p_id) z loop
      if not exists (select 1 from public.acct_mappings m where m.key = k) then raise exception 'mapping_missing:%', k; end if;
    end loop;
  end if;
  for rw in select * from jsonb_array_elements(pl->'rows') loop
    select id into cl from public.landed_cost_lines where cost_id = p_id and line_no = (rw->>'ci')::int;
    insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method)
      values (p_id, 'post', cl, nullif(rw->>'bl', '')::bigint, nullif(rw->>'item_id', '')::uuid, h.location_id, rw->>'part', (rw->>'amount')::numeric, rw->>'dr_key', rw->>'method');
    nrows := nrows + 1;
  end loop;
  for it in select * from jsonb_array_elements(pl->'items') loop
    stk := (it->>'stock')::numeric; q := (it->>'on_hand')::numeric; av := nullif(it->>'avg', '')::numeric; na := null; lo := null; li := null;
    if stk <> 0 and q > 0 and av is not null then
      na := round((q * av + stk) / q, 6);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values ((it->>'item_id')::uuid, h.location_id, -q, av, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost: stock out at the old average', auth.uid()) returning id into lo;
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values ((it->>'item_id')::uuid, h.location_id, q, na, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost: stock back in at the new average', auth.uid()) returning id into li;
      nstock := nstock + 1;
    end if;
    insert into public.landed_cost_stock (cost_id, kind, item_id, location_id, lot_qty, on_hand_before, avg_before, avg_after, stock_value, cogs_value, ledger_out, ledger_in, flags)
      values (p_id, 'post', (it->>'item_id')::uuid, h.location_id, (it->>'lot_qty')::numeric, q, av, coalesce(na, av), stk, (it->>'cogs')::numeric, lo, li, it->>'flags');
    sum_stock := sum_stock + stk; sum_cogs := sum_cogs + (it->>'cogs')::numeric;
    if (it->>'late_qty')::numeric > 0.0005 then late_any := true; end if;
  end loop;
  update public.landed_costs set status = 'posted', posted_by = auth.uid(), posted_at = now(), late_mode_used = pl->>'late_mode', post_client = p_client where id = p_id;
  if req = 'warn' and h.status <> 'approved' then
    perform public._stock_exc(h.location_id, 'landed_unapproved', 'yellow', 'Landed cost অনুমোদন ছাড়াই post হয়েছে, মোট ' || h.total::text, 'A landed cost was posted without approval, total ' || h.total::text, null, h.cost_date, 'PURCHASE', h.total);
  end if;
  if late_any then
    perform public._stock_exc(h.location_id, 'landed_late_cost', 'yellow', 'Landed cost এসেছে মাল আংশিক বিক্রি হওয়ার পর (পদ্ধতি: ' || (pl->>'late_mode') || ')', 'A landed cost arrived after part of the goods was sold or used (mode: ' || (pl->>'late_mode') || ')', null, h.cost_date, 'PURCHASE', h.total);
  end if;
  return jsonb_build_object('id', p_id, 'status', 'posted', 'dup', false, 'posted', nrows, 'total', h.total, 'stock_added', sum_stock, 'to_variance', sum_cogs, 'items_adjusted', nstock, 'late', late_any);
end $$;

-- ---------- void (reversal): only the part still on the shelf leaves the stock cost; the sold part is released from the variance account ----------
create or replace function public.landed_void(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.landed_costs; st public.landed_cost_stock; a public.landed_cost_alloc; bal public.stock_balance; q_now numeric; f numeric; v numeric; fac jsonb := '{}'::jsonb; sumv jsonb := '{}'::jsonb;
        sv numeric; lo bigint; li bigint; na numeric; tot_orig numeric; nrows int := 0; ikey text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'approve') then raise exception 'not allowed'; end if;
  if h.status = 'void' then return jsonb_build_object('id', h.id, 'status', 'void', 'dup', true); end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if h.status in ('draft', 'approved') then
    update public.landed_costs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'void', 'reversed_rows', 0);
  end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  perform 1 from public.stock_balance b where b.location_id = h.location_id and b.item_id in (select item_id from public.landed_cost_stock where cost_id = p_id and kind = 'post') order by b.item_id for update;
  for st in select * from public.landed_cost_stock where cost_id = p_id and kind = 'post' order by item_id loop
    select * into bal from public.stock_balance where item_id = st.item_id and location_id = st.location_id;
    q_now := greatest(coalesce(bal.qty, 0), 0);
    if st.stock_value = 0 or q_now <= 0 or bal.avg_cost is null or st.on_hand_before <= 0 then f := 0;
    else
      f := least(1, q_now / st.on_hand_before);
      v := round(st.stock_value * f, 2);
      if v > 0 then v := least(v, round(q_now * bal.avg_cost, 2)); end if;
      f := v / st.stock_value;
    end if;
    fac := fac || jsonb_build_object(st.item_id::text, f);
  end loop;
  for a in select * from public.landed_cost_alloc where cost_id = p_id and kind = 'post' order by id loop
    if a.part = 'stock' then
      f := coalesce((fac->>a.item_id::text)::numeric, 0); v := round(a.amount * f, 2);
      if v <> 0 then
        insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, 'stock', -v, a.dr_key, a.method);
        nrows := nrows + 1;
        sumv := jsonb_set(sumv, array[a.item_id::text], to_jsonb(coalesce((sumv->>a.item_id::text)::numeric, 0) + v));
      end if;
      if a.amount - v <> 0 then
        insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, 'cogs', -(a.amount - v), 'landed_variance', a.method);
        nrows := nrows + 1;
      end if;
    else
      insert into public.landed_cost_alloc (cost_id, kind, charge_line_id, bill_line_id, item_id, location_id, part, amount, dr_key, method) values (p_id, 'void', a.charge_line_id, a.bill_line_id, a.item_id, a.location_id, a.part, -a.amount, a.dr_key, a.method);
      nrows := nrows + 1;
    end if;
  end loop;
  for st in select * from public.landed_cost_stock where cost_id = p_id and kind = 'post' order by item_id loop
    sv := coalesce((sumv->>st.item_id::text)::numeric, 0); lo := null; li := null; na := null;
    select * into bal from public.stock_balance where item_id = st.item_id and location_id = st.location_id;
    q_now := greatest(coalesce(bal.qty, 0), 0);
    if sv <> 0 and q_now > 0 and bal.avg_cost is not null then
      na := round((q_now * bal.avg_cost - sv) / q_now, 6);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (st.item_id, st.location_id, -q_now, bal.avg_cost, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost void: stock out at the average', auth.uid()) returning id into lo;
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (st.item_id, st.location_id, q_now, na, 'cost_adjust', 'landed', p_id::text, now(), 'landed cost void: stock back in at the corrected average', auth.uid()) returning id into li;
    end if;
    tot_orig := (select coalesce(sum(amount), 0) from public.landed_cost_alloc where cost_id = p_id and kind = 'post' and item_id = st.item_id);
    insert into public.landed_cost_stock (cost_id, kind, item_id, location_id, lot_qty, on_hand_before, avg_before, avg_after, stock_value, cogs_value, ledger_out, ledger_in, flags)
      values (p_id, 'void', st.item_id, st.location_id, st.lot_qty, q_now, bal.avg_cost, coalesce(na, bal.avg_cost), -sv, -(tot_orig - sv), lo, li, case when sv = 0 and st.stock_value <> 0 then 'nothing_left' end);
  end loop;
  update public.landed_costs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'void', 'reversed_rows', nrows);
end $$;

-- ---------- read: one landed cost, a list, the reminder list, the return view ----------
create or replace function public.landed_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h public.landed_costs; s jsonb := null;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into h from public.landed_costs where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(h.location_id, 'entry') then raise exception 'not allowed'; end if;
  if h.status in ('draft', 'approved') then
    begin s := public._landed_saved97(p_id, false); s := s - '_plan' - '_chg' - '_rows' - '_spread' - '_bills'; exception when others then s := jsonb_build_object('ok', false, 'error', sqlerrm); end;
  end if;
  return jsonb_build_object(
    'header', to_jsonb(h) - 'client_id' - 'post_client',
    'docs', coalesce((select jsonb_agg(jsonb_build_object('bill_id', d.bill_id, 'doc_type', d.doc_type, 'doc_id', d.doc_id, 'bill_no', b.bill_no, 'bill_date', b.bill_date, 'supplier', sp.name, 'total', b.total) order by b.bill_date, b.bill_no)
                      from public.landed_cost_docs d join public.purchase_bills b on b.id = d.bill_id join public.suppliers sp on sp.id = b.supplier_id where d.cost_id = p_id), '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) - 'cost_id' order by l.line_no) from public.landed_cost_lines l where l.cost_id = p_id), '[]'::jsonb),
    'basis', coalesce((select jsonb_agg(to_jsonb(b) - 'cost_id') from public.landed_cost_basis b where b.cost_id = p_id), '[]'::jsonb),
    'alloc', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'charge_line_id', a.charge_line_id, 'bill_line_id', a.bill_line_id, 'item_id', a.item_id, 'part', a.part, 'amount', a.amount, 'dr_key', a.dr_key) order by a.id)
                       from public.landed_cost_alloc a where a.cost_id = p_id), '[]'::jsonb),
    'stock', coalesce((select jsonb_agg(to_jsonb(x) - 'cost_id' order by x.id) from public.landed_cost_stock x where x.cost_id = p_id), '[]'::jsonb),
    'preview', s,
    'can', jsonb_build_object('approve', public._landed_ok97(h.location_id, 'approve'), 'entry', true),
    'rules', jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'requires_approval', coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn')));
end $$;

create or replace function public.landed_list(p_status text default null, p_bill uuid default null, p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(z order by z.cost_date desc, z.created_at desc) from (
    select c.id, c.status, c.location_id, c.shipment_ref, c.title, c.cost_date, c.total, c.alloc_method, c.created_staff, c.created_at, c.posted_at,
           (select count(*) from public.landed_cost_docs d where d.cost_id = c.id) as n_bills
      from public.landed_costs c
     where (p_status is null or c.status = p_status) and (p_bill is null or exists (select 1 from public.landed_cost_docs d where d.cost_id = c.id and d.bill_id = p_bill))
       and public._landed_ok97(c.location_id, 'entry')
     order by c.cost_date desc, c.created_at desc limit least(greatest(coalesce(p_limit, 50), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.landed_reminders(p_days integer default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare days int := coalesce(p_days, public.rule_num('landed_reminder_days')::int, 30); mode_ text := coalesce(public.rule_txt('landed_cost_mode'), 'off'); rows_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('landed_reminder_on') then return jsonb_build_object('on', false, 'mode', mode_, 'rows', '[]'::jsonb); end if;
  select coalesce(jsonb_agg(z order by z.bill_date desc, z.bill_no), '[]'::jsonb) into rows_ from (
    select b.id as bill_id, b.bill_no, b.bill_date, b.total, b.location_id, b.supplier_id, s.name as supplier, f.kind as flag,
           case when f.supplier_id is not null then 'supplier_' || f.kind else 'every_bill' end as why,
           exists (select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = b.id and c.status in ('draft', 'approved')) as in_progress
      from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
      left join public.landed_supplier_flags f on f.supplier_id = b.supplier_id and f.active
     where b.kind = 'bill' and b.status = 'posted' and b.bill_date >= (now() at time zone 'Asia/Dhaka')::date - days
       and (f.supplier_id is not null or mode_ = 'per_bill')
       and not exists (select 1 from public.landed_cost_docs d join public.landed_costs c on c.id = d.cost_id where d.bill_id = b.id and c.status = 'posted')
       and not exists (select 1 from public.landed_skips k where k.bill_id = b.id)
       and public._landed_ok97(b.location_id, 'entry')
     order by b.bill_date desc limit 200) z;
  return jsonb_build_object('on', true, 'mode', mode_, 'days', days, 'rows', rows_, 'count', jsonb_array_length(rows_));
end $$;

create or replace function public.landed_return_info(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.purchase_bills; orig uuid; items_ jsonb; tot numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(b.location_id, 'entry') then raise exception 'not allowed'; end if;
  orig := case when b.kind = 'return' then b.ref_bill_id else b.id end;
  if orig is null then return jsonb_build_object('original', null, 'has_landed', false, 'items', '[]'::jsonb, 'total', 0); end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'returned_qty', z.rq, 'lot_qty', z.lq, 'landed_per_unit', z.lpu, 'landed_on_returned', round(z.rq * z.lpu, 2)) order by z.code), '[]'::jsonb),
         coalesce(sum(round(z.rq * z.lpu, 2)), 0) into items_, tot
  from (
    select pl.item_id, it.code, sum(pl.base_qty) as lq,
           coalesce((select sum(r.base_qty) from public.purchase_bills rb join public.purchase_lines r on r.bill_id = rb.id
                      where rb.kind = 'return' and rb.status = 'posted' and rb.ref_bill_id = orig and r.item_id = pl.item_id and (b.kind <> 'return' or rb.id = b.id)), 0) as rq,
           coalesce((select sum(a.amount) from public.landed_cost_alloc a join public.landed_costs c on c.id = a.cost_id join public.landed_cost_docs d on d.cost_id = c.id and d.bill_id = orig
                      where a.item_id = pl.item_id and c.status = 'posted' and a.part in ('stock', 'cogs') and a.kind = 'post'), 0) / nullif(sum(pl.base_qty), 0) as lpu
      from public.purchase_lines pl join public.items it on it.id = pl.item_id where pl.bill_id = orig and pl.item_id is not null group by pl.item_id, it.code) z
  where z.lpu is not null and z.lpu <> 0;
  return jsonb_build_object('original', orig, 'has_landed', jsonb_array_length(items_) > 0, 'items', items_, 'total', tot,
    'note', jsonb_build_object('bn', 'ফেরতের মালের সাথে যে landed cost যুক্ত ছিল তা সরবরাহকারী ফেরত দেয় না — ক্রয় ফেরতের দামের পার্থক্য (purchase variance) হিসেবে থেকে যায়। সরবরাহকারী ওই ভাড়া ফেরত দিলে একটি ঋণাত্মক landed খরচ লিখুন।',
      'mix', 'ফেরত দেওয়া মালের সাথে যে landed cost যুক্ত ছিল তা supplier ফেরত দেয় না — purchase return variance হিসেবে থেকে যায়। Supplier ওই charge ফেরত দিলে একটি negative landed charge লিখুন।',
      'en', 'The landed cost carried by the returned goods is not refunded by the supplier: it stays as a purchase return price variance. If the supplier also refunds that charge, enter a negative landed charge.'));
end $$;

create or replace function public.landed_info() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', coalesce(public.rule_txt('landed_cost_mode'), 'off'), 'alloc_default', coalesce(public.rule_txt('landed_alloc_default'), 'value'),
    'late_mode', coalesce(public.rule_txt('landed_late_mode'), 'split_remaining_and_cogs'), 'requires_approval', coalesce(public.rule_txt('landed_cost_requires_approval'), 'warn'),
    'reminder_on', public.rule_on('landed_reminder_on'), 'journal_ready', public._landed_journal_ready97(), 'base_currency', upper(coalesce(public.rule_txt('landed_base_currency'), 'BDT')),
    'can_entry', public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now())),
    'can_approve', public.is_owner() or public.has_grant('landed_approve', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'landed_approve' and (g.valid_until is null or g.valid_until > now())),
    'charge_types', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'name_mix', coalesce(t.name_mix, t.name_en), 'treatment', t.treatment, 'default_alloc', t.default_alloc,
                      'hint_bn', t.hint_bn, 'hint_mix', t.hint_mix, 'hint_en', t.hint_en, 'active', t.active, 'is_system', t.is_system) order by t.sort, t.code) from public.cost_charge_types t where t.active or public.is_owner()), '[]'::jsonb));
end $$;

-- ---------- small owner / entry tools ----------
create or replace function public.landed_charge_type_save(p_code text, p_name_bn text, p_name_en text, p_name_mix text, p_treatment text, p_expense_key text default null, p_default_alloc text default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.cost_charge_types;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,32}$' then raise exception 'bad_code'; end if;
  if p_treatment not in ('capitalise', 'expense_only', 'recoverable_tax') then raise exception 'bad_treatment'; end if;
  if p_default_alloc is not null and p_default_alloc not in ('qty', 'value', 'weight', 'volume', 'equal') then raise exception 'bad_method'; end if;
  if p_treatment = 'expense_only' and p_expense_key is not null and not exists (select 1 from public.acct_mappings where key = p_expense_key) then raise exception 'mapping_missing:%', p_expense_key; end if;
  select * into t from public.cost_charge_types where code = p_code;
  if found then
    update public.cost_charge_types set treatment = p_treatment, expense_key = case when p_treatment = 'expense_only' then p_expense_key end, default_alloc = case when p_treatment = 'capitalise' then p_default_alloc end, active = coalesce(p_active, active),
           name_bn = case when is_system then name_bn else coalesce(nullif(btrim(p_name_bn), ''), name_bn) end,
           name_en = case when is_system then name_en else coalesce(nullif(btrim(p_name_en), ''), name_en) end,
           name_mix = case when is_system then name_mix else coalesce(nullif(btrim(p_name_mix), ''), name_mix) end where code = p_code;
  else
    if nullif(btrim(p_name_bn), '') is null or nullif(btrim(p_name_en), '') is null then raise exception 'name_required'; end if;
    insert into public.cost_charge_types (code, name_bn, name_en, name_mix, treatment, expense_key, default_alloc, sort, active, is_system, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), nullif(btrim(p_name_mix), ''), p_treatment, case when p_treatment = 'expense_only' then p_expense_key end, case when p_treatment = 'capitalise' then p_default_alloc end, 500, coalesce(p_active, true), false, auth.uid());
  end if;
  return jsonb_build_object('code', p_code, 'treatment', p_treatment);
end $$;

create or replace function public.landed_logistics_set(p_item uuid, p_weight_kg numeric, p_volume_l numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now()))) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if (p_weight_kg is not null and not (p_weight_kg > 0 and p_weight_kg < 1000000)) or (p_volume_l is not null and not (p_volume_l > 0 and p_volume_l < 1000000)) then raise exception 'bad_value'; end if;
  insert into public.item_logistics (item_id, unit_weight_kg, unit_volume_l, note, set_by) values (p_item, p_weight_kg, p_volume_l, left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (item_id) do update set unit_weight_kg = excluded.unit_weight_kg, unit_volume_l = excluded.unit_volume_l, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('item_id', p_item, 'unit_weight_kg', p_weight_kg, 'unit_volume_l', p_volume_l);
end $$;

create or replace function public.landed_supplier_flag_set(p_supplier uuid, p_kind text, p_active boolean default true, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('landed_entry', null) or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('landed_entry', 'landed_approve') and (g.valid_until is null or g.valid_until > now()))) then raise exception 'not allowed'; end if;
  if p_kind not in ('imported', 'extra_charges') then raise exception 'bad_kind'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier) then raise exception 'supplier_not_found'; end if;
  insert into public.landed_supplier_flags (supplier_id, kind, active, note, set_by) values (p_supplier, p_kind, coalesce(p_active, true), left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (supplier_id) do update set kind = excluded.kind, active = excluded.active, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('supplier_id', p_supplier, 'kind', p_kind, 'active', coalesce(p_active, true));
end $$;

create or replace function public.landed_skip(p_bill uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.purchase_bills;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into b from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._landed_ok97(b.location_id, 'entry') then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  insert into public.landed_skips (bill_id, reason) values (p_bill, left(btrim(p_reason), 200)) on conflict (bill_id) do nothing;
  return jsonb_build_object('bill_id', p_bill, 'skipped', true);
end $$;

-- ---------- privileges: signed-in users call the RPCs; every internal function stays closed ----------
revoke all on function public.landed_preview(uuid[], jsonb, jsonb, text, text), public.landed_recommendation(uuid[], uuid, jsonb, jsonb), public.landed_save(uuid, uuid, jsonb, jsonb, jsonb, jsonb),
  public.landed_approve(uuid), public.landed_post(uuid, uuid), public.landed_void(uuid, text), public.landed_get(uuid), public.landed_list(text, uuid, integer), public.landed_reminders(integer),
  public.landed_return_info(uuid), public.landed_info(), public.landed_charge_type_save(text, text, text, text, text, text, text, boolean), public.landed_logistics_set(uuid, numeric, numeric, text),
  public.landed_supplier_flag_set(uuid, text, boolean, text), public.landed_skip(uuid, text) from public, anon;
grant execute on function public.landed_preview(uuid[], jsonb, jsonb, text, text), public.landed_recommendation(uuid[], uuid, jsonb, jsonb), public.landed_save(uuid, uuid, jsonb, jsonb, jsonb, jsonb),
  public.landed_approve(uuid), public.landed_post(uuid, uuid), public.landed_void(uuid, text), public.landed_get(uuid), public.landed_list(text, uuid, integer), public.landed_reminders(integer),
  public.landed_return_info(uuid), public.landed_info(), public.landed_charge_type_save(text, text, text, text, text, text, text, boolean), public.landed_logistics_set(uuid, numeric, numeric, text),
  public.landed_supplier_flag_set(uuid, text, boolean, text), public.landed_skip(uuid, text) to authenticated;

-- ---------- the accounts follow: _acct_docs = phase515 body + two bos97 blocks ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
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

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);
end $function$;

-- ---------------------------------------------------------------- phase524.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase98.sql there and is already pasted on the live database under that name.
-- Renumbered to phase524.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 524 (bos98) - STEP INT3: the final merge of the functions that phase522 and phase523 both re-create.
--   Needs phases 72..97 pasted first (guard below). Paste order: ... phase520, phase522, phase523, phase524 - it goes LAST.
--   Problem it fixes: phase522 and phase523 each re-create _acct_docs from the phase515 body. Pasted one after the other, the later file silently erases the
--   other one's lines (phase523 after phase522 drops every bos96 line = the stock_ledger_eff96 reads of the cost-waiting step; phase522 after phase523 would drop the
--   landed-cost blocks). The same happens when phase515 is pasted again.
--   What it does: create or replace of 5 functions, nothing else. No table, rule, data, privilege or trigger is touched.
--     _acct_docs(date)  = phase515 body + all bos96 lines + both bos97 blocks (3-way merge, no conflict; one new comment line tagged bos98)
--     _acct_inv_split72, _acct_stock_moves85, _pvar85, inventory_vs_gl = the phase522 bodies, re-asserted byte-identical
--   Additive, paste-twice safe (a second paste changes no function body). If phase515, 522 or 523 is ever pasted again, paste phase524 again after it.
--   Each create runs only if the guards passed (session flag phase524.ok).
--   BODY GUARD: if a live body carries a tag this file does not know (a newer phase), it stops instead of overwriting it.
-- ============================================================

-- ---------- guard: every phase 72..97 must be there (one marker object per phase) ----------
do $g$ begin perform set_config('phase98.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if coalesce(position('bos72' in pg_get_functiondef(to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'))), 0) = 0 then miss := miss || ' 79'; end if;
  if coalesce(position('bos89' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))), 0) = 0 then miss := miss || ' 89'; end if;
  if miss <> '' then
    raise exception 'phase524 needs phases 72..97 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase98.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with an unknown (newer) tag is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase98.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._acct_docs(date)', array['bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89', 'bos96', 'bos97', 'bos98']::text[]),
    ('public._acct_inv_split72(text[],text,text[],integer)', array['bos72', 'bos85', 'bos96']::text[]),
    ('public._acct_stock_moves85(date)', array['bos72', 'bos85', 'bos96']::text[]),
    ('public._pvar85(uuid)', array['bos72', 'bos85', 'bos96']::text[]),
    ('public.inventory_vs_gl(date,integer)', array['bos72', 'bos85', 'bos96']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase524: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase98.ok', 'on', false);
end $g$;
-- the five statements below run only when both guards passed (a failed guard on a client that keeps going after an error changes nothing)

-- ---- public._acct_docs(date) ----
do $p98$ begin if current_setting('phase98.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
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
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
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

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);
end $function$
$f$; end if; end $p98$;

-- ---- public._acct_inv_split72(text[],text,text[],integer) ----
do $p98$ begin if current_setting('phase98.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_inv_split72(p_ref_types text[], p_ref_id text, p_reasons text[], p_sign integer)
 RETURNS TABLE(t text, amt numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with g as (
    select it.item_type as ty, sum(p_sign * l.qty_delta * l.unit_cost) as raw
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id /* bos96 */
    where l.ref_type = any (p_ref_types) and l.ref_id = p_ref_id and l.reason = any (p_reasons) and l.unit_cost is not null group by it.item_type),
  r as (select ty, round(raw, 2) as a, row_number() over (order by round(raw, 2) desc, ty nulls last) as rn from g),
  d as (select round((select sum(raw) from g), 2) - (select sum(a) from r) as rest)
  select r.ty, r.a + case when r.rn = 1 then (select rest from d) else 0 end from r;
$function$
$f$; end if; end $p98$;

-- ---- public._acct_stock_moves85(date) ----
do $p98$ begin if current_setting('phase98.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer' end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal')
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_stock_actions96 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$
$f$; end if; end $p98$;

-- ---- public._pvar85(uuid) ----
do $p98$ begin if current_setting('phase98.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._pvar85(p_bill uuid)
 RETURNS TABLE(nulls integer, nonzero boolean, lines jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with lo as (select public._acct_buy_key(it.item_type) k, sum(round(-l.qty_delta * coalesce(l.unit_cost, 0), 2)) a, count(*) filter (where coalesce(l.unit_cost, 0) = 0) n
                from public.stock_ledger_eff96 l join public.items it /* bos96 */ on it.id = l.item_id
               where l.ref_type = 'purchase' and l.reason = 'purchase_return' and l.ref_id = p_bill::text and public._acct_buy_key(it.item_type) in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       jc as (select al.k, sum(al.amt) a from public._acct_purchase_alloc(p_bill) al where al.k in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       dd as (select coalesce(lo.k, jc.k) k, round(coalesce(lo.a, 0) - coalesce(jc.a, 0), 2) df from lo full join jc on jc.k = lo.k),
       nz as (select * from dd where df <> 0),
       tot as (select coalesce(sum(df), 0) net from nz)
  select coalesce((select sum(n) from lo), 0)::int, exists (select 1 from nz),
         (select jsonb_agg(j) from (
            select jsonb_build_object('a', k, case when df > 0 then 'c' else 'd' end, abs(df)) j from nz
            union all select jsonb_build_object('a', 'purchase_variance', case when net > 0 then 'd' else 'c' end, abs(net)) from tot where net <> 0) x);
$function$
$f$; end if; end $p98$;

-- ---- public.inventory_vs_gl(date,integer) ----
do $p98$ begin if current_setting('phase98.ok', true) = 'on' then execute $f$
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
            from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening', 'opening_stock96') /* bos85 bos96 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
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
$f$; end if; end $p98$;

-- ---------------------------------------------------------------- phase525.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase99.sql there and is already pasted on the live database under that name.
-- Renumbered to phase525.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 525 (bos99) - STEP Opt: two OPTIONS the owner can switch at any time (both default = today's behaviour; the system only shows a recommendation).
--   Needs phases 72..98 (guard below; phase524 = step INT3, the final merge of _acct_docs of 96 + 97). Paste order: ... phase520, phase522, phase523, phase524, phase525 (LAST).
--   phase524 does not touch the five functions re-created here, and phase525 does not touch _acct_docs; if phase524 or phase515 is ever pasted again nothing of phase525 is lost.
--   Additive + paste-twice safe. Re-created (latest definitions, only lines tagged bos99 differ): inbox_list, inbox_get, online_orders_list, online_order_get, telegram_chat_info.
--   Nothing else existing is re-created: the payment hooks are TRIGGERS on cost_source_bills / purchase_bills / supplier_payments (no function of phase75/508/513/515 is touched).
--
--   DECISION 1 - does a saved cost bill / purchase bill create a payment record by itself?
--     rule cost_bill_creates_payment      off (DEFAULT = today: a cost bill is information only) | ask | auto_cash | auto_bank | auto_by_supplier_default
--     rule purchase_bill_creates_payment  same five values (purchase bill: acts when the bill is POSTED)
--     rule bill_void_payment_mode         void (DEFAULT) | keep_credit    what happens to a payment made through this feature when its bill is voided
--     rule bill_pay_auto_credit_ok        switch, DEFAULT off: auto modes never pay a bill of a party marked "credit terms" (supplier credit_days > 0 or the credit flag) unless on
--     rules bill_pay_large_amount / bill_pay_small_cash_max   numbers the OWNER types (blank = none, nothing built in) used only by payment_recommendation()
--     The payment is the SAME record the rest of the system already counts: a purchase bill payment = supplier_payments (bill_id set, purchase_bills.paid updated);
--     a cost bill payment = quick_expenses (path A of the expense domain: path_guard 'expense' respected, locked shadow 10-2 owed at day end, client_id idempotent,
--     journal source quick_expense unique by je_source_uq, void = status void -> the engine posts the reversing entry). Mode "other" on a cost bill is a NOTE ONLY row
--     (not in the cash book / journal, said so on screen). bill_payments99 is the link ledger (append-only; only active -> void | kept_credit).
--     Never twice: remaining = bill - what is paid (purchase: the supplier open amount after oldest-first credit); a 10-2 or quick expense that looks like the same cost
--     gives a warning that must be confirmed (auto modes skip instead and leave a yellow flag).
--     payment_recommendation(kind, ref): ask for large / credit-term bills, auto_cash (or auto_bank) for small no-credit bills of a party whose default mode is cash (bank), else ask.
--   DECISION 2 - inbox customer phone / address masking.
--     rule inbox_pii_mode  off (DEFAULT = today) | mask_phone | mask_phone_address | mask_all_pii. inbox_pii_guard_on is untouched (guard on = people without the contact right see nothing, as today).
--     inbox_unmask(kind, id, reason): the person with grant inbox_unmask (owner always) reveals ONE message / order; every reveal is written to inbox_unmask_log99 (who, when, which
--     message / order, which fields, reason) and to audit_log; rule inbox_unmask_daily_max (owner types, blank = none; the owner himself is not limited).
--     NOT masked by this rule: direct table reads of online_orders.customer_mobile / address (use inbox_pii_guard_on for that) and the order edit form of salesx.js.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.set_doc_template(text,text,integer)'), ('94', 'public._scan_photo_ok(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.drawer_events') is null then miss := miss || ' 95'; end if;
  if to_regclass('public.opening_stock_actions96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos98%' then miss := miss || ' 98'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)') is null
     or pg_get_functiondef('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure) not like '%bos72%' then miss := miss || ' 79'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is not null
     and pg_get_functiondef('public._cogs_lines72(date,date,integer[])'::regprocedure) not like '%bos89%' then miss := miss || ' 89'; end if;
  if miss <> '' then
    raise exception 'phase525 needs phases 72..98 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cost_bill_creates_payment', 'purchase', 'choice', '"off"', null, '["off","ask","auto_cash","auto_bank","auto_by_supplier_default"]'::jsonb, null, null,
  'cost bill সেভ করলে payment এন্ট্রি হবে কি?', 'Cost bill save করলে payment entry হবে কি?', 'Does saving a cost bill create a payment?',
  'off = আজকের নিয়ম (bill শুধু তথ্য)। ask = সেভের পর "এখনই payment লিখবেন?" জিজ্ঞেস করবে। auto_* = নিজে লিখবে (credit-শর্তের পক্ষ বাদ)।',
  'off = today (a cost bill is information only). ask = after saving it offers "Record payment now?". auto_* = records it by itself (parties with credit terms are skipped).', 641),
 ('purchase_bill_creates_payment', 'purchase', 'choice', '"off"', null, '["off","ask","auto_cash","auto_bank","auto_by_supplier_default"]'::jsonb, null, null,
  'purchase bill পোস্ট করলে payment এন্ট্রি হবে কি?', 'Purchase bill post করলে payment entry হবে কি?', 'Does posting a purchase bill create a payment?',
  'off = আজকের নিয়ম (payment আলাদা বা পোস্টের সময় লেখা)। ask = পোস্টের পর জিজ্ঞেস করবে। auto_* = বাকি পুরোটা নিজে লিখবে (credit-শর্তের supplier বাদ)।',
  'off = today (payment is written separately or at posting). ask = offers it after posting. auto_* = pays the whole open amount by itself (suppliers with credit terms are skipped).', 642),
 ('bill_void_payment_mode', 'purchase', 'choice', '"void"', null, '["void","keep_credit"]'::jsonb, null, null,
  'bill বাতিল হলে এই সুবিধায় লেখা payment-এর কী হবে?', 'Bill void হলে এই feature-এ লেখা payment-এর কী হবে?', 'When the bill is voided, what happens to a payment made through this option?',
  'void = payment-ও বাতিল (উল্টো এন্ট্রি যায়)। keep_credit = payment থাকে; ক্রয়ে supplier-এর credit হয়ে যায়।',
  'void = the payment is voided too (a reversing entry follows). keep_credit = the payment stays; for a purchase it becomes supplier credit.', 643),
 ('bill_pay_auto_credit_ok', 'purchase', 'switch', 'false', null, null, null, null,
  'credit-শর্তের পক্ষেও auto payment চলবে', 'Credit-terms এর পক্ষেও auto payment চলবে', 'Allow auto payment for parties with credit terms',
  'বন্ধ থাকলে auto mode কখনো credit-শর্তের supplier/source-এর bill শোধ করে না।', 'When off, an auto mode never pays a bill of a supplier / source that has credit terms.', 644),
 ('bill_pay_large_amount', 'purchase', 'number', null, 'টাকা', null, 0, 1000000000000, 'বড় bill-এর সীমা (প্রস্তাবনার জন্য)', 'Large bill এর সীমা (recommendation এর জন্য)', 'Large bill amount (for the recommendation)',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। এর সমান বা বেশি হলে প্রস্তাব সবসময় "ask"।', 'You type it; blank = none. At or above it the recommendation is always "ask".', 645),
 ('bill_pay_small_cash_max', 'purchase', 'number', null, 'টাকা', null, 0, 1000000000000, 'ছোট cash bill-এর সীমা (প্রস্তাবনার জন্য)', 'Small cash bill এর সীমা (recommendation এর জন্য)', 'Small cash bill amount (for the recommendation)',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। এর সমান বা কম, credit ছাড়া, cash পক্ষের bill-এ প্রস্তাব "auto_cash"।', 'You type it; blank = none. At or below it, with no credit and a cash party, the recommendation is "auto_cash".', 646),
 ('inbox_pii_mode', 'pos', 'choice', '"off"', null, '["off","mask_phone","mask_phone_address","mask_all_pii"]'::jsonb, null, null,
  'inbox-এ গ্রাহকের তথ্য ঢাকা', 'Inbox এ customer এর তথ্য ঢাকা', 'Mask customer details in the inbox',
  'off = আজকের নিয়ম। mask_phone = phone ঢাকা। mask_phone_address = phone ও address ঢাকা। mask_all_pii = নাম, handle, message-এর লেখা ও attachmentও ঢাকা। অনুমতিপ্রাপ্ত মানুষ একটি একটি করে খুলতে পারেন (log-এ থাকে)।',
  'off = today. mask_phone = phone hidden. mask_phone_address = phone and address hidden. mask_all_pii = name, handle, message text and attachment hidden too. Authorised people reveal one at a time (logged).', 647),
 ('inbox_unmask_daily_max', 'pos', 'number', null, 'বার', null, 1, 100000, 'একজন দিনে সর্বোচ্চ কতবার খুলতে পারবে', 'একজন দিনে সর্বোচ্চ কতবার unmask করতে পারবে', 'Max reveals per person per day',
  'আপনি লিখবেন; ফাঁকা = সীমা নেই। মালিকের ওপর সীমা খাটে না।', 'You type it; blank = no limit. The owner is not limited.', 648)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'inbox_unmask', 'pos', 96, 'inbox-এ ঢাকা গ্রাহকের তথ্য খোলা (প্রতিবার log-এ থাকে)', 'Inbox এ ঢাকা customer এর তথ্য খোলা (প্রতিবার log এ থাকে)', 'Reveal masked customer details in the inbox (every reveal is logged)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'inbox_unmask');

-- ---------- tables ----------
-- per supplier / per cost source: the usual payment mode and "has credit terms". Owner writes only (bill_pay_default_set99).
create table if not exists public.bill_pay_defaults99 (
  id bigserial primary key,
  party_kind text not null check (party_kind in ('supplier', 'cost_source')),
  party_id text not null check (char_length(party_id) between 1 and 60),
  pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile', 'card')),
  credit_terms boolean not null default false,
  note text check (note is null or char_length(note) <= 200),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (party_kind, party_id)
);
drop trigger if exists audit_bill_pay_defaults99 on public.bill_pay_defaults99;
create trigger audit_bill_pay_defaults99 after insert or update on public.bill_pay_defaults99 for each row execute function public.log_change('id');
alter table public.bill_pay_defaults99 enable row level security;
revoke all on public.bill_pay_defaults99 from public, anon, authenticated;
drop policy if exists bill_pay_defaults99_sel on public.bill_pay_defaults99;
create policy bill_pay_defaults99_sel on public.bill_pay_defaults99 for select to authenticated using (public.is_owner());

-- the link ledger: one row per payment made through this option (the money itself lives in quick_expenses / supplier_payments)
create table if not exists public.bill_payments99 (
  id bigserial primary key,
  bill_kind text not null check (bill_kind in ('cost', 'purchase')),
  bill_ref text not null,
  location_id int references public.locations(id),
  mode text not null check (mode in ('cash', 'bank', 'mobile', 'card', 'other')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  origin text not null check (origin in ('auto', 'ask')),
  money_type text not null check (money_type in ('quick_expense', 'supplier_payment', 'note_only')),
  money_ref text,
  status text not null default 'active' check (status in ('active', 'void', 'kept_credit')),
  note text check (note is null or char_length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  closed_by uuid, closed_at timestamptz, closed_note text
);
create index if not exists bp99_bill on public.bill_payments99 (bill_kind, bill_ref);
create unique index if not exists bp99_auto_once on public.bill_payments99 (bill_kind, bill_ref) where origin = 'auto' and status = 'active';
drop trigger if exists audit_bill_payments99 on public.bill_payments99;
create trigger audit_bill_payments99 after insert or update on public.bill_payments99 for each row execute function public.log_change('id');
create or replace function public._bp_ro99() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'active' and new.status in ('void', 'kept_credit')
     and (to_jsonb(new) - 'status' - 'closed_by' - 'closed_at' - 'closed_note') = (to_jsonb(old) - 'status' - 'closed_by' - 'closed_at' - 'closed_note') then return new; end if;
  raise exception 'append_only: a bill payment row cannot be changed or deleted (it can only be voided or kept as credit)';
end $$;
drop trigger if exists bp99_ro on public.bill_payments99;
create trigger bp99_ro before update or delete on public.bill_payments99 for each row execute function public._bp_ro99();
alter table public.bill_payments99 enable row level security;
revoke all on public.bill_payments99 from public, anon, authenticated;
grant select on public.bill_payments99 to authenticated;
drop policy if exists bill_payments99_sel on public.bill_payments99;
create policy bill_payments99_sel on public.bill_payments99 for select to authenticated
  using (public.is_owner() or (public.can_loc(location_id) and (case when bill_kind = 'cost' then public._cs_view() else public._pur_ok(location_id) end)));

-- append-only log of every reveal of masked customer details
create table if not exists public.inbox_unmask_log99 (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  kind text not null check (kind in ('message', 'order')),
  ref_id text not null,
  location_id int,
  fields text,
  reason text check (reason is null or char_length(reason) <= 300),
  outcome text not null check (outcome in ('revealed', 'blocked'))
);
create index if not exists iul99_user_day on public.inbox_unmask_log99 (user_id, at);
create or replace function public._inb_unmask_ro99() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the reveal log cannot be changed or deleted'; end $$;
drop trigger if exists iul99_ro on public.inbox_unmask_log99;
create trigger iul99_ro before update or delete on public.inbox_unmask_log99 for each row execute function public._inb_unmask_ro99();
alter table public.inbox_unmask_log99 enable row level security;
revoke all on public.inbox_unmask_log99 from public, anon, authenticated;
drop policy if exists inbox_unmask_log99_sel on public.inbox_unmask_log99;
create policy inbox_unmask_log99_sel on public.inbox_unmask_log99 for select to authenticated using (public.is_owner());
grant select on public.inbox_unmask_log99 to authenticated;

-- ============================================================
-- DECISION 1 helpers
-- ============================================================
create or replace function public._bp_today99() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- the 10-2 head a cost type falls under (same convention as the duplicate guard of cost_bill_add)
create or replace function public._bp_head99(p_cost_type text) returns text language sql immutable as $$
  select case when p_cost_type in ('electricity', 'gas', 'water', 'internet', 'machine_repair') then 'repair' else 'other' end $$;
create or replace function public._bp_uuid99(p_kind text, p_ref text) returns uuid language sql immutable as $$ select md5('bos99auto:' || p_kind || ':' || p_ref)::uuid $$;

-- warnings that this payment may count the same cost a second time: [] when clean
create or replace function public._bp_dup99(p_kind text, p_ref text, p_amount numeric) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare w text[] := '{}'; cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; sn text; heads text[]; locs int[];
begin
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then return w; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select array_agg(location_id) into locs from public.cost_source_locs where source_id = cb.source_id;
    heads := array[public._bp_head99(cs.cost_type)];
    if not cb.dup_ack and exists (
         select 1 from public.entries en cross join lateral jsonb_array_elements(case when jsonb_typeof(en.data->'lines') = 'array' then en.data->'lines' else '[]'::jsonb end) ln
          where en.form_code = '10-2' and en.status in ('submitted', 'approved') and en.location_id = any (coalesce(locs, '{}'))
            and public._m1(en.entry_date) = cb.period_month and lower(coalesce(ln->>'head', '')) = any (heads) and public._acct_num(ln->>'amount') in (cb.amount, p_amount)) then
      w := array_append(w, 'form_10_2_matches');
    end if;
    if exists (select 1 from public.quick_expenses q
                where q.status = 'done' and q.location_id = any (coalesce(locs, '{}')) and q.head = any (heads) and q.amount in (cb.amount, p_amount)
                  and q.exp_date >= cb.period_month
                  and not exists (select 1 from public.bill_payments99 b where b.money_type = 'quick_expense' and b.money_ref = q.id::text)) then
      w := array_append(w, 'quick_expense_similar');
    end if;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then return w; end if;
    select lower(btrim(name)) into sn from public.suppliers where id = pb.supplier_id;
    if sn is not null and exists (select 1 from public.quick_expenses q where q.status = 'done' and q.location_id = pb.location_id and lower(btrim(coalesce(q.paid_to, ''))) = sn
                                   and q.amount = p_amount and q.exp_date >= pb.bill_date
                                   and not exists (select 1 from public.bill_payments99 b where b.money_type = 'quick_expense' and b.money_ref = q.id::text)) then
      w := array_append(w, 'quick_expense_similar');
    end if;
  end if;
  return w;
end $$;

-- THE one place where a payment is written. Cost bill -> quick expense (path A) ; purchase bill -> supplier payment tied to the bill. Callers gate who may call it.
create or replace function public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for update;                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $$;

-- the sheet's call (mode ask) and the list's "record payment" button
create or replace function public.bill_pay_record(p_kind text, p_ref text, p_mode text, p_amount numeric default null, p_client uuid default null, p_note text default null, p_confirm_dup boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; cb public.cost_source_bills; pb public.purchase_bills;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_enter() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'bill_pay:' || p_ref, p_amount)) then raise exception 'not allowed'; end if;
  else
    raise exception 'bad_ref';
  end if;
  return public._bp_pay99(p_kind, p_ref, p_mode, p_amount, 'ask', p_client, p_note, p_confirm_dup);
end $$;

-- ---------- AUTO modes: triggers (a failure never blocks the bill; it leaves a yellow flag and the bill stays in "Bills without payment") ----------
create or replace function public._bp_auto99(p_kind text, p_ref text, p_loc int, p_party_kind text, p_party_id text, p_rule text, p_credit_days int, p_bill_mode text) returns void
language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt(p_rule), 'off'); d public.bill_pay_defaults99; pm text; credit boolean; r jsonb; frm text := case when p_kind = 'cost' then 'STOCK' else 'PURCHASE' end;
begin
  if mode_ not in ('auto_cash', 'auto_bank', 'auto_by_supplier_default') then return; end if;
  begin                                                   -- nothing in here may stop the bill itself from being saved / posted
    select * into d from public.bill_pay_defaults99 where party_kind = p_party_kind and party_id = p_party_id;
    credit := coalesce(d.credit_terms, false) or coalesce(p_credit_days, 0) > 0;
    if credit and not public.rule_on('bill_pay_auto_credit_ok') then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'credit-শর্তের পক্ষ: স্বয়ংক্রিয় payment হয়নি, bill payment-এর অপেক্ষায়', 'Party has credit terms: no automatic payment made; the bill waits for a payment', null, null, frm, null);
      return;
    end if;
    pm := case mode_ when 'auto_cash' then 'cash' when 'auto_bank' then 'bank'
            else coalesce(d.pay_mode, case when p_bill_mode in ('cash', 'bank', 'mobile') then p_bill_mode end) end;
    if pm is null then return; end if;                    -- by_supplier_default with no default known = behaves like "ask" (the list offers it)
    r := public._bp_pay99(p_kind, p_ref, pm, null, 'auto', public._bp_uuid99(p_kind, p_ref), 'automatic (rule ' || p_rule || ')', false);
    if not coalesce((r->>'ok')::boolean, false) then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: একই খরচ আগেই লেখা থাকতে পারে (' || coalesce(r->>'warnings', '') || ')', 'Automatic payment not made: the same cost may already be recorded (' || coalesce(r->>'warnings', '') || ')', null, null, frm, null);
    end if;
  exception when others then
    begin
      perform public._stock_exc(p_loc, 'bill_pay_auto_failed', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: ' || left(sqlerrm, 120), 'Automatic payment failed: ' || left(sqlerrm, 120), null, null, frm, null);
    exception when others then null;
    end;
  end;
end $$;

create or replace function public._bp_cost_auto99() returns trigger language plpgsql security definer set search_path = public as $$
declare loc int;
begin
  if new.status <> 'active' then return new; end if;
  select min(location_id) into loc from public.cost_source_locs where source_id = new.source_id;
  perform public._bp_auto99('cost', new.id::text, loc, 'cost_source', new.source_id::text, 'cost_bill_creates_payment', null, new.pay_mode);
  return new;
end $$;
drop trigger if exists cs_bills_pay99 on public.cost_source_bills;
create trigger cs_bills_pay99 after insert on public.cost_source_bills for each row execute function public._bp_cost_auto99();

create or replace function public._bp_pur_auto99() returns trigger language plpgsql security definer set search_path = public as $$
declare cd int;
begin
  if new.status <> 'posted' or old.status is not distinct from 'posted' or new.kind <> 'bill' or new.paid > 0 then return new; end if;     -- the poster already paid something: his choice stands
  select credit_days into cd from public.suppliers where id = new.supplier_id;
  perform public._bp_auto99('purchase', new.id::text, new.location_id, 'supplier', new.supplier_id::text, 'purchase_bill_creates_payment', cd, null);
  return new;
end $$;
drop trigger if exists purchase_bills_pay99 on public.purchase_bills;
create trigger purchase_bills_pay99 after update of status on public.purchase_bills for each row execute function public._bp_pur_auto99();

-- ---------- VOID of the bill ----------
-- cost bill voided: its payments follow bill_void_payment_mode. void = the quick expense is voided (the engine posts the reversing entry); a payment that is already inside a
-- day-end 10-2 form or sits in a closed period cannot be voided here: it stays (kept_credit) with a yellow flag.
create or replace function public._bp_cost_void99() returns trigger language plpgsql security definer set search_path = public as $$
declare p public.bill_payments99; keep boolean := coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit'; q public.quick_expenses; why text;
begin
  if not (new.status = 'void' and old.status = 'active') then return new; end if;
  for p in select * from public.bill_payments99 where bill_kind = 'cost' and bill_ref = new.id::text and status = 'active' order by id loop
    why := null;
    if not keep and p.money_type = 'quick_expense' then
      select * into q from public.quick_expenses where id = p.money_ref::uuid for update;
      if q.status = 'done' then
        if exists (select 1 from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed') then why := 'already in the day-end 10-2 form';
        else
          begin
            perform public.lock_check(q.exp_date);
            update public.quick_expenses set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left('cost bill #' || new.id::text || ' voided', 300) where id = q.id;
            update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'cost bill voided', 300) where primary_type = 'quick_expenses' and primary_id = q.id::text and state = 'pending';
          exception when others then why := 'period closed';
          end;
        end if;
      end if;
    end if;
    if keep or why is not null then
      update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = left(coalesce(why, 'owner rule: keep'), 300) where id = p.id;
      perform public._stock_exc(p.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment রাখা হয়েছে: ' || p.amount::text || coalesce(' (' || why || ')', ''), 'Payment of a voided cost bill was kept: ' || p.amount::text || coalesce(' (' || why || ')', ''), null, null, 'STOCK', p.amount);
    else
      update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'cost bill voided' where id = p.id;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists cs_bills_void99 on public.cost_source_bills;
create trigger cs_bills_void99 after update of status on public.cost_source_bills for each row execute function public._bp_cost_void99();

-- purchase bill voided: the stock-side void (void_purchase / _void_purchase_p13) voids bill payments BEFORE it flips the bill. keep_credit stops that for payments made through this
-- option: the payment is un-tied from the bill instead, so it remains a payment to the supplier = supplier credit (nothing is un-voided afterwards, nothing is rewritten).
create or replace function public._bp_sp_void99() returns trigger language plpgsql security definer set search_path = public as $$
declare l public.bill_payments99;
begin
  if not (new.voided and not old.voided and old.bill_id is not null) then return new; end if;
  select * into l from public.bill_payments99 where money_type = 'supplier_payment' and money_ref = old.id::text and status = 'active';
  if not found then return new; end if;
  if coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit' then
    new.voided := false; new.void_note := old.void_note; new.void_by := old.void_by; new.bill_id := null;
    update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment kept as supplier credit' where id = l.id;
    perform public._stock_exc(old.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment supplier-এর credit হিসেবে রাখা হয়েছে: ' || old.amount::text, 'Payment of a voided purchase bill kept as supplier credit: ' || old.amount::text, null, null, 'PURCHASE', old.amount);
  else
    update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'purchase bill voided' where id = l.id;
  end if;
  return new;
end $$;
drop trigger if exists supplier_payments_void99 on public.supplier_payments;
create trigger supplier_payments_void99 before update of voided on public.supplier_payments for each row execute function public._bp_sp_void99();

-- a purchase void that left payments alone (existing rule purchase_void_payments = keep): the link rows say so
create or replace function public._bp_pur_void99() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    update public.bill_payments99 l set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment not voided (rule purchase_void_payments = keep)'
     where l.bill_kind = 'purchase' and l.bill_ref = new.id::text and l.status = 'active'
       and exists (select 1 from public.supplier_payments s where s.id::text = l.money_ref and not s.voided);
  end if;
  return new;
end $$;
drop trigger if exists purchase_bills_void99 on public.purchase_bills;
create trigger purchase_bills_void99 after update of status on public.purchase_bills for each row execute function public._bp_pur_void99();

-- ---------- recommendation / info / lists ----------
create or replace function public.payment_recommendation(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare amt numeric; credit boolean := false; dm text; bm text; large numeric := public.rule_num('bill_pay_large_amount'); small numeric := public.rule_num('bill_pay_small_cash_max'); d public.bill_pay_defaults99;
        cb public.cost_source_bills; pb public.purchase_bills; cd int; rec text; why text[]; basis text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_view() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
    amt := cb.amount; bm := cb.pay_mode;
    select * into d from public.bill_pay_defaults99 where party_kind = 'cost_source' and party_id = cb.source_id::text;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public._pur_ok(pb.location_id) then raise exception 'not allowed'; end if;
    amt := pb.total; select credit_days into cd from public.suppliers where id = pb.supplier_id;
    select * into d from public.bill_pay_defaults99 where party_kind = 'supplier' and party_id = pb.supplier_id::text;
  else raise exception 'bad_ref'; end if;
  dm := coalesce(d.pay_mode, case when bm in ('cash', 'bank', 'mobile') then bm end);
  credit := coalesce(d.credit_terms, false) or coalesce(cd, 0) > 0;
  if credit then rec := 'ask'; basis := 'credit';
  elsif large is not null and amt >= large then rec := 'ask'; basis := 'large';
  elsif small is not null and amt <= small and dm = 'cash' then rec := 'auto_cash'; basis := 'small_cash';
  elsif small is not null and amt <= small and dm = 'bank' then rec := 'auto_bank'; basis := 'small_bank';
  else rec := 'ask'; basis := case when large is null and small is null then 'no_numbers' else 'default' end; end if;
  return jsonb_build_object('mode', rec, 'basis', basis, 'amount', amt, 'credit_terms', credit, 'default_pay_mode', dm, 'large_limit', large, 'small_cash_limit', small,
    'never_auto', credit,
    'reason_bn', case basis when 'credit' then 'credit-শর্তের পক্ষ: কখনো নিজে নিজে payment নয়; প্রতিবার জিজ্ঞেস করুন।' when 'large' then 'বড় bill (আপনার দেওয়া সীমার সমান বা বেশি): প্রতিবার জিজ্ঞেস করুন।'
      when 'small_cash' then 'ছোট cash bill, credit নেই: নিজে cash-এ লেখা যায়।' when 'small_bank' then 'ছোট bill, credit নেই, bank-এ দেওয়া হয়: নিজে bank-এ লেখা যায়।'
      when 'no_numbers' then 'কোনো সীমা লেখা নেই, তাই নিরাপদ পথ: জিজ্ঞেস করুন। সীমা লিখলে ছোট cash bill-এ auto প্রস্তাব আসবে।' else 'কোনো নিয়ম মেলেনি: নিরাপদ পথ হলো জিজ্ঞেস করা।' end,
    'reason_mix', case basis when 'credit' then 'Credit-terms এর পক্ষ: কখনো নিজে নিজে payment নয়; প্রতিবার জিজ্ঞেস করুন।' when 'large' then 'Large bill (আপনার দেওয়া সীমার সমান বা বেশি): প্রতিবার জিজ্ঞেস করুন।'
      when 'small_cash' then 'Small cash bill, credit নেই: নিজে cash এ লেখা যায়।' when 'small_bank' then 'Small bill, credit নেই, bank এ দেওয়া হয়: নিজে bank এ লেখা যায়।'
      when 'no_numbers' then 'কোনো সীমা লেখা নেই, তাই safe পথ: জিজ্ঞেস করুন। সীমা লিখলে small cash bill এ auto প্রস্তাব আসবে।' else 'কোনো rule মেলেনি: safe পথ হলো জিজ্ঞেস করা।' end,
    'reason_en', case basis when 'credit' then 'The party has credit terms: never automatic; ask every time.' when 'large' then 'A large bill (at or above the limit you typed): ask every time.'
      when 'small_cash' then 'A small cash bill with no credit: it can be recorded in cash automatically.' when 'small_bank' then 'A small bill with no credit, paid through the bank: it can be recorded in bank automatically.'
      when 'no_numbers' then 'No limits are typed yet, so the safe choice is to ask. Type a small-cash limit to get an automatic suggestion for small cash bills.' else 'No rule matched: the safe choice is to ask.' end);
end $$;

-- what the "Record payment now?" sheet shows
create or replace function public.bill_pay_info99(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; total numeric; paid_sum numeric := 0; rem numeric; rule_ text; nm text; modes jsonb; open_amt numeric; dm text; loc int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind = 'cost' and p_ref ~ '^[0-9]{1,18}$' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint;
    if not found then raise exception 'not_found'; end if;
    if not (public._cs_view() and public._cs_src_ok(cb.source_id)) then raise exception 'not allowed'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    total := cb.amount; rem := case when cb.status = 'active' then cb.amount - paid_sum else 0 end; rule_ := coalesce(public.rule_txt('cost_bill_creates_payment'), 'off');
    nm := coalesce(cs.provider, cs.code); modes := '["cash","bank","mobile","other"]'::jsonb; dm := cb.pay_mode;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
  elsif p_kind = 'purchase' and p_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    if not public._pur_ok(pb.location_id) then raise exception 'not allowed'; end if;
    select name into nm from public.suppliers where id = pb.supplier_id;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    total := pb.total; paid_sum := pb.paid; rem := case when pb.status = 'posted' and pb.kind = 'bill' then least(coalesce(open_amt, 0), pb.total - pb.paid) else 0 end;
    rule_ := coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'); modes := '["cash","bank","mobile","card"]'::jsonb; loc := pb.location_id;
    select pay_mode into dm from public.bill_pay_defaults99 where party_kind = 'supplier' and party_id = pb.supplier_id::text;
  else raise exception 'bad_ref'; end if;
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'party', nm, 'total', total, 'paid', paid_sum, 'remaining', greatest(rem, 0), 'rule', rule_, 'modes', modes,
    'suggest_mode', dm, 'location_id', loc, 'recommendation', public.payment_recommendation(p_kind, p_ref),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'mode', b.mode, 'amount', b.amount, 'origin', b.origin, 'status', b.status, 'counted', b.money_type <> 'note_only', 'at', b.created_at) order by b.id)
                            from public.bill_payments99 b where b.bill_kind = p_kind and b.bill_ref = p_ref), '[]'::jsonb));
end $$;

-- "Bills without payment": cost bills and posted purchase bills that still have an open amount (nothing is guessed: the list is the bill minus the recorded payments)
create or replace function public.bills_without_payment99(p_kind text default null, p_loc int default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; lim int := least(greatest(coalesce(p_limit, 200), 1), 500);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is not null and p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if (p_kind is null or p_kind = 'cost') and public._cs_view() then
    out_ := out_ || coalesce((select jsonb_agg(z.j order by z.o desc) from (
      select b.id o, jsonb_build_object('kind', 'cost', 'ref', b.id::text, 'party', coalesce(s.provider, s.code), 'bill_no', b.bill_no, 'date', coalesce(b.bill_date, b.period_month), 'total', b.amount,
             'paid', coalesce(pp.paid, 0), 'due', b.amount - coalesce(pp.paid, 0), 'location_id', (select min(location_id) from public.cost_source_locs where source_id = b.source_id)) j
        from public.cost_source_bills b join public.cost_sources s on s.id = b.source_id
        left join lateral (select sum(amount) paid from public.bill_payments99 x where x.bill_kind = 'cost' and x.bill_ref = b.id::text and x.status in ('active', 'kept_credit')) pp on true
       where b.status = 'active' and b.amount - coalesce(pp.paid, 0) > 0.004 and public._cs_src_ok(b.source_id)
         and (p_loc is null or exists (select 1 from public.cost_source_locs l where l.source_id = b.source_id and l.location_id = p_loc))
       order by b.id desc limit lim) z), '[]'::jsonb);
  end if;
  if (p_kind is null or p_kind = 'purchase') then
    out_ := out_ || coalesce((select jsonb_agg(z.j order by z.d desc) from (
      select o.bill_date d, jsonb_build_object('kind', 'purchase', 'ref', o.bill_id::text, 'party', s.name, 'bill_no', o.bill_no, 'date', o.bill_date, 'total', pb.total, 'paid', pb.paid,
             'due', least(o.open_amt, pb.total - pb.paid), 'location_id', o.location_id) j
        from public._sup_open(null) o join public.purchase_bills pb on pb.id = o.bill_id join public.suppliers s on s.id = o.supplier_id
       where o.bill_id is not null and o.open_amt > 0.004 and public._pur_ok(o.location_id) and (p_loc is null or o.location_id = p_loc)
       order by o.bill_date desc nulls last limit lim) z), '[]'::jsonb);
  end if;
  return jsonb_build_object('rows', out_, 'cost_rule', coalesce(public.rule_txt('cost_bill_creates_payment'), 'off'), 'purchase_rule', coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'));
end $$;

-- owner: the usual mode and credit terms of a supplier / cost source (the only way anything reaches bill_pay_defaults99)
create or replace function public.bill_pay_default_set99(p_kind text, p_id text, p_mode text, p_credit boolean default false, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.bill_pay_defaults99;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('supplier', 'cost_source') then raise exception 'bad_kind'; end if;
  if p_mode is not null and p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
  if p_kind = 'supplier' and not exists (select 1 from public.suppliers where id::text = p_id) then raise exception 'not_found'; end if;
  if p_kind = 'cost_source' and not exists (select 1 from public.cost_sources where id::text = p_id) then raise exception 'not_found'; end if;
  insert into public.bill_pay_defaults99 (party_kind, party_id, pay_mode, credit_terms, note, updated_by) values (p_kind, p_id, p_mode, coalesce(p_credit, false), left(nullif(btrim(p_note), ''), 200), auth.uid())
    on conflict (party_kind, party_id) do update set pay_mode = excluded.pay_mode, credit_terms = excluded.credit_terms, note = excluded.note, updated_by = auth.uid(), updated_at = now() returning * into r;
  return jsonb_build_object('id', r.id, 'kind', r.party_kind, 'party', r.party_id, 'mode', r.pay_mode, 'credit', r.credit_terms);
end $$;

create or replace function public.bill_pay_defaults_list99() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('kind', d.party_kind, 'id', d.party_id, 'mode', d.pay_mode, 'credit', d.credit_terms, 'note', d.note,
      'name', case d.party_kind when 'supplier' then (select name from public.suppliers where id::text = d.party_id) else (select coalesce(provider, code) from public.cost_sources where id::text = d.party_id) end) order by d.id)
    from public.bill_pay_defaults99 d), '[]'::jsonb);
end $$;

-- ============================================================
-- DECISION 2: inbox masking
-- ============================================================
create or replace function public._inb_pii_mode99() returns text language sql stable security definer set search_path = public as $$
  select case when coalesce(public.rule_txt('inbox_pii_mode'), 'off') in ('mask_phone', 'mask_phone_address', 'mask_all_pii') then public.rule_txt('inbox_pii_mode') else 'off' end $$;

-- the shown form of a value: phone / handle keeps its last 3 characters, a name keeps its first, address / text / attachment are fully hidden
create or replace function public._inb_mask99(p_field text, p_val text) returns text language sql immutable as $$
  select case
    when p_val is null then null
    when p_field in ('mobile') or (p_field = 'handle' and p_val ~ '^\+?[0-9][0-9 ()-]{5,}$') then repeat('•', greatest(char_length(p_val) - 3, 3)) || right(p_val, least(3, char_length(p_val)))
    when p_field in ('name', 'handle') then left(p_val, 1) || '•••'
    else '••••' end $$;

-- field = mobile | handle | address | name | text | attachment. Returns the value as it may be shown NOW (mode off or an active reveal = unchanged)
create or replace function public._inb_pii_f99(p_field text, p_val text) returns text
language plpgsql stable security definer set search_path = public as $$
declare mode_ text := public._inb_pii_mode99(); hide boolean;
begin
  if mode_ = 'off' or p_val is null then return p_val; end if;
  if coalesce(current_setting('bos.inb_unmask99', true), '') = txid_current()::text then return p_val; end if;      -- inside inbox_unmask only
  hide := case p_field
    when 'mobile' then true
    when 'handle' then mode_ = 'mask_all_pii' or p_val ~ '^\+?[0-9][0-9 ()-]{5,}$'
    when 'address' then mode_ in ('mask_phone_address', 'mask_all_pii')
    else mode_ = 'mask_all_pii' end;
  return case when hide then public._inb_mask99(p_field, p_val) else p_val end;
end $$;

-- the same for a whole order object
create or replace function public._inb_pii_json99(j jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mode_ text := public._inb_pii_mode99();
begin
  if mode_ = 'off' then return j; end if;
  if j ? 'customer_mobile' and jsonb_typeof(j->'customer_mobile') = 'string' then j := jsonb_set(j, '{customer_mobile}', to_jsonb(public._inb_pii_f99('mobile', j->>'customer_mobile'))); end if;
  if j ? 'address' and jsonb_typeof(j->'address') = 'string' then j := jsonb_set(j, '{address}', to_jsonb(public._inb_pii_f99('address', j->>'address'))); end if;
  if j ? 'customer_name' and jsonb_typeof(j->'customer_name') = 'string' then j := jsonb_set(j, '{customer_name}', to_jsonb(public._inb_pii_f99('name', j->>'customer_name'))); end if;
  return j || jsonb_build_object('pii_mode', mode_);
end $$;

-- reveal ONE message / order. Needs the contact right of the place AND grant inbox_unmask (owner always). Limited by inbox_unmask_daily_max (blank = none; owner not limited). Always logged.
create or replace function public.inbox_unmask(p_kind text, p_id text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; m public.inbound_messages; o public.online_orders; mode_ text := public._inb_pii_mode99(); lim numeric := public.rule_num('inbox_unmask_daily_max'); used int; data jsonb; fields text; sid text;
begin
  if p_kind not in ('message', 'order') or p_id is null then raise exception 'bad_input'; end if;
  if p_kind = 'message' then
    if p_id !~ '^[0-9]{1,18}$' then raise exception 'bad_input'; end if;
    select * into m from public.inbound_messages where id = p_id::bigint;
    if not found then raise exception 'not_found'; end if;
    loc := m.location_id; perform public._inb_gate(loc, 'view'); fields := 'handle,name,text,attachment';
  else
    if p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_input'; end if;
    select * into o from public.online_orders where id = p_id::uuid;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
    if not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(loc) then raise exception 'not allowed'; end if;
    fields := 'customer_mobile,address,customer_name';
  end if;
  if not public._inb_contact_ok(loc) then raise exception 'not allowed'; end if;
  if mode_ = 'off' then          -- nothing is masked: the normal read (which has its own view line)
    return jsonb_build_object('ok', true, 'mode', 'off', 'logged', false, 'data', case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end);
  end if;
  if not (public.is_owner() or public.has_grant('inbox_unmask', loc)) then raise exception 'not allowed'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if lim is not null and not public.is_owner() then
    select count(*) into used from public.inbox_unmask_log99 where user_id = auth.uid() and outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date;
    if used >= lim then
      insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'blocked');
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'used', used, 'max', lim);
    end if;
  end if;
  perform set_config('bos.inb_unmask99', txid_current()::text, true);
  begin
    data := case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end;
  exception when others then
    perform set_config('bos.inb_unmask99', '', true); raise;
  end;
  perform set_config('bos.inb_unmask99', '', true);
  insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'revealed');
  perform public._inb_audit_view('inbox_unmask', p_kind || ':' || p_id, jsonb_build_object('fields', fields, 'reason', left(nullif(btrim(p_reason), ''), 300)));
  return jsonb_build_object('ok', true, 'mode', mode_, 'logged', true, 'data', data, 'used', coalesce(used, 0) + 1, 'max', lim);
end $$;

-- owner: who revealed what, when
create or replace function public.inbox_unmask_log_list99(p_limit int default 100, p_user uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'user_id', z.user_id, 'staff', z.staff_id, 'kind', z.kind, 'ref', z.ref_id, 'location_id', z.location_id,
                   'fields', z.fields, 'reason', z.reason, 'outcome', z.outcome) order by z.id desc)
    from (select * from public.inbox_unmask_log99 l where p_user is null or l.user_id = p_user order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- owner cards: current values + counts of both options
create or replace function public.options99_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare w jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  w := public.bills_without_payment99(null, null, 500);
  return jsonb_build_object(
    'cost_bill_creates_payment', coalesce(public.rule_txt('cost_bill_creates_payment'), 'off'), 'purchase_bill_creates_payment', coalesce(public.rule_txt('purchase_bill_creates_payment'), 'off'),
    'bill_void_payment_mode', coalesce(public.rule_txt('bill_void_payment_mode'), 'void'), 'bill_pay_auto_credit_ok', public.rule_on('bill_pay_auto_credit_ok'),
    'bill_pay_large_amount', public.rule_num('bill_pay_large_amount'), 'bill_pay_small_cash_max', public.rule_num('bill_pay_small_cash_max'),
    'inbox_pii_mode', public._inb_pii_mode99(), 'inbox_pii_guard_on', public.rule_on('inbox_pii_guard_on'), 'inbox_unmask_daily_max', public.rule_num('inbox_unmask_daily_max'),
    'unpaid_cost', (select count(*) from jsonb_array_elements(w->'rows') e where e->>'kind' = 'cost'), 'unpaid_purchase', (select count(*) from jsonb_array_elements(w->'rows') e where e->>'kind' = 'purchase'),
    'reveals_today', (select count(*) from public.inbox_unmask_log99 where outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date),
    'blocked_today', (select count(*) from public.inbox_unmask_log99 where outcome = 'blocked' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date));
end $$;

-- ============================================================
-- re-created from their LATEST definitions (phase76/77/512/515 text); only the /* bos99 */ and -- bos99 lines differ
-- ============================================================

CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('text', left(m.msg_text, 200)) end, 'masked', not public._inb_contact_ok(m.location_id), 'pii_mode', public._inb_pii_mode99()) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.inbox_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.inbound_messages; c public.sales_channels; ok boolean;
begin
  select * into m from public.inbound_messages where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  ok := public._inb_contact_ok(m.location_id);
  if ok then perform public._inb_audit_view('inbound_messages', m.id::text, jsonb_build_object('fields', 'handle,name,text,attachment')); end if;
  return jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
    'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'masked', not ok,
    'handle', case when ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when ok then public._inb_pii_f99('name', m.customer_name) end, 'text', case when ok then public._inb_pii_f99('text', m.msg_text) end, 'attachment_ref', case when ok then public._inb_pii_f99('attachment', m.attachment_ref) end, 'pii_mode', public._inb_pii_mode99(),   /* bos99 */
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, public._inb_pii_f99('name', o.customer_name) as customer_name,   -- bos99
           case when public._inb_contact_ok(o.location_id) then public._inb_pii_f99('mobile', o.customer_mobile) end as customer_mobile,   -- bos76 bos99
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked, public._inb_pii_mode99() as pii_mode,   -- bos76 bos99
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;

CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := public._inb_pii_json99(j);                                                                               -- bos99
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.telegram_chat_info(p_msg_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'customer_id', l.customer_id, 'customer_name', case when ok then public._inb_pii_f99('name', cu.name) end, 'customer_mobile', case when ok then public._inb_pii_f99('mobile', cu.mobile) end, 'pii_mode', public._inb_pii_mode99(),   -- bos99
    'order_id', l.order_id, 'order_no', oo.order_no, 'note', l.note,
    'message_count', (select count(*) from public.inbound_messages x where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle),
    'orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_no', o2.order_no, 'status', o2.status) order by o2.created_at)
                          from public.online_orders o2 where o2.id in (select x.linked_order_id from public.inbound_messages x
                                                                        where x.channel_id = m.channel_id and x.customer_handle = m.customer_handle and x.linked_order_id is not null)), '[]'::jsonb));
end $function$;

-- ============================================================
-- recommendations (shown by setup_recommendations(); ON CONFLICT DO NOTHING; the owner decides, nothing is applied by itself)
-- ============================================================
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('cost_bill_creates_payment', 'cost_bill_creates_payment', '99', 'purchase', '"ask"', '{}',
  'cost bill সেভ করার পর "এখনই payment লিখবেন?" জিজ্ঞেস করা নিরাপদ: টাকা কখনো ভুল করে সরে না, আবার bill ও payment দুটো আলাদা করে type করার ঝামেলাও থাকে না। পুরোপুরি স্বয়ংক্রিয় (auto) করবেন কেবল cash-এ শোধ হওয়া ছোট bill-এর জন্য।',
  'Cost bill save করার পর "এখনই payment লিখবেন?" জিজ্ঞেস করা safe: টাকা কখনো ভুল করে সরে না, আবার bill ও payment দুটো আলাদা করে type করার ঝামেলাও থাকে না। পুরোপুরি auto করবেন কেবল cash এ শোধ হওয়া ছোট bill এর জন্য।',
  'Asking "Record payment now?" after a cost bill is saved is the safe middle: money never moves by mistake and you do not type the bill and the payment twice. Use a fully automatic mode only for small bills paid in cash.', 321),
 ('purchase_bill_creates_payment', 'purchase_bill_creates_payment', '99', 'purchase', '"ask"', '{}',
  'purchase bill পোস্ট করার পর জিজ্ঞেস করা নিরাপদ। credit-শর্তের supplier-এর bill কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধের সুযোগ থাকে।',
  'Purchase bill post করার পর জিজ্ঞেস করা safe। Credit-terms এর supplier এর bill কখনো নিজে নিজে শোধ হয় না, তাই আংশিক বা পরে শোধের সুযোগ থাকে।',
  'Asking after a purchase bill is posted is the safe choice. A supplier with credit terms is never paid automatically, so part payment or paying later stays possible.', 322),
 ('bill_void_payment_mode', 'bill_void_payment_mode', '99', 'purchase', '"void"', '{}',
  'bill বাতিল হলে তার payment-ও বাতিল হওয়াই সাধারণ নিয়ম: নইলে বই-এ খরচ থেকে যায় অথচ bill নেই। টাকা সত্যিই দেওয়া হয়ে গেলে keep_credit বেছে নিন।',
  'Bill বাতিল হলে তার payment ও বাতিল হওয়াই সাধারণ নিয়ম: নইলে বই-এ খরচ থেকে যায় অথচ bill নেই। টাকা সত্যিই দেওয়া হয়ে গেলে keep_credit বেছে নিন।',
  'Voiding the payment together with its bill is the normal rule: otherwise the books keep a cost for a bill that no longer exists. Choose keep_credit only when the money really left.', 323),
 ('bill_pay_auto_credit_ok', 'bill_pay_auto_credit_ok', '99', 'purchase', 'false', '{}',
  'বন্ধ থাকুক: credit-শর্তের পক্ষের bill নিজে নিজে শোধ হলে "পরে দেব" শর্তটাই অর্থহীন হয়ে যায়।',
  'Off থাকুক: credit-terms এর পক্ষের bill নিজে নিজে শোধ হলে "পরে দেব" শর্তটাই অর্থহীন হয়ে যায়।',
  'Keep it off: if a bill of a party with credit terms were paid automatically, the credit term itself would mean nothing.', 324),
 ('bill_pay_large_amount', 'bill_pay_large_amount', '99', 'purchase', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা থেকে bill "বড়" তা আপনি লিখবেন; লিখলে বড় bill-এ সিস্টেম সবসময় জিজ্ঞেস করার প্রস্তাব দেবে।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা থেকে bill "বড়" তা আপনি লিখবেন; লিখলে বড় bill এ system সবসময় জিজ্ঞেস করার প্রস্তাব দেবে।',
  'No number is suggested. You type from which amount a bill counts as large; the system then always recommends asking for large bills.', 325),
 ('bill_pay_small_cash_max', 'bill_pay_small_cash_max', '99', 'purchase', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা পর্যন্ত cash bill "ছোট" তা আপনি লিখবেন; লিখলে creditহীন ছোট cash bill-এ auto_cash প্রস্তাব আসবে।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। কত টাকা পর্যন্ত cash bill "ছোট" তা আপনি লিখবেন; লিখলে credit ছাড়া ছোট cash bill এ auto_cash প্রস্তাব আসবে।',
  'No number is suggested. You type up to which amount a cash bill counts as small; the system then recommends auto_cash for small cash bills without credit.', 326),
 ('inbox_pii_mode', 'inbox_pii_mode', '99', 'pos', '"mask_phone_address"', '{}',
  'phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে (message পড়া, order বানানো) পুরো নম্বর লাগে না, আর ফাঁস হলে ক্ষতি বেশি। নাম ও message-এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে অনুমতিপ্রাপ্ত মানুষ একটি একটি করে খুলবেন, আর প্রতিবার log-এ থাকবে।',
  'Phone ও address ঢেকে রাখা ভালো: বেশিরভাগ কাজে (message পড়া, order বানানো) পুরো নম্বর লাগে না, আর leak হলে ক্ষতি বেশি। নাম ও message এর লেখা খোলা থাকে যাতে কাজ আটকায় না। দরকারে authorised মানুষ একটি একটি করে খুলবেন, আর প্রতিবার log এ থাকবে।',
  'Hiding phone and address is the better default: most work (reading a message, making an order) does not need the full number, and a leak costs a lot. Name and message text stay visible so work is not blocked. Authorised people reveal one at a time, and every reveal is logged.', 327),
 ('inbox_unmask_daily_max', 'inbox_unmask_daily_max', '99', 'pos', null, '{}',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। দিনে একজন কতবার খুলতে পারবে তা আপনি লিখবেন; ফাঁকা = সীমা নেই। মালিকের ওপর সীমা খাটে না।',
  'কোনো সংখ্যা প্রস্তাব করা হয়নি। দিনে একজন কতবার unmask করতে পারবে তা আপনি লিখবেন; ফাঁকা = সীমা নেই। Owner এর ওপর সীমা খাটে না।',
  'No number is suggested. You type how many reveals one person may make per day; blank = no limit. The owner is not limited.', 328)
 on conflict (code) do nothing;

-- ============================================================
-- privileges: internals closed, public calls for signed-in users only
-- ============================================================
revoke all on function public._bp_today99(), public._bp_head99(text), public._bp_uuid99(text, text), public._bp_dup99(text, text, numeric),
  public._bp_pay99(text, text, text, numeric, text, uuid, text, boolean), public._bp_auto99(text, text, int, text, text, text, int, text),
  public._bp_cost_auto99(), public._bp_pur_auto99(), public._bp_cost_void99(), public._bp_sp_void99(), public._bp_pur_void99(), public._bp_ro99(),
  public._inb_pii_mode99(), public._inb_mask99(text, text), public._inb_pii_f99(text, text), public._inb_pii_json99(jsonb), public._inb_unmask_ro99() from public, anon, authenticated;
revoke all on function public.bill_pay_record(text, text, text, numeric, uuid, text, boolean), public.payment_recommendation(text, text), public.bill_pay_info99(text, text),
  public.bills_without_payment99(text, int, int), public.bill_pay_default_set99(text, text, text, boolean, text), public.bill_pay_defaults_list99(),
  public.inbox_unmask(text, text, text), public.inbox_unmask_log_list99(int, uuid), public.options99_state() from public, anon;
grant execute on function public.bill_pay_record(text, text, text, numeric, uuid, text, boolean), public.payment_recommendation(text, text), public.bill_pay_info99(text, text),
  public.bills_without_payment99(text, int, int), public.bill_pay_default_set99(text, text, text, boolean, text), public.bill_pay_defaults_list99(),
  public.inbox_unmask(text, text, text), public.inbox_unmask_log_list99(int, uuid), public.options99_state() to authenticated;
revoke all on function public.inbox_list(int, text, int), public.inbox_get(bigint), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.telegram_chat_info(bigint) from public, anon;
grant execute on function public.inbox_list(int, text, int), public.inbox_get(bigint), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.telegram_chat_info(bigint) to authenticated;

-- ---------------------------------------------------------------- phase100.sql
-- ============================================================
-- Phase 100 (bos100) - STEP Cat: ONE category / sub-category master for every item.
--   Needs phases 72..97 (docs/PASTE_ORDER.md) - guard below. Additive, paste-twice safe. NO existing function is re-created
--   (items.category / items.sub_category stay the text columns every old screen reads; nothing breaks), so there is nothing to re-base on phase524 / phase525.
--   Nothing is invented: names come from the existing items (category_bn), the existing editable lists (option_lists item_categories /
--   item_subcategories) or the stored code itself.
--
--   Table item_categories (tree: parent_id null = Category, parent_id set = Sub-category). `code` is the text value kept in items.category /
--   items.sub_category (stable on rename). items also get category_id / sub_category_id, kept in sync by a trigger (which also registers a new text value).
--   RPCs: category_list, category_save (add / sort / deactivate, client id = idempotent), category_rename (owner), category_merge (owner),
--         category_move (sub -> another category), category_reorder, item_set_category(+_bulk), category_sync100, category_rule_state, items_missing_category,
--         biz_items_by_category, stock_valuation_by_category (read-only wrappers: totals == the ungrouped report; cost columns only for cost-right holders).
--   Rule category_required_on_item = off (default) | warn | required (recommended: warn). 'required' refuses a NEW item without a category (and clearing it);
--   old items without a category stay editable. 'warn' is shown on the screens + the missing list.
--   Manage = owner or the item_create / item_bulk grant; rename + merge = owner only. Every change is in the audit log (log_change + a merge row).
-- Tag: bos100.
--   NOTE: item_sys stays set to the end of the transaction after merge / rename / move (transaction-local; PostgREST runs one RPC per transaction).
-- ============================================================

-- ---------- 0. guard ----------
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._recipe_gate73(uuid)') is null then miss := miss || ' 73'; end if;
  if to_regprocedure('public._pool_rate(integer,date,text)') is null then miss := miss || ' 74'; end if;
  if to_regprocedure('public._cs_alloc(bigint)') is null then miss := miss || ' 75'; end if;
  if to_regclass('public.intake_failures') is null then miss := miss || ' 76'; end if;
  if to_regprocedure('public._oo_short77(uuid)') is null then miss := miss || ' 77'; end if;
  if to_regprocedure('public._c78_main_loc(date)') is null then miss := miss || ' 78'; end if;
  if to_regprocedure('public._cost_free80(uuid)') is null then miss := miss || ' 80'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regprocedure('public.grn_bill_link(uuid,uuid,text)') is null then miss := miss || ' 82'; end if;
  if to_regprocedure('public._pf83_ro()') is null then miss := miss || ' 83'; end if;
  if to_regprocedure('public._aud84()') is null then miss := miss || ' 84'; end if;
  if to_regclass('public.acct_autopost_runs85') is null then miss := miss || ' 85'; end if;
  if to_regprocedure('public._tg_hash(text)') is null then miss := miss || ' 86'; end if;
  if to_regprocedure('public._prod_double_issue87()') is null then miss := miss || ' 87'; end if;
  if to_regprocedure('public._rcs88()') is null then miss := miss || ' 88'; end if;
  if to_regprocedure('public._sale_stock_out()') is null or position('bos89' in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) = 0 then miss := miss || ' 89'; end if;
  if to_regclass('public.scan_jobs') is null then miss := miss || ' 90'; end if;
  if to_regprocedure('public._ov_key(text,text)') is null then miss := miss || ' 91'; end if;
  if to_regclass('public.invoice_shares') is null then miss := miss || ' 92'; end if;
  if to_regclass('public.doc_template_choice') is null then miss := miss || ' 93'; end if;
  if to_regprocedure('public.anon_exec_audit94()') is null then miss := miss || ' 94'; end if;
  if not exists (select 1 from public.rules where key = 'cash_drawer_mode') then miss := miss || ' 95'; end if;
  if to_regclass('public.ledger_cost_supply96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if miss <> '' then raise exception 'phase100 needs phases 72..97 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the master table ----------
create table if not exists public.item_categories (
  id bigint generated always as identity primary key,
  parent_id bigint references public.item_categories(id),
  code text not null check (length(btrim(code)) between 1 and 80),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(btrim(name_en)) between 1 and 120),
  name_mix text,
  sort integer not null default 0,
  active boolean not null default true,
  merged_into bigint references public.item_categories(id),
  client_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now()
);
create unique index if not exists item_categories_code_uq100 on public.item_categories ((coalesce(parent_id, 0)), code);
create unique index if not exists item_categories_name_uq100 on public.item_categories ((coalesce(parent_id, 0)), lower(btrim(name_bn))) where active;
create unique index if not exists item_categories_client_uq100 on public.item_categories (client_id) where client_id is not null;
create index if not exists item_categories_parent_idx100 on public.item_categories (parent_id);

alter table public.item_categories enable row level security;
drop policy if exists item_categories_read100 on public.item_categories;
create policy item_categories_read100 on public.item_categories for select to authenticated using (public.is_active());
revoke all on table public.item_categories from public, anon, authenticated;
grant select on table public.item_categories to authenticated;

create or replace function public._item_categories_before100() returns trigger language plpgsql security definer set search_path = public as $f$
begin   -- bos100
  new.name_bn := btrim(new.name_bn); new.code := btrim(new.code);
  if new.name_en is not null then new.name_en := nullif(btrim(new.name_en), ''); end if;
  if tg_op = 'UPDATE' then new.updated_at := now(); new.updated_by := auth.uid(); else new.created_by := coalesce(new.created_by, auth.uid()); end if;
  if new.parent_id is not null and exists (select 1 from public.item_categories p where p.id = new.parent_id and p.parent_id is not null) then raise exception 'cat_depth'; end if;   -- two levels only
  if new.parent_id is not null and new.parent_id = new.id then raise exception 'cat_depth'; end if;
  return new;
end $f$;
drop trigger if exists item_categories_before100 on public.item_categories;
create trigger item_categories_before100 before insert or update on public.item_categories for each row execute function public._item_categories_before100();
drop trigger if exists item_categories_no_delete100 on public.item_categories;
create trigger item_categories_no_delete100 before delete on public.item_categories for each row execute function public.no_hard_delete();
drop trigger if exists audit_item_categories100 on public.item_categories;
create trigger audit_item_categories100 after insert or update on public.item_categories for each row execute function public.log_change('id');

alter table public.items add column if not exists category_id bigint;
alter table public.items add column if not exists sub_category_id bigint;
create index if not exists items_category_id_idx100 on public.items (category_id);

-- ---------- 2. rule + recommendation ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('category_required_on_item', 'items', 'choice', '"off"', null, '["off","warn","required"]'::jsonb, null, null,
  'প্রতিটি আইটেমে Category / Sub-category: বন্ধ / warn / লাগবেই', 'প্রতিটি Item-এ Category / Sub-category: off / warn / required', 'Category / Sub-category on every item: off, warn or required',
  'বন্ধ = আগের মতো। warn = Category ছাড়া আইটেমের তালিকা দেখায়, আটকায় না (প্রস্তাবিত)। required = নতুন আইটেম Category ছাড়া সেভ হয় না (Category-র Sub-category থাকলে সেটাও লাগবে); পুরনো আইটেম আগের মতো এডিট করা যায়।',
  'off = আগের মতো। warn = Category ছাড়া Item-এর list দেখায়, আটকায় না (recommended)। required = নতুন Item Category ছাড়া save হয় না (Category-র Sub-category থাকলে সেটাও লাগবে); পুরনো Item আগের মতো edit করা যায়।',
  'off = as before. warn = lists the items with no category and never blocks (recommended). required = a NEW item cannot be saved without a Category (and a Sub-category when the Category has any); old items stay editable.', 910)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('category_required_on_item', 'category_required_on_item', '100', 'items', '"warn"', '{}',
  'প্রতিটি আইটেমের Category ও Sub-category থাকলে বিক্রি, স্টক, খরচ ও রিপোর্ট ধরে ধরে দেখা যায়। প্রথমে warn রাখুন: Category ছাড়া আইটেমের তালিকা দেখে ঠিক করুন। সব ঠিক হলে required করা যায়। সিদ্ধান্ত মালিকের।',
  'প্রতিটি Item-এর Category ও Sub-category থাকলে sale, stock, cost ও report ধরে ধরে দেখা যায়। প্রথমে warn রাখুন: Category ছাড়া Item-এর list দেখে ঠিক করুন। সব ঠিক হলে required করা যায়। সিদ্ধান্ত owner-এর।',
  'With a Category and Sub-category on every item, sales, stock, cost and reports can be read by group. Start with warn, fix the items on the missing list, then switch to required when it is empty. The owner decides.', 300)
on conflict (code) do nothing;

-- ---------- 3. helpers ----------
create or replace function public._cat_mgr100() returns boolean language sql stable security definer set search_path = public as $f$
  select public.is_active() and (public.is_owner() or public.has_grant('item_create') or public.has_grant('item_bulk'));   -- bos100
$f$;

-- a stable text code for a new Category / Sub-category (never shown)
create sequence if not exists public.item_cat_seq100;
create or replace function public._cat_newcode100(p_sub boolean) returns text language plpgsql security definer set search_path = public as $f$
declare c text;
begin   -- bos100
  loop
    c := case when p_sub then 's' else 'k' end || lpad(nextval('public.item_cat_seq100')::text, 3, '0');
    exit when not exists (select 1 from public.item_categories where code = c)
          and not exists (select 1 from public.option_lists where list_code in ('item_categories', 'item_subcategories') and value_code = c)
          and not exists (select 1 from public.items where category = c or sub_category = c);
  end loop;
  return c;
end $f$;

-- keep the editable lists (option_lists) that the item editor reads in step with the master (best effort: a locked list is left alone)
create or replace function public._cat_ol_put100(p_sub boolean, p_code text, p_bn text, p_en text, p_active boolean, p_sort integer) returns void language plpgsql security definer set search_path = public as $f$
declare lc text := case when p_sub then 'item_subcategories' else 'item_categories' end;
begin   -- bos100
  insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, active) values (lc, p_code, p_bn, p_en, coalesce(p_sort, 0), coalesce(p_active, true))
  on conflict (list_code, value_code) do update set label_bn = excluded.label_bn, label_en = coalesce(excluded.label_en, public.option_lists.label_en), active = excluded.active, sort = excluded.sort;
exception when others then null;   -- list locked / rule: the master still works
end $f$;

-- the seed: master rows for every distinct existing value (idempotent; also what category_sync100 runs)
create or replace function public._cat_seed100() returns jsonb language plpgsql security definer set search_path = public as $f$
declare r record; nm text; n_top int := 0; n_sub int := 0; pid bigint; cnt int := 0;
begin   -- bos100
  for r in
    select v.code,
           coalesce((select nullif(btrim(o.label_bn), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code),
                    (select max(i.category_bn) from public.items i where i.category = v.code and nullif(btrim(i.category_bn), '') is not null),
                    (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), v.code) as bn,
           (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code) as en,
           coalesce((select o.sort from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), 0) as srt,
           coalesce((select o.active from public.option_lists o where o.list_code = 'item_categories' and o.value_code = v.code), true) as act
    from (select btrim(category) code from public.items where nullif(btrim(category), '') is not null
          union select value_code from public.option_lists where list_code = 'item_categories') v
    order by 4, 2, 1
  loop
    if exists (select 1 from public.item_categories where parent_id is null and code = r.code) then continue; end if;
    nm := r.bn;
    if exists (select 1 from public.item_categories where parent_id is null and active and lower(btrim(name_bn)) = lower(btrim(nm))) then nm := nm || ' (' || r.code || ')'; end if;
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active) values (null, r.code, nm, r.en, r.srt, r.act);
    n_top := n_top + 1;
  end loop;
  for r in
    select distinct btrim(i.category) cat, btrim(i.sub_category) sub from public.items i
    where nullif(btrim(i.category), '') is not null and nullif(btrim(i.sub_category), '') is not null order by 1, 2
  loop
    select id into pid from public.item_categories where parent_id is null and code = r.cat;
    if pid is null or exists (select 1 from public.item_categories where parent_id = pid and code = r.sub) then continue; end if;
    nm := coalesce((select nullif(btrim(o.label_bn), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub),
                   (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub), r.sub);
    if exists (select 1 from public.item_categories where parent_id = pid and active and lower(btrim(name_bn)) = lower(btrim(nm))) then nm := nm || ' (' || r.sub || ')'; end if;
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active)
      values (pid, r.sub, nm, (select nullif(btrim(o.label_en), '') from public.option_lists o where o.list_code = 'item_subcategories' and o.value_code = r.sub), 0, true);
    n_sub := n_sub + 1;
  end loop;
  -- link the items (no audit noise, locked items included: only the id columns change; the items trigger is not fired by these columns)
  perform set_config('bos.item_sys', '1', true); perform set_config('bos.item_import', '1', true);
  update public.items i set category_id = c.id
    from public.item_categories c where c.parent_id is null and c.code = btrim(i.category) and i.category_id is distinct from c.id;
  get diagnostics cnt = row_count;
  update public.items i set sub_category_id = s.id
    from public.item_categories c join public.item_categories s on s.parent_id = c.id
    where c.parent_id is null and c.code = btrim(i.category) and s.code = btrim(i.sub_category) and i.sub_category_id is distinct from s.id;
  update public.items i set category_id = null where nullif(btrim(i.category), '') is null and i.category_id is not null;
  update public.items i set sub_category_id = null where nullif(btrim(i.sub_category), '') is null and i.sub_category_id is not null;
  perform set_config('bos.item_sys', '', true); perform set_config('bos.item_import', '', true);
  return jsonb_build_object('categories_added', n_top, 'sub_categories_added', n_sub, 'items_linked', cnt);
end $f$;

-- ---------- 4. trigger on items: keep ids in step with the text columns, register new values, enforce the rule ----------
create or replace function public._items_cat100() returns trigger language plpgsql security definer set search_path = public as $f$
declare cid bigint; sid bigint; cat text := nullif(btrim(new.category), ''); sub text := nullif(btrim(new.sub_category), ''); sysq boolean;
begin   -- bos100
  sysq := coalesce(current_setting('bos.item_sys', true), '') = '1' or coalesce(current_setting('bos.item_import', true), '') = '1';
  if cat is not null then
    select id into cid from public.item_categories where parent_id is null and code = cat;
    if cid is null and not sysq then
      begin   -- registering is an add-on: it can never block an item save
        insert into public.item_categories (parent_id, code, name_bn) values (null, cat, coalesce(nullif(btrim(new.category_bn), ''), cat))
          on conflict do nothing returning id into cid;
        if cid is null then select id into cid from public.item_categories where parent_id is null and code = cat; end if;
        if cid is null then   -- the name is taken by another code: register under the code
          insert into public.item_categories (parent_id, code, name_bn) values (null, cat, cat || ' (' || cat || ')') on conflict do nothing returning id into cid;
        end if;
      exception when others then cid := null;
      end;
    end if;
  end if;
  new.category_id := cid;
  sid := null;
  if sub is not null and cid is not null then
    select id into sid from public.item_categories where parent_id = cid and code = sub;
    if sid is null and not sysq then
      begin
        insert into public.item_categories (parent_id, code, name_bn) values (cid, sub, sub) on conflict do nothing returning id into sid;
        if sid is null then select id into sid from public.item_categories where parent_id = cid and code = sub; end if;
        if sid is null then insert into public.item_categories (parent_id, code, name_bn) values (cid, sub, sub || ' (' || sub || ')') on conflict do nothing returning id into sid; end if;
      exception when others then sid := null;
      end;
    end if;
  end if;
  new.sub_category_id := sid;
  return new;
end $f$;
drop trigger if exists items_cat100 on public.items;
create trigger items_cat100 before insert or update of category, sub_category on public.items for each row execute function public._items_cat100();

-- the rule 'required' is checked at the END of the statement's transaction (a deferred constraint trigger on the FINAL row): the item editor inserts the item first
-- and sets the Sub-category in a second statement, so a per-statement check would refuse a complete item
create or replace function public._items_cat_req100() returns trigger language plpgsql security definer set search_path = public as $f$
declare mode text; cur record; sysq boolean;
begin   -- bos100
  sysq := coalesce(current_setting('bos.item_sys', true), '') = '1' or coalesce(current_setting('bos.item_import', true), '') = '1';
  if sysq then return null; end if;
  mode := coalesce(public.rule_txt('category_required_on_item'), 'off');
  if mode <> 'required' then return null; end if;
  select i.category, i.sub_category, i.category_id into cur from public.items i where i.id = new.id;
  if not found then return null; end if;
  if nullif(btrim(cur.category), '') is null then
    if tg_op = 'INSERT' or nullif(btrim(old.category), '') is not null then raise exception 'category_required' using hint = 'category_required_on_item'; end if;
    return null;
  end if;
  if nullif(btrim(cur.sub_category), '') is null and exists (select 1 from public.item_categories s where s.parent_id = cur.category_id and s.active)
     and (tg_op = 'INSERT' or cur.category is distinct from old.category or old.sub_category is distinct from cur.sub_category) then
    raise exception 'sub_category_required' using hint = 'category_required_on_item';
  end if;
  return null;
end $f$;
drop trigger if exists items_cat_req100 on public.items;
create constraint trigger items_cat_req100 after insert or update of category, sub_category on public.items deferrable initially deferred for each row execute function public._items_cat_req100();

-- a Category added to the editable list later is registered too (a Sub-category needs its parent, which the first item that uses it gives)
create or replace function public._ol_cat100() returns trigger language plpgsql security definer set search_path = public as $f$
declare nm text := coalesce(nullif(btrim(new.label_bn), ''), nullif(btrim(new.label_en), ''), new.value_code);
begin   -- bos100
  if new.list_code = 'item_categories' and not exists (select 1 from public.item_categories where parent_id is null and code = new.value_code) then
    begin   -- the master is an add-on: whatever goes wrong here must never block the editable list
      insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active)
        values (null, new.value_code, case when exists (select 1 from public.item_categories x where x.parent_id is null and x.active and lower(btrim(x.name_bn)) = lower(btrim(nm))) then nm || ' (' || new.value_code || ')' else nm end,
                nullif(btrim(new.label_en), ''), coalesce(new.sort, 0), new.active);
    exception when others then null;
    end;
  end if;
  return new;
end $f$;
drop trigger if exists option_lists_cat100 on public.option_lists;
create trigger option_lists_cat100 after insert on public.option_lists for each row execute function public._ol_cat100();

select public._cat_seed100();

-- ---------- 5. RPCs ----------
create or replace function public.category_list(p_include_inactive boolean default false)
returns table (id bigint, parent_id bigint, code text, name_bn text, name_en text, name_mix text, sort integer, active boolean, item_count bigint)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select c.id, c.parent_id, c.code, c.name_bn, c.name_en, c.name_mix, c.sort, c.active,
           (select count(*) from public.items i where case when c.parent_id is null then i.category_id = c.id else i.sub_category_id = c.id end)::bigint
    from public.item_categories c
    where (p_include_inactive or (c.active and (c.parent_id is null or exists (select 1 from public.item_categories p where p.id = c.parent_id and p.active))))
    order by coalesce(c.parent_id, c.id), (c.parent_id is not null), c.sort, c.name_bn, c.id;
end $f$;

create or replace function public.category_save(p_id bigint default null, p_parent bigint default null, p_name_bn text default null, p_name_en text default null,
                                                p_sort integer default null, p_active boolean default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; bn text; en text; code_ text; nid bigint;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into r from public.item_categories where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'code', r.code, 'duplicate', true); end if;
  end if;
  if p_id is null then
    bn := nullif(btrim(p_name_bn), ''); en := nullif(btrim(p_name_en), '');
    bn := coalesce(bn, en);
    if bn is null then raise exception 'name_required'; end if;
    if p_parent is not null and not exists (select 1 from public.item_categories where id = p_parent and parent_id is null and active) then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.item_categories where coalesce(parent_id, 0) = coalesce(p_parent, 0) and active and lower(btrim(name_bn)) = lower(bn)) then raise exception 'name_taken'; end if;
    code_ := public._cat_newcode100(p_parent is not null);
    insert into public.item_categories (parent_id, code, name_bn, name_en, sort, active, client_id)
      values (p_parent, code_, bn, en, coalesce(p_sort, (select coalesce(max(x.sort), 0) + 10 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(p_parent, 0))), true, p_client) returning id into nid;
    perform public._cat_ol_put100(p_parent is not null, code_, bn, en, true, coalesce(p_sort, 0));
    return jsonb_build_object('id', nid, 'code', code_);
  end if;
  select * into r from public.item_categories where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if p_name_bn is not null or p_name_en is not null then raise exception 'use_rename'; end if;   -- names change only through category_rename (owner)
  if p_active is true and not r.active and r.merged_into is not null then raise exception 'merged'; end if;
  if p_active is true and not r.active and exists (select 1 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(r.parent_id, 0) and x.active and x.id <> r.id and lower(btrim(x.name_bn)) = lower(btrim(r.name_bn))) then raise exception 'name_taken'; end if;
  update public.item_categories set sort = coalesce(p_sort, sort), active = coalesce(p_active, active) where id = p_id;
  perform public._cat_ol_put100(r.parent_id is not null, r.code, r.name_bn, r.name_en, coalesce(p_active, r.active), coalesce(p_sort, r.sort));
  return jsonb_build_object('id', p_id, 'code', r.code);
end $f$;

create or replace function public.category_reorder(p_ids bigint[]) returns integer language plpgsql security definer set search_path = public as $f$
declare i int := 0; x bigint; c public.item_categories;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  foreach x in array coalesce(p_ids, '{}') loop
    i := i + 10;
    update public.item_categories set sort = i where id = x;
    select * into c from public.item_categories where id = x;
    if found then perform public._cat_ol_put100(c.parent_id is not null, c.code, c.name_bn, c.name_en, c.active, i); end if;
  end loop;
  return i / 10;
end $f$;

create or replace function public.category_rename(p_id bigint, p_name_bn text, p_name_en text default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; bn text := nullif(btrim(p_name_bn), ''); en text := nullif(btrim(p_name_en), ''); n int := 0;
begin   -- bos100
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if bn is null then raise exception 'name_required'; end if;
  select * into r from public.item_categories where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.item_categories x where coalesce(x.parent_id, 0) = coalesce(r.parent_id, 0) and x.active and x.id <> r.id and lower(btrim(x.name_bn)) = lower(bn)) then raise exception 'name_taken'; end if;
  update public.item_categories set name_bn = bn, name_en = en where id = p_id;
  if r.parent_id is null then   -- items keep the code; their Bangla display name follows the master
    perform set_config('bos.item_sys', '1', true);   -- stays on to the end of the transaction (the deferred 'required' check reads it)
    update public.items set category_bn = bn where category_id = p_id and category_bn is distinct from bn;
    get diagnostics n = row_count;
  end if;
  perform public._cat_ol_put100(r.parent_id is not null, r.code, bn, en, r.active, r.sort);
  return jsonb_build_object('id', p_id, 'items_updated', n);
end $f$;

create or replace function public.category_merge(p_from bigint, p_into bigint, p_client uuid default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare f public.item_categories; t public.item_categories; s record; tg bigint; n_items int := 0; n_subs int := 0; sid text;
begin   -- bos100
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_into is null or p_from = p_into then raise exception 'bad_request'; end if;
  select * into f from public.item_categories where id = p_from for update;
  select * into t from public.item_categories where id = p_into for update;
  if f.id is null or t.id is null then raise exception 'not_found'; end if;
  if f.merged_into = t.id then return jsonb_build_object('items_moved', 0, 'subs_moved', 0, 'duplicate', true); end if;
  if (f.parent_id is null) <> (t.parent_id is null) then raise exception 'same_level_only'; end if;
  if not t.active then raise exception 'target_inactive'; end if;
  perform set_config('bos.item_sys', '1', true);
  if f.parent_id is null then
    -- sub-categories of the source: moved under the target, or folded into a same-code / same-name one of the target
    for s in select * from public.item_categories where parent_id = f.id order by id loop
      select x.id into tg from public.item_categories x where x.parent_id = t.id and (x.code = s.code or (x.active and lower(btrim(x.name_bn)) = lower(btrim(s.name_bn)))) order by (x.code = s.code) desc limit 1;
      if tg is null then
        update public.item_categories set parent_id = t.id where id = s.id;
        n_subs := n_subs + 1;
      else
        update public.items set sub_category = (select x.code from public.item_categories x where x.id = tg) where category_id = f.id and sub_category_id = s.id;
        update public.item_categories set active = false, merged_into = tg where id = s.id;
      end if;
    end loop;
    update public.items set category = t.code, category_bn = t.name_bn where category_id = f.id;
    get diagnostics n_items = row_count;
  else
    update public.items set category = (select x.code from public.item_categories x where x.id = t.parent_id), category_bn = (select x.name_bn from public.item_categories x where x.id = t.parent_id),
           sub_category = t.code where sub_category_id = f.id;
    get diagnostics n_items = row_count;
  end if;
  update public.item_categories set active = false, merged_into = t.id where id = f.id;
  perform public._cat_ol_put100(f.parent_id is not null, f.code, f.name_bn, f.name_en, false, f.sort);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'category_merge', 'item_categories', p_from::text, jsonb_build_object('into', p_into, 'items_moved', n_items, 'subs_moved', n_subs, 'client_id', p_client));
  return jsonb_build_object('items_moved', n_items, 'subs_moved', n_subs);
end $f$;

create or replace function public.category_move(p_id bigint, p_new_parent bigint) returns jsonb language plpgsql security definer set search_path = public as $f$
declare r public.item_categories; np public.item_categories; n int := 0;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  select * into r from public.item_categories where id = p_id for update;
  select * into np from public.item_categories where id = p_new_parent;
  if r.id is null or np.id is null then raise exception 'not_found'; end if;
  if r.parent_id is null or np.parent_id is not null or not np.active then raise exception 'bad_parent'; end if;
  if r.parent_id = np.id then return jsonb_build_object('items_moved', 0); end if;
  if exists (select 1 from public.item_categories x where x.parent_id = np.id and (x.code = r.code or (x.active and lower(btrim(x.name_bn)) = lower(btrim(r.name_bn))))) then raise exception 'sub_exists'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_categories set parent_id = np.id where id = r.id;
  update public.items set category = np.code, category_bn = np.name_bn where sub_category_id = r.id;
  get diagnostics n = row_count;
  return jsonb_build_object('items_moved', n);
end $f$;

create or replace function public.item_set_category(p_item uuid, p_cat bigint, p_sub bigint default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare c public.item_categories; s public.item_categories;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'not_found'; end if;
  if p_cat is null then
    if p_sub is not null then raise exception 'bad_parent'; end if;
    update public.items set category = null, category_bn = null, sub_category = null where id = p_item;   -- the items trigger refuses it when the rule is 'required'
    return jsonb_build_object('item_id', p_item, 'category', null, 'sub_category', null);
  end if;
  select * into c from public.item_categories where id = p_cat;
  if c.id is null or c.parent_id is not null or not c.active then raise exception 'bad_category'; end if;
  if p_sub is not null then
    select * into s from public.item_categories where id = p_sub;
    if s.id is null or s.parent_id is distinct from c.id or not s.active then raise exception 'bad_sub_category'; end if;
  end if;
  update public.items set category = c.code, category_bn = c.name_bn, sub_category = s.code where id = p_item;
  return jsonb_build_object('item_id', p_item, 'category', c.code, 'sub_category', s.code);
end $f$;

create or replace function public.item_set_category_bulk(p_items uuid[], p_cat bigint, p_sub bigint default null, p_client uuid default null) returns jsonb language plpgsql security definer set search_path = public as $f$
declare x uuid; n int := 0;
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  if coalesce(array_length(p_items, 1), 0) > 500 then raise exception 'too_many'; end if;
  foreach x in array coalesce(p_items, '{}') loop perform public.item_set_category(x, p_cat, p_sub); n := n + 1; end loop;
  return jsonb_build_object('items', n);
end $f$;

create or replace function public.category_sync100() returns jsonb language plpgsql security definer set search_path = public as $f$
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  return public._cat_seed100();
end $f$;

create or replace function public.category_rule_state() returns jsonb language plpgsql stable security definer set search_path = public as $f$
begin   -- bos100
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', coalesce(public.rule_txt('category_required_on_item'), 'off'), 'recommended', 'warn',
    'missing', (select count(*) from public.items i where i.is_active and i.count_in_business and nullif(btrim(i.category), '') is null),
    'missing_sub', (select count(*) from public.items i where i.is_active and i.count_in_business and nullif(btrim(i.category), '') is not null and nullif(btrim(i.sub_category), '') is null
                       and exists (select 1 from public.item_categories s where s.parent_id = i.category_id and s.active)));
end $f$;

create or replace function public.items_missing_category(p_limit integer default 200)
returns table (item_id uuid, code text, name_bn text, name_en text, item_type text, category text, sub_category text, reason text)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if not public._cat_mgr100() then raise exception 'not allowed'; end if;
  return query
    select i.id, i.code, i.name_bn, i.name_en, i.item_type, i.category, i.sub_category,
           case when nullif(btrim(i.category), '') is null then 'no_category' else 'no_sub_category' end
    from public.items i
    where i.is_active and i.count_in_business and (nullif(btrim(i.category), '') is null
          or (nullif(btrim(i.sub_category), '') is null and exists (select 1 from public.item_categories s where s.parent_id = i.category_id and s.active)))
    order by i.code limit least(greatest(coalesce(p_limit, 200), 1), 2000);
end $f$;

-- ---------- 6. reports by Category / Sub-category (read-only wrappers: same permission checks and cost secrecy as the ungrouped report) ----------
create or replace function public.biz_items_by_category(p_from date, p_to date, p_loc integer default null, p_level text default 'category')
returns table (category text, sub_category text, cat_name_bn text, cat_name_en text, sub_name_bn text, sub_name_en text, items bigint, revenue numeric, cogs numeric, cogs_unknown_items bigint, share_pct numeric)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if p_level not in ('category', 'sub') then raise exception 'bad_level'; end if;
  return query
  with b as (select * from public.biz_items(p_from, p_to, p_loc)),   -- biz_items refuses a caller without report rights and hides cost without the cost right
  j as (
    select nullif(btrim(i.category), '') cat, case when p_level = 'sub' then nullif(btrim(i.sub_category), '') end sb, b.revenue rev, b.cogs cg
    from b join public.items i on i.id = b.item_id),
  g as (select j.cat, j.sb, count(*) n, sum(j.rev) rev, sum(j.cg) cg, count(*) filter (where j.cg is null and j.rev > 0) unk from j group by 1, 2),
  tot as (select coalesce(sum(g.rev), 0) t from g)
  select g.cat, g.sb, c.name_bn, c.name_en, s.name_bn, s.name_en, g.n, g.rev, g.cg, g.unk,
         case when (select t from tot) > 0 then round(100 * g.rev / (select t from tot), 2) else 0 end
  from g left join public.item_categories c on c.parent_id is null and c.code = g.cat
         left join public.item_categories s on s.parent_id = c.id and s.code = g.sb
  order by g.rev desc nulls last, g.cat nulls last, g.sb nulls last;
end $f$;

create or replace function public.stock_valuation_by_category(p_loc integer default null, p_level text default 'category')
returns table (category text, sub_category text, cat_name_bn text, cat_name_en text, sub_name_bn text, sub_name_en text, items bigint, value numeric)
language plpgsql stable security definer set search_path = public as $f$
#variable_conflict use_column
begin   -- bos100
  if p_level not in ('category', 'sub') then raise exception 'bad_level'; end if;
  return query
  with v as (select * from public.stock_valuation(p_loc)),   -- stock_valuation checks the cost right per place
  j as (select nullif(btrim(i.category), '') cat, case when p_level = 'sub' then nullif(btrim(i.sub_category), '') end sb, v.item_id iid, v.value val from v join public.items i on i.id = v.item_id),
  g as (select j.cat, j.sb, count(distinct j.iid) n, sum(j.val) val from j group by 1, 2)
  select g.cat, g.sb, c.name_bn, c.name_en, s.name_bn, s.name_en, g.n, g.val
  from g left join public.item_categories c on c.parent_id is null and c.code = g.cat
         left join public.item_categories s on s.parent_id = c.id and s.code = g.sb
  order by g.val desc nulls last, g.cat nulls last, g.sb nulls last;
end $f$;

-- ---------- 7. privileges: the browser calls only the public RPCs ----------
do $p$
declare r record;
begin
  for r in select p.oid::regprocedure f, p.proname n from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('category_list', 'category_save', 'category_reorder', 'category_rename', 'category_merge', 'category_move', 'item_set_category', 'item_set_category_bulk',
                             'category_sync100', 'category_rule_state', 'items_missing_category', 'biz_items_by_category', 'stock_valuation_by_category',
                             '_cat_mgr100', '_cat_newcode100', '_cat_ol_put100', '_cat_seed100', '_items_cat100', '_items_cat_req100', '_ol_cat100', '_item_categories_before100')
  loop
    execute format('revoke all on function %s from public, anon', r.f);
    if left(r.n, 1) = '_' then execute format('revoke all on function %s from authenticated', r.f); else execute format('grant execute on function %s to authenticated', r.f); end if;
  end loop;
  revoke all on sequence public.item_cat_seq100 from public, anon, authenticated;
end $p$;

-- ---------------------------------------------------------------- phase101.sql
-- ============================================================
-- Phase 101 (bos101) - Step Rec: the setup advisor covers EVERY rule / switch added in phases 508..98. Run AFTER phase524 (canonical order, docs/PASTE_ORDER.md).
-- Additive + idempotent (paste twice = no change). Strictly ADVISORY: only rows are added to public.setup_rec_defs81 (INSERT ... ON CONFLICT DO NOTHING).
--   * Nothing here blocks, changes or re-routes any sale, purchase, production, journal or order. No rule default, rate, limit or amount is changed.
--   * No function is created or re-created: setup_recommendations() / setup_recommend_apply() already read jsonb rec_value rows (text / choice / switch) and
--     set them through set_rule (validated by the rule kind, audited). Rows of phase507 and phase520 are not touched.
--   * A row whose rule is not installed shows not_installed, as before. A rule that already has a row (phase507 / phase520) gets no second row.
--   * Owner-typed numbers, dates, currencies and anything that depends on hardware, the shop layout or an outside setup get NO recommended value
--     (status info, the screen shows the allowed range). Where a value is recommended the reason (bn / mix / en) says why; backlog-posting
--     accounting switches carry the warnings of the Dscr screen and are apply-ready only when the accounting basics are clean.
--   * The rules of phase525 (Opt) and phase100 (Cat) get their rows in their own phases.
-- ============================================================

do $g$ begin perform set_config('phase101.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regprocedure('public._acct_docs(date)') is null or coalesce(position('bos98' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))), 0) = 0 then miss := miss || ' 98'; end if;
  if to_regclass('public.setup_rec_defs81') is null or to_regprocedure('public.setup_recommendations()') is null then miss := miss || ' 81'; end if;
  if miss <> '' then
    raise exception 'phase101 needs phases 72..98 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase101.ok', 'on', false);
end $g$;

-- ---------- recommendations (one row per rule; code = rule key; sort 300+ so phase507 / phase520 rows keep their place) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('purchase_grn_guard', '82', 'stock', null::jsonb, '{}'::text[],
  'GRN যদি মালের উৎস হয় আর bill-ও stock বাড়ায়, একই মাল দুবার গোনা হয়। তখন "skip" দিন: bill শুধু টাকা ও বাকি ধরবে, stock আসবে GRN থেকে। GRN উৎস না হলে "off" থাকুক। উৎস কোনটা তা আপনার অবস্থার উপর নির্ভর করে, তাই এখানে একটি মান ঠিক করে দেওয়া হয়নি।',
  'GRN যদি goods-এর source হয় আর bill-ও stock বাড়ায়, একই মাল দুবার গোনা হয়। তখন skip দিন: bill শুধু টাকা ও due ধরবে, stock আসবে GRN থেকে। GRN source না হলে off থাকুক। Source কোনটা তা আপনার অবস্থার উপর নির্ভর করে, তাই এখানে একটি value ঠিক করে দেওয়া হয়নি।',
  'When GRN is the source of goods and the purchase bill also adds stock, the same goods are counted twice. In that case choose skip: the bill records money and dues only and stock comes from the GRN. If GRN is not the source, keep off. It depends on how you receive goods, so no single value is recommended here.', 300),
 ('purchase_void_guard', '82', 'stock', '"refuse"'::jsonb, '{}'::text[],
  'ফেরত দেওয়া, ব্যবহার হয়ে যাওয়া বা GRN batch আছে এমন মালের bill বাতিল করলে stock মাইনাস ও হিসাব ভুল হয়। refuse দিলে এমন বাতিল আটকে যায়, আগে ফেরত বা ব্যবহার ঠিক করতে হয়।',
  'Return হয়ে যাওয়া, use হয়ে যাওয়া বা GRN batch আছে এমন মালের bill void করলে stock minus ও হিসাব ভুল হয়। refuse দিলে এমন void আটকে যায়, আগে return বা use ঠিক করতে হয়।',
  'Voiding a bill whose goods were already returned, used or received by a GRN batch makes stock negative and the books wrong. Refuse stops such a void until the return or use is sorted out.', 301),
 ('purchase_void_payments', '82', 'stock', '"keep"'::jsonb, '{}'::text[],
  'টাকা সত্যিই বেরিয়ে গেছে। bill বাতিল হলেও payment রেখে দিলে সেটা সরবরাহকারীর জমা (credit) হয়ে থাকে, day book-এ টাকা ফিরে আসার ভুল দেখায় না। টাকা সত্যিই ফেরত এলে supplier refund লিখুন।',
  'টাকা সত্যিই বেরিয়ে গেছে। Bill void হলেও payment রেখে দিলে সেটা supplier credit হয়ে থাকে, day book-এ cash ফিরে আসার ভুল দেখায় না। টাকা সত্যিই ফেরত এলে supplier refund লিখুন।',
  'The money really left. If the payment is kept when the bill is voided it stays as supplier credit and the day book does not show cash that never came back. Record a supplier refund when the money does come back.', 302),
 ('unit_conv_required', '82', 'stock', '"refuse"'::jsonb, '{stk_conv}'::text[],
  'ইউনিটের রূপান্তর (conversion) নেই এমন tracked পণ্য বিক্রি হলে stock কমে না। refuse দিলে এমন বিক্রি আটকে যায়। সব পণ্যের conversion বসানোর পরই চালু করুন (তার আগে warn থাকুক); না হলে বিক্রি আটকে যেতে পারে।',
  'Unit conversion নেই এমন tracked item বিক্রি হলে stock কমে না। refuse দিলে এমন sale আটকে যায়। সব item-এর conversion বসানোর পরই চালু করুন (তার আগে warn থাকুক); না হলে sale আটকে যেতে পারে।',
  'Selling a tracked item that has no unit conversion does not reduce its stock. Refuse stops such a sale. Switch it on only after every item has its conversion (keep warn until then), otherwise sales may be stopped.', 303),
 ('neg_grant_log', '82', 'stock', 'true'::jsonb, '{}'::text[],
  'যার অনুমতি আছে সে stock-এর নিচে বিক্রি করলে কে, কোন পণ্য, কত - হলুদ সতর্কতায় লেখা থাকে, যাতে মালিক জানতে পারেন। কোনো বিক্রি আটকায় না।',
  'যার permission আছে সে stock-এর নিচে sell করলে কে, কোন item, কত - yellow warning-এ লেখা থাকে, যাতে owner জানতে পারেন। কোনো sale আটকায় না।',
  'When someone with the permission sells below zero, who, which item and how much is written as a yellow warning so the owner knows. No sale is stopped.', 304),
 ('production_negative_reason', '82', 'stock', '"required"'::jsonb, '{}'::text[],
  'কাঁচামাল না থাকা অবস্থায় উৎপাদন করলে খরচ ভুল হয়। required দিলে production note-এ কারণ না লিখলে উৎপাদন হয় না, তাই চুপচাপ মাইনাস হয় না।',
  'Ingredient না থাকা অবস্থায় production করলে cost ভুল হয়। required দিলে production note-এ reason না লিখলে production হয় না, তাই চুপচাপ minus হয় না।',
  'Producing without enough ingredient stock gives wrong costs. Required means production is refused unless the production note gives a reason, so stock never goes negative silently.', 305),
 ('stock_negative_mode', '82', 'stock', null::jsonb, '{}'::text[],
  'প্রথম stock গোনা (count) বা শুরুর stock (opening) তোলার পরে "block" বেছে নিন: তখন stock-এর চেয়ে বেশি বিক্রি আটকায়। তার আগে block দিলে ভুল stock-এ বৈধ বিক্রিও আটকে যেতে পারে, তাই এখানে মান ঠিক করে দেওয়া হয়নি।',
  'প্রথম stock count বা opening stock তোলার পরে block বেছে নিন: তখন stock-এর বেশি sale আটকায়। তার আগে block দিলে ভুল stock-এ বৈধ sale-ও আটকে যেতে পারে, তাই এখানে value ঠিক করে দেওয়া হয়নি।',
  'Choose block after the first stock count or opening stock is entered: then a sale above stock is stopped. Before that, block may stop genuine sales because the stock figures are wrong, so no value is recommended here.', 306),
 ('form_051_mode', '83', 'stock', null::jsonb, '{}'::text[],
  'যদি 05-1 শিটই উৎপাদনের আসল record হয় (recipe production screen নয়), তাহলে "post" দিন: শিট stock-এ গেলে কাঁচামালও গড় খরচে বের হবে ও তৈরি মালের খরচ বসবে। নইলে "reference" থাকুক (আগের মতো)। কোনটা আপনার কারখানার নিয়ম তা আমরা জানি না, তাই মান ঠিক করা হয়নি। refuse = 05-1 কখনো stock-এ যাবে না।',
  'যদি 05-1 sheet-ই production-এর আসল record হয় (recipe production screen নয়), তাহলে post দিন: sheet stock-এ গেলে ingredient-ও গড় cost-এ বের হবে ও finished goods-এর cost বসবে। নইলে reference থাকুক (আগের মতো)। কোনটা আপনার factory-র নিয়ম তা আমরা জানি না, তাই value ঠিক করা হয়নি। refuse = 05-1 কখনো stock-এ যাবে না।',
  'If the 05-1 sheet is the real production record (not the recipe production screen), choose post: when the sheet posts to stock the ingredients also go out at average cost and the finished goods get a cost. Otherwise keep reference (as before). It depends on how your factory records production, so no value is recommended. Refuse means 05-1 never posts to stock.', 307),
 ('transit_short_mode', '83', 'stock', '"loss"'::jsonb, '{}'::text[],
  'কম পৌঁছানো মাল এখন কোনো খাতায় নেই, শুধু একটি তালিকায় থাকে। loss দিলে ঘাটতি stock ledger-এ খরচসহ লেখা থাকে, পরে হিসাবে নেওয়া যায় (acct_transit_loss দেখুন)।',
  'কম পৌঁছানো মাল এখন কোনো খাতায় নেই, শুধু একটি list-এ থাকে। loss দিলে ঘাটতি stock ledger-এ cost-সহ লেখা থাকে, পরে accounts-এ নেওয়া যায় (acct_transit_loss দেখুন)।',
  'Goods that arrive short are in no book today, only on a list. With loss, the shortfall is written in the stock ledger with its cost and can be taken into the accounts later (see acct_transit_loss).', 308),
 ('transit_open_hours', '83', 'stock', null::jsonb, '{}'::text[],
  'কোনো সংখ্যা কোডে দেওয়া নেই। আপনার ডেলিভারি সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি সংখ্যা মালিক নিজে লিখুন; এর বেশি সময় পাঠানো-কিন্তু-না-পৌঁছানো ট্রান্সফারে জরুরি সতর্কতা আসবে। ফাঁকা = সতর্কতা নেই।',
  'কোনো সংখ্যা code-এ দেওয়া নেই। আপনার delivery সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি সংখ্যা owner নিজে লিখুন; এর বেশি সময় sent-কিন্তু-received-না transfer-এ urgent alert আসবে। ফাঁকা = alert নেই।',
  'No number is built in. The owner types a little more than the hours a delivery normally takes; a transfer that stays sent but not received for longer raises an urgent alert. Blank = no alert.', 309),
 ('offline_soft_stock', '83', 'pos', 'true'::jsonb, '{}'::text[],
  'offline-এ বিক্রির সময় মাল ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে বিক্রি হারিয়ে যায়। চালু থাকলে বিক্রি record হয় ও হলুদ চিহ্ন থাকে। online বিক্রি বদলায় না।',
  'Offline-এ sale করার সময় goods ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে sale হারিয়ে যায়। On থাকলে sale record হয় ও yellow flag থাকে। Online sale বদলায় না।',
  'An offline sale has already handed the goods over; if a short stock refuses it, the sale is lost. When on, the sale is recorded and flagged yellow. Online sales do not change.', 310),
 ('acct_count_adjust', '85', 'books', 'true'::jsonb, '{acc_start,acc_coa,acc_map}'::text[],
  'গণনার পার্থক্য খাতায় না উঠলে stock-এর মান আর খাতা আলাদা হয়ে যায়; চালু করলে প্রতি গণনা-সমন্বয়ে একটি entry হয়। সতর্কতা: চালু করলে হিসাব শুরুর তারিখ (বা acct_stock_moves_from) পর্যন্ত পুরোনো stock movement আসল তারিখে খাতায় উঠে যায়। বন্ধ মাসের তারিখ আটকে থাকে (মালিক ছাড়া)। তা না চাইলে আগে acct_stock_moves_from-এ তারিখ দিন।',
  'Count-এর difference খাতায় না উঠলে stock value আর books আলাদা হয়ে যায়; চালু করলে প্রতি count adjustment-এ একটি entry হয়। সতর্কতা: Switch চালু করলে accounting start (বা acct_stock_moves_from) পর্যন্ত backlog আসল তারিখে post হয়। Closed period-এর তারিখ আটকে থাকে (owner ছাড়া)। না চাইলে আগে acct_stock_moves_from-এ date দিন।',
  'Without it the stock value and the books drift apart; when on, every count adjustment becomes one entry. WARNING: turning it on posts the backlog back to the accounting start (or the acct_stock_moves_from date) at the original dates. Dates inside a closed period are held (locked) except for the owner. Set acct_stock_moves_from first if that is not wanted.', 311),
 ('acct_stock_opening', '85', 'books', 'false'::jsonb, '{}'::text[],
  'এটি বন্ধ রাখুন। স্টক যদি আগেই শুরুর জের (acct_opening)-এর মধ্যে থাকে, চালু করলে একই স্টক দুইবার গোনা হবে। শুরুর স্টক খাতায় নেওয়ার নিরাপদ পথ "Opening stock" পর্দা: সেখানে সংখ্যা দেখে একটি পথ বেছে নেওয়া হয়। শুধু হিসাব শুরুর তারিখ বা তার পরের opening ধরা হয়।',
  'এটা off রাখুন। Stock যদি আগেই opening balance (acct_opening)-এর মধ্যে থাকে, চালু করলে একই stock দুইবার গোনা হবে। Opening stock খাতায় নেওয়ার নিরাপদ পথ "Opening stock" screen: সেখানে numbers দেখে একটি option বেছে নেওয়া হয়। শুধু accounting start-এর পরের opening ধরা হয়।',
  'Keep this OFF. If the opening stock is already inside the opening balance (acct_opening), turning it on counts the same stock twice. The safe way to bring opening stock into the books is the Opening stock screen, where you pick one option after seeing the numbers. Only openings dated on or after the accounting start are posted.', 312),
 ('acct_issue_out', '85', 'books', 'true'::jsonb, '{acc_start,acc_coa,acc_map}'::text[],
  'না হলে নিজের কাজে stock বের করলে শুধু stock কমে, খরচ হিসাবে আসে না। চালু করলে ledger খরচে Dr "নিজের কাজে stock" / Cr inventory হয়। খরচ জানা নেই এমন সারি আন্দাজ হয় না, অপেক্ষায় থাকে। সতর্কতা: চালু করলে হিসাব শুরুর তারিখ (বা acct_stock_moves_from) পর্যন্ত পুরোনো stock movement আসল তারিখে খাতায় উঠে যায়। বন্ধ মাসের তারিখ আটকে থাকে (মালিক ছাড়া)। তা না চাইলে আগে acct_stock_moves_from-এ তারিখ দিন।',
  'না হলে own-use stock issue-এ শুধু stock কমে, expense হিসাবে আসে না। চালু করলে ledger cost-এ Dr own-use / Cr inventory হয়। Cost জানা না থাকা row আন্দাজ হয় না, অপেক্ষায় থাকে। সতর্কতা: Switch চালু করলে accounting start (বা acct_stock_moves_from) পর্যন্ত backlog আসল তারিখে post হয়। Closed period-এর তারিখ আটকে থাকে (owner ছাড়া)। না চাইলে আগে acct_stock_moves_from-এ date দিন।',
  'Otherwise an own-use issue lowers stock but never shows as an expense. When on it posts Dr stock issued for own use / Cr inventory at the ledger cost. Rows with no known cost are never guessed; they wait. WARNING: turning it on posts the backlog back to the accounting start (or the acct_stock_moves_from date) at the original dates. Dates inside a closed period are held (locked) except for the owner. Set acct_stock_moves_from first if that is not wanted.', 313),
 ('acct_transfer_mode', '85', 'books', null::jsonb, '{}'::text[],
  'একের বেশি জায়গা (শোরুম/গুদাম) থাকলে "location_tagged" ভালো: পাঠানো ও গ্রহণ আলাদা entry, মাঝে inter-location clearing। একটাই জায়গা হলে "off" থাকুক। "company_wide" = পুরো কোম্পানির হিসাব, জোড়া post হয় না। জায়গার সংখ্যার উপর নির্ভর করে, তাই এখানে মান ঠিক করা হয়নি। চালু করার সতর্কতা: backlog আসল তারিখে উঠে যায়।',
  'একের বেশি place (showroom/godown) থাকলে location_tagged ভালো: send ও receive আলাদা entry, মাঝে inter-location clearing। একটাই place হলে off থাকুক। company_wide = পুরো company-র books, pair post হয় না। Place-এর সংখ্যার উপর নির্ভর করে, তাই এখানে value ঠিক করা হয়নি। চালু করার warning: backlog আসল তারিখে post হয়।',
  'With more than one place (showroom or store) location_tagged is the usual choice: a send entry and a receive entry through the inter-location clearing account. With one place keep off. Company_wide means company-wide books only and no pair is posted. It depends on how many places you have, so no value is recommended. Warning: turning it on posts the backlog at the original dates.', 314),
 ('acct_transit_loss', '85', 'books', null::jsonb, '{}'::text[],
  'ট্রান্সফারের হিসাব (acct_transfer_mode) চালু থাকলে এটাও চালু রাখা ভালো: কম পৌঁছানো মালের খরচ আলাদা খাতে যায়। ট্রান্সফারের হিসাব বন্ধ থাকলে দরকার নেই, তাই এখানে মান ঠিক করা হয়নি। সতর্কতা: "receiver" হলে owner না মেটানো পর্যন্ত clearing-এ প্রেরক +V ও গ্রহণকারী -V দেখা যায়; backlog আসল তারিখে উঠে যায়।',
  'Transfer accounting (acct_transfer_mode) চালু থাকলে এটাও on রাখা ভালো: কম পৌঁছানো মালের cost আলাদা খাতে যায়। Transfer accounting বন্ধ থাকলে দরকার নেই, তাই এখানে value ঠিক করা হয়নি। Warning: receiver হলে owner না মেটানো পর্যন্ত clearing-এ sender +V ও receiver -V দেখা যায়; backlog আসল তারিখে post হয়।',
  'Best on when transfer accounting (acct_transfer_mode) is on: the missing cost goes to the transit loss account. Not needed when transfer accounting is off, so no value is recommended. Warning: with receiver the clearing account shows sender +V and receiver -V until the owner settles it; the backlog posts at the original dates.', 315),
 ('acct_transit_loss_at', '85', 'books', '"receiver"'::jsonb, '{}'::text[],
  'সাধারণ পছন্দ: গ্রহণকারী (receiver)। শুধু পথের ক্ষতি (acct_transit_loss) চালু থাকলে কাজ করে। সতর্কতা: receiver দিলে ক্ষতি গ্রহণকারীর জায়গায় বসে; owner না মেটানো পর্যন্ত clearing-এ প্রেরক +V ও গ্রহণকারী -V দেখা যায়। sender একটি বিকল্প।',
  'সাধারণ পছন্দ: receiver। শুধু transit loss (acct_transit_loss) on থাকলে কাজ করে। Warning: receiver দিলে loss গ্রহণকারী place-এ বসে; owner না মেটানো পর্যন্ত clearing-এ sender +V ও receiver -V দেখা যায়। sender একটি বিকল্প।',
  'The usual choice: receiver. Used only when transit loss posting (acct_transit_loss) is on. Warning: with receiver the loss is booked at the receiving place, so the clearing account shows sender +V and receiver -V until the owner settles it. Sender is the alternative.', 316),
 ('acct_purchase_variance', '85', 'books', 'true'::jsonb, '{acc_start,acc_coa,acc_map}'::text[],
  'কেনা ফেরতে stock গড় খরচে বের হয় কিন্তু সরবরাহকারীর credit bill-এর দামে; না হলে ফেরতের পর stock-এর মান আর খাতা মিলবে না। চালু করলে পার্থক্য আলাদা খাতে যায়। সতর্কতা: stock-tracked হলেও যে item type কেনার সময় consumable purchase-এ যায়, সেটি এই পার্থক্যের বাইরে থাকে। সতর্কতা: চালু করলে হিসাব শুরুর তারিখ (বা acct_stock_moves_from) পর্যন্ত পুরোনো stock movement আসল তারিখে খাতায় উঠে যায়। বন্ধ মাসের তারিখ আটকে থাকে (মালিক ছাড়া)। তা না চাইলে আগে acct_stock_moves_from-এ তারিখ দিন।',
  'Purchase return-এ stock গড় cost-এ বের হয় কিন্তু supplier credit bill-এর দামে; না হলে return-এর পর stock value ও books মিলবে না। চালু করলে difference আলাদা খাতে যায়। Warning: stock-tracked হলেও যে item type কেনার সময় consumable purchase-এ যায়, সেটি variance-এর বাইরে থাকে। সতর্কতা: Switch চালু করলে accounting start (বা acct_stock_moves_from) পর্যন্ত backlog আসল তারিখে post হয়। Closed period-এর তারিখ আটকে থাকে (owner ছাড়া)। না চাইলে আগে acct_stock_moves_from-এ date দিন।',
  'A return takes stock out at average cost but the supplier credit is at the bill price; without this, stock value and books differ after a return. When on, the difference goes to its own account. Warning: an item type that is stock-tracked but booked to consumable purchases is left out of the variance. WARNING: turning it on posts the backlog back to the accounting start (or the acct_stock_moves_from date) at the original dates. Dates inside a closed period are held (locked) except for the owner. Set acct_stock_moves_from first if that is not wanted.', 317),
 ('acct_stock_moves_from', '85', 'books', null::jsonb, '{}'::text[],
  'সুইচ দেরিতে চালালে বড় backlog এড়াতে একটি তারিখ (YYYY-MM-DD) দিন; এর আগের stock movement খাতায় উঠবে না। না দিলে হিসাব শুরু থেকে। তারিখ মালিক নিজে ঠিক করবেন, তাই কোনো মান প্রস্তাব করা হয়নি।',
  'Switch দেরিতে চালালে বড় backlog এড়াতে একটি date (YYYY-MM-DD) দিন; এর আগের stock movement খাতায় উঠবে না। না দিলে accounting start থেকে। Date owner নিজে ঠিক করবেন, তাই কোনো value প্রস্তাব করা হয়নি।',
  'If you turn the switches on late, type a date (YYYY-MM-DD) to avoid a big backlog; older stock movements are left out. Blank = from the accounting start. The owner picks the date, so no value is recommended.', 318),
 ('manual_journal_guard', '85', 'books', '"on"'::jsonb, '{}'::text[],
  'চালু করলে inventory, COGS, বিক্রি, payable, receivable বা stock-adjust খাতায় হাতে লেখা journal-এ কারণ-কোড (reason code) লাগে, আর payable/receivable লাইনে পক্ষ (party) লাগে। এতে হাতে-লেখা entry দিয়ে stock বা লাভ সরানো কঠিন হয়। কোড তালিকা চারটি দিয়ে শুরু; মালিক আরও যোগ করতে পারেন।',
  'চালু করলে inventory, COGS, sales, payable, receivable বা stock-adjust account-এ manual journal-এ reason code লাগে, আর payable/receivable line-এ party লাগে। এতে manual entry দিয়ে stock বা profit সরানো কঠিন হয়। Code list চারটি দিয়ে শুরু; owner আরও যোগ করতে পারেন।',
  'When on, a manual journal on an inventory, COGS, sales, payable, receivable or stock-adjust account needs a reason code, and payable or receivable lines need a party. This makes it hard to move stock or profit with a hand-written entry. The code list starts with four codes; the owner can add more.', 319),
 ('acct_scheduler_on', '85', 'books', null::jsonb, '{}'::text[],
  'এটি শুধু সুইচ দিয়ে চলে না: সার্ভারে pg_cron দিয়ে সময়-সূচি (scheduler) চালু করতে হয়, যেটা ফোন থেকে হয় না। চালু করতে হিসাব পর্দার "Auto posting" ট্যাবের enable ব্যবহার করুন (সেটা সূচি ও সুইচ একসাথে বসায়)। তাই এখানে মান ঠিক করা হয়নি।',
  'এটা শুধু switch দিয়ে চলে না: server-এ pg_cron দিয়ে scheduler চালু করতে হয়, যেটা phone থেকে হয় না। চালু করতে accounts screen-এর "Auto posting" tab-এর enable ব্যবহার করুন (সেটা schedule ও switch একসাথে বসায়)। তাই এখানে value ঠিক করা হয়নি।',
  'This does not work by the switch alone: a scheduler must be started on the server with pg_cron, which cannot be done from a phone. Use enable on the Auto posting tab of the accounts screen (it sets the schedule and the switch together). So no value is recommended here.', 320),
 ('acct_pending_alert_days', '85', 'books', null::jsonb, '{}'::text[],
  'এর মধ্যে কত দিনের পুরোনো কাগজ এখনো খাতায় ওঠেনি তা "দেরি" ধরা হবে। শিপ করা মান (ডিফল্ট) চলতে পারে অথবা নিজের সংখ্যা লিখুন; সংখ্যা মালিক ঠিক করবেন।',
  'কত দিনের পুরোনো document এখনো books-এ ওঠেনি তা "দেরি" ধরা হবে। Shipped default চলতে পারে অথবা নিজের সংখ্যা লিখুন; সংখ্যা owner ঠিক করবেন।',
  'How many days old a document may be before it counts as waiting too long to reach the books. Keep the shipped default or type your own; the number is the owner choice.', 321),
 ('telegram_intake_on', '86', 'pos', null::jsonb, '{}'::text[],
  'এটি চালু করলেও কিছু আসবে না, যতক্ষণ না বাইরের সেটআপ (Edge function ও bot) হয়, যেটা ফোন থেকে করা যায় না। কোনো উত্তর নিজে থেকে পাঠানো হয় না। সেটআপ হয়ে গেলে মালিক চালু করুন।',
  'এটা চালু করলেও কিছু আসবে না, যতক্ষণ না বাইরের setup (Edge function ও bot) হয়, যেটা phone থেকে করা যায় না। কোনো reply নিজে থেকে পাঠানো হয় না। Setup হয়ে গেলে owner চালু করুন।',
  'Nothing arrives when this is on until the outside setup (the Edge function and the bot) is done, which cannot be done from a phone. No reply is ever sent automatically. Switch it on after the setup.', 322),
 ('expiry_sale_guard', '87', 'stock', '"warn"'::jsonb, '{}'::text[],
  'মেয়াদ-উত্তীর্ণ মাল বিক্রি হলে warn দিলে বিক্রি চলে কিন্তু লাল সতর্কতায় batch ও মেয়াদ-শেষের তারিখ লেখা থাকে। refuse দিলে বিক্রি আটকায় (ভুল মেয়াদ বসানো থাকলে বৈধ বিক্রিও আটকাতে পারে, তাই আগে warn)। আগের block_expired_sale সুইচ আলাদা, সেটা এতে দুর্বল হয় না।',
  'মেয়াদ-উত্তীর্ণ মাল sale হলে warn দিলে sale চলে কিন্তু red warning-এ batch ও expiry date লেখা থাকে। refuse দিলে sale আটকায় (ভুল expiry বসানো থাকলে বৈধ sale-ও আটকাতে পারে, তাই আগে warn)। আগের block_expired_sale switch আলাদা, সেটা এতে দুর্বল হয় না।',
  'When expired stock is sold, warn lets the sale go through but the red warning names the batch and its expiry date. Refuse stops the sale (a wrong expiry date could stop a genuine sale, so start with warn). The older block_expired_sale switch is separate and is not weakened by this.', 323),
 ('purchase_backdate_flag', '87', 'stock', '"warn"'::jsonb, '{}'::text[],
  'আজকের তারিখ ছাড়া অন্য তারিখে purchase bill post হলে একটি হলুদ সতর্কতা জমে (stock তখনকার সময়ে নয়, এখনকার সময়ে ঢোকে; journal bill-এর তারিখে)। কিছু আটকায় না, শুধু পুরোনো তারিখের বিল চোখে পড়ে।',
  'আজকের date ছাড়া অন্য date-এ purchase bill post হলে একটি yellow warning জমে (stock এখনকার সময়ে ঢোকে; journal bill-এর date-এ)। কিছু আটকায় না, শুধু backdated bill চোখে পড়ে।',
  'When a purchase bill is posted with a date other than today, a yellow warning is kept (the stock is stamped now and the journal uses the bill date). Nothing is blocked; a backdated bill just becomes visible.', 324),
 ('production_double_issue_guard', '87', 'stock', '"warn"'::jsonb, '{}'::text[],
  'একই দিনে একই মাল উৎপাদন (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে সতর্কবার্তা আসে, কিছু আটকায় না।',
  'একই দিনে একই মাল production (recipe) আর stock issue/form দুটোতেই কাটলে দুবার কাটা হতে পারে; warn দিলে warning আসে, কিছু আটকায় না।',
  'If the same goods are deducted by a recipe production run and by a stock issue or form on the same day, they may be deducted twice; warn flags it and blocks nothing.', 325),
 ('report_cost_source', '88', 'stock', '"ledger_then_item_costs"'::jsonb, '{}'::text[],
  'সব রিপোর্টের পণ্য-খরচ প্রথমে journal যে ledger খরচ ব্যবহার করে সেখান থেকে আসে; ledger-এ না থাকলে লেখা item খরচ (আন্দাজ চিহ্নসহ)। এতে রিপোর্ট ও খাতার লাভ মেলে। ledger_avg = শুধু ledger, না থাকলে অজানা; item_costs = শুধু লেখা খরচ।',
  'সব report-এর product cost প্রথমে journal যে ledger cost ব্যবহার করে সেখান থেকে আসে; ledger-এ না থাকলে typed item cost (estimate চিহ্নসহ)। এতে report ও books-এর profit মেলে। ledger_avg = শুধু ledger, না থাকলে অজানা; item_costs = শুধু typed cost।',
  'Every report takes the product cost from the cost the journal uses (the stock ledger), and the typed item cost only where the ledger has none (marked as an estimate). This keeps report profit in line with the books. Ledger_avg = ledger only, no ledger cost means unknown; item_costs = typed cost only.', 326),
 ('scan_enabled', '90', 'purchase', 'true'::jsonb, '{}'::text[],
  'ছবি (bill বা তালিকা) থেকে এন্ট্রি চালু করলে ছবি একটি খসড়া (DRAFT) হয়; কোনো person দেখে নিশ্চিত না করা পর্যন্ত কিছু এন্ট্রি হয় না। শুরুতে reading method "manual" রাখুন (খরচ নেই)।',
  'ছবি (bill বা list) থেকে entry চালু করলে ছবি একটি DRAFT হয়; কোনো person দেখে confirm না করা পর্যন্ত কিছু entry হয় না। শুরুতে reading method manual রাখুন (cost নেই)।',
  'With scanning on, a photo of a bill or list becomes a DRAFT; nothing is entered until a person reviews and confirms it. Start with the reading method manual (no cost).', 327),
 ('scan_engine', '90', 'purchase', '"manual"'::jsonb, '{}'::text[],
  'manual = ছবির পাশে নিজে লাইন টাইপ করা (সবসময় কাজ করে, খরচ নেই)। browser_ocr আগে কিছু আসল bill-এ চেষ্টা করুন (বাংলা ও হাতের লেখায় দুর্বল)। ai_vision শুধু আলাদা সেটআপ ও key-এর পরে, আর প্রতিবার খরচ হয়। তাই manual দিয়ে শুরু।',
  'manual = ছবির পাশে নিজে line টাইপ করা (সবসময় কাজ করে, cost নেই)। browser_ocr আগে কিছু আসল bill-এ চেষ্টা করুন (Bangla ও handwriting-এ দুর্বল)। ai_vision শুধু আলাদা setup ও key-এর পরে, আর প্রতিবার cost হয়। তাই manual দিয়ে শুরু।',
  'Manual means you type the lines beside the photo (always works, no cost). Try browser_ocr on some real bills first (weak on Bangla and handwriting). Use ai_vision only after the separate setup and key, and every reading costs money. So start with manual.', 328),
 ('scan_min_confidence', '90', 'purchase', null::jsonb, '{}'::text[],
  'পাঠক যে ঘরে নিশ্চিত ছিল না সেটি হলুদ দেখায় (শুধু সতর্কতা, Confirm কখনো আটকায় না)। শিপ করা মান চলতে পারে; অন্য সংখ্যা মালিক নিজে লিখুন।',
  'Reader যে field-এ sure ছিল না সেটা yellow দেখায় (শুধু warning, Confirm কখনো আটকায় না)। Shipped default চলতে পারে; অন্য সংখ্যা owner নিজে লিখুন।',
  'A field the reader was unsure about is shown yellow (a warning only; it never blocks Confirm). The shipped default can stay; the owner types any other number.', 329),
 ('pos_show_invoice_after_sale', '92', 'pos', '"always"'::jsonb, '{}'::text[],
  'always দিলে প্রতি বিক্রির পরই ইনভয়েস পর্দায় খোলে, সঙ্গে Print, Email, SMS ও WhatsApp বোতাম। printer না থাকলেও ক্রেতা ইনভয়েস দেখতে ও পেতে পারে। Email, SMS, WhatsApp ফোনের নিজের app খোলে; আমাদের সার্ভার থেকে কিছু পাঠানো হয় না। ডিফল্ট never = আগের মতো (শুধু ছোট "Print receipt" বার)।',
  'always দিলে প্রতি sale-এর পরই invoice screen-এ খোলে, সঙ্গে Print, Email, SMS ও WhatsApp button। Printer না থাকলেও ক্রেতা invoice দেখতে ও পেতে পারে। Email, SMS, WhatsApp phone-এর নিজের app খোলে; আমাদের server থেকে কিছু পাঠানো হয় না। Default never = আগের মতো (শুধু ছোট "Print receipt" bar)।',
  'With always, the invoice opens on screen right after every sale, with Print, Email, SMS and WhatsApp buttons, so the customer can see and receive the invoice even when no printer is connected. Email, SMS and WhatsApp open the phone own app; nothing is sent from our server. The default never keeps today behaviour (only the small Print receipt bar).', 330),
 ('cash_drawer_mode', '95', 'pos', null::jsonb, '{}'::text[],
  'ক্যাশ ড্রয়ার লাগানো থাকলে "on_cash_sale" ভালো (নগদ নেওয়া হলে ড্রয়ার খুলতে বলা হয়)। ড্রয়ার না থাকলে off। ড্রয়ার আছে কিনা আমরা জানি না, তাই মান ঠিক করা হয়নি। ড্রয়ার নষ্ট বা না থাকলেও বিক্রি কখনো আটকায় না।',
  'Cash drawer লাগানো থাকলে on_cash_sale ভালো (cash নেওয়া হলে drawer খুলতে বলা হয়)। Drawer না থাকলে off। Drawer আছে কিনা আমরা জানি না, তাই value ঠিক করা হয়নি। Drawer নষ্ট বা না থাকলেও sale কখনো আটকায় না।',
  'Once a cash drawer is fitted, on_cash_sale is the usual choice (the drawer is asked to open when cash is taken). With no drawer keep off. We do not know whether a drawer is fitted, so no value is recommended. A missing or broken drawer never blocks a sale.', 331),
 ('cash_drawer_method', '95', 'pos', null::jsonb, '{}'::text[],
  'কীভাবে ড্রয়ারে সংযোগ হবে তা আপনার ডিভাইস ও প্রিন্টারের উপর নির্ভর করে (browser_print_pulse, web_serial, web_usb, bluetooth)। iPhone ব্রাউজার সরাসরি পারে না। kiosk_url এখনো তৈরি হয়নি। হার্ডওয়্যার না জেনে মান ঠিক করা হয়নি।',
  'কীভাবে drawer-এ connect হবে তা আপনার device ও printer-এর উপর নির্ভর করে (browser_print_pulse, web_serial, web_usb, bluetooth)। iPhone browser সরাসরি পারে না। kiosk_url এখনো তৈরি হয়নি। Hardware না জেনে value ঠিক করা হয়নি।',
  'The connection type depends on your device and printer (browser_print_pulse, web_serial, web_usb, bluetooth). iPhone browsers cannot talk to the drawer directly. kiosk_url is planned and not built yet. Without knowing the hardware, no value is recommended.', 332),
 ('cash_drawer_when', '95', 'pos', '"after_payment"'::jsonb, '{}'::text[],
  'after_payment = বিক্রি সেভ হওয়ার পরই ড্রয়ার খোলে (প্রস্তাবিত)। before_payment = Save চাপলেই খোলে, বিক্রি ব্যর্থ হলেও - তাতে বিক্রি ছাড়া ড্রয়ার খোলা যায়।',
  'after_payment = sale save হওয়ার পরই drawer খোলে (recommended)। before_payment = Save চাপলেই খোলে, sale fail হলেও - তাতে sale ছাড়া drawer খোলা যায়।',
  'After_payment opens the drawer only once the sale is saved (recommended). Before_payment opens it as soon as Save is tapped, even if the sale then fails, so the drawer can open without a sale.', 333),
 ('cash_drawer_no_sale_requires_reason', '95', 'pos', 'true'::jsonb, '{}'::text[],
  'বিক্রি ছাড়া ড্রয়ার খুললে (No sale) কারণ লিখতে হবে। বিক্রি ছাড়া প্রতিটি খোলা চুরি-ধরার সংকেত, তাই চালু রাখুন।',
  'Sale ছাড়া drawer খুললে (No sale) reason লিখতে হবে। Sale ছাড়া প্রতিটি open anti-theft signal, তাই চালু রাখুন।',
  'A No sale open cannot be logged without a reason. Every open without a sale is an anti-theft signal, so keep this on.', 334),
 ('acct_cost_wait_alert_days', '96', 'books', null::jsonb, '{}'::text[],
  'খরচ জানা নেই বলে অপেক্ষায় থাকা কাগজ কত দিনের বেশি হলে সতর্কতা আসবে - সংখ্যা মালিক নিজে লিখবেন, কোডে কোনো মান নেই। ফাঁকা = শুধু তালিকা দেখা যায়, সতর্কতা নেই। খরচ বসালে কাগজ নিজে থেকে খাতায় ঢোকে।',
  'Cost জানা নেই বলে অপেক্ষায় থাকা document কত দিনের বেশি হলে alert আসবে - সংখ্যা owner নিজে লিখবেন, code-এ কোনো value নেই। ফাঁকা = শুধু list দেখা যায়, alert নেই। Cost বসালে document নিজে থেকে books-এ ঢোকে।',
  'After how many days a document waiting for its cost raises an alert - the owner types the number; there is no built-in value. Blank = the waiting list is shown but no alert is raised. Once the cost is entered the document posts by itself.', 335),
 ('landed_cost_mode', '97', 'purchase', null::jsonb, '{}'::text[],
  'আমদানির মালে freight, শুল্ক ইত্যাদি item-এর খরচে যোগ করতে "per_shipment" ভালো; দেশের ভেতরে ডেলিভারি চার্জে "manual"। off = আগের মতো, item খরচ = bill-এর দাম। আপনি আমদানি করেন কিনা আমরা জানি না, তাই মান ঠিক করা হয়নি।',
  'Import-করা মালে freight, duty ইত্যাদি item cost-এ যোগ করতে per_shipment ভালো; দেশের ভেতরে delivery charge-এ manual। off = আগের মতো, item cost = bill-এর price। আপনি import করেন কিনা আমরা জানি না, তাই value ঠিক করা হয়নি।',
  'To add freight, duty and similar charges to item cost, per_shipment is the usual choice for imports and manual for a local delivery charge. Off = as before, item cost = the invoice price. We do not know whether you import, so no value is recommended.', 336),
 ('landed_alloc_default', '97', 'purchase', '"value"'::jsonb, '{}'::text[],
  'value = দামি মাল বেশি অংশ নেয়। weight বা volume ভাড়ার জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (কখনো আন্দাজ হয় না)। সাধারণ পছন্দ value; প্রতিবার বদলানো যায়।',
  'value = দামি মাল বেশি share নেয়। weight বা volume freight-এর জন্য ভালো, কিন্তু ওজন জানা থাকতে হবে (কখনো আন্দাজ হয় না)। সাধারণ পছন্দ value; প্রতিবার বদলানো যায়।',
  'Value means costly goods take a bigger share. Weight or volume is best for freight but the weight must be known (it is never guessed). Value is the usual choice and can be changed for each landed cost.', 337),
 ('landed_late_mode', '97', 'purchase', '"split_remaining_and_cogs"'::jsonb, '{}'::text[],
  'lot-এর কিছু অংশ বিক্রি বা ব্যবহার হয়ে যাওয়ার পর charge এলে: split দিলে যেটুকু শেলফে আছে সেটা stock খরচে যায়, যেটুকু বিক্রি হয়ে গেছে সেটা landed-cost variance-এ (লাভ-ক্ষতি)। এতে stock-এর খরচ অযথা বাড়ে না ও খরচ হারায় না।',
  'Lot-এর কিছু অংশ sale বা use হয়ে যাওয়ার পর charge এলে: split দিলে যেটুকু shelf-এ আছে সেটা stock cost-এ যায়, যেটুকু sold হয়ে গেছে সেটা landed-cost variance-এ (P&L)। এতে stock cost অযথা বাড়ে না ও cost হারায় না।',
  'When a charge arrives after part of the lot was sold or used, split puts the part still on the shelf into stock cost and the part already sold into the landed-cost variance (profit and loss). Stock cost does not look inflated and no cost is lost.', 338),
 ('landed_cost_requires_approval', '97', 'purchase', null::jsonb, '{}'::text[],
  'required দিলে landed cost অনুমোদন ছাড়া post হয় না, আর যিনি বানিয়েছেন তিনি অনুমোদন করতে পারেন না (মালিক পারেন)। warn দিলে অনুমোদন ছাড়াও post হয় কিন্তু হলুদ সতর্কতা জমে। কত টাকার উপরে "বড়" তা মালিক ঠিক করবেন, তাই মান ঠিক করা হয়নি।',
  'required দিলে landed cost approval ছাড়া post হয় না, আর যিনি বানিয়েছেন তিনি approve করতে পারেন না (owner পারেন)। warn দিলে approval ছাড়াও post হয় কিন্তু yellow warning জমে। কত টাকার উপরে "বড়" তা owner ঠিক করবেন, তাই value ঠিক করা হয়নি।',
  'With required, a landed cost cannot be posted until approved and the person who made it cannot approve it (the owner can). With warn it can be posted without approval but a yellow warning is kept. What counts as a big amount is the owner decision, so no value is recommended.', 339),
 ('landed_reminder_on', '97', 'purchase', null::jsonb, '{}'::text[],
  'চালু করলে আমদানি-করা বা চিহ্নিত সরবরাহকারীর যে bill-এ landed cost যোগ হয়নি সেগুলোর একটি তালিকা দেখা যায়। আমদানি করলে চালু ভালো; না করলে দরকার নেই, তাই মান ঠিক করা হয়নি।',
  'চালু করলে imported বা flagged supplier-এর যে bill-এ landed cost যোগ হয়নি সেগুলোর একটি list দেখা যায়। Import করলে on ভালো; না করলে দরকার নেই, তাই value ঠিক করা হয়নি।',
  'When on, bills of imported or flagged suppliers that have no landed cost are listed. Good to have on if you import; not needed otherwise, so no value is recommended.', 340),
 ('landed_reminder_days', '97', 'purchase', null::jsonb, '{}'::text[],
  'মনে-করানো তালিকা কত দিন পিছনে দেখবে। শিপ করা মান চলতে পারে অথবা নিজের সংখ্যা লিখুন; সংখ্যা মালিক ঠিক করবেন। এর চেয়ে পুরোনো bill তালিকায় আসে না।',
  'Reminder list কত দিন পিছনে দেখবে। Shipped default চলতে পারে অথবা নিজের সংখ্যা লিখুন; সংখ্যা owner ঠিক করবেন। এর চেয়ে পুরোনো bill list-এ আসে না।',
  'How many days back the reminder list looks. Keep the shipped default or type your own; the number is the owner choice. Older bills do not appear in the list.', 341),
 ('landed_base_currency', '97', 'purchase', null::jsonb, '{}'::text[],
  'landed cost-এর মূল মুদ্রার কোড (যেমন আপনার হিসাবের মুদ্রা)। অন্য মুদ্রার charge এই মুদ্রায় বদলানো হয়; হার আপনি নিজে লেখেন। মুদ্রা ও হার মালিকের, তাই কোনো মান প্রস্তাব করা হয়নি।',
  'Landed cost-এর base currency code (আপনার books-এর currency)। অন্য currency-র charge এই currency-তে convert হয়; rate আপনি নিজে লেখেন। Currency ও rate owner-এর, তাই কোনো value প্রস্তাব করা হয়নি।',
  'The base currency code of landed costs (the currency of your books). A charge in another currency is converted to it and you type the rate yourself. The currency and rate are the owner choice, so no value is recommended.', 342)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
where current_setting('phase101.ok', true) = 'on'
on conflict (code) do nothing;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase102.sql
-- ============================================================
-- Phase 102 (bos102) - STEP Img: item photos on the item cards / pickers. Owner option, DEFAULT = today's behaviour (off).
--   Needs phases 72..98 (guard below). Canonical order: ... phase524, phase525, (phase100, phase101 in their own steps), phase102. Additive + paste-twice safe.
--   Nothing existing is re-created (no function of phases 72..101 is touched). Strictly a display option: no sale, stock, price, journal or permission changes.
--   rule item_images_mode           off (DEFAULT = today) | pos_only (POS item cards only) | everywhere (POS + item pickers / lists)
--   rule item_images_thumb_only     on (recommended) | off : load the small thumbnail (<path>.t.jpg) when it exists, else the original
--   rule item_images_cache_hours    number the OWNER types (blank = keep signed links / pictures for the session only)
--   rows in setup_rec_defs81 (advisory; ON CONFLICT DO NOTHING). Recommendation: item_images_mode = pos_only (see the reason text), thumb_only = on, cache hours = none.
--   RPC items_first_image(item_ids uuid[]) -> (item_id, path): first photo path only, SECURITY INVOKER so the items row policy / grants apply exactly as for a select on items.
--     No cost, price or stock column is returned. At most 500 ids per call.
-- ============================================================

-- ---------- guard ----------
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.set_doc_template(text,text,integer)'), ('94', 'public._scan_photo_ok(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.drawer_events') is null then miss := miss || ' 95'; end if;
  if to_regclass('public.opening_stock_actions96') is null then miss := miss || ' 96'; end if;
  if to_regclass('public.landed_costs') is null then miss := miss || ' 97'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or pg_get_functiondef('public._acct_docs(date)'::regprocedure) not like '%bos98%' then miss := miss || ' 98'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)') is null
     or pg_get_functiondef('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure) not like '%bos72%' then miss := miss || ' 79'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is not null
     and pg_get_functiondef('public._cogs_lines72(date,date,integer[])'::regprocedure) not like '%bos89%' then miss := miss || ' 89'; end if;
  if miss <> '' then
    raise exception 'phase102 needs phases 72..98 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('item_images_mode', 'pos', 'choice', '"off"', null, '["off","pos_only","everywhere"]'::jsonb, null, null,
  'আইটেমের ছবি দেখানো', 'Item এর photo দেখানো', 'Show item photos',
  'off = আজকের নিয়ম (ছবি শুধু আইটেম ফর্মে)। pos_only = শুধু POS-এর আইটেম কার্ডে। everywhere = POS ও সব আইটেম বাছাই/তালিকায়। ছবি না থাকলে নামের প্রথম অক্ষর দেখায়।',
  'off = today (photos only in the item form). pos_only = POS item cards only. everywhere = POS and every item picker / list. An item without a photo shows its first letter.', 661),
 ('item_images_thumb_only', 'pos', 'choice', '"on"', null, '["on","off"]'::jsonb, null, null,
  'ছোট thumbnail আগে লোড', 'ছোট thumbnail আগে load', 'Load the small thumbnail first',
  'on = নতুন তোলা ছবির ছোট কপি থাকলে সেটাই লোড হয় (কম data)। ছোট কপি না থাকলে আসল ছবি। off = সবসময় আসল ছবি।',
  'on = when a photo has a small copy (uploaded with it) only that is loaded (less data). Without a small copy the original is used. off = always the original.', 662),
 ('item_images_cache_hours', 'pos', 'number', null, 'ঘণ্টা', null, 1, 720, 'ছবির link/cache কত ঘণ্টা রাখবে', 'Photo link/cache কত ঘণ্টা রাখবে', 'Hours to keep photo links and pictures',
  'আপনি লিখবেন; ফাঁকা = শুধু এই সেশন। বেশি ঘণ্টা দিলে ধীর নেটে বা অফলাইনে ছবি আসে, কিন্তু বদলানো ছবি দেরিতে দেখা যায়। ১ ঘণ্টার বেশি দিলেও সাইন করা link সর্বোচ্চ ১ ঘণ্টা চলে; ছবির নিজস্ব কপি এই সময় ধরে থাকে।',
  'You type it; blank = this session only. A longer time helps on slow data or offline, but a changed photo shows later. Signed links themselves last at most 1 hour; the picture copy is kept for this time.', 663)
 on conflict (key) do nothing;

-- ---------- first image path of many items (one round trip instead of full item rows) ----------
create or replace function public.items_first_image(item_ids uuid[]) returns table (item_id uuid, path text)
language sql stable security invoker set search_path = public as $$
  select i.id, i.images[1] from public.items i
   where i.id = any(item_ids) and coalesce(array_length(item_ids, 1), 0) <= 500
     and coalesce(array_length(i.images, 1), 0) > 0 and i.images[1] is not null and i.images[1] <> ''
$$;
revoke all on function public.items_first_image(uuid[]) from public, anon;
grant execute on function public.items_first_image(uuid[]) to authenticated;

-- ---------- setup advisor rows (advisory only) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('item_images_mode', '102', 'pos', '"pos_only"'::jsonb, '{}'::text[],
  'ছবি ডেটা খরচ করে। POS-এ ছবি থাকলে ব্যস্ত সময়ে ঠিক আইটেম চেনা সহজ, আর কার্ডের সংখ্যা সীমিত; তাই pos_only সুপারিশ। everywhere দিলে লম্বা তালিকায় অনেক ছবি লোড হয়, ধীর মোবাইল নেটে খরচ বাড়ে। মোবাইল নেট ভালো হলে পরে everywhere দিতে পারেন।',
  'Photo data খরচ করে। POS-এ photo থাকলে busy সময়ে ঠিক item চেনা সহজ, আর card এর সংখ্যা সীমিত; তাই pos_only recommend। everywhere দিলে লম্বা list এ অনেক photo load হয়, slow mobile data তে খরচ বাড়ে। Data ভালো হলে পরে everywhere দিতে পারেন।',
  'Photos use mobile data. On the POS a photo helps pick the right item in busy hours and the number of cards on screen is limited, so pos_only is recommended. Everywhere loads many pictures in long lists, which costs more on slow data. Switch to everywhere later if your data is good.', 361),
 ('item_images_thumb_only', '102', 'pos', '"on"'::jsonb, '{}'::text[],
  'ছোট কপি আসল ছবির চেয়ে অনেক কম data নেয়। যে ছবির ছোট কপি নেই তার আসল ছবিই আসে, তাই on রাখা নিরাপদ।',
  'ছোট copy আসল photo এর চেয়ে অনেক কম data নেয়। যে photo র ছোট copy নেই তার আসল photo ই আসে, তাই on রাখা safe।',
  'The small copy uses much less data than the original. A photo without a small copy falls back to the original, so on is safe.', 362),
 ('item_images_cache_hours', '102', 'pos', null::jsonb, '{}'::text[],
  'ঘণ্টা আপনার নেটের অবস্থার উপর নির্ভর করে, তাই কোনো মান ঠিক করে দেওয়া হয়নি। ফাঁকা = শুধু এই সেশন।',
  'ঘণ্টা আপনার net এর অবস্থার উপর নির্ভর করে, তাই কোনো value ঠিক করে দেওয়া হয়নি। ফাঁকা = শুধু এই session।',
  'The hours depend on your network, so no value is recommended. Blank = this session only.', 363)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
where to_regclass('public.setup_rec_defs81') is not null
on conflict do nothing;

-- ---------------------------------------------------------------- phase103.sql
-- ============================================================
-- Phase 103 (bos103) - STEP E2E: fixes for the defects an independent end-to-end run found (docs/briefs_p2p3/step_E2E_REPORT.md). Goes LAST.
--   Needs phases 72..101 pasted first (guard below, incl. phase524 = the _acct_docs merge, phase525, phase100, phase101). It carries the COMPLETE final text of the functions below, so if phase515 / 520 / 522 / 523 is ever pasted again, pasting phase103 again repairs it (phase524 itself would refuse: its body guard does not know bos103). Phase102 (item images) touches no accounting function.
--   Additive, paste-twice safe: every function is re-created from its LATEST body (phase524 / phase525 / phase522 / phase515 / phase507 text), only lines tagged bos103 differ,
--   every older bosNN tag is kept; one new switch (default OFF), one new advisor check row, three internal helper functions. No table, column, trigger or privilege of an
--   existing object is changed. Each create runs only if both guards passed (session flag phase103.ok).
--   D-1  production run whose ingredients are ALL free-cost items: a free-cost item is a known cost 0, so the run is no longer "cost_missing" for ever
--        (_acct_docs). Conversion cost, if any, is posted (Dr finished goods / Cr overhead absorbed); a run with nothing to book posts nothing and does not wait.
--   D-2  direct production-in without a recipe: appears in the cost-waiting list when its cost is missing (_cw_docs96 / _cw_rows96), and posts when the cost is known
--        if the new switch acct_manual_prod_in103 is ON (default OFF = as before; Dr inventory / Cr overhead absorbed, one entry per ledger row). inventory_vs_gl
--        removes what the entries cover from the manual_in reason.
--   D-3  cost supplied later to an opening row after the opening-stock helper: the helper (opening_stock_apply96) can be applied ONE more time for the rows the
--        first decision did not cover; no double count (the rows are frozen again, a second call answers already_applied).
--   D-4  recipe_cost: a free-cost ingredient is a known cost 0 (unit_cost 0, complete = true), the same as production_post.
--   D-5  GRN is the stock source + purchase_grn_guard off: new flow check flw_grn_double103 (setup_flow_check, level warn, never blocks) and the setup advisor
--        recommends skip for purchase_grn_guard while grn_receipt_source = grn (computed at read time; the phase101 row and every owner-chosen value are untouched).
--   D-6  inventory_vs_gl: GRN stock rows covered by a bill that added no stock of its own (guard skip / link) are no longer "manual_in".
--   D-7  inbox_pii_mode masked modes also mask a phone number typed inside free text (message text, name, address, order note); unmask stays audited.
--   D-8  customer_directory / find_customer follow inbox_pii_mode: mobile (and whatsapp / address / note) masked for a user who is neither owner nor holds view_customer_mobile.
--   Tag: bos103.
-- ============================================================

do $g$ begin perform set_config('phase103.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  -- 98: the merged _acct_docs (bos98), or phase103 itself pasted before, or the phase515 merge (bos89) with the markers of 96 and 97 above: phase103 carries the COMPLETE merged body, so it also repairs a re-paste of 89 / 96 / 97
  if to_regprocedure('public._acct_docs(date)') is null
     or (position('bos98' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0 and position('bos103' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0
         and position('bos89' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0) then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if miss <> '' then
    raise exception 'phase103 needs phases 72..101 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase103.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase103.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._acct_docs(date)', array['bos103', 'bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89', 'bos96', 'bos97', 'bos98']::text[]),
    ('public._acct_stock_moves85(date)', array['bos103', 'bos96']::text[]),
    ('public.inventory_vs_gl(date,integer)', array['bos103', 'bos85', 'bos96']::text[]),
    ('public._cw_docs96()', array['bos103']::text[]),
    ('public._cw_rows96(text,text)', array['bos103']::text[]),
    ('public._cw_posted96(text,text)', array['bos103']::text[]),
    ('public.recipe_cost(uuid,integer)', array['bos103', 'bos73', 'bos74']::text[]),
    ('public._ob_plan96(text,integer,text,date)', array['bos103']::text[]),
    ('public.opening_stock_apply96(text,integer,text,date,text,uuid)', array['bos103']::text[]),
    ('public._setup_chk81(text)', array['bos103']::text[]),
    ('public.setup_recommendations()', array['bos103']::text[]),
    ('public.setup_recommend_apply(uuid,text[],boolean,boolean)', array['bos103', 'bos109']::text[]),
    ('public._inb_pii_f99(text,text)', array['bos103']::text[]),
    ('public._inb_pii_json99(jsonb)', array['bos103']::text[]),
    ('public.inbox_list(integer,text,integer)', array['bos103', 'bos99']::text[]),
    ('public.customer_directory(integer)', array['bos103']::text[]),
    ('public.find_customer(text)', array['bos103']::text[]),
    ('public._ob_rows96(integer)', array['bos103']::text[]),
    ('public.online_order_get(uuid)', array['bos103', 'bos76', 'bos77', 'bos99']::text[]),
    ('public.online_orders_list(integer,text,date,date,integer)', array['bos103', 'bos76', 'bos77', 'bos99']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase103: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase103.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- follow-up decisions of the opening-stock helper (append-only, audited; one decision per place stays in opening_stock_actions96) ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
  create table if not exists public.opening_stock_followups103 (
    id bigint generated always as identity primary key,
    action_id bigint references public.opening_stock_actions96(id),
    location_id int references public.locations(id),
    option text not null check (option in ('owner_capital', 'existing_account', 'skip', 'difference')),
    account_code text, amount numeric(18,2) not null default 0, entry_id bigint,
    covered_ids bigint[] not null default '{}',                -- the opening ledger rows this follow-up covers (a cost supplied later, or an opening entered later)
    reason text, client_id uuid unique, created_by uuid, created_staff text, created_at timestamptz not null default now());
  alter table public.opening_stock_followups103 enable row level security;
  revoke all on public.opening_stock_followups103 from public, anon, authenticated;
  drop trigger if exists opening_stock_followups103_ro on public.opening_stock_followups103;
  create trigger opening_stock_followups103_ro before update or delete on public.opening_stock_followups103 for each row execute function public._ledger_immutable();
  drop trigger if exists opening_stock_followups103_nt on public.opening_stock_followups103;
  create trigger opening_stock_followups103_nt before truncate on public.opening_stock_followups103 for each statement execute function public._ledger_immutable();
  drop trigger if exists audit_opening_stock_followups103 on public.opening_stock_followups103;
  create trigger audit_opening_stock_followups103 after insert on public.opening_stock_followups103 for each row execute function public.log_change('id');
  create or replace view public.opening_covered103 as
    select a.location_id, a.covered_ids from public.opening_stock_actions96 a
    union all select f.location_id, f.covered_ids from public.opening_stock_followups103 f;
  revoke all on public.opening_covered103 from public, anon, authenticated;
end if; end $p103$;

-- ---------- new switch (default OFF = today's behaviour) ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('acct_manual_prod_in103', 'books', 'switch', 'false', null, null, null,
  'Recipe ছাড়া সরাসরি production-in journal এ তোলা', 'Recipe ছাড়া direct production-in journal এ post করা', 'Post direct production-in (no recipe) to the books',
  'বন্ধ থাকলে আগের মতোই: recipe ছাড়া production-in শুধু stock বাড়ায়, journal এ যায় না (inventory_vs_gl এ manual_in হিসেবে দেখা যায়)। চালু করলে লেখা cost ধরে প্রতিটি row এর জন্য একটি entry হয়। cost না থাকলে cost-waiting তালিকায় থাকে।',
  'Off = as before: a production-in typed without a recipe raises the stock only and is not in the books (inventory_vs_gl lists it as manual_in). On = one entry per row at the typed cost: Dr inventory / Cr overhead absorbed. A row without a cost waits in the cost-waiting list either way.', 956)
on conflict (key) do nothing;
end if; end $p103$;

-- ---------- new advisor check (flow): the double count of a GRN + a bill that both add stock ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort, active) values
 ('flw_grn_double103', 'stock_tracking', 'flow', null, 'warn',
  'GRN মালের উৎস, guard বন্ধ, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে',
  'GRN goods এর source, guard off, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে',
  'GRN is the stock source, the guard is off and bills also add stock: the same goods are counted twice',
  'purchase_grn_guard "skip" করুন (bill শুধু টাকা ধরবে), তারপর বাড়তি stock গুনে ঠিক করুন',
  'purchase_grn_guard "skip" করুন (bill শুধু money ধরবে), তারপর extra stock count করে ঠিক করুন',
  'Set purchase_grn_guard to skip (the bill then records money only), then correct the extra stock with a count', 'stock', 71, true)
on conflict (code) do update set topic = excluded.topic, kind = excluded.kind, level = excluded.level, label_bn = excluded.label_bn, label_mix = excluded.label_mix, label_en = excluded.label_en,
  fix_bn = excluded.fix_bn, fix_mix = excluded.fix_mix, fix_en = excluded.fix_en, nav = excluded.nav, sort = excluded.sort, active = excluded.active;
end if; end $p103$;

-- ---------- the grant that the customer screens already test (rpt_grant('view_customer_mobile')) becomes a grant the owner can give ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_customer_mobile', 'pos', 97, 'গ্রাহকের মোবাইল নম্বর দেখা (ইনবক্স ঢাকা থাকলেও)', 'Customer এর mobile number দেখা (inbox mask থাকলেও)', 'See customer mobile numbers (even when inbox masking is on)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_customer_mobile');
end if; end $p103$;

-- ---------- internal helpers ----------
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._inb_mask_phones103(p text) returns text
language plpgsql immutable set search_path = public as $b$
-- masks every phone-number-like digit run (ASCII or Bangla digits, optional +, spaces / hyphens / brackets between digits, 8..15 digits; a date such as 2026-10-14 is left alone), keeps the last 3 digits
declare r text := p; m text[]; dg text; nd int;
begin
  if p is null or p !~ '[0-9০-৯]' then return p; end if;
  for m in select regexp_matches(p, '\+?[0-9০-৯](?:[0-9০-৯]|[ ()-]{1,2}(?=[0-9০-৯])){6,}', 'g') loop
    dg := regexp_replace(m[1], '[^0-9০-৯]', '', 'g'); nd := char_length(dg);
    if nd between 8 and 15 and m[1] !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
      r := replace(r, m[1], repeat('•', greatest(nd - 3, 3)) || right(dg, 3));
    end if;
  end loop;
  return r;
end $b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._cust_pii103(p_field text, p_val text) returns text
language plpgsql stable security definer set search_path = public as $b$
-- customer fields follow inbox_pii_mode; owner and view_customer_mobile holders see them as before
declare mode_ text := public._inb_pii_mode99();
begin
  if p_val is null or btrim(p_val) = '' or mode_ = 'off' then return p_val; end if;
  if public.is_owner() or public.rpt_grant('view_customer_mobile') then return p_val; end if;
  return case p_field
    when 'mobile' then public._inb_mask99('mobile', p_val)
    when 'address' then case when mode_ in ('mask_phone_address', 'mask_all_pii') then public._inb_mask99('address', p_val) else public._inb_mask_phones103(p_val) end
    else case when mode_ = 'mask_all_pii' then public._inb_mask99('text', p_val) else public._inb_mask_phones103(p_val) end end;
end $b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
create or replace function public._rec_value103(p_key text, p_rec jsonb) returns jsonb
language sql stable security definer set search_path = public as $b$
  -- purchase_grn_guard has no fixed recommendation (phase101); while GRN is the stock source the recommendation is skip
  select case when p_key = 'purchase_grn_guard' and p_rec is null and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then '"skip"'::jsonb else p_rec end
$b$;
$f$; end if; end $p103$;

do $p103$ begin if current_setting('phase103.ok', true) = 'on' then
  revoke all on function public._inb_mask_phones103(text), public._cust_pii103(text, text), public._rec_value103(text, jsonb) from public, anon, authenticated;
end if; end $p103$;

-- ---- public._acct_docs(date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);

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
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
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
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
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

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);
end $function$
$f$; end if; end $p103$;

-- ---- public._acct_stock_moves85(date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f,
                      public.rule_on('acct_manual_prod_in103') p /* bos103 */),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer'
             when 'production_in' then case when not exists (select 1 from public.production_runs pr where pr.id::text = coalesce(o.ref_id, l.ref_id)) then 'prodin' end /* bos103: direct production-in, no recipe run */ end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal', 'production_in') /* bos103 */
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' when 'prodin' then 'overhead_absorbed' /* bos103 */ else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_covered103 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x) or (m.cls = 'prodin' and cfg.p))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$
$f$; end if; end $p103$;

-- ---- public.inventory_vs_gl(date,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean; j_skip numeric; j_prodin numeric; g_dup numeric; /* bos103 */
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
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'entry'), 0) as g_grn_in, /* bos103 */
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening', 'opening_stock96') /* bos85 bos96 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    -- bos103: inventory a posted bill booked while it added no stock rows of its own (guard skip / link: the stock came from the GRN) covers GRN stock rows; direct production-in rows that were posted by acct_manual_prod_in103
    select coalesce(sum(jl.debit - jl.credit), 0) into j_skip from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id join public.purchase_bills pb on pb.id::text = e.source_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'purchase' and e.reverses_id is null and pb.kind = 'bill' and (p_loc is null or jl.location_id = p_loc)
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id)
        and not exists (select 1 from public.stock_ledger sl where sl.ref_type = 'purchase' and sl.reason = 'purchase_in' and sl.ref_id = pb.id::text);
    -- bos103: with GRN as the stock source, a bill that added its own stock after the first GRN stock row duplicates GRN stock (guard off): that part is NOT explained as manual_in, it stays in "unexplained"
    select coalesce(sum(coalesce(sl.qty_delta * sl.unit_cost, 0)), 0) into g_dup from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id
      where public._acct_inv_key(it.item_type) = k and sl.reason = 'purchase_in' and sl.ref_type = 'purchase' and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)
        and sl.made_at >= (select min(g.made_at) from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null)
        and not exists (select 1 from public.stock_ledger v where v.reverses_id = sl.id);
    select coalesce(sum(jl.debit - jl.credit), 0) into j_prodin from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'stock_prodin' and (p_loc is null or jl.location_id = p_loc);
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in + least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)) + least(greatest(rw.g_grn_in - least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)), 0), greatest(g_dup, 0)) + j_prodin, 2)),   -- bos103
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
$f$; end if; end $p103$;

-- ---- public._cw_docs96() ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_docs96()
 RETURNS TABLE(kind text, ref text, loc integer, d date, n integer, gl boolean, move text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with u as (
    select l.id, l.location_id, l.reason, l.ref_type, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date dd,
      case when l.reason = 'wastage' and l.ref_type = 'wastage' then 'wastage'
           when l.reason = 'issue_out' and l.ref_type = 'production' then 'production'
           when l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' then 'transfer'
           when l.reason = 'purchase_return' and l.ref_type = 'purchase' then 'purchase_return'
           when l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production')
           or (l.reason = 'production_in' and not exists (select 1 from public.production_runs pr where pr.id::text = l.ref_id)) /* bos103: direct production-in without a recipe */ then 'ledger' end k
    from public.stock_ledger_eff96 l
    where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
      and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
      and not (l.reason = 'opening' and exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)  /* bos103 */ and (a.location_id is null or a.location_id = l.location_id)))),
  g as (
    select u.k, case when u.k = 'ledger' then u.id::text else u.ref_id end ref, (array_agg(u.location_id order by u.id))[1] loc, min(u.dd) d, count(*)::int n, min(u.reason) r
    from u where u.k is not null group by 1, 2)
  select g.k, g.ref, g.loc, g.d, g.n,
         public.rule_on('accounting_on') and public._acct_start() is not null and g.d >= public._acct_start() and g.d >= coalesce(public._acct_from85(), public._acct_start())
         and case g.k when 'wastage' then true when 'production' then true when 'transfer' then coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged'
                      when 'purchase_return' then public.rule_on('acct_purchase_variance')
                      else case g.r when 'count_adjust' then public.rule_on('acct_count_adjust') when 'opening' then public.rule_on('acct_stock_opening') when 'production_in' then public.rule_on('acct_manual_prod_in103') /* bos103 */ else public.rule_on('acct_issue_out') end end,
         g.r
  from g where g.ref is not null and not public._cw_posted96(g.k, g.ref);
$function$
$f$; end if; end $p103$;

-- ---- public._cw_rows96(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_rows96(p_kind text, p_ref text)
 RETURNS TABLE(lid bigint, item_id uuid, loc integer, qty numeric, reason text, made_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.item_id, l.location_id, l.qty_delta, l.reason, l.made_at
  from public.stock_ledger_eff96 l
  where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
    and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                    and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
    and not (l.reason = 'opening' and exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)  /* bos103 */ and (a.location_id is null or a.location_id = l.location_id)))
    and case p_kind
      when 'wastage' then l.reason = 'wastage' and l.ref_type = 'wastage' and l.ref_id = p_ref
      when 'production' then l.reason = 'issue_out' and l.ref_type = 'production' and l.ref_id = p_ref
      when 'transfer' then l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' and l.ref_id = p_ref
      when 'purchase_return' then l.reason = 'purchase_return' and l.ref_type = 'purchase' and l.ref_id = p_ref
      when 'ledger' then l.id::text = p_ref and (l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production')
                                       or (l.reason = 'production_in' and not exists (select 1 from public.production_runs pr where pr.id::text = l.ref_id))) /* bos103 */
      else false end;
$function$
$f$; end if; end $p103$;

-- ---- public._cw_posted96(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cw_posted96(p_kind text, p_ref text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case p_kind
    when 'wastage' then exists (select 1 from public.journal_entries e where e.source_type = 'wastage' and e.source_id = p_ref and e.reverses_id is null)
    when 'production' then exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = p_ref and e.reverses_id is null)
    when 'purchase_return' then exists (select 1 from public.journal_entries e where e.source_type = 'purchase_variance' and e.source_id = p_ref and e.reverses_id is null)
    when 'transfer' then exists (select 1 from public.journal_entries e where e.reverses_id is null and ((e.source_type = 'stock_transfer' and e.source_id in
                                   (select s.id::text from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = p_ref)) or (e.source_type = 'transit_loss' and e.source_id = p_ref)))
    when 'ledger' then exists (select 1 from public.journal_entries e where e.source_type in ('stock_adjust', 'stock_opening', 'stock_issue', 'stock_prodin') /* bos103 */ and e.source_id = p_ref and e.reverses_id is null)
    else false end;
$function$
$f$; end if; end $p103$;

-- ---- public.recipe_cost(uuid,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.recipe_cost(p_recipe uuid, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  for n in select * from public._recipe_need(p_recipe, 1, coalesce(p_loc, 0)) order by kind, code loop      -- bos74: the same function the production run uses
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = n.item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null and public._cost_free80(n.item_id) then av := 0; end if;   -- bos103: a free-cost item is a known cost 0 (production_post accepts it the same way)
    td := public._today_cost(n.item_id, p_loc);
    if av is null then complete := false;
    elsif n.kind = 'packaging' then pack_t := pack_t + n.need * av; else raw_t := raw_t + n.need * av; end if;
    if td is null then fb := fb + 1; end if;
    if coalesce(td, av) is not null then
      if n.kind = 'packaging' then pack_d := pack_d + n.need * coalesce(td, av); else raw_d := raw_d + n.need * coalesce(td, av); end if;
    end if;
    gl := case when av is not null and av > 0 and td is not null then round((td - av) / av * 100, 2) end;
    ls := ls || jsonb_build_object('ingredient_item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'need_base', n.need, 'unit_cost', av, 'line_cost', case when av is null then null else round(n.need * av, 4) end,
      'today_unit_cost', td, 'gap_pct', gl, 'waste_missing', n.waste_missing);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, (now() at time zone 'Asia/Dhaka')::date, case when p_loc is null then 'recipe' end);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); mode_ := conv->>'mode'; cinc := mode_ <> 'off' and not (conv->>'complete')::boolean;
  mat := raw_t + pack_t; matd := raw_d + pack_d;
  gap := case when complete and mat > 0 then round((matd - mat) / mat * 100, 2) end;
  thr := public.rule_num('cost_gap_warn_pct');
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete,
    'rows', jsonb_build_array(jsonb_build_object('row', 'raw', 'amount', case when complete then round(raw_t, 4) end), jsonb_build_object('row', 'packaging', 'amount', case when complete then round(pack_t, 4) end),
      jsonb_build_object('row', 'conversion', 'amount', round(conv_amt, 4), 'mode', mode_, 'complete', not cinc)),
    'raw_cost', case when complete then round(raw_t, 4) end, 'packaging_cost', case when complete then round(pack_t, 4) end, 'material_cost', case when complete then round(mat, 4) end,
    'conversion_cost', round(conv_amt, 4), 'conversion_mode', mode_, 'conversion_complete', not cinc, 'conversion_detail', conv->'detail', 'conversion_reason', conv->>'reason',
    'conversion_flag', case when cinc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'batch_cost', case when complete then round(mat + conv_amt, 4) end,
    'unit_cost', case when complete and yb > 0 then round((mat + conv_amt) / yb, 6) end, 'yield_base', yb,
    'approved', r.approved_at is not null, 'approval_warn', gate = 'warn',
    'today', jsonb_build_object('raw_cost', round(raw_d, 4), 'packaging_cost', round(pack_d, 4), 'material_cost', round(matd, 4), 'batch_cost', round(matd + conv_amt, 4),
      'unit_cost', case when yb > 0 then round((matd + conv_amt) / yb, 6) end, 'gap_pct', gap, 'gap_warn', thr is not null and gap is not null and abs(gap) > thr,
      'lines_without_purchase_price', fb, 'note', 'display only - never booked'));
end $function$
$f$; end if; end $p103$;

-- ---- public._ob_plan96(text,integer,text,date) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._ob_plan96(p_option text, p_loc integer, p_account text, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); vals jsonb := '{}'::jsonb; cov jsonb := '{}'::jsonb; unt numeric := 0; k text; v numeric; c numeric; amt jsonb := '{}'::jsonb; tot numeric := 0;
        lines jsonb := '[]'::jsonb; ctr bigint; ctr_code text; acc public.coa_accounts; d date; n_unc int; sw numeric; warns jsonb := '[]'::jsonb; prior boolean := false; cov_all numeric; val_all numeric; maxlid bigint; cov_ids bigint[];
begin
  if st is null then return jsonb_build_object('ok', false, 'error', 'data_needed'); end if;
  if p_option is null or p_option not in ('owner_capital', 'existing_account', 'skip', 'difference') then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;
  if p_loc is null and p_option <> 'difference' then return jsonb_build_object('ok', false, 'error', 'place_needed'); end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then return jsonb_build_object('ok', false, 'error', 'bad_location'); end if;
  prior := exists (select 1 from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc));
  -- bos103: a decision that is already applied answers already_applied only when no opening row is left that it did not cover; a cost supplied LATER to an opening row
  -- (or an opening entered after the decision) can be booked ONCE by one more decision of that place (the rows it covers are then frozen again); a company-wide decision is still refused
  if prior and (p_loc is null or not exists (select 1 from public._ob_rows96(p_loc) r where not r.nocost and not r.by_switch and not r.handled)) then
    return jsonb_build_object('ok', false, 'error', 'already_applied'); end if;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into vals from (select r.k, sum(r.val) s from public._ob_rows96(p_loc) r where not r.nocost and not r.by_switch and not r.handled group by r.k) x;
  select count(*) filter (where r.nocost and not r.by_switch and not r.handled), coalesce(sum(r.val) filter (where r.by_switch), 0) into n_unc, sw from public._ob_rows96(p_loc) r;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into cov from (select o.k, sum(o.amt) s from public._ob_cover96() o where p_loc is null or o.loc = p_loc group by o.k) x;
  select coalesce(sum(o.amt), 0) into unt from public._ob_cover96() o where o.loc is null;
  if p_option = 'difference' and p_loc is not null and unt > 0 then return jsonb_build_object('ok', false, 'error', 'untagged_opening_inventory'); end if;
  d := coalesce(p_date, st);
  if d < st then return jsonb_build_object('ok', false, 'error', 'before_start'); end if;
  if d > public._acct_today() + 1 then return jsonb_build_object('ok', false, 'error', 'bad_date'); end if;
  select coalesce(sum(value::numeric), 0) into val_all from jsonb_each_text(vals);
  select coalesce(sum(value::numeric), 0) into cov_all from jsonb_each_text(cov);
  if n_unc > 0 then warns := warns || to_jsonb('uncosted_openings'::text); end if;
  if prior then warns := warns || to_jsonb('followup'::text); end if;   -- bos103
  if public.rule_on('acct_stock_opening') then warns := warns || to_jsonb('switch_on'::text); end if;
  if p_option = 'skip' then
    if cov_all + unt < val_all then warns := warns || to_jsonb('skip_but_not_in_opening_journal'::text); end if;
  else
    if p_option = 'existing_account' and p_account is null then return jsonb_build_object('ok', false, 'error', 'account_needed'); end if;
    if p_account is not null then
      select * into acc from public.coa_accounts a where a.code = p_account and a.active and not a.is_group and a.type in ('equity', 'liability')
        and not exists (select 1 from public.acct_mappings m where m.account_id = a.id and m.key in ('inv_finished', 'inv_raw', 'inv_pack'));
      if not found then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
      ctr := acc.id; ctr_code := acc.code;
    elsif p_option <> 'existing_account' then
      select m.account_id, a.code into ctr, ctr_code from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = 'stock_opening_equity';
      if ctr is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:stock_opening_equity'); end if;
    end if;
    if p_option = 'owner_capital' and p_account is not null then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;   -- owner_capital always uses the stock_opening_equity mapping
    for k in select unnest(array['inv_finished', 'inv_raw', 'inv_pack']) loop
      v := coalesce((vals->>k)::numeric, 0); c := coalesce((cov->>k)::numeric, 0);
      if p_option = 'difference' and not prior then v := greatest(v - c, 0); end if;   -- bos103: a follow-up decision books only the rows the first one did not cover
      v := round(v, 2);
      if v > 0 then
        select a.id into maxlid from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
        if maxlid is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:' || k); end if;
        amt := amt || jsonb_build_object(k, v); tot := tot + v;
        lines := lines || jsonb_build_object('account_id', maxlid, 'debit', v, 'credit', 0, 'location_id', p_loc, 'memo', 'Opening stock');
      end if;
    end loop;
    if tot <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_to_post', 'detail', jsonb_build_object('uncosted_rows', n_unc, 'posted_by_switch', sw)); end if;
    lines := lines || jsonb_build_object('account_id', ctr, 'debit', 0, 'credit', tot, 'location_id', p_loc, 'memo', 'Opening stock counterpart');
    if public._acct_locked(d) then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
  end if;
  select coalesce(array_agg(r.lid order by r.lid) filter (where not r.handled and not r.by_switch and (p_option = 'skip' or not r.nocost)), '{}') into cov_ids from public._ob_rows96(p_loc) r;
  return jsonb_build_object('ok', true, 'option', p_option, 'location_id', p_loc, 'date', d, 'amount', tot, 'by_key', amt, 'counter_code', ctr_code, 'covered_ids_n', coalesce(array_length(cov_ids, 1), 0),
    'opening_value', val_all, 'already_in_opening_journal', cov_all, 'untagged_in_opening_journal', unt, 'uncosted_rows', n_unc, 'posted_by_switch', sw,
    'warnings', warns, 'covered_ids', cov_ids,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'location_id', p_loc)), '[]'::jsonb)
                from jsonb_array_elements(lines) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint),
    'post_lines', lines);
end $function$
$f$; end if; end $p103$;

-- ---- public.opening_stock_apply96(text,integer,text,date,text,uuid) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.opening_stock_apply96(p_option text, p_loc integer, p_account text DEFAULT NULL::text, p_date date DEFAULT NULL::date, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl jsonb; eid bigint; aid bigint; r public.opening_stock_actions96; staff text; nprev int; pa bigint; fl public.opening_stock_followups103;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into r from public.opening_stock_actions96 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'option', r.option, 'entry_id', r.entry_id); end if;
  select * into fl from public.opening_stock_followups103 where client_id = p_client;   -- bos103
  if found then return jsonb_build_object('dup', true, 'id', fl.id, 'option', fl.option, 'entry_id', fl.entry_id, 'followup', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('opening_stock96', 0));
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  select count(*), max(a.id) into nprev, pa from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc);   -- bos103: one decision per place stays; a later cost is booked by ONE follow-up record
  if nprev > 0 then nprev := nprev + (select count(*) from public.opening_stock_followups103 f where f.location_id is not distinct from p_loc); end if;
  if p_option <> 'skip' then
    eid := public._acct_write((pl->>'date')::date, p_loc, 'opening_stock96', 'loc:' || coalesce(p_loc::text, 'all') || case when nprev > 0 then ':f' || nprev::text else '' end, p_option,
             'Opening stock (' || p_option || ')' || coalesce(': ' || nullif(btrim(p_reason), ''), ''), null, pl->'post_lines', null, p_client, null);
  end if;
  if nprev > 0 then   -- bos103: follow-up decision for the opening rows the first decision did not cover
    insert into public.opening_stock_followups103 (action_id, location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
      values (pa, p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid,
              (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x), left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
    return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings', 'followup', true);
  end if;
  insert into public.opening_stock_actions96 (location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
    values (p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid, (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x),
            left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
  return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings');
end $function$
$f$; end if; end $p103$;

-- ---- public._setup_chk81(text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._setup_chk81(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  when 'flw_grn_double103' then   -- bos103: GRN is the stock source, the guard is off and posted bills add their own stock after the first GRN stock row: the same goods are counted twice
    ap := coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' and coalesce(public.rule_txt('purchase_grn_guard'), 'off') = 'off';
    if ap then
      select count(distinct l.ref_id) into n from public.stock_ledger l
        where l.reason = 'purchase_in' and l.ref_type = 'purchase' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
          and l.made_at >= (select min(g.made_at) from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null);
      select count(distinct g.ref_id) into tot from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null;
    end if;
  when 'flw_oo_flags' then
    select count(*) into n from public.online_order_flags where state = 'open';
    select count(*) into tot from public.online_order_flags;
  else
    return jsonb_build_object('n', null, 'total', null, 'applies', false, 'unknown_check', true);
  end case;
  return jsonb_build_object('n', n, 'total', tot, 'applies', ap);
end $function$
$f$; end if; end $p103$;

-- ---- public.setup_recommendations() ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommendations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out_ jsonb := '[]'::jsonb; d record; r public.rules; eff jsonb; st text; chosen boolean; iss jsonb; c record; cj jsonb;
        cnt_ok int := 0; cnt_rec int := 0; cnt_own int := 0; cnt_info int := 0; cnt_ni int := 0; ready boolean; rv jsonb;
begin
  if not public._setup_view81() then raise exception 'not allowed'; end if;
  for d in select * from public.setup_rec_defs81 where active order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    iss := '[]'::jsonb; ready := true;
    if not found then
      st := 'not_installed'; cnt_ni := cnt_ni + 1; eff := null; chosen := false;
    else
      eff := coalesce(r.value, r.default_value); chosen := r.value is not null;
      if rv is null then st := 'info'; cnt_info := cnt_info + 1;
      elsif eff is not distinct from rv then st := 'ok'; cnt_ok := cnt_ok + 1;
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
      'status', st, 'recommended', rv, 'current', eff, 'default', r.default_value, 'owner_chosen', chosen,
      'min', r.min_value, 'max', r.max_value, 'unit', r.unit, 'choices', r.choices,
      'ready', ready, 'ready_issues', iss,
      'rule_label_bn', r.label_bn, 'rule_label_mix', r.label_mix, 'rule_label_en', r.label_en,
      'reason_bn', d.reason_bn, 'reason_mix', coalesce(d.reason_mix, d.reason_bn), 'reason_en', d.reason_en, 'sort', d.sort);
  end loop;
  return jsonb_build_object('advisory', true, 'can_apply', public.is_owner(),
    'summary', jsonb_build_object('total', jsonb_array_length(out_), 'ok', cnt_ok, 'recommended', cnt_rec, 'owner_chosen', cnt_own, 'info', cnt_info, 'not_installed', cnt_ni),
    'items', out_);
end $function$
$f$; end if; end $p103$;

-- ---- public.setup_recommend_apply(uuid,text[],boolean,boolean) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommend_apply(p_client uuid, p_codes text[] DEFAULT NULL::text[], p_overwrite boolean DEFAULT false, p_ignore_ready boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean; rv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if rv is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from rv then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
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
      perform public.set_rule(d.rule_key, rv);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', rv, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $function$
$f$; end if; end $p103$;

-- ---- public._inb_pii_f99(text,text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._inb_pii_f99(p_field text, p_val text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := public._inb_pii_mode99(); hide boolean;
begin
  if mode_ = 'off' or p_val is null then return p_val; end if;
  if coalesce(current_setting('bos.inb_unmask99', true), '') = txid_current()::text then return p_val; end if;      -- inside inbox_unmask only
  hide := case p_field
    when 'mobile' then true
    when 'handle' then mode_ = 'mask_all_pii' or p_val ~ '^\+?[0-9][0-9 ()-]{5,}$'
    when 'address' then mode_ in ('mask_phone_address', 'mask_all_pii')
    else mode_ = 'mask_all_pii' end;
  return case when hide then public._inb_mask99(p_field, p_val)
              when p_field in ('text', 'name', 'address', 'attachment') then public._inb_mask_phones103(p_val)   -- bos103: a number typed inside free text is masked too
              else p_val end;
end $function$
$f$; end if; end $p103$;

-- ---- public._inb_pii_json99(jsonb) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._inb_pii_json99(j jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := public._inb_pii_mode99(); k text;
begin
  if mode_ = 'off' then return j; end if;
  if j ? 'customer_mobile' and jsonb_typeof(j->'customer_mobile') = 'string' then j := jsonb_set(j, '{customer_mobile}', to_jsonb(public._inb_pii_f99('mobile', j->>'customer_mobile'))); end if;
  if j ? 'address' and jsonb_typeof(j->'address') = 'string' then j := jsonb_set(j, '{address}', to_jsonb(public._inb_pii_f99('address', j->>'address'))); end if;
  if j ? 'customer_name' and jsonb_typeof(j->'customer_name') = 'string' then j := jsonb_set(j, '{customer_name}', to_jsonb(public._inb_pii_f99('name', j->>'customer_name'))); end if;
  for k in select unnest(array['note', 'draft_note', 'cancel_reason']) loop   -- bos103: free text of the order
    if j ? k and jsonb_typeof(j->k) = 'string' then j := jsonb_set(j, array[k], to_jsonb(public._inb_pii_f99('text', j->>k))); end if;
  end loop;
  return j || jsonb_build_object('pii_mode', mode_);
end $function$
$f$; end if; end $p103$;

-- ---- public.inbox_list(integer,text,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when public._inb_contact_ok(m.location_id) then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when public._inb_contact_ok(m.location_id) then left(public._inb_pii_f99('text', m.msg_text), 200) /* bos103: mask first, cut after */ end, 'masked', not public._inb_contact_ok(m.location_id), 'pii_mode', public._inb_pii_mode99()) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
$f$; end if; end $p103$;

-- ---- public.customer_directory(integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
 RETURNS TABLE(id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text, credit_limit numeric, customer_since date, balance numeric, spend numeric, orders integer, last_sale date, points integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return query
    with s as (select x.customer_id cid, sum(x.total) tot, count(*)::int n, max(x.sale_date) last_d from public.sales x
               where x.status = 'done' and x.customer_id is not null and public.can_loc(x.location_id) group by 1),
         r as (select y.customer_id cid, sum(y.amount) amt from public.sale_returns y join public.sales z on z.id = y.sale_id
               where y.status = 'done' and y.customer_id is not null and public.can_loc(z.location_id) group by 1),
         d as (select q.id cid, q.balance bal from public.customer_dues() q),
         p as (select l.customer_id cid, sum(l.delta)::int pts from public.customer_points_ledger l group by 1)
    select c.id, public._cust_pii103('mobile', c.mobile) /* bos103 */, c.name, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, public._cust_pii103('address', c.address), public._cust_pii103('mobile', c.whatsapp), public._cust_pii103('text', c.note), c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$
$f$; end if; end $p103$;

-- ---- public.find_customer(text) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.find_customer(p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text := public.norm_mobile(p_mobile); c public.customers;
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where mobile = m;
  if not found then return jsonb_build_object('mobile', m, 'found', false); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', public._cust_pii103('mobile', c.mobile) /* bos103 */, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit, 'balance', public.customer_balance(c.id));
end $function$
$f$; end if; end $p103$;

-- ---- public._ob_rows96(integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._ob_rows96(p_loc integer)
 RETURNS TABLE(lid bigint, loc integer, k text, val numeric, nocost boolean, by_switch boolean, handled boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.location_id, public._acct_inv_key(it.item_type), round(l.qty_delta * coalesce(l.unit_cost, 0), 2), coalesce(l.unit_cost, 0) = 0,
         exists (select 1 from public.journal_entries e where e.source_type = 'stock_opening' and e.source_id = l.id::text and e.reverses_id is null),
         exists (select 1 from public.opening_covered103 a where l.id = any (a.covered_ids)   /* bos103 */ and (a.location_id is null or a.location_id = l.location_id))
  from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id
  where l.reason = 'opening' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (p_loc is null or l.location_id = p_loc)
    and (l.made_at at time zone 'Asia/Dhaka')::date >= greatest(public._acct_start(), coalesce(public._acct_from85(), public._acct_start()));
$function$
$f$; end if; end $p103$;

-- ---- public.online_order_get(uuid) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := public._inb_pii_json99(j);                                                                               -- bos99
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$
$f$; end if; end $p103$;

-- ---- public.online_orders_list(integer,text,date,date,integer) ----
do $p103$ begin if current_setting('phase103.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, public._inb_pii_f99('name', o.customer_name) as customer_name,   -- bos99
           case when public._inb_contact_ok(o.location_id) then public._inb_pii_f99('mobile', o.customer_mobile) end as customer_mobile,   -- bos76 bos99
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked, public._inb_pii_mode99() as pii_mode,   -- bos76 bos99
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
$f$; end if; end $p103$;

-- ---------- marker: phase103 pasted (tests read this) ----------
do $g$ begin
  if current_setting('phase103.ok', true) = 'on' then
    raise notice 'phase103 applied (bos103)';
  else
    raise notice 'phase103 NOT applied: a guard stopped it';
  end if;
end $g$;

-- ---------------------------------------------------------------- phase104.sql
-- ============================================================
-- Phase 104 (bos104) - Owner dashboard (#/dashx): per-user dashboard layout (tile order, metric ids, chart types, sizes, period, location).
--   Needs phases 72..103 pasted first (guard below, incl. phase103's check row flw_grn_double103). Goes LAST.
--   Additive, paste-twice safe: one new table (dash_layouts, RLS: a user sees / writes ONLY their own row), two functions, one audit trigger.
--   No existing table, column, function or privilege is changed. The default layout lives in web/dashx.js (no server rule).
--   dash_layout_get()                    -> {layout, updated_at} of the caller (layout null when nothing saved yet)
--   dash_layout_save(p_layout, p_client) -> {ok, changed, updated_at}; saving the same layout again changes nothing and is not audited again (idempotent).
--   Tag: bos104.
-- ============================================================

do $g$ begin perform set_config('phase104.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  -- 98: the merged _acct_docs (bos98), or phase103 pasted before (bos103), or the phase515 merge (bos89)
  if to_regprocedure('public._acct_docs(date)') is null
     or (position('bos98' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0 and position('bos103' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0
         and position('bos89' in pg_get_functiondef(to_regprocedure('public._acct_docs(date)'))) = 0) then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.setup_check_defs81') is null or not exists (select 1 from public.setup_check_defs81 where code = 'flw_grn_double103') then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase104 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase104.ok', 'guard1', false);
end $g$;

do $p$ begin if current_setting('phase104.ok', true) = 'guard1' then
  create table if not exists public.dash_layouts (
    user_id uuid primary key references auth.users (id) on delete cascade,
    layout jsonb not null,
    client text,
    updated_at timestamptz not null default now(),
    constraint dash_layouts_obj_chk check (jsonb_typeof(layout) = 'object' and octet_length(layout::text) <= 65536)
  );
  alter table public.dash_layouts enable row level security;
  drop policy if exists dash_layouts_sel on public.dash_layouts;
  create policy dash_layouts_sel on public.dash_layouts for select to authenticated using (user_id = auth.uid());
  drop policy if exists dash_layouts_ins on public.dash_layouts;
  create policy dash_layouts_ins on public.dash_layouts for insert to authenticated with check (user_id = auth.uid());
  drop policy if exists dash_layouts_upd on public.dash_layouts;
  create policy dash_layouts_upd on public.dash_layouts for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
  revoke all on public.dash_layouts from public, anon, authenticated;
  grant select, insert, update on public.dash_layouts to authenticated;
  drop trigger if exists audit_dash_layouts on public.dash_layouts;
  create trigger audit_dash_layouts after insert or update on public.dash_layouts for each row execute function public.log_change('user_id');
end if; end $p$;

do $p$ begin if current_setting('phase104.ok', true) = 'guard1' then
  execute $f$
  create or replace function public.dash_layout_get() returns jsonb
  language plpgsql stable security definer set search_path = public as $b$
  declare r public.dash_layouts;
  begin   -- bos104
    if auth.uid() is null or not public.is_active() then raise exception 'not allowed'; end if;
    select * into r from public.dash_layouts where user_id = auth.uid();
    if not found then return jsonb_build_object('layout', null, 'updated_at', null); end if;
    return jsonb_build_object('layout', r.layout, 'updated_at', r.updated_at);
  end $b$ $f$;
  execute $f$
  create or replace function public.dash_layout_save(p_layout jsonb, p_client text default null) returns jsonb
  language plpgsql security definer set search_path = public as $b$
  declare r public.dash_layouts; t timestamptz;
  begin   -- bos104
    if auth.uid() is null or not public.is_active() then raise exception 'not allowed'; end if;
    if p_layout is null or jsonb_typeof(p_layout) <> 'object' then raise exception 'bad_layout'; end if;
    if octet_length(p_layout::text) > 65536 then raise exception 'layout_too_big'; end if;
    if p_layout ? 'tiles' and (jsonb_typeof(p_layout -> 'tiles') <> 'array' or jsonb_array_length(p_layout -> 'tiles') > 40) then raise exception 'bad_tiles'; end if;
    select * into r from public.dash_layouts where user_id = auth.uid() for update;
    if found then
      if r.layout = p_layout then return jsonb_build_object('ok', true, 'changed', false, 'updated_at', r.updated_at); end if;   -- the same layout again: nothing written, nothing audited
      update public.dash_layouts set layout = p_layout, client = left(p_client, 80), updated_at = now() where user_id = auth.uid() returning updated_at into t;
    else
      insert into public.dash_layouts (user_id, layout, client) values (auth.uid(), p_layout, left(p_client, 80)) on conflict (user_id) do update set layout = excluded.layout, client = excluded.client, updated_at = now() returning updated_at into t;
    end if;
    return jsonb_build_object('ok', true, 'changed', true, 'updated_at', t);
  end $b$ $f$;
  revoke all on function public.dash_layout_get() from public, anon;
  revoke all on function public.dash_layout_save(jsonb, text) from public, anon;
  grant execute on function public.dash_layout_get() to authenticated;
  grant execute on function public.dash_layout_save(jsonb, text) to authenticated;
end if; end $p$;

-- ============================================================================
-- End of FRESH part 9 of 21.
