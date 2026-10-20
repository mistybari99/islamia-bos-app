-- ============================================================================
-- DELTA part 1 of 2. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase499 phase501 phase502 phase503 phase504 phase505 phase529 phase530 phase531 phase532 phase533 phase534 phase535
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase499.sql
-- Phase 499 (SW-1) - SWEETS STOCK TRANSFERS: partial receipt in steps, paused destination, over-send.
-- Paste AFTER phase498. Paste-twice safe (create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A5 (factory to branch) and findings F-14 / F-15. Reproduced on a local throwaway
-- database built from the owner paste chain (before this file):
--   R1 over-send: 120 kg sent from a place with 100 kg on hand under the default stock_negative_mode 'warn': sender stock became -20.
--   R2 paused destination: a send to a place with status 'paused' was accepted.
--   R3 partial receipt: 20 kg sent, 8 received, the second receipt returned status 'received' and dup = true; 12 kg stayed in transit for ever.
-- Three new switches, ALL OFF by default. With every switch off, every function behaves exactly as before this file.
--   transfer_overdraw_block  (false): refuse a send that is bigger than the sender's stock on hand (error insufficient_stock).
--   transfer_paused_block    (false): refuse a send to a place whose status is not 'live' (error destination_paused).
--   transfer_partial_on      (false): a receipt may be part of the delivery. The transfer stays open ('sent') until the whole quantity has
--                                     arrived or the owner closes the rest with stock_close_transfer_short (the rest is then a transit_short
--                                     yellow exception, as today). The second and later receipts take goods from the first lines of the
--                                     delivery that have not arrived yet, so batches and unit cost travel with the goods.
-- Damage on a partial receipt is added up over the steps (received_damaged_qty is the total).
-- Business reasons (decided, not asked): an over-send makes a negative balance at the factory that nobody physically holds, so the owner
-- can refuse it; a send to a paused place puts goods where no one is open to receive them; a split delivery is normal for a factory that ships
-- by van in several lots. Each switch is listed in web/data/info.json so the owner sees what it does before switching it on.

do $g$ begin
  if to_regclass('public.stock_transfers') is null or to_regclass('public.stock_ledger') is null or to_regclass('public.locations') is null then
    raise exception 'phase499 needs the stock tables and locations (phase 3 to 10)';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, 'stock', 'switch', 'false'::jsonb, null, null, null, null, v.lab, v.lab, v.lab, v.hint, v.hint, v.srt
  from (values
    ('transfer_overdraw_block', 'পাঠানোর আগে স্টক যাচাই (স্টকের চেয়ে বেশি পাঠানো বন্ধ) / Refuse a send bigger than the stock on hand: on',
       'OFF = the send is accepted and the sender balance may go negative (today). ON = the send is refused with insufficient_stock.', 4991),
    ('transfer_paused_block', 'বন্ধ/স্থগিত জায়গায় পাঠানো বন্ধ / Refuse a send to a paused or closed place: on',
       'OFF = a send to a paused place is accepted (today). ON = refused with destination_paused.', 4992),
    ('transfer_partial_on', 'ভাগে ভাগে গ্রহণ (আংশিক রসিদ) / Receive a transfer in parts (partial receipt): on',
       'OFF = one receipt closes the transfer (today). ON = the transfer stays open until all arrives or is closed short by the owner.', 4993)
  ) as v(key, lab, hint, srt)
on conflict (key) do nothing;

-- 1. send: the two checks in front of the stock movement (the rest is the same as phase 3 to 10 wrote it)
create or replace function public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if public.rule_on('transfer_paused_block') and coalesce((select l.status from public.locations l where l.id = p_to), '') <> 'live' then
    raise exception 'destination_paused';
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if public.rule_on('transfer_overdraw_block') and coalesce((select sb.qty from public.stock_balance sb where sb.item_id = p_item and sb.location_id = p_from), 0) < bq then
    raise exception 'insufficient_stock';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, note, sent_by, sent_staff)
      values (tid, p_client, p_from, p_to, p_item, bq, left(p_note, 200), auth.uid(), sid);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins
    select * into t from public.stock_transfers where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
    raise;
  end;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $function$;

-- 2. receive: one step (as before) or several steps (switch transfer_partial_on)
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; ob public.stock_batches;
  lid bigint; got numeric; skip numeric; avail numeric; left_qty numeric; partial boolean;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  -- what has already arrived in earlier steps of this delivery (always 0 when the switch is off: one receipt closes the transfer)
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  left_qty := t.qty - got;
  rq := coalesce(p_received_qty, left_qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > left_qty then raise exception 'over_received'; end if;
  partial := public.rule_on('transfer_partial_on') and rq < left_qty;
  rem := rq;
  skip := got;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;      -- this line already arrived in an earlier step
    avail := avail - skip;
    skip := 0;
    take := least(avail, rem);
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
  if partial then
    update public.stock_transfers set received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
    return jsonb_build_object('id', t.id, 'status', 'sent', 'partial', true, 'received_qty', got + rq, 'remaining', left_qty - rq);
  end if;
  update public.stock_transfers set status = 'received', received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got + rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || (got + rq)::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || (got + rq)::text || ' — short in transit');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);
end $function$;

-- 3. receive with the damage count (phase 3 to 10 wrapper); the damage is added up over the steps
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; rq numeric; res jsonb; dq numeric := p_damaged_qty; rs text := nullif(btrim(p_damaged_reason), ''); it public.items; got numeric;
begin
  select * into t from public.stock_transfers where id = p_id;
  if not found then raise exception 'not found'; end if;
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  rq := coalesce(p_received_qty, t.qty - got);
  if dq is not null then
    if not (dq between 0 and 999999999) then raise exception 'bad_qty'; end if;
    if dq > rq then raise exception 'damaged_over_received'; end if;
    if dq > 0 and (rs is null or not exists (select 1 from public.option_lists where list_code = 'transfer_damage_reasons' and value_code = rs and active)) then raise exception 'damage_reason_required'; end if;
    if dq = 0 then rs := null; end if;
  end if;
  res := public.stock_receive_transfer(p_id, p_received_qty, p_note);          -- the 3-argument function: every rule (grant, short quantity, batches, exception, parts)
  if coalesce((res ->> 'dup')::boolean, false) then return res; end if;
  if dq is not null then
    update public.stock_transfers set received_damaged_qty = coalesce(received_damaged_qty, 0) + dq, damaged_reason = coalesce(rs, damaged_reason) where id = p_id;
    if dq > 0 then
      select * into it from public.items where id = t.item_id;
      perform public._stock_exc(t.to_location_id, 'transit_damaged', 'yellow', it.name_bn || ': গ্রহণ ' || rq::text || ', তার মধ্যে ' || dq::text || ' ক্ষতিগ্রস্ত',
        coalesce(it.name_en, it.name_bn) || ': received ' || rq::text || ', of which ' || dq::text || ' damaged');
    end if;
  end if;
  return res || jsonb_build_object('damaged', dq);
end $function$;

-- 4. the owner closes the rest of a split delivery as short (only when transfer_partial_on is on)
create or replace function public.stock_close_transfer_short(p_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare t public.stock_transfers; it public.items; got numeric; sid text;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  if not public.rule_on('transfer_partial_on') then raise exception 'partial_receipt_off'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = got, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || got::text || ' — পথে কম (বাকি বন্ধ করা হয়েছে)',
      coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || got::text || ' — short in transit (rest closed by the owner)');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got, 'short', t.qty - got);
end $function$;

-- Privileges: the same as the functions they replace (authenticated only). New function: closing a split delivery.
revoke all on function public.stock_close_transfer_short(uuid, text) from public, anon;
grant execute on function public.stock_close_transfer_short(uuid, text) to authenticated;

