-- ============================================================================
-- FRESH part 2 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase12.sql
-- ============================================================
-- BOS tool · Phase 12 (W0 carry-over, owner's list HANDOVER §8 items 1-5, 7-12, 14): items / stock / purchase finishing work.
-- Run AFTER phase8, phase9, phase10 (phase11 may come before or after; nothing here depends on it).
-- ADDITIVE and IDEMPOTENT: safe to paste whole and run again. Nothing existing is dropped. Functions that are re-created keep ALL their old behaviour
-- (the old text is copied and extended); where another phase may also have replaced a function, a wrapper is used instead of a copy.
--
-- What is here
--   1  items.details (text) + apply_item_patch learns it (wrapper around the existing function, so any later column added by another phase is kept)
--   2  items_with_cost(): item costs for people who hold only the grant view_cost (item_costs RLS is NOT changed)
--   8  photos for stock / purchase: storage prefixes STOCK/<loc>/... and PURCHASE/<loc>/... decided by grants (photo_ok re-created, all old prefixes unchanged)
--   9  emergency keys for stock_count_adjust / stock_transfer / stock_issue / stock_production (all OFF by default)
--  10  wastage maker-checker: rule wastage_approval_limit (empty = off); above it the write-off waits for ANOTHER person holding the grant wastage_approve
--  11  supplier refund (cash back from a supplier) and sale_return (restock, batch aware, reduces the customer's due first, or refunds)
--  12  rule block_expired_sale (default OFF): on = a sale from an expired batch is refused; off = the red exception 'sold_expired' as before
--  14  stock_ledger.ref_id is no longer readable by location users directly (column privilege); stock_ledger_rows() still returns it where allowed
-- No business number is invented: the new limit is empty, the new switches are off (block_expired_sale, every em_*), sale_return_due_first is on only
-- because refunding the cash of a customer who still owes us would be silly; the owner can switch it off.
-- ============================================================

-- ---------- (1) items.details ----------
alter table public.items add column if not exists details text;

do $$
begin
  if position('bos12-details' in pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure)) = 0 then
    drop function if exists public._apply_item_patch_base(uuid, jsonb);
    alter function public.apply_item_patch(uuid, jsonb) rename to _apply_item_patch_base;
    execute $f$
      create function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
      language plpgsql security definer set search_path = public as $b$
      declare iid uuid;   -- bos12-details: everything else is done by the previous version, kept as _apply_item_patch_base
      begin
        iid := public._apply_item_patch_base(p_item, p_patch);
        if p_patch ? 'details' then
          update public.items set details = left(nullif(btrim(p_patch->>'details'), ''), 2000) where id = iid;
        end if;
        return iid;
      end $b$ $f$;
  end if;
end $$;
revoke all on function public.apply_item_patch(uuid, jsonb), public._apply_item_patch_base(uuid, jsonb) from public, anon, authenticated;

-- ---------- (2) costs for view_cost holders ----------
create or replace function public.items_with_cost() returns table (item_id uuid, cost_price numeric)
language sql stable security definer set search_path = public as $$
  select c.item_id, c.cost_price from public.item_costs c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;
revoke all on function public.items_with_cost() from public, anon;
grant execute on function public.items_with_cost() to authenticated;

-- ---------- rules, grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('wastage_approval_limit', 'stock', 'number', null, null, null, 0, 1000000000, 'এর বেশি পরিমাণ নষ্ট দেখাতে হলে আরেকজনের অনুমোদন লাগবে (বেস এককে)', 'এর বেশি quantity নষ্ট দেখাতে হলে আরেকজনের approval লাগবে (base unit এ)', 'A wastage above this quantity waits for a second person to approve (in the item base unit)', 'Empty = Data needed = off (every write-off posts at once). The owner is never held back', 103),
 ('wastage_limit_daily_sum', 'stock', 'switch', 'true', null, null, null, null, 'একই ব্যক্তির একই দিনে একই পণ্যের নষ্ট মালের যোগফলও সীমার সাথে মেলানো হবে', 'একই person এর একই দিনে একই item এর wastage এর যোগফলও limit এর সাথে মেলানো হবে', 'The same person''s wastage of the same item on the same day is added up against the limit (stops splitting a big write-off)', 'Only matters when wastage_approval_limit is set', 105),
 ('block_expired_sale', 'stock', 'switch', 'false', null, null, null, null, 'মেয়াদোত্তীর্ণ মাল বিক্রি আটকানো', 'মেয়াদোত্তীর্ণ মাল sale আটকানো', 'Block selling expired stock', 'Off = the sale goes through and the owner gets a red line (as before). On = the sale is refused. A sale that syncs late from an offline phone is never refused', 104),
 ('sale_return_due_first', 'pos', 'switch', 'true', null, null, null, null, 'বিক্রি ফেরতে আগে গ্রাহকের বাকি কমবে, বাকি টাকা ফেরত', 'Sale return এ আগে customer এর due কমবে, বাকি টাকা ফেরত', 'A sale return first reduces what the customer owes; only the rest is refunded', 'Off = the whole value is refunded in cash / mobile / card', 90),
 ('em_stock_count_adjust', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: গণনা অনুযায়ী স্টক ঠিক', 'জরুরি request চলবে: count অনুযায়ী stock ঠিক', 'Emergency allowed for: adjusting stock to a count', 'Off by default', 127),
 ('em_stock_transfer', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: মাল পাঠানো / গ্রহণ', 'জরুরি request চলবে: মাল transfer / receive', 'Emergency allowed for: sending / receiving stock', 'Off by default', 128),
 ('em_stock_issue', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদনে কাঁচামাল দেওয়া', 'জরুরি request চলবে: production এ কাঁচামাল issue', 'Emergency allowed for: issuing material to production', 'Off by default', 129),
 ('em_stock_production', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদিত মাল স্টকে তোলা', 'জরুরি request চলবে: production এর মাল stock এ তোলা', 'Emergency allowed for: posting production into stock', 'Off by default', 130),
 ('em_sale_return', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: বিক্রি ফেরত নেওয়া', 'জরুরি request চলবে: sale return নেওয়া', 'Emergency allowed for: taking a sale return', 'Off by default', 131)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('wastage_approve', 'stock', 47, 'বড় নষ্ট মাল বাদ দেওয়া অনুমোদন', 'বড় wastage write-off approve', 'Approve a large wastage write-off', 'once', null),
   ('sale_return', 'pos', 11, 'বিক্রি ফেরত নেওয়া', 'Sale return নেওয়া', 'Take a sale return', 'once', 'em_sale_return')
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('wastage_approve', 'management'),
    ('sale_return', 'management'), ('sale_return', 'showroom_manager')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- (9) the four stock grants now name their emergency switch (an owner's own choice is never overwritten: only a still-empty one is filled)
update public.grant_defs set emergency_rule = 'em_' || grant_code where grant_code in ('stock_count_adjust', 'stock_transfer', 'stock_issue', 'stock_production') and emergency_rule is null;

-- ---------- (8) photos: STOCK / PURCHASE prefixes ----------
-- path = <PREFIX or form code>/<location id>/<file>.jpg ; the old form-code prefixes behave exactly as before.
create or replace function public.photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active()
    and split_part(p_name, '/', 2) ~ '^[0-9]+$'
    and public.can_loc(split_part(p_name, '/', 2)::int)
    and case split_part(p_name, '/', 1)
      when 'STOCK' then
        case when p_action = 'view' then true          -- anyone who works at that location may see a stock photo (wastage, count)
             else (public.has_grant('wastage_write_off', split_part(p_name, '/', 2)::int) or public.has_grant('stock_count_adjust', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_transfer', split_part(p_name, '/', 2)::int) or public.has_grant('stock_issue', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_production', split_part(p_name, '/', 2)::int) or public.has_grant('stock_opening', split_part(p_name, '/', 2)::int)) end
      when 'PURCHASE' then
        case when p_action = 'view' then public._pur_ok(split_part(p_name, '/', 2)::int)      -- a bill photo shows costs: only the purchase people
             else (public.has_grant('purchase_entry', split_part(p_name, '/', 2)::int) or public.has_grant('purchase_return', split_part(p_name, '/', 2)::int)
                   or public.has_grant('supplier_pay', split_part(p_name, '/', 2)::int)) end
      else public.can_do(split_part(p_name, '/', 1), p_action) end;
$$;
revoke all on function public.photo_ok(text, text) from public, anon;
grant execute on function public.photo_ok(text, text) to authenticated;

-- ---------- (14) stock_ledger.ref_id: not readable directly (a purchase bill id would open a bill) ----------
revoke select on public.stock_ledger from authenticated;
grant select (id, item_id, location_id, qty_delta, reason, ref_type, batch_id, reverses_id, made_at, note, created_by, created_at) on public.stock_ledger to authenticated;

-- ---------- (12) stock_post: optional block of expired stock, and a sale return puts goods back into its batch ----------
-- identical to phase10 except the two marked places
create or replace function public.stock_post(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_ref_type text default null, p_ref_id text default null,
  p_unit_cost numeric default null, p_batch bigint default null, p_made_at timestamptz default null, p_note text default null,
  p_reverses bigint default null, p_neg text default 'full', p_sale uuid default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false;
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale'); end if;           -- (12) read once
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
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
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
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
end $$;

-- ---------- (10) wastage maker-checker ----------
create table if not exists public.wastage_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0 and qty between 0 and 1000000000000),          -- base unit
  reason_code text not null,
  note text, photo text,
  batch_id bigint,                                                   -- no foreign key: keeps the ledger tables free of dependants
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  wastage_id uuid
);
create index if not exists wastage_requests_open on public.wastage_requests (location_id, status);
drop trigger if exists audit_wastage_requests on public.wastage_requests;
create trigger audit_wastage_requests after insert or update on public.wastage_requests for each row execute function public.log_change('id');
alter table public.wastage_requests enable row level security;
drop policy if exists wastage_requests_read on public.wastage_requests;
create policy wastage_requests_read on public.wastage_requests for select to authenticated
  using (public.can_loc(location_id) and (requested_by = auth.uid() or public.has_grant('wastage_approve', location_id)));
revoke all on public.wastage_requests from public, anon, authenticated;
grant select on public.wastage_requests to authenticated;

-- the posting itself (shared by a direct write-off and an approved request). Internal.
create or replace function public._wastage_post(p_item uuid, p_loc int, p_bq numeric, p_reason text, p_note text, p_photo text, p_batch bigint,
  p_client uuid, p_by uuid, p_staff text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; wid uuid := gen_random_uuid(); lid bigint;
begin
  select * into it from public.items where id = p_item;
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
end $$;

-- write off wasted stock (same behaviour as phase10) + maker-checker above the owner's limit
create or replace function public.stock_wastage(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_note text default null, p_photo text default null,
  p_unit text default null, p_client uuid default null, p_batch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; lim numeric; sid text; alim numeric; rid uuid; rq public.wastage_requests; dsum numeric := 0; dd date := (now() at time zone 'Asia/Dhaka')::date;
begin
  it := public._stock_guard(p_item, p_loc, 'wastage_write_off', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = 'wastage' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    select * into rq from public.wastage_requests where client_id = p_client;
    if found then
      if rq.requested_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id);
    end if;
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  lim := public.rule_num('wastage_photo_above');
  if lim is not null and bq > lim and nullif(btrim(p_photo), '') is null then raise exception 'photo_required'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if not public._may('wastage_write_off', p_loc, 'wastage:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if p_batch is not null and not exists (select 1 from public.stock_batches where id = p_batch and item_id = p_item and location_id = p_loc) then raise exception 'batch_not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  alim := public.rule_num('wastage_approval_limit');
  if alim is not null and public.rule_on('wastage_limit_daily_sum') then        -- today's wastage of this person for this item here, posted + still pending
    select coalesce((select sum(w.qty) from public.stock_wastage w where w.created_by = auth.uid() and w.item_id = p_item and w.location_id = p_loc and (w.made_at at time zone 'Asia/Dhaka')::date = dd), 0)
         + coalesce((select sum(r.qty) from public.wastage_requests r where r.requested_by = auth.uid() and r.item_id = p_item and r.location_id = p_loc and r.status = 'pending' and (r.requested_at at time zone 'Asia/Dhaka')::date = dd), 0) into dsum;
  end if;
  if alim is not null and (bq > alim or dsum + bq > alim) and not public.is_owner() then
    begin
      insert into public.wastage_requests (client_id, item_id, location_id, qty, reason_code, note, photo, batch_id, requested_by, requested_staff)
        values (p_client, p_item, p_loc, bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, auth.uid(), sid) returning id into rid;
    exception when unique_violation then
      select * into rq from public.wastage_requests where p_client is not null and client_id = p_client;
      if found and rq.requested_by = auth.uid() then return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id); end if;
      raise;
    end;
    perform public._stock_exc(p_loc, 'wastage_pending', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ — অনুমোদনের অপেক্ষায় (' || bq::text || ')',
      coalesce(it.name_en, it.name_bn) || ': a large wastage write-off is waiting for approval (' || bq::text || ')');
    return jsonb_build_object('pending', true, 'request_id', rid, 'qty', bq);
  end if;
  return public._wastage_post(p_item, p_loc, bq, p_reason, p_note, p_photo, p_batch, p_client, auth.uid(), sid);
end $$;

-- a DIFFERENT person with the grant wastage_approve (or the owner) decides. Approving posts the write-off now.
create or replace function public.wastage_decide(p_id uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests; sid text; res jsonb; it public.items;
begin
  select * into r from public.wastage_requests where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) or not public.has_grant('wastage_approve', r.location_id) then raise exception 'not allowed'; end if;
  perform 1 from public.wastage_requests where id = p_id for update;
  select * into r from public.wastage_requests where id = p_id;
  if r.status <> 'pending' then
    if r.status = (case when p_approve then 'approved' else 'rejected' end) then return jsonb_build_object('dup', true, 'status', r.status); end if;
    raise exception 'already_decided';
  end if;
  if r.requested_by = auth.uid() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then
    res := public._wastage_post(r.item_id, r.location_id, r.qty, r.reason_code, coalesce(r.note, '') || case when r.note is null then '' else ' · ' end || 'approved by ' || coalesce(sid, '?'),
                                r.photo, r.batch_id, r.client_id, r.requested_by, r.requested_staff);
    update public.wastage_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(nullif(btrim(p_note), ''), 300),
      wastage_id = nullif(res->>'id', '')::uuid where id = p_id;
    return jsonb_build_object('status', 'approved') || res;
  end if;
  update public.wastage_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  select * into it from public.items where id = r.item_id;
  perform public._stock_exc(r.location_id, 'wastage_rejected', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ নামঞ্জুর — ' || left(btrim(p_note), 100),
    coalesce(it.name_en, it.name_bn) || ': a large wastage write-off was rejected — ' || left(btrim(p_note), 100));
  return jsonb_build_object('status', 'rejected');
end $$;

-- the requester takes a pending request back
create or replace function public.wastage_cancel(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests;
begin
  select * into r from public.wastage_requests where id = p_id for update;
  if not found or r.requested_by <> auth.uid() then raise exception 'not allowed'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if r.status <> 'pending' then raise exception 'already_decided'; end if;
  update public.wastage_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- the waiting list: approvers see every pending request of their locations, anyone sees their own
create or replace function public.wastage_pending(p_loc int default null, p_status text default 'pending')
returns table (id uuid, item_id uuid, code text, name_bn text, name_en text, location_id int, qty numeric, base_unit text, reason_code text, note text, photo text,
               status text, requested_staff text, requested_at timestamptz, mine boolean, can_decide boolean, decision_note text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select r.id, r.item_id, i.code, i.name_bn, i.name_en, r.location_id, r.qty, public._item_base(i.id), r.reason_code, r.note, r.photo, r.status, r.requested_staff, r.requested_at,
           r.requested_by = auth.uid(), (r.status = 'pending' and r.requested_by <> auth.uid() and public.has_grant('wastage_approve', r.location_id)), r.decision_note
    from public.wastage_requests r join public.items i on i.id = r.item_id
    where public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc) and (p_status is null or r.status = p_status)
      and (r.requested_by = auth.uid() or public.has_grant('wastage_approve', r.location_id))
    order by r.requested_at desc limit 200;
end $$;

-- ---------- (11a) supplier refund: cash back from a supplier, reduces the supplier's credit ----------
create table if not exists public.supplier_refunds (
  id bigserial primary key,
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  mode text not null check (mode in ('cash', 'mobile', 'card', 'bank')),
  wallet text, ref text,
  amount numeric not null check (amount > 0 and amount between 0 and 1000000000000),
  refunded_at timestamptz not null default now(),
  reason_code text, note text,
  voided boolean not null default false, void_note text, void_by uuid,
  created_by uuid, created_staff text, client_id uuid
);
create index if not exists supplier_refunds_sup on public.supplier_refunds (supplier_id) where not voided;
create unique index if not exists supplier_refunds_client on public.supplier_refunds (client_id) where client_id is not null;
drop trigger if exists audit_supplier_refunds on public.supplier_refunds;
create trigger audit_supplier_refunds after insert or update on public.supplier_refunds for each row execute function public.log_change('id');
alter table public.supplier_refunds enable row level security;
drop policy if exists supplier_refunds_read on public.supplier_refunds;
create policy supplier_refunds_read on public.supplier_refunds for select to authenticated using (public._pur_ok(location_id));
revoke all on public.supplier_refunds from public, anon, authenticated;
revoke all on sequence public.supplier_refunds_id_seq from public, anon, authenticated;
grant select on public.supplier_refunds to authenticated;

-- balance owed = opening + bills - returns - payments + refunds received (a refund uses up credit, so we owe more / are owed less)
create or replace function public._sup_balance(p_supplier uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0)
       + coalesce((select sum(amount) from public.supplier_refunds where supplier_id = p_supplier and not voided), 0);
$$;

-- open-bill allocation: a refund is NEGATIVE credit at the location where it was taken (copy of phase10 + one union branch)
create or replace function public._sup_open(p_supplier uuid default null)
returns table (supplier_id uuid, bill_id uuid, bill_no text, bill_date date, location_id int, rem numeric, open_amt numeric)
language sql stable security definer set search_path = public as $$
  with bills as (
    select b.supplier_id, b.id bill_id, b.bill_no, b.bill_date, b.location_id, b.total - b.paid rem, coalesce(b.posted_at, b.created_at) ord_at, coalesce(b.location_id, -1) lk
    from public.purchase_bills b where b.status = 'posted' and b.kind = 'bill' and b.total - b.paid > 0 and (p_supplier is null or b.supplier_id = p_supplier)
    union all
    select s.id, null::uuid, 'opening', null::date, null::int, s.opening_balance, '-infinity'::timestamptz, -1
    from public.suppliers s where s.opening_balance > 0 and (p_supplier is null or s.id = p_supplier)),
  lc as (
    select z.supplier_id, z.lk, sum(z.x) credit from (
      select p.supplier_id, p.location_id lk, p.amount x from public.supplier_payments p where not p.voided and p.bill_id is null and (p_supplier is null or p.supplier_id = p_supplier)
      union all select b.supplier_id, b.location_id, b.total from public.purchase_bills b where b.status = 'posted' and b.kind = 'return' and (p_supplier is null or b.supplier_id = p_supplier)
      union all select f.supplier_id, f.location_id, -f.amount from public.supplier_refunds f where not f.voided and (p_supplier is null or f.supplier_id = p_supplier)) z
    group by 1, 2),
  oc as (select s.id supplier_id, -s.opening_balance credit from public.suppliers s where s.opening_balance < 0 and (p_supplier is null or s.id = p_supplier)),
  c1 as (select bills.*, sum(bills.rem) over (partition by bills.supplier_id, bills.lk order by bills.bill_date nulls first, bills.ord_at, bills.bill_id) c from bills),
  a1 as (
    select c1.supplier_id, c1.bill_id, c1.bill_no, c1.bill_date, c1.location_id, c1.rem, c1.ord_at,
           c1.rem - least(c1.rem, greatest(0, coalesce(lc.credit, 0) - (c1.c - c1.rem))) rem2
    from c1 left join lc on lc.supplier_id = c1.supplier_id and lc.lk = c1.lk),
  pool as (
    select z.supplier_id, sum(z.credit) - coalesce((select sum(a1.rem - a1.rem2) from a1 where a1.supplier_id = z.supplier_id), 0) spill
    from (select lc.supplier_id, lc.credit from lc union all select oc.supplier_id, oc.credit from oc) z group by 1),
  c2 as (select a1.*, sum(a1.rem2) over (partition by a1.supplier_id order by a1.bill_date nulls first, a1.ord_at, a1.bill_id) cc from a1)
  select c2.supplier_id, c2.bill_id, c2.bill_no, c2.bill_date, c2.location_id, c2.rem,
         c2.rem2 - least(c2.rem2, greatest(0, coalesce(pool.spill, 0) - (c2.cc - c2.rem2)))
  from c2 left join pool on pool.supplier_id = c2.supplier_id;
$$;

-- supplier ledger: a refund is a debit (it brings the balance back up)
create or replace function public.supplier_ledger(p_supplier uuid, p_loc int default null)
returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint, bill_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with e as (
      select '-infinity'::timestamptz at, 'opening'::text kind, null::text ref, null::int location_id, greatest(s.opening_balance, 0) debit, greatest(-s.opening_balance, 0) credit, null::text note, null::bigint pid, null::uuid bill_id, 0 srt
        from public.suppliers s where s.id = p_supplier and p_loc is null and coalesce(s.opening_balance, 0) <> 0
      union all
      select (b.bill_date::timestamp at time zone 'Asia/Dhaka'), case b.kind when 'bill' then 'bill' else 'return' end, coalesce(b.bill_no, '-'), b.location_id,
             case when b.kind = 'bill' then b.total else 0 end, case when b.kind = 'return' then b.total else 0 end, b.note, null::bigint, b.id, 1
        from public.purchase_bills b where b.supplier_id = p_supplier and b.status = 'posted' and (p_loc is null or b.location_id = p_loc)
      union all
      select p.paid_at, case when p.bill_id is null then 'payment' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id, p.bill_id, 2
        from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided and (p_loc is null or p.location_id = p_loc)
      union all
      select f.refunded_at, 'refund', coalesce(f.wallet, f.mode), f.location_id, f.amount, 0, f.note, f.id, null::uuid, 3
        from public.supplier_refunds f where f.supplier_id = p_supplier and not f.voided and (p_loc is null or f.location_id = p_loc))
    select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, e.srt, e.pid, e.bill_id), e.note, e.pid, e.bill_id
    from e order by e.at, e.srt, e.pid, e.bill_id;
end $$;

-- record cash (or mobile / card / bank) refunded BY a supplier. Only while the supplier owes US (balance < 0), never more than that credit.
create or replace function public.supplier_refund(p_supplier uuid, p_loc int, p_amount numeric, p_mode text, p_wallet text default null, p_ref text default null,
  p_reason text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare amt numeric; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
  if p_amount is null or not (p_amount between 0.01 and 999999999999) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if p_reason is not null and not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  if p_client is not null then
    select created_by into dupby from public.supplier_refunds where client_id = p_client;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'supplier_refund:' || p_supplier::text, amt)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for update;
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_refunds where client_id = p_client) then return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier)); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if bal >= 0 or amt > -bal then raise exception 'refund_exceeds_credit'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.supplier_refunds (supplier_id, location_id, mode, wallet, ref, amount, reason_code, note, created_by, created_staff, client_id)
    values (p_supplier, p_loc, p_mode, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), amt, p_reason, left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  return jsonb_build_object('refunded', amt, 'balance', bal + amt);
end $$;

create or replace function public.void_supplier_refund(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.supplier_refunds;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.supplier_refunds where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', r.location_id) or public._use_em('purchase_void', r.location_id, 'void_refund:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = r.supplier_id for update;
  select * into r from public.supplier_refunds where id = p_id for update;
  if r.voided then raise exception 'already void'; end if;
  perform public.lock_check((r.refunded_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_refunds set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(r.location_id, 'supplier_refund_void', 'yellow', 'সাপ্লায়ার রিফান্ড বাতিল: ' || left(btrim(p_note), 100), 'A supplier refund was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', r.amount);
end $$;

-- ---------- (11b) sale return ----------
create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  sale_id uuid not null references public.sales(id),
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  lines jsonb not null,                                                -- [{item_id, name, unit, qty, price, amount}] qty in the unit of the sale line
  amount numeric not null check (amount > 0 and amount <= 1000000000000),   -- value of the goods taken back (the sale's discount share already taken off)
  credit_amount numeric not null default 0 check (credit_amount >= 0),     -- used to reduce what the customer owes
  refund_amount numeric not null default 0 check (refund_amount >= 0),     -- money handed back
  refund_mode text check (refund_mode is null or refund_mode in ('cash', 'mobile', 'card')),
  wallet text, ref text,
  reason_code text not null, note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (credit_amount + refund_amount = amount)
);
create index if not exists sale_returns_sale on public.sale_returns (sale_id);
create index if not exists sale_returns_cust on public.sale_returns (customer_id) where status = 'done';
drop trigger if exists audit_sale_returns on public.sale_returns;
create trigger audit_sale_returns after insert or update on public.sale_returns for each row execute function public.log_change('id');
alter table public.sale_returns enable row level security;
drop policy if exists sale_returns_read on public.sale_returns;
create policy sale_returns_read on public.sale_returns for select to authenticated
  using (public.can_loc(location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', location_id)));
revoke all on public.sale_returns from public, anon, authenticated;
grant select on public.sale_returns to authenticated;

-- a sale that has a live return cannot be voided (its stock would go back twice): void the return first
create or replace function public._sale_void_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.sale_returns where sale_id = new.id and status = 'done') then raise exception 'sale_has_returns'; end if;
  return new;
end $$;
drop trigger if exists sales_void_guard on public.sales;
create trigger sales_void_guard before update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_void_guard();

-- customer balance: sold - paid - credited by returns. The gate stays as before (POS view / enter).
create or replace function public._cust_bal(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$$;
create or replace function public.customer_balance(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then public._cust_bal(p_customer) end;
$$;
create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
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
$$;
create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done'
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0)
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

-- take goods back from a sale. p_lines: [{"item_id":uuid,"qty":1.5}] (qty in the unit the sale line used).
-- Stock goes back (tracked items) into the batch it came out of at the cost it left with; the value first reduces the customer's due
-- (rule sale_return_due_first), the rest is refunded in p_refund_mode.
create or replace function public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text default null,
  p_refund_mode text default null, p_wallet text default null, p_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $$;

create or replace function public.void_sale_return(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sale_returns; o public.stock_ledger;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.sale_returns where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('sale_return', r.location_id) or public._use_em('sale_return', r.location_id, 'void_return:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  for o in select * from public.stock_ledger x where x.ref_type = 'sale_return' and x.ref_id = p_id::text and x.reason = 'sale_return'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
    perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', 'sale_return', p_id::text, o.unit_cost, o.batch_id, now(), left('void: ' || btrim(p_note), 200), o.id, 'none');
  end loop;
  update public.sale_returns set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  perform public._stock_exc(r.location_id, 'sale_return_void', 'yellow', 'বিক্রি ফেরত বাতিল: ' || left(btrim(p_note), 100), 'A sale return was voided: ' || left(btrim(p_note), 100), r.sale_id, null, 'POS', r.amount);
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;

-- returns of one sale (for the sale's ⋮ menu) and what can still be returned per item
create or replace function public.sale_returns_for(p_sale uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales;
begin
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'not found'; end if;
  if not (public.is_active() and public.can_loc(s.location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', s.location_id))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('sale_id', s.id, 'receipt', s.receipt, 'status', s.status, 'location_id', s.location_id, 'customer_id', s.customer_id, 'customer', s.customer,
    'factor', case when s.subtotal > 0 then round(s.total / s.subtotal, 8) else 1 end, 'due_first', public.rule_on('sale_return_due_first'),
    'balance', case when s.customer_id is not null then public._cust_bal(s.customer_id) end,
    'can_return', public.has_grant('sale_return', s.location_id) and s.status = 'done',
    'lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', z.iid, 'name', z.nm, 'unit', z.u, 'sold', z.sq, 'returned', z.pq, 'left', z.sq - z.pq, 'price', round(z.samt / nullif(z.sq, 0), 4)) order by z.nm)
      from (select l.iid, max(l.nm) nm, max(l.u) u, sum(l.q) sq, sum(l.a) samt,
                   coalesce((select sum((x2->>'qty')::numeric) from public.sale_returns r2, jsonb_array_elements(r2.lines) x2 where r2.sale_id = s.id and r2.status = 'done' and x2->>'item_id' = l.iid), 0) pq
            from (select e->>'item_id' iid, e->>'name' nm, e->>'unit' u, (e->>'qty')::numeric q, (e->>'amount')::numeric a
                  from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where nullif(e->>'item_id', '') is not null) l
            group by l.iid) z), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount, 'refund_mode', r.refund_mode,
      'reason', r.reason_code, 'note', r.note, 'status', r.status, 'at', r.created_at, 'staff', r.created_staff) order by r.created_at desc) from public.sale_returns r where r.sale_id = s.id), '[]'::jsonb));
end $$;

-- suppliers that owe US (advance paid, or credit from returns): where a refund can be recorded
create or replace function public.supplier_credits() returns table (supplier_id uuid, name text, mobile text, credit numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(null) then raise exception 'not allowed'; end if;
  return query select z.id, z.name, z.mobile, -z.b from (select s.id, s.name, s.mobile, public._sup_balance(s.id) b from public.suppliers s) z where z.b < 0 order by 4 desc;
end $$;

-- owner-only copies of the two tables whose cost columns are not granted (for the app's backup)
create or replace function public.backup_stock_ledger(p_from bigint default 0, p_limit int default 1000) returns setof public.stock_ledger
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query select * from public.stock_ledger where id > coalesce(p_from, 0) order by id limit least(greatest(coalesce(p_limit, 1000), 1), 5000);
end $$;
create or replace function public.backup_stock_balance() returns setof public.stock_balance
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query select * from public.stock_balance order by item_id, location_id;
end $$;
revoke all on function public.backup_stock_ledger(bigint, int), public.backup_stock_balance() from public, anon, authenticated;
grant execute on function public.backup_stock_ledger(bigint, int), public.backup_stock_balance() to authenticated;

-- ---------- privileges for everything new ----------
revoke all on function public._wastage_post(uuid, int, numeric, text, text, text, bigint, uuid, uuid, text), public._cust_bal(uuid), public._sale_void_guard(),
  public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() from public, anon, authenticated;
grant execute on function public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() to authenticated;
-- re-created functions keep their old grants (create or replace); make sure they are exactly as before
revoke all on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid),
  public._sup_balance(uuid), public._sup_open(uuid), public.supplier_ledger(uuid, int), public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) from public, anon;
grant execute on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.supplier_ledger(uuid, int),
  public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) to authenticated;
revoke all on function public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid), public._sup_balance(uuid), public._sup_open(uuid) from authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase13.sql
-- ============================================================
-- BOS tool · Phase 13: DAY BOOK (cash / bank / mobile in and out by day) + SALARY REPORT (forms 02-1 / 02-2 / 02-3) + audited exports.
-- Run AFTER phase8, phase9, phase10 (phases 11 / 12 are independent). ADDITIVE and IDEMPOTENT: safe to run again, paste whole.
--
-- Principles kept:
--   * nothing is invented: the day book only adds up rows that really exist (POS payments, due collections, expense vouchers 10-2,
--     supplier payments, cash handover slips 10-1, staff advances 02-3, salary receipts 02-2). A day book start date is the owner's choice:
--     empty = no opening / closing figures at all ("Data needed"), only the movements.
--   * new grant `view_daybook` (owner can delegate to a role or a person, per location, with an end date, emergency window off by default).
--   * salary lines (advances, salary payments) inside the day book are only returned for people who also hold `salary_view`.
--   * salary_report is for the owner or `salary_view` holders only, and only returns what the forms contain; the sums are exactly the
--     formulas of form 02-2 (gross = due + overtime + other; net = gross - advance deduction - other deduction).
--   * export of either page is audited by log_page_export, which needs the owner or the grant export_data (same rpt_grant as the reports).
--   * RLS untouched (no new tables); new functions are SECURITY DEFINER, search_path=public, no anon, authenticated only.
-- ============================================================

-- ---------- (a) settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('daybook_enabled', 'books', 'switch', 'true', null, null, null, null, 'দিনের খাতা (Day book) চালু', 'Day book চালু', 'Day book is on',
  'বন্ধ করলে মালিক ছাড়া কেউ খুলতে পারবে না', 'When off, only the owner can open it', 160),
 ('daybook_start', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'দিনের খাতার শুরুর তারিখ (এই তারিখ থেকে চলতি জের গোনা হয়)', 'Day book শুরুর তারিখ (এই তারিখ থেকে running total)', 'Day book start date (running totals count from here)',
  'খালি থাকলে শুরু/শেষ জের দেখানো হয় না — শুধু লেনদেন', 'Empty = no opening / closing figures, movements only', 161),
 ('em_view_daybook', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: দিনের খাতা দেখা', 'জরুরি request চলবে: day book দেখা', 'Emergency allowed for: seeing the day book', 'ডিফল্টে বন্ধ', 'Off by default', 55)
on conflict (key) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('daybook_open_cash', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে নগদ জের', 'Start তারিখে Cash জের', 'Opening cash balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 162),
 ('daybook_open_bank', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে ব্যাংক জের', 'Start তারিখে Bank জের', 'Opening bank balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 163),
 ('daybook_open_mobile', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে মোবাইল জের', 'Start তারিখে Mobile জের', 'Opening mobile balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 164),
 ('daybook_mask_names', 'books', 'switch', 'false', null, null, null, null, 'দিনের খাতায় নাম/রেফারেন্স লুকানো (মালিক ছাড়া)', 'Day book-এ নাম/ref লুকানো (Owner ছাড়া)', 'Mask customer / supplier names and references in the day book (non-owners)', 'ডিফল্টে বন্ধ', 'Off by default', 165)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('view_daybook', 'reports', 27, 'দিনের খাতা দেখা', 'Day book দেখা', 'See the day book', 'window', 'em_view_daybook')
on conflict (grant_code) do nothing;

-- ---------- (b) small safe parsers (never raise; Infinity / NaN / absurd sizes come back null) ----------
create or replace function public._db_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if j is null or jsonb_typeof(j) not in ('number', 'string') then return null; end if;
  s := translate(btrim(j #>> '{}'), '০১২৩৪৫৬৭৮৯', '0123456789');
  s := regexp_replace(s, '(৳|tk\.?|bdt|taka|\s)', '', 'gi');          -- currency signs and spaces
  s := replace(s, ',', '');                                           -- thousands commas
  if s ~ '^-?\.' then s := regexp_replace(s, '^(-?)\.', '\10.'); end if;   -- ".5" -> "0.5"
  s := regexp_replace(s, '\.$', '');                                  -- "5." -> "5"
  if s !~ '^-?[0-9]{1,13}(\.[0-9]{1,6})?$' then return null; end if;
  return s::numeric;
end $$;

create or replace function public._db_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return btrim(t)::date;
exception when others then return null;
end $$;

create or replace function public._db_int(j jsonb) returns int
language plpgsql immutable set search_path = public as $$
declare n numeric := public._db_num(j);
begin
  if n is null or n <> trunc(n) or not (n between -100000 and 100000) then return null; end if;
  return n::int;
end $$;

-- the day book start date setting, null when empty / malformed
create or replace function public._db_start() returns date
language sql stable security definer set search_path = public as $$
  select public._db_date(public.rule_txt('daybook_start'));
$$;

-- owner sets / clears the start date (validated here because set_rule only checks "is a string")
create or replace function public.set_daybook_start(p_date date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is not null and not (p_date between date '2000-01-01' and (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  perform public.set_rule('daybook_start', case when p_date is null then null else to_jsonb(to_char(p_date, 'YYYY-MM-DD')) end);
end $$;

-- owner sets the opening balances AT THE START DATE (null = not set = balances show "Data needed")
create or replace function public.set_daybook_opening(p_cash numeric, p_bank numeric, p_mobile numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v numeric; k text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  foreach v in array array[p_cash, p_bank, p_mobile] loop
    if v is not null and not (v between -1000000000000 and 1000000000000) then raise exception 'bad_amount'; end if;
  end loop;
  update public.rules set value = case when p_cash is null then null else to_jsonb(p_cash) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_cash';
  update public.rules set value = case when p_bank is null then null else to_jsonb(p_bank) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_bank';
  update public.rules set value = case when p_mobile is null then null else to_jsonb(p_mobile) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_mobile';
end $$;

-- ---------- (c) the raw movements ----------
-- one row per real money movement. p_locs = locations the caller may see; p_sal = the subset where the caller may also see salary lines.
create or replace function public._daybook_lines(p_locs int[], p_sal int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable as $$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,
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
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, sp.wallet, sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
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
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$$;


-- phase12 money flows, only when those tables exist (phase12 may not be installed): refunds paid to customers (OUT) and refunds received from suppliers (IN)
create or replace function public._daybook_lines12(p_locs int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language plpgsql stable as $$
declare ts timestamptz := p_from::timestamp at time zone 'Asia/Dhaka'; te timestamptz := (p_to + 1)::timestamp at time zone 'Asia/Dhaka';
begin
  if to_regclass('public.sale_returns') is not null then
    return query execute $q$
      select r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, 'out'::text,
             (case r.refund_mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end)::text, 'sale_return'::text, r.refund_amount::numeric,
             (case when s.receipt is not null then '#' || s.receipt::text end)::text, nullif(btrim(concat_ws(' · ', c.name, r.wallet, r.ref)), '')::text, r.created_staff::text, r.created_at,
             'sale'::text, r.sale_id::text, false, false
        from public.sale_returns r left join public.sales s on s.id = r.sale_id left join public.customers c on c.id = r.customer_id
       where r.status = 'done' and r.refund_amount > 0 and r.refund_mode is not null and r.location_id = any ($1)
         and r.refund_amount between 0.01 and 1000000000000 and r.created_at >= $2 and r.created_at < $3 $q$ using p_locs, ts, te;
  end if;
  if to_regclass('public.supplier_refunds') is not null then
    return query execute $q$
      select f.location_id, (f.refunded_at at time zone 'Asia/Dhaka')::date, 'in'::text,
             (case f.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end)::text, 'supplier_refund'::text, f.amount::numeric,
             null::text, nullif(btrim(concat_ws(' · ', su.name, f.wallet, f.ref)), '')::text, f.created_staff::text, f.refunded_at,
             'supplier'::text, f.supplier_id::text, false, false
        from public.supplier_refunds f left join public.suppliers su on su.id = f.supplier_id
       where not f.voided and f.location_id = any ($1) and f.amount between 0.01 and 1000000000000 and f.refunded_at >= $2 and f.refunded_at < $3 $q$ using p_locs, ts, te;
  end if;
end $$;

-- how many form lines were skipped because their amount could not be read as a number (shown by the page as "N lines could not be read")
create or replace function public._daybook_skipped(p_locs int[], p_sal int[], p_from date, p_to date) returns int
language sql stable as $$
  select (
    (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs) and e.entry_date between p_from and p_to
        and nullif(btrim(l ->> 'amount'), '') is not null and public._db_num(l -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
      where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(a ->> 'amount'), '') is not null and public._db_num(a -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(r ->> 'net'), '') is not null and public._db_num(r -> 'net') is null))::int;
$$;

-- ---------- (d) the day book ----------
-- Result: { from, to (capped at today), loc, start, opening_known, balances, enabled, salary_hidden, names_masked, skipped_rows,
--           days:[{date, open, close, net_open, net_close, in, out, transfers, lines}], totals:{...}, notes:[...] }
-- net_open / net_close = running NET of counted movements since daybook_start (null when no start / day before it).
-- open / close = real balances = the owner's opening balances (daybook_open_*) + net; only when the opening balance of that mode is set AND the view is
--   all locations (the opening balances are business-wide) -> otherwise null ("Data needed").
-- Cash handover slips (10-1) are INTERNAL transfers: always listed as their own lines and summed separately in `transfers`; counted as cash OUT only in a
--   single-location view (the cash really left that showroom), never in the all-locations totals (the hub side has no location on record).
-- Only lines up to today (Dhaka) are returned; p_to beyond today is capped.
create or replace function public.day_book(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_locs int[]; v_sal int[]; v_start date; v_all boolean := (p_loc is null); v_to date; v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_days jsonb; v_tot jsonb; v_hidden boolean; v_mask boolean; v_known boolean; v_skipped int; v_allseen boolean;
  v_ob numeric[] := array[null, null, null]::numeric[]; v_base numeric[] := array[0, 0, 0]::numeric[]; v_bal boolean;
  v_netopen jsonb; v_netclose jsonb; v_open jsonb; v_close jsonb; v_i1 numeric; v_i2 numeric; v_i3 numeric; v_o1 numeric; v_o2 numeric; v_o3 numeric; v_n1 numeric; v_n2 numeric; v_n3 numeric; v_tr numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from in (date 'infinity', date '-infinity') or p_to in (date 'infinity', date '-infinity')
     or not (p_from between date '2000-01-01' and date '2100-01-01') or not (p_to between date '2000-01-01' and date '2100-01-01')
     or p_to < p_from or p_to - p_from + 1 > 366 then raise exception 'bad_range'; end if;
  if not public.is_owner() and not public.rule_on('daybook_enabled') then raise exception 'daybook_off'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('view_daybook', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l), '{}') into v_sal from unnest(v_locs) l where public.has_grant('salary_view', l);
  v_hidden := cardinality(v_sal) < cardinality(v_locs);
  v_mask := (not public.is_owner()) and public.rule_on('daybook_mask_names');
  v_start := public._db_start();
  v_to := least(p_to, v_today);
  v_allseen := v_all and (select count(*) from public.locations) = cardinality(v_locs);
  v_ob := array[public.rule_num('daybook_open_cash'), public.rule_num('daybook_open_bank'), public.rule_num('daybook_open_mobile')];
  v_bal := v_allseen and v_ob[1] is not null and v_ob[2] is not null and v_ob[3] is not null;
  v_known := v_start is not null and v_to >= v_start;

  -- opening net: ONE aggregate over [start, p_from - 1] (only rows dated on/after the start date)
  if v_start is not null and v_start < p_from then
    select array[coalesce(sum(s) filter (where mode = 'cash'), 0), coalesce(sum(s) filter (where mode = 'bank'), 0), coalesce(sum(s) filter (where mode = 'mobile'), 0)] into v_base
      from (select u.mode, case when u.dir = 'in' then u.amount else -u.amount end as s
              from (select * from public._daybook_lines(v_locs, v_sal, v_start, p_from - 1) union all select * from public._daybook_lines12(v_locs, v_start, p_from - 1)) u
             where not (u.internal and v_all)) z;
  end if;

  with rl as (select * from public._daybook_lines(v_locs, v_sal, p_from, v_to) union all select * from public._daybook_lines12(v_locs, p_from, v_to)),
  c as (select d, mode, case when dir = 'in' then amount else -amount end as s from rl where not (internal and v_all) and v_start is not null and d >= v_start),
  perday as (select d, sum(s) filter (where mode = 'cash') cash, sum(s) filter (where mode = 'bank') bank, sum(s) filter (where mode = 'mobile') mobile from c group by d),
  cum as (select d, coalesce(cash, 0) cash, coalesce(bank, 0) bank, coalesce(mobile, 0) mobile,
                 coalesce(sum(cash) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[1] pc,
                 coalesce(sum(bank) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[2] pb,
                 coalesce(sum(mobile) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[3] pm from perday),
  x as (select t.d,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'cash' and not (t.internal and v_all)), 0) i_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'bank' and not (t.internal and v_all)), 0) i_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'mobile' and not (t.internal and v_all)), 0) i_mobile,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'cash' and not (t.internal and v_all)), 0) o_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'bank' and not (t.internal and v_all)), 0) o_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'mobile' and not (t.internal and v_all)), 0) o_mobile,
          coalesce(sum(t.amount) filter (where t.internal), 0) tr,
          jsonb_agg(jsonb_build_object('loc', t.loc, 'dir', t.dir, 'mode', t.mode, 'type', t.typ, 'amount', t.amount,
                    'ref', case when v_mask then null else t.ref end, 'text', case when v_mask then null else t.txt end, 'who', t.who,
                    'at', t.at, 'src', t.src, 'src_id', t.src_id, 'internal', t.internal, 'sensitive', t.sensitive) order by t.at, t.typ) lines
          from rl t group by t.d)
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', x.d,
      'net_open', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc, 'bank', cm.pb, 'mobile', cm.pm, 'total', cm.pc + cm.pb + cm.pm) end,
      'net_close', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc + cm.cash, 'bank', cm.pb + cm.bank, 'mobile', cm.pm + cm.mobile, 'total', cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'open', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc, 'bank', v_ob[2] + cm.pb, 'mobile', v_ob[3] + cm.pm, 'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm) end,
      'close', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc + cm.cash, 'bank', v_ob[2] + cm.pb + cm.bank, 'mobile', v_ob[3] + cm.pm + cm.mobile,
                    'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'in', jsonb_build_object('cash', x.i_cash, 'bank', x.i_bank, 'mobile', x.i_mobile, 'total', x.i_cash + x.i_bank + x.i_mobile),
      'out', jsonb_build_object('cash', x.o_cash, 'bank', x.o_bank, 'mobile', x.o_mobile, 'total', x.o_cash + x.o_bank + x.o_mobile),
      'transfers', x.tr, 'lines', x.lines) order by x.d), '[]'::jsonb),
    coalesce(sum(x.i_cash), 0), coalesce(sum(x.i_bank), 0), coalesce(sum(x.i_mobile), 0), coalesce(sum(x.o_cash), 0), coalesce(sum(x.o_bank), 0), coalesce(sum(x.o_mobile), 0), coalesce(sum(x.tr), 0),
    coalesce(sum(x.i_cash - x.o_cash) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_bank - x.o_bank) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_mobile - x.o_mobile) filter (where v_start is not null and x.d >= v_start), 0)
    into v_days, v_i1, v_i2, v_i3, v_o1, v_o2, v_o3, v_tr, v_n1, v_n2, v_n3
    from x left join cum cm on cm.d = x.d;

  v_tot := jsonb_build_object(
    'in', jsonb_build_object('cash', v_i1, 'bank', v_i2, 'mobile', v_i3, 'total', v_i1 + v_i2 + v_i3),
    'out', jsonb_build_object('cash', v_o1, 'bank', v_o2, 'mobile', v_o3, 'total', v_o1 + v_o2 + v_o3), 'transfers', v_tr);
  if v_known then
    -- start of the range = running net before p_from (rows on/after the start date only); end = that + what happened in the range on/after the start date
    select jsonb_build_object('cash', v_base[1], 'bank', v_base[2], 'mobile', v_base[3], 'total', v_base[1] + v_base[2] + v_base[3]) into v_netopen;
    v_netclose := jsonb_build_object('cash', v_base[1] + v_n1, 'bank', v_base[2] + v_n2, 'mobile', v_base[3] + v_n3, 'total', v_base[1] + v_base[2] + v_base[3] + v_n1 + v_n2 + v_n3);
    v_tot := v_tot || jsonb_build_object('net_open', v_netopen, 'net_close', v_netclose);
    if v_bal then
      v_tot := v_tot || jsonb_build_object('open', jsonb_build_object('cash', v_ob[1] + v_base[1], 'bank', v_ob[2] + v_base[2], 'mobile', v_ob[3] + v_base[3], 'total', v_ob[1] + v_ob[2] + v_ob[3] + v_base[1] + v_base[2] + v_base[3]),
        'close', jsonb_build_object('cash', v_ob[1] + (v_netclose ->> 'cash')::numeric, 'bank', v_ob[2] + (v_netclose ->> 'bank')::numeric, 'mobile', v_ob[3] + (v_netclose ->> 'mobile')::numeric,
                                    'total', v_ob[1] + v_ob[2] + v_ob[3] + (v_netclose ->> 'total')::numeric));
    end if;
  end if;
  v_skipped := public._daybook_skipped(v_locs, v_sal, p_from, v_to);

  return jsonb_build_object('from', p_from, 'to', v_to, 'capped', p_to > v_today, 'loc', p_loc, 'start', v_start, 'opening_known', v_known, 'balances', v_bal,
    'enabled', public.rule_on('daybook_enabled'), 'salary_hidden', v_hidden, 'names_masked', v_mask, 'skipped_rows', v_skipped, 'days', v_days,
    'totals', v_tot || jsonb_build_object('net_open', coalesce(v_tot -> 'net_open', 'null'::jsonb), 'net_close', coalesce(v_tot -> 'net_close', 'null'::jsonb), 'open', coalesce(v_tot -> 'open', 'null'::jsonb), 'close', coalesce(v_tot -> 'close', 'null'::jsonb)),
    'notes', jsonb_build_array('card_as_bank', 'imprest_in_cash', 'bank_deposit_not_dated', 'hub_receipt_not_recorded', 'drafts_excluded', 'refunds_included', 'future_dates_capped'));
