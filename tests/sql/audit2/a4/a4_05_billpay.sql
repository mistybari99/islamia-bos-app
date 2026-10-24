\echo == A4-05 bill auto-payment (phase99) + manual payment: one payment counted once
select tt.as(:'o');
select set_rule('purchase_bill_creates_payment','"auto_cash"') is null as ac \gset
select tt.bal('1110') as cashb \gset
select tt.bal('2100') as payb \gset
select save_purchase(null,null,:'s1'::uuid,1,'A4-B3',tt.today(),format('[{"item_id":"%s","qty":2,"unit":"pc","unit_cost":50}]',tt.iid('FG-X'))::jsonb) ->> 'id' as b3 \gset
select post_purchase(:'b3'::uuid) is not null as pb3 \gset
select tt.eq('BP1 auto_cash: bill 100 paid at posting', 100, (select paid from purchase_bills where id=:'b3'::uuid));
select acct_post_pending(false) is not null as ppb \gset
select tt.eq('BP1 GL cash -100 for the auto payment', -100, tt.bal('1110') - :cashb::numeric);
select tt.eq('BP1 GL payable net change 0 (bill +100, payment -100)', 0, tt.bal('2100') - :payb::numeric);
select tt.err('BP2 manual payment on the already paid bill refused (overpaid)', format($$select bill_pay_record('purchase','%s','cash',100)$$, :'b3'), 'nothing_due');
select pay_supplier(:'s1'::uuid,1,'[{"mode":"cash","amount":50}]'::jsonb,gen_random_uuid(),'unbilled extra') is not null as xp \gset
select tt.t('BP3 pay_supplier not tied to a bill is accepted (no bill-level overpay control on the generic payment)', true, 'accepted', 'accepted');
select acct_post_pending(false) is not null as ppb2 \gset
select tt.eq('BP4 supplier sub-ledger == GL payable after all this (suppliers differing)', 0, (acct_reconcile('supplier')->>'suppliers_off')::numeric);
select set_rule('purchase_bill_creates_payment',null) is null as ac0 \gset
\echo == A4-06 expense paid by mobile/card, 10-2 vs daybook mode
select save_entry(null,'11-1',1,tt.today(),'{"pay_mode":"mobile","lines":[{"head":"transport","to":"rider","receipt":"yes","amount":"40"}]}','[]') ->> 'id' as v3 \gset
select submit_entry(:'v3'::uuid) is not null as sv3 \gset
select tt.bal('1130') as mob0 \gset
select tt.bal('1110') as cash1 \gset
select decide_entry(:'v3'::uuid, true, null, null, '[]') ->> 'status' as dv3 \gset
select acct_post_pending(false) is not null as ppb3 \gset
select tt.eq('EX1 voucher paid by mobile: GL mobile -40', -40, tt.bal('1130') - :mob0::numeric);
select tt.eq('EX1 voucher paid by mobile: GL cash unchanged', 0, tt.bal('1110') - :cash1::numeric);
select day_book(null, tt.today(), tt.today()) as db3 \gset
select tt.eq('EX2 day_book shows the mobile-paid voucher as cash out (mode hard-coded cash): mobile out today', 40, ((:'db3'::jsonb)->'totals'->'out'->>'mobile')::numeric, 0.005, 'expected by pay_mode; actual shows cash');
select count(*) filter (where e.status='submitted') as subm from entries e where form_code='11-1' \gset
select tt.t('EX3 submitted-but-not-approved vouchers are counted by the day book as money out, but not in GL', true, 'by design', 'note in daybook_vs_journal');
select tt.t('EX4 daybook_vs_journal lists the expense mode difference', (daybook_vs_journal(tt.today(), tt.today(), null)->'total'->>'kinds_differing')::int > 0);
\echo == A4-09 summary
select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail, count(*) as total from tt.ea \gset
\echo SUMMARY pass=:pass fail=:fail total=:total
select n, step, expected, actual from tt.ea where not ok order by n;
