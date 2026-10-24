-- ============================================================================
-- FRESH part 19 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase491 phase492 phase493 phase494 phase495 phase496 phase497 phase498 phase499 phase501 phase502 phase503 phase504 phase505 phase530 phase531 phase532 phase533 phase534
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase491.sql
-- ============================================================
-- Phase 491 - XB package part 1: bKash / Nagad / Rocket payment capture and reconciliation.
-- Run AFTER phase 478 (needs phase61 online_orders, phase83 d_wallets, phase6 sales). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * pay_captures          one row per mobile payment the counter writes down: provider, Trx-ID, sender number, amount, time, wallet,
--                           the order / sale / advance it is for, the amount expected, the flag (ok / overpay / underpay / no_target).
--                           A Trx-ID is unique (a duplicate is refused). Verification: pending -> verified | rejected (approver holds
--                           grant pay_verify or is the owner; never the person who captured it). Append-only (decision fields only).
--   * xb_pay_capture        write a capture (rule pay_capture_on OFF = refused). Nothing is posted to the books: a capture is evidence.
--   * xb_pay_capture_decide approve / reject; a flagged capture needs a note.
--   * xb_pay_capture_screenshot  attach a payment screenshot (private bucket 'payproof', path pay/<place>/<file>.jpg), once.
--   * pay_statement_lines   wallet statement lines imported from CSV / paste (append-only, deduplicated on wallet + Trx-ID + direction).
--   * xb_pay_statement_import   owner or a pay_verify holder (place-less grant) imports a statement; duplicates are counted, not written twice.
--   * xb_pay_tieout         daily tie-out per wallet: captured vs statement, with the lists of what does not match.
--   * Rules (OFF / blank): pay_capture_on (OFF), pay_capture_tol (blank = the amount must match exactly; no tolerance is invented).
-- No merchant API adapter is built: statement and capture records are the only inputs; no outbound call exists anywhere.
-- Paper form code for any printed version: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.d_wallets') is null or to_regclass('public.sales') is null
     or to_regprocedure('public.c2_orders_features()') is null then
    raise exception 'phase491 needs phase61, phase83, phase6 and phase445 pasted first';
  end if;
end $guard$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('pay_verify', 'pos', 90, 'মোবাইল পেমেন্ট যাচাই করা', 'Mobile payment verify করা', 'Verify mobile payments (bKash / Nagad / Rocket)', 'once', null)
on conflict (grant_code) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pay_capture_on', 'pos', 'switch', 'false', null, null, null, null, 'মোবাইল পেমেন্ট (Trx-ID) লেখা চালু', 'Mobile payment (Trx-ID) capture চালু', 'Mobile payment capture is on',
  'চালু হলে বিকাশ/নগদ/রকেটের Trx-ID, নম্বর, টাকা লেখা যাবে; একই Trx-ID দুবার ঢোকে না।', 'When on, bKash / Nagad / Rocket Trx-ID, sender, amount and time can be written; a Trx-ID is never accepted twice.', 540),
 ('pay_capture_tol', 'pos', 'number', null, 'taka', null, 0, 1000000, 'মেলানোর সহনশীলতা (টাকা)', 'Match tolerance (taka)', 'Amount match tolerance (taka)',
  'ফাঁকা = টাকা হুবহু মিলতে হবে। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = the amount must match exactly. No number is assumed.', 541)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.pay_captures (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  provider text not null check (provider in ('bkash', 'nagad', 'rocket', 'other')),
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  sender_no text check (sender_no is null or char_length(sender_no) between 6 and 20),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  paid_at timestamptz not null,
  location_id int not null references public.locations(id),
  target text not null check (target in ('order', 'sale', 'advance', 'none')),
  online_order_id uuid references public.online_orders(id),
  sale_id uuid references public.sales(id),
  expected numeric,
  diff numeric,
  flag text not null check (flag in ('ok', 'overpay', 'underpay', 'no_target')),
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected', 'void')),
  source text not null default 'manual' check (source in ('manual', 'sms_paste')),
  screenshot_path text check (screenshot_path is null or char_length(screenshot_path) <= 200),
  note text check (note is null or char_length(note) <= 300),
  captured_by uuid, captured_staff text, captured_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz, decide_note text check (decide_note is null or char_length(decide_note) <= 300),
  check ((target = 'order') = (online_order_id is not null) or target = 'advance'), check ((target = 'sale') = (sale_id is not null))
);
create unique index if not exists pay_captures_trx_live on public.pay_captures (trx_id) where status <> 'void';
create index if not exists pay_captures_day on public.pay_captures (location_id, paid_at);

create table if not exists public.pay_statement_lines (
  id bigint generated always as identity primary key,
  wallet_code text not null references public.d_wallets(code),
  trx_id text not null check (trx_id ~ '^[A-Z0-9]{6,20}$'),
  direction text not null check (direction in ('in', 'out')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  stmt_at timestamptz not null,
  counterpart text check (counterpart is null or char_length(counterpart) <= 40),
  import_batch uuid not null,
  imported_by uuid, imported_at timestamptz not null default now(),
  unique (wallet_code, trx_id, direction)
);

-- captures: only the decision fields and the screenshot path move; nothing is deleted
create or replace function public._xb540_pay_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a payment capture is never deleted, void it through the decision'; end if;
  if (to_jsonb(new) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path')
     is distinct from (to_jsonb(old) - 'status' - 'decided_by' - 'decided_at' - 'decide_note' - 'screenshot_path') then
    raise exception 'append_only: a payment capture changes only its decision and its screenshot';
  end if;
  if old.screenshot_path is not null and new.screenshot_path is distinct from old.screenshot_path then raise exception 'already_attached'; end if;
  if old.status in ('verified', 'rejected', 'void') and new.status is distinct from old.status then raise exception 'decided: a decided capture cannot change'; end if;
  return new;
end $$;
drop trigger if exists pay_captures_ro on public.pay_captures;
create trigger pay_captures_ro before update or delete on public.pay_captures for each row execute function public._xb540_pay_ro();
drop trigger if exists audit_pay_captures on public.pay_captures;
create trigger audit_pay_captures after insert or update on public.pay_captures for each row execute function public.log_change('id');

create or replace function public._xb540_lines_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: a statement line is never changed or deleted'; end $$;
drop trigger if exists pay_statement_lines_ro on public.pay_statement_lines;
create trigger pay_statement_lines_ro before update or delete on public.pay_statement_lines for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_pay_statement_lines on public.pay_statement_lines;
create trigger audit_pay_statement_lines after insert on public.pay_statement_lines for each row execute function public.log_change('id');

-- ---------- helpers ----------
create or replace function public._xb540_verifier(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or public.has_grant('pay_verify', p_loc);
$$;
create or replace function public._xb540_verifier_any() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'pay_verify' and g.location_id is null);
$$;
create or replace function public._xb540_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_capture_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- ---------- capture ----------
create or replace function public.xb_pay_capture(p_client uuid, p_provider text, p_trx text, p_sender text, p_amount numeric, p_paid_at timestamptz,
  p_wallet text, p_loc int, p_target text, p_order uuid default null, p_sale uuid default null, p_source text default 'manual', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare trx text := upper(btrim(coalesce(p_trx, ''))); o public.online_orders; s public.sales; ex numeric; df numeric; fl text; tol numeric := coalesce(public.rule_num('pay_capture_tol'), 0);
        rec public.pay_captures; wok boolean; id_ bigint; ol uuid; sl uuid; sndr text;
begin
  if p_client is not null then
    select * into rec from public.pay_captures where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'status', rec.status, 'flag', rec.flag, 'dup', true); end if;
  end if;
  perform public._xb540_gate(p_loc);
  if p_provider not in ('bkash', 'nagad', 'rocket', 'other') then raise exception 'bad_provider'; end if;
  if trx !~ '^[A-Z0-9]{6,20}$' then raise exception 'bad_trx_id'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_paid_at is null or p_paid_at > now() + interval '10 minutes' then raise exception 'bad_time'; end if;
  if p_source not in ('manual', 'sms_paste') then raise exception 'bad_source'; end if;
  if p_target not in ('order', 'sale', 'advance', 'none') then raise exception 'bad_target'; end if;
  select exists (select 1 from public.d_wallets w where w.code = p_wallet and w.active) into wok;
  if not wok then raise exception 'bad_wallet'; end if;
  sndr := nullif(btrim(coalesce(p_sender, '')), '');
  if sndr is not null then sndr := public.norm_mobile(sndr); if sndr is null or char_length(sndr) < 6 then raise exception 'bad_sender'; end if; end if;
  if exists (select 1 from public.pay_captures where trx_id = trx and status <> 'void') then raise exception 'duplicate_trx: this Trx-ID is already written'; end if;
  ex := null;
  if p_target = 'order' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
    ex := o.subtotal - o.discount + o.delivery_charge - o.advance; ol := o.id;
  elsif p_target = 'sale' then
    select * into s from public.sales where id = p_sale;
    if not found then raise exception 'not_found'; end if;
    if s.location_id <> p_loc then raise exception 'other_location'; end if;
    ex := s.due_amount; sl := s.id;
  elsif p_target = 'advance' then
    select * into o from public.online_orders where id = p_order;
    if not found then raise exception 'not_found'; end if;
    if o.location_id <> p_loc then raise exception 'other_location'; end if;
    ol := o.id;
    ex := case when o.advance > 0 then o.advance end;
  end if;
  if ex is null then fl := 'no_target'; df := null;
  else
    df := round(p_amount - ex, 2);
    fl := case when abs(df) <= tol then 'ok' when df > 0 then 'overpay' else 'underpay' end;
  end if;
  insert into public.pay_captures (client_id, provider, wallet_code, trx_id, sender_no, amount, paid_at, location_id, target, online_order_id, sale_id, expected, diff, flag, source, note, captured_by, captured_staff)
    values (p_client, p_provider, p_wallet, trx, sndr, round(p_amount, 2), p_paid_at, p_loc, p_target, ol, sl, ex, df, fl, p_source, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'status', 'pending', 'flag', fl, 'expected', ex, 'diff', df, 'note_needed_to_verify', fl <> 'ok');
exception when unique_violation then
  raise exception 'duplicate_trx: this Trx-ID is already written';
end $$;

-- ---------- verify (nobody approves the capture they wrote; a flagged or rejected one needs a note) ----------
create or replace function public.xb_pay_capture_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public._xb540_verifier(rec.location_id) then raise exception 'not allowed'; end if;
  if p_approve is null then raise exception 'bad_input'; end if;
  if rec.status <> 'pending' then raise exception 'already_decided'; end if;
  if rec.captured_by = auth.uid() then raise exception 'own_capture: nobody approves the capture they wrote'; end if;
  if (rec.flag <> 'ok' or not p_approve) and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.pay_captures set status = case when p_approve then 'verified' else 'rejected' end, decided_by = auth.uid(), decided_at = now(),
    decide_note = left(nullif(btrim(p_note), ''), 300) where id = rec.id;
  return jsonb_build_object('id', rec.id, 'status', case when p_approve then 'verified' else 'rejected' end, 'flag', rec.flag);
end $$;

create or replace function public.xb_pay_capture_screenshot(p_id bigint, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rec public.pay_captures;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into rec from public.pay_captures where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(rec.location_id) or not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if rec.screenshot_path is not null then raise exception 'already_attached'; end if;
  if p_path is null or p_path !~ ('^pay/' || rec.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.pay_captures set screenshot_path = p_path where id = rec.id;
  return jsonb_build_object('id', rec.id, 'screenshot_path', p_path);
end $$;

create or replace function public.xb_pay_captures_list(p_loc int default null, p_status text default null, p_day date default null, p_limit int default 200) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(z) order by z.paid_at desc), '[]'::jsonb) from (
    select c.id, c.provider, c.wallet_code, c.trx_id, c.sender_no, c.amount, c.paid_at, c.location_id, c.target, c.online_order_id, c.sale_id, c.expected, c.diff, c.flag, c.status,
           c.screenshot_path is not null as has_screenshot, c.captured_staff, c.decided_at, c.decide_note
      from public.pay_captures c
     where public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(c.location_id)
       and (p_loc is null or c.location_id = p_loc) and (p_status is null or c.status = p_status)
       and (p_day is null or (c.paid_at at time zone 'Asia/Dhaka')::date = p_day)
     order by c.paid_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z;
$$;

-- ---------- statement import and tie-out ----------
create or replace function public.xb_pay_statement_import(p_wallet text, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare batch uuid := gen_random_uuid(); ln jsonb; ins int := 0; dup int := 0; bad int := 0; n int;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.d_wallets where code = p_wallet and active) then raise exception 'bad_wallet'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 2000 then raise exception 'bad_lines'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    if upper(btrim(coalesce(ln->>'trx_id', ''))) !~ '^[A-Z0-9]{6,20}$' or coalesce(ln->>'direction', '') not in ('in', 'out')
       or (ln->>'amount') is null or (ln->>'amount')::numeric <= 0 or (ln->>'at') is null then bad := bad + 1; continue; end if;
    insert into public.pay_statement_lines (wallet_code, trx_id, direction, amount, stmt_at, counterpart, import_batch, imported_by)
      values (p_wallet, upper(btrim(ln->>'trx_id')), ln->>'direction', round((ln->>'amount')::numeric, 2), (ln->>'at')::timestamptz,
              left(nullif(btrim(ln->>'counterpart'), ''), 40), batch, auth.uid())
      on conflict (wallet_code, trx_id, direction) do nothing;
    get diagnostics n = row_count;
    if n = 1 then ins := ins + 1; else dup := dup + 1; end if;
  end loop;
  return jsonb_build_object('wallet', p_wallet, 'batch', batch, 'inserted', ins, 'already_there', dup, 'bad_rows', bad);
end $$;

create or replace function public.xb_pay_tieout(p_date date, p_wallet text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); out_ jsonb := '[]';
        w record; cap numeric; cap_ver numeric; stm_in numeric; stm_out numeric; l_stmt jsonb; l_erp jsonb; l_mis jsonb; nmis int; nstm int; nerp int; has_stm boolean;
begin
  if not public.is_active() or not public._xb540_verifier_any() then raise exception 'not allowed'; end if;
  for w in select code, name_en from public.d_wallets where active and (p_wallet is null or code = p_wallet) order by sort, id loop
    select coalesce(sum(amount), 0), coalesce(sum(amount) filter (where status = 'verified'), 0) into cap, cap_ver
      from public.pay_captures where wallet_code = w.code and status in ('pending', 'verified') and (paid_at at time zone 'Asia/Dhaka')::date = d;
    select coalesce(sum(amount) filter (where direction = 'in'), 0), coalesce(sum(amount) filter (where direction = 'out'), 0) into stm_in, stm_out
      from public.pay_statement_lines where wallet_code = w.code and (stmt_at at time zone 'Asia/Dhaka')::date = d;
    has_stm := exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and (s.stmt_at at time zone 'Asia/Dhaka')::date = d);
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', s.trx_id, 'amount', s.amount) order by s.trx_id), '[]'::jsonb), count(*)
      into l_stmt, nstm from public.pay_statement_lines s
     where s.wallet_code = w.code and s.direction = 'in' and (s.stmt_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_captures c where c.trx_id = s.trx_id and c.status <> 'void');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'amount', c.amount, 'status', c.status) order by c.trx_id), '[]'::jsonb), count(*)
      into l_erp, nerp from public.pay_captures c
     where c.wallet_code = w.code and c.status = 'verified' and (c.paid_at at time zone 'Asia/Dhaka')::date = d
       and not exists (select 1 from public.pay_statement_lines s where s.wallet_code = w.code and s.trx_id = c.trx_id and s.direction = 'in');
    select coalesce(jsonb_agg(jsonb_build_object('trx_id', c.trx_id, 'captured', c.amount, 'statement', s.amount) order by c.trx_id), '[]'::jsonb), count(*)
      into l_mis, nmis from public.pay_captures c join public.pay_statement_lines s on s.wallet_code = c.wallet_code and s.trx_id = c.trx_id and s.direction = 'in'
     where c.wallet_code = w.code and c.status in ('pending', 'verified') and c.amount <> s.amount;
    out_ := out_ || jsonb_build_object('wallet', w.code, 'name_en', w.name_en, 'captured_total', cap, 'captured_verified', cap_ver,
      'statement_in', stm_in, 'statement_out', stm_out, 'statement_lines_without_capture', nstm, 'captured_not_on_statement', nerp,
      'amount_mismatch', nmis, 'statement_only', l_stmt, 'captured_only', l_erp, 'mismatch', l_mis, 'statement_imported', has_stm,
      'status', case when not has_stm then 'no_statement_imported'
                     when nstm = 0 and nerp = 0 and nmis = 0 then 'matched' else 'difference' end);
  end loop;
  return jsonb_build_object('date', d, 'wallets', out_, 'notes', jsonb_build_array('a_capture_is_evidence_not_a_posting', 'blank_tolerance_means_exact_match'));
