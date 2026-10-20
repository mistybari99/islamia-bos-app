-- ============================================================================
-- DELTA part 2 of 2. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase536 phase537 phase538 phase539
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase536.sql
-- Phase 536 (UNION-8: the advanced line's logic in 43 shared functions (bank_recon_report ... items_with_cost) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
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
-- bank_recon_report(bigint,date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_report(bigint,date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_report(p_account bigint, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date := coalesce(p_from, date '2000-01-01'); to_ date := coalesce(p_to, date '2999-12-31');
  su jsonb; bu jsonb; sn int; sa numeric; bn int; ba numeric; mn int; ma numeric; st numeric; bk numeric; lb numeric; lbd date;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'date', x.line_date, 'amount', x.amount, 'reference', x.reference, 'description', x.description) order by x.line_date, x.id), '[]'::jsonb), count(*), coalesce(sum(x.amount), 0)
    into su, sn, sa from (select l.* from public.bank_statement_lines l where l.account_id = p_account and l.line_date between fr and to_
      and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active) order by l.line_date, l.id limit 500) x;
  select count(*), coalesce(sum(l.amount), 0) into sn, sa from public.bank_statement_lines l where l.account_id = p_account and l.line_date between fr and to_
      and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active);
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', x.entry_id, 'line_no', x.line_no, 'date', x.entry_date, 'memo', x.memo, 'source_type', x.source_type, 'amount', x.amount) order by x.entry_date, x.entry_id), '[]'::jsonb)
    into bu from (select e.id entry_id, l.line_no, e.entry_date, e.memo, e.source_type, (l.debit - l.credit) amount from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs))
        and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active) order by e.entry_date, e.id limit 500) x;
  select count(*), coalesce(sum(l.debit - l.credit), 0) into bn, ba from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs))
        and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active);
  select count(*), coalesce(sum(l.amount), 0) into mn, ma from public.bank_statement_lines l join public.bank_recon_matches m on m.line_id = l.id and m.active
      where l.account_id = p_account and l.line_date between fr and to_;
  select coalesce(sum(amount), 0) into st from public.bank_statement_lines where account_id = p_account and line_date between fr and to_;
  select coalesce(sum(l.debit - l.credit), 0) into bk from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      where l.account_id = p_account and e.status = 'posted' and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs));
  select balance, line_date into lb, lbd from public.bank_statement_lines where account_id = p_account and balance is not null order by line_date desc, id desc limit 1;
  return jsonb_build_object('account_id', p_account, 'from', p_from, 'to', p_to,
    'statement_unmatched', su, 'statement_unmatched_count', sn, 'statement_unmatched_sum', sa,
    'book_unmatched', bu, 'book_unmatched_count', bn, 'book_unmatched_sum', ba,
    'matched_count', mn, 'matched_sum', ma, 'statement_total', st, 'book_total', bk, 'difference', st - bk,
    'last_statement_balance', lb, 'last_statement_balance_date', lbd);
end $function$$r0_0$, null),
  ('public.bank_recon_report(bigint,date,date)', 'known', 'b80680d7434a3507d5847a5fd091212c', null);
