-- Phase 547 tests (backup coverage: AI tables, staff manifest, bucket list). TEST DATABASE ONLY: local throwaway Postgres built through the paste chain, phase 547 pasted.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase547_test.sql | grep -E 'FAIL|RESULT547'
-- Test data only: test_* identifiers.
\set ON_ERROR_STOP off
\set o  '00000000-0000-0000-0000-000000005471'
\set b  '00000000-0000-0000-0000-000000005472'
\set k  '00000000-0000-0000-0000-000000005473'
create schema if not exists t547;
create table if not exists t547.res (name text, ok boolean);
truncate t547.res;
create or replace function t547.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t547.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t547.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function t547.refused(p_sql text) returns boolean language plpgsql as $$
begin execute p_sql; return false; exception when others then return sqlerrm = 'not allowed'; end $$;
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner547@test.invalid', '{"full_name":"test_owner547"}'),
  (:'b', 'test_bot547@test.invalid', '{}'), (:'k', 'test_clerk547@test.invalid', '{"full_name":"test_clerk547"}') on conflict do nothing;
update profiles set status = 'active' where id in (:'o', :'k');
insert into user_roles values (:'o', 'owner'), (:'k', 'storekeeper') on conflict do nothing;
insert into user_locations values (:'k', 1) on conflict do nothing;
select t547.as(:'o');
select public.ops_account_set(:'b', 'backup', true);
select t547.chk('A1 ai_agents and ai_providers are in the backup list', 'ai_agents' = any (public._backup_tables()) and 'ai_providers' = any (public._backup_tables()));
select t547.chk('A2 secret tables stay out', not ('telegram_secrets' = any (public._backup_tables())) and not ('attendance_devices' = any (public._backup_tables())) and not ('ops_accounts' = any (public._backup_tables())));
select t547.chk('A3 both rules exist and are OFF', (select count(*) from public.rules where key in ('backup_accounts_on', 'backup_buckets_on') and default_value = 'false'::jsonb) = 2 and not public.rule_on('backup_accounts_on') and not public.rule_on('backup_buckets_on'));
select t547.chk('A4 _union_audit still says merged for _backup_tables', (select count(*) from public._union_audit() where fn = 'public._backup_tables()' and state = 'merged') = 1);
-- B: manifest
select t547.as(:'k');
select t547.chk('B1 a normal user is refused', t547.refused('select public.backup_accounts_manifest()'));
select t547.as(:'o');
select t547.chk('B2 the owner is refused (bot only)', t547.refused('select public.backup_accounts_manifest()'));
select t547.as(:'b');
select t547.chk('B3 rule OFF: answers enabled=false and nothing else', (select public.backup_accounts_manifest()) = jsonb_build_object('enabled', false, 'note', 'rule backup_accounts_on is OFF'));
select t547.as(:'o');
select public.set_rule('backup_accounts_on', 'true'::jsonb);
select t547.as(:'b');
create temp table m547 as select public.backup_accounts_manifest() j;
select t547.chk('B4 rule ON: enabled and one entry per profile', (select (j->>'enabled')::boolean and (j->>'logins')::int = (select count(*) from public.profiles) from m547));
select t547.chk('B5 the clerk has staff id, e-mail, role and location', (select exists (select 1 from jsonb_array_elements(j->'accounts') a where a->>'id' = :'k' and a->>'email' = 'test_clerk547@test.invalid'
   and a->'roles' = '["storekeeper"]'::jsonb and a->'locations' = '[1]'::jsonb and a->>'staff_id' = 'test_clerk547') from m547));
select t547.chk('B6 the bot is marked with its purpose', (select exists (select 1 from jsonb_array_elements(j->'accounts') a where a->>'id' = :'b' and a->'bot_purposes' = '["backup"]'::jsonb) from m547));
select t547.chk('B7 no password / hash / token / secret key anywhere in the answer', (select (j->'accounts')::text || (j->'attendance_devices')::text !~* '(password|pin_hash|token_hash|encrypted|secret|token)' from m547));
select t547.chk('B8 the never_included list is present', (select j->'never_included' @> '"passwords"'::jsonb from m547));
-- C: buckets
select t547.chk('C1 backup_storage_buckets lists photos as readable', (select exists (select 1 from jsonb_array_elements(public.backup_storage_buckets()->'buckets') x where x->>'id' = 'photos' and (x->>'bot_can_read')::boolean)));
select t547.chk('C2 payproof not readable while the rule is OFF', (select exists (select 1 from jsonb_array_elements(public.backup_storage_buckets()->'buckets') x where x->>'id' = 'payproof' and not (x->>'bot_can_read')::boolean)));
select t547.as(:'k');
select t547.chk('C3 a normal user cannot list buckets', t547.refused('select public.backup_storage_buckets()'));
select t547.chk('RESULT547 passed ' || (select count(*) filter (where ok) from t547.res) || ' of ' || (select count(*) from t547.res), (select bool_and(ok) from t547.res));
