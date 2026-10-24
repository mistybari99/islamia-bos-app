-- Phase 549 tests (freight / transporter payable). TEST DATABASE ONLY: local throwaway Postgres built through the paste chain (phase 549 pasted).
--   cd <repo root>; psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase549_test.sql | grep -E 'FAIL|RESULT549'
-- The end-to-end proof (landed cost with a payable freight line, supplier_dues, pay_supplier, journal Dr 2150 / Cr cash, balance sheet) is the readiness scenario
-- (tests/sql/readiness: P2, P3, P3b, F2); this file checks the patch, the split and the unchanged ordinary path. Test data only: test_* identifiers.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000005491'
create schema if not exists t549;
create table if not exists t549.res (name text, ok boolean);
truncate t549.res;
create or replace function t549.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t549.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table t549_before as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p');
select t549.chk('T1 the patches are in place', (select bool_and(d like '%p549%' or d like '%_p549_pay_debits%' or d like '%_sup_balance_ord%') from (select pg_get_functiondef(x::regprocedure) d from unnest(array['public._sup_open(uuid)','public._sup_balance(uuid)','public.supplier_ledger(uuid,integer)','public._acct_docs(date)','public.acct_reconcile(text)']) x) q));
\i supabase/phase549.sql
select t549.chk('T2 a second paste changes no public function', (select count(*) = 0 from t549_before b join (select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind in ('f','p')) a using (sig) where a.h <> b.h));
select t549.chk('T3 helpers are closed to anon and authenticated', not has_function_privilege('anon', 'public._lc_open(uuid)', 'execute') and not has_function_privilege('authenticated', 'public._lc_open(uuid)', 'execute') and not has_function_privilege('anon', 'public._sup_balance_ord(uuid)', 'execute'));
select t549.chk('T4 debit lines: ordinary only', public._p549_pay_debits(100, 0, '00000000-0000-0000-0000-000000000001') = jsonb_build_array(jsonb_build_object('a','payable','d',100,'pt','supplier','pid','00000000-0000-0000-0000-000000000001')));
select t549.chk('T5 debit lines: split adds up to the payment', (select sum((x->>'d')::numeric) = 100 and count(*) = 2 from jsonb_array_elements(public._p549_pay_debits(100, 30, '00000000-0000-0000-0000-000000000001')) x));
select t549.chk('T6 debit lines: all landed gives one line on landed_payable', (select count(*) = 1 and bool_and(x->>'a' = 'landed_payable') from jsonb_array_elements(public._p549_pay_debits(100, 100, '00000000-0000-0000-0000-000000000001')) x));
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner549@test.invalid', '{"full_name":"test_owner549"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
insert into suppliers (id, name, opening_balance) values ('00000000-0000-0000-0000-000000005492', 'test_supplier549', 100) on conflict do nothing;
select t549.chk('T7 ordinary supplier: balance 100, nothing landed', public._sup_balance('00000000-0000-0000-0000-000000005492') = 100 and public._lc_open_total('00000000-0000-0000-0000-000000005492') = 0);
select public.pay_supplier('00000000-0000-0000-0000-000000005492', 1, '[{"mode":"cash","amount":40}]'::jsonb) as pr \gset
select t549.chk('T8 ordinary payment: balance 60, landed_part 0', (:'pr'::jsonb->>'balance')::numeric = 60 and (select landed_part from supplier_payments where supplier_id = '00000000-0000-0000-0000-000000005492') = 0);
select t549.chk('T9 supplier_dues shows 60 and the ledger has no landed row', (select balance from public.supplier_dues(null) where supplier_id = '00000000-0000-0000-0000-000000005492') = 60 and not exists (select 1 from public.supplier_ledger('00000000-0000-0000-0000-000000005492', null) where kind = 'landed'));
create or replace function t549.refused(p_sql text, p_msg text) returns boolean language plpgsql as $$ begin execute p_sql; return false; exception when others then return sqlerrm = p_msg; end $$;
select t549.chk('T10 overpaying is still refused', t549.refused($q$select public.pay_supplier('00000000-0000-0000-0000-000000005492', 1, '[{"mode":"cash","amount":61}]'::jsonb)$q$, 'overpaid'));
select t549.chk('RESULT549 passed ' || (select count(*) filter (where ok) from t549.res) || ' of ' || (select count(*) from t549.res), (select bool_and(ok) from t549.res));
