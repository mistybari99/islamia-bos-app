-- ============================================================================
-- FRESH part 8 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase515 phase518 phase519 phase521 phase520 phase522
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase515.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase89.sql there and is already pasted on the live database under that name.
-- Renumbered to phase515.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 515 (bos89) - INTEGRATION FIX: the final body of every function that more than one phase re-created (72..88, 90, 91).
-- Run LAST, after phase517 (and re-check after any later phase 518/519). Paste twice = no error (create or replace only).
-- No table, no data, no rule, no privilege is touched; every default stays as today. Old phase files are NOT edited.
-- Step Sec (phase520): the 3 lines tagged bos94 in _sale_stock_out (rule offline_sale_max_age, empty = as before) are merged here too, byte for byte the same as in phase520, so pasting phase515 again
-- after phase520 does not bring the older text back. Before phase520 the rule does not exist and the lines do nothing.
--
-- Why: each phase was built on its own branch from the function text that existed THERE, so a later file silently put the older text back
-- (found by comparing pg_get_functiondef after every phase on a fresh build, see docs/briefs_p2p3/step_INT2_G_REPORT.md):
--   _sale_stock_out   phase509 dropped the phase508 unit_conv_required rule (and re-worded one Bangla message)
--   _acct_docs        phase511 dropped the phase506 free-cost-item rule
--   _cogs_lines72     phase514 dropped the phase506 free-cost-item rule
-- Every other function below is listed because two or more phases re-create it (or it was named in the integration notes); its text here is
-- the LAST phase's text, i.e. the same as the numeric paste order gives - written again so a different paste order cannot leave an older body.
-- Lines changed by this file carry "bos89".
-- ============================================================

-- ---- guard: every phase must be there (one marker object per phase) ----
do $$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  -- phase79 (merge of 72..78) leaves its tag in the 7-argument production_post core
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)') is null
     or pg_get_functiondef('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure) not like '%bos72%' then miss := miss || ' 79'; end if;
  if miss <> '' then
    raise exception 'phase515 needs phases 72..88, 90, 91 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $$;

-- the 7-argument acct_journal_post was replaced by the 8-argument one in phase511; make sure a re-pasted older file cannot leave both
do $$ begin
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null
     and to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is not null then
    drop function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean);   -- bos89
  end if;
end $$;