-- ---------------------------------------------------------------- phase501.sql
-- Phase 501 (SW-2) - SWEETS SALE STOCK: unknown unit refused on request, and a return uses the factor of the sale.
-- Paste AFTER phase499. Paste-twice safe (create table if not exists, create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A2 (sales to stock) and findings F-12 / F-13. Reproduced on a local throwaway database (before this file):
--   U1 unit: an item whose unit is not its base unit and has no conversion: a sale of 2 box is ACCEPTED, the stock is NOT reduced, only a yellow warning (default warn).
--   U2 return: 2 box sold at factor 12 (24 pieces out). The factor is then edited to 10 and the same 2 box are returned: 20 pieces come back, 4 are lost.
--   L1 late sale: with stock_negative_mode 'block', a sale whose sold_at is 10 minutes old (9 kg on 5 kg) is ACCEPTED, the stock goes to -4 and a
--      yellow stock_negative exception is written. A fresh sale of the same quantity is refused (insufficient_stock).
--      DECISION (business, not asked): a late sale is NOT refused. Goods that left the shop cannot be un-sold, and refusing a queued offline sale
--      loses the sale. The owner's yellow exception is the control. The clock-skew gap (a phone whose clock is behind reads as "late") is recorded in
--      docs/PLAN_NEXT.md as an open item: it needs a replay marker from the phone, which this file does not change.
-- Changes, both switches OFF by default (with both off every sale and every return works as before, except that each new sale now also keeps
-- the conversion factor it used, in the new table sale_base_factor, which nothing reads until return_sale_factor_on is switched on):
--   stock_unit_unknown_block (false): refuse the sale (error stock_unit_unknown) when a tracked line has no conversion, instead of accepting it without stock movement.
--   return_sale_factor_on    (false): a return puts back the quantity at the factor saved at the sale. Sales made before this file have no saved factor and use today's factor.

do $g$ begin
  if to_regclass('public.sales') is null or to_regclass('public.stock_ledger') is null then raise exception 'phase501 needs the sales and stock tables'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, 'stock', 'switch', 'false'::jsonb, null, null, null, null, v.lab, v.lab, v.lab, v.hint, v.hint, v.srt
  from (values
    ('stock_unit_unknown_block', 'এককের রূপান্তর না থাকলে বিক্রি বন্ধ / Refuse a sale when the unit conversion is unknown: on',
       'OFF = the sale is kept with a yellow warning and the stock is NOT reduced (today). ON = the sale is refused with stock_unit_unknown.', 5001),
    ('return_sale_factor_on', 'ফেরত: বিক্রির সময়ের রূপান্তর / Return at the conversion factor of the sale: on',
       'OFF = a return uses today''s conversion factor (today). ON = a return uses the factor saved when the sale was made.', 5002)
  ) as v(key, lab, hint, srt)
on conflict (key) do nothing;

-- the factor each sale used, per item and unit (written by the sale trigger; read by sale_return when its switch is on)
create table if not exists public.sale_base_factor (
  sale_id uuid not null,                        -- no foreign key on purpose: the test-project reset (phase 84) refuses a table that points at a cleared table
  item_id uuid not null,
  unit text not null default '',
  factor numeric not null check (factor > 0),
  created_at timestamptz not null default now(),
  primary key (sale_id, item_id, unit)
);
alter table public.sale_base_factor enable row level security;
revoke all on public.sale_base_factor from anon, authenticated;

-- backfill: nothing to do (sales made before this file have no saved factor; the return falls back to today's factor for them)

-- the sale trigger: the same stock movement as phase 3 to 10 wrote it, plus the saved factor and the unknown-unit switch
create or replace function public._sale_stock_out()
returns trigger language plpgsql security definer set search_path = public as $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner). See phase 501, L1.
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      if public.rule_on('stock_unit_unknown_block') then
        raise exception 'stock_unit_unknown' using detail = coalesce(it.code, ''), hint = 'unit ' || coalesce(ln->>'unit', '') || ' has no conversion to ' || coalesce(nullif(it.base_unit, ''), it.unit);
      end if;
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    insert into public.sale_base_factor (sale_id, item_id, unit, factor) values (new.id, it.id, coalesce(ln->>'unit', ''), round(bq / q, 12)) on conflict do nothing;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

-- the return: the same as phase 3 to 10 wrote it, with the factor of the sale when return_sale_factor_on is on (one line changes)
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
    bq := null;
    if public.rule_on('return_sale_factor_on') then                  -- the factor saved at the sale (sale_base_factor); older sales have none and use today's factor
      select f.factor * ln.q into bq from public.sale_base_factor f where f.sale_id = s.id and f.item_id = it.id and f.unit = coalesce(ln.u, '');
    end if;
    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
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
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  perform public._w1c_return_hook(rid); /* bos91 */
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $function$;

-- ---------------------------------------------------------------- phase502.sql
-- Phase 502 (SW-3) - SWEETS PROFIT: the item analysis (biz_items) nets sale returns, as the returns line of the other reports already says.
-- Paste AFTER phase501. Paste-twice safe (create or replace, on conflict do nothing). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A3 (real profit) and finding F-16: "biz_items / builder summaries do not consistently net sales returns".
-- Reproduced on a local throwaway database (before this file): 3 kg sold, 1 kg returned in the same period: biz_items shows qty 3 and the full revenue.
-- The audit names a "bos112 returns-netting block" that is live in biz_items but is NOT in this repository, and its text was not found (no backup text
-- in the repo, no scratch copy). It is not recreated from memory here. This file writes the netting from the return rows themselves (sale_returns.lines),
-- dated the way the other reports date a return: the day it was made (Asia/Dhaka), counted in that period and in the location of the return.
-- Switch biz_items_net_returns (default OFF). OFF = the report is exactly as before (sales only, returns not taken off).
-- The audit's other profit gaps (unknown cost shown as 100% margin, wastage and card fees, payroll double count, date cut-off for shared costs) are NOT changed here.
-- They are listed in docs/PLAN_NEXT.md with the decision for each.

do $g$ begin
  if to_regclass('public.sale_returns') is null then raise exception 'phase502 needs the sale returns table'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('biz_items_net_returns', 'reports',
     'আইটেম বিশ্লেষণে বিক্রি-ফেরত বাদ / Item analysis takes sale returns off: on', 'আইটেম বিশ্লেষণে বিক্রি-ফেরত বাদ / Item analysis takes sale returns off: on', 'Item analysis takes sale returns off: on', 'OFF = the item analysis shows sales before returns (today). ON = the returns of the period are taken off, the same as the returns line of the other reports.', 'OFF = the item analysis shows sales before returns (today). ON = the returns of the period are taken off, the same as the returns line of the other reports.', 5011)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

create or replace function public.biz_items(p_from date, p_to date, p_loc integer default null::integer)
returns table(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
language plpgsql stable security definer set search_path = public as $function$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  -- phase 502: the returns of the period, taken off (negative lines); nothing when the switch is off
  rt as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then -(e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then -round((e->>'amount')::numeric, 2) end amt
    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc) c /* bos402 */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$;

revoke all on function public.biz_items(date, date, integer) from public, anon;
grant execute on function public.biz_items(date, date, integer) to authenticated;

-- ---------------------------------------------------------------- phase503.sql
-- Phase 503 (SW-4) - SWEETS CUSTOMER DUES: an advance that was applied to a sale reduces the customer's due.
-- Paste AFTER phase502. Paste-twice safe (on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A4 (cash and accounting) and finding F-17: "customer dues list can fail to net an applied advance:
-- the test showed debt listed after the advance cleared it, and collecting against that visible due could clear the receivable twice".
-- Reproduced on a local throwaway database (before this file): a 500 credit sale, a 300 advance received, the 300 applied (cash move cust_advance_used):
-- customer_dues still shows 500; customer_advances correctly shows 0. The known gap is also written in the header of phase 447.
-- Switch dues_net_advance_on (default OFF). OFF = customer_dues exactly as before. ON = the applied advances of the customer are taken off the due.
-- Not changed here (listed in docs/PLAN_NEXT.md): customer_ledger does not net applied advances either; the card settlement, over-settlement and
-- settled-card void items of the audit are not in this branch (no card settlement code exists here), so they are not touched.

do $g$ begin
  if to_regclass('public.cash_moves') is null or to_regclass('public.sale_payments') is null then raise exception 'phase503 needs the cash moves and sale payments'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('dues_net_advance_on', 'pos',
     'গ্রাহকের বকেয়া থেকে জমা (advance) বাদ / Customer due takes off applied advances: on', 'গ্রাহকের বকেয়া থেকে জমা (advance) বাদ / Customer due takes off applied advances: on', 'Customer due takes off applied advances: on', 'OFF = the due still shows a sale whose advance was applied (today). ON = the applied advance reduces the due of the customer.', 'OFF = the due still shows a sale whose advance was applied (today). ON = the applied advance reduces the due of the customer.', 5021)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

-- customer_dues: the definition as it stands before this file, plus the applied advances (one union line; nothing when the switch is off)
CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)
  from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$;

-- ---------------------------------------------------------------- phase504.sql
-- Phase 504 (SW-6) - SWEETS RECIPES: a made product can be an ingredient of another recipe (two-stage production), behind a switch.
-- Paste AFTER phase503. Paste-twice safe (on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, A1 (manufacturing cost): "semi-finished item cannot be a recipe ingredient (e.g. chhana used to make
-- sweets; dough used to make another product). The recorded recipe validator accepts only certain ingredient types."
-- This branch has no separate "semi-finished" item type. The item types here are: raw_material, packaging, resale, finished_good, controlled, consumable,
-- asset, infrastructure. A made intermediate (chhana, dough) is therefore a finished_good item made by its own recipe. The validator refused it.
-- Reproduced on a local throwaway database (before this file): recipe_save with a finished_good ingredient -> bad_ingredient_type.
-- Change, switch recipe_intermediate_on (default OFF; OFF = the validator refuses as before):
--   ON: a finished_good may be an ingredient. A loop is refused (recipe_loop): an ingredient whose active recipe leads back to the product.
--   Production of the product consumes the intermediate's stock at its weighted average cost (production_post is not changed; it already takes any ingredient).
--   Cost: the intermediate's cost comes from its own last production. If it has no cost yet, the usual cost warning (production_requires_cost) applies.
-- Not changed here (docs/PLAN_NEXT.md): late cost pools not repriced, pool bills without an expense, overhead true-up as a report only, actual-yield variance,
-- packaging on actual yield, and recipe_approval_required (its default 'off' is an owner decision).

do $g$ begin
  if to_regclass('public.recipes') is null or to_regclass('public.recipe_lines') is null then raise exception 'phase504 needs the recipe tables'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('recipe_intermediate_on', 'items',
     'তৈরি পণ্য অন্য রেসিপিতে উপাদান / A made product can be an ingredient of another recipe: on', 'তৈরি পণ্য অন্য রেসিপিতে উপাদান / A made product can be an ingredient of another recipe: on', 'A made product can be an ingredient of another recipe: on', 'OFF = only raw material, packaging and resale items can be ingredients (today). ON = a made product (chhana, dough) can be an ingredient; a loop is refused.', 'OFF = only raw material, packaging and resale items can be ingredients (today). ON = a made product (chhana, dough) can be an ingredient; a loop is refused.', 5031)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

-- is the product reachable from p_from through active recipes (the loop test)? Stops at a loop (union).
create or replace function public._recipe_reaches(p_from uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive walk(item) as (
    select p_from
    union
    select l.ingredient_item_id from walk w
      join public.recipes r on r.item_id = w.item and r.active
      join public.recipe_lines l on l.recipe_id = r.id and l.active
  )
  select exists (select 1 from walk where item = p_target);
$$;
revoke all on function public._recipe_reaches(uuid, uuid) from public, anon;

-- the recipe ingredient validator: as before, plus the switch for made products and the loop test
CREATE OR REPLACE FUNCTION public._recipe_lines_ok(p_item uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- phase 504: a made product (finished good) may be an ingredient only when recipe_intermediate_on is on, and never in a loop
      if not (ing.item_type = 'finished_good' and public.rule_on('recipe_intermediate_on')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;
    end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$;

-- ---------------------------------------------------------------- phase505.sql
-- Phase 505 (SW-7) - SWEETS STOCK TRACKING: the mapping tool (item type to tracked yes/no). Nothing is flipped by this file.
-- Paste AFTER phase504. Paste-twice safe (create table if not exists, on conflict do nothing, create or replace). Earlier phase files are not edited.
-- Source: the owner's read-only audit of 19 Oct 2026, F-10: "all 1,369 items have tracked = false ... do not simply flip tracked=true on all rows; use a
-- reviewed mapping by item type". The plan itself is docs/STOCK_TRACKING_POLICY.md.
-- What this file adds:
--   stock_tracking_map   one row per item type: the PROPOSED tracked value and the reason. Proposals only. Reviewed by the owner (reviewed_by / reviewed_at).
--   stock_tracking_plan()          read-only, owner only: per type, the items in the database, how many are tracked now, the proposal, and how many differ.
--   stock_tracking_review(type, note)   owner only: records that the owner reviewed the proposal for that type (note required).
--   stock_tracking_apply(type, dry_run) owner only. dry_run (default true) only counts. A real run needs the switch tracking_map_apply_on = true AND a
--                                  review for that type. It sets items.tracked to the proposal for that type only, and only for items that differ.
-- The switch tracking_map_apply_on defaults OFF. With it OFF nothing can change any item. Opening stock must be counted before an item is tracked
-- (the owner's count, through the existing opening stock flow); this file does not create stock.

do $g$ begin
  if to_regclass('public.items') is null or to_regclass('public.item_types') is null then raise exception 'phase505 needs the items and item types'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort)
select v.key, v.module, 'switch', 'false'::jsonb, null, null, null, null, v.lab_bn, v.lab_mix, v.lab_en, v.hint_bn, v.hint_en, v.srt
  from (values
    ('tracking_map_apply_on', 'stock',
     'স্টক ট্র্যাকিং মানচিত্র প্রয়োগ / Apply the reviewed stock tracking map: on', 'স্টক ট্র্যাকিং মানচিত্র প্রয়োগ / Apply the reviewed stock tracking map: on', 'Apply the reviewed stock tracking map: on', 'OFF = the map can be read and reviewed, nothing changes. ON = the owner can apply the reviewed map to items of one type at a time.', 'OFF = the map can be read and reviewed, nothing changes. ON = the owner can apply the reviewed map to items of one type at a time.', 5041)
  ) as v(key, module, lab_bn, lab_mix, lab_en, hint_bn, hint_en, srt)
on conflict (key) do nothing;

create table if not exists public.stock_tracking_map (
  item_type text primary key references public.item_types(code),
  proposed_tracked boolean not null,
  reason_en text not null,
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  updated_at timestamptz not null default now()
);
alter table public.stock_tracking_map enable row level security;
revoke all on public.stock_tracking_map from anon, authenticated;

-- the proposals (from the item dictionary's control classes; the live counts are the owner's to check with stock_tracking_plan)
insert into public.stock_tracking_map (item_type, proposed_tracked, reason_en) values
  ('finished_good', true,  'Made and sold goods: stock must be known for sale, production and waste. Count the opening stock first.'),
  ('resale',        true,  'Bought and resold goods (drinks, direct-sale items): stock and cost are needed for the sale.'),
  ('raw_material',  true,  'Ingredients used by production: their stock is consumed by the recipe.'),
  ('packaging',     true,  'Boxes and bags used per cake or sweet: consumed by production and sales.'),
  ('consumable',    false, 'Cleaning and small supplies: expensed on purchase. Track only if the owner asks for it.'),
  ('controlled',    false, 'Controlled tools: the existing rule tools_stock_on decides; not changed by this map.'),
  ('asset',         false, 'Fixed machines and furniture: a register, never a stock item.'),
  ('infrastructure', false, 'Building and utility materials: not a stock item.')
on conflict (item_type) do nothing;

-- read-only plan (owner only)
create or replace function public.stock_tracking_plan()
returns table (item_type text, items_total bigint, tracked_now bigint, proposed_tracked boolean, reviewed_at timestamptz, items_differ bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query
    select m.item_type, count(i.id), count(i.id) filter (where i.tracked), m.proposed_tracked, m.reviewed_at,
           count(i.id) filter (where coalesce(i.tracked, false) <> m.proposed_tracked)
    from public.stock_tracking_map m left join public.items i on i.item_type = m.item_type
    group by m.item_type, m.proposed_tracked, m.reviewed_at
    union all      -- items with no type cannot be mapped until they are classified
    select '(not classified)'::text, count(*), count(*) filter (where x.tracked), null::boolean, null::timestamptz, 0::bigint
    from public.items x where x.item_type is null
    order by 1;
end $$;

-- the owner's review of one type's proposal (the note is required)
create or replace function public.stock_tracking_review(p_item_type text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_required'; end if;
  update public.stock_tracking_map set reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(btrim(p_note), 300), updated_at = now()
    where item_type = p_item_type;
  if not found then raise exception 'type_not_in_map'; end if;
  return jsonb_build_object('item_type', p_item_type, 'reviewed', true);
end $$;

-- apply the reviewed proposal to one type. dry run counts only.
create or replace function public.stock_tracking_apply(p_item_type text, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m public.stock_tracking_map; n bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into m from public.stock_tracking_map where item_type = p_item_type;
  if not found then raise exception 'type_not_in_map'; end if;
  if coalesce(p_dry_run, true) then
    select count(*) into n from public.items where item_type = p_item_type and coalesce(tracked, false) <> m.proposed_tracked;
    return jsonb_build_object('item_type', p_item_type, 'dry_run', true, 'would_change', n, 'to', m.proposed_tracked, 'reviewed', m.reviewed_at is not null);
  end if;
  if not public.rule_on('tracking_map_apply_on') then raise exception 'tracking_map_apply_off'; end if;
  if m.reviewed_at is null then raise exception 'not_reviewed'; end if;
  update public.items set tracked = m.proposed_tracked where item_type = p_item_type and coalesce(tracked, false) <> m.proposed_tracked;
  get diagnostics n = row_count;
  return jsonb_build_object('item_type', p_item_type, 'dry_run', false, 'changed', n, 'to', m.proposed_tracked);
end $$;

revoke all on function public.stock_tracking_plan() from public, anon;
revoke all on function public.stock_tracking_review(text, text) from public, anon;
revoke all on function public.stock_tracking_apply(text, boolean) from public, anon;
grant execute on function public.stock_tracking_plan() to authenticated;
grant execute on function public.stock_tracking_review(text, text) to authenticated;
grant execute on function public.stock_tracking_apply(text, boolean) to authenticated;

-- ---------------------------------------------------------------- phase529.sql
-- Phase 529 (UNION-1) - what our line's phases 80 to 505 need from the database before they can be pasted on top of the advanced block. Paste-twice safe. Earlier phase files are not edited.
-- Place in the paste order: after the advanced block (phase 135), before phase 80 (tests/sql/ORDER.txt, docs/PASTE_ORDER.md).
-- Two shared functions were changed by the advanced line in a way that stops our line's exact-text hooks and guards:
--   1. lock_check(date): advanced phase113 (bos113) added the owner mode `period_lock_owner_mode`; our phases 87/89/99/477 hook the phase 6 text
--      `if p_date is null or public.is_owner() then return; end if;` and stop with "phase89 patch site not found in lock_check(date)".
--      Only when the body carries bos113 and none of our tags (bos87, bos89), the body is saved in public._union_fn_backup and the phase 6 text is put back.
--      Phase 530 (paste after phase 505) puts the bos113 owner mode back on top of the hooked body. Nothing of bos113 is lost.
--   2. acct_journal_post: the advanced phase511 replaced the 7-argument function by an 8-argument one (extra p_reason, bos85 manual journal guard). Our phases 88/94/99 need
--      the 7-argument function (guard in phase88, text hook of phase99). A call with up to 7 arguments would also be ambiguous while both exist, because p_reason has a default.
--      This file (a) re-creates the 7-argument function from the phase 40 text when it is missing and (b) re-creates the 8-argument one WITHOUT any parameter default, so a call
--      with up to 7 arguments always means the 7-argument function and a call with all 8 arguments always means the 8-argument one. Phase 530 adds the bos85 guard to the 7-argument function
--      and our journal gate to the 8-argument one, so both behave the same.
-- A body that already carries our hooks is never replaced by this file.

create table if not exists public._union_fn_backup (
  id bigserial primary key,
  fn text not null,
  saved_at timestamptz not null default now(),
  why text,
  def text not null
);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

-- 1. lock_check
do $u529$
declare d text;
begin
  if to_regprocedure('public.lock_check(date)') is null then
    raise exception 'phase529 needs lock_check(date) (phase 6)';
  end if;
  d := pg_get_functiondef('public.lock_check(date)'::regprocedure);
  if position('bos113' in d) > 0 and position('bos87' in d) = 0 and position('bos89' in d) = 0 then
    insert into public._union_fn_backup (fn, why, def) values ('public.lock_check(date)', 'phase529: body with the bos113 owner mode, replaced by the phase 6 text so the hooks of phases 87/89 can be applied; phase530 restores bos113', d);
    execute $f$
CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $b$

$f$;
    revoke all on function public.lock_check(date) from public, anon, authenticated;
  end if;
end $u529$;

-- 2. acct_journal_post: one 7-argument function (hooked by our line) and one 8-argument function (p_reason without default)
do $u529b$
declare d8 text;
begin
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null then
    execute $f$
CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $b$
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
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $b$

$f$;
    revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) from public, anon;
    grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean) to authenticated;
  end if;
  if to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null then
    d8 := pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'::regprocedure);
    if position(' DEFAULT ' in substr(d8, 1, position(E'\n' in d8))) > 0 then
      insert into public._union_fn_backup (fn, why, def) values ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'phase529: the 8-argument function had defaults, so a call with up to 7 arguments was ambiguous; the defaults are removed (a call with 8 arguments means this function)', d8);
      drop function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text);
      execute regexp_replace(substr(d8, 1, position(E'\n' in d8) - 1), ' DEFAULT [A-Za-z0-9_:]+', '', 'g') || substr(d8, position(E'\n' in d8));
      revoke all on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) from public, anon;
      grant execute on function public.acct_journal_post(date, integer, text, jsonb, uuid, text, boolean, text) to authenticated;
    end if;
  end if;
end $u529b$;

-- _cust_bal(uuid): the advanced body (md5 ed80bafae0dc2eeba6382ebc284bbede) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public._cust_bal(uuid)') is null then raise exception 'phase529: public._cust_bal(uuid) is missing'; end if;
  d := pg_get_functiondef('public._cust_bal(uuid)'::regprocedure);
  if md5(d) = 'ed80bafae0dc2eeba6382ebc284bbede' then
    insert into public._union_fn_backup (fn, why, def) values ('public._cust_bal(uuid)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public._cust_bal(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$function$
$b$;
  end if;
end $u529c$;

-- customer_dues(): the advanced body (md5 14bce6b96ca918b1fb7f9aa72dcd08f5) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.customer_dues()') is null then raise exception 'phase529: public.customer_dues() is missing'; end if;
  d := pg_get_functiondef('public.customer_dues()'::regprocedure);
  if md5(d) = '14bce6b96ca918b1fb7f9aa72dcd08f5' then
    insert into public._union_fn_backup (fn, why, def) values ('public.customer_dues()', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$
$b$;
  end if;
end $u529c$;

-- rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean): the advanced body (md5 803786a2870251caf1679492765cea9b) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)') is null then raise exception 'phase529: public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean) is missing'; end if;
  d := pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure);
  if md5(d) = '803786a2870251caf1679492765cea9b' then
    insert into public._union_fn_backup (fn, why, def) values ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$
$b$;
  end if;
end $u529c$;

-- biz_items(date,date,integer): the advanced body (md5 505a50e08115e25ad02335b958568ee8) is saved and the base body (phases 4-79) is put back so the hooks of our packages find their text
do $u529c$
declare d text;
begin
  if to_regprocedure('public.biz_items(date,date,integer)') is null then raise exception 'phase529: public.biz_items(date,date,integer) is missing'; end if;
  d := pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure);
  if md5(d) = '505a50e08115e25ad02335b958568ee8' then
    insert into public._union_fn_backup (fn, why, def) values ('public.biz_items(date,date,integer)', 'phase529: advanced body replaced by the base body so the hooks of our line can be applied; phase 530+ puts the advanced logic back', d);
    execute $b$CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$
$b$;
  end if;
end $u529c$;

-- ---------------------------------------------------------------- phase530.sql
-- Phase 530 (UNION-2: lock_check keeps the owner mode of the advanced line (bos113) on top of our hooks (bos87, bos89)). Paste-twice safe. Earlier phase files are not edited.
-- What: lock_check(date) gets the bos113 owner mode back. The advanced line wrote it in phase113 (rule period_lock_owner_mode = off | warn: with warn the owner may still change a closed
--   period, as before, but a yellow exception `closed_period_owner` is written, once a day per date). Our hooks (bos87 one-off exception, bos89 period integrity with the owner mode
--   owner_closed_period_mode off | log | reason) stay exactly as they are; the bos113 block runs only after our check allowed the date. Both rules default to off, so nothing changes until the owner chooses.
-- Why a separate file: phase529 had to put the phase 6 text back so that our hooks (exact text) could be applied; this file puts bos113 on top of the hooked body.
-- How it works (all UNION files 530 to 539 do the same): each function is looked at first. If it already has the merged text: nothing. If it has a KNOWN older text (the text our chain or the advanced
--   chain or the earlier live paste produced, by md5): it is replaced by the merged text and the old text is saved in public._union_fn_backup. If it has an unknown text: the patch sites of the
--   fallback are looked for; if they are not all there, ALL such functions are listed in ONE message and nothing is changed.
-- Paste AFTER phase529 and after phase 505 (end of the chain). Safe to paste twice, safe to paste again after an old phase was pasted again.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- lock_check(date)
insert into _u_plan (fn, kind, a, b) values
  ('public.lock_check(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then   -- bos89: pure date test, owner mode, override windows
    if public.is_owner() and coalesce(public.rule_txt('period_lock_owner_mode'), 'off') = 'warn' then   -- bos113: warn = the owner may still change a closed period but it is written down as a yellow exception
      v := public.rule_txt('period_closed_until');
      if v is not null and v ~ '^\d{4}-\d{2}-\d{2}$' then
        begin d := v::date; exception when others then d := null; end;
        if d is not null and p_date <= d
           and not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
          perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
            'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
        end if;
      end if;
    end if;
    return;
  end if;
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  if public._m_lock_exc(p_date) then return; end if;   -- bos87: an owner granted one-off exception (reason on record, shown in the Exceptions list)
  raise exception 'period_closed';
end $function$$r0_0$, null),
  ('public.lock_check(date)', 'known', '7627a1d055031d926293f90fbf2570ee', null),
  ('public.lock_check(date)', 'known', '78b7ce236462f7e613a1ee22870eb31f', null),
  ('public.lock_check(date)', 'known', 'e2722a7e428097f826c9c321ea568d44', null),
  ('public.lock_check(date)', 'old', $o0_0$AS $function$
declare v text; d date;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$o0_0$, $n0_0$AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then   -- bos89: pure date test, owner mode, override windows
    if public.is_owner() and coalesce(public.rule_txt('period_lock_owner_mode'), 'off') = 'warn' then   -- bos113: warn = the owner may still change a closed period but it is written down as a yellow exception
      v := public.rule_txt('period_closed_until');
      if v is not null and v ~ '^\d{4}-\d{2}-\d{2}$' then
        begin d := v::date; exception when others then d := null; end;
        if d is not null and p_date <= d
           and not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
          perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
            'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
        end if;
      end if;
    end if;
    return;
  end if;
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$n0_0$);
do $u530$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase530: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase530: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase530: % function(s) changed', nfix;
end $u530$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase531.sql
-- Phase 531 (UNION-3: biz_items and rpt_agg_sql keep the advanced cost source and returns netting (bos112, bos110) and our cost basis (bos402) and returns switch (phase 502)). Paste-twice safe. Earlier phase files are not edited.
-- What: biz_items(date,date,integer): the returns netting of the advanced line (rule items_net_of_returns, bos112, uses the margin report's own lines) is the one that counts; our phase 502
--   netting (rule biz_items_net_returns) is kept but does nothing while the advanced one is on, so a return is never taken off twice. Our cost basis hook (bos402, rule reports_cost_basis =
--   ledger_first) stays; the default basis is the advanced ONE report cost source (bos88). rpt_agg_sql: the advanced set-based cost join (bos110) is used, except when reports_cost_basis =
--   ledger_first (bos402), which keeps our join. Every rule defaults as before; with all rules at their defaults both functions return what the advanced line returned.
-- Paste AFTER phase530 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- biz_items(date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.biz_items(date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric, cogs numeric, share_pct numeric, cum_pct numeric, abc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[]; nr boolean := coalesce(public.rule_txt('items_net_of_returns'), 'off') = 'on';   -- bos88; bos112: returns netted when the rule is on
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ln as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) end amt
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  -- phase 502: the returns of the period, taken off (negative lines); nothing when the switch is off
  rt as (
    select case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then -(e->>'qty')::numeric end qty,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then -round((e->>'amount')::numeric, 2) end amt
    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and not nr and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  rtn as (   -- bos112: what came back (revenue with its discount share, quantity), from the same lines the margin report reads
    select h.item_id iid, sum(h.qty) q, round(sum(h.rev), 2) r from public._cogs_lines72(p_from, p_to, locs) h where nr and h.src = 'return' and h.item_id is not null group by 1),
  by_item as (select coalesce(a.iid, b.iid) iid, coalesce(a.q, 0) - coalesce(b.q, 0) q, coalesce(a.r, 0) - coalesce(b.r, 0) r from by_item0 a full join rtn b on b.iid = a.iid),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as c, sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as u   -- bos112: returns subtracted (only present when the rule is on)
      from public._cogs_lines72(p_from, p_to, locs) h where (h.src = 'sale' or nr) and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc where public._rptb1_cost_basis() = 'ledger_first') c /* bos402: cost basis ledger_first (rule reports_cost_basis), off by default */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$$r0_0$, null),
  ('public.biz_items(date,date,integer)', 'known', '05fcc50a4a496359af35a0a47ec8ad3f', null),
  ('public.biz_items(date,date,integer)', 'known', '2c0360a871e57cde9d3a7a439d493edc', null),
  ('public.biz_items(date,date,integer)', 'known', '57a0d3939bb344bd291e814966dc62d3', null),
  ('public.biz_items(date,date,integer)', 'known', 'afbe85dd4dbcf5b54944ebeab60f3354', null),
  ('public.biz_items(date,date,integer)', 'old', $o0_0$AS $function$
declare cost_ok boolean := public.biz_cost_ok();
begin$o0_0$, $n0_0$AS $function$
declare cost_ok boolean := public.biz_cost_ok(); locs int[]; nr boolean := coalesce(public.rule_txt('items_net_of_returns'), 'off') = 'on';   -- bos88; bos112: returns netted when the rule is on
begin$n0_0$),
  ('public.biz_items(date,date,integer)', 'old', $o1_0$  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query$o1_0$, $n1_0$  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));   -- bos88
  return query$n1_0$),
  ('public.biz_items(date,date,integer)', 'old', $o2_0$    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc) c /* bos402 */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),$o2_0$, $n2_0$    from public.sale_returns sr, jsonb_array_elements(case when jsonb_typeof(sr.lines) = 'array' then sr.lines else '[]'::jsonb end) e
    where public.rule_on('biz_items_net_returns') and not nr and sr.status = 'done'
      and (sr.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
      and (p_loc is null or sr.location_id = p_loc) and sr.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from (select * from ln union all select * from rt) l where l.iid is not null group by 1),
  rtn as (   -- bos112: what came back (revenue with its discount share, quantity), from the same lines the margin report reads
    select h.item_id iid, sum(h.qty) q, round(sum(h.rev), 2) r from public._cogs_lines72(p_from, p_to, locs) h where nr and h.src = 'return' and h.item_id is not null group by 1),
  by_item as (select coalesce(a.iid, b.iid) iid, coalesce(a.q, 0) - coalesce(b.q, 0) q, coalesce(a.r, 0) - coalesce(b.r, 0) r from by_item0 a full join rtn b on b.iid = a.iid),
  tot as (select coalesce(sum(r), 0) t from by_item),
  cg as (   -- bos14: the count_in_business filter on the typed cost now lives in _cogs_lines72 (cst) and _line_cost88 ; bos88: cost of what was sold from the ONE report source (switch report_cost_source); NULL = some quantity has no known cost (never a silent 0)
    select h.item_id as iid, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as c, sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as u   -- bos112: returns subtracted (only present when the rule is on)
      from public._cogs_lines72(p_from, p_to, locs) h where (h.src = 'sale' or nr) and h.item_id is not null group by 1),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when not cost_ok then null
                when b.iid is null then (case when exists (select 1 from public._item_cost_eff88() e where e.item_id = i.id) then 0 end)
                when coalesce(g.u, 0) > 0.004 then null
                else g.c end cg
    from public.items i
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id left join (select bc.item_id, bc.cost_price from public._rptb1_biz_item_cost(p_from, p_to, p_loc) bc where public._rptb1_cost_basis() = 'ledger_first') c /* bos402: cost basis ledger_first (rule reports_cost_basis), off by default */ on c.item_id = i.id
    where (i.is_active and i.sellable) or b.iid is not null),$n2_0$),
  ('public.biz_items(date,date,integer)', 'old', $o3_0$    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end$o3_0$, $n3_0$    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end$n3_0$);
-- rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
  m text; keyq text; costq text; costj text := '';
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  if p_withcost and public._rptb1_cost_basis() = 'ledger_first' then
    costj := ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no';      /* bos402: ledger cost first */
  elsif p_withcost then
    -- bos110: the cost of every (sale, item) pair of the report is computed ONCE, set-based, instead of calling _line_cost88() for every fact row. Same rules, same answer per pair:
    --   ledger cost of the sale's own stock rows when all of them carry a cost (not in item_costs mode), else the list cost (not in ledger_avg mode), else null.
    m := public._rcs88();
    keyq := 'select distinct ' || p_al || '.sale_id as sale_id, ' || p_al || '.item_id as item_id from ' || p_rel || ' ' || p_al || ' where ' || p_where || ' and ' || p_al || '.item_id is not null';
    if m = 'item_costs' then
      costq := format($c$with k as (%s)
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id, ic.cost_price as cost_price
          from k left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id$c$, keyq);
    else
      costq := format($c$with k as materialized (%s),
        g as (select k.sale_id, k.item_id, count(*) as n, bool_and(coalesce(l.unit_cost, 0) > 0) as allc,
                     coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0) as lc, coalesce(sum(-l.qty_delta), 0) as lq
                from k join public.stock_ledger l on l.ref_id = k.sale_id::text and l.item_id = k.item_id
               where l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') group by k.sale_id, k.item_id),
        q as (select s.id as sale_id, e->>'item_id' as iid, coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as q
                from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
               where s.id in (select g.sale_id from g where g.n > 0 and g.allc and g.lq > 0) group by s.id, e->>'item_id')
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id,
               case when g.n > 0 and g.allc and g.lq > 0 then g.lc / coalesce(nullif(coalesce(q.q, 0), 0), g.lq) else %s end as cost_price
          from k left join g on g.sale_id = k.sale_id and g.item_id = k.item_id
               left join q on q.sale_id = g.sale_id and q.iid = g.item_id::text
               %s$c$, keyq,
        case when m = 'ledger_avg' then 'null::numeric' else 'ic.cost_price' end,
        case when m = 'ledger_avg' then '' else 'left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id' end);
    end if;
    costj := ' left join (' || costq || ') c on c.sk = coalesce(' || p_al || '.sale_id, ''00000000-0000-0000-0000-000000000000''::uuid) and c.item_id = ' || p_al || '.item_id /* bos14 count_in_business filter; bos88: one cost source, see report_cost_source; bos110: set-based */';
  end if;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al || costj
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $function$$r0_0$, null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '06b6da348b8ac5840947802fcf9449a5', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '3ec2d9cb01bd8522fb9d64335a4f4de9', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'known', '9f8766108c4745cfe438b6fc5da6f74d', null),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'old', $o0_0$declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin$o0_0$, $n0_0$declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
  m text; keyq text; costq text; costj text := '';
begin$n0_0$),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'old', $o1_0$  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then case when public._rptb1_cost_basis() = 'ledger_first' then ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no'      /* bos402: ledger cost first */
            else ' left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = ' || p_al || '.item_id' end else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');$o1_0$, $n1_0$  end loop;
  if p_withcost and public._rptb1_cost_basis() = 'ledger_first' then
    costj := ' left join public.rpt_line_cost c on c.sale_id = ' || p_al || '.sale_id and c.line_no = ' || p_al || '.line_no';      /* bos402: ledger cost first */
  elsif p_withcost then
    -- bos110: the cost of every (sale, item) pair of the report is computed ONCE, set-based, instead of calling _line_cost88() for every fact row. Same rules, same answer per pair:
    --   ledger cost of the sale's own stock rows when all of them carry a cost (not in item_costs mode), else the list cost (not in ledger_avg mode), else null.
    m := public._rcs88();
    keyq := 'select distinct ' || p_al || '.sale_id as sale_id, ' || p_al || '.item_id as item_id from ' || p_rel || ' ' || p_al || ' where ' || p_where || ' and ' || p_al || '.item_id is not null';
    if m = 'item_costs' then
      costq := format($c$with k as (%s)
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id, ic.cost_price as cost_price
          from k left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id$c$, keyq);
    else
      costq := format($c$with k as materialized (%s),
        g as (select k.sale_id, k.item_id, count(*) as n, bool_and(coalesce(l.unit_cost, 0) > 0) as allc,
                     coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0) as lc, coalesce(sum(-l.qty_delta), 0) as lq
                from k join public.stock_ledger l on l.ref_id = k.sale_id::text and l.item_id = k.item_id
               where l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') group by k.sale_id, k.item_id),
        q as (select s.id as sale_id, e->>'item_id' as iid, coalesce(sum(case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end), 0) as q
                from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
               where s.id in (select g.sale_id from g where g.n > 0 and g.allc and g.lq > 0) group by s.id, e->>'item_id')
        select coalesce(k.sale_id, '00000000-0000-0000-0000-000000000000'::uuid) as sk, k.item_id as item_id,
               case when g.n > 0 and g.allc and g.lq > 0 then g.lc / coalesce(nullif(coalesce(q.q, 0), 0), g.lq) else %s end as cost_price
          from k left join g on g.sale_id = k.sale_id and g.item_id = k.item_id
               left join q on q.sale_id = g.sale_id and q.iid = g.item_id::text
               %s$c$, keyq,
        case when m = 'ledger_avg' then 'null::numeric' else 'ic.cost_price' end,
        case when m = 'ledger_avg' then '' else 'left join (select x.item_id, x.cost_price from public.item_costs x join public.items i on i.id = x.item_id where i.count_in_business) ic on ic.item_id = k.item_id' end);
    end if;
    costj := ' left join (' || costq || ') c on c.sk = coalesce(' || p_al || '.sale_id, ''00000000-0000-0000-0000-000000000000''::uuid) and c.item_id = ' || p_al || '.item_id /* bos14 count_in_business filter; bos88: one cost source, see report_cost_source; bos110: set-based */';
  end if;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al || costj
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');$n1_0$);
do $u531$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase531: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase531: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase531: % function(s) changed', nfix;
end $u531$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase532.sql
-- Phase 532 (UNION-4: customer balance, dues, books documents, day book and profit reports carry both lines). Paste-twice safe. Earlier phase files are not edited.
-- What: _cust_bal and customer_dues: opening dues of the open parties package (bos88) and the business scope of the advanced line (scope133, phase 123 org_scope_on) and the customer
--   mobile mask (bos105); customer_dues also keeps our "net of the advance used" clause (phase 503, rule dues_net_advance_on, superseded by the advanced customer_dues_net113 but kept, OFF).
--   _acct_docs: the sources of our phases 81-83, 87, 96 AND the advanced inline sources (stock moves, transit loss, purchase variance, card settlement, landed cost, drawer cash short, bos113).
--   _daybook_lines: money account of an expense voucher (bos87) or its pay mode (bos113, rule daybook_align_mode) and the advanced card-fee and drawer rows.
--   _p27_pl: our payroll accrual and app payroll run (bos85/86/93) and the advanced labour already absorbed into product cost (bos117, rule factory_labour_absorbed117).
--   _r3q_l3_shop_pnl: our blank-profit rule (bos440) inside the advanced profit_truth_mode wrapper (bos112).
-- Every switch involved keeps its own default. Paste AFTER phase531 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _cust_bal(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._cust_bal(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cust_bal(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller's businesses (owner, server and the notify bot: all) */ 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))), 0);
$function$$r0_0$, null),
  ('public._cust_bal(uuid)', 'known', '316a2ab793e14c118f0cdd8f7dc24fe2', null),
  ('public._cust_bal(uuid)', 'known', '7233c24399dd3254a265c055fc170827', null),
  ('public._cust_bal(uuid)', 'known', 'b9ddd93fb0b5436b0d1ad8b46144e117', null),
  ('public._cust_bal(uuid)', 'old', $o0_0$AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$function$$o0_0$, $n0_0$AS $function$
  select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller's businesses (owner, server and the notify bot: all) */ 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))), 0);
$function$$n0_0$);
-- customer_dues()
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_dues()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_dues()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)
  from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$$r0_0$, null),
  ('public.customer_dues()', 'known', '37acd7f15fb9795a3af819ef50cfc2b4', null),
  ('public.customer_dues()', 'known', '6216d60b85dbb7168e9aa93272bd3873', null),
  ('public.customer_dues()', 'known', '842f16bd58318a3424c7f31defc95a5b', null),
  ('public.customer_dues()', 'known', 'a86ed505fbdcc4245cf4006feed04380', null),
  ('public.customer_dues()', 'old', $o0_0$           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)$o0_0$, $n0_0$           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null and (not (select public._org_on123()) or public.can_loc(x.location_id))),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(location_id))
          union all select customer_id, amount from public.cash_moves where kind = 'cust_advance_used' and status = 'done' and customer_id is not null and public.rule_on('dues_net_advance_on')) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),
         (case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)$n0_0$);
