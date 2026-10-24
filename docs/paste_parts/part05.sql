-- ============================================================================
-- FRESH part 5 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71 phase72
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase50.sql
-- ============================================================
-- Phase 50 - P1 slice 3: payroll (gap #24) and expense (gap #28) - one record + locked shadow copy.
-- Run AFTER phase48 (phase49 is optional). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   PAYROLL  path A = app payroll (payroll_runs / payroll_payments), path B = form 02-2.  Same place + month (+ year) = same event.
--            Owner default: the app payroll is the record; the 02-2 sheet becomes a locked shadow (kept, shown, never counted in the day book).
--            Owner may switch the primary to the form, or "first one wins", or lock either path (Switch board, domain payroll).
--            A voided run releases its shadows: the forms count again.
--   EXPENSE  path A = quick expense typed in the day-book tab (quick_expenses), path B = form 10-2.
--            A quick entry counts at once (day book, journal, P&L). It gets a pending shadow; quick_expense_close_day() builds ONE draft 10-2 from the
--            day's unlinked quick entries (one click) and confirms the shadows. The 10-2 shadow is never counted again.
--   Guards   BEFORE INSERT triggers refuse a new record on a path the owner has locked (payroll_runs, entries of 02-2 / 10-2 / 04-2 / 03-1 / 04-3 / 05-1).
--   Lock     a shadow form that is submitted/approved cannot have its data changed or be re-opened.
--   Counting once: _daybook_lines, _daybook_skipped, _daybook_lines23, _acct_docs, _p27_pl, _r3q_e2_expense_trend are RE-CREATED from their latest definitions;
--            ONLY the blocks marked "bos50" differ.
-- ============================================================

-- ---------- 1. form -> domain map, guard for the form path ----------
create or replace function public._entry_domain(p_form text) returns text language sql immutable as $$
  select case p_form when '02-2' then 'payroll' when '10-2' then 'expense' when '04-2' then 'stock_issue' when '03-1' then 'stock_transfer' when '04-3' then 'stock_count' when '05-1' then 'production' end;
$$;

create or replace function public._entries_path_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text := public._entry_domain(new.form_code);
begin
  if d is not null and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard(d, new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_path_guard50 on public.entries;
create trigger entries_path_guard50 before insert on public.entries for each row execute function public._entries_path_guard50();

-- a shadow form that is submitted / approved is locked: no data change, no re-open
create or replace function public._entries_shadow_lock50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.status in ('submitted', 'approved') and (new.data is distinct from old.data or new.status = 'draft') and public.is_shadow('entries', old.id::text) then
    raise exception 'shadow_locked: this form is a locked copy of another record; it cannot be changed or re-opened';
  end if;
  return new;
end $$;
drop trigger if exists entries_shadow_lock50 on public.entries;
create trigger entries_shadow_lock50 before update on public.entries for each row execute function public._entries_shadow_lock50();

-- ---------- 2. PAYROLL: guard, link, release ----------
create or replace function public._payroll_run_guard50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.path_guard('payroll', coalesce(new.location_id, 0), 'a');
  return new;
end $$;
drop trigger if exists payroll_runs_path_guard50 on public.payroll_runs;
create trigger payroll_runs_path_guard50 before insert on public.payroll_runs for each row execute function public._payroll_run_guard50();

-- the month / year a 02-2 sheet is written for (null when it cannot be read)
create or replace function public._entry_pay_month50(p_data jsonb) returns date
language sql immutable as $$
  select case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end;
$$;

create or replace function public._payroll_pair50(p_run bigint, p_entry uuid, p_loc int, p_incoming_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  begin
    if public.path_winner('payroll', p_loc, p_incoming_path) = 'incoming' then
      -- the record that just arrived is the primary: the older one becomes its shadow
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy'); end if;
    else
      if p_incoming_path = 'a' then perform public.shadow_link_add('payroll', p_loc, 'entries', p_entry::text, 'payroll_runs', p_run::text, 'app payroll kept as a copy');
      else perform public.shadow_link_add('payroll', p_loc, 'payroll_runs', p_run::text, 'entries', p_entry::text, 'form 02-2 kept as a copy'); end if;
    end if;
  exception when others then
    if sqlerrm not like 'primary_is_already_a_shadow%' and sqlerrm not like 'shadow_is_already_a_primary%' then raise; end if;   -- an older decision already settled this pair
  end;
end $$;

create or replace function public._payroll_run_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'void' then return new; end if;
  for r in select e.id, e.location_id from public.entries e
            where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (new.location_id is null or e.location_id = new.location_id)
              and public._entry_pay_month50(e.data) = new.month loop
    perform public._payroll_pair50(new.id, r.id, r.location_id, 'a');
  end loop;
  return new;
end $$;
drop trigger if exists payroll_runs_link50 on public.payroll_runs;
create trigger payroll_runs_link50 after insert or update of status on public.payroll_runs for each row execute function public._payroll_run_link50();

create or replace function public._payroll_entry_link50() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record; m date := public._entry_pay_month50(new.data);
begin
  if m is null or new.form_code <> '02-2' or new.status not in ('submitted', 'approved') then return new; end if;
  for r in select pr.id from public.payroll_runs pr where pr.status <> 'void' and pr.month = m and (pr.location_id is null or pr.location_id = new.location_id) loop
    perform public._payroll_pair50(r.id, new.id, new.location_id, 'b');
  end loop;
  return new;
end $$;
drop trigger if exists entries_payroll_link50 on public.entries;
create trigger entries_payroll_link50 after insert or update of status on public.entries for each row when (new.form_code = '02-2') execute function public._payroll_entry_link50();

-- a voided run releases everything it held: the forms count again
create or replace function public._payroll_run_release50() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'released: payroll run voided', 300)
     where domain = 'payroll' and state <> 'void' and ((primary_type = 'payroll_runs' and primary_id = new.id::text) or (shadow_type = 'payroll_runs' and shadow_id = new.id::text));
  end if;
  return new;
end $$;
drop trigger if exists payroll_runs_release50 on public.payroll_runs;
create trigger payroll_runs_release50 after update of status on public.payroll_runs for each row execute function public._payroll_run_release50();

-- ---------- 3. EXPENSE: quick expense (path A) ----------
create table if not exists public.quick_expenses (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  exp_date date not null,
  head text not null check (head ~ '^[a-z0-9_]{2,30}$'),
  paid_to text check (paid_to is null or length(paid_to) <= 120),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  mode text not null default 'cash' check (mode in ('cash', 'bank', 'mobile')),
  receipt boolean not null default false,
  note text check (note is null or length(note) <= 300),
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create index if not exists quick_exp_day on public.quick_expenses (location_id, exp_date);
drop trigger if exists audit_quick_expenses on public.quick_expenses;
create trigger audit_quick_expenses after insert or update on public.quick_expenses for each row execute function public.log_change('id');
create or replace function public._quick_exp_ro50() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.status = 'done' and new.status = 'void' and (to_jsonb(new) - 'status' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'status' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: a quick expense cannot be changed or deleted (void it)';
end $$;
drop trigger if exists quick_exp_ro on public.quick_expenses;
create trigger quick_exp_ro before update or delete on public.quick_expenses for each row execute function public._quick_exp_ro50();
alter table public.quick_expenses enable row level security;
revoke all on public.quick_expenses from public, anon, authenticated;
grant select on public.quick_expenses to authenticated;
drop policy if exists quick_expenses_sel on public.quick_expenses;
create policy quick_expenses_sel on public.quick_expenses for select to authenticated using (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(location_id)));

create or replace function public.quick_expense_add(p_loc int, p_date date, p_head text, p_to text, p_amount numeric, p_mode text default 'cash', p_receipt boolean default false,
                                                    p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses; today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_client is not null then
    select * into q from public.quick_expenses where client_id = p_client;
    if found then
      if q.created_by <> auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('id', q.id, 'duplicate', true);
    end if;
  end if;
  perform public.path_guard('expense', p_loc, 'a');
  if p_amount is null or p_amount <= 0 then raise exception 'bad_amount'; end if;
  if nullif(btrim(p_head), '') is null then raise exception 'head_needed'; end if;
  if d > today or (d < today - 7 and not public.is_owner()) then raise exception 'bad_date'; end if;
  perform public.lock_check(d);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.quick_expenses (client_id, location_id, exp_date, head, paid_to, amount, mode, receipt, note, created_by, created_staff)
    values (p_client, p_loc, d, lower(btrim(p_head)), nullif(btrim(p_to), ''), p_amount, coalesce(p_mode, 'cash'), coalesce(p_receipt, false), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into q;
  -- the form copy is owed at day end: a pending shadow
  perform public.shadow_link_add('expense', p_loc, 'quick_expenses', q.id::text, 'entries', null, 'form 10-2 owed at day end');
  return jsonb_build_object('id', q.id);
end $$;

create or replace function public.quick_expense_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare q public.quick_expenses;
begin
  select * into q from public.quick_expenses where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (q.created_by = auth.uid() and q.exp_date = (now() at time zone 'Asia/Dhaka')::date and public.can_loc(q.location_id))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  if q.status = 'void' then return jsonb_build_object('id', q.id, 'noop', true); end if;
  perform public.lock_check(q.exp_date);
  if exists (select 1 from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed') then raise exception 'already_in_voucher: the day-end form was made; re-do it first'; end if;
  update public.quick_expenses set status = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = p_id;
  update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'quick expense voided', 300) where primary_type = 'quick_expenses' and primary_id = p_id::text and state = 'pending';
  return jsonb_build_object('id', q.id, 'status', 'void');
end $$;

-- what is typed today and what is still owed to the form
create or replace function public.quick_expense_day(p_loc int, p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or (public.can_do('10-2', 'view') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('location_id', p_loc, 'date', p_date,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'head', q.head, 'paid_to', q.paid_to, 'amount', q.amount, 'mode', q.mode, 'receipt', q.receipt, 'note', q.note, 'status', q.status,
        'form', (select l.shadow_id from public.shadow_links l where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'confirmed' limit 1)) order by q.created_at)
        from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date), '[]'::jsonb),
    'total', coalesce((select sum(q.amount) from public.quick_expenses q where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'), 0),
    'owed', (select count(*) from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
              where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done'));
end $$;

-- one click at day end: ONE draft 10-2 from the day's quick entries that are not yet in a form; the shadows are confirmed
create or replace function public.quick_expense_close_day(p_loc int, p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lines jsonb; n int; sv jsonb; eid uuid; r record;
begin
  if not (public.can_do('10-2', 'enter') and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('head', q.head, 'to', coalesce(q.paid_to, ''), 'receipt', case when q.receipt then 'yes' else 'no' end, 'amount', q.amount) order by q.created_at), '[]'::jsonb), count(*)
    into lines, n
    from public.quick_expenses q join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending'
   where q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  if n = 0 then return jsonb_build_object('made', 0, 'note', 'nothing owed'); end if;
  perform set_config('bos.shadow_create', '1', true);
  sv := public.save_entry(null, '10-2', p_loc, p_date, jsonb_build_object('lines', lines, 'from_quick', true), '[]'::jsonb, 'made from the day''s quick expenses', null);
  perform set_config('bos.shadow_create', '', true);
  eid := (sv->>'id')::uuid;
  update public.shadow_links l set state = 'confirmed', shadow_id = eid::text, confirmed_by = auth.uid(), confirmed_at = now()
    from public.quick_expenses q
   where l.primary_type = 'quick_expenses' and l.primary_id = q.id::text and l.state = 'pending' and q.location_id = p_loc and q.exp_date = p_date and q.status = 'done';
  return jsonb_build_object('made', n, 'entry_id', eid, 'serial', sv->'serial');
end $$;

revoke all on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) from public, anon;
grant execute on function public.quick_expense_add(int, date, text, text, numeric, text, boolean, text, uuid), public.quick_expense_void(uuid, text), public.quick_expense_day(int, date),
  public.quick_expense_close_day(int, date) to authenticated;
revoke all on function public._entry_domain(text), public._entries_path_guard50(), public._entries_shadow_lock50(), public._payroll_run_guard50(), public._entry_pay_month50(jsonb),
  public._payroll_pair50(bigint, uuid, int, text), public._payroll_run_link50(), public._payroll_entry_link50(), public._payroll_run_release50(), public._quick_exp_ro50() from public, anon, authenticated;

-- ============================================================
-- 4. COUNT ONCE: consumers re-created from their latest definitions. ONLY the lines marked bos50 differ.
-- ============================================================

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
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
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
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_skipped(p_locs integer[], p_sal integer[], p_from date, p_to date)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select (
    (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs) and e.entry_date between p_from and p_to
        and nullif(btrim(l ->> 'amount'), '') is not null and public._db_num(l -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
      where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(a ->> 'amount'), '') is not null and public._db_num(a -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(r ->> 'net'), '') is not null and public._db_num(r -> 'net') is null))::int;
$function$;

CREATE OR REPLACE FUNCTION public._daybook_lines23(p_locs integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) /* bos50 */ and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id))
  union all
  -- bos50: a quick expense typed in the day-book tab (its 10-2 copy is a locked shadow and is not counted again)
  select q.location_id, q.exp_date, 'out', q.mode, 'expense', q.amount, 'Q-' || left(q.id::text, 8), nullif(btrim(concat_ws(' · ', q.paid_to, q.head, q.note)), ''), q.created_staff, q.created_at,
         'quick_expense', q.id::text, false, false
    from public.quick_expenses q
   where q.status = 'done' and q.location_id = any (p_locs) and q.exp_date between p_from and p_to;
$function$;

CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
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
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
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
  select 'cash_move'::text, m.id::text, m.move_date, m.location_id, ('Cash move: ' || m.kind)::text, m.kind, m.status = 'done', (m.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when m.status = 'done' then case m.kind
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
  where m.move_date >= p_start and public._acct_need('cash_move', m.id::text, m.status = 'done');

  -- wastage at the real cost in the stock ledger
  return query
  select 'wastage'::text, w.id::text, (w.made_at at time zone 'Asia/Dhaka')::date, w.location_id, 'Wastage written off'::text, null::text, true, null::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when c.amt is null or c.amt <= 0 then 'cost_missing' end,
    case when c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'wastage', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');
end $function$;

CREATE OR REPLACE FUNCTION public._p27_pl(d1 date, d2 date, locs integer[])
 RETURNS TABLE(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select u.m, u.location_id, sum(u.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id, public._r2_num(ln -> 'amount') as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)) u group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$function$;

CREATE OR REPLACE FUNCTION public._r3q_e2_expense_trend(d1 date, d2 date, locs integer[], flt jsonb)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2
              union all  -- bos50: quick expenses
              select q.exp_date, coalesce(nullif(btrim(q.head), ''), '-'), q.amount from public.quick_expenses q
               where q.status = 'done' and q.location_id = any (locs) and q.exp_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase51.sql
-- ============================================================
-- Phase 51 - P1 slice 4: stock issue / transfer / count (gaps #25), production (#26), owner top-up / draw (#27).
-- Run AFTER phase50. Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   STOCK + PRODUCTION  path A = the stock screen / recipe run, path B = the paper form (04-2 issue, 03-1 transfer, 04-3 count, 05-1 factory sheet).
--       Rule "never both posting": exactly one of them posts to the stock ledger.
--       primary a (owner default): the screen / recipe run posts; an approved form is a reference - its lines are kept as "skipped: covered_by_screen",
--                                  nothing is posted twice.
--       primary b:                 the form posts (needs forms_post_to_ledger ON as before); the stock screen / recipe run cannot post the same action.
--       A path the owner has locked takes no new record.  Reversals / voids are never blocked.
--   OWNER MONEY  path A = partner capital (contribution / owner_drawing), path B = cash move (owner_topup / owner_draw).
--       Today only the cash move reaches the day book and the journal, partner capital is an equity sub-ledger, so nothing is counted twice now.
--       owner_money_link() joins the two records of one event (primary per the switch); the shadow is excluded from counting once partner capital
--       is auto-posted (P2, gap #6). Guards refuse a new record on a locked path.
--   Re-created from their latest definitions (only lines marked bos51 differ): entry_post_ledger, _elp_post_line.
-- ============================================================

-- ---------- 1. screen / recipe-run side: BEFORE INSERT guard on the stock ledger ----------
create or replace function public._stock_ledger_path_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text;
begin
  if new.reverses_id is not null or coalesce(current_setting('bos.form_post', true), '') = '1' then return new; end if;
  d := case when new.reason = 'issue_out' and new.ref_type = 'issue' then 'stock_issue'
            when new.reason = 'count_adjust' and new.ref_type = 'count' then 'stock_count'
            when new.reason = 'transfer_out' and new.ref_type = 'transfer' then 'stock_transfer'
            when new.reason = 'production_in' and new.ref_type = 'production' then 'production' end;
  if d is null then return new; end if;
  perform public.path_guard(d, new.location_id, 'a');
  if public.path_primary(d, new.location_id) = 'b' then
    raise exception 'path_locked: % - the paper form is the record here (owner switch), the screen cannot post this action', d;
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_path_guard51 on public.stock_ledger;
create trigger stock_ledger_path_guard51 before insert on public.stock_ledger for each row execute function public._stock_ledger_path_guard51();

-- ---------- 2. owner money: guards + the link ----------
create or replace function public._partner_capital_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('contribution', 'owner_drawing') then perform public.path_guard('owner_money', 0, 'a'); end if;
  return new;
end $$;
drop trigger if exists partner_capital_path_guard51 on public.partner_capital;
create trigger partner_capital_path_guard51 before insert on public.partner_capital for each row execute function public._partner_capital_guard51();

create or replace function public._cash_moves_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('owner_topup', 'owner_draw') then perform public.path_guard('owner_money', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists cash_moves_path_guard51 on public.cash_moves;
create trigger cash_moves_path_guard51 before insert on public.cash_moves for each row execute function public._cash_moves_guard51();

-- owner joins the two records of ONE event: contribution <-> owner_topup, owner_drawing <-> owner_draw (same amount). The primary follows the switch:
-- a = partner capital is the record (cash move = shadow), b = cash move is the record, first = the earlier record.
create or replace function public.owner_money_link(p_capital bigint, p_cash uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.partner_capital; m public.cash_moves; prim text; cash_first boolean; lk bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.partner_capital where id = p_capital;
  if not found or c.status <> 'posted' then raise exception 'capital_not_found'; end if;
  select * into m from public.cash_moves where id = p_cash;
  if not found or m.status <> 'done' then raise exception 'cash_move_not_found'; end if;
  if not ((c.kind = 'contribution' and m.kind = 'owner_topup') or (c.kind = 'owner_drawing' and m.kind = 'owner_draw')) then raise exception 'kind_mismatch'; end if;
  if c.amount <> m.amount then raise exception 'amount_mismatch'; end if;
  prim := public.path_primary('owner_money', m.location_id);
  if prim = 'first' then cash_first := m.created_at < c.created_at; else cash_first := (prim = 'b'); end if;
  if cash_first then lk := public.shadow_link_add('owner_money', m.location_id, 'cash_moves', m.id::text, 'partner_capital', c.id::text, coalesce(p_note, 'partner capital kept as a copy'));
  else lk := public.shadow_link_add('owner_money', m.location_id, 'partner_capital', c.id::text, 'cash_moves', m.id::text, coalesce(p_note, 'cash move kept as a copy')); end if;
  return jsonb_build_object('link', lk, 'primary', case when cash_first then 'cash_move' else 'partner_capital' end);
end $$;
revoke all on function public.owner_money_link(bigint, uuid, text) from public, anon;
grant execute on function public.owner_money_link(bigint, uuid, text) to authenticated;
revoke all on function public._stock_ledger_path_guard51(), public._partner_capital_guard51(), public._cash_moves_guard51() from public, anon, authenticated;

-- ---------- 3. form side: a form is a reference while the screen is primary ----------
CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
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
end $function$;

CREATE OR REPLACE FUNCTION public.entry_post_ledger(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  perform set_config('bos.form_post', '1', true);  -- bos51: rows posted by a form are not blocked by the screen guard
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
  perform set_config('bos.form_post', '', true);  -- bos51
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase52.sql
-- ============================================================
-- Phase 52 - P2 gap #6: journal auto-post SOURCES for payroll payments, staff advances and partner capital (+ owner-money count-once). Run AFTER phase51
-- (phase49 optional but its daybook_vs_journal is refreshed here). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   NEW SOURCES in the accounting scanner _acct_docs (posted by acct_post_pending exactly like every other source: unique on (source_type, source_id), voided
--   source -> reversing entry via _acct_need, locked period skipped, accounting_on / accounting_start_date as before):
--     payroll_payment  payroll_payments (status done). Dr salary expense (5200) [+ advance recovery], Cr cash / bank / mobile by mode. A run that is a locked
--                      shadow of a 02-2 sheet (owner chose the sheet as the record) posts nothing. The advance recovery on the pay line (payroll_lines.advance_recovery)
--                      is split over the payments pro rata and credited to Staff advances (1220): gross cost = paid + recovered.
--     staff_advance    employee_advances with mode cash / bank / mobile. Dr Staff advances (1220), Cr cash / bank / mobile. Mode none (money not moved here) posts nothing.
--     partner_capital  contribution Dr cash / Cr owner capital; return_of_capital Dr owner capital / Cr cash; loan_in Dr cash / Cr Partner loans (2500);
--                      loan_repayment Dr Partner loans / Cr cash; owner_drawing Dr owner drawings / Cr cash. In-kind = no money moved: shown as "waiting: in_kind".
--   OWNER MONEY COUNT ONCE (phase51 link): while partner capital is the record, the linked cash move (owner_topup / owner_draw) is a locked shadow and neither posts
--   to the journal (a copy posted earlier is reversed) nor shows in the day book; the partner-capital record takes its place (same place, same day, once).
--   An unlinked cash move keeps posting as today. If the primary record is voided the shadow counts again (nothing is lost).
--   NEW KEYS in acct_mappings (the owner re-points them in the accounts screen): salary_exp -> 5200, staff_advance -> 1220, partner_loan -> 2500 (new account, seeded).
--   daybook_vs_journal: kinds normalised (payroll payment = salary, staff advance = advance, partner capital = owner_topup / owner_draw / loan_in ...); the paper-form
--   salary (02-2) / advance (02-3) lines stay day-book-only and are reported as their own kinds salary_form / advance_form; partner capital without a place as unplaced_*.
--   NOT done: 10-1 cash handover / 10-3 digital payment items (the hub side of a handover is not recorded -> a one-sided entry would be a guess; see the report).
-- ============================================================

-- ---------- 1. chart + mappings ----------
do $seed$
declare code_ text;
begin
  -- Partner loans (liability). Take 2500 unless the owner already used that code for something else.
  if not exists (select 1 from public.coa_accounts where code = '2500' and is_system and name_en = 'Partner / owner loans') then
    code_ := case when exists (select 1 from public.coa_accounts where code = '2500') then '2510' else '2500' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select code_, 'অংশীদার / মালিকের কাছ থেকে ঋণ', 'Partner / owner loans', 'liability', 'credit', false, true, 105, (select id from public.coa_accounts where code = '2000')
       where not exists (select 1 from public.coa_accounts where code = code_);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('salary_exp', '5200', 'বেতন খরচ (পে-রোল পেমেন্ট)', 'Salary expense (payroll payments)'),
  ('staff_advance', '1220', 'স্টাফকে অগ্রিম (দেওয়া ও কাটা)', 'Staff advances (given and recovered)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_loan', a.id, 'অংশীদার / মালিকের ঋণ', 'Partner / owner loans'
  from public.coa_accounts a where a.is_system and a.name_en = 'Partner / owner loans' order by a.code limit 1
on conflict (key) do nothing;

-- ---------- 2. count-once helper: is this record a locked shadow whose primary record is still live? ----------
--   cash_moves  shadow of a partner_capital that is still posted;  partner_capital shadow of a cash move that is still done. (A voided primary releases the shadow.)
create or replace function public._shadowed52(p_type text, p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_shadow(p_type, p_id) and exists (
    select 1 from public.shadow_links x
     where x.shadow_type = p_type and x.shadow_id = p_id and x.state <> 'void'
       and case x.primary_type
             when 'partner_capital' then exists (select 1 from public.partner_capital c where c.id::text = x.primary_id and c.status = 'posted')
             when 'cash_moves' then exists (select 1 from public.cash_moves m where m.id::text = x.primary_id and m.status = 'done')
             else true end);
$$;
revoke all on function public._shadowed52(text, text) from public, anon, authenticated;

-- the source id of the CURRENT life of a record: a record that was reversed because it became a shadow (and is live again after its primary was voided) must be able to post
-- again, but journal_entries is unique on (source_type, source_id). Generation 0 = the plain id (all existing postings), generation n = id:gn.
create or replace function public._acct_sid52(p_type text, p_id text) returns text
language sql stable set search_path = public as $$
  select p_id || case when n = 0 then '' else ':g' || n::text end
    from (select count(*) n from public.journal_entries e where e.source_type = p_type and e.reverses_id is null and e.status = 'void'
                and (e.source_id = p_id or e.source_id like p_id || ':g%')) z;
$$;
revoke all on function public._acct_sid52(text, text) from public, anon, authenticated;

-- ---------- 3. _daybook_lines23 (latest definition, only bos52 lines differ) ----------
CREATE OR REPLACE FUNCTION public._daybook_lines23(p_locs integer[], p_from date, p_to date)
 RETURNS TABLE(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
 LANGUAGE sql
 STABLE
AS $function$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and not public._shadowed52('cash_moves', m.id::text) /* bos52 */ and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text) /* bos50 */ and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id))
  union all
  -- bos50: a quick expense typed in the day-book tab (its 10-2 copy is a locked shadow and is not counted again)
  select q.location_id, q.exp_date, 'out', q.mode, 'expense', q.amount, 'Q-' || left(q.id::text, 8), nullif(btrim(concat_ws(' · ', q.paid_to, q.head, q.note)), ''), q.created_staff, q.created_at,
         'quick_expense', q.id::text, false, false
    from public.quick_expenses q
   where q.status = 'done' and q.location_id = any (p_locs) and q.exp_date between p_from and p_to
  union all
  -- bos52: partner capital that is the record of a linked owner top-up / draw (the cash move is then a locked shadow and is not counted above); same place, same day, once
  select lk.location_id, c.cap_date, case c.kind when 'contribution' then 'in' else 'out' end, c.mode, case c.kind when 'contribution' then 'owner_topup' else 'owner_draw' end,
         c.amount, c.ref, nullif(btrim(concat_ws(' · ', 'partner capital', c.description)), ''), pr.staff_id, c.created_at, 'partner_capital', c.id::text, false, false
    from public.partner_capital c
    join lateral (select x.location_id from public.shadow_links x where x.primary_type = 'partner_capital' and x.primary_id = c.id::text and x.shadow_type = 'cash_moves'
                   and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true
    left join public.profiles pr on pr.id = c.created_by
   where c.status = 'posted' and c.kind in ('contribution', 'owner_drawing') and c.mode in ('cash', 'bank', 'mobile') and lk.location_id > 0
     and lk.location_id = any (p_locs) and c.cap_date between p_from and p_to;
$function$;

-- ---------- 4. _acct_docs (latest definition = phase50, bos50 blocks kept, only bos52 lines/blocks differ) ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when s.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'pay_' || p.mode, 'd', sum(p.amount)) j from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided group by p.mode
        union all select 2, jsonb_build_object('a', 'receivable', 'd', round(s.total - pp.paid, 2), 'pt', case when s.customer_id is not null then 'customer' end, 'pid', s.customer_id::text) where s.total - pp.paid > 0.004
        union all select 3, jsonb_build_object('a', 'sales_discount', 'd', s.discount) where s.discount > 0
        union all select 4, jsonb_build_object('a', 'sales', 'c', s.subtotal)
        union all select 5, jsonb_build_object('a', 'cogs', 'd', cg.amt) from (select round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null) cg where cg.amt > 0
        union all select 6, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt) from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_id = s.id::text and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out') and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) x) end
  from public.sales s cross join lateral (select coalesce(sum(p.amount), 0) paid from public.sale_payments p where p.sale_id = s.id and p.kind = 'sale' and not p.voided) pp
  where s.sale_date >= p_start and s.subtotal > 0 and public._acct_need('sale', s.id::text, s.status = 'done');

  -- sale returns
  return query
  select 'sale_return'::text, r.id::text, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, ('Return of receipt ' || coalesce(s.receipt::text, '-'))::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when r.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return'
                   and l.item_id = (e->>'item_id')::uuid and l.unit_cost is not null)) then 'cogs_missing' end,
    null::text,
    case when r.status = 'done' then (
      select coalesce(jsonb_agg(j order by o), '[]'::jsonb) from (
        select 1 o, jsonb_build_object('a', 'sales_returns', 'd', r.amount) j
        union all select 2, jsonb_build_object('a', 'receivable', 'c', r.credit_amount, 'pt', case when r.customer_id is not null then 'customer' end, 'pid', r.customer_id::text) where r.credit_amount > 0
        union all select 3, jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount) where r.refund_amount > 0
        union all select 4, jsonb_build_object('a', public._acct_inv_key(z.t), 'd', z.amt) from (select it.item_type t, round(sum(l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
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
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
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
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.stock_wastage w cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where l.unit_cost is null) nulls
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
end $function$;

-- ---------- 5. daybook_vs_journal: kind normalisation for the new sources (only bos52 lines differ from phase49) ----------
CREATE OR REPLACE FUNCTION public.daybook_vs_journal(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); d1 date; locs int[]; rows jsonb; tot jsonb; own boolean := public.is_owner();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'why', 'accounting_start_date'); end if;
  d1 := greatest(p_from, st);
  select array_agg(l.id) into locs from public.locations l where (p_loc is null or l.id = p_loc) and (own or public.can_loc(l.id));
  if locs is null then raise exception 'not allowed'; end if;
  with db as (  -- the day book, internal hub lines kept apart, signed per mode (card settles to bank in the day book)
    select case when u.typ in ('bill', 'supplier') then 'supplier_payment' when u.src = 'entry' and u.typ in ('salary', 'advance') then u.typ || '_form' /* bos52 */ else u.typ end as k, u.mode, u.internal, case when u.dir = 'in' then u.amount else -u.amount end as s
      from (select * from public._daybook_lines(locs, locs, d1, p_to) union all select * from public._daybook_lines12(locs, d1, p_to) union all select * from public._daybook_lines23(locs, d1, p_to)) u
  ), jr as (    -- the journal: movement on the cash / bank / mobile accounts, by kind (cash_move keeps its own kind)
    select case je.source_type when 'cash_move' then coalesce(je.subtype, 'cash_move') when 'expense_voucher' then 'expense' when 'quick_expense' then 'expense'
             when 'payroll_payment' then 'salary' when 'staff_advance' then 'advance' /* bos52 */
             when 'partner_capital' then case when coalesce(je.location_id, nullif(lk.loc, 0)) is null then 'unplaced_' || je.subtype else case je.subtype when 'contribution' then 'owner_topup' when 'owner_drawing' then 'owner_draw' else je.subtype end end /* bos52 */
             else je.source_type end as k,
           case when a.key = 'pay_cash' then 'cash' when a.key = 'pay_mobile' then 'mobile' else 'bank' end as mode, (jl.debit - jl.credit) as s
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      left join lateral (select x.location_id as loc from public.shadow_links x where je.source_type = 'partner_capital' and x.primary_type = 'partner_capital' and x.primary_id = split_part(je.source_id, ':', 1)
                          and x.shadow_type = 'cash_moves' and x.shadow_id is not null and x.state <> 'void' order by x.id limit 1) lk on true /* bos52: a link made after posting still gives the place */
      join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')
     where je.entry_date between d1 and p_to and je.source_type <> 'opening' and (coalesce(je.location_id, nullif(lk.loc, 0)) is null or coalesce(je.location_id, nullif(lk.loc, 0)) = any (locs))
  ), kk as (
    select k, mode, sum(s) filter (where not internal) as dbs, sum(s) filter (where internal) as dbi, 0::numeric as js from db group by k, mode
    union all select k, mode, null, null, sum(s) from jr group by k, mode
  ), agg as (
    select k, mode, coalesce(sum(dbs), 0) as daybook, coalesce(sum(dbi), 0) as hub_internal, coalesce(sum(js), 0) as journal from kk group by k, mode
  )
  select coalesce(jsonb_agg(jsonb_build_object('kind', k, 'mode', mode, 'daybook', daybook, 'journal', journal, 'diff', daybook - journal, 'hub_internal', hub_internal) order by k, mode)
           filter (where abs(daybook - journal) > 0.004 or hub_internal <> 0), '[]'::jsonb),
         jsonb_build_object('daybook', coalesce(sum(daybook), 0), 'journal', coalesce(sum(journal), 0), 'diff', coalesce(sum(daybook - journal), 0),
           'kinds_checked', count(*), 'kinds_differing', count(*) filter (where abs(daybook - journal) > 0.004))
    into rows, tot from agg;
  return jsonb_build_object('from', d1, 'to', p_to, 'location_id', p_loc, 'accounting_start', st, 'rows', rows, 'total', tot,
    'note', 'Day book counts a 10-2 voucher when submitted, the journal only when approved. Payroll payments (salary), staff advances (advance) and partner capital are posted from phase52; paper-form salary / advance lines (salary_form, advance_form) are day-book only; partner capital without a place shows as unplaced_*. Reversals post on the day they are made.');
end $function$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase53.sql
-- ============================================================
-- PHASE 53 (P2 gaps #1-#5 on top of phase40 accounting). Additive and idempotent (paste twice = no error). Needs phase8..phase28, phase40.
--   #1 Bank statement reconcile: bank_statement_lines (append-only) + bank_recon_matches (current state) + bank_recon_trail (append-only).
--      Owner / accounts_manage pastes statement lines (JSON rows, the browser turns CSV into rows); match to journal lines of the same bank/cash account
--      by amount + date window + reference; manual match / unmatch (reason) with a trail; unmatched report. NOTHING is auto-posted to the books.
--   #2 Year-end close: year_closes + ONE closing journal entry (income/expense -> retained earnings, per location), owner only, only after the period is
--      locked (rule period_closed_until >= year end), dry-run preview first, reversible by a reversing entry (phase40 _acct_reverse).
--   #3 VAT ledger: REPORT ONLY (vat_report). Uses the existing phase8 switches vat_on (OFF) + vat_rate (no default, owner enters). Output VAT from sales /
--      sale returns, input VAT from posted purchase bills / returns, only for items marked vat_applicable = true. Nothing is posted.
--   #4 Fixed-asset register fa_assets + straight-line schedule + monthly depreciation posting fa_depr_post (idempotent on (asset, month)).
--   #5 Budgets per account / month (/ location) with a change log, and the budget-vs-actual report.
-- Switches (rules, module books, ALL default OFF): bank_recon_on, year_close_on, fixed_assets_on, budgets_on, plus vat_prices_include (how the owner prices: ON = prices already include VAT).
-- Every write goes through a SECURITY DEFINER function (owner or accounts_manage; the year close is owner only). Tables are RLS read-only. Nothing is deleted.
-- ============================================================

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('bank_recon_on', 'books', 'switch', 'false', null, null, null, null, 'ব্যাংক স্টেটমেন্ট মিলানো চালু', 'Bank statement reconcile চালু', 'Bank statement reconcile on',
  'চালু হলে স্টেটমেন্টের লাইন পেস্ট করে খতিয়ানের সাথে মেলানো যায়। কিছু নিজে পোস্ট হয় না।', 'On = paste statement lines and match them to the books. Nothing is posted by itself.', 93),
 ('year_close_on', 'books', 'switch', 'false', null, null, null, null, 'বছর শেষের ক্লোজ চালু', 'Year-end close চালু', 'Year-end close on',
  'শুধু মালিক। আগে হিসাব-লক তারিখ বছর শেষ পর্যন্ত দিতে হবে। আগে প্রিভিউ, উল্টানো যায়।', 'Owner only. The books-closed date must reach the year end first. Preview first; it can be reversed.', 94),
 ('fixed_assets_on', 'books', 'switch', 'false', null, null, null, null, 'স্থায়ী সম্পদ ও অবচয় চালু', 'Fixed assets ও depreciation চালু', 'Fixed assets and depreciation on',
  'চালু হলে সম্পদ তালিকা ও মাসিক অবচয় পোস্ট করা যায়।', 'On = enter assets and post monthly depreciation.', 95),
 ('budgets_on', 'books', 'switch', 'false', null, null, null, null, 'বাজেট চালু', 'Budget চালু', 'Budgets on',
  'চালু হলে হিসাব/মাস ধরে বাজেট দেওয়া যায়; বাজেট বনাম আসল রিপোর্ট দেখা যায়।', 'On = set budgets per account and month; budget-vs-actual report.', 96),
 ('vat_prices_include', 'books', 'switch', 'true', null, null, null, null, 'দামে ভ্যাট ধরা আছে', 'Prices এ VAT ধরা আছে', 'Prices already include VAT',
  'চালু = বিক্রি/কেনার দামে ভ্যাট ভেতরেই আছে (হার থেকে ভাগ করে বের হয়)। বন্ধ = ভ্যাট দামের উপরে যোগ হয়। আপনার পরামর্শদাতার কাছে নিশ্চিত হয়ে নিন।', 'On = sale / purchase prices already contain VAT (it is extracted from the rate). Off = VAT is added on top. Confirm with your adviser.', 97)
 on conflict (key) do nothing;

-- mapping keys for depreciation and the closing entry (the owner can re-point them with acct_mapping_set)
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('depreciation', '5820', 'অবচয় খরচ', 'Depreciation expense'),
  ('accum_depr', '1590', 'সঞ্চিত অবচয়', 'Accumulated depreciation'),
  ('retained_close', '3900', 'বছর শেষের ক্লোজ: জমা মুনাফা', 'Year-end close: retained earnings')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.bank_statement_lines (
  id bigserial primary key,
  batch_id uuid not null,
  account_id bigint not null references public.coa_accounts(id),
  line_date date not null check (line_date >= date '2000-01-01'),
  amount numeric not null check (amount <> 0 and abs(amount) <= 1000000000000),      -- signed: + money in, - money out
  reference text check (reference is null or length(reference) <= 120),
  description text check (description is null or length(description) <= 300),
  balance numeric check (balance is null or abs(balance) <= 1000000000000),
  row_hash text not null,
  created_by uuid, created_at timestamptz not null default now(),
  unique (account_id, row_hash)
);
create index if not exists bsl_acc_date on public.bank_statement_lines (account_id, line_date);
create index if not exists bsl_batch on public.bank_statement_lines (batch_id);

create table if not exists public.bank_recon_matches (
  id bigserial primary key,
  line_id bigint not null references public.bank_statement_lines(id),
  entry_id bigint not null,
  line_no int not null,
  active boolean not null default true,
  how text not null default 'manual' check (how in ('manual', 'suggested')),
  note text,
  matched_by uuid, matched_at timestamptz not null default now(),
  unmatched_by uuid, unmatched_at timestamptz, unmatch_note text      -- (entry_id, line_no) is checked in _a53_match1; no FK so phase40's truncate guard on journal_lines stays the one that answers
);
create unique index if not exists brm_line_uq on public.bank_recon_matches (line_id) where active;
create unique index if not exists brm_jl_uq on public.bank_recon_matches (entry_id, line_no) where active;

create table if not exists public.bank_recon_trail (
  id bigserial primary key,
  line_id bigint not null references public.bank_statement_lines(id),
  action text not null check (action in ('match', 'unmatch')),
  entry_id bigint, line_no int,
  how text, note text,
  actor uuid, at timestamptz not null default now()
);

create table if not exists public.year_closes (
  id bigserial primary key,
  fiscal_from date not null, fiscal_to date not null check (fiscal_to >= fiscal_from),
  status text not null default 'closed' check (status in ('closed', 'reopened')),
  entry_id bigint references public.journal_entries(id),
  reversal_id bigint references public.journal_entries(id),
  income_total numeric not null default 0, expense_total numeric not null default 0, net_profit numeric not null default 0,
  note text, client_id uuid unique,
  closed_by uuid, closed_at timestamptz not null default now(),
  reopened_by uuid, reopened_at timestamptz, reopen_note text
);
create index if not exists yc_range on public.year_closes (fiscal_from, fiscal_to);

create table if not exists public.fa_assets (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  code text not null unique check (code ~ '^[0-9A-Za-z.\-]{1,20}$'),
  name text not null check (length(btrim(name)) between 1 and 120),
  category text check (category is null or length(category) <= 60),
  location_id int references public.locations(id),
  acquired_on date not null,
  cost numeric not null check (cost > 0 and cost <= 1000000000000),
  salvage numeric not null default 0 check (salvage >= 0 and salvage < cost),
  life_months int not null check (life_months between 1 and 1200),
  method text not null default 'straight_line' check (method in ('straight_line')),
  depr_from date not null check (extract(day from depr_from) = 1),           -- first month that is depreciated
  status text not null default 'active' check (status in ('active', 'disposed')),
  disposed_on date, note text,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz
);
create table if not exists public.fa_depr_posts (
  id bigserial primary key,
  asset_id uuid not null references public.fa_assets(id),
  month date not null check (extract(day from month) = 1),
  seq int not null,
  amount numeric not null check (amount > 0),
  entry_id bigint not null references public.journal_entries(id),
  created_by uuid, created_at timestamptz not null default now(),
  unique (asset_id, month)
);

create table if not exists public.budgets (
  id bigserial primary key,
  account_id bigint not null references public.coa_accounts(id),
  month date not null check (extract(day from month) = 1),
  location_id int references public.locations(id),
  amount numeric not null check (amount >= 0 and amount <= 1000000000000),
  updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists budgets_uq on public.budgets (account_id, month, coalesce(location_id, 0));
create table if not exists public.budget_log (
  id bigserial primary key,
  account_id bigint not null, month date not null, location_id int,
  old_amount numeric, new_amount numeric not null, note text,
  actor uuid, at timestamptz not null default now()
);

-- ---------- immutability ----------
create or replace function public._a53_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
create or replace function public._a53_nodel() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: %', tg_table_name; end $$;
do $t$
declare t text;
begin
  foreach t in array array['bank_statement_lines', 'bank_recon_trail', 'budget_log', 'fa_depr_posts'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro', t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public._a53_ro()', t || '_ro', t);
    execute format('drop trigger if exists %I on public.%I', t || '_ro_t', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._a53_ro()', t || '_ro_t', t);
  end loop;
  foreach t in array array['bank_recon_matches', 'year_closes', 'fa_assets', 'budgets'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nd', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public._a53_nodel()', t || '_nd', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nd_t', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public._a53_nodel()', t || '_nd_t', t);
  end loop;
end $t$;
drop trigger if exists audit_year_closes on public.year_closes;
create trigger audit_year_closes after insert or update on public.year_closes for each row execute function public.log_change('id');
drop trigger if exists audit_fa_assets on public.fa_assets;
create trigger audit_fa_assets after insert or update on public.fa_assets for each row execute function public.log_change('id');
drop trigger if exists audit_budgets on public.budgets;
create trigger audit_budgets after insert or update on public.budgets for each row execute function public.log_change('id');
drop trigger if exists audit_bank_recon_matches on public.bank_recon_matches;
create trigger audit_bank_recon_matches after insert or update on public.bank_recon_matches for each row execute function public.log_change('id');

create or replace function public._a53_mgr() returns boolean language sql stable security definer set search_path = public as $$ select public._acct_manage(); $$;
revoke all on function public._a53_mgr() from public, anon;
grant execute on function public._a53_mgr() to authenticated;

-- ---------- RLS: read only, owner / accounts_manage for the bank tables, accounts viewers for the rest ----------
alter table public.bank_statement_lines enable row level security;
alter table public.bank_recon_matches enable row level security;
alter table public.bank_recon_trail enable row level security;
alter table public.year_closes enable row level security;
alter table public.fa_assets enable row level security;
alter table public.fa_depr_posts enable row level security;
alter table public.budgets enable row level security;
alter table public.budget_log enable row level security;
drop policy if exists bsl_read on public.bank_statement_lines;
create policy bsl_read on public.bank_statement_lines for select to authenticated using (public._a53_mgr());
drop policy if exists brm_read on public.bank_recon_matches;
create policy brm_read on public.bank_recon_matches for select to authenticated using (public._a53_mgr());
drop policy if exists brt_read on public.bank_recon_trail;
create policy brt_read on public.bank_recon_trail for select to authenticated using (public._a53_mgr());
drop policy if exists yc_read on public.year_closes;
create policy yc_read on public.year_closes for select to authenticated using (public._acct_view() and public._acct_all());
drop policy if exists fa_read on public.fa_assets;
create policy fa_read on public.fa_assets for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists fadp_read on public.fa_depr_posts;
create policy fadp_read on public.fa_depr_posts for select to authenticated using (public._acct_view() and exists (select 1 from public.fa_assets a where a.id = asset_id));
drop policy if exists bud_read on public.budgets;
create policy bud_read on public.budgets for select to authenticated using (public._acct_view() and (public._acct_all() or (location_id is not null and public.can_loc(location_id))));
drop policy if exists budlog_read on public.budget_log;
create policy budlog_read on public.budget_log for select to authenticated using (public._a53_mgr());
revoke all on public.bank_statement_lines, public.bank_recon_matches, public.bank_recon_trail, public.year_closes, public.fa_assets, public.fa_depr_posts, public.budgets, public.budget_log from public, anon, authenticated;
grant select on public.bank_statement_lines, public.bank_recon_matches, public.bank_recon_trail, public.year_closes, public.fa_assets, public.fa_depr_posts, public.budgets, public.budget_log to authenticated;

-- ---------- shared helpers (closed to browsers) ----------
-- income / expense movement per account and location, optionally leaving out year-close entries (so a closed year still shows its real profit)
create or replace function public._a53_pl(p_from date, p_to date, p_loc int, p_excl boolean) returns table(account_id bigint, location_id int, dr numeric, cr numeric)
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
  select l.account_id, l.location_id, coalesce(sum(l.debit), 0), coalesce(sum(l.credit), 0)
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
  where a.type in ('income', 'expense') and e.entry_date between p_from and p_to
    and (not p_excl or coalesce(e.flags, '') not like '%year_close%')
    and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
  group by l.account_id, l.location_id;
end $$;

create or replace function public._a53_mon(p date) returns date language sql immutable as $$ select date_trunc('month', p)::date; $$;

-- ============================================================
-- #1 BANK STATEMENT RECONCILE
-- ============================================================
create or replace function public._a53_bank_acct(p_account bigint) returns public.coa_accounts language plpgsql stable security definer set search_path = public as $$
declare a public.coa_accounts; par public.coa_accounts;
begin
  select * into a from public.coa_accounts where id = p_account;
  if not found or a.is_group or a.type <> 'asset' or not a.active then raise exception 'bad_account'; end if;
  select * into par from public.coa_accounts where id = a.parent_id;
  if not found or par.code <> '1100' then raise exception 'bad_account'; end if;       -- only cash and bank accounts
  return a;
end $$;

-- candidate journal lines for one statement line: same account, exactly the same signed amount, posted, not matched yet, date within +-p_days
create or replace function public._a53_cands(p_line bigint, p_days int default 5) returns table(entry_id bigint, line_no int, entry_date date, memo text, source_type text, source_id text, amount numeric, days_off int, ref_hit boolean)
language plpgsql stable security definer set search_path = public as $$
declare s public.bank_statement_lines; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  select * into s from public.bank_statement_lines where id = p_line;
  if not found then raise exception 'not found'; end if;
  return query
  select e.id, l.line_no, e.entry_date, e.memo, e.source_type, e.source_id, (l.debit - l.credit), (e.entry_date - s.line_date),
    (nullif(btrim(s.reference), '') is not null and (position(lower(btrim(s.reference)) in lower(coalesce(e.memo, '') || ' ' || e.source_id || ' ' || coalesce(l.memo, ''))) > 0))
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  where l.account_id = s.account_id and (l.debit - l.credit) = s.amount and e.status = 'posted'
    and e.entry_date between s.line_date - greatest(coalesce(p_days, 5), 0) and s.line_date + greatest(coalesce(p_days, 5), 0)
    and (v_all or l.location_id = any (v_locs))
    and not exists (select 1 from public.bank_recon_matches m where m.entry_id = l.entry_id and m.line_no = l.line_no and m.active)
  order by 9 desc, abs(e.entry_date - s.line_date), e.id;
end $$;

-- import statement lines. p_rows = [{date:'YYYY-MM-DD', amount: signed number (+in / -out), reference, description, balance}]
create or replace function public.bank_stmt_import(p_account bigint, p_rows jsonb, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.coa_accounts; e jsonb; ord int := 0; d date; amt numeric; ref text; dsc text; bal numeric; k text; cnt int; m jsonb := '{}'::jsonb;
  good jsonb := '[]'::jsonb; bad jsonb := '[]'::jsonb; nbad int := 0; hsh text; nnew int := 0; ndup int := 0; batch uuid; ins int; rec record; sum_in numeric := 0; sum_out numeric := 0;
begin
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
end $$;

create or replace function public.bank_recon_candidates(p_line bigint, p_days int default 5) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('entry_id', c.entry_id, 'line_no', c.line_no, 'date', c.entry_date, 'memo', c.memo, 'source_type', c.source_type,
      'source_id', c.source_id, 'amount', c.amount, 'days_off', c.days_off, 'ref_hit', c.ref_hit)) from (select * from public._a53_cands(p_line, p_days) limit 20) c), '[]'::jsonb);
end $$;

-- suggestions only (writes nothing). confident = the only candidate, or the only one whose text contains the statement reference.
create or replace function public.bank_recon_suggest(p_account bigint, p_from date default null, p_to date default null, p_days int default 3) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; s record; n int; hits int; best record; used text[] := '{}'; kk text; conf boolean;
begin
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
end $$;

create or replace function public._a53_match1(p_line bigint, p_entry bigint, p_no int, p_how text, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare s public.bank_statement_lines; jl public.journal_lines; je public.journal_entries; id_ bigint;
begin
  select * into s from public.bank_statement_lines where id = p_line for update;
  if not found then raise exception 'not found'; end if;
  select * into jl from public.journal_lines where entry_id = p_entry and line_no = p_no;
  if not found then raise exception 'journal_line_not_found'; end if;
  select * into je from public.journal_entries where id = p_entry;
  if je.status <> 'posted' then raise exception 'entry_not_posted'; end if;
  if jl.account_id <> s.account_id then raise exception 'wrong_account'; end if;
  if jl.location_id is not null and not public.can_loc(jl.location_id) then raise exception 'not allowed for this location'; end if;
  if (jl.debit - jl.credit) <> s.amount then raise exception 'amount_mismatch' using detail = 'statement ' || s.amount::text || ' book ' || (jl.debit - jl.credit)::text; end if;
  if exists (select 1 from public.bank_recon_matches where line_id = p_line and active) then raise exception 'line_already_matched'; end if;
  if exists (select 1 from public.bank_recon_matches where entry_id = p_entry and line_no = p_no and active) then raise exception 'journal_already_matched'; end if;
  insert into public.bank_recon_matches (line_id, entry_id, line_no, how, note, matched_by) values (p_line, p_entry, p_no, p_how, left(nullif(btrim(p_note), ''), 200), auth.uid()) returning id into id_;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'match', p_entry, p_no, p_how, left(nullif(btrim(p_note), ''), 200), auth.uid());
  return id_;
end $$;

create or replace function public.bank_recon_match(p_line bigint, p_entry bigint, p_line_no int, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  id_ := public._a53_match1(p_line, p_entry, p_line_no, 'manual', p_note);
  return jsonb_build_object('match_id', id_);
end $$;

-- accept a reviewed list of suggestions [{line_id, entry_id, line_no}]; dry = check only. Each pair is checked on its own; failures are listed, the rest go through.
create or replace function public.bank_recon_match_many(p_pairs jsonb, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb; ok int := 0; fails jsonb := '[]'::jsonb;
begin
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
end $$;

create or replace function public.bank_recon_unmatch(p_line bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.bank_recon_matches;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('bank_recon_on') then raise exception 'switch_off: bank_recon_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into m from public.bank_recon_matches where line_id = p_line and active for update;
  if not found then raise exception 'not_matched'; end if;
  update public.bank_recon_matches set active = false, unmatched_by = auth.uid(), unmatched_at = now(), unmatch_note = left(btrim(p_note), 200) where id = m.id;
  insert into public.bank_recon_trail (line_id, action, entry_id, line_no, how, note, actor) values (p_line, 'unmatch', m.entry_id, m.line_no, m.how, left(btrim(p_note), 200), auth.uid());
  return jsonb_build_object('unmatched', p_line);
end $$;

create or replace function public.bank_recon_report(p_account bigint, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date := coalesce(p_from, date '2000-01-01'); to_ date := coalesce(p_to, date '2999-12-31');
  su jsonb; bu jsonb; sn int; sa numeric; bn int; ba numeric; mn int; ma numeric; st numeric; bk numeric; lb numeric; lbd date;
begin
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
end $$;

create or replace function public.bank_recon_lines(p_account bigint, p_status text default 'all', p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  perform public._a53_bank_acct(p_account);
  if p_status not in ('all', 'matched', 'unmatched') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(j order by (j->>'date') desc, (j->>'id')::bigint desc) from (
    select jsonb_build_object('id', l.id, 'date', l.line_date, 'amount', l.amount, 'reference', l.reference, 'description', l.description,
      'matched', m.id is not null, 'entry_id', m.entry_id, 'line_no', m.line_no, 'how', m.how) j
    from public.bank_statement_lines l left join public.bank_recon_matches m on m.line_id = l.id and m.active
    where l.account_id = p_account and (p_status = 'all' or (p_status = 'matched') = (m.id is not null))
    order by l.line_date desc, l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- ============================================================
-- #2 YEAR-END CLOSE
-- ============================================================
create or replace function public._a53_close_plan(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lines jsonb := '[]'::jsonb; r record; ti numeric := 0; te numeric := 0; re_acc bigint; net numeric; problems jsonb := '[]'::jsonb; lk text; lkd date; cnt int := 0; dr_sum numeric := 0; cr_sum numeric := 0;
begin
  select account_id into re_acc from public.acct_mappings where key = 'retained_close';
  if re_acc is null then problems := problems || '"no_retained_mapping"'::jsonb; end if;
  for r in select p.account_id, p.location_id, a.type, a.code, a.name_en, (p.dr - p.cr) n from public._a53_pl(p_from, p_to, null, true) p join public.coa_accounts a on a.id = p.account_id
           where p.dr - p.cr <> 0 order by a.code, p.location_id loop
    cnt := cnt + 1;
    if r.type = 'income' then ti := ti - r.n; else te := te + r.n; end if;
    if r.n > 0 then
      lines := lines || jsonb_build_object('account_id', r.account_id, 'debit', 0, 'credit', r.n, 'location_id', r.location_id, 'code', r.code, 'name', r.name_en); cr_sum := cr_sum + r.n;
    else
      lines := lines || jsonb_build_object('account_id', r.account_id, 'debit', -r.n, 'credit', 0, 'location_id', r.location_id, 'code', r.code, 'name', r.name_en); dr_sum := dr_sum - r.n;
    end if;
  end loop;
  net := dr_sum - cr_sum;           -- credit-balance accounts closed minus debit-balance accounts closed = profit
  if cnt = 0 then problems := problems || '"nothing_to_close"'::jsonb; end if;
  -- retained-earnings line(s): one per location so a location's own books also balance
  for r in select nullif(l->>'location_id', '')::int location_id, sum(((l->>'debit')::numeric) - ((l->>'credit')::numeric)) d from jsonb_array_elements(lines) l group by 1 having sum(((l->>'debit')::numeric) - ((l->>'credit')::numeric)) <> 0 loop
    lines := lines || jsonb_build_object('account_id', re_acc, 'debit', case when r.d < 0 then -r.d else 0 end, 'credit', case when r.d > 0 then r.d else 0 end, 'location_id', r.location_id, 'code', 'RE', 'name', 'Retained earnings');
  end loop;
  lk := public.rule_txt('period_closed_until');
  if lk is null or lk !~ '^\d{4}-\d{2}-\d{2}$' then problems := problems || '"period_not_locked"'::jsonb;
  else
    begin lkd := lk::date; exception when others then lkd := null; end;
    if lkd is null or lkd < p_to then problems := problems || '"period_not_locked"'::jsonb; end if;
  end if;
  if exists (select 1 from public.year_closes where status = 'closed' and daterange(fiscal_from, fiscal_to, '[]') && daterange(p_from, p_to, '[]')) then problems := problems || '"already_closed"'::jsonb; end if;
  if public._acct_start() is null then problems := problems || '"data_needed"'::jsonb;
  elsif p_from < public._acct_start() then problems := problems || '"before_start"'::jsonb; end if;
  return jsonb_build_object('from', p_from, 'to', p_to, 'income_total', ti, 'expense_total', te, 'net_profit', ti - te, 'accounts', cnt, 'lines', lines, 'problems', problems,
    'period_closed_until', lk, 'ok', jsonb_array_length(problems) = 0);
end $$;

create or replace function public.year_close_run(p_from date, p_to date, p_note text default null, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare plan jsonb; yc_id bigint; ent bigint; r public.year_closes; prob text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('year_close_on') then raise exception 'switch_off: year_close_on'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 or p_to > public._acct_today() then raise exception 'bad_range'; end if;
  plan := public._a53_close_plan(p_from, p_to);
  if p_dry then return plan || jsonb_build_object('dry', true); end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.year_closes where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'entry_id', r.entry_id); end if;
  end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if jsonb_array_length(plan->'problems') > 0 then raise exception '%', plan->'problems'->>0; end if;
  insert into public.year_closes (fiscal_from, fiscal_to, income_total, expense_total, net_profit, note, client_id, closed_by)
    values (p_from, p_to, (plan->>'income_total')::numeric, (plan->>'expense_total')::numeric, (plan->>'net_profit')::numeric, left(btrim(p_note), 300), p_client, auth.uid()) returning id into yc_id;
  ent := public._acct_write(p_to, null, 'year_close', yc_id::text, null, 'Year-end close ' || p_from::text || ' to ' || p_to::text, 'year_close', plan->'lines', null, null, null);
  update public.year_closes set entry_id = ent where id = yc_id;
  return jsonb_build_object('id', yc_id, 'entry_id', ent, 'net_profit', plan->'net_profit');
end $$;

create or replace function public.year_close_reverse(p_id bigint, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare y public.year_closes; rv bigint; r public.year_closes;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('year_close_on') then raise exception 'switch_off: year_close_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.year_closes where reopened_by is not null and id = p_id and status = 'reopened';
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'reversal_id', r.reversal_id); end if;
  end if;
  select * into y from public.year_closes where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if y.status <> 'closed' then raise exception 'already_reopened'; end if;
  if exists (select 1 from public.year_closes where status = 'closed' and fiscal_from > y.fiscal_to) then raise exception 'later_close_exists'; end if;
  rv := public._acct_reverse(y.entry_id, y.fiscal_to, 'Reopen year ' || y.fiscal_from::text || ' to ' || y.fiscal_to::text || ' (' || left(btrim(p_note), 150) || ')', p_client);
  update public.year_closes set status = 'reopened', reversal_id = rv, reopened_by = auth.uid(), reopened_at = now(), reopen_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'reversal_id', rv);
end $$;

create or replace function public.year_close_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('year_close_on'), 'period_closed_until', public.rule_txt('period_closed_until'), 'owner', public.is_owner(),
    'rows', coalesce((select jsonb_agg(to_jsonb(y) - 'client_id' order by y.fiscal_to desc, y.id desc) from public.year_closes y), '[]'::jsonb));
end $$;

-- income statement that leaves the closing entries out (phase40's acct_income_statement shows them, so a closed year there reads 0)
create or replace function public.acct_pnl_ex_close(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ti numeric; te numeric; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  select coalesce(sum(case when a.type = 'income' then p.cr - p.dr end), 0), coalesce(sum(case when a.type = 'expense' then p.dr - p.cr end), 0),
    coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn, 'type', a.type, 'amount', case when a.type = 'income' then p.cr - p.dr else p.dr - p.cr end) order by a.code), '[]'::jsonb)
    into ti, te, rows_ from (select account_id, sum(dr) dr, sum(cr) cr from public._a53_pl(p_from, p_to, p_loc, true) group by account_id) p join public.coa_accounts a on a.id = p.account_id;
  return jsonb_build_object('from', p_from, 'to', p_to, 'total_income', ti, 'total_expense', te, 'net_profit', ti - te, 'rows', rows_);
end $$;

-- ============================================================
-- #3 VAT LEDGER (report only; vat_on + vat_rate are the phase8 switches)
-- ============================================================
create or replace function public.vat_report(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rate numeric := public.rule_num('vat_rate'); inc boolean := public.rule_on('vat_prices_include'); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
  out_t numeric := 0; out_v numeric := 0; out_u numeric := 0; out_n int := 0; ret_t numeric := 0; ret_v numeric := 0; in_t numeric := 0; in_v numeric := 0; in_u numeric := 0; in_n int := 0; inr_t numeric := 0; inr_v numeric := 0;
  months jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if not public.rule_on('vat_on') then return jsonb_build_object('off', true); end if;
  if rate is null then return jsonb_build_object('data_needed', true, 'need', 'vat_rate'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  create temporary table if not exists _a53_vat (kind text, d date, taxable numeric, undecided numeric) on commit drop;
  delete from _a53_vat;
  -- sales: taxable = value of vat_applicable=true lines, less the bill discount share
  insert into _a53_vat
  select 'out', s.sale_date,
    coalesce(t.tx, 0) * case when s.subtotal > 0 then (s.subtotal - s.discount) / s.subtotal else 1 end,
    coalesce(t.und, 0) * case when s.subtotal > 0 then (s.subtotal - s.discount) / s.subtotal else 1 end
  from public.sales s cross join lateral (
    select sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is true) tx,
           sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is null) und
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
    left join public.items i on i.id = nullif(e->>'item_id', '')::uuid) t
  where s.status = 'done' and s.sale_date between p_from and p_to and (v_all or s.location_id = any (v_locs)) and (p_loc is null or s.location_id = p_loc);
  -- sale returns reduce output VAT (the value taken back, in the share of VAT-applicable lines)
  insert into _a53_vat
  select 'outret', r.created_at::date, r.amount * case when t.tot > 0 then coalesce(t.tx, 0) / t.tot else 0 end, 0
  from public.sale_returns r cross join lateral (
    select sum(coalesce((e->>'amount')::numeric, 0)) tot, sum(coalesce((e->>'amount')::numeric, 0)) filter (where i.vat_applicable is true) tx
    from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e left join public.items i on i.id = nullif(e->>'item_id', '')::uuid) t
  where r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (v_all or r.location_id = any (v_locs)) and (p_loc is null or r.location_id = p_loc);
  -- purchases: bill total (after the bill discount) in the share of VAT-applicable lines
  insert into _a53_vat
  select case when b.kind = 'return' then 'inret' else 'in' end, b.bill_date,
    b.total * case when t.tot > 0 then coalesce(t.tx, 0) / t.tot else 0 end, b.total * case when t.tot > 0 then coalesce(t.und, 0) / t.tot else 0 end
  from public.purchase_bills b cross join lateral (
    select sum(l.amount) tot, sum(l.amount) filter (where i.vat_applicable is true) tx, sum(l.amount) filter (where i.id is null or i.vat_applicable is null) und
    from public.purchase_lines l left join public.items i on i.id = l.item_id where l.bill_id = b.id) t
  where b.status = 'posted' and b.bill_date between p_from and p_to and (v_all or b.location_id = any (v_locs)) and (p_loc is null or b.location_id = p_loc);
  select coalesce(sum(taxable) filter (where kind = 'out'), 0), coalesce(sum(undecided) filter (where kind = 'out'), 0), count(*) filter (where kind = 'out'),
         coalesce(sum(taxable) filter (where kind = 'outret'), 0), coalesce(sum(taxable) filter (where kind = 'in'), 0), coalesce(sum(undecided) filter (where kind = 'in'), 0),
         count(*) filter (where kind = 'in'), coalesce(sum(taxable) filter (where kind = 'inret'), 0)
    into out_t, out_u, out_n, ret_t, in_t, in_u, in_n, inr_t from _a53_vat;
  out_v := round(case when inc then (out_t) * rate / (100 + rate) else out_t * rate / 100 end, 2);
  ret_v := round(case when inc then ret_t * rate / (100 + rate) else ret_t * rate / 100 end, 2);
  in_v := round(case when inc then in_t * rate / (100 + rate) else in_t * rate / 100 end, 2);
  inr_v := round(case when inc then inr_t * rate / (100 + rate) else inr_t * rate / 100 end, 2);
  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'output_taxable', ot, 'output_vat', ov, 'input_taxable', it, 'input_vat', iv) order by m), '[]'::jsonb) into months from (
    select date_trunc('month', d)::date m,
      sum(case kind when 'out' then taxable when 'outret' then -taxable else 0 end) ot,
      round(sum(case kind when 'out' then taxable when 'outret' then -taxable else 0 end) * case when inc then rate / (100 + rate) else rate / 100 end, 2) ov,
      sum(case kind when 'in' then taxable when 'inret' then -taxable else 0 end) it,
      round(sum(case kind when 'in' then taxable when 'inret' then -taxable else 0 end) * case when inc then rate / (100 + rate) else rate / 100 end, 2) iv
    from _a53_vat group by 1) z;
  return jsonb_build_object('from', p_from, 'to', p_to, 'rate', rate, 'prices_include_vat', inc,
    'output', jsonb_build_object('taxable_sales', out_t, 'returns_taxable', ret_t, 'vat', out_v - ret_v, 'vat_before_returns', out_v, 'returns_vat', ret_v, 'documents', out_n, 'undecided_amount', out_u),
    'input', jsonb_build_object('taxable_purchases', in_t, 'returns_taxable', inr_t, 'vat', in_v - inr_v, 'vat_before_returns', in_v, 'returns_vat', inr_v, 'documents', in_n, 'undecided_amount', in_u),
    'net_vat_payable', (out_v - ret_v) - (in_v - inr_v), 'months', months,
    'note', 'report only: nothing is posted; items with VAT status undecided are not taxed and are shown as undecided_amount');
end $$;

-- ============================================================
-- #4 FIXED ASSETS + STRAIGHT-LINE DEPRECIATION
-- ============================================================
-- month k (1-based) of the schedule: equal parts, the last month takes the rounding remainder
create or replace function public._a53_fa_amt(p_cost numeric, p_salvage numeric, p_life int, p_k int) returns numeric language sql immutable as $$
  select case when p_k < 1 or p_k > p_life then 0
              when p_k < p_life then round((p_cost - p_salvage) / p_life, 2)
              else (p_cost - p_salvage) - round((p_cost - p_salvage) / p_life, 2) * (p_life - 1) end;
$$;

create or replace function public.fa_asset_save(p_id uuid, p_code text, p_name text, p_category text, p_loc int, p_acquired date, p_cost numeric, p_salvage numeric,
  p_life_months int, p_depr_from date, p_note text default null, p_client uuid default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.fa_assets; id_ uuid; df date := public._a53_mon(p_depr_from); sched numeric;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if p_name is null or length(btrim(p_name)) = 0 or length(p_name) > 120 then raise exception 'name_required'; end if;
  if p_cost is null or p_cost <= 0 or p_cost > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_salvage is null or p_salvage < 0 or p_salvage >= p_cost then raise exception 'bad_salvage'; end if;
  if p_life_months is null or p_life_months < 1 or p_life_months > 1200 then raise exception 'bad_life'; end if;
  if p_acquired is null or p_acquired < date '2000-01-01' or p_acquired > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_depr_from is null or df < public._a53_mon(p_acquired) then raise exception 'bad_depr_start'; end if;
  if p_loc is not null and (not exists (select 1 from public.locations where id = p_loc) or not public.can_loc(p_loc)) then raise exception 'bad_location'; end if;
  if p_category is not null and length(p_category) > 60 then raise exception 'bad_category'; end if;
  sched := public._a53_fa_amt(p_cost, p_salvage, p_life_months, 1);
  if p_dry then
    return jsonb_build_object('dry', true, 'monthly', sched, 'last_month', public._a53_fa_amt(p_cost, p_salvage, p_life_months, p_life_months), 'depr_from', df,
      'depr_to', (df + ((p_life_months - 1) || ' months')::interval)::date, 'depreciable', p_cost - p_salvage);
  end if;
  if p_id is null then
    if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,20}$' then raise exception 'bad_code'; end if;
    if p_client is not null then
      perform public._client_lock(p_client);
      select * into a from public.fa_assets where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', a.id); end if;
    end if;
    if exists (select 1 from public.fa_assets where code = p_code) then raise exception 'code_taken'; end if;
    insert into public.fa_assets (client_id, code, name, category, location_id, acquired_on, cost, salvage, life_months, depr_from, note, created_by)
      values (p_client, p_code, btrim(p_name), nullif(btrim(p_category), ''), p_loc, p_acquired, p_cost, p_salvage, p_life_months, df, left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into id_;
    return jsonb_build_object('id', id_, 'monthly', sched);
  end if;
  select * into a from public.fa_assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.location_id is not null and not public.can_loc(a.location_id) then raise exception 'not allowed for this location'; end if;
  if exists (select 1 from public.fa_depr_posts where asset_id = p_id)
     and (p_cost <> a.cost or p_salvage <> a.salvage or p_life_months <> a.life_months or df <> a.depr_from or p_acquired <> a.acquired_on or p_loc is distinct from a.location_id) then
    raise exception 'depreciation_already_posted';
  end if;
  if a.status <> 'active' then raise exception 'asset_disposed'; end if;
  update public.fa_assets set name = btrim(p_name), category = nullif(btrim(p_category), ''), location_id = p_loc, acquired_on = p_acquired, cost = p_cost, salvage = p_salvage,
    life_months = p_life_months, depr_from = df, note = left(nullif(btrim(p_note), ''), 300), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'monthly', sched);
end $$;

-- retire an asset from the register: no further depreciation after the month of p_date. (No disposal journal is posted: use the manual journal for the sale / write-off.)
create or replace function public.fa_asset_dispose(p_id uuid, p_date date, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.fa_assets;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into a from public.fa_assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.status <> 'active' then raise exception 'asset_disposed'; end if;
  if p_date is null or p_date < a.acquired_on or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if exists (select 1 from public.fa_depr_posts where asset_id = p_id and month > public._a53_mon(p_date)) then raise exception 'depreciation_posted_after_date'; end if;
  update public.fa_assets set status = 'disposed', disposed_on = p_date, note = left(coalesce(note || ' | ', '') || btrim(p_note), 300), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'disposed_on', p_date);
end $$;

create or replace function public.fa_schedule(p_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.fa_assets; rows_ jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select * into a from public.fa_assets where id = p_id;
  if not found then raise exception 'not found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('k', k, 'month', m, 'amount', amt, 'accumulated', acc, 'book_value', a.cost - acc, 'posted', p.id is not null,
      'skipped_after_disposal', a.status = 'disposed' and m > public._a53_mon(a.disposed_on)) order by k), '[]'::jsonb) into rows_ from (
    select g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m, public._a53_fa_amt(a.cost, a.salvage, a.life_months, g) amt,
      sum(public._a53_fa_amt(a.cost, a.salvage, a.life_months, g)) over (order by g) acc from generate_series(1, a.life_months) g) s
    left join public.fa_depr_posts p on p.asset_id = a.id and p.month = s.m;
  return jsonb_build_object('asset_id', a.id, 'code', a.code, 'name', a.name, 'cost', a.cost, 'salvage', a.salvage, 'life_months', a.life_months, 'method', a.method, 'status', a.status, 'rows', rows_);
end $$;

-- post depreciation for every due month up to and including p_through's month (only COMPLETED months). Idempotent on (asset, month).
create or replace function public.fa_depr_post(p_through date, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); thr date; r record; list_ jsonb := '[]'::jsonb; skipped jsonb := '[]'::jsonb; n int := 0; tot numeric := 0; ent bigint; ex bigint; ac bigint; me date; sid text; done_ text[] := '{}';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('fixed_assets_on') then raise exception 'switch_off: fixed_assets_on'; end if;
  if st is null then raise exception 'data_needed'; end if;
  if p_through is null then raise exception 'bad_date'; end if;
  thr := public._a53_mon(p_through);
  if (thr + interval '1 month')::date - 1 > public._acct_today() then raise exception 'month_not_complete'; end if;
  select account_id into ex from public.acct_mappings where key = 'depreciation';
  select account_id into ac from public.acct_mappings where key = 'accum_depr';
  if ex is null or ac is null then raise exception 'no_mapping'; end if;
  for r in
    select a.id, a.code, a.location_id, a.depr_from, a.cost, a.salvage, a.life_months, a.status, a.disposed_on, g k, (a.depr_from + ((g - 1) || ' months')::interval)::date m
    from public.fa_assets a cross join lateral generate_series(1, a.life_months) g
    where (a.depr_from + ((g - 1) || ' months')::interval)::date <= thr
      and (a.status = 'active' or (a.disposed_on is not null and (a.depr_from + ((g - 1) || ' months')::interval)::date <= public._a53_mon(a.disposed_on)))
      and (a.location_id is null or public.can_loc(a.location_id))
      and not exists (select 1 from public.fa_depr_posts p where p.asset_id = a.id and p.month = (a.depr_from + ((g - 1) || ' months')::interval)::date)
    order by 11, a.code limit 600 loop
    me := (r.m + interval '1 month')::date - 1;
    if me < st then skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'before_start'); continue; end if;
    if public._acct_locked(me) then skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'period_closed'); continue; end if;
    -- months must be posted in order for one asset
    if exists (select 1 from generate_series(1, r.k - 1) q where not exists (select 1 from public.fa_depr_posts p where p.asset_id = r.id and p.month = (r.depr_from + ((q - 1) || ' months')::interval)::date)
                 and not ((r.id::text || '_' || q::text) = any (done_))
                 and (r.depr_from + ((q - 1) || ' months')::interval)::date >= st) then
      skipped := skipped || jsonb_build_object('code', r.code, 'month', r.m, 'why', 'earlier_month_missing'); continue;
    end if;
    done_ := done_ || (r.id::text || '_' || r.k::text);
    n := n + 1; tot := tot + public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k);
    list_ := list_ || jsonb_build_object('code', r.code, 'month', r.m, 'k', r.k, 'amount', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k));
    if not p_dry then
      sid := r.id::text || '_' || r.m::text;
      ent := public._acct_write(me, r.location_id, 'fa_depr', sid, null, 'Depreciation ' || r.code || ' ' || to_char(r.m, 'YYYY-MM'), null,
        jsonb_build_array(jsonb_build_object('account_id', ex, 'debit', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), 'credit', 0, 'location_id', r.location_id),
                          jsonb_build_object('account_id', ac, 'debit', 0, 'credit', public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), 'location_id', r.location_id)), null, null, null);
      insert into public.fa_depr_posts (asset_id, month, seq, amount, entry_id, created_by) values (r.id, r.m, r.k, public._a53_fa_amt(r.cost, r.salvage, r.life_months, r.k), ent, auth.uid());
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'through', thr, 'count', n, 'total', tot, 'rows', list_, 'skipped', skipped);
end $$;

create or replace function public.fa_register(p_as_of date default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare as_ date := coalesce(p_as_of, public._acct_today());
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('fixed_assets_on'), 'as_of', as_, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'category', a.category, 'location_id', a.location_id, 'acquired_on', a.acquired_on, 'cost', a.cost, 'salvage', a.salvage,
      'life_months', a.life_months, 'method', a.method, 'depr_from', a.depr_from, 'status', a.status, 'disposed_on', a.disposed_on,
      'accumulated', coalesce(p.s, 0), 'book_value', a.cost - coalesce(p.s, 0), 'months_posted', coalesce(p.n, 0), 'last_month', p.mx) order by a.code)
    from public.fa_assets a left join lateral (select sum(amount) s, count(*) n, max(month) mx from public.fa_depr_posts x where x.asset_id = a.id and x.month <= as_) p on true), '[]'::jsonb));
