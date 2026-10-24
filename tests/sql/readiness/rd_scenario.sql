-- READINESS SCENARIO (docs/READINESS_99.md part B). One scripted sweet-shop month-slice with neutral test_* data.
-- usage: bash tests/sql/readiness/run.sh <def|rec|recx> <dbname>   (def = default settings, rec = setup advisor "recommended values" applied, recx = rec plus the extra switches named in section D of the doc)
-- Local throwaway Postgres only. Every expected number below is derived from the inputs in this file by plain arithmetic, never from a system function.
\set ON_ERROR_STOP off
\set QUIET on
\set o  '00000000-0000-0000-0000-0000000000a1'
\set ap '00000000-0000-0000-0000-0000000000a2'
\set sp '00000000-0000-0000-0000-0000000000a3'
\set sp3 '00000000-0000-0000-0000-0000000000a4'
\set bu '00000000-0000-0000-0000-0000000000a5'
\set fm '00000000-0000-0000-0000-0000000000a6'
\set sm '00000000-0000-0000-0000-0000000000a7'
create schema if not exists tt;
drop table if exists tt.ea; create table tt.ea (n serial, step text, expected text, actual text, ok boolean, note text);
create or replace function tt.as(p_sub text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.eq(p_step text, p_exp numeric, p_act numeric, p_tol numeric default 0.005, p_note text default null) returns void language plpgsql as $$
declare ok boolean := p_act is not null and p_exp is not null and abs(p_exp - p_act) <= p_tol;
begin insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp::text, p_act::text, ok, p_note); raise notice '% % exp=% act=%', case when ok then 'PASS' else 'FAIL' end, p_step, p_exp, p_act; end $$;
create or replace function tt.is(p_step text, p_exp text, p_act text, p_note text default null) returns void language plpgsql as $$
declare ok boolean := p_exp is not distinct from p_act;
begin insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp, p_act, ok, p_note); raise notice '% % exp=% act=%', case when ok then 'PASS' else 'FAIL' end, p_step, p_exp, p_act; end $$;
create or replace function tt.t(p_step text, p_ok boolean, p_exp text default 'true', p_act text default null, p_note text default null) returns void language plpgsql as $$
begin insert into tt.ea (step, expected, actual, ok, note) values (p_step, p_exp, coalesce(p_act, coalesce(p_ok,false)::text), coalesce(p_ok,false), p_note); raise notice '% % %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_step, coalesce(p_act,''); end $$;
create or replace function tt.err(p_step text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; insert into tt.ea (step, expected, actual, ok) values (p_step, 'error '||p_msg, 'NO ERROR', false); raise notice 'FAIL % (no error)', p_step;
exception when others then
  insert into tt.ea (step, expected, actual, ok) values (p_step, 'error '||p_msg, left(sqlerrm,90), sqlerrm like '%'||p_msg||'%'); raise notice '% % (%)', case when sqlerrm like '%'||p_msg||'%' then 'PASS' else 'FAIL' end, p_step, left(sqlerrm,60); end $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$ select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.bal(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.bal_loc(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code and l.location_id = p_loc $$;
create or replace function tt.qty(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b join public.items i on i.id=b.item_id where i.code=p_code and b.location_id=p_loc),0) $$;
create or replace function tt.avg(p_code text, p_loc int) returns numeric language sql stable as $$
  select (select b.avg_cost from public.stock_balance b join public.items i on i.id=b.item_id where i.code=p_code and b.location_id=p_loc) $$;
create or replace function tt.val(p_code text, p_loc int) returns numeric language sql stable as $$
  select coalesce((select b.qty*coalesce(b.avg_cost,0) from public.stock_balance b join public.items i on i.id=b.item_id where i.code=p_code and b.location_id=p_loc),0) $$;
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code=p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on all tables in schema tt to authenticated, anon; grant usage on all sequences in schema tt to authenticated, anon;

\echo == mode = :mode
\echo == S0 setup: users, items, accounting start, opening journal
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@rd.test','{"full_name":"test_owner"}'),(:'ap','approver@rd.test','{"full_name":"test_approver"}'),(:'sp','seller1@rd.test','{"full_name":"test_seller_a"}'),
 (:'sp3','seller3@rd.test','{"full_name":"test_seller_b"}'),(:'bu','buyer@rd.test','{"full_name":"test_buyer"}'),(:'fm','maker@rd.test','{"full_name":"test_maker"}'),(:'sm','manager@rd.test','{"full_name":"test_showroom_manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver'),(:'sp','salesperson'),(:'sp3','salesperson'),(:'bu','purchasing'),(:'fm','factory_incharge'),(:'sm','showroom_manager') on conflict do nothing;
insert into user_locations values (:'bu',6),(:'fm',6),(:'sp',1),(:'sp3',3),(:'ap',6),(:'sm',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'fm'::uuid,'view_cost') is null as g1 \gset
-- items. Raw: flour, sugar (kg), box (pc). Made: sweet A (400/kg), sweet B (500/kg). VAT status true on all (test value; the rate itself is a test number set below).
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,vat_applicable) values
 ('test_flour','test_flour','test_flour','kg','kg','raw_material',true,0,false,true),
 ('test_sugar','test_sugar','test_sugar','kg','kg','raw_material',true,0,false,true),
 ('test_box','test_box','test_box','pc','pc','packaging',true,0,false,true),
 ('test_sweet_a','test_sweet_a','test_sweet_a','kg','kg','finished_good',true,400,true,true),
 ('test_sweet_b','test_sweet_b','test_sweet_b','kg','kg','finished_good',true,500,true,true) on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
-- opening journal: cash in showroom 1 = 20000, bank = 100000, owner capital = 120000. No opening stock (all stock comes from purchases below).
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"1120","debit":100000},{"code":"3100","credit":120000}]'::jsonb)->>'id' as oj \gset
select tt.t('S0 opening journal posted', :'oj' is not null);

