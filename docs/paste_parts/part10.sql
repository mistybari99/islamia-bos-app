-- ============================================================================
-- FRESH part 10 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase105 phase106 phase107 phase108 phase109 phase110 phase111 phase112 phase113 phase114 phase115 phase116
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase105.sql
-- ============================================================
-- Phase 105 (bos105) - STEP Sec2: fixes of the second security review (docs/briefs_p2p3/step_Sec2_REPORT.md). Goes LAST (phase104 is reserved for the dashboard step and is NOT needed).
--   Needs phases 72..103 pasted first (guard below, incl. the phase103 advisor row flw_grn_double103). Additive, paste-twice safe: every function is re-created from its LATEST body,
--   only lines tagged bos105 differ, every older bosNN tag is kept (a body guard refuses to overwrite a body that carries a tag this file does not know).
--   Defaults: everything keeps today's behaviour. Pure bug fixes are on at once; the only new switch (customers_pii_guard_on) is OFF.
--   H1  customer phone / address bypass paths. customer_dues, customer_advances, customer_profile (the "customer card") now follow inbox_pii_mode through _cust_pii103, exactly like
--       customer_directory / find_customer (owner and view_customer_mobile holders see everything; inbox_pii_mode = off changes nothing). The online_orders column guard
--       (inbox_pii_guard_on) now also hides note, draft_note and lines. New opt-in switch customers_pii_guard_on (OFF): the browser may then not read customers.mobile / whatsapp /
--       address / note with a plain table read (screens that do so must move to the RPCs first - see the report). customer_save ignores a masked value (it holds the mask dot) so a masked
--       screen value is never saved over the real one.
--   M1  inbox_unmask: the daily limit is counted under an advisory lock (parallel calls can no longer all pass).
--   M2  automatic bill payment honours bill_pay_large_amount and (purchase bills) the supplier_pay grant of the person who posts; otherwise it is skipped with the yellow flag
--       bill_pay_auto_skipped and the bill waits for a payment.
--   M3  keep_credit trigger: a direct void of a bill-linked payment is refused with void_the_bill instead of being dropped silently (the bill void keeps working as before).
--   M6  phone number typed in free text: separators space, tab, no-break space, ( ) . - / _ (1..3 of them) are followed; dates such as 14/10/2026 are left alone.
--   L3  automatic payment client id: md5 of kind + ref + a private random salt (bos_salt105, closed table). L4 a known client id of another bill raises client_id_reused.
--   L5  blocked unmask attempts: at most one log line per person per minute. L6 customer_directory name follows mask_all_pii (first letter + dots); the one changed line there is marked
--       sec2-L6 (not bos105) so that phase103's body guard still accepts the function: after a re-paste of phase515 / 520 / 522 / 523 / 524 paste phase103 and then phase105 again.
--   Tag: bos105.
-- ============================================================

do $g$ begin perform set_config('phase105.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._bp_auto99(text,text,integer,text,text,text,integer,text)'), ('99', 'public.inbox_unmask(text,text,text)'),
    ('103', 'public._cust_pii103(text,text)'), ('103', 'public._inb_mask_phones103(text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_check_defs81') is null or not exists (select 1 from public.setup_check_defs81 where code = 'flw_grn_double103') then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase105 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase105.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase105.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._bp_uuid99(text,text)', array['bos99', 'bos105']::text[]),                       -- 'bos99' = the text of the literal 'bos99auto:'
    ('public._bp_auto99(text,text,integer,text,text,text,integer,text)', array['bos105']::text[]),
    ('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)', array['bos105', 'bos109', 'bos111']::text[]),   -- (INT4) bos109 / bos111 = a re-paste of this file on the final database: that merged body is left alone (see the skip before the create below)
    ('public._bp_sp_void99()', array['bos105']::text[]),
    ('public.inbox_unmask(text,text,text)', array['bos105']::text[]),
    ('public._inb_mask_phones103(text)', array['bos105']::text[]),
    ('public._cust_pii103(text,text)', array['bos105']::text[]),
    ('public.customer_dues()', array['bos105']::text[]),
    ('public.customer_advances()', array['bos105']::text[]),
    ('public.customer_profile(uuid)', array['bos105']::text[]),
    ('public.customer_directory(integer)', array['bos103']::text[]),                         -- carries the marker sec2-L6 instead of a bosNN tag: phase103's own body guard must still accept it (a re-paste of 103 is followed by 105)
    ('public.customer_save(uuid,jsonb,uuid)', array['bos105']::text[]),
    ('public._inb_pii_cols76()', array['bos105']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase105: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase105.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- L3: the automatic-payment client id is no longer a guessable md5 of kind+ref (a private random salt, kept in a closed table) ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
  create table if not exists public.bos_salt105 (k text primary key, v text not null);
  alter table public.bos_salt105 enable row level security;
  revoke all on public.bos_salt105 from public, anon, authenticated;
  insert into public.bos_salt105 (k, v) values ('auto99', gen_random_uuid()::text || gen_random_uuid()::text) on conflict (k) do nothing;
end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._bp_uuid99(p_kind text, p_ref text) returns uuid language sql stable security definer set search_path = public as $$
  select md5('bos99auto:' || p_kind || ':' || p_ref || ':' || (select v from public.bos_salt105 where k = 'auto99'))::uuid   -- bos105 (L3): unguessable, still one fixed id per bill
$$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._bp_auto_ok105(p_kind text, p_ref text, p_loc int) returns text
language plpgsql stable security definer set search_path = public as $$
-- bos105 (M2): an automatic payment keeps the limits a person would meet: the owner-typed large-bill limit, and (purchase) the poster must hold supplier_pay. NULL = go ahead, else the reason.
declare lim numeric := public.rule_num('bill_pay_large_amount'); amt numeric;
begin
  if p_kind = 'cost' then select b.amount into amt from public.cost_source_bills b where b.id = p_ref::bigint;
  else select b.total - b.paid into amt from public.purchase_bills b where b.id = p_ref::uuid; end if;
  if lim is not null and amt is not null and amt >= lim then return 'large_bill'; end if;
  if p_kind = 'purchase' and not (public.is_owner() or public.has_grant('supplier_pay', p_loc)) then return 'no_supplier_pay'; end if;
  return null;
end $$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_auto99(p_kind text, p_ref text, p_loc integer, p_party_kind text, p_party_id text, p_rule text, p_credit_days integer, p_bill_mode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mode_ text := coalesce(public.rule_txt(p_rule), 'off'); d public.bill_pay_defaults99; pm text; credit boolean; r jsonb; why text; frm text := case when p_kind = 'cost' then 'STOCK' else 'PURCHASE' end;
begin
  if mode_ not in ('auto_cash', 'auto_bank', 'auto_by_supplier_default') then return; end if;
  begin                                                   -- nothing in here may stop the bill itself from being saved / posted
    select * into d from public.bill_pay_defaults99 where party_kind = p_party_kind and party_id = p_party_id;
    credit := coalesce(d.credit_terms, false) or coalesce(p_credit_days, 0) > 0;
    if credit and not public.rule_on('bill_pay_auto_credit_ok') then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'credit-শর্তের পক্ষ: স্বয়ংক্রিয় payment হয়নি, bill payment-এর অপেক্ষায়', 'Party has credit terms: no automatic payment made; the bill waits for a payment', null, null, frm, null);
      return;
    end if;
    why := public._bp_auto_ok105(p_kind, p_ref, p_loc);   -- bos105 (M2)
    if why is not null then   -- bos105
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি (' || why || '): বড় bill বা payment-এর অনুমতি নেই', 'Automatic payment skipped (' || why || '): a large bill, or the person has no payment right', null, null, frm, null);   -- bos105
      return;   -- bos105
    end if;   -- bos105
    pm := case mode_ when 'auto_cash' then 'cash' when 'auto_bank' then 'bank'
            else coalesce(d.pay_mode, case when p_bill_mode in ('cash', 'bank', 'mobile') then p_bill_mode end) end;
    if pm is null then return; end if;                    -- by_supplier_default with no default known = behaves like "ask" (the list offers it)
    r := public._bp_pay99(p_kind, p_ref, pm, null, 'auto', public._bp_uuid99(p_kind, p_ref), 'automatic (rule ' || p_rule || ')', false);
    if not coalesce((r->>'ok')::boolean, false) then
      perform public._stock_exc(p_loc, 'bill_pay_auto_skipped', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: একই খরচ আগেই লেখা থাকতে পারে (' || coalesce(r->>'warnings', '') || ')', 'Automatic payment not made: the same cost may already be recorded (' || coalesce(r->>'warnings', '') || ')', null, null, frm, null);
    end if;
  exception when others then
    begin
      perform public._stock_exc(p_loc, 'bill_pay_auto_failed', 'yellow', 'স্বয়ংক্রিয় payment হয়নি: ' || left(sqlerrm, 120), 'Automatic payment failed: ' || left(sqlerrm, 120), null, null, frm, null);
    exception when others then null;
    end;
  end;
end $function$
$f$; end if; end $p105$;

-- (INT4) skipped when phase109 / phase111 already merged this function (tag bos109): a re-paste of phase105 must not take the supplier lock fix back out.
do $p105$ begin if current_setting('phase105.ok', true) = 'on' and position('bos109' in pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure)) = 0 then execute $f$
CREATE OR REPLACE FUNCTION public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found and (ex.bill_kind <> p_kind or ex.bill_ref <> p_ref) then raise exception 'client_id_reused'; end if;   -- bos105 (L4): a known id of ANOTHER bill is never answered "paid"
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for update;                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_sp_void99()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l public.bill_payments99; ctx text;
begin
  if not (new.voided and not old.voided and old.bill_id is not null) then return new; end if;
  select * into l from public.bill_payments99 where money_type = 'supplier_payment' and money_ref = old.id::text and status = 'active';
  if not found then return new; end if;
  if coalesce(public.rule_txt('bill_void_payment_mode'), 'void') = 'keep_credit' then
    get diagnostics ctx = pg_context;   -- bos105 (M3): only the void of the BILL may turn its payment into supplier credit; a direct void of the payment is refused loudly, never dropped silently
    if position('_void_purchase_p13' in ctx) = 0 and not exists (select 1 from public.purchase_bills b where b.id = old.bill_id and b.status = 'void') then raise exception 'void_the_bill'; end if;   -- bos105
    new.voided := false; new.void_note := old.void_note; new.void_by := old.void_by; new.bill_id := null;
    update public.bill_payments99 set status = 'kept_credit', closed_by = auth.uid(), closed_at = now(), closed_note = 'bill voided: payment kept as supplier credit' where id = l.id;
    perform public._stock_exc(old.location_id, 'bill_pay_kept', 'yellow', 'বাতিল bill-এর payment supplier-এর credit হিসেবে রাখা হয়েছে: ' || old.amount::text, 'Payment of a voided purchase bill kept as supplier credit: ' || old.amount::text, null, null, 'PURCHASE', old.amount);
  else
    update public.bill_payments99 set status = 'void', closed_by = auth.uid(), closed_at = now(), closed_note = 'purchase bill voided' where id = l.id;
  end if;
  return new;
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.inbox_unmask(p_kind text, p_id text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare loc int; m public.inbound_messages; o public.online_orders; mode_ text := public._inb_pii_mode99(); lim numeric := public.rule_num('inbox_unmask_daily_max'); used int; data jsonb; fields text; sid text;
begin
  if p_kind not in ('message', 'order') or p_id is null then raise exception 'bad_input'; end if;
  if p_kind = 'message' then
    if p_id !~ '^[0-9]{1,18}$' then raise exception 'bad_input'; end if;
    select * into m from public.inbound_messages where id = p_id::bigint;
    if not found then raise exception 'not_found'; end if;
    loc := m.location_id; perform public._inb_gate(loc, 'view'); fields := 'handle,name,text,attachment';
  else
    if p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_input'; end if;
    select * into o from public.online_orders where id = p_id::uuid;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
    if not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(loc) then raise exception 'not allowed'; end if;
    fields := 'customer_mobile,address,customer_name';
  end if;
  if not public._inb_contact_ok(loc) then raise exception 'not allowed'; end if;
  if mode_ = 'off' then          -- nothing is masked: the normal read (which has its own view line)
    return jsonb_build_object('ok', true, 'mode', 'off', 'logged', false, 'data', case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end);
  end if;
  if not (public.is_owner() or public.has_grant('inbox_unmask', loc)) then raise exception 'not allowed'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if lim is not null and not public.is_owner() then
    perform pg_advisory_xact_lock(hashtextextended('inb_unmask99:' || auth.uid()::text, 0));   -- bos105 (M1): parallel calls of one person are counted one after the other
    select count(*) into used from public.inbox_unmask_log99 where user_id = auth.uid() and outcome = 'revealed' and (at at time zone 'Asia/Dhaka')::date = (now() at time zone 'Asia/Dhaka')::date;
    if used >= lim then
      if not exists (select 1 from public.inbox_unmask_log99 z where z.user_id = auth.uid() and z.outcome = 'blocked' and z.at > now() - interval '1 minute') then   -- bos105 (L5): at most one blocked line per person per minute
      insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'blocked');
      end if;   -- bos105
      return jsonb_build_object('ok', false, 'error', 'rate_limited', 'used', used, 'max', lim);
    end if;
  end if;
  perform set_config('bos.inb_unmask99', txid_current()::text, true);
  begin
    data := case when p_kind = 'message' then public.inbox_get(p_id::bigint) else public.online_order_get(p_id::uuid) end;
  exception when others then
    perform set_config('bos.inb_unmask99', '', true); raise;
  end;
  perform set_config('bos.inb_unmask99', '', true);
  insert into public.inbox_unmask_log99 (user_id, staff_id, kind, ref_id, location_id, fields, reason, outcome) values (auth.uid(), sid, p_kind, p_id, loc, fields, left(nullif(btrim(p_reason), ''), 300), 'revealed');
  perform public._inb_audit_view('inbox_unmask', p_kind || ':' || p_id, jsonb_build_object('fields', fields, 'reason', left(nullif(btrim(p_reason), ''), 300)));
  return jsonb_build_object('ok', true, 'mode', mode_, 'logged', true, 'data', data, 'used', coalesce(used, 0) + 1, 'max', lim);
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._inb_mask_phones103(p text) returns text
language plpgsql immutable set search_path = public as $b$
-- masks every phone-number-like digit run (ASCII or Bangla digits, optional +, 8..15 digits, keeps the last 3). Between digits (bos105, M6): up to 3 of space, tab, no-break space, ( ) . - / _ ;
-- a date written 2026-10-14, 2026.10.14, 14/10/2026 or 14-10-2026 is left alone
declare r text := p; m text[]; dg text; nd int; sep text := '[\s' || chr(160) || '()./_-]';
begin
  if p is null or p !~ '[0-9০-৯]' then return p; end if;
  for m in select regexp_matches(p, '(\+?[0-9০-৯](?:[0-9০-৯]|' || sep || '{1,3}(?=[0-9০-৯])){6,})', 'g') loop
    dg := regexp_replace(m[1], '[^0-9০-৯]', '', 'g'); nd := char_length(dg);
    if nd between 8 and 15 and m[1] !~ '^[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}$' and m[1] !~ '^[0-9]{1,2}[-./][0-9]{1,2}[-./][0-9]{4}$' then
      r := replace(r, m[1], repeat('•', greatest(nd - 3, 3)) || right(dg, 3));
    end if;
  end loop;
  return r;
end $b$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._cust_pii103(p_field text, p_val text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- customer fields follow inbox_pii_mode; owner and view_customer_mobile holders see them as before
declare mode_ text := public._inb_pii_mode99();
begin
  if p_val is null or btrim(p_val) = '' or mode_ = 'off' then return p_val; end if;
  if public.is_owner() or public.rpt_grant('view_customer_mobile') then return p_val; end if;
  return case p_field
    when 'name' then case when mode_ = 'mask_all_pii' then public._inb_mask99('name', p_val) else p_val end   -- bos105 (L6): names are hidden only in mask_all_pii
    when 'mobile' then public._inb_mask99('mobile', p_val)
    when 'address' then case when mode_ in ('mask_phone_address', 'mask_all_pii') then public._inb_mask99('address', p_val) else public._inb_mask_phones103(p_val) end
    else case when mode_ = 'mask_all_pii' then public._inb_mask99('text', p_val) else public._inb_mask_phones103(p_val) end end;
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
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
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, public._cust_pii103('mobile', cu.mobile) /* bos105 */, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_advances()
 RETURNS TABLE(customer_id uuid, name text, mobile text, balance numeric, last_at date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, public._cust_pii103('mobile', c.mobile) /* bos105 */, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_profile(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; res jsonb;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'mobile', public._cust_pii103('mobile', c.mobile) /* bos105 */, 'name', c.name, 'type', c.type, 'active', c.active, 'tier_id', c.tier_id, 'tier_locked', c.tier_locked, 'birthday', c.birthday,
        'anniversary', c.anniversary, 'address', public._cust_pii103('address', c.address), 'whatsapp', public._cust_pii103('mobile', c.whatsapp), 'note', public._cust_pii103('text', c.note) /* bos105 */, 'source', c.source, 'credit_limit', c.credit_limit, 'customer_since', c.customer_since),
    'spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'first_sale', st.first_sale, 'last_sale', st.last_sale,
    'avg_bill', case when st.orders > 0 then round(st.spend / st.orders, 2) end,
    'balance', public._cust_bal(p_customer),
    'points', coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', h.at, 'from_tier', h.from_tier, 'to_tier', h.to_tier, 'reason', h.reason, 'note', h.note, 'by', h.by_staff) order by h.at desc, h.id desc)
                         from (select * from public.customer_tier_history where customer_id = p_customer order by at desc, id desc limit 30) h), '[]'::jsonb),
    'gifts', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'text_bn', g.gift_text_bn, 'text_en', g.gift_text_en, 'value', g.value_taka, 'issued_at', g.issued_at, 'valid_until', g.valid_until, 'claimed_at', g.claimed_at)
                                        order by g.issued_at desc) from (select * from public.customer_gifts where customer_id = p_customer order by issued_at desc limit 30) g), '[]'::jsonb),
    'points_log', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'delta', l.delta, 'reason', l.reason, 'note', l.note) order by l.at desc, l.id desc)
                            from (select * from public.customer_points_ledger where customer_id = p_customer order by at desc, id desc limit 30) l), '[]'::jsonb),
    'recent_sales', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'receipt', z.receipt, 'date', z.sale_date, 'total', z.total, 'due', z.due_amount, 'status', z.status, 'loc', z.location_id) order by z.sold_at desc)
                              from (select * from public.sales x where x.customer_id = p_customer and public.can_loc(x.location_id) order by x.sold_at desc limit 10) z), '[]'::jsonb));
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
 RETURNS TABLE(id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text, credit_limit numeric, customer_since date, balance numeric, spend numeric, orders integer, last_sale date, points integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return query
    with s as (select x.customer_id cid, sum(x.total) tot, count(*)::int n, max(x.sale_date) last_d from public.sales x
               where x.status = 'done' and x.customer_id is not null and public.can_loc(x.location_id) group by 1),
         r as (select y.customer_id cid, sum(y.amount) amt from public.sale_returns y join public.sales z on z.id = y.sale_id
               where y.status = 'done' and y.customer_id is not null and public.can_loc(z.location_id) group by 1),
         d as (select q.id cid, q.balance bal from public.customer_dues() q),
         p as (select l.customer_id cid, sum(l.delta)::int pts from public.customer_points_ledger l group by 1)
    select c.id, public._cust_pii103('mobile', c.mobile) /* bos103 */, public._cust_pii103('name', c.name) /* sec2-L6 */, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, public._cust_pii103('address', c.address), public._cust_pii103('mobile', c.whatsapp), public._cust_pii103('text', c.note), c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$
$f$; end if; end $p105$;

do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_save(p_id uuid, p jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mob text; c public.customers; nm text; ty text; mgr boolean; tid bigint; wa text; old_tier bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  mgr := public._cust_mgr43();
  if not (mgr or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if (p ? 'birthday' and public._d43(p, 'birthday') > public._today43()) or (p ? 'anniversary' and public._d43(p, 'anniversary') > public._today43()) then raise exception 'bad_date'; end if;
  if p_id is not null then p := p - array(select e.key from jsonb_each_text(p) e where e.key in ('name', 'address', 'note', 'whatsapp') and e.value like '%•%'); end if;   -- bos105: a masked value read from the screen is never saved back over the real one
  perform public._client_lock(p_client);
  if p ? 'name' then
    nm := left(btrim(coalesce(p ->> 'name', '')), 80);
    if nm = '' then raise exception 'customer_name_required'; end if;
  end if;
  if p ? 'type' then ty := p ->> 'type'; if ty is null or ty not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if; end if;
  if p ? 'whatsapp' then
    wa := nullif(btrim(coalesce(p ->> 'whatsapp', '')), '');
    if wa is not null then wa := public.norm_mobile(wa); end if;
  end if;
  if p_id is null then
    if nullif(btrim(coalesce(p ->> 'mobile', '')), '') is null then raise exception 'bad_mobile'; end if;
    mob := public.norm_mobile(p ->> 'mobile');
    if nm is null then raise exception 'customer_name_required'; end if;
    select * into c from public.customers where mobile = mob;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'name', c.name, 'active', c.active); end if;
    if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit') and not mgr then raise exception 'not allowed'; end if;
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null and not exists (select 1 from public.customer_tiers where id = tid and active) then raise exception 'tier_not_found'; end if;
    insert into public.customers (mobile, name, type, created_by, tier_id, tier_locked, birthday, anniversary, address, note, source, whatsapp, credit_limit)
      values (mob, nm, coalesce(ty, 'retail'), auth.uid(), tid, coalesce((p ->> 'tier_locked')::boolean, tid is not null), public._d43(p, 'birthday'), public._d43(p, 'anniversary'),
              left(nullif(btrim(p ->> 'address'), ''), 200), left(nullif(btrim(p ->> 'note'), ''), 500), left(nullif(btrim(p ->> 'source'), ''), 60), wa, public._n43(p, 'credit_limit', 0))
      returning * into c;
    if tid is not null and tid is distinct from (select id from public.customer_tiers where is_default limit 1) then
      insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
        values (c.id, (select id from public.customer_tiers where is_default limit 1), tid, 'manual', 'at registration', auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
    end if;
    return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
  end if;
  select * into c from public.customers where id = p_id for update;
  if not found then raise exception 'customer_not_found'; end if;
  if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit' or p ? 'active') and not mgr then raise exception 'not allowed'; end if;
  update public.customers set
    name = coalesce(nm, name), type = coalesce(ty, type),
    birthday = case when p ? 'birthday' then public._d43(p, 'birthday') else birthday end,
    anniversary = case when p ? 'anniversary' then public._d43(p, 'anniversary') else anniversary end,
    address = case when p ? 'address' then left(nullif(btrim(p ->> 'address'), ''), 200) else address end,
    note = case when p ? 'note' then left(nullif(btrim(p ->> 'note'), ''), 500) else note end,
    source = case when p ? 'source' then left(nullif(btrim(p ->> 'source'), ''), 60) else source end,
    whatsapp = case when p ? 'whatsapp' then wa else whatsapp end,
    credit_limit = case when p ? 'credit_limit' then public._n43(p, 'credit_limit', 0) else credit_limit end,
    tier_locked = case when p ? 'tier_locked' then coalesce((p ->> 'tier_locked')::boolean, tier_locked) else tier_locked end,
    active = case when p ? 'active' then coalesce((p ->> 'active')::boolean, active) else active end
  where id = p_id returning * into c;
  if p ? 'tier_id' then
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null then perform public.customer_set_tier(p_id, tid, coalesce(nullif(btrim(p ->> 'tier_reason'), ''), 'edited'), case when p ? 'tier_locked' then (p ->> 'tier_locked')::boolean end); end if;
  end if;
  return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
end $function$
$f$; end if; end $p105$;

-- ---------- H1: the new opt-in switch (default OFF = today) ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('customers_pii_guard_on', 'pos', 'switch', 'false', null, null, null, null,
  'গ্রাহকের ফোন/ঠিকানা table থেকে সরাসরি পড়া বন্ধ', 'Customer এর ফোন/ঠিকানা table থেকে সরাসরি পড়া বন্ধ', 'Block direct table reads of customer phone / address',
  'বন্ধ = আজকের মতো। চালু করলে mobile, whatsapp, address, note সরাসরি পড়া যায় না; শুধু customer_directory / customer_profile / customer_dues পড়ায় (inbox_pii_mode মানে)। আগে মোবাইল দিয়ে খোঁজার পর্দাগুলো ঠিক করুন।',
  'Off = as today. On = the browser can no longer read mobile, whatsapp, address, note with a plain table read; only customer_directory / customer_profile / customer_dues show them (following inbox_pii_mode). Screens that search customers by mobile must be moved first.', 990)
on conflict (key) do nothing;
end if; end $p105$;

-- ---------- H1: the existing guard trigger now also covers more online_orders columns and the customers table ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then execute $f$
create or replace function public._inb_pii_cols76() returns trigger language plpgsql security definer set search_path = public as $$
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
end $$
$f$; end if; end $p105$;

-- ---------- grants: the new helper is internal; the salt table is closed ----------
do $p105$ begin if current_setting('phase105.ok', true) = 'on' then
  revoke all on function public._bp_auto_ok105(text, text, int) from public, anon, authenticated;
  revoke all on function public._bp_uuid99(text, text) from public, anon, authenticated;
end if; end $p105$;

-- ---------- marker: phase105 pasted (tests read this) ----------
do $g$ begin
  if current_setting('phase105.ok', true) = 'on' then
    raise notice 'phase105 applied (bos105)';
  else
    raise notice 'phase105 NOT applied: a guard stopped it';
  end if;
end $g$;

-- ---------------------------------------------------------------- phase106.sql
-- ============================================================
-- Phase 106 - Backup / restore-drill coverage for everything added in phases 72..103 (audit: docs/backend/BACKUP_COVERAGE.md)
-- Run AFTER phase103 (and phase102 if used). Additive and idempotent (paste twice = no error). Nothing is deleted. Independent of phase104 / 105.
--   * The backup list is COMPUTED at call time (public._backup_tables(), phase46 / phase70), so all new tables of phases 72..103 are already
--     included automatically, EXCEPT where the blunt column-name filter hides a table that holds no secret:
--       perm_conflict (phase517) has the columns token_a / token_b = permission tokens ("purchase_entry" + "supplier_pay" must not be held together),
--       not credentials. It is owner-edited segregation-of-duties data and was silently left out of every backup.
--   * bos106: public._backup_tables() re-created from its LATEST body (phase70) with ONE change: columns token_a / token_b no longer count as secret
--     (same pattern phase70 used for tokens_in / tokens_out). Everything else is identical: *_secret*, ops_*, login_*, backup_runs, notifications,
--     notification_reads and every table with a password / pin_hash / secret / token / salt / api_key / private_key column stay out
--     (telegram_secrets, intake_proofs94, attendance_devices: on purpose, hashes of secrets are set again after a restore).
--   * public.backup_coverage106()  owner only, read only: every public table, whether it is in the backup, its row count and, when it is out, the reason.
--     The restore drill (docs/RESTORE_DRILL.md) compares this with the manifest; tools/restore_drill.py reports it as optional.
--   * Storage objects (Supabase bucket "photos": item / receipt / staff pictures and scan photos SCAN/...) are NOT in any SQL dump: see docs/backend/BACKUP_COVERAGE.md.
-- ============================================================

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.opening_stock_followups103') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public._backup_tables()') is null then miss := miss || ' 46'; end if;
  if miss <> '' then
    raise exception 'phase106 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- bos106: identical to phase70 except token_a / token_b (permission tokens of perm_conflict) are not secret-looking
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;
comment on function public._backup_tables() is 'bos106: backup / restore-drill table list (computed). token_a/token_b (perm_conflict) are not secrets.';

-- owner-only coverage report: which public tables are in the backup, which are not and why (read only)
create or replace function public.backup_coverage106() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bk text[] := public._backup_tables(); r record; n bigint; arr jsonb := '[]'::jsonb; why text; bad text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in select c.oid, c.relname::text t from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and not c.relispartition order by c.relname loop
    execute format('select count(*) from public.%I', r.t) into n;
    why := null;
    if not (r.t = any (bk)) then
      select string_agg(a.attname::text, ',' order by a.attnum) into bad from pg_attribute a
       where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped and a.attname::text !~ '^(tokens_(in|out)|token_[ab])$'
         and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)';
      why := case when r.t like '%\_secret%' then 'name contains _secret'
                  when r.t like 'ops\_%' then 'ops_* bot account'
                  when r.t in ('login_failures', 'login_attempts', 'login_throttle') then 'login throttle data (re-created by use)'
                  when r.t in ('backup_runs', 'notifications', 'notification_reads') then 'run-time table (re-created by the app)'
                  when bad is not null then 'secret-looking column(s): ' || bad
                  else 'excluded' end;
    end if;
    arr := arr || jsonb_build_object('table', r.t, 'in_backup', r.t = any (bk), 'rows', n, 'reason', why);
  end loop;
  return jsonb_build_object('tables', jsonb_array_length(arr), 'in_backup', coalesce(array_length(bk, 1), 0), 'rows_in_backup',
           coalesce((select sum((x ->> 'rows')::bigint) from jsonb_array_elements(arr) x where (x ->> 'in_backup')::boolean), 0), 'list', arr);
end $$;

do $$ declare r regprocedure; begin
  for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_backup_tables', 'backup_coverage106') loop
    execute format('revoke all on function %s from public, anon, authenticated', r);
    if r::text like 'backup_coverage106%' then execute format('grant execute on function %s to authenticated', r); end if;
  end loop;
end $$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase107.sql
-- ============================================================
-- Phase 107 (bos107) - STEP Errlog: a quiet error log the owner can read from a phone (docs/briefs_p2p3/step_Errlog_REPORT.md).
--   Why: the owner has no browser console. When a screen breaks nothing told us. The web (web/errlog.js) now sends a small, anonymised record of a script error,
--   an unhandled promise rejection, a failed (non-business) rpc call, or a note typed in "Report a problem"; the owner reads them on #/problems.
--   Needs phases 72..103 pasted first (guard below). Independent of 104 (dashboard), 105 (security), 106 (backup): none of them is read or changed here.
--   Additive, paste-twice safe (create ... if not exists / or replace / on conflict do nothing). No existing table, column, function, trigger, rule value or privilege is changed.
--   Whole file = one transaction: if the guard refuses, nothing is created.
--   Objects:
--     tables   client_errors (the log), client_error_seen107 (idempotency keys), client_error_hits107 (per user per hour counter for the rate limit)
--     rules    client_errors_on (switch, default OFF = today's behaviour; RECOMMENDED ON, see the advisor row), client_error_rate_max (number, owner-typed, blank = built-in
--              ceiling 200 per user per hour; a typed number can only LOWER it), client_errors_keep_days (number, blank = keep for ever)
--     grant    view_client_errors (read the log without being the owner)
--     RPC      client_error_log(p_client, p_batch)  any active user, batch <= 20, idempotent, deduped (same fingerprint within 10 minutes -> count + 1), rate limited, never raises
--              client_errors_list(p_from, p_to, p_kind, p_limit, p_status)   owner or view_client_errors
--              client_errors_summary()                                        owner or view_client_errors: top fingerprints of the last 7 days
--              client_error_resolve(p_id, p_note)                             owner only, audited (resolves every open row with the same fingerprint)
--              client_errors_purge(p_days default 60)                         owner only, audited; the rule client_errors_keep_days (blank = keep) drives the automatic purge
--   Privacy: no request body, token, or customer data is stored. extra is cleaned: every key that matches token|key|password|secret|authorization|cookie is removed (any depth),
--   long values are cut, the whole is capped at 2 KB. message / stack lose JWT-looking strings, "Bearer x", e-mail addresses and digit runs of 8+ (phone numbers). route loses its query string and ids.
--   user_report is the one kind that is accepted while client_errors_on is OFF (a person pressed Send on purpose).
--   Tag: bos107. No existing function is re-created.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase107 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- tables ----------
create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),                       -- first seen
  last_at timestamptz not null default now(),                  -- last seen (moves when the same error repeats inside 10 minutes)
  user_id uuid,
  staff_id text,
  app_build text check (app_build is null or char_length(app_build) <= 40),
  route text check (route is null or char_length(route) <= 200),
  kind text not null check (kind in ('js_error', 'unhandled_rejection', 'rpc_error', 'user_report')),
  message text check (message is null or char_length(message) <= 500),
  stack text check (stack is null or char_length(stack) <= 2000),
  ua text check (ua is null or char_length(ua) <= 200),
  lang text check (lang is null or char_length(lang) <= 10),
  extra jsonb check (extra is null or octet_length(extra::text) <= 2048),
  user_note text check (user_note is null or char_length(user_note) <= 1000),
  fingerprint text,                                            -- md5(kind | first line of message with numbers folded | route)
  count int not null default 1 check (count >= 1),
  resolved_at timestamptz, resolved_by uuid, resolve_note text check (resolve_note is null or char_length(resolve_note) <= 500)
);
create index if not exists client_errors_fp107 on public.client_errors (fingerprint, last_at desc);
create index if not exists client_errors_user_fp107 on public.client_errors (user_id, fingerprint, last_at desc);
create index if not exists client_errors_at107 on public.client_errors (at desc);
create table if not exists public.client_error_seen107 (
  user_id uuid not null, client_key text not null, at timestamptz not null default now(), primary key (user_id, client_key));
create table if not exists public.client_error_hits107 (
  user_id uuid not null, hr timestamptz not null, n int not null default 0, primary key (user_id, hr));