end $$;

-- ---------- privileges and RLS ----------
alter table public.pay_captures enable row level security;
alter table public.pay_statement_lines enable row level security;
revoke all on public.pay_captures, public.pay_statement_lines from public, anon, authenticated;
grant select on public.pay_captures to authenticated;
grant select on public.pay_statement_lines to authenticated;
drop policy if exists pay_captures_sel on public.pay_captures;
create policy pay_captures_sel on public.pay_captures for select to authenticated
  using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists pay_statement_lines_sel on public.pay_statement_lines;
create policy pay_statement_lines_sel on public.pay_statement_lines for select to authenticated using (public.is_owner() or public._xb540_verifier_any());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('payproof', 'payproof', false, 3145728, array['image/jpeg']) on conflict (id) do nothing;
drop policy if exists xb540_payproof_ins on storage.objects;
create policy xb540_payproof_ins on storage.objects for insert to authenticated
  with check (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and public.can_do('POS', 'enter') and public.can_loc(split_part(name, '/', 2)::int));
drop policy if exists xb540_payproof_read on storage.objects;
create policy xb540_payproof_read on storage.objects for select to authenticated
  using (bucket_id = 'payproof' and split_part(name, '/', 1) = 'pay' and public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(split_part(name, '/', 2)::int));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_pay\_%' or p.proname like '\_xb540\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_pay\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase492.sql