end $$;

-- ---------- (e) salary report (forms 02-2 sheet, 02-3 advances, 02-1 attendance) ----------
-- p_month is any date inside the month. A sheet belongs to the month written on the form (month + year), else its entry date.
create or replace function public.salary_report(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_locs int[]; m0 date; m1 date; mm int; yy int; v_rows jsonb; v_adv jsonb; v_att jsonb; v_tot jsonb; v_n int; v_dup jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_month is null or not (p_month between date '2000-01-01' and date '2100-01-01') then raise exception 'bad_range'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('salary_view', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  m0 := date_trunc('month', p_month)::date; m1 := (m0 + interval '1 month')::date;
  mm := extract(month from m0)::int; yy := extract(year from m0)::int;

  -- salary sheet lines
  with sh as (
    select e.id, e.serial, e.location_id, e.status, e.data, e.entry_date
      from public.entries e
     where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs)
       and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
       and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy),
  ln as (
    select sh.id as entry_id, sh.serial, sh.location_id, sh.status, btrim(coalesce(r ->> 'name', '')) as name,
           public._db_num(r -> 'salary') salary, public._db_num(r -> 'work_days') work_days, public._db_num(r -> 'absent') absent, public._db_num(r -> 'leave') leave_days,
           coalesce(public._db_num(r -> 'due'), 0) due, coalesce(public._db_num(r -> 'overtime'), 0) overtime, coalesce(public._db_num(r -> 'other'), 0) other,
           coalesce(public._db_num(r -> 'adv_ded'), 0) adv_ded, coalesce(public._db_num(r -> 'other_ded'), 0) other_ded, nullif(btrim(r ->> 'remark'), '') remark,
           sh.data -> 'receipts' as rc, z.ord
      from sh cross join lateral jsonb_array_elements(case when jsonb_typeof(sh.data -> 'pay') = 'array' then sh.data -> 'pay' else '[]'::jsonb end) with ordinality as z(r, ord)),
  ln2 as (select ln.*, count(*) over (partition by location_id, lower(name)) as nn from ln where name <> '' and (due <> 0 or overtime <> 0 or other <> 0 or adv_ded <> 0 or other_ded <> 0 or salary is not null))
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', entry_id, 'serial', serial, 'loc', location_id, 'status', status, 'name', name, 'salary', salary,
        'work_days', work_days, 'absent', absent, 'leave', leave_days, 'due', due, 'overtime', overtime, 'other', other,
        'gross', due + overtime + other, 'adv_ded', adv_ded, 'other_ded', other_ded, 'deductions', adv_ded + other_ded,
        'net', due + overtime + other - adv_ded - other_ded, 'remark', remark, 'ambiguous', nn > 1,
        'paid', case when nn > 1 then null else (select sum(public._db_num(q -> 'net')) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)) end,
        'signed', case when nn > 1 then null else (select bool_and(coalesce((q ->> 'signed')::boolean, false)) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)) end)
        order by location_id, serial, ord), '[]'::jsonb),
      jsonb_build_object('people', count(*), 'due', coalesce(sum(due), 0), 'overtime', coalesce(sum(overtime), 0), 'other', coalesce(sum(other), 0),
        'gross', coalesce(sum(due + overtime + other), 0), 'adv_ded', coalesce(sum(adv_ded), 0), 'other_ded', coalesce(sum(other_ded), 0),
        'deductions', coalesce(sum(adv_ded + other_ded), 0), 'net', coalesce(sum(due + overtime + other - adv_ded - other_ded), 0)),
      count(distinct entry_id)::int
    into v_rows, v_tot, v_n from ln2;

  -- advances (02-3): per page = per employee
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'status', e.status, 'staff', e.data ->> 'staff',
        'name', coalesce(pr.full_name, e.data ->> 'staff'), 'post', e.data ->> 'post',
        'given', x.given, 'deducted', x.ded, 'outstanding', x.bal) order by e.location_id, e.serial), '[]'::jsonb)
    into v_adv
    from public.entries e
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
    cross join lateral (select coalesce(sum(public._db_num(a -> 'amount')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) given,
                               coalesce(sum(public._db_num(a -> 'ded_now')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) ded,
                               coalesce(sum(public._db_num(a -> 'balance')), 0) bal,
                               count(*) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1) n_in
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a) x
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and (x.n_in > 0 or (e.entry_date >= m0 and e.entry_date < m1));

  -- attendance (02-1) of the same month
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'name', btrim(r ->> 'name'), 'present', public._db_num(r -> 'present'),
        'late', public._db_num(r -> 'late'), 'absent', public._db_num(r -> 'absent'), 'leave_unpaid', public._db_num(r -> 'leave_unpaid'), 'leave_paid', public._db_num(r -> 'leave_paid'),
        'ot_hours', public._db_num(r -> 'ot_hours')) order by e.location_id, e.serial), '[]'::jsonb)
    into v_att
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
   where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and btrim(coalesce(r ->> 'name', '')) <> ''
     and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
     and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy;

  select coalesce(jsonb_agg(jsonb_build_object('loc', z.location_id, 'n', z.n) order by z.location_id), '[]'::jsonb) into v_dup
    from (select e.location_id, count(*) n from public.entries e
           where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs)
             and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
             and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy group by 1 having count(*) > 1) z;

  return jsonb_build_object('month', m0, 'loc', p_loc, 'duplicate_sheets', v_dup, 'rows', v_rows, 'totals', v_tot, 'sheets', v_n, 'advances', v_adv, 'attendance', v_att,
    'data_needed', (v_n = 0), 'drafts_excluded', true);
end $$;

-- ---------- (f) audited export of these pages ----------
-- The page calls this BEFORE it builds the file and only builds it when this returns without error, so the check is server-side and the audit row exists.
create or replace function public.log_page_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('daybook', 'salary') then raise exception 'unknown_report'; end if;
  if p_key = 'daybook' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('view_daybook', l.id))) then raise exception 'not allowed'; end if;
  if p_key = 'salary' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('salary_view', l.id))) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._db_num(jsonb), public._db_date(text), public._db_int(jsonb), public._db_start(), public.set_daybook_start(date),
  public._daybook_lines(int[], int[], date, date), public._daybook_lines12(int[], date, date), public._daybook_skipped(int[], int[], date, date), public.set_daybook_opening(numeric, numeric, numeric), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.set_daybook_start(date), public.set_daybook_opening(numeric, numeric, numeric), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase14.sql
-- ============================================================
-- Phase 14 (W2): ITEM MASTER (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase13 applied first (phase11 / phase12 / phase13 are optional but expected).
--   * items: item_type, control_class, count_in_business, sellable, locked, hidden, master_code, retired_at/reason, import_batch
--   * item_types (defaults per type, editable) + item_class_map (dictionary class -> type, editable)
--   * rules tools_stock_on (off), asset_register_on (on), item_create_needs_approval (on), item_master_apply_ok (off); grants item_create, asset_manage
--   * item codes: dictionary code is the permanent code; item_next_code() = max numeric suffix in the category + 1 (advisory lock), retired codes stay reserved
--   * item_new / item_apply (owner or grant item_create act at once; others file a request through item_changes, approved as before)
--   * dictionary import: item_master_import_preview (writes NOTHING) and item_master_import_apply (owner only, idempotent, batch id, one audit line per batch)
--   * old seed items -> dictionary: item_mapping_review / item_master_links (only high-confidence rows auto-link; the rest wait for a decision)
--   * asset register: assets + asset_costs (cost visible only to owner / ITEM_COST / view_cost), RPCs asset_add / asset_update / asset_retire,
--     purchase of an asset-type item auto-adds register rows (hook around post_purchase), voiding the bill retires them
--   * server enforcement: a sale line must be a sellable, priced item; stock ledger refuses items that are not counted in the business;
--     stock value / COGS / profit reports skip count_in_business = false items
--   Nothing is deleted. No price, cost, VAT or limit is invented: imported items have NO selling price ("Data needed").
-- ============================================================

-- ---------- (1) items: new columns (existing items keep behaving exactly as before) ----------
alter table public.items add column if not exists item_type text;
alter table public.items add column if not exists control_class text;
alter table public.items add column if not exists count_in_business boolean not null default true;
alter table public.items add column if not exists sellable boolean not null default true;
alter table public.items add column if not exists locked boolean not null default false;
alter table public.items add column if not exists hidden boolean not null default false;
alter table public.items add column if not exists master_code text;
alter table public.items add column if not exists retired_at timestamptz;
alter table public.items add column if not exists retired_reason text;
alter table public.items add column if not exists import_batch text;
create index if not exists items_type_idx on public.items (item_type);
create index if not exists items_code_prefix_idx on public.items (code text_pattern_ops);

-- ---------- (2) item types (editable defaults) and the dictionary-class map ----------
create table if not exists public.item_types (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  label_bn text not null, label_mix text, label_en text,
  count_in_business boolean not null default true,    -- default of the flag for new items of this type
  sellable boolean not null default false,            -- default of the flag
  sort int not null default 0, active boolean not null default true,
  note_en text,
  updated_at timestamptz not null default now(), updated_by uuid
);
create table if not exists public.item_class_map (
  control_class text primary key,
  item_type text not null references public.item_types(code),
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.item_types (code, label_bn, label_mix, label_en, count_in_business, sellable, sort, note_en) values
 ('finished_good',  'তৈরি পণ্য',        'Finished good',   'Finished good',  true,  true,  1, 'Made here, then sold'),
 ('resale',         'কিনে বিক্রি',       'Resale',          'Resale',         true,  true,  2, 'Bought, then sold'),
 ('raw_material',   'কাঁচামাল',         'Raw material',    'Raw material',   true,  false, 3, 'Consumed in production, never sold'),
 ('packaging',      'প্যাকেজিং',        'Packaging',       'Packaging',      true,  false, 4, 'Goes out with a sale by the per-product rule'),
 ('consumable',     'ভোগ্য সামগ্রী',     'Consumable',      'Consumable',     false, false, 5, 'An expense: not stock, not COGS'),
 ('asset',          'সম্পদ',            'Asset',           'Asset',          false, false, 6, 'Never in stock, sales or COGS; kept in the asset register'),
 ('controlled',     'নিয়ন্ত্রিত (যন্ত্রপাতি)', 'Controlled (tools)', 'Controlled (tools)', false, false, 7, 'Tools: counted separately; off until the tools-stock switch is on'),
 ('infrastructure', 'অবকাঠামো সামগ্রী',  'Infrastructure',  'Infrastructure', false, false, 8, 'Treated like a consumable by default')
on conflict (code) do nothing;
insert into public.item_class_map (control_class, item_type) values
 ('Finished Good', 'finished_good'), ('Stock/Direct Sale', 'resale'), ('Raw Material', 'raw_material'), ('Packaging', 'packaging'),
 ('Consumable', 'consumable'), ('Asset', 'asset'), ('Controlled Item', 'controlled'), ('Infrastructure Material', 'infrastructure')
on conflict (control_class) do nothing;

-- legacy items: type from the old data (a selling price = finished good, else resale); nothing else changes
update public.items set item_type = case when sell_price is not null then 'finished_good' else 'resale' end where item_type is null;
alter table public.items alter column item_type set default 'finished_good';
alter table public.items alter column item_type set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'items_item_type_fk') then
    alter table public.items add constraint items_item_type_fk foreign key (item_type) references public.item_types(code);
  end if;
end $$;

-- ---------- (3) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('tools_stock_on', 'items', 'switch', 'false', null, null, null, null, 'যন্ত্রপাতির (নিয়ন্ত্রিত আইটেম) আলাদা স্টক গণনা চালু', 'Tools (controlled item) এর আলাদা stock count চালু', 'Tools stock count (controlled items) on',
   'বন্ধ থাকলে যন্ত্রপাতি ব্যবসার স্টকে ধরা হয় না', 'Off হলে tools business stock এ ধরা হয় না', 'Off = tools are not counted in the business stock. On = every controlled item is counted (its own flag can still be changed). Turning it off needs zero tool stock', 200),
 ('asset_register_on', 'items', 'switch', 'true', null, null, null, null, 'সম্পদ কিনলে সম্পদ-খাতায় নিজে যোগ হবে', 'Asset কিনলে asset register এ নিজে যোগ হবে', 'Buying an asset adds it to the asset register',
   'চালু থাকলে ক্রয় বিল পোস্ট করলে প্রতিটি সম্পদের জন্য একটি সারি', 'On থাকলে purchase bill post করলে প্রতিটি asset এর জন্য একটি row', 'On = posting a purchase bill adds one register row per asset bought (never stock). Off = no rows are added', 201),
 ('item_create_needs_approval', 'items', 'switch', 'true', null, null, null, null, 'নতুন আইটেম যোগে মালিকের অনুমোদন লাগবে (মালিক বা অনুমতিপ্রাপ্ত ছাড়া)', 'নতুন item যোগে owner approval লাগবে (owner বা grant-holder ছাড়া)', 'A new item needs approval (unless added by the owner or a person with the item_create grant)',
   'বন্ধ করলে আইটেম-অনুমতিধারী সবাই সরাসরি যোগ করতে পারবে', 'Off করলে Item-permission আছে এমন সবাই সরাসরি যোগ করতে পারবে', 'Off = anyone who may enter items adds a new item at once', 202),
 ('item_master_apply_ok', 'items', 'switch', 'false', null, null, null, null, 'ডিকশনারি ইমপোর্ট SQL চালানোর অনুমতি (শুধু মালিকের জন্য)', 'Dictionary import SQL চালানোর অনুমতি (শুধু owner)', 'Allow the dictionary import SQL file to write (owner only)',
   null, null, 'Used only by supabase/phase14_import.sql. The owner turns it on by one statement, runs the import, then turns it off again', 203)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('item_create', 'master', 60, 'নতুন আইটেম সরাসরি যোগ ও আইটেমের ফ্ল্যাগ বদল (অনুমোদন ছাড়া)', 'নতুন item সরাসরি যোগ ও item flag বদল (approval ছাড়া)', 'Add new items and change item flags at once (no approval)', 'once', null),
 ('asset_manage', 'master', 61, 'সম্পদ-খাতা সম্পাদনা', 'Asset register edit', 'Edit the asset register', 'once', null)
on conflict (grant_code) do nothing;
insert into public.rule_grants (grant_code, role_code)
  select 'asset_manage', 'management' where exists (select 1 from public.roles where code = 'management') and exists (select 1 from public.grant_defs where grant_code = 'asset_manage')
  and not exists (select 1 from public.rule_grants where grant_code = 'asset_manage')
on conflict do nothing;

-- ---------- (4) option lists: units added (existing values are never renamed), asset condition list ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('units', 'ltr', 'লিটার', 'ltr', 'litre', 7), ('units', 'set', 'সেট', 'set', 'set', 8), ('units', 'pair', 'জোড়া', 'pair', 'pair', 9), ('units', 'meter', 'মিটার', 'meter', 'metre', 10),
 ('asset_conditions', 'new', 'নতুন', 'New', 'New', 1), ('asset_conditions', 'good', 'ভালো', 'Good', 'Good', 2), ('asset_conditions', 'fair', 'মোটামুটি', 'Fair', 'Fair', 3),
 ('asset_conditions', 'poor', 'খারাপ', 'Poor', 'Poor', 4), ('asset_conditions', 'broken', 'নষ্ট', 'Broken', 'Broken', 5)
on conflict (list_code, value_code) do nothing;

-- dictionary unit -> the unit code an item stores (old items use kg / pc / lb; the rest are values of the editable units list)
create or replace function public._item_unit_code(p text) returns text language sql immutable set search_path = public as $$
  select case lower(btrim(p)) when 'kg' then 'kg' when 'pc' then 'pc' when 'pound' then 'lb' when 'lb' then 'lb' when 'gm' then 'gram' when 'gram' then 'gram'
    when 'pack' then 'pack' when 'box' then 'box' when 'ltr' then 'ltr' when 'set' then 'set' when 'pair' then 'pair' when 'meter' then 'meter' end;
$$;

-- ---------- (5) type flag defaults ----------
create or replace function public._item_type_flags(p_type text, out o_count boolean, out o_sell boolean) language plpgsql stable security definer set search_path = public as $$
declare t public.item_types;
begin
  select * into t from public.item_types where code = p_type;
  if not found then return; end if;
  o_count := t.count_in_business or (p_type = 'controlled' and public.rule_on('tools_stock_on'));
  o_sell := t.sellable;
  if p_type = 'asset' then o_count := false; o_sell := false; end if;
  if p_type = 'raw_material' then o_sell := false; end if;
end $$;

-- ---------- (6) guard on items: locked, type rules, counted-in-business ----------
create or replace function public._items_p14_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare sys boolean := coalesce(current_setting('bos.item_sys', true), '') = '1'; busy boolean;
begin
  if tg_op = 'UPDATE' and old.locked and not sys and not public.is_owner() then
    if (to_jsonb(new) - 'updated_at' - 'updated_by') is distinct from (to_jsonb(old) - 'updated_at' - 'updated_by') then raise exception 'item_locked'; end if;
  end if;
  if tg_op = 'INSERT' or new.item_type is distinct from old.item_type then
    if not exists (select 1 from public.item_types where code = new.item_type) then raise exception 'bad_item_type'; end if;
  end if;
  if new.item_type = 'asset' then new.sellable := false; new.count_in_business := false; end if;      -- an asset is never sold or counted
  if new.item_type = 'raw_material' then new.sellable := false; end if;                             -- a raw material is never sold
  if not new.count_in_business then
    if tg_op = 'UPDATE' and old.count_in_business then          -- switching off needs an empty shelf: stock would vanish from the books
      select exists (select 1 from public.stock_balance where item_id = new.id and qty <> 0) into busy;
      if busy then raise exception 'item_has_stock'; end if;
    end if;
    new.tracked := false;
  end if;
  if new.sub_category is not null and new.sub_category = '' then new.sub_category := null; end if;
  -- prices: finite and 0 .. 1e9 (a numeric can hold NaN / Infinity); the unit must be an old item unit or a value of the units list
  if new.sell_price is not null and not (new.sell_price between 0 and 1000000000) then raise exception 'bad_price'; end if;
  if new.wholesale_price is not null and not (new.wholesale_price between 0 and 1000000000) then raise exception 'bad_price'; end if;
  if new.unit is not null and (tg_op = 'INSERT' or new.unit is distinct from old.unit) and new.unit not in ('kg', 'pc', 'lb')
     and not exists (select 1 from public.option_lists where list_code = 'units' and value_code = new.unit and active) then raise exception 'bad_unit'; end if;
  return new;
end $$;
drop trigger if exists items_p14_guard on public.items;
create trigger items_p14_guard before insert or update on public.items for each row execute function public._items_p14_guard();

-- the per-row audit line is skipped while a dictionary import runs (the import writes ONE audit line per batch instead)
drop trigger if exists audit_items on public.items;
create trigger audit_items after insert or update on public.items for each row
  when (coalesce(current_setting('bos.item_import', true), '') <> '1') execute function public.log_change('id');

-- ---------- (7) server enforcement: sales and stock ----------
create or replace function public._sale_item_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items; late boolean := new.sold_at < now() - interval '2 minutes'; changed boolean := false;
begin
  if new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found then continue; end if;
    -- sold only when the item is a sellable type, switched on for sale and has a selling price ("Data needed" otherwise)
    if not it.sellable or it.sell_price is null or it.item_type in ('asset', 'raw_material') then
      -- an offline sale made BEFORE the item changed (it was fine at the sale time) is accepted and flagged red; an online attempt is refused
      if late and it.updated_at > new.sold_at then changed := true; continue; end if;
      raise exception 'item_not_sellable' using detail = it.code || ' ' || it.name_bn;
    end if;
  end loop;
  if changed then perform set_config('bos.offline_item_changed', new.id::text, true); end if;
  return new;
end $$;
create or replace function public._sale_item_changed_exc() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('bos.offline_item_changed', true), '') = new.id::text then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, new.id, 'POS', new.location_id, new.sale_date, 'offline_sale_item_changed', 'red', new.total,
        jsonb_build_object('bn', 'রসিদ ' || new.receipt || ': অফলাইনে করা সেল — পরে আইটেমের ফ্ল্যাগ/দাম বদলেছে, সেল গ্রহণ করা হয়েছে', 'en', 'Receipt ' || new.receipt || ': an offline sale was accepted although the item changed (sellable / price / type) after the sale time'));
  end if;
  return null;
end $$;
drop trigger if exists sales_item_guard on public.sales;
create trigger sales_item_guard before insert on public.sales for each row execute function public._sale_item_guard();
drop trigger if exists sales_item_changed_exc on public.sales;
create trigger sales_item_changed_exc after insert on public.sales for each row execute function public._sale_item_changed_exc();

create or replace function public._ledger_item_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if new.reverses_id is not null then return new; end if;                  -- undoing an earlier line is always allowed
  if new.reason = 'sale_out' and new.made_at < now() - interval '2 minutes' then return new; end if;      -- a sale that syncs late has already happened
  select count_in_business into ok from public.items where id = new.item_id;
  if ok is distinct from true then raise exception 'item_not_counted' using detail = new.item_id::text; end if;
  return new;
end $$;
drop trigger if exists stock_ledger_item_guard on public.stock_ledger;
create trigger stock_ledger_item_guard before insert on public.stock_ledger for each row execute function public._ledger_item_guard();

-- reports: stock value, COGS and profit leave out items that are not counted in the business (text patch of the current definitions, run once)
do $$
declare d text; o oid;
begin
  select oid into o from pg_proc where proname = 'stock_valuation' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('where b.qty <> 0' in d) > 0 then execute replace(d, 'where b.qty <> 0', 'where i.count_in_business /* bos14 */ and b.qty <> 0'); end if; end if;
  select oid into o from pg_proc where proname = 'rpt_agg_sql' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = ' in d) > 0 then
      execute replace(d, 'left join public.item_costs c on c.item_id = ', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = '); end if; end if;
  select oid into o from pg_proc where proname = 'biz_daily' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = l.iid' in d) > 0 then
      execute replace(d, 'left join public.item_costs c on c.item_id = l.iid', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = l.iid'); end if; end if;
  select oid into o from pg_proc where proname = 'biz_items' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = i.id' in d) > 0 then
      d := replace(d, 'left join public.item_costs c on c.item_id = i.id', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id');
      d := replace(d, 'where i.is_active or b.iid is not null', 'where (i.is_active and i.sellable) or b.iid is not null');
      execute d; end if; end if;
end $$;

-- ---------- (8) item codes ----------
-- category value (c14) or category number (14) -> the two-digit number used in codes; a category without one gets the next free number (only inside item_new)
create or replace function public._cat_free_no() returns text language sql stable security definer set search_path = public as $$
  select lpad((greatest(
    coalesce((select max((extra->>'cat_no')::int) from public.option_lists where list_code = 'item_categories' and (extra->>'cat_no') ~ '^[0-9]+$'), 0),
    coalesce((select max(substring(code from '^([0-9]+)-[0-9]+$')::int) from public.items where code ~ '^[0-9]+-[0-9]+$'), 0)) + 1)::text, 2, '0');
$$;
create or replace function public._cat_no(p_cat text, p_make boolean default false) returns text language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if p_cat is null or btrim(p_cat) = '' then return null; end if;
  if p_cat ~ '^[0-9]{2,3}$' then return p_cat; end if;
  select extra->>'cat_no' into n from public.option_lists where list_code = 'item_categories' and value_code = p_cat;
  if n is not null and n <> '' then return n; end if;
  if not p_make or not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = p_cat) then return null; end if;
  perform pg_advisory_xact_lock(hashtext('item_cat_no'));
  n := public._cat_free_no();               -- above every category number AND every code prefix in use, so it is unique
  update public.option_lists set extra = extra || jsonb_build_object('cat_no', n) where list_code = 'item_categories' and value_code = p_cat;
  return n;
end $$;
create unique index if not exists option_lists_cat_no_uq on public.option_lists ((extra->>'cat_no')) where list_code = 'item_categories' and (extra->>'cat_no') is not null;

-- next code in a category: highest numeric suffix + 1, zero-padded to 3 digits. Retired items keep their row, so a retired code is never handed out again.
create or replace function public._next_code(p_cat_no text, p_lock boolean) returns text language plpgsql security definer set search_path = public as $$
declare mx int;
begin
  if p_cat_no !~ '^[0-9]{2,3}$' then raise exception 'bad_category'; end if;
  if p_lock then perform pg_advisory_xact_lock(hashtext('item_code:' || p_cat_no)); end if;
  select coalesce(max(substring(code from '^[0-9]+-([0-9]+)$')::int), 0) + 1 into mx from public.items where code like p_cat_no || '-%' and code ~ ('^' || p_cat_no || '-[0-9]+$');
  return p_cat_no || '-' || lpad(mx::text, 3, '0');
end $$;
-- what the screen shows before saving (no lock; the real code is taken inside item_new / apply_item_patch)
create or replace function public.item_next_code(p_category text) returns text language plpgsql stable security definer set search_path = public as $$
declare n text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  n := public._cat_no(p_category, false);
  if n is null then      -- an owner-made category without a number: the number item_new would give it
    if p_category is not null and exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = p_category and active) then return public._cat_free_no() || '-001'; end if;
    return null;
  end if;
  return public._next_code(n, false);
end $$;

-- ---------- (9) create / apply: wrapper around the phase12 apply_item_patch (marker keeps phase12 re-runs a no-op) ----------
create or replace function public._item_create_p14(p_patch jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare iid uuid; cat text := nullif(btrim(p_patch->>'category'), ''); cn text; cd text; ty text := coalesce(nullif(p_patch->>'item_type', ''), 'finished_good'); f record; nbn text;
begin
  nbn := coalesce(nullif(btrim(p_patch->>'name_bn'), ''), nullif(btrim(p_patch->>'name_en'), ''));
  if nbn is null then raise exception 'name_required'; end if;
  if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
  if cat is not null and exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = cat and not active) then raise exception 'category_inactive'; end if;
  cn := public._cat_no(cat, true);
  if cn is not null then cd := public._next_code(cn, true); end if;       -- locked until this transaction ends; the unique index is the backstop
  select * into f from public._item_type_flags(ty);
  insert into public.items (code, name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active, item_type, control_class, count_in_business, sellable)
    values (coalesce(cd, 'I-' || lpad(nextval('item_code_seq')::text, 3, '0')), nbn, nullif(btrim(p_patch->>'name_en'), ''), nullif(btrim(p_patch->>'name_mix'), ''), cat, p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price', '')::numeric, coalesce((p_patch->>'is_active')::boolean, true), ty, nullif(btrim(p_patch->>'control_class'), ''),
            coalesce((p_patch->>'count_in_business')::boolean, f.o_count), coalesce((p_patch->>'sellable')::boolean, f.o_sell))
    returning id into iid;
  return iid;
end $$;

create or replace function public._item_flags_apply(p_item uuid, p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare it public.items; f record; ty text;
begin
  select * into it from public.items where id = p_item;
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
end $$;

-- one place that decides which keys a patch may carry; the flag / type keys only come through item_apply / item_new (they set bos.item_apply)
create or replace function public._item_patch_check(p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare k text; v text; cat text;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name_bn','name_en','name_mix','category','category_bn','unit','sell_price','is_active','sub_category','base_unit','sell_units','wholesale_price','tracked','min_stock',
                 'barcode','source','vat_applicable','images','details','cost_price','item_type','control_class','count_in_business','sellable','locked','hidden','master_code','retired_reason') then
      raise exception 'bad_field';
    end if;
    if k in ('item_type','control_class','count_in_business','sellable','locked','hidden','master_code','retired_reason') and coalesce(current_setting('bos.item_apply', true), '') <> '1' then
      raise exception 'bad_field';
    end if;
  end loop;
  foreach k in array array['sell_price', 'wholesale_price', 'cost_price', 'min_stock'] loop
    v := nullif(btrim(coalesce(p_patch->>k, '')), '');
    if v is not null and (v !~ '^[0-9]{1,10}(\.[0-9]{1,6})?$' or v::numeric > 1000000000) then raise exception 'bad_price'; end if;
  end loop;
  cat := nullif(btrim(coalesce(p_patch->>'category', '')), '');
  if cat is not null and not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = cat) and not exists (select 1 from public.items where category = cat) then raise exception 'bad_category'; end if;
end $$;
create or replace function public._item_changes_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public._item_patch_check(new.patch); return new; end $$;
drop trigger if exists item_changes_guard on public.item_changes;
create trigger item_changes_guard before insert on public.item_changes for each row execute function public._item_changes_guard();

do $$
declare d text := pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure); mk text; done boolean;
begin
  -- already installed? (the marker can sit one level down when phase12 was run after phase14)
  done := position('bos14-master' in d) > 0
       or coalesce(position('bos14-master' in pg_get_functiondef(to_regprocedure('public._apply_item_patch_base(uuid,jsonb)'))) > 0, false);
  if not done then
    -- when phase12 is already in place the new wrapper carries its marker too, so a later re-run of phase12 stays a no-op; without phase12 the marker is left out and phase12 can still add its details step on top
    mk := case when position('bos12-details' in d) > 0 then 'bos12-details' else '' end;
    drop function if exists public._apply_item_patch_p12(uuid, jsonb);
    alter function public.apply_item_patch(uuid, jsonb) rename to _apply_item_patch_p12;
    execute replace($f$
      create function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
      language plpgsql security definer set search_path = public as $b$
      declare iid uuid;   -- bos14-master @MK@ : creation (next code per category) and the item-master fields are done here, everything else by the previous version
      begin
        perform public._item_patch_check(p_patch);
        if p_item is null then iid := public._item_create_p14(p_patch); else iid := p_item; end if;
        iid := public._apply_item_patch_p12(iid, p_patch);
        perform public._item_flags_apply(iid, p_patch);
        return iid;
      end $b$ $f$, '@MK@', mk);
  end if;
