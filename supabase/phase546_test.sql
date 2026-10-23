-- Phase 546 tests (stock_transfer carries all four switch behaviours). TEST DATABASE ONLY: a local throwaway Postgres built from the paste chain through phase 545, fresh database, run ONCE.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase546_test.sql | grep -E 'FAIL|RESULT|FP546'
-- Two ways to run it:
--   WITH phase 546 (default): section F pastes phase 546 twice, sections C to E test each switch ON, the last line prints RESULT546.
--   BASELINE (-v nopaste=1) on the chain WITHOUT phase 546: only sections A and B run (every switch OFF) and the line FP546 is printed.
--   The FP546 line of both runs must be identical: with every switch OFF the new function behaves exactly like the phase 544 function.
-- Test data only: test_* identifiers, no person names. Numbers are hand-computed (comment above each block).
\set ON_ERROR_STOP off
\set o  '00000000-0000-0000-0000-000000005461'
\set k1 '00000000-0000-0000-0000-000000005462'
\set k2 '00000000-0000-0000-0000-000000005463'
create schema if not exists t546;
create table if not exists t546.res (name text, ok boolean);
truncate t546.res;
create or replace function t546.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t546.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t546.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- runs one transfer and returns its outcome as text: status / dup / error message (no ids, no times)
create or replace function t546.try(p_from int, p_to int, p_code text, p_qty numeric, p_client uuid default null) returns text language plpgsql as $$
declare r jsonb;
begin r := public.stock_transfer(p_from, p_to, (select id from public.items where code = p_code), p_qty, 'kg', 'test t546', p_client);
  return coalesce(r->>'status', '?') || case when coalesce((r->>'dup')::boolean, false) then ':dup' else '' end;
exception when others then return 'ERR:' || sqlerrm; end $$;
create or replace function t546.qty(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b where b.item_id = (select id from public.items where code = p_code) and b.location_id = p_loc), 0) $$;
grant usage on schema t546 to authenticated, anon; grant execute on all functions in schema t546 to authenticated, anon; grant select, insert on t546.res to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner546@test.invalid', '{"full_name":"test_owner546"}'), (:'k1', 'test_k1_546@test.invalid', '{"full_name":"test_k1_546"}'),
  (:'k2', 'test_k2_546@test.invalid', '{"full_name":"test_k2_546"}') on conflict do nothing;
update profiles set status = 'active' where id in (:'o', :'k1', :'k2');
insert into user_roles values (:'o', 'owner'), (:'k1', 'storekeeper'), (:'k2', 'storekeeper') on conflict do nothing;
insert into user_locations values (:'k1', 1), (:'k1', 2), (:'k2', 1), (:'k2', 2) on conflict do nothing;
select t546.as(:'o');
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, sellable)
  values ('test_t546_a', 'test t546 a', 'test t546 a', 'kg', 'kg', 'finished_good', true, 100, true),
         ('test_t546_b', 'test t546 b', 'test t546 b', 'kg', 'kg', 'finished_good', true, 100, true),
         ('test_t546_c', 'test t546 c', 'test t546 c', 'kg', 'kg', 'finished_good', true, 100, true),
         ('test_t546_d', 'test t546 d', 'test t546 d', 'kg', 'kg', 'finished_good', true, 100, true) on conflict do nothing;
-- opening stock at place 1: a = 20, b = 10, c = 10, d = 10
select stock_opening((select id from items where code = 'test_t546_a'), 1, 20, 50) is not null as s1 \gset
select stock_opening((select id from items where code = 'test_t546_b'), 1, 10, 50) is not null as s2 \gset
select stock_opening((select id from items where code = 'test_t546_c'), 1, 10, 50) is not null as s3 \gset
select stock_opening((select id from items where code = 'test_t546_d'), 1, 10, 50) is not null as s4 \gset

\echo == A shape: the five switches exist and are OFF
select t546.chk('A1 five transfer switches exist, kind switch, default off', (select count(*) = 5 and bool_and(kind = 'switch' and default_value = 'false'::jsonb) from rules where key in ('transfer_client_reuse_block', 'transfer_overdraw_block', 'transfer_paused_block', 'transfer_needs_stock', 'transfer_notify_receiver')));
select t546.chk('A2 all five are off now', not rule_on('transfer_client_reuse_block') and not rule_on('transfer_overdraw_block') and not rule_on('transfer_paused_block') and not rule_on('transfer_needs_stock') and not rule_on('transfer_notify_receiver'));