\echo == S1 settings (mode switch)
select :'mode' in ('rec','recx') as isrec \gset
select :'mode'='recx' as isrecx \gset
\if :isrec
select setup_recommend_apply('aaaaaaaa-0000-0000-0000-00000000a001'::uuid) as ap1 \gset
select setup_recommend_apply('aaaaaaaa-0000-0000-0000-00000000a002'::uuid) as ap2 \gset
select (:'ap1'::jsonb->>'count')||' + '||(:'ap2'::jsonb->>'count') as nrec \gset
\echo RECOMMENDED_APPLIED_COUNT: :nrec
select string_agg(x->>'code'||':'||(x->>'reason'), ', ') as sk2 from jsonb_array_elements(:'ap2'::jsonb->'skipped') x where x->>'reason' not in ('already','no_recommendation') \gset
\echo RECOMMENDED_SKIPPED: :sk2
\endif
\if :isrecx
-- recx = the advisor's recommended values PLUS the extra switches this audit found missing from the advisor (docs/READINESS_99.md section D)
select set_rule('acct_transfer_mode','"location_tagged"') is null as x1 \gset
select set_rule('acct_transit_loss','true') is null as x2 \gset
select set_rule('blind_count_on','true') is null as x3 \gset
select set_rule('report_salary_source','"app_first"') is null as x4 \gset
select set_rule('rpt131_on','true') is null as x5 \gset
select set_rule('cash_short_post_on','true') is null as x6 \gset
\endif
select set_rule('accounting_on','true') is null as a_on \gset
select set_rule('accounting_autopost','true') is null as a_on2 \gset
-- test-only numbers (the product never invents these; a real owner sets his own): VAT 5 percent, prices include VAT
select set_rule('vat_on','true') is null as v1 \gset
select set_rule('vat_rate','5') is null as v2 \gset
select set_rule('vat_prices_include','true') is null as v3 \gset
select string_agg(key||'='||coalesce(value::text,'-'), ', ' order by key) as rr from rules where value is not null \gset
\echo RULES_SET_AFTER_S1: :rr

\echo == P purchase to pay: bill with freight (landed cost), goods receipt, supplier payment later
select tt.as(:'o');
with s as (insert into suppliers (name, credit_days) values ('test_supplier_one', null) returning id) select id as sup1 from s \gset
with s as (insert into suppliers (name, credit_days) values ('test_transporter', null) returning id) select id as sup2 from s \gset
-- inputs: flour 100 kg @ 40 = 4000, sugar 60 kg @ 80 = 4800, box 200 pc @ 5 = 1000 -> bill 9800 at the factory (place 6). Freight 490 (5 percent) by value.
select save_purchase(gen_random_uuid(),null,:'sup1'::uuid,6,'test_bill_1',tt.today()-3,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40},{"item_id":"%s","qty":60,"unit":"kg","unit_cost":80},{"item_id":"%s","qty":200,"unit":"pc","unit_cost":5}]',tt.iid('test_flour'),tt.iid('test_sugar'),tt.iid('test_box'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select tt.eq('P1 bill total = 100*40+60*80+200*5', 100*40+60*80+200*5, (select total from purchase_bills where id=:'b1'::uuid));
select tt.eq('P1 flour qty', 100, tt.qty('test_flour',6)); select tt.eq('P1 flour avg cost', 40, tt.avg('test_flour',6));
select tt.eq('P1 supplier owes 9800 (supplier_dues)', 9800, (select balance from supplier_dues(6) where supplier_id=:'sup1'::uuid));
select acct_post_pending(false) is not null as pp0 \gset
select tt.eq('P1 GL inventory raw + packaging (1320+1330) = 9800', 9800, tt.bal('1320')+tt.bal('1330'));
select tt.eq('P1 GL supplier payable 2100 credit 9800', -9800, tt.bal('2100'));

select set_rule('landed_cost_mode','"manual"') is null as lm \gset
select landed_save(gen_random_uuid(), null, '{"title":"test freight","alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b1')::jsonb,
  format('[{"charge_type":"freight","amount":490,"alloc_method":"value","pay_mode":"payable","supplier_id":"%s"}]',:'sup2')::jsonb) as lsv \gset
select (:'lsv'::jsonb->>'id')::uuid as lc \gset
select landed_post(:'lc'::uuid, gen_random_uuid()) as lpo \gset
select tt.eq('P2 landed stock_added = freight 490', 490, (:'lpo'::jsonb->>'stock_added')::numeric);
-- hand: freight share = amount/9800*490 = 5 percent of value -> flour 42, sugar 84, box 5.25
select tt.eq('P2 flour landed avg = 40 + 0.05*40', 42, tt.avg('test_flour',6), 0.0001);
select tt.eq('P2 sugar landed avg = 80 + 0.05*80', 84, tt.avg('test_sugar',6), 0.0001);
select tt.eq('P2 box landed avg = 5 + 0.05*5', 5.25, tt.avg('test_box',6), 0.0001);
select acct_post_pending(false) is not null as pp1 \gset
select tt.eq('P2 GL inventory 1320+1330 = 9800 + 490', 10290, tt.bal('1320')+tt.bal('1330'));
select tt.eq('P2 transporter payable 490 (supplier_dues of the second supplier)', 490, coalesce((select balance from supplier_dues(6) where supplier_id=:'sup2'::uuid),0));

