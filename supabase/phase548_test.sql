-- Phase 548 tests (stock_recon_period lists transit_loss). TEST DATABASE ONLY: local throwaway Postgres built through the paste chain (phase 548 is the last file).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase548_test.sql | grep -E 'FAIL|RESULT548'
-- The behaviour proof with real movements is the readiness scenario (tests/sql/readiness, check R17); this file checks the patch itself.
\set ON_ERROR_STOP off
\set o  '00000000-0000-0000-0000-000000005481'
create schema if not exists t548;
create table if not exists t548.res (name text, ok boolean);
truncate t548.res;
create or replace function t548.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t548.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
-- snapshot of every other function before a second paste
create temp table t548_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
select t548.chk('T1 stock_recon_period text carries transit_loss as a listed movement', (select pg_get_functiondef('public.stock_recon_period(date,date,integer,text[])'::regprocedure) like '%coalesce(a.transit_loss, 0) as listed%'));
\i supabase/phase548.sql
select t548.chk('T2 a second paste changes no public function at all', (select count(*) = 0 from t548_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t548.chk('T3 no function was added or dropped', (select count(*) from t548_before) = (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')));
select t548.chk('T4 anon cannot execute, authenticated can (unchanged grants)', not has_function_privilege('anon', 'public.stock_recon_period(date,date,integer,text[])', 'execute') and has_function_privilege('authenticated', 'public.stock_recon_period(date,date,integer,text[])', 'execute'));
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner548@test.invalid', '{"full_name":"test_owner548"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select t548.chk('T5 the function runs for the owner on a period with no movements and returns its rows array (row content is proven by readiness R17)', (select jsonb_typeof(public.stock_recon_period(date '2000-01-01', date '2000-01-02', null, null)->'rows') = 'array'));
select t548.chk('RESULT548 passed ' || (select count(*) filter (where ok) from t548.res) || ' of ' || (select count(*) from t548.res), (select bool_and(ok) from t548.res));
