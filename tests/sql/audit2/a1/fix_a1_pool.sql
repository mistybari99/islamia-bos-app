-- A1 FIX probes (gap closure by phase117: pool in the books, G2/G3), written after the fixes.  Self-contained scenario, A1 audit numbers
-- (hand-computed in the HAND comments; same data as supabase/phase117_test.sql).  Own session, clone of the template DB.  The switch pool_gl_post117
-- is NOT set here: defaults = OFF -> FAIL = gap open by default; switches_on.txt = ON -> PASS = closed.  Labels start FX1-G2 / FX1-G3.
\i tests/sql/e2e/00_common.sql
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b3.app','{"full_name":"Owner"}'),(:'fm','maker@b3.app','{"full_name":"Maker"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge') on conflict do nothing;
insert into user_locations values (:'fm',1) on conflict do nothing;
select tt.as(:'o');
\echo == setup
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false),('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),('RM-B','Butter','Butter','kg','kg','raw_material',true,0,false),
 ('PK-B','Box','Box','pc','pc','packaging',true,0,false),('FG-CAKE','Cake','Cake','kg','kg','finished_good',true,300,true) on conflict do nothing;
select acct_set_start(tt.today()-100)->>'start' as sd \gset
select acct_opening('[{"code":"1110","debit":100000,"location_id":1},{"code":"3100","credit":100000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a1 \gset
select set_rule('accounting_autopost','true') is null as a2 \gset
with s as (insert into suppliers (name, credit_days) values ('Sup Main', null) returning id) select id as s1 from s \gset
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'B3c',tt.today()-12,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40},{"item_id":"%s","qty":50,"unit":"kg","unit_cost":60},{"item_id":"%s","qty":20,"unit":"kg","unit_cost":500},{"item_id":"%s","qty":200,"unit":"pc","unit_cost":3}]',tt.iid('RM-F'),tt.iid('RM-S'),tt.iid('RM-B'),tt.iid('PK-B'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select acct_post_pending(false) as pp0 \gset
select set_user_grant(:'o'::uuid,'view_cost') is null as g0 \gset
select (recipe_save(null, tt.iid('FG-CAKE'), 10, 'kg', 'cake v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',10),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-B'),'qty',2,'unit','kg','waste_pct',5),
  jsonb_build_object('ingredient_item_id',tt.iid('PK-B'),'qty',2,'unit','pc','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_labour_hour',50,2,null,'2h x 50',gen_random_uuid()) is not null as c1 \gset
select recipe_cost_component_set(:'rc'::uuid,'gas','per_unit',2,null,null,'gas per kg',gen_random_uuid()) is not null as c2 \gset
select recipe_approve(:'rc'::uuid,'ok') is not null as ap \gset

\echo == T1 factory labour counted twice (A3 gap 5)
-- recipe mode: 2 batches full yield 20 kg -> labour 2 x 2h x 50 = 200 absorbed. Factory sheet salary 200 (02-2).
select loc_cost_cfg_set(1,'recipe') is null as lc \gset
select production_post(1, :'rc'::uuid, 2, gen_random_uuid(), null, 'recipe mode', null) as pr1 \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('21-1',1,9101,tt.today(),'approved','{"pay":[{"name":"F Cook - Cook","due":200}]}','[]',:'o','st');
update entries set data = '{"pay":[{"name":"F Cook - Cook","due":300}]}' where serial = 9101;

\echo == T2 pool is a memo today (A1 b8): absorbed credit with no expense in the books
select loc_cost_cfg_set(1,'pool',1000) is null as lcp \gset
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 3000) is not null as p1 \gset
-- HAND: pool of the month: labour 3000 -> 3.0/kg ; cake 1 batch 10 kg: 30 absorbed (the recipe-mode run above absorbed labour 200 + gas 40 = 240 in the same month)
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'pool mode', null) as pr2 \gset
select acct_post_pending(false) as pp1 \gset
select pool_vs_gl117(1, tt.today()) as v0 \gset