-- bank_recon_suggest(bigint,date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_suggest(bigint,date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_suggest(p_account bigint, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_days integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare out_ jsonb := '[]'::jsonb; s record; n int; hits int; best record; used text[] := '{}'; kk text; conf boolean;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  for s in select l.* from public.bank_statement_lines l
           where l.account_id = p_account and (p_from is null or l.line_date >= p_from) and (p_to is null or l.line_date <= p_to)
             and not exists (select 1 from public.bank_recon_matches m where m.line_id = l.id and m.active)
           order by l.line_date, l.id limit 500 loop
    select count(*), count(*) filter (where ref_hit) into n, hits from public._a53_cands(s.id, p_days);
    if n = 0 then continue; end if;
    select * into best from public._a53_cands(s.id, p_days) c where (hits <> 1 or c.ref_hit) and not ((c.entry_id::text || ':' || c.line_no::text) = any (used)) limit 1;
    if not found then continue; end if;
    conf := (n = 1) or (hits = 1);
    kk := best.entry_id::text || ':' || best.line_no::text;
    if conf then used := used || kk; end if;
    out_ := out_ || jsonb_build_object('line_id', s.id, 'line_date', s.line_date, 'amount', s.amount, 'reference', s.reference, 'entry_id', best.entry_id, 'line_no', best.line_no,
      'entry_date', best.entry_date, 'memo', best.memo, 'days_off', best.days_off, 'ref_hit', best.ref_hit, 'candidates', n, 'confident', conf);
  end loop;
  return jsonb_build_object('suggestions', out_, 'count', jsonb_array_length(out_));
end $function$$r0_0$, null),
  ('public.bank_recon_suggest(bigint,date,date,integer)', 'known', 'afe12b6773c81b35ae357b3123868a44', null);
-- bank_recon_unmatch(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_recon_unmatch(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_recon_unmatch(p_line bigint, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.bank_recon_matches;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into m from public.bank_recon_matches where line_id = p_line and active for update;
  if not found then raise exception 'not_matched'; end if;
  update public.bank_recon_matches set active = false, unmatched_by = auth.uid(), unmatched_at = now(), unmatch_note = left(btrim(p_note), 200) where id = m.id;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'unmatch', m.entry_id, m.line_no, m.how, left(btrim(p_note), 200), auth.uid());
  return jsonb_build_object('unmatched', p_line);
end $function$$r0_0$, null),
  ('public.bank_recon_unmatch(bigint,text)', 'known', '7e36ecfc9c301bf483d0541be6ea2b09', null);
-- bank_stmt_import(bigint,jsonb,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.bank_stmt_import(p_account bigint, p_rows jsonb, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.coa_accounts; e jsonb; ord int := 0; d date; amt numeric; ref text; dsc text; bal numeric; k text; cnt int; m jsonb := '{}'::jsonb;
  good jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; nbad int := 0; hsh text; nnew int := 0; ndup int := 0; batch uuid; ins int; rec record; sum_in numeric := 0; sum_out numeric := 0;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  a := public._a53_bank_acct(p_account);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if p_client is not null and not p_dry then
    perform public._client_lock(p_client);
    if exists (select 1 from public.bank_statement_lines where batch_id = p_client) then
      return jsonb_build_object('dup', true, 'batch_id', p_client, 'imported', (select count(*) from public.bank_statement_lines where batch_id = p_client));
    end if;
  end if;
  batch := coalesce(p_client, gen_random_uuid());
  for e in select * from jsonb_array_elements(p_rows) loop
    ord := ord + 1;
    begin
      if jsonb_typeof(e) <> 'object' then raise exception 'bad_row'; end if;
      if coalesce(e->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_date'; end if;
      d := (e->>'date')::date;
      if d < date '2000-01-01' or d > public._acct_today() + 1 then raise exception 'bad_date'; end if;
      if coalesce(e->>'amount', '') !~ '^-?\d+(\.\d+)?$' then raise exception 'bad_amount'; end if;
      amt := round((e->>'amount')::numeric, 2);
      if amt = 0 or abs(amt) > 1000000000000 then raise exception 'bad_amount'; end if;
      ref := left(nullif(btrim(coalesce(e->>'reference', '')), ''), 120);
      dsc := left(nullif(btrim(coalesce(e->>'description', '')), ''), 300);
      bal := null;
      if nullif(e->>'balance', '') is not null then
        if e->>'balance' !~ '^-?\d+(\.\d+)?$' or abs((e->>'balance')::numeric) > 1000000000000 then raise exception 'bad_balance'; end if;
        bal := round((e->>'balance')::numeric, 2);
      end if;
      k := p_account::text || '|' || d::text || '|' || amt::text || '|' || lower(coalesce(ref, '')) || '|' || lower(coalesce(dsc, ''));
      cnt := coalesce((m->>k)::int, 0) + 1;
      m := m || jsonb_build_object(k, cnt);
      hsh := md5(k || '|' || cnt::text);
      good := good || jsonb_build_object('d', d, 'a', amt, 'r', ref, 'x', dsc, 'b', bal, 'h', hsh, 'n', ord);
    exception when others then
      nbad := nbad + 1;
      if nbad <= 20 then bad := bad || jsonb_build_object('row', ord, 'why', sqlerrm); end if;
    end;
  end loop;
  for rec in select (g->>'d')::date d, (g->>'a')::numeric a, g->>'h' h from jsonb_array_elements(good) g loop
    if exists (select 1 from public.bank_statement_lines where account_id = p_account and row_hash = rec.h) then ndup := ndup + 1;
    else nnew := nnew + 1; if rec.a > 0 then sum_in := sum_in + rec.a; else sum_out := sum_out + rec.a; end if; end if;
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'rows', ord, 'new', nnew, 'duplicate', ndup, 'invalid', nbad, 'invalid_list', bad, 'sum_in', sum_in, 'sum_out', sum_out);
  end if;
  if nbad > 0 then raise exception 'invalid_rows' using detail = bad::text; end if;
  for rec in select (g->>'d')::date d, (g->>'a')::numeric a, g->>'r' r, g->>'x' x, nullif(g->>'b', '')::numeric b, g->>'h' h from jsonb_array_elements(good) g loop
    insert into public.bank_statement_lines (batch_id, account_id, line_date, amount, reference, description, balance, row_hash, created_by)
      values (batch, p_account, rec.d, rec.a, rec.r, rec.x, rec.b, rec.h, auth.uid()) on conflict (account_id, row_hash) do nothing;
    get diagnostics ins = row_count;
  end loop;
  return jsonb_build_object('batch_id', batch, 'rows', ord, 'imported', nnew, 'duplicate', ndup, 'sum_in', sum_in, 'sum_out', sum_out);
end $function$$r0_0$, null),
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'known', '2246f73e6879cc1c8e6eb6a41b204dff', null);
-- blind_active(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.blind_active(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.blind_active(p_form text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_form in ('14-1', '10-1') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */
$function$$r0_0$, null),
  ('public.blind_active(text,integer)', 'known', '16d3e4dd208233e5d6854661267f96da', null);
-- cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cash_move_add(p_loc integer, p_kind text, p_amount numeric, p_date date DEFAULT NULL::date, p_mode text DEFAULT NULL::text, p_customer uuid DEFAULT NULL::uuid, p_ref text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text; r public.cash_moves; id_ uuid := gen_random_uuid(); bal numeric;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_kind is null or p_kind not in ('bank_deposit', 'bank_withdraw', 'owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'cust_advance_used', 'hub_receipt') then raise exception 'bad_kind'; end if;
  if p_amount is null or not (p_amount between 0.01 and 1000000000000) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  if d < date '2000-01-01' or d > today + 1 then raise exception 'bad_date'; end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') then p_mode := null;
  elsif p_mode is null or p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode';
  end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind like 'cust_advance%' and p_customer is not null then perform pg_advisory_xact_lock(hashtext('adv:' || p_customer::text)); end if;
  if p_kind like 'cust_advance%' then
    if p_customer is null or not exists (select 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */) then raise exception 'customer_required'; end if;
    if p_kind in ('cust_advance_refund', 'cust_advance_used') then
      select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) into bal from public.cash_moves where customer_id = p_customer and status = 'done' and kind like 'cust_advance%';
      if round(p_amount, 2) > bal then raise exception 'exceeds_advance' using detail = bal::text; end if;
    end if;
  else p_customer := null;
  end if;
  perform public.lock_check(d);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.cash_moves where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'mode', p_mode, 'amount', round(p_amount, 2), 'date', d, 'location_id', p_loc, 'customer_id', p_customer,
      'daybook', case p_kind when 'bank_deposit' then 'cash out, bank in' when 'bank_withdraw' then 'bank out, cash in' when 'owner_topup' then p_mode || ' in' when 'owner_draw' then p_mode || ' out'
                             when 'cust_advance' then p_mode || ' in' when 'cust_advance_refund' then p_mode || ' out' when 'hub_receipt' then 'cash in (internal)' else 'no money moves (advance used)' end);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.cash_moves (id, client_id, location_id, kind, mode, amount, move_date, customer_id, ref, note, created_by, created_staff)
    values (id_, p_client, p_loc, p_kind, p_mode, round(p_amount, 2), d, p_customer, left(btrim(p_ref), 80), left(btrim(p_note), 300), auth.uid(), sid);
  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */
end $function$$r0_0$, null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', '0d095c78e935bd5ce34a6d274fb508b4', null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', '7c0e3d340d494d62dadb5ffd57ae423d', null),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'known', 'c6e46f450b3a65fa9e4f7af93c470bf6', null);
-- control_counts()
insert into _u_plan (fn, kind, a, b) values
  ('public.control_counts()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.control_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select count(*) into n from public.locations where status in ('planned', 'setting_up') and ((select not public._org_on123()) or public.can_loc(id));   /* scope133 */ res := res || jsonb_build_object('location_setup', n);
  end if;
  if own or hd or sa then
    select count(*) into n from public.settings_sheets where status = 'draft' and ((select not public._org_on123()) or public.can_loc(location_id));   /* scope133 */ res := res || jsonb_build_object('settings_drafts', n);
  end if;
  -- the list queue is for people who may DECIDE it (the list_manage grant); head_management alone does not (the server would refuse the Lists screen)
  if (own or lg) and to_regprocedure('public.list_queue_counts()') is not null then
    execute 'select public.list_queue_counts()' into q;
    res := res || jsonb_build_object('lists', coalesce((q->>'requests')::int, 0) + coalesce((q->>'other')::int, 0));
  end if;
  return res;
end $function$$r0_0$, null),
  ('public.control_counts()', 'known', 'f09b8dc9906803dbf745f9759126d607', null);
-- cost_attrib_main_set(integer,date,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_attrib_main_set(integer,date,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_attrib_main_set(p_loc integer, p_effective date, p_reason text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.cost_attrib_main; same public.cost_attrib_main; m date; nid bigint; cur date := public._m1(public._c78_today());
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into a from public.cost_attrib_main where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', a.id); end if; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'unknown_location'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  m := public._m1(p_effective);
  if m < cur then raise exception 'effective_in_past'; end if;
  perform public.lock_check(m);
  if exists (select 1 from public.cost_attrib_main where active and effective_from <= m) and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception 'reason_required'; end if;
  select * into same from public.cost_attrib_main where active and effective_from = m;
  if found then update public.cost_attrib_main set active = false, retired_at = now(), retired_by = auth.uid() where id = same.id; end if;
  insert into public.cost_attrib_main (location_id, effective_from, reason, client_id, created_by) values (p_loc, m, left(btrim(p_reason), 300), p_client, auth.uid()) returning id into nid;
  if same.id is not null then update public.cost_attrib_main set replaced_by = nid where id = same.id; end if;
  return jsonb_build_object('id', nid, 'effective_from', m);
end $function$$r0_0$, null),
  ('public.cost_attrib_main_set(integer,date,text,uuid)', 'known', '2dbd65c94d4f883eead5b13bc654c2ee', null);
-- cost_rule_approve(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_rule_approve(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_rule_approve(p_rule bigint, p_note text DEFAULT NULL::text)
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
end $function$$r0_0$, null),
  ('public.cost_rule_approve(bigint,text)', 'known', '99a2d3954ba5bdb66effd9bc24e1808a', null);
-- cost_source_set_active(bigint,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.cost_source_set_active(bigint,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.cost_source_set_active(p_id bigint, p_active boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if public._org_on123() and auth.uid() is not null and not public._cs_src_ok(p_id) then raise exception 'source_not_found'; end if;   /* scope133: a cost source of another business is a missing id */
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cost_sources set active = p_active, retired_at = case when p_active then null else now() end, retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'source_not_found'; end if;
end $function$$r0_0$, null),
  ('public.cost_source_set_active(bigint,boolean,text)', 'known', '591affe276bd9e22d4e028952639e194', null);
-- count_lines_seal(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.count_lines_seal(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.count_lines_seal(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.entries; k text; cf text; r jsonb; n int; cnt numeric; it public.items; bk numeric; tot int := 0;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if e.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then raise exception 'count_not_open'; end if;
  if not public.stock_blind_active(e.form_code, e.location_id) then return jsonb_build_object('blind', false, 'sealed', 0); end if;
  k := case e.form_code when '04-3' then 'rows' else 'lines' end; cf := case e.form_code when '04-3' then 'count' else 'counted' end;
  for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data -> k) = 'array' then e.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
    continue when nullif(btrim(r ->> 'item'), '') is null;
    if nullif(btrim(coalesce(r ->> cf, '')), '') is null then raise exception 'count_missing'; end if;
    cnt := public._n18(r, cf);
    if cnt < 0 then raise exception 'bad_count'; end if;
    if not exists (select 1 from public.entry_count_seals where entry_id = e.id and line_no = n) then
      select * into it from public.items where code = btrim(r ->> 'item') and public._m132_at(org_unit_id, e.location_id) /* m132 */;
      if not found then raise exception 'item_not_found'; end if;
      bk := null;
      if e.form_code = '04-3' then
        select coalesce(b.qty, 0) into bk from public.stock_balance b where b.item_id = it.id and b.location_id = e.location_id;
        bk := coalesce(bk, 0);
      end if;
      insert into public.entry_count_seals (entry_id, line_no, form_code, item_code, counted, book_base, sealed_by) values (e.id, n, e.form_code, btrim(r ->> 'item'), cnt, bk, auth.uid());
    end if;
  end loop;
  select count(*) into tot from public.entry_count_seals where entry_id = e.id;
  return jsonb_build_object('blind', true, 'sealed', tot);
end $function$$r0_0$, null),
  ('public.count_lines_seal(uuid)', 'known', '0c6f2b998e0ff8df221c8568b6033816', null);
-- count_unsubmitted_scan()
insert into _u_plan (fn, kind, a, b) values
  ('public.count_unsubmitted_scan()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.count_unsubmitted_scan()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    select e.id, e.form_code, e.location_id, e.entry_date, 'count_unsubmitted', 'red', null,
           jsonb_build_object('bn', 'গণনা সেভ হয়েছে কিন্তু শিট জমা হয়নি', 'en', 'Count saved but the sheet was never submitted')
    from public.entry_counts c join public.entries e on e.id = c.entry_id
    where c.section = 'drawer' and e.status = 'draft' and e.entry_date < (now() at time zone 'Asia/Dhaka')::date
      and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'count_unsubmitted')
      and ((select not public._org_on123()) or public.can_loc(e.location_id));   /* scope133: only the places of the caller */
  get diagnostics n = row_count;
  return n;
end $function$$r0_0$, null),
  ('public.count_unsubmitted_scan()', 'known', '68e8da0c14e0ceee2d4a14761696ca38', null);
-- customer_advances()
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_advances()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_advances()
 RETURNS TABLE(customer_id uuid, name text, mobile text, balance numeric, last_at date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, public._cust_pii103('mobile', c.mobile) /* bos105 */, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$function$$r0_0$, null),
  ('public.customer_advances()', 'known', '533cc9d5486899115fb2bcc814b2a182', null);
-- customer_balance(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_balance(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_balance(p_customer uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then (case when public._m132_own((select c.org_unit_id from public.customers c where c.id = p_customer)) /* m132 */ then public._cust_bal(p_customer) end) end;
$function$$r0_0$, null),
  ('public.customer_balance(uuid)', 'known', '030b0d2494c9bee644e8237481766d7f', null);
-- customer_directory(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_directory(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_directory(p_limit integer DEFAULT 5000)
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
    where public._m132_own(c.org_unit_id) /* m132 */ order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $function$$r0_0$, null),
  ('public.customer_directory(integer)', 'known', '484043d32143b4d2ec77be5cc641fa67', null);
-- customer_ledger(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_ledger(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_ledger(p_customer uuid)
 RETURNS TABLE(at timestamp with time zone, kind text, ref text, location_id integer, debit numeric, credit numeric, balance numeric, note text, pid bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with e as (
    select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not (select public._org_on123()) or public.can_loc(s.location_id))
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided and (not (select public._org_on123()) or public.can_loc(p.location_id))
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0 and (not (select public._org_on123()) or public.can_loc(r.location_id)))
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$function$$r0_0$, null),
  ('public.customer_ledger(uuid)', 'known', 'dbba32ccc6c52bd97e77bb0252b02dbb', null),
  ('public.customer_ledger(uuid)', 'known', 'ded875bcc1da74da42da271b1f9fac41', null),
  ('public.customer_ledger(uuid)', 'known', 'fe27f4e36ceabdd7cf8f0da215bfcdce', null);
-- customer_points_adjust(uuid,integer,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_points_adjust(uuid,integer,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_points_adjust(p_customer uuid, p_delta integer, p_note text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bal int; why text := left(btrim(coalesce(p_note, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 10000000 then raise exception 'bad_number'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', (select sum(delta) from public.customer_points_ledger where customer_id = p_customer));
  end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if bal + p_delta < 0 then raise exception 'not_enough_points'; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, p_delta, 'adjust', p_client, why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dup', false, 'balance', bal + p_delta);
end $function$$r0_0$, null),
  ('public.customer_points_adjust(uuid,integer,text,uuid)', 'known', 'f758e0f59a2e94c726161defac575ce9', null);
-- customer_points_redeem(uuid,integer,text,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_points_redeem(p_customer uuid, p_points integer, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_dry boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bal int; val numeric; mn numeric;
begin
  if not (public._cust_mgr43() or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('loyalty_points_on') then raise exception 'loyalty_off'; end if;
  if p_points is null or p_points <= 0 or p_points > 10000000 then raise exception 'bad_number'; end if;
  mn := coalesce(public.rule_num('redeem_min_points'), 0);
  if p_points < mn then raise exception 'below_min_points'; end if;
  val := round(p_points * coalesce(public.rule_num('point_value_taka'), 0), 2);
  perform public._client_lock(p_client);
  if not coalesce(p_dry, false) and p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client) then
    return jsonb_build_object('dup', true, 'points', p_points, 'value_taka', val, 'balance', (select sum(delta) from public.customer_points_ledger where customer_id = p_customer));
  end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if p_points > bal then raise exception 'not_enough_points'; end if;
  if coalesce(p_dry, false) then return jsonb_build_object('dry', true, 'points', p_points, 'value_taka', val, 'balance', bal, 'balance_after', bal - p_points); end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, -p_points, 'redeem', p_client, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dry', false, 'dup', false, 'points', p_points, 'value_taka', val, 'balance', bal - p_points);
end $function$$r0_0$, null),
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)', 'known', '1a6adfda8d0e208551dfabe985f497f0', null);
-- customer_pos_info(text)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_pos_info(text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_pos_info(p_mobile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m text; c public.customers; t public.customer_tiers; g int := 0;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  m := public.norm_mobile(p_mobile);
  select * into c from public.customers where mobile = m and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;
  if not found then return jsonb_build_object('found', false, 'mobile', m); end if;
  select * into t from public.customer_tiers where id = c.tier_id;
  if public.rule_on('customer_gifts_on') then select count(*)::int into g from public.gifts_due(c.id); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'name', c.name, 'birthday', c.birthday,
    'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'color', t.color, 'badge', t.badge, 'perks', t.perks,
        'discount_percent', t.discount_percent, 'discount_cap_amount', t.discount_cap_amount, 'birthday_gift', t.birthday_gift) end,
    'tier_discount_on', public.rule_on('tier_discount_on') and coalesce(t.discount_percent, 0) > 0 and c.active and coalesce(t.active, false),
    'gifts_due', g,
    'points', case when public.rule_on('loyalty_points_on') then coalesce((select sum(delta) from public.customer_points_ledger where customer_id = c.id), 0) end);
end $function$$r0_0$, null),
  ('public.customer_pos_info(text)', 'known', 'f2060f1f46fa4c12803f0e7b0e2f238f', null);
-- customer_profile(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_profile(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_profile(p_customer uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; res jsonb;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
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
end $function$$r0_0$, null),
  ('public.customer_profile(uuid)', 'known', '13ad334a4ee0a61c1604c7f3cb9f7d78', null);
-- customer_save(uuid,jsonb,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_save(uuid,jsonb,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_save(p_id uuid, p jsonb, p_client uuid DEFAULT NULL::uuid)
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
    select * into c from public.customers where mobile = mob and public._m132_own(org_unit_id) /* m132 */ order by (org_unit_id is not distinct from public._m132_caller_biz()) desc, org_unit_id limit 1;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'name', c.name, 'active', c.active); end if;
    if (p ? 'tier_id' or p ? 'tier_locked' or p ? 'credit_limit') and not mgr then raise exception 'not allowed'; end if;
    tid := nullif(p ->> 'tier_id', '')::bigint;
    if tid is not null and not exists (select 1 from public.customer_tiers where id = tid and active) then raise exception 'tier_not_found'; end if;
    insert into public.customers (org_unit_id, mobile, name, type, created_by, tier_id, tier_locked, birthday, anniversary, address, note, source, whatsapp, credit_limit)
      values (nullif(p ->> 'org_unit_id', '')::bigint /* m132 */, mob, nm, coalesce(ty, 'retail'), auth.uid(), tid, coalesce((p ->> 'tier_locked')::boolean, tid is not null), public._d43(p, 'birthday'), public._d43(p, 'anniversary'),
              left(nullif(btrim(p ->> 'address'), ''), 200), left(nullif(btrim(p ->> 'note'), ''), 500), left(nullif(btrim(p ->> 'source'), ''), 60), wa, public._n43(p, 'credit_limit', 0))
      returning * into c;
    if tid is not null and tid is distinct from (select id from public.customer_tiers where is_default limit 1) then
      insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
        values (c.id, (select id from public.customer_tiers where is_default limit 1), tid, 'manual', 'at registration', auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
    end if;
    return jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'dup', false);
  end if;
  select * into c from public.customers where id = p_id and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
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
end $function$$r0_0$, null),
  ('public.customer_save(uuid,jsonb,uuid)', 'known', '56fd859271382effabb220827db3d7ad', null);
-- customer_set_tier(uuid,bigint,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.customer_set_tier(uuid,bigint,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.customer_set_tier(p_customer uuid, p_tier bigint, p_reason text, p_lock boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; t public.customer_tiers; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into t from public.customer_tiers where id = p_tier;
  if not found or not t.active then raise exception 'tier_not_found'; end if;
  if c.tier_id is distinct from p_tier then
    insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
      values (c.id, c.tier_id, p_tier, 'manual', why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  end if;
  update public.customers set tier_id = p_tier, tier_locked = coalesce(p_lock, true) where id = c.id;
  return jsonb_build_object('id', c.id, 'tier_id', p_tier, 'changed', c.tier_id is distinct from p_tier, 'tier_locked', coalesce(p_lock, true));
end $function$$r0_0$, null),
  ('public.customer_set_tier(uuid,bigint,text,boolean)', 'known', '36b55a268dd6cef296b8c234dc2eae47', null);
-- decide_emergency(bigint,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.decide_emergency(bigint,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.decide_emergency(p_id bigint, p_approve boolean, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.is_owner() and (r.location_id is null or not public._biz_ok123(r.location_id)) then raise exception 'not found'; end if;   -- scope123
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $function$$r0_0$, null),
  ('public.decide_emergency(bigint,boolean,text)', 'known', '00dfa679b8711fb289b4e1f2a28cde34', null);
-- dup_suspects(date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.dup_suspects(date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.dup_suspects(p_from date, p_to date)
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
end $function$$r0_0$, null),
  ('public.dup_suspects(date,date)', 'known', '9d22f4c1f28144978ab4f1984b4c96f1', null);
-- fa_register(date)
insert into _u_plan (fn, kind, a, b) values
  ('public.fa_register(date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.fa_register(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true
    where (not public._org_on123() or public.can_loc(a.location_id))), '[]'::jsonb));   -- scope123: the caller's places (no place = owner only)
end $function$$r0_0$, null),
  ('public.fa_register(date)', 'known', '7e2da3ac91436ede29cf5ee268b59cf3', null);
-- fa_schedule(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.fa_schedule(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.fa_schedule(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  if public._org_on123() and not public.can_loc(a.location_id) then raise exception 'not found'; end if;   -- scope123: same answer as a missing id
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $function$$r0_0$, null),
  ('public.fa_schedule(uuid)', 'known', '4f6c3a49f93c00f58c0505ea5d47d9d8', null);
-- gift_claim(uuid,uuid,bigint,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gift_claim(p_customer uuid, p_gift uuid DEFAULT NULL::uuid, p_rule bigint DEFAULT NULL::bigint, p_occasion text DEFAULT NULL::text, p_sale uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.customer_gifts; due record; r public.gift_rules; ok boolean := false; sid text;
begin
  if not (public.is_active() and (public.can_do('POS', 'enter') or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */ for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_sale is not null and not exists (select 1 from public.sales where id = p_sale and customer_id = p_customer) then raise exception 'sale_not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_gift is not null then
    select * into g from public.customer_gifts where id = p_gift and customer_id = p_customer for update;
    if not found then raise exception 'gift_not_found'; end if;
    if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
    if g.valid_until is not null and g.valid_until < public._today43() then raise exception 'gift_expired'; end if;
  else
    if p_rule is null or nullif(btrim(p_occasion), '') is null then raise exception 'bad_value'; end if;
    select * into g from public.customer_gifts where customer_id = p_customer and rule_id = p_rule and occasion = p_occasion for update;
    if found then
      if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
      if g.valid_until is not null and g.valid_until < public._today43() then raise exception 'gift_expired'; end if;
    else
      for due in select * from public.gifts_due(p_customer) x where x.rule_id = p_rule and x.occasion = p_occasion and not x.issued loop ok := true; end loop;
      if not ok then raise exception 'gift_not_due'; end if;
      select * into r from public.gift_rules where id = p_rule;
      insert into public.customer_gifts (customer_id, rule_id, occasion, gift_text_bn, gift_text_en, value_taka, issued_by, valid_until)
        values (p_customer, p_rule, p_occasion, r.gift_text_bn, r.gift_text_en, r.value_taka, auth.uid(), public._today43() + coalesce(r.valid_days, public.rule_num('gift_valid_days')::int, 30))
        on conflict do nothing returning * into g;
      if not found then select * into g from public.customer_gifts where customer_id = p_customer and rule_id = p_rule and occasion = p_occasion; end if;
      if g.claimed_at is not null then return jsonb_build_object('dup', true, 'id', g.id, 'claimed_at', g.claimed_at); end if;
    end if;
  end if;
  update public.customer_gifts set claimed_at = now(), claimed_by = auth.uid(), claimed_staff = sid, claimed_sale_id = p_sale where id = g.id;
  return jsonb_build_object('dup', false, 'id', g.id, 'claimed_at', now());
end $function$$r0_0$, null),
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)', 'known', 'b99e7a30db187dd6167bb7704e059ea5', null);
-- gift_issue(uuid,text,text,numeric,date,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gift_issue(p_customer uuid, p_text_bn text, p_text_en text, p_value numeric DEFAULT NULL::numeric, p_valid_until date DEFAULT NULL::date, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g public.customer_gifts; occ text;
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  if coalesce(nullif(btrim(p_text_bn), ''), nullif(btrim(p_text_en), '')) is null then raise exception 'gift_text_required'; end if;
  if p_value is not null and (p_value = 'NaN'::numeric or p_value < 0 or p_value > 1e12) then raise exception 'bad_number'; end if;
  if p_valid_until is not null and (p_valid_until < public._today43() or p_valid_until > public._today43() + 3650) then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  occ := 'manual:' || coalesce(p_client::text, gen_random_uuid()::text);
  perform 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found then raise exception 'customer_not_found'; end if;
  select * into g from public.customer_gifts where customer_id = p_customer and rule_id is null and occasion = occ;
  if found then return jsonb_build_object('dup', true, 'id', g.id); end if;
  insert into public.customer_gifts (customer_id, rule_id, occasion, gift_text_bn, gift_text_en, value_taka, issued_by, valid_until, note)
    values (p_customer, null, occ, left(nullif(btrim(p_text_bn), ''), 200), left(nullif(btrim(p_text_en), ''), 200), round(p_value, 2), auth.uid(),
            coalesce(p_valid_until, public._today43() + coalesce(public.rule_num('gift_valid_days')::int, 30)), left(nullif(btrim(p_note), ''), 300)) returning * into g;
  return jsonb_build_object('dup', false, 'id', g.id);
end $function$$r0_0$, null),
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)', 'known', '0a021ac09e2e0a34005e6ad032727961', null);
-- gifts_due(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.gifts_due(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.gifts_due(p_customer uuid)
 RETURNS TABLE(gift_id uuid, rule_id bigint, occasion text, kind text, text_bn text, text_en text, value_taka numeric, valid_until date, issued boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.customers; st record; r public.gift_rules; today date := public._today43(); win int := coalesce(public.rule_num('gift_window_days'), 7)::int;
        y int; d date; occ text; vd int; k int;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then return; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found or not c.active then return; end if;
  -- already issued, not claimed, not expired
  return query select g.id, g.rule_id, g.occasion, coalesce(gr.trigger, 'manual'), g.gift_text_bn, g.gift_text_en, g.value_taka, g.valid_until, true
    from public.customer_gifts g left join public.gift_rules gr on gr.id = g.rule_id
    where g.customer_id = p_customer and g.claimed_at is null and (g.valid_until is null or g.valid_until >= today) order by g.issued_at;
  select * into st from public._cust_stats43(p_customer, false);
  for r in select * from public.gift_rules x where x.active and x.trigger <> 'manual' and (x.tier_id is null or x.tier_id = c.tier_id) order by x.id loop
    occ := null; vd := coalesce(r.valid_days, public.rule_num('gift_valid_days')::int, 30);
    if r.trigger in ('birthday', 'anniversary') then
      d := case r.trigger when 'birthday' then c.birthday else c.anniversary end;
      if d is not null then
        for y in extract(year from today)::int - 1 .. extract(year from today)::int + 1 loop
          if abs((make_date(y, 1, 1) + (to_char(d, 'DDD')::int - 1)) - today) <= win then occ := r.trigger || ':' || y; end if;
        end loop;
      end if;
    elsif r.trigger = 'first_purchase' then
      if st.orders >= 1 then occ := 'first'; end if;
    elsif r.trigger = 'every_n_purchases' then
      k := floor(st.orders / r.threshold)::int;
      if k >= 1 then occ := 'nth:' || k; end if;
    elsif r.trigger = 'spend_threshold' then
      if st.spend >= r.threshold then occ := 'spend:' || trim_scale(r.threshold)::text; end if;
    end if;
    if occ is not null and not exists (select 1 from public.customer_gifts g where g.customer_id = p_customer and g.rule_id = r.id and g.occasion = occ) then
      return query select null::uuid, r.id, occ, r.trigger, r.gift_text_bn, r.gift_text_en, r.value_taka, today + vd, false;
    end if;
  end loop;
end $function$$r0_0$, null),
  ('public.gifts_due(uuid)', 'known', 'f5f53befd6bbe4e16fe160fb2753dd27', null);
-- has_grant(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.has_grant(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.has_grant(p_code text, p_loc integer DEFAULT NULL::integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_owner() or (public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline
    -- OFF: exactly the rule of phase8
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  else (
    -- ON (scope123 + scope133): with a location it must be one of the caller's businesses; the role matrix is the one of THAT business; a personal grant without a location = the caller's businesses
    (p_loc is null or public._biz_ok123(p_loc)) and (
      (case when p_loc is null then public.can_grant(p_code) else public._can_grant_in133(p_code, public._business_of_loc123(p_loc)) end)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$function$$r0_0$, null),
  ('public.has_grant(text,integer)', 'known', '85f7d00b93db4bf6562506095ff35bc1', null);
-- inbox_board(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_board(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_board(p_loc integer DEFAULT NULL::integer)
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
end $function$$r0_0$, null),
  ('public.inbox_board(integer)', 'known', '44c5e6a1347f85568728e2205aed00d0', null);
-- inbox_get(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_get(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.inbound_messages; c public.sales_channels; ok boolean;
begin
  select * into m from public.inbound_messages where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'view');
  select * into c from public.sales_channels where id = m.channel_id;
  ok := public._inb_contact_ok(m.location_id);
  if ok then perform public._inb_audit_view('inbound_messages', m.id::text, jsonb_build_object('fields', 'handle,name,text,attachment')); end if;
  return jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
    'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'masked', not ok,
    'handle', case when ok then public._inb_pii_f99('handle', m.customer_handle) end, 'name', case when ok then public._inb_pii_f99('name', m.customer_name) end, 'text', case when ok then public._inb_pii_f99('text', m.msg_text) end, 'attachment_ref', case when ok then public._inb_pii_f99('attachment', m.attachment_ref) end, 'pii_mode', public._inb_pii_mode99(),   /* bos99 */
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.inbox_get(bigint)', 'known', 'adb9e108a51bfb1fe0a762c993652745', null);
-- inbox_list(integer,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inbox_list(integer,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inbox_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 100)
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
end $function$$r0_0$, null),
  ('public.inbox_list(integer,text,integer)', 'known', '41de5df76cf6e81eebf968965e3a1aee', null);
-- intake_failures_list(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.intake_failures_list(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.intake_failures_list(p_state text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select f.id, f.kind, f.channel_id, f.external_id, f.error, f.attempts, f.next_try_at, f.last_try_at, f.state, f.created_at, f.done_at
      from public.intake_failures f where (p_state is null or f.state = p_state) and ((select not public._org_on123()) or public.is_owner() or exists (select 1 from public.sales_channels sc where sc.id = f.channel_id and public._biz_ok123(sc.location_id))) /* scope133 */ order by f.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.intake_failures_list(text,integer)', 'known', 'e042a95d48fbaaaf3b0d6e385be5e4ce', null);
-- inventory_vs_gl(date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.inventory_vs_gl(date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.inventory_vs_gl(p_date date DEFAULT NULL::date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; j_adj numeric; j_issue numeric; j_xfer numeric; j_var numeric; /* bos85 */ g_prod numeric; g_pret numeric; ok boolean; j_skip numeric; j_prodin numeric; g_dup numeric; /* bos103 */
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
           coalesce(sum(x.v) filter (where x.reason = 'purchase_in' and x.ref_type = 'entry'), 0) as g_grn_in, /* bos103 */
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
    -- bos103: inventory a posted bill booked while it added no stock rows of its own (guard skip / link: the stock came from the GRN) covers GRN stock rows; direct production-in rows that were posted by acct_manual_prod_in103
    select coalesce(sum(jl.debit - jl.credit), 0) into j_skip from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id join public.purchase_bills pb on pb.id::text = e.source_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'purchase' and e.reverses_id is null and pb.kind = 'bill' and (p_loc is null or jl.location_id = p_loc)
        and not exists (select 1 from public.journal_entries r where r.reverses_id = e.id)
        and not exists (select 1 from public.stock_ledger sl where sl.ref_type = 'purchase' and sl.reason = 'purchase_in' and sl.ref_id = pb.id::text);
    -- bos103: with GRN as the stock source, a bill that added its own stock after the first GRN stock row duplicates GRN stock (guard off): that part is NOT explained as manual_in, it stays in "unexplained"
    select coalesce(sum(coalesce(sl.qty_delta * sl.unit_cost, 0)), 0) into g_dup from public.stock_ledger_eff96 sl join public.items it on it.id = sl.item_id
      where public._acct_inv_key(it.item_type) = k and sl.reason = 'purchase_in' and sl.ref_type = 'purchase' and (sl.made_at at time zone 'Asia/Dhaka')::date <= d and (p_loc is null or sl.location_id = p_loc)
        and sl.made_at >= (select min(g.made_at) from public.stock_ledger g where g.reason = 'purchase_in' and g.ref_type = 'entry' and g.reverses_id is null)
        and not exists (select 1 from public.stock_ledger v where v.reverses_id = sl.id);
    select coalesce(sum(jl.debit - jl.credit), 0) into j_prodin from public.journal_lines jl join public.journal_entries e on e.id = jl.entry_id
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'stock_prodin' and (p_loc is null or jl.location_id = p_loc);
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count + j_adj, 2)),   -- bos85
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer + j_xfer, 2)),   -- bos85
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue + j_issue, 2)),   -- bos85
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in + least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)) + least(greatest(rw.g_grn_in - least(greatest(j_skip, 0), greatest(rw.g_grn_in, 0)), 0), greatest(g_dup, 0)) + j_prodin, 2)),   -- bos103
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
end $function$$r0_0$, null),
  ('public.inventory_vs_gl(date,integer)', 'known', 'fe8cd894585ad965a496be4d1e516893', null);
-- item_apply(uuid,jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_apply(uuid,jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_apply(p_item uuid, p_patch jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid text; cid bigint; k text; iid uuid;
begin
  if p_item is null or p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */) then raise exception 'item_not_found'; end if;
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
end $function$$r0_0$, null),
  ('public.item_apply(uuid,jsonb,text)', 'known', '5262f9672019bc7681cb7612b3615eae', null);
-- item_dup_check(text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_dup_check(text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_dup_check(p_name_bn text, p_name_en text, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, name_bn text, name_en text, why text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select i.id, i.code, i.name_bn, i.name_en,
         case when lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(coalesce(p_name_bn, ''), '\s+', '', 'g')) then 'same_name_bn' else 'same_name_en' end
  from public.items i
  where public.is_active() and public._m132_vis('items', i.org_unit_id, i.id::text, false) /* m132 */ and (p_exclude is null or i.id <> p_exclude)
    and ((nullif(btrim(p_name_bn), '') is not null and lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(p_name_bn, '\s+', '', 'g')))
      or (nullif(btrim(p_name_en), '') is not null and i.name_en is not null and lower(regexp_replace(i.name_en, '\s+', '', 'g')) = lower(regexp_replace(p_name_en, '\s+', '', 'g'))))
  order by i.code limit 20;
$function$$r0_0$, null),
  ('public.item_dup_check(text,text,uuid)', 'known', '93569294281c61f7316e39bbe2ec674a', null);
-- item_map_accept_confident(boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_map_accept_confident(boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_map_accept_confident(p_dry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int := 0; mn numeric; codes text[] := '{}'; skipped int := 0;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  mn := public.rule_num('item_map_accept_min_conf');
  for r in select m.* from public.item_mapping_review m where m.status in ('pending', 'later') and m.suggested_code is not null
           and (m.auto_ok or (mn is not null and m.confidence >= mn)) order by m.id loop
    if not exists (select 1 from public.items t where t.code = r.suggested_code and t.import_batch is not null and t.is_active)
       or exists (select 1 from public.item_master_links l where l.dict_code = r.suggested_code and l.active and l.item_id <> r.item_id)
       or exists (select 1 from public.items t where t.id = r.item_id and t.master_code is not null) then skipped := skipped + 1; continue; end if;
    begin
      if not coalesce(p_dry, true) then
        perform public._item_link(r.item_id, r.suggested_code, 'accepted', false);
        update public.item_mapping_review set status = 'linked', decided_by = auth.uid(), decided_at = now(), note = 'accepted (high confidence)' where id = r.id;
        insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (r.item_id, r.suggested_code, 'accept_all', 'high confidence', auth.uid());
      end if;
      n := n + 1; codes := codes || (select code from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */);
    exception when others then skipped := skipped + 1;
    end;
  end loop;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'accepted', n, 'skipped', skipped, 'codes', to_jsonb(codes));
end $function$$r0_0$, null),
  ('public.item_map_accept_confident(boolean)', 'known', 'c2b1ebab661e7b4ff526b65e9291a664', null);
-- item_map_decide2(uuid,text,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_map_decide2(uuid,text,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_map_decide2(p_item uuid, p_action text, p_dict text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lg public.items; dc public.items; rv public.item_mapping_review; act public.item_map_actions; aid bigint; f record; cur_status text; dstock boolean; bc_moved boolean := false;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_action not in ('link', 'keep', 'later', 'use_dict', 'undo') then raise exception 'bad_request'; end if;
  select * into lg from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ and import_batch is null;
  if not found then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  select * into rv from public.item_mapping_review where item_id = p_item;
  cur_status := rv.status;

  if p_action = 'link' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, p_dict, 'linked', p_note, p_force);
    insert into public.item_map_actions (item_id, dict_code, action, note, created_by) values (p_item, btrim(p_dict), 'link', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'linked');
  elsif p_action = 'keep' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    perform public.item_mapping_decide(p_item, null, 'rejected', p_note);
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'keep', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'rejected');
  elsif p_action = 'later' then
    if cur_status = 'replaced' then raise exception 'undo_first'; end if;
    if cur_status in ('linked', 'rejected') then perform public.item_mapping_decide(p_item, null, 'pending', p_note); end if;
    update public.item_mapping_review set status = 'later', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
    insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'later', left(p_note, 300), auth.uid());
    return jsonb_build_object('status', 'later');
  elsif p_action = 'undo' then
    if cur_status = 'replaced' then
      if not public.is_owner() then raise exception 'not allowed'; end if;           -- undoing a replacement is the owner's only
      select * into act from public.item_map_actions a where a.item_id = p_item and a.action = 'use_dict'
         and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id) order by a.id desc limit 1;
      if not found then raise exception 'nothing_to_undo'; end if;
      select * into dc from public.items where code = act.dict_code and import_batch is not null;
      if (found and dc.locked) or lg.locked then raise exception 'item_locked'; end if;
      if found and not coalesce(p_force, false) and (dc.sell_price is distinct from (act.before->'dict'->>'new_price')::numeric) then raise exception 'changed_since'; end if;
      perform set_config('bos.item_sys', '1', true);
      if found then
        update public.items set sell_price = (act.before->'dict'->>'sell_price')::numeric, wholesale_price = (act.before->'dict'->>'wholesale_price')::numeric, unit = act.before->'dict'->>'unit',
          hidden = (act.before->'dict'->>'hidden')::boolean, sellable = (act.before->'dict'->>'sellable')::boolean, barcode = act.before->'dict'->>'barcode' where id = dc.id;
      end if;
      update public.items set barcode = coalesce(act.before->'legacy'->>'barcode', barcode) where id = p_item and act.before->'legacy'->>'barcode' is not null;
      update public.items set is_active = (act.before->'legacy'->>'is_active')::boolean, retired_at = (act.before->'legacy'->>'retired_at')::timestamptz,
        retired_reason = act.before->'legacy'->>'retired_reason' where id = p_item;
      perform set_config('bos.item_sys', '', true);
      update public.item_mapping_review set status = 'pending', decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
      insert into public.item_map_actions (item_id, dict_code, action, ref_id, note, created_by) values (p_item, act.dict_code, 'undo_use_dict', act.id, left(p_note, 300), auth.uid());
    else
      perform public.item_mapping_decide(p_item, null, 'pending', p_note);
      insert into public.item_map_actions (item_id, action, note, created_by) values (p_item, 'undo', left(p_note, 300), auth.uid());
    end if;
    return jsonb_build_object('status', 'pending');
  end if;

  -- use_dict
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if cur_status = 'replaced' then raise exception 'already_replaced'; end if;
  if lg.master_code is not null then raise exception 'unlink_first'; end if;
  if not lg.is_active then raise exception 'item_inactive'; end if;
  if lg.locked then raise exception 'item_locked'; end if;
  if lg.sell_price is null then raise exception 'legacy_has_no_price'; end if;
  if exists (select 1 from public.stock_balance where item_id = lg.id and qty <> 0) then raise exception 'legacy_has_stock'; end if;
  select * into dc from public.items where code = btrim(coalesce(p_dict, '')) and import_batch is not null for update;
  if not found then raise exception 'master_code_not_found'; end if;
  if not dc.is_active then raise exception 'dict_retired'; end if;
  if dc.locked then raise exception 'item_locked'; end if;
  if dc.item_type in ('asset', 'raw_material', 'packaging', 'consumable', 'controlled') and not coalesce(p_force, false) then raise exception 'master_type_mismatch'; end if;
  if exists (select 1 from public.item_master_links where dict_code = dc.code and active) then raise exception 'master_code_taken'; end if;
  if exists (select 1 from public.item_map_actions a where a.dict_code = dc.code and a.action = 'use_dict'
             and not exists (select 1 from public.item_map_actions u where u.action = 'undo_use_dict' and u.ref_id = a.id)) then raise exception 'master_code_taken'; end if;
  dstock := exists (select 1 from public.stock_balance where item_id = dc.id and qty <> 0);
  if dstock and dc.unit is distinct from lg.unit then raise exception 'dict_unit_has_stock'; end if;      -- never re-label units under stock (no override)
  if not coalesce(p_force, false) then                                                                        -- the owner can confirm these
    if dstock then raise exception 'dict_has_stock'; end if;
    if dc.sell_price is not null and dc.sell_price is distinct from lg.sell_price then raise exception 'dict_price_differs'; end if;
    if dc.unit is not null and dc.unit is distinct from lg.unit then raise exception 'dict_unit_differs'; end if;
  end if;
  select * into f from public._item_type_flags(dc.item_type);
  perform set_config('bos.item_sys', '1', true);
  insert into public.item_map_actions (item_id, dict_code, action, before, note, created_by) values (lg.id, dc.code, 'use_dict', jsonb_build_object(
      'dict', jsonb_build_object('sell_price', dc.sell_price, 'wholesale_price', dc.wholesale_price, 'unit', dc.unit, 'hidden', dc.hidden, 'sellable', dc.sellable, 'new_price', lg.sell_price, 'barcode', dc.barcode),
      'legacy', jsonb_build_object('is_active', lg.is_active, 'retired_at', lg.retired_at, 'retired_reason', lg.retired_reason, 'barcode', case when lg.barcode is not null and dc.barcode is null then lg.barcode end)), left(p_note, 300), auth.uid()) returning id into aid;
  if lg.barcode is not null and dc.barcode is null then            -- the barcode on the shelf now scans the dictionary item (the legacy one is cleared first: barcodes are unique)
    update public.items set barcode = null where id = lg.id; bc_moved := true;
  end if;
  update public.items set sell_price = lg.sell_price, wholesale_price = coalesce(lg.wholesale_price, wholesale_price), unit = lg.unit, hidden = false, sellable = coalesce(f.o_sell, sellable),
    barcode = case when bc_moved then lg.barcode else barcode end where id = dc.id;
  update public.items set is_active = false, retired_at = coalesce(retired_at, now()), retired_reason = 'replaced by ' || dc.code where id = lg.id;
  perform set_config('bos.item_sys', '', true);
  update public.item_mapping_review set status = 'replaced', suggested_code = dc.code, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  return jsonb_build_object('status', 'replaced', 'action_id', aid, 'dict_code', dc.code, 'barcode_moved', bc_moved, 'barcode_kept', (lg.barcode is not null and not bc_moved));
end $function$$r0_0$, null),
  ('public.item_map_decide2(uuid,text,text,text,boolean)', 'known', '61f9f1e6f906245b6169e9635b23a2bd', null);
-- item_mapping_decide(uuid,text,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_mapping_decide(uuid,text,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_mapping_decide(p_item uuid, p_dict text, p_status text, p_note text DEFAULT NULL::text, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_code text; tid uuid;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_status not in ('linked', 'rejected', 'pending') then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ and import_batch is null) then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  if p_status = 'linked' then
    if nullif(btrim(p_dict), '') is null then raise exception 'master_code_not_found'; end if;
    if coalesce(p_force, false) and not public.is_owner() then raise exception 'not allowed'; end if;
    perform public._item_link(p_item, btrim(p_dict), 'manual', p_force);
    update public.item_mapping_review set status = 'linked', suggested_code = coalesce(suggested_code, btrim(p_dict)), decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  else
    select master_code into old_code from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
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
end $function$$r0_0$, null),
  ('public.item_mapping_decide(uuid,text,text,text,boolean)', 'known', 'd6207b19cbf2dcb0fe81903f88f2c4b4', null);
-- item_master_import_apply(jsonb,text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_master_import_apply(jsonb,text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_master_import_apply(p_rows jsonb, p_batch text, p_expected integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      on conflict (org_unit_id, code) /* m132 */ do nothing;
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
end $function$$r0_0$, null),
  ('public.item_master_import_apply(jsonb,text,integer)', 'known', '417489316d983a75e9dbb0239e7f9d39', null);
-- item_new(jsonb,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.item_new(jsonb,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.item_new(p_patch jsonb, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    return jsonb_build_object('status', 'created', 'item_id', iid, 'code', (select code from public.items where id = iid and public._m132_own(items.org_unit_id) /* m132b:items */));
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (null, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  perform set_config('bos.item_apply', '', true);
  return jsonb_build_object('status', 'pending', 'id', cid);
end $function$$r0_0$, null),
  ('public.item_new(jsonb,text)', 'known', 'dd04b5bbe99f986f5364a9cd738aa648', null);
-- items_with_cost()
insert into _u_plan (fn, kind, a, b) values
  ('public.items_with_cost()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.items_with_cost()
 RETURNS TABLE(item_id uuid, cost_price numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.item_id, c.cost_price from (
    select e.item_id, e.cost_price from public._item_cost_eff88() e where (select not public._org_on123() or public.is_owner())   -- bos88: the effective cost of the ONE source (report_cost_source); an item with no known cost has NO row = unknown, never 0
    union all
    select s.item_id, s.cost_price from public._item_cost_scoped123() s where (select public._org_on123() and not public.is_owner())   -- scope123: my own places only
  ) c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$function$$r0_0$, null),
  ('public.items_with_cost()', 'known', 'cce3ebb32149b8ae0541c35f4c8036aa', null);
do $u536$
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
  if miss <> '' then raise exception 'phase536: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase536: merged text of the two lines', cur);
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
  raise notice 'phase536: % function(s) changed', nfix;
end $u536$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase537.sql
-- Phase 537 (UNION-9: the advanced line's logic in 32 shared functions (location_save ... recipe_yield_suggestion) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
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
-- location_save(integer,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.location_save(integer,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.location_save(p_id integer, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.locations; v_code text; base text; n int := 1; v text; k text; sb int; hops int := 0; nid int; po date; sortv int; hubv boolean;
  newname_bn text; newname_en text;
begin
  if p_id is null then
    if not (public._loc_mgr() or public._pc_ok135()) then raise exception 'not allowed'; end if;   /* loc135 */
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
    if exists (select 1 from public.locations x where (not public._pc_ok135() or public._business_of_unit123(x.org_unit_id) is not distinct from public._pc_biz135())
                  and (lower(btrim(x.name_bn)) = lower(newname_bn) or (newname_en is not null and lower(btrim(coalesce(x.name_en, ''))) = lower(newname_en)))) then raise exception 'name_in_use'; end if;
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
    insert into public.locations (code, name_bn, name_mix, name_en, sort, is_active, kind, model, status, supplied_by, planned_opening, hub_functions, note, created_by, created_at, status_by, status_at, org_unit_id)
    values (v_code, newname_bn, nullif(btrim(coalesce(p_patch->>'name_mix', '')), ''), newname_en,
            coalesce(sortv, (select coalesce(max(x.sort), 0) + 1 from public.locations x)), true,
            coalesce(nullif(p_patch->>'kind', ''), 'showroom'), coalesce(nullif(p_patch->>'model', ''), 'A'), 'planned', sb, po,
            coalesce(hubv, false), nullif(p_patch->>'note', ''), auth.uid(), now(), auth.uid(), now(), public._pc_unit135())
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
end $function$$r0_0$, null),
  ('public.location_save(integer,jsonb)', 'known', '58511c50bddf09406120f1e54f10affb', null);
-- login_failed(text)
insert into _u_plan (fn, kind, a, b) values
  ('public.login_failed(text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.login_failed(p_staff text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s text := left(lower(btrim(coalesce(p_staff, ''))), 64); mx int := public._login_setting_num('max_fails', 5)::int;
        lm int := public._login_setting_num('lock_minutes', 10)::int; known boolean; f public.login_failures; nf int;
begin
  if s = '' then return; end if;
  select exists (select 1 from public.profiles where staff_id = s) into known;
  -- spam guard: unknown ids share ONE global bucket; known ids get 50 log rows per minute each. Unknown/known look the same to the caller.
  if not public._login_throttle(case when known then 'sid:' || s else 'unknown' end, case when known then 20 else 60 end) then return; end if;
  insert into public.login_attempts (staff_id, ok, ip_hint) values (s, false, null);
  if not known and not public._org_on123() then return; end if;   /* scope133 */
  if not known and random() < 0.02 then delete from public.login_failures lf where lf.last_fail < now() - interval '1 day' and not exists (select 1 from public.profiles p where p.staff_id = lf.staff_id); end if;
  select * into f from public.login_failures where staff_id = s for update;
  if not found then
    insert into public.login_failures (staff_id, fails, locked, locked_until, window_start, last_fail)
      values (s, 1, 1 >= mx, case when 1 >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) end, now(), now())
    on conflict (staff_id) do nothing;
    return;
  end if;
  if f.locked then
    if f.locked_until is not null and f.locked_until <= now() and public._login_auto_release_for(s) then
      update public.login_failures set fails = 1, locked = (1 >= mx), locked_until = case when 1 >= mx then now() + make_interval(mins => lm) end,
        window_start = now(), last_fail = now() where staff_id = s;
    else
      update public.login_failures set last_fail = now() where staff_id = s;   -- still locked: attempts do not extend the lock
    end if;
    return;
  end if;
  if f.window_start < now() - make_interval(mins => lm) then nf := 1; else nf := f.fails + 1; end if;
  update public.login_failures set
    fails = nf, last_fail = now(),
    window_start = case when nf = 1 then now() else f.window_start end,
    locked = nf >= mx,
    locked_until = case when nf >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) else null end
  where staff_id = s;
end $function$$r0_0$, null),
  ('public.login_failed(text)', 'known', 'a929eef6ffcf32ba491b2cc217431d19', null);
-- loyalty_award(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.loyalty_award(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.loyalty_award(p_sale uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.sales; c public.customers; t public.customer_tiers; per numeric; pts int;
begin
  if not public.rule_on('loyalty_points_on') then return 0; end if;
  select * into s from public.sales where id = p_sale;
  if not found or s.customer_id is null or s.status <> 'done' then return 0; end if;
  select * into c from public.customers where id = s.customer_id and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  select * into t from public.customer_tiers where id = c.tier_id;
  per := coalesce(public.rule_num('points_per_100_taka'), 0);
  pts := floor(s.total * per * coalesce(t.points_multiplier, 1) / 100)::int;
  if pts <= 0 then return 0; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, note, by_user, by_staff)
    values (s.customer_id, pts, 'sale', s.id, 'receipt ' || s.receipt, s.created_by, s.created_staff) on conflict do nothing;
  return pts;
end $function$$r0_0$, null),
  ('public.loyalty_award(uuid)', 'known', '5950eb1b451e317891ccff29872a75b2', null);
-- notify_cancel(bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_cancel(bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_cancel(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  update public.notify_outbox set status = 'cancelled', last_error = 'cancelled_by_staff' where id = p_id and status in ('queued', 'failed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_cancellable'; end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $function$$r0_0$, null),
  ('public.notify_cancel(bigint)', 'known', '76c97ec512ce0bb5005685b1bc2067fc', null);
-- notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_enqueue(p_client uuid, p_customer uuid, p_channel text, p_template text, p_vars jsonb DEFAULT '{}'::jsonb, p_lang text DEFAULT 'bn'::text, p_source_type text DEFAULT NULL::text, p_source_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.notify_templates; c public.customers; ph text; b text; k text; v text; ex public.notify_outbox; nid bigint; mt int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then raise exception 'sms_off'; end if;
  if p_client is null or p_customer is null or p_channel not in ('sms', 'whatsapp') or p_template is null or coalesce(p_lang, 'bn') not in ('bn', 'en')
     or (p_vars is not null and jsonb_typeof(p_vars) <> 'object') or (p_source_type is null) <> (p_source_id is null)
     or (p_source_type is not null and (length(p_source_type) > 40 or length(p_source_id) > 80)) then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.notify_outbox where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  select * into t from public.notify_templates where code = p_template and active;
  if not found then raise exception 'template_not_found'; end if;
  if t.channel <> p_channel then raise exception 'template_channel_mismatch'; end if;
  select * into c from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */;
  if not found then raise exception 'customer_not_found'; end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
  perform public._crmb_enqueue_guard(p_customer, p_channel); /* bosCRMB: do-not-contact and linked duplicates */
  ph := public._i62_phone(c.mobile);
  if ph is null then raise exception 'bad_phone'; end if;
  b := case when coalesce(p_lang, 'bn') = 'en' then t.body_en else t.body_bn end;
  b := replace(b, '{name}', coalesce(left(c.name, 60), ''));
  for k, v in select key, left(value, 100) from jsonb_each_text(coalesce(p_vars, '{}'::jsonb)) loop
    if k ~ '^[a-z_]{1,20}$' then b := replace(b, '{' || k || '}', v); end if;
  end loop;
  b := regexp_replace(b, '\{[a-z_]{1,20}\}', '', 'g');
  if length(btrim(b)) not between 1 and 480 then raise exception 'bad_body'; end if;
  mt := greatest(least(coalesce(public.rule_num('notify_sms_max_tries'), 5)::int, 20), 1);
  begin
    insert into public.notify_outbox (client_id, customer_id, channel, to_phone, template_code, body, max_attempts, source_type, source_id, created_by)
      values (p_client, p_customer, p_channel, ph, p_template, btrim(b), mt, p_source_type, p_source_id, auth.uid()) returning id into nid;
  exception when unique_violation then
    select * into ex from public.notify_outbox where source_type = p_source_type and source_id = p_source_id and template_code = p_template;
    return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true);
  end;
  return jsonb_build_object('id', nid, 'status', 'queued', 'duplicate', false);
end $function$$r0_0$, null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', '00b01af71f9ed0b0bd9559c027d36136', null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', '81352a4d7577e6ff89e7972e36fe1dbe', null),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'known', 'f2e44de25e88a7c5a3535c18aa38d3f5', null);
-- notify_optin_set(uuid,text,boolean,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_optin_set(p_customer uuid, p_channel text, p_in boolean, p_source text DEFAULT 'owner_entry'::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_customer is null or p_in is null or p_channel not in ('sms', 'whatsapp') or coalesce(p_source, 'owner_entry') not in ('customer_consent', 'owner_entry')
     or (p_note is not null and length(p_note) > 200) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */) then raise exception 'customer_not_found'; end if;
  if p_in and public._i62_phone((select mobile from public.customers where id = p_customer and public._m132_own(customers.org_unit_id) /* m132b:customers */)) is null then raise exception 'bad_phone'; end if;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid());
  perform public._crmb_legacy_evidence(p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note); /* bosCRMB: evidence line */
  if not p_in then   -- opting out cancels what is still waiting
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st);
end $function$$r0_0$, null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '2dc63a9a540cd9afa90c223b7c33101c', null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '52eb8bb18690f687a54cdaf3d1e23b86', null),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', 'known', '530a8f4475d3c1670ccc4c4473aa7287', null);
-- notify_outbox_summary()
insert into _u_plan (fn, kind, a, b) values
  ('public.notify_outbox_summary()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.notify_outbox_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception 'not allowed'; end if;   /* scope133 */
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('notify_sms_on'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.notify_outbox group by status) s), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts, 'template', template_code,
        'to', left(to_phone, 6) || '****' || right(to_phone, 2), 'last_error', last_error, 'created_at', created_at, 'sent_at', sent_at) order by id desc)
        from (select * from public.notify_outbox order by id desc limit 50) r), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.notify_outbox_summary()', 'known', '811e64958974acb57eab987fccf9b41e', null);
-- online_order_get(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_order_get(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_order_get(p_id uuid)
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
  j := public._inb_pii_json99(j);                                                                               -- bos99
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.online_order_get(uuid)', 'known', 'e6647b83d678b5c736619267f7a043b8', null);
-- online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_order_save(p_id uuid, p_client uuid, p_loc integer, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb, p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text)
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
end $function$$r0_0$, null),
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)', 'known', 'f76b73ddde41b954c0d9b66f4801cba6', null);
-- online_orders_list(integer,text,date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.online_orders_list(integer,text,date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.online_orders_list(p_loc integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_limit integer DEFAULT 100)
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
    select o.id, o.order_no, o.location_id, o.channel, public._inb_pii_f99('name', o.customer_name) as customer_name,   -- bos99
           case when public._inb_contact_ok(o.location_id) then public._inb_pii_f99('mobile', o.customer_mobile) end as customer_mobile,   -- bos76 bos99
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked, public._inb_pii_mode99() as pii_mode,   -- bos76 bos99
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $function$$r0_0$, null),
  ('public.online_orders_list(integer,text,date,date,integer)', 'known', 'e0914436e4ad0e16d81d774affd75011', null);
-- packaging_set(uuid,uuid,numeric,text,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.packaging_set(p_product uuid, p_packaging uuid, p_qty numeric, p_applies text DEFAULT 'sale'::text, p_active boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pr public.items; pk public.items; rid bigint;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_applies not in ('sale', 'production') then raise exception 'bad_value'; end if;
  if p_qty is null or not (p_qty > 0 and p_qty < 1000000) then raise exception 'bad_qty'; end if;
  select * into pr from public.items where id = p_product and public._m132_own(items.org_unit_id) /* m132b:items */;
  select * into pk from public.items where id = p_packaging and public._m132_own(items.org_unit_id) /* m132b:items */;
  if pr.id is null or pk.id is null then raise exception 'item_not_found'; end if;
  if pk.item_type is distinct from 'packaging' then raise exception 'bad_ingredient_type' using detail = pk.code; end if;
  if pr.item_type not in ('finished_good', 'resale') then raise exception 'bad_product_type'; end if;
  insert into public.product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to, active, note, updated_by, updated_at)
    values (p_product, p_packaging, p_qty, p_applies, coalesce(p_active, true), left(p_note, 200), auth.uid(), now())
    on conflict (product_item_id, packaging_item_id, applies_to) do update
      set qty_per_unit = excluded.qty_per_unit, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now()
    returning id into rid;
  return rid;
end $function$$r0_0$, null),
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)', 'known', 'e04a9dcd6c818f716c504c858cc5e734', null);
-- partner_calculate(bigint,date,date,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.partner_calculate(bigint,date,date,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */ locs int[]; k text; r record; cfg jsonb; sh jsonb; er record; er2 record;
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
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;
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
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);
end $function$$r0_0$, null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', '307859e61a0dbf410cc0e17b7b63f79d', null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', 'c4072622b8e2e28d903f48b88ea69c99', null),
  ('public.partner_calculate(bigint,date,date,jsonb)', 'known', 'e9c4d1a5df3790be9431b316389276a6', null);
-- partner_settlement_save(bigint,date,date,jsonb,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid DEFAULT NULL::uuid)
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
end $function$$r0_0$, null),
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', 'known', 'dbda3123c8cdeeb2426357531035f0df', null);
-- path_cfg(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.path_cfg(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.path_cfg(p_domain text, p_loc integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('a_open', coalesce(x.a_open, true), 'b_open', coalesce(x.b_open, true), 'primary', coalesce(x.primary_rule, case when d.legacy_rule is not null and public.rule_on(d.legacy_rule) then 'b' else d.default_primary end))
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        and (s.location_id = 0 or public._cfgvis133(s.location_id)) /* scope133 */ order by s.location_id desc limit 1) x on true
   where d.domain = p_domain;
$function$$r0_0$, null),
  ('public.path_cfg(text,integer)', 'known', 'c12ccf4692a26e5a896b3ea6d1486aec', null);
-- pay_supplier(uuid,integer,jsonb,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.pay_supplier(p_supplier uuid, p_loc integer, p_payments jsonb, p_client uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */
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
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (p_supplier, p_loc, null, pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('paid', tot, 'balance', bal - tot);
end $function$$r0_0$, null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '11c68a538d1adbb2dad1546a563a117f', null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '27ff51231129d7176705ea93bc07cd3a', null),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'known', '31cbab604c7a47236bd135753deb4012', null);
-- payment_intent_link(bigint,bigint)
insert into _u_plan (fn, kind, a, b) values
  ('public.payment_intent_link(bigint,bigint)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.payment_intent_link(p_id bigint, p_sale_payment bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sale_payments where id = p_sale_payment and ((select not public._org_on123()) or auth.uid() is null or public._biz_ok123(location_id))) then   /* scope133 */ raise exception 'payment_not_found'; end if;
  if exists (select 1 from public.payment_intents where sale_payment_id = p_sale_payment and id <> p_id) then raise exception 'payment_already_linked'; end if;
  update public.payment_intents set sale_payment_id = p_sale_payment, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'sale_payment_id', p_sale_payment);
end $function$$r0_0$, null),
  ('public.payment_intent_link(bigint,bigint)', 'known', 'c7c5c98ed498fc66bbf519123233e89a', null);
-- pool_set(integer,date,text,numeric,text,boolean,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.pool_set(p_loc integer, p_month date, p_type text, p_amount numeric, p_period_kind text DEFAULT 'month'::text, p_one_off boolean DEFAULT false, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
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
  if public.rule_on('pool_gl_post117') and (public.is_owner() or public._acct_manage()) then      -- sec121: owner / accountant only, others rely on the catch-up; bos117: the typed pool also becomes the expense in the books (the matching Dr for the Cr 5950 absorbed)
    begin perform public._pool_gl_sync117(p_loc, m);
    exception when others then
      perform public._stock_exc(p_loc, 'pool_gl_failed', 'yellow', 'কারখানার খরচ হিসাবে (GL) ওঠেনি: ' || left(sqlerrm, 120), 'The factory cost could not be posted to the books: ' || left(sqlerrm, 120), null, m, 'STOCK');
    end;
  end if;
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $function$$r0_0$, null),
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', 'known', '358f68e44003d9b8fb0157547f45cba6', null);
-- production_can_make(integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_can_make(integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_can_make(p_loc integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; out jsonb := '[]'::jsonb; mx numeric; lim uuid; unk boolean; n record; per numeric; it public.items;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for r in select distinct on (item_id) * from public.recipes where active order by item_id, version desc loop
    select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
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
end $function$$r0_0$, null),
  ('public.production_can_make(integer)', 'known', '30c4626c6dddf2b4a19bfa7fd0abf984', null);
-- production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamp with time zone, p_note text, p_actual_yield numeric)
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
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
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
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89
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
end $function$$r0_0$, null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', '01a3ef963f29db79b951d3b9df768bef', null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', '6859c81ecf25a25c8e54182f652bc250', null),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'known', 'c9bc08ce76c01947ab33a08ce867a8c4', null);
-- production_preview(integer,uuid,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_preview(integer,uuid,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_preview(p_loc integer, p_recipe uuid, p_batches numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; yb numeric; ls jsonb; sh jsonb; wm int;
begin
  if not public._recipe_read() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_batches is null or not (p_batches between 0.0001 and 100000) then raise exception 'bad_qty'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  yb := round(public._base_qty(r.item_id, r.yield_qty, r.yield_unit) * p_batches, 4);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', n.item_id, 'kind', n.kind, 'code', n.code, 'name_bn', n.name_bn, 'name_en', n.name_en, 'need', n.need, 'on_hand', n.on_hand,
           'short', greatest(n.need - n.on_hand, 0), 'unit', n.base_unit, 'tracked', n.tracked, 'unit_ok', n.unit_ok, 'waste_missing', n.waste_missing) order by n.kind, n.code), '[]'::jsonb),
         coalesce(jsonb_agg(n.item_id) filter (where n.need > n.on_hand), '[]'::jsonb), count(*) filter (where n.waste_missing)
    into ls, sh, wm from public._recipe_need(p_recipe, p_batches, p_loc) n;
  return jsonb_build_object('recipe_id', r.id, 'item_id', r.item_id, 'version', r.version, 'active', r.active, 'batches', p_batches, 'yield_base', yb, 'yield_unit', public._item_base(r.item_id),
    'lines', ls, 'short_items', sh, 'waste_missing', wm,
    'can_make', (jsonb_array_length(sh) = 0 and not exists (select 1 from jsonb_array_elements(ls) x where (x->>'tracked')::boolean is not true or (x->>'unit_ok')::boolean is not true)),
    'tracked', it.tracked);
end $function$$r0_0$, null),
  ('public.production_preview(integer,uuid,numeric)', 'known', '5ed96727886165b8e3ad862258b6e7ae', null);
-- production_run_costs(integer,date,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_run_costs(integer,date,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_run_costs(p_loc integer, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', case when coalesce(r.conversion_mode, 'off') = 'off' then null else r.conversion_cost end,   /* bos401 */
        'conversion_status', case when coalesce(r.conversion_mode, 'off') = 'off' then 'not_captured' end,
        'unit_cost_basis', case when coalesce(r.conversion_mode, 'off') = 'off' then 'material_only' else 'material_and_conversion' end, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', case when r.yield_actual is null then null else r.actual_cost end, 'actual_status', case when r.yield_actual is null then 'not_captured' end,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail,
      'cost_full_yield', r.cost_full_yield116, 'std_unit_cost', r.std_unit_cost116, 'conversion_provisional', r.conversion_provisional116,
      'yield_loss_money', case when r.cost_complete and coalesce(r.yield_std, 0) > 0 and r.yield_actual is not null then round((coalesce(r.material_cost, 0) + coalesce(r.conversion_cost, 0)) * (1 - r.yield_base / r.yield_std), 2) end) order by r.made_at, r.id)      -- bos116
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $function$$r0_0$, null),
  ('public.production_run_costs(integer,date,date)', 'known', '7178010da5ac8a62f96efd91be331a39', null),
  ('public.production_run_costs(integer,date,date)', 'known', '7571cb2c8ad74b490d1821ec548d16d6', null),
  ('public.production_run_costs(integer,date,date)', 'known', 'ee6a4845b5baedc33b7170f57253f95a', null);
-- production_void(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.production_void(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.production_void(p_run uuid, p_note text)
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
end $function$$r0_0$, null),
  ('public.production_void(uuid,text)', 'known', '613e15ba809f5360f66544e1c801bc59', null);
-- profit_source_check(date,date,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.profit_source_check(date,date,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.profit_source_check(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); fr date := p_from; locs int[]; r record; jc numeric; cid bigint; pend int := 0; cmp_from date; notes jsonb := '[]'::jsonb; rc numeric; ok boolean;
begin
  if not public.biz_ok() or not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  locs := public._cogs_locs72(p_loc);
  select round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.led_cogs), 0), 2) as led, round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_cogs), 0), 2) as fb,
         round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_rev), 0), 2) as fbr, round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev), 0), 2) as unk,
         round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.rev), 0), 2) as netrev
    into r from public._cogs_lines72(p_from, p_to, locs) h;
  rc := r.led + r.fb;
  -- the books only start at the accounting start date: compare the same days
  cmp_from := case when st is null then null else greatest(p_from, st) end;
  if st is not null and public._acct_view() and cmp_from <= p_to then
    select account_id into cid from public.acct_mappings where key = 'cogs';
    select coalesce(sum(b.dr - b.cr), 0) into jc from public._acct_bal(cmp_from, p_to, p_loc) b where b.account_id = cid;
    select count(*) into pend from public._acct_docs(st) d where d.waiting is null and d.source_type in ('sale', 'sale_return') and d.entry_date between cmp_from and p_to
      and (p_loc is null or d.location_id = p_loc) and ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id));   /* scope133 */
    if cmp_from > p_from then   -- report side for the compared days only
      select round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)), 0), 2) into rc from public._cogs_lines72(cmp_from, p_to, locs) h;
    end if;
  else jc := null; end if;
  if r.fb <> 0 then notes := notes || to_jsonb('fallback_used'::text); end if;
  if r.unk <> 0 then notes := notes || to_jsonb('unknown_cost'::text); end if;
  if pend > 0 then notes := notes || to_jsonb('journal_pending'::text); end if;
  if jc is null then notes := notes || to_jsonb('journal_unavailable'::text); end if;
  ok := jc is not null and abs(rc - jc) <= 0.01 and r.fb = 0 and r.unk = 0 and pend = 0;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc,
    'report_cogs', r.led + r.fb, 'ledger_cogs', r.led, 'fallback_cogs', r.fb, 'fallback_rev', r.fbr, 'unknown_cost_rev', r.unk, 'net_revenue', r.netrev,
    'journal_cogs', jc, 'compared_from', cmp_from, 'compared_report_cogs', case when jc is null then null else rc end,
    'difference', case when jc is null then null else round(rc - jc, 2) end, 'pending_docs', pend, 'agree', ok, 'notes', notes);
end $function$$r0_0$, null),
  ('public.profit_source_check(date,date,integer)', 'known', '33394b1a312ba88565b7d33db94507ed', null);
-- purchase_get(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.purchase_get(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.purchase_get(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b public.purchase_bills;
begin
  select * into b from public.purchase_bills where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._pur_ok(b.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(b) || jsonb_build_object('supplier_name', (select name from public.suppliers where id = b.supplier_id and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no) from public.purchase_lines l where l.bill_id = b.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'mode', p.mode, 'wallet', p.wallet, 'ref', p.ref, 'amount', p.amount, 'paid_at', p.paid_at, 'voided', p.voided) order by p.id) from public.supplier_payments p where p.bill_id = b.id), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.purchase_get(uuid)', 'known', '39dfedb32a2c26c7ef5e8c6d0abd3dd4', null);
-- recipe_approve(uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_approve(uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_approve(p_recipe uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; prev jsonb; selfap boolean := false; sid text;   -- bos87
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
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
end $function$$r0_0$, null),
  ('public.recipe_approve(uuid,text)', 'known', '95d59422fb9334d709ec01809d7925f6', null);
-- recipe_book(integer,boolean,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_book(integer,boolean,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_book(p_artisan integer DEFAULT NULL::integer, p_with_cost boolean DEFAULT false, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.artisans; aid int := coalesce(p_artisan, public._artisan_of_user()); rs jsonb := '[]'::jsonb; r record; ln jsonb; st jsonb; lab jsonb; cst jsonb; cost_on boolean;
begin
  if aid is null or not public._recipe_view_ok(aid) then raise exception 'not allowed'; end if;
  select * into a from public.artisans where id = aid and public._m132_vis('artisans', artisans.org_unit_id, artisans.id::text, false) /* m132b:artisans */;
  if not found then raise exception 'artisan_not_found'; end if;
  cost_on := coalesce(p_with_cost, false) and public._recipe_cost_ok();
  for r in select rc.*, i.code, i.name_bn, i.name_en from public.recipes rc join public.items i on i.id = rc.item_id where rc.artisan_id = aid and rc.active order by i.code, rc.version loop
    select coalesce(jsonb_agg(jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'qty', l.qty, 'unit', coalesce(l.unit, public._item_base(l.ingredient_item_id)),
        'waste_pct', l.waste_pct, 'waste_missing', l.waste_pct is null) order by l.sort, l.id), '[]'::jsonb) into ln
      from public.recipe_lines l join public.items x on x.id = l.ingredient_item_id where l.recipe_id = r.id and l.active;
    select coalesce(jsonb_agg(jsonb_build_object('step_no', s.step_no, 'step_name', s.step_name, 'description', s.description, 'minutes', s.minutes, 'people', s.people, 'fuel', s.fuel, 'fuel_other', s.fuel_other,
        'flame_note', s.flame_note, 'equipment', s.equipment, 'qc_note', s.qc_note, 'resp_post', s.resp_post, 'resp_other', s.resp_other) order by s.step_no), '[]'::jsonb) into st
      from public.recipe_steps s where s.recipe_id = r.id and s.active;
    lab := public.recipe_labour_suggest(r.id);
    cst := null;
    if cost_on then
      begin cst := public.recipe_cost(r.id, p_loc); exception when others then cst := jsonb_build_object('error', sqlerrm); end;
    end if;
    rs := rs || (jsonb_build_object('recipe_id', r.id, 'version', r.version, 'item_id', r.item_id, 'code', r.code, 'name_bn', r.name_bn, 'name_en', r.name_en, 'yield_qty', r.yield_qty,
        'yield_unit', coalesce(r.yield_unit, public._item_base(r.item_id)), 'approved', r.approved_at is not null, 'approved_at', r.approved_at, 'form_ref', r.form_ref,
        'lines', ln, 'steps', st, 'labour', lab) || case when cost_on then jsonb_build_object('cost', cst) else '{}'::jsonb end);
  end loop;
  perform public._audit_view('recipe_book', aid::text, jsonb_build_object('with_cost', cost_on, 'recipes', jsonb_array_length(rs)));
  return jsonb_build_object('artisan', jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active), 'recipes', rs, 'with_cost', cost_on, 'generated_at', now());
end $function$$r0_0$, null),
  ('public.recipe_book(integer,boolean,integer)', 'known', '328fb90f9d21f76d39ca955ffd693f3a', null);
-- recipe_copy(uuid,uuid,boolean,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_copy(uuid,uuid,boolean,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_copy(p_from uuid, p_item uuid DEFAULT NULL::uuid, p_retire_old boolean DEFAULT false, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
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
  insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at, artisan_id)
    values (tgt.id, v, s.yield_qty, case when tgt.id = s.item_id then s.yield_unit else null end, true, s.note, p_client, auth.uid(), auth.uid(), now(),
            case when tgt.id = s.item_id and exists (select 1 from public.artisans a where a.id = s.artisan_id and a.active) then s.artisan_id end) returning id into rid;   -- bos73
  insert into public.recipe_lines (recipe_id, ingredient_item_id, qty, unit, waste_pct, note, sort)
    select rid, ingredient_item_id, qty, unit, waste_pct, note, sort from public.recipe_lines where recipe_id = p_from and active;
  insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
    select rid, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, auth.uid()
      from public.recipe_steps where recipe_id = p_from and active;   -- bos73
  if tgt.id <> s.item_id and public._base_qty(tgt.id, s.yield_qty, null) is null then raise exception 'unit_unknown'; end if;
  if p_retire_old and tgt.id = s.item_id then update public.recipes set active = false where id = p_from; end if;
  perform public._rv_log(rid, 'created', null, 'copy of version ' || s.version::text);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $function$$r0_0$, null),
  ('public.recipe_copy(uuid,uuid,boolean,uuid)', 'known', 'b690cbb197ca80cd1731e192ec3ad7a5', null);
-- recipe_cost(uuid,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_cost(uuid,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_cost(p_recipe uuid, p_loc integer DEFAULT NULL::integer)
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
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
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
    if av is null and public._cost_free80(n.item_id) then av := 0; end if;   -- bos103: a free-cost item is a known cost 0 (production_post accepts it the same way)
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
end $function$$r0_0$, null),
  ('public.recipe_cost(uuid,integer)', 'known', 'fa76dd3b2076ca1fd8efec9ed92b3c21', null);
-- recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_cost_component_set(p_recipe uuid, p_type text, p_basis text, p_amount numeric, p_hours numeric DEFAULT NULL::numeric, p_type_note text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d public.recipe_cost_components; nid bigint; tn text := nullif(btrim(p_type_note), '');
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.recipe_cost_components where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if not exists (select 1 from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */) then raise exception 'recipe_not_found'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_type = 'other' and tn is null then raise exception 'type_note_needed'; end if;
  if p_basis not in ('per_batch', 'per_unit', 'per_labour_hour') then raise exception 'bad_value'; end if;
  if p_amount is not null and not (p_amount >= 0 and p_amount <= 1000000000) then raise exception 'bad_cost'; end if;
  if p_hours is not null and not (p_hours >= 0 and p_hours <= 100000) then raise exception 'bad_qty'; end if;
  update public.recipe_cost_components set active = false where recipe_id = p_recipe and component_type = p_type and coalesce(type_note, '') = coalesce(tn, '') and active;
  insert into public.recipe_cost_components (recipe_id, component_type, type_note, basis, amount, hours_per_batch, note, set_by, client_id)
    values (p_recipe, p_type, case when p_type = 'other' then left(tn, 80) end, p_basis, p_amount, case when p_basis = 'per_labour_hour' then p_hours end, left(p_note, 200), auth.uid(), p_client) returning id into nid;
  return jsonb_build_object('id', nid, 'incomplete', p_amount is null or (p_basis = 'per_labour_hour' and p_hours is null));
end $function$$r0_0$, null),
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)', 'known', 'a139406c13fcbfed23116ffb450826b3', null);
-- recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid DEFAULT NULL::uuid, p_retire_old boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), ''); prev jsonb; /* bos73 */
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
    if not found then raise exception 'recipe_not_found'; end if;
    if r.approved_at is not null then raise exception 'recipe_approved'; end if;   -- bos73
    if r.used_at is not null then raise exception 'recipe_used'; end if;
    it := (select i from public.items i where i.id = r.item_id);
    prev := public._recipe_snapshot(p_id);   -- bos73
  else
    if p_client is not null then
      select * into r from public.recipes where client_id = p_client;
      if found then
        if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', r.id, 'version', r.version);
      end if;
    end if;
    select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
    if not found then raise exception 'item_not_found'; end if;
  end if;
  if it.item_type is distinct from 'finished_good' then raise exception 'bad_product_type'; end if;
  if public._base_qty(it.id, p_yield_qty, yu) is null then raise exception 'unit_unknown' using detail = it.code; end if;
  perform public._recipe_lines_ok(it.id, p_lines);
  if p_id is null then
    select coalesce(max(version), 0) + 1 into v from public.recipes where item_id = it.id;
    insert into public.recipes (item_id, version, yield_qty, yield_unit, active, note, client_id, created_by, changed_by, changed_at)
      values (it.id, v, p_yield_qty, yu, true, left(p_note, 300), p_client, auth.uid(), auth.uid(), now()) returning id into rid;   -- bos73: changed_by
    if p_retire_old then update public.recipes set active = false where item_id = it.id and id <> rid and active; end if;
  else
    rid := p_id; v := r.version;
    update public.recipes set yield_qty = p_yield_qty, yield_unit = yu, note = left(p_note, 300), changed_by = auth.uid(), changed_at = now() where id = rid;   -- bos73
    update public.recipe_lines set active = false where recipe_id = rid and active;      -- a draft only (never used): old lines are retired, never deleted; the trigger refuses this for a used version
  end if;
  perform public._recipe_put_lines(rid, p_lines);
  perform public._rv_log(rid, case when p_id is null then 'created' else 'edited' end, prev, null);   -- bos73
  return jsonb_build_object('id', rid, 'version', v);
end $function$$r0_0$, null),
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', 'known', '49944936dcab6b7fadc033befd0e3530', null);
-- recipe_steps_save(uuid,jsonb,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_steps_save(uuid,jsonb,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_steps_save(p_recipe uuid, p_steps jsonb, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; s jsonb; n int := 0; prev jsonb; mins numeric; ppl int; fu text; rp text; dup public.recipe_versions;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into dup from public.recipe_versions where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'recipe_id', dup.recipe_id); end if;
  end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */ for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then raise exception 'recipe_approved'; end if;
  if p_steps is null or jsonb_typeof(p_steps) <> 'array' then raise exception 'bad_value'; end if;
  if jsonb_array_length(p_steps) > 100 then raise exception 'too_many_lines'; end if;
  for s in select x from jsonb_array_elements(p_steps) x loop
    if length(btrim(coalesce(s->>'step_name', ''))) = 0 then raise exception 'step_name_needed'; end if;
    mins := nullif(btrim(s->>'minutes'), '')::numeric;
    if mins is not null and not (mins >= 0 and mins <= 100000) then raise exception 'bad_qty'; end if;
    ppl := nullif(btrim(s->>'people'), '')::int;
    if ppl is not null and not (ppl >= 0 and ppl <= 1000) then raise exception 'bad_qty'; end if;
    fu := nullif(btrim(s->>'fuel'), '');
    if fu is not null and fu not in ('gas', 'electric', 'other') then raise exception 'bad_value'; end if;
    if fu = 'other' and length(btrim(coalesce(s->>'fuel_other', ''))) = 0 then raise exception 'fuel_other_needed'; end if;
    rp := nullif(btrim(s->>'resp_post'), '');
    if rp is not null and rp not in ('karigor', 'chef', 'asst_karigor', 'other') then raise exception 'bad_post'; end if;
  end loop;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipe_steps set active = false where recipe_id = p_recipe and active;          -- old steps are retired, never deleted
  for s in select x from jsonb_array_elements(p_steps) x loop
    n := n + 1;
    insert into public.recipe_steps (recipe_id, step_no, step_name, description, minutes, people, fuel, fuel_other, flame_note, equipment, qc_note, resp_post, resp_other, created_by)
      values (p_recipe, n, left(btrim(s->>'step_name'), 120), left(nullif(btrim(s->>'description'), ''), 2000), nullif(btrim(s->>'minutes'), '')::numeric, nullif(btrim(s->>'people'), '')::int,
        nullif(btrim(s->>'fuel'), ''), case when s->>'fuel' = 'other' then left(btrim(s->>'fuel_other'), 60) end, left(nullif(btrim(s->>'flame_note'), ''), 200), left(nullif(btrim(s->>'equipment'), ''), 200),
        left(nullif(btrim(s->>'qc_note'), ''), 300), nullif(btrim(s->>'resp_post'), ''), case when s->>'resp_post' = 'other' then left(btrim(s->>'resp_other'), 60) end, auth.uid());
  end loop;
  update public.recipes set changed_by = auth.uid(), changed_at = now() where id = p_recipe;
  perform public._rv_log(p_recipe, 'steps_edited', prev, n::text || ' steps', p_client);
  return jsonb_build_object('recipe_id', p_recipe, 'steps', n) || (public.recipe_labour_suggest(p_recipe));
end $function$$r0_0$, null),
  ('public.recipe_steps_save(uuid,jsonb,uuid)', 'known', '64bcda698a159f90c96c74e099c8e72e', null);
-- recipe_yield_suggestion(uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.recipe_yield_suggestion(uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.recipe_yield_suggestion(p_recipe uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; e record; lines_ jsonb;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe and public._m132_own(recipes.org_unit_id) /* m132b:recipes */;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  select x.serial, x.entry_date, x.location_id, x.w into e from (
    select en.serial, en.entry_date, en.location_id,
           (select avg(public._r2_num(b -> 'waste') / nullif(coalesce(public._r2_num(b -> 'good'), 0) + coalesce(public._r2_num(b -> 'second'), 0) + coalesce(public._r2_num(b -> 'waste'), 0), 0) * 100)
              from jsonb_array_elements(public._p26_arr(en.data -> 'b')) b where public._r2_num(b -> 'waste') is not null) as w
      from public.entries en where en.form_code = '05-4' and en.status = 'approved' and en.data ->> 'item' = it.code and public.can_loc(en.location_id)
     order by en.entry_date desc, en.serial desc limit 1) x;
  select coalesce(jsonb_agg(jsonb_build_object('code', i.code, 'waste_pct', l.waste_pct) order by l.sort, l.id), '[]'::jsonb) into lines_
    from public.recipe_lines l join public.items i on i.id = l.ingredient_item_id where l.recipe_id = p_recipe and l.active;
  return jsonb_build_object('recipe_id', p_recipe, 'suggested_waste_pct', case when e.w is null then null else round(e.w, 2) end, 'source_serial', e.serial, 'source_date', e.entry_date,
    'recipe_lines_waste', lines_, 'note', 'suggestion_only', 'applied', false);
end $function$$r0_0$, null),
  ('public.recipe_yield_suggestion(uuid)', 'known', 'ee5672da78a73843eacb64f6ebbea0a0', null);
do $u537$
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
  if miss <> '' then raise exception 'phase537: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase537: merged text of the two lines', cur);
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
  raise notice 'phase537: % function(s) changed', nfix;
end $u537$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase538.sql
-- Phase 538 (UNION-10: the advanced line's logic in 21 shared functions (record_sale2 ... year_close_list) put back where a repaste of the early phases reset it). Paste-twice safe. Earlier phase files are not edited.
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
-- record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)
insert into _u_plan (fn, kind, a, b) values
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.record_sale2(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_discount_kind text DEFAULT NULL::text, p_discount_input numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; dkind text; dinput numeric; credit_over boolean := false; em text; ov_ok boolean;
  tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
  lt89 jsonb;   -- bos89
begin
  perform set_config('bos.em_used', '', true);
  perform set_config('bos.tier_use', '', true);   -- bos43
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: another user already used this client_id
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  -- discount given as an AMOUNT (default, also every old call) or as a PERCENT of the subtotal (computed here, 2 decimals)
  dkind := coalesce(nullif(btrim(p_discount_kind), ''), 'amount');
  if dkind not in ('amount', 'percent') then raise exception 'bad_discount_kind'; end if;
  if dkind = 'percent' then
    dinput := p_discount_input;
    if dinput is null or dinput = 'NaN'::numeric or dinput < 0 or dinput > 100 then raise exception 'bad_discount'; end if;
    disc := 0;                                        -- computed after the subtotal is known
  else
    dinput := coalesce(p_discount_input, p_discount, 0);
    if dinput = 'NaN'::numeric then raise exception 'bad_discount'; end if;
    dinput := round(dinput, 2); disc := dinput;
  end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found then raise exception 'item_not_found'; end if; /* bos22-late */ if not it.is_active and not (at_ < now() - interval '2 minutes' and it.updated_at > at_) then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        if public.rule_on('pos_override_manager') then
          if ov_ok is null then ov_ok := public.rule_ok('price_override', p_loc, null, null, 'sale'); end if;      -- one approval covers every price change in this sale
          if not ov_ok then raise exception 'override_needs_approval'; end if;
        end if;
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        shown := nullif(ln->>'price', '')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit, 'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    elsif ln ? 'qty' and ln ? 'price' then            -- an item that is not in the list
      qty := (ln->>'qty')::numeric; pr := (ln->>'price')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      if pr is null or pr = 'NaN'::numeric or pr <= 0 then raise exception 'bad_price'; end if;
      if nullif(btrim(ln->>'name'), '') is null then raise exception 'name_required'; end if;
      if public.rule_txt('pos_unlisted') = 'block' then raise exception 'unlisted_blocked'; end if;
      amt := round(qty * pr, 2); any_custom := coalesce(public.rule_txt('pos_unlisted'), 'flag') = 'flag';
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(btrim(ln->>'name'), 80), 'unit', left(coalesce(ln->>'unit', ''), 20), 'qty', qty, 'price', pr, 'amount', amt, 'override', false, 'custom', true);
    else                                              -- quick sale
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name', ''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if dkind = 'percent' then
    disc := round(sub * dinput / 100, 2);
    -- the phone shows the discount it computed from the percent; a half-cent case can round the other way here. Within one paisa (0.01) the amount the
    -- customer was shown wins, so the bill never asks for a paisa more or less than the screen said (never beyond 0.01, never outside 0..subtotal).
    if p_discount is not null and abs(p_discount - disc) <= 0.01 and p_discount between 0 and sub then disc := round(p_discount, 2); end if;
  end if;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if disc > 0 and not public.rule_on(case dkind when 'percent' then 'discount_mode_percent_on' else 'discount_mode_amount_on' end) then raise exception 'discount_mode_off'; end if;
  -- bos43: the customer's tier discount is pre-approved (switch tier_discount_on): the part of the discount up to the tier percent (and the tier cap) needs no manager approval
  if disc > 0 and public.rule_on('tier_discount_on') and nullif(btrim(p_customer_mobile), '') is not null then
    select t.id, t.discount_percent, t.discount_cap_amount into tier_id43, tier_pct43, tier_cap43
      from public.customers cu join public.customer_tiers t on t.id = cu.tier_id
      where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0 and public._m132_at(cu.org_unit_id, p_loc) /* m132 */;
    if found then tier_amt43 := least(disc, round(sub * tier_pct43 / 100, 2), coalesce(tier_cap43, disc)); end if;
  end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > tier_amt43 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;
    amt := (pay->>'amount')::numeric;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    amt := round(amt, 2); paid_sum := paid_sum + amt;
    if not pm = any (modes) then modes := modes || pm; end if;
  end loop;
  if paid_sum > sub - disc then raise exception 'overpaid'; end if;
  due := sub - disc - paid_sum;
  -- customer
  mob := case when nullif(btrim(p_customer_mobile), '') is not null then public.norm_mobile(p_customer_mobile) end;
  needcust := (due > 0 and public.rule_on('pos_customer_on_due')) or (stype = 'wholesale' and public.rule_on('pos_customer_on_wholesale')) or (disc > 0 and public.rule_on('pos_customer_on_discount'));
  if needcust and mob is null and not public.rule_ok('sale_without_customer', p_loc, null, null, 'sale') then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob and public._m132_at(org_unit_id, p_loc) /* m132 */ order by (org_unit_id is not distinct from public._m132_biz_of_loc(p_loc)) desc, org_unit_id limit 1 for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by, org_unit_id) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid(), public._m132_biz_of_loc(p_loc) /* m132 */) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null and coalesce(public.rule_txt('pos_credit_mode'), 'block') <> 'off' then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit then
        credit_over := true;
        if coalesce(public.rule_txt('pos_credit_mode'), 'block') = 'block' and not public.rule_ok('credit_over_limit', p_loc, due, null, 'sale') then raise exception 'over_credit_limit'; end if;
      end if;
    end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if tier_amt43 > 0 then perform set_config('bos.tier_use', tier_id43 || '|' || tier_pct43 || '|' || tier_amt43, true); end if;   -- bos43
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount, discount_kind, discount_input)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due, case when disc > 0 then dkind end, case when disc > 0 then dinput end)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    if p_client is not null and exists (select 1 from public.sales x where x.client_id = p_client and x.created_by is distinct from auth.uid()) then raise exception 'client_id_taken'; end if;   -- bos87: a race with another user
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
  end loop;
  -- exceptions for the owner (nothing is blocked here except the customer / credit rules above)
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  if any_custom then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unlisted_item', 'yellow', s.total,
        jsonb_build_object('bn', 'রসিদ ' || n || ': তালিকায় নেই এমন আইটেম বিক্রি — আইটেম তালিকায় যোগ করুন', 'en', 'Receipt ' || n || ': an item that is not in the list was sold — add it to the item list'));
  end if;
  if disc > tier_amt43 then   -- bos43 (was: disc > 0)
    if lim is null or jsonb_typeof(lim) = 'null' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_no_limit', 'yellow', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট দেওয়া হয়েছে কিন্তু ডিসকাউন্টের সীমা সেটিংসে নেই', 'en', 'Receipt ' || n || ': a discount was given but no discount limit is set'));
    elsif disc > (lim #>> '{}')::numeric then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_over_limit', 'red', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট সীমার উপরে', 'en', 'Receipt ' || n || ': discount above the limit'));
    end if;
  end if;
  if due > 0 and cust.id is null then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unattributed_due', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': বাকি আছে কিন্তু কোনো গ্রাহক নেই — এই বাকি কোনো গ্রাহকের খাতায় নেই', 'en', 'Receipt ' || n || ': an amount is due but there is no customer — it is on nobody’s ledger'));
  end if;
  if credit_over then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
  for em in select unnest(string_to_array(nullif(current_setting('bos.em_used', true), ''), ',')) loop
    if em <> '' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'emergency_used', 'yellow', s.total,
          jsonb_build_object('bn', 'রসিদ ' || n || ': জরুরি অনুমোদনে সেল (' || split_part(em, ':', 2) || ')', 'en', 'Receipt ' || n || ': sold on an emergency approval (' || split_part(em, ':', 2) || ')'));
    end if;
  end loop;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id, 'discount', disc);
end $function$$r0_0$, null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', '08a61db0833cf41e5256f8963ba3a2b5', null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', '6410e5d47a1109693208da2fbef16701', null),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'known', 'cdd520542240939b993bca9d8defae1c', null);
-- rollout_mode(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.rollout_mode(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.rollout_mode(p_form text, p_loc integer)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select mode from public.form_rollout where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), 'app');   /* scope133 */
$function$$r0_0$, null),
  ('public.rollout_mode(text,integer)', 'known', '7d9d84b171012c1649e2ce643476b177', null);
-- sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)
insert into _u_plan (fn, kind, a, b) values
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sales_channel_save(p_id integer, p_code text, p_kind text, p_other text, p_name text, p_loc integer, p_role text, p_account_ref text, p_active boolean DEFAULT true)
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
end $function$$r0_0$, null),
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)', 'known', '76028050e90cf1a269dc4f5affec9a73', null);
-- save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.save_purchase(p_client uuid, p_id uuid, p_supplier uuid, p_loc integer, p_bill_no text, p_bill_date date, p_lines jsonb, p_discount numeric DEFAULT 0, p_note text DEFAULT NULL::text, p_photo text DEFAULT NULL::text, p_kind text DEFAULT 'bill'::text, p_ref_bill uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pb public.purchase_bills; ln jsonb; it public.items; n int := 0; qty numeric; uc numeric; amt numeric; sub numeric := 0; disc numeric := coalesce(p_discount, 0);
        un text; bid uuid := p_id; sid text; ref public.purchase_bills; gcode text; norm jsonb := '[]'::jsonb;
begin
  if p_kind not in ('bill', 'return') then raise exception 'bad_kind'; end if;
  gcode := case p_kind when 'return' then 'purchase_return' else 'purchase_entry' end;
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_client is not null and p_id is null then          -- editing a draft (p_id) is never a "duplicate"
    select * into pb from public.purchase_bills where client_id = p_client;
    if found then
      if pb.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true);
    end if;
  end if;
  if bid is not null then
    select * into pb from public.purchase_bills where id = bid for update;
    if not found then raise exception 'not found'; end if;
    if pb.status <> 'draft' then raise exception 'not_draft'; end if;
    if pb.kind <> p_kind or pb.location_id <> p_loc then raise exception 'cannot_change_kind_or_location'; end if;
  end if;
  if not (public.has_grant(gcode, p_loc) or public._use_em(gcode, p_loc, 'save_purchase', null)) then raise exception 'not allowed'; end if;
  if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */ and active) then raise exception 'supplier_not_found'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (disc between 0 and 999999999999) then raise exception 'bad_discount'; end if;      -- false for NaN / Infinity
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if p_kind = 'return' then
    if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
    if p_ref_bill is null then
      if not public.is_owner() then raise exception 'return_needs_bill'; end if;
    else
      select * into ref from public.purchase_bills where id = p_ref_bill;
      if not found or ref.supplier_id <> p_supplier or ref.kind <> 'bill' or ref.status <> 'posted' then raise exception 'bad_ref_bill'; end if;
    end if;
  elsif p_ref_bill is not null then raise exception 'bad_ref_bill';
  end if;
  if nullif(btrim(p_bill_no), '') is not null and exists (select 1 from public.purchase_bills where supplier_id = p_supplier and lower(bill_no) = lower(btrim(p_bill_no)) and kind = p_kind and status <> 'void'
       and id is distinct from bid and (p_client is null or client_id is distinct from p_client)) then
    raise exception 'duplicate_bill';
  end if;
  -- validate lines first (nothing is written if one is wrong)
  for ln in select * from jsonb_array_elements(p_lines) loop
    qty := nullif(ln->>'qty', '')::numeric; uc := nullif(ln->>'unit_cost', '')::numeric;
    if qty is null or not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    if uc is null or not (uc between 0 and 999999999) then raise exception 'bad_cost'; end if;
    it := null; un := nullif(ln->>'unit', '');
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      un := coalesce(un, it.unit);
      if it.tracked and public._base_qty(it.id, 1, un) is null then raise exception 'unit_unknown'; end if;
    elsif nullif(btrim(ln->>'description'), '') is null then raise exception 'description_required';
    end if;
    sub := sub + round(qty * uc, 2);
    if not (sub <= 999999999999) then raise exception 'bad_amount'; end if;
    norm := norm || jsonb_build_array(jsonb_build_object('item_id', it.id, 'description', nullif(btrim(ln->>'description'), ''), 'qty', qty, 'unit', un, 'unit_cost', uc));
  end loop;
  if disc > sub then raise exception 'bad_discount'; end if;
  if p_kind = 'return' and p_ref_bill is not null then perform public._return_check(p_ref_bill, bid, norm); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if bid is null then
    begin
      insert into public.purchase_bills (client_id, kind, supplier_id, bill_no, bill_date, location_id, status, subtotal, discount, total, note, photo, reason_code, ref_bill_id, created_by, created_staff)
        values (p_client, p_kind, p_supplier, nullif(btrim(p_bill_no), ''), p_bill_date, p_loc, 'draft', sub, round(disc, 2), sub - round(disc, 2), left(p_note, 300), nullif(btrim(p_photo), ''), p_reason, p_ref_bill, auth.uid(), sid)
        returning id into bid;
    exception when unique_violation then
      select * into pb from public.purchase_bills where p_client is not null and client_id = p_client;
      if found and pb.created_by = auth.uid() then return jsonb_build_object('id', pb.id, 'status', pb.status, 'total', pb.total, 'dup', true); end if;
      raise exception 'duplicate_bill';
    end;
  else
    update public.purchase_bills set supplier_id = p_supplier, bill_no = nullif(btrim(p_bill_no), ''), bill_date = p_bill_date, subtotal = sub, discount = round(disc, 2), total = sub - round(disc, 2),
      note = left(p_note, 300), photo = nullif(btrim(p_photo), ''), reason_code = p_reason, ref_bill_id = p_ref_bill where id = bid;
    delete from public.purchase_lines where bill_id = bid;
  end if;
  for ln in select * from jsonb_array_elements(norm) loop
    n := n + 1; qty := (ln->>'qty')::numeric; uc := (ln->>'unit_cost')::numeric; amt := round(qty * uc, 2);
    insert into public.purchase_lines (bill_id, line_no, item_id, description, qty, unit, unit_cost, amount)
      values (bid, n, nullif(ln->>'item_id', '')::uuid, left(nullif(btrim(ln->>'description'), ''), 120), qty, left(nullif(ln->>'unit', ''), 20), uc, amt);
  end loop;
  return jsonb_build_object('id', bid, 'status', 'draft', 'total', sub - round(disc, 2), 'lines', n);
end $function$$r0_0$, null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', '4cc5b1117196648e04a15127eb685154', null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', '679a8ce09e2b97fccad841cadace5562', null),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'known', 'df1e1dc7039f37cc61b6e18551330bd0', null);
-- save_supplier(uuid,jsonb)
insert into _u_plan (fn, kind, a, b) values
  ('public.save_supplier(uuid,jsonb)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.save_supplier(p_id uuid, p_patch jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid := p_id; p jsonb := coalesce(p_patch, '{}');
begin
  if not public.has_grant('supplier_manage') then raise exception 'not allowed'; end if;
  if sid is null then
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    insert into public.suppliers (name, created_by) values (left(btrim(p->>'name'), 120), auth.uid()) returning id into sid;
  elsif not exists (select 1 from public.suppliers where id = sid and public._m132_vis('suppliers', suppliers.org_unit_id, suppliers.id::text, false) /* m132b:suppliers */) then raise exception 'not found';
  end if;
  update public.suppliers set
    name = case when p ? 'name' and nullif(btrim(p->>'name'), '') is not null then left(btrim(p->>'name'), 120) else name end,
    mobile = case when p ? 'mobile' then nullif(public.norm_mobile(p->>'mobile'), '') else mobile end,
    type_code = case when p ? 'type_code' then nullif(p->>'type_code', '') else type_code end,
    address = case when p ? 'address' then left(nullif(p->>'address', ''), 300) else address end,
    credit_days = case when p ? 'credit_days' then nullif(p->>'credit_days', '')::int else credit_days end,
    opening_balance = case when p ? 'opening_balance' then nullif(p->>'opening_balance', '')::numeric else opening_balance end,
    nid = case when p ? 'nid' then left(nullif(p->>'nid', ''), 40) else nid end,
    tin = case when p ? 'tin' then left(nullif(p->>'tin', ''), 40) else tin end,
    note = case when p ? 'note' then left(nullif(p->>'note', ''), 300) else note end,
    active = case when p ? 'active' then (p->>'active')::boolean else active end,
    updated_at = now()
  where id = sid;
  return sid;
end $function$$r0_0$, null),
  ('public.save_supplier(uuid,jsonb)', 'known', '86e38f6aacde788adc0a6eb601364f83', null);