end $$;
revoke all on function public.apply_item_patch(uuid, jsonb), public._apply_item_patch_p12(uuid, jsonb), public._item_create_p14(jsonb), public._item_flags_apply(uuid, jsonb),
  public._cat_no(text, boolean), public._next_code(text, boolean), public._item_type_flags(text) from public, anon, authenticated;

-- a request to create an item can also be approved by a person holding item_create (the owner as before; ITEMS approve as before)
create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve') or (public.is_active() and public.has_grant('item_create'))) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform set_config('bos.item_apply', '1', true); perform public.apply_item_patch(c.item_id, c.patch); perform set_config('bos.item_apply', '', true); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_item_change(bigint, boolean, text) from public, anon;
grant execute on function public.decide_item_change(bigint, boolean, text) to authenticated;

-- item_changes: the approval list also shows to item_create holders
drop policy if exists item_changes_read on public.item_changes;
create policy item_changes_read on public.item_changes for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_do('ITEMS', 'approve') or public.has_grant('item_create'));

-- item_apply: change an existing item (any field of apply_item_patch + type / flags). Owner or item_create holder = at once, otherwise a request.
create or replace function public.item_apply(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint; k text; iid uuid;
begin
  if p_item is null or p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;               -- only the owner locks / unlocks
  perform set_config('bos.item_apply', '1', true); perform public._item_patch_check(p_patch);
  if public.is_owner() or public.has_grant('item_create') then
    iid := public.apply_item_patch(p_item, p_patch); perform set_config('bos.item_apply', '', true);
    return jsonb_build_object('status', 'applied', 'item_id', iid);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (p_item, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  perform set_config('bos.item_apply', '', true);
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

-- item_new: add a new item under a category with the next code. Owner / item_create holder: at once. Others: a request (rule item_create_needs_approval off = at once).
create or replace function public.item_new(p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint; iid uuid; direct boolean; ty text; cat text;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_patch->>'name_bn', p_patch->>'name_en')), '') is null then raise exception 'name_required'; end if;
  ty := coalesce(nullif(p_patch->>'item_type', ''), 'finished_good'); cat := nullif(btrim(p_patch->>'category'), '');
  if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
  if cat is not null and not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = cat and active)
     and not exists (select 1 from public.items where category = cat) then raise exception 'bad_category'; end if;
  direct := public.is_owner() or public.has_grant('item_create') or not public.rule_on('item_create_needs_approval');
  perform set_config('bos.item_apply', '1', true); perform public._item_patch_check(p_patch);
  if direct then
    iid := public.apply_item_patch(null, p_patch); perform set_config('bos.item_apply', '', true);
    return jsonb_build_object('status', 'created', 'item_id', iid, 'code', (select code from public.items where id = iid));
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (null, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  perform set_config('bos.item_apply', '', true);
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

-- look-alike check for the ⋮ menu: same name (Bangla / English, ignoring case and spaces), same code prefix, or the same barcode
create or replace function public.item_dup_check(p_name_bn text, p_name_en text, p_exclude uuid default null)
returns table (id uuid, code text, name_bn text, name_en text, why text) language sql stable security definer set search_path = public as $$
  select i.id, i.code, i.name_bn, i.name_en,
         case when lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(coalesce(p_name_bn, ''), '\s+', '', 'g')) then 'same_name_bn' else 'same_name_en' end
  from public.items i
  where public.is_active() and (p_exclude is null or i.id <> p_exclude)
    and ((nullif(btrim(p_name_bn), '') is not null and lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(p_name_bn, '\s+', '', 'g')))
      or (nullif(btrim(p_name_en), '') is not null and i.name_en is not null and lower(regexp_replace(i.name_en, '\s+', '', 'g')) = lower(regexp_replace(p_name_en, '\s+', '', 'g'))))
  order by i.code limit 20;
$$;

-- owner edits of the settings tables (nothing is deleted: active = false retires)
create or replace function public.item_type_set(p_code text, p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare c text := lower(btrim(p_code));
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if c !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code'; end if;
  if not exists (select 1 from public.item_types where code = c) then
    if nullif(btrim(p_patch->>'label_bn'), '') is null then raise exception 'name_required'; end if;
    insert into public.item_types (code, label_bn, sort) values (c, btrim(p_patch->>'label_bn'), coalesce((select max(sort) + 1 from public.item_types), 1));
  end if;
  update public.item_types set
    label_bn = coalesce(nullif(btrim(p_patch->>'label_bn'), ''), label_bn),
    label_mix = case when p_patch ? 'label_mix' then nullif(btrim(p_patch->>'label_mix'), '') else label_mix end,
    label_en = case when p_patch ? 'label_en' then nullif(btrim(p_patch->>'label_en'), '') else label_en end,
    count_in_business = case when p_patch ? 'count_in_business' then (p_patch->>'count_in_business')::boolean else count_in_business end,
    sellable = case when p_patch ? 'sellable' then (p_patch->>'sellable')::boolean else sellable end,
    active = case when p_patch ? 'active' then (p_patch->>'active')::boolean else active end,
    updated_at = now(), updated_by = auth.uid()
  where code = c;
  if c = 'asset' then update public.item_types set count_in_business = false, sellable = false where code = 'asset'; end if;       -- fixed by the rule "an asset is never in stock or sales"
  if c = 'raw_material' then update public.item_types set sellable = false where code = 'raw_material'; end if;
end $$;
create or replace function public.item_class_map_set(p_class text, p_type text, p_active boolean default true) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_class), '') is null then raise exception 'bad_code'; end if;
  if not exists (select 1 from public.item_types where code = p_type) then raise exception 'bad_item_type'; end if;
  insert into public.item_class_map (control_class, item_type, active, updated_by) values (btrim(p_class), p_type, coalesce(p_active, true), auth.uid())
    on conflict (control_class) do update set item_type = excluded.item_type, active = excluded.active, updated_at = now(), updated_by = auth.uid();
end $$;

-- tools stock switch: turning it on counts every controlled item; turning it off needs zero tool stock
create or replace function public._tools_switch() returns trigger language plpgsql security definer set search_path = public as $$
declare v boolean := coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false); n int;
begin
  if new.key <> 'tools_stock_on' then return new; end if;
  perform set_config('bos.item_sys', '1', true); perform set_config('bos.item_import', '1', true);
  if v then update public.items set count_in_business = true where item_type = 'controlled' and not count_in_business and is_active;
  else
    if exists (select 1 from public.stock_balance b join public.items i on i.id = b.item_id where i.item_type = 'controlled' and b.qty <> 0) then raise exception 'tools_stock_has_stock'; end if;
    update public.items set count_in_business = false where item_type = 'controlled' and count_in_business;
  end if;
  get diagnostics n = row_count;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'items', 'tools_stock_on', jsonb_build_object('tools_stock_on', v, 'items_changed', n));
  perform set_config('bos.item_sys', '', true); perform set_config('bos.item_import', '', true);
  return new;
end $$;
drop trigger if exists rules_tools_switch on public.rules;
create trigger rules_tools_switch after update on public.rules for each row when (new.key = 'tools_stock_on' and new.value is distinct from old.value) execute function public._tools_switch();

-- ---------- (10) dictionary import: classify (shared by preview and apply), preview, apply ----------
create table if not exists public.item_import_batches (
  batch_id text primary key check (batch_id ~ '^[A-Za-z0-9_.:-]{3,60}$'),
  started_at timestamptz not null default now(), started_by uuid, last_at timestamptz not null default now(),
  chunks int not null default 0, rows_seen int not null default 0, created int not null default 0, skipped int not null default 0,
  retired int not null default 0, conflicts int not null default 0, expected_rows int,
  detail jsonb not null default '{}'::jsonb
);
alter table public.item_import_batches enable row level security;
drop policy if exists item_import_batches_read on public.item_import_batches;
create policy item_import_batches_read on public.item_import_batches for select to authenticated using (public.is_owner());
revoke all on public.item_import_batches from public, anon, authenticated; grant select on public.item_import_batches to authenticated;

create or replace function public._item_master_classify(p_rows jsonb) returns table (
  ord int, code text, cat_no text, category text, name_en text, name_bn text, subcategory text, unit text, control_class text, note text,
  item_type text, unit_code text, retired boolean, status text, reason text) language sql stable security definer set search_path = public as $$
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
         when exists (select 1 from public.items i where i.code = c.code) then 'skip_existing' else 'create' end,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' then 'bad_code' when c.dup_n > 1 then 'duplicate_in_file' when c.name_en = '' and c.name_bn = '' then 'no_name'
         when c.item_type is null then 'unmapped_class' when c.unit_code is null then 'unknown_unit'
         when c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'category_mismatch'
         when exists (select 1 from public.items i where i.code = c.code) then 'exists' end
  from c order by c.ord;
$$;

create or replace function public.item_master_import_preview(p_rows jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'too_many_rows'; end if;
  with k as (select * from public._item_master_classify(p_rows))
  select jsonb_build_object(
    'total', (select count(*) from k),
    'to_create', (select count(*) from k where status = 'create'),
    'to_create_active', (select count(*) from k where status = 'create' and not retired),
    'to_create_retired', (select count(*) from k where status = 'create' and retired),
    'skip_existing', (select count(*) from k where status = 'skip_existing'),
    'retired_rows', (select count(*) from k where retired),
    'conflicts', (select count(*) from k where status = 'conflict'),
    'conflict_list', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'reason', reason, 'name', coalesce(nullif(name_en, ''), name_bn)) order by ord) from (select * from k where status = 'conflict' order by ord limit 100) z), '[]'::jsonb),
    'by_type', coalesce((select jsonb_object_agg(item_type, n) from (select item_type, count(*) n from k where status = 'create' group by 1) z), '{}'::jsonb),
    'by_unit', coalesce((select jsonb_object_agg(unit_code, n) from (select unit_code, count(*) n from k where status = 'create' group by 1) z), '{}'::jsonb),
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('cat_no', cat_no, 'category', category, 'to_create', cr, 'skip_existing', sk, 'retired', rt, 'conflicts', cf) order by cat_no)
        from (select cat_no, max(category) category, count(*) filter (where status = 'create') cr, count(*) filter (where status = 'skip_existing') sk,
                     count(*) filter (where retired) rt, count(*) filter (where status = 'conflict') cf from k group by cat_no) z), '[]'::jsonb),
    'unmapped_classes', coalesce((select jsonb_agg(distinct control_class) from k where reason = 'unmapped_class'), '[]'::jsonb),
    'priced', 0, 'note', 'No selling price is imported: every new item shows Data needed until a price is written')
  into out_;
  return out_;
end $$;