end $$;

-- ============================================================
-- #5 BUDGETS
-- ============================================================
-- p_rows = [{account_id, month:'YYYY-MM-01', location_id?, amount}]; dry first. Every change is logged (old -> new).
create or replace function public.budget_set(p_rows jsonb, p_note text default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; a public.coa_accounts; mo date; amt numeric; lc int; old_ numeric; n_new int := 0; n_chg int := 0; n_same int := 0; ord int := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if not public.rule_on('budgets_on') then raise exception 'switch_off: budgets_on'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'too_many_rows'; end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    ord := ord + 1;
    select * into a from public.coa_accounts where id = nullif(e->>'account_id', '')::bigint;
    if not found or a.is_group or a.type not in ('income', 'expense') or not a.active then raise exception 'bad_account (row %)', ord; end if;
    if coalesce(e->>'month', '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_month (row %)', ord; end if;
    mo := public._a53_mon((e->>'month')::date);
    if mo < date '2000-01-01' or mo > public._acct_today() + 3650 then raise exception 'bad_month (row %)', ord; end if;
    if coalesce(e->>'amount', '') !~ '^\d+(\.\d+)?$' then raise exception 'bad_amount (row %)', ord; end if;
    amt := round((e->>'amount')::numeric, 2);
    if amt > 1000000000000 then raise exception 'bad_amount (row %)', ord; end if;
    lc := nullif(e->>'location_id', '')::int;
    if lc is not null and (not exists (select 1 from public.locations where id = lc) or not public.can_loc(lc)) then raise exception 'bad_location (row %)', ord; end if;
    if lc is null and not public._acct_all() then raise exception 'not allowed for this location'; end if;
    select amount into old_ from public.budgets where account_id = a.id and month = mo and coalesce(location_id, 0) = coalesce(lc, 0);
    if not found then n_new := n_new + 1; elsif old_ = amt then n_same := n_same + 1; continue; else n_chg := n_chg + 1; end if;
    if not p_dry then
      insert into public.budgets (account_id, month, location_id, amount, updated_by) values (a.id, mo, lc, amt, auth.uid())
        on conflict (account_id, month, coalesce(location_id, 0)) do update set amount = excluded.amount, updated_by = auth.uid(), updated_at = now();
      insert into public.budget_log (account_id, month, location_id, old_amount, new_amount, note, actor) values (a.id, mo, lc, old_, amt, left(nullif(btrim(p_note), ''), 200), auth.uid());
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'new', n_new, 'changed', n_chg, 'unchanged', n_same);
end $$;

create or replace function public.budget_list(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs();
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('budgets_on'), 'rows', coalesce((select jsonb_agg(jsonb_build_object('account_id', b.account_id, 'code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn,
      'month', b.month, 'location_id', b.location_id, 'amount', b.amount) order by a.code, b.month) from public.budgets b join public.coa_accounts a on a.id = b.account_id
      where b.month between public._a53_mon(p_from) and public._a53_mon(p_to) and (p_loc is null or b.location_id = p_loc)
        and (v_all or b.location_id = any (v_locs))), '[]'::jsonb));
end $$;

create or replace function public.budget_vs_actual(p_from date, p_to date, p_loc int default null, p_by_month boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); f date; t date; rows_ jsonb; tb_i numeric; ta_i numeric; tb_e numeric; ta_e numeric;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  f := public._a53_mon(p_from); t := (public._a53_mon(p_to) + interval '1 month')::date - 1;
  create temporary table if not exists _a53_bva (account_id bigint, m date, bud numeric, act numeric) on commit drop;
  delete from _a53_bva;
  insert into _a53_bva
  select account_id, case when p_by_month then m else null end, sum(bud), sum(act) from (
    select b.account_id, b.month m, b.amount bud, 0::numeric act from public.budgets b
      where b.month between f and t and (v_all or b.location_id = any (v_locs)) and (p_loc is null or b.location_id = p_loc)
    union all
    select l.account_id, public._a53_mon(e.entry_date), 0, case when a.type = 'income' then l.credit - l.debit else l.debit - l.credit end
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
      where a.type in ('income', 'expense') and e.entry_date between f and t and coalesce(e.flags, '') not like '%year_close%'
        and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)) u
  group by account_id, case when p_by_month then m else null end;
  select coalesce(jsonb_agg(jsonb_build_object('account_id', a.id, 'code', a.code, 'name_en', a.name_en, 'name_bn', a.name_bn, 'type', a.type, 'month', x.m, 'budget', x.bud, 'actual', x.act,
      'variance', case when a.type = 'income' then x.act - x.bud else x.bud - x.act end,           -- positive = good (more income / less spend)
      'pct_used', case when x.bud > 0 then round(x.act * 100 / x.bud, 1) end) order by a.code, x.m), '[]'::jsonb),
    coalesce(sum(x.bud) filter (where a.type = 'income'), 0), coalesce(sum(x.act) filter (where a.type = 'income'), 0),
    coalesce(sum(x.bud) filter (where a.type = 'expense'), 0), coalesce(sum(x.act) filter (where a.type = 'expense'), 0)
    into rows_, tb_i, ta_i, tb_e, ta_e from _a53_bva x join public.coa_accounts a on a.id = x.account_id where x.bud <> 0 or x.act <> 0;
  return jsonb_build_object('on', public.rule_on('budgets_on'), 'from', f, 'to', t, 'by_month', p_by_month, 'rows', rows_,
    'income_budget', tb_i, 'income_actual', ta_i, 'expense_budget', tb_e, 'expense_actual', ta_e, 'profit_budget', tb_i - tb_e, 'profit_actual', ta_i - ta_e);