-- ---- _acct_docs(date) ----
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._acct_paykey(v.pm, true) /* bos85 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' else 'Stock transfer' end) || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' else 'stock_transfer' end)::text st) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');
end $function$;

-- ---- _cogs_lines72(date,date,integer[]) ----
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase506 (free-cost item) and phase514 (one report cost switch)
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as (select public._rcs88() as m),   -- bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
  cst as (select i.id as iid, coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) as cost_price   -- bos80: a free-cost item without a list cost counts as cost 0
          from public.items i left join public.item_costs ic on ic.item_id = i.id
          where i.count_in_business and coalesce(ic.cost_price, case when public._cost_free80(i.id) then 0::numeric end) is not null),
  docs as (
    select 'sale'::text as src, x.id as doc, x.sale_date as d, x.location_id as loc, (case when x.subtotal > 0 then x.total / x.subtotal else 1 end) as f, x.lines
    from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)
    union all
    select 'return'::text, r.id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, (case when la.s > 0 then r.amount / la.s else 1 end), r.lines
    from public.sale_returns r cross join net_on
    cross join lateral (select coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end), 0) as s
                        from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e) la
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  ln as (
    select docs.src, docs.doc,
           coalesce(case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end, '00000000-0000-0000-0000-000000000000'::uuid) as k,
           coalesce(sum(case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end * docs.f), 0) as rev,
           coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as qty
    from docs cross join lateral jsonb_array_elements(case when jsonb_typeof(docs.lines) = 'array' then docs.lines else '[]'::jsonb end) e group by 1, 2, 3),
  led as (
    select docs.src, docs.doc, l.item_id as k,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * coalesce(l.unit_cost, 0)) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lc,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0 or public._cost_free80(l.item_id)) as lq,   -- bos80
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0 and not public._cost_free80(l.item_id)) as uq   -- bos80
    from public.stock_ledger l
    join docs on l.ref_id = docs.doc::text
             and ((docs.src = 'sale' and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out'))
               or (docs.src = 'return' and l.ref_type = 'sale_return' and l.reason = 'sale_return'))
    group by 1, 2, 3),
  keys as (select src, doc, k from ln union select src, doc, k from led),
  j as (
    select docs.src, docs.doc, docs.d, docs.loc, keys.k, coalesce(ln.qty, 0) as jq, coalesce(ln.rev, 0) as rev,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.lc, 0) end as lc, case when rcs.m = 'item_costs' then 0 else coalesce(led.lq, 0) end as lq,
           case when rcs.m = 'item_costs' then 0 else coalesce(led.uq, 0) end as uq, ((led.lq is not null or led.uq is not null) and rcs.m <> 'item_costs') as hl,
           (case when rcs.m = 'ledger_avg' then null else c.cost_price end) as cost_price, rcs.m as m   -- bos88
    from keys join docs on docs.src = keys.src and docs.doc = keys.doc cross join rcs
    left join ln on ln.src = keys.src and ln.doc = keys.doc and ln.k = keys.k
    left join led on led.src = keys.src and led.doc = keys.doc and led.k = keys.k
    left join cst c on c.iid = keys.k),
  q as (select j.*, (case when hl then uq else jq end) as unk_q, (case when hl then lq + uq else jq end) as tot_q from j),
  w as (select q.*, (case when tot_q > 0 then rev * lq / tot_q else 0 end) as lrev from q)
  select w.src, w.doc, w.d, w.loc, nullif(w.k, '00000000-0000-0000-0000-000000000000'::uuid), w.jq, w.rev,
         w.lc + (case when w.m = 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),   -- bos88: item_costs mode = item_costs IS the primary source (no fallback flag)
         w.lrev + (case when w.m = 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.unk_q * w.cost_price else 0 end),
         (case when w.m <> 'item_costs' and w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.cost_price is null then w.rev - w.lrev else 0 end)
  from w;
$function$;

-- ---- _post_purchase_p13(uuid,jsonb) ----
CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb; gm text; skipst boolean := false;   -- bos82
begin
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  gcode := case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if pb.status = 'posted' then          -- a re-sent request: answered only to someone who may see purchases (or who posted it)
    if not (public._pur_ok(pb.location_id) or pb.posted_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true);
  end if;
  if not (public.has_grant(gcode, pb.location_id) or public._use_em(gcode, pb.location_id, 'post_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
  if pb.bill_date is distinct from (now() at time zone 'Asia/Dhaka')::date and coalesce(public.rule_txt('purchase_backdate_flag'), 'off') = 'warn' then   -- bos87 (a4-F11): stock is stamped now(), the journal uses bill_date
    perform public._stock_exc(pb.location_id, 'purchase_backdated', 'yellow', 'বিল ' || coalesce(pb.bill_no, '-') || ': তারিখ ' || pb.bill_date::text || ' (আজ নয়) — stock আজকের সময়ে ঢুকেছে, হিসাবের journal বিলের তারিখে',
      'Bill ' || coalesce(pb.bill_no, '-') || ': dated ' || pb.bill_date::text || ' (not today) — the stock is stamped now, the journal uses the bill date', null, pb.bill_date, 'PURCHASE', pb.total);   -- bos87
  end if;   -- bos87
  if pb.subtotal = 0 and pb.total = 0 and not exists (select 1 from public.purchase_lines where bill_id = pb.id) then raise exception 'no_lines'; end if;
  if pb.kind = 'return' then
    if pb.ref_bill_id is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
      perform public._stock_exc(pb.location_id, 'purchase_return_unreferenced', 'red', 'বিল ছাড়া ক্রয় ফেরত (বিল ' || coalesce(pb.bill_no, '-') || ')',
        'A purchase return was posted without the original bill (return ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE', pb.total);
    else
      perform 1 from public.purchase_bills where id = pb.ref_bill_id for update;
      select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'description', l.description, 'qty', l.qty, 'unit', l.unit, 'unit_cost', l.unit_cost)), '[]'::jsonb) into norm
        from public.purchase_lines l where l.bill_id = pb.id;
      if not exists (select 1 from public.purchase_bills where id = pb.ref_bill_id and status = 'posted') then raise exception 'bad_ref_bill'; end if;
      perform public._return_check(pb.ref_bill_id, pb.id, norm, true);
    end if;
  end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  -- bos82: GRN exclusivity. Source = GRN and guard on: the bill keeps money / supplier balance, the GRN holds the stock (no second purchase_in)
  gm := coalesce(public.rule_txt('purchase_grn_guard'), 'off');   -- bos82
  if pb.kind = 'bill' and gm in ('skip', 'link') and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then   -- bos82
    if gm = 'link' and not exists (select 1 from public.shadow_links x where x.domain = 'grn' and x.shadow_type = 'purchase_bills' and x.shadow_id = pb.id::text and x.state <> 'void') then   -- bos82
      raise exception 'grn_link_required' using detail = 'GRN is the stock source: link this bill to its GRN before posting', hint = 'grn_bill_link';   -- bos82
    end if;   -- bos82
    skipst := true;   -- bos82
  end if;   -- bos82
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;         -- the bill discount is spread over the lines
  for ln in select * from public.purchase_lines where bill_id = pb.id order by item_id nulls last, line_no loop
    if ln.item_id is null then continue; end if;
    select * into it from public.items where id = ln.item_id;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    if f is null or f <= 0 then
      if it.tracked then raise exception 'unit_unknown'; end if;
      f := 1;
    end if;
    bq := ln.qty * f; ucb := ln.unit_cost / f;
    update public.purchase_lines set base_qty = bq, unit_cost_base = ucb where id = ln.id;
    -- price jump against the last posted bill of this item (before this one); a return is checked the same way
    if pct is not null then
      select pl.unit_cost_base into last_c from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where pl.item_id = ln.item_id and x.status = 'posted' and x.kind = 'bill' and x.id <> pb.id and pl.unit_cost_base is not null order by x.posted_at desc, pl.id desc limit 1;
      if last_c is not null and last_c > 0 and abs(ucb - last_c) / last_c * 100 > pct and not jumped then
        jumped := true; nm := it.name_bn;
        perform public._stock_exc(pb.location_id, 'purchase_price_jump', 'yellow',
          nm || ': ' || case when pb.kind = 'return' then 'ফেরতের' else 'ক্রয়' end || 'মূল্য আগের চেয়ে ' || round((ucb - last_c) / last_c * 100, 1)::text || '% বদলেছে (বিল ' || coalesce(pb.bill_no, '-') || ')',
          coalesce(it.name_en, nm) || ': ' || case when pb.kind = 'return' then 'return ' else '' end || 'unit cost moved ' || round((ucb - last_c) / last_c * 100, 1)::text || '% from the last purchase (bill ' || coalesce(pb.bill_no, '-') || ')', null, pb.bill_date, 'PURCHASE');
      end if;
    end if;
    if it.tracked and not (skipst and pb.kind = 'bill') then   -- bos82: stock comes from the GRN
      if pb.kind = 'bill' then
        perform public.stock_post(ln.item_id, pb.location_id, bq, 'purchase_in', 'purchase', pb.id::text, round(ucb * net, 6), null, now(), null, null, 'none');
      else
        -- out at the current average cost (cost null = the average); what the supplier credits beyond / below that is the variance of this return
        lid := public.stock_post(ln.item_id, pb.location_id, -bq, 'purchase_return', 'purchase', pb.id::text, null, null, now(), null, null, 'full');
        select unit_cost into av from public.stock_ledger where id = lid;
        var := var + round(bq * (round(ucb * net, 6) - coalesce(av, round(ucb * net, 6))), 2);
      end if;
    end if;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_payments is not null and jsonb_typeof(p_payments) = 'array' and jsonb_array_length(p_payments) > 0 then
    if pb.kind <> 'bill' then raise exception 'no_payment_on_return'; end if;
    if not (public.has_grant('supplier_pay', pb.location_id) or public._use_em('supplier_pay', pb.location_id, 'post_purchase:' || p_id::text, null)) then raise exception 'not allowed'; end if;
    for pay in select * from jsonb_array_elements(p_payments) loop
      pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
      if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
      if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
      amt := round(amt, 2); psum := psum + amt;
      insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, created_by, created_staff)
        values (pb.supplier_id, pb.location_id, pb.id, pm, left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), amt, auth.uid(), sid);
    end loop;
    if psum > pb.total then raise exception 'overpaid'; end if;
  end if;
  update public.purchase_bills set status = 'posted', paid = psum, posted_by = auth.uid(), posted_at = now(), variance = case when pb.kind = 'return' then var end where id = pb.id;
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum) || case when skipst then jsonb_build_object('stock_from_grn', true) else '{}'::jsonb end;   -- bos82
end $function$;

-- ---- _r3q_l1_pnl(date,date,integer[],jsonb) ----
CREATE OR REPLACE FUNCTION public._r3q_l1_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'cogs_fallback', coalesce(sx.o_cogs_fallback, 0),   -- bos72: part of cogs that is an estimate from item_costs ("বইয়ের খরচ থেকে অনুমান")
    'unknown_cost_rev', coalesce(sx.o_unknown_rev, 0),   -- bos72: "সাময়িক: খরচহীন বিক্রি"
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc
  left join public._p27_src72(d1, d2, locs) sx on sx.o_m = p.o_m and sx.o_loc = p.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'month', to_char(z.mth, 'YYYY-MM'), 'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.mth, r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3, 4) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

-- ---- _r3q_l3_shop_pnl(date,date,integer[],jsonb) ----
CREATE OR REPLACE FUNCTION public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  sx as (select o_loc, sum(o_cogs_fallback) fb, sum(o_unknown_rev) unk from public._p27_src72(d1, d2, locs) group by o_loc)  -- bos72
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'cogs_fallback', coalesce(sx.fb, 0), 'unknown_cost_rev', coalesce(sx.unk, 0),   -- bos72
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc left join sx on sx.o_loc = a.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

-- ---- _sale_stock_out() ----
CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

-- ---- _void_purchase_p13(uuid,text) ----
CREATE OR REPLACE FUNCTION public._void_purchase_p13(p_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; r public.stock_ledger; gmode text; why text; shorts text := ''; kept numeric := 0; z record;   -- bos82
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into pb from public.purchase_bills where id = p_id;          -- no lock yet: who is asking comes first
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if pb.status = 'void' then          -- a re-sent request: answered only to someone who may see purchases (or who voided it)
    if not (public._pur_ok(pb.location_id) or pb.void_by = auth.uid()) then raise exception 'not allowed'; end if;
    return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true);
  end if;
  if pb.status = 'draft' then
    if not (public.has_grant(case pb.kind when 'return' then 'purchase_return' else 'purchase_entry' end, pb.location_id)) then raise exception 'not allowed'; end if;
  elsif not (public.has_grant('purchase_void', pb.location_id) or public._use_em('purchase_void', pb.location_id, 'void_purchase:' || p_id::text, pb.total)) then raise exception 'not allowed';
  end if;
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  perform public.lock_check(pb.bill_date);
  -- bos82: a posted bill that others depend on cannot simply disappear (switch purchase_void_guard: off | warn | refuse)
  gmode := coalesce(public.rule_txt('purchase_void_guard'), 'off');   -- bos82
  if gmode <> 'off' and pb.kind = 'bill' then   -- bos82
    if exists (select 1 from public.purchase_bills x where x.ref_bill_id = pb.id and x.kind = 'return' and x.status = 'posted') then why := 'void_has_return';   -- bos82
    elsif exists (select 1 from public.grn_batch_links gl join public.stock_batches b on b.id = gl.batch_id where gl.source_type = 'purchase' and gl.source_id = pb.id and b.qty_remaining > 0) then why := 'void_has_grn_batch';   -- bos82
    else   -- bos82
      for z in select o.item_id, o.location_id, sum(o.qty_delta) q from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason = 'purchase_in'   -- bos82
               and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) group by 1, 2 order by 1, 2 loop   -- bos82
        perform 1 from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id for update;   -- bos82
        if coalesce((select sb.qty from public.stock_balance sb where sb.item_id = z.item_id and sb.location_id = z.location_id), 0) - z.q < 0 then   -- bos82
          why := 'void_would_go_negative'; shorts := shorts || case when shorts = '' then '' else ', ' end || coalesce((select code from public.items where id = z.item_id), '?');   -- bos82
        end if;   -- bos82
      end loop;   -- bos82
    end if;   -- bos82
    if why is not null then   -- bos82
      if gmode = 'refuse' then raise exception '%', why using detail = case why when 'void_has_return' then 'A posted purchase return refers to this bill: void the return first' when 'void_has_grn_batch' then 'GRN batches with stock left exist for this bill' else 'Stock used or sold already: voiding would make it negative: ' || shorts end, hint = 'purchase_void_guard'; end if;   -- bos82
      perform public._stock_exc(pb.location_id, 'purchase_void_unsafe', 'red', 'ক্রয় bill বাতিল (ঝুঁকিপূর্ণ): ' || why || ' ' || shorts, 'Purchase bill voided although: ' || why || ' ' || shorts, null, pb.bill_date, 'PURCHASE', pb.total);   -- bos82
    end if;   -- bos82
  end if;   -- bos82
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  if coalesce(public.rule_txt('purchase_void_payments'), 'void') = 'keep' then   -- bos82: cash really left; the payment stays and becomes supplier credit (use supplier_refund to take the money back)
    select coalesce(sum(amount), 0) into kept from public.supplier_payments where bill_id = pb.id and not voided;   -- bos82
    if kept > 0 then perform public._stock_exc(pb.location_id, 'purchase_void_credit', 'yellow', 'বাতিল bill-এর পরিশোধ রাখা হয়েছে, supplier-এর কাছে credit: ' || kept::text, 'Voided bill payment kept as supplier credit: ' || kept::text, null, pb.bill_date, 'PURCHASE', kept); end if;   -- bos82
  else   -- bos82
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  end if;   -- bos82
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void') || case when kept > 0 then jsonb_build_object('payments_kept', kept) else '{}'::jsonb end;   -- bos82
end $function$;

-- ---- acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text) ----
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_memo is null or length(btrim(p_memo)) < 3 then raise exception 'memo_required'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  ln := public._acct_resolve(p_lines, p_loc);
  if coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' then perform public._manual_guard85(ln, p_reason); end if;   -- bos85
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;
  if td <> tc or td <= 0 then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', p_date, 'total_debit', td, 'total_credit', tc, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $function$;

-- ---- acct_post_pending(boolean,integer) ----
CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]';
begin
  if not (public._acct_manage() or (auth.uid() is null and coalesce(current_setting('bos.autopost85', true), '') = 'on')) then raise exception 'not allowed'; end if;   -- bos85: the scheduler entry point has no signed-in person
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric)), '[]'::jsonb)
                         from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'flags', d.flags, 'location_id', d.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'party_type', x->>'party_type', 'party_id', x->>'party_id'))
                        from jsonb_array_elements(ln) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint));
          end if;
        else
          eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        if d.flags like '%cogs_missing%' then flagged := flagged + 1; end if;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if p_dry then
          acc := acc || (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit)), '[]'::jsonb)
                         from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id);
          if jsonb_array_length(prev) < 60 then
            prev := prev || jsonb_build_object('date', rdate, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', 'Reversal: ' || orig.memo, 'reversal', true, 'location_id', orig.location_id,
              'lines', (select jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', l.credit, 'credit', l.debit, 'party_type', l.party_type, 'party_id', l.party_id) order by l.line_no)
                        from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where l.entry_id = orig.id));
          end if;
        else
          eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo);
        end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;   -- bos72: solved
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      if not p_dry then   -- bos72: keep the failure so the status strip and the accounts page can show it (the browser used to drop it)
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped);
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$;

-- ---- acct_status() ----
CREATE OR REPLACE FUNCTION public.acct_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); pend int := 0; lck int := 0; wt int := 0; er int := 0; erl jsonb := '[]'::jsonb;   -- bos72
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is not null then   -- bos72: documents not yet in the books (the same list acct_post_pending would work through)
    with dd as materialized (select * from public._acct_docs(st)),
    e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null),
           (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries, 'last_at', y.last_at) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, er, erl;
  end if;
  return jsonb_build_object('on', public.rule_on('accounting_on'), 'autopost', public.rule_on('accounting_autopost'), 'start', st,
    'can_manage', public._acct_manage(), 'owner', public.is_owner(),
    'opening', exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)),
    'entries', (select count(*) from public.journal_entries), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),
    'last_post_at', (select max(created_at) from public.journal_entries where (created_by is not null or exists (select 1 from public.acct_autopost_runs85)) and source_type not in ('manual', 'opening')),   -- bos72 bos85: a scheduler run has no person
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl,   -- bos72
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));   -- bos85
end $function$;

-- ---- cost_rule_approve(bigint,text) ----
CREATE OR REPLACE FUNCTION public.cost_rule_approve(p_rule bigint, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.cost_source_rules; b record; n int := 0; selfap boolean := false; sid text;   -- bos87
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch cost_rule_self_approve)
    if public.is_owner() or public.rule_on('cost_rule_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'cost_source_rules', p_rule::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n) || public._self_approve_hint87(selfap);   -- bos87
end $function$;

-- ---- dup_suspects(date,date) ----
CREATE OR REPLACE FUNCTION public.dup_suspects(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb),
    -- bos83 F10: two finished-goods screens for the same item, place and day - a recipe run (production_post) and a plain finished-goods entry (stock_production_in)
    'production_screens', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.item_id, r.location_id, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.id as run_id, s.id as plain_ledger_id, s.qty_delta as plain_qty, r.yield_base as run_qty
          from public.production_runs r join public.stock_ledger s on s.item_id = r.item_id and s.location_id = r.location_id and s.reason = 'production_in' and s.ref_type = 'production'
            and s.reverses_id is null and s.id is distinct from r.ledger_in_id and (s.made_at at time zone 'Asia/Dhaka')::date = (r.made_at at time zone 'Asia/Dhaka')::date
         where r.status = 'done' and r.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and r.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and not exists (select 1 from public.production_runs r2 where r2.ledger_in_id = s.id) order by r.made_at limit 200) z), '[]'::jsonb),
    -- bos83 E6 (a4-F5): a quick expense and an approved 10-2 voucher line for the same place, day, head and amount that are NOT linked as a shadow
    'expense', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select q.id as quick_id, q.location_id, q.exp_date as day, q.head, q.amount, e.id as entry_id, e.serial
          from public.quick_expenses q
          join public.entries e on e.form_code = '10-2' and e.status = 'approved' and e.location_id = q.location_id and e.entry_date = q.exp_date
            and jsonb_typeof(e.data -> 'lines') = 'array' and not public.is_shadow('entries', e.id::text)
          join lateral jsonb_array_elements(e.data -> 'lines') ln on lower(btrim(ln ->> 'head')) = q.head and public._db_num(ln -> 'amount') = q.amount
         where q.status = 'done' and q.exp_date between p_from and p_to
           and not exists (select 1 from public.shadow_links x where x.primary_type = 'quick_expenses' and x.primary_id = q.id::text and x.state = 'confirmed')
         order by q.exp_date, q.id limit 200) z), '[]'::jsonb));
end $function$;

-- ---- inbox_board(integer) ----
CREATE OR REPLACE FUNCTION public.inbox_board(p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l int[]; last_at timestamptz; hrs numeric := coalesce(public.rule_num('inbox_silence_hours'), 0); hs numeric; fcount int := 0;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('on', false); end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select max(received_at) into last_at from public.inbound_messages where location_id = any (l);
  hs := case when last_at is null then null else round(extract(epoch from now() - last_at) / 3600, 1) end;
  if public.is_owner() or public.can_do('POS', 'approve') then select count(*) into fcount from public.intake_failures where state = 'failed'; end if;
  return jsonb_build_object('on', true,
    'new_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'new'),
    'seen_count', (select count(*) from public.inbound_messages where location_id = any (l) and status = 'seen'),
    'last_at', last_at, 'hours_since', hs, 'silence_hours', hrs,
    'silent', hrs > 0 and hs is not null and hs > hrs,
    'failed_count', fcount,
    'dup_open', (select count(*) from public.order_dup_flags where location_id = any (l) and state = 'open'),
    'drafts', (select count(*) from public.online_orders where location_id = any (l) and is_draft and status = 'new'),
    'channels', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name_bn, 'kind', c.kind,
        'last_at', (select max(received_at) from public.inbound_messages m where m.channel_id = c.id),
        'new_count', (select count(*) from public.inbound_messages m where m.channel_id = c.id and m.status = 'new')) order by c.id)
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp', 'telegram') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));   -- bos86: + telegram
end $function$;

-- ---- inventory_vs_gl(date,integer) ----
CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null then
    if not public._acct_all() or exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  elsif not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  basis := case when d >= t then 'average_cost' else 'ledger_replay' end;
  foreach k in array array['inv_finished', 'inv_raw', 'inv_pack'] loop
    select m.account_id, a.code, a.name_bn, a.name_en into acct, acode, anbn, anen from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
    if acct is null then continue; end if;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(x.v), 0) as lv_all, coalesce(sum(x.v) filter (where x.cib), 0) as lv_cib,
           coalesce(sum(x.v) filter (where x.reason = 'count_adjust'), 0) as g_count,
           coalesce(sum(x.v) filter (where x.reason = 'opening'), 0) as g_opening,
           coalesce(sum(x.v) filter (where x.reason in ('transfer_out', 'transfer_in') or x.ref_type = 'transfer'), 0) as g_transfer,
           coalesce(sum(x.v) filter (where x.reason = 'issue_out' and x.ref_type in ('issue', 'entry')), 0) as g_issue,
           coalesce(sum(x.v) filter (where (x.reason = 'production_in' and not x.has_run) or (x.reason = 'purchase_in' and x.ref_type = 'entry') or (x.reason = 'reversal' and x.ref_type = 'entry')), 0) as g_manual_in,
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger sl join public.items it on it.id = sl.item_id
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening') /* bos85 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger sl join public.items it on it.id = sl.item_id
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in, 2)),
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret + j_var, 2)),   -- bos85
      jsonb_build_object('code', 'production_cost_missing', 'amount', round(g_prod, 2)),
      jsonb_build_object('code', 'manual_journal', 'amount', round(g_man, 2)));
    ex := df - (select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(rs) x);
    rows_ := rows_ || jsonb_build_object('key', k, 'code', acode, 'name_bn', anbn, 'name_en', anen, 'gl', round(gl, 2), 'valuation', round(v, 2), 'ledger_value', round(rw.lv_all, 2),
                'diff', df, 'reasons', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(rs) x where abs((x->>'amount')::numeric) >= 0.005), 'unexplained', round(ex, 2));
    tg := tg + gl; tv := tv + v; tx := tx + ex;
  end loop;
  ok := abs(tg - tv) < 0.05;
  return jsonb_build_object('as_of', d, 'location_id', p_loc, 'start', st, 'accounting_on', public.rule_on('accounting_on'), 'valuation_basis', basis, 'rows', rows_,
    'total', jsonb_build_object('gl', round(tg, 2), 'valuation', round(tv, 2), 'diff', round(tg - tv, 2), 'unexplained', round(tx, 2)), 'agree', ok,
    'note', 'Read only: nothing is posted. Reasons are movements the books or the stock ledger do not have; "unexplained" is what is left.');
end $function$;

-- ---- online_order_get(uuid) ----
CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$;

-- ---- online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text) ----
CREATE OR REPLACE FUNCTION public.online_order_save(p_id uuid, p_client uuid, p_loc integer, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb, p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.online_orders; nl jsonb; sub numeric; n int; mob text; chg numeric := coalesce(p_charge, 0); dsc numeric := coalesce(p_discount, 0); adv numeric := coalesce(p_advance, 0); loc int := p_loc; sid text;
begin
  if p_id is not null then
    select * into o from public.online_orders where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
  else
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into o from public.online_orders where client_id = p_client and created_by = auth.uid();
      if found then return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'dup', true); end if;
    end if;
  end if;
  perform public._oo_gate80(loc, p_id is null);      -- bos80: the dedicated intake bot may CREATE an order, never edit one
  if p_id is not null and o.status not in ('new', 'confirmed') then raise exception 'order_closed: only a new or confirmed order can be edited'; end if;
  if p_channel not in ('website', 'facebook', 'instagram', 'whatsapp', 'phone', 'foodapp', 'other') then raise exception 'bad_channel'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 80 then raise exception 'customer_name_required'; end if;
  mob := public.norm_mobile(p_mobile);
  if mob is null or char_length(mob) < 6 then raise exception 'bad_mobile'; end if;
  if p_delivery_mode not in ('pickup', 'home', 'courier') then raise exception 'bad_delivery_mode'; end if;
  if p_delivery_mode <> 'pickup' and nullif(btrim(p_address), '') is null then raise exception 'address_required'; end if;
  if char_length(coalesce(p_address, '')) > 300 or char_length(coalesce(p_note, '')) > 300 or char_length(coalesce(p_delivery_by, '')) > 60 then raise exception 'too_long'; end if;
  if p_delivery_date is not null and not (p_delivery_date between public._dhaka_today() - 1 and public._dhaka_today() + 365) then raise exception 'bad_date'; end if;
  if chg = 'NaN'::numeric or chg < 0 or chg > 1000000 then raise exception 'bad_amount'; end if;
  if dsc = 'NaN'::numeric or dsc < 0 or adv = 'NaN'::numeric or adv < 0 then raise exception 'bad_amount'; end if;
  nl := public._oo_lines61(p_lines); sub := (nl->>'subtotal')::numeric;
  dsc := round(dsc, 2); adv := round(adv, 2); chg := round(chg, 2);
  if dsc > sub then raise exception 'bad_discount'; end if;
  if adv > sub - dsc + chg then raise exception 'advance_over_total'; end if;
  if adv > 0 and coalesce(p_adv_mode, '') not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
  if adv = 0 then p_adv_mode := null; p_adv_wallet := null; end if;
  if p_id is null then
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.serials (form_code, location_id, last) values ('ORD', loc, 1)
      on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
    insert into public.online_orders (client_id, order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_by, delivery_date,
        delivery_charge, advance, advance_mode, advance_wallet, note, created_by, created_staff)
      values (p_client, n, loc, p_channel, left(btrim(p_name), 80), mob, nullif(btrim(p_address), ''), nl->'lines', sub, dsc, p_delivery_mode, nullif(btrim(p_delivery_by), ''), p_delivery_date,
        chg, adv, p_adv_mode, left(nullif(btrim(p_adv_wallet), ''), 30), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into o;
    perform public._oo_event61(o.id, null, 'new', 'created');
    return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
  end if;
  update public.online_orders set channel = p_channel, customer_name = left(btrim(p_name), 80), customer_mobile = mob, address = nullif(btrim(p_address), ''), lines = nl->'lines', subtotal = sub,
      discount = dsc, delivery_mode = p_delivery_mode, delivery_by = nullif(btrim(p_delivery_by), ''), delivery_date = p_delivery_date, delivery_charge = chg, advance = adv,
      advance_mode = p_adv_mode, advance_wallet = left(nullif(btrim(p_adv_wallet), ''), 30), note = nullif(btrim(p_note), ''), updated_at = now()
    where id = o.id returning * into o;
  perform public._oo_event61(o.id, o.status, o.status, 'edited');
  return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
end $function$;

-- ---- online_orders_list(integer,text,date,date,integer) ----
CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name,
           case when public._inb_contact_ok(o.location_id) then o.customer_mobile end as customer_mobile,   -- bos76
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked,                          -- bos76
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$;

-- ---- partner_calculate(bigint,date,date,jsonb) ----
CREATE OR REPLACE FUNCTION public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ag public.partner_agreements; vn public.partner_ventures; locs int[]; k text; r record; cfg jsonb; sh jsonb; er record; er2 record;
  bases jsonb := '{}'::jsonb; src jsonb := '{}'::jsonb; warns jsonb := '[]'::jsonb; steps jsonb := '[]'::jsonb; lines jsonb := '[]'::jsonb; nl jsonb;
  v_gs numeric; v_ns numeric; v_costed numeric; v_cogs numeric; v_exp numeric; v_sal numeric; v_fix numeric; v_gp numeric; v_nf numeric; v_n int;
  pool numeric; poolset boolean := false; incomplete boolean := false; fees numeric := 0;
  rto numeric := 0.01; rmode text := 'nearest';
  carry_in numeric := 0; carry_out numeric := 0; retained numeric := 0; floor_added numeric := 0;
  amt numeric; core numeric; stepamt numeric; pool_before numeric; pid bigint; pct numeric; mths numeric := public._a44_months(p_from, p_to); days int := p_to - p_from + 1;
  capb numeric; due numeric; capc numeric; paid_b numeric; sf_in numeric; short_out numeric; outb numeric; a1 numeric; a2 numeric; used numeric; tgt numeric; lim numeric; tot numeric; exc numeric; rem numeric; red numeric;
  detail jsonb; skipped boolean; remaining numeric; prev_up numeric; size numeric; dist jsonb; d jsonb; need numeric; outside boolean; names jsonb; ptot jsonb; tdist numeric := 0; tout numeric := 0;
  nbase int := 0; newlines jsonb; v_fb numeric;   -- bos80
begin
  perform public._a44_guard();
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then raise exception 'bad_range'; end if;
  select * into ag from public.partner_agreements where id = p_agr;
  if not found then raise exception 'not_found'; end if;
  select * into vn from public.partner_ventures where id = ag.venture_id;
  -- manual figures typed by the owner
  if p_manual is not null then
    if jsonb_typeof(p_manual) <> 'object' then raise exception 'bad_manual'; end if;
    for k in select jsonb_object_keys(p_manual) loop
      if k not in ('gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'manual', 'carry_in') or public._a44_n(p_manual -> k) is null or abs(public._a44_n(p_manual -> k)) > 1000000000000 then raise exception 'bad_manual'; end if;
    end loop;
  end if;
  -- bases from the books (only what can be computed honestly)
  if vn.scope in ('location', 'business') then
    locs := case when vn.scope = 'location' then array[vn.location_id] else array(select id from public.locations) end;
    select count(*), coalesce(sum(o_gross), 0), coalesce(sum(o_net), 0), coalesce(sum(o_costed), 0), coalesce(sum(o_cogs), 0), coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0), sum(o_fixed)
      into v_n, v_gs, v_ns, v_costed, v_cogs, v_exp, v_sal, v_fix from public._p27_pl(p_from, p_to, locs);
    bases := jsonb_build_object('gross_sales', v_gs, 'net_sales', v_ns);
    if abs(v_ns - v_costed) <= greatest(1, abs(v_ns) * 0.001) then
      v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      bases := bases || jsonb_build_object('gross_profit', v_gp, 'net_profit_before_fees', v_nf);
    else
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'uncosted_sales', 'detail', round(v_ns - v_costed, 2), 'msg', 'Some sold items have no cost price, so gross profit cannot be computed honestly. Type a manual base.'));
      bases := bases || jsonb_build_object('gross_profit', null, 'net_profit_before_fees', null);
    end if;
    bases := bases || jsonb_build_object('expenses', v_exp, 'salary', v_sal, 'fixed_cost', v_fix, 'cogs', v_cogs);
    -- bos80: part of the cost of goods sold may be an ESTIMATE from the item cost list (no stock-ledger cost). Always shown; partner_base_estimate = refuse stops a settlement SAVE on it.
    select coalesce(sum(o_cogs_fallback), 0) into v_fb from public._p27_src72(p_from, p_to, locs);
    if v_fb > 0.004 then
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'estimated_base', 'detail', round(v_fb, 2), 'refuse', coalesce(public.rule_txt('partner_base_estimate'), 'warn') = 'refuse',
        'msg', 'Part of the cost of goods sold is an estimate from the item cost list, not from the stock ledger.'));
    end if;
    if v_n = 0 then warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_book_rows', 'msg', 'No sales, expenses or salary were recorded in this period.')); end if;
  else
    bases := jsonb_build_object('gross_sales', null, 'net_sales', null, 'gross_profit', null, 'net_profit_before_fees', null);
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'manual_only', 'msg', 'A product-line or custom venture has no books of its own - type the manual base.'));
  end if;
  for k in select jsonb_object_keys(coalesce(p_manual, '{}'::jsonb)) loop
    if k <> 'carry_in' then bases := bases || jsonb_build_object(k, public._a44_n(p_manual -> k)); src := src || jsonb_build_object(k, 'manual'); end if;
  end loop;
  for k in select unnest(array['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees']) loop
    if not src ? k then src := src || jsonb_build_object(k, case when bases -> k is null or jsonb_typeof(bases -> k) = 'null' then 'unavailable' else 'books' end); end if;
  end loop;
  -- loss carried from the earlier settlement
  if p_manual ? 'carry_in' then carry_in := greatest(public._a44_n(p_manual -> 'carry_in'), 0);
  else
    select coalesce(s.carry_out, 0) into carry_in from public.partner_settlements s
     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from order by s.period_to desc limit 1;
    carry_in := coalesce(carry_in, 0);
  end if;

  for r in select * from public.partner_rules where agreement_id = p_agr and active order by step_no loop
    cfg := r.config; stepamt := 0; core := null; detail := '{}'::jsonb; skipped := false; pool_before := pool; short_out := null;
    if r.kind <> 'base' and r.kind <> 'rounding' and not poolset then raise exception 'base_step_first'; end if;
    if incomplete and r.kind <> 'rounding' and r.kind <> 'base' then
      skipped := true; detail := jsonb_build_object('skipped', 'no_base');
    else
    case r.kind
      when 'base' then
        nbase := nbase + 1; if nbase > 1 then raise exception 'base_twice'; end if;
        k := cfg ->> 'base';
        pool := case k when 'fixed_amount' then public._a44_n(cfg -> 'amount')
                       when 'manual' then public._a44_n(bases -> 'manual')
                       when 'net_profit' then case when public._a44_n(bases -> 'net_profit_before_fees') is null then null else public._a44_n(bases -> 'net_profit_before_fees') - fees end
                       else public._a44_n(bases -> k) end;
        poolset := true;
        if pool is null then
          incomplete := true;
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'This base cannot be computed from the books - type a manual base.'));
        end if;
        detail := jsonb_build_object('base', k, 'value', pool); pool_before := null;
      when 'royalty' then
        pid := public._a44_need(p_agr, cfg, r.name); k := coalesce(cfg ->> 'base', 'net_sales');
        if public._a44_n(bases -> k) is null then
          incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The royalty base cannot be computed - type a manual base.'));
        else
          amt := public._a44_round(greatest(public._a44_n(bases -> k), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode);
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'royalty', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt;
          detail := jsonb_build_object('base', k, 'base_value', public._a44_n(bases -> k), 'percent', public._a44_n(cfg -> 'percent'), 'party_id', pid);
        end if;
      when 'management_fee' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'fixed') is not null then
          amt := public._a44_round(public._a44_n(cfg -> 'fixed') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end, rto, rmode);
        else
          k := cfg ->> 'base';
          if k is not null and public._a44_n(bases -> k) is null then amt := null; incomplete := true; skipped := true; detail := jsonb_build_object('skipped', 'no_base');
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'base_unavailable', 'base', k, 'step_no', r.step_no, 'msg', 'The fee base cannot be computed - type a manual base.'));
          else amt := public._a44_round(greatest(coalesce(public._a44_n(bases -> k), pool), 0) * public._a44_n(cfg -> 'percent') / 100, rto, rmode); end if;
        end if;
        if amt is not null then
          lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'fee', 'amount', amt, 'outside', false));
          pool := pool - amt; fees := fees + amt; stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'months', round(mths, 4));
        end if;
      when 'expense_allow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool - amt; stepamt := -amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'expense_disallow' then
        select coalesce(sum(public._a44_n(i -> 'amount')), 0) into amt from jsonb_array_elements(cfg -> 'items') i;
        pool := pool + amt; stepamt := amt; detail := jsonb_build_object('items', cfg -> 'items', 'total', amt);
      when 'loss_carry_forward' then
        amt := pool - carry_in;
        if amt < 0 then carry_out := -amt; pool := 0; else carry_out := 0; pool := amt; end if;
        detail := jsonb_build_object('carry_in', carry_in, 'carry_out', carry_out);
      when 'priority_return' then
        pid := public._a44_need(p_agr, cfg, r.name);
        if public._a44_n(cfg -> 'percent_per_year') is not null then
          due := round(public._a44_capdays(p_agr, pid, p_from, p_to) * public._a44_n(cfg -> 'percent_per_year') / 100 / 365, 2);
        else due := round(public._a44_n(cfg -> 'fixed_monthly') * mths, 2); end if;
        select h.paid_before, h.shortfall_in into paid_b, sf_in from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        if coalesce((cfg ->> 'catch_up')::boolean, false) then due := due + sf_in; else sf_in := 0; end if;
        due := public._a44_round(due, rto, rmode);
        if public._a44_n(cfg -> 'cap') is not null then due := least(due, greatest(public._a44_n(cfg -> 'cap') - paid_b, 0)); end if;
        amt := least(due, greatest(pool, 0));
        short_out := case when coalesce((cfg ->> 'catch_up')::boolean, false) then due - amt else 0 end;
        if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'return', 'amount', amt, 'outside', false)); end if;
        pool := pool - amt; stepamt := amt; core := amt;
        detail := jsonb_build_object('party_id', pid, 'due', due, 'catch_up_in', sf_in, 'paid_before', paid_b, 'shortfall_out', short_out);
        if amt < due and not coalesce((cfg ->> 'catch_up')::boolean, false) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'return_short', 'step_no', r.step_no, 'msg', 'The profit was not enough for the whole priority return.')); end if;
      when 'payback' then
        pid := public._a44_need(p_agr, cfg, r.name); pct := coalesce(public._a44_n(cfg -> 'percent'), 100);
        select h.paid_before into paid_b from public._a44_step_hist(p_agr, p_from, r.step_key::text) h;
        outb := coalesce(public._a44_n(cfg -> 'target'), public._a44_cap(p_agr, pid, p_to)) - paid_b;
        a1 := 0; a2 := 0;
        if outb > 0 then
          a1 := least(outb, public._a44_round(greatest(pool, 0) * pct / 100, rto, rmode));
          if public._a44_n(cfg -> 'then_percent') is not null and a1 >= outb - 0.004 and greatest(pool, 0) * pct / 100 > outb then
            used := outb / (pct / 100); a2 := public._a44_round(greatest(pool - used, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
          end if;
        elsif public._a44_n(cfg -> 'then_percent') is not null then
          a2 := public._a44_round(greatest(pool, 0) * public._a44_n(cfg -> 'then_percent') / 100, rto, rmode);
        end if;
        if a1 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'payback', 'amount', a1, 'outside', false)); end if;
        if a2 > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'share', 'amount', a2, 'outside', false)); end if;
        pool := pool - a1 - a2; stepamt := a1 + a2; core := a1;
        detail := jsonb_build_object('party_id', pid, 'outstanding_before', greatest(outb, 0), 'payback', a1, 'then_share', a2, 'outstanding_after', greatest(outb - a1, 0));
      when 'split' then
        if pool > 0 then
          dist := public._a44_distribute(p_agr, pool, cfg -> 'shares', rto, rmode, r.name);
          for d in select value from jsonb_array_elements(dist) loop
            lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
          end loop;
          stepamt := pool; detail := jsonb_build_object('distributed', pool, 'parts', dist); pool := 0;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
          detail := jsonb_build_object('distributed', 0);
        end if;
      when 'tiered_split' then
        if pool > 0 then
          remaining := pool; prev_up := 0; detail := jsonb_build_object('slabs', '[]'::jsonb);
          for er in select value as v, ord from jsonb_array_elements(cfg -> 'slabs') with ordinality as t(value, ord) order by ord loop
            exit when remaining <= 0;
            size := case when public._a44_n(er.v -> 'upto') is null then remaining else least(remaining, public._a44_n(er.v -> 'upto') - prev_up) end;
            dist := public._a44_distribute(p_agr, size, er.v -> 'shares', rto, rmode, r.name);
            for d in select value from jsonb_array_elements(dist) loop
              lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', (d ->> 'party_id')::bigint, 'kind', 'share', 'amount', (d ->> 'amount')::numeric, 'outside', false));
            end loop;
            detail := jsonb_set(detail, '{slabs}', (detail -> 'slabs') || jsonb_build_array(jsonb_build_object('slab', er.ord, 'amount', size, 'parts', dist)));
            remaining := remaining - size; stepamt := stepamt + size;
            if public._a44_n(er.v -> 'upto') is not null then prev_up := public._a44_n(er.v -> 'upto'); end if;
          end loop;
          pool := remaining;
        else
          warns := warns || jsonb_build_array(jsonb_build_object('code', 'no_profit', 'step_no', r.step_no, 'msg', 'There is no profit to share at this step.'));
        end if;
      when 'minimum_guarantee', 'floor' then
        if r.kind = 'floor' and coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool < lim then floor_added := floor_added + (lim - pool); stepamt := lim - pool;
            warns := warns || jsonb_build_array(jsonb_build_object('code', 'floor_topup', 'step_no', r.step_no, 'detail', lim - pool, 'msg', 'The pool was lifted to the floor; the difference is funded outside the books.'));
            pool := lim; end if;
          detail := jsonb_build_object('floor', lim, 'added', greatest(stepamt, 0));
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          need := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, true);
          amt := 0; outside := coalesce(cfg ->> 'funded_by', 'pool') = 'outside';
          if tot < need then
            amt := need - tot;
            if not outside then
              if amt > greatest(pool, 0) then warns := warns || jsonb_build_array(jsonb_build_object('code', 'guarantee_short', 'step_no', r.step_no, 'detail', amt - greatest(pool, 0), 'msg', 'The pool could not pay the whole guarantee.')); amt := greatest(pool, 0); end if;
              pool := pool - amt;
            end if;
            amt := public._a44_round(amt, rto, rmode);
            if amt > 0 then lines := lines || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'party_id', pid, 'kind', 'guarantee', 'amount', amt, 'outside', outside)); end if;
          end if;
          stepamt := amt; core := amt; detail := jsonb_build_object('party_id', pid, 'needed', need, 'had', tot, 'topup', amt, 'funded_by', case when outside then 'outside' else 'pool' end);
        end if;
      when 'cap' then
        if coalesce(cfg ->> 'target', 'pool') = 'pool' then
          lim := public._a44_n(cfg -> 'amount');
          if pool > lim then retained := retained + (pool - lim); stepamt := -(pool - lim); pool := lim; end if;
          detail := jsonb_build_object('cap', lim, 'retained', retained);
        else
          pid := public._a44_need(p_agr, cfg, r.name);
          lim := public._a44_n(cfg -> 'amount') * case when coalesce(cfg ->> 'per', 'period') = 'month' then mths else 1 end;
          tot := public._a44_party_total(lines, pid, false); exc := greatest(tot - lim, 0); rem := exc;
          if exc > 0 then
            newlines := '[]'::jsonb;
            for er2 in select value as v, ord from jsonb_array_elements(lines) with ordinality as t(value, ord) order by ord desc loop
              if rem > 0 and (er2.v ->> 'party_id')::bigint = pid and not coalesce((er2.v ->> 'outside')::boolean, false) then
                red := least(rem, (er2.v ->> 'amount')::numeric); rem := rem - red;
                newlines := jsonb_build_array(jsonb_set(er2.v, '{amount}', to_jsonb(round((er2.v ->> 'amount')::numeric - red, 2)))) || newlines;
              else newlines := jsonb_build_array(er2.v) || newlines; end if;
            end loop;
            lines := newlines; pool := pool + exc; stepamt := -exc;
          end if;
          detail := jsonb_build_object('party_id', pid, 'cap', lim, 'had', tot, 'returned_to_pool', exc);
        end if;
      when 'rounding' then
        rto := public._a44_n(cfg -> 'to'); rmode := coalesce(cfg ->> 'mode', 'nearest'); detail := jsonb_build_object('to', rto, 'mode', rmode);
      else raise exception 'bad_kind';
    end case;
    end if;
    steps := steps || jsonb_build_array(jsonb_build_object('step_no', r.step_no, 'key', r.step_key, 'name', r.name, 'kind', r.kind, 'skipped', skipped,
        'pool_before', pool_before, 'pool_after', pool, 'amount', round(stepamt, 2), 'core', round(coalesce(core, stepamt), 2), 'shortfall_out', short_out, 'detail', detail));
  end loop;
  if nbase = 0 then raise exception 'base_step_first'; end if;
  if pool is not null and pool > 0.004 then
    retained := retained + pool;
    warns := warns || jsonb_build_array(jsonb_build_object('code', 'retained', 'detail', pool, 'msg', 'Part of the profit was not given to anybody by the rules.'));
  end if;
  select coalesce(sum((e ->> 'amount')::numeric) filter (where not coalesce((e ->> 'outside')::boolean, false)), 0), coalesce(sum((e ->> 'amount')::numeric) filter (where coalesce((e ->> 'outside')::boolean, false)), 0)
    into tdist, tout from jsonb_array_elements(lines) e;
  select coalesce(jsonb_agg(jsonb_build_object('party_id', q.pid, 'name', p.name, 'amount', q.a) order by p.name), '[]'::jsonb) into ptot
    from (select (e ->> 'party_id')::bigint as pid, sum((e ->> 'amount')::numeric) as a from jsonb_array_elements(lines) e group by 1) q join public.partner_parties p on p.id = q.pid;
  return jsonb_build_object('agreement_id', p_agr, 'venture_id', ag.venture_id, 'from', p_from, 'to', p_to, 'days', days, 'months', round(mths, 4),
    'status', case when incomplete then 'incomplete' else 'ok' end, 'bases', bases, 'sources', src, 'manual_used', coalesce(p_manual, '{}'::jsonb),
    'steps', steps, 'lines', lines, 'party_totals', ptot, 'carry_in', carry_in, 'carry_out', carry_out, 'retained', round(retained, 2), 'floor_added', round(floor_added, 2),
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'wrote', false);
end $function$;

-- ---- partner_settlement_save(bigint,date,date,jsonb,text,uuid) ----
CREATE OR REPLACE FUNCTION public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.partner_agreements; c jsonb; s public.partner_settlements;
begin
  perform public._a44_guard();
  if p_client is not null then perform public._client_lock(p_client); select * into s from public.partner_settlements where client_id = p_client; if found then return to_jsonb(s); end if; end if;
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  if p_from < a.effective_from or (a.effective_to is not null and p_to > a.effective_to) then raise exception 'outside_deed_dates'; end if;
  if p_to > public._a44_today() then raise exception 'bad_date'; end if;
  perform public.lock_check(p_to);
  if exists (select 1 from public.partner_settlements x where x.agreement_id in (select id from public._a44_chain(p_agr)) and x.status <> 'void' and x.period_from <= p_to and x.period_to >= p_from) then raise exception 'period_overlap'; end if;
  c := public.partner_calculate(p_agr, p_from, p_to, p_manual);
  if c ->> 'status' <> 'ok' then raise exception 'calc_incomplete'; end if;
  -- bos80: partner_base_estimate = refuse: a settlement whose profit base uses an ESTIMATED cost of goods is not saved (a typed manual base replaces the book base)
  if coalesce(public.rule_txt('partner_base_estimate'), 'warn') = 'refuse'
     and exists (select 1 from jsonb_array_elements(c -> 'warnings') w where w ->> 'code' = 'estimated_base')
     and exists (select 1 from public.partner_rules r where r.agreement_id = p_agr and r.active and r.config ->> 'base' in ('gross_profit', 'net_profit'))
     and not (coalesce(p_manual, '{}'::jsonb) ? 'gross_profit' or coalesce(p_manual, '{}'::jsonb) ? 'net_profit_before_fees') then
    raise exception 'base_estimated';
  end if;
  insert into public.partner_settlements (agreement_id, period_from, period_to, status, calc, manual_base, total_distributable, carry_out, note, client_id, created_by)
    values (p_agr, p_from, p_to, 'draft', c, p_manual, (c ->> 'total_distributable')::numeric, (c ->> 'carry_out')::numeric, left(p_note, 1000), p_client, auth.uid()) returning * into s;
  insert into public.partner_settlement_lines (settlement_id, party_id, amount, kind, funded_outside)
    select s.id, (e ->> 'party_id')::bigint, round(sum((e ->> 'amount')::numeric), 2), e ->> 'kind', coalesce((e ->> 'outside')::boolean, false)
      from jsonb_array_elements(c -> 'lines') e group by 2, 4, 5 having round(sum((e ->> 'amount')::numeric), 2) > 0;
  return to_jsonb(s);
end $function$;

-- ---- pool_set(integer,date,text,numeric,text,boolean,text,uuid) ----
CREATE OR REPLACE FUNCTION public.pool_set(p_loc integer, p_month date, p_type text, p_amount numeric, p_period_kind text DEFAULT 'month'::text, p_one_off boolean DEFAULT false, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month); alloc boolean;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.factory_cost_pools where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  perform public.lock_check(m);
  update public.factory_cost_pools set active = false where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'manual' and active;
  insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, note, client_id, created_by)
    values (p_loc, m, p_type, p_period_kind, p_amount, coalesce(p_one_off, false), 'manual', left(p_note, 200), p_client, auth.uid()) returning id into nid;
  alloc := exists (select 1 from public.factory_cost_pools where location_id = p_loc and month = m and component_type = p_type and period_kind = p_period_kind and source = 'allocated' and active);      -- bos75
  if alloc then
    perform public._stock_exc(p_loc, 'pool_double_entry', 'yellow', 'এই মাসের এই খরচ বিল থেকে আগেই এসেছে — হাতে আবার লিখলে দুবার গোনা হবে',
      'A cost bill already feeds this pool - a manual amount on top is counted twice', null, m, 'STOCK');
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $function$;

-- ---- production_post(integer,uuid,numeric,uuid,timestamp with time zone,text) ----
CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid DEFAULT NULL::uuid, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.production_post(p_loc, p_recipe, p_batches, p_client, p_made_at, p_note, null::numeric);
$function$;

-- ---- production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric) ----
CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamp with time zone, p_note text, p_actual_yield numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; nocost text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
        outq numeric; conv jsonb; conv_amt numeric := 0; cinc boolean; yvp numeric; ythr numeric;   -- bos74
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  it := public._stock_guard(r.item_id, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into run from public.production_runs where client_id = p_client;
    if found then
      if run.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'run_id', run.id, 'ledger_id', run.ledger_in_id, 'batch_id', run.batch_id, 'qty', run.yield_base);
    end if;
  end if;
  if not r.active then raise exception 'recipe_inactive'; end if;
  gate := public._recipe_gate73(r.id);      -- bos73: on = refuse an unapproved recipe; warn = a yellow line below
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_actual_yield is not null and not (round(p_actual_yield, 4) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;      -- bos74
  outq := case when p_actual_yield is null then yb else round(p_actual_yield, 4) end;      -- bos74: what is really booked into stock
  -- everything that leaves the stock: checks first, nothing is posted until all are fine
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0
         and not public._cost_free80(n.item_id) then      -- bos80: an item marked 'cost really zero' is a known cost
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then cost_ok := false; else tot := tot + n.need * coalesce(av, 0); end if;   -- bos72: cost 0 = unknown; bos80: unless the item is marked 'cost really zero'
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- bos74: conversion cost (layer 2) of this run: off = nothing (today's behaviour); recipe = the recipe's rates; pool = monthly pool / NORMAL output
  conv := public._conv_cost(r.id, p_loc, p_batches, outq, (at_ at time zone 'Asia/Dhaka')::date);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); cinc := (conv->>'mode') <> 'off' and not (conv->>'complete')::boolean;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      conversion_mode = conv->>'mode', conversion_complete = not cinc, conversion_detail = conv->'detail', yield_std = yb, yield_actual = p_actual_yield, yield_var_pct = yvp where id = rid;   -- bos74
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  if cinc then      -- bos74
    perform public._stock_exc(p_loc, 'conversion_incomplete', 'yellow', it.name_bn || ': রূপান্তর খরচ অসম্পূর্ণ (খালি ঘর আছে) — যা জানা ছিল শুধু তা ধরা হয়েছে',
      coalesce(it.name_en, it.name_bn) || ': conversion cost incomplete (blank amounts) — only the known part was booked', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $function$;

-- ---- recipe_approve(uuid,text) ----
CREATE OR REPLACE FUNCTION public.recipe_approve(p_recipe uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; prev jsonb; selfap boolean := false; sid text;   -- bos87
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() then   -- bos87: the owner is never refused; others as before (switch recipe_self_approve)
    if public.is_owner() or public.rule_on('recipe_self_approve') then selfap := true; else raise exception 'self_approve_refused'; end if;   -- bos87
  end if;   -- bos87
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  if selfap then   -- bos87
    select staff_id into sid from public.profiles where id = auth.uid();   -- bos87
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos87
      values (auth.uid(), sid, 'self_approved', 'recipes', r.id::text, jsonb_build_object('self_approved', true, 'owner', public.is_owner(), 'note', left(p_note, 200), 'src', 'phase87'));   -- bos87
  end if;   -- bos87
  return jsonb_build_object('recipe_id', r.id, 'approved', true) || public._self_approve_hint87(selfap);   -- bos87
end $function$;

-- ---- recipe_cost(uuid,integer) ----
CREATE OR REPLACE FUNCTION public.recipe_cost(p_recipe uuid, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  for n in select * from public._recipe_need(p_recipe, 1, coalesce(p_loc, 0)) order by kind, code loop      -- bos74: the same function the production run uses
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = n.item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    td := public._today_cost(n.item_id, p_loc);
    if av is null then complete := false;
    elsif n.kind = 'packaging' then pack_t := pack_t + n.need * av; else raw_t := raw_t + n.need * av; end if;
    if td is null then fb := fb + 1; end if;
    if coalesce(td, av) is not null then
      if n.kind = 'packaging' then pack_d := pack_d + n.need * coalesce(td, av); else raw_d := raw_d + n.need * coalesce(td, av); end if;
    end if;
    gl := case when av is not null and av > 0 and td is not null then round((td - av) / av * 100, 2) end;
    ls := ls || jsonb_build_object('ingredient_item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'need_base', n.need, 'unit_cost', av, 'line_cost', case when av is null then null else round(n.need * av, 4) end,
      'today_unit_cost', td, 'gap_pct', gl, 'waste_missing', n.waste_missing);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, (now() at time zone 'Asia/Dhaka')::date, case when p_loc is null then 'recipe' end);
  conv_amt := coalesce((conv->>'amount')::numeric, 0); mode_ := conv->>'mode'; cinc := mode_ <> 'off' and not (conv->>'complete')::boolean;
  mat := raw_t + pack_t; matd := raw_d + pack_d;
  gap := case when complete and mat > 0 then round((matd - mat) / mat * 100, 2) end;
  thr := public.rule_num('cost_gap_warn_pct');
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete,
    'rows', jsonb_build_array(jsonb_build_object('row', 'raw', 'amount', case when complete then round(raw_t, 4) end), jsonb_build_object('row', 'packaging', 'amount', case when complete then round(pack_t, 4) end),
      jsonb_build_object('row', 'conversion', 'amount', round(conv_amt, 4), 'mode', mode_, 'complete', not cinc)),
    'raw_cost', case when complete then round(raw_t, 4) end, 'packaging_cost', case when complete then round(pack_t, 4) end, 'material_cost', case when complete then round(mat, 4) end,
    'conversion_cost', round(conv_amt, 4), 'conversion_mode', mode_, 'conversion_complete', not cinc, 'conversion_detail', conv->'detail', 'conversion_reason', conv->>'reason',
    'conversion_flag', case when cinc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'batch_cost', case when complete then round(mat + conv_amt, 4) end,
    'unit_cost', case when complete and yb > 0 then round((mat + conv_amt) / yb, 6) end, 'yield_base', yb,
    'approved', r.approved_at is not null, 'approval_warn', gate = 'warn',
    'today', jsonb_build_object('raw_cost', round(raw_d, 4), 'packaging_cost', round(pack_d, 4), 'material_cost', round(matd, 4), 'batch_cost', round(matd + conv_amt, 4),
      'unit_cost', case when yb > 0 then round((matd + conv_amt) / yb, 6) end, 'gap_pct', gap, 'gap_warn', thr is not null and gap is not null and abs(gap) > thr,
      'lines_without_purchase_price', fb, 'note', 'display only - never booked'));
end $function$;

-- ---- sale_return(uuid,uuid,jsonb,text,text,text,text,text) ----
CREATE OR REPLACE FUNCTION public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text DEFAULT NULL::text, p_refund_mode text DEFAULT NULL::text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; r public.sale_returns; it public.items; ln record; rid uuid := gen_random_uuid(); pamt numeric; sq numeric; samt numeric; su text; pq numeric; price numeric; lamt numeric;
        gross numeric := 0; amt numeric; credit numeric := 0; refund numeric; bal numeric; fac numeric; out_lines jsonb := '[]'::jsonb; sid text;
        bq numeric; prior numeric; skip numeric; rem numeric; take numeric; o record; avail numeric; lid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into r from public.sale_returns where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() and not public.has_grant('sale_return', r.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount);
    end if;
  end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (public.has_grant('sale_return', s.location_id) or public._use_em('sale_return', s.location_id, 'sale_return:' || p_sale::text, null)) then raise exception 'not allowed'; end if;
  -- every line is checked before anything is cast: a malformed uuid / quantity is bad_item / bad_qty, never a raw cast error
  for ln in select e from jsonb_array_elements(p_lines) e loop
    if jsonb_typeof(ln.e) <> 'object' or coalesce(ln.e->>'item_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'bad_item'; end if;
    if coalesce(ln.e->>'qty', '') !~ '^[0-9]{1,9}(\.[0-9]{1,6})?$' then raise exception 'bad_qty'; end if;
  end loop;
  perform 1 from public.sales where id = p_sale for update;                  -- one return at a time per sale
  select * into s from public.sales where id = p_sale;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  -- same item twice in p_lines is added up
  for ln in select e->>'item_id' iid, sum((e->>'qty')::numeric) q from jsonb_array_elements(p_lines) e group by 1 loop
    if ln.iid is null or ln.q is null or not (ln.q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0), coalesce(sum((e->>'amount')::numeric), 0), max(e->>'unit')
      into sq, samt, su from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = ln.iid;
    if sq <= 0 then raise exception 'line_not_in_sale'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0) into pq from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    if ln.q > sq - pq + 0.00005 then raise exception 'return_exceeds_sale'; end if;
    select coalesce(sum((e->>'amount')::numeric), 0) into pamt from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    price := samt / sq;
    -- the last unit takes what is left of the line's money, so partial returns add up to the line exactly
    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);
  end loop;
  if not (gross between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  fac := case when s.subtotal > 0 then s.total / s.subtotal else 1 end;               -- the sale's discount is shared in proportion
  amt := round(gross * fac, 2);
  if not (amt between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  if s.customer_id is not null then perform pg_advisory_xact_lock(hashtextextended('bos12c:' || s.customer_id::text, 0)); end if;
  if s.customer_id is not null and public.rule_on('sale_return_due_first') then
    bal := coalesce(public._cust_bal(s.customer_id), 0);
    credit := least(amt, greatest(bal, 0));
  end if;
  refund := amt - credit;
  if refund > 0 and (p_refund_mode is null or p_refund_mode not in ('cash', 'mobile', 'card')) then raise exception 'refund_mode_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.sale_returns (id, client_id, sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, wallet, ref, reason_code, note, created_by, created_staff)
      values (rid, p_client, s.id, s.location_id, s.customer_id, out_lines, amt, credit, refund, case when refund > 0 then p_refund_mode end, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), p_reason, left(nullif(btrim(p_note), ''), 300), auth.uid(), sid);
  exception when unique_violation then
    select * into r from public.sale_returns where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount); end if;
    raise;
  end;
  -- stock back (tracked items), batch aware
  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid;
    if it.tracked is not true then continue; end if;
    bq := public._base_qty(it.id, ln.q, ln.u);
    if bq is null then
      perform public._stock_exc(s.location_id, 'stock_unit_unknown', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, ফেরত মাল স্টকে ওঠেনি',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, the returned goods were NOT put back', s.id, s.sale_date, 'POS');
      continue;
    end if;
    rem := round(bq, 4);
    -- what earlier (live) returns of this sale already put back for this item
    select coalesce(sum(l.qty_delta), 0) into prior from public.stock_ledger l
      where l.item_id = it.id and l.ref_type = 'sale_return' and l.ref_id in (select x.id::text from public.sale_returns x where x.sale_id = s.id and x.id <> rid);
    skip := prior;
    for o in select * from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
             and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
      exit when rem <= 0;
      avail := -o.qty_delta;
      if skip >= avail then skip := skip - avail; continue; end if;
      avail := avail - skip; skip := 0;
      take := least(avail, rem);
      perform public.stock_post(it.id, s.location_id, take, 'sale_return', 'sale_return', rid::text, o.unit_cost, o.batch_id, now(), left('return of receipt ' || s.receipt, 200), null, 'none');
      rem := rem - take;
    end loop;
    if rem >= 0.0005 then            -- no sale_out ledger row covers this (stock tracking was switched on after the sale): nothing is invented, the owner is told
      perform public._stock_exc(s.location_id, 'return_no_stock_trace', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — বিক্রির স্টক-হিসাব নেই, ফেরত মাল স্টকে ওঠেনি (টাকা ফেরত/বাকি কমা হয়েছে)',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the sale has no stock ledger trace, the returned goods were NOT put back (money / due credit was still given)', s.id, s.sale_date, 'POS');
    end if;
  end loop;
  if coalesce(public.rule_txt('packaging_return_mode'), 'none') <> 'none' then      -- bos80: packaging of a returned product (none = today)
    perform public._ret_pack80(rid, s.id, out_lines);
  end if;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $function$;

-- ---- sales_channel_save(integer,text,text,text,text,integer,text,text,boolean) ----
CREATE OR REPLACE FUNCTION public.sales_channel_save(p_id integer, p_code text, p_kind text, p_other text, p_name text, p_loc integer, p_role text, p_account_ref text, p_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'telegram', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;   -- bos86: + telegram
  if p_kind = 'telegram' and nullif(btrim(p_account_ref), '') is null then raise exception 'account_ref_required'; end if;                           -- bos86
  if p_kind = 'other' and nullif(btrim(p_other), '') is null then raise exception 'other_text_required'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 60 then raise exception 'name_required'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_role is not null and not exists (select 1 from public.roles where code = p_role) then raise exception 'role_not_found'; end if;
  if p_id is null then
    insert into public.sales_channels (code, kind, other_text, name_bn, location_id, role_code, account_ref, active, created_by)
      values (p_code, p_kind, case when p_kind = 'other' then left(btrim(p_other), 60) end, btrim(p_name), p_loc, p_role, nullif(btrim(p_account_ref), ''), coalesce(p_active, true), auth.uid()) returning * into c;
  else
    update public.sales_channels set code = p_code, kind = p_kind, other_text = case when p_kind = 'other' then left(btrim(p_other), 60) end, name_bn = btrim(p_name), location_id = p_loc,
        role_code = p_role, account_ref = nullif(btrim(p_account_ref), ''), active = coalesce(p_active, true), updated_at = now() where id = p_id returning * into c;
    if not found then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', c.id, 'code', c.code, 'active', c.active);
end $function$;

-- ---- stock_count_adjust(uuid,integer,numeric,text,text,uuid) ----
CREATE OR REPLACE FUNCTION public.stock_count_adjust(p_item uuid, p_loc integer, p_counted numeric, p_note text, p_unit text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; bal public.stock_balance; d numeric; lid bigint; tol numeric;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_count_adjust', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'count_adjust' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_counted is null or not (p_counted between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  bq := public._base_qty(p_item, p_counted, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_count_adjust', p_loc, 'count:' || p_item::text) then raise exception 'not allowed'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;
  d := round(bq - bal.qty, 4);
  if d = 0 then return jsonb_build_object('ledger_id', null, 'delta', 0, 'qty', bal.qty); end if;
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, case when d > 0 and public.rule_on('acct_count_adjust') then bal.avg_cost end /* bos85: a gain is recorded at the average cost so it has a known cost; the average does not move */, null, now(), left(p_note, 200), null, 'none', null, p_client);
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $function$;

