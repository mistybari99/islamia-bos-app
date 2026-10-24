-- AUDIT2 / A3  real profit scenario.  Hand-computed expectations are written BEFORE the system is asked (columns "exp").
-- Places: 2 = showroom S1, 3 = showroom S2, 6 = factory F, 1 = main centre (cost_attrib_main).   Everything happens on ONE day (today), so period cut-offs are tested at the end.
-- Product A (sweet_kg): made in F, 2 batches x 10 kg: flour 6 kg x 40 + sugar 3 kg x 20 = 300 raw + labour component 100 per batch -> unit cost (300+100)/10 = 40.  sell 100/kg
-- Product B (resale, cost 50, sell 90) only in S1 ; product C (resale, NO cost known, sell 100) only in S1.
\set ON_ERROR_STOP off
\echo == A3 setup
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@a3.app','{"full_name":"Owner"}'),(:'ap','approver@a3.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'ap',6) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false,null),('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false,null),
 ('FG-A','Sweet A','Sweet A','kg','kg','finished_good',true,100,true,'sweet_kg'),
 ('RS-B','Item B','Item B','pc','pc','resale',true,90,true,'cake_pc'),
 ('RS-C','Item C nocost','Item C nocost','pc','pc','resale',true,100,true,'cake_pc') on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('RM-F'),6,100,40) is not null as a1 \gset