\echo == B every switch OFF: the scenario whose fingerprint must not change
-- k1 sends 5 of a (20 -> 15); k1 sends 30 of b (stock 10: goes to -20, stock from nothing, as today); k1 sends 1 of a to the paused place 5 (accepted, as today);
-- k1 sends 4 of c with client id Y, k2 reuses Y with 7 of c (answered dup, nothing moves: c stays 10 - 4 = 6); k1 replays Y (dup); bad destination, same place, zero qty
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_a', 5, '6f1c2b3a-0000-4000-8000-000000005460') as b1 \gset
select t546.try(1, 2, 'test_t546_b', 30) as b2 \gset
select t546.try(1, 5, 'test_t546_a', 1) as b3 \gset
select t546.try(1, 2, 'test_t546_c', 4, '6f1c2b3a-0000-4000-8000-000000005461') as b4 \gset
select t546.as(:'k2');
select t546.try(1, 2, 'test_t546_c', 7, '6f1c2b3a-0000-4000-8000-000000005461') as b5 \gset
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_c', 4, '6f1c2b3a-0000-4000-8000-000000005461') as b6 \gset
select t546.try(1, 99, 'test_t546_a', 1) as b7 \gset
select t546.try(1, 1, 'test_t546_a', 1) as b8 \gset
select t546.try(1, 2, 'test_t546_a', 0) as b9 \gset
select t546.chk('B1 plain send accepted', :'b1' = 'sent');
select t546.chk('B2 over-send accepted with every switch off (today)', :'b2' = 'sent' and t546.qty('test_t546_b', 1) = -20);
select t546.chk('B3 send to a paused place accepted (today)', :'b3' = 'sent');
select t546.chk('B4 reused id from another user answered dup, nothing moved (today)', :'b4' = 'sent' and :'b5' = 'sent:dup' and :'b6' = 'sent:dup' and t546.qty('test_t546_c', 1) = 6);
select t546.chk('B5 bad destination, same place and zero qty refused as before', :'b7' = 'ERR:bad_location' and :'b8' = 'ERR:bad_location' and :'b9' = 'ERR:bad_qty');
select t546.chk('B6 no transfer_sent notice with the switch off', not exists (select 1 from notifications where kind = 'transfer_sent'));
select 'FP546 ' || md5(concat_ws('|', :'b1', :'b2', :'b3', :'b4', :'b5', :'b6', :'b7', :'b8', :'b9',
  t546.qty('test_t546_a', 1), t546.qty('test_t546_b', 1), t546.qty('test_t546_c', 1), t546.qty('test_t546_a', 2), t546.qty('test_t546_b', 2), t546.qty('test_t546_c', 2), t546.qty('test_t546_a', 5),
  (select count(*) from stock_transfers where note = 'test t546'), (select coalesce(sum(qty), 0) from stock_transfers where note = 'test t546'),
  (select count(*) from notifications where kind = 'transfer_sent'))) as fp546;

\if :{?nopaste}
\echo == baseline run: sections C to F skipped
\else
\echo == F paste twice: the function text is the same after the second paste, the hooks are all there
\ir phase546.sql
select md5(pg_get_functiondef('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)'::regprocedure)) as h1 \gset
\ir phase546.sql
select md5(pg_get_functiondef('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)'::regprocedure)) as h2 \gset
select t546.chk('F1 second paste leaves the function unchanged', :'h1' = :'h2');
select t546.chk('F2 the function carries all five switches and both tags', (select position('transfer_client_reuse_block' in d) > 0 and position('transfer_paused_block' in d) > 0 and position('transfer_overdraw_block' in d) > 0
  and position('bos114:xfer-stock' in d) > 0 and position('bos115:xfer-notify' in d) > 0 and position('transfer_needs_stock' in d) > 0 and position('transfer_notify_receiver' in d) > 0
  from (select pg_get_functiondef('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)'::regprocedure) as d) z));
select t546.chk('F3 still five switches, all off, no new rule from phase 546', (select count(*) = 5 from rules where key in ('transfer_client_reuse_block', 'transfer_overdraw_block', 'transfer_paused_block', 'transfer_needs_stock', 'transfer_notify_receiver') and default_value = 'false'::jsonb)
  and not rule_on('transfer_needs_stock') and not rule_on('transfer_notify_receiver'));

