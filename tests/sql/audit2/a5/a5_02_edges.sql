-- A5 edge scenarios (run after a5_01_main.sql in the same session). Hand-computed expectations are in the comments / first argument.
\set o  '00000000-0000-0000-0000-000000000001'
\set fm '00000000-0000-0000-0000-000000000003'
\set ma '00000000-0000-0000-0000-000000000011'
\set mb '00000000-0000-0000-0000-000000000012'
\set mx '00000000-0000-0000-0000-000000000013'
\set ap '00000000-0000-0000-0000-000000000008'
\echo == E0 setup items Y (ladoo, 100 @ 50 at the factory)
select tt.as(:'o');
select stock_opening(tt.iid('A5-Y'),1,100,50) is not null as y0 \gset
\echo == E1 repeated partial receives: 20 sent, A receives 8, later 12 more. Business expectation: A=20 and nothing short. Code: first receive closes the transfer.
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('A5-Y'),20,null,'e1',gen_random_uuid())->>'id')::uuid as e1 \gset
select tt.as(:'ma');
select stock_receive_transfer(:'e1'::uuid, 8, 'first lorry') is not null as r1 \gset
select tt.eq('E1a A holds 8 after the first receive', 8, tt.qty('A5-Y',2));
select stock_receive_transfer(:'e1'::uuid, 12, 'second lorry')->>'dup' as r2 \gset
select tt.is('E1b second receive answers dup=true (ignored, no stock added)', 'true', :'r2');
select tt.eq('E1c EXPECTED A=20 once the remaining 12 arrive (partial receipts accumulate)', 20, tt.qty('A5-Y',2), 0.005, 'GAP-1: second receive silently ignored');
select tt.eq('E1d transfer row shows received_qty 8 (short 12 stays "short" for ever)', 8, (select received_qty from stock_transfers where id=:'e1'::uuid));
\echo == E2 receive without send / wrong place / cancel rights
select tt.err('E2a receive an id that was never sent', $$select stock_receive_transfer(gen_random_uuid(), 1)$$, 'not found');
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('A5-Y'),5,null,'e2',gen_random_uuid())->>'id')::uuid as e2 \gset
select tt.as(:'mx');
select tt.err('E2b branch-4 manager cannot receive goods meant for branch 2', format($$select stock_receive_transfer('%s'::uuid, 5)$$, :'e2'), 'not allowed');
select tt.as(:'ma');
select tt.err('E2c receiving branch cannot cancel the sender''s transfer', format($$select stock_cancel_transfer('%s'::uuid,'x')$$, :'e2'), 'not allowed');
select tt.as(:'fm');
select stock_cancel_transfer(:'e2'::uuid,'wrong branch')->>'status' as c2 \gset
select tt.is('E2d sender cancels while in transit', 'cancelled', :'c2');
select tt.as(:'ma');
select tt.err('E2e receive after cancel is refused', format($$select stock_receive_transfer('%s'::uuid, 5)$$, :'e2'), 'not_in_transit');
select tt.as(:'fm');
select tt.err('E2f cancel after receive is refused (e1 already received)', format($$select stock_cancel_transfer('%s'::uuid,'x')$$, :'e1'), 'not_in_transit');
\echo == E3 over-receive, negative, zero
select (stock_transfer(1,2,tt.iid('A5-Y'),10,null,'e3',gen_random_uuid())->>'id')::uuid as e3 \gset
select tt.as(:'ma');
select tt.err('E3a receive 11 of 10 sent', format($$select stock_receive_transfer('%s'::uuid, 11)$$, :'e3'), 'over_received');
select tt.err('E3b receive -1', format($$select stock_receive_transfer('%s'::uuid, -1)$$, :'e3'), 'bad_qty');
select stock_receive_transfer(:'e3'::uuid, 0, 'nothing came')->>'short' as z3 \gset
select tt.eq('E3c receive 0 is accepted: whole 10 short, transfer closed', 10, :'z3'::numeric);
\echo == E4 location access: outsider sends; send to a place the sender cannot see; send to a CLOSED place
select tt.as(:'mx');
select tt.err('E4a branch-4 manager sends FROM factory (no access to loc 1)', $$select stock_transfer(1,2,tt.iid('A5-Y'),1)$$, 'not allowed for this location');
select tt.as(:'fm');
select (stock_transfer(1,4,tt.iid('A5-Y'),2,null,'e4b',gen_random_uuid())->>'id') is not null as s4 \gset
select tt.t('E4b factory may send to loc 4 although fm has no access there (by design; receiver must be loc-4 staff)', :'s4'::boolean);
select tt.as(:'o');
update locations set status='closed', closed_reason='test' where id=5;
update locations set status='paused', paused_reason='test' where id=7;
select tt.as(:'fm');
select tt.err('E4c send to a CLOSED location is refused (trigger _loc_closed_guard)', $$select stock_transfer(1,5,tt.iid('A5-Y'),1,null,'to closed',gen_random_uuid())$$, 'location_paused');
select stock_transfer(1,7,tt.iid('A5-Y'),1,null,'to paused',gen_random_uuid()) is not null as s7 \gset
select tt.t('E4c2 send to a PAUSED location: EXPECTED refused or warned', not :'s7'::boolean, 'refused', case when :'s7'::boolean then 'accepted' else 'refused' end, 'paused godown 7');
select tt.err('E4d send to the same place', $$select stock_transfer(1,1,tt.iid('A5-Y'),1)$$, 'bad_location');
select tt.err('E4e send qty 0', $$select stock_transfer(1,2,tt.iid('A5-Y'),0)$$, 'bad_qty');
\echo == E5 duplicate client_id
select gen_random_uuid() as cid \gset
select stock_transfer(1,3,tt.iid('A5-Y'),1,null,'dup',:'cid'::uuid)->>'id' as d1 \gset
select stock_transfer(1,3,tt.iid('A5-Y'),1,null,'dup',:'cid'::uuid)->>'id' as d2 \gset
select tt.is('E5a same client id twice returns the same transfer id', :'d1', :'d2');
select tt.eq('E5b only one transfer row for that client id', 1, (select count(*) from stock_transfers where client_id=:'cid'::uuid));
select tt.as(:'o');
select stock_transfer(1,3,tt.iid('A5-Y'),1,null,'dup other user',:'cid'::uuid)->>'id' as d3 \gset
select tt.t('E5c another user replaying the same client id gets the first user''s transfer id back (no client_id_taken, unlike wastage)', :'d3' = :'d1', 'same id', case when :'d3' = :'d1' then 'same id' else 'different' end);
\echo == E6 sending more than the factory holds / selling at a branch whose goods are still in transit
select tt.as(:'fm');
select qty as fq from stock_balance where item_id=tt.iid('A5-Y') and location_id=1 \gset
select stock_transfer(1,3,tt.iid('A5-Y'),5000,null,'oversend',gen_random_uuid()) as big \gset
select tt.t('E6a send 5000 kg while the factory holds '||:'fq'||': EXPECTED refused', :'big' is null, 'refused', case when :'big' is null then 'refused' else 'accepted (factory now negative)' end, 'GAP-8 stock_negative_mode='||coalesce(rule_txt('stock_negative_mode'),'?'));
select tt.as(:'mb');
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":2,"price":300}]',tt.iid('A5-Y'))::jsonb,0,'[{"mode":"cash","amount":600}]',null,null,'retail',null,false) is not null as nsale \gset
select tt.t('E6b branch B sold 2 kg Y while B holds '||tt.qty('A5-Y',3)::text||' (goods in transit): EXPECTED refused', not :'nsale'::boolean, 'refused', case when :'nsale'::boolean then 'accepted (negative stock)' else 'refused' end, 'GAP-8');
select tt.as(:'o');
update locations set status='live', paused_reason=null where id=7;
\echo == E7 mode=loss: 10 sent, 7 received -> expected transit loss 3 x 50 = 150 booked ONCE, clearing nets to 0
select set_rule('transit_short_mode','"loss"') is null as m1 \gset
select tt.as(:'o'); select acct_post_pending(false) is not null as pp \gset
select tt.bal('5130') as l_before, tt.bal('1230') as c_before, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric as iv0 \gset
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('A5-Y'),10,null,'e7',gen_random_uuid())->>'id')::uuid as e7 \gset
select tt.as(:'ma'); select qty as aq0 from stock_balance where item_id=tt.iid('A5-Y') and location_id=2 \gset
select stock_receive_transfer(:'e7'::uuid, 7, 'short, mode loss') is not null as r7 \gset
select tt.eq('E7a A stock grew by 7 only', 7, tt.qty('A5-Y',2)-:'aq0'::numeric);
select tt.eq('E7b ledger has a transit_loss row of -3 at A', -3, (select coalesce(sum(qty_delta),0) from stock_ledger where ref_id=:'e7' and reason='transit_loss'));
select tt.as(:'o'); select acct_post_pending(false) as pp7 \gset
select tt.eq('E7c GL 5130 grew by 150 (3 x 50)', 150, tt.bal('5130')-:'l_before'::numeric);
select tt.eq('E7d clearing 1230 company-wide unchanged (nets 0)', 0, tt.bal('1230')-:'c_before'::numeric);
select tt.eq('E7e waiting cost_missing rows after posting (expect 0)', 0, coalesce((:'pp7'::jsonb->'waiting'->>'cost_missing')::int,0));
select tt.eq('E2g cancelled transfer e2 (out + reversal) nets to 0 on clearing 1230 in the GL', 0, (select coalesce(sum(l.debit-l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='stock_transfer' and a.code='1230' and e.source_id in (select id::text from stock_ledger where ref_type='transfer' and ref_id=:'e2')));
select tt.t('E2h the cancel produced GL entries (2 = out + reversal)', (select count(*) from journal_entries e where e.source_type='stock_transfer' and e.source_id in (select id::text from stock_ledger where ref_type='transfer' and ref_id=:'e2'))=2);
select tt.eq('E7f unbalanced entries', 0, tt.unbalanced());
select tt.eq('E7g inventory_vs_gl total diff CHANGE caused by a loss-mode short (expect 0; baseline '||:'iv0'||' is the unbooked Y opening)', 0, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric-:'iv0'::numeric);
select tt.eq('E7h inventory (finished goods) GL minus stock valuation, by place 2 (expect 0)', 0, (inventory_vs_gl(null,2)->'total'->>'diff')::numeric);
\echo == E8 mode=keep_in_transit then transit_short_resolve: booked once
select set_rule('transit_short_mode','"keep_in_transit"') is null as m2 \gset
select tt.as(:'fm');
select (stock_transfer(1,2,tt.iid('A5-Y'),10,null,'e8',gen_random_uuid())->>'id')::uuid as e8 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'e8'::uuid, 6, 'short 4') is not null as r8 \gset
select tt.as(:'o'); select acct_post_pending(false) as pp8 \gset
select tt.bal('5130') as l8a, tt.bal('1230') as c8a \gset
select tt.as(:'ma'); select transit_short_resolve(:'e8'::uuid, 'lost on the van')->>'short' as sr8 \gset
select tt.eq('E8a resolve returns short 4', 4, :'sr8'::numeric);
select tt.as(:'o'); select acct_post_pending(false) as pp8b \gset
select tt.eq('E8b 5130 unchanged by the resolve (already booked at receive: 4 x 50 = 200 once)', 0, tt.bal('5130')-:'l8a'::numeric);
select tt.eq('E8c clearing unchanged by the resolve', 0, tt.bal('1230')-:'c8a'::numeric);
select tt.eq('E8d transit_short_open no longer lists e8', 0, (select count(*) from jsonb_array_elements(transit_short_open(null)) x where x->>'transfer_id'=:'e8'));
select tt.eq('E8f inventory_vs_gl diff change since baseline after E7+E8 (expect 0; E7 phantom 150 + E8 phantom 200 = 350)', 0, (inventory_vs_gl(null,null)->'total'->>'diff')::numeric-:'iv0'::numeric);
select tt.eq('E8e waiting cost_missing after resolve (expect 0)', 0, coalesce((:'pp8b'::jsonb->'waiting'->>'cost_missing')::int,0));
\echo == E9 ageing of goods in transit
select set_rule('transit_open_hours','24') is null as h1 \gset
select tt.as(:'fm');
select (stock_transfer(1,3,tt.iid('A5-Y'),4,null,'e9',gen_random_uuid())->>'id')::uuid as e9 \gset
update stock_transfers set sent_at = now() - interval '30 hours' where id=:'e9'::uuid;
select tt.as(:'o');
select (x->>'hours')::numeric as hrs, (x->>'over_limit')::boolean as ovl from jsonb_array_elements(transit_open_list(null)->'rows') x where x->>'transfer_id'=:'e9' \gset
select tt.eq('E9a open list ageing hours = 30', 30, :'hrs'::numeric, 0.2);
select tt.t('E9b over_limit flag true', :'ovl'::boolean);
select count(*) as ua from jsonb_array_elements(urgent_alerts(now()-interval '1 hour')) x where x->>'kind'='transit_open' \gset
select tt.t('E9c urgent_alerts carries a transit_open item for the owner (count '||:'ua'||')', :'ua'::int >= 1);
select tt.as(:'mb');
select tt.t('E9d neither stock_transfer nor stock_receive_transfer calls _notif_add (the receiving branch is never told that goods are on the way)', (select bool_and(prosrc not like '%_notif_add%') from pg_proc where proname in ('stock_transfer','stock_receive_transfer')));
select tt.as(:'fm'); select stock_cancel_transfer(:'e9'::uuid,'test cleanup') is not null as c9 \gset
\echo == E10 cost drift: Z factory 20 @ 50, branch A 10 @ 80 ; send 10 to A -> A avg 65; A returns 4 -> factory avg (500+260)/14 = 54.2857
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('A5-Z','Z','Z','kg','kg','finished_good',true,100,true) on conflict do nothing;
select stock_opening(tt.iid('A5-Z'),1,20,50) is not null as z1 \gset
select stock_opening(tt.iid('A5-Z'),2,10,80) is not null as z2 \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('A5-Z'),10,null,'z',gen_random_uuid())->>'id')::uuid as zt \gset
select tt.as(:'ma'); select stock_receive_transfer(:'zt'::uuid) is not null as zr \gset
select tt.eq('E10a A blended avg after receiving 10 @50 onto 10 @80', 65, tt.avg('A5-Z',2), 0.001);
select (stock_transfer(2,1,tt.iid('A5-Z'),4,null,'z back',gen_random_uuid())->>'id')::uuid as zb \gset
select tt.as(:'fm'); select stock_receive_transfer(:'zb'::uuid) is not null as zbr \gset
select tt.eq('E10b factory avg after taking 4 back @65 onto 10 @50 (branch cost leaks into factory cost)', 54.2857, tt.avg('A5-Z',1), 0.001);
select tt.t('E10c there is no transfer-price / mark-up column anywhere (stock_transfers has no price column)', not exists (select 1 from information_schema.columns where table_name='stock_transfers' and column_name ~ 'price|markup|rate|cost'));
\echo == E11 batches and expiry travel with the goods; branch expiry write-off
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('A5-E','Rasgulla','Rasgulla','kg','kg','finished_good',true,200,true) on conflict do nothing;
insert into shelf_life_rules (item_id, value, unit) values (tt.iid('A5-E'), 48, 'hours');
select (recipe_save(null, tt.iid('A5-E'), 1, 'kg', 'e v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('A5-F'),'qty',1,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rce \gset
select tt.as(:'ap'); select recipe_approve(:'rce'::uuid,'ok') is not null as rape \gset
select tt.as(:'fm'); select production_post(1, :'rce'::uuid, 10, gen_random_uuid()) is not null as pe \gset
select (stock_transfer(1,2,tt.iid('A5-E'),10,null,'ex',gen_random_uuid())->>'id')::uuid as ex \gset
select tt.as(:'ma'); select stock_receive_transfer(:'ex'::uuid, 8, 'two missing') is not null as rex \gset
select tt.eq('E11a A holds 8 kg of E in ONE batch', 8, (select coalesce(sum(qty_remaining),0) from stock_batches where item_id=tt.iid('A5-E') and location_id=2));
select tt.t('E11b same expiry and made-at as the factory batch', (select count(*) from stock_batches a join stock_batches f on f.item_id=a.item_id and f.location_id=1 where a.item_id=tt.iid('A5-E') and a.location_id=2 and a.expires_at=f.expires_at and a.made_at=f.made_at)=1);
update stock_batches set expires_at = now() - interval '1 hour' where item_id=tt.iid('A5-E') and location_id=2;
select tt.eq('E11c expiry_list at A shows 1 expired batch of 8', 8, (select coalesce(sum(qty_remaining),0) from expiry_list(2, 0) where expired));
select stock_expire_batch((select batch_id from expiry_list(2,0) limit 1), 'expired', 'branch write-off') is not null as ew \gset
select tt.eq('E11d A stock of E after write-off = 0', 0, tt.qty('A5-E',2));
select tt.as(:'o'); select acct_post_pending(false) as pp11 \gset
select tt.eq('E11e GL wastage account 5100 at A includes 8 x 40 = 320 more (70 earlier + 320 = 390)', 390, tt.bal_loc('5100',2));
\echo == E12 form 03-1 (transfer challan) vs screen: default primary = screen, form is a reference
select tt.as(:'o');
select tt.is('E12-0 forms_post_to_ledger is OFF by default', 'false', rule_on('forms_post_to_ledger')::text);
select save_entry(null,'39-1',1,tt.today(),'{"from_loc":"1","to_loc":"2","ttype":"f2s","items":[{"item":"A5-Y","sent":"3"}]}','[]') ->> 'id' as f1 \gset
select submit_entry(:'f1'::uuid) is not null as fs \gset
select decide_entry(:'f1'::uuid, true, null, '{"items":[{"received":"3"}]}'::jsonb, '[]') ->> 'status' as fd \gset
select tt.is('E12a approved 03-1 with the switch OFF moves no stock (0 ledger posts)', '0', (select count(*) from entry_ledger_posts where entry_id=:'f1'::uuid)::text);
select set_rule('forms_post_to_ledger','true') is null as fp \gset
select tt.is('E12b with the switch ON the path_primary for stock_transfer flips to b (form posts)', 'b', path_primary('stock_transfer',1));
select count(*) as xs0 from exceptions where flag_code='transit_short' \gset
select qty as a_before from stock_balance where item_id=tt.iid('A5-Y') and location_id=2 \gset
select save_entry(null,'39-1',1,tt.today(),'{"from_loc":"1","to_loc":"2","ttype":"f2s","items":[{"item":"A5-Y","sent":"10"}]}','[]') ->> 'id' as f2 \gset
select submit_entry(:'f2'::uuid) is not null as fs2 \gset
select decide_entry(:'f2'::uuid, true, null, '{"items":[{"received":"7"}]}'::jsonb, '[]') ->> 'status' as fd2 \gset
select tt.eq('E12c form with sent 10 / received 7 puts +7 at A at once (one-step challan)', 7, (select qty from stock_balance where item_id=tt.iid('A5-Y') and location_id=2)-:'a_before'::numeric);
select tt.eq('E12d the form short (3) is listed by transit_short_open', 1, (select count(*) from jsonb_array_elements(transit_short_open(null)) x where (x->>'short')::numeric=3));
select tt.eq('E12e no yellow transit_short exception raised by the form path (screen path raises one)', 0, (select count(*) from exceptions where flag_code='transit_short')-:'xs0'::numeric);
select tt.eq('E12f an approved form is 2 taps apart from the receiver: receiver count is typed by the APPROVER, not by the branch (no receiver login needed)', 1, 1);
select set_rule('forms_post_to_ledger','false') is null as fp0 \gset
\echo == E13 reconcile + reports that exist
select tt.eq('E13a stock_reconcile finds 0 differences (ledger vs cache)', 0, (select count(*) from stock_reconcile(false)));
select report_run2('transfers_gap', jsonb_build_object('from', tt.today()::text, 'to', tt.today()::text)) as tg \gset
\echo TRANSFERS_GAP: :tg
select tt.t('E13b transfers_gap is an exception list only: columns have no sold / remaining / value', (:'tg'::jsonb->'columns')::text !~* 'sold|remain|value|aging|age');
select tt.t('E13c transfers_gap has no per-branch grouping (one row per transfer); totals keys = transfers/not_received/short_received', (:'tg'::jsonb->'totals') ?& array['transfers','not_received','short_received'] and not (:'tg'::jsonb->'totals') ? 'sold');
select string_agg(proname, ',') as stm from pg_proc where proname ~* '(branch|showroom).*(statement|recon|summary)|(factory|transfer).*(statement|recon|summary|ageing)' \gset
\echo STATEMENT_FUNCTIONS_FOUND: :stm
\echo == RESULT
select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from tt.ea \gset
\echo PASS=:pass FAIL=:fail
select step, expected, actual from tt.ea where not ok order by n;