-- ---- stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid) ----
CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false; pm text; who text;   -- bos82
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale') or coalesce(public.rule_txt('expiry_sale_guard'), 'off') = 'refuse'; end if;           -- (12) read once; bos87: expiry_sale_guard = refuse acts like the block_expired_sale switch
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    -- bos82: production that takes an ingredient below zero: reason needed (production_negative_reason: off | warn | required)
    if p_reason = 'issue_out' and p_ref_type = 'production' then   -- bos82
      pm := coalesce(public.rule_txt('production_negative_reason'), 'off');   -- bos82
      if pm <> 'off' then   -- bos82
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      if mode = 'block' and p_neg = 'full' and public.rule_on('neg_grant_log') and public.has_grant('sell_below_zero', p_loc) then   -- bos82: the grant was used to go below zero: tell the owner who / what / how much
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        perform public._stock_exc(p_loc, 'sell_below_zero_used', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): "stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): the sell-below-zero permission was used, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', মেয়াদ ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end,   -- bos87
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold'
            || case when coalesce(public.rule_txt('expiry_sale_guard'), 'off') <> 'off' then ' — batch ' || b.id::text || ', expired ' || (b.expires_at at time zone 'Asia/Dhaka')::date::text else '' end, p_sale, d, form);   -- bos87
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $function$;

-- ---- stock_receive_transfer(uuid,numeric,text) ----
CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; cost numeric; ob public.stock_batches; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty then raise exception 'over_received'; end if;
  rem := rq;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    take := least(-o.qty_delta, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || rq::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || rq::text || ' — short in transit');
  end if;
  if rq < t.qty and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss
    perform public._transit_loss83(t.id, t.qty - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', rq, 'short', t.qty - rq);
end $function$;

-- ---- stock_reconcile(boolean) ----
CREATE OR REPLACE FUNCTION public.stock_reconcile(p_fix boolean DEFAULT false)
 RETURNS TABLE(item_id uuid, location_id integer, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric;
        sid text;                                                                                            -- bos84
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in
    select k.iid, k.lid from (select x.item_id iid, x.location_id lid from public.stock_ledger x group by 1, 2
                              union select y.item_id, y.location_id from public.stock_balance y) k order by 1, 2 loop
    if p_fix then
      insert into public.stock_balance (item_id, location_id) values (r.iid, r.lid) on conflict do nothing;
      perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update;     -- nobody can post to this pair until we are done
    end if;
    select z.qty, z.avg_cost into bq, bavg from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid;
    bq := coalesce(bq, 0);
    q := 0; a := null;
    for l in select x.qty_delta, x.unit_cost, x.reason from public.stock_ledger x where x.item_id = r.iid and x.location_id = r.lid order by x.id loop
      a := public._avg_next(q, a, l.qty_delta, l.unit_cost, l.reason); q := q + l.qty_delta;
    end loop;
    if q <> bq or bavg is distinct from a then
      item_id := r.iid; location_id := r.lid; ledger_qty := q; cached_qty := bq; qty_diff := bq - q; cached_avg := bavg; replay_avg := a;
      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;
      return next;
    end if;
  end loop;
end $function$;

-- ---- urgent_alerts(timestamp with time zone) ----
CREATE OR REPLACE FUNCTION public.urgent_alerts(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._transit_open_scan83();      -- bos83: open transit older than the owner's limit becomes an urgent notification (blank limit = nothing)
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $function$;

-- ---------------------------------------------------------------- phase518.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase92.sql there and is already pasted on the live database under that name.
-- Renumbered to phase518.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 518 (bos92) - STEP Inv: show the invoice on screen right after a sale; Print / Email / SMS / WhatsApp / Share are device-side.
--   Needs phases 72..88 pasted first (guard below). Additive, paste-twice safe: one rule, one append-only table, two functions. No existing table or function is changed.
--
--   * Rule  pos_show_invoice_after_sale  (module pos, kind choice)
--       never   DEFAULT. Exactly today's behaviour: toast + the small "Print receipt" bar.  (Recommended for a shop with a phone-only owner: always.)
--       ask     After a sale a bar offers "Show invoice"; the cashier taps it when wanted.
--       always  The invoice opens on screen straight after every sale (a queued offline sale shows with a provisional number, marked pending sync).
--   * Table invoice_shares  - one row each time a cashier prints / emails / SMSes / WhatsApps / shares / copies / downloads an invoice.
--       APPEND-ONLY (update / delete / truncate are refused by triggers). No customer number or e-mail is stored, no cost data. Closed to the browser:
--       rows are written by invoice_share_log92 and read (owner / POS approve only) inside invoice_data92.
--   * invoice_data92(p_sale, p_client)  - one sale ready to show: header, lines, totals, VAT, payments, customer, staff.
--       SAFE FOR NON-COST USERS BY CONSTRUCTION: every line key is copied by name (item_id, code, name, name_en, name_mix, unit, qty, price, amount); nothing is `select *`d
--       from stock, item_costs or the ledger. Customer name is returned; the customer MOBILE only to the owner, POS approve, a view_customer_mobile holder, or the
--       cashier who made that very sale (customer_masked = true otherwise). E-mail is not held on file at all.
--   * invoice_share_log92(p_sale, p_channel, p_client) - the audited log call (channel print|email|sms|whatsapp, plus share|copy|download).
--   Sending itself happens from the user's own phone (mailto: / sms: / wa.me deep links). No provider, no secret, no server-side sending is built here.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._rcs88()') is null                                   -- 88 (and with it 72..87)
     or to_regprocedure('public.rpt_mobile_ok()') is null                         -- 9
     or to_regprocedure('public.can_loc(integer)') is null
     or to_regprocedure('public.can_do(text, text)') is null
     or to_regclass('public.sales') is null or to_regclass('public.sale_payments') is null or to_regclass('public.rules') is null then
    raise exception 'phase518 needs phases 72..88 pasted first';
  end if;
end $g$;

-- ---------- the switch ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('pos_show_invoice_after_sale', 'pos', 'choice', '"never"', null, '["never","ask","always"]'::jsonb, null, null,
  'বিক্রির পর ইনভয়েস পর্দায় দেখানো: কখনো না / জিজ্ঞেস / সবসময়', 'Sale এর পর invoice screen এ দেখানো: never / ask / always', 'Show the invoice on screen after a sale: never, ask or always',
  'কখনো না = আগের মতো (শুধু ছোট "রসিদ প্রিন্ট" বার)। জিজ্ঞেস = বিক্রির পর "ইনভয়েস দেখুন" বার আসে। সবসময় = প্রতি বিক্রির পরই ইনভয়েস পর্দায় খোলে, সেখান থেকে Print, Email, SMS, WhatsApp। সুপারিশ: সবসময়।',
  'never = আগের মতো (শুধু ছোট "Receipt Print" bar)। ask = sale এর পর "Invoice দেখুন" bar আসে। always = প্রতি sale এর পরই invoice screen এ খোলে, সেখান থেকে Print, Email, SMS, WhatsApp। Recommended: always।',
  'never = as before (only the small "Print receipt" bar). ask = a "Show invoice" bar appears after a sale. always = the invoice opens on screen after every sale, with Print, Email, SMS and WhatsApp buttons. Recommended: always, so the customer can see and receive the invoice even when no printer is connected. Email, SMS and WhatsApp open the phone''s own app; nothing is sent from our server.', 92)
on conflict (key) do nothing;

-- ---------- the audited share log (append-only) ----------
create table if not exists public.invoice_shares (
  id bigint generated always as identity primary key,
  sale_id uuid not null references public.sales(id),
  channel text not null check (channel in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download')),
  by_user uuid not null default auth.uid(),
  by_staff text,
  at timestamptz not null default now(),
  location_id int
);
create index if not exists invoice_shares_sale on public.invoice_shares (sale_id, at);
alter table public.invoice_shares enable row level security;
revoke all on table public.invoice_shares from public, anon, authenticated;     -- no policy, no grant: the browser never touches the table

create or replace function public._invoice_shares_ro92() returns trigger language plpgsql as $$
begin raise exception 'invoice_shares is append-only'; end $$;
revoke all on function public._invoice_shares_ro92() from public, anon, authenticated;
drop trigger if exists invoice_shares_no_change92 on public.invoice_shares;
create trigger invoice_shares_no_change92 before update or delete on public.invoice_shares for each row execute function public._invoice_shares_ro92();
drop trigger if exists invoice_shares_no_trunc92 on public.invoice_shares;
create trigger invoice_shares_no_trunc92 before truncate on public.invoice_shares for each statement execute function public._invoice_shares_ro92();
drop trigger if exists audit_invoice_shares on public.invoice_shares;
create trigger audit_invoice_shares after insert on public.invoice_shares for each row execute function public.log_change('id');

-- ---------- one sale, ready to show (no cost column anywhere) ----------
create or replace function public.invoice_data92(p_sale uuid default null, p_client uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  s public.sales; loc public.locations; cu public.customers; lines_j jsonb; pays_j jsonb; shares_j jsonb := '[]';
  mob_ok boolean; sub numeric; share numeric := 1; tx numeric; rate numeric; inc boolean; vat_j jsonb := null; can_log boolean;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  select * into loc from public.locations where id = s.location_id;
  -- lines: whitelist of keys, in sale order; names in all three languages from the item master
  select coalesce(jsonb_agg(jsonb_build_object(
      'item_id', e.v ->> 'item_id', 'code', coalesce(i.code, e.v ->> 'code'), 'name', e.v ->> 'name', 'name_en', i.name_en, 'name_mix', i.name_mix,
      'unit', e.v ->> 'unit', 'qty', coalesce((e.v ->> 'qty')::numeric, 1), 'price', coalesce((e.v ->> 'price')::numeric, (e.v ->> 'amount')::numeric),
      'amount', coalesce((e.v ->> 'amount')::numeric, 0), 'custom', coalesce((e.v ->> 'custom')::boolean, false)) order by e.n), '[]')
    into lines_j
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality e(v, n)
    left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('mode', p.mode, 'wallet', p.wallet, 'amount', p.amount) order by p.id), '[]') into pays_j
    from public.sale_payments p where p.sale_id = s.id and not p.voided and p.kind = 'sale';
  if s.customer_id is not null then select * into cu from public.customers where id = s.customer_id; end if;
  mob_ok := public.is_owner() or public.rpt_mobile_ok() or s.created_by = auth.uid();
  -- VAT: the same base as vat_report (VAT-applicable lines, after the bill discount share); shown only when the VAT switch is on and a rate is entered
  rate := public.rule_num('vat_rate'); inc := public.rule_on('vat_prices_include');
  if public.rule_on('vat_on') and rate is not null then
    sub := coalesce(s.subtotal, 0); if sub > 0 then share := (sub - coalesce(s.discount, 0)) / sub; end if;
    select coalesce(sum(coalesce((e.v ->> 'amount')::numeric, 0)) filter (where i.vat_applicable is true), 0) * share into tx
      from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e(v)
      left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
    vat_j := jsonb_build_object('rate', rate, 'included', coalesce(inc, false), 'taxable', round(tx, 2),
                                'amount', round(case when coalesce(inc, false) then tx * rate / (100 + rate) else tx * rate / 100 end, 2));
  end if;
  if public.is_owner() or public.can_do('POS', 'approve') then
    select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'by', x.by_staff, 'at', x.at) order by x.at desc), '[]') into shares_j
      from (select channel, by_staff, at from public.invoice_shares where sale_id = s.id order by at desc limit 20) x;
  end if;
  return jsonb_build_object(
    'id', s.id, 'client_id', s.client_id, 'receipt', s.receipt, 'location_id', s.location_id, 'location_code', loc.code,
    'location', jsonb_build_object('bn', loc.name_bn, 'mix', loc.name_mix, 'en', loc.name_en),
    'sale_date', s.sale_date, 'sold_at', s.sold_at, 'status', s.status, 'sale_type', s.sale_type, 'cashier', s.created_staff,
    'lines', lines_j, 'subtotal', s.subtotal, 'discount', s.discount, 'total', s.total, 'paid', s.paid, 'due', s.due_amount,
    'payments', pays_j, 'vat', vat_j,
    'customer', case when s.customer_id is null then case when s.customer is null then null else jsonb_build_object('name', s.customer, 'mobile', null, 'masked', false) end
                     else jsonb_build_object('name', cu.name, 'mobile', case when mob_ok then cu.mobile end, 'whatsapp', case when mob_ok then cu.whatsapp end, 'masked', not mob_ok) end,
    'shares', shares_j);