select stock_opening(tt.iid('RM-S'),6,100,20) is not null as a2 \gset
select stock_opening(tt.iid('RS-B'),2,10,50) is not null as a3 \gset
select stock_opening(tt.iid('RS-C'),2,5,null) is not null as a4 \gset
select acct_opening('[{"code":"1110","debit":10000,"location_id":1},{"code":"3100","credit":10000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a_on \gset
select set_rule('accounting_autopost','true') is null as a_on2 \gset
select (recipe_save(null, tt.iid('FG-A'), 10, 'kg', 'A v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select loc_cost_cfg_set(6,'recipe') is null as lc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_batch',100,null,null,'labour',gen_random_uuid()) is not null as cc \gset
select tt.as(:'ap'); select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'o');
select production_post(6, :'rc'::uuid, 2, gen_random_uuid()) as pj \gset
select tt.eq('P0 factory unit cost of A = (300+100)/10', 40, tt.avg('FG-A',6), 0.0005);
select (stock_transfer(6,2,tt.iid('FG-A'),10,null,'t1')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 10, null) is not null as r1 \gset
select (stock_transfer(6,3,tt.iid('FG-A'),10,null,'t2')->>'id')::uuid as t2 \gset
select stock_receive_transfer(:'t2'::uuid, 10, null) is not null as r2 \gset
select tt.eq('P0 S1 stock of A 10 @ 40', 40, tt.avg('FG-A',2), 0.0005);
select tt.eq('P0 S2 stock of A 10 @ 40', 40, tt.avg('FG-A',3), 0.0005);

\echo == A3 sales / return / wastage / fee / expenses
-- S1 sale1: A 5 kg x 100 = 500, discount 50 -> 450 cash
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":5,"price":100}]',tt.iid('FG-A'))::jsonb,50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,false) as s1 \gset
select (:'s1'::jsonb->>'id')::uuid as sale1 \gset
select tt.eq('X1 sale1 total (500-50)', 450, (:'s1'::jsonb->>'total')::numeric);
-- S1 sale2: B 4 x 90 = 360 by card
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":90}]',tt.iid('RS-B'))::jsonb,0,'[{"mode":"card","amount":360}]',null,null,'retail',null,false) as s2 \gset
-- S1 sale3: C 2 x 100 = 200 cash, C has no cost anywhere
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('RS-C'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false) as s3 \gset
-- S2 sale4: A 8 kg x 100 = 800, discount 160 (20 %) -> 640 cash
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":8,"price":100}]',tt.iid('FG-A'))::jsonb,160,'[{"mode":"cash","amount":640}]',null,null,'retail',null,false) as s4 \gset
select tt.eq('X1 sale4 total (800-160)', 640, (:'s4'::jsonb->>'total')::numeric);
-- return of 1 kg A from sale1: refund = 1 x 100 x 450/500 = 90
select sale_return(gen_random_uuid(), :'sale1'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-A'))::jsonb, 'damaged','a3 return','cash') as rt \gset
select tt.eq('X2 return amount keeps the discount share (90, not 100)', 90, (:'rt'::jsonb->>'amount')::numeric);
-- wastage 1 kg A at S2 (cost 40)
select stock_wastage(tt.iid('FG-A'),3,1,'spoiled','a3 waste') is not null as wg \gset
-- card settlement S1: gross 360 fee 7.20 (2 %)
select card_settle(2, tt.today(), 360, 7.2, 'a3 batch', gen_random_uuid()) is not null as cs \gset
-- salary: S1 300 (booked to showroom 1), factory 200 ; sheet 02-2 is what the P&L reads
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('21-1',2,8101,tt.today(),'approved','{"pay":[{"name":"S1 Clerk - Clerk","due":300}]}','[]',:'o','st'),
 ('21-1',6,8102,tt.today(),'approved','{"pay":[{"name":"F Cook - Cook","due":200}]}','[]',:'o','st');
-- operating costs: S1 rent 150 (quick expense, head rent), S2 delivery 40 (head transport)
select quick_expense_add(2, tt.today(), 'rent', 'landlord', 150, 'cash', true, 'a3 rent S1', gen_random_uuid()) is not null as q1 \gset
select quick_expense_add(3, tt.today(), 'transport', 'rider', 40, 'cash', true, 'a3 delivery S2', gen_random_uuid()) is not null as q2 \gset

\echo == A3 shared cost bills (electricity headcount 2:1, internet fixed 70:30, admin share of S1 -> main centre)
select cost_source_save(null,'electricity','Utility Co','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'a3',gen_random_uuid())->>'id' as es \gset
select cost_rule_save(:'es'::bigint,'headcount',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":2},{"location_id":3,"dest":"showroom","value":1}]'::jsonb,'a3',gen_random_uuid())->>'id' as er \gset
select cost_rule_approve(:'er'::bigint,'ok') is not null as era \gset
select cost_bill_add(:'es'::bigint,'month',date_trunc('month',tt.today())::date,600,'cash','E-1',tt.today(),false,null,null,gen_random_uuid()) as eb \gset
select cost_source_save(null,'internet','ISP','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'a3',gen_random_uuid())->>'id' as is_ \gset
select cost_rule_save(:'is_'::bigint,'fixed_percent',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":70},{"location_id":3,"dest":"showroom","value":30}]'::jsonb,'a3',gen_random_uuid())->>'id' as ir \gset
select cost_rule_approve(:'ir'::bigint,'ok') is not null as ira \gset
select cost_bill_add(:'is_'::bigint,'month',date_trunc('month',tt.today())::date,300,'cash','I-1',tt.today(),false,null,null,gen_random_uuid()) as ib \gset
select cost_source_save(null,'other','Accounts software','separate','admin',array[2],'monthly',date_trunc('month',tt.today())::date,'a3 admin',gen_random_uuid())->>'id' as ads \gset
select cost_bill_add(:'ads'::bigint,'month',date_trunc('month',tt.today())::date,120,'cash','A-1',tt.today(),false,null,null,gen_random_uuid()) as ab \gset
select tt.eq('B1 electricity shares sum to bill', 600, (select sum(amount) from cost_bill_shares where bill_id=(:'eb'::jsonb->>'id')::bigint and active));
select tt.eq('B1 electricity S1 share 2/3 of 600', 400, (select amount from cost_bill_shares where bill_id=(:'eb'::jsonb->>'id')::bigint and active and location_id=2));
select tt.eq('B1 internet S1 share 70 % of 300', 210, (select amount from cost_bill_shares where bill_id=(:'ib'::jsonb->>'id')::bigint and active and location_id=2));
select tt.err('B2 sales-share allocation method is not offered', format($$select cost_rule_save(%s,'sales_share',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom"},{"location_id":3,"dest":"showroom"}]'::jsonb,'x',gen_random_uuid())$$,:'es'), 'bad_value');
\echo == A3 post to books
select acct_post_pending(false) is not null as pp \gset

\echo == A3 FIGURES THE SYSTEM SHOWS (cost-attribution switch OFF)
select tt.as(:'o');
\echo -- biz_daily  (loc, n, revenue, discount, costed_rev, cogs)
select 'biz_daily', location_id, n, revenue, discount, costed_rev, cogs from biz_daily(tt.today(), tt.today(), null) order by location_id;
\echo -- _p27_pl  (loc, gross, ret, net, costed, cogs, exp, sal, fixed)
select '_p27_pl', o_loc, o_gross, o_ret, o_net, o_costed, o_cogs, o_exp, o_sal, o_fixed from _p27_pl(tt.today(), tt.today(), array[1,2,3,6]) order by o_loc;
\echo -- shop P&L report row (_r3q_l3_shop_pnl)
select '_r3q_l3', (x->>'location_id'), x->>'net_sales', x->>'cogs', x->>'expenses', x->>'salary', x->>'profit', x->>'profit_pct', x->>'uncosted_pct', x->>'gaps', x->>'row_type' from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x order by 2,11;
\echo -- biz_items  (code, qty, revenue, cogs)
select 'biz_items', code, qty, revenue, cogs from biz_items(tt.today(), tt.today(), null) where revenue>0 order by code;
select 'biz_items_S1', code, qty, revenue, cogs from biz_items(tt.today(), tt.today(), 2) where revenue>0 order by code;
\echo -- biz_items_by_category
select 'by_cat', category, items, revenue, cogs, cogs_unknown_items from biz_items_by_category(tt.today(), tt.today(), null, 'category') order by category;
\echo -- margin report by item (_r3q_l2_margin)
select '_r3q_l2', x->>'level', x->>'item_code', x->>'category', x->>'revenue', x->>'cogs', x->>'margin', x->>'margin_pct', x->>'uncosted_pct' from _r3q_l2_margin(tt.today(), tt.today(), array[2,3], '{}'::jsonb) x order by 2,3;
\echo -- brand_pnl
select 'brand_pnl', brand_code, revenue, discount, costed_rev, cogs, gross_profit, gp_pct from brand_pnl(tt.today(), tt.today(), null);
\echo -- acct_income_statement per loc: total_income total_expense cogs gross_profit net_profit
select 'gl_all', (acct_income_statement(tt.today(), tt.today(), null)) - 'income' - 'expense' as j;
select 'gl_S1', (acct_income_statement(tt.today(), tt.today(), 2)) - 'income' - 'expense' as j;
select 'gl_S2', (acct_income_statement(tt.today(), tt.today(), 3)) - 'income' - 'expense' as j;
select 'gl_F', (acct_income_statement(tt.today(), tt.today(), 6)) - 'income' - 'expense' as j;
select 'gl_lines_S1', a.code, a.name_en, (x->>'amount') from jsonb_array_elements(acct_income_statement(tt.today(), tt.today(), 2)->'income') x join coa_accounts a on a.id=(x->>'id')::bigint order by 2;
select 'gl_lines_S1x', a.code, a.name_en, (x->>'amount') from jsonb_array_elements(acct_income_statement(tt.today(), tt.today(), 2)->'expense') x join coa_accounts a on a.id=(x->>'id')::bigint order by 2;
select 'gl_lines_S2x', a.code, a.name_en, (x->>'amount') from jsonb_array_elements(acct_income_statement(tt.today(), tt.today(), 3)->'expense') x join coa_accounts a on a.id=(x->>'id')::bigint order by 2;
\echo -- profit_source_check
select 'psc', (profit_source_check(tt.today(), tt.today(), null)) as j;
\echo -- branch_cost_view (switch off)
select 'bcv', branch_cost_view(date_trunc('month',tt.today())::date, null)->'totals' as j;

\echo == A3 PART 2: cost attribution (switch cost_attrib_in_pl) ======================================
select cost_attrib_main_set(1, date_trunc('month',tt.today())::date, 'a3 main centre', gen_random_uuid()) is not null as m1 \gset
select cost_attrib_set(2, null, 'showroom', date_trunc('month',tt.today())::date, 'a3', gen_random_uuid()) is not null as c1 \gset
select cost_attrib_set(3, null, 'showroom', date_trunc('month',tt.today())::date, 'a3', gen_random_uuid()) is not null as c2 \gset
select cost_attrib_set(2, 'other', 'main_centre', date_trunc('month',tt.today())::date, 'a3 admin to head office', gen_random_uuid()) is not null as c3 \gset
\echo -- branch_cost_view after the settings, switch still OFF
select 'bcv_off', branch_cost_view(date_trunc('month',tt.today())::date, null)->>'in_pl' as in_pl, branch_cost_view(date_trunc('month',tt.today())::date, null)->'totals' as j;
\echo -- shop P&L rows with switch OFF (cost shares must be absent)
select 'l3_off', count(*) filter (where x->>'row_type'='cost_share') as share_rows from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x;
select set_rule('cost_attrib_in_pl','true') is null as sw \gset
select '_r3q_l3_on', (x->>'location_id') loc, x->>'location_en', x->>'expenses', x->>'profit', x->>'row_type', x->>'cost_share_dest' from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x order by 2,6;
\echo -- partner_calculate base after switch ON: does it include the shares?   (use a location venture)
select ('x')::text as dummy \gset
select 'pnl_1m', o_loc, o_exp, o_sal from _p27_pl(tt.today(), tt.today(), array[2,3]) order by 2;

\echo -- re-assign the S1 admin share (120) from main centre to showroom S2 (audited)
select s.id as admin_share from cost_bill_shares s where s.bill_id=(:'ab'::jsonb->>'id')::bigint and s.active \gset
select 'dest_before', dkind, dloc from _c78_dest(:'admin_share'::bigint, date_trunc('month',tt.today())::date);
select cost_share_reassign(:'admin_share'::bigint,'location',3,'a3 move to S2', gen_random_uuid()) as ra \gset
select 'dest_after', dkind, dloc from _c78_dest(:'admin_share'::bigint, date_trunc('month',tt.today())::date);
select 'audit_reassign_rows', count(*) from cost_share_reassign where share_id=:'admin_share'::bigint;
select 'audit_log_rows', count(*) from audit_log where table_name in ('cost_share_reassign','location_cost_attribution','cost_attrib_main');
select 'l3_after_reassign', x->>'location_id' loc, x->>'expenses', x->>'row_type', x->>'cost_share_dest' from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[2,3], '{}'::jsonb) x where x->>'row_type'='cost_share' order by 2,4;

\echo -- re-assign again after the period was closed? (period lock)
\echo -- history: cost_attrib_set for a PAST month is refused (cannot restate) 
select tt.err('H1 attribution setting for a past month refused', $$select cost_attrib_set(3,'other','showroom',(date_trunc('month',tt.today())-interval '1 month')::date,'late fix',gen_random_uuid())$$, 'effective_in_past');
\echo -- partner base: venture on location 2
select 'partner_tables', table_name from information_schema.tables where table_schema='public' and table_name like 'partner_%' order by 2;

\echo == A3 PART 3: product x branch, partner base, period cut-off, card fee/waste placement ====
\echo -- product profit per branch from the report builder (item_sales group item, one location at a time)
select 'rb_S1', r->>'item_code', r->>'net', r->>'cogs', r->>'gp', r->>'gp_pct', r->>'uncosted_pct' from jsonb_array_elements(report_run('item_sales', jsonb_build_object('from',tt.today(),'to',tt.today(),'locations',array[2]), 'item', null, 1, false)->'rows') r order by 2;
select 'rb_S2', r->>'item_code', r->>'net', r->>'cogs', r->>'gp', r->>'gp_pct' from jsonb_array_elements(report_run('item_sales', jsonb_build_object('from',tt.today(),'to',tt.today(),'locations',array[3]), 'item', null, 1, false)->'rows') r order by 2;
select 'rb_by_location', r->>'location_id', r->>'net', r->>'cogs', r->>'gp' from jsonb_array_elements(report_run('item_sales', jsonb_build_object('from',tt.today(),'to',tt.today()), 'location', null, 1, false)->'rows') r order by 2;
\echo -- dashboard tiles (dashx_metrics.js formulas replayed in SQL on the same RPCs)
select 'dash_gross_profit', sum(costed_rev - cogs) as gp, sum(costed_rev) as rev, round(100*sum(costed_rev - cogs)/nullif(sum(costed_rev),0),2) as gm_pct from biz_daily(tt.today(), tt.today(), null);
select 'dash_net_profit_books', (acct_income_statement(tt.today(), tt.today(), null)->>'net_profit')::numeric as net_profit, (acct_income_statement(tt.today(), tt.today(), null)->>'total_expense')::numeric as total_expense, (acct_income_statement(tt.today(), tt.today(), null)->>'provisional') as provisional;
select 'margin_S1', x->>'item_code', x->>'revenue', x->>'cogs', x->>'margin' from _r3q_l2_margin(tt.today(), tt.today(), array[2], '{}'::jsonb) x where x->>'level'='item' order by 2;
select 'margin_S2', x->>'item_code', x->>'revenue', x->>'cogs', x->>'margin' from _r3q_l2_margin(tt.today(), tt.today(), array[3], '{}'::jsonb) x where x->>'level'='item' order by 2;

\echo -- partner statement base for a venture on place 2 (net_profit)
select partner_party_save(null,'Owner Party','company',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_venture_save(null,'S1','Showroom S1','location',2,'own','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v2 \gset
select partner_agreement_save(null, :'v2'::bigint, 'a3 deed', date_trunc('month',tt.today())::date, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as ag \gset
select partner_agreement_party_set(:'ag'::bigint,:'pa'::bigint,'owner',100,'n') is not null as x1 \gset
select partner_rule_save(:'ag'::bigint,null,'Base','base','{"base":"net_profit"}') is not null as x2 \gset
select partner_rule_save(:'ag'::bigint,null,'Split','split','{"shares":[{"role":"owner","percent":100}]}') is not null as x3 \gset
select partner_agreement_activate(:'ag'::bigint) is not null as x4 \gset
select 'partner_S1', (partner_calculate(:'ag'::bigint, tt.today(), tt.today()) -> 'bases') as bases, (partner_calculate(:'ag'::bigint, tt.today(), tt.today()) -> 'warnings') as warns;

\echo -- period cut-off: a day with NO activity (yesterday, same month) - what does the shop P&L show?
select 'yday_l3', x->>'location_en', x->>'expenses', x->>'profit', x->>'row_type' from _r3q_l3_shop_pnl(tt.today()-1, tt.today()-1, array[1,2,3,6], '{}'::jsonb) x order by 2;
\echo -- the same cost shares in a one-day report and in a whole-month report (not pro-rated)
select 'shares_1day', round(sum((x->>'expenses')::numeric),2) from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x where x->>'row_type'='cost_share';
select 'shares_month', round(sum((x->>'expenses')::numeric),2) from _r3q_l3_shop_pnl(date_trunc('month',tt.today())::date, (date_trunc('month',tt.today())+interval '1 month - 1 day')::date, array[1,2,3,6], '{}'::jsonb) x where x->>'row_type'='cost_share';
\echo -- a quick expense dated yesterday is outside a today-only report
select quick_expense_add(2, tt.today()-1, 'transport', 'x', 25, 'cash', true, 'yday', gen_random_uuid()) is not null as q3 \gset
select 'exp_today_only', o_exp from _p27_pl(tt.today(), tt.today(), array[2]);
select 'exp_two_days', o_exp from _p27_pl(tt.today()-1, tt.today(), array[2]) order by o_m;

\echo -- consistency sums (switch ON, shares included)
select 'sum_branch_profit_with_shares', round(sum((x->>'profit')::numeric),2) from _r3q_l3_shop_pnl(tt.today(), tt.today(), array[1,2,3,6], '{}'::jsonb) x;
select 'gl_company_net', (acct_income_statement(tt.today(), tt.today(), null)->>'net_profit')::numeric;
select 'sum_gl_by_loc', round(sum((acct_income_statement(tt.today(), tt.today(), l)->>'net_profit')::numeric),2) from unnest(array[1,2,3,6]) l;
select 'sum_p27_profit', round(sum(o_net - o_cogs - coalesce(o_exp,0) - coalesce(o_sal,0) - coalesce(o_fixed,0)),2) from _p27_pl(tt.today(), tt.today(), array[1,2,3,6]);
\echo -- product sums vs branch revenue
select 'sum_biz_items', round(sum(revenue),2), round(sum(cogs),2) from biz_items(tt.today(), tt.today(), null);
select 'sum_biz_daily', round(sum(revenue),2), round(sum(cogs),2) from biz_daily(tt.today(), tt.today(), null);
select 'sum_margin_items', round(sum((x->>'revenue')::numeric),2), round(sum((x->>'cogs')::numeric),2) from _r3q_l2_margin(tt.today(), tt.today(), array[2,3,6], '{}'::jsonb) x where x->>'level'='item';

\echo -- GL after the cost-share reassign: nothing moves in the books (shares are report-only)
select 'gl_S1_after', acct_income_statement(tt.today(), tt.today(), 2)->>'net_profit' ;
select 'gl_S2_after', acct_income_statement(tt.today(), tt.today(), 3)->>'net_profit' ;
\echo -- settings table of the location (fixed cost per month) and what the report does with it
select location_settings_exists from (select to_regclass('public.location_settings') is not null as location_settings_exists) z;