end $$;

-- ---------- privileges ----------
revoke all on function public._a53_ro(), public._a53_nodel(), public._a53_pl(date, date, int, boolean), public._a53_mon(date), public._a53_bank_acct(bigint), public._a53_cands(bigint, int),
  public._a53_match1(bigint, bigint, int, text, text), public._a53_close_plan(date, date), public._a53_fa_amt(numeric, numeric, int, int) from public, anon, authenticated;
revoke all on function public.bank_stmt_import(bigint, jsonb, uuid, boolean), public.bank_recon_candidates(bigint, int), public.bank_recon_suggest(bigint, date, date, int),
  public.bank_recon_match(bigint, bigint, int, text), public.bank_recon_match_many(jsonb, boolean), public.bank_recon_unmatch(bigint, text), public.bank_recon_report(bigint, date, date),
  public.bank_recon_lines(bigint, text, int), public.year_close_run(date, date, text, uuid, boolean), public.year_close_reverse(bigint, text, uuid), public.year_close_list(),
  public.acct_pnl_ex_close(date, date, int), public.vat_report(date, date, int),
  public.fa_asset_save(uuid, text, text, text, int, date, numeric, numeric, int, date, text, uuid, boolean), public.fa_asset_dispose(uuid, date, text), public.fa_schedule(uuid),
  public.fa_depr_post(date, boolean), public.fa_register(date), public.budget_set(jsonb, text, boolean), public.budget_list(date, date, int), public.budget_vs_actual(date, date, int, boolean)
  from public, anon;
grant execute on function public.bank_stmt_import(bigint, jsonb, uuid, boolean), public.bank_recon_candidates(bigint, int), public.bank_recon_suggest(bigint, date, date, int),
  public.bank_recon_match(bigint, bigint, int, text), public.bank_recon_match_many(jsonb, boolean), public.bank_recon_unmatch(bigint, text), public.bank_recon_report(bigint, date, date),
  public.bank_recon_lines(bigint, text, int), public.year_close_run(date, date, text, uuid, boolean), public.year_close_reverse(bigint, text, uuid), public.year_close_list(),
  public.acct_pnl_ex_close(date, date, int), public.vat_report(date, date, int),
  public.fa_asset_save(uuid, text, text, text, int, date, numeric, numeric, int, date, text, uuid, boolean), public.fa_asset_dispose(uuid, date, text), public.fa_schedule(uuid),
  public.fa_depr_post(date, boolean), public.fa_register(date), public.budget_set(jsonb, text, boolean), public.budget_list(date, date, int), public.budget_vs_actual(date, date, int, boolean)
  to authenticated;

-- ---------------------------------------------------------------- phase54.sql
-- ============================================================
-- Phase 54 - P2c: attendance, two paths counted once (gap #29) + form equation recompute (gap #20, safe core).
-- Run AFTER phase51 (needs phase42 attendance + phase48-50 path engine). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   ATTENDANCE  path A = staff attendance (device / finger file / app punch / manager entry -> attendance_punches + attendance_days),
--               path B = the monthly paper register, form 02-1.   Same place + month = same event.
--               Owner default: path A is the record; an 02-1 that is submitted/approved for a month that path A already holds becomes a LOCKED SHADOW
--               copy (kept, shown, never counted again). Owner may switch primary to the form, or lock either path (Switch board, domain 'attendance').
--               Form 14-1 (daily showroom sheet) is NOT mapped to this domain: it is the cash drawer sheet, locking it would stop the drawer count.
--   (a) SELF PUNCH  staff punch from the phone (attendance_self_punch). Master switch = existing rule app_punch_on (OFF). Owner can lock one person
--               or one role (att_self_lock). A lock never deletes anything; it only refuses NEW self punches.
--   (b) EVIDENCE    fingerprint / face / browser-passkey registration is EVIDENCE ONLY: a flag + a reference (photo path, passkey id, device user id).
--               No biometric template is stored. The server cannot verify a passkey assertion or a face, so nothing here proves identity.
--               GPS is a SOFT flag (rule att_geo_check_on, OFF): a punch outside the radius is recorded and flagged, never refused.
--   (c) MARK OTHERS new grant attendance_mark_others (no role has it by default; the owner gives it to a person). Lets a manager mark another person's
--               day status, rest time and closing time by hand with a source tag device/finger/face/manual. Every call is written to an append-only log.
--               The tag is the manager's declaration, not a proof. Cannot mark himself. A month locked by approved/paid payroll is refused (month_locked).
--   EQUATIONS   entry_equation_check(entry) re-works the key totals of 10-2 and 02-2 on the server and lists differences against the flags the phone
--               stored. Rule entry_equation_flag_on (OFF): when ON, a submitted 10-2 / 02-2 that differs gets one red exception 'equation_mismatch'.
--   Re-created from the latest definition: attendance_app_punch (now a thin wrapper of attendance_self_punch; same errors, same 1-minute rule).
-- ============================================================

-- ---------- 1. the shadow engine: new domain ----------
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('attendance', 'কর্মী হাজিরা (মেশিন / অ্যাপ পাঞ্চ)', 'Staff attendance (device / app punch)', 'ফর্ম 02-1 (মাসিক হাজিরা রেজিস্টার)', 'Form 02-1 (monthly attendance register)', 'a',
  'ডিফল্ট: পাঞ্চ/হাজিরা রেকর্ড মূল; সেই মাসের 02-1 লক করা শ্যাডো কপি। শুধু মাস-পর্যায়ের মিল; কাউকে শনাক্তের প্রমাণ নয়।',
  'Default: punch / attendance record is primary; the 02-1 of a month that path A holds is a locked shadow. Month-level match only; not proof of anybody''s identity.', 60)
on conflict (domain) do nothing;

-- ---------- 2. columns ----------
alter table public.attendance_days add column if not exists rest_minutes int check (rest_minutes is null or rest_minutes between 0 and 720);
alter table public.attendance_days add column if not exists mark_source text check (mark_source is null or mark_source in ('device', 'finger', 'face', 'manual'));
alter table public.attendance_punches add column if not exists evidence_kind text check (evidence_kind is null or evidence_kind in ('webauthn', 'face_photo'));
alter table public.attendance_punches add column if not exists evidence_ref text check (evidence_ref is null or char_length(evidence_ref) <= 300);
alter table public.attendance_punches add column if not exists evidence_state text check (evidence_state is null or evidence_state in ('registered', 'unregistered', 'none'));
alter table public.attendance_punches add column if not exists geo_lat numeric check (geo_lat is null or geo_lat between -90 and 90);
alter table public.attendance_punches add column if not exists geo_lng numeric check (geo_lng is null or geo_lng between -180 and 180);
alter table public.attendance_punches add column if not exists geo_flag text check (geo_flag is null or geo_flag in ('ok', 'outside', 'no_fix', 'unchecked'));

-- ---------- 3. tables ----------
create table if not exists public.att_self_lock (               -- owner's lock: this person / role may NOT self-punch
  scope text not null check (scope in ('person', 'role')),
  ref text not null check (char_length(ref) between 1 and 60),   -- employee id (uuid text) or role code
  locked boolean not null default true,
  note text check (note is null or char_length(note) <= 300),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (scope, ref)
);
create table if not exists public.att_site_geo (                -- optional place coordinates for the soft GPS flag
  location_id int primary key references public.locations(id),
  lat numeric not null check (lat between -90 and 90), lng numeric not null check (lng between -180 and 180),
  set_by uuid, set_at timestamptz not null default now()
);
create table if not exists public.att_evidence_reg (            -- registration FLAG + reference. Never a biometric template. Evidence only.
  id bigserial primary key,
  employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('webauthn', 'face_photo', 'finger_device')),
  ref text not null check (char_length(ref) between 1 and 300),
  label text check (label is null or char_length(label) <= 80),
  active boolean not null default true,
  registered_by uuid, registered_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_reason text check (void_reason is null or char_length(void_reason) <= 300)
);
create unique index if not exists att_evidence_reg_uq on public.att_evidence_reg (employee_id, kind, ref) where active;
create table if not exists public.att_mark_log54 (              -- append-only audit of every "mark others" call
  id bigserial primary key, client_id uuid unique,
  employee_id uuid not null references public.employees(id), location_id int, day date not null,
  source_tag text not null check (source_tag in ('device', 'finger', 'face', 'manual')),
  status text not null, first_in timestamptz, last_out timestamptz, rest_minutes int, ot_minutes int,
  reason text not null, note text, prev jsonb, approved boolean not null default false,
  marked_by uuid, marked_staff text, marked_at timestamptz not null default now()
);
create or replace function public._att_log_ro54() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists att_mark_log54_ro on public.att_mark_log54;
create trigger att_mark_log54_ro before update or delete on public.att_mark_log54 for each row execute function public._att_log_ro54();

drop trigger if exists audit_att_self_lock on public.att_self_lock;
create trigger audit_att_self_lock after insert or update on public.att_self_lock for each row execute function public.log_change('scope,ref');
drop trigger if exists audit_att_site_geo on public.att_site_geo;
create trigger audit_att_site_geo after insert or update on public.att_site_geo for each row execute function public.log_change('location_id');
drop trigger if exists audit_att_evidence_reg on public.att_evidence_reg;
create trigger audit_att_evidence_reg after insert or update on public.att_evidence_reg for each row execute function public.log_change('id');

alter table public.att_self_lock enable row level security;
alter table public.att_site_geo enable row level security;
alter table public.att_evidence_reg enable row level security;
alter table public.att_mark_log54 enable row level security;
revoke all on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 from public, anon, authenticated;
revoke all on sequence public.att_evidence_reg_id_seq, public.att_mark_log54_id_seq from public, anon, authenticated;
grant select on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 to authenticated;
drop policy if exists att_self_lock_read on public.att_self_lock;
create policy att_self_lock_read on public.att_self_lock for select to authenticated using (public.is_owner());
drop policy if exists att_site_geo_read on public.att_site_geo;
create policy att_site_geo_read on public.att_site_geo for select to authenticated using (public.is_active());
drop policy if exists att_evidence_reg_read on public.att_evidence_reg;
create policy att_evidence_reg_read on public.att_evidence_reg for select to authenticated using (public._att_view(employee_id));
drop policy if exists att_mark_log54_read on public.att_mark_log54;
create policy att_mark_log54_read on public.att_mark_log54 for select to authenticated using (public.is_owner()
  or (location_id is not null and public.can_loc(location_id) and (public.has_grant('attendance_mark_others', location_id) or public.has_grant('attendance_manage', location_id))));

-- ---------- 4. rules and grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('att_geo_check_on', 'people', 'switch', 'false', null, null, null, null, 'স্ব-পাঞ্চে জিপিএস দূরত্বের নরম পতাকা', 'Self punch এ GPS দূরত্বের soft flag', 'Soft GPS flag on self punches',
  'চালু থাকলে অফিস/শোরুমের স্থানাঙ্ক থেকে দূরে পাঞ্চ হলে পতাকা পড়বে; পাঞ্চ বাতিল হবে না। জিপিএস সহজে ভুল/নকল হয়।', 'When ON, a punch far from the place coordinates is flagged, never refused. GPS can be wrong or faked.', 190),
 ('att_geo_radius_m', 'people', 'number', '300', 'm', null, 20, 20000, 'জিপিএস সীমা (মিটার)', 'GPS radius (meter)', 'GPS radius (metres)', null, null, 191),
 ('entry_equation_flag_on', 'entries', 'switch', 'false', null, null, null, null, 'জমা দেওয়ার সময় সার্ভারে হিসাব মিলিয়ে লাল ব্যতিক্রম', 'Submit এ server হিসাব মিলিয়ে red exception', 'Server re-check of 10-2 / 02-2 totals at submit (red exception)',
  'চালু থাকলে ফোনের হিসাব আর সার্ভারের পুনঃহিসাব না মিললে একটি লাল ব্যতিক্রম পড়বে; জমা আটকায় না।', 'When ON, a submitted 10-2 / 02-2 whose stored flags differ from the server re-work gets one red exception; the submit is not blocked.', 320)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('attendance_mark_others', 76, 'অন্যের দৈনিক হাজিরা, বিরতি ও বন্ধের সময় হাতে লেখা (সোর্স ট্যাগসহ)', 'অন্যের daily attendance, rest ও closing time হাতে লেখা (source tag সহ)', 'Mark other people''s daily attendance, rest and closing time by hand (with a source tag)')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

-- ---------- 5. helpers ----------
create or replace function public._att_geo_m54(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric) returns numeric
language sql immutable as $$
  select (2 * 6371000 * asin(least(1, sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))))::numeric;
$$;

-- may this login punch itself right now? (shared by status + punch)
create or replace function public._att_self_state54(p_emp public.employees) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.rule_on('attendance_on') then return 'attendance_off'; end if;
  if not public.rule_on('app_punch_on') then return 'app_punch_off'; end if;
  if exists (select 1 from public.att_self_lock where scope = 'person' and ref = p_emp.id::text and locked) then return 'self_punch_locked'; end if;
  if exists (select 1 from public.att_self_lock l where l.scope = 'role' and l.locked
              and (l.ref = p_emp.primary_role_code or l.ref in (select ur.role_code from public.user_roles ur where ur.user_id = p_emp.profile_id))) then return 'self_punch_locked'; end if;
  if not public.path_allowed('attendance', coalesce(p_emp.primary_location_id, 0), 'a') then return 'path_locked'; end if;
  return 'ok';
end $$;