-- ============================================================
-- Phase 492 - XB package part 2: custom-cake workflow on top of an app order.
-- Run AFTER phase 491 (and phase 445 / 448 for the order spec and cancel). New file only; no old phase or function is edited.
-- Paste twice = no error, no second row.
--
--   * cake_price_rules      owner-editable price table: base per kg, flavour extras and design extras (per kg or flat). Empty table = no quote
--                           (nothing is invented). Written only through xb_cake_price_rule_save (owner).
--   * xb_cake_quote         quote breakdown for a weight, flavour and design list (no write).
--   * cake_jobs             one cake job per app order: weight, flavour, layers, message, design notes, reference photos (paths),
--                           eggless / halal / allergen flags, due date and slot, quote lines, total, advance required, balance, state.
--   * cake_job_events       append-only trail of every state move: from, to, who (login and staff id), when, note.
--   * State chain: quoted -> confirmed (advance in the order) -> slip (production slip) -> baked -> decorated -> ready -> delivered.
--                  cancelled from any state before delivered; cancelling calls the existing c2_order_cancel (refund rules unchanged).
--                  delivered needs the app order to be delivered already (the money path stays the order's own path).
--   * Rules (OFF / blank): cake_flow_on (OFF), cake_capacity_day (blank = confirming and quoting are refused: no cap is invented),
--                  cake_lead_days (blank = refused), cake_photo_required (OFF: photo of the finished cake before delivery).
--   * xb_cake_create / xb_cake_confirm / xb_cake_move / xb_cake_photo / xb_cake_cancel: writers.
--   * xb_cake_due           production and decoration sheet for one day (printable in the web; no paper form code is invented).
--   * xb_cake_notify        customer confirmation: returns a wa.me text (the owner's phone taps send) and, when SMS is on and the customer
--                           has opted in and is not on do-not-contact, enqueues an SMS through notify_enqueue. Nothing is sent by this phase.
-- Birthday link to CRM and per-slot capacity: NOT built (see report).
-- Paper form code for a printed cake sheet: to be given by owner (none invented).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.xb_pay_capture(uuid,text,text,text,numeric,timestamptz,text,int,text,uuid,uuid,text,text)') is null
     or to_regprocedure('public.c2_order_cancel(uuid,text,text,text)') is null or to_regprocedure('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)') is null
     or to_regprocedure('public.c2_order_spec_save(uuid,jsonb,text)') is null then
    raise exception 'phase492 needs phase491, phase445-448 and phase62 pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cake_flow_on', 'pos', 'switch', 'false', null, null, null, null, 'কাস্টম কেক ওয়ার্কফ্লো চালু', 'Custom cake workflow চালু', 'Custom cake workflow is on',
  'চালু হলে কেকের কোট, অ্যাডভান্স, উৎপাদন স্লিপ, ডেকোরেশন ও ডেলিভারি ধাপ লেখা যাবে।', 'When on, cake quote, advance, production slip, decoration and delivery steps can be recorded.', 542),
 ('cake_capacity_day', 'pos', 'number', null, 'cakes', null, 1, 1000, 'একদিনে সর্বোচ্চ কেক', 'Cake per day cap', 'Maximum cakes per day',
  'ফাঁকা থাকলে নতুন কেক কোট/নিশ্চিত করা যায় না। কোনো সংখ্যা ধরে নেওয়া হয় না।', 'Blank = cakes cannot be quoted or confirmed. No number is assumed.', 543),
 ('cake_lead_days', 'pos', 'number', null, 'days', null, 0, 90, 'কেক অর্ডারের আগাম দিন', 'Cake lead time (days)', 'Cake lead time (days)',
  'ফাঁকা থাকলে কেক নেওয়া যায় না। কত দিন আগে অর্ডার দিতে হবে তা মালিক ঠিক করেন।', 'Blank = cakes cannot be taken. The owner sets how many days ahead.', 544),
 ('cake_photo_required', 'pos', 'switch', 'false', null, null, null, null, 'ডেলিভারির আগে কেকের ছবি লাগবে', 'Cake photo before delivery', 'Photo of the finished cake is required before delivery',
  'চালু থাকলে তৈরি কেকের ছবি না থাকলে ডেলিভারি হবে না।', 'On = no delivery step without a photo of the finished cake.', 545)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cake_price_manage', 'pos', 91, 'কেকের দামের তালিকা বদল', 'Cake price list বদল', 'Change the cake price list', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- price rules ----------
create table if not exists public.cake_price_rules (
  id bigint generated always as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,40}$'),
  group_kind text not null check (group_kind in ('base', 'flavour', 'design')),
  rate_kind text not null check (rate_kind in ('per_kg', 'flat')),
  label_bn text not null check (char_length(btrim(label_bn)) between 1 and 80),
  label_en text not null check (char_length(btrim(label_en)) between 1 and 80),
  amount numeric not null check (amount >= 0 and amount <= 1000000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create or replace function public._xb541_no_delete() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: retire the row (active = false)'; end $$;
drop trigger if exists cake_price_rules_nodel on public.cake_price_rules;
create trigger cake_price_rules_nodel before delete on public.cake_price_rules for each row execute function public._xb541_no_delete();
drop trigger if exists audit_cake_price_rules on public.cake_price_rules;
create trigger audit_cake_price_rules after insert or update on public.cake_price_rules for each row execute function public.log_change('id');

create or replace function public.xb_cake_price_rule_save(p_code text, p_group text, p_rate text, p_label_bn text, p_label_en text, p_amount numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('cake_price_manage', null)) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_group not in ('base', 'flavour', 'design') or p_rate not in ('per_kg', 'flat')
     or p_amount is null or p_amount < 0 or p_amount > 1000000000 or p_active is null then raise exception 'bad_input'; end if;
  if p_group = 'base' and p_rate <> 'per_kg' then raise exception 'bad_input: the base price is per kg'; end if;
  insert into public.cake_price_rules (code, group_kind, rate_kind, label_bn, label_en, amount, active, updated_by)
    values (p_code, p_group, p_rate, left(btrim(coalesce(p_label_bn, '')), 80), left(btrim(coalesce(p_label_en, '')), 80), p_amount, p_active, auth.uid())
    on conflict (code) do update set group_kind = excluded.group_kind, rate_kind = excluded.rate_kind, label_bn = excluded.label_bn, label_en = excluded.label_en,
      amount = excluded.amount, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'amount', p_amount, 'active', p_active);
end $$;

-- ---------- quote (no write) ----------
create or replace function public._xb541_quote(p_weight numeric, p_flavour text, p_designs text[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare base public.cake_price_rules; f public.cake_price_rules; d text; dr public.cake_price_rules; lines jsonb := '[]'; tot numeric := 0; amt numeric;
begin
  select * into base from public.cake_price_rules where group_kind = 'base' and active order by id limit 1;
  if not found then raise exception 'price_rules_missing: the owner has not set the cake base price'; end if;
  if p_weight is null or p_weight <= 0 or p_weight > 1000 then raise exception 'bad_weight'; end if;
  amt := round(p_weight * base.amount, 2);
  lines := lines || jsonb_build_object('code', base.code, 'group', 'base', 'label_en', base.label_en, 'label_bn', base.label_bn, 'rate', base.amount, 'basis', 'per_kg', 'qty', p_weight, 'amount', amt);
  tot := tot + amt;
  if nullif(btrim(coalesce(p_flavour, '')), '') is not null then
    select * into f from public.cake_price_rules where code = p_flavour and group_kind = 'flavour' and active;
    if not found then raise exception 'bad_flavour: no active flavour price with this code'; end if;
    amt := case when f.rate_kind = 'per_kg' then round(p_weight * f.amount, 2) else f.amount end;
    lines := lines || jsonb_build_object('code', f.code, 'group', 'flavour', 'label_en', f.label_en, 'label_bn', f.label_bn, 'rate', f.amount, 'basis', f.rate_kind, 'qty', case when f.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end if;
  foreach d in array coalesce(p_designs, '{}') loop
    select * into dr from public.cake_price_rules where code = d and group_kind = 'design' and active;
    if not found then raise exception 'bad_design: no active design extra with this code'; end if;
    amt := case when dr.rate_kind = 'per_kg' then round(p_weight * dr.amount, 2) else dr.amount end;
    lines := lines || jsonb_build_object('code', dr.code, 'group', 'design', 'label_en', dr.label_en, 'label_bn', dr.label_bn, 'rate', dr.amount, 'basis', dr.rate_kind, 'qty', case when dr.rate_kind = 'per_kg' then p_weight else 1 end, 'amount', amt);
    tot := tot + amt;
  end loop;
  return jsonb_build_object('lines', lines, 'total', round(tot, 2));
end $$;

create or replace function public.xb_cake_quote(p_weight numeric, p_flavour text default null, p_designs text[] default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  return public._xb541_quote(p_weight, p_flavour, p_designs);
end $$;

create or replace function public.xb_cake_price_rules_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.is_owner() or public.can_do('POS', 'view'))
    then coalesce((select jsonb_agg(to_jsonb(r) - 'updated_by' order by r.group_kind, r.code) from public.cake_price_rules r), '[]'::jsonb)
    else '[]'::jsonb end;
$$;

-- ---------- cake job ----------
create table if not exists public.cake_jobs (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  due_date date not null,
  due_slot_from time,
  weight_kg numeric not null check (weight_kg > 0 and weight_kg <= 1000),
  flavour_code text references public.cake_price_rules(code),
  layers int check (layers is null or layers between 1 and 10),
  message text check (message is null or char_length(message) <= 200),
  design_notes text check (design_notes is null or char_length(design_notes) <= 500),
  design_codes text[] not null default '{}',
  ref_photos text[] not null default '{}',
  eggless boolean not null default false,
  halal boolean not null default false,
  allergen_note text check (allergen_note is null or char_length(allergen_note) <= 200),
  quote_lines jsonb not null,
  quote_total numeric not null check (quote_total >= 0),
  advance_required numeric not null check (advance_required >= 0 and advance_required <= quote_total),
  balance numeric generated always as (quote_total - advance_required) stored,
  photo_ready_path text check (photo_ready_path is null or char_length(photo_ready_path) <= 200),
  state text not null default 'quoted' check (state in ('quoted', 'confirmed', 'slip', 'baked', 'decorated', 'ready', 'delivered', 'cancelled')),
  state_at timestamptz not null default now(),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists cake_jobs_due on public.cake_jobs (location_id, due_date) where state <> 'cancelled';

create table if not exists public.cake_job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.cake_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create index if not exists cake_job_events_job on public.cake_job_events (job_id, id);

-- trail and money-free fields: only state, photo and cancel fields move; nothing is deleted
create or replace function public._xb541_job_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a cake job is cancelled'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'photo_ready_path' - 'cancel_reason' - 'balance') then
    raise exception 'a cake job changes only its state, photo and cancel reason; the order and quote are fixed';
  end if;
  if old.state in ('delivered', 'cancelled') and new.state is distinct from old.state then raise exception 'closed: a delivered or cancelled cake job cannot change'; end if;
  return new;
end $$;
drop trigger if exists cake_jobs_ro on public.cake_jobs;
create trigger cake_jobs_ro before update or delete on public.cake_jobs for each row execute function public._xb541_job_ro();
drop trigger if exists audit_cake_jobs on public.cake_jobs;
create trigger audit_cake_jobs after insert or update on public.cake_jobs for each row execute function public.log_change('id');
drop trigger if exists cake_job_events_ro on public.cake_job_events;
create trigger cake_job_events_ro before update or delete on public.cake_job_events for each row execute function public._xb540_lines_ro();
drop trigger if exists audit_cake_job_events on public.cake_job_events;
create trigger audit_cake_job_events after insert on public.cake_job_events for each row execute function public.log_change('id');

create or replace function public._xb541_event(p_job uuid, p_from text, p_to text, p_note text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.cake_job_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (p_job, p_from, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
end $$;

create or replace function public._xb541_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('cake_flow_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
end $$;

-- create the job and its quote for an open app order. Capacity and lead time are checked here; the order spec is written too.
create or replace function public.xb_cake_create(p_order uuid, p_client uuid, p_due date, p_slot time, p_weight numeric, p_flavour text, p_layers int, p_message text,
  p_design_codes text[], p_design_notes text, p_eggless boolean, p_halal boolean, p_allergen text, p_ref_photos text[], p_advance numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; q jsonb; cap numeric := public.rule_num('cake_capacity_day'); lead numeric := public.rule_num('cake_lead_days'); n int; jid uuid; rec public.cake_jobs;
        photos text[] := coalesce(p_ref_photos, '{}'); adv numeric := coalesce(p_advance, 0);
begin
  if p_client is not null then
    select * into rec from public.cake_jobs where client_id = p_client;
    if found then return jsonb_build_object('id', rec.id, 'state', rec.state, 'dup', true); end if;
  end if;
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(o.location_id);
  if o.status not in ('new', 'confirmed') then raise exception 'order_closed: a cake is quoted on a new or confirmed order'; end if;
  if exists (select 1 from public.cake_jobs where order_id = o.id) then raise exception 'already_has_cake_job'; end if;
  if p_due is null or p_due < (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if lead is null then raise exception 'lead_time_not_set: the owner must set the cake lead time'; end if;
  if p_due < (now() at time zone 'Asia/Dhaka')::date + lead::int then raise exception 'lead_time: a cake needs % day(s) notice', lead::int; end if;
  if cap is null then raise exception 'capacity_not_set: the owner must set the cakes per day'; end if;
  select count(*) into n from public.cake_jobs where location_id = o.location_id and due_date = p_due and state <> 'cancelled';
  if n >= cap::int then raise exception 'capacity_full: % cakes already due on this day', n; end if;
  if o.delivery_date is not null and o.delivery_date <> p_due then raise exception 'due_date_differs_from_order'; end if;
  if p_message is not null and char_length(p_message) > 200 then raise exception 'too_long'; end if;
  q := public._xb541_quote(p_weight, p_flavour, p_design_codes);
  if (q->>'total')::numeric > o.subtotal - o.discount + o.delivery_charge then raise exception 'order_total_below_quote: the order lines must carry the cake at its quoted total'; end if;
  if adv < 0 or adv > (q->>'total')::numeric then raise exception 'bad_advance'; end if;
  if array_length(photos, 1) > 5 then raise exception 'too_many_photos'; end if;
  perform public.c2_order_spec_save(o.id, jsonb_build_array(jsonb_build_object('weight_kg', p_weight, 'flavour', p_flavour, 'message', p_message,
      'design', p_design_notes, 'photo_ref', photos[1])), 'cake job');
  insert into public.cake_jobs (client_id, order_id, location_id, due_date, due_slot_from, weight_kg, flavour_code, layers, message, design_notes, design_codes, ref_photos,
      eggless, halal, allergen_note, quote_lines, quote_total, advance_required, created_by, created_staff)
    values (p_client, o.id, o.location_id, p_due, p_slot, p_weight, nullif(p_flavour, ''), p_layers, nullif(btrim(p_message), ''), nullif(btrim(p_design_notes), ''),
      coalesce(p_design_codes, '{}'), photos, coalesce(p_eggless, false), coalesce(p_halal, false), nullif(btrim(p_allergen), ''), q->'lines', (q->>'total')::numeric, adv,
      auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into jid;
  perform public._xb541_event(jid, null, 'quoted', 'quote ' || (q->>'total') || ', advance ' || adv::text);
  return jsonb_build_object('id', jid, 'state', 'quoted', 'quote', q, 'advance_required', adv, 'balance', (q->>'total')::numeric - adv, 'due_count_after', n + 1);
end $$;

-- quote -> confirmed: needs the advance already in the order (the order advance field) at least the advance required
create or replace function public.xb_cake_confirm(p_job uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'confirmed' then return jsonb_build_object('id', j.id, 'state', 'confirmed', 'noop', true); end if;
  if j.state <> 'quoted' then raise exception 'bad_status: only a quoted cake can be confirmed (now %)', j.state; end if;
  select * into o from public.online_orders where id = j.order_id;
  if o.advance < j.advance_required then raise exception 'advance_required: the order must carry at least % before the cake is confirmed', j.advance_required; end if;
  update public.cake_jobs set state = 'confirmed', state_at = now() where id = j.id;
  perform public._xb541_event(j.id, 'quoted', 'confirmed', 'advance ' || o.advance::text);
  return jsonb_build_object('id', j.id, 'state', 'confirmed');
end $$;

-- the forward chain. delivered also needs the app order delivered and, when the switch is on, the finished-cake photo.
create or replace function public.xb_cake_move(p_job uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; nxt text;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_to not in ('slip', 'baked', 'decorated', 'ready', 'delivered') then raise exception 'bad_status'; end if;
  if j.state = p_to then return jsonb_build_object('id', j.id, 'state', j.state, 'noop', true); end if;
  nxt := case j.state when 'confirmed' then 'slip' when 'slip' then 'baked' when 'baked' then 'decorated' when 'decorated' then 'ready' when 'ready' then 'delivered' else null end;
  if nxt is distinct from p_to then raise exception 'bad_status: % -> % is not allowed', j.state, p_to; end if;
  if p_to = 'delivered' then
    select * into o from public.online_orders where id = j.order_id;
    if o.status <> 'delivered' then raise exception 'order_not_delivered: deliver the app order first (its own money path)'; end if;
    if public.rule_on('cake_photo_required') and j.photo_ready_path is null then raise exception 'photo_required: a photo of the finished cake is needed first'; end if;
  end if;
  update public.cake_jobs set state = p_to, state_at = now() where id = j.id;
  perform public._xb541_event(j.id, j.state, p_to, p_note);
  return jsonb_build_object('id', j.id, 'state', p_to);
end $$;

create or replace function public.xb_cake_photo(p_job uuid, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state not in ('decorated', 'ready') then raise exception 'bad_status: the photo is taken when the cake is decorated or ready'; end if;
  if p_path is null or p_path !~ ('^cake/' || j.location_id || '/[A-Za-z0-9_.-]{1,120}\.jpe?g$') then raise exception 'bad_path'; end if;
  update public.cake_jobs set photo_ready_path = p_path where id = j.id;
  perform public._xb541_event(j.id, j.state, j.state, 'photo of the finished cake');
  return jsonb_build_object('id', j.id, 'photo_ready_path', p_path);
end $$;

-- cancel before delivery: the refund and advance rules are the existing order cancel (phase 448)
create or replace function public.xb_cake_cancel(p_job uuid, p_reason text, p_advance_fate text default 'none', p_refund_mode text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; r jsonb;
begin
  select * into j from public.cake_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if j.state = 'cancelled' then return jsonb_build_object('id', j.id, 'state', 'cancelled', 'noop', true); end if;
  if j.state = 'delivered' then raise exception 'order_closed: a delivered cake is not cancelled; use the sale return'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  r := public.c2_order_cancel(j.order_id, btrim(p_reason), p_advance_fate, p_refund_mode);
  update public.cake_jobs set state = 'cancelled', state_at = now(), cancel_reason = left(btrim(p_reason), 300) where id = j.id;
  perform public._xb541_event(j.id, j.state, 'cancelled', btrim(p_reason));
  return jsonb_build_object('id', j.id, 'state', 'cancelled', 'order', r);
end $$;

-- the production and decoration sheet for one day (cakes due on that day, not cancelled)
create or replace function public.xb_cake_due(p_date date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then '{"rows":[]}'::jsonb else jsonb_build_object(
    'date', p_date,
    'count', (select count(*) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'total_kg', (select coalesce(sum(j.weight_kg), 0) from public.cake_jobs j where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('job_id', j.id, 'order_no', o.order_no, 'slot', j.due_slot_from, 'weight_kg', j.weight_kg, 'layers', j.layers,
        'flavour', j.flavour_code, 'message', j.message, 'design', j.design_notes, 'design_codes', j.design_codes, 'eggless', j.eggless, 'halal', j.halal,
        'allergen', j.allergen_note, 'state', j.state, 'delivery_mode', o.delivery_mode, 'customer', o.customer_name, 'balance', j.balance, 'ref_photos', j.ref_photos)
        order by j.due_slot_from nulls last, j.id)
      from public.cake_jobs j join public.online_orders o on o.id = j.order_id
      where j.due_date = p_date and j.state <> 'cancelled' and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)), '[]'::jsonb)) end;
$$;

-- customer confirmation: a wa.me text for the owner's tap, and an SMS queued only when SMS is on, the customer opted in and is not do-not-contact
create or replace function public.xb_cake_notify(p_job uuid, p_template text default 'cake_confirmed') returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.cake_jobs; o public.online_orders; cu uuid; mob text; txt text; q jsonb; dnc boolean := false; enq jsonb := null;
begin
  select * into j from public.cake_jobs where id = p_job;
  if not found then raise exception 'not_found'; end if;
  perform public._xb541_gate(j.location_id);
  if p_template not in ('cake_confirmed', 'cake_ready') then raise exception 'bad_template'; end if;
  select * into o from public.online_orders where id = j.order_id;
  mob := public.norm_mobile(o.customer_mobile);
  txt := case when p_template = 'cake_ready' then 'Your cake (order #' || o.order_no || ') is ready for ' || j.due_date::text || '.'
              else 'Your cake order #' || o.order_no || ' is confirmed for ' || j.due_date::text || '. Advance ' || j.advance_required::text || ', balance ' || j.balance::text || ' taka.' end;
  select c.id into cu from public.customers c where c.mobile = mob;
  if cu is not null then select coalesce(p.dnc, false) into dnc from public.crm_contact_prefs p where p.customer_id = cu; end if;
  if cu is not null and not dnc and public.rule_on('notify_sms_on') then
    enq := public.notify_enqueue(gen_random_uuid(), cu, 'sms', p_template, jsonb_build_object('ref', '#' || o.order_no, 'date', j.due_date::text), 'en', 'cake_job', j.id::text);
  end if;
  return jsonb_build_object('id', j.id, 'wa_phone', case when mob like '01%' then '880' || substr(mob, 2) end, 'wa_text', txt,
    'sms', coalesce(to_jsonb(case when cu is null then 'no_customer_record' when dnc then 'do_not_contact' when not public.rule_on('notify_sms_on') then 'sms_off' end), enq));
end $$;

create or replace function public.xb_cake_job_get(p_order uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not public.can_do('POS', 'view') then null else (
    select to_jsonb(j) - 'client_id' || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_state, 'to', e.to_state, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
        from public.cake_job_events e where e.job_id = j.id), '[]'::jsonb))
    from public.cake_jobs j where j.order_id = p_order and public.can_loc(j.location_id) ) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.cake_price_rules enable row level security;
alter table public.cake_jobs enable row level security;
alter table public.cake_job_events enable row level security;
revoke all on public.cake_price_rules, public.cake_jobs, public.cake_job_events from public, anon, authenticated;
grant select on public.cake_price_rules, public.cake_jobs, public.cake_job_events to authenticated;
drop policy if exists cake_price_rules_sel on public.cake_price_rules;
create policy cake_price_rules_sel on public.cake_price_rules for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists cake_jobs_sel on public.cake_jobs;
create policy cake_jobs_sel on public.cake_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cake_job_events_sel on public.cake_job_events;
create policy cake_job_events_sel on public.cake_job_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.cake_jobs j where j.id = job_id and public.can_loc(j.location_id)));

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('cake_confirmed', 'sms', 'আপনার কেক অর্ডার {ref} নিশ্চিত হয়েছে, তারিখ {date}। - {shop}', 'Your cake order {ref} is confirmed for {date}. - {shop}'),
 ('cake_ready', 'sms', 'আপনার কেক {ref} প্রস্তুত, তারিখ {date}। - {shop}', 'Your cake {ref} is ready for {date}. - {shop}')
on conflict (code) do nothing;

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_cake\_%' or p.proname like '\_xb541\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'xb\_cake\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase493.sql
-- ============================================================
-- Phase 493 - XB package part 3: riders, delivery status, delivery zones, COD collected and deposited per rider per day.
-- Run AFTER phase 492. New file only; no old phase or function is edited. Paste twice = no error, no second row.
--
--   * riders                 staff or external rider master (name_bn / name_en, kind, optional employee link, phone, place, active). Owner or grant rider_manage.
--   * delivery_zones        zone fee table (owner or rider_manage). A zone with no fee cannot be assigned (nothing invented).
--   * delivery_jobs         one per app order: rider, zone, fee, attempts, live-location link (a https maps link the rider shares; no tracking is built),
--                           COD amount (= the order balance at handover). States: assigned -> out -> delivered | failed;
--                           failed -> assigned (reattempt, attempts + 1) or failed -> returned (back to the shop). Every move in delivery_events.
--   * cod_deposits          money a rider hands in (append-only, client id).
--   * xb_cod_reconcile      per rider per day: COD collected on delivered jobs, deposited, difference (short / over). Information only.
--   * cod_cases             one open case per rider per day with a difference; the owner explains it. NOTHING is posted to cash or the books:
--                           linking a short to the existing shortage cases needs an entry row and is an owner decision (not built).
--   * xb_rider_perf         deliveries, failed, returned, average minutes from handover to delivered, per rider for a date range.
--   * Rules: xb_delivery_on (OFF). When OFF every writer here is refused. Nothing is sent to riders or customers by this phase.
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.employees') is null or to_regprocedure('public.xb_cake_create(uuid,uuid,date,time,numeric,text,int,text,text[],text,boolean,boolean,text,text[],numeric)') is null then
    raise exception 'phase493 needs phase492 (and phase61 / phase41 employees) pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('xb_delivery_on', 'pos', 'switch', 'false', null, null, null, null, 'রাইডার ও ডেলিভারি ট্র্যাকিং চালু', 'Rider & delivery tracking চালু', 'Rider and delivery tracking is on',
  'চালু হলে রাইডার, ডেলিভারির অবস্থা, COD জমা ও হিসাব লেখা যাবে। কিছু পাঠানো হয় না।', 'When on, riders, delivery status and COD deposits can be recorded. Nothing is sent by this.', 546)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rider_manage', 'pos', 92, 'রাইডার ও জোন ঠিক করা', 'Rider ও zone ঠিক করা', 'Manage riders and delivery zones', 'once', null)
on conflict (grant_code) do nothing;

create or replace function public._xb542_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('xb_delivery_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
end $$;
create or replace function public._xb542_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'rider_manage' and g.location_id is null));
$$;
create or replace function public._xb542_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: this trail or deposit is never changed or deleted'; end $$;

-- ---------- riders and zones ----------
create table if not exists public.riders (
  id bigint generated always as identity primary key,
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  kind text not null check (kind in ('staff', 'external')),
  employee_id uuid references public.employees(id),
  phone text check (phone is null or char_length(phone) between 6 and 20),
  location_id int references public.locations(id),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'staff') = (employee_id is not null) or kind = 'external')
);
create table if not exists public.delivery_zones (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (char_length(btrim(name_en)) between 1 and 80),
  fee numeric not null check (fee >= 0 and fee <= 1000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists riders_nodel on public.riders;
create trigger riders_nodel before delete on public.riders for each row execute function public._xb542_ro();
drop trigger if exists delivery_zones_nodel on public.delivery_zones;
create trigger delivery_zones_nodel before delete on public.delivery_zones for each row execute function public._xb542_ro();
drop trigger if exists audit_riders on public.riders;
create trigger audit_riders after insert or update on public.riders for each row execute function public.log_change('id');
drop trigger if exists audit_delivery_zones on public.delivery_zones;
create trigger audit_delivery_zones after insert or update on public.delivery_zones for each row execute function public.log_change('code');

create or replace function public.xb_rider_save(p_id bigint, p_name_bn text, p_name_en text, p_kind text, p_employee uuid, p_phone text, p_loc int, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or p_kind not in ('staff', 'external') or p_active is null then raise exception 'bad_input'; end if;
  if p_kind = 'staff' and (p_employee is null or not exists (select 1 from public.employees e where e.id = p_employee)) then raise exception 'employee_required'; end if;
  if p_kind = 'external' then p_employee := null; end if;
  if p_id is null then
    insert into public.riders (name_bn, name_en, kind, employee_id, phone, location_id, active, created_by)
      values (left(btrim(p_name_bn), 80), left(nullif(btrim(p_name_en), ''), 80), p_kind, p_employee, nullif(btrim(p_phone), ''), p_loc, p_active, auth.uid()) returning id into id_;
  else
    update public.riders set name_bn = left(btrim(p_name_bn), 80), name_en = left(nullif(btrim(p_name_en), ''), 80), kind = p_kind, employee_id = p_employee,
      phone = nullif(btrim(p_phone), ''), location_id = p_loc, active = p_active where id = p_id returning id into id_;
    if id_ is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.xb_delivery_zone_save(p_code text, p_name_bn text, p_name_en text, p_fee numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if p_code !~ '^[a-z0-9_]{2,30}$' or p_fee is null or p_fee < 0 or p_fee > 1000000 or p_active is null then raise exception 'bad_input'; end if;
  insert into public.delivery_zones (code, name_bn, name_en, fee, active, updated_by) values (p_code, left(btrim(p_name_bn), 80), left(btrim(p_name_en), 80), p_fee, p_active, auth.uid())
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, fee = excluded.fee, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'fee', p_fee);
end $$;

-- ---------- delivery jobs ----------
create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  rider_id bigint references public.riders(id),
  zone_code text references public.delivery_zones(code),
  fee numeric check (fee is null or fee >= 0),
  attempts int not null default 0 check (attempts >= 0 and attempts <= 10),
  map_link text check (map_link is null or (map_link ~ '^https://' and char_length(map_link) <= 300)),
  cod_amount numeric check (cod_amount is null or cod_amount >= 0),
  state text not null default 'unassigned' check (state in ('unassigned', 'assigned', 'out', 'delivered', 'failed', 'returned')),
  handed_at timestamptz, delivered_at timestamptz, failed_reason text check (failed_reason is null or char_length(failed_reason) <= 300),
  cod_collected numeric check (cod_collected is null or cod_collected >= 0),
  created_by uuid, created_at timestamptz not null default now(), state_at timestamptz not null default now()
);
create table if not exists public.delivery_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.delivery_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create table if not exists public.cod_deposits (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  deposit_day date not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  note text check (note is null or char_length(note) <= 300),
  deposited_by uuid, deposited_staff text, deposited_at timestamptz not null default now()
);
create table if not exists public.cod_cases (
  id bigint generated always as identity primary key,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  case_day date not null,
  collected numeric not null, deposited numeric not null, difference numeric not null check (difference <> 0),
  state text not null default 'open' check (state in ('open', 'explained')),
  explain_note text check (explain_note is null or char_length(explain_note) <= 300),
  explained_by uuid, explained_at timestamptz,
  opened_at timestamptz not null default now(),
  unique (rider_id, case_day)
);
drop trigger if exists delivery_events_ro on public.delivery_events;
create trigger delivery_events_ro before update or delete on public.delivery_events for each row execute function public._xb542_ro();
drop trigger if exists cod_deposits_ro on public.cod_deposits;
create trigger cod_deposits_ro before update or delete on public.cod_deposits for each row execute function public._xb542_ro();
drop trigger if exists audit_delivery_jobs on public.delivery_jobs;
create trigger audit_delivery_jobs after insert or update on public.delivery_jobs for each row execute function public.log_change('id');
drop trigger if exists audit_cod_deposits on public.cod_deposits;
create trigger audit_cod_deposits after insert on public.cod_deposits for each row execute function public.log_change('id');

-- delivery_jobs: state, attempts, link, cod and the rider move; the order and zone fee are fixed once a job exists
create or replace function public._xb542_job_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a delivery is returned or closed'; end if;
  if old.state in ('delivered', 'returned') and new.state is distinct from old.state then raise exception 'closed: a delivered or returned job cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at')
     is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at') then
    raise exception 'the order, zone and fee of a delivery are fixed';
  end if;
  return new;
end $$;
drop trigger if exists delivery_jobs_guard on public.delivery_jobs;
create trigger delivery_jobs_guard before update or delete on public.delivery_jobs for each row execute function public._xb542_job_guard();

-- assign a rider and a zone (fee from the zone table; a zone with no fee is refused by the table itself)
create or replace function public.xb_delivery_assign(p_order uuid, p_rider bigint, p_zone text, p_map_link text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; z public.delivery_zones; r public.riders; j public.delivery_jobs; bal numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
  select * into r from public.riders where id = p_rider and active;
  if not found then raise exception 'rider_not_found_or_inactive'; end if;
  if r.location_id is not null and r.location_id <> o.location_id then raise exception 'rider_other_location'; end if;
  select * into z from public.delivery_zones where code = p_zone and active;
  if not found then raise exception 'zone_not_found_or_inactive'; end if;
  bal := o.subtotal - o.discount + o.delivery_charge - o.advance;
  select * into j from public.delivery_jobs where order_id = o.id for update;
  if not found then
    insert into public.delivery_jobs (order_id, location_id, rider_id, zone_code, fee, map_link, cod_amount, state, created_by)
      values (o.id, o.location_id, r.id, z.code, z.fee, nullif(btrim(p_map_link), ''), greatest(bal, 0), 'assigned', auth.uid()) returning * into j;
    insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff) values (j.id, 'unassigned', 'assigned', 'rider ' || r.name_en, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  else
    if j.state not in ('unassigned', 'assigned') then raise exception 'bad_status: a job on the road cannot change rider'; end if;
    update public.delivery_jobs set rider_id = r.id, state = 'assigned', state_at = now(), map_link = coalesce(nullif(btrim(p_map_link), ''), map_link) where id = j.id returning * into j;
  end if;
  return jsonb_build_object('id', j.id, 'state', j.state, 'rider_id', r.id, 'zone', z.code, 'fee', z.fee, 'cod_amount', j.cod_amount);
end $$;

-- out (handed to rider), delivered (COD collected stated), failed (reason), reattempt (failed -> assigned), returned (failed -> back to shop)
create or replace function public.xb_delivery_move(p_job uuid, p_to text, p_cod numeric default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; from_s text; n int;
begin
  select * into j from public.delivery_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(j.location_id);
  from_s := j.state;
  if p_to not in ('out', 'delivered', 'failed', 'reattempt', 'returned') then raise exception 'bad_status'; end if;
  if p_to = 'out' and from_s = 'assigned' then
    update public.delivery_jobs set state = 'out', handed_at = now(), state_at = now() where id = j.id;
  elsif p_to = 'delivered' and from_s = 'out' then
    if p_cod is not null and (p_cod < 0 or p_cod > 1000000000) then raise exception 'bad_amount'; end if;
    update public.delivery_jobs set state = 'delivered', delivered_at = now(), state_at = now(), cod_collected = coalesce(p_cod, cod_amount) where id = j.id;
  elsif p_to = 'failed' and from_s = 'out' then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
    update public.delivery_jobs set state = 'failed', failed_reason = left(btrim(p_reason), 300), state_at = now(), attempts = attempts + 1 where id = j.id;
  elsif p_to = 'reattempt' and from_s = 'failed' then
    if j.attempts >= 3 then raise exception 'too_many_attempts: return the goods to the shop'; end if;
    update public.delivery_jobs set state = 'assigned', state_at = now(), handed_at = null where id = j.id;
    p_to := 'assigned';
  elsif p_to = 'returned' and from_s = 'failed' then
    update public.delivery_jobs set state = 'returned', state_at = now() where id = j.id;
  else
    raise exception 'bad_status: % -> % is not allowed', from_s, p_to;
  end if;
  insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (j.id, from_s, p_to, left(nullif(btrim(coalesce(p_reason, '')), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('id', j.id, 'state', p_to, 'attempts', (select attempts from public.delivery_jobs where id = j.id));
end $$;

-- COD deposit: what a rider hands in on a day (no cash move is posted here)
create or replace function public.xb_cod_deposit(p_client uuid, p_rider bigint, p_loc int, p_day date, p_amount numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if p_client is not null and exists (select 1 from public.cod_deposits where client_id = p_client) then
    return jsonb_build_object('dup', true, 'id', (select id from public.cod_deposits where client_id = p_client));
  end if;
  perform public._xb542_gate(p_loc);
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.riders where id = p_rider and active) then raise exception 'rider_not_found_or_inactive'; end if;
  insert into public.cod_deposits (client_id, rider_id, location_id, deposit_day, amount, note, deposited_by, deposited_staff)
    values (p_client, p_rider, p_loc, p_day, round(p_amount, 2), left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'dup', false);
end $$;

-- per rider per day: collected (delivered jobs of that day) versus deposited. A difference opens one case (owner explains it).
create or replace function public.xb_cod_reconcile(p_day date, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rr record; col numeric; dep numeric; rows_ jsonb := '[]';
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then raise exception 'not allowed'; end if;
  for rr in select r.id, r.name_en, r.name_bn from public.riders r where r.active and (p_loc is null or r.location_id is null or r.location_id = p_loc) order by r.id loop
    select coalesce(sum(j.cod_collected), 0) into col from public.delivery_jobs j
     where j.rider_id = rr.id and j.state = 'delivered' and (j.delivered_at at time zone 'Asia/Dhaka')::date = p_day and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id);
    select coalesce(sum(d.amount), 0) into dep from public.cod_deposits d where d.rider_id = rr.id and d.deposit_day = p_day and (p_loc is null or d.location_id = p_loc) and public.can_loc(d.location_id);
    rows_ := rows_ || jsonb_build_object('rider_id', rr.id, 'rider', coalesce(rr.name_en, rr.name_bn), 'collected', col, 'deposited', dep, 'difference', col - dep,
      'status', case when col - dep = 0 then 'matched' when col - dep > 0 then 'short' else 'over' end);
    if col - dep <> 0 and (p_loc is not null) then
      insert into public.cod_cases (rider_id, location_id, case_day, collected, deposited, difference)
        values (rr.id, p_loc, p_day, col, dep, col - dep) on conflict (rider_id, case_day) do nothing;
    end if;
  end loop;
  return jsonb_build_object('day', p_day, 'riders', rows_, 'notes', jsonb_build_array('information_only_no_cash_is_posted', 'a_difference_opens_a_case_for_the_owner_to_explain'));
end $$;

create or replace function public.xb_cod_case_explain(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.cod_cases;
begin
  if not public._xb542_manage() and not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.cod_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if c.state <> 'open' then raise exception 'already_explained'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cod_cases set state = 'explained', explain_note = left(btrim(p_note), 300), explained_by = auth.uid(), explained_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'state', 'explained');
end $$;

-- performance per rider over a date range (handover date)
create or replace function public.xb_rider_perf(p_from date, p_to date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then '[]'::jsonb else coalesce((
    select jsonb_agg(z.row_json order by z.rid) from (
      select r.id as rid, jsonb_build_object('rider_id', r.id, 'rider', coalesce(r.name_en, r.name_bn),
        'jobs', count(j.id), 'delivered', count(j.id) filter (where j.state = 'delivered'), 'failed', count(j.id) filter (where j.state in ('failed', 'returned')),
        'returned', count(j.id) filter (where j.state = 'returned'), 'open', count(j.id) filter (where j.state in ('unassigned', 'assigned', 'out')),
        'avg_minutes_to_deliver', round(avg(extract(epoch from (j.delivered_at - j.handed_at)) / 60) filter (where j.state = 'delivered' and j.handed_at is not null), 1)) as row_json
      from public.riders r left join public.delivery_jobs j on j.rider_id = r.id and (j.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
        and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)
      where r.active group by r.id) z), '[]'::jsonb) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.riders enable row level security;
alter table public.delivery_zones enable row level security;
alter table public.delivery_jobs enable row level security;
alter table public.delivery_events enable row level security;
alter table public.cod_deposits enable row level security;
alter table public.cod_cases enable row level security;
revoke all on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases from public, anon, authenticated;
grant select on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases to authenticated;
drop policy if exists riders_sel on public.riders;
create policy riders_sel on public.riders for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_zones_sel on public.delivery_zones;
create policy delivery_zones_sel on public.delivery_zones for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_jobs_sel on public.delivery_jobs;
create policy delivery_jobs_sel on public.delivery_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists delivery_events_sel on public.delivery_events;
create policy delivery_events_sel on public.delivery_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.delivery_jobs j where j.id = job_id and public.can_loc(j.location_id)));
drop policy if exists cod_deposits_sel on public.cod_deposits;
create policy cod_deposits_sel on public.cod_deposits for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cod_cases_sel on public.cod_cases;
create policy cod_cases_sel on public.cod_cases for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_rider\_%' or p.proname like 'xb\_delivery\_%' or p.proname like 'xb\_cod\_%' or p.proname like 'xb\_rider\_perf%'
                  or p.proname like '\_xb542\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not like '\_xb542\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase494.sql
-- Phase 494 (XC-1) - OWNER DAILY SUMMARY, RECIPIENTS, SEND LOG, RECEIPT CONTINUITY AND SYNC REPORT.
-- Paste AFTER phase478 (end of the owner paste order). Paste-twice safe. Earlier phase files are not edited.
-- Everything new is OFF by default: switches xc_summary_on, xc_summary_email_on, xc_summary_telegram_on, xc_sync_alert_on (all false).
-- Nothing is sent from here. tools/owner_summary.py (GitHub Actions or a laptop, dry-run by default) reads xc_summary_targets(), composes with xc_summary_compose(),
-- sends by e-mail (Gmail SMTP, existing pattern) or Telegram (bot token = secret, chat id = recipient address), then writes xc_summary_record(). A send that is already logged
-- as sent for the same day and recipient is never repeated (partial unique index).
-- Blank thresholds stay blank: xc_sync_stale_hours has no default; with it blank the sync alert says "threshold not set" and sends nothing.
-- Access: owner, or the ops bot (ops purpose 'notify'). Recipient addresses are readable only by the owner and the ops bot.

do $g$ begin
  if to_regprocedure('public.daily_digest(date)') is null then raise exception 'phase494 needs phase46 (daily_digest)'; end if;
  if to_regprocedure('public._notif_add(text,text,text,text,text,text,text,text,text,integer)') is null then raise exception 'phase494 needs the notifications helper'; end if;
  if to_regprocedure('public._rb4_prod_view(integer)') is null then raise exception 'phase494 needs phase404'; end if;
end $g$;

-- ---------- settings (all OFF / blank) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_summary_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'দৈনিক সারাংশ চালু / Owner daily summary: on', 'Sends the owner daily summary by the channels switched on below. OFF = nothing is sent.', 9500),
 ('xc_summary_email_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'ই-মেইলে সারাংশ / Daily summary by e-mail', 'Recipients with channel e-mail get the summary. Needs the Gmail secrets (docs/OPS_SETUP.md).', 9501),
 ('xc_summary_telegram_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'টেলিগ্রামে সারাংশ / Daily summary by Telegram', 'Recipients with channel telegram get the summary. The bot token is a GitHub secret; the chat id is on the recipient row.', 9502),
 ('xc_summary_times', 'text', '"21"'::jsonb, null::text, null::numeric, null::numeric,
   'সারাংশের সময় (ঢাকা, যেমন 08,21) / Summary hours (Dhaka, e.g. 08,21)', 'The scheduled hours the summary is due at. The script decides by the hour.', 9503),
 ('xc_sync_alert_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'সব দোকান সিঙ্ক? সতর্কতা / Every shop synced? alert', 'Adds an in-app warning for each outlet whose last recorded sale is older than the hours below.', 9504),
 ('xc_sync_stale_hours', 'number', null::jsonb, 'hours', 1::numeric, 720::numeric,
   'কত ঘণ্টা বিক্রি না এলে সতর্কতা (ফাঁকা = সেট নেই) / Hours without a sale before the alert (blank = not set)', 'Blank = the alert says "threshold not set" and does nothing. Nothing is assumed.', 9505)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- recipients (owner-entered; addresses are personal, owner and ops bot only) ----------
create table if not exists public.xc_summary_recipients (
  id bigint generated by default as identity primary key,
  name text not null check (length(btrim(name)) between 1 and 80),
  channel text not null check (channel in ('email', 'telegram')),
  address text not null check (length(btrim(address)) between 3 and 200),        -- e-mail address, or Telegram chat id (a number). Not a secret.
  scope text not null default 'owner' check (scope in ('owner', 'outlet')),
  location_id int references public.locations(id),
  quiet_when_empty boolean not null default false,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  check ((scope = 'outlet') = (location_id is not null)),
  check (channel <> 'telegram' or address ~ '^-?[0-9]{5,20}$')
);
alter table public.xc_summary_recipients enable row level security;
revoke all on public.xc_summary_recipients from public, anon, authenticated;
grant select on public.xc_summary_recipients to authenticated;
drop policy if exists xc_summary_recipients_owner on public.xc_summary_recipients;
create policy xc_summary_recipients_owner on public.xc_summary_recipients for select to authenticated using (public.is_owner());
drop trigger if exists audit_xc_summary_recipients on public.xc_summary_recipients;
create trigger audit_xc_summary_recipients after insert or update on public.xc_summary_recipients for each row execute function public.log_change('id');
drop trigger if exists xc_summary_recipients_nodel on public.xc_summary_recipients;
create trigger xc_summary_recipients_nodel before delete on public.xc_summary_recipients for each row execute function public.no_hard_delete();

-- ---------- send log (append-only; one successful send per day, recipient and channel) ----------
create table if not exists public.xc_summary_log (
  id bigint generated by default as identity primary key,
  run_date date not null,
  recipient_id bigint references public.xc_summary_recipients(id),
  channel text not null check (channel in ('email', 'telegram')),
  scope text not null check (scope in ('owner', 'outlet')),
  location_id int references public.locations(id),
  status text not null check (status in ('sent', 'failed', 'skipped_empty')),
  content_hash text check (content_hash is null or length(content_hash) <= 80),
  error text check (error is null or length(error) <= 300),
  created_at timestamptz not null default now()
);
create unique index if not exists xc_summary_log_sent_once on public.xc_summary_log (run_date, recipient_id, channel) where status = 'sent';
create index if not exists xc_summary_log_day on public.xc_summary_log (run_date desc);
alter table public.xc_summary_log enable row level security;
revoke all on public.xc_summary_log from public, anon, authenticated;
grant select on public.xc_summary_log to authenticated;
drop policy if exists xc_summary_log_owner on public.xc_summary_log;
create policy xc_summary_log_owner on public.xc_summary_log for select to authenticated using (public.is_owner());
drop trigger if exists xc_summary_log_nodel on public.xc_summary_log;
create trigger xc_summary_log_nodel before delete or update on public.xc_summary_log for each row execute function public.no_hard_delete();

-- who may read the summary: the owner, or the ops bot for notify
create or replace function public._xc_summary_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._is_ops('notify'));
$$;

-- ---------- recipients: save (owner only; no delete, retire with active = false) ----------
create or replace function public.xc_recipient_save(p_id bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_summary_recipients; nm text; ch text; ad text; sc text; lc int; qe boolean; ac boolean; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is not null then select * into o from public.xc_summary_recipients where id = p_id; if not found then raise exception 'not_found'; end if; end if;
  nm := coalesce(nullif(btrim(p ->> 'name'), ''), o.name);
  ch := coalesce(nullif(btrim(p ->> 'channel'), ''), o.channel);
  ad := coalesce(nullif(btrim(p ->> 'address'), ''), o.address);
  sc := coalesce(nullif(btrim(p ->> 'scope'), ''), o.scope, 'owner');
  lc := case when p ? 'location_id' then nullif(p ->> 'location_id', '')::int else o.location_id end;
  qe := case when p ? 'quiet_when_empty' then coalesce((p ->> 'quiet_when_empty')::boolean, false) else coalesce(o.quiet_when_empty, false) end;
  ac := case when p ? 'active' then coalesce((p ->> 'active')::boolean, true) else coalesce(o.active, true) end;
  if nm is null then raise exception 'name_required'; end if;
  if ch not in ('email', 'telegram') then raise exception 'bad_channel'; end if;
  if sc not in ('owner', 'outlet') then raise exception 'bad_scope'; end if;
  if sc = 'outlet' and lc is null then raise exception 'location_required'; end if;
  if sc = 'owner' then lc := null; end if;
  if lc is not null and not exists (select 1 from public.locations where id = lc) then raise exception 'bad_location'; end if;
  if ch = 'email' and ad !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'bad_address'; end if;
  if ch = 'telegram' and ad !~ '^-?[0-9]{5,20}$' then raise exception 'bad_address'; end if;
  if p_id is null then
    insert into public.xc_summary_recipients (name, channel, address, scope, location_id, quiet_when_empty, active, created_by)
      values (left(nm, 80), ch, ad, sc, lc, qe, ac, auth.uid()) returning id into id_;
  else
    update public.xc_summary_recipients set name = left(nm, 80), channel = ch, address = ad, scope = sc, location_id = lc,
      quiet_when_empty = qe, active = ac, updated_by = auth.uid(), updated_at = now() where id = p_id returning id into id_;
  end if;
  return jsonb_build_object('ok', true, 'id', id_);
end $$;

-- one place, one day: bills and net sales with the same definition as daily_digest (net of returns when the setting is on)
create or replace function public._xc_outlet_day(p_day date, p_loc int) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('net',
           (select coalesce(sum(s.total), 0) from public.sales s where s.status = 'done' and s.sale_date = p_day and s.location_id = p_loc)
         - case when public.rule_on('reports_net_of_returns') then
             (select coalesce(sum(r.amount), 0) from public.sale_returns r where r.status = 'done' and r.location_id = p_loc and (r.created_at at time zone 'Asia/Dhaka')::date = p_day)
           else 0 end,
         'bills', (select count(*) from public.sales s where s.status = 'done' and s.sale_date = p_day and s.location_id = p_loc));
$$;

-- ---------- the composed summary (one JSON; the server decides every figure) ----------
create or replace function public.xc_summary_compose(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); dig jsonb; sales_t jsonb; sales_y jsonb; sales_w jsonb; cash jsonb; wallets jsonb; wast jsonb;
        cakes int; cake_specs int; open_o int; failed_jobs int := 0; failed_mail int; failed_ifail int; nflag int := 0; attention int; by_loc jsonb := '[]'::jsonb;
        notes jsonb := '[]'::jsonb; coll numeric := 0; outlet_name text; ex_red int; ex_yellow int; appr int; lowc int; expc int; st jsonb; rc jsonb;
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  if p_loc is not null then
    if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    select name_en into outlet_name from public.locations where id = p_loc;
  end if;
  -- sales: owner = the whole company (daily_digest, same figures as the e-mail digest); outlet = that place only, same definition (net of returns when the setting is on)
  if p_loc is null then
    dig := public.daily_digest(d);
    sales_t := dig -> 'sales' -> 'today'; sales_y := dig -> 'sales' -> 'yesterday'; sales_w := dig -> 'sales' -> 'last_week'; by_loc := dig -> 'sales' -> 'by_location';
  else
    sales_t := public._xc_outlet_day(d, p_loc); sales_y := public._xc_outlet_day(d - 1, p_loc); sales_w := public._xc_outlet_day(d - 7, p_loc);
  end if;
  select jsonb_build_object('short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0), 'count', count(*))
    into cash from public.exceptions where flag_code = 'cash_short_over' and entry_date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('total', coalesce(sum(amount), 0), 'by_wallet', coalesce(jsonb_agg(jsonb_build_object('wallet', w.wallet, 'amount', w.amount) order by w.wallet) filter (where w.wallet is not null), '[]'::jsonb))
    into wallets from (select sp.wallet, sum(sp.amount) as amount from public.sale_payments sp
                        where sp.mode = 'mobile' and not sp.voided and (sp.paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or sp.location_id = p_loc) group by sp.wallet) w;
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or location_id = p_loc);
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into wast
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id
   where (x.made_at at time zone 'Asia/Dhaka')::date = d and (p_loc is null or x.location_id = p_loc);
  select count(*) into open_o from public.online_orders where status in ('new', 'confirmed', 'packed') and (p_loc is null or location_id = p_loc);
  select count(*) into cakes from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc);
  select count(*) into cake_specs from public.online_orders o where o.status in ('new', 'confirmed', 'packed') and o.delivery_date = d + 1 and (p_loc is null or o.location_id = p_loc)
     and exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active');
  -- company-wide sections: only in the owner summary (an outlet recipient does not see other outlets' dues, approvals or failures)
  if p_loc is null then
    ex_red := (dig -> 'exceptions_open' ->> 'red')::int; ex_yellow := (dig -> 'exceptions_open' ->> 'yellow')::int;
    appr := (dig ->> 'approvals_pending')::int; lowc := (dig -> 'stock_alerts' ->> 'low_items')::int; expc := (dig -> 'stock_alerts' ->> 'expiring_batches')::int;
    select count(*) into failed_ifail from public.intake_failures where state = 'failed';
    select count(*) into failed_mail from public.notify_outbox where status = 'failed' and created_at > now() - interval '1 day';
    if to_regclass('public.job_runs') is not null then
      execute $q$select count(*) from public.job_runs where status = 'failed' and started_at > now() - interval '1 day'$q$ into failed_jobs;
    end if;
    st := dig -> 'backup';
  end if;
  attention := coalesce(cash ->> 'count', '0')::int + coalesce(appr, 0) + coalesce(lowc, 0) + coalesce(expc, 0) + coalesce(ex_red, 0) + coalesce(failed_ifail, 0)
             + coalesce(failed_mail, 0) + coalesce(failed_jobs, 0) + cakes + coalesce((wast ->> 'count')::int, 0);
  if p_loc is null and (st ->> 'stale')::boolean then attention := attention + 1; end if;
  -- what the summary says about itself (no ML, no probability)
  notes := jsonb_build_array(
    jsonb_build_object('code', 'figures_are_server_totals', 'text_en', 'Every figure is computed on the server for the day shown; nothing is estimated.', 'text_bn', 'সব সংখ্যা সার্ভারে ওই দিনের হিসাব; কোনো অনুমান নেই।'),
    jsonb_build_object('code', 'net_of_returns', 'text_en', case when public.rule_on('reports_net_of_returns') then 'Sales are net of returns.' else 'Sales are gross (returns not deducted; setting off).' end,
                       'text_bn', case when public.rule_on('reports_net_of_returns') then 'বিক্রি ফেরত বাদে (নিট)।' else 'বিক্রি ফেরত না বাদ দিয়ে (সেটিং বন্ধ)।' end));
  if p_loc is not null then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'outlet_scope', 'text_en', 'Outlet view: company-wide dues, approvals, stock alerts and failures are left out.', 'text_bn', 'শাখার দৃশ্য: কোম্পানি-ব্যাপী বাকি, অনুমোদন, স্টক সতর্কতা ও ব্যর্থতা বাদ।'));
  end if;
  return jsonb_strip_nulls(jsonb_build_object('date', d, 'scope', case when p_loc is null then 'owner' else 'outlet' end, 'location_id', p_loc, 'location_name_en', outlet_name,
    'generated_at', now(),
    'sales', jsonb_build_object('today', sales_t, 'yesterday', sales_y, 'last_week', sales_w,
       'vs_yesterday_pct', case when (sales_y ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_y ->> 'net')::numeric) * 100 / (sales_y ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (sales_w ->> 'net')::numeric > 0 then round(((sales_t ->> 'net')::numeric - (sales_w ->> 'net')::numeric) * 100 / (sales_w ->> 'net')::numeric, 1) end,
       'by_location', by_loc),
    'cash', cash, 'wallet_receipts', wallets, 'collections', coll, 'wastage', wast,
    'orders', jsonb_build_object('open', open_o, 'cakes_due_tomorrow', cakes, 'cake_specs_due_tomorrow', cake_specs),
    'owner_only', case when p_loc is null then jsonb_build_object('dues', dig -> 'dues', 'approvals_waiting', appr, 'low_stock_items', lowc, 'batches_expiring', expc,
        'red_exceptions', ex_red, 'yellow_exceptions', ex_yellow, 'failed_intake', failed_ifail, 'failed_mail', failed_mail, 'failed_jobs', failed_jobs,
        'backup', st, 'day_close', dig -> 'day_close') end,
    'attention_items', attention, 'nothing_to_report', (attention = 0 and coalesce((sales_t ->> 'bills')::int, 0) = 0),
    'notes', notes));
end $$;

-- ---------- what the script needs: active recipients and the switches (no send from SQL) ----------
create or replace function public.xc_summary_targets() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'on', public.rule_on('xc_summary_on'), 'email_on', public.rule_on('xc_summary_email_on'), 'telegram_on', public.rule_on('xc_summary_telegram_on'),
    'times', coalesce(public.rule_val('xc_summary_times') #>> '{}', '21'),
    'recipients', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'channel', r.channel, 'address', r.address, 'scope', r.scope,
                                       'location_id', r.location_id, 'quiet_when_empty', r.quiet_when_empty) order by r.id)
                              from public.xc_summary_recipients r where r.active), '[]'::jsonb));
end $$;

-- ---------- the script writes one line per send (or failed send); a second 'sent' for the same day is refused by the index ----------
create or replace function public.xc_summary_record(p_run date, p_recipient bigint, p_channel text, p_status text, p_hash text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.xc_summary_recipients; id_ bigint;
begin
  if not public._xc_summary_ok() then raise exception 'not allowed'; end if;
  if p_status not in ('sent', 'failed', 'skipped_empty') then raise exception 'bad_status'; end if;
  if p_channel not in ('email', 'telegram') then raise exception 'bad_channel'; end if;
  select * into r from public.xc_summary_recipients where id = p_recipient;
  if not found then raise exception 'not_found'; end if;
  if r.channel <> p_channel then raise exception 'channel_mismatch'; end if;
  insert into public.xc_summary_log (run_date, recipient_id, channel, scope, location_id, status, content_hash, error)
    values (p_run, r.id, p_channel, r.scope, r.location_id, p_status, left(p_hash, 80), left(p_error, 300)) returning id into id_;
  return jsonb_build_object('ok', true, 'id', id_);
end $$;

create or replace function public.xc_summary_already_sent(p_run date, p_recipient bigint, p_channel text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._xc_summary_ok() and exists (select 1 from public.xc_summary_log where run_date = p_run and recipient_id = p_recipient and channel = p_channel and status = 'sent');
$$;

-- owner history of what went out (no addresses; the log holds ids, status and a short error)
create or replace function public.xc_summary_history(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_owner() then jsonb_build_object('rows', '[]'::jsonb, 'denied', true) else jsonb_build_object('rows', coalesce(jsonb_agg(z order by z.run_date desc, z.id desc), '[]'::jsonb)) end
    from (select l.id, l.run_date, l.channel, l.scope, l.location_id, l.status, l.error, l.created_at, r.name as recipient
            from public.xc_summary_log l left join public.xc_summary_recipients r on r.id = l.recipient_id
           order by l.run_date desc, l.id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) z;
$$;

-- ---------- receipt continuity and "every shop synced?" (server side: what the server has received) ----------
-- Receipts are numbered per place by the app. Inside a period the numbers of one place must run without a gap; a gap is a sale the server never received
-- (or a number that was used offline on another device). The check is a flag for the owner to look at, never an automatic correction.
create or replace function public.xc_sync_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 7); t date := coalesce(p_to, public._today()); stale numeric := public.rule_num('xc_sync_stale_hours'); rows_ jsonb;
begin
  if not (public.is_owner() or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  if t < f or t - f > 120 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(z order by z.location_id), '[]'::jsonb) into rows_ from (
    select base.location_id, base.name, base.sales, base.first_receipt, base.last_receipt, base.receipt_gaps, base.last_sale_ever,
           case when base.sales = 0 then null when base.receipt_gaps > 0 then 'gap' else 'ok' end as receipt_state,
           case when stale is null then 'threshold_not_set' when base.last_sale_ever is null then 'no_sales'
                when base.last_sale_ever < now() - make_interval(hours => stale::int) then 'stale' else 'ok' end as sync_state
      from (
        select l.id as location_id, l.name_en as name, count(s.id) as sales, min(s.receipt) as first_receipt, max(s.receipt) as last_receipt,
               coalesce((max(s.receipt) - min(s.receipt) + 1) - count(distinct s.receipt), 0) as receipt_gaps,
               (select max(x.sold_at) from public.sales x where x.location_id = l.id and x.status = 'done') as last_sale_ever
          from public.locations l left join public.sales s on s.location_id = l.id and s.sale_date between f and t
         where l.is_active and l.status = 'live' and (p_loc is null or l.id = p_loc)
         group by l.id, l.name_en) base) z;
  return jsonb_build_object('from', f, 'to', t, 'stale_hours', stale, 'rows', coalesce(rows_, '[]'::jsonb),
    'notes', jsonb_build_array(
      'receipt_state gap = numbers missing inside the period for that place: check the offline outbox on the phone and the voided bills before assuming a loss.',
      'sync_state uses the time of the last recorded sale (the server has no per-device timestamp in this build); a quiet shop is not a broken one.',
      'threshold_not_set = the owner has not typed the hours; nothing is flagged until then.'));
end $$;

-- sync alert: one in-app warning per outlet per day, only when switched on AND the hours are typed
create or replace function public.xc_sync_alert_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rep jsonb; r jsonb; n int := 0; stale numeric := public.rule_num('xc_sync_stale_hours');
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_sync_alert_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if stale is null then return jsonb_build_object('skipped', 'threshold_not_set'); end if;
  rep := public.xc_sync_report(null, null, null);
  for r in select * from jsonb_array_elements(rep -> 'rows') loop
    if r ->> 'sync_state' = 'stale' then
      if not p_dry then
        perform public._notif_add('sync_stale', 'warn', 'দোকান থেকে বিক্রি আসেনি: ' || (r ->> 'name'), 'No sale received from: ' || (r ->> 'name'),
          'শেষ বিক্রি ' || to_char((select max(sold_at) at time zone 'Asia/Dhaka' from public.sales where location_id = (r ->> 'location_id')::int and status = 'done'), 'DD Mon HH24:MI') || '। সীমা ' || stale || ' ঘণ্টা।',
          'Last sale ' || to_char((select max(sold_at) at time zone 'Asia/Dhaka' from public.sales where location_id = (r ->> 'location_id')::int and status = 'done'), 'DD Mon HH24:MI') || '. Limit ' || stale || ' hours.',
          '#/home', (r ->> 'location_id')::text, 'owner', (r ->> 'location_id')::int);
      end if;
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('stale_outlets', n, 'dry', p_dry);
end $$;

-- ---------- access: closed helpers, reads by signed-in roles only ----------
do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_summary_ok', '_xc_outlet_day') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_summary_compose(date, int) from public, anon;
revoke all on function public.xc_summary_targets() from public, anon;
revoke all on function public.xc_summary_record(date, bigint, text, text, text, text) from public, anon;
revoke all on function public.xc_summary_already_sent(date, bigint, text) from public, anon;
revoke all on function public.xc_summary_history(int) from public, anon;
revoke all on function public.xc_sync_report(date, date, int) from public, anon;
revoke all on function public.xc_sync_alert_scan(boolean) from public, anon;
revoke all on function public.xc_recipient_save(bigint, jsonb) from public, anon;
grant execute on function public.xc_summary_compose(date, int) to authenticated;
grant execute on function public.xc_summary_targets() to authenticated;
grant execute on function public.xc_summary_record(date, bigint, text, text, text, text) to authenticated;
grant execute on function public.xc_summary_already_sent(date, bigint, text) to authenticated;
grant execute on function public.xc_summary_history(int) to authenticated;
grant execute on function public.xc_sync_report(date, date, int) to authenticated;
grant execute on function public.xc_sync_alert_scan(boolean) to authenticated;
grant execute on function public.xc_recipient_save(bigint, jsonb) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase495.sql
-- Phase 495 (XC-2) - DAILY PRODUCTION SUGGESTION, THE BAKER'S CONFIRMATION, AND THE ACCURACY REPORT.
-- Paste AFTER phase494. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_prod_suggest_on (false). Window xc_prod_weeks is BLANK by default: with it blank nothing is suggested ("data needed").
-- A suggestion is arithmetic on the server, not a forecasting model. It writes NOTHING to production_plans: the baker copies or edits the lines in the production screen.
--   EXPECTED   = average sold on the same weekday over the last N weeks, using only TRADING days (a day with a bill) that are not festival days.
--   RANGE      = the lowest and the highest of those days (a range of what happened; NOT a confidence interval; no probability is claimed).
--   FESTIVAL   = an owner-entered festival covering the day shows the owner uplift % as a separate "with uplift" figure (only if the owner typed one).
--   CARRY-OVER = finished stock on hand at the place now (stock_balance); it is subtracted.
--   OPEN ORDERS = production orders for that place due that day (open status); they are added.
--   SUGGESTED  = max(0, expected + open orders - carry-over)   (or the uplifted expected, when a festival uplift applies). Rounded to 2 decimals.
-- Confirmation stores the suggestion AS IT WAS when the baker confirmed, so the accuracy report compares like with like later.
-- Costs are not used. Supplier prices are not used. No weather, no trend, no ML.

do $g$ begin
  if to_regprocedure('public._rb4_prod_view(integer)') is null or to_regprocedure('public._rb4_prod_entry(integer)') is null then raise exception 'phase495 needs phase404'; end if;
  if to_regclass('public.festival_calendar') is null then raise exception 'phase495 needs phase465 (festival calendar)'; end if;
  if to_regclass('public.production_orders') is null then raise exception 'phase495 needs phase404 (production orders)'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_prod_suggest_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'দৈনিক উৎপাদন পরামর্শ / Daily production suggestion: on', 'Shows suggested quantities on the production planning screen. OFF = no suggestion is calculated.', 9510),
 ('xc_prod_weeks', 'number', null::jsonb, 'weeks', 1::numeric, 12::numeric,
   'কত সপ্তাহের একই বারের বিক্রি দেখে পরামর্শ (ফাঁকা = সেট নেই) / Weeks of same-weekday history (blank = not set)', 'Blank = no suggestion, the screen says "data needed: xc_prod_weeks". Nothing is assumed.', 9511)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- what was suggested, confirmed, made and left (append-only per day, place and item; a re-confirm updates the planned figure and keeps the history) ----------
create table if not exists public.xc_prod_feedback (
  id bigint generated by default as identity primary key,
  plan_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  suggested_qty numeric check (suggested_qty is null or suggested_qty >= 0),
  range_low numeric check (range_low is null or range_low >= 0),
  range_high numeric check (range_high is null or range_high >= 0),
  days_used int check (days_used is null or days_used >= 0),
  planned_qty numeric check (planned_qty is null or planned_qty >= 0),           -- what the baker confirmed
  made_qty numeric check (made_qty is null or made_qty >= 0),                    -- what was made (entered later, base unit)
  unsold_qty numeric check (unsold_qty is null or unsold_qty >= 0),              -- left at close (entered later)
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  unique (plan_date, location_id, item_id)
);
alter table public.xc_prod_feedback enable row level security;
revoke all on public.xc_prod_feedback from public, anon, authenticated;
grant select on public.xc_prod_feedback to authenticated;
drop policy if exists xc_prod_feedback_read on public.xc_prod_feedback;
create policy xc_prod_feedback_read on public.xc_prod_feedback for select to authenticated using (public._rb4_prod_view(location_id));
drop trigger if exists audit_xc_prod_feedback on public.xc_prod_feedback;
create trigger audit_xc_prod_feedback after insert or update on public.xc_prod_feedback for each row execute function public.log_change('id');
drop trigger if exists xc_prod_feedback_nodel on public.xc_prod_feedback;
create trigger xc_prod_feedback_nodel before delete on public.xc_prod_feedback for each row execute function public.no_hard_delete();

-- ---------- one place, one day: item sold (quantity in the item base unit as the sale lines carry it) ----------
create or replace function public._xc_sold_day(p_loc int, p_day date) returns table (item_id uuid, qty numeric)
language sql stable security definer set search_path = public as $$
  select (x.l ->> 'item_id')::uuid, sum((x.l ->> 'qty')::numeric)
    from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) x(l)
   where s.status = 'done' and s.location_id = p_loc and s.sale_date = p_day
     and (x.l ->> 'item_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (x.l ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$'
   group by 1;
$$;

-- ---------- the suggestion (read only; writes nothing) ----------
create or replace function public.xc_prod_suggest(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); w int; ndays int; lines_ jsonb; fest jsonb; upl numeric; fest_name text; rows_ jsonb;
begin
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_prod_suggest_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if d > public._today() + 14 or d < public._today() - 400 then raise exception 'bad_date'; end if;
  w := public.rule_num('xc_prod_weeks')::int;
  if w is null then return jsonb_build_object('date', d, 'location_id', p_loc, 'data_needed', jsonb_build_array('xc_prod_weeks'), 'rows', '[]'::jsonb); end if;
  -- festival covering the day (owner-entered; the largest uplift the owner typed)
  select f.name_en, f.uplift_pct into fest_name, upl from public.festival_calendar f
   where f.active and d between f.start_date and f.end_date and (f.location_id is null or f.location_id = p_loc)
   order by f.uplift_pct desc nulls last limit 1;
  -- same weekday, last w weeks; trading days only; festival days left out of the ordinary average
  with days as (select (d - 7 * k)::date as dd from generate_series(1, w) k),
  trading as (select dd from days t where exists (select 1 from public.sales s where s.status = 'done' and s.location_id = p_loc and s.sale_date = t.dd)),
  ordinary as (select t.dd from trading t where not exists (select 1 from public.festival_calendar f where f.active and t.dd between f.start_date and f.end_date and (f.location_id is null or f.location_id = p_loc))),
  sold as (select o.dd, x.item_id, x.qty from ordinary o cross join lateral public._xc_sold_day(p_loc, o.dd) x),
  items as (select distinct sold.item_id from sold),
  grid as (select i.item_id, o.dd, coalesce((select sum(sd.qty) from sold sd where sd.item_id = i.item_id and sd.dd = o.dd), 0) as q from items i cross join ordinary o),
  stat as (select g.item_id, round(avg(g.q), 3) as expected, min(g.q) as lo, max(g.q) as hi from grid g group by g.item_id),
  ord as (select po.item_id, sum(po.qty) as qty from public.production_orders po where po.status = 'open' and po.location_id = p_loc and coalesce(po.due_date, po.order_date) = d group by po.item_id),
  allitems as (select item_id from items union select item_id from ord),
  base as (
    select a.item_id, i.code, i.name_bn, i.name_en,
           coalesce(s.expected, 0) as expected, coalesce(s.lo, 0) as lo, coalesce(s.hi, 0) as hi,
           coalesce(o.qty, 0) as orders, coalesce(sb.qty, 0) as carry
      from allitems a join public.items i on i.id = a.item_id
      left join stat s on s.item_id = a.item_id left join ord o on o.item_id = a.item_id
      left join public.stock_balance sb on sb.item_id = a.item_id and sb.location_id = p_loc)
  select (select count(*) from ordinary), coalesce(jsonb_agg(jsonb_build_object(
      'item_id', b.item_id, 'code', b.code, 'name_bn', b.name_bn, 'name_en', coalesce(b.name_en, b.name_bn),
      'days_used', (select count(*) from ordinary), 'window_weeks', w,
      'expected', b.expected, 'range_low', greatest(0, round(b.lo + b.orders - b.carry, 2)), 'range_high', greatest(0, round(b.hi + b.orders - b.carry, 2)),
      'open_orders', b.orders, 'carry_over', b.carry,
      'festival', fest_name, 'uplift_pct', upl,
      'with_uplift', case when upl is not null then round(greatest(0, b.expected * (1 + upl / 100) + b.orders - b.carry), 2) end,
      'suggested', round(greatest(0, case when upl is not null then b.expected * (1 + upl / 100) else b.expected end + b.orders - b.carry), 2),
      'explanation_en', 'Average of ' || (select count(*) from ordinary) || ' same-weekday trading day(s), range ' || b.lo || ' to ' || b.hi
          || '; plus open orders ' || b.orders || '; minus carry-over ' || b.carry || '.' || case when upl is not null then ' Festival uplift ' || upl || '% shown separately.' else '' end,
      'explanation_bn', 'একই বারের ' || (select count(*) from ordinary) || 'টি বিক্রির দিনের গড়, সীমা ' || b.lo || ' থেকে ' || b.hi
          || '; যোগ: খোলা অর্ডার ' || b.orders || '; বিয়োগ: হাতে থাকা স্টক ' || b.carry || '।' || case when upl is not null then ' উৎসবের বাড়তি ' || upl || '% আলাদা দেখানো।' else '' end)
      order by b.code), '[]'::jsonb)
    into ndays, rows_ from base b;
  return jsonb_build_object('date', d, 'location_id', p_loc, 'window_weeks', w, 'trading_days_used', ndays, 'festival', fest_name, 'uplift_pct', upl,
    'rows', rows_,
    'data_needed', case when ndays = 0 then jsonb_build_array('no_same_weekday_trading_day_in_window') else '[]'::jsonb end,
    'notes', jsonb_build_array(
      'Arithmetic only: an average of past same weekdays, not a forecasting model. No probability is claimed.',
      'The range is the lowest and the highest of the past days, not a confidence interval.',
      'Days without a bill are closed, not zero sales; they are not counted.',
      'Festival days in the past are left out of the ordinary average; the owner uplift is shown separately.',
      'Carry-over is the stock on hand now; re-check it before the baker confirms.'));
end $$;

-- ---------- the baker confirms (stores the suggestion as it stands now, and the planned quantity; a line with no suggestion is stored with blanks) ----------
create or replace function public.xc_prod_confirm(p_date date, p_loc int, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sg jsonb; ln jsonb; x jsonb; it uuid; pq numeric; n int := 0;
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then raise exception 'bad_value'; end if;
  sg := public.xc_prod_suggest(p_date, p_loc);
  if sg ? 'skipped' then raise exception 'suggestion_off'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    it := nullif(ln ->> 'item_id', '')::uuid;
    pq := nullif(ln ->> 'planned_qty', '')::numeric;
    if it is null or pq is null or pq < 0 or pq > 999999999 then raise exception 'bad_value'; end if;
    select z into x from jsonb_array_elements(coalesce(sg -> 'rows', '[]'::jsonb)) z where (z ->> 'item_id')::uuid = it;
    insert into public.xc_prod_feedback (plan_date, location_id, item_id, suggested_qty, range_low, range_high, days_used, planned_qty, created_by)
      values (p_date, p_loc, it, (x ->> 'suggested')::numeric, (x ->> 'range_low')::numeric, (x ->> 'range_high')::numeric, (x ->> 'days_used')::int, pq, auth.uid())
      on conflict (plan_date, location_id, item_id) do update set planned_qty = excluded.planned_qty, suggested_qty = excluded.suggested_qty,
        range_low = excluded.range_low, range_high = excluded.range_high, days_used = excluded.days_used, updated_by = auth.uid(), updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'saved', n);
end $$;

-- ---------- after the day: what was made and what was left (the person enters it; nothing is computed here) ----------
create or replace function public.xc_prod_actual_save(p_date date, p_loc int, p_item uuid, p_made numeric, p_unsold numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_made is not null and (p_made < 0 or p_made > 999999999) then raise exception 'bad_value'; end if;
  if p_unsold is not null and (p_unsold < 0 or p_unsold > 999999999) then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.xc_prod_feedback where plan_date = p_date and location_id = p_loc and item_id = p_item) then raise exception 'not_confirmed'; end if;
  update public.xc_prod_feedback set made_qty = p_made, unsold_qty = p_unsold, note = left(nullif(btrim(p_note), ''), 300), updated_by = auth.uid(), updated_at = now()
   where plan_date = p_date and location_id = p_loc and item_id = p_item;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- accuracy: did the suggestion's range hold the sold quantity? (days with a stored suggestion only; no verdict is written) ----------
create or replace function public.xc_prod_accuracy(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb;
begin
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(z order by z.code, z.location_id), '[]'::jsonb) into rows_ from (
    select fb.location_id, i.code, coalesce(i.name_en, i.name_bn) as name, count(*) as days,
           count(*) filter (where fb.suggested_qty is not null) as with_suggestion,
           round(avg(fb.suggested_qty), 2) as avg_suggested, round(avg(fb.planned_qty), 2) as avg_planned,
           round(avg(coalesce(sd.qty, 0)), 2) as avg_sold,
           round(avg(abs(fb.suggested_qty - coalesce(sd.qty, 0))), 2) as avg_abs_error,
           round(100.0 * count(*) filter (where fb.range_low is not null and coalesce(sd.qty, 0) between fb.range_low and fb.range_high) / nullif(count(*) filter (where fb.range_low is not null), 0), 1) as sold_in_range_pct,
           round(100.0 * count(*) filter (where fb.planned_qty <> fb.suggested_qty) / nullif(count(*) filter (where fb.suggested_qty is not null), 0), 1) as edited_pct,
           round(sum(fb.unsold_qty), 2) as unsold_total, round(sum(fb.made_qty), 2) as made_total
      from public.xc_prod_feedback fb join public.items i on i.id = fb.item_id
      left join lateral (select sum(x.qty) as qty from public._xc_sold_day(fb.location_id, fb.plan_date) x where x.item_id = fb.item_id) sd on true
     where fb.plan_date between f and t and (p_loc is null or fb.location_id = p_loc)
     group by fb.location_id, i.code, i.name_en, i.name_bn) z;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_,
    'notes', jsonb_build_array('Sold = the sales of that day at that place (base unit).', 'sold_in_range_pct counts days when the sold quantity fell inside the suggested range.',
      'A row with few days says little. No verdict is written by the system.'));
end $$;

do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_sold_day') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_prod_suggest(date, int) from public, anon;
revoke all on function public.xc_prod_confirm(date, int, jsonb) from public, anon;
revoke all on function public.xc_prod_actual_save(date, int, uuid, numeric, numeric, text) from public, anon;
revoke all on function public.xc_prod_accuracy(date, date, int) from public, anon;
grant execute on function public.xc_prod_suggest(date, int) to authenticated;
grant execute on function public.xc_prod_confirm(date, int, jsonb) to authenticated;
grant execute on function public.xc_prod_actual_save(date, int, uuid, numeric, numeric, text) to authenticated;
grant execute on function public.xc_prod_accuracy(date, date, int) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase496.sql
-- Phase 496 (XC-3) - SUPPLIER PRICE INTELLIGENCE: last price, 90-day trend, cheapest supplier, costliest ingredients, rise alerts and a recipe-cost preview.
-- Paste AFTER phase495. Paste-twice safe. Earlier phase files are not edited. It does NOT duplicate the purchase-rate trend report (p2_rate_trend, phase434): it links to it.
-- Prices are costs: readable only by the owner, the cost right (rpt_cost_ok) or the recipe-cost right. Browsers never read the tables directly.
-- OFF by default: switch xc_price_alert_on (false). The rise threshold xc_price_rise_pct is BLANK by default: with it blank the alert says "threshold not set" and writes nothing.
-- The alert compares the latest purchase rate of an item from a supplier with the one before it (the same supplier), inside the last 90 days. An alert is an in-app warning only.
-- The recipe preview changes ONE ingredient price on paper and shows the change per batch and per unit. It saves nothing.

do $g$ begin
  if to_regprocedure('public._p26_rates(date,date,integer[])') is null then raise exception 'phase496 needs phase434 (purchase rates)'; end if;
  if to_regprocedure('public._recipe_need(uuid,numeric,integer)') is null then raise exception 'phase496 needs phase74 (recipe need)'; end if;
  if to_regprocedure('public._notif_add(text,text,text,text,text,text,text,text,text,integer)') is null then raise exception 'phase496 needs the notifications helper'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_price_alert_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'ক্রয়মূল্য বৃদ্ধির সতর্কতা / Supplier price-rise alert: on', 'Writes an in-app warning when a purchase rate rises by more than the threshold below. OFF = nothing is checked.', 9520),
 ('xc_price_rise_pct', 'number', null::jsonb, '%', 1::numeric, 500::numeric,
   'কত % বাড়লে সতর্কতা (ফাঁকা = সেট নেই) / Rise % that triggers the alert (blank = not set)', 'Blank = "threshold not set" and nothing is written. Nothing is assumed.', 9521)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- one place of truth for "the rates of the last 90 days" (all places; the cost right decides who reads)
create or replace function public._xc_rates90() returns table (item_id uuid, supplier text, dt date, rate numeric, qty numeric, ord text)
language sql stable security definer set search_path = public as $$
  select r.item_id, r.sname, r.dt, r.rate, r.qty, r.ord from public._p26_rates(public._today() - 90, public._today(), array(select l.id from public.locations l)) r;
$$;

-- the price board (read only). Owner, or a holder of the cost right.
create or replace function public.xc_price_board(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; sup jsonb;
begin
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  with r as (select * from public._xc_rates90()),
  per_sup as (   -- per item and supplier: last rate, the rate before it, first rate, last date, count
    select r.item_id, r.supplier,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate,
           max(r.dt) as last_date, count(*) as n
      from r group by r.item_id, r.supplier),
  cheapest as (select distinct on (item_id) item_id, supplier as cheapest_supplier, last_rate as cheapest_rate
                 from per_sup order by item_id, last_rate asc, supplier),
  spend as (select item_id, sum(qty * rate) as spend90, sum(qty) as qty90 from r group by item_id),
  itm as (select ps.item_id, sum(ps.n) as n, max(ps.last_date) as last_date,
                 (select p.last_rate from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_rate,
                 (select p.supplier from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_supplier,
                 (select r2.rate from r r2 where r2.item_id = ps.item_id order by r2.dt, r2.ord limit 1) as first_rate
            from per_sup ps group by ps.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_code', i.code, 'item_name', coalesce(i.name_en, i.name_bn), 'base_unit', i.base_unit,
      'last_rate', round(x.last_rate, 4), 'last_supplier', x.last_supplier, 'last_date', x.last_date,
      'trend_90d_pct', case when x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end,
      'cheapest_supplier', c.cheapest_supplier, 'cheapest_rate', round(c.cheapest_rate, 4),
      'spend_90d', round(s.spend90, 2), 'qty_90d', round(s.qty90, 3), 'purchase_lines', x.n,
      'see', '#/report/p2_rate_trend')
      order by s.spend90 desc nulls last), '[]'::jsonb)
    into rows_
    from itm x join public.items i on i.id = x.item_id left join cheapest c on c.item_id = x.item_id left join spend s on s.item_id = x.item_id
   where x.last_rate is not null;
  return jsonb_build_object('window_days', 90,
    'items', coalesce(rows_, '[]'::jsonb), 'costliest_by_last_rate', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select e ->> 'item_name' as item_name, e ->> 'last_rate' as last_rate, e ->> 'base_unit' as base_unit
       from jsonb_array_elements(coalesce(rows_, '[]'::jsonb)) e order by (e ->> 'last_rate')::numeric desc nulls last limit greatest(least(coalesce(p_limit, 50), 200), 1)) z),
    'notes', jsonb_build_array('Costs: last purchase rate per base unit. Spend = quantity x rate over the 90 days.',
      'Trend = last rate against the first rate in the window (not a forecast).', 'Full history: the purchase-rate trend report (p2_rate_trend).'));
end $$;

-- the alert scan: latest rate against the previous rate of the SAME supplier, last 90 days; one warning per item and supplier per day
create or replace function public.xc_price_alert_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare thr numeric := public.rule_num('xc_price_rise_pct'); n int := 0; x record; k text;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_price_alert_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if thr is null then return jsonb_build_object('skipped', 'threshold_not_set'); end if;
  for x in
    with r as (select * from public._xc_rates90()),
    ps as (select r.item_id, r.supplier, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
                  max(r.dt) as last_date from r group by r.item_id, r.supplier having count(*) >= 2)
    select ps.item_id, ps.supplier, ps.last_rate, ps.prev_rate, round((ps.last_rate - ps.prev_rate) / ps.prev_rate * 100, 2) as pct, i.code, coalesce(i.name_en, i.name_bn) as nm
      from ps join public.items i on i.id = ps.item_id
     where ps.prev_rate > 0 and (ps.last_rate - ps.prev_rate) / ps.prev_rate * 100 > thr
  loop
    k := left(x.code || '|' || x.supplier, 80);
    if not p_dry then
      perform public._notif_add('price_rise', 'warn', 'ক্রয়মূল্য বেড়েছে: ' || x.nm, 'Purchase price rose: ' || x.nm,
        x.supplier || ' থেকে ' || x.prev_rate || ' থেকে ' || x.last_rate || ' (' || x.pct || '%)।',
        'From ' || x.supplier || ': ' || x.prev_rate || ' to ' || x.last_rate || ' (' || x.pct || '%).',
        '#/report/p2_rate_trend', k, 'owner', null);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('alerts', n, 'threshold_pct', thr, 'dry', p_dry);
end $$;

-- the recipe-cost preview: one ingredient at a new price, on paper (saves nothing)
create or replace function public.xc_recipe_price_preview(p_recipe uuid, p_item uuid, p_new_rate numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare need_ numeric; yb numeric; cur numeric; batch_now jsonb; delta numeric;
begin
  if not (public._recipe_cost_ok() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  if p_new_rate is null or p_new_rate < 0 or p_new_rate > 1000000000 then raise exception 'bad_value'; end if;
  select n.need into need_ from public._recipe_need(p_recipe, 1, 0) n where n.item_id = p_item limit 1;
  if need_ is null then return jsonb_build_object('ingredient_in_recipe', false); end if;
  select public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit) into yb from public.recipes rc where rc.id = p_recipe;
  select (x ->> 'last_rate')::numeric into cur from jsonb_array_elements((public.xc_price_board(1000)) -> 'items') x where x ->> 'item_code' = (select code from public.items where id = p_item);
  if public._recipe_cost_ok() then select public.recipe_cost(p_recipe, null) into batch_now; end if;
  delta := need_ * (p_new_rate - coalesce(cur, 0));
  return jsonb_build_object('ingredient_in_recipe', true, 'need_base_per_batch', round(need_, 4), 'current_rate', cur, 'new_rate', p_new_rate,
    'batch_cost_now', case when batch_now is not null then batch_now -> 'batch_cost' end, 'batch_change', case when cur is not null then round(delta, 4) end,
    'unit_change', case when cur is not null and yb > 0 then round(delta / yb, 6) end, 'yield_base', yb,
    'note', 'Preview only: nothing is saved. Uses the last purchase rate as the current price.');
end $$;

do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_rates90') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_price_board(int) from public, anon;
revoke all on function public.xc_price_alert_scan(boolean) from public, anon;
revoke all on function public.xc_recipe_price_preview(uuid, uuid, numeric) from public, anon;
grant execute on function public.xc_price_board(int) to authenticated;
grant execute on function public.xc_price_alert_scan(boolean) to authenticated;
grant execute on function public.xc_recipe_price_preview(uuid, uuid, numeric) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase497.sql
-- Phase 497 (XC-4) - END-OF-DAY UNSOLD AND MARKDOWN: what cannot sell tomorrow, the outcome of each unsold unit, and wastage share per item and place.
-- Paste AFTER phase496. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_unsold_on (false). The markdown % xc_markdown_pct is BLANK by default: with it blank no discount is suggested and a sale at a discount is refused ("markdown % not set").
-- WHAT IS AT RISK: stock batches (stock_batches) with units left whose expiry falls before the end of the next Dhaka day. A batch with NO expiry is counted and named as "no expiry captured" (not treated as safe, not treated as expiring).
-- OUTCOMES (one line per decision, append-only, void only): sold_discount (sold at the markdown price; value = quantity x sell price x (1 - %)), staff_meal, donation, waste.
--   An outcome line NEVER moves stock or money. A waste that must leave the stock is booked through the existing wastage screen (stock_wastage); this record says so on the answer.
-- A discount sale is taken at the till through the existing coupon/discount rules; this phase does not create a coupon (no new coupon table).
-- WASTAGE SHARE = wastage quantity / (quantity sold + wastage quantity), with both shown. A zero denominator gives a blank, never 0.

do $g$ begin
  if to_regclass('public.stock_batches') is null or to_regclass('public.stock_wastage') is null then raise exception 'phase497 needs the stock phases'; end if;
  if to_regprocedure('public._rb4_prod_entry(integer)') is null then raise exception 'phase497 needs phase404'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_unsold_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'বিক্রি না হওয়া মাল ও ছাড় / Unsold stock and markdown: on', 'Shows the end-of-day list and lets the outcome be recorded. OFF = the list and the records are refused.', 9530),
 ('xc_markdown_pct', 'number', null::jsonb, '%', 1::numeric, 90::numeric,
   'ছাড়ের শতাংশ (ফাঁকা = সেট নেই) / Markdown % (blank = not set)', 'Blank = no discount is suggested and a markdown sale is refused. Nothing is assumed.', 9531)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create table if not exists public.xc_unsold_outcomes (
  id bigint generated by default as identity primary key,
  client_id uuid unique,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  day date not null,
  qty numeric not null check (qty > 0 and qty <= 999999999),                    -- item base unit
  outcome text not null check (outcome in ('sold_discount', 'staff_meal', 'donation', 'waste')),
  discount_pct numeric check (discount_pct is null or (discount_pct > 0 and discount_pct <= 90)),
  unit_price numeric check (unit_price is null or unit_price >= 0),              -- the sell price at the time, less the markdown (sold_discount only)
  value numeric check (value is null or value >= 0),                             -- qty x unit_price (sold_discount only); other outcomes are blank, never 0
  note text check (note is null or length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((outcome = 'sold_discount') = (discount_pct is not null and unit_price is not null and value is not null))
);
create index if not exists xc_unsold_outcomes_day on public.xc_unsold_outcomes (location_id, day);
alter table public.xc_unsold_outcomes enable row level security;
revoke all on public.xc_unsold_outcomes from public, anon, authenticated;
grant select on public.xc_unsold_outcomes to authenticated;
drop policy if exists xc_unsold_outcomes_read on public.xc_unsold_outcomes;
create policy xc_unsold_outcomes_read on public.xc_unsold_outcomes for select to authenticated using (public._rb4_prod_view(location_id));
drop trigger if exists audit_xc_unsold_outcomes on public.xc_unsold_outcomes;
create trigger audit_xc_unsold_outcomes after insert or update on public.xc_unsold_outcomes for each row execute function public.log_change('id');
drop trigger if exists xc_unsold_outcomes_nodel on public.xc_unsold_outcomes;
create trigger xc_unsold_outcomes_nodel before delete on public.xc_unsold_outcomes for each row execute function public.no_hard_delete();

-- the end-of-day list for a place: units left whose expiry falls before the end of the next Dhaka day
create or replace function public.xc_unsold_candidates(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); pct numeric := public.rule_num('xc_markdown_pct'); cutoff timestamptz; rows_ jsonb; noexp jsonb;
begin
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_unsold_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  cutoff := (d + 2)::timestamp at time zone 'Asia/Dhaka';
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_en', coalesce(z.name_en, z.name_bn), 'qty_at_risk', z.qty,
           'earliest_expiry', z.first_exp, 'batches', z.nb, 'sell_price', z.sell_price,
           'markdown_pct', pct, 'markdown_price', case when pct is not null then round(z.sell_price * (1 - pct / 100), 2) end,
           'value_at_markdown', case when pct is not null then round(z.qty * z.sell_price * (1 - pct / 100), 2) end) order by z.first_exp), '[]'::jsonb)
    into rows_
    from (select sb.item_id, i.code, i.name_bn, i.name_en, sum(sb.qty_remaining) as qty, min(sb.expires_at) as first_exp, count(*) as nb, coalesce(i.sell_price, 0) as sell_price
            from public.stock_batches sb join public.items i on i.id = sb.item_id
           where sb.location_id = p_loc and sb.qty_remaining > 0 and sb.expires_at is not null and sb.expires_at < cutoff
           group by sb.item_id, i.code, i.name_bn, i.name_en, i.sell_price) z;
  select jsonb_build_object('batches', count(*), 'units', coalesce(sum(sb.qty_remaining), 0), 'items', count(distinct sb.item_id)) into noexp
    from public.stock_batches sb where sb.location_id = p_loc and sb.qty_remaining > 0 and sb.expires_at is null;
  return jsonb_build_object('date', d, 'location_id', p_loc, 'cutoff', cutoff, 'markdown_pct', pct,
    'data_needed', case when pct is null then jsonb_build_array('xc_markdown_pct') else '[]'::jsonb end,
    'rows', rows_, 'no_expiry_captured', noexp,
    'notes', jsonb_build_array('Units with no expiry date are counted apart and are NOT treated as safe or as expiring.',
      'The markdown price is a suggestion. It is taken at the till through the usual discount rules.'));
end $$;

-- the outcome of one unsold unit line (no stock movement here)
create or replace function public.xc_unsold_record(p_client uuid, p_loc int, p_item uuid, p_day date, p_qty numeric, p_outcome text,
                                                   p_discount_pct numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_unsold_outcomes; it public.items; pct numeric; up numeric; val numeric; nid bigint;
begin
  if not public._rb4_prod_entry(p_loc) and not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_unsold_on') then raise exception 'switch_off'; end if;
  if p_client is not null then
    select * into o from public.xc_unsold_outcomes where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'id', o.id, 'duplicate', true); end if;
  end if;
  if p_outcome not in ('sold_discount', 'staff_meal', 'donation', 'waste') then raise exception 'bad_outcome'; end if;
  if p_qty is null or p_qty <= 0 or p_qty > 999999999 then raise exception 'bad_value'; end if;
  if p_day is null or p_day > public._today() + 1 or p_day < public._today() - 7 then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found then raise exception 'item_not_found'; end if;
  if p_outcome = 'sold_discount' then
    pct := coalesce(p_discount_pct, public.rule_num('xc_markdown_pct'));
    if pct is null then raise exception 'markdown_pct_not_set'; end if;
    if pct <= 0 or pct > 90 then raise exception 'bad_discount'; end if;
    up := round(coalesce(it.sell_price, 0) * (1 - pct / 100), 2);
    val := round(p_qty * up, 2);
  end if;
  insert into public.xc_unsold_outcomes (client_id, location_id, item_id, day, qty, outcome, discount_pct, unit_price, value, note, created_by, created_staff)
    values (p_client, p_loc, p_item, p_day, p_qty, p_outcome, case when p_outcome = 'sold_discount' then pct end, up, val, left(nullif(btrim(p_note), ''), 300), auth.uid(),
            (select staff_id from public.profiles where id = auth.uid()))
    returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid, 'duplicate', false, 'value', val,
    'note', case when p_outcome = 'waste' then 'Stock is not moved by this line: book the waste on the wastage screen.'
                 when p_outcome = 'sold_discount' then 'Stock is not moved by this line: the sale itself is recorded at the till.' else 'Stock is not moved by this line.' end);
end $$;

-- void (never delete): the line stays with the reason
create or replace function public.xc_unsold_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.xc_unsold_outcomes;
begin
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  select * into o from public.xc_unsold_outcomes where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (o.created_by = auth.uid() and (now() - o.created_at) < interval '1 hour' and public._rb4_prod_entry(o.location_id))) then raise exception 'not allowed'; end if;
  if o.state = 'void' then return jsonb_build_object('ok', true, 'duplicate', true); end if;
  update public.xc_unsold_outcomes set state = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- the report: sold, unsold outcomes, wastage and wastage share per item and place, with the denominator shown, and a weekly trend
create or replace function public.xc_unsold_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb; wk jsonb; cost_ok boolean := public.rpt_cost_ok();
begin
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  with sold as (select s.location_id, (x.l ->> 'item_id')::uuid as item_id, sum((x.l ->> 'qty')::numeric) as q
                  from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) x(l)
                 where s.status = 'done' and s.sale_date between f and t and (p_loc is null or s.location_id = p_loc)
                   and (x.l ->> 'item_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and (x.l ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$'
                 group by 1, 2),
  waste as (select w.location_id, w.item_id, sum(w.qty) as q from public.stock_wastage w
             where (w.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or w.location_id = p_loc) group by 1, 2),
  outc as (select o.location_id, o.item_id, sum(o.qty) filter (where o.outcome = 'sold_discount') as disc_q, sum(o.value) filter (where o.outcome = 'sold_discount') as disc_v,
                  sum(o.qty) filter (where o.outcome = 'staff_meal') as staff_q, sum(o.qty) filter (where o.outcome = 'donation') as don_q,
                  sum(o.qty) filter (where o.outcome = 'waste') as outw_q
             from public.xc_unsold_outcomes o where o.state = 'active' and o.day between f and t and (p_loc is null or o.location_id = p_loc) group by 1, 2),
  keys as (select location_id, item_id from sold union select location_id, item_id from waste union select location_id, item_id from outc)
  select coalesce(jsonb_agg(jsonb_build_object('location_id', k.location_id, 'item_code', i.code, 'item_name', coalesce(i.name_en, i.name_bn),
      'sold_qty', coalesce(s.q, 0), 'wastage_qty', coalesce(w.q, 0),
      'wastage_share_pct', case when coalesce(s.q, 0) + coalesce(w.q, 0) > 0 then round(100 * coalesce(w.q, 0) / (coalesce(s.q, 0) + coalesce(w.q, 0)), 1) end,
      'share_denominator', coalesce(s.q, 0) + coalesce(w.q, 0),
      'markdown_sold_qty', o.disc_q, 'markdown_value', o.disc_v, 'staff_meal_qty', o.staff_q, 'donation_qty', o.don_q, 'outcome_waste_qty', o.outw_q,
      'wastage_value_at_current_avg_cost', case when cost_ok then round(coalesce(w.q, 0) * coalesce(sb.avg_cost, 0), 2) end)
      order by i.code, k.location_id), '[]'::jsonb) into rows_
    from keys k join public.items i on i.id = k.item_id
    left join sold s on s.location_id = k.location_id and s.item_id = k.item_id
    left join waste w on w.location_id = k.location_id and w.item_id = k.item_id
    left join outc o on o.location_id = k.location_id and o.item_id = k.item_id
    left join public.stock_balance sb on sb.location_id = k.location_id and sb.item_id = k.item_id;
  -- weekly trend of the wastage share for the whole selection (all items together, with its denominator)
  select coalesce(jsonb_agg(z order by z.week), '[]'::jsonb) into wk from (
    select date_trunc('week', x.day)::date as week,
           sum(x.sold) as sold, sum(x.wasted) as wasted,
           case when sum(x.sold) + sum(x.wasted) > 0 then round(100 * sum(x.wasted) / (sum(x.sold) + sum(x.wasted)), 1) end as share_pct
      from (select s.sale_date as day, sum((l.v ->> 'qty')::numeric) as sold, 0::numeric as wasted
              from public.sales s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) l(v)
             where s.status = 'done' and s.sale_date between f and t and (p_loc is null or s.location_id = p_loc)
               and (l.v ->> 'qty') ~ '^[0-9]+(\.[0-9]+)?$' group by s.sale_date
            union all
            select (w.made_at at time zone 'Asia/Dhaka')::date, 0, sum(w.qty) from public.stock_wastage w
             where (w.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or w.location_id = p_loc) group by 1) x
     group by 1) z;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_, 'weekly_share', wk,
    'notes', jsonb_build_array('Wastage share = wasted / (sold + wasted); both are shown. Blank = no sales and no waste to compare.',
      'Waste value uses the current average cost, shown only to the cost right; it is not the cost at the time of waste.',
      'Outcome lines (markdown, staff meal, donation) are records; they are not stock movements.'));
