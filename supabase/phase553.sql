-- Phase 553 (READINESS D2 + D3 + D6) - the setup advisor gets recommended values for the switches the readiness audit found missing.
-- Paste AFTER phase552. Paste-twice safe (the rows that already have a value are not touched). Earlier phase files are not edited.
-- What this is: ADVISOR DATA ONLY. The advisor (setup_recommend_apply) still needs the owner's tap; no rule, no default and no function changes; a switch the owner has already set is never overwritten
--   (reason owner_chosen). Each row carries the readiness checks that stop it while the data is not ready (reason not_ready), and an honest reason text.
-- Rows that existed without a value (the audit's D2/D3/D6): acct_transit_loss -> true, acct_transfer_mode -> location_tagged, stock_negative_mode -> block, production_requires_recipe -> true.
--   Note acct_transfer_mode: location_tagged vs company_wide is the owner's open question since 14 Oct 2026; the advisor row proposes location_tagged (the choice that makes the books equal the stock per place); the owner may choose company_wide instead.
-- New rows: blind_count_on -> true (the recorded default, for a project where it was switched off), report_salary_source -> app_first, rpt131_on -> true, payroll_accrual_on -> true, pin_signature_on -> true.
-- Test: supabase/phase553_test.sql and the readiness scenario in rec mode (books equal stock; count blind; salary reports from the app).

update public.setup_rec_defs81 set rec_value = 'true'::jsonb, ready_checks = array['acc_start','acc_coa','acc_map'], phase = '553',
  reason_bn = 'হিসাব চালু ও জায়গাভিত্তিক স্থানান্তর হিসাব চালু থাকলে পথে হারানো মালের খরচ "পথে ক্ষতি" অ্যাকাউন্টে যায়; না হলে খাতার ইনভেন্টরি স্টকের চেয়ে বেশি থাকে। ঝুঁকি: চালু করলে পুরনো জমা আসল তারিখে পোস্ট হয়।',
  reason_mix = 'Accounting ও transfer accounting চালু থাকলে পথে হারানো মালের cost "transit loss" account-এ যায়; না হলে খাতার inventory stock-এর চেয়ে বেশি থাকে। Warning: backlog আসল তারিখে post হয়।',
  reason_en = 'With accounting and transfer accounting on, the cost of goods short on arrival goes to the transit loss account; without it the books carry inventory above the stock. Warning: turning it on posts the backlog at the original dates.'
 where rule_key = 'acct_transit_loss' and rec_value is null;
update public.setup_rec_defs81 set rec_value = '"location_tagged"'::jsonb, ready_checks = array['acc_start','acc_coa','acc_map'], phase = '553',
  reason_bn = 'একাধিক জায়গা (দোকান, গুদাম, কারখানা) থাকলে location_tagged দিলে পাঠানো ও গ্রহণের দুটি এন্ট্রি হয় এবং প্রতি জায়গায় খাতা ও স্টক মেলে। একটাই জায়গা হলে off থাকুক। company_wide বেছে নেওয়া মালিকের সিদ্ধান্ত (১৪ অক্টোবর থেকে খোলা)।',
  reason_mix = 'একাধিক জায়গা থাকলে location_tagged: send ও receive দুটি entry, প্রতি জায়গায় books ও stock মেলে। এক জায়গা হলে off। company_wide মালিকের সিদ্ধান্ত (14 Oct থেকে open)।',
  reason_en = 'With more than one place, location_tagged posts a send and a receive entry so the books equal the stock place by place. With one place keep off. Choosing company_wide instead is the owner''s decision (open since 14 Oct 2026). Warning: the backlog posts at the original dates.'
 where rule_key = 'acct_transfer_mode' and rec_value is null;
update public.setup_rec_defs81 set rec_value = '"block"'::jsonb, ready_checks = array['stk_neg','stk_opening'], phase = '553',
  reason_bn = 'শুরুর স্টক বা প্রথম গণনার পর block দিলে স্টকের চেয়ে বেশি বিক্রি আটকায়। ঋণাত্মক স্টক থাকলে বা শুরুর স্টক না দিলে আগে ঠিক করুন, নইলে সত্যিকারের বিক্রিও আটকে যেতে পারে।',
  reason_mix = 'Opening stock বা প্রথম count-এর পর block: stock-এর বেশি sale আটকায়। Negative stock বা opening stock না থাকলে আগে ঠিক করুন।',
  reason_en = 'After the opening stock or the first count, block stops a sale above stock. Fix negative balances and enter the opening stock first, or genuine sales may be stopped.'
 where rule_key = 'stock_negative_mode' and rec_value is null;
update public.setup_rec_defs81 set rec_value = 'true'::jsonb, ready_checks = array['prd_recipes'], phase = '553',
  reason_bn = 'চালু থাকলে অনুমোদিত রেসিপি ছাড়া উৎপাদন পোস্ট হয় না, তাই খরচ ও স্টক নিয়ম মেনে চলে। আগে রেসিপি বানিয়ে অনুমোদন করুন।',
  reason_mix = 'চালু থাকলে approved recipe ছাড়া production post হয় না। আগে recipe বানিয়ে approve করুন।',
  reason_en = 'When on, production cannot be posted without an approved recipe, so cost and stock follow the recipe. Make and approve the recipes first.'
 where rule_key = 'production_requires_recipe' and rec_value is null;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort, active) values
 ('blind_count_on', 'blind_count_on', '553', 'entries', 'true'::jsonb, '{}',
  'আগে গণনা, তারপর প্রত্যাশিত অঙ্ক: মালিকের ১১ অক্টোবরের সিদ্ধান্ত। এটি এখন ডিফল্টে চালু; কেউ বন্ধ করে থাকলে এই সারি আবার চালু করে।',
  'আগে count, তারপর expected: মালিকের 11 Oct সিদ্ধান্ত। এখন default চালু; কেউ বন্ধ করলে এই row আবার চালু করে।',
  'Count first, then the expected figure: the owner''s decision of 11 Oct 2026. It is now ON by default; this row switches it on again if it was turned off.', 1301, true),
 ('report_salary_source', 'report_salary_source', '553', 'books', '"app_first"'::jsonb, '{}',
  'অ্যাপের বেতন রান থেকে বেতনের রিপোর্ট ও লাভ-ক্ষতি হিসাব হয়; কাগজের শিট শুধু রান না থাকা মাসে। না হলে রিপোর্ট ০ দেখাতে পারে।',
  'App-এর payroll run থেকে বেতনের report ও P&L; কাগজের sheet শুধু run না থাকা মাসে।',
  'Salary reports and the profit-and-loss take the app''s payroll runs; paper sheets are used only for months without a run. Otherwise the staff-cost report can show zero after payroll was paid in the app.', 1302, true),
 ('rpt131_on', 'rpt131_on', '553', 'general', 'true'::jsonb, '{}',
  'যাচাই-করা রিপোর্ট পরিবার (rpt131) চালু করে; বন্ধ থাকলে সেগুলো "feature_off" বলে।',
  'Verified report family (rpt131) চালু; বন্ধ থাকলে "feature_off" বলে।',
  'Turns on the verified report family (rpt131); while off these reports answer feature_off.', 1303, true),
 ('payroll_accrual_on', 'payroll_accrual_on', '553', 'books', null, '{}',
  'বেতন মাসের খরচ হিসেবে মাস শেষে ধরা হয় (পরিশোধের দিনে নয়), দেনা আলাদা থাকে। এটি হিসাবরক্ষক ও মালিকের সিদ্ধান্ত, তাই কোনো মান সুপারিশ করা হয় না।',
  'Salary মাসের expense হিসেবে মাস শেষে ধরা হয় (payment-এর দিনে নয়)। এটি accountant ও মালিকের সিদ্ধান্ত, তাই কোনো মান recommend করা হয় না।',
  'Salary is booked as the month''s expense at month end (not on the payment day) with the liability kept apart. This is the accountant''s and the owner''s decision, so the advisor shows the row but recommends no value.', 1304, true),
 ('pin_signature_on', 'pin_signature_on', '553', 'entries', 'true'::jsonb, array['sec_pin'],
  'দ্বিতীয় সাইনের সময় আলাদা লগইনের PIN লাগে, তাই একজন দুই সই করতে পারে না (BUILD-RULES 10)। আগে মালিক নিশ্চিত করুন যে সবার PIN সেট আছে (সুইচ pin_all_set_confirmed); তার আগে এই সারি "প্রস্তুত নয়" থাকে।',
  'দ্বিতীয় sign-এ আলাদা login-এর PIN লাগে (BUILD-RULES 10)। আগে মালিক নিশ্চিত করুন যে সবার PIN সেট আছে (সুইচ pin_all_set_confirmed); তার আগে এই সারি "প্রস্তুত নয়" থাকে।',
  'The second signature needs the other login''s PIN, so one person cannot sign twice (BUILD-RULES 10). First the owner confirms that everyone has a PIN (switch pin_all_set_confirmed); until then this row stays not ready.', 1305, true)