\echo == C bos114 transfer_needs_stock ON (storekeeper has no sell_below_zero; the owner has)
-- item d: place 1 has 10. Sending 20 is refused (stock stays 10, no transfer row), sending exactly 10 is accepted (0), the owner may still go below zero (-5).
select t546.as(:'o');
select set_rule('transfer_needs_stock', 'true'::jsonb);
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_d', 20) as c1 \gset
select t546.chk('C1 ON: send of 20 from stock 10 refused with insufficient_stock', :'c1' = 'ERR:insufficient_stock');
select t546.chk('C2 ON: stock still 10 and no transfer row', t546.qty('test_t546_d', 1) = 10 and not exists (select 1 from stock_transfers where item_id = (select id from items where code = 'test_t546_d')));
select t546.try(1, 2, 'test_t546_d', 10) as c3 \gset
select t546.chk('C3 ON: send of exactly 10 accepted, stock 0', :'c3' = 'sent' and t546.qty('test_t546_d', 1) = 0);
select t546.as(:'o');
select t546.try(1, 2, 'test_t546_d', 5) as c4 \gset
select t546.chk('C4 ON: the owner (sell_below_zero) may still send 5 more, stock -5', :'c4' = 'sent' and t546.qty('test_t546_d', 1) = -5);
select set_rule('transfer_needs_stock', 'false'::jsonb);

\echo == D bos115 transfer_notify_receiver ON
select t546.as(:'o');
select set_rule('transfer_notify_receiver', 'true'::jsonb);
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_a', 2, '6f1c2b3a-0000-4000-8000-000000005464') as d1 \gset
select t546.chk('D1 ON: send accepted', :'d1' = 'sent');
select t546.chk('D2 ON: exactly one transfer_sent notice, for managers of place 2, level info, route stock', (select count(*) = 1 and bool_and(location_id = 2 and audience = 'manager' and level = 'info' and route = 'stock') from notifications where kind = 'transfer_sent'));
select t546.try(1, 2, 'test_t546_a', 2, '6f1c2b3a-0000-4000-8000-000000005464') as d3 \gset
select t546.chk('D3 ON: a replay of the same client id is a dup and makes no second notice', :'d3' = 'sent:dup' and (select count(*) = 1 from notifications where kind = 'transfer_sent'));
select t546.as(:'o');
select set_rule('transfer_notify_receiver', 'false'::jsonb);

\echo == E phase 544 and 499 switches ON
select t546.as(:'o');
select set_rule('transfer_client_reuse_block', 'true'::jsonb);
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_c', 1, '6f1c2b3a-0000-4000-8000-000000005465') as e1 \gset
select t546.as(:'k2');
select t546.try(1, 2, 'test_t546_c', 1, '6f1c2b3a-0000-4000-8000-000000005465') as e2 \gset
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_c', 1, '6f1c2b3a-0000-4000-8000-000000005465') as e3 \gset
select t546.chk('E1 reuse block ON: other user refused with client_id_reused, same user replay still dup', :'e1' = 'sent' and :'e2' = 'ERR:client_id_reused' and :'e3' = 'sent:dup');
select t546.as(:'o');
select set_rule('transfer_client_reuse_block', 'false'::jsonb);
select set_rule('transfer_paused_block', 'true'::jsonb);
select t546.as(:'k1');
select t546.try(1, 5, 'test_t546_a', 1) as e4 \gset
select t546.chk('E2 paused block ON: send to the paused place 5 refused with destination_paused', :'e4' = 'ERR:destination_paused');
select t546.as(:'o');
select set_rule('transfer_paused_block', 'false'::jsonb);
select set_rule('transfer_overdraw_block', 'true'::jsonb);
select t546.as(:'k1');
select t546.try(1, 2, 'test_t546_a', 500) as e5 \gset
select t546.chk('E3 overdraw block ON: send of 500 from a small stock refused with insufficient_stock', :'e5' = 'ERR:insufficient_stock');
select t546.as(:'o');
select set_rule('transfer_overdraw_block', 'false'::jsonb);
select t546.chk('E4 all five switches back to off', not rule_on('transfer_client_reuse_block') and not rule_on('transfer_overdraw_block') and not rule_on('transfer_paused_block') and not rule_on('transfer_needs_stock') and not rule_on('transfer_notify_receiver'));
select count(*) filter (where not ok) as failing, count(*) as checks from t546.res \gset
select 'RESULT546 failing=' || :'failing' || ' checks=' || :'checks';
\endif