end $$;

revoke all on function public.xc_unsold_candidates(date, int) from public, anon;
revoke all on function public.xc_unsold_record(uuid, int, uuid, date, numeric, text, numeric, text) from public, anon;
revoke all on function public.xc_unsold_void(bigint, text) from public, anon;
revoke all on function public.xc_unsold_report(date, date, int) from public, anon;
grant execute on function public.xc_unsold_candidates(date, int) to authenticated;
grant execute on function public.xc_unsold_record(uuid, int, uuid, date, numeric, text, numeric, text) to authenticated;
grant execute on function public.xc_unsold_void(bigint, text) to authenticated;
grant execute on function public.xc_unsold_report(date, date, int) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase498.sql
-- Phase 498 (XC-5) - STAFF COACHING BOARD (OWNER ONLY): per person, the figures that already exist, side by side. No rankings, no scores, no public view.
-- Paste AFTER phase497. Paste-twice safe. Earlier phase files are not edited.
-- OFF by default: switch xc_coaching_on (false). Only the owner can read it, even when the switch is on.
-- The figures come from records that already exist: sales (sales, discounts, voids), cash shortage cases, production runs and their losses, attendance days (late minutes),
-- and complaints. A person with no record for a figure shows a blank, never 0. People are matched to a person's record by their staff id (profiles.staff_id) and by the employee link.
-- Shift and role awareness: not built in this phase (noted on the answer). The board does not judge; it lists what happened in the chosen period.
-- Reads personal data: nothing is shown to any other role, and the rows carry no rank field.

