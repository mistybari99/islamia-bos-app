-- ===================== phase97.sql =====================
-- Phase 97 (bos97) - W1-F / U-10: CUSTOMER RECEIPT CHANNELS. Bank and cheque on collections and POS split payments, payment source (money account) on customer receipts, reference rules.
-- Paste after phase96 (which needs phase87). Paste-twice safe. Earlier phase files are not edited. collect_payment, record_sale2 and the other shared functions are NOT re-created here:
-- every change to a shared function is a HOOK written in docs/integration/W1-F.md (tests/sql/w1f_hooks97.sql is the exact text, proved on a scratch copy by phase97_test.sql).
--
-- WHAT THIS ADDS
--   * sale_payments.mode accepts 'bank' (and sales.pay_mode too). A cheque is a bank receipt with cheque_no (and cheque_date). New columns: money_account_id, cheque_no, cheque_date, ref_waiver.
--   * Two new event types in money_event_settings: customer_collection (a due paid later) and pos_split_payment (money taken with a sale). They work exactly like the 14 phase87 events:
--     default account, owner fixed source, source required, one-off owner exceptions. The money account travels IN BAND as "ma#<id>;" in front of the wallet text (what web/pay.js already sends when
--     a row has a payment source) or in the column money_account_id.
--   * A BEFORE INSERT trigger on sale_payments resolves the source, sets the mode from the account, refuses bank mode while the switch is OFF and checks the reference rule.
--   * A new route _w1f_collect_payment (same contract as collect_payment plus bank, cheque, money_account_id, reference and an exception reason per payment) so the shared collect_payment need not change;
--     the hook that makes collect_payment itself accept the same fields is in the integration note.
--   * _w1f_receipt_settings and _w1f_receipts_list for the screen.
-- SETTINGS (rules, every change is in audit_log):
--   receipt_bank_on           OFF    bank / cheque receipts are accepted (today's behaviour: refused with bad_mode)
--   receipt_ref_required      off    off | bank (bank receipts need a transaction or cheque number) | bank_mobile (mobile wallet receipts too)
--   receipt_ref_from          blank  the reference rule applies to payments dated on or after this day (blank = at once)
-- A missing reference can be waived per payment with a written reason (ref_waiver): audit_log line + a yellow line in the Exceptions list. Books balance is not involved, so the rule may be waived.
-- Nothing changes for an existing install: with the three settings at their defaults and no money account chosen, every payment is stored exactly as before.

do $g$ begin
  if to_regprocedure('public._w1f_present96()') is null then raise exception 'phase97 needs phase96 (and phase87) first'; end if;
  if to_regclass('public.sale_payments') is null or to_regprocedure('public.customer_balance(uuid)') is null then raise exception 'phase97 needs the POS tables'; end if;
end $g$;

create or replace function public._w1f_present97() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, choices, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('receipt_bank_on', 'pos', 'switch', 'false', null, 'Accept bank transfer and cheque from customers', 'Accept bank transfer and cheque from customers', 'Accept bank transfer and cheque from customers',
  'OFF = only cash, mobile and card', 'OFF (default) = a customer payment can only be cash, mobile or card, as today. ON = bank transfer and cheque (a cheque is a bank receipt with its cheque number) are accepted on due collections and POS split payments.', 962),
 ('receipt_ref_required', 'pos', 'choice', '"off"', '["off","bank","bank_mobile"]', 'Reference number needed on bank receipts', 'Reference number needed on bank receipts', 'Reference number needed on customer bank receipts',
  'off | bank | bank_mobile', 'off (default) = never. bank = a bank or cheque receipt needs a transaction number or a cheque number. bank_mobile = mobile wallet receipts need one too. A missing number can be waived with a written reason.', 963),
 ('receipt_ref_from', 'pos', 'text', null, null, 'The reference rule counts from this date', 'The reference rule counts from this date', 'The reference rule counts from this date (YYYY-MM-DD)',
  'Blank = at once', 'Blank = at once. When set, a payment dated before it is never asked for a number, so an old figure is never touched.', 964)
on conflict (key) do nothing;

-- ---------- columns and constraints ----------
alter table public.sale_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.sale_payments add column if not exists cheque_no text;
alter table public.sale_payments add column if not exists cheque_date date;
alter table public.sale_payments add column if not exists ref_waiver text;
do $c$ declare d text; ck record; begin
  for ck in select * from (values ('sale_payments', 'sale_payments_mode_check', 'array[''cash'',''mobile'',''card'',''bank'']'), ('sales', 'sales_pay_mode_check', 'array[''cash'',''mobile'',''card'',''due'',''split'',''bank'']')) v(t, n, arr) loop
    select pg_get_constraintdef(c.oid) into d from pg_constraint c where c.conrelid = ('public.' || ck.t)::regclass and c.conname = ck.n;
    if d is not null and position('bank' in d) = 0 then
      execute format('alter table public.%I drop constraint %I', ck.t, ck.n);
      execute format('alter table public.%I add constraint %I check (%s)', ck.t, ck.n, case ck.t when 'sale_payments' then 'mode' else 'pay_mode' end || ' = any (' || ck.arr || ')');
    end if;
  end loop;
  if not exists (select 1 from pg_constraint where conrelid = 'public.sale_payments'::regclass and conname = 'sale_payments_w1f_len') then
    alter table public.sale_payments add constraint sale_payments_w1f_len check ((cheque_no is null or length(cheque_no) <= 40) and (ref_waiver is null or length(ref_waiver) <= 200));
  end if;
end $c$;
create index if not exists sale_payments_money_acc on public.sale_payments (money_account_id) where money_account_id is not null;

insert into public.money_event_settings (event_type, label_en, dir, sort) values
 ('customer_collection', 'Customer payment of a due (collection)', 'in', 160),
 ('pos_split_payment', 'Customer payment taken with a sale (POS)', 'in', 170)
on conflict (event_type) do nothing;

-- ---------- helpers ----------
create or replace function public._w1f_receipt_modes() returns text[] language sql stable security definer set search_path = public as $$
  select case when public.rule_on('receipt_bank_on') then array['cash', 'mobile', 'card', 'bank'] else array['cash', 'mobile', 'card'] end $$;
-- readers of one payment object (used by the hook text of collect_payment and record_sale2)
create or replace function public._w1f_pj_text(p jsonb, k text, n int) returns text language sql immutable as $$ select left(nullif(btrim(p ->> k), ''), n) $$;
create or replace function public._w1f_pj_date(p jsonb, k text) returns date language plpgsql immutable as $$
begin return nullif(btrim(p ->> k), '')::date; exception when others then raise exception 'bad_date'; end $$;
create or replace function public._w1f_pj_acc(p jsonb) returns bigint language sql immutable as $$ select case when (p ->> 'money_account_id') ~ '^[0-9]{1,12}$' then (p ->> 'money_account_id')::bigint end $$;

-- ---------- the BEFORE INSERT trigger of sale_payments ----------
create or replace function public._w1f_sp_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare ac bigint; rest text; ev text; src record; usr boolean := auth.uid() is not null; refreq text; frm text; need boolean; dt date;
begin
  select u.acc, u.rest into ac, rest from public._m_untag(new.wallet) u;                   -- the in-band tag "ma#<id>;" of the payment source picker
  if ac is not null then new.wallet := rest; end if;
  ac := coalesce(ac, new.money_account_id);
  dt := (new.paid_at at time zone 'Asia/Dhaka')::date;
  if new.mode = 'bank' and usr and not public.rule_on('receipt_bank_on') then raise exception 'receipt_bank_off'; end if;
  ev := case when new.kind = 'collection' then 'customer_collection' else 'pos_split_payment' end;
  select * into src from public._w1f_pick_source(ev, ac, new.location_id, new.mode, new.amount, new.client_id, dt, 'sale_payments');
  if src.o_acc is not null then
    new.money_account_id := src.o_acc; new.mode := src.o_mode; new.wallet := null;
  end if;
  if nullif(btrim(coalesce(new.cheque_no, '')), '') is not null and new.mode <> 'bank' then raise exception 'cheque_needs_bank'; end if;
  new.ref := nullif(btrim(coalesce(new.ref, '')), '');
  new.cheque_no := nullif(btrim(coalesce(new.cheque_no, '')), '');
  new.ref_waiver := nullif(btrim(coalesce(new.ref_waiver, '')), '');
  -- reference rule (a setting; may be waived with a reason because it is not about balancing the books)
  refreq := coalesce(public.rule_txt('receipt_ref_required'), 'off'); frm := public.rule_txt('receipt_ref_from');
  need := usr and refreq <> 'off' and (new.mode = 'bank' or (refreq = 'bank_mobile' and new.mode = 'mobile'))
          and (frm is null or frm !~ '^\d{4}-\d{2}-\d{2}$' or dt >= frm::date);
  if need and new.ref is null and new.cheque_no is null then
    if new.ref_waiver is null or length(new.ref_waiver) < 3 then raise exception 'receipt_reference_required'; end if;
    perform public._w1f_audit('receipt_reference_waived', 'sale_payments', coalesce(new.client_id::text, new.sale_id::text, '-'),
      jsonb_build_object('kind', new.kind, 'mode', new.mode, 'amount', new.amount, 'location_id', new.location_id, 'reason', new.ref_waiver));
    perform public._w1f_exception('POS', new.location_id, dt, 'receipt_reference_waived', new.amount, 'Receipt without a reference number: ' || new.ref_waiver);
  end if;
  return new;
end $$;

create or replace function public._w1f_sp_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id then raise exception 'money_account_fixed'; end if;
  if new.cheque_no is distinct from old.cheque_no or new.cheque_date is distinct from old.cheque_date then raise exception 'cheque_fixed'; end if;
  return new;
end $$;

drop trigger if exists w1f_sp_bi on public.sale_payments;
create trigger w1f_sp_bi before insert on public.sale_payments for each row execute function public._w1f_sp_bi();
drop trigger if exists w1f_sp_bu on public.sale_payments;
create trigger w1f_sp_bu before update on public.sale_payments for each row execute function public._w1f_sp_bu();

-- ---------- the new route: collect a due with bank, cheque, a payment source and a reference ----------
-- Same contract and checks as collect_payment (POS permission, place, one collection at a time per customer, repeat of the same client id returns the first answer, never more than the due),
-- plus per payment: money_account_id, ref, cheque_no, cheque_date, exception_reason (waives a missing reference).
create or replace function public._w1f_collect_payment(p_client uuid, p_loc integer, p_customer uuid, p_payments jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; modes text[] := public._w1f_receipt_modes(); ids bigint[] := '{}'; nid bigint; cheque_d date;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if p_client is not null and exists (select 1 from public.sale_payments where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', public.customer_balance(p_customer));
  end if;
  if p_payments is null or jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then raise exception 'no_payments'; end if;
  for pay in select * from jsonb_array_elements(p_payments) loop
    pm := pay ->> 'mode'; amt := (pay ->> 'amount')::numeric;
    if pm is null or pm <> all (modes) then raise exception 'bad_mode'; end if;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    if (pay ->> 'money_account_id') is not null and public._w1f_pj_acc(pay) is null then raise exception 'unknown_money_account'; end if;
    tot := tot + round(amt, 2);
  end loop;
  bal := coalesce(public.customer_balance(p_customer), 0);
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay ->> 'mode', public._w1f_pj_text(pay, 'wallet', 30), public._w1f_pj_text(pay, 'ref', 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'),
              public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay ->> 'amount')::numeric, 2), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client)
      returning id into nid;
    ids := ids || nid;
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot, 'ids', to_jsonb(ids));
end $$;

-- ---------- screen readers ----------
create or replace function public._w1f_receipt_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('bank_on', public.rule_on('receipt_bank_on'), 'ref_required', coalesce(public.rule_txt('receipt_ref_required'), 'off'), 'ref_from', public.rule_txt('receipt_ref_from'),
    'modes', to_jsonb(public._w1f_receipt_modes()),
    'events', coalesce((select jsonb_agg(jsonb_build_object('event_type', s.event_type, 'default_account_id', s.default_account_id, 'allow_override', s.allow_override, 'require_source', s.require_source))
                          from public.money_event_settings s where s.event_type in ('customer_collection', 'pos_split_payment')), '[]'::jsonb));
end $$;

create or replace function public._w1f_receipts_list(p_loc int default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public._acct_view()) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.paid_at desc, z.id desc) from (
      select p.id, p.kind, p.location_id, p.mode, p.amount, p.paid_at, p.ref, p.cheque_no, p.cheque_date, p.money_account_id, a.name_en as account_name, p.ref_waiver, p.voided, p.void_note,
             c.name as customer_name, c.mobile as customer_mobile, s.receipt, p.created_staff
        from public.sale_payments p left join public.money_accounts a on a.id = p.money_account_id left join public.customers c on c.id = p.customer_id left join public.sales s on s.id = p.sale_id
       where (p.mode = 'bank' or p.money_account_id is not null or p.cheque_no is not null) and (p_loc is null or p.location_id = p_loc) and public.can_loc(p.location_id)
         and (p.paid_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2100-01-01')
       order by p.paid_at desc, p.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $pv$ declare f record; pub text[] := array['_w1f_collect_payment', '_w1f_receipt_settings', '_w1f_receipts_list'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
       ('_w1f_receipt_modes', '_w1f_pj_text', '_w1f_pj_date', '_w1f_pj_acc', '_w1f_sp_bi', '_w1f_sp_bu', '_w1f_collect_payment', '_w1f_receipt_settings', '_w1f_receipts_list', '_w1f_present97') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (pub) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $pv$;

-- ===================== phase98.sql =====================
-- Phase 98 (bos98, package W1-G, items U-11 and U-12) - JOURNAL FRESHNESS, SWITCH-COUPLING WARNING, DATA-PROTECTION SETTINGS.
-- Paste AFTER phase87 (needs the phase 40/72/87 accounting engine). Paste-twice safe. No earlier phase file is edited, no shared function is re-created.
-- The wave integrator (I-1, phase 99) wires the hooks written in docs/integration/W1-G.md; nothing here changes a figure, a screen or a workflow by itself.
--
-- WHY (plan U-11, A-29, G30, G33, G2): the books fill only when an authorised person opens Accounts. Turning on forms_post_to_ledger silently locks four stock screens.
-- WHAT THIS FILE ADDS (every new name starts _w1g_ / w1g_ so it cannot clash with another package)
--   1. _w1g_post_scheduled(p_dry)   scheduled poster. Same engine calls as acct_post_pending (_acct_docs -> _acct_resolve -> _acct_write / _acct_reverse, same
--                                   advisory lock, same acct_post_errors72 bookkeeping), plus: a watermark per source type (w1g_post_watermark), a cap per run,
--                                   fair rotation between source types, an optional source-type list and look-back window, one audit_log line per run that posted.
--                                   OFF by default (rule journal_sched_post_on). Called by the existing notify workflow (ops bot, purpose notify) or by the owner /
--                                   accounts manager, or from pg_cron when the database offers it [unverified: plan]. A dry run never writes and works while OFF.
--   2. _w1g_freshness()             data for the "last posted at" strip on Home and Accounts (read only).
--   3. _w1g_acct_readiness()        G2: start date, switch, opening entry, mappings, waiting documents, posting errors, scheduler state (read only).
--   4. _w1g_switch_coupling_warning(key, value) + _w1g_switch_coupling_ack(...)   the text shown BEFORE a coupled switch is saved: what locks / unlocks.
--      Rule switch_coupling_warning = off | warn (default) | confirm. In confirm mode a server trigger refuses turning a coupled switch ON without a fresh owner
--      confirmation, so a hidden button is also a refused request.
--   5. U-12 settings read by tools/backup_dump.py: backup_encrypt_on (OFF), backup_retention_days (blank). _w1g_backup_settings() for the backup bot.
-- DEFAULTS: every new rule defaults to OFF or blank, so with the defaults the books, reports and workflows behave exactly as before (proved by
-- tests/sql/phase98_before_after.sh). Re-pasting an older phase does not touch anything here (no shared function is patched).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase98 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regprocedure('public._acct_reverse(bigint,date,text,uuid)') is null or to_regprocedure('public._is_ops(text)') is null
     or to_regclass('public.acct_post_errors72') is null or to_regclass('public.path_domains') is null then
    raise exception 'phase98 needs the accounting engine (phase 40, 46, 48, 72) first';
  end if;
end $g$;

create or replace function public._w1g_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). Every row: safe default, English label and hint. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('journal_sched_post_on', 'books', 'switch', 'false'::jsonb, null, null, null, null,
  'Post new documents to the books on a schedule', 'Post new documents to the books on a schedule', 'Post new documents to the books on a schedule',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.',
  'OFF = the books fill only when someone presses Post now or opens Accounts (today). ON = the 30-minute notify job posts waiting documents by itself. Needs Accounting on and a start date.', 900),
 ('journal_sched_post_cap', 'books', 'number', '1500'::jsonb, 'documents', null, 1, 5000, 'Most documents one scheduled run may post', 'Most documents one scheduled run may post', 'Most documents one scheduled run may post',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.',
  'A technical batch size, not a business limit (1500 = the same batch as Post now). Documents over the cap wait for the next run, oldest first.', 901),
 ('journal_sched_post_types', 'books', 'text', null, null, null, null, null, 'Scheduled posting: only these source types', 'Scheduled posting: only these source types', 'Scheduled posting: only these source types',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.',
  'Blank = every source type. Otherwise a comma list such as sale,sale_return. Types left out are still posted by Post now.', 902),
 ('journal_sched_post_lookback_days', 'books', 'number', null, 'days', null, 1, 3650, 'Scheduled posting: look back this many days', 'Scheduled posting: look back this many days', 'Scheduled posting: look back this many days',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.',
  'Blank = scan every document since the accounting start date (slowest, safest). A number makes each run look only at the last N days; older leftovers need Post now.', 903),
 ('journal_stale_warn_hours', 'books', 'number', null, 'hours', null, 1, 8760, 'Warn when waiting documents are not posted for this many hours', 'Warn when waiting documents are not posted for this many hours',
  'Warn when waiting documents are not posted for this many hours',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.',
  'Blank = the "last posted at" strip never turns red (it only shows the facts). A number turns it red when documents wait and nothing was posted for that long.', 904),
 ('switch_coupling_warning', 'settings', 'choice', '"warn"'::jsonb, null, '["off","warn","confirm"]'::jsonb, null, null, 'Warning before a switch that locks other screens', 'Warning before a switch that locks other screens', 'Warning before a switch that locks other screens',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.',
  'off = no warning. warn = the screen shows what the switch will lock or unlock before it is saved (default; changes nothing else). confirm = the owner must also tick a confirmation, enforced on the server.', 910),
 ('backup_encrypt_on', 'notify', 'switch', 'false'::jsonb, null, null, null, null, 'Encrypt the nightly backup files', 'Encrypt the nightly backup files', 'Encrypt the nightly backup files',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.',
  'Keep OFF until the owner holds the passphrase (secret BACKUP_PASSPHRASE). ON with no passphrase makes the backup FAIL on purpose; it never falls back to plain files. Restore needs the same passphrase.', 920),
 ('backup_retention_days', 'notify', 'number', null, 'days', null, 1, 36500, 'Keep dated backup folders for this many days', 'Keep dated backup folders for this many days', 'Keep dated backup folders for this many days',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.',
  'Blank = keep every dated folder (today). A number lets tools/backup_retention.py list (and, only when told to, remove) older dated folders. The newest folder is never removed. Git history still holds old files.', 921)
on conflict (key) do nothing;

-- ============================================================================
-- 2. STATE TABLES (no browser access; read only through the definer functions below)
-- ============================================================================
create table if not exists public.w1g_post_watermark (            -- one row per journal source type the scheduler has seen
  source_type text primary key,
  last_run_at timestamptz,                  -- last run in which a document of this type was handled (rotation: the type served longest ago goes first)
  last_posted_at timestamptz,               -- last time the scheduler posted or reversed a document of this type
  last_posted_date date,                    -- document date of the newest document the scheduler posted
  posted_total bigint not null default 0,
  reversed_total bigint not null default 0,
  pending_after int not null default 0,     -- still waiting after the last run (over the cap, period locked, or failed)
  capped_after int not null default 0,
  locked_after int not null default 0,
  errors_after int not null default 0,
  oldest_pending date,
  watermark_date date,                      -- everything of this type dated up to here was posted at the last run (today when nothing waits)
  updated_at timestamptz not null default now()
);
create table if not exists public.w1g_sched_state (               -- one row: when the scheduler last looked, even when there was nothing to post
  id int primary key check (id = 1),
  last_run_at timestamptz, last_run_by uuid, last_via text, last_result jsonb
);
create table if not exists public.w1g_post_runs (                 -- append only: one line per real run that posted, reversed, failed or hit the cap
  id bigserial primary key,
  at timestamptz not null default now(),
  run_by uuid, via text not null,
  posted int not null default 0, reversed int not null default 0, locked int not null default 0, errors int not null default 0,
  capped boolean not null default false, left_after int not null default 0, floor_date date, by_type jsonb
);
create table if not exists public.w1g_switch_acks (               -- owner confirmations used by switch_coupling_warning = confirm (single use)
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid not null, rule_key text not null, new_value jsonb, note text,
  used_at timestamptz
);
do $t$ declare t text; begin
  foreach t in array array['w1g_post_watermark', 'w1g_sched_state', 'w1g_post_runs', 'w1g_switch_acks'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;

-- ============================================================================
-- 3. SCHEDULED POSTER
-- ============================================================================
create or replace function public._w1g_bump(j jsonb, ty text, k text) returns jsonb language sql immutable as $$
  select jsonb_set(case when j ? ty then j else jsonb_set(j, array[ty], '{}'::jsonb) end, array[ty, k], to_jsonb(coalesce((j #>> array[ty, k])::int, 0) + 1)) $$;
create or replace function public._w1g_oldest(j jsonb, ty text, d date) returns jsonb language sql immutable as $$
  select case when d is null or (j #>> array[ty, 'oldest']) is not null and (j #>> array[ty, 'oldest'])::date <= d then j
         else jsonb_set(case when j ? ty then j else jsonb_set(j, array[ty], '{}'::jsonb) end, array[ty, 'oldest'], to_jsonb(d::text)) end $$;

create or replace function public._w1g_post_scheduled(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); via text; st date; today date := public._acct_today(); cap int; lb int; floor_ date; types text[]; txt text;
        d record; orig public.journal_entries; ln jsonb; rdate date; eid bigint; n int := 0; posted int := 0; rev int := 0; locked int := 0; waiting int := 0; nerr int := 0;
        capped boolean := false; left_ int := 0; bt jsonb := '{}'; errs jsonb := '[]'; ty text; k text; rid bigint; sid text; res jsonb; seen text[] := '{}';
begin
  -- who may call: the notify bot, the owner, an accounts manager; or the database's own scheduler (no login, role none) - never a browser session without a login
  if uid is not null then
    if not (public._is_ops('notify') or public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
    via := case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  else
    if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
    via := 'database_scheduler';
  end if;
  if not p_dry and not public.rule_on('journal_sched_post_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  st := public._acct_start();
  if st is null then return jsonb_build_object('ran', false, 'skipped', 'data_needed', 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then return jsonb_build_object('ran', false, 'skipped', 'accounting_off'); end if;
  if not p_dry and not pg_try_advisory_xact_lock(hashtextextended('acct_post', 0)) then return jsonb_build_object('ran', false, 'skipped', 'busy'); end if;   -- same lock as acct_post_pending
  cap := least(greatest(coalesce(public.rule_num('journal_sched_post_cap'), 1500), 1), 5000)::int;
  lb := public.rule_num('journal_sched_post_lookback_days')::int;
  floor_ := case when lb is null then st else greatest(st, today - lb) end;
  txt := regexp_replace(coalesce(public.rule_txt('journal_sched_post_types'), ''), '\s', '', 'g');
  types := case when txt = '' then null else string_to_array(txt, ',') end;
  -- oldest document first inside a type; types served longest ago go first; a document that failed before goes last, so a poison document cannot starve the rest
  for d in
    select x.* from public._acct_docs(floor_) x
      left join public.w1g_post_watermark w on w.source_type = x.source_type
      left join public.acct_post_errors72 e on e.source_type = x.source_type and e.source_id = x.source_id
     where types is null or x.source_type = any(types)
     order by coalesce(w.last_run_at, '-infinity'::timestamptz), x.source_type, (e.source_id is not null), x.entry_date, x.source_id
  loop
    ty := d.source_type;
    if not (ty = any(seen)) then seen := seen || ty; bt := jsonb_set(bt, array[ty], '{}'::jsonb); end if;
    if d.waiting is not null then waiting := waiting + 1; continue; end if;
    if n >= cap then
      capped := true; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'capped'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
    end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then
          locked := locked + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'locked'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
        end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if not p_dry then eid := public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln); end if;
        posted := posted + 1; bt := public._w1g_bump(bt, ty, 'posted');
        if (bt #>> array[ty, 'last_date']) is null or (bt #>> array[ty, 'last_date'])::date < d.entry_date then bt := jsonb_set(bt, array[ty, 'last_date'], to_jsonb(d.entry_date::text)); end if;
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then
          locked := locked + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'locked'); bt := public._w1g_oldest(bt, ty, d.entry_date); continue;
        end if;
        if not p_dry then eid := public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1; bt := public._w1g_bump(bt, ty, 'reversed');
      end if;
      if not p_dry then delete from public.acct_post_errors72 where source_type = d.source_type and source_id = d.source_id; end if;
      n := n + 1;
    exception when others then
      nerr := nerr + 1; left_ := left_ + 1; bt := public._w1g_bump(bt, ty, 'errors'); bt := public._w1g_oldest(bt, ty, d.entry_date);
      if jsonb_array_length(errs) < 20 then errs := errs || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', left(sqlerrm, 200)); end if;
      if not p_dry then
        insert into public.acct_post_errors72 (source_type, source_id, error) values (d.source_type, d.source_id, left(sqlerrm, 300))
          on conflict (source_type, source_id) do update set error = excluded.error, tries = public.acct_post_errors72.tries + 1, last_at = now();
      end if;
      n := n + 1;
    end;
  end loop;
  res := jsonb_build_object('ran', not p_dry, 'dry', p_dry, 'posted', posted, 'reversed', rev, 'locked', locked, 'waiting', waiting, 'errors', errs, 'error_count', nerr,
    'capped', capped, 'cap', cap, 'left', left_, 'floor', floor_, 'via', via, 'by_type', bt);
  if p_dry then return res; end if;
  -- watermark per source type
  for ty in select jsonb_object_keys(bt) loop
    k := ty;
    insert into public.w1g_post_watermark as w0 (source_type, last_run_at, last_posted_at, last_posted_date, posted_total, reversed_total, pending_after, capped_after, locked_after, errors_after, oldest_pending, watermark_date, updated_at)
      values (k,
        case when coalesce((bt #>> array[k, 'posted'])::int, 0) + coalesce((bt #>> array[k, 'reversed'])::int, 0) + coalesce((bt #>> array[k, 'errors'])::int, 0) + coalesce((bt #>> array[k, 'locked'])::int, 0) > 0 then now() end,
        case when coalesce((bt #>> array[k, 'posted'])::int, 0) + coalesce((bt #>> array[k, 'reversed'])::int, 0) > 0 then now() end,
        (bt #>> array[k, 'last_date'])::date,
        coalesce((bt #>> array[k, 'posted'])::int, 0), coalesce((bt #>> array[k, 'reversed'])::int, 0),
        coalesce((bt #>> array[k, 'capped'])::int, 0) + coalesce((bt #>> array[k, 'locked'])::int, 0) + coalesce((bt #>> array[k, 'errors'])::int, 0),
        coalesce((bt #>> array[k, 'capped'])::int, 0), coalesce((bt #>> array[k, 'locked'])::int, 0), coalesce((bt #>> array[k, 'errors'])::int, 0),
        (bt #>> array[k, 'oldest'])::date,
        case when (bt #>> array[k, 'oldest']) is null then today else (bt #>> array[k, 'oldest'])::date - 1 end, now())
    on conflict (source_type) do update set
      last_run_at = coalesce(excluded.last_run_at, w0.last_run_at),
      last_posted_at = coalesce(excluded.last_posted_at, w0.last_posted_at),
      last_posted_date = coalesce(excluded.last_posted_date, w0.last_posted_date),
      posted_total = w0.posted_total + excluded.posted_total, reversed_total = w0.reversed_total + excluded.reversed_total,
      pending_after = excluded.pending_after, capped_after = excluded.capped_after, locked_after = excluded.locked_after, errors_after = excluded.errors_after,
      oldest_pending = excluded.oldest_pending, watermark_date = excluded.watermark_date, updated_at = now();
  end loop;
  -- types that had waiting documents at an earlier run and have none now (someone pressed Post now): clear them, but only inside this run's scope
  update public.w1g_post_watermark w set pending_after = 0, capped_after = 0, locked_after = 0, errors_after = 0, oldest_pending = null, watermark_date = today, updated_at = now()
   where not (w.source_type = any(seen)) and (types is null or w.source_type = any(types)) and w.pending_after > 0;
  insert into public.w1g_sched_state as s (id, last_run_at, last_run_by, last_via, last_result)
    values (1, now(), uid, via, jsonb_build_object('posted', posted, 'reversed', rev, 'locked', locked, 'errors', nerr, 'capped', capped, 'left', left_))
    on conflict (id) do update set last_run_at = excluded.last_run_at, last_run_by = excluded.last_run_by, last_via = excluded.last_via, last_result = excluded.last_result;
  if posted + rev + nerr > 0 or capped then
    insert into public.w1g_post_runs (run_by, via, posted, reversed, locked, errors, capped, left_after, floor_date, by_type)
      values (uid, via, posted, rev, locked, nerr, capped, left_, floor_, bt) returning id into rid;
    res := res || jsonb_build_object('run_id', rid);
    if posted + rev > 0 then
      select staff_id into sid from public.profiles where id = uid;
      insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
        values (uid, sid, 'journal_sched_post', 'journal_entries', rid::text, jsonb_build_object('via', via, 'posted', posted, 'reversed', rev, 'errors', nerr, 'capped', capped, 'left', left_, 'by_type', bt));
    end if;
  end if;
  return res;
end $function$;

-- ============================================================================
-- 4. STRIP DATA AND READINESS (read only)
-- ============================================================================
create or replace function public._w1g_freshness() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare st date := public._acct_start(); now_ timestamptz := now(); on_ boolean := public.rule_on('accounting_on'); sch boolean := public.rule_on('journal_sched_post_on');
        hrs numeric := public.rule_num('journal_stale_warn_hours'); last_at timestamptz; last_src text; pend int := 0; oldest date; wt int := 0; nerr int := 0; status text; stale boolean := false;
        sstate public.w1g_sched_state; bt jsonb;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  select e.created_at, e.source_type into last_at, last_src from public.journal_entries e where e.source_type not in ('manual', 'opening') order by e.id desc limit 1;
  select * into sstate from public.w1g_sched_state where id = 1;
  if st is not null then
    select count(*) filter (where d.waiting is null), min(d.entry_date) filter (where d.waiting is null), count(*) filter (where d.waiting is not null)
      into pend, oldest, wt from public._acct_docs(st) d;
    select count(*) into nerr from public.acct_post_errors72;
  end if;
  stale := hrs is not null and pend > 0 and (last_at is null or now_ - last_at > make_interval(hours => hrs::int));
  status := case when st is null then 'data_needed' when not on_ then 'off' when stale then 'stale' when pend > 0 then 'waiting' else 'fresh' end;
  select coalesce(jsonb_agg(jsonb_build_object('source_type', w.source_type, 'last_posted_at', w.last_posted_at, 'last_posted_date', w.last_posted_date, 'watermark_date', w.watermark_date,
      'pending_after', w.pending_after, 'capped_after', w.capped_after, 'locked_after', w.locked_after, 'errors_after', w.errors_after, 'oldest_pending', w.oldest_pending,
      'posted_total', w.posted_total, 'reversed_total', w.reversed_total) order by w.source_type), '[]'::jsonb) into bt from public.w1g_post_watermark w;
  return jsonb_build_object('status', status, 'now', now_, 'accounting_on', on_, 'start', st, 'sched_on', sch,
    'last_posted_at', last_at, 'last_posted_source', last_src, 'age_minutes', case when last_at is null then null else round(extract(epoch from (now_ - last_at)) / 60)::int end,
    'last_check_at', sstate.last_run_at, 'last_check_via', sstate.last_via, 'last_check_result', sstate.last_result,
    'pending', pend, 'oldest_pending', oldest, 'waiting', wt, 'errors', nerr, 'stale_after_hours', hrs, 'stale', stale, 'by_type', bt);
end $function$;

create or replace function public._w1g_acct_readiness() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare st date := public._acct_start(); on_ boolean := public.rule_on('accounting_on'); op boolean; mt int; mb int; mbl jsonb; pend int := 0; lck int := 0; wt int := 0; nerr int := 0; erl jsonb := '[]'::jsonb;
        checks jsonb := '[]'::jsonb; blockers jsonb := '[]'::jsonb;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  op := exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                  and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id));
  select count(*), count(*) filter (where a.id is null or not a.active or a.is_group) into mt, mb
    from public.acct_mappings m left join public.coa_accounts a on a.id = m.account_id;
  select coalesce(jsonb_agg(z.key order by z.key), '[]'::jsonb) into mbl
    from (select m.key from public.acct_mappings m left join public.coa_accounts a on a.id = m.account_id where a.id is null or not a.active or a.is_group order by m.key limit 20) z;
  if st is not null then
    with dd as materialized (select * from public._acct_docs(st)),
         e as (select x.* from public.acct_post_errors72 x where exists (select 1 from dd where dd.source_type = x.source_type and dd.source_id = x.source_id and dd.waiting is null))
    select (select count(*) from dd where dd.waiting is null),
           (select count(*) from dd where dd.waiting is null and public._acct_locked(case when dd.live then dd.entry_date else coalesce(dd.void_date, public._acct_today()) end)),
           (select count(*) from dd where dd.waiting is not null), (select count(*) from e),
           (select coalesce(jsonb_agg(jsonb_build_object('source_type', y.source_type, 'source_id', y.source_id, 'error', y.error, 'tries', y.tries) order by y.last_at desc), '[]'::jsonb)
              from (select * from e order by e.last_at desc limit 5) y)
      into pend, lck, wt, nerr, erl;
  end if;
  checks := jsonb_build_array(
    jsonb_build_object('key', 'start_date', 'ok', st is not null, 'text', 'Accounting start date is set'),
    jsonb_build_object('key', 'accounting_on', 'ok', on_, 'text', 'Accounting is switched on'),
    jsonb_build_object('key', 'opening', 'ok', op, 'text', 'An opening balance entry exists'),
    jsonb_build_object('key', 'mappings', 'ok', mt > 0 and mb = 0, 'text', 'Every account mapping points to an active, postable account'),
    jsonb_build_object('key', 'no_errors', 'ok', nerr = 0, 'text', 'No document failed to post'));
  select coalesce(jsonb_agg(c ->> 'key'), '[]'::jsonb) into blockers from jsonb_array_elements(checks) c where not (c ->> 'ok')::boolean;
  return jsonb_build_object('ready', jsonb_array_length(blockers) = 0, 'blockers', blockers, 'checks', checks, 'start', st, 'accounting_on', on_, 'opening', op,
    'mappings', mt, 'mappings_broken', mb, 'mappings_broken_keys', mbl, 'pending', pend, 'locked', lck, 'waiting', wt, 'errors', nerr, 'error_list', erl,
    'autopost_on_open', public.rule_on('accounting_autopost'), 'sched_on', public.rule_on('journal_sched_post_on'));
end $function$;

-- ============================================================================
-- 5. SWITCH-COUPLING WARNING (G30, G33)
-- ============================================================================
create or replace function public._w1g_coupled_keys() returns text[] language sql immutable as $$ select array['forms_post_to_ledger', 'journal_sched_post_on']::text[] $$;

-- the primary path path_cfg() would return if the legacy rule had this value (same row choice as path_cfg: the place row beats the all-places row)
create or replace function public._w1g_primary_if(p_domain text, p_loc integer, p_legacy_on boolean) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(x.primary_rule, case when d.legacy_rule is not null and p_legacy_on then 'b' else d.default_primary end)
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        order by s.location_id desc limit 1) x on true
   where d.domain = p_domain $$;

create or replace function public._w1g_switch_coupling_warning(p_key text, p_value jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare mode text := coalesce(public.rule_txt('switch_coupling_warning'), 'warn'); nowv boolean; newv boolean; dom record; loc int; pn text; pa text; places jsonb; acts jsonb := '[]'::jsonb;
        locks int := 0; unlocks int := 0; names text := ''; txt text; fix text; sev text := 'info'; dkey text; newp text; lr text; rd jsonb; showit boolean;
begin
  if not (public.is_owner() or public._acct_view()) then raise exception 'not allowed'; end if;
  showit := mode <> 'off';
  if p_key = 'forms_post_to_ledger' then
    nowv := public.rule_on(p_key);
    if p_value is null or jsonb_typeof(p_value) = 'null' then newv := not nowv;
    elsif jsonb_typeof(p_value) = 'boolean' then newv := (p_value #>> '{}')::boolean;
    else raise exception 'bad_value'; end if;
    for dom in select * from public.path_domains where legacy_rule = p_key order by sort, domain loop
      places := '[]'::jsonb;
      for loc in select distinct s.location_id from (select 0 as location_id union select location_id from public.path_switch where domain = dom.domain) s order by 1 loop
        pn := public._w1g_primary_if(dom.domain, loc, nowv); pa := public._w1g_primary_if(dom.domain, loc, newv);
        if pn is distinct from pa then
          places := places || jsonb_build_object('location_id', loc, 'from', pn, 'to', pa);
          if pa = 'b' then locks := locks + 1; else unlocks := unlocks + 1; end if;
        end if;
      end loop;
      if jsonb_array_length(places) > 0 then
        acts := acts || jsonb_build_object('domain', dom.domain, 'screen', dom.a_en, 'form', dom.b_en, 'places', places);
        names := names || case when names = '' then '' else '; ' end || dom.a_en || ' -> ' || dom.b_en;
      end if;
    end loop;
    if newv = nowv then
      txt := 'No change: the switch is already ' || case when nowv then 'ON' else 'OFF' end || '.';
    elsif newv and locks > 0 then
      sev := 'high';
      txt := 'Turning this ON makes the paper form the only record for: ' || names || '. From the moment it is saved the matching stock screens REFUSE new records ("path_locked") at ' || locks::text
        || ' place setting(s). Approved forms 04-1 (goods receipt) also start posting stock. Nothing already recorded changes.';
      fix := 'To keep a stock screen working, first set its owner switch on #/paths to "Screen" (path a): an explicit owner setting beats this switch. Turning the switch OFF again gives the screens back.';
    elsif newv then
      txt := 'Turning this ON lets approved stock forms (04-1, 04-2, 04-3, 03-1, 05-1) post to the stock ledger. Every place already has an explicit owner setting, so no stock screen is locked by it.';
    elsif locks = 0 and unlocks > 0 then
      txt := 'Turning this OFF gives the stock screens back as the record for: ' || names || '. The paper forms become references again. Nothing already recorded changes.';
    else
      txt := 'Turning this OFF stops stock forms from posting to the stock ledger. Nothing already recorded changes.';
    end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and newv <> nowv, 'confirm', mode = 'confirm' and newv and not nowv,
      'on_now', nowv, 'new_value', newv, 'severity', sev, 'locks', locks, 'unlocks', unlocks, 'actions', acts, 'text', txt, 'fix', fix);
  elsif p_key like 'path:%' then
    dkey := substr(p_key, 6);
    select * into dom from public.path_domains where domain = dkey;
    if not found then raise exception 'unknown_domain'; end if;
    newp := p_value #>> '{}';
    if newp is null or newp not in ('a', 'b', 'first') then raise exception 'bad_value'; end if;
    lr := dom.legacy_rule;
    if newp = 'b' and lr is not null and not public.rule_on(lr) then
      sev := 'high';
      txt := 'Making the paper form the record for "' || dom.a_en || '" while the switch "' || lr || '" is OFF means NOTHING posts this action to the stock ledger: the screen is refused and the form does not post.';
      fix := 'Turn "' || lr || '" ON first, or keep the screen as the record (path a).';
    elsif newp = 'b' and lr is not null then
      txt := 'The paper form (' || dom.b_en || ') becomes the record for "' || dom.a_en || '". The stock screen will refuse new records here.';
    elsif newp = 'a' then
      txt := 'The screen (' || dom.a_en || ') stays the record. The paper form (' || dom.b_en || ') is kept as a reference and posts nothing twice.';
    else
      txt := 'Whichever path records first wins; the other becomes a locked shadow for that record.';
    end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and sev = 'high', 'confirm', mode = 'confirm' and sev = 'high', 'severity', sev,
      'domain', dom.domain, 'new_value', newp, 'text', txt, 'fix', fix);
  elsif p_key = 'journal_sched_post_on' then
    nowv := public.rule_on(p_key);
    if p_value is null or jsonb_typeof(p_value) = 'null' then newv := not nowv;
    elsif jsonb_typeof(p_value) = 'boolean' then newv := (p_value #>> '{}')::boolean;
    else raise exception 'bad_value'; end if;
    rd := public._w1g_acct_readiness();
    if newv = nowv then txt := 'No change.';
    elsif newv then
      txt := 'Turning this ON lets the 30-minute notify job post every waiting sale, return, collection, purchase and expense to the books by itself, in batches, oldest first. They are posted by the same rules as Post now; a posted document is undone only by voiding the document.';
      if jsonb_array_length(rd -> 'blockers') > 0 then
        sev := 'high';
        txt := txt || ' It will do nothing until these are fixed: ' || (select string_agg(c ->> 'text', '; ') from jsonb_array_elements(rd -> 'checks') c where not (c ->> 'ok')::boolean) || '.';
      end if;
    else txt := 'Turning this OFF returns to today: the books fill only when someone presses Post now or opens Accounts.'; end if;
    return jsonb_build_object('key', p_key, 'known', true, 'mode', mode, 'show', showit and newv <> nowv, 'confirm', mode = 'confirm' and newv and not nowv, 'on_now', nowv, 'new_value', newv,
      'severity', sev, 'text', txt, 'readiness', rd);
  end if;
  return jsonb_build_object('key', p_key, 'known', false, 'show', false, 'confirm', false);
end $function$;

-- the owner confirms a warning; in confirm mode the trigger below needs one fresh, unused confirmation per switch-on (single use, valid for one hour)
create or replace function public._w1g_switch_coupling_ack(p_key text, p_value jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare w jsonb; sid text; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not (p_key = any(public._w1g_coupled_keys())) then raise exception 'unknown_key'; end if;
  w := public._w1g_switch_coupling_warning(p_key, p_value);
  insert into public.w1g_switch_acks (user_id, rule_key, new_value, note) values (auth.uid(), p_key, p_value, left(p_note, 300)) returning id into id_;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'switch_coupling_confirm', 'rules', p_key, jsonb_build_object('value', p_value, 'ack_id', id_, 'severity', w ->> 'severity', 'locks', w -> 'locks', 'text', left(w ->> 'text', 500), 'note', left(p_note, 300)));
  return w || jsonb_build_object('ack_id', id_);
end $function$;

create or replace function public._w1g_rules_coupling_guard() returns trigger
language plpgsql security definer set search_path = public as $function$
declare was boolean; will boolean; a public.w1g_switch_acks;
begin
  if not (new.key = any(public._w1g_coupled_keys())) then return new; end if;
  if coalesce(public.rule_txt('switch_coupling_warning'), 'warn') <> 'confirm' then return new; end if;
  was := coalesce((old.value #>> '{}')::boolean, (old.default_value #>> '{}')::boolean, false);
  will := coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false);
  if not will or was then return new; end if;                      -- only turning ON needs a confirmation; turning OFF restores the old behaviour
  select * into a from public.w1g_switch_acks x
   where x.rule_key = new.key and x.user_id = auth.uid() and x.used_at is null and x.at > now() - interval '1 hour' and coalesce((x.new_value #>> '{}')::boolean, true)
   order by x.id desc limit 1 for update;
  if not found then raise exception 'coupling_confirm_needed: read the warning (_w1g_switch_coupling_warning) and confirm it (_w1g_switch_coupling_ack) before turning % on', new.key; end if;
  update public.w1g_switch_acks set used_at = now() where id = a.id;
  return new;
end $function$;
drop trigger if exists rules_coupling_guard98 on public.rules;
create trigger rules_coupling_guard98 before update of value on public.rules for each row when (old.value is distinct from new.value) execute function public._w1g_rules_coupling_guard();

-- ============================================================================
-- 6. U-12: what the backup tool may read (the backup bot, the notify bot or the owner)
-- ============================================================================
create or replace function public._w1g_backup_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not (public._is_ops('backup') or public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('encrypt_on', public.rule_on('backup_encrypt_on'), 'retention_days', public.rule_num('backup_retention_days'));
end $function$;

-- ============================================================================
-- 7. PRIVILEGES: internals closed to browsers, API open to signed-in users (each function checks its own permission)
-- ============================================================================
revoke all on function public._w1g_present(), public._w1g_bump(jsonb, text, text), public._w1g_oldest(jsonb, text, date), public._w1g_coupled_keys(),
  public._w1g_primary_if(text, integer, boolean), public._w1g_rules_coupling_guard() from public, anon, authenticated;
revoke all on function public._w1g_post_scheduled(boolean), public._w1g_freshness(), public._w1g_acct_readiness(), public._w1g_switch_coupling_warning(text, jsonb),
  public._w1g_switch_coupling_ack(text, jsonb, text), public._w1g_backup_settings() from public, anon, authenticated;
grant execute on function public._w1g_post_scheduled(boolean), public._w1g_freshness(), public._w1g_acct_readiness(), public._w1g_switch_coupling_warning(text, jsonb),
  public._w1g_switch_coupling_ack(text, jsonb, text), public._w1g_backup_settings() to authenticated;

-- ===================== phase99.sql =====================
-- Phase 99 (bos99) - WAVE 1 INTEGRATION (UNIFIED_BUILD_PLAN section 4.3, package I-1). Paste LAST, after phases 88 to 98. Paste-twice safe. Earlier phase files are not edited.
-- Needs phase87 and every Wave 1 phase: 88 (open parties), 89 (period integrity), 90 and 91 (exit, return rules), 92 and 93 (one profit number, report parity), 94 and 95 (money controls),
-- 96 and 97 (other income, chart, receipt channels), 98 (scheduled posting, freshness). The file stops with a clear message that names what is missing.
--
-- What it does (and nothing else):
--   1. _i1_apply_hooks(): applies EVERY exact-text hook the seven packages shipped to the shared functions, in ONE fixed order (A, B, C, D, E, F, then C's optional scan hook), using the helper each
--      package shipped (_w1a_patch, _w1b_patch, _w1c_patch, _w1d_patch / _w1d_hooks_apply, _m_patch for W1-E, _w1f_patch). Every call reads the LIVE definition, replaces exact text,
--      stops with "patch site not found" if a text is missing (the whole call is one transaction: nothing is half patched) and does nothing the second time (each hook carries its marker).
--      After the patches it checks that every expected marker is inside its function (_i1_expect) and stops with a message if one is missing (a helper that skipped a function is caught).
--   2. _i1_exc_kinds() / _i1_exc_kinds_apply(): the Exceptions list (money_exceptions) accepts the UNION of the kinds of phase87, 89 and 94. The final check constraint is written from this one list
--      (merged with whatever the live constraint holds, so a kind added by a later phase is never lost).
--   Defaults: every hook is inert while its setting is at the default; the before / after snapshot (tests/sql/phase99_before_after.sh) proves P&L, balance sheet, trial balance, cash flow, day book,
--   stock reports and journal lines are identical to a database built only through phase 87.
-- Re-paste hazard: re-pasting phase 6, 8, 10, 12, 13, 14, 19, 23, 27, 40, 41, 43, 44, 50, 52, 72, 73, 74, 79, 80, 82, 85, 86 or 87 removes the matching hooks. Run   select public._i1_apply_hooks();   (or paste this file again).
-- Tag bos99. Test data only (test_*).

do $g$ declare miss text := '';
begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_patch(regprocedure,text[])') is null then miss := miss || ' phase87'; end if;
  if to_regprocedure('public._p88_present()') is null or to_regprocedure('public._w1a_patch(regprocedure,text[],text)') is null then miss := miss || ' phase88'; end if;
  if to_regprocedure('public._p89_present()') is null or to_regprocedure('public._w1b_patch(regprocedure,text,text[])') is null then miss := miss || ' phase89'; end if;
  if to_regprocedure('public._w1c_present90()') is null then miss := miss || ' phase90'; end if;
  if to_regprocedure('public._w1c_present91()') is null or to_regprocedure('public._w1c_patch(regprocedure,text[],text)') is null then miss := miss || ' phase91'; end if;
  if to_regprocedure('public._w1d_p92_present()') is null or to_regprocedure('public._w1d_patch(regprocedure,text,text[])') is null then miss := miss || ' phase92'; end if;
  if to_regprocedure('public._w1d_p93_present()') is null or to_regprocedure('public._w1d_hooks_apply()') is null then miss := miss || ' phase93'; end if;
  if to_regprocedure('public._p94_present()') is null then miss := miss || ' phase94'; end if;
  if to_regprocedure('public._p95_present()') is null then miss := miss || ' phase95'; end if;
  if to_regprocedure('public._w1f_present96()') is null or to_regprocedure('public._w1f_patch(regprocedure,text[],text)') is null then miss := miss || ' phase96'; end if;
  if to_regprocedure('public._w1f_present97()') is null then miss := miss || ' phase97'; end if;
  if to_regprocedure('public._w1g_present()') is null then miss := miss || ' phase98'; end if;
  if miss <> '' then raise exception 'phase99 needs these phases pasted first (in this order, each once):%', miss; end if;
end $g$;

create or replace function public._p99_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. The Exceptions list: ONE list of kinds, ONE place that writes the check constraint
-- ============================================================================
-- phase87: negative_warn, negative_block_exception, source_required_exception, override_exception, period_lock_exception, approver_exception, recon_diff
-- phase89 (W1-B): late_sale_held, late_sale_redated, backdate_exception
-- phase94 (W1-E): w1e_bank_move_flag, w1e_duplicate_payment, w1e_pay_over_request, w1e_vendor_duplicate, w1e_pay_account_duplicate, w1e_pay_account_changed, w1e_owner_money_request, w1e_journal_request
create or replace function public._i1_exc_kinds() returns text[] language sql immutable as $$
  select array[
    'approver_exception', 'backdate_exception', 'late_sale_held', 'late_sale_redated', 'negative_block_exception', 'negative_warn', 'override_exception', 'period_lock_exception',
    'recon_diff', 'source_required_exception',
    'w1e_bank_move_flag', 'w1e_duplicate_payment', 'w1e_journal_request', 'w1e_owner_money_request', 'w1e_pay_account_changed', 'w1e_pay_account_duplicate', 'w1e_pay_over_request', 'w1e_vendor_duplicate'
  ]::text[]
$$;

-- Reads the live constraint in either form (ARRAY['a'::text, ...] or '{a,b}'::text[]), adds the known list, keeps any other kind it finds, writes it back sorted. Same list = nothing changes.
create or replace function public._i1_exc_kinds_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare con text; def text; cur text[]; want text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase99: the money_exceptions kind check was not found (phase87 missing?)'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase99: the money_exceptions kind check has an unknown shape: %', left(def, 120); end if;
  select array_agg(x order by x) into want from (select unnest(cur) x union select unnest(public._i1_exc_kinds())) z;
  if cur = want and position('ARRAY[' in def) > 0 then return jsonb_build_object('changed', false, 'kinds', cardinality(want)); end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
  return jsonb_build_object('changed', true, 'kinds', cardinality(want));
end $$;

-- ============================================================================
-- 2. What each shared function must carry after the hooks (used by the check at the end of _i1_apply_hooks and by the tests)
-- ============================================================================
create or replace function public._i1_expect() returns table (pkg text, fn text, marker text) language sql immutable as $$
  select * from (values
    ('W1-A', 'public._cust_bal(uuid)', 'bos88'), ('W1-A', 'public.customer_dues()', 'bos88'), ('W1-A', 'public.customer_ledger(uuid)', 'bos88'),
    ('W1-A', 'public.opening_balance_post(jsonb,uuid,boolean,boolean)', 'bos88'),
    ('W1-B', 'public.lock_check(date)', 'bos89'), ('W1-B', 'public._acct_locked(date)', 'bos89'),
    ('W1-B', 'public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'bos89'),
    ('W1-B', 'public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'bos89'),
    ('W1-B', 'public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)', 'bos89'),
    ('W1-B', 'public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)', 'bos89'),
    ('W1-B', 'public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)', 'bos89'),
    ('W1-C', 'public.employee_status_set(uuid,text,date,text)', 'bos90'), ('W1-C', 'public.notify_scan()', 'bos90'),
    ('W1-C', 'public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'bos91'), ('W1-C', 'public.void_sale_return(uuid,text)', 'bos91'),
    ('W1-D', 'public._p27_pl(date,date,integer[])', 'bos92'), ('W1-D', 'public.partner_calculate(bigint,date,date,jsonb)', 'bos92'), ('W1-D', 'public.c_partner_month_split(date)', 'bos92'),
    ('W1-D', 'public._p27_pl(date,date,integer[])', 'bos93'), ('W1-D', 'public.report_run2_core(text,jsonb,text,text,integer)', 'bos93'),
    ('W1-D', 'public._r3q_e3_weak_control(date,date,integer[],jsonb)', 'bos93'), ('W1-D', 'public._r3q_e2_expense_trend(date,date,integer[],jsonb)', 'bos93'),
    ('W1-D', 'public.brand_pnl(date,date,text)', 'bos93'), ('W1-D', 'public._daybook_lines(integer[],integer[],date,date)', 'bos93'), ('W1-D', 'public._acct_docs(date)', 'bos93'),
    ('W1-E', 'public.pay_supplier(uuid,integer,jsonb,uuid,text)', 'w1e94'), ('W1-E', 'public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)', 'w1e94c'),
    ('W1-E', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'w1e95'),
    ('W1-F', 'public._acct_docs(date)', 'bos96'), ('W1-F', 'public._daybook_lines(integer[],integer[],date,date)', 'bos96'), ('W1-F', 'public._e_balance_check(date,integer,integer)', 'bos96'),
    ('W1-F', 'public.acct_cash_flow(date,date,integer)', 'bos96'), ('W1-F', 'public.daybook_vs_journal(date,date,integer)', 'bos96'),
    ('W1-F', 'public._acct_docs(date)', 'bos97'), ('W1-F', 'public._daybook_lines(integer[],integer[],date,date)', 'bos97'), ('W1-F', 'public.collect_payment(uuid,integer,uuid,jsonb,text)', 'bos97'),
    ('W1-F', 'public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)', 'bos97')
  ) v(pkg, fn, marker)
$$;

create or replace function public._i1_hooks_state() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('pkg', e.pkg, 'fn', e.fn, 'marker', e.marker,
           'present', to_regprocedure(e.fn) is not null and position(e.marker in pg_get_functiondef(to_regprocedure(e.fn))) > 0) order by e.pkg, e.fn, e.marker), '[]'::jsonb)
    from public._i1_expect() e
$$;

-- ============================================================================
-- 3. The hooks, in the fixed order A, B, C, D, E, F (F96 before F97), C's scan hook last. Returns one entry per patch: true = patched now, false = already there.
-- ============================================================================
create or replace function public._i1_apply_hooks() returns jsonb language plpgsql security definer set search_path = public as $i1$
declare res jsonb := '{}'::jsonb; r boolean; bad text;
begin
  perform pg_advisory_xact_lock(hashtext('bos99_hooks'));
  -- ===== W1-A (marker bos88): opening dues and payables in the customer and supplier sub-ledgers =====
  r := public._w1a_patch('public._cust_bal(uuid)'::regprocedure, array[
  $a$select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$,
  $a$select public._w1a_cust_open(p_customer) /* bos88: opening due */ + coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)$a$]);
  res := res || jsonb_build_object('bos88:_cust_bal', r);
  r := public._w1a_patch('public.customer_dues()'::regprocedure, array[
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),$a$,
  $a$select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) /* bos88 */ - coalesce(c.coll, 0),$a$,
  $a$(select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))$a$,
  $a$(case when public._w1a_cust_open(cu.id) > coalesce(c.coll, 0) then public._w1a_cust_open_date(cu.id)
              else (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr + public._w1a_cust_open(cu.id) > coalesce(c.coll, 0)) end)$a$,
  $a$from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$from public.customers cu left join t on t.customer_id = cu.id left join c on c.customer_id = cu.id$a$,
  $a$and t.rem - coalesce(c.coll, 0) > 0$a$,
  $a$and coalesce(t.rem, 0) + public._w1a_cust_open(cu.id) - coalesce(c.coll, 0) > 0$a$]);
  res := res || jsonb_build_object('bos88:customer_dues', r);
  r := public._w1a_patch('public.customer_ledger(uuid)'::regprocedure, array[
  $a$select s.sold_at at, 'sale'::text kind,$a$,
  $a$select public._w1a_cust_open_at(p_customer) at, 'opening'::text kind, null::text ref, null::int location_id, o.ob debit, 0::numeric credit, 'opening balance'::text note, null::bigint pid /* bos88 */
      from (select public._w1a_cust_open(p_customer) ob) o where o.ob <> 0
    union all
    select s.sold_at at, 'sale'::text kind,$a$]);
  res := res || jsonb_build_object('bos88:customer_ledger', r);
  r := public._w1a_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$,
  $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */ perform public._w1a_opening_apply(p_json); /* bos88 */$a$]);
  res := res || jsonb_build_object('bos88:opening_balance_post', r);
  -- ===== W1-B (marker bos89): period integrity =====
  r := public._w1b_patch('public.lock_check(date)'::regprocedure, 'bos89', array[
  $a$if p_date is null or public.is_owner() then return; end if;$a$,
  $a$if p_date is null then return; end if;
  if public._w1b_lock_allowed(p_date) then return; end if;   -- bos89: pure date test, owner mode, override windows
  raise exception 'period_closed';                            -- bos89: the statements below are the old body and are not reached any more$a$]);
  res := res || jsonb_build_object('bos89:lock_check', r);
  r := public._w1b_patch('public._acct_locked(date)'::regprocedure, 'bos89', array[
  $a$begin perform public.lock_check(p_date); return false;$a$,
  $a$begin if public._w1b_pure_posting() then return public._w1b_is_locked(p_date); end if; /* bos89 */ perform public.lock_check(p_date); return false;$a$]);
  res := res || jsonb_build_object('bos89:_acct_locked', r);
  r := public._w1b_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43$a$,
  $a$tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
  lt89 jsonb;   -- bos89$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;$a$,
  $a$if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then
    lt89 := public._w1b_late_sale(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input, at_);   -- bos89
    if lt89 is not null and (lt89 ->> 'keep') is null then return lt89; end if;   -- parked for the owner
    if lt89 is null then at_ := now(); end if;                                    -- re-dated, as before
  end if;$a$]);
  res := res || jsonb_build_object('bos89:record_sale2', r);
  r := public._w1b_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, 'bos89', array[
  $a$if p_dry then$a$,
  $a$perform public._w1b_backdate_check('cash_move', d, p_client, 'cash_moves');   -- bos89
  if p_dry then$a$]);
  res := res || jsonb_build_object('bos89:cash_move_add', r);
  r := public._w1b_patch('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'::regprocedure, 'bos89', array[
  $a$perform public.lock_check(d);$a$,
  $a$perform public.lock_check(d);
  perform public._w1b_backdate_check('expense', d, p_client, 'quick_expenses');   -- bos89$a$]);
  res := res || jsonb_build_object('bos89:quick_expense_add', r);
  r := public._w1b_patch('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'::regprocedure, 'bos89', array[
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;$a$,
  $a$if p_bill_date is null or not (p_bill_date <= (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  if bid is null then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills');   -- bos89
  elsif pb.bill_date is distinct from p_bill_date then perform public._w1b_backdate_check('purchase', p_bill_date, p_client, 'purchase_bills'); end if;$a$]);
  res := res || jsonb_build_object('bos89:save_purchase', r);
  r := public._w1b_patch('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)'::regprocedure, 'bos89', array[
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;$a$,
  $a$if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  perform public._w1b_backdate_check('production', (at_ at time zone 'Asia/Dhaka')::date, p_client, 'production_runs');   -- bos89$a$]);
  res := res || jsonb_build_object('bos89:production_post', r);
  -- ===== W1-C (markers bos90, bos91): staff exit, sale return =====
  r := public._w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);',
  E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'
], 'bos90');
  res := res || jsonb_build_object('C:employee_status_set', r);
  r := public._w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);',
  E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'
], 'bos91');
  res := res || jsonb_build_object('C:sale_return', r);
  r := public._w1c_patch('public.void_sale_return(uuid,text)'::regprocedure, array[
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;',
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;\n  perform public._w1c_return_void_guard(p_id); /* bos91 */'
], 'bos91');
  res := res || jsonb_build_object('C:void_sale_return', r);
  -- ===== W1-D (markers bos92, bos93): one profit number, report parity (the patches of phases 92 and 93 again, then the day book and journal hook) =====
  r := public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos92', array[
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),$a$,
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),$a$]);
  res := res || jsonb_build_object('bos92:_p27_pl', r);
  r := public._w1d_patch('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure, 'bos92', array[
  $a$ag public.partner_agreements; vn public.partner_ventures;$a$, $a$ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;$a$,
  $a$'warnings', warns, 'wrote', false);$a$, $a$'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);$a$]);
  res := res || jsonb_build_object('bos92:partner_calculate', r);
  r := public._w1d_patch('public.c_partner_month_split(date)'::regprocedure, 'bos92', array[
  $a$base := (prof ->> 'net_profit')::numeric;$a$,
  $a$base := coalesce(public._w1d_split_base(greatest(m, st), me, case when a.scope = 'location' then a.location_id end), (prof ->> 'net_profit')::numeric);   /* bos92 */$a$,
  $a$'basis', 'journal net profit of the month (salary accrual included)'$a$, $a$'basis', coalesce(public._w1d_split_basis(), 'journal net profit of the month (salary accrual included)')$a$]);
  res := res || jsonb_build_object('bos92:c_partner_month_split', r);
  r := public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */$a$,
  $a$where public.rule_on('payroll_accrual_on') /* bos85 bos86 */$a$,
  $a$where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */$a$]);
  res := res || jsonb_build_object('bos93:_p27_pl', r);
  r := public._w1d_patch('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) and e.entry_date between %L and %L and e.location_id = any (%L::int[])
            union all  /* bos93: quick expenses (only while report_expense_parity_on) */
            select null::uuid, q.location_id, q.exp_date, q.amount, case when q.receipt then 'yes' else 'no' end, coalesce(nullif(btrim(q.head), ''), '-') from public.quick_expenses q
            where public._w1d_parity_on() and q.status = 'done' and q.exp_date between %2$L and %3$L and q.location_id = any (%4$L::int[])) x$a$]);
  res := res || jsonb_build_object('bos93:report_run2_core', r);
  r := public._w1d_patch('public._r3q_e3_weak_control(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) /* bos93 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)) v$a$,
  $a$   group by l.id, l.name_bn;$a$,
  $a$   group by l.id, l.name_bn
  union all  /* bos93: quick expenses have no voucher flags; their count and the lines without a receipt are shown so that the control report covers them */
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', 'quick', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', count(*) filter (where not q.receipt), 'no_receipt_amount', coalesce(sum(q.amount) filter (where not q.receipt), 0), 'over_limit_vouchers', null, 'over_limit_amount', null,
      'approval_missing', null, 'reason_missing', null, 'imprest_diff_sheets', null, 'imprest_diff_amount', null)
    from public.quick_expenses q join public.locations l on l.id = q.location_id
   where public._w1d_parity_on() and q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
   group by l.id, l.name_bn;$a$]);
  res := res || jsonb_build_object('bos93:_r3q_e3_weak_control', r);
  r := public._w1d_patch('public._r3q_e2_expense_trend(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$]);
  res := res || jsonb_build_object('bos93:_r3q_e2_expense_trend', r);
  r := public._w1d_patch('public.brand_pnl(date,date,text)'::regprocedure, 'bos93', array[
  $a$left join public.report_brand_map b on b.location_id = d.location_id$a$,
  $a$left join lateral public._w1d_brand_at(d.location_id, d.sale_date) b on true /* bos93 */$a$]);
  res := res || jsonb_build_object('bos93:brand_pnl', r);
  res := res || jsonb_build_object('bos93:_w1d_hooks_apply', public._w1d_hooks_apply());
  -- ===== W1-E (markers w1e94, w1e94c, w1e95; phase87 helper _m_patch): supplier payment, cash move display, manual journal =====
  r := public._m_patch('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure, array[
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;$h$,
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
$h$]);
  res := res || jsonb_build_object('w1e:pay_supplier', r);
  r := public._m_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, array[
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));$h$,
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */$h$]);
  res := res || jsonb_build_object('w1e:cash_move_add', r);
  r := public._m_patch('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure, array[
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb;$h$,
 $h$declare st date := public._acct_start(); r public.journal_entries; ln jsonb; id_ bigint; td numeric := 0; tc numeric := 0; x jsonb; gate jsonb; /* bos87 w1e95 */$h$,
 $h$  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$,
 $h$  gate := public._w1e_journal_gate(p_date, p_loc, p_memo, ln, p_photo, p_client, td);
  if gate is not null then return gate; end if;
  id_ := public._acct_write(p_date, p_loc, 'manual', coalesce(p_client::text, gen_random_uuid()::text), null, p_memo, null, ln, null, p_client, p_photo);$h$]);
  res := res || jsonb_build_object('w1e:acct_journal_post', r);
  -- ===== W1-F (markers bos96, bos97): other income, legacy wallets, receipt channels =====
  r := public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$,
  $a$return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */
  return query select * from public._w1f_docs(p_start); /* bos96: other income */$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_acct_docs', r);
  r := public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$,
  $a$union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */
  union all select * from public._w1f_daybook_rows(p_locs, p_from, p_to) /* bos96 */;$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_daybook_lines', r);
  r := public._w1f_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$  begin   -- bos96: mapping coverage (amber): every key the posting needs points to an active account
    xc := xc || jsonb_build_object('mapping_coverage', public._w1f_mapping_coverage());
    if not coalesce((xc #>> '{mapping_coverage,ok}')::boolean, true) then warn := warn || to_jsonb('mapping_coverage'::text); end if;
  exception when others then xc := xc || jsonb_build_object('mapping_coverage', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$], 'bos96');
  res := res || jsonb_build_object('bos96:_e_balance_check', r);
  r := public._w1f_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$union select coa_account_id from public.money_accounts) z; /* bos87 */$a$,
  $a$union select coa_account_id from public.money_accounts union select account_id from public.acct_mappings where key like 'd\_wallet\_%' /* bos96: legacy wallets */) z; /* bos87 */$a$], 'bos96');
  res := res || jsonb_build_object('bos96:acct_cash_flow', r);
  r := public._w1f_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$from public.acct_mappings m0 union select ma.coa_account_id$a$,
  $a$from public.acct_mappings m0 union select w0.account_id, 'pay_mobile' from public.acct_mappings w0 where w0.key like 'd\_wallet\_%' /* bos96: legacy wallets */ union select ma.coa_account_id$a$], 'bos96');
  res := res || jsonb_build_object('bos96:daybook_vs_journal', r);
  r := public._w1f_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode$a$,
  $a$jsonb_build_object('a', public._m_key(p.money_account_id, 'pay_' || p.mode) /* bos97 */, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode, p.money_account_id$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p.mode), 'd', p.amount),$a$,
  $a$case when not p.voided then jsonb_build_array(jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode)) /* bos97 */, 'd', p.amount),$a$], 'bos97');
  res := res || jsonb_build_object('bos97:_acct_docs', r);
  r := public._w1f_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,$a$,
  $a$nullif(btrim(concat_ws(' · ', c.name, coalesce(public._m_name(p.money_account_id), p.wallet), p.ref, case when p.cheque_no is not null then 'cheque ' || p.cheque_no end) /* bos97 */), ''), p.created_staff, p.paid_at,$a$], 'bos97');
  res := res || jsonb_build_object('bos97:_daybook_lines', r);
  r := public._w1f_patch('public.collect_payment(uuid,integer,uuid,jsonb,text)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, note, created_by, created_staff, client_id) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2),$a$], 'bos97');
  res := res || jsonb_build_object('bos97:collect_payment', r);
  r := public._w1f_patch('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure, array[
  $a$if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;$a$,
  $a$if pm is null or pm <> all (public._w1f_receipt_modes()) /* bos97 */ then raise exception 'bad_mode'; end if;$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)$a$,
  $a$insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, cheque_no, cheque_date, money_account_id, ref_waiver, amount, paid_at, created_by, created_staff) /* bos97 */$a$,
  $a$left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_,$a$,
  $a$left(nullif(pay->>'ref', ''), 60), public._w1f_pj_text(pay, 'cheque_no', 40), public._w1f_pj_date(pay, 'cheque_date'), public._w1f_pj_acc(pay), public._w1f_pj_text(pay, 'exception_reason', 200), round((pay->>'amount')::numeric, 2), at_,$a$], 'bos97');
  res := res || jsonb_build_object('bos97:record_sale2', r);
  -- ===== W1-C optional hook 4 (marker bos90): the exit alert scan runs inside notify_scan (does nothing until exit_alert_hours is set) =====
  r := public._w1c_patch('public.notify_scan()'::regprocedure, array[
  E'  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);',
  E'  perform public._w1c_exit_scan_run(); /* bos90 */\n  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);'
], 'bos90');
  res := res || jsonb_build_object('C4:notify_scan', r);
  -- every expected marker must now be inside its function (a helper that skipped a function silently is caught here)
  select string_agg(x ->> 'fn' || ' (' || (x ->> 'marker') || ')', ', ') into bad from jsonb_array_elements(public._i1_hooks_state()) x where not (x ->> 'present')::boolean;
  if bad is not null then raise exception 'phase99: hook missing after patching: %', bad; end if;
  return res;
end $i1$;

revoke all on function public._p99_present(), public._i1_exc_kinds(), public._i1_exc_kinds_apply(), public._i1_expect(), public._i1_hooks_state(), public._i1_apply_hooks() from public, anon, authenticated;

-- ============================================================================
-- 4. Run
-- ============================================================================
select public._i1_exc_kinds_apply();
select public._i1_apply_hooks();

-- ===================== phase120.sql =====================
-- Phase 120 (bos120) - PAY REQUESTS (package R1). Paste AFTER phase99 (needs phase 87 and the staff, payroll, purchase and notification phases). Paste-twice safe. Earlier phase files are not edited.
-- Purpose: nobody has to ask for salary, an advance or a supplier payment by word of mouth. A person writes a request in the app (amount, reason, needed-by date); ONE responsible
-- person decides it (approve on the date asked, approve on another date, or reject with a reason); on the pay date it shows in a due list; the payment is made by the EXISTING functions
-- (staff_advance_add, payroll_pay, pay_supplier) with the payment source chosen at that moment (cash, mobile banking, bank: never fixed), so the ledger entry is the same as today.
-- EVERY choice is a setting; every default keeps TODAY'S behaviour (nothing changes when the settings are left alone):
--   pay_requests_on               OFF   staff can send salary / advance requests
--   pay_requests_required         OFF   ("verbal request policy") salary and advance are paid only against an approved request; one exception with a reason is logged to the Exceptions list
--   pay_requests_required_kinds   both  which payments the policy covers: both | advance | salary
--   pay_request_approver_mode     owner who decides staff requests: owner | role | user  (+ pay_request_approver_role / pay_request_approver_user); the owner can always decide
--   pay_request_exception_mode    reason  how an unbacked payment can still be made: reason (the payer writes why) | owner (only the owner) | never
--   pay_request_max_per_month     blank = no limit   requests one staff member may send per month
--   pay_request_advance_ceiling   blank = no limit   open advances + open advance requests + this one may not pass this amount
--   party_requests_on / party_requests_required / party_request_approver_mode (same | owner | role | user) + _role / _user   the same for supplier payments
-- NO shared function is replaced and NO hook is needed: the "required" policy is a BEFORE INSERT trigger (a0_r1_gate_bi) on employee_advances, payroll_payments and supplier_payments, so every
-- path that pays (old screens, the due list, a W1-E approved request) meets it, and re-pasting an older phase cannot remove it. The trigger is inert while the settings are at the default.
-- The maker never decides or pays his own request (BUILD-RULES 8); the owner may do it only where the project already lets him approve his own entries (owner_self_approve, not in named mode).
-- Notifications: in-app rows in public.notifications (phase 46), aimed at one person. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null
     or to_regprocedure('public._m_mode_of_kind(text)') is null then raise exception 'phase120 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.staff_advance_add(uuid,date,numeric,numeric,text,date,text,uuid)') is null or to_regprocedure('public.payroll_pay(bigint,bigint[],text,date,text,text,uuid,numeric)') is null
     or to_regprocedure('public.pay_supplier(uuid,integer,jsonb,uuid,text)') is null then raise exception 'phase120 needs the payroll (phase 42) and supplier payment (phase 10) functions'; end if;
  if to_regclass('public.notifications') is null or to_regclass('public.employees') is null or to_regclass('public.money_exceptions') is null then raise exception 'phase120 needs phases 46, 87 and the employee tables'; end if;
end $g$;

create or replace function public._p120_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- Exceptions list: one more kind (merged with the live list, same pattern as phase 94 / 99; every kind found is kept) ----------
create or replace function public._r1_exc_kinds_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare con text; def text; cur text[]; want text[];
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase120: the money_exceptions kind check was not found (phase87 missing?)'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase120: the money_exceptions kind check has an unknown shape: %', left(def, 120); end if;
  select array_agg(x order by x) into want from (select unnest(cur) x union select unnest(array['r1_unbacked_payment']::text[])) z;
  if cur = want and position('ARRAY[' in def) > 0 then return jsonb_build_object('changed', false, 'kinds', cardinality(want)); end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
  return jsonb_build_object('changed', true, 'kinds', cardinality(want));
end $$;
select public._r1_exc_kinds_apply();

-- ---------- settings (rules). Every default = today. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, v.module, v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lbn, v.lmix, v.len, v.hbn, v.hmix, v.hen, v.srt
  from (values
 ('pay_requests_on', 'people', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'স্টাফ অ্যাপে বেতন / অগ্রিম চাইতে পারবে', 'Staff Salary / Advance request পাঠাতে পারবে', 'Staff can ask for salary or an advance in the app',
   'বন্ধ থাকলে আগের মতোই। চালু হলে স্টাফ নিজের ফোন থেকে পরিমাণ, কারণ ও কবে লাগবে লিখে অনুরোধ পাঠায়।', 'Off = as today. On = a staff member sends an amount, a reason and the needed-by date from his own login.',
   'Off = as today. On = a staff member sends an amount, a reason and the needed-by date from his own login; one responsible person decides.', 1200),
 ('pay_requests_required', 'people', 'switch', 'false'::jsonb, null, null, null, null,
   'মুখের কথায় বেতন / অগ্রিম নয় (অনুমোদিত অনুরোধ ছাড়া পেমেন্ট নয়)', 'Verbal request policy: অনুমোদিত request ছাড়া payment নয়', 'Verbal request policy: pay salary and advance only against an approved request',
   'বন্ধ থাকলে আগের মতোই। চালু হলে অনুমোদিত অনুরোধ ছাড়া বেতন / অগ্রিম দেওয়া যাবে না। কারণ লিখে ব্যতিক্রম করা যায়; সেটি ব্যতিক্রম তালিকায় ওঠে।', 'Off = as today. On = refused unless an approved request backs it. One exception with a reason is possible and is written to the Exceptions list.',
   'Off = as today. On = a salary or advance payment to a staff member is refused unless an approved request backs it. One exception with a written reason is possible (see the exception setting) and is written to the Exceptions list. Also known as pay_requests_required / verbal request policy.', 1201),
 ('pay_requests_required_kinds', 'people', 'choice', '"both"'::jsonb, null, '["both","advance","salary"]'::jsonb, null, null,
   'কোন পেমেন্টে অনুরোধ লাগবে', 'Request লাগবে: salary / advance', 'Which payments need an approved request',
   'both = বেতন ও অগ্রিম, advance = শুধু অগ্রিম, salary = শুধু বেতন। শুধু উপরের নীতি চালু থাকলে কাজ করে।', 'both | advance | salary. Used only when the policy above is ON.',
   'both = salary and advance, advance = advance only, salary = salary only. Used only when the policy above is ON.', 1202),
 ('pay_request_approver_mode', 'people', 'choice', '"owner"'::jsonb, null, '["owner","role","user"]'::jsonb, null, null,
   'বেতন / অগ্রিমের অনুরোধ কে সিদ্ধান্ত দেবে', 'Staff request কে decide করবে', 'Who decides staff requests',
   'owner = মালিক, role = একটি ভূমিকা, user = একজন নির্দিষ্ট ব্যক্তি। মালিক সবসময় সিদ্ধান্ত দিতে পারেন। বদলাতে "অনুরোধের সিদ্ধান্তদাতা" পাতা ব্যবহার করুন।', 'owner | role | user. The owner can always decide. Change it on the pay-request settings page.',
   'owner | role | user. The owner can always decide. Change it on the pay-request settings page (one call, written to the change log).', 1203),
 ('pay_request_approver_role', 'people', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ভূমিকা', 'Approver role', 'Approver role (when the mode is role)', null, null, 'A role code. Set through the pay-request settings page.', 1204),
 ('pay_request_approver_user', 'people', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ব্যক্তি', 'Approver person', 'Approver person (when the mode is user)', null, null, 'A person id. Set through the pay-request settings page.', 1205),
 ('pay_request_exception_mode', 'people', 'choice', '"reason"'::jsonb, null, '["reason","owner","never"]'::jsonb, null, null,
   'অনুরোধ ছাড়া পেমেন্টের ব্যতিক্রম', 'Request ছাড়া payment: exception', 'Payment without an approved request: how an exception works',
   'reason = পেমেন্টকারী কারণ লিখে করতে পারে, owner = শুধু মালিক, never = একেবারে নয়। প্রতিটি ব্যবহার ব্যতিক্রম তালিকায় ওঠে।', 'reason = the payer writes why, owner = only the owner, never = no way past. Every use is on the Exceptions list.',
   'reason = the payer writes why (one payment, 30 minutes), owner = only the owner, never = no way past. Every use is on the Exceptions list. Used only when the policy is ON.', 1206),
 ('pay_request_max_per_month', 'people', 'number', null, 'requests', null, 1, 1000,
   'একজন স্টাফ মাসে সর্বোচ্চ কতটি অনুরোধ', 'Staff প্রতি মাসে max request', 'Most requests one staff member may send in a month',
   'ফাঁকা = সীমা নেই।', 'Blank = no limit.', 'Blank = no limit. Cancelled requests are not counted.', 1207),
 ('pay_request_advance_ceiling', 'people', 'number', null, 'Tk', null, 1, 1000000000,
   'অগ্রিমের সর্বোচ্চ সীমা (মোট বকেয়া অগ্রিম + খোলা অনুরোধ + এই অনুরোধ)', 'Advance ceiling (বকেয়া advance + খোলা request + এটি)', 'Advance ceiling for one person (open advances + open requests + this one)',
   'ফাঁকা = সীমা নেই।', 'Blank = no limit.', 'Blank = no limit. A request that would pass this total is refused when it is sent.', 1208),
 ('party_requests_on', 'purchase', 'switch', 'false'::jsonb, null, null, null, null,
   'সরবরাহকারীর পেমেন্টের অনুরোধ চালু', 'Supplier payment request চালু', 'Supplier payment requests',
   'বন্ধ থাকলে আগের মতোই। চালু হলে ক্রয় / স্টোর / যেকোনো স্টাফ সরবরাহকারীকে টাকা দেওয়ার অনুরোধ লিখতে পারে।', 'Off = as today. On = purchase, store or any staff can write a request to pay a supplier.',
   'Off = as today. On = purchase, store or any staff (or the supplier side, entered on their behalf) can write a request to pay a supplier.', 1220),
 ('party_requests_required', 'purchase', 'switch', 'false'::jsonb, null, null, null, null,
   'অনুমোদিত অনুরোধ ছাড়া সরবরাহকারীকে পেমেন্ট নয়', 'Approved request ছাড়া supplier payment নয়', 'Pay a supplier only against an approved request',
   'বন্ধ থাকলে আগের মতোই। বিলের সাথে দেওয়া পেমেন্ট এর আওতায় পড়ে না।', 'Off = as today. A payment made together with a purchase bill is not covered.',
   'Off = as today. On = the standalone supplier payment (pay_supplier) is refused unless an approved request backs it; the same exception setting applies. A payment made together with a purchase bill is not covered.', 1221),
 ('party_request_approver_mode', 'purchase', 'choice', '"same"'::jsonb, null, '["same","owner","role","user"]'::jsonb, null, null,
   'সরবরাহকারী পেমেন্টের অনুরোধ কে সিদ্ধান্ত দেবে', 'Supplier request কে decide করবে', 'Who decides supplier payment requests',
   'same = স্টাফ অনুরোধের মতোই।', 'same = the person chosen for staff requests.', 'same = the person chosen for staff requests; or owner | role | user.', 1222),
 ('party_request_approver_role', 'purchase', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ভূমিকা (সরবরাহকারী)', 'Approver role (supplier)', 'Approver role for supplier requests', null, null, 'A role code. Set through the pay-request settings page.', 1223),
 ('party_request_approver_user', 'purchase', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ব্যক্তি (সরবরাহকারী)', 'Approver person (supplier)', 'Approver person for supplier requests', null, null, 'A person id. Set through the pay-request settings page.', 1224)
 ) v(key, module, kind, dv, unit, ch, mn, mx, lbn, lmix, len, hbn, hmix, hen, srt)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.pay_requests (
  id bigserial primary key,
  client_id uuid unique,
  kind text not null check (kind in ('salary', 'advance', 'supplier')),
  status text not null default 'received' check (status in ('received', 'approved', 'rejected', 'paid', 'cancelled')),
  requested_by uuid not null, requested_staff text, on_behalf boolean not null default false,
  employee_id uuid references public.employees(id),
  supplier_id uuid references public.suppliers(id),
  bill_id uuid references public.purchase_bills(id), bill_ref text check (bill_ref is null or length(bill_ref) <= 80),
  asked_by_name text check (asked_by_name is null or length(asked_by_name) <= 80),
  location_id int references public.locations(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  needed_by date not null,
  approved_amount numeric check (approved_amount is null or (approved_amount > 0 and approved_amount <= 1000000000)),
  pay_date date, date_changed boolean not null default false,
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text check (decision_note is null or length(decision_note) <= 300),
  paid_amount numeric not null default 0 check (paid_amount >= 0), paid_at timestamptz, paid_by uuid, paid_ref text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((kind = 'supplier' and supplier_id is not null and employee_id is null) or (kind in ('salary', 'advance') and employee_id is not null and supplier_id is null))
);
create index if not exists pay_requests_status on public.pay_requests (status, pay_date);
create index if not exists pay_requests_emp on public.pay_requests (employee_id, created_at);
create index if not exists pay_requests_by on public.pay_requests (requested_by);

create table if not exists public.pay_request_events (            -- the timeline a staff member sees; append only
  id bigserial primary key,
  request_id bigint not null references public.pay_requests(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  action text not null check (action in ('received', 'approved', 'redated', 'rejected', 'cancelled', 'paid', 'partly_paid', 'exception_used')),
  from_status text, to_status text, note text, data jsonb
);
create index if not exists pay_request_events_req on public.pay_request_events (request_id, id);

create table if not exists public.pay_request_exceptions (        -- a one-payment, 30 minute permission to pay without an approved request (reason required)
  id bigserial primary key,
  user_id uuid not null, kind text not null check (kind in ('salary', 'advance', 'supplier')),
  employee_id uuid, supplier_id uuid, max_amount numeric not null check (max_amount > 0),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  opened_by uuid not null, opened_at timestamptz not null default now(), expires_at timestamptz not null default (now() + interval '30 minutes'),
  used_at timestamptz, used_ref text
);

do $t$ declare t text; begin
  foreach t in array array['pay_requests', 'pay_request_events', 'pay_request_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['pay_requests', 'pay_request_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  if exists (select 1 from pg_class where relname = 'pay_requests_id_seq' and relnamespace = 'public'::regnamespace) then
    execute 'revoke all on sequence public.pay_requests_id_seq, public.pay_request_events_id_seq, public.pay_request_exceptions_id_seq from public, anon, authenticated';
  end if;
end $t$;

-- ---------- small helpers ----------
create or replace function public._r1_staff(p_uid uuid default null) returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = coalesce(p_uid, auth.uid()) $$;
create or replace function public._r1_is_owner_uid(p_uid uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id where p.id = p_uid and p.status = 'active' and ur.role_code = 'owner') $$;
create or replace function public._r1_my_emp(p_uid uuid default null) returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e where e.profile_id = coalesce(p_uid, auth.uid()) and e.status in ('active', 'on_leave') order by e.created_at limit 1 $$;
create or replace function public._r1_uuid(t text) returns uuid language plpgsql immutable as $$
begin return nullif(btrim(coalesce(t, '')), '')::uuid; exception when others then return null; end $$;

-- configured approver for a kind: staff requests use pay_request_approver_*; supplier requests use party_request_approver_* unless that is "same"
create or replace function public._r1_cfg(p_kind text, out mode text, out role text, out usr uuid) language plpgsql stable security definer set search_path = public as $$
declare pm text := coalesce(public.rule_txt('party_request_approver_mode'), 'same');
begin
  if p_kind = 'supplier' and pm <> 'same' then
    mode := pm; role := nullif(btrim(coalesce(public.rule_txt('party_request_approver_role'), '')), ''); usr := public._r1_uuid(public.rule_txt('party_request_approver_user'));
  else
    mode := coalesce(public.rule_txt('pay_request_approver_mode'), 'owner'); role := nullif(btrim(coalesce(public.rule_txt('pay_request_approver_role'), '')), ''); usr := public._r1_uuid(public.rule_txt('pay_request_approver_user'));
  end if;
end $$;

-- may this person decide / pay requests of this kind (before the maker rule)? The owner always; otherwise the person or role the owner named.
create or replace function public._r1_approver_ok(p_uid uuid, p_kind text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid and status = 'active') then return false; end if;
  if public._r1_is_owner_uid(p_uid) then return true; end if;
  select * into c from public._r1_cfg(p_kind);
  if c.mode = 'role' then return c.role is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = c.role); end if;
  if c.mode = 'user' then return c.usr is not null and c.usr = p_uid; end if;
  return false;
end $$;

-- the maker rule: nobody decides or pays his own request; the owner only where the project already lets him approve his own entries
create or replace function public._r1_can_act(r public.pay_requests, p_uid uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare maker boolean;
begin
  if not public._r1_approver_ok(p_uid, r.kind) then return false; end if;
  maker := p_uid = r.requested_by or (r.employee_id is not null and r.employee_id = public._r1_my_emp(p_uid));
  if not maker then return true; end if;
  return public._r1_is_owner_uid(p_uid) and public.rule_on('owner_self_approve') and public._owner_mode() <> 'named';
end $$;

create or replace function public._r1_visible(p_by uuid, p_emp uuid, p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (p_by = auth.uid() or public.is_owner() or (p_emp is not null and p_emp = public._r1_my_emp()) or public._r1_approver_ok(auth.uid(), p_kind)) $$;
create or replace function public._r1_req_visible(p_id bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.pay_requests r where r.id = p_id and public._r1_visible(r.requested_by, r.employee_id, r.kind)) $$;

drop policy if exists pay_requests_read on public.pay_requests;
create policy pay_requests_read on public.pay_requests for select to authenticated using (public._r1_visible(requested_by, employee_id, kind));
drop policy if exists pay_request_events_read on public.pay_request_events;
create policy pay_request_events_read on public.pay_request_events for select to authenticated using (public._r1_req_visible(request_id));
drop policy if exists pay_request_exceptions_read on public.pay_request_exceptions;
create policy pay_request_exceptions_read on public.pay_request_exceptions for select to authenticated using (user_id = auth.uid() or public.is_owner());
grant select on public.pay_requests, public.pay_request_events, public.pay_request_exceptions to authenticated;

create or replace function public._r1_event(p_req bigint, p_action text, p_from text, p_to text, p_note text, p_data jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.pay_request_events (request_id, by_user, by_staff, action, from_status, to_status, note, data) values (p_req, auth.uid(), public._r1_staff(), p_action, p_from, p_to, left(p_note, 300), p_data);
end $$;

-- in-app note aimed at one person (notifications, phase 46). One note per request, event and person per day.
create or replace function public._r1_notify(p_user uuid, p_key text, p_tbn text, p_ten text, p_bbn text, p_ben text, p_route text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or to_regclass('public.notifications') is null then return; end if;
  insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key)
    values (p_user, 'all', 'pay_request', 'info', p_tbn, p_ten, p_bbn, p_ben, p_route, left(p_key, 80)) on conflict (kind, key, day) do nothing;
exception when others then null;     -- a note that cannot be written never stops a request
end $$;

-- the people who should hear about a new request: the configured person(s); the owner when the mode is owner. Never the maker.
create or replace function public._r1_approver_users(p_kind text, p_exclude uuid) returns setof uuid language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from public._r1_cfg(p_kind);
  if c.mode = 'user' and c.usr is not null then return query select p.id from public.profiles p where p.id = c.usr and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  elsif c.mode = 'role' and c.role is not null then return query select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id where ur.role_code = c.role and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  else return query select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id where ur.role_code = 'owner' and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;
end $$;

create or replace function public._r1_feature_on(p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'supplier' then public.rule_on('party_requests_on') else public.rule_on('pay_requests_on') end $$;
create or replace function public._r1_required(p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'supplier' then public.rule_on('party_requests_required')
              else public.rule_on('pay_requests_required') and coalesce(public.rule_txt('pay_requests_required_kinds'), 'both') in ('both', p_kind) end $$;

-- ============================================================================
-- Approver setting: one call, written to the audit log; the settings cannot be changed one by one from the browser
-- ============================================================================
create or replace function public._r1_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos120.setting', true), '') <> '1' then raise exception 'use pay_request_approver_set'; end if;
  return new;
end $$;
drop trigger if exists r1_rules_guard on public.rules;
create trigger r1_rules_guard before update on public.rules for each row
  when (new.key in ('pay_request_approver_mode', 'pay_request_approver_role', 'pay_request_approver_user', 'party_request_approver_mode', 'party_request_approver_role', 'party_request_approver_user'))
  execute function public._r1_rules_guard();

create or replace function public.pay_request_approver_set(p_scope text, p_mode text, p_role text default null, p_user uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pfx text; rl text := nullif(btrim(coalesce(p_role, '')), ''); old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope not in ('staff', 'party') then raise exception 'bad_value'; end if;
  if p_mode is null or p_mode not in ('owner', 'role', 'user') and not (p_scope = 'party' and p_mode = 'same') then raise exception 'bad_value'; end if;
  pfx := case p_scope when 'staff' then 'pay_request_approver_' else 'party_request_approver_' end;
  if p_mode = 'role' then
    if rl is null or not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active') then raise exception 'no_one_holds_role'; end if;
  elsif p_mode = 'user' then
    if p_user is null or not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  old := jsonb_build_object('mode', public.rule_txt(pfx || 'mode'), 'role', public.rule_txt(pfx || 'role'), 'user', public.rule_txt(pfx || 'user'));
  perform set_config('bos120.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = pfx || 'mode';
  update public.rules set value = case when p_mode = 'role' then to_jsonb(rl) end, updated_at = now(), updated_by = auth.uid() where key = pfx || 'role';
  update public.rules set value = case when p_mode = 'user' then to_jsonb(p_user::text) end, updated_at = now(), updated_by = auth.uid() where key = pfx || 'user';
  perform set_config('bos120.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._r1_staff(), 'pay_request_approver_set', 'rules', p_scope, jsonb_build_object('old', old, 'new', jsonb_build_object('mode', p_mode, 'role', rl, 'user', p_user), 'note', left(p_note, 300)));
  return jsonb_build_object('scope', p_scope, 'mode', p_mode, 'role', case when p_mode = 'role' then rl end, 'user', case when p_mode = 'user' then p_user end);
end $$;

-- ============================================================================
-- Sending, deciding, cancelling
-- ============================================================================
create or replace function public.pay_request_submit(p_kind text, p_amount numeric, p_reason text, p_needed_by date, p_employee uuid default null, p_client uuid default null,
  p_supplier uuid default null, p_bill uuid default null, p_bill_ref text default null, p_asked_by text default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today(); emp uuid; r public.pay_requests; id_ bigint; amt numeric := round(p_amount, 2); lim numeric; n int; out_ numeric; opn numeric;
  b public.purchase_bills; loc int; behalf boolean := false; u uuid; nm text; ref text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('salary', 'advance', 'supplier') then raise exception 'bad_kind'; end if;
  if not public._r1_feature_on(p_kind) then raise exception 'requests_off'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.pay_requests where client_id = p_client;
    if found then
      if r.requested_by <> me and not public.is_owner() then raise exception 'not allowed'; end if;
      return jsonb_build_object('id', r.id, 'status', r.status, 'repeat', true);
    end if;
  end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 or length(btrim(p_reason)) > 300 then raise exception 'reason_required'; end if;
  if p_needed_by is null or p_needed_by < today or p_needed_by > today + 366 then raise exception 'bad_date'; end if;
  if p_kind in ('salary', 'advance') then
    emp := coalesce(p_employee, public._r1_my_emp());
    if emp is null then raise exception 'no_employee_profile'; end if;
    if emp is distinct from public._r1_my_emp() then
      if not public._emp_ok(emp, array['payroll_manage']) then raise exception 'not allowed'; end if;
      behalf := true;
    end if;
    select e.primary_location_id into loc from public.employees e where e.id = emp and e.status in ('active', 'on_leave');
    if not found then raise exception 'employee_not_active'; end if;
    lim := public.rule_num('pay_request_max_per_month');
    if lim is not null then
      select count(*) into n from public.pay_requests q where q.employee_id = emp and q.status <> 'cancelled'
         and date_trunc('month', q.created_at at time zone 'Asia/Dhaka') = date_trunc('month', now() at time zone 'Asia/Dhaka');
      if n >= lim then raise exception 'monthly_request_limit' using detail = 'limit ' || lim::text; end if;
    end if;
    lim := public.rule_num('pay_request_advance_ceiling');
    if p_kind = 'advance' and lim is not null then
      select coalesce(sum(public._adv_outstanding(a.id)), 0) into out_ from public.employee_advances a where a.employee_id = emp and a.status = 'active';
      select coalesce(sum(case q.status when 'received' then q.amount else greatest(q.approved_amount - q.paid_amount, 0) end), 0) into opn
        from public.pay_requests q where q.employee_id = emp and q.kind = 'advance' and q.status in ('received', 'approved');
      if out_ + opn + amt > lim then raise exception 'advance_ceiling' using detail = 'open ' || (out_ + opn)::text || ' + ' || amt::text || ' > ' || lim::text; end if;
    end if;
    if p_loc is not null and p_loc <> loc then loc := p_loc; end if;
    insert into public.pay_requests (client_id, kind, requested_by, requested_staff, on_behalf, employee_id, location_id, amount, reason, needed_by)
      values (p_client, p_kind, me, public._r1_staff(), behalf, emp, loc, amt, left(btrim(p_reason), 300), p_needed_by) returning id into id_;
    nm := (select coalesce(full_name_en, full_name_bn) from public.employees where id = emp);
  else
    loc := p_loc;
    if loc is null or not exists (select 1 from public.locations where id = loc) then raise exception 'bad_location'; end if;
    if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
    if p_supplier is null or not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
    if amt > public._sup_balance(p_supplier) then raise exception 'overpaid'; end if;
    ref := nullif(left(btrim(coalesce(p_bill_ref, '')), 80), '');
    if p_bill is not null then
      select * into b from public.purchase_bills where id = p_bill and supplier_id = p_supplier and status <> 'void';
      if not found then raise exception 'bill_not_found'; end if;
      ref := coalesce(ref, b.bill_no);
    end if;
    insert into public.pay_requests (client_id, kind, requested_by, requested_staff, on_behalf, supplier_id, bill_id, bill_ref, asked_by_name, location_id, amount, reason, needed_by)
      values (p_client, 'supplier', me, public._r1_staff(), nullif(btrim(coalesce(p_asked_by, '')), '') is not null, p_supplier, p_bill, ref, nullif(left(btrim(coalesce(p_asked_by, '')), 80), ''), loc, amt, left(btrim(p_reason), 300), p_needed_by) returning id into id_;
    nm := (select name from public.suppliers where id = p_supplier);
  end if;
  perform public._r1_event(id_, 'received', null, 'received', p_reason, jsonb_build_object('amount', amt, 'needed_by', p_needed_by));
  for u in select * from public._r1_approver_users(p_kind, me) loop
    perform public._r1_notify(u, 'r1:' || id_ || ':new:' || u::text, 'নতুন পেমেন্ট অনুরোধ: ' || amt::text, 'New pay request: ' || amt::text || ' (' || coalesce(nm, '-') || ')',
      'দেখে সিদ্ধান্ত দিন।', 'Please look and decide.', 'payapprovals');
  end loop;
  return jsonb_build_object('id', id_, 'status', 'received', 'kind', p_kind, 'amount', amt, 'needed_by', p_needed_by);
end $$;

create or replace function public.pay_request_decide(p_id bigint, p_approve boolean, p_pay_date date default null, p_amount numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; today date := public._dhaka_today(); d date; a numeric; prev text; act text; nm text;
begin
  if not public.is_active() or p_approve is null then raise exception 'not allowed'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._r1_approver_ok(auth.uid(), r.kind) then raise exception 'approver_only'; end if;
  if not public._r1_can_act(r, auth.uid()) then raise exception 'self_approval'; end if;
  if r.status not in ('received', 'approved') then raise exception 'request_not_pending'; end if;
  prev := r.status;
  if p_approve then
    d := coalesce(p_pay_date, r.needed_by);
    if d < today or d > today + 366 then raise exception 'bad_date'; end if;
    a := round(coalesce(p_amount, r.approved_amount, r.amount), 2);
    if a is null or a <= 0 or a > r.amount then raise exception 'bad_amount'; end if;
    if r.paid_amount > 0 and (a < r.paid_amount) then raise exception 'bad_amount'; end if;
    if p_note is not null and length(p_note) > 300 then raise exception 'too_long'; end if;
    act := case when prev = 'approved' then 'redated' else 'approved' end;
    update public.pay_requests set status = 'approved', approved_amount = a, pay_date = d, date_changed = (d <> r.needed_by), decided_by = auth.uid(), decided_staff = public._r1_staff(),
           decided_at = now(), decision_note = nullif(btrim(left(p_note, 300)), ''), updated_at = now() where id = p_id;
    perform public._r1_event(p_id, act, prev, 'approved', p_note, jsonb_build_object('pay_date', d, 'needed_by', r.needed_by, 'approved_amount', a, 'date_changed', d <> r.needed_by));
    nm := case when d <> r.needed_by then 'আপনার অনুরোধে অন্য তারিখ দেওয়া হয়েছে: ' || d::text else 'অনুমোদিত, তারিখ ' || d::text end;
    perform public._r1_notify(r.requested_by, 'r1:' || p_id || ':' || act || ':' || d::text, nm,
      case when d <> r.needed_by then 'Your request was approved for another date: ' || d::text else 'Your request was approved. Pay date: ' || d::text end,
      'পরিমাণ ' || a::text, 'Amount ' || a::text, case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
  else
    if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
    if r.paid_amount > 0 then raise exception 'already_partly_paid'; end if;
    update public.pay_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = public._r1_staff(), decided_at = now(), decision_note = left(btrim(p_note), 300), updated_at = now() where id = p_id;
    perform public._r1_event(p_id, 'rejected', prev, 'rejected', p_note);
    perform public._r1_notify(r.requested_by, 'r1:' || p_id || ':rejected', 'আপনার অনুরোধ নাকচ হয়েছে', 'Your request was rejected', left(btrim(p_note), 200), left(btrim(p_note), 200),
      case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
  end if;
  return (select jsonb_build_object('id', q.id, 'status', q.status, 'pay_date', q.pay_date, 'approved_amount', q.approved_amount, 'date_changed', q.date_changed) from public.pay_requests q where q.id = p_id);
end $$;

create or replace function public.pay_request_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (r.requested_by = auth.uid() or public.is_owner() or (r.employee_id is not null and r.employee_id = public._r1_my_emp())) then raise exception 'not allowed'; end if;
  if r.status not in ('received', 'approved') then raise exception 'request_not_pending'; end if;
  if r.paid_amount > 0 then raise exception 'already_partly_paid'; end if;
  update public.pay_requests set status = 'cancelled', decision_note = coalesce(decision_note, left(btrim(p_note), 300)), updated_at = now() where id = p_id;
  perform public._r1_event(p_id, 'cancelled', r.status, 'cancelled', p_note);
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- ============================================================================
-- The payment gate (BEFORE INSERT on the three payment tables) and the paying call
-- ============================================================================
create or replace function public._r1_link(p_req bigint, p_amt numeric, p_tbl text, p_row text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; full_ boolean;
begin
  select * into r from public.pay_requests where id = p_req for update;
  full_ := r.paid_amount + p_amt >= coalesce(r.approved_amount, r.amount) - 0.004;
  update public.pay_requests set paid_amount = paid_amount + p_amt, status = case when full_ then 'paid' else status end, paid_at = case when full_ then now() else paid_at end,
         paid_by = auth.uid(), paid_ref = left(coalesce(nullif(paid_ref, '') || ', ', '') || p_tbl || ':' || p_row, 300), updated_at = now() where id = p_req;
  perform public._r1_event(p_req, case when full_ then 'paid' else 'partly_paid' end, r.status, case when full_ then 'paid' else r.status end, null, jsonb_build_object('amount', p_amt, 'row', p_tbl || ':' || p_row));
  perform public._r1_notify(r.requested_by, 'r1:' || p_req || ':' || case when full_ then 'paid' else 'part' end || ':' || p_row, case when full_ then 'পেমেন্ট দেওয়া হয়েছে: ' || p_amt::text else 'আংশিক পেমেন্ট: ' || p_amt::text end,
    case when full_ then 'Paid: ' || p_amt::text else 'Part paid: ' || p_amt::text end, null, null, case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
end $$;

create or replace function public._r1_gate_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare k text; emp uuid; sup uuid; amt numeric; d date; cl uuid; explicit bigint := nullif(current_setting('r1.req', true), '')::bigint; r public.pay_requests; t public.pay_request_exceptions;
  tbl text := tg_table_name; today date := public._dhaka_today(); rid text := new.id::text;
begin
  if auth.uid() is null then return new; end if;                                  -- the system (backup, migration): never gated
  if tbl = 'employee_advances' then
    if new.mode = 'none' or new.status <> 'active' then return new; end if;        -- a paper-register entry moves no money
    k := 'advance'; emp := new.employee_id; amt := new.amount; d := new.adv_date; cl := new.client_id;
  elsif tbl = 'payroll_payments' then
    k := 'salary'; emp := new.employee_id; amt := new.amount; d := new.pay_date; cl := new.client_batch;
  else
    if new.bill_id is not null or new.kind is distinct from 'payment' or new.voided then return new; end if;    -- a payment made with a purchase bill is not covered
    k := 'supplier'; sup := new.supplier_id; amt := new.amount; d := (new.paid_at at time zone 'Asia/Dhaka')::date; cl := new.client_id;
  end if;
  -- 1. the paying call named its request: it must fit
  if explicit is not null then
    select * into r from public.pay_requests where id = explicit for update;
    if not found or r.status <> 'approved' or r.kind <> k or r.employee_id is distinct from emp or r.supplier_id is distinct from sup then raise exception 'pay_request_mismatch'; end if;
    if r.pay_date > today then raise exception 'not_due_yet'; end if;
    if r.paid_amount + amt > coalesce(r.approved_amount, r.amount) + 0.004 then raise exception 'pay_request_amount'; end if;
    perform public._r1_link(r.id, amt, tbl, rid); return new;
  end if;
  -- 2. policy off: nothing to check (today's behaviour)
  if not public._r1_required(k) then return new; end if;
  -- 3. an approved request that is due and big enough
  select * into r from public.pay_requests q where q.kind = k and q.status = 'approved' and q.employee_id is not distinct from emp and q.supplier_id is not distinct from sup
     and q.pay_date <= today and coalesce(q.approved_amount, q.amount) - q.paid_amount >= amt - 0.004 order by q.pay_date, q.id limit 1 for update skip locked;
  if found then perform public._r1_link(r.id, amt, tbl, rid); return new; end if;
  -- 4. one exception with a reason (opened by this person, valid for 30 minutes, one payment), logged to the Exceptions list
  select * into t from public.pay_request_exceptions x where x.user_id = auth.uid() and x.kind = k and x.used_at is null and x.expires_at > now()
     and x.employee_id is not distinct from emp and x.supplier_id is not distinct from sup and x.max_amount >= amt - 0.004 order by x.id limit 1 for update skip locked;
  if found then
    update public.pay_request_exceptions set used_at = now(), used_ref = tbl || ':' || rid where id = t.id;
    insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user)
      values ('r1_unbacked_payment', 'r1_pay_' || k, amt, tbl, rid, left('Paid without an approved request: ' || t.reason || ' (opened by ' || coalesce(public._r1_staff(t.opened_by), '-') || ')', 300), auth.uid());
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), public._r1_staff(), 'pay_request_exception_used', tbl, rid, jsonb_build_object('kind', k, 'amount', amt, 'reason', t.reason, 'exception_id', t.id));
    return new;
  end if;
  -- 5. the owner's one-off override of phase 87 (event r1_pay_<kind>), if he gave one
  if public._m_grant_take('override', 'r1_pay_' || k, cl, null, amt, d, tbl) then return new; end if;
  raise exception 'pay_request_required' using detail = k || ' ' || amt::text;
end $$;

do $trg$ declare t text; begin
  foreach t in array array['employee_advances', 'payroll_payments', 'supplier_payments'] loop
    execute format('drop trigger if exists a0_r1_gate_bi on public.%I', t);
    execute format('create trigger a0_r1_gate_bi before insert on public.%I for each row execute function public._r1_gate_bi()', t);
  end loop;
end $trg$;

-- the one-payment exception (who may open it is the setting pay_request_exception_mode)
create or replace function public.pay_request_exception_open(p_kind text, p_subject uuid, p_amount numeric, p_reason text, p_for_user uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare md text := coalesce(public.rule_txt('pay_request_exception_mode'), 'reason'); amt numeric := round(p_amount, 2); u uuid := coalesce(p_for_user, auth.uid()); id_ bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('salary', 'advance', 'supplier') then raise exception 'bad_kind'; end if;
  if not public._r1_required(p_kind) then raise exception 'not_required'; end if;
  if md = 'never' then raise exception 'exceptions_off'; end if;
  if (md = 'owner' or u <> auth.uid()) and not public.is_owner() then raise exception 'owner_only'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if amt is null or amt <= 0 then raise exception 'bad_amount'; end if;
  if p_subject is null then raise exception 'subject_required'; end if;
  if p_kind = 'supplier' then
    if not exists (select 1 from public.suppliers where id = p_subject) then raise exception 'supplier_not_found'; end if;
  elsif not exists (select 1 from public.employees where id = p_subject) then raise exception 'not_found'; end if;
  insert into public.pay_request_exceptions (user_id, kind, employee_id, supplier_id, max_amount, reason, opened_by)
    values (u, p_kind, case when p_kind <> 'supplier' then p_subject end, case when p_kind = 'supplier' then p_subject end, amt, left(btrim(p_reason), 300), auth.uid()) returning id into id_;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._r1_staff(), 'pay_request_exception_open', 'pay_request_exceptions', id_::text, jsonb_build_object('kind', p_kind, 'subject', p_subject, 'amount', amt, 'for_user', u, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_, 'expires_at', (select expires_at from public.pay_request_exceptions where id = id_));
end $$;

-- pay an approved request through the EXISTING function; the payment source is chosen now (a money account, or a mode)
create or replace function public.pay_request_pay(p_id bigint, p_mode text default null, p_money_account bigint default null, p_ref text default null, p_note text default null,
  p_instalment numeric default null, p_recover_from date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; today date := public._dhaka_today(); amt numeric; md text; tag text := ''; ma public.money_accounts; ln public.payroll_lines; cid uuid; res jsonb; note_ text; q public.pay_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._r1_approver_ok(auth.uid(), r.kind) then raise exception 'approver_only'; end if;
  if not public._r1_can_act(r, auth.uid()) then raise exception 'self_payment'; end if;
  if r.status <> 'approved' then raise exception 'request_not_approved'; end if;
  if r.pay_date > today then raise exception 'not_due_yet'; end if;
  amt := round(coalesce(r.approved_amount, r.amount) - r.paid_amount, 2);
  if amt <= 0 then raise exception 'request_not_approved'; end if;
  if p_money_account is not null then
    select * into ma from public.money_accounts where id = p_money_account;
    if not found or not ma.active then raise exception 'money_account_inactive'; end if;
    md := public._m_mode_of_kind(ma.kind); tag := 'ma#' || p_money_account::text || ';';
  else
    md := lower(btrim(coalesce(p_mode, '')));
    if md not in ('cash', 'mobile', 'bank') and not (r.kind = 'supplier' and md = 'card') then raise exception 'mode_required'; end if;
  end if;
  cid := md5('r1pay:' || p_id::text || ':' || r.paid_amount::text)::uuid;
  note_ := left(tag || 'Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 300);
  perform set_config('r1.req', p_id::text, true);
  if r.kind = 'advance' then
    res := public.staff_advance_add(r.employee_id, today, amt, p_instalment, md, p_recover_from, note_, cid);
  elsif r.kind = 'salary' then
    select l.* into ln from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
     where l.employee_id = r.employee_id and l.active and pr.status in ('approved', 'paid') and l.net - l.paid_amount > 0 order by l.month, l.id limit 1;
    if not found then raise exception 'no_payroll_due'; end if;
    res := public.payroll_pay(ln.run_id, array[ln.id], md, today, left(tag || coalesce(nullif(btrim(p_ref), ''), 'REQ-' || p_id::text), 80), left('Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 300), cid, amt);
  else
    res := public.pay_supplier(r.supplier_id, r.location_id, jsonb_build_array(jsonb_build_object('mode', md, 'amount', amt, 'wallet', nullif(tag, ''), 'ref', left(coalesce(nullif(btrim(p_ref), ''), 'REQ-' || p_id::text), 60))),
      cid, left('Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 200));
    if coalesce((res ->> 'pending')::boolean, false) then raise exception 'held_by_payment_limit'; end if;
  end if;
  perform set_config('r1.req', '', true);
  select * into q from public.pay_requests where id = p_id;
  if q.paid_amount <= r.paid_amount then raise exception 'payment_not_linked'; end if;
  return jsonb_build_object('request_id', p_id, 'status', q.status, 'paid_amount', q.paid_amount, 'mode', md, 'result', res);
end $$;

-- ============================================================================
-- Reading: state, lists, counts
-- ============================================================================
create or replace function public.pay_request_state() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c1 record; c2 record; today date := public._dhaka_today(); me uuid := auth.uid();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into c1 from public._r1_cfg('salary'); select * into c2 from public._r1_cfg('supplier');
  return jsonb_build_object(
    'staff_on', public.rule_on('pay_requests_on'), 'party_on', public.rule_on('party_requests_on'),
    'staff_required', public.rule_on('pay_requests_required') , 'required_kinds', coalesce(public.rule_txt('pay_requests_required_kinds'), 'both'), 'party_required', public.rule_on('party_requests_required'),
    'exception_mode', coalesce(public.rule_txt('pay_request_exception_mode'), 'reason'),
    'max_per_month', public.rule_num('pay_request_max_per_month'), 'advance_ceiling', public.rule_num('pay_request_advance_ceiling'),
    'my_employee', public._r1_my_emp(), 'is_owner', public.is_owner(),
    'approver_staff', public._r1_approver_ok(me, 'salary'), 'approver_party', public._r1_approver_ok(me, 'supplier'),
    'can_on_behalf', public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = me and g.grant_code = 'payroll_manage' and (g.valid_until is null or g.valid_until > now())),
    'approver', jsonb_build_object('staff', jsonb_build_object('mode', c1.mode, 'role', c1.role, 'user', c1.usr, 'name', (select full_name from public.profiles where id = c1.usr)),
                                   'party', jsonb_build_object('mode', c2.mode, 'role', c2.role, 'user', c2.usr, 'name', (select full_name from public.profiles where id = c2.usr)),
                                   'party_same', coalesce(public.rule_txt('party_request_approver_mode'), 'same') = 'same'),
    'gate', jsonb_build_object('advance', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.employee_advances'::regclass),
                               'salary', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.payroll_payments'::regclass),
                               'supplier', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.supplier_payments'::regclass)),
    'counts', public.pay_request_counts(), 'today', today);
end $$;

create or replace function public.pay_request_counts() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today();
begin
  if not public.is_active() then return jsonb_build_object('inbox', 0, 'due', 0, 'mine_open', 0); end if;
  return jsonb_build_object(
    'inbox', (select count(*) from public.pay_requests r where r.status = 'received' and public._r1_can_act(r, me)),
    'due', (select count(*) from public.pay_requests r where r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)),
    'mine_open', (select count(*) from public.pay_requests r where r.status in ('received', 'approved') and (r.requested_by = me or r.employee_id = public._r1_my_emp())));
end $$;

-- p_scope: mine | inbox (waiting for me to decide) | due (approved, pay date today or earlier) | upcoming (approved, later date) | all (everything I may see)
create or replace function public.pay_request_list(p_scope text default 'mine', p_status text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today(); myemp uuid := public._r1_my_emp();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_scope is null or p_scope not in ('mine', 'inbox', 'due', 'upcoming', 'all') then raise exception 'bad_value'; end if;
  return jsonb_build_object('today', today, 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.sortkey, z.id desc) from (
    select r.id, r.kind, r.status, r.amount, r.approved_amount, r.paid_amount, r.reason, r.needed_by, r.pay_date, r.date_changed, r.decided_at, r.decision_note, r.paid_at, r.created_at as requested_at,
           r.requested_staff, r.on_behalf, r.employee_id, r.supplier_id, r.bill_id, r.bill_ref, r.asked_by_name, r.location_id, r.paid_ref,
           case when r.kind = 'supplier' then (select s.name from public.suppliers s where s.id = r.supplier_id) else (select coalesce(e.full_name_en, e.full_name_bn) from public.employees e where e.id = r.employee_id) end as subject,
           (r.requested_by = me or (r.employee_id is not null and r.employee_id = myemp)) as mine,
           (r.status in ('received', 'approved') and public._r1_can_act(r, me)) as can_decide,
           (r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)) as can_pay,
           (r.status in ('received', 'approved') and r.paid_amount = 0 and (r.requested_by = me or public.is_owner() or (r.employee_id is not null and r.employee_id = myemp))) as can_cancel,
           (r.status = 'approved' and r.pay_date < today) as overdue,
           coalesce((select jsonb_agg(jsonb_build_object('at', ev.at, 'action', ev.action, 'note', ev.note, 'by', ev.by_staff, 'data', ev.data) order by ev.id) from public.pay_request_events ev where ev.request_id = r.id), '[]'::jsonb) as events,
           case when r.status = 'approved' then 0 when r.status = 'received' then 1 else 2 end as sortkey
      from public.pay_requests r
     where public._r1_visible(r.requested_by, r.employee_id, r.kind)
       and (p_status is null or r.status = p_status)
       and case p_scope
             when 'mine' then (r.requested_by = me or (r.employee_id is not null and r.employee_id = myemp))
             when 'inbox' then r.status = 'received' and public._r1_can_act(r, me)
             when 'due' then r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)
             when 'upcoming' then r.status = 'approved' and r.pay_date > today and public._r1_can_act(r, me)
             else true end
     order by r.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ---------- the browser may call the API, never the helpers ----------
revoke all on function public._r1_exc_kinds_apply(), public._r1_staff(uuid), public._r1_is_owner_uid(uuid), public._r1_my_emp(uuid), public._r1_uuid(text), public._r1_cfg(text),
  public._r1_approver_ok(uuid, text), public._r1_can_act(public.pay_requests, uuid), public._r1_event(bigint, text, text, text, text, jsonb), public._r1_notify(uuid, text, text, text, text, text, text),
  public._r1_approver_users(text, uuid), public._r1_feature_on(text), public._r1_required(text), public._r1_link(bigint, numeric, text, text), public._r1_gate_bi(), public._r1_rules_guard() from public, anon, authenticated;
-- used inside row policies: they run as the caller, so the two predicates must stay callable
revoke all on function public._r1_visible(uuid, uuid, text), public._r1_req_visible(bigint) from public, anon;
grant execute on function public._r1_visible(uuid, uuid, text), public._r1_req_visible(bigint), public._r1_my_emp(uuid) to authenticated;
revoke all on function public.pay_request_approver_set(text, text, text, uuid, text), public.pay_request_submit(text, numeric, text, date, uuid, uuid, uuid, uuid, text, text, int),
  public.pay_request_decide(bigint, boolean, date, numeric, text), public.pay_request_cancel(bigint, text), public.pay_request_exception_open(text, uuid, numeric, text, uuid),
  public.pay_request_pay(bigint, text, bigint, text, text, numeric, date), public.pay_request_state(), public.pay_request_counts(), public.pay_request_list(text, text, int) from public, anon;
grant execute on function public.pay_request_approver_set(text, text, text, uuid, text), public.pay_request_submit(text, numeric, text, date, uuid, uuid, uuid, uuid, text, text, int),
  public.pay_request_decide(bigint, boolean, date, numeric, text), public.pay_request_cancel(bigint, text), public.pay_request_exception_open(text, uuid, numeric, text, uuid),
  public.pay_request_pay(bigint, text, bigint, text, text, numeric, date), public.pay_request_state(), public.pay_request_counts(), public.pay_request_list(text, text, int) to authenticated;

-- ===================== phase130.sql =====================
-- Phase 130 (package R2-A) - ANNOUNCEMENTS: a message from the owner (or a person he designates) to everyone, a role, a place or one person.
-- Paste after phase99 (needs phase7/8 rules + grants, phase11 no_hard_delete). Paste-twice safe. No earlier phase file is edited and NO shared function is
-- patched or re-created (nothing to hook): with the switch announce_on OFF (the default) nothing reads or writes these tables and every screen is as before.
--
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_ so it cannot clash with another package)
--   1. Setting   announce_on (rules, module people)   OFF by default. OFF = the headline bar is never shown, posting is refused (announce_off).
--   2. Grant     announce_post (grant_defs)           who may post. Nobody holds it by default except the owner. The owner gives it to a role (rule_grants)
--                or to one person (user_grants, optionally for one place only) on the existing Delegation board. A person's grant limited to one place can
--                post only to that place; a grant without a place can post to everyone, a role, a place or a person.
--   3. Tables    r2_announcements (the message, who, when, the audience, start / expiry, urgent flag, status active|withdrawn)
--                r2_announce_seen (read receipt: one row per person and announcement, written only by r2_announce_seen)
--                Both: row level security (a person reads only what is addressed to him, or what he posted; the owner reads all), no browser write, no delete.
--   4. API       r2_announce_state()                 switch, may I post, places I may post to
--                r2_announce_post(...)               post (checks switch, grant, target, dates; client id makes a retry harmless)
--                r2_announce_active()                what is on the bar for ME right now (empty when OFF)
--                r2_announce_seen(id)                "I have read this" (only for a person it is addressed to, only while it is on)
--                r2_announce_mine()                  what I posted (owner: all) with audience and seen counts
--                r2_announce_receipts(id)            who has seen it and who has not (poster and owner only)
--                r2_announce_withdraw(id, reason)    stop it now (poster and owner only; the row stays, nothing is deleted)
-- AUDIENCE: all = every active login; role = people holding that role; location = people linked to that place in user_locations; person = one login.
--   (A manager who reaches every place through the management role but has no user_locations row for it is not counted in a place audience.)

do $g$ begin
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.rule_on(text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null then
    raise exception 'phase130 needs the rules and grants engine (phase 7, 8, 10, 11) first';
  end if;
end $g$;

create or replace function public._r2a_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTING and GRANT (safe defaults: OFF, nobody)
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('announce_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'ঘোষণা ও নির্দেশ চালু (উপরের চলমান লাইন)', 'ঘোষণা / Announcements চালু (উপরের headline bar)', 'Announcements are on (headline bar at the top)',
  'বন্ধ থাকলে কোনো বার দেখা যায় না এবং ঘোষণা দেওয়া যায় না; অ্যাপ আগের মতোই চলে। চালু করলে যাদের জন্য ঘোষণা আছে তারা উপরে চলমান লাইন দেখবে।',
  'বন্ধ থাকলে কোনো bar দেখা যায় না, ঘোষণা দেওয়া যায় না; app আগের মতোই। চালু করলে যাদের জন্য ঘোষণা আছে তারা উপরে bar দেখবে।',
  'OFF = no bar is shown and nothing can be posted; the app is as before. ON = people an announcement is addressed to see a slim headline bar at the top. Who may post is the grant announce_post.', 1300)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('announce_post', 'people', 76, 'ঘোষণা / নির্দেশ দেওয়া (সবাইকে, ভূমিকাকে, শাখাকে বা একজনকে)', 'ঘোষণা / instruction দেওয়া (সবাই, role, শাখা বা একজন)', 'Post announcements and instructions (to everyone, a role, a place or one person)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLES
-- ============================================================================
create table if not exists public.r2_announcements (
  id bigserial primary key,
  client_id uuid unique,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  body text not null default '' check (char_length(body) <= 2000),
  urgent boolean not null default false,
  target_kind text not null check (target_kind in ('all', 'role', 'location', 'person')),
  target_role text references public.roles(code),
  target_location int references public.locations(id),
  target_user uuid references public.profiles(id),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active', 'withdrawn')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  withdrawn_by uuid, withdrawn_at timestamptz, withdrawn_reason text,
  check ((target_kind = 'all' and target_role is null and target_location is null and target_user is null)
      or (target_kind = 'role' and target_role is not null and target_location is null and target_user is null)
      or (target_kind = 'location' and target_location is not null and target_role is null and target_user is null)
      or (target_kind = 'person' and target_user is not null and target_role is null and target_location is null)),
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists r2_announcements_live on public.r2_announcements (starts_at, ends_at) where status = 'active';
create index if not exists r2_announcements_by on public.r2_announcements (created_by, created_at desc);

create table if not exists public.r2_announce_seen (
  announcement_id bigint not null references public.r2_announcements(id),
  user_id uuid not null references public.profiles(id),
  seen_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

create or replace function public._r2a_seen_guard() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'a read receipt is never changed or removed'; end $$;
drop trigger if exists r2_announce_seen_no_change on public.r2_announce_seen;
create trigger r2_announce_seen_no_change before update or delete on public.r2_announce_seen for each row execute function public._r2a_seen_guard();
drop trigger if exists r2_announcements_no_delete on public.r2_announcements;
create trigger r2_announcements_no_delete before delete on public.r2_announcements for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_announcements on public.r2_announcements;
create trigger audit_r2_announcements after insert or update on public.r2_announcements for each row execute function public.log_change('id');

-- ============================================================================
-- 3. HELPERS (answer about the caller only)
-- ============================================================================
-- is this announcement's audience the caller? (used by the read policy, so authenticated may execute it)
create or replace function public._r2_ann_to_me(p_kind text, p_role text, p_loc int, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and case p_kind
    when 'all' then true
    when 'role' then exists (select 1 from public.user_roles ur where ur.user_id = auth.uid() and ur.role_code = p_role)
    when 'location' then exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_loc)
    when 'person' then p_user = auth.uid()
    else false end;
$$;

-- the audience of one announcement: active logins it is addressed to
create or replace function public._r2_ann_audience(p_id bigint) returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p join public.r2_announcements a on a.id = p_id
   where p.status = 'active' and case a.target_kind
     when 'all' then true
     when 'role' then exists (select 1 from public.user_roles ur where ur.user_id = p.id and ur.role_code = a.target_role)
     when 'location' then exists (select 1 from public.user_locations ul where ul.user_id = p.id and ul.location_id = a.target_location)
     when 'person' then p.id = a.target_user
     else false end;
$$;

-- ============================================================================
-- 4. ROW LEVEL SECURITY (reads only; every write goes through the functions)
-- ============================================================================
alter table public.r2_announcements enable row level security;
alter table public.r2_announce_seen enable row level security;
revoke all on public.r2_announcements, public.r2_announce_seen from public, anon, authenticated;
grant select on public.r2_announcements, public.r2_announce_seen to authenticated;

drop policy if exists r2_ann_read on public.r2_announcements;
create policy r2_ann_read on public.r2_announcements for select to authenticated using (
  public.is_active() and (public.is_owner() or created_by = auth.uid() or (
    public.rule_on('announce_on') and status = 'active' and starts_at <= now() and (ends_at is null or ends_at > now())
    and public._r2_ann_to_me(target_kind, target_role, target_location, target_user))));
drop policy if exists r2_ann_seen_read on public.r2_announce_seen;
create policy r2_ann_seen_read on public.r2_announce_seen for select to authenticated using (
  public.is_active() and (public.is_owner() or user_id = auth.uid()
    or exists (select 1 from public.r2_announcements a where a.id = announcement_id and a.created_by = auth.uid())));

-- ============================================================================
-- 5. API
-- ============================================================================
create or replace function public.r2_announce_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('announce_on');
begin
  if not public.is_active() then return jsonb_build_object('on', false, 'can_post', false, 'can_post_all', false, 'post_locations', '[]'::jsonb); end if;
  return jsonb_build_object('on', v_on,
    'can_post_all', v_on and (public.is_owner() or public.has_grant('announce_post')),
    'can_post', v_on and (public.is_owner() or public.has_grant('announce_post')
                          or exists (select 1 from public.locations l where l.is_active and public.has_grant('announce_post', l.id))),
    'post_locations', case when v_on then coalesce((select jsonb_agg(l.id order by l.sort, l.id) from public.locations l where l.is_active and (public.is_owner() or public.has_grant('announce_post', l.id))), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.r2_announce_post(p_title text, p_body text, p_urgent boolean, p_kind text, p_target text,
                                                    p_starts timestamptz default null, p_ends timestamptz default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_loc int; v_user uuid; v_id bigint; v_start timestamptz := coalesce(p_starts, now());
        v_title text := btrim(coalesce(p_title, '')); v_body text := btrim(coalesce(p_body, '')); n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('announce_on') then raise exception 'announce_off'; end if;
  if p_kind is null or p_kind not in ('all', 'role', 'location', 'person') then raise exception 'bad_target'; end if;
  begin
    if p_kind = 'role' then v_role := nullif(btrim(coalesce(p_target, '')), '');
    elsif p_kind = 'location' then v_loc := p_target::int;
    elsif p_kind = 'person' then v_user := p_target::uuid; end if;
  exception when others then raise exception 'bad_target'; end;
  -- who may post: the owner, or a holder of announce_post (a grant limited to one place covers only that place)
  if not (public.is_owner() or public.has_grant('announce_post', v_loc)) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select id into v_id from public.r2_announcements where client_id = p_client; if found then return jsonb_build_object('id', v_id, 'repeat', true); end if; end if;
  if char_length(v_title) < 1 or char_length(v_title) > 120 then raise exception 'title_required'; end if;
  if char_length(v_body) > 2000 then raise exception 'text_too_long'; end if;
  if p_kind = 'role' and not exists (select 1 from public.roles where code = v_role and active) then raise exception 'bad_target'; end if;
  if p_kind = 'location' and not exists (select 1 from public.locations where id = v_loc and is_active) then raise exception 'bad_target'; end if;
  if p_kind = 'person' and not exists (select 1 from public.profiles where id = v_user and status = 'active') then raise exception 'bad_target'; end if;
  if v_start < now() - interval '1 day' or v_start > now() + interval '400 days' then raise exception 'bad_date'; end if;
  if p_ends is not null and (p_ends <= v_start or p_ends <= now()) then raise exception 'bad_date'; end if;
  insert into public.r2_announcements (client_id, title, body, urgent, target_kind, target_role, target_location, target_user, starts_at, ends_at, created_by)
    values (p_client, v_title, v_body, coalesce(p_urgent, false), p_kind, v_role, v_loc, v_user, v_start, p_ends, auth.uid()) returning id into v_id;
  select count(*) into n from public._r2_ann_audience(v_id);
  return jsonb_build_object('id', v_id, 'audience', n);
end $$;

-- what is on the bar for the caller right now
create or replace function public.r2_announce_active() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.rule_on('announce_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'urgent', a.urgent, 'target_kind', a.target_kind,
            'starts_at', a.starts_at, 'ends_at', a.ends_at, 'posted_at', a.created_at, 'poster', coalesce(nullif(p.full_name, ''), p.staff_id),
            'seen', exists (select 1 from public.r2_announce_seen s where s.announcement_id = a.id and s.user_id = auth.uid()))
            order by a.urgent desc, a.starts_at desc, a.id desc)
     from public.r2_announcements a left join public.profiles p on p.id = a.created_by
    where a.status = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())
      and public._r2_ann_to_me(a.target_kind, a.target_role, a.target_location, a.target_user)), '[]'::jsonb);
end $$;

-- "I have read this"
create or replace function public.r2_announce_seen(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.r2_announcements; v_at timestamptz;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('announce_on') then raise exception 'announce_off'; end if;
  select * into a from public.r2_announcements where id = p_id;
  if not found or a.status <> 'active' or a.starts_at > now() or (a.ends_at is not null and a.ends_at <= now())
     or not public._r2_ann_to_me(a.target_kind, a.target_role, a.target_location, a.target_user) then raise exception 'not allowed'; end if;
  insert into public.r2_announce_seen (announcement_id, user_id) values (p_id, auth.uid()) on conflict do nothing;
  select seen_at into v_at from public.r2_announce_seen where announcement_id = p_id and user_id = auth.uid();
  return jsonb_build_object('id', p_id, 'seen', true, 'seen_at', v_at);
end $$;

-- what I posted (the owner sees everything), newest first, with audience and seen counts
create or replace function public.r2_announce_mine(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x ->> 'created_at') desc, (x ->> 'id')::bigint desc) from (
    select jsonb_build_object('id', a.id, 'title', a.title, 'body', a.body, 'urgent', a.urgent, 'target_kind', a.target_kind, 'target_role', a.target_role,
           'target_location', a.target_location, 'target_user', a.target_user,
           'target_name', case a.target_kind when 'person' then (select coalesce(nullif(t.full_name, ''), t.staff_id) from public.profiles t where t.id = a.target_user) end,
           'starts_at', a.starts_at, 'ends_at', a.ends_at, 'status', a.status, 'created_at', a.created_at, 'created_by', a.created_by,
           'poster', coalesce(nullif(p.full_name, ''), p.staff_id), 'withdrawn_reason', a.withdrawn_reason,
           'live', (a.status = 'active' and a.starts_at <= now() and (a.ends_at is null or a.ends_at > now())),
           'audience', (select count(*) from public._r2_ann_audience(a.id)),
           'seen', (select count(*) from public.r2_announce_seen s where s.announcement_id = a.id)) as x
      from public.r2_announcements a left join public.profiles p on p.id = a.created_by
     where public.is_owner() or a.created_by = auth.uid()
     order by a.created_at desc, a.id desc limit greatest(1, least(coalesce(p_limit, 50), 200))) z), '[]'::jsonb);
end $$;

-- read receipts: who has seen it, who has not (poster and owner only)
create or replace function public.r2_announce_receipts(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.r2_announcements;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into a from public.r2_announcements where id = p_id;
  if not found or not (public.is_owner() or a.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('id', a.id, 'title', a.title, 'status', a.status,
    'seen', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id), 'seen_at', s.seen_at) order by s.seen_at)
                        from public.r2_announce_seen s join public.profiles p on p.id = s.user_id where s.announcement_id = a.id), '[]'::jsonb),
    'unseen', coalesce((select jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id)) order by p.full_name, p.staff_id)
                          from public._r2_ann_audience(a.id) au join public.profiles p on p.id = au.user_id
                         where not exists (select 1 from public.r2_announce_seen s where s.announcement_id = a.id and s.user_id = au.user_id)), '[]'::jsonb));
end $$;

create or replace function public.r2_announce_withdraw(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.r2_announcements;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into a from public.r2_announcements where id = p_id for update;
  if not found or not (public.is_owner() or a.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null or char_length(p_reason) > 200 then raise exception 'reason_required'; end if;
  if a.status = 'withdrawn' then return jsonb_build_object('id', p_id, 'repeat', true); end if;
  update public.r2_announcements set status = 'withdrawn', withdrawn_by = auth.uid(), withdrawn_at = now(), withdrawn_reason = btrim(p_reason) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'withdrawn');
end $$;

-- ============================================================================
-- 6. WHO MAY CALL WHAT (browsers: signed-in users only; helpers closed, except the one the read policy needs)
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_announce_state', 'r2_announce_post', 'r2_announce_active', 'r2_announce_seen', 'r2_announce_mine', 'r2_announce_receipts', 'r2_announce_withdraw',
                                                            '_r2_ann_to_me', '_r2_ann_audience', '_r2a_seen_guard', '_r2a_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('r2_announce_state', 'r2_announce_post', 'r2_announce_active', 'r2_announce_seen', 'r2_announce_mine', 'r2_announce_receipts', 'r2_announce_withdraw', '_r2_ann_to_me') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- ===================== phase131.sql =====================
-- Phase 131 (package R2-B) - TO-DO LIST: extra tasks and duties given by the owner (or a person he designates) to one person or to a role.
-- Paste after phase99 (needs phase7/8 rules + grants, phase11 no_hard_delete). Independent of phase130 and phase132. Paste-twice safe.
-- No earlier phase file is edited and NO shared function is patched or re-created (nothing to hook): with todo_on OFF (the default) nothing reads or writes
-- these tables and every screen is as before.
--
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_)
--   1. Settings  todo_on (OFF)           the whole to-do list: OFF = no card on Home, nothing can be assigned, the screen shows "off".
--                todo_repeat_on (OFF)    repeating duties (daily / weekly). OFF = a repeat other than "none" is refused (repeat_off).
--   2. Grant     todo_assign             who may give tasks. Nobody holds it by default except the owner; the owner gives it to a role or one person
--                                        on the existing Delegation board.
--   3. Table     r2_todos                one row per person per task. A task given to a ROLE becomes one row for each active person who holds that role
--                                        at the moment it is given (people who join the role later do not get it). Fields: title, detail, due date, priority
--                                        (low|normal|high|urgent), status open|done|cannot|cancelled, the note (done note, or the reason for cannot / cancel),
--                                        who and when for every move, repeat kind, the task a repeat came from. Row level security: the assignee reads his own,
--                                        the assigner reads what he gave, the owner reads all; no browser write; no delete.
--   4. API       r2_todo_state()         switch, repeat switch, may I assign, my open / overdue counts and the next three (for the Home card)
--                r2_todo_assign(...)     give a task (person or role); a client id makes a retry harmless
--                r2_todo_mine(all)       MY list: open first (overdue marked), done / cannot of the last 30 days when asked
--                r2_todo_given(status)   what I gave (owner: everything), with the assignee and status
--                r2_todo_set(id, status, note)   the ASSIGNEE moves his own task: open -> done (note optional) or cannot (reason required)
--                r2_todo_manage(id, action, note)  the ASSIGNER (or owner): cancel (reason required) or reopen
--   5. Repeat    when a repeating task is marked done or cannot and todo_repeat_on is ON, the next one is created at once for the same person:
--                due = the later of (its due date, today) + 1 day (daily) or + 7 days (weekly); one open child at a time.

do $g$ begin
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.rule_on(text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null
     or to_regprocedure('public._client_lock(uuid)') is null then
    raise exception 'phase131 needs the rules and grants engine (phase 7, 8, 10, 11) first';
  end if;
end $g$;

create or replace function public._r2b_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS and GRANT (safe defaults: OFF, nobody)
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('todo_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'করণীয় তালিকা (অতিরিক্ত কাজ দেওয়া) চালু', 'করণীয় / To-do list চালু', 'To-do list is on (extra tasks given to people)',
  'বন্ধ থাকলে হোমে কোনো কার্ড নেই এবং কাজ দেওয়া যায় না; অ্যাপ আগের মতোই চলে। চালু করলে যাকে কাজ দেওয়া হয়েছে সে শুধু নিজের তালিকা দেখে।',
  'বন্ধ থাকলে Home-এ card নেই, কাজ দেওয়া যায় না; app আগের মতোই। চালু করলে যাকে কাজ দেওয়া হয়েছে সে শুধু নিজের list দেখে।',
  'OFF = no card on Home and nothing can be assigned; the app is as before. ON = a person sees only his own tasks; whoever gave a task sees what he gave. Who may give tasks is the grant todo_assign.', 1310),
 ('todo_repeat_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'করণীয়: প্রতিদিন / প্রতি সপ্তাহের পুনরাবৃত্ত কাজ চালু', 'করণীয়: daily / weekly repeat চালু', 'To-do: repeating duties (daily / weekly) are allowed',
  'বন্ধ থাকলে "পুনরাবৃত্তি" বাছাই করা যায় না। চালু থাকলে পুনরাবৃত্ত কাজ শেষ হলে (বা করা গেল না লিখলে) পরেরটি নিজে তৈরি হয়।',
  'বন্ধ থাকলে repeat বাছা যায় না। চালু থাকলে repeat কাজ done / cannot হলে পরেরটি নিজে তৈরি হয়।',
  'OFF = a repeat cannot be chosen. ON = when a repeating task is marked done (or cannot), the next one is created for the same person. Needs todo_on.', 1311)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('todo_assign', 'people', 77, 'অতিরিক্ত কাজ / করণীয় দেওয়া (একজনকে বা ভূমিকাকে)', 'অতিরিক্ত কাজ / to-do দেওয়া (একজন বা role)', 'Give extra tasks and duties (to a person or a role)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.r2_todos (
  id bigserial primary key,
  client_id uuid,
  batch_id uuid not null default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  detail text not null default '' check (char_length(detail) <= 2000),
  due_date date,
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assignee_user uuid not null references public.profiles(id),
  assigned_via text not null default 'person' check (assigned_via in ('person', 'role')),
  assigned_role text references public.roles(code),
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'done', 'cannot', 'cancelled')),
  status_note text check (status_note is null or char_length(status_note) <= 500),
  status_by uuid, status_at timestamptz,
  repeat_kind text not null default 'none' check (repeat_kind in ('none', 'daily', 'weekly')),
  repeat_parent bigint references public.r2_todos(id),
  check (status not in ('cannot', 'cancelled') or char_length(btrim(coalesce(status_note, ''))) > 0)
);
create unique index if not exists r2_todos_client_uq on public.r2_todos (client_id, assignee_user) where client_id is not null;
create unique index if not exists r2_todos_one_child on public.r2_todos (repeat_parent) where repeat_parent is not null and status = 'open';
create index if not exists r2_todos_assignee on public.r2_todos (assignee_user, status, due_date);
create index if not exists r2_todos_assigner on public.r2_todos (assigned_by, assigned_at desc);

drop trigger if exists r2_todos_no_delete on public.r2_todos;
create trigger r2_todos_no_delete before delete on public.r2_todos for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_todos on public.r2_todos;
create trigger audit_r2_todos after insert or update on public.r2_todos for each row execute function public.log_change('id');

alter table public.r2_todos enable row level security;
revoke all on public.r2_todos from public, anon, authenticated;
grant select on public.r2_todos to authenticated;
drop policy if exists r2_todos_read on public.r2_todos;
create policy r2_todos_read on public.r2_todos for select to authenticated using (
  public.is_active() and (public.is_owner() or assignee_user = auth.uid() or assigned_by = auth.uid()));

-- ============================================================================
-- 3. HELPERS
-- ============================================================================
create or replace function public._r2b_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- one task as json (the assignee and assigner names are looked up; used by the list functions)
create or replace function public._r2b_json(t public.r2_todos) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', t.id, 'batch_id', t.batch_id, 'title', t.title, 'detail', t.detail, 'due_date', t.due_date, 'priority', t.priority,
    'status', t.status, 'status_note', t.status_note, 'status_at', t.status_at, 'assigned_at', t.assigned_at, 'assigned_via', t.assigned_via, 'assigned_role', t.assigned_role,
    'assignee_id', t.assignee_user, 'assignee', (select coalesce(nullif(p.full_name, ''), p.staff_id) from public.profiles p where p.id = t.assignee_user),
    'assigner_id', t.assigned_by, 'assigner', (select coalesce(nullif(p.full_name, ''), p.staff_id) from public.profiles p where p.id = t.assigned_by),
    'repeat_kind', t.repeat_kind, 'repeat_parent', t.repeat_parent,
    'overdue', (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()));
$$;

-- the next occurrence of a repeating task (called after done / cannot; a no-op unless todo_repeat_on is ON)
create or replace function public._r2b_repeat_next(t public.r2_todos) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_due date;
begin
  if t.repeat_kind = 'none' or not public.rule_on('todo_repeat_on') then return null; end if;
  if exists (select 1 from public.r2_todos c where c.repeat_parent = t.id and c.status = 'open') then return null; end if;
  v_due := greatest(coalesce(t.due_date, public._r2b_today()), public._r2b_today()) + case t.repeat_kind when 'weekly' then 7 else 1 end;
  insert into public.r2_todos (batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_role, assigned_by, repeat_kind, repeat_parent)
    values (t.batch_id, t.title, t.detail, v_due, t.priority, t.assignee_user, t.assigned_via, t.assigned_role, t.assigned_by, t.repeat_kind, t.id) returning id into v_id;
  return v_id;
end $$;

-- ============================================================================
-- 4. API
-- ============================================================================
create or replace function public.r2_todo_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('todo_on'); v_open int; v_over int; v_next jsonb;
begin
  if not public.is_active() then return jsonb_build_object('on', false, 'repeat_on', false, 'can_assign', false, 'open', 0, 'overdue', 0, 'next', '[]'::jsonb); end if;
  if not v_on then return jsonb_build_object('on', false, 'repeat_on', false, 'can_assign', false, 'open', 0, 'overdue', 0, 'next', '[]'::jsonb); end if;
  select count(*), count(*) filter (where due_date is not null and due_date < public._r2b_today()) into v_open, v_over
    from public.r2_todos where assignee_user = auth.uid() and status = 'open';
  select coalesce(jsonb_agg(public._r2b_json(t) order by (t.due_date is not null and t.due_date < public._r2b_today()) desc,
                            case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.due_date nulls last, t.id), '[]'::jsonb) into v_next
    from (select * from public.r2_todos where assignee_user = auth.uid() and status = 'open'
           order by (due_date is not null and due_date < public._r2b_today()) desc, case priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, due_date nulls last, id limit 3) t;
  return jsonb_build_object('on', true, 'repeat_on', public.rule_on('todo_repeat_on'), 'can_assign', (public.is_owner() or public.has_grant('todo_assign')),
                            'open', v_open, 'overdue', v_over, 'next', v_next);
end $$;

create or replace function public.r2_todo_assign(p_title text, p_detail text, p_due date, p_priority text, p_kind text, p_target text,
                                                 p_repeat text default 'none', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_role text; v_user uuid; v_batch uuid := gen_random_uuid(); v_title text := btrim(coalesce(p_title, '')); v_detail text := btrim(coalesce(p_detail, ''));
        v_pri text := coalesce(nullif(btrim(p_priority), ''), 'normal'); v_rep text := coalesce(nullif(btrim(p_repeat), ''), 'none'); ids bigint[] := '{}'; v_id bigint; r record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  if not (public.is_owner() or public.has_grant('todo_assign')) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('person', 'role') then raise exception 'bad_target'; end if;
  begin
    if p_kind = 'role' then v_role := nullif(btrim(coalesce(p_target, '')), ''); else v_user := p_target::uuid; end if;
  exception when others then raise exception 'bad_target'; end;
  perform public._client_lock(p_client);
  if p_client is not null then
    select array_agg(id order by id) into ids from public.r2_todos where client_id = p_client and assigned_by = auth.uid();
    if ids is not null then return jsonb_build_object('count', cardinality(ids), 'ids', to_jsonb(ids), 'repeat', true); end if;
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 120 then raise exception 'title_required'; end if;
  if char_length(v_detail) > 2000 then raise exception 'text_too_long'; end if;
  if v_pri not in ('low', 'normal', 'high', 'urgent') then raise exception 'bad_priority'; end if;
  if v_rep not in ('none', 'daily', 'weekly') then raise exception 'bad_repeat'; end if;
  if v_rep <> 'none' and not public.rule_on('todo_repeat_on') then raise exception 'repeat_off'; end if;
  if p_due is not null and (p_due < public._r2b_today() or p_due > public._r2b_today() + 730) then raise exception 'bad_date'; end if;
  if p_kind = 'person' then
    if not exists (select 1 from public.profiles where id = v_user and status = 'active') then raise exception 'bad_target'; end if;
    insert into public.r2_todos (client_id, batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_by, repeat_kind)
      values (p_client, v_batch, v_title, v_detail, p_due, v_pri, v_user, 'person', auth.uid(), v_rep) returning id into v_id;
    ids := array[v_id];
  else
    if not exists (select 1 from public.roles where code = v_role and active) then raise exception 'bad_target'; end if;
    for r in select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id and ur.role_code = v_role where p.status = 'active' order by p.id loop
      insert into public.r2_todos (client_id, batch_id, title, detail, due_date, priority, assignee_user, assigned_via, assigned_role, assigned_by, repeat_kind)
        values (p_client, v_batch, v_title, v_detail, p_due, v_pri, r.id, 'role', v_role, auth.uid(), v_rep) returning id into v_id;
      ids := ids || v_id;
    end loop;
    if cardinality(ids) = 0 then raise exception 'no_recipients'; end if;
  end if;
  return jsonb_build_object('count', cardinality(ids), 'ids', to_jsonb(ids), 'batch_id', v_batch);
end $$;

-- MY list. p_all = also the done / cannot ones of the last 30 days. Cancelled tasks are not shown to the assignee.
create or replace function public.r2_todo_mine(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.rule_on('todo_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public._r2b_json(t) order by (t.status = 'open') desc, (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()) desc,
                                    case t.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, t.due_date nulls last, t.id)
     from public.r2_todos t
    where t.assignee_user = auth.uid() and (t.status = 'open' or (coalesce(p_all, false) and t.status in ('done', 'cannot') and t.status_at > now() - interval '30 days'))), '[]'::jsonb);
end $$;

-- what I gave (the owner sees everything). p_status null = all, or open|done|cannot|cancelled
create or replace function public.r2_todo_given(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public._r2b_json(t) order by (t.status = 'open') desc, (t.status = 'open' and t.due_date is not null and t.due_date < public._r2b_today()) desc,
                                    t.due_date nulls last, t.id desc)
     from (select * from public.r2_todos x where (public.is_owner() or x.assigned_by = auth.uid()) and (p_status is null or x.status = p_status)
            order by x.assigned_at desc, x.id desc limit 300) t), '[]'::jsonb);
end $$;

-- the ASSIGNEE moves his own task
create or replace function public.r2_todo_set(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.r2_todos; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_next bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  select * into t from public.r2_todos where id = p_id for update;
  if not found or t.assignee_user <> auth.uid() then raise exception 'not allowed'; end if;
  if p_status is null or p_status not in ('done', 'cannot') then raise exception 'bad_status'; end if;
  if v_note is not null and char_length(v_note) > 500 then raise exception 'text_too_long'; end if;
  if p_status = 'cannot' and v_note is null then raise exception 'reason_required'; end if;
  if t.status = p_status then return jsonb_build_object('id', p_id, 'status', t.status, 'repeat', true); end if;
  if t.status <> 'open' then raise exception 'not_open'; end if;
  update public.r2_todos set status = p_status, status_note = v_note, status_by = auth.uid(), status_at = now() where id = p_id returning * into t;
  v_next := public._r2b_repeat_next(t);
  return jsonb_build_object('id', p_id, 'status', p_status, 'next_id', v_next);
end $$;

-- the ASSIGNER (or the owner): cancel with a reason, or reopen
create or replace function public.r2_todo_manage(p_id bigint, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.r2_todos; v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('todo_on') then raise exception 'todo_off'; end if;
  select * into t from public.r2_todos where id = p_id for update;
  if not found or not (public.is_owner() or t.assigned_by = auth.uid()) then raise exception 'not allowed'; end if;
  if p_action is null or p_action not in ('cancel', 'reopen') then raise exception 'bad_status'; end if;
  if v_note is not null and char_length(v_note) > 500 then raise exception 'text_too_long'; end if;
  if p_action = 'cancel' then
    if v_note is null then raise exception 'reason_required'; end if;
    if t.status = 'cancelled' then return jsonb_build_object('id', p_id, 'status', 'cancelled', 'repeat', true); end if;
    if t.status <> 'open' then raise exception 'not_open'; end if;
    update public.r2_todos set status = 'cancelled', status_note = v_note, status_by = auth.uid(), status_at = now() where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'cancelled');
  end if;
  if t.status = 'open' then return jsonb_build_object('id', p_id, 'status', 'open', 'repeat', true); end if;
  update public.r2_todos set status = 'open', status_note = case when v_note is null then null else 'reopened: ' || v_note end, status_by = auth.uid(), status_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'open');
end $$;

-- ============================================================================
-- 5. WHO MAY CALL WHAT
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_todo_state', 'r2_todo_assign', 'r2_todo_mine', 'r2_todo_given', 'r2_todo_set', 'r2_todo_manage',
                                                            '_r2b_today', '_r2b_json', '_r2b_repeat_next', '_r2b_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname in ('r2_todo_state', 'r2_todo_assign', 'r2_todo_mine', 'r2_todo_given', 'r2_todo_set', 'r2_todo_manage') then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- ===================== phase132.sql =====================
-- Phase 132 (package R2-C) - SHIFT SCHEDULE: shift templates, a weekly roster per person and place, off-days, leave / swap notes,
-- "my upcoming shifts and who else is on at my place", and a soft roster-versus-attendance report.
-- Paste after phase99 (needs phase41/42: employees, shifts, employee_shift_assignments, holidays, leave_requests). Independent of phases 130 and 131.
-- Paste-twice safe. No earlier phase file is edited and NO shared function is patched or re-created (nothing to hook): with shift_on OFF (the default)
-- nothing here reads or writes anything, and attendance, leave and payroll work exactly as before.
--
-- REUSE (nothing is duplicated):
--   * Shift TEMPLATES are the existing `shifts` table (name, start, end, place). A person holding shift_manage may add or retire a template at his place
--     through r2_shift_template_save (same table, same checks as shift_save, but with the new grant instead of attendance_manage).
--   * The recurring weekly pattern already exists: employee_shift_assignments (weekday mask, off mask) written by shift_assign. It is READ here as the base
--     of the roster; this file never writes it.
--   * Holidays (holidays) and approved leave (leave_requests) are READ to mark a day. Attendance (attendance_days) is READ by the report only when it exists.
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_)
--   1. Settings  shift_on (OFF)           the whole shift schedule. OFF = no screen data, no edits (shift_off).
--                shift_mates_on (ON)      staff see who else is on at their place (only when shift_on is ON). OFF = a person sees only his own shifts.
--   2. Grant     shift_manage             who may schedule (templates, roster cells). Nobody holds it by default except the owner. Scope: the person's
--                                         PRIMARY place, the same rule as attendance_manage (_emp_ok); a grant limited to one place covers that place.
--   3. Table     r2_roster_days           one row per person and day that SAYS something: a shift (a template) or an off-day, with a leave / swap note.
--                                         A day with no row follows the weekly pattern (employee_shift_assignments), or shows nothing. Row level security: no
--                                         browser access at all (read through the functions); never deleted (clear = active false; the audit log keeps every change).
--   4. API       r2_shift_state()          switch, may I schedule, places I may schedule, am I linked to an employee record
--                r2_shift_my(from, days)   MY days (default 14): shift, off, note, holiday, approved leave, and (if shift_mates_on) who else is on at my place
--                r2_shift_roster(loc, from, days)   the roster grid for one place (schedulers only): people x days + the templates
--                r2_roster_set / r2_roster_clear / r2_roster_week / r2_roster_copy_week   edit cells (schedulers only)
--                r2_shift_template_save(id, data)   add / edit / retire a template (schedulers; owner may use "every place")
--                r2_shift_report(loc, from, to)     roster versus actual attendance, only if attendance_days exists (soft link, read only)

do $g$ begin
  if to_regclass('public.shifts') is null or to_regclass('public.employees') is null or to_regclass('public.employee_shift_assignments') is null
     or to_regprocedure('public._emp_ok(uuid,text[],boolean)') is null or to_regprocedure('public._loc_ok(integer,text)') is null
     or to_regprocedure('public._att_is_off(uuid,date)') is null or to_regprocedure('public._hhmm(text)') is null then
    raise exception 'phase132 needs phase 41 and 42 (employees, shifts, shift pattern, attendance helpers) first';
  end if;
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null then
    raise exception 'phase132 needs the rules and grants engine (phase 7, 8, 11) first';
  end if;
end $g$;

create or replace function public._r2c_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS and GRANT
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('shift_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'শিফট রোস্টার চালু (কে কোন দিন কোন শিফটে)', 'শিফট roster চালু', 'Shift schedule is on (who works which shift on which day)',
  'বন্ধ থাকলে রোস্টারের কিছুই দেখা বা লেখা যায় না; হাজিরা, ছুটি ও বেতন আগের মতোই। চালু করলে কর্মী নিজের আগামী শিফট দেখে, নির্ধারিত ব্যক্তি রোস্টার সাজায়।',
  'বন্ধ থাকলে roster কিছুই দেখা বা লেখা যায় না; হাজিরা, ছুটি, বেতন আগের মতোই। চালু করলে কর্মী নিজের শিফট দেখে, নির্ধারিত ব্যক্তি roster সাজায়।',
  'OFF = no roster can be seen or written; attendance, leave and payroll are as before. ON = staff see their own coming shifts and a person holding shift_manage edits the roster.', 1320),
 ('shift_mates_on', 'people', 'switch', 'true'::jsonb, null, null, null, null,
  'রোস্টারে নিজের জায়গায় আর কে ডিউটিতে আছে তা কর্মী দেখবে', 'Roster-এ নিজের জায়গায় আর কে on আছে তা দেখবে', 'Staff see who else is on at their place',
  'শিফট রোস্টার চালু থাকলে কাজ করে। বন্ধ করলে কর্মী শুধু নিজের শিফট দেখে, সহকর্মীর নাম দেখে না।',
  'Shift roster চালু থাকলে কাজ করে। বন্ধ করলে কর্মী শুধু নিজের শিফট দেখে।',
  'Works only while shift_on is ON. OFF = a person sees only his own shifts, not his colleagues'' names.', 1321)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('shift_manage', 'people', 78, 'শিফট ও রোস্টার সাজানো (টেমপ্লেট, দিনের শিফট, অফ-ডে, ছুটি / বদলের নোট)', 'Shift ও roster সাজানো (template, শিফট, off-day, note)', 'Schedule shifts and the roster (templates, shifts, off-days, leave / swap notes)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.r2_roster_days (
  id bigserial primary key,
  employee_id uuid not null references public.employees(id),
  day date not null,
  shift_id int references public.shifts(id),
  is_off boolean not null default false,
  note text check (note is null or char_length(note) <= 200),
  location_id int references public.locations(id),
  active boolean not null default true,
  set_by uuid, set_at timestamptz not null default now(),
  check (is_off or shift_id is not null),
  check (not (is_off and shift_id is not null))
);
create unique index if not exists r2_roster_days_uq on public.r2_roster_days (employee_id, day) where active;
create index if not exists r2_roster_days_day on public.r2_roster_days (day, location_id) where active;

drop trigger if exists r2_roster_days_no_delete on public.r2_roster_days;
create trigger r2_roster_days_no_delete before delete on public.r2_roster_days for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_roster_days on public.r2_roster_days;
create trigger audit_r2_roster_days after insert or update on public.r2_roster_days for each row execute function public.log_change('id');

alter table public.r2_roster_days enable row level security;
revoke all on public.r2_roster_days from public, anon, authenticated;

-- ============================================================================
-- 3. HELPERS
-- ============================================================================
create or replace function public._r2c_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('shift_on') then raise exception 'shift_off'; end if;
end $$;

-- may the caller schedule this person?
create or replace function public._r2c_ok(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public._emp_ok(p_emp, array['shift_manage']);
$$;

-- The plan for a range of days: roster rows first, then the weekly pattern (employee_shift_assignments), else nothing.
-- One row per person and day that has a shift or an off-day. place_id = the row's place, else the template's place, else the person's primary place.
create or replace function public._r2_plan(p_from date, p_to date, p_emp uuid default null, p_loc int default null)
returns table (employee_id uuid, day date, shift_id int, is_off boolean, note text, source text, place_id int, holiday_bn text, holiday_en text)
language sql stable security definer set search_path = public as $$
  with days as (select g::date as d from generate_series(p_from, least(p_to, p_from + 92), interval '1 day') g),
  emps as (select e.id, e.primary_location_id from public.employees e where e.status in ('active', 'on_leave') and (p_emp is null or e.id = p_emp)),
  rd as (select r.* from public.r2_roster_days r where r.active and r.day between p_from and least(p_to, p_from + 92) and (p_emp is null or r.employee_id = p_emp)),
  cov as (select distinct on (a.employee_id, d.d) a.employee_id, d.d as day, a.shift_id, a.weekday_mask
            from public.employee_shift_assignments a join days d on d.d >= a.from_date and (a.to_date is null or d.d <= a.to_date)
           where a.active and (p_emp is null or a.employee_id = p_emp)
           order by a.employee_id, d.d, a.from_date desc, a.id desc),
  base as (
    select e.id as emp, d.d as day, e.primary_location_id as ploc,
           case when rd.id is not null then rd.shift_id
                when cov.employee_id is not null and (cov.weekday_mask & (1 << extract(dow from d.d)::int)) <> 0 and not public._att_is_off(e.id, d.d) then cov.shift_id end as sid,
           case when rd.id is not null then rd.is_off
                when cov.employee_id is not null then not ((cov.weekday_mask & (1 << extract(dow from d.d)::int)) <> 0 and not public._att_is_off(e.id, d.d)) else false end as off_,
           rd.note as note_, rd.location_id as rloc,
           case when rd.id is not null then 'day' when cov.employee_id is not null then 'pattern' end as src
      from emps e cross join days d
      left join rd on rd.employee_id = e.id and rd.day = d.d
      left join cov on cov.employee_id = e.id and cov.day = d.d
     where rd.id is not null or cov.employee_id is not null),
  placed as (select b.*, coalesce(b.rloc, sh.location_id, b.ploc) as pl from base b left join public.shifts sh on sh.id = b.sid)
  select p.emp, p.day, p.sid, p.off_, p.note_, p.src, p.pl, (public._att_holiday(p.pl, p.day)).name_bn, (public._att_holiday(p.pl, p.day)).name_en
    from placed p where (p_loc is null or p.pl = p_loc);
$$;

-- ============================================================================
-- 4. READ API
-- ============================================================================
create or replace function public.r2_shift_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('shift_on');
begin
  if not public.is_active() or not v_on then return jsonb_build_object('on', false, 'can_manage', false, 'locations', '[]'::jsonb, 'linked', false, 'mates_on', false); end if;
  return jsonb_build_object('on', true, 'mates_on', public.rule_on('shift_mates_on'),
    'can_manage', (public.is_owner() or exists (select 1 from public.locations l where l.is_active and public._loc_ok(l.id, 'shift_manage'))),
    'locations', coalesce((select jsonb_agg(l.id order by l.sort, l.id) from public.locations l where l.is_active and public._loc_ok(l.id, 'shift_manage')), '[]'::jsonb),
    'linked', exists (select 1 from public.employees e where e.profile_id = auth.uid() and e.status in ('active', 'on_leave')));
end $$;

create or replace function public.r2_shift_my(p_from date default null, p_days int default 14) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_from date := coalesce(p_from, public._dhaka_today()); v_days int := greatest(1, least(coalesce(p_days, 14), 62)); v_emp uuid; v_mates boolean := public.rule_on('shift_mates_on');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('shift_on') then return jsonb_build_object('on', false, 'linked', false, 'days', '[]'::jsonb); end if;
  select id into v_emp from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if v_emp is null then return jsonb_build_object('on', true, 'linked', false, 'days', '[]'::jsonb); end if;
  return jsonb_build_object('on', true, 'linked', true, 'employee_id', v_emp, 'mates_on', v_mates, 'days', coalesce((
    select jsonb_agg(jsonb_build_object('day', m.day, 'dow', extract(dow from m.day)::int, 'off', m.is_off, 'note', m.note, 'source', m.source, 'place_id', m.place_id,
        'holiday_bn', m.holiday_bn, 'holiday_en', m.holiday_en,
        'leave', exists (select 1 from public.leave_requests lr where lr.employee_id = v_emp and lr.status = 'approved' and m.day between lr.from_date and lr.to_date),
        'shift', case when m.shift_id is null then null else (select jsonb_build_object('id', s.id, 'name_bn', s.name_bn, 'name_en', s.name_en, 'start', to_char(s.start_time, 'HH24:MI'),
                  'end', to_char(s.end_time, 'HH24:MI'), 'crosses_midnight', s.crosses_midnight) from public.shifts s where s.id = m.shift_id) end,
        'mates', case when not v_mates or m.is_off or m.shift_id is null or m.place_id is null then '[]'::jsonb else coalesce((
            select jsonb_agg(jsonb_build_object('name_bn', e2.full_name_bn, 'name_en', e2.full_name_en, 'shift_bn', s2.name_bn, 'shift_en', s2.name_en,
                   'start', to_char(s2.start_time, 'HH24:MI'), 'end', to_char(s2.end_time, 'HH24:MI')) order by s2.start_time, e2.full_name_bn)
              from public._r2_plan(m.day, m.day, null, m.place_id) o join public.employees e2 on e2.id = o.employee_id left join public.shifts s2 on s2.id = o.shift_id
             where o.employee_id <> v_emp and not o.is_off and o.shift_id is not null), '[]'::jsonb) end) order by m.day)
      from public._r2_plan(v_from, v_from + v_days - 1, v_emp) m), '[]'::jsonb));
end $$;

-- the roster grid of one place (schedulers only): people x days, plus the templates that can be used there
create or replace function public.r2_shift_roster(p_loc int, p_from date default null, p_days int default 7) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_from date := coalesce(p_from, public._dhaka_today()); v_days int := greatest(1, least(coalesce(p_days, 7), 31));
begin
  perform public._r2c_gate();
  if not public._loc_ok(p_loc, 'shift_manage') then raise exception 'not allowed'; end if;
  return jsonb_build_object('loc', p_loc, 'from', v_from, 'days', v_days,
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name_bn', s.name_bn, 'name_en', s.name_en, 'location_id', s.location_id,
                'start', to_char(s.start_time, 'HH24:MI'), 'end', to_char(s.end_time, 'HH24:MI'), 'crosses_midnight', s.crosses_midnight) order by s.start_time, s.id)
              from public.shifts s where s.active and (s.location_id is null or s.location_id = p_loc)), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en, 'nickname', e.nickname,
        'days', coalesce((select jsonb_agg(jsonb_build_object('day', m.day, 'shift_id', m.shift_id, 'off', m.is_off, 'note', m.note, 'source', m.source,
                  'holiday_bn', m.holiday_bn, 'holiday_en', m.holiday_en,
                  'leave', exists (select 1 from public.leave_requests lr where lr.employee_id = e.id and lr.status = 'approved' and m.day between lr.from_date and lr.to_date)) order by m.day)
                   from public._r2_plan(v_from, v_from + v_days - 1, e.id) m), '[]'::jsonb)) order by e.full_name_bn, e.id)
              from public.employees e where e.primary_location_id = p_loc and e.status in ('active', 'on_leave')), '[]'::jsonb));
end $$;

-- ============================================================================
-- 5. WRITE API (schedulers only; every move is an audit_log line through the table trigger)
-- ============================================================================
create or replace function public.r2_roster_set(p_emp uuid, p_day date, p_shift int, p_off boolean, p_note text default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_off boolean := coalesce(p_off, false); v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_place int; v_id bigint;
begin
  perform public._r2c_gate();
  select * into e from public.employees where id = p_emp and status in ('active', 'on_leave');
  if not found then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  if p_day is null or p_day < public._dhaka_today() - 7 or p_day > public._dhaka_today() + 400 then raise exception 'bad_date'; end if;
  if v_note is not null and char_length(v_note) > 200 then raise exception 'text_too_long'; end if;
  if v_off = (p_shift is not null) then raise exception 'bad_shift'; end if;                 -- exactly one of: a shift, or an off-day
  if p_shift is not null then
    select * into s from public.shifts where id = p_shift and active;
    if not found then raise exception 'bad_shift'; end if;
  end if;
  v_place := coalesce(p_loc, s.location_id, e.primary_location_id);
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'bad_location'; end if;
  insert into public.r2_roster_days (employee_id, day, shift_id, is_off, note, location_id, set_by)
    values (p_emp, p_day, p_shift, v_off, v_note, v_place, auth.uid())
    on conflict (employee_id, day) where active do update set shift_id = excluded.shift_id, is_off = excluded.is_off, note = excluded.note, location_id = excluded.location_id, set_by = auth.uid(), set_at = now()
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'employee_id', p_emp, 'day', p_day);
end $$;

create or replace function public.r2_roster_clear(p_emp uuid, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public._r2c_gate();
  if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  update public.r2_roster_days set active = false, set_by = auth.uid(), set_at = now() where employee_id = p_emp and day = p_day and active returning id into v_id;
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'cleared', v_id is not null);
end $$;

-- one person, seven days at once: p_days is a JSON array of up to 7 items, item i = day p_from + i; null = clear that day,
-- {"shift_id": n} or {"off": true}, optional "note"
create or replace function public.r2_roster_week(p_emp uuid, p_from date, p_days jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int; it jsonb; n_set int := 0; n_clear int := 0;
begin
  perform public._r2c_gate();
  if p_days is null or jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) > 7 or p_from is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  for i in 0 .. jsonb_array_length(p_days) - 1 loop
    it := p_days -> i;
    if it is null or jsonb_typeof(it) = 'null' then perform public.r2_roster_clear(p_emp, p_from + i); n_clear := n_clear + 1;
    else
      perform public.r2_roster_set(p_emp, p_from + i, nullif(it ->> 'shift_id', '')::int, coalesce((it ->> 'off')::boolean, false), it ->> 'note');
      n_set := n_set + 1;
    end if;
  end loop;
  return jsonb_build_object('employee_id', p_emp, 'set', n_set, 'cleared', n_clear);
end $$;

-- copy the roster rows of one week to another week for everybody whose primary place is p_loc (cells that already have a row are kept)
create or replace function public.r2_roster_copy_week(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; n_copy int := 0; n_skip int := 0; v_off int;
begin
  perform public._r2c_gate();
  if not public._loc_ok(p_loc, 'shift_manage') then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from = p_to then raise exception 'bad_date'; end if;
  v_off := p_to - p_from;
  for r in select d.* from public.r2_roster_days d join public.employees e on e.id = d.employee_id
            where d.active and d.day between p_from and p_from + 6 and e.primary_location_id = p_loc and e.status in ('active', 'on_leave') order by d.employee_id, d.day loop
    if r.day + v_off < public._dhaka_today() - 7 or r.day + v_off > public._dhaka_today() + 400 then n_skip := n_skip + 1; continue; end if;
    if exists (select 1 from public.r2_roster_days x where x.employee_id = r.employee_id and x.day = r.day + v_off and x.active) then n_skip := n_skip + 1; continue; end if;
    insert into public.r2_roster_days (employee_id, day, shift_id, is_off, note, location_id, set_by) values (r.employee_id, r.day + v_off, r.shift_id, r.is_off, r.note, r.location_id, auth.uid());
    n_copy := n_copy + 1;
  end loop;
  return jsonb_build_object('copied', n_copy, 'skipped', n_skip);
end $$;

-- add / edit / retire a shift template (the existing `shifts` table). data: name_bn, name_en, location_id, start_time, end_time, active
create or replace function public.r2_shift_template_save(p_id int, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); s public.shifts; v_loc int; v_id int;
begin
  perform public._r2c_gate();
  if p_id is not null then select * into s from public.shifts where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  v_loc := case when d ? 'location_id' then public._e_num(d, 'location_id', 1, 100000)::int else s.location_id end;
  if not (public.is_owner() or (v_loc is not null and public._loc_ok(v_loc, 'shift_manage') and (p_id is null or s.location_id is not distinct from v_loc))) then raise exception 'not allowed'; end if;
  if v_loc is not null and not exists (select 1 from public.locations where id = v_loc and is_active) then raise exception 'bad_location'; end if;
  s.name_bn := coalesce(public._e_txt(d, 'name_bn', 60), s.name_bn);
  s.name_en := case when d ? 'name_en' then public._e_txt(d, 'name_en', 60) else s.name_en end;
  s.location_id := v_loc;
  s.start_time := coalesce(public._hhmm(d ->> 'start_time'), s.start_time);
  s.end_time := coalesce(public._hhmm(d ->> 'end_time'), s.end_time);
  s.active := coalesce((d ->> 'active')::boolean, s.active, true);
  if s.name_bn is null then raise exception 'name_required'; end if;
  if s.start_time is null or s.end_time is null then raise exception 'bad_time'; end if;
  s.crosses_midnight := s.end_time <= s.start_time;
  if p_id is null then
    insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, crosses_midnight, active, created_by)
      values (s.name_bn, s.name_en, s.location_id, s.start_time, s.end_time, s.crosses_midnight, s.active, auth.uid()) returning id into v_id;
  else
    update public.shifts set name_bn = s.name_bn, name_en = s.name_en, location_id = s.location_id, start_time = s.start_time, end_time = s.end_time, crosses_midnight = s.crosses_midnight, active = s.active where id = p_id;
    v_id := p_id;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- ============================================================================
-- 6. SOFT LINK TO ATTENDANCE: roster versus what really happened (read only; answers "attendance: false" if the table is missing)
-- ============================================================================
create or replace function public.r2_shift_report(p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to date := least(coalesce(p_to, public._dhaka_today()), public._dhaka_today()); v_from date := coalesce(p_from, v_to - 6); v_rows jsonb; v_tot jsonb;
begin
  perform public._r2c_gate();
  if not (public._loc_ok(p_loc, 'shift_manage') or public._loc_ok(p_loc, 'attendance_manage')) then raise exception 'not allowed'; end if;
  if v_from > v_to or v_to - v_from > 61 then raise exception 'bad_date'; end if;
  if to_regclass('public.attendance_days') is null then return jsonb_build_object('attendance', false, 'from', v_from, 'to', v_to, 'rows', '[]'::jsonb, 'totals', '{}'::jsonb); end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.employee_id, 'name_bn', x.name_bn, 'name_en', x.name_en, 'day', x.day, 'planned', x.planned, 'shift_bn', x.shift_bn,
             'start', x.st, 'end', x.en, 'attendance', x.att, 'first_in', x.first_in, 'late_minutes', x.late_minutes, 'result', x.result) order by x.day, x.name_bn), '[]'::jsonb)
      from (select pl.employee_id, e.full_name_bn as name_bn, e.full_name_en as name_en, pl.day, (not pl.is_off) as planned, s.name_bn as shift_bn,
                   to_char(s.start_time, 'HH24:MI') as st, to_char(s.end_time, 'HH24:MI') as en, a.status as att, a.first_in, a.late_minutes,
                   case when not pl.is_off then case when a.employee_id is null then 'no_record' when a.status = 'present' then 'ok' when a.status = 'late' then 'late' when a.status = 'half_day' then 'half_day'
                                                    when a.status = 'leave' then 'leave' when a.status in ('absent', 'unpaid') then 'absent' else 'other' end
                        else case when a.status in ('present', 'late', 'half_day') then 'worked_off' else 'off' end end as result
              from public._r2_plan($1, $2, null, $3) pl join public.employees e on e.id = pl.employee_id
              left join public.shifts s on s.id = pl.shift_id
              left join public.attendance_days a on a.employee_id = pl.employee_id and a.day = pl.day
             where pl.day <= (now() at time zone 'Asia/Dhaka')::date
             order by pl.day, e.full_name_bn limit 600) x
  $q$ into v_rows using v_from, v_to, p_loc;
  select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) into v_tot from (select r ->> 'result' as k, count(*) as c from jsonb_array_elements(v_rows) r group by 1) z;
  return jsonb_build_object('attendance', true, 'from', v_from, 'to', v_to, 'rows', v_rows, 'totals', v_tot);
end $$;

-- ============================================================================
-- 7. WHO MAY CALL WHAT
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_shift_state', 'r2_shift_my', 'r2_shift_roster', 'r2_roster_set', 'r2_roster_clear', 'r2_roster_week', 'r2_roster_copy_week',
                                                            'r2_shift_template_save', 'r2_shift_report', '_r2c_gate', '_r2c_ok', '_r2_plan', '_r2c_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'r2\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;

-- ===================== phase140.sql =====================
-- Phase 140 (bos140) - W1-FIX: a sale void follows the return rules (finding 4 of the independent Wave 1 check). Paste after phase99, paste-twice safe. Earlier phase files are not edited.
--
-- THE GAP: void_sale cancels a whole sale and the stock trigger puts every unit back on the shelf, with no return window, no "never put back" class rule and no
-- expired-batch rule. A person who is refused a return (phase91) could void the sale instead.
--
-- WHAT THIS ADDS: ONE owner setting, void_follows_return_rules (switch, default OFF = exactly today). When ON, void_sale asks the same questions the return
-- code asks (phase91): is the sale inside the return window of each item class, is any item in a class that is never put back (a void puts everything back),
-- and (rule return_expired_restock = writeoff or block) would an expired batch go back on the shelf. If any answer is "no" the void is REFUSED with the
-- same code the return screen already shows (return_window_exceeded, return_restock_not_allowed, return_expired_restock) unless the caller holds the grant
-- return_override (the owner always does; the owner can give it to anyone). That override needs the void note (already required) as its reason and writes one
-- audit_log line (void_override) and one row in the Exceptions list (flag void_outside_return_rules). The receipt rule is not asked: a void is made from the sale itself.
--
-- HOW: one hook line in void_sale, written by the patch helper _w1x_patch (marker bos140), exactly as the Wave 1 packages did it (docs/integration/W1-FIX.md).
-- phase143 (re-patch) puts the line back if an old phase re-creates void_sale. With the setting OFF the hook returns at once: nothing else changes.

do $g$ begin
  if to_regprocedure('public._w1c_present91()') is null then raise exception 'phase140 needs phase91 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase140 needs phase99 pasted first'; end if;
  if to_regprocedure('public.void_sale(uuid,text)') is null then raise exception 'phase140 needs void_sale'; end if;
end $g$;

create or replace function public._w1x_present140() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same logic as _w1c_patch; markers bos140 to bos149)
create or replace function public._w1x_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos14[0-9]$' then raise exception 'w1x_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1x_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1x_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1x_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1x_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- setting (default OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('void_follows_return_rules', 'pos', 'switch', 'false'::jsonb, null, null, null, null,
  'Voiding a sale follows the return rules', 'Voiding a sale follows the return rules', 'Voiding a sale follows the return rules',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list',
  'Off = today: a sale can be voided at any time by anyone who may void. On = a void is refused when a return of the same sale would be refused (return window, goods that are never put back, expired batch). The owner and anyone with the grant return_override may still void, with the void note as the reason; it is logged in the Exceptions list', 910)
on conflict (key) do nothing;

-- ---------- the check, called from the hook line in void_sale ----------
create or replace function public._w1x_void_guard(p_sale uuid, p_note text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.sales; lines jsonb; rs jsonb; ev jsonb; v text[] := '{}'; gwin numeric; age numeric; note text := nullif(btrim(coalesce(p_note, '')), ''); lvl text := 'yellow';
        uuid_re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if not coalesce(public.rule_on('void_follows_return_rules'), false) then return jsonb_build_object('skipped', 'setting_off'); end if;
  select * into s from public.sales where id = p_sale;
  if not found then return jsonb_build_object('skipped', 'not_found'); end if;
  -- the item lines of the sale, one line per item: a void puts the whole quantity of every item back on the shelf
  select jsonb_agg(jsonb_build_object('item_id', x.iid, 'qty', x.q) order by x.iid), jsonb_agg(jsonb_build_object('item_id', x.iid, 'restock_qty', x.q) order by x.iid)
    into lines, rs
    from (select e ->> 'item_id' iid, round(sum((e ->> 'qty')::numeric), 6)::text q
            from jsonb_array_elements(s.lines) e
           where jsonb_typeof(e) = 'object' and coalesce(e ->> 'item_id', '') ~ uuid_re and coalesce(e ->> 'qty', '') ~ '^[0-9]{1,9}(\.[0-9]{1,6})?$' and (e ->> 'qty')::numeric > 0
           group by 1) x
   where x.q::numeric > 0;
  if lines is not null then
    ev := public._w1c_return_eval(p_sale, lines, rs, s.receipt::text);        -- the receipt of this very sale is "shown"
    select coalesce(array_agg(z), '{}') into v from jsonb_array_elements_text(ev -> 'violations') z;
  else
    gwin := public.rule_num('return_window_hours');                            -- a sale without item lines (quick sale): only the general window can be asked
    age := round(extract(epoch from (now() - s.sold_at)) / 3600, 2);
    if gwin is not null and age > gwin then v := array['return_window_exceeded']; end if;
  end if;
  -- a void cannot write expired goods off, so in the modes writeoff and block it may not put them back on the shelf
  if coalesce(public.rule_txt('return_expired_restock'), 'allow') in ('writeoff', 'block')
     and exists (select 1 from public.stock_ledger l join public.stock_batches b on b.id = l.batch_id
                  where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out' and b.expires_at is not null and b.expires_at <= now()) then
    v := array_append(v, 'return_expired_restock'::text);
    lvl := 'red';
  end if;
  if array_length(v, 1) is null then return jsonb_build_object('ok', true); end if;
  -- outside the rules: only the owner or a person holding return_override, and only with a reason
  if not public.has_grant('return_override', s.location_id) then raise exception '%', v[1]; end if;
  if note is null or char_length(note) < 3 then raise exception 'return_override_reason_required'; end if;
  perform public._w1c_audit('void_override', 'sales', s.id::text, jsonb_build_object('receipt', s.receipt, 'rules_broken', to_jsonb(v), 'reason', note, 'amount', s.total, 'owner', public.is_owner()));
  perform public._w1c_exc(s.location_id, 'POS', 'void_outside_return_rules', lvl,
    'Receipt ' || s.receipt::text || ' was voided outside the return rules (' || array_to_string(v, ', ') || '). Reason: ' || note, s.id::text, s.total, s.sale_date);
  return jsonb_build_object('ok', true, 'override', true, 'rules_broken', to_jsonb(v));
end $$;
revoke all on function public._w1x_void_guard(uuid, text) from public, anon, authenticated;

-- ---------- the hook (idempotent: nothing happens when marker bos140 is already inside void_sale) ----------
create or replace function public._w1x140_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('void_sale', public._w1x_patch('public.void_sale(uuid,text)'::regprocedure, array[
    E'  if s.status = ''void'' then raise exception ''already void''; end if;',
    E'  if s.status = ''void'' then raise exception ''already void''; end if;\n  perform public._w1x_void_guard(s.id, p_note); /* bos140 */'
  ], 'bos140'));
end $$;
revoke all on function public._w1x140_hooks() from public, anon, authenticated;

select public._w1x140_hooks();

-- ===================== phase141.sql =====================
-- Phase 141 (bos141) - W1-FIX: the supplier payment limit can count over several days (finding 5 of the independent Wave 1 check). Paste after phase99, paste-twice safe.
-- Earlier phase files are not edited.
--
-- THE GAP: supplier_pay_over (phase94) is compared with the total of ONE pay_supplier call. A person who is not the owner can pay the same supplier in several
-- smaller calls and stay under the limit every time.
--
-- WHAT THIS ADDS: ONE owner setting, supplier_pay_over_cumulative_days (number of days, default 0 = exactly today: the limit is per call). When N is more than 0
-- the limit is compared with THIS payment PLUS what the SAME person has already paid to the SAME supplier in the last N days (payments not voided, plus that
-- person's requests still waiting for the approver). Approved requests are already payments (the payment keeps the maker's login), so nothing is counted twice.
-- The owner is still never held. The approver sees the reason in the request text ("plus Tk ... already paid or waiting by this person in the last N days").
--
-- HOW: two exact-text lines in _w1e_pay_gate (marker bos141), patched with _w1x_patch (docs/integration/W1-FIX.md). With the setting at 0 both helpers return
-- 0 / empty text and the gate behaves exactly as before. phase143 puts the lines back if phase94 is pasted again.

do $g$ begin
  if to_regprocedure('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)') is null then raise exception 'phase141 needs phase94 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase141 needs phase99 pasted first'; end if;
end $g$;

create or replace function public._w1x_present141() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same text as in phase140; create or replace is harmless to repeat)
create or replace function public._w1x_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos14[0-9]$' then raise exception 'w1x_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1x_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1x_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1x_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1x_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- setting (default 0 = per call, as today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('supplier_pay_over_cumulative_days', 'books', 'number', '0'::jsonb, 'days', null, 0, 365,
  'Supplier payment limit counts payments of the last days', 'Supplier payment limit counts payments of the last days', 'Supplier payment limit counts payments of the last days',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number',
  'Number of days. 0 = today: the limit above is compared with each payment on its own, so paying in smaller parts avoids it. A number of days (for example 7) = the limit is compared with this payment plus what the same person already paid to the same supplier in those days. The owner is not held. Only used when "A supplier payment above this amount waits for the approver" has a number', 750)
on conflict (key) do nothing;

-- ---------- what this person already paid or has waiting for this supplier in the last N days (0 when the setting is 0) ----------
create or replace function public._w1x_pay_prior(p_supplier uuid) returns numeric language plpgsql stable security definer set search_path = public as $$
declare n numeric := coalesce(public.rule_num('supplier_pay_over_cumulative_days'), 0); since timestamptz; paid numeric; waiting numeric;
begin
  if n <= 0 or auth.uid() is null then return 0; end if;
  since := now() - make_interval(secs => (n * 86400)::double precision);
  select coalesce(sum(amount), 0) into paid from public.supplier_payments where supplier_id = p_supplier and not voided and created_by = auth.uid() and paid_at >= since;
  select coalesce(sum((q.payload ->> 'total')::numeric), 0) into waiting from public.w1e_requests q
   where q.kind = 'supplier_pay' and q.status = 'pending' and q.requested_by = auth.uid() and q.payload ->> 'supplier' = p_supplier::text and q.requested_at >= since;
  return paid + waiting;
end $$;
revoke all on function public._w1x_pay_prior(uuid) from public, anon, authenticated;

-- the sentence added to the request text when earlier payments were counted
create or replace function public._w1x_pay_note(p_supplier uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare pr numeric := public._w1x_pay_prior(p_supplier); n numeric := coalesce(public.rule_num('supplier_pay_over_cumulative_days'), 0);
begin
  if pr <= 0 then return ''; end if;
  return ', plus ' || trim_scale(pr)::text || ' already paid or waiting by this person in the last ' || trim_scale(n)::text || ' day(s)';
end $$;
revoke all on function public._w1x_pay_note(uuid) from public, anon, authenticated;

-- ---------- the hooks (idempotent: nothing happens when marker bos141 is already inside _w1e_pay_gate) ----------
create or replace function public._w1x141_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object('_w1e_pay_gate', public._w1x_patch('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure, array[
    E'  if ov is not null and p_tot > ov and not public.is_owner() then',
    E'  if ov is not null and p_tot + public._w1x_pay_prior(p_supplier) > ov and not public.is_owner() then   /* bos141 */',
    E'|| '' (limit '' || ov::text || '')'', 300)',
    E'|| '' (limit '' || ov::text || public._w1x_pay_note(p_supplier) || '')'', 300)'
  ], 'bos141'));
end $$;
revoke all on function public._w1x141_hooks() from public, anon, authenticated;

select public._w1x141_hooks();

-- ===================== phase142.sql =====================
-- Phase 142 (bos142) - W1-FIX: a staff exit cannot be undone by linking a login or by a non-owner reactivation (finding 8 of the independent Wave 1 check).
-- Paste after phase99, paste-twice safe. Earlier phase files are not edited.
--
-- THE GAPS (both reproduced on a database built through phase 99 with exit_revoke_mode = auto, see tests in phase142_test.sql):
--   1. employee_link_profile on a person who has ALREADY left: the exit step ran when the status changed (and found no login, or an older one), so a login linked
--      afterwards stayed active. The leaver had a working login again.
--   2. When the owner counts on_leave as a leaving status (exit_revoke_statuses), a person with only the right employee_manage could set the status back to
--      active, and phase90 then enabled the login that the exit had disabled. (For resigned, terminated and retired employee_status_set already says owner_only.)
--
-- WHAT THIS CHANGES (no new switch: it follows the existing owner setting exit_revoke_mode; with it OFF nothing here does anything)
--   1. After a login is linked to a person whose status is a leaving status, the same exit step as at the moment of leaving runs again (_w1c_exit_apply):
--      mode auto = the new login is disabled and its grants end (unless the owner kept the access with a reason, or it is the owner role, or the caller's own login),
--      mode alert = the red line "login still active" is raised. Every outcome is in w1c_exit_log and one audit_log line (staff_exit_link_checked).
--   2. With mode auto, coming back from a leaving status when the login was disabled by the exit step needs the owner (error owner_only, the status is not changed).
--      The owner brings the person back as before; the existing step then enables the login and logs it with the reason (audit_log staff_exit_login_reenabled).
--
-- HOW: two exact-text lines, patched with _w1x_patch (markers bos142): one in employee_link_profile, one in employee_status_set (docs/integration/W1-FIX.md).
-- phase143 puts the lines back if phase12/phase41 is pasted again.

do $g$ begin
  if to_regprocedure('public._w1c_exit_apply(uuid,text,text,date,text)') is null then raise exception 'phase142 needs phase90 (and phase99)'; end if;
  if to_regprocedure('public._i1_apply_hooks()') is null then raise exception 'phase142 needs phase99 pasted first'; end if;
  if to_regprocedure('public.employee_link_profile(uuid,uuid)') is null or to_regprocedure('public.employee_status_set(uuid,text,date,text)') is null then
    raise exception 'phase142 needs the employee functions (phase41)';
  end if;
end $g$;

create or replace function public._w1x_present142() returns boolean language sql immutable as $$ select true $$;

-- patch helper of this package (same text as in phase140; create or replace is harmless to repeat)
create or replace function public._w1x_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos14[0-9]$' then raise exception 'w1x_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1x_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1x_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1x_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1x_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- 1. a login linked after the person left ----------
create or replace function public._w1x_link_after(p_emp uuid, p_profile uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.employees; mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); res jsonb;
begin
  if p_profile is null then return jsonb_build_object('skipped', 'unlinked'); end if;
  if mode = 'off' then return jsonb_build_object('skipped', 'mode_off'); end if;
  select * into e from public.employees where id = p_emp;
  if not found or not (e.status = any (public._w1c_exit_statuses())) then return jsonb_build_object('skipped', 'not_left'); end if;
  perform set_config('w1c.exit_done', '', true);                 -- the exit step may run again for the same person in this transaction
  res := public._w1c_exit_apply(e.id, e.status, e.status, coalesce(e.status_date, (now() at time zone 'Asia/Dhaka')::date), 'login linked after the person had left');
  perform public._w1c_audit('staff_exit_link_checked', 'employees', e.id::text, jsonb_build_object('profile', p_profile, 'status', e.status, 'mode', mode, 'result', res));
  return res;
end $$;
revoke all on function public._w1x_link_after(uuid, uuid) from public, anon, authenticated;

-- ---------- 2. coming back needs the owner when the exit step disabled the login ----------
create or replace function public._w1x_reactivate_guard(p_emp uuid, p_from text, p_to text) returns void language plpgsql security definer set search_path = public as $$
declare mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); sts text[] := public._w1c_exit_statuses(); e public.employees; st text; last_act text;
begin
  if mode <> 'auto' or public.is_owner() then return; end if;
  if not (p_from = any (sts)) or p_to = any (sts) then return; end if;      -- only a move from a leaving status to a staying one
  select * into e from public.employees where id = p_emp;
  if not found or e.profile_id is null then return; end if;
  select status into st from public.profiles where id = e.profile_id;
  if st is distinct from 'disabled' then return; end if;
  select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
  if last_act = 'revoked' then raise exception 'owner_only'; end if;
end $$;
revoke all on function public._w1x_reactivate_guard(uuid, text, text) from public, anon, authenticated;

-- ---------- the hooks (idempotent: nothing happens when marker bos142 is already inside the function) ----------
create or replace function public._w1x142_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return jsonb_build_object(
    'employee_link_profile', public._w1x_patch('public.employee_link_profile(uuid,uuid)'::regprocedure, array[
      E'  return jsonb_build_object(''id'', e.id, ''profile_id'', p_profile);',
      E'  perform public._w1x_link_after(e.id, p_profile); /* bos142 */\n  return jsonb_build_object(''id'', e.id, ''profile_id'', p_profile);'
    ], 'bos142'),
    'employee_status_set', public._w1x_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
      E'  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;',
      E'  perform public._w1x_reactivate_guard(e.id, e.status, p_status); /* bos142 */\n  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;'
    ], 'bos142'));
end $$;
revoke all on function public._w1x142_hooks() from public, anon, authenticated;

select public._w1x142_hooks();

-- ===================== phase143.sql =====================
-- Phase 143 (bos143) - W1-FIX re-patch: ONE call that puts every hook of phases 140 to 142 (W1-FIX) back, and a state check. Paste after phase142, paste-twice safe.
-- Earlier phase files are not edited. It changes no behaviour of its own.
--
-- WHY: phases 140 to 142 patch four old functions (void_sale, _w1e_pay_gate, employee_link_profile, employee_status_set) by exact text, like the Wave 1 hooks of
-- phase99. Pasting an OLD phase again (phase3/6 void_sale, phase94 _w1e_pay_gate, phase41 employee functions) replaces the function and the hook line is gone.
-- After such a paste run, in this order:   select public._i1_apply_hooks();   select public._w1x_apply_hooks();
-- Both are idempotent (a hook that is already inside is reported false and nothing is rewritten). Details: docs/integration/W1-FIX.md.

do $g$ begin
  if to_regprocedure('public._w1x_present140()') is null or to_regprocedure('public._w1x_present141()') is null or to_regprocedure('public._w1x_present142()') is null then
    raise exception 'phase143 needs phases 140, 141 and 142 pasted first';
  end if;
end $g$;

create or replace function public._w1x_present143() returns boolean language sql immutable as $$ select true $$;

-- the (function, marker) pairs W1-FIX expects
create or replace function public._w1x_expect() returns table (fn text, marker text) language sql immutable as $$
  values ('public.void_sale(uuid,text)'::text, 'bos140'::text),
         ('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)', 'bos141'),
         ('public.employee_link_profile(uuid,uuid)', 'bos142'),
         ('public.employee_status_set(uuid,text,date,text)', 'bos142')
$$;

create or replace function public._w1x_hooks_state() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('fn', e.fn, 'marker', e.marker,
           'present', to_regprocedure(e.fn) is not null and position(e.marker in pg_get_functiondef(to_regprocedure(e.fn))) > 0) order by e.fn, e.marker), '[]'::jsonb)
    from public._w1x_expect() e
$$;

-- one statement: if a patch site is missing the whole call stops and nothing is half patched
create or replace function public._w1x_apply_hooks() returns jsonb language plpgsql security definer set search_path = public as $$
declare res jsonb; bad text;
begin
  res := public._w1x140_hooks() || public._w1x141_hooks() || public._w1x142_hooks();
  select string_agg(x ->> 'fn' || ' (' || (x ->> 'marker') || ')', ', ') into bad from jsonb_array_elements(public._w1x_hooks_state()) x where not (x ->> 'present')::boolean;
  if bad is not null then raise exception 'w1x hooks missing after patching: %', bad; end if;
  return res;
end $$;
revoke all on function public._w1x_present143(), public._w1x_expect(), public._w1x_hooks_state(), public._w1x_apply_hooks() from public, anon, authenticated;

select public._w1x_apply_hooks();

-- ===================== phase300.sql =====================
-- Phase 300 (bos300, package CRM-A, local label 100) - CUSTOMER PROFILE PLUS: schema, settings, grants, helpers.
-- Paste AFTER phase99 (works on a database built through phase 98 as well). Paste-twice safe. Earlier phase files are not edited and NO shared function is patched or re-created.
-- Phase files 301 (write functions) and 302 (read functions: Customer 360, timeline, favourites, masked directory) follow.
--
-- WHAT THIS ADDS (all new objects; prefix crm_ for tables the CRM family shares, crma_ / _crma_ for the functions of this package)
--   customers (+4 nullable columns)  preferred_location_id, language ('bn' | 'en'), owner_user (the staff member who looks after the customer), credit_days (credit terms; informational)
--                                    type_code already exists (phase 8) and becomes writable through crma_customer_extras_save.
--   customer_phones      extra phone numbers (label, WhatsApp yes/no). The main number stays customers.mobile (the key POS and record_sale2 use) and customers.whatsapp.
--   customer_addresses   delivery points (label, area, landmark, delivery note, one default). The main address stays customers.address.
--   customer_dates       family dates (spouse, child, parent ... birthday / anniversary / other), month + day, year optional. Own birthday / anniversary stay in customers.
--   crm_tags, customer_tags   owner-editable tag list; tags on a customer (retired, never deleted).
--   crm_notes            notes with author and time (append-only; a note is retired with a reason, never changed or deleted). The old single customers.note is shown as the first note.
--   Settings (rules, module crm): crm_on (OFF), crm_second_phone_on (OFF), crm_mask_phone (OFF). Grants: crm_view, crm_contact_view (nobody holds them until the owner gives them).
--
-- NO BACKFILL ON PURPOSE. The customer screen reads the main mobile, WhatsApp, address, birthday and anniversary straight from customers, so the old customer form
-- (customer_save) and this package can never drift apart, and an existing customer shows a complete profile with no migration. The side tables hold only what is ADDITIONAL.
--
-- PRIVACY: the new tables are closed to browsers (no select grant, row security on). Everything is read through SECURITY DEFINER functions that mask phone numbers
-- when the owner switches crm_mask_phone ON and the caller has no right (owner, grant crm_contact_view, or the existing report right rpt_mobile_ok).
-- ACCOUNTING: nothing here touches sales, payments, journal_entries or journal_lines. The CRM never posts to the journal.
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner switches crm_on (and, for extra phones, crm_second_phone_on) ON. Reading the 360 view is always allowed to people
-- who may already see customers; masking applies only when crm_mask_phone is ON.

do $g$ begin
  if to_regprocedure('public._cust_pos43()') is null or to_regprocedure('public._cust_mgr43()') is null or to_regprocedure('public._cust_stats43(uuid,boolean)') is null
     or to_regprocedure('public.customer_directory(integer)') is null or to_regprocedure('public.rpt_mobile_ok()') is null then
    raise exception 'phase300 needs phase 43 (customers), phase 9 (rpt_mobile_ok) first';
  end if;
  if to_regclass('public.notify_outbox') is null or to_regclass('public.online_orders') is null or to_regclass('public.inbound_messages') is null then
    raise exception 'phase300 needs phase 61, 62 and 76 first';
  end if;
end $g$;

create or replace function public._crma_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('crm_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer profile extras are on', 'Customer profile extras are on', 'Customer profile extras are on',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.', 1300),
 ('crm_second_phone_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Allow extra phone numbers on a customer', 'Allow extra phone numbers on a customer', 'Allow extra phone numbers on a customer',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.', 1301),
 ('crm_mask_phone', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Hide customer phone numbers and addresses from people without the right', 'Hide customer phone numbers and addresses from people without the right', 'Hide customer phone numbers and addresses from people without the right',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.', 1302)
on conflict (key) do nothing;

-- ---------- grants (idempotent; no role holds them until the owner gives them) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_view', 'master', 72, 'See customer notes, messages and the full timeline', 'See customer notes, messages and the full timeline', 'See customer notes, messages and the full timeline', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_contact_view', 'master', 73, 'See full customer phone and address', 'See full customer phone and address', 'See full customer phone and address', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_contact_view');

-- ---------- columns on customers (all nullable: an existing customer needs no migration) ----------
alter table public.customers add column if not exists preferred_location_id integer references public.locations(id);
alter table public.customers add column if not exists language text;
alter table public.customers add column if not exists owner_user uuid references public.profiles(id);
alter table public.customers add column if not exists credit_days integer;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_language_crma' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_language_crma check (language is null or language in ('bn', 'en'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_credit_days_crma' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_credit_days_crma check (credit_days is null or (credit_days >= 0 and credit_days <= 365));
  end if;
end $c$;

-- ---------- small helpers (closed to browsers; SECURITY DEFINER callers use them) ----------
-- a phone as 01XXXXXXXXX, or NULL (never raises): used to match online orders and messages typed in any format
create or replace function public._crma_norm(p text) returns text language plpgsql immutable set search_path = public as $$
begin return public.norm_mobile(p); exception when others then return null; end $$;

-- 01712345678 -> 017******78 (first 3 and last 2 digits)
create or replace function public._crma_mask(p text) returns text language sql immutable set search_path = public as $$
  select case when p is null then null
              when length(p) < 6 then repeat('*', length(p))
              else left(p, 3) || repeat('*', length(p) - 5) || right(p, 2) end;
$$;

create or replace function public._crma_valid_md(m integer, d integer) returns boolean language sql immutable as $$
  select m between 1 and 12 and d between 1 and 31
     and d <= extract(day from (make_date(2024, m, 1) + interval '1 month' - interval '1 day'))::int;
$$;

-- the next date on or after p_from for a month and day (29 February falls on 28 February in a year that has no 29th)
create or replace function public._crma_next_date(m integer, d integer, p_from date) returns date language plpgsql immutable set search_path = public as $$
declare y int := extract(year from p_from)::int; dd int; c date;
begin
  if not public._crma_valid_md(m, d) then return null; end if;
  loop
    dd := least(d, extract(day from (make_date(y, m, 1) + interval '1 month' - interval '1 day'))::int);
    c := make_date(y, m, dd);
    if c >= p_from then return c; end if;
    y := y + 1;
  end loop;
end $$;

create or replace function public._crma_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_on'); $$;
create or replace function public._crma_mask_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_mask_phone'); $$;
-- may the caller see full phone numbers and addresses?  owner, grant crm_contact_view, or the existing report right
create or replace function public._crma_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_contact_view') or public.rpt_mobile_ok());
$$;
-- shows the full number? (guard OFF = today = everybody who can see customers)
create or replace function public._crma_show_phone() returns boolean language sql stable security definer set search_path = public as $$
  select not public.rule_on('crm_mask_phone') or public._crma_contact_ok();
$$;
create or replace function public._crma_ph(p text) returns text language sql stable security definer set search_path = public as $$
  select case when public._crma_show_phone() then p else public._crma_mask(p) end;
$$;
-- notes, messages and enquiries in the timeline
create or replace function public._crma_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_view'));
$$;
-- who may add to a profile: the people who may already register customers (POS enter or customer manager)
create or replace function public._crma_write_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._cust_mgr43() or public.can_do('POS', 'enter'));
$$;
-- ---------- tables ----------
create table if not exists public.customer_phones (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  phone text not null check (phone ~ '^01[3-9][0-9]{8}$'),
  label text not null default 'mobile' check (label in ('mobile', 'home', 'work', 'other')),
  wa_ok boolean not null default false,
  note text check (note is null or length(note) <= 100),
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz
);
create unique index if not exists customer_phones_one on public.customer_phones (customer_id, phone) where active;
create index if not exists customer_phones_phone on public.customer_phones (phone) where active;

create table if not exists public.customer_addresses (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  label text not null default 'home' check (label in ('home', 'office', 'gift', 'other')),
  address text not null check (length(btrim(address)) between 1 and 200),
  area text check (area is null or length(area) <= 80),
  landmark text check (landmark is null or length(landmark) <= 120),
  delivery_note text check (delivery_note is null or length(delivery_note) <= 200),
  is_default boolean not null default false,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz
);
create unique index if not exists customer_addresses_default on public.customer_addresses (customer_id) where is_default and active;
create index if not exists customer_addresses_cust on public.customer_addresses (customer_id) where active;

create table if not exists public.customer_dates (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  kind text not null check (kind in ('birthday', 'anniversary', 'other')),
  person_label text not null check (length(btrim(person_label)) between 1 and 40),     -- Spouse, Child 1, Mother ... (the customer's own dates live in customers)
  month integer not null, day integer not null,
  year integer check (year is null or year between 1900 and 2100),
  remind_days_before integer check (remind_days_before is null or remind_days_before between 0 and 60),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz,
  check (public._crma_valid_md(month, day))
);
create unique index if not exists customer_dates_one on public.customer_dates (customer_id, kind, lower(person_label), month, day) where active;
create index if not exists customer_dates_md on public.customer_dates (month, day) where active;

create table if not exists public.crm_tags (
  id bigserial primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,30}$'),
  label text not null check (length(btrim(label)) between 1 and 40),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.customer_tags (
  customer_id uuid not null references public.customers(id),
  tag_id bigint not null references public.crm_tags(id),
  active boolean not null default true,
  added_by uuid, added_at timestamptz not null default now(),
  removed_by uuid, removed_at timestamptz,
  primary key (customer_id, tag_id)
);
create index if not exists customer_tags_tag on public.customer_tags (tag_id) where active;

create table if not exists public.crm_notes (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  kind text not null default 'note' check (kind in ('note', 'call', 'visit', 'message', 'other')),
  body text not null check (length(btrim(body)) between 1 and 1000),
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  retired_at timestamptz, retired_by uuid, retire_reason text check (retire_reason is null or length(retire_reason) <= 300)
);
create index if not exists crm_notes_cust on public.crm_notes (customer_id, created_at desc, id desc);

-- the phones used to match a customer to online orders and inbox messages (those carry a phone number, not a customer id).
-- The main mobile always counts. The WhatsApp number and the extra numbers count only when NO other customer holds the same number (as main mobile or as an active extra number):
-- a number two customers share belongs to nobody for matching, so one customer's orders never show up on another customer's timeline.
create or replace function public._crma_phones(p_customer uuid) returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct z.x) filter (where z.x is not null), '{}'::text[])
  from (select c.mobile x from public.customers c where c.id = p_customer
        union all select public._crma_norm(c.whatsapp) from public.customers c where c.id = p_customer
        union all select p.phone from public.customer_phones p where p.customer_id = p_customer and p.active) z
  where z.x is not null and (z.x = (select mobile from public.customers where id = p_customer)
        or (not exists (select 1 from public.customers o where o.mobile = z.x and o.id <> p_customer)
            and not exists (select 1 from public.customer_phones o where o.phone = z.x and o.active and o.customer_id <> p_customer)));
$$;

-- a note is a record: only its retirement can be written, once
create or replace function public._crma_notes_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a note is retired, never deleted'; end if;
  if old.retired_at is not null then raise exception 'append_only: a retired note cannot change'; end if;
  if (new.customer_id, new.kind, new.body, new.client_id, new.created_by, new.created_staff, new.created_at)
     is distinct from (old.customer_id, old.kind, old.body, old.client_id, old.created_by, old.created_staff, old.created_at) then
    raise exception 'append_only: a note cannot be edited, retire it and write a new one';
  end if;
  return new;
end $$;
drop trigger if exists crm_notes_guard on public.crm_notes;
create trigger crm_notes_guard before update or delete on public.crm_notes for each row execute function public._crma_notes_guard();

-- audit + nothing is deleted + closed to browsers
do $t$ declare t text; begin
  foreach t in array array['customer_phones', 'customer_addresses', 'customer_dates', 'crm_tags', 'customer_tags', 'crm_notes'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t,
                   case when t = 'customer_tags' then 'customer_id,tag_id' else 'id' end);
    if t <> 'crm_notes' then
      execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
      execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    end if;
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;
-- the tag list (labels only) may be read by every active user; every other new table is read only through the masking functions
drop policy if exists crm_tags_read on public.crm_tags;
create policy crm_tags_read on public.crm_tags for select to authenticated using (public.is_active());
grant select on public.crm_tags to authenticated;
revoke usage, select on sequence public.customer_phones_id_seq, public.customer_addresses_id_seq, public.customer_dates_id_seq, public.crm_tags_id_seq, public.crm_notes_id_seq
  from public, anon, authenticated;

revoke all on function public._crma_present(), public._crma_norm(text), public._crma_mask(text), public._crma_valid_md(integer, integer), public._crma_next_date(integer, integer, date),
  public._crma_on(), public._crma_mask_on(), public._crma_contact_ok(), public._crma_show_phone(), public._crma_ph(text), public._crma_view_ok(), public._crma_write_ok(),
  public._crma_phones(uuid), public._crma_notes_guard() from public, anon, authenticated;

-- ===================== phase301.sql =====================
-- Phase 301 (bos301, package CRM-A, local label 101) - CUSTOMER PROFILE PLUS: the write functions.
-- Paste AFTER phase300. Paste-twice safe. No shared function is patched or re-created; customer_save, find_customer, record_sale2 are untouched.
--
-- Every write: (1) the caller must be allowed to register customers (POS enter or customer manager) - a hidden button is also a refused request,
-- (2) the owner's switch crm_on must be ON (otherwise error crm_off and nothing is written), (3) a repeated call changes nothing (client id or natural key),
-- (4) the table audit trigger writes one change-log line. Nothing is deleted: phones, delivery points, dates, tags and notes are retired.
-- Fields that carry money terms (customer type, credit days, account owner) and the tag list need the owner or the customer manager.
-- A second phone that another customer already holds is ACCEPTED and reported (shared_with); a sale is never blocked by it.
--
--   crma_customer_extras_save(customer, {language, preferred_location_id, type_code, credit_days, owner_user}, client)
--   crma_phone_add / crma_phone_retire / crma_phone_make_primary   (extra phones; changing the main number needs a reason and the customer manager)
--   crma_address_save / crma_address_retire                         (delivery points)
--   crma_date_save / crma_date_retire                               (family dates)
--   crma_tag_save (owner or manager) / crma_tag_set
--   crma_note_add / crma_note_retire                                (needs the grant crm_view or the owner)
--   crma_phone_reveal(customer, reason)                             (a masked caller gets the number once; one change-log line)

do $g$ begin
  if to_regprocedure('public._crma_present()') is null then raise exception 'phase301 needs phase300 first'; end if;
end $g$;

create or replace function public._crma_gate() returns void language plpgsql security definer set search_path = public as $$
begin
  if not public._crma_write_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
end $$;

create or replace function public._crma_int(p jsonb, k text, p_min numeric, p_max numeric) returns integer
language plpgsql immutable set search_path = public as $$
declare n numeric := public._n43(p, k, p_min, p_max);
begin
  if n is not null and n <> floor(n) then raise exception 'bad_number'; end if;
  return n::int;
end $$;

create or replace function public._crma_audit(p_action text, p_table text, p_record text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_record, p_detail);
end $$;

-- ---------- profile extras on the customer row ----------
create or replace function public.crma_customer_extras_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; k text; mgr boolean; v text;
  lang text; loc int; tc text; cd int; ou uuid;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('language', 'preferred_location_id', 'type_code', 'credit_days', 'owner_user') then raise exception 'unknown_key: %', k; end if;
  end loop;
  mgr := public._cust_mgr43();
  if (p ? 'type_code' or p ? 'credit_days' or p ? 'owner_user') and not mgr then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into c from public.customers where id = p_id for update;
  if not found then raise exception 'customer_not_found'; end if;
  lang := c.language; loc := c.preferred_location_id; tc := c.type_code; cd := c.credit_days; ou := c.owner_user;
  if p ? 'language' then
    v := nullif(btrim(coalesce(p ->> 'language', '')), '');
    if v is not null and v not in ('bn', 'en') then raise exception 'bad_value'; end if;
    lang := v;
  end if;
  if p ? 'preferred_location_id' then
    v := nullif(btrim(coalesce(p ->> 'preferred_location_id', '')), '');
    if v is null then loc := null;
    else
      begin loc := v::int; exception when others then raise exception 'bad_value'; end;
      if not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'location_not_found'; end if;
    end if;
  end if;
  if p ? 'type_code' then
    v := nullif(btrim(coalesce(p ->> 'type_code', '')), '');
    if v is not null and not exists (select 1 from public.option_lists where list_code = 'customer_types' and value_code = v and active) then raise exception 'type_not_found'; end if;
    tc := v;
  end if;
  if p ? 'credit_days' then
    cd := public._crma_int(p, 'credit_days', 0, 365);
  end if;
  if p ? 'owner_user' then
    v := nullif(btrim(coalesce(p ->> 'owner_user', '')), '');
    if v is null then ou := null;
    else
      begin ou := v::uuid; exception when others then raise exception 'bad_value'; end;
      if not exists (select 1 from public.profiles where id = ou and status = 'active') then raise exception 'user_not_found'; end if;
    end if;
  end if;
  update public.customers set language = lang, preferred_location_id = loc, type_code = tc, credit_days = cd, owner_user = ou where id = p_id;
  return jsonb_build_object('id', p_id, 'saved', true);
end $$;

-- ---------- extra phones ----------
create or replace function public._crma_phone_holders(p_phone text, p_except uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name) order by z.name), '[]'::jsonb)
  from (select c.id, c.name from public.customers c where c.mobile = p_phone and c.id is distinct from p_except
        union select c.id, c.name from public.customer_phones ph join public.customers c on c.id = ph.customer_id where ph.phone = p_phone and ph.active and c.id is distinct from p_except) z;
$$;

create or replace function public.crma_phone_add(p_customer uuid, p_phone text, p_label text default 'mobile', p_wa boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; ph text; lb text := coalesce(nullif(btrim(p_label), ''), 'mobile'); r public.customer_phones; sh jsonb; nt text := left(nullif(btrim(coalesce(p_note, '')), ''), 100);
begin
  perform public._crma_gate();
  if not public.rule_on('crm_second_phone_on') then raise exception 'second_phone_off'; end if;
  if lb not in ('mobile', 'home', 'work', 'other') then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.customer_phones where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'customer_id', r.customer_id); end if;
  end if;
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  if nullif(btrim(coalesce(p_phone, '')), '') is null then raise exception 'bad_mobile'; end if;
  ph := public.norm_mobile(p_phone);                                        -- raises bad_mobile
  if ph = c.mobile then return jsonb_build_object('dup', true, 'primary', true, 'customer_id', c.id); end if;
  select * into r from public.customer_phones where customer_id = c.id and phone = ph and active;
  if found then return jsonb_build_object('dup', true, 'id', r.id, 'customer_id', c.id); end if;
  if (select count(*) from public.customer_phones where customer_id = c.id and active) >= 10 then raise exception 'too_many_phones'; end if;
  insert into public.customer_phones (customer_id, phone, label, wa_ok, note, client_id, created_by)
    values (c.id, ph, lb, coalesce(p_wa, false), nt, p_client, auth.uid()) returning * into r;
  sh := public._crma_phone_holders(ph, c.id);
  return jsonb_build_object('dup', false, 'id', r.id, 'customer_id', c.id, 'shared_with', sh, 'warning', case when jsonb_array_length(sh) > 0 then 'phone_shared' end);
end $$;

create or replace function public.crma_phone_retire(p_phone_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_phones;
begin
  perform public._crma_gate();
  select * into r from public.customer_phones where id = p_phone_id for update;
  if not found then raise exception 'phone_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_phones set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- the main number (customers.mobile, the key POS and record_sale2 use) is swapped with an extra number: manager only, with a reason, one change-log line.
-- The old main number stays on the profile as an extra number. A number that is the main number of ANOTHER customer is refused (the key is unique).
create or replace function public.crma_phone_make_primary(p_phone_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_phones; c public.customers; why text := left(btrim(coalesce(p_reason, '')), 300); old text;
begin
  perform public._crma_gate();
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.customer_phones where id = p_phone_id for update;
  if not found or not r.active then raise exception 'phone_not_found'; end if;
  select * into c from public.customers where id = r.customer_id for update;
  if exists (select 1 from public.customers x where x.mobile = r.phone and x.id <> c.id) then raise exception 'mobile_taken'; end if;
  old := c.mobile;
  update public.customer_phones set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  update public.customers set mobile = r.phone where id = c.id;
  insert into public.customer_phones (customer_id, phone, label, wa_ok, note, created_by) values (c.id, old, 'other', false, 'was the main number', auth.uid())
    on conflict (customer_id, phone) where active do nothing;
  perform public._crma_audit('crm_primary_phone_changed', 'customers', c.id::text, jsonb_build_object('from', old, 'to', r.phone, 'reason', why));
  return jsonb_build_object('id', c.id, 'mobile', r.phone, 'old_mobile', old);
end $$;

-- ---------- delivery points ----------
create or replace function public.crma_address_save(p_customer uuid, p jsonb, p_id bigint default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; a public.customer_addresses; r public.customer_addresses; lb text; ad text; ar text; lm text; dn text; df boolean;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('label', 'address', 'area', 'landmark', 'delivery_note', 'is_default') then raise exception 'unknown_key: %', k; end if;
  end loop;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.customer_addresses where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into a from public.customer_addresses where false;
  if p_id is not null then
    select * into a from public.customer_addresses where id = p_id and customer_id = p_customer and active for update;
    if not found then raise exception 'address_not_found'; end if;
  end if;
  lb := case when p ? 'label' then coalesce(nullif(btrim(p ->> 'label'), ''), 'home') else coalesce(a.label, 'home') end;
  if lb not in ('home', 'office', 'gift', 'other') then raise exception 'bad_value'; end if;
  ad := case when p ? 'address' then left(btrim(coalesce(p ->> 'address', '')), 200) else a.address end;
  if ad is null or ad = '' then raise exception 'address_required'; end if;
  ar := case when p ? 'area' then left(nullif(btrim(coalesce(p ->> 'area', '')), ''), 80) else a.area end;
  lm := case when p ? 'landmark' then left(nullif(btrim(coalesce(p ->> 'landmark', '')), ''), 120) else a.landmark end;
  dn := case when p ? 'delivery_note' then left(nullif(btrim(coalesce(p ->> 'delivery_note', '')), ''), 200) else a.delivery_note end;
  df := case when p ? 'is_default' then coalesce((p ->> 'is_default')::boolean, false) else coalesce(a.is_default, false) end;
  if p_id is null then
    select * into r from public.customer_addresses where customer_id = p_customer and active and lower(address) = lower(ad) and coalesce(lower(area), '') = coalesce(lower(ar), '');
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
    if (select count(*) from public.customer_addresses where customer_id = p_customer and active) >= 20 then raise exception 'too_many_addresses'; end if;
    if df then update public.customer_addresses set is_default = false where customer_id = p_customer and is_default and active; end if;
    insert into public.customer_addresses (customer_id, label, address, area, landmark, delivery_note, is_default, client_id, created_by)
      values (p_customer, lb, ad, ar, lm, dn, df, p_client, auth.uid()) returning * into r;
    return jsonb_build_object('dup', false, 'id', r.id);
  end if;
  if df then update public.customer_addresses set is_default = false where customer_id = p_customer and is_default and active and id <> p_id; end if;
  update public.customer_addresses set label = lb, address = ad, area = ar, landmark = lm, delivery_note = dn, is_default = df where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.crma_address_retire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_addresses;
begin
  perform public._crma_gate();
  select * into r from public.customer_addresses where id = p_id for update;
  if not found then raise exception 'address_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_addresses set active = false, is_default = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- family dates ----------
create or replace function public.crma_date_save(p_customer uuid, p jsonb, p_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text; d public.customer_dates; r public.customer_dates; kd text; pl text; m int; dd int; y int; rb int;
begin
  perform public._crma_gate();
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('kind', 'person_label', 'month', 'day', 'year', 'remind_days_before') then raise exception 'unknown_key: %', k; end if;
  end loop;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into d from public.customer_dates where false;
  if p_id is not null then
    select * into d from public.customer_dates where id = p_id and customer_id = p_customer and active for update;
    if not found then raise exception 'date_not_found'; end if;
  end if;
  kd := case when p ? 'kind' then nullif(btrim(p ->> 'kind'), '') else d.kind end;
  if kd is null or kd not in ('birthday', 'anniversary', 'other') then raise exception 'bad_value'; end if;
  pl := case when p ? 'person_label' then left(btrim(coalesce(p ->> 'person_label', '')), 40) else d.person_label end;
  if pl is null or pl = '' then raise exception 'person_required'; end if;
  m := case when p ? 'month' then public._crma_int(p, 'month', 1, 12) else d.month end;
  dd := case when p ? 'day' then public._crma_int(p, 'day', 1, 31) else d.day end;
  if m is null or dd is null or not public._crma_valid_md(m, dd) then raise exception 'bad_date'; end if;
  if p ? 'year' then y := public._crma_int(p, 'year', 1900, 2100); else y := d.year; end if;
  if y is not null and make_date(y, m, case when m = 2 and dd = 29 and not (y % 4 = 0 and (y % 100 <> 0 or y % 400 = 0)) then 28 else dd end) > public._today43() then raise exception 'bad_date'; end if;
  if p ? 'remind_days_before' then rb := public._crma_int(p, 'remind_days_before', 0, 60); else rb := d.remind_days_before; end if;
  select * into r from public.customer_dates where customer_id = p_customer and active and kind = kd and lower(person_label) = lower(pl) and month = m and day = dd and id is distinct from p_id;
  if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if p_id is null then
    if (select count(*) from public.customer_dates where customer_id = p_customer and active) >= 30 then raise exception 'too_many_dates'; end if;
    insert into public.customer_dates (customer_id, kind, person_label, month, day, year, remind_days_before, created_by) values (p_customer, kd, pl, m, dd, y, rb, auth.uid()) returning * into r;
    return jsonb_build_object('dup', false, 'id', r.id);
  end if;
  update public.customer_dates set kind = kd, person_label = pl, month = m, day = dd, year = y, remind_days_before = rb where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id);
end $$;

create or replace function public.crma_date_retire(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.customer_dates;
begin
  perform public._crma_gate();
  select * into r from public.customer_dates where id = p_id for update;
  if not found then raise exception 'date_not_found'; end if;
  if not r.active then return jsonb_build_object('dup', true, 'id', r.id); end if;
  update public.customer_dates set active = false, retired_by = auth.uid(), retired_at = now() where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- tags ----------
create or replace function public.crma_tag_save(p_id bigint, p_code text, p_label text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tags; lb text := left(btrim(coalesce(p_label, '')), 40);
begin
  if not (public.is_active() and (public.is_owner() or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if lb = '' then raise exception 'name_required'; end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.crm_tags where code = p_code) then raise exception 'code_exists'; end if;
    insert into public.crm_tags (code, label, active, created_by) values (p_code, lb, coalesce(p_active, true), auth.uid()) returning * into t;
  else
    select * into t from public.crm_tags where id = p_id for update;
    if not found then raise exception 'tag_not_found'; end if;
    update public.crm_tags set label = lb, active = coalesce(p_active, active) where id = p_id returning * into t;
  end if;
  return jsonb_build_object('id', t.id, 'code', t.code, 'label', t.label, 'active', t.active);
end $$;

create or replace function public.crma_tag_set(p_customer uuid, p_tag bigint, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tags; r public.customer_tags;
begin
  perform public._crma_gate();
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into t from public.crm_tags where id = p_tag;
  if not found then raise exception 'tag_not_found'; end if;
  select * into r from public.customer_tags where customer_id = p_customer and tag_id = p_tag for update;
  if coalesce(p_on, true) then
    if not t.active then raise exception 'tag_not_found'; end if;
    if found and r.active then return jsonb_build_object('dup', true); end if;
    if found then update public.customer_tags set active = true, added_by = auth.uid(), added_at = now(), removed_by = null, removed_at = null where customer_id = p_customer and tag_id = p_tag;
    else insert into public.customer_tags (customer_id, tag_id, added_by) values (p_customer, p_tag, auth.uid()); end if;
    return jsonb_build_object('dup', false, 'on', true);
  end if;
  if not found or not r.active then return jsonb_build_object('dup', true); end if;
  update public.customer_tags set active = false, removed_by = auth.uid(), removed_at = now() where customer_id = p_customer and tag_id = p_tag;
  return jsonb_build_object('dup', false, 'on', false);
end $$;

-- ---------- notes ----------
create or replace function public.crma_note_add(p_customer uuid, p_body text, p_kind text default 'note', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.crm_notes; b text := left(btrim(coalesce(p_body, '')), 1000); kd text := coalesce(nullif(btrim(p_kind), ''), 'note');
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if b = '' then raise exception 'note_required'; end if;
  if kd not in ('note', 'call', 'visit', 'message', 'other') then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into r from public.crm_notes where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id); end if;
  end if;
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  insert into public.crm_notes (customer_id, kind, body, client_id, created_by, created_staff)
    values (p_customer, kd, b, p_client, auth.uid(), (select staff_id from public.profiles where id = auth.uid())) returning * into r;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

create or replace function public.crma_note_retire(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.crm_notes; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  if not public._crma_on() then raise exception 'crm_off'; end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.crm_notes where id = p_id for update;
  if not found then raise exception 'note_not_found'; end if;
  if r.retired_at is not null then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if not (public.is_owner() or r.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  update public.crm_notes set retired_at = now(), retired_by = auth.uid(), retire_reason = why where id = r.id;
  return jsonb_build_object('dup', false, 'id', r.id);
end $$;

-- ---------- a masked caller gets the number once, with a reason, and it is written to the change log ----------
create or replace function public.crma_phone_reveal(p_customer uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if public._crma_show_phone() then return jsonb_build_object('mobile', c.mobile, 'whatsapp', c.whatsapp, 'logged', false); end if;
  if length(why) < 3 then raise exception 'reason_required'; end if;
  perform public._crma_audit('crm_phone_reveal', 'customers', c.id::text, jsonb_build_object('reason', why));
  return jsonb_build_object('mobile', c.mobile, 'whatsapp', c.whatsapp, 'logged', true);
end $$;

-- ---------- find a customer by ANY of their numbers (for a hook in the POS lookup; find_customer itself is not changed) ----------
-- The cashier typed one of this customer's own numbers, and the sale needs the main number to attach to the right customer, so the main number is returned in full
-- (the same exposure find_customer already has for a typed number). Name and balance are what find_customer returns today.
create or replace function public.crma_find_by_any_phone(p_phone text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text; c public.customers; n int; via text := 'mobile';
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  m := public.norm_mobile(p_phone);
  select * into c from public.customers where mobile = m;
  if not found then
    select count(distinct ph.customer_id) into n from public.customer_phones ph where ph.phone = m and ph.active;
    if n = 0 then return jsonb_build_object('mobile', m, 'found', false); end if;
    select cu.* into c from public.customer_phones ph join public.customers cu on cu.id = ph.customer_id where ph.phone = m and ph.active order by cu.active desc, cu.created_at limit 1;
    via := 'extra_phone';
  else n := 1; end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', c.mobile, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit,
    'balance', public.customer_balance(c.id), 'via', via, 'matches', n, 'ambiguous', n > 1);
end $$;

-- ---------- possible duplicates caused by extra phones (manager / owner) ----------
create or replace function public.crma_phone_conflicts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('phone', public._crma_ph(z.phone), 'customers', z.cs) order by z.phone)
    from (select a.phone, jsonb_agg(distinct jsonb_build_object('id', a.cid, 'name', a.name)) cs
          from (select c.mobile phone, c.id cid, c.name from public.customers c
                union all select ph.phone, c.id, c.name from public.customer_phones ph join public.customers c on c.id = ph.customer_id where ph.active) a
          group by a.phone having count(distinct a.cid) > 1) z), '[]'::jsonb);
end $$;

-- ---------- permissions: browser-callable vs internal ----------
revoke all on function public._crma_gate(), public._crma_int(jsonb, text, numeric, numeric), public._crma_audit(text, text, text, jsonb), public._crma_phone_holders(text, uuid) from public, anon, authenticated;
revoke all on function public.crma_customer_extras_save(uuid, jsonb, uuid), public.crma_phone_add(uuid, text, text, boolean, text, uuid), public.crma_phone_retire(bigint),
  public.crma_phone_make_primary(bigint, text), public.crma_address_save(uuid, jsonb, bigint, uuid), public.crma_address_retire(bigint), public.crma_date_save(uuid, jsonb, bigint),
  public.crma_date_retire(bigint), public.crma_tag_save(bigint, text, text, boolean), public.crma_tag_set(uuid, bigint, boolean), public.crma_note_add(uuid, text, text, uuid),
  public.crma_note_retire(bigint, text), public.crma_phone_reveal(uuid, text), public.crma_find_by_any_phone(text), public.crma_phone_conflicts() from public, anon;
grant execute on function public.crma_customer_extras_save(uuid, jsonb, uuid), public.crma_phone_add(uuid, text, text, boolean, text, uuid), public.crma_phone_retire(bigint),
  public.crma_phone_make_primary(bigint, text), public.crma_address_save(uuid, jsonb, bigint, uuid), public.crma_address_retire(bigint), public.crma_date_save(uuid, jsonb, bigint),
  public.crma_date_retire(bigint), public.crma_tag_save(bigint, text, text, boolean), public.crma_tag_set(uuid, bigint, boolean), public.crma_note_add(uuid, text, text, uuid),
  public.crma_note_retire(bigint, text), public.crma_phone_reveal(uuid, text), public.crma_find_by_any_phone(text), public.crma_phone_conflicts() to authenticated;

-- ===================== phase302.sql =====================
-- Phase 302 (bos302, package CRM-A, local label 102) - CUSTOMER 360: read functions (profile, timeline, favourites, upcoming dates, masked directory).
-- Paste AFTER phase301. Paste-twice safe. READ ONLY: nothing here writes a table. No shared function is patched or re-created.
--
--   crma_state()                         what the caller may see / do and where the three settings stand (one call for the screen)
--   crma_customer_360(customer)          the whole profile in one call: main + extra phones, addresses, dates with the next occurrence, tags, type, credit terms,
--                                        tier, totals, points, favourites, counts. Same people as customer_profile may call it. Phone numbers and addresses are
--                                        masked when the owner switched crm_mask_phone ON and the caller has no right. Notes and the old single note need crm_view.
--   crma_timeline(customer, before, before_key, limit, kinds)   one timeline of every touchpoint, newest first, paged by (time, key):
--                                        sale, return, collection (a due paid), order (online order matched by phone), points, gift, tier, and for crm_view holders
--                                        message (the SMS / WhatsApp queue), note, enquiry (inbox). Sales, returns, collections and orders are limited to the
--                                        places the caller may see (can_loc), like customer_profile.
--   crma_favourites(customer, limit)     what the customer buys most (counted on done sales, not net of returns)
--   crma_dates_upcoming(days, limit)     birthdays, anniversaries and family dates in the next N days (crm_view or owner)
--   crma_customer_directory(limit)       the masked variant of customer_directory: the SAME columns. With crm_mask_phone OFF (default) the rows are identical to
--                                        customer_directory; ON and no right: mobile and WhatsApp masked, address hidden, note only with crm_view.
-- Accounting: nothing here changes a figure; balances come from the existing _cust_bal.

do $g$ begin
  if to_regprocedure('public._crma_present()') is null or to_regclass('public.customer_phones') is null then raise exception 'phase302 needs phase300 and 301 first'; end if;
end $g$;

create or replace function public.crma_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('crm_on', public.rule_on('crm_on'), 'second_phone_on', public.rule_on('crm_second_phone_on'), 'mask_phone', public.rule_on('crm_mask_phone'),
    'is_owner', public.is_owner(), 'can_see_customers', public._cust_pos43(), 'can_write', public._crma_write_ok(), 'can_manage', public._cust_mgr43(),
    'can_view', public._crma_view_ok(), 'contact_ok', public._crma_contact_ok(), 'shows_phone', public._crma_show_phone());
end $$;

create or replace function public.crma_favourites(p_customer uuid, p_limit int default 10) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('item_id', f.item_id, 'name', f.name, 'name_en', (select i.name_en from public.items i where i.id::text = f.item_id), 'unit', f.unit,
                                        'orders', f.orders, 'qty', f.qty, 'amount', f.amount, 'last_date', f.last_date) order by f.orders desc, f.qty desc nulls last, f.last_date desc, f.name)
    from (select coalesce(l.l ->> 'item_id', 'n:' || lower(coalesce(l.l ->> 'name', ''))) k, max(l.l ->> 'item_id') item_id, max(l.l ->> 'name') name, max(l.l ->> 'unit') unit,
                 count(distinct l.sid)::int orders, sum(l.qty) qty, sum(l.amt) amount, max(l.sd) last_date
          from (select s.id sid, s.sale_date sd, x.l,
                       case when x.l ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (x.l ->> 'qty')::numeric end qty,
                       case when x.l ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (x.l ->> 'amount')::numeric end amt
                from public.sales s cross join lateral jsonb_array_elements(s.lines) x(l)
                where s.customer_id = p_customer and s.status = 'done' and jsonb_typeof(s.lines) = 'array' and public.can_loc(s.location_id)) l
          group by 1 order by count(distinct l.sid) desc, sum(l.qty) desc nulls last, max(l.sd) desc, max(l.l ->> 'name') limit least(greatest(coalesce(p_limit, 10), 1), 50)) f), '[]'::jsonb);
end $$;

create or replace function public.crma_customer_360(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; st record; t public.customer_tiers; show boolean := public._crma_show_phone(); vw boolean := public._crma_view_ok();
  today date := public._today43(); ph jsonb; ad jsonb; dt jsonb; tg jsonb; xtra_default boolean; ty text; loc jsonb; own jsonb; phs text[];
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  select * into t from public.customer_tiers where id = c.tier_id;
  select label_en into ty from public.option_lists where list_code = 'customer_types' and value_code = c.type_code;
  select jsonb_build_object('id', l.id, 'name', coalesce(l.name_en, l.name_bn)) into loc from public.locations l where l.id = c.preferred_location_id;
  select jsonb_build_object('id', p.id, 'name', coalesce(nullif(p.full_name, ''), p.staff_id)) into own from public.profiles p where p.id = c.owner_user;
  phs := public._crma_phones(p_customer);

  ph := jsonb_build_array(jsonb_build_object('id', null, 'kind', 'main', 'phone', public._crma_ph(c.mobile), 'label', 'mobile', 'wa_ok', c.whatsapp is not null and c.whatsapp = c.mobile, 'masked', not show))
     || case when c.whatsapp is not null and c.whatsapp <> c.mobile then jsonb_build_array(jsonb_build_object('id', null, 'kind', 'whatsapp', 'phone', public._crma_ph(c.whatsapp), 'label', 'mobile', 'wa_ok', true, 'masked', not show)) else '[]'::jsonb end
     || coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', 'extra', 'phone', public._crma_ph(x.phone), 'label', x.label, 'wa_ok', x.wa_ok, 'note', x.note, 'masked', not show,
                                                      'shared', exists (select 1 from public.customers o where o.mobile = x.phone and o.id <> c.id)
                                                                or exists (select 1 from public.customer_phones o where o.phone = x.phone and o.active and o.customer_id <> c.id)) order by x.id)
                  from public.customer_phones x where x.customer_id = c.id and x.active), '[]'::jsonb);

  xtra_default := exists (select 1 from public.customer_addresses where customer_id = c.id and active and is_default);
  ad := case when c.address is not null then jsonb_build_array(jsonb_build_object('id', null, 'kind', 'main', 'label', 'home', 'address', case when show then c.address end, 'is_default', not xtra_default, 'hidden', not show)) else '[]'::jsonb end
     || coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', 'extra', 'label', a.label, 'address', case when show then a.address end, 'area', a.area,
                                                      'landmark', case when show then a.landmark end, 'delivery_note', case when show then a.delivery_note end, 'is_default', a.is_default, 'hidden', not show) order by a.id)
                  from public.customer_addresses a where a.customer_id = c.id and a.active), '[]'::jsonb);

  dt := coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'person', d.person, 'month', d.m, 'day', d.d, 'year', d.y, 'remind_days_before', d.rb, 'own', d.own,
                                                       'next_date', d.nx, 'days_until', d.nx - today, 'turning', case when d.y is not null then extract(year from d.nx)::int - d.y end) order by d.nx, d.person)
                  from (select z.*, public._crma_next_date(z.m, z.d, today) nx
                        from (select null::bigint id, 'birthday' kind, 'Customer'::text person, extract(month from c.birthday)::int m, extract(day from c.birthday)::int d, extract(year from c.birthday)::int y, null::int rb, true own where c.birthday is not null
                              union all select null, 'anniversary', 'Customer', extract(month from c.anniversary)::int, extract(day from c.anniversary)::int, extract(year from c.anniversary)::int, null, true where c.anniversary is not null
                              union all select x.id, x.kind, x.person_label, x.month, x.day, x.year, x.remind_days_before, false from public.customer_dates x where x.customer_id = c.id and x.active) z) d), '[]'::jsonb);

  tg := coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'code', g.code, 'label', g.label) order by g.label) from public.customer_tags ct join public.crm_tags g on g.id = ct.tag_id where ct.customer_id = c.id and ct.active), '[]'::jsonb);

  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'name', c.name, 'active', c.active, 'type', c.type, 'type_code', c.type_code, 'type_label', ty,
        'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'name', t.name_en, 'color', t.color, 'badge', t.badge) end, 'tier_locked', c.tier_locked,
        'source', c.source, 'language', c.language, 'preferred_location', loc, 'owner', own, 'credit_limit', c.credit_limit, 'credit_days', c.credit_days, 'customer_since', c.customer_since,
        'created_at', c.created_at, 'note', case when vw then c.note end),
    'stats', jsonb_build_object('spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'first_sale', st.first_sale, 'last_sale', st.last_sale,
        'avg_bill', case when st.orders > 0 then round(st.spend / st.orders, 2) end, 'balance', public._cust_bal(p_customer),
        'points', coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0)),
    'phones', ph, 'addresses', ad, 'dates', dt, 'tags', tg,
    'next_date', (select x from jsonb_array_elements(dt) x order by (x ->> 'days_until')::int limit 1),
    'favourites', public.crma_favourites(p_customer, 5),
    'counts', jsonb_build_object(
        'notes', case when vw then (select count(*) from public.crm_notes where customer_id = c.id and retired_at is null) end,
        'open_orders', (select count(*) from public.online_orders o where public.can_do('POS', 'view') and public.can_loc(o.location_id) and o.status in ('new', 'confirmed', 'packed') and public._crma_norm(o.customer_mobile) = any(phs)),
        'messages_waiting', case when vw then (select count(*) from public.notify_outbox m where m.customer_id = c.id and m.status in ('queued', 'sending')) end),
    'can', jsonb_build_object('crm_on', public.rule_on('crm_on'), 'edit', public._crma_write_ok() and public.rule_on('crm_on'), 'manage', public._cust_mgr43(),
        'view', vw, 'contact', public._crma_contact_ok(), 'shows_phone', show, 'second_phone', public.rule_on('crm_second_phone_on')));
end $$;

create or replace function public.crma_timeline(p_customer uuid, p_before timestamptz default null, p_before_key text default null, p_limit int default 30, p_kinds text[] default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 30), 1), 100); bk text := coalesce(p_before_key, '~~~~'); vw boolean := public._crma_view_ok(); phs text[]; arr jsonb; n int; posv boolean := public.can_do('POS', 'view');
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  phs := public._crma_phones(p_customer);
  select coalesce(jsonb_agg(jsonb_build_object('at', x.at, 'key', x.ukey, 'kind', x.kind, 'title', x.title, 'amount', x.amount, 'status', x.status, 'location_id', x.loc, 'ref', x.ref, 'detail', x.detail)
                           order by x.at desc, x.ukey desc), '[]'::jsonb)
    into arr from (
      select * from (
        (select s.sold_at at, 's:' || s.id::text ukey, 'sale' kind, 'Sale #' || s.receipt title, s.total amount, s.status, s.location_id loc, s.receipt::text ref,
                jsonb_build_object('paid', s.paid, 'due', s.due_amount, 'discount', s.discount, 'pay_mode', s.pay_mode, 'sale_id', s.id) detail
         from public.sales s where s.customer_id = p_customer and public.can_loc(s.location_id) and (p_kinds is null or 'sale' = any(p_kinds)) and (p_before is null or (s.sold_at, 's:' || s.id::text) < (p_before, bk))
         order by s.sold_at desc, 's:' || s.id::text desc limit lim + 1)
        union all
        (select r.created_at, 'r:' || r.id::text, 'return', 'Return', r.amount, r.status, r.location_id, null,
                jsonb_build_object('credit', r.credit_amount, 'refund', r.refund_amount, 'reason', r.reason_code, 'sale_id', r.sale_id)
         from public.sale_returns r where r.customer_id = p_customer and public.can_loc(r.location_id) and (p_kinds is null or 'return' = any(p_kinds)) and (p_before is null or (r.created_at, 'r:' || r.id::text) < (p_before, bk))
         order by r.created_at desc, 'r:' || r.id::text desc limit lim + 1)
        union all
        (select p.paid_at, 'c:' || lpad(p.id::text, 12, '0'), 'collection', 'Due payment received', p.amount, case when p.voided then 'void' else 'done' end, p.location_id, null,
                jsonb_build_object('mode', p.mode)
         from public.sale_payments p where p.customer_id = p_customer and p.kind = 'collection' and public.can_loc(p.location_id) and (p_kinds is null or 'collection' = any(p_kinds)) and (p_before is null or (p.paid_at, 'c:' || lpad(p.id::text, 12, '0')) < (p_before, bk))
         order by p.paid_at desc, 'c:' || lpad(p.id::text, 12, '0') desc limit lim + 1)
        union all
        (select o.created_at, 'o:' || o.id::text, 'order', 'Order #' || o.order_no, o.subtotal - o.discount + o.delivery_charge, o.status, o.location_id, o.order_no::text,
                jsonb_build_object('channel', o.channel, 'delivery_date', o.delivery_date, 'advance', o.advance, 'delivery_mode', o.delivery_mode)
         from public.online_orders o where posv and public.can_loc(o.location_id) and public._crma_norm(o.customer_mobile) = any(phs) and (p_kinds is null or 'order' = any(p_kinds)) and (p_before is null or (o.created_at, 'o:' || o.id::text) < (p_before, bk))
         order by o.created_at desc, 'o:' || o.id::text desc limit lim + 1)
        union all
        (select l.at, 'p:' || lpad(l.id::text, 12, '0'), 'points', case l.reason when 'sale' then 'Points earned' when 'redeem' then 'Points used' when 'expire' then 'Points expired' else 'Points adjusted' end, null::numeric, 'done', null::int, null,
                jsonb_build_object('points', l.delta, 'note', l.note)
         from public.customer_points_ledger l where l.customer_id = p_customer and (p_kinds is null or 'points' = any(p_kinds)) and (p_before is null or (l.at, 'p:' || lpad(l.id::text, 12, '0')) < (p_before, bk))
         order by l.at desc, 'p:' || lpad(l.id::text, 12, '0') desc limit lim + 1)
        union all
        (select g.issued_at, 'g:' || g.id::text, 'gift', coalesce(g.gift_text_en, g.gift_text_bn), g.value_taka, case when g.claimed_at is not null then 'given' else 'waiting' end, null::int, null,
                jsonb_build_object('valid_until', g.valid_until, 'claimed_at', g.claimed_at)
         from public.customer_gifts g where g.customer_id = p_customer and (p_kinds is null or 'gift' = any(p_kinds)) and (p_before is null or (g.issued_at, 'g:' || g.id::text) < (p_before, bk))
         order by g.issued_at desc, 'g:' || g.id::text desc limit lim + 1)
        union all
        (select h.at, 't:' || lpad(h.id::text, 12, '0'), 'tier', 'Tier: ' || coalesce((select name_en from public.customer_tiers where id = h.from_tier), '-') || ' to ' || coalesce((select name_en from public.customer_tiers where id = h.to_tier), '-'), null::numeric, 'done', null::int, null,
                jsonb_build_object('reason', h.reason, 'note', h.note)
         from public.customer_tier_history h where h.customer_id = p_customer and (p_kinds is null or 'tier' = any(p_kinds)) and (p_before is null or (h.at, 't:' || lpad(h.id::text, 12, '0')) < (p_before, bk))
         order by h.at desc, 't:' || lpad(h.id::text, 12, '0') desc limit lim + 1)
        union all
        (select m.created_at, 'm:' || lpad(m.id::text, 12, '0'), 'message', initcap(m.channel) || ': ' || m.template_code, null::numeric, m.status, null::int, null,
                jsonb_build_object('to', public._crma_ph(case when m.to_phone ~ '^\+8801' then '0' || substr(m.to_phone, 5) else m.to_phone end), 'text', left(m.body, 160), 'sent_at', m.sent_at)
         from public.notify_outbox m where vw and m.customer_id = p_customer and (p_kinds is null or 'message' = any(p_kinds)) and (p_before is null or (m.created_at, 'm:' || lpad(m.id::text, 12, '0')) < (p_before, bk))
         order by m.created_at desc, 'm:' || lpad(m.id::text, 12, '0') desc limit lim + 1)
        union all
        (select nn.created_at, 'n:' || lpad(nn.id::text, 12, '0'), 'note', initcap(nn.kind), null::numeric, 'done', null::int, null,
                jsonb_build_object('text', nn.body, 'by', nn.created_staff, 'note_id', nn.id)
         from public.crm_notes nn where vw and nn.customer_id = p_customer and nn.retired_at is null and (p_kinds is null or 'note' = any(p_kinds)) and (p_before is null or (nn.created_at, 'n:' || lpad(nn.id::text, 12, '0')) < (p_before, bk))
         order by nn.created_at desc, 'n:' || lpad(nn.id::text, 12, '0') desc limit lim + 1)
        union all
        (select im.received_at, 'e:' || lpad(im.id::text, 12, '0'), 'enquiry', 'Enquiry', null::numeric, im.status, im.location_id, null,
                jsonb_build_object('text', left(im.msg_text, 160), 'channel_id', im.channel_id)
         from public.inbound_messages im where vw and posv and public.can_loc(im.location_id) and public._crma_norm(im.customer_handle) = any(phs) and (p_kinds is null or 'enquiry' = any(p_kinds)) and (p_before is null or (im.received_at, 'e:' || lpad(im.id::text, 12, '0')) < (p_before, bk))
         order by im.received_at desc, 'e:' || lpad(im.id::text, 12, '0') desc limit lim + 1)
      ) u order by u.at desc, u.ukey desc limit lim + 1) x;
  n := jsonb_array_length(arr);
  if n > lim then arr := arr - lim; end if;
  return jsonb_build_object('items', arr, 'has_more', n > lim,
    'next', case when n > lim then jsonb_build_object('before', arr -> (lim - 1) ->> 'at', 'key', arr -> (lim - 1) ->> 'key') end);
end $$;

create or replace function public.crma_dates_upcoming(p_days int default 30, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._today43(); dys int := least(greatest(coalesce(p_days, 30), 0), 366);
begin
  if not public._crma_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('customer_id', r.cid, 'name', r.name, 'phone', public._crma_ph(r.mobile), 'kind', r.kind, 'person', r.person, 'date', r.nx, 'days_until', r.nx - today,
                                                       'turning', case when r.y is not null then extract(year from r.nx)::int - r.y end) order by r.nx, r.name)
    from (select * from (
            select c.id cid, c.name, c.mobile, 'birthday' kind, 'Customer'::text person, extract(year from c.birthday)::int y, public._crma_next_date(extract(month from c.birthday)::int, extract(day from c.birthday)::int, today) nx
              from public.customers c where c.active and c.birthday is not null
            union all select c.id, c.name, c.mobile, 'anniversary', 'Customer', extract(year from c.anniversary)::int, public._crma_next_date(extract(month from c.anniversary)::int, extract(day from c.anniversary)::int, today)
              from public.customers c where c.active and c.anniversary is not null
            union all select c.id, c.name, c.mobile, d.kind, d.person_label, d.year, public._crma_next_date(d.month, d.day, today)
              from public.customer_dates d join public.customers c on c.id = d.customer_id where d.active and c.active) z
          where z.nx - today <= dys order by z.nx, z.name limit least(greatest(coalesce(p_limit, 200), 1), 1000)) r), '[]'::jsonb);
end $$;

create or replace function public.crma_customer_directory(p_limit int default 5000)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if public._crma_show_phone() then
    return query select * from public.customer_directory(p_limit);                               -- guard OFF (today) or the caller has the right: identical rows
    return;
  end if;
  return query
    select d.id, public._crma_mask(d.mobile), d.name, d.type, d.active, d.tier_id, d.tier_locked, d.birthday, d.anniversary, null::text, public._crma_mask(d.whatsapp),
           case when public._crma_view_ok() then d.note end, d.credit_limit, d.customer_since, d.balance, d.spend, d.orders, d.last_sale, d.points
    from public.customer_directory(p_limit) d;
end $$;

revoke all on function public.crma_state(), public.crma_favourites(uuid, int), public.crma_customer_360(uuid), public.crma_timeline(uuid, timestamptz, text, int, text[]),
  public.crma_dates_upcoming(int, int), public.crma_customer_directory(int) from public, anon;
grant execute on function public.crma_state(), public.crma_favourites(uuid, int), public.crma_customer_360(uuid), public.crma_timeline(uuid, timestamptz, text, int, text[]),
  public.crma_dates_upcoming(int, int), public.crma_customer_directory(int) to authenticated;

-- ===================== phase303.sql =====================
-- Phase 303 (CRM package B, local label 103) - CONSENT: record and withdraw a customer's yes / no per channel, with evidence and a log; do-not-contact.
-- Paste AFTER phase62 and phase43 (it reuses notify_optin and notify_optin_log). Paste-twice safe. No earlier phase file is edited and NO shared function is re-created.
-- The integrator wires the hooks written in docs/integration/CRM-B.md (two small lines in notify_enqueue / notify_optin_set, a few lines in customers.js and pos.js).
--
-- WHY (CRM audit rows 13, 14): notify_optin_set exists but no screen or script calls it, so a customer's yes or no could never be recorded, and a "no" could not be
-- written down with where it came from. Existing customers have NO row = "Not asked" = nothing may be sent (unchanged). Nothing here sends anything.
-- WHAT THIS FILE ADDS (functions start _crmb_, tables start crm_)
--   1. crm_consent_events      append-only evidence: who recorded a yes / no / do-not-contact, for which customer and channel, how it was given (counter tick, phone,
--                              paper form, message reply, owner entry, import), where (outlet), the wording version, a note. notify_optin / notify_optin_log stay the single
--                              truth that notify_enqueue reads; every change here also writes them (same rows the old owner-only function writes).
--   2. crm_contact_prefs       one row per customer that ever had a do-not-contact flag. Do-not-contact beats any opt-in.
--   3. _crmb_consent_set / _crmb_consent_set_mobile   record a yes or a no (idempotent by client id). A "no" cancels queued messages at once. A "yes" after a "no" needs a reason.
--   4. _crmb_prefs_set         do-not-contact on / off (on is open to the people who may record; off needs a manager and a reason).
--   5. _crmb_consent_get / _crmb_consent_get_mobile / _crmb_consent_history / _crmb_consent_summary   read side (no phone number in the summary).
--   6. _crmb_consent_import    paper list import (dry run first). An import never turns a withdrawn "no" back into a "yes".
--   7. _crmb_send_allowed / _crmb_enqueue_guard   one answer to "may this customer be messaged", used by the hook in notify_enqueue and by the campaign package.
--   8. _crmb_patch             exact-text patch helper for the hooks (closed to browsers).
-- SETTINGS (rules, module crm; all default OFF or blank, the owner changes them in the Switchboard / settings hub):
--   crm_consent_pos_on (OFF)   counter staff with POS enter may record a customer's yes / no. OFF = only the owner or a customer manager (today).
--   crm_quiet_from / crm_quiet_to (blank)   a quiet time window; blank = none. Read by _crmb_send_allowed only.
-- Accounting: nothing here reads or writes sales, payments or the journal.

do $g$ begin
  if to_regprocedure('public._i62_ok()') is null or to_regclass('public.notify_optin') is null or to_regclass('public.notify_optin_log') is null
     or to_regclass('public.notify_outbox') is null or to_regprocedure('public.customer_directory(integer)') is null or to_regprocedure('public._cust_pos43()') is null then
    raise exception 'phase303 needs phase 62 (notify_optin) and phase 43 (customers) first';
  end if;
end $g$;

create or replace function public._crmb_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (reads the CURRENT definition, so it sits on top of whatever is installed) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed and the call stops). Already patched (marker found) = no-op.
create or replace function public._crmb_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bosCRMB') returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

-- ---------- settings seed (used by phases 303 to 305; closed to browsers) ----------
create or replace function public._crmb_rule_seed(p_key text, p_kind text, p_default jsonb, p_unit text, p_choices jsonb, p_min numeric, p_max numeric, p_label text, p_hint text, p_sort int)
returns void language plpgsql set search_path = public as $$
begin
  insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
    values (p_key, 'crm', p_kind, p_default, p_unit, p_choices, p_min, p_max, p_label, p_label, p_label, p_hint, p_hint, p_hint, p_sort)
    on conflict (key) do nothing;
end $$;

do $r$ begin
  perform public._crmb_rule_seed('crm_consent_pos_on', 'switch', 'false'::jsonb, null, null, null, null,
  'Let counter staff record a customer''s yes or no to messages',
  'OFF = only the owner or a customer manager can record a customer''s consent (today). ON = anyone who can enter POS sales can tick yes or no at the counter. Staff can never use the owner-entry or import ways.', 3000);
  perform public._crmb_rule_seed('crm_quiet_from', 'text', null, null, null, null, null,
  'Quiet time starts (24-hour clock, for example 21:00)',
  'Blank = no quiet time. With both quiet times set, the message check says "quiet hours" inside the window. Shop time (Dhaka).', 3001);
  perform public._crmb_rule_seed('crm_quiet_to', 'text', null, null, null, null, null,
  'Quiet time ends (24-hour clock, for example 08:00)',
  'Blank = no quiet time. A window that runs past midnight is fine (21:00 to 08:00).', 3002);
end $r$;

-- ---------- tables ----------
create table if not exists public.crm_consent_events (        -- append-only evidence of every yes / no / do-not-contact
  id bigserial primary key,
  client_id uuid unique,
  batch_id uuid,
  customer_id uuid not null references public.customers(id),
  kind text not null check (kind in ('optin', 'dnc')),
  channel text check (channel in ('sms', 'whatsapp')),
  status text not null check (status in ('in', 'out', 'on', 'off')),
  how text not null check (how in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'import', 'other')),
  location_id int references public.locations(id),
  note text check (note is null or length(note) <= 300),
  text_version text check (text_version is null or length(text_version) <= 40),
  recorded_by uuid, staff_id text,
  at timestamptz not null default now(),
  check ((kind = 'optin' and channel is not null and status in ('in', 'out')) or (kind = 'dnc' and channel is null and status in ('on', 'off')))
);
create index if not exists crm_consent_events_cust on public.crm_consent_events (customer_id, id desc);
create index if not exists crm_consent_events_batch on public.crm_consent_events (batch_id) where batch_id is not null;

create table if not exists public.crm_contact_prefs (         -- do-not-contact: wins over every opt-in
  customer_id uuid primary key references public.customers(id),
  dnc boolean not null default false,
  note text check (note is null or length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now()
);

create or replace function public._crmb_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
drop trigger if exists crm_consent_events_ro on public.crm_consent_events;
create trigger crm_consent_events_ro before update or delete on public.crm_consent_events for each row execute function public._crmb_ro();
drop trigger if exists crm_contact_prefs_nodel on public.crm_contact_prefs;
create trigger crm_contact_prefs_nodel before delete on public.crm_contact_prefs for each row execute function public.no_hard_delete();
drop trigger if exists audit_crm_contact_prefs on public.crm_contact_prefs;
create trigger audit_crm_contact_prefs after insert or update on public.crm_contact_prefs for each row execute function public.log_change('customer_id');

do $t$ declare t text; begin
  foreach t in array array['crm_consent_events', 'crm_contact_prefs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok())', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_consent_events_id_seq from public, anon, authenticated;

-- ---------- who may record ----------
-- owner / customer manager (as today), plus POS-enter staff only while crm_consent_pos_on is ON
create or replace function public._crmb_consent_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._i62_ok() or (public.rule_on('crm_consent_pos_on') and public.can_do('POS', 'enter')));
$$;

create or replace function public._crmb_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;

-- ---------- group helpers (the soft link of phase305 may not exist yet: everything answers "just this customer") ----------
create or replace function public._crmb_links_active() returns table (primary_id uuid, linked_id uuid) language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.crm_customer_links') is null then return; end if;
  return query execute 'select l.primary_id, l.linked_id from public.crm_customer_links l where l.undone_at is null';
end $$;
create or replace function public._crmb_group_root(p_customer uuid) returns uuid language sql stable security definer set search_path = public as $$
  select coalesce((select l.primary_id from public._crmb_links_active() l where l.linked_id = p_customer), p_customer);
$$;
create or replace function public._crmb_group_ids(p_customer uuid) returns uuid[] language sql stable security definer set search_path = public as $$
  with r as (select public._crmb_group_root(p_customer) root)
  select array_agg(distinct x) from (select root x from r union select l.linked_id from public._crmb_links_active() l, r where l.primary_id = r.root union select p_customer) z;
$$;

-- ---------- the one answer to "may this customer be messaged?" ----------
-- Blocks that nothing may override: do-not-contact (this customer or anyone linked to the same person) and a withdrawn "no" (same). Returns the reason or null.
create or replace function public._crmb_block_reason(p_customer uuid, p_channel text) returns text language plpgsql stable security definer set search_path = public as $$
declare ids uuid[] := public._crmb_group_ids(p_customer);
begin
  if exists (select 1 from public.crm_contact_prefs p where p.customer_id = p_customer and p.dnc) then return 'dnc'; end if;
  if exists (select 1 from public.crm_contact_prefs p where p.customer_id = any(ids) and p.dnc) then return 'group_dnc'; end if;
  if exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'out') then return 'opted_out'; end if;
  if exists (select 1 from public.notify_optin o where o.customer_id = any(ids) and o.channel = p_channel and o.status = 'out') then return 'group_opted_out'; end if;
  return null;
end $$;

create or replace function public._crmb_in_quiet(p_now timestamptz) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f text := public.rule_txt('crm_quiet_from'); t text := public.rule_txt('crm_quiet_to'); n time := (p_now at time zone 'Asia/Dhaka')::time;
begin
  if f is null or t is null or f !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or f = t then return false; end if;
  if f::time < t::time then return n >= f::time and n < t::time; end if;
  return n >= f::time or n < t::time;
end $$;

-- p_purpose is accepted for the campaign package ('promo' / 'transactional'); today both need the customer's yes, exactly like notify_enqueue.
create or replace function public._crmb_send_allowed(p_customer uuid, p_channel text, p_purpose text default 'promo', p_now timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; b text;
begin
  if p_channel not in ('sms', 'whatsapp') then return jsonb_build_object('ok', false, 'reason', 'bad_channel', 'overridable', false); end if;
  select * into c from public.customers where id = p_customer;
  if not found then return jsonb_build_object('ok', false, 'reason', 'customer_not_found', 'overridable', false); end if;
  b := public._crmb_block_reason(p_customer, p_channel);
  if b is not null then return jsonb_build_object('ok', false, 'reason', b, 'overridable', false); end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then
    return jsonb_build_object('ok', false, 'reason', 'not_asked', 'overridable', false);
  end if;
  if public._i62_phone(c.mobile) is null then return jsonb_build_object('ok', false, 'reason', 'bad_phone', 'overridable', false); end if;
  if public._crmb_in_quiet(coalesce(p_now, now())) then return jsonb_build_object('ok', false, 'reason', 'quiet_hours', 'overridable', true); end if;
  return jsonb_build_object('ok', true, 'reason', null, 'overridable', false);
end $$;

-- the hook line inside notify_enqueue calls this after its own opt-in check: it refuses only the blocks above (never adds a way to send)
create or replace function public._crmb_enqueue_guard(p_customer uuid, p_channel text) returns void language plpgsql stable security definer set search_path = public as $$
declare b text := public._crmb_block_reason(p_customer, p_channel);
begin
  if b in ('dnc', 'group_dnc') then raise exception 'do_not_contact'; end if;
  if b in ('opted_out', 'group_opted_out') then raise exception 'not_opted_in'; end if;
end $$;

-- ---------- the write core (no permission check here: the callers decide) ----------
create or replace function public._crmb_consent_apply(p_customer uuid, p_channel text, p_in boolean, p_how text, p_note text, p_loc int, p_text_version text, p_client uuid, p_batch uuid, p_require_reason boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur text; st text := case when p_in then 'in' else 'out' end; src text; c public.customers; cancelled int := 0; ev bigint;
begin
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select status into cur from public.notify_optin where customer_id = p_customer and channel = p_channel for update;
  if cur = st then return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st, 'unchanged', true); end if;
  if p_in then
    if public._i62_phone(c.mobile) is null then raise exception 'bad_phone'; end if;
    if cur = 'out' and p_require_reason and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'reason_required'; end if;
  end if;
  src := case when p_how in ('pos_tick', 'phone', 'paper_form', 'message_reply') then 'customer_consent' else 'owner_entry' end;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, src, left(p_how || coalesce(': ' || nullif(btrim(p_note), ''), ''), 200), auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, src, left(p_how || coalesce(': ' || nullif(btrim(p_note), ''), ''), 200), auth.uid());
  insert into public.crm_consent_events (client_id, batch_id, customer_id, kind, channel, status, how, location_id, note, text_version, recorded_by, staff_id)
    values (p_client, p_batch, p_customer, 'optin', p_channel, st, p_how, p_loc, nullif(btrim(p_note), ''), nullif(btrim(p_text_version), ''), auth.uid(), public._crmb_staff()) returning id into ev;
  if not p_in then   -- a withdrawn yes cancels what still waits (the same rule as the old owner-only function)
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
    get diagnostics cancelled = row_count;
  end if;
  if cur = 'out' and p_in then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), public._crmb_staff(), 'crm_consent_resubscribe', 'notify_optin', p_customer::text || ':' || p_channel, jsonb_build_object('how', p_how, 'note', p_note));
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st, 'unchanged', false, 'event_id', ev, 'cancelled', cancelled);
end $$;

create or replace function public._crmb_consent_check_input(p_channel text, p_how text, p_note text, p_loc int, p_text_version text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_channel not in ('sms', 'whatsapp') or p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'import', 'other')
     or (p_note is not null and length(p_note) > 300) or (p_text_version is not null and length(p_text_version) > 40) then raise exception 'bad_input'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  -- counter staff (not a manager) may only use the ways that need the customer in front of them or on the phone
  if not public._i62_ok() and p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply') then raise exception 'not allowed'; end if;
end $$;

-- record a yes (p_in true) or a no (false). Idempotent: the same client id twice changes nothing.
create or replace function public._crmb_consent_set(p_client uuid, p_customer uuid, p_channel text, p_in boolean, p_how text default 'owner_entry', p_note text default null,
                                                    p_loc int default null, p_text_version text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_consent_events; r jsonb;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_customer is null or p_in is null then raise exception 'bad_input'; end if;
  perform public._crmb_consent_check_input(p_channel, p_how, p_note, p_loc, p_text_version);
  perform public._client_lock(p_client);
  select * into ex from public.crm_consent_events where client_id = p_client;
  if found then return jsonb_build_object('customer_id', ex.customer_id, 'channel', ex.channel, 'status', ex.status, 'duplicate', true, 'event_id', ex.id); end if;
  r := public._crmb_consent_apply(p_customer, p_channel, p_in, p_how, p_note, p_loc, p_text_version, p_client, null, true);
  return r || jsonb_build_object('duplicate', false);
end $$;

-- the POS knows the mobile the cashier typed, not always the customer id (a new customer exists only after the sale): same call by mobile
create or replace function public._crmb_consent_set_mobile(p_client uuid, p_mobile text, p_channel text, p_in boolean, p_how text default 'pos_tick', p_note text default null,
                                                           p_loc int default null, p_text_version text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m text; cid uuid;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_mobile is null or p_in is null then raise exception 'bad_input'; end if;
  begin m := public.norm_mobile(p_mobile); exception when others then raise exception 'bad_mobile'; end;
  select id into cid from public.customers where mobile = m;
  if cid is null then raise exception 'customer_not_found'; end if;
  return public._crmb_consent_set(p_client, cid, p_channel, p_in, p_how, p_note, p_loc, p_text_version);
end $$;

-- do-not-contact: ON is open to everyone who may record (protective); OFF needs a manager and a reason. ON cancels what still waits on both channels.
create or replace function public._crmb_prefs_set(p_client uuid, p_customer uuid, p_dnc boolean, p_note text default null, p_how text default 'owner_entry', p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_consent_events; cur boolean; cancelled int := 0;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_customer is null or p_dnc is null or p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'other')
     or (p_note is not null and length(p_note) > 300) then raise exception 'bad_input'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not public._i62_ok() and p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply') then raise exception 'not allowed'; end if;
  if not p_dnc and not public._i62_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_consent_events where client_id = p_client;
  if found then return jsonb_build_object('customer_id', ex.customer_id, 'dnc', ex.status = 'on', 'duplicate', true); end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  select dnc into cur from public.crm_contact_prefs where customer_id = p_customer for update;
  if coalesce(cur, false) = p_dnc then return jsonb_build_object('customer_id', p_customer, 'dnc', p_dnc, 'unchanged', true, 'duplicate', false); end if;
  if not p_dnc and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'reason_required'; end if;
  insert into public.crm_contact_prefs (customer_id, dnc, note, updated_by) values (p_customer, p_dnc, nullif(btrim(p_note), ''), auth.uid())
    on conflict (customer_id) do update set dnc = excluded.dnc, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  insert into public.crm_consent_events (client_id, customer_id, kind, channel, status, how, location_id, note, recorded_by, staff_id)
    values (p_client, p_customer, 'dnc', null, case when p_dnc then 'on' else 'off' end, p_how, p_loc, nullif(btrim(p_note), ''), auth.uid(), public._crmb_staff());
  if p_dnc then
    update public.notify_outbox set status = 'cancelled', last_error = 'do_not_contact' where customer_id = p_customer and status = 'queued';
    get diagnostics cancelled = row_count;
  end if;
  return jsonb_build_object('customer_id', p_customer, 'dnc', p_dnc, 'unchanged', false, 'duplicate', false, 'cancelled', cancelled);
end $$;

-- ---------- read side ----------
create or replace function public._crmb_consent_state(p_customer uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'customer_id', p_customer,
    'dnc', coalesce((select p.dnc from public.crm_contact_prefs p where p.customer_id = p_customer), false),
    'channels', (select jsonb_object_agg(ch, jsonb_build_object(
        'status', coalesce(o.status, 'not_asked'), 'at', o.changed_at, 'source', o.source,
        'how', (select e.how from public.crm_consent_events e where e.customer_id = p_customer and e.channel = ch order by e.id desc limit 1),
        'by', (select e.staff_id from public.crm_consent_events e where e.customer_id = p_customer and e.channel = ch order by e.id desc limit 1)))
      from unnest(array['sms', 'whatsapp']) ch left join public.notify_optin o on o.customer_id = p_customer and o.channel = ch));
$$;

create or replace function public._crmb_consent_get(p_customer uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  return public._crmb_consent_state(p_customer) || jsonb_build_object('block', public._crmb_block_reason(p_customer, 'sms'), 'can_manage', public._i62_ok());
end $$;

create or replace function public._crmb_consent_get_mobile(p_mobile text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m text; cid uuid;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  begin m := public.norm_mobile(p_mobile); exception when others then return jsonb_build_object('found', false); end;
  select id into cid from public.customers where mobile = m;
  if cid is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true) || public._crmb_consent_state(cid);
end $$;

create or replace function public._crmb_consent_history(p_customer uuid, p_limit int default 30) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select e.id, e.at, e.kind, e.channel, e.status, e.how, e.location_id, e.note, e.text_version, e.staff_id from public.crm_consent_events e
     where e.customer_id = p_customer order by e.id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) z), '[]'::jsonb);
end $$;

-- counts only: who has been asked, who said yes / no, who is do-not-contact. No name, no phone.
create or replace function public._crmb_consent_summary() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tot int; r jsonb := '{}'::jsonb; ch text; n_in int; n_out int; dn int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  select count(*) into tot from public.customers where active;
  select count(*) into dn from public.crm_contact_prefs p join public.customers c on c.id = p.customer_id where p.dnc and c.active;
  foreach ch in array array['sms', 'whatsapp'] loop
    select count(*) filter (where o.status = 'in'), count(*) filter (where o.status = 'out') into n_in, n_out
      from public.notify_optin o join public.customers c on c.id = o.customer_id where o.channel = ch and c.active;
    r := r || jsonb_build_object(ch, jsonb_build_object('in', n_in, 'out', n_out, 'not_asked', greatest(tot - n_in - n_out, 0),
          'coverage_pct', case when tot = 0 then null else round(100.0 * (n_in + n_out) / tot, 1) end));
  end loop;
  return jsonb_build_object('active_customers', tot, 'dnc', dn, 'channels', r);
end $$;

-- ---------- paper list import (owner or customer manager; dry run first) ----------
-- p_rows = [{"mobile": "01XXXXXXXXX"}, ...]. p_in true = they said yes on the paper list, false = they asked not to be contacted.
-- A customer who has withdrawn (status out) is NEVER turned back to yes by an import: that needs the one-by-one yes with a reason.
create or replace function public._crmb_consent_import(p_client uuid, p_rows jsonb, p_channel text, p_in boolean, p_list_note text, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; i int := 0; m text; cid uuid; cur text; st text; out_rows jsonb := '[]'::jsonb; seen text[] := '{}'; n_ok int := 0; n_same int := 0; n_err int := 0; n_blocked int := 0; ex int; want text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' or p_in is null or p_channel not in ('sms', 'whatsapp') then raise exception 'bad_input'; end if;
  if coalesce(length(btrim(p_list_note)), 0) < 3 or length(p_list_note) > 200 then raise exception 'reason_required'; end if;
  if jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if not p_dry then
    perform public._client_lock(p_client);
    select count(*) into ex from public.crm_consent_events where batch_id = p_client;
    if ex > 0 then return jsonb_build_object('dry', false, 'duplicate', true, 'changed', ex); end if;
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; m := null; cid := null; st := null;
    begin m := public.norm_mobile(r ->> 'mobile'); exception when others then m := null; end;
    if m is null or m !~ '^01[0-9]{9}$' then st := 'bad_mobile';
    elsif m = any(seen) then st := 'duplicate_row';
    else
      seen := seen || m;
      select id into cid from public.customers where mobile = m;
      if cid is null then st := 'unknown_customer';
      else
        select status into cur from public.notify_optin where customer_id = cid and channel = p_channel;
        if cur = want then st := 'same';
        elsif p_in and cur = 'out' then st := 'withdrawn_kept';
        else st := 'will_change';
        end if;
      end if;
    end if;
    if st = 'will_change' then n_ok := n_ok + 1; elsif st = 'same' then n_same := n_same + 1; elsif st = 'withdrawn_kept' then n_blocked := n_blocked + 1; else n_err := n_err + 1; end if;
    out_rows := out_rows || jsonb_build_array(jsonb_build_object('i', i, 'mobile', m, 'status', st));
    if not p_dry and st = 'will_change' then
      perform public._crmb_consent_apply(cid, p_channel, p_in, 'import', p_list_note, null, null, null, p_client, false);
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'duplicate', false, 'will_change', n_ok, 'same', n_same, 'withdrawn_kept', n_blocked, 'errors', n_err, 'rows', out_rows);
end $$;

-- ---------- hook texts (single source of truth; docs/integration/CRM-B.md copies them) ----------
-- notify_enqueue: after its own opt-in check, refuse do-not-contact and a withdrawn "no" of a linked duplicate.   notify_optin_set: also write the evidence line.
create or replace function public._crmb_hook_pairs(p_fn text) returns text[] language sql immutable set search_path = public as $$
  select case p_fn
    when 'notify_enqueue' then array[
      $a$then raise exception 'not_opted_in'; end if;
  ph := public._i62_phone(c.mobile);$a$,
      $a$then raise exception 'not_opted_in'; end if;
  perform public._crmb_enqueue_guard(p_customer, p_channel); /* bosCRMB: do-not-contact and linked duplicates */
  ph := public._i62_phone(c.mobile);$a$]
    when 'notify_optin_set' then array[
      $a$  if not p_in then   -- opting out cancels what is still waiting$a$,
      $a$  perform public._crmb_legacy_evidence(p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note); /* bosCRMB: evidence line */
  if not p_in then   -- opting out cancels what is still waiting$a$]
  end;
$$;

-- evidence line for a change made through the old owner-only function (never blocks it)
create or replace function public._crmb_legacy_evidence(p_customer uuid, p_channel text, p_status text, p_source text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_consent_events (customer_id, kind, channel, status, how, note, recorded_by, staff_id)
    values (p_customer, 'optin', p_channel, p_status, case when p_source = 'customer_consent' then 'other' else 'owner_entry' end, left('old function: ' || coalesce(p_note, ''), 300), auth.uid(), public._crmb_staff());
exception when others then
  raise warning 'crm evidence line skipped: %', sqlerrm;
end $$;

-- ---------- privileges (only the functions of THIS file, so pasting this file again never touches the grants of phases 304 and 305) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_present', '_crmb_patch', '_crmb_rule_seed', '_crmb_ro', '_crmb_consent_ok', '_crmb_staff', '_crmb_links_active', '_crmb_group_root', '_crmb_group_ids',
              '_crmb_block_reason', '_crmb_in_quiet', '_crmb_send_allowed', '_crmb_enqueue_guard', '_crmb_consent_apply', '_crmb_consent_check_input', '_crmb_consent_set',
              '_crmb_consent_set_mobile', '_crmb_prefs_set', '_crmb_consent_state', '_crmb_consent_get', '_crmb_consent_get_mobile', '_crmb_consent_history', '_crmb_consent_summary',
              '_crmb_consent_import', '_crmb_hook_pairs', '_crmb_legacy_evidence']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_consent_set(uuid, uuid, text, boolean, text, text, int, text), public._crmb_consent_set_mobile(uuid, text, text, boolean, text, text, int, text),
  public._crmb_prefs_set(uuid, uuid, boolean, text, text, int), public._crmb_consent_get(uuid), public._crmb_consent_get_mobile(text), public._crmb_consent_history(uuid, int),
  public._crmb_consent_summary(), public._crmb_consent_import(uuid, jsonb, text, boolean, text, boolean), public._crmb_consent_ok() to authenticated;

-- ===================== phase304.sql =====================
-- Phase 304 (CRM package B, local label 104) - PRIVACY BY ROLE: who sees, exports or prints customer phone numbers and customer lists, with a log.
-- Paste AFTER phase303. Paste-twice safe. No earlier phase file is edited and NO shared function is re-created.
-- The integrator wires the hooks written in docs/integration/CRM-B.md (customers.js reads the list through _crmb_customer_list, the Call button and the Print button ask first).
--
-- WHY (CRM audit rows 57 to 60): customers_read (phase6) lets every POS-view user read every customer row and customer_directory() (phase43) returns name, mobile, address and
-- WhatsApp of up to 20000 customers unmasked. Masking exists for reports (rpt_mobile_ok) and for the inbox (phase76), not for the customer list. There was no log of who looked at
-- a number and no export control for customers.
-- THE SAFE DEFAULT KEEPS TODAY'S BEHAVIOUR: crm_pii_guard_on is OFF, so _crmb_customer_list returns exactly what customer_directory returns. Switching the guard ON masks phone and
-- address for everybody except the owner and holders of the grant crm_contact_view, in the functions below. Direct table reads of customers stay as they are (documented residual
-- exposure: a person with POS view can still read the table through the API; closing that is an owner decision, see CRM-B.md section 5).
-- WHAT THIS FILE ADDS
--   1. _crmb_customer_list(limit, collapse)   masked list with the same columns as customer_directory plus masked / linked_to / linked_count. collapse = one row per person (linked duplicates folded, phase305).
--   1b. _crmb_customer_profile(customer)       customer_profile with phone, WhatsApp and address masked for a person who may not see them (same shape plus masked).
--   2. _crmb_phone_reveal(customer, reason)    returns the full number once and writes crm_view_log (a reason when the setting asks for one).
--   3. _crmb_export(...) + crm_export_log      customer export with reason, row cap, masked columns, one log line; blocked until the owner sets a row cap.
--   4. _crmb_print_log(...)                    writes a print line; with crm_print_needs_export ON, printing a customer list needs the export right.
--   5. _crmb_policy()                          one call for the screens: what this person may do right now.
--   6. _crmb_consent_register(...)             the consent register list (names, masked phone, yes / no / not asked), counts from phase303.
--   7. _crmb_view_log_list / _crmb_export_log_list   owner only.
-- SETTINGS (rules, module crm): crm_pii_guard_on (OFF), crm_mask_style (first3_last2), crm_unmask_reason_required (ON; only matters when the guard is ON), crm_reveal_for_call (OFF),
--   crm_export_on (OFF), crm_export_max_rows (blank = blocked), crm_print_needs_export (OFF).  GRANTS (given by the owner, nobody has them by default): crm_contact_view, crm_export.
-- Accounting: nothing here reads or writes sales payments or the journal beyond what customer_directory already reads.

do $g$ begin
  if to_regprocedure('public._crmb_present()') is null then raise exception 'phase304 needs phase303 first'; end if;
end $g$;

do $r$ begin
  perform public._crmb_rule_seed('crm_pii_guard_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Show customer phone and address only to people who are allowed',
    'OFF = every customer list shows phone numbers as today. ON = the CRM customer list and sheets show a masked number (for example 017******78) and no address, except to the owner and people given "See customers'' full phone and address". Does not stop a person with POS access from reading the table through the API.', 3100);
  perform public._crmb_rule_seed('crm_mask_style', 'choice', '"first3_last2"'::jsonb, null, '["first3_last2","last4"]'::jsonb, null, null,
    'How a hidden phone number looks',
    'first3_last2 shows the first three and last two digits (017******78). last4 shows only the last four digits. Used only while the privacy switch is ON.', 3101);
  perform public._crmb_rule_seed('crm_unmask_reason_required', 'switch', 'true'::jsonb, null, null, null, null,
    'Ask for a reason before showing a full phone number',
    'ON = staff other than the owner write a short reason (at least 3 characters) each time they open a hidden number; it goes in the access log. Used only while the privacy switch is ON.', 3102);
  perform public._crmb_rule_seed('crm_reveal_for_call', 'switch', 'false'::jsonb, null, null, null, null,
    'Let counter staff ask for one number at a time to call',
    'OFF = a masked person cannot open the full number. ON = they can open one number at a time to call, always with a reason, and every look is in the access log. Used only while the privacy switch is ON.', 3103);
  perform public._crmb_rule_seed('crm_export_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Allow the customer list to be exported',
    'OFF = no customer export (today). ON = the owner and people given "Export the customer list" can export, with a row cap and a log line. Blocked until the row cap below is set.', 3104);
  perform public._crmb_rule_seed('crm_export_max_rows', 'number', null, 'rows', null, 1, 20000,
    'Most customers one export may contain',
    'Blank = export stays blocked even when switched on. Set a number to allow it.', 3105);
  perform public._crmb_rule_seed('crm_print_needs_export', 'switch', 'false'::jsonb, null, null, null, null,
    'Printing a customer list needs the export right',
    'OFF = anyone who sees the list can print it (today). ON = only the owner and people given "Export the customer list" can print it. The screen enforces the button; the print is logged either way.', 3106);
end $r$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_contact_view', 'pos', 96, 'See customers'' full phone and address', 'See customers'' full phone and address', 'See customers'' full phone and address', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_contact_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_export', 'pos', 97, 'Export the customer list', 'Export the customer list', 'Export the customer list', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_export');

-- ---------- logs (append only, owner reads) ----------
create table if not exists public.crm_view_log (          -- who opened a hidden contact detail, when, why
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  customer_id uuid references public.customers(id),
  what text not null check (what in ('contact', 'call', 'list', 'profile')),
  reason text check (reason is null or length(reason) <= 200),
  row_count int,
  detail jsonb
);
create index if not exists crm_view_log_at on public.crm_view_log (id desc);
create index if not exists crm_view_log_cust on public.crm_view_log (customer_id, id desc);
create table if not exists public.crm_export_log (        -- every customer export and customer-list print
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  kind text not null check (kind in ('export', 'print')),
  what text not null,
  filter jsonb,
  row_count int not null default 0,
  masked boolean not null default false,
  format text,
  reason text check (reason is null or length(reason) <= 200)
);
drop trigger if exists crm_view_log_ro on public.crm_view_log;
create trigger crm_view_log_ro before update or delete on public.crm_view_log for each row execute function public._crmb_ro();
drop trigger if exists crm_export_log_ro on public.crm_export_log;
create trigger crm_export_log_ro before update or delete on public.crm_export_log for each row execute function public._crmb_ro();
do $t$ declare t text; begin
  foreach t in array array['crm_view_log', 'crm_export_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner())', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_view_log_id_seq, public.crm_export_log_id_seq from public, anon, authenticated;

-- ---------- masking ----------
create or replace function public._crmb_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (not public.rule_on('crm_pii_guard_on') or public.is_owner() or public.has_grant('crm_contact_view'));
$$;

create or replace function public._crmb_mask_phone(p text) returns text language plpgsql stable security definer set search_path = public as $$
declare n int := length(coalesce(p, ''));
begin
  if p is null then return null; end if;
  if n <= 5 then return repeat('*', n); end if;
  if coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'last4' then return repeat('*', n - 4) || right(p, 4); end if;
  return left(p, 3) || repeat('*', n - 5) || right(p, 2);
end $$;

create or replace function public._crmb_view_log_add(p_customer uuid, p_what text, p_reason text, p_count int, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_view_log (user_id, staff_id, customer_id, what, reason, row_count, detail)
    values (auth.uid(), public._crmb_staff(), p_customer, p_what, nullif(btrim(p_reason), ''), p_count, p_detail);
end $$;

-- ---------- the customer list (same columns as customer_directory + masked / linked_to / linked_count) ----------
create or replace function public._crmb_customer_rows(p_limit int, p_collapse boolean, p_log boolean)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int, masked boolean, linked_to uuid, linked_count int)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare ok boolean; lim int := least(greatest(coalesce(p_limit, 5000), 1), 20000);
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  ok := public._crmb_contact_ok();
  -- while the guard is ON, a person who sees the numbers (not the owner) leaves one line per list they open
  if p_log and ok and public.rule_on('crm_pii_guard_on') and not public.is_owner() then
    perform public._crmb_view_log_add(null, 'list', null, lim, jsonb_build_object('collapse', coalesce(p_collapse, false)));
  end if;
  return query
    with d as (select x.* from public.customer_directory(lim) x),
         lk as (select l.primary_id pid, l.linked_id lid from public._crmb_links_active() l),
         g as (select lk.pid, count(*)::int cnt, sum(dd.spend) sp, sum(dd.orders)::int ord, max(dd.last_sale) ls, sum(dd.points)::int pt
                 from lk join d dd on dd.id = lk.lid group by lk.pid)
    select d.id, case when ok then d.mobile else public._crmb_mask_phone(d.mobile) end, d.name, d.type, d.active, d.tier_id, d.tier_locked, d.birthday, d.anniversary,
           case when ok then d.address end, case when ok then d.whatsapp else public._crmb_mask_phone(d.whatsapp) end, d.note, d.credit_limit, d.customer_since,
           d.balance,                                                                                                  -- a balance is never added up across a link: ledgers stay separate
           case when p_collapse then d.spend + coalesce(g.sp, 0) else d.spend end,
           case when p_collapse then d.orders + coalesce(g.ord, 0) else d.orders end,
           case when p_collapse then greatest(d.last_sale, g.ls) else d.last_sale end,
           case when p_collapse then d.points + coalesce(g.pt, 0) else d.points end,
           not ok, (select lk.pid from lk where lk.lid = d.id), coalesce(g.cnt, 0)
      from d left join g on g.pid = d.id
     where not (coalesce(p_collapse, false) and exists (select 1 from lk where lk.lid = d.id))
     order by lower(d.name), d.mobile;
end $$;

create or replace function public._crmb_customer_list(p_limit int default 5000, p_collapse boolean default false)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int, masked boolean, linked_to uuid, linked_count int)
language sql security definer set search_path = public as $$
  select * from public._crmb_customer_rows(p_limit, p_collapse, true);
$$;

-- the customer profile (customer_profile unchanged) with phone, WhatsApp and address hidden for a person who may not see them; same shape, plus masked
create or replace function public._crmb_customer_profile(p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j jsonb := public.customer_profile(p_customer); ok boolean := public._crmb_contact_ok();
begin
  if ok then
    if public.rule_on('crm_pii_guard_on') and not public.is_owner() then perform public._crmb_view_log_add(p_customer, 'profile', null, 1, null); end if;
    return j || jsonb_build_object('masked', false);
  end if;
  return jsonb_set(j, '{customer}', (j -> 'customer') || jsonb_build_object('mobile', public._crmb_mask_phone(j -> 'customer' ->> 'mobile'), 'whatsapp', public._crmb_mask_phone(j -> 'customer' ->> 'whatsapp'), 'address', null)) || jsonb_build_object('masked', true);
end $$;

-- one number, once, with a log line
create or replace function public._crmb_phone_reveal(p_customer uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; ok boolean; guard boolean := public.rule_on('crm_pii_guard_on');
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if not guard then   -- nothing is hidden today: answer, nothing to log
    return jsonb_build_object('id', c.id, 'name', c.name, 'mobile', c.mobile, 'whatsapp', c.whatsapp, 'address', c.address, 'logged', false);
  end if;
  ok := public._crmb_contact_ok();
  if not ok and not public.rule_on('crm_reveal_for_call') then raise exception 'not allowed'; end if;
  if not public.is_owner() and public.rule_on('crm_unmask_reason_required') and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if p_reason is not null and length(p_reason) > 200 then raise exception 'bad_input'; end if;
  perform public._crmb_view_log_add(c.id, case when ok then 'contact' else 'call' end, p_reason, 1, null);
  return jsonb_build_object('id', c.id, 'name', c.name, 'mobile', c.mobile, 'whatsapp', c.whatsapp, 'address', case when ok then c.address end, 'logged', true);
end $$;

create or replace function public._crmb_view_log_list(p_limit int default 100, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select v.id, v.at, v.staff_id, v.what, v.reason, v.row_count, v.customer_id, c.name as customer_name from public.crm_view_log v left join public.customers c on c.id = v.customer_id
     where p_customer is null or v.customer_id = p_customer order by v.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- export and print ----------
create or replace function public._crmb_export(p_dataset text default 'customers', p_filter jsonb default '{}'::jsonb, p_format text default 'json', p_limit int default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare maxr numeric; lim int; ok boolean; fmt text := lower(coalesce(p_format, 'json')); f jsonb := coalesce(p_filter, '{}'::jsonb); k text; rows jsonb; n int; trunc boolean; logid bigint;
        cols text[] := array['id', 'name', 'mobile', 'whatsapp', 'type', 'tier_id', 'active', 'birthday', 'anniversary', 'address', 'spend', 'orders', 'last_sale', 'points', 'balance'];
        q text; collapse boolean; csv text := ''; r jsonb; c text; line text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_export_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('crm_export')) or not public._cust_pos43() then raise exception 'not allowed'; end if;
  maxr := public.rule_num('crm_export_max_rows');
  if maxr is null then raise exception 'export_limit_not_set'; end if;
  if p_dataset is distinct from 'customers' then raise exception 'bad_dataset'; end if;
  if fmt not in ('json', 'csv') then raise exception 'bad_format'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'bad_filter'; end if;
  for k in select jsonb_object_keys(f) loop
    if k not in ('active', 'tier_id', 'type', 'has_due', 'birthday_month', 'search', 'collapse') then raise exception 'bad_filter'; end if;
  end loop;
  begin
    if f ? 'active' then perform (f ->> 'active')::boolean; end if;
    if f ? 'tier_id' then perform (f ->> 'tier_id')::bigint; end if;
    if f ? 'has_due' then perform (f ->> 'has_due')::boolean; end if;
    if f ? 'collapse' then collapse := (f ->> 'collapse')::boolean; end if;
    if f ? 'birthday_month' and ((f ->> 'birthday_month')::int not between 1 and 12) then raise exception 'x'; end if;
  exception when others then raise exception 'bad_filter';
  end;
  if f ? 'type' and (f ->> 'type') not in ('retail', 'wholesale') then raise exception 'bad_filter'; end if;
  if f ? 'search' and length(f ->> 'search') > 60 then raise exception 'bad_filter'; end if;
  if not public.is_owner() and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if p_reason is not null and length(p_reason) > 200 then raise exception 'bad_input'; end if;
  ok := public._crmb_contact_ok();
  lim := least(greatest(coalesce(p_limit, maxr::int), 1), maxr::int);
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'name', z.name, 'mobile', z.mobile, 'whatsapp', z.whatsapp, 'type', z.type, 'tier_id', z.tier_id, 'active', z.active,
           'birthday', z.birthday, 'anniversary', z.anniversary, 'address', z.address, 'spend', z.spend, 'orders', z.orders, 'last_sale', z.last_sale, 'points', z.points, 'balance', z.balance)
           order by lower(z.name), z.id), '[]'::jsonb), count(*)::int
    into rows, n
    from (select x.* from public._crmb_customer_rows(20000, coalesce(collapse, false), false) x
           where (not (f ? 'active') or x.active = (f ->> 'active')::boolean)
             and (not (f ? 'tier_id') or x.tier_id = (f ->> 'tier_id')::bigint)
             and (not (f ? 'type') or x.type = f ->> 'type')
             and (not (f ? 'has_due') or (x.balance > 0) = (f ->> 'has_due')::boolean)
             and (not (f ? 'birthday_month') or extract(month from x.birthday) = (f ->> 'birthday_month')::int)
             and (not (f ? 'search') or lower(x.name) like '%' || lower(f ->> 'search') || '%' or (ok and x.mobile like '%' || (f ->> 'search') || '%'))
           order by lower(x.name), x.id limit lim + 1) z;
  trunc := n > lim;
  if trunc then rows := (select coalesce(jsonb_agg(e), '[]'::jsonb) from (select e from jsonb_array_elements(rows) with ordinality t(e, o) order by o limit lim) y); n := lim; end if;
  if fmt = 'csv' then
    csv := (select string_agg(public._i62_csv(c2), ',') from unnest(cols) c2) || E'\n';
    for r in select * from jsonb_array_elements(rows) loop
      line := null;
      foreach c in array cols loop line := coalesce(line || ',', '') || public._i62_csv(r ->> c); end loop;
      csv := csv || line || E'\n';
    end loop;
  end if;
  insert into public.crm_export_log (user_id, staff_id, kind, what, filter, row_count, masked, format, reason)
    values (auth.uid(), public._crmb_staff(), 'export', 'customers', f, n, not ok, fmt, nullif(btrim(p_reason), '')) returning id into logid;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'export', 'customers', logid::text, jsonb_build_object('rows', n, 'masked', not ok, 'format', fmt, 'filter', f));
  return jsonb_build_object('log_id', logid, 'count', n, 'truncated', trunc, 'masked', not ok, 'format', fmt, 'columns', to_jsonb(cols),
                            'rows', case when fmt = 'json' then rows end, 'csv', case when fmt = 'csv' then csv end);
end $$;

create or replace function public._crmb_print_log(p_what text, p_count int, p_reason text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare logid bigint;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if p_what not in ('customer_list', 'customer_sheet', 'customer_labels') or p_count is null or p_count < 0 or p_count > 100000 or (p_reason is not null and length(p_reason) > 200) then raise exception 'bad_input'; end if;
  if public.rule_on('crm_print_needs_export') and not (public.is_owner() or public.has_grant('crm_export')) then raise exception 'not allowed'; end if;
  insert into public.crm_export_log (user_id, staff_id, kind, what, filter, row_count, masked, format, reason)
    values (auth.uid(), public._crmb_staff(), 'print', p_what, null, p_count, not public._crmb_contact_ok(), 'print', nullif(btrim(p_reason), '')) returning id into logid;
  return logid;
end $$;

create or replace function public._crmb_export_log_list(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (select * from public.crm_export_log order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- what may this person do right now (one call for the screens; no customer data inside) ----------
create or replace function public._crmb_policy() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ok boolean; exp boolean; cap numeric := public.rule_num('crm_export_max_rows');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ok := public._crmb_contact_ok();
  exp := public.is_owner() or public.has_grant('crm_export');
  return jsonb_build_object(
    'guard_on', public.rule_on('crm_pii_guard_on'), 'contact_ok', ok, 'mask_style', coalesce(public.rule_txt('crm_mask_style'), 'first3_last2'),
    'can_reveal', ok or (public.rule_on('crm_pii_guard_on') and public.rule_on('crm_reveal_for_call') and public._cust_pos43()),
    'reason_required', public.rule_on('crm_pii_guard_on') and public.rule_on('crm_unmask_reason_required') and not public.is_owner(),
    'export_on', public.rule_on('crm_export_on'), 'export_cap', cap, 'can_export', public.rule_on('crm_export_on') and cap is not null and exp and public._cust_pos43(),
    'print_needs_export', public.rule_on('crm_print_needs_export'), 'can_print', public._cust_pos43() and (not public.rule_on('crm_print_needs_export') or exp),
    'can_consent', public._crmb_consent_ok(), 'can_manage_consent', public._i62_ok(), 'consent_pos_on', public.rule_on('crm_consent_pos_on'),
    'dup_on', public.rule_on('crm_dup_check_on'), 'can_merge', public.is_owner() or public.has_grant('crm_merge'), 'can_link', public.rule_on('crm_dup_check_on') and (public.is_owner() or public.has_grant('crm_merge')),
    'is_owner', public.is_owner());
end $$;

-- ---------- the consent register list (names, masked phone, yes / no / not asked) ----------
create or replace function public._crmb_consent_register(p_status text default null, p_channel text default 'sms', p_search text default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ok boolean := public._crmb_contact_ok(); lim int := least(greatest(coalesce(p_limit, 50), 1), 200); off int := greatest(coalesce(p_offset, 0), 0); tot int; rows jsonb; s text := nullif(btrim(p_search), '');
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_channel not in ('sms', 'whatsapp') or (p_status is not null and p_status not in ('in', 'out', 'not_asked', 'dnc')) or (s is not null and length(s) > 60) then raise exception 'bad_input'; end if;
  with base as (
    select c.id, c.name, c.mobile, coalesce(o.status, 'not_asked') st, o.changed_at, coalesce(p.dnc, false) dnc
      from public.customers c left join public.notify_optin o on o.customer_id = c.id and o.channel = p_channel left join public.crm_contact_prefs p on p.customer_id = c.id
     where c.active
       and (s is null or lower(c.name) like '%' || lower(s) || '%' or (ok and c.mobile like '%' || s || '%'))
       and (p_status is null or (p_status = 'dnc' and coalesce(p.dnc, false)) or (p_status <> 'dnc' and coalesce(o.status, 'not_asked') = p_status))),
  pg as (select * from base order by lower(name), id limit lim offset off)
  select (select count(*) from base), coalesce(jsonb_agg(jsonb_build_object('id', pg.id, 'name', pg.name, 'mobile', case when ok then pg.mobile else public._crmb_mask_phone(pg.mobile) end,
           'status', pg.st, 'at', pg.changed_at, 'dnc', pg.dnc,
           'how', (select e.how from public.crm_consent_events e where e.customer_id = pg.id and e.channel = p_channel order by e.id desc limit 1)) order by lower(pg.name), pg.id), '[]'::jsonb)
    into tot, rows from pg;
  return jsonb_build_object('total', tot, 'rows', rows, 'masked', not ok, 'summary', public._crmb_consent_summary());
end $$;

-- ---------- privileges (only the functions of THIS file) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_contact_ok', '_crmb_mask_phone', '_crmb_view_log_add', '_crmb_customer_rows', '_crmb_customer_list', '_crmb_customer_profile', '_crmb_phone_reveal', '_crmb_view_log_list',
              '_crmb_export', '_crmb_print_log', '_crmb_export_log_list', '_crmb_policy', '_crmb_consent_register']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_customer_list(int, boolean), public._crmb_customer_profile(uuid), public._crmb_phone_reveal(uuid, text), public._crmb_view_log_list(int, uuid), public._crmb_export(text, jsonb, text, int, text),
  public._crmb_print_log(text, int, text), public._crmb_export_log_list(int), public._crmb_policy(), public._crmb_consent_register(text, text, text, int, int), public._crmb_contact_ok() to authenticated;

-- ===================== phase305.sql =====================
-- Phase 305 (CRM package B, local label 105) - DUPLICATE CUSTOMERS: a "possible duplicates" review list and a SOFT link ("same person").
-- Paste AFTER phase304. Paste-twice safe. No earlier phase file is edited and NO shared function is re-created. Nothing is merged, moved or deleted.
--
-- WHY (CRM audit rows 11, 12 and risk R3): customer_save only catches an exact mobile number. The same person under a second number or a spelling variant splits history,
-- points and tier. A hard merge is NOT safe: journal_lines.party_id (phase40), customer_dues, _cust_bal and collect_payment carry the customer id, so moving rows would change
-- accounting. The soft link only GROUPS two customers for CRM views: the list (_crmb_customer_list with collapse), the customer group view, and the message check
-- (a withdrawn "no" or a do-not-contact of one number protects the other number of the same person). Customer ids never change; sales, payments, dues and the journal are not touched.
-- WHAT THIS FILE ADDS
--   1. crm_customer_links      the soft link: primary customer + linked customer + reason + who + when; append-only, undone by a stamp, never deleted.
--                              One active link per linked customer; a primary can never be linked itself, so a loop (A under B and B under A) cannot exist.
--   2. crm_dup_reviews         "these two are not the same person" decisions, so a pair is not offered again (can be reopened).
--   3. _crmb_dup_candidates    the review list: same phone (mobile, WhatsApp, and customer_phones when that table exists), same name, similar name (one letter apart, only when the owner switches it on),
--                              each pair with its reasons and a strength (strong / possible / weak). Phones are masked by the privacy setting.
--   4. _crmb_link_customers / _crmb_unlink_customers / _crmb_dup_review / _crmb_customer_group / _crmb_links_list.
-- SETTINGS (rules, module crm): crm_dup_check_on (OFF = no list, no new link; customer_save and the POS behave exactly as today), crm_dup_similar_names_on (OFF = names must match after
--   removing spaces, capitals and punctuation; ON = also names one letter apart). GRANT: crm_merge (the owner always may). Every link needs a written reason and writes an audit line and a yellow row in the Exceptions list.

do $g$ begin
  if to_regprocedure('public._crmb_customer_rows(integer,boolean,boolean)') is null then raise exception 'phase305 needs phase304 (and 303) first'; end if;
  if to_regprocedure('public._cust_stats43(uuid,boolean)') is null then raise exception 'phase305 needs phase43 first'; end if;
end $g$;

do $r$ begin
  perform public._crmb_rule_seed('crm_dup_check_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Look for duplicate customers and allow linking them as one person',
    'OFF = no duplicate list and no new link (today; saving a customer still stops on an identical mobile number). ON = the review list is built and people with the right can link two customers as the same person. A link never moves sales, payments, dues or the books.', 3200);
  perform public._crmb_rule_seed('crm_dup_similar_names_on', 'switch', 'false'::jsonb, null, null, null, null,
    'Also list names that differ by one letter',
    'OFF = names must be the same after removing spaces, capitals and punctuation. ON = a name that differs by one letter (a spelling slip) is also listed, as a weak hint, unless it shares an address or birthday.', 3201);
end $r$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_merge', 'pos', 98, 'Link two customers as the same person', 'Link two customers as the same person', 'Link two customers as the same person', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_merge');

-- ---------- tables ----------
create table if not exists public.crm_customer_links (
  id bigserial primary key,
  client_id uuid unique,
  primary_id uuid not null references public.customers(id),
  linked_id uuid not null references public.customers(id),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  undone_at timestamptz, undone_by uuid, undo_reason text check (undo_reason is null or length(undo_reason) <= 300), undo_client uuid unique,
  check (primary_id <> linked_id)
);
create unique index if not exists crm_customer_links_one_active on public.crm_customer_links (linked_id) where undone_at is null;
create index if not exists crm_customer_links_primary on public.crm_customer_links (primary_id) where undone_at is null;

create table if not exists public.crm_dup_reviews (
  id bigserial primary key,
  client_id uuid unique,
  a_id uuid not null references public.customers(id),
  b_id uuid not null references public.customers(id),
  reason text check (reason is null or length(reason) <= 300),
  decided_by uuid, decided_staff text, decided_at timestamptz not null default now(),
  undone_at timestamptz, undone_by uuid,
  check (a_id < b_id)
);
create unique index if not exists crm_dup_reviews_one_active on public.crm_dup_reviews (a_id, b_id) where undone_at is null;

-- a link row can only be stamped as undone (once); it can never be deleted or rewritten; a loop cannot be inserted even by a direct write
create or replace function public._crmb_links_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'crm_customer_links is append-only'; end if;
  if tg_op = 'UPDATE' then
    if old.undone_at is not null or new.undone_at is null or new.primary_id is distinct from old.primary_id or new.linked_id is distinct from old.linked_id
       or new.reason is distinct from old.reason or new.created_at is distinct from old.created_at or new.client_id is distinct from old.client_id then
      raise exception 'crm_customer_links can only be undone once';
    end if;
    return new;
  end if;
  if exists (select 1 from public.crm_customer_links l where l.linked_id = new.primary_id and l.undone_at is null) then raise exception 'primary_is_linked'; end if;
  if exists (select 1 from public.crm_customer_links l where l.primary_id = new.linked_id and l.undone_at is null) then raise exception 'linked_has_members'; end if;
  return new;
end $$;
drop trigger if exists crm_customer_links_guard on public.crm_customer_links;
create trigger crm_customer_links_guard before insert or update or delete on public.crm_customer_links for each row execute function public._crmb_links_guard();
drop trigger if exists audit_crm_customer_links on public.crm_customer_links;
create trigger audit_crm_customer_links after insert or update on public.crm_customer_links for each row execute function public.log_change('id');
drop trigger if exists crm_dup_reviews_nodel on public.crm_dup_reviews;
create trigger crm_dup_reviews_nodel before delete on public.crm_dup_reviews for each row execute function public.no_hard_delete();
drop trigger if exists audit_crm_dup_reviews on public.crm_dup_reviews;
create trigger audit_crm_dup_reviews after insert or update on public.crm_dup_reviews for each row execute function public.log_change('id');

do $t$ declare t text; begin
  foreach t in array array['crm_customer_links', 'crm_dup_reviews'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok() or public.has_grant(''crm_merge''))', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_customer_links_id_seq, public.crm_dup_reviews_id_seq from public, anon, authenticated;

-- ---------- helpers ----------
create or replace function public._crmb_dup_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._i62_ok() or public.has_grant('crm_merge'));
$$;
create or replace function public._crmb_merge_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_merge'));
$$;
create or replace function public._crmb_norm_name(p text) returns text language sql immutable set search_path = public as $$
  select regexp_replace(lower(btrim(coalesce(p, ''))), '[\s\.\,\-_''"()/]+', '', 'g');
$$;
create or replace function public._crmb_norm_phone(p text) returns text language plpgsql immutable set search_path = public as $$
begin
  if p is null or btrim(p) = '' then return null; end if;
  return public.norm_mobile(p);
exception when others then return null;
end $$;
-- spelling distance with a cap (stops early; returns cap + 1 when the names are further apart)
create or replace function public._crmb_lev(a text, b text, cap int) returns int language plpgsql immutable set search_path = public as $$
declare la int := length(a); lb int := length(b); prev int[]; cur int[]; i int; j int; cost int; best int;
begin
  if abs(la - lb) > cap then return cap + 1; end if;
  if la = 0 then return lb; end if;
  if lb = 0 then return la; end if;
  prev := array(select generate_series(0, lb));
  for i in 1 .. la loop
    cur := array[i];
    best := i;
    for j in 1 .. lb loop
      cost := case when substr(a, i, 1) = substr(b, j, 1) then 0 else 1 end;
      cur := cur || least(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost);
      if cur[j + 1] < best then best := cur[j + 1]; end if;
    end loop;
    if best > cap then return cap + 1; end if;
    prev := cur;
  end loop;
  return prev[lb + 1];
end $$;
create or replace function public._crmb_exc(p_flag text, p_level text, p_en text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, 'CRM', (select min(id) from public.locations), (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, null, jsonb_build_object('bn', p_en, 'en', p_en));
end $$;

-- ---------- the review list ----------
create or replace function public._crmb_dup_candidates(p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sim boolean; ok boolean; lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0); q text; extra text := ''; res jsonb;
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then return jsonb_build_object('off', true, 'rows', '[]'::jsonb, 'total', 0); end if;
  sim := public.rule_on('crm_dup_similar_names_on');
  ok := public._crmb_contact_ok();
  -- the second-phone table of the profile package, when it is installed
  if to_regclass('public.customer_phones') is not null
     and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'customer_phones' and column_name in ('customer_id', 'phone', 'active')) = 3 then
    extra := 'union select customer_id, public._crmb_norm_phone(phone) from public.customer_phones where coalesce(active, true)';
  end if;
  q := $q$
  with cust as (
    select c.id, c.name, c.active, c.mobile, c.birthday, public._crmb_norm_name(c.name) nn,
           regexp_replace(lower(btrim(coalesce(c.address, ''))), '[\s\.\,\-_''"()/]+', '', 'g') na,
           coalesce((select l.primary_id from public.crm_customer_links l where l.linked_id = c.id and l.undone_at is null), c.id) root
      from public.customers c),
  dk as (   -- one-letter-apart names share a key: the name itself, or the name with one letter taken out (so no all-pairs comparison)
    select c.id, c.nn, c.nn k from cust c where @SIM@ and length(c.nn) >= 4
    union all
    select c.id, c.nn, left(c.nn, i - 1) || substr(c.nn, i + 1) from cust c, generate_series(1, 200) i where @SIM@ and length(c.nn) >= 4 and i <= length(c.nn)),
  pk as (select id, ph from (
           select id, public._crmb_norm_phone(mobile) ph from public.customers
           union select id, public._crmb_norm_phone(whatsapp) from public.customers
           @EXTRA@) z where ph is not null),
  pairs as (
    select a.id aid, b.id bid, 'same_phone'::text reason from pk a join pk b on a.ph = b.ph and a.id < b.id
    union
    select a.id, b.id, 'same_name' from cust a join cust b on a.nn = b.nn and a.id < b.id
      where length(a.nn) >= 3 and a.nn in (select nn from cust where length(nn) >= 3 group by nn having count(*) between 2 and 10)
    union
    select a.id, b.id, 'similar_name' from dk a join dk b on a.k = b.k and a.id < b.id
      where @SIM@ and a.nn <> b.nn and abs(length(a.nn) - length(b.nn)) <= 1 and public._crmb_lev(a.nn, b.nn, 1) = 1),
  g as (
    select p.aid, p.bid, array_agg(distinct p.reason order by p.reason) reasons,
           (a.na <> '' and a.na = b.na) same_addr, (a.birthday is not null and a.birthday = b.birthday) same_bday, a.root ra, b.root rb
      from pairs p join cust a on a.id = p.aid join cust b on b.id = p.bid
     group by p.aid, p.bid, a.na, b.na, a.birthday, b.birthday, a.root, b.root),
  f as (
    select g.*, case when 'same_phone' = any(g.reasons) or ('same_name' = any(g.reasons) and (g.same_addr or g.same_bday)) then 'strong'
                     when 'same_name' = any(g.reasons) or g.same_addr or g.same_bday then 'possible' else 'weak' end strength
      from g
     where g.ra <> g.rb
       and not exists (select 1 from public.crm_dup_reviews r where r.a_id = g.aid and r.b_id = g.bid and r.undone_at is null)),
  pg as (select * from f order by case strength when 'strong' then 0 when 'possible' then 1 else 2 end, aid, bid limit @LIM@ offset @OFF@)
  select jsonb_build_object('off', false, 'total', (select count(*) from f), 'masked', not @OK@,
    'rows', coalesce(jsonb_agg(jsonb_build_object(
      'a_id', pg.aid, 'b_id', pg.bid, 'strength', pg.strength,
      'reasons', to_jsonb(pg.reasons || case when pg.same_addr then array['same_address'] else '{}'::text[] end || case when pg.same_bday then array['same_birthday'] else '{}'::text[] end),
      'a', jsonb_build_object('id', ca.id, 'name', ca.name, 'active', ca.active, 'mobile', case when @OK@ then ca.mobile else public._crmb_mask_phone(ca.mobile) end),
      'b', jsonb_build_object('id', cb.id, 'name', cb.name, 'active', cb.active, 'mobile', case when @OK@ then cb.mobile else public._crmb_mask_phone(cb.mobile) end))
      order by case pg.strength when 'strong' then 0 when 'possible' then 1 else 2 end, pg.aid, pg.bid), '[]'::jsonb))
    from pg join public.customers ca on ca.id = pg.aid join public.customers cb on cb.id = pg.bid
  $q$;
  q := replace(replace(replace(replace(replace(q, '@EXTRA@', extra), '@SIM@', sim::text), '@LIM@', lim::text), '@OFF@', off::text), '@OK@', ok::text);
  execute q into res;
  return res;
end $$;

-- "these two are not the same person" (p_not_duplicate true) or reopen the pair (false)
create or replace function public._crmb_dup_review(p_client uuid, p_a uuid, p_b uuid, p_not_duplicate boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a uuid := least(p_a, p_b); b uuid := greatest(p_a, p_b); ex public.crm_dup_reviews; n int;
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then raise exception 'module_off'; end if;
  if p_client is null or p_a is null or p_b is null or p_not_duplicate is null or p_reason is not null and length(p_reason) > 300 then raise exception 'bad_input'; end if;
  if p_a = p_b then raise exception 'self_link'; end if;
  if p_not_duplicate and coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if (select count(*) from public.customers where id in (p_a, p_b)) <> 2 then raise exception 'customer_not_found'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_dup_reviews where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'a_id', ex.a_id, 'b_id', ex.b_id, 'duplicate', true); end if;
  if p_not_duplicate then
    begin
      insert into public.crm_dup_reviews (client_id, a_id, b_id, reason, decided_by, decided_staff) values (p_client, a, b, nullif(btrim(p_reason), ''), auth.uid(), public._crmb_staff());
    exception when unique_violation then
      return jsonb_build_object('a_id', a, 'b_id', b, 'unchanged', true, 'duplicate', false);
    end;
    return jsonb_build_object('a_id', a, 'b_id', b, 'not_duplicate', true, 'unchanged', false, 'duplicate', false);
  end if;
  update public.crm_dup_reviews set undone_at = now(), undone_by = auth.uid() where a_id = a and b_id = b and undone_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('a_id', a, 'b_id', b, 'not_duplicate', false, 'unchanged', n = 0, 'duplicate', false);
end $$;

-- ---------- link / unlink ----------
create or replace function public._crmb_link_customers(p_client uuid, p_primary uuid, p_linked uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_customer_links; lid bigint; m record; moved int := 0;
begin
  if not public._crmb_merge_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_dup_check_on') then raise exception 'module_off'; end if;
  if p_client is null or p_primary is null or p_linked is null then raise exception 'bad_input'; end if;
  if p_primary = p_linked then raise exception 'self_link'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if length(p_reason) > 300 then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_customer_links where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'primary_id', ex.primary_id, 'linked_id', ex.linked_id, 'duplicate', true); end if;
  if (select count(*) from public.customers where id in (p_primary, p_linked)) <> 2 then raise exception 'customer_not_found'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crmb_link', 0));
  if exists (select 1 from public.crm_customer_links where linked_id = p_primary and undone_at is null) then raise exception 'primary_is_linked'; end if;
  if exists (select 1 from public.crm_customer_links where linked_id = p_linked and primary_id = p_primary and undone_at is null) then raise exception 'already_linked'; end if;
  if exists (select 1 from public.crm_customer_links where linked_id = p_linked and undone_at is null) then raise exception 'linked_elsewhere'; end if;
  -- the linked customer already has duplicates of its own: they move under the new primary (one group, one level)
  for m in select id, linked_id from public.crm_customer_links where primary_id = p_linked and undone_at is null order by id loop
    update public.crm_customer_links set undone_at = now(), undone_by = auth.uid(), undo_reason = 'regrouped under ' || p_primary::text where id = m.id;
    insert into public.crm_customer_links (primary_id, linked_id, reason, created_by, created_staff) values (p_primary, m.linked_id, left('regrouped: ' || btrim(p_reason), 300), auth.uid(), public._crmb_staff());
    moved := moved + 1;
  end loop;
  insert into public.crm_customer_links (client_id, primary_id, linked_id, reason, created_by, created_staff)
    values (p_client, p_primary, p_linked, btrim(p_reason), auth.uid(), public._crmb_staff()) returning id into lid;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'crm_link', 'crm_customer_links', lid::text, jsonb_build_object('primary', p_primary, 'linked', p_linked, 'reason', btrim(p_reason), 'regrouped', moved));
  perform public._crmb_exc('customers_linked', 'yellow', 'Two customers were linked as the same person (ledgers stay separate). Reason: ' || btrim(p_reason));
  return jsonb_build_object('id', lid, 'primary_id', p_primary, 'linked_id', p_linked, 'regrouped', moved, 'duplicate', false);
end $$;

create or replace function public._crmb_unlink_customers(p_client uuid, p_linked uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_customer_links;
begin
  if not public._crmb_merge_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_linked is null then raise exception 'bad_input'; end if;
  if coalesce(length(btrim(p_reason)), 0) < 3 then raise exception 'reason_required'; end if;
  if length(p_reason) > 300 then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into l from public.crm_customer_links where undo_client = p_client;
  if found then return jsonb_build_object('id', l.id, 'primary_id', l.primary_id, 'linked_id', l.linked_id, 'unlinked', true, 'duplicate', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('crmb_link', 0));
  select * into l from public.crm_customer_links where linked_id = p_linked and undone_at is null;
  if not found then raise exception 'not_linked'; end if;
  update public.crm_customer_links set undone_at = now(), undone_by = auth.uid(), undo_reason = btrim(p_reason), undo_client = p_client where id = l.id;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmb_staff(), 'crm_unlink', 'crm_customer_links', l.id::text, jsonb_build_object('primary', l.primary_id, 'linked', l.linked_id, 'reason', btrim(p_reason)));
  return jsonb_build_object('id', l.id, 'primary_id', l.primary_id, 'linked_id', l.linked_id, 'unlinked', true, 'duplicate', false);
end $$;

-- ---------- read side ----------
-- one person: every number in the group, ledgers kept apart, CRM figures added up (spend, orders, last purchase, points). Balances are listed per customer and never added.
create or replace function public._crmb_customer_group(p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare root uuid; ok boolean := public._crmb_contact_ok(); members jsonb; sp numeric := 0; ord int := 0; ls date; pt int := 0; m record; st record;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  root := public._crmb_group_root(p_customer);
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'mobile', case when ok then c.mobile else public._crmb_mask_phone(c.mobile) end, 'active', c.active,
           'is_primary', c.id = root, 'balance', public._cust_bal(c.id), 'linked_at', l.created_at, 'link_reason', l.reason) order by (c.id = root) desc, l.created_at, c.id), '[]'::jsonb)
    into members
    from public.customers c left join public.crm_customer_links l on l.linked_id = c.id and l.undone_at is null
   where c.id = root or c.id in (select linked_id from public._crmb_links_active() where primary_id = root);
  for m in select c.id from public.customers c where c.id = root or c.id in (select linked_id from public._crmb_links_active() where primary_id = root) loop
    select * into st from public._cust_stats43(m.id, true);
    sp := sp + coalesce(st.spend, 0); ord := ord + coalesce(st.orders, 0); ls := greatest(ls, st.last_sale);
    pt := pt + coalesce((select sum(delta) from public.customer_points_ledger where customer_id = m.id), 0)::int;
  end loop;
  return jsonb_build_object('customer_id', p_customer, 'root_id', root, 'is_primary', p_customer = root, 'in_group', jsonb_array_length(members) > 1, 'members', members,
    'combined', jsonb_build_object('spend', sp, 'orders', ord, 'last_sale', ls, 'points', pt), 'ledgers_separate', true,
    'note', 'Dues, payments and the books stay on each customer. Only spend, orders, last purchase and points are shown together.');
end $$;

create or replace function public._crmb_links_list(p_limit int default 100, p_include_undone boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean := public._crmb_contact_ok();
begin
  if not public._crmb_dup_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select l.id, l.primary_id, pc.name as primary_name, case when ok then pc.mobile else public._crmb_mask_phone(pc.mobile) end as primary_mobile,
           l.linked_id, lc.name as linked_name, case when ok then lc.mobile else public._crmb_mask_phone(lc.mobile) end as linked_mobile,
           l.reason, l.created_staff, l.created_at, l.undone_at, l.undo_reason
      from public.crm_customer_links l join public.customers pc on pc.id = l.primary_id join public.customers lc on lc.id = l.linked_id
     where p_include_undone or l.undone_at is null order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- privileges (only the functions of THIS file) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_links_guard', '_crmb_dup_ok', '_crmb_merge_ok', '_crmb_norm_name', '_crmb_norm_phone', '_crmb_lev', '_crmb_exc', '_crmb_dup_candidates',
              '_crmb_dup_review', '_crmb_link_customers', '_crmb_unlink_customers', '_crmb_customer_group', '_crmb_links_list']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_dup_candidates(int, int), public._crmb_dup_review(uuid, uuid, uuid, boolean, text), public._crmb_link_customers(uuid, uuid, uuid, text),
  public._crmb_unlink_customers(uuid, uuid, text), public._crmb_customer_group(uuid), public._crmb_links_list(int, boolean) to authenticated;

-- ===================== phase306.sql =====================
-- Phase 306 (package CRM-C, label 106) - CUSTOMER SCORES: one row of numbers per customer, RFM labels with the owner's own cut-offs, settings, rights.
-- Paste AFTER phase98 (it needs the customer module of phase 43, sale returns of phase 12 and the notify tables of phase 62). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created: everything here is new, every function starts _crmc_ / crmc_, every table starts crm_.
-- Nothing starts by itself: scores are worked out only when someone presses "Refresh scores" or when the owner switches the schedule ON (and sets the hours).
-- All new settings default to OFF or blank, so with the defaults the books, reports and screens behave exactly as before (proved by tests/sql/crmc_before_after.sh).
--
-- WHAT THIS FILE ADDS
--   1. Settings (rules, module crm): crm_segments_on (OFF), crm_rfm_recent_days / crm_rfm_frequency_min / crm_rfm_spend_min (blank), crm_winback_days (blank),
--      crm_metrics_batch (2000, a technical batch size), crm_metrics_schedule_on (OFF), crm_metrics_schedule_hours (blank), crm_segment_max_members (5000, technical),
--      crm_seg_export_on (OFF), crm_seg_export_max_rows (blank). Grants: crm_view, crm_contact_view, crm_export, crm_settings_edit (nobody holds them until the owner gives them).
--   2. crm_metrics: one row per active customer (last visit, orders, spend net of returns, due, points, outlets, top three items). A cache the owner can rebuild at any time.
--      Money figures are COPIED from sales / returns, never changed. r/f/m flags and the label are NOT stored: they are worked out when read (see _crmc_scored), so a changed
--      cut-off applies at once without a rebuild.
--   3. crmc_metrics_refresh(dry): on demand, capped per run (crm_metrics_batch), oldest first; crmc_metrics_status(); crmc_scheduled_run() for the notify job (OFF by default).
--   4. crmc_me(): what the caller may do (the screens only ask; the server decides every call).
--   5. _crmc_patch(): the exact-text patch helper used for the one optional hook in notify_scan (docs/integration/CRM-C.md), marker bosCRMC.
-- Privacy: the cache is closed to browsers (no table right, no policy). Lists show a mobile number masked unless the privacy guard of package B is OFF (or absent) or the caller
-- holds crm_contact_view. Package B is read through rules with a safe fallback: if B is not installed the guard counts as OFF (today's behaviour) and no DNC table is consulted.

do $g$ begin
  if to_regprocedure('public._cust_stats43(uuid,boolean)') is null or to_regprocedure('public._cust_mgr43()') is null then raise exception 'phase306 needs phase43 (customers) first'; end if;
  if to_regclass('public.sale_returns') is null or to_regclass('public.customer_points_ledger') is null or to_regclass('public.notify_optin') is null then
    raise exception 'phase306 needs phases 12, 43 and 62 first'; end if;
  if to_regprocedure('public._is_ops(text)') is null or to_regprocedure('public.has_grant(text,integer)') is null then raise exception 'phase306 needs phases 8 and 46 first'; end if;
end $g$;

create or replace function public._crmc_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). English text everywhere (owner rule). Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('crm_segments_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer lists: allow saving and freezing lists', 'Customer lists: allow saving and freezing lists', 'Customer lists: allow saving and freezing lists',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.',
  'OFF = you can look at a list and see how many customers it holds, but you cannot save or freeze one (today). ON = people with the right can save lists. Nothing is sent to anyone either way.', 3060),
 ('crm_rfm_recent_days', 'crm', 'number', null, 'days', null, 1, 3650,
  'Customer score: a customer counts as recent if they bought within this many days', 'Customer score: a customer counts as recent if they bought within this many days', 'Customer score: a customer counts as recent if they bought within this many days',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.',
  'Blank = the standard labels are used (the same cut-offs as the existing Customer value report). Set all three score numbers to use your own cut-offs.', 3061),
 ('crm_rfm_frequency_min', 'crm', 'number', null, 'orders', null, 1, 1000,
  'Customer score: a customer counts as frequent with at least this many orders in 12 months', 'Customer score: a customer counts as frequent with at least this many orders in 12 months', 'Customer score: a customer counts as frequent with at least this many orders in 12 months',
  'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 3062),
 ('crm_rfm_spend_min', 'crm', 'number', null, '৳', null, 1, 1000000000,
  'Customer score: a customer counts as a big spender with at least this much spent in 12 months', 'Customer score: a customer counts as a big spender with at least this much spent in 12 months', 'Customer score: a customer counts as a big spender with at least this much spent in 12 months',
  'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.',
  'Spend is net of returns. Blank = the standard labels are used. Set all three score numbers to use your own cut-offs.', 3063),
 ('crm_winback_days', 'crm', 'number', null, 'days', null, 1, 3650,
  'Lapsed customer: not seen for this many days', 'Lapsed customer: not seen for this many days', 'Lapsed customer: not seen for this many days',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.',
  'Blank = the lapsed list asks you to type the number of days each time. A number makes it the default for the lapsed list.', 3064),
 ('crm_metrics_batch', 'crm', 'number', '2000'::jsonb, 'customers', null, 100, 20000,
  'Most customers scored in one run', 'Most customers scored in one run', 'Most customers scored in one run',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.',
  'A technical batch size, not a business limit. A bigger shop just presses Refresh scores a few times. Oldest scores are done first.', 3065),
 ('crm_metrics_schedule_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Refresh customer scores by itself', 'Refresh customer scores by itself', 'Refresh customer scores by itself',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.',
  'OFF = scores are refreshed only when someone presses Refresh scores (today). ON = the 30-minute notify job refreshes them, but only as often as the hours below.', 3066),
 ('crm_metrics_schedule_hours', 'crm', 'number', null, 'hours', null, 1, 720,
  'Refresh customer scores by itself: at most once every this many hours', 'Refresh customer scores by itself: at most once every this many hours', 'Refresh customer scores by itself: at most once every this many hours',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.',
  'Blank = the scheduled refresh does nothing even if switched ON. A big shop is finished over several runs; each run stays inside the batch size above.', 3067),
 ('crm_segment_max_members', 'crm', 'number', '5000'::jsonb, 'customers', null, 100, 50000,
  'Largest list that can be frozen', 'Largest list that can be frozen', 'Largest list that can be frozen',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.',
  'A technical safety size. A list with more customers can still be looked at and counted, but it cannot be frozen until you narrow the rules or raise this number.', 3068),
 ('crm_seg_export_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer lists: allow export', 'Customer lists: allow export', 'Customer lists: allow export',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.',
  'OFF = no list can be exported (today). ON = people with the Export right can download a list, with a reason, and every export is written to a log.', 3069),
 ('crm_seg_export_max_rows', 'crm', 'number', null, 'customers', null, 1, 50000,
  'Customer lists: most customers one export may hold', 'Customer lists: most customers one export may hold', 'Customer lists: most customers one export may hold',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.',
  'Blank = export stays blocked even if switched ON. A list bigger than this number is refused, never cut short silently.', 3070)
on conflict (key) do nothing;

-- Rights. Nobody holds them until the owner gives them (the owner always can). Other CRM packages seed the same codes with "where not exists", so the first paste wins.
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'master', v.s, v.l, v.l, v.l, 'once', null
  from (values ('crm_view', 3060, 'See customer lists, scores and customer notes'),
               ('crm_contact_view', 3061, 'See full phone numbers and addresses in customer lists'),
               ('crm_export', 3062, 'Export customer lists'),
               ('crm_settings_edit', 3063, 'Save customer lists and refresh customer scores')) v(c, s, l)
 where not exists (select 1 from public.grant_defs d where d.grant_code = v.c);

-- ============================================================================
-- 2. WHO MAY DO WHAT (internal; closed to browsers)
-- ============================================================================
create or replace function public._crmc_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._cust_mgr43() or public.has_grant('crm_view') or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_edit_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_run_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._cust_mgr43() or public.has_grant('crm_settings_edit'));
$$;
create or replace function public._crmc_export_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_export'));
$$;
-- package B's privacy guard, read through the rule only: a missing rule is OFF (phones show as they do today)
create or replace function public._crmc_guard_on() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_on('crm_pii_guard_on'), false);
$$;
create or replace function public._crmc_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_contact_view'));
$$;
create or replace function public._crmc_mobile_visible() returns boolean language sql stable security definer set search_path = public as $$
  select not public._crmc_guard_on() or public._crmc_contact_ok();
$$;
create or replace function public._crmc_mask(p_mobile text) returns text language sql stable security definer set search_path = public as $$
  select case when p_mobile is null then null
              when coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'hidden' then '****'
              when coalesce(public.rule_txt('crm_mask_style'), 'first3_last2') = 'last4' and length(p_mobile) > 4 then repeat('*', length(p_mobile) - 4) || right(p_mobile, 4)
              when length(p_mobile) >= 6 then left(p_mobile, 3) || repeat('*', length(p_mobile) - 5) || right(p_mobile, 2)
              else repeat('*', length(p_mobile)) end;
$$;
-- mobile as the caller may see it (never returns a full number to a masked caller)
create or replace function public._crmc_mobile_for_caller(p_mobile text) returns text language sql stable security definer set search_path = public as $$
  select case when public._crmc_mobile_visible() then p_mobile else public._crmc_mask(p_mobile) end;
$$;
create or replace function public._crmc_audit(p_action text, p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
create or replace function public._crmc_append_only() returns trigger language plpgsql as $$
begin raise exception 'crmc_append_only' using hint = 'This log is never edited or deleted'; end $$;

-- days from p_today to the next month/day of p_date (Feb 29 counts as Feb 28 in a year that has no Feb 29); null when p_date is null
create or replace function public._crmc_days_to_next(p_date date, p_today date) returns int language plpgsql immutable as $$
declare y int; m int := extract(month from p_date)::int; d int := extract(day from p_date)::int; c date;
begin
  if p_date is null or p_today is null then return null; end if;
  y := extract(year from p_today)::int;
  for i in 0 .. 1 loop
    c := make_date(y + i, m, case when m = 2 and d = 29 and not ((y + i) % 4 = 0 and ((y + i) % 100 <> 0 or (y + i) % 400 = 0)) then 28 else d end);
    if c >= p_today then return c - p_today; end if;
  end loop;
  return null;
end $$;

-- ============================================================================
-- 3. THE SCORE CACHE
-- ============================================================================
create table if not exists public.crm_metrics (
  customer_id uuid primary key references public.customers(id),
  first_visit date, last_visit date,
  orders_total int not null default 0,
  orders_12m int not null default 0,
  lifetime_spend numeric not null default 0,          -- net of returns, same rule as _cust_stats43
  spend_12m numeric not null default 0,               -- sales of the last 12 months minus returns of the last 12 months
  gross_spend numeric not null default 0,             -- before returns
  returns_total numeric not null default 0,
  avg_bill numeric,                                   -- gross spend / orders
  due_amount numeric not null default 0,              -- what the customer owes now (0 when nothing)
  points int not null default 0,
  top_location_id int,                                -- the outlet with most orders in the last 12 months
  outlet_ids int[] not null default '{}',             -- outlets used in the last 12 months
  top_items jsonb not null default '[]'::jsonb,       -- [{item_id,name,qty,amount}] three biggest items of the last 12 months
  computed_at timestamptz not null default now(),
  computed_on date not null default public._today43()
);
create index if not exists crm_metrics_last_visit on public.crm_metrics (last_visit);
create index if not exists crm_metrics_computed_on on public.crm_metrics (computed_on);
alter table public.crm_metrics enable row level security;
revoke all on public.crm_metrics from public, anon, authenticated;
drop trigger if exists crm_metrics_no_delete on public.crm_metrics;
create trigger crm_metrics_no_delete before delete on public.crm_metrics for each row execute function public.no_hard_delete();

create table if not exists public.crm_metrics_runs (
  id bigserial primary key,
  at timestamptz not null default now(),
  by_user uuid, kind text not null check (kind in ('manual', 'scheduled')),
  dry boolean not null default false,
  processed int not null default 0, remaining int not null default 0, batch int not null default 0
);
alter table public.crm_metrics_runs enable row level security;
revoke all on public.crm_metrics_runs from public, anon, authenticated;
drop trigger if exists crm_metrics_runs_ro on public.crm_metrics_runs;
create trigger crm_metrics_runs_ro before update or delete on public.crm_metrics_runs for each row execute function public._crmc_append_only();

-- the cut-offs in force: owner mode only when all three are set; otherwise the standard labels of the existing Customer value report
create or replace function public._crmc_cfg() returns table (rd numeric, fm numeric, sm numeric, mode text)
language sql stable security definer set search_path = public as $$
  select a, b, c, case when a is not null and b is not null and c is not null then 'owner' else 'standard' end
    from (select public.rule_num('crm_rfm_recent_days') a, public.rule_num('crm_rfm_frequency_min') b, public.rule_num('crm_rfm_spend_min') c) z;
$$;

-- the label of one customer. Owner mode: Champion, Loyal, Big spender, New, Recent, At risk, Drifting, Lost.
-- Standard mode (any cut-off blank) = exactly the labels of the Customer value report (m1_rfm): Champion (3+ orders, seen within 30 days), At-risk (2+ orders, not seen for over 60 days),
-- One-time (one order), Regular; plus Inactive (no order in 12 months). No order ever = No purchases.
create or replace function public._crmc_label(p_orders_total int, p_orders12 int, p_spend12 numeric, p_days int, p_rd numeric, p_fm numeric, p_sm numeric) returns text
language sql immutable as $$
  select case
    when coalesce(p_orders_total, 0) = 0 then 'No purchases'
    when p_rd is not null and p_fm is not null and p_sm is not null then
      case when p_days <= p_rd then
             case when p_orders12 >= p_fm and p_spend12 >= p_sm then 'Champion'
                  when p_orders12 >= p_fm then 'Loyal'
                  when p_spend12 >= p_sm then 'Big spender'
                  when p_orders_total = 1 then 'New'
                  else 'Recent' end
           else
             case when p_orders12 >= p_fm or p_spend12 >= p_sm then 'At risk'
                  when p_orders12 > 0 then 'Drifting'
                  else 'Lost' end end
    else
      case when p_orders12 = 0 then 'Inactive'
           when p_orders12 >= 3 and p_days <= 30 then 'Champion'
           when p_orders12 >= 2 and p_days > 60 then 'At-risk'
           when p_orders12 = 1 then 'One-time'
           else 'Regular' end end;
$$;

-- scores read live: one row per ACTIVE customer that has a cache row. Internal contract for the other CRM packages (campaigns, automation, dashboard).
create or replace function public._crmc_scored(p_today date default null)
returns table (customer_id uuid, days_since_last int, orders_total int, orders_12m int, spend_12m numeric, lifetime_spend numeric, due_amount numeric, points int,
               last_visit date, r_ok boolean, f_ok boolean, m_ok boolean, label text, mode text, computed_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_d date := coalesce(p_today, public._today43()); v_rd numeric; v_fm numeric; v_sm numeric; v_mode text;
begin
  select c.rd, c.fm, c.sm, c.mode into v_rd, v_fm, v_sm, v_mode from public._crmc_cfg() c;   -- cut-offs and today are read once, not once per customer
  return query
  select m.customer_id, case when m.last_visit is null then null else v_d - m.last_visit end, m.orders_total, m.orders_12m, m.spend_12m, m.lifetime_spend, m.due_amount, m.points, m.last_visit,
         case when v_mode = 'owner' and m.last_visit is not null then (v_d - m.last_visit) <= v_rd end,
         case when v_mode = 'owner' then m.orders_12m >= v_fm end,
         case when v_mode = 'owner' then m.spend_12m >= v_sm end,
         public._crmc_label(m.orders_total, m.orders_12m, m.spend_12m, case when m.last_visit is null then null else v_d - m.last_visit end, v_rd, v_fm, v_sm), v_mode, m.computed_at
    from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
end $$;

-- which customers need new scores: no row, computed on an earlier day, or a sale / return newer than the row (oldest first)
create or replace function public._crmc_stale(p_limit int default null) returns setof uuid language sql stable security definer set search_path = public as $$
  select c.id
    from public.customers c left join public.crm_metrics m on m.customer_id = c.id
   where c.active and (m.customer_id is null or m.computed_on < public._today43()
          or exists (select 1 from public.sales s where s.customer_id = c.id and s.sold_at > m.computed_at)
          or exists (select 1 from public.sale_returns r where r.customer_id = c.id and r.created_at > m.computed_at))
   order by m.computed_at nulls first, c.id
   limit coalesce(p_limit, 2147483647);
$$;

-- the worker. p_limit never exceeds crm_metrics_batch. No permission test here (the callers test).
create or replace function public._crmc_refresh_core(p_dry boolean, p_limit int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := public._today43(); cap int; ids uuid[]; v_n int := 0; total_stale int; rem int;
begin
  cap := least(greatest(coalesce(p_limit, 2147483647), 1), greatest(coalesce(public.rule_num('crm_metrics_batch'), 2000), 1))::int;
  select count(*) into total_stale from public._crmc_stale(null);
  if p_dry then
    return jsonb_build_object('dry', true, 'stale', total_stale, 'would_process', least(total_stale, cap), 'batch', cap);
  end if;
  if not pg_try_advisory_xact_lock(hashtext('crmc_refresh')) then return jsonb_build_object('busy', true); end if;
  select coalesce(array_agg(x), '{}') into ids from public._crmc_stale(cap) x;
  if cardinality(ids) > 0 then
    with s as (
      select x.customer_id cid, count(*)::int n, coalesce(sum(x.total), 0) amt, min(x.sale_date) fd, max(x.sale_date) ld,
             count(*) filter (where x.sale_date > today - 365)::int n12, coalesce(sum(x.total) filter (where x.sale_date > today - 365), 0) amt12
        from public.sales x where x.customer_id = any (ids) and x.status = 'done' group by 1),
    r as (
      select y.customer_id cid, coalesce(sum(y.amount), 0) amt,
             coalesce(sum(y.amount) filter (where (y.created_at at time zone 'Asia/Dhaka')::date > today - 365), 0) amt12
        from public.sale_returns y where y.customer_id = any (ids) and y.status = 'done' group by 1),
    lo as (
      select x.customer_id cid, x.location_id loc, count(*) n, max(x.sale_date) ld
        from public.sales x where x.customer_id = any (ids) and x.status = 'done' and x.sale_date > today - 365 group by 1, 2),
    tp as (select distinct on (cid) cid, loc from lo order by cid, n desc, ld desc, loc),
    oa as (select cid, array_agg(loc order by loc) locs from lo group by cid),
    it0 as (
      select x.customer_id cid, e ->> 'item_id' iid, max(e ->> 'name') nm,
             sum(case when e ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'qty')::numeric else 0 end) q,
             sum(case when e ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e ->> 'amount')::numeric else 0 end) a
        from public.sales x cross join lateral jsonb_array_elements(case when jsonb_typeof(x.lines) = 'array' then x.lines else '[]'::jsonb end) e
       where x.customer_id = any (ids) and x.status = 'done' and x.sale_date > today - 365 and (e ->> 'item_id') ~ '^[0-9a-f-]{36}$' group by 1, 2),
    it1 as (select it0.*, row_number() over (partition by cid order by a desc, iid) rn from it0),
    it as (select cid, jsonb_agg(jsonb_build_object('item_id', iid, 'name', nm, 'qty', q, 'amount', a) order by rn) arr from it1 where rn <= 3 group by cid)
    insert into public.crm_metrics as m (customer_id, first_visit, last_visit, orders_total, orders_12m, lifetime_spend, spend_12m, gross_spend, returns_total, avg_bill, due_amount, points,
                                         top_location_id, outlet_ids, top_items, computed_at, computed_on)
    select b.cid, s.fd, s.ld, coalesce(s.n, 0), coalesce(s.n12, 0), coalesce(s.amt, 0) - coalesce(r.amt, 0), coalesce(s.amt12, 0) - coalesce(r.amt12, 0), coalesce(s.amt, 0), coalesce(r.amt, 0),
           case when coalesce(s.n, 0) > 0 then round(s.amt / s.n, 2) end, greatest(public._cust_bal(b.cid), 0),
           coalesce((select sum(l.delta) from public.customer_points_ledger l where l.customer_id = b.cid), 0)::int,
           tp.loc, coalesce(oa.locs, '{}'), coalesce(it.arr, '[]'::jsonb), now(), today
      from (select unnest(ids) cid) b left join s on s.cid = b.cid left join r on r.cid = b.cid left join tp on tp.cid = b.cid left join oa on oa.cid = b.cid left join it on it.cid = b.cid
    on conflict (customer_id) do update set first_visit = excluded.first_visit, last_visit = excluded.last_visit, orders_total = excluded.orders_total, orders_12m = excluded.orders_12m,
       lifetime_spend = excluded.lifetime_spend, spend_12m = excluded.spend_12m, gross_spend = excluded.gross_spend, returns_total = excluded.returns_total, avg_bill = excluded.avg_bill,
       due_amount = excluded.due_amount, points = excluded.points, top_location_id = excluded.top_location_id, outlet_ids = excluded.outlet_ids, top_items = excluded.top_items,
       computed_at = excluded.computed_at, computed_on = excluded.computed_on;
    get diagnostics v_n = row_count;
  end if;
  select count(*) into rem from public._crmc_stale(null);
  return jsonb_build_object('dry', false, 'processed', v_n, 'remaining', rem, 'batch', cap);
end $$;

-- on demand
create or replace function public.crmc_metrics_refresh(p_dry boolean default false, p_limit int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if not public._crmc_run_ok() then raise exception 'not allowed'; end if;
  if p_limit is not null and (p_limit < 1 or p_limit > 20000) then raise exception 'bad_value'; end if;
  r := public._crmc_refresh_core(coalesce(p_dry, false), p_limit);
  if coalesce((r ->> 'busy')::boolean, false) then return r; end if;
  if not coalesce(p_dry, false) then
    insert into public.crm_metrics_runs (by_user, kind, dry, processed, remaining, batch) values (auth.uid(), 'manual', false, (r ->> 'processed')::int, (r ->> 'remaining')::int, (r ->> 'batch')::int);
    perform public._crmc_audit('crm_scores_refresh', 'crm_metrics', 'manual', r);
  end if;
  return r;
end $$;

-- for the 30-minute notify job (ops bot, purpose notify) or the owner. Does nothing unless the owner switched it ON and set the hours.
create or replace function public.crmc_scheduled_run() returns jsonb
language plpgsql security definer set search_path = public as $$
declare hrs numeric; last_run record; r jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_metrics_schedule_on') then return jsonb_build_object('off', true); end if;
  hrs := public.rule_num('crm_metrics_schedule_hours');
  if hrs is null then return jsonb_build_object('blocked', 'set_hours'); end if;
  select * into last_run from public.crm_metrics_runs where kind = 'scheduled' and not dry order by id desc limit 1;
  if found and last_run.remaining = 0 and last_run.at > now() - make_interval(secs => hrs * 3600) then return jsonb_build_object('skipped', 'not_due', 'last_run', last_run.at); end if;
  r := public._crmc_refresh_core(false, null);
  if coalesce((r ->> 'busy')::boolean, false) then return r; end if;
  insert into public.crm_metrics_runs (by_user, kind, dry, processed, remaining, batch) values (auth.uid(), 'scheduled', false, (r ->> 'processed')::int, (r ->> 'remaining')::int, (r ->> 'batch')::int);
  perform public._crmc_audit('crm_scores_refresh', 'crm_metrics', 'scheduled', r);
  return r;
end $$;

create or replace function public.crmc_metrics_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cfg record; tot int; scored int; stale int; lr record;
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  select * into cfg from public._crmc_cfg();
  select count(*) into tot from public.customers where active;
  select count(*) into scored from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
  select count(*) into stale from public._crmc_stale(null);
  select * into lr from public.crm_metrics_runs where not dry order by id desc limit 1;
  return jsonb_build_object('customers', tot, 'scored', scored, 'never_scored', tot - scored, 'stale', stale,
    'oldest', (select min(m.computed_at) from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active),
    'newest', (select max(m.computed_at) from public.crm_metrics m),
    'mode', cfg.mode, 'recent_days', cfg.rd, 'frequency_min', cfg.fm, 'spend_min', cfg.sm,
    'missing', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (select 'crm_rfm_recent_days' k where cfg.rd is null union all select 'crm_rfm_frequency_min' where cfg.fm is null union all select 'crm_rfm_spend_min' where cfg.sm is null) z),
    'batch', coalesce(public.rule_num('crm_metrics_batch'), 2000), 'schedule_on', public.rule_on('crm_metrics_schedule_on'), 'schedule_hours', public.rule_num('crm_metrics_schedule_hours'),
    'last_run', case when lr.id is null then null else jsonb_build_object('at', lr.at, 'kind', lr.kind, 'processed', lr.processed, 'remaining', lr.remaining) end,
    'winback_days', public.rule_num('crm_winback_days'));
end $$;

-- what the caller may do (for showing or hiding buttons; the server still decides every call)
create or replace function public.crmc_me() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('view', public._crmc_view_ok(), 'edit', public._crmc_edit_ok(), 'run', public._crmc_run_ok(), 'export', public._crmc_export_ok(),
    'contact', public._crmc_mobile_visible(), 'cost', coalesce(public.biz_cost_ok(), false), 'owner', public.is_owner(),
    'segments_on', public.rule_on('crm_segments_on'), 'export_on', public.rule_on('crm_seg_export_on'), 'export_max', public.rule_num('crm_seg_export_max_rows'),
    'guard_on', public._crmc_guard_on());
$$;

-- exact-text patch helper for the one optional hook (docs/integration/CRM-C.md). Same contract as the earlier packages: marker, unique site, nothing half done.
create or replace function public._crmc_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[A-Z]{3,6}$' then raise exception 'crmc_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'crmc_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'crmc_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'crmc_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ============================================================================
-- 4. RIGHTS ON THE FUNCTIONS: internal helpers are closed to browsers, the screens' functions are open to signed-in users (each one tests the caller itself)
-- ============================================================================
revoke all on function public._crmc_present(), public._crmc_view_ok(), public._crmc_edit_ok(), public._crmc_run_ok(), public._crmc_export_ok(), public._crmc_guard_on(), public._crmc_contact_ok(),
  public._crmc_mobile_visible(), public._crmc_mask(text), public._crmc_mobile_for_caller(text), public._crmc_audit(text, text, text, jsonb), public._crmc_append_only(), public._crmc_days_to_next(date, date),
  public._crmc_cfg(), public._crmc_label(int, int, numeric, int, numeric, numeric, numeric), public._crmc_scored(date), public._crmc_stale(int), public._crmc_refresh_core(boolean, int),
  public._crmc_patch(regprocedure, text[], text) from public, anon, authenticated;
revoke all on function public.crmc_metrics_refresh(boolean, int), public.crmc_scheduled_run(), public.crmc_metrics_status(), public.crmc_me() from public, anon;
grant execute on function public.crmc_metrics_refresh(boolean, int), public.crmc_scheduled_run(), public.crmc_metrics_status(), public.crmc_me() to authenticated;

-- ===================== phase307.sql =====================
-- Phase 307 (package CRM-C, label 107) - CUSTOMER LISTS (SEGMENTS): a safe rule builder over a fixed list of fields, size preview, saved lists, frozen lists.
-- Paste AFTER phase306. Paste-twice safe. Nothing existing is edited or re-created. Names start crm_ / crmc_ / _crmc_.
--
-- SAFE BY CONSTRUCTION: a rule is data, never SQL text. It is checked field by field against a fixed catalog (_crmc_catalog): unknown field, operator not allowed for that field,
-- unknown key, wrong value type, value out of range, more than 8 conditions, a list longer than allowed - all refused with bad_rule:<reason>. The checked rule is then evaluated by
-- fixed, written-out queries (one branch per field) that receive the values as parameters. There is no dynamic SQL and no string is ever pasted into a query.
--
-- WHAT THIS FILE ADDS
--   crm_segments, crm_segment_members   saved rule lists ("dynamic": worked out when used) and frozen lists ("list": the customers are copied once and never change).
--   crmc_field_catalog / crmc_item_search      what the screen offers in its pickers.
--   crmc_preview(rule | list)                  how many customers, split by label, total spend. Reads only. Allowed while crm_segments_on is OFF.
--   crmc_members(rule | list, limit, offset)   one page of customers (mobile masked for callers who may not see it). Reads only.
--   crmc_segment_save / retire / freeze        need the right crm_settings_edit (or the owner) AND crm_segments_on. Idempotent by client id. Retire needs a reason.
--   _crmc_audience(segment, cap)               the contract for the campaign package: the customer ids of a list, active customers only.
-- Customers with no score row yet are never counted in a score-based condition (they are reported as "unscored" in the preview). Customer-table conditions (tier, type, birthday...) need no score.
-- Package B (consent / do-not-contact) is read with a safe fallback: if crm_contact_prefs does not exist nothing is excluded for it.

do $g$ begin
  if to_regprocedure('public._crmc_present()') is null then raise exception 'phase307 needs phase306 first'; end if;
end $g$;

-- ============================================================================
-- 1. TABLES
-- ============================================================================
create table if not exists public.crm_segments (
  id bigint generated by default as identity primary key,
  client_id uuid unique,
  name text not null check (length(btrim(name)) between 1 and 60),
  kind text not null default 'dynamic' check (kind in ('dynamic', 'list')),
  rule jsonb,                                                 -- the checked rule (dynamic) or the rule it was frozen from (list)
  note text check (note is null or length(note) <= 200),
  active boolean not null default true,
  source_segment_id bigint references public.crm_segments(id),
  frozen_at timestamptz,
  member_count int,
  last_count int, last_count_at timestamptz,                  -- the size when it was saved or frozen
  retired_reason text,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  check (kind <> 'dynamic' or rule is not null)
);
create unique index if not exists crm_segments_name_uq on public.crm_segments (lower(btrim(name))) where active;
create table if not exists public.crm_segment_members (
  segment_id bigint not null references public.crm_segments(id),
  customer_id uuid not null references public.customers(id),
  added_at timestamptz not null default now(),
  primary key (segment_id, customer_id)
);
create index if not exists crm_segment_members_cust on public.crm_segment_members (customer_id);
alter table public.crm_segments enable row level security;
alter table public.crm_segment_members enable row level security;
revoke all on public.crm_segments, public.crm_segment_members from public, anon, authenticated;
drop trigger if exists audit_crm_segments on public.crm_segments;
create trigger audit_crm_segments after insert or update on public.crm_segments for each row execute function public.log_change('id');
drop trigger if exists crm_segments_no_delete on public.crm_segments;
create trigger crm_segments_no_delete before delete on public.crm_segments for each row execute function public.no_hard_delete();
drop trigger if exists crm_segment_members_ro on public.crm_segment_members;
create trigger crm_segment_members_ro before update or delete on public.crm_segment_members for each row execute function public._crmc_append_only();
-- a frozen list never changes: no member can be added to a segment once it has a frozen_at stamp except by the freeze itself (same transaction, stamp set first)

-- ============================================================================
-- 2. THE CATALOG (the only fields and operators a rule may use)
-- ============================================================================
create or replace function public._crmc_catalog() returns table (field text, kind text, ops text[], lo numeric, hi numeric, label text, unit text)
language sql immutable as $$
  select * from (values
    ('days_since_last',     'num',      array['eq','ne','gt','ge','lt','le','between'], 0::numeric,    36500::numeric, 'Days since last visit',            'days'),
    ('orders_total',        'num',      array['eq','ne','gt','ge','lt','le','between'], 0,             1000000,        'Orders, all time',                 'orders'),
    ('orders_12m',          'num',      array['eq','ne','gt','ge','lt','le','between'], 0,             1000000,        'Orders in the last 12 months',     'orders'),
    ('spend_total',         'num',      array['eq','ne','gt','ge','lt','le','between'], -1e12,         1e12,           'Total spent (net of returns)',     '৳'),
    ('spend_12m',           'num',      array['eq','ne','gt','ge','lt','le','between'], -1e12,         1e12,           'Spent in the last 12 months',      '৳'),
    ('avg_bill',            'num',      array['eq','ne','gt','ge','lt','le','between'], 0,             1e12,           'Average bill',                     '৳'),
    ('due_amount',          'num',      array['eq','ne','gt','ge','lt','le','between'], 0,             1e12,           'Amount owed now',                  '৳'),
    ('points',              'num',      array['eq','ne','gt','ge','lt','le','between'], -1e9,          1e9,            'Loyalty points',                   'points'),
    ('customer_age_days',   'num',      array['eq','ne','gt','ge','lt','le','between'], 0,             36500,          'Days since the customer joined',   'days'),
    ('birthday_month',      'num',      array['eq','ne'],                               1,             12,             'Birthday month (1 to 12)',         'month'),
    ('birthday_in_days',    'within',   array['le'],                                    0,             366,            'Birthday within the next days',    'days'),
    ('anniversary_in_days', 'within',   array['le'],                                    0,             366,            'Anniversary within the next days', 'days'),
    ('birthday_this_month', 'bool',     array['is'],                                    null,          null,           'Birthday is this month',           null),
    ('has_birthday',        'bool',     array['is'],                                    null,          null,           'Birthday is on file',              null),
    ('has_due',             'bool',     array['is'],                                    null,          null,           'Owes money now',                   null),
    ('opted_in',            'optin',    array['is'],                                    null,          null,           'Agreed to messages',               null),
    ('tier',                'set_text', array['in','not_in'],                           null,          null,           'Customer tier',                    null),
    ('type',                'set_text', array['in','not_in'],                           null,          null,           'Customer type (retail or wholesale)', null),
    ('type_code',           'set_text', array['in','not_in'],                           null,          null,           'Customer group',                   null),
    ('source',              'set_text', array['in','not_in'],                           null,          null,           'How they came to us',              null),
    ('rfm_label',           'set_text', array['in','not_in'],                           null,          null,           'Customer label (score)',           null),
    ('outlet',              'set_int',  array['in','not_in'],                           1,             1000000,        'Bought at outlet (last 12 months)', null),
    ('bought_item',         'items',    array['in'],                                    null,          null,           'Bought any of these items',        null),
    ('not_bought_item',     'items',    array['in'],                                    null,          null,           'Never bought any of these items',  null)
  ) v(field, kind, ops, lo, hi, label, unit);
$$;

create or replace function public._crmc_labels() returns text[] language sql immutable as $$
  select array['No purchases','Champion','Loyal','Big spender','New','Recent','At risk','Drifting','Lost','Inactive','At-risk','One-time','Regular'];
$$;

-- ============================================================================
-- 3. CHECK AND NORMALISE A RULE (raises bad_rule:<reason>)
-- ============================================================================
create or replace function public._crmc_rule_norm(p_rule jsonb) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  v_k text; v_match text; v_n int; v_cond jsonb; v_out jsonb := '[]'::jsonb; v_cat record; v_f text; v_op text; v_v jsonb; v_el jsonb; v_arr jsonb; v_x numeric; v_y numeric; v_s text; v_cnt int; v_new jsonb;
begin
  if p_rule is null or jsonb_typeof(p_rule) <> 'object' then raise exception 'bad_rule:not_an_object'; end if;
  if length(p_rule::text) > 20000 then raise exception 'bad_rule:too_big'; end if;
  for v_k in select jsonb_object_keys(p_rule) loop
    if v_k not in ('match', 'conditions') then raise exception 'bad_rule:unknown_key'; end if;
  end loop;
  if p_rule ? 'match' and jsonb_typeof(p_rule -> 'match') <> 'string' then raise exception 'bad_rule:bad_match'; end if;
  v_match := coalesce(p_rule ->> 'match', 'all');
  if v_match not in ('all', 'any') then raise exception 'bad_rule:bad_match'; end if;
  if jsonb_typeof(p_rule -> 'conditions') is distinct from 'array' then raise exception 'bad_rule:no_conditions'; end if;
  v_n := jsonb_array_length(p_rule -> 'conditions');
  if v_n = 0 then raise exception 'bad_rule:no_conditions'; end if;
  if v_n > 8 then raise exception 'bad_rule:too_many_conditions'; end if;
  for v_cond in select e from jsonb_array_elements(p_rule -> 'conditions') e loop
    if jsonb_typeof(v_cond) <> 'object' then raise exception 'bad_rule:bad_condition'; end if;
    for v_k in select jsonb_object_keys(v_cond) loop
      if v_k not in ('field', 'op', 'value', 'within_days', 'channel') then raise exception 'bad_rule:unknown_key'; end if;
    end loop;
    if jsonb_typeof(v_cond -> 'field') is distinct from 'string' or jsonb_typeof(v_cond -> 'op') is distinct from 'string' then raise exception 'bad_rule:bad_condition'; end if;
    v_f := v_cond ->> 'field'; v_op := v_cond ->> 'op'; v_v := v_cond -> 'value';
    select * into v_cat from public._crmc_catalog() where field = v_f;
    if not found then raise exception 'bad_rule:unknown_field'; end if;
    if not (v_op = any (v_cat.ops)) then raise exception 'bad_rule:bad_operator'; end if;
    if v_cond ? 'within_days' and v_cat.kind <> 'items' then raise exception 'bad_rule:unknown_key'; end if;
    if v_cond ? 'channel' and v_cat.kind <> 'optin' then raise exception 'bad_rule:unknown_key'; end if;
    v_new := jsonb_build_object('field', v_f, 'op', v_op);
    if v_cat.kind = 'num' or v_cat.kind = 'within' then
      if v_op = 'between' then
        if jsonb_typeof(v_v) is distinct from 'array' or jsonb_array_length(v_v) <> 2 or jsonb_typeof(v_v -> 0) <> 'number' or jsonb_typeof(v_v -> 1) <> 'number' then raise exception 'bad_rule:bad_value'; end if;
        v_x := (v_v ->> 0)::numeric; v_y := (v_v ->> 1)::numeric;
        if v_x > v_y or v_x < v_cat.lo or v_y > v_cat.hi then raise exception 'bad_rule:bad_value'; end if;
        v_new := v_new || jsonb_build_object('value', jsonb_build_array(v_x, v_y));
      else
        if jsonb_typeof(v_v) is distinct from 'number' then raise exception 'bad_rule:bad_value'; end if;
        v_x := (v_v #>> '{}')::numeric;
        if v_x < v_cat.lo or v_x > v_cat.hi then raise exception 'bad_rule:bad_value'; end if;
        if v_cat.kind = 'within' and v_x <> floor(v_x) then raise exception 'bad_rule:bad_value'; end if;
        v_new := v_new || jsonb_build_object('value', v_x);
      end if;
    elsif v_cat.kind = 'bool' then
      if jsonb_typeof(v_v) is distinct from 'boolean' then raise exception 'bad_rule:bad_value'; end if;
      v_new := v_new || jsonb_build_object('value', v_v);
    elsif v_cat.kind = 'optin' then
      if jsonb_typeof(v_v) is distinct from 'boolean' then raise exception 'bad_rule:bad_value'; end if;
      v_s := coalesce(v_cond ->> 'channel', 'any');
      if jsonb_typeof(coalesce(v_cond -> 'channel', '"any"'::jsonb)) <> 'string' or v_s not in ('any', 'sms', 'whatsapp') then raise exception 'bad_rule:bad_value'; end if;
      v_new := v_new || jsonb_build_object('value', v_v, 'channel', v_s);
    elsif v_cat.kind = 'set_text' then
      if jsonb_typeof(v_v) is distinct from 'array' then raise exception 'bad_rule:bad_value'; end if;
      v_cnt := jsonb_array_length(v_v);
      if v_cnt < 1 or v_cnt > 50 then raise exception 'bad_rule:bad_value'; end if;
      v_arr := '[]'::jsonb;
      for v_el in select e from jsonb_array_elements(v_v) e loop
        if jsonb_typeof(v_el) <> 'string' then raise exception 'bad_rule:bad_value'; end if;
        v_s := v_el #>> '{}';
        if v_f = 'rfm_label' then
          if not (v_s = any (public._crmc_labels())) then raise exception 'bad_rule:bad_value'; end if;
        elsif v_f = 'type' then
          v_s := lower(btrim(v_s));
          if v_s not in ('retail', 'wholesale') then raise exception 'bad_rule:bad_value'; end if;
        elsif v_f in ('tier', 'type_code') then
          v_s := lower(btrim(v_s));
          if v_s !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_rule:bad_value'; end if;
        else   -- source: free text, compared as lower case, never as a pattern
          v_s := lower(btrim(v_s));
          if length(v_s) < 1 or length(v_s) > 60 or v_s ~ '[\x01-\x1f]' then raise exception 'bad_rule:bad_value'; end if;
        end if;
        v_arr := v_arr || to_jsonb(v_s);
      end loop;
      v_new := v_new || jsonb_build_object('value', v_arr);
    elsif v_cat.kind = 'set_int' then
      if jsonb_typeof(v_v) is distinct from 'array' then raise exception 'bad_rule:bad_value'; end if;
      v_cnt := jsonb_array_length(v_v);
      if v_cnt < 1 or v_cnt > 50 then raise exception 'bad_rule:bad_value'; end if;
      v_arr := '[]'::jsonb;
      for v_el in select e from jsonb_array_elements(v_v) e loop
        if jsonb_typeof(v_el) <> 'number' then raise exception 'bad_rule:bad_value'; end if;
        v_x := (v_el #>> '{}')::numeric;
        if v_x <> floor(v_x) or v_x < v_cat.lo or v_x > v_cat.hi then raise exception 'bad_rule:bad_value'; end if;
        v_arr := v_arr || to_jsonb(v_x::int);
      end loop;
      v_new := v_new || jsonb_build_object('value', v_arr);
    elsif v_cat.kind = 'items' then
      if jsonb_typeof(v_v) is distinct from 'array' then raise exception 'bad_rule:bad_value'; end if;
      v_cnt := jsonb_array_length(v_v);
      if v_cnt < 1 or v_cnt > 10 then raise exception 'bad_rule:bad_value'; end if;
      v_arr := '[]'::jsonb;
      for v_el in select e from jsonb_array_elements(v_v) e loop
        if jsonb_typeof(v_el) <> 'string' then raise exception 'bad_rule:bad_value'; end if;
        v_s := lower(v_el #>> '{}');
        if v_s !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_rule:bad_value'; end if;
        v_arr := v_arr || to_jsonb(v_s);
      end loop;
      v_new := v_new || jsonb_build_object('value', v_arr);
      if v_cond ? 'within_days' then
        if jsonb_typeof(v_cond -> 'within_days') <> 'number' then raise exception 'bad_rule:bad_value'; end if;
        v_x := (v_cond ->> 'within_days')::numeric;
        if v_x <> floor(v_x) or v_x < 1 or v_x > 3650 then raise exception 'bad_rule:bad_value'; end if;
        v_new := v_new || jsonb_build_object('within_days', v_x::int);
      end if;
    end if;
    v_out := v_out || jsonb_build_array(v_new);
  end loop;
  return jsonb_build_object('match', v_match, 'conditions', v_out);
end $$;

-- ============================================================================
-- 4. EVALUATE ONE CONDITION (a checked one) -> the customer ids; one fixed branch per field kind, values only as parameters
-- ============================================================================
create or replace function public._crmc_cond_ids(p_cond jsonb, p_today date) returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare
  v_f text := p_cond ->> 'field'; v_op text := p_cond ->> 'op'; v_kind text; v_a numeric; v_b numeric; v_bool boolean; v_txt text[]; v_int int[]; v_ids uuid[] := '{}'; v_wd int; v_ch text; v_dnc uuid[];
begin
  select kind into v_kind from public._crmc_catalog() where field = v_f;
  if v_kind is null then raise exception 'bad_rule:unknown_field'; end if;

  if v_kind in ('num', 'within') then
    if v_op = 'between' then v_a := (p_cond -> 'value' ->> 0)::numeric; v_b := (p_cond -> 'value' ->> 1)::numeric; else v_a := (p_cond ->> 'value')::numeric; end if;
    select coalesce(array_agg(c.id), '{}') into v_ids
      from public.customers c left join public.crm_metrics m on m.customer_id = c.id
      cross join lateral (select case v_f
          when 'days_since_last'      then (p_today - m.last_visit)::numeric
          when 'orders_total'         then m.orders_total::numeric
          when 'orders_12m'           then m.orders_12m::numeric
          when 'spend_total'          then m.lifetime_spend
          when 'spend_12m'            then m.spend_12m
          when 'avg_bill'             then m.avg_bill
          when 'due_amount'           then m.due_amount
          when 'points'               then m.points::numeric
          when 'customer_age_days'    then (p_today - coalesce(c.customer_since, (c.created_at at time zone 'Asia/Dhaka')::date))::numeric
          when 'birthday_month'       then extract(month from c.birthday)::numeric
          when 'birthday_in_days'     then public._crmc_days_to_next(c.birthday, p_today)::numeric
          when 'anniversary_in_days'  then public._crmc_days_to_next(c.anniversary, p_today)::numeric
        end as v) z
     where c.active and z.v is not null and case v_op
          when 'eq' then z.v = v_a when 'ne' then z.v <> v_a when 'gt' then z.v > v_a when 'ge' then z.v >= v_a when 'lt' then z.v < v_a when 'le' then z.v <= v_a
          when 'between' then z.v between v_a and v_b else false end;

  elsif v_kind = 'bool' then
    v_bool := (p_cond ->> 'value')::boolean;
    if v_f = 'has_due' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c join public.crm_metrics m on m.customer_id = c.id where c.active and (m.due_amount > 0) = v_bool;
    elsif v_f = 'has_birthday' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c where c.active and (c.birthday is not null) = v_bool;
    else   -- birthday_this_month
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and coalesce(extract(month from c.birthday) = extract(month from p_today), false) = v_bool;
    end if;

  elsif v_kind = 'optin' then
    v_bool := (p_cond ->> 'value')::boolean; v_ch := coalesce(p_cond ->> 'channel', 'any');
    if v_bool then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and exists (select 1 from public.notify_optin n where n.customer_id = c.id and n.status = 'in' and (v_ch = 'any' or n.channel = v_ch));
    else
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and not exists (select 1 from public.notify_optin n where n.customer_id = c.id and n.status = 'in' and (v_ch = 'any' or n.channel = v_ch));
    end if;
    -- package B (do-not-contact) wins over any opt-in, when it is installed; a missing table or column means "nothing to exclude"
    if to_regclass('public.crm_contact_prefs') is not null then
      begin
        execute 'select coalesce(array_agg(customer_id), ''{}'') from public.crm_contact_prefs where dnc' into v_dnc;
        if v_bool then v_ids := array(select unnest(v_ids) except select unnest(v_dnc));
        else v_ids := array(select unnest(v_ids) union select x from unnest(v_dnc) x join public.customers cc on cc.id = x and cc.active);
        end if;
      exception when others then null;
      end;
    end if;

  elsif v_kind = 'set_text' then
    select coalesce(array_agg(x), '{}') into v_txt from jsonb_array_elements_text(p_cond -> 'value') x;
    if v_f = 'tier' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c left join public.customer_tiers t on t.id = c.tier_id
       where c.active and ((v_op = 'in' and coalesce(t.code, '') = any (v_txt)) or (v_op = 'not_in' and not (coalesce(t.code, '') = any (v_txt))));
    elsif v_f = 'type' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and ((v_op = 'in' and c.type = any (v_txt)) or (v_op = 'not_in' and not (c.type = any (v_txt))));
    elsif v_f = 'type_code' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and ((v_op = 'in' and coalesce(c.type_code, '') = any (v_txt)) or (v_op = 'not_in' and not (coalesce(c.type_code, '') = any (v_txt))));
    elsif v_f = 'source' then
      select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c
       where c.active and ((v_op = 'in' and lower(btrim(coalesce(c.source, ''))) = any (v_txt)) or (v_op = 'not_in' and not (lower(btrim(coalesce(c.source, ''))) = any (v_txt))));
    else   -- rfm_label (needs a score row)
      select coalesce(array_agg(s.customer_id), '{}') into v_ids from public._crmc_scored(p_today) s
       where (v_op = 'in' and s.label = any (v_txt)) or (v_op = 'not_in' and not (s.label = any (v_txt)));
    end if;

  elsif v_kind = 'set_int' then   -- outlet
    select coalesce(array_agg(x::int), '{}') into v_int from jsonb_array_elements_text(p_cond -> 'value') x;
    select coalesce(array_agg(c.id), '{}') into v_ids from public.customers c join public.crm_metrics m on m.customer_id = c.id
     where c.active and ((v_op = 'in' and m.outlet_ids && v_int) or (v_op = 'not_in' and not (m.outlet_ids && v_int)));

  elsif v_kind = 'items' then
    select coalesce(array_agg(x), '{}') into v_txt from jsonb_array_elements_text(p_cond -> 'value') x;
    v_wd := (p_cond ->> 'within_days')::int;
    select coalesce(array_agg(distinct s.customer_id), '{}') into v_ids
      from public.sales s
     where s.status = 'done' and s.customer_id is not null and (v_wd is null or s.sale_date > p_today - v_wd)
       and exists (select 1 from unnest(v_txt) it where s.lines @> jsonb_build_array(jsonb_build_object('item_id', it)));
    v_ids := array(select c.id from public.customers c where c.active and c.id = any (v_ids));
    if v_f = 'not_bought_item' then
      v_ids := array(select c.id from public.customers c where c.active and not (c.id = any (v_ids)));
    end if;
  end if;
  return v_ids;
end $$;

-- the whole rule: conditions combined with all (and) or any (or). Takes any rule, checks it first.
create or replace function public._crmc_eval(p_rule jsonb, p_today date default null) returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare v_r jsonb := public._crmc_rule_norm(p_rule); v_today date := coalesce(p_today, public._today43()); v_acc uuid[]; v_ids uuid[]; v_cond jsonb; v_all boolean := (v_r ->> 'match') = 'all';
begin
  for v_cond in select e from jsonb_array_elements(v_r -> 'conditions') e loop
    v_ids := public._crmc_cond_ids(v_cond, v_today);
    if v_acc is null then v_acc := v_ids;
    elsif v_all then v_acc := array(select unnest(v_acc) intersect select unnest(v_ids));
    else v_acc := array(select unnest(v_acc) union select unnest(v_ids));
    end if;
    exit when v_all and cardinality(v_acc) = 0;
  end loop;
  return coalesce(v_acc, '{}');
end $$;

-- the ids of a saved segment (active customers only): a frozen list returns its copied members, a rule list works the rule out now
create or replace function public._crmc_ids_of(p_segment bigint, p_rule jsonb) returns uuid[]
language plpgsql stable security definer set search_path = public as $$
declare s record;
begin
  if p_segment is not null then
    select * into s from public.crm_segments where id = p_segment;
    if not found then raise exception 'not found'; end if;
    if s.kind = 'list' then return coalesce((select array_agg(m.customer_id) from public.crm_segment_members m join public.customers c on c.id = m.customer_id and c.active where m.segment_id = s.id), '{}'); end if;
    return public._crmc_eval(s.rule);
  end if;
  return public._crmc_eval(p_rule);
end $$;

-- contract for the campaign package: the customers of a list. Closed to browsers; the caller (a server function of that package) does its own permission test.
create or replace function public._crmc_audience(p_segment bigint, p_cap int default null) returns table (customer_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[];
begin
  if not exists (select 1 from public.crm_segments where id = p_segment and active) then raise exception 'not found'; end if;
  v_ids := public._crmc_ids_of(p_segment, null);
  if p_cap is not null and cardinality(v_ids) > p_cap then raise exception 'over_cap:%', cardinality(v_ids); end if;
  return query select unnest(v_ids);
end $$;

-- ============================================================================
-- 5. PICKERS
-- ============================================================================
create or replace function public.crmc_field_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'fields', (select jsonb_agg(jsonb_build_object('field', field, 'kind', kind, 'ops', ops, 'lo', lo, 'hi', hi, 'label', label, 'unit', unit) order by ord)
                 from (select cat.*, row_number() over () ord from public._crmc_catalog() cat) q),
    'tiers', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name_en) order by rank), '[]'::jsonb) from public.customer_tiers where active),
    'types', jsonb_build_array(jsonb_build_object('code', 'retail', 'name', 'Retail'), jsonb_build_object('code', 'wholesale', 'name', 'Wholesale')),
    'groups', (select coalesce(jsonb_agg(jsonb_build_object('code', value_code, 'name', coalesce(label_en, label_bn)) order by sort, value_code), '[]'::jsonb) from public.option_lists where list_code = 'customer_types' and active),
    'outlets', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', coalesce(name_en, name_bn)) order by sort, id), '[]'::jsonb) from public.locations where is_active),
    'labels', to_jsonb(public._crmc_labels()),
    'channels', jsonb_build_array('any', 'sms', 'whatsapp'));
exception when undefined_table or undefined_column then
  -- the customer groups list differs in this database: send the rest
  return jsonb_build_object('fields', (select jsonb_agg(jsonb_build_object('field', field, 'kind', kind, 'ops', ops, 'lo', lo, 'hi', hi, 'label', label, 'unit', unit)) from public._crmc_catalog()),
    'tiers', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name_en) order by rank), '[]'::jsonb) from public.customer_tiers where active),
    'types', jsonb_build_array(jsonb_build_object('code', 'retail', 'name', 'Retail'), jsonb_build_object('code', 'wholesale', 'name', 'Wholesale')), 'groups', '[]'::jsonb,
    'outlets', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', coalesce(name_en, name_bn)) order by sort, id), '[]'::jsonb) from public.locations where is_active),
    'labels', to_jsonb(public._crmc_labels()), 'channels', jsonb_build_array('any', 'sms', 'whatsapp'));
end $$;

-- find items by a word (no pattern characters are interpreted: the word is matched as plain text)
create or replace function public.crmc_item_search(p_q text, p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_q text := lower(btrim(coalesce(p_q, '')));
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if length(v_q) < 2 then return '[]'::jsonb; end if;
  if length(v_q) > 60 then raise exception 'bad_value'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'code', code, 'name', coalesce(name_en, name_bn)) order by coalesce(name_en, name_bn))
                     from (select i.id, i.code, i.name_en, i.name_bn from public.items i
                            where i.is_active and (position(v_q in lower(coalesce(i.name_en, ''))) > 0 or position(v_q in lower(i.name_bn)) > 0 or position(v_q in lower(i.code)) > 0)
                            order by coalesce(i.name_en, i.name_bn) limit least(greatest(coalesce(p_limit, 20), 1), 50)) z), '[]'::jsonb);
end $$;

-- ============================================================================
-- 5b. SHARED PAGE BUILDER (one page of customers for a list of ids; sort is chosen from a fixed set, never pasted into SQL)
-- ============================================================================
create or replace function public._crmc_page(p_ids uuid[], p_sort text, p_limit int, p_offset int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_rows jsonb; v_sort text := coalesce(p_sort, 'lifetime');
        v_today date := public._today43(); v_vis boolean := public._crmc_mobile_visible(); v_rd numeric; v_fm numeric; v_sm numeric;
begin
  if v_sort not in ('lifetime', 'last12m', 'orders', 'avg_bill', 'silent_longest', 'silent_shortest', 'due') then raise exception 'bad_value'; end if;
  select g.rd, g.fm, g.sm into v_rd, v_fm, v_sm from public._crmc_cfg() g;
  -- step 1: pick the page (only ids and an order number); step 2: build the answer for those few rows only
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', c.id, 'name', c.name, 'mobile', case when v_vis then c.mobile else public._crmc_mask(c.mobile) end, 'tier', t.code, 'type', c.type,
             'last_visit', m.last_visit, 'days_since_last', case when m.last_visit is null then null else v_today - m.last_visit end,
             'orders_total', m.orders_total, 'orders_12m', m.orders_12m, 'spend_12m', m.spend_12m, 'lifetime_spend', m.lifetime_spend, 'avg_bill', m.avg_bill,
             'due_amount', m.due_amount, 'scored', m.customer_id is not null,
             'label', case when m.customer_id is null then null else public._crmc_label(m.orders_total, m.orders_12m, m.spend_12m, case when m.last_visit is null then null else v_today - m.last_visit end, v_rd, v_fm, v_sm) end,
             'top_items', coalesce(m.top_items, '[]'::jsonb)) order by pg.ord), '[]'::jsonb) into v_rows
    from (select z.id, row_number() over (order by
               case v_sort when 'lifetime' then zm.lifetime_spend when 'last12m' then zm.spend_12m when 'orders' then zm.orders_total::numeric when 'avg_bill' then zm.avg_bill
                           when 'due' then zm.due_amount when 'silent_longest' then (v_today - zm.last_visit)::numeric end desc nulls last,
               case v_sort when 'silent_shortest' then (v_today - zm.last_visit)::numeric end asc nulls last, z.name, z.id) ord
            from public.customers z left join public.crm_metrics zm on zm.customer_id = z.id where z.id = any (p_ids)
            order by 2 limit v_lim offset v_off) pg
    join public.customers c on c.id = pg.id left join public.crm_metrics m on m.customer_id = c.id left join public.customer_tiers t on t.id = c.tier_id;
  return jsonb_build_object('total', cardinality(p_ids), 'limit', v_lim, 'offset', v_off, 'masked', not v_vis, 'rows', v_rows);
end $$;

-- ============================================================================
-- 6. PREVIEW AND PAGES (read only; allowed while crm_segments_on is OFF)
-- ============================================================================
create or replace function public.crmc_preview(p_rule jsonb default null, p_segment bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ids uuid[]; v_cap int := coalesce(public.rule_num('crm_segment_max_members'), 5000)::int; v_by jsonb; v_sum record; v_tot int; v_scored int; v_kind text := 'dynamic';
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if (p_rule is null) = (p_segment is null) then raise exception 'bad_value'; end if;
  if p_segment is not null then select kind into v_kind from public.crm_segments where id = p_segment; end if;
  v_ids := public._crmc_ids_of(p_segment, p_rule);
  select count(*) into v_tot from public.customers where active;
  select count(*) into v_scored from public.crm_metrics m join public.customers c on c.id = m.customer_id and c.active;
  select coalesce(jsonb_object_agg(label, n), '{}'::jsonb) into v_by from (select s.label, count(*) n from public._crmc_scored() s where s.customer_id = any (v_ids) group by 1) z;
  select coalesce(sum(s.lifetime_spend), 0) ls, coalesce(sum(s.spend_12m), 0) s12, min(s.computed_at) oldest, count(*) n_scored into v_sum from public._crmc_scored() s where s.customer_id = any (v_ids);
  return jsonb_build_object('count', cardinality(v_ids), 'total_customers', v_tot, 'scored_customers', v_scored, 'unscored_customers', v_tot - v_scored,
    'members_scored', v_sum.n_scored, 'members_unscored', cardinality(v_ids) - v_sum.n_scored,
    'over_cap', cardinality(v_ids) > v_cap, 'cap', v_cap, 'by_label', v_by, 'lifetime_spend', v_sum.ls, 'spend_12m', v_sum.s12, 'oldest_score', v_sum.oldest, 'kind', v_kind);
end $$;

create or replace function public.crmc_members(p_rule jsonb default null, p_segment bigint default null, p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  if (p_rule is null) = (p_segment is null) then raise exception 'bad_value'; end if;
  return public._crmc_page(public._crmc_ids_of(p_segment, p_rule), 'lifetime', p_limit, p_offset);
end $$;

-- ============================================================================
-- 7. SAVE, RETIRE, FREEZE (need the right + crm_segments_on; idempotent by client id; logged by the audit trigger)
-- ============================================================================
create or replace function public._crmc_seg_json(s public.crm_segments) returns jsonb language sql stable as $$
  select jsonb_build_object('id', s.id, 'name', s.name, 'kind', s.kind, 'rule', s.rule, 'note', s.note, 'active', s.active, 'last_count', s.last_count, 'last_count_at', s.last_count_at,
    'member_count', s.member_count, 'frozen_at', s.frozen_at, 'source_segment_id', s.source_segment_id, 'created_at', s.created_at, 'retired_reason', s.retired_reason);
$$;

create or replace function public.crmc_segments_list(p_include_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmc_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(public._crmc_seg_json(s) order by s.active desc, s.name) from public.crm_segments s where s.active or coalesce(p_include_retired, false)), '[]'::jsonb);
end $$;

create or replace function public.crmc_segment_save(p_client uuid, p_id bigint, p_name text, p_rule jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(coalesce(p_name, '')); v_rule jsonb; s public.crm_segments; v_cnt int;
begin
  if not public._crmc_edit_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_segments_on') then raise exception 'segments_off'; end if;
  if length(v_name) < 1 or length(v_name) > 60 then raise exception 'bad_name'; end if;
  if p_note is not null and length(p_note) > 200 then raise exception 'bad_value'; end if;
  if p_client is not null then
    select * into s from public.crm_segments where client_id = p_client;
    if found then return public._crmc_seg_json(s) || jsonb_build_object('repeat', true); end if;
  end if;
  if p_id is null then
    v_rule := public._crmc_rule_norm(p_rule);
    v_cnt := cardinality(public._crmc_eval(v_rule));
    if exists (select 1 from public.crm_segments where active and lower(btrim(name)) = lower(v_name)) then raise exception 'name_taken'; end if;
    insert into public.crm_segments (client_id, name, kind, rule, note, last_count, last_count_at, created_by, updated_by)
      values (p_client, v_name, 'dynamic', v_rule, nullif(btrim(coalesce(p_note, '')), ''), v_cnt, now(), auth.uid(), auth.uid()) returning * into s;
  else
    select * into s from public.crm_segments where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    if not s.active then raise exception 'segment_retired'; end if;
    if exists (select 1 from public.crm_segments where active and id <> p_id and lower(btrim(name)) = lower(v_name)) then raise exception 'name_taken'; end if;
    if s.kind = 'list' then   -- a frozen list can only be renamed or get a note: its customers and its rule never change
      update public.crm_segments set name = v_name, note = nullif(btrim(coalesce(p_note, '')), ''), updated_by = auth.uid(), updated_at = now() where id = p_id returning * into s;
    else
      v_rule := public._crmc_rule_norm(p_rule);
      v_cnt := cardinality(public._crmc_eval(v_rule));
      update public.crm_segments set name = v_name, rule = v_rule, note = nullif(btrim(coalesce(p_note, '')), ''), last_count = v_cnt, last_count_at = now(), updated_by = auth.uid(), updated_at = now()
       where id = p_id returning * into s;
    end if;
  end if;
  return public._crmc_seg_json(s);
end $$;

create or replace function public.crmc_segment_retire(p_id bigint, p_active boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.crm_segments;
begin
  if not public._crmc_edit_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_segments_on') then raise exception 'segments_off'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  select * into s from public.crm_segments where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p_active and exists (select 1 from public.crm_segments where active and id <> p_id and lower(btrim(name)) = lower(btrim(s.name))) then raise exception 'name_taken'; end if;
  update public.crm_segments set active = p_active, retired_reason = case when p_active then null else btrim(p_reason) end, updated_by = auth.uid(), updated_at = now() where id = p_id returning * into s;
  return public._crmc_seg_json(s);
end $$;

-- freeze: copy today's customers of a saved list or of a rule into a new "list" segment. Empty lists and lists over the cap are refused (nothing is cut short).
create or replace function public.crmc_segment_freeze(p_client uuid, p_segment bigint, p_rule jsonb, p_name text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_name text := btrim(coalesce(p_name, '')); v_ids uuid[]; v_cap int := coalesce(public.rule_num('crm_segment_max_members'), 5000)::int; s public.crm_segments; v_rule jsonb;
begin
  if not public._crmc_edit_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_segments_on') then raise exception 'segments_off'; end if;
  if (p_segment is null) = (p_rule is null) then raise exception 'bad_value'; end if;
  if length(v_name) < 1 or length(v_name) > 60 then raise exception 'bad_name'; end if;
  if p_note is not null and length(p_note) > 200 then raise exception 'bad_value'; end if;
  if p_client is not null then
    select * into s from public.crm_segments where client_id = p_client;
    if found then return public._crmc_seg_json(s) || jsonb_build_object('repeat', true); end if;
  end if;
  if exists (select 1 from public.crm_segments where active and lower(btrim(name)) = lower(v_name)) then raise exception 'name_taken'; end if;
  if p_segment is not null then
    select rule into v_rule from public.crm_segments where id = p_segment;
    if not found then raise exception 'not found'; end if;
  else v_rule := public._crmc_rule_norm(p_rule); end if;
  v_ids := public._crmc_ids_of(p_segment, p_rule);
  if cardinality(v_ids) = 0 then raise exception 'empty_segment'; end if;
  if cardinality(v_ids) > v_cap then raise exception 'over_cap:%', cardinality(v_ids); end if;
  insert into public.crm_segments (client_id, name, kind, rule, note, source_segment_id, frozen_at, member_count, last_count, last_count_at, created_by, updated_by)
    values (p_client, v_name, 'list', v_rule, nullif(btrim(coalesce(p_note, '')), ''), p_segment, now(), cardinality(v_ids), cardinality(v_ids), now(), auth.uid(), auth.uid()) returning * into s;
  insert into public.crm_segment_members (segment_id, customer_id) select s.id, x from unnest(v_ids) x;
  return public._crmc_seg_json(s);
end $$;

-- ============================================================================
-- 8. RIGHTS
-- ============================================================================
revoke all on function public._crmc_page(uuid[], text, int, int), public._crmc_catalog(), public._crmc_labels(), public._crmc_rule_norm(jsonb), public._crmc_cond_ids(jsonb, date), public._crmc_eval(jsonb, date), public._crmc_ids_of(bigint, jsonb),
  public._crmc_audience(bigint, int), public._crmc_seg_json(public.crm_segments) from public, anon, authenticated;
revoke all on function public.crmc_field_catalog(), public.crmc_item_search(text, int), public.crmc_preview(jsonb, bigint), public.crmc_members(jsonb, bigint, int, int),
  public.crmc_segments_list(boolean), public.crmc_segment_save(uuid, bigint, text, jsonb, text), public.crmc_segment_retire(bigint, boolean, text),
  public.crmc_segment_freeze(uuid, bigint, jsonb, text, text) from public, anon;
grant execute on function public.crmc_field_catalog(), public.crmc_item_search(text, int), public.crmc_preview(jsonb, bigint), public.crmc_members(jsonb, bigint, int, int),
  public.crmc_segments_list(boolean), public.crmc_segment_save(uuid, bigint, text, jsonb, text), public.crmc_segment_retire(bigint, boolean, text),
  public.crmc_segment_freeze(uuid, bigint, jsonb, text, text) to authenticated;

