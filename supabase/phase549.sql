-- Phase 549 (READINESS D1) - freight / transporter payable (account 2150) is visible in the supplier lists and payable through the normal supplier payment.
-- Paste AFTER phase548. Paste-twice safe (every patch looks for its own marker first). Earlier phase files are not edited.
-- Problem (reproduced by tests/sql/readiness, scenario P2/P3): a landed cost with a charge line pay_mode = payable and supplier_id = transporter credits account 2150
--   with the transporter as party (phase 97). supplier_dues / supplier_open_bills / supplier_ledger / _sup_balance only know purchase bills, so the transporter
--   is owed 490 in the books but appears in no list, and pay_supplier raises 'overpaid'.
-- Fix (additive): (1) column supplier_payments.landed_part (the part of a payment that settles landed charges; default 0); (2) a BEFORE INSERT trigger sets it:
--   ordinary bills are settled first, the rest (up to what is owed for landed charges) settles the landed charges; every payment path (pay_supplier, the approved
--   pay request, cheque clear) goes through it; (3) _lc_open() = landed charges still owed per supplier and place; (4) patches at anchors: _sup_open (landed rows appear
--   as the pseudo-bill "Landed charges", payments only reduce ordinary bills by amount - landed_part), _sup_balance (+ landed charges), supplier_ledger (a "landed" row per cost),
--   _acct_docs (a supplier payment debits 2150 for its landed part and 2100 for the rest), acct_reconcile (compares 2100 with the ordinary balance only).
-- No new rule: with no landed charge payable to a supplier every result is identical to before (landed_part stays 0). The behaviour starts when such a charge exists.
-- Every journal entry still balances: the two debit lines add up to the payment amount, the credit line is unchanged.
-- Test: supabase/phase549_test.sql and the readiness scenario (P2, P3).

alter table public.supplier_payments add column if not exists landed_part numeric not null default 0;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'supplier_payments_landed_part_chk549') then
    alter table public.supplier_payments add constraint supplier_payments_landed_part_chk549 check (landed_part >= 0 and landed_part <= amount);
  end if;
end $c$;

-- landed charges still owed, per supplier and place (payable lines of posted landed costs, minus the landed parts paid; payments are applied oldest place first)
create or replace function public._lc_open(p_supplier uuid default null)
returns table(supplier_id uuid, location_id integer, oldest date, open_amt numeric) language sql stable security definer set search_path = public as $$
  with ch as (
    select l.supplier_id, c.location_id, min(c.cost_date) oldest, sum(a.amount) charged
    from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
    where a.kind = 'post' and c.status = 'posted' and l.pay_mode = 'payable' and l.supplier_id is not null and (p_supplier is null or l.supplier_id = p_supplier)
    group by l.supplier_id, c.location_id),
  paid as (select p.supplier_id, sum(p.landed_part) paid from public.supplier_payments p where not p.voided and p.landed_part > 0 and (p_supplier is null or p.supplier_id = p_supplier) group by 1),
  cum as (select ch.*, sum(ch.charged) over (partition by ch.supplier_id order by ch.oldest, ch.location_id) cs from ch)
  select cum.supplier_id, cum.location_id, cum.oldest,
         cum.charged - least(cum.charged, greatest(0, coalesce(paid.paid, 0) - (cum.cs - cum.charged)))
  from cum left join paid on paid.supplier_id = cum.supplier_id $$;

create or replace function public._lc_charged(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(a.amount), 0)
  from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
  where a.kind = 'post' and c.status = 'posted' and l.pay_mode = 'payable' and l.supplier_id = p_supplier $$;

create or replace function public._lc_open_total(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._lc_charged(p_supplier) - coalesce((select sum(p.landed_part) from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided), 0) $$;

-- the debit lines of a supplier payment journal entry (2100 for the ordinary part, 2150 for the landed part; no zero line)
create or replace function public._p549_pay_debits(p_amount numeric, p_landed numeric, p_supplier uuid) returns jsonb language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb) from (
    select jsonb_build_object('a', 'payable', 'd', p_amount - coalesce(p_landed, 0), 'pt', 'supplier', 'pid', p_supplier::text) x where p_amount - coalesce(p_landed, 0) > 0
    union all
    select jsonb_build_object('a', 'landed_payable', 'd', p_landed, 'pt', 'supplier', 'pid', p_supplier::text) where coalesce(p_landed, 0) > 0) z $$;

