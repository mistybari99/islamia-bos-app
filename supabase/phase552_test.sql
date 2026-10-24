-- Phase 552 tests (count-first by default; drawer expected cash from the POS). TEST DATABASE ONLY (local throwaway Postgres, chain pasted).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase552_test.sql | grep -E 'FAIL|RESULT552'
-- The number proof (maker sees no expected figure by default; POS expectation 2,350; pos_compare exception) is the readiness scenario (D1, D9).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005521'
create schema if not exists t552;
create table if not exists t552.res (name text, ok boolean);
truncate t552.res;
create or replace function t552.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t552.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table t552_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
create temp table t552_rules_before as select key, kind, value::text v, default_value::text d from public.rules where key not in ('blind_count_on', 'drawer_expected_source');
\i supabase/phase552.sql
select t552.chk('T1 a second paste changes no public function', (select count(*) = 0 from t552_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t552.chk('T2 only the intended functions were added', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p') and p.proname like '\_p552%') = 4);
select t552.chk('T3 blind_count_on default is true (owner decision 11 Oct), no value set', (select default_value = 'true'::jsonb and value is null from public.rules where key = 'blind_count_on'));
select t552.chk('T4 drawer_expected_source default typed, choices typed|pos_compare|pos', (select default_value = '"typed"'::jsonb and choices = '["typed","pos_compare","pos"]'::jsonb from public.rules where key = 'drawer_expected_source'));
select t552.chk('T5 no other rule changed', (select count(*) = 0 from t552_rules_before b join public.rules r using (key) where r.kind is distinct from b.kind or r.value::text is distinct from b.v or r.default_value::text is distinct from b.d));
select t552.chk('T6 helpers closed to anon and authenticated', not has_function_privilege('anon', 'public._p552_pos_cash(integer,date)', 'execute') and not has_function_privilege('authenticated', 'public._p552_expected(entries,text,jsonb,numeric)', 'execute'));
select t552.chk('T7 no POS activity gives null (typed figure is used)', public._p552_pos_cash(1, date '2000-01-01') is null);
select t552.chk('T8 typed mode returns the typed figure', public._p552_expected(null::public.entries, 'drawer', '{}'::jsonb, 123) = 123);
select t552.chk('T9 flags untouched in typed mode', public._p552_flags(null::public.entries, 1, '[]'::jsonb) = '[]'::jsonb);
select t552.chk('T10 blind_active is true for the cash and goods forms by default', public.blind_active('06-1', 1) and public.stock_blind_active('13-1', 1) and not public.blind_active('21-1', 1));
select t552.chk('RESULT552 passed ' || (select count(*) filter (where ok) from t552.res) || ' of ' || (select count(*) from t552.res), (select bool_and(ok) from t552.res));