end $$;

-- ---------- the audited log call ----------
create or replace function public.invoice_share_log92(p_sale uuid default null, p_channel text default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare s public.sales; nid bigint;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_channel is null or p_channel not in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download') then raise exception 'bad_channel'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  insert into public.invoice_shares (sale_id, channel, by_user, by_staff, location_id)
    values (s.id, p_channel, auth.uid(), (select coalesce(nullif(full_name, ''), staff_id) from public.profiles where id = auth.uid()), s.location_id) returning id into nid;
  return nid;
end $$;

revoke all on function public.invoice_data92(uuid, uuid), public.invoice_share_log92(uuid, text, uuid) from public, anon;
grant execute on function public.invoice_data92(uuid, uuid), public.invoice_share_log92(uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------- phase519.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase93.sql there and is already pasted on the live database under that name.
-- Renumbered to phase519.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 519 (bos93) - STEP Tpl: selectable print / message templates per document type (and optionally per location).
--   Needs only the base schema (guard below: is_owner, is_active, audit_log, locations). Additive, paste-twice safe: one table, two functions, nothing else is touched.
--   The templates themselves live in the web app (web/tpl_*.js); the database only remembers WHICH template id the owner picked.
--   No row = no choice = today's output, unchanged (the app falls back to what it printed before).
--   A location row beats the all-locations row (location_id null) of the same document type.
--   set_doc_template is owner-only; passing a null template clears the choice (back to today's output). Every change is written to audit_log.
-- ============================================================

do $g$ begin
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null
     or to_regclass('public.audit_log') is null or to_regclass('public.locations') is null then
    raise exception 'phase519 needs the base schema (is_owner, is_active, audit_log, locations)';
  end if;
end $g$;

create table if not exists public.doc_template_choice (
  id          bigserial primary key,
  doc_type    text not null check (doc_type ~ '^[a-z][a-z0-9_]{1,40}$'),
  location_id int references public.locations(id),
  template_id text not null check (template_id ~ '^[a-z][a-z0-9_]{1,40}$'),
  set_by      uuid,
  set_at      timestamptz not null default now()
);
-- one choice per document type and place (null location = all locations)
create unique index if not exists doc_template_choice_uq on public.doc_template_choice (doc_type, coalesce(location_id, 0));

alter table public.doc_template_choice enable row level security;
drop policy if exists doc_template_choice_read on public.doc_template_choice;
create policy doc_template_choice_read on public.doc_template_choice for select to authenticated using (public.is_active());
-- nobody writes the table directly; the owner goes through set_doc_template
revoke insert, update, delete, truncate on public.doc_template_choice from public, anon, authenticated;
grant select on public.doc_template_choice to authenticated;

create or replace function public.set_doc_template(p_doc_type text, p_template_id text, p_location_id int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old text; sid text;
begin
  if not public.is_owner() then raise exception 'owner_only'; end if;
  if p_doc_type is null or p_doc_type !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_doc_type'; end if;
  if p_template_id is not null and p_template_id !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_template_id'; end if;
  if p_location_id is not null and not exists (select 1 from public.locations where id = p_location_id) then raise exception 'bad_location'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  select template_id into old from public.doc_template_choice where doc_type = p_doc_type and coalesce(location_id, 0) = coalesce(p_location_id, 0);
  if p_template_id is null then
    delete from public.doc_template_choice where doc_type = p_doc_type and coalesce(location_id, 0) = coalesce(p_location_id, 0);
  else
    insert into public.doc_template_choice (doc_type, location_id, template_id, set_by, set_at) values (p_doc_type, p_location_id, p_template_id, auth.uid(), now())
    on conflict (doc_type, (coalesce(location_id, 0))) do update set template_id = excluded.template_id, set_by = excluded.set_by, set_at = excluded.set_at;
  end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)   -- bos93
    values (auth.uid(), sid, case when p_template_id is null then 'doc_template_clear' else 'doc_template_set' end, 'doc_template_choice', p_doc_type || ':' || coalesce(p_location_id::text, 'all'),
            jsonb_build_object('doc_type', p_doc_type, 'location_id', p_location_id, 'old', old, 'new', p_template_id, 'src', 'phase93'));
  return jsonb_build_object('doc_type', p_doc_type, 'location_id', p_location_id, 'template_id', p_template_id, 'old', old);
end $$;
revoke all on function public.set_doc_template(text, text, int) from public, anon;
grant execute on function public.set_doc_template(text, text, int) to authenticated;

-- every saved choice (small table). The app resolves: this location first, then the all-locations row, else nothing (= today's output).
create or replace function public.get_doc_templates(p_location_id int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('doc_type', c.doc_type, 'location_id', c.location_id, 'template_id', c.template_id, 'set_at', c.set_at,
                    'effective', (c.location_id is null and not exists (select 1 from public.doc_template_choice x where x.doc_type = c.doc_type and x.location_id = p_location_id))
                                 or c.location_id = p_location_id) order by c.doc_type, c.location_id nulls first)
                   from public.doc_template_choice c), '[]'::jsonb);
end $$;
revoke all on function public.get_doc_templates(int) from public, anon;
grant execute on function public.get_doc_templates(int) to authenticated;

-- ---------------------------------------------------------------- phase521.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase95.sql there and is already pasted on the live database under that name.
-- Renumbered to phase521.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 521 (bos95) - STEP Drw: an OPTION so a cash drawer can be connected later. (phase520 is reserved for the security step.)
--   Needs only the base schema + phase 8 (guard below). Additive, paste-twice safe: 4 rules, 1 grant, 1 append-only table, 3 functions. No existing table or function is changed.
--   Default = OFF = exactly today's behaviour: nothing opens, nothing is logged, POS is untouched.
--
--   Rules (module pos):
--     cash_drawer_mode     off (DEFAULT) | on_cash_sale | on_any_sale | manual_only      when the app asks the drawer to open
--     cash_drawer_when     before_payment | after_payment (DEFAULT)                       relative to saving the sale
--     cash_drawer_method   none (DEFAULT) | browser_print_pulse | web_serial | web_usb | bluetooth | kiosk_url
--                          Only methods a browser on a phone/PC can really do are built; kiosk_url is a PLANNED placeholder (the app says so).
--     cash_drawer_no_sale_requires_reason   switch, DEFAULT on: a "no sale" open must carry a reason.
--   Grant drawer_nosale: who may open the drawer with no sale (owner always may).
--   Table drawer_events: APPEND-ONLY audit of every open (auto_open | no_sale_open | test_open | failed). A test open is allowed to anyone who can use POS (setting up the till), and is counted separately in the report. No amounts, no cost, no customer data.
--   drawer_event_log(...)  idempotent by client id (offline queue can replay it safely); drawer_settings(); drawer_report(from,to) owner / view_reports only.
--   The drawer itself is opened from the user's own device (web/cashdrawer.js). The server only remembers the setting and the audit trail.
-- ============================================================

do $g$ begin
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null
     or to_regprocedure('public.has_grant(text, integer)') is null or to_regprocedure('public.can_loc(integer)') is null
     or to_regprocedure('public.can_do(text, text)') is null or to_regprocedure('public.log_change()') is null
     or to_regclass('public.rules') is null or to_regclass('public.grant_defs') is null or to_regclass('public.profiles') is null
     or to_regclass('public.locations') is null then
    raise exception 'phase521 needs the base schema and phase 8 (is_owner, is_active, has_grant, can_loc, can_do, log_change, rules, grant_defs, profiles, locations)';
  end if;
end $g$;

-- ---------- the switches (all default to today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('cash_drawer_mode', 'pos', 'choice', '"off"', null, '["off","on_cash_sale","on_any_sale","manual_only"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: কখন খুলবে', 'Cash drawer: কখন খুলবে', 'Cash drawer: when it opens',
  'off = আগের মতো (ড্রয়ার কিছু করে না)। on_cash_sale = ক্যাশ পেমেন্ট নিলে খোলার অনুরোধ। on_any_sale = যেকোনো বিক্রিতে। manual_only = শুধু "No sale" বোতামে। ড্রয়ার না থাকলে বিক্রি কখনো আটকায় না।',
  'off = আগের মতো (drawer কিছু করে না)। on_cash_sale = cash payment নিলে open এর request। on_any_sale = যেকোনো sale এ। manual_only = শুধু "No sale" button এ। Drawer না থাকলে sale কখনো আটকায় না।',
  'off = as today (the drawer does nothing). on_cash_sale = ask the drawer to open when cash is taken. on_any_sale = on every sale. manual_only = only from the "No sale" button. A missing or broken drawer never blocks a sale. Recommended once a drawer is fitted: on_cash_sale.', 950),
 ('cash_drawer_when', 'pos', 'choice', '"after_payment"', null, '["before_payment","after_payment"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: বিক্রি সেভের আগে নাকি পরে', 'Cash drawer: sale save এর আগে নাকি পরে', 'Cash drawer: before or after the sale is saved',
  'after_payment = বিক্রি সফল হলে তবেই খোলে (ডিফল্ট)। before_payment = সেভের বোতাম চাপলেই খোলে, সফল না হলেও।',
  'after_payment = sale সফল হলে তবেই খোলে (default)। before_payment = Save button চাপলেই খোলে, সফল না হলেও।',
  'after_payment = opens only once the sale is saved (default; recommended). before_payment = opens as soon as Save is tapped, even if the sale then fails.', 951),
 ('cash_drawer_method', 'pos', 'choice', '"none"', null, '["none","browser_print_pulse","web_serial","web_usb","bluetooth","kiosk_url"]'::jsonb, null, null,
  'ক্যাশ ড্রয়ার: সংযোগের ধরন', 'Cash drawer: connection type', 'Cash drawer: connection type',
  'none = কিছু না। browser_print_pulse = প্রিন্টারের ড্রাইভারে "print এর সময় drawer খোলো" চালু থাকলে। web_serial / web_usb / bluetooth = ডিভাইসে সরাসরি ESC/POS সংকেত (Android Chrome বা কম্পিউটার)। kiosk_url = পরিকল্পিত, এখনো কাজ করে না।',
  'none = কিছু না। browser_print_pulse = printer driver এ "print এর সময় drawer খোলো" on থাকলে। web_serial / web_usb / bluetooth = device এ সরাসরি ESC/POS signal (Android Chrome বা computer)। kiosk_url = planned, এখনো কাজ করে না।',
  'none = nothing. browser_print_pulse = a tiny print job; works when the printer driver is set to open the drawer on print. web_serial / web_usb / bluetooth = send the ESC/POS pulse straight to the device (Chrome on Android or a computer; iPhone browsers cannot). kiosk_url = PLANNED, not built yet.', 952),
 ('cash_drawer_no_sale_requires_reason', 'pos', 'switch', 'true', null, null, null, null,
  'ক্যাশ ড্রয়ার: "No sale" খুলতে কারণ লাগবে', 'Cash drawer: "No sale" open এ reason লাগবে', 'Cash drawer: a "No sale" open needs a reason',
  'চালু = কারণ না লিখলে No-sale খোলা যায় না (ডিফল্ট, প্রস্তাবিত)।', 'On = reason না লিখলে No-sale open হয় না (default, recommended)।',
  'On = a no-sale open cannot be logged without a reason (default and recommended: every open without a sale is an anti-theft signal).', 953)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('drawer_nosale', 'pos', 95, 'বিক্রি ছাড়া ক্যাশ ড্রয়ার খোলা (No sale)', 'Sale ছাড়া Cash drawer খোলা (No sale)', 'Open the cash drawer with no sale', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- the audit trail (append-only) ----------
create table if not exists public.drawer_events (
  id bigint generated always as identity primary key,
  client_id uuid not null,
  event text not null check (event in ('auto_open', 'no_sale_open', 'test_open', 'failed')),
  location_id int,
  by_user uuid not null default auth.uid(),
  by_staff text,
  sale_ref text check (sale_ref is null or length(sale_ref) <= 80),
  reason text check (reason is null or length(reason) <= 300),
  method text check (method is null or method ~ '^[a-z_]{1,30}$'),
  at timestamptz not null default now(),          -- when it happened on the device (an offline queue may log later)
  logged_at timestamptz not null default now()
);
create unique index if not exists drawer_events_client on public.drawer_events (client_id);
create index if not exists drawer_events_at on public.drawer_events (at);
create index if not exists drawer_events_user on public.drawer_events (by_user, event, at);
alter table public.drawer_events enable row level security;
revoke all on table public.drawer_events from public, anon, authenticated;     -- the browser never touches the table; only the functions below

create or replace function public._drawer_events_ro95() returns trigger language plpgsql as $$
begin raise exception 'drawer_events is append-only'; end $$;
revoke all on function public._drawer_events_ro95() from public, anon, authenticated;
drop trigger if exists drawer_events_no_change95 on public.drawer_events;
create trigger drawer_events_no_change95 before update or delete on public.drawer_events for each row execute function public._drawer_events_ro95();
drop trigger if exists drawer_events_no_trunc95 on public.drawer_events;
create trigger drawer_events_no_trunc95 before truncate on public.drawer_events for each statement execute function public._drawer_events_ro95();
drop trigger if exists audit_drawer_events on public.drawer_events;
create trigger audit_drawer_events after insert on public.drawer_events for each row execute function public.log_change('id');

-- ---------- settings the screen and POS read ----------
create or replace function public.drawer_settings(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'mode', coalesce(public.rule_txt('cash_drawer_mode'), 'off'),
    'when', coalesce(public.rule_txt('cash_drawer_when'), 'after_payment'),
    'method', coalesce(public.rule_txt('cash_drawer_method'), 'none'),
    'no_sale_requires_reason', coalesce(public.rule_on('cash_drawer_no_sale_requires_reason'), true),
    'can_no_sale', public.has_grant('drawer_nosale', p_loc),
    'can_report', (public.is_owner() or public.has_grant('view_reports')),
    'is_owner', public.is_owner(),
    'methods', jsonb_build_array(
      jsonb_build_object('id', 'none', 'status', 'ready'),
      jsonb_build_object('id', 'browser_print_pulse', 'status', 'ready'),
      jsonb_build_object('id', 'web_serial', 'status', 'ready'),
      jsonb_build_object('id', 'web_usb', 'status', 'ready'),
      jsonb_build_object('id', 'bluetooth', 'status', 'experimental'),
      jsonb_build_object('id', 'kiosk_url', 'status', 'planned')));
end $$;
revoke all on function public.drawer_settings(int) from public, anon;
grant execute on function public.drawer_settings(int) to authenticated;

-- ---------- log one drawer event (idempotent by client id) ----------
create or replace function public.drawer_event_log(p_client uuid, p_event text, p_loc int default null, p_sale_ref text default null,
                                                    p_reason text default null, p_method text default null, p_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r text := nullif(btrim(coalesce(p_reason, '')), ''); t timestamptz; v_id bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_required'; end if;
  if p_event is null or p_event not in ('auto_open', 'no_sale_open', 'test_open', 'failed') then raise exception 'bad_event'; end if;
  if p_loc is not null then
    if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  end if;
  if not (public.is_owner() or public.can_do('POS', 'enter') or public.can_do('POS', 'view')) then raise exception 'not allowed'; end if;
  if p_event = 'no_sale_open' then
    if not public.has_grant('drawer_nosale', p_loc) then raise exception 'not allowed'; end if;
    if r is null and coalesce(public.rule_on('cash_drawer_no_sale_requires_reason'), true) then raise exception 'reason_required'; end if;
  end if;
  -- a device clock that is wildly off must not rewrite history: outside [-30 days, +5 minutes] the server time is used
  t := case when p_at is not null and p_at <= now() + interval '5 minutes' and p_at >= now() - interval '30 days' then p_at else now() end;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.drawer_events (client_id, event, location_id, by_user, by_staff, sale_ref, reason, method, at)
    values (p_client, p_event, p_loc, auth.uid(), sid, left(p_sale_ref, 80), left(r, 300), case when p_method ~ '^[a-z_]{1,30}$' then p_method end, t)
    on conflict (client_id) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('client_id', p_client, 'dup', true); end if;
  return jsonb_build_object('client_id', p_client, 'id', v_id, 'dup', false);
end $$;
revoke all on function public.drawer_event_log(uuid, text, int, text, text, text, timestamptz) from public, anon;
grant execute on function public.drawer_event_log(uuid, text, int, text, text, text, timestamptz) to authenticated;

-- ---------- the anti-theft view: counts per person (owner or a view_reports holder only) ----------
create or replace function public.drawer_report(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 29); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); res jsonb;
begin
  if not (public.is_owner() or public.has_grant('view_reports')) then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_range'; end if;
  if t - f > 366 then raise exception 'range_too_long'; end if;
  with e as (
    select d.*, (d.at at time zone 'Asia/Dhaka')::date as day from public.drawer_events d where (d.at at time zone 'Asia/Dhaka')::date between f and t)
  select jsonb_build_object(
    'from', f, 'to', t,
    'totals', jsonb_build_object(
      'auto_open', (select count(*) from e where event = 'auto_open'), 'no_sale_open', (select count(*) from e where event = 'no_sale_open'),
      'test_open', (select count(*) from e where event = 'test_open'), 'failed', (select count(*) from e where event = 'failed')),
    'by_user', coalesce((select jsonb_agg(x order by (x ->> 'no_sale_open')::int desc, x ->> 'staff') from (
        select jsonb_build_object('user_id', by_user, 'staff', coalesce(max(by_staff), ''), 'name', coalesce(max(p.full_name), ''),
                 'no_sale_open', count(*) filter (where event = 'no_sale_open'), 'auto_open', count(*) filter (where event = 'auto_open'),
                 'failed', count(*) filter (where event = 'failed'), 'last_no_sale', max(e.at) filter (where event = 'no_sale_open')) as x
        from e left join public.profiles p on p.id = e.by_user group by by_user) q), '[]'::jsonb),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'no_sale_open', n) order by day) from (
        select day, count(*) as n from e where event = 'no_sale_open' group by day) q), '[]'::jsonb),
    'recent_no_sale', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'staff', by_staff, 'location_id', location_id, 'reason', reason) order by at desc) from (
        select * from e where event = 'no_sale_open' order by at desc limit 50) q), '[]'::jsonb))
  into res;
  return res;
end $$;
revoke all on function public.drawer_report(date, date) from public, anon;
grant execute on function public.drawer_report(date, date) to authenticated;