do $g$ begin
  if to_regclass('public.attendance_days') is null or to_regclass('public.shortage_cash_cases') is null or to_regclass('public.production_loss') is null then
    raise exception 'phase498 needs phases 404, 412 (attendance) and the shortage cases';
  end if;
  if to_regclass('public.crm_complaints') is null then raise exception 'phase498 needs the complaints table (CRM-H)'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_coaching_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'কর্মী পর্যালোচনা বোর্ড (শুধু মালিক) / Staff coaching board (owner only): on', 'Owner-only view of the figures that already exist per person. OFF = nothing is shown to anyone.', 9540)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

create or replace function public.xc_staff_board(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._today() - 30); t date := coalesce(p_to, public._today()); rows_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_coaching_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if t < f or t - f > 400 then raise exception 'bad_range'; end if;
  with
  emp as (select p.staff_id, p.full_name, e.id as employee_id from public.profiles p left join public.employees e on e.profile_id = p.id where p.staff_id is not null),
  sales_ as (select s.created_staff as sid, count(*) filter (where s.status = 'done') as sales_n, sum(s.total) filter (where s.status = 'done') as sales_amt,
                    count(*) filter (where s.status = 'done' and s.discount > 0) as disc_n, sum(s.discount) filter (where s.status = 'done') as disc_amt
               from public.sales s where s.sale_date between f and t and (p_loc is null or s.location_id = p_loc) and s.created_staff is not null group by 1),
  voids as (select s.void_staff as sid, count(*) as void_n from public.sales s where s.status = 'void' and s.void_staff is not null
              and (s.void_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or s.location_id = p_loc) group by 1),
  cash as (select e.staff_id as sid, sum(c.amount) as short_amt, count(*) as short_n from public.shortage_cash_cases c join emp e on e.employee_id = c.employee_id
            where c.void_at is null and c.case_date between f and t and (p_loc is null or c.location_id = p_loc) group by 1),
  prod as (select pr.created_staff as sid, sum(pr.yield_base) as yield_n from (select r.*, p.staff_id as created_staff from public.production_runs r join public.profiles p on p.id = r.created_by) pr
            where pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  rej as (select pr.created_staff as sid, sum(l.qty) as reject_q from public.production_loss l join (select r.id, p.staff_id as created_staff, r.location_id, r.made_at from public.production_runs r join public.profiles p on p.id = r.created_by) pr on pr.id = l.run_id
           where l.status = 'active' and l.kind = 'reject' and (pr.made_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or pr.location_id = p_loc) group by 1),
  att as (select e.staff_id as sid, count(*) as days, count(*) filter (where a.late_minutes > 0) as late_days, sum(a.late_minutes) as late_min
            from public.attendance_days a join emp e on e.employee_id = a.employee_id where a.day between f and t and (p_loc is null or a.location_id = p_loc) group by 1),
  cmp as (select c.created_staff as sid, count(*) as complaints from public.crm_complaints c where c.created_at::date between f and t and (p_loc is null or c.location_id = p_loc) and c.created_staff is not null group by 1),
  people as (select sid from sales_ union select sid from voids union select sid from cash union select sid from prod union select sid from rej union select sid from att union select sid from cmp)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', pe.sid, 'name', coalesce(em.full_name, pe.sid),
      'sales_bills', sa.sales_n, 'sales_amount', round(sa.sales_amt, 2), 'discount_bills', sa.disc_n, 'discount_amount', round(sa.disc_amt, 2),
      'discount_share_pct', case when coalesce(sa.sales_n, 0) > 0 then round(100.0 * sa.disc_n / sa.sales_n, 1) end,
      'voids', v.void_n,
      'cash_shortage_cases', ca.short_n, 'cash_shortage_amount', round(ca.short_amt, 2),
      'production_yield', round(pd.yield_n, 3), 'production_reject', round(rj.reject_q, 3),
      'reject_share_pct', case when coalesce(pd.yield_n, 0) > 0 then round(100 * coalesce(rj.reject_q, 0) / pd.yield_n, 1) end,
      'attendance_days', at.days, 'late_days', at.late_days, 'late_minutes', at.late_min,
      'complaints', cm.complaints)
      order by coalesce(em.full_name, pe.sid)), '[]'::jsonb) into rows_
    from people pe
    left join emp em on em.staff_id = pe.sid
    left join sales_ sa on sa.sid = pe.sid left join voids v on v.sid = pe.sid left join cash ca on ca.sid = pe.sid
    left join prod pd on pd.sid = pe.sid left join rej rj on rj.sid = pe.sid left join att at on at.sid = pe.sid left join cmp cm on cm.sid = pe.sid;
  return jsonb_build_object('from', f, 'to', t, 'location_id', p_loc, 'rows', rows_, 'owner_only', true,
    'notes', jsonb_build_array('Owner only. Figures are for the period shown and are not a score. No ranking is shown.',
      'A blank means no record for that figure; it is not zero.', 'Shift and role are not taken into account in this version.'));
end $$;

revoke all on function public.xc_staff_board(date, date, int) from public, anon;
grant execute on function public.xc_staff_board(date, date, int) to authenticated;

notify pgrst, 'reload schema';

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

-- ============================================================================
-- End of FRESH part 19 of 21.