-- _acct_docs(date)
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_docs(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
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
        select 1 o, jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id
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
        union all select 3, jsonb_build_object('a', public._m_key(r.money_account_id, public._acct_paykey(coalesce(r.refund_mode, 'cash'))), 'c', r.refund_amount) /* bos87 */ where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from public._acct_inv_split72(array['sale_return'], r.id::text, array['sale_return'], 1) z where z.amt > 0 /* bos72 */
        union all select 5, jsonb_build_object('a', 'cogs', 'c', cg.amt) from (select round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null) cg where cg.amt > 0
      ) x) end
  from public.sale_returns r left join public.sales s on s.id = r.sale_id
  where (r.created_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('sale_return', r.id::text, r.status = 'done');

  -- customer collections (later payments of dues)
  return query
  select 'collection'::text, p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'Due collection'::text, null::text, not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),
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
      jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode, true)), 'c', p.amount) /* bos87 */) end
  from public.supplier_payments p
  where (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('supplier_payment', p.id::text, not p.voided);

  -- supplier refunds
  return query
  select 'supplier_refund'::text, f.id::text, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, 'Supplier refund'::text, null::text, not f.voided, public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(f.money_account_id, public._acct_paykey(f.mode, true)), 'd', f.amount) /* bos87 */,
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
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), public._acct_paykey(v.pm, true) /* bos85 */) /* bos87 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad
    from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x) v
  where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date >= p_start and public._acct_need('expense_voucher', e.id::text || ':' || coalesce(e.rev_no, 0)::text, v.total > 0);
  return query
  select 'expense_voucher'::text, je.source_id, je.entry_date, je.location_id, 'Expense voucher no longer approved'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'expense_voucher' and je.reverses_id is null
    and not exists (select 1 from public.entries e where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);

  -- bos50: quick expenses typed in the day-book tab: expense head debit, cash / bank / mobile credit
  return query
  select 'quick_expense'::text, q.id::text, q.exp_date, q.location_id, ('Quick expense: ' || q.head)::text, null::text, q.status = 'done', (q.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when q.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'exp_' || q.head) then 'exp_' || q.head else 'exp_other' end, 'd', q.amount),
      jsonb_build_object('a', public._m_key(q.money_account_id, public._acct_paykey(q.mode)), 'c', q.amount) /* bos87 */) end
  from public.quick_expenses q
  where q.exp_date >= p_start and public._acct_need('quick_expense', q.id::text, q.status = 'done');

  -- cash moves (bank deposit / withdraw, owner top-up / draw, customer advances, hub receipt)
  return query
  select 'cash_move'::text, public._acct_sid52('cash_move', m.id::text) /* bos52 */, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */, (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ then case m.kind
      when 'bank_deposit' then jsonb_build_array(jsonb_build_object('a', 'pay_bank', 'd', m.amount), jsonb_build_object('a', 'pay_cash', 'c', m.amount))
      when 'bank_withdraw' then jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'pay_bank', 'c', m.amount))
      when 'owner_topup' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'd', m.amount), jsonb_build_object('a', 'owner_capital', 'c', m.amount))
      when 'owner_draw' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', m.amount), jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'c', m.amount))
      when 'cust_advance' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'd', m.amount), jsonb_build_object('a', 'cust_advance', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'cust_advance_refund' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */, 'c', m.amount))
      when 'cust_advance_used' then jsonb_build_array(jsonb_build_object('a', 'cust_advance', 'd', m.amount, 'pt', 'customer', 'pid', m.customer_id::text), jsonb_build_object('a', 'receivable', 'c', m.amount, 'pt', 'customer', 'pid', m.customer_id::text))
      when 'hub_receipt' then jsonb_build_array(jsonb_build_object('a', public._m_key(m.money_account_id, 'pay_cash'), 'd', m.amount), jsonb_build_object('a', 'hub_clearing', 'c', m.amount))
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
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */, (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */ then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount /* bos85 */))
      || case when r.rec > 0 then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'c', r.rec, 'pt', 'staff', 'pid', p.employee_id::text)) else '[]'::jsonb end
    end
  from public.payroll_payments p
  cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                        from public.payroll_lines l where l.id = p.line_id) r
  where p.pay_date >= p_start
    and public._acct_need('payroll_payment', public._acct_sid52('payroll_payment', p.id::text), p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */);

  -- bos52: staff advances paid out of the business (cash / bank / mobile only; mode none = money not moved here, nothing posted). Dr staff advances, Cr cash / bank / mobile.
  return query
  select 'staff_advance'::text, a.id::text, a.adv_date, a.location_id, ('Staff advance ADV-' || a.id::text)::text, null::text,
    a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), (a.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') then
      jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', a.amount, 'pt', 'staff', 'pid', a.employee_id::text),
                        jsonb_build_object('a', public._m_key(a.money_account_id, public._acct_paykey(a.mode)), 'c', a.amount)) end
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
      when 'contribution' then jsonb_build_array(jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'd', c.amount), jsonb_build_object('a', 'owner_capital', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'return_of_capital' then jsonb_build_array(jsonb_build_object('a', 'owner_capital', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
      when 'loan_in' then jsonb_build_array(jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'd', c.amount), jsonb_build_object('a', 'partner_loan', 'c', c.amount, 'pt', 'partner', 'pid', c.party_id::text))
      when 'loan_repayment' then jsonb_build_array(jsonb_build_object('a', 'partner_loan', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
      when 'owner_drawing' then jsonb_build_array(jsonb_build_object('a', 'owner_drawings', 'd', c.amount, 'pt', 'partner', 'pid', c.party_id::text), jsonb_build_object('a', public._m_key(c.money_account_id, public._acct_paykey(c.mode)), 'c', c.amount))
    end end
  from public.partner_capital c
  left join lateral (select x.location_id as loc from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                      and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
  where c.cap_date >= p_start and public._acct_need('partner_capital', public._acct_sid52('partner_capital', c.id::text), c.status = 'posted' and not public._shadowed52('partner_capital', c.id::text));
  -- bos85: sources of phases 81, 82, 83 (cash short / transit short, salary accrual + partner settlement, mobile wallets)
  return query select * from public._b_docs(p_start); /* bos85 */
  return query select * from public._c_docs(p_start); /* bos85 */
  return query select * from public._d_acct_docs(p_start); /* bos85 */
  return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
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
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c
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

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);

  -- bos113: a drawer count difference reaches the books (rule drawer_short_post = on; default off = as before, the difference is only the yellow / red exception flag).
  --   Short (count < expected): Dr cash short / over (5800), Cr cash. Over: Dr cash, Cr 5800. One entry per final (submitted / approved) form 14-1 revision; a form that is no longer final is reversed by the second query.
  return query
  select 'cash_variance'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id,
    (case when k.diff < 0 then 'Cash short, drawer count ' else 'Cash over, drawer count ' end || e.entry_date::text)::text, null::text, true, null::date, null::text, null::text,
    case when k.diff < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', -k.diff), jsonb_build_object('a', 'pay_cash', 'c', -k.diff))
         else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', k.diff), jsonb_build_object('a', 'cash_short', 'c', k.diff)) end
  from public.entry_counts k join public.entries e on e.id = k.entry_id
  where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date >= p_start
    and coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on'
    and public._acct_need('cash_variance', e.id::text || ':' || coalesce(e.rev_no, 0)::text, true);
  return query
  select 'cash_variance'::text, je.source_id, je.entry_date, je.location_id, 'Drawer count no longer final'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'cash_variance' and je.reverses_id is null
    and not exists (select 1 from public.entry_counts k join public.entries e on e.id = k.entry_id
                     where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);
end $function$$r0_0$, null),
  ('public._acct_docs(date)', 'known', '5a0a9057b8c83c3ac7ae5b3b0d7efc09', null),
  ('public._acct_docs(date)', 'known', '92853940c471e24bd48b9b4f1b2ba32c', null),
  ('public._acct_docs(date)', 'known', '9b3e7e1c565114553cca06f6fe513eff', null),
  ('public._acct_docs(date)', 'old', $o0_0$AS $function$
begin$o0_0$, $n0_0$AS $function$
-- bos97: phase515 body + two landed-cost blocks at the end (landed_cost, landed_cost_void)
-- bos103: production run whose ingredients are all free-cost = known cost 0 (posts conversion only, or nothing when there is none); production-in without recipe via _acct_stock_moves85
-- bos98: merged by phase524 = phase515 body + every bos96 line (stock_ledger_eff96 reads) + both bos97 blocks, so neither phase522 nor phase523 can erase the other
-- bos89: merge of phase506 (free-cost) and phase511 (stock moves, card, voucher mode) bodies; every bos50/52/72/74/80/85 line kept
begin$n0_0$),
  ('public._acct_docs(date)', 'old', $o1_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,$o1_0$, $n1_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,$n1_0$),
  ('public._acct_docs(date)', 'old', $o2_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
    null::text,$o2_0$, $n2_0$                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0) and not public._cost_free80((e->>'item_id')::uuid)) then 'cogs_missing' end, /* bos72: cost 0 = unknown; bos80: free-cost item is a known cost */
    null::text,$n2_0$),
  ('public._acct_docs(date)', 'old', $o3_0$          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), 'pay_cash'), 'c', v.total) /* bos87 */
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad$o3_0$, $n3_0$          where public._acct_num(x->>'amount') > 0 group by 1) h
        union all select 2, jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), public._acct_paykey(v.pm, true) /* bos85 */) /* bos87 */, 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select case when e.data->>'pay_mode' in ('cash', 'bank', 'mobile', 'card') then e.data->>'pay_mode' else 'cash' end pm, /* bos85: how the voucher was paid; none = cash as before */
           coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
           count(*) filter (where coalesce(btrim(x->>'amount'), '') <> '' and public._acct_num(x->>'amount') is null) bad$n3_0$),
  ('public._acct_docs(date)', 'old', $o4_0$  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);$o4_0$, $n4_0$  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);$n4_0$),
  ('public._acct_docs(date)', 'old', $o5_0$  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)$o5_0$, $n5_0$  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done' and not c.zero103 /* bos103 */, (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) and not c.known103 /* bos103: every ingredient line is a real cost or a free-cost item */ then 'cost_missing' end,
    case when r.status = 'done' and (c.amt > 0 or (c.known103 and not c.zero103)) /* bos103 */ then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', coalesce(c.amt, 0) + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */ /* bos103 */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)$n5_0$),
  ('public._acct_docs(date)', 'old', $o6_0$  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
$o6_0$, $n6_0$  from public.production_runs r cross join lateral (
    select q.amt, q.nulls, (q.nulls = 0 and q.n > 0) as known103, (q.nulls = 0 and q.n > 0 and coalesce(q.amt, 0) <= 0 and round(coalesce(r.conversion_cost, 0), 2) < 0.005) as zero103 from (   /* bos103: known103 = no unknown cost; zero103 = known and nothing to book */
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */, count(*) n
    from public.stock_ledger_eff96 l /* bos96 */ where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') q) c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done' and not c.zero103 /* bos103 */);
$n6_0$),
  ('public._acct_docs(date)', 'old', $o7_0$  return query select * from public._w1f_docs(p_start); /* bos96: other income */
end $function$$o7_0$, $n7_0$  return query select * from public._w1f_docs(p_start); /* bos96: other income */

  -- bos85: stock movements that had no document: count adjustment, opening stock, own-use issue, location transfers (one entry per stock-ledger row, source_id = ledger id)
  return query
  select t.st, m.lid::text, m.d, m.loc,
    ((case m.cls when 'adjust' then 'Stock count adjustment' when 'opening' then 'Opening stock' when 'issue' then 'Stock issued for own use' when 'prodin' then 'Production-in without recipe' else 'Stock transfer' end) /* bos103 */ || case when m.rev then ' (reversal)' else '' end)::text,
    null::text, true, null::date, null::text, case when m.nocost then 'cost_missing' end,
    case when not m.nocost then jsonb_build_array(
      jsonb_build_object('a', case when m.qty < 0 then m.xkey else m.ikey end, 'd', m.amt),
      jsonb_build_object('a', case when m.qty < 0 then m.ikey else m.xkey end, 'c', m.amt)) end
  from public._acct_stock_moves85(p_start) m
  cross join lateral (select (case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening' when 'issue' then 'stock_issue' when 'prodin' then 'stock_prodin' else 'stock_transfer' end)::text st /* bos103 */) t
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
    from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c
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

  -- bos97: landed cost (freight, duty, insurance ... added to the item cost). One entry once it is posted: Dr inventory raw / pack / finished (the part still on the shelf),
  -- Dr landed_variance (the part already sold), Dr expense / vat_input (charges that are not capitalised); Cr landed_payable / cash / bank / mobile. Lines come from the append-only landed_cost_alloc rows.
  return query
  select 'landed_cost'::text, c.id::text, c.cost_date, c.location_id, ('Landed cost ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'post')
  from public.landed_costs c
  where c.status in ('posted', 'void') and c.posted_at is not null and c.cost_date >= p_start and public._acct_need('landed_cost', c.id::text, true);

  -- bos97: a voided landed cost has its own counter entry (the sold part is released from the variance account, only what is still on the shelf leaves the inventory account)
  return query
  select 'landed_cost_void'::text, c.id::text, (c.void_at at time zone 'Asia/Dhaka')::date, c.location_id, ('Landed cost void ' || coalesce(nullif(c.shipment_ref, ''), left(c.id::text, 8)))::text, null::text, true, null::date, null::text, null::text,
    public._landed_jlines97(c.id, 'void')
  from public.landed_costs c
  where c.status = 'void' and c.posted_at is not null and (c.void_at at time zone 'Asia/Dhaka')::date >= p_start
    and exists (select 1 from public.journal_entries e where e.source_type = 'landed_cost' and e.source_id = c.id::text and e.reverses_id is null)
    and public._acct_need('landed_cost_void', c.id::text, true);

  -- bos113: a drawer count difference reaches the books (rule drawer_short_post = on; default off = as before, the difference is only the yellow / red exception flag).
  --   Short (count < expected): Dr cash short / over (5800), Cr cash. Over: Dr cash, Cr 5800. One entry per final (submitted / approved) form 14-1 revision; a form that is no longer final is reversed by the second query.
  return query
  select 'cash_variance'::text, e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.entry_date, e.location_id,
    (case when k.diff < 0 then 'Cash short, drawer count ' else 'Cash over, drawer count ' end || e.entry_date::text)::text, null::text, true, null::date, null::text, null::text,
    case when k.diff < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', -k.diff), jsonb_build_object('a', 'pay_cash', 'c', -k.diff))
         else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', k.diff), jsonb_build_object('a', 'cash_short', 'c', k.diff)) end
  from public.entry_counts k join public.entries e on e.id = k.entry_id
  where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date >= p_start
    and coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on'
    and public._acct_need('cash_variance', e.id::text || ':' || coalesce(e.rev_no, 0)::text, true);
  return query
  select 'cash_variance'::text, je.source_id, je.entry_date, je.location_id, 'Drawer count no longer final'::text, null::text, false, public._acct_today(), null::text, null::text, null::jsonb
  from public.journal_entries je
  where je.source_type = 'cash_variance' and je.reverses_id is null
    and not exists (select 1 from public.entry_counts k join public.entries e on e.id = k.entry_id
                     where k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.id::text || ':' || coalesce(e.rev_no, 0)::text = je.source_id)
    and not exists (select 1 from public.journal_entries r where r.reverses_id = je.id);
end $function$$n7_0$);
-- _daybook_lines(integer[],integer[],date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._daybook_lines(integer[],integer[],date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, coalesce(public._m_name(sp.money_account_id), sp.wallet), sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end) /* bos87 bos113: the money account when one is chosen, else how the voucher was paid as the journal reads it (rule daybook_align_mode) */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'daybook') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to
  union all  -- bos85: mobile wallet fees (phase83)
  select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */
  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */
  union all
  -- bos113 (rule daybook_align_mode = on): the card fee kept back at the settlement leaves the bank side of the day book on the settlement day, as the journal posts it (5810)
  select c.location_id, c.settle_date, 'out'::text, 'bank'::text, 'card_settlement'::text, c.fee, null::text, 'card fee'::text, c.created_staff, c.created_at, 'card_settlement'::text, c.id::text, false, false
    from public.card_settlements85 c
   where coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' and c.status = 'done' and c.fee between 0.01 and 1000000000000 and c.location_id = any (p_locs) and c.settle_date between p_from and p_to
  union all
  -- bos113 (rule drawer_short_post = on): a final drawer count difference is a cash movement of the day (short = out, over = in)
  select e.location_id, e.entry_date, case when k.diff < 0 then 'out' else 'in' end, 'cash'::text, 'cash_variance'::text, abs(k.diff), '#' || e.serial::text, 'drawer count difference'::text, e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry'::text, e.id::text, false, false
    from public.entry_counts k join public.entries e on e.id = k.entry_id
   where coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on' and k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved')
     and e.location_id = any (p_locs) and e.entry_date between p_from and p_to;
$function$$r0_0$, null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', '323ad3de5d5a1ac6577bc678a4ec395d', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', '8c430ac963050c2ebd055483dd096355', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'known', 'a8f59470ceaf856cabd788e834f4a77f', null),
  ('public._daybook_lines(integer[],integer[],date,date)', 'old', $o0_0$  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), 'cash') /* bos87 */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false$o0_0$, $n0_0$  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end) /* bos87 bos113: the money account when one is chosen, else how the voucher was paid as the journal reads it (rule daybook_align_mode) */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false$n0_0$),
  ('public._daybook_lines(integer[],integer[],date,date)', 'old', $o1_0$  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;
$function$$o1_0$, $n1_0$  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */
  union all
  -- bos113 (rule daybook_align_mode = on): the card fee kept back at the settlement leaves the bank side of the day book on the settlement day, as the journal posts it (5810)
  select c.location_id, c.settle_date, 'out'::text, 'bank'::text, 'card_settlement'::text, c.fee, null::text, 'card fee'::text, c.created_staff, c.created_at, 'card_settlement'::text, c.id::text, false, false
    from public.card_settlements85 c
   where coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' and c.status = 'done' and c.fee between 0.01 and 1000000000000 and c.location_id = any (p_locs) and c.settle_date between p_from and p_to
  union all
  -- bos113 (rule drawer_short_post = on): a final drawer count difference is a cash movement of the day (short = out, over = in)
  select e.location_id, e.entry_date, case when k.diff < 0 then 'out' else 'in' end, 'cash'::text, 'cash_variance'::text, abs(k.diff), '#' || e.serial::text, 'drawer count difference'::text, e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry'::text, e.id::text, false, false
    from public.entry_counts k join public.entries e on e.id = k.entry_id
   where coalesce(public.rule_txt('drawer_short_post'), 'off') = 'on' and k.section = 'drawer' and k.diff <> 0 and e.form_code = '14-1' and e.status in ('submitted', 'approved')
     and e.location_id = any (p_locs) and e.entry_date between p_from and p_to;
$function$$n1_0$);
-- _p27_pl(date,date,integer[])
insert into _u_plan (fn, kind, a, b) values
  ('public._p27_pl(date,date,integer[])', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ag as (  -- bos72: stock-ledger cost of what was sold (item_costs only as fallback), returns subtracted with their discount share
    select date_trunc('month', h.d)::date as m, h.loc as location_id,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as cr,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cg
    from public._cogs_lines72(d1, d2, locs) h group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
      union all  -- bos85: mobile wallet fees (phase83), zero rows while the fee treatment is not_posted
      select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa0 as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id,
             sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */
        and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2
      union all
      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0), 2), round(coalesce(a.cg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$$r0_0$, null),
  ('public._p27_pl(date,date,integer[])', 'known', '8b6e3e138ccae1a4e0e78321c3cd9a6a', null),
  ('public._p27_pl(date,date,integer[])', 'known', 'a6c9637a42387221374986fbf931209a', null),
  ('public._p27_pl(date,date,integer[])', 'known', 'e230fe7962af686a514e6205f66a757d', null),
  ('public._p27_pl(date,date,integer[])', 'old', $o0_0$      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from ($o0_0$, $n0_0$      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),
  sa0 as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from ($n0_0$),
  ('public._p27_pl(date,date,integer[])', 'old', $o1_0$      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)$o1_0$, $n1_0$      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */) z group by 1, 2),
  sa as (  -- bos117: labour already absorbed into product cost (conversion detail 'labour' of the runs) is not charged a second time to the factory branch (switch factory_labour_absorbed117)
    select s0.m, s0.location_id, case when public.rule_on('factory_labour_absorbed117') then greatest(s0.amt - coalesce((select sum((dd ->> 'amount')::numeric) from public.production_runs pr, jsonb_array_elements(coalesce(pr.conversion_detail, '[]'::jsonb)) dd
        where pr.status = 'done' and pr.location_id = s0.location_id and date_trunc('month', (pr.made_at at time zone 'Asia/Dhaka')::date)::date = s0.m and (pr.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
          and dd ->> 'type' = 'labour' and (dd ->> 'amount') is not null), 0), 0) else s0.amt end as amt
    from sa0 s0),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)$n1_0$);
-- _r3q_l3_shop_pnl(date,date,integer[],jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: profit_truth_mode = on returns the rows of _pnl_truth112 (ONE figure, shares inside the place); off = the two selects below, exactly as before
  select t from public._pnl_truth112(d1, d2, locs) t where coalesce(public.rule_txt('profit_truth_mode'), 'off') = 'on'
  union all
  select x from (
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  sx as (select o_loc, sum(o_cogs_fallback) fb, sum(o_unknown_rev) unk from public._p27_src72(d1, d2, locs) group by o_loc)  -- bos72
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'cogs_fallback', coalesce(sx.fb, 0), 'unknown_cost_rev', coalesce(sx.unk, 0),   -- bos72
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', case when public.rule_on('report_profit_blank_on') /* bos440 */ and (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)) then null
                    else round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2) end,
    'profit_complete', not (a.ex is null or a.sal is null or a.fx is null or (a.net > 0 and a.costed < a.net)),
    'profit_pct', case when a.net > 0 and not (public.rule_on('report_profit_blank_on') and (a.ex is null or a.sal is null or a.fx is null or a.costed < a.net)) then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end, public._rptb1_loss_gaps(d1, d2, a.o_loc) /* bos401 */), '')) as x
  from a join public.locations l on l.id = a.o_loc left join sx on sx.o_loc = a.o_loc
  where coalesce(public.rule_txt('profit_truth_mode'), 'off') <> 'on'
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl') and coalesce(public.rule_txt('profit_truth_mode'), 'off') <> 'on') old;
$function$$r0_0$, null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', '35851d5e0867126927acc20eacdf6cbf', null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', '6558f0168718af880d0aea46b40208a1', null),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'known', 'c117f72d482259a0b32156f54489a722', null);
do $u532$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase532: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase532: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase532: % function(s) changed', nfix;
end $u532$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase533.sql
-- Phase 533 (UNION-5: stock functions carry both lines (unit conversion, late sale, returns, transit loss, reconcile audit, intermediate ingredients)). Paste-twice safe. Earlier phase files are not edited.
-- What: _sale_stock_out: our switch stock_unit_unknown_block (phase 501) first, then the advanced unit_conv_required (bos82) and the late sale / offline soft stock rules.
--   sale_return: our return_sale_factor_on (phase 501) then the advanced return_uses_sale_rows (bos114). stock_receive_transfer: our partial receipt (phase 499) and the advanced
--   transit_short_mode = loss (bos83) counted on what is still missing. stock_reconcile: our change log (bos420) and the advanced audit line per fixed row (bos84). stock_transfer: both.
--   _recipe_lines_ok: a made product may be an ingredient when EITHER recipe_intermediate_on (phase 504) OR semi_finished_ingredient116 (bos116) is on; both loop checks run.
-- All of these rules default to OFF/as before. Paste AFTER phase532 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _sale_stock_out()
insert into _u_plan (fn, kind, a, b) values
  ('public._sale_stock_out()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner). See phase 501, L1.
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
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
      if public.rule_on('stock_unit_unknown_block') then
        raise exception 'stock_unit_unknown' using detail = coalesce(it.code, ''), hint = 'unit ' || coalesce(ln->>'unit', '') || ' has no conversion to ' || coalesce(nullif(it.base_unit, ''), it.unit);
      end if;
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
    insert into public.sale_base_factor (sale_id, item_id, unit, factor) values (new.id, it.id, coalesce(ln->>'unit', ''), round(bq / q, 12)) on conflict do nothing;
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
end $function$$r0_0$, null),
  ('public._sale_stock_out()', 'known', '6d154ba33575afcbed1c3e41aa767a0a', null),
  ('public._sale_stock_out()', 'known', '85cb2f162c0cf934e637824e4de000aa', null),
  ('public._sale_stock_out()', 'known', 'c67d14180692b7b19b114e01052a0e9b', null),
  ('public._sale_stock_out()', 'old', $o0_0$AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text;
begin$o0_0$, $n0_0$AS $function$
-- bos89: merge of phase508 (unit_conv_required) and phase509 (offline soft stock); the original Bangla wording of the unit message is kept
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; um text; soft83 boolean := false; bal83 numeric;   -- bos82 bos83
begin$n0_0$),
  ('public._sale_stock_out()', 'old', $o1_0$  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle$o1_0$, $n1_0$  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos94: owner can limit how old a sale may be and still count as a late sync (rule offline_sale_max_age, hours; empty = no limit = as before). A manager replay override stays soft.
  if neg = 'soft' and public.rule_num('offline_sale_max_age') is not null and new.sold_at < now() - make_interval(hours => public.rule_num('offline_sale_max_age')::int)
     and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos94
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle$n1_0$),
  ('public._sale_stock_out()', 'old', $o2_0$      end if;
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',$o2_0$, $n2_0$      end if;
      um := coalesce(public.rule_txt('unit_conv_required'), 'warn');   -- bos82: off | warn (today) | refuse
      if um = 'refuse' and neg = 'full' then raise exception 'unit_unknown' using detail = 'Unit conversion unknown for ' || it.code || ': set the conversion or sell in the base unit', hint = it.code; end if;   -- bos82
      if um = 'refuse' then   -- bos82: a sale that already happened (offline) is recorded, never lost, but flagged red
        perform public._stock_exc(new.location_id, 'stock_unit_unknown_late', 'red',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline বিক্রি নেওয়া হয়েছে কিন্তু unit-এর conversion জানা নেই, stock কমেনি',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.code) || ' — offline sale accepted but the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');   -- bos82
      elsif um <> 'off' then   -- bos82
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',$n2_0$),
  ('public._sale_stock_out()', 'old', $o3_0$        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;$o3_0$, $n3_0$        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      end if;   -- bos82
      continue;$n3_0$),
  ('public._sale_stock_out()', 'old', $o4_0$    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);$o4_0$, $n4_0$    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);$n4_0$);