-- ---------- 6. SELF PUNCH (a) + EVIDENCE flags (b) ----------
create or replace function public.attendance_self_punch(p_dir text default 'unknown', p_lat numeric default null, p_lng numeric default null, p_acc numeric default null,
                                                         p_ev_kind text default null, p_ev_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint; st text; dir text := case when p_dir in ('in', 'out') then p_dir else 'unknown' end; g public.att_site_geo; gf text := 'unchecked'; dist numeric;
        evs text := 'none'; evk text := null; evr text := null; rad numeric := coalesce(public.rule_num('att_geo_radius_m'), 300);
begin
  perform public._att_gate();
  if not public.rule_on('app_punch_on') then raise exception 'app_punch_off'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then raise exception 'no_employee_record'; end if;
  st := public._att_self_state54(e);
  if st = 'self_punch_locked' then raise exception 'self_punch_locked: the owner has locked self punch for you or your role'; end if;
  if st = 'path_locked' then raise exception 'path_locked: attendance path A is locked here by the owner'; end if;
  if (p_lat is null) <> (p_lng is null) or abs(coalesce(p_lat, 0)) > 90 or abs(coalesce(p_lng, 0)) > 180 or abs(coalesce(p_acc, 0)) > 1e7 then raise exception 'bad_geo'; end if;
  if p_ev_kind is not null and p_ev_kind not in ('webauthn', 'face_photo') then raise exception 'bad_evidence'; end if;
  if p_ev_kind is not null and (nullif(btrim(p_ev_ref), '') is null or char_length(p_ev_ref) > 300) then raise exception 'bad_evidence'; end if;
  if exists (select 1 from public.attendance_punches where employee_id = e.id and source = 'app' and punched_at > now() - interval '1 minute' and not void) then raise exception 'too_soon'; end if;
  if p_ev_kind is not null then
    evk := p_ev_kind; evr := btrim(p_ev_ref);
    evs := case when exists (select 1 from public.att_evidence_reg r where r.employee_id = e.id and r.kind = p_ev_kind and r.ref = evr and r.active) then 'registered' else 'unregistered' end;
  end if;
  if public.rule_on('att_geo_check_on') then
    select * into g from public.att_site_geo where location_id = e.primary_location_id;
    if p_lat is null then gf := 'no_fix';
    elsif not found then gf := 'unchecked';
    else dist := public._att_geo_m54(p_lat, p_lng, g.lat, g.lng); gf := case when dist > rad then 'outside' else 'ok' end; end if;
  end if;
  insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, created_by, evidence_kind, evidence_ref, evidence_state, geo_lat, geo_lng, geo_flag, raw)
    values (e.id, null, e.primary_location_id, 'app:' || e.id::text, date_trunc('second', now()), dir, 'app', auth.uid(), evk, evr, evs, p_lat, p_lng, gf,
            case when p_acc is null then null else jsonb_build_object('geo_accuracy_m', p_acc) end) returning id into v_id;
  perform public._att_store(e.id, public._dhaka_today());
  if (now() at time zone 'Asia/Dhaka')::time < time '06:00' then perform public._att_store(e.id, public._dhaka_today() - 1); end if;
  return jsonb_build_object('id', v_id, 'at', now(), 'direction', dir, 'evidence_state', evs, 'geo_flag', gf, 'geo_distance_m', case when dist is null then null else round(dist) end,
    'note', 'evidence_only_not_identity_proof');
end $$;

-- bos54: the old one-argument entry point keeps its name, errors and 1-minute rule; it now goes through the same locks.
create or replace function public.attendance_app_punch(p_dir text default 'unknown') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.attendance_self_punch(p_dir);   -- bos54
end $$;

-- what the logged-in person may do now (for the screen)
create or replace function public.att_my_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; st text; ev jsonb; last_p jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then return jsonb_build_object('employee', false, 'can_punch', false, 'state', 'no_employee_record'); end if;
  st := public._att_self_state54(e);
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label, 'registered_at', r.registered_at) order by r.id), '[]') into ev
    from public.att_evidence_reg r where r.employee_id = e.id and r.active;
  select to_jsonb(x) into last_p from (select punched_at, direction, evidence_state, geo_flag from public.attendance_punches
                                        where employee_id = e.id and source = 'app' and not void order by punched_at desc limit 1) x;
  return jsonb_build_object('employee', true, 'employee_id', e.id, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en, 'can_punch', st = 'ok', 'state', st, 'evidence', ev, 'last_punch', last_p,
    'geo_check_on', public.rule_on('att_geo_check_on'));
end $$;

-- owner: lock / unlock self punch for one person or one role
create or replace function public.att_self_lock_set(p_scope text, p_ref text, p_locked boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope not in ('person', 'role') then raise exception 'bad_scope'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 60 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_scope = 'person' and not exists (select 1 from public.employees where id::text = btrim(p_ref)) then raise exception 'not_found'; end if;
  if p_scope = 'role' and not exists (select 1 from public.roles where code = btrim(p_ref)) and not exists (select 1 from public.staff_roles where code = btrim(p_ref)) then raise exception 'not_found'; end if;
  insert into public.att_self_lock (scope, ref, locked, note, set_by, set_at) values (p_scope, btrim(p_ref), coalesce(p_locked, true), nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (scope, ref) do update set locked = excluded.locked, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('scope', p_scope, 'ref', btrim(p_ref), 'locked', coalesce(p_locked, true));
end $$;

create or replace function public.att_site_geo_set(p_loc int, p_lat numeric, p_lng numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'bad_geo'; end if;
  insert into public.att_site_geo (location_id, lat, lng, set_by, set_at) values (p_loc, p_lat, p_lng, auth.uid(), now())
    on conflict (location_id) do update set lat = excluded.lat, lng = excluded.lng, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('location_id', p_loc, 'lat', p_lat, 'lng', p_lng);
end $$;

-- owner / attendance manager: people at a place with their lock + evidence status
create or replace function public.att_staff_overview(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; roles_ jsonb;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en, 'role', x.primary_role_code,
      'has_login', x.profile_id is not null,
      'person_locked', exists (select 1 from public.att_self_lock l where l.scope = 'person' and l.ref = x.id::text and l.locked) and public.is_owner(),
      'evidence', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label)) from public.att_evidence_reg r where r.employee_id = x.id and r.active), '[]'::jsonb))
      order by x.employee_no nulls last, x.full_name_bn), '[]') into rows_
    from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave');
  select coalesce(jsonb_agg(jsonb_build_object('role', l.ref, 'locked', l.locked)), '[]') into roles_ from public.att_self_lock l where l.scope = 'role' and public.is_owner();
  return jsonb_build_object('location_id', p_loc, 'rows', rows_, 'role_locks', roles_, 'self_punch_master', public.rule_on('app_punch_on'),
    'limits', 'evidence_only: registration is a flag + reference, not proof of identity; fingerprint only through the external device bridge; GPS is a soft flag');
end $$;

-- evidence registration: the person himself (passkey / face photo) or owner / attendance manager (any kind incl. finger_device)
create or replace function public.att_evidence_register(p_emp uuid, p_kind text, p_ref text, p_label text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; own boolean; v bigint;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if p_kind is null or p_kind not in ('webauthn', 'face_photo', 'finger_device') then raise exception 'bad_kind'; end if;
  own := e.profile_id is not null and e.profile_id = auth.uid();
  if not (public._emp_ok(p_emp, array['attendance_manage']) or (own and p_kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 300 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_label, '')) > 80 then raise exception 'too_long: label'; end if;
  if (select count(*) from public.att_evidence_reg where employee_id = p_emp and active) >= 10 then raise exception 'too_many'; end if;
  insert into public.att_evidence_reg (employee_id, kind, ref, label, registered_by) values (p_emp, p_kind, btrim(p_ref), nullif(btrim(p_label), ''), auth.uid())
    on conflict (employee_id, kind, ref) where active do nothing returning id into v;
  if v is null then select id into v from public.att_evidence_reg where employee_id = p_emp and kind = p_kind and ref = btrim(p_ref) and active; return jsonb_build_object('id', v, 'repeat', true); end if;
  return jsonb_build_object('id', v, 'kind', p_kind, 'note', 'evidence_only_not_identity_proof');
end $$;

create or replace function public.att_evidence_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.att_evidence_reg; e public.employees;
begin
  perform public._att_gate();
  select * into r from public.att_evidence_reg where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  select * into e from public.employees where id = r.employee_id;
  if not (public._emp_ok(r.employee_id, array['attendance_manage']) or (e.profile_id is not null and e.profile_id = auth.uid() and r.kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if not r.active then return jsonb_build_object('id', p_id, 'repeat', true); end if;
  update public.att_evidence_reg set active = false, void_by = auth.uid(), void_at = now(), void_reason = btrim(p_reason) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

-- ---------- 7. MARK OTHERS (c) ----------
-- rest / source columns follow the row: anything that is not this function resets them (a plain attendance_mark, a recompute)
create or replace function public._att_days_guard54() returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bos.mark54', true), '') <> '1' then
    new.rest_minutes := null;
    new.mark_source := case when new.source = 'manual' then 'manual' end;
  end if;
  return new;
end $$;
drop trigger if exists attendance_days_guard54 on public.attendance_days;
create trigger attendance_days_guard54 before insert or update on public.attendance_days for each row execute function public._att_days_guard54();

create or replace function public.attendance_mark_others(p_emp uuid, p_day date, p_status text, p_in text, p_out text, p_rest_min int, p_source text, p_reason text,
                                                         p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_today date := public._dhaka_today(); t1 time := public._hhmm(p_in); t2 time := public._hhmm(p_out); ti timestamptz; tout timestamptz;
        worked int := 0; late int := 0; early int := 0; ot int := 0; ss timestamptz; se timestamptz; v_kind text := 'normal'; hol public.holidays; v_appr boolean; rest int; prev jsonb; old public.attendance_days;
        lg public.att_mark_log54; sid text;
begin
  perform public._att_gate();
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into lg from public.att_mark_log54 where client_id = p_client;
    if found then
      if lg.marked_by is distinct from auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('employee_id', lg.employee_id, 'day', lg.day, 'status', lg.status, 'source_tag', lg.source_tag, 'duplicate', true);
    end if;
  end if;
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not (public.is_owner() or (e.primary_location_id is not null and public.can_loc(e.primary_location_id) and public.has_grant('attendance_mark_others', e.primary_location_id))) then raise exception 'not allowed'; end if;
  if e.profile_id is not null and e.profile_id = auth.uid() and not public.is_owner() then raise exception 'cannot_mark_self'; end if;
  perform public.path_guard('attendance', coalesce(e.primary_location_id, 0), 'a');
  if p_day is null or p_day > v_today or p_day < v_today - 62 then raise exception 'bad_date'; end if;
  if e.joining_date is not null and p_day < e.joining_date then raise exception 'bad_date'; end if;
  if p_status not in ('present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid') then raise exception 'bad_status'; end if;
  if p_source is null or p_source not in ('device', 'finger', 'face', 'manual') then raise exception 'bad_source'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_rest_min is not null and (p_rest_min < 0 or p_rest_min > 720) then raise exception 'bad_rest'; end if;
  if (p_in is not null and btrim(p_in) <> '' and t1 is null) or (p_out is not null and btrim(p_out) <> '' and t2 is null) then raise exception 'bad_time'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  if p_status = 'absent' then t1 := null; t2 := null; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  if t1 is not null then ti := (p_day + t1) at time zone 'Asia/Dhaka'; end if;
  if t2 is not null then tout := (p_day + t2 + case when t1 is not null and t2 <= t1 then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka'; end if;
  rest := case when p_status = 'absent' then null else coalesce(p_rest_min, s.break_min, 0) end;
  if ti is not null and tout is not null then worked := greatest(0, floor(extract(epoch from (tout - ti)) / 60)::int - coalesce(rest, 0)); end if;
  if s.id is not null and ti is not null and v_kind = 'normal' then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    if ti > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (ti - ss)) / 60)::int; end if;
    if tout is not null and tout < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - tout)) / 60)::int; end if;
    if tout is not null and tout > se then ot := least(1440, floor(extract(epoch from (tout - se)) / 60)::int); end if;
  end if;
  if p_status in ('absent', 'off', 'holiday', 'unpaid') then late := 0; early := 0; end if;
  if p_status = 'late' and late = 0 then late := 1; end if;
  v_appr := public.is_owner() and public.rule_on('owner_self_approve');
  select * into old from public.attendance_days where employee_id = p_emp and day = p_day;
  prev := case when found then to_jsonb(old) end;
  perform set_config('bos.mark54', '1', true);
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, marked_by, marked_at, approved_by, approved_at, override_reason, note, computed_at, rest_minutes, mark_source)
    values (p_emp, p_day, p_status, v_kind, ti, tout, worked, late, early, ot, v_appr, 0, false, s.id, e.primary_location_id, null,
      case when p_status = 'holiday' then coalesce(hol.paid, true) when p_status = 'unpaid' then false end, 'manual', auth.uid(), now(),
      case when v_appr then auth.uid() end, case when v_appr then now() end, btrim(p_reason), nullif(btrim(p_note), ''), now(), rest, p_source)
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes, ot_minutes = excluded.ot_minutes,
      ot_approved = excluded.ot_approved, punch_count = a.punch_count, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = null, paid_day = excluded.paid_day,
      source = 'manual', marked_by = excluded.marked_by, marked_at = excluded.marked_at, approved_by = excluded.approved_by, approved_at = excluded.approved_at,
      override_reason = excluded.override_reason, note = excluded.note, computed_at = now(), rest_minutes = excluded.rest_minutes, mark_source = excluded.mark_source;
  perform set_config('bos.mark54', '', true);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.att_mark_log54 (client_id, employee_id, location_id, day, source_tag, status, first_in, last_out, rest_minutes, ot_minutes, reason, note, prev, approved, marked_by, marked_staff)
    values (p_client, p_emp, e.primary_location_id, p_day, p_source, p_status, ti, tout, rest, ot, btrim(p_reason), nullif(btrim(p_note), ''), prev, v_appr, auth.uid(), sid);
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'status', p_status, 'source', 'manual', 'source_tag', p_source, 'approved', v_appr, 'late_minutes', late,
    'ot_minutes', ot, 'rest_minutes', rest, 'worked_minutes', worked, 'note', 'source_tag_is_the_markers_declaration_not_proof');
end $$;

-- the board for a person who holds the new grant (attendance_board needs attendance_manage / employee_view)
create or replace function public.att_others_board(p_loc int, p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, public._dhaka_today()); rows_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or (p_loc is not null and public.can_loc(p_loc) and public.has_grant('attendance_mark_others', p_loc))) then raise exception 'not allowed'; end if;
  if d > public._dhaka_today() or d < date '2020-01-01' then raise exception 'bad_date'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en,
      'is_me', x.profile_id is not null and x.profile_id = auth.uid(),
      'status', j ->> 'status', 'first_in', j ->> 'first_in', 'last_out', j ->> 'last_out', 'worked_minutes', (j ->> 'worked_minutes')::int, 'rest_minutes', a.rest_minutes,
      'ot_minutes', (j ->> 'ot_minutes')::int, 'source', coalesce(j ->> 'source', 'auto'), 'mark_source', a.mark_source,
      'pending', (j ->> 'source') = 'manual' and (j ->> 'approved_by') is null, 'stored', a.employee_id is not null) order by x.employee_no nulls last, x.full_name_bn), '[]')
    into rows_
    from public.employees x
    left join public.attendance_days a on a.employee_id = x.id and a.day = d
    cross join lateral (select coalesce(to_jsonb(a.*), public._att_derive(x.id, d)) as j) q
   where x.primary_location_id = p_loc and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and x.status_date >= d))
     and (x.joining_date is null or x.joining_date <= d);
  return jsonb_build_object('day', d, 'location_id', p_loc, 'rows', rows_);
end $$;

-- ---------- 8. TWO PATHS COUNTED ONCE: guard, link, report ----------
create or replace function public._entries_att_guard54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.form_code = '02-1' and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard('attendance', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_att_guard54 on public.entries;
create trigger entries_att_guard54 before insert on public.entries for each row execute function public._entries_att_guard54();

-- does path A hold records for this place + month?
create or replace function public._att_month_has_a54(p_loc int, p_month date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.attendance_days d where d.location_id = p_loc and d.day >= p_month and d.day < (p_month + interval '1 month')::date)
      or exists (select 1 from public.attendance_punches p where p.location_id = p_loc and not p.void and p.punched_at >= (p_month::timestamp at time zone 'Asia/Dhaka')
                  and p.punched_at < ((p_month + interval '1 month')::timestamp at time zone 'Asia/Dhaka'));
$$;

create or replace function public._att_form_month54(p_data jsonb, p_date date) returns date
language sql immutable as $$
  select coalesce(case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end, date_trunc('month', p_date)::date);
$$;

-- link one submitted / approved 02-1 as a shadow when path A is the record for its month. Returns 'linked' | 'already' | 'form_is_primary' | 'path_a_empty' | 'skip'
create or replace function public._att_form_link54(p_entry uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.entries; m date; k text;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '02-1' or e.status not in ('submitted', 'approved') then return 'skip'; end if;
  if public.is_shadow('entries', e.id::text) then return 'already'; end if;
  if public.path_primary('attendance', e.location_id) <> 'a' then return 'form_is_primary'; end if;
  m := public._att_form_month54(e.data, e.entry_date);
  if not public._att_month_has_a54(e.location_id, m) then return 'path_a_empty'; end if;
  k := e.location_id::text || ':' || to_char(m, 'YYYY-MM');
  if exists (select 1 from public.shadow_links x where x.domain = 'attendance' and x.primary_type = 'attendance_month' and x.primary_id = k and x.shadow_type = 'entries' and x.state <> 'void') then return 'already'; end if;
  perform public.shadow_link_add('attendance', e.location_id, 'attendance_month', k, 'entries', e.id::text, 'bos54 02-1 shadow of staff attendance');
  return 'linked';
end $$;

create or replace function public._entries_att_link54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_form_link54(new.id);
  return null;
end $$;
drop trigger if exists entries_att_link54 on public.entries;
create trigger entries_att_link54 after update of status on public.entries for each row
  when (new.form_code = '02-1' and new.status in ('submitted', 'approved') and old.status is distinct from new.status) execute function public._entries_att_link54();

-- the manager's "link now" for a month whose punches arrived after the form
create or replace function public.attendance_form_link_run(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m date := date_trunc('month', p_month)::date; res jsonb := '{}'::jsonb; x text;
begin
  perform public._att_gate();
  if not (public.is_owner() or (public.can_loc(p_loc) and public.has_grant('attendance_manage', p_loc))) then raise exception 'not allowed'; end if;
  for r in select e.id from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m order by e.serial loop
    x := public._att_form_link54(r.id);
    res := res || jsonb_build_object(x, coalesce((res ->> x)::int, 0) + 1);
  end loop;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'result', res);
end $$;

-- read-only: per person, what path A says vs what the 02-1 register says, and which one is counted
create or replace function public.attendance_count_once(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; m2 date; cfg jsonb; rows_ jsonb; forms_ jsonb; mism int;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  if p_month is null or m > public._dhaka_today() or m < date '2020-01-01' then raise exception 'bad_date'; end if;
  m2 := (m + interval '1 month')::date;
  cfg := public.path_cfg('attendance', p_loc);
  with emp as (select x.id, x.employee_no, x.full_name_bn, x.full_name_en from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave', 'resigned', 'terminated', 'retired')),
  dv as (select a.employee_id,
                count(*) filter (where a.status in ('present', 'late')) + 0.5 * count(*) filter (where a.status = 'half_day') as present,
                count(*) filter (where a.status = 'late') as late, count(*) filter (where a.status = 'absent') as absent, round(sum(a.ot_minutes) / 60.0, 2) as ot_hours
           from public.attendance_days a where a.day >= m and a.day < m2 group by a.employee_id),
  fm as (select e.id as entry_id, r as row_ from public.entries e
           cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
          where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = p_loc and public._att_form_month54(e.data, e.entry_date) = m
            and btrim(coalesce(r ->> 'name', '')) <> ''),
  fx as (select emp.id as employee_id,
                sum(coalesce(public._db_num(fm.row_ -> 'present'), 0)) as present, sum(coalesce(public._db_num(fm.row_ -> 'late'), 0)) as late,
                sum(coalesce(public._db_num(fm.row_ -> 'absent'), 0)) as absent, sum(coalesce(public._db_num(fm.row_ -> 'ot_hours'), 0)) as ot_hours, count(*) as lines
           from emp join fm on lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_bn)) or (nullif(btrim(emp.full_name_en), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_en)))
                                or (nullif(btrim(emp.employee_no), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.employee_no)))
          group by emp.id),
  j as (select emp.id, emp.employee_no, emp.full_name_bn, emp.full_name_en, dv.present as d_present, dv.late as d_late, dv.absent as d_absent, dv.ot_hours as d_ot,
               fx.present as f_present, fx.late as f_late, fx.absent as f_absent, fx.ot_hours as f_ot, fx.lines as f_lines,
               (dv.employee_id is not null and fx.employee_id is not null and (dv.present <> fx.present or dv.late <> fx.late or dv.absent <> fx.absent or abs(coalesce(dv.ot_hours, 0) - fx.ot_hours) > 0.5)) as mismatch
          from emp left join dv on dv.employee_id = emp.id left join fx on fx.employee_id = emp.id where dv.employee_id is not null or fx.employee_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', j.id, 'employee_no', j.employee_no, 'name_bn', j.full_name_bn, 'name_en', j.full_name_en,
           'device', case when j.d_present is null and j.d_absent is null then null else jsonb_build_object('present', j.d_present, 'late', j.d_late, 'absent', j.d_absent, 'ot_hours', j.d_ot) end,
           'form', case when j.f_lines is null then null else jsonb_build_object('present', j.f_present, 'late', j.f_late, 'absent', j.f_absent, 'ot_hours', j.f_ot) end,
           'mismatch', j.mismatch) order by j.employee_no nulls last, j.full_name_bn), '[]'), count(*) filter (where j.mismatch)
    into rows_, mism from j;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status, 'is_shadow', public.is_shadow('entries', e.id::text)) order by e.serial), '[]') into forms_
    from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'primary', cfg ->> 'primary', 'a_open', cfg -> 'a_open', 'b_open', cfg -> 'b_open',
    'counted', case when cfg ->> 'primary' = 'b' then 'form_02_1' else 'attendance_record' end,
    'path_a_has_month', public._att_month_has_a54(p_loc, m), 'forms', forms_, 'rows', rows_, 'mismatches', mism,
    'limits', 'People are matched by name / employee no. written on the register; a difference is a prompt to look, not a verdict.');
end $$;

-- ---------- 9. EQUATION RECOMPUTE (gap #20, read-only) ----------
create or replace function public._eq_limit54(p_loc int, p_key text, p_date date) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  begin v := public.get_limit(p_loc, p_key, p_date); exception when others then return null; end;
  return public._db_num(v);
end $$;

create or replace function public._eq_truthy54(j jsonb) returns boolean language sql immutable as $$
  select coalesce(j = 'true'::jsonb or j = '"true"'::jsonb or j = '"yes"'::jsonb or j = '"1"'::jsonb or j = '1'::jsonb, false);
$$;

-- the engine: no permission check (callers do it); returns {form, supported, recomputed, mismatches, observations, ok}
create or replace function public._eq_check54(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := coalesce(e.data, '{}'::jsonb); lines jsonb; r jsonb; rc jsonb;
        total numeric := 0; amt numeric; norec numeric := 0; maxa numeric := 0; lim numeric; imp numeric; cashn numeric; rcpt numeric; diff numeric;
        exp_ jsonb := '{}'::jsonb;      -- expected flags: code -> amount (null amount = flag without amount)
        mism jsonb := '[]'::jsonb; obs jsonb := '[]'::jsonb; rec jsonb := '{}'::jsonb; k text; c text; st jsonb;
        neg int := 0; noreason int := 0; unsigned boolean := false; t_due numeric := 0; t_ot numeric := 0; t_other numeric := 0; t_adv numeric := 0; t_od numeric := 0; g numeric; n numeric; any_ boolean; t_rc numeric := 0;
        codes text[];
begin
  if e.form_code = '10-2' then
    codes := array['imprest_mismatch', 'no_receipt', 'over_limit'];
    lines := case when jsonb_typeof(d -> 'lines') = 'array' then d -> 'lines' else '[]'::jsonb end;
    lim := public._eq_limit54(e.location_id, 'expense_max', e.entry_date);
    imp := public._eq_limit54(e.location_id, 'imprest', e.entry_date);
    for r in select * from jsonb_array_elements(lines) loop
      amt := coalesce(public._db_num(r -> 'amount'), 0);
      total := total + amt; maxa := greatest(maxa, amt);
      if r ->> 'receipt' = 'no' and amt > 0 then norec := norec + amt; end if;
    end loop;
    cashn := public._db_num(d -> 'cash_now'); rcpt := coalesce(public._db_num(d -> 'receipts_total'), 0);
    if lim is not null and maxa > lim then exp_ := exp_ || jsonb_build_object('over_limit', maxa); end if;
    if norec > 0 then exp_ := exp_ || jsonb_build_object('no_receipt', norec); end if;
    if imp is not null and cashn is not null then
      diff := coalesce(cashn, 0) + rcpt - imp;
      if diff <> 0 then exp_ := exp_ || jsonb_build_object('imprest_mismatch', diff); end if;
    end if;
    rec := jsonb_build_object('total', total, 'cash_plus_receipts', coalesce(cashn, 0) + rcpt, 'imprest', imp, 'expense_max', lim, 'imprest_diff', diff, 'no_receipt_amount', norec);
  elsif e.form_code = '02-2' then
    codes := array['net_negative', 'other_no_reason', 'paid_unsigned'];
    lines := case when jsonb_typeof(d -> 'pay') = 'array' then d -> 'pay' else '[]'::jsonb end;
    for r in select * from jsonb_array_elements(lines) loop
      any_ := exists (select 1 from jsonb_each_text(case when jsonb_typeof(r) = 'object' then r else '{}'::jsonb end) kv where btrim(kv.value) <> '');
      g := coalesce(public._db_num(r -> 'due'), 0) + coalesce(public._db_num(r -> 'overtime'), 0) + coalesce(public._db_num(r -> 'other'), 0);
      n := g - coalesce(public._db_num(r -> 'adv_ded'), 0) - coalesce(public._db_num(r -> 'other_ded'), 0);
      t_due := t_due + coalesce(public._db_num(r -> 'due'), 0); t_ot := t_ot + coalesce(public._db_num(r -> 'overtime'), 0); t_other := t_other + coalesce(public._db_num(r -> 'other'), 0);
      t_adv := t_adv + coalesce(public._db_num(r -> 'adv_ded'), 0); t_od := t_od + coalesce(public._db_num(r -> 'other_ded'), 0);
      if any_ then
        if n < 0 then neg := neg + 1; end if;
        if (coalesce(public._db_num(r -> 'other'), 0) > 0 or coalesce(public._db_num(r -> 'other_ded'), 0) > 0) and nullif(btrim(coalesce(r ->> 'remark', '')), '') is null then noreason := noreason + 1; end if;
      end if;
    end loop;
    for r in select * from jsonb_array_elements(case when jsonb_typeof(d -> 'receipts') = 'array' then d -> 'receipts' else '[]'::jsonb end) loop
      t_rc := t_rc + coalesce(public._db_num(r -> 'net'), 0);
      if coalesce(public._db_num(r -> 'net'), 0) > 0 and not public._eq_truthy54(r -> 'signed') then unsigned := true; end if;
    end loop;
    if neg > 0 then exp_ := exp_ || jsonb_build_object('net_negative', neg); end if;
    if noreason > 0 then exp_ := exp_ || jsonb_build_object('other_no_reason', noreason); end if;
    if unsigned then exp_ := exp_ || jsonb_build_object('paid_unsigned', null); end if;
    rec := jsonb_build_object('t_due', t_due, 't_ot', t_ot, 't_other', t_other, 't_gross', t_due + t_ot + t_other, 't_adv', t_adv, 't_other_ded', t_od,
                              't_net', t_due + t_ot + t_other - t_adv - t_od, 't_receipts', t_rc, 'negative_net_people', neg, 'other_without_reason', noreason);
    if abs(t_rc - (t_due + t_ot + t_other - t_adv - t_od)) > 0.004 and t_rc > 0 then
      obs := obs || jsonb_build_array(jsonb_build_object('code', 'receipts_vs_net', 'receipts_total', t_rc, 'sheet_net', t_due + t_ot + t_other - t_adv - t_od,
                                                          'note', 'information only: the receipt acknowledgement does not add up to the sheet net'));
    end if;
  else
    return jsonb_build_object('form', e.form_code, 'supported', false, 'ok', true, 'mismatches', '[]'::jsonb, 'why', 'only 10-2 and 02-2 are re-worked; 14-1 is not');
  end if;
  -- compare to the flags the phone stored
  foreach c in array codes loop
    select x into st from jsonb_array_elements(coalesce(e.flags, '[]'::jsonb)) x where x ->> 'code' = c limit 1;
    if exp_ ? c and st is null then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_missing', 'recomputed', exp_ -> c, 'stored', null));
    elsif not (exp_ ? c) and st is not null and st ->> 'level' = 'red' then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_extra', 'recomputed', null, 'stored', st -> 'amount'));
    elsif exp_ ? c and st is not null and jsonb_typeof(exp_ -> c) = 'number' and public._db_num(st -> 'amount') is distinct from (exp_ ->> c)::numeric then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'amount_differs', 'recomputed', exp_ -> c, 'stored', st -> 'amount'));
    end if;
  end loop;
  return jsonb_build_object('form', e.form_code, 'supported', true, 'recomputed', rec, 'expected_flags', exp_, 'mismatches', mism, 'observations', obs, 'ok', jsonb_array_length(mism) = 0,
    'note', 'limits (expense_max, imprest) are read as they are today; a limit changed after the sheet was saved can show as a difference');
end $$;

create or replace function public.entry_equation_check(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (public.can_loc(e.location_id) and (public.can_do(e.form_code, 'view') or public.can_do(e.form_code, 'enter') or e.created_by = auth.uid()))) then raise exception 'not allowed'; end if;
  return public._eq_check54(e) || jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status);
end $$;

-- optional (switch entry_equation_flag_on, default OFF): at the end of the submitting transaction, one red exception when the stored flags differ from the re-work.
-- A deferred constraint trigger, so submit_entry (which clears and rewrites open exceptions) is not touched and cannot erase it.
create or replace function public._entries_eq_flag54() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.entries; res jsonb;
begin
  if not public.rule_on('entry_equation_flag_on') then return null; end if;
  select * into e from public.entries where id = new.id;
  if not found or e.status not in ('submitted', 'approved') then return null; end if;
  res := public._eq_check54(e);
  if coalesce((res ->> 'ok')::boolean, true) then return null; end if;
  if not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'equation_mismatch' and x.status = 'open') then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'equation_mismatch', 'red', null,
              jsonb_build_object('bn', 'ফোনের হিসাব আর সার্ভারের পুনঃহিসাব মেলেনি — ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m),
                                 'en', 'Phone totals and the server re-work differ: ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m)));
  end if;
  return null;
end $$;
drop trigger if exists entries_eq_flag54 on public.entries;
create constraint trigger entries_eq_flag54 after update of status on public.entries deferrable initially deferred for each row
  when (new.form_code in ('10-2', '02-2') and new.status = 'submitted' and old.status is distinct from new.status) execute function public._entries_eq_flag54();

-- ---------- 10. rights ----------
revoke all on function public._att_geo_m54(numeric, numeric, numeric, numeric), public._att_self_state54(public.employees), public._att_log_ro54(), public._att_days_guard54(),
  public._entries_att_guard54(), public._att_month_has_a54(int, date), public._att_form_month54(jsonb, date), public._att_form_link54(uuid), public._entries_att_link54(),
  public._eq_limit54(int, text, date), public._eq_truthy54(jsonb), public._eq_check54(public.entries), public._entries_eq_flag54() from public, anon, authenticated;
revoke all on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) from public, anon;
grant execute on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) to authenticated;