-- sheet_sync_all()
insert into _u_plan (fn, kind, a, b) values
  ('public.sheet_sync_all()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.sheet_sync_all()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l record; n int := 0;
begin
  if not public._sheet_viewer() then raise exception 'not allowed'; end if;
  for l in select id from public.locations where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(id)) loop   /* scope133 */ perform public._sheet_writethrough(l.id); n := n + 1; end loop;
  return n;
end $function$$r0_0$, null),
  ('public.sheet_sync_all()', 'known', 'c2b22049a8f5d33ca08eb40ab0c8ac05', null);
-- shelf_life_for(uuid,date)
insert into _u_plan (fn, kind, a, b) values
  ('public.shelf_life_for(uuid,date)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.shelf_life_for(p_item uuid, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); md int := extract(month from d)::int * 100 + extract(day from d)::int;
        it public.items; r public.shelf_life_rules;
begin
  select * into it from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if not found then return null; end if;
  select * into r from public.shelf_life_rules s
  where s.active
    and (s.item_id = p_item or (s.item_id is null and s.category is not null and s.category = it.category) or (s.item_id is null and s.category is null))
    and (s.start_month is null
         or (case when s.start_month * 100 + s.start_day <= s.end_month * 100 + s.end_day
                  then md between s.start_month * 100 + s.start_day and s.end_month * 100 + s.end_day
                  else md >= s.start_month * 100 + s.start_day or md <= s.end_month * 100 + s.end_day end))
  order by (case when s.item_id is not null then 3 when s.category is not null then 2 else 1 end) desc,
           (s.start_month is not null) desc,
           (case when s.start_month is null then 0
                 when s.start_month * 31 + s.start_day <= s.end_month * 31 + s.end_day then (s.end_month * 31 + s.end_day) - (s.start_month * 31 + s.start_day)
                 else 372 - ((s.start_month * 31 + s.start_day) - (s.end_month * 31 + s.end_day)) end) asc,
           s.id desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object('rule_id', r.id, 'scope', case when r.item_id is not null then 'item' when r.category is not null then 'category' else 'all' end,
    'season', r.season_label, 'value', r.value, 'unit', r.unit, 'hours', case r.unit when 'days' then r.value * 24 else r.value end, 'date', d);
end $function$$r0_0$, null),
  ('public.shelf_life_for(uuid,date)', 'known', '335903b6a88e3632c9f237543a08c536', null);