-- ---------------------------------------------------------------- phase520.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase94.sql there and is already pasted on the live database under that name.
-- Renumbered to phase520.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 520 (bos94) - STEP Sec: fixes from the security review of phases 72-519 (docs/briefs_p2p3/step_Sec_REPORT.md).
--   Paste AFTER phase515 and after 90, 91, 92, 93, 95 (docs/PASTE_ORDER.md). Additive and paste-twice safe: create-or-replace functions, one new table,
--   new rules, new recommendation rows. Nothing is deleted. EVERY NEW SWITCH / LIMIT IS OFF / EMPTY BY DEFAULT = today's behaviour; the owner decides (see the report).
--   Functions re-created from their LATEST definition (changed lines carry the tag bos94, every older bosNN tag kept):
--     _scan_photo_ok, scan_get (H1) | _sale_stock_out (M5) | _intake_fail, _inb_insert_message (M3) | invoice_data92, invoice_share_log92 (L2)
--     inbound_message_receive, web_order_submit get ONE extra argument at the end (p_proof_hash, default null) - the old call shapes still work (M2).
--   H1  The photo of a purchase bill and its path follow the cost right (same rule as the extracted text).
--   M1  pii_exposure_report94(): owner view of who can read customer phone / address directly; recommendation row inbox_pii_guard_on already says ON (default NOT changed).
--   M2  Optional proof secrets (hash only, like the Telegram secret token): scope 'meta' and 'web_form'. Not set = exactly today's behaviour.
--   M3  intake_purge(days), optional limits intake_reject_max_per_min and inbox_rate_max_per_min (empty = no limit). The edge sources check their token BEFORE any sign-in.
--   M4  scan_ai_gate94(job): the edge function asks it before every paid AI call; rules scan_ai_max_per_job / scan_ai_max_per_user_day (empty = unlimited = today).
--   M5  rule offline_sale_max_age (hours, empty = today): an older sale no longer skips the stock guard.
--       (the same 3 lines are also merged into phase515's _sale_stock_out, identical text, so a repeated paste of phase515 cannot undo it - docs/PASTE_ORDER.md rule D.1)
--   M6  execute revoked from anon / public on the re-created functions; authenticated keeps what it had. anon_exec_audit94() lists what anon can still run.
--   L2  invoice_share_log92 collapses the same person + sale + channel within a minute; optional rule invoice_own_sales_only (default off).
--   Also: acct_autopost_runs_list (scheduler run history for owner / accounts viewers), recommendation rows for partner_base_estimate, packaging_return_mode and the new rules.
-- ============================================================

-- ---------- 0. guard ----------
do $g$
declare miss text := '';
begin
  if to_regclass('public.intake_failures') is null then miss := miss || ' 76'; end if;
  if to_regprocedure('public._tg_hash_eq(text,text)') is null then miss := miss || ' 86'; end if;
  if not exists (select 1 from public.rules where key = 'partner_base_estimate') then miss := miss || ' 80'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.acct_autopost_runs85') is null then miss := miss || ' 85'; end if;
  if to_regprocedure('public._sale_stock_out()') is null or position('bos89' in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) = 0 then miss := miss || ' 89'; end if;
  if to_regclass('public.scan_jobs') is null then miss := miss || ' 90'; end if;
  if to_regclass('public.invoice_shares') is null then miss := miss || ' 92'; end if;
  if to_regclass('public.doc_template_choice') is null then miss := miss || ' 93'; end if;
  if miss <> '' then raise exception 'phase520 needs phases 76, 506, 507, 511, 512, 515, 516, 518, 519 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. rules (all empty / off = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('scan_ai_max_per_job', 'purchase', 'number', null, 'বার', null, 1, 1000,
  'Scan: একটি ছবিতে AI কতবার পড়বে (সর্বোচ্চ)', 'Scan: একটি ছবিতে AI কতবার পড়বে (max)', 'Scan: most AI readings per photo',
  'ফাঁকা = সীমা নেই (আগের মতো)। প্রতিবার AI পড়লে খরচ হয়; সীমা বসালে তার বেশি পড়া আটকে যায়।',
  'ফাঁকা = limit নেই (আগের মতো)। প্রতিবার AI পড়লে খরচ হয়; limit বসালে তার বেশি পড়া আটকে যায়।',
  'Empty = no limit (as before). Every AI reading costs money; with a limit, readings above it are refused. The security review suggested 5.', 940),
 ('scan_ai_max_per_user_day', 'purchase', 'number', null, 'বার', null, 1, 100000,
  'Scan: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (সর্বোচ্চ)', 'Scan: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (max)', 'Scan: most AI readings per person in 24 hours',
  'ফাঁকা = সীমা নেই (আগের মতো)।', 'ফাঁকা = limit নেই (আগের মতো)।', 'Empty = no limit (as before). The number is the owner''s choice; there is no built-in value.', 941),
 ('offline_sale_max_age', 'pos', 'number', null, 'ঘণ্টা', null, 1, 8760,
  'পুরোনো সময়ের বিক্রিতে স্টক-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা', 'পুরোনো সময়ের sale-এ stock-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা', 'Hours an old-dated sale may skip the stock guard',
  'ফাঁকা = আগের মতো (২ মিনিটের বেশি পুরোনো সময়ের বিক্রি স্টক আটকায় না)। সংখ্যা দিলে তার চেয়ে পুরোনো সময়ের বিক্রিতে স্টক-পাহারা পুরো চালু থাকে; ম্যানেজারের replay override আগের মতো চলে।',
  'ফাঁকা = আগের মতো (২ মিনিটের বেশি পুরোনো সময়ের sale stock আটকায় না)। সংখ্যা দিলে তার চেয়ে পুরোনো সময়ের sale-এ stock-পাহারা পুরো চালু থাকে; ম্যানেজারের replay override আগের মতো চলে।',
  'Empty = as before (a sale dated more than 2 minutes back never stops on stock). With a number, a sale dated older than that gets the full stock guard; a manager replay override works as before. Set it to the longest time a phone is normally offline.', 942),
 ('inbox_rate_max_per_min', 'pos', 'number', null, 'বার', null, 1, 100000,
  'ইনবক্স: এক চ্যানেলে মিনিটে সর্বোচ্চ কত বার্তা রাখা হবে', 'Inbox: এক channel-এ মিনিটে max কত message রাখা হবে', 'Inbox: most messages stored per channel per minute',
  'ফাঁকা = সীমা নেই (আগের মতো)। বেশি এলে বার্তা পরে আবার চেষ্টার তালিকায় যায়।', 'ফাঁকা = limit নেই (আগের মতো)। বেশি এলে message পরে retry তালিকায় যায়।',
  'Empty = no limit (as before). Above the limit a message goes to the retry list. The security review suggested 120.', 943),
 ('intake_reject_max_per_min', 'pos', 'number', null, 'বার', null, 1, 100000,
  'ভুল সই/টোকেনের লাইন মিনিটে সর্বোচ্চ কত রাখা হবে', 'ভুল signature/token-এর line মিনিটে max কত রাখা হবে', 'Most rejected-call lines kept per minute',
  'ফাঁকা = সীমা নেই (আগের মতো)। ভুয়া ডাকের বন্যায় তালিকা ভরে যাওয়া ঠেকায়।', 'ফাঁকা = limit নেই (আগের মতো)। ভুয়া ডাকের বন্যায় তালিকা ভরে যাওয়া ঠেকায়।',
  'Empty = no limit (as before). Stops a flood of forged calls from filling the failed list.', 944),
 ('invoice_own_sales_only', 'pos', 'switch', 'false', null, null, null, null,
  'ইনভয়েস: নিজের বিক্রি ছাড়া অন্যেরটা শুধু মালিক / POS approve দেখবে', 'Invoice: নিজের sale ছাড়া অন্যেরটা শুধু owner / POS approve দেখবে', 'Invoice: other people''s sales only for owner / POS approve',
  'বন্ধ = আগের মতো (জায়গার যে কেউ POS দিয়ে যেকোনো বিক্রির ইনভয়েস দেখতে পারে)। চালু = ক্যাশিয়ার শুধু নিজের বিক্রির ইনভয়েস দেখে ও লগ করে।',
  'বন্ধ = আগের মতো (জায়গার যে কেউ POS দিয়ে যেকোনো sale-এর invoice দেখতে পারে)। চালু = cashier শুধু নিজের sale-এর invoice দেখে ও log করে।',
  'Off = as before (anyone with POS at the place can open any sale''s invoice). On: a cashier opens and logs only his own sales'' invoices.', 945)
on conflict (key) do nothing;

-- ---------- 2. H1: the photo of a purchase bill follows the cost right ----------
CREATE OR REPLACE FUNCTION public._scan_photo_ok(p_name text, p_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare loc int;
begin
  if p_name is null or p_name !~ '^SCAN/[0-9]+/[A-Za-z0-9_.-]+$' or not public.is_active() then return false; end if;
  loc := split_part(p_name, '/', 2)::int;
  if p_action = 'enter' then return public.can_loc(loc) and public.has_grant('scan_upload', loc); end if;
  return exists (select 1 from public.scan_jobs j where j.image_path = p_name and public._scan_content_ok(j));   -- bos94: the photo of a purchase bill shows costs: same right as the extracted text
end $function$;


CREATE OR REPLACE FUNCTION public.scan_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j public.scan_jobs; ok boolean; ev jsonb;
begin
  select * into j from public.scan_jobs where id = p_id;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  ok := public._scan_content_ok(j);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', e.at, 'action', e.action, 'from', e.from_status, 'to', e.to_status, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev from public.scan_events e where e.job_id = j.id;
  return jsonb_build_object('id', j.id, 'kind', j.kind, 'location_id', j.location_id, 'status', j.status, 'engine', j.engine, 'image_path', case when ok then j.image_path end, 'note', j.note,   -- bos94: the photo path only with the content right
    'extract_error', j.extract_error, 'created_at', j.created_at, 'created_staff', j.created_staff, 'mine', j.created_by = auth.uid(),
    'cost_hidden', not ok, 'extracted', case when ok then j.extracted end, 'confidence', case when ok then j.confidence end, 'edited', case when ok then j.edited end,
    'dups', case when ok then j.dups end, 'warnings', case when ok and j.status in ('extracted', 'reviewed') then public._scan_warn(j, coalesce(j.edited, j.extracted, '{}'::jsonb)) end,
    'result_type', j.result_type, 'result_id', j.result_id, 'reject_reason', j.reject_reason, 'events', ev,
    'can_confirm', public.can_loc(j.location_id) and public.has_grant('scan_confirm', j.location_id) and ok);
end $function$;


-- ---------- 3. M2: optional proof secrets (hash only; the secret itself is never stored) ----------
create table if not exists public.intake_proofs94 (
  scope text primary key check (scope in ('meta', 'web_form')),
  secret_hash text not null check (secret_hash ~ '^[0-9a-f]{64}$'),
  set_by uuid, set_at timestamptz not null default now()
);
alter table public.intake_proofs94 enable row level security;
revoke all on public.intake_proofs94 from public, anon, authenticated;

-- no proof set for the scope = true (today's behaviour). Set = the caller must send the matching hash (constant-time compare). The owner is never blocked.
create or replace function public._intake_proof_ok94(p_scope text, p_hash text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare sh text;
begin
  if public.is_owner() then return true; end if;
  select secret_hash into sh from public.intake_proofs94 where scope = p_scope;
  if sh is null then return true; end if;
  return public._tg_hash_eq(sh, lower(coalesce(p_hash, '')));
end $$;

create or replace function public.intake_proof_set94(p_scope text, p_secret text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope is null or p_scope not in ('meta', 'web_form') then raise exception 'bad_scope'; end if;
  if p_secret is null then      -- empty secret = remove the proof = back to today's behaviour
    delete from public.intake_proofs94 where scope = p_scope;
  else
    if p_secret !~ '^[A-Za-z0-9_-]{16,255}$' then raise exception 'bad_secret: 16-255 characters, letters, digits, _ and - only'; end if;
    insert into public.intake_proofs94 (scope, secret_hash, set_by) values (p_scope, public._tg_hash(p_secret), auth.uid())
      on conflict (scope) do update set secret_hash = excluded.secret_hash, set_by = excluded.set_by, set_at = now();
  end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'intake_proofs94', p_scope, jsonb_build_object('scope', p_scope, 'event', case when p_secret is null then 'proof_cleared' else 'proof_set' end));
  return jsonb_build_object('scope', p_scope, 'set', p_secret is not null);
end $$;

create or replace function public.intake_proof_status94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('meta', exists (select 1 from public.intake_proofs94 where scope = 'meta'), 'web_form', exists (select 1 from public.intake_proofs94 where scope = 'web_form'));
end $$;

drop function if exists public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean);
CREATE OR REPLACE FUNCTION public.inbound_message_receive(p_kind text, p_account_ref text, p_external_id text, p_handle text, p_name text, p_text text, p_msg_time timestamp with time zone, p_attachment text, p_signature_ok boolean, p_proof_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pl jsonb; res jsonb; fid bigint; ch int;
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('off', true); end if;
  if p_kind in ('facebook', 'instagram', 'whatsapp') and not public.rule_on('meta_intake_on') then return jsonb_build_object('off', true); end if;
  if p_kind not in ('facebook', 'instagram', 'whatsapp', 'web_form', 'other') or p_signature_ok is null or p_external_id is null or char_length(p_external_id) not between 1 and 200
     or char_length(coalesce(p_account_ref, '')) > 120 or char_length(coalesce(p_text, '')) > 20000 then raise exception 'bad_input'; end if;
  if not p_signature_ok then
    -- a wrong signature is never stored as a message; only the fact (no body) goes to the failed list for the owner to see
    fid := public._intake_fail('bad_signature', null, p_external_id, 'bad_signature', jsonb_build_object('kind', p_kind), 'rejected');
    return jsonb_build_object('rejected', 'bad_signature', 'failure_id', fid);
  end if;
  if not public._intake_proof_ok94('meta', p_proof_hash) then      -- bos94: the signature result is believed only with the stored proof (when the owner has set one)
    fid := public._intake_fail('bad_signature', null, p_external_id, 'bad_proof', jsonb_build_object('kind', p_kind), 'rejected');   -- bos94
    return jsonb_build_object('rejected', 'bad_proof', 'failure_id', fid);   -- bos94
  end if;   -- bos94
  pl := jsonb_build_object('kind', p_kind, 'account_ref', p_account_ref, 'external_id', p_external_id, 'handle', p_handle, 'name', p_name, 'text', p_text,
                           'msg_time', p_msg_time, 'attachment', p_attachment);
  select id into ch from public.sales_channels where kind = p_kind and account_ref = p_account_ref;
  begin
    res := public._inb_insert_message(pl);
  exception when others then
    fid := public._intake_fail('message', ch, p_external_id, sqlerrm, pl);
    return jsonb_build_object('failed', true, 'queued', true, 'failure_id', fid);
  end;
  return res;
end $function$;


drop function if exists public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean);
CREATE OR REPLACE FUNCTION public.web_order_submit(p_channel text, p_submission uuid, p_name text, p_mobile text, p_address text, p_delivery_mode text, p_lines jsonb, p_note text, p_source text DEFAULT NULL::text, p_pay_mode text DEFAULT NULL::text, p_pay_ref text DEFAULT NULL::text, p_key_hash text DEFAULT NULL::text, p_captcha_ok boolean DEFAULT NULL::boolean, p_proof_hash text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch public.sales_channels; pl jsonb; res jsonb; fid bigint; mx int; win int; c int; k text := coalesce(p_key_hash, '');
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if p_submission is null then raise exception 'bad_input'; end if;
  if not public._intake_proof_ok94('web_form', p_proof_hash) then return jsonb_build_object('ok', false, 'error', 'bad_proof'); end if;   -- bos94: captcha result and rate key are believed only with the stored proof (when set)
  select * into ch from public.sales_channels where code = p_channel and kind = 'web_form' and active;
  if not found then return jsonb_build_object('ok', false, 'error', 'channel_not_found'); end if;
  if public.rule_on('web_form_captcha_on') and p_captcha_ok is not true then return jsonb_build_object('ok', false, 'error', 'captcha_required'); end if;
  -- same submission twice must never count as spam: an existing order is just returned
  if exists (select 1 from public.online_orders where channel_id = ch.id and external_ref = p_submission::text) then
    return jsonb_build_object('ok', true) || public._web_order_run(jsonb_build_object('channel', p_channel, 'submission', p_submission));
  end if;
  mx := coalesce(public.rule_num('web_form_rate_max'), 0)::int; win := greatest(1, coalesce(public.rule_num('web_form_rate_window_min'), 60)::int);
  if mx > 0 then
    select count(*) into c from public.intake_hits where channel_id = ch.id and key_hash = k and at > now() - make_interval(mins => win);
    if c >= mx then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  end if;
  insert into public.intake_hits (channel_id, key_hash) values (ch.id, k);
  -- whitelist: only the necessary fields are kept
  pl := jsonb_build_object('channel', p_channel, 'submission', p_submission, 'name', left(btrim(p_name), 80), 'mobile', left(p_mobile, 30), 'address', left(p_address, 300),
          'delivery_mode', p_delivery_mode, 'lines', p_lines, 'note', left(p_note, 300), 'source', left(p_source, 80), 'pay_mode', p_pay_mode, 'pay_ref', left(p_pay_ref, 80));
  begin
    res := public._web_order_run(pl);
  exception when others then
    if sqlerrm ~ '^(bad_|item_|customer_name|address_required|no_lines|no_price|too_long|advance_|channel_not_found|pay_mode_other)' then
      return jsonb_build_object('ok', false, 'error', split_part(sqlerrm, ':', 1));
    end if;
    fid := public._intake_fail('web_order', ch.id, p_submission::text, sqlerrm, pl);
    return jsonb_build_object('ok', false, 'queued', true, 'failure_id', fid);
  end;
  return jsonb_build_object('ok', true) || res;
end $function$;


-- ---------- 4. M3: limits on the failed list + purge ----------
CREATE OR REPLACE FUNCTION public._intake_fail(p_kind text, p_channel integer, p_ext text, p_err text, p_payload jsonb, p_state text DEFAULT 'failed'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_ bigint; cap94 numeric := public.rule_num('intake_reject_max_per_min');
begin
  -- bos94: a flood of forged calls must not fill the table: over the owner's per-minute limit a rejected line is counted by nobody and stored by nobody (empty rule = no limit = as before)
  if p_state = 'rejected' and cap94 is not null and cap94 > 0
     and (select count(*) from public.intake_failures where state = 'rejected' and created_at > now() - interval '1 minute') >= cap94 then return 0; end if;   -- bos94
  insert into public.intake_failures (kind, channel_id, external_id, error, payload, state, next_try_at)
    values (p_kind, p_channel, left(p_ext, 200), left(p_err, 500), p_payload, p_state,
            case when p_state = 'failed' then now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int)) end)
    returning id into id_;
  return id_;
end $function$;


CREATE OR REPLACE FUNCTION public._inb_insert_message(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch public.sales_channels; m public.inbound_messages; n int;
begin
  select * into ch from public.sales_channels where kind = p->>'kind' and account_ref = p->>'account_ref' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  -- bos94: optional per-channel limit of stored messages per minute (rule inbox_rate_max_per_min; empty = no limit = as before). The caller queues the message for a later retry.
  if public.rule_num('inbox_rate_max_per_min') is not null and public.rule_num('inbox_rate_max_per_min') > 0
     and (select count(*) from public.inbound_messages where channel_id = ch.id and received_at > now() - interval '1 minute') >= public.rule_num('inbox_rate_max_per_min') then raise exception 'rate_limited'; end if;   -- bos94
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, attachment_ref)
    values (ch.id, ch.location_id, p->>'external_id', left(p->>'handle', 120), left(p->>'name', 120), left(p->>'text', 4000),
            nullif(p->>'msg_time', '')::timestamptz, left(p->>'attachment', 500))
    on conflict (channel_id, external_id) do nothing returning * into m;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, null, 'new', 'received', auth.uid());
  return jsonb_build_object('duplicate', false, 'id', m.id);
end $function$;

create index if not exists inbound_messages_chan_time94 on public.inbound_messages (channel_id, received_at);

-- owner: delete finished / rejected / dismissed lines older than N days (the audit trail itself is never touched) and old rate-limit hits
create or replace function public.intake_purge(p_days int default 30) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; h int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'bad_input'; end if;
  delete from public.intake_failures where state in ('rejected', 'done', 'dismissed') and created_at < now() - make_interval(days => p_days);
  get diagnostics n = row_count;
  delete from public.intake_hits where at < now() - make_interval(days => p_days);
  get diagnostics h = row_count;
  return jsonb_build_object('failures_deleted', n, 'hits_deleted', h, 'days', p_days);
end $$;

-- ---------- 5. M4: the paid AI call is counted BEFORE it is made ----------
alter table public.scan_events drop constraint if exists scan_events_action_check;
alter table public.scan_events add constraint scan_events_action_check
  check (action in ('created', 'extracted', 'extract_failed', 'saved', 'reviewed', 'confirmed', 'confirm_replay', 'rejected', 'ai_call'));

create or replace function public.scan_ai_gate94(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.scan_jobs; capj numeric := public.rule_num('scan_ai_max_per_job'); capu numeric := public.rule_num('scan_ai_max_per_user_day'); nj int; nu int;
begin
  select * into j from public.scan_jobs where id = p_id for update;
  if not found or not public._scan_can_see(j) then raise exception 'not found'; end if;
  if not (j.created_by = auth.uid() or public.has_grant('scan_confirm', j.location_id)) then raise exception 'not allowed'; end if;
  if j.status not in ('uploaded', 'extracted') then raise exception 'not_open: %', j.status; end if;
  select count(*) into nj from public.scan_events where job_id = p_id and action = 'ai_call';
  select count(*) into nu from public.scan_events where by_user = auth.uid() and action = 'ai_call' and at > now() - interval '24 hours';
  if capj is not null and nj >= capj then raise exception 'too_many_attempts'; end if;
  if capu is not null and nu >= capu then raise exception 'too_many_attempts_today'; end if;
  perform public._scan_event(p_id, 'ai_call', j.status, j.status, jsonb_build_object('n', nj + 1));
  return jsonb_build_object('ok', true, 'attempt', nj + 1, 'cap_job', capj, 'cap_user_day', capu);
end $$;

-- ---------- 6. M5: old-dated sale and the stock guard ----------
CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;


-- ---------- 7. L2: invoice scoping + log dedupe ----------
CREATE OR REPLACE FUNCTION public.invoice_data92(p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.sales; loc public.locations; cu public.customers; lines_j jsonb; pays_j jsonb; shares_j jsonb := '[]';
  mob_ok boolean; sub numeric; share numeric := 1; tx numeric; rate numeric; inc boolean; vat_j jsonb := null; can_log boolean;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if public.rule_on('invoice_own_sales_only') and s.created_by is distinct from auth.uid() and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not_found'; end if;   -- bos94: optional, own sales only
  select * into loc from public.locations where id = s.location_id;
  -- lines: whitelist of keys, in sale order; names in all three languages from the item master
  select coalesce(jsonb_agg(jsonb_build_object(
      'item_id', e.v ->> 'item_id', 'code', coalesce(i.code, e.v ->> 'code'), 'name', e.v ->> 'name', 'name_en', i.name_en, 'name_mix', i.name_mix,
      'unit', e.v ->> 'unit', 'qty', coalesce((e.v ->> 'qty')::numeric, 1), 'price', coalesce((e.v ->> 'price')::numeric, (e.v ->> 'amount')::numeric),
      'amount', coalesce((e.v ->> 'amount')::numeric, 0), 'custom', coalesce((e.v ->> 'custom')::boolean, false)) order by e.n), '[]')
    into lines_j
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality e(v, n)
    left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
  select coalesce(jsonb_agg(jsonb_build_object('mode', p.mode, 'wallet', p.wallet, 'amount', p.amount) order by p.id), '[]') into pays_j
    from public.sale_payments p where p.sale_id = s.id and not p.voided and p.kind = 'sale';
  if s.customer_id is not null then select * into cu from public.customers where id = s.customer_id; end if;
  mob_ok := public.is_owner() or public.rpt_mobile_ok() or s.created_by = auth.uid();
  -- VAT: the same base as vat_report (VAT-applicable lines, after the bill discount share); shown only when the VAT switch is on and a rate is entered
  rate := public.rule_num('vat_rate'); inc := public.rule_on('vat_prices_include');
  if public.rule_on('vat_on') and rate is not null then
    sub := coalesce(s.subtotal, 0); if sub > 0 then share := (sub - coalesce(s.discount, 0)) / sub; end if;
    select coalesce(sum(coalesce((e.v ->> 'amount')::numeric, 0)) filter (where i.vat_applicable is true), 0) * share into tx
      from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e(v)
      left join public.items i on i.id = nullif(e.v ->> 'item_id', '')::uuid;
    vat_j := jsonb_build_object('rate', rate, 'included', coalesce(inc, false), 'taxable', round(tx, 2),
                                'amount', round(case when coalesce(inc, false) then tx * rate / (100 + rate) else tx * rate / 100 end, 2));
  end if;
  if public.is_owner() or public.can_do('POS', 'approve') then
    select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'by', x.by_staff, 'at', x.at) order by x.at desc), '[]') into shares_j
      from (select channel, by_staff, at from public.invoice_shares where sale_id = s.id order by at desc limit 20) x;
  end if;
  return jsonb_build_object(
    'id', s.id, 'client_id', s.client_id, 'receipt', s.receipt, 'location_id', s.location_id, 'location_code', loc.code,
    'location', jsonb_build_object('bn', loc.name_bn, 'mix', loc.name_mix, 'en', loc.name_en),
    'sale_date', s.sale_date, 'sold_at', s.sold_at, 'status', s.status, 'sale_type', s.sale_type, 'cashier', s.created_staff,
    'lines', lines_j, 'subtotal', s.subtotal, 'discount', s.discount, 'total', s.total, 'paid', s.paid, 'due', s.due_amount,
    'payments', pays_j, 'vat', vat_j,
    'customer', case when s.customer_id is null then case when s.customer is null then null else jsonb_build_object('name', s.customer, 'mobile', null, 'masked', false) end
                     else jsonb_build_object('name', cu.name, 'mobile', case when mob_ok then cu.mobile end, 'whatsapp', case when mob_ok then cu.whatsapp end, 'masked', not mob_ok) end,
    'shares', shares_j);
end $function$;


CREATE OR REPLACE FUNCTION public.invoice_share_log92(p_sale uuid DEFAULT NULL::uuid, p_channel text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; nid bigint;
begin
  if not public.is_active() or not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p_channel is null or p_channel not in ('print', 'email', 'sms', 'whatsapp', 'share', 'copy', 'download') then raise exception 'bad_channel'; end if;
  if p_sale is not null then select * into s from public.sales where id = p_sale;
  elsif p_client is not null then select * into s from public.sales where client_id = p_client and created_by = auth.uid();
  else raise exception 'no_sale'; end if;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if public.rule_on('invoice_own_sales_only') and s.created_by is distinct from auth.uid() and not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not_found'; end if;   -- bos94
  select x.id into nid from public.invoice_shares x where x.sale_id = s.id and x.channel = p_channel and x.by_user = auth.uid() and x.at > now() - interval '1 minute' order by x.id desc limit 1;   -- bos94: the same person + sale + channel within a minute is one log line
  if nid is not null then return nid; end if;   -- bos94
  insert into public.invoice_shares (sale_id, channel, by_user, by_staff, location_id)
    values (s.id, p_channel, auth.uid(), (select coalesce(nullif(full_name, ''), staff_id) from public.profiles where id = auth.uid()), s.location_id) returning id into nid;
  return nid;
end $function$;


-- ---------- 8. M1: who can read customer phone / address directly (owner view) ----------
create or replace function public.pii_exposure_report94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'guard_on', public.rule_on('inbox_pii_guard_on'),
    'direct_mobile_read', has_column_privilege('authenticated', 'public.online_orders', 'customer_mobile', 'select'),
    'direct_address_read', has_column_privilege('authenticated', 'public.online_orders', 'address', 'select'),
    'users_with_pos_view', (select count(distinct ur.user_id) from public.user_roles ur join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = 'POS' and p.can_view
                              join public.roles r on r.code = ur.role_code and r.active),
    'audited_views_30d', (select count(*) from public.audit_log a where a.action = 'view' and a.table_name in ('inbound_messages', 'online_orders') and a.at > now() - interval '30 days'),
    'note', 'While inbox_pii_guard_on is off, every POS-view user can read phone and address with a plain table read; the database cannot log such a read (only inbox_get / inbox_list / online_order_get leave a view line). Recommended: switch inbox_pii_guard_on on.');