-- ---------------------------------------------------------------- phase60.sql
-- ============================================================
-- BOS tool · Phase 60 (P3 gaps #7-#10): reorder suggestion, wastage reasons report, batch/expiry on GRN, QC records.
-- ADDITIVE + paste-twice safe. stock_post / stock_wastage are NOT changed. Everything is tagged bos60.
--  #7 reorder_report()      read-only: stock on hand, min_stock, average daily usage over N days, owner-set lead days. No purchase order is made.
--  #8 wastage reasons       more reasons in option_lists 'wastage_reasons' (insert-if-missing); wastage_by_reason() report. Old rows untouched.
--  #9 grn_batch_add()       capture batch no + expiry for goods received (purchase bill or GRN 04-1) into the EXISTING stock_batches
--                           (+ batch_no column, append-only link table). near_expiry_report(), fefo_hint(). stock_post already picks FEFO.
--  #10 qc_record()          append-only quality check per production run or GRN: checklist from option list 'qc_checks', pass/hold/reject.
--                           Nothing is blocked unless the owner switches quality_block_on ON (default OFF).
-- ============================================================

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('reorder_lookback_days', 'stock', 'number', '30', 'days', null, 1, 365, 'রিঅর্ডার: কত দিনের গড় ব্যবহার দেখা হবে', 'Reorder: কত দিনের গড় usage', 'Reorder: days of usage to average', 'Average daily usage = sales + production issues over this many days', 600),
 ('reorder_lead_days', 'stock', 'number', '3', 'days', null, 0, 120, 'সাপ্লায়ার মাল দিতে কত দিন লাগে (লিড ডে)', 'Supplier lead days (মাল আসতে কত দিন)', 'Supplier lead days', 'Set by the owner. Used only for the suggestion; no order is placed', 601),
 ('reorder_cover_days', 'stock', 'number', '7', 'days', null, 0, 365, 'রিঅর্ডারে কত দিনের বাড়তি মাল চাই', 'Reorder এ কত দিনের extra cover', 'Extra days of cover to order', 'Suggested qty = average daily usage x (lead + cover days) - on hand', 602),
 ('expiry_warn_days', 'stock', 'number', '7', 'days', null, 0, 365, 'মেয়াদ শেষের কত দিন আগে সতর্কতা', 'মেয়াদ শেষের কত দিন আগে warning', 'Warn this many days before expiry', 'Used by the near-expiry report', 603),
 ('quality_block_on', 'stock', 'switch', 'false', null, null, null, null, 'কোয়ালিটি হোল্ড/রিজেক্ট হলে ব্যাচ আটকাও', 'Quality hold/reject হলে batch আটকাও', 'Block held / rejected batches', 'OFF = QC is only a record. ON = a held/rejected GRN cannot get new batches and its batches are marked blocked; a red line is raised', 604)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('grn_batch', 'stock', 47, 'প্রাপ্ত মালের ব্যাচ নং ও মেয়াদ লেখা', 'Receive করা মালের batch no ও expiry লেখা', 'Record batch no and expiry of received goods', 'once', null),
   ('qc_record', 'stock', 48, 'কোয়ালিটি চেক লেখা', 'Quality check লেখা', 'Record a quality check', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('grn_batch', 'storekeeper'), ('grn_batch', 'purchasing'), ('grn_batch', 'factory_incharge'),
    ('qc_record', 'storekeeper'), ('qc_record', 'factory_incharge'), ('qc_record', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'qc_reject', 'কোয়ালিটিতে বাতিল', 'Quality তে reject', 'Rejected by quality check', 7),
 ('wastage_reasons', 'spillage', 'ছিটকে / পড়ে গেছে', 'ছিটকে / spillage', 'Spillage', 8),
 ('wastage_reasons', 'overproduction', 'বেশি বানানো হয়েছে', 'বেশি production', 'Over-production', 10),
 ('wastage_reasons', 'weight_loss', 'ওজন কমে গেছে', 'ওজন loss', 'Weight loss / shrinkage', 11),
 ('wastage_reasons', 'pest', 'পোকা / ইঁদুর', 'পোকা / pest', 'Pest damage', 12),
 ('wastage_reasons', 'power_cut', 'বিদ্যুৎ না থাকায় নষ্ট', 'Power cut এ নষ্ট', 'Lost to power cut', 13),
 ('qc_checks', 'appearance', 'দেখতে ঠিক', 'দেখতে ঠিক (appearance)', 'Appearance', 1),
 ('qc_checks', 'smell', 'গন্ধ ঠিক', 'গন্ধ ঠিক (smell)', 'Smell', 2),
 ('qc_checks', 'taste', 'স্বাদ ঠিক', 'স্বাদ ঠিক (taste)', 'Taste', 3),
 ('qc_checks', 'weight', 'ওজন ঠিক', 'ওজন ঠিক (weight)', 'Weight', 4),
 ('qc_checks', 'packaging', 'প্যাকেট ঠিক', 'প্যাকেট ঠিক (packaging)', 'Packaging intact', 5),
 ('qc_checks', 'label', 'লেবেল / মেয়াদ লেখা', 'Label / expiry printed', 'Label / expiry printed', 6),
 ('qc_checks', 'temperature', 'তাপমাত্রা ঠিক', 'তাপমাত্রা (temperature)', 'Temperature', 7),
 ('qc_checks', 'foreign', 'বাইরের কিছু নেই', 'কোনো foreign matter নেই', 'No foreign matter', 8)
on conflict (list_code, value_code) do nothing;

-- ---------- tables ----------
alter table public.stock_batches add column if not exists batch_no text;      -- bos60: the supplier's / our own batch number (null on older batches)

create table if not exists public.grn_batch_links (
  id bigserial primary key,
  batch_id bigint not null unique,                       -- (no FK on purpose: a truncate of the stock tables must still hit the ledger trigger first)
  source_type text not null check (source_type in ('purchase', 'grn')),
  source_id uuid not null,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  batch_no text not null check (length(batch_no) between 1 and 40),
  expiry_date date not null,
  qty_base numeric not null check (qty_base > 0 and qty_base <= 1000000000000),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists grn_batch_links_no on public.grn_batch_links (item_id, location_id, lower(batch_no));
create index if not exists grn_batch_links_src on public.grn_batch_links (source_type, source_id);

create table if not exists public.qc_records (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  source_type text not null check (source_type in ('production', 'grn')),
  source_id uuid not null,
  location_id int not null references public.locations(id),
  status text not null check (status in ('pass', 'hold', 'reject')),
  checks jsonb not null default '[]'::jsonb,
  note text check (note is null or length(note) <= 300),
  photo text check (photo is null or length(photo) <= 300),
  supersedes_id uuid references public.qc_records(id),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists qc_records_src on public.qc_records (source_type, source_id, created_at desc);
create index if not exists qc_records_loc on public.qc_records (location_id, created_at);

create or replace function public._append_only60() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists qc_records_ro on public.qc_records;
create trigger qc_records_ro before update or delete on public.qc_records for each row execute function public._append_only60();
drop trigger if exists qc_records_ro_t on public.qc_records;
create trigger qc_records_ro_t before truncate on public.qc_records for each statement execute function public._append_only60();
drop trigger if exists grn_batch_links_ro on public.grn_batch_links;
create trigger grn_batch_links_ro before update or delete on public.grn_batch_links for each row execute function public._append_only60();
drop trigger if exists grn_batch_links_ro_t on public.grn_batch_links;
create trigger grn_batch_links_ro_t before truncate on public.grn_batch_links for each statement execute function public._append_only60();
drop trigger if exists audit_qc_records on public.qc_records;
create trigger audit_qc_records after insert on public.qc_records for each row execute function public.log_change('id');
drop trigger if exists audit_grn_batch_links on public.grn_batch_links;
create trigger audit_grn_batch_links after insert on public.grn_batch_links for each row execute function public.log_change('id');

alter table public.grn_batch_links enable row level security;
alter table public.qc_records enable row level security;
drop policy if exists grn_batch_links_read on public.grn_batch_links;
create policy grn_batch_links_read on public.grn_batch_links for select to authenticated using (public.can_loc(location_id));
drop policy if exists qc_records_read on public.qc_records;
create policy qc_records_read on public.qc_records for select to authenticated using (public.can_loc(location_id));
revoke all on public.grn_batch_links, public.qc_records from public, anon, authenticated;
grant select on public.grn_batch_links, public.qc_records to authenticated;
revoke all on sequence public.grn_batch_links_id_seq from public, anon, authenticated;

-- ---------- #10 helpers + QC ----------
-- latest QC status of one source (null = never checked)
create or replace function public._qc_latest60(p_type text, p_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select status from public.qc_records where source_type = p_type and source_id = p_id order by created_at desc, id desc limit 1;
$$;

-- is this batch blocked by quality? Only when the owner switched quality_block_on ON.
create or replace function public._qc_batch_blocked60(p_batch bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rule_on('quality_block_on') and (
    exists (select 1 from public.grn_batch_links l where l.batch_id = p_batch and public._qc_latest60('grn', l.source_id) in ('hold', 'reject'))
    or exists (select 1 from public.production_runs r where r.batch_id = p_batch and public._qc_latest60('production', r.id) in ('hold', 'reject')));
$$;

-- QC state of a source for any screen: {status, blocked, switch_on}
create or replace function public.qc_gate(p_source_type text, p_source_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  st := public._qc_latest60(p_source_type, p_source_id);
  return jsonb_build_object('status', st, 'switch_on', public.rule_on('quality_block_on'),
    'blocked', public.rule_on('quality_block_on') and st in ('hold', 'reject'));
end $$;

create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb default '[]'::jsonb,
  p_note text default null, p_photo text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; sid text; prev public.qc_records; rid uuid; c jsonb; codes text[] := '{}'; code text; bad int := 0; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.qc_records where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id, 'status', prev.status);
    end if;
  end if;
  if p_source_type is null or p_source_type not in ('production', 'grn') then raise exception 'bad_source'; end if;
  if p_source_id is null then raise exception 'bad_source'; end if;
  if p_status is null or p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  if p_source_type = 'production' then
    select location_id into loc from public.production_runs where id = p_source_id;
  else
    select location_id into loc from public.entries where id = p_source_id and form_code = '04-1';
    if loc is null then select location_id into loc from public.purchase_bills where id = p_source_id and kind = 'bill' and status = 'posted'; end if;
  end if;
  if loc is null then raise exception 'source_not_found'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('qc_record', loc)) then raise exception 'not allowed'; end if;
  if p_checks is null or jsonb_typeof(p_checks) <> 'array' or jsonb_array_length(p_checks) > 30 then raise exception 'bad_checks'; end if;
  for c in select * from jsonb_array_elements(p_checks) loop
    if jsonb_typeof(c) <> 'object' or jsonb_typeof(c->'ok') <> 'boolean' or jsonb_typeof(c->'code') <> 'string' then raise exception 'bad_checks'; end if;
    code := c->>'code';
    if code = any (codes) then raise exception 'bad_checks'; end if;
    if not exists (select 1 from public.option_lists where list_code = 'qc_checks' and value_code = code and active) then raise exception 'bad_check_code'; end if;
    codes := codes || code;
    if not (c->>'ok')::boolean then bad := bad + 1; end if;
  end loop;
  if p_status = 'pass' and bad > 0 then raise exception 'pass_has_failed_check'; end if;
  if p_status <> 'pass' and (n is null or length(n) < 3) then raise exception 'note_required'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  select * into prev from public.qc_records where source_type = p_source_type and source_id = p_source_id order by created_at desc, id desc limit 1;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.qc_records (client_id, source_type, source_id, location_id, status, checks, note, photo, supersedes_id, created_by, created_staff)
    values (p_client, p_source_type, p_source_id, loc, p_status, p_checks, n, nullif(btrim(p_photo), ''), prev.id, auth.uid(), sid) returning id into rid;
  if p_status in ('hold', 'reject') then
    perform public._stock_exc(loc, 'qc_' || p_status, case when public.rule_on('quality_block_on') then 'red' else 'yellow' end,
      'কোয়ালিটি চেকে ' || case p_status when 'hold' then 'আটক' else 'বাতিল' end || ' (' || p_source_type || ')',
      'Quality check: ' || p_status || ' (' || p_source_type || ')', null, null, 'QC');
  end if;
  return jsonb_build_object('id', rid, 'status', p_status, 'failed', bad, 'blocked', public.rule_on('quality_block_on') and p_status in ('hold', 'reject'));
end $$;

-- latest QC per source (one line each), newest first
create or replace function public.qc_list(p_loc int default null, p_from date default null, p_to date default null, p_status text default null)
returns table (id uuid, source_type text, source_id uuid, location_id int, status text, checks jsonb, note text, created_at timestamptz, created_staff text, history_n bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_status is not null and p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  return query
    select q.id, q.source_type, q.source_id, q.location_id, q.status, q.checks, q.note, q.created_at, q.created_staff,
           (select count(*) from public.qc_records h where h.source_type = q.source_type and h.source_id = q.source_id)
    from public.qc_records q
    where q.id = (select x.id from public.qc_records x where x.source_type = q.source_type and x.source_id = q.source_id order by x.created_at desc, x.id desc limit 1)
      and public.can_loc(q.location_id) and (p_loc is null or q.location_id = p_loc)
      and (p_status is null or q.status = p_status)
      and (p_from is null or (q.created_at at time zone 'Asia/Dhaka')::date >= p_from)
      and (p_to is null or (q.created_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by q.created_at desc limit 200;
end $$;

-- full trail of one source
create or replace function public.qc_history(p_source_type text, p_source_id uuid)
returns table (id uuid, status text, checks jsonb, note text, photo text, supersedes_id uuid, created_at timestamptz, created_staff text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query select q.id, q.status, q.checks, q.note, q.photo, q.supersedes_id, q.created_at, q.created_staff
    from public.qc_records q where q.source_type = p_source_type and q.source_id = p_source_id and public.can_loc(q.location_id)
    order by q.created_at, q.id;
end $$;

-- ---------- #9 batch + expiry on received goods ----------
create or replace function public.grn_batch_add(p_source_type text, p_source_id uuid, p_item uuid, p_qty numeric, p_unit text,
  p_batch_no text, p_expiry date, p_made date default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; it public.items; bq numeric; bn text := btrim(p_batch_no); today date := (now() at time zone 'Asia/Dhaka')::date; bid bigint; lk public.grn_batch_links;
        recv numeric; used numeric; free numeric; code text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into lk from public.grn_batch_links where client_id = p_client;
    if found then
      if lk.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'batch_id', lk.batch_id);
    end if;
  end if;
  if p_source_type is null or p_source_type not in ('purchase', 'grn') or p_source_id is null then raise exception 'bad_source'; end if;
  if p_source_type = 'purchase' then
    select location_id into loc from public.purchase_bills where id = p_source_id and kind = 'bill' and status = 'posted';
  else
    select location_id into loc from public.entries where id = p_source_id and form_code = '04-1' and status in ('submitted', 'approved');
  end if;
  if loc is null then raise exception 'source_not_found'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('grn_batch', loc)) then raise exception 'not allowed'; end if;
  it := public._stock_guard(p_item, loc, 'grn_batch', today);
  if bn is null or length(bn) not between 1 and 40 then raise exception 'bad_batch_no'; end if;
  if p_expiry is null or p_expiry < today or p_expiry > today + 3650 then raise exception 'bad_expiry'; end if;
  if p_made is not null and (p_made > today or p_made < today - 3650) then raise exception 'bad_made_date'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if public.rule_on('quality_block_on') and public._qc_latest60('grn', p_source_id) in ('hold', 'reject') then raise exception 'qc_blocked'; end if;
  if exists (select 1 from public.grn_batch_links where item_id = p_item and location_id = loc and lower(batch_no) = lower(bn)) then raise exception 'batch_no_exists'; end if;
  -- the stock row is locked: nobody else changes this item's balance or batches meanwhile
  insert into public.stock_balance (item_id, location_id) values (p_item, loc) on conflict do nothing;
  perform 1 from public.stock_balance where item_id = p_item and location_id = loc for update;
  if p_source_type = 'purchase' then
    select coalesce(sum(base_qty), 0) into recv from public.purchase_lines where bill_id = p_source_id and item_id = p_item;
    if recv <= 0 then raise exception 'item_not_in_source'; end if;
    select coalesce(sum(qty_base), 0) into used from public.grn_batch_links where source_type = 'purchase' and source_id = p_source_id and item_id = p_item;
    if used + bq > recv + 0.0005 then raise exception 'more_than_received'; end if;
  else
    if not exists (select 1 from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) l
                    where e.id = p_source_id and l->>'item' = it.code) then raise exception 'item_not_in_source'; end if;
  end if;
  -- batches can only describe stock that is really on hand and not yet in another batch
  select b.qty - coalesce((select sum(qty_remaining) from public.stock_batches where item_id = p_item and location_id = loc and qty_remaining > 0), 0) into free
    from public.stock_balance b where b.item_id = p_item and b.location_id = loc;
  if free + 0.0005 < bq then raise exception 'more_than_on_hand'; end if;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by, batch_no)
    values (p_item, loc, coalesce(p_made, today)::timestamp at time zone 'Asia/Dhaka', bq, bq,
            (p_expiry::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Dhaka',
            jsonb_build_object('source', 'grn_batch_add', 'source_type', p_source_type, 'source_id', p_source_id), 'GRN batch ' || bn, auth.uid(), bn)
    returning id into bid;
  insert into public.grn_batch_links (batch_id, source_type, source_id, item_id, location_id, batch_no, expiry_date, qty_base, client_id, created_by)
    values (bid, p_source_type, p_source_id, p_item, loc, bn, p_expiry, bq, p_client, auth.uid());
  return jsonb_build_object('batch_id', bid, 'batch_no', bn, 'expiry', p_expiry, 'qty_base', bq);
end $$;

-- near-expiry report (reuses expiry_list): batches expiring within p_days days, expired ones included
create or replace function public.near_expiry_report(p_loc int default null, p_days numeric default null)
returns table (batch_id bigint, batch_no text, item_id uuid, code text, name_bn text, name_en text, location_id int, expires_at timestamptz, qty_remaining numeric, days_left numeric, expired boolean, qc_blocked boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare d numeric := coalesce(p_days, public.rule_num('expiry_warn_days'), 7);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not (d between 0 and 3650) then d := 7; end if;
  return query
    select e.batch_id, b.batch_no, e.item_id, e.code, e.name_bn, e.name_en, e.location_id, e.expires_at, e.qty_remaining,
           round(e.hours_left / 24, 2), e.expired, public._qc_batch_blocked60(e.batch_id)
    from public.expiry_list(p_loc, d * 24) e join public.stock_batches b on b.id = e.batch_id
    order by e.expires_at, e.batch_id;
end $$;

-- FEFO hint: the order stock_post will take batches in (not-expired first, soonest expiry first, expired last)
create or replace function public.fefo_hint(p_item uuid, p_loc int)
returns table (rank int, batch_id bigint, batch_no text, expires_at timestamptz, qty_remaining numeric, expired boolean, qc_blocked boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
    select (row_number() over (order by (b.expires_at is not null and b.expires_at <= now()), b.expires_at nulls last, b.made_at, b.id))::int,
           b.id, b.batch_no, b.expires_at, b.qty_remaining, (b.expires_at is not null and b.expires_at <= now()), public._qc_batch_blocked60(b.id)
    from public.stock_batches b where b.item_id = p_item and b.location_id = p_loc and b.qty_remaining > 0
    order by 1;
end $$;

-- ---------- #8 wastage by reason ----------
create or replace function public.wastage_by_reason(p_loc int default null, p_from date default null, p_to date default null)
returns table (reason_code text, label_bn text, label_mix text, label_en text, entries bigint, items bigint, qty numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  return query
    select w.reason_code, coalesce(o.label_bn, w.reason_code), coalesce(o.label_mix, o.label_bn, w.reason_code), coalesce(o.label_en, w.reason_code),
           count(*), count(distinct w.item_id), round(sum(w.qty), 4)
    from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
    where public.can_loc(w.location_id) and (p_loc is null or w.location_id = p_loc)
      and (w.made_at at time zone 'Asia/Dhaka')::date between f and t
    group by w.reason_code, o.label_bn, o.label_mix, o.label_en
    order by sum(w.qty) desc, w.reason_code;
end $$;

-- ---------- #7 reorder suggestion (read-only) ----------
create or replace function public.reorder_report(p_loc int default null, p_days int default null)
returns table (item_id uuid, code text, name_bn text, name_en text, location_id int, base_unit text, on_hand numeric, min_stock numeric,
               avg_daily numeric, days_left numeric, lead_days numeric, suggest_qty numeric, why text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare d int := coalesce(p_days, public.rule_num('reorder_lookback_days')::int, 30); lead numeric := coalesce(public.rule_num('reorder_lead_days'), 3);
        cover numeric := coalesce(public.rule_num('reorder_cover_days'), 7);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if d is null or d not between 1 and 365 then raise exception 'bad_days'; end if;
  return query
    with u as (
      select l.item_id, l.location_id,
             sum(case when l.reason in ('sale_out', 'issue_out') then -l.qty_delta when l.reason in ('sale_void_in', 'sale_return') then -l.qty_delta else 0 end) as used
      from public.stock_ledger l
      where l.made_at >= now() - (d * interval '1 day') and l.reason in ('sale_out', 'issue_out', 'sale_void_in', 'sale_return')
      group by l.item_id, l.location_id),
    r as (
      select i.id as item_id, i.code, i.name_bn, i.name_en, b.location_id, public._item_base(i.id) as base_unit, b.qty as on_hand, i.min_stock,
             round(greatest(coalesce(u.used, 0), 0) / d, 4) as avg_daily
      from public.stock_balance b join public.items i on i.id = b.item_id and i.tracked and i.is_active
      left join u on u.item_id = b.item_id and u.location_id = b.location_id
      where public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc))
    select r.item_id, r.code, r.name_bn, r.name_en, r.location_id, r.base_unit, r.on_hand, r.min_stock, r.avg_daily,
           case when r.avg_daily > 0 then round(r.on_hand / r.avg_daily, 1) end, lead,
           round(greatest(greatest(r.avg_daily * (lead + cover), coalesce(r.min_stock, 0)) - r.on_hand, 0), 4),
           case when r.min_stock is not null and r.on_hand < r.min_stock then 'below_min'
                when r.avg_daily > 0 and r.on_hand <= r.avg_daily * lead then 'runs_out_in_lead'
                else 'cover' end
    from r
    where greatest(greatest(r.avg_daily * (lead + cover), coalesce(r.min_stock, 0)) - r.on_hand, 0) > 0
      and (r.avg_daily > 0 or (r.min_stock is not null and r.on_hand < r.min_stock))
    order by (case when r.min_stock is not null and r.on_hand < r.min_stock then 0 when r.avg_daily > 0 and r.on_hand <= r.avg_daily * lead then 1 else 2 end), r.code, r.location_id;
end $$;

-- ---------- grants ----------
revoke all on function public._qc_latest60(text, uuid), public._qc_batch_blocked60(bigint), public._append_only60() from public, anon, authenticated;
revoke all on function public.qc_gate(text, uuid), public.qc_record(text, uuid, text, jsonb, text, text, uuid), public.qc_list(int, date, date, text), public.qc_history(text, uuid),
  public.grn_batch_add(text, uuid, uuid, numeric, text, text, date, date, uuid), public.near_expiry_report(int, numeric), public.fefo_hint(uuid, int),
  public.wastage_by_reason(int, date, date), public.reorder_report(int, int) from public, anon;
grant execute on function public.qc_gate(text, uuid), public.qc_record(text, uuid, text, jsonb, text, text, uuid), public.qc_list(int, date, date, text), public.qc_history(text, uuid),
  public.grn_batch_add(text, uuid, uuid, numeric, text, text, date, date, uuid), public.near_expiry_report(int, numeric), public.fefo_hint(uuid, int),
  public.wastage_by_reason(int, date, date), public.reorder_report(int, int) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase61.sql
-- ============================================================
-- Phase 61 - P3 slice b: gaps #11 online order channel, #12 forms 20-1/20-2/20-4 linked to sales, #13 benefits depth, #14 BI export.
-- Run AFTER phase51 (needs the phase48 shadow engine, phase41 employees, phase13 export_data grant). Additive + idempotent (paste twice = no error).
-- Nothing existing is changed: no existing function is re-created, no existing row is edited. Every new switch is OFF by default.
--
--   #11 ORDERS    online_orders (+ online_order_events trail). Flow new -> confirmed -> packed -> delivered | cancelled.
--                 Delivering calls the EXISTING record_sale2 once (sale client id is stored on the order) or links an already-made sale
--                 (online_order_link_sale). One order = at most one sale (unique sale_id). Create takes a client id (idempotent).
--   #12 FORMS     path domain 'sale_forms' (owner switch: b_open=false stops new links). sale_form_links: primary = the sales row,
--                 forms 20-1 / 20-2 / 20-4 = locked shadows (shadow_type 'entries:20-x'); they never post. Owner links / unlinks;
--                 unlinked_sale_forms() lists the 20-x entries that have no sale.
--   #13 BENEFITS  benefit_types (paid_in_payroll flag, eligible_after_days) + employee_benefit_grants (grant dates, eligible_from, paid flag,
--                 value hidden without salary_view). benefits_report() is REPORT ONLY - payroll maths is not touched.
--   #14 EXPORT    bi_export(dataset, from, to, loc, format, limit): sales / sale_lines / purchases / stock_ledger / journal as json or csv.
--                 Owner or grant export_data; row cap (rule bi_export_max_rows, hard max 20000); <= 366 days; one bi_export_log row per call;
--                 cost columns only with rpt_cost_ok() (stock_ledger.unit_cost is blanked, purchases need the cost right).
-- Rules (all default OFF): online_orders_on, sale_forms_link_on, benefit_grants_on, bi_export_on; number bi_export_max_rows.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('online_orders_on', 'pos', 'switch', 'false', null, null, null, null, 'অনলাইন অর্ডার চ্যানেল চালু', 'Online order channel চালু', 'Online order channel is on',
  'চালু হলে ফেসবুক/হোয়াটসঅ্যাপ/ফোন অর্ডার লিখে রাখা যায়; ডেলিভারিতে একটাই বিক্রি তৈরি হয়।', 'When on, social / phone orders can be recorded; delivery makes exactly one sale.', 610),
 ('sale_forms_link_on', 'entries', 'switch', 'false', null, null, null, null, 'ফর্ম 20-১/২/৪ বিক্রির সাথে জোড়া চালু', 'Form 20-1/2/4 ↔ sale link চালু', 'Link forms 20-1 / 20-2 / 20-4 to sales',
  'মালিক একটি ফর্ম এন্ট্রিকে একটি বিক্রির সাথে জুড়বেন; ফর্ম তখন লক শ্যাডো কপি, কিছু পোস্ট হয় না।', 'The owner links a form entry to a sale; the form becomes a locked shadow copy and posts nothing.', 611),
 ('benefit_grants_on', 'people', 'switch', 'false', null, null, null, null, 'কর্মীর সুবিধা (গভীর) চালু', 'Employee benefits (depth) চালু', 'Employee benefit grants are on',
  'সুবিধার ধরন, প্রাপ্যতার তারিখ, বেতনের সাথে দেওয়া কিনা। শুধু রিপোর্ট; বেতনের হিসাব বদলায় না।', 'Benefit types, eligibility dates, paid-in-payroll flag. Report only; payroll maths is unchanged.', 612),
 ('bi_export_on', 'reports', 'switch', 'false', null, null, null, null, 'BI এক্সপোর্ট চালু', 'BI export চালু', 'BI export is on',
  'বিক্রি/ক্রয়/স্টক/জার্নাল CSV-JSON এক্সপোর্ট; শুধু মালিক বা export_data অনুমতি; প্রতিবার লগ।', 'Sales / purchases / stock / journal CSV-JSON export; owner or export_data only; every call is logged.', 613),
 ('bi_export_max_rows', 'reports', 'number', '5000', 'rows', null, 100, 20000, 'BI এক্সপোর্ট: সর্বোচ্চ সারি', 'BI export: max rows', 'BI export: row cap',
  'প্রতি এক্সপোর্টে এর বেশি সারি যাবে না (সর্বোচ্চ ২০০০০)।', 'No export returns more rows than this (hard max 20000).', 614)
 on conflict (key) do nothing;

-- =====================================================================
-- #11 ONLINE ORDER CHANNEL
-- =====================================================================
create table if not exists public.online_orders (
  id uuid primary key default gen_random_uuid(),
  client_id uuid, order_no int not null, location_id int not null references public.locations(id),
  channel text not null check (channel in ('website', 'facebook', 'instagram', 'whatsapp', 'phone', 'foodapp', 'other')),
  customer_name text not null check (char_length(btrim(customer_name)) between 1 and 80),
  customer_mobile text not null check (char_length(customer_mobile) between 6 and 20),
  address text check (address is null or char_length(address) <= 300),
  lines jsonb not null check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) between 1 and 100),
  subtotal numeric not null check (subtotal >= 0 and subtotal <= 1000000000000),
  discount numeric not null default 0 check (discount >= 0 and discount <= 1000000000000),
  delivery_mode text not null check (delivery_mode in ('pickup', 'home', 'courier')),
  delivery_by text check (delivery_by is null or char_length(delivery_by) <= 60),
  delivery_date date, delivery_charge numeric not null default 0 check (delivery_charge >= 0 and delivery_charge <= 1000000),
  advance numeric not null default 0 check (advance >= 0 and advance <= 1000000000000),
  advance_mode text check (advance_mode is null or advance_mode in ('cash', 'mobile', 'card')), advance_wallet text check (advance_wallet is null or char_length(advance_wallet) <= 30),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'new' check (status in ('new', 'confirmed', 'packed', 'delivered', 'cancelled')),
  sale_client uuid not null default gen_random_uuid(),           -- the client id given to record_sale2, so a retry can never make a 2nd sale
  sale_id uuid unique references public.sales(id),
  cancel_reason text, advance_fate text check (advance_fate is null or advance_fate in ('refund', 'adjust', 'income', 'none')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  delivered_by uuid, delivered_at timestamptz,
  check ((advance > 0) = (advance_mode is not null))
);
create unique index if not exists online_orders_no on public.online_orders (location_id, order_no);
create unique index if not exists online_orders_client on public.online_orders (created_by, client_id) where client_id is not null;
create index if not exists online_orders_by_status on public.online_orders (location_id, status, created_at desc);

create table if not exists public.online_order_events (
  id bigint generated always as identity primary key, order_id uuid not null references public.online_orders(id),
  from_status text, to_status text not null, note text, by_user uuid, by_staff text, at timestamptz not null default now()
);
create index if not exists online_order_events_o on public.online_order_events (order_id, id);

create or replace function public._oo_ro61() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'online_order_events' then raise exception 'append_only: the order trail cannot be changed or deleted'; end if;
  if tg_op = 'DELETE' then raise exception 'append_only: an order is never deleted, cancel it'; end if;
  if old.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  return new;
end $$;
drop trigger if exists online_orders_ro61 on public.online_orders;
create trigger online_orders_ro61 before update or delete on public.online_orders for each row execute function public._oo_ro61();
drop trigger if exists online_order_events_ro61 on public.online_order_events;
create trigger online_order_events_ro61 before update or delete on public.online_order_events for each row execute function public._oo_ro61();
drop trigger if exists audit_online_orders on public.online_orders;
create trigger audit_online_orders after insert or update on public.online_orders for each row execute function public.log_change('id');

-- normalise the order lines: item lines only, list price of today, qty > 0
create or replace function public._oo_lines61(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ln jsonb; it public.items; q numeric; out jsonb := '[]'; sub numeric := 0;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'no_lines'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    if nullif(ln->>'item_id', '') is null then raise exception 'item_required'; end if;
    select * into it from public.items where id = (ln->>'item_id')::uuid and is_active;
    if not found then raise exception 'item_not_found'; end if;
    q := (ln->>'qty')::numeric;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    if it.sell_price is null then raise exception 'no_price'; end if;
    out := out || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'qty', q, 'price', it.sell_price, 'amount', round(q * it.sell_price, 2));
    sub := sub + round(q * it.sell_price, 2);
  end loop;
  return jsonb_build_object('lines', out, 'subtotal', sub);
end $$;

create or replace function public._oo_event61(p_order uuid, p_from text, p_to text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.online_order_events (order_id, from_status, to_status, note, by_user, by_staff)
    values (p_order, p_from, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
end $$;

create or replace function public._oo_gate61(p_loc int, p_action text default 'enter') returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', p_action) then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
end $$;

-- create (p_id null) or edit (status new / confirmed). Idempotent on p_client.
create or replace function public.online_order_save(p_id uuid, p_client uuid, p_loc int, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb,
  p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  perform public._oo_gate61(loc);
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
end $$;

-- confirm / pack (forward only)
create or replace function public.online_order_status(p_id uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_to not in ('confirmed', 'packed') then raise exception 'bad_status'; end if;
  if o.status = p_to then return jsonb_build_object('id', o.id, 'status', o.status, 'noop', true); end if;
  if not ((o.status = 'new' and p_to = 'confirmed') or (o.status = 'confirmed' and p_to = 'packed')) then raise exception 'bad_status: % -> % is not allowed', o.status, p_to; end if;
  update public.online_orders set status = p_to, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, p_to, p_note);
  return jsonb_build_object('id', o.id, 'status', p_to);
end $$;

create or replace function public.online_order_cancel(p_id uuid, p_reason text, p_advance_fate text default 'none') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status = 'cancelled' then return jsonb_build_object('id', o.id, 'status', 'cancelled', 'noop', true); end if;
  if o.status = 'delivered' then raise exception 'order_closed: a delivered order has a sale; use the sale return'; end if;
  if nullif(btrim(p_reason), '') is null or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if coalesce(p_advance_fate, 'none') not in ('refund', 'adjust', 'income', 'none') then raise exception 'bad_fate'; end if;
  if o.advance > 0 and coalesce(p_advance_fate, 'none') = 'none' then raise exception 'advance_fate_required'; end if;
  update public.online_orders set status = 'cancelled', cancel_reason = btrim(p_reason), advance_fate = case when o.advance > 0 then p_advance_fate else 'none' end, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, 'cancelled', btrim(p_reason) || case when o.advance > 0 then ' | advance: ' || p_advance_fate else '' end);
  return jsonb_build_object('id', o.id, 'status', 'cancelled', 'advance', o.advance, 'advance_fate', p_advance_fate);
end $$;

-- deliver: ONE sale through record_sale2 (advance counted as the first payment, p_payments = what is collected now). Retrying never makes a second sale.
create or replace function public.online_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sl jsonb := '[]'; ln jsonb; pay jsonb := '[]'; res jsonb; sid uuid;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.sale_id is not null then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    sl := sl || jsonb_build_object('item_id', ln->>'item_id', 'qty', (ln->>'qty')::numeric, 'price', (ln->>'price')::numeric);
  end loop;
  if o.delivery_charge > 0 then sl := sl || jsonb_build_object('name', 'Delivery charge', 'amount', o.delivery_charge); end if;
  if o.advance > 0 then pay := pay || jsonb_build_object('mode', o.advance_mode, 'amount', o.advance, 'wallet', o.advance_wallet, 'ref', 'online order #' || o.order_no || ' advance'); end if;
  pay := pay || coalesce(p_payments, '[]'::jsonb);
  res := public.record_sale2(o.sale_client, o.location_id, sl, o.discount, pay, o.customer_mobile, o.customer_name, 'retail', 'Online order #' || o.order_no, false, null);
  sid := (res->>'id')::uuid;
  if exists (select 1 from public.online_orders x where x.sale_id = sid and x.id <> o.id) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = sid, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'packed', 'delivered', 'sale receipt ' || (res->>'receipt'));
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', sid, 'receipt', res->'receipt', 'total', res->'total', 'paid', res->'paid', 'due', res->'due');
end $$;

-- link an order to a sale that already exists (sold over the counter meanwhile). Needs POS approve (or the owner). Never creates a sale.
create or replace function public.online_order_link_sale(p_id uuid, p_sale uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; s public.sales;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'approve');
  if o.sale_id = p_sale then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.location_id <> o.location_id then raise exception 'sale_other_location'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if exists (select 1 from public.online_orders x where x.sale_id = p_sale) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = p_sale, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, 'delivered', 'linked to existing sale receipt ' || s.receipt || coalesce(' | ' || nullif(btrim(p_note), ''), ''));
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', p_sale, 'receipt', s.receipt, 'linked', true);
end $$;

create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name, o.customer_mobile, o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(o) - 'sale_client' || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;

-- =====================================================================
-- #12 FORMS 20-1 / 20-2 / 20-4 LINKED TO SALES (shadow engine)
-- =====================================================================
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('sale_forms', 'বিক্রি (POS / ইনভয়েস)', 'Sale (POS / invoice)', 'ফর্ম 20-1 / 20-2 / 20-4', 'Forms 20-1 / 20-2 / 20-4', 'a',
  'বিক্রিই মূল রেকর্ড; জোড়া দেওয়া ফর্ম লক শ্যাডো কপি, কিছু পোস্ট করে না। পথ খ লক = নতুন জোড়া বন্ধ।', 'The sale is the record; a linked form is a locked shadow copy and posts nothing. Locking path B stops new links.', 80)
 on conflict (domain) do nothing;

create table if not exists public.sale_form_links (
  id bigint generated always as identity primary key,
  sale_id uuid not null references public.sales(id), entry_id uuid not null references public.entries(id),
  form_code text not null check (form_code in ('20-1', '20-2', '20-4')), location_id int not null,
  shadow_link_id bigint references public.shadow_links(id), amount_diff numeric,
  state text not null default 'active' check (state in ('active', 'void')), note text check (note is null or char_length(note) <= 300),
  linked_by uuid, linked_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists sale_form_links_entry on public.sale_form_links (entry_id) where state = 'active';
create unique index if not exists sale_form_links_sale_form on public.sale_form_links (sale_id, form_code) where state = 'active';
create index if not exists sale_form_links_sale on public.sale_form_links (sale_id);
create or replace function public._sfl_ro61() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.state = 'active' and new.state = 'void'
     and (to_jsonb(new) - 'state' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'state' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: sale_form_links is a trail, void it instead';
end $$;
drop trigger if exists sale_form_links_ro61 on public.sale_form_links;
create trigger sale_form_links_ro61 before update or delete on public.sale_form_links for each row execute function public._sfl_ro61();
drop trigger if exists audit_sale_form_links on public.sale_form_links;
create trigger audit_sale_form_links after insert or update on public.sale_form_links for each row execute function public.log_change('id');

-- a linked 20-x entry is a locked copy: no data change, no re-open (same lock the phase50 shadows have)
create or replace function public._entries_saleform_lock61() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.form_code in ('20-1', '20-2', '20-4') and old.status in ('submitted', 'approved') and (new.data is distinct from old.data or new.status = 'draft')
     and exists (select 1 from public.sale_form_links l where l.entry_id = old.id and l.state = 'active') then
    raise exception 'shadow_locked: this form is a locked copy of a sale; it cannot be changed or re-opened (the owner can unlink it first)';
  end if;
  return new;
end $$;
drop trigger if exists entries_saleform_lock61 on public.entries;
create trigger entries_saleform_lock61 before update on public.entries for each row execute function public._entries_saleform_lock61();

create or replace function public._sfl_total61(p_form text, p_data jsonb) returns numeric
language sql immutable as $$
  select case when p_form = '20-1' and (p_data->>'total') ~ '^-?[0-9]+(\.[0-9]+)?$' then round((p_data->>'total')::numeric - case when (p_data->>'discount') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p_data->>'discount')::numeric else 0 end, 2) end;
$$;

create or replace function public.sale_form_link(p_entry uuid, p_sale uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; s public.sales; ex public.sale_form_links; lk bigint; id_ bigint; tot numeric; diff numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('sale_forms_link_on') then raise exception 'module_off'; end if;
  select * into e from public.entries where id = p_entry for update;
  if not found or e.form_code not in ('20-1', '20-2', '20-4') then raise exception 'form_not_linkable: only 20-1, 20-2 and 20-4'; end if;
  if e.status not in ('submitted', 'approved') then raise exception 'form_not_final: submit the form first'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if s.location_id <> e.location_id then raise exception 'other_location'; end if;
  select * into ex from public.sale_form_links where entry_id = p_entry and state = 'active';
  if found then
    if ex.sale_id = p_sale then return jsonb_build_object('id', ex.id, 'dup', true); end if;
    raise exception 'entry_already_linked';
  end if;
  if exists (select 1 from public.sale_form_links where sale_id = p_sale and form_code = e.form_code and state = 'active') then raise exception 'sale_already_has_form'; end if;
  perform public.path_guard('sale_forms', e.location_id, 'b');
  lk := public.shadow_link_add('sale_forms', e.location_id, 'sales', p_sale::text, 'entries:' || e.form_code, p_entry::text, coalesce(nullif(btrim(p_note), ''), 'form ' || e.form_code || ' kept as a copy'));
  tot := public._sfl_total61(e.form_code, e.data);
  diff := case when tot is not null then round(tot - s.total, 2) end;
  insert into public.sale_form_links (sale_id, entry_id, form_code, location_id, shadow_link_id, amount_diff, note, linked_by)
    values (p_sale, p_entry, e.form_code, e.location_id, lk, diff, left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_, 'shadow_link', lk, 'form', e.form_code, 'amount_diff', diff, 'amount_matches', coalesce(diff = 0, null));
end $$;

create or replace function public.sale_form_unlink(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.sale_form_links;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  select * into l from public.sale_form_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if l.state = 'void' then return jsonb_build_object('id', l.id, 'state', 'void', 'noop', true); end if;
  if l.shadow_link_id is not null then perform public.shadow_void(l.shadow_link_id, p_note); end if;
  update public.sale_form_links set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = l.id;
  return jsonb_build_object('id', l.id, 'state', 'void');
end $$;

-- forms linked to one sale (anyone who may view the sale)
create or replace function public.sale_forms_for(p_sale uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales;
begin
  select * into s from public.sales where id = p_sale;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(s.location_id) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'entry_id', l.entry_id, 'form_code', l.form_code, 'amount_diff', l.amount_diff, 'linked_at', l.linked_at) order by l.id)
                     from public.sale_form_links l where l.sale_id = p_sale and l.state = 'active'), '[]'::jsonb);
end $$;

-- report: 20-1 / 20-2 / 20-4 entries (submitted / approved) with no sale link, with up to 3 candidate sales
create or replace function public.unlinked_sale_forms(p_from date, p_to date, p_loc int default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_date'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.entry_date, z.serial) from (
    select e.id as entry_id, e.form_code, e.serial, e.entry_date, e.location_id,
           coalesce(nullif(e.data->>'cust_name', ''), nullif(e.data->>'party', '')) as customer, public._sfl_total61(e.form_code, e.data) as form_total,
           coalesce((select jsonb_agg(c.id order by abs(c.sale_date - e.entry_date), c.receipt) from (
               select s.id, s.sale_date, s.receipt from public.sales s
                where s.location_id = e.location_id and s.status = 'done' and s.sale_date between e.entry_date - 3 and e.entry_date + 3
                  and (public._sfl_total61(e.form_code, e.data) is null or s.total = public._sfl_total61(e.form_code, e.data))
                  and not exists (select 1 from public.sale_form_links l where l.sale_id = s.id and l.form_code = e.form_code and l.state = 'active')
                order by abs(s.sale_date - e.entry_date), s.receipt limit 3) c), '[]'::jsonb) as candidate_sales
      from public.entries e
     where e.form_code in ('20-1', '20-2', '20-4') and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to
       and (p_loc is null or e.location_id = p_loc) and public.can_loc(e.location_id) and (public.is_owner() or public.can_do(e.form_code, 'view'))
       and not exists (select 1 from public.sale_form_links l where l.entry_id = e.id and l.state = 'active')
     order by e.entry_date, e.serial limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- =====================================================================
-- #13 BENEFITS DEPTH (report only; payroll maths untouched)
-- =====================================================================
create table if not exists public.benefit_types (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,30}$'), name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80), name_en text,
  paid_in_payroll boolean not null default false,                       -- default for new grants: the value is paid through the salary sheet
  eligible_after_days int not null default 0 check (eligible_after_days between 0 and 3650),   -- days after the joining date
  default_for_all boolean not null default false,                       -- every active employee should hold it once eligible (feeds the "missing" list)
  active boolean not null default true, sort int not null default 100, updated_by uuid, updated_at timestamptz not null default now()
);
insert into public.benefit_types (code, name_bn, name_en, sort) values
 ('meal', 'খাবার', 'Meal', 10), ('uniform', 'ইউনিফর্ম', 'Uniform', 20), ('accommodation', 'থাকার ব্যবস্থা', 'Accommodation', 30), ('transport', 'যাতায়াত', 'Transport', 40),
 ('phone', 'ফোন', 'Phone', 50), ('insurance', 'বিমা', 'Insurance', 60), ('other', 'অন্যান্য', 'Other', 90)
 on conflict (code) do nothing;

create table if not exists public.employee_benefit_grants (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), type_code text not null references public.benefit_types(code),
  from_date date not null, eligible_from date not null, to_date date, status text not null default 'active' check (status in ('active', 'ended')),
  paid_in_payroll boolean not null default false,
  value_per_month numeric check (value_per_month is null or (value_per_month >= 0 and value_per_month <= 1000000000000)),   -- column hidden from the browser (salary_view only through the report)
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date), check (eligible_from >= from_date)
);
create index if not exists employee_benefit_grants_emp on public.employee_benefit_grants (employee_id, type_code);
drop trigger if exists audit_employee_benefit_grants on public.employee_benefit_grants;
create trigger audit_employee_benefit_grants after insert or update on public.employee_benefit_grants for each row execute function public.log_change('id');
drop trigger if exists audit_benefit_types on public.benefit_types;
create trigger audit_benefit_types after insert or update on public.benefit_types for each row execute function public.log_change('code');

create or replace function public.benefit_type_save(p_code text, p_name_bn text, p_name_en text, p_paid boolean, p_days int, p_default_all boolean, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._emp_gate();
  if not (public.is_owner() or public.has_grant('salary_manage')) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or char_length(p_name_bn) > 80 or char_length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_days is null or p_days not between 0 and 3650 then raise exception 'bad_days'; end if;
  insert into public.benefit_types (code, name_bn, name_en, paid_in_payroll, eligible_after_days, default_for_all, active, updated_by)
    values (p_code, btrim(p_name_bn), coalesce(nullif(btrim(p_name_en), ''), btrim(p_name_bn)), coalesce(p_paid, false), p_days, coalesce(p_default_all, false), coalesce(p_active, true), auth.uid())
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, paid_in_payroll = excluded.paid_in_payroll, eligible_after_days = excluded.eligible_after_days,
      default_for_all = excluded.default_for_all, active = excluded.active, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('code', p_code);
end $$;

create or replace function public.employee_benefit_grant(p_id bigint, p_client uuid, p_emp uuid, p_type text, p_from date, p_to date, p_value numeric, p_paid boolean default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefit_grants; t public.benefit_types; e public.employees; v_today date := public._dhaka_today(); elig date; emp uuid := p_emp;
begin
  perform public._emp_gate();
  if not public.rule_on('benefit_grants_on') then raise exception 'module_off'; end if;
  perform public._client_lock(p_client);
  if p_id is not null then
    select * into r from public.employee_benefit_grants where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    emp := r.employee_id;
    if r.status <> 'active' then raise exception 'grant_ended'; end if;
  elsif p_client is not null then
    select * into r from public.employee_benefit_grants where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'repeat', true); end if;
  end if;
  if not public._emp_ok(emp, array['employee_manage', 'salary_manage']) then raise exception 'not allowed'; end if;
  if p_value is not null and not public._emp_ok(emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  select * into e from public.employees where id = emp;
  if not found then raise exception 'not_found'; end if;
  select * into t from public.benefit_types where code = coalesce(p_type, r.type_code);
  if not found or not t.active then raise exception 'bad_type'; end if;
  if p_value is not null and not (p_value between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if p_from is null or not (p_from between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if exists (select 1 from public.employee_benefit_grants g where g.employee_id = emp and g.type_code = t.code and g.status = 'active' and (p_id is null or g.id <> p_id)
               and daterange(g.from_date, coalesce(g.to_date, 'infinity'::date), '[]') && daterange(p_from, coalesce(p_to, 'infinity'::date), '[]')) then raise exception 'overlap: this employee already holds this benefit in those dates'; end if;
  elig := greatest(p_from, case when e.joining_date is not null then e.joining_date + t.eligible_after_days else p_from end);
  if p_id is null then
    insert into public.employee_benefit_grants (client_id, employee_id, type_code, from_date, eligible_from, to_date, paid_in_payroll, value_per_month, note, created_by, updated_by)
      values (p_client, emp, t.code, p_from, elig, p_to, coalesce(p_paid, t.paid_in_payroll), p_value, nullif(btrim(p_note), ''), auth.uid(), auth.uid()) returning * into r;
  else
    update public.employee_benefit_grants set from_date = p_from, eligible_from = elig, to_date = p_to, paid_in_payroll = coalesce(p_paid, paid_in_payroll),
        value_per_month = case when p_value is not null then p_value else value_per_month end, note = nullif(btrim(p_note), ''), updated_by = auth.uid(), updated_at = now()
      where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'eligible_from', r.eligible_from, 'paid_in_payroll', r.paid_in_payroll);
end $$;

create or replace function public.employee_benefit_grant_end(p_id bigint, p_to date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefit_grants;
begin
  perform public._emp_gate();
  select * into r from public.employee_benefit_grants where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if r.status = 'ended' then return jsonb_build_object('id', r.id, 'noop', true); end if;
  if p_to is null or p_to < r.from_date or p_to > public._dhaka_today() + 366 then raise exception 'bad_date'; end if;
  update public.employee_benefit_grants set status = 'ended', to_date = p_to, note = left(coalesce(nullif(btrim(p_note), ''), note), 300), updated_by = auth.uid(), updated_at = now() where id = r.id;
  return jsonb_build_object('id', r.id, 'to_date', p_to);
end $$;

-- report: every grant (state not_yet / eligible / ended), the paid-in-payroll flag, and the people who are past eligibility for a default_for_all type but hold no grant
create or replace function public.benefits_report(p_as_of date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_as_of, public._dhaka_today()); grants jsonb; missing jsonb; tot numeric;
begin
  perform public._emp_gate();
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.employee_name, z.type_code), '[]'::jsonb), coalesce(sum(z.value_per_month) filter (where z.state = 'eligible' and z.paid_in_payroll), 0)
    into grants, tot from (
    select g.id, g.employee_id, e.employee_no, e.full_name_bn as employee_name, e.primary_location_id as location_id, g.type_code, t.name_bn as type_name, g.from_date, g.eligible_from, g.to_date,
           case when g.status = 'ended' or (g.to_date is not null and g.to_date < d) then 'ended' when g.eligible_from > d then 'not_yet' else 'eligible' end as state,
           g.paid_in_payroll, case when public._emp_ok(g.employee_id, array['salary_view']) then g.value_per_month end as value_per_month
      from public.employee_benefit_grants g join public.employees e on e.id = g.employee_id join public.benefit_types t on t.code = g.type_code
     where (p_loc is null or e.primary_location_id = p_loc) and public._emp_ok(g.employee_id, array['employee_view', 'employee_manage', 'salary_view'], true) limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'employee_name', e.full_name_bn, 'type_code', t.code, 'type_name', t.name_bn,
           'eligible_from', e.joining_date + t.eligible_after_days) order by e.full_name_bn, t.code), '[]'::jsonb) into missing
    from public.employees e cross join public.benefit_types t
   where t.active and t.default_for_all and e.status = 'active' and e.joining_date is not null and e.joining_date + t.eligible_after_days <= d
     and (p_loc is null or e.primary_location_id = p_loc) and public._emp_ok(e.id, array['employee_view', 'employee_manage', 'salary_view'], true)
     and not exists (select 1 from public.employee_benefit_grants g where g.employee_id = e.id and g.type_code = t.code and g.status = 'active' and g.from_date <= d and (g.to_date is null or g.to_date >= d));
  return jsonb_build_object('as_of', d, 'grants', grants, 'missing', missing, 'paid_in_payroll_monthly_visible', tot,
    'note', 'report only: payroll maths does not read these grants');
end $$;

-- =====================================================================
-- #14 BI EXPORT (read only data; one log row per call)
-- =====================================================================
create table if not exists public.bi_export_log (
  id bigint generated always as identity primary key, at timestamptz not null default now(), user_id uuid, staff_id text,
  dataset text not null, date_from date not null, date_to date not null, location_id int, format text not null, row_limit int not null,
  row_count int not null, truncated boolean not null, cost_included boolean not null
);
create or replace function public._bil_ro61() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the export log cannot be changed or deleted'; end $$;
drop trigger if exists bi_export_log_ro61 on public.bi_export_log;
create trigger bi_export_log_ro61 before update or delete on public.bi_export_log for each row execute function public._bil_ro61();

create or replace function public._bi_csv61(p_cols text[], p_rows jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare out text := array_to_string(p_cols, ','); r jsonb; c text; v jsonb; t text; cells text[];
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    cells := '{}';
    foreach c in array p_cols loop
      v := r -> c;
      if v is null or jsonb_typeof(v) = 'null' then t := '';
      elsif jsonb_typeof(v) in ('number', 'boolean') then t := v #>> '{}';
      else
        t := v #>> '{}';
        if t ~ '^[=+@-]' or left(t, 1) in (E'\t', E'\r') then t := '''' || t; end if;      -- spreadsheet formula guard
        if t ~ '[",]' or position(E'\n' in t) > 0 or position(E'\r' in t) > 0 then t := '"' || replace(t, '"', '""') || '"'; end if;
      end if;
      cells := cells || t;
    end loop;
    out := out || E'\n' || array_to_string(cells, ',');
  end loop;
  return out;
end $$;

create or replace function public.bi_export(p_dataset text, p_from date, p_to date, p_loc int default null, p_format text default 'json', p_limit int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cap int; lim int; rows jsonb; cols text[]; trunc boolean := false; cost boolean := public.rpt_cost_ok(); logid bigint; fmt text := lower(coalesce(p_format, 'json')); n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('bi_export_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_dataset not in ('sales', 'sale_lines', 'purchases', 'stock_ledger', 'journal') then raise exception 'bad_dataset'; end if;
  if fmt not in ('json', 'csv') then raise exception 'bad_format'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_date: from/to required, at most 366 days'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  cap := least(greatest(coalesce(public.rule_num('bi_export_max_rows'), 5000), 100), 20000)::int;
  lim := least(greatest(coalesce(p_limit, cap), 1), cap);
  if p_dataset in ('sales', 'sale_lines') and not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_dataset = 'purchases' and not cost then raise exception 'cost_not_allowed: purchase data carries cost prices'; end if;
  if p_dataset = 'journal' and not public._acct_view() then raise exception 'not allowed'; end if;

  if p_dataset = 'sales' then
    cols := array['id', 'receipt', 'sale_date', 'location_id', 'status', 'sale_type', 'pay_mode', 'subtotal', 'discount', 'total', 'paid', 'due_amount', 'customer', 'line_count'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sale_date, x.location_id, x.receipt), '[]'::jsonb) into rows from (
      select s.id, s.receipt, s.sale_date, s.location_id, s.status, s.sale_type, s.pay_mode, s.subtotal, s.discount, s.total, s.paid, s.due_amount, s.customer, jsonb_array_length(s.lines) as line_count
        from public.sales s where s.sale_date between p_from and p_to and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
        order by s.sale_date, s.location_id, s.receipt limit lim + 1) x;
  elsif p_dataset = 'sale_lines' then
    cols := array['sale_id', 'receipt', 'sale_date', 'location_id', 'status', 'line_no', 'item_id', 'code', 'name', 'qty', 'price', 'amount'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sale_date, x.location_id, x.receipt, x.line_no), '[]'::jsonb) into rows from (
      select s.id as sale_id, s.receipt, s.sale_date, s.location_id, s.status, l.ord::int as line_no, l.v->>'item_id' as item_id, l.v->>'code' as code, l.v->>'name' as name,
             (l.v->>'qty')::numeric as qty, (l.v->>'price')::numeric as price, (l.v->>'amount')::numeric as amount
        from public.sales s cross join lateral jsonb_array_elements(s.lines) with ordinality as l(v, ord)
       where s.sale_date between p_from and p_to and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
       order by s.sale_date, s.location_id, s.receipt, l.ord limit lim + 1) x;
  elsif p_dataset = 'purchases' then
    cols := array['bill_id', 'bill_no', 'bill_date', 'kind', 'status', 'supplier_id', 'location_id', 'line_no', 'item_id', 'description', 'qty', 'unit', 'unit_cost', 'amount'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.bill_date, x.bill_id, x.line_no), '[]'::jsonb) into rows from (
      select b.id as bill_id, b.bill_no, b.bill_date, b.kind, b.status, b.supplier_id, b.location_id, l.line_no, l.item_id, l.description, l.qty, l.unit, l.unit_cost, l.amount
        from public.purchase_bills b join public.purchase_lines l on l.bill_id = b.id
       where b.bill_date between p_from and p_to and (p_loc is null or b.location_id = p_loc) and public._pur_ok(b.location_id)
       order by b.bill_date, b.id, l.line_no limit lim + 1) x;
  elsif p_dataset = 'stock_ledger' then
    cols := array['id', 'made_at', 'item_id', 'location_id', 'qty_delta', 'unit_cost', 'reason', 'ref_type', 'ref_id', 'reverses_id'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) into rows from (
      select k.id, k.made_at, k.item_id, k.location_id, k.qty_delta, case when cost then k.unit_cost end as unit_cost, k.reason, k.ref_type, k.ref_id, k.reverses_id
        from public.stock_ledger k where (k.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (p_loc is null or k.location_id = p_loc) and public.can_loc(k.location_id)
       order by k.id limit lim + 1) x;
  else
    cols := array['entry_id', 'entry_date', 'location_id', 'source_type', 'source_id', 'status', 'memo', 'line_no', 'account_id', 'debit', 'credit'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.entry_date, x.entry_id, x.line_no), '[]'::jsonb) into rows from (
      select j.id as entry_id, j.entry_date, j.location_id, j.source_type, j.source_id, j.status, j.memo, l.line_no, l.account_id, l.debit, l.credit
        from public.journal_entries j join public.journal_lines l on l.entry_id = j.id
       where j.entry_date between p_from and p_to and (p_loc is null or j.location_id = p_loc) and (public._acct_all() or (j.location_id is not null and public.can_loc(j.location_id)))
       order by j.entry_date, j.id, l.line_no limit lim + 1) x;
  end if;

  n := jsonb_array_length(rows);
  if n > lim then trunc := true; rows := rows - lim; n := lim; end if;
  insert into public.bi_export_log (user_id, staff_id, dataset, date_from, date_to, location_id, format, row_limit, row_count, truncated, cost_included)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_dataset, p_from, p_to, p_loc, fmt, lim, n, trunc, cost and p_dataset in ('purchases', 'stock_ledger'))
    returning id into logid;
  return jsonb_build_object('dataset', p_dataset, 'format', fmt, 'columns', to_jsonb(cols), 'row_count', n, 'truncated', trunc, 'cap', cap, 'cost_visible', cost, 'log_id', logid)
    || case when fmt = 'csv' then jsonb_build_object('csv', public._bi_csv61(cols, rows)) else jsonb_build_object('rows', rows) end;
end $$;

create or replace function public.bi_export_log_list(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (select * from public.bi_export_log order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['online_orders', 'online_order_events', 'sale_form_links', 'benefit_types', 'employee_benefit_grants', 'bi_export_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
grant select on public.online_orders, public.online_order_events, public.sale_form_links, public.benefit_types, public.bi_export_log to authenticated;
-- the grant value is salary data: every column except value_per_month
grant select (id, client_id, employee_id, type_code, from_date, eligible_from, to_date, status, paid_in_payroll, note, created_by, created_at, updated_by, updated_at) on public.employee_benefit_grants to authenticated;
-- order secrets: sale_client stays server side
revoke select on public.online_orders from authenticated;
grant select (id, client_id, order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_by, delivery_date, delivery_charge,
  advance, advance_mode, advance_wallet, note, status, sale_id, cancel_reason, advance_fate, created_by, created_staff, created_at, updated_at, delivered_by, delivered_at) on public.online_orders to authenticated;

create policy online_orders_sel on public.online_orders for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
create policy online_order_events_sel on public.online_order_events for select to authenticated
  using (exists (select 1 from public.online_orders o where o.id = order_id and public.can_do('POS', 'view') and public.can_loc(o.location_id)));
create policy sale_form_links_sel on public.sale_form_links for select to authenticated using (public.is_owner() or (public.can_do('POS', 'view') and public.can_loc(location_id)));
create policy benefit_types_sel on public.benefit_types for select to authenticated using (public.is_active());
create policy employee_benefit_grants_sel on public.employee_benefit_grants for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage', 'salary_view'], true));
create policy bi_export_log_sel on public.bi_export_log for select to authenticated using (public.is_owner());

-- browser-callable
revoke all on function public.online_order_save(uuid, uuid, int, text, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text), public.online_order_status(uuid, text, text),
  public.online_order_cancel(uuid, text, text), public.online_order_deliver(uuid, jsonb), public.online_order_link_sale(uuid, uuid, text), public.online_orders_list(int, text, date, date, int),
  public.online_order_get(uuid), public.sale_form_link(uuid, uuid, text), public.sale_form_unlink(bigint, text), public.sale_forms_for(uuid), public.unlinked_sale_forms(date, date, int, int),
  public.benefit_type_save(text, text, text, boolean, int, boolean, boolean), public.employee_benefit_grant(bigint, uuid, uuid, text, date, date, numeric, boolean, text),
  public.employee_benefit_grant_end(bigint, date, text), public.benefits_report(date, int), public.bi_export(text, date, date, int, text, int), public.bi_export_log_list(int) from public, anon;
grant execute on function public.online_order_save(uuid, uuid, int, text, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text), public.online_order_status(uuid, text, text),
  public.online_order_cancel(uuid, text, text), public.online_order_deliver(uuid, jsonb), public.online_order_link_sale(uuid, uuid, text), public.online_orders_list(int, text, date, date, int),
  public.online_order_get(uuid), public.sale_form_link(uuid, uuid, text), public.sale_form_unlink(bigint, text), public.sale_forms_for(uuid), public.unlinked_sale_forms(date, date, int, int),
  public.benefit_type_save(text, text, text, boolean, int, boolean, boolean), public.employee_benefit_grant(bigint, uuid, uuid, text, date, date, numeric, boolean, text),
  public.employee_benefit_grant_end(bigint, date, text), public.benefits_report(date, int), public.bi_export(text, date, date, int, text, int), public.bi_export_log_list(int) to authenticated;
-- helpers: never from the browser
revoke all on function public._oo_lines61(jsonb), public._oo_event61(uuid, text, text, text), public._oo_gate61(int, text), public._oo_ro61(), public._sfl_ro61(), public._entries_saleform_lock61(),
  public._sfl_total61(text, jsonb), public._bil_ro61(), public._bi_csv61(text[], jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase62.sql
-- ============================================================
-- Phase 62 (bos62) - P3 gaps #21 SMS/WhatsApp queue, #22 payment-gateway intents + webhook log + reconciliation,
--                    #23 accounting CSV export, #30 AI Assistant access (owner by default, others only with grant assistant_use).
-- Additive + paste-twice safe. No provider credentials anywhere: sending SMS/WhatsApp is done by tools/notify_sms.py (env secrets, default OFF);
-- the payment gateway is called ONLY by a (not yet deployed) Edge function whose contract is in docs/INTEGRATIONS_P3C.md. Nothing here calls a provider.
-- Runs after phase51 (uses phase40 accounts, phase46 ops bot (_is_ops 'notify'), phase47 assistant).
--   #21  tables: notify_templates, notify_optin, notify_outbox (queue: status, attempts, next_try_at) ; rule notify_sms_on (OFF)
--        browser: notify_template_save, notify_optin_set, notify_enqueue, notify_cancel, notify_outbox_summary
--        worker (ops bot purpose 'notify' or owner): notify_outbox_claim, notify_outbox_report
--   #22  tables: payment_intents, payment_webhook_log (append-only, unique (provider, event_id)) ; view payment_recon_v (not browser-readable) ;
--        rule pay_gateway_on (OFF) ; fns payment_intent_create, payment_intent_set_ref, payment_intent_link, payment_webhook_receive, payment_recon
--   #23  acct_export_csv(kind, from, to, loc) read-only; owner or accounts_manage (columns documented in docs/INTEGRATIONS_P3C.md)
--   #30  _assistant_ok() tightened (owner or explicit assistant_use only); grant_defs row (idempotent); assistant_access_list() owner-only
-- ============================================================

-- ---------- rules (default OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('notify_sms_on', 'integrations', 'switch', 'false', null, null, null, null, 'SMS / WhatsApp কিউ চালু', 'SMS / WhatsApp queue চালু', 'SMS / WhatsApp queue is on',
  'বন্ধ থাকলে কিছু কিউতে ঢোকে না ও কিছু পাঠানো হয় না। পাঠায় tools/notify_sms.py (গোপন চাবি শুধু GitHub secret-এ)।', 'Off = nothing is queued or sent. Sending is done by tools/notify_sms.py (secrets live only in GitHub secrets).', 620),
 ('notify_sms_max_tries', 'integrations', 'number', '5', 'times', null, 1, 20, 'একটি বার্তা সর্বোচ্চ কতবার চেষ্টা', 'একটি message সর্বোচ্চ কতবার try', 'Most send attempts per message', null, null, 621),
 ('pay_gateway_on', 'integrations', 'switch', 'false', null, null, null, null, 'পেমেন্ট গেটওয়ে রেকর্ড চালু', 'Payment gateway record চালু', 'Payment-gateway records are on',
  'শুধু রেকর্ড ও মিলানো; অ্যাপ কোনো গেটওয়ে কল করে না। চালু করার আগে Edge function লাগবে।', 'Records and reconciliation only; the app never calls a gateway. An Edge function is needed first.', 622)
on conflict (key) do nothing;

-- ---------- grants (idempotent) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_use', 'reports', 90, 'ব্যবসার সহকারী ব্যবহার', 'Business assistant ব্যবহার', 'Use the business assistant', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_use');

-- ---------- small helpers (closed to browsers) ----------
create or replace function public._i62_ok() returns boolean   -- owner or customer manager: SMS queue / opt-in / templates
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage')
    or exists (select 1 from public.locations l where public.has_grant('customer_manage', l.id)));
$$;
create or replace function public._i62_ops() returns boolean   -- the ops bot (purpose notify) or the owner
language sql stable security definer set search_path = public as $$
  select public.is_active() and public.is_owner() or public._is_ops('notify');
$$;
create or replace function public._i62_pay_ok() returns boolean   -- owner or accounts manager
language sql stable security definer set search_path = public as $$ select public._acct_manage(); $$;
create or replace function public._i62_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
create or replace function public._i62_phone(p text) returns text language plpgsql immutable set search_path = public as $$
declare d text := regexp_replace(coalesce(p, ''), '[\s\-\(\)]', '', 'g');
begin
  if d ~ '^01[0-9]{9}$' then return '+880' || substr(d, 2); end if;
  if d ~ '^8801[0-9]{9}$' then return '+' || d; end if;
  if d ~ '^\+[1-9][0-9]{7,14}$' then return d; end if;
  return null;
end $$;
create or replace function public._i62_csv(p text) returns text language sql immutable set search_path = public as $$
  -- RFC 4180 quoting + spreadsheet formula guard (a cell never starts with = + - @ tab CR)
  select case when p is null then ''
    else (select case when v ~ '[",\r\n]' then '"' || replace(v, '"', '""') || '"' else v end
            from (select case when p ~ '^[=+\-@\t\r]' then '''' || p else p end v) s) end;
$$;

-- ============================================================
-- #21  SMS / WhatsApp queue
-- ============================================================
create table if not exists public.notify_templates (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  channel text not null default 'sms' check (channel in ('sms', 'whatsapp')),
  body_bn text not null check (length(body_bn) between 1 and 480),
  body_en text not null check (length(body_en) between 1 and 480),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create table if not exists public.notify_optin (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  status text not null check (status in ('in', 'out')),
  source text not null default 'owner_entry' check (source in ('customer_consent', 'owner_entry')),
  note text check (note is null or length(note) <= 200),
  changed_by uuid, changed_at timestamptz not null default now(),
  unique (customer_id, channel)
);
create table if not exists public.notify_optin_log (          -- append-only history of every opt-in / opt-out
  id bigserial primary key, customer_id uuid not null, channel text not null, status text not null, source text, note text,
  changed_by uuid, changed_at timestamptz not null default now()
);
create table if not exists public.notify_outbox (
  id bigserial primary key,
  client_id uuid unique,
  customer_id uuid references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  to_phone text not null check (to_phone ~ '^\+[1-9][0-9]{7,14}$'),
  template_code text not null references public.notify_templates(code),
  body text not null check (length(body) between 1 and 480),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled')),
  attempts int not null default 0 check (attempts >= 0),
  max_attempts int not null default 5 check (max_attempts between 1 and 20),
  next_try_at timestamptz not null default now(),
  last_error text check (last_error is null or length(last_error) <= 300),
  provider_ref text check (provider_ref is null or length(provider_ref) <= 100),
  source_type text, source_id text,
  created_by uuid, created_at timestamptz not null default now(),
  claimed_at timestamptz, sent_at timestamptz
);
create unique index if not exists notify_outbox_src_uq on public.notify_outbox (source_type, source_id, template_code) where source_type is not null and source_id is not null;
create index if not exists notify_outbox_due on public.notify_outbox (status, next_try_at);

do $$ declare t text; begin
  foreach t in array array['notify_templates', 'notify_optin', 'notify_optin_log', 'notify_outbox'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists notify_optin_log_ro on public.notify_optin_log;
create trigger notify_optin_log_ro before update or delete on public.notify_optin_log for each row execute function public._i62_ro();
drop trigger if exists audit_notify_outbox on public.notify_outbox;
create trigger audit_notify_outbox after insert or update on public.notify_outbox for each row execute function public.log_change('id');
drop trigger if exists audit_notify_templates on public.notify_templates;
create trigger audit_notify_templates after insert or update on public.notify_templates for each row execute function public.log_change('code');
revoke usage, select on sequence public.notify_optin_id_seq, public.notify_optin_log_id_seq, public.notify_outbox_id_seq from public, anon, authenticated;

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('due_reminder', 'sms', 'প্রিয় {name}, আপনার বাকি {amount} টাকা। ধন্যবাদ। - {shop}', 'Dear {name}, your balance due is {amount} Taka. Thank you. - {shop}'),
 ('order_ready', 'sms', '{name}, আপনার অর্ডার {ref} প্রস্তুত। - {shop}', '{name}, your order {ref} is ready. - {shop}'),
 ('thanks', 'sms', '{name}, কেনাকাটার জন্য ধন্যবাদ। - {shop}', '{name}, thank you for shopping with us. - {shop}')
on conflict (code) do nothing;

create or replace function public.notify_template_save(p_code text, p_channel text, p_body_bn text, p_body_en text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_channel not in ('sms', 'whatsapp') or p_active is null
     or coalesce(length(btrim(p_body_bn)), 0) not between 1 and 480 or coalesce(length(btrim(p_body_en)), 0) not between 1 and 480 then raise exception 'bad_input'; end if;
  insert into public.notify_templates (code, channel, body_bn, body_en, active, updated_by) values (p_code, p_channel, btrim(p_body_bn), btrim(p_body_en), p_active, auth.uid())
    on conflict (code) do update set channel = excluded.channel, body_bn = excluded.body_bn, body_en = excluded.body_en, active = excluded.active, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('code', p_code, 'active', p_active);
end $$;

create or replace function public.notify_optin_set(p_customer uuid, p_channel text, p_in boolean, p_source text default 'owner_entry', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_customer is null or p_in is null or p_channel not in ('sms', 'whatsapp') or coalesce(p_source, 'owner_entry') not in ('customer_consent', 'owner_entry')
     or (p_note is not null and length(p_note) > 200) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  if p_in and public._i62_phone((select mobile from public.customers where id = p_customer)) is null then raise exception 'bad_phone'; end if;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid());
  if not p_in then   -- opting out cancels what is still waiting
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st);
end $$;

create or replace function public.notify_enqueue(p_client uuid, p_customer uuid, p_channel text, p_template text, p_vars jsonb default '{}'::jsonb, p_lang text default 'bn',
                                                 p_source_type text default null, p_source_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
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
end $$;

create or replace function public.notify_cancel(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  update public.notify_outbox set status = 'cancelled', last_error = 'cancelled_by_staff' where id = p_id and status in ('queued', 'failed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_cancellable'; end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

create or replace function public.notify_outbox_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('notify_sms_on'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.notify_outbox group by status) s), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts, 'template', template_code,
        'to', left(to_phone, 6) || '****' || right(to_phone, 2), 'last_error', last_error, 'created_at', created_at, 'sent_at', sent_at) order by id desc)
        from (select * from public.notify_outbox order by id desc limit 50) r), '[]'::jsonb));
end $$;

-- worker side (tools/notify_sms.py): claim due rows, then report each result. A stale 'sending' (> 15 min) is claimable again.
create or replace function public.notify_outbox_claim(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100); res jsonb;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then return jsonb_build_object('on', false, 'rows', '[]'::jsonb); end if;
  with c as (
    select id from public.notify_outbox
     where ((status = 'queued' and next_try_at <= now()) or (status = 'sending' and claimed_at < now() - interval '15 minutes')) and attempts < max_attempts
     order by id limit lim for update skip locked),
  u as (update public.notify_outbox o set status = 'sending', attempts = o.attempts + 1, claimed_at = now() from c where o.id = c.id
        returning o.id, o.channel, o.to_phone, o.body, o.attempts)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'to', to_phone, 'body', body, 'attempt', attempts) order by id), '[]'::jsonb) into res from u;
  return jsonb_build_object('on', true, 'rows', res);
end $$;

create or replace function public.notify_outbox_report(p_id bigint, p_ok boolean, p_provider_ref text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.notify_outbox;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if p_id is null or p_ok is null then raise exception 'bad_input'; end if;
  select * into r from public.notify_outbox where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'sending' then return jsonb_build_object('id', p_id, 'status', r.status, 'ignored', true); end if;
  if p_ok then
    update public.notify_outbox set status = 'sent', sent_at = now(), provider_ref = left(p_provider_ref, 100), last_error = null where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'sent');
  end if;
  if r.attempts >= r.max_attempts then
    update public.notify_outbox set status = 'failed', last_error = left(coalesce(p_error, 'error'), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'failed');
  end if;
  update public.notify_outbox set status = 'queued', last_error = left(coalesce(p_error, 'error'), 300),
      next_try_at = now() + (interval '1 minute' * power(2, r.attempts)::int) where id = p_id;   -- back-off 2, 4, 8, 16 ... minutes
  return jsonb_build_object('id', p_id, 'status', 'queued', 'retry', true);
end $$;

-- ============================================================
-- #22  payment gateway: intents + webhook receipt log + reconciliation (no live call anywhere)
-- ============================================================
create table if not exists public.payment_intents (
  id bigserial primary key,
  client_id uuid unique,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  provider_ref text check (provider_ref is null or length(provider_ref) between 3 and 100),
  sale_id uuid references public.sales(id),
  customer_id uuid references public.customers(id),
  location_id int not null references public.locations(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded')),
  paid_amount numeric check (paid_amount is null or (paid_amount >= 0 and paid_amount <= 1000000000000)),
  sale_payment_id bigint references public.sale_payments(id),   -- manual link; otherwise matched by ref
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists payment_intents_ref_uq on public.payment_intents (provider, provider_ref) where provider_ref is not null;
create table if not exists public.payment_webhook_log (
  id bigserial primary key,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  event_id text not null check (length(event_id) between 1 and 120),
  provider_ref text, event_type text check (event_type is null or length(event_type) <= 60),
  status text, amount numeric, signature_ok boolean not null,
  payload jsonb not null default '{}'::jsonb,
  applied boolean not null default false, note text,
  received_at timestamptz not null default now(),
  unique (provider, event_id)
);
do $$ declare t text; begin
  foreach t in array array['payment_intents', 'payment_webhook_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_pay_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists payment_webhook_log_ro on public.payment_webhook_log;
create trigger payment_webhook_log_ro before update or delete on public.payment_webhook_log for each row execute function public._i62_ro();
drop trigger if exists audit_payment_intents on public.payment_intents;
create trigger audit_payment_intents after insert or update on public.payment_intents for each row execute function public.log_change('id');
revoke usage, select on sequence public.payment_intents_id_seq, public.payment_webhook_log_id_seq from public, anon, authenticated;


create or replace function public.payment_intent_create(p_client uuid, p_provider text, p_sale uuid, p_customer uuid, p_loc int, p_amount numeric,
                                                        p_provider_ref text default null, p_currency text default 'BDT') returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.payment_intents; nid bigint;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then raise exception 'gateway_off'; end if;
  if p_client is null or p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_loc is null or p_amount is null or p_amount <= 0 or p_amount > 1000000000000
     or p_amount <> round(p_amount, 2) or coalesce(p_currency, 'BDT') !~ '^[A-Z]{3}$' or (p_provider_ref is not null and length(p_provider_ref) not between 3 and 100) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not (public._acct_all() or public.can_loc(p_loc) or public._is_ops('notify')) then raise exception 'not allowed for this location'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.payment_intents where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  insert into public.payment_intents (client_id, provider, provider_ref, sale_id, customer_id, location_id, amount, currency, created_by)
    values (p_client, p_provider, p_provider_ref, p_sale, p_customer, p_loc, round(p_amount, 2), coalesce(p_currency, 'BDT'), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'status', 'created', 'duplicate', false);
end $$;

create or replace function public.payment_intent_set_ref(p_id bigint, p_provider_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payment_intents;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if p_provider_ref is null or length(p_provider_ref) not between 3 and 100 then raise exception 'bad_input'; end if;
  select * into r from public.payment_intents where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.provider_ref is not null and r.provider_ref <> p_provider_ref then raise exception 'ref_already_set'; end if;
  update public.payment_intents set provider_ref = p_provider_ref, status = case when status = 'created' then 'pending' else status end, updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'provider_ref', p_provider_ref);
end $$;

create or replace function public.payment_intent_link(p_id bigint, p_sale_payment bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sale_payments where id = p_sale_payment) then raise exception 'payment_not_found'; end if;
  if exists (select 1 from public.payment_intents where sale_payment_id = p_sale_payment and id <> p_id) then raise exception 'payment_already_linked'; end if;
  update public.payment_intents set sale_payment_id = p_sale_payment, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'sale_payment_id', p_sale_payment);
end $$;

-- called ONLY by the Edge function (logged in as the ops bot) AFTER it verified the provider signature. Idempotent on (provider, event_id).
create or replace function public.payment_webhook_receive(p_provider text, p_event_id text, p_provider_ref text, p_event_type text, p_status text, p_amount numeric,
                                                          p_signature_ok boolean, p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.payment_intents; ap boolean := false; nt text; rk int; rk0 int; n int; pl jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then return jsonb_build_object('off', true); end if;
  if p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_event_id is null or length(p_event_id) not between 1 and 120 or p_signature_ok is null
     or (p_status is not null and p_status not in ('pending', 'succeeded', 'failed', 'cancelled', 'refunded'))
     or (p_amount is not null and (p_amount < 0 or p_amount > 1000000000000)) or (p_provider_ref is not null and length(p_provider_ref) > 100)
     or (p_event_type is not null and length(p_event_type) > 60) or length(coalesce(p_payload, '{}'::jsonb)::text) > 20000 then raise exception 'bad_input'; end if;
  pl := coalesce(p_payload, '{}'::jsonb);
  if jsonb_typeof(pl) = 'object' then pl := pl - array['authorization', 'signature', 'secret', 'token', 'password', 'api_key', 'apikey', 'card', 'card_number', 'cvv']; end if;
  if not p_signature_ok then nt := 'bad_signature';
  else
    select * into it from public.payment_intents where provider = p_provider and provider_ref = p_provider_ref for update;
    if not found then nt := 'no_intent';
    elsif p_status is null then nt := 'no_status';
    else
      rk := case p_status when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      rk0 := case it.status when 'created' then 0 when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      if rk > rk0 or (rk = rk0 and rk = 2 and it.status <> p_status) then ap := true; nt := 'applied'; else nt := 'stale_event'; end if;
    end if;
  end if;
  insert into public.payment_webhook_log (provider, event_id, provider_ref, event_type, status, amount, signature_ok, payload, applied, note)
    values (p_provider, p_event_id, p_provider_ref, p_event_type, p_status, p_amount, p_signature_ok, pl, ap, nt) on conflict (provider, event_id) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  if ap then
    update public.payment_intents set status = p_status, updated_at = now(),
        paid_amount = case when p_status = 'succeeded' then p_amount else paid_amount end where id = it.id;
  end if;
  return jsonb_build_object('duplicate', false, 'applied', ap, 'note', nt);
end $$;

-- reconciliation: one row per intent against sale_payments (matched by explicit link, else mobile payment with the same ref). Not readable by browsers: use payment_recon().
create or replace view public.payment_recon_v as
  select i.id as intent_id, i.provider, i.provider_ref, i.sale_id, i.location_id, i.amount as intent_amount, i.status as intent_status, i.paid_amount,
         sp.id as sale_payment_id, sp.amount as payment_amount, sp.voided as payment_voided,
         case when i.status in ('created', 'pending') then 'open'
              when i.status in ('failed', 'cancelled') then 'closed_unpaid'
              when i.status = 'refunded' then 'refunded'
              when sp.id is null then 'missing_payment'
              when sp.voided then 'voided_payment'
              when sp.amount <> coalesce(i.paid_amount, i.amount) or coalesce(i.paid_amount, i.amount) <> i.amount then 'amount_mismatch'
              else 'matched' end as state,
         coalesce(i.paid_amount, 0) - coalesce(sp.amount, 0) as diff
    from public.payment_intents i
    left join lateral (select p.* from public.sale_payments p
                        where p.id = i.sale_payment_id
                           or (i.sale_payment_id is null and i.provider_ref is not null and p.mode = 'mobile' and p.ref = i.provider_ref and not exists
                               (select 1 from public.payment_intents i2 where i2.sale_payment_id = p.id))
                        order by (p.id = i.sale_payment_id) desc, p.id limit 1) sp on true;
revoke all on public.payment_recon_v from public, anon, authenticated;

create or replace function public.payment_recon(p_from date default null, p_to date default null, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fr timestamptz; tt timestamptz; v_all boolean := public._acct_all();
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if p_state is not null and p_state not in ('open', 'closed_unpaid', 'refunded', 'missing_payment', 'voided_payment', 'amount_mismatch', 'matched') then raise exception 'bad_input'; end if;
  fr := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30)::timestamp at time zone 'Asia/Dhaka';
  tt := (coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date) + 1)::timestamp at time zone 'Asia/Dhaka';
  if tt - fr > interval '400 days' then raise exception 'bad_range'; end if;
  return jsonb_build_object('on', public.rule_on('pay_gateway_on'),
    'counts', coalesce((select jsonb_object_agg(state, n) from (select v.state, count(*) n from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
                          where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) group by v.state) s), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.intent_id desc) from (
        select v.* from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
         where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) and (p_state is null or v.state = p_state)
         order by v.intent_id desc limit 500) x), '[]'::jsonb),
    'orphan_events', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'provider', w.provider, 'event_id', w.event_id, 'provider_ref', w.provider_ref, 'status', w.status,
          'amount', w.amount, 'note', w.note, 'received_at', w.received_at) order by w.id desc)
        from (select * from public.payment_webhook_log where received_at >= fr and received_at < tt and note in ('no_intent', 'bad_signature') order by id desc limit 200) w), '[]'::jsonb));