-- stock_blind_active(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_blind_active(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_blind_active(p_form text, p_loc integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p_form in ('04-1', '04-3') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */
$function$$r0_0$, null),
  ('public.stock_blind_active(text,integer)', 'known', 'b9502bbe82a04d90f98a17e4353c9434', null);
-- stock_count_adjust(uuid,integer,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_count_adjust(p_item uuid, p_loc integer, p_counted numeric, p_note text, p_unit text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
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
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, case when d > 0 and public.rule_on('acct_count_adjust') then bal.avg_cost end /* bos85: a gain is recorded at the average cost so it has a known cost; the average does not move */, public._adj_batch114(p_item, p_loc, d, 'count gain'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:count-batch
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)', 'known', '282a9df482f28749d5e730abc87c2eff', null);
-- stock_opening(uuid,integer,numeric,numeric,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_opening(p_item uuid, p_loc integer, p_qty numeric, p_unit_cost numeric DEFAULT NULL::numeric, p_unit text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; bq numeric; f numeric; cost numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_opening', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'opening'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  if not public._may('stock_opening', p_loc, 'opening:' || p_item::text) then raise exception 'not allowed'; end if;
  perform 1 from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */ for no key update;                -- two people entering the same opening wait here (NO KEY UPDATE: ledger inserts take a KEY SHARE lock on the item, so this can never deadlock with them)
  if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and reason = 'opening') then raise exception 'opening_exists'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  cost := case when p_unit_cost is null then null else p_unit_cost / f end;       -- cost given per p_unit -> per base unit
  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, public._adj_batch114(p_item, p_loc, bq, 'opening stock'), now(), left(p_note, 200), null, 'none', null, p_client);   -- bos114:opening-batch
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $function$$r0_0$, null),
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)', 'known', 'fbf8d3ca185642152ceda9ee93608714', null);
-- stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_post(p_item uuid, p_loc integer, p_qty numeric, p_reason text, p_ref_type text DEFAULT NULL::text, p_ref_id text DEFAULT NULL::text, p_unit_cost numeric DEFAULT NULL::numeric, p_batch bigint DEFAULT NULL::bigint, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text, p_reverses bigint DEFAULT NULL::bigint, p_neg text DEFAULT 'full'::text, p_sale uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
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
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;   -- bos82
        select coalesce(staff_id, '-') into who from public.profiles where id = auth.uid();   -- bos82
        if pm = 'required' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'production_negative_reason_needed' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text; end if;   -- bos82
        perform public._stock_exc(p_loc, 'production_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): উৎপাদনে stock-এর চেয়ে বেশি কাঁচামাল নেওয়া হয়েছে, পরিমাণ ' || trim_scale(-q)::text || ', কর্মী ' || coalesce(who, '-') || ', কারণ: ' || coalesce(nullif(btrim(p_note), ''), '-'),
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): production took more than the stock on hand, qty ' || trim_scale(-q)::text || ', staff ' || coalesce(who, '-') || ', reason: ' || coalesce(nullif(btrim(p_note), ''), '-'), p_sale, d, form);   -- bos82
      end if;   -- bos82
    end if;   -- bos82
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
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
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
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
end $function$$r0_0$, null),
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)', 'known', '6499d1b362cae0242a2ad430f4621e7f', null);
-- stock_receive_transfer(uuid,numeric,text,numeric,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$$r0_0$, null),
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)', 'known', 'b8d20930741592905fa5bc7677021df4', null);
-- supplier_pick()
insert into _u_plan (fn, kind, a, b) values
  ('public.supplier_pick()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.supplier_pick()
 RETURNS TABLE(id uuid, name text, type_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.id, s.name, s.type_code from public.suppliers s where public.is_active() and s.active and public._m132_vis('suppliers', s.org_unit_id, s.id::text, false) /* m132 */ order by lower(s.name);
$function$$r0_0$, null),
  ('public.supplier_pick()', 'known', '9a956f85fe391e26dc6ebc1e87ef545e', null);
-- supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)
insert into _u_plan (fn, kind, a, b) values
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.supplier_refund(p_supplier uuid, p_loc integer, p_amount numeric, p_mode text, p_wallet text DEFAULT NULL::text, p_ref text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid)
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
end $function$$r0_0$, null),
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', 'known', '529288c03769fa61a9d7d01e68a73985', null);
-- template_for(text,integer)
insert into _u_plan (fn, kind, a, b) values
  ('public.template_for(text,integer)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.template_for(p_kind text, p_loc integer)
 RETURNS invoice_templates
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select t.* from public.invoice_templates t
  where public.is_active() and t.active and t.is_default and t.kind = p_kind and (t.location_id = p_loc or t.location_id is null) and (t.location_id is null or public._cfgvis133(t.location_id)) /* scope133 */
  order by (t.location_id is null) limit 1;
$function$$r0_0$, null),
  ('public.template_for(text,integer)', 'known', 'dacd83149625cd03edaf46eaa298fa31', null);