-- GRN first, bill second, link guard: 10 pc tape @ 3 must count ONCE (value 30, payable +30)
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,vat_applicable) values ('test_tape','test_tape','test_tape','pc','pc','packaging',true,0,false,true) on conflict do nothing;
select set_rule('forms_post_to_ledger','true') is null as fpl \gset
select set_rule('grn_receipt_source','"grn"') is null as grs \gset
select set_rule('purchase_grn_guard','"link"') is null as gl \gset
select save_entry(null,'13-1',6,tt.today(),'{"supplier":"test_supplier_one","lines":[{"item":"test_tape","counted":"10","rate":"3","quality":"accept"}]}','[]') ->> 'id' as g1 \gset
select rule_on('blind_count_on') as blindon \gset
\if :blindon
select count_lines_seal(:'g1'::uuid) ->> 'sealed' as seal1 \gset
\endif
select submit_entry(:'g1'::uuid) is not null as sg1 \gset
select decide_entry(:'g1'::uuid, true, null, null, '[]') ->> 'status' as dg1 \gset
select tt.is('G1 GRN 13-1 approved', 'approved', :'dg1');
select tt.eq('G1 tape qty after GRN', 10, tt.qty('test_tape',6));
select save_purchase(null,null,:'sup1'::uuid,6,'test_bill_tape',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":3}]',tt.iid('test_tape'))::jsonb) ->> 'id' as bt \gset
select tt.err('G1 bill without GRN link refused', format($$select post_purchase('%s'::uuid)$$, :'bt'), 'grn_link_required');
select grn_bill_link(:'g1'::uuid, :'bt'::uuid) is not null as lk \gset
select post_purchase(:'bt'::uuid) is not null as pbt \gset
select tt.eq('G1 tape qty after linked bill (counted once)', 10, tt.qty('test_tape',6));
select set_rule('forms_post_to_ledger',null) is null as fpl2 \gset
select set_rule('grn_receipt_source','"purchase"') is null as grs2 \gset
select set_rule('purchase_grn_guard','"off"') is null as go \gset
select acct_post_pending(false) is not null as pp2 \gset
select tt.eq('G1 GL inventory incl tape = 10290 + 30', 10320, tt.bal('1320')+tt.bal('1330'));
select tt.eq('G1 supplier one owes 9800 + 30', 9830, (select balance from supplier_dues(6) where supplier_id=:'sup1'::uuid));

\echo == P3 pay the transporter (freight payable, credited to 2150 with the transporter as party)
select pay_supplier(:'sup2'::uuid,6,'[{"mode":"cash","amount":490}]'::jsonb) as p3 \gset
select tt.eq('P3 pay_supplier pays the transporter 490 (phase 549; before it raised overpaid, defect D1) and nothing is left owed', 0, (:'p3'::jsonb->>'balance')::numeric);
select tt.eq('P3 the payment settles landed charges 490 (landed_part)', 490, (select coalesce(sum(landed_part),0) from supplier_payments where supplier_id=:'sup2'::uuid and not voided));

\echo == M production at the factory (place 6): recipe cost + overhead (conversion) per batch
select tt.as(:'o');
-- Recipe A: 10 kg per batch from flour 5, sugar 4, box 2; conversion: labour 100 + gas 50 per batch. Recipe B: 5 kg per batch from flour 3, sugar 2, box 1; labour 80 per batch.
select (recipe_save(null, tt.iid('test_sweet_a'), 10, 'kg', 'test recipe A', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('test_flour'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('test_sugar'),'qty',4,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('test_box'),'qty',2,'unit','pc','waste_pct',0)), gen_random_uuid())->>'id')::uuid as ra \gset
select (recipe_save(null, tt.iid('test_sweet_b'), 5, 'kg', 'test recipe B', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('test_flour'),'qty',3,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('test_sugar'),'qty',2,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('test_box'),'qty',1,'unit','pc','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rb \gset
select loc_cost_cfg_set(6,'recipe') is null as lc \gset
select recipe_cost_component_set(:'ra'::uuid,'labour','per_batch',100,null,null,'labour',gen_random_uuid()) is not null as c1 \gset
select recipe_cost_component_set(:'ra'::uuid,'gas','per_batch',50,null,null,'gas',gen_random_uuid()) is not null as c2 \gset
select recipe_cost_component_set(:'rb'::uuid,'labour','per_batch',80,null,null,'labour',gen_random_uuid()) is not null as c3 \gset
select tt.as(:'ap');
select recipe_approve(:'ra'::uuid,'ok') is not null as ap_a \gset
select recipe_approve(:'rb'::uuid,'ok') is not null as ap_b \gset
select tt.as(:'o');
select recipe_cost(:'ra'::uuid,6) as rca \gset
select tt.eq('M1 recipe_cost A unit cost = (5*42+4*84+2*5.25+100+50)/10', (5*42+4*84+2*5.25+100+50)/10.0, (:'rca'::jsonb->>'unit_cost')::numeric, 0.0005);
select production_post(6, :'ra'::uuid, 3, gen_random_uuid()) as pa \gset
select production_post(6, :'rb'::uuid, 2, gen_random_uuid()) as pbp \gset
select tt.eq('M2 yield A = 3 batches x 10 kg', 30, tt.qty('test_sweet_a',6)); select tt.eq('M2 yield B = 2 x 5 kg', 10, tt.qty('test_sweet_b',6));
select tt.eq('M2 flour left 100 - (5*3 + 3*2)', 100-(5*3+3*2), tt.qty('test_flour',6));
select tt.eq('M2 sugar left 60 - (4*3 + 2*2)', 60-(4*3+2*2), tt.qty('test_sugar',6));
select tt.eq('M2 box left 200 - (2*3 + 1*2)', 200-(2*3+1*2), tt.qty('test_box',6));
select tt.eq('M2 cost A = (5*42+4*84+2*5.25+150)/10', 70.65, tt.avg('test_sweet_a',6), 0.0005);
select tt.eq('M2 cost B = (3*42+2*84+5.25+80)/5', 75.85, tt.avg('test_sweet_b',6), 0.0005);
select acct_post_pending(false) is not null as pp3 \gset
-- hand: raw used = flour 21*42 + sugar 16*84 + box 8*5.25 = 882+1344+42 = 2268; conversion absorbed = 3*150 + 2*80 = 610; finished value = 30*70.65+10*75.85 = 2878
select tt.eq('M3 GL finished goods 1310 = 30*70.65 + 10*75.85', 30*70.65+10*75.85, tt.bal('1310'), 0.01);
select tt.eq('M3 GL raw+packaging after use = 10320 - 2268 (incl. test_tape 30)', 10320 - (21*42+16*84+8*5.25), tt.bal('1320')+tt.bal('1330'), 0.01);
select tt.eq('M3 overhead absorbed (5950 credit) = 3*150 + 2*80', -610, tt.bal('5950'), 0.01);

\echo == T transfers: factory to showrooms, one short receipt
select tt.as(:'o');
select stock_transfer(6, 1, tt.iid('test_sweet_a'), 20, 'kg', 'test to showroom 1 A', gen_random_uuid()) ->> 'id' as t1 \gset
select stock_transfer(6, 1, tt.iid('test_sweet_b'), 8, 'kg', 'test to showroom 1 B', gen_random_uuid()) ->> 'id' as t2 \gset
select stock_transfer(6, 3, tt.iid('test_sweet_a'), 8, 'kg', 'test to showroom 3 A', gen_random_uuid()) ->> 'id' as t3 \gset
select tt.eq('T1 factory A after send 30-20-8', 2, tt.qty('test_sweet_a',6)); select tt.eq('T1 showroom 1 A not yet received', 0, tt.qty('test_sweet_a',1));
select acct_post_pending(false) is not null as pp4 \gset
select tt.eq('T1 in transit A = 28 kg (stock_in_transit)', 28, coalesce((select sum(qty) from stock_in_transit(null) where item_id=tt.iid('test_sweet_a')),-1));
select stock_receive_transfer(:'t1'::uuid, 20, 'ok') is not null as r1 \gset
select stock_receive_transfer(:'t2'::uuid, 8, 'ok') is not null as r2 \gset
select stock_receive_transfer(:'t3'::uuid, 7.5, 'short 0.5 kg on the way') is not null as r3 \gset
select tt.eq('T2 showroom 1 A = 20', 20, tt.qty('test_sweet_a',1)); select tt.eq('T2 showroom 1 B = 8', 8, tt.qty('test_sweet_b',1));
select tt.eq('T2 showroom 3 A = 7.5 (short 0.5)', 7.5, tt.qty('test_sweet_a',3));
select tt.eq('T2 showroom 1 A cost carried = 70.65', 70.65, tt.avg('test_sweet_a',1), 0.0005);
select tt.eq('T2 showroom 3 A cost carried = 70.65 (short kg does not change unit cost)', 70.65, tt.avg('test_sweet_a',3), 0.0005);
select tt.eq('T2 transit_short exception count', 1, (select count(*) from exceptions where flag_code='transit_short'));
select acct_post_pending(false) is not null as pp5 \gset
select tt.eq('T3 per-place stock valuation total (stock_valuation all places) = GL inventory 1310+1320+1330 [short kg 0.5 x 70.65 is lost: stock gone, GL must show 5130 or stay in inventory]', (select sum(qty*coalesce(avg_cost,0)) from stock_balance), tt.bal('1310')+tt.bal('1320')+tt.bal('1330'), 0.01, 'inventory ledger value vs GL inventory after the short receipt');
select tt.eq('T3 short loss to 5130 (hand 0.5 x 70.65 = 35.325) - on by default?', 0.5*70.65, tt.bal('5130'), 0.01);

\echo == X sales at the showrooms: cash, card, bKash-style wallet, credit with due, discount, one return, one wastage
-- inputs. Showroom 1 (seller A): S1 A 2 kg cash 800; S2 B 1 kg card 500; S3 A 1.5 kg wallet 600; S4 A 3 kg = 1200 (cash 500, due 700, customer test_customer_one); S5 B 2 kg = 1000 less discount 50 = 950 cash.
-- Showroom 3 (seller B): S6 A 4 kg cash 1600. Then: collection of 300 cash from the customer; return 0.5 kg A from S1 (refund 200 cash); wastage 0.4 kg A at showroom 1.
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":400}]',tt.iid('test_sweet_a'))::jsonb,0,'[{"mode":"cash","amount":800}]',null,null,'retail',null,false) as s1j \gset
select (:'s1j'::jsonb->>'id')::uuid as s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":500}]',tt.iid('test_sweet_b'))::jsonb,0,'[{"mode":"card","amount":500}]',null,null,'retail',null,false) as s2j \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1.5,"price":400}]',tt.iid('test_sweet_a'))::jsonb,0,'[{"mode":"mobile","wallet":"bKash","amount":600}]',null,null,'retail',null,false) as s3j \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":400}]',tt.iid('test_sweet_a'))::jsonb,0,'[{"mode":"cash","amount":500}]','01700000601','test_customer_one','retail',null,false) as s4j \gset
select tt.err('X0 a salesperson cannot give a discount of 50 when no limit is written (control works: discount_needs_approval)', format($q$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":2,"price":500}]'::jsonb,50,'[{"mode":"cash","amount":950}]',null,null,'retail',null,false)$q$, tt.iid('test_sweet_b')), 'discount_needs_approval');
select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":500}]',tt.iid('test_sweet_b'))::jsonb,50,'[{"mode":"cash","amount":950}]',null,null,'retail',null,false) as s5j \gset
select tt.as(:'sp3');
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":4,"price":400}]',tt.iid('test_sweet_a'))::jsonb,0,'[{"mode":"cash","amount":1600}]',null,null,'retail',null,false) as s6j \gset
select tt.eq('X1 S1 total', 800, (:'s1j'::jsonb->>'total')::numeric); select tt.eq('X1 S3 wallet total', 600, (:'s3j'::jsonb->>'total')::numeric);
select tt.eq('X1 S4 total 1200', 1200, (:'s4j'::jsonb->>'total')::numeric);
select tt.eq('X1 S4 due = 1200 - 500', 700, coalesce((:'s4j'::jsonb->>'due')::numeric, 1200-500-(select coalesce(sum(amount),0) from sale_payments where sale_id=(:'s4j'::jsonb->>'id')::uuid)));
select tt.eq('X1 S5 total after discount 50', 950, (:'s5j'::jsonb->>'total')::numeric);
select tt.as(:'sp3');
select tt.eq('X1 S6 total', 1600, (:'s6j'::jsonb->>'total')::numeric);
select tt.as(:'sp');
select id as cust from customers where mobile='01700000601' \gset
select collect_payment(gen_random_uuid(), 1, :'cust'::uuid, '[{"mode":"cash","amount":300}]', 'test collection') is not null as col \gset
select tt.as(:'o');
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":0.5}]',tt.iid('test_sweet_a'))::jsonb, 'damaged','test return','cash') as retj \gset
select stock_wastage(tt.iid('test_sweet_a'),1,0.4,'spoiled','test wastage') is not null as wj \gset
-- hand stock: showroom 1 A = 20 - (2+1.5+3) + 0.5 - 0.4 ; B = 8 - (1+2); showroom 3 A = 7.5 - 4
select tt.eq('X2 showroom 1 A', 20-(2+1.5+3)+0.5-0.4, tt.qty('test_sweet_a',1)); select tt.eq('X2 showroom 1 B', 8-(1+2), tt.qty('test_sweet_b',1));
select tt.eq('X2 showroom 3 A', 7.5-4, tt.qty('test_sweet_a',3));
select tt.eq('X2 customer due after collection = 700 - 300', 400, (select balance from customer_dues() where id=:'cust'::uuid));
select acct_post_pending(false) is not null as pp6 \gset

\echo == A books after the sales (hand numbers from the inputs above)
-- revenue: gross 4100 + 1600 = 5700 at list, discount 50, returns 200 -> net 5450. Cash: showroom 1 = 20000 + 800 + 500 + 950 + 300 - 200 ; showroom 3 = 1600.
select tt.eq('A1 GL sales 4100 (gross at list price) = 2600+1500 at showroom 1 + 1600 at showroom 3', -(800+600+1200+500+1000+1600), tt.bal('4100'));
select tt.eq('A1 GL discount 4120', 50, tt.bal('4120')); select tt.eq('A1 GL returns 4110', 200, tt.bal('4110'));
select tt.eq('A1 cash 1110 showroom 1', 20000+800+500+950+300-200, tt.bal_loc('1110',1)); select tt.eq('A1 cash 1110 showroom 3', 1600, tt.bal_loc('1110',3));
select tt.eq('A1 card receivable 1140 = card sale', 500, tt.bal('1140')); select tt.eq('A1 wallet 1130 (bKash-style)', 600, tt.bal('1130')+tt.bal('1131'));
select tt.eq('A1 customer receivable 1210 = 700 due - 300 collected', 400, tt.bal('1210'));
select tt.eq('A1 COGS 5000 = A 6.5kg*70.65 + B 3kg*75.85 + loc3 A 4kg*70.65 - return 0.5kg*70.65', 6.5*70.65+3*75.85+4*70.65-0.5*70.65, tt.bal('5000'), 0.01);
select tt.eq('A1 wastage 5100 = 0.4 kg x 70.65', 0.4*70.65, tt.bal('5100'), 0.01);
select tt.eq('A1 trial balance: unbalanced entries', 0, tt.unbalanced());
select tt.eq('P3b account 2150 freight payable is 0 after the payment (Dr 2150, Cr cash)', 0, tt.bal('2150'));
select acct_trial_balance(tt.today()-5, tt.today(), null) as tb \gset
select tt.t('A1 trial balance report: debit = credit', (:'tb'::jsonb->>'balanced')::boolean, 'balanced', (:'tb'::jsonb->>'total_debit')||' vs '||(:'tb'::jsonb->>'total_credit'));
-- inventory: quantity ledger value = GL, in total and place by place
select tt.eq('A2 inventory: ledger value (all places) = GL 1310+1320+1330', (select sum(qty*coalesce(avg_cost,0)) from stock_balance), tt.bal('1310')+tt.bal('1320')+tt.bal('1330'), 0.01, 'company-wide');
select tt.eq('A2 inventory place 6 (factory): ledger value = GL tagged to place 6', (select sum(qty*coalesce(avg_cost,0)) from stock_balance where location_id=6), tt.bal_loc('1310',6)+tt.bal_loc('1320',6)+tt.bal_loc('1330',6), 0.01, 'place by place: transfers must move GL inventory between places');
select tt.eq('A2 inventory place 1 (showroom 1): ledger value = GL tagged to place 1', (select sum(qty*coalesce(avg_cost,0)) from stock_balance where location_id=1), tt.bal_loc('1310',1)+tt.bal_loc('1320',1)+tt.bal_loc('1330',1), 0.01);
select tt.eq('A2 inventory place 3 (showroom 3): ledger value = GL tagged to place 3', (select sum(qty*coalesce(avg_cost,0)) from stock_balance where location_id=3), tt.bal_loc('1310',3)+tt.bal_loc('1320',3)+tt.bal_loc('1330',3), 0.01);

\echo == G gross margin per product and place from the inputs (net of return); report side by side
-- revenue net of discount/return: place 1 A = 800+600+1200-200 = 2400, B = 500+1000-50 = 1450; place 3 A = 1600. Cost: A 70.65, B 75.85.
-- margin place1 A = 2400 - 6*70.65 ; B = 1450 - 3*75.85 ; place 3 A = 1600 - 4*70.65
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd1_
select tt.eq('G2 biz_daily place 1 revenue (after returns)', 2400+1450, :bd1_revenue::numeric); select tt.eq('G2 biz_daily place 1 COGS', 6*70.65+3*75.85, :bd1_cogs::numeric, 0.01);
select * from biz_daily(tt.today(), tt.today(), 3) \gset bd3_
select tt.eq('G2 biz_daily place 3 revenue', 1600, :bd3_revenue::numeric); select tt.eq('G2 biz_daily place 3 COGS', 4*70.65, :bd3_cogs::numeric, 0.01);
select report_run('sales_summary', jsonb_build_object('from', tt.today(), 'to', tt.today()), 'location', null, 1, false) as ss \gset
select (select (x->>'gp')::numeric from jsonb_array_elements(:'ss'::jsonb->'rows') x where (x->>'location_id')::int=1) as ss_gp1 \gset
select tt.eq('G3 sales_summary place 1 gp = revenue after returns - COGS after returns (3850 - 651.45)', 3850-(6*70.65+3*75.85), :ss_gp1::numeric, 0.01, 'sales_summary gp uses net before returns unless reports_net_of_returns is on');
select (select (x->>'gp')::numeric from jsonb_array_elements(:'ss'::jsonb->'rows') x where (x->>'location_id')::int=3) as ss_gp3 \gset
select tt.eq('G3 sales_summary place 3 gp = 1600 - 282.6', 1600-4*70.65, :ss_gp3::numeric, 0.01);

\echo == D day close at showroom 1 with a blind cash count (form 06-1 Daily Showroom Sheet)
-- typed from the day: total sales 4050 (800+500+600+1200+950), digital 1100 (card 500 + wallet 600), dues collected 300, refund 200, credit 700 -> expected drawer 4050 - 1100 + 300 - 200 - 700 = 2350.
-- counted: 2 x 1000 + 3 x 100 + 2 x 20 = 2340 -> short 10.
select tt.as(:'sm');
select save_entry(null,'06-1',1,tt.today(),'{"open_counted":0,"total_entered":4050,"d_bkash":600,"d_card":500,"dues":300,"credit_sales":700,"refund":200,"cash_count":{"n1000":2,"n100":3,"n20":2}}','[]') ->> 'id' as dc \gset
select tt.t('D1 daily sheet saved', :'dc' is not null);
select count_save(:'dc'::uuid,'drawer','{"n1000":2,"n100":3,"n20":2}') as cs \gset
\echo COUNT_SAVE_RESULT_FOR_MAKER: :cs
select tt.t('D1 maker sees no expected figure after counting (blind)', not (:'cs'::jsonb ? 'expected') and not (:'cs'::jsonb ? 'diff'));
select submit_entry(:'dc'::uuid) ->> 'status' as dst \gset
select tt.as(:'o');
select tt.eq('D2 stored expected drawer cash', 4050-1100+300-200-700, (select expected from entry_counts where entry_id=:'dc'::uuid and section='drawer'));
select tt.eq('D2 stored counted', 2340, (select counted from entry_counts where entry_id=:'dc'::uuid and section='drawer'));
select tt.eq('D2 stored difference (short)', -10, (select diff from entry_counts where entry_id=:'dc'::uuid and section='drawer'));
select tt.eq('D2 expected cash by the POS day-close report equals the typed expectation', 4050-1100+300-200-700, (select (x->>'expected_cash_after_refunds')::numeric from jsonb_array_elements(report_run('pos_day_close', jsonb_build_object('from',tt.today(),'to',tt.today()), null,null,1,false)->'rows') x where (x->>'location_id')::int=1));
select tt.eq('D9 POS cash of the place and day (cash taken + collections - cash refunds) = the typed expectation 2350 (phase 552)', 4050-1100+300-200-700, _p552_pos_cash(1, tt.today()));
select tt.eq('D9 POS-based expectation of the sheet = 2350', 2350, (select _p552_pos_expected(e, _count_inputs18(e,'drawer')) from entries e where e.id=:'dc'::uuid));
select tt.t('D9 pos_compare: no exception when the typed expectation equals the POS', (select jsonb_array_length(_p552_flags(e, 2350, '[]'::jsonb)) = 0 from entries e where e.id=:'dc'::uuid));
select set_rule('drawer_expected_source','"pos_compare"') is null as d9a \gset
select tt.t('D9 pos_compare: exception drawer_typed_vs_pos when the typed expectation (2400) differs from the POS (2350)', (select _p552_flags(e, 2400, '[]'::jsonb) -> 0 ->> 'code' = 'drawer_typed_vs_pos' and (_p552_flags(e, 2400, '[]'::jsonb) -> 0 ->> 'amount')::numeric = 50 from entries e where e.id=:'dc'::uuid));
select set_rule('drawer_expected_source','"typed"') is null as d9b \gset
select tt.t('D9 typed (default): never an exception', (select jsonb_array_length(_p552_flags(e, 2400, '[]'::jsonb)) = 0 from entries e where e.id=:'dc'::uuid));
select tt.eq('D2 exception cash_short_over raised with amount -10', 1, (select count(*) from exceptions where entry_id=:'dc'::uuid and flag_code='cash_short_over' and amount=-10));
select decide_entry(:'dc'::uuid, true, null, null, '[]') ->> 'status' as dd \gset
select tt.is('D2 sheet approved by the owner (a different login)', 'approved', :'dd');
select acct_post_pending(false) is not null as pp7 \gset
select tt.eq('D3 the 10 short is in the books (5800 cash short/over, Dr 10) - posted by default?', 10, tt.bal('5800'), 0.005, 'switch drawer_short_post / cash_short_post_on');
select tt.eq('D3 cash 1110 showroom 1 after the short', 20000+800+500+950+300-200-10, tt.bal_loc('1110',1), 0.005);
select daybook_vs_journal(tt.today(), tt.today(), 1) as dvj \gset
select tt.eq('D4 day book vs journal: total difference for place 1 on the day', 0, (:'dvj'::jsonb->'total'->>'diff')::numeric);

\echo == P4 supplier payment (partial, from the bank)
select tt.as(:'o');
select pay_supplier(:'sup1'::uuid, 6, '[{"mode":"bank","amount":5000}]'::jsonb, gen_random_uuid()) as psj \gset
select tt.eq('P4 supplier one owes 9830 - 5000', 9830-5000, (select balance from supplier_dues(6) where supplier_id=:'sup1'::uuid));
select acct_post_pending(false) is not null as pp8 \gset
select tt.eq('P4 GL supplier payable 2100 (supplier one 4830)', -(9830-5000), tt.bal('2100'));
select tt.eq('P4 bank 1120 = 100000 - 5000', 95000, tt.bal('1120'));
select tt.err('P4 pay more than owed is refused', format($$select pay_supplier('%s'::uuid,6,'[{"mode":"bank","amount":4831}]'::jsonb)$$,:'sup1'), 'overpaid');

\echo == W payroll sheet for the month: factory worker (absent 2 days) and showroom staff
select date_trunc('month', tt.today())::date as m0 \gset
insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, joining_date) values
 ('TEST_RD_A','test_worker_a','test_worker_a','active',6,'2025-01-01'),('TEST_RD_B','test_staff_b','test_staff_b','active',1,'2025-01-01');
select id as ea from employees where employee_no='TEST_RD_A' \gset
select id as eb from employees where employee_no='TEST_RD_B' \gset
insert into employee_pay (employee_id, effective_from, pay_basis, basic, ot_rule, ot_value, ot_hours_basis, bonus_rules) values
 (:'ea','2025-01-01','monthly',6000,'none',null,8,'[]'),(:'eb','2025-01-01','monthly',4000,'none',null,8,'[]');
insert into attendance_days (employee_id, day, status, day_kind, location_id, source)
 select e.id, g::date, case when e.id=:'ea'::uuid and g::date in (:'m0'::date+3, :'m0'::date+4) then 'absent' else 'present' end, 'normal', e.primary_location_id, 'auto'
 from employees e cross join generate_series(:'m0'::date, (:'m0'::date + interval '1 month - 1 day')::date, interval '1 day') g where e.employee_no like 'TEST_RD_%';
select (payroll_create(:'m0'::date, 6, gen_random_uuid()) ->> 'id')::bigint as r6 \gset
select (payroll_create(:'m0'::date, 1, gen_random_uuid()) ->> 'id')::bigint as r1 \gset
-- hand: month days = days in the month; worker A = 6000 - 2 * 6000 / days, rounded to a whole taka; staff B = 4000.
select extract(day from (date_trunc('month', :'m0'::date) + interval '1 month - 1 day'))::int as dim \gset
select tt.eq('W1 worker A net pay = round(6000 - 2*6000/days)', round(6000 - 2*6000.0/:dim), (select net from payroll_lines where employee_id=:'ea'::uuid));
select tt.eq('W1 staff B net pay', 4000, (select net from payroll_lines where employee_id=:'eb'::uuid));
select payroll_approve(:'r6') ->> 'status' as ap6 \gset
select payroll_approve(:'r1') ->> 'status' as ap1 \gset
select payroll_pay(:'r6', array(select id from payroll_lines where run_id=:'r6'), 'bank', tt.today(), 'test-sal-a', null, gen_random_uuid(), null) is not null as pa \gset
select payroll_pay(:'r1', array(select id from payroll_lines where run_id=:'r1'), 'cash', tt.today(), 'test-sal-b', null, gen_random_uuid(), null) is not null as pb \gset
select acct_post_pending(false) is not null as pp9 \gset
select tt.eq('W2 GL salaries 5200 = net pay of both (payroll_accrual_on off = expense at payment)', round(6000 - 2*6000.0/:dim)+4000, tt.bal('5200'));
select tt.eq('W2 bank after salary of A and supplier payment', 100000-5000-round(6000 - 2*6000.0/:dim), tt.bal('1120'));
select tt.eq('W2 cash showroom 1 after salary of B', 20000+800+500+950+300-200-10-4000, tt.bal_loc('1110',1), 0.005, 'includes the 10 cash short only if it was booked (D3)');
select tt.eq('W2 payroll sheet: both runs paid', 2, (select count(*) from payroll_runs where status='paid'));

\echo == V VAT memo (test rate 5 percent, prices include VAT); sales 5650 (after discount), returns 200, purchases 9830
select tt.as(:'o');
select vat_report(tt.today()-5, tt.today(), null) as vj \gset
select tt.eq('V1 output VAT = round(5650*5/105,2) - round(200*5/105,2)', round(5650*5/105.0,2) - round(200*5/105.0,2), (:'vj'::jsonb->'output'->>'vat')::numeric, 0.011);
select tt.eq('V1 input VAT = round(9830*5/105,2) (freight 490 is not in the bills)', round(9830*5/105.0,2), (:'vj'::jsonb->'input'->>'vat')::numeric, 0.011);
select tt.eq('V1 net VAT payable', (round(5650*5/105.0,2) - round(200*5/105.0,2)) - round(9830*5/105.0,2), (:'vj'::jsonb->>'net_vat_payable')::numeric, 0.02);
select tt.eq('V2 VAT is a memo only: GL VAT payable 2800 and input 1240 stay 0', 0, tt.bal('2800') + tt.bal('1240'));

\echo == F statements: P&L, balance sheet, cash flow against hand numbers
-- correct P&L, all days: net sales 5450 - COGS 934.05 - wastage 28.26 - transit short 35.325 - cash short 10 - salaries - overhead absorbed credit 610 (a credit)
select (round(6000 - 2*6000.0/:dim)+4000) as sal \gset
select tt.as(:'o');
select acct_income_statement(tt.today()-5, tt.today(), null) as ist \gset
select tt.eq('F1 P&L revenue (net of returns and discount)', 5450, (:'ist'::jsonb->>'total_income')::numeric, 0.01);
select tt.eq('F1 P&L COGS', 934.05, (:'ist'::jsonb->>'cogs')::numeric, 0.01);
select tt.eq('F1 P&L gross profit', 5450-934.05, (:'ist'::jsonb->>'gross_profit')::numeric, 0.01);
select tt.eq('F1 P&L net profit (every cost the stock and drawer lost is in)', 5450-934.05-28.26-0.5*70.65-10-:sal+610, (:'ist'::jsonb->>'net_profit')::numeric, 0.02, 'def: transit short and cash short stay unbooked (D2, D3); rec: booked');
select acct_balance_sheet(tt.today(), null) as bs \gset
select tt.t('F2 balance sheet balances (difference 0)', (:'bs'::jsonb->>'difference')::numeric = 0 and not (:'bs'::jsonb->>'unbalanced')::boolean, 'diff 0', :'bs'::jsonb->>'difference');
select tt.eq('F2 retained earnings = P&L net profit', (:'ist'::jsonb->>'net_profit')::numeric, (:'bs'::jsonb->>'retained_earnings')::numeric, 0.01);
select tt.eq('F2 total assets (less the 490 cash paid to the transporter in P3) = cash 18340+1600, bank 89387, wallet 600, card 500, receivable 400, inventory 9932.365 (all costs booked)', 18340+1600+89387+600+500+400+9932.365-490, (:'bs'::jsonb->>'total_assets')::numeric, 0.02, 'def: transit short and cash short unbooked, inventory overstated by 35.325 and cash by 10');
select tt.eq('F2 total liabilities = supplier 4830 (freight payable 490 was paid in P3)', 4830, (:'bs'::jsonb->>'total_liabilities')::numeric, 0.01);
select tt.eq('F2 equity + earnings = 120000 + correct net profit', 120000 + (5450-934.05-28.26-0.5*70.65-10-:sal+610), (:'bs'::jsonb->>'total_equity_and_earnings')::numeric, 0.02);
select acct_cash_flow(tt.today()-5, tt.today(), null) as cf \gset
\echo CASH_FLOW_JSON: :cf

\echo == R each report of the hub against the ledger (all 120 catalogue reports are also run for errors)
select tt.eq('R1 payment_modes: sale cash+card+mobile = money taken = 5650 net of discount less 700 on credit', 5650-700, (select coalesce(sum((x->>'sale_amount')::numeric),0) from jsonb_array_elements(report_run('payment_modes', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1,false)->'rows') x));
select tt.eq('R2 customer_dues report = receivable account 1210', tt.bal('1210'), (select coalesce(sum((x->>'balance')::numeric),0) from jsonb_array_elements(report_run('customer_dues', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1,false)->'rows') x));
select tt.eq('R3 supplier_ageing = supplier payable 2100', -tt.bal('2100'), (select coalesce(sum((x->>'balance')::numeric),0) from jsonb_array_elements(report_run2('supplier_ageing', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x));
select tt.eq('R4 stock_balance report value = ledger value by hand (3318+3696+1008+30+141.3+151.7+960.84+379.25+247.275)', 9932.365, (select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(report_run2('stock_balance', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x), 0.01);
select tt.eq('R5 l1_pnl profit, both places = revenue after returns - COGS (less salaries only when report_salary_source = app_first)', 5450-934.05 - (case when rule_txt('report_salary_source')='app_first' then (round(6000 - 2*6000.0/:dim)+4000) else 0 end), (select coalesce(sum((x->>'profit')::numeric),0) from jsonb_array_elements(report_run2('l1_pnl', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x), 0.01);
select tt.eq('R6 l3_shop_pnl profit place 3', 1600-4*70.65, (select (x->>'profit')::numeric from jsonb_array_elements(report_run2('l3_shop_pnl', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x where (x->>'location_id')::int=3), 0.01);
select tt.eq('R7 l2_margin sweet A, both places: margin = 4000 - 10 kg*70.65', 4000-10*70.65, (select (x->>'margin')::numeric from jsonb_array_elements(report_run2('l2_margin', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x where x->>'item_code'='test_sweet_a'), 0.01);
select tt.eq('R7 l2_margin sweet B, margin = 1450 - 3*75.85', 1450-3*75.85, (select (x->>'margin')::numeric from jsonb_array_elements(report_run2('l2_margin', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x where x->>'item_code'='test_sweet_b'), 0.01);
select tt.eq('R8 l2_margin place 1 only, sweet A: margin = 2400 - 6*70.65', 2400-6*70.65, (select (x->>'margin')::numeric from jsonb_array_elements(report_run2('l2_margin', jsonb_build_object('from',tt.today()-5,'to',tt.today(),'locations',jsonb_build_array(1)),null,null,1)->'rows') x where x->>'item_code'='test_sweet_a'), 0.01);
select tt.eq('R9 wastage report value', 0.4*70.65, (select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(report_run2('wastage', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x), 0.01);
select tt.eq('R10 wastage in GL 5100 = wastage report', tt.bal('5100'), (select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(report_run2('wastage', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x), 0.01);
select tt.eq('R11 transfers_gap short qty', 0.5, (select coalesce(sum((x->>'diff_qty')::numeric),0) from jsonb_array_elements(report_run2('transfers_gap', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x));
select tt.eq('R12 transfers short value in the books = 0.5 kg x 70.65 (5130)', 0.5*70.65, tt.bal('5130'), 0.01);
select tt.eq('R13 wallet_recon bKash total', 600, (select coalesce(sum((x->>'amount')::numeric),0) from jsonb_array_elements(report_run('wallet_recon', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1,false)->'rows') x));
select tt.eq('R14 cash_short_over report = -10', -10, coalesce((select sum((x->>'diff')::numeric) from jsonb_array_elements(report_run2('cash_short_over', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x), (select sum(diff) from entry_counts)));
select tt.eq('R15 w1_cash_flow cash in (both places, sales cash + collection)', 2250+300+1600, (select coalesce(sum((x->>'cash_in')::numeric),0) from jsonb_array_elements(report_run2('w1_cash_flow', jsonb_build_object('from',tt.today()-5,'to',tt.today()),null,null,1)->'rows') x));
select tt.eq('R16 acct_overview / inventory_vs_gl unexplained difference', 0, coalesce((inventory_vs_gl(tt.today(), null)->'total'->>'unexplained')::numeric, -1), 0.01);
select tt.eq('R17 stock_recon_period: every item row obeys opening + movements = closing (sum of identity_diff and unclassified)', 0, (select coalesce(sum(abs((x->>'identity_diff')::numeric) + abs((x->>'unclassified')::numeric)),-1) from jsonb_array_elements(stock_recon_period(tt.today()-5, tt.today(), null, null)->'rows') x), 0.001);
select tt.eq('R18 stock_reconcile: items whose cached balance differs from the ledger', 0, (select count(*) from stock_reconcile(false) where qty_diff <> 0));
select tt.eq('R18b c2_salary_basis (paid payroll runs) = 9613 net pay + advance recovery', round(6000 - 2*6000.0/:dim)+4000, coalesce((c2_salary_basis(:'m0'::date, tt.today()+30, null)->'summary'->>'runs_paid')::numeric,0), 0.01);
select tt.eq('R18c t3_payroll (staff cost report) shows the paid payroll runs', round(6000 - 2*6000.0/:dim)+4000, coalesce((report_run2('t3_payroll', jsonb_build_object('from',:'m0','to',tt.today()+30),null,null,1)->'totals'->>'net_pay')::numeric,0), 0.01, 'T3 reads paper sheets 02-2 / 02-3 only');
select tt.eq('R19 profit_source_check agrees (report COGS = journal COGS)', 1, (case when (profit_source_check(tt.today()-5, tt.today(), null)->>'agree')::boolean then 1 else 0 end));
select tt.eq('R20 acct_party_ledger customer: balance 400', 400, (acct_party_ledger('customer', (select id::text from customers where mobile='01700000601'), null, null, null)->>'closing')::numeric);

\echo -- smoke: every catalogue report runs without an error on this data
create temp table sm (src text, key text, ok boolean, err text);
do $$
declare k record; r jsonb; flt jsonb := jsonb_build_object('from', (now() at time zone 'Asia/Dhaka')::date - 6, 'to', (now() at time zone 'Asia/Dhaka')::date);
begin
  for k in select 'c1' src, x->>'key' key from jsonb_array_elements(report_catalog()) x union all select 'c2', x->>'key' from jsonb_array_elements(report_catalog2()) x union all select 'c3', x->>'key' from jsonb_array_elements(report_catalog3()) x loop
    begin
      if k.src='c1' then r := report_run(k.key, flt, null, null, 1, false); elsif k.src='c2' then r := report_run2(k.key, flt, null, null, 1); else r := report_run3(k.key, flt, null, null, 1); end if;
      insert into sm values (k.src, k.key, true, null);
    exception when others then insert into sm values (k.src, k.key, false, left(sqlerrm,80)); end;
  end loop;
end $$;
select tt.eq('R21 catalogue reports that raise an error', 0, (select count(*) from sm where not ok));
select tt.t('R22 report hub metrics call works', (select rpt_hub_metrics() is not null));

\echo == K stock count adjustment, void of a sale (extra, after the statements above)
select tt.as(:'o');
select tt.bal('5110') as k_before_count \gset
select stock_count_adjust(tt.iid('test_flour'),6,78,'test count') is not null as kc \gset
select tt.eq('K1 flour counted 78 against book 79: book becomes 78', 78, tt.qty('test_flour',6));
select acct_post_pending(false) is not null as ppk1 \gset
select tt.eq('K2 count loss in the books 5110 = 1 kg x 42 (posted by default? switch acct_count_adjust)', 42, tt.bal('5110') - :k_before_count::numeric, 0.01);
select void_sale((:'s6j'::jsonb->>'id')::uuid, 'test void') is not null as vs \gset
select acct_post_pending(false) is not null as ppk2 \gset
select tt.eq('K3 voided sale: showroom 3 stock back to 7.5', 7.5, tt.qty('test_sweet_a',3));
select tt.eq('K3 voided sale: cash showroom 3 back to 0', 0, tt.bal_loc('1110',3));
select tt.eq('K3 trial balance still balanced', 0, tt.unbalanced());

\echo == Z totals
select tt.eq('Z1 unbalanced journal entries', 0, tt.unbalanced());
select tt.eq('Z2 journal total debit = credit', 0, (select sum(debit-credit) from journal_lines));
select format('SUMMARY mode=%s pass=%s fail=%s', :'mode', count(*) filter (where ok), count(*) filter (where not ok)) as sm1 from tt.ea \gset
\echo :sm1
select 'FAILLIST ' || n || ' | ' || step || ' | exp=' || coalesce(expected,'') || ' | act=' || coalesce(actual,'') from tt.ea where not ok order by n;
select 'TB ' || a.code || ' loc ' || coalesce(l.location_id,0) || ' net ' || sum(debit-credit) from journal_lines l join coa_accounts a on a.id=l.account_id group by a.code, l.location_id order by a.code, l.location_id;
