\echo == 07 shadow engine: same expense via quick entry and form 11-1
select tt.as(:'o');
select bal_before from (select tt.bal('5700') as bal_before) z \gset
select (quick_expense_add(1, tt.today(), 'transport', 'rickshaw', 300, 'cash', true, 'e2e transport', gen_random_uuid())) as qe \gset
\echo QUICK_EXPENSE: :qe
select count(*) as pend from shadow_links where state='pending' \gset
select tt.eq('H1 quick entry creates one pending shadow link for form 11-1', 1, :pend);
select save_entry(null,'11-1',1,tt.today(),'{"lines":[{"head":"transport","to":"rickshaw","receipt":"yes","amount":"300"}]}','[]') ->> 'id' as f102 \gset
select submit_entry(:'f102'::uuid) is not null as sub \gset
select decide_entry(:'f102'::uuid, true, null, null, '[]') ->> 'status' as dec \gset
select tt.is('H1 form 11-1 approved', 'approved', :'dec');
select id as lnk from shadow_links where state='pending' limit 1 \gset
select shadow_confirm(:lnk, :'f102') ->> 'state' as sc \gset
select tt.is('H1 shadow link confirmed to the form', 'confirmed', :'sc');
select acct_post_pending(false) as pp9 \gset
\echo POST_PENDING_9: :pp9
select tt.eq('H2 transport 5700 debit after posting: ONE 300 (not 600)', 300, tt.bal('5700') - :bal_before::numeric);
select tt.eq('H2 quick_expense journal entries', 1, (select count(*) from journal_entries where source_type='quick_expense' and reverses_id is null));
select shadow_count_once_check() as sco \gset
select tt.eq('H2 count-once check: shadow docs found in the journal', 0, jsonb_array_length(:'sco'::jsonb->'shadow_in_journal'));
select tt.eq('H2 count-once check: both-roles', 0, jsonb_array_length(:'sco'::jsonb->'both_roles'));
select (select coalesce(sum((l->>'amount')::numeric),0) from jsonb_array_elements(day_book(1, tt.today(), tt.today())->'days') d cross join lateral jsonb_array_elements(d->'lines') l where l->>'dir'='out' and l->>'src' in ('quick','quick_expense','expense','entry') and (l->>'amount')::numeric=300) as dbk \gset
select tt.eq('H2 day book shows the 300 expense once', 300, :dbk);
select jsonb_agg(l) as dblines from jsonb_array_elements(day_book(1, tt.today(), tt.today())->'days') d cross join lateral jsonb_array_elements(d->'lines') l where l->>'dir'='out' \gset
\echo DAYBOOK_OUT: :dblines

\echo == 07 reports: biz_daily, P&L, COGS three-way, balance sheet, trial balance, inventory_vs_gl
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd_
select tt.eq('Q1 biz_daily revenue (net of returns) = 3375 - 325', 3050, :bd_revenue::numeric);
select tt.eq('Q1 biz_daily COGS hand 1084.936', 1084.936, :bd_cogs::numeric, 0.01);
select acct_income_statement(tt.today(), tt.today(), 1) as ist \gset
select tt.eq('Q2 P&L COGS == biz_daily COGS', :bd_cogs::numeric, (:'ist'::jsonb->>'cogs')::numeric, 0.01);
select tt.eq('Q2 journal COGS 5000', :bd_cogs::numeric, tt.bal_loc('5000',1), 0.01);
select round(sum(-qty_delta * unit_cost),2) as led_cogs from stock_ledger where ref_type in ('sale','sale_return') and unit_cost is not null and reason in ('sale_out','sale_return','packaging_out','packaging_return','packaging_restore') \gset
select string_agg(distinct reason, ',') as ledreasons from stock_ledger where ref_type in ('sale','sale_return') \gset
\echo SALE_LEDGER_REASONS: :ledreasons
select round(sum(-qty_delta * coalesce(unit_cost,0)),2) as led_cogs2 from stock_ledger where ref_type in ('sale','sale_return','sale_pack') \gset
select tt.eq('Q2 stock ledger movement of sold goods (incl. packaging, net of returns)', :bd_cogs::numeric, :led_cogs2::numeric, 0.01);
select tt.eq('Q2 net profit hand: 3050 - 1084.94 - 12 (wastage) - 51.28 (count) - 12 (bank) - 300 (transport) + 300 (overhead absorbed)', 1889.78, (acct_income_statement(tt.today(), tt.today(), 1)->>'net_profit')::numeric, 0.02);
select profit_source_check(tt.today(), tt.today(), 1) as psc \gset
select tt.t('Q3 profit_source_check agrees (report COGS = journal COGS)', (:'psc'::jsonb->>'agree')::boolean, 'true', :'psc'::jsonb->>'agree');

\echo -- report_cost_source modes
select tt.as(:'o');
insert into item_costs (item_id, cost_price) values (tt.iid('FG-CAKE'), 60) on conflict (item_id) do update set cost_price=excluded.cost_price;
select set_rule('report_cost_source','"ledger_avg"') is null as rcs1 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd2_
select tt.eq('Q4 ledger_avg: report COGS = journal 1084.94', 1084.94, :bd2_cogs::numeric, 0.01);
select set_rule('report_cost_source','"item_costs"') is null as rcs2 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd3_
select tt.eq('Q4 item_costs (only cake typed at 60): COGS = 4 kg x 60 = 240', 240, :bd3_cogs::numeric, 0.01);
select profit_source_check(tt.today(), tt.today(), 1) as psc3 \gset
select tt.eq('Q4 item_costs: journal COGS unchanged 1084.94', 1084.94, (:'psc3'::jsonb->>'journal_cogs')::numeric, 0.01);
select tt.t('Q4 item_costs: profit_source_check says NOT agree (honest)', not (:'psc3'::jsonb->>'agree')::boolean, 'false', :'psc3'::jsonb->>'agree');
select set_rule('report_cost_source','"ledger_then_item_costs"') is null as rcs3 \gset
select * from biz_daily(tt.today(), tt.today(), 1) \gset bd4_
select tt.eq('Q4 ledger_then_item_costs: = 1084.94', 1084.94, :bd4_cogs::numeric, 0.01);
select set_rule('report_cost_source',null) is null as rcs4 \gset

\echo -- balance sheet / trial balance / inventory_vs_gl
select acct_balance_sheet(tt.today(), null) as bs \gset
select tt.t('Q5 balance sheet balances', (:'bs'::jsonb->>'difference')::numeric = 0 and not (:'bs'::jsonb->>'unbalanced')::boolean, 'diff 0', :'bs'::jsonb->>'difference');
select tt.eq('Q5 retained earnings = P&L net profit (all days)', (acct_income_statement(tt.today()-5, tt.today(), null)->>'net_profit')::numeric, (:'bs'::jsonb->>'retained_earnings')::numeric, 0.01);
select acct_trial_balance(tt.today()-5, tt.today(), null) as tb \gset
select tt.t('Q5 trial balance debit == credit', (:'tb'::jsonb->>'balanced')::boolean, 'balanced', (:'tb'::jsonb->>'total_debit')||' vs '||(:'tb'::jsonb->>'total_credit'));
select tt.eq('Q5 every journal entry balanced', 0, tt.unbalanced());
select inventory_vs_gl(tt.today(), 1) as ivg \gset
\echo INV_VS_GL: :ivg
select tt.eq('Q6 inventory_vs_gl unexplained = -200 (hand: only the salt guard-off double count is unexplained; valuation_basis 48, glaze opening -60, biscuit manual_in -240 are explained)', -200, (:'ivg'::jsonb->'total'->>'unexplained')::numeric);