-- RLS: nobody inserts / updates / deletes directly (only the definer RPCs write); select only for the owner or a holder of view_client_errors
alter table public.client_errors enable row level security;
alter table public.client_error_seen107 enable row level security;
alter table public.client_error_hits107 enable row level security;
revoke all on public.client_errors, public.client_error_seen107, public.client_error_hits107 from public, anon, authenticated;
grant select on public.client_errors to authenticated;
drop policy if exists client_errors_read107 on public.client_errors;
create policy client_errors_read107 on public.client_errors for select to authenticated using (public.is_owner() or public.has_grant('view_client_errors'));

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('client_errors_on', 'settings', 'switch', 'false', null, null, null, null,
  'অ্যাপের ভাঙা স্ক্রিনের খবর নিজে থেকে জমা হবে', 'App এর ভাঙা screen এর খবর নিজে থেকে জমা হবে', 'Collect error reports from the app automatically',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু করলে কোনো স্ক্রিন ভাঙলে সংক্ষিপ্ত খবর (কোন স্ক্রিন, কী ভুল, কোন সংস্করণ) জমা হয়; মালিক "সমস্যা" পাতায় দেখেন। পাসওয়ার্ড, টোকেন, গ্রাহকের তথ্য কখনো জমা হয় না। "সমস্যা জানান" বোতাম এই সুইচ ছাড়াও কাজ করে।',
  'বন্ধ = আগের মতোই (default)। চালু করলে কোনো screen ভাঙলে সংক্ষিপ্ত খবর (কোন screen, কী error, কোন build) জমা হয়; owner Problems পাতায় দেখেন। Password, token, customer এর তথ্য কখনো জমা হয় না। Report a problem বোতাম এই switch ছাড়াও কাজ করে।',
  'Off = as before (default). On: when a screen breaks, a short note (which screen, what error, which build) is saved and the owner reads it on the Problems page. Passwords, tokens and customer data are never stored. The Report a problem button works even while this is off.', 990),
 ('client_error_rate_max', 'settings', 'number', null, 'per hour', null, 1, 200,
  'একজন ব্যবহারকারী ঘণ্টায় সর্বোচ্চ কতটি ত্রুটির খবর পাঠাতে পারবে', 'একজন user ঘণ্টায় সর্বোচ্চ কতটি error report পাঠাতে পারবে', 'Most error reports one user may send per hour',
  'ফাঁকা = ভেতরের নিরাপত্তা সীমা ২০০ (এটা ব্যবসার সংখ্যা নয়, শুধু ভুল লুপ থেকে সার্ভার বাঁচানোর জন্য)। সংখ্যা দিলে শুধু সীমা কমানো যায়, ২০০ এর বেশি নয়।',
  'ফাঁকা = ভেতরের safety limit 200 (এটা business এর সংখ্যা নয়, শুধু ভুল loop থেকে server বাঁচানোর জন্য)। সংখ্যা দিলে শুধু limit কমানো যায়, 200 এর বেশি নয়।',
  'Blank = the built-in safety ceiling of 200 (not a business number, only a guard against a runaway loop hammering the server). A number can only lower it, never raise it above 200.', 991),
 ('client_errors_keep_days', 'settings', 'number', null, 'days', null, 1, 3650,
  'ত্রুটির খবর কত দিন রাখা হবে', 'Error report কত দিন রাখা হবে', 'Days to keep error reports',
  'ফাঁকা = চিরকাল রাখা হবে (ডিফল্ট)। সংখ্যা দিলে তার চেয়ে পুরনো খবর নিজে থেকে মুছে যায়। মালিক "সমস্যা" পাতা থেকেও হাতে মুছতে পারেন।',
  'ফাঁকা = চিরকাল রাখা হবে (default)। সংখ্যা দিলে তার চেয়ে পুরনো report নিজে থেকে মুছে যায়। Owner Problems পাতা থেকেও হাতে মুছতে পারেন।',
  'Blank = keep for ever (default). A number: reports older than that are deleted automatically. The owner can also purge by hand from the Problems page.', 992)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'view_client_errors', 'settings', 98, 'অ্যাপের ত্রুটির খবর দেখা (সমস্যা পাতা)', 'App এর error report দেখা (Problems পাতা)', 'See the app error reports (Problems page)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'view_client_errors');

-- the setup advisor: client_errors_on recommended ON; the two numbers are owner-typed (no value recommended)
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('client_errors_on', 'client_errors_on', '107', 'settings', 'true'::jsonb, '{}'::text[],
  'ফোনে কনসোল খোলা যায় না, তাই স্ক্রিন ভাঙলে কেউ জানতে পারে না। চালু রাখলে শুধু সংক্ষিপ্ত খবর জমা হয় (কোন স্ক্রিন, কী ভুল); কোনো বিক্রি, হিসাব বা দাম বদলায় না, পাসওয়ার্ড বা গ্রাহকের তথ্য জমা হয় না।',
  'Phone এ console খোলা যায় না, তাই screen ভাঙলে কেউ জানতে পারে না। চালু রাখলে শুধু সংক্ষিপ্ত খবর জমা হয় (কোন screen, কী error); কোনো sale, হিসাব বা দাম বদলায় না, password বা customer এর তথ্য জমা হয় না।',
  'You cannot open a browser console on a phone, so a broken screen goes unnoticed. With this on, only a short note is saved (which screen, what error); no sale, book or price is touched and no password or customer data is stored.', 990),
 ('client_error_rate_max', 'client_error_rate_max', '107', 'settings', null, '{}'::text[],
  'ফাঁকা থাকলে ভেতরের সীমা ২০০ কাজ করে। কম সীমা চাইলে মালিক নিজে লিখুন; ২০০ এর বেশি হয় না।',
  'ফাঁকা থাকলে ভেতরের limit 200 কাজ করে। কম limit চাইলে owner নিজে লিখুন; 200 এর বেশি হয় না।',
  'Blank keeps the built-in ceiling of 200. Type a number only to lower it; it can never go above 200.', 991),
 ('client_errors_keep_days', 'client_errors_keep_days', '107', 'settings', null, '{}'::text[],
  'কত দিন রাখবেন তা আপনার সিদ্ধান্ত, তাই কোনো সংখ্যা ঠিক করা নেই। ফাঁকা = চিরকাল রাখা।',
  'কত দিন রাখবেন তা আপনার decision, তাই কোনো সংখ্যা ঠিক করা নেই। ফাঁকা = চিরকাল রাখা।',
  'How long to keep reports is your decision, so no number is recommended. Blank = keep for ever.', 992)
on conflict (code) do nothing;

-- ---------- helpers (internal, no privilege for anyone) ----------
create or replace function public._ce_strip107(j jsonb, d int default 0) returns jsonb
language plpgsql immutable set search_path = public as $$
-- removes every object key matching token|key|password|secret|authorization|cookie (any depth), cuts long strings, limits depth / array size
declare o jsonb; k text; v jsonb; n int := 0; r jsonb;
begin
  if j is null then return null; end if;
  if d > 4 then return to_jsonb('…'::text); end if;
  case jsonb_typeof(j)
    when 'object' then
      o := '{}'::jsonb;
      for k, v in select * from jsonb_each(j) loop
        if k ~* 'token|key|password|secret|authorization|cookie' then continue; end if;
        n := n + 1; if n > 30 then exit; end if;
        o := o || jsonb_build_object(left(k, 60), public._ce_strip107(v, d + 1));
      end loop;
      return o;
    when 'array' then
      r := '[]'::jsonb;
      for v in select * from jsonb_array_elements(j) limit 20 loop r := r || jsonb_build_array(public._ce_strip107(v, d + 1)); end loop;
      return r;
    when 'string' then return to_jsonb(left(j #>> '{}', 200));
    else return j;
  end case;
end $$;

create or replace function public._ce_clean107(p text, p_max int) returns text
language sql immutable set search_path = public as $$
  -- JWT-looking strings, Bearer values, e-mail addresses and digit runs of 8+ (phone / account numbers) are replaced; then cut to p_max
  select left(regexp_replace(regexp_replace(regexp_replace(regexp_replace(p,
    'eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+){0,2}', '[jwt]', 'g'),
    'Bearer\s+[^\s"'',;]+', 'Bearer [x]', 'gi'),
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
    '[0-9০-৯]{8,}', '[num]', 'g'), p_max)
$$;

create or replace function public._ce_route107(p text) returns text
language sql immutable set search_path = public as $$
  -- no query string, no hash parameters, no ids: uuids and long numbers become :id
  select left(regexp_replace(regexp_replace(split_part(coalesce(p, ''), '?', 1),
    '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', ':id', 'g'),
    '/[0-9]{2,}(?=/|$)', '/:id', 'g'), 200)
$$;

create or replace function public._ce_fp107(p_kind text, p_msg text, p_route text) returns text
language sql immutable set search_path = public as $$
  select md5(coalesce(p_kind, '') || '|' || regexp_replace(left(split_part(coalesce(p_msg, ''), E'\n', 1), 200), '[0-9]+', '#', 'g') || '|' || coalesce(p_route, ''))
$$;

create or replace function public._client_errors_autopurge107() returns int
language plpgsql security definer set search_path = public as $$
-- rule client_errors_keep_days blank = keep. Also drops the idempotency keys / hour counters older than 2 days (they only matter for a day).
declare dd numeric := public.rule_num('client_errors_keep_days'); n int := 0;
begin
  delete from public.client_error_seen107 where at < now() - interval '2 days';
  delete from public.client_error_hits107 where hr < now() - interval '2 days';
  if dd is not null and dd >= 1 then
    delete from public.client_errors where at < now() - (dd::int || ' days')::interval; get diagnostics n = row_count;
  end if;
  return n;
end $$;

-- ---------- write: a batch of up to 20 reports from the device ----------
create or replace function public.client_error_log(p_client text, p_batch jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); sid text; on_ boolean; cap int; hr_ timestamptz := date_trunc('hour', now()); used int := 0; startused int;
  e jsonb; i int := 0; kind_ text; msg text; stk text; rt text; fp text; cid text; ck text; ex jsonb; note text; cnt int; did bigint;
  acc int := 0; dedup int := 0; dup int := 0; skip int := 0; offc int := 0; lim int := 0; bad int := 0; drop_ int := 0; ins int;
begin
  if uid is null or not public.is_active() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_batch is null or jsonb_typeof(p_batch) <> 'array' then return jsonb_build_object('ok', false, 'error', 'bad_batch'); end if;
  on_ := coalesce(public.rule_on('client_errors_on'), false);
  cap := greatest(1, least(coalesce(public.rule_num('client_error_rate_max'), 200), 200))::int;   -- the typed number can only lower the built-in ceiling
  select n into used from public.client_error_hits107 where user_id = uid and hr = date_trunc('hour', now());
  used := coalesce(used, 0); startused := used;
  select staff_id into sid from public.profiles where id = uid;
  for e in select x from jsonb_array_elements(p_batch) x loop
    i := i + 1;
    if i > 20 then drop_ := drop_ + 1; continue; end if;
    begin
      kind_ := e ->> 'kind';
      if kind_ is null or kind_ not in ('js_error', 'unhandled_rejection', 'rpc_error', 'user_report') then skip := skip + 1; continue; end if;
      if not on_ and kind_ <> 'user_report' then offc := offc + 1; continue; end if;
      if used >= cap then lim := lim + 1; continue; end if;
      cid := nullif(left(btrim(coalesce(e ->> 'cid', '')), 64), '');
      if cid is not null then
        ck := left(coalesce(p_client, ''), 64) || ':' || cid;
        insert into public.client_error_seen107 (user_id, client_key) values (uid, ck) on conflict do nothing;
        get diagnostics ins = row_count;
        if ins = 0 then dup := dup + 1; continue; end if;
      end if;
      msg := public._ce_clean107(e ->> 'message', 500);
      stk := public._ce_clean107(e ->> 'stack', 2000);
      rt := public._ce_route107(e ->> 'route');
      note := left(e ->> 'note', 1000);
      ex := public._ce_strip107(case when jsonb_typeof(e -> 'extra') = 'object' then e -> 'extra' else null end);
      if ex is not null and octet_length(ex::text) > 2048 then ex := jsonb_build_object('truncated', true, 'keys', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (select jsonb_object_keys(ex) k limit 10) q)); end if;
      cnt := greatest(1, least(coalesce(nullif(e ->> 'count', '')::int, 1), 1000));
      fp := public._ce_fp107(kind_, msg, rt);
      used := used + 1;
      did := null;
      if kind_ <> 'user_report' then
        update public.client_errors set count = least(count + cnt, 1000000), last_at = now()
         where id = (select id from public.client_errors where user_id = uid and fingerprint = fp and resolved_at is null and last_at > now() - interval '10 minutes' order by last_at desc limit 1)
        returning id into did;
      end if;
      if did is not null then dedup := dedup + 1;
      else
        insert into public.client_errors (user_id, staff_id, app_build, route, kind, message, stack, ua, lang, extra, user_note, fingerprint, count)
        values (uid, sid, left(e ->> 'app_build', 40), rt, kind_, msg, stk, left(e ->> 'ua', 200), left(e ->> 'lang', 10), ex, note, fp, cnt);
        acc := acc + 1;
      end if;
    exception when others then bad := bad + 1;
    end;
  end loop;
  if used > startused then
    insert into public.client_error_hits107 (user_id, hr, n) values (uid, hr_, used) on conflict (user_id, hr) do update set n = greatest(public.client_error_hits107.n, excluded.n);
  end if;
  if random() < 0.02 then perform public._client_errors_autopurge107(); end if;
  return jsonb_build_object('ok', true, 'accepted', acc, 'deduped', dedup, 'duplicate', dup, 'skipped', skip, 'off', offc, 'limited', lim, 'dropped', drop_, 'bad', bad);
exception when others then
  return jsonb_build_object('ok', false, 'error', 'failed');   -- logging must never break the app
end $$;

-- ---------- read ----------
create or replace function public.client_errors_list(p_from timestamptz default null, p_to timestamptz default null, p_kind text default null, p_limit int default 200, p_status text default 'all')
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public.has_grant('view_client_errors')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.last_at desc) from (
    select id, at, last_at, user_id, staff_id, app_build, route, kind, message, stack, ua, lang, extra, user_note, fingerprint, count, resolved_at, resolve_note
      from public.client_errors
     where (p_from is null or last_at >= p_from) and (p_to is null or at <= p_to) and (p_kind is null or kind = p_kind)
       and (coalesce(p_status, 'all') = 'all' or (p_status = 'open' and resolved_at is null) or (p_status = 'resolved' and resolved_at is not null))
     order by last_at desc limit greatest(1, least(coalesce(p_limit, 200), 500))) q), '[]'::jsonb);
end $$;

create or replace function public.client_errors_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public.has_grant('view_client_errors')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q.total desc, q.last_at desc) from (
    select fingerprint, (array_agg(kind order by last_at desc))[1] as kind, (array_agg(message order by last_at desc))[1] as message, (array_agg(route order by last_at desc))[1] as route,
           sum(count)::int as total, count(distinct user_id)::int as users, max(last_at) as last_at, bool_or(resolved_at is null) as open
      from public.client_errors where last_at >= now() - interval '7 days' group by fingerprint order by sum(count) desc, max(last_at) desc limit 20) q), '[]'::jsonb);
end $$;

-- ---------- owner actions (audited) ----------
create or replace function public.client_error_resolve(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.client_errors; n int; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.client_errors where id = p_id;
  if not found then raise exception 'not found'; end if;
  update public.client_errors set resolved_at = now(), resolved_by = auth.uid(), resolve_note = left(p_note, 500)
   where resolved_at is null and (id = p_id or (fingerprint is not null and fingerprint = r.fingerprint));
  get diagnostics n = row_count;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), sid, 'resolve', 'client_errors', p_id::text, jsonb_build_object('fingerprint', r.fingerprint, 'rows', n, 'note', left(p_note, 500)));
  return jsonb_build_object('ok', true, 'resolved', n);
end $$;

create or replace function public.client_errors_purge(p_days int default 60) returns int
language plpgsql security definer set search_path = public as $$
-- the 60 is only this function's default; the automatic purge follows the rule client_errors_keep_days (blank = keep). Explicit call by the owner deletes rows older than p_days.
declare n int; sid text; dd int := p_days;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if dd is null then dd := public.rule_num('client_errors_keep_days')::int; end if;
  if dd is null then return 0; end if;
  if dd < 1 then raise exception 'bad_value'; end if;
  delete from public.client_errors where at < now() - (dd || ' days')::interval; get diagnostics n = row_count;
  delete from public.client_error_seen107 where at < now() - interval '2 days';
  delete from public.client_error_hits107 where hr < now() - interval '2 days';
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), sid, 'purge', 'client_errors', null, jsonb_build_object('days', dd, 'deleted', n));
  return n;
end $$;

revoke all on function public._ce_strip107(jsonb, int), public._ce_clean107(text, int), public._ce_route107(text), public._ce_fp107(text, text, text), public._client_errors_autopurge107() from public, anon, authenticated;
revoke all on function public.client_error_log(text, jsonb), public.client_errors_list(timestamptz, timestamptz, text, int, text), public.client_errors_summary(),
  public.client_error_resolve(bigint, text), public.client_errors_purge(int) from public, anon;
grant execute on function public.client_error_log(text, jsonb), public.client_errors_list(timestamptz, timestamptz, text, int, text), public.client_errors_summary(),
  public.client_error_resolve(bigint, text), public.client_errors_purge(int) to authenticated;

commit;

-- ---------------------------------------------------------------- phase108.sql
-- ============================================================
-- Phase 108 (bos108) - Bangla wording fixes for the label_bn / label_mix seed rows of phases 72..103 (docs/i18n/BANGLA_REVIEW.md).
--   Generated by tools/apply_bangla_review.py --emit-sql (re-run after the CSV changes; the file is rewritten whole).
--   Needs phases 72..103 pasted first (guard below). Additive + paste-twice safe: every UPDATE fires only while the column STILL equals the old seed
--   text, so an owner edit, an old row (pre-72) or an already-fixed row is never overwritten. No table, column, function or privilege is changed.
--   Phases 104..107 are reserved by other agents.
-- ============================================================

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 101'; end if;
  if to_regclass('public.rules') is null or not exists (select 1 from public.rules where key = 'item_images_mode') then miss := miss || ' 102'; end if;
  if to_regclass('public.rules') is null or not exists (select 1 from public.rules where key = 'acct_manual_prod_in103') then miss := miss || ' 103'; end if;
  if miss <> '' then raise exception 'phase108 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