-- unit_factor(uuid,text,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.unit_factor(uuid,text,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.unit_factor(p_item uuid, p_from text, p_to text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare f numeric; b text; x numeric; y numeric;
begin
  if p_from is null or p_to is null then return null; end if;
  if p_from = p_to then return 1; end if;
  f := public._unit_hop(p_item, p_from, p_to);
  if f is not null then return f; end if;
  select base_unit into b from public.items where id = p_item and public._m132_own(items.org_unit_id) /* m132b:items */;
  if b is not null and b <> p_from and b <> p_to then
    x := public._unit_hop(p_item, p_from, b); y := public._unit_hop(p_item, b, p_to);
    if x is not null and y is not null then return x * y; end if;
  end if;
  return null;
end $function$$r0_0$, null),
  ('public.unit_factor(uuid,text,text)', 'known', '9a3e3b20fcaf59910f1362aba2445b5a', null);
-- urgent_alerts(timestamp with time zone)
insert into _u_plan (fn, kind, a, b) values
  ('public.urgent_alerts(timestamp with time zone)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.urgent_alerts(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
end $function$$r0_0$, null),
  ('public.urgent_alerts(timestamp with time zone)', 'known', 'f419b0c6d38fce523d63daa9ad675367', null);
-- void_supplier_payment(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.void_supplier_payment(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.void_supplier_payment(p_id bigint, p_note text)
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
end $function$$r0_0$, null),
  ('public.void_supplier_payment(bigint,text)', 'known', 'a7d5acd40df1bcff77e04e28c9dcfc43', null);
-- void_supplier_refund(bigint,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.void_supplier_refund(bigint,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.void_supplier_refund(p_id bigint, p_note text)
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
end $function$$r0_0$, null),
  ('public.void_supplier_refund(bigint,text)', 'known', '97a57b13f10cf99da5f5fc7b3e9581f5', null);
-- wastage_decide(uuid,boolean,text)
insert into _u_plan (fn, kind, a, b) values
  ('public.wastage_decide(uuid,boolean,text)', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.wastage_decide(p_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  select * into it from public.items where id = r.item_id and public._m132_own(items.org_unit_id) /* m132b:items */;
  perform public._stock_exc(r.location_id, 'wastage_rejected', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ নামঞ্জুর — ' || left(btrim(p_note), 100),
    coalesce(it.name_en, it.name_bn) || ': a large wastage write-off was rejected — ' || left(btrim(p_note), 100));
  return jsonb_build_object('status', 'rejected');
end $function$$r0_0$, null),
  ('public.wastage_decide(uuid,boolean,text)', 'known', '1c262451ed469888e610a4e0dad6a74f', null);
-- year_close_list()
insert into _u_plan (fn, kind, a, b) values
  ('public.year_close_list()', 'body', $r0_0$CREATE OR REPLACE FUNCTION public.year_close_list()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if public._org_on123() and not public._acct_all() then raise exception 'not allowed'; end if;   -- scope123: year closes are company-level records (owner only until the per-entity books of Stage C2)
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $function$$r0_0$, null),
  ('public.year_close_list()', 'known', '90e8d1a776fda4d13dc90fe6d13e54be', null);
do $u538$
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
  if miss <> '' then raise exception 'phase538: these functions have an unknown text, nothing was changed. Send this message to the agent:%', miss; end if;
  for f in select distinct fn from _u_plan loop
    select a into rbody from _u_plan where fn = f.fn and kind = 'body';
    if to_regprocedure(f.fn) is null then
      execute rbody; nfix := nfix + 1; continue;
    end if;
    cur := rtrim(pg_get_functiondef(f.fn::regprocedure), E'\n');
    if md5(cur) = md5(rtrim(rbody, E'\n')) then continue; end if;
    insert into public._union_fn_backup (fn, why, def) values (f.fn, 'phase538: merged text of the two lines', cur);
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
  raise notice 'phase538: % function(s) changed', nfix;
end $u538$;
drop table if exists _u_plan;

-- ---------------------------------------------------------------- phase539.sql
-- Phase 539 (UNION-11): the two stale overloads and the audit of the merged functions. Paste-twice safe. Earlier phase files are not edited.
-- Paste AFTER phase538 and after phase 505.
-- 1. inbound_message_receive(9 arguments) and web_order_submit(13 arguments): the advanced line replaced them by the same functions with one more argument (phase 520 / 516 era). A database that was
--    built by pasting the advanced phases and then the early phases again has BOTH, and a call with the old number of arguments is then ambiguous ("function is not unique"). When both exist the
--    old one is saved in public._union_fn_backup and dropped. Nothing happens when only the new one exists (the fresh build).
-- 2. public._union_fn_expected / public._union_audit(): the md5 of the merged text of every function the UNION files 529 to 538 handle, and a read-only report that says for each function whether the
--    database has exactly that text ("merged"), another text ("other": a hand fix or an older paste; look at public._union_fn_backup) or no such function ("missing").

create table if not exists public._union_fn_backup (id bigserial primary key, fn text not null, saved_at timestamptz not null default now(), why text, def text not null);
alter table public._union_fn_backup enable row level security;
revoke all on public._union_fn_backup from anon, authenticated;

do $u539$
declare o record;
begin
  for o in select * from (values
      ('public.inbound_message_receive(text,text,text,text,text,text,timestamp with time zone,text,boolean)', 'public.inbound_message_receive(text,text,text,text,text,text,timestamp with time zone,text,boolean,text)'),
      ('public.web_order_submit(text,uuid,text,text,text,text,jsonb,text,text,text,text,text,boolean)', 'public.web_order_submit(text,uuid,text,text,text,text,jsonb,text,text,text,text,text,boolean,text)')) v(old_sig, new_sig) loop
    if to_regprocedure(o.old_sig) is not null and to_regprocedure(o.new_sig) is not null then
      insert into public._union_fn_backup (fn, why, def) values (o.old_sig, 'phase539: the old overload made a call with fewer arguments ambiguous; the new function (one more argument) stays', pg_get_functiondef(o.old_sig::regprocedure));
      execute 'drop function ' || o.old_sig;
    end if;
  end loop;
end $u539$;

create table if not exists public._union_fn_expected (fn text primary key, md5_text text not null);
alter table public._union_fn_expected enable row level security;
revoke all on public._union_fn_expected from anon, authenticated;
insert into public._union_fn_expected (fn, md5_text) values
  ('public._acct_all()', 'dac0c957a08e06f7713dc781b3c908b7'),
  ('public._acct_docs(date)', 'f5d492c5f91676781bc1c3da0cf804e5'),
  ('public._acct_inv_split72(text[],text,text[],integer)', '3e84d6c8222d39629bd1cd6c2464b1ee'),
  ('public._all_locs()', 'c680e730cf6f6d07deb50ed219fe4321'),
  ('public._backup_tables()', '221b896a31d94f9fbaa979546b869594'),
  ('public._c78_rows(date,date)', '430dd70337995269cafd3b0065393d91'),
  ('public._cogs_lines72(date,date,integer[])', '512e75706693df14492bad04b7c84119'),
  ('public._conv_cost(uuid,integer,numeric,numeric,date,text)', '0e2f0913a5fd66f364e143435ed67834'),
  ('public._cs_push_pools(bigint)', '31370a2ef60c54fa250da2cdcd0cd00c'),
  ('public._cust_bal(uuid)', '474ecdbc4675f9882054aa53c4786df2'),
  ('public._daybook_lines(integer[],integer[],date,date)', '2e1ca2a48dd2bcc20f04b3224604361f'),
  ('public._elp_post_line(entries,integer,text,jsonb)', '4de54a223aea81d283769e20f21611a9'),
  ('public._entries_countseal_guard23()', '13124043708735f9aca3221d5c3bcc83'),
  ('public._inb_insert_message(jsonb)', '98e802fefc2866406963c7953968b928'),
  ('public._inb_pii_cols76()', 'bdfc9e203970d38b73000c3f3eac17fd'),
  ('public._intake_fail(text,integer,text,text,jsonb,text)', 'c7cf0af4032bca5a928ba129b535e7f7'),
  ('public._item_base(uuid)', '03385e3ae53398056384f3e2e8b79cc2'),
  ('public._item_flags_apply(uuid,jsonb)', '1b66a7ea69915f84c95c30213e29a473'),
  ('public._item_link(uuid,text,text,boolean)', '138fdc0a192b8b3555fc9f182f9c9747'),
  ('public._item_master_classify(jsonb)', '4b4809d580465c1e8323e1aeef9375e6'),
  ('public._ledger_item_guard()', 'ccc2e4e8a634cecfa392ae8d450e1fc5'),
  ('public._notif_ok(uuid,text,integer)', '1529700f5f3af190f8113cb1b49cd2e1'),
  ('public._oo_short77(uuid)', '58696c328ef13339c7452af9e385edd8'),
  ('public._p27_pl(date,date,integer[])', '2de38bdd8c6142342aa63665cecd285e'),
  ('public._post_purchase_p13(uuid,jsonb)', '5715f9e11473bdaa94e7f3a53862a54b'),
  ('public._qc_latest60(text,uuid)', '1c3b77156ff3d04c067857d8c7c91438'),
  ('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', '6357271ded442f542a7042143d54e616'),
  ('public._recipe_approved_guard()', '009b0cdf821f84944c466ccff12d089e'),
  ('public._recipe_frozen()', '66d8bd6bc93afc47415a4313b8c3bb6a'),
  ('public._recipe_gate73(uuid)', 'baf4edaf682f17fc8191e535e7b51b71'),
  ('public._recipe_lines_ok(uuid,jsonb)', '243d211ccd6cf4ee53ca5954718940c5'),
  ('public._recipe_need(uuid,numeric,integer)', '2f0e30e6acd8156907f639c5fc99744d'),
  ('public._recipe_set_artisan(uuid,integer,text)', '43f57bf11696ff7175be42b84391dbda'),
  ('public._rv_log(uuid,text,jsonb,text,uuid)', '29079c1b19bd31c60bf5f979a8ff5016'),
  ('public._sale_stock_out()', 'b25b51f222ee84f3206f79b36f983e61'),
  ('public._stock_guard(uuid,integer,text,date)', 'b1d801de9011e70c1bcc4808f5db94d5'),
  ('public._sup_balance(uuid)', 'c522b30b76455348bd0adac5f11304bc'),
  ('public._void_purchase_p13(uuid,text)', '6f5f40d98ada3cc5d7feae353e73ee07'),
  ('public._wastage_post(uuid,integer,numeric,text,text,text,bigint,uuid,uuid,text)', 'c93f68edd847f75f58e4ece7e91418a9'),
  ('public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', '0580b3c0d953201269118ec4be7bc15d'),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', '511d8bebbc82c38c5fc4aa4a43604eac'),
  ('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', '339b89dd83278200bbe8a4991ed0e3b1'),
  ('public.acct_mapping_set(text,bigint)', '5d33b57f91e83ba5eeea1e19749e690d'),
  ('public.acct_opening(jsonb,boolean,text,uuid,boolean)', 'e54a5a3f1e6676cf3af6ed962809be40'),
  ('public.acct_post_pending(boolean,integer)', 'a92316ebd9ba5a0c3a536e5d358bdc5d'),
  ('public.acct_status()', '94ea46ad356974d59f7fafe1550154eb'),
  ('public.artisan_list(boolean)', '995e3347a4227e59bd603c1474f2e722'),
  ('public.assistant_health()', '54cf093d5efb4a1b4cf9aad5d0585478'),
  ('public.bank_recon_candidates(bigint,integer)', 'ce00427ed41cd0a548d800a0cb075d34'),
  ('public.bank_recon_lines(bigint,text,integer)', '6ec07311768687877f3366d7c89d75d5'),
  ('public.bank_recon_match(bigint,bigint,integer,text)', '6cae75b638fbfd9297b9407d3fee2180'),
  ('public.bank_recon_match_many(jsonb,boolean)', '66029b6273540a5008df2af5e20cfa9c'),
  ('public.bank_recon_report(bigint,date,date)', '933ccaa5e45f62db9f8ea35389e5bdb2'),
  ('public.bank_recon_suggest(bigint,date,date,integer)', 'f571419688a80398abe1585da61e4c04'),
  ('public.bank_recon_unmatch(bigint,text)', 'a223fd11d9c63ab628ec501090823dc8'),
  ('public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'e209e7693b546922b5d0a49c3311893e'),
  ('public.biz_items(date,date,integer)', '2cbdbc98b5281fe21ec3749c68526345'),
  ('public.blind_active(text,integer)', '452a1903c5d052b9e6a3ab439955350c'),
  ('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', '2e1526e444b15dcb9e60226ca9bb6ba9'),
  ('public.control_counts()', '65fcd091672c0cf25861ca6235931531'),
  ('public.cost_attrib_main_set(integer,date,text,uuid)', 'a55f79b3764dfdc8f3e1570b6635dfc8'),
  ('public.cost_rule_approve(bigint,text)', 'c980dbff1ac1119905ac5005c7a333ea'),
  ('public.cost_source_set_active(bigint,boolean,text)', '56d46508962a79db3e843ad5131fc164'),
  ('public.count_lines_seal(uuid)', '4defda3fb7b923f8a65411e5ed0e9169'),
  ('public.count_unsubmitted_scan()', '888fc199883188956d17fa7a8e54b3bb'),
  ('public.customer_advances()', '8341abb1177673474349c7d33ea1f114'),
  ('public.customer_balance(uuid)', 'e810728f6785c5637457086a75399a1f'),
  ('public.customer_directory(integer)', '6cac1fd4f9224b8df97f7e7c4a0b3eed'),
  ('public.customer_dues()', '1b0393afb8e38162d7e4be07638f6cda'),
  ('public.customer_ledger(uuid)', '893ac2149cd2618bb88a8a4451636384'),
  ('public.customer_points_adjust(uuid,integer,text,uuid)', 'bf73d622eda866a365a377fe996a35cd'),
  ('public.customer_points_redeem(uuid,integer,text,uuid,boolean)', '2474bda8979ab4820ef3fff6340361dc'),
  ('public.customer_pos_info(text)', '49abbb09a2a9e7649a787bb5d3141457'),
  ('public.customer_profile(uuid)', 'd56376e61e16818c6c57df7e7c14e007'),
  ('public.customer_save(uuid,jsonb,uuid)', '8c3f7014ec5d1529633feedae59b4efe'),
  ('public.customer_set_tier(uuid,bigint,text,boolean)', '8e7b8e2eff25783bab3ea99b63764f1a'),
  ('public.decide_emergency(bigint,boolean,text)', '6e1c79456e5eeec3451ac81d8b85e529'),
  ('public.dup_suspects(date,date)', '862aa450026a3b9c081621d2676be9f4'),
  ('public.fa_register(date)', 'b0ccb663d77c54bfa4a3cbd7e29bc1aa'),
  ('public.fa_schedule(uuid)', '6c761fdbcf6baa997d0bc769a906b980'),
  ('public.gift_claim(uuid,uuid,bigint,text,uuid)', '93eb8afe68c359f80725c5f7559c7e9b'),
  ('public.gift_issue(uuid,text,text,numeric,date,text,uuid)', '8a7d0fa7116ea4c3eaface0c1fca691c'),
  ('public.gifts_due(uuid)', '8bd7faf50de77f1edc8a65258ea64068'),
  ('public.has_grant(text,integer)', '4ced154bbea4186e39d92600376792ad'),
  ('public.inbox_board(integer)', 'be26968d5c65ac1551bb35b97f25a8a7'),
  ('public.inbox_get(bigint)', 'de5af63bed889360700547b65ba3fa31'),
  ('public.inbox_list(integer,text,integer)', 'f7e785151edaab76b397e839555df087'),
  ('public.intake_failures_list(text,integer)', '29f5a7fe24a900eb85e2167e9e840d3c'),
  ('public.inventory_vs_gl(date,integer)', 'f56c355e63a8259ddb7f8f887c07bdc9'),
  ('public.item_apply(uuid,jsonb,text)', 'f3803082621c026b84c5bbde997efb01'),
  ('public.item_dup_check(text,text,uuid)', '5a0e942c22ad0b60da55e475dd1fb20f'),
  ('public.item_map_accept_confident(boolean)', '8a1130586d072f27319925af52592836'),
  ('public.item_map_decide2(uuid,text,text,text,boolean)', 'c29519db04ffc5b179071b767da3d844'),
  ('public.item_mapping_decide(uuid,text,text,text,boolean)', '46dd393d2319606d3fbf36b4b3dabe62'),
  ('public.item_master_import_apply(jsonb,text,integer)', '8e67b4e63826a49c5d845e24d41c6827'),
  ('public.item_new(jsonb,text)', '3781326f42ead5bfc5b24db564fcb852'),
  ('public.items_with_cost()', 'e78fe39037f3b8e4426a4f073bb41e32'),
  ('public.location_save(integer,jsonb)', '8931f5cc1a32e93a7fb92bb51f861223'),
  ('public.lock_check(date)', 'fb77f334456aef9946c3c23a47feac2f'),
  ('public.login_failed(text)', '9268eff5c96e25aa72e62dba59ad0e04'),
  ('public.loyalty_award(uuid)', '183ebd12e0644d5bbc581e2c521ec9d0'),
  ('public.notify_cancel(bigint)', 'e4edc805d33e97411bcd70bf75a02ee8'),
  ('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)', 'c7afcdaabdeb2823963a775bef9b57e5'),
  ('public.notify_optin_set(uuid,text,boolean,text,text)', '9d845ac6ca474718f81e746dcff85f8a'),
  ('public.notify_outbox_summary()', '584ae0ed362d6af80530a7ffb32f86e1'),
  ('public.online_order_get(uuid)', '50e4a20313b646d211ba24d35fca213a'),
  ('public.online_order_save(uuid,uuid,integer,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)', 'de7dd3735dfa8e87b2c909d74a454f90'),
  ('public.online_orders_list(integer,text,date,date,integer)', 'eb2b580648192da6c4e12cc24f79af77'),
  ('public.packaging_set(uuid,uuid,numeric,text,boolean,text)', '4689ef04634ad8a460471cee6fc42624'),
  ('public.partner_calculate(bigint,date,date,jsonb)', '745a4e87b710715dbafc13b96b1e581f'),
  ('public.partner_settlement_save(bigint,date,date,jsonb,text,uuid)', '243851fc7e76e8404f30670b7a38b1e3'),
  ('public.path_cfg(text,integer)', '25f179987453530bc695ffe78383fb60'),
  ('public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'b09944fc5f8f4f804379da0df53ebf1f'),
  ('public.payment_intent_link(bigint,bigint)', '81883d1deee9b5be05269270c4e6df3e'),
  ('public.pool_set(integer,date,text,numeric,text,boolean,text,uuid)', '5da66059139c270017608838f238c98d'),
  ('public.production_can_make(integer)', '2a05ed1890c20734a0a40f8bea2d9678'),
  ('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', '14c2393161cd72dc97eb7c2c6cb82500'),
  ('public.production_preview(integer,uuid,numeric)', 'd938798d15ee1097c0443a42aa4a6a8f'),
  ('public.production_run_costs(integer,date,date)', 'a01638dde8c694bd337e04c22088b64a'),
  ('public.production_void(uuid,text)', 'ae5735b19c16b8bb8698bb8f01d97938'),
  ('public.profit_source_check(date,date,integer)', 'ba3a80e333a9823642b16f8d0aaf3504'),
  ('public.purchase_get(uuid)', 'fe8ed542e411ebe02f06ed95b600a8dc'),
  ('public.recipe_approve(uuid,text)', '2bd35a38670bf8959741789c08579efb'),
  ('public.recipe_book(integer,boolean,integer)', '6d32e407143c06f28cee557153f28018'),
  ('public.recipe_copy(uuid,uuid,boolean,uuid)', '65cab5275bffdfa712a6f5fede427b18'),
  ('public.recipe_cost(uuid,integer)', 'e26acf5f5dc7e7f7a79bd5f1d7f7c6e0'),
  ('public.recipe_cost_component_set(uuid,text,text,numeric,numeric,text,text,uuid)', 'ceca56b9c172b2d10dcb0c7a6d7606da'),
  ('public.recipe_save(uuid,uuid,numeric,text,text,jsonb,uuid,boolean)', '5ebdf746b280e67daf9e8966e29ab567'),
  ('public.recipe_steps_save(uuid,jsonb,uuid)', 'e72c2a759edad1f24645e4112f4f49f3'),
  ('public.recipe_yield_suggestion(uuid)', 'f8ee9e811cc28a19f09fc30b84a3e44e'),
  ('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', '660e61d55ce3ae533daa7229977b77b9'),
  ('public.rollout_mode(text,integer)', '9a66d23e0b28b04207191eafb49891e2'),
  ('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', '3e7e8752359360b7b087885c1457f9fc'),
  ('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', '133c835685ca7f0957333cb569036fa3'),
  ('public.sales_channel_save(integer,text,text,text,text,integer,text,text,boolean)', '885671997cc553466d622da350b7ae94'),
  ('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', '0e5e20a398daccd1e79445a821929761'),
  ('public.save_supplier(uuid,jsonb)', '12fe6a2cfb3b0813749200025709147e'),
  ('public.sheet_sync_all()', '2cb0b11f011ec5f91ed24784f3dc6e2f'),
  ('public.shelf_life_for(uuid,date)', '1e62264b116618ebc1802403cb61bdcf'),
  ('public.stock_blind_active(text,integer)', '51ff614657ad74411e4d282dc3c088eb'),
  ('public.stock_count_adjust(uuid,integer,numeric,text,text,uuid)', 'ddf597953fbb5114e13d51ffd7a97081'),
  ('public.stock_opening(uuid,integer,numeric,numeric,text,text,uuid)', '8e56dafaca14a597ae2229366a2c45f9'),
  ('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)', 'eba13926cba30b077ad8fb9186eb006f'),
  ('public.stock_receive_transfer(uuid,numeric,text)', '08738479abecae77129437d16dde2ae4'),
  ('public.stock_receive_transfer(uuid,numeric,text,numeric,text)', 'a84da692ccf9b3d12c83f7dbc398c748'),
  ('public.stock_reconcile(boolean)', 'dca972cf87c25d3c2e681a649b176c7f'),
  ('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'e575c1bf5735e023ba468646fe9ac37a'),
  ('public.supplier_pick()', '641b8815a18df23180206f4c6f75b48d'),
  ('public.supplier_refund(uuid,integer,numeric,text,text,text,text,text,uuid)', 'cb871ea3419fb9604af6bb1c3c9abfb5'),
  ('public.template_for(text,integer)', '4a79d1e8291fde01b5b87b6e65c0de3d'),
  ('public.unit_factor(uuid,text,text)', '19dc88ca5fc6a25f2294a83d895dc00a'),
  ('public.urgent_alerts(timestamp with time zone)', '2a28026ebd8fbf430796bd69fb3ef062'),
  ('public.void_supplier_payment(bigint,text)', '80c4d63a1cb686838be8bbf78ad8b2fb'),
  ('public.void_supplier_refund(bigint,text)', '6c03022e334dd5c67d45cffa192371e9'),
  ('public.wastage_decide(uuid,boolean,text)', 'bed0dd5585a5b6486b2a70d55a7abb47'),
  ('public.year_close_list()', 'fa84a2d5c54e899b6c4b2db46542312f')
on conflict (fn) do update set md5_text = excluded.md5_text;

create or replace function public._union_audit() returns table (fn text, state text, expected_md5 text, actual_md5 text)
language sql stable security definer set search_path = public as $$
  select e.fn,
         case when to_regprocedure(e.fn) is null then 'missing'
              when md5(rtrim(pg_get_functiondef(to_regprocedure(e.fn)), E'\n')) = e.md5_text then 'merged' else 'other' end,
         e.md5_text,
         case when to_regprocedure(e.fn) is null then null else md5(rtrim(pg_get_functiondef(to_regprocedure(e.fn)), E'\n')) end
    from public._union_fn_expected e order by 2 desc, 1;
$$;
revoke all on function public._union_audit() from public, anon, authenticated;

-- ============================================================================
-- End of DELTA part 2 of 2.
-- Now run this check (it only reads):
-- select * from public._i2_state() where not present;   -- must return no rows
-- select fn, saved_at, why from public._union_fn_backup order by id;   -- the bodies that were saved before a change
