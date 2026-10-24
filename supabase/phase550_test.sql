-- Phase 550 tests (gross profit net of returns in the cost-join reports). TEST DATABASE ONLY: local throwaway Postgres built through the paste chain (phase 550 pasted).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase550_test.sql | grep -E 'FAIL|RESULT550'
-- The number proof (sales_summary gp 3,198.55 = 3,850 - 651.45 after a return; catalogue of 120 reports runs without error) is the readiness scenario (G3, R21).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005501'
create schema if not exists t550;
create table if not exists t550.res (name text, ok boolean);
truncate t550.res;
create or replace function t550.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t550.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table t550_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
select t550.chk('T1 the wrap carries the patch', (select pg_get_functiondef('public._rptb1_agg_wrap(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean,text,text)'::regprocedure) like '%p550%'));
\i supabase/phase550.sql
select t550.chk('T2 a second paste changes no public function', (select count(*) = 0 from t550_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t550.chk('T3 no function added or dropped', (select count(*) from t550_before) = (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')));
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner550@test.invalid', '{"full_name":"test_owner550"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select t550.chk('T4 sales_summary runs with the rule ON (default) on an empty period', jsonb_typeof(public.report_run('sales_summary', jsonb_build_object('from', date '2000-01-01', 'to', date '2000-01-02'), 'location', null, 1, false)->'rows') = 'array');
select public.set_rule('reports_net_of_returns', 'false'::jsonb);
select t550.chk('T5 sales_summary runs with the rule OFF', jsonb_typeof(public.report_run('sales_summary', jsonb_build_object('from', date '2000-01-01', 'to', date '2000-01-02'), 'location', null, 1, false)->'rows') = 'array');
select public.set_rule('reports_net_of_returns', 'true'::jsonb);
select t550.chk('RESULT550 passed ' || (select count(*) filter (where ok) from t550.res) || ' of ' || (select count(*) from t550.res), (select bool_and(ok) from t550.res));