-- 124 statements (cost_component_types 1, grant_defs 9, grant_separation_pairs 2, manual_reason_codes85 5, rules 77, setup_check_defs81 30)
  -- ---------- rules ----------
  update public.rules set label_bn = 'উৎপাদনে কোনো উপকরণের কস্ট অজানা (ফাঁকা বা ০) থাকলে: সতর্কতা / আটকানো' where key = 'production_requires_cost' and label_bn = 'উৎপাদনে কোনো উপকরণের খরচ অজানা (ফাঁকা বা ০) থাকলে: সতর্কতা / আটকানো';
  update public.rules set label_mix = 'Production-এ কোনো উপকরণের cost অজানা (ফাঁকা বা ০) হলে: warn / refuse' where key = 'production_requires_cost' and label_mix = 'Production এ কোনো উপকরণের cost অজানা (ফাঁকা বা ০) হলে: warn / refuse';
  update public.rules set label_bn = 'রেসিপি অ্যাপ্রুভের আগে কস্ট/উৎপাদন: বন্ধ / হলুদ সতর্কতা / আটকানো' where key = 'recipe_approval_required' and label_bn = 'রেসিপি অনুমোদনের আগে খরচ/উৎপাদন: বন্ধ / হলুদ সতর্কতা / আটকানো';
  update public.rules set label_mix = 'Recipe approval-এর আগে cost/production: off / warn / on' where key = 'recipe_approval_required' and label_mix = 'Recipe approval এর আগে cost/production: off / warn / on';
  update public.rules set label_bn = 'যে রেসিপি বদলেছে সে-ই অ্যাপ্রুভ করতে পারবে' where key = 'recipe_self_approve' and label_bn = 'যে রেসিপি বদলেছে সে-ই অনুমোদন করতে পারবে';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'রেসিপি অ্যাপ্রুভ' where grant_code = 'recipe_approve' and label_bn = 'রেসিপি অনুমোদন';
  update public.grant_defs set label_mix = 'Artisan register-এ নাম ও তথ্য লেখা' where grant_code = 'artisan_manage' and label_mix = 'Artisan register এ নাম ও তথ্য লেখা';
  -- ---------- rules ----------
  update public.rules set label_bn = '"আজকের কেনা প্রাইস" ও গড় প্রাইসের ফারাক % — এর বেশি হলে হলুদ সতর্কতা' where key = 'cost_gap_warn_pct' and label_bn = '"আজকের কেনা দাম" ও গড় দামের ফারাক % — এর বেশি হলে হলুদ সতর্কতা';
  update public.rules set label_mix = '"আজকের কেনা price" vs গড় price-এর gap % — এর বেশি হলে yellow' where key = 'cost_gap_warn_pct' and label_mix = '"আজকের কেনা দাম" vs গড় দামের gap % — এর বেশি হলে yellow';
  update public.rules set label_bn = 'সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) জরুরি' where key = 'production_manual_needs_reason' and label_bn = 'সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) বাধ্যতামূলক';
  update public.rules set label_mix = 'Direct "Production in"-এ reason (note) জরুরি' where key = 'production_manual_needs_reason' and label_mix = 'Direct "Production in"-এ reason (note) বাধ্যতামূলক';
  -- ---------- cost_component_types ----------
  update public.cost_component_types set label_bn = 'ডেপ্রিসিয়েশন' where code = 'depreciation' and label_bn = 'অবচয়';
  -- ---------- rules ----------
  update public.rules set label_bn = 'যে ভাগের নিয়ম লিখেছে সে-ই অ্যাপ্রুভ করতে পারবে' where key = 'cost_rule_self_approve' and label_bn = 'যে ভাগের নিয়ম লিখেছে সে-ই অনুমোদন করতে পারবে';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'কস্টের বিল ও সোর্স লেখা' where grant_code = 'cost_bill_entry' and label_bn = 'খরচের বিল ও সোর্স লেখা';
  update public.grant_defs set label_bn = 'ভাগের নিয়ম অ্যাপ্রুভ' where grant_code = 'cost_rule_approve' and label_bn = 'ভাগের নিয়ম অনুমোদন';
  -- ---------- rules ----------
  update public.rules set label_bn = 'ওয়েব ফর্মে ক্যাপচা জরুরি' where key = 'web_form_captcha_on' and label_bn = 'ওয়েব ফর্মে ক্যাপচা বাধ্যতামূলক';
  update public.rules set label_mix = 'Web form-এ captcha জরুরি' where key = 'web_form_captcha_on' and label_mix = 'Web form-এ captcha বাধ্যতামূলক';
  update public.rules set label_bn = 'বার্তা থেকে অর্ডারের ড্রাফট (যাচাই বাকি) চালু' where key = 'inbox_autodraft_on' and label_bn = 'বার্তা থেকে অর্ডারের খসড়া (যাচাই বাকি) চালু';
  update public.rules set label_mix = 'Message থেকে order draft (যাচাই বাকি) চালু' where key = 'inbox_autodraft_on' and label_mix = 'Message থেকে order খসড়া (যাচাই বাকি) চালু';
  update public.rules set label_bn = 'কাস্টমারের ফোন/ঠিকানা শুধু অনুমতি-পাওয়াদের' where key = 'inbox_pii_guard_on' and label_bn = 'গ্রাহকের ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের';
  update public.rules set label_mix = 'Customer ফোন/ঠিকানা শুধু অনুমতি-পাওয়াদের' where key = 'inbox_pii_guard_on' and label_mix = 'Customer ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের';
  update public.rules set label_bn = 'ডেলিভারিতে অর্ডারের প্রাইস ধরে রাখা' where key = 'online_keep_order_price' and label_bn = 'ডেলিভারিতে অর্ডারের দাম ধরে রাখা';
  update public.rules set label_mix = 'Delivery-তে order-এর price ধরে রাখা' where key = 'online_keep_order_price' and label_mix = 'Delivery-তে order-এর দাম ধরে রাখা';
  update public.rules set label_bn = 'কস্টের বিলের শোরুম/অ্যাডমিন অংশ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখান' where key = 'cost_attrib_in_pl' and label_bn = 'খরচের বিলের শোরুম/অ্যাডমিন অংশ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখান';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'কস্ট কোন শাখার — ঠিক ও বদল' where grant_code = 'cost_attrib_manage' and label_bn = 'খরচ কোন শাখার — ঠিক ও বদল';
  -- ---------- grant_separation_pairs ----------
  update public.grant_separation_pairs set label_bn = 'রেসিপি লেখা ও অ্যাপ্রুভ' where code = 'recipe' and label_bn = 'রেসিপি লেখা ও অনুমোদন';
  update public.grant_separation_pairs set label_bn = 'কস্টের বিল / ভাগের নিয়ম লেখা ও অ্যাপ্রুভ' where code = 'cost_rules' and label_bn = 'খরচের বিল / ভাগের নিয়ম লেখা ও অনুমোদন';
  -- ---------- rules ----------
  update public.rules set label_bn = 'অংশীদার লাভের ভিত্তিতে অনুমানের কস্ট থাকলে: সতর্কতা / আটকানো' where key = 'partner_base_estimate' and label_bn = 'অংশীদার লাভের ভিত্তিতে অনুমানের খরচ থাকলে: সতর্কতা / আটকানো';
  -- ---------- setup_check_defs81 ----------
  update public.setup_check_defs81 set label_mix = 'Tracked item-এ base unit নেই' where code = 'stk_unit' and label_mix = 'Tracked item এ base unit নেই';
  update public.setup_check_defs81 set label_bn = 'ট্র্যাক করা আইটেমের শুরুর স্টক (ওপেনিং) তোলা হয়নি' where code = 'stk_opening' and label_bn = 'ট্র্যাক করা আইটেমের শুরুর স্টক (opening) তোলা হয়নি';
  update public.setup_check_defs81 set label_mix = 'Tracked item-এর opening stock তোলা হয়নি' where code = 'stk_opening' and label_mix = 'Tracked item এর opening stock তোলা হয়নি';
  update public.setup_check_defs81 set label_mix = 'Sell unit-এর conversion নেই' where code = 'stk_conv' and label_mix = 'Sell unit এর conversion নেই';
  update public.setup_check_defs81 set label_bn = 'স্টক আছে কিন্তু কস্ট জানা নেই (ফাঁকা বা ০ = অজানা)' where code = 'stk_cost' and label_bn = 'স্টক আছে কিন্তু খরচ জানা নেই (ফাঁকা বা ০ = অজানা)';
  update public.setup_check_defs81 set label_bn = 'হিসাব শুরুর ডেট বসানো নেই' where code = 'acc_start' and label_bn = 'হিসাব শুরুর তারিখ বসানো নেই';
  update public.setup_check_defs81 set label_mix = 'দরকারি account mapping নেই বা বন্ধ account-এ' where code = 'acc_map' and label_mix = 'দরকারি account mapping নেই বা বন্ধ account এ';
  update public.setup_check_defs81 set label_bn = 'কিছু কাগজ কস্ট অজানা বলে অপেক্ষায় আছে' where code = 'acc_wait' and label_bn = 'কিছু কাগজ খরচ অজানা বলে অপেক্ষায় আছে';
  update public.setup_check_defs81 set label_mix = 'Autopost-এ error জমে আছে' where code = 'acc_err' and label_mix = 'Autopost এ error জমে আছে';
  update public.setup_check_defs81 set label_mix = 'Recipe-এর yield নেই' where code = 'prd_yield' and label_mix = 'Recipe এর yield নেই';
  update public.setup_check_defs81 set label_bn = 'অ্যাপ্রুভ (অ্যাপ্রুভ) হয়নি এমন রেসিপি' where code = 'prd_approve' and label_bn = 'অনুমোদন (approve) হয়নি এমন রেসিপি';
  update public.setup_check_defs81 set label_bn = 'উপাদানের কস্ট অজানা (ফাঁকা বা ০)' where code = 'prd_icost' and label_bn = 'উপাদানের খরচ অজানা (ফাঁকা বা ০)';
  update public.setup_check_defs81 set label_mix = 'Ingredient-এর cost অজানা (blank বা 0)' where code = 'prd_icost' and label_mix = 'Ingredient এর cost অজানা (blank বা 0)';
  update public.setup_check_defs81 set label_mix = 'Recipe unit-এর conversion নেই' where code = 'prd_unit' and label_mix = 'Recipe unit এর conversion নেই';
  update public.setup_check_defs81 set label_bn = 'কারখানার কস্টের পদ্ধতি অসম্পূর্ণ (pool-এ স্বাভাবিক মাসিক উৎপাদন নেই / recipe-এ কস্টের ধরন নেই)' where code = 'prd_conv' and label_bn = 'কারখানার খরচের পদ্ধতি অসম্পূর্ণ (pool-এ স্বাভাবিক মাসিক উৎপাদন নেই / recipe-এ খরচের ধরন নেই)';
  update public.setup_check_defs81 set label_mix = 'Factory cost method অসম্পূর্ণ (pool-এ normal monthly output নেই / recipe-এ cost component নেই)' where code = 'prd_conv' and label_mix = 'Factory cost method অসম্পূর্ণ (pool এ normal monthly output নেই / recipe এ cost component নেই)';
  update public.setup_check_defs81 set label_bn = 'কোনো কস্টের উৎস (বিল) বসানো নেই' where code = 'cs_sources' and label_bn = 'কোনো খরচের উৎস (বিল) বসানো নেই';
  update public.setup_check_defs81 set label_bn = 'অ্যাপ্রুভড ভাগের নিয়ম নেই এমন উৎস' where code = 'cs_rule' and label_bn = 'অনুমোদিত ভাগের নিয়ম নেই এমন উৎস';
  update public.setup_check_defs81 set label_bn = 'কোন কস্ট কোন শোরুমের তা এখনো ঠিক করা নেই' where code = 'cs_attrib' and label_bn = 'কোন খরচ কোন শোরুমের তা এখনো ঠিক করা নেই';
  update public.setup_check_defs81 set label_mix = 'কোন cost কোন showroom-এর তা এখনো ঠিক করা নেই' where code = 'cs_attrib' and label_mix = 'কোন cost কোন showroom এর তা এখনো ঠিক করা নেই';
  update public.setup_check_defs81 set label_bn = 'কোনো চালু সেলের চ্যানেল নেই' where code = 'onl_channels' and label_bn = 'কোনো চালু বিক্রির চ্যানেল নেই';
  update public.setup_check_defs81 set label_mix = 'আগের দিনের document এখনো books-এ ঢোকেনি' where code = 'flw_acc_old' and label_mix = 'আগের দিনের document এখনো books এ ঢোকেনি';
  update public.setup_check_defs81 set label_mix = 'Autopost-এ error জমে আছে' where code = 'flw_acc_err' and label_mix = 'Autopost এ error জমে আছে';
  update public.setup_check_defs81 set label_bn = 'কস্ট অজানা বলে কাগজ অপেক্ষায়' where code = 'flw_acc_wait' and label_bn = 'খরচ অজানা বলে কাগজ অপেক্ষায়';
  update public.setup_check_defs81 set label_bn = 'কস্ট অসম্পূর্ণ রেখে হওয়া উৎপাদন' where code = 'flw_prod_cost' and label_bn = 'খরচ অসম্পূর্ণ রেখে হওয়া উৎপাদন';
  update public.setup_check_defs81 set label_bn = 'অনলাইন অর্ডারের খোলা ফ্ল্যাগ (ভয়েড সেল) আছে' where code = 'flw_oo_flags' and label_bn = 'অনলাইন অর্ডারের খোলা ফ্ল্যাগ (বাতিল বিক্রি) আছে';
  update public.setup_check_defs81 set label_mix = 'Online order-এর open flag (voided sale) আছে' where code = 'flw_oo_flags' and label_mix = 'Online order এর open flag (voided sale) আছে';
  update public.setup_check_defs81 set label_mix = 'Pool method-এর জায়গায় এই মাসের cost বসানো নেই' where code = 'flw_pool' and label_mix = 'Pool method এর জায়গায় এই মাসের cost বসানো নেই';
  -- ---------- rules ----------
  update public.rules set label_bn = 'বিল ভয়েডে সাপ্লায়ারকে দেওয়া টাকা: ভয়েড ধরা / রেখে দেওয়া (credit)' where key = 'purchase_void_payments' and label_bn = 'bill বাতিলে supplierকে দেওয়া টাকা: বাতিল ধরা / রেখে দেওয়া (credit)';
  update public.rules set label_bn = 'stock-tracked আইটেমে unit-এর conversion না থাকলে সেল: বন্ধ / warn / block' where key = 'unit_conv_required' and label_bn = 'stock-tracked পণ্যে unit-এর conversion না থাকলে বিক্রি: বন্ধ / warn / block';
  update public.rules set label_bn = '"স্টকের নিচে বিক্রি" অনুমতি ব্যবহার হলে yellow warning' where key = 'neg_grant_log' and label_bn = '"stock-এর নিচে বিক্রি" অনুমতি ব্যবহার হলে yellow warning';
  update public.rules set label_bn = 'উৎপাদনে উপকরণ মাইনাস হলে কারণ: বন্ধ / warn / required' where key = 'production_negative_reason' and label_bn = 'উৎপাদনে কাঁচামাল ঋণাত্মক হলে কারণ: বন্ধ / warn / required';
  update public.rules set label_bn = 'কারখানা দৈনিক শিট (05-1): স্টকে কীভাবে ধরা হবে' where key = 'form_051_mode' and label_bn = 'কারখানা দৈনিক শিট (05-1): stock-এ কীভাবে ধরা হবে';
  update public.rules set label_bn = 'স্টক গণনার পার্থক্য journal-এ তোলা (stock gain / loss)' where key = 'acct_count_adjust' and label_bn = 'Stock গণনার পার্থক্য journal এ তোলা (stock gain / loss)';
  update public.rules set label_mix = 'Stock count-এর difference journal-এ post করা' where key = 'acct_count_adjust' and label_mix = 'Stock count এর difference journal এ post করা';
  update public.rules set label_bn = 'Opening stock journal-এ তোলা (owner capital-এর বিপরীতে)' where key = 'acct_stock_opening' and label_bn = 'Opening stock journal এ তোলা (owner capital এর বিপরীতে)';
  update public.rules set label_mix = 'Opening stock journal-এ post করা (owner capital-এর against-এ)' where key = 'acct_stock_opening' and label_mix = 'Opening stock journal এ post করা (owner capital এর against এ)';
  update public.rules set label_bn = 'নিজের কাজে stock issue journal-এ তোলা' where key = 'acct_issue_out' and label_bn = 'নিজের কাজে stock issue journal এ তোলা';
  update public.rules set label_mix = 'Own-use stock issue journal-এ post করা' where key = 'acct_issue_out' and label_mix = 'Own-use stock issue journal এ post করা';
  update public.rules set label_bn = 'Stock transfer-এর হিসাব: বন্ধ / স্থানভিত্তিক জোড়া / পুরো কোম্পানি' where key = 'acct_transfer_mode' and label_bn = 'Stock transfer এর হিসাব: বন্ধ / স্থানভিত্তিক জোড়া / পুরো কোম্পানি';
  update public.rules set label_mix = 'Stock transfer-এর accounting: off / location-tagged pair / company-wide' where key = 'acct_transfer_mode' and label_mix = 'Stock transfer এর accounting: off / location-tagged pair / company-wide';
  update public.rules set label_bn = 'পথে কম পৌঁছানো মাল (transit loss) journal-এ তোলা' where key = 'acct_transit_loss' and label_bn = 'পথে কম পৌঁছানো মাল (transit loss) journal এ তোলা';
  update public.rules set label_mix = 'Transit-এ কম পৌঁছানো stock journal-এ post করা' where key = 'acct_transit_loss' and label_mix = 'Transit এ কম পৌঁছানো stock journal এ post করা';
  update public.rules set label_mix = 'Transit loss কোন place-এর cost: receiver / sender' where key = 'acct_transit_loss_at' and label_mix = 'Transit loss কোন place এর cost: receiver / sender';
  update public.rules set label_bn = 'Purchase return-এর প্রাইসের পার্থক্য journal-এ তোলা' where key = 'acct_purchase_variance' and label_bn = 'Purchase return এর দামের পার্থক্য journal এ তোলা';
  update public.rules set label_mix = 'Purchase return-এর price variance journal-এ post করা' where key = 'acct_purchase_variance' and label_mix = 'Purchase return এর price variance journal এ post করা';
  update public.rules set label_bn = 'Stock movement journal-এর শুরুর ডেট (ফাঁকা = হিসাব শুরু থেকে)' where key = 'acct_stock_moves_from' and label_bn = 'Stock movement journal এর শুরুর তারিখ (ফাঁকা = হিসাব শুরু থেকে)';
  update public.rules set label_mix = 'Stock movement journal-এর start date (ফাঁকা = accounting start থেকে)' where key = 'acct_stock_moves_from' and label_mix = 'Stock movement journal এর start date (ফাঁকা = accounting start থেকে)';
  update public.rules set label_bn = 'হাতে লেখা journal-এর গার্ড: বন্ধ / চালু' where key = 'manual_journal_guard' and label_bn = 'হাতে লেখা journal এর পাহারা: বন্ধ / চালু';
  update public.rules set label_bn = 'কত দিনের বেশি পুরোনো অপেক্ষায় document-এ সতর্কতা' where key = 'acct_pending_alert_days' and label_bn = 'কত দিনের বেশি পুরোনো বাকি document এ সতর্কতা';
  update public.rules set label_mix = 'কত দিনের বেশি পুরোনো pending document-এ alert' where key = 'acct_pending_alert_days' and label_mix = 'কত দিনের বেশি পুরোনো pending document এ alert';
  -- ---------- manual_reason_codes85 ----------
  update public.manual_reason_codes85 set label_mix = 'আগের entry-এর correction' where code = 'correction' and label_mix = 'আগের entry এর correction';
  update public.manual_reason_codes85 set label_mix = 'অন্য account-এ reclass' where code = 'reclass' and label_mix = 'অন্য account এ reclass';
  update public.manual_reason_codes85 set label_mix = 'Auditor-এর adjustment' where code = 'audit_adjust' and label_mix = 'Auditor এর adjustment';
  update public.manual_reason_codes85 set label_bn = 'অন্য কারণ (note-এ লিখুন)' where code = 'other' and label_bn = 'অন্য কারণ (note এ লিখুন)';
  update public.manual_reason_codes85 set label_mix = 'অন্য reason (memo-তে লিখুন)' where code = 'other' and label_mix = 'অন্য reason (memo তে লিখুন)';
  -- ---------- rules ----------
  update public.rules set label_bn = 'মেয়াদ শেষ মাল বিক্রি: বন্ধ / warn / block' where key = 'expiry_sale_guard' and label_bn = 'মেয়াদোত্তীর্ণ মাল বিক্রি: বন্ধ / warn / block';
  update public.rules set label_bn = 'আগের ডেটের ক্রয় বিল পোস্ট হলে warning: বন্ধ / warn' where key = 'purchase_backdate_flag' and label_bn = 'আগের তারিখের ক্রয় bill পোস্ট হলে warning: বন্ধ / warn';
  update public.rules set label_bn = 'রিপোর্টে আইটেমের কস্ট কোথা থেকে: স্টক খাতার গড় / হাতে লেখা কস্ট / আগে স্টক খাতা, না থাকলে হাতে লেখা' where key = 'report_cost_source' and label_bn = 'রিপোর্টে পণ্যের খরচ কোথা থেকে: স্টক খাতার গড় / হাতে লেখা খরচ / আগে স্টক খাতা, না থাকলে হাতে লেখা';
  update public.rules set label_mix = 'Report-এ product cost কোথা থেকে: ledger average / হাতে লেখা item cost / আগে ledger, না থাকলে item cost' where key = 'report_cost_source' and label_mix = 'Report এ product cost কোথা থেকে: ledger average / হাতে লেখা item cost / আগে ledger, না থাকলে item cost';
  update public.rules set label_bn = 'ছবি তুলে বিল / তালিকা ঢোকানো (স্ক্যান)' where key = 'scan_enabled' and label_bn = 'ছবি তুলে বিল / তালিকা ঢোকানো (Scan)';
  update public.rules set label_bn = 'স্ক্যানের পাঠ-পদ্ধতি' where key = 'scan_engine' and label_bn = 'Scan-এর পাঠ-পদ্ধতি';
  update public.rules set label_bn = 'স্ক্যান: এর নিচে নিশ্চয়তা হলে সতর্কতা (আটকায় না)' where key = 'scan_min_confidence' and label_bn = 'Scan: এর নিচে নিশ্চয়তা হলে সতর্কতা (আটকায় না)';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'বিল / তালিকার ছবি তুলে ড্রাফট করা' where grant_code = 'scan_upload' and label_bn = 'বিল / তালিকার ছবি তুলে খসড়া করা';
  update public.grant_defs set label_bn = 'ছবি থেকে করা ড্রাফট কনফার্ম / বাতিল করা' where grant_code = 'scan_confirm' and label_bn = 'ছবি থেকে করা খসড়া Confirm / বাতিল করা';
  -- ---------- rules ----------
  update public.rules set label_bn = 'সেলের পর ইনভয়েস পর্দায় দেখানো: কখনো না / জিজ্ঞেস / সবসময়' where key = 'pos_show_invoice_after_sale' and label_bn = 'বিক্রির পর ইনভয়েস পর্দায় দেখানো: কখনো না / জিজ্ঞেস / সবসময়';
  update public.rules set label_mix = 'Sale-এর পর invoice screen-এ দেখানো: never / ask / always' where key = 'pos_show_invoice_after_sale' and label_mix = 'Sale এর পর invoice screen এ দেখানো: never / ask / always';
  update public.rules set label_bn = 'স্ক্যান: একটি ছবিতে AI কতবার পড়বে (সর্বোচ্চ)' where key = 'scan_ai_max_per_job' and label_bn = 'Scan: একটি ছবিতে AI কতবার পড়বে (সর্বোচ্চ)';
  update public.rules set label_bn = 'স্ক্যান: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (সর্বোচ্চ)' where key = 'scan_ai_max_per_user_day' and label_bn = 'Scan: একজন ২৪ ঘণ্টায় AI কতবার পড়াতে পারবে (সর্বোচ্চ)';
  update public.rules set label_bn = 'পুরোনো সময়ের বিক্রিতে স্টক-গার্ড কত ঘণ্টা পর্যন্ত ঢিলা' where key = 'offline_sale_max_age' and label_bn = 'পুরোনো সময়ের বিক্রিতে স্টক-পাহারা কত ঘণ্টা পর্যন্ত ঢিলা';
  update public.rules set label_bn = 'ইনভয়েস: নিজের সেল ছাড়া অন্যেরটা শুধু মালিক / POS approve দেখবে' where key = 'invoice_own_sales_only' and label_bn = 'ইনভয়েস: নিজের বিক্রি ছাড়া অন্যেরটা শুধু মালিক / POS approve দেখবে';
  update public.rules set label_bn = 'ক্যাশ ড্রয়ার: সেল সেভের আগে নাকি পরে' where key = 'cash_drawer_when' and label_bn = 'ক্যাশ ড্রয়ার: বিক্রি সেভের আগে নাকি পরে';
  update public.rules set label_mix = 'Cash drawer: sale save-এর আগে নাকি পরে' where key = 'cash_drawer_when' and label_mix = 'Cash drawer: sale save এর আগে নাকি পরে';
  update public.rules set label_mix = 'Cash drawer: "No sale" open-এ reason লাগবে' where key = 'cash_drawer_no_sale_requires_reason' and label_mix = 'Cash drawer: "No sale" open এ reason লাগবে';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'সেল ছাড়া ক্যাশ ড্রয়ার খোলা (No sale)' where grant_code = 'drawer_nosale' and label_bn = 'বিক্রি ছাড়া ক্যাশ ড্রয়ার খোলা (No sale)';
  -- ---------- rules ----------
  update public.rules set label_bn = 'কস্ট (কস্ট) ছাড়া পড়ে থাকা document কত দিন পর সতর্কতা (ফাঁকা = সতর্কতা বন্ধ)' where key = 'acct_cost_wait_alert_days' and label_bn = 'খরচ (cost) ছাড়া পড়ে থাকা document কত দিন পর সতর্কতা (ফাঁকা = সতর্কতা বন্ধ)';
  update public.rules set label_bn = 'Landed cost (মালের সাথে আসা কস্ট) যোগ করা: বন্ধ / হাতে / প্রতি বিল / প্রতি চালান' where key = 'landed_cost_mode' and label_bn = 'Landed cost (মালের সাথে আসা খরচ) যোগ করা: বন্ধ / হাতে / প্রতি বিল / প্রতি চালান';
  update public.rules set label_mix = 'Landed cost (মালের সাথে আসা cost) যোগ করা: off / manual / per bill / per shipment' where key = 'landed_cost_mode' and label_mix = 'Landed cost (মালের সাথে আসা খরচ) যোগ করা: off / manual / per bill / per shipment';
  update public.rules set label_bn = 'খরচ ভাগ করার ডিফল্ট পদ্ধতি: দাম / Qty / ওজন / আয়তন / হাতে % / সমান' where key = 'landed_alloc_default' and label_bn = 'খরচ ভাগ করার ডিফল্ট পদ্ধতি: দাম / পরিমাণ / ওজন / আয়তন / হাতে % / সমান';
  update public.rules set label_bn = 'Landed cost পোস্টের আগে অ্যাপ্রুভ: সতর্কতা / জরুরি' where key = 'landed_cost_requires_approval' and label_bn = 'Landed cost পোস্টের আগে অনুমোদন: সতর্কতা / বাধ্যতামূলক';
  -- ---------- grant_defs ----------
  update public.grant_defs set label_bn = 'Landed cost অ্যাপ্রুভ ও ভয়েড (void)' where grant_code = 'landed_approve' and label_bn = 'Landed cost অনুমোদন ও বাতিল (void)';
  -- ---------- rules ----------
  update public.rules set label_bn = 'cost bill সেভ করলে পেমেন্ট এন্ট্রি হবে কি?' where key = 'cost_bill_creates_payment' and label_bn = 'cost bill সেভ করলে payment এন্ট্রি হবে কি?';
  update public.rules set label_bn = 'purchase bill পোস্ট করলে পেমেন্ট এন্ট্রি হবে কি?' where key = 'purchase_bill_creates_payment' and label_bn = 'purchase bill পোস্ট করলে payment এন্ট্রি হবে কি?';
  update public.rules set label_bn = 'বিল ভয়েড হলে এই সুবিধায় লেখা পেমেন্টের কী হবে?' where key = 'bill_void_payment_mode' and label_bn = 'bill বাতিল হলে এই সুবিধায় লেখা payment-এর কী হবে?';
  update public.rules set label_mix = 'Credit-terms-এর পক্ষেও auto payment চলবে' where key = 'bill_pay_auto_credit_ok' and label_mix = 'Credit-terms এর পক্ষেও auto payment চলবে';
  update public.rules set label_bn = 'বড় বিলের সীমা (প্রস্তাবনার জন্য)' where key = 'bill_pay_large_amount' and label_bn = 'বড় bill-এর সীমা (প্রস্তাবনার জন্য)';
  update public.rules set label_mix = 'Large bill-এর সীমা (recommendation-এর জন্য)' where key = 'bill_pay_large_amount' and label_mix = 'Large bill এর সীমা (recommendation এর জন্য)';
  update public.rules set label_mix = 'Small cash bill-এর সীমা (recommendation-এর জন্য)' where key = 'bill_pay_small_cash_max' and label_mix = 'Small cash bill এর সীমা (recommendation এর জন্য)';
  update public.rules set label_bn = 'ইনবক্সে কাস্টমারের তথ্য ঢাকা' where key = 'inbox_pii_mode' and label_bn = 'inbox-এ গ্রাহকের তথ্য ঢাকা';
  update public.rules set label_mix = 'Inbox-এ customer-এর তথ্য ঢাকা' where key = 'inbox_pii_mode' and label_mix = 'Inbox এ customer এর তথ্য ঢাকা';
  update public.rules set label_bn = 'প্রতিটি আইটেমে ক্যাটাগরি / সাব-ক্যাটাগরি: বন্ধ / warn / লাগবেই' where key = 'category_required_on_item' and label_bn = 'প্রতিটি আইটেমে Category / Sub-category: বন্ধ / warn / লাগবেই';
  update public.rules set label_mix = 'Item-এর photo দেখানো' where key = 'item_images_mode' and label_mix = 'Item এর photo দেখানো';
  update public.rules set label_bn = 'Recipe ছাড়া সরাসরি production-in journal-এ তোলা' where key = 'acct_manual_prod_in103' and label_bn = 'Recipe ছাড়া সরাসরি production-in journal এ তোলা';
  update public.rules set label_mix = 'Recipe ছাড়া direct production-in journal-এ post করা' where key = 'acct_manual_prod_in103' and label_mix = 'Recipe ছাড়া direct production-in journal এ post করা';
  -- ---------- setup_check_defs81 ----------
  update public.setup_check_defs81 set label_bn = 'GRN মালের উৎস, guard বন্ধ, আর বিল-ও স্টক বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে' where code = 'flw_grn_double103' and label_bn = 'GRN মালের উৎস, guard বন্ধ, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে';
  update public.setup_check_defs81 set label_mix = 'GRN goods-এর source, guard off, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে' where code = 'flw_grn_double103' and label_mix = 'GRN goods এর source, guard off, আর bill-ও stock বাড়াচ্ছে: একই মাল দুবার গোনা হচ্ছে';
end $g$;

-- ---------------------------------------------------------------- phase109.sql
-- ============================================================
-- Phase 109 (bos109) - STEP Conc: fixes for the concurrency findings F1, F2, F4, F5, F6 of tests/sql/concurrency/CONCURRENCY_REPORT.md. Run AFTER phase103 (docs/PASTE_ORDER.md; 104..108 are reserved by other steps, this file does not need them).
--   Needs phases 72..103 pasted first (guard below). F3 (inbox_unmask) is NOT here: it is fixed by the security step (phase105).
--   Additive, paste-twice safe: every function is re-created from its LATEST body (taken from a build of docs/PASTE_ORDER.md incl. phase103); only lines tagged bos109 differ, every older bosNN tag is kept.
--   No table, column, trigger or privilege of an existing object is changed. One new rule (default OFF = today), one advisor row. Each create runs only if both guards passed (session flag phase109.ok).
--   F1 (high)  production_post: with the default rules (stock_negative_mode warn, production_short_mode refuse) N cooks on the same raw material all passed the shortage check and the balance went negative.
--              The balances of all ingredients / packaging AND the finished good are now row-locked in one item order before the check (select ... order by item_id for update).
--   F2 (high)  scan_confirm(p_post => true) saves a bill (foreign key = FOR KEY SHARE on the supplier row) and posts it in the same transaction (FOR UPDATE on the same row): two bills of one supplier deadlocked.
--              The supplier lock is now FOR NO KEY UPDATE in all 7 places that take it (post / void purchase, bill payment, pay / void supplier payment, supplier refund / void): it still excludes the other
--              posters (it conflicts with itself) but not the key-share lock of an insert.
--   F4 (med)   set_option_view_bulk / set_role_option_view_bulk upsert the keys sorted (by key, then by position): two owners sending the same keys in opposite order no longer deadlock.
--   F5 (low)   setup_recommend_apply: one apply at a time (transaction advisory lock after the client lock): a second tap with another client id sees the rules already set ('already'); each changed rule is applied and audited once.
--   F6 (med)   card_settle: NO change of behaviour by default. New rule card_settle_over_mode off | warn | refuse (default off). warn = the settlement is saved and a yellow exception 'card_settle_over' is logged when
--              gross > unsettled receivable (GL balance minus settlements saved but not yet booked); refuse = error over_settlement. Per-place advisory lock while the check is on. Advisor row recommends warn.
-- Tag: bos109.
-- ============================================================