create or replace function public.item_master_import_apply(p_rows jsonb, p_batch text, p_expected int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; f record; nb boolean := false; cr int := 0; sk int := 0; rt int := 0; cf int := 0; seen int := 0; catv text; subv text; iid uuid; n int; confl jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  if p_batch is null or p_batch !~ '^[A-Za-z0-9_.:-]{3,60}$' then raise exception 'bad_batch'; end if;
  perform pg_advisory_xact_lock(hashtext('item_master_import'));              -- one chunk at a time
  perform set_config('bos.item_import', '1', true); perform set_config('bos.item_sys', '1', true);
  insert into public.item_import_batches (batch_id, started_by, expected_rows) values (p_batch, auth.uid(), p_expected) on conflict (batch_id) do nothing;
  get diagnostics n = row_count; nb := n > 0;
  for r in select * from public._item_master_classify(p_rows) loop
    seen := seen + 1;
    if r.status = 'conflict' then cf := cf + 1; if jsonb_array_length(confl) < 50 then confl := confl || jsonb_build_object('code', r.code, 'reason', r.reason); end if; continue; end if;
    if r.status = 'skip_existing' then sk := sk + 1; continue; end if;
    catv := 'c' || r.cat_no;
    insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
      values ('item_categories', catv, '', r.category, r.cat_no::int, jsonb_build_object('cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    subv := null;
    if r.subcategory <> '' then
      subv := catv || '_' || left(md5(lower(r.subcategory)), 8);
      insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
        values ('item_subcategories', subv, '', r.subcategory, r.cat_no::int, jsonb_build_object('category', catv, 'cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    end if;
    select * into f from public._item_type_flags(r.item_type);
    insert into public.items (code, name_bn, name_en, category, unit, sub_category, sell_price, is_active, item_type, control_class, count_in_business, sellable, tracked, source, import_batch, retired_at, retired_reason)
      values (r.code, coalesce(nullif(r.name_bn, ''), r.name_en), nullif(r.name_en, ''), catv, r.unit_code, subv, null, not r.retired, r.item_type, r.control_class,
              f.o_count and not r.retired, f.o_sell, false, case r.item_type when 'finished_good' then 'made' when 'resale' then 'bought' end, p_batch,
              case when r.retired then now() end, case when r.retired then left(coalesce(nullif(r.note, ''), 'Retired in the dictionary'), 200) end)
      on conflict (code) do nothing;
    get diagnostics n = row_count;
    if n = 0 then sk := sk + 1; continue; end if;
    cr := cr + 1; if r.retired then rt := rt + 1; end if;
  end loop;
  update public.item_import_batches set chunks = chunks + 1, rows_seen = rows_seen + seen, created = created + cr, skipped = skipped + sk, retired = retired + rt,
    conflicts = conflicts + cf, last_at = now(), expected_rows = coalesce(p_expected, expected_rows),
    detail = jsonb_set(detail, '{conflicts}', coalesce(detail->'conflicts', '[]'::jsonb) || confl) where batch_id = p_batch;
  if nb then      -- ONE audit line per batch (the per-row audit is switched off during the import)
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'import', 'items', p_batch, jsonb_build_object('batch', p_batch, 'source', 'item dictionary', 'expected_rows', p_expected));
  end if;
  begin perform public.item_mapping_autolink(); exception when undefined_function then null; end;
  perform set_config('bos.item_import', '', true); perform set_config('bos.item_sys', '', true);
  return jsonb_build_object('batch', p_batch, 'rows', seen, 'created', cr, 'skipped_existing', sk, 'retired_created', rt, 'conflicts', cf, 'conflict_list', confl);
end $$;

-- ---------- (11) old seed items -> dictionary ----------
create table if not exists public.item_mapping_review (
  id bigserial primary key,
  item_id uuid not null unique references public.items(id),
  suggested_code text, confidence numeric(5,3) check (confidence is null or confidence between 0 and 1), auto_ok boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'linked', 'rejected')),
  decided_by uuid, decided_at timestamptz, note text, created_at timestamptz not null default now()
);
create table if not exists public.item_master_links (
  id bigserial primary key,
  item_id uuid not null references public.items(id),          -- the old item (keeps its code and price)
  dict_code text not null,                                    -- the dictionary item it stands for
  active boolean not null default true,
  via text, linked_by uuid, linked_at timestamptz not null default now(), unlinked_at timestamptz
);
create unique index if not exists item_master_links_item_uq on public.item_master_links (item_id) where active;
create unique index if not exists item_master_links_code_uq on public.item_master_links (dict_code) where active;
do $$ declare t text; begin
  foreach t in array array['item_mapping_review', 'item_master_links', 'item_types', 'item_class_map'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, case t when 'item_types' then 'code' when 'item_class_map' then 'control_class' else 'id' end);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
drop policy if exists item_mapping_review_read on public.item_mapping_review;
create policy item_mapping_review_read on public.item_mapping_review for select to authenticated using (public.is_owner() or public.has_grant('item_create'));
drop policy if exists item_master_links_read on public.item_master_links;
create policy item_master_links_read on public.item_master_links for select to authenticated using (public.is_active());
drop policy if exists item_types_read on public.item_types;
create policy item_types_read on public.item_types for select to authenticated using (public.is_active());
drop policy if exists item_class_map_read on public.item_class_map;
create policy item_class_map_read on public.item_class_map for select to authenticated using (public.is_active());
revoke all on public.item_mapping_review, public.item_master_links, public.item_types, public.item_class_map from public, anon, authenticated;
grant select on public.item_mapping_review, public.item_master_links, public.item_types, public.item_class_map to authenticated;
do $$ begin execute 'grant usage, select on sequence public.item_mapping_review_id_seq, public.item_master_links_id_seq to authenticated'; exception when others then null; end $$;

-- rows: [{seed_code, best_code, confidence, auto}] from tools/map_seed_items.py ; existing rows are left alone (a decision is never overwritten)
create or replace function public.item_mapping_load(p_rows jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare e jsonb; iid uuid; n int := 0; s int := 0; cf numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'bad_request'; end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    select id into iid from public.items where code = e->>'seed_code' and import_batch is null;
    cf := nullif(e->>'confidence', '')::numeric;
    if iid is null or cf is null or not (cf between 0 and 1) then s := s + 1; continue; end if;
    insert into public.item_mapping_review (item_id, suggested_code, confidence, auto_ok) values (iid, nullif(e->>'best_code', ''), cf, coalesce((e->>'auto')::int, 0) = 1)
      on conflict (item_id) do nothing;
    get diagnostics n = row_count; if n = 0 then s := s + 1; end if;
  end loop;
  return jsonb_build_object('loaded', jsonb_array_length(p_rows) - s, 'skipped', s);
end $$;

drop function if exists public._item_link(uuid, text, text);
create or replace function public._item_link(p_item uuid, p_dict text, p_via text, p_force boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare tid uuid; cls text;
begin
  select id, control_class into tid, cls from public.items where code = p_dict and import_batch is not null;
  if tid is null then raise exception 'master_code_not_found'; end if;
  if tid = p_item then raise exception 'bad_request'; end if;
  -- an old (sold) item stands for a sellable product; linking it to a material / asset / tool code needs the owner's explicit yes
  if not coalesce(p_force, false) and exists (select 1 from public.items where id = tid and item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled')) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = p_dict and active and item_id <> p_item) then raise exception 'master_code_taken'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active and dict_code <> p_dict;
  insert into public.item_master_links (item_id, dict_code, via, linked_by) select p_item, p_dict, p_via, auth.uid()
    where not exists (select 1 from public.item_master_links where item_id = p_item and dict_code = p_dict and active);
  update public.items set master_code = p_dict, control_class = coalesce(control_class, cls) where id = p_item;
  update public.items set hidden = true, sellable = false where id = tid;           -- the old item stands for it: no second copy in the pickers
  perform set_config('bos.item_sys', '', true);
end $$;

create or replace function public.item_mapping_autolink() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not (public.is_owner() or current_setting('bos.item_import', true) = '1') then raise exception 'not allowed'; end if;
  for r in select m.* from public.item_mapping_review m where m.status = 'pending' and m.auto_ok and m.suggested_code is not null
           and exists (select 1 from public.items t where t.code = m.suggested_code and t.import_batch is not null)
           and not exists (select 1 from public.item_master_links l where l.dict_code = m.suggested_code and l.active) order by m.id loop
    perform public._item_link(r.item_id, r.suggested_code, 'auto', false);
    update public.item_mapping_review set status = 'linked', decided_at = now(), decided_by = auth.uid(), note = 'auto (high confidence)' where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- decide: 'linked' (needs p_dict), 'rejected' (stays a stand-alone old item), 'pending' (undo)
drop function if exists public.item_mapping_decide(uuid, text, text, text);
create or replace function public.item_mapping_decide(p_item uuid, p_dict text, p_status text, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_code text; tid uuid;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_status not in ('linked', 'rejected', 'pending') then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and import_batch is null) then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  if p_status = 'linked' then
    if nullif(btrim(p_dict), '') is null then raise exception 'master_code_not_found'; end if;
    if coalesce(p_force, false) and not public.is_owner() then raise exception 'not allowed'; end if;
    perform public._item_link(p_item, btrim(p_dict), 'manual', p_force);
    update public.item_mapping_review set status = 'linked', suggested_code = coalesce(suggested_code, btrim(p_dict)), decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  else
    select master_code into old_code from public.items where id = p_item;
    if old_code is not null then
      perform set_config('bos.item_sys', '1', true);
      update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active;
      update public.items set master_code = null where id = p_item;
      select id into tid from public.items where code = old_code and import_batch is not null;
      if tid is not null then update public.items set hidden = false, sellable = (select o_sell from public._item_type_flags(items.item_type)) where id = tid; end if;
      perform set_config('bos.item_sys', '', true);
    end if;
    update public.item_mapping_review set status = p_status, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  end if;
  return jsonb_build_object('status', p_status);
end $$;

-- helper trigger functions of phase11 (W1): created here only when phase11 has not been run yet (same text, so a later phase11 changes nothing)
do $$
begin
  if to_regprocedure('public.no_hard_delete()') is null then
    execute $f$create function public.no_hard_delete() returns trigger language plpgsql set search_path = public as $b$ begin raise exception 'nothing is deleted – retire instead'; end $b$ $f$;
  end if;
  if to_regprocedure('public.code_immutable()') is null then
    execute $f$create function public.code_immutable() returns trigger language plpgsql set search_path = public as $b$
      declare c text; o text; n text;
      begin
        foreach c in array tg_argv loop
          o := to_jsonb(old) ->> c; n := to_jsonb(new) ->> c;
          if o is not null and o is distinct from n then raise exception 'code is immutable'; end if;
        end loop;
        return new;
      end $b$ $f$;
  end if;
end $$;

-- ---------- (12) asset register ----------
create sequence if not exists public.asset_tag_seq;
create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  tag text not null unique check (length(tag) between 1 and 60) default ('A-' || lpad(nextval('public.asset_tag_seq')::text, 5, '0')),
  bought_on date,
  condition text,                                           -- value of the list asset_conditions
  status text not null default 'in_use' check (status in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired')),
  maintenance_ref uuid references public.entries(id),       -- the 08-1 maintenance record, optional
  note text, active boolean not null default true,
  purchase_bill_id uuid, purchase_line_id bigint, seq_no int,
  retired_at timestamptz, retired_reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists assets_line_seq_uq on public.assets (purchase_line_id, seq_no) where purchase_line_id is not null;
create index if not exists assets_loc_idx on public.assets (location_id, active);
create index if not exists assets_item_idx on public.assets (item_id);
create table if not exists public.asset_costs (
  asset_id uuid primary key references public.assets(id),
  cost numeric(14,2) check (cost between 0 and 1000000000000),
  updated_at timestamptz not null default now(), updated_by uuid
);
create or replace function public._assets_touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists assets_touch on public.assets;
create trigger assets_touch before update on public.assets for each row execute function public._assets_touch();
drop trigger if exists assets_code_immutable on public.assets;
create trigger assets_code_immutable before update on public.assets for each row execute function public.code_immutable('tag');
drop trigger if exists assets_no_delete on public.assets;
create trigger assets_no_delete before delete on public.assets for each row execute function public.no_hard_delete();
drop trigger if exists audit_assets on public.assets;
create trigger audit_assets after insert or update on public.assets for each row execute function public.log_change('id');
drop trigger if exists audit_asset_costs on public.asset_costs;
create trigger audit_asset_costs after insert or update on public.asset_costs for each row execute function public.log_change('asset_id');
drop trigger if exists asset_costs_no_delete on public.asset_costs;
create trigger asset_costs_no_delete before delete on public.asset_costs for each row execute function public.no_hard_delete();
alter table public.assets enable row level security;
alter table public.asset_costs enable row level security;
drop policy if exists assets_read on public.assets;
create policy assets_read on public.assets for select to authenticated using (public.can_loc(location_id));
drop policy if exists asset_costs_read on public.asset_costs;
create policy asset_costs_read on public.asset_costs for select to authenticated
  using (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost'));
revoke all on public.assets, public.asset_costs from public, anon, authenticated;
grant select on public.assets, public.asset_costs to authenticated;

create or replace function public._asset_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('asset_manage', p_loc));
$$;

-- p: {item_id, location_id, qty (1..200, default 1), tag, bought_on, cost, condition, status, maintenance_ref, note}; cost needs ITEM_COST enter (or the owner)
create or replace function public.asset_add(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.items; loc int; q int; k int; aid uuid; ids uuid[] := '{}'; cost_ numeric; cond text; st text; mref uuid; bo date; tg text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_request'; end if;
  loc := nullif(p->>'location_id', '')::int;
  if loc is null or not public._asset_ok(loc) then raise exception 'not allowed'; end if;
  select * into it from public.items where id = nullif(p->>'item_id', '')::uuid;
  if not found or it.item_type <> 'asset' then raise exception 'not_an_asset_item'; end if;
  q := coalesce(nullif(p->>'qty', '')::int, 1); if q < 1 or q > 200 then raise exception 'bad_qty'; end if;
  tg := nullif(btrim(p->>'tag'), ''); if tg is not null and length(tg) > 60 then raise exception 'tag_too_long'; end if;
  if tg is not null and q > 1 then raise exception 'tag_needs_qty_1'; end if;
  cost_ := nullif(p->>'cost', '')::numeric;
  if cost_ is not null then
    if not (cost_ between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
    if not (public.is_owner() or public.can_do('ITEM_COST', 'enter')) then raise exception 'not allowed to change cost'; end if;
  end if;
  cond := nullif(p->>'condition', ''); if cond is not null and not exists (select 1 from public.option_lists where list_code = 'asset_conditions' and value_code = cond and active) then raise exception 'bad_condition'; end if;
  st := coalesce(nullif(p->>'status', ''), 'in_use'); if st not in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired') then raise exception 'bad_status'; end if;
  mref := nullif(p->>'maintenance_ref', '')::uuid;
  if mref is not null and not exists (select 1 from public.entries where id = mref and form_code = '08-1') then raise exception 'bad_maintenance_ref'; end if;
  bo := nullif(p->>'bought_on', '')::date; if bo is not null and bo > (now() at time zone 'Asia/Dhaka')::date + 1 then raise exception 'bad_date'; end if;
  for k in 1..q loop
    insert into public.assets (item_id, location_id, tag, bought_on, condition, status, maintenance_ref, note)
      values (it.id, loc, coalesce(tg, 'A-' || lpad(nextval('public.asset_tag_seq')::text, 5, '0')), bo, cond, st, mref, left(nullif(btrim(p->>'note'), ''), 300)) returning id into aid;
    if cost_ is not null then insert into public.asset_costs (asset_id, cost, updated_by) values (aid, round(cost_, 2), auth.uid()); end if;
    ids := ids || aid;
  end loop;
  return jsonb_build_object('ids', to_jsonb(ids), 'count', q);
end $$;

create or replace function public.asset_update(p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets; cond text; st text; mref uuid; cost_ numeric;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  if p ? 'location_id' and nullif(p->>'location_id', '')::int is distinct from a.location_id then
    if not public._asset_ok((p->>'location_id')::int) then raise exception 'not allowed'; end if;
    if not exists (select 1 from public.locations where id = (p->>'location_id')::int) then raise exception 'bad_request'; end if;
  end if;
  if p ? 'condition' then cond := nullif(p->>'condition', ''); if cond is not null and not exists (select 1 from public.option_lists where list_code = 'asset_conditions' and value_code = cond and active) then raise exception 'bad_condition'; end if; end if;
  if p ? 'status' then st := p->>'status'; if st not in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired') then raise exception 'bad_status'; end if; end if;
  if p ? 'maintenance_ref' then mref := nullif(p->>'maintenance_ref', '')::uuid; if mref is not null and not exists (select 1 from public.entries where id = mref and form_code = '08-1') then raise exception 'bad_maintenance_ref'; end if; end if;
  if p ? 'cost' then
    if not (public.is_owner() or public.can_do('ITEM_COST', 'enter')) then raise exception 'not allowed to change cost'; end if;
    cost_ := nullif(p->>'cost', '')::numeric; if cost_ is not null and not (cost_ between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
    insert into public.asset_costs (asset_id, cost, updated_by) values (p_id, round(cost_, 2), auth.uid()) on conflict (asset_id) do update set cost = excluded.cost, updated_at = now(), updated_by = auth.uid();
  end if;
  update public.assets set
    location_id = case when p ? 'location_id' then (p->>'location_id')::int else location_id end,
    condition = case when p ? 'condition' then cond else condition end,
    status = case when p ? 'status' then st else status end,
    maintenance_ref = case when p ? 'maintenance_ref' then mref else maintenance_ref end,
    bought_on = case when p ? 'bought_on' then nullif(p->>'bought_on', '')::date else bought_on end,
    note = case when p ? 'note' then left(nullif(btrim(p->>'note'), ''), 300) else note end
  where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.asset_retire(p_id uuid, p_reason text, p_status text default 'retired') returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  if p_status not in ('lost', 'sold', 'retired') then raise exception 'bad_status'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'note_required'; end if;
  update public.assets set active = false, status = p_status, retired_at = coalesce(retired_at, now()), retired_reason = left(btrim(p_reason), 200) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;
create or replace function public.asset_reactivate(p_id uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  if a.purchase_bill_id is not null and exists (select 1 from public.purchase_bills where id = a.purchase_bill_id and status = 'void') then raise exception 'bill_voided'; end if;
  update public.assets set active = true, status = 'in_use', retired_at = null, retired_reason = null where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

-- asset rows from a posted purchase bill (one row per whole unit bought; the cost is the line cost after the bill discount share)
create or replace function public._assets_from_bill(p_bill uuid) returns int language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; q int; k int; net numeric; total int := 0; n int; aid uuid;
begin
  if not public.rule_on('asset_register_on') then return 0; end if;
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'posted' then return 0; end if;
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;
  for ln in select l.*, i.item_type from public.purchase_lines l join public.items i on i.id = l.item_id where l.bill_id = p_bill and i.item_type = 'asset' order by l.line_no loop
    if ln.qty > 200 then raise exception 'asset_qty_too_large'; end if;           -- never cap silently: split the line (or add the rows by hand)
    q := greatest(floor(ln.qty)::int, 1);
    for k in 1..q loop
      insert into public.assets (item_id, location_id, bought_on, condition, status, purchase_bill_id, purchase_line_id, seq_no, note)
        values (ln.item_id, pb.location_id, pb.bill_date, 'new', 'in_use', pb.id, ln.id, k, case when ln.qty <> floor(ln.qty) then 'bought qty ' || ln.qty::text || ' (fraction)' end)
        on conflict (purchase_line_id, seq_no) where purchase_line_id is not null do nothing returning id into aid;
      get diagnostics n = row_count;
      if n > 0 then
        insert into public.asset_costs (asset_id, cost) values (aid, round(ln.unit_cost * net, 2)) on conflict do nothing;
        total := total + 1;
      end if;
    end loop;
  end loop;
  return total;
end $$;

-- a posted purchase RETURN takes the same number of register rows out (latest first, rows of the returned bill first)
create or replace function public._assets_from_return(p_bill uuid) returns int language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; q int; total int := 0; a record;
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'return' or pb.status <> 'posted' then return 0; end if;
  for ln in select l.* from public.purchase_lines l join public.items i on i.id = l.item_id where l.bill_id = p_bill and i.item_type = 'asset' order by l.line_no loop
    q := least(greatest(floor(ln.qty)::int, 1), 200);
    for a in select id from public.assets where item_id = ln.item_id and location_id = pb.location_id and active
             order by (purchase_bill_id is not distinct from pb.ref_bill_id) desc, created_at desc, tag desc limit q loop
      update public.assets set active = false, status = 'retired', retired_at = now(), retired_reason = 'purchase return' where id = a.id;
      total := total + 1;
    end loop;
  end loop;
  return total;
end $$;

do $$
begin
  if position('bos14-assets' in pg_get_functiondef('public.post_purchase(uuid,jsonb)'::regprocedure)) = 0 then
    drop function if exists public._post_purchase_p13(uuid, jsonb);
    alter function public.post_purchase(uuid, jsonb) rename to _post_purchase_p13;
    execute $f$
      create function public.post_purchase(p_id uuid, p_payments jsonb default null) returns jsonb
      language plpgsql security definer set search_path = public as $b$
      declare r jsonb; n int;   -- bos14-assets: posting is done by the previous version; asset-type lines then go to the asset register (never to stock)
      begin
        r := public._post_purchase_p13(p_id, p_payments);
        if coalesce((r->>'dup')::boolean, false) then return r; end if;
        n := public._assets_from_bill(p_id);
        return r || jsonb_build_object('assets_added', n, 'assets_returned', public._assets_from_return(p_id));
      end $b$ $f$;
  end if;
  if position('bos14-assets' in pg_get_functiondef('public.void_purchase(uuid,text)'::regprocedure)) = 0 then
    drop function if exists public._void_purchase_p13(uuid, text);
    alter function public.void_purchase(uuid, text) rename to _void_purchase_p13;
    execute $f$
      create function public.void_purchase(p_id uuid, p_note text) returns jsonb
      language plpgsql security definer set search_path = public as $b$
      declare r jsonb;   -- bos14-assets: the register rows of a voided bill are retired (never deleted)
      begin
        r := public._void_purchase_p13(p_id, p_note);
        update public.assets set active = false, status = 'retired', retired_at = coalesce(retired_at, now()), retired_reason = 'purchase bill voided' where purchase_bill_id = p_id and active;
        return r;
      end $b$ $f$;
  end if;
end $$;
revoke all on function public._post_purchase_p13(uuid, jsonb), public._void_purchase_p13(uuid, text), public._assets_from_bill(uuid), public._assets_from_return(uuid), public._asset_ok(int), public._item_unit_code(text), public._assets_touch(), public._item_patch_check(jsonb), public._item_changes_guard(), public._cat_free_no(), public._sale_item_changed_exc() from public, anon, authenticated;
revoke all on function public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text) from public, anon;
grant execute on function public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text) to authenticated;

-- ---------- (13) execute rights ----------
revoke all on function public.item_next_code(text), public.item_new(jsonb, text), public.item_apply(uuid, jsonb, text), public.item_dup_check(text, text, uuid),
  public.item_type_set(text, jsonb), public.item_class_map_set(text, text, boolean), public.item_master_import_preview(jsonb), public.item_master_import_apply(jsonb, text, int),
  public.item_mapping_load(jsonb), public.item_mapping_autolink(), public.item_mapping_decide(uuid, text, text, text, boolean),
  public.asset_add(jsonb), public.asset_update(uuid, jsonb), public.asset_retire(uuid, text, text), public.asset_reactivate(uuid),
  public._item_link(uuid, text, text, boolean), public._item_master_classify(jsonb), public._items_p14_guard(), public._sale_item_guard(), public._ledger_item_guard(), public._tools_switch(),
  public._item_create_p14(jsonb) from public, anon;
grant execute on function public.item_next_code(text), public.item_new(jsonb, text), public.item_apply(uuid, jsonb, text), public.item_dup_check(text, text, uuid),
  public.item_type_set(text, jsonb), public.item_class_map_set(text, text, boolean), public.item_master_import_preview(jsonb), public.item_master_import_apply(jsonb, text, int),
  public.item_mapping_load(jsonb), public.item_mapping_autolink(), public.item_mapping_decide(uuid, text, text, text, boolean),
  public.asset_add(jsonb), public.asset_update(uuid, jsonb), public.asset_retire(uuid, text, text), public.asset_reactivate(uuid) to authenticated;
revoke all on function public._item_link(uuid, text, text, boolean), public._item_master_classify(jsonb), public._items_p14_guard(), public._sale_item_guard(), public._ledger_item_guard(),
  public._tools_switch(), public._item_create_p14(jsonb) from authenticated;

-- ---------------------------------------------------------------- phase15.sql
-- ============================================================
-- Phase 15 (W3): LIST ADD-RULES + OTHER QUEUE + SHARED LIST CONTROL (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first (phase11 for no_hard_delete / code_immutable is expected; created here only if missing).
--   * option_lists (existing table, no second lists table): + created_by/at, retired_by/at/reason (retire = active=false, never delete)
--   * list_defs: one row per list: add_rule open | approval | owner, allow_other, active, locked, hidden, note
--   * option_add(): the ONLY way a non-owner joins a list; the rule is enforced here (open: at once; approval: option_requests row; owner: owner / list manager only)
--     similar-name check (case / spaces / Bangla digits, contains, one-letter slip) returns the similar options so the screen can say "already exists"
--   * option_requests (+ option_request_decide), list_other_entries (+ option_other_log / option_other_resolve: add as new / merge / reject; rows are never deleted)
--   * maker <> approver; the owner is exempt only while the rule owner_self_approve is ON (default ON)
--   * grant list_manage (owner delegates: decide requests / add to owner-rule lists, all lists) and list_managers (the same, one list only)
--   * retire / reactivate / edit through option_retire / option_reactivate / option_update (reason required for retire)
--   * rules owner_self_approve (on), list_search_min (8)
--   Nothing is deleted. Direct insert / update on option_lists stays owner only (policy option_lists_owner); locked lists refuse every change by trigger.
-- ============================================================

-- ---------- (0) helpers from phase11 (same text; created only so this file also works if phase11 was skipped) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) option_lists: who/when created, who/when/why retired ----------
alter table public.option_lists add column if not exists created_by uuid;
alter table public.option_lists add column if not exists created_at timestamptz;
alter table public.option_lists add column if not exists retired_by uuid;
alter table public.option_lists add column if not exists retired_at timestamptz;
alter table public.option_lists add column if not exists retired_reason text;

-- ---------- (2) list_defs ----------
create table if not exists public.list_defs (
  list_code text primary key,
  add_rule text not null default 'approval' check (add_rule in ('open', 'approval', 'owner')),
  allow_other boolean not null default true,
  active boolean not null default true,
  locked boolean not null default false,
  hidden boolean not null default false,
  note text, title_bn text, title_en text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.list_defs (list_code) select distinct list_code from public.option_lists on conflict (list_code) do nothing;
alter table public.list_defs enable row level security;
drop policy if exists list_defs_read on public.list_defs;
create policy list_defs_read on public.list_defs for select to authenticated using (public.is_active());
revoke all on public.list_defs from anon, authenticated;
grant select on public.list_defs to authenticated;
drop trigger if exists audit_list_defs on public.list_defs;
create trigger audit_list_defs after insert or update on public.list_defs for each row execute function public.log_change('list_code');
drop trigger if exists list_defs_no_delete on public.list_defs;
create trigger list_defs_no_delete before delete on public.list_defs for each row execute function public.no_hard_delete();
drop trigger if exists list_defs_code_immutable on public.list_defs;
create trigger list_defs_code_immutable before update on public.list_defs for each row execute function public.code_immutable('list_code');

-- ---------- (3) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবে', 'The owner may approve his / her own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner এর request ও অন্য অনুমতিপ্রাপ্ত কেউ approve করবে', 'Off = even the owner''s own request must be decided by another person who holds list_manage', 210),
 ('list_search_min', 'lists', 'number', '8', null, null, 1, 200, 'তালিকায় এর বেশি অপশন থাকলে সার্চ বক্স দেখাবে', 'List এ এর বেশি option থাকলে search box দেখাবে', 'Show a search box when a list has more options than this', null, null, 'Used by the shared list control in forms', 211)
on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('other_pending_cap', 'lists', 'number', '50', null, null, 1, 10000, 'একজনের সর্বোচ্চ অপেক্ষমাণ "অন্যান্য" লেখা', 'একজনের maximum pending "Other" লেখা', 'Most pending "Other" write-ins one person may have', null, null, 'More are refused until the owner decides some', 212)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('list_manage', 'master', 62, 'তালিকা পরিচালনা: নতুন অপশনের অনুরোধ ও "অন্যান্য" তালিকা সিদ্ধান্ত, মালিক-নিয়মের তালিকায় যোগ', 'List পরিচালনা: নতুন option এর request ও "Other" queue সিদ্ধান্ত, owner-rule list এ যোগ', 'Manage lists: decide new-option requests and the Other queue, add to owner-rule lists', 'once', null)
on conflict (grant_code) do nothing;

-- one list only (the owner delegates a single list to a person)
create table if not exists public.list_managers (
  list_code text not null, user_id uuid not null references public.profiles(id),
  active boolean not null default true, granted_by uuid, granted_at timestamptz not null default now(),
  primary key (list_code, user_id)
);
alter table public.list_managers enable row level security;
drop policy if exists list_managers_read on public.list_managers;
create policy list_managers_read on public.list_managers for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.list_managers from anon, authenticated;
grant select on public.list_managers to authenticated;
drop trigger if exists audit_list_managers on public.list_managers;
create trigger audit_list_managers after insert or update on public.list_managers for each row execute function public.log_change('list_code,user_id');
drop trigger if exists list_managers_no_delete on public.list_managers;
create trigger list_managers_no_delete before delete on public.list_managers for each row execute function public.no_hard_delete();

-- may the caller manage this list (decide requests / Other queue, add to an owner-rule list)?
create or replace function public._list_mgr(p_list text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('list_manage')
    or exists (select 1 from public.list_managers m where m.list_code = p_list and m.user_id = auth.uid() and m.active)));
$$;

create or replace function public.list_manager_set(p_list text, p_user uuid, p_on boolean default true) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  insert into public.list_managers (list_code, user_id, active, granted_by) values (p_list, p_user, coalesce(p_on, true), auth.uid())
    on conflict (list_code, user_id) do update set active = coalesce(p_on, true), granted_by = auth.uid(), granted_at = now();
end $$;

-- ---------- (4) name helpers (similar-name check) ----------
create or replace function public._opt_norm(p text) returns text
language sql immutable set search_path = public as $$
  -- NFC, zero-width joiners and the danda removed, precomposed য় ড় ঢ় written as base + nukta, Bangla digits as ASCII digits
  select regexp_replace(translate(replace(replace(replace(replace(replace(replace(normalize(lower(coalesce(p, '')), NFC),
      U&'\200C', ''), U&'\200D', ''), U&'\09DF', U&'\09AF\09BC'), U&'\09DC', U&'\09A1\09BC'), U&'\09DD', U&'\09A2\09BC'), U&'\0964', ''),
      '০১২৩৪৫৬৭৮৯', '0123456789'), '[[:space:].,;:!?(){}/_&+-]+', '', 'g');
$$;
-- true when the two (already normalised) names differ by one inserted / removed / changed character (both at least 4 long)
create or replace function public._opt_lev1(a text, b text) returns boolean
language plpgsql immutable set search_path = public as $$
declare la int := length(coalesce(a, '')); lb int := length(coalesce(b, '')); i int := 1;
begin
  if abs(la - lb) > 1 or least(la, lb) < 4 then return false; end if;
  if a = b then return true; end if;
  while i <= least(la, lb) and substr(a, i, 1) = substr(b, i, 1) loop i := i + 1; end loop;
  if la = lb then return substr(a, i + 1) = substr(b, i + 1);
  elsif la > lb then return substr(a, i + 1) = substr(b, i);
  else return substr(a, i) = substr(b, i + 1); end if;
end $$;

-- similar existing options (active AND retired ones, so a retired value is not re-added by accident)
create or replace function public.option_similar(p_list text, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare names text[]; r record; rn text[]; k text; res jsonb := '[]'; hit text; a text; b text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if length(coalesce(p_bn, '')) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  names := array(select x from unnest(array[public._opt_norm(p_bn), public._opt_norm(p_en), public._opt_norm(p_mix)]) x where x <> '');
  if coalesce(array_length(names, 1), 0) = 0 then return res; end if;
  for r in select * from public.option_lists where list_code = p_list order by sort loop
    rn := array(select x from unnest(array[public._opt_norm(r.label_bn), public._opt_norm(r.label_en), public._opt_norm(r.label_mix), public._opt_norm(r.value_code)]) x where x <> '');
    hit := null;
    foreach a in array names loop
      foreach b in array rn loop
        if a = b then hit := 'same';
        elsif hit is distinct from 'same' and least(length(a), length(b)) >= 3 and (position(a in b) > 0 or position(b in a) > 0) then hit := coalesce(hit, 'contains');
        elsif hit is null and public._opt_lev1(a, b) then hit := 'close'; end if;
      end loop;
    end loop;
    if hit is not null then
      res := res || jsonb_build_array(jsonb_build_object('value_code', r.value_code, 'label_bn', r.label_bn, 'label_en', r.label_en, 'label_mix', r.label_mix, 'active', r.active, 'kind', hit));
    end if;
  end loop;
  -- same first, then contains, then close; at most 8
  return coalesce((select jsonb_agg(e) from (select e from jsonb_array_elements(res) e
      order by case e->>'kind' when 'same' then 0 when 'contains' then 1 else 2 end limit 8) q), '[]'::jsonb);
end $$;

-- ---------- (5) option_lists guard: audit fields, retire stamps, locked lists ----------
create or replace function public.option_lists_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lk boolean;
begin
  if tg_op = 'INSERT' then
    insert into public.list_defs (list_code) values (new.list_code) on conflict (list_code) do nothing;
  end if;
  select locked into lk from public.list_defs where list_code = new.list_code;
  if tg_op = 'INSERT' then
    if coalesce(lk, false) then raise exception 'list_locked'; end if;
    new.created_by := coalesce(new.created_by, auth.uid()); new.created_at := coalesce(new.created_at, now());
    if not new.active then new.retired_at := coalesce(new.retired_at, now()); new.retired_by := coalesce(new.retired_by, auth.uid()); end if;
    return new;
  end if;
  if coalesce(lk, false) and (new.label_bn is distinct from old.label_bn or new.label_en is distinct from old.label_en or new.label_mix is distinct from old.label_mix
     or new.active is distinct from old.active or new.sort is distinct from old.sort or (new.extra - 'cat_no') is distinct from (old.extra - 'cat_no')) then
    raise exception 'list_locked';
  end if;
  if old.active and not new.active then
    new.retired_at := now(); new.retired_by := auth.uid();
  elsif not old.active and new.active then
    new.retired_at := null; new.retired_by := null; new.retired_reason := null;          -- the audit log keeps the history
  end if;
  return new;
end $$;
drop trigger if exists option_lists_guard on public.option_lists;
create trigger option_lists_guard before insert or update on public.option_lists for each row execute function public.option_lists_guard();

-- ---------- (6) requests and the Other queue ----------
create table if not exists public.option_requests (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, label_bn text not null, label_en text, label_mix text, extra jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid not null default auth.uid(), requested_at timestamptz not null default now(),
  client_id uuid, similar_opts jsonb,
  decided_by uuid, decided_at timestamptz, decision_note text, resulting_value text
);
create unique index if not exists option_requests_client_uq on public.option_requests (requested_by, client_id) where client_id is not null;
create index if not exists option_requests_list_idx on public.option_requests (list_code, status);
create table if not exists public.list_other_entries (
  id uuid primary key default gen_random_uuid(),
  list_code text not null, text text not null check (length(text) between 1 and 200),
  entered_by uuid not null default auth.uid(), entered_at timestamptz not null default now(),
  form_code text, entry_id uuid, client_id uuid, ctx jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'merged', 'added', 'rejected')),
  resolved_option text, resolved_by uuid, resolved_at timestamptz, resolved_note text
);
create unique index if not exists list_other_client_uq on public.list_other_entries (entered_by, client_id) where client_id is not null;
create index if not exists list_other_list_idx on public.list_other_entries (list_code, status);
alter table public.option_requests enable row level security;
alter table public.list_other_entries enable row level security;
drop policy if exists option_requests_read on public.option_requests;
create policy option_requests_read on public.option_requests for select to authenticated using (requested_by = auth.uid() or public._list_mgr(list_code));
drop policy if exists list_other_read on public.list_other_entries;
create policy list_other_read on public.list_other_entries for select to authenticated using (entered_by = auth.uid() or public._list_mgr(list_code));
revoke all on public.option_requests, public.list_other_entries from anon, authenticated;
grant select on public.option_requests, public.list_other_entries to authenticated;
drop trigger if exists audit_option_requests on public.option_requests;
create trigger audit_option_requests after insert or update on public.option_requests for each row execute function public.log_change('id');
drop trigger if exists audit_list_other on public.list_other_entries;
create trigger audit_list_other after insert or update on public.list_other_entries for each row execute function public.log_change('id');
drop trigger if exists option_requests_no_delete on public.option_requests;
create trigger option_requests_no_delete before delete on public.option_requests for each row execute function public.no_hard_delete();
drop trigger if exists list_other_no_delete on public.list_other_entries;
create trigger list_other_no_delete before delete on public.list_other_entries for each row execute function public.no_hard_delete();

-- ---------- (7) insert one option (internal): unique, immutable value_code ----------
create or replace function public._opt_insert(p_list text, p_bn text, p_en text, p_mix text, p_extra jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare base text; vc text; n int := 1; mx int;
begin
  perform pg_advisory_xact_lock(hashtext('optlist:' || p_list));
  base := left(trim(both '_' from lower(regexp_replace(coalesce(nullif(btrim(p_en), ''), ''), '[^a-zA-Z0-9]+', '_', 'g'))), 24);
  if base is null or base = '' then base := 'o'; end if;
  vc := base;
  while vc = 'other' or exists (select 1 from public.option_lists where list_code = p_list and value_code = vc) loop n := n + 1; vc := base || '_' || n; end loop;   -- retired codes stay reserved
  select coalesce(max(sort), 0) + 1 into mx from public.option_lists where list_code = p_list;
  insert into public.option_lists (list_code, value_code, label_bn, label_en, label_mix, sort, active, extra, created_by, created_at)
    values (p_list, vc, btrim(p_bn), nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), mx, true, coalesce(p_extra, '{}'), auth.uid(), now());
  return vc;
end $$;

-- ---------- (8) option_add: THE add path; the list's rule is enforced here ----------
create or replace function public.option_add(p_list text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default '{}',
                                             p_force boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; sim jsonb; same jsonb; bn text := nullif(btrim(p_bn), ''); mgr boolean; direct boolean; rq public.option_requests; vc text; rid uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if bn is null or public._opt_norm(bn) = '' then raise exception 'name_required'; end if;
  if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and jsonb_typeof(p_extra) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.list_defs where list_code = p_list) and not exists (select 1 from public.option_lists where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  select * into d from public.list_defs where list_code = p_list;
  if not d.active then raise exception 'list_inactive'; end if;
  if d.locked then raise exception 'list_locked'; end if;
  if p_client is not null then
    select * into rq from public.option_requests where requested_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('status', case rq.status when 'approved' then 'added' else 'requested' end, 'request_id', rq.id, 'value_code', rq.resulting_value, 'repeat', true); end if;
  end if;
  sim := public.option_similar(p_list, bn, p_en, p_mix);
  select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
  if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
  if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
  mgr := public._list_mgr(p_list);
  -- limits, cat_no and the like are business data: only the owner / a list manager may send them along (everybody else's extra is dropped)
  p_extra := case when mgr then coalesce(p_extra, '{}') - 'cat_no' else '{}'::jsonb end;
  direct := d.add_rule = 'open' or (d.add_rule = 'owner' and mgr) or (d.add_rule = 'approval' and public.is_owner() and public.rule_on('owner_self_approve'));
  if direct then
    vc := public._opt_insert(p_list, bn, p_en, p_mix, p_extra);
    return jsonb_build_object('status', 'added', 'value_code', vc);
  end if;
  if d.add_rule = 'owner' then raise exception 'owner_only'; end if;
  -- approval: a pending request (the same name already waiting is not filed twice)
  select * into rq from public.option_requests where list_code = p_list and status = 'pending' and public._opt_norm(label_bn) = public._opt_norm(bn) limit 1;
  if found then return jsonb_build_object('status', 'requested', 'request_id', rq.id, 'duplicate', true); end if;
  insert into public.option_requests (list_code, label_bn, label_en, label_mix, extra, client_id, similar_opts)
    values (p_list, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), coalesce(p_extra, '{}'), p_client, case when jsonb_array_length(sim) > 0 then sim end) returning id into rid;
  return jsonb_build_object('status', 'requested', 'request_id', rid);
end $$;

-- ---------- (9) decide a request: owner or list manager; maker <> approver (owner exempt only while owner_self_approve is on) ----------
create or replace function public.option_request_decide(p_id uuid, p_approve boolean, p_note text default null, p_bn text default null, p_en text default null, p_mix text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.option_requests; d public.list_defs; vc text; bn text; same text;
begin
  select * into r from public.option_requests where id = p_id;
  if not found then raise exception 'request_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));
  select * into r from public.option_requests where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resulting_value, 'repeat', true); end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  if coalesce(p_approve, false) then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.label_bn);
    select e->>'value_code' into same from jsonb_array_elements(public.option_similar(r.list_code, bn, coalesce(p_en, r.label_en), coalesce(p_mix, r.label_mix))) e where e->>'kind' = 'same' and (e->>'active')::boolean limit 1;
    vc := coalesce(same, public._opt_insert(r.list_code, bn, coalesce(nullif(btrim(p_en), ''), r.label_en), coalesce(nullif(btrim(p_mix), ''), r.label_mix), r.extra));
    update public.option_requests set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300), resulting_value = vc where id = p_id;
    return jsonb_build_object('status', 'approved', 'value_code', vc);
  end if;
  update public.option_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 300) where id = p_id;
  return jsonb_build_object('status', 'rejected');
end $$;

-- ---------- (10) Other queue ----------
create or replace function public.option_other_log(p_list text, p_text text, p_ctx jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.list_defs; tx text := nullif(btrim(p_text), ''); ex record; rid uuid; cl uuid; ent uuid; cap int; c2 jsonb := '{}'; k text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if tx is null or public._opt_norm(tx) = '' then raise exception 'name_required'; end if;
  if length(tx) > 200 then raise exception 'name_too_long'; end if;
  select * into d from public.list_defs where list_code = p_list;
  if not found then raise exception 'unknown_list'; end if;
  if not d.allow_other or not d.active then raise exception 'other_not_allowed'; end if;
  p_ctx := case when jsonb_typeof(coalesce(p_ctx, '{}')) = 'object' then coalesce(p_ctx, '{}') else '{}'::jsonb end;
  if length(p_ctx::text) > 2048 then raise exception 'ctx_too_large'; end if;
  begin cl := nullif(p_ctx->>'client_id', '')::uuid; exception when others then cl := null; end;
  begin ent := nullif(p_ctx->>'entry_id', '')::uuid; exception when others then ent := null; end;
  foreach k in array array['form_code', 'item_id', 'field', 'supplier_id'] loop       -- only these keys are kept, each a short string
    if p_ctx ? k and jsonb_typeof(p_ctx->k) = 'string' then c2 := c2 || jsonb_build_object(k, left(p_ctx->>k, 60)); end if;
  end loop;
  if cl is not null then
    select id, status into ex from public.list_other_entries where entered_by = auth.uid() and client_id = cl;
    if found then return jsonb_build_object('status', ex.status, 'id', ex.id, 'repeat', true); end if;
  end if;
  -- a text that is already a listed option is not queued: the screen uses the option
  select o.value_code into ex from public.option_lists o where o.list_code = p_list and o.active
    and public._opt_norm(tx) in (public._opt_norm(o.label_bn), public._opt_norm(o.label_en), public._opt_norm(o.label_mix)) limit 1;
  if found then return jsonb_build_object('status', 'exists', 'value_code', ex.value_code); end if;
  cap := coalesce(public.rule_num('other_pending_cap'), 50)::int;
  if (select count(*) from public.list_other_entries where entered_by = auth.uid() and status = 'pending') >= cap then raise exception 'other_queue_full'; end if;
  insert into public.list_other_entries (list_code, text, form_code, entry_id, client_id, ctx)
    values (p_list, tx, left(p_ctx->>'form_code', 20), ent, cl, c2) returning id into rid;
  return jsonb_build_object('status', 'pending', 'id', rid);
end $$;

-- p_action: 'add' (becomes a new option), 'merge' (joins p_value, an existing option), 'reject'. Equal texts waiting in the same list are decided together.
drop function if exists public.option_other_resolve(uuid, text, text, text, text, text, text);
create or replace function public.option_other_resolve(p_id uuid, p_action text, p_value text default null, p_bn text default null, p_en text default null, p_mix text default null, p_note text default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.list_other_entries; d public.list_defs; vc text; bn text; ownok boolean; st text; n int; o public.option_lists; sim jsonb; same jsonb;
begin
  select * into r from public.list_other_entries where id = p_id;
  if not found then raise exception 'other_not_found'; end if;
  perform pg_advisory_xact_lock(hashtext('optlist:' || r.list_code));          -- one lock per list, always taken first: no deadlock between two deciders
  select * into r from public.list_other_entries where id = p_id for update;
  if not public._list_mgr(r.list_code) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then return jsonb_build_object('status', r.status, 'value_code', r.resolved_option, 'repeat', true); end if;
  ownok := public.is_owner() and public.rule_on('owner_self_approve');
  if r.entered_by = auth.uid() and not ownok then raise exception 'self_approval'; end if;
  if p_action = 'reject' then
    st := 'rejected'; vc := null;
  elsif p_action = 'merge' then
    select * into o from public.option_lists where list_code = r.list_code and value_code = p_value;
    if not found then raise exception 'bad_option'; end if;
    if not o.active then raise exception 'option_inactive'; end if;
    st := 'merged'; vc := p_value;
  elsif p_action = 'add' then
    select * into d from public.list_defs where list_code = r.list_code;
    if d.locked then raise exception 'list_locked'; end if;
    if not d.active then raise exception 'list_inactive'; end if;
    bn := coalesce(nullif(btrim(p_bn), ''), r.text);
    if length(bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
    sim := public.option_similar(r.list_code, bn, p_en, p_mix);
    select e into same from jsonb_array_elements(sim) e where e->>'kind' = 'same' limit 1;
    if same is not null then return jsonb_build_object('status', 'exists', 'value_code', same->>'value_code', 'similar', sim); end if;
    if jsonb_array_length(sim) > 0 and not coalesce(p_force, false) then return jsonb_build_object('status', 'similar', 'similar', sim); end if;
    vc := public._opt_insert(r.list_code, bn, nullif(btrim(p_en), ''), nullif(btrim(p_mix), ''), '{}');
    st := 'added';
  else raise exception 'bad_value'; end if;
  update public.list_other_entries set status = st, resolved_option = vc, resolved_by = auth.uid(), resolved_at = now(), resolved_note = left(p_note, 300)
    where id in (select id from public.list_other_entries where list_code = r.list_code and status = 'pending' and public._opt_norm(text) = public._opt_norm(r.text)
                   and (entered_by <> auth.uid() or ownok or id = p_id) order by id for update);
  get diagnostics n = row_count;
  return jsonb_build_object('status', st, 'value_code', vc, 'resolved', n);
end $$;

-- ---------- (11) edit / retire / reactivate (owner or list manager); retire needs a reason; nothing is deleted ----------
create or replace function public.option_retire(p_list text, p_value text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'reason_required'; end if;
  select * into o from public.option_lists where list_code = p_list and value_code = p_value for update;
  if not found then raise exception 'bad_option'; end if;
  if not o.active then return jsonb_build_object('status', 'retired', 'repeat', true); end if;
  update public.option_lists set active = false, retired_reason = left(btrim(p_reason), 200) where list_code = p_list and value_code = p_value;
  return jsonb_build_object('status', 'retired');
end $$;
create or replace function public.option_reactivate(p_list text, p_value text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  update public.option_lists set active = true where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'active');
end $$;
drop function if exists public.option_update(text, text, text, text, text);
create or replace function public.option_update(p_list text, p_value text, p_bn text, p_en text default null, p_mix text default null, p_extra jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_bn), '') is null then raise exception 'name_required'; end if;
  if length(p_bn) > 120 or length(coalesce(p_en, '')) > 120 or length(coalesce(p_mix, '')) > 120 then raise exception 'name_too_long'; end if;
  if p_extra is not null and (jsonb_typeof(p_extra) <> 'object' or not public.is_owner()) then raise exception 'not allowed'; end if;   -- limits and the like: owner only
  update public.option_lists set label_bn = btrim(p_bn), label_en = nullif(btrim(p_en), ''), label_mix = nullif(btrim(p_mix), ''),
      extra = case when p_extra is null then extra else jsonb_strip_nulls((extra - 'limit_month') || (p_extra - 'cat_no')) end
    where list_code = p_list and value_code = p_value;
  if not found then raise exception 'bad_option'; end if;
  return jsonb_build_object('status', 'saved');
end $$;
create or replace function public.option_reorder(p_list text, p_codes text[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int := 0; c text;
begin
  if not public._list_mgr(p_list) then raise exception 'not allowed'; end if;
  foreach c in array coalesce(p_codes, '{}') loop
    i := i + 1;
    update public.option_lists set sort = i where list_code = p_list and value_code = c;
  end loop;
  return jsonb_build_object('status', 'saved', 'n', i);
end $$;

-- owner edits the list's own settings (rule, Other on/off, active, locked, hidden, note, titles)
create or replace function public.list_def_set(p_list text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.option_lists where list_code = p_list) and not exists (select 1 from public.list_defs where list_code = p_list) then raise exception 'unknown_list'; end if;
  insert into public.list_defs (list_code) values (p_list) on conflict (list_code) do nothing;
  for k, v in select * from jsonb_each(p_patch) loop
    if k = 'add_rule' then
      if jsonb_typeof(v) <> 'string' or (v #>> '{}') not in ('open', 'approval', 'owner') then raise exception 'bad_value'; end if;
      update public.list_defs set add_rule = v #>> '{}' where list_code = p_list;
    elsif k in ('allow_other', 'active', 'locked', 'hidden') then
      if jsonb_typeof(v) <> 'boolean' then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = $1 where list_code = $2', k) using (v #>> '{}')::boolean, p_list;
    elsif k in ('note', 'title_bn', 'title_en') then
      if jsonb_typeof(v) not in ('string', 'null') then raise exception 'bad_value'; end if;
      execute format('update public.list_defs set %I = left(nullif(btrim($1), ''''), 200) where list_code = $2', k) using v #>> '{}', p_list;
    else raise exception 'bad_value'; end if;
  end loop;
  update public.list_defs set updated_at = now(), updated_by = auth.uid() where list_code = p_list;
  return (select to_jsonb(x) from public.list_defs x where list_code = p_list);
end $$;

-- ---------- (12) counts for the Needs-you badge (only for people who may decide) ----------
create or replace function public.list_queue_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb := '{"requests":0,"other":0,"lists":{}}'; r record; rq int := 0; ot int := 0;
begin
  if not public.is_active() then return res; end if;
  for r in select d.list_code,
      (select count(*) from public.option_requests q where q.list_code = d.list_code and q.status = 'pending') as rq,
      (select count(*) from public.list_other_entries o where o.list_code = d.list_code and o.status = 'pending') as ot
    from public.list_defs d loop
    if (r.rq > 0 or r.ot > 0) and public._list_mgr(r.list_code) then
      rq := rq + r.rq; ot := ot + r.ot;
      res := jsonb_set(res, array['lists', r.list_code], jsonb_build_object('requests', r.rq, 'other', r.ot));
    end if;
  end loop;
  return jsonb_set(jsonb_set(res, '{requests}', to_jsonb(rq)), '{other}', to_jsonb(ot));
end $$;

-- ---------- (13) privileges: authenticated only; internal helpers not callable from outside ----------
revoke all on function public._opt_insert(text, text, text, text, jsonb), public.option_lists_guard() from public, anon, authenticated;
revoke all on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) from public, anon;
grant execute on function public.option_add(text, text, text, text, jsonb, boolean, uuid), public.option_request_decide(uuid, boolean, text, text, text, text),
  public.option_other_log(text, text, jsonb), public.option_other_resolve(uuid, text, text, text, text, text, text, boolean), public.option_retire(text, text, text),
  public.option_reactivate(text, text), public.option_update(text, text, text, text, text, jsonb), public.option_reorder(text, text[]), public.list_def_set(text, jsonb),
  public.list_manager_set(text, uuid, boolean), public.list_queue_counts(), public.option_similar(text, text, text, text), public._list_mgr(text),
  public._opt_norm(text), public._opt_lev1(text, text) to authenticated;

-- ---------------------------------------------------------------- phase16.sql
-- ============================================================
-- Phase 16 (W4): LOCATIONS (kind / model / status / hub / setup steps / pause / close) + CONTROL CENTER counts
--                + SETTINGS SHEET 0-1 VERSIONS (get_limit)   (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase14 applied first. Does NOT need phase15 (list_defs / list_queue_counts are used only when they exist).
--   * locations (existing table): + kind, model, status (planned | setting_up | live | paused | closed), supplied_by, planned_opening, hub_functions,
--     note, paused_reason/by/at, closed_reason/by/at, status_by/at, created_by/at.  Existing 7 rows: kind/model/status filled ONCE
--     (all live, except the stopped Mujgunni factory `mishti_factory` = paused).  Codes stay immutable (phase11); nothing is deleted.
--   * option list 'location_models' (A own place, B franchise, C funded; B and C start retired = hidden, the owner switches them on in Lists)
--   * location_setup_steps: 17 steps per new place (read from Build command 5), gate: steps 1-15 (optional ones aside) before 16 (start)
--   * RPC location_save (edit / add a new place; code = slug of the name, unique), location_set_status (pause / resume / close with checklist
--     warnings; the owner may override), location_set_active, location_step_set, location_steps_init, location_close_check
--   * grants location_manage, head_management, settings_approve (owner delegates; has_grant()); rules location_block_when_paused (ON),
--     location_start_first_of_month (OFF), block_on_missing_limit (OFF), owner_self_approve (ON, same key as phase15)
--   * a paused / closed place refuses NEW entries and sales on the server (triggers on entries and sales); reading stays open
--   * settings_sheets + settings_values: versions of the Location Settings Sheet 0-1, seeded as approved version 1 from location_settings;
--     draft -> approve (maker <> approver, the owner exempt while owner_self_approve is ON); get_limit(loc, key, date) returns the value in force
--     on that date or NULL (= Data needed).  location_settings stays readable and is written through, so every old screen keeps working;
--     an edit through the old screen makes a new (auto) version.
--   * control_counts(): the merged "Needs you" counts for the Control Center / Home (only what the caller may decide)
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / phase15; created only so this file also works alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) locations: new columns ----------
alter table public.locations add column if not exists kind text;
alter table public.locations add column if not exists model text;
alter table public.locations add column if not exists status text not null default 'live';
alter table public.locations add column if not exists supplied_by int references public.locations(id);
alter table public.locations add column if not exists planned_opening date;
alter table public.locations add column if not exists hub_functions boolean not null default false;
alter table public.locations add column if not exists note text;
alter table public.locations add column if not exists paused_reason text;
alter table public.locations add column if not exists paused_by uuid;
alter table public.locations add column if not exists paused_at timestamptz;
alter table public.locations add column if not exists closed_reason text;
alter table public.locations add column if not exists closed_by uuid;
alter table public.locations add column if not exists closed_at timestamptz;
alter table public.locations add column if not exists status_by uuid;
alter table public.locations add column if not exists status_at timestamptz;
alter table public.locations add column if not exists created_by uuid;
alter table public.locations add column if not exists created_at timestamptz default now();
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'locations_kind_chk') then
    alter table public.locations add constraint locations_kind_chk check (kind is null or kind in ('showroom', 'factory', 'godown', 'hub', 'online', 'other'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'locations_status_chk') then
    alter table public.locations add constraint locations_status_chk check (status in ('planned', 'setting_up', 'live', 'paused', 'closed'));
  end if;
end $$;

-- the seven existing places: filled ONCE (kind is null only before the first run), never overwritten afterwards
update public.locations set
  kind = case code when 'cake_factory' then 'factory' when 'mishti_factory' then 'factory' when 'godown' then 'godown' else 'showroom' end,
  model = 'A',
  hub_functions = (code = 'main'),
  status = case when code = 'mishti_factory' or not is_active then 'paused' else 'live' end,
  paused_reason = case when code = 'mishti_factory' then 'বন্ধ মুজগুন্নি কারখানা (যন্ত্র রাখা) / stopped Mujgunni factory'
                       when not is_active then 'inactive before phase16' end,
  paused_at = case when code = 'mishti_factory' or not is_active then now() end,
  status_at = now()
where kind is null and code in ('main', 'branch2', 'mishti_bari', 'al_cakes', 'cake_factory', 'mishti_factory', 'godown');
-- any other pre-existing row (added by SQL by hand): showroom, own place, live unless inactive
update public.locations set kind = 'showroom', model = 'A', status = case when is_active then 'live' else 'paused' end, status_at = now()
where kind is null;

-- ---------- (2) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('location_block_when_paused', 'locations', 'switch', 'true', null, null, null, null, 'বিরতি/বন্ধ লোকেশনে নতুন এন্ট্রি ও বিক্রি আটকানো', 'Paused/closed location-এ নতুন entry ও sale আটকানো', 'Block new entries and sales at a paused or closed place',
   'চালু থাকলে সার্ভারই নতুন এন্ট্রি/বিক্রি নেবে না; দেখা (রিপোর্ট) চলবে', 'On থাকলে server নতুন entry/sale নেবে না; দেখা চলবে', 'When on the server refuses new entries and sales; reading and reports stay open', 80),
 ('location_start_first_of_month', 'locations', 'switch', 'false', null, null, null, null, 'নতুন লোকেশন শুধু মাসের ১ তারিখে চালু (ধাপ ১৬)', 'নতুন location শুধু মাসের ১ তারিখে চালু (step 16)', 'A new place may start only on the 1st of a month (step 16)',
   'বন্ধ রাখলে যেকোনো দিনে চালু করা যাবে', 'Off থাকলে যেকোনো দিনে start', 'Off = any day', 81),
 ('block_on_missing_limit', 'locations', 'switch', 'false', null, null, null, null, 'সীমা ফাঁকা থাকলে ফর্ম জমা আটকানো', 'Limit ফাঁকা থাকলে Form জমা আটকানো', 'Block a form submit while a limit it needs is blank (Data needed)',
   'ডিফল্ট বন্ধ: ফাঁকা থাকলে শুধু ‘তথ্য লাগবে’ দেখাবে', 'Default Off: শুধু ‘Data needed’ দেখাবে', 'Default off: only shows Data needed', 82),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('location_manage', 'master', 63, 'লোকেশন পরিচালনা: সম্পাদনা, নতুন শোরুম, বিরতি/বন্ধ, সেটআপ ধাপ', 'Location পরিচালনা: edit, নতুন showroom, pause/close, setup step', 'Manage locations: edit, add a showroom, pause / close, setup steps', 'window', null),
 ('head_management', 'master', 64, 'হেড ম্যানেজমেন্ট: কন্ট্রোল সেন্টারের অংশ (লোকেশন, সীমা, তালিকা) — খরচ/বেতন ছাড়া', 'Head management: Control Center-এর অংশ (location, limit, list) — cost/salary ছাড়া', 'Head management: part of the Control Center (places, limits, lists), no costs or salaries', 'window', null),
 ('settings_approve', 'settings', 65, 'সেটিংস শিট (০-১) এর নতুন সংস্করণ অনুমোদন', 'Settings sheet (0-1) এর নতুন version approve', 'Approve a new version of the settings sheet (0-1)', 'window', null)
on conflict (grant_code) do nothing;

-- who may do what (server side)
create or replace function public._loc_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management')));
$$;
create or replace function public._sheet_viewer() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage') or public.has_grant('head_management') or public.has_grant('settings_approve')));
$$;

-- location-scoped versions: a grant given for ONE place (user_grants.location_id) counts for that place only
create or replace function public._loc_mgr_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc)));
$$;
create or replace function public._sheet_viewer_at(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (public.has_grant('location_manage', p_loc) or public.has_grant('head_management', p_loc) or public.has_grant('settings_approve', p_loc)));
$$;

-- ---------- (3) option list 'location_models' (editable in #/lists) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
select 'location_models', v.c, v.bn, v.mx, v.en, v.s, v.a from (values
  ('A', 'ক — নিজস্ব স্থান', 'A — Own place', 'A — Own place', 1, true),
  ('B', 'খ — ফ্র্যাঞ্চাইজ (এখনও সিদ্ধান্ত হয়নি)', 'B — Franchise (not decided yet)', 'B — Franchise (not decided yet)', 2, false),
  ('C', 'গ — অংশীদারি/ফান্ডেড (এখনও সিদ্ধান্ত হয়নি)', 'C — Funded (not decided yet)', 'C — Funded partner (not decided yet)', 3, false)) as v(c, bn, mx, en, s, a)
where not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = v.c);
do $$ begin
  if to_regclass('public.list_defs') is not null then
    insert into public.list_defs (list_code, add_rule) values ('location_models', 'owner') on conflict (list_code) do nothing;
  end if;
end $$;

-- ---------- (4) setup steps ----------
create table if not exists public.location_setup_steps (
  location_id int not null references public.locations(id),
  step_no int not null check (step_no between 1 and 17),
  title_bn text not null, title text not null,
  owner_role text, owner_yes boolean not null default false, optional boolean not null default false,
  done boolean not null default false, done_by uuid, done_at timestamptz, note text,
  primary key (location_id, step_no)
);
alter table public.location_setup_steps enable row level security;
drop policy if exists loc_steps_read on public.location_setup_steps;
create policy loc_steps_read on public.location_setup_steps for select to authenticated using (public._loc_mgr_at(location_id));
revoke all on public.location_setup_steps from public, anon, authenticated;
grant select on public.location_setup_steps to authenticated;
drop trigger if exists audit_loc_steps on public.location_setup_steps;
create trigger audit_loc_steps after insert or update on public.location_setup_steps for each row execute function public.log_change('location_id,step_no');
drop trigger if exists loc_steps_no_delete on public.location_setup_steps;
create trigger loc_steps_no_delete before delete on public.location_setup_steps for each row execute function public.no_hard_delete();

-- the 17 steps of Build command 5 (owner_yes = the step marked * : needs the owner's yes)
create or replace function public._loc_steps_def() returns table (n int, bn text, en text, who text, yes boolean, opt boolean)
language sql immutable set search_path = public as $$
  select * from (values
   (1,  'সিদ্ধান্ত: জায়গা, ভাড়া, বাজেট, প্রত্যাশিত বিক্রি, কোন কারখানা সরবরাহ করবে', 'Decide: place, rent, budget, expected sales, which factory supplies it', 'Owner', true, false),
   (2,  'লোকেশন কোড ও লোকেশন তালিকায় একটি সারি', 'Location code and a row in the location list', 'Daily-accounts reconciliation staff', false, false),
   (3,  'পরের ছাপা পর্যন্ত প্রতিটি ফর্মের লোকেশন বক্সে "অন্যান্য"-এ নাম লেখা', 'Name the place under Other on every form''s location box until the next print', 'Head management', false, false),
   (4,  'এই জায়গার আইটেম তালিকা ও বর্তমান মূল্য তালিকা', 'Item list and current price list for this place', 'Head management', false, false),
   (5,  'ডিউটি স্লট: ম্যানেজার, ব্যাকআপ, রাতের দ্বিতীয় গণনাকারী; একই ব্যক্তি দুই স্লটে নয় (ফর্ম ০২-৭)', 'Duty slots: manager, backup, night second counter; the same person is never in two slots (form 02-7)', 'Owner names, head management enters', true, false),
   (6,  'নতুন ডিউটি-ধারকের দক্ষতা যাচাই (ফর্ম ০২-৮)', 'Skill check of the new duty holder (form 02-8)', 'A checker from the list', false, false),
   (7,  'নিয়োগ ও নিবন্ধন (ফর্ম ০২-৪)', 'Hiring and registration (form 02-4)', 'Head management', false, false),
   (8,  'একজন-মানুষের ফাঁক পূরণ: রাতের দ্বিতীয় গণনা, সাক্ষী, শিফট হস্তান্তর (ফর্ম ০২-৭, ১১-১)', 'Cover the one-person gap: night second count, witness, shift handover (forms 02-7, 11-1)', 'Owner', true, false),
   (9,  'ক্যাশ বক্স: ড্রয়ার ফ্লোট ও ইমপ্রেস আলাদা; ব্যবসার মোবাইল-মানি নম্বর (০-১ সারি ১, ২)', 'Cash boxes: drawer float and imprest kept apart; the business mobile-money number (0-1 rows 1 and 2)', 'Head management', false, false),
   (10, 'এই জায়গার নিজস্ব মাপে লোকেশন সেটিংস শিট ০-১ (হেড ম্যানেজমেন্ট পূরণ, মালিক অনুমোদন)', 'Location Settings Sheet 0-1 at this place''s own measures (head management fills, owner approves)', 'Head management fills, owner approves', true, false),
   (11, 'যন্ত্রপাতি ও জায়গা: ফ্রিজ থার্মোমিটার, ওজন পরীক্ষার বাটখারা, হস্তান্তরের জায়গা, চাবির দায়িত্ব (০-১ সারি ১১, ১৩, ৩০)', 'Equipment and places: fridge thermometer, scale test weight, handover place, key duty (0-1 rows 11, 13, 30)', 'Head management', false, false),
   (12, 'কাগজের সেট ছাপা, সিরিয়াল সহ; প্রতিটি বইয়ের প্রথম নম্বর লেখা', 'Print the paper set with serial numbers; write the first number of each book', 'Head management', false, false),
   (13, 'সরবরাহ মানচিত্র: কোন কারখানা, কত ট্রিপ, হস্তান্তর বিন্দু (সরবরাহ মানচিত্র নিশ্চিত না হওয়া পর্যন্ত ঐচ্ছিক)', 'Supply map: which factory, how many trips, the handover point (optional until the supply map is confirmed)', 'Head management', false, true),
   (14, 'প্রশিক্ষণ, এক কাগজ এক করে (ফর্ম ০২-৮)', 'Training, one paper at a time (form 02-8)', 'Head management', false, false),
   (15, 'আগের রাতে উদ্বোধনী গণনা (ফর্ম ০৪-৩, ০৪-৪)', 'Opening count the night before (forms 04-3, 04-4)', 'Two counters', false, false),
   (16, 'মাসের ১ তারিখে চালু: প্রথম সপ্তাহ, এক মাসের পাস/ফেল, তারপর ৭, ৩০, ৯০ দিনের পর্যালোচনা', 'Start on the 1st: first week, then one month pass or fail, then 7, 30 and 90 day reviews', 'Everyone at the place', false, false),
   (17, 'অন্য জায়গার সাথে একই সংখ্যায় সাপ্তাহিক তুলনা (ফর্ম ০১-১, নতুন কলাম)', 'Weekly comparison with the other places on the same figures (form 01-1, a new column)', 'Head management', false, false)
  ) as v(n, bn, en, who, yes, opt);
$$;

create or replace function public._loc_steps_seed(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.location_setup_steps (location_id, step_no, title_bn, title, owner_role, owner_yes, optional)
  select p_loc, d.n, d.bn, d.en, d.who, d.yes, d.opt from public._loc_steps_def() d
  on conflict (location_id, step_no) do nothing;
end $$;

-- ---------- (5) location RPCs ----------
create or replace function public._slug(p text) returns text
language sql immutable set search_path = public as $$
  select left(trim(both '_' from regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '_', 'g')), 30);
$$;

-- status moves are enforced by the DATABASE (any writer, also plain SQL): closed is final
create or replace function public._loc_status_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if old.status = 'closed' then raise exception 'closed_is_final'; end if;
    if not ((old.status, new.status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                         ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'))) then
      raise exception 'bad_transition:%->%', old.status, new.status;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists locations_status_guard on public.locations;
create trigger locations_status_guard before update on public.locations for each row execute function public._loc_status_guard();

-- edit (p_id given) or add (p_id null) a place.  p_patch keys: name_bn name_mix name_en kind model supplied_by planned_opening hub_functions note sort code (add only)
create or replace function public.location_save(p_id int, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r public.locations; v_code text; base text; n int := 1; v text; k text; sb int; hops int := 0; nid int; po date; sortv int; hubv boolean;
  newname_bn text; newname_en text;
begin
  if p_id is null then
    if not public._loc_mgr() then raise exception 'not allowed'; end if;
  elsif not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_patch'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name_bn', 'name_mix', 'name_en', 'kind', 'model', 'supplied_by', 'planned_opening', 'hub_functions', 'note', 'sort', 'code') then raise exception 'unknown_field:%', k; end if;
  end loop;
  if p_patch ? 'code' and p_id is not null and (p_patch->>'code') is distinct from (select l.code from public.locations l where l.id = p_id) then raise exception 'code is immutable'; end if;
  if p_patch ? 'kind' and nullif(p_patch->>'kind', '') is not null and (p_patch->>'kind') not in ('showroom', 'factory', 'godown', 'hub', 'online', 'other') then raise exception 'bad_kind'; end if;
  if p_patch ? 'model' and nullif(p_patch->>'model', '') is not null
     and not exists (select 1 from public.option_lists o where o.list_code = 'location_models' and o.value_code = p_patch->>'model' and o.active) then raise exception 'bad_model'; end if;
  foreach v in array array['name_bn', 'name_mix', 'name_en', 'note'] loop
    if p_patch ? v and length(coalesce(p_patch->>v, '')) > (case when v = 'note' then 500 else 120 end) then raise exception 'too_long:%', v; end if;
  end loop;
  -- casts: a bad text is a friendly code, never a raw cast error
  if p_patch ? 'planned_opening' and nullif(p_patch->>'planned_opening', '') is not null then
    begin po := (p_patch->>'planned_opening')::date; exception when others then raise exception 'bad_date'; end;
    if po < date '2000-01-01' or po > date '2100-01-01' then raise exception 'bad_date'; end if;
  end if;
  if p_patch ? 'sort' and nullif(p_patch->>'sort', '') is not null then
    begin sortv := (p_patch->>'sort')::int; exception when others then raise exception 'bad_number'; end;
    if not (sortv between 0 and 9999) then raise exception 'bad_number'; end if;
  end if;
  if p_patch ? 'hub_functions' then
    begin hubv := coalesce((p_patch->>'hub_functions')::boolean, false); exception when others then raise exception 'bad_value'; end;
  end if;
  if p_patch ? 'supplied_by' and nullif(p_patch->>'supplied_by', '') is not null then
    begin sb := (p_patch->>'supplied_by')::int; exception when others then raise exception 'bad_number'; end;
    if not exists (select 1 from public.locations where id = sb) then raise exception 'unknown_supplier_location'; end if;
    if p_id is null or sb is distinct from (select l.supplied_by from public.locations l where l.id = p_id) then
      if not exists (select 1 from public.locations where id = sb and is_active and status <> 'closed') then raise exception 'supplier_not_active'; end if;
    end if;
    if p_id is not null then
      if sb = p_id then raise exception 'supplied_by_itself'; end if;
      -- no loop: walk up the supplied_by chain of the chosen supplier
      declare walk int := sb;
      begin
        loop
          select l.supplied_by into walk from public.locations l where l.id = walk; hops := hops + 1;
          exit when walk is null or hops > 20;
          if walk = p_id then raise exception 'supplied_by_loop'; end if;
        end loop;
      end;
    end if;
  end if;

  if p_id is null then
    perform pg_advisory_xact_lock(1600);
    newname_bn := nullif(btrim(coalesce(p_patch->>'name_bn', '')), ''); newname_en := nullif(btrim(coalesce(p_patch->>'name_en', '')), '');
    if newname_bn is null and newname_en is null then raise exception 'name_required'; end if;
    if newname_bn is null then newname_bn := newname_en; end if;
    if exists (select 1 from public.locations x where lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en))) then raise exception 'name_in_use'; end if;
    if nullif(p_patch->>'code', '') is not null then
      v_code := p_patch->>'code';
      if v_code !~ '^[a-z][a-z0-9_]{1,29}$' then raise exception 'bad_code'; end if;
      if exists (select 1 from public.locations x where x.code = v_code) then raise exception 'code_in_use'; end if;
    else
      base := public._slug(coalesce(newname_en, ''));
      if base is null or length(base) < 2 or base !~ '^[a-z]' then base := 'loc'; end if;
      v_code := base;
      while exists (select 1 from public.locations x where x.code = v_code) loop n := n + 1; v_code := left(base, 26) || '_' || n; end loop;
    end if;
    insert into public.locations (code, name_bn, name_mix, name_en, sort, is_active, kind, model, status, supplied_by, planned_opening, hub_functions, note, created_by, created_at, status_by, status_at)
    values (v_code, newname_bn, nullif(btrim(coalesce(p_patch->>'name_mix', '')), ''), newname_en,
            coalesce(sortv, (select coalesce(max(x.sort), 0) + 1 from public.locations x)), true,
            coalesce(nullif(p_patch->>'kind', ''), 'showroom'), coalesce(nullif(p_patch->>'model', ''), 'A'), 'planned', sb, po,
            coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now())
    returning id into nid;
    perform public._loc_steps_seed(nid);
    update public.location_setup_steps set done = true, done_by = auth.uid(), done_at = now(), note = 'created with the place' where location_id = nid and step_no = 2;
    perform public._sheet_sync_due();
    return jsonb_build_object('id', nid, 'code', v_code, 'created', true);
  end if;

  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  -- a rename may not collide with another place
  if p_patch ? 'name_bn' and nullif(btrim(p_patch->>'name_bn'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(x.name_bn)) = lower(btrim(p_patch->>'name_bn'))) then raise exception 'name_in_use'; end if;
  if p_patch ? 'name_en' and nullif(btrim(p_patch->>'name_en'), '') is not null
     and exists (select 1 from public.locations x where x.id <> p_id and lower(btrim(coalesce(x.name_en, ''))) = lower(btrim(p_patch->>'name_en'))) then raise exception 'name_in_use'; end if;
  update public.locations l set
    name_bn = case when p_patch ? 'name_bn' then coalesce(nullif(btrim(p_patch->>'name_bn'), ''), l.name_bn) else l.name_bn end,
    name_mix = case when p_patch ? 'name_mix' then nullif(btrim(p_patch->>'name_mix'), '') else l.name_mix end,
    name_en = case when p_patch ? 'name_en' then nullif(btrim(p_patch->>'name_en'), '') else l.name_en end,
    kind = case when p_patch ? 'kind' then coalesce(nullif(p_patch->>'kind', ''), l.kind) else l.kind end,
    model = case when p_patch ? 'model' then coalesce(nullif(p_patch->>'model', ''), l.model) else l.model end,
    supplied_by = case when p_patch ? 'supplied_by' then sb else l.supplied_by end,
    planned_opening = case when p_patch ? 'planned_opening' then po else l.planned_opening end,
    hub_functions = case when p_patch ? 'hub_functions' then coalesce(hubv, false) else l.hub_functions end,
    note = case when p_patch ? 'note' then nullif(p_patch->>'note', '') else l.note end,
    sort = coalesce(sortv, l.sort)
  where l.id = p_id;
  perform public._sheet_sync_due();
  return jsonb_build_object('id', p_id, 'code', r.code, 'created', false);
end $$;

-- things that should be settled before a place stops: open credit, stock on hand, open entries, transfers on the way
create or replace function public.location_close_check(p_id int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dues numeric := 0; stk numeric := 0; stki int := 0; oe int := 0; tr int := 0; w jsonb := '[]';
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  select coalesce(sum(due_amount), 0) into dues from public.sales where location_id = p_id and status = 'done' and due_amount > 0;
  select coalesce(sum(qty), 0), count(*) into stk, stki from public.stock_balance where location_id = p_id and qty > 0;
  select count(*) into oe from public.entries where location_id = p_id and status in ('draft', 'submitted');
  select count(*) into tr from public.stock_transfers where status = 'sent' and (from_location_id = p_id or to_location_id = p_id);
  if dues > 0 then w := w || jsonb_build_object('code', 'open_dues', 'amount', dues); end if;
  if stki > 0 then w := w || jsonb_build_object('code', 'stock_on_hand', 'items', stki, 'qty', stk); end if;
  if oe > 0 then w := w || jsonb_build_object('code', 'open_entries', 'count', oe); end if;
  if tr > 0 then w := w || jsonb_build_object('code', 'transfers_in_transit', 'count', tr); end if;
  return jsonb_build_object('warnings', w, 'ok', jsonb_array_length(w) = 0);
end $$;

-- steps that block the start (1..15 except optional ones)
create or replace function public._loc_open_steps(p_id int) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(step_no order by step_no), '{}') from public.location_setup_steps
  where location_id = p_id and step_no <= 15 and not done and not optional;
$$;

-- pause / resume / start / close.  Returns {ok:false, warnings:[...]} when a checklist is open and p_override is not set; only the owner may override.
create or replace function public.location_set_status(p_id int, p_status text, p_reason text default null, p_override boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.locations; w jsonb := '[]'; open_steps int[]; cc jsonb; okmove boolean := false; reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if p_status not in ('planned', 'setting_up', 'live', 'paused', 'closed') then raise exception 'bad_status'; end if;
  if reason is not null and length(reason) > 500 then raise exception 'too_long:reason'; end if;
  select * into r from public.locations where id = p_id for update;
  if not found then raise exception 'unknown_location'; end if;
  if r.status = p_status then return jsonb_build_object('ok', true, 'status', r.status, 'unchanged', true); end if;
  if r.status = 'closed' then raise exception 'closed_is_final'; end if;
  okmove := (r.status, p_status) in (('planned', 'setting_up'), ('planned', 'live'), ('planned', 'closed'), ('setting_up', 'planned'), ('setting_up', 'live'), ('setting_up', 'paused'), ('setting_up', 'closed'),
                                     ('live', 'paused'), ('live', 'closed'), ('paused', 'live'), ('paused', 'closed'));
  if not okmove then raise exception 'bad_transition:%->%', r.status, p_status; end if;
  if p_status in ('paused', 'closed') and reason is null then raise exception 'reason_required'; end if;

  if p_status = 'live' and r.status in ('planned', 'setting_up') then
    open_steps := public._loc_open_steps(p_id);
    if coalesce(array_length(open_steps, 1), 0) > 0 then w := w || jsonb_build_object('code', 'setup_steps_open', 'steps', to_jsonb(open_steps)); end if;
    if public.rule_on('location_start_first_of_month') and extract(day from (now() at time zone 'Asia/Dhaka')::date) <> 1 then w := w || jsonb_build_object('code', 'not_first_of_month'); end if;
  elsif p_status = 'closed' then
    cc := public.location_close_check(p_id); w := cc->'warnings';
  end if;
  if jsonb_array_length(w) > 0 then
    if not coalesce(p_override, false) then return jsonb_build_object('ok', false, 'warnings', w, 'status', r.status); end if;
    if not public.is_owner() then raise exception 'owner_override_only'; end if;
    if reason is null then raise exception 'reason_required'; end if;
  end if;

  update public.locations set status = p_status, status_by = auth.uid(), status_at = now(),
    paused_reason = case when p_status = 'paused' then reason else paused_reason end,
    paused_by = case when p_status = 'paused' then auth.uid() else paused_by end,
    paused_at = case when p_status = 'paused' then now() else paused_at end,
    closed_reason = case when p_status = 'closed' then reason else closed_reason end,
    closed_by = case when p_status = 'closed' then auth.uid() else closed_by end,
    closed_at = case when p_status = 'closed' then now() else closed_at end,
    is_active = case when p_status = 'closed' then false else is_active end
  where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_status, 'overridden', jsonb_array_length(w) > 0, 'warnings', w);
end $$;

-- switch a place active / inactive (a lighter switch than pause).  Closed places stay inactive.
create or replace function public.location_set_active(p_id int, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  select status into st from public.locations where id = p_id;
  if not found then raise exception 'unknown_location'; end if;
  if st = 'closed' and coalesce(p_active, true) then raise exception 'closed_is_final'; end if;
  update public.locations set is_active = coalesce(p_active, true) where id = p_id;
end $$;

-- make sure a place has its 17 steps (for an older place the owner wants to run the checklist on)
create or replace function public.location_steps_init(p_id int) returns int
language plpgsql security definer set search_path = public as $$
begin
  if not public._loc_mgr_at(p_id) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_id) then raise exception 'unknown_location'; end if;
  perform public._loc_steps_seed(p_id);
  return (select count(*) from public.location_setup_steps where location_id = p_id);
end $$;

-- tick / untick one step.  Steps marked * (owner_yes) are the owner's only; step 16 needs 1-15; ticking 16 starts a place that is in setup
-- (a PAUSED place is never resumed silently: resume it on purpose).
create or replace function public.location_step_set(p_loc int, p_step int, p_done boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.location_setup_steps; st jsonb; open_steps int[]; cur text;
begin
  if not public._loc_mgr_at(p_loc) then raise exception 'not allowed'; end if;
  if p_note is not null and length(p_note) > 500 then raise exception 'too_long:note'; end if;
  select * into s from public.location_setup_steps where location_id = p_loc and step_no = p_step for update;
  if not found then raise exception 'unknown_step'; end if;
  select status into cur from public.locations where id = p_loc;
  if cur = 'closed' then raise exception 'closed_is_final'; end if;
  if s.owner_yes and not public.is_owner() then raise exception 'owner_only_step'; end if;
  if coalesce(p_done, true) and p_step = 16 then
    if cur = 'paused' then raise exception 'place_paused'; end if;
    open_steps := public._loc_open_steps(p_loc);
    if coalesce(array_length(open_steps, 1), 0) > 0 then raise exception 'steps_open:%', array_to_string(open_steps, ','); end if;
  end if;
  update public.location_setup_steps set done = coalesce(p_done, true),
    done_by = case when coalesce(p_done, true) then auth.uid() end, done_at = case when coalesce(p_done, true) then now() end,
    note = coalesce(nullif(btrim(p_note), ''), note)
  where location_id = p_loc and step_no = p_step;
  if coalesce(p_done, true) and p_step = 16 and cur in ('planned', 'setting_up') then
    st := public.location_set_status(p_loc, 'live', 'step 16: started', false);
    if (st->>'ok')::boolean is not true then
      update public.location_setup_steps set done = false, done_by = null, done_at = null where location_id = p_loc and step_no = 16;
      return jsonb_build_object('ok', false, 'warnings', st->'warnings');
    end if;
  elsif coalesce(p_done, true) and cur = 'planned' then
    update public.locations set status = 'setting_up', status_by = auth.uid(), status_at = now() where id = p_loc and status = 'planned';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- (6) paused / closed places refuse NEW entries and sales ----------
-- Real work that happened BEFORE the status change but reaches the server late (back-dated entry, offline sale synced later) is still accepted:
-- only rows dated on / after the status change are refused.  The owner can open a short window for late work (location_block_override, logged).
create table if not exists public.location_block_overrides (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  reason text not null, created_by uuid, created_at timestamptz not null default now(), expires_at timestamptz not null
);
alter table public.location_block_overrides enable row level security;
drop policy if exists loc_block_ov_read on public.location_block_overrides;
create policy loc_block_ov_read on public.location_block_overrides for select to authenticated using (public.is_owner());
revoke all on public.location_block_overrides from public, anon, authenticated;
grant select on public.location_block_overrides to authenticated;
drop trigger if exists audit_loc_block_ov on public.location_block_overrides;
create trigger audit_loc_block_ov after insert or update on public.location_block_overrides for each row execute function public.log_change('id');
drop trigger if exists loc_block_ov_no_delete on public.location_block_overrides;
create trigger loc_block_ov_no_delete before delete on public.location_block_overrides for each row execute function public.no_hard_delete();

create or replace function public.location_block_override(p_loc int, p_reason text, p_minutes int default 30) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare e timestamptz;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  if not (coalesce(p_minutes, 0) between 1 and 240) then raise exception 'bad_number'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown_location'; end if;
  e := now() + make_interval(mins => p_minutes);
  insert into public.location_block_overrides (location_id, reason, created_by, expires_at) values (p_loc, left(btrim(p_reason), 300), auth.uid(), e);
  return e;
end $$;

create or replace function public._loc_block_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text; sat timestamptz;
begin
  select status, status_at into st, sat from public.locations where id = new.location_id;
  if st in ('paused', 'closed') and public.rule_on('location_block_when_paused') then
    if sat is not null then
      if tg_table_name = 'entries' and (to_jsonb(new) ->> 'entry_date')::date < (sat at time zone 'Asia/Dhaka')::date then return new; end if;
      if tg_table_name = 'sales' and (to_jsonb(new) ->> 'sold_at')::timestamptz < sat then return new; end if;
    end if;
    if exists (select 1 from public.location_block_overrides o where o.location_id = new.location_id and o.expires_at > now()) then return new; end if;
    raise exception 'location_paused:%', st;
  end if;
  return new;
end $$;
drop trigger if exists entries_loc_guard on public.entries;
create trigger entries_loc_guard before insert on public.entries for each row execute function public._loc_block_guard();
drop trigger if exists sales_loc_guard on public.sales;
create trigger sales_loc_guard before insert on public.sales for each row execute function public._loc_block_guard();

-- stock transfers INTO, purchase bills / wastage requests AT a CLOSED place are refused (a paused place only warns: the screens show its status).
create or replace function public._loc_closed_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lid int := nullif(to_jsonb(new) ->> tg_argv[0], '')::int; st text;
begin
  select status into st from public.locations where id = lid;
  if st = 'closed' and public.rule_on('location_block_when_paused')
     and not exists (select 1 from public.location_block_overrides o where o.location_id = lid and o.expires_at > now()) then raise exception 'location_paused:closed'; end if;
  return new;
end $$;
do $$ declare t record; begin
  for t in select * from (values ('stock_transfers', 'to_location_id'), ('purchase_bills', 'location_id'), ('wastage_requests', 'location_id'), ('stock_wastage', 'location_id')) v(tb, col) loop
    if to_regclass('public.' || t.tb) is not null and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = t.tb and c.column_name = t.col) then
      execute format('drop trigger if exists %I on public.%I', t.tb || '_closed_guard', t.tb);
      execute format('create trigger %I before insert on public.%I for each row execute function public._loc_closed_guard(%L)', t.tb || '_closed_guard', t.tb, t.col);
    end if;
  end loop;
end $$;

-- ---------- (7) settings sheet 0-1 versions ----------
-- the keys a sheet may hold (the 64 keys of the limits screen) with their shape; the owner can add keys with SQL.  Unknown key = refused.
create table if not exists public.settings_keys (
  key text primary key, kind text not null check (kind in ('number', 'text', 'time', 'bool')),
  min_value numeric not null default -1000, max_value numeric not null default 1000000000000, active boolean not null default true
);
alter table public.settings_keys enable row level security;
drop policy if exists settings_keys_read on public.settings_keys;
create policy settings_keys_read on public.settings_keys for select to authenticated using (public.is_active());
revoke all on public.settings_keys from public, anon, authenticated;
grant select on public.settings_keys to authenticated;
drop trigger if exists settings_keys_no_delete on public.settings_keys;
create trigger settings_keys_no_delete before delete on public.settings_keys for each row execute function public.no_hard_delete();
insert into public.settings_keys (key, kind) values
  ('drawer_float', 'number'),
  ('imprest', 'number'),
  ('expense_max', 'number'),
  ('cash_tol', 'number'),
  ('goods_money_tol_pct', 'number'),
  ('goods_money_tol_max', 'number'),
  ('big_sale', 'number'),
  ('avg_daily_sales', 'number'),
  ('discount_limit', 'number'),
  ('refund_limit', 'number'),
  ('hub_cash_max', 'number'),
  ('hub_min_cash', 'number'),
  ('order_hold_days', 'number'),
  ('unclaimed_days', 'number'),
  ('open_time', 'time'),
  ('close_time', 'time'),
  ('busy_day_def', 'text'),
  ('handover_point', 'text'),
  ('crates', 'number'),
  ('trays', 'number'),
  ('fridge1_name', 'text'),
  ('fridge1_min', 'number'),
  ('fridge1_max', 'number'),
  ('fridge2_name', 'text'),
  ('fridge2_min', 'number'),
  ('fridge2_max', 'number'),
  ('fridge3_name', 'text'),
  ('fridge3_min', 'number'),
  ('fridge3_max', 'number'),
  ('shelf_sweet', 'number'),
  ('shelf_cake', 'number'),
  ('shelf_doi', 'number'),
  ('shelf_bakery', 'number'),
  ('daytag_0', 'text'),
  ('daytag_1', 'text'),
  ('daytag_2', 'text'),
  ('daytag_3', 'text'),
  ('daytag_4', 'text'),
  ('daytag_5', 'text'),
  ('daytag_6', 'text'),
  ('waste_classes', 'text'),
  ('count_tol_pct', 'number'),
  ('count_tol_max', 'number'),
  ('quote_over', 'number'),
  ('jalebi_base_pct', 'number'),
  ('jalebi_per_kg_flour', 'number'),
  ('jalebi_tol_pct', 'number'),
  ('jalebi_tol_kg', 'number'),
  ('oil_change_rule', 'text'),
  ('mkt_limit_1', 'number'),
  ('mkt_limit_2', 'number'),
  ('mkt_limit_3', 'number'),
  ('mkt_limit_4', 'number'),
  ('mkt_limit_5', 'number'),
  ('mkt_limit_6', 'number'),
  ('mkt_limit_7', 'number'),
  ('mkt_limit_8', 'number'),
  ('mkt_limit_9', 'number'),
  ('mkt_limit_10', 'number'),
  ('online_order_limit', 'number'),
  ('scale_test', 'text'),
  ('newprod_review_days', 'number'),
  ('fixed_cost_month', 'number'),
  ('anomaly_ratio', 'number')
on conflict (key) do nothing;

create table if not exists public.settings_sheets (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  version int not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'discarded')),
  effective_from date,
  source text not null default 'sheet' check (source in ('seed', 'sheet', 'legacy')),
  note text,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  unique (location_id, version)
);
alter table public.settings_sheets add column if not exists base_version int;          -- the version the draft was copied from
alter table public.settings_sheets add column if not exists last_edited_by uuid;
alter table public.settings_sheets add column if not exists applied_at timestamptz;    -- when the version was written through to location_settings
update public.settings_sheets set applied_at = coalesce(approved_at, now()) where applied_at is null and source in ('seed', 'legacy');
create unique index if not exists settings_sheets_one_draft on public.settings_sheets (location_id) where status = 'draft';
create table if not exists public.settings_values (
  sheet_id bigint not null references public.settings_sheets(id),
  key text not null,
  value jsonb,                       -- null = blank = Data needed
  primary key (sheet_id, key)
);
alter table public.settings_sheets enable row level security;
alter table public.settings_values enable row level security;
drop policy if exists settings_sheets_read on public.settings_sheets;
create policy settings_sheets_read on public.settings_sheets for select to authenticated using (public._sheet_viewer_at(location_id));
drop policy if exists settings_values_read on public.settings_values;
create policy settings_values_read on public.settings_values for select to authenticated using (exists (select 1 from public.settings_sheets s where s.id = sheet_id and public._sheet_viewer_at(s.location_id)));
revoke all on public.settings_sheets, public.settings_values from public, anon, authenticated;
grant select on public.settings_sheets, public.settings_values to authenticated;
drop trigger if exists audit_settings_sheets on public.settings_sheets;
create trigger audit_settings_sheets after insert or update on public.settings_sheets for each row execute function public.log_change('id');
drop trigger if exists audit_settings_values on public.settings_values;
create trigger audit_settings_values after insert or update on public.settings_values for each row execute function public.log_change('sheet_id,key');
drop trigger if exists settings_sheets_no_delete on public.settings_sheets;
create trigger settings_sheets_no_delete before delete on public.settings_sheets for each row execute function public.no_hard_delete();
drop trigger if exists settings_values_no_delete on public.settings_values;
create trigger settings_values_no_delete before delete on public.settings_values for each row execute function public.no_hard_delete();
-- an approved version never changes its values (a change is the next version)
create or replace function public._sheet_values_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare st text;
begin
  select status into st from public.settings_sheets where id = new.sheet_id;
  if st is distinct from 'draft' and coalesce(current_setting('bos.sheet_seed', true), '') <> '1' then raise exception 'sheet_not_draft'; end if;
  return new;
end $$;
drop trigger if exists settings_values_guard on public.settings_values;
create trigger settings_values_guard before insert or update on public.settings_values for each row execute function public._sheet_values_guard();

-- version 1 for every place: approved, copied from location_settings (blank = Data needed).  Only places that have no sheet yet.
do $$
declare l record; sid bigint;
begin
  perform set_config('bos.sheet_seed', '1', true);
  for l in select id from public.locations loc where not exists (select 1 from public.settings_sheets s where s.location_id = loc.id) loop
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
      values (l.id, 1, 'approved', date '2000-01-01', 'seed', 'copied from location_settings', now(), now()) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, ls.key, ls.value from public.location_settings ls where ls.location_id = l.id
      on conflict do nothing;
  end loop;
  perform set_config('bos.sheet_seed', '', true);
end $$;

-- the version in force on a date (latest approved with effective_from <= date; before the first one: the first)
create or replace function public._sheet_in_force(p_loc int, p_date date) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' and effective_from <= p_date order by effective_from desc, version desc limit 1),
    (select id from public.settings_sheets where location_id = p_loc and status = 'approved' order by effective_from, version limit 1));
$$;

-- THE reader: the value in force on that date; NULL = blank = Data needed
create or replace function public.get_limit(p_loc int, p_key text, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sid bigint; v jsonb;
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  sid := public._sheet_in_force(p_loc, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date));
  if sid is null then
    select value into v from public.location_settings where location_id = p_loc and key = p_key;
  else
    select value into v from public.settings_values where sheet_id = sid and key = p_key;
  end if;
  if v is null or v = 'null'::jsonb or (jsonb_typeof(v) = 'string' and btrim(v #>> '{}') = '') then return null; end if;
  return v;
end $$;

-- which of these keys are blank at the place on that date
create or replace function public.limit_missing(p_loc int, p_keys text[], p_date date default null) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare k text; res text[] := '{}';
begin
  if not (public.is_active() and (public.can_loc(p_loc) or public._sheet_viewer_at(p_loc))) then raise exception 'not allowed'; end if;
  foreach k in array coalesce(p_keys, '{}') loop
    if public.get_limit(p_loc, k, p_date) is null then res := res || k; end if;
  end loop;
  return res;
end $$;

create or replace function public.sheet_list(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'version', s.version, 'status', s.status, 'effective_from', s.effective_from, 'source', s.source, 'note', s.note,
      'created_by', s.created_by, 'created_at', s.created_at, 'approved_by', s.approved_by, 'approved_at', s.approved_at, 'base_version', s.base_version,
      'filled', (select count(*) from public.settings_values v where v.sheet_id = s.id and v.value is not null and v.value <> 'null'::jsonb and btrim(v.value #>> '{}') <> ''),
      'blank', (select count(*) from public.settings_values v where v.sheet_id = s.id and (v.value is null or v.value = 'null'::jsonb or btrim(v.value #>> '{}') = '')),
      'in_force', s.id = public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date)) order by s.version desc)
    from public.settings_sheets s where s.location_id = p_loc), '[]');
end $$;

-- the one draft of a place (created from the version in force, remembering which version that was)
create or replace function public._sheet_draft_for(p_loc int, p_uid uuid) returns bigint
language plpgsql security definer set search_path = public as $$
declare d bigint; cur bigint; nv int; bv int;
begin
  perform 1 from public.locations where id = p_loc for update;
  if not found then raise exception 'unknown_location'; end if;
  select id into d from public.settings_sheets where location_id = p_loc and status = 'draft';
  if d is not null then return d; end if;
  select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = p_loc;
  cur := public._sheet_in_force(p_loc, (now() at time zone 'Asia/Dhaka')::date);
  select version into bv from public.settings_sheets where id = cur;
  insert into public.settings_sheets (location_id, version, status, source, created_by, last_edited_by, base_version) values (p_loc, nv, 'draft', 'sheet', p_uid, p_uid, bv) returning id into d;
  if cur is not null then insert into public.settings_values (sheet_id, key, value) select d, key, value from public.settings_values where sheet_id = cur; end if;
  return d;
end $$;
create or replace function public.sheet_draft(p_loc int) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  if not public._sheet_viewer_at(p_loc) then raise exception 'not allowed'; end if;
  return public._sheet_draft_for(p_loc, auth.uid());
end $$;

-- a value must fit the key: numbers must be real jsonb numbers inside the range (a string such as 'Infinity', 'NaN' or 'abc' is refused for a number key)
create or replace function public._limit_value_ok(p_key text, p_val jsonb) returns jsonb
language plpgsql stable set search_path = public as $$
declare k public.settings_keys; n numeric; t text;
begin
  if p_key is null or p_key !~ '^[a-z0-9_]{1,60}$' then raise exception 'bad_key'; end if;
  select * into k from public.settings_keys where key = p_key and active;
  if not found and not exists (select 1 from public.location_settings where key = p_key) then raise exception 'unknown_key'; end if;
  if p_val is null or p_val = 'null'::jsonb then return null; end if;
  if k.key is null then   -- only known from old location_settings rows: any sane scalar
    if jsonb_typeof(p_val) = 'number' then
      if not ((p_val #>> '{}')::numeric between -1000000000000 and 1000000000000) then raise exception 'bad_number'; end if; return p_val;
    elsif jsonb_typeof(p_val) = 'string' then
      t := btrim(p_val #>> '{}'); if length(t) > 200 or lower(t) in ('infinity', '-infinity', 'nan') then raise exception 'bad_value'; end if; return case when t = '' then null else to_jsonb(t) end;
    elsif jsonb_typeof(p_val) = 'boolean' then return p_val; end if;
    raise exception 'bad_value';
  end if;
  if k.kind = 'number' then
    if jsonb_typeof(p_val) <> 'number' then raise exception 'bad_value'; end if;
    n := (p_val #>> '{}')::numeric;
    if not (n between k.min_value and k.max_value) then raise exception 'bad_number'; end if;
    return p_val;
  elsif k.kind = 'time' then
    if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
    t := btrim(p_val #>> '{}'); if t = '' then return null; end if;
    if t !~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'bad_value'; end if;
    return to_jsonb(t);
  elsif k.kind = 'bool' then
    if jsonb_typeof(p_val) <> 'boolean' then raise exception 'bad_value'; end if; return p_val;
  end if;
  if jsonb_typeof(p_val) <> 'string' then raise exception 'bad_value'; end if;
  t := btrim(p_val #>> '{}'); if length(t) > 200 then raise exception 'too_long:value'; end if;
  return case when t = '' then null else to_jsonb(t) end;
end $$;

create or replace function public.sheet_set(p_sheet bigint, p_values jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; k text; n int := 0;
begin
  if p_values is null or jsonb_typeof(p_values) <> 'object' then raise exception 'bad_patch'; end if;
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  for k in select jsonb_object_keys(p_values) loop
    insert into public.settings_values (sheet_id, key, value) values (p_sheet, k, public._limit_value_ok(k, p_values->k))
      on conflict (sheet_id, key) do update set value = excluded.value;
    n := n + 1;
  end loop;
  update public.settings_sheets set last_edited_by = auth.uid() where id = p_sheet;
  return n;
end $$;

create or replace function public.sheet_discard(p_sheet bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not public._sheet_viewer_at(s.location_id) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  if s.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  update public.settings_sheets set status = 'discarded' where id = p_sheet;
end $$;

-- write the version in force today through to location_settings (old screens and server functions keep reading location_settings)
create or replace function public._sheet_writethrough(p_loc int) returns void
language plpgsql security definer set search_path = public as $$
declare sid bigint; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  sid := public._sheet_in_force(p_loc, today);
  if sid is null then return; end if;
  perform set_config('bos.sheet_sync', '1', true);
  insert into public.location_settings (location_id, key, value, updated_by)
    select p_loc, v.key, v.value, auth.uid() from public.settings_values v where v.sheet_id = sid
  on conflict (location_id, key) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  perform set_config('bos.sheet_sync', '', true);
  update public.settings_sheets set applied_at = now() where location_id = p_loc and status = 'approved' and effective_from <= today and applied_at is null;
end $$;

-- there is no scheduler: a future-dated version is written through lazily, by this cheap check (does nothing when nothing is due).
-- It runs from control_counts() (every Home load of an owner / delegate), location_save, sheet_approve and sheet_sync_all().
-- get_limit() itself is always right by date; only code that reads location_settings DIRECTLY (record_sale2 ...) sees the new value after one of these ran.
create or replace function public._sheet_sync_due() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  for l in select distinct location_id from public.settings_sheets where status = 'approved' and applied_at is null and effective_from <= (now() at time zone 'Asia/Dhaka')::date loop
    perform public._sheet_writethrough(l.location_id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.sheet_approve(p_sheet bigint, p_effective date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.settings_sheets; eff date; lastd date; firstd date; today date := (now() at time zone 'Asia/Dhaka')::date; exempt boolean;
begin
  select * into s from public.settings_sheets where id = p_sheet for update;
  if not found then raise exception 'unknown_sheet'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('settings_approve', s.location_id))) then raise exception 'not allowed'; end if;
  if s.status <> 'draft' then raise exception 'sheet_not_draft'; end if;
  exempt := public.is_owner() and public.rule_on('owner_self_approve');
  -- the approver is neither the person who started the draft nor the last person who edited it
  if not exempt and (s.created_by is not distinct from auth.uid() or s.last_edited_by is not distinct from auth.uid()) then raise exception 'maker_cannot_approve'; end if;
  -- a newer version was approved since this draft was copied: refuse (start a new draft from the current version)
  if exists (select 1 from public.settings_sheets x where x.location_id = s.location_id and x.status = 'approved' and x.version > coalesce(s.base_version, 0)) then raise exception 'newer_version_exists'; end if;
  eff := coalesce(p_effective, today);
  select coalesce((select l.created_at::date from public.locations l where l.id = s.location_id and l.created_by is not null), date '2000-01-01') into firstd;
  if eff < firstd then raise exception 'effective_too_early'; end if;
  if eff > today + 365 then raise exception 'effective_too_far'; end if;
  select max(effective_from) into lastd from public.settings_sheets where location_id = s.location_id and status = 'approved' and source <> 'seed';
  if lastd is not null and eff < lastd then raise exception 'effective_before_previous'; end if;
  update public.settings_sheets set status = 'approved', effective_from = eff, approved_by = auth.uid(), approved_at = now(), note = coalesce(nullif(btrim(p_note), ''), note) where id = p_sheet;
  perform public._sheet_writethrough(s.location_id);
  return jsonb_build_object('ok', true, 'version', s.version, 'effective_from', eff);
end $$;

create or replace function public.sheet_sync_all() returns int
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0;
begin
  if not public._sheet_viewer() then raise exception 'not allowed'; end if;
  for l in select id from public.locations loop perform public._sheet_writethrough(l.id); n := n + 1; end loop;
  return n;
end $$;

-- the OLD screen (#/locset) writes location_settings directly (owner only, RLS).  Keep it working AND versioned:
--  * owner_self_approve ON : a direct change makes a new approved version (source 'legacy', effective today, copied from the version in force TODAY);
--    the same person changing again the same day edits that version.
--  * owner_self_approve OFF: the direct change is NOT applied; it goes into the draft (someone else approves it) and location_settings keeps the old value.
create or replace function public._ls_legacy() returns trigger
language plpgsql security definer set search_path = public as $$
declare cur public.settings_sheets; nv int; sid bigint; did bigint; today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid();
begin
  if coalesce(current_setting('bos.sheet_sync', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and old.value is not distinct from new.value then return new; end if;
  if me is not null and public.is_owner() and not public.rule_on('owner_self_approve') then
    did := public._sheet_draft_for(new.location_id, me);
    insert into public.settings_values (sheet_id, key, value) values (did, new.key, new.value) on conflict (sheet_id, key) do update set value = excluded.value;
    update public.settings_sheets set last_edited_by = me where id = did;
    perform set_config('bos.sheet_sync', '1', true);
    if tg_op = 'UPDATE' then update public.location_settings set value = old.value where location_id = new.location_id and key = new.key;
    else update public.location_settings set value = null where location_id = new.location_id and key = new.key; end if;
    perform set_config('bos.sheet_sync', '', true);
    return new;
  end if;
  perform set_config('bos.sheet_seed', '1', true);
  select * into cur from public.settings_sheets where id = public._sheet_in_force(new.location_id, today);
  if not found then
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at) values (new.location_id, 1, 'approved', date '2000-01-01', 'seed', 'created by a direct settings change', now(), now()) returning id into sid;
  elsif cur.source = 'legacy' and cur.effective_from = today and cur.approved_by is not distinct from me and cur.version = (select max(version) from public.settings_sheets where location_id = new.location_id and status = 'approved') then
    sid := cur.id;
  else
    select coalesce(max(version), 0) + 1 into nv from public.settings_sheets where location_id = new.location_id;
    insert into public.settings_sheets (location_id, version, status, effective_from, source, note, created_by, approved_by, approved_at, applied_at, base_version)
      values (new.location_id, nv, 'approved', today, 'legacy', 'changed on the old limits screen', me, me, now(), now(), cur.version) returning id into sid;
    insert into public.settings_values (sheet_id, key, value) select sid, key, value from public.settings_values where sheet_id = cur.id on conflict do nothing;
  end if;
  insert into public.settings_values (sheet_id, key, value) values (sid, new.key, new.value)
    on conflict (sheet_id, key) do update set value = excluded.value;
  perform set_config('bos.sheet_seed', '', true);
  return new;
end $$;
drop trigger if exists location_settings_legacy on public.location_settings;
create trigger location_settings_legacy after insert or update on public.location_settings for each row execute function public._ls_legacy();

-- a new place gets its (blank) version 1 too
create or replace function public._loc_sheet_v1() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.settings_sheets (location_id, version, status, effective_from, source, note, approved_at, applied_at)
    values (new.id, 1, 'approved', date '2000-01-01', 'seed', 'blank: every value needs data', now(), now()) on conflict (location_id, version) do nothing;
  return new;
end $$;
drop trigger if exists locations_sheet_v1 on public.locations;
create trigger locations_sheet_v1 after insert on public.locations for each row execute function public._loc_sheet_v1();

-- ---------- (8) Control Center: what waits for the caller ----------
create or replace function public.control_counts() returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare own boolean := public.is_owner(); hd boolean; lm boolean; sa boolean; lg boolean; res jsonb := '{}'; n int; q jsonb;
begin
  if not public.is_active() then return '{}'::jsonb; end if;
  perform public._sheet_sync_due();
  hd := public.has_grant('head_management'); lm := public.has_grant('location_manage'); sa := public.has_grant('settings_approve'); lg := public.has_grant('list_manage');
  res := jsonb_build_object('tier', case when own then 'owner' when hd then 'head' else 'delegate' end);
  if own then
    select count(*) into n from public.item_changes where status = 'pending'; res := res || jsonb_build_object('item_requests', n);
    select count(*) into n from public.exceptions where status = 'open'; res := res || jsonb_build_object('exceptions', n);
    select count(*) into n from public.release_requests where status = 'pending'; res := res || jsonb_build_object('releases', n);
    select count(*) into n from public.emergency_requests where status = 'pending'; res := res || jsonb_build_object('emergency', n);
    select count(*) into n from public.profiles where status = 'pending'; res := res || jsonb_build_object('staff_pending', n);
    select count(*) into n from public.wastage_requests where status = 'pending'; res := res || jsonb_build_object('wastage', n);
  end if;
  if own or hd or lm then
    select count(*) into n from public.locations where status in ('planned', 'setting_up'); res := res || jsonb_build_object('location_setup', n);
  end if;
  if own or hd or sa then
    select count(*) into n from public.settings_sheets where status = 'draft'; res := res || jsonb_build_object('settings_drafts', n);
  end if;
  -- the list queue is for people who may DECIDE it (the list_manage grant); head_management alone does not (the server would refuse the Lists screen)
  if (own or lg) and to_regprocedure('public.list_queue_counts()') is not null then
    execute 'select public.list_queue_counts()' into q;
    res := res || jsonb_build_object('lists', coalesce((q->>'requests')::int, 0) + coalesce((q->>'other')::int, 0));
  end if;
  return res;
end $$;

-- ---------- (9) privileges ----------
revoke all on function public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int), public._loc_steps_def(), public._loc_steps_seed(int), public._slug(text), public._loc_open_steps(int),
  public._loc_block_guard(), public._loc_closed_guard(), public._loc_status_guard(), public._sheet_values_guard(), public._sheet_in_force(int, date), public._limit_value_ok(text, jsonb), public._sheet_writethrough(int),
  public._sheet_sync_due(), public._sheet_draft_for(int, uuid), public._ls_legacy(), public._loc_sheet_v1(),
  public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts() from public, anon, authenticated;
grant execute on function public.location_save(int, jsonb), public.location_close_check(int), public.location_set_status(int, text, text, boolean), public.location_set_active(int, boolean),
  public.location_steps_init(int), public.location_step_set(int, int, boolean, text), public.location_block_override(int, text, int),
  public.get_limit(int, text, date), public.limit_missing(int, text[], date), public.sheet_list(int), public.sheet_draft(int), public.sheet_set(bigint, jsonb),
  public.sheet_discard(bigint), public.sheet_approve(bigint, date, text), public.sheet_sync_all(), public.control_counts(), public._loc_mgr(), public._sheet_viewer(), public._loc_mgr_at(int), public._sheet_viewer_at(int) to authenticated;

-- ---------------------------------------------------------------- phase17.sql
-- ============================================================
-- Phase 17 (W5a): ROLLOUT (paper / parallel / app per form x place), PAPER + APP TOGETHER (entered later + paper serial),
--                 LOCK / REVISIONS / CHANGE REQUESTS, OWNER SELF-APPROVAL SWITCH, idempotent client_id for the form offline queue.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase14.  Does NOT need phase15 / 16
--   (the rule owner_self_approve is the same key phase15 / 16 use: inserted here only when it is missing).
--   * form_rollout(form_code, location_id, mode paper | parallel | app, note, changed_by, changed_at): every existing form x place starts 'app'
--     (live forms stay in the app).  A missing row means 'app'.  RPC rollout_set / rollout_set_many: owner or the delegable grant rollout_manage; audit-logged.
--     Enforcement on the server: a BEFORE INSERT trigger on entries (like the pause trigger of phase16) refuses a NEW app entry where the mode is
--     'paper', unless it is flagged "entered later from paper" with a paper serial and the original time.  'parallel' and 'app' are allowed.
--     Switch rollout_enforce (default ON, acts only on mode 'paper' so nothing existing changes).
--   * entries: + entered_later, paper_serial, paper_at (original time), source ('app' | 'paper_entry'), rev_no, client_id, rollout_mode.
--     The paper serial is the number printed in the paper book: unique per (form, place) (index + the existing data.paper_no index of phase5, the
--     value is mirrored to data.paper_no so the gap audit sees it), the app serial (entries.serial) is software generated: the two never clash.
--     Switch entered_later_on (default ON).  number_audit_both(form, place) reports both series.
--   * save_entry gets an optional 8th argument p_meta jsonb ({client_id, entered_later, paper_serial, paper_at}); the old 7-argument calls keep working.
--     A create with a client_id that already exists returns the existing entry (idempotent re-send from the phone's offline queue).
--   * entry_change_requests + entry_revisions (append-only): after approval an entry is locked; a person who may enter the form asks for a change
--     (entry_change_request), the owner or a holder of the delegable grant change_approve decides (maker <> approver); an approval keeps the old
--     version as revision n and makes revision n+1 current.  entry_revisions_list shows the history.  reopen_entry (owner) also keeps the approved
--     version as a revision.
--   * owner_self_approve (default ON = owner exempt): decide_entry, decide_release, decide_emergency, submit_item_change / decide_item_change honour it.
--     When OFF the owner's own submission needs another approver (another owner, or a delegate: approve right on the form, release_decide,
--     emergency_decide, ITEMS approve / item_create).
-- ============================================================

-- ---------- (0) helpers (same text as phase11 / 16; here so the file stands alone) ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- ---------- (1) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('rollout_enforce', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ অবস্থায় অ্যাপে নতুন এন্ট্রি আটকানো', 'Paper অবস্থায় app-এ নতুন entry আটকানো', 'Refuse new app entries where the form is on Paper',
   'চালু থাকলে যে ফর্ম × লোকেশন ‘কাগজ’-এ আছে সেখানে সার্ভার নতুন এন্ট্রি নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)। ‘পাশাপাশি’ ও ‘অ্যাপ’-এ কিছু বদলায় না', 'On থাকলে ‘Paper’ ফর্ম×লোকেশনে server নতুন entry নেবে না (কাগজ থেকে ‘পরে তোলা’ ছাড়া)', 'When on, the server refuses a new entry at a form x place set to Paper (except one entered later from paper). Parallel and App are never blocked', 90),
 ('entered_later_on', 'entries', 'switch', 'true', null, null, null, null, 'কাগজ থেকে ‘পরে তোলা’ এন্ট্রি চালু', 'কাগজ থেকে ‘পরে তোলা’ entry চালু', 'Allow "entered later from paper" entries',
   'বাইরে কাজ করা কেউ আগে কাগজে লিখে পরে অ্যাপে তুলতে পারবেন: কাগজের নম্বর ও আসল সময় লাগে; অনুমোদনে যায়', 'বাইরে কাজ করা কেউ আগে paper-এ লিখে পরে app-এ তুলতে পারবেন: paper number ও আসল সময় লাগে', 'Someone working outside fills the paper and keys it in later: needs the paper serial and the original time; goes to approval like any entry', 91),
 ('change_requests_on', 'entries', 'switch', 'true', null, null, null, null, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ চালু', 'Approved entry বদলের request চালু', 'Allow change requests on approved entries',
   'বন্ধ করলে অনুমোদিত এন্ট্রি বদলের অনুরোধ নেওয়া হবে না (মালিক আগের মতো ‘আবার খুলুন’ ব্যবহার করবেন)', 'Off করলে approved entry বদলের request নেওয়া হবে না', 'When off, change requests are refused (the owner still has Reopen)', 92),
 ('entered_later_max_days', 'entries', 'number', null, 'days', null, 0, 3650, 'পরে তোলা এন্ট্রি: কাগজের আসল তারিখ সর্বোচ্চ কত দিন আগের (ফাঁকা = সীমা নেই)', 'পরে তোলা entry: paper-এর আসল date সর্বোচ্চ কত দিন আগের (ফাঁকা = Data needed)', 'Entered later: oldest allowed paper date, in days (blank = Data needed / no limit)',
   'ফাঁকা থাকলে কোনো সীমা নেই। দিলে: তার চেয়ে পুরনো কাগজ শুধু মালিক তুলতে পারবেন (লাল এক্সেপশনসহ)', 'ফাঁকা = no limit। দিলে: তার চেয়ে পুরনো paper শুধু owner তুলতে পারবেন (red exception সহ)', 'Blank = no limit. When set, older paper can be entered by the owner only (with a red exception)', 93),
 ('owner_self_approve', 'lists', 'switch', 'true', null, null, null, null, 'মালিক নিজের অনুরোধ নিজে অনুমোদন করতে পারবেন', 'Owner নিজের request নিজে approve করতে পারবেন', 'Owner may approve their own request',
   'বন্ধ করলে মালিকের অনুরোধও অন্য অনুমতিপ্রাপ্ত কেউ অনুমোদন করবেন', 'Off করলে owner-এর request অন্য কেউ approve করবেন', 'When off, the owner''s own requests need another approver', 50)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rollout_manage', 'master', 66, 'ফর্ম × লোকেশন: কাগজ / পাশাপাশি / অ্যাপ বদলানো', 'Form × location: Paper / Parallel / App বদলানো', 'Change a form x place between Paper / Parallel / App', 'window', null),
 ('change_approve', 'master', 67, 'অনুমোদিত এন্ট্রি বদলের অনুরোধ অনুমোদন', 'Approved entry বদলের request approve', 'Approve change requests on approved entries', 'window', null),
 ('release_decide', 'master', 68, 'লাল নিয়ন্ত্রণ ছাড়ের অনুরোধ অনুমোদন', 'Red control release request approve', 'Decide red-control release requests', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) rollout state ----------
create table if not exists public.form_rollout (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  mode text not null default 'app' check (mode in ('paper', 'parallel', 'app')),
  note text,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
alter table public.form_rollout enable row level security;
drop policy if exists form_rollout_read on public.form_rollout;
create policy form_rollout_read on public.form_rollout for select to authenticated using (public.is_active());
revoke all on public.form_rollout from public, anon, authenticated;
grant select on public.form_rollout to authenticated;
drop trigger if exists audit_form_rollout on public.form_rollout;
create trigger audit_form_rollout after insert or update on public.form_rollout for each row execute function public.log_change('form_code,location_id');
drop trigger if exists form_rollout_no_delete on public.form_rollout;
create trigger form_rollout_no_delete before delete on public.form_rollout for each row execute function public.no_hard_delete();

-- every existing form x place starts on the app (live forms stay live); a missing row also means app
insert into public.form_rollout (form_code, location_id, mode, note)
select f.code, l.id, 'app', 'start: live forms stay on the app'
from public.forms f cross join public.locations l
on conflict (form_code, location_id) do nothing;

create or replace function public.rollout_mode(p_form text, p_loc int) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select mode from public.form_rollout where form_code = p_form and location_id = p_loc), 'app');
$$;

create or replace function public._rollout_mgr() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and public.has_grant('rollout_manage'));
$$;

create or replace function public.rollout_set(p_form text, p_loc int, p_mode text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  old := public.rollout_mode(p_form, p_loc);
  insert into public.form_rollout (form_code, location_id, mode, note, changed_by, changed_at)
    values (p_form, p_loc, p_mode, nullif(left(btrim(coalesce(p_note, '')), 300), ''), auth.uid(), now())
    on conflict (form_code, location_id) do update set mode = excluded.mode, note = excluded.note, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'from', old, 'to', p_mode);
end $$;

-- bulk: null array = all forms / all places
create or replace function public.rollout_set_many(p_forms text[], p_locs int[], p_mode text, p_note text default null) returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; f text; l int;
begin
  if not public._rollout_mgr() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('paper', 'parallel', 'app') then raise exception 'bad_mode'; end if;
  for f in select code from public.forms where p_forms is null or code = any(p_forms) order by code loop
    for l in select id from public.locations where p_locs is null or id = any(p_locs) order by id loop
      perform public.rollout_set(f, l, p_mode, p_note); n := n + 1;
    end loop;
  end loop;
  return n;
end $$;

-- ---------- (3) entries: paper + app together, revision number, client id ----------
alter table public.entries add column if not exists entered_later boolean not null default false;
alter table public.entries add column if not exists paper_serial text;
alter table public.entries add column if not exists paper_at timestamptz;
alter table public.entries add column if not exists source text not null default 'app';
alter table public.entries add column if not exists rev_no int not null default 1;
alter table public.entries add column if not exists client_id uuid;
alter table public.entries add column if not exists rollout_mode text;
alter table public.entries add column if not exists reopen_snap jsonb;      -- the approved version kept at an owner reopen; becomes a revision only if the re-approved entry really differs
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'entries_source_chk') then
    alter table public.entries add constraint entries_source_chk check (source in ('app', 'paper_entry'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_later_chk') then
    alter table public.entries add constraint entries_later_chk check (not entered_later or (nullif(btrim(paper_serial), '') is not null and paper_at is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'entries_rollout_mode_chk') then
    alter table public.entries add constraint entries_rollout_mode_chk check (rollout_mode is null or rollout_mode in ('paper', 'parallel', 'app'));
  end if;
end $$;
create unique index if not exists entries_client_uq on public.entries (client_id) where client_id is not null;
-- the printed number, normalised: upper case, trimmed, leading zeros of each number dropped (A-0101 = a-101 = A-101); once per form and place, apart from the app serial
create or replace function public.norm_paper_serial(p text) returns text
language sql immutable as $$ select nullif(regexp_replace(upper(btrim(coalesce(p, ''))), '(^|[^0-9])0+([0-9])', '\1\2', 'g'), '') $$;
create or replace function public.paper_serial_collisions() returns table (form_code text, location_id int, norm text, entries bigint)
language sql stable security definer set search_path = public as $$
  select e.form_code, e.location_id, public.norm_paper_serial(e.paper_serial), count(*) from public.entries e
  where public.is_owner() and public.norm_paper_serial(e.paper_serial) is not null group by 1, 2, 3 having count(*) > 1;
$$;
do $$ begin
  if exists (select 1 from public.entries where public.norm_paper_serial(paper_serial) is not null group by form_code, location_id, public.norm_paper_serial(paper_serial) having count(*) > 1) then
    raise warning 'phase17: paper serials collide after normalisation - the unique index was NOT changed; run select * from paper_serial_collisions() as the owner and fix them, then run this file again';
  else
    create unique index if not exists entries_paper_serial_nuq on public.entries (form_code, location_id, (public.norm_paper_serial(paper_serial))) where public.norm_paper_serial(paper_serial) is not null;
    drop index if exists public.entries_paper_serial_uq;
  end if;
end $$;

create or replace function public._entries_rollout_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare m text;
begin
  m := public.rollout_mode(new.form_code, new.location_id);
  new.rollout_mode := m;
  new.source := case when new.entered_later then 'paper_entry' else 'app' end;
  if m = 'paper' and public.rule_on('rollout_enforce') and not new.entered_later then raise exception 'rollout_paper:%', new.form_code; end if;
  return new;
end $$;
drop trigger if exists entries_rollout_guard on public.entries;
create trigger entries_rollout_guard before insert on public.entries for each row execute function public._entries_rollout_guard();

-- ---------- (4) save_entry with the optional meta (client id, entered later) ----------
drop function if exists public.save_entry(uuid, text, int, date, jsonb, jsonb, text);
create or replace function public.save_entry(p_id uuid, p_form text, p_loc int, p_date date, p_data jsonb, p_flags jsonb, p_note text default null, p_meta jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int; ow boolean; cid uuid; later boolean; ps text; pat timestamptz; pt text; d date := p_date; dat jsonb := coalesce(p_data, '{}'::jsonb); has_later boolean; oldd jsonb; mx numeric; fls jsonb := coalesce(p_flags, '[]'::jsonb);
begin
  if not public.can_do(p_form, 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not exists (select 1 from public.forms where code = p_form and enabled) then raise exception 'form is switched off'; end if;
  if p_meta is not null and jsonb_typeof(p_meta) <> 'object' then raise exception 'bad_meta'; end if;
  begin cid := nullif(p_meta->>'client_id', '')::uuid; exception when others then raise exception 'bad_client_id'; end;
  has_later := p_meta is not null and p_meta ? 'entered_later';
  select staff_id into sid from public.profiles where id = auth.uid();

  if p_id is null then
    if cid is not null then
      select * into e from public.entries where client_id = cid;
      if found then
        if e.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
        if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
        return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
      end if;
    end if;
  else
    select * into e from public.entries where id = p_id for update;
    if not found then raise exception 'entry not found'; end if;
    if e.status <> 'draft' then raise exception 'entry is locked'; end if;
    if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can edit'; end if;
  end if;

  -- entered later from paper: effective values (a draft keeps its own when the meta does not mention them)
  begin later := case when has_later then coalesce((p_meta->>'entered_later')::boolean, false) else coalesce(e.entered_later, false) end;
  exception when others then raise exception 'bad_meta'; end;
  if later then
    if has_later then
      ps := nullif(btrim(coalesce(p_meta->>'paper_serial', '')), '');
      begin
        pt := nullif(btrim(coalesce(p_meta->>'paper_at', '')), '');
        if pt is null then pat := null;
        elsif pt ~ '[T ][0-9:.]+(Z|[+-][0-9]{2}(:?[0-9]{2})?)$' then pat := pt::timestamptz;      -- has an offset
        else pat := pt::timestamp at time zone 'Asia/Dhaka';                                        -- naive = Dhaka local time
        end if;
      exception when others then raise exception 'paper_time_required'; end;
    else ps := e.paper_serial; pat := e.paper_at; end if;
    if not public.rule_on('entered_later_on') and not coalesce(e.entered_later, false) then raise exception 'entered_later_off'; end if;
    if ps is null then raise exception 'paper_serial_required'; end if;
    if length(ps) > 40 then raise exception 'paper_serial_too_long'; end if;
    if pat is null then raise exception 'paper_time_required'; end if;
    if pat > now() + interval '5 minutes' then raise exception 'paper_time_future'; end if;
    d := (pat at time zone 'Asia/Dhaka')::date;                       -- the business date is the original date
    dat := jsonb_set(dat, '{paper_no}', to_jsonb(ps));                -- mirrored: the gap audit and the old unique index see it
    mx := public.rule_num('entered_later_max_days');
    if mx is not null and pat < now() - make_interval(days => mx::int) then
      if not public.is_owner() then raise exception 'entered_later_too_old'; end if;
      if not exists (select 1 from jsonb_array_elements(fls) x where x->>'code' = 'entered_later_old') then
        fls := fls || jsonb_build_array(jsonb_build_object('code', 'entered_later_old', 'level', 'red', 'src', 'system',
          'text', jsonb_build_object('bn', 'কাগজের তারিখ সীমার চেয়ে পুরনো — পরে তোলা', 'en', 'Entered later: paper date older than the limit')));
      end if;
    end if;
    if exists (select 1 from public.entries x where x.form_code = p_form and x.location_id = p_loc and (p_id is null or x.id <> p_id)
               and (public.norm_paper_serial(x.paper_serial) = public.norm_paper_serial(ps) or public.norm_paper_serial(x.data->>'paper_no') = public.norm_paper_serial(ps))) then raise exception 'paper_serial_in_use'; end if;
  else ps := null; pat := null; end if;

  if p_id is null then
    begin
      insert into public.serials (form_code, location_id, last) values (p_form, p_loc, 1)
        on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
      insert into public.entries (form_code, location_id, serial, entry_date, data, flags, created_by, created_staff, entered_later, paper_serial, paper_at, client_id)
        values (p_form, p_loc, n, d, dat, fls, auth.uid(), sid, later, ps, pat, cid) returning * into e;
    exception when unique_violation then
      -- two sends of the same client id at once: the loser (its serial bump is rolled back with this block) gets the winner's entry
      if cid is null then raise; end if;
      select * into e from public.entries where client_id = cid and created_by = auth.uid();
      if not found then raise; end if;
      if e.form_code <> p_form or e.location_id <> p_loc then raise exception 'client_id_mismatch'; end if;
      return jsonb_build_object('id', e.id, 'serial', e.serial, 'duplicate', true);
    end;
    return jsonb_build_object('id', e.id, 'serial', e.serial);
  end if;

  oldd := e.data;
  if e.entered_later and not later and not (dat ? 'paper_no') then oldd := e.data - 'paper_no'; end if;     -- switching “entered later” off drops only the mirrored serial: no note needed
  ow := public.jsonb_overwrites(oldd, dat);
  if ow and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  if ow then
    insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
      values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), e.data, dat);
  end if;
  update public.entries set data = dat, flags = fls, entry_date = d, updated_at = now(),
    entered_later = later, paper_serial = ps, paper_at = pat, source = case when later then 'paper_entry' else 'app' end where id = p_id;
  return jsonb_build_object('id', e.id, 'serial', e.serial, 'overwrote', ow);
end $$;
revoke all on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) from public, anon;
grant execute on function public.save_entry(uuid, text, int, date, jsonb, jsonb, text, jsonb) to authenticated;

create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) owner self-approval switch: entries ----------
create or replace function public.decide_entry(p_id uuid, p_approve boolean, p_note text default null, p_check jsonb default null, p_flags jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; self_ok boolean; auto boolean; newflags jsonb;
begin
  select * into e from public.entries where id = p_id for update;
  if not found or e.status <> 'submitted' then raise exception 'entry is not waiting for a decision'; end if;
  if not (public.can_do(e.form_code, 'approve') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if e.created_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own entry'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- flags found while checking (receiver's count, etc.) are added to the maker's flags
  newflags := coalesce(p_flags, '[]'::jsonb);
  if p_approve and e.reopen_snap is not null then
    -- an owner reopen: the old approved version becomes a revision only when the re-approved entry really differs (no empty revisions)
    if (e.reopen_snap->'data') is distinct from e.data or (e.reopen_snap->'check_data') is distinct from coalesce(p_check, e.check_data) then
      insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, reason)
        values (e.id, e.rev_no, e.reopen_snap->'data', e.reopen_snap->'check_data', e.reopen_snap->'flags', (e.reopen_snap->>'by')::uuid, e.reopen_snap->>'staff', auth.uid(), sid, e.reopen_snap->>'reason');
      update public.entries set rev_no = e.rev_no + 1 where id = p_id;
    end if;
    update public.entries set reopen_snap = null where id = p_id;
  end if;
  update public.entries set status = case when p_approve then 'approved' else 'rejected' end,
    check_data = coalesce(p_check, check_data),
    flags = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(e.flags) x where coalesce(x->>'src','') <> 'check') || newflags,
    checked_by = auth.uid(), checked_staff = sid, checked_at = now(), check_note = p_note, updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  if auto and jsonb_array_length(newflags) > 0 then
    delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in (select x->>'code' from jsonb_array_elements(newflags) x);
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(newflags) x;
  end if;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) from public, anon;
grant execute on function public.decide_entry(uuid, boolean, text, jsonb, jsonb) to authenticated;

-- red-control release: the owner as before, plus a delegate holding release_decide; maker <> approver (the owner exempt only while owner_self_approve is ON)
create or replace function public.decide_release(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r public.release_requests;
begin
  select * into r from public.release_requests where id = p_id for update;
  if not found then raise exception 'request is not pending'; end if;
  if not (public.is_owner() or (public.is_active() and public.has_grant('release_decide', (select location_id from public.entries where id = r.entry_id)))) then raise exception 'owner only'; end if;
  if r.status <> 'pending' then raise exception 'request is not pending'; end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'self_approval'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.release_requests set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_release(bigint, boolean, text) from public, anon;
grant execute on function public.decide_release(bigint, boolean, text) to authenticated;
create or replace function public._release_can_see(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('release_decide', (select location_id from public.entries where id = p_entry)));
$$;
revoke all on function public._release_can_see(uuid) from public, anon; grant execute on function public._release_can_see(uuid) to authenticated;
drop policy if exists release_read on public.release_requests;
create policy release_read on public.release_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public._release_can_see(entry_id));

-- emergency requests: someone else decides; the owner is exempt only while owner_self_approve is ON
create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;
revoke all on function public.decide_emergency(bigint, boolean, text) from public, anon;
grant execute on function public.decide_emergency(bigint, boolean, text) to authenticated;

-- item changes: the owner's own change is applied at once only while owner_self_approve is ON; otherwise it is a request for another approver
create or replace function public.submit_item_change(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint;
begin
  if not public.can_do('ITEMS', 'enter') then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if public.is_owner() and public.rule_on('owner_self_approve') then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff)
    values (p_item, p_patch, p_note, auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;
revoke all on function public.submit_item_change(uuid, jsonb, text) from public, anon;
grant execute on function public.submit_item_change(uuid, jsonb, text) to authenticated;

create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve') or (public.is_active() and public.has_grant('item_create'))) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve);
  end if;
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform set_config('bos.item_apply', '1', true); perform public.apply_item_patch(c.item_id, c.patch); perform set_config('bos.item_apply', '', true); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_item_change(bigint, boolean, text) from public, anon;
grant execute on function public.decide_item_change(bigint, boolean, text) to authenticated;

-- ---------- (6) revisions (append-only) and change requests ----------
create table if not exists public.entry_revisions (
  entry_id uuid not null references public.entries(id),
  rev_no int not null,
  data jsonb not null, check_data jsonb not null default '{}', flags jsonb not null default '[]',
  changed_by uuid, changed_staff text,                 -- who asked for the change
  approved_by uuid, approved_staff text,               -- who decided it
  request_id bigint, reason text,
  at timestamptz not null default now(),
  primary key (entry_id, rev_no)
);
create or replace function public.entry_revisions_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'entry_revisions is append-only'; end $$;
drop trigger if exists entry_revisions_no_change on public.entry_revisions;
create trigger entry_revisions_no_change before update or delete on public.entry_revisions for each row execute function public.entry_revisions_append_only();
drop trigger if exists entry_revisions_no_truncate on public.entry_revisions;
create trigger entry_revisions_no_truncate before truncate on public.entry_revisions for each statement execute function public.entry_revisions_append_only();
alter table public.entry_revisions enable always trigger entry_revisions_no_truncate;
alter table public.entry_revisions enable row level security;
drop policy if exists entry_revisions_read on public.entry_revisions;
create policy entry_revisions_read on public.entry_revisions for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id));      -- exactly the entries the caller may read (entries RLS)
revoke all on public.entry_revisions from public, anon, authenticated;
grant select on public.entry_revisions to authenticated;

create table if not exists public.entry_change_requests (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  base_rev int not null,
  requested_by uuid not null, requested_staff text,
  reason text not null check (length(btrim(reason)) > 0),
  patch jsonb not null,                                -- {data?, check_data?, flags?}: the whole new value of each part named
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text, new_rev int
);
create unique index if not exists entry_change_one_pending on public.entry_change_requests (entry_id) where status = 'pending';
create index if not exists entry_change_status on public.entry_change_requests (status, created_at desc);
-- a delegate sees (and decides) requests only for entries of a place where the grant holds AND of a form he may view / approve there
create or replace function public._ecr_scope(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.entries e where e.id = p_entry
    and public.has_grant('change_approve', e.location_id) and public.can_loc(e.location_id)
    and (public.can_do(e.form_code, 'approve') or public.can_do(e.form_code, 'view'))));
$$;
create or replace function public._ecr_can_see(p_requester uuid, p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (p_requester = auth.uid() or public._ecr_scope(p_entry));
$$;
alter table public.entry_change_requests enable row level security;
drop policy if exists entry_change_read on public.entry_change_requests;
create policy entry_change_read on public.entry_change_requests for select to authenticated using (public._ecr_can_see(requested_by, entry_id));
revoke all on public.entry_change_requests from public, anon, authenticated;
grant select on public.entry_change_requests to authenticated;
drop trigger if exists audit_entry_change on public.entry_change_requests;
create trigger audit_entry_change after insert or update on public.entry_change_requests for each row execute function public.log_change('id');
drop trigger if exists entry_change_no_delete on public.entry_change_requests;
create trigger entry_change_no_delete before delete on public.entry_change_requests for each row execute function public.no_hard_delete();

create or replace function public.entry_change_request(p_entry uuid, p_reason text, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; rid bigint;
begin
  if not public.rule_on('change_requests_on') then raise exception 'change_requests_off'; end if;
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'note_required'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or not (p_patch ?| array['data', 'check_data', 'flags']) then raise exception 'bad_patch'; end if;
  if p_patch ? 'data' and jsonb_typeof(p_patch->'data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'check_data' and jsonb_typeof(p_patch->'check_data') <> 'object' then raise exception 'bad_patch'; end if;
  if p_patch ? 'flags' and jsonb_typeof(p_patch->'flags') <> 'array' then raise exception 'bad_patch'; end if;
  if length(p_patch::text) > 400000 then raise exception 'bad_patch'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.can_do(e.form_code, 'enter') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  if e.status <> 'approved' then raise exception 'not_locked'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.entry_change_requests (entry_id, base_rev, requested_by, requested_staff, reason, patch)
      values (e.id, e.rev_no, auth.uid(), sid, left(btrim(p_reason), 500), p_patch) returning id into rid;
  exception when unique_violation then raise exception 'change_pending'; end;
  return jsonb_build_object('id', rid, 'status', 'pending');
end $$;

create or replace function public.entry_change_cancel(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now()
   where id = p_id and requested_by = auth.uid() and status = 'pending';
  if not found then raise exception 'request is not pending'; end if;
end $$;

create or replace function public.entry_change_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.entry_change_requests; e public.entries; sid text; nd jsonb; nc jsonb; nf jsonb; auto boolean; nr int; self_ok boolean;
begin
  select * into r from public.entry_change_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  select * into e from public.entries where id = r.entry_id for update;
  if not public._ecr_scope(e.id) then raise exception 'not allowed'; end if;
  if public.is_owner() then self_ok := public.rule_on('owner_self_approve');
  else self_ok := exists (select 1 from public.user_roles ur join public.roles ro on ro.code = ur.role_code where ur.user_id = auth.uid() and ro.allow_self_approve);
  end if;
  if r.requested_by = auth.uid() and not self_ok then raise exception 'self_approval'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if not p_approve then
    update public.entry_change_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500) where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;
  if e.status <> 'approved' or e.rev_no <> r.base_rev then raise exception 'stale_request'; end if;
  nd := coalesce(r.patch->'data', e.data); nc := coalesce(r.patch->'check_data', e.check_data); nf := coalesce(r.patch->'flags', e.flags);
  if e.entered_later then nd := jsonb_set(nd, '{paper_no}', to_jsonb(e.paper_serial)); end if;     -- the paper serial never changes through a revision
  nr := e.rev_no + 1;
  insert into public.entry_revisions (entry_id, rev_no, data, check_data, flags, changed_by, changed_staff, approved_by, approved_staff, request_id, reason)
    values (e.id, e.rev_no, e.data, e.check_data, e.flags, r.requested_by, r.requested_staff, auth.uid(), sid, r.id, r.reason);
  update public.entries set data = nd, check_data = nc, flags = nf, rev_no = nr, updated_at = now() where id = e.id;
  if r.patch ? 'flags' then
    select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
    delete from public.exceptions where entry_id = e.id and status = 'open';
    if auto then
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
        from jsonb_array_elements(nf) x;
    end if;
  end if;
  update public.entry_change_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 500), new_rev = nr where id = p_id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'revision', 'entries', e.id::text, jsonb_build_object('form', e.form_code, 'serial', e.serial, 'from_rev', e.rev_no, 'to_rev', nr, 'request', r.id, 'reason', r.reason));
  return jsonb_build_object('status', 'approved', 'rev_no', nr);
end $$;

-- the history of an entry: every older version (immutable) and the current one
create or replace function public.entry_revisions_list(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if not (public.is_owner() or (public.can_do(e.form_code, 'view') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'rev_no')::int desc) from (
      select jsonb_build_object('rev_no', v.rev_no, 'current', false, 'data', v.data, 'check_data', v.check_data, 'flags', v.flags,
             'changed_staff', v.changed_staff, 'approved_staff', v.approved_staff, 'at', v.at, 'reason', v.reason) x
      from public.entry_revisions v where v.entry_id = e.id
      union all
      select jsonb_build_object('rev_no', e.rev_no, 'current', true, 'data', e.data, 'check_data', e.check_data, 'flags', e.flags,
             'changed_staff', null, 'approved_staff', e.checked_staff, 'at', e.updated_at, 'reason', null)) q), '[]'::jsonb);
end $$;

-- how many change requests the caller may decide (for Needs-you / badge)
create or replace function public.entry_change_counts() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('pending', (select count(*) from public.entry_change_requests q where q.status = 'pending' and public._ecr_scope(q.entry_id)
    and (q.requested_by <> auth.uid() or (public.is_owner() and public.rule_on('owner_self_approve')))));
$$;

-- reopen (owner): pending change requests of the entry are cancelled; the approved version is kept and becomes a revision only if the re-approved entry differs
create or replace function public.reopen_entry(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status = 'draft' then return jsonb_build_object('status', 'draft'); end if;
  if e.status = 'approved' and not public.is_owner() then raise exception 'only the owner can reopen an approved entry'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can reopen'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
    values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), jsonb_build_object('status', e.status, 'data', e.data), null);
  if e.status = 'approved' then
    update public.entries set reopen_snap = jsonb_build_object('data', e.data, 'check_data', e.check_data, 'flags', e.flags, 'by', auth.uid(), 'staff', sid, 'reason', 'reopened: ' || left(btrim(p_note), 400)) where id = p_id;
  end if;
  update public.entry_change_requests set status = 'cancelled', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = 'entry reopened by the owner'
    where entry_id = p_id and status = 'pending';
  update public.entries set status = 'draft', submitted_at = null, checked_by = null, checked_staff = null, checked_at = null, check_note = null, check_data = '{}', updated_at = now() where id = p_id;
  return jsonb_build_object('status', 'draft');
end $$;
revoke all on function public.reopen_entry(uuid, text) from public, anon;
grant execute on function public.reopen_entry(uuid, text) to authenticated;

-- ---------- (7) gap audit over both series ----------
create or replace function public.number_audit_both(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss_n bigint; miss bigint[]; later bigint; pa jsonb; ap jsonb;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  begin pa := public.number_audit(p_form, p_loc);
  exception when others then
    if sqlerrm like '%range too wide%' then pa := jsonb_build_object('range_too_wide', true); else raise; end if;
  end;
  select min(serial), max(serial), count(*) into lo, hi, cnt from public.entries where form_code = p_form and location_id = p_loc;
  select count(*) into later from public.entries where form_code = p_form and location_id = p_loc and entered_later;
  if cnt = 0 then ap := jsonb_build_object('entered', 0, 'missing_count', 0, 'missing', '[]'::jsonb);
  elsif hi - lo > 100000 then ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'range_too_wide', true);
  else
    select coalesce(array_agg(g order by g), '{}') into miss from (select g from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g) limit 200) m;
    select count(*) into miss_n from generate_series(lo, hi) g where not exists (select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc and e.serial = g);
    ap := jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'missing_count', miss_n, 'missing', to_jsonb(miss));
  end if;
  return jsonb_build_object('paper', pa, 'app', ap, 'entered_later', later);
end $$;

-- ---------- (7b) the owner self-approval switch may only go OFF while another person can approve ----------
create or replace function public._other_approver_exists() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p where p.status = 'active' and p.id <> auth.uid() and (
      exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = 'owner')
      or exists (select 1 from public.user_roles ur join public.role_form_perms f on f.role_code = ur.role_code join public.roles ro on ro.code = ur.role_code and ro.active
                 where ur.user_id = p.id and f.can_approve)
      or exists (select 1 from public.user_grants g where g.user_id = p.id and g.grant_code in ('change_approve', 'release_decide', 'item_create') and (g.valid_until is null or g.valid_until > now()))));
$$;
create or replace function public.owner_self_approve_set(p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if not p_on and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_on));
  return jsonb_build_object('owner_self_approve', p_on);
end $$;
create or replace function public._rules_self_approve_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- only for the API roles (set_rule through the app): a direct SQL update by the database owner is not blocked
  if current_setting('role', true) = 'authenticated' and new.key = 'owner_self_approve'
     and coalesce(new.value, new.default_value) = 'false'::jsonb and not public._other_approver_exists() then raise exception 'no_other_approver'; end if;
  return new;
end $$;
drop trigger if exists rules_self_approve_guard on public.rules;
create trigger rules_self_approve_guard before update on public.rules for each row execute function public._rules_self_approve_guard();
revoke all on function public._other_approver_exists(), public.owner_self_approve_set(boolean), public._rules_self_approve_guard(), public._ecr_scope(uuid), public.norm_paper_serial(text), public.paper_serial_collisions() from public, anon;
grant execute on function public.owner_self_approve_set(boolean), public.paper_serial_collisions(), public._ecr_scope(uuid), public.norm_paper_serial(text) to authenticated;

-- ---------- (8) privileges ----------
revoke all on function public.rollout_mode(text, int), public._rollout_mgr(), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public._entries_rollout_guard(), public.entry_revisions_append_only(), public.entry_change_request(uuid, text, jsonb),
  public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text), public.entry_revisions_list(uuid), public.entry_change_counts(),
  public.number_audit_both(text, int), public._ecr_can_see(uuid, uuid) from public, anon;
grant execute on function public.rollout_mode(text, int), public.rollout_set(text, int, text, text), public.rollout_set_many(text[], int[], text, text),
  public.entry_change_request(uuid, text, jsonb), public.entry_change_cancel(bigint), public.entry_change_decide(bigint, boolean, text),
  public.entry_revisions_list(uuid), public.entry_change_counts(), public.number_audit_both(text, int) to authenticated;
grant execute on function public._ecr_can_see(uuid, uuid) to authenticated;   -- used by the RLS policy
revoke execute on function public._rollout_mgr(), public._entries_rollout_guard(), public.entry_revisions_append_only() from authenticated;

-- ---------------------------------------------------------------- phase18.sql
-- PHASE 18 (W5): server-side BLIND COUNT for forms 14-1 (drawer) and 10-1 (hub), and PIN SIGNATURES (second signature = another login).
-- Additive, idempotent, safe to paste whole in the Supabase SQL editor.  ORDER: phase8..phase17 first (needs phase16 get_limit and phase17 for nothing else).
-- Everything is OFF by default: rules blind_count_on, pin_signature_on = false.  Nothing changes for any form until the owner switches them on.
--
-- BLIND COUNT (rule 9)
--   count_save(entry, section, counted): the counted figure is stored FIRST (immutable), the expected figure is computed on the server from the
--   entry's other saved data and returned only after the save.  Short/over is stored always (also 0) in entry_counts and mirrored to
--   entries.check_data.blind.  `expected` is never stored in entries.data and never returned by any function before the count is saved,
--   except to the owner / holders of the delegable grant see_expected (count_peek, logged; rule owner_sees_expected_first can take it from the owner too).
--   sections: 'drawer' = 14-1 (the maker counts the cash drawer), 'hub' = 10-1 (the hub person counts the handover).
-- PIN SIGNATURES (rule 10)
--   A second signature is a different login with its own PIN.  The browser signs the second person in on a throw-away client (no session kept)
--   and that client calls sign_entry: auth.uid() is the signer.  The server refuses signer = maker, one login twice, a role signed twice,
--   a signer without access to the place, a locked login.  entry_signatures is append-only.  Wrong PINs go through login_failed (phase11).
--   NOTE: SQL cannot check another user's password, so the PIN itself is checked by Supabase Auth, not by this file.

-- ---------- (1) rules + grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('blind_count_on', 'entries', 'switch', 'false', null, null, null, null, 'অন্ধ গণনা: আগে গণনা সেভ, তারপর প্রত্যাশিত অঙ্ক', 'Blind count: আগে count save, তারপর expected', 'Blind count: save the count first, then see the expected figure',
   'চালু করলে ১৪-১ (ড্রয়ার) ও ১০-১ (হাব)-এ প্রত্যাশিত অঙ্ক গণনা সেভের আগে দেখা যাবে না। ফর্ম × লোকেশন আলাদা করে বন্ধ করা যায়', 'চালু করলে 14-1 (drawer) ও 10-1 (hub)-এ expected figure count save-এর আগে দেখা যাবে না। form × location আলাদা বন্ধ করা যায়', 'When on, forms 14-1 (drawer) and 10-1 (hub) do not show the expected figure before the count is saved. Can be switched off per form x place', 94),
 ('owner_sees_expected_first', 'entries', 'switch', 'true', null, null, null, null, 'মালিক গণনার আগেও প্রত্যাশিত অঙ্ক দেখতে পারবেন', 'Owner count-এর আগেও expected দেখতে পারবেন', 'Owner may see the expected figure before the count is saved',
   'বন্ধ করলে মালিকও আগে দেখতে পারবেন না (see_expected অনুমতিপ্রাপ্ত অন্য কেউ পারবেন)। প্রতিবার দেখা লগে থাকে', 'বন্ধ করলে owner-ও আগে দেখতে পারবেন না (see_expected grant-ওয়ালা অন্য কেউ পারবেন)। প্রতিবার log-এ থাকে', 'When off the owner is blind too (a person holding see_expected still may). Every early look is logged', 95),
 ('pin_signature_owner_override', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর ছাড়া জমা: মালিকের ছাড় (হলুদ এক্সেপশনসহ)', 'PIN signature ছাড়া submit: owner override (yellow exception সহ)', 'Owner may submit without the PIN signatures (yellow exception)',
   'চালু থাকলে শুধু মালিক স্বাক্ষর ছাড়া জমা দিতে পারবেন; হলুদ এক্সেপশন তৈরি হয়', 'চালু থাকলে শুধু owner signature ছাড়া submit করতে পারবেন; yellow exception হয়', 'When on only the owner may submit without signatures; a yellow exception is raised', 97),
 ('pin_signature_on', 'entries', 'switch', 'false', null, null, null, null, 'পিন স্বাক্ষর: দ্বিতীয় স্বাক্ষর অন্য লগইন + নিজের পিন', 'PIN signature: দ্বিতীয় signature অন্য login + নিজের PIN', 'PIN signature: the second signature is another login with its own PIN',
   'বন্ধ থাকলে আগের মতো নাম বেছে সাক্ষী। চালু করলে ফর্ম অনুযায়ী (তালিকা) সাক্ষী নিজের পিন দিয়ে স্বাক্ষর করবেন; লেখক নিজে স্বাক্ষর করতে পারবেন না', 'বন্ধ থাকলে আগের মতো name বেছে witness। চালু করলে form অনুযায়ী witness নিজের PIN দিয়ে sign করবেন', 'When off the old name-picker witness stays. When on (per form list) the witness signs with their own PIN; the maker can never be the signer', 96)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('see_expected', 'master', 69, 'গণনা সেভের আগে প্রত্যাশিত অঙ্ক দেখা', 'Count save-এর আগে expected দেখা', 'See the expected figure before the count is saved', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- (2) per form x place / per form switch lists ----------
create table if not exists public.blind_count_cfg (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now(),
  primary key (form_code, location_id)
);
create table if not exists public.pin_sig_cfg (
  form_code text primary key references public.forms(code),
  enabled boolean not null default true,
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.blind_count_cfg enable row level security;
alter table public.pin_sig_cfg enable row level security;
drop policy if exists blind_count_cfg_read on public.blind_count_cfg;
create policy blind_count_cfg_read on public.blind_count_cfg for select to authenticated using (public.is_active());
drop policy if exists pin_sig_cfg_read on public.pin_sig_cfg;
create policy pin_sig_cfg_read on public.pin_sig_cfg for select to authenticated using (public.is_active());
revoke all on public.blind_count_cfg, public.pin_sig_cfg from public, anon, authenticated;
grant select on public.blind_count_cfg, public.pin_sig_cfg to authenticated;
drop trigger if exists audit_blind_count_cfg on public.blind_count_cfg;
create trigger audit_blind_count_cfg after insert or update on public.blind_count_cfg for each row execute function public.log_change('form_code,location_id');
drop trigger if exists audit_pin_sig_cfg on public.pin_sig_cfg;
create trigger audit_pin_sig_cfg after insert or update on public.pin_sig_cfg for each row execute function public.log_change('form_code');
drop trigger if exists blind_count_cfg_no_delete on public.blind_count_cfg;
create trigger blind_count_cfg_no_delete before delete on public.blind_count_cfg for each row execute function public.no_hard_delete();
drop trigger if exists pin_sig_cfg_no_delete on public.pin_sig_cfg;
create trigger pin_sig_cfg_no_delete before delete on public.pin_sig_cfg for each row execute function public.no_hard_delete();

create or replace function public.blind_active(p_form text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc), true);
$$;
create or replace function public.pin_sig_active(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1') and public.rule_on('pin_signature_on')
     and coalesce((select enabled from public.pin_sig_cfg where form_code = p_form), true);
$$;
create or replace function public.blind_cfg_set(p_form text, p_loc int, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  insert into public.blind_count_cfg (form_code, location_id, enabled, changed_by, changed_at) values (p_form, p_loc, p_enabled, auth.uid(), now())
    on conflict (form_code, location_id) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'enabled', p_enabled);
end $$;
create or replace function public.pin_sig_cfg_set(p_form text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  insert into public.pin_sig_cfg (form_code, enabled, changed_by, changed_at) values (p_form, p_enabled, auth.uid(), now())
    on conflict (form_code) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'enabled', p_enabled);
end $$;

-- ---------- (3) counts ----------
-- the maker of a draft must not learn expected / diff from the server while blind is on (only an approver, or a see_expected holder, does)
create or replace function public._count_hide18(e public.entries) returns boolean
language sql stable security definer set search_path = public as $$
  select public.blind_active(e.form_code, e.location_id) and e.status = 'draft' and e.created_by = auth.uid() and not public.has_grant('see_expected', e.location_id);
$$;
create table if not exists public.entry_counts (
  entry_id uuid not null references public.entries(id),
  section text not null check (section in ('drawer', 'hub')),
  counted_detail jsonb not null,                 -- what the person typed (notes by denomination, or one number)
  counted numeric not null check (counted between 0 and 1000000000),
  expected numeric not null,                     -- computed on the server at save time (kept here, never in entries.data)
  diff numeric not null,                         -- counted - expected, ALWAYS stored, also 0
  inputs_hash text,                              -- hash of the figures the expected value was made from
  counted_by uuid not null, counted_staff text, counted_at timestamptz not null default now(),
  expected_seen_by uuid, expected_seen_at timestamptz,
  seen_before_count boolean not null default false,
  primary key (entry_id, section)
);
create table if not exists public.entry_count_peeks (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  section text not null,
  seen_by uuid not null, seen_staff text, seen_at timestamptz not null default now()
);
create or replace function public._append_only18() returns trigger
language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
drop trigger if exists entry_counts_no_change on public.entry_counts;
create trigger entry_counts_no_change before update or delete on public.entry_counts for each row execute function public._append_only18();
drop trigger if exists entry_counts_no_truncate on public.entry_counts;
create trigger entry_counts_no_truncate before truncate on public.entry_counts for each statement execute function public._append_only18();
alter table public.entry_counts enable always trigger entry_counts_no_truncate;
drop trigger if exists entry_count_peeks_no_change on public.entry_count_peeks;
create trigger entry_count_peeks_no_change before update or delete on public.entry_count_peeks for each row execute function public._append_only18();
drop trigger if exists entry_count_peeks_no_truncate on public.entry_count_peeks;
create trigger entry_count_peeks_no_truncate before truncate on public.entry_count_peeks for each statement execute function public._append_only18();
alter table public.entry_count_peeks enable always trigger entry_count_peeks_no_truncate;
alter table public.entry_counts enable row level security;
alter table public.entry_count_peeks enable row level security;
drop policy if exists entry_counts_read on public.entry_counts;
create policy entry_counts_read on public.entry_counts for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id and not public._count_hide18(e)));      -- rows exist only AFTER the count; the maker of a blind draft does not read expected / diff
drop policy if exists entry_count_peeks_read on public.entry_count_peeks;
create policy entry_count_peeks_read on public.entry_count_peeks for select to authenticated using (public.is_owner());
revoke all on public.entry_counts, public.entry_count_peeks from public, anon, authenticated;
grant select on public.entry_counts, public.entry_count_peeks to authenticated;
revoke all on sequence public.entry_count_peeks_id_seq from public, anon, authenticated;

-- lenient number of a json field (blank / junk / Infinity = 0), same as the browser's num()
create or replace function public._n18(j jsonb, k text) returns numeric
language plpgsql immutable set search_path = public as $$
declare v numeric;
begin
  v := nullif(btrim(coalesce(j ->> k, '')), '')::numeric;
  if v is null or not (v between -1000000000000 and 1000000000000) then return 0; end if;
  return v;
exception when others then return 0;
end $$;

-- total of a count: a plain number, or notes by denomination {n1000..n1, coin}.  strict = refuse bad input
create or replace function public._den_total18(j jsonb, strict boolean) returns numeric
language plpgsql immutable set search_path = public as $$
declare t numeric := 0; d int; v numeric; k text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return 0; end if;
  if jsonb_typeof(j) = 'number' then
    v := (j #>> '{}')::numeric;
    if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
    return v;
  end if;
  if jsonb_typeof(j) <> 'object' then if strict then raise exception 'bad_count'; end if; return 0; end if;
  foreach d in array array[1000, 500, 200, 100, 50, 20, 10, 5, 2, 1] loop
    k := 'n' || d;
    if j ? k then
      begin v := nullif(btrim(j ->> k), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
      if v is not null then
        if not (v between 0 and 1000000) or (strict and v <> trunc(v)) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
        t := t + d * v;
      end if;
    end if;
  end loop;
  if j ? 'coin' then
    begin v := nullif(btrim(j ->> 'coin'), '')::numeric; exception when others then v := null; if strict then raise exception 'bad_count'; end if; end;
    if v is not null then
      if not (v between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; v := 0; end if;
      t := t + v;
    end if;
  end if;
  if not (t between 0 and 1000000000) then if strict then raise exception 'bad_count'; end if; return 0; end if;
  return t;
end $$;

-- the figures the expected value is made of (also hashed, to show later changes)
create or replace function public._count_inputs18(e public.entries, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fl numeric; fj jsonb; d jsonb := e.data;
begin
  if p_section = 'drawer' then
    begin fj := public.get_limit(e.location_id, 'drawer_float', e.entry_date); exception when others then fj := null; end;
    fl := case when fj is null or jsonb_typeof(fj) <> 'number' then null else (fj #>> '{}')::numeric end;
    return jsonb_build_object('float', fl, 'open_counted', nullif(btrim(coalesce(d ->> 'open_counted', '')), ''),
      'total', public._n18(d, 'total_entered'), 'digital', public._n18(d, 'd_bkash') + public._n18(d, 'd_nagad') + public._n18(d, 'd_card') + public._n18(d, 'd_bank') + public._n18(d, 'd_other'),
      'dues', public._n18(d, 'dues'), 'new_adv', public._n18(d, 'new_adv'), 'prior_adv', public._n18(d, 'prior_adv'), 'refund', public._n18(d, 'refund'),
      'credit', public._n18(d, 'credit_sales'), 'midday', public._n18(d, 'midday_hub'), 'rounding', public._n18(d, 'rounding'));
  end if;
  return jsonb_build_object('sent', public._den_total18(d -> 'count', false), 'leave', public._n18(d, 'leave_float'));
end $$;
-- same arithmetic as forms.js (14-1: guidebook G.6 equation 1; 10-1: handover = counted - float left)
create or replace function public._count_expected18(p_in jsonb, p_section text) returns numeric
language plpgsql immutable set search_path = public as $$
declare openf numeric;
begin
  if p_section = 'drawer' then
    openf := case when p_in ->> 'open_counted' is not null then (p_in ->> 'open_counted')::numeric when p_in ->> 'float' is not null then (p_in ->> 'float')::numeric else 0 end;
    return openf + (p_in ->> 'total')::numeric - (p_in ->> 'digital')::numeric + (p_in ->> 'dues')::numeric + (p_in ->> 'new_adv')::numeric - (p_in ->> 'prior_adv')::numeric
      - (p_in ->> 'refund')::numeric - (p_in ->> 'credit')::numeric - (p_in ->> 'midday')::numeric + (p_in ->> 'rounding')::numeric;
  end if;
  return (p_in ->> 'sent')::numeric - (p_in ->> 'leave')::numeric;
end $$;

create or replace function public._count_sec18(p_section text) returns text
language sql immutable as $$ select case p_section when 'drawer' then '14-1' when 'hub' then '10-1' end; $$;

-- may the caller count / peek at this entry?
create or replace function public._count_can18(e public.entries, p_section text, p_for_save boolean) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare self_ok boolean;
begin
  if not public.is_active() or not public.can_loc(e.location_id) then return false; end if;
  if public.is_owner() then return true; end if;
  if p_section = 'drawer' then
    return e.created_by = auth.uid() or (not p_for_save and public.can_do(e.form_code, 'approve'));
  end if;
  if not public.can_do(e.form_code, 'approve') then return false; end if;
  select exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code where ur.user_id = auth.uid() and r.allow_self_approve) into self_ok;
  return e.created_by <> auth.uid() or self_ok;
end $$;


-- counted but never submitted (throw-away drafts): an owner exception once the business day is over (no invented time limit)
create or replace function public.count_unsubmitted_scan() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    select e.id, e.form_code, e.location_id, e.entry_date, 'count_unsubmitted', 'red', null,
           jsonb_build_object('bn', 'গণনা সেভ হয়েছে কিন্তু শিট জমা হয়নি', 'en', 'Count saved but the sheet was never submitted')
    from public.entry_counts c join public.entries e on e.id = c.entry_id
    where c.section = 'drawer' and e.status = 'draft' and e.entry_date < (now() at time zone 'Asia/Dhaka')::date
      and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'count_unsubmitted');
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.count_save(p_entry uuid, p_section text, p_counted jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; tot numeric; inp jsonb; ex numeric; df numeric; sid text; c public.entry_counts; peek public.entry_count_peeks; hide boolean;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  perform public.count_unsubmitted_scan();
  select * into e from public.entries where id = p_entry for update;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, true) then raise exception 'not allowed'; end if;
  if (p_section = 'drawer' and e.status <> 'draft') or (p_section = 'hub' and e.status <> 'submitted') then raise exception 'count_not_open'; end if;
  tot := public._den_total18(p_counted, true);
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then
    -- a retry of the same count (lost answer) gets the saved result; a different figure is refused: the count never changes
    if c.counted = tot and c.counted_by = auth.uid() then
      if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', c.counted, 'hidden', true, 'already', true); end if;
      return jsonb_build_object('section', p_section, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'already', true);
    end if;
    raise exception 'count_already_saved';
  end if;
  if p_section = 'drawer' then
    if not (e.data ? 'cash_count') then raise exception 'count_missing'; end if;
    if public._den_total18(e.data -> 'cash_count', false) <> tot then raise exception 'count_mismatch'; end if;
    -- one counted open draft per person, place and day: no throw-away drafts to read the expected figure
    if exists (select 1 from public.entries x join public.entry_counts k on k.entry_id = x.id and k.section = 'drawer'
               where x.form_code = e.form_code and x.location_id = e.location_id and x.entry_date = e.entry_date and x.created_by = e.created_by and x.status = 'draft' and x.id <> e.id) then
      raise exception 'count_draft_limit';
    end if;
  end if;
  if p_section = 'hub' and (e.check_data ? 'rcount') and public._den_total18(e.check_data -> 'rcount', false) <> tot then raise exception 'count_mismatch'; end if;
  inp := public._count_inputs18(e, p_section);
  ex := public._count_expected18(inp, p_section);
  df := tot - ex;
  select staff_id into sid from public.profiles where id = auth.uid();
  select * into peek from public.entry_count_peeks where entry_id = p_entry and section = p_section and seen_by = auth.uid() order by id limit 1;
  insert into public.entry_counts (entry_id, section, counted_detail, counted, expected, diff, inputs_hash, counted_by, counted_staff, counted_at, expected_seen_by, expected_seen_at, seen_before_count)
    values (p_entry, p_section, coalesce(p_counted, 'null'::jsonb), tot, ex, df, md5(inp::text), auth.uid(), sid, now(),
            coalesce(peek.seen_by, auth.uid()), coalesce(peek.seen_at, now()),
            exists (select 1 from public.entry_count_peeks where entry_id = p_entry and section = p_section));
  update public.entries set check_data = check_data where id = p_entry;          -- the guard trigger mirrors the result into check_data.blind (not while a draft)
  if public._count_hide18(e) then return jsonb_build_object('section', p_section, 'saved', true, 'counted', tot, 'hidden', true); end if;
  return jsonb_build_object('section', p_section, 'counted', tot, 'expected', ex, 'diff', df, 'match', df = 0);
end $$;

-- the expected figure BEFORE the count: only the owner (rule owner_sees_expected_first) or a holder of see_expected; every look is logged
create or replace function public.count_peek(p_entry uuid, p_section text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; c public.entry_counts; inp jsonb; sid text;
begin
  if p_section not in ('drawer', 'hub') then raise exception 'bad_section'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'entry not found'; end if;
  if e.form_code <> public._count_sec18(p_section) then raise exception 'bad_section'; end if;
  if not public._count_can18(e, p_section, false) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if found then
    if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true); end if;
    return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff);
  end if;
  if public.blind_active(e.form_code, e.location_id) then
    if public.is_owner() and not public.rule_on('owner_sees_expected_first') and not exists (
         select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'see_expected' and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = e.location_id)) then
      raise exception 'not allowed';
    end if;
    if not public.has_grant('see_expected', e.location_id) then raise exception 'not allowed'; end if;
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.entry_count_peeks (entry_id, section, seen_by, seen_staff) values (p_entry, p_section, auth.uid(), sid);
  end if;
  inp := public._count_inputs18(e, p_section);
  return jsonb_build_object('saved', false, 'expected', public._count_expected18(inp, p_section));
end $$;

-- the saved count of an entry (no expected figure unless it is saved)
create or replace function public.count_get(p_entry uuid, p_section text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; c public.entry_counts;
begin
  select * into e from public.entries where id = p_entry;
  if not found or not public.is_active() or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  select * into c from public.entry_counts where entry_id = p_entry and section = p_section;
  if not found then return jsonb_build_object('saved', false, 'blind', public.blind_active(e.form_code, e.location_id)); end if;
  if public._count_hide18(e) then return jsonb_build_object('saved', true, 'counted', c.counted, 'hidden', true, 'counted_at', c.counted_at); end if;
  return jsonb_build_object('saved', true, 'counted', c.counted, 'expected', c.expected, 'diff', c.diff, 'match', c.diff = 0, 'counted_at', c.counted_at, 'counted_staff', c.counted_staff,
    'seen_before_count', c.seen_before_count, 'inputs_changed', md5(public._count_inputs18(e, p_section)::text) is distinct from c.inputs_hash);
end $$;

-- guard on entries: a saved count cannot be changed through the entry, the result is mirrored into check_data.blind once the sheet is submitted,
-- and the server adds the cash short/over flag at submit (the maker never sees expected / diff before that)
create or replace function public._entries_blind_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.entry_counts; tol numeric; tj jsonb; lvl text;
begin
  for r in select * from public.entry_counts where entry_id = new.id loop
    if r.section = 'drawer' then
      if new.data is distinct from old.data and (new.data ? 'cash_count') and public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
      if old.status = 'draft' and new.status = 'submitted' then
        if not (new.data ? 'cash_count') or public._den_total18(new.data -> 'cash_count', false) <> r.counted then raise exception 'count_locked'; end if;
        if r.diff <> 0 and not exists (select 1 from jsonb_array_elements(new.flags) f where f ->> 'code' = 'cash_short_over') then
          begin tj := public.get_limit(new.location_id, 'cash_tol', new.entry_date); exception when others then tj := null; end;
          tol := case when tj is not null and jsonb_typeof(tj) = 'number' then (tj #>> '{}')::numeric end;
          lvl := case when tol is not null and abs(r.diff) <= tol then 'yellow' else 'red' end;
          new.flags := new.flags || jsonb_build_array(jsonb_build_object('code', 'cash_short_over', 'level', lvl, 'amount', r.diff, 'src', 'system',
            'text', case when r.diff < 0 then jsonb_build_object('bn', 'ক্যাশ কম', 'en', 'Cash short') else jsonb_build_object('bn', 'ক্যাশ বেশি', 'en', 'Cash over') end));
        end if;
      end if;
    elsif new.check_data ? 'rcount' and public._den_total18(new.check_data -> 'rcount', false) <> r.counted then raise exception 'count_locked';
    end if;
  end loop;
  if new.status = 'draft' then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) - 'blind';
  elsif exists (select 1 from public.entry_counts where entry_id = new.id) then
    new.check_data := coalesce(new.check_data, '{}'::jsonb) || jsonb_build_object('blind', (
      select jsonb_object_agg(section, jsonb_build_object('counted', counted, 'expected', expected, 'diff', diff, 'match', diff = 0, 'counted_at', counted_at))
      from public.entry_counts where entry_id = new.id));
  end if;
  return new;
end $$;
drop trigger if exists entries_blind_guard on public.entries;
create trigger entries_blind_guard before update on public.entries for each row execute function public._entries_blind_guard();

-- ---------- (4) PIN signatures ----------
create table if not exists public.entry_signatures (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  role text not null check (role in ('witness', 'second_sig', 'hub_pair')),
  signer_id uuid not null, signer_staff text,
  signed_at timestamptz not null default now(),
  data_hash text not null,                         -- md5 of the sheet (without the signer names) when it was signed: a later change makes the signature stale
  unique (entry_id, role, data_hash),
  unique (entry_id, signer_id, data_hash)
);
drop trigger if exists entry_signatures_no_change on public.entry_signatures;
create trigger entry_signatures_no_change before update or delete on public.entry_signatures for each row execute function public._append_only18();
drop trigger if exists entry_signatures_no_truncate on public.entry_signatures;
create trigger entry_signatures_no_truncate before truncate on public.entry_signatures for each statement execute function public._append_only18();
alter table public.entry_signatures enable always trigger entry_signatures_no_truncate;
alter table public.entry_signatures enable row level security;
drop policy if exists entry_signatures_read on public.entry_signatures;
create policy entry_signatures_read on public.entry_signatures for select to authenticated using (exists (select 1 from public.entries e where e.id = entry_id));
revoke all on public.entry_signatures from public, anon, authenticated;
grant select on public.entry_signatures to authenticated;
drop trigger if exists audit_entry_signatures on public.entry_signatures;
create trigger audit_entry_signatures after insert on public.entry_signatures for each row execute function public.log_change('entry_id,role');

create or replace function public._sig_hash18(d jsonb) returns text
language sql immutable as $$ select md5(((coalesce(d, '{}'::jsonb)) - 'witness' - 'second_sig' - 'pair_by')::text); $$;
create or replace function public._addflag18(fl jsonb, p_code text, p_level text, p_bn text, p_en text) returns jsonb
language sql immutable as $$ select coalesce(fl, '[]'::jsonb) || jsonb_build_array(jsonb_build_object('code', p_code, 'level', p_level, 'src', 'system', 'text', jsonb_build_object('bn', p_bn, 'en', p_en))); $$;

-- called by the SECOND person's own session (their PIN was checked by Supabase Auth in the browser): auth.uid() is the signer
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; iat numeric; h text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry for update;
  -- place first, one text for every refusal of access (no hint whether the entry exists)
  if not found or not public.can_loc(e.location_id) or not (public.can_do(e.form_code, 'enter') or public.can_do(e.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  if (p_role in ('witness', 'second_sig') and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  -- a fresh sign-in just now (the browser signs the signer in on a second client): an old token cannot sign
  begin iat := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'iat', nullif(current_setting('request.jwt.claim.iat', true), ''))::numeric; exception when others then iat := null; end;
  if iat is null or iat < extract(epoch from now()) - 120 then raise exception 'login_not_fresh'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  h := public._sig_hash18(e.data);
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid() and data_hash = h) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role and data_hash = h) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff, data_hash) values (p_entry, p_role, auth.uid(), sid, h);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;

-- a draft cannot be submitted without valid (not stale) PIN signatures once they are switched on for the form
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text; h text; missing text[] := '{}';
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] else array['hub_pair'] end;
  h := public._sig_hash18(new.data);
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r and data_hash = h order by id desc limit 1;
    if s is null then
      missing := missing || r;
      continue;
    end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  if array_length(missing, 1) > 0 then
    if new.entered_later then
      new.flags := public._addflag18(new.flags, 'unsigned_entered_later', 'yellow', 'কাগজ থেকে পরে তোলা — পিন স্বাক্ষর নেই', 'Entered later from paper - no PIN signature');
    elsif public.is_owner() and public.rule_on('pin_signature_owner_override') then
      new.flags := public._addflag18(new.flags, 'unsigned_owner_override', 'yellow', 'মালিকের ছাড়ে পিন স্বাক্ষর ছাড়া জমা', 'Submitted without PIN signatures by the owner override');
    else
      r := missing[1];
      if exists (select 1 from public.entry_signatures where entry_id = new.id and role = r) then raise exception 'pin_signature_stale:%', r; end if;
      raise exception 'pin_signature_required:%', r;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists entries_sig_guard on public.entries;
create trigger entries_sig_guard before update on public.entries for each row execute function public._entries_sig_guard();


-- submit_entry (phase17 body) with ONE change: the exceptions are made from the flags AFTER the update, so flags the server adds at submit
-- (cash_short_over from the saved blind count, unsigned_entered_later, unsigned_owner_override) become exceptions too
create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if public.rollout_mode(e.form_code, e.location_id) = 'paper' and public.rule_on('rollout_enforce') and not e.entered_later then
    raise exception 'rollout_paper:%', e.form_code;
  end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and fl->>'code' <> 'entered_later_old' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select * into e from public.entries where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code <> 'count_unsubmitted';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;
revoke all on function public.submit_entry(uuid) from public, anon;
grant execute on function public.submit_entry(uuid) to authenticated;

-- ---------- (5) rights ----------
revoke execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries), public._sig_hash18(jsonb), public._addflag18(jsonb, text, text, text, text),
  public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from public, anon;
grant execute on function public.blind_active(text, int), public.pin_sig_active(text), public.blind_cfg_set(text, int, boolean), public.pin_sig_cfg_set(text, boolean),
  public.count_save(uuid, text, jsonb), public.count_peek(uuid, text), public.count_get(uuid, text), public.sign_entry(uuid, text), public.count_unsubmitted_scan(), public._count_hide18(public.entries) to authenticated;   -- _count_hide18 is used by the entry_counts read policy
-- the helpers stay internal (they are called inside security definer functions); authenticated needs no direct access
revoke execute on function public._n18(jsonb, text), public._den_total18(jsonb, boolean), public._count_inputs18(public.entries, text), public._count_expected18(jsonb, text),
  public._count_sec18(text), public._count_can18(public.entries, text, boolean), public._entries_blind_guard(), public._entries_sig_guard(), public._append_only18() from authenticated;

-- ---------------------------------------------------------------- phase19.sql
-- Phase 19 (W6): recipes / BOM, packaging rule, production that consumes raw material.
--   Additive and idempotent (paste whole in the Supabase SQL editor; run twice is fine). Needs phase8..phase14 (stock ledger, items, item types). phase15..18 are not required.
--   * recipes (a version per finished good) + recipe_lines (ingredients: raw_material / packaging / resale items, qty, unit, waste % - empty waste = "Data needed")
--     A version that has been used by a production run is immutable (a change is a NEW version). Nothing is deleted: active flag. No cost columns anywhere.
--   * recipe_cost(recipe, loc): cost of one batch from the stock average cost - only for the owner / ITEM_COST / view_cost people.
--   * product_packaging (packaging per product, applies to sale or production) + setting packaging_consume_on (off | sale | production, default off).
--       sale       -> an AFTER INSERT trigger on sales (separate from the stock trigger, record_sale2 is NOT changed) takes the packaging out of the ledger
--                     with the SOFT mode (a sale is never blocked); if one packaging line cannot be posted the sale still goes through and the owner gets a yellow
--                     line `packaging_not_consumed`. A void gives the packaging back.
--       production -> production_post takes the packaging out in the same transaction as the ingredients.
--   * production_post(loc, recipe, batches, client, made_at, note): ONE transaction: ledger OUT per ingredient (qty x batches x (1 + waste%)) at the weighted average
--     cost, ledger IN of the finished good (yield x batches) with batch + expiry from shelf_life_for(), idempotent by client id, period lock, can_loc, grant
--     stock_production (+ its emergency rule em_stock_production), shortage refused (setting production_short_mode) with the full list of what is short.
--   * production_preview / production_can_make for the production sheet and the "what can I make now" view (no costs).
--   * settings: packaging_consume_on, production_requires_recipe (default OFF: the old stock_production_in works as before), production_short_mode,
--     recipe_waste_required (default OFF: an empty waste % is treated as 0 and the owner gets a yellow line). Grant recipe_manage (delegable).
--   The old stock_production_in is re-created with the same body plus one switch check (production_requires_recipe).

-- ---------- settings and grant ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('packaging_consume_on', 'stock', 'choice', '"off"', '["off","sale","production"]', null, null,
  'প্যাকেজিং কখন স্টক থেকে কমবে: বন্ধ / বিক্রিতে / উৎপাদনে', 'Packaging কখন stock থেকে কমবে: off / sale / production', 'When packaging leaves the stock: off, with a sale, or with production',
  'Off = packaging is not taken out automatically. Uses the per-product packaging list. A sale is never blocked by packaging.', 190),
 ('production_requires_recipe', 'stock', 'switch', 'false', null, null, null,
  'উৎপাদন শুধু রেসিপি দিয়েই (পুরনো সরাসরি "উৎপাদিত মাল তোলা" বন্ধ)', 'Production শুধু recipe দিয়েই (পুরনো সরাসরি "Production in" বন্ধ)', 'Production only through a recipe (the old direct "Production in" is refused)',
  'Off = the direct production-in works as before. On = every production must use a recipe so the raw material is taken out.', 191),
 ('production_short_mode', 'stock', 'choice', '"refuse"', '["refuse","follow_stock_rule"]', null, null,
  'কাঁচামাল কম থাকলে: আটকানো / স্টকের সাধারণ নিয়ম', 'Raw material কম থাকলে: refuse / stock এর সাধারণ rule', 'When raw material is short: refuse, or follow the general stock rule',
  'refuse = the production is refused (unless stock_negative_mode is allow, or the person may sell below zero). follow_stock_rule = same as selling (warn / block / allow).', 192),
 ('recipe_waste_required', 'stock', 'switch', 'false', null, null, null,
  'রেসিপিতে অপচয় % না থাকলে উৎপাদন আটকানো', 'Recipe এ waste % না থাকলে production আটকানো', 'Refuse production when a recipe line has no waste %',
  'Off = an empty waste % counts as 0 and the owner gets a yellow line. The owner sets the real waste %; nothing is guessed.', 193)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_manage', 'master', 69, 'রেসিপি ও প্যাকেজিং নিয়ম তৈরি / বদল', 'Recipe ও packaging rule তৈরি / বদল', 'Create and change recipes and packaging rules', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- tables ----------
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  version int not null check (version >= 1),
  yield_qty numeric not null check (yield_qty > 0 and yield_qty < 1000000000),
  yield_unit text,                                           -- null = the item base unit
  active boolean not null default true,
  note text,
  used_at timestamptz,                                       -- first production run: from then on the version is frozen
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  unique (item_id, version)
);
create index if not exists recipes_item on public.recipes (item_id, active);
create table if not exists public.recipe_lines (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  ingredient_item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty < 1000000000),
  unit text,                                                 -- null = the ingredient base unit
  waste_pct numeric check (waste_pct is null or (waste_pct >= 0 and waste_pct <= 100)),     -- null = Data needed
  note text,
  sort int not null default 0,
  unique (recipe_id, ingredient_item_id)
);
alter table public.recipe_lines add column if not exists active boolean not null default true;
alter table public.recipe_lines drop constraint if exists recipe_lines_recipe_id_ingredient_item_id_key;
create unique index if not exists recipe_lines_one_active on public.recipe_lines (recipe_id, ingredient_item_id) where active;
create table if not exists public.product_packaging (
  id bigserial primary key,
  product_item_id uuid not null references public.items(id),
  packaging_item_id uuid not null references public.items(id),
  qty_per_unit numeric not null check (qty_per_unit > 0 and qty_per_unit < 1000000),     -- packaging base units per ONE base unit of the product
  applies_to text not null default 'sale' check (applies_to in ('sale', 'production')),
  active boolean not null default true,
  note text,
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (product_item_id, packaging_item_id, applies_to)
);
create table if not exists public.production_runs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  recipe_id uuid not null references public.recipes(id),
  item_id uuid not null references public.items(id),
  batches numeric not null check (batches > 0),
  made_at timestamptz not null,
  yield_base numeric not null,
  ledger_in_id bigint, batch_id bigint,
  waste_missing int not null default 0,
  cost_complete boolean,
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists production_runs_loc on public.production_runs (location_id, made_at);

-- ---------- helpers ----------
create or replace function public._recipe_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage'));
$$;
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._recipe_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;

-- immutability: lines and the yield of a used version never change; a used version is never removed
create or replace function public._recipe_frozen() returns trigger language plpgsql security definer set search_path = public as $$
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
  select used_at into used from public.recipes where id = rid;
  if used is not null then raise exception 'recipe_used'; end if;
  if tg_op = 'DELETE' then raise exception 'no_delete'; end if;
  if tg_op = 'UPDATE' and new.recipe_id is distinct from old.recipe_id then raise exception 'recipe_used'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_frozen on public.recipes;
create trigger recipes_frozen before update or delete on public.recipes for each row execute function public._recipe_frozen();
drop trigger if exists recipe_lines_frozen on public.recipe_lines;
create trigger recipe_lines_frozen before insert or update or delete on public.recipe_lines for each row execute function public._recipe_frozen();

drop trigger if exists audit_recipes on public.recipes;
create trigger audit_recipes after insert or update on public.recipes for each row execute function public.log_change('id');
drop trigger if exists audit_recipe_lines on public.recipe_lines;
create trigger audit_recipe_lines after insert or update or delete on public.recipe_lines for each row execute function public.log_change('id');
drop trigger if exists audit_product_packaging on public.product_packaging;
create trigger audit_product_packaging after insert or update on public.product_packaging for each row execute function public.log_change('id');
drop trigger if exists audit_production_runs on public.production_runs;
create trigger audit_production_runs after insert on public.production_runs for each row execute function public.log_change('id');

-- ---------- RLS ----------
alter table public.recipes enable row level security;
alter table public.recipe_lines enable row level security;
alter table public.product_packaging enable row level security;
alter table public.production_runs enable row level security;
drop policy if exists recipes_read on public.recipes;
create policy recipes_read on public.recipes for select to authenticated using (public._recipe_read());
drop policy if exists recipe_lines_read on public.recipe_lines;
create policy recipe_lines_read on public.recipe_lines for select to authenticated using (public._recipe_read());
drop policy if exists product_packaging_read on public.product_packaging;
create policy product_packaging_read on public.product_packaging for select to authenticated using (public._recipe_read());
drop policy if exists production_runs_read on public.production_runs;
create policy production_runs_read on public.production_runs for select to authenticated using (public._recipe_read() and public.can_loc(location_id));
revoke all on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs from anon, authenticated;
grant select on public.recipes, public.recipe_lines, public.product_packaging, public.production_runs to authenticated;
revoke all on sequence public.recipe_lines_id_seq, public.product_packaging_id_seq from anon, authenticated;

-- ---------- recipe writes ----------
create or replace function public._recipe_lines_ok(p_item uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; ing public.items; q numeric; w numeric; seen uuid[] := '{}'; iid uuid;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  for ln in select x from jsonb_array_elements(p_lines) x loop
    iid := nullif(ln->>'ingredient_item_id', '')::uuid;
    select * into ing from public.items where id = iid;
    if not found then raise exception 'item_not_found'; end if;
    if iid = p_item then raise exception 'ingredient_is_product'; end if;
    if ing.item_type not in ('raw_material', 'packaging', 'resale') then raise exception 'bad_ingredient_type' using detail = ing.code; end if;
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $$;

create or replace function public._recipe_put_lines(p_recipe uuid, p_lines jsonb) returns void language plpgsql security definer set search_path = public as $$
declare ln jsonb; n int := 0;
begin
  for ln in select x from jsonb_array_elements(p_lines) x loop
    n := n + 1;
    insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
      values (p_recipe, (ln->>'ingredient_item_id')::uuid, (ln->>'qty')::numeric, nullif(btrim(ln->>'unit'), ''), nullif(ln->>'waste_pct', '')::numeric, left(nullif(btrim(ln->>'note'), ''), 200), n);
  end loop;
end $$;

-- create a new version (p_id null) or edit a version that has never been used. p_lines = [{ingredient_item_id, qty, unit, waste_pct, note}]
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), '');
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
  else
    if p_client is not null then
      select * into r from public.recipes where client_id = p_client;
      if found then
        if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', r.id, 'version', r.version);
      end if;
    end if;
    select * into it from public.items where id = p_item;
    if not found then raise exception 'item_not_found'; end if;
  end if;
  if it.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if public._base_qty(it.id, p_yield_qty, yu) is null then raise exception 'unit_unknown' using detail = it.code; end if;
  perform public._recipe_lines_ok(it.id, p_lines);
  if p_id is null then
    select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = it.id;
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid()) returning id into rid;
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300) where id = rid;
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  return jsonb_build_object('id', rid, 'version', v);
end $$;

-- copy a version: same item = next version (optionally retiring the source); another item = version 1 of that item
create or replace function public.recipe_copy(p_from uuid, p_item uuid default null, p_retire_old boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_client is not null then
    select * into dup from public.recipes where client_id = p_client;
    if found then
      if dup.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', dup.id, 'version', dup.version);
    end if;
  end if;
  select * into tgt from public.items where id = coalesce(p_item, s.item_id);
  if not found then raise exception 'item_not_found'; end if;
  if tgt.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if exists (select 1 from public.recipe_lines where recipe_id = p_from and active and ingredient_item_id = tgt.id) then raise exception 'ingredient_is_product'; end if;
  select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = tgt.id;
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid()) returning id into rid;
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  return jsonb_build_object('id', rid, 'version', v);
end $$;

create or replace function public.recipe_set_active(p_id uuid, p_active boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  update public.recipes set active = p_active where id = p_id;
  if not found then raise exception 'recipe_not_found'; end if;
end $$;

-- packaging per product (one row per product x packaging x sale|production); inactive instead of delete
create or replace function public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text default 'sale', p_active boolean default true, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product;
  select * into pk from public.items where id = p_packaging;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $$;

-- ---------- the consumption maths (internal; used by preview, can-make and post) ----------
-- one row per thing that leaves the stock for p_batches batches: the ingredients, plus the production-time packaging when the setting says so
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc int)
returns table (item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; yb numeric;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then return; end if;
  yb := coalesce(public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 0) * p_batches;
  return query
    select z.item_id, min(z.kind), sum(z.need), max(z.on_hand), bool_and(z.tracked), bool_and(z.unit_ok), bool_or(z.waste_missing), z.code, z.name_bn, z.name_en, z.base_unit
    from (
      select i.id as item_id, 'ingredient'::text as kind,
             round(public._base_qty(i.id, l.qty, l.unit) * p_batches * (1 + coalesce(l.waste_pct, 0) / 100), 4) as need,
             coalesce(b.qty, 0) as on_hand, i.tracked, public._base_qty(i.id, l.qty, l.unit) is not null as unit_ok, l.waste_pct is null as waste_missing,
             i.code, i.name_bn, i.name_en, public._item_base(i.id) as base_unit
        from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where l.recipe_id = p_recipe and l.active
      union all
      select i.id, 'packaging'::text, round(pp.qty_per_unit * yb, 4), coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $$;

-- preview for the production sheet: what will be used, what is on hand, what is short. No costs.
create or replace function public.production_preview(p_loc int, p_recipe uuid, p_batches numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $$;

-- "what can I make now" at one location: for every active recipe (newest active version per product) how many batches the stock allows
create or replace function public.production_can_make(p_loc int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id;
    if not it.is_active then continue; end if;
    mx := null; lim := null; unk := not it.tracked;
    for n in select * from public._recipe_need(r.id, 1, p_loc) loop
      if not n.tracked or not n.unit_ok or n.need <= 0 then unk := true; continue; end if;
      per := n.on_hand / n.need;
      if mx is null or per < mx then mx := per; lim := n.item_id; end if;
    end loop;
    out := out || jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'code', it.code, 'name_bn', it.name_bn, 'name_en', it.name_en,
      'max_batches', case when mx is null then null else greatest(floor(mx * 10000) / 10000, 0) end, 'limiting_item_id', lim, 'unknown', unk,
      'yield_per_batch', public._base_qty(r.item_id, r.yield_qty, r.yield_unit), 'yield_unit', public._item_base(r.item_id));
  end loop;
  return out;
end $$;

-- cost of one batch from the average cost in stock (owner / ITEM_COST / view_cost only; unknown cost = null = Data needed)
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  for l in select x.*, i.code, i.name_bn, i.name_en from public.recipe_lines x join public.items i on i.id = x.ingredient_item_id where x.recipe_id = p_recipe and x.active order by x.sort, x.id loop
    need := round(public._base_qty(l.ingredient_item_id, l.qty, l.unit) * (1 + coalesce(l.waste_pct, 0) / 100), 4);
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = l.ingredient_item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = l.ingredient_item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null then complete := false; else total := total + need * av; end if;
    ls := ls || jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', l.code, 'need_base', need, 'unit_cost', av, 'line_cost', case when av is null then null else round(need * av, 4) end,
      'waste_missing', l.waste_pct is null);
  end loop;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete, 'batch_cost', case when complete then round(total, 4) end,
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb);
end $$;

-- ---------- production ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid;
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
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  f := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  yb := round(f * p_batches, 4);
  if not (yb between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
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
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, yb, wm, left(p_note, 200), auth.uid());
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
    derived := md5(coalesce(p_client::text, rid::text) || ':' || n.item_id::text)::uuid;
    lin := public.stock_post(n.item_id, p_loc, -n.need, 'issue_out', 'production', rid::text, null, null, at_, left(p_note, 200), null, 'full', null, derived);
    used := used || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty', n.need);
  end loop;
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is the ingredient cost when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, yb, yb, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and yb > 0 then round(tot / yb, 6) end;
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, yb, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok where id = rid;
  update public.recipes set used_at = coalesce(used_at, now()) where id = r.id;
  if wm > 0 then
    perform public._stock_exc(p_loc, 'recipe_waste_missing', 'yellow', it.name_bn || ': রেসিপিতে অপচয় % বসানো নেই — ০ ধরা হয়েছে (' || wm::text || ' লাইন)',
      coalesce(it.name_en, it.name_bn) || ': the recipe has no waste % on ' || wm::text || ' line(s) — counted as 0', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- the old direct "production in": identical to phase10 except the new switch (production_requires_recipe)
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric; ucb numeric; pct numeric; av numeric;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if public.rule_on('production_requires_recipe') then raise exception 'recipe_required'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  pct := public.rule_num('purchase_cost_jump_pct');
  if p_unit_cost is not null and pct is not null then
    ucb := p_unit_cost / f;
    select avg_cost into av from public.stock_balance where item_id = p_item and location_id = p_loc;
    if av is not null and av > 0 and abs(ucb - av) / av * 100 > pct then
      perform public._stock_exc(p_loc, 'production_cost_jump', 'yellow',
        it.name_bn || ': উৎপাদন খরচ গড় খরচের চেয়ে ' || round((ucb - av) / av * 100, 1)::text || '% বদলেছে',
        coalesce(it.name_en, it.name_bn) || ': production cost moved ' || round((ucb - av) / av * 100, 1)::text || '% from the average cost in stock', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
    end if;
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- packaging with a sale (separate trigger; the stock trigger and record_sale2 are untouched) ----------
create or replace function public._sale_packaging_out() returns trigger language plpgsql security definer set search_path = public as $$
declare pk record; bad boolean := false;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  if coalesce(public.rule_txt('packaging_consume_on'), 'off') <> 'sale' then return new; end if;
  begin
    for pk in
      select pp.packaging_item_id as item_id, sum(public._base_qty(li.iid, li.q, li.u) * pp.qty_per_unit) as qty, count(*) filter (where public._base_qty(li.iid, li.q, li.u) is null) as unk,
             i.code, i.name_bn, i.name_en
        from (select (x->>'item_id')::uuid as iid, nullif(x->>'qty', '')::numeric as q, x->>'unit' as u from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null) li
        join public.product_packaging pp on pp.product_item_id = li.iid and pp.active and pp.applies_to = 'sale'
        join public.items i on i.id = pp.packaging_item_id
       where li.q > 0 and li.q <= 999999999
       group by pp.packaging_item_id, i.code, i.name_bn, i.name_en order by pp.packaging_item_id loop
      if pk.unk > 0 then bad := true; end if;
      begin
        if pk.qty is null or round(pk.qty, 4) < 0.0001 then continue; end if;
        perform public.stock_post(pk.item_id, new.location_id, -round(pk.qty, 4), 'issue_out', 'sale_pack', new.id::text, null, null, new.sold_at, null, null, 'soft', new.id);
      exception when others then
        bad := true;
        perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': ' || coalesce(pk.name_bn, '') || ' — প্যাকেজিং স্টক থেকে কমানো যায়নি',
          'Receipt ' || new.receipt || ': ' || coalesce(pk.name_en, pk.name_bn, '') || ' — the packaging could not be taken out of the stock', new.id, new.sale_date, 'POS');
      end;
    end loop;
  exception when others then
    bad := true;
  end;
  if bad then
    perform public._stock_exc(new.location_id, 'packaging_not_consumed', 'yellow', 'রসিদ ' || new.receipt || ': প্যাকেজিং পুরোটা কমানো যায়নি', 'Receipt ' || new.receipt || ': the packaging could not be fully taken out of the stock', new.id, new.sale_date, 'POS');
  end if;
  return new;
end $$;
drop trigger if exists sales_packaging_out on public.sales;
create trigger sales_packaging_out after insert on public.sales for each row execute function public._sale_packaging_out();

create or replace function public._sale_packaging_void() returns trigger language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale_pack' and o.ref_id = new.id::text and o.reason = 'issue_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale_pack', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_packaging_void on public.sales;
create trigger sales_packaging_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_packaging_void();

-- ---------- privileges ----------
revoke all on function public._recipe_mgr(), public._recipe_read(), public._recipe_cost_ok(), public._recipe_frozen(), public._recipe_lines_ok(uuid, jsonb), public._recipe_put_lines(uuid, jsonb),
  public._recipe_need(uuid, numeric, int), public._sale_packaging_out(), public._sale_packaging_void() from public, anon, authenticated;
revoke all on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.recipe_save(uuid, uuid, numeric, text, text, jsonb, uuid, boolean), public.recipe_copy(uuid, uuid, boolean, uuid), public.recipe_set_active(uuid, boolean),
  public.packaging_set(uuid, uuid, numeric, text, boolean, text), public.production_preview(int, uuid, numeric), public.production_can_make(int), public.recipe_cost(uuid, int),
  public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;
-- the read policies call this helper as the signed-in person
grant execute on function public._recipe_read() to authenticated;
-- cost_complete is a cost fact: not readable by people who may not see costs
revoke select on public.production_runs from authenticated;
grant select (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, ledger_in_id, batch_id, waste_missing, note, created_by, created_at) on public.production_runs to authenticated;

-- ---------------------------------------------------------------- phase20.sql
-- ============================================================
-- Phase 20: FORMS <-> STOCK LEDGER LINKS, discount approver on sales, brand-level P&L.
--   Additive and safe to run twice; paste the whole file into the Supabase SQL editor.  Needs phase8..phase17 (phase18 / 19 are not required).
--   (1) rule forms_post_to_ledger (default OFF) + per-form switches forms_ledger_cfg(form_code, is_on).
--       When an entry of 04-1 GRN / 04-2 issue / 04-3 count / 03-1 transfer / 05-1 factory sheet is APPROVED, an AFTER UPDATE trigger on entries
--       calls entry_post_ledger(entry), which posts into the existing stock ledger through stock_post.  decide_entry is NOT edited.
--       - one log row per form line in entry_ledger_posts (entry, generation, line): the same approval twice posts nothing twice;
--       - reopen + re-approve (or an approved change request) with different content: reverse the earlier generation (reversal rows) and post the new one;
--       - lines whose item is not tracked / not counted in the business, held / returned GRN lines, lines without a quantity: skipped, yellow exception ledger_skip;
--       - any failure (unknown item, not enough stock, unknown unit ...): yellow exception ledger_post_failed with the reason, approval is never blocked;
--         entry_post_ledger_retry(entry) posts the failed lines again (and also posts an entry approved while the switch was off).
--   (2) the 04-4 store ledger and 06-5 supplier ledger need no new data: they become read views over stock_ledger_rows / supplier_ledger (web).
--   (3) sales.discount_approved_by / _staff / discount_approval: filled by a BEFORE INSERT trigger from the approval that record_sale2 used
--       (a granted role = the seller, an emergency approval = the person who approved the request).  record_sale2 is NOT edited.  RPC discounts_report.
--   (4) brand_pnl(from, to): the existing gross-profit figures (biz_daily) grouped by brand through report_brand_map. Costs only for cost-grant holders.
-- ============================================================

-- ---------- (1) switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('forms_post_to_ledger', 'stock', 'switch', 'false', null, null, null, null,
  'ফর্ম অনুমোদন হলে স্টক লেজারে নিজে থেকে পোস্ট', 'Form approve হলে stock ledger এ নিজে পোস্ট', 'Approved forms post to the stock ledger',
  'চালু করলে GRN, ইস্যু স্লিপ, কাউন্ট শিট, ট্রান্সফার চালান ও কারখানা শিট অনুমোদনের সময় স্টক লেজারে লাইন যোগ করে। বন্ধ থাকলে কিছুই বদলায় না।',
  null,
  'When on, an approved GRN, issue slip, count sheet, transfer challan or factory sheet adds its lines to the stock ledger. Off = nothing changes (default). Each form also has its own switch.', 71)
on conflict (key) do nothing;

create table if not exists public.forms_ledger_cfg (
  form_code text primary key references public.forms(code),
  is_on boolean not null default true,                     -- the master rule forms_post_to_ledger must be on as well
  changed_by uuid, changed_at timestamptz not null default now()
);
alter table public.forms_ledger_cfg enable row level security;
revoke all on public.forms_ledger_cfg from public, anon, authenticated;
grant select on public.forms_ledger_cfg to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'forms_ledger_cfg' and policyname = 'forms_ledger_cfg_read') then
    create policy forms_ledger_cfg_read on public.forms_ledger_cfg for select to authenticated using (public.is_active());
  end if;
end $$;
insert into public.forms_ledger_cfg (form_code) select code from public.forms where code in ('04-1', '04-2', '04-3', '03-1', '05-1') on conflict do nothing;

create table if not exists public.entry_ledger_posts (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  gen int not null check (gen >= 1),                        -- a new generation when the approved content changed (the old one is reversed)
  line_no int not null,                                     -- 1-based line of the form table; 0 = the form as a whole
  form_code text not null,
  location_id int not null references public.locations(id), -- the entry's place
  to_location_id int references public.locations(id),
  kind text not null check (kind in ('in', 'out', 'count', 'transfer', 'prod', 'none')),
  item_id uuid references public.items(id),
  item_code text,
  qty_base numeric,                                         -- base unit; for a count the counted quantity
  sig text not null,                                        -- fingerprint of all lines of this generation
  status text not null check (status in ('posted', 'skipped', 'failed', 'reversed', 'void')),
  reason text,                                              -- why skipped / failed / the short note of a post
  ref text,                                                 -- entry:gen:line, written to stock_ledger.ref_id (ref_type 'entry')
  transfer_id uuid,
  posted_by uuid, posted_at timestamptz not null default now(), reversed_at timestamptz,
  unique (entry_id, gen, line_no)
);
create index if not exists entry_ledger_posts_entry on public.entry_ledger_posts (entry_id, gen);
create index if not exists entry_ledger_posts_bad on public.entry_ledger_posts (status) where status in ('failed', 'skipped');
alter table public.entry_ledger_posts enable row level security;
revoke all on public.entry_ledger_posts from public, anon, authenticated;
grant select on public.entry_ledger_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'entry_ledger_posts' and policyname = 'entry_ledger_posts_read') then
    create policy entry_ledger_posts_read on public.entry_ledger_posts for select to authenticated using (public.is_active() and (public.is_owner() or public.can_loc(location_id)));
  end if;
end $$;

-- ---------- small helpers ----------
create or replace function public._elp_num(p text) returns numeric
language sql immutable as $$ select case when btrim(p) ~ '^-?[0-9]+(\.[0-9]+)?$' then btrim(p)::numeric end $$;
create or replace function public._elp_flag(p text) returns boolean
language sql immutable as $$ select coalesce(lower(btrim(p)) in ('true', 't', '1', 'yes', 'on'), false) $$;
create or replace function public._elp_loc(p text) returns int
language sql stable security definer set search_path = public as $$
  select l.id from public.locations l where btrim(p) ~ '^[0-9]{1,9}$' and l.id = btrim(p)::int;
$$;
create or replace function public._elp_enabled(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-2', '04-3', '03-1', '05-1') and public.rule_on('forms_post_to_ledger')
         and coalesce((select c.is_on from public.forms_ledger_cfg c where c.form_code = p_form), true);
$$;

-- ---------- the form -> ledger lines map (what each form means for the ledger; nothing is guessed) ----------
-- one jsonb object per non-empty row: {n, kind, item, qty, cost, from, to, recv, skip, note}.  qty / cost are in the item's own unit as written on the form.
create or replace function public._elp_lines(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb := '[]'::jsonb; r jsonb; n int; tab text; arr jsonb; q text; cr jsonb; kept boolean; note text; nrate numeric;
begin
  note := left(e.form_code || '-' || e.serial::text || coalesce(' ' || nullif(btrim(e.data->>'supplier'), ''), ''), 120);
  if e.form_code = '04-1' then
    nrate := public._elp_num(e.data->>'new_rate');
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'counted'), '')) is null;
      q := coalesce(r->>'quality', 'accept');
      out := out || jsonb_build_object('n', n, 'kind', 'in', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'counted'),
        'cost', case when q = 'reduced' and nrate is not null then nrate else public._elp_num(r->>'rate') end,
        'skip', case when q = 'hold' then 'quality_hold' when q = 'return' then 'quality_return' end, 'note', note);
    end loop;
  elsif e.form_code = '04-2' then
    kept := not public._elp_flag(e.data->>'not_overnight');       -- the form's own rule: kept overnight = the whole quantity counts as used
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'issued'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'out', 'item', nullif(btrim(r->>'item'), ''),
        'qty', public._elp_num(r->>'issued') - case when kept then 0 else coalesce(public._elp_num(r->>'ret'), 0) end, 'note', note || ' ' || coalesce(e.data->>'purpose', ''));
    end loop;
  elsif e.form_code = '04-3' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'rows') = 'array' then e.data->'rows' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'count'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'count', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'count'), 'book', public._elp_num(r->>'book'),
        'skip', case when public._elp_num(r->>'book') is null then 'no_count_basis' end,
        'note', left(note || ' ' || coalesce(nullif(btrim(r->>'reason'), ''), 'stock count'), 190));
    end loop;
  elsif e.form_code = '03-1' then
    cr := case when jsonb_typeof(e.check_data->'items') = 'array' then e.check_data->'items' else '[]'::jsonb end;
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'items') = 'array' then e.data->'items' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'sent'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'transfer', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'sent'),
        'from', public._elp_loc(e.data->>'from_loc'), 'to', public._elp_loc(e.data->>'to_loc'),
        'recv', public._elp_num(cr->(n - 1)->>'received'), 'note', note);
    end loop;
  elsif e.form_code = '05-1' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data->'output') = 'array' then e.data->'output' else '[]'::jsonb end) with ordinality x(v, o) loop
      continue when coalesce(nullif(btrim(r->>'item'), ''), nullif(btrim(r->>'qty'), '')) is null;
      out := out || jsonb_build_object('n', n, 'kind', 'prod', 'item', nullif(btrim(r->>'item'), ''), 'qty', public._elp_num(r->>'qty'), 'note', note);
    end loop;
  end if;
  if jsonb_array_length(out) = 0 then
    out := jsonb_build_array(jsonb_build_object('n', 0, 'kind', 'none', 'skip', 'no_item_lines', 'note', note));
  end if;
  return out;
end $$;

-- ---------- post ONE line (runs inside a sub-transaction of entry_post_ledger: an error here undoes only this line) ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item';
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
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
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, null, bid, at_, left(note, 200), null, 'none');
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
end $$;

-- ---------- undo one generation (reversal rows; nothing is deleted) ----------
create or replace function public._elp_reverse(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare p public.entry_ledger_posts; o public.stock_ledger;
begin
  for p in select * from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'posted' order by line_no desc loop
    for o in select x.* from public.stock_ledger x where x.reason <> 'reversal'
             and ((p.transfer_id is not null and x.ref_type = 'transfer' and x.ref_id = p.transfer_id::text) or (p.transfer_id is null and x.ref_type = 'entry' and x.ref_id = p.ref))
             and not exists (select 1 from public.stock_ledger y where y.reverses_id = x.id) order by x.id desc loop
      perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', o.ref_type, o.ref_id, o.unit_cost, o.batch_id, now(), 'entry revised: earlier posting undone', o.id, 'none');
    end loop;
    if p.transfer_id is not null then update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now() where id = p.transfer_id; end if;
    update public.entry_ledger_posts set status = 'reversed', reversed_at = now() where id = p.id;
  end loop;
  update public.entry_ledger_posts set status = 'void' where entry_id = e.id and gen = g and status in ('failed', 'skipped');
end $$;

create or replace function public._elp_exceptions(e public.entries, g int) returns void
language plpgsql security definer set search_path = public as $$
declare sk text; fl text; nsk int; nfl int;
begin
  delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in ('ledger_skip', 'ledger_post_failed');
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ' ' || coalesce(reason, ''), '; ' order by line_no) into nsk, sk
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'skipped';
  select count(*), string_agg('#' || line_no::text || ' ' || coalesce(item_code, '-') || ': ' || coalesce(reason, ''), '; ' order by line_no) into nfl, fl
    from public.entry_ledger_posts where entry_id = e.id and gen = g and status = 'failed';
  if nsk > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_skip', 'yellow', nsk,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nsk || ' লাইন স্টক লেজারে যায়নি — ' || left(sk, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nsk || ' line(s) were not posted to the stock ledger — ' || left(sk, 300)));
  end if;
  if nfl > 0 then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', nfl,
        jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || nfl || ' লাইন স্টক লেজারে পোস্ট হয়নি (আবার চেষ্টা করা যাবে) — ' || left(fl, 300),
                           'en', e.form_code || '-' || e.serial || ': ' || nfl || ' line(s) could not be posted to the stock ledger (retry is possible) — ' || left(fl, 300)));
  end if;
end $$;

-- ---------- the poster: idempotent. Same content = nothing new; changed content = reverse the old generation and post the new one ----------
create or replace function public.entry_post_ledger(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; lines jsonb; sg text; g int; cur text; l jsonb; n int; nposted int := 0; nfail int := 0; nskip int := 0; msg text; sid text;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.status <> 'approved' then return jsonb_build_object('ok', false, 'why', 'not_approved'); end if;
  if not public._elp_enabled(e.form_code) then return jsonb_build_object('ok', true, 'enabled', false); end if;
  lines := public._elp_lines(e); sg := md5(lines::text);
  select max(gen) into g from public.entry_ledger_posts where entry_id = e.id;
  if g is null then g := 1;
  else
    select sig into cur from public.entry_ledger_posts where entry_id = e.id and gen = g limit 1;
    if cur is distinct from sg then
      begin
        perform public._elp_reverse(e, g);
        g := g + 1;
      exception when others then
        msg := sqlerrm;
        delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code = 'ledger_post_failed';
        insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
          values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', null,
            jsonb_build_object('bn', e.form_code || '-' || e.serial || ': সংশোধিত ফর্মের আগের লেজার পোস্টিং ফেরানো যায়নি — ' || left(msg, 200),
                               'en', e.form_code || '-' || e.serial || ': the earlier ledger posting of the revised form could not be undone — ' || left(msg, 200)));
        return jsonb_build_object('ok', false, 'why', 'reverse_failed', 'error', msg);
      end;
    end if;
  end if;
  for l in select * from jsonb_array_elements(lines) loop
    n := (l->>'n')::int;
    if exists (select 1 from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status in ('posted', 'skipped')) then continue; end if;
    delete from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status = 'failed';
    begin
      perform public._elp_post_line(e, g, sg, l);
    exception when others then
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_code, qty_base, sig, status, reason, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, nullif(l->>'to', '')::int, coalesce(l->>'kind', 'none'), left(l->>'item', 60), null, sg, 'failed', left(sqlerrm, 200), auth.uid());
    end;
  end loop;
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $$;
revoke all on function public.entry_post_ledger(uuid), public._elp_post_line(public.entries, int, text, jsonb), public._elp_reverse(public.entries, int),
  public._elp_exceptions(public.entries, int), public._elp_lines(public.entries) from public, anon, authenticated;

-- the trigger: never blocks the approval (a failure of the whole poster becomes one exception)
create or replace function public._entries_post_ledger() returns trigger
language plpgsql security definer set search_path = public as $$
declare msg text;
begin
  if not public._elp_enabled(new.form_code) then return null; end if;
  begin
    perform public.entry_post_ledger(new.id);
  exception when others then
    msg := sqlerrm;
    begin
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (new.id, new.form_code, new.location_id, new.entry_date, 'ledger_post_failed', 'yellow', null,
          jsonb_build_object('bn', new.form_code || '-' || new.serial || ': স্টক লেজারে পোস্ট হয়নি — ' || left(msg, 200),
                             'en', new.form_code || '-' || new.serial || ': could not post to the stock ledger — ' || left(msg, 200)));
    exception when others then null;
    end;
  end;
  return null;
end $$;
revoke all on function public._entries_post_ledger() from public, anon, authenticated;
drop trigger if exists entries_post_ledger on public.entries;
create trigger entries_post_ledger after update on public.entries for each row
  when (new.status = 'approved' and (old.status is distinct from 'approved' or old.data is distinct from new.data or old.check_data is distinct from new.check_data))
  execute function public._entries_post_ledger();

-- ---------- public RPCs ----------
create or replace function public._elp_may(p_entry uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (select 1 from public.entries e where e.id = p_entry
    and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve'))));
$$;
revoke all on function public._elp_may(uuid) from public, anon, authenticated;

create or replace function public.entry_post_ledger_retry(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._elp_may(p_entry) then raise exception 'not allowed'; end if;
  return public.entry_post_ledger(p_entry);
end $$;

-- lines of one entry (what went to the ledger); no costs
create or replace function public.entry_ledger_lines(p_entry uuid)
returns table (gen int, line_no int, kind text, item_code text, qty_base numeric, status text, reason text, posted_at timestamptz, reversed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and exists (select 1 from public.entries e where e.id = p_entry and (public.is_owner() or public.can_loc(e.location_id)))) then raise exception 'not allowed'; end if;
  return query select x.gen, x.line_no, x.kind, x.item_code, x.qty_base, x.status, x.reason, x.posted_at, x.reversed_at from public.entry_ledger_posts x where x.entry_id = p_entry order by x.gen, x.line_no;
end $$;

-- approved entries whose latest generation has failed lines (the retry list)
create or replace function public.ledger_post_problems(p_loc int default null)
returns table (entry_id uuid, form_code text, serial int, location_id int, entry_date date, failed int, skipped int, first_reason text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    with cur as (select x.entry_id, max(x.gen) g from public.entry_ledger_posts x group by 1)
    select e.id, e.form_code, e.serial, e.location_id, e.entry_date,
           (count(*) filter (where x.status = 'failed'))::int, (count(*) filter (where x.status = 'skipped'))::int,
           min(x.reason) filter (where x.status = 'failed')
    from cur join public.entry_ledger_posts x on x.entry_id = cur.entry_id and x.gen = cur.g
    join public.entries e on e.id = x.entry_id
    where (p_loc is null or e.location_id = p_loc) and (public.is_owner() or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
    group by e.id, e.form_code, e.serial, e.location_id, e.entry_date
    having count(*) filter (where x.status in ('failed', 'skipped')) > 0
    order by e.entry_date desc, e.serial desc limit 200;
end $$;

-- owner: per-form switch
create or replace function public.forms_ledger_cfg_set(p_form text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('04-1', '04-2', '04-3', '03-1', '05-1') or p_on is null then raise exception 'bad_form'; end if;
  insert into public.forms_ledger_cfg (form_code, is_on, changed_by, changed_at) values (p_form, p_on, auth.uid(), now())
    on conflict (form_code) do update set is_on = excluded.is_on, changed_by = auth.uid(), changed_at = now();
  return jsonb_build_object('form_code', p_form, 'is_on', p_on);
end $$;

-- ---------- (3) discount approver on sales ----------
alter table public.sales add column if not exists discount_approved_by uuid;
alter table public.sales add column if not exists discount_approved_staff text;
alter table public.sales add column if not exists discount_approval text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'sales_discount_approval_chk') then
    alter table public.sales add constraint sales_discount_approval_chk check (discount_approval is null or discount_approval in ('grant', 'emergency'));
  end if;
end $$;

-- record_sale2 asks rule_ok('discount_over_limit', ...) BEFORE the insert: a granted role passes can_grant (= the seller holds the right), otherwise the one-use / window
-- emergency approval is consumed and use_emergency leaves 'id:grant' in the transaction setting bos.em_used.  The trigger reads exactly that.
create or replace function public._sales_discount_approver() returns trigger
language plpgsql security definer set search_path = public as $$
declare em text; rid bigint; r public.emergency_requests; lim jsonb;
begin
  if coalesce(new.discount, 0) <= 0 or new.discount_approved_by is not null then return new; end if;
  em := current_setting('bos.em_used', true);
  if em is not null and em ~ ':discount_over_limit' then
    select (x.m)[1]::bigint into rid from regexp_matches(em, '([0-9]+):discount_over_limit', 'g') as x(m) order by (x.m)[1]::bigint desc limit 1;
    select * into r from public.emergency_requests where id = rid;
    if found and r.decided_by is not null then
      new.discount_approved_by := r.decided_by; new.discount_approved_staff := r.decided_staff; new.discount_approval := 'emergency'; return new;
    end if;
  end if;
  select value into lim from public.location_settings where location_id = new.location_id and key = 'discount_limit';
  if public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or new.discount > (lim #>> '{}')::numeric) and public.can_grant('discount_over_limit') then
    new.discount_approved_by := new.created_by;
    select staff_id into new.discount_approved_staff from public.profiles where id = new.created_by;
    new.discount_approval := 'grant';
  end if;
  return new;
end $$;
revoke all on function public._sales_discount_approver() from public, anon, authenticated;
drop trigger if exists sales_discount_approver on public.sales;
create trigger sales_discount_approver before insert on public.sales for each row execute function public._sales_discount_approver();

create or replace function public.discounts_report(p_from date, p_to date, p_loc int default null, p_only_approved boolean default false)
returns table (sale_id uuid, location_id int, receipt int, sale_date date, status text, subtotal numeric, discount numeric, discount_kind text, discount_input numeric, total numeric,
               seller_staff text, approver_staff text, approval text, over_limit boolean, customer text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
    select s.id, s.location_id, s.receipt, s.sale_date, s.status, s.subtotal, s.discount, s.discount_kind, s.discount_input, s.total, s.created_staff,
           s.discount_approved_staff, s.discount_approval,
           (s.discount_approval is not null), s.customer
    from public.sales s
    where s.sale_date between p_from and p_to and s.discount > 0 and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
      and (not coalesce(p_only_approved, false) or s.discount_approval is not null)
    order by s.sale_date desc, s.location_id, s.receipt desc limit 2000;
end $$;

-- ---------- (4) brand-level P&L ----------
-- The existing gross-profit figures (biz_daily: revenue, discount, voids, costed revenue, cost of goods) grouped by brand.  A location that is not in report_brand_map is
-- shown as 'unmapped' (nothing is guessed).  Cost / gross profit are NULL for callers without a cost right (biz_daily already blanks them).  Combined = the sum of the rows (web).
create or replace function public.brand_pnl(p_from date, p_to date, p_brand text default null)
returns table (brand_code text, brand_bn text, brand_en text, locations int, n bigint, revenue numeric, discount numeric, void_n bigint, void_amt numeric,
               costed_rev numeric, cogs numeric, gross_profit numeric, gp_pct numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  return query
    with d as (select x.* from public.biz_daily(p_from, p_to, null) x),
    m as (select d.*, coalesce(b.brand_code, 'unmapped') bc, b.brand_bn bbn, b.brand_en ben from d left join public.report_brand_map b on b.location_id = d.location_id)
    select m.bc, coalesce(max(m.bbn), 'ব্র্যান্ড ঠিক করা নেই'), coalesce(max(m.ben), 'Not mapped to a brand'), (count(distinct m.location_id))::int,
           sum(m.n)::bigint, sum(m.revenue), sum(m.discount), sum(m.void_n)::bigint, sum(m.void_amt),
           sum(m.costed_rev), sum(m.cogs),
           case when public.biz_cost_ok() then sum(m.costed_rev) - sum(m.cogs) end,
           case when public.biz_cost_ok() and sum(m.costed_rev) > 0 then round((sum(m.costed_rev) - sum(m.cogs)) / sum(m.costed_rev) * 100, 2) end
    from m where p_brand is null or m.bc = p_brand
    group by m.bc order by sum(m.revenue) desc nulls last;
end $$;

-- ---------- grants ----------
revoke all on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) from public, anon;
grant execute on function public.entry_post_ledger_retry(uuid), public.entry_ledger_lines(uuid), public.ledger_post_problems(int), public.forms_ledger_cfg_set(text, boolean),
  public.discounts_report(date, date, int, boolean), public.brand_pnl(date, date, text) to authenticated;
revoke all on function public._elp_num(text), public._elp_flag(text), public._elp_loc(text), public._elp_enabled(text), public._sales_discount_approver() from public, anon, authenticated;

-- ============================================================================
-- End of FRESH part 2 of 21.