end $$;

-- ============================================================
-- #23  accounting export (read-only, generic CSV)
-- ============================================================
create or replace function public.acct_export_csv(p_kind text, p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); cr text := E'\r\n';
  hdr text; body text; n int; tot int; cap constant int := 50000; tb jsonb; td numeric := 0; tc numeric := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('journal', 'trial_balance') then raise exception 'bad_input'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 3660 then raise exception 'bad_range'; end if;
  if p_kind = 'journal' then
    hdr := 'entry_id,entry_date,location_code,source_type,source_id,subtype,status,reverses_id,entry_memo,line_no,account_code,account_name_en,account_type,debit,credit,line_location_code,party_type,party_id,line_memo';
    select count(*) into tot from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
    select count(*), string_agg(r.line, cr order by r.entry_date, r.entry_id, r.line_no) into n, body from (
      select e.entry_date, e.id entry_id, l.line_no,
        concat_ws(',', e.id::text, e.entry_date::text, public._i62_csv(le.code), public._i62_csv(e.source_type), public._i62_csv(e.source_id), public._i62_csv(e.subtype), e.status,
          coalesce(e.reverses_id::text, ''), public._i62_csv(e.memo), l.line_no::text, public._i62_csv(a.code), public._i62_csv(a.name_en), a.type,
          to_char(l.debit, 'FM999999999999990.00'), to_char(l.credit, 'FM999999999999990.00'), public._i62_csv(ll.code), coalesce(l.party_type, ''), public._i62_csv(l.party_id), public._i62_csv(l.memo)) line
        from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
        left join public.locations le on le.id = e.location_id left join public.locations ll on ll.id = l.location_id
       where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc)
       order by e.entry_date, e.id, l.line_no limit cap) r;
    return jsonb_build_object('kind', 'journal', 'filename', 'journal_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'entries', tot, 'rows', coalesce(n, 0),
      'truncated', coalesce(n, 0) >= cap, 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
  end if;
  tb := public.acct_trial_balance(fr, to_, p_loc);
  hdr := 'account_code,account_name_en,account_name_bn,account_type,is_group,opening_debit,opening_credit,period_debit,period_credit,closing_debit,closing_credit';
  select count(*), string_agg(concat_ws(',', public._i62_csv(x ->> 'code'), public._i62_csv(x ->> 'name_en'), public._i62_csv(x ->> 'name_bn'), x ->> 'type', x ->> 'is_group',
          to_char((x ->> 'open_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'open_cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'close_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'close_cr')::numeric, 'FM999999999999990.00')), cr order by x ->> 'code')
    into n, body from jsonb_array_elements(tb -> 'rows') x;
  return jsonb_build_object('kind', 'trial_balance', 'filename', 'trial_balance_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'rows', coalesce(n, 0),
    'total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'balanced', tb -> 'balanced', 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
end $$;

-- ============================================================
-- #30  AI Assistant access: owner by default, anyone else ONLY with the explicit grant assistant_use (bos62)
-- ============================================================
create or replace function public._assistant_ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then return false; end if;
  if not public.rule_on('assistant_on') then return false; end if;
  -- bos62: head_management and the assistant_roles rule no longer open the assistant; only the owner or an explicit assistant_use grant (any place) does
  return public.is_owner() or public._assistant_any_grant('assistant_use');
end $$;

create or replace function public.assistant_access_list() returns jsonb   -- owner only: who holds assistant_use (per person, per role)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('assistant_on'),
    'users', coalesce((select jsonb_agg(jsonb_build_object('user_id', g.user_id, 'name', p.full_name, 'location_id', g.location_id, 'valid_until', g.valid_until) order by p.full_name)
                         from public.user_grants g join public.profiles p on p.id = g.user_id where g.grant_code = 'assistant_use' and (g.valid_until is null or g.valid_until > now())), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(rg.role_code order by rg.role_code) from public.rule_grants rg where rg.grant_code = 'assistant_use' and rg.allowed), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
revoke all on function public._i62_ok(), public._i62_ops(), public._i62_ro(), public._i62_phone(text), public._i62_csv(text), public._i62_pay_ok() from public, anon, authenticated;
grant execute on function public._i62_ok(), public._i62_pay_ok() to authenticated;      -- used inside RLS policies
revoke all on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() from public, anon;
grant execute on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() to authenticated;

-- ---------------------------------------------------------------- phase70.sql
-- ============================================================
-- Phase 70 - Gap #17: restore drill (record of "did we prove the backup can be restored?")
-- Run AFTER phase46 (backup). Additive and idempotent (paste it twice = no error). Nothing is deleted.
--   * restore_drills            append-only trail of drills (tools/restore_drill.py prints the result; the owner records it here)
--   * restore_drill_record(...) owner only
--   * restore_drill_list(n)     owner only
--   * restore_drill_status()    owner only: last drill, its age, warn when none in restore_drill_warn_days (default 90)
--   * rule restore_drill_warn_days (90)
--   * bos70: public._backup_tables() re-created ONLY to stop the blunt "token" column filter from hiding assistant_usage
--            (its tokens_in / tokens_out are plain counters, not secrets). attendance_devices (token_hash), ops_*, login_*, *_secret*,
--            backup_runs, notifications, notification_reads stay excluded - see docs/RESTORE_DRILL.md.
-- ============================================================

create table if not exists public.restore_drills (
  id bigserial primary key,
  drilled_at timestamptz not null default now(),
  backup_name text not null check (length(btrim(backup_name)) between 1 and 200),
  result text not null check (result in ('pass', 'fail')),
  tables_ok boolean not null default false,
  rows_ok boolean not null default false,
  notes text check (notes is null or length(notes) <= 2000),
  recorded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists restore_drills_at on public.restore_drills (drilled_at desc);

create or replace function public._append_only70() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
revoke all on function public._append_only70() from public, anon, authenticated;
drop trigger if exists restore_drills_ro on public.restore_drills;
create trigger restore_drills_ro before update or delete on public.restore_drills for each row execute function public._append_only70();

alter table public.restore_drills enable row level security;
revoke all on public.restore_drills from public, anon, authenticated;
grant select on public.restore_drills to authenticated;
revoke usage, select on sequence public.restore_drills_id_seq from public, anon, authenticated;
drop policy if exists restore_drills_read on public.restore_drills;
create policy restore_drills_read on public.restore_drills for select to authenticated using (public.is_owner());

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('restore_drill_warn_days', 'notify', 'number', '90', 'দিন', null, 7, 730, 'রিস্টোর ড্রিল কত দিনের মধ্যে একবার করতে হবে', 'Restore drill কত দিনে একবার', 'Run a restore drill at least every (days)', 'এর বেশি দিন ড্রিল না হলে অ্যাপ সতর্ক করে।', 'The app warns when no drill was recorded within this many days.', 331)
 on conflict (key) do nothing;

create or replace function public.restore_drill_record(p_backup_name text, p_result text, p_tables_ok boolean default false, p_rows_ok boolean default false,
                                                       p_notes text default null, p_drilled_at timestamptz default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_backup_name is null or length(btrim(p_backup_name)) not between 1 and 200 then raise exception 'bad_input'; end if;
  if p_result is null or p_result not in ('pass', 'fail') then raise exception 'bad_input'; end if;
  if p_notes is not null and length(p_notes) > 2000 then raise exception 'bad_input'; end if;
  if p_drilled_at is not null and p_drilled_at > now() + interval '5 minutes' then raise exception 'bad_input'; end if;
  if p_result = 'pass' and not (coalesce(p_tables_ok, false) and coalesce(p_rows_ok, false)) then raise exception 'pass_needs_tables_and_rows_ok'; end if;
  insert into public.restore_drills (drilled_at, backup_name, result, tables_ok, rows_ok, notes, recorded_by)
    values (coalesce(p_drilled_at, now()), btrim(p_backup_name), p_result, coalesce(p_tables_ok, false), coalesce(p_rows_ok, false), nullif(btrim(coalesce(p_notes, '')), ''), auth.uid())
    returning id into rid;
  return rid;
end $$;

create or replace function public.restore_drill_list(p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.drilled_at desc, x.id desc)
    from (select d.id, d.drilled_at, d.backup_name, d.result, d.tables_ok, d.rows_ok, d.notes, d.recorded_by
            from public.restore_drills d order by d.drilled_at desc, d.id desc limit least(greatest(coalesce(p_limit, 20), 1), 200)) x), '[]'::jsonb);
end $$;

create or replace function public.restore_drill_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare warn_days numeric := coalesce(public.rule_num('restore_drill_warn_days'), 90); last_ record; lastpass record; age numeric; agep numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into last_ from public.restore_drills order by drilled_at desc, id desc limit 1;
  select * into lastpass from public.restore_drills where result = 'pass' order by drilled_at desc, id desc limit 1;
  age := case when last_.id is null then null else round(extract(epoch from (now() - last_.drilled_at)) / 86400, 1) end;
  agep := case when lastpass.id is null then null else round(extract(epoch from (now() - lastpass.drilled_at)) / 86400, 1) end;
  return jsonb_build_object('warn_days', warn_days, 'drills', (select count(*) from public.restore_drills),
    'last', case when last_.id is null then null else jsonb_build_object('id', last_.id, 'at', last_.drilled_at, 'result', last_.result, 'backup_name', last_.backup_name) end,
    'age_days', age, 'last_pass_age_days', agep,
    'never', last_.id is null,
    'warn', (agep is null or agep > warn_days),
    'last_failed', coalesce(last_.result = 'fail', false));
end $$;

-- bos70: same as phase46 except the column filter no longer matches tokens_in / tokens_out (assistant_usage counters)
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text !~ '^tokens_(in|out)$'
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;

do $$ declare f text; r regprocedure; begin
  foreach f in array array['restore_drill_record', 'restore_drill_list', 'restore_drill_status'] loop
    for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f loop
      execute format('revoke all on function %s from public, anon, authenticated', r);
      execute format('grant execute on function %s to authenticated', r);
    end loop;
  end loop;
end $$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase71.sql
-- ============================================================
-- Phase 71 (bos71) - gap #18 two-factor (2FA, TOTP) for staff: SAFE CORE.
-- Factors live in Supabase Auth (auth.mfa_factors); the owner must enable MFA in the dashboard (docs/TWOFA.md). PIN scheme is NOT touched (#16 stays postponed).
--   rules   : twofa_required_roles (text, comma list, default empty = nobody is told they must), twofa_enforce_owner_writes (switch, default OFF)
--   helpers : _aal2() reads the jwt claim aal; _twofa_has_factor(uuid); _twofa_guard71()
--   reads   : twofa_policy() (caller), twofa_status_report() (owner only, no secrets)
--   guard   : when twofa_enforce_owner_writes is ON, set_rule / path_switch_set / acct_set_start / year_close_run / set_user_grant refuse
--             ('twofa_required') unless the jwt aal is aal2 - but ONLY for a user who has a verified factor (so nobody is locked out by switching it on).
-- Additive + paste-twice safe. Lock-out escape hatch (SQL editor, role postgres): update public.rules set value='false'::jsonb where key='twofa_enforce_owner_writes';
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('twofa_required_roles', 'security', 'text', '""', null, null, null, null,
  'যেসব ভূমিকার 2FA লাগবে (কমা দিয়ে)', '2FA লাগবে এমন role (comma দিয়ে)', 'Roles that should use 2FA (comma list)',
  'ফাঁকা = কাউকে বাধ্য করা হয় না। যেমন: owner,accountant। এটা শুধু জানানোর নীতি; লগইন আটকায় না।', 'ফাঁকা = কেউ forced না। যেমন owner,accountant। শুধু policy জানায়, login আটকায় না।', 'Empty = nobody is told they must. Example: owner,accountant. Informational only; it does not block login.', 710),
 ('twofa_enforce_owner_writes', 'security', 'switch', 'false', null, null, null, null,
  'মালিকের সংবেদনশীল কাজে 2FA বাধ্যতামূলক', 'Owner-এর sensitive কাজে 2FA বাধ্যতামূলক', 'Require 2FA code for the most sensitive owner actions',
  'চালু হলে নিয়ম বদল, পথ সুইচ, হিসাব শুরুর তারিখ, বছর-শেষ ক্লোজ ও অনুমতি দেওয়া — 2FA কোড দিয়ে ঢোকা ছাড়া হবে না। শুধু যাঁর যাচাই-করা 2FA আছে তাঁর জন্য।', 'ON হলে rule বদল, path switch, accounting start, year close, grant দেওয়া — 2FA code দিয়ে login ছাড়া হবে না। শুধু verified 2FA আছে এমন user-এর জন্য।', 'When ON: changing rules, path switches, accounting start date, year close and granting permissions need a session verified with a 2FA code. Applies only to users who HAVE a verified factor.', 711)
on conflict (key) do nothing;

-- jwt claim reader (what auth.jwt()->>'aal' returns on Supabase; PostgREST puts the claims in request.jwt.claims)
create or replace function public._aal2() returns boolean
language plpgsql stable set search_path = public as $$
declare c jsonb;
begin
  begin c := nullif(current_setting('request.jwt.claims', true), '')::jsonb; exception when others then c := null; end;
  return coalesce(c ->> 'aal', nullif(current_setting('request.jwt.claim.aal', true), ''), '') = 'aal2';
end $$;

create or replace function public._twofa_has_factor(p_user uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r boolean := false;
begin
  if p_user is null or to_regclass('auth.mfa_factors') is null then return false; end if;
  execute 'select exists (select 1 from auth.mfa_factors where user_id = $1 and status = ''verified'')' into r using p_user;
  return coalesce(r, false);
end $$;

create or replace function public._twofa_guard71() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if public.rule_on('twofa_enforce_owner_writes') and not public._aal2() and public._twofa_has_factor(auth.uid()) then
    raise exception 'twofa_required: sign in again and enter your 2FA code (aal2) for this action';
  end if;
end $$;

create or replace function public.twofa_policy() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); lst text[]; roles text[]; req boolean; hf boolean; aal2 boolean := public._aal2();
begin
  if uid is null or not public.is_active() then raise exception 'not allowed'; end if;
  lst := array(select btrim(x) from unnest(string_to_array(lower(coalesce(public.rule_val('twofa_required_roles') #>> '{}', '')), ',')) x where btrim(x) <> '');
  roles := array(select role_code from public.user_roles where user_id = uid);
  req := roles && lst;
  hf := public._twofa_has_factor(uid);
  return jsonb_build_object('required', req, 'has_verified_factor', hf, 'aal2', aal2,
    'enforce_owner_writes', public.rule_on('twofa_enforce_owner_writes'),
    'listed_roles', to_jsonb(lst), 'my_roles', to_jsonb(roles),
    'must_enroll', req and not hf,
    'sensitive_actions_blocked_now', public.rule_on('twofa_enforce_owner_writes') and hf and not aal2);
end $$;

create or replace function public.twofa_status_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb; lst text[];
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  lst := array(select btrim(x) from unnest(string_to_array(lower(coalesce(public.rule_val('twofa_required_roles') #>> '{}', '')), ',')) x where btrim(x) <> '');
  select coalesce(jsonb_agg(jsonb_build_object('user_id', p.id, 'staff_id', p.staff_id, 'name', p.full_name, 'roles', to_jsonb(rl.roles),
      'verified_factors', f.n, 'has_2fa', f.n > 0, 'required', rl.roles && lst, 'missing', (rl.roles && lst) and f.n = 0) order by p.staff_id), '[]'::jsonb) into out
  from public.profiles p
  cross join lateral (select coalesce(array_agg(role_code), '{}'::text[]) as roles from public.user_roles ur where ur.user_id = p.id) rl
  cross join lateral (select case when to_regclass('auth.mfa_factors') is null then 0 else
      (select count(*)::int from auth.mfa_factors m where m.user_id = p.id and m.status = 'verified') end as n) f
  where p.status = 'active';
  return jsonb_build_object('enforce_owner_writes', public.rule_on('twofa_enforce_owner_writes'), 'listed_roles', to_jsonb(lst), 'users', out);
end $$;

-- guard injection: take the LIVE definition, add one line after the owner check (skips if already tagged bos71 or the pattern is absent)
do $do$
declare f text; def text; pat text := 'if not public.is_owner() then raise exception ''not allowed''; end if;';
begin
  foreach f in array array['set_rule(text,jsonb)', 'path_switch_set(text,integer,boolean,boolean,text,text)', 'acct_set_start(date)', 'year_close_run(date,date,text,uuid,boolean)', 'set_user_grant(uuid,text,integer,timestamp with time zone,boolean,text)'] loop
    if to_regprocedure('public.' || f) is null then raise notice 'bos71: % not found, skipped', f; continue; end if;
    def := pg_get_functiondef(to_regprocedure('public.' || f));
    if position('bos71' in def) > 0 then continue; end if;
    if position(pat in def) = 0 then raise notice 'bos71: owner check not found in %, skipped', f; continue; end if;
    def := replace(def, pat, pat || E'\n  perform public._twofa_guard71(); -- bos71');
    execute def;
  end loop;
end $do$;

revoke all on function public._aal2() from public, anon, authenticated;
revoke all on function public._twofa_has_factor(uuid) from public, anon, authenticated;
revoke all on function public._twofa_guard71() from public, anon, authenticated;
revoke all on function public.twofa_policy() from public, anon;
revoke all on function public.twofa_status_report() from public, anon;
grant execute on function public.twofa_policy() to authenticated;
grant execute on function public.twofa_status_report() to authenticated;

-- ---------------------------------------------------------------- phase72.sql
-- Phase 72 (Phase B of the audit fixes): one COGS source for the reports, balanced inventory lines, unknown-cost warnings,
-- inventory-vs-GL report, posting status.  Additive, paste-twice safe.  Nothing here posts a journal entry by itself.
--
--   B1 ROUNDING     _acct_docs: the inventory credit/debit lines of a sale, sale return, production and wastage are rounded per item type and the
--                   rounding remainder is put on the largest part (like _acct_purchase_alloc), so the entry always balances. New helper _acct_inv_split72.
--                   acct_post_pending now keeps its failures in acct_post_errors72 (upsert on failure, delete on success); acct_status reports them.
--   B2 ONE COGS     helper _cogs_lines72 = the ONE source for report COGS: stock-ledger unit_cost x qty of the sale (sale_out / sale_pack), net of sale
--                   returns at their original cost; item_costs only as FALLBACK for quantity whose ledger cost is NULL or 0; the fallback is kept apart
--                   (cogs_fallback). Used by biz_daily (so brand_pnl too), _p27_pl (so l1 / l3 / l4 / l5 / partner_calculate), _r3q_l2_margin.
--                   New: biz_daily_src72, _p27_src72, profit_source_check(from, to, loc).
--   B3 RETURN MARGIN the return revenue of a line is scaled by (return amount / sum of the return line amounts) = the sale's discount share, so
--                   costed_rev = revenue for a discounted sale that is returned (same helper).
--   B4 UNKNOWN COST revenue whose cost is neither in the ledger nor in item_costs is reported as unknown_cost_rev ("সাময়িক: খরচহীন বিক্রি").
--                   Cost 0 counts as UNKNOWN (reports, journal flag cogs_missing, production_post). New rule production_requires_cost (warn | refuse,
--                   default warn = today's behaviour): refuse blocks production_post (error cost_missing) when an ingredient cost is NULL or 0.
--   B5 inventory_vs_gl(date, loc): per item type GL (inv_finished / inv_raw / inv_pack mapping) vs stock valuation, the difference and the reasons
--                   computed from the ledger / journal. READ-ONLY.
--   B6 acct_status: last_post_at, pending, locked, errors (+ last errors). acct_overview / acct_income_statement carry unknown_cost_rev.
-- Tag: bos72 marks every changed line inside a re-created function (latest definition = phase52 _acct_docs, phase50 _p27_pl, phase40 acct_*, phase23 biz_daily ...).

-- ---------- rule ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('production_requires_cost', 'stock', 'choice', '"warn"', '["warn","refuse"]', null, null,
  'উৎপাদনে কোনো উপকরণের খরচ অজানা (ফাঁকা বা ০) থাকলে: সতর্কতা / আটকানো', 'Production এ কোনো উপকরণের cost অজানা (ফাঁকা বা ০) হলে: warn / refuse', 'When an ingredient cost is unknown (empty or 0): warn, or refuse the production',
  'warn = production is posted as before, the finished good has no cost and is flagged. refuse = production_post is refused (cost_missing) until every ingredient has a cost above 0.', 194)
on conflict (key) do nothing;

-- ---------- posting errors kept for the status strip (read only for the browser; written by acct_post_pending) ----------
create table if not exists public.acct_post_errors72 (
  source_type text not null, source_id text not null, error text not null,
  tries int not null default 1, first_at timestamptz not null default now(), last_at timestamptz not null default now(),
  primary key (source_type, source_id));
alter table public.acct_post_errors72 enable row level security;
revoke all on public.acct_post_errors72 from public, anon, authenticated;

-- ---------- B1: split the cost of a document over the item types; the remainder goes to the largest part ----------
create or replace function public._acct_inv_split72(p_ref_types text[], p_ref_id text, p_reasons text[], p_sign int)
returns table(t text, amt numeric) language sql stable set search_path = public as $$
  with g as (
    select it.item_type as ty, sum(p_sign * l.qty_delta * l.unit_cost) as raw
    from public.stock_ledger l join public.items it on it.id = l.item_id
    where l.ref_type = any (p_ref_types) and l.ref_id = p_ref_id and l.reason = any (p_reasons) and l.unit_cost is not null group by it.item_type),
  r as (select ty, round(raw, 2) as a, row_number() over (order by round(raw, 2) desc, ty nulls last) as rn from g),
  d as (select round((select sum(raw) from g), 2) - (select sum(a) from r) as rest)
  select r.ty, r.a + case when r.rn = 1 then (select rest from d) else 0 end from r;
$$;
revoke all on function public._acct_inv_split72(text[], text, text[], int) from public, anon, authenticated;

-- ---------- B2 / B3 / B4: the ONE COGS source for reports ----------
-- One row per (document, item). Positive numbers; src = 'sale' or 'return' (the caller subtracts returns).
--   led_cogs / led_rev : quantity whose stock-ledger cost is known (> 0): cost x qty from the ledger (return = the sale's original cost) and the revenue share of that quantity
--   fb_cogs  / fb_rev  : quantity with no usable ledger cost, costed from item_costs (ESTIMATE: "বইয়ের খরচ থেকে অনুমান")
--   unk_rev            : revenue whose cost is unknown in both places ("খরচহীন বিক্রি")
-- rev is the line amount after the sale's discount share; for a return it is scaled by (return amount / sum of the return lines) = the same discount share (B3).
create or replace function public._cogs_lines72(d1 date, d2 date, locs int[])
returns table(src text, doc_id uuid, d date, loc int, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id as iid, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
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
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta * l.unit_cost) filter (where coalesce(l.unit_cost, 0) > 0) as lc,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) > 0) as lq,
           sum((case docs.src when 'sale' then -1 else 1 end) * l.qty_delta) filter (where coalesce(l.unit_cost, 0) <= 0) as uq
    from public.stock_ledger l
    join docs on l.ref_id = docs.doc::text
             and ((docs.src = 'sale' and l.ref_type in ('sale', 'sale_pack') and l.reason in ('sale_out', 'issue_out'))
               or (docs.src = 'return' and l.ref_type = 'sale_return' and l.reason = 'sale_return'))
    group by 1, 2, 3),
  keys as (select src, doc, k from ln union select src, doc, k from led),
  j as (
    select docs.src, docs.doc, docs.d, docs.loc, keys.k, coalesce(ln.qty, 0) as jq, coalesce(ln.rev, 0) as rev,
           coalesce(led.lc, 0) as lc, coalesce(led.lq, 0) as lq, coalesce(led.uq, 0) as uq, (led.lq is not null or led.uq is not null) as hl, c.cost_price
    from keys join docs on docs.src = keys.src and docs.doc = keys.doc
    left join ln on ln.src = keys.src and ln.doc = keys.doc and ln.k = keys.k
    left join led on led.src = keys.src and led.doc = keys.doc and led.k = keys.k
    left join cst c on c.iid = keys.k),
  q as (select j.*, (case when hl then uq else jq end) as unk_q, (case when hl then lq + uq else jq end) as tot_q from j),
  w as (select q.*, (case when tot_q > 0 then rev * lq / tot_q else 0 end) as lrev from q)
  select w.src, w.doc, w.d, w.loc, nullif(w.k, '00000000-0000-0000-0000-000000000000'::uuid), w.jq, w.rev, w.lc, w.lrev,
         (case when w.cost_price is not null then w.unk_q * w.cost_price else 0 end),
         (case when w.cost_price is not null then w.rev - w.lrev else 0 end),
         (case when w.cost_price is null then w.rev - w.lrev else 0 end)
  from w;
$$;
revoke all on function public._cogs_lines72(date, date, int[]) from public, anon, authenticated;

-- places the caller may see (and optionally one place)
create or replace function public._cogs_locs72(p_loc int) returns int[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(l.id), '{}') from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id);
$$;
revoke all on function public._cogs_locs72(int) from public, anon, authenticated;

-- ---------- biz_daily: same columns, COGS from the one source (bos72) ----------
create or replace function public.biz_daily(p_from date, p_to date, p_loc integer default null::integer)
 returns table(sale_date date, location_id integer, n bigint, revenue numeric, discount numeric, void_n bigint, void_amt numeric, costed_rev numeric, cogs numeric)
 language plpgsql stable security definer set search_path to 'public'
as $function$
declare cost_ok boolean := public.biz_cost_ok(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ok as (select * from s where s.status = 'done'),
  ag as (  -- bos72: costed revenue and COGS from the one source (stock-ledger cost, item_costs only as fallback), returns subtracted with their discount share; bos14: the count_in_business filter on item_costs now lives in _cogs_lines72 (cst)
    select h.d as hd, h.loc as hl,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as cr,
           sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cg
    from public._cogs_lines72(p_from, p_to, public._cogs_locs72(p_loc)) h group by 1, 2),
  tot as (select ok.sale_date, ok.location_id, count(*) n, sum(ok.total) rev, sum(ok.discount) disc from ok group by 1, 2),
  vd as (select s.sale_date, s.location_id, count(*) vn, sum(s.total) va from s where s.status = 'void' group by 1, 2),
  rr as (select r.id, (r.created_at at time zone 'Asia/Dhaka')::date sale_date, r.location_id, r.amount from public.sale_returns r
         where net_on and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
           and (p_loc is null or r.location_id = p_loc) and r.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  rt as (select rr.sale_date, rr.location_id, sum(rr.amount) ra from rr group by 1, 2),
  k as (select t.sale_date, t.location_id from tot t union select v.sale_date, v.location_id from vd v union select x.sale_date, x.location_id from rt x)
  select k.sale_date, k.location_id,
         coalesce(t.n, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0), coalesce(t.disc, 0), coalesce(v.vn, 0), coalesce(v.va, 0),
         case when cost_ok then round(coalesce(a.cr, 0), 2) end, case when cost_ok then round(coalesce(a.cg, 0), 2) end
  from k
  left join tot t on t.sale_date = k.sale_date and t.location_id = k.location_id
  left join vd v on v.sale_date = k.sale_date and v.location_id = k.location_id
  left join rt x on x.sale_date = k.sale_date and x.location_id = k.location_id
  left join ag a on a.hd = k.sale_date and a.hl = k.location_id
  order by 1, 2;
end $function$;

-- new, read only: the split of the same COGS (ledger / fallback estimate) and the revenue whose cost is unknown
create or replace function public.biz_daily_src72(p_from date, p_to date, p_loc integer default null)
 returns table(sale_date date, location_id integer, cogs_ledger numeric, cogs_fallback numeric, fallback_rev numeric, unknown_cost_rev numeric)
 language plpgsql stable security definer set search_path to 'public'
as $function$
#variable_conflict use_column
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  select h.d, h.loc,
         case when cost_ok then round(sum((case h.src when 'sale' then 1 else -1 end) * h.led_cogs), 2) end,
         case when cost_ok then round(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_cogs), 2) end,
         round(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_rev), 2),
         round(sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev), 2)
  from public._cogs_lines72(p_from, p_to, public._cogs_locs72(p_loc)) h group by 1, 2 order by 1, 2;
end $function$;
grant execute on function public.biz_daily_src72(date, date, integer) to authenticated;
revoke execute on function public.biz_daily_src72(date, date, integer) from anon, public;

-- ---------- _p27_pl: same columns; costed revenue and COGS from the one source (bos72) ----------
create or replace function public._p27_pl(d1 date, d2 date, locs integer[])
 returns table(o_m date, o_loc integer, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
 language sql stable security definer set search_path to 'public'
as $function$
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
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.entry_date between d1 and d2 and e.location_id = any (locs)
      union all  -- bos50: quick expenses
      select date_trunc('month', q.exp_date)::date, q.location_id, q.amount from public.quick_expenses q
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)) u group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
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
$function$;

-- new: the split behind _p27_pl (same month x place rows): ledger COGS, fallback estimate, revenue costed by the fallback, revenue with unknown cost
create or replace function public._p27_src72(d1 date, d2 date, locs integer[])
 returns table(o_m date, o_loc integer, o_cogs_ledger numeric, o_cogs_fallback numeric, o_fallback_rev numeric, o_unknown_rev numeric)
 language sql stable security definer set search_path to 'public'
as $function$
  select date_trunc('month', h.d)::date, h.loc,
         round(sum((case h.src when 'sale' then 1 else -1 end) * h.led_cogs), 2), round(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_cogs), 2),
         round(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_rev), 2), round(sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev), 2)
  from public._cogs_lines72(d1, d2, locs) h group by 1, 2;
$function$;
revoke all on function public._p27_src72(date, date, integer[]) from public, anon, authenticated;

-- ---------- l1 (monthly P&L): the old keys + the split (bos72) ----------
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb language sql stable security definer set search_path to 'public'
as $function$
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
  left join public._p27_src72(d1, d2, locs) sx on sx.o_m = p.o_m and sx.o_loc = p.o_loc;
$function$;

-- ---------- l3 (shop P&L): the old keys + the split (bos72) ----------
create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb language sql stable security definer set search_path to 'public'
as $function$
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
  from a join public.locations l on l.id = a.o_loc left join sx on sx.o_loc = a.o_loc;
$function$;

-- ---------- l2 (margin per item / category) from the one source (bos72) ----------
create or replace function public._r3q_l2_margin(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb language sql stable security definer set search_path to 'public'
as $function$
  with cats as (select public.rpt_arr_text(flt -> 'categories') as c),
  p as (  -- bos72: one row per document x item from the one COGS source; returns count negative, with their discount share
    select (case h.src when 'sale' then 1 else -1 end) as sg, h.item_id as iid, h.rev, h.qty, h.led_cogs + h.fb_cogs as cg, h.fb_cogs, h.unk_rev,
           case when h.led_rev + h.fb_rev > 0 or h.led_cogs + h.fb_cogs > 0 then h.led_rev + h.fb_rev end as crev
    from public._cogs_lines72(d1, d2, locs) h),
  j as (
    select i.id as item_id, coalesce(i.code, '-') as icode, coalesce(i.name_bn, '(item not linked)') as nbn, coalesce(i.name_en, i.name_bn, '(item not linked)') as nen,
           coalesce(nullif(btrim(i.category), ''), '-') as cat, p.*
    from p left join public.items i on i.id = p.iid),
  jf as (select j.* from j, cats where cats.c is null or j.cat = any (cats.c)),
  ia as (
    select item_id, icode, nbn, nen, cat, sum(sg * rev) as rev, sum(sg * qty) as qty,
           sum(sg * crev) as crev, sum(sg * cg) filter (where crev is not null) as cg, sum(sg * fb_cogs) as fb, sum(sg * unk_rev) as unk
    from jf group by item_id, icode, nbn, nen, cat),
  ca as (select cat, sum(rev) as rev, sum(crev) as crev, sum(cg) as cg, sum(fb) as fb, sum(unk) as unk from ia group by cat)
  select jsonb_build_object('level', 'item', 'category', ia.cat, 'item_code', ia.icode, 'item_name', ia.nbn, 'item_name_en', ia.nen,
    'qty', round(ia.qty, 3), 'revenue', round(ia.rev, 2), 'cogs', round(ia.cg, 2),
    'cogs_fallback', round(coalesce(ia.fb, 0), 2), 'unknown_cost_rev', round(coalesce(ia.unk, 0), 2),   -- bos72
    'margin', case when ia.crev is not null then round(ia.crev - ia.cg, 2) end,
    'margin_pct', case when ia.crev > 0 then round(100 * (ia.crev - ia.cg) / ia.crev, 2) end,
    'uncosted_pct', case when ia.rev > 0 then round(100 * greatest(ia.rev - coalesce(ia.crev, 0), 0) / ia.rev, 2) end)
  from ia
  union all
  select jsonb_build_object('level', 'category', 'category', ca.cat, 'item_code', null, 'item_name', null, 'item_name_en', null,
    'qty', null, 'revenue', round(ca.rev, 2), 'cogs', round(ca.cg, 2),
    'cogs_fallback', round(coalesce(ca.fb, 0), 2), 'unknown_cost_rev', round(coalesce(ca.unk, 0), 2),   -- bos72
    'margin', case when ca.crev is not null then round(ca.crev - ca.cg, 2) end,
    'margin_pct', case when ca.crev > 0 then round(100 * (ca.crev - ca.cg) / ca.crev, 2) end,
    'uncosted_pct', case when ca.rev > 0 then round(100 * greatest(ca.rev - coalesce(ca.crev, 0), 0) / ca.rev, 2) end)
  from ca;
$function$;

-- ---------- B1 / B4: _acct_docs (latest = phase52) with the bos72 lines ----------
CREATE OR REPLACE FUNCTION public._acct_docs(p_start date)
 RETURNS TABLE(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- sales (payments split, discount, revenue, COGS only from real unit costs)
  return query
  select 'sale'::text, s.id::text, s.sale_date, s.location_id, ('Receipt ' || s.receipt)::text, null::text, s.status = 'done', (s.void_at at time zone 'Asia/Dhaka')::date,
    case when s.status = 'done' and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e
                 where nullif(e->>'item_id', '') is not null and not exists (select 1 from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and l.reason = 'sale_out'
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
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
                   and l.item_id = (e->>'item_id')::uuid and coalesce(l.unit_cost, 0) > 0)) then 'cogs_missing' end, /* bos72: cost 0 = unknown */
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
        union all select 2, jsonb_build_object('a', 'pay_cash', 'c', v.total)
      ) y) end
  from public.entries e cross join lateral (
    select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0) total,
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'wastage' and l.ref_id = w.id::text and l.reason = 'wastage') c
  where (w.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('wastage', w.id::text, true);

  -- production: ingredients (at their real cost) move from raw / packaging to finished goods
  return query
  select 'production'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, 'Production run'::text, null::text, r.status = 'done', (r.void_at at time zone 'Asia/Dhaka')::date,
    case when c.nulls > 0 and c.amt > 0 then 'cogs_missing' end,
    case when r.status = 'done' and (c.amt is null or c.amt <= 0) then 'cost_missing' end,
    case when r.status = 'done' and c.amt > 0 then (
      select jsonb_agg(j order by o) from (
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt) j
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
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
end $function$;

-- ---------- B1 / B6: acct_post_pending keeps failures ----------
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
  if not public._acct_manage() then raise exception 'not allowed'; end if;
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

-- ---------- B4: acct_income_statement / acct_overview carry unknown_cost_rev ----------
CREATE OR REPLACE FUNCTION public.acct_income_statement(p_from date, p_to date, p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); inc jsonb; exp_ jsonb; ti numeric; te numeric; cg numeric := 0; cid bigint; to_ date := coalesce(p_to, public._acct_today()); fr date; cm bigint; unk numeric := 0; unk_est numeric := 0;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.cr - b.dr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.cr - b.dr) filter (where not a.is_group), 0)
    into inc, ti from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'income' and (b.dr <> 0 or b.cr <> 0);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name_bn', a.name_bn, 'name_en', a.name_en, 'parent_id', a.parent_id, 'is_group', a.is_group, 'amount', (b.dr - b.cr)) order by a.code), '[]'::jsonb),
         coalesce(sum(b.dr - b.cr) filter (where not a.is_group), 0)
    into exp_, te from public._acct_bal(fr, to_, p_loc) b join public.coa_accounts a on a.id = b.account_id where a.type = 'expense' and (b.dr <> 0 or b.cr <> 0);
  select account_id into cid from public.acct_mappings where key = 'cogs';
  select coalesce(sum(b.dr - b.cr), 0) into cg from public._acct_bal(fr, to_, p_loc) b where b.account_id = cid;
  select count(*) into cm from public.journal_entries e where e.entry_date between fr and to_ and e.flags like '%cogs_missing%' and e.reverses_id is null
    and (public._acct_all() or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
  -- bos72: revenue (net of returns) for which the books have no cost: the gross profit is PROVISIONAL by this amount (cogs_estimate_missing = what item_costs would add)
  select round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * (h.unk_rev + h.fb_rev)), 0), 2), round(coalesce(sum((case h.src when 'sale' then 1 else -1 end) * h.fb_cogs), 0), 2) into unk, unk_est
    from public._cogs_lines72(fr, to_, (select coalesce(array_agg(l.id), '{}') from public.locations l where (p_loc is null or l.id = p_loc) and (public._acct_all() or public.can_loc(l.id)))) h;
  return jsonb_build_object('from', fr, 'to', to_, 'location_id', p_loc, 'income', inc, 'expense', exp_, 'total_income', ti, 'total_expense', te, 'cogs', cg,
    'gross_profit', ti - cg, 'net_profit', ti - te, 'cogs_missing', cm, 'unknown_cost_rev', unk, 'cogs_estimate_missing', unk_est, 'provisional', unk > 0 or cm > 0);   -- bos72
end $function$;
CREATE OR REPLACE FUNCTION public.acct_overview(p_loc integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare st date := public._acct_start(); t date := public._acct_today(); bs jsonb; isx jsonb; pend jsonb;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'on', public.rule_on('accounting_on')); end if;
  bs := public.acct_balance_sheet(t, p_loc);
  isx := public.acct_income_statement(greatest(date_trunc('month', t)::date, st), t, p_loc);
  return jsonb_build_object('start', st, 'on', public.rule_on('accounting_on'), 'balance_sheet', jsonb_build_object('total_assets', bs->'total_assets', 'total_liabilities', bs->'total_liabilities',
      'total_equity', bs->'total_equity_and_earnings', 'unbalanced', bs->'unbalanced', 'difference', bs->'difference', 'cogs_missing', bs->'cogs_missing'),
    'income_month', jsonb_build_object('total_income', isx->'total_income', 'total_expense', isx->'total_expense', 'net_profit', isx->'net_profit', 'cogs', isx->'cogs', 'gross_profit', isx->'gross_profit', 'from', isx->'from', 'unknown_cost_rev', isx->'unknown_cost_rev', 'provisional', isx->'provisional'),   -- bos72
    'status', public.acct_status());
end $function$;

-- ---------- B4: production_post (latest = phase23) with rule production_requires_cost and cost 0 = unknown ----------
CREATE OR REPLACE FUNCTION public.production_post(p_loc integer, p_recipe uuid, p_batches numeric, p_client uuid DEFAULT NULL::uuid, p_made_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; nocost text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid;
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
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost
  if coalesce(public.rule_txt('production_requires_cost'), 'warn') = 'refuse' then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by code loop
      if n.need >= 0.0001 and coalesce((select b.avg_cost from public.stock_balance b where b.item_id = n.item_id and b.location_id = p_loc), 0) <= 0 then
        nocost := nocost || case when nocost = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '');
      end if;
    end loop;
    if nocost <> '' then raise exception 'cost_missing' using detail = nocost, hint = 'production'; end if;
  end if;
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, yb, wm, left(p_note, 200), auth.uid());
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 then cost_ok := false; else tot := tot + n.need * av; end if;   -- bos72: cost 0 = unknown
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
end $function$;

-- ---------- B6: acct_status (same keys as before + last_post_at / pending / locked / waiting / errors) ----------
create or replace function public.acct_status()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
    'last_post_at', (select max(created_at) from public.journal_entries where created_by is not null and source_type not in ('manual', 'opening')),   -- bos72
    'pending', pend, 'locked', lck, 'waiting', wt, 'errors', er, 'error_list', erl);   -- bos72
end $function$;

-- ---------- B2: does the report COGS agree with the books? (read only) ----------
create or replace function public.profit_source_check(p_from date, p_to date, p_loc integer default null)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
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
      and (p_loc is null or d.location_id = p_loc);
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
end $function$;
grant execute on function public.profit_source_check(date, date, integer) to authenticated;
revoke execute on function public.profit_source_check(date, date, integer) from anon, public;

-- ---------- B5: inventory in the books vs the stock valuation (READ ONLY, posts nothing) ----------
-- diff = GL - valuation. Each reason is the part of the diff that comes from a stock movement / journal the OTHER side does not have, computed from the
-- stock ledger and the journal. What is left is "unexplained" (rounding of the average cost, production with an unknown ingredient cost that was not flagged, ...).
-- valuation: for today (or later) qty x average cost of the stock balance (same as stock_valuation); for an earlier date the ledger replay (basis = 'ledger_replay').
create or replace function public.inventory_vs_gl(p_date date default null, p_loc integer default null)
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); t date := public._acct_today(); k text; acct bigint; acode text; anbn text; anen text;
        gl numeric; v numeric; rw record; rs jsonb; ex numeric; df numeric; rows_ jsonb := '[]'::jsonb; tg numeric := 0; tv numeric := 0; tx numeric := 0; basis text;
        g_open numeric; g_man numeric; g_prod numeric; g_pret numeric; ok boolean;
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
      where jl.account_id = acct and e.entry_date <= d and e.source_type = 'opening' and (p_loc is null or jl.location_id = p_loc);
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
    df := round(gl - v, 2);
    rs := jsonb_build_array(
      jsonb_build_object('code', 'valuation_basis', 'amount', round(rw.lv_all - v, 2)),
      jsonb_build_object('code', 'count_adjust', 'amount', round(-rw.g_count, 2)),
      jsonb_build_object('code', 'opening', 'amount', round(g_open - rw.g_opening, 2)),
      jsonb_build_object('code', 'transfer', 'amount', round(-rw.g_transfer, 2)),
      jsonb_build_object('code', 'issue_out', 'amount', round(-rw.g_issue, 2)),
      jsonb_build_object('code', 'manual_in', 'amount', round(-rw.g_manual_in, 2)),
      jsonb_build_object('code', 'purchase_before_start', 'amount', round(-rw.g_prestart, 2)),
      jsonb_build_object('code', 'purchase_return_variance', 'amount', round(g_pret, 2)),
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
grant execute on function public.inventory_vs_gl(date, integer) to authenticated;
revoke execute on function public.inventory_vs_gl(date, integer) from anon, public;

-- ============================================================================
-- End of FRESH part 5 of 21.
