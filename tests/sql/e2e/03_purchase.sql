\echo == 03 purchase, landed cost, bill payment, GRN guard
select tt.as(:'o');
with s as (insert into suppliers (name, credit_days) values ('Sup Main', null) returning id) select id as s1 from s \gset
with s as (insert into suppliers (name, credit_days) values ('Transporter', null) returning id) select id as s2 from s \gset
-- B1: flour 200@42=8400, sugar 100@60=6000, box 500@3=1500 -> total 15900
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'B1',tt.today()-3,format('[{"item_id":"%s","qty":200,"unit":"kg","unit_cost":42},{"item_id":"%s","qty":100,"unit":"kg","unit_cost":60},{"item_id":"%s","qty":500,"unit":"pc","unit_cost":3}]',tt.iid('RM-F'),tt.iid('RM-S'),tt.iid('PK-B'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select tt.eq('P1 bill total', 15900, (select total from purchase_bills where id=:'b1'::uuid));
select tt.eq('P1 flour qty 100+200', 300, tt.qty('RM-F'));
select tt.eq('P1 flour avg (4000+8400)/300', 41.3333, tt.avg('RM-F'), 0.0001);
select tt.eq('P1 sugar avg', 60, tt.avg('RM-S')); select tt.eq('P1 box avg', 3, tt.avg('PK-B'));

\echo -- bill payment modes (phase99). default = off, recommended = ask
select rule_txt('purchase_bill_creates_payment') as pm0 \gset
\echo PURCHASE_PAY_RULE_AT_START=:pm0
select tt.as(:'o');
select bill_pay_record('purchase',:'b1','cash',5000,gen_random_uuid()) as pr1 \gset
select tt.eq('P2 manual payment 5000 works even while the rule is off (rule only governs auto)', 10900, (:'pr1'::jsonb->>'remaining')::numeric);
select set_rule('purchase_bill_creates_payment','"ask"') is null as ask \gset
select bill_pay_record('purchase',:'b1','bank',3000,gen_random_uuid()) as pr2 \gset
select tt.eq('P2 remaining after cash 5000 + bank 3000', 7900, (:'pr2'::jsonb->>'remaining')::numeric);
select tt.eq('P2 supplier balance (owed)', 7900, _sup_balance(:'s1'::uuid));
select tt.err('P2 overpay refused', format($$select bill_pay_record('purchase','%s','cash',8000)$$, :'b1'), 'overpaid');

\echo -- landed cost: freight 795 by value (phase97)
select set_rule('landed_cost_mode','"manual"') is null as lm \gset
select landed_save(gen_random_uuid(), null, '{"title":"Freight B1","alloc_method":"value"}'::jsonb, format('[{"type":"bill","id":"%s"}]',:'b1')::jsonb,
  format('[{"charge_type":"freight","amount":795,"alloc_method":"value","pay_mode":"payable","supplier_id":"%s"}]',:'s2')::jsonb) as lsv \gset
select (:'lsv'::jsonb->>'id')::uuid as lc \gset
select landed_preview(array[:'b1'::uuid], '[{"charge_type":"freight","amount":795,"alloc_method":"value"}]'::jsonb, null, 'value', null) as lpv \gset
select tt.t('L1 landed_save returned id', :'lc' is not null, 'draft', :'lsv'::jsonb->>'status');
select landed_post(:'lc'::uuid, gen_random_uuid()) as lpo \gset
select tt.eq('L1 stock added = 795', 795, (:'lpo'::jsonb->>'stock_added')::numeric);
select tt.eq('L1 flour avg (4000+8400+420)/300', 42.7333, tt.avg('RM-F'), 0.0001);
select tt.eq('L1 sugar avg (6000+300)/100', 63, tt.avg('RM-S'));
select tt.eq('L1 box avg (1500+75)/500', 3.15, tt.avg('PK-B'));
select tt.eq('L1 flour qty unchanged', 300, tt.qty('RM-F'));

\echo -- GRN vs bill guard on Salt (source=grn)
select set_rule('forms_post_to_ledger','true') is null as fpl \gset
select set_rule('grn_receipt_source','"grn"') is null as grs \gset
-- phase 552: count-first is ON by default (owner decision 11 Oct 2026), so a goods receipt (13-1) needs its sealed count. This block tests the GRN guard, not the count: count-first is switched off here and back to its default below.
select set_rule('blind_count_on','false') is null as bco \gset
-- guard OFF: GRN 10 kg @20 + bill 10 kg @20 -> hand: 20 kg (double count is the documented risk)
select save_entry(null,'13-1',1,tt.today(),'{"supplier":"Sup Main","lines":[{"item":"RM-SALT","counted":"10","rate":"20","quality":"accept"}]}','[]') ->> 'id' as g1 \gset
select submit_entry(:'g1'::uuid) is not null as sg1 \gset
select decide_entry(:'g1'::uuid, true, null, null, '[]') ->> 'status' as dg1 \gset
select tt.eq('G1 after GRN only salt', 10, tt.qty('RM-SALT'));
select save_purchase(null,null,:'s1'::uuid,1,'B-SALT1',tt.today()-1,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":20}]',tt.iid('RM-SALT'))::jsonb) ->> 'id' as bs1 \gset
select post_purchase(:'bs1'::uuid) is not null as pbs1 \gset
select tt.eq('G1 guard OFF: GRN 10 + bill 10 -> 20 (double count) [default behaviour]', 20, tt.qty('RM-SALT'));
select rule_txt('purchase_grn_guard') as grd0 \gset
\echo GRN_GUARD_DEFAULT_RULE=:grd0
-- guard SKIP: GRN 5 + bill 5 -> +5 only
select set_rule('purchase_grn_guard','"skip"') is null as gs \gset
select save_entry(null,'13-1',1,tt.today(),'{"supplier":"Sup Main","lines":[{"item":"RM-SALT","counted":"5","rate":"20","quality":"accept"}]}','[]') ->> 'id' as g2 \gset
select submit_entry(:'g2'::uuid) is not null as sg2 \gset
select decide_entry(:'g2'::uuid, true, null, null, '[]') ->> 'status' as dg2 \gset
select save_purchase(null,null,:'s1'::uuid,1,'B-SALT2',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":20}]',tt.iid('RM-SALT'))::jsonb) ->> 'id' as bs2 \gset
select post_purchase(:'bs2'::uuid) ->> 'stock_from_grn' as flag \gset
select tt.eq('G2 guard SKIP: GRN 5 + bill 5 -> 25 total (+5, not +10)', 25, tt.qty('RM-SALT'));
select tt.is('G2 bill says stock came from the GRN', 'true', :'flag');
-- guard LINK: bill without link refused, with link posts +7 once
select set_rule('purchase_grn_guard','"link"') is null as gl \gset
select save_entry(null,'13-1',1,tt.today(),'{"supplier":"Sup Main","lines":[{"item":"RM-SALT","counted":"7","rate":"20","quality":"accept"}]}','[]') ->> 'id' as g3 \gset
select submit_entry(:'g3'::uuid) is not null as sg3 \gset
select decide_entry(:'g3'::uuid, true, null, null, '[]') ->> 'status' as dg3 \gset
select save_purchase(null,null,:'s1'::uuid,1,'B-SALT3',tt.today(),format('[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":20}]',tt.iid('RM-SALT'))::jsonb) ->> 'id' as bs3 \gset
select tt.err('G3 guard LINK: bill without GRN link refused', format($$select post_purchase('%s'::uuid)$$, :'bs3'), 'grn_link_required');
select grn_bill_link(:'g3'::uuid, :'bs3'::uuid) is not null as lk \gset
select post_purchase(:'bs3'::uuid) is not null as pbs3 \gset
select tt.eq('G3 guard LINK after link: +7 once -> 32', 32, tt.qty('RM-SALT'));
select set_rule('purchase_grn_guard','"off"') is null as go \gset
select set_rule('grn_receipt_source','"purchase"') is null as grs2 \gset
select set_rule('forms_post_to_ledger',null) is null as fpl2 \gset
select set_rule('blind_count_on',null) is null as bco2 \gset   -- back to the default (ON)

\echo -- auto_cash: bill posts and pays itself (Salt 4 kg @ 20 = 80)
select set_rule('purchase_bill_creates_payment','"auto_cash"') is null as ac \gset
select save_purchase(null,null,:'s1'::uuid,1,'B-SALT4',tt.today(),format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":20}]',tt.iid('RM-SALT'))::jsonb) ->> 'id' as bs4 \gset
select post_purchase(:'bs4'::uuid) is not null as pbs4 \gset
select tt.eq('A1 auto_cash: bill 80 paid in cash at posting', 80, (select paid from purchase_bills where id=:'bs4'::uuid));
select tt.eq('A1 one auto payment record', 1, (select count(*) from bill_payments99 where bill_ref=:'bs4' and origin='auto'));
select set_rule('purchase_bill_creates_payment','"ask"') is null as ac2 \gset
-- GRN guard-less sale of tolerance: salt total = 36
select tt.eq('A1 salt qty 32+4', 36, tt.qty('RM-SALT'));