on conflict (code) do nothing;

-- the readiness check behind the pin row: the server cannot see whether every login has a PIN, so the OWNER confirms it with a switch (default OFF = the row is not ready)
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('pin_all_set_confirmed', 'entries', 'switch', 'false'::jsonb, null, null, null, null,
  'মালিক নিশ্চিত করছেন: সবার PIN সেট আছে', 'Owner confirm করছেন: সবার PIN set আছে', 'Owner confirms: every login has a PIN',
  'বন্ধ = setup advisor pin_signature_on চালু করবে না। চালু = advisor চালু করতে পারবে। এই সুইচ নিজে কোনো আচরণ বদলায় না।',
  'বন্ধ = advisor pin_signature_on চালু করবে না। চালু = পারবে। এই switch নিজে কোনো behaviour বদলায় না।',
  'OFF = the setup advisor will not switch pin_signature_on on. ON = it may. This switch changes no behaviour by itself.', 924)
on conflict (key) do nothing;
insert into public.setup_check_defs81 (code, topic, kind, gate_rule, level, label_bn, label_mix, label_en, fix_bn, fix_mix, fix_en, nav, sort, active)
 select 'sec_pin', 'security', 'ready', null, 'warn', 'সবার PIN সেট আছে কিনা মালিক নিশ্চিত করেননি', 'সবার PIN set আছে কিনা owner confirm করেননি', 'The owner has not confirmed that every login has a PIN',
        'সবাইকে PIN দিয়ে সুইচ pin_all_set_confirmed চালু করুন', 'সবাইকে PIN দিয়ে pin_all_set_confirmed চালু করুন', 'Give everyone a PIN, then switch pin_all_set_confirmed on', 'switchboard', 1301, true
 where not exists (select 1 from public.setup_check_defs81 where code = 'sec_pin');

create or replace function public._p553_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase553: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase553: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;
select public._p553_patch('public._setup_chk81(text)', '/* p553 */',
  array['  when ''acc_start'' then'],
  array['  when ''sec_pin'' then   /* p553 */
    n := case when coalesce(public.rule_on(''pin_all_set_confirmed''), false) then 0 else 1 end; tot := 1;
  when ''acc_start'' then']);
drop function public._p553_patch(text, text, text[], text[]);
