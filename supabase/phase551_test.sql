-- Phase 551 tests (t3_payroll reads app payroll runs when report_salary_source = app_first or payroll_accrual_on). TEST DATABASE ONLY (local throwaway Postgres, chain pasted).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase551_test.sql | grep -E 'FAIL|RESULT551'
-- The number proof (two paid runs, net pay 9,613 shown by t3_payroll under app_first; paper-only under legacy) is the readiness scenario (R18b, R18c).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005511'
create schema if not exists t551;
create table if not exists t551.res (name text, ok boolean);
truncate t551.res;
create or replace function t551.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t551.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table t551_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
select t551.chk('T1 the report function carries the patch', (select pg_get_functiondef('public._r3q_t3_payroll(date,date,integer[],jsonb)'::regprocedure) like '%p551%'));
\i supabase/phase551.sql
select t551.chk('T2 a second paste changes no public function', (select count(*) = 0 from t551_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t551.chk('T3 no function added or dropped', (select count(*) from t551_before) = (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')));
select t551.chk('T4 the helper is closed to anon and authenticated', not has_function_privilege('anon', 'public._p551_app_salary()', 'execute') and not has_function_privilege('authenticated', 'public._p551_app_salary()', 'execute'));
select t551.chk('T5 default source is legacy, so the helper is false', public._p551_app_salary() = false);
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner551@test.invalid', '{"full_name":"test_owner551"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select t551.chk('T6 t3_payroll runs under legacy', jsonb_typeof(public.report_run2('t3_payroll', jsonb_build_object('from', date '2000-01-01', 'to', date '2000-01-31'), null, null, 1)->'rows') = 'array');
select public.set_rule('report_salary_source', '"app_first"'::jsonb);
select t551.chk('T7 the helper is true under app_first', public._p551_app_salary());
select t551.chk('T8 t3_payroll runs under app_first', jsonb_typeof(public.report_run2('t3_payroll', jsonb_build_object('from', date '2000-01-01', 'to', date '2000-01-31'), null, null, 1)->'rows') = 'array');
select t551.chk('RESULT551 passed ' || (select count(*) filter (where ok) from t551.res) || ' of ' || (select count(*) from t551.res), (select bool_and(ok) from t551.res));