-- the split: ordinary bills first, the rest settles landed charges
create or replace function public._p549_split_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare lc numeric; tot numeric; ord numeric;
begin
  lc := public._lc_open_total(new.supplier_id);
  if lc is null or lc <= 0 then new.landed_part := 0; return new; end if;
  tot := public._sup_balance(new.supplier_id);                 -- includes the landed charges (patched below)
  ord := greatest(tot - lc, 0);
  new.landed_part := least(lc, greatest(0, new.amount - ord));
  return new;
end $$;
drop trigger if exists zz549_landed_split_bi on public.supplier_payments;
create trigger zz549_landed_split_bi before insert on public.supplier_payments for each row execute function public._p549_split_bi();

create or replace function public._sup_balance_ord(p_supplier uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._sup_balance(p_supplier) - greatest(public._lc_open_total(p_supplier), 0) $$;

revoke all on function public._lc_open(uuid), public._lc_charged(uuid), public._lc_open_total(uuid), public._p549_pay_debits(numeric, numeric, uuid), public._p549_split_bi(), public._sup_balance_ord(uuid) from public, anon, authenticated;

-- patch helper (dropped at the end): the function text is read from the database, so later patches to it are kept
create or replace function public._p549_patch(p_sig text, p_marker text, p_from text[], p_to text[]) returns void language plpgsql as $$
declare d text; i int;
begin
  select pg_get_functiondef(p_sig::regprocedure) into d;
  if d is null then raise exception 'phase549: % not found', p_sig; end if;
  if position(p_marker in d) > 0 then return; end if;               -- already patched: paste twice does nothing
  for i in 1 .. array_length(p_from, 1) loop
    if position(p_from[i] in d) = 0 then raise exception 'phase549: an anchor of % was not found (the function text changed); nothing was changed: %', p_sig, left(p_from[i], 80); end if;
    d := replace(d, p_from[i], p_to[i]);
  end loop;
  execute d;
end $$;

select public._p549_patch('public._sup_open(uuid)', '/* p549 */',
  array['p.amount x from public.supplier_payments p', 'from c2 left join pool on pool.supplier_id = c2.supplier_id;'],
  array['p.amount - p.landed_part x /* p549 */ from public.supplier_payments p',
        E'from c2 left join pool on pool.supplier_id = c2.supplier_id\n  union all select o.supplier_id, null::uuid, ''Landed charges''::text, o.oldest, o.location_id, o.open_amt, o.open_amt from public._lc_open(p_supplier) o where o.open_amt > 0;']);

select public._p549_patch('public._sup_balance(uuid)', '/* p549 */',
  array['and not voided), 0);'],
  array['and not voided), 0)
       + coalesce(public._lc_charged(p_supplier), 0) /* p549 */;']);

select public._p549_patch('public.supplier_ledger(uuid,integer)', '/* p549 */',
  array['select f.refunded_at, ''refund'''],
  array['select (c.cost_date::timestamp at time zone ''Asia/Dhaka''), ''landed''::text, coalesce(nullif(c.shipment_ref, ''''), left(c.id::text, 8)), c.location_id, sum(a.amount), 0::numeric, null::text, null::bigint, null::uuid, 1 /* p549 */
        from public.landed_cost_alloc a join public.landed_cost_lines l on l.id = a.charge_line_id join public.landed_costs c on c.id = a.cost_id
        where a.kind = ''post'' and c.status = ''posted'' and l.pay_mode = ''payable'' and l.supplier_id = p_supplier and (p_loc is null or c.location_id = p_loc)
        group by c.id, c.cost_date, c.shipment_ref, c.location_id
      union all
      select f.refunded_at, ''refund''']);

select public._p549_patch('public._acct_docs(date)', '_p549_pay_debits',
  array['case when not p.voided then jsonb_build_array(jsonb_build_object(''a'', ''payable'', ''d'', p.amount, ''pt'', ''supplier'', ''pid'', p.supplier_id::text),'],
  array['case when not p.voided then public._p549_pay_debits(p.amount, p.landed_part, p.supplier_id) || jsonb_build_array(']);

select public._p549_patch('public.acct_reconcile(text)', '_sup_balance_ord',
  array['coalesce(public._sup_balance(s.id), 0) l', 'coalesce(public._sup_balance(s.id), 0) <> 0'],
  array['coalesce(public._sup_balance_ord(s.id), 0) l', 'coalesce(public._sup_balance_ord(s.id), 0) <> 0']);

drop function public._p549_patch(text, text, text[], text[]);