end $$;

-- ---------- 9. M6: nobody anonymous runs the re-created functions ----------
do $m6$
declare r record; had boolean;
begin
  for r in select p.oid, p.oid::regprocedure as sig from pg_proc p
           where p.pronamespace = 'public'::regnamespace
             and p.proname = any (array['acct_income_statement', 'acct_overview', 'acct_post_pending', 'partner_calculate', 'partner_settlement_save', 'sale_return', 'stock_count_adjust',
                                        'stock_receive_transfer', 'record_sale2', 'urgent_alerts', 'biz_items', 'items_with_cost', 'online_order_save', 'rpt_agg_sql', 'stock_post', 'recipe_save', 'recipe_copy'])
  loop
    had := has_function_privilege('authenticated', r.oid, 'execute');       -- keep exactly what signed-in users had (they may have got it through PUBLIC)
    execute format('revoke execute on function %s from public, anon', r.sig);
    if had then execute format('grant execute on function %s to authenticated', r.sig); end if;
  end loop;
end $m6$;

-- owner: every SECURITY DEFINER function in public that the anon role can still execute (run it on the live database and compare with what you expect: login_precheck, login_failed, attendance_punch_push)
create or replace function public.anon_exec_audit94() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(p.oid::regprocedure::text order by p.proname) from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.prosecdef and has_function_privilege('anon', p.oid, 'execute')), '[]'::jsonb);
end $$;

-- ---------- 10. scheduler run history without a direct table grant ----------
create or replace function public.acct_autopost_runs_list(p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.ran_at desc, z.id desc) from (
    select r.id, r.ran_at, r.posted, r.reversed, r.errors, r.locked, r.waiting, r.more, r.note
      from public.acct_autopost_runs85 r order by r.ran_at desc, r.id desc limit least(greatest(coalesce(p_limit, 20), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 11. recommendations for the setup guide (the owner decides; nothing is applied here) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('partner_base_estimate', 'partner_base_estimate', '80', 'partners', '"refuse"', '{}',
  'অংশীদারের হিসাব সেভ করার সময় বিক্রিত মালের খরচ যদি আনুমানিক (item খরচের তালিকা থেকে) হয়, refuse দিলে সেভ আটকে যায়; ভুল লাভের ভিত্তিতে অংশ ভাগ হয় না। হাতে লেখা base দিলে সেটাই চলে। তার আগে warn থাকুক।',
  'Partner-এর হিসাব save করার সময় বিক্রিত মালের cost যদি আনুমানিক (item cost তালিকা থেকে) হয়, refuse দিলে save আটকে যায়; ভুল profit-এর ভিত্তিতে অংশ ভাগ হয় না। হাতে লেখা base দিলে সেটাই চলে। তার আগে warn থাকুক।',
  'A partner settlement is not saved when part of the cost of goods is only an estimate from the item cost list, so profit is never split on a guessed base; a typed base still works. Keep warn until the ledger costs are in. The owner decides.', 200),
 ('packaging_return_mode', 'packaging_return_mode', '80', 'stock', '"wastage"', '{}',
  'ফেরত আসা বিক্রির মোড়ক সাধারণত আর বিক্রিতে লাগে না। wastage দিলে সেটা কারণসহ নষ্ট হিসাবে লেখা হয়, তাই স্টক ও হিসাব মেলে। মোড়ক সত্যিই আবার ব্যবহার করা গেলে restore। none = আগের মতো।',
  'ফেরত আসা sale-এর packaging সাধারণত আর বিক্রিতে লাগে না। wastage দিলে সেটা reason-সহ নষ্ট হিসাবে লেখা হয়, তাই stock ও হিসাব মেলে। Packaging সত্যিই আবার ব্যবহার করা গেলে restore। none = আগের মতো।',
  'Packaging of a returned sale usually cannot be sold again. wastage records it as waste with a reason, so stock and books agree. Use restore only if the packaging can really be reused. none = as before. The owner decides.', 201),
 ('scan_ai_max_per_job', 'scan_ai_max_per_job', '94', 'purchase', null, '{}',
  'AI দিয়ে ছবি পড়ালে প্রতিবার খরচ হয়। একটি ছবিতে কতবার পড়া যাবে তার সীমা বসানো ভালো; সংখ্যা মালিক ঠিক করবেন (পর্যালোচনার পরামর্শ: ৫)।',
  'AI দিয়ে ছবি পড়ালে প্রতিবার cost হয়। একটি ছবিতে কতবার পড়া যাবে তার limit বসানো ভালো; সংখ্যা owner ঠিক করবেন (review-এর পরামর্শ: ৫)।',
  'Every AI reading of a photo costs money, so a limit per photo is advisable. The number is the owner''s choice (the review suggested 5). Empty = unlimited = as before.', 202),
 ('scan_ai_max_per_user_day', 'scan_ai_max_per_user_day', '94', 'purchase', null, '{}',
  'একজন মানুষ ২৪ ঘণ্টায় কতবার AI পড়াতে পারবে তার সীমা; সংখ্যা মালিক ঠিক করবেন। ফাঁকা = সীমা নেই।',
  'একজন মানুষ ২৪ ঘণ্টায় কতবার AI পড়াতে পারবে তার limit; সংখ্যা owner ঠিক করবেন। ফাঁকা = limit নেই।',
  'A daily limit of AI readings per person; the number is the owner''s choice. Empty = unlimited = as before.', 203),
 ('offline_sale_max_age', 'offline_sale_max_age', '94', 'pos', null, '{}',
  'পুরোনো সময় দিয়ে পাঠানো বিক্রি স্টক-পাহারা এড়াতে পারে। ফোন সাধারণত সর্বোচ্চ কত ঘণ্টা অফলাইন থাকে সেটা দিয়ে সীমা বসান; সংখ্যা মালিক ঠিক করবেন।',
  'পুরোনো সময় দিয়ে পাঠানো sale stock-পাহারা এড়াতে পারে। Phone সাধারণত সর্বোচ্চ কত ঘণ্টা offline থাকে সেটা দিয়ে limit বসান; সংখ্যা owner ঠিক করবেন।',
  'A sale sent with an old date can skip the stock guard. Set the limit to the longest time a phone is normally offline; the number is the owner''s choice. Empty = as before.', 204),
 ('inbox_rate_max_per_min', 'inbox_rate_max_per_min', '94', 'pos', null, '{}',
  'এক চ্যানেলে মিনিটে কত বার্তা রাখা হবে তার সীমা; ভুয়া বার্তার বন্যা ঠেকায়। সংখ্যা মালিক ঠিক করবেন (পর্যালোচনার পরামর্শ: ১২০)।',
  'এক channel-এ মিনিটে কত message রাখা হবে তার limit; ভুয়া message-এর বন্যা ঠেকায়। সংখ্যা owner ঠিক করবেন (review-এর পরামর্শ: ১২০)।',
  'A per-channel limit of stored messages per minute; stops a flood of fake messages. The number is the owner''s choice (the review suggested 120). Empty = no limit = as before.', 205),
 ('intake_reject_max_per_min', 'intake_reject_max_per_min', '94', 'pos', null, '{}',
  'ভুল সই/টোকেনের ডাকের লাইন মিনিটে কত রাখা হবে তার সীমা; তালিকা ভরে যাওয়া ঠেকায়। সংখ্যা মালিক ঠিক করবেন। পুরোনো লাইন মুছতে intake_purge।',
  'ভুল signature/token-এর ডাকের line মিনিটে কত রাখা হবে তার limit; তালিকা ভরে যাওয়া ঠেকায়। সংখ্যা owner ঠিক করবেন। পুরোনো line মুছতে intake_purge।',
  'A limit of rejected-call lines kept per minute so the list cannot be filled by forged calls. The number is the owner''s choice. Old lines can be removed with intake_purge. Empty = no limit = as before.', 206),
 ('invoice_own_sales_only', 'invoice_own_sales_only', '94', 'pos', 'true', '{}',
  'চালু করলে ক্যাশিয়ার শুধু নিজের বিক্রির ইনভয়েস দেখে ও শেয়ার লগ করে; অন্যের বিক্রির ইনভয়েস মালিক ও POS approve-এর জন্য।',
  'চালু করলে cashier শুধু নিজের sale-এর invoice দেখে ও share log করে; অন্যের sale-এর invoice owner ও POS approve-এর জন্য।',
  'With this on a cashier opens and logs only his own sales'' invoices; other sales'' invoices stay with the owner and POS approve. The owner decides.', 207)
on conflict (code) do nothing;

-- ---------- 12. privileges ----------
revoke all on function public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean, text) from public, anon;
grant execute on function public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean, text) to authenticated;
revoke all on function public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean, text) from public, anon;
grant execute on function public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean, text) to authenticated;
revoke all on function public._intake_proof_ok94(text, text) from public, anon, authenticated;
revoke all on function public.intake_proof_set94(text, text), public.intake_proof_status94(), public.intake_purge(int), public.scan_ai_gate94(uuid), public.pii_exposure_report94(),
  public.anon_exec_audit94(), public.acct_autopost_runs_list(int) from public, anon;
grant execute on function public.intake_proof_set94(text, text), public.intake_proof_status94(), public.intake_purge(int), public.scan_ai_gate94(uuid), public.pii_exposure_report94(),
  public.anon_exec_audit94(), public.acct_autopost_runs_list(int) to authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase522.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase96.sql there and is already pasted on the live database under that name.
-- Renumbered to phase522.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- Phase 522 (step D23): the two items step D left unbuilt.
-- Additive, paste-twice safe. Paste AFTER phase515 (which comes after phase517/518/519): this file re-creates functions from their latest definition (the phase515 bodies),
-- the file is produced by tests/sql/gen_phase522.py from a database built through phase515 - see the BODY GUARD below.
--
--   D2 OPENING STOCK HELPER   Before / when the switch acct_stock_opening is turned on: detect whether the opening stock is already inside the opening journal (acct_opening)
--                             = double count risk, and show per place: opening stock value, what the opening journal already carries on the inventory accounts, the GL inventory,
--                             the stock valuation and their difference.  Four ways to get the opening stock into the books (all built, the owner chooses; nothing is automatic):
--                               owner_capital     Dr inventory / Cr stock_opening_equity (owner capital 3100 unless re-pointed)
--                               existing_account  Dr inventory / Cr an existing opening balance account the owner names (equity or liability account)
--                               skip              already in the GL: only the decision is kept, nothing is posted, the switch will not post these openings
--                               difference        post only what the opening journal does not carry yet
--                             opening_stock_check96 (read only), opening_stock_preview96 (dry run, no writes), opening_stock_apply96 (OWNER ONLY, audited, idempotent by client id,
--                             one entry per place via je_source_uq), opening_stock_recommend96 (picks the best option from the numbers, never applies it).
--                             The phase511 posting of openings (switch acct_stock_opening) leaves out the opening rows a decision here already covers, so the same stock is never counted twice.
--   D3 COST WAITING           Stock moves that have no cost wait as cost_missing (wastage, production ingredients, count gains/losses, opening, own-use issue, transfers, purchase returns).
--                             cost_wait_list96 = the waiting list (documents awaiting cost, oldest first), cost_wait_preview96 (dry run), cost_wait_recommend96,
--                             cost_wait_supply96 (owner or cost-right holder supplies the cost: item_average | last_purchase | recipe_standard | manual with a reason; the ledger is NOT edited,
--                             the cost is kept in the append-only table ledger_cost_supply96 and the posting then reads it; the document posts ONCE, je_source_uq),
--                             cost_wait_alert96 + rule acct_cost_wait_alert_days (owner types the number; blank = no alert, no built-in number).
--                             Not done here: a finished good's stock AVERAGE cost cache is not changed (that needs a new ledger row); a document already posted with a partial cost is not re-posted.
-- Tag: bos96 marks every changed line inside a re-created function.

-- ---------- guard ----------
do $g$ begin
  if to_regprocedure('public._acct_stock_moves85(date)') is null or to_regprocedure('public._pvar85(uuid)') is null
     or to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null or to_regprocedure('public._cost_free80(uuid)') is null then
    raise exception 'phase522 needs phase511 (and phase506) pasted first';
  end if;
  if position('bos85' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase522 needs phase511 pasted first (_acct_docs carries no bos85 line)';
  end if;
  if position('bos89' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0 then
    raise exception 'phase522 needs phase515 pasted first (the re-created functions below are built on the phase515 bodies)';
  end if;
end $g$;

-- BODY GUARD: the live function must not carry a tag this file does not know (it would be overwritten by an older body)
do $g$ declare d text; t text[]; ok boolean := true; begin
  d := pg_get_functiondef('public._acct_inv_split72(text[],text,text[],integer)'::regprocedure);
  if position('bos96' in d) = 0 then
    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;
    if t is not null and not (t <@ array['']::text[]) then raise exception 'phase522: _acct_inv_split72 carries tags newer than the ones this file was built from (%); re-run tests/sql/gen_phase522.py on a database built through the latest phase', t; end if;
  end if;
  d := pg_get_functiondef('public._acct_stock_moves85(date)'::regprocedure);
  if position('bos96' in d) = 0 then
    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;
    if t is not null and not (t <@ array['']::text[]) then raise exception 'phase522: _acct_stock_moves85 carries tags newer than the ones this file was built from (%); re-run tests/sql/gen_phase522.py on a database built through the latest phase', t; end if;
  end if;
  d := pg_get_functiondef('public._pvar85(uuid)'::regprocedure);
  if position('bos96' in d) = 0 then
    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;
    if t is not null and not (t <@ array['']::text[]) then raise exception 'phase522: _pvar85 carries tags newer than the ones this file was built from (%); re-run tests/sql/gen_phase522.py on a database built through the latest phase', t; end if;
  end if;
  d := pg_get_functiondef('public._acct_docs(date)'::regprocedure);
  if position('bos96' in d) = 0 then
    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;
    if t is not null and not (t <@ array['bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89']::text[]) then raise exception 'phase522: _acct_docs carries tags newer than the ones this file was built from (%); re-run tests/sql/gen_phase522.py on a database built through the latest phase', t; end if;
  end if;
  d := pg_get_functiondef('public.inventory_vs_gl(date,integer)'::regprocedure);
  if position('bos96' in d) = 0 then
    select array_agg(distinct m[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') m;
    if t is not null and not (t <@ array['bos85']::text[]) then raise exception 'phase522: inventory_vs_gl carries tags newer than the ones this file was built from (%); re-run tests/sql/gen_phase522.py on a database built through the latest phase', t; end if;
  end if;
end $g$;


-- ---------- the owner types the number (no built-in number): blank = no aging alert ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('acct_cost_wait_alert_days', 'books', 'number', null, 'days', null, 0, 3650,
  'খরচ (cost) ছাড়া পড়ে থাকা document কত দিন পর সতর্কতা (ফাঁকা = সতর্কতা বন্ধ)', 'Cost ছাড়া পড়ে থাকা document কত দিন পর alert (ফাঁকা = alert বন্ধ)', 'Alert when a document has waited for its cost longer than this many days (blank = no alert)',
  'সংখ্যাটি আপনি নিজে বসাবেন; সিস্টেমে কোনো ধরা সংখ্যা নেই। ফাঁকা থাকলে শুধু তালিকা দেখা যাবে, সতর্কতা আসবে না।', 'সংখ্যাটা আপনি নিজে দেবেন; system এ কোনো built-in সংখ্যা নেই। ফাঁকা থাকলে শুধু list দেখা যাবে, alert আসবে না।',
  'You type the number; there is no built-in value. Blank = the waiting list is shown but no alert is raised.', 961)
on conflict (key) do nothing;

-- ---------- D3: costs supplied for ledger rows that have none (the ledger itself is never edited) ----------
create table if not exists public.ledger_cost_supply96 (
  id bigint generated always as identity primary key,
  ledger_id bigint not null unique,                       -- no foreign key on purpose: a key into stock_ledger would stop the ledger's own truncate guard from answering first
  unit_cost numeric(18,6) not null check (unit_cost > 0 and unit_cost < 1000000000000),
  method text not null check (method in ('item_average', 'last_purchase', 'recipe_standard', 'manual', 'from_ingredients')),
  reason text, doc_kind text not null, doc_ref text not null, client_id uuid, basis jsonb,
  supplied_by uuid, supplied_staff text, supplied_at timestamptz not null default now(),
  constraint ledger_cost_supply96_reason check (method <> 'manual' or length(btrim(coalesce(reason, ''))) > 0));
create index if not exists ledger_cost_supply96_doc on public.ledger_cost_supply96 (doc_kind, doc_ref);
create index if not exists ledger_cost_supply96_client on public.ledger_cost_supply96 (client_id) where client_id is not null;
alter table public.ledger_cost_supply96 enable row level security;
revoke all on public.ledger_cost_supply96 from public, anon, authenticated;
drop trigger if exists ledger_cost_supply96_ro on public.ledger_cost_supply96;
create trigger ledger_cost_supply96_ro before update or delete on public.ledger_cost_supply96 for each row execute function public._ledger_immutable();
drop trigger if exists ledger_cost_supply96_nt on public.ledger_cost_supply96;
create trigger ledger_cost_supply96_nt before truncate on public.ledger_cost_supply96 for each statement execute function public._ledger_immutable();
drop trigger if exists audit_ledger_cost_supply96 on public.ledger_cost_supply96;
create trigger audit_ledger_cost_supply96 after insert on public.ledger_cost_supply96 for each row execute function public.log_change('id');

-- the ledger as the books read it: a supplied cost replaces a blank / zero cost. Closed to the browser (cost secrecy).
create or replace view public.stock_ledger_eff96 as
  select l.id, l.item_id, l.location_id, l.qty_delta,
         case when coalesce(l.unit_cost, 0) = 0 and s.unit_cost is not null then s.unit_cost else l.unit_cost end as unit_cost,
         l.reason, l.ref_type, l.ref_id, l.batch_id, l.reverses_id, l.client_id, l.made_at, l.note, l.created_by, l.created_at, (s.id is not null) as cost_supplied
  from public.stock_ledger l left join public.ledger_cost_supply96 s on s.ledger_id = l.id;
revoke all on public.stock_ledger_eff96 from public, anon, authenticated;

-- ---------- D2: what the owner decided about the opening stock (append-only, audited) ----------
create table if not exists public.opening_stock_actions96 (
  id bigint generated always as identity primary key,
  location_id int references public.locations(id),           -- null = company wide
  option text not null check (option in ('owner_capital', 'existing_account', 'skip', 'difference')),
  account_code text, amount numeric(18,2) not null default 0, entry_id bigint,
  covered_ids bigint[] not null default '{}',                -- the opening ledger rows this decision covers (costed ones for a post, all for a skip)
  reason text, client_id uuid unique, created_by uuid, created_staff text, created_at timestamptz not null default now());
create unique index if not exists opening_stock_actions96_one on public.opening_stock_actions96 (coalesce(location_id, 0)) where option <> 'skip';
alter table public.opening_stock_actions96 enable row level security;
revoke all on public.opening_stock_actions96 from public, anon, authenticated;
drop trigger if exists opening_stock_actions96_ro on public.opening_stock_actions96;
create trigger opening_stock_actions96_ro before update or delete on public.opening_stock_actions96 for each row execute function public._ledger_immutable();
drop trigger if exists opening_stock_actions96_nt on public.opening_stock_actions96;
create trigger opening_stock_actions96_nt before truncate on public.opening_stock_actions96 for each statement execute function public._ledger_immutable();
drop trigger if exists audit_opening_stock_actions96 on public.opening_stock_actions96;
create trigger audit_opening_stock_actions96 after insert on public.opening_stock_actions96 for each row execute function public.log_change('id');


-- ---------- re-created functions (latest definitions, only bos96 lines changed; generated by tests/sql/gen_phase522.py from database 'built through the last earlier phase') ----------
CREATE OR REPLACE FUNCTION public._acct_inv_split72(p_ref_types text[], p_ref_id text, p_reasons text[], p_sign integer)
 RETURNS TABLE(t text, amt numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with g as (
    select it.item_type as ty, sum(p_sign * l.qty_delta * l.unit_cost) as raw
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id /* bos96 */
    where l.ref_type = any (p_ref_types) and l.ref_id = p_ref_id and l.reason = any (p_reasons) and l.unit_cost is not null group by it.item_type),
  r as (select ty, round(raw, 2) as a, row_number() over (order by round(raw, 2) desc, ty nulls last) as rn from g),
  d as (select round((select sum(raw) from g), 2) - (select sum(a) from r) as rest)
  select r.ty, r.a + case when r.rn = 1 then (select rest from d) else 0 end from r;
$function$;

CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer' end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal')
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_stock_actions96 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$;

CREATE OR REPLACE FUNCTION public._pvar85(p_bill uuid)
 RETURNS TABLE(nulls integer, nonzero boolean, lines jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with lo as (select public._acct_buy_key(it.item_type) k, sum(round(-l.qty_delta * coalesce(l.unit_cost, 0), 2)) a, count(*) filter (where coalesce(l.unit_cost, 0) = 0) n
                from public.stock_ledger_eff96 l join public.items it /* bos96 */ on it.id = l.item_id
               where l.ref_type = 'purchase' and l.reason = 'purchase_return' and l.ref_id = p_bill::text and public._acct_buy_key(it.item_type) in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       jc as (select al.k, sum(al.amt) a from public._acct_purchase_alloc(p_bill) al where al.k in ('inv_finished', 'inv_raw', 'inv_pack') group by 1),
       dd as (select coalesce(lo.k, jc.k) k, round(coalesce(lo.a, 0) - coalesce(jc.a, 0), 2) df from lo full join jc on jc.k = lo.k),
       nz as (select * from dd where df <> 0),
       tot as (select coalesce(sum(df), 0) net from nz)
  select coalesce((select sum(n) from lo), 0)::int, exists (select 1 from nz),
         (select jsonb_agg(j) from (
            select jsonb_build_object('a', k, case when df > 0 then 'c' else 'd' end, abs(df)) j from nz
            union all select jsonb_build_object('a', 'purchase_variance', case when net > 0 then 'd' else 'c' end, abs(net)) from tot where net <> 0) x);
$function$;

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from public._acct_inv_split72(array['sale', 'sale_pack'], s.id::text, array['sale_out', 'issue_out'], -1) z where z.amt > 0 /* bos72: rounding remainder on the largest part */
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),
      jsonb_build_object('a', 'receivable', 'c', p.amount, 'pt', case when p.customer_id is not null then 'customer' end, 'pid', p.customer_id::text)) end
  from public.sale_payments p
  where p.kind = 'collection' and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('collection', p.id::text, not p.voided);

  -- purchase bills and purchase returns
  return query
  select 'purchase'::text, b.id::text, b.bill_date, b.location_id, ((case b.kind when 'return' then 'Purchase return ' else 'Purchase bill ' end) || coalesce(b.bill_no, '-'))::text, b.kind, b.status = 'posted' and b.total > 0, (b.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when b.status = 'posted' and b.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'payable', case when b.kind = 'return' then 'd' else 'c' end, b.total, 'pt', 'supplier', 'pid', b.supplier_id::text) j
        union all select 2, jsonb_build_object('a', al.k, case when b.kind = 'return' then 'c' else 'd' end, al.amt) from public._acct_purchase_alloc(b.id) al
      ) x) end
  from public.purchase_bills b
  where b.bill_date >= p_start and public._acct_need('purchase', b.id::text, b.status = 'posted' and b.total > 0);

  -- supplier payments
  return query
  select 'supplier_payment'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Supplier payment'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'payable', 'd', p.amount, 'pt', 'supplier', 'pid', p.supplier_id::text),
      jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount),
      jsonb_build_object('a', 'payable', 'c', f.amount, 'pt', 'supplier', 'pid', f.supplier_id::text)) end
  from public.supplier_refunds f
  where (f.refunded_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_refund', f.id::text, not f.voided);

  -- 10-2 expense vouchers (approved; a re-opened or re-numbered voucher is reversed, the new revision posted)
  return query
  select 'expense_voucher'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id, ('Expense voucher ' || e.serial)::text, null::text, v.total > 0, public._acct_today(),
    case when v.bad > 0 then 'unreadable_lines' end, null::text,
    case when v.total > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'exp_' || h.head, 'd', h.amt) j from (
          select regexp_replace(lower(coalesce(nullif(btrim(x->>'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') head, sum(public._acct_num(x->>'amount')) amt
          from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._acct_paykey(v.pm, true) /* bos85 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(m.mode), 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._acct_paykey(m.mode), 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
    end end
  from public.cash_moves m
  where m.move_date >= p_start and public._acct_need('cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */);

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['wastage'], w.id::text, array['wastage'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(p.mode), 'c', p.amount))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text));

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)) end
  from public.employee_advances a
  where a.adv_date >= p_start and public._acct_need('staff_advance', a.id::text, a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'));

  -- bos52: partner capital (contribution / return of capital / loan in / loan repayment / owner drawing). The partner-capital record that is a locked shadow of a cash move
  -- is not posted (the cash move is the record then). A partner-capital record that is the primary of a cash-move shadow takes the place of the cash move (same place, once).
  -- In-kind contributions move no money: they are reported as waiting (in_kind), nothing is guessed.
  return query
  select 'partner_capital'::text, public._acct_sid52('partner_capital', c.id::text), c.cap_date, nullif(lk.loc, 0), ('Partner capital: ' || c.kind)::text, c.kind,
    c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text), (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.mode = 'in_kind' then 'in_kind' end,
    case when c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text) then case c.kind
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(c.mode), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._acct_paykey(c.mode), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' else 'Stock transfer' end) || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' else 'stock_transfer' end)::text st) t
  where public._acct_need(t.st, m.lid::text, true);

  -- bos85: goods short on a received transfer: Dr transit loss / Cr clearing (location-tagged transfers) or inventory
  return query
  select 'transit_loss'::text, t.id::text, (t.received_at at time zone 'Asia/Dhaka')::date, case when public.rule_txt('acct_transit_loss_at') = 'sender' then t.from_location_id else t.to_location_id end,
    'Stock short in transit'::text, null::text, true, null::date, null::text, case when c.nulls > 0 then 'cost_missing' end,
    case when c.nulls = 0 then jsonb_build_array(
      jsonb_build_object('a', 'transit_loss', 'd', c.l),
      jsonb_build_object('a', case when coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' then 'interloc_clearing' else public._acct_inv_key(it.item_type) end, 'c', c.l)) end
  from public.stock_transfers t join public.items it on it.id = t.item_id cross join lateral (
    select coalesce(sum(round(-s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_out'), 0) - coalesce(sum(round(s.qty_delta * s.unit_cost, 2)) filter (where s.reason = 'transfer_in'), 0) l,
           count(*) filter (where s.reason in ('transfer_out', 'transfer_in') and coalesce(s.unit_cost, 0) = 0) nulls
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c
  where public.rule_on('acct_transit_loss') and t.status = 'received' and t.received_qty < t.qty
    and (t.received_at at time zone 'Asia/Dhaka')::date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and (c.nulls > 0 or c.l >= 0.01)
    and public._acct_need('transit_loss', t.id::text, true);

  -- bos85: purchase return price variance (stock left at ledger cost, supplier credit was at bill price)
  return query
  select 'purchase_variance'::text, b.id::text, b.bill_date, b.location_id, ('Purchase return price variance ' || coalesce(b.bill_no, '-'))::text, null::text, b.status = 'posted' and b.total > 0,
    (b.void_at at time zone 'Asia/Dhaka')::date, null::text, case when b.status = 'posted' and b.total > 0 and v.nulls > 0 then 'cost_missing' end,
    case when b.status = 'posted' and b.total > 0 and v.nulls = 0 then v.lines end
  from public.purchase_bills b cross join lateral public._pvar85(b.id) v
  where b.kind = 'return' and b.bill_date >= greatest(p_start, coalesce(public._acct_from85(), p_start)) and public.rule_on('acct_purchase_variance')
    and case when b.status = 'posted' and b.total > 0 then (v.nulls > 0 or v.nonzero) and public._acct_need('purchase_variance', b.id::text, true) else public._acct_need('purchase_variance', b.id::text, false) end;

  -- bos85: card settlement (typed by the person): Dr bank (net), Dr bank charges (fee), Cr card receivable (gross)
  return query
  select 'card_settlement'::text, c.id::text, c.settle_date, c.location_id, 'Card settlement'::text, null::text, c.status = 'done', (c.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when c.status = 'done' then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', public._acct_paykey(c.bank_mode), 'd', c.gross - c.fee) j
        union all select 2, jsonb_build_object('a', 'bank_charges', 'd', c.fee) where c.fee > 0
        union all select 3, jsonb_build_object('a', 'pay_card', 'c', c.gross)) x) end
  from public.card_settlements85 c
  where c.settle_date >= p_start and public._acct_need('card_settlement', c.id::text, c.status = 'done');
end $function$;

CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null then
    if not public._acct_all() or exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  elsif not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  basis := case when d >= t then 'average_cost' else 'ledger_replay' end;
  foreach k in array array['inv_finished', 'inv_raw', 'inv_pack'] loop
    select m.account_id, a.code, a.name_bn, a.name_en into acct, acode, anbn, anen from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
    if acct is null then continue; end if;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(x.v), 0) as lv_all, coalesce(sum(x.v) filter (where x.cib), 0) as lv_cib,
           coalesce(sum(x.v) filter (where x.reason = 'count_adjust'), 0) as g_count,
           coalesce(sum(x.v) filter (where x.reason = 'opening'), 0) as g_opening,
           coalesce(sum(x.v) filter (where x.reason in ('transfer_out', 'transfer_in') or x.ref_type = 'transfer'), 0) as g_transfer,
           coalesce(sum(x.v) filter (where x.reason = 'issue_out' and x.ref_type in ('issue', 'entry')), 0) as g_issue,
           coalesce(sum(x.v) filter (where (x.reason = 'production_in' and not x.has_run) or (x.reason = 'purchase_in' and x.ref_type = 'entry') or (x.reason = 'reversal' and x.ref_type = 'entry')), 0) as g_manual_in,
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'purchase' and x.bill_date < st), 0) as g_prestart
      into rw
      from (select sl.reason, sl.ref_type, coalesce(sl.qty_delta * sl.unit_cost, 0) as v, it.count_in_business as cib,
                   exists (select 1 from public.production_runs pr where pr.id::text = sl.ref_id) as has_run,
                   (select b.bill_date from public.purchase_bills b where sl.ref_type = 'purchase' and b.id::text = sl.ref_id) as bill_date
            from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
            where public._acct_inv_key(it.item_type) = k and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)) x;
    v := case when basis = 'average_cost' then
            (select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) from public.stock_balance b join public.items it on it.id = b.item_id
              where it.count_in_business and public._acct_inv_key(it.item_type) = k and b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc))
          else rw.lv_cib end;
    -- journal side
    select coalesce(sum(jl.debit - jl.credit), 0) into g_open from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type in ('opening', 'stock_opening', 'opening_stock96') /* bos85 bos96 */ and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit - jl.credit), 0) into g_man from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'manual' and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(jl.debit), 0) into g_prod from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'production' and e.reverses_id is null and e.flags like '%cogs_missing%'
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id) and (p_loc is null or jl.location_id = p_loc);
    select coalesce(sum(o.lo - o.jc), 0) into g_pret from (
        select b.id, coalesce((select sum(-sl.qty_delta * coalesce(sl.unit_cost, 0)) from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id /* bos96 */
                                where sl.ref_type = 'purchase' and sl.reason = 'purchase_return' and sl.ref_id = b.id::text and public._acct_inv_key(it.item_type) = k), 0) as lo,
               coalesce((select sum(jl.credit - jl.debit) from public.journal_entries e join public.journal_lines jl on jl.entry_id = e.id
                          where e.source_type = 'purchase' and e.source_id = b.id::text and e.reverses_id is null and jl.account_id = acct), 0) as jc
        from public.purchase_bills b where b.kind = 'return' and b.status = 'posted' and b.bill_date <= d and (p_loc is null or b.location_id = p_loc)
          and not exists (select 1 from public.journal_entries r join public.journal_entries o2 on o2.id = r.reverses_id where o2.source_type = 'purchase' and o2.source_id = b.id::text)) o;
    select coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_adjust'), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'stock_issue'), 0),
           coalesce(sum(jl.debit - jl.credit) filter (where e.source_type in ('stock_transfer', 'transit_loss')), 0), coalesce(sum(jl.debit - jl.credit) filter (where e.source_type = 'purchase_variance'), 0)
      into j_adj, j_issue, j_xfer, j_var from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and (p_loc is null or jl.location_id = p_loc);   -- bos85: what the new stock-movement entries put on this inventory account
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in, 2)),
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret + j_var, 2)),   -- bos85
      jsonb_build_object('code', 'production_cost_missing', 'amount', round(g_prod, 2)),
      jsonb_build_object('code', 'manual_journal', 'amount', round(g_man, 2)));
    ex := df - (select coalesce(sum((x->>'amount')::numeric), 0) from jsonb_array_elements(rs) x);
    rows_ := rows_ || jsonb_build_object('key', k, 'code', acode, 'name_bn', anbn, 'name_en', anen, 'gl', round(gl, 2), 'valuation', round(v, 2), 'ledger_value', round(rw.lv_all, 2),
                'diff', df, 'reasons', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(rs) x where abs((x->>'amount')::numeric) >= 0.005), 'unexplained', round(ex, 2));
    tg := tg + gl; tv := tv + v; tx := tx + ex;
  end loop;
  ok := abs(tg - tv) < 0.05;
  return jsonb_build_object('as_of', d, 'location_id', p_loc, 'start', st, 'accounting_on', public.rule_on('accounting_on'), 'valuation_basis', basis, 'rows', rows_,
    'total', jsonb_build_object('gl', round(tg, 2), 'valuation', round(tv, 2), 'diff', round(tg - tv, 2), 'unexplained', round(tx, 2)), 'agree', ok,
    'note', 'Read only: nothing is posted. Reasons are movements the books or the stock ledger do not have; "unexplained" is what is left.');