do $g$ begin perform set_config('phase109.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._rec_value103(text,jsonb)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regprocedure('public._acct_docs(date)') is null then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if miss <> '' then
    raise exception 'phase109 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase109.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase, e.g. 104..108) is never overwritten: build a newer merge instead
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase109.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values    ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', array['bos72', 'bos73', 'bos74', 'bos80', 'bos109']::text[]),
    ('public._post_purchase_p13(uuid,jsonb)', array['bos82', 'bos87', 'bos109']::text[]),
    ('public._void_purchase_p13(uuid,text)', array['bos82', 'bos109']::text[]),
    ('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)', array['bos105', 'bos109', 'bos111']::text[]),   -- bos105 = phase105 (L4 client_id_reused); that body is NOT overwritten here, phase111 re-asserts the merge (105 + 109)
    ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', array['bos109']::text[]),
    ('public.void_supplier_payment(bigint,text)', array['bos109']::text[]),
    ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', array['bos109']::text[]),
    ('public.void_supplier_refund(bigint,text)', array['bos109']::text[]),
    ('public.set_option_view_bulk(uuid,jsonb,uuid)', array['bos109']::text[]),
    ('public.set_role_option_view_bulk(text,jsonb,uuid)', array['bos109']::text[]),
    ('public.setup_recommend_apply(uuid,text[],boolean,boolean)', array['bos103', 'bos109']::text[]),
    ('public.card_settle(integer,date,numeric,numeric,text,uuid,text)', array['bos109']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase109: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase109.ok', 'on', false);
end $g$;
-- the statements below run only when both guards passed

-- ---------- F6: new rule (default OFF = today's behaviour) + advisor row (recommends warn) ----------
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('card_settle_over_mode', 'books', 'choice', '"off"', null, '["off","warn","refuse"]'::jsonb, null, null,
  'Card settlement larger than the unsettled card receivable: off / warn / refuse', 'Card settlement larger than the unsettled card receivable: off / warn / refuse', 'Card settlement larger than the unsettled card receivable: off, warn or refuse',
  'off = as before (the settlement is saved and only the over flag in the answer shows it, counted on the booked balance). warn = saved, and a yellow exception is logged when it is more than the unsettled receivable, counting settlements saved but not yet booked. refuse = such a settlement is rejected with over_settlement.',
  'off = as before (the settlement is saved and only the over flag in the answer shows it, counted on the booked balance). warn = saved, and a yellow exception is logged when it is more than the unsettled receivable, counting settlements saved but not yet booked. refuse = such a settlement is rejected with over_settlement.', 980)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('card_settle_over_mode', 'card_settle_over_mode', '109', 'books', '"warn"', '{}'::text[],
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.',
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.',
  'Settling more than the card receivable still open makes the card account negative. With warn the settlement is saved and a yellow exception tells the owner; switch to refuse once the card settlements are routine. Nothing is blocked while warn is on.', 350)
on conflict do nothing;
end if; end $p109$;

-- public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
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
  -- bos109: lock every ingredient / packaging balance AND the finished-good balance of this place in ONE item order BEFORE the shortage check, so two cooks (or a cook and a sale)
  -- cannot both pass the check on the same stock, and the later stock_post calls never take a lock in another order (no lock-order deadlock between recipes)
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and (sbl.item_id = r.item_id or sbl.item_id in (select n2.item_id from public._recipe_need(r.id, p_batches, p_loc) n2)) order by sbl.item_id for update;   -- bos109
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
end $function$
$f$; end if; end $p109$;

-- public._post_purchase_p13(uuid,jsonb)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
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
end $function$
$f$; end if; end $p109$;

-- public._void_purchase_p13(uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
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
end $function$
$f$; end if; end $p109$;

-- public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)
-- (INT4) skipped when phase105 is already on it (tag bos105): this text was built before phase105 and would erase the L4 line. phase111 creates the merged body (bos105 + bos109).
do $p109$ begin if current_setting('phase109.ok', true) = 'on' and position('bos105' in pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure)) = 0 then execute $f$
CREATE OR REPLACE FUNCTION public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $function$
$f$; end if; end $p109$;

-- public.pay_supplier(uuid,integer,jsonb,uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.pay_supplier(p_supplier uuid, p_loc integer, p_payments jsonb, p_client uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := nullif(pay->>'amount', '')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
    if amt is null or not (amt between 0.01 and 999999999999) or round(amt, 2) <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  if not (tot between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  -- a re-sent request is answered before anything is locked or consumed, but only to someone who may see supplier money (or who made it)
  if p_client is not null then
    select created_by into dupby from public.supplier_payments where client_id = p_client order by id limit 1;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'pay_supplier:' || p_supplier::text, tot)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)           -- one payment at a time per supplier
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
  end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (p_supplier, p_loc, null, pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('paid', tot, 'balance', bal - tot);
end $function$
$f$; end if; end $p109$;

-- public.void_supplier_payment(bigint,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.void_supplier_payment(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.supplier_payments;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.supplier_payments where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(p.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', p.location_id) or public._use_em('purchase_void', p.location_id, 'void_payment:' || p_id::text, p.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)       -- one posting / payment / void at a time per supplier
  select * into p from public.supplier_payments where id = p_id for update;
  if p.voided then raise exception 'already void'; end if;
  if p.bill_id is not null then raise exception 'void_the_bill'; end if;     -- a payment made with a bill goes with the bill
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(p.location_id, 'supplier_payment_void', 'yellow', 'সাপ্লায়ার পেমেন্ট বাতিল: ' || left(btrim(p_note), 100), 'A supplier payment was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', p.amount);
end $function$
$f$; end if; end $p109$;

-- public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.supplier_refund(p_supplier uuid, p_loc integer, p_amount numeric, p_mode text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  perform 1 from public.suppliers where id = p_supplier for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_refunds where client_id = p_client) then return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier)); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if bal >= 0 or amt > -bal then raise exception 'refund_exceeds_credit'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.supplier_refunds (supplier_id, location_id, mode, wallet, ref, amount, reason_code, note, created_by, created_staff, client_id)
    values (p_supplier, p_loc, p_mode, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), amt, p_reason, left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  return jsonb_build_object('refunded', amt, 'balance', bal + amt);
end $function$
$f$; end if; end $p109$;

-- public.void_supplier_refund(bigint,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.void_supplier_refund(p_id bigint, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.supplier_refunds;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.supplier_refunds where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', r.location_id) or public._use_em('purchase_void', r.location_id, 'void_refund:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = r.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)
  select * into r from public.supplier_refunds where id = p_id for update;
  if r.voided then raise exception 'already void'; end if;
  perform public.lock_check((r.refunded_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_refunds set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(r.location_id, 'supplier_refund_void', 'yellow', 'সাপ্লায়ার রিফান্ড বাতিল: ' || left(btrim(p_note), 100), 'A supplier refund was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', r.amount);
end $function$
$f$; end if; end $p109$;

-- public.set_option_view_bulk(uuid,jsonb,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.set_option_view_bulk(p_user uuid, p_items jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'user_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select e.value from jsonb_array_elements(p_items) with ordinality e(value, ord) order by e.value->>'key', e.ord loop   -- bos109: one key order for every caller, so two bulk sets can never wait on each other in a circle
    r := public._ov_put_user(p_user, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('user_option_view', p_user::text, ch);
  res := jsonb_build_object('user_id', p_user, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'user_bulk', res);
  return res;
end $function$
$f$; end if; end $p109$;

-- public.set_role_option_view_bulk(text,jsonb,uuid)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.set_role_option_view_bulk(p_role text, p_items jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rp jsonb; it jsonb; r jsonb; ch jsonb := '[]'::jsonb; n int := 0; res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  rp := public._ov_replay(p_client, 'role_bulk'); if rp is not null then return rp; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 500 then raise exception 'too_many_items'; end if;
  for it in select e.value from jsonb_array_elements(p_items) with ordinality e(value, ord) order by e.value->>'key', e.ord loop   -- bos109: one key order for every caller, so two bulk sets can never wait on each other in a circle
    r := public._ov_put_role(p_role, it->>'key', it->>'mode'); n := n + 1;
    if (r->>'changed')::boolean then ch := ch || jsonb_build_array(r); end if;
  end loop;
  perform public._ov_audit('role_option_view', p_role, ch);
  res := jsonb_build_object('role_code', p_role, 'count', n, 'changed', jsonb_array_length(ch));
  perform public._ov_remember(p_client, 'role_bulk', res);
  return res;
end $function$
$f$; end if; end $p109$;

-- public.setup_recommend_apply(uuid,text[],boolean,boolean)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.setup_recommend_apply(p_client uuid, p_codes text[] DEFAULT NULL::text[], p_overwrite boolean DEFAULT false, p_ignore_ready boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d record; r public.rules; eff jsonb; applied jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; old_ jsonb; ex public.setup_apply_batches81; res jsonb; sid text;
        c record; cj jsonb; ready boolean; owr boolean; rv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_required'; end if;
  perform public._client_lock(p_client);
  perform pg_advisory_xact_lock(hashtextextended('setup_recommend_apply', 0));   -- bos109: one apply at a time; a second tap with another client id waits, then reads the rules already set ('already') - no rule is applied or audited twice
  select * into ex from public.setup_apply_batches81 where client_id = p_client;
  if found then return ex.result || jsonb_build_object('dup', true); end if;
  for d in select * from public.setup_rec_defs81 where active and (p_codes is null or code = any (p_codes)) order by sort, code loop
    rv := public._rec_value103(d.rule_key, d.rec_value);   -- bos103: purchase_grn_guard = skip when GRN is the stock source
    select * into r from public.rules where key = d.rule_key;
    if not found then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_installed'); continue; end if;
    if rv is null then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'no_recommendation'); continue; end if;
    eff := coalesce(r.value, r.default_value);
    if eff is not distinct from rv then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'already'); continue; end if;
    owr := r.value is not null;                       -- the owner already chose another value
    if owr and not (p_overwrite and p_codes is not null) then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'owner_chosen'); continue; end if;
    ready := true;
    if not p_ignore_ready then
      for c in select x.code from public.setup_check_defs81 x where x.code = any (d.ready_checks) and x.active loop
        cj := public._setup_chk81(c.code);
        if coalesce((cj->>'applies')::boolean, false) and coalesce((cj->>'n')::bigint, 0) > 0 then ready := false; end if;
      end loop;
    end if;
    if not ready then skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'not_ready'); continue; end if;
    begin
      perform public.set_rule(d.rule_key, rv);      -- validates the value by the rule's kind; the rules audit trigger logs it too
    exception when others then
      skipped := skipped || jsonb_build_object('code', d.code, 'reason', 'rejected', 'error', left(sqlerrm, 120)); continue;
    end;
    old_ := r.value;
    applied := applied || jsonb_build_object('code', d.code, 'rule_key', d.rule_key, 'old', old_, 'new', rv, 'overwrote', owr);
  end loop;
  res := jsonb_build_object('applied', applied, 'skipped', skipped, 'count', jsonb_array_length(applied));
  insert into public.setup_apply_batches81 (client_id, applied_by, overwrite, ignore_ready, result) values (p_client, auth.uid(), coalesce(p_overwrite, false), coalesce(p_ignore_ready, false), res);
  insert into public.setup_apply_lines81 (batch_id, code, rule_key, old_value, new_value, overwrote)
    select p_client, x->>'code', x->>'rule_key', case when jsonb_typeof(x->'old') = 'null' then null else x->'old' end, x->'new', (x->>'overwrote')::boolean from jsonb_array_elements(applied) x;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'setup_apply', 'setup_apply_batches81', p_client::text, jsonb_build_object('applied', applied, 'skipped_count', jsonb_array_length(skipped), 'overwrite', coalesce(p_overwrite, false), 'ignore_ready', coalesce(p_ignore_ready, false)));
  return res;
end $function$
$f$; end if; end $p109$;

-- public.card_settle(integer,date,numeric,numeric,text,uuid,text)
do $p109$ begin if current_setting('phase109.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.card_settle(p_loc integer, p_date date, p_gross numeric, p_fee numeric DEFAULT 0, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_bank_mode text DEFAULT 'bank'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.card_settlements85; sid text; t date := public._acct_today(); d date := coalesce(p_date, public._acct_today()); fee numeric := coalesce(p_fee, 0); bal numeric; omode text := coalesce(public.rule_txt('card_settle_over_mode'), 'off');   -- bos109
begin
  if not (public._acct_manage() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.card_settlements85 where client_id = p_client;
    if found then
      if c.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', c.id, 'dup', true);
    end if;
  end if;
  if p_gross is null or not (p_gross > 0 and p_gross <= 1000000000000) then raise exception 'bad_amount'; end if;
  if not (fee >= 0 and fee < p_gross) then raise exception 'bad_fee'; end if;
  if coalesce(p_bank_mode, 'bank') not in ('bank', 'mobile') then raise exception 'bad_mode'; end if;
  if d > t then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  if omode in ('warn', 'refuse') then perform pg_advisory_xact_lock(hashtextextended('card_settle:' || p_loc::text, 0)); end if;   -- bos109: one settlement per place at a time while the check is on
  select coalesce(sum(jl.debit - jl.credit), 0) into bal from public.journal_lines jl join public.acct_mappings m on m.account_id = jl.account_id and m.key = 'pay_card' where jl.location_id = p_loc;
  if omode in ('warn', 'refuse') then      -- bos109: rule card_settle_over_mode (default off = exactly the old behaviour above). The GL balance lags the books, so settlements saved but not yet booked are taken off it.
    bal := bal - coalesce((select sum(c2.gross) from public.card_settlements85 c2 where c2.location_id = p_loc and c2.status = 'done'
                            and not exists (select 1 from public.journal_entries e where e.source_type = 'card_settlement' and e.source_id = c2.id::text and e.reverses_id is null)), 0);
    if round(p_gross, 2) > bal then
      if omode = 'refuse' then raise exception 'over_settlement' using detail = 'unsettled ' || bal::text, hint = 'card_settle_over_mode'; end if;
      perform public._stock_exc(p_loc, 'card_settle_over', 'yellow', 'Card settlement ' || round(p_gross, 2)::text || ' is more than the unsettled card receivable ' || bal::text,
        'Card settlement ' || round(p_gross, 2)::text || ' is more than the unsettled card receivable ' || bal::text, null, d, 'ACCOUNTS', round(p_gross, 2));
    end if;
  end if;
  insert into public.card_settlements85 (client_id, location_id, settle_date, gross, fee, bank_mode, note, created_by, created_staff)
    values (p_client, p_loc, d, round(p_gross, 2), round(fee, 2), coalesce(p_bank_mode, 'bank'), left(nullif(btrim(p_note), ''), 300), auth.uid(), sid) returning * into c;
  return jsonb_build_object('id', c.id, 'unsettled', bal, 'over', round(p_gross, 2) > bal);
end $function$
$f$; end if; end $p109$;

-- ---------------------------------------------------------------- phase110.sql
-- ============================================================
-- Phase 110 - Performance step (audit: docs/briefs_p2p3/step_Perf_REPORT.md, review: tests/sql/perf/README.md)
-- Run AFTER phase103 (and after phase104..109 if they are used; this file is independent of them). Additive and idempotent: paste twice = no error, same result.
--
-- RUN AT A QUIET TIME. Every CREATE INDEX below holds a SHARE lock on its table while it builds: reads work, WRITES (sales, stock posts, audit rows) WAIT for it.
-- Measured on 184,000 ledger rows: 0.03 - 1.5 s per index; expect about 1-2 s per million stock_ledger rows and about 2.5 s per million audit_log rows.
-- No CONCURRENTLY (it cannot run inside the Supabase SQL editor). If the editor times out, run it again: finished indexes are skipped (IF NOT EXISTS).
--
-- Order of this file (on purpose): guard, then the 8 INDEXES FIRST (they alone fix inventory_vs_gl 22 s -> 0.5 s and unmatched_forms 25 s -> 0.2 s), then the function patches.
--
-- Why (year reports became 70-430x slower after phases 72-525, review PERF_REPORT):
--   * _cogs_lines72 / _item_cost_eff88: a one-row CTE calling _rcs88() was inlined into every use, so the cost-source rule was read ONCE PER ROW (143,000 calls for 30 days). AS MATERIALIZED evaluates it once.
--   * _cogs_lines72 joins stock_ledger on ref_id alone: the existing (ref_type, ref_id) index cannot serve it -> index 1.
--   * rpt_agg_sql called the plpgsql _line_cost88() for every fact row; now the cost of every (sale, item) pair is computed once, set-based (same rules, same numbers).
--   * inventory_vs_gl compared id::text with stock_ledger.ref_id for every ledger row (table scan per row) -> expression indexes. unmatched_forms: no index for (item, place, reason) -> index 2.
--   * _acct_docs (autopost tick every minute): the stock-move branch costed production / sale issue_out rows that can never be posted; they are skipped before the joins.
--   * inbox_list: the contact check ran 4x per row, now once per place (same output).
-- Results are identical to before (proved by tests/sql/perf/equality.sh and supabase/phase110_test.sql). Nothing is deleted; no table or column changes.
-- Functions re-created from their LATEST bodies (every bosNN tag kept): _cogs_lines72 (bos89), _item_cost_eff88, _rcs88, rpt_agg_sql (bos14, bos88), inbox_list (bos99, bos103), _acct_stock_moves85 (bos96, bos103). New tag bos110 on the four it alone owns; inbox_list and _acct_stock_moves85 carry the plain marker `perf110` (no bosNN tag), so phase103's body guard still accepts them.
-- Re-paste rule: a re-paste of phase103 (or of phase515, which re-creates _cogs_lines72) puts the older bodies of those functions back, results unchanged but slow: paste phase110 again after it.
-- If a later phase re-creates one of these six, merge its change into the phase110 text (or paste phase110 before it): the check before the patches stops the paste when a body carries a tag this file does not know.
-- ============================================================

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.opening_stock_followups103') is null then miss := miss || ' 103'; end if;
  if miss <> '' then
    raise exception 'phase110 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ============================ 1. INDEXES (first) ============================
-- 1. _cogs_lines72 (biz_daily, _p27_pl, biz_items) joins stock_ledger on ref_id alone: the (ref_type, ref_id) index cannot be used for it
create index if not exists stock_ledger_refid_idx on public.stock_ledger (ref_id, ref_type);
-- 2. unmatched_forms: "is there a ledger row for this item + place + reason" per form line (the existing (item_id, location_id, id) index walks every row of a big item)
create index if not exists stock_ledger_item_loc_reason_idx on public.stock_ledger (item_id, location_id, reason, made_at);
-- 3. inventory_vs_gl compares production_runs.id::text / purchase_bills.id::text with stock_ledger.ref_id (text): expression indexes turn the per-row table scan into a lookup
create index if not exists production_runs_idtext_idx on public.production_runs ((id::text));
create index if not exists purchase_bills_idtext_idx on public.purchase_bills ((id::text));
-- 4. the autopost stock-move scan (_acct_stock_moves85, every minute) asks for the rows of 7 reasons since the accounting window. Without this index the planner takes index 2 above for it and reads that
--    whole index on every tick (about 2x slower here and growing with the ledger); with it the scan costs about what the window holds and no more. (Added after measuring index 2: see the Perf report.)
create index if not exists stock_ledger_reason_made_idx on public.stock_ledger (reason, made_at);
-- 5. items_with_cost / _item_cost_eff88 take the last positive-cost ledger row of every item (order by id desc limit 1): one probe per item
create index if not exists stock_ledger_lastcost_idx on public.stock_ledger (item_id, id desc) where coalesce(unit_cost, 0) > 0 and qty_delta > 0;
-- 6. audit_log had only its primary key: the item-history popup (table_name + record_id, newest first) and pii_exposure_report94 (action = 'view') scanned the whole table
create index if not exists audit_log_tbl_rec_id_idx on public.audit_log (table_name, record_id, id desc);
create index if not exists audit_log_view_at_idx on public.audit_log (table_name, at) where action = 'view';

analyze public.stock_ledger;
analyze public.production_runs;
analyze public.purchase_bills;
analyze public.audit_log;

-- ============================ 2. FUNCTION PATCHES ============================
-- Stop (before changing anything) when a function carries a bosNN tag this file does not know, i.e. a newer phase changed it: merge that change into the text below first.
do $c$
declare r record; src text; t text; bad text := '';
begin
  for r in select * from (values
    ('public._cogs_lines72(date,date,integer[])', array['bos80','bos88','bos89','bos110']),
    ('public._item_cost_eff88()', array['bos110']),
    ('public._rcs88()', array['bos110']),
    ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', array['bos14','bos88','bos110']),
    ('public.inbox_list(integer,text,integer)', array['bos99','bos103']),
    ('public._acct_stock_moves85(date)', array['bos96','bos103'])) v(fn, known)
  loop
    select p.prosrc into src from pg_proc p where p.oid = to_regprocedure(r.fn);
    if src is null then bad := bad || ' ' || r.fn || ' (missing)'; continue; end if;
    for t in select distinct m[1] from regexp_matches(src, '(bos[0-9]+)', 'g') m loop
      if not t = any (r.known) then bad := bad || ' ' || r.fn || ' has ' || t || ';'; end if;
    end loop;
  end loop;
  if bad <> '' then
    raise exception 'phase110 stopped: a function it re-creates was changed by a phase it does not know (merge that change into phase110 first):%', bad;
  end if;
end $c$;

-- P1  _cogs_lines72 (bos89 merge of bos80 + bos88): the one-row rule CTE is MATERIALIZED (evaluated once, not once per row)
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
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
$function$
;

-- P4  _item_cost_eff88 (behind items_with_cost and biz_items): same defect, the rule was read once per item
CREATE OR REPLACE FUNCTION public._item_cost_eff88()
 RETURNS TABLE(item_id uuid, cost_price numeric, src text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with m as materialized (select public._rcs88() as m),   -- bos110: once, not once per item
  lg as (
    select b.item_id as iid,
           coalesce(sum(b.qty * b.avg_cost) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0) / nullif(sum(b.qty) filter (where b.qty > 0 and coalesce(b.avg_cost, 0) > 0), 0),
                    (select l.unit_cost from public.stock_ledger l where l.item_id = b.item_id and coalesce(l.unit_cost, 0) > 0 and l.qty_delta > 0 order by l.id desc limit 1)) as c
    from public.stock_balance b group by b.item_id),
  ic as (select x.item_id as iid, x.cost_price as c from public.item_costs x where x.cost_price is not null)
  select z.iid, z.cp, z.s from (
    select coalesce(lg.iid, ic.iid) as iid,
           case m.m when 'item_costs' then ic.c when 'ledger_avg' then lg.c else coalesce(lg.c, ic.c) end as cp,
           case m.m when 'item_costs' then 'item_costs' when 'ledger_avg' then 'ledger' else (case when lg.c is not null then 'ledger' else 'item_costs' end) end as s
    from lg full join ic on ic.iid = lg.iid cross join m) z
  where z.cp is not null;
$function$
;

-- P5a _rcs88: one rules lookup instead of two rule_txt() -> rule_val() chains. Same answer for every setting, including an unknown or empty value (-> ledger_then_item_costs)
CREATE OR REPLACE FUNCTION public._rcs88()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos110: same answer as before (rules.value, else default_value; anything unknown or empty = ledger_then_item_costs), one rules lookup instead of two rule_txt() -> rule_val() chains
  select coalesce((select case when x.v in ('ledger_avg', 'item_costs', 'ledger_then_item_costs') then x.v else 'ledger_then_item_costs' end
                     from (select nullif(coalesce(r.value, r.default_value) #>> '{}', '') as v from public.rules r where r.key = 'report_cost_source') x),
                  'ledger_then_item_costs') $function$
;

-- P5b rpt_agg_sql: the line-report cost (cogs, gp, ...) is joined set-based per (sale, item) instead of calling _line_cost88() for every fact row. Same cost per pair (ledger cost of the sale's own rows when all carry a cost,
--      else the list cost, else null; all three report_cost_source modes). _line_cost88 itself is unchanged (other callers keep it).
CREATE OR REPLACE FUNCTION public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text, p_dexpr text, p_ws integer, p_fym integer, p_mobok boolean, p_nodim boolean, p_withcost boolean)
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
  if p_withcost then
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
end $function$
;

-- P2  inbox_list (bos99 + bos103; marker perf110, NOT a bos tag: phase103's body guard owns this function): the contact check and the PII mode once per call/place; output identical
CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    with lo as materialized (select x as id, public._inb_contact_ok(x) as ok from unnest(l) x),   -- perf110: the contact check once per place, not four times per row
         pm as materialized (select public._inb_pii_mode99() as m)
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when lo.ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when lo.ok then public._inb_pii_f99('name', m.customer_name) end,   /* bos99 */
      'text', case when lo.ok then left(public._inb_pii_f99('text', m.msg_text), 200) /* bos103: mask first, cut after */ end, 'masked', not lo.ok, 'pii_mode', pm.m) j   /* bos99 */
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id join lo on lo.id = m.location_id cross join pm
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$
;

-- P3  _acct_stock_moves85 (bos96 + bos103; marker perf110, NOT a bos tag: phase103's body guard owns this function): production / sale issue_out rows never get a class (cls is null) but were joined and costed first; skipped before the joins. Output identical
CREATE OR REPLACE FUNCTION public._acct_stock_moves85(p_start date)
 RETURNS TABLE(lid bigint, cls text, d date, loc integer, qty numeric, rev boolean, nocost boolean, amt numeric, ikey text, xkey text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with cfg as (select public.rule_on('acct_count_adjust') a, public.rule_on('acct_stock_opening') o, public.rule_on('acct_issue_out') i,
                      coalesce(public.rule_txt('acct_transfer_mode'), 'off') = 'location_tagged' x, greatest(p_start, coalesce(public._acct_from85(), p_start)) f,
                      public.rule_on('acct_manual_prod_in103') p /* bos103 */),
  m as (
    select l.id, l.location_id, l.qty_delta, l.reason = 'reversal' rv, it.item_type, (l.made_at at time zone 'Asia/Dhaka')::date d,
           case coalesce(o.reason, l.reason)
             when 'count_adjust' then 'adjust' when 'opening' then 'opening'
             when 'issue_out' then case when coalesce(o.ref_type, l.ref_type) in ('issue', 'entry') then 'issue' end
             when 'transfer_out' then 'xfer' when 'transfer_in' then 'xfer'
             when 'production_in' then case when not exists (select 1 from public.production_runs pr where pr.id::text = coalesce(o.ref_id, l.ref_id)) then 'prodin' end /* bos103: direct production-in, no recipe run */ end cls,
           case when coalesce(l.unit_cost, 0) > 0 then l.unit_cost
                when l.reason = 'transfer_in' then (select s.unit_cost from public.stock_ledger_eff96 s where s.reason = 'transfer_out' and s.ref_type is not distinct from l.ref_type
                                                      and s.ref_id is not distinct from l.ref_id and s.item_id = l.item_id and coalesce(s.unit_cost, 0) > 0 order by s.id limit 1) end c
    from public.stock_ledger_eff96 l join public.items it on it.id = l.item_id left join public.stock_ledger o on o.id = l.reverses_id /* bos96 */
    where l.reason in ('count_adjust', 'opening', 'issue_out', 'transfer_out', 'transfer_in', 'reversal', 'production_in') /* bos103 */
      and not (l.reason = 'issue_out' and l.reverses_id is null and coalesce(l.ref_type, '') not in ('issue', 'entry'))   -- perf110: a production / sale issue_out never gets a class (cls is null below): skip it before the costing
      and l.made_at >= ((p_start::timestamp at time zone 'Asia/Dhaka') - interval '2 days'))
  select m.id, m.cls, m.d, m.location_id, m.qty_delta, m.rv, m.c is null, round(abs(m.qty_delta) * coalesce(m.c, 0), 2), public._acct_inv_key(m.item_type),
         case m.cls when 'adjust' then 'stock_adjust' when 'opening' then 'stock_opening_equity' when 'issue' then 'stock_issue_use' when 'prodin' then 'overhead_absorbed' /* bos103 */ else 'interloc_clearing' end
  from m cross join cfg
  where m.cls is not null and m.d >= cfg.f
    and not (m.cls = 'opening' and exists (select 1 from public.opening_covered103 a where m.id = any (a.covered_ids) and (a.location_id is null or a.location_id = m.location_id))) /* bos96: an opening that a decision of the opening-stock helper covers is not posted twice */
    and ((m.cls = 'adjust' and cfg.a) or (m.cls = 'opening' and cfg.o) or (m.cls = 'issue' and cfg.i) or (m.cls = 'xfer' and cfg.x) or (m.cls = 'prodin' and cfg.p))
    and (m.c is null or round(abs(m.qty_delta) * m.c, 2) >= 0.01);
$function$
;

-- ---------------------------------------------------------------- phase111.sql
-- ============================================================
-- Phase 111 (bos111) - STEP INT4: re-asserts the merged body of the one function that two of the phases 104..109 both re-create.
--   Why: phase109 (concurrency) was built before phase105 (security 2) existed. Both re-create public._bp_pay99(...): 105 adds the L4 line
--   `client_id_reused` (tag bos105), 109 changes the supplier lock to FOR NO KEY UPDATE (tag bos109). Built from a fresh database in the order
--   72..103, 104, 105, 106, 107, 108, 109 (tests/sql/tag_loss_check.sh) the diff of pg_get_functiondef + bosNN tags after every phase showed exactly one such function.
--   phase109 (as shipped in INT4) leaves a body that carries bos105 untouched; this file then creates the 3-way merge: base = phase103 body, + bos105 line, + bos109 line.
--   Needs phases 72..109 pasted first (guard below). phase110 (performance) may come before or after this file: it re-creates none of the functions here and this file none of its six, so the guard does not require it (canonical order 109, 110, 111; the owner may also paste 111 first and 110 later).
--   Additive, paste-twice safe: one function re-created, no table, rule, data, privilege or trigger. Goes LAST. Tag: bos111.
--   Body guard: a live body with a tag this file does not know is never overwritten.
-- ============================================================

do $g$ begin perform set_config('phase111.ok', 'off', false); end $g$;
do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._rec_value103(text,jsonb)'),
    ('104', 'public.dash_layout_get()'), ('105', 'public._bp_auto_ok105(text,text,integer)'), ('106', 'public.backup_coverage106()'),
    ('107', 'public.client_error_log(text,jsonb)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regprocedure('public._acct_docs(date)') is null then miss := miss || ' 98'; end if;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if not exists (select 1 from public.rules where key = 'card_settle_over_mode') then miss := miss || ' 109'; end if;
  if miss <> '' then
    raise exception 'phase111 needs phases 72..109 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase111.ok', 'guard1', false);
end $g$;

do $g$
declare d text; t text[];
begin
  if current_setting('phase111.ok', true) is distinct from 'guard1' then return; end if;
  d := pg_get_functiondef('public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)'::regprocedure);
  select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
  if t is not null and not (t <@ array['bos105', 'bos109', 'bos111']::text[]) then
    raise exception 'phase111: _bp_pay99 carries tags this file does not know (%); build a newer merge instead of overwriting it', t;
  end if;
  perform set_config('phase111.ok', 'on', false);
end $g$;

-- public._bp_pay99(text,text,text,numeric,text,uuid,text,boolean)  = phase103 body + bos105 (L4 client_id_reused) + bos109 (supplier lock FOR NO KEY UPDATE)
do $p111$ begin if current_setting('phase111.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._bp_pay99(p_kind text, p_ref text, p_mode text, p_amount numeric, p_origin text, p_client uuid, p_note text, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- bos111: merge of bos105 (L4 client_id_reused) and bos109 (supplier lock FOR NO KEY UPDATE)
declare cb public.cost_source_bills; cs public.cost_sources; pb public.purchase_bills; q public.quick_expenses; loc int; rem numeric; paid_sum numeric; amt numeric; warns text[];
        sid text; mtype text; mref text; today date := public._bp_today99(); open_amt numeric; bid bigint; ex public.bill_payments99;
begin
  if p_kind not in ('cost', 'purchase') then raise exception 'bad_kind'; end if;
  if p_origin not in ('auto', 'ask') then raise exception 'bad_value'; end if;
  if p_ref is null or (p_kind = 'cost' and p_ref !~ '^[0-9]{1,18}$') or (p_kind = 'purchase' and p_ref !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_ref'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.bill_payments99 where client_id = p_client;
    if found and (ex.bill_kind <> p_kind or ex.bill_ref <> p_ref) then raise exception 'client_id_reused'; end if;   -- bos105 (L4): a known id of ANOTHER bill is never answered "paid"
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ex.id, 'amount', ex.amount); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_kind = 'cost' then
    select * into cb from public.cost_source_bills where id = p_ref::bigint for update;
    if not found then raise exception 'not_found'; end if;
    if cb.status <> 'active' then raise exception 'bill_void'; end if;
    select * into cs from public.cost_sources where id = cb.source_id;
    select min(location_id) into loc from public.cost_source_locs where source_id = cb.source_id;
    if loc is null then raise exception 'no_location'; end if;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'other') then raise exception 'bad_mode'; end if;
    select coalesce(sum(amount), 0) into paid_sum from public.bill_payments99 where bill_kind = 'cost' and bill_ref = p_ref and status in ('active', 'kept_credit');
    rem := cb.amount - paid_sum;
  else
    select * into pb from public.purchase_bills where id = p_ref::uuid;
    if not found then raise exception 'not_found'; end if;
    perform 1 from public.suppliers where id = pb.supplier_id for no key update;   -- bos109 (was: for update; the row lock must not conflict with the key-share lock of a bill / payment insert in the same transaction)                 -- one posting / payment / void at a time per supplier
    select * into pb from public.purchase_bills where id = p_ref::uuid for update;
    if pb.status <> 'posted' or pb.kind <> 'bill' then raise exception 'bill_not_posted'; end if;
    loc := pb.location_id;
    if p_mode is null or p_mode not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    select o.open_amt into open_amt from public._sup_open(pb.supplier_id) o where o.bill_id = pb.id;
    rem := least(coalesce(open_amt, 0), pb.total - pb.paid);
  end if;
  if rem <= 0.004 then raise exception 'nothing_due'; end if;
  amt := round(coalesce(p_amount, rem), 2);
  if amt is null or amt <= 0 or amt > 1000000000000 then raise exception 'bad_amount'; end if;
  if amt > rem + 0.004 then raise exception 'overpaid'; end if;
  warns := public._bp_dup99(p_kind, p_ref, amt);
  if coalesce(array_length(warns, 1), 0) > 0 and not coalesce(p_confirm, false) then
    return jsonb_build_object('ok', false, 'needs_confirm', true, 'warnings', to_jsonb(warns), 'remaining', rem);
  end if;
  if p_kind = 'cost' then
    if p_mode = 'other' then
      mtype := 'note_only';                                                              -- no cash / bank / mobile movement: not in the cash book, not in the journal
    else
      perform public.path_guard('expense', loc, 'a');                                    -- the owner may have made the 10-2 form the record here
      perform public.lock_check(today);
      insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
        values (p_client, loc, today, public._bp_head99(cs.cost_type), left(nullif(btrim(coalesce(cs.provider, '')), ''), 120), amt, p_mode, cb.bill_no is not null,
                left('cost bill #' || cb.id::text || coalesce(' ' || cb.bill_no, ''), 300), auth.uid(), sid) returning * into q;
      perform public.shadow_link_add('expense', loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
      mtype := 'quick_expense'; mref := q.id::text;
    end if;
  else
    perform public.lock_check(today);
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (pb.supplier_id, pb.location_id, pb.id, p_mode, null, null, amt, left(coalesce(nullif(btrim(p_note), ''), 'bill payment (option)'), 200), auth.uid(), sid, p_client)
      returning id::text into mref;
    update public.purchase_bills set paid = paid + amt where id = pb.id;
    mtype := 'supplier_payment';
  end if;
  insert into public.bill_payments99 (bill_kind, bill_ref, location_id, mode, amount, origin, money_type, money_ref, note, client_id, created_by, created_staff)
    values (p_kind, p_ref, loc, p_mode, amt, p_origin, mtype, mref, left(nullif(btrim(p_note), ''), 300), p_client, auth.uid(), sid) returning id into bid;
  return jsonb_build_object('ok', true, 'id', bid, 'amount', amt, 'remaining', rem - amt, 'money_type', mtype, 'money_ref', mref,
                            'counted', mtype <> 'note_only', 'warnings', to_jsonb(warns));
end $function$
$f$; end if; end $p111$;

-- ---------------------------------------------------------------- phase112.sql
-- ============================================================
-- Phase 112 (bos112) - BATCH 1a "profit truth": ONE net-profit figure for the shop P&L and the dashboard tile; returns netted in biz_items; shared bills pro-rated by days.
--   Source: docs/audit2/A3_real_profit.md gaps G1 (one figure), G2 (sheet salary vs payroll app, no double count), G3 (wastage / expiry loss), G4 (card fees),
--   G5 (unknown-cost revenue + provisional flag), G6 (shared bills inside the branch result), G7 (unallocated shared bills visible), G8 (one-day report showed the whole month's bills), G9 (returns in biz_items).
--   Needs phases 72..111 pasted first (guard below). Additive, paste-twice safe. NOTHING changes by default: three new rules, all default off = today's behaviour; three advisor rows recommend on.
--     profit_truth_mode        off | on   on = _r3q_l3_shop_pnl (the shop P&L report) returns the rows of _pnl_truth112 (one figure per place: sales with a known cost - cost of goods - expenses
--                                         - salary (paper sheet 02-2 OR payroll app, never both) - wastage - card fees - fixed cost - attributed shared bills; unallocated bills as their own row)
--                                         and the dashboard tile "Net profit" reads profit_truth112 and shows when the figure is provisional.
--     cost_share_prorate_mode  off | on   on = the cost-bill shares of a month are taken pro rata for the days of the report range (a one-day report shows 1/30 of a monthly bill, not all of it).
--     items_net_of_returns     off | on   on = biz_items (and biz_items_by_category, dashboard top items) subtract returns (revenue, quantity, cost), like the margin report.
--   New functions: _c78_rows112, _pl_extra112, _pnl_truth112 (internal), profit_truth112 (RPC, owner / cost right + accounts view). Re-created: _c78_rows (wrapper), _r3q_l3_shop_pnl, biz_items (tag bos112 kept next to bos72 / bos78 / bos88 / bos14).
--   NOT changed on purpose: acct_income_statement and the journal (the books keep their own definition), partner_calculate (a payout base is never changed silently), the report builder item_sales
--   (separate fact view, see the report), printed forms 05-3 / 05-4 / 10-2 (never auto-changed).
--   Body guard: a live body with a tag this file does not know is never overwritten. Tag: bos112.
-- ============================================================

do $g$ begin perform set_config('phase112.ok', 'off', false); end $g$;
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._c78_rows(date,date)') is null then miss := miss || ' 78'; end if;
  if to_regprocedure('public._p27_pl(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._p27_src72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._cogs_lines72(date,date,integer[])') is null then miss := miss || ' 72'; end if;
  if to_regprocedure('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)') is null then miss := miss || ' 89'; end if;
  if to_regprocedure('public.biz_items(date,date,integer)') is null or to_regprocedure('public._rcs88()') is null then miss := miss || ' 88'; end if;
  if to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.payroll_payments') is null then miss := miss || ' 50'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if not exists (select 1 from public.rules where key = 'card_settle_over_mode') then miss := miss || ' 109'; end if;
  if miss <> '' then
    raise exception 'phase112 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase112.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase112.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._c78_rows(date,date)', array['bos112']::text[]),
    ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', array['bos72', 'bos78', 'bos112']::text[]),
    ('public.biz_items(date,date,integer)', array['bos14', 'bos88', 'bos112']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase112: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase112.ok', 'on', false);
end $g$;

-- ---------- 1. rules (default off = today) + advisor rows ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_truth_mode', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'একটাই সত্যিকারের নিট লাভ (দোকান P&L ও ড্যাশবোর্ড): বন্ধ / চালু', 'একটাই সত্যিকারের Net profit (Shop P&L ও Dashboard): off / on', 'One true net profit (shop P&L and dashboard tile): off or on',
  'বন্ধ = আগের মতো। চালু = দোকান P&L ও ড্যাশবোর্ডের "নিট লাভ" একই হিসাবে চলে: খরচ-জানা বিক্রি - মালের খরচ - খরচ - বেতন (কাগজের শিট অথবা পেরোল অ্যাপ, দুটো একসাথে নয়) - নষ্ট মাল - কার্ড ফি - নির্দিষ্ট খরচ - ভাগ করা বিল। ভাগ না-করা বিল আলাদা সারিতে দেখায়। খরচ-না-জানা বিক্রি আলাদা দেখায় এবং অঙ্কটি "অস্থায়ী" চিহ্নিত হয়।',
  'off = আগের মতো। on = Shop P&L ও Dashboard-এর "Net profit" একই হিসাবে চলে: খরচ-জানা বিক্রি - মালের খরচ - খরচ - বেতন (কাগজের শিট অথবা payroll app, দুটো একসাথে নয়) - নষ্ট মাল - card fee - fixed খরচ - ভাগ করা বিল। ভাগ না-করা বিল আলাদা সারিতে দেখায়। খরচ-না-জানা বিক্রি আলাদা দেখায়, অঙ্কটি "provisional" চিহ্নিত হয়।',
  'off = as before (the shop P&L ignores wastage, card fees, app payroll and shared bills; the dashboard tile shows the books figure). on = the shop P&L and the Net profit tile use ONE figure: sales with a known cost minus cost of goods, expenses, salary (paper sheet OR payroll app, never both), wastage, card fees, fixed cost and attributed shared bills. Unallocated shared bills show as their own row. Sales whose cost is unknown are shown apart and the figure is marked provisional.', 984),
 ('cost_share_prorate_mode', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ভাগ করা মাসিক বিল দিন অনুপাতে: বন্ধ / চালু', 'ভাগ করা মাসিক বিল দিন অনুপাতে: off / on', 'Shared monthly bills pro rata by days: off or on',
  'বন্ধ = আগের মতো (এক দিনের রিপোর্টেও পুরো মাসের বিল দেখায়)। চালু = রিপোর্টের তারিখ-সীমার দিন অনুযায়ী মাসিক বিলের অংশ দেখায় (৩০ দিনের মাসে ১ দিন = ১/৩০)।',
  'off = আগের মতো (এক দিনের report-এও পুরো মাসের bill দেখায়)। on = report-এর তারিখ-সীমার দিন অনুযায়ী মাসিক bill-এর অংশ দেখায় (৩০ দিনের মাসে ১ দিন = ১/৩০)।',
  'off = as before (a one-day report shows the whole month''s bills). on = a monthly bill share is taken for the days of the report range only (1 day of a 30-day month = 1/30). Full-month reports are unchanged.', 985),
 ('items_net_of_returns', 'reports', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'আইটেম রিপোর্টে ফেরত বাদ: বন্ধ / চালু', 'Item report-এ return বাদ: off / on', 'Item reports net of returns: off or on',
  'বন্ধ = আগের মতো (সেরা বিক্রির আইটেম ও ক্যাটাগরি রিপোর্টে ফেরত ধরা হয় না)। চালু = ফেরতের টাকা, পরিমাণ ও খরচ বাদ যায়, যেমন মার্জিন রিপোর্টে। "ফেরত বাদ দিয়ে রিপোর্ট" চালু থাকলে তবেই কাজ করে।',
  'off = আগের মতো (সেরা বিক্রির Item ও Category report-এ return ধরা হয় না)। on = return-এর টাকা, পরিমাণ ও খরচ বাদ যায়, যেমন margin report-এ। "Report net of returns" চালু থাকলে তবেই কাজ করে।',
  'off = as before (top items and category reports ignore returns). on = returned revenue, quantity and cost are subtracted, like the margin report. Works only while the rule "reports net of returns" is on.', 986)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('profit_truth_mode', 'profit_truth_mode', '112', 'reports', '"on"', '{}'::text[],
  'আজ চারটি আলাদা "লাভ" আছে এবং একই তথ্যে মেলে না। চালু করলে দোকান P&L ও ড্যাশবোর্ড একই নিট লাভ দেখায়। সিদ্ধান্ত মালিকের।',
  'আজ চারটি আলাদা "profit" আছে এবং একই তথ্যে মেলে না। on করলে Shop P&L ও Dashboard একই Net profit দেখায়। সিদ্ধান্ত owner-এর।',
  'Today four different profit figures exist and they disagree on the same data. With this on, the shop P&L and the dashboard tile show one net profit that includes wastage, card fees, payroll and shared bills, and say when it is provisional. The owner decides.', 360),
 ('cost_share_prorate_mode', 'cost_share_prorate_mode', '112', 'reports', '"on"', '{}'::text[],
  'চালু করলে এক দিনের বা এক সপ্তাহের রিপোর্টে মাসিক বিলের শুধু সেই দিনের অংশ আসে। সিদ্ধান্ত মালিকের।',
  'on করলে এক দিনের বা এক সপ্তাহের report-এ মাসিক bill-এর শুধু সেই দিনের অংশ আসে। সিদ্ধান্ত owner-এর।',
  'With this on, a one-day or one-week report carries only that many days of a monthly shared bill instead of the whole month. Full-month reports do not change. The owner decides.', 361),
 ('items_net_of_returns', 'items_net_of_returns', '112', 'reports', '"on"', '{}'::text[],
  'চালু করলে সেরা বিক্রির আইটেম ও ক্যাটাগরির হিসাবে ফেরত বাদ যায়, ফলে বেশি-ফেরত-হওয়া পণ্য সেরা দেখায় না। সিদ্ধান্ত মালিকের।',
  'on করলে সেরা বিক্রির Item ও Category-র হিসাবে return বাদ যায়, ফলে বেশি-return-হওয়া পণ্য সেরা দেখায় না। সিদ্ধান্ত owner-এর।',
  'With this on, top-item and category figures subtract returns, so a product that is returned a lot no longer ranks first. The owner decides.', 362)
on conflict do nothing;
end if; end $p112$;

-- ---------- 2. shared bills: the same rows as before, optionally pro rata by days ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._c78_rows112(p_from date, p_to date, p_pro boolean)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: the body of _c78_rows (bos78) with one more factor: p_pro = the days of the range inside the month / days of the month (1 for a full month, and for an open range)
  select z.mth, z.share_id, z.bill_id, z.code, z.cost_type, z.tbn, z.ten, z.share_loc, z.share_dest,
         case when p_pro and p_from is not null and p_to is not null
              then round(z.amt * greatest((least(p_to, (z.mth + interval '1 month')::date - 1) - greatest(p_from, z.mth) + 1), 0)::numeric / ((z.mth + interval '1 month')::date - z.mth), 4)
              else z.amt end,
         d.dkind, d.dloc, d.via
    from (
      select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.id share_id, b.id bill_id, s.code, s.cost_type,
             t.label_bn tbn, coalesce(t.label_en, t.label_bn) ten, sh.location_id share_loc, sh.dest share_dest, (case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
        from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id join public.cost_source_types t on t.code = s.cost_type
        cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
       where sh.active and sh.kind = 'share' and sh.dest in ('showroom', 'admin') and b.status = 'active') z
    cross join lateral public._c78_dest(z.share_id, z.mth) d
   where z.mth between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31');
$function$
$f$; end if; end $p112$;

do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._c78_rows(p_from date, p_to date)
 RETURNS TABLE(mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text, share_loc integer, share_dest text, amount numeric, dkind text, dloc integer, via text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112: same rows as before; rule cost_share_prorate_mode = on takes a monthly share pro rata for the days of the range (default off = the whole month, as before)
  select * from public._c78_rows112(p_from, p_to, coalesce(public.rule_txt('cost_share_prorate_mode'), 'off') = 'on');
$function$
$f$; end if; end $p112$;

-- ---------- 3. what the branch P&L never had: wastage, card fees, payroll-app salary, shadow sheets ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._pl_extra112(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_loc integer, o_wastage numeric, o_wastage_unk integer, o_fees numeric, o_sal_app numeric, o_sal_shadow numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112. Wastage / expiry loss = stock written off at the real ledger cost (the same query the journal uses for account 5100); card fee = fee of the settlements in the range (as the journal's 5810);
  -- salary of the payroll app = payments (cash basis, like the journal) of runs that are NOT a shadow copy of a paper sheet; sheet salary of a sheet that IS a shadow of an app run is taken out again (it would count twice).
  with w as (
    select x.location_id as loc, sum(c.amt) as amt, count(*) filter (where c.amt is null or c.amt <= 0)::int as unk
    from public.stock_wastage x
    cross join lateral (select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) as amt
                          from public.stock_ledger_eff96 l where l.ref_type = 'wastage' and l.ref_id = x.id::text and l.reason = 'wastage') c
    where (x.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and x.location_id = any (locs) group by 1),
  f as (
    select c.location_id as loc, sum(c.fee) as amt from public.card_settlements85 c
    where c.status = 'done' and c.settle_date between d1 and d2 and c.location_id = any (locs) group by 1),
  pa as (
    select p.location_id as loc, sum(p.amount + r.rec) as amt
    from public.payroll_payments p
    cross join lateral (select case when l.advance_recovery > 0 and l.net > 0 then least(round(l.advance_recovery * p.amount / l.net, 2), l.advance_recovery) else 0 end as rec
                          from public.payroll_lines l where l.id = p.line_id) r
    where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) and p.pay_date between d1 and d2 and p.location_id = any (locs) group by 1),
  ss as (
    select e.location_id as loc,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and public.is_shadow('entries', e.id::text)
      and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1),
  k as (select loc from w union select loc from f union select loc from pa union select loc from ss)
  select k.loc, coalesce(w.amt, 0), coalesce(w.unk, 0), coalesce(f.amt, 0), coalesce(pa.amt, 0), coalesce(ss.amt, 0)
  from k left join w on w.loc = k.loc left join f on f.loc = k.loc left join pa on pa.loc = k.loc left join ss on ss.loc = k.loc;
$function$
$f$; end if; end $p112$;

-- ---------- 4. ONE figure per place: the rows of the shop P&L when profit_truth_mode = on ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._pnl_truth112(d1 date, d2 date, locs integer[])
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos112. profit = sales WITH a known cost - cost of goods - expenses - salary - fixed cost - wastage - card fees - attributed shared bills.
  -- Sales whose cost is unknown are NOT counted at cost 0: they are shown as uncosted_rev, and profit_if_uncosted_free is the figure if they really cost nothing.
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  sx as (select o_loc, sum(o_cogs_fallback) fb, sum(o_unknown_rev) unk from public._p27_src72(d1, d2, locs) group by o_loc),
  x as (select * from public._pl_extra112(d1, d2, locs)),
  rws as (select * from public._c78_rows112(d1, d2, true)),
  sh as (select r.dloc as o_loc, round(sum(r.amount), 2) as amt from rws r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1),
  k as (select o_loc from a union select o_loc from x union select o_loc from sh),
  b as (
    select k.o_loc, coalesce(a.net, 0) net, coalesce(a.costed, 0) costed, coalesce(a.cogs, 0) cogs, a.ex, a.fx,
           case when a.sal is not null or x.o_sal_app is not null then coalesce(a.sal, 0) - coalesce(x.o_sal_shadow, 0) + coalesce(x.o_sal_app, 0) end as sal,
           coalesce(x.o_sal_app, 0) sal_app, coalesce(x.o_wastage, 0) wst, coalesce(x.o_wastage_unk, 0) wst_unk, coalesce(x.o_fees, 0) fee, coalesce(sh.amt, 0) shr,
           coalesce(sx.fb, 0) fb, coalesce(sx.unk, 0) unk
    from k left join a on a.o_loc = k.o_loc left join x on x.o_loc = k.o_loc left join sh on sh.o_loc = k.o_loc left join sx on sx.o_loc = k.o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(b.net, 2), 'cogs', round(b.cogs, 2), 'costed_rev', round(b.costed, 2),
    'uncosted_rev', round(greatest(b.net - b.costed, 0), 2),
    'cogs_fallback', b.fb, 'unknown_cost_rev', b.unk,
    'uncosted_pct', case when b.net > 0 then round(100 * greatest(b.net - b.costed, 0) / b.net, 2) end,
    'expenses', round(b.ex, 2), 'salary', round(b.sal, 2), 'salary_app', round(b.sal_app, 2), 'fixed', b.fx,
    'wastage', round(b.wst, 2), 'wastage_unknown_cost', b.wst_unk, 'card_fees', round(b.fee, 2), 'overheads_attributed', round(b.shr, 2),
    'profit', round(b.costed - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr, 2),
    'profit_if_uncosted_free', round(b.net - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr, 2),
    'profit_pct', case when b.costed > 0 then round(100 * (b.costed - b.cogs - coalesce(b.ex, 0) - coalesce(b.sal, 0) - coalesce(b.fx, 0) - b.wst - b.fee - b.shr) / b.costed, 2) end,
    'row_type', 'truth',
    'gaps', nullif(concat_ws(', ', case when b.ex is null then 'expenses' end, case when b.sal is null then 'salary' end, case when b.fx is null then 'fixed' end,
                              case when b.net > b.costed + 0.004 then 'cogs(uncosted)' end, case when b.wst_unk > 0 then 'wastage(cost unknown)' end), ''))
  from b join public.locations l on l.id = b.o_loc
  union all  -- shared bills nobody is charged with (no attribution setting, or the main centre has no place): their own row, so the total is complete
  select jsonb_build_object('location_id', null, 'location_bn', 'ভাগ না-করা শেয়ার্ড খরচ', 'location_en', 'Unallocated shared costs',
    'expenses', round(u.amt, 2), 'unallocated', round(u.amt, 2), 'profit', -round(u.amt, 2), 'row_type', 'unallocated')
  from (select sum(r.amount) amt from rws r where (r.dkind = 'unallocated' or r.dloc is null) and r.share_loc = any (locs)) u
  where u.amt is not null and u.amt > 0;
$function$
$f$; end if; end $p112$;

-- ---------- 5. the shop P&L report: today's rows unless profit_truth_mode = on ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
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
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), '')) as x
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
$function$
$f$; end if; end $p112$;

-- ---------- 6. the RPC: one company figure with its completeness ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.profit_truth112(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare locs int[]; rws jsonb; co jsonb; un numeric := 0; unc numeric := 0; wu int := 0; np numeric := 0; npf numeric := 0; prov boolean; notes jsonb := '[]'::jsonb;
begin   -- bos112
  if not (public.biz_ok() and public.biz_cost_ok() and public._acct_view()) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  select coalesce(jsonb_agg(t), '[]'::jsonb) into rws from public._pnl_truth112(p_from, p_to, locs) t;
  select coalesce(sum((t ->> 'profit')::numeric), 0), coalesce(sum((t ->> 'profit_if_uncosted_free')::numeric), 0), coalesce(sum((t ->> 'uncosted_rev')::numeric), 0),
         coalesce(sum((t ->> 'wastage_unknown_cost')::int), 0), coalesce(sum((t ->> 'unallocated')::numeric), 0)
    into np, npf, unc, wu, un from jsonb_array_elements(rws) t;
  -- the unallocated row has no profit_if_uncosted_free: it costs the same in both figures
  npf := npf + coalesce((select sum((t ->> 'profit')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'unallocated'), 0);
  prov := unc > 0.004 or un > 0.004 or wu > 0;
  if unc > 0.004 then notes := notes || jsonb_build_array('uncosted_revenue'); end if;
  if un > 0.004 then notes := notes || jsonb_build_array('unallocated_shared_costs'); end if;
  if wu > 0 then notes := notes || jsonb_build_array('wastage_cost_unknown'); end if;
  co := jsonb_build_object(
    'net_sales', coalesce((select sum((t ->> 'net_sales')::numeric) from jsonb_array_elements(rws) t), 0),
    'costed_rev', coalesce((select sum((t ->> 'costed_rev')::numeric) from jsonb_array_elements(rws) t), 0),
    'cogs', coalesce((select sum((t ->> 'cogs')::numeric) from jsonb_array_elements(rws) t), 0),
    'expenses', coalesce((select sum((t ->> 'expenses')::numeric) from jsonb_array_elements(rws) t where t ->> 'row_type' = 'truth'), 0),
    'salary', coalesce((select sum((t ->> 'salary')::numeric) from jsonb_array_elements(rws) t), 0),
    'fixed', coalesce((select sum((t ->> 'fixed')::numeric) from jsonb_array_elements(rws) t), 0),
    'wastage', coalesce((select sum((t ->> 'wastage')::numeric) from jsonb_array_elements(rws) t), 0),
    'card_fees', coalesce((select sum((t ->> 'card_fees')::numeric) from jsonb_array_elements(rws) t), 0),
    'overheads_attributed', coalesce((select sum((t ->> 'overheads_attributed')::numeric) from jsonb_array_elements(rws) t), 0),
    'unallocated', un, 'uncosted_rev', unc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'mode', coalesce(public.rule_txt('profit_truth_mode'), 'off'),
    'company', co || jsonb_build_object('net_profit', round(np, 2), 'net_profit_if_uncosted_free', round(npf, 2)),
    'rows', rws, 'provisional', prov, 'incomplete', notes);
end $function$
$f$; end if; end $p112$;

-- ---------- 7. biz_items: returns netted (rule items_net_of_returns) ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.biz_items(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
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
  by_item0 as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
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
    left join by_item b on b.iid = i.id left join cg g on g.iid = i.id
    where (i.is_active and i.sellable) or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, round(r.cg, 2), r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $function$
$f$; end if; end $p112$;

-- ---------- 8. privileges ----------
do $p112$ begin if current_setting('phase112.ok', true) = 'on' then
  revoke all on function public._c78_rows112(date, date, boolean), public._pl_extra112(date, date, integer[]), public._pnl_truth112(date, date, integer[]) from public, anon, authenticated;
  revoke all on function public.profit_truth112(date, date, integer) from public, anon;
  grant execute on function public.profit_truth112(date, date, integer) to authenticated;
end if; end $p112$;

-- ---------------------------------------------------------------- phase113.sql
-- ============================================================
-- Phase 113 (bos113) - BATCH 1b "books truth": the drawer shortage reaches the books, advances stop being collected twice, closed periods stop being silent,
--   the day book agrees with the journal, a bank statement fee can be posted from the statement line.
--   Source: docs/audit2/A4_cash_accounting_reconciliation.md gaps G01 (drawer shortage / overage never posted; account 5800 unused), G03 (customer_dues ignores the advance already used, new list function customer_dues_net113; a collection after the advance
--   clears the debt twice), G04 (owner changes a closed period without trace; the scheduler skips late documents silently), G05 (day book vs journal: 10-2 voucher paid by bank shown as cash, card fee missing),
--   G08 (a bank statement line without a ledger entry has no action), G06 (card over-settlement: the option card_settle_over_mode from phase109 is the guard; this phase only tests it).
--   Needs phases 72..111 pasted first (guard below). Additive, paste-twice safe. NOTHING changes by default: six new rules, all default off = today's behaviour, six advisor rows recommend a value.
--     drawer_short_post        off | on    on = a submitted / approved drawer count (form 14-1) with a difference posts "cash short / over" (Dr 5800 Cr cash; over: the reverse); the day book shows the same row.
--     dues_net_advance         off | on    on = collect_payment refuses a collection above what is still due after the advance already applied (cash move "advance used"), and the app reads the dues list from customer_dues_net113 (customer_dues itself is not changed).
--     period_lock_owner_mode   off | warn  warn = the owner can still change a closed period (as before) but a yellow exception "closed_period_owner" is written (once per date and day).
--     period_lock_late_warn    off | on    on = acct_post_pending (the scheduler) logs a yellow exception "late_docs_locked" when documents were skipped because their date is in a closed period, and returns locked_docs.
--     daybook_align_mode       off | on    on = the day book reads the pay mode of a 10-2 voucher (bank / mobile / card) like the journal and shows the card fee of a card settlement (bank side).
--     bank_stmt_post_on        off | on    on = bank_stmt_post113(line, 'fee' | 'interest') posts the statement line (Dr 5810 / Cr bank, or Dr bank / Cr 4900) and matches it in one step.
--   New: mapping key cash_short -> account 5800 (if missing), RPC bank_stmt_post113. New: customer_dues_net113 (list net of the advance used). Re-created (tag bos113 next to the older tags): _acct_docs, acct_post_pending, _daybook_lines, collect_payment, lock_check. customer_dues stays as phase105 left it (so a re-paste of 103 + 105 still works).
--   NOT changed on purpose: the journal of any existing document, sale_return / void_sale (a void of a settled card sale is still a manual job), printed forms 05-3 / 05-4 / 10-2, the owner bypass in lock_check by default.
--   Body guard: a live body with a tag this file does not know is never overwritten. Tag: bos113.
-- ============================================================

do $g$ begin perform set_config('phase113.ok', 'off', false); end $g$;
do $g$
declare miss text := '';
begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public.acct_post_pending(boolean,integer)') is null then miss := miss || ' 98'; end if;
  if to_regprocedure('public._daybook_lines(integer[],integer[],date,date)') is null then miss := miss || ' 50'; end if;
  if to_regprocedure('public.customer_dues()') is null or to_regprocedure('public.collect_payment(uuid,integer,uuid,jsonb,text)') is null then miss := miss || ' 12'; end if;
  if to_regprocedure('public._cust_pii103(text,text)') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public.lock_check(date)') is null then miss := miss || ' 6'; end if;
  if to_regprocedure('public._a53_match1(bigint,bigint,integer,text,text)') is null or to_regclass('public.bank_statement_lines') is null then miss := miss || ' 53'; end if;
  if to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null then miss := miss || ' 18'; end if;
  if to_regclass('public.entry_counts') is null or to_regclass('public.card_settlements85') is null then miss := miss || ' 85'; end if;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if not exists (select 1 from public.rules where key = 'card_settle_over_mode') then miss := miss || ' 109'; end if;
  if miss <> '' then
    raise exception 'phase113 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
  perform set_config('phase113.ok', 'guard1', false);
end $g$;

-- BODY GUARD: a live body with a tag this file does not know (a newer phase) is never overwritten
do $g$
declare d text; t text[]; r record;
begin
  if current_setting('phase113.ok', true) is distinct from 'guard1' then return; end if;
  for r in select * from (values
    ('public._acct_docs(date)', array['bos50', 'bos52', 'bos72', 'bos74', 'bos80', 'bos85', 'bos89', 'bos96', 'bos97', 'bos98', 'bos103', 'bos113']::text[]),
    ('public.acct_post_pending(boolean,integer)', array['bos72', 'bos85', 'bos113']::text[]),
    ('public._daybook_lines(integer[],integer[],date,date)', array['bos50', 'bos113']::text[]),
    ('public.collect_payment(uuid,integer,uuid,jsonb,text)', array['bos113']::text[]),
    ('public.lock_check(date)', array['bos113']::text[])) v(sig, known)
  loop
    d := pg_get_functiondef(r.sig::regprocedure);
    select array_agg(distinct x[1]) into t from regexp_matches(d, 'bos[0-9]+', 'g') x;
    if t is not null and not (t <@ r.known) then
      raise exception 'phase113: % carries tags this file does not know (%); build a newer merge instead of overwriting it', r.sig, t;
    end if;
  end loop;
  perform set_config('phase113.ok', 'on', false);
end $g$;

-- ---------- 1. rules (default off = today) + advisor rows + the cash short / over mapping ----------
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('drawer_short_post', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ক্যাশ গণনার কম / বেশি হিসাব খাতায় তোলা: বন্ধ / চালু', 'Cash count-এর কম / বেশি হিসাব খাতায় তোলা: off / on', 'Post the drawer count difference to the books: off or on',
  'বন্ধ = আগের মতো (কম / বেশি শুধু লাল-হলুদ সতর্কতা, হিসাব খাতার ক্যাশ আসল ক্যাশের চেয়ে বেশি থাকে)। চালু = জমা দেওয়া ফর্ম ১৪-১ গণনায় কম বা বেশি থাকলে "ক্যাশ কম / বেশি" (৫৮০০) এন্ট্রি হয় এবং ডে-বুকে সেই সারি আসে।',
  'off = আগের মতো (কম / বেশি শুধু লাল-হলুদ সতর্কতা, books-এর cash আসল cash-এর চেয়ে বেশি থাকে)। on = submit করা Form 14-1 count-এ কম বা বেশি থাকলে "Cash short / over" (5800) entry হয় এবং Day book-এ সেই row আসে।',
  'off = as before (the difference is only the yellow / red flag and the books keep more cash than the till holds). on = a submitted or approved drawer count (form 14-1) with a difference posts Cash short / over (5800) and the day book shows the same row. A form that stops being final is reversed.', 987),
 ('dues_net_advance', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'বাকির তালিকায় ও আদায়ে আগে-নেওয়া অগ্রিম বাদ: বন্ধ / চালু', 'Dues list ও collection-এ ব্যবহৃত advance বাদ: off / on', 'Dues list and collection net of the advance already used: off or on',
  'বন্ধ = আগের মতো (অগ্রিম দিয়ে শোধ করা বাকিও তালিকায় দেখায়, আবার আদায় করলে দুইবার শোধ হয়)। চালু = বাকির তালিকা ও আদায় থেকে ব্যবহৃত অগ্রিম বাদ যায়।',
  'off = আগের মতো (advance দিয়ে শোধ করা due-ও list-এ দেখায়, আবার collect করলে দুইবার শোধ হয়)। on = Dues list ও collection থেকে ব্যবহৃত advance বাদ যায়।',
  'off = as before (a due already paid off with an advance still shows and can be collected a second time). on = the dues list (customer_dues_net113) and collect_payment subtract the advance already applied to bills.', 988),
 ('period_lock_owner_mode', 'books', 'choice', '"off"', null, '["off","warn"]'::jsonb, null, null,
  'বন্ধ হিসাবকালে মালিকের পরিবর্তন: বন্ধ / warn', 'বন্ধ period-এ owner-এর পরিবর্তন: off / warn', 'Owner changes inside a closed period: off or warn',
  'বন্ধ = আগের মতো (মালিক বাধা ছাড়াই লিখতে পারেন, কোনো চিহ্ন থাকে না)। warn = মালিক তবুও পারেন, কিন্তু হলুদ সতর্কতা লেখা হয় (প্রতি তারিখ ও দিনে একবার)।',
  'off = আগের মতো (owner বাধা ছাড়াই লিখতে পারেন, কোনো চিহ্ন থাকে না)। warn = owner তবুও পারেন, কিন্তু yellow exception লেখা হয় (প্রতি date ও দিনে একবার)।',
  'off = as before (the owner can write into a closed period and nothing is left behind). warn = the owner still can, and a yellow exception closed_period_owner is written (once per date and day). Nobody else is affected: they are still refused.', 989),
 ('period_lock_late_warn', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'বন্ধ হিসাবকালে আটকে-থাকা নথির সতর্কতা: বন্ধ / চালু', 'বন্ধ period-এ আটকে-থাকা document-এর warning: off / on', 'Warn about documents the scheduler could not book (closed period): off or on',
  'বন্ধ = আগের মতো (শুধু গোনা হয়)। চালু = হলুদ সতর্কতা "late_docs_locked" লেখা হয় এবং উত্তরে তালিকা (locked_docs) আসে।',
  'off = আগের মতো (শুধু গোনা হয়)। on = yellow exception "late_docs_locked" লেখা হয় এবং result-এ list (locked_docs) আসে।',
  'off = as before (they are only counted). on = a yellow exception late_docs_locked is written and the result lists them (locked_docs). The documents stay unbooked until the period is reopened.', 990),
 ('daybook_align_mode', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ডে-বুক হিসাব খাতার সাথে মেলানো: বন্ধ / চালু', 'Day book হিসাব খাতার সাথে মেলানো: off / on', 'Day book follows the journal: off or on',
  'বন্ধ = আগের মতো। চালু = ১০-২ ভাউচার ব্যাংক / মোবাইলে দিলে ডে-বুকেও তাই দেখায় (এখন সবই ক্যাশ), এবং কার্ড সেটেলমেন্টের ফি ব্যাংক দিকে আসে।',
  'off = আগের মতো। on = Voucher 10-2 bank / mobile-এ দিলে Day book-এও তাই দেখায় (এখন সবই cash), এবং card settlement-এর fee bank দিকে আসে।',
  'off = as before. on = a 10-2 voucher paid by bank or mobile shows with that mode in the day book (today every voucher is cash) and the card fee of a settlement leaves the bank side. daybook_vs_journal then shows no difference for these kinds.', 991),
 ('bank_stmt_post_on', 'books', 'choice', '"off"', null, '["off","on"]'::jsonb, null, null,
  'ব্যাংক স্টেটমেন্ট লাইন থেকে ফি / সুদ এন্ট্রি: বন্ধ / চালু', 'Bank statement line থেকে fee / interest entry: off / on', 'Post bank fee / interest from a statement line: off or on',
  'বন্ধ = আগের মতো (মিলানো না-যাওয়া লাইনের জন্য হাতে জার্নাল লিখতে হয়)। চালু = ব্যাংক মেলানোর পর্দায় "ফি" বা "সুদ" বেছে এক ধাপে এন্ট্রি ও মিল হয়। "ব্যাংক মেলানো" চালু থাকা লাগবে।',
  'off = আগের মতো (মেলে-না এমন line-এর জন্য হাতে journal লিখতে হয়)। on = Bank reconciliation-এ "fee" বা "interest" বেছে এক ধাপে entry ও match হয়। "Bank reconciliation" চালু থাকা লাগবে।',
  'off = as before (an unmatched statement line needs a manual journal). on = bank_stmt_post113 posts the line (fee: Dr bank charges 5810 / Cr bank; interest: Dr bank / Cr other income 4900) and matches it in one step. Needs the rule bank_recon_on.', 992)
on conflict (key) do nothing;
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('drawer_short_post', 'drawer_short_post', '113', 'books', '"on"', '{}'::text[],
  'ক্যাশ কম হলে হিসাব খাতার ক্যাশ ও আসল ক্যাশ আলাদা হয়ে যায়। চালু করলে কম / বেশি খরচ হিসেবে খাতায় ওঠে। সিদ্ধান্ত মালিকের।',
  'Cash কম হলে books-এর cash ও আসল cash আলাদা হয়ে যায়। on করলে কম / বেশি খাতায় ওঠে। সিদ্ধান্ত owner-এর।',
  'When a till is short, the cash in the books stays higher than the real cash. With this on the difference is posted (cash short / over) so the books agree with the count. The owner decides.', 363),
 ('dues_net_advance', 'dues_net_advance', '113', 'books', '"on"', '{}'::text[],
  'অগ্রিম দিয়ে শোধ হওয়া বাকি তালিকায় থাকলে একই টাকা দুইবার আদায় হতে পারে। চালু করলে তা আর দেখায় না। সিদ্ধান্ত মালিকের।',
  'Advance দিয়ে শোধ হওয়া due list-এ থাকলে একই টাকা দুইবার collect হতে পারে। on করলে তা আর দেখায় না। সিদ্ধান্ত owner-এর।',
  'A due already paid with an advance stays on the list and can be collected twice. With this on it no longer shows and cannot be collected again. The owner decides.', 364),
 ('period_lock_owner_mode', 'period_lock_owner_mode', '113', 'books', '"warn"', '{}'::text[],
  'বন্ধ হিসাবকালে মালিকের লেখা এখন নিঃশব্দ। warn করলে বাধা না দিয়ে হলুদ সতর্কতা লেখা থাকে। সিদ্ধান্ত মালিকের।',
  'বন্ধ period-এ owner-এর লেখা এখন নিঃশব্দ। warn করলে বাধা না দিয়ে yellow exception লেখা থাকে। সিদ্ধান্ত owner-এর।',
  'Today the owner can change a closed period without any trace. With warn nothing is blocked but a yellow exception is left behind. The owner decides.', 365),
 ('period_lock_late_warn', 'period_lock_late_warn', '113', 'books', '"on"', '{}'::text[],
  'স্বয়ংক্রিয় পোস্টিং বন্ধ হিসাবকালের নথি বাদ দিলে এখন কেউ জানে না। চালু করলে হলুদ সতর্কতা আসে। সিদ্ধান্ত মালিকের।',
  'Auto posting বন্ধ period-এর document বাদ দিলে এখন কেউ জানে না। on করলে yellow exception আসে। সিদ্ধান্ত owner-এর।',
  'When the automatic posting skips documents of a closed period nobody is told. With this on a yellow exception says how many. The owner decides.', 366),
 ('daybook_align_mode', 'daybook_align_mode', '113', 'books', '"on"', '{}'::text[],
  'ডে-বুক ও হিসাব খাতার ক্যাশ / ব্যাংক এক না হলে মালিক দুই রকম অঙ্ক দেখেন। চালু করলে মিলে যায়। সিদ্ধান্ত মালিকের।',
  'Day book ও books-এর cash / bank এক না হলে owner দুই রকম অঙ্ক দেখেন। on করলে মিলে যায়। সিদ্ধান্ত owner-এর।',
  'When the day book and the books show different cash and bank figures the owner reads two numbers. With this on they agree for vouchers paid by bank and for the card fee. The owner decides.', 367),
 ('bank_stmt_post_on', 'bank_stmt_post_on', '113', 'books', '"on"', '{}'::text[],
  'ব্যাংক ফি স্টেটমেন্টে থাকে কিন্তু হিসাব খাতায় নেই। চালু করলে এক ধাপে এন্ট্রি হয়। সিদ্ধান্ত মালিকের।',
  'Bank fee statement-এ থাকে কিন্তু books-এ নেই। on করলে এক ধাপে entry হয়। সিদ্ধান্ত owner-এর।',
  'A bank fee shows on the statement but not in the books. With this on it is posted from the statement line in one step. The owner decides.', 368)
on conflict do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select 'cash_short', a.id, 'ক্যাশ কম / বেশি', 'Cash short / over' from public.coa_accounts a where a.code = '5800'
  on conflict (key) do nothing;
end if; end $p113$;

-- public._acct_docs(date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
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
end $function$
$f$; end if; end $p113$;

-- public.acct_post_pending(boolean,integer)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.acct_post_pending(p_dry boolean DEFAULT false, p_limit integer DEFAULT 1500)
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
  for d in select * from public._acct_docs(st) order by 3, 1, 2 loop
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
end $function$
$f$; end if; end $p113$;

-- public._daybook_lines(integer[],integer[],date,date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public._daybook_lines(p_locs integer[], p_sal integer[], p_from date, p_to date)
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
  select e.location_id, e.entry_date, 'out', case when coalesce(public.rule_txt('daybook_align_mode'), 'off') = 'on' then (case e.data ->> 'pay_mode' when 'mobile' then 'mobile' when 'bank' then 'bank' when 'card' then 'bank' else 'cash' end) else 'cash' end /* bos113: how the voucher was paid, as the journal reads it */, 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)
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
$function$
$f$; end if; end $p113$;

-- public.customer_dues_net113()
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.customer_dues_net113()
 RETURNS TABLE(id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- bos113: customer_dues() with the advance already applied to bills (cash move "advance used") taken off. Rows, mobile masking and rights come from customer_dues() itself (phase105 owns it);
  -- the oldest open sale date is recomputed on the same running total as customer_dues, with the advance counted as a payment.
  with b as (select * from public.customer_dues()),
  adv as (select m.customer_id as cid, sum(m.amount) as a from public.cash_moves m where m.kind = 'cust_advance_used' and m.status = 'done' and m.customer_id is not null group by 1),
  s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id in (select b2.id from b b2)),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select b.id, b.name, b.mobile, b.type, b.credit_limit, b.balance - coalesce(adv.a, 0),
         (select min(k.sale_date) from cum k where k.customer_id = b.id and k.cr > (coalesce(t.rem, 0) - b.balance) + coalesce(adv.a, 0))
  from b left join adv on adv.cid = b.id left join t on t.customer_id = b.id
  where b.balance - coalesce(adv.a, 0) > 0
  order by 6 desc;
$function$
$f$; end if; end $p113$;

-- public.collect_payment(uuid,integer,uuid,jsonb,text)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.collect_payment(p_client uuid, p_loc integer, p_customer uuid, p_payments jsonb, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform 1 from public.customers where id = p_customer for update;      -- one collection at a time per customer
  if not found then raise exception 'customer_not_found'; end if;
  if p_client is not null and exists (select 1 from public.sale_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public.customer_balance(p_customer)); end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay->>'mode'; amt := (pay->>'amount')::numeric;
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    tot := tot + round(amt, 2);
  end loop;
  bal := coalesce(public.customer_balance(p_customer), 0);
  if coalesce(public.rule_txt('dues_net_advance'), 'off') = 'on' then   -- bos113: what an advance already paid off is not collected again
    bal := greatest(bal - coalesce((select sum(m.amount) from public.cash_moves m where m.customer_id = p_customer and m.kind = 'cust_advance_used' and m.status = 'done'), 0), 0);
  end if;
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),
              left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot);
end $function$
$f$; end if; end $p113$;

-- public.lock_check(date)
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.lock_check(p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v text; d date; om text;
begin
  if p_date is null then return; end if;
  if public.is_owner() then
    om := coalesce(public.rule_txt('period_lock_owner_mode'), 'off');   -- bos113: warn = the owner may still change a closed period (as before) but it is written down as a yellow exception
    if om <> 'warn' then return; end if;
    v := public.rule_txt('period_closed_until');
    if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
    begin d := v::date; exception when others then return; end;
    if p_date > d then return; end if;
    if not exists (select 1 from public.exceptions x where x.flag_code = 'closed_period_owner' and x.entry_date = p_date and x.created_at > now() - interval '1 day') then
      perform public._stock_exc((select min(l.id) from public.locations l), 'closed_period_owner', 'yellow', 'মালিক বন্ধ হিসাবকালে (' || p_date::text || ') পরিবর্তন করেছেন',
        'The owner changed a closed period (date ' || p_date::text || ')', null, p_date, 'ACCOUNTS', null);
    end if;
    return;
  end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $function$
$f$; end if; end $p113$;

-- ---------- bank statement line -> journal entry + match (rule bank_stmt_post_on) ----------
do $p113$ begin if current_setting('phase113.ok', true) = 'on' then execute $f$
CREATE OR REPLACE FUNCTION public.bank_stmt_post113(p_line bigint, p_kind text, p_loc integer DEFAULT NULL::integer, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.bank_statement_lines; st date := public._acct_start(); amt numeric; ln jsonb; eid bigint; r public.journal_entries; memo text;
begin   -- bos113
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if coalesce(public.rule_txt('bank_stmt_post_on'), 'off') <> 'on' then raise exception 'switch_off: bank_stmt_post_on'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_kind is null or p_kind not in ('fee', 'interest') then raise exception 'bad_kind'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into s from public.bank_statement_lines where id = p_line for update;
  if not found then raise exception 'not found'; end if;
  perform public._a53_bank_acct(s.account_id);                                         -- only a cash / bank account (child of 1100)
  if (p_kind = 'fee' and s.amount >= 0) or (p_kind = 'interest' and s.amount <= 0) then raise exception 'wrong_sign'; end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;
  if exists (select 1 from public.journal_entries where source_type = 'bank_stmt_line' and source_id = p_line::text and reverses_id is null) then raise exception 'already_posted'; end if;
  if s.line_date < st then raise exception 'before_start'; end if;
  perform public.lock_check(s.line_date);
  amt := abs(s.amount);
  ln := public._acct_resolve(case p_kind
    when 'fee' then jsonb_build_array(jsonb_build_object('account_id', s.account_id, 'credit', amt), jsonb_build_object('a', 'bank_charges', 'debit', amt))
    else jsonb_build_array(jsonb_build_object('account_id', s.account_id, 'debit', amt), jsonb_build_object('code', '4900', 'credit', amt)) end, p_loc);
  if p_dry then return jsonb_build_object('dry', true, 'date', s.line_date, 'kind', p_kind, 'amount', amt, 'lines', jsonb_array_length(ln)); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.journal_entries where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  memo := case p_kind when 'fee' then 'Bank charge from statement ' else 'Bank interest from statement ' end || s.line_date::text;
  eid := public._acct_write(s.line_date, p_loc, 'bank_stmt_line', p_line::text, p_kind, memo, null, ln, null, p_client);
  perform public._a53_match1(p_line, eid, 1, 'manual', coalesce(nullif(btrim(p_note), ''), 'posted from the statement line'));
  return jsonb_build_object('id', eid, 'kind', p_kind, 'amount', amt, 'matched', true);
end $function$
$f$; end if; end $p113$;

do $p113$ begin if current_setting('phase113.ok', true) = 'on' then
  revoke all on function public.bank_stmt_post113(bigint, text, integer, text, uuid, boolean) from public, anon;
  grant execute on function public.bank_stmt_post113(bigint, text, integer, text, uuid, boolean) to authenticated;
end if; end $p113$;

-- ---------------------------------------------------------------- phase114.sql
-- ============================================================
-- Phase 114 (bos114) - BATCH 2 "stock safety", part 1 (sales / stock / units / batches / item lifecycle).
--   Source: docs/audit2/A2_sales_stock_reconciliation.md (gaps G3, G5, G6, G8, G9; G4 is already an advisor row, see below).
--   Needs phases 72..103 pasted first (guard below). Independent of 112/113/116..121. Paste twice = no change.
--   EVERY behaviour change is behind a rules switch whose default is OFF = today's behaviour. Nothing here is switched on by this file.
--
--   Rules (all switches, default false)                          what ON does
--     late_sale_follows_block   G3  a sale that arrives online with an OLD p_sold_at (phone clock behind / direct API call) is no longer
--                                   treated as a "late offline sync": stock_negative_mode = block applies to it. A real offline-queue replay
--                                   (record_sale_offline, manager override) is untouched.
--     transfer_needs_stock      G6  a transfer cannot send more than the sender holds (the sell_below_zero permission / emergency approval
--                                   still lets the owner through). Also stops "negative stock on send" (A5 GAP-8). Row-locked: two phones cannot both pass.
--     return_uses_sale_rows     G5  a sale return puts back what the SALE took out (ledger rows, in proportion to the returned part of the line),
--                                   not today's unit factor. A factor edited after the sale no longer shifts the book.
--     item_unit_change_needs_zero G5 the base unit (the unit the stock number is counted in) cannot be changed while stock is on hand.
--     item_lifecycle_needs_zero G9  an item cannot be set "not tracked" or inactive while stock is on hand (same error item_has_stock as "count in business").
--     batch_for_adjustments     G8  a count GAIN and an OPENING stock get an adjustment batch (no expiry), so FEFO / expiry lists see the stock.
--     batch_refill_cap          G8  a new batch that refills a NEGATIVE balance only keeps the part that is really on hand (balance -2, batch 10 -> batch 8).
--   Functions
--     new       stock_batch_reconcile(p_fix)   owner: batch sum vs balance per item / place; p_fix adds an adjustment batch for the missing part only
--               _adj_batch114, _stock_batch_refill114 (trigger), _items_stock_guard114 (trigger)  internal
--     patched   _sale_stock_out, stock_transfer, sale_return, stock_count_adjust, stock_opening - each by an exact-text insert into the CURRENT body
--               (helper _b2_patch114, dropped at the end of this file): every older bosNN tag of the function is kept by construction, a body that no longer
--               contains the expected line makes this file stop with a clear message instead of overwriting anything. Tag bos114.
--   Not done here (see docs/audit2 + the batch report): combo / kit (G7), item merge (G9), stock_levels listing inactive items, statement report (G1/G2).
--   G4 (unit conversion missing -> block): already exists as rule unit_conv_required = refuse (phase508) and is already an advisor row (recommended refuse).
--   Money / cost secrecy: no cost is read or written by anything new; RLS / grants unchanged; internal functions have no privilege for anyone.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.audit_log') is null or to_regclass('public.stock_batches') is null or to_regclass('public.rules') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase114 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- helper: exact-text patch of a live function body (dropped at the end of this file) ----------
create or replace function public._b2_patch114(p_sig text, p_anchor text, p_repl text, p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int;
begin
  if f is null then raise exception 'phase114: function % not found - paste phases 72..103 first', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  n := (length(d) - length(replace(d, p_anchor, ''))) / length(p_anchor);
  if n <> 1 then raise exception 'phase114: % expected text found % times (need exactly 1) in %; the function changed - merge by hand', p_marker, n, p_sig; end if;
  execute replace(d, p_anchor, p_repl);
end $$;

-- ---------- rules (all OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('late_sale_follows_block', 'stock', 'switch', 'false', null, null, null, null,
  'পুরনো সময়ের অনলাইন বিক্রিতেও "block" নিয়ম খাটবে', 'পুরনো সময়ের online sale-এও block নিয়ম খাটবে', 'The block rule also applies to online sales that carry an old time',
  'বন্ধ = আগের মতোই (ডিফল্ট): ২ মিনিটের বেশি পুরনো সময় সহ আসা যেকোনো বিক্রি stock-এর হিসাবে "দেরিতে আসা" ধরা হয়, তাই block থাকলেও আটকায় না। চালু = শুধু আসল offline সারি (replay) থেকে আসা বিক্রিই ছাড় পায়; ফোনের ঘড়ি পিছিয়ে থাকলে বা সরাসরি API-তে পাঠালে block কাজ করে।',
  'Off = আগের মতোই (default): 2 মিনিটের বেশি পুরনো সময় সহ আসা যেকোনো sale stock-এর হিসাবে "late" ধরা হয়, তাই block থাকলেও আটকায় না। On = শুধু আসল offline queue (replay) থেকে আসা sale ছাড় পায়; phone-এর ঘড়ি পিছিয়ে থাকলে বা সরাসরি API-তে পাঠালে block কাজ করে।',
  'Off = as before (default): any sale that arrives with a time more than 2 minutes old counts as a late sync and is not stopped by block mode. On = only a real offline-queue replay is exempt; a phone with a slow clock or a direct API call is stopped by block like any other sale.', 1140),
 ('transfer_needs_stock', 'stock', 'switch', 'false', null, null, null, null,
  'Transfer-এ প্রেরকের stock-এর বেশি পাঠানো যাবে না', 'Transfer-এ sender-এর stock-এর বেশি পাঠানো যাবে না', 'A transfer cannot send more than the sender holds',
  'বন্ধ = আগের মতোই (ডিফল্ট): stock_negative_mode = warn থাকলে বেশি পাঠানো যায়, প্রেরকের stock মাইনাস হয় ও প্রাপক শূন্য থেকে stock পায়। চালু = প্রেরকের হাতে যা আছে তার বেশি পাঠানো যায় না ("stock-এর নিচে বিক্রি" অনুমতি বা জরুরি অনুমোদন থাকলে ছাড়)। আগে stock গুনে ঠিক করে নিন।',
  'Off = আগের মতোই (default): stock_negative_mode = warn হলে বেশি পাঠানো যায়, sender-এর stock minus হয় ও receiver শূন্য থেকে stock পায়। On = sender-এর হাতে যা আছে তার বেশি পাঠানো যায় না (sell-below-zero permission বা emergency approval থাকলে ছাড়)। আগে stock গুনে ঠিক করে নিন।',
  'Off = as before (default): in warn mode a transfer above the sender''s stock is accepted, the sender goes negative and the receiver gets stock from nothing. On = a transfer above what the sender holds is refused (the sell-below-zero permission or an emergency approval still lets it through). Count your stock first.', 1141),
 ('return_uses_sale_rows', 'stock', 'switch', 'false', null, null, null, null,
  'বিক্রি ফেরতে বিক্রির সময়ে যা stock থেকে বেরিয়েছিল ঠিক তাই ফেরত আসবে', 'Sale return-এ বিক্রির সময়ে যা stock থেকে বেরিয়েছিল ঠিক তাই ফেরত আসবে', 'A sale return puts back what the sale took out',
  'বন্ধ = আগের মতোই (ডিফল্ট): ফেরতের পরিমাণ আজকের unit factor দিয়ে হিসাব হয়; বিক্রির পরে factor বদলালে stock ভুল হয়। চালু = বিক্রির নিজের stock-খাতার সারি থেকে আনুপাতিক হারে ফেরত হয়।',
  'Off = আগের মতোই (default): ফেরতের পরিমাণ আজকের unit factor দিয়ে হিসাব হয়; sale-এর পরে factor বদলালে stock ভুল হয়। On = sale-এর নিজের stock ledger row থেকে আনুপাতিক হারে ফেরত হয়।',
  'Off = as before (default): the returned quantity is converted with today''s unit factor, so a factor edited after the sale shifts the book. On = the return is taken from the sale''s own stock ledger rows, in proportion to the returned part of the line.', 1142),
 ('item_unit_change_needs_zero', 'items', 'switch', 'false', null, null, null, null,
  'Stock থাকা অবস্থায় পণ্যের base unit বদলানো যাবে না', 'Stock থাকা অবস্থায় item-এর base unit বদলানো যাবে না', 'The base unit cannot change while stock is on hand',
  'বন্ধ = আগের মতোই (ডিফল্ট): kg থেকে pc করলে খাতার সংখ্যাটির মানেই বদলে যায়। চালু = কোনো জায়গায় stock শূন্য না হলে base unit বদলানো যায় না (আগে গুনে শূন্য করুন)।',
  'Off = আগের মতোই (default): kg থেকে pc করলে খাতার সংখ্যাটির মানেই বদলে যায়। On = কোথাও stock শূন্য না হলে base unit বদলানো যায় না (আগে count করে শূন্য করুন)।',
  'Off = as before (default): changing kg to pc silently changes what the stock number means. On = the base unit cannot be changed unless the stock is zero everywhere (count it down first).', 1143),
 ('item_lifecycle_needs_zero', 'items', 'switch', 'false', null, null, null, null,
  'Stock থাকা পণ্য "ট্র্যাক বন্ধ" বা নিষ্ক্রিয় করা যাবে না', 'Stock থাকা item "tracking বন্ধ" বা inactive করা যাবে না', 'An item with stock cannot be untracked or deactivated',
  'বন্ধ = আগের মতোই (ডিফল্ট): ট্র্যাক বন্ধ করে বিক্রি চললে খাতার stock আর মেলে না; নিষ্ক্রিয় পণ্যের stock তালিকা থেকে লুকায় কিন্তু মূল্যে গোনা হয়। চালু = stock শূন্য না হলে দুটোই আটকায়।',
  'Off = আগের মতোই (default): tracking বন্ধ করে sale চললে book stock আর মেলে না; inactive item-এর stock list থেকে লুকায় কিন্তু valuation-এ গোনা হয়। On = stock শূন্য না হলে দুটোই আটকায়।',
  'Off = as before (default): selling after tracking is switched off leaves the book wrong; a deactivated item''s stock vanishes from the stock list but is still valued. On = both are refused until the stock is zero.', 1144),
 ('batch_for_adjustments', 'stock', 'switch', 'false', null, null, null, null,
  'গণনায় বাড়া stock ও শুরুর (opening) stock-এর জন্য batch খোলা হবে', 'Count-এ বাড়া stock ও opening stock-এর জন্য batch খোলা হবে', 'Count gains and opening stock get an adjustment batch',
  'বন্ধ = আগের মতোই (ডিফল্ট): এই stock-এর কোনো batch থাকে না, তাই মেয়াদ/FEFO তালিকায় আসে না এবং সবার শেষে বিক্রি হয়। চালু = মেয়াদহীন একটি adjustment batch খোলা হয়, ফলে batch-এর যোগফল খাতার stock-এর সমান থাকে।',
  'Off = আগের মতোই (default): এই stock-এর কোনো batch থাকে না, তাই expiry/FEFO list-এ আসে না এবং সবার শেষে sell হয়। On = expiry ছাড়া একটি adjustment batch খোলা হয়, ফলে batch-এর যোগফল book stock-এর সমান থাকে।',
  'Off = as before (default): this stock has no batch, so it is missing from expiry / FEFO lists and is sold last. On = a no-expiry adjustment batch is opened so the batches add up to the book stock.', 1145),
 ('batch_refill_cap', 'stock', 'switch', 'false', null, null, null, null,
  'মাইনাস stock পূরণ করা নতুন batch-এ শুধু আসল মজুত ধরা হবে', 'Minus stock পূরণ করা নতুন batch-এ শুধু আসল মজুত ধরা হবে', 'A batch that refills a negative balance only keeps what is really on hand',
  'বন্ধ = আগের মতোই (ডিফল্ট): stock -২ থাকা অবস্থায় ১০ উৎপাদন হলে খাতায় ৮ কিন্তু batch-এ ১০ দেখায় (২টি ভুতুড়ে)। চালু = batch-এ ৮ ধরা হয়। বাতিল (void) করার সময় এই batch "আংশিক ব্যবহৃত" ধরা পড়তে পারে।',
  'Off = আগের মতোই (default): stock -2 থাকা অবস্থায় 10 production হলে book-এ 8 কিন্তু batch-এ 10 দেখায় (2টি phantom)। On = batch-এ 8 ধরা হয়। Void করার সময় এই batch "partly used" ধরা পড়তে পারে।',
  'Off = as before (default): producing 10 while the balance is -2 leaves 8 in the book but 10 in the batch (2 phantom). On = the batch keeps 8. Voiding such a run may report "batch partly used".', 1146)
on conflict (key) do nothing;

-- ---------- setup advisor rows (advisory only; apply goes through set_rule) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('late_sale_follows_block', 'late_sale_follows_block', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'stock "block" দিলে আপনি চান বেশি বিক্রি আটকাক। ফোনের ঘড়ি পিছিয়ে থাকলে সেই আটকানো ফাঁকি দেওয়া যায়। এটি চালু করলে শুধু আসল offline বিক্রি ছাড় পায়; block না থাকলে কিছুই বদলায় না।',
  'Stock block দিলে আপনি চান বেশি sale আটকাক। Phone-এর ঘড়ি পিছিয়ে থাকলে সেই আটকানো ফাঁকি দেওয়া যায়। এটি চালু করলে শুধু আসল offline sale ছাড় পায়; block না থাকলে কিছুই বদলায় না।',
  'If you chose block you want oversells stopped, but a phone with a slow clock gets around it. With this on only a real offline sale is exempt; if block is not used nothing changes.', 1140),
 ('transfer_needs_stock', 'transfer_needs_stock', '114', 'stock', null::jsonb, '{}'::text[],
  'চালু করলে প্রেরকের হাতে যা নেই তা পাঠানো যায় না, ফলে শূন্য থেকে stock তৈরি হয় না। কিন্তু খাতার stock ভুল থাকলে বৈধ transfer-ও আটকে যেতে পারে, তাই প্রথম stock গোনার পরে নিজে চালু করুন; এখানে মান ঠিক করে দেওয়া হয়নি।',
  'চালু করলে sender-এর হাতে যা নেই তা পাঠানো যায় না, ফলে শূন্য থেকে stock তৈরি হয় না। কিন্তু book stock ভুল থাকলে বৈধ transfer-ও আটকে যেতে পারে, তাই প্রথম stock count-এর পরে নিজে চালু করুন; এখানে value ঠিক করে দেওয়া হয়নি।',
  'On, a transfer above what the sender holds is refused so no stock appears from nothing. If the book stock is wrong a genuine transfer may be stopped, so switch it on yourself after the first stock count; no value is recommended here.', 1141),
 ('return_uses_sale_rows', 'return_uses_sale_rows', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'unit factor বদলালে পুরনো বিক্রির ফেরত ভুল পরিমাণ stock-এ ওঠে। চালু করলে ফেরত ঠিক সেই পরিমাণ ওঠে যা বিক্রির সময় বেরিয়েছিল। আগের কোনো হিসাব বদলায় না।',
  'Unit factor বদলালে পুরনো sale-এর return ভুল পরিমাণ stock-এ ওঠে। চালু করলে return ঠিক সেই পরিমাণ ওঠে যা sale-এর সময় বেরিয়েছিল। আগের কোনো হিসাব বদলায় না।',
  'After a unit factor is edited, a return of an old sale puts the wrong quantity back. With this on the return restores exactly what the sale took out. Nothing already booked changes.', 1142),
 ('item_unit_change_needs_zero', 'item_unit_change_needs_zero', '114', 'items', 'true'::jsonb, '{}'::text[],
  'stock থাকা অবস্থায় base unit বদলালে খাতার সংখ্যার মানে চুপচাপ বদলে যায়। চালু করলে আগে stock শূন্য করতে হয়; তাতে ভুল হওয়ার পথ বন্ধ হয়।',
  'Stock থাকা অবস্থায় base unit বদলালে book-এর সংখ্যার মানে চুপচাপ বদলে যায়। চালু করলে আগে stock শূন্য করতে হয়; তাতে ভুল হওয়ার পথ বন্ধ হয়।',
  'Changing the base unit while stock is on hand silently changes what the number means. With this on the stock must be zero first, which closes that mistake.', 1143),
 ('item_lifecycle_needs_zero', 'item_lifecycle_needs_zero', '114', 'items', 'true'::jsonb, '{}'::text[],
  'ট্র্যাক বন্ধ বা নিষ্ক্রিয় করা পণ্যের stock খাতায় থেকে যায় অথচ কেউ দেখে না। চালু করলে আগে stock শূন্য (গণনা/ব্যবহার) করতে হয়।',
  'Tracking বন্ধ বা inactive করা item-এর stock book-এ থেকে যায় অথচ কেউ দেখে না। চালু করলে আগে stock শূন্য (count/use) করতে হয়।',
  'Stock of an untracked or deactivated item stays in the books where nobody sees it. With this on the stock must be brought to zero (count / use) first.', 1144),
 ('batch_for_adjustments', 'batch_for_adjustments', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'গণনায় বাড়া ও শুরুর stock-এর batch না থাকায় মেয়াদ ও FEFO তালিকা থেকে সেই মাল বাদ পড়ে। চালু করলে মেয়াদহীন একটি batch খোলা হয়; stock বা দাম বদলায় না।',
  'Count-এ বাড়া ও opening stock-এর batch না থাকায় expiry ও FEFO list থেকে সেই মাল বাদ পড়ে। চালু করলে expiry ছাড়া একটি batch খোলা হয়; stock বা দাম বদলায় না।',
  'Stock added by a count or an opening has no batch, so it is missing from expiry and FEFO lists. With this on a no-expiry batch is opened; stock and costs do not change.', 1145),
 ('batch_refill_cap', 'batch_refill_cap', '114', 'stock', 'true'::jsonb, '{}'::text[],
  'মাইনাস stock পূরণ করা উৎপাদন/ক্রয়ের batch-এ ভুতুড়ে পরিমাণ থেকে যায়, মেয়াদের তালিকা বেশি দেখায়। চালু করলে batch-এ শুধু আসল মজুত থাকে।',
  'Minus stock পূরণ করা production/purchase-এর batch-এ phantom পরিমাণ থেকে যায়, expiry list বেশি দেখায়। চালু করলে batch-এ শুধু আসল মজুত থাকে।',
  'A production or purchase batch that refills a negative balance keeps a phantom quantity and the expiry list shows too much. With this on the batch keeps only what is really on hand.', 1146)
on conflict (code) do nothing;

-- ---------- internal: adjustment batch for a count gain / opening ----------
create or replace function public._adj_batch114(p_item uuid, p_loc integer, p_qty numeric, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  if p_qty is null or p_qty <= 0 or not public.rule_on('batch_for_adjustments') then return null; end if;      -- bos114: off = no batch, as before
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, note, created_by)
    values (p_item, p_loc, now(), round(p_qty, 4), round(p_qty, 4), null, left(p_note, 200), auth.uid()) returning id into bid;
  return bid;
end $$;
revoke all on function public._adj_batch114(uuid, integer, numeric, text) from public, anon, authenticated;

-- ---------- trigger: a new batch that refills a negative balance keeps only what is really on hand ----------
create or replace function public._stock_batch_refill114() returns trigger
language plpgsql security definer set search_path = public as $$
declare q numeric;
begin
  if not public.rule_on('batch_refill_cap') then return new; end if;                                     -- bos114: off = as before
  if new.qty_remaining is distinct from new.qty_made then return new; end if;                            -- only a fresh, untouched batch
  select b.qty into q from public.stock_balance b where b.item_id = new.item_id and b.location_id = new.location_id for update;   -- same row stock_post locks next
  if q is not null and q < 0 then new.qty_remaining := greatest(0, round(new.qty_made + q, 4)); end if;
  return new;
end $$;
revoke all on function public._stock_batch_refill114() from public, anon, authenticated;
drop trigger if exists stock_batch_refill114 on public.stock_batches;
create trigger stock_batch_refill114 before insert on public.stock_batches for each row execute function public._stock_batch_refill114();

-- ---------- trigger: base unit change / untrack / deactivate with stock on hand ----------
create or replace function public._items_stock_guard114() returns trigger
language plpgsql security definer set search_path = public as $$
declare busy boolean;
begin
  if tg_op <> 'UPDATE' then return new; end if;
  if (public.rule_on('item_lifecycle_needs_zero') and ((old.tracked and not new.tracked) or (old.is_active and not new.is_active)))
     or (public.rule_on('item_unit_change_needs_zero') and coalesce(nullif(btrim(old.base_unit), ''), old.unit) is distinct from coalesce(nullif(btrim(new.base_unit), ''), new.unit)) then
    select exists (select 1 from public.stock_balance where item_id = new.id and qty <> 0) into busy;      -- bos114
    if busy then raise exception 'item_has_stock' using detail = 'Stock is on hand for ' || new.code || ': bring it to zero first', hint = new.code; end if;
  end if;
  return new;
end $$;
revoke all on function public._items_stock_guard114() from public, anon, authenticated;
drop trigger if exists items_stock_guard114 on public.items;
create trigger items_stock_guard114 after update on public.items for each row
  when (old.tracked is distinct from new.tracked or old.is_active is distinct from new.is_active or old.base_unit is distinct from new.base_unit or old.unit is distinct from new.unit)
  execute function public._items_stock_guard114();

-- ---------- batch sum vs balance (owner) ----------
create or replace function public.stock_batch_reconcile(p_fix boolean default false)
returns table(item_id uuid, location_id integer, balance numeric, batch_sum numeric, diff numeric, fixed boolean)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; bq numeric; bs numeric; sid text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select p.staff_id into sid from public.profiles p where p.id = auth.uid();
  for r in select k.iid, k.lid from (select b.item_id iid, b.location_id lid from public.stock_batches b group by 1, 2) k order by 1, 2 loop
    if p_fix then perform 1 from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid for update; end if;
    bq := coalesce((select z.qty from public.stock_balance z where z.item_id = r.iid and z.location_id = r.lid), 0);
    bs := coalesce((select sum(x.qty_remaining) from public.stock_batches x where x.item_id = r.iid and x.location_id = r.lid), 0);
    if abs(bs - greatest(bq, 0)) >= 0.0005 then
      item_id := r.iid; location_id := r.lid; balance := bq; batch_sum := bs; diff := round(bs - greatest(bq, 0), 4); fixed := false;
      if p_fix and diff < 0 then          -- stock the batches do not know about: an adjustment batch for exactly that part; the other direction (phantom batch stock) is only reported
        insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, note, created_by)
          values (r.iid, r.lid, now(), -diff, -diff, null, 'reconcile: adjustment batch', auth.uid());
        insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
          values (auth.uid(), sid, 'batch_reconcile_fix', 'stock_batches', r.iid::text || ':' || r.lid::text,
                  jsonb_build_object('balance', bq, 'batch_sum_before', bs, 'added', -diff, 'src', 'phase114'));
        fixed := true;
      end if;
      return next;
    end if;
  end loop;
end $$;
revoke all on function public.stock_batch_reconcile(boolean) from public, anon;
grant execute on function public.stock_batch_reconcile(boolean) to authenticated;

-- ---------- patches of the live bodies (each keeps every older tag; a changed body stops the file) ----------
-- G3: a late sale is exempt from "block" only when it really is an offline replay
do $do$ begin perform public._b2_patch114('public._sale_stock_out()',
$a$  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'$a$,
$a$  if neg = 'soft' and public.rule_on('late_sale_follows_block') and coalesce(current_setting('bos.offline_replay', true), '') <> '1' and coalesce(current_setting('bos.replay_override', true), '') <> '1' then neg := 'full'; end if;   -- bos114:late-sale (an online sale with an old p_sold_at is not an offline sync)
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'$a$,
'bos114:late-sale'); end $do$;

-- G6: a transfer cannot create stock
do $do$ begin perform public._b2_patch114('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)',
$a$  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out'$a$,
$a$  if public.rule_on('transfer_needs_stock') then   -- bos114:xfer-stock (the balance row is locked, so two phones cannot both pass)
    insert into public.stock_balance (item_id, location_id) values (p_item, p_from) on conflict do nothing;
    perform 1 from public.stock_balance b where b.item_id = p_item and b.location_id = p_from for update;
    if coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0) < bq
       and not (public.has_grant('sell_below_zero', p_from) or public._use_em('sell_below_zero', p_from, 'transfer:' || tid::text, null)) then
      raise exception 'insufficient_stock' using detail = coalesce(it.code, '') || ' ' || coalesce(it.name_bn, ''), hint = 'on hand ' || coalesce((select b.qty from public.stock_balance b where b.item_id = p_item and b.location_id = p_from), 0)::text;
    end if;
  end if;
  lid := public.stock_post(p_item, p_from, -bq, 'transfer_out'$a$,
'bos114:xfer-stock'); end $do$;

-- G5: a return restores what the sale took out
do $do$ begin perform public._b2_patch114('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)',
$a$    bq := public._base_qty(it.id, ln.q, ln.u);$a$,
$a$    bq := public._base_qty(it.id, ln.q, ln.u);
    if public.rule_on('return_uses_sale_rows') then   -- bos114:return-rows: base quantity the sale itself took out x returned part of the line (not today's factor)
      bq := coalesce((select z.sold_base * ln.q / z.sold_line from (select
          (select sum(-x.qty_delta) from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
              and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id)) sold_base,
          (select sum(nullif(e->>'qty', '')::numeric) from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
              where e->>'item_id' = it.id::text and (e->>'unit') is not distinct from ln.u) sold_line) z
        where z.sold_base > 0 and z.sold_line > 0), bq);
    end if;$a$,
'bos114:return-rows'); end $do$;

-- G8: a count gain gets an adjustment batch
do $do$ begin perform public._b2_patch114('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)',
$a$ the average does not move */, null, now(), left(p_note, 200), null, 'none', null, p_client);$a$,
$a$ the average does not move */, public._adj_batch114(p_item, p_loc, d, 'count gain'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:count-batch$a$,
'bos114:count-batch'); end $do$;

-- G8: opening stock gets an adjustment batch
do $do$ begin perform public._b2_patch114('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)',
$a$  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, null, now(), left(p_note, 200), null, 'none', null, p_client);$a$,
$a$  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, public._adj_batch114(p_item, p_loc, bq, 'opening stock'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:opening-batch$a$,
'bos114:opening-batch'); end $do$;

drop function public._b2_patch114(text, text, text, text);

commit;

-- ---------------------------------------------------------------- phase115.sql
-- ============================================================
-- Phase 115 (bos115) - BATCH 2 "stock safety", part 2 (factory-to-branch transfers).
--   Source: docs/audit2/A5_factory_branch_reconciliation.md (GAP-2, GAP-3, GAP-4, GAP-6, GAP-8 is rule transfer_needs_stock of phase114).
--   Needs phases 72..103 pasted first (guard below); phase114 is NOT required (its own rule is used only by phase114). Independent of 112/113/116..121.
--   Paste twice = no change. EVERY behaviour change is behind a rules switch, default OFF = today's behaviour. Nothing here is switched on by this file.
--
--   Rules (switches, default false)
--     transfer_late_receive     GAP-2 a short receipt can be completed later: stock_receive_more(id, qty) books the rest (second lorry) at the sent cost,
--                                     same batch / expiry, as long as the shortage was not written off (transit_loss) or booked in the accounts.
--     transfer_return_marker    GAP-3 stock_return_transfer(...) sends goods back to the factory as a MARKED return: kind = return, a reason
--                                     (damaged / expired / excess / wrong_item / other) and a link to the original transfer; it is an ordinary transfer otherwise.
--     transfer_notify_receiver  GAP-6 when goods are sent, a notification goes to the receiving place's managers (kind transfer_sent, once per transfer).
--     transit_loss_gl_fix       GAP-4 location-tagged accounting: transit_short_mode = loss / transit_short_resolve no longer leave a phantom inventory
--                                     (+short transfer_in leg without a matching leg) and the transit-loss entry is no longer stuck on cost_missing.
--                                     Entries already posted wrongly are NOT rewritten (see the report).
--   Columns  stock_transfers.kind (null = normal send, 'return'), .reason, .ref_transfer_id   (all nullable; old rows unchanged)
--   Functions new: stock_receive_more(id, qty, note, client), stock_return_transfer(from, to, item, qty, reason, ref, unit, note, client)
--             patched by exact-text insert (helper _b2_patch115, dropped at the end; older bosNN tags stay): stock_transfer (tag bos115), _acct_stock_moves85 and _acct_docs.
--             These two carry the marker b2s115, NOT a bosNN tag, on purpose (same as perf110 / sec2-L6): the body guards of phase524 / 103 / 110 refuse to overwrite a function with a bosNN
--             tag they do not know, so a bos115 tag there would make an out-of-order re-paste of those phases impossible. Re-paste rule: after phase524 / 103 / 110 paste phase115 again.
--   Not done: factory-branch statement report (GAP-1), challan header (GAP-7), transfer price (GAP-9), paused-location check (GAP-5), offline outbox (GAP-12),
--             returns valued at the original send cost (G8: needs a cost-aware return post; risky), form 03-1 path (GAP-11).
--   Money / cost secrecy: no cost is shown by anything new (costs are read only inside stock_post / the accounts, as before); RLS / grants unchanged.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.stock_transfers') is null or to_regclass('public.journal_entries') is null or to_regclass('public.notifications') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase115 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- helper: exact-text patch of a live function body (dropped at the end of this file) ----------
create or replace function public._b2_patch115(p_sig text, p_anchor text, p_repl text, p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int;
begin
  if f is null then raise exception 'phase115: function % not found - paste phases 72..103 first', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  n := (length(d) - length(replace(d, p_anchor, ''))) / length(p_anchor);
  if n <> 1 then raise exception 'phase115: % expected text found % times (need exactly 1) in %; the function changed - merge by hand', p_marker, n, p_sig; end if;
  execute replace(d, p_anchor, p_repl);
end $$;

-- ---------- columns (additive, nullable) ----------
alter table public.stock_transfers add column if not exists kind text;
alter table public.stock_transfers add column if not exists reason text;
alter table public.stock_transfers add column if not exists ref_transfer_id uuid;
do $c$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.stock_transfers'::regclass and conname = 'stock_transfers_kind115') then
    alter table public.stock_transfers add constraint stock_transfers_kind115 check (kind is null or kind = 'return');
  end if;
end $c$;

-- ---------- rules (all OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('transfer_late_receive', 'stock', 'switch', 'false', null, null, null, null,
  'কম গ্রহণ করা transfer-এর বাকি মাল পরে গ্রহণ করা যাবে', 'কম receive করা transfer-এর বাকি মাল পরে receive করা যাবে', 'The rest of a short transfer can be received later',
  'বন্ধ = আগের মতোই (ডিফল্ট): প্রথম গ্রহণেই transfer বন্ধ হয়, দ্বিতীয় গাড়ির মাল "ঘাটতি" থেকে যায়। চালু = ঘাটতি অবশিষ্টের মধ্যে পরে আরও গ্রহণ করা যায় (যতক্ষণ ঘাটতি "পথে ক্ষতি" হিসেবে লেখা বা হিসাবে তোলা হয়নি)।',
  'Off = আগের মতোই (default): প্রথম receive-এই transfer বন্ধ হয়, দ্বিতীয় গাড়ির মাল "short" থেকে যায়। On = ঘাটতি অবশিষ্টের মধ্যে পরে আরও receive করা যায় (যতক্ষণ ঘাটতি transit loss হিসেবে লেখা বা accounts-এ তোলা হয়নি)।',
  'Off = as before (default): the first receipt closes the transfer and the second lorry stays "short" for ever. On = more can be received later up to the shortage, as long as the shortage was not written off as a transit loss or booked in the accounts.', 1150),
 ('transfer_return_marker', 'stock', 'switch', 'false', null, null, null, null,
  'কারখানায় ফেরত পাঠানো মাল কারণ ও মূল transfer-সহ চিহ্নিত হবে', 'Factory-তে ফেরত পাঠানো মাল কারণ ও মূল transfer-সহ চিহ্নিত হবে', 'Returns to the factory are marked with a reason and a link',
  'বন্ধ = আগের মতোই (ডিফল্ট): ফেরত পাঠানো একটি সাধারণ উল্টো transfer, কারণ বা যোগসূত্র থাকে না। চালু = "ফেরত" transfer-এ কারণ (নষ্ট / মেয়াদ শেষ / বাড়তি / ভুল মাল / অন্য) ও মূল transfer লেখা থাকে।',
  'Off = আগের মতোই (default): ফেরত পাঠানো একটি সাধারণ উল্টো transfer, reason বা link থাকে না। On = return transfer-এ reason (damaged / expired / excess / wrong item / other) ও মূল transfer লেখা থাকে।',
  'Off = as before (default): a return to the factory is an ordinary reverse transfer with no reason or link. On = a return transfer records its reason (damaged / expired / excess / wrong item / other) and the original transfer.', 1151),
 ('transfer_notify_receiver', 'notify', 'switch', 'false', null, null, null, null,
  'মাল পাঠালে গ্রহণকারী শাখাকে জানানো হবে', 'মাল পাঠালে গ্রহণকারী শাখাকে জানানো হবে', 'Tell the receiving branch when goods are sent',
  'বন্ধ = আগের মতোই (ডিফল্ট): গ্রহণকারী শাখা জানে না মাল পথে আছে (মালিক শুধু অনেক দেরি হলে সতর্কতা পান)। চালু = মাল পাঠানোর সঙ্গে সঙ্গে ওই শাখার ম্যানেজাররা বিজ্ঞপ্তি পান।',
  'Off = আগের মতোই (default): receiving branch জানে না goods পথে আছে (owner শুধু অনেক দেরি হলে alert পান)। On = goods পাঠানোর সঙ্গে সঙ্গে ওই branch-এর manager-রা notification পান।',
  'Off = as before (default): the receiving branch is not told that goods are on the way (the owner only gets an alert after a long delay). On = the managers of that place get a notification as soon as goods are sent.', 1152),
 ('transit_loss_gl_fix', 'stock', 'switch', 'false', null, null, null, null,
  'পথে ক্ষতি (loss মোড) হিসাবে ভুতুড়ে inventory তৈরি করবে না', 'Transit loss (loss mode) accounts-এ phantom inventory তৈরি করবে না', 'Transit loss no longer creates phantom inventory in the accounts',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু = location-tagged transfer হিসাবে transit_short_mode = loss বা "ঘাটতি নিষ্পত্তি" করলে inventory-র হিসাব শেষে stock মূল্যের সমান থাকে এবং পথে-ক্ষতির entry আটকে থাকে না। আগে ভুল ওঠা entry বদলায় না।',
  'Off = আগের মতোই (default)। On = location-tagged transfer accounts-এ transit_short_mode = loss বা short resolve করলে inventory GL শেষে stock valuation-এর সমান থাকে এবং transit-loss entry আটকে থাকে না। আগে ভুল ওঠা entry বদলায় না।',
  'Off = as before (default). On = with location-tagged transfer accounting, transit_short_mode = loss or resolving a short leaves the inventory GL equal to the stock valuation and the transit-loss entry is no longer stuck. Entries already posted wrongly are not rewritten.', 1153)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('transfer_late_receive', 'transfer_late_receive', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'দুই গাড়িতে মাল এলে প্রথম গ্রহণেই transfer বন্ধ হয়ে বাকি মাল চিরকাল "ঘাটতি" দেখায়। চালু করলে বাকিটা পরে গ্রহণ করা যায়; আগের কোনো হিসাব বদলায় না।',
  'দুই গাড়িতে মাল এলে প্রথম receive-এই transfer বন্ধ হয়ে বাকি মাল চিরকাল short দেখায়। চালু করলে বাকিটা পরে receive করা যায়; আগের কোনো হিসাব বদলায় না।',
  'When goods arrive in two lorries the first receipt closes the transfer and the rest shows as short for ever. With this on the rest can be received later; nothing already booked changes.', 1150),
 ('transfer_return_marker', 'transfer_return_marker', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'কারখানায় ফেরত মাল এখন সাধারণ transfer থেকে আলাদা করা যায় না। চালু করলে কারণ ও মূল transfer লেখা থাকে, ফলে নষ্ট/মেয়াদ-শেষ/বাড়তি ফেরত আলাদা চেনা যায়।',
  'Factory-তে ফেরত মাল এখন সাধারণ transfer থেকে আলাদা করা যায় না। চালু করলে reason ও মূল transfer লেখা থাকে, ফলে damaged/expired/excess return আলাদা চেনা যায়।',
  'A return to the factory cannot be told apart from a normal transfer. With this on the reason and the original transfer are recorded, so damaged / expired / excess returns can be told apart.', 1151),
 ('transfer_notify_receiver', 'transfer_notify_receiver', '115', 'notify', 'true'::jsonb, '{}'::text[],
  'মাল পাঠানোর খবর গ্রহণকারী শাখা পায় না, তাই মাল পড়ে থাকে। চালু করলে ওই শাখার ম্যানেজাররা সঙ্গে সঙ্গে বিজ্ঞপ্তি পান; কোনো stock বা হিসাব বদলায় না।',
  'Goods পাঠানোর খবর receiving branch পায় না, তাই মাল পড়ে থাকে। চালু করলে ওই branch-এর manager-রা সঙ্গে সঙ্গে notification পান; কোনো stock বা হিসাব বদলায় না।',
  'The receiving branch is not told that goods are on the way, so they sit unreceived. With this on the managers of that place are notified at once; no stock or book changes.', 1152),
 ('transit_loss_gl_fix', 'transit_loss_gl_fix', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'transfer-এর হিসাব (location-tagged) চালু থাকলে এবং কম পৌঁছানো মাল "loss" ধরলে inventory-র হিসাব stock-এর চেয়ে বেশি দেখায়। চালু করলে ঠিক মেলে। শুধু এখন থেকে ওঠা entry-তে কাজ করে।',
  'Transfer accounting (location-tagged) চালু থাকলে এবং short মাল loss ধরলে inventory GL stock-এর চেয়ে বেশি দেখায়। চালু করলে ঠিক মেলে। শুধু এখন থেকে ওঠা entry-তে কাজ করে।',
  'With location-tagged transfer accounting and short goods booked as loss, the inventory in the books ends above the stock. With this on it matches. It only affects entries posted from now on.', 1153)
on conflict (code) do nothing;

-- ---------- GAP-2: receive the rest of a short transfer ----------
create or replace function public.stock_receive_more(p_id uuid, p_qty numeric, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; it public.items; rq numeric; rem numeric; skip numeric; avail numeric; take numeric; o record; ob public.stock_batches; nb bigint; lid bigint; first boolean := true; sid text;
begin
  if not public.rule_on('transfer_late_receive') then raise exception 'feature_off'; end if;
  perform public._client_lock(p_client);
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);      -- access first: nothing below is shown to a stranger
  if p_client is not null and exists (select 1 from public.stock_ledger where client_id = p_client and reason = 'transfer_in' and ref_type = 'transfer' and ref_id = t.id::text) then
    return jsonb_build_object('dup', true, 'id', t.id, 'received_qty', t.received_qty);
  end if;
  if t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then raise exception 'not_short'; end if;
  if exists (select 1 from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transit_loss') then raise exception 'short_already_written_off'; end if;
  if exists (select 1 from public.journal_entries e where e.source_type = 'transit_loss' and e.source_id = t.id::text and e.reverses_id is null) then raise exception 'short_already_booked'; end if;
  rq := round(p_qty, 4);
  if rq is null or not (rq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty - t.received_qty + 0.00005 then raise exception 'over_received'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'receive_more:' || p_id::text, rq) then raise exception 'not allowed'; end if;
  rem := least(rq, t.qty - t.received_qty); skip := t.received_qty;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;          -- this part of the lorry was received the first time
    avail := avail - skip; skip := 0;
    take := least(avail, rem); nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none', null, case when first then p_client end);
    first := false; rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set received_qty = received_qty + rq, receive_note = left(coalesce(receive_note || ' | ', '') || coalesce(p_note, 'rest received'), 200) where id = t.id;
  perform public._stock_exc(t.to_location_id, 'transit_short_late', 'yellow',
    it.name_bn || ': বাকি মাল পরে গ্রহণ ' || rq::text || ', এখনো ঘাটতি ' || (t.qty - t.received_qty - rq)::text, coalesce(it.name_en, it.name_bn) || ': the rest was received later: ' || rq::text || ', still short ' || (t.qty - t.received_qty - rq)::text);
  return jsonb_build_object('id', t.id, 'received_qty', t.received_qty + rq, 'short', t.qty - t.received_qty - rq);
end $$;
revoke all on function public.stock_receive_more(uuid, numeric, text, uuid) from public, anon;
grant execute on function public.stock_receive_more(uuid, numeric, text, uuid) to authenticated;

-- ---------- GAP-3: a marked return to the factory ----------
create or replace function public.stock_return_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_reason text, p_ref uuid default null,
                                                       p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.stock_transfers; r jsonb; bq numeric; prior numeric; t public.stock_transfers;
begin
  if not public.rule_on('transfer_return_marker') then raise exception 'feature_off'; end if;
  if not public.can_loc(p_from) then raise exception 'not allowed for this location'; end if;
  if p_reason is null or p_reason not in ('damaged', 'expired', 'excess', 'wrong_item', 'other') then raise exception 'reason_required'; end if;
  if p_reason = 'other' and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_needed'; end if;
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status, 'kind', t.kind); end if;
  end if;
  if p_ref is not null then
    select * into o from public.stock_transfers where id = p_ref;
    if not found or o.item_id <> p_item or o.from_location_id <> p_to or o.to_location_id <> p_from or o.status <> 'received' then raise exception 'bad_ref'; end if;
    bq := public._base_qty(p_item, p_qty, p_unit);
    select coalesce(sum(x.qty), 0) into prior from public.stock_transfers x where x.ref_transfer_id = p_ref and x.kind = 'return' and x.status <> 'cancelled';
    if bq is not null and bq > coalesce(o.received_qty, 0) - prior + 0.00005 then raise exception 'return_exceeds_receipt'; end if;
  end if;
  r := public.stock_transfer(p_from, p_to, p_item, p_qty, p_unit, p_note, p_client);
  if not coalesce((r->>'dup')::boolean, false) then
    update public.stock_transfers set kind = 'return', reason = p_reason, ref_transfer_id = p_ref where id = (r->>'id')::uuid;
  end if;
  return r || jsonb_build_object('kind', 'return', 'reason', p_reason);
end $$;
revoke all on function public.stock_return_transfer(integer, integer, uuid, numeric, text, uuid, text, text, uuid) from public, anon;
grant execute on function public.stock_return_transfer(integer, integer, uuid, numeric, text, uuid, text, text, uuid) to authenticated;

-- ---------- patches of the live bodies ----------
-- GAP-6: tell the receiving place
do $do$ begin perform public._b2_patch115('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)',
$a$  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$a$,
$a$  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$a$,
'bos115:xfer-notify'); end $do$;

-- GAP-4 (a): the synthetic "+short" transfer_in written by _transit_loss83 gets no inventory / clearing leg
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$public.rule_on('acct_manual_prod_in103') p /* bos103 */)$a$,
$a$public.rule_on('acct_manual_prod_in103') p /* bos103 */, public.rule_on('transit_loss_gl_fix') g115 /* b2s115:cfg */)$a$,
'b2s115:cfg'); end $do$;
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$l.qty_delta, l.reason = 'reversal' rv,$a$,
$a$l.qty_delta, l.reason = 'reversal' rv, (l.reason = 'transfer_in' and l.client_id is not null and l.client_id = md5(coalesce(l.ref_id, '') || ':tl_in')::uuid) syn115 /* b2s115:syn */,$a$,
'b2s115:syn'); end $do$;
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$where m.cls is not null and m.d >= cfg.f$a$,
$a$where m.cls is not null and m.d >= cfg.f and not (cfg.g115 and m.syn115) /* b2s115:where */$a$,
'b2s115:where'); end $do$;

-- GAP-4 (b): the transit-loss entry counts only the real transfer rows (the synthetic pair nets to zero in the stock book and has no leg)
do $do$ begin perform public._b2_patch115('public._acct_docs(date)',
$a$from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c$a$,
$a$from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c$a$,
'b2s115:docs'); end $do$;

drop function public._b2_patch115(text, text, text, text);

commit;

-- ---------------------------------------------------------------- phase116.sql
-- ============================================================
-- Phase 116 (bos116) - BATCH 3, part 1: manufacturing cost ENGINE (audit: docs/audit2/A1_manufacturing_cost.md G1 G4 G5 G6 G7 G8 G10).
-- Run AFTER phase111 (canonical order, docs/PASTE_ORDER.md section N). Needs phases 72..111. Additive; paste twice = no change. Phase117 (GL side) is the companion.
-- EVERY behaviour change is behind a rules switch whose default is today's behaviour; with all switches off the books, costs and screens are exactly as before.
--   semi_finished_ingredient116  finished goods (chhana, dough) may be an ingredient of another recipe; cycles refused                         (G1)
--   packaging_on_actual_yield116 packaging is used for the quantity really made, not the planned yield                                        (G10)
--   std_snapshot_auto116         the first run of a recipe at a place stores the STANDARD (recipe quantities x prices of that day)              (G8)
--   std_cost_true116             production_runs.std_cost = that true standard per unit (today it is actual cost / theoretical output)          (G8)
--   pool_drivers116              overhead pool can be spread by output kg / output units / batches / labour hours, per place and per cost type   (G5, G6)
--   conv_provisional116          a run made before its month's pool exists uses the last month that has a pool, flagged PROVISIONAL              (G4)
--   cost_supply_to_avg116        a cost supplied through the cost-waiting list also reaches stock_balance.avg_cost and re-costs the run           (G7)
-- New read/act functions (no switch needed, they change nothing until called): recipe_std_set116, production_variance116, production_reprice116 and production_recost116 (both dry by default),
--   production_cost_queue116, recipe_stage_cost116, loc_cost_driver_set116, cost_type_driver_set116.
-- Functions re-created (tag bos116, every older tag kept): _recipe_lines_ok, _recipe_need (thin wrapper), production_post (7 args), _conv_cost, cost_wait_supply96, production_run_costs, production_void.
-- Re-paste rule: if phase19/73/74/79/522/109 (anything that re-creates one of those functions) is pasted again, paste phase116 again after it.
-- ============================================================

do $g$
declare miss text := ''; m record; d text; t text; bad text := '';
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('96', 'public._cw_docs96()'),
    ('97', 'public._landed_jlines97(uuid,text)'), ('87', 'public._prod_double_issue87()')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.setup_rec_defs81') is null then miss := miss || ' 81'; end if;
  if to_regclass('public.opening_covered103') is null then miss := miss || ' 103'; end if;
  if to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)') is null
     or coalesce(position('bos109' in pg_get_functiondef(to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)'))), 0) = 0
        and coalesce(position('bos116' in pg_get_functiondef(to_regprocedure('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)'))), 0) = 0 then miss := miss || ' 109'; end if;
  if miss <> '' then raise exception 'phase116 needs phases 72..111 pasted first (see docs/PASTE_ORDER.md); missing:%', miss; end if;
  -- body guard: a function this file re-creates must carry no bosNN tag that this file does not know (a later phase changed it: merge into this file first)
  for m in select * from (values
    ('public.production_post(integer,uuid,numeric,uuid,timestamptz,text,numeric)', 'bos72 bos73 bos74 bos80 bos109 bos116'),
    ('public._recipe_lines_ok(uuid,jsonb)', 'bos116'), ('public._recipe_need(uuid,numeric,integer)', 'bos116'), ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', 'bos116'),
    ('public.cost_wait_supply96(text,text,text,jsonb,text,uuid,boolean)', 'bos116'), ('public.production_run_costs(integer,date,date)', 'bos116'), ('public.production_void(uuid,text)', 'bos116')) v(fn, ok)
  loop
    d := pg_get_functiondef(to_regprocedure(m.fn));
    for t in select distinct x[1] from regexp_matches(d, '(bos[0-9]+)', 'g') x loop
      if position(t in m.ok) = 0 then bad := bad || ' ' || m.fn || '->' || t; end if;
    end loop;
  end loop;
  if bad <> '' then raise exception 'phase116 refuses: a function it re-creates carries a tag it does not know (merge that change into phase116 first):%', bad; end if;
end $g$;

-- ---------- switches (all default OFF = today's behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('semi_finished_ingredient116', 'stock', 'switch', 'false', null, null, null,
  'তৈরি পণ্য (আধা-তৈরি মাল) অন্য রেসিপির উপাদান হতে পারবে', 'Finished good (semi-finished) অন্য recipe-র ingredient হতে পারবে', 'A finished good (semi-finished) may be an ingredient of another recipe',
  'Off (default) = আজকের মতো, শুধু কাঁচামাল / প্যাকেজিং / রিসেল। On = ছানার মতো আধা-তৈরি মাল মিষ্টির রেসিপিতে বসানো যাবে; উৎপাদনে সেই মাল stock থেকে গড় খরচে কমবে। ঘুরে-আসা রেসিপি (ক → খ → ক) আটকানো হয়।',
  'Off (default) = as today: only raw material, packaging and resale items. On = a semi-finished good such as chhana can be an ingredient; production takes it out of stock at its average cost. A circle (A uses B, B uses A) is refused.', 750),
 ('packaging_on_actual_yield116', 'stock', 'switch', 'false', null, null, null,
  'প্যাকেজিং আসল উৎপাদনের হিসাবে', 'Packaging আসল উৎপাদনের হিসাবে', 'Packaging is used for the quantity really made',
  'Off (default) = আজকের মতো, পরিকল্পিত ফলনের হিসাবে। On = আসল ফলন দিলে প্যাকেজিংয়ের পরিমাণ ও খরচ সেই আসল পরিমাণের উপর (শুধু packaging_consume_on = production হলে)।',
  'Off (default) = as today, planned yield. On = when an actual yield is given, packaging quantity and cost follow the quantity really made (only with packaging_consume_on = production).', 751),
 ('std_snapshot_auto116', 'stock', 'switch', 'false', null, null, null,
  'প্রথম উৎপাদনে রেসিপির স্ট্যান্ডার্ড খরচ সংরক্ষণ', 'প্রথম production-এ recipe-র standard cost save', 'Store the recipe standard cost at the first run',
  'Off (default) = আজকের মতো, কিছু সংরক্ষণ হয় না। On = কোনো জায়গায় রেসিপির প্রথম উৎপাদনে সেদিনের গড় দাম × রেসিপির পরিমাণ standard হিসেবে রাখা হয় (price / usage variance report-এর জন্য)। হাতে বসাতে recipe_std_set116।',
  'Off (default) = nothing is stored. On = at the first run of a recipe at a place, the recipe quantities x that day''s average prices are kept as the standard (for the price / usage variance report). To set one by hand use recipe_std_set116.', 752),
 ('std_cost_true116', 'stock', 'switch', 'false', null, null, null,
  'std_cost = সত্যিকারের standard (রেসিপির পরিমাণ × standard দাম)', 'std_cost = আসল standard (recipe qty × standard price)', 'std_cost holds the true standard cost per unit',
  'Off (default) = আজকের মতো: std_cost = (আসল কাঁচামাল + আসল রূপান্তর) / তাত্ত্বিক উৎপাদন (এটা standard নয়, নাম ভুল)। On = std_cost = সংরক্ষিত standard খরচ প্রতি একক। পুরনো সংখ্যাটা cost_full_yield116-এ সবসময় থাকে।',
  'Off (default) = as today: std_cost = (actual material + actual conversion) / theoretical output (a mislabelled number, not a standard). On = std_cost = the stored standard cost per unit. The old number is always kept in cost_full_yield116.', 753),
 ('pool_drivers116', 'stock', 'switch', 'false', null, null, null,
  'ওভারহেড পুল ভাগের একক: কেজি / একক / ব্যাচ / শ্রম-ঘণ্টা', 'Overhead pool ভাগের driver: kg / unit / batch / labour hour', 'Overhead pool drivers: kg, units, batches, labour hours',
  'Off (default) = আজকের মতো, শুধু কেজি (পিস / লিটারের পণ্যে রূপান্তর খরচ শূন্য)। On = জায়গা ও খরচের ধরন অনুযায়ী driver বেছে নেওয়া যায় (loc_cost_driver_set116), সংশ্লিষ্ট "স্বাভাবিক মাসিক পরিমাণ" লিখতে হয়। কোনো সংখ্যা আন্দাজ করা হয় না।',
  'Off (default) = as today: output kg only (piece / litre products get no conversion cost in pool mode). On = pick the driver per place and per cost type (loc_cost_driver_set116); the matching normal monthly quantity must be typed. Nothing is guessed.', 754),
 ('conv_provisional116', 'stock', 'switch', 'false', null, null, null,
  'মাসের পুল না থাকলে আগের মাসের হার দিয়ে সাময়িক রূপান্তর খরচ', 'Month-এর pool না থাকলে আগের মাসের rate-এ provisional conversion cost', 'Provisional conversion cost from the last month with a pool',
  'Off (default) = আজকের মতো, রূপান্তর খরচ শূন্য + হলুদ সতর্কতা। On = মাসের কোনো পুলই না লেখা থাকলে আগের ৬ মাসের মধ্যে সবচেয়ে সাম্প্রতিক পুলের হার ধরা হয়, run "সাময়িক" চিহ্নিত; বিল এলে production_reprice116 দিয়ে ঠিক করুন।',
  'Off (default) = as today, conversion 0 + a yellow flag. On = when the month has no pool at all, the rate of the latest month (up to 6 back) that has one is used and the run is marked PROVISIONAL; re-price it with production_reprice116 once the bills are in.', 755),
 ('cost_supply_to_avg116', 'stock', 'switch', 'false', null, null, null,
  'cost-waiting-এ দেওয়া দাম গড় খরচেও যাবে, রান নতুন করে খরচ ধরবে', 'Cost-waiting-এ দেওয়া দাম avg cost-এও যাবে, run re-cost হবে', 'A supplied cost also reaches the item average and re-costs the run',
  'Off (default) = আজকের মতো, দেওয়া দাম শুধু খাতার overlay-তে থাকে, stock-এর গড় খরচ ফাঁকা থেকে যায়। On = দাম দিলে stock_balance.avg_cost-ও বসে (বা গড়ে মেশে) এবং সেই উৎপাদন run-এর খরচ হালনাগাদ হয়।',
  'Off (default) = as today: the supplied cost lives only in the ledger overlay and the item average stays blank. On = the supplied cost also sets (or blends into) stock_balance.avg_cost and the production run it belongs to is re-costed.', 756)
on conflict (key) do nothing;

-- ---------- columns / tables ----------
alter table public.production_runs add column if not exists conversion_provisional116 boolean not null default false;
alter table public.production_runs add column if not exists cost_full_yield116 numeric;     -- (material + conversion) / theoretical output: what std_cost always held
alter table public.production_runs add column if not exists std_unit_cost116 numeric;       -- the true standard cost per unit (stored standard), when one exists
alter table public.location_cost_cfg add column if not exists driver116 text check (driver116 is null or driver116 in ('output_kg', 'output_units', 'batches', 'labour_hours'));
alter table public.location_cost_cfg add column if not exists normal_units116 numeric check (normal_units116 is null or (normal_units116 > 0 and normal_units116 <= 1000000000));
alter table public.location_cost_cfg add column if not exists normal_batches116 numeric check (normal_batches116 is null or (normal_batches116 > 0 and normal_batches116 <= 1000000000));
alter table public.location_cost_cfg add column if not exists normal_labour_hours116 numeric check (normal_labour_hours116 is null or (normal_labour_hours116 > 0 and normal_labour_hours116 <= 1000000000));
alter table public.cost_component_types add column if not exists driver116 text check (driver116 is null or driver116 in ('output_kg', 'output_units', 'batches', 'labour_hours'));

create table if not exists public.recipe_std116 (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  location_id int not null references public.locations(id),
  yield_per_batch numeric not null check (yield_per_batch > 0),      -- base units of finished good per batch
  mat_per_batch numeric,                                              -- NULL = some ingredient price was unknown (no number is invented)
  conv_per_batch numeric,
  lines jsonb not null,                                               -- [{item_id, kind, qty_per_batch, unit_cost}]
  conv_detail jsonb,
  complete boolean not null,
  source text not null default 'auto' check (source in ('auto', 'manual')),
  active boolean not null default true,
  note text,
  set_by uuid,
  set_at timestamptz not null default now()
);
create unique index if not exists recipe_std116_one_active on public.recipe_std116 (recipe_id, location_id) where active;
create index if not exists recipe_std116_lookup on public.recipe_std116 (recipe_id, location_id, set_at);

create table if not exists public.production_reprice116 (
  id bigserial primary key,
  run_id uuid not null references public.production_runs(id),
  old_conversion numeric not null,
  new_conversion numeric not null,
  delta numeric not null,
  delta_inventory numeric not null,
  delta_cogs numeric not null,
  entry_id bigint,
  by_user uuid,
  at timestamptz not null default now()
);
create unique index if not exists production_reprice116_run on public.production_reprice116 (run_id);

drop trigger if exists rs116_no_delete on public.recipe_std116;
create trigger rs116_no_delete before delete on public.recipe_std116 for each row execute function public.no_hard_delete();
drop trigger if exists pr116_no_delete on public.production_reprice116;
create trigger pr116_no_delete before delete on public.production_reprice116 for each row execute function public.no_hard_delete();
drop trigger if exists audit_rs116 on public.recipe_std116;
create trigger audit_rs116 after insert or update on public.recipe_std116 for each row execute function public.log_change('id');
drop trigger if exists audit_pr116 on public.production_reprice116;
create trigger audit_pr116 after insert or update on public.production_reprice116 for each row execute function public.log_change('id');
alter table public.recipe_std116 enable row level security;
alter table public.production_reprice116 enable row level security;
-- cost secrecy: NO browser SELECT on these tables (like the cost columns of production_runs); they are read only through the cost-right functions (production_variance116, recipe_stage_cost116 ...)
drop policy if exists rs116_read on public.recipe_std116;
drop policy if exists pr116_read on public.production_reprice116;
revoke all on public.recipe_std116, public.production_reprice116 from anon, authenticated;
revoke all on sequence public.recipe_std116_id_seq, public.production_reprice116_id_seq from anon, authenticated;
-- bos116: does the (active) recipe tree of p_from contain p_target? (cycle guard for semi-finished ingredients; depth capped at 12)
create or replace function public._recipe_reaches116(p_from uuid, p_target uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive t(i, d) as (
    select p_from, 1
    union all
    select rl.ingredient_item_id, t.d + 1 from t join public.recipes r on r.item_id = t.i and r.active join public.recipe_lines rl on rl.recipe_id = r.id and rl.active where t.d < 12)
  select exists (select 1 from t where i = p_target);
$$;

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
    if ing.item_type not in ('raw_material', 'packaging', 'resale') and not (ing.item_type = 'finished_good' and public.rule_on('semi_finished_ingredient116')) then raise exception 'bad_ingredient_type' using detail = ing.code; end if;   -- bos116: semi-finished goods behind a switch
    if ing.item_type = 'finished_good' and public.rule_on('semi_finished_ingredient116') and public._recipe_reaches116(iid, p_item) then raise exception 'recipe_cycle' using detail = ing.code; end if;   -- bos116
    if iid = any(seen) then raise exception 'dup_ingredient'; end if;
    seen := seen || iid;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or not (q > 0 and q < 1000000000) then raise exception 'bad_qty'; end if;
    w := nullif(ln->>'waste_pct', '')::numeric;
    if w is not null and not (w between 0 and 100) then raise exception 'bad_waste'; end if;
    if public._base_qty(iid, q, nullif(btrim(ln->>'unit'), '')) is null then raise exception 'unit_unknown' using detail = ing.code; end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._recipe_need116(p_recipe uuid, p_batches numeric, p_loc integer, p_out numeric)
 RETURNS TABLE(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      select i.id, 'packaging'::text, round(pp.qty_per_unit * case when p_out is not null and public.rule_on('packaging_on_actual_yield116') then p_out else yb end, 4) /* bos116: packaging on the quantity really made, behind a switch */, coalesce(b.qty, 0), i.tracked, true, false, i.code, i.name_bn, i.name_en, public._item_base(i.id)
        from public.product_packaging pp join public.items i on i.id = pp.packaging_item_id
        left join public.stock_balance b on b.item_id = i.id and b.location_id = p_loc
       where coalesce(public.rule_txt('packaging_consume_on'), 'off') = 'production' and pp.product_item_id = r.item_id and pp.active and pp.applies_to = 'production') z
    group by z.item_id, z.code, z.name_bn, z.name_en, z.base_unit;
end $function$;

-- bos116: the old 3-argument entry point is a thin wrapper (planned yield) so every reader keeps working
create or replace function public._recipe_need(p_recipe uuid, p_batches numeric, p_loc integer)
returns table(item_id uuid, kind text, need numeric, on_hand numeric, tracked boolean, unit_ok boolean, waste_missing boolean, code text, name_bn text, name_en text, base_unit text)
language sql stable security definer set search_path = public as $$
  select * from public._recipe_need116(p_recipe, p_batches, p_loc, null::numeric);   -- bos116
$$;

-- bos116: provisional pool rate of a cost type: the latest of the 6 months before p_month that has a pool figure (never a guess: the month is named in the result)
create or replace function public._pool_rate_prov116(p_loc int, p_month date, p_type text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k int; pm date; pr jsonb;
begin
  for k in 1 .. 6 loop
    pm := (p_month - make_interval(months => k))::date;
    pr := public._pool_rate(p_loc, pm, p_type);
    if (pr ->> 'amount') is not null then return pr || jsonb_build_object('from', pm); end if;
  end loop;
  return jsonb_build_object('amount', null);
end $$;

CREATE OR REPLACE FUNCTION public._conv_cost(p_recipe uuid, p_loc integer, p_batches numeric, p_out numeric, p_date date, p_force_mode text DEFAULT NULL::text)
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
end $function$;

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
        prov boolean := false; sn public.recipe_std116; stdu numeric; stdc numeric;   -- bos116
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
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) loop
    if not n.tracked then raise exception 'ingredient_not_tracked' using detail = coalesce(n.code, ''); end if;
    if not n.unit_ok then raise exception 'unit_unknown' using detail = coalesce(n.code, ''); end if;
    if n.waste_missing then wm := wm + 1; end if;
  end loop;
  if wm > 0 and public.rule_on('recipe_waste_required') then raise exception 'waste_needed'; end if;
  mode := coalesce(public.rule_txt('production_short_mode'), 'refuse');
  -- bos109: lock every ingredient / packaging balance AND the finished-good balance of this place in ONE item order BEFORE the shortage check, so two cooks (or a cook and a sale)
  -- cannot both pass the check on the same stock, and the later stock_post calls never take a lock in another order (no lock-order deadlock between recipes)
  perform 1 from public.stock_balance sbl where sbl.location_id = p_loc and (sbl.item_id = r.item_id or sbl.item_id in (select n2.item_id from public._recipe_need116(r.id, p_batches, p_loc, outq) n2)) order by sbl.item_id for update;   -- bos109
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0
         and not public._cost_free80(n.item_id) then      -- bos80: an item marked 'cost really zero' is a known cost
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if public.rule_on('std_snapshot_auto116') and not exists (select 1 from public.recipe_std116 where recipe_id = r.id and location_id = p_loc) then      -- bos116: the first run stores the standard (prices of today, before anything is issued)
    perform public._recipe_std_snap116(r.id, p_loc, 'auto', null, (at_ at time zone 'Asia/Dhaka')::date);
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need116(r.id, p_batches, p_loc, outq) order by item_id loop
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
  prov := coalesce((conv->>'provisional')::boolean, false);      -- bos116
  -- finished good IN: batch + expiry from the owner's shelf-life rules (no rule = no expiry); the cost is material + conversion when every ingredient has a known cost
  sl := public.shelf_life_for(r.item_id, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (r.item_id, p_loc, at_, outq, outq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  ucb := case when cost_ok and outq > 0 then round((tot + conv_amt) / outq, 6) end;      -- bos74: (material + conversion) / actual output
  derived := md5(coalesce(p_client::text, rid::text) || ':in')::uuid;
  lid := public.stock_post(r.item_id, p_loc, outq, 'production_in', 'production', rid::text, ucb, bid, at_, left(p_note, 200), null, 'none', null, derived);
  yvp := case when p_actual_yield is not null and yb > 0 then round((outq - yb) / yb * 100, 2) end;
  select * into sn from public.recipe_std116 where recipe_id = r.id and location_id = p_loc and active;      -- bos116: the stored standard (if any)
  stdu := case when sn.id is not null and sn.complete and sn.mat_per_batch is not null and sn.conv_per_batch is not null then round((sn.mat_per_batch + sn.conv_per_batch) / sn.yield_per_batch, 6) end;      -- bos116
  update public.production_runs set ledger_in_id = lid, batch_id = bid, cost_complete = cost_ok,
      material_cost = case when cost_ok then round(tot, 4) end, conversion_cost = round(conv_amt, 4), unit_cost = ucb,
      std_cost = case when public.rule_on('std_cost_true116') then stdu when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, actual_cost = ucb,
      cost_full_yield116 = case when cost_ok and yb > 0 then round((tot + conv_amt) / yb, 6) end, std_unit_cost116 = stdu, conversion_provisional116 = prov,      -- bos116
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
  if prov then      -- bos116
    perform public._stock_exc(p_loc, 'conversion_provisional', 'yellow', it.name_bn || ': রূপান্তর খরচ সাময়িক (আগের মাসের হারে) — মাসের বিল এলে production_reprice116 দিয়ে ঠিক করুন',
      coalesce(it.name_en, it.name_bn) || ': conversion cost is PROVISIONAL (last month''s rate) — re-price it with production_reprice116 once this month''s bills are in', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  ythr := public.rule_num('yield_variance_warn_pct');      -- bos74
  if yvp is not null and ythr is not null and abs(yvp) > ythr then
    perform public._stock_exc(p_loc, 'yield_variance', 'yellow', it.name_bn || ': আসল উৎপাদন রেসিপির ফলন থেকে ' || yvp::text || '% আলাদা',
      coalesce(it.name_en, it.name_bn) || ': actual yield differs from the recipe yield by ' || yvp::text || '%', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', outq, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) ||
    case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok, 'conversion_complete', not cinc, 'unit_cost', ucb) else '{}'::jsonb end;
end $function$;

CREATE OR REPLACE FUNCTION public.production_run_costs(p_loc integer, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', r.conversion_cost, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', r.actual_cost,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail,
      'cost_full_yield', r.cost_full_yield116, 'std_unit_cost', r.std_unit_cost116, 'conversion_provisional', r.conversion_provisional116,
      'yield_loss_money', case when r.cost_complete and coalesce(r.yield_std, 0) > 0 and r.yield_actual is not null then round((coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) * (1 - r.yield_base / r.yield_std), 2) end) order by r.made_at, r.id)      -- bos116
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.production_void(p_run uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare run public.production_runs; r record; b public.stock_batches; n int := 0;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(run.location_id) or not (public.is_owner() or public.has_grant('production_void', run.location_id)) then raise exception 'not allowed'; end if;
  if run.status = 'void' then return jsonb_build_object('id', run.id, 'status', 'void', 'dup', true); end if;
  if exists (select 1 from public.production_reprice116 x where x.run_id = run.id) then raise exception 'run_repriced'; end if;      -- bos116: a re-priced run has an adjustment entry; it cannot be undone silently
  perform public.lock_check((run.made_at at time zone 'Asia/Dhaka')::date);
  -- the finished goods must still be unsold: a partly sold batch cannot be undone (use wastage / count instead)
  if run.batch_id is not null then
    select * into b from public.stock_batches where id = run.batch_id for update;
    if found and b.qty_remaining < b.qty_made - 0.0001 then raise exception 'batch_partly_used'; end if;
  end if;
  for r in select o.* from public.stock_ledger o where o.ref_type = 'production' and o.ref_id = run.id::text and o.reason in ('issue_out', 'production_in')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'production', run.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
    n := n + 1;
  end loop;
  update public.production_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = run.id;
  return jsonb_build_object('id', run.id, 'status', 'void', 'reversed_lines', n);
end $function$;

CREATE OR REPLACE FUNCTION public.cost_wait_supply96(p_kind text, p_ref text, p_method text, p_manual jsonb DEFAULT NULL::jsonb, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_post boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if public.rule_on('cost_supply_to_avg116') then perform public._cw_apply_avg116(p_client, p_kind, p_ref); end if;      -- bos116: the supplied cost also reaches the item average and the run
  if coalesce(p_post, true) and public.rule_on('accounting_on') and public._acct_manage() then pr := public.acct_post_pending(false, 1500); end if;
  posted := public._cw_posted96(p_kind, p_ref);
  return jsonb_build_object('kind', p_kind, 'ref', p_ref, 'method', p_method, 'rows', n, 'total', pl->'total', 'posted', posted,
    'post_run', case when pr is null then null else jsonb_build_object('posted', pr->'posted', 'locked', pr->'locked', 'errors', pr->'errors') end);
end $function$;

-- ============================================================
-- New functions (nothing here runs until somebody calls it)
-- ============================================================

-- the standard of a recipe at a place: recipe quantities (waste included, per ONE batch) x the weighted-average price of that day; conversion per batch from the place's mode.
-- A price that is unknown stays NULL and the snapshot is marked incomplete: no number is invented.
create or replace function public._recipe_std_snap116(p_recipe uuid, p_loc int, p_source text, p_note text, p_date date) returns bigint
language plpgsql security definer set search_path = public as $$
declare r public.recipes; yb numeric; ln jsonb := '[]'::jsonb; mat numeric := 0; ok boolean := true; n record; av numeric; conv jsonb; cv numeric; nid bigint;
begin
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  if yb is null or not (yb > 0) then raise exception 'unit_unknown'; end if;
  for n in select * from public._recipe_need116(p_recipe, 1, p_loc, null) order by item_id loop
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc;
    if coalesce(av, 0) <= 0 and not public._cost_free80(n.item_id) then ok := false; av := null; else mat := mat + n.need * coalesce(av, 0); end if;
    ln := ln || jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'qty_per_batch', n.need, 'unit_cost', av);
  end loop;
  conv := public._conv_cost(p_recipe, p_loc, 1, yb, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date));
  cv := case when (conv ->> 'mode') = 'off' or (conv ->> 'complete')::boolean then (conv ->> 'amount')::numeric end;
  if cv is null then ok := false; end if;
  update public.recipe_std116 set active = false where recipe_id = p_recipe and location_id = p_loc and active;
  insert into public.recipe_std116 (recipe_id, location_id, yield_per_batch, mat_per_batch, conv_per_batch, lines, conv_detail, complete, source, note, set_by)
    values (p_recipe, p_loc, yb, case when ok then round(mat, 4) end, case when cv is not null then round(cv, 4) end, ln, conv -> 'detail', ok and cv is not null, p_source, left(p_note, 300), auth.uid()) returning id into nid;
  return nid;
end $$;

-- the owner (or a recipe manager with the cost right) sets / renews the standard of a recipe at a place from TODAY's average prices
create or replace function public.recipe_std_set116(p_recipe uuid, p_loc int, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint; s public.recipe_std116;
begin
  if not (public._recipe_mgr() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  nid := public._recipe_std_snap116(p_recipe, p_loc, 'manual', p_note, null);
  select * into s from public.recipe_std116 where id = nid;
  return jsonb_build_object('id', nid, 'complete', s.complete, 'material_per_batch', s.mat_per_batch, 'conversion_per_batch', s.conv_per_batch, 'yield_per_batch', s.yield_per_batch,
    'standard_unit_cost', case when s.complete then round((s.mat_per_batch + s.conv_per_batch) / s.yield_per_batch, 6) end);
end $$;

-- standard vs actual per run (money). Standard = the snapshot that was active when the run was made (p_use_latest = true: the newest snapshot, to look back at old runs).
--   price_var   = sum (actual price - standard price) x actual quantity                      (+ = dearer than standard)
--   usage_var   = sum (actual quantity - standard quantity for the OUTPUT really made) x standard price   (includes the yield loss at standard price)
--   conv_var    = actual conversion - standard conversion x (output / theoretical output)
--   total_var   = actual cost - standard cost of the output = price_var + usage_var + conv_var
--   yield_loss_money = actual cost x (1 - output / theoretical output): the share of what was spent that produced nothing (A1 a8: 3237 x 1.5/20 = 242.78)
create or replace function public.production_variance116(p_loc int, p_from date, p_to date, p_use_latest boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; sn public.recipe_std116; rows_ jsonb := '[]'::jsonb; scale numeric; act_mat numeric; unk int; pv numeric; uv numeric; cvv numeric; std_mat numeric; std_conv numeric; act_conv numeric; act_tot numeric; ylm numeric; ylS numeric; ok boolean; why text;
        t_pv numeric := 0; t_uv numeric := 0; t_cv numeric := 0; t_yl numeric := 0; t_act numeric := 0; t_std numeric := 0; nrun int := 0; nstd int := 0;
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  for r in select pr.*, i.code from public.production_runs pr join public.items i on i.id = pr.item_id
            where pr.location_id = p_loc and pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31') order by pr.made_at, pr.id loop
    nrun := nrun + 1; ok := true; why := null; pv := null; uv := null; cvv := null; std_mat := null; std_conv := null; ylm := null; ylS := null;
    select s.* into sn from public.recipe_std116 s where s.recipe_id = r.recipe_id and s.location_id = r.location_id and (s.set_at <= r.created_at or coalesce(p_use_latest, false)) order by s.set_at desc, s.id desc limit 1;
    act_conv := coalesce(r.conversion_cost, 0);
    select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 0), count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id))
      into act_mat, unk from public.stock_ledger_eff96 l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.reverses_id is null
        and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
    act_tot := act_mat + act_conv;
    if unk > 0 then ok := false; why := 'ingredient_cost_unknown'; end if;
    if coalesce(r.yield_std, 0) > 0 and unk = 0 then ylm := round(act_tot * (1 - r.yield_base / r.yield_std), 2); end if;
    if sn.id is null then ok := false; why := coalesce(why, 'no_standard');
    elsif not sn.complete then ok := false; why := coalesce(why, 'standard_incomplete');
    elsif unk = 0 and coalesce(r.yield_std, 0) > 0 then
      scale := r.yield_base / r.yield_std;
      with act as (select l.item_id, sum(-l.qty_delta) q, sum(-l.qty_delta * l.unit_cost) amt from public.stock_ledger_eff96 l
                    where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id) group by l.item_id),
           std as (select (x ->> 'item_id')::uuid item_id, (x ->> 'qty_per_batch')::numeric qb, nullif(x ->> 'unit_cost', '')::numeric sp from jsonb_array_elements(sn.lines) x),
           j as (select a.q, a.amt, s.qb, s.sp, s.item_id sid from act a full join std s on s.item_id = a.item_id)
      select coalesce(sum(case when j.sp is not null and j.q is not null then coalesce(j.amt, 0) - j.sp * j.q else 0 end), 0),
             coalesce(sum(case when j.sp is not null then (coalesce(j.q, 0) - coalesce(j.qb, 0) * r.batches * scale) * j.sp else coalesce(j.amt, 0) end), 0),
             coalesce(sum(coalesce(j.qb, 0) * r.batches * scale * j.sp), 0)
        into pv, uv, std_mat from j;
      std_conv := sn.conv_per_batch * r.batches * scale;
      cvv := act_conv - std_conv;
    end if;
    if ok and pv is not null then
      t_pv := t_pv + pv; t_uv := t_uv + uv; t_cv := t_cv + cvv; t_act := t_act + act_tot; t_std := t_std + std_mat + std_conv; nstd := nstd + 1;
    end if;
    if ylm is not null and unk = 0 then t_yl := t_yl + ylm; end if;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'item_id', r.item_id, 'code', r.code, 'batches', r.batches, 'theoretical_output', r.yield_std, 'output', r.yield_base,
      'actual_material', round(act_mat, 2), 'actual_conversion', round(act_conv, 2), 'actual_total', round(act_tot, 2), 'standard_available', sn.id is not null, 'standard_set_at', sn.set_at,
      'standard_material', case when ok and pv is not null then round(std_mat, 2) end, 'standard_conversion', case when ok and pv is not null then round(std_conv, 2) end,
      'standard_total', case when ok and pv is not null then round(std_mat + std_conv, 2) end,
      'price_var', case when ok and pv is not null then round(pv, 2) end, 'usage_var', case when ok and pv is not null then round(uv, 2) end, 'conv_var', case when ok and pv is not null then round(cvv, 2) end,
      'total_var', case when ok and pv is not null then round(act_tot - std_mat - std_conv, 2) end,
      'yield_loss_money', ylm, 'conversion_provisional', r.conversion_provisional116, 'complete', ok and pv is not null, 'why', why);
  end loop;
  return jsonb_build_object('location_id', p_loc, 'from', p_from, 'to', p_to, 'runs', nrun, 'runs_with_standard', nstd, 'rows', rows_,
    'totals', jsonb_build_object('price_var', round(t_pv, 2), 'usage_var', round(t_uv, 2), 'conv_var', round(t_cv, 2), 'total_var', round(t_pv + t_uv + t_cv, 2), 'actual_total', round(t_act, 2), 'standard_total', round(t_std, 2), 'yield_loss_money', round(t_yl, 2)),
    'note', 'price_var + usage_var + conv_var = actual cost - standard cost of the output really made. yield_loss_money is a memo at ACTUAL cost (already inside usage_var at standard price). A run with no stored standard shows only its actual figures.');
end $$;

-- place default driver and the normal monthly quantity that goes with it (owner only). A NULL quantity leaves the stored one.
create or replace function public.loc_cost_driver_set116(p_loc int, p_driver text, p_normal_units numeric default null, p_normal_batches numeric default null, p_normal_hours numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_driver is not null and p_driver not in ('output_kg', 'output_units', 'batches', 'labour_hours') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  if (p_normal_units is not null and not (p_normal_units > 0 and p_normal_units <= 1000000000)) or (p_normal_batches is not null and not (p_normal_batches > 0 and p_normal_batches <= 1000000000))
     or (p_normal_hours is not null and not (p_normal_hours > 0 and p_normal_hours <= 1000000000)) then raise exception 'bad_qty'; end if;
  insert into public.location_cost_cfg (location_id, mode, driver116, normal_units116, normal_batches116, normal_labour_hours116, updated_by, updated_at)
    values (p_loc, 'off', p_driver, p_normal_units, p_normal_batches, p_normal_hours, auth.uid(), now())
    on conflict (location_id) do update set driver116 = excluded.driver116, normal_units116 = coalesce(excluded.normal_units116, public.location_cost_cfg.normal_units116),
      normal_batches116 = coalesce(excluded.normal_batches116, public.location_cost_cfg.normal_batches116), normal_labour_hours116 = coalesce(excluded.normal_labour_hours116, public.location_cost_cfg.normal_labour_hours116),
      updated_by = auth.uid(), updated_at = now();
end $$;

-- driver of ONE cost type (labour by labour hours, gas by kg ...); NULL = follow the place default
create or replace function public.cost_type_driver_set116(p_code text, p_driver text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_driver is not null and p_driver not in ('output_kg', 'output_units', 'batches', 'labour_hours') then raise exception 'bad_value'; end if;
  update public.cost_component_types set driver116 = p_driver where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- G7: a cost supplied from the cost-waiting list reaches stock_balance.avg_cost (and re-costs the run it belongs to).
--   avg blank / 0: the item takes the supplied cost.   avg known: blended, the units that were supplied weigh with their supplied cost, the rest with the average (same formula as _avg_next).
--   The average is moved through the ledger, not by an UPDATE: the whole on-hand stock goes out and comes back IN AT THE NEW AVERAGE (reason cost_adjust, same cost on both rows = no change of
--   ledger value, the overlay already carries the value), so stock_reconcile (replay of the ledger) still agrees with the cached average and a reconcile-fix cannot undo it.
create or replace function public._cw_apply_avg116(p_client uuid, p_kind text, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare r record; bal public.stock_balance; qs numeric; na numeric;
begin
  for r in select l.item_id, l.location_id, sum(l.qty_delta) q, sum(l.qty_delta * s.unit_cost) / nullif(sum(l.qty_delta), 0) uc
             from public.ledger_cost_supply96 s join public.stock_ledger l on l.id = s.ledger_id
            where s.client_id = p_client and l.qty_delta > 0 group by 1, 2 order by 1, 2 loop
    select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = r.location_id for update;
    if not found or r.uc is null or r.uc <= 0 or bal.qty <= 0 then continue; end if;
    qs := least(r.q, bal.qty);
    na := round(case when coalesce(bal.avg_cost, 0) <= 0 then r.uc else (bal.avg_cost * (bal.qty - qs) + r.uc * qs) / bal.qty end, 6);
    if na is not distinct from bal.avg_cost then continue; end if;
    insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
      values (r.item_id, r.location_id, -bal.qty, na, 'cost_adjust', 'costsupply116', p_ref, now(), 'supplied cost: stock out (no value change)', auth.uid());
    insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
      values (r.item_id, r.location_id, bal.qty, na, 'cost_adjust', 'costsupply116', p_ref, now(), 'supplied cost: stock back in at the new average', auth.uid());
  end loop;
  if p_kind = 'production' and p_ref ~ '^[0-9a-f-]{36}$' then perform public._cw_run_recost116(p_ref::uuid); end if;
end $$;

create or replace function public._cw_run_recost116(p_run uuid) returns void
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; mat numeric; unk int; cnt int; conv numeric;
begin
  select * into run from public.production_runs where id = p_run for update;
  if not found or run.status <> 'done' or coalesce(run.yield_base, 0) <= 0 then return; end if;
  select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 0), count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)), count(*)
    into mat, unk, cnt from public.stock_ledger_eff96 l where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null
      and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
  if unk > 0 or cnt = 0 then return; end if;
  conv := coalesce(run.conversion_cost, 0);
  update public.production_runs set material_cost = round(mat, 4), cost_complete = true, unit_cost = round((mat + conv) / yield_base, 6), actual_cost = round((mat + conv) / yield_base, 6),
      cost_full_yield116 = case when coalesce(yield_std, 0) > 0 then round((mat + conv) / yield_std, 6) end,
      std_cost = case when public.rule_on('std_cost_true116') then std_cost when coalesce(yield_std, 0) > 0 then round((mat + conv) / yield_std, 6) else std_cost end
    where id = p_run;
end $$;

-- G4: work queue of runs whose cost is not final: conversion provisional or incomplete (pool mode), or an ingredient cost unknown
create or replace function public.production_cost_queue116(p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'code', i.code, 'output', r.yield_base, 'unit_cost', r.unit_cost, 'conversion_mode', r.conversion_mode,
      'reason', case when r.cost_complete is not true then 'ingredient_cost_unknown' when r.conversion_provisional116 then 'conversion_provisional' else 'conversion_incomplete' end,
      'month', public._m1((r.made_at at time zone 'Asia/Dhaka')::date)) order by r.made_at, r.id)
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')
      and (r.cost_complete is not true or r.conversion_provisional116 or (r.conversion_mode is not null and r.conversion_mode <> 'off' and r.conversion_complete is not true))), '[]'::jsonb);
end $$;

-- G4: re-price the POOL-mode runs of a month whose conversion was provisional or incomplete, now that the month's pool is typed. DRY by default.
--   Per run: delta = new conversion - booked conversion. The on-hand share of the run's output (min(1, finished good on hand / run output)) moves the item average and
--   Dr/Cr 1310; the sold share goes to cost of goods sold. Cr/Dr overhead absorbed takes the whole delta. One adjustment entry per run (source prod_reprice116), dated today.
--   If the run's own journal entry is not posted yet, no adjustment entry is made (it will post with the new conversion cost).
create or replace function public.production_reprice116(p_loc int, p_month date, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._m1(p_month); r record; conv jsonb; d numeric; bal public.stock_balance; q numeric; share numeric; dinv numeric; dcogs numeric; rows_ jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb;
        acct boolean; today_ date; lines jsonb; ent bigint; has_je boolean; n int := 0; tot numeric := 0; newc numeric; rdate date; na numeric;
begin
  if not (public._recipe_mgr() and public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  perform set_config('bos.no_prov116', 'on', true);      -- _conv_cost sees only the REAL pool of the month
  acct := public.rule_on('accounting_on') and public._acct_start() is not null;
  today_ := public._acct_today();
  for r in select pr.* from public.production_runs pr where pr.location_id = p_loc and pr.status = 'done' and public._m1((pr.made_at at time zone 'Asia/Dhaka')::date) = m
             and pr.conversion_mode = 'pool' and (pr.conversion_provisional116 or pr.conversion_complete is not true) order by pr.made_at, pr.id for update loop
    rdate := (r.made_at at time zone 'Asia/Dhaka')::date;
    if r.cost_complete is not true then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', 'ingredient_cost_unknown'); continue; end if;
    conv := public._conv_cost(r.recipe_id, p_loc, r.batches, r.yield_base, rdate, 'pool');
    if not (conv ->> 'complete')::boolean then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', coalesce(conv ->> 'reason', 'pool_missing')); continue; end if;
    newc := (conv ->> 'amount')::numeric;
    d := round(newc - coalesce(r.conversion_cost, 0), 2);
    select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = p_loc;
    q := coalesce(bal.qty, 0);
    share := case when bal.avg_cost is null or coalesce(r.yield_base, 0) <= 0 then 0 else least(1, greatest(q, 0) / r.yield_base) end;
    dinv := round(d * share, 2); dcogs := d - dinv;
    has_je := exists (select 1 from public.journal_entries e where e.source_type = 'production' and e.source_id = r.id::text and e.reverses_id is null);
    if acct and has_je and abs(d) >= 0.005 and (rdate < public._acct_start() or public._acct_locked(today_)) then skipped := skipped || jsonb_build_object('run_id', r.id, 'why', 'period_closed_or_before_start'); continue; end if;
    n := n + 1; tot := tot + d;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'old_conversion', coalesce(r.conversion_cost, 0), 'new_conversion', round(newc, 4), 'delta', d, 'to_inventory', dinv, 'to_cogs', dcogs, 'journal', acct and has_je and abs(d) >= 0.005);
    if p_dry then continue; end if;
    if dinv <> 0 and q > 0 and bal.avg_cost is not null then      -- same technique as landed_post: the whole on-hand stock goes out at the old average and comes back at the new one (reason cost_adjust), so the ledger value and the average move together
      select * into bal from public.stock_balance b where b.item_id = r.item_id and b.location_id = p_loc for update;
      q := bal.qty; na := greatest(round((q * bal.avg_cost + dinv) / q, 6), 0);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (r.item_id, p_loc, -q, bal.avg_cost, 'cost_adjust', 'reprice116', r.id::text, now(), 'overhead re-price: stock out at the old average', auth.uid());
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at, note, created_by)
        values (r.item_id, p_loc, q, na, 'cost_adjust', 'reprice116', r.id::text, now(), 'overhead re-price: stock back in at the new average', auth.uid());
    end if;
    ent := null;
    if acct and has_je and abs(d) >= 0.005 then
      lines := '[]'::jsonb;
      if dinv <> 0 then lines := lines || jsonb_build_object('a', 'inv_finished', case when dinv > 0 then 'd' else 'c' end, abs(dinv)); end if;
      if dcogs <> 0 then lines := lines || jsonb_build_object('a', 'cogs', case when dcogs > 0 then 'd' else 'c' end, abs(dcogs)); end if;
      lines := lines || jsonb_build_object('a', 'overhead_absorbed', case when d > 0 then 'c' else 'd' end, abs(d));
      ent := public._acct_write(today_, p_loc, 'prod_reprice116', r.id::text, null, 'Overhead re-priced for run ' || to_char(r.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), null, public._acct_resolve(lines, p_loc));
    end if;
    update public.production_runs set conversion_cost = round(newc, 4), conversion_detail = conv -> 'detail', conversion_complete = true, conversion_provisional116 = false,
        unit_cost = round((coalesce(material_cost, 0) + newc) / yield_base, 6), actual_cost = round((coalesce(material_cost, 0) + newc) / yield_base, 6),
        cost_full_yield116 = case when coalesce(yield_std, 0) > 0 then round((coalesce(material_cost, 0) + newc) / yield_std, 6) end,
        std_cost = case when public.rule_on('std_cost_true116') then std_cost when coalesce(yield_std, 0) > 0 then round((coalesce(material_cost, 0) + newc) / yield_std, 6) else std_cost end
      where id = r.id;
    insert into public.production_reprice116 (run_id, old_conversion, new_conversion, delta, delta_inventory, delta_cogs, entry_id, by_user)
      values (r.id, coalesce(r.conversion_cost, 0), round(newc, 4), d, dinv, dcogs, ent, auth.uid());
  end loop;
  return jsonb_build_object('dry', p_dry, 'location_id', p_loc, 'month', m, 'runs', n, 'total_delta', round(tot, 2), 'rows', rows_, 'skipped', skipped,
    'note', 'Only POOL-mode runs of this month that were provisional or incomplete. Stock average moves for the on-hand share; the sold share goes to cost of goods sold; one entry per run.');
end $$;

-- G1: the stage split of a recipe's material cost: which lines are semi-finished goods (made in-house) and what that semi-finished good cost to make (its latest run)
create or replace function public.recipe_stage_cost116(p_recipe uuid, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; n record; av numeric; ln jsonb := '[]'::jsonb; semi_t numeric := 0; other_t numeric := 0; amt numeric; it public.items; lr public.production_runs; unknown boolean := false;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  for n in select * from public._recipe_need116(p_recipe, 1, p_loc, null) order by kind, code loop
    select * into it from public.items where id = n.item_id;
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc;
    amt := case when coalesce(av, 0) > 0 then round(n.need * av, 4) end;
    if amt is null and not public._cost_free80(n.item_id) then unknown := true; end if;
    if it.item_type = 'finished_good' then semi_t := semi_t + coalesce(amt, 0); else other_t := other_t + coalesce(amt, 0); end if;
    lr := null;
    if it.item_type = 'finished_good' then select * into lr from public.production_runs x where x.item_id = n.item_id and x.location_id = p_loc and x.status = 'done' order by x.made_at desc limit 1; end if;
    ln := ln || jsonb_build_object('item_id', n.item_id, 'code', n.code, 'kind', n.kind, 'semi_finished', it.item_type = 'finished_good', 'qty', n.need, 'avg_cost', av, 'amount', amt,
      'stage', case when lr.id is not null then jsonb_build_object('run_id', lr.id, 'material_cost', lr.material_cost, 'conversion_cost', lr.conversion_cost, 'unit_cost', lr.unit_cost) end);
  end loop;
  return jsonb_build_object('recipe_id', p_recipe, 'location_id', p_loc, 'lines', ln, 'semi_finished_amount', round(semi_t, 4), 'other_amount', round(other_t, 4), 'unknown_cost', unknown);
end $$;

-- G7: re-cost a run whose ingredient cost was unknown when it was made (cost_complete false), now that the ingredients have an average cost.
--   Ingredient lines with no cost are priced at the CURRENT item average (never guessed: an ingredient with no average stops the run, supply it first through the cost-waiting list).
--   The cost goes into the ledger overlay (as the cost-waiting list does), the run row is re-costed, the finished-good average takes the new unit cost (blend by quantity),
--   and if the run's journal entry was already posted (partial, flag cogs_missing) it is reversed and re-posted at the full cost (source prod_recost116). DRY by default.
create or replace function public.production_recost116(p_run uuid, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; n record; av numeric; items_ jsonb := '[]'::jsonb; missing text := ''; mat_known numeric; added numeric := 0; conv numeric; mat_new numeric; uc numeric; cl uuid := gen_random_uuid();
        ent bigint; today_ date := public._acct_today(); lines jsonb; z record; sum_d numeric := 0; ev text; staff text; lin bigint; acct boolean;
begin
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._recipe_mgr() and public._cost_ok(run.location_id) and public.can_loc(run.location_id)) then raise exception 'not allowed'; end if;
  if run.status <> 'done' then raise exception 'run_void'; end if;
  if run.cost_complete is true then return jsonb_build_object('run_id', run.id, 'nothing_to_do', true); end if;
  for n in select l.id lid, l.item_id, -l.qty_delta q, i.code from public.stock_ledger_eff96 l join public.items i on i.id = l.item_id
            where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
              and coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id) order by l.id loop
    select b.avg_cost into av from public.stock_balance b where b.item_id = n.item_id and b.location_id = run.location_id;
    if coalesce(av, 0) <= 0 then missing := missing || case when missing = '' then '' else ', ' end || n.code; continue; end if;
    items_ := items_ || jsonb_build_object('ledger_id', n.lid, 'item_id', n.item_id, 'code', n.code, 'qty', n.q, 'unit_cost', av, 'amount', round(n.q * av, 2));
    added := added + round(n.q * av, 2);
  end loop;
  if missing <> '' then raise exception 'cost_unavailable' using detail = missing, hint = 'Supply the ingredient cost first (cost-waiting list or a purchase)'; end if;
  if jsonb_array_length(items_) = 0 then raise exception 'nothing_waiting'; end if;
  select coalesce(sum(-l.qty_delta * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0), 0) into mat_known from public.stock_ledger_eff96 l
    where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' and l.reverses_id is null and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id);
  conv := coalesce(run.conversion_cost, 0);
  mat_new := mat_known + added; uc := round((mat_new + conv) / run.yield_base, 6);
  if p_dry then
    return jsonb_build_object('dry', true, 'run_id', p_run, 'lines', items_, 'material_known', round(mat_known, 2), 'material_added', added, 'material_new', round(mat_new, 2), 'conversion', conv, 'unit_cost_new', uc);
  end if;
  acct := public.rule_on('accounting_on') and public._acct_start() is not null;
  select e.id into ent from public.journal_entries e where e.source_type = 'production' and e.source_id = p_run::text and e.reverses_id is null
     and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id);
  if acct and ent is not null and (public._acct_locked(today_) or today_ < public._acct_start()) then raise exception 'period_closed'; end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  for n in select * from jsonb_to_recordset(items_) as x(ledger_id bigint, unit_cost numeric) loop
    insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, supplied_by, supplied_staff)
      values (n.ledger_id, n.unit_cost, 'item_average', 'run re-costed (production_recost116)', 'production', p_run::text, cl, auth.uid(), staff);
  end loop;
  if run.ledger_in_id is not null and not exists (select 1 from public.stock_ledger_eff96 l where l.id = run.ledger_in_id and coalesce(l.unit_cost, 0) > 0) and uc > 0 then
    insert into public.ledger_cost_supply96 (ledger_id, unit_cost, method, reason, doc_kind, doc_ref, client_id, supplied_by, supplied_staff)
      values (run.ledger_in_id, uc, 'from_ingredients', 'run re-costed (production_recost116)', 'production', p_run::text, cl, auth.uid(), staff);
  end if;
  perform public._cw_apply_avg116(cl, 'production', p_run::text);
  if acct and ent is not null then
    perform public._acct_reverse(ent, today_, 'Reversal: production re-costed');
    lines := '[]'::jsonb;
    for z in select * from public._acct_inv_split72(array['production'], p_run::text, array['issue_out'], -1) where amt > 0 loop
      lines := lines || jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt); sum_d := sum_d + z.amt;
    end loop;
    if round(conv, 2) >= 0.005 then lines := lines || jsonb_build_object('a', 'overhead_absorbed', 'c', round(conv, 2)); end if;
    lines := jsonb_build_array(jsonb_build_object('a', 'inv_finished', 'd', sum_d + case when round(conv, 2) >= 0.005 then round(conv, 2) else 0 end)) || lines;
    perform public._acct_write(today_, run.location_id, 'prod_recost116', p_run::text, null, 'Production re-costed (ingredient cost became known)', null, public._acct_resolve(lines, run.location_id));
  end if;
  return jsonb_build_object('dry', false, 'run_id', p_run, 'lines', items_, 'material_new', round(mat_new, 2), 'conversion', conv, 'unit_cost', uc, 'journal_reposted', acct and ent is not null);
end $$;

-- ---------- privileges ----------
revoke all on function public._recipe_reaches116(uuid, uuid), public._recipe_need116(uuid, numeric, integer, numeric), public._pool_rate_prov116(int, date, text), public._recipe_std_snap116(uuid, int, text, text, date),
  public._cw_apply_avg116(uuid, text, text), public._cw_run_recost116(uuid) from public, anon, authenticated;
revoke all on function public.recipe_std_set116(uuid, int, text), public.production_variance116(int, date, date, boolean), public.loc_cost_driver_set116(int, text, numeric, numeric, numeric), public.cost_type_driver_set116(text, text),
  public.production_cost_queue116(int, date, date), public.production_reprice116(int, date, boolean), public.recipe_stage_cost116(uuid, int), public.production_recost116(uuid, boolean) from public, anon;
grant execute on function public.recipe_std_set116(uuid, int, text), public.production_variance116(int, date, date, boolean), public.loc_cost_driver_set116(int, text, numeric, numeric, numeric), public.cost_type_driver_set116(text, text),
  public.production_cost_queue116(int, date, date), public.production_reprice116(int, date, boolean), public.recipe_stage_cost116(uuid, int), public.production_recost116(uuid, boolean) to authenticated;

-- ---------- setup advisor rows (advisory only; phase507 mechanism) ----------
insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select v.code, v.code, v.phase, v.module, v.rec_value, v.ready_checks, v.reason_bn, v.reason_mix, v.reason_en, v.sort from (values
 ('semi_finished_ingredient116', '116', 'stock', null::jsonb, '{}'::text[],
  'আপনার কারখানায় ছানা / ডো-র মতো আধা-তৈরি মাল দিয়ে আরেকটা পণ্য বানানো হলে চালু করুন; তখন উৎপাদনে সেই মাল stock থেকে কমবে ও খরচ পরের পণ্যে যাবে। না হলে বন্ধ থাকুক।',
  'আপনার factory-তে ছানা / dough-এর মতো semi-finished মাল দিয়ে আরেকটা পণ্য বানানো হলে চালু করুন; তখন production-এ সেই মাল stock থেকে কমবে ও cost পরের পণ্যে যাবে। না হলে off থাকুক।',
  'Switch on only if your factory makes one product out of another (chhana into sweets, dough into biscuits): production then takes the semi-finished good out of stock and carries its cost into the next product. It depends on how you make things, so no value is recommended.', 360),
 ('packaging_on_actual_yield116', '116', 'stock', null::jsonb, '{}'::text[],
  'আসল উৎপাদন পরিকল্পনার চেয়ে কম বা বেশি হলে প্যাকেজিং যতটা সত্যিই লাগল ততটাই কমবে ও খরচে ধরবে; নইলে প্যাকেজিংয়ের stock ধীরে ধীরে ভুল হয়ে যায়। শুধু "উৎপাদনে প্যাকেজিং" নিয়মে প্রযোজ্য।',
  'আসল production পরিকল্পনার চেয়ে কম বা বেশি হলে packaging যতটা সত্যিই লাগল ততটাই কমবে ও cost-এ ধরবে; নইলে packaging stock ধীরে ধীরে ভুল হয়ে যায়। শুধু packaging_consume_on = production হলে প্রযোজ্য।',
  'When the quantity really made differs from the plan, packaging used and its cost follow the real quantity; otherwise the packaging stock drifts. Applies only with packaging_consume_on = production.', 361),
 ('std_snapshot_auto116', '116', 'stock', null::jsonb, '{}'::text[],
  'প্রথম উৎপাদনে রেসিপির standard খরচ রাখা হয়; পরে "কেন খরচ বাড়ল" (দাম / ব্যবহার / ফলন / ওভারহেড) দেখতে এটা লাগে। কিছু বদলায় না, শুধু একটি হিসাব জমে।',
  'প্রথম production-এ recipe-র standard cost রাখা হয়; পরে "কেন cost বাড়ল" (price / usage / yield / overhead) দেখতে এটা লাগে। কিছু বদলায় না, শুধু একটি হিসাব জমে।',
  'The first run stores the recipe standard; it is needed later to see why a cost went up (price, usage, yield, overhead). Nothing else changes.', 362),
 ('std_cost_true116', '116', 'stock', null::jsonb, '{}'::text[],
  'চালু করলে রান-তালিকার std_cost হবে সংরক্ষিত standard (রেসিপি × standard দাম), আগের মতো "আসল খরচ / তাত্ত্বিক উৎপাদন" নয়। আগে std_cost_snapshot (std_snapshot_auto116) চালু করে কিছু রান করুন।',
  'চালু করলে run-তালিকার std_cost হবে stored standard (recipe × standard price), আগের মতো "actual cost / theoretical output" নয়। আগে std_snapshot_auto116 চালু করে কিছু run করুন।',
  'When on, std_cost of a run is the stored standard (recipe x standard prices) instead of actual cost / theoretical output. Switch std_snapshot_auto116 on first and make some runs. The old number stays in cost_full_yield.', 363),
 ('pool_drivers116', '116', 'stock', null::jsonb, '{}'::text[],
  'পুল মোডে পিস / লিটারের পণ্যে রূপান্তর খরচ ধরতে বা শ্রম-ঘণ্টা / ব্যাচ অনুযায়ী ভাগ করতে চালু করুন; তারপর জায়গার driver ও "স্বাভাবিক মাসিক পরিমাণ" লিখুন। সংখ্যা আপনার নিজের, কোনো মান ধরে দেওয়া হয়নি।',
  'Pool mode-এ piece / litre-এর পণ্যে conversion cost ধরতে বা labour hour / batch অনুযায়ী ভাগ করতে চালু করুন; তারপর place-এর driver ও normal monthly quantity লিখুন। সংখ্যা আপনার নিজের, কোনো মান ধরে দেওয়া হয়নি।',
  'Switch on to give piece / litre products a conversion cost in pool mode, or to spread overhead by batches or labour hours; then type the driver and the normal monthly quantity. The numbers are yours; none is assumed.', 364),
 ('conv_provisional116', '116', 'stock', null::jsonb, '{}'::text[],
  'মাসের শুরুতে বিল আসার আগেই উৎপাদন হলে আজ রূপান্তর খরচ শূন্য ধরা হয়। চালু করলে আগের মাসের হারে সাময়িক খরচ বসে (চিহ্নিত), বিল এলে production_reprice116 দিয়ে ঠিক হয়। আপনার পুল-মোড কারখানায় এটাই সাধারণত ভালো।',
  'মাসের শুরুতে bill আসার আগেই production হলে আজ conversion cost শূন্য ধরা হয়। চালু করলে আগের মাসের rate-এ provisional cost বসে (flagged), bill এলে production_reprice116 দিয়ে ঠিক হয়।',
  'A run made early in the month, before the bills are in, gets conversion cost 0 today. With this on it gets the last month''s rate, flagged provisional, and production_reprice116 fixes it when the bills arrive. It depends on whether you use pool mode, so no value is recommended.', 365),
 ('cost_supply_to_avg116', '116', 'stock', null::jsonb, '{}'::text[],
  'cost-waiting তালিকায় দাম দিলে আজ তা শুধু খাতার overlay-তে থাকে, মালের গড় খরচ ফাঁকা থেকে যায় ও পরের উৎপাদন আবার আংশিক খরচে বুক হয়। চালু করলে দামটা গড় খরচেও বসে ও সেই উৎপাদন run-এর খরচ ঠিক হয়।',
  'Cost-waiting তালিকায় দাম দিলে আজ তা শুধু ledger overlay-তে থাকে, item-এর avg cost ফাঁকা থেকে যায় ও পরের production আবার partial cost-এ book হয়। চালু করলে দামটা avg cost-এও বসে ও সেই production run-এর cost ঠিক হয়।',
  'Today a cost typed in the cost-waiting list lives only in the ledger overlay: the item average stays blank and the next run is again booked at a partial cost. With this on the cost also reaches the item average and the run is re-costed.', 366)
) v(code, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
on conflict (code) do nothing;

-- ============================================================================
-- End of FRESH part 10 of 21.
