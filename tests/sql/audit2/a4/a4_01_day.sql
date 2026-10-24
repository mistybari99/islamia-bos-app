\echo == A4-01 setup + one business day D (= yesterday, Asia/Dhaka)
-- users: owner (o), seller (sp), buyer (bu)
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@a4.app','{"full_name":"Owner"}'),(:'sp','seller@a4.app','{"full_name":"Seller"}'),(:'bu','buyer@a4.app','{"full_name":"Buyer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'sp','salesperson'),(:'bu','purchasing') on conflict do nothing;
insert into user_locations values (:'sp',1),(:'bu',1) on conflict do nothing;
select tt.as(:'o');
select set_rule('accounting_on','true') is null as a1 \gset
select set_user_grant(:'sp'::uuid,'sale_return') is null as g1 \gset
select set_user_grant(:'bu'::uuid,'supplier_pay') is null as g2 \gset
select set_user_grant(:'sp'::uuid,'sale_void') is null as g3 \gset
select set_user_grant(:'sp'::uuid,'cash_move') is null as g4 \gset
select (tt.today()-1) as dd \gset
select (tt.today()-1)::text as dds \gset
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FG-X','X','Item X','pc','pc','finished_good',true,100,true) on conflict do nothing;
select acct_set_start(tt.today()-5) is not null as st \gset
select stock_opening(tt.iid('FG-X'),1,100,60) is not null as so \gset
-- opening journal: cash 20000, bank 50000, inventory FG 6000 = capital 76000
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"1120","debit":50000,"location_id":1},{"code":"1310","debit":6000,"location_id":1},{"code":"3100","credit":76000}]'::jsonb)->>'id' as oj \gset
select tt.t('S0 opening posted', :'oj' is not null);
insert into customers (mobile,name,type) values ('01700000001','Cust One','retail') returning id as c1 \gset
insert into customers (mobile,name,type) values ('01700000002','Cust Two','retail') returning id as c2 \gset
with s as (insert into suppliers (name, credit_days) values ('Sup A4', null) returning id) select id as s1 from s \gset
-- timestamps on day D (Dhaka)
select ((:'dds'||' 12:00:00+06')::timestamptz) as t12 \gset
select ((:'dds'||' 00:30:00+06')::timestamptz) as t0030 \gset
select tt.as(:'sp');
-- 1 cash sale 3x100 = 300
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as s1id \gset
-- 2 card sale 2x100 = 200
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"card","amount":200}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as s2id \gset
-- 3 mobile-wallet sale 1x100 = 100
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"mobile","amount":100,"wallet":"bkash","ref":"TX1"}]',null,null,'retail',null,false,:'t12'::timestamptz)->>'id' as s3id \gset
-- 3b bank transfer mode at POS (expected: refused, bad_mode)
select tt.err('S3b POS payment mode bank refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":100}]'::jsonb,0,'[{"mode":"bank","amount":100}]',null,null,'retail',null,false)$$, tt.iid('FG-X')), 'bad_mode');
-- 4 due sale: 4x100 - discount 20 = 380, paid cash 80, due 300 (Cust One)
select tt.as(:'o');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":100}]',tt.iid('FG-X'))::jsonb,20,'[{"mode":"cash","amount":80}]','01700000001','Cust One','retail',null,false,:'t12'::timestamptz)->>'id' as s4id \gset
select tt.as(:'sp');
-- 6 midnight sale: 00:30 Dhaka on D (= 18:30 UTC of D-1) cash 100
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false,:'t0030'::timestamptz)->>'id' as s6id \gset
select tt.as(:'o');
-- 5 advance 500 cash from Cust Two, then due sale 2x100 = 200, then advance used 200
select cash_move_add(1,'cust_advance',500,:'dd'::date,'cash',:'c2'::uuid,null,'adv',gen_random_uuid()) ->> 'id' as adv1 \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('FG-X'))::jsonb,0,'[]','01700000002','Cust Two','retail',null,false,:'t12'::timestamptz)->>'id' as s5id \gset
select tt.as(:'o');
select cash_move_add(1,'cust_advance_used',200,:'dd'::date,null,:'c2'::uuid,null,'adv used',gen_random_uuid()) ->> 'id' as adv2 \gset
-- 6 return 1 unit of sale 1, refunded in cash (100)
select sale_return(gen_random_uuid(), :'s1id'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-X'))::jsonb, 'damaged','a4 return','cash') as ret1 \gset
-- 7 expenses: 10-2 voucher transport 150 paid by BANK (pay_mode), voucher repair 70 (cash, no pay_mode), quick expense transport 50 cash
select save_entry(null,'11-1',1,:'dd'::date,'{"pay_mode":"bank","lines":[{"head":"transport","to":"courier","receipt":"yes","amount":"150"}]}','[]') ->> 'id' as v1 \gset
select submit_entry(:'v1'::uuid) is not null as sv1 \gset
select decide_entry(:'v1'::uuid, true, null, null, '[]') ->> 'status' as dv1 \gset
select save_entry(null,'11-1',1,:'dd'::date,'{"lines":[{"head":"repair","to":"fixer","receipt":"yes","amount":"70"}]}','[]') ->> 'id' as v2 \gset
select submit_entry(:'v2'::uuid) is not null as sv2 \gset
select decide_entry(:'v2'::uuid, true, null, null, '[]') ->> 'status' as dv2 \gset
select tt.is('S7 vouchers approved', 'approved/approved', :'dv1'||'/'||:'dv2');
select quick_expense_add(1, :'dd'::date, 'transport', 'rickshaw', 50, 'cash', true, 'a4 quick', gen_random_uuid()) ->> 'id' as qe \gset
-- 8 purchase bill 10 x 60 = 600 on D (payable), supplier payment 300 by bank (paid_at = now, i.e. day D+1 = today)
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'A4-B1',:'dd'::date,format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":60}]',tt.iid('FG-X'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select tt.as(:'bu');
select pay_supplier(:'s1'::uuid,1,'[{"mode":"bank","amount":300}]'::jsonb,gen_random_uuid(),'a4 pay') as ps \gset
select tt.as(:'o');
-- 9 cash deposit to bank 400 on D
select cash_move_add(1,'bank_deposit',400,:'dd'::date,null,null,null,'dep',gen_random_uuid()) ->> 'id' as dep \gset
-- 10 drawer closing form 14-1 for D: float 1000, typed day figures, cash counted 1770 (expected 1780 => shortage 10)
select tt.as(:'o');
select save_entry(null,'06-1',1,:'dd'::date,'{"open_counted":1000,"total_entered":1180,"d_card":200,"d_bkash":100,"dues":0,"new_adv":500,"prior_adv":0,"refund":100,"credit_sales":500,"cash_count":{"n1000":1,"n500":1,"n200":1,"n50":1,"n20":1}}','[]') ->> 'id' as dr \gset
select count_save(:'dr'::uuid,'drawer','{"n1000":1,"n500":1,"n200":1,"n50":1,"n20":1}'::jsonb) as cnt \gset
\echo DRAWER_COUNT: :cnt
-- 11 card settlement NEXT DAY (today): gross 200, fee 4 (2%)
select tt.as(:'o');
select card_settle(1, tt.today(), 200, 4, 'batch D', gen_random_uuid()) as cs \gset
select acct_post_pending(false) as pp \gset
\echo POST_PENDING: :pp
select acct_post_pending(false)->>'posted' as pp2 \gset
select tt.eq('G0 second pending run posts nothing', 0, :'pp2'::numeric);
select tt.eq('G0 no unbalanced journal entry', 0, tt.unbalanced());