end $function$;


-- =====================================================================================================================
-- shared small helpers
-- =====================================================================================================================
create or replace function public._t96(p_bn text, p_mix text, p_en text) returns jsonb language sql immutable as $$
  select jsonb_build_object('bn', p_bn, 'mix', p_mix, 'en', p_en);
$$;

-- who may see the costed numbers of a place (null = every place)
create or replace function public._d23_gate96(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and case when p_loc is null
    then (public._acct_all() and not exists (select 1 from public.locations l where public.can_loc(l.id) and not public._cost_ok(l.id)))
    else (public.can_loc(p_loc) and public._cost_ok(p_loc)) end;
$$;

-- =====================================================================================================================
-- D2 opening stock helper
-- =====================================================================================================================
-- one row per opening ledger row of the accounting period (costed or not), with what already happened to it
create or replace function public._ob_rows96(p_loc int)
returns table(lid bigint, loc int, k text, val numeric, nocost boolean, by_switch boolean, handled boolean)
language sql stable security definer set search_path = public as $$
  select l.id, l.location_id, public._acct_inv_key(it.item_type), round(l.qty_delta * coalesce(l.unit_cost, 0), 2), coalesce(l.unit_cost, 0) = 0,
         exists (select 1 from public.journal_entries e where e.source_type = 'stock_opening' and e.source_id = l.id::text and e.reverses_id is null),
         exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id))
  from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id
  where l.reason = 'opening' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (p_loc is null or l.location_id = p_loc)
    and (l.made_at at time zone 'Asia/Dhaka')::date >= greatest(public._acct_start(), coalesce(public._acct_from85(), public._acct_start()));
$$;

-- what the opening journal (acct_opening) already carries on the inventory accounts, per place (null place = not split by place) and inventory key
create or replace function public._ob_cover96() returns table(loc int, k text, amt numeric)
language sql stable security definer set search_path = public as $$
  select jl.location_id, m.key, sum(jl.debit - jl.credit)
  from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
  join public.acct_mappings m on m.account_id = jl.account_id and m.key in ('inv_finished', 'inv_raw', 'inv_pack')
  where e.source_type = 'opening' and e.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id)
  group by 1, 2;
$$;

-- the plan of one option: lines that would post, warnings, or an error code. No writes.
create or replace function public._ob_plan96(p_option text, p_loc int, p_account text, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); vals jsonb := '{}'::jsonb; cov jsonb := '{}'::jsonb; unt numeric := 0; k text; v numeric; c numeric; amt jsonb := '{}'::jsonb; tot numeric := 0;
        lines jsonb := '[]'::jsonb; ctr bigint; ctr_code text; acc public.coa_accounts; d date; n_unc int; sw numeric; warns jsonb := '[]'::jsonb; cov_all numeric; val_all numeric; maxlid bigint; cov_ids bigint[];
begin
  if st is null then return jsonb_build_object('ok', false, 'error', 'data_needed'); end if;
  if p_option is null or p_option not in ('owner_capital', 'existing_account', 'skip', 'difference') then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;
  if p_loc is null and p_option <> 'difference' then return jsonb_build_object('ok', false, 'error', 'place_needed'); end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then return jsonb_build_object('ok', false, 'error', 'bad_location'); end if;
  if exists (select 1 from public.opening_stock_actions96 a where a.option <> 'skip' and (a.location_id is null or p_loc is null or a.location_id = p_loc)) then
    return jsonb_build_object('ok', false, 'error', 'already_applied'); end if;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into vals from (select r.k, sum(r.val) s from public._ob_rows96(p_loc) r where not r.nocost and not r.by_switch and not r.handled group by r.k) x;
  select count(*) filter (where r.nocost and not r.by_switch and not r.handled), coalesce(sum(r.val) filter (where r.by_switch), 0) into n_unc, sw from public._ob_rows96(p_loc) r;
  select coalesce(jsonb_object_agg(x.k, x.s), '{}'::jsonb) into cov from (select o.k, sum(o.amt) s from public._ob_cover96() o where p_loc is null or o.loc = p_loc group by o.k) x;
  select coalesce(sum(o.amt), 0) into unt from public._ob_cover96() o where o.loc is null;
  if p_option = 'difference' and p_loc is not null and unt > 0 then return jsonb_build_object('ok', false, 'error', 'untagged_opening_inventory'); end if;
  d := coalesce(p_date, st);
  if d < st then return jsonb_build_object('ok', false, 'error', 'before_start'); end if;
  if d > public._acct_today() + 1 then return jsonb_build_object('ok', false, 'error', 'bad_date'); end if;
  select coalesce(sum(value::numeric), 0) into val_all from jsonb_each_text(vals);
  select coalesce(sum(value::numeric), 0) into cov_all from jsonb_each_text(cov);
  if n_unc > 0 then warns := warns || to_jsonb('uncosted_openings'::text); end if;
  if public.rule_on('acct_stock_opening') then warns := warns || to_jsonb('switch_on'::text); end if;
  if p_option = 'skip' then
    if cov_all + unt < val_all then warns := warns || to_jsonb('skip_but_not_in_opening_journal'::text); end if;
  else
    if p_option = 'existing_account' and p_account is null then return jsonb_build_object('ok', false, 'error', 'account_needed'); end if;
    if p_account is not null then
      select * into acc from public.coa_accounts a where a.code = p_account and a.active and not a.is_group and a.type in ('equity', 'liability')
        and not exists (select 1 from public.acct_mappings m where m.account_id = a.id and m.key in ('inv_finished', 'inv_raw', 'inv_pack'));
      if not found then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
      ctr := acc.id; ctr_code := acc.code;
    elsif p_option <> 'existing_account' then
      select m.account_id, a.code into ctr, ctr_code from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = 'stock_opening_equity';
      if ctr is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:stock_opening_equity'); end if;
    end if;
    if p_option = 'owner_capital' and p_account is not null then return jsonb_build_object('ok', false, 'error', 'bad_option'); end if;   -- owner_capital always uses the stock_opening_equity mapping
    for k in select unnest(array['inv_finished', 'inv_raw', 'inv_pack']) loop
      v := coalesce((vals->>k)::numeric, 0); c := coalesce((cov->>k)::numeric, 0);
      if p_option = 'difference' then v := greatest(v - c, 0); end if;
      v := round(v, 2);
      if v > 0 then
        select a.id into maxlid from public.acct_mappings m join public.coa_accounts a on a.id = m.account_id where m.key = k;
        if maxlid is null then return jsonb_build_object('ok', false, 'error', 'mapping_missing:' || k); end if;
        amt := amt || jsonb_build_object(k, v); tot := tot + v;
        lines := lines || jsonb_build_object('account_id', maxlid, 'debit', v, 'credit', 0, 'location_id', p_loc, 'memo', 'Opening stock');
      end if;
    end loop;
    if tot <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_to_post', 'detail', jsonb_build_object('uncosted_rows', n_unc, 'posted_by_switch', sw)); end if;
    lines := lines || jsonb_build_object('account_id', ctr, 'debit', 0, 'credit', tot, 'location_id', p_loc, 'memo', 'Opening stock counterpart');
    if public._acct_locked(d) then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
  end if;
  select coalesce(array_agg(r.lid order by r.lid) filter (where not r.handled and not r.by_switch and (p_option = 'skip' or not r.nocost)), '{}') into cov_ids from public._ob_rows96(p_loc) r;
  return jsonb_build_object('ok', true, 'option', p_option, 'location_id', p_loc, 'date', d, 'amount', tot, 'by_key', amt, 'counter_code', ctr_code, 'covered_ids_n', coalesce(array_length(cov_ids, 1), 0),
    'opening_value', val_all, 'already_in_opening_journal', cov_all, 'untagged_in_opening_journal', unt, 'uncosted_rows', n_unc, 'posted_by_switch', sw,
    'warnings', warns, 'covered_ids', cov_ids,
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'debit', (x->>'debit')::numeric, 'credit', (x->>'credit')::numeric, 'location_id', p_loc)), '[]'::jsonb)
                from jsonb_array_elements(lines) x join public.coa_accounts a on a.id = (x->>'account_id')::bigint),
    'post_lines', lines);
end $$;

-- READ ONLY: per place the opening stock, what the opening journal already carries, the GL inventory, the valuation and their difference; warnings for the double count
create or replace function public.opening_stock_check96(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); rowsj jsonb := '[]'::jsonb; l record; ov numeric; orows int; unc int; sw numeric; hd text; oj numeric; gl numeric; vl numeric; tov numeric := 0; toj numeric := 0; tgl numeric := 0; tvl numeric := 0;
        unt numeric; untgl numeric; warns jsonb := '[]'::jsonb; todo numeric := 0; risk boolean; sw_on boolean := public.rule_on('acct_stock_opening'); keys text[] := array['inv_finished', 'inv_raw', 'inv_pack'];
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  for l in select x.id, x.name_bn, x.name_en from public.locations x where x.is_active and (p_loc is null or x.id = p_loc) and public.can_loc(x.id) and public._cost_ok(x.id) order by x.sort, x.id loop
    select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0), count(*) filter (where not r.handled and not r.by_switch), count(*) filter (where r.nocost and not r.handled and not r.by_switch),
           coalesce(sum(r.val) filter (where r.by_switch), 0)
      into ov, orows, unc, sw from public._ob_rows96(l.id) r;
    select a.option into hd from public.opening_stock_actions96 a where a.location_id = l.id or a.location_id is null order by (a.option <> 'skip') desc, a.id desc limit 1;
    select coalesce(sum(o.amt), 0) into oj from public._ob_cover96() o where o.loc = l.id;
    select coalesce(sum(jl.debit - jl.credit), 0) into gl from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = any (keys) where jl.location_id = l.id;
    select coalesce(sum(round(b.qty * b.avg_cost, 2)), 0) into vl from public.stock_balance b join public.items it on it.id = b.item_id
      where b.location_id = l.id and it.count_in_business and b.qty <> 0 and b.avg_cost is not null;
    rowsj := rowsj || jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'opening_value', ov, 'opening_rows', orows, 'uncosted_rows', unc, 'posted_by_switch', sw,
      'decision', hd, 'opening_journal_inventory', oj, 'gl_inventory', gl, 'valuation', vl, 'diff', round(gl - vl, 2));
    tov := tov + ov; toj := toj + oj; tgl := tgl + gl; tvl := tvl + vl; todo := todo + ov;
    if unc > 0 and not (warns ? 'uncosted_openings') then warns := warns || to_jsonb('uncosted_openings'::text); end if;
  end loop;
  select coalesce(sum(o.amt), 0) into unt from public._ob_cover96() o where o.loc is null;
  select coalesce(sum(jl.debit - jl.credit), 0) into untgl from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = any (keys) where jl.location_id is null;
  toj := toj + unt; tgl := tgl + untgl;
  risk := toj > 0 and todo > 0;
  if toj > 0 then warns := warns || to_jsonb('opening_journal_has_inventory'::text); end if;
  if risk and sw_on then warns := warns || to_jsonb('switch_on_double_count'::text);
  elsif risk then warns := warns || to_jsonb('switch_would_double_count'::text); end if;
  if unt > 0 then warns := warns || to_jsonb('opening_journal_not_split_by_place'::text); end if;
  return jsonb_build_object('start', st, 'accounting_on', public.rule_on('accounting_on'), 'switch_on', sw_on, 'rows', rowsj,
    'untagged', jsonb_build_object('opening_journal_inventory', unt, 'gl_inventory', untgl),
    'total', jsonb_build_object('opening_value', tov, 'opening_journal_inventory', toj, 'gl_inventory', tgl, 'valuation', tvl, 'diff', round(tgl - tvl, 2)),
    'risk', risk, 'warnings', warns,
    'note', jsonb_build_object('bn', 'শুধু দেখা: কিছু post হয়নি। শুরুর জের (opening journal) এ stock আগেই থাকলে acct_stock_opening চালালে দুইবার গোনা হবে।',
      'mix', 'Read only: কিছু post হয়নি। Opening journal এ stock আগেই থাকলে acct_stock_opening চালালে দুইবার গোনা হবে।',
      'en', 'Read only: nothing is posted. If the stock is already in the opening journal, turning acct_stock_opening on would count it twice.'));
end $$;

-- DRY RUN: the entry an option would post, or the reason it cannot. No writes.
create or replace function public.opening_stock_preview96(p_option text, p_loc int default null, p_account text default null, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date) - 'post_lines' - 'covered_ids';
  return pl || jsonb_build_object('dry', true);
end $$;

-- APPLY: owner only, audited (decision table + journal entry), idempotent by client id, one posting per place
create or replace function public.opening_stock_apply96(p_option text, p_loc int, p_account text default null, p_date date default null, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; eid bigint; aid bigint; r public.opening_stock_actions96; staff text;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into r from public.opening_stock_actions96 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'option', r.option, 'entry_id', r.entry_id); end if;
  perform pg_advisory_xact_lock(hashtextextended('opening_stock96', 0));
  pl := public._ob_plan96(p_option, p_loc, p_account, p_date);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  if p_option <> 'skip' then
    eid := public._acct_write((pl->>'date')::date, p_loc, 'opening_stock96', 'loc:' || coalesce(p_loc::text, 'all'), p_option,
             'Opening stock (' || p_option || ')' || coalesce(': ' || nullif(btrim(p_reason), ''), ''), null, pl->'post_lines', null, p_client, null);
  end if;
  insert into public.opening_stock_actions96 (location_id, option, account_code, amount, entry_id, covered_ids, reason, client_id, created_by, created_staff)
    values (p_loc, p_option, case when p_option in ('existing_account', 'difference') then p_account end, coalesce((pl->>'amount')::numeric, 0), eid, (select coalesce(array_agg(x::bigint), '{}') from jsonb_array_elements_text(pl->'covered_ids') x),
            left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), staff) returning id into aid;
  return jsonb_build_object('id', aid, 'option', p_option, 'location_id', p_loc, 'entry_id', eid, 'amount', coalesce((pl->>'amount')::numeric, 0), 'warnings', pl->'warnings');
end $$;