-- sale_return(uuid,uuid,jsonb,text,text,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text DEFAULT NULL::text, p_refund_mode text DEFAULT NULL::text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text)
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
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
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
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if it.tracked is not true then continue; end if;
    bq := null;
    if public.rule_on('return_sale_factor_on') then                  -- the factor saved at the sale (sale_base_factor); older sales have none and use today's factor
      select f.factor * ln.q into bq from public.sale_base_factor f where f.sale_id = s.id and f.item_id = it.id and f.unit = coalesce(ln.u, '');
    end if;
    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * bq / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;
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
  perform public._w1c_return_hook(rid); /* bos91 */
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $function$$r0_0$, null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '7e2e09f0185df9ee356ad36f76070fe6', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '8532e9849c8b6233ee40d2699cfd538a', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', '98732425d858f6bd190aeac139f92b1e', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'known', 'c3298aa49ef8be2c624eef0638bd6dba', null),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o0_0$    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);$o0_0$, $n0_0$    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);$n0_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o1_0$  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid;
    if it.tracked is not true then continue; end if;$o1_0$, $n1_0$  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if it.tracked is not true then continue; end if;$n1_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o2_0$    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if bq is null then$o2_0$, $n2_0$    if bq is null then bq := public._base_qty(it.id, ln.q, ln.u); end if;
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * bq / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select case when count(*) filter (where q.b is null) > 0 then null else sum(q.b) end from (select public._base_qty(it.id, nullif(e->>'qty', '')::numeric, e->>'unit') b      -- sec121: all lines of the item, in base units
              from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = it.id::text) q) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;
    if bq is null then$n2_0$),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'old', $o3_0$  end loop;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);$o3_0$, $n3_0$  end loop;
  if coalesce(public.rule_txt('packaging_return_mode'), 'none') <> 'none' then      -- bos80: packaging of a returned product (none = today)
    perform public._ret_pack80(rid, s.id, out_lines);
  end if;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);$n3_0$);
-- stock_receive_transfer(uuid,numeric,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_receive_transfer(uuid,numeric,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; ob public.stock_batches;
  lid bigint; got numeric; skip numeric; avail numeric; left_qty numeric; partial boolean;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  -- what has already arrived in earlier steps of this delivery (always 0 when the switch is off: one receipt closes the transfer)
  got := coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in'), 0);
  left_qty := t.qty - got;
  rq := coalesce(p_received_qty, left_qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > left_qty then raise exception 'over_received'; end if;
  partial := public.rule_on('transfer_partial_on') and rq < left_qty;
  rem := rq;
  skip := got;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;      -- this line already arrived in an earlier step
    avail := avail - skip;
    skip := 0;
    take := least(avail, rem);
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
  if partial then
    update public.stock_transfers set received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
    return jsonb_build_object('id', t.id, 'status', 'sent', 'partial', true, 'received_qty', got + rq, 'remaining', left_qty - rq);
  end if;
  update public.stock_transfers set status = 'received', received_qty = got + rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if got + rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || (got + rq)::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || (got + rq)::text || ' — short in transit');
  end if;
  if t.qty - got - rq > 0 and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss (shortfall counted after earlier partial receipts)
    perform public._transit_loss83(t.id, t.qty - got - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);
end $function$$r0_0$, null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', '24c310ed8a630b1753efa4a047e2d5de', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', '81118bd620e74142e39274c833cfa284', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'known', 'e1e47c4f94c94390d19e18abec8494fd', null),
  ('public.stock_receive_transfer(uuid,numeric,text)', 'old', $o0_0$  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);$o0_0$, $n0_0$  end if;
  if t.qty - got - rq > 0 and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss (shortfall counted after earlier partial receipts)
    perform public._transit_loss83(t.id, t.qty - got - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', got + rq, 'short', t.qty - got - rq);$n0_0$);
-- stock_reconcile(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_reconcile(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_reconcile(p_fix boolean DEFAULT false)
 RETURNS TABLE(item_id uuid, location_id integer, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric; n int := 0; sid text; log_ jsonb := '[]'::jsonb;
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
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;
      return next;
    end if;
  end loop;
  if p_fix and n > 0 then                                                                                                   -- bos420: the cache was rewritten, say who and what
    select p.staff_id into sid from public.profiles p where p.id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'stock_reconcile_fix', 'stock_balance', null, jsonb_build_object('rows_fixed', n, 'confirmed', coalesce(current_setting('bos.reconcile_confirm', true), '') = 'yes', 'first_rows', log_));
  end if;
end $function$$r0_0$, null),
  ('public.stock_reconcile(boolean)', 'known', '493eac1f54ca49daf250160bc220ecbb', null),
  ('public.stock_reconcile(boolean)', 'known', 'a3c49535852e3e2db835a74dcee58a2d', null),
  ('public.stock_reconcile(boolean)', 'known', 'cbcb93c7f000f71974e4e86cf4162ded', null),
  ('public.stock_reconcile(boolean)', 'old', $o0_0$  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in$o0_0$, $n0_0$  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();                                  -- bos84
  for r in$n0_0$),
  ('public.stock_reconcile(boolean)', 'old', $o1_0$      if p_fix then
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
      end if;$o1_0$, $n1_0$      if p_fix then
        perform set_config('bos.audit_skip84', '1', true);                                                    -- bos84 (this function writes its own, single row)
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
        n := n + 1; if n <= 50 then log_ := log_ || jsonb_build_array(jsonb_build_object('item_id', r.iid, 'location_id', r.lid, 'old_qty', bq, 'new_qty', q, 'old_avg', bavg, 'new_avg', a)); end if;   -- bos420
        perform set_config('bos.audit_skip84', '', true);                                                     -- bos84
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)               -- bos84
          values (auth.uid(), sid, 'reconcile_fix', 'stock_balance', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('old', jsonb_build_object('qty', bq, 'avg_cost', bavg), 'new', jsonb_build_object('qty', q, 'avg_cost', a),
                                     'source', 'stock_reconcile', 'src', 'phase84'));                          -- bos84
      end if;$n1_0$);
-- stock_transfer(integer,integer,uuid,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if public.rule_on('transfer_paused_block') and coalesce((select l.status from public.locations l where l.id = p_to), '') <> 'live' then
    raise exception 'destination_paused';
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if public.rule_on('transfer_overdraw_block') and coalesce((select sb.qty from public.stock_balance sb where sb.item_id = p_item and sb.location_id = p_from), 0) < bq then
    raise exception 'insufficient_stock';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.stock_transfers (id, client_id, from_location_id, to_location_id, item_id, qty, note, sent_by, sent_staff)
      values (tid, p_client, p_from, p_to, p_item, bq, left(p_note, 200), auth.uid(), sid);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins
    select * into t from public.stock_transfers where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
    raise;
  end;
  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', '36ef875eee267f280ec4b9c29dfa7250', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', '5ffe72be40375c722d7b753d4e7f7533', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'known', 'ae3bb09a26d249c2c2e094d503cbcef3', null),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'old', $o0_0$  end;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$o0_0$, $n0_0$  end;
  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out', 'transfer', tid::text, null, null, now(), left(p_note, 200), null, 'full');
  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$n0_0$);
-- _recipe_lines_ok(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_lines_ok(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_lines_ok(p_item uuid, p_lines jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- a made product (finished good) may be an ingredient only behind a switch: phase 504 recipe_intermediate_on (navstack line) or bos116 semi_finished_ingredient116 (advanced line); never in a loop
      if not (ing.item_type = 'finished_good' and (public.rule_on('recipe_intermediate_on') or public.rule_on('semi_finished_ingredient116'))) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public.rule_on('recipe_intermediate_on') and public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;   -- phase 504
      if public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$$r0_0$, null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', '5cebadbf52950d50546715a034c3f7a2', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', 'dfa3141d8708ae0dafea55bb9ce7b690', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'known', 'fe83e9b62649c3d38e780399c6d72219', null),
  ('public._recipe_lines_ok(uuid,jsonb)', 'old', $o0_0$    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;$o0_0$, $n0_0$    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;$n0_0$),
  ('public._recipe_lines_ok(uuid,jsonb)', 'old', $o1_0$    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- phase 504: a made product (finished good) may be an ingredient only when recipe_intermediate_on is on, and never in a loop
      if not (ing.item_type = 'finished_good' and public.rule_on('recipe_intermediate_on')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;
    end if;$o1_0$, $n1_0$    if ing.item_type not in ('raw_material', 'packaging', 'resale') then
      -- a made product (finished good) may be an ingredient only behind a switch: phase 504 recipe_intermediate_on (navstack line) or bos116 semi_finished_ingredient116 (advanced line); never in a loop
      if not (ing.item_type = 'finished_good' and (public.rule_on('recipe_intermediate_on') or public.rule_on('semi_finished_ingredient116'))) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
      if public.rule_on('recipe_intermediate_on') and public._recipe_reaches(iid, p_item) then raise exception 'recipe_loop' using detail = ing.code; end if;   -- phase 504
      if public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    end if;$n1_0$);
do $u533$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase533: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase533: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase533: % function(s) changed', nfix;
end $u533$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase534.sql
-- Phase 534 (UNION-6: acct_journal_post, the 7-argument and the 8-argument function behave the same). Paste-twice safe. Earlier phase files are not edited.
-- What: phase529 left two real functions: acct_journal_post with 7 arguments (hooked by our line: the journal gate of phase 94/95, bos87 w1e95) and with 8 arguments (advanced line: p_reason and the
--   manual journal guard of phase 85/511, bos85; no parameter has a default any more, so a call can never be ambiguous). This file gives the 7-argument function the bos85 guard (reason absent)
--   and the 8-argument function our journal gate, so a screen that sends p_reason and one that does not are checked by the same rules. manual_journal_guard defaults off.
-- Paste AFTER phase533 and after phase 505. Same behaviour on a re-paste as phase530.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_photo text DEFAULT NULL::text, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */
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
  if coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' then perform public._manual_guard85(ln, null::text); end if;   -- bos85 (same guard as the 8-argument function, no reason given)
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
  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $function$$r0_0$, null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'known', '787639caa0c11c3027a38a4bb2981894', null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'known', 'c8726b98477c6355b3dbe032867a09bb', null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'old', $o0_0$  ln := public._acct_resolve(p_lines, p_loc);
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;$o0_0$, $n0_0$  ln := public._acct_resolve(p_lines, p_loc);
  if coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' then perform public._manual_guard85(ln, null::text); end if;   -- bos85 (same guard as the 8-argument function, no reason given)
  for x in select * from jsonb_array_elements(ln) loop td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric; end loop;$n0_0$);
-- acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_journal_post(p_date date, p_loc integer, p_memo text, p_lines jsonb, p_client uuid, p_photo text, p_dry boolean, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */
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
  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);
  return jsonb_build_object('id', id_, 'total', td);
end $function$$r0_0$, null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'known', '39f4c4148167bf702f97d82c4022b670', null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'known', 'f7498db70ba73066d80c4835bfe50332', null),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'old', $o0_0$AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;
begin$o0_0$, $n0_0$AS $function$
declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */
begin$n0_0$),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'old', $o1_0$  end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);$o1_0$, $n1_0$  end if;
  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, case when coalesce(public.rule_txt('manual_journal_guard'), 'off') = 'on' and nullif(btrim(p_reason), '') is not null then 'reason:' || btrim(p_reason) end /* bos85 */, ln, null, p_client, p_photo);$n1_0$);
do $u534$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase534: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase534: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase534: % function(s) changed', nfix;
end $u534$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase535.sql
-- Phase 535 (UNION-7: the advanced line's logic in 43 shared functions (_acct_all ... bank_recon_match_many) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
-- What: the advanced line changed these functions after phase 79 (rules, scope, audit, templates, cost, ...). Pasting the early phases (8 to 79) again, as the owner's earlier paste of
--   our line did, puts their older text back and the advanced logic is silently gone. A database that was built by pasting the advanced phases and then ONE run of our phases
--   never loses it (this is how the fresh build is ordered), so on a fresh build this file does nothing.
-- What this file does: for every function listed, if its text is a KNOWN older text (the base text of phases 8-79, or the text of the earlier live paste, recognised by md5), it is replaced by the merged
--   text (the advanced text, our line did not change these functions); the old text is saved in public._union_fn_backup first. An unknown text is never overwritten: all such functions are
--   listed in one message and nothing is changed. Nothing here adds a switch or changes a default.
-- Paste AFTER phase534 and after phase 505. Safe to paste twice.

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

drop table if exists _u_plan;
create temp table _u_plan (seq serial primary key, fn text not null, kind text not null, a text not null, b text);
-- _acct_all()
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_all()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_all()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when not public._org_on123()
    then (public.can_loc(null) or (public.is_active() and public.has_grant('accounts_manage')))   -- OFF: phase40
    else (public.is_active() and public.is_owner()) end;                                          -- ON (scope123): owner only
$function$$r0_0$, null),
  ('public._acct_all()', 'known', '94425e97bfc176a99d2a30d27eebd421', null);
