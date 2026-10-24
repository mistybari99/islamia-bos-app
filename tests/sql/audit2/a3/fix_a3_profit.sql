-- A3 FIX probes (gap closure by phase112/117, written after the fixes; the old a3_probes.sql keep their old-name checks).
-- Appended after a3_probes.sql, same psql session, same scenario data.  Each probe asserts the hand-computed number of
-- docs/audit2/A3_real_profit.md section 2/3 with whatever switches the DB has (defaults = OFF -> FAIL = gap open by default;
-- switches_on.txt = ON -> PASS = closed).  Labels start with "FX3-".  Switches used: profit_truth_mode, cost_share_prorate_mode, items_net_of_returns.
\echo == A3 FIX PROBES (assert the corrected behaviour with the batch switches as configured)
select tt.as(:'o');
select date_trunc('month',tt.today())::date as fm1, (date_trunc('month',tt.today())+interval '1 month - 1 day')::date as fm2,
       extract(day from (date_trunc('month',tt.today())+interval '1 month - 1 day'))::int as fdim \gset
create or replace function tt.safe_num(p_sql text) returns numeric language plpgsql as $$ declare v numeric; begin execute p_sql into v; return v; exception when others then return null; end $$;
-- shares must be active for the per-place figures; the scenario left cost_attrib_in_pl as the scenario wants it
-- G1 / G5: profit_truth112 = ONE figure per place and for the company (hand: S1 720-360-150-300-7.20-610, S2 640-320-40-40-290, factory -200, main -120)
select tt.eq('FX3-G1 S1 net profit = 720 - 360 - rent 150 - salary 300 - card fee 7.20 - shares 610 - transport 25 (A3 scenario q3)', -732.20, tt.safe_num(format($q$select (r->>'profit')::numeric from jsonb_array_elements(profit_truth112('%s'::date,'%s'::date,null)->'rows') r where r->>'location_id'='2'$q$, :'fm1', :'fm2')));
select tt.eq('FX3-G1 S2 net profit = 640 - 320 - delivery 40 - wastage 40 - shares 290 - admin 120 moved to S2 by the scenario reassign', -170, tt.safe_num(format($q$select (r->>'profit')::numeric from jsonb_array_elements(profit_truth112('%s'::date,'%s'::date,null)->'rows') r where r->>'location_id'='3'$q$, :'fm1', :'fm2')));
select tt.eq('FX3-G1 factory = salary 200 loss (0 when factory_labour_absorbed117 is on: labour already in product cost, A3 gap 5)', case when coalesce((select coalesce(value,default_value) from rules where key='factory_labour_absorbed117'),'false'::jsonb)='true'::jsonb then 0 else -200 end, tt.safe_num(format($q$select (r->>'profit')::numeric from jsonb_array_elements(profit_truth112('%s'::date,'%s'::date,null)->'rows') r where r->>'location_id'='6'$q$, :'fm1', :'fm2')));
select tt.eq('FX3-G1 company net profit = sum of the place rows (-1102.20, +200 when the factory salary is absorbed)', -1102.20 + case when coalesce((select coalesce(value,default_value) from rules where key='factory_labour_absorbed117'),'false'::jsonb)='true'::jsonb then 200 else 0 end, tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'net_profit')::numeric$q$, :'fm1', :'fm2')));
select tt.eq('FX3-G1 shop P&L rows (shares inside the place) sum to the same company figure', -1102.20 + case when coalesce((select coalesce(value,default_value) from rules where key='factory_labour_absorbed117'),'false'::jsonb)='true'::jsonb then 200 else 0 end, (select sum((x->>'profit')::numeric) from _r3q_l3_shop_pnl(:'fm1',:'fm2',array[1,2,3,6],'{}'::jsonb) x));
-- G5: revenue of item C with no cost is shown apart, not as 100 % margin
select tt.eq('FX3-G5 uncosted revenue shown apart (item C 2 x 100)', 200, tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'uncosted_rev')::numeric$q$, :'fm1', :'fm2')));
select tt.t('FX3-G5 statement flagged provisional while a sold item has no cost', coalesce((select (j->>'provisional')::boolean from (select (case when exists (select 1 from pg_proc where proname='profit_truth112') then profit_truth112(:'fm1',:'fm2',null) end) j) z), false));
-- G3 / G4 (inside the single statement): wastage 1 kg x 40, card fee 7.20
select tt.eq('FX3-G3 wastage 40 reaches the branch profit', 40, tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'wastage')::numeric$q$, :'fm1', :'fm2')));
select tt.eq('FX3-G4 card fee 7.20 reaches the branch profit', 7.20, tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'card_fees')::numeric$q$, :'fm1', :'fm2')));
-- G8: pro-rated shares (hand: whole month of shares 1020, one day = 1020 / days in month)
select tt.eq('FX3-G8 one-day report: cost shares attributed = 1020 / days in month', round(1020::numeric / :fdim, 2), tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'overheads_attributed')::numeric$q$, tt.today(), tt.today())), 0.05);
select tt.eq('FX3-G8 whole-month report keeps the whole 1020', 1020, tt.safe_num(format($q$select (profit_truth112('%s'::date,'%s'::date,null)->'company'->>'overheads_attributed')::numeric$q$, :'fm1', :'fm2')), 0.05);
-- G9: returns netted in the product report (hand: A 1090 - 90 refund = 1000; all items 1650 - 90 = 1560 = biz_daily)
select tt.eq('FX3-G9 FG-A revenue net of the 90 return', 1000, (select revenue from biz_items(:'fm1',:'fm2',null) where code='FG-A'));
select tt.eq('FX3-G9 sum of biz_items revenue = biz_daily revenue (1560)', (select sum(revenue) from biz_daily(:'fm1',:'fm2',null)), (select sum(revenue) from biz_items(:'fm1',:'fm2',null)));
-- G2: salary sits in the sheet (02-2) AND in the payroll app: hand = app 1000 paid in the month for S2, sheet 400 for the same month and place
--     (the A3 scenario's own S1 sheet has no month/year keys, so the pair is built on S2 with a proper monthly sheet, as the form does)
insert into employees (employee_no, full_name_bn) values ('FX3E','Staff One') returning id as fx_emp \gset
with x as (insert into payroll_runs (month, location_id, status) values (date_trunc('month', tt.today())::date, 3, 'approved') returning id) select id as fx_run from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, net, advance_recovery, gross) values (:'fx_run', date_trunc('month', tt.today())::date, :'fx_emp', 3, 1000, 0, 1000) returning id) select id as fx_ln from x \gset
select payroll_pay(:'fx_run'::bigint, array[:'fx_ln'::bigint], 'cash', tt.today(), 'fx3', null, gen_random_uuid(), 1000) is not null as fx_pay \gset
select format('{"month":"%s","year":"%s","pay":[{"name":"S2 Clerk - Clerk","due":400}]}', extract(month from tt.today())::int, extract(year from tt.today())::int) as fx_sheetdata \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values ('21-1',3,8193,tt.today(),'approved',:'fx_sheetdata'::jsonb,'[]',:'o','st');
select id as fx_sheet from entries where form_code='21-1' and serial=8193 \gset
select tt.t('FX3-G2 S2 salary is ONE of the two records (1000 app or 400 sheet), never 1400',
  coalesce(tt.safe_num(format($q$select (r->>'salary')::numeric from jsonb_array_elements(profit_truth112('%s'::date,'%s'::date,3)->'rows') r where r->>'location_id'='3'$q$, :'fm1', :'fm2')) in (1000, 400), false));
select tt.t('FX3-G2 the sheet and the app record were linked as one expense by the system (shadow_links)',
  exists (select 1 from shadow_links x where x.state <> 'void' and ((x.shadow_type='entries' and x.shadow_id=:'fx_sheet'::text) or (x.shadow_type='payroll_runs' and x.shadow_id=:'fx_run'::text))));