-- RECOMMENDATION from the numbers (never applied by itself)
create or replace function public.opening_stock_recommend96(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v numeric; cv numeric; unt numeric; n_unc int; scope int := p_loc; opt text; why jsonb; alts jsonb := '[]'::jsonb; o text; pl jsonb; handled text;
begin
  if not (public._acct_view() and public._d23_gate96(p_loc)) then raise exception 'not allowed'; end if;
  if public._acct_start() is null then return jsonb_build_object('data_needed', true, 'never_auto', true); end if;
  select coalesce(sum(o2.amt), 0) into unt from public._ob_cover96() o2 where o2.loc is null;
  if unt > 0 and p_loc is not null then scope := null; end if;            -- the opening journal is not split by place: judge the whole company
  select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0), count(*) filter (where r.nocost and not r.handled and not r.by_switch)
    into v, n_unc from public._ob_rows96(scope) r;
  select coalesce(sum(o2.amt), 0) into cv from public._ob_cover96() o2 where scope is null or o2.loc = scope or o2.loc is null;
  select a.option into handled from public.opening_stock_actions96 a where scope is null or a.location_id is null or a.location_id = scope order by (a.option <> 'skip') desc, a.id desc limit 1;
  if handled is not null and v = 0 then
    opt := 'none'; why := public._t96('এই opening stock নিয়ে সিদ্ধান্ত আগেই নেওয়া হয়েছে; আর কিছু করার নেই।', 'এই opening stock নিয়ে decision আগেই নেওয়া হয়েছে; আর কিছু করার নেই।', 'A decision about this opening stock was already taken; nothing more to do.');
  elsif v = 0 and n_unc > 0 then
    opt := 'wait_for_cost'; why := public._t96('opening stock এর cost জানা নেই; আগে cost দিন (cost waiting list), তারপর অপশন বেছে নিন।', 'Opening stock এর cost জানা নেই; আগে cost দিন (cost waiting list), তারপর option বাছুন।', 'The cost of the opening stock is unknown; supply the cost first (cost waiting list), then choose an option.');
  elsif v = 0 then
    opt := 'none'; why := public._t96('post করার মতো opening stock নেই।', 'Post করার মতো opening stock নেই।', 'There is no opening stock to post.');
  elsif cv > 0 and cv >= v then
    opt := 'skip'; why := public._t96('শুরুর জের (opening journal) এ stock এর টাকা আগেই ধরা আছে; আবার ধরলে দুইবার গোনা হবে। তাই সিদ্ধান্ত লিখে রাখুন, কিছু post করবেন না।', 'Opening journal এ stock এর টাকা আগেই ধরা আছে; আবার ধরলে দুইবার গোনা হবে। তাই decision লিখে রাখুন, কিছু post করবেন না।', 'The opening journal already carries the stock value; posting again would count it twice. Record the decision and post nothing.');
  elsif cv > 0 then
    opt := 'difference'; why := public._t96('শুরুর জের এ stock এর টাকা আংশিক ধরা আছে; শুধু বাকি অংশটুকু post করুন।', 'Opening journal এ stock এর টাকা আংশিক ধরা আছে; শুধু বাকি অংশটুকু post করুন।', 'The opening journal carries only part of the stock value; post only the part that is missing.');
  else
    opt := 'owner_capital'; why := public._t96('শুরুর জের এ stock নেই; opening stock মালিকের মূলধনের বিপরীতে ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'Opening journal এ stock নেই; opening stock owner capital এর against এ ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'The opening journal has no stock; booking the opening stock against owner capital is the most reasonable choice.');
  end if;
  foreach o in array array['owner_capital', 'existing_account', 'skip', 'difference'] loop
    pl := public._ob_plan96(case when o = 'existing_account' then 'owner_capital' else o end, scope, null, null);
    alts := alts || jsonb_build_object('option', o, 'amount', case when o = 'skip' then 0 else coalesce((pl->>'amount')::numeric, 0) end, 'possible', coalesce((pl->>'ok')::boolean, false),
              'error', case when coalesce((pl->>'ok')::boolean, false) then null else pl->>'error' end, 'needs_account', o = 'existing_account');
  end loop;
  return jsonb_build_object('location_id', p_loc, 'scope_location_id', scope, 'recommended', opt, 'reason', why, 'numbers', jsonb_build_object('opening_value', v, 'already_in_opening_journal', cv, 'uncosted_rows', n_unc),
    'alternatives', alts, 'never_auto', true);
end $$;

-- a warning in the audit trail when acct_stock_opening is turned ON while the opening journal already carries inventory
create or replace function public._ob_rule_watch96() returns trigger language plpgsql security definer set search_path = public as $$
declare toj numeric; todo numeric; sid text;
begin
  if new.key = 'acct_stock_opening' and coalesce(new.value, new.default_value) = 'true'::jsonb and coalesce(old.value, old.default_value) is distinct from 'true'::jsonb then
    select coalesce(sum(o.amt), 0) into toj from public._ob_cover96() o;
    select coalesce(sum(r.val) filter (where not r.nocost and not r.handled and not r.by_switch), 0) into todo from public._ob_rows96(null) r;
    if toj > 0 and todo > 0 then
      select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
        values (auth.uid(), sid, 'warn', 'rules', 'acct_stock_opening', jsonb_build_object('code', 'switch_on_double_count', 'opening_journal_inventory', toj, 'opening_stock_to_post', todo));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rules_watch_opening96 on public.rules;
create trigger rules_watch_opening96 after update on public.rules for each row execute function public._ob_rule_watch96();

-- =====================================================================================================================
-- D3 cost waiting
-- =====================================================================================================================
-- the ledger rows of one document that still have no cost (cost 0 = unknown, "cost really zero" items excluded, reversed rows excluded)
create or replace function public._cw_rows96(p_kind text, p_ref text)
returns table(lid bigint, item_id uuid, loc int, qty numeric, reason text, made_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, l.item_id, l.location_id, l.qty_delta, l.reason, l.made_at
  from public.stock_ledger_eff96 l
  where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
    and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
    and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                    and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
    and not (l.reason = 'opening' and exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id)))
    and case p_kind
      when 'wastage' then l.reason = 'wastage' and l.ref_type = 'wastage' and l.ref_id = p_ref
      when 'production' then l.reason = 'issue_out' and l.ref_type = 'production' and l.ref_id = p_ref
      when 'transfer' then l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' and l.ref_id = p_ref
      when 'purchase_return' then l.reason = 'purchase_return' and l.ref_type = 'purchase' and l.ref_id = p_ref
      when 'ledger' then l.id::text = p_ref and (l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production'))
      else false end;
$$;

-- is the document already in the journal (then a late cost cannot post it again)
create or replace function public._cw_posted96(p_kind text, p_ref text) returns boolean language sql stable security definer set search_path = public as $$
  select case p_kind
    when 'wastage' then exists (select 1 from public.journal_entries e where e.source_type = 'wastage' and e.source_id = p_ref and e.reverses_id is null)
    when 'production' then exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = p_ref and e.reverses_id is null)
    when 'purchase_return' then exists (select 1 from public.journal_entries e where e.source_type = 'purchase_variance' and e.source_id = p_ref and e.reverses_id is null)
    when 'transfer' then exists (select 1 from public.journal_entries e where e.reverses_id is null and ((e.source_type = 'stock_transfer' and e.source_id in
                                   (select s.id::text from public.stock_ledger s where s.ref_type = 'transfer' and s.ref_id = p_ref)) or (e.source_type = 'transit_loss' and e.source_id = p_ref)))
    when 'ledger' then exists (select 1 from public.journal_entries e where e.source_type in ('stock_adjust', 'stock_opening', 'stock_issue') and e.source_id = p_ref and e.reverses_id is null)
    else false end;
$$;

-- every document that waits for a cost and is not in the journal yet
create or replace function public._cw_docs96() returns table(kind text, ref text, loc int, d date, n int, gl boolean, move text)
language sql stable security definer set search_path = public as $$
  with u as (
    select l.id, l.location_id, l.reason, l.ref_type, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date dd,
      case when l.reason = 'wastage' and l.ref_type = 'wastage' then 'wastage'
           when l.reason = 'issue_out' and l.ref_type = 'production' then 'production'
           when l.reason in ('transfer_out', 'transfer_in') and l.ref_type = 'transfer' then 'transfer'
           when l.reason = 'purchase_return' and l.ref_type = 'purchase' then 'purchase_return'
           when l.reason in ('count_adjust', 'opening') or (l.reason = 'issue_out' and l.ref_type is distinct from 'production') then 'ledger' end k
    from public.stock_ledger_eff96 l
    where coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null and l.reason <> 'reversal' and not public._cost_free80(l.item_id)
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
      and (l.reason <> 'transfer_in' or not exists (select 1 from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0))
      and not (l.reason = 'opening' and exists (select 1 from public.opening_stock_actions96 a where l.id = any (a.covered_ids) and (a.location_id is null or a.location_id = l.location_id)))),
  g as (
    select u.k, case when u.k = 'ledger' then u.id::text else u.ref_id end ref, (array_agg(u.location_id order by u.id))[1] loc, min(u.dd) d, count(*)::int n, min(u.reason) r
    from u where u.k is not null group by 1, 2)
  select g.k, g.ref, g.loc, g.d, g.n,
         public.rule_on('accounting_on') and public._acct_start() is not null and g.d >= public._acct_start() and g.d >= coalesce(public._acct_from85(), public._acct_start())
         and case g.k when 'wastage' then true when 'production' then true when 'transfer' then coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged'
                      when 'purchase_return' then public.rule_on('acct_purchase_variance')
                      else case g.r when 'count_adjust' then public.rule_on('acct_count_adjust') when 'opening' then public.rule_on('acct_stock_opening') else public.rule_on('acct_issue_out') end end,
         g.r
  from g where g.ref is not null and not public._cw_posted96(g.k, g.ref);
$$;

-- candidate costs of an item at a place: average, last purchase before the movement, recipe standard
create or replace function public._cw_cands96(p_item uuid, p_loc int, p_at timestamptz) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare av numeric; lb numeric; rc numeric; rid uuid; j jsonb;
begin
  select b.avg_cost into av from public.stock_balance b where b.item_id = p_item and b.location_id = p_loc;
  if coalesce(av, 0) <= 0 then
    select sum(b.qty * b.avg_cost) / nullif(sum(b.qty), 0) into av from public.stock_balance b where b.item_id = p_item and b.qty > 0 and b.avg_cost > 0;
  end if;
  if coalesce(av, 0) <= 0 then av := null; else av := round(av, 6); end if;
  select l.unit_cost into lb from public.stock_ledger_eff96 l where l.item_id = p_item and l.reason = 'purchase_in' and coalesce(l.unit_cost, 0) > 0 and l.made_at <= p_at order by l.made_at desc, l.id desc limit 1;
  select r.id into rid from public.recipes r where r.item_id = p_item and r.active order by r.version desc limit 1;
  if rid is not null then
    begin j := public.recipe_cost(rid, p_loc); rc := nullif(j->>'unit_cost', '')::numeric; if coalesce(rc, 0) <= 0 then rc := null; end if;
    exception when others then rc := null; end;
  end if;
  return jsonb_build_object('item_average', av, 'last_purchase', lb, 'recipe_standard', rc);
end $$;

create or replace function public._cw_manual96(p_manual jsonb, p_item uuid, p_groups int) returns numeric
language plpgsql immutable as $$
begin
  if p_manual is null then return null; end if;
  return case jsonb_typeof(p_manual)
    when 'array' then (select nullif(btrim(e->>'cost'), '')::numeric from jsonb_array_elements(p_manual) e where e->>'item_id' = p_item::text limit 1)
    when 'object' then nullif(btrim(p_manual->>(p_item::text)), '')::numeric
    when 'number' then case when p_groups = 1 then (p_manual #>> '{}')::numeric end
    else null end;
exception when others then return -1;
end $$;

-- THE PLAN: which cost each item of the document would get with a method (or the recommended one). No writes.
create or replace function public._cw_plan96(p_kind text, p_ref text, p_method text, p_manual jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g record; c jsonb; m text; cost numeric; items_ jsonb := '[]'::jsonb; total numeric := 0; missing text[] := '{}'; ng int; qa numeric; derived jsonb := '[]'::jsonb; locs int[] := '{}';
        ing numeric; conv numeric; pin record; ing_ok boolean := true; bad_manual boolean := false; alts jsonb; rec text; need_manual jsonb := '[]'::jsonb;
begin
  if p_kind is null or p_kind not in ('wastage', 'production', 'transfer', 'purchase_return', 'ledger') then return jsonb_build_object('ok', false, 'error', 'bad_kind'); end if;
  if p_method is null or p_method not in ('item_average', 'last_purchase', 'recipe_standard', 'manual', 'recommended') then return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  select count(distinct r.item_id) into ng from public._cw_rows96(p_kind, p_ref) r;
  if ng = 0 then return jsonb_build_object('ok', false, 'error', 'nothing_waiting'); end if;
  select coalesce(array_agg(distinct r.loc), '{}') into locs from public._cw_rows96(p_kind, p_ref) r;
  for g in select r.item_id, array_agg(r.lid order by r.lid) lids, (array_agg(r.loc order by r.lid))[1] loc, min(r.made_at) made_at,
                  sum(abs(r.qty)) filter (where r.reason <> 'transfer_in') q_main, sum(abs(r.qty)) q_all, it.code, it.name_bn, it.name_en, it.base_unit
             from public._cw_rows96(p_kind, p_ref) r join public.items it on it.id = r.item_id group by r.item_id, it.code, it.name_bn, it.name_en, it.base_unit order by it.code loop
    qa := coalesce(g.q_main, g.q_all);
    c := public._cw_cands96(g.item_id, g.loc, g.made_at);
    m := p_method;
    if m = 'recommended' then
      m := case when c->>'recipe_standard' is not null then 'recipe_standard' when c->>'item_average' is not null then 'item_average' when c->>'last_purchase' is not null then 'last_purchase' else 'manual' end;
    end if;
    if m = 'manual' then cost := public._cw_manual96(p_manual, g.item_id, ng); else cost := nullif(c->>m, '')::numeric; end if;
    if cost is not null and cost < 0 then bad_manual := true; cost := null; end if;
    if cost is not null and (cost <= 0 or cost >= 1000000000000) then bad_manual := true; cost := null; end if;
    if cost is null then
      if p_method = 'recommended' then need_manual := need_manual || to_jsonb(g.code); else missing := missing || g.code; end if;
    end if;
    rec := case when c->>'recipe_standard' is not null then 'recipe_standard' when c->>'item_average' is not null then 'item_average' when c->>'last_purchase' is not null then 'last_purchase' else 'manual' end;
    alts := (select coalesce(jsonb_agg(jsonb_build_object('method', k, 'unit_cost', nullif(c->>k, '')::numeric, 'amount', round(qa * nullif(c->>k, '')::numeric, 2))), '[]'::jsonb)
               from unnest(array['item_average', 'last_purchase', 'recipe_standard']) k where c->>k is not null);
    items_ := items_ || jsonb_build_object('item_id', g.item_id, 'code', g.code, 'name_bn', g.name_bn, 'name_en', g.name_en, 'unit', g.base_unit, 'qty', qa, 'location_id', g.loc, 'lids', to_jsonb(g.lids),
               'method', m, 'unit_cost', cost, 'amount', case when cost is not null then round(qa * cost, 2) end, 'recommended', rec, 'candidates', c, 'alternatives', alts,
               'reason', case rec when 'recipe_standard' then public._t96('এই item নিজেদের তৈরি; recipe এর standard cost ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'এই item নিজেদের তৈরি; recipe এর standard cost ধরাই সবচেয়ে যুক্তিসঙ্গত।', 'This item is made in-house; the recipe standard cost is the most reasonable figure.')
                                  when 'item_average' then public._t96('stock এ এই item এর average cost আগে থেকেই আছে; এটি ধরলে খাতা আর stock valuation এক থাকে।', 'Stock এ এই item এর average cost আগে থেকেই আছে; এটি ধরলে খাতা আর stock valuation এক থাকে।', 'The stock already carries this item at its average cost; using it keeps the books and the stock valuation in step.')
                                  when 'last_purchase' then public._t96('average cost জানা নেই; সবচেয়ে সাম্প্রতিক কেনা cost সবচেয়ে কাছের প্রমাণ।', 'Average cost জানা নেই; সবচেয়ে recent purchase cost-ই সবচেয়ে কাছের প্রমাণ।', 'No average cost is known; the latest purchase cost is the closest evidence.')
                                  else public._t96('কোনো cost জানা নেই; নিজে cost লিখুন ও কারণ দিন, সিস্টেম কিছু ধরে নেয় না।', 'কোনো cost জানা নেই; নিজে cost লিখুন ও reason দিন, system কিছু ধরে নেয় না।', 'No cost is known; type the cost and give a reason - the system assumes nothing.') end);
    total := total + coalesce(round(qa * cost, 2), 0);
  end loop;
  if bad_manual then return jsonb_build_object('ok', false, 'error', 'bad_manual', 'items', items_); end if;
  if coalesce(array_length(missing, 1), 0) > 0 then return jsonb_build_object('ok', false, 'error', 'cost_unavailable', 'detail', array_to_string(missing, ','), 'items', items_); end if;
  -- the finished good of a production run: ingredient cost + conversion cost, per unit (a record for the ledger valuation; the stock average cache is not changed)
  if p_kind = 'production' and jsonb_array_length(need_manual) = 0 then
    select coalesce(sum(abs(l.qty_delta) * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0), 0) + total into ing from public.stock_ledger_eff96 l
      where l.ref_type = 'production' and l.ref_id = p_ref and l.reason = 'issue_out' and l.reverses_id is null;
    select coalesce(r.conversion_cost, 0) into conv from public.production_runs r where r.id::text = p_ref;
    for pin in select l.item_id, array_agg(l.id order by l.id) lids, sum(l.qty_delta) q from public.stock_ledger_eff96 l
                where l.ref_type = 'production' and l.ref_id = p_ref and l.reason = 'production_in' and coalesce(l.unit_cost, 0) = 0 and l.reverses_id is null
                  and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id) group by l.item_id loop
      if pin.q > 0 and ing + coalesce(conv, 0) > 0 then
        derived := derived || jsonb_build_object('item_id', pin.item_id, 'lids', to_jsonb(pin.lids), 'method', 'from_ingredients', 'unit_cost', round((ing + coalesce(conv, 0)) / pin.q, 6), 'qty', pin.q);
      end if;
    end loop;
  end if;
  return jsonb_build_object('ok', true, 'kind', p_kind, 'ref', p_ref, 'method', p_method, 'items', items_, 'derived', derived, 'total', round(total, 2), 'location_ids', to_jsonb(locs), 'needs_manual', need_manual);
end $$;

-- the list (shared by the list and the alert)
create or replace function public._cw_list96(p_loc int, p_limit int, p_only_old boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dd record; days numeric := public.rule_num('acct_cost_wait_alert_days'); t date := public._acct_today(); arr jsonb := '[]'::jsonb; n int := 0; tot int := 0; old int := 0; oldest int := 0; age int; over boolean;
        lim int := least(greatest(coalesce(p_limit, 100), 1), 500); by_kind jsonb := '{}'::jsonb;
begin
  for dd in select * from public._cw_docs96() x where (p_loc is null or x.loc = p_loc) and public.can_loc(x.loc) and public._cost_ok(x.loc) order by x.d, x.kind, x.ref loop
    age := t - dd.d; over := days is not null and age > days;
    tot := tot + 1; if over then old := old + 1; end if; oldest := greatest(oldest, age);
    by_kind := jsonb_set(by_kind, array[dd.kind], to_jsonb(coalesce((by_kind->>dd.kind)::int, 0) + 1));
    if n < lim and (not p_only_old or over) then
      n := n + 1;
      arr := arr || jsonb_build_object('kind', dd.kind, 'ref', dd.ref, 'location_id', dd.loc, 'date', dd.d, 'age_days', age, 'rows', dd.n, 'move', dd.move, 'gl_post', dd.gl, 'over_alert', case when days is not null then over end,
        'items', (select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_bn', z.name_bn, 'name_en', z.name_en, 'unit', z.base_unit, 'qty', z.q) order by z.code), '[]'::jsonb)
                    from (select r.item_id, it.code, it.name_bn, it.name_en, it.base_unit, sum(abs(r.qty)) filter (where r.reason <> 'transfer_in') q
                            from public._cw_rows96(dd.kind, dd.ref) r join public.items it on it.id = r.item_id group by 1, 2, 3, 4, 5) z));
    end if;
  end loop;
  return jsonb_build_object('as_of', t, 'alert_days', days, 'alert_enabled', days is not null, 'total', tot, 'shown', n, 'old_count', case when days is not null then old end, 'oldest_days', oldest, 'by_kind', by_kind, 'items', arr);
end $$;

create or replace function public.cost_wait_list96(p_loc int default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not exists (select 1 from public.locations l where public.can_loc(l.id) and public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  return public._cw_list96(p_loc, p_limit, false);
end $$;

-- the aging alert: documents waiting longer than the number the owner typed (blank = no alert)
create or replace function public.cost_wait_alert96(p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_active() or not exists (select 1 from public.locations l where public.can_loc(l.id) and public._cost_ok(l.id)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  r := public._cw_list96(p_loc, p_limit, true);
  return r || jsonb_build_object('alert', coalesce((r->>'alert_enabled')::boolean and (r->>'old_count')::int > 0, false),
    'message', public._t96('এই document গুলো cost এর অপেক্ষায় আছে; cost দিলে একবারই post হবে।', 'এই document গুলো cost এর অপেক্ষায় আছে; cost দিলে একবারই post হবে।', 'These documents are waiting for their cost; once a cost is supplied each posts once.'));
end $$;

create or replace function public._cw_visible96(p_kind text, p_ref text) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public._cw_rows96(p_kind, p_ref))
     and not exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc)));
$$;

-- DRY RUN of one method (or the recommended choice per item): costs, amounts, what is missing. No writes.
create or replace function public.cost_wait_preview96(p_kind text, p_ref text, p_method text default 'recommended', p_manual jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  pl := public._cw_plan96(p_kind, p_ref, p_method, p_manual);
  return (pl - 'items') || jsonb_build_object('dry', true, 'items', (select coalesce(jsonb_agg(x - 'lids'), '[]'::jsonb) from jsonb_array_elements(coalesce(pl->'items', '[]'::jsonb)) x),
    'gl_post', (select d.gl from public._cw_docs96() d where d.kind = p_kind and d.ref = p_ref));
end $$;

-- RECOMMENDATION: the best method per item from the numbers (never applied by itself)
create or replace function public.cost_wait_recommend96(p_kind text, p_ref text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pl jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  pl := public._cw_plan96(p_kind, p_ref, 'recommended', null);
  if not (pl->>'ok')::boolean then return pl || jsonb_build_object('never_auto', true); end if;
  return (pl - 'items') || jsonb_build_object('never_auto', true, 'items', (select coalesce(jsonb_agg(x - 'lids'), '[]'::jsonb) from jsonb_array_elements(pl->'items') x));
end $$;

-- SUPPLY: owner or cost-right holder; the cost is kept in the append-only table, the document then posts once (je_source_uq)
create or replace function public.cost_wait_supply96(p_kind text, p_ref text, p_method text, p_manual jsonb default null, p_reason text default null, p_client uuid default null, p_post boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; it jsonb; lid jsonb; n int := 0; staff text; pr jsonb; cnt int; posted boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  if p_method is null or p_method not in ('item_average', 'last_purchase', 'recipe_standard', 'manual') then raise exception 'bad_method'; end if;
  perform public._client_lock(p_client);
  select count(*) into cnt from public.ledger_cost_supply96 where client_id = p_client;
  if cnt > 0 then return jsonb_build_object('dup', true, 'rows', cnt, 'posted', public._cw_posted96(p_kind, p_ref)); end if;
  if exists (select 1 from public._cw_rows96(p_kind, p_ref) r where not (public.can_loc(r.loc) and public._cost_ok(r.loc))) then raise exception 'not allowed'; end if;
  if p_method = 'manual' and length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'reason_needed'; end if;
  perform pg_advisory_xact_lock(hashtextextended('cost_supply96', 0));
  if public._cw_posted96(p_kind, p_ref) then raise exception 'already_posted'; end if;
  pl := public._cw_plan96(p_kind, p_ref, p_method, p_manual);
  if not (pl->>'ok')::boolean then raise exception '%', pl->>'error' using detail = left(coalesce(pl->>'detail', ''), 500); end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  for it in select * from jsonb_array_elements(pl->'items') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, it->>'method', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, it->'candidates', auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  for it in select * from jsonb_array_elements(pl->'derived') loop
    for lid in select * from jsonb_array_elements(it->'lids') loop
      insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, basis, supplied_by, supplied_staff)
        values ((lid #>> '{}')::bigint, (it->>'unit_cost')::numeric, 'from_ingredients', left(nullif(btrim(p_reason), ''), 300), p_kind, p_ref, p_client, null, auth.uid(), staff);
      n := n + 1;
    end loop;
  end loop;
  if coalesce(p_post, true) and public.rule_on('accounting_on') and public._acct_manage() then pr := public.acct_post_pending(false, 1500); end if;
  posted := public._cw_posted96(p_kind, p_ref);
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'method', p_method, 'rows', n, 'total', pl->'total', 'posted', posted,
    'post_run', case when pr is null then null else jsonb_build_object('posted', pr->'posted', 'locked', pr->'locked', 'errors', pr->'errors') end);
end $$;

-- ---------- privileges: internals closed; the calls are for signed-in people (each one checks its own right) ----------
revoke all on function public._t96(text, text, text), public._d23_gate96(int), public._ob_rows96(int), public._ob_cover96(), public._ob_plan96(text, int, text, date), public._ob_rule_watch96(),
  public._cw_rows96(text, text), public._cw_posted96(text, text), public._cw_docs96(), public._cw_cands96(uuid, int, timestamptz), public._cw_manual96(jsonb, uuid, int),
  public._cw_plan96(text, text, text, jsonb), public._cw_list96(int, int, boolean), public._cw_visible96(text, text) from public, anon, authenticated;
revoke all on function public.opening_stock_check96(int), public.opening_stock_preview96(text, int, text, date), public.opening_stock_apply96(text, int, text, date, text, uuid), public.opening_stock_recommend96(int),
  public.cost_wait_list96(int, int), public.cost_wait_alert96(int, int), public.cost_wait_preview96(text, text, text, jsonb), public.cost_wait_recommend96(text, text),
  public.cost_wait_supply96(text, text, text, jsonb, text, uuid, boolean) from public, anon;
grant execute on function public.opening_stock_check96(int), public.opening_stock_preview96(text, int, text, date), public.opening_stock_apply96(text, int, text, date, text, uuid), public.opening_stock_recommend96(int),
  public.cost_wait_list96(int, int), public.cost_wait_alert96(int, int), public.cost_wait_preview96(text, text, text, jsonb), public.cost_wait_recommend96(text, text),
  public.cost_wait_supply96(text, text, text, jsonb, text, uuid, boolean) to authenticated;

-- ============================================================================
-- End of FRESH part 8 of 21.
