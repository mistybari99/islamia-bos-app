-- Phase 546 - stock_transfer carries ALL four switch behaviours again (fix). Paste AFTER phase545 (and after 544). Paste-twice safe (create or replace). Earlier phase files are not edited.
-- Why: phase 544 re-created stock_transfer "as phase 499" plus the reused-id check. That text did not contain the two blocks that phase 114 (bos114:xfer-stock) and
--   phase 115 (bos115:xfer-notify) had added and that phase 533 (UNION-5) had put back together with phase 499. A normal paste order (544 after 533) therefore ended with the weaker function:
--     (1) rule transfer_needs_stock (bos114): "a transfer needs stock" check with the balance row locked, refused with insufficient_stock (detail = item, hint = on hand),
--         unless the sender holds sell_below_zero or an emergency use of it;
--     (2) rule transfer_notify_receiver (bos115): a transfer_sent notice for the managers of the receiving place.
--   Found by the owner's read-only audit; confirmed on a local throwaway database built from the full chain (see docs/BUILD-LOG.md).
-- What: ONE function, stock_transfer(integer,integer,uuid,numeric,text,text,uuid), re-created = the phase 544 text (client-id reuse switch, phase 499 over-send and paused destination)
--   + the bos114 stock check + the bos115 receiver notice, both exactly as phase 533 has them (same position, same text, tags bos114:xfer-stock and bos115:xfer-notify kept).
-- No new rule, table, column, privilege or data. All four switches stay OFF by default (transfer_client_reuse_block, transfer_overdraw_block, transfer_paused_block are phase 544/499;
--   transfer_needs_stock is phase 114; transfer_notify_receiver is phase 115). With every switch OFF the function behaves exactly as the phase 544 function did.
-- Test: supabase/phase546_test.sql.

create or replace function public.stock_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then
      if public.rule_on('transfer_client_reuse_block') and t.sent_by is distinct from auth.uid() then raise exception 'client_id_reused'; end if;
      return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status);
    end if;
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
    if found then
      if public.rule_on('transfer_client_reuse_block') and t.sent_by is distinct from auth.uid() then raise exception 'client_id_reused'; end if;
      return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status);
    end if;
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
end $function$;
