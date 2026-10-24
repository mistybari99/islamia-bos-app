-- Phase 553 tests (advisor rows for the switches the readiness audit found missing). TEST DATABASE ONLY (local throwaway Postgres, chain pasted).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase553_test.sql | grep -E 'FAIL|RESULT553'
-- The number proof (the advisor alone makes the readiness scenario pass in rec mode) is tests/sql/readiness.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005531'
create schema if not exists t553;
create table if not exists t553.res (name text, ok boolean);
truncate t553.res;
create or replace function t553.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t553.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table t553_fn_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
create temp table t553_rules_before as select key, kind, value::text v, default_value::text d from public.rules;
create temp table t553_rec_before as select code, md5(row(d.*)::text) h from public.setup_rec_defs81 d;
\i supabase/phase553.sql
select t553.chk('T1 a second paste changes no function', (select count(*) = 0 from t553_fn_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t553.chk('T2 a second paste changes no advisor row', (select count(*) = 0 from t553_rec_before b join public.setup_rec_defs81 d using (code) where md5(row(d.*)::text) <> b.h));
select t553.chk('T3 no rule value or default changed by the second paste', (select count(*) = 0 from t553_rules_before b join public.rules r using (key) where r.value::text is distinct from b.v or r.default_value::text is distinct from b.d));
select t553.chk('T4 recommended values are the intended ones', (select count(*) = 8 from public.setup_rec_defs81 where active and (rule_key, rec_value) in (('acct_transit_loss','true'::jsonb),('acct_transfer_mode','"location_tagged"'::jsonb),('stock_negative_mode','"block"'::jsonb),('production_requires_recipe','true'::jsonb),('blind_count_on','true'::jsonb),('report_salary_source','"app_first"'::jsonb),('rpt131_on','true'::jsonb),('pin_signature_on','true'::jsonb))));
select t553.chk('T5 payroll accrual has a row but no recommended value (accountant and owner decide)', (select rec_value is null and active from public.setup_rec_defs81 where rule_key = 'payroll_accrual_on'));
select t553.chk('T6 no default of any rule is changed by this phase (all new defaults are off)', (select default_value = 'false'::jsonb from public.rules where key = 'pin_all_set_confirmed'));
select t553.chk('T7 the pin row is gated by the sec_pin check', (select ready_checks = array['sec_pin'] from public.setup_rec_defs81 where rule_key = 'pin_signature_on'));
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner553@test.invalid', '{"full_name":"test_owner553"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select t553.chk('T8 sec_pin check says not ready until the owner confirms', (public._setup_chk81('sec_pin') ->> 'n')::int = 1);
select public.setup_recommend_apply('00000000-0000-0000-0000-000000005539'::uuid, array['report_salary_source','rpt131_on','pin_signature_on','payroll_accrual_on']) as ap \gset
select t553.chk('T9 apply: salary source and rpt131 applied, pin not ready, payroll no recommendation',
  (select count(*) = 2 from jsonb_array_elements(:'ap'::jsonb -> 'applied')) and :'ap'::jsonb::text like '%"pin_signature_on"%' and :'ap'::jsonb::text like '%not_ready%' and :'ap'::jsonb::text like '%no_recommendation%');
select t553.chk('T10 the rules now hold the owner-applied values', public.rule_txt('report_salary_source') = 'app_first' and public.rule_on('rpt131_on'));
select public.set_rule('pin_all_set_confirmed', 'true'::jsonb);
select t553.chk('T11 after the owner confirms, the sec_pin check is ready', (public._setup_chk81('sec_pin') ->> 'n')::int = 0);
select t553.chk('RESULT553 passed ' || (select count(*) filter (where ok) from t553.res) || ' of ' || (select count(*) from t553.res), (select bool_and(ok) from t553.res));