\echo == T3 switch on: the pool is posted as an expense
select tt.err('FX1-G2 T3 catch-up needs accounts rights', format($$select tt.as('%s'); select pool_gl_sync117(1, current_date)$$, :'fm'), 'not allowed');
select tt.as(:'o');
-- the labour pool typed before the switch: catch-up. HAND: Dr 5200 3000 / Cr 2400 3000
-- (the pool typed above is already in the books when pool_gl_post117 is on; the catch-up call must then post nothing more)
select pool_gl_sync117(1, tt.today()) as sy \gset
select tt.eq('FX1-G2 T3 Dr 5200 salaries 3000', 3000, tt.bal('5200'));
select tt.eq('FX1-G2 T3 Cr 2400 accrued 3000', -3000, tt.bal('2400'));
select tt.eq('FX1-G2 T3 second call posts nothing more', 0, (pool_gl_sync117(1, tt.today())->>'posted')::numeric);
-- typing the labour pool again (3500) retires the old row: old entry reversed, new posted. HAND: net Dr 5200 3500
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 3500) is not null as p1b \gset
select tt.eq('FX1-G2 T3 labour pool typed again: net 5200 = 3500', 3500, tt.bal('5200'));
select tt.eq('FX1-G2 T3 net 2400 = -3500', -3500, tt.bal('2400'));
select tt.t('FX1-G2 T3 the old entry has its reversal', exists (select 1 from pool_gl_posts117 where reversal_id is not null));
-- gas 2000 -> 5400 ; depreciation 500 -> not posted (fixed asset module) ; licence fee yearly 1200 -> 100 a month -> 5900
select pool_set(1, date_trunc('month', tt.today())::date, 'gas', 2000) is not null as p2 \gset
select pool_set(1, date_trunc('month', tt.today())::date, 'depreciation', 500) is not null as p3 \gset
select pool_set(1, date_trunc('month', tt.today())::date, 'licence_fee', 1200, 'year') is not null as p4 \gset
select tt.eq('FX1-G2 T3 gas -> utilities 5400 = 2000', 2000, tt.bal('5400'));
select tt.eq('FX1-G2 T3 licence fee yearly 1200 / 12 -> 5900 = 100', 100, tt.bal('5900'));
select tt.eq('FX1-G2 T3 depreciation is not posted (no extra expense: 3500 + 2000 + 100)', 5600, (select coalesce(sum(l.debit - l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id join journal_entries e on e.id=l.entry_id where a.type='expense' and a.code not like '50%' and a.code not like '51%' and a.code <> '5950'));
select tt.eq('FX1-G2 T3 unbalanced entries', 0, tt.unbalanced());
select pool_vs_gl117(1, tt.today()) as v1 \gset
select tt.eq('FX1-G3 T3 report: posted_total', 5600, (:'v1'::jsonb->>'posted_total')::numeric);
select tt.eq('FX1-G3 T3 report: expense in the books', 5600, (:'v1'::jsonb->>'expense_gl')::numeric);
select tt.t('FX1-G3 T3 report: absorbed no longer exceeds expense', not (:'v1'::jsonb->>'absorbed_exceeds_expense')::boolean);
select tt.eq('FX1-G3 T3 report: unabsorbed overhead that reached the P&L = 5600 - 270', 5330, (:'v1'::jsonb->>'unabsorbed_in_pnl')::numeric);
select overhead_trueup117(1, tt.today()) as tu \gset
select tt.eq('FX1-G3 T3 true-up still reports the memo figures (actual 3500+2000+100+500 months share)', 6100, (:'tu'::jsonb->>'actual_total')::numeric);
select tt.eq('FX1-G3 T3 true-up carries the books figures', 5600, (:'tu'::jsonb->'gl'->>'posted_total')::numeric);

\echo == T4 cost bill with destination factory reaches the books, a voided bill is reversed
select cost_source_save(null,'electricity','Utility Co','separate','factory',array[1],'monthly',date_trunc('month',tt.today())::date,'b3',gen_random_uuid())->>'id' as es \gset
select cost_bill_add(:'es'::bigint,'month',date_trunc('month',tt.today())::date,600,'cash','E-1',tt.today(),false,null,null,gen_random_uuid()) as eb \gset
select tt.eq('FX1-G2 T4 bill 600 became a pool row', 600, (select actual_amount from factory_cost_pools where source='allocated' and active and location_id=1 and component_type='electricity'));
select tt.eq('FX1-G2 T4 and the books: utilities 5400 = 2000 + 600', 2600, tt.bal('5400'));
select cost_bill_void((:'eb'::jsonb->>'id')::bigint, 'entered twice') is not null as vb \gset
select tt.eq('FX1-G2 T4 voided bill: reversed, 5400 back to 2000', 2000, tt.bal('5400'));
select tt.eq('FX1-G2 T4 unbalanced entries', 0, tt.unbalanced());