-- _acct_inv_split72(text[],text,text[],integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._acct_inv_split72(text[],text,text[],integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._acct_inv_split72(p_ref_types text[], p_ref_id text, p_reasons text[], p_sign integer)
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
$function$$r0_0$, null),
  ('public._acct_inv_split72(text[],text,text[],integer)', 'known', 'fb2f5b8895308fc29d6f84d6994d80f9', null);
-- _all_locs()
insert into _u_plan (fn, kind, a, b) values
  ('public._all_locs()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._all_locs()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active() and (case when not public._org_on123()
    then (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'))   -- OFF: phase10
    else public.is_owner() end);                                                                                                  -- ON (scope123): owner only
$function$$r0_0$, null),
  ('public._all_locs()', 'known', '9c7db09ef458d68c1ed20fcca6ea91f9', null);
-- _backup_tables()
insert into _u_plan (fn, kind, a, b) values
  ('public._backup_tables()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._backup_tables()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$function$$r0_0$, null),
  ('public._backup_tables()', 'known', 'cc54ed6c9dc11587384e9a9ff260ebf3', null);
-- _c78_rows(date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._c78_rows(date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._c78_rows(p_from date, p_to date)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: same rows as before; rule cost_share_prorate_mode = on takes a monthly share pro rata for the days of the range (default off = the whole month, as before)
  select * from public._c78_rows112(p_from, p_to, coalesce(public.rule_txt('cost_share_prorate_mode'), 'off') = 'on');
$function$$r0_0$, null),
  ('public._c78_rows(date,date)', 'known', 'f286d1e20c5dd0730f626d2df68136e7', null);
-- _cogs_lines72(date,date,integer[])
insert into _u_plan (fn, kind, a, b) values
  ('public._cogs_lines72(date,date,integer[])', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos89: merge of phase506 (free-cost item) and phase514 (one report cost switch)
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  rcs as materialized (select public._rcs88() as m),   -- bos110: evaluated once (it was inlined into every use = once per row); bos88: the ONE report cost switch (ledger_avg | item_costs | ledger_then_item_costs)
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
$function$$r0_0$, null),
  ('public._cogs_lines72(date,date,integer[])', 'known', 'aebb3a5c12140996670db8c7a1a5c332', null);
-- _conv_cost(uuid,integer,numeric,numeric,date,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._conv_cost(p_recipe uuid, p_loc integer, p_batches numeric, p_out numeric, p_date date, p_force_mode text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare md text; c record; ty record; det jsonb := '[]'::jsonb; tot numeric := 0; complete boolean := true; amt numeric; norm numeric; m date := public._m1(p_date); any_pool boolean := false; ncomp int := 0; why text := null; a numeric; pr jsonb;
        drv boolean := public.rule_on('pool_drivers116'); cfg public.location_cost_cfg; dn text; nd numeric; qd numeric; hrs numeric; prov boolean := false; use_prov boolean := false; pj jsonb; base_u text;   -- bos116
begin
  md := coalesce(p_force_mode, (select mode from public.location_cost_cfg where location_id = p_loc), 'off');
  if md = 'off' then return jsonb_build_object('mode', 'off', 'amount', 0, 'complete', true, 'detail', '[]'::jsonb, 'reason', null); end if;
  if md = 'recipe' then
    for c in select * from public.recipe_cost_components where recipe_id = p_recipe and active order by component_type, id loop
      ncomp := ncomp + 1; amt := null;
      if c.amount is null then complete := false;
      elsif c.basis = 'per_batch' then amt := c.amount * p_batches;
      elsif c.basis = 'per_unit' then amt := c.amount * p_out;
      elsif c.hours_per_batch is null then complete := false;
      else amt := c.amount * c.hours_per_batch * p_batches; end if;
      if amt is not null then tot := tot + amt; end if;
      det := det || jsonb_build_object('type', c.component_type, 'note', c.type_note, 'basis', c.basis, 'amount', case when amt is null then null else round(amt, 6) end, 'incomplete', amt is null);
    end loop;
    if ncomp = 0 then complete := false; why := 'no_components'; end if;
  else
    select * into cfg from public.location_cost_cfg where location_id = p_loc;      -- bos116
    norm := cfg.normal_monthly_output;
    -- bos116: provisional only when the run month has NO pool row at all (nothing typed yet) and the owner switched it on; reprice sets bos.no_prov116 to see the real pool only
    use_prov := public.rule_on('conv_provisional116') and coalesce(current_setting('bos.no_prov116', true), '') <> 'on'
                and not exists (select 1 from public.factory_cost_pools f where f.active and f.location_id = p_loc and f.month = m);
    base_u := lower(coalesce((select public._item_base(r.item_id) from public.recipes r where r.id = p_recipe), ''));
    if not drv then
      if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg';      -- the pool rate is per kg of output: a piece-based product needs recipe rates (or pool_drivers116)
      elsif norm is null or norm <= 0 then complete := false; why := 'normal_output_blank';
      else
        for ty in select code from public.cost_component_types where active order by code loop
          pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
          if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;      -- bos116
          if a is not null then any_pool := true; amt := a / norm * p_out; tot := tot + amt;
            if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
            det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'rate', round(a / norm, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
              || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end; end if;
        end loop;
        if not any_pool then complete := false; why := 'no_pool'; end if;
      end if;
    else
      -- bos116: driver per cost type (type override, else the place default, else output kg = today)
      for ty in select code, driver116 from public.cost_component_types where active order by code loop
        pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric; pj := null;
        if a is null and use_prov then pj := public._pool_rate_prov116(p_loc, m, ty.code); a := (pj ->> 'amount')::numeric; end if;
        if a is null then continue; end if;
        dn := coalesce(ty.driver116, cfg.driver116, 'output_kg'); nd := null; qd := null;
        if dn = 'output_kg' then
          nd := norm; qd := p_out;
          if base_u <> 'kg' then complete := false; why := 'pool_unit_not_kg'; continue; end if;
        elsif dn = 'output_units' then nd := cfg.normal_units116; qd := p_out;
        elsif dn = 'batches' then nd := cfg.normal_batches116; qd := p_batches;
        else
          nd := cfg.normal_labour_hours116;
          select sum(c2.hours_per_batch) into hrs from public.recipe_cost_components c2 where c2.recipe_id = p_recipe and c2.active and c2.basis = 'per_labour_hour' and c2.hours_per_batch is not null;
          qd := hrs * p_batches;
        end if;
        if nd is null or nd <= 0 then complete := false; why := 'normal_' || dn || '_blank'; continue; end if;
        if qd is null then complete := false; why := 'no_labour_hours'; continue; end if;
        any_pool := true; amt := a / nd * qd; tot := tot + amt;
        if pj is not null and (pj ->> 'amount') is not null then prov := true; end if;
        det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'driver', dn, 'rate', round(a / nd, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', coalesce(pj -> 'span', pr -> 'span'), 'gap_months', coalesce(pj -> 'gaps', pr -> 'gaps'))
          || case when pj is not null and (pj ->> 'amount') is not null then jsonb_build_object('provisional', true, 'provisional_from', pj ->> 'from') else '{}'::jsonb end;
      end loop;
      if not any_pool and why is null then complete := false; why := 'no_pool'; end if;
    end if;
  end if;
  return jsonb_build_object('mode', md, 'amount', tot, 'complete', complete, 'detail', det, 'reason', why) || case when prov then jsonb_build_object('provisional', true) else '{}'::jsonb end;      -- bos116
end $function$$r0_0$, null),
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'known', 'e37bc4d962076d534a57a048fc879947', null);
-- _cs_push_pools(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public._cs_push_pools(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._cs_push_pools(p_bill bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.cost_source_bills; ct text; sh record;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  update public.factory_cost_pools set active = false where source = 'allocated' and ref like 'bill:' || p_bill::text || ':%' and active;
  if b.status <> 'active' then perform public._pool_gl_after_bill117(p_bill); return; end if;      -- bos117
  select t.component_type into ct from public.cost_sources s join public.cost_source_types t on t.code = s.cost_type where s.id = b.source_id;
  for sh in select location_id, sum(amount) amt from public.cost_bill_shares where bill_id = p_bill and active and kind = 'share' and dest = 'factory' group by location_id loop
    if sh.amt > 0 then
      insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, ref, note, created_by)
        values (sh.location_id, b.period_month, coalesce(ct, 'other'), b.period_kind, sh.amt, b.one_off, 'allocated', 'bill:' || p_bill::text || ':' || sh.location_id::text, 'from cost bill ' || p_bill::text, auth.uid());
    end if;
  end loop;
  perform public._pool_gl_after_bill117(p_bill);      -- bos117: pool rows of this bill (new and retired) are mirrored in the books (switch pool_gl_post117)
end $function$$r0_0$, null),
  ('public._cs_push_pools(bigint)', 'known', 'de725d03d263c625b7ab4d9f1c38071f', null);
-- _elp_post_line(entries,integer,text,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._elp_post_line(entries,integer,text,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
        fmode text; rc public.recipes; nr record; tot numeric := 0; cok boolean := true; av numeric; yf numeric;   -- bos83
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
    -- bos83: the slip has no screen record yet: a PENDING link (form -> screen record owed) so unmatched_forms() can list it
    begin perform public.shadow_link_add(public._entry_domain(e.form_code), e.location_id, 'entries', e.id::text, 'stock_screen', null, 'form ' || e.form_code || ' skipped: the screen is the record, screen record owed'); exception when others then null; end;
    return;
  end if;
  -- bos83: owner switch form_051_mode = refuse: the factory daily sheet is not a posting source at all (kept as a reference, line shown as skipped)
  fmode := coalesce(public.rule_txt('form_051_mode'), 'reference');
  if l->>'skip' is null and kind = 'prod' and e.form_code = '05-1' and fmode = 'refuse' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', 'form051_not_a_source', ref, auth.uid());
    return;
  end if;
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item' and public._m132_at(org_unit_id, e.location_id) /* m132 */;
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item' and public._m132_at(i.org_unit_id, e.location_id) /* m132 */), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    ucb := null;
    if e.form_code = '05-1' and fmode = 'post' then      -- bos83: the finished goods are made FROM the recipe's ingredients, taken out at the average cost
      select r.* into rc from public.recipes r where r.item_id = it.id and r.active and exists (select 1 from public.recipe_lines x where x.recipe_id = r.id and x.active) order by r.version desc limit 1;
      if not found then raise exception 'no_recipe_for_051: %', it.code; end if;
      perform public._recipe_gate73(rc.id);
      yf := public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit);
      if yf is null or not (yf > 0) then raise exception 'unit_unknown: %', it.code; end if;
      for nr in select * from public._recipe_need(rc.id, bq / yf, e.location_id) order by item_id loop
        if not nr.tracked then raise exception 'ingredient_not_tracked: %', coalesce(nr.code, ''); end if;
        if not nr.unit_ok then raise exception 'unit_unknown: %', coalesce(nr.code, ''); end if;
        if nr.need < 0.0001 then continue; end if;
        select b.avg_cost into av from public.stock_balance b where b.item_id = nr.item_id and b.location_id = e.location_id;
        if av is null then cok := false; else tot := tot + nr.need * av; end if;
        perform public.stock_post(nr.item_id, e.location_id, -nr.need, 'issue_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
      end loop;
      ucb := case when cok and bq > 0 then round(tot / bq, 6) end;
    end if;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, ucb, bid, at_, left(note, 200), null, 'none');
    if ucb is null and e.form_code = '05-1' and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'form051_cost_null' and x.status = 'open') then      -- bos83
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (e.id, e.form_code, e.location_id, e.entry_date, 'form051_cost_null', 'yellow', null,
          jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || it.name_bn || ' তৈরি মাল cost ছাড়া stock-এ ঢুকেছে (cost অজানা)',
                             'en', e.form_code || '-' || e.serial || ': ' || coalesce(it.name_en, it.name_bn) || ' entered stock with NO cost (cost unknown)'));
    end if;
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $function$$r0_0$, null),
  ('public._elp_post_line(entries,integer,text,jsonb)', 'known', '8f1b730dc2d6f74e13d818010222e5a1', null);
-- _entries_countseal_guard23()
insert into _u_plan (fn, kind, a, b) values
  ('public._entries_countseal_guard23()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._entries_countseal_guard23()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; cf text; s record; r jsonb; n int; arr jsonb := '[]'::jsonb; it public.items; iid uuid; f numeric; bk numeric;
begin
  if new.form_code not in ('04-1', '04-3') or not public.stock_blind_active(new.form_code, new.location_id) then return new; end if;
  k := case new.form_code when '04-3' then 'rows' else 'lines' end; cf := case new.form_code when '04-3' then 'count' else 'counted' end;
  if tg_op = 'UPDATE' then
    for s in select * from public.entry_count_seals where entry_id = new.id loop
      r := case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k -> (s.line_no - 1) end;
      if r is null or btrim(coalesce(r ->> 'item', '')) <> s.item_code or public._n18(r, cf) <> s.counted then raise exception 'count_locked'; end if;
    end loop;
    if old.status = 'draft' and new.status <> 'draft' then
      for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
        if nullif(btrim(r ->> 'item'), '') is not null and not exists (select 1 from public.entry_count_seals where entry_id = new.id and line_no = n) then raise exception 'count_not_sealed'; end if;
      end loop;
    end if;
  end if;
  if new.form_code = '04-3' and jsonb_typeof(new.data -> k) = 'array' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(new.data -> k) with ordinality x(v, o) loop
      r := case when jsonb_typeof(r) = 'object' then r - 'book' else r end;
      if tg_op = 'UPDATE' and new.status <> 'draft' and jsonb_typeof(r) = 'object' then
        select sl.book_base, i.id into bk, iid from public.entry_count_seals sl left join public.items i on i.code = sl.item_code and public._m132_at(i.org_unit_id, new.location_id) /* m132 */ where sl.entry_id = new.id and sl.line_no = n;
        if found and bk is not null then
          select * into it from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */;
          f := public._unit_factor_base(it.id, it.unit);
          if f is not null and f > 0 then r := r || jsonb_build_object('book', round(bk / f, 4)::text); end if;
        end if;
      end if;
      arr := arr || jsonb_build_array(r);
    end loop;
    new.data := jsonb_set(new.data, array[k], arr);
  end if;
  return new;
end $function$$r0_0$, null),
  ('public._entries_countseal_guard23()', 'known', '68e035fbee29c9f868eb8f5b9a2b905a', null);
-- _inb_insert_message(jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._inb_insert_message(jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._inb_insert_message(p jsonb)
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
end $function$$r0_0$, null),
  ('public._inb_insert_message(jsonb)', 'known', '8f89c4b249bc129e6a749a0f1332b9a5', null);
-- _inb_pii_cols76()
insert into _u_plan (fn, kind, a, b) values
  ('public._inb_pii_cols76()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._inb_pii_cols76()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cols text;
begin
  if new.key = 'inbox_pii_guard_on' then
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      revoke select (customer_mobile, address, note, draft_note, lines) on public.online_orders from authenticated;   -- bos105: note, draft_note, lines too
    else
      grant select (customer_mobile, address, note, draft_note, lines) on public.online_orders to authenticated;   -- bos105
    end if;
  elsif new.key = 'customers_pii_guard_on' then   -- bos105
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into cols from pg_attribute a
       where a.attrelid = 'public.customers'::regclass and a.attnum > 0 and not a.attisdropped and a.attname not in ('mobile', 'whatsapp', 'address', 'note');
      revoke select on public.customers from authenticated;
      execute 'grant select (' || cols || ') on public.customers to authenticated';
    else
      grant select on public.customers to authenticated;
    end if;
  end if;
  return new;
end $function$$r0_0$, null),
  ('public._inb_pii_cols76()', 'known', '9115169f930182c0e432c80a0c91de86', null);
-- _intake_fail(text,integer,text,text,jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._intake_fail(text,integer,text,text,jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._intake_fail(p_kind text, p_channel integer, p_ext text, p_err text, p_payload jsonb, p_state text DEFAULT 'failed'::text)
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
end $function$$r0_0$, null),
  ('public._intake_fail(text,integer,text,text,jsonb,text)', 'known', '292695e1e05729b885381982772ade6b', null);
-- _item_base(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_base(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_base(p_item uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(nullif(btrim(base_unit), ''), nullif(btrim(unit), '')) from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
$function$$r0_0$, null),
  ('public._item_base(uuid)', 'known', '33fbf5dfa0af34aee227e0a9ec76e6d5', null);
-- _item_flags_apply(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_flags_apply(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_flags_apply(p_item uuid, p_patch jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; f record; ty text;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found then raise exception 'item_not_found'; end if;
  if p_patch ? 'item_type' and nullif(p_patch->>'item_type', '') is not null and (p_patch->>'item_type') is distinct from it.item_type then
    ty := p_patch->>'item_type';
    if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
    select * into f from public._item_type_flags(ty);
    -- a changed type starts from the defaults of the new type, unless the same request also says the flags itself
    update public.items set item_type = ty,
      count_in_business = case when p_patch ? 'count_in_business' then (p_patch->>'count_in_business')::boolean else f.o_count end,
      sellable = case when p_patch ? 'sellable' then (p_patch->>'sellable')::boolean else f.o_sell end where id = p_item;
  else
    if p_patch ? 'count_in_business' then update public.items set count_in_business = (p_patch->>'count_in_business')::boolean where id = p_item; end if;
    if p_patch ? 'sellable' then update public.items set sellable = (p_patch->>'sellable')::boolean where id = p_item; end if;
  end if;
  if p_patch ? 'control_class' then update public.items set control_class = nullif(btrim(p_patch->>'control_class'), '') where id = p_item; end if;
  if p_patch ? 'hidden' then update public.items set hidden = (p_patch->>'hidden')::boolean where id = p_item; end if;
  if p_patch ? 'master_code' then update public.items set master_code = nullif(btrim(p_patch->>'master_code'), '') where id = p_item; end if;
  if p_patch ? 'is_active' then
    if (p_patch->>'is_active')::boolean then update public.items set retired_at = null, retired_reason = null where id = p_item and retired_at is not null;
    else update public.items set retired_at = coalesce(retired_at, now()), retired_reason = coalesce(left(nullif(btrim(p_patch->>'retired_reason'), ''), 200), retired_reason) where id = p_item;
    end if;
  end if;
  if p_patch ? 'locked' then
    if not (public.is_owner() or coalesce(current_setting('bos.item_sys', true), '') = '1') then raise exception 'not allowed'; end if;      -- only the owner locks / unlocks
    update public.items set locked = (p_patch->>'locked')::boolean where id = p_item;
  end if;      -- last: the lock never blocks the changes of the same request
end $function$$r0_0$, null),
  ('public._item_flags_apply(uuid,jsonb)', 'known', '3a55d5efd8bcd78644f084ed31d0bd02', null);
-- _item_link(uuid,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_link(uuid,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_link(p_item uuid, p_dict text, p_via text, p_force boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tid uuid; cls text;
begin
  select id, control_class into tid, cls from public.items where code = p_dict and import_batch is not null;
  if tid is null then raise exception 'master_code_not_found'; end if;
  if tid = p_item then raise exception 'bad_request'; end if;
  -- an old (sold) item stands for a sellable product; linking it to a material / asset / tool code needs the owner's explicit yes
  if not coalesce(p_force, false) and exists (select 1 from public.items where id = tid and public._m132_own(items.org_unit_id) /* m132b:items */ and item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled')) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = p_dict and active and item_id <> p_item) then raise exception 'master_code_taken'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active and dict_code <> p_dict;
  insert into public.item_master_links (item_id, dict_code, via, linked_by) select p_item, p_dict, p_via, auth.uid()
    where not exists (select 1 from public.item_master_links where item_id = p_item and dict_code = p_dict and active);
  update public.items set master_code = p_dict, control_class = coalesce(control_class, cls) where id = p_item;
  update public.items set hidden = true, sellable = false where id = tid;           -- the old item stands for it: no second copy in the pickers
  perform set_config('bos.item_sys', '', true);
end $function$$r0_0$, null),
  ('public._item_link(uuid,text,text,boolean)', 'known', '13b709ad1be3b6724b31e9486e0cb6c5', null);
-- _item_master_classify(jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._item_master_classify(jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._item_master_classify(p_rows jsonb)
 RETURNS TABLE(ord integer, code text, cat_no text, category text, name_en text, name_bn text, subcategory text, unit text, control_class text, note text, item_type text, unit_code text, retired boolean, status text, reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with r as (
    select e.ord::int ord, btrim(coalesce(e.v->>'code', '')) code, btrim(coalesce(e.v->>'cat_no', '')) cat_no, btrim(coalesce(e.v->>'category', '')) category,
           btrim(coalesce(e.v->>'name_en', '')) name_en, btrim(coalesce(e.v->>'name_bn', '')) name_bn, btrim(coalesce(e.v->>'subcategory', '')) subcategory,
           btrim(coalesce(e.v->>'unit', '')) unit, btrim(coalesce(e.v->>'control_class', '')) control_class, btrim(coalesce(e.v->>'note', '')) note
    from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end) with ordinality e(v, ord)),
  c as (
    select r.*, m.item_type, public._item_unit_code(r.unit) unit_code,
           (r.name_en ~* '^\s*RETIRED' or r.name_bn ~* '^\s*RETIRED' or r.note ~* '^\s*Retired') retired,
           row_number() over (partition by r.code order by r.ord) dup_n
    from r left join public.item_class_map m on m.control_class = r.control_class and m.active)
  select c.ord, c.code, c.cat_no, c.category, c.name_en, c.name_bn, c.subcategory, c.unit, c.control_class, c.note, c.item_type, c.unit_code, c.retired,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' or c.dup_n > 1 or (c.name_en = '' and c.name_bn = '') or c.item_type is null or c.unit_code is null
              or c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'conflict'
         when exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */) then 'skip_existing' else 'create' end,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' then 'bad_code' when c.dup_n > 1 then 'duplicate_in_file' when c.name_en = '' and c.name_bn = '' then 'no_name'
         when c.item_type is null then 'unmapped_class' when c.unit_code is null then 'unknown_unit'
         when c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'category_mismatch'
         when exists (select 1 from public.items i where i.code = c.code and (not public._m132_relaxed() or i.org_unit_id is not distinct from public._m132_caller_biz()) /* m132 */) then 'exists' end
  from c order by c.ord;
$function$$r0_0$, null),
  ('public._item_master_classify(jsonb)', 'known', '3471221fdbac15dc3379aa42a4275fe1', null);
-- _ledger_item_guard()
insert into _u_plan (fn, kind, a, b) values
  ('public._ledger_item_guard()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._ledger_item_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ok boolean;
begin
  if new.reverses_id is not null then return new; end if;                  -- undoing an earlier line is always allowed
  if new.reason = 'sale_out' and new.made_at < now() - interval '2 minutes' then return new; end if;      -- a sale that syncs late has already happened
  select count_in_business into ok from public.items where id = new.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  if ok is distinct from true then raise exception 'item_not_counted' using detail = new.item_id::text; end if;
  return new;
end $function$$r0_0$, null),
  ('public._ledger_item_guard()', 'known', '079b6a10d7af6d3b0fea8149593982a1', null);
-- _notif_ok(uuid,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._notif_ok(uuid,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._notif_ok(p_user uuid, p_aud text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and (p_loc is not null or not public._org_on123()) and exists (select 1 from public.user_roles r where r.user_id = auth.uid()   -- scope123: no place = owner only
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$function$$r0_0$, null),
  ('public._notif_ok(uuid,text,integer)', 'known', '2bde1ebff43d6b52e7e6454303126c85', null);
-- _oo_short77(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._oo_short77(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._oo_short77(p_order uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.online_orders; r record; res jsonb := '[]'::jsonb; rsv boolean := public.rule_on('online_pack_reserve_on'); have numeric; reserved numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then return res; end if;
  for r in select (l->>'item_id')::uuid as item_id, sum((l->>'qty')::numeric) as need from jsonb_array_elements(o.lines) l where nullif(l->>'item_id', '') is not null group by 1 loop
    if not exists (select 1 from public.items i where i.id = r.item_id and i.tracked) then continue; end if;
    select coalesce(b.qty, 0) into have from (select 1) z left join public.stock_balance b on b.item_id = r.item_id and b.location_id = o.location_id;
    reserved := 0;
    if rsv then
      select coalesce(sum((l2->>'qty')::numeric), 0) into reserved from public.online_orders o2, jsonb_array_elements(o2.lines) l2
       where o2.location_id = o.location_id and o2.status = 'packed' and o2.id <> o.id and l2->>'item_id' = r.item_id::text;
    end if;
    if r.need > have - reserved then
      res := res || jsonb_build_object('item_id', r.item_id, 'name', (select name_bn from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */), 'need', r.need, 'have', have, 'reserved', reserved, 'short_by', r.need - (have - reserved));
    end if;
  end loop;
  return res;
end $function$$r0_0$, null),
  ('public._oo_short77(uuid)', 'known', 'fab17db83de4367e24d0698b70aad60f', null);
-- _post_purchase_p13(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public._post_purchase_p13(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._post_purchase_p13(p_id uuid, p_payments jsonb DEFAULT NULL::jsonb)
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
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
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
    select * into it from public.items where id = ln.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
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
end $function$$r0_0$, null),
  ('public._post_purchase_p13(uuid,jsonb)', 'known', '7cf22fff506d2bb536e1e40dd01181da', null);
-- _qc_latest60(text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._qc_latest60(text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._qc_latest60(p_type text, p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select status from public.qc_records where source_type = p_type and source_id = p_id and ((select not public._org_on123()) or public._cfgvis133(location_id)) /* scope133 */ order by created_at desc, id desc limit 1;
$function$$r0_0$, null),
  ('public._qc_latest60(text,uuid)', 'known', '4a452166116cebeb49696682abc229ca', null);
-- _recipe_approved_guard()
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_approved_guard()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_approved_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; ap timestamptz;
begin
  if tg_table_name = 'recipes' then
    if old.approved_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
       or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_approved'; end if;
    if old.approved_at is not null and (new.approved_at is distinct from old.approved_at or new.approved_by is distinct from old.approved_by) then raise exception 'recipe_approved'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select approved_at into ap from public.recipes where id = rid and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if ap is not null then raise exception 'recipe_approved'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$$r0_0$, null),
  ('public._recipe_approved_guard()', 'known', 'a3dede9c1d8cf1838e3e33ec05700464', null);
-- _recipe_frozen()
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_frozen()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_frozen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; used timestamptz;
begin
  if tg_table_name = 'recipes' then
    if tg_op = 'DELETE' then
      if old.used_at is not null then raise exception 'recipe_used'; end if;
      raise exception 'no_delete';
    end if;
    if tg_op = 'UPDATE' and old.used_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
        or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_used'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select used_at into used from public.recipes where id = rid and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $function$$r0_0$, null),
  ('public._recipe_frozen()', 'known', 'b3aaa196019317feca931eeb7913a66c', null);
-- _recipe_gate73(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_gate73(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_gate73(p_recipe uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text := coalesce(public.rule_txt('recipe_approval_required'), 'off'); ap timestamptz;
begin
  select approved_at into ap from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if ap is not null or m = 'off' then return 'ok'; end if;
  if m = 'on' then raise exception 'recipe_not_approved'; end if;
  return 'warn';
end $function$$r0_0$, null),
  ('public._recipe_gate73(uuid)', 'known', '1315b3569fd5008a86cc480c14b3c54e', null);
-- _recipe_need(uuid,numeric,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_need(uuid,numeric,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_need(p_recipe uuid, p_batches numeric, p_loc integer)
 RETURNS TABLE(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from public._recipe_need116(p_recipe, p_batches, p_loc, null::numeric);   -- bos116
$function$$r0_0$, null),
  ('public._recipe_need(uuid,numeric,integer)', 'known', 'feeae75737cf48502013349d01950b51', null);
-- _recipe_set_artisan(uuid,integer,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._recipe_set_artisan(uuid,integer,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._recipe_set_artisan(p_recipe uuid, p_artisan integer, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; prev jsonb;
begin
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_artisan is not null and not exists (select 1 from public.artisans where id = p_artisan and public._m132_vis('artisans', artisans.org_unit_id, artisans.id::text, false) /* m132b:artisans */ and active) then raise exception 'artisan_not_found'; end if;
  if r.artisan_id is not distinct from p_artisan then return; end if;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipes set artisan_id = p_artisan where id = p_recipe;
  perform public._rv_log(p_recipe, 'artisan_set', prev, left(p_note, 200));
end $function$$r0_0$, null),
  ('public._recipe_set_artisan(uuid,integer,text)', 'known', '1598dc1d7e0839c50982da7d0a56468d', null);
-- _rv_log(uuid,text,jsonb,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._rv_log(uuid,text,jsonb,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._rv_log(p_recipe uuid, p_kind text, p_prev jsonb, p_summary text, p_client uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes;
begin
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  insert into public.recipe_versions (recipe_id, version, seq, kind, changed_by, changed_at, summary, prev, snap, client_id)
    values (p_recipe, r.version, coalesce((select max(seq) from public.recipe_versions where recipe_id = p_recipe), 0) + 1, p_kind, auth.uid(), now(), left(p_summary, 300), p_prev, public._recipe_snapshot(p_recipe), p_client);
end $function$$r0_0$, null),
  ('public._rv_log(uuid,text,jsonb,text,uuid)', 'known', 'ce4e0ae7fbec99a9b239f221712bd556', null);
-- _stock_guard(uuid,integer,text,date)
insert into _u_plan (fn, kind, a, b) values
  ('public._stock_guard(uuid,integer,text,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._stock_guard(p_item uuid, p_loc integer, p_grant text, p_date date DEFAULT NULL::date)
 RETURNS items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if not it.tracked then raise exception 'item_not_tracked'; end if;
  if p_date is not null then perform public.lock_check(p_date); end if;
  return it;
end $function$$r0_0$, null),
  ('public._stock_guard(uuid,integer,text,date)', 'known', 'a380080d4df172de3a1f755b65c00843', null);
-- _sup_balance(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public._sup_balance(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._sup_balance(p_supplier uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0)
       + coalesce((select sum(amount) from public.supplier_refunds where supplier_id = p_supplier and not voided), 0);
$function$$r0_0$, null),
  ('public._sup_balance(uuid)', 'known', 'a5964fd9457f19e6d79dd1d479f8ccd2', null);
-- _void_purchase_p13(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._void_purchase_p13(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._void_purchase_p13(p_id uuid, p_note text)
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
  perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)      -- one posting / payment / void at a time per supplier
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
          why := 'void_would_go_negative'; shorts := shorts || case when shorts = '' then '' else ', ' end || coalesce((select code from public.items where id = z.item_id and public._m132_own(items.org_unit_id) /* m132b:items */), '?');   -- bos82
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
end $function$$r0_0$, null),
  ('public._void_purchase_p13(uuid,text)', 'known', 'a184305d1e9103bddb619f2858e8dee3', null);
-- _wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public._wastage_post(p_item uuid, p_loc integer, p_bq numeric, p_reason text, p_note text, p_photo text, p_batch bigint, p_client uuid, p_by uuid, p_staff text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; wid uuid := gen_random_uuid(); lid bigint;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  begin
    lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
    insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
      values (wid, p_item, p_loc, p_bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, p_by, p_staff);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins, this one is the duplicate
    select id into lid from public.stock_ledger where p_client is not null and client_id = p_client and reason = 'wastage' order by id limit 1;
    if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    raise;
  end;
  if p_reason = 'unknown' then
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', it.name_bn || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, it.name_bn) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', p_bq);
end $function$$r0_0$, null),
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)', 'known', '977c0e0b97a6c5fd64bff7b04eac43e4', null);
-- acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_account_save(p_id bigint, p_code text, p_name_bn text, p_name_en text, p_type text, p_parent bigint DEFAULT NULL::bigint, p_active boolean DEFAULT true, p_sort integer DEFAULT NULL::integer, p_contra boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts; side text; par public.coa_accounts;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or length(p_name_bn) > 120 or p_name_en is null or length(btrim(p_name_en)) = 0 or length(p_name_en) > 120 then raise exception 'name_required'; end if;
  if p_parent is not null then
    select * into par from public.coa_accounts where id = p_parent;
    if not found or not par.is_group then raise exception 'bad_parent'; end if;
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
    if p_type is null or p_type not in ('asset', 'liability', 'equity', 'income', 'expense') then raise exception 'bad_type'; end if;
    if par.id is not null and par.type <> p_type then raise exception 'bad_parent'; end if;
    if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
    side := case when (p_type in ('asset', 'expense')) <> coalesce(p_contra, false) then 'debit' else 'credit' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, sort, created_by)
      values (p_code, btrim(p_name_bn), btrim(p_name_en), p_type, side, p_parent, coalesce(p_sort, 500), auth.uid()) returning * into a;
    return jsonb_build_object('id', a.id, 'code', a.code);
  end if;
  select * into a from public.coa_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if par.id is not null and (par.type <> a.type or par.id = a.id) then raise exception 'bad_parent'; end if;
  if not coalesce(p_active, true) then
    if a.is_system and exists (select 1 from public.acct_mappings where account_id = a.id) then raise exception 'account_in_use_by_mapping'; end if;
    if exists (select 1 from public.coa_accounts where parent_id = a.id and active) then raise exception 'has_active_children'; end if;
  end if;
  update public.coa_accounts set name_bn = btrim(p_name_bn), name_en = btrim(p_name_en), parent_id = coalesce(p_parent, parent_id), active = coalesce(p_active, active), sort = coalesce(p_sort, sort) where id = a.id;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $function$$r0_0$, null),
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'known', '9cfc4b0aff3117417d83fa0b3ff26503', null);
-- acct_mapping_set(text,bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_mapping_set(text,bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_mapping_set(p_key text, p_account bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_key is null or p_key !~ '^[a-z0-9_]{2,48}$' then raise exception 'bad_key'; end if;
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
  if not exists (select 1 from public.acct_mappings where key = p_key) and p_key not like 'exp\_%' then raise exception 'bad_key'; end if;
  insert into public.acct_mappings (key, account_id, updated_by) values (p_key, p_account, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('key', p_key, 'account_id', p_account);
end $function$$r0_0$, null),
  ('public.acct_mapping_set(text,bigint)', 'known', '174255f4dac51c1fd71820cb6408ecef', null);
-- acct_opening(jsonb,boolean,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_opening(p_lines jsonb, p_plug boolean DEFAULT false, p_memo text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); ln jsonb; x jsonb; td numeric := 0; tc numeric := 0; diff numeric; plug bigint; r public.journal_entries; id_ bigint; ty text;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r2 where r2.reverses_id = o.id)) then raise exception 'opening_exists'; end if;
  if exists (select 1 from public.journal_entries where entry_date < st and source_type <> 'opening') then raise exception 'postings_before_opening'; end if;
  ln := public._acct_resolve(p_lines, null);
  for x in select * from jsonb_array_elements(ln) loop
    select type into ty from public.coa_accounts where id = (x->>'account_id')::bigint;
    if ty in ('income', 'expense') then raise exception 'opening_balance_sheet_only'; end if;
    td := td + (x->>'debit')::numeric; tc := tc + (x->>'credit')::numeric;
  end loop;
  diff := round(td - tc, 2);
  if diff <> 0 then
    if not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
    select account_id into plug from public.acct_mappings where key = 'retained';
    if plug is null then raise exception 'mapping_missing:retained'; end if;
    ln := ln || jsonb_build_object('account_id', plug, 'debit', case when diff < 0 then -diff else 0 end, 'credit', case when diff > 0 then diff else 0 end, 'party_type', null, 'party_id', null, 'memo', 'balancing figure', 'location_id', null);
    if diff > 0 then tc := tc + diff; else td := td - diff; end if;
  end if;
  if td <= 0 then raise exception 'no_lines'; end if;
  if p_dry then return jsonb_build_object('dry', true, 'date', st, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  id_ := public._acct_write(st, null, 'opening', 'opening:' || coalesce(p_client::text, gen_random_uuid()::text), null, coalesce(nullif(btrim(p_memo), ''), 'Opening balances'), null, ln, null, p_client, null);
  return jsonb_build_object('id', id_, 'date', st, 'plug', diff);
end $function$$r0_0$, null),
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)', 'known', '6ed9f953d2d13665ffe41a5d75d34c3c', null);
-- acct_post_pending(boolean,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_post_pending(boolean,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; more boolean := false; ln jsonb; res jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; flagged int := 0; eid bigint; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 1500), 1), 5000);
        trial jsonb; skipped jsonb := '[]'; acc jsonb := '[]'; lk jsonb := '[]'; lw boolean := coalesce(public.rule_txt('period_lock_late_warn'), 'off') = 'on';   -- bos113
begin
  if not (public._acct_manage() or (auth.uid() is null and coalesce(current_setting('bos.autopost85', true), '') = 'on')) then raise exception 'not allowed'; end if;   -- bos85: the scheduler entry point has no signed-in person
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id)) /* scope133 */ order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then more := true; exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', d.entry_date); end if; continue; end if;   -- bos113
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
        if public._acct_locked(rdate) then locked := locked + 1; if lw and jsonb_array_length(lk) < 20 then lk := lk || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'date', rdate, 'reversal', true); end if; continue; end if;   -- bos113
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
  if lw and not p_dry and locked > 0 then   -- bos113: rule period_lock_late_warn = on: documents the scheduler could not book (their date is in a closed period) are no longer silent
    if exists (select 1 from public.exceptions x where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open') then
      update public.exceptions x set amount = locked where x.flag_code = 'late_docs_locked' and x.entry_date = public._acct_today() and x.status = 'open';
    else
      perform public._stock_exc((select min(l.id) from public.locations l), 'late_docs_locked', 'yellow',
        locked::text || ' নথি বই-এ ওঠেনি: তারিখ বন্ধ হিসাবকালে', locked::text || ' document(s) are not in the books: their date is in a closed period (reopen the period or post them by hand)', null, public._acct_today(), 'ACCOUNTS', locked);
    end if;
  end if;
  if p_dry then
    select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name_bn', name_bn, 'name_en', name_en, 'debit', dr, 'credit', cr) order by code), '[]'::jsonb), coalesce(sum(dr), 0), coalesce(sum(cr), 0)
      into trial, tot_d, tot_c from (select x->>'code' code, x->>'name_bn' name_bn, x->>'name_en' name_en, sum((x->>'debit')::numeric) dr, sum((x->>'credit')::numeric) cr from jsonb_array_elements(acc) x group by 1, 2, 3) z;
  end if;
  if to_regclass('public.staff_advances') is null then skipped := skipped || to_jsonb('staff_advances'::text); end if;
  if to_regclass('public.salary_payments') is null then skipped := skipped || to_jsonb('salary_payments'::text); end if;
  res := jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'cogs_missing', flagged,
    'errors', errors, 'more', more, 'skipped_sources', skipped) || case when lw then jsonb_build_object('locked_docs', lk) else '{}'::jsonb end;   -- bos113
  if p_dry then res := res || jsonb_build_object('preview', prev, 'trial', trial, 'total_debit', tot_d, 'total_credit', tot_c); end if;
  return res;
end $function$$r0_0$, null),
  ('public.acct_post_pending(boolean,integer)', 'known', '7f14a329e494717cca39e326267e6e07', null);
-- acct_status()
insert into _u_plan (fn, kind, a, b) values
  ('public.acct_status()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.acct_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); pend int := 0; lck int := 0; wt int := 0; er int := 0; erl jsonb := '[]'::jsonb;   -- bos72
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is not null then   -- bos72: documents not yet in the books (the same list acct_post_pending would work through)
    with dd as materialized (select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id))), /* scope133 */
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
    'entries', (select count(*) from public.journal_entries je where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(je.location_id))), 'accounts', (select count(*) from public.coa_accounts where active),
    'last_post', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),
    'last_post_at', (select max(created_at) from public.journal_entries where (created_by is not null or exists (select 1 from public.acct_autopost_runs85)) and source_type not in ('manual', 'opening')),   -- bos72 bos85: a scheduler run has no person
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl,   -- bos72
    'scheduler', jsonb_build_object('on', public.rule_on('acct_scheduler_on'), 'last_run', (select max(ran_at) from public.acct_autopost_runs85)));   -- bos85
end $function$$r0_0$, null),
  ('public.acct_status()', 'known', '0ec4a16d7f2d7227280832344eee7627', null);
-- artisan_list(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.artisan_list(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.artisan_list(p_include_retired boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._recipe_read() or public.has_grant('recipe_view') or public._artisan_mgr()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active) order by a.id) from public.artisans a where (p_include_retired or a.active) and public._m132_vis('artisans', a.org_unit_id, a.id::text, false) /* m132 */), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.artisan_list(boolean)', 'known', '80c857cff6dadbe00d644af2c40a5333', null);
-- assistant_health()
insert into _u_plan (fn, kind, a, b) values
  ('public.assistant_health()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.assistant_health()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  f jsonb := '[]'::jsonb; locs int[]; n bigint; n2 bigint; ev jsonb; r record; d date; today date := (now() at time zone 'Asia/Dhaka')::date;
  age int := coalesce(public.rule_num('assistant_closed_age_days'), 45)::int; sid bigint; miss text[]; k text; v jsonb; maxh numeric; last timestamptz; fin boolean;
  keys constant text[] := array['drawer_float', 'cash_tol', 'discount_limit', 'expense_max'];
begin
  if not public._assistant_health_ok() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into locs from public.locations l
   where coalesce(l.status, 'live') in ('live', 'setting_up') and (public.is_owner() or (public.has_grant('head_management') and ((select not public._org_on123()) or public._biz_ok123(l.id))) or public.can_loc(l.id));   /* scope133 */

  -- items
  select count(*), coalesce(jsonb_agg(code order by code) filter (where rn <= 5), '[]') into n, ev from (
    select i.code, row_number() over (order by i.code) rn from public.items i
     where i.is_active and coalesce(i.sellable, true) and not coalesce(i.hidden, false) and i.retired_at is null and (i.sell_price is null or i.sell_price <= 0)) z;
  if n > 0 then f := f || public._ah('items_no_price', 'warn', 'দাম ছাড়া বিক্রয়যোগ্য আইটেম', 'Sellable items without a price', n || ' active sellable items have no selling price', 'bulkitems', jsonb_build_object('count', n, 'sample', ev)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.unit is null and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_no_unit', 'warn', 'একক ছাড়া আইটেম', 'Items without a unit', n || ' active items have no unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.items i where i.is_active and i.retired_at is null and i.tracked and i.base_unit is null;
  if n > 0 then f := f || public._ah('items_tracked_no_base', 'warn', 'স্টক-হিসাবি আইটেমের মূল একক নেই', 'Stock-tracked items without a base unit', n || ' tracked items have no base unit', 'bulkitems', jsonb_build_object('count', n)); end if;
  select count(*) filter (where i.tracked), count(*) into n, n2 from public.items i where i.is_active and i.retired_at is null;
  if n2 > 0 and n = 0 then f := f || public._ah('items_none_tracked', 'info', 'কোনো আইটেমে স্টক-হিসাব চালু নেই', 'No item has stock tracking on', 'Stock pages and stock reports stay empty until items are tracked', 'bulkitems', jsonb_build_object('active_items', n2)); end if;

  -- places: settings sheet and key limits (showrooms)
  for r in select l.id, l.code, l.kind from public.locations l where l.id = any (locs) order by l.id loop
    sid := public._sheet_in_force(r.id, today);
    if not exists (select 1 from public.settings_sheets s where s.location_id = r.id and s.status = 'approved') then
      f := f || public._ah('loc_no_sheet', 'warn', 'জায়গার সেটিংস-শিট অনুমোদিত নয়', 'Place has no approved settings sheet', r.code || ': no approved Location Settings Sheet (0-1)', 'locset', jsonb_build_object('location_id', r.id, 'code', r.code));
    end if;
    if coalesce(r.kind, 'showroom') = 'showroom' then
      miss := '{}';
      foreach k in array keys loop
        if sid is null then select value into v from public.location_settings where location_id = r.id and key = k; else select value into v from public.settings_values where sheet_id = sid and key = k; end if;
        if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then miss := miss || k; end if;
        v := null;
      end loop;
      if cardinality(miss) > 0 then
        f := f || public._ah('loc_limit_blank', 'warn', 'জায়গার সীমা ফাঁকা (তথ্য দরকার)', 'Blank limits at a place (data needed)', r.code || ': ' || array_to_string(miss, ', '), 'locset', jsonb_build_object('location_id', r.id, 'code', r.code, 'missing', to_jsonb(miss)));
      end if;
    end if;
  end loop;

  -- rollout
  select count(*) into n from public.form_rollout fr where fr.mode = 'paper' and fr.location_id = any (locs)
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id);
  if n > 0 then f := f || public._ah('paper_never_app', 'info', 'কাগজে চলা ফর্ম, অ্যাপে কখনো লেখা হয়নি', 'Forms on paper never tried in the app', n || ' form x place cells are on Paper and have no app entry yet', 'rollout', jsonb_build_object('count', n)); end if;
  if public.rule_on('parallel_compare_on') then
    select count(*), coalesce(jsonb_agg(fr.form_code || '@' || fr.location_id) filter (where true), '[]') into n, ev from public.form_rollout fr
     where fr.mode = 'parallel' and fr.location_id = any (locs) and not exists (select 1 from public.comparison_pairs p where p.form_code = fr.form_code and p.is_active);
    if n > 0 then f := f || public._ah('parallel_no_pair', 'warn', 'পাশাপাশি চলছে কিন্তু তুলনার জোড়া নেই', 'Parallel without a comparison pair', n || ' parallel cells cannot record a comparison day', 'parallel', jsonb_build_object('count', n, 'cells', ev)); end if;
  end if;
  select count(*) into n from public.form_rollout fr where fr.mode = 'app' and fr.location_id = any (locs) and fr.changed_at < now() - interval '14 days'
     and not exists (select 1 from public.entries e where e.form_code = fr.form_code and e.location_id = fr.location_id and e.created_at > now() - interval '14 days');
  if n > 0 then f := f || public._ah('app_unused', 'info', 'অ্যাপে বদলানো ফর্ম ১৪ দিন ব্যবহার হয়নি', 'Forms moved to the app but unused for 14 days', n || ' form x place cells', 'rollout', jsonb_build_object('count', n)); end if;

  -- rule conflicts (each justified in docs/ASSISTANT_AUDIT.md section 6)
  if coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'grn' then
    if public.rule_on('forms_post_to_ledger') then
      f := f || public._ah('grn_double_count', 'warn', 'GRN ও ক্রয় পেজ দুটোই স্টক বাড়াতে পারে', 'GRN and the purchase page may both add stock', 'grn_receipt_source = grn and forms_post_to_ledger ON: the purchase page still posts purchase_in; check receipt duplicates', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', true));
    else
      f := f || public._ah('grn_source_no_effect', 'info', 'GRN-কে উৎস করা হয়েছে, কিন্তু ফর্ম লেজারে যায় না', 'GRN chosen as the source but forms do not post', 'grn_receipt_source = grn while forms_post_to_ledger is OFF: the choice has no effect', 'switchboard', jsonb_build_object('grn_receipt_source', 'grn', 'forms_post_to_ledger', false));
    end if;
  end if;
  if public.rule_on('vat_on') and public.rule_num('vat_rate') is null then
    f := f || public._ah('vat_no_rate', 'bad', 'ভ্যাট চালু কিন্তু হার নেই', 'VAT is on but the rate is blank', 'vat_on ON, vat_rate blank', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('production_requires_recipe') and not exists (select 1 from public.recipes rc where rc.active) then
    f := f || public._ah('production_no_recipe', 'bad', 'রেসিপি বাধ্যতামূলক কিন্তু কোনো রেসিপি নেই', 'Recipe required but no active recipe', 'production_requires_recipe ON: every production is refused', 'recipes', '{}'::jsonb);
  end if;
  if public.rule_on('recipe_waste_required') then
    select count(*) into n from public.recipe_lines rl join public.recipes rc on rc.id = rl.recipe_id where rc.active and rl.active and rl.waste_pct is null;
    if n > 0 then f := f || public._ah('recipe_waste_blank', 'warn', 'রেসিপির লাইনে অপচয় % নেই', 'Recipe lines without waste %', n || ' active lines: production with them is refused', 'recipes', jsonb_build_object('count', n)); end if;
  end if;
  select count(*) into n from public.recipes rc where rc.active and (rc.yield_qty is null or rc.yield_qty <= 0);
  if n > 0 then f := f || public._ah('recipe_no_yield', 'warn', 'রেসিপির উৎপাদন-পরিমাণ (yield) নেই', 'Recipes without yield', n || ' active recipes', 'recipes', jsonb_build_object('count', n)); end if;
  if public.rule_on('blind_count_on') and not exists (select 1 from public.blind_count_cfg b where b.enabled) then
    f := f || public._ah('blind_no_form', 'info', 'ব্লাইন্ড কাউন্ট চালু, কিন্তু কোনো ফর্মে নয়', 'Blind count is on for no form', 'blind_count_on ON but no form x place is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if public.rule_on('pin_signature_on') and not exists (select 1 from public.pin_sig_cfg p where p.enabled) then
    f := f || public._ah('pin_no_form', 'info', 'পিন-সই চালু, কিন্তু কোনো ফর্মে নয়', 'PIN signature is on for no form', 'pin_signature_on ON but no form is switched on', 'switchboard', '{}'::jsonb);
  end if;
  if coalesce(public.rule_txt('stock_negative_mode'), 'warn') = 'allow' and not public.rule_on('block_expired_sale') then
    f := f || public._ah('stock_guards_off', 'info', 'বিক্রিতে স্টকের কোনো বাধা নেই (দুর্বল নিয়ন্ত্রণ)', 'No stock guard at the till (weak control)', 'stock_negative_mode = allow and block_expired_sale OFF', 'switchboard', '{}'::jsonb);
  end if;

  -- books and day book
  d := public.rpt_date(public.rule_txt('period_closed_until'));
  if d is null then f := f || public._ah('books_never_closed', 'warn', 'হিসাব কখনো বন্ধ (লক) করা হয়নি', 'Books were never closed', 'period_closed_until is blank: any old date can still be changed', 'rules', '{}'::jsonb);
  elsif d < today - age then f := f || public._ah('books_closed_old', 'info', 'হিসাব বন্ধের তারিখ পুরনো', 'Books-closed date is old', 'closed until ' || d || ' (' || (today - d) || ' days ago)', 'rules', jsonb_build_object('closed_until', d, 'days', today - d)); end if;
  if public.rule_on('daybook_enabled') then
    if public._db_start() is null then f := f || public._ah('daybook_no_start', 'warn', 'দৈনিক খাতার শুরুর তারিখ নেই', 'Day book has no start date', 'running cash / bank / mobile totals are unknown', 'daybook', '{}'::jsonb);
    elsif public.rule_num('daybook_open_cash') is null or public.rule_num('daybook_open_bank') is null or public.rule_num('daybook_open_mobile') is null then
      f := f || public._ah('daybook_no_opening', 'info', 'শুরুর ক্যাশ/ব্যাংক/মোবাইল ব্যালান্স ফাঁকা', 'Opening cash / bank / mobile balance blank', 'closing balances cannot be shown (data needed)', 'daybook', '{}'::jsonb);
    end if;
  end if;
  if public.rule_txt('fiscal_year_start_month') is null or public.rule_txt('week_start') is null then
    f := f || public._ah('calendar_defaults', 'info', 'অর্থবছর / সপ্তাহের শুরু ঠিক করা হয়নি', 'Fiscal year / week start not set', 'reports use the calendar year and Saturday', 'switchboard', '{}'::jsonb);
  end if;

  -- people
  select count(*) into n from public.profiles p where p.status = 'pending';
  if n > 0 then f := f || public._ah('staff_pending', 'warn', 'নতুন স্টাফ অনুমোদনের অপেক্ষায়', 'Staff accounts waiting for approval', n || ' pending', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active'
     and not exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code in ('owner', 'management'))
     and not exists (select 1 from public.user_locations ul where ul.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_location', 'warn', 'সক্রিয় স্টাফের কোনো জায়গা নেই', 'Active staff without a place', n || ' people cannot work anywhere', 'staff', jsonb_build_object('count', n)); end if;
  select count(*) into n from public.profiles p where p.status = 'active' and not exists (select 1 from public.user_roles ur where ur.user_id = p.id);
  if n > 0 then f := f || public._ah('staff_no_role', 'warn', 'সক্রিয় স্টাফের ভূমিকা নেই', 'Active staff without a role', n || ' people', 'staff', jsonb_build_object('count', n)); end if;
  foreach k in array array['release_decide', 'wastage_approve', 'change_approve'] loop
    if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where g.grant_code = k and (g.valid_until is null or g.valid_until > now())
                     and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
       and not exists (select 1 from public.rule_grants rg where rg.grant_code = k and rg.allowed and rg.role_code <> 'owner') then
      f := f || public._ah('only_owner_' || k, 'info', 'এই অনুমোদন শুধু মালিক দিতে পারেন', 'Only the owner can decide this', k || ': nobody else holds it (owner absent = waiting)', 'delegation', jsonb_build_object('grant', k));
    end if;
  end loop;
  if not exists (select 1 from public.user_grants g join public.profiles p on p.id = g.user_id and p.status = 'active' where (g.grant_code like 'report\_%' or g.grant_code = 'view_reports') and (g.valid_until is null or g.valid_until > now())
                   and not exists (select 1 from public.user_roles ur where ur.user_id = g.user_id and ur.role_code = 'owner'))
     and not exists (select 1 from public.rule_grants rg where (rg.grant_code like 'report\_%' or rg.grant_code = 'view_reports') and rg.allowed and rg.role_code <> 'owner') then
    f := f || public._ah('reports_owner_only', 'info', 'রিপোর্ট শুধু মালিক দেখেন', 'Only the owner sees reports', 'no report grant is given to anyone else', 'delegation', '{}'::jsonb);
  end if;

  -- parties
  select count(*) into n from public.suppliers s where s.active and s.credit_days is null;
  if n > 0 then f := f || public._ah('supplier_no_credit_days', 'info', 'সরবরাহকারীর বাকির দিন নেই', 'Suppliers without credit days', n || ' suppliers: overdue cannot be worked out for them', 'settings2/suppliers', jsonb_build_object('count', n)); end if;
  select count(*), coalesce(round(sum(c.balance - c.credit_limit), 2), 0) into n, n2 from public.customer_dues() c where c.credit_limit is not null and c.balance > c.credit_limit;
  if n > 0 then f := f || public._ah('customers_over_limit', 'warn', 'বাকির সীমা পেরোনো গ্রাহক', 'Customers over their credit limit', n || ' customers, ' || n2 || ' over in total', 'dues', jsonb_build_object('count', n, 'over_total', n2)); end if;

  -- optional modules (only when installed)
  if to_regclass('public.backup_runs') is not null then
    maxh := coalesce(public.rule_num('backup_max_age_hours'), 36);
    execute 'select max(finished_at) from public.backup_runs where status = ''ok''' into last;
    if last is null then f := f || public._ah('backup_none', 'warn', 'কোনো সফল ব্যাকআপ নেই', 'No successful backup recorded', 'backup_runs has no ok run', 'backup', '{}'::jsonb);
    elsif last < now() - make_interval(hours => maxh::int) then f := f || public._ah('backup_stale', 'bad', 'ব্যাকআপ পুরনো', 'Backup is stale', 'last ok backup ' || round(extract(epoch from now() - last) / 3600) || ' hours ago (limit ' || maxh || ')', 'backup', jsonb_build_object('hours', round(extract(epoch from now() - last) / 3600), 'limit', maxh)); end if;
  end if;
  if exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and public.rule_txt('accounting_start_date') is null then
    f := f || public._ah('accounting_no_start', 'bad', 'হিসাব (অ্যাকাউন্টিং) চালু কিন্তু শুরুর তারিখ / প্রারম্ভিক ব্যালান্স নেই', 'Accounting on without a start date / opening balances', 'accounting_on ON, accounting_start_date blank', 'accounts', '{}'::jsonb);
  elsif exists (select 1 from public.rules where key = 'accounting_on') and public.rule_on('accounting_on') and to_regclass('public.journal_entries') is not null then
    execute 'select exists (select 1 from public.journal_entries o where o.source_type = ''opening'' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id))' into fin;
    if not fin then f := f || public._ah('accounting_no_opening', 'warn', 'হিসাব চালু কিন্তু প্রারম্ভিক ব্যালান্স (opening journal) নেই', 'Accounting on without an opening journal', 'no active opening journal (phase40 acct_opening)', 'accounts', '{}'::jsonb); end if;
  end if;
  return f;
end $function$$r0_0$, null),
  ('public.assistant_health()', 'known', '7adfcc394b57315d37daa4f1a2634a23', null);
-- bank_recon_candidates(bigint,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_candidates(bigint,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_candidates(p_line bigint, p_days integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('entry_id', c.entry_id, 'line_no', c.line_no, 'date', c.entry_date, 'memo', c.memo, 'source_type', c.source_type,
      'source_id', c.source_id, 'amount', c.amount, 'days_off', c.days_off, 'ref_hit', c.ref_hit)) from (select * from public._a53_cands(p_line, p_days) limit 20) c), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.bank_recon_candidates(bigint,integer)', 'known', '054be453a006c4d3e6aae86837f10377', null);
-- bank_recon_lines(bigint,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_lines(bigint,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_lines(p_account bigint, p_status text DEFAULT 'all'::text, p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  if p_status not in ('all', 'matched', 'unmatched') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(j order by (j->>'date') desc, (j->>'id')::bigint desc) from (
    select jsonb_build_object('id', l.id, 'date', l.line_date, 'amount', l.amount, 'reference', l.reference, 'description', l.description,
      'matched', m.id is not null, 'entry_id', m.entry_id, 'line_no', m.line_no, 'how', m.how) j
    from public.bank_statement_lines l left join public.bank_recon_matches m on m.line_id = l.id and m.active
    where l.account_id = p_account and (p_status = 'all' or (p_status = 'matched') = (m.id is not null))
    order by l.line_date desc, l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.bank_recon_lines(bigint,text,integer)', 'known', '726a495058c1b0a566ed454d4720c08a', null);
-- bank_recon_match(bigint,bigint,integer,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_match(bigint,bigint,integer,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_match(p_line bigint, p_entry bigint, p_line_no integer, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare id_ bigint;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  id_ := public._a53_match1(p_line, p_entry, p_line_no, 'manual', p_note);
  return jsonb_build_object('match_id', id_);
end $function$$r0_0$, null),
  ('public.bank_recon_match(bigint,bigint,integer,text)', 'known', '8790e217569d918318a64339bb0f2a05', null);
-- bank_recon_match_many(jsonb,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_match_many(jsonb,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_match_many(p_pairs jsonb, p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p jsonb; ok int := 0; fails jsonb := '[]'::jsonb;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_pairs is null or jsonb_typeof(p_pairs) <> 'array' or jsonb_array_length(p_pairs) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_pairs) > 500 then raise exception 'too_many_rows'; end if;
  for p in select * from jsonb_array_elements(p_pairs) loop
    begin
      perform public._a53_match1((p->>'line_id')::bigint, (p->>'entry_id')::bigint, (p->>'line_no')::int, 'suggested', null);
      ok := ok + 1;
      if p_dry then raise exception 'dry_rollback'; end if;
    exception when others then
      if sqlerrm = 'dry_rollback' then null; else fails := fails || jsonb_build_object('line_id', p->'line_id', 'why', sqlerrm); end if;
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'ok', ok, 'failed', jsonb_array_length(fails), 'failures', fails);
end $function$$r0_0$, null),
  ('public.bank_recon_match_many(jsonb,boolean)', 'known', '6ee94ee0bc05fe82f2dd0d399e06eedc', null);
do $u535$
declare f record; r record; cur text; body text; rbody text; miss text := ''; st text; nfix int := 0; ok boolean;
begin
  -- Every function of this file is looked at first. A function is in one of these states: DONE (already the merged text), KNOWN (a known older text of one of the two lines: it is replaced by the
  -- merged text), PATCH (not a known text, but every patch site of the fallback is found), MISSING (nothing fits). ALL missing ones are listed in ONE message and nothing is changed.
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then continue; end if;     -- the function does not exist yet: it is created below
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then continue; end if;
    ok := exists (select 1 from _u_plan where fn = f.fn and kind = 'old');
    body := cur;
    for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
      if position(r.b in body) > 0 then continue; end if;
      if position(r.a in body) = 0 then ok := false; exit; end if;
      body := overlay(body placing r.b from position(r.a in body) for length(r.a));
    end loop;
    if not ok then miss := miss || E'\n  ' || f.fn || ' (the text in this database is not one of the known texts and the patch sites are not all there; md5 ' || md5(cur) || ')'; end if;
  end loop;
  if miss <> '' then raise exception 'phase535: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase535: merged text of the two lines', cur);
    if exists (select 1 from _u_plan where fn = f.fn and kind = 'known' and a = md5(cur)) then
      execute rbody;
    else
      body := cur;
      for r in select * from _u_plan where fn = f.fn and kind = 'old' order by seq loop
        if position(r.b in body) > 0 then continue; end if;
        body := overlay(body placing r.b from position(r.a in body) for length(r.a));
      end loop;
      execute body;
    end if;
    nfix := nfix + 1;
  end loop;
  raise notice 'phase535: % function(s) changed', nfix;
end $u535$;
drop table if exists _u_plan;

-- ============================================================================
-- End of DELTA part 1 of 2.
