-- ===================== phase87.sql =====================
-- Phase 87 (bos87) - MONEY ACCOUNTS. Paste LAST (after phase86), paste-twice safe. Earlier phase files are not edited.
-- Owner decision (final): the money source of any payment is NOT fixed. Cash drawer, mobile wallet (any provider) or bank account, chosen per payment.
--
-- WHAT EXISTED (inventory, reused and not duplicated)
--   chart of accounts + double-entry journal (phase40), mapping keys, _acct_docs scanner, acct_post_pending (autopost), manual journal, reversal
--   opening_balance_post (phase80)           -> reused: gets one more section "money"; no second opening path
--   d_wallets / d_wallet_* (phase83)         -> left as it is (legacy register of bKash, Nagad, Rocket, Upay on accounts 1131-1134). Its switch d_wallet_split_on only
--                                               governs that legacy text based split of 1130. Money accounts of kind wallet NEVER depend on it (see below).
--   _d_cash_ok (10-3 / accounts permission)  -> reused for the real-balance check; the blind count rule (real figure typed first) is the same as d_wallet_checks
--   quick expense / cash_moves / payroll / partner tables -> reused: each only gets one nullable column money_account_id
--   Balance Check (phase84), day book (phase13/23/50), cash flow (phase40), daybook_vs_journal (phase49/52) -> patched in place (text patch of the live function), nothing duplicated
--   salary_pay_source (phase82, a FIXED source for salary) -> kept as the fallback for a payment that names no money account
-- WHAT THIS FILE ADDS
--   money_accounts (registry: cash drawer per place, wallet per provider and number, bank per bank/branch/account number), each on its own chart account
--   money_event_settings (per event type: default source, allow override, require source)
--   a payment source on 14 event types, carried IN BAND on the record (so an offline saved payment keeps it): the text "ma#<id>;" in front of the free text field
--     of the payment (wallet / ref / note column, see _m_tagcol), or the key money_account_id inside the 10-2 form data. A BEFORE INSERT trigger reads it, checks it,
--     sets money_account_id and the payment mode, removes the tag. The journal line then hits exactly that account (mapping key m_acct_<id>).
--   transfers between accounts (one balanced entry, optional fee), charges / interest, recurring transfers
--   per account statement, period summary, negative balance policy (warn | block | allow), real balance check, exceptions list, one-off owner exceptions
--   Balance Check item "money accounts total = mapped ledger accounts", day book shows the account, P&L / balance sheet per account
--   approver choice (any role, any named user, per entry) on top of phase80/86
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner adds a money account and sets a default or the picker sends one: no rows are seeded, every setting
-- defaults to "no default, override allowed, source not required". !! Re-pasting phase 13, 40, 49, 50, 52, 79, 80, 82, 84, 85 or 86 removes the patches: paste this file again.

do $g$ begin
  if to_regprocedure('public._p86_present()') is null then raise exception 'phase87 needs phase86 (and 80-85) first'; end if;
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._c_docs(date)') is null or to_regprocedure('public.opening_balance_post(jsonb,uuid,boolean,boolean)') is null
     or to_regprocedure('public._e_balance_check(date,integer,integer)') is null or to_regprocedure('public._daybook_lines(integer[],integer[],date,date)') is null then
    raise exception 'phase87 needs the shared functions of phases 40, 80, 82, 84, 85';
  end if;
end $g$;

create or replace function public._p87_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (reads the CURRENT definition, so it sits on top of whatever is installed) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise the paste stops, nothing is half changed). Already patched (marker bos87) = no-op.
create or replace function public._m_patch(p_fn regprocedure, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if position('bos87' in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase87 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position('bos87' in def) = 0 then raise exception 'phase87 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- tables ----------
create sequence if not exists public.money_account_code_seq;
create table if not exists public.money_accounts (
  id bigserial primary key,
  code text not null unique,
  kind text not null check (kind in ('cash', 'wallet', 'bank')),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text not null check (length(btrim(name_en)) between 1 and 120),
  provider text check (provider is null or length(provider) <= 80),          -- wallet company or bank name
  branch text check (branch is null or length(branch) <= 80),
  account_no text check (account_no is null or length(account_no) <= 40),    -- wallet number or bank account number
  location_id int references public.locations(id),                          -- cash drawer: the place
  coa_account_id bigint not null unique references public.coa_accounts(id),
  neg_policy text not null default 'warn' check (neg_policy in ('warn', 'block', 'allow')),
  active boolean not null default true,
  sort int not null default 100,
  opening_amount numeric not null default 0 check (opening_amount >= 0 and opening_amount <= 1000000000000),
  opening_date date,
  opening_posted boolean not null default false,
  note text check (note is null or length(note) <= 300),
  deactivated_by uuid, deactivated_at timestamptz, deactivate_reason text,
  created_at timestamptz not null default now(), created_by uuid
);
create unique index if not exists money_accounts_ident on public.money_accounts (kind, lower(coalesce(provider, '')), lower(coalesce(account_no, '')), coalesce(location_id, 0), (case when kind = 'cash' then lower(name_en) else '' end)) where active;

create table if not exists public.money_event_settings (
  event_type text primary key,
  label_en text not null, dir text not null check (dir in ('out', 'in', 'both')),
  default_account_id bigint references public.money_accounts(id),
  allow_override boolean not null default true,
  require_source boolean not null default false,
  sort int not null default 100,
  updated_by uuid, updated_at timestamptz not null default now()
);
insert into public.money_event_settings (event_type, label_en, dir, sort) values
  ('salary_payment', 'Salary payment', 'out', 10), ('salary_advance', 'Salary advance (recovery rides on the salary payment)', 'out', 20),
  ('expense_10_2', 'Expense voucher 10-2', 'out', 30), ('quick_expense', 'Quick expense', 'out', 40),
  ('supplier_payment', 'Supplier payment', 'out', 50), ('purchase_payment', 'Purchase payment (paid with the bill)', 'out', 60),
  ('owner_topup', 'Owner top-up', 'in', 70), ('owner_draw', 'Owner draw', 'out', 80),
  ('partner_capital', 'Partner capital / loan (in and out)', 'both', 90), ('partner_payout', 'Partner profit payout', 'out', 100),
  ('customer_refund', 'Customer refund', 'out', 110), ('supplier_refund', 'Supplier refund received', 'in', 120),
  ('customer_advance', 'Customer advance (taken and refunded)', 'both', 130), ('cash_handover', 'Cash handover received (hub)', 'in', 140)
on conflict (event_type) do nothing;

alter table public.supplier_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.supplier_refunds add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.sale_returns add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.quick_expenses add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.cash_moves add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.payroll_payments add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.employee_advances add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.partner_capital add column if not exists money_account_id bigint references public.money_accounts(id);
alter table public.partner_settlement_payments add column if not exists money_account_id bigint references public.money_accounts(id);

create table if not exists public.money_transfers (
  id bigserial primary key,
  client_id uuid unique,
  from_account bigint not null references public.money_accounts(id),
  to_account bigint not null references public.money_accounts(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  fee numeric not null default 0 check (fee >= 0 and fee <= 1000000000),
  fee_side text not null default 'from' check (fee_side in ('from', 'to')),
  xfer_date date not null,
  location_id int references public.locations(id),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  status text not null default 'done' check (status in ('done', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  recurring_id bigint,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (from_account <> to_account)
);
create index if not exists money_transfers_d on public.money_transfers (xfer_date);

create table if not exists public.money_charges (
  id bigserial primary key,
  client_id uuid unique,
  account_id bigint not null references public.money_accounts(id),
  kind text not null check (kind in ('charge', 'interest')),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  charge_date date not null,
  location_id int references public.locations(id),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  status text not null default 'done' check (status in ('done', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);

create table if not exists public.money_recurring (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 1 and 80),
  from_account bigint not null references public.money_accounts(id),
  to_account bigint not null references public.money_accounts(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  fee numeric not null default 0 check (fee >= 0),
  fee_side text not null default 'from' check (fee_side in ('from', 'to')),
  day_of_month int not null check (day_of_month between 1 and 28),
  location_id int references public.locations(id),
  start_date date not null, end_date date,
  active boolean not null default true,
  last_run date,
  created_by uuid, created_at timestamptz not null default now(),
  check (from_account <> to_account)
);

alter table public.money_recurring add column if not exists location_id int references public.locations(id);

create table if not exists public.money_checks (               -- the real balance, typed FIRST (blind); same idea as d_wallet_checks (phase83) for every money account
  id bigserial primary key,
  account_id bigint not null references public.money_accounts(id),
  check_date date not null,
  real_balance numeric not null check (real_balance >= 0 and real_balance <= 1000000000000),
  book_balance numeric not null,
  diff numeric not null,                                       -- real - book, always written, even 0
  status text not null check (status in ('matched', 'difference', 'explained')),
  reason text check (reason is null or length(reason) <= 300), reason_by uuid, reason_at timestamptz,
  client_id uuid unique,
  counted_by uuid, counted_staff text, counted_at timestamptz not null default now()
);

create table if not exists public.money_exception_grants (     -- an owner allows ONE exception for ONE payment (reason required)
  id bigserial primary key,
  rule text not null check (rule in ('negative', 'require_source', 'override', 'period_lock', 'approver')),
  event_type text, for_user uuid, client_id uuid, account_id bigint references public.money_accounts(id),
  max_amount numeric, on_date date,
  reason text not null check (length(btrim(reason)) >= 3),
  granted_by uuid not null, granted_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 day'),
  used_at timestamptz, used_ref text, revoked boolean not null default false
);

create table if not exists public.money_exceptions (           -- the Exceptions list (append only, resolved by a note)
  id bigserial primary key,
  at timestamptz not null default now(),
  kind text not null check (kind in ('negative_warn', 'negative_block_exception', 'source_required_exception', 'override_exception', 'period_lock_exception', 'approver_exception', 'recon_diff')),
  event_type text, account_id bigint references public.money_accounts(id), amount numeric,
  src_table text, src_id text, reason text, by_user uuid,
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_by uuid, resolved_at timestamptz, resolve_note text
);

do $t$ declare t text; begin
  foreach t in array array['money_accounts', 'money_event_settings', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exception_grants', 'money_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['money_accounts', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exception_grants', 'money_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  drop trigger if exists audit_money_event_settings on public.money_event_settings;
  create trigger audit_money_event_settings after insert or update on public.money_event_settings for each row execute function public.log_change('event_type');
end $t$;

-- ---------- permission helpers ----------
create or replace function public._m_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
create or replace function public._m_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;

do $p$ declare t text; begin
  foreach t in array array['money_accounts', 'money_transfers', 'money_charges', 'money_recurring', 'money_checks', 'money_exceptions', 'money_event_settings'] loop
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._m_view())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  drop policy if exists money_exception_grants_read on public.money_exception_grants;
  create policy money_exception_grants_read on public.money_exception_grants for select to authenticated using (public.is_owner());
  grant select on public.money_exception_grants to authenticated;
end $p$;
grant execute on function public._m_mgr(), public._m_view() to authenticated;

-- ---------- small helpers ----------
create or replace function public._m_id(t text) returns bigint language sql immutable as $$ select case when t ~ '^[0-9]{1,12}$' then t::bigint end $$;
create or replace function public._m_key(p_id bigint, p_default text) returns text language sql immutable as $$ select case when p_id is null then p_default else 'm_acct_' || p_id::text end $$;
create or replace function public._m_mode_of_kind(p_kind text) returns text language sql immutable as $$ select case p_kind when 'cash' then 'cash' when 'wallet' then 'mobile' else 'bank' end $$;
create or replace function public._m_mode(t text) returns text language sql stable security definer set search_path = public as $$
  select public._m_mode_of_kind(a.kind) from public.money_accounts a where a.id = public._m_id(t) $$;
create or replace function public._m_name(p_id bigint) returns text language sql stable security definer set search_path = public as $$
  select a.name_en from public.money_accounts a where a.id = p_id $$;
create or replace function public._m_untag(p_text text, out acc bigint, out rest text) language sql immutable as $$
  select case when p_text ~ '^ma#[0-9]{1,12};' then substring(p_text from '^ma#([0-9]{1,12});')::bigint end,
         case when p_text ~ '^ma#[0-9]{1,12};' then nullif(regexp_replace(p_text, '^ma#[0-9]{1,12};', ''), '') else p_text end $$;
create or replace function public._m_linked_types() returns text[] language sql immutable as $$
  select array['supplier_payment', 'supplier_refund', 'sale_return', 'quick_expense', 'cash_move', 'payroll_payment', 'payroll_pay_accr', 'staff_advance', 'partner_capital',
               'partner_settle_pay', 'expense_voucher', 'money_transfer', 'money_charge'] $$;
-- sum of a 10-2 voucher exactly as the scanner reads it
create or replace function public._m_voucher_total(p_data jsonb) returns numeric language sql immutable set search_path = public as $$
  select coalesce(sum(public._acct_num(x->>'amount')) filter (where public._acct_num(x->>'amount') > 0), 0)
    from jsonb_array_elements(case when jsonb_typeof(p_data->'lines') = 'array' then p_data->'lines' else '[]'::jsonb end) x $$;

create or replace function public._m_journal_bal(p_acc bigint, p_asof date default null) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.money_accounts a on a.coa_account_id = l.account_id where a.id = p_acc and (p_asof is null or e.entry_date <= p_asof) $$;
create or replace function public._m_is_generic(p_acc bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.money_accounts a join public.acct_mappings m on m.account_id = a.coa_account_id and m.key in ('pay_cash', 'pay_bank', 'pay_mobile') where a.id = p_acc) $$;
create or replace function public._m_accounting_ready() returns boolean language sql stable security definer set search_path = public as $$
  select public.rule_on('accounting_on') and public._acct_start() is not null $$;

-- ---------- coa: bank charges and interest accounts (mapping keys used by charges and transfer fees) ----------
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'm_bank_charge', a.id, 'ব্যাংক চার্জ', 'Bank charges' from public.coa_accounts a where a.code = '5810' on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'm_interest_income', a.id, 'সুদ / অন্যান্য আয়', 'Interest income' from public.coa_accounts a where a.code = '4900' on conflict (key) do nothing;

-- ============================================================================
-- PART B: the register of payments per account (_m_src), balance, exceptions, the payment source trigger
-- ============================================================================
-- every payment that names a money account, signed (+ into the account), with the journal source it will be posted under
create or replace function public._m_src(p_acc bigint default null)
returns table(tbl text, pk text, ev text, acc bigint, d date, loc int, amt numeric, jtype text, jid text, live boolean, memo text)
language sql stable security definer set search_path = public as $$
  select z.* from (
    select 'supplier_payments'::text as tbl, p.id::text as pk, (case when p.bill_id is not null then 'purchase_payment' else 'supplier_payment' end)::text as ev, p.money_account_id as acc,
           (p.paid_at at time zone 'Asia/Dhaka')::date as d, p.location_id as loc, -p.amount as amt, 'supplier_payment'::text as jtype, p.id::text as jid, not p.voided as live, 'Supplier payment'::text as memo
      from public.supplier_payments p where p.money_account_id is not null
    union all
    select 'supplier_refunds', f.id::text, 'supplier_refund', f.money_account_id, (f.refunded_at at time zone 'Asia/Dhaka')::date, f.location_id, f.amount, 'supplier_refund', f.id::text, not f.voided, 'Supplier refund'
      from public.supplier_refunds f where f.money_account_id is not null
    union all
    select 'sale_returns', r.id::text, 'customer_refund', r.money_account_id, (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, -r.refund_amount, 'sale_return', r.id::text, r.status = 'done', 'Customer refund'
      from public.sale_returns r where r.money_account_id is not null and r.refund_amount > 0
    union all
    select 'quick_expenses', q.id::text, 'quick_expense', q.money_account_id, q.exp_date, q.location_id, -q.amount, 'quick_expense', q.id::text, q.status = 'done', 'Quick expense: ' || q.head
      from public.quick_expenses q where q.money_account_id is not null
    union all
    select 'cash_moves', m.id::text,
           case m.kind when 'owner_topup' then 'owner_topup' when 'owner_draw' then 'owner_draw' when 'hub_receipt' then 'cash_handover' else 'customer_advance' end,
           m.money_account_id, m.move_date, m.location_id,
           case m.kind when 'owner_draw' then -m.amount when 'cust_advance_refund' then -m.amount else m.amount end,
           'cash_move', public._acct_sid52('cash_move', m.id::text), m.status = 'done' and not public._shadowed52('cash_moves', m.id::text), 'Cash move: ' || m.kind
      from public.cash_moves m where m.money_account_id is not null and m.kind in ('owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'hub_receipt')
    union all
    select 'payroll_payments', p.id::text, 'salary_payment', p.money_account_id, p.pay_date, p.location_id, -p.amount,
           case when public._c_run_basis(p.run_id) = 'accrual' then 'payroll_pay_accr' else 'payroll_payment' end,
           case when public._c_run_basis(p.run_id) = 'accrual' then p.id::text else public._acct_sid52('payroll_payment', p.id::text) end,
           p.status = 'done' and not public.is_shadow('payroll_runs', p.run_id::text), 'Salary payment PR-' || p.run_id::text
      from public.payroll_payments p where p.money_account_id is not null
    union all
    select 'employee_advances', a.id::text, 'salary_advance', a.money_account_id, a.adv_date, a.location_id, -a.amount, 'staff_advance', a.id::text,
           a.status = 'active' and a.mode in ('cash', 'bank', 'mobile'), 'Staff advance ADV-' || a.id::text
      from public.employee_advances a where a.money_account_id is not null
    union all
    select 'partner_capital', c.id::text, 'partner_capital', c.money_account_id, c.cap_date, null::int,
           case when c.kind in ('contribution', 'loan_in') then c.amount else -c.amount end, 'partner_capital', public._acct_sid52('partner_capital', c.id::text),
           c.status = 'posted' and c.mode <> 'in_kind' and not public._shadowed52('partner_capital', c.id::text), 'Partner capital: ' || c.kind
      from public.partner_capital c where c.money_account_id is not null
    union all
    select 'partner_settlement_payments', pp.id::text, 'partner_payout', pp.money_account_id, pp.paid_on, null::int, -pp.amount, 'partner_settle_pay', pp.id::text,
           coalesce((select s.status <> 'void' from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id where l.id = pp.line_id), false), 'Partner payout'
      from public.partner_settlement_payments pp where pp.money_account_id is not null
    union all
    select 'entries', e.id::text, 'expense_10_2', public._m_id(e.data ->> 'money_account_id'), e.entry_date, e.location_id, -public._m_voucher_total(e.data), 'expense_voucher',
           e.id::text || ':' || coalesce(e.rev_no, 0)::text, e.status = 'approved' and not public.is_shadow('entries', e.id::text), 'Expense voucher ' || e.serial::text
      from public.entries e where e.form_code = '10-2' and public._m_id(e.data ->> 'money_account_id') is not null
    union all
    select 'money_transfers', t.id::text, 'money_transfer', t.from_account, t.xfer_date, t.location_id, -(t.amount + case when t.fee_side = 'from' then t.fee else 0 end), 'money_transfer', t.id::text,
           t.status = 'done', 'Transfer out'
      from public.money_transfers t
    union all
    select 'money_transfers', t.id::text, 'money_transfer', t.to_account, t.xfer_date, t.location_id, t.amount - case when t.fee_side = 'to' then t.fee else 0 end, 'money_transfer', t.id::text,
           t.status = 'done', 'Transfer in'
      from public.money_transfers t
    union all
    select 'money_charges', c.id::text, 'money_charge', c.account_id, c.charge_date, c.location_id, case c.kind when 'interest' then c.amount else -c.amount end, 'money_charge', c.id::text,
           c.status = 'done', case c.kind when 'interest' then 'Interest' else 'Bank / wallet charge' end
      from public.money_charges c
  ) z
  where (p_acc is null or z.acc = p_acc) and (public._acct_start() is null or z.d >= public._acct_start()) $$;

-- book balance right now: the journal part that does not come from payments, plus every live payment on the account (posted or not yet)
create or replace function public._m_reg(p_acc bigint) returns numeric language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; j numeric;
begin
  select * into a from public.money_accounts where id = p_acc;
  if not found then return null; end if;
  if public._m_is_generic(p_acc) then return public._m_journal_bal(p_acc); end if;
  select coalesce(sum(l.debit - l.credit), 0) into j from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.source_type <> all (public._m_linked_types());
  return j + coalesce((select sum(s.amt) from public._m_src(p_acc) s where s.live), 0);
end $$;

-- the proof for one account: ledger = (non payment lines) + (posted live payments) + (voided payments whose reversal is still to come). Differences that are only "not posted yet" are timing.
create or replace function public._m_prove(p_acc bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; jt numeric; jn numeric; lp numeric := 0; stl numeric := 0; pend numeric := 0; pn int := 0; r record;
begin
  select * into a from public.money_accounts where id = p_acc;
  if not found then return null; end if;
  jt := public._m_journal_bal(p_acc);
  if public._m_is_generic(p_acc) then return jsonb_build_object('account_id', p_acc, 'journal', jt, 'register', jt, 'diff', 0, 'pending', 0, 'pending_n', 0, 'stale', 0, 'generic', true); end if;
  select coalesce(sum(l.debit - l.credit), 0) into jn from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.source_type <> all (public._m_linked_types());
  for r in select s.*, exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null) as posted,
                  exists (select 1 from public.journal_entries e join public.journal_entries x on x.reverses_id = e.id where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null) as reversed
             from public._m_src(p_acc) s loop
    if r.live and r.posted then lp := lp + r.amt;
    elsif r.live and not r.posted then pend := pend + r.amt; pn := pn + 1;
    elsif not r.live and r.posted and not r.reversed then stl := stl + r.amt; end if;
  end loop;
  return jsonb_build_object('account_id', p_acc, 'journal', jt, 'register', jn + lp + pend, 'diff', round(jt - (jn + lp + stl), 2), 'pending', pend, 'pending_n', pn, 'stale', stl, 'generic', false);
end $$;

-- ---------- exceptions: one-off, owner granted, reason required ----------
create or replace function public._m_grant_take(p_rule text, p_ev text, p_client uuid, p_acc bigint, p_amt numeric, p_date date, p_ref text) returns boolean
language plpgsql security definer set search_path = public as $$
declare g public.money_exception_grants; k text;
begin
  select * into g from public.money_exception_grants x
   where x.rule = p_rule and not x.revoked and x.used_at is null and x.expires_at > now()
     and (x.event_type is null or x.event_type = p_ev) and (x.account_id is null or x.account_id = p_acc) and (x.max_amount is null or p_amt is null or p_amt <= x.max_amount)
     and (x.on_date is null or x.on_date = p_date)
     and ((x.client_id is not null and x.client_id = p_client) or (x.client_id is null and x.for_user = auth.uid()))
   order by (x.client_id is not null) desc, x.id limit 1 for update skip locked;
  if not found then return false; end if;
  update public.money_exception_grants set used_at = now(), used_ref = left(coalesce(p_ref, ''), 80) where id = g.id;
  k := case p_rule when 'negative' then 'negative_block_exception' when 'require_source' then 'source_required_exception' when 'override' then 'override_exception'
         when 'period_lock' then 'period_lock_exception' else 'approver_exception' end;
  insert into public.money_exceptions (kind, event_type, account_id, amount, src_table, src_id, reason, by_user)
    values (k, p_ev, p_acc, p_amt, null, p_ref, g.reason || ' (granted by ' || coalesce((select staff_id from public.profiles where id = g.granted_by), '-') || ')', auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_used', 'money_exception_grants', g.id::text,
      jsonb_build_object('rule', p_rule, 'event', p_ev, 'account', p_acc, 'amount', p_amt, 'ref', p_ref, 'reason', g.reason, 'granted_by', g.granted_by));
  return true;
end $$;

create or replace function public._m_neg_check(p_acc bigint, p_amt numeric, p_ev text, p_client uuid, p_date date, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; bal numeric;
begin
  select * into a from public.money_accounts where id = p_acc for update;         -- one outgoing payment at a time per account
  if not found or a.neg_policy = 'allow' or not public._m_accounting_ready() then return; end if;
  bal := public._m_reg(p_acc);
  if bal - p_amt >= 0 then return; end if;
  if a.neg_policy = 'block' then
    if public._m_grant_take('negative', p_ev, p_client, p_acc, p_amt, p_date, p_ref) then return; end if;
    raise exception 'money_negative' using detail = 'account ' || a.code || ' balance ' || bal::text || ' payment ' || p_amt::text;
  end if;
  insert into public.money_exceptions (kind, event_type, account_id, amount, src_id, reason, by_user)
    values ('negative_warn', p_ev, p_acc, p_amt, p_ref, 'balance ' || bal::text || ' before, ' || (bal - p_amt)::text || ' after', auth.uid());
end $$;

-- ---------- row readers for the source trigger ----------
create or replace function public._m_event(p_tbl text, r jsonb) returns text language sql immutable as $$
  select case p_tbl
    when 'supplier_payments' then case when r ->> 'bill_id' is not null then 'purchase_payment' else 'supplier_payment' end
    when 'supplier_refunds' then 'supplier_refund'
    when 'sale_returns' then case when coalesce((r ->> 'refund_amount')::numeric, 0) > 0 and r ->> 'refund_mode' is not null then 'customer_refund' end
    when 'quick_expenses' then 'quick_expense'
    when 'cash_moves' then case r ->> 'kind' when 'owner_topup' then 'owner_topup' when 'owner_draw' then 'owner_draw' when 'cust_advance' then 'customer_advance'
                                  when 'cust_advance_refund' then 'customer_advance' when 'hub_receipt' then 'cash_handover' end
    when 'payroll_payments' then 'salary_payment'
    when 'employee_advances' then case when r ->> 'mode' in ('cash', 'bank', 'mobile') then 'salary_advance' end
    when 'partner_capital' then case when r ->> 'mode' <> 'in_kind' then 'partner_capital' end
    when 'partner_settlement_payments' then 'partner_payout'
    when 'entries' then case when r ->> 'form_code' = '10-2' then 'expense_10_2' end end $$;
create or replace function public._m_dir(p_tbl text, r jsonb) returns text language sql immutable as $$
  select case p_tbl when 'supplier_refunds' then 'in'
    when 'cash_moves' then case when r ->> 'kind' in ('owner_topup', 'cust_advance', 'hub_receipt') then 'in' else 'out' end
    when 'partner_capital' then case when r ->> 'kind' in ('contribution', 'loan_in') then 'in' else 'out' end
    else 'out' end $$;
create or replace function public._m_amount(p_tbl text, r jsonb) returns numeric language sql immutable as $$
  select coalesce(case when p_tbl = 'sale_returns' then (r ->> 'refund_amount')::numeric end, (r ->> 'amount')::numeric, 0) $$;
create or replace function public._m_date(p_tbl text, r jsonb) returns date language sql immutable as $$
  select coalesce((case p_tbl when 'supplier_payments' then r ->> 'paid_at' when 'supplier_refunds' then r ->> 'refunded_at' when 'sale_returns' then r ->> 'created_at' end)::timestamptz at time zone 'Asia/Dhaka',
                  now() at time zone 'Asia/Dhaka')::date $$;

-- ---------- the BEFORE INSERT trigger: resolve the source, check it, set mode, strip the tag ----------
create or replace function public._m_src_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb := to_jsonb(new); tagcol text := tg_argv[0]; ev text; st public.money_event_settings; ac bigint; rest text; a public.money_accounts; usr boolean := auth.uid() is not null;
  dflt boolean := false; rowmode text; cl uuid; loc int; amt numeric; md text; dt date;
begin
  select u.acc, u.rest into ac, rest from public._m_untag(r ->> tagcol) u;
  if ac is not null then new := jsonb_populate_record(new, jsonb_build_object(tagcol, rest)); r := to_jsonb(new); end if;
  ev := public._m_event(tg_table_name, r);
  if ev is null then return new; end if;
  select * into st from public.money_event_settings where event_type = ev;
  rowmode := coalesce(r ->> 'mode', r ->> 'refund_mode');
  cl := coalesce(nullif(r ->> 'client_id', '')::uuid, nullif(r ->> 'client_batch', '')::uuid);
  loc := nullif(r ->> 'location_id', '')::int;
  amt := public._m_amount(tg_table_name, r); dt := public._m_date(tg_table_name, r);
  if ac is null and st.default_account_id is not null then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (rowmode is null or rowmode = public._m_mode_of_kind(a.kind) or (a.kind = 'bank' and rowmode = 'card')) and (a.location_id is null or loc is null or a.location_id = loc) then
      ac := a.id; dflt := true;
    end if;
  end if;
  if ac is null then
    if st.require_source and usr and not public._m_grant_take('require_source', ev, cl, null, amt, dt, tg_table_name) then raise exception 'money_source_required'; end if;
    return new;                                                      -- no source: today's behaviour (generic cash / bank / mobile account by mode)
  end if;
  select * into a from public.money_accounts where id = ac;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if usr and not dflt and st.default_account_id is not null and ac <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', ev, cl, ac, amt, dt, tg_table_name) then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and loc is not null and a.location_id <> loc and not public._m_grant_take('override', ev, cl, ac, amt, dt, tg_table_name) then raise exception 'money_account_place'; end if;
  if ev = 'cash_handover' and a.kind <> 'cash' then raise exception 'money_account_kind'; end if;
  md := public._m_mode_of_kind(a.kind);
  new := jsonb_populate_record(new, jsonb_build_object('mode', md, 'refund_mode', case when a.kind = 'bank' then 'card' else md end, 'money_account_id', ac, 'wallet', null));
  if usr and public._m_dir(tg_table_name, r) = 'out' and amt > 0 then perform public._m_neg_check(ac, amt, ev, cl, dt, tg_table_name); end if;
  return new;
end $$;

create or replace function public._m_src_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id then raise exception 'money_account_fixed'; end if;
  return new;
end $$;

-- 10-2 expense voucher: the source is the key money_account_id inside the form data
create or replace function public._m_entries_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare st public.money_event_settings; ac bigint; raw text; a public.money_accounts; usr boolean := auth.uid() is not null; dflt boolean := false; amt numeric; moving boolean;
begin
  if new.form_code <> '10-2' or coalesce(new.data ->> 'from_quick', '') = 'true' or coalesce(current_setting('bos.shadow_create', true), '') = '1' then return new; end if;   -- a shadow made from quick expenses is not a payment
  raw := nullif(btrim(new.data ->> 'money_account_id'), '');
  ac := public._m_id(raw);
  if raw is not null and ac is null then raise exception 'unknown_money_account'; end if;
  select * into st from public.money_event_settings where event_type = 'expense_10_2';
  moving := new.status in ('submitted', 'approved') and (tg_op = 'INSERT' or old.status is distinct from new.status);
  if ac is null and st.default_account_id is not null and new.status in ('draft', 'submitted') then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (a.location_id is null or a.location_id = new.location_id) then
      ac := a.id; dflt := true; new.data := new.data || jsonb_build_object('money_account_id', ac);
    end if;
  end if;
  if ac is null then
    if moving and st.require_source and usr and not public._m_grant_take('require_source', 'expense_10_2', new.client_id, null, null, new.entry_date, 'entries') then raise exception 'money_source_required'; end if;
    return new;
  end if;
  if tg_op = 'UPDATE' and old.data ->> 'money_account_id' is not distinct from new.data ->> 'money_account_id' and not moving then return new; end if;
  select * into a from public.money_accounts where id = ac;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active and (tg_op = 'INSERT' or old.data ->> 'money_account_id' is distinct from new.data ->> 'money_account_id') then raise exception 'money_account_inactive'; end if;
  amt := public._m_voucher_total(new.data);
  if usr and not dflt and st.default_account_id is not null and ac <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', 'expense_10_2', new.client_id, ac, amt, new.entry_date, 'entries') then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and a.location_id <> new.location_id and not public._m_grant_take('override', 'expense_10_2', new.client_id, ac, amt, new.entry_date, 'entries') then raise exception 'money_account_place'; end if;
  if usr and moving and new.status = 'submitted' and amt > 0 then perform public._m_neg_check(ac, amt, 'expense_10_2', new.client_id, new.entry_date, 'entries'); end if;
  return new;
end $$;

do $trg$ declare r record; begin
  for r in select * from (values ('supplier_payments', 'wallet'), ('supplier_refunds', 'wallet'), ('sale_returns', 'wallet'), ('quick_expenses', 'note'), ('cash_moves', 'ref'),
                                 ('payroll_payments', 'ref'), ('employee_advances', 'note'), ('partner_capital', 'ref'), ('partner_settlement_payments', 'ref')) v(t, c) loop
    execute format('drop trigger if exists aa87_money_src_bi on public.%I', r.t);
    execute format('create trigger aa87_money_src_bi before insert on public.%I for each row execute function public._m_src_bi(%L)', r.t, r.c);
    if r.t not in ('partner_settlement_payments') then
      execute format('drop trigger if exists aa87_money_src_bu on public.%I', r.t);
      execute format('create trigger aa87_money_src_bu before update on public.%I for each row execute function public._m_src_bu()', r.t);
    end if;
  end loop;
end $trg$;
drop trigger if exists aa87_money_entries_bi on public.entries;
create trigger aa87_money_entries_bi before insert or update on public.entries for each row when (new.form_code = '10-2') execute function public._m_entries_bi();

-- ============================================================================
-- PART C: registry API (add / rename / deactivate / settings / pick list / exceptions)
-- ============================================================================
create or replace function public.money_account_add(p_kind text, p_name_en text, p_name_bn text default null, p_provider text default null, p_branch text default null,
  p_account_no text default null, p_location int default null, p_coa_code text default null, p_opening numeric default 0, p_opening_date date default null,
  p_neg text default 'warn', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint; v_coa public.coa_accounts; v_code text; v_par bigint; n bigint; prefix text; nm text := btrim(coalesce(p_name_en, '')); pv text := nullif(btrim(coalesce(p_provider, '')), '');
  an text := nullif(btrim(coalesce(p_account_no, '')), ''); gen text;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('cash', 'wallet', 'bank') then raise exception 'bad_kind'; end if;
  if length(nm) < 1 then raise exception 'name_required'; end if;
  if coalesce(p_neg, 'warn') not in ('warn', 'block', 'allow') then raise exception 'bad_policy'; end if;
  if p_kind in ('wallet', 'bank') and (pv is null or an is null) then raise exception 'provider_and_number_required'; end if;
  if p_kind = 'cash' and p_location is null and p_coa_code is null then raise exception 'place_required'; end if;
  if p_location is not null and (not exists (select 1 from public.locations where id = p_location) or not public.can_loc(p_location)) then raise exception 'bad_location'; end if;
  if p_kind <> 'cash' and p_location is not null then raise exception 'place_only_for_cash'; end if;
  if coalesce(p_opening, 0) < 0 or coalesce(p_opening, 0) > 1000000000000 then raise exception 'bad_amount'; end if;
  if coalesce(p_opening, 0) > 0 and exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                                              and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id)) then raise exception 'opening_exists_use_topup'; end if;
  if exists (select 1 from public.money_accounts a where a.active and a.kind = p_kind and lower(coalesce(a.provider, '')) = lower(coalesce(pv, '')) and lower(coalesce(a.account_no, '')) = lower(coalesce(an, ''))
                and coalesce(a.location_id, 0) = coalesce(p_location, 0) and (p_kind <> 'cash' or lower(a.name_en) = lower(nm))) then raise exception 'account_exists'; end if;
  v_id := nextval(pg_get_serial_sequence('public.money_accounts', 'id'));
  if p_coa_code is not null then
    select * into v_coa from public.coa_accounts where code = btrim(p_coa_code);
    if not found then raise exception 'unknown_account'; end if;
    if v_coa.type <> 'asset' or v_coa.is_group or not v_coa.active then raise exception 'coa_not_usable'; end if;
    if exists (select 1 from public.money_accounts where coa_account_id = v_coa.id) then raise exception 'coa_already_mapped'; end if;
    if exists (select 1 from public.d_wallets where coa_account_id = v_coa.id) then raise exception 'coa_is_legacy_wallet'; end if;
    select string_agg(m.key, ',') into gen from public.acct_mappings m where m.account_id = v_coa.id and m.key like 'pay\_%';
    if gen is not null and not ((gen = 'pay_cash' and p_kind = 'cash') or (gen = 'pay_bank' and p_kind = 'bank') or (gen = 'pay_mobile' and p_kind = 'wallet')) then raise exception 'coa_kind_mismatch'; end if;
  else
    prefix := case p_kind when 'cash' then '1110' when 'bank' then '1120' else '1130' end;
    loop
      n := nextval('public.money_account_code_seq'); v_code := prefix || '-' || lpad(n::text, 3, '0');
      exit when not exists (select 1 from public.coa_accounts where code = v_code);
    end loop;
    select id into v_par from public.coa_accounts where code = '1100';
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, sort, created_by)
      values (v_code, left(coalesce(nullif(btrim(p_name_bn), ''), nm), 120), left(nm, 120), 'asset', 'debit', v_par, false, false, 16, auth.uid()) returning * into v_coa;
  end if;
  insert into public.money_accounts (id, code, kind, name_bn, name_en, provider, branch, account_no, location_id, coa_account_id, neg_policy, opening_amount, opening_date, note, created_by)
    values (v_id, 'MA-' || lpad(v_id::text, 4, '0'), p_kind, left(coalesce(nullif(btrim(p_name_bn), ''), nm), 120), left(nm, 120), left(pv, 80), left(nullif(btrim(coalesce(p_branch, '')), ''), 80), left(an, 40),
      p_location, v_coa.id, coalesce(p_neg, 'warn'), round(coalesce(p_opening, 0), 2), coalesce(p_opening_date, public._acct_start()), left(p_note, 300), auth.uid());
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('m_acct_' || v_id::text, v_coa.id, left(nm, 100), 'Money account ' || left(nm, 90), auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_account_add', 'money_accounts', v_id::text,
      jsonb_build_object('kind', p_kind, 'name', nm, 'coa', v_coa.code, 'existing_coa', p_coa_code is not null, 'opening', round(coalesce(p_opening, 0), 2)));
  return jsonb_build_object('id', v_id, 'code', 'MA-' || lpad(v_id::text, 4, '0'), 'coa_code', v_coa.code, 'coa_account_id', v_coa.id);
end $$;

create or replace function public.money_account_update(p_id bigint, p_name_en text default null, p_name_bn text default null, p_provider text default null, p_branch text default null,
  p_account_no text default null, p_neg text default null, p_sort int default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p_neg is not null and p_neg not in ('warn', 'block', 'allow') then raise exception 'bad_policy'; end if;
  if a.kind <> 'cash' and ((p_provider is not null and nullif(btrim(p_provider), '') is null) or (p_account_no is not null and nullif(btrim(p_account_no), '') is null)) then raise exception 'provider_and_number_required'; end if;
  update public.money_accounts set name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), name_bn = coalesce(nullif(btrim(p_name_bn), ''), nullif(btrim(p_name_en), ''), name_bn),
    provider = coalesce(left(nullif(btrim(p_provider), ''), 80), provider), branch = coalesce(left(nullif(btrim(p_branch), ''), 80), branch),
    account_no = coalesce(left(nullif(btrim(p_account_no), ''), 40), account_no), neg_policy = coalesce(p_neg, neg_policy), sort = coalesce(p_sort, sort), note = coalesce(left(p_note, 300), note)
   where id = a.id;
  -- the chart account follows the name (code, type and side never change)
  update public.coa_accounts c set name_en = m.name_en, name_bn = m.name_bn from public.money_accounts m
   where m.id = a.id and c.id = m.coa_account_id and not exists (select 1 from public.acct_mappings k where k.account_id = c.id and k.key like 'pay\_%');
  return jsonb_build_object('id', a.id);
end $$;

create or replace function public.money_account_set_active(p_id bigint, p_active boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; ev text; pr jsonb;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p_active is null or p_active = a.active then return jsonb_build_object('id', a.id, 'active', a.active); end if;
  if p_active then
    update public.money_accounts set active = true, deactivated_by = null, deactivated_at = null, deactivate_reason = null where id = a.id;
    update public.coa_accounts set active = true where id = a.coa_account_id;
  else
    if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
    pr := public._m_prove(a.id);
    if abs(coalesce((pr ->> 'journal')::numeric, 0)) > 0.004 or abs(coalesce((pr ->> 'register')::numeric, 0)) > 0.004 then raise exception 'account_not_empty' using detail = 'balance ' || (pr ->> 'register'); end if;
    if coalesce((pr ->> 'pending_n')::int, 0) > 0 then raise exception 'account_has_unposted'; end if;
    select string_agg(event_type, ',') into ev from public.money_event_settings where default_account_id = a.id;
    if ev is not null then raise exception 'account_is_default' using detail = ev; end if;
    if exists (select 1 from public.money_recurring r where r.active and (r.from_account = a.id or r.to_account = a.id)) then raise exception 'account_in_recurring'; end if;
    update public.money_accounts set active = false, deactivated_by = auth.uid(), deactivated_at = now(), deactivate_reason = left(btrim(p_reason), 300) where id = a.id;
    update public.coa_accounts set active = false where id = a.coa_account_id and not exists (select 1 from public.acct_mappings k where k.account_id = a.coa_account_id and k.key like 'pay\_%');
  end if;
  return jsonb_build_object('id', a.id, 'active', p_active);
end $$;

create or replace function public.money_accounts_list(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._acct_today());
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('ready', public._m_accounting_ready(), 'as_of', d, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'code', a.code, 'kind', a.kind, 'name_en', a.name_en, 'name_bn', a.name_bn, 'provider', a.provider, 'branch', a.branch, 'account_no', a.account_no,
      'location_id', a.location_id, 'coa_code', c.code, 'coa_account_id', a.coa_account_id, 'neg_policy', a.neg_policy, 'active', a.active, 'sort', a.sort,
      'opening_amount', a.opening_amount, 'opening_posted', a.opening_posted, 'generic', public._m_is_generic(a.id), 'note', a.note,
      'journal', public._m_journal_bal(a.id, d), 'book', public._m_reg(a.id), 'pending', (public._m_prove(a.id) ->> 'pending')::numeric,
      'is_default_for', coalesce((select jsonb_agg(s.event_type) from public.money_event_settings s where s.default_account_id = a.id), '[]'::jsonb)) order by a.active desc, a.sort, a.id)
    from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id), '[]'::jsonb),
    'legacy_wallets', coalesce((select jsonb_agg(jsonb_build_object('code', w.code, 'name_en', w.name_en, 'coa_code', c.code)) from public.d_wallets w join public.coa_accounts c on c.id = w.coa_account_id), '[]'::jsonb));
end $$;

create or replace function public.money_pick(p_event text, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st public.money_event_settings; seeall boolean := public._m_view();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into st from public.money_event_settings where event_type = p_event;
  if not found then raise exception 'unknown_event'; end if;
  return jsonb_build_object('event', st.event_type, 'default_id', st.default_account_id, 'allow_override', st.allow_override, 'require_source', st.require_source,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'kind', a.kind, 'name_en', a.name_en, 'provider', a.provider, 'location_id', a.location_id,
        'account_no', case when seeall then a.account_no else right(coalesce(a.account_no, ''), 4) end, 'is_default', a.id = st.default_account_id, 'mode', public._m_mode_of_kind(a.kind)) order by a.sort, a.id)
      from public.money_accounts a where a.active and (a.location_id is null or p_loc is null or a.location_id = p_loc)
        and (st.allow_override or st.default_account_id is null or a.id = st.default_account_id)
        and (p_event <> 'cash_handover' or a.kind = 'cash')), '[]'::jsonb));
end $$;

create or replace function public.money_event_settings_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('event_type', s.event_type, 'label_en', s.label_en, 'dir', s.dir, 'default_account_id', s.default_account_id,
    'default_name', a.name_en, 'allow_override', s.allow_override, 'require_source', s.require_source) order by s.sort) from public.money_event_settings s left join public.money_accounts a on a.id = s.default_account_id), '[]'::jsonb);
end $$;

create or replace function public.money_event_setting_set(p_event text, p_default bigint, p_allow_override boolean, p_require boolean, p_clear_default boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.money_event_settings; a public.money_accounts; nd bigint;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  select * into s from public.money_event_settings where event_type = p_event for update;
  if not found then raise exception 'unknown_event'; end if;
  nd := case when coalesce(p_clear_default, false) then null else coalesce(p_default, s.default_account_id) end;
  if nd is not null then
    select * into a from public.money_accounts where id = nd;
    if not found or not a.active then raise exception 'money_account_inactive'; end if;
    if p_event = 'cash_handover' and a.kind <> 'cash' then raise exception 'money_account_kind'; end if;
  end if;
  update public.money_event_settings set default_account_id = nd, allow_override = coalesce(p_allow_override, allow_override), require_source = coalesce(p_require, require_source),
    updated_by = auth.uid(), updated_at = now() where event_type = p_event;
  return jsonb_build_object('event_type', p_event, 'default_account_id', nd);
end $$;

-- ---------- exceptions ----------
create or replace function public.money_exception_grant(p_rule text, p_reason text, p_for_user uuid default null, p_client uuid default null, p_event text default null,
  p_account bigint default null, p_max numeric default null, p_date date default null, p_hours int default 24) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rule is null or p_rule not in ('negative', 'require_source', 'override', 'period_lock', 'approver') then raise exception 'bad_rule'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_for_user is null and p_client is null then raise exception 'target_required'; end if;
  if p_for_user is not null and not exists (select 1 from public.profiles where id = p_for_user and status = 'active') then raise exception 'unknown_user'; end if;
  insert into public.money_exception_grants (rule, event_type, for_user, client_id, account_id, max_amount, on_date, reason, granted_by, expires_at)
    values (p_rule, p_event, p_for_user, p_client, p_account, p_max, p_date, left(btrim(p_reason), 300), auth.uid(), now() + make_interval(hours => least(greatest(coalesce(p_hours, 24), 1), 168))) returning id into id_;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_grant', 'money_exception_grants', id_::text,
      jsonb_build_object('rule', p_rule, 'event', p_event, 'for_user', p_for_user, 'client', p_client, 'account', p_account, 'max', p_max, 'date', p_date, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.money_exception_revoke(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.money_exception_grants set revoked = true where id = p_id and used_at is null;
  if not found then raise exception 'not found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_revoke', 'money_exception_grants', p_id::text, jsonb_build_object('note', left(p_note, 200)));
  return jsonb_build_object('id', p_id, 'revoked', true);
end $$;

create or replace function public.money_exceptions_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select x.id, x.at, x.kind, x.event_type, x.account_id, a.name_en as account_name, x.amount, x.src_table, x.src_id, x.reason, x.status, x.resolve_note, x.resolved_at
        from public.money_exceptions x left join public.money_accounts a on a.id = x.account_id where p_status is null or x.status = p_status order by x.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb),
    'grants', case when public.is_owner() then coalesce((select jsonb_agg(to_jsonb(g) order by g.id desc) from (select * from public.money_exception_grants order by id desc limit 100) g), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.money_exception_resolve(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  update public.money_exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolve_note = left(btrim(p_note), 300) where id = p_id and status = 'open';
  if not found then raise exception 'not found'; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_resolve', 'money_exceptions', p_id::text, jsonb_build_object('note', left(btrim(p_note), 300)));
  return jsonb_build_object('id', p_id, 'status', 'resolved');
end $$;

-- period lock: an owner granted one-off exception (rule period_lock). lock_check is patched to ask this; the grant is used once per transaction.
create or replace function public._m_lock_exc(p_date date) returns boolean language plpgsql security definer set search_path = public as $$
declare g public.money_exception_grants; cur text := coalesce(current_setting('bos87.lockx', true), '');
begin
  if auth.uid() is null then return false; end if;
  if cur <> '' then return true; end if;
  select * into g from public.money_exception_grants x
   where x.rule = 'period_lock' and not x.revoked and x.used_at is null and x.expires_at > now() and x.for_user = auth.uid() and (x.on_date is null or x.on_date = p_date)
   order by x.id limit 1 for update skip locked;
  if not found then return false; end if;
  update public.money_exception_grants set used_at = now(), used_ref = 'lock ' || p_date::text where id = g.id;
  perform set_config('bos87.lockx', g.id::text, true);
  insert into public.money_exceptions (kind, reason, amount, src_id, by_user) values ('period_lock_exception', g.reason || ' (date ' || p_date::text || ')', null, 'lock_check', auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'money_exception_used', 'money_exception_grants', g.id::text,
      jsonb_build_object('rule', 'period_lock', 'date', p_date, 'reason', g.reason, 'granted_by', g.granted_by));
  return true;
end $$;

-- ============================================================================
-- PART D: transfers, charges, recurring
-- ============================================================================
create or replace function public._m_transfer_core(p_from bigint, p_to bigint, p_amount numeric, p_date date, p_fee numeric, p_fee_side text, p_ref text, p_note text, p_loc int, p_client uuid, p_rec bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f public.money_accounts; t public.money_accounts; t0 public.money_transfers; amt numeric := round(p_amount, 2); fee numeric := round(coalesce(p_fee, 0), 2); loc int; sid text; id_ bigint;
begin
  if p_from is null or p_to is null or p_from = p_to then raise exception 'same_account'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if fee < 0 or fee > 1000000000 then raise exception 'bad_amount'; end if;
  if coalesce(p_fee_side, 'from') not in ('from', 'to') then raise exception 'bad_kind'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if coalesce(p_fee_side, 'from') = 'to' and fee > amt then raise exception 'fee_exceeds_amount'; end if;
  perform public.lock_check(p_date);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into t0 from public.money_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t0.id); end if;
  end if;
  select * into f from public.money_accounts where id = least(p_from, p_to) for update;      -- fixed lock order
  select * into t from public.money_accounts where id = greatest(p_from, p_to) for update;
  select * into f from public.money_accounts where id = p_from; select * into t from public.money_accounts where id = p_to;
  if f.id is null or t.id is null then raise exception 'unknown_money_account'; end if;
  if not f.active or not t.active then raise exception 'money_account_inactive'; end if;
  loc := coalesce(p_loc, f.location_id, t.location_id);
  if p_loc is not null and ((f.location_id is not null and f.location_id <> p_loc) or (t.location_id is not null and t.location_id <> p_loc)) and auth.uid() is not null then raise exception 'money_account_place'; end if;
  if loc is null then raise exception 'place_required'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if auth.uid() is not null then
    perform public._m_neg_check(f.id, amt + case when coalesce(p_fee_side, 'from') = 'from' then fee else 0 end, 'money_transfer', p_client, p_date, 'money_transfers');
    if coalesce(p_fee_side, 'from') = 'to' and fee > 0 then null; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_transfers (client_id, from_account, to_account, amount, fee, fee_side, xfer_date, location_id, ref, note, recurring_id, created_by, created_staff)
    values (p_client, p_from, p_to, amt, fee, coalesce(p_fee_side, 'from'), p_date, loc, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_rec, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'from_balance', public._m_reg(p_from), 'to_balance', public._m_reg(p_to));
end $$;

create or replace function public.money_transfer_add(p_from bigint, p_to bigint, p_amount numeric, p_date date, p_fee numeric default 0, p_fee_side text default 'from',
  p_ref text default null, p_note text default null, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._m_mgr() or public._d_cash_ok(p_loc)) then raise exception 'not allowed'; end if;
  return public._m_transfer_core(p_from, p_to, p_amount, p_date, p_fee, p_fee_side, p_ref, p_note, p_loc, p_client, null);
end $$;

create or replace function public.money_transfer_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.money_transfers;
begin
  select * into t from public.money_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(t.location_id)) then raise exception 'not allowed'; end if;
  if t.status = 'void' then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(t.xfer_date);
  perform public._m_neg_check(t.to_account, t.amount - case when t.fee_side = 'to' then t.fee else 0 end, 'money_transfer_void', null, t.xfer_date, 'money_transfers');
  update public.money_transfers set status = 'void', void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = t.id;
  return jsonb_build_object('id', t.id, 'voided', true);
end $$;

create or replace function public.money_charge_add(p_account bigint, p_kind text, p_amount numeric, p_date date, p_ref text default null, p_note text default null, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; amt numeric := round(p_amount, 2); c0 public.money_charges; id_ bigint; sid text;
begin
  if not (public._m_mgr() or public._d_cash_ok(p_loc)) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('charge', 'interest') then raise exception 'bad_kind'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  perform public.lock_check(p_date);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into c0 from public.money_charges where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', c0.id); end if;
  end if;
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_kind = 'charge' then perform public._m_neg_check(a.id, amt, 'money_charge', p_client, p_date, 'money_charges'); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_charges (client_id, account_id, kind, amount, charge_date, location_id, ref, note, created_by, created_staff)
    values (p_client, a.id, p_kind, amt, p_date, coalesce(p_loc, a.location_id), left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'balance', public._m_reg(a.id));
end $$;

create or replace function public.money_charge_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.money_charges;
begin
  select * into c from public.money_charges where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(c.location_id)) then raise exception 'not allowed'; end if;
  if c.status = 'void' then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(c.charge_date);
  if c.kind = 'interest' then perform public._m_neg_check(c.account_id, c.amount, 'money_charge_void', null, c.charge_date, 'money_charges'); end if;
  update public.money_charges set status = 'void', void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'voided', true);
end $$;

create or replace function public.money_recurring_add(p_name text, p_from bigint, p_to bigint, p_amount numeric, p_day int, p_start date, p_end date default null, p_fee numeric default 0, p_fee_side text default 'from', p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  if p_from = p_to then raise exception 'same_account'; end if;
  if not exists (select 1 from public.money_accounts where id = p_from and active) or not exists (select 1 from public.money_accounts where id = p_to and active) then raise exception 'money_account_inactive'; end if;
  insert into public.money_recurring (name, from_account, to_account, amount, fee, fee_side, day_of_month, start_date, end_date, location_id, created_by)
    values (p_name, p_from, p_to, round(p_amount, 2), round(coalesce(p_fee, 0), 2), coalesce(p_fee_side, 'from'), p_day, p_start, p_end, p_loc, auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.money_recurring_set_active(p_id bigint, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  update public.money_recurring set active = coalesce(p_active, active) where id = p_id;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('id', p_id, 'active', p_active);
end $$;

create or replace function public.money_recurring_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from public.money_recurring r), '[]'::jsonb);
end $$;

-- creates the transfers that are due up to p_date (once each: the client id is derived from the template and the due date)
create or replace function public.money_recurring_run(p_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(p_date, public._acct_today()); r public.money_recurring; due date; made int := 0; errs jsonb := '[]'; cid uuid;
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  for r in select * from public.money_recurring where active order by id loop
    due := make_date(extract(year from d)::int, extract(month from d)::int, r.day_of_month);
    if d < due or due < r.start_date or (r.end_date is not null and due > r.end_date) or (r.last_run is not null and r.last_run >= due) then continue; end if;
    cid := md5('money_recurring:' || r.id::text || ':' || due::text)::uuid;
    begin
      perform public._m_transfer_core(r.from_account, r.to_account, r.amount, due, r.fee, r.fee_side, 'REC-' || r.id::text, r.name, r.location_id, cid, r.id);
      update public.money_recurring set last_run = due where id = r.id;
      made := made + 1;
    exception when others then errs := errs || jsonb_build_object('recurring_id', r.id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('date', d, 'made', made, 'errors', errs);
end $$;

-- ============================================================================
-- PART E: journal sources, day book rows, statements, summary, real balance check, reports, balance check
-- ============================================================================
-- journal sources of this phase, same shape as _acct_docs (hooked in by the patch below)
create or replace function public._m_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  -- a transfer: Dr receiving account, Cr paying account; the fee (if any) is its own expense line against the account that bears it. One balanced entry.
  return query
  select 'money_transfer'::text, t.id::text, t.xfer_date, t.location_id, ('Transfer ' || fa.name_en || ' to ' || ta.name_en)::text, null::text, t.status = 'done',
    coalesce((t.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when t.status = 'done' then
      jsonb_build_array(jsonb_build_object('a', 'm_acct_' || t.to_account::text, 'd', t.amount), jsonb_build_object('a', 'm_acct_' || t.from_account::text, 'c', t.amount))
      || case when t.fee > 0 then jsonb_build_array(
           jsonb_build_object('a', case when (case t.fee_side when 'from' then fa.kind else ta.kind end) = 'wallet' then 'wallet_fee' else 'm_bank_charge' end, 'd', t.fee),
           jsonb_build_object('a', 'm_acct_' || (case t.fee_side when 'from' then t.from_account else t.to_account end)::text, 'c', t.fee)) else '[]'::jsonb end
    end
  from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
  where t.xfer_date >= p_start and public._acct_need('money_transfer', t.id::text, t.status = 'done');
  -- bank / wallet charge: Dr charge expense, Cr the account. Interest: Dr the account, Cr interest income.
  return query
  select 'money_charge'::text, c.id::text, c.charge_date, c.location_id, ((case c.kind when 'interest' then 'Interest ' else 'Charge ' end) || a.name_en)::text, c.kind, c.status = 'done',
    coalesce((c.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when c.status = 'done' then case c.kind
      when 'interest' then jsonb_build_array(jsonb_build_object('a', 'm_acct_' || c.account_id::text, 'd', c.amount), jsonb_build_object('a', 'm_interest_income', 'c', c.amount))
      else jsonb_build_array(jsonb_build_object('a', case a.kind when 'wallet' then 'wallet_fee' else 'm_bank_charge' end, 'd', c.amount), jsonb_build_object('a', 'm_acct_' || c.account_id::text, 'c', c.amount)) end end
  from public.money_charges c join public.money_accounts a on a.id = c.account_id
  where c.charge_date >= p_start and public._acct_need('money_charge', c.id::text, c.status = 'done');
end $$;

-- day book rows for transfers and charges (same columns as _daybook_lines); both sides of a transfer are shown, one per account mode
create or replace function public._m_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select t.location_id, t.xfer_date, 'out'::text, public._m_mode_of_kind(fa.kind), 'money_transfer'::text, t.amount + case when t.fee_side = 'from' then t.fee else 0 end, t.ref,
         nullif(btrim(concat_ws(' · ', 'to ' || ta.name_en, case when t.fee > 0 then 'fee ' || t.fee::text end, fa.name_en, t.note)), ''), t.created_staff, t.created_at, 'money_transfer'::text, t.id::text, false, false
    from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
   where t.status = 'done' and t.location_id = any (p_locs) and t.xfer_date between p_from and p_to
  union all
  select t.location_id, t.xfer_date, 'in', public._m_mode_of_kind(ta.kind), 'money_transfer', t.amount - case when t.fee_side = 'to' then t.fee else 0 end, t.ref,
         nullif(btrim(concat_ws(' · ', 'from ' || fa.name_en, ta.name_en, t.note)), ''), t.created_staff, t.created_at, 'money_transfer', t.id::text, false, false
    from public.money_transfers t join public.money_accounts fa on fa.id = t.from_account join public.money_accounts ta on ta.id = t.to_account
   where t.status = 'done' and t.location_id = any (p_locs) and t.xfer_date between p_from and p_to
  union all
  select c.location_id, c.charge_date, case c.kind when 'interest' then 'in' else 'out' end, public._m_mode_of_kind(a.kind), 'money_charge', c.amount, c.ref,
         nullif(btrim(concat_ws(' · ', a.name_en, c.kind, c.note)), ''), c.created_staff, c.created_at, 'money_charge', c.id::text, false, false
    from public.money_charges c join public.money_accounts a on a.id = c.account_id
   where c.status = 'done' and c.location_id = any (p_locs) and c.charge_date between p_from and p_to $$;

create or replace function public._m_csv(t text) returns text language sql immutable as $$ select '"' || replace(coalesce(t, ''), '"', '""') || '"' $$;

-- ---------- per account statement (opening, in, out, closing for a date range) ----------
create or replace function public.money_statement(p_account bigint, p_from date default null, p_to date default null, p_loc int default null, p_limit int default 2000) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts; st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date; to_ date := coalesce(p_to, public._acct_today());
  open_ numeric; rows_ jsonb; tin numeric; tout numeric; pend jsonb; lim int := least(greatest(coalesce(p_limit, 2000), 1), 5000);
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'not found'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  select coalesce(sum(l.debit - l.credit), 0) into open_ from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.entry_date < fr and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(sum(l.debit), 0), coalesce(sum(l.credit), 0) into tin, tout from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.account_id = a.coa_account_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('date', w.entry_date, 'entry_id', w.entry_id, 'line_no', w.line_no, 'memo', w.memo, 'source_type', w.source_type, 'source_id', w.source_id,
      'counter', w.counter, 'location_id', w.location_id, 'in', w.debit, 'out', w.credit, 'balance', w.bal, 'reversal', w.reverses_id is not null) order by w.entry_date, w.entry_id, w.line_no), '[]'::jsonb)
    into rows_ from (
      select z.*, open_ + sum(z.debit - z.credit) over (order by z.entry_date, z.entry_id, z.line_no) bal from (
        select e.entry_date, e.id entry_id, l.line_no, e.memo, e.source_type, e.source_id, e.reverses_id, l.location_id, l.debit, l.credit,
               (select string_agg(distinct c2.code, ',') from public.journal_lines l2 join public.coa_accounts c2 on c2.id = l2.account_id where l2.entry_id = l.entry_id and l2.account_id <> l.account_id) counter
          from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
         where l.account_id = a.coa_account_id and e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
         order by e.entry_date, e.id, l.line_no limit lim) z) w;
  select coalesce(jsonb_agg(jsonb_build_object('date', s.d, 'source', s.tbl, 'id', s.pk, 'event', s.ev, 'amount', s.amt, 'memo', s.memo) order by s.d), '[]'::jsonb) into pend
    from public._m_src(a.id) s
   where s.live and s.d between fr and to_ and not exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null);
  return jsonb_build_object('account', jsonb_build_object('id', a.id, 'code', a.code, 'kind', a.kind, 'name_en', a.name_en, 'provider', a.provider, 'account_no', a.account_no, 'active', a.active),
    'from', fr, 'to', to_, 'opening', open_, 'in', tin, 'out', tout, 'closing', open_ + tin - tout, 'rows', rows_, 'not_posted_yet', pend,
    'truncated', jsonb_array_length(rows_) >= lim);
end $$;

create or replace function public.money_statement_csv(p_account bigint, p_from date default null, p_to date default null, p_loc int default null) returns text
language plpgsql stable security definer set search_path = public as $$
declare s jsonb := public.money_statement(p_account, p_from, p_to, p_loc, 5000); out_ text; r jsonb;
begin
  if s ? 'data_needed' then return 'data_needed'; end if;
  out_ := 'Statement,' || public._m_csv(s #>> '{account,name_en}') || E'\nFrom,' || (s ->> 'from') || E'\nTo,' || (s ->> 'to') || E'\nOpening,' || (s ->> 'opening') || E'\n' ||
          'date,entry,source,memo,counter account,in,out,balance' || E'\n';
  for r in select * from jsonb_array_elements(s -> 'rows') loop
    out_ := out_ || (r ->> 'date') || ',' || (r ->> 'entry_id') || ',' || public._m_csv(r ->> 'source_type') || ',' || public._m_csv(r ->> 'memo') || ',' || public._m_csv(r ->> 'counter') || ',' ||
            (r ->> 'in') || ',' || (r ->> 'out') || ',' || (r ->> 'balance') || E'\n';
  end loop;
  return out_ || 'Totals,,,,,' || (s ->> 'in') || ',' || (s ->> 'out') || ',' || (s ->> 'closing') || E'\n';
end $$;

-- ---------- period summary across all accounts (opening, in, out, closing per account; per day totals) ----------
create or replace function public.money_summary(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); fr date; to_ date := coalesce(p_to, public._acct_today()); rows_ jsonb; days_ jsonb; tot jsonb;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ then raise exception 'bad_range'; end if;
  with b as (
    select a.id, a.code, a.kind, a.name_en, a.active,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date < fr), 0) op,
      coalesce(sum(l.debit) filter (where e.entry_date between fr and to_), 0) din,
      coalesce(sum(l.credit) filter (where e.entry_date between fr and to_), 0) dout,
      coalesce(sum(l.debit - l.credit) filter (where e.entry_date <= to_), 0) cl
    from public.money_accounts a
    left join public.journal_lines l on l.account_id = a.coa_account_id and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)
    left join public.journal_entries e on e.id = l.entry_id
    group by a.id, a.code, a.kind, a.name_en, a.active, a.sort order by a.sort, a.id)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'code', code, 'kind', kind, 'name_en', name_en, 'active', active, 'opening', op, 'in', din, 'out', dout, 'closing', cl)) filter (where active or op <> 0 or din <> 0 or dout <> 0 or cl <> 0), '[]'::jsonb),
         jsonb_build_object('opening', coalesce(sum(op), 0), 'in', coalesce(sum(din), 0), 'out', coalesce(sum(dout), 0), 'closing', coalesce(sum(cl), 0))
    into rows_, tot from b;
  select coalesce(jsonb_agg(jsonb_build_object('date', d, 'in', i, 'out', o, 'net', i - o) order by d), '[]'::jsonb) into days_ from (
    select e.entry_date d, sum(l.debit) i, sum(l.credit) o from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.money_accounts a on a.coa_account_id = l.account_id
     where e.entry_date between fr and to_ and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc) group by e.entry_date) z;
  return jsonb_build_object('from', fr, 'to', to_, 'accounts', rows_, 'total', tot, 'days', days_,
    'note', 'In and out include transfers between your own accounts (they cancel in the total).');
end $$;

-- ---------- the real balance (blind) ----------
create or replace function public._m_book(p_acc bigint, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select public._m_journal_bal(p_acc, p_asof) + case when public._m_is_generic(p_acc) then 0 else coalesce((select sum(s.amt) from public._m_src(p_acc) s
      where s.live and s.d <= p_asof and not exists (select 1 from public.journal_entries e where e.source_type = s.jtype and e.source_id = s.jid and e.reverses_id is null)), 0) end $$;

create or replace function public.money_check_save(p_account bigint, p_date date, p_real numeric, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.money_accounts; c public.money_checks; book numeric; df numeric; real_ numeric := round(p_real, 2); sid text; ex bigint;
begin
  select * into a from public.money_accounts where id = p_account;
  if not found then raise exception 'not found'; end if;
  if not (public._m_mgr() or public._d_cash_ok(a.location_id)) then raise exception 'not allowed'; end if;
  if real_ is null or real_ < 0 or real_ > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into c from public.money_checks where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', c.id, 'book', c.book_balance, 'diff', c.diff, 'status', c.status); end if;
  end if;
  book := public._m_book(a.id, p_date); df := round(real_ - book, 2);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.money_checks (account_id, check_date, real_balance, book_balance, diff, status, client_id, counted_by, counted_staff)
    values (a.id, p_date, real_, book, df, case when df = 0 then 'matched' else 'difference' end, p_client, auth.uid(), sid) returning * into c;
  if df <> 0 then
    insert into public.money_exceptions (kind, account_id, amount, src_table, src_id, reason, by_user) values ('recon_diff', a.id, df, 'money_checks', c.id::text, 'real ' || real_::text || ' book ' || book::text, auth.uid());
  end if;
  return jsonb_build_object('id', c.id, 'real', c.real_balance, 'book', c.book_balance, 'diff', c.diff, 'status', c.status);      -- the book figure is shown only now, after the count is saved
end $$;

create or replace function public.money_check_explain(p_check bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.money_checks; a public.money_accounts;
begin
  select * into c from public.money_checks where id = p_check for update;
  if not found then raise exception 'not found'; end if;
  select * into a from public.money_accounts where id = c.account_id;
  if not (public._m_mgr() or public._d_cash_ok(a.location_id)) then raise exception 'not allowed'; end if;
  if c.status <> 'difference' then raise exception 'nothing_to_explain'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.money_checks set reason = left(btrim(p_reason), 300), status = 'explained', reason_by = auth.uid(), reason_at = now() where id = c.id;
  update public.money_exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolve_note = left(btrim(p_reason), 300)
   where kind = 'recon_diff' and src_table = 'money_checks' and src_id = c.id::text and status = 'open';
  return jsonb_build_object('id', c.id, 'status', 'explained');
end $$;

create or replace function public.money_checks_list(p_account bigint default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public._d_cash_ok(null)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'account_id', k.account_id, 'account', a.name_en, 'date', k.check_date, 'real', k.real_balance, 'book', k.book_balance, 'diff', k.diff,
    'status', k.status, 'reason', k.reason) order by k.id desc) from (select * from public.money_checks where p_account is null or account_id = p_account order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) k
    join public.money_accounts a on a.id = k.account_id), '[]'::jsonb);
end $$;

-- ---------- Balance Check item: money accounts total = sum of the mapped ledger accounts ----------
create or replace function public._m_balance_check(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; pr jsonb; rows_ jsonb := '[]'; tot_reg numeric := 0; tot_led numeric := 0; bad int := 0; pend int := 0; n int := 0;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  for r in select a.id, a.code, a.name_en from public.money_accounts a order by a.id loop
    pr := public._m_prove(r.id); n := n + 1;
    tot_reg := tot_reg + (pr ->> 'register')::numeric; tot_led := tot_led + (pr ->> 'journal')::numeric;
    if abs((pr ->> 'diff')::numeric) > 0.004 then bad := bad + 1; end if;
    if abs((pr ->> 'pending')::numeric) > 0.004 or abs((pr ->> 'stale')::numeric) > 0.004 then pend := pend + 1; end if;
    if abs((pr ->> 'diff')::numeric) > 0.004 or abs((pr ->> 'pending')::numeric) > 0.004 or abs((pr ->> 'stale')::numeric) > 0.004 then
      rows_ := rows_ || (pr || jsonb_build_object('code', r.code, 'name_en', r.name_en));
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'accounts', n, 'money_accounts_total', tot_reg, 'ledger_total', tot_led, 'difference', round(tot_reg - tot_led, 2),
    'unexplained_accounts', bad, 'timing_accounts', pend, 'rows', rows_, 'red', bad > 0, 'amber', pend > 0, 'ok', bad = 0 and pend = 0,
    'note', 'Money accounts total = the book balance of every registered account (payments counted when entered). Ledger total = the mapped chart accounts in the journal. A difference that is only a payment not posted yet is timing (amber); a ledger movement that belongs to no payment is red.');
end $$;

-- ---------- reports: P&L and balance sheet with the cash / bank / wallet lines per account ----------
create or replace function public.money_statements(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); v_locs int[] := public._acct_locs(); lines_ jsonb;
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  fr := coalesce(p_from, st);
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', c.code, 'coa_code', c.code, 'name_en', a.name_en, 'kind', a.kind, 'active', a.active,
      'opening', x.op, 'in', x.din, 'out', x.dout, 'closing', x.cl) order by a.kind, a.sort, a.id), '[]'::jsonb) into lines_
    from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id
    cross join lateral (select coalesce(sum(l.debit - l.credit) filter (where e.entry_date < fr), 0) op, coalesce(sum(l.debit) filter (where e.entry_date between fr and to_), 0) din,
                               coalesce(sum(l.credit) filter (where e.entry_date between fr and to_), 0) dout, coalesce(sum(l.debit - l.credit) filter (where e.entry_date <= to_), 0) cl
                          from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                         where l.account_id = a.coa_account_id and (v_all or l.location_id = any (v_locs)) and (p_loc is null or l.location_id = p_loc)) x
   where a.active or x.op <> 0 or x.din <> 0 or x.dout <> 0 or x.cl <> 0;
  return jsonb_build_object('from', fr, 'to', to_, 'income_statement', public.acct_income_statement(fr, to_, p_loc), 'balance_sheet', public.acct_balance_sheet(to_, p_loc),
    'money_lines', lines_, 'money_total_closing', (select coalesce(sum((z ->> 'closing')::numeric), 0) from jsonb_array_elements(lines_) z));
end $$;

-- ---------- salary reports show the payment source ----------
create or replace function public.money_salary_sources(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._acct_view() or p_loc is not null and public.has_grant('salary_view', p_loc)) then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'date', p.pay_date, 'run', p.run_id, 'employee_no', e.employee_no, 'employee', e.full_name_bn, 'amount', p.amount, 'mode', p.mode,
        'money_account_id', p.money_account_id, 'source', coalesce(a.name_en, 'not named (' || p.mode || ')'), 'status', p.status) order by p.pay_date, p.id)
      from public.payroll_payments p join public.employees e on e.id = p.employee_id left join public.money_accounts a on a.id = p.money_account_id
      where p.pay_date between p_from and p_to and (p_loc is null or p.location_id = p_loc) and (public.is_owner() or public.has_grant('salary_view', p.location_id))), '[]'::jsonb),
    'by_source', coalesce((select jsonb_agg(jsonb_build_object('source', s, 'amount', t) order by s) from (
        select coalesce(a.name_en, 'not named (' || p.mode || ')') s, sum(p.amount) t from public.payroll_payments p left join public.money_accounts a on a.id = p.money_account_id
         where p.pay_date between p_from and p_to and p.status = 'done' and (p_loc is null or p.location_id = p_loc) and (public.is_owner() or public.has_grant('salary_view', p.location_id)) group by 1) z), '[]'::jsonb));
end $$;

-- ---------- opening balance: the section "money" of opening_balance_post (phase80) ----------
create or replace function public._m_opening_line(x jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a public.money_accounts;
begin
  select * into a from public.money_accounts where id = public._m_id(x ->> 'money_account_id');
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if coalesce(x ->> 'amount', '') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then raise exception 'bad_amount'; end if;
  return jsonb_build_object('a', 'm_acct_' || a.id::text, 'debit', x ->> 'amount', 'memo', left('opening ' || a.name_en, 120), 'location_id', a.location_id);
end $$;
create or replace function public._m_opening_mark(p_json jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x jsonb;
begin
  for x in select * from jsonb_array_elements(coalesce(p_json -> 'money', '[]'::jsonb)) loop
    update public.money_accounts set opening_amount = (x ->> 'amount')::numeric, opening_posted = true, opening_date = coalesce(public._acct_start(), opening_date) where id = public._m_id(x ->> 'money_account_id');
  end loop;
end $$;
-- the "money" section the opening screen should send: every registered account with the opening figure typed on it
create or replace function public.money_opening_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('money_account_id', a.id, 'amount', a.opening_amount::text) order by a.id) from public.money_accounts a
                    where a.active and a.opening_amount > 0 and not a.opening_posted), '[]'::jsonb);
end $$;

-- ============================================================================
-- PART F: PATCHES of the shared functions (text patch of the LIVE definition; each site must exist, otherwise the paste stops)
--   _acct_docs / _c_docs : the money line of 14 payment events uses the payment's own account (mapping key m_acct_<id>) when it has one, else exactly what it used before
--   day book (3 functions): 10-2 mode follows the account, the account name is shown in the text of the line, transfers and charges are listed
--   daybook_vs_journal, acct_cash_flow : the money accounts count as cash / bank / mobile accounts
--   _e_balance_check : the new item money_accounts       opening_balance_post : the section "money"       lock_check : owner granted one-off exception
-- ============================================================================
select public._m_patch('public._acct_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', public._acct_paykey(p.mode, true), 'c', p.amount)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._acct_paykey(p.mode, true)), 'c', p.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(f.mode, true), 'd', f.amount)$a$, $a$jsonb_build_object('a', public._m_key(f.money_account_id, public._acct_paykey(f.mode, true)), 'd', f.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(coalesce(r.refund_mode, 'cash')), 'c', r.refund_amount)$a$, $a$jsonb_build_object('a', public._m_key(r.money_account_id, public._acct_paykey(coalesce(r.refund_mode, 'cash'))), 'c', r.refund_amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', 'pay_cash', 'c', v.total)$a$, $a$jsonb_build_object('a', public._m_key(public._m_id(e.data ->> 'money_account_id'), 'pay_cash'), 'c', v.total) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(q.mode), 'c', q.amount)$a$, $a$jsonb_build_object('a', public._m_key(q.money_account_id, public._acct_paykey(q.mode)), 'c', q.amount) /* bos87 */$a$,
  $a$public._acct_paykey(m.mode)$a$, $a$public._m_key(m.money_account_id, public._acct_paykey(m.mode)) /* bos87 */$a$,
  $a$jsonb_build_object('a', 'pay_cash', 'd', m.amount), jsonb_build_object('a', 'hub_clearing'$a$, $a$jsonb_build_object('a', public._m_key(m.money_account_id, 'pay_cash'), 'd', m.amount), jsonb_build_object('a', 'hub_clearing'$a$,
  $a$jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount /* bos85 */)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount /* bos85 */)$a$,
  $a$jsonb_build_object('a', public._acct_paykey(a.mode), 'c', a.amount)$a$, $a$jsonb_build_object('a', public._m_key(a.money_account_id, public._acct_paykey(a.mode)), 'c', a.amount)$a$,
  $a$public._acct_paykey(c.mode)$a$, $a$public._m_key(c.money_account_id, public._acct_paykey(c.mode))$a$,
  $a$return query select * from public._d_acct_docs(p_start); /* bos85 */$a$, $a$return query select * from public._d_acct_docs(p_start); /* bos85 */
  return query select * from public._m_docs(p_start); /* bos87: transfers and charges between money accounts */$a$]);

select public._m_patch('public._c_docs(date)'::regprocedure, array[
  $a$jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount)$a$, $a$jsonb_build_object('a', public._m_key(p.money_account_id, public._c_salary_paykey(p.mode)), 'c', p.amount) /* bos87 */$a$,
  $a$jsonb_build_object('a', public._acct_paykey(pp.mode), 'c', pp.amount)$a$, $a$jsonb_build_object('a', public._m_key(pp.money_account_id, public._acct_paykey(pp.mode)), 'c', pp.amount)$a$]);

select public._m_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, array[
  $a$select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot,$a$, $a$select e.location_id, e.entry_date, 'out', coalesce(public._m_mode(e.data ->> 'money_account_id'), 'cash') /* bos87 */, 'expense', x.tot,$a$,
  $a$x.n::text || ' line(s)', e.created_staff$a$, $a$x.n::text || ' line(s)' || coalesce(' · ' || public._m_name(public._m_id(e.data ->> 'money_account_id')), ''), e.created_staff$a$,
  $a$concat_ws(' · ', su.name, sp.wallet, sp.ref)$a$, $a$concat_ws(' · ', su.name, coalesce(public._m_name(sp.money_account_id), sp.wallet), sp.ref)$a$,
  $a$select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */;$a$, $a$select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */
  union all select * from public._m_daybook_rows(p_locs, p_from, p_to) /* bos87 */;$a$]);

select public._m_patch('public._daybook_lines12(integer[],date,date)'::regprocedure, array[
  $a$concat_ws(' · ', c.name, r.wallet, r.ref)$a$, $a$concat_ws(' · ', c.name, coalesce(public._m_name(r.money_account_id), r.wallet), r.ref) /* bos87 */$a$,
  $a$concat_ws(' · ', su.name, f.wallet, f.ref)$a$, $a$concat_ws(' · ', su.name, coalesce(public._m_name(f.money_account_id), f.wallet), f.ref)$a$]);

select public._m_patch('public._daybook_lines23(integer[],date,date)'::regprocedure, array[
  $a$concat_ws(' · ', c.name, m.note)$a$, $a$concat_ws(' · ', c.name, public._m_name(m.money_account_id), m.note) /* bos87 */$a$,
  $a$concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)$a$, $a$concat_ws(' · ', e.employee_no, e.full_name_bn, public._m_name(p.money_account_id), p.note)$a$,
  $a$concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)$a$, $a$concat_ws(' · ', e.employee_no, e.full_name_bn, public._m_name(a.money_account_id), a.note)$a$,
  $a$concat_ws(' · ', q.paid_to, q.head, q.note)$a$, $a$concat_ws(' · ', q.paid_to, q.head, public._m_name(q.money_account_id), q.note)$a$]);

select public._m_patch('public.daybook_vs_journal(date,date,integer)'::regprocedure, array[
  $a$join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')$a$,
  $a$join (select m0.account_id, m0.key from public.acct_mappings m0 union select ma.coa_account_id, 'pay_' || public._m_mode_of_kind(ma.kind) from public.money_accounts ma) a /* bos87 */
        on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')$a$]);

select public._m_patch('public.acct_cash_flow(date,date,integer)'::regprocedure, array[
  $a$select array_agg(account_id) into ids from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile');$a$,
  $a$select array_agg(account_id) into ids from (select account_id from public.acct_mappings where key in ('pay_cash', 'pay_bank', 'pay_mobile') union select coa_account_id from public.money_accounts) z; /* bos87 */$a$]);

select public._m_patch('public._e_balance_check(date,integer,integer)'::regprocedure, array[
  $a$eq jsonb; trial jsonb;$a$, $a$mnc jsonb; eq jsonb; trial jsonb;$a$,
  $a$red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0;$a$,
  $a$begin   -- bos87: money accounts total = the mapped ledger accounts (amber = a payment not posted yet, red = a ledger movement that belongs to no payment)
    mnc := public._m_balance_check(d);
    xc := xc || jsonb_build_object('money_accounts', mnc);
    if coalesce((mnc ->> 'amber')::boolean, false) then warn := warn || to_jsonb('money_accounts'::text); end if;
  exception when others then mnc := null; xc := xc || jsonb_build_object('money_accounts', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0 or coalesce((mnc ->> 'red')::boolean, false);$a$,
  $a$('journal', jr_n > 0), ('stock_identity', st_n > 0)) v(k, bad)$a$, $a$('journal', jr_n > 0), ('stock_identity', st_n > 0), ('money_accounts', coalesce((mnc ->> 'red')::boolean, false))) v(k, bad)$a$]);

select public._m_patch('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure, array[
  $a$if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other') then$a$, $a$if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other', 'money') then /* bos87 */$a$,
  $a$for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop$a$, $a$for x in select * from jsonb_array_elements(coalesce(p_json->'money', '[]')) loop   /* bos87: a registered money account, Dr its own chart account */
    ln := ln || public._m_opening_line(x);
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop$a$,
  $a$jid := (r->>'id')::bigint;$a$, $a$jid := (r->>'id')::bigint; perform public._m_opening_mark(p_json); /* bos87 */$a$]);

select public._m_patch('public.lock_check(date)'::regprocedure, array[
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;$a$,
  $a$if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  if public._m_lock_exc(p_date) then return; end if;   -- bos87: an owner granted one-off exception (reason on record, shown in the Exceptions list)$a$]);

-- ============================================================================
-- PART G: approver choice. Not fixed: any role OR any named user, as a setting (named mode) and per individual entry, changeable at any time (audit_log line each time).
--   Kept from phase80/86: safe default stays mode self with nobody named; the decider is never the maker; the owner cannot hold the approver role he names;
--   owner_self_approve cannot be switched back on while the mode is named; the owner can always return to self (recovery).
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_approver_users', 'lists', 'text', null, null, null, null, null,
  'নির্ধারিত অনুমোদনকারী ব্যক্তি (named হলে)', 'Named approver people (named mode)', 'Named approver people (used in named mode)',
  'এক বা একাধিক ব্যক্তি; ভূমিকার বদলে বা সঙ্গে', 'One or more people; instead of or together with the role', 17)
on conflict (key) do nothing;

create or replace function public._owner_approver_users() returns uuid[] language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('owner_approver_users');
begin
  if t is null or t = '' then return '{}'; end if;
  return coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(t::jsonb) x), '{}');
exception when others then return '{}';
end $$;

-- the setting itself may only change through the setter (keeps the legacy switch in step), like the two phase80 rules
create or replace function public._rules_mode_guard80() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key in ('owner_approval_mode', 'owner_approver_role', 'owner_approver_users')
     and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos80.setting', true), '') <> '1' then raise exception 'use owner_approval_mode_set'; end if;
  return new;
end $$;

create or replace function public.owner_approval_mode() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'approver_role', public.rule_txt('owner_approver_role'), 'approver_users', to_jsonb(public._owner_approver_users()),
    'owner_self_approve', public.rule_on('owner_self_approve'));
end $$;

create or replace function public.owner_approval_mode_set2(p_mode text, p_role text default null, p_users uuid[] default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); old_u uuid[] := public._owner_approver_users();
  rl text := nullif(btrim(coalesce(p_role, '')), ''); us uuid[]; u uuid; clr boolean := btrim(coalesce(p_role, '')) = '-';
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if clr then rl := null; end if;                                                         -- role '-' = no role, people only
  us := coalesce(p_users, old_u);                                                         -- null = keep, empty array = clear
  foreach u in array us loop
    if u = auth.uid() then raise exception 'owner_cannot_be_approver'; end if;
    if not exists (select 1 from public.profiles where id = u and status = 'active') then raise exception 'unknown_user'; end if;
  end loop;
  if p_mode = 'named' then
    if not clr then rl := coalesce(rl, old_r); end if;
    if rl is null and coalesce(array_length(us, 1), 0) = 0 then raise exception 'data_needed:owner_approver'; end if;
    if rl is not null then
      if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
      if coalesce(array_length(us, 1), 0) = 0 and not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
    end if;
  end if;
  if rl is not null and exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = rl) then raise exception 'owner_holds_approver_role'; end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role';
  elsif clr then update public.rules set value = null, updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  if p_users is not null then update public.rules set value = to_jsonb(to_jsonb(us)::text), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_users'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r, 'users', to_jsonb(old_u)), 'new', jsonb_build_object('mode', p_mode, 'role', case when clr then null else coalesce(rl, old_r) end, 'users', to_jsonb(us)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', case when clr then null else coalesce(rl, old_r) end, 'approver_users', to_jsonb(us), 'owner_self_approve', p_mode <> 'named');
end $$;

-- named mode guard, now with people and with the owner granted one-off approver exception. Decider <> maker always.
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text; ok boolean; eid text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by; eid := new.id::text;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by; eid := new.id::text;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  ok := decider is not null and decider <> maker /* bos86 */
        and ((rl is not null and exists (select 1 from public.user_roles where user_id = decider and role_code = rl)) or decider = any (public._owner_approver_users())) /* bos87 */;
  if not ok then
    if decider is not null and decider <> maker and public._m_grant_take('approver', 'owner_named', null, null, null, current_date, tg_table_name || ':' || eid) then return new; end if;
    raise exception 'named_approver_only';
  end if;
  return new;
end $$;

-- ---------- per individual entry ----------
create table if not exists public.entry_approvers (
  entry_id uuid primary key references public.entries(id),
  approver_user uuid, approver_role text,
  set_by uuid, set_at timestamptz not null default now(), reason text,
  check (approver_user is not null or approver_role is not null)
);
alter table public.entry_approvers enable row level security;
revoke all on public.entry_approvers from public, anon, authenticated;
drop trigger if exists entry_approvers_nodel on public.entry_approvers;
create trigger entry_approvers_nodel before delete on public.entry_approvers for each row execute function public.no_hard_delete();
drop trigger if exists audit_entry_approvers on public.entry_approvers;
create trigger audit_entry_approvers after insert or update on public.entry_approvers for each row execute function public.log_change('entry_id');
drop policy if exists entry_approvers_read on public.entry_approvers;
create policy entry_approvers_read on public.entry_approvers for select to authenticated using (public.is_owner() or approver_user = auth.uid()
  or exists (select 1 from public.entries e where e.id = entry_id and e.created_by = auth.uid()));
grant select on public.entry_approvers to authenticated;

create or replace function public._entry_approver_apply(p_entry uuid, p_user uuid, p_role text, p_reason text, p_by uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.entries; old_ public.entry_approvers;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not found'; end if;
  if e.status in ('approved', 'rejected') then raise exception 'entry_decided'; end if;
  if p_user is null and nullif(btrim(coalesce(p_role, '')), '') is null then raise exception 'approver_required'; end if;
  if p_user is not null then
    if p_user = e.created_by then raise exception 'approver_is_maker'; end if;
    if not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  if nullif(btrim(coalesce(p_role, '')), '') is not null and not exists (select 1 from public.roles where code = btrim(p_role) and active) then raise exception 'bad_role'; end if;
  select * into old_ from public.entry_approvers where entry_id = p_entry;
  insert into public.entry_approvers (entry_id, approver_user, approver_role, set_by, set_at, reason) values (p_entry, p_user, nullif(btrim(coalesce(p_role, '')), ''), p_by, now(), left(p_reason, 300))
    on conflict (entry_id) do update set approver_user = excluded.approver_user, approver_role = excluded.approver_role, set_by = excluded.set_by, set_at = now(), reason = excluded.reason;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (p_by, (select staff_id from public.profiles where id = p_by), 'entry_approver_set', 'entries', p_entry::text,
      jsonb_build_object('old', case when old_.entry_id is not null then jsonb_build_object('user', old_.approver_user, 'role', old_.approver_role) end,
                         'new', jsonb_build_object('user', p_user, 'role', nullif(btrim(coalesce(p_role, '')), '')), 'reason', left(p_reason, 300)));
end $$;

create or replace function public.entry_approver_set(p_entry uuid, p_user uuid default null, p_role text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries;
begin
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  perform public._entry_approver_apply(p_entry, p_user, p_role, p_reason, auth.uid());
  return jsonb_build_object('entry_id', p_entry, 'approver_user', p_user, 'approver_role', nullif(btrim(coalesce(p_role, '')), ''));
end $$;

-- choosing the approver at entry time: the form data may carry approver_user / approver_role
create or replace function public._entry_approver_sync() returns trigger language plpgsql security definer set search_path = public as $$
declare u uuid; r text; cur public.entry_approvers;
begin
  u := case when new.data ->> 'approver_user' ~ '^[0-9a-fA-F-]{36}$' then (new.data ->> 'approver_user')::uuid end;
  r := nullif(btrim(coalesce(new.data ->> 'approver_role', '')), '');
  if u is null and r is null then return null; end if;
  select * into cur from public.entry_approvers where entry_id = new.id;
  if found and cur.approver_user is not distinct from u and cur.approver_role is not distinct from r then return null; end if;
  perform public._entry_approver_apply(new.id, u, r, 'chosen at entry', coalesce(auth.uid(), new.created_by));
  return null;
end $$;
drop trigger if exists aa87_entry_approver_sync on public.entries;
create trigger aa87_entry_approver_sync after insert or update of data on public.entries for each row
  when (new.data ? 'approver_user' or new.data ? 'approver_role') execute function public._entry_approver_sync();

-- a designated approver (person or role) must be the one who decides that entry (never the maker); the owner can re-designate at any time or grant a one-off exception
create or replace function public._entry_approver_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare d public.entry_approvers; maker uuid; decider uuid; eid uuid; ok boolean;
begin
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by; eid := new.id;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by; eid := new.entry_id;
  end if;
  select * into d from public.entry_approvers where entry_id = eid;
  if not found then return new; end if;
  ok := decider is not null and decider <> maker and (decider = d.approver_user or (d.approver_role is not null and exists (select 1 from public.user_roles where user_id = decider and role_code = d.approver_role)));
  if not ok then
    if decider is not null and decider <> maker and public._m_grant_take('approver', 'entry_approver', null, null, null, current_date, 'entries:' || eid::text) then return new; end if;
    raise exception 'designated_approver_only';
  end if;
  return new;
end $$;
drop trigger if exists entries_approver_guard87 on public.entries;
create trigger entries_approver_guard87 before update on public.entries for each row execute function public._entry_approver_guard();
drop trigger if exists ecr_approver_guard87 on public.entry_change_requests;
create trigger ecr_approver_guard87 before update on public.entry_change_requests for each row execute function public._entry_approver_guard();

-- ============================================================================
-- PART H: privileges. Internals closed to browsers; the API checks its own permission.
-- ============================================================================
revoke all on function public._m_patch(regprocedure, text[]), public._p87_present(), public._m_id(text), public._m_key(bigint, text), public._m_mode_of_kind(text), public._m_mode(text), public._m_name(bigint),
  public._m_untag(text), public._m_linked_types(), public._m_voucher_total(jsonb), public._m_journal_bal(bigint, date), public._m_is_generic(bigint), public._m_accounting_ready(),
  public._m_src(bigint), public._m_reg(bigint), public._m_prove(bigint), public._m_grant_take(text, text, uuid, bigint, numeric, date, text), public._m_neg_check(bigint, numeric, text, uuid, date, text),
  public._m_event(text, jsonb), public._m_dir(text, jsonb), public._m_amount(text, jsonb), public._m_date(text, jsonb), public._m_src_bi(), public._m_src_bu(), public._m_entries_bi(),
  public._m_lock_exc(date), public._m_transfer_core(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid, bigint), public._m_docs(date), public._m_daybook_rows(int[], date, date),
  public._m_csv(text), public._m_book(bigint, date), public._m_balance_check(date), public._m_opening_line(jsonb), public._m_opening_mark(jsonb),
  public._owner_approver_users(), public._rules_mode_guard80(), public._owner_named_guard(), public._entry_approver_apply(uuid, uuid, text, text, uuid), public._entry_approver_sync(), public._entry_approver_guard()
  from public, anon, authenticated;
revoke all on function public.money_account_add(text, text, text, text, text, text, int, text, numeric, date, text, text), public.money_account_update(bigint, text, text, text, text, text, text, int, text),
  public.money_account_set_active(bigint, boolean, text), public.money_accounts_list(date), public.money_pick(text, int), public.money_event_settings_list(),
  public.money_event_setting_set(text, bigint, boolean, boolean, boolean), public.money_exception_grant(text, text, uuid, uuid, text, bigint, numeric, date, int), public.money_exception_revoke(bigint, text),
  public.money_exceptions_list(text, int), public.money_exception_resolve(bigint, text), public.money_transfer_add(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid),
  public.money_transfer_void(bigint, text), public.money_charge_add(bigint, text, numeric, date, text, text, int, uuid), public.money_charge_void(bigint, text),
  public.money_recurring_add(text, bigint, bigint, numeric, int, date, date, numeric, text, int), public.money_recurring_set_active(bigint, boolean), public.money_recurring_list(), public.money_recurring_run(date),
  public.money_statement(bigint, date, date, int, int), public.money_statement_csv(bigint, date, date, int), public.money_summary(date, date, int), public.money_check_save(bigint, date, numeric, uuid),
  public.money_check_explain(bigint, text), public.money_checks_list(bigint, int), public.money_statements(date, date, int), public.money_salary_sources(date, date, int), public.money_opening_json(),
  public.owner_approval_mode(), public.owner_approval_mode_set2(text, text, uuid[], text), public.entry_approver_set(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.money_account_add(text, text, text, text, text, text, int, text, numeric, date, text, text), public.money_account_update(bigint, text, text, text, text, text, text, int, text),
  public.money_account_set_active(bigint, boolean, text), public.money_accounts_list(date), public.money_pick(text, int), public.money_event_settings_list(),
  public.money_event_setting_set(text, bigint, boolean, boolean, boolean), public.money_exception_grant(text, text, uuid, uuid, text, bigint, numeric, date, int), public.money_exception_revoke(bigint, text),
  public.money_exceptions_list(text, int), public.money_exception_resolve(bigint, text), public.money_transfer_add(bigint, bigint, numeric, date, numeric, text, text, text, int, uuid),
  public.money_transfer_void(bigint, text), public.money_charge_add(bigint, text, numeric, date, text, text, int, uuid), public.money_charge_void(bigint, text),
  public.money_recurring_add(text, bigint, bigint, numeric, int, date, date, numeric, text, int), public.money_recurring_set_active(bigint, boolean), public.money_recurring_list(), public.money_recurring_run(date),
  public.money_statement(bigint, date, date, int, int), public.money_statement_csv(bigint, date, date, int), public.money_summary(date, date, int), public.money_check_save(bigint, date, numeric, uuid),
  public.money_check_explain(bigint, text), public.money_checks_list(bigint, int), public.money_statements(date, date, int), public.money_salary_sources(date, date, int), public.money_opening_json(),
  public.owner_approval_mode(), public.owner_approval_mode_set2(text, text, uuid[], text), public.entry_approver_set(uuid, uuid, text, text) to authenticated;

-- ===================== phase88.sql =====================
-- Phase 88 (bos88) - OPENING DUES AND PAYABLES LINKED TO THE CUSTOMER AND SUPPLIER SUB-LEDGERS (plan item U-01, package W1-A).
-- Paste AFTER phase87. Paste-twice safe. Earlier phase files are not edited. Nothing in an existing function is changed by THIS file (see "HOOKS" below).
--
-- THE PROBLEM
--   An old customer due (owed before go-live) is in the books (phase80 opening journal: Dr receivable with the customer as party) but NOT in the customer sub-ledger:
--   collect_payment raises "overpaid", the POS credit limit ignores the old due, the dues list does not show it. A supplier opening has to be typed twice
--   (suppliers.opening_balance for the sub-ledger, and again in the opening JSON for the books).
-- WHAT THIS FILE ADDS (all new objects, own prefix _w1a_ / w1a_)
--   customers.opening_balance / opening_date, suppliers.opening_date (suppliers.opening_balance already exists and is already part of _sup_balance)
--   three SETTINGS (rules, module books, safe defaults = today's behaviour, editable by the owner at any time, every change is an audit_log line through audit_rules):
--     open_parties_link         switch  OFF   ON = the typed opening due is part of the customer balance (credit limit, collect, dues list, ledger) and opening_balance_post fills it
--     open_parties_freeze       choice  off   after_opening = once the opening batch is posted a direct change of an opening figure is refused; the way is an adjustment with a reason
--     open_parties_adjust_mode  choice  direct   direct = a holder of Accounts manage adjusts with a reason; approval = a second person decides (the owner's own request follows
--                                               the owner approval setting of phase80/87: self, logged, off or named approvers; nothing is hard-coded)
--   w1a_open_state / w1a_open_list (list with the DIFFERENCE column: books minus sub-ledger) / w1a_open_set / w1a_open_import (paste import, dry run first, all or nothing)
--   w1a_open_json (the customer_dues and supplier_dues sections for the opening screen, from what was typed once) / w1a_open_precheck / w1a_open_from_journal (fill from an
--   opening batch that was posted before this phase) / w1a_open_adjust + w1a_open_adjust_decide + w1a_open_adjust_list (change after the opening: reason required, balanced
--   adjustment journal, one audit_log line, one row in the Exceptions list) / w1a_party_gate (per party: sub-ledger equals general ledger, wraps acct_reconcile and names the cause)
--   _w1a_cust_open / _w1a_opening_apply (the pieces the hooks call) / _w1a_patch (exact-text patch helper with a marker parameter, see below)
-- EXCEPTIONS: every adjustment and every frozen change needs a written reason (min 3 characters), writes audit_log and a row in the Exceptions list (exceptions, flag opening_adjusted).
--   Nothing here is tied to a person or to a role: permission is the existing Accounts manage grant (_acct_manage), the approver of the owner's own request is read from the
--   owner approval setting. Nothing is deleted.
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner turns a setting on: all three defaults keep today's behaviour and the new columns are empty.
--
-- HOOKS (the integrator pastes them in phase99; the exact text is in docs/integration/W1-A.md and in tests/sql/phase88_hooks.sql). This file does NOT patch a shared function.
--   _cust_bal, customer_dues, customer_ledger : read _w1a_cust_open(customer)  (0 while open_parties_link is OFF)
--   opening_balance_post                      : perform _w1a_opening_apply(p_json) after the journal entry
--   !! _m_patch of phase87 cannot patch opening_balance_post again (it stops when the marker bos87 is already inside). Use _w1a_patch (marker bos88).
--   !! Re-pasting phase 6, 12, 80 or 87 removes the hooks: paste the hook file again.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase88 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.opening_balance_post(jsonb,uuid,boolean,boolean)') is null or to_regprocedure('public.acct_reconcile(text)') is null
     or to_regprocedure('public._cust_bal(uuid)') is null or to_regprocedure('public._sup_balance(uuid)') is null or to_regprocedure('public.customer_dues()') is null
     or to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is null or to_regprocedure('public._owner_approver_users()') is null then
    raise exception 'phase88 needs the shared functions of phases 6, 12, 40, 80, 87';
  end if;
end $g$;

create or replace function public._p88_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic exact-text patch helper with its OWN marker (phase87 _m_patch is hard-wired to bos87 and cannot patch a function that already carries bos87) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed). Marker already inside = no-op (returns false).
create or replace function public._w1a_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bos88') returns boolean language plpgsql set search_path = public as $$
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

-- ---------- columns ----------
alter table public.customers add column if not exists opening_balance numeric;
alter table public.customers add column if not exists opening_date date;
alter table public.suppliers add column if not exists opening_date date;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_opening_balance_chk') then
    alter table public.customers add constraint customers_opening_balance_chk check (opening_balance is null or (opening_balance >= 0 and opening_balance <= 1000000000000));
  end if;
end $c$;

-- ---------- settings (rules). Bangla later: the Bangla column carries the English text for now. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('open_parties_link', 'books', 'switch', 'false', null, null, null, null,
  'Count opening dues in customer balances', 'Count opening dues in customer balances', 'Count opening dues in customer balances',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.',
  'OFF = as today: a customer balance is built only from sales, collections and returns. ON = the opening due typed in Opening dues and payables is added to the balance, the credit limit check, the dues list and the ledger, and can be collected.', 150),
 ('open_parties_freeze', 'books', 'choice', '"off"', null, '["off","after_opening"]', null, null,
  'Lock opening dues after the opening batch', 'Lock opening dues after the opening batch', 'Lock opening dues after the opening batch',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.',
  'off = changes are allowed as today. after_opening = once the opening batch is posted, a direct change of an opening due or payable is refused; use an adjustment with a reason instead.', 151),
 ('open_parties_adjust_mode', 'books', 'choice', '"direct"', null, '["direct","approval"]', null, null,
  'Who decides a change of an opening due', 'Who decides a change of an opening due', 'Who decides a change of an opening due',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.',
  'direct = a holder of Accounts manage makes the change with a written reason. approval = a second person with Accounts manage decides; the owner''s own request follows the owner approval setting.', 152)
on conflict (key) do nothing;

-- ---------- small helpers ----------
-- who may type, import and adjust openings: a holder of Accounts manage (owner or delegated) who works company-wide (an opening is a company figure, not a place figure)
create or replace function public._w1a_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public._acct_manage() and public._acct_all() $$;
create or replace function public._w1a_batch_exists() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.opening_batches) $$;
create or replace function public._w1a_frozen() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('open_parties_freeze'), 'off') = 'after_opening' and public._w1a_batch_exists() $$;

-- what a customer's opening due adds to the balance. 0 while the switch is OFF, and 0 before the opening date.
create or replace function public._w1a_cust_open(p_customer uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when public.rule_on('open_parties_link')
              then coalesce((select c.opening_balance from public.customers c where c.id = p_customer and (c.opening_date is null or c.opening_date <= (now() at time zone 'Asia/Dhaka')::date)), 0)
              else 0 end $$;
create or replace function public._w1a_cust_open_date(p_customer uuid) returns date language sql stable security definer set search_path = public as $$
  select coalesce(c.opening_date, public._acct_start()) from public.customers c where c.id = p_customer $$;
create or replace function public._w1a_cust_open_at(p_customer uuid) returns timestamptz language sql stable security definer set search_path = public as $$
  select (coalesce((select c.opening_date from public.customers c where c.id = p_customer), public._acct_start(), (now() at time zone 'Asia/Dhaka')::date)::timestamp at time zone 'Asia/Dhaka') $$;

create or replace function public._w1a_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail);
end $$;

-- one row in the Exceptions list (public.exceptions, shown in #/exceptions to the owner and to approvers)
create or replace function public._w1a_exc(p_flag text, p_level text, p_amount numeric, p_en text, p_bn text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, 'ACC', (select min(id) from public.locations), (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, p_amount, jsonb_build_object('bn', p_bn, 'en', p_en));
end $$;

-- ---------- freeze: a direct change of an opening figure after the opening batch (only while open_parties_freeze = after_opening) ----------
create or replace function public._w1a_open_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if new.opening_balance is not distinct from old.opening_balance and new.opening_date is not distinct from old.opening_date then return new; end if;
  else
    if coalesce(new.opening_balance, 0) = 0 then return new; end if;
  end if;
  if coalesce(current_setting('bos88.api', true), '') = '1' then return new; end if;      -- our own functions (they carry their own reason, audit and exception)
  if public._w1a_frozen() then raise exception 'opening_frozen'; end if;
  return new;
end $$;
drop trigger if exists customers_open_guard88 on public.customers;
create trigger customers_open_guard88 before insert or update of opening_balance, opening_date on public.customers for each row execute function public._w1a_open_guard();
drop trigger if exists suppliers_open_guard88 on public.suppliers;
create trigger suppliers_open_guard88 before insert or update of opening_balance, opening_date on public.suppliers for each row execute function public._w1a_open_guard();

-- ---------- adjustments (append only, decided once) ----------
create table if not exists public.open_party_adjustments (
  id bigserial primary key,
  client_id uuid unique,
  kind text not null check (kind in ('customer', 'supplier')),
  party_id uuid not null,
  party_name text,
  old_amount numeric not null,
  new_amount numeric not null,
  delta numeric not null check (delta <> 0),
  reason text not null check (length(btrim(reason)) >= 3),
  mode text not null default 'direct' check (mode in ('direct', 'approval')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_by uuid, requested_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz, decision_note text,
  journal_entry_id bigint
);
create unique index if not exists open_party_adjustments_one_pending on public.open_party_adjustments (kind, party_id) where status = 'pending';
do $t$ begin
  drop trigger if exists open_party_adjustments_nodel on public.open_party_adjustments;
  create trigger open_party_adjustments_nodel before delete on public.open_party_adjustments for each row execute function public.no_hard_delete();
  drop trigger if exists audit_open_party_adjustments on public.open_party_adjustments;
  create trigger audit_open_party_adjustments after insert or update on public.open_party_adjustments for each row execute function public.log_change('id');
  alter table public.open_party_adjustments enable row level security;
  revoke all on public.open_party_adjustments from public, anon, authenticated;
  drop policy if exists open_party_adjustments_read on public.open_party_adjustments;
  create policy open_party_adjustments_read on public.open_party_adjustments for select to authenticated using (public._acct_view());
  grant select on public.open_party_adjustments to authenticated;
  revoke all on sequence public.open_party_adjustments_id_seq from public, anon, authenticated;
end $t$;

-- ============================================================================
-- STATE and LIST
-- ============================================================================
create or replace function public.w1a_open_state() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare b record;
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  select id, at into b from public.opening_batches order by id limit 1;
  return jsonb_build_object(
    'link', public.rule_on('open_parties_link'), 'freeze', coalesce(public.rule_txt('open_parties_freeze'), 'off'), 'adjust_mode', coalesce(public.rule_txt('open_parties_adjust_mode'), 'direct'),
    'batch_exists', b.id is not null, 'batch_at', b.at, 'frozen', public._w1a_frozen(), 'accounting_start', public._acct_start(),
    'can_manage', public._w1a_mgr(), 'is_owner', public.is_owner(), 'all_places', public._acct_all(),
    'customers_typed', (select count(*) from public.customers where coalesce(opening_balance, 0) <> 0),
    'customers_typed_total', (select coalesce(sum(opening_balance), 0) from public.customers where coalesce(opening_balance, 0) <> 0),
    'suppliers_typed', (select count(*) from public.suppliers where coalesce(opening_balance, 0) <> 0),
    'suppliers_typed_total', (select coalesce(sum(opening_balance), 0) from public.suppliers where coalesce(opening_balance, 0) <> 0),
    'pending_adjustments', (select count(*) from public.open_party_adjustments where status = 'pending'));
end $$;

-- the list, with the difference column: general ledger (journal, by party) minus the sub-ledger balance. A row with a difference is a party whose books and sub-ledger disagree.
create or replace function public.w1a_open_list(p_kind text, p_search text default null, p_only text default 'all', p_limit int default 300, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ar bigint; ap bigint; lim int := least(greatest(coalesce(p_limit, 300), 1), 1000); off_ int := greatest(coalesce(p_offset, 0), 0); s text := nullif(btrim(coalesce(p_search, '')), ''); res jsonb; mg boolean := public._w1a_mgr();
begin
  if not (public._acct_view() and public._acct_all()) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_only is null or p_only not in ('all', 'opening', 'diff') then raise exception 'bad_value'; end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  if p_kind = 'customer' then
    with j as (
      select l.party_id pid, sum(l.debit - l.credit) gl,
             coalesce(sum(l.debit - l.credit) filter (where e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening')), 0) jo
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = ar and l.party_type = 'customer' group by 1),
    b as (
      select c.id, c.name, c.mobile, c.active, c.opening_balance, c.opening_date, coalesce(j.gl, 0) gl, coalesce(j.jo, 0) jo
        from public.customers c left join j on j.pid = c.id::text
       where (s is null or position(lower(s) in lower(c.name)) > 0 or position(s in c.mobile) > 0)
         and (p_only <> 'opening' or coalesce(c.opening_balance, 0) <> 0 or coalesce(j.jo, 0) <> 0)
       order by lower(c.name), c.id
       limit case when p_only = 'diff' then null else lim + 1 end offset case when p_only = 'diff' then 0 else off_ end),
    d as (select b.*, public._cust_bal(b.id) sub from b),
    f as (select d.*, round(d.gl - d.sub, 2) df from d where p_only <> 'diff' or abs(d.gl - d.sub) > 0.005 order by case when p_only = 'diff' then abs(d.gl - d.sub) end desc nulls last, lower(d.name), d.id
          limit lim + 1 offset case when p_only = 'diff' then off_ else 0 end)
    select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'mobile', case when mg then f.mobile end, 'active', f.active, 'opening', f.opening_balance, 'opening_date', f.opening_date,
             'journal_opening', f.jo, 'journal_balance', f.gl, 'subledger_balance', f.sub, 'difference', f.df) order by case when p_only = 'diff' then abs(f.df) end desc nulls last, lower(f.name), f.id) filter (where f.rn <= lim), '[]'::jsonb),
           'has_more', coalesce(bool_or(f.rn > lim), false))
      into res from (select f0.*, row_number() over (order by case when p_only = 'diff' then abs(f0.df) end desc nulls last, lower(f0.name), f0.id) rn from f f0) f;
  else
    with j as (
      select l.party_id pid, sum(l.credit - l.debit) gl,
             coalesce(sum(l.credit - l.debit) filter (where e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening')), 0) jo
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
       where l.account_id = ap and l.party_type = 'supplier' group by 1),
    b as (
      select c.id, c.name, c.mobile, c.active, c.opening_balance, c.opening_date, coalesce(j.gl, 0) gl, coalesce(j.jo, 0) jo
        from public.suppliers c left join j on j.pid = c.id::text
       where (s is null or position(lower(s) in lower(c.name)) > 0 or position(s in coalesce(c.mobile, '')) > 0)
         and (p_only <> 'opening' or coalesce(c.opening_balance, 0) <> 0 or coalesce(j.jo, 0) <> 0)
       order by lower(c.name), c.id
       limit case when p_only = 'diff' then null else lim + 1 end offset case when p_only = 'diff' then 0 else off_ end),
    d as (select b.*, public._sup_balance(b.id) sub from b),
    f as (select d.*, round(d.gl - d.sub, 2) df from d where p_only <> 'diff' or abs(d.gl - d.sub) > 0.005 order by case when p_only = 'diff' then abs(d.gl - d.sub) end desc nulls last, lower(d.name), d.id
          limit lim + 1 offset case when p_only = 'diff' then off_ else 0 end)
    select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'mobile', case when mg then f.mobile end, 'active', f.active, 'opening', f.opening_balance, 'opening_date', f.opening_date,
             'journal_opening', f.jo, 'journal_balance', f.gl, 'subledger_balance', f.sub, 'difference', f.df) order by case when p_only = 'diff' then abs(f.df) end desc nulls last, lower(f.name), f.id) filter (where f.rn <= lim), '[]'::jsonb),
           'has_more', coalesce(bool_or(f.rn > lim), false))
      into res from (select f0.*, row_number() over (order by case when p_only = 'diff' then abs(f0.df) end desc nulls last, lower(f0.name), f0.id) rn from f f0) f;
  end if;
  return res || jsonb_build_object('kind', p_kind, 'link', public.rule_on('open_parties_link'), 'frozen', public._w1a_frozen());
end $$;

-- ============================================================================
-- STAGING: type the opening once (before the opening batch). One party, or a paste import.
-- ============================================================================
create or replace function public.w1a_open_set(p_kind text, p_party uuid, p_amount numeric, p_date date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ numeric; old_d date; amt numeric; nm text;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if public._w1a_batch_exists() then raise exception 'opening_posted_use_adjust'; end if;
  if p_amount is not null and (p_amount = 'NaN'::numeric or abs(p_amount) > 1000000000000) then raise exception 'bad_amount'; end if;
  if p_kind = 'customer' and p_amount < 0 then raise exception 'negative_not_allowed'; end if;
  amt := nullif(round(coalesce(p_amount, 0), 2), 0);
  if p_kind = 'customer' then
    select opening_balance, opening_date, name into old_, old_d, nm from public.customers where id = p_party for update;
  else
    select opening_balance, opening_date, name into old_, old_d, nm from public.suppliers where id = p_party for update;
  end if;
  if not found then raise exception 'unknown_party'; end if;
  perform set_config('bos88.api', '1', true);
  if p_kind = 'customer' then update public.customers set opening_balance = amt, opening_date = coalesce(p_date, opening_date) where id = p_party;
  else update public.suppliers set opening_balance = amt, opening_date = coalesce(p_date, opening_date) where id = p_party; end if;
  perform set_config('bos88.api', '', true);
  perform public._w1a_audit('open_party_set', case p_kind when 'customer' then 'customers' else 'suppliers' end, p_party::text,
    jsonb_build_object('name', nm, 'old', old_, 'new', amt, 'old_date', old_d, 'new_date', coalesce(p_date, old_d), 'note', left(p_note, 200)));
  return jsonb_build_object('kind', p_kind, 'party_id', p_party, 'old', old_, 'new', amt);
end $$;

-- paste import. p_rows: [{party_id | mobile | name, amount, date?, name?}]. Dry run (default) writes nothing. A real run is ALL OR NOTHING: one bad row refuses the whole file.
-- Customers that do not exist yet can be created (p_create, needs mobile and name); suppliers are never created here.
create or replace function public.w1a_open_import(p_kind text, p_rows jsonb, p_dry boolean default true, p_create boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare x jsonb; i int := 0; out_ jsonb := '[]'::jsonb; todo jsonb := '[]'::jsonb; n_ok int := 0; n_same int := 0; n_err int := 0; n_new int := 0; tot numeric := 0;
  pid uuid; st text; txt text; amt numeric; dt date; dg text; cnt int; old_ numeric; old_d date; nm text; seen uuid[] := '{}'; mob text; create_ boolean; t jsonb;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if public._w1a_batch_exists() then raise exception 'opening_posted_use_adjust'; end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; st := null; pid := null; amt := null; dt := null; old_ := null; old_d := null; nm := null; create_ := false; mob := null;
    begin
      if jsonb_typeof(x) <> 'object' then st := 'bad_row'; end if;
      -- amount
      if st is null then
        txt := replace(translate(coalesce(x ->> 'amount', ''), '০১২৩৪৫৬৭৮৯', '0123456789'), ',', '');
        if txt = '' then txt := '0'; end if;
        if txt !~ '^-?[0-9]{1,12}(\.[0-9]{1,2})?$' then st := 'bad_amount'; else amt := txt::numeric; end if;
        if st is null and p_kind = 'customer' and amt < 0 then st := 'negative_not_allowed'; end if;
      end if;
      if st is null and nullif(x ->> 'date', '') is not null then
        if (x ->> 'date') !~ '^\d{4}-\d{2}-\d{2}$' then st := 'bad_date'; else begin dt := (x ->> 'date')::date; exception when others then st := 'bad_date'; end; end if;
      end if;
      -- which party
      if st is null then
        if nullif(x ->> 'party_id', '') is not null then
          if (x ->> 'party_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then st := 'unknown_party';
          else
            pid := (x ->> 'party_id')::uuid;
            if p_kind = 'customer' then select count(*) into cnt from public.customers where id = pid; else select count(*) into cnt from public.suppliers where id = pid; end if;
            if cnt = 0 then st := 'unknown_party'; pid := null; end if;
          end if;
        elsif nullif(x ->> 'mobile', '') is not null then
          mob := right(regexp_replace(translate(x ->> 'mobile', '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9]', '', 'g'), 10);
          if length(mob) <> 10 then st := 'bad_mobile';
          else
            if p_kind = 'customer' then select count(*), min(id::text)::uuid into cnt, pid from public.customers where right(regexp_replace(mobile, '[^0-9]', '', 'g'), 10) = mob;
            else select count(*), min(id::text)::uuid into cnt, pid from public.suppliers where right(regexp_replace(coalesce(mobile, ''), '[^0-9]', '', 'g'), 10) = mob; end if;
            if cnt > 1 then st := 'ambiguous_party'; pid := null;
            elsif cnt = 0 then
              pid := null;
              if p_kind = 'customer' and p_create and nullif(btrim(coalesce(x ->> 'name', '')), '') is not null then create_ := true; else st := 'unknown_party'; end if;
            end if;
          end if;
        elsif nullif(btrim(coalesce(x ->> 'name', '')), '') is not null then
          if p_kind = 'customer' then select count(*), min(id::text)::uuid into cnt, pid from public.customers where lower(btrim(name)) = lower(btrim(x ->> 'name'));
          else select count(*), min(id::text)::uuid into cnt, pid from public.suppliers where lower(btrim(name)) = lower(btrim(x ->> 'name')); end if;
          if cnt > 1 then st := 'ambiguous_party'; pid := null; elsif cnt = 0 then st := 'unknown_party'; pid := null; end if;
        else st := 'party_missing'; end if;
      end if;
      if st is null and pid is not null then
        if pid = any (seen) then st := 'duplicate_row'; else seen := seen || pid; end if;
      end if;
      if st is null and pid is not null then
        if p_kind = 'customer' then select opening_balance, opening_date, name into old_, old_d, nm from public.customers where id = pid;
        else select opening_balance, opening_date, name into old_, old_d, nm from public.suppliers where id = pid; end if;
        if coalesce(old_, 0) = coalesce(amt, 0) and (dt is null or old_d is not distinct from dt) then st := 'same'; n_same := n_same + 1;
        else st := 'ok'; n_ok := n_ok + 1; tot := tot + coalesce(amt, 0); todo := todo || jsonb_build_object('party', pid, 'amount', amt, 'date', dt); end if;
      elsif st is null and create_ then
        st := 'will_create'; n_new := n_new + 1; nm := left(btrim(x ->> 'name'), 80); tot := tot + coalesce(amt, 0);
        todo := todo || jsonb_build_object('create', true, 'mobile', x ->> 'mobile', 'name', nm, 'amount', amt, 'date', dt);
      end if;
    exception when others then st := 'bad_row'; end;
    if st not in ('ok', 'same', 'will_create') then n_err := n_err + 1; end if;
    out_ := out_ || jsonb_build_object('i', i, 'status', st, 'party_id', pid, 'name', coalesce(nm, left(x ->> 'name', 80)), 'old', old_, 'new', amt);
  end loop;
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'rows', out_, 'ok', n_ok, 'same', n_same, 'create', n_new, 'errors', n_err, 'total_new', tot);
  end if;
  if n_err > 0 then raise exception 'import_has_errors' using detail = n_err::text || ' row(s) are not valid: nothing was written'; end if;
  perform set_config('bos88.api', '1', true);
  for t in select * from jsonb_array_elements(todo) loop
    if (t ->> 'create') = 'true' then
      -- a customer who has never bought here (an old due owed from before go-live)
      begin mob := public.norm_mobile(t ->> 'mobile'); exception when others then raise exception 'bad_mobile'; end;
      insert into public.customers (mobile, name, type, created_by, opening_balance, opening_date)
        values (mob, t ->> 'name', 'retail', auth.uid(), nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), (t ->> 'date')::date)
        on conflict (mobile) do update set opening_balance = excluded.opening_balance, opening_date = coalesce(excluded.opening_date, public.customers.opening_date);
    elsif p_kind = 'customer' then
      update public.customers set opening_balance = nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), opening_date = coalesce((t ->> 'date')::date, opening_date) where id = (t ->> 'party')::uuid;
    else
      update public.suppliers set opening_balance = nullif(round(coalesce((t ->> 'amount')::numeric, 0), 2), 0), opening_date = coalesce((t ->> 'date')::date, opening_date) where id = (t ->> 'party')::uuid;
    end if;
  end loop;
  perform set_config('bos88.api', '', true);
  perform public._w1a_audit('open_party_import', case p_kind when 'customer' then 'customers' else 'suppliers' end, null,
    jsonb_build_object('kind', p_kind, 'rows', jsonb_array_length(p_rows), 'changed', n_ok, 'created', n_new, 'unchanged', n_same, 'total_new', tot));
  return jsonb_build_object('dry', false, 'kind', p_kind, 'changed', n_ok, 'created', n_new, 'unchanged', n_same, 'total_new', tot);
end $$;

-- ============================================================================
-- THE OPENING SCREEN: the customer_dues and supplier_dues sections come from what was typed once
-- ============================================================================
create or replace function public.w1a_open_json() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if public._w1a_batch_exists() then return jsonb_build_object('batch_exists', true, 'customer_dues', '[]'::jsonb, 'supplier_dues', '[]'::jsonb, 'not_postable', '[]'::jsonb); end if;
  return jsonb_build_object('batch_exists', false,
    'customer_dues', coalesce((select jsonb_agg(jsonb_build_object('customer_id', c.id, 'amount', c.opening_balance::text) order by c.id) from public.customers c where coalesce(c.opening_balance, 0) > 0), '[]'::jsonb),
    'supplier_dues', coalesce((select jsonb_agg(jsonb_build_object('supplier_id', s.id, 'amount', s.opening_balance::text) order by s.id) from public.suppliers s where coalesce(s.opening_balance, 0) > 0), '[]'::jsonb),
    'not_postable', coalesce((select jsonb_agg(jsonb_build_object('kind', 'supplier', 'party_id', s.id, 'name', s.name, 'amount', s.opening_balance, 'why', 'a supplier who owes us (negative opening) cannot go in the supplier_dues section: enter it after the opening as an adjustment')
                                order by s.id) from public.suppliers s where coalesce(s.opening_balance, 0) < 0), '[]'::jsonb));
end $$;

-- compare an opening JSON with what is typed on the parties
create or replace function public.w1a_open_precheck(p_json jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb := '[]'::jsonb; x record;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_json is null or jsonb_typeof(p_json) <> 'object' then raise exception 'bad_payload'; end if;
  for x in
    select 'customer' kind, coalesce(a.pid, b.id::text) pid, c.name, a.amt jamt, coalesce(c.opening_balance, 0) typed
      from (select e ->> 'customer_id' pid, sum((e ->> 'amount')::numeric) amt from jsonb_array_elements(coalesce(p_json -> 'customer_dues', '[]'::jsonb)) e group by 1) a
      full join (select id from public.customers where coalesce(opening_balance, 0) <> 0) b on b.id::text = a.pid
      left join public.customers c on c.id::text = coalesce(a.pid, b.id::text)
    union all
    select 'supplier', coalesce(a.pid, b.id::text), c.name, a.amt, coalesce(c.opening_balance, 0)
      from (select e ->> 'supplier_id' pid, sum((e ->> 'amount')::numeric) amt from jsonb_array_elements(coalesce(p_json -> 'supplier_dues', '[]'::jsonb)) e group by 1) a
      full join (select id from public.suppliers where coalesce(opening_balance, 0) <> 0) b on b.id::text = a.pid
      left join public.suppliers c on c.id::text = coalesce(a.pid, b.id::text)
  loop
    rows_ := rows_ || jsonb_build_object('kind', x.kind, 'party_id', x.pid, 'name', x.name, 'json_amount', x.jamt, 'typed', x.typed,
      'status', case when x.jamt is null then 'typed_not_in_json' when x.typed = 0 then 'not_typed' when x.jamt = x.typed then 'same' else 'differs' end);
  end loop;
  return jsonb_build_object('rows', rows_, 'link', public.rule_on('open_parties_link'),
    'differing', (select count(*) from jsonb_array_elements(rows_) r where r ->> 'status' <> 'same'));
end $$;

-- the piece the opening_balance_post hook calls, inside the same transaction as the journal entry. Does nothing while open_parties_link is OFF.
create or replace function public._w1a_opening_apply(p_json jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x record; st date := public._acct_start(); old_ numeric; nc int := 0; ns int := 0;
begin
  if not public.rule_on('open_parties_link') then return; end if;
  perform set_config('bos88.api', '1', true);
  for x in select (e ->> 'customer_id')::uuid pid, round(sum((e ->> 'amount')::numeric), 2) amt from jsonb_array_elements(coalesce(p_json -> 'customer_dues', '[]'::jsonb)) e group by 1 loop
    select opening_balance into old_ from public.customers where id = x.pid;
    update public.customers set opening_balance = nullif(x.amt, 0), opening_date = coalesce(st, opening_date) where id = x.pid;
    nc := nc + 1;
    if coalesce(old_, 0) <> 0 and old_ <> x.amt then perform public._w1a_audit('open_party_json_override', 'customers', x.pid::text, jsonb_build_object('typed', old_, 'posted', x.amt)); end if;
  end loop;
  for x in select (e ->> 'supplier_id')::uuid pid, round(sum((e ->> 'amount')::numeric), 2) amt from jsonb_array_elements(coalesce(p_json -> 'supplier_dues', '[]'::jsonb)) e group by 1 loop
    select opening_balance into old_ from public.suppliers where id = x.pid;
    update public.suppliers set opening_balance = nullif(x.amt, 0), opening_date = coalesce(st, opening_date) where id = x.pid;
    ns := ns + 1;
    if coalesce(old_, 0) <> 0 and old_ <> x.amt then perform public._w1a_audit('open_party_json_override', 'suppliers', x.pid::text, jsonb_build_object('typed', old_, 'posted', x.amt)); end if;
  end loop;
  perform set_config('bos88.api', '', true);
  if nc + ns > 0 then perform public._w1a_audit('open_party_linked', 'opening_batches', null, jsonb_build_object('customers', nc, 'suppliers', ns)); end if;
end $$;

-- an opening batch posted BEFORE this phase: fill the sub-ledger fields from its journal lines (dry run first; a party that already has a different figure is reported, never overwritten)
create or replace function public.w1a_open_from_journal(p_dry boolean default true) returns jsonb language plpgsql security definer set search_path = public as $$
declare e record; ar bigint; ap bigint; x record; rows_ jsonb := '[]'::jsonb; n_fill int := 0; n_same int := 0; n_conf int := 0; stt text;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  select o.id, o.entry_date into e from public.journal_entries o
   where o.source_type = 'opening' and o.reverses_id is null and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id) order by o.id limit 1;
  if not found then raise exception 'no_opening_posted'; end if;
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  if not p_dry then perform set_config('bos88.api', '1', true); end if;
  for x in
    select 'customer' kind, l.party_id::uuid pid, c.name, c.opening_balance cur, round(sum(l.debit - l.credit), 2) amt
      from public.journal_lines l join public.customers c on c.id::text = l.party_id where l.entry_id = e.id and l.account_id = ar and l.party_type = 'customer' group by l.party_id, c.name, c.opening_balance
    union all
    select 'supplier', l.party_id::uuid, c.name, c.opening_balance, round(sum(l.credit - l.debit), 2)
      from public.journal_lines l join public.suppliers c on c.id::text = l.party_id where l.entry_id = e.id and l.account_id = ap and l.party_type = 'supplier' group by l.party_id, c.name, c.opening_balance
  loop
    continue when x.amt = 0;
    if coalesce(x.cur, 0) = x.amt then stt := 'same'; n_same := n_same + 1;
    elsif coalesce(x.cur, 0) = 0 and not (x.kind = 'customer' and x.amt < 0) then
      stt := 'fill'; n_fill := n_fill + 1;
      if not p_dry then
        if x.kind = 'customer' then update public.customers set opening_balance = x.amt, opening_date = coalesce(opening_date, e.entry_date) where id = x.pid;
        else update public.suppliers set opening_balance = x.amt, opening_date = coalesce(opening_date, e.entry_date) where id = x.pid; end if;
      end if;
    else stt := 'conflict'; n_conf := n_conf + 1; end if;
    rows_ := rows_ || jsonb_build_object('kind', x.kind, 'party_id', x.pid, 'name', x.name, 'typed', x.cur, 'journal', x.amt, 'status', stt);
  end loop;
  if not p_dry then
    perform set_config('bos88.api', '', true);
    if n_fill > 0 then perform public._w1a_audit('open_party_from_journal', 'journal_entries', e.id::text, jsonb_build_object('filled', n_fill, 'same', n_same, 'conflicts', n_conf)); end if;
  end if;
  return jsonb_build_object('dry', p_dry, 'entry_id', e.id, 'rows', rows_, 'filled', n_fill, 'same', n_same, 'conflicts', n_conf);
end $$;

-- ============================================================================
-- CHANGE AFTER THE OPENING: an adjustment with a reason (balanced journal, audit line, Exceptions row)
-- ============================================================================
-- who may decide a request: never the maker, except the owner for his own request while the owner approval setting lets him decide his own entries (self, logged, off).
-- In named mode the named approvers (role or people) decide the owner's request. No role or person is written into this function.
create or replace function public._w1a_may_decide(p_maker uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare owner_maker boolean; rl text; me uuid := auth.uid();
begin
  if me is null or not public._w1a_mgr() then return false; end if;
  owner_maker := exists (select 1 from public.user_roles where user_id = p_maker and role_code = 'owner');
  if owner_maker and public._owner_mode() = 'named' then
    rl := public.rule_txt('owner_approver_role');
    return me <> p_maker and ((rl is not null and exists (select 1 from public.user_roles where user_id = me and role_code = rl)) or me = any (public._owner_approver_users()));
  end if;
  if me = p_maker then return owner_maker; end if;
  return true;
end $$;

create or replace function public._w1a_adj_apply(p_id bigint, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.open_party_adjustments; st date := public._acct_start(); jid bigint; ln jsonb; r jsonb; amt numeric; memo text;
begin
  select * into a from public.open_party_adjustments where id = p_id for update;
  if not found or a.status <> 'pending' then raise exception 'not_pending'; end if;
  amt := abs(a.delta);
  memo := left('Opening ' || a.kind || ' balance adjustment: ' || coalesce(a.party_name, '') || ' - ' || a.reason, 190);
  if st is not null then
    if a.kind = 'customer' then
      ln := case when a.delta > 0
        then jsonb_build_array(jsonb_build_object('a', 'receivable', 'debit', amt, 'party_type', 'customer', 'party_id', a.party_id::text, 'memo', memo), jsonb_build_object('a', 'retained', 'credit', amt, 'memo', memo))
        else jsonb_build_array(jsonb_build_object('a', 'retained', 'debit', amt, 'memo', memo), jsonb_build_object('a', 'receivable', 'credit', amt, 'party_type', 'customer', 'party_id', a.party_id::text, 'memo', memo)) end;
    else
      ln := case when a.delta > 0
        then jsonb_build_array(jsonb_build_object('a', 'retained', 'debit', amt, 'memo', memo), jsonb_build_object('a', 'payable', 'credit', amt, 'party_type', 'supplier', 'party_id', a.party_id::text, 'memo', memo))
        else jsonb_build_array(jsonb_build_object('a', 'payable', 'debit', amt, 'party_type', 'supplier', 'party_id', a.party_id::text, 'memo', memo), jsonb_build_object('a', 'retained', 'credit', amt, 'memo', memo)) end;
    end if;
    r := public.acct_journal_post(greatest(public._acct_today(), st), null, memo, ln, null, null, false);
    jid := (r ->> 'id')::bigint;
  end if;
  perform set_config('bos88.api', '1', true);
  if a.kind = 'customer' then update public.customers set opening_balance = nullif(a.new_amount, 0), opening_date = coalesce(opening_date, st) where id = a.party_id;
  else update public.suppliers set opening_balance = nullif(a.new_amount, 0), opening_date = coalesce(opening_date, st) where id = a.party_id; end if;
  perform set_config('bos88.api', '', true);
  update public.open_party_adjustments set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(coalesce(p_note, '')), 300), journal_entry_id = jid where id = p_id;
  perform public._w1a_audit('open_party_adjust', case a.kind when 'customer' then 'customers' else 'suppliers' end, a.party_id::text,
    jsonb_build_object('adjustment', p_id, 'name', a.party_name, 'old', a.old_amount, 'new', a.new_amount, 'delta', a.delta, 'reason', a.reason, 'journal_entry', jid, 'requested_by', a.requested_by));
  perform public._w1a_exc('opening_adjusted', 'yellow', abs(a.delta),
    'Opening ' || a.kind || ' balance of ' || coalesce(a.party_name, '') || ' changed from ' || a.old_amount::text || ' to ' || a.new_amount::text || '. Reason: ' || a.reason,
    'Opening ' || a.kind || ' balance of ' || coalesce(a.party_name, '') || ' changed from ' || a.old_amount::text || ' to ' || a.new_amount::text || '. Reason: ' || a.reason);
  return jsonb_build_object('id', p_id, 'status', 'approved', 'journal_entry_id', jid, 'delta', a.delta);
end $$;

create or replace function public.w1a_open_adjust(p_kind text, p_party uuid, p_new numeric, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ numeric; nm text; d numeric; nid bigint; ex public.open_party_adjustments; md text := coalesce(public.rule_txt('open_parties_adjust_mode'), 'direct'); newv numeric;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('customer', 'supplier') then raise exception 'bad_kind'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_new is null or p_new = 'NaN'::numeric or abs(p_new) > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_kind = 'customer' and p_new < 0 then raise exception 'negative_not_allowed'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into ex from public.open_party_adjustments where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', ex.id, 'status', ex.status); end if;
  end if;
  if p_kind = 'customer' then select coalesce(opening_balance, 0), name into old_, nm from public.customers where id = p_party for update;
  else select coalesce(opening_balance, 0), name into old_, nm from public.suppliers where id = p_party for update; end if;
  if not found then raise exception 'unknown_party'; end if;
  newv := round(p_new, 2);
  d := newv - old_;
  if d = 0 then raise exception 'no_change'; end if;
  if exists (select 1 from public.open_party_adjustments where kind = p_kind and party_id = p_party and status = 'pending') then raise exception 'adjust_pending_exists'; end if;
  insert into public.open_party_adjustments (client_id, kind, party_id, party_name, old_amount, new_amount, delta, reason, mode, requested_by)
    values (p_client, p_kind, p_party, nm, old_, newv, d, left(btrim(p_reason), 300), md, auth.uid()) returning id into nid;
  if md = 'direct' then return public._w1a_adj_apply(nid, 'direct') || jsonb_build_object('mode', 'direct'); end if;
  perform public._w1a_audit('open_party_adjust_request', case p_kind when 'customer' then 'customers' else 'suppliers' end, p_party::text,
    jsonb_build_object('adjustment', nid, 'old', old_, 'new', newv, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', nid, 'status', 'pending', 'mode', 'approval');
end $$;

create or replace function public.w1a_open_adjust_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.open_party_adjustments;
begin
  if not public._w1a_mgr() then raise exception 'not allowed'; end if;
  select * into a from public.open_party_adjustments where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if a.status <> 'pending' then raise exception 'not_pending'; end if;
  if not public._w1a_may_decide(a.requested_by) then
    if a.requested_by = auth.uid() then raise exception 'maker_cannot_decide'; end if;
    raise exception 'named_approver_only';
  end if;
  if p_approve is null then raise exception 'bad_value'; end if;
  if not p_approve then
    if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
    update public.open_party_adjustments set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
    perform public._w1a_audit('open_party_adjust_reject', case a.kind when 'customer' then 'customers' else 'suppliers' end, a.party_id::text, jsonb_build_object('adjustment', p_id, 'note', left(btrim(p_note), 300)));
    return jsonb_build_object('id', p_id, 'status', 'rejected');
  end if;
  return public._w1a_adj_apply(p_id, p_note);
end $$;

create or replace function public.w1a_open_adjust_list(p_status text default null, p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select a.id, a.kind, a.party_id, a.party_name, a.old_amount, a.new_amount, a.delta, a.reason, a.mode, a.status, a.requested_by, a.requested_at, a.decided_by, a.decided_at, a.decision_note, a.journal_entry_id,
             (a.status = 'pending' and public._w1a_may_decide(a.requested_by)) as can_decide
        from public.open_party_adjustments a where p_status is null or a.status = p_status order by a.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ============================================================================
-- THE GATE: per party, the sub-ledger equals the general ledger (wraps acct_reconcile, names the cause)
-- ============================================================================
create or replace function public.w1a_party_gate(p_kind text default 'all') returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb; cust jsonb := '[]'::jsonb; sup jsonb := '[]'::jsonb; ar bigint; ap bigint; link boolean := public.rule_on('open_parties_link');
begin
  if not (public._acct_view() and public._acct_all()) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('all', 'customer', 'supplier') then raise exception 'bad_kind'; end if;
  if public._acct_start() is null then return jsonb_build_object('status', 'data_needed', 'why', 'accounting_start_date'); end if;
  r := public.acct_reconcile(p_kind);
  select account_id into ar from public.acct_mappings where key = 'receivable';
  select account_id into ap from public.acct_mappings where key = 'payable';
  select coalesce(jsonb_agg(z.row_ order by abs((z.row_ ->> 'unexplained')::numeric) desc), '[]'::jsonb) into cust from (
    select x || jsonb_build_object('typed_opening', coalesce(c.opening_balance, 0), 'journal_opening', jo.v,
      'cause', case when abs((x ->> 'unexplained')::numeric) <= 0.005 then null
                    when jo.v > 0 and coalesce(c.opening_balance, 0) = 0 then 'opening_in_books_not_in_subledger'
                    when coalesce(c.opening_balance, 0) > 0 and jo.v = 0 then 'opening_in_subledger_not_in_books'
                    when coalesce(c.opening_balance, 0) <> jo.v then 'opening_amounts_differ'
                    else 'transactions_differ' end) row_
      from jsonb_array_elements(coalesce(r -> 'customers', '[]'::jsonb)) x
      left join public.customers c on c.id::text = x ->> 'party_id'
      left join lateral (select coalesce(sum(l.debit - l.credit), 0) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                          where l.account_id = ar and l.party_type = 'customer' and l.party_id = x ->> 'party_id' and (e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening'))) jo on true) z;
  select coalesce(jsonb_agg(z.row_ order by abs((z.row_ ->> 'unexplained')::numeric) desc), '[]'::jsonb) into sup from (
    select x || jsonb_build_object('typed_opening', coalesce(c.opening_balance, 0), 'journal_opening', jo.v,
      'cause', case when abs((x ->> 'unexplained')::numeric) <= 0.005 then null
                    when jo.v <> 0 and coalesce(c.opening_balance, 0) = 0 then 'opening_in_books_not_in_subledger'
                    when coalesce(c.opening_balance, 0) <> 0 and jo.v = 0 then 'opening_in_subledger_not_in_books'
                    when coalesce(c.opening_balance, 0) <> jo.v then 'opening_amounts_differ'
                    else 'transactions_differ' end) row_
      from jsonb_array_elements(coalesce(r -> 'suppliers', '[]'::jsonb)) x
      left join public.suppliers c on c.id::text = x ->> 'party_id'
      left join lateral (select coalesce(sum(l.credit - l.debit), 0) v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                          where l.account_id = ap and l.party_type = 'supplier' and l.party_id = x ->> 'party_id' and (e.source_type = 'opening' or e.reverses_id in (select o.id from public.journal_entries o where o.source_type = 'opening'))) jo on true) z;
  return jsonb_build_object('status', case when jsonb_array_length(cust) + jsonb_array_length(sup) = 0 then 'green' else 'red' end, 'link', link, 'start', r -> 'start',
    'customers', cust, 'suppliers', sup, 'customers_off', jsonb_array_length(cust), 'suppliers_off', jsonb_array_length(sup), 'unattributed_receivable', coalesce(r -> 'unattributed_receivable', '0'::jsonb));
end $$;

-- ============================================================================
-- GRANTS: the API for signed-in users (each function checks the permission itself); internals closed
-- ============================================================================
revoke all on function public._w1a_patch(regprocedure, text[], text), public._p88_present(), public._w1a_mgr(), public._w1a_batch_exists(), public._w1a_frozen(), public._w1a_cust_open(uuid), public._w1a_cust_open_date(uuid),
  public._w1a_cust_open_at(uuid), public._w1a_audit(text, text, text, jsonb), public._w1a_exc(text, text, numeric, text, text), public._w1a_open_guard(), public._w1a_opening_apply(jsonb),
  public._w1a_may_decide(uuid), public._w1a_adj_apply(bigint, text) from public, anon, authenticated;
revoke all on function public.w1a_open_state(), public.w1a_open_list(text, text, text, int, int), public.w1a_open_set(text, uuid, numeric, date, text), public.w1a_open_import(text, jsonb, boolean, boolean),
  public.w1a_open_json(), public.w1a_open_precheck(jsonb), public.w1a_open_from_journal(boolean), public.w1a_open_adjust(text, uuid, numeric, text, uuid),
  public.w1a_open_adjust_decide(bigint, boolean, text), public.w1a_open_adjust_list(text, int), public.w1a_party_gate(text) from public, anon;
grant execute on function public.w1a_open_state(), public.w1a_open_list(text, text, text, int, int), public.w1a_open_set(text, uuid, numeric, date, text), public.w1a_open_import(text, jsonb, boolean, boolean),
  public.w1a_open_json(), public.w1a_open_precheck(jsonb), public.w1a_open_from_journal(boolean), public.w1a_open_adjust(text, uuid, numeric, text, uuid),
  public.w1a_open_adjust_decide(bigint, boolean, text), public.w1a_open_adjust_list(text, int), public.w1a_party_gate(text) to authenticated;

-- ===================== phase89.sql =====================
-- Phase 89 (bos89) - PERIOD INTEGRITY (U-02). Paste after phase87 (phase88 is a separate package and is not needed). Paste-twice safe. Earlier phase files are not edited.
-- Package W1-B. Owner standing rules applied: every policy is a SETTING with a safe default that keeps TODAY's behaviour, every change is an audit_log line,
-- the books of the past are never changed, an exception needs a reason and shows in the Exceptions list (money_exceptions, phase87).
--
-- WHAT THIS FILE ADDS (all of it works on its own; the five shared functions below are NOT touched here, their hook text is in docs/integration/W1-B.md and docs/integration/W1-B_hooks.sql)
--   * a pure date test for the period lock: _w1b_lock_date() / _w1b_is_locked(date) never look at who is asking.
--   * lock policy as settings: period_lock_mode (manual [default, today] | auto | off), auto_lock_day, owner_closed_period_mode (off [default, today] | log | reason).
--   * period_override_start / period_override_end: a short window (reason, from, to, minutes) in which ONE person may edit closed dates or back-date; every use is one audit_log line
--     and one row of the Exceptions list. Reuses the phase87 one-off grants (rule period_lock / override) for other people.
--   * back-date window per document type: backdate_max_days_purchase / cash_move / expense / production (blank = off). Over the limit needs a window, a one-off grant or a role grant.
--   * late offline sale policy: late_sale_policy redate [default, today] | redate_flag (re-dated and written to the Exceptions list) | park (held for the owner: accept with its own time, re-date, reject).
--   * guards on rules (only for calls that come through the API, like the phase80 guard): accounting_start_date cannot move after an opening exists (switch),
--     accounting_on OFF -> ON needs a reason (switch), the lock date cannot move back without a reason (lock_backward_policy).
--   * period_lock_state(), period_lock_set(date, reason), period_lock_policy_set(key, value, note), period_override_log(), period_lateness_report(days), accounting_on_preview(), accounting_on_set(on, reason),
--     late_sales_held_list(status), late_sale_release(id, action, reason).
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner changes a setting AND the hooks of the integrator are installed: every default equals today's behaviour.
-- !! Re-pasting phase 6, 8, 10, 14, 19, 23, 43, 50, 73, 74 or 87 after the hooks removes them: the integrator's re-patch phase puts them back.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase89 needs phase87 (and the phases before it) first'; end if;
  if to_regprocedure('public.lock_check(date)') is null or to_regprocedure('public._acct_locked(date)') is null or to_regprocedure('public._m_lock_exc(date)') is null
     or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regclass('public.money_exceptions') is null
     or to_regprocedure('public.rule_ok(text,integer,numeric,date,text)') is null or to_regprocedure('public.no_hard_delete()') is null then
    raise exception 'phase89 needs the shared functions of phases 6, 7 and 87';
  end if;
end $g$;

create or replace function public._p89_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text, with a marker of your own (the phase87 helper _m_patch only knows the marker bos87, and lock_check already carries it) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed and the paste stops). The marker must appear in the new text. Already patched = no-op.
create or replace function public._w1b_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'phase89 patch needs a marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase89 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'phase89 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- tables ----------
create table if not exists public.period_overrides (          -- a short window in which one person may work in a closed period / back-date (reason required)
  id bigserial primary key,
  scope text not null default 'lock' check (scope in ('lock', 'backdate', 'both')),
  user_id uuid not null,
  from_date date not null, to_date date not null,
  doc_type text check (doc_type is null or doc_type in ('purchase', 'cash_move', 'expense', 'production')),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  started_by uuid not null, started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz, ended_by uuid, end_note text,
  uses int not null default 0, last_used_at timestamptz,
  check (from_date <= to_date)
);
create index if not exists period_overrides_user on public.period_overrides (user_id, expires_at);

create table if not exists public.late_sales_held (            -- offline sales older than pos_offline_hours when late_sale_policy = park
  id bigserial primary key,
  client_id uuid,
  user_id uuid not null,
  location_id int not null,
  sold_at timestamptz not null,
  received_at timestamptz not null default now(),
  hours_late numeric,
  payload jsonb not null,
  status text not null default 'held' check (status in ('held', 'accepted', 'redated', 'rejected')),
  decided_by uuid, decided_at timestamptz, decide_reason text,
  sale_id uuid, result jsonb,
  exception_id bigint
);
create unique index if not exists late_sales_held_client on public.late_sales_held (client_id, user_id) where client_id is not null;
create index if not exists late_sales_held_status on public.late_sales_held (status, id);

do $t$ declare t text; begin
  foreach t in array array['period_overrides', 'late_sales_held'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  drop policy if exists period_overrides_read on public.period_overrides;
  create policy period_overrides_read on public.period_overrides for select to authenticated using (public.is_owner());
  grant select on public.period_overrides to authenticated;
  drop policy if exists late_sales_held_read on public.late_sales_held;
  create policy late_sales_held_read on public.late_sales_held for select to authenticated using (public.can_grant('late_sale_release'));
  grant select on public.late_sales_held to authenticated;
end $t$;

-- the Exceptions list (phase87 money_exceptions) learns the new kinds. The list is MERGED with what is allowed now, so another package that added kinds is not wiped out.
do $k$ declare def text; cur text[]; want text[] := array['late_sale_held', 'late_sale_redated', 'backdate_exception']; allk text[]; k text;
begin
  select pg_get_constraintdef(oid) into def from pg_constraint where conrelid = 'public.money_exceptions'::regclass and conname = 'money_exceptions_kind_check';
  if def is null then return; end if;
  select coalesce(array_agg(m[1]), '{}') into cur from regexp_matches(def, '''([a-z_0-9]+)''::text', 'g') m;          -- the form ARRAY['a'::text, 'b'::text]
  if cardinality(cur) = 0 then cur := coalesce(string_to_array(substring(def from '\{([^}]*)\}'), ','), '{}'); end if;   -- the form '{a,b}'::text[] (what this block itself writes)
  if cardinality(cur) = 0 then return; end if;                                                                           -- unknown shape: leave the constraint alone
  allk := cur;
  foreach k in array want loop if not k = any (allk) then allk := allk || k; end if; end loop;
  if cardinality(allk) = cardinality(cur) then return; end if;
  alter table public.money_exceptions drop constraint money_exceptions_kind_check;
  execute format('alter table public.money_exceptions add constraint money_exceptions_kind_check check (kind = any (%L::text[]))', allk);
end $k$;

-- ---------- settings (English labels only for now; Bangla later). Every default equals today's behaviour ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('period_lock_mode', 'books', 'choice', '"manual"', null, '["manual","auto","off"]', null, null,
  'Period lock: how the books are closed', 'Period lock: how the books are closed', 'Period lock: how the books are closed',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.',
  'manual = the date typed in "Books closed until" (today). auto = the previous month locks by itself after the day set below, and the typed date still counts. off = no lock at all.', 200),
 ('auto_lock_day', 'books', 'number', null, 'day of month', null, 1, 28, 'Automatic lock: lock last month after this day', 'Automatic lock: lock last month after this day', 'Automatic lock: lock last month after this day',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).',
  'Used only when the period lock is auto. Example 10: from the 11th of each month the whole previous month is closed. Blank = not set (auto then locks nothing by itself).', 201),
 ('owner_closed_period_mode', 'books', 'choice', '"off"', null, '["off","log","reason"]', null, null,
  'Owner in a closed period', 'Owner in a closed period', 'Owner in a closed period',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).',
  'off = the owner changes closed dates silently (today). log = allowed, but every use is logged to the Exceptions list. reason = refused until the owner opens an override window with a written reason (recommended once the books are really closed).', 202),
 ('period_override_default_minutes', 'books', 'number', '60', 'minutes', null, 5, 1440, 'Override window: default length', 'Override window: default length', 'Override window: default length',
  'How long an override window stays open when no length is typed.', 'How long an override window stays open when no length is typed.', 'How long an override window stays open when no length is typed.', 203),
 ('lock_backward_policy', 'books', 'choice', '"allow"', null, '["allow","reason_after_year_close","reason_always"]', null, null,
  'Moving the lock date back', 'Moving the lock date back', 'Moving the lock date back',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.',
  'allow = anytime (today). reason_after_year_close = moving the date back into a closed year needs a written reopen reason. reason_always = any move back needs a reason.', 204),
 ('backdate_max_days_purchase', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: purchase bill date', 'Back-date limit: purchase bill date', 'Back-date limit: purchase bill date',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.',
  'How many days back a new purchase bill may be dated. Blank = no limit (today). Over the limit needs an override window, a one-off owner grant or a role with the back-date grant.', 205),
 ('backdate_max_days_cash_move', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: cash move date', 'Back-date limit: cash move date', 'Back-date limit: cash move date',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).',
  'How many days back a new cash move (deposit, withdrawal, owner top-up or draw, advance) may be dated. Blank = no limit (today).', 206),
 ('backdate_max_days_expense', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: quick expense date', 'Back-date limit: quick expense date', 'Back-date limit: quick expense date',
  'How many days back a new quick expense may be dated. Blank = no limit (today).', 'How many days back a new quick expense may be dated. Blank = no limit (today).', 'How many days back a new quick expense may be dated. Blank = no limit (today).', 207),
 ('backdate_max_days_production', 'books', 'number', null, 'days', null, 0, 3650, 'Back-date limit: production date', 'Back-date limit: production date', 'Back-date limit: production date',
  'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 'How many days back a production run may be dated (the made-at time). Blank = no limit (today).', 208),
 ('late_sale_policy', 'pos', 'choice', '"redate"', null, '["redate","redate_flag","park"]', null, null,
  'Offline sale older than the offline limit', 'Offline sale older than the offline limit', 'Offline sale older than the offline limit',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".',
  'redate = the sale takes the time it reached the server (today). redate_flag = same, and a line goes to the Exceptions list. park = the sale is held for the owner, who accepts it with its own time, re-dates it, or rejects it. The limit itself is the setting "How many hours an offline sale keeps its own time".', 209),
 ('start_date_lock_after_opening', 'books', 'switch', 'false', null, null, null, null, 'Do not move the accounting start date after the opening is posted', 'Do not move the accounting start date after the opening is posted', 'Do not move the accounting start date after the opening is posted',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.',
  'On = once an opening balance entry exists the start date cannot be changed (reverse the opening first). Off = as today.', 210),
 ('accounting_on_needs_reason', 'books', 'switch', 'false', null, null, null, null, 'Switching accounting ON needs a reason', 'Switching accounting ON needs a reason', 'Switching accounting ON needs a reason',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.',
  'On = turning Accounting from OFF to ON must be done from the Period lock screen with a written reason, after a preview of the backlog that will be posted. Off = as today.', 211)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('late_sale_release', 'pos', 40, 'Decide a held late offline sale', 'Decide a held late offline sale', 'Decide a held late offline sale', 'once', null),
 ('backdate_over_limit', 'books', 41, 'Date a record further back than the limit', 'Date a record further back than the limit', 'Date a record further back than the limit', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- small helpers ----------
create or replace function public._w1b_exc(p_kind text, p_reason text, p_src_table text, p_src_id text, p_amount numeric default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  insert into public.money_exceptions (kind, reason, src_table, src_id, amount, by_user) values (p_kind, left(coalesce(p_reason, ''), 500), p_src_table, p_src_id, p_amount, auth.uid()) returning id into id_;
  return id_;
end $$;

create or replace function public._w1b_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;

create or replace function public._w1b_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

create or replace function public._w1b_pdate(t text) returns date language plpgsql immutable as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;      -- an impossible date (2026-02-30) locks nobody out
end $$;

-- ---------- the pure date test (never looks at who asks) ----------
-- automatic month lock: from the day AFTER day N of a month the whole previous month is closed; up to and including day N the month before that is the last closed one
create or replace function public._w1b_auto_date(p_today date, p_day int) returns date language plpgsql immutable as $$
declare a date;
begin
  if p_today is null or p_day is null or p_day not between 1 and 28 then return null; end if;
  a := date_trunc('month', p_today)::date - 1;                                   -- last day of the previous month
  if extract(day from p_today)::int <= p_day then a := date_trunc('month', a)::date - 1; end if;     -- not yet past day N: the month before that
  return a;
end $$;

create or replace function public._w1b_lock_date() returns date
language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('period_lock_mode'), 'manual'); d date;
begin
  if m = 'off' then return null; end if;
  d := public._w1b_pdate(public.rule_txt('period_closed_until'));
  if m = 'auto' then d := greatest(d, public._w1b_auto_date(public._w1b_today(), public.rule_num('auto_lock_day')::int)); end if;
  return d;
end $$;

create or replace function public._w1b_is_locked(p_date date) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d date := public._w1b_lock_date();
begin return p_date is not null and d is not null and p_date <= d; end $$;

-- the owner is not exempt from the books-posting date test when the owner mode is log or reason (see the hook of _acct_locked)
create or replace function public._w1b_pure_posting() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('owner_closed_period_mode'), 'off') in ('log', 'reason') $$;

-- ---------- override windows ----------
create or replace function public._w1b_override_take(p_scope text, p_date date, p_doc text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare o public.period_overrides; k text; cur text := coalesce(current_setting('bos89.ovx', true), '');
begin
  if auth.uid() is null or p_date is null then return null; end if;
  select * into o from public.period_overrides x
   where x.user_id = auth.uid() and x.ended_at is null and x.expires_at > now() and x.scope in (p_scope, 'both') and p_date between x.from_date and x.to_date
     and (x.doc_type is null or x.doc_type = p_doc) order by x.id limit 1;
  if not found then return null; end if;
  k := '|' || o.id::text || ':' || p_scope || '|';
  if position(k in cur) = 0 then           -- the first use in this transaction is the one that is logged
    update public.period_overrides set uses = uses + 1, last_used_at = now() where id = o.id;
    perform public._w1b_exc(case p_scope when 'lock' then 'period_lock_exception' else 'backdate_exception' end,
      o.reason || ' (override window #' || o.id::text || ', date ' || p_date::text || ')', 'period_overrides', o.id::text, null);
    perform public._w1b_audit('period_override_used', 'period_overrides', o.id::text, jsonb_build_object('scope', p_scope, 'date', p_date, 'doc', p_doc, 'reason', o.reason, 'started_by', o.started_by));
    perform set_config('bos89.ovx', cur || k, true);
  end if;
  return o.id;
end $$;

-- the decision behind lock_check (the hook calls this). true = the date may be used. false = period_closed. Raises period_closed_reason_required for the owner in mode reason.
create or replace function public._w1b_lock_allowed(p_date date) returns boolean
language plpgsql security definer set search_path = public as $$
declare d date := public._w1b_lock_date(); om text; k text; cur text;
begin
  if d is null or p_date is null or p_date > d then return true; end if;
  if public.is_owner() then
    om := coalesce(public.rule_txt('owner_closed_period_mode'), 'off');
    if om = 'off' then return true; end if;                                      -- today: the owner is silent
    if public._w1b_override_take('lock', p_date) is not null then return true; end if;
    if om = 'log' then
      k := '|log:' || p_date::text || '|'; cur := coalesce(current_setting('bos89.ovx', true), '');
      if position(k in cur) = 0 then
        perform public._w1b_exc('period_lock_exception', 'owner used a closed date (log mode), date ' || p_date::text, 'lock_check', null, null);
        perform public._w1b_audit('period_owner_closed_date', 'rules', 'period_closed_until', jsonb_build_object('date', p_date, 'mode', 'log'));
        perform set_config('bos89.ovx', cur || k, true);
      end if;
      return true;
    end if;
    raise exception 'period_closed_reason_required' using detail = 'books are closed until ' || d::text || '; open an override window with a reason';
  end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return true; end if;
  if public._m_lock_exc(p_date) then return true; end if;
  if public._w1b_override_take('lock', p_date) is not null then return true; end if;
  return false;
end $$;

-- ---------- back-date window per document type ----------
-- p_doc: purchase | cash_move | expense | production. Blank limit = off. Called by the hooks of the integrator (after the duplicate check, so a retry of a saved record is never refused).
create or replace function public._w1b_backdate_check(p_doc text, p_date date, p_client uuid default null, p_ref text default null) returns void
language plpgsql security definer set search_path = public as $$
declare lim numeric; t date := public._w1b_today();
begin
  if p_doc is null or p_doc not in ('purchase', 'cash_move', 'expense', 'production') or p_date is null then return; end if;
  lim := public.rule_num('backdate_max_days_' || p_doc);
  if lim is null then return; end if;                                        -- blank = off
  if p_date >= t - lim::int then return; end if;
  if public._w1b_override_take('backdate', p_date, p_doc) is not null then return; end if;
  if public._m_grant_take('override', 'backdate:' || p_doc, p_client, null, null, p_date, p_ref) then return; end if;     -- a one-off grant of the owner (phase87)
  if auth.uid() is not null and exists (select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = 'backdate_over_limit' and g.allowed
                                         join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid()) then       -- a role the owner trusts with it
    perform public._w1b_exc('backdate_exception', p_doc || ' dated ' || p_date::text || ', limit ' || lim::text || ' days (role grant)', coalesce(p_ref, p_doc), null, null);
    perform public._w1b_audit('backdate_over_limit', p_doc, coalesce(p_client::text, p_ref, ''), jsonb_build_object('date', p_date, 'limit_days', lim));
    return;
  end if;
  raise exception 'backdate_over_limit' using detail = p_doc || ' dated ' || p_date::text || ' is more than ' || lim::text || ' days back';
end $$;

-- ---------- late offline sales ----------
-- Called by the hook of record_sale2 when the sale time is outside the offline window. Returns null = re-date to now (as today), {"keep":true} = keep the sale time, anything else = the parked answer.
create or replace function public._w1b_late_sale(p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb, p_mobile text, p_name text, p_type text, p_note text,
  p_quick boolean, p_sold_at timestamptz, p_dk text, p_di numeric, p_at timestamptz) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pol text := coalesce(public.rule_txt('late_sale_policy'), 'redate'); okf text := coalesce(current_setting('bos89.late_ok', true), ''); h public.late_sales_held; eid bigint; hrs numeric;
begin
  if p_at is null or p_at > now() then return null; end if;                   -- a time in the future is always corrected (as before)
  if okf like 'keep:%' then return jsonb_build_object('keep', true); end if;  -- the owner accepted this sale with its own time
  if okf like 'redate:%' then return null; end if;
  hrs := round(extract(epoch from (now() - p_at)) / 3600, 1);
  if pol = 'park' then
    if p_client is not null then
      select * into h from public.late_sales_held where client_id = p_client and user_id = auth.uid();
      if found then return jsonb_build_object('parked', true, 'held_id', h.id, 'dup', true, 'status', h.status); end if;
    end if;
    insert into public.late_sales_held (client_id, user_id, location_id, sold_at, hours_late, payload)
      values (p_client, auth.uid(), p_loc, p_at, hrs, jsonb_build_object('lines', p_lines, 'discount', p_discount, 'payments', p_payments, 'customer_mobile', p_mobile, 'customer_name', p_name,
        'sale_type', p_type, 'note', p_note, 'quick', p_quick, 'discount_kind', p_dk, 'discount_input', p_di)) returning * into h;
    eid := public._w1b_exc('late_sale_held', 'offline sale made ' || to_char(p_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI') || ', ' || hrs::text || ' h before it reached the server (limit '
      || coalesce(public.rule_num('pos_offline_hours'), 72)::text || ' h); held for the owner', 'late_sales_held', h.id::text, null);
    update public.late_sales_held set exception_id = eid where id = h.id;
    perform public._w1b_audit('late_sale_held', 'late_sales_held', h.id::text, jsonb_build_object('location', p_loc, 'sold_at', p_at, 'hours_late', hrs, 'client_id', p_client));
    return jsonb_build_object('parked', true, 'held_id', h.id, 'hours_late', hrs);
  elsif pol = 'redate_flag' then
    perform set_config('bos89.redated', to_char(p_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI'), true);
  end if;
  return null;
end $$;

create or replace function public._w1b_sale_redate_flag() returns trigger language plpgsql security definer set search_path = public as $$
declare o text := coalesce(current_setting('bos89.redated', true), '');
begin
  if o = '' then return new; end if;
  perform set_config('bos89.redated', '', true);
  perform public._w1b_exc('late_sale_redated', 'receipt ' || new.receipt::text || ' was made ' || o || ' and was re-dated to the time it reached the server', 'sales', new.id::text, new.total);
  perform public._w1b_audit('late_sale_redated', 'sales', new.id::text, jsonb_build_object('receipt', new.receipt, 'made_at', o));
  return new;
end $$;
drop trigger if exists w1b_sales_redate_flag on public.sales;
create trigger w1b_sales_redate_flag after insert on public.sales for each row execute function public._w1b_sale_redate_flag();

-- ---------- guards on rules (only for calls that come through the API; the owner pasting SQL is not stopped) ----------
create or replace function public._w1b_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ov jsonb := coalesce(old.value, old.default_value); nv jsonb := coalesce(new.value, new.default_value); od date; nd date; pol text; need boolean;
begin
  if current_setting('role', true) is distinct from 'authenticated' then return new; end if;
  if ov is not distinct from nv then return new; end if;
  if new.key = 'accounting_start_date' then
    if public.rule_on('start_date_lock_after_opening') and nullif(ov #>> '{}', '') is not null
       and (exists (select 1 from public.journal_entries o where o.source_type = 'opening' and o.reverses_id is null
                     and not exists (select 1 from public.journal_entries r where r.reverses_id = o.id))
            or (to_regclass('public.opening_batches') is not null and exists (select 1 from public.opening_batches))) then
      raise exception 'start_date_locked_by_opening' using detail = 'an opening balance exists; reverse it before moving the accounting start date';
    end if;
  elsif new.key = 'period_closed_until' then
    pol := coalesce(public.rule_txt('lock_backward_policy'), 'allow');
    od := public._w1b_pdate(ov #>> '{}'); nd := public._w1b_pdate(nv #>> '{}');
    if pol <> 'allow' and od is not null and (nd is null or nd < od) then
      need := pol = 'reason_always' or exists (select 1 from public.year_closes y where y.status = 'closed' and (nd is null or y.fiscal_to >= nd));
      if need and coalesce(current_setting('bos89.lockreason', true), '') = '' then
        raise exception 'lock_backward_needs_reason' using detail = 'use Period lock > Set the lock date and write the reopen reason';
      end if;
    end if;
  elsif new.key = 'accounting_on' then
    if nv = 'true'::jsonb and ov is distinct from 'true'::jsonb and public.rule_on('accounting_on_needs_reason') and coalesce(current_setting('bos89.accreason', true), '') = '' then
      raise exception 'accounting_on_needs_reason' using detail = 'use Period lock > Accounting ON, read the backlog preview and write the reason';
    end if;
  elsif new.key = 'period_lock_mode' then
    if nv #>> '{}' = 'auto' and public.rule_num('auto_lock_day') is null then raise exception 'auto_lock_day_missing' using detail = 'set the automatic lock day first'; end if;
  elsif new.key = 'auto_lock_day' then
    if nullif(nv #>> '{}', '') is null and coalesce(public.rule_txt('period_lock_mode'), 'manual') = 'auto' then raise exception 'auto_lock_day_missing' using detail = 'the lock mode is auto: switch it first'; end if;
  end if;
  return new;
end $$;
drop trigger if exists w1b_rules_guard on public.rules;
create trigger w1b_rules_guard before update on public.rules for each row execute function public._w1b_rules_guard();

-- ============================================================================
-- Screens' functions
-- ============================================================================
create or replace function public._w1b_hooked(p_sig text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f regprocedure := to_regprocedure(p_sig);
begin
  if f is null then return false; end if;
  return position('bos89' in pg_get_functiondef(f)) > 0;
end $$;

create or replace function public.period_lock_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'owner', own,
    'today', public._w1b_today(),
    'mode', coalesce(public.rule_txt('period_lock_mode'), 'manual'),
    'manual_date', public._w1b_pdate(public.rule_txt('period_closed_until')),
    'auto_day', public.rule_num('auto_lock_day'),
    'effective_lock_date', public._w1b_lock_date(),
    'owner_mode', coalesce(public.rule_txt('owner_closed_period_mode'), 'off'),
    'override_minutes', public.rule_num('period_override_default_minutes'),
    'backward_policy', coalesce(public.rule_txt('lock_backward_policy'), 'allow'),
    'backdate', jsonb_build_object('purchase', public.rule_num('backdate_max_days_purchase'), 'cash_move', public.rule_num('backdate_max_days_cash_move'),
                                   'expense', public.rule_num('backdate_max_days_expense'), 'production', public.rule_num('backdate_max_days_production')),
    'late_sale_policy', coalesce(public.rule_txt('late_sale_policy'), 'redate'),
    'offline_hours', coalesce(public.rule_num('pos_offline_hours'), 72),
    'start_date_lock_after_opening', public.rule_on('start_date_lock_after_opening'),
    'accounting_on', public.rule_on('accounting_on'),
    'accounting_on_needs_reason', public.rule_on('accounting_on_needs_reason'),
    'held_sales', (select count(*) from public.late_sales_held where status = 'held'),
    'hooks', jsonb_build_object(
      'lock_check', public._w1b_hooked('public.lock_check(date)'), 'acct_locked', public._w1b_hooked('public._acct_locked(date)'),
      'record_sale2', public._w1b_hooked('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamp with time zone,text,numeric)'),
      'cash_move_add', public._w1b_hooked('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'),
      'quick_expense_add', public._w1b_hooked('public.quick_expense_add(integer,date,text,text,numeric,text,boolean,text,uuid)'),
      'save_purchase', public._w1b_hooked('public.save_purchase(uuid,uuid,uuid,integer,text,date,jsonb,numeric,text,text,text,uuid,text)'),
      'production_post', public._w1b_hooked('public.production_post(integer,uuid,numeric,uuid,timestamp with time zone,text,numeric)')),
    'my_windows', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'scope', o.scope, 'from', o.from_date, 'to', o.to_date, 'doc', o.doc_type, 'expires_at', o.expires_at, 'reason', o.reason) order by o.id)
                             from public.period_overrides o where o.user_id = auth.uid() and o.ended_at is null and o.expires_at > now()), '[]'::jsonb),
    'open_windows', case when own then coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'user_id', o.user_id, 'staff', (select staff_id from public.profiles where id = o.user_id), 'scope', o.scope,
                                'from', o.from_date, 'to', o.to_date, 'doc', o.doc_type, 'expires_at', o.expires_at, 'reason', o.reason, 'uses', o.uses) order by o.id)
                             from public.period_overrides o where o.ended_at is null and o.expires_at > now()), '[]'::jsonb) else '[]'::jsonb end);
end $$;

-- owner: set / clear the typed lock date. Moving back follows lock_backward_policy; a move back always leaves a line in the Exceptions list.
create or replace function public.period_lock_set(p_date date, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cur date := public._w1b_pdate(public.rule_txt('period_closed_until')); back boolean; pol text := coalesce(public.rule_txt('lock_backward_policy'), 'allow');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is not null and (p_date < date '2000-01-01' or p_date > public._w1b_today() + 366) then raise exception 'bad_date'; end if;
  back := cur is not null and (p_date is null or p_date < cur);
  if back and pol <> 'allow' and (p_reason is null or length(btrim(p_reason)) < 3) then
    if pol = 'reason_always' or exists (select 1 from public.year_closes y where y.status = 'closed' and (p_date is null or y.fiscal_to >= p_date)) then raise exception 'reason_required'; end if;
  end if;
  if back then perform set_config('bos89.lockreason', coalesce(nullif(btrim(p_reason), ''), 'moved back'), true); end if;
  perform public.set_rule('period_closed_until', case when p_date is null then null else to_jsonb(p_date::text) end);
  perform public._w1b_audit('period_lock_set', 'rules', 'period_closed_until', jsonb_build_object('old', cur, 'new', p_date, 'back', back, 'reason', left(btrim(coalesce(p_reason, '')), 300)));
  if back then perform public._w1b_exc('period_lock_exception', 'lock date moved back from ' || cur::text || ' to ' || coalesce(p_date::text, 'none') || ': ' || left(btrim(coalesce(p_reason, '')), 300), 'rules', 'period_closed_until', null); end if;
  perform set_config('bos89.lockreason', '', true);
  return jsonb_build_object('old', cur, 'new', p_date, 'back', back);
end $$;

create or replace function public.period_lock_policy_set(p_key text, p_value jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('period_lock_mode', 'auto_lock_day', 'owner_closed_period_mode', 'period_override_default_minutes', 'lock_backward_policy', 'backdate_max_days_purchase',
       'backdate_max_days_cash_move', 'backdate_max_days_expense', 'backdate_max_days_production', 'late_sale_policy', 'start_date_lock_after_opening', 'accounting_on_needs_reason') then
    raise exception 'unknown_setting';
  end if;
  select coalesce(value, default_value) into old_ from public.rules where key = p_key;
  perform public.set_rule(p_key, p_value);
  perform public._w1b_audit('period_policy_set', 'rules', p_key, jsonb_build_object('old', old_, 'new', p_value, 'note', left(btrim(coalesce(p_note, '')), 300)));
  return jsonb_build_object('key', p_key, 'old', old_, 'new', p_value);
end $$;

-- owner: open a window (reason required) for himself or a named person
create or replace function public.period_override_start(p_reason text, p_from date, p_to date, p_minutes int default null, p_scope text default 'lock', p_for_user uuid default null, p_doc text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mins int; u uuid := coalesce(p_for_user, auth.uid()); id_ bigint; exp timestamptz;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_from is null or p_to is null or p_from > p_to or p_from < date '2000-01-01' or p_to > public._w1b_today() + 366 then raise exception 'bad_date'; end if;
  if p_scope is null or p_scope not in ('lock', 'backdate', 'both') then raise exception 'bad_scope'; end if;
  if p_doc is not null and p_doc not in ('purchase', 'cash_move', 'expense', 'production') then raise exception 'bad_doc'; end if;
  mins := coalesce(p_minutes, public.rule_num('period_override_default_minutes')::int, 60);
  if mins < 1 or mins > 1440 then raise exception 'bad_minutes'; end if;
  if not exists (select 1 from public.profiles where id = u and status = 'active') then raise exception 'unknown_user'; end if;
  exp := now() + make_interval(mins => mins);
  insert into public.period_overrides (scope, user_id, from_date, to_date, doc_type, reason, started_by, expires_at)
    values (p_scope, u, p_from, p_to, p_doc, left(btrim(p_reason), 300), auth.uid(), exp) returning id into id_;
  perform public._w1b_audit('period_override_start', 'period_overrides', id_::text, jsonb_build_object('scope', p_scope, 'for_user', u, 'from', p_from, 'to', p_to, 'doc', p_doc, 'minutes', mins, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_, 'expires_at', exp, 'minutes', mins);
end $$;

create or replace function public.period_override_end(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.period_overrides set ended_at = now(), ended_by = auth.uid(), end_note = left(btrim(coalesce(p_note, '')), 300) where id = p_id and ended_at is null;
  if not found then raise exception 'not found'; end if;
  perform public._w1b_audit('period_override_end', 'period_overrides', p_id::text, jsonb_build_object('note', left(btrim(coalesce(p_note, '')), 300)));
  return jsonb_build_object('id', p_id, 'ended', true);
end $$;

-- owner: every window ever opened, the Exceptions-list lines this package wrote, and the audit lines about the lock
create or replace function public.period_override_log(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'windows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select o.id, o.scope, o.user_id, (select staff_id from public.profiles where id = o.user_id) as staff, o.from_date, o.to_date, o.doc_type, o.reason, o.started_at, o.expires_at, o.ended_at, o.uses, o.last_used_at
          from public.period_overrides o order by o.id desc limit lim) z), '[]'::jsonb),
    'exceptions', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select x.id, x.at, x.kind, x.reason, x.src_table, x.src_id, x.status from public.money_exceptions x
         where x.kind in ('period_lock_exception', 'backdate_exception', 'late_sale_held', 'late_sale_redated') order by x.id desc limit lim) z), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
        select a.id, a.at, a.staff_id, a.action, a.record_id, a.detail from public.audit_log a
         where a.action in ('period_lock_set', 'period_policy_set', 'period_override_start', 'period_override_used', 'period_override_end', 'period_owner_closed_date', 'late_sale_held', 'late_sale_redated',
                            'late_sale_release', 'backdate_over_limit', 'accounting_on_set') order by a.id desc limit lim) z), '[]'::jsonb));
end $$;

-- how late are records entered: read this for 30 days before choosing a back-date number (counts by days between the record date and the day it was entered)
create or replace function public.period_lateness_report(p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dd int := least(greatest(coalesce(p_days, 30), 1), 365); t date := public._w1b_today(); res jsonb := '{}'::jsonb; r record;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in
    with x as (
      select 'purchase' as doc, (b.created_at at time zone 'Asia/Dhaka')::date - b.bill_date as late from public.purchase_bills b where b.status <> 'void' and b.created_at >= now() - make_interval(days => dd)
      union all select 'cash_move', (m.created_at at time zone 'Asia/Dhaka')::date - m.move_date from public.cash_moves m where m.status = 'done' and m.created_at >= now() - make_interval(days => dd)
      union all select 'expense', (q.created_at at time zone 'Asia/Dhaka')::date - q.exp_date from public.quick_expenses q where q.status <> 'void' and q.created_at >= now() - make_interval(days => dd)
      union all select 'production', (p.created_at at time zone 'Asia/Dhaka')::date - (p.made_at at time zone 'Asia/Dhaka')::date from public.production_runs p where p.created_at >= now() - make_interval(days => dd))
    select doc, count(*) n, coalesce(max(late), 0) max_late, count(*) filter (where late <= 0) d0, count(*) filter (where late between 1 and 2) d1_2, count(*) filter (where late between 3 and 7) d3_7,
           count(*) filter (where late between 8 and 30) d8_30, count(*) filter (where late > 30) d31 from x group by doc
  loop
    res := res || jsonb_build_object(r.doc, jsonb_build_object('records', r.n, 'max_days_late', r.max_late, 'same_day', r.d0, 'days_1_2', r.d1_2, 'days_3_7', r.d3_7, 'days_8_30', r.d8_30, 'over_30', r.d31));
  end loop;
  return jsonb_build_object('days', dd, 'as_of', t, 'by_document', res, 'note', 'Sales are not listed: a sale carries no entry time. The offline sale limit is the setting pos_offline_hours.');
end $$;

-- accounting ON after OFF: what would be posted at once
create or replace function public.accounting_on_preview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; oldest date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  begin r := public.acct_post_pending(true, 5000);
  exception when others then return jsonb_build_object('ran', false, 'why', sqlerrm, 'accounting_on', public.rule_on('accounting_on')); end;
  select min((x ->> 'date')::date) into oldest from jsonb_array_elements(coalesce(r -> 'preview', '[]'::jsonb)) x;
  return jsonb_build_object('ran', true, 'accounting_on', public.rule_on('accounting_on'), 'start_date', public._w1b_pdate(public.rule_txt('accounting_start_date')),
    'would_post', coalesce((r ->> 'posted')::int, 0), 'would_reverse', coalesce((r ->> 'reversed')::int, 0), 'skipped_locked', coalesce((r ->> 'locked')::int, 0), 'by_type', coalesce(r -> 'by_type', '{}'::jsonb),
    'oldest_in_sample', oldest, 'data_needed', coalesce((r ->> 'data_needed')::boolean, false), 'more', coalesce((r ->> 'more')::boolean, false));
end $$;

create or replace function public.accounting_on_set(p_on boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare was boolean := public.rule_on('accounting_on'); pv jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_on is null then raise exception 'bad_value'; end if;
  if p_on and not was and public.rule_on('accounting_on_needs_reason') and (p_reason is null or length(btrim(p_reason)) < 3) then raise exception 'reason_required'; end if;
  if p_on and not was then pv := public.accounting_on_preview(); end if;
  if p_on and not was then perform set_config('bos89.accreason', coalesce(nullif(btrim(p_reason), ''), 'switched on'), true); end if;
  perform public.set_rule('accounting_on', to_jsonb(p_on));
  perform set_config('bos89.accreason', '', true);
  perform public._w1b_audit('accounting_on_set', 'rules', 'accounting_on', jsonb_build_object('old', was, 'new', p_on, 'reason', left(btrim(coalesce(p_reason, '')), 300), 'backlog', pv));
  return jsonb_build_object('old', was, 'new', p_on, 'backlog', pv);
end $$;

-- ---------- held late sales ----------
create or replace function public.late_sales_held_list(p_status text default 'held') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_grant('late_sale_release') then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select h.id, h.client_id, h.location_id, h.sold_at, h.received_at, h.hours_late, h.status, h.user_id, (select staff_id from public.profiles where id = h.user_id) as staff,
           jsonb_array_length(coalesce(h.payload -> 'lines', '[]'::jsonb)) as n_lines,
           coalesce((select sum(nullif(p ->> 'amount', '')::numeric) from jsonb_array_elements(coalesce(h.payload -> 'payments', '[]'::jsonb)) p), 0) as paid,
           h.payload -> 'lines' as lines, h.decide_reason, h.decided_at, h.sale_id
      from public.late_sales_held h where p_status is null or h.status = p_status order by h.id desc limit 300) z), '[]'::jsonb);
end $$;

-- action: accept (the sale keeps its own time) | redate (it takes the time of now) | reject (it is not recorded). The sale is recorded AS the cashier who made it.
create or replace function public.late_sale_release(p_id bigint, p_action text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.late_sales_held; pl jsonb; res jsonb; me uuid := auth.uid();
  prev_sub text := coalesce(current_setting('request.jwt.claim.sub', true), ''); prev_claims text := coalesce(current_setting('request.jwt.claims', true), '');
begin
  if not public.is_active() or not public.can_grant('late_sale_release') then raise exception 'not allowed'; end if;
  if p_action is null or p_action not in ('accept', 'redate', 'reject') then raise exception 'bad_action'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into h from public.late_sales_held where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if h.status <> 'held' then raise exception 'already_decided'; end if;
  if h.user_id = me and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_decide'; end if;
  if p_action <> 'reject' then
    pl := h.payload;
    perform set_config('request.jwt.claim.sub', h.user_id::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub', h.user_id::text, 'role', 'authenticated')::text, true);
    perform set_config('bos89.late_ok', case p_action when 'accept' then 'keep:' else 'redate:' end || h.id::text, true);
    res := public.record_sale2(h.client_id, h.location_id, pl -> 'lines', nullif(pl ->> 'discount', '')::numeric, pl -> 'payments', pl ->> 'customer_mobile', pl ->> 'customer_name', pl ->> 'sale_type',
      pl ->> 'note', nullif(pl ->> 'quick', '')::boolean, case when p_action = 'accept' then h.sold_at end, pl ->> 'discount_kind', nullif(pl ->> 'discount_input', '')::numeric);
    perform set_config('bos89.late_ok', '', true);
    perform set_config('request.jwt.claim.sub', prev_sub, true);
    perform set_config('request.jwt.claims', prev_claims, true);
  end if;
  update public.late_sales_held set status = case p_action when 'accept' then 'accepted' when 'redate' then 'redated' else 'rejected' end, decided_by = me, decided_at = now(),
         decide_reason = left(btrim(p_reason), 300), sale_id = nullif(res ->> 'id', '')::uuid, result = res where id = h.id;
  if h.exception_id is not null then
    update public.money_exceptions set status = 'resolved', resolved_by = me, resolved_at = now(), resolve_note = left(p_action || ': ' || btrim(p_reason), 300) where id = h.exception_id and status = 'open';
  end if;
  perform public._w1b_audit('late_sale_release', 'late_sales_held', h.id::text, jsonb_build_object('action', p_action, 'reason', left(btrim(p_reason), 300), 'maker', h.user_id, 'sale', res ->> 'id'));
  return jsonb_build_object('id', h.id, 'action', p_action, 'sale', res);
end $$;

-- ---------- privileges ----------
revoke all on function public._w1b_patch(regprocedure, text, text[]), public._w1b_exc(text, text, text, text, numeric), public._w1b_audit(text, text, text, jsonb), public._w1b_today(), public._w1b_pdate(text),
  public._w1b_auto_date(date, int), public._w1b_lock_date(), public._w1b_is_locked(date), public._w1b_pure_posting(), public._w1b_override_take(text, date, text), public._w1b_lock_allowed(date),
  public._w1b_backdate_check(text, date, uuid, text), public._w1b_late_sale(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric, timestamptz),
  public._w1b_sale_redate_flag(), public._w1b_rules_guard(), public._w1b_hooked(text) from public, anon, authenticated;
revoke all on function public.period_lock_state(), public.period_lock_set(date, text), public.period_lock_policy_set(text, jsonb, text), public.period_override_start(text, date, date, int, text, uuid, text),
  public.period_override_end(bigint, text), public.period_override_log(int), public.period_lateness_report(int), public.accounting_on_preview(), public.accounting_on_set(boolean, text),
  public.late_sales_held_list(text), public.late_sale_release(bigint, text, text) from public, anon;
grant execute on function public.period_lock_state(), public.period_lock_set(date, text), public.period_lock_policy_set(text, jsonb, text), public.period_override_start(text, date, date, int, text, uuid, text),
  public.period_override_end(bigint, text), public.period_override_log(int), public.period_lateness_report(int), public.accounting_on_preview(), public.accounting_on_set(boolean, text),
  public.late_sales_held_list(text), public.late_sale_release(bigint, text, text) to authenticated;

-- ===================== phase90.sql =====================
-- Phase 90 (bos90) - U-03 STAFF EXIT REVOKES ACCESS. Paste after phase87 (needs phase41 employees), paste-twice safe. Earlier phase files are not edited.
-- Package W1-C (Wave 1). New functions all carry the prefix _w1c_. No shared function is changed by this file: the one hook line that
-- employee_status_set needs is written in docs/integration/W1-C.md and proved on a scratch copy in phase90_test.sql.
--
-- WHAT THIS ADDS
--   * When a person's employee status becomes one of the chosen exit statuses, their login (profiles.status), their grants (user_grants.valid_until),
--     their list-manager rows and, only if the owner switches it on, the attendance device tokens THEY registered are ended. One audit_log line per exit.
--   * Settings (rules, owner editable at any time, every change is an audit_log line through the rules audit trigger):
--       exit_revoke_mode      off [default: today's behaviour, nothing is touched] | alert (only a red exception) | auto (login is disabled)
--       exit_revoke_statuses  which statuses revoke, default resigned,terminated,retired (on_leave is allowed in the list but not recommended)
--       exit_alert_hours      blank = off; a linked login still active that many hours after the exit raises the red exception exit_access_open
--       exit_deactivate_devices  off [default]; on = also switch off attendance device tokens that this person registered
--   * Exception path: the owner, or any person the owner gave the grant exit_keep_access, can keep one person's access with a required reason
--     (audit_log line + a yellow row in the Exceptions list). A non-owner without the grant is refused on the server.
--   * Re-hire (status back to a non-exit status) re-enables the login that THIS feature disabled. Grants and device tokens are NOT restored.
--   * A departing owner login or the caller's own login is never disabled by this feature: a red exception tells the owner instead.
--   * Wrapper _w1c_employee_status_set(...) gives the same result without any hook (it calls employee_status_set and then the exit step once).
-- NOTHING CHANGES until the owner sets exit_revoke_mode to alert or auto (default off) or fills exit_alert_hours.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase90 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.employee_status_set(uuid,text,date,text)') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null
     or to_regclass('public.employee_status_log') is null or to_regclass('public.attendance_devices') is null then
    raise exception 'phase90 needs phase41 (employees) and the stock exception helper';
  end if;
end $g$;

create or replace function public._w1c_present90() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text, marker passed in (same idea as phase87 _m_patch, whose marker is fixed to bos87) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist exactly once, otherwise nothing is changed. Marker already present = no-op.
create or replace function public._w1c_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2,3}$' then raise exception 'w1c_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1c_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1c_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1c_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1c_patch(regprocedure, text[], text) from public, anon, authenticated;

-- append-only guard for the logs of this package
create or replace function public._w1c_append_only() returns trigger language plpgsql as $$
begin raise exception 'w1c_append_only' using hint = 'This log is never edited or deleted'; end $$;

-- one audit_log line (who, when, what, from, to)
create or replace function public._w1c_audit(p_action text, p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
revoke all on function public._w1c_audit(text, text, text, jsonb) from public, anon, authenticated;

-- one row in the Exceptions list (same table the stock exceptions use); the same open one for the same ref is not written twice
create or replace function public._w1c_exc(p_loc int, p_form text, p_flag text, p_level text, p_en text, p_ref text, p_amount numeric default null, p_date date default null) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if p_ref is not null and exists (select 1 from public.exceptions x where x.flag_code = p_flag and x.status = 'open' and x.text ->> 'ref' = p_ref) then return false; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, p_form, coalesce(p_loc, (select min(id) from public.locations)), coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date), p_flag, p_level, p_amount,
            jsonb_build_object('bn', p_en, 'en', p_en, 'ref', p_ref));
  return true;
end $$;
revoke all on function public._w1c_exc(int, text, text, text, text, text, numeric, date) from public, anon, authenticated;

-- ---------- tables ----------
create table if not exists public.w1c_exit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  employee_id uuid not null references public.employees(id),
  profile_id uuid,
  from_status text, to_status text,
  action text not null check (action in ('revoked', 'alert_only', 'kept', 'keep_ended', 'reenabled', 'skipped_owner', 'skipped_self', 'no_linked_login', 'already_disabled', 'scan_alert')),
  grants_ended int not null default 0, lists_ended int not null default 0, devices_off int not null default 0,
  reason text, by_user uuid
);
create index if not exists w1c_exit_log_emp on public.w1c_exit_log (employee_id, id);
drop trigger if exists w1c_exit_log_ro on public.w1c_exit_log;
create trigger w1c_exit_log_ro before update or delete on public.w1c_exit_log for each row execute function public._w1c_append_only();
alter table public.w1c_exit_log enable row level security;
drop policy if exists w1c_exit_log_read on public.w1c_exit_log;
create policy w1c_exit_log_read on public.w1c_exit_log for select to authenticated using (public.is_owner() or public._emp_any(array['employee_manage']));
revoke all on table public.w1c_exit_log from anon, authenticated; grant select on table public.w1c_exit_log to authenticated;
revoke all on sequence public.w1c_exit_log_id_seq from anon, authenticated;

create table if not exists public.w1c_exit_keep (
  employee_id uuid primary key references public.employees(id),
  profile_id uuid,
  reason text not null check (char_length(btrim(reason)) >= 3 and char_length(reason) <= 300),
  kept_by uuid, kept_at timestamptz not null default now(),
  ended_at timestamptz, ended_by uuid, end_reason text
);
drop trigger if exists audit_w1c_exit_keep on public.w1c_exit_keep;
create trigger audit_w1c_exit_keep after insert or update on public.w1c_exit_keep for each row execute function public.log_change('employee_id');
drop trigger if exists w1c_exit_keep_nodel on public.w1c_exit_keep;
create trigger w1c_exit_keep_nodel before delete on public.w1c_exit_keep for each row execute function public.no_hard_delete();
alter table public.w1c_exit_keep enable row level security;
drop policy if exists w1c_exit_keep_read on public.w1c_exit_keep;
create policy w1c_exit_keep_read on public.w1c_exit_keep for select to authenticated using (public.is_owner() or public._emp_any(array['employee_manage']));
revoke all on table public.w1c_exit_keep from anon, authenticated; grant select on table public.w1c_exit_keep to authenticated;

-- ---------- settings and grant (own keys only, on conflict do nothing) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('exit_revoke_mode', 'people', 'choice', '"off"'::jsonb, null, '["off","alert","auto"]'::jsonb, null, null,
  'When a person leaves: what happens to their login', 'When a person leaves: what happens to their login', 'When a person leaves: what happens to their login',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end',
  'off = nothing is touched (today); alert = only a red line in Exceptions; auto = the login is disabled and the grants end', 905),
 ('exit_revoke_statuses', 'people', 'text', '"resigned,terminated,retired"'::jsonb, null, null, null, null,
  'Which statuses count as leaving', 'Which statuses count as leaving', 'Which statuses count as leaving',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)',
  'Comma list of: resigned, terminated, retired, on_leave. Recommended: resigned, terminated, retired (not on_leave)', 906),
 ('exit_alert_hours', 'people', 'number', null, 'hours', null, 0, 8760,
  'Hours after leaving before an active login is flagged', 'Hours after leaving before an active login is flagged', 'Hours after leaving before an active login is flagged',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions',
  'Blank = off. A person who left but still has an active login after this many hours becomes a red line in Exceptions', 907),
 ('exit_deactivate_devices', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'Also switch off attendance device tokens the person registered', 'Also switch off attendance device tokens the person registered', 'Also switch off attendance device tokens the person registered',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave',
  'Off = device tokens are left alone (a token is shared by everyone at a place). On = tokens that this person registered are switched off when they leave', 908)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
values ('exit_keep_access', 'people', 905, 'Keep a login after the person has left', 'Keep a login after the person has left', 'Keep a login after the person has left', 'once')
on conflict (grant_code) do nothing;

-- the status list must contain only known statuses (the setting is free text on the Rules page)
create or replace function public._w1c_status_list_ok(p_txt text) returns boolean language sql immutable as $$
  select p_txt is not null and btrim(p_txt) <> '' and not exists (
    select 1 from unnest(string_to_array(lower(regexp_replace(p_txt, '\s', '', 'g')), ',')) t(s) where t.s not in ('resigned', 'terminated', 'retired', 'on_leave')) $$;
create or replace function public._w1c_rules_guard90() returns trigger language plpgsql as $$
begin
  if new.key = 'exit_revoke_statuses' and new.value is not null and jsonb_typeof(new.value) <> 'null' then
    if jsonb_typeof(new.value) <> 'string' or not public._w1c_status_list_ok(new.value #>> '{}') then raise exception 'bad_value'; end if;
  end if;
  return new;
end $$;
drop trigger if exists w1c_rules_guard90 on public.rules;
create trigger w1c_rules_guard90 before update on public.rules for each row when (new.key = 'exit_revoke_statuses') execute function public._w1c_rules_guard90();

create or replace function public._w1c_exit_statuses() returns text[] language plpgsql stable security definer set search_path = public as $$
declare t text := coalesce(public.rule_txt('exit_revoke_statuses'), 'resigned,terminated,retired');
begin
  if not public._w1c_status_list_ok(t) then t := 'resigned,terminated,retired'; end if;
  return string_to_array(lower(regexp_replace(t, '\s', '', 'g')), ',');
end $$;
revoke all on function public._w1c_exit_statuses() from public, anon, authenticated;

-- is an open keep record in force for this person
create or replace function public._w1c_exit_kept(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.w1c_exit_keep k where k.employee_id = p_emp and k.ended_at is null) $$;
revoke all on function public._w1c_exit_kept(uuid) from public, anon, authenticated;

-- ---------- the exit step (called by the hook in employee_status_set, or by the wrapper below) ----------
create or replace function public._w1c_exit_apply(p_emp uuid, p_from text, p_to text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; mode text := coalesce(public.rule_txt('exit_revoke_mode'), 'off'); sts text[] := public._w1c_exit_statuses(); pr public.profiles;
        g int := 0; l int := 0; d int := 0; last_act text; nm text;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return jsonb_build_object('skipped', 'not_found'); end if;
  if coalesce(current_setting('w1c.exit_done', true), '') = p_emp::text || ':' || p_to then return jsonb_build_object('skipped', 'done'); end if;
  perform set_config('w1c.exit_done', p_emp::text || ':' || p_to, true);
  nm := coalesce(nullif(e.employee_no, ''), '-') || ' ' || coalesce(e.full_name_en, e.full_name_bn);
  select * into pr from public.profiles where id = e.profile_id;

  -- coming back: the login THIS feature disabled is enabled again (grants and device tokens are not restored)
  if not (p_to = any (sts)) then
    if pr.id is not null and pr.status = 'disabled' then
      select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
      if last_act = 'revoked' then
        update public.profiles set status = 'active' where id = pr.id;
        insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'reenabled', left(p_reason, 300), auth.uid());
        perform public._w1c_audit('staff_exit_login_reenabled', 'profiles', pr.id::text, jsonb_build_object('employee', e.id, 'from', p_from, 'to', p_to, 'reason', p_reason, 'grants_restored', false));
        update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolved_note = 'person came back (' || p_to || ')'
          where flag_code = 'exit_access_open' and status = 'open' and text ->> 'ref' = e.id::text;
        return jsonb_build_object('action', 'reenabled');
      end if;
    end if;
    return jsonb_build_object('action', 'none');
  end if;

  -- leaving
  if mode = 'off' then return jsonb_build_object('action', 'mode_off'); end if;
  if e.profile_id is null or pr.id is null then
    insert into public.w1c_exit_log (employee_id, from_status, to_status, action, reason, by_user) values (e.id, p_from, p_to, 'no_linked_login', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_no_login_link', 'yellow', nm || ' left (' || p_to || ') and has no linked login, so nothing could be switched off. Check whether this person has a login.', e.id::text);
    return jsonb_build_object('action', 'no_linked_login');
  end if;
  if public._w1c_exit_kept(e.id) then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'kept', 'access kept by the owner (see keep record)', auth.uid());
    return jsonb_build_object('action', 'kept');
  end if;
  if mode = 'alert' then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'alert_only', left(p_reason, 300), auth.uid());
    if pr.status = 'active' then
      perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || p_to || ') but the login is still active. Disable it or keep it with a reason.', e.id::text);
    end if;
    return jsonb_build_object('action', 'alert_only');
  end if;
  -- mode auto
  if exists (select 1 from public.user_roles ur where ur.user_id = pr.id and ur.role_code = 'owner') then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'skipped_owner', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || p_to || ') but holds the owner role: the login was not disabled automatically.', e.id::text);
    return jsonb_build_object('action', 'skipped_owner');
  end if;
  if pr.id = auth.uid() then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'skipped_self', left(p_reason, 300), auth.uid());
    perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' changed their own status to ' || p_to || ': the login was not disabled automatically.', e.id::text);
    return jsonb_build_object('action', 'skipped_self');
  end if;
  if pr.status = 'disabled' then
    insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, pr.id, p_from, p_to, 'already_disabled', left(p_reason, 300), auth.uid());
    return jsonb_build_object('action', 'already_disabled');
  end if;
  update public.profiles set status = 'disabled' where id = pr.id;
  update public.user_grants set valid_until = now(), note = left(coalesce(note || ' ', '') || '[ended: staff exit ' || p_to || ']', 500)
    where user_id = pr.id and (valid_until is null or valid_until > now());
  get diagnostics g = row_count;
  update public.list_managers set active = false where user_id = pr.id and active;
  get diagnostics l = row_count;
  if public.rule_on('exit_deactivate_devices') then
    update public.attendance_devices set active = false where created_by = pr.id and active;
    get diagnostics d = row_count;
  end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, grants_ended, lists_ended, devices_off, reason, by_user)
    values (e.id, pr.id, p_from, p_to, 'revoked', g, l, d, left(p_reason, 300), auth.uid());
  perform public._w1c_audit('staff_exit_access_revoked', 'profiles', pr.id::text,
    jsonb_build_object('employee', e.id, 'from', p_from, 'to', p_to, 'date', p_date, 'reason', p_reason, 'grants_ended', g, 'list_manager_rows_ended', l, 'device_tokens_off', d));
  return jsonb_build_object('action', 'revoked', 'grants_ended', g, 'devices_off', d);
end $$;
revoke all on function public._w1c_exit_apply(uuid, text, text, date, text) from public, anon, authenticated;

-- wrapper: same call as employee_status_set; does the exit step once (also when the hook line is not installed yet)
create or replace function public._w1c_employee_status_set(p_id uuid, p_status text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_from text; r jsonb; x jsonb;
begin
  select status into v_from from public.employees where id = p_id;
  r := public.employee_status_set(p_id, p_status, p_date, p_reason);
  x := public._w1c_exit_apply(p_id, v_from, p_status, p_date, nullif(left(btrim(coalesce(p_reason, '')), 300), ''));
  -- integration fix (phase99): with the hook installed the step already ran inside employee_status_set, so the call above answers "done". Report what that step logged in this transaction.
  if x ->> 'skipped' = 'done' then
    select jsonb_build_object('action', l.action, 'grants_ended', l.grants_ended, 'lists_ended', l.lists_ended, 'devices_off', l.devices_off) into x
      from public.w1c_exit_log l where l.employee_id = p_id and l.at = now() order by l.id desc limit 1;
    x := coalesce(x, jsonb_build_object('action', 'done_by_hook'));
  end if;
  return r || jsonb_build_object('exit', x);
end $$;
revoke all on function public._w1c_employee_status_set(uuid, text, date, text) from public, anon; grant execute on function public._w1c_employee_status_set(uuid, text, date, text) to authenticated;

-- ---------- exception path: keep one person's access ----------
create or replace function public._w1c_exit_keep(p_employee uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; pr public.profiles; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), ''); restored boolean := false; last_act text;
begin
  if not public.has_grant('exit_keep_access') then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.employees where id = p_employee for update;
  if not found then raise exception 'not_found'; end if;
  if e.profile_id is null then raise exception 'no_linked_login'; end if;
  select * into pr from public.profiles where id = e.profile_id;
  insert into public.w1c_exit_keep (employee_id, profile_id, reason, kept_by, kept_at, ended_at, ended_by, end_reason)
    values (e.id, e.profile_id, v_reason, auth.uid(), now(), null, null, null)
    on conflict (employee_id) do update set profile_id = excluded.profile_id, reason = excluded.reason, kept_by = excluded.kept_by, kept_at = now(), ended_at = null, ended_by = null, end_reason = null;
  if pr.status = 'disabled' then
    select x.action into last_act from public.w1c_exit_log x where x.employee_id = e.id and x.action in ('revoked', 'reenabled') order by x.id desc limit 1;
    if last_act = 'revoked' then update public.profiles set status = 'active' where id = pr.id; restored := true; end if;
  end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, e.profile_id, e.status, e.status, 'kept', v_reason, auth.uid());
  perform public._w1c_audit('staff_exit_access_kept', 'profiles', e.profile_id::text, jsonb_build_object('employee', e.id, 'status', e.status, 'reason', v_reason, 'login_restored', restored));
  perform public._w1c_exc(e.primary_location_id, 'HR', 'exit_access_kept', 'yellow',
    coalesce(nullif(e.employee_no, ''), '-') || ' ' || coalesce(e.full_name_en, e.full_name_bn) || ': login kept although status is ' || e.status || '. Reason: ' || v_reason, e.id::text || ':keep:' || extract(epoch from now())::bigint);
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(), resolved_note = 'access kept: ' || v_reason
    where flag_code = 'exit_access_open' and status = 'open' and text ->> 'ref' = e.id::text;
  return jsonb_build_object('employee', e.id, 'kept', true, 'login_restored', restored);
end $$;
revoke all on function public._w1c_exit_keep(uuid, text) from public, anon; grant execute on function public._w1c_exit_keep(uuid, text) to authenticated;

create or replace function public._w1c_exit_keep_end(p_employee uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), ''); n int; x jsonb := '{}';
begin
  if not public.has_grant('exit_keep_access') then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  select * into e from public.employees where id = p_employee for update;
  if not found then raise exception 'not_found'; end if;
  update public.w1c_exit_keep set ended_at = now(), ended_by = auth.uid(), end_reason = v_reason where employee_id = e.id and ended_at is null;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_kept'; end if;
  insert into public.w1c_exit_log (employee_id, profile_id, from_status, to_status, action, reason, by_user) values (e.id, e.profile_id, e.status, e.status, 'keep_ended', v_reason, auth.uid());
  perform public._w1c_audit('staff_exit_keep_ended', 'profiles', coalesce(e.profile_id::text, '-'), jsonb_build_object('employee', e.id, 'status', e.status, 'reason', v_reason));
  perform set_config('w1c.exit_done', '', true);
  if e.status = any (public._w1c_exit_statuses()) then x := public._w1c_exit_apply(e.id, e.status, e.status, public._dhaka_today(), 'keep ended: ' || v_reason); end if;
  return jsonb_build_object('employee', e.id, 'kept', false, 'exit', x);
end $$;
revoke all on function public._w1c_exit_keep_end(uuid, text) from public, anon; grant execute on function public._w1c_exit_keep_end(uuid, text) to authenticated;

-- ---------- the alert scan (owner screen, scheduler or notification run) ----------
-- the work itself, no caller check: for a scheduler or the notification run (the hook line is in docs/integration/W1-C.md)
create or replace function public._w1c_exit_scan_run() returns jsonb language plpgsql security definer set search_path = public as $$
declare h numeric := public.rule_num('exit_alert_hours'); sts text[] := public._w1c_exit_statuses(); r record; n int := 0; nm text;
begin
  if h is null then return jsonb_build_object('raised', 0, 'skipped', 'alert_hours_blank'); end if;
  for r in
    select e.id, e.employee_no, e.full_name_en, e.full_name_bn, e.status, e.primary_location_id,
           coalesce((select max(x.at) from public.employee_status_log x where x.employee_id = e.id and x.to_status = e.status), e.status_date::timestamptz) as left_at
      from public.employees e join public.profiles pr on pr.id = e.profile_id
     where e.status = any (sts) and pr.status = 'active'
       and not exists (select 1 from public.user_roles ur where ur.user_id = pr.id and ur.role_code = 'owner')
       and not public._w1c_exit_kept(e.id)
  loop
    continue when r.left_at is null or r.left_at > now() - make_interval(secs => h * 3600);
    nm := coalesce(nullif(r.employee_no, ''), '-') || ' ' || coalesce(r.full_name_en, r.full_name_bn);
    if public._w1c_exc(r.primary_location_id, 'HR', 'exit_access_open', 'red', nm || ' left (' || r.status || ') and the login is still active after ' || h::text || ' hours.', r.id::text) then
      n := n + 1;
      insert into public.w1c_exit_log (employee_id, from_status, to_status, action, reason, by_user) values (r.id, r.status, r.status, 'scan_alert', 'still active after ' || h::text || ' hours', auth.uid());
    end if;
  end loop;
  return jsonb_build_object('raised', n, 'hours', h);
end $$;
revoke all on function public._w1c_exit_scan_run() from public, anon, authenticated;

create or replace function public._w1c_exit_scan() returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return public._w1c_exit_scan_run();
end $$;
revoke all on function public._w1c_exit_scan() from public, anon; grant execute on function public._w1c_exit_scan() to authenticated;

-- ---------- screen data ----------
create or replace function public._w1c_exit_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'mode', coalesce(public.rule_txt('exit_revoke_mode'), 'off'), 'statuses', to_jsonb(public._w1c_exit_statuses()), 'alert_hours', public.rule_num('exit_alert_hours'),
    'devices', public.rule_on('exit_deactivate_devices'), 'can_keep', public.has_grant('exit_keep_access'), 'is_owner', public.is_owner(),
    'allowed_statuses', jsonb_build_array('resigned', 'terminated', 'retired', 'on_leave'));
end $$;
revoke all on function public._w1c_exit_settings() from public, anon; grant execute on function public._w1c_exit_settings() to authenticated;

create or replace function public._w1c_exit_settings_set(p_mode text, p_statuses text, p_alert_hours numeric, p_devices boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old jsonb; st text := lower(regexp_replace(coalesce(p_statuses, ''), '\s', '', 'g'));
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('off', 'alert', 'auto') then raise exception 'bad_mode'; end if;
  if not public._w1c_status_list_ok(st) then raise exception 'bad_statuses'; end if;
  if p_alert_hours is not null and not (p_alert_hours between 0 and 8760) then raise exception 'bad_hours'; end if;
  old := jsonb_build_object('mode', coalesce(public.rule_txt('exit_revoke_mode'), 'off'), 'statuses', public._w1c_exit_statuses(), 'alert_hours', public.rule_num('exit_alert_hours'), 'devices', public.rule_on('exit_deactivate_devices'));
  perform public.set_rule('exit_revoke_mode', to_jsonb(p_mode));
  perform public.set_rule('exit_revoke_statuses', to_jsonb(st));
  perform public.set_rule('exit_alert_hours', case when p_alert_hours is null then 'null'::jsonb else to_jsonb(p_alert_hours) end);
  perform public.set_rule('exit_deactivate_devices', to_jsonb(coalesce(p_devices, false)));
  perform public._w1c_audit('exit_settings_changed', 'rules', 'exit_*', jsonb_build_object('old', old,
    'new', jsonb_build_object('mode', p_mode, 'statuses', string_to_array(st, ','), 'alert_hours', p_alert_hours, 'devices', coalesce(p_devices, false)), 'note', left(p_note, 300)));
  return public._w1c_exit_settings();
end $$;
revoke all on function public._w1c_exit_settings_set(text, text, numeric, boolean, text) from public, anon; grant execute on function public._w1c_exit_settings_set(text, text, numeric, boolean, text) to authenticated;

-- people who left and still have an active login (the list the owner acts on)
create or replace function public._w1c_exit_open_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sts text[] := public._w1c_exit_statuses();
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name_en', e.full_name_en, 'name_bn', e.full_name_bn, 'status', e.status,
           'status_date', e.status_date, 'staff_id', pr.staff_id, 'login_status', pr.status, 'kept', public._w1c_exit_kept(e.id),
           'kept_reason', (select k.reason from public.w1c_exit_keep k where k.employee_id = e.id and k.ended_at is null)) order by e.status_date desc nulls last, e.employee_no)
      from public.employees e join public.profiles pr on pr.id = e.profile_id
     where (e.status = any (sts) and pr.status = 'active') or public._w1c_exit_kept(e.id)), '[]'::jsonb);
end $$;
revoke all on function public._w1c_exit_open_list() from public, anon; grant execute on function public._w1c_exit_open_list() to authenticated;

create or replace function public._w1c_exit_log_list(p_limit int default 100) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._emp_any(array['employee_manage'])) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', l.id, 'at', l.at, 'employee_id', l.employee_id, 'employee_no', e.employee_no, 'name_en', e.full_name_en, 'name_bn', e.full_name_bn,
           'from', l.from_status, 'to', l.to_status, 'action', l.action, 'grants_ended', l.grants_ended, 'lists_ended', l.lists_ended, 'devices_off', l.devices_off, 'reason', l.reason) x
      from public.w1c_exit_log l join public.employees e on e.id = l.employee_id order by l.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) q), '[]'::jsonb);
end $$;
revoke all on function public._w1c_exit_log_list(int) from public, anon; grant execute on function public._w1c_exit_log_list(int) to authenticated;

-- ===================== phase91.sql =====================
-- Phase 91 (bos91) - U-04 SALE RETURN CONTROL. Paste after phase90, paste-twice safe. Earlier phase files are not edited.
-- Package W1-C (Wave 1). New functions all carry the prefix _w1c_. sale_return and void_sale_return are integrator-owned and are NOT changed here:
-- the two hook lines they need are written in docs/integration/W1-C.md and proved on a scratch copy in phase91_test.sql.
--
-- WHAT THIS ADDS (everything is a setting, the owner edits it at any time, every change is an audit_log line)
--   Per item class (items.category) in w1c_return_class_rules: restock = restock | no_restock, window_hours (blank = no limit), receipt_required (blank = follow the global switch),
--   effective_from. A class without a row behaves exactly as today (goods go back on the shelf, any age, no receipt).
--   Global rules: return_needs_receipt (off), return_window_hours (blank = off, used by classes without their own window), return_expired_restock (allow [today] | writeoff | block).
--   At the moment a return is saved:
--     * the quantity that may not go back on the shelf is written off at once: the goods are put back by the existing return code, then written off through the
--       existing wastage source (stock_wastage, reason customer_return) at the SAME cost, so the books show Dr 5100 wastage / Cr inventory and balance;
--     * the cashier may choose to write off more (restock_qty per item), never to restock a no_restock class without an override;
--     * a return past its window, without the receipt number, or restocking an expired batch (mode block) is refused unless an override with a reason is given
--       by a person who holds the grant return_override (the owner always does; the owner can give it to anyone, also through an emergency request);
--       each override writes one audit_log line and one row in the Exceptions list.
--   Disposition of every return is kept (w1c_returns, w1c_return_lines, append-only) for the report "returns by reason: restocked or written off".
--   _w1c_sale_return(...) is the call for the screen. It works with or without the hook line; the hook makes a direct sale_return call obey the same rules.
-- NOTHING CHANGES until the owner adds a class rule or switches a global rule (defaults: no rows, receipt off, window blank, expired = allow).

do $g$ begin
  if to_regprocedure('public._w1c_present90()') is null then raise exception 'phase91 needs phase90'; end if;
  if to_regprocedure('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)') is null or to_regprocedure('public.void_sale_return(uuid,text)') is null
     or to_regprocedure('public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)') is null then
    raise exception 'phase91 needs the sale return and stock functions (phase12)';
  end if;
end $g$;

create or replace function public._w1c_present91() returns boolean language sql immutable as $$ select true $$;

-- same patch helper as phase90 (create or replace: harmless to repeat)
create or replace function public._w1c_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int; n int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2,3}$' then raise exception 'w1c_patch: bad marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    n := (length(def) - length(replace(def, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1);
    if n = 0 then raise exception 'w1c_patch: patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    if n > 1 then raise exception 'w1c_patch: patch site is not unique in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'w1c_patch: patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;
revoke all on function public._w1c_patch(regprocedure, text[], text) from public, anon, authenticated;

-- ---------- tables ----------
create table if not exists public.w1c_return_class_rules (
  class_code text primary key check (char_length(btrim(class_code)) between 1 and 60),
  restock text not null default 'restock' check (restock in ('restock', 'no_restock')),
  window_hours numeric check (window_hours is null or (window_hours > 0 and window_hours <= 100000)),
  receipt_required boolean,
  effective_from date not null default ((now() at time zone 'Asia/Dhaka')::date),
  active boolean not null default true,
  note text check (note is null or char_length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists audit_w1c_return_class_rules on public.w1c_return_class_rules;
create trigger audit_w1c_return_class_rules after insert or update on public.w1c_return_class_rules for each row execute function public.log_change('class_code');
drop trigger if exists w1c_return_class_rules_nodel on public.w1c_return_class_rules;
create trigger w1c_return_class_rules_nodel before delete on public.w1c_return_class_rules for each row execute function public.no_hard_delete();
alter table public.w1c_return_class_rules enable row level security;
drop policy if exists w1c_return_class_rules_read on public.w1c_return_class_rules;
create policy w1c_return_class_rules_read on public.w1c_return_class_rules for select to authenticated using (public.is_owner());
revoke all on table public.w1c_return_class_rules from anon, authenticated; grant select on table public.w1c_return_class_rules to authenticated;

create table if not exists public.w1c_returns (
  return_id uuid primary key references public.sale_returns(id),
  sale_id uuid not null references public.sales(id),
  location_id int not null,
  age_hours numeric, receipt_shown text,
  override boolean not null default false, override_kinds text[], override_reason text,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.w1c_return_lines (
  id bigserial primary key,
  return_id uuid not null references public.w1c_returns(return_id),
  item_id uuid not null, class_code text, unit text,
  qty numeric not null, restock_qty numeric not null, writeoff_qty numeric not null,
  restock_base numeric not null default 0, writeoff_base numeric not null default 0, writeoff_value numeric not null default 0,
  decision text not null check (decision in ('restocked', 'written_off', 'split', 'not_tracked')),
  basis text not null check (basis in ('default', 'class_rule', 'cashier_choice', 'expired_batch', 'override')),
  wastage_ids uuid[] not null default '{}'
);
create index if not exists w1c_return_lines_ret on public.w1c_return_lines (return_id);
drop trigger if exists w1c_returns_ro on public.w1c_returns;
create trigger w1c_returns_ro before update or delete on public.w1c_returns for each row execute function public._w1c_append_only();
drop trigger if exists w1c_return_lines_ro on public.w1c_return_lines;
create trigger w1c_return_lines_ro before update or delete on public.w1c_return_lines for each row execute function public._w1c_append_only();
alter table public.w1c_returns enable row level security;
alter table public.w1c_return_lines enable row level security;
drop policy if exists w1c_returns_read on public.w1c_returns;
create policy w1c_returns_read on public.w1c_returns for select to authenticated using (public.can_loc(location_id) and (public.is_owner() or public.has_grant('sale_return', location_id)));
drop policy if exists w1c_return_lines_read on public.w1c_return_lines;
create policy w1c_return_lines_read on public.w1c_return_lines for select to authenticated
  using (exists (select 1 from public.w1c_returns h where h.return_id = w1c_return_lines.return_id and public.can_loc(h.location_id) and (public.is_owner() or public.has_grant('sale_return', h.location_id))));
revoke all on table public.w1c_returns, public.w1c_return_lines from anon, authenticated; grant select on table public.w1c_returns, public.w1c_return_lines to authenticated;
revoke all on sequence public.w1c_return_lines_id_seq from anon, authenticated;

-- ---------- settings, grant, wastage reason (own keys only, on conflict do nothing) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('return_needs_receipt', 'pos', 'switch', 'false'::jsonb, null, null, null, null,
  'A sale return must show the receipt number', 'A sale return must show the receipt number', 'A sale return must show the receipt number',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this',
  'Off = today: any return of a recorded sale is accepted. On = the receipt number must be typed and match the sale. A class can override this', 905),
 ('return_window_hours', 'pos', 'number', null, 'hours', null, 1, 87600,
  'Return window (hours after the sale)', 'Return window (hours after the sale)', 'Return window (hours after the sale)',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason',
  'Blank = no limit (today). Used for every item class that has no window of its own. Past the window a return needs an override with a reason', 906),
 ('return_expired_restock', 'pos', 'choice', '"allow"'::jsonb, null, '["allow","writeoff","block"]'::jsonb, null, null,
  'Returned goods from an expired batch', 'Returned goods from an expired batch', 'Returned goods from an expired batch',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason',
  'allow = back on the shelf (today); writeoff = written off automatically; block = refused unless an override with a reason', 907)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
values ('return_override', 'pos', 905, 'Approve a sale return outside the return rules', 'Approve a sale return outside the return rules', 'Approve a sale return outside the return rules', 'window')
on conflict (grant_code) do nothing;

do $o$ begin
  insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
    values ('wastage_reasons', 'customer_return', 'Customer return, not for resale', 'Customer return, not for resale', 'Customer return, not for resale', 905, true)
    on conflict (list_code, value_code) do nothing;
exception when others then
  raise notice 'phase91: the wastage reason customer_return could not be added (%): add it by hand in Lists', sqlerrm;
end $o$;

-- ---------- helpers ----------
create or replace function public._w1c_class_of(p_item uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(btrim(i.category), ''), '-') from public.items i where i.id = p_item $$;
revoke all on function public._w1c_class_of(uuid) from public, anon, authenticated;

-- ---------- the check (read only): what does the rule say about this return? ----------
-- p_lines = [{item_id, qty}], p_restock = [{item_id, restock_qty}] or null (null = the class default for every item)
create or replace function public._w1c_return_eval(p_sale uuid, p_lines jsonb, p_restock jsonb, p_receipt text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales; ln record; rl record; cr public.w1c_return_class_rules; has_cr boolean; cls text; q numeric; dflt numeric; arg numeric; given boolean; rq numeric; win numeric; need boolean; rec_ok boolean;
        age numeric; lines_out jsonb := '[]'::jsonb; allv text[] := '{}'; lv text[]; today date := (now() at time zone 'Asia/Dhaka')::date;
        gwin numeric := public.rule_num('return_window_hours'); gneed boolean := public.rule_on('return_needs_receipt');
        uuid_re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; qty_re constant text := '^[0-9]{1,9}(\.[0-9]{1,6})?$';
begin
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  age := round(extract(epoch from (now() - s.sold_at)) / 3600, 2);
  rec_ok := regexp_replace(coalesce(p_receipt, ''), '[^0-9]', '', 'g') = s.receipt::text;
  if p_restock is not null and jsonb_typeof(p_restock) not in ('array', 'null') then raise exception 'return_bad_restock_qty'; end if;
  if p_restock is not null and jsonb_typeof(p_restock) = 'array' then
    for rl in select e from jsonb_array_elements(p_restock) e loop
      if jsonb_typeof(rl.e) <> 'object' or coalesce(rl.e ->> 'item_id', '') !~ uuid_re or coalesce(rl.e ->> 'restock_qty', '') !~ qty_re then raise exception 'return_bad_restock_qty'; end if;
      if not exists (select 1 from jsonb_array_elements(p_lines) x where x ->> 'item_id' = rl.e ->> 'item_id') then raise exception 'return_bad_restock_qty'; end if;
    end loop;
  end if;
  for ln in select e ->> 'item_id' iid, sum((e ->> 'qty')::numeric) q from jsonb_array_elements(p_lines) e
             where jsonb_typeof(e) = 'object' and coalesce(e ->> 'item_id', '') ~ uuid_re and coalesce(e ->> 'qty', '') ~ qty_re group by 1 order by 1 loop
    q := ln.q;
    cls := public._w1c_class_of(ln.iid::uuid);
    select * into cr from public.w1c_return_class_rules where class_code = cls and active and effective_from <= today;
    has_cr := found;
    dflt := case when has_cr and cr.restock = 'no_restock' then 0 else q end;
    arg := null;
    if p_restock is not null and jsonb_typeof(p_restock) = 'array' then
      select (x ->> 'restock_qty')::numeric into arg from jsonb_array_elements(p_restock) x where x ->> 'item_id' = ln.iid limit 1;
    end if;
    given := arg is not null;
    if given and arg > q + 0.00005 then raise exception 'return_bad_restock_qty'; end if;
    rq := coalesce(arg, dflt);
    lv := '{}';
    if has_cr and cr.restock = 'no_restock' and rq > 0.00005 then lv := array_append(lv, 'return_restock_not_allowed'::text); end if;
    win := case when has_cr and cr.window_hours is not null then cr.window_hours else gwin end;
    if win is not null and age > win then lv := array_append(lv, 'return_window_exceeded'::text); end if;
    need := coalesce(case when has_cr then cr.receipt_required end, gneed);
    if need and not rec_ok then lv := array_append(lv, 'return_receipt_required'::text); end if;
    allv := allv || lv;
    lines_out := lines_out || jsonb_build_object('item_id', ln.iid, 'class', cls, 'qty', q, 'default_restock_qty', dflt, 'restock_qty', rq, 'given', given,
      'restock_rule', case when has_cr then cr.restock else 'restock' end, 'window_hours', win, 'receipt_needed', need, 'violations', to_jsonb(lv));
  end loop;
  return jsonb_build_object('age_hours', age, 'receipt_ok', rec_ok, 'lines', lines_out,
    'violations', coalesce((select jsonb_agg(distinct v) from unnest(allv) v), '[]'::jsonb));
end $$;
revoke all on function public._w1c_return_eval(uuid, jsonb, jsonb, text) from public, anon, authenticated;

-- write off a quantity of returned goods through the existing wastage source, at the cost of the return row (so the books net to the loss)
create or replace function public._w1c_writeoff(p_item uuid, p_loc int, p_bq numeric, p_batch bigint, p_cost numeric, p_note text) returns uuid
language plpgsql security definer set search_path = public as $$
declare wid uuid := gen_random_uuid(); lid bigint;
begin
  lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, p_cost, p_batch, now(), left(p_note, 200), null, 'none');
  insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, batch_id, ledger_id, created_by, created_staff)
    values (wid, p_item, p_loc, p_bq, 'customer_return', left(p_note, 200), p_batch, lid, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return wid;
end $$;
revoke all on function public._w1c_writeoff(uuid, int, numeric, bigint, numeric, text) from public, anon, authenticated;

-- ---------- the step that runs when a return is saved (hook in sale_return, or the wrapper below) ----------
create or replace function public._w1c_return_finish(p_return uuid, p_restock jsonb default null, p_receipt text default null, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sale_returns; s public.sales; ev jsonb; v text[]; ov_reason text := nullif(left(btrim(coalesce(p_override, '')), 300), ''); ov boolean := false;
        mode text := coalesce(public.rule_txt('return_expired_restock'), 'allow'); ln jsonb; it public.items; plan jsonb := '[]'::jsonb; pl jsonb; rw record;
        total_back numeric; wo numeric; exp_tot numeric; remaining numeric; chunk numeric; basis text; bad_exp boolean := false; wids uuid[]; wid uuid; wval numeric; rq_final numeric; rbase numeric;
        n_wo int := 0; n_rs int := 0; dec text; lvl text := 'yellow';
begin
  select * into r from public.sale_returns where id = p_return;
  if not found then raise exception 'not_found'; end if;
  if exists (select 1 from public.w1c_returns h where h.return_id = p_return) then return jsonb_build_object('skipped', 'done'); end if;
  select * into s from public.sales where id = r.sale_id;
  ev := public._w1c_return_eval(r.sale_id, r.lines, p_restock, p_receipt);
  select coalesce(array_agg(x), '{}') into v from jsonb_array_elements_text(ev -> 'violations') x;

  -- plan: how much of each item goes back on the shelf, how much is written off
  for ln in select e from jsonb_array_elements(ev -> 'lines') e loop
    select * into it from public.items where id = (ln ->> 'item_id')::uuid;
    if it.tracked is not true then
      plan := plan || jsonb_build_object('item_id', it.id, 'class', ln ->> 'class', 'qty', (ln ->> 'qty')::numeric, 'restock_qty', (ln ->> 'restock_qty')::numeric, 'wo', 0, 'total_back', 0, 'basis', 'default', 'decision', 'not_tracked');
      continue;
    end if;
    select coalesce(sum(l.qty_delta), 0) into total_back from public.stock_ledger l where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = it.id;
    wo := round(total_back * (1 - least(1, (ln ->> 'restock_qty')::numeric / nullif((ln ->> 'qty')::numeric, 0))), 4);
    basis := case when (ln ->> 'given')::boolean then 'cashier_choice' when ln ->> 'restock_rule' = 'no_restock' then 'class_rule' else 'default' end;
    select coalesce(sum(l.qty_delta), 0) into exp_tot from public.stock_ledger l join public.stock_batches b on b.id = l.batch_id
      where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = it.id and b.expires_at is not null and b.expires_at <= now();
    if exp_tot > 0.0005 and mode = 'writeoff' and wo < exp_tot then wo := exp_tot; basis := 'expired_batch'; end if;
    if exp_tot > 0.0005 and mode = 'block' and exp_tot - least(wo, exp_tot) > 0.0005 then bad_exp := true; end if;
    plan := plan || jsonb_build_object('item_id', it.id, 'class', ln ->> 'class', 'qty', (ln ->> 'qty')::numeric, 'restock_qty', (ln ->> 'restock_qty')::numeric, 'wo', wo, 'total_back', total_back, 'basis', basis, 'decision', null, 'rs_viol', ln -> 'violations' @> '"return_restock_not_allowed"');
  end loop;
  if bad_exp then v := array_append(v, 'return_expired_restock'::text); end if;

  -- rule check: a violation needs an override (reason + grant), otherwise the whole return is refused
  if array_length(v, 1) is not null then
    if ov_reason is null or char_length(ov_reason) < 3 then raise exception '%', v[1]; end if;
    if not public.has_grant('return_override', s.location_id) then raise exception 'return_override_not_allowed'; end if;
    ov := true;
    if 'return_expired_restock' = any (v) then lvl := 'red'; end if;
  end if;

  insert into public.w1c_returns (return_id, sale_id, location_id, age_hours, receipt_shown, override, override_kinds, override_reason, created_by)
    values (r.id, r.sale_id, r.location_id, (ev ->> 'age_hours')::numeric, left(nullif(btrim(coalesce(p_receipt, '')), ''), 30), ov, case when ov then v end, case when ov then ov_reason end, auth.uid());

  for pl in select e from jsonb_array_elements(plan) e loop
    wo := (pl ->> 'wo')::numeric; wids := '{}'; wval := 0; remaining := wo; total_back := (pl ->> 'total_back')::numeric;
    if remaining > 0.00005 then
      for rw in select l.id, l.batch_id, l.qty_delta, l.unit_cost, coalesce(b.expires_at <= now(), false) as expd
                   from public.stock_ledger l left join public.stock_batches b on b.id = l.batch_id
                  where l.ref_type = 'sale_return' and l.ref_id = r.id::text and l.reason = 'sale_return' and l.item_id = (pl ->> 'item_id')::uuid
                  order by coalesce(b.expires_at <= now(), false) desc, l.id loop
        exit when remaining <= 0.00005;
        chunk := least(rw.qty_delta, remaining);
        wid := public._w1c_writeoff((pl ->> 'item_id')::uuid, r.location_id, chunk, rw.batch_id, rw.unit_cost, 'customer return, receipt ' || s.receipt::text);
        wids := wids || wid; remaining := remaining - chunk; wval := wval + round(chunk * coalesce(rw.unit_cost, 0), 2);
      end loop;
    end if;
    rbase := total_back - (wo - greatest(remaining, 0));
    rq_final := case when total_back > 0 then round((pl ->> 'qty')::numeric * rbase / total_back, 6) else (pl ->> 'restock_qty')::numeric end;
    dec := case when pl ->> 'decision' = 'not_tracked' or total_back <= 0.00005 then 'not_tracked' when (wo - greatest(remaining, 0)) <= 0.00005 then 'restocked' when rbase <= 0.00005 then 'written_off' else 'split' end;
    if dec in ('written_off', 'split') then n_wo := n_wo + 1; end if;
    if dec in ('restocked', 'split') then n_rs := n_rs + 1; end if;
    insert into public.w1c_return_lines (return_id, item_id, class_code, unit, qty, restock_qty, writeoff_qty, restock_base, writeoff_base, writeoff_value, decision, basis, wastage_ids)
      values (r.id, (pl ->> 'item_id')::uuid, pl ->> 'class', (select e ->> 'unit' from jsonb_array_elements(r.lines) e where e ->> 'item_id' = pl ->> 'item_id' limit 1),
              (pl ->> 'qty')::numeric, rq_final, greatest((pl ->> 'qty')::numeric - rq_final, 0), greatest(rbase, 0), wo - greatest(remaining, 0), wval, dec,
              case when ov and coalesce((pl ->> 'rs_viol')::boolean, false) then 'override' else pl ->> 'basis' end, wids);
  end loop;

  if n_wo > 0 then
    perform public._w1c_audit('return_writeoff', 'sale_returns', r.id::text, jsonb_build_object('sale', r.sale_id, 'receipt', s.receipt, 'lines', (select jsonb_agg(jsonb_build_object('item', x.item_id, 'class', x.class_code,
      'writeoff_qty', x.writeoff_qty, 'value', x.writeoff_value, 'basis', x.basis)) from public.w1c_return_lines x where x.return_id = r.id and x.writeoff_base > 0)));
  end if;
  if ov then
    perform public._w1c_audit('return_override', 'sale_returns', r.id::text, jsonb_build_object('sale', r.sale_id, 'receipt', s.receipt, 'rules_broken', to_jsonb(v), 'reason', ov_reason, 'amount', r.amount, 'age_hours', ev -> 'age_hours'));
    perform public._w1c_exc(r.location_id, 'POS', 'return_override', lvl, 'Receipt ' || s.receipt::text || ': a return was accepted outside the return rules (' || array_to_string(v, ', ') || '). Reason: ' || ov_reason, r.id::text, r.amount, s.sale_date);
  end if;
  return jsonb_build_object('return', r.id, 'written_off_items', n_wo, 'restocked_items', n_rs, 'override', ov, 'rules_broken', to_jsonb(v));
end $$;
revoke all on function public._w1c_return_finish(uuid, jsonb, text, text) from public, anon, authenticated;

-- the line sale_return calls (reads what the wrapper stored for this transaction; a direct call has nothing stored and gets the defaults)
create or replace function public._w1c_return_hook(p_return uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare a jsonb := nullif(current_setting('w1c.return_args', true), '')::jsonb;
begin
  return public._w1c_return_finish(p_return, case when jsonb_typeof(a -> 'restock') = 'array' then a -> 'restock' end, a ->> 'receipt', a ->> 'override');
end $$;
revoke all on function public._w1c_return_hook(uuid) from public, anon, authenticated;

-- the line void_sale_return calls: a return that wrote goods off cannot be voided (the write-off cannot be undone in the books; correct it with a stock adjustment)
create or replace function public._w1c_return_void_guard(p_return uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.w1c_return_lines x where x.return_id = p_return and x.writeoff_base > 0.00005) then raise exception 'return_written_off' using hint = 'Goods of this return were written off; fix with a stock adjustment'; end if;
end $$;
revoke all on function public._w1c_return_void_guard(uuid) from public, anon, authenticated;

-- ---------- the call for the screen ----------
create or replace function public._w1c_sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text default null, p_refund_mode text default null, p_wallet text default null, p_ref text default null,
                                                   p_restock_lines jsonb default null, p_receipt_no text default null, p_override_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; fin jsonb; rid uuid;
begin
  perform set_config('w1c.return_args', jsonb_build_object('restock', p_restock_lines, 'receipt', p_receipt_no, 'override', p_override_reason)::text, true);
  res := public.sale_return(p_client, p_sale, p_lines, p_reason, p_note, p_refund_mode, p_wallet, p_ref);
  if coalesce((res ->> 'dup')::boolean, false) then perform set_config('w1c.return_args', '', true); return res; end if;
  rid := (res ->> 'id')::uuid;
  fin := public._w1c_return_finish(rid, case when jsonb_typeof(p_restock_lines) = 'array' then p_restock_lines end, p_receipt_no, p_override_reason);   -- skipped when the hook already did it
  if fin ? 'skipped' then
    fin := (select jsonb_build_object('return', h.return_id, 'override', h.override, 'rules_broken', coalesce(to_jsonb(h.override_kinds), '[]'::jsonb),
              'written_off_items', (select count(*) from public.w1c_return_lines x where x.return_id = h.return_id and x.writeoff_base > 0.00005),
              'restocked_items', (select count(*) from public.w1c_return_lines x where x.return_id = h.return_id and x.restock_base > 0.00005)) from public.w1c_returns h where h.return_id = rid);
  end if;
  perform set_config('w1c.return_args', '', true);
  return res || jsonb_build_object('w1c', fin);
end $$;
revoke all on function public._w1c_sale_return(uuid, uuid, jsonb, text, text, text, text, text, jsonb, text, text) from public, anon;
grant execute on function public._w1c_sale_return(uuid, uuid, jsonb, text, text, text, text, text, jsonb, text, text) to authenticated;

-- preview for the picker: defaults and rule hits before the cashier saves (read only)
create or replace function public._w1c_return_preview(p_sale uuid, p_lines jsonb, p_restock jsonb default null, p_receipt text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales; ev jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) or not (public.has_grant('sale_return', s.location_id) or public.has_grant('return_override', s.location_id)) then raise exception 'not allowed'; end if;
  ev := public._w1c_return_eval(p_sale, p_lines, p_restock, p_receipt);
  return ev || jsonb_build_object('can_override', public.has_grant('return_override', s.location_id), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'));
end $$;
revoke all on function public._w1c_return_preview(uuid, jsonb, jsonb, text) from public, anon; grant execute on function public._w1c_return_preview(uuid, jsonb, jsonb, text) to authenticated;

-- ---------- settings screen ----------
create or replace function public._w1c_return_settings() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'needs_receipt', public.rule_on('return_needs_receipt'), 'window_hours', public.rule_num('return_window_hours'), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('class_code', c.cls, 'items', c.n, 'sample_en', c.sample_en, 'sample_bn', c.sample_bn,
         'configured', cr.class_code is not null and cr.active, 'restock', coalesce(cr.restock, 'restock'), 'window_hours', cr.window_hours, 'receipt_required', cr.receipt_required,
         'effective_from', cr.effective_from, 'active', coalesce(cr.active, false), 'note', cr.note,
         'perishable', exists (select 1 from public.shelf_life_rules z where z.active and (z.category = c.cls or z.item_id in (select i.id from public.items i where coalesce(nullif(btrim(i.category), ''), '-') = c.cls)))
                       or exists (select 1 from public.stock_batches b join public.items i on i.id = b.item_id where coalesce(nullif(btrim(i.category), ''), '-') = c.cls and b.expires_at is not null)) order by c.cls)
       from (select coalesce(nullif(btrim(i.category), ''), '-') cls, count(*) n, min(i.name_en) sample_en, min(i.name_bn) sample_bn from public.items i where i.is_active group by 1) c
       left join public.w1c_return_class_rules cr on cr.class_code = c.cls), '[]'::jsonb));
end $$;
revoke all on function public._w1c_return_settings() from public, anon; grant execute on function public._w1c_return_settings() to authenticated;

create or replace function public._w1c_return_class_set(p_class text, p_restock text, p_window numeric, p_receipt boolean, p_effective date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old public.w1c_return_class_rules; cls text := nullif(btrim(coalesce(p_class, '')), ''); eff date := coalesce(p_effective, public._dhaka_today());
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if cls is null or char_length(cls) > 60 then raise exception 'bad_class'; end if;
  if not exists (select 1 from public.items i where coalesce(nullif(btrim(i.category), ''), '-') = cls) then raise exception 'unknown_class'; end if;
  if p_restock is null or p_restock not in ('restock', 'no_restock') then raise exception 'bad_restock'; end if;
  if p_window is not null and not (p_window > 0 and p_window <= 100000) then raise exception 'bad_window'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  select * into old from public.w1c_return_class_rules where class_code = cls;
  insert into public.w1c_return_class_rules (class_code, restock, window_hours, receipt_required, effective_from, active, note, updated_by, updated_at)
    values (cls, p_restock, p_window, p_receipt, eff, true, nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (class_code) do update set restock = excluded.restock, window_hours = excluded.window_hours, receipt_required = excluded.receipt_required,
      effective_from = excluded.effective_from, active = true, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  perform public._w1c_audit('return_rule_changed', 'w1c_return_class_rules', cls, jsonb_build_object('old', case when old.class_code is null then null else to_jsonb(old) end,
    'new', jsonb_build_object('restock', p_restock, 'window_hours', p_window, 'receipt_required', p_receipt, 'effective_from', eff, 'note', p_note)));
  return jsonb_build_object('class', cls, 'saved', true);
end $$;
revoke all on function public._w1c_return_class_set(text, text, numeric, boolean, date, text) from public, anon; grant execute on function public._w1c_return_class_set(text, text, numeric, boolean, date, text) to authenticated;

-- switch a class rule off (the row stays; nothing is deleted)
create or replace function public._w1c_return_class_off(p_class text, p_reason text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n int; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if v_reason is null or char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  update public.w1c_return_class_rules set active = false, updated_by = auth.uid(), updated_at = now() where class_code = p_class and active;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_found'; end if;
  perform public._w1c_audit('return_rule_off', 'w1c_return_class_rules', p_class, jsonb_build_object('reason', v_reason));
  return jsonb_build_object('class', p_class, 'active', false);
end $$;
revoke all on function public._w1c_return_class_off(text, text) from public, anon; grant execute on function public._w1c_return_class_off(text, text) to authenticated;

create or replace function public._w1c_return_global_set(p_needs_receipt boolean, p_window numeric, p_expired text) returns jsonb language plpgsql security definer set search_path = public as $$
declare old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_expired is null or p_expired not in ('allow', 'writeoff', 'block') then raise exception 'bad_mode'; end if;
  if p_window is not null and not (p_window between 1 and 87600) then raise exception 'bad_window'; end if;
  old := jsonb_build_object('needs_receipt', public.rule_on('return_needs_receipt'), 'window_hours', public.rule_num('return_window_hours'), 'expired_mode', coalesce(public.rule_txt('return_expired_restock'), 'allow'));
  perform public.set_rule('return_needs_receipt', to_jsonb(coalesce(p_needs_receipt, false)));
  perform public.set_rule('return_window_hours', case when p_window is null then 'null'::jsonb else to_jsonb(p_window) end);
  perform public.set_rule('return_expired_restock', to_jsonb(p_expired));
  perform public._w1c_audit('return_rules_changed', 'rules', 'return_*', jsonb_build_object('old', old, 'new', jsonb_build_object('needs_receipt', coalesce(p_needs_receipt, false), 'window_hours', p_window, 'expired_mode', p_expired)));
  return public._w1c_return_settings();
end $$;
revoke all on function public._w1c_return_global_set(boolean, numeric, text) from public, anon; grant execute on function public._w1c_return_global_set(boolean, numeric, text) to authenticated;

-- ---------- report: returns by reason, restocked or written off ----------
create or replace function public._w1c_return_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, public._dhaka_today() - 30); t date := coalesce(p_to, public._dhaka_today());
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('sale_return', p_loc) or public.has_grant('return_override', p_loc)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('from', f, 'to', t,
    'by_reason', coalesce((select jsonb_agg(z order by (z ->> 'reason')) from (
        select jsonb_build_object('reason', sr.reason_code, 'class', l.class_code, 'returns', count(distinct sr.id), 'lines', count(*),
               'restocked_qty', coalesce(sum(l.restock_qty), 0), 'written_off_qty', coalesce(sum(l.writeoff_qty), 0), 'written_off_value', coalesce(sum(l.writeoff_value), 0)) z
          from public.sale_returns sr join public.w1c_returns h on h.return_id = sr.id join public.w1c_return_lines l on l.return_id = h.return_id
         where sr.status = 'done' and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc) and public.can_loc(sr.location_id)
         group by sr.reason_code, l.class_code) q), '[]'::jsonb),
    'overrides', coalesce((select jsonb_agg(jsonb_build_object('return_id', h.return_id, 'at', h.created_at, 'kinds', h.override_kinds, 'reason', h.override_reason, 'by', h.created_by))
        from public.w1c_returns h join public.sale_returns sr on sr.id = h.return_id
       where h.override and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc) and public.can_loc(sr.location_id)), '[]'::jsonb),
    'not_covered', (select count(*) from public.sale_returns sr where sr.status = 'done' and (sr.created_at at time zone 'Asia/Dhaka')::date between f and t and (p_loc is null or sr.location_id = p_loc)
                      and public.can_loc(sr.location_id) and not exists (select 1 from public.w1c_returns h where h.return_id = sr.id)));
end $$;
revoke all on function public._w1c_return_report(date, date, int) from public, anon; grant execute on function public._w1c_return_report(date, date, int) to authenticated;

-- ===================== phase92.sql =====================
-- Phase 92 (bos92) - ONE PROFIT NUMBER (UNIFIED_BUILD_PLAN U-05, package W1-D). Paste after phase87, paste-twice safe. Earlier phase files are not edited.
-- WHY: the management profit (the _p27_pl extraction that feeds the branch P&L L1/L3, the owner sheet L4, break-even L5, the staff-cost ratio, partner_calculate and the owner board)
--      leaves out wastage, count shrinkage, transit loss, cash short and operating cost that was paid by a supplier bill, and it counts factory overhead twice when conversion costing
--      is on (the overhead is in the expenses AND inside the cost of the goods sold). The journal has most of these. Two different profits are two different truths.
-- WHAT THIS FILE DOES (everything is OFF by default; with every setting at its default NO historic figure changes - proved by tests/sql/w1d_before_after.sh)
--   1. Settings (owner, any time, every change is written to audit_log by the existing rules trigger):
--        profit_one_number_on      master switch, default OFF      count the extra rows below in the management profit
--        profit_losses_from        date, default blank             count the extra rows only from this date (blank = every date)
--        profit_loss_wastage / profit_loss_count / profit_loss_transit / profit_loss_cashshort / profit_loss_billopex / profit_overhead_once   one switch per row, default ON (they act only while the master is ON)
--        profit_source             management (default) | ledger  where partner shares take their profit from (acts only while the master is ON)
--   2. _w1d_pl_rows / _w1d_pl_extra: the extra rows by month and place. _p27_pl gets ONE more union (text patch, marker bos92) so ONE function feeds L1, L3, L4, L5, T4,
--      partner_calculate and (through a one-line patch) the partner preview c_partner_month_split. Wastage = stock-ledger cost; count shrinkage = negative count_adjust at ledger cost;
--      transit loss = written-off events of phase81; cash short = approved cases (a short booked as staff receivable is not a loss); supplier-bill opex = the consumable / unclassified
--      part of posted purchase bills; absorbed overhead = conversion cost of finished production runs, SUBTRACTED from the expenses (it is already inside the cost of goods).
--   3. Exception path (needs a written reason, writes audit_log and one yellow line in the Exceptions list): profit_exclude / profit_exclusion_revoke leave ONE named loss out of the management profit.
--   4. profit_recon(from, to, place): management profit versus journal profit, the difference by named cause, and what is still unexplained. profit_exclusions_list().
--   5. Every partner settlement stores the basis it used: partner_calculate returns profit_basis (stored in the settlement calc).
-- NOT DONE (listed in docs/integration/W1-D.md): the ledger source feeds partner shares only (not L1/L3); count surplus is not valued (the ledger row has no cost).
-- !! Re-pasting phase 27, 44, 50, 72, 82, 85 or 86 removes the bos92 patches: paste this file again. The integrator's last phase of the wave must paste it again too.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase92 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public.partner_calculate(bigint,date,date,jsonb)') is null
     or to_regprocedure('public.c_partner_month_split(date)') is null or to_regprocedure('public._d_wallet_fee_rows(date,date,integer[])') is null
     or to_regprocedure('public._acct_purchase_alloc(uuid)') is null or to_regclass('public.shortage_transit_events') is null or to_regclass('public.shortage_cash_cases') is null
     or to_regclass('public.production_runs') is null or to_regprocedure('public._stock_exc(integer,text,text,text,text,uuid,date,text,numeric)') is null then
    raise exception 'phase92 needs the shared functions and tables of phases 10, 27, 44, 52, 72, 74, 81, 82, 83';
  end if;
end $g$;

create or replace function public._w1d_p92_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (the phase87 _m_patch idea with the package's own marker) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist, otherwise the paste STOPS and nothing is half changed. Already patched (marker present) = no-op.
create or replace function public._w1d_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or p_marker !~ '^bos[0-9]{2}$' then raise exception 'bad_marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception '% patch site not found in %: %', p_marker, p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception '% patch of % carries no marker', p_marker, p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- settings (rules). Labels are English only (owner rule 5). All defaults keep today's behaviour. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('profit_one_number_on', 'reports', 'switch', 'false', null, null, null, null,
  'One profit number: count losses in the profit', 'One profit number: count losses in the profit', 'One profit number: count losses in the profit',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.',
  'Off keeps every profit figure exactly as it is today. On adds the rows below to the profit shown for branches, the owner sheet, break-even and partner shares.', 790),
 ('profit_losses_from', 'reports', 'text', null, null, null, null, null,
  'Count these extra profit rows from this date', 'Count these extra profit rows from this date', 'Count these extra profit rows from this date',
  'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.', 'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.',
  'Type a date as YYYY-MM-DD. Blank counts every date. Use it to keep closed months as they were.', 791),
 ('profit_loss_wastage', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts wasted stock', 'Profit counts wasted stock', 'Profit counts wasted stock',
  'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.', 'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.',
  'Stock written off as wastage, at its ledger cost. Acts only while the master switch is on.', 792),
 ('profit_loss_count', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts stock count shortages', 'Profit counts stock count shortages', 'Profit counts stock count shortages',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.',
  'Stock that a physical count found missing, at its ledger cost. A surplus is not valued. Acts only while the master switch is on.', 793),
 ('profit_loss_transit', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts goods lost in transit', 'Profit counts goods lost in transit', 'Profit counts goods lost in transit',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.',
  'Transit shortages that were written off. A claim to the carrier is not a loss until it is written off. Acts only while the master switch is on.', 794),
 ('profit_loss_cashshort', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts cash short and over', 'Profit counts cash short and over', 'Profit counts cash short and over',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.',
  'Approved cash short or over cases. A short that is booked as a staff receivable is not a loss. Acts only while the master switch is on.', 795),
 ('profit_loss_billopex', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts running costs paid by supplier bill', 'Profit counts running costs paid by supplier bill', 'Profit counts running costs paid by supplier bill',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.',
  'The consumable and unclassified part of posted purchase bills (a purchase return reduces it). Acts only while the master switch is on.', 796),
 ('profit_overhead_once', 'reports', 'switch', 'true', null, null, null, null,
  'Profit counts factory overhead once', 'Profit counts factory overhead once', 'Profit counts factory overhead once',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.',
  'Overhead that conversion costing already put inside the cost of finished goods is taken out of the expenses. Acts only while the master switch is on.', 797),
 ('profit_source', 'reports', 'choice', '"management"', null, '["management","ledger"]', null, null,
  'Partner shares take the profit from', 'Partner shares take the profit from', 'Partner shares take the profit from',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.',
  'management = the management profit (one function for every report). ledger = the journal profit. Acts only while the master switch is on. Choose ledger only when the journal is posted every day and two clean months agree.', 798)
on conflict (key) do nothing;

-- ---------- the exception path: leave ONE named loss out of the management profit (reason required, audit_log, Exceptions list) ----------
create table if not exists public.profit_row_exclusions (
  id bigserial primary key,
  cause text not null check (cause in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed')),
  source_id text not null check (length(source_id) between 1 and 80),
  amount numeric, row_date date, location_id integer,
  reason text not null check (length(btrim(reason)) between 5 and 300),
  status text not null default 'active' check (status in ('active', 'revoked')),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  revoked_by uuid, revoked_at timestamptz, revoke_reason text check (revoke_reason is null or length(btrim(revoke_reason)) between 5 and 300)
);
create unique index if not exists profit_row_exclusions_one on public.profit_row_exclusions (cause, source_id) where status = 'active';
drop trigger if exists profit_row_exclusions_nodel on public.profit_row_exclusions;
create trigger profit_row_exclusions_nodel before delete on public.profit_row_exclusions for each row execute function public.no_hard_delete();
drop trigger if exists audit_profit_row_exclusions on public.profit_row_exclusions;
create trigger audit_profit_row_exclusions after insert or update on public.profit_row_exclusions for each row execute function public.log_change('id');
alter table public.profit_row_exclusions enable row level security;
revoke all on public.profit_row_exclusions from public, anon, authenticated;

create or replace function public._w1d_view() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;
create or replace function public._w1d_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
drop policy if exists profit_row_exclusions_read on public.profit_row_exclusions;
create policy profit_row_exclusions_read on public.profit_row_exclusions for select to authenticated using (public._w1d_view());
grant select on public.profit_row_exclusions to authenticated;
grant execute on function public._w1d_view(), public._w1d_mgr() to authenticated;

-- ---------- the extra rows ----------
create or replace function public._w1d_losses_from() returns date language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('profit_losses_from');
begin
  if t is null or t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

-- every candidate row, no setting looked at. amt: a LOSS is positive, absorbed overhead is negative (it lowers the expenses).
create or replace function public._w1d_pl_rows(d1 date, d2 date, locs integer[])
returns table (cause text, source_id text, d date, loc integer, amt numeric)
language sql stable security definer set search_path = public as $$
  -- wastage: stock leaves at its ledger cost (cost 0 or empty = unknown, never guessed; same rule as the journal source 'wastage')
  select 'wastage'::text, l.ref_id, (l.made_at at time zone 'Asia/Dhaka')::date, l.location_id, round(-l.qty_delta * l.unit_cost, 2)
    from public.stock_ledger l
   where l.ref_type = 'wastage' and l.reason = 'wastage' and l.qty_delta < 0 and coalesce(l.unit_cost, 0) > 0
     and not exists (select 1 from public.stock_ledger r where r.reverses_id = l.id)
     and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  -- count shrinkage: a physical count found less than the book. A surplus carries no cost on its ledger row, so it is not valued.
  select 'count_shrink'::text, l.id::text, (l.made_at at time zone 'Asia/Dhaka')::date, l.location_id, round(-l.qty_delta * l.unit_cost, 2)
    from public.stock_ledger l
   where l.reason = 'count_adjust' and l.qty_delta < 0 and coalesce(l.unit_cost, 0) > 0
     and not exists (select 1 from public.stock_ledger r where r.reverses_id = l.id)
     and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and l.location_id = any (locs)
  union all
  -- transit loss: only the written-off events (a claim to the carrier is a receivable, not a loss)
  select 'transit_loss'::text, e.id::text, e.event_date, e.location_id, e.amount
    from public.shortage_transit_events e
   where e.kind = 'writeoff' and e.event_date between d1 and d2 and e.location_id = any (locs)
  union all
  -- cash short (+) / over (-): approved cases; a short booked as a staff receivable is not a loss
  select 'cash_short'::text, c.id::text, c.case_date, c.location_id,
         case when c.amount < 0 and coalesce(c.treatment, 'expense') = 'staff_receivable' then 0 else -c.amount end
    from public.shortage_cash_cases c
   where c.status = 'approved' and c.case_date between d1 and d2 and c.location_id = any (locs)
  union all
  -- running cost paid by supplier bill: the part of a posted bill that the journal books on an expense account (consumable or unclassified); a purchase return is negative
  select 'bill_opex'::text, b.id::text, b.bill_date, b.location_id, (case when b.kind = 'return' then -1 else 1 end) * a.amt
    from public.purchase_bills b
    cross join lateral (select coalesce(sum(al.amt), 0) as amt from public._acct_purchase_alloc(b.id) al where al.k in ('purch_consumable', 'purch_unclassified')) a
   where b.status = 'posted' and b.total > 0 and a.amt <> 0 and b.bill_date between d1 and d2 and b.location_id = any (locs)
  union all
  -- absorbed overhead: conversion cost that finished-goods costing already carries (it comes back through the cost of goods sold), so the expenses must lose it
  select 'overhead_absorbed'::text, r.id::text, (r.made_at at time zone 'Asia/Dhaka')::date, r.location_id, -round(r.conversion_cost, 2)
    from public.production_runs r
   where r.status = 'done' and coalesce(r.conversion_cost, 0) >= 0.005
     and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs);
$$;

create or replace function public._w1d_cause_on(p_cause text) returns boolean language sql stable security definer set search_path = public as $$
  select case p_cause
    when 'wastage' then public.rule_on('profit_loss_wastage') when 'count_shrink' then public.rule_on('profit_loss_count')
    when 'transit_loss' then public.rule_on('profit_loss_transit') when 'cash_short' then public.rule_on('profit_loss_cashshort')
    when 'bill_opex' then public.rule_on('profit_loss_billopex') when 'overhead_absorbed' then public.rule_on('profit_overhead_once') else false end $$;

-- the rows that count NOW: master on, the cause on, date from the start date, and not an excluded row
create or replace function public._w1d_pl_rows_on(d1 date, d2 date, locs integer[])
returns table (cause text, source_id text, d date, loc integer, amt numeric)
language plpgsql stable security definer set search_path = public as $$
declare f date;
begin
  if not public.rule_on('profit_one_number_on') then return; end if;
  f := public._w1d_losses_from();
  return query
    select r.cause, r.source_id, r.d, r.loc, r.amt from public._w1d_pl_rows(greatest(d1, coalesce(f, d1)), d2, locs) r
     where public._w1d_cause_on(r.cause)
       and not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active');
end $$;

-- month x place amounts for _p27_pl (zero rows while the master switch is off)
create or replace function public._w1d_pl_extra(d1 date, d2 date, locs integer[]) returns table (m date, loc integer, amt numeric)
language sql stable security definer set search_path = public as $$
  select date_trunc('month', r.d)::date, r.loc, sum(r.amt) from public._w1d_pl_rows_on(d1, d2, locs) r group by 1, 2 $$;

-- ---------- ONE profit function: the management profit for a period and a set of places (same formula as partner_calculate) ----------
create or replace function public._w1d_mgmt_profit(d1 date, d2 date, locs integer[]) returns numeric language sql stable security definer set search_path = public as $$
  select case when abs(z.ns - z.costed) <= greatest(1, abs(z.ns) * 0.001) then round(round(z.ns - z.cg, 2) - z.ex - z.sal - z.fix, 2) end
    from (select coalesce(sum(o_net), 0) ns, coalesce(sum(o_costed), 0) costed, coalesce(sum(o_cogs), 0) cg, coalesce(sum(o_exp), 0) ex, coalesce(sum(o_sal), 0) sal, coalesce(sum(o_fixed), 0) fix
            from public._p27_pl(d1, d2, locs)) z $$;

-- the journal profit (income minus expense accounts, from the accounting start date); null when accounting has not started
create or replace function public._w1d_ledger_profit(d1 date, d2 date, p_loc integer) returns numeric language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); v numeric;
begin
  if st is null or d2 < st then return null; end if;
  select coalesce(sum(l.credit - l.debit), 0) into v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
   where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(d1, st) and d2 and (p_loc is null or l.location_id = p_loc);
  return round(v, 2);
end $$;

-- partner_calculate: the profit override. null = nothing to override (master off or source management). Else {source, net_profit (null = journal unavailable), note}
create or replace function public._w1d_profit_override(d1 date, d2 date, p_loc integer) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v numeric;
begin
  if not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') <> 'ledger' then return null; end if;
  v := public._w1d_ledger_profit(d1, d2, p_loc);
  return jsonb_build_object('source', 'ledger', 'net_profit', v, 'note', case when v is null then 'The journal has no data for this period (accounting not started): the management profit was used.' end);
end $$;

-- the basis written into every partner settlement calc
create or replace function public._w1d_profit_basis(d1 date, d2 date, locs integer[], lj jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ex jsonb := '{}'::jsonb; c record;
begin
  if locs is not null and public.rule_on('profit_one_number_on') and not (lj is not null and lj ->> 'net_profit' is not null) then
    for c in select r.cause, round(sum(r.amt), 2) amt from public._w1d_pl_rows_on(d1, d2, locs) r group by 1 loop ex := ex || jsonb_build_object(c.cause, c.amt); end loop;
  end if;
  return jsonb_build_object('one_number', public.rule_on('profit_one_number_on'),
    'source', case when locs is null then 'manual' when lj is not null and lj ->> 'net_profit' is not null then 'ledger' else 'management' end,
    'losses_from', public._w1d_losses_from(), 'extra_rows', ex, 'note', lj ->> 'note');
end $$;

-- c_partner_month_split: the base of the preview. null = keep today's journal figure.
create or replace function public._w1d_split_base(d1 date, d2 date, p_loc integer) returns numeric language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') = 'ledger' then null
              else public._w1d_mgmt_profit(d1, d2, case when p_loc is null then array(select id from public.locations) else array[p_loc] end) end $$;
create or replace function public._w1d_split_basis() returns text language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('profit_one_number_on') or coalesce(public.rule_txt('profit_source'), 'management') = 'ledger' then null
              else 'management profit of the month (one profit number: net sales, cost of goods, expenses, salary, fixed cost and the counted losses)' end $$;

-- ============================================================================
-- PATCHES (text patch of the LIVE definition; a missing site stops the paste; marker bos92)
-- ============================================================================
-- _p27_pl: one more union in the expenses, zero rows while the master switch is off
select public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos92', array[
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),$a$,
  $a$select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w
      union all  /* bos92: wastage, count shrinkage, transit loss, cash short, bill-paid running cost, minus absorbed overhead (zero rows while profit_one_number_on is off) */
      select x.m, x.loc, x.amt from public._w1d_pl_extra(d1, d2, locs) x) u group by 1, 2),$a$]);

-- partner_calculate: ledger source (only while the master is on and profit_source = ledger) and the basis stored with the settlement
select public._w1d_patch('public.partner_calculate(bigint,date,date,jsonb)'::regprocedure, 'bos92', array[
  $a$ag public.partner_agreements; vn public.partner_ventures;$a$, $a$ag public.partner_agreements; lj jsonb; vn public.partner_ventures; /* bos92 */$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);$a$,
  $a$v_gp := round(v_ns - v_cogs, 2); v_nf := round(v_gp - v_exp - v_sal - coalesce(v_fix, 0), 2);
      lj := public._w1d_profit_override(p_from, p_to, case when vn.scope = 'location' then vn.location_id end);   /* bos92 */
      if lj is not null and lj ->> 'net_profit' is not null then v_nf := (lj ->> 'net_profit')::numeric; end if;$a$,
  $a$'warnings', warns, 'wrote', false);$a$, $a$'warnings', warns, 'profit_basis', public._w1d_profit_basis(p_from, p_to, locs, lj), 'wrote', false);$a$]);

-- c_partner_month_split: the preview uses the same profit as the settlement (while the master is on and the source is management)
select public._w1d_patch('public.c_partner_month_split(date)'::regprocedure, 'bos92', array[
  $a$base := (prof ->> 'net_profit')::numeric;$a$,
  $a$base := coalesce(public._w1d_split_base(greatest(m, st), me, case when a.scope = 'location' then a.location_id end), (prof ->> 'net_profit')::numeric);   /* bos92 */$a$,
  $a$'basis', 'journal net profit of the month (salary accrual included)'$a$, $a$'basis', coalesce(public._w1d_split_basis(), 'journal net profit of the month (salary accrual included)')$a$]);

-- ============================================================================
-- API (security definer, the server decides)
-- ============================================================================
create or replace function public.profit_exclude(p_cause text, p_source_id text, p_reason text) returns bigint language plpgsql security definer set search_path = public as $$
declare r record; id_ bigint; why text := btrim(coalesce(p_reason, '')); amt_ numeric;
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if p_cause is null or p_cause not in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed') then raise exception 'bad_cause'; end if;
  if length(why) < 5 then raise exception 'reason_required'; end if;
  if length(why) > 300 then raise exception 'too_long'; end if;
  select min(x.d) d, min(x.loc) loc, sum(x.amt) amt, count(*) n into r
    from public._w1d_pl_rows(date '2000-01-01', date '2100-01-01', array(select l.id from public.locations l where public.can_loc(l.id))) x where x.cause = p_cause and x.source_id = p_source_id;
  if r.n = 0 then raise exception 'row_not_found'; end if;
  if exists (select 1 from public.profit_row_exclusions where cause = p_cause and source_id = p_source_id and status = 'active') then raise exception 'already_excluded'; end if;
  amt_ := round(r.amt, 2);
  insert into public.profit_row_exclusions (cause, source_id, amount, row_date, location_id, reason) values (p_cause, p_source_id, amt_, r.d, r.loc, why) returning id into id_;
  perform public._stock_exc(r.loc, 'profit_row_excluded', 'yellow', 'Left out of profit by the owner: ' || p_cause || ' ' || amt_::text || ' (' || why || ')',
                            'Left out of profit by the owner: ' || p_cause || ' ' || amt_::text || ' (' || why || ')', null, r.d, 'PROFIT', amt_);
  return id_;
end $$;

create or replace function public.profit_exclusion_revoke(p_id bigint, p_reason text) returns boolean language plpgsql security definer set search_path = public as $$
declare x public.profit_row_exclusions; why text := btrim(coalesce(p_reason, ''));
begin
  if not public._w1d_mgr() then raise exception 'not allowed'; end if;
  if length(why) < 5 then raise exception 'reason_required'; end if;
  select * into x from public.profit_row_exclusions where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if x.status <> 'active' then raise exception 'not_active'; end if;
  update public.profit_row_exclusions set status = 'revoked', revoked_by = auth.uid(), revoked_at = now(), revoke_reason = left(why, 300) where id = p_id;
  perform public._stock_exc(x.location_id, 'profit_row_exclusion_revoked', 'yellow', 'Loss counted in profit again: ' || x.cause || ' ' || coalesce(x.amount::text, '') || ' (' || why || ')',
                            'Loss counted in profit again: ' || x.cause || ' ' || coalesce(x.amount::text, '') || ' (' || why || ')', null, x.row_date, 'PROFIT', x.amount);
  return true;
end $$;

create or replace function public.profit_exclusions_list(p_status text default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'cause', x.cause, 'source_id', x.source_id, 'amount', x.amount, 'row_date', x.row_date, 'location_id', x.location_id,
           'reason', x.reason, 'status', x.status, 'created_at', x.created_at, 'revoked_at', x.revoked_at, 'revoke_reason', x.revoke_reason) order by x.id desc)
    from public.profit_row_exclusions x where p_status is null or x.status = p_status), '[]'::jsonb);
end $$;

-- ---------- profit_recon: management versus journal, the difference by named cause ----------
create or replace function public.profit_recon(p_from date, p_to date, p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  locs int[]; st date := public._acct_start(); f date := public._w1d_losses_from();
  ns numeric; cg numeric; ex_ numeric; sal numeric; fix numeric; wf numeric; xt numeric; mg numeric; lg numeric;
  rows_ jsonb := '[]'::jsonb; k text; mval numeric; lval numeric; df numeric; why text; unposted bigint := 0; explained numeric := 0; unexplained numeric := 0; nex int;
  m_on boolean := public.rule_on('profit_one_number_on'); cand jsonb := '{}'::jsonb; c record; lab text;
  keys text[] := array['sales', 'cogs', 'vouchers', 'wallet_fee', 'salary', 'fixed_cost', 'wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed', 'other'];
  mg_by jsonb := '{}'::jsonb; lg_by jsonb := '{}'::jsonb;
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 3660 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  -- management side (as the settings are now)
  select coalesce(sum(o_net), 0), coalesce(sum(o_cogs), 0), coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0), coalesce(sum(o_fixed), 0) into ns, cg, ex_, sal, fix from public._p27_pl(p_from, p_to, locs);
  select coalesce(sum(amount), 0) into wf from public._d_wallet_fee_rows(p_from, p_to, locs);
  select coalesce(sum(r.amt), 0) into xt from public._w1d_pl_rows_on(p_from, p_to, locs) r;
  mg := round(ns - cg - ex_ - sal - fix, 2);
  mg_by := jsonb_build_object('sales', ns, 'cogs', -cg, 'vouchers', -(ex_ - wf - xt), 'wallet_fee', -wf, 'salary', -sal, 'fixed_cost', -fix);
  for c in select r.cause, sum(r.amt) amt from public._w1d_pl_rows_on(p_from, p_to, locs) r group by 1 loop mg_by := mg_by || jsonb_build_object(c.cause, -c.amt); end loop;
  -- what each cause WOULD add when counted (ignores the switches, honours exclusions and the start date): lets the owner see the effect before switching on
  for c in select r.cause, round(sum(r.amt), 2) amt, count(*) n from public._w1d_pl_rows(greatest(p_from, coalesce(f, p_from)), p_to, locs) r
            where not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active') group by 1 loop
    cand := cand || jsonb_build_object(c.cause, jsonb_build_object('amount', c.amt, 'rows', c.n));
  end loop;
  -- ledger side (from the accounting start date)
  if st is not null and p_to >= st then
    select coalesce(jsonb_object_agg(g.grp, g.v), '{}'::jsonb) into lg_by from (
      select case when e.source_type in ('sale', 'sale_return') and a.type = 'income' then 'sales' when e.source_type in ('sale', 'sale_return') then 'cogs'
                  when e.source_type in ('expense_voucher', 'quick_expense') then 'vouchers' when e.source_type = 'd_wallet_fee' then 'wallet_fee'
                  when e.source_type in ('payroll_payment', 'payroll_accrual') then 'salary' when e.source_type = 'wastage' then 'wastage'
                  when e.source_type = 'transit_writeoff' then 'transit_loss' when e.source_type = 'cash_short' then 'cash_short'
                  when e.source_type = 'purchase' then 'bill_opex' when e.source_type = 'production' then 'overhead_absorbed' else 'other' end grp,
             round(sum(l.credit - l.debit), 2) v
        from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
       where a.type in ('income', 'expense') and not a.is_group and e.entry_date between greatest(p_from, st) and p_to
         and (l.location_id = any (locs) or (p_loc is null and l.location_id is null))
       group by 1) g;
    select coalesce(sum(v.value::numeric), 0) into lg from jsonb_each_text(lg_by) v;
    select count(*) into unposted from public._acct_docs(st) d
     where d.live and d.waiting is null and d.entry_date between greatest(p_from, st) and p_to and (d.location_id is null or d.location_id = any (locs))
       and not exists (select 1 from public.journal_entries je where je.source_type = d.source_type and je.source_id = d.source_id and je.reverses_id is null);
  end if;
  foreach k in array keys loop
    mval := coalesce((mg_by ->> k)::numeric, 0); lval := case when st is null or p_to < st then null else coalesce((lg_by ->> k)::numeric, 0) end;
    df := case when lval is null then null else round(mval - lval, 2) end; why := null;
    select count(*) into nex from public.profit_row_exclusions x where x.status = 'active' and x.cause = k and x.row_date between p_from and p_to and x.location_id = any (locs);
    if df is null then why := 'journal_not_started';
    elsif df <> 0 then
      why := case
        when nex > 0 and k in ('wastage', 'count_shrink', 'transit_loss', 'cash_short', 'bill_opex', 'overhead_absorbed') then 'left_out_by_owner_exception'
        when k = 'fixed_cost' then 'fixed_cost_is_management_only'
        when k = 'count_shrink' then 'count_adjustment_not_in_journal_yet'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and not m_on then 'not_counted_in_management_profit_switch_off'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and not public._w1d_cause_on(k) then 'this_cause_is_switched_off'
        when k in ('wastage', 'transit_loss', 'bill_opex', 'overhead_absorbed', 'cash_short') and f is not null and f > p_from then 'before_the_start_date'
        when k = 'cash_short' and not public.rule_on('cash_short_post_on') then 'cash_short_not_posted_to_journal'
        when k = 'salary' then 'salary_basis_differs_forms_runs_or_payments'
        when k = 'vouchers' then 'voucher_status_basis_differs'
        when k = 'other' then 'journal_only_entries_manual_depreciation_charges_opening'
        when unposted > 0 then 'documents_not_posted_to_journal_yet'
        when st is not null and p_from < st then 'period_starts_before_accounting_start'
        else null end;
    end if;
    if df is not null and df <> 0 then if why is null then unexplained := unexplained + df; else explained := explained + df; end if; end if;
    lab := case k when 'sales' then 'Net sales' when 'cogs' then 'Cost of goods sold' when 'vouchers' then 'Expense vouchers and quick expenses' when 'wallet_fee' then 'Wallet fees'
                  when 'salary' then 'Salary' when 'fixed_cost' then 'Fixed cost (setting)' when 'wastage' then 'Wasted stock' when 'count_shrink' then 'Stock count shortage'
                  when 'transit_loss' then 'Goods lost in transit' when 'cash_short' then 'Cash short and over' when 'bill_opex' then 'Running cost paid by supplier bill'
                  when 'overhead_absorbed' then 'Factory overhead absorbed into products' else 'Other journal entries' end;
    rows_ := rows_ || jsonb_build_object('key', k, 'label_en', lab, 'management', mval, 'ledger', lval, 'difference', df, 'reason', why);
  end loop;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'one_number_on', m_on, 'profit_source', coalesce(public.rule_txt('profit_source'), 'management'), 'losses_from', f,
    'management_profit', mg, 'ledger_profit', case when st is null or p_to < st then null else lg end,
    'difference', case when st is null or p_to < st then null else round(mg - lg, 2) end, 'explained', round(explained, 2), 'unexplained', round(unexplained, 2),
    'unposted_documents', unposted, 'would_add_if_counted', cand, 'rows', rows_,
    'ledger_note', case when st is null then 'Accounting start date is not set: the journal has no figures.' when p_from < st then 'The period starts before the accounting start date: the journal counts only from that date.' end);
end $$;

-- ---------- rights: internals closed, API open to signed-in users (the function checks the person) ----------
revoke all on function public._w1d_patch(regprocedure, text, text[]), public._w1d_p92_present(), public._w1d_losses_from(), public._w1d_pl_rows(date, date, integer[]), public._w1d_cause_on(text),
  public._w1d_pl_rows_on(date, date, integer[]), public._w1d_pl_extra(date, date, integer[]), public._w1d_mgmt_profit(date, date, integer[]), public._w1d_ledger_profit(date, date, integer),
  public._w1d_profit_override(date, date, integer), public._w1d_profit_basis(date, date, integer[], jsonb), public._w1d_split_base(date, date, integer), public._w1d_split_basis() from public, anon, authenticated;
revoke all on function public.profit_exclude(text, text, text), public.profit_exclusion_revoke(bigint, text), public.profit_exclusions_list(text), public.profit_recon(date, date, integer) from public, anon;
grant execute on function public.profit_exclude(text, text, text), public.profit_exclusion_revoke(bigint, text), public.profit_exclusions_list(text), public.profit_recon(date, date, integer) to authenticated;

-- ===================== phase93.sql =====================
-- Phase 93 (bos93) - REPORT PARITY AND DATED BRAND MAP (UNIFIED_BUILD_PLAN U-06, package W1-D). Paste after phase92, paste-twice safe. Earlier phase files are not edited.
-- WHY: salary and expense totals differ between the day book, the P&L, the expense report and the journal (G16, G21, G12), and changing the brand map rewrites the brand P&L of old months.
-- EVERYTHING IS OFF BY DEFAULT: with every setting at its default no figure changes (proved by tests/sql/w1d_before_after.sh).
--   report_salary_source     legacy (default) | app_first    P&L salary: app payroll runs are primary and the 02-2 sheet is the fallback only where NO counted run exists for the month and place.
--                                                           (legacy = today: 02-2 sheets, plus the runs only while payroll_accrual_on is on). One salary is counted once whether or not a form and a run both exist.
--   report_expense_parity_on switch, default OFF             the expense report (expense_by_head) and the control report (E3) drop locked shadow vouchers and ADD quick expenses, as the P&L and E2 already do.
--   expense_count_on         as_today (default) | approved | submitted   which 10-2 vouchers count. as_today = each report as it is now (P&L and day book: submitted + approved, journal: approved only).
--                                                           approved / submitted = the SAME rule in the P&L, the expense reports and (through the integrator hook _w1d_hooks_apply) the day book and the journal.
--   brand_map_dated_on       switch, default OFF             the brand P&L reads the brand of each place AS OF each day (report_brand_map_hist); off = the current map for every day, as today.
-- Always on (no effect on any figure): report_brand_map_hist keeps every change of the map with its dates (a trigger on report_brand_map + backfill of the current rows), brand_map_set() changes the map
--   from a date (a date in the past needs a reason: audit_log + Exceptions list), report_parity() shows the four totals side by side.
-- INTEGRATOR: the day book and the journal are shared functions. _w1d_hooks_apply() patches them (marker bos93, exact text, stops if a site is missing). Call it from the last phase of the wave:  select public._w1d_hooks_apply();
-- NOT DONE: salary_report and _r3q_t3_payroll still read 02-2 sheets only; the brand filter of _r2_locs uses the current map.
-- !! Re-pasting phase 27, 44, 50, 72, 82, 85, 86 or 21/23 removes bos93 patches: paste phase92 and phase93 again (and call _w1d_hooks_apply()).

do $g$ begin
  if to_regprocedure('public._w1d_p92_present()') is null then raise exception 'phase93 needs phase92 first'; end if;
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,integer)') is null or to_regprocedure('public._r3q_e3_weak_control(date,date,integer[],jsonb)') is null
     or to_regprocedure('public._r3q_e2_expense_trend(date,date,integer[],jsonb)') is null or to_regprocedure('public.brand_pnl(date,date,text)') is null
     or to_regprocedure('public.c_salary_by_month(date,date,integer[])') is null or to_regclass('public.report_brand_map') is null or to_regclass('public.quick_expenses') is null then
    raise exception 'phase93 needs the report functions of phases 9, 20, 21, 50, 82';
  end if;
end $g$;

create or replace function public._w1d_p93_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings (English labels only, defaults keep today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_salary_source', 'reports', 'choice', '"legacy"', null, '["legacy","app_first"]', null, null,
  'Salary in the profit comes from', 'Salary in the profit comes from', 'Salary in the profit comes from',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.',
  'legacy = as today (02-2 sheets; payroll runs only while salary accrual is on). app_first = the approved payroll run of the month and place, and the 02-2 sheet only where no run exists. A salary is then counted once.', 800),
 ('report_expense_parity_on', 'reports', 'switch', 'false', null, null, null, null,
  'Expense report counts quick expenses and skips shadow vouchers', 'Expense report counts quick expenses and skips shadow vouchers', 'Expense report counts quick expenses and skips shadow vouchers',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.',
  'Off keeps the expense report as it is. On makes the expense report and the control report count the same expenses as the profit report.', 801),
 ('expense_count_on', 'reports', 'choice', '"as_today"', null, '["as_today","approved","submitted"]', null, null,
  'Expense vouchers count when they are', 'Expense vouchers count when they are', 'Expense vouchers count when they are',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).',
  'as_today = each report as it is now. approved = only approved vouchers everywhere. submitted = submitted and approved vouchers everywhere (the journal then posts a voucher when it is submitted).', 802),
 ('brand_map_dated_on', 'reports', 'switch', 'false', null, null, null, null,
  'Brand reports use the brand each place had on each day', 'Brand reports use the brand each place had on each day', 'Brand reports use the brand each place had on each day',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.',
  'Off = the brand report uses today''s brand map for every day. On = it uses the map as it was on each day, so changing the map never changes an old month.', 803)
on conflict (key) do nothing;

create or replace function public._w1d_salary_app_first() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('report_salary_source'), 'legacy') = 'app_first' $$;
create or replace function public._w1d_parity_on() returns boolean language sql stable security definer set search_path = public as $$
  select public.rule_on('report_expense_parity_on') $$;
-- does a 10-2 voucher of this status count? ctx = where it is asked: 'pl' (P&L and expense reports), 'daybook', 'journal'. as_today = each as it is now.
create or replace function public._w1d_exp_status_ok(p_status text, p_ctx text) returns boolean language sql stable security definer set search_path = public as $$
  select case coalesce(public.rule_txt('expense_count_on'), 'as_today')
    when 'approved' then p_status = 'approved'
    when 'submitted' then p_status in ('submitted', 'approved')
    else case when p_ctx = 'journal' then p_status = 'approved' else p_status in ('submitted', 'approved') end end $$;
grant execute on function public._w1d_exp_status_ok(text, text) to authenticated;

-- ---------- dated brand map ----------
create table if not exists public.report_brand_map_hist (
  id bigserial primary key,
  location_id integer not null references public.locations(id),
  brand_code text not null, brand_bn text not null, brand_en text not null,
  valid_from date,                                   -- null = from the beginning
  valid_to date,                                     -- null = still valid
  active boolean not null default true,              -- false = replaced by a dated correction (kept, never deleted)
  reason text check (reason is null or length(btrim(reason)) between 5 and 300),
  changed_by uuid default auth.uid(), changed_at timestamptz not null default now(),
  check (valid_to is null or valid_from is null or valid_to >= valid_from)
);
create index if not exists report_brand_map_hist_loc on public.report_brand_map_hist (location_id, valid_from);
drop trigger if exists report_brand_map_hist_nodel on public.report_brand_map_hist;
create trigger report_brand_map_hist_nodel before delete on public.report_brand_map_hist for each row execute function public.no_hard_delete();
drop trigger if exists audit_report_brand_map_hist on public.report_brand_map_hist;
create trigger audit_report_brand_map_hist after insert or update on public.report_brand_map_hist for each row execute function public.log_change('id');
alter table public.report_brand_map_hist enable row level security;
revoke all on public.report_brand_map_hist from public, anon, authenticated;
drop policy if exists report_brand_map_hist_read on public.report_brand_map_hist;
create policy report_brand_map_hist_read on public.report_brand_map_hist for select to authenticated using (public.is_active());
grant select on public.report_brand_map_hist to authenticated;

-- backfill: every mapping that exists today is valid from the beginning (idempotent)
insert into public.report_brand_map_hist (location_id, brand_code, brand_bn, brand_en, valid_from, reason)
select m.location_id, m.brand_code, m.brand_bn, m.brand_en, null, 'mapping that existed when the history started'
  from public.report_brand_map m where not exists (select 1 from public.report_brand_map_hist h where h.location_id = m.location_id);

-- close the open row of a place and open a new one from e (same-day corrections replace the row of that day)
create or replace function public._w1d_brand_open(p_loc integer, p_code text, p_bn text, p_en text, e date, p_reason text) returns bigint language plpgsql security definer set search_path = public as $$
declare r record; id_ bigint;
begin
  for r in select * from public.report_brand_map_hist where location_id = p_loc and active and (valid_to is null or valid_to >= e) order by valid_from nulls first, id for update loop
    if r.valid_from is null or r.valid_from < e then update public.report_brand_map_hist set valid_to = e - 1 where id = r.id;
    else update public.report_brand_map_hist set active = false where id = r.id; end if;
  end loop;
  if p_code is null then return null; end if;                    -- the mapping was removed: the place is unmapped from e
  insert into public.report_brand_map_hist (location_id, brand_code, brand_bn, brand_en, valid_from, reason) values (p_loc, p_code, p_bn, p_en, e, left(btrim(p_reason), 300)) returning id into id_;
  return id_;
end $$;

-- a direct edit of report_brand_map (owner, SQL or table API) is dated TODAY (a change in the past goes through brand_map_set with a reason)
create or replace function public._w1d_brand_trg() returns trigger language plpgsql security definer set search_path = public as $$
declare e date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if coalesce(current_setting('bos.w1d_brand_skip', true), '') = '1' then return null; end if;
  if tg_op = 'DELETE' then perform public._w1d_brand_open(old.location_id, null, null, null, e, null);
  elsif tg_op = 'INSERT' then perform public._w1d_brand_open(new.location_id, new.brand_code, new.brand_bn, new.brand_en, e, 'mapping added');
  elsif new.brand_code is distinct from old.brand_code or new.brand_bn is distinct from old.brand_bn or new.brand_en is distinct from old.brand_en then
    perform public._w1d_brand_open(new.location_id, new.brand_code, new.brand_bn, new.brand_en, e, 'mapping changed');
  end if;
  return null;
end $$;
drop trigger if exists report_brand_map_w1d on public.report_brand_map;
create trigger report_brand_map_w1d after insert or update or delete on public.report_brand_map for each row execute function public._w1d_brand_trg();

-- the brand of a place on a day: dated history when the switch is on, today's map when it is off
create or replace function public._w1d_brand_at(p_loc integer, p_day date) returns table (brand_code text, brand_bn text, brand_en text) language sql stable security definer set search_path = public as $$
  select m.brand_code, m.brand_bn, m.brand_en from public.report_brand_map m where not public.rule_on('brand_map_dated_on') and m.location_id = p_loc
  union all
  select z.brand_code, z.brand_bn, z.brand_en from (
    select h.brand_code, h.brand_bn, h.brand_en from public.report_brand_map_hist h
     where public.rule_on('brand_map_dated_on') and h.active and h.location_id = p_loc and (h.valid_from is null or h.valid_from <= p_day) and (h.valid_to is null or h.valid_to >= p_day)
     order by h.valid_from nulls first, h.id desc limit 1) z $$;

-- owner: map a place to a brand FROM a date. Today or later in the future is not allowed; a date in the past rewrites history, so it needs a reason (audit_log + Exceptions list).
create or replace function public.brand_map_set(p_loc integer, p_code text, p_bn text, p_en text, p_from date default null, p_reason text default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare today_ date := (now() at time zone 'Asia/Dhaka')::date; e date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date); id_ bigint; why text := nullif(btrim(coalesce(p_reason, '')), ''); retro boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if p_code is null or length(btrim(p_code)) = 0 or length(p_code) > 40 or p_bn is null or length(btrim(p_bn)) = 0 or p_en is null or length(btrim(p_en)) = 0 then raise exception 'bad_brand'; end if;
  if e > today_ then raise exception 'future_date_not_allowed'; end if;
  retro := e < today_;
  if retro and (why is null or length(why) < 5) then raise exception 'reason_required'; end if;
  id_ := public._w1d_brand_open(p_loc, btrim(p_code), btrim(p_bn), btrim(p_en), e, coalesce(why, 'brand map set'));
  perform set_config('bos.w1d_brand_skip', '1', true);
  insert into public.report_brand_map (location_id, brand_code, brand_bn, brand_en) values (p_loc, btrim(p_code), btrim(p_bn), btrim(p_en))
    on conflict (location_id) do update set brand_code = excluded.brand_code, brand_bn = excluded.brand_bn, brand_en = excluded.brand_en;
  perform set_config('bos.w1d_brand_skip', '', true);
  if retro then
    perform public._stock_exc(p_loc, 'brand_map_backdated', 'yellow', 'Brand map changed from a past date (' || e::text || '): ' || btrim(p_code) || ' (' || why || ')',
                              'Brand map changed from a past date (' || e::text || '): ' || btrim(p_code) || ' (' || why || ')', null, e, 'BRAND', null);
  end if;
  return jsonb_build_object('id', id_, 'location_id', p_loc, 'valid_from', e, 'backdated', retro);
end $$;

create or replace function public.brand_map_hist_list(p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', h.id, 'location_id', h.location_id, 'brand_code', h.brand_code, 'brand_bn', h.brand_bn, 'brand_en', h.brand_en,
           'valid_from', h.valid_from, 'valid_to', h.valid_to, 'active', h.active, 'reason', h.reason, 'changed_at', h.changed_at) order by h.location_id, h.valid_from nulls first, h.id)
    from public.report_brand_map_hist h where p_loc is null or h.location_id = p_loc), '[]'::jsonb);
end $$;

-- ============================================================================
-- PATCHES (text patch of the LIVE definition; a missing site stops the paste; marker bos93)
-- ============================================================================
-- _p27_pl: the 10-2 status rule, and the salary source
select public._w1d_patch('public._p27_pl(date,date,integer[])'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */$a$,
  $a$(not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and (not public._w1d_salary_app_first() or not exists (select 1 from public.c_salary_by_month(d1, d2, locs) c2 where c2.m = date_trunc('month', e.entry_date)::date and c2.loc = e.location_id)) /* bos93: the sheet is the fallback only where no counted run exists */$a$,
  $a$where public.rule_on('payroll_accrual_on') /* bos85 bos86 */$a$,
  $a$where (public.rule_on('payroll_accrual_on') or public._w1d_salary_app_first()) /* bos85 bos86 bos93 */$a$]);

-- the expense report: same expenses as the P&L (quick expenses in, locked shadow vouchers out) when report_expense_parity_on; status rule from expense_count_on
select public._w1d_patch('public.report_run2_core(text,jsonb,text,text,integer)'::regprocedure, 'bos93', array[
  $a$where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between %L and %L and e.location_id = any (%L::int[])) x$a$,
  $a$where e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') and (not public._w1d_parity_on() or not public.is_shadow('entries', e.id::text)) and e.entry_date between %L and %L and e.location_id = any (%L::int[])
            union all  /* bos93: quick expenses (only while report_expense_parity_on) */
            select null::uuid, q.location_id, q.exp_date, q.amount, case when q.receipt then 'yes' else 'no' end, coalesce(nullif(btrim(q.head), ''), '-') from public.quick_expenses q
            where public._w1d_parity_on() and q.status = 'done' and q.exp_date between %2$L and %3$L and q.location_id = any (%4$L::int[])) x$a$]);

-- E3 control report: status rule, shadows out, and a row for the quick expenses (only while report_expense_parity_on)
select public._w1d_patch('public._r3q_e3_weak_control(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
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

-- E2 expense trend: the status rule only (it already counts quick expenses and drops shadows)
select public._w1d_patch('public._r3q_e2_expense_trend(date,date,integer[],jsonb)'::regprocedure, 'bos93', array[
  $a$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */$a$,
  $a$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'pl') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$a$]);

-- brand P&L: the brand of each place AS OF each day (switch brand_map_dated_on; off = today's map)
select public._w1d_patch('public.brand_pnl(date,date,text)'::regprocedure, 'bos93', array[
  $a$left join public.report_brand_map b on b.location_id = d.location_id$a$,
  $a$left join lateral public._w1d_brand_at(d.location_id, d.sale_date) b on true /* bos93 */$a$]);

-- ---------- the integrator's hook: the shared day book and journal use the same voucher rule ----------
-- Call once from the last phase of the wave (and again after any re-paste of phases 13, 23, 50, 52, 79, 85, 87). Exact-text patch, marker bos93, stops if a site is missing. Idempotent.
create or replace function public._w1d_hooks_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare a boolean; b boolean;
begin
  a := public._w1d_patch('public._daybook_lines(integer[],integer[],date,date)'::regprocedure, 'bos93', array[
    $x$e.form_code = '10-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)$x$,
    $x$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'daybook') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */ and e.location_id = any (p_locs)$x$]);
  b := public._w1d_patch('public._acct_docs(date)'::regprocedure, 'bos93', array[
    $x$e.form_code = '10-2' and e.status = 'approved' and not public.is_shadow('entries', e.id::text) /* bos50 */$x$,
    $x$e.form_code = '10-2' and public._w1d_exp_status_ok(e.status, 'journal') /* bos93 */ and not public.is_shadow('entries', e.id::text) /* bos50 */$x$]);
  return jsonb_build_object('daybook_lines_patched', a, 'acct_docs_patched', b);
end $$;

-- ---------- report_parity: the same expenses and salary in the day book, the P&L, the expense report and the journal ----------
create or replace function public.report_parity(p_from date, p_to date, p_loc integer default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  locs int[]; st date := public._acct_start(); db_e numeric; db_s numeric; pl_e numeric; pl_s numeric; xt numeric; wf numeric; rep numeric; j_e numeric; j_s numeric; j_rec numeric;
  rr jsonb; agree_e boolean; agree_s boolean; agree_d boolean;
begin
  if not public._w1d_view() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  locs := array(select l.id from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id));
  if cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  -- day book (money out): vouchers and quick expenses = typ expense; salary paid = typ salary
  select coalesce(sum(u.amount) filter (where u.typ = 'expense'), 0), coalesce(sum(u.amount) filter (where u.typ = 'salary'), 0) into db_e, db_s
    from (select * from public._daybook_lines(locs, locs, p_from, p_to) union all select * from public._daybook_lines12(locs, p_from, p_to) union all select * from public._daybook_lines23(locs, p_from, p_to)) u;
  -- P&L: expenses without the wallet fee and the profit-only rows of phase92; salary as the P&L counts it
  select coalesce(sum(o_exp), 0), coalesce(sum(o_sal), 0) into pl_e, pl_s from public._p27_pl(p_from, p_to, locs);
  select coalesce(sum(amount), 0) into wf from public._d_wallet_fee_rows(p_from, p_to, locs);
  select coalesce(sum(r.amt), 0) into xt from public._w1d_pl_rows_on(p_from, p_to, locs) r;
  pl_e := pl_e - wf - xt;
  -- the expense report (expense_by_head) total, run through the real report
  begin
    rr := public.report_run2_core('expense_by_head', jsonb_build_object('from', p_from, 'to', p_to, 'locations', to_jsonb(locs)), 'none');
    rep := coalesce((rr #>> '{totals,amount}')::numeric, 0);
  exception when others then rep := null;
  end;
  -- the journal: debits on expense accounts of the voucher / quick expense / payroll sources, net of reversals
  if st is null or p_to < st then j_e := null; j_s := null; j_rec := null;
  else
    select coalesce(sum(l.debit - l.credit) filter (where e.source_type in ('expense_voucher', 'quick_expense') and a.type = 'expense'), 0),
           coalesce(sum(l.debit - l.credit) filter (where e.source_type in ('payroll_payment', 'payroll_accrual') and a.type = 'expense'), 0),
           coalesce(sum(l.credit - l.debit) filter (where e.source_type = 'payroll_payment' and a.code = (select ac.code from public.acct_mappings m join public.coa_accounts ac on ac.id = m.account_id where m.key = 'staff_advance')), 0)
      into j_e, j_s, j_rec
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.coa_accounts a on a.id = l.account_id
     where e.entry_date between greatest(p_from, st) and p_to and (l.location_id = any (locs) or (p_loc is null and l.location_id is null));
  end if;
  agree_e := j_e is not null and rep is not null and db_e = pl_e and pl_e = rep and rep = j_e;
  agree_s := j_s is not null and pl_s = j_s;
  agree_d := j_s is not null and db_s = j_s - j_rec;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc,
    'expenses', jsonb_build_object('daybook', db_e, 'pl', pl_e, 'expense_report', rep, 'journal', j_e, 'agree', agree_e,
       'note', 'Expense vouchers (10-2) and quick expenses. The journal counts only what is posted; the day book counts money out on the voucher date.'),
    'salary', jsonb_build_object('daybook_paid', db_s, 'pl', coalesce(pl_s, 0), 'journal', j_s, 'journal_advance_recovery', j_rec, 'pl_agrees_journal', agree_s, 'daybook_agrees_journal_less_recovery', agree_d,
       'note', 'The P&L and the journal show the salary expense (net pay plus advance recovery). The day book shows only the money paid out (net pay).'),
    'settings', jsonb_build_object('expense_count_on', coalesce(public.rule_txt('expense_count_on'), 'as_today'), 'report_expense_parity_on', public.rule_on('report_expense_parity_on'),
       'report_salary_source', coalesce(public.rule_txt('report_salary_source'), 'legacy')));
end $$;

-- ---------- rights ----------
revoke all on function public._w1d_p93_present(), public._w1d_salary_app_first(), public._w1d_parity_on(), public._w1d_brand_open(integer, text, text, text, date, text), public._w1d_brand_trg(),
  public._w1d_brand_at(integer, date), public._w1d_hooks_apply() from public, anon, authenticated;
revoke all on function public.brand_map_set(integer, text, text, text, date, text), public.brand_map_hist_list(integer), public.report_parity(date, date, integer) from public, anon;
grant execute on function public.brand_map_set(integer, text, text, text, date, text), public.brand_map_hist_list(integer), public.report_parity(date, date, integer) to authenticated;

-- ===================== phase94.sql =====================
-- Phase 94 (bos94) - CASH AND PAYMENT CONTROLS (package W1-E, item U-07). Paste AFTER phase87 (phases 88-93 of the other packages are independent). Paste-twice safe.
-- Earlier phase files are not edited. No shared function is replaced by this file: every control is a new trigger or a new function with the prefix _w1e_ / w1e_.
--
-- EVERY policy choice is a SETTING (table rules, module books, shown on the Rules page and on #/moneycontrols), English label, hint, owner editable at any time,
-- every change is written to audit_log by the existing audit_rules trigger. Every default keeps TODAY'S behaviour, so pasting this file changes nothing:
--   owner_money_entry_mode     open (default) | approval | owner     who may record owner_draw / owner_topup (cash moves)
--   bank_slip_required         off (default)                          bank_deposit / bank_withdraw need a slip number in the reference
--   bank_move_large_over       blank = off                            yellow exception for a bank move above this amount
--   bank_move_backdate_days    blank = off                            yellow exception for a bank move dated more than N days back
--   supplier_pay_dup_mode      off (default) | flag | block           same supplier, same total, again inside the window
--   supplier_pay_dup_hours     blank = same calendar day              the window
--   supplier_pay_over          blank = off                            a non-owner supplier payment above this amount waits for the approver
--   supplier_dup_mode          off (default) | warn | block           a second supplier with the same name, mobile or TIN
--   employee_pay_dup_mode      off (default) | warn | block           two employees on one bank account or wallet number
--   employee_pay_change_flag   off (default)                          red exception when a pay account is changed
-- APPROVER: a request is decided by the approver the owner chose under phase87 (owner_approval_mode_set2: any role, any named people), or - when a request carries its own
--   approver (w1e_request_approver_set) - by that person or role. Nothing is hard-coded. The maker NEVER decides his own request (also not the owner). The owner may grant one
--   one-off 'approver' exception (phase87 money_exception_grant) with a reason; it is logged in audit_log and in the Exceptions list.
-- EXCEPTIONS: every blocking control has a one-off override through the phase87 grant (rule 'override', event w1e_*), reason required, audit_log line, Exceptions row.
--   Events: w1e_owner_money, w1e_bank_slip, w1e_dup_payment, w1e_pay_over, w1e_vendor_dup, w1e_pay_account (phase95 adds w1e_mapping, w1e_journal_*).
-- HOOKS (integrator, see docs/integration/W1-E.md): pay_supplier (duplicate guard and over-threshold wait need the exact amount of the whole call) and, for display only,
--   cash_move_add (returns pending). Without the hooks the cash move controls, vendor and employee controls still work; the supplier payment controls simply do nothing.
-- Nothing is deleted. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_patch(regprocedure,text[])') is null
     or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regprocedure('public._owner_approver_users()') is null then
    raise exception 'phase94 needs phase87 (and 80-86) first';
  end if;
end $g$;

create or replace function public._p94_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- Exceptions list: more kinds (additive: keeps every kind another package added) ----------
create or replace function public._w1e_add_exc_kinds(p_kinds text[]) returns void language plpgsql set search_path = public as $$
declare con text; def text; cur text[]; allk text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase94: money_exceptions kind check not found'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  -- the form '{a,b}'::text[] (what phase89 writes when it runs first): integration fix, both forms are read
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase94: money_exceptions kind check has an unknown shape'; end if;
  allk := cur;
  foreach k in array p_kinds loop if not (k = any (allk)) then allk := allk || k; end if; end loop;
  if allk = cur then return; end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(allk) x));
end $$;
select public._w1e_add_exc_kinds(array['w1e_bank_move_flag', 'w1e_duplicate_payment', 'w1e_pay_over_request', 'w1e_vendor_duplicate', 'w1e_pay_account_duplicate',
  'w1e_pay_account_changed', 'w1e_owner_money_request', 'w1e_journal_request']);

-- ---------- settings (rules). Label and hint in English only (the owner will translate later). ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('owner_money_entry_mode', 'choice', '"open"'::jsonb, null::text, '["open","approval","owner"]'::jsonb, null::numeric, null::numeric,
   'Who may record an owner draw or an owner top-up',
   'open = anyone who has the cash move right (today). approval = an entry by a person who is not the owner waits for the approver chosen under "Approval of the owner''s own entries". owner = only the owner. Recommended: approval or owner.', 740),
 ('bank_slip_required', 'switch', 'false'::jsonb, null, null, null, null,
   'Bank slip number required on a bank deposit and a bank withdraw',
   'When ON, the Reference field of a bank deposit or bank withdraw must hold the slip number. Off = today. Recommended: ON.', 741),
 ('bank_move_large_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'Flag a bank deposit or withdraw above this amount',
   'A yellow line in the Exceptions list. Blank = off. The entry is still saved.', 742),
 ('bank_move_backdate_days', 'number', null, 'days', null, 0, 3650,
   'Flag a bank deposit or withdraw dated more than this many days back',
   'A yellow line in the Exceptions list. Blank = off. The entry is still saved.', 743),
 ('supplier_pay_dup_mode', 'choice', '"off"'::jsonb, null, '["off","flag","block"]'::jsonb, null, null,
   'Same supplier payment entered twice',
   'off = today. flag = save it and add a yellow line to the Exceptions list. block = refuse it unless the owner allows one exception. A payment is a repeat when the supplier and the total are the same inside the window below.', 744),
 ('supplier_pay_dup_hours', 'number', null, 'hours', null, 1, 720,
   'Window for the repeat-payment check',
   'Blank = the same calendar day (Asia/Dhaka). Only used when the repeat-payment check is not off.', 745),
 ('supplier_pay_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'A supplier payment above this amount waits for the approver',
   'Blank = off. A payment entered by someone who is not the owner and above this total is held until the approver decides. The owner is not held.', 746),
 ('supplier_dup_mode', 'choice', '"off"'::jsonb, null, '["off","warn","block"]'::jsonb, null, null,
   'Second supplier with the same name, mobile or TIN',
   'off = today. warn = save it and add a yellow line to the Exceptions list. block = refuse it unless the owner allows one exception.', 747),
 ('employee_pay_dup_mode', 'choice', '"off"'::jsonb, null, '["off","warn","block"]'::jsonb, null, null,
   'Two employees on one pay account (bank account or wallet number)',
   'off = today. warn = save it and add a red line to the Exceptions list. block = refuse it unless the owner allows one exception. Employees who have left are not compared.', 748),
 ('employee_pay_change_flag', 'switch', 'false'::jsonb, null, null, null, null,
   'Red line in the Exceptions list when an employee pay account is changed',
   'Off = today. The line shows only the last 4 characters of the old and new account.', 749)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- requests: one waiting list for the three controls that need an approver (owner money, supplier payment over the limit, journal on a control account) ----------
create table if not exists public.w1e_requests (
  id bigserial primary key,
  kind text not null check (kind in ('owner_money', 'supplier_pay', 'journal_control')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  location_id int, amount numeric, ref_date date,
  summary text not null check (length(summary) <= 300),
  payload jsonb not null,
  client_id uuid unique,
  approver_user uuid, approver_role text, approver_set_by uuid, approver_set_at timestamptz, approver_reason text,
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text, applied_ref text
);
create index if not exists w1e_requests_status on public.w1e_requests (status, id);
drop trigger if exists w1e_requests_nodel on public.w1e_requests;
create trigger w1e_requests_nodel before delete on public.w1e_requests for each row execute function public.no_hard_delete();
drop trigger if exists audit_w1e_requests on public.w1e_requests;
create trigger audit_w1e_requests after insert or update on public.w1e_requests for each row execute function public.log_change('id');
alter table public.w1e_requests enable row level security;
revoke all on public.w1e_requests from public, anon, authenticated;
do $s$ begin
  if exists (select 1 from pg_class where relname = 'w1e_requests_id_seq' and relnamespace = 'public'::regnamespace) then
    execute 'revoke all on sequence public.w1e_requests_id_seq from public, anon, authenticated';
  end if;
end $s$;

-- ---------- helpers ----------
create or replace function public._w1e_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._w1e_staff() returns text language sql stable security definer set search_path = public as $$ select staff_id from public.profiles where id = auth.uid() $$;
create or replace function public._w1e_choice(p_key text, p_default text) returns text language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt(p_key), p_default) $$;
create or replace function public._w1e_nalnum(t text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(coalesce(t, ''), '[^0-9a-zA-Z]', '', 'g')), '') $$;
create or replace function public._w1e_nname(t text) returns text language sql immutable as $$ select nullif(lower(regexp_replace(btrim(coalesce(t, '')), '\s+', ' ', 'g')), '') $$;
-- a mobile number compared on its last 10 digits (+8801712345678 equals 01712345678); shorter than 10 digits is not compared
create or replace function public._w1e_nmobile(t text) returns text language sql immutable as $$
  select case when length(regexp_replace(coalesce(t, ''), '\D', '', 'g')) >= 10 then right(regexp_replace(t, '\D', '', 'g'), 10) end $$;
create or replace function public._w1e_mask(t text) returns text language sql immutable as $$
  select case when t is null or btrim(t) = '' then '-' else '****' || right(btrim(t), 4) end $$;

create or replace function public._w1e_exc(p_kind text, p_ev text, p_amount numeric, p_src_table text, p_src_id text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user) values (p_kind, p_ev, p_amount, p_src_table, left(p_src_id, 120), left(p_reason, 300), auth.uid());
end $$;
create or replace function public._w1e_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), public._w1e_staff(), p_action, p_table, p_id, p_detail);
end $$;

-- who may decide a request: its own approver if the owner set one, else the approver chosen under phase87 (named role / people), else an owner. Never the maker (checked by the caller).
create or replace function public._w1e_user_is_approver(p_uid uuid, r public.w1e_requests) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare rl text;
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid and status = 'active') then return false; end if;
  if r.approver_user is not null or r.approver_role is not null then
    return p_uid = r.approver_user or (r.approver_role is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = r.approver_role));
  end if;
  if public._owner_mode() = 'named' then
    rl := public.rule_txt('owner_approver_role');
    return (rl is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = rl)) or p_uid = any (public._owner_approver_users());
  end if;
  return exists (select 1 from public.user_roles where user_id = p_uid and role_code = 'owner');
end $$;

-- ---------- control 1: cash moves (owner money, bank slip, large and back-dated bank moves). A BEFORE INSERT trigger, so a hidden button is also a refused request. ----------
create or replace function public._w1e_cash_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare mode text; slip text; lim numeric; dys numeric; rid bigint;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if new.kind in ('bank_deposit', 'bank_withdraw') then
    if public.rule_on('bank_slip_required') then
      select u.rest into slip from public._m_untag(new.ref) u;
      if nullif(btrim(coalesce(slip, '')), '') is null
         and not public._m_grant_take('override', 'w1e_bank_slip', new.client_id, null, new.amount, new.move_date, 'cash_moves') then raise exception 'bank_slip_required'; end if;
    end if;
    lim := public.rule_num('bank_move_large_over');
    if lim is not null and new.amount > lim then
      perform public._w1e_exc('w1e_bank_move_flag', 'w1e_bank_large', new.amount, 'cash_moves', new.id::text, new.kind || ' ' || new.amount::text || ' is above the limit ' || lim::text);
    end if;
    dys := public.rule_num('bank_move_backdate_days');
    if dys is not null and new.move_date < public._w1e_today() - dys::int then
      perform public._w1e_exc('w1e_bank_move_flag', 'w1e_bank_backdated', new.amount, 'cash_moves', new.id::text, new.kind || ' dated ' || new.move_date::text || ' is more than ' || dys::text || ' days back');
    end if;
  elsif new.kind in ('owner_topup', 'owner_draw') and not public.is_owner() then
    mode := public._w1e_choice('owner_money_entry_mode', 'open');
    if mode = 'open' then
      perform public._w1e_audit('w1e_owner_money_open', 'cash_moves', new.id::text, jsonb_build_object('kind', new.kind, 'amount', new.amount, 'date', new.move_date, 'mode', 'open'));
    elsif mode = 'owner' then
      if not public._m_grant_take('override', 'w1e_owner_money', new.client_id, null, new.amount, new.move_date, 'cash_moves') then raise exception 'owner_money_owner_only'; end if;
    else                                                                      -- approval: the row is NOT written; it waits in w1e_requests with the same id and client id
      insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
        values ('owner_money', new.location_id, new.amount, new.move_date, left(new.kind || ' ' || new.amount::text || ' on ' || new.move_date::text || ' (' || coalesce(new.mode, '-') || ')', 300),
                to_jsonb(new), new.client_id, coalesce(new.created_by, auth.uid()), coalesce(new.created_staff, public._w1e_staff()))
        on conflict (client_id) do nothing returning id into rid;
      if rid is not null then
        perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'owner_money', 'amount', new.amount, 'cash_move', new.id));
        perform public._w1e_exc('w1e_owner_money_request', 'w1e_owner_money', new.amount, 'w1e_requests', rid::text, new.kind || ' entered by a person who is not the owner; waits for the approver');
      end if;
      return null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_cash_bi on public.cash_moves;
create trigger a94_w1e_cash_bi before insert on public.cash_moves for each row execute function public._w1e_cash_bi();   -- a94 sorts before aa87: the request is held before any money-account check

create or replace function public._w1e_cash_pending(p_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select jsonb_build_object('pending', true, 'request_id', r.id) from public.w1e_requests r where r.kind = 'owner_money' and r.status = 'pending' and r.payload ->> 'id' = p_id::text limit 1), '{}'::jsonb) $$;

-- ---------- control 2: supplier payment (called from the pay_supplier hook with the exact total of the whole call) ----------
create or replace function public._w1e_pay_gate(p_supplier uuid, p_loc int, p_payments jsonb, p_client uuid, p_note text, p_tot numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dm text := public._w1e_choice('supplier_pay_dup_mode', 'off'); hrs numeric := public.rule_num('supplier_pay_dup_hours'); ov numeric := public.rule_num('supplier_pay_over');
  since timestamptz; dup boolean := false; rid bigint; ex public.w1e_requests; bal numeric;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return null; end if;
  if p_client is not null then
    select * into ex from public.w1e_requests where client_id = p_client;
    if found then return jsonb_build_object('pending', true, 'request_id', ex.id, 'paid', 0, 'balance', public._sup_balance(p_supplier), 'dup', true); end if;
  end if;
  if dm <> 'off' then
    since := case when hrs is null then (date_trunc('day', now() at time zone 'Asia/Dhaka')) at time zone 'Asia/Dhaka' else now() - make_interval(secs => (hrs * 3600)::double precision) end;
    select exists (select 1 from (select sum(amount) a, max(paid_at) t from public.supplier_payments
                                   where supplier_id = p_supplier and not voided and bill_id is null and client_id is distinct from p_client
                                   group by coalesce(client_id::text, id::text)) g where g.a = p_tot and g.t >= since)
        or exists (select 1 from public.w1e_requests q where q.kind = 'supplier_pay' and q.status = 'pending' and q.payload ->> 'supplier' = p_supplier::text and (q.payload ->> 'total')::numeric = p_tot and q.requested_at >= since)
      into dup;
    if dup then
      if dm = 'block' then
        if not public._m_grant_take('override', 'w1e_dup_payment', p_client, null, p_tot, public._w1e_today(), 'supplier:' || p_supplier::text) then raise exception 'duplicate_payment'; end if;
      else
        perform public._w1e_exc('w1e_duplicate_payment', 'w1e_dup_payment', p_tot, 'suppliers', p_supplier::text, 'a payment of the same total to the same supplier was already entered inside the window');
      end if;
    end if;
  end if;
  if ov is not null and p_tot > ov and not public.is_owner() then
    if public._m_grant_take('override', 'w1e_pay_over', p_client, null, p_tot, public._w1e_today(), 'supplier:' || p_supplier::text) then return null; end if;
    insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
      values ('supplier_pay', p_loc, p_tot, public._w1e_today(),
              left('Supplier payment ' || p_tot::text || ' to ' || coalesce((select name from public.suppliers where id = p_supplier), '-') || ' (limit ' || ov::text || ')', 300),
              jsonb_build_object('supplier', p_supplier, 'loc', p_loc, 'payments', p_payments, 'client', p_client, 'note', p_note, 'total', p_tot), p_client, auth.uid(), public._w1e_staff())
      returning id into rid;
    perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'supplier_pay', 'amount', p_tot, 'supplier', p_supplier, 'limit', ov));
    perform public._w1e_exc('w1e_pay_over_request', 'w1e_pay_over', p_tot, 'w1e_requests', rid::text, 'supplier payment above the limit ' || ov::text || ' waits for the approver');
    bal := public._sup_balance(p_supplier);
    return jsonb_build_object('pending', true, 'request_id', rid, 'paid', 0, 'balance', bal);
  end if;
  return null;
end $$;

-- ---------- control 3: second supplier with the same name, mobile or TIN ----------
create or replace function public._w1e_vendor_match(p_name text, p_mobile text, p_tin text, p_exclude uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'by', case when public._w1e_nname(s.name) = public._w1e_nname(p_name) then 'name'
                                                                                    when public._w1e_nmobile(s.mobile) is not null and public._w1e_nmobile(s.mobile) = public._w1e_nmobile(p_mobile) then 'mobile' else 'tin' end)), '[]'::jsonb)
    from public.suppliers s
   where s.active and (p_exclude is null or s.id <> p_exclude)
     and ((public._w1e_nname(p_name) is not null and public._w1e_nname(s.name) = public._w1e_nname(p_name))
       or (public._w1e_nmobile(p_mobile) is not null and public._w1e_nmobile(s.mobile) = public._w1e_nmobile(p_mobile))
       or (public._w1e_nalnum(p_tin) is not null and public._w1e_nalnum(s.tin) = public._w1e_nalnum(p_tin))) $$;

create or replace function public._w1e_supplier_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare m text := public._w1e_choice('supplier_dup_mode', 'off'); hit jsonb;
begin
  if m = 'off' or auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.name is not distinct from old.name and new.mobile is not distinct from old.mobile and new.tin is not distinct from old.tin and new.active is not distinct from old.active then return new; end if;
  if not new.active then return new; end if;
  hit := public._w1e_vendor_match(new.name, new.mobile, new.tin, new.id);
  if jsonb_array_length(hit) = 0 then return new; end if;
  if m = 'block' then
    if not public._m_grant_take('override', 'w1e_vendor_dup', null, null, null, public._w1e_today(), 'suppliers:' || new.id::text) then raise exception 'vendor_duplicate' using detail = hit::text; end if;
  else
    perform public._w1e_exc('w1e_vendor_duplicate', 'w1e_vendor_dup', null, 'suppliers', new.id::text, 'same ' || (hit -> 0 ->> 'by') || ' as supplier "' || left(hit -> 0 ->> 'name', 80) || '"');
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_supplier_bi on public.suppliers;
create trigger a94_w1e_supplier_bi before insert or update on public.suppliers for each row execute function public._w1e_supplier_bi();

-- ---------- control 4: one pay account per employee ----------
create or replace function public._w1e_pay_match(p_bank text, p_wallet text, p_exclude uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'by', case when public._w1e_nalnum(p_bank) is not null and public._w1e_nalnum(e.bank_account) = public._w1e_nalnum(p_bank) then 'bank_account' else 'mobile_wallet' end)), '[]'::jsonb)
    from public.employees e
   where (p_exclude is null or e.id <> p_exclude) and e.status not in ('resigned', 'terminated', 'retired', 'discarded')
     and ((public._w1e_nalnum(p_bank) is not null and public._w1e_nalnum(e.bank_account) = public._w1e_nalnum(p_bank))
       or (public._w1e_nmobile(p_wallet) is not null and public._w1e_nmobile(e.mobile_wallet) = public._w1e_nmobile(p_wallet))) $$;

create or replace function public._w1e_employee_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare m text := public._w1e_choice('employee_pay_dup_mode', 'off'); hit jsonb; chg boolean;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.bank_account is not distinct from old.bank_account and new.mobile_wallet is not distinct from old.mobile_wallet then return new; end if;
  if tg_op = 'UPDATE' and public.rule_on('employee_pay_change_flag') then
    chg := (nullif(btrim(coalesce(old.bank_account, '')), '') is not null and new.bank_account is distinct from old.bank_account)
        or (nullif(btrim(coalesce(old.mobile_wallet, '')), '') is not null and new.mobile_wallet is distinct from old.mobile_wallet);
    if chg then
      perform public._w1e_exc('w1e_pay_account_changed', 'w1e_pay_account', null, 'employees', new.id::text,
        'pay account changed: bank ' || public._w1e_mask(old.bank_account) || ' -> ' || public._w1e_mask(new.bank_account) || ', wallet ' || public._w1e_mask(old.mobile_wallet) || ' -> ' || public._w1e_mask(new.mobile_wallet));
    end if;
  end if;
  if m = 'off' then return new; end if;
  hit := public._w1e_pay_match(new.bank_account, new.mobile_wallet, new.id);
  if jsonb_array_length(hit) = 0 then return new; end if;
  if m = 'block' then
    if not public._m_grant_take('override', 'w1e_pay_account', null, null, null, public._w1e_today(), 'employees:' || new.id::text) then raise exception 'pay_account_duplicate'; end if;
  else
    perform public._w1e_exc('w1e_pay_account_duplicate', 'w1e_pay_account', null, 'employees', new.id::text, 'the same ' || (hit -> 0 ->> 'by') || ' is already used by employee ' || coalesce(hit -> 0 ->> 'employee_no', '-'));
  end if;
  return new;
end $$;
drop trigger if exists a94_w1e_employee_bi on public.employees;
create trigger a94_w1e_employee_bi before insert or update on public.employees for each row execute function public._w1e_employee_bi();

-- ---------- applying an approved request (one function per kind; phase95 adds journal_control) ----------
create or replace function public._w1e_apply_owner_money(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare d date := (r.payload ->> 'move_date')::date; cid uuid := (r.payload ->> 'id')::uuid;
begin
  perform public.lock_check(d);
  if exists (select 1 from public.cash_moves where id = cid) then raise exception 'request_already_applied'; end if;
  insert into public.cash_moves select * from jsonb_populate_record(null::public.cash_moves, r.payload);
  return 'cash_moves:' || cid::text;
end $$;

create or replace function public._w1e_apply_supplier_pay(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare p jsonb := r.payload; pay jsonb; sup uuid := (r.payload ->> 'supplier')::uuid; tot numeric := (r.payload ->> 'total')::numeric; bal numeric; n int := 0;
begin
  perform 1 from public.suppliers where id = sup for update;
  if not found then raise exception 'supplier_not_found'; end if;
  perform public.lock_check(public._w1e_today());
  bal := public._sup_balance(sup);
  if tot > bal then raise exception 'overpaid'; end if;
  for pay in select * from jsonb_array_elements(p -> 'payments') loop
    insert into public.supplier_payments (supplier_id, location_id, bill_id, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (sup, (p ->> 'loc')::int, null, pay ->> 'mode', left(nullif(pay ->> 'wallet', ''), 30), left(nullif(pay ->> 'ref', ''), 60), round((pay ->> 'amount')::numeric, 2),
              left(nullif(btrim(p ->> 'note'), ''), 200), r.requested_by, r.requested_staff, nullif(p ->> 'client', '')::uuid);
    n := n + 1;
  end loop;
  return 'supplier_payments:' || n::text || ' rows for ' || sup::text;
end $$;

create or replace function public._w1e_apply(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare out text; fname text := '_w1e_apply_' || r.kind;
begin
  if to_regprocedure('public.' || fname || '(public.w1e_requests)') is null then raise exception 'request_kind_unavailable'; end if;
  execute format('select public.%I($1)', fname) into out using r;
  return out;
end $$;

-- ---------- API: requests ----------
create or replace function public.w1e_requests_list(p_status text default 'pending', p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select q.id, q.kind, q.status, q.location_id, q.amount, q.ref_date, q.summary, q.requested_by, q.requested_staff, q.requested_at, q.decided_staff, q.decided_at, q.decision_note,
           q.approver_user, q.approver_role, q.approver_reason, q.applied_ref,
           (q.status = 'pending' and q.requested_by <> me and public._w1e_user_is_approver(me, q)) as can_decide,
           (q.status = 'pending' and (q.requested_by = me or public.is_owner())) as can_cancel,
           (q.requested_by = me) as mine
      from public.w1e_requests q
     where (p_status is null or q.status = p_status)
       and (public.is_owner() or q.requested_by = me or public._w1e_user_is_approver(me, q))
     order by q.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

create or replace function public.w1e_request_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests; ok boolean; ref text; sid text := public._w1e_staff();
begin
  if not public.is_active() or p_approve is null then raise exception 'not allowed'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if r.requested_by = auth.uid() then raise exception 'self_approval'; end if;
  ok := public._w1e_user_is_approver(auth.uid(), r);
  if not ok then
    if public._m_grant_take('approver', 'w1e_' || r.kind, null, null, r.amount, public._w1e_today(), 'w1e_requests:' || r.id::text) then ok := true; end if;
  end if;
  if not ok then raise exception 'approver_only'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  if p_approve then
    perform set_config('w1e.apply', '1', true);
    ref := public._w1e_apply(r);
    perform set_config('w1e.apply', '', true);
  end if;
  update public.w1e_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
         decision_note = left(btrim(p_note), 300), applied_ref = ref where id = p_id;
  perform public._w1e_audit('w1e_request_decide', 'w1e_requests', p_id::text, jsonb_build_object('kind', r.kind, 'approve', p_approve, 'note', left(p_note, 300), 'applied', ref, 'maker', r.requested_by));
  return jsonb_build_object('id', p_id, 'status', case when p_approve then 'approved' else 'rejected' end, 'applied', ref);
end $$;

create or replace function public.w1e_request_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.requested_by <> auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  update public.w1e_requests set status = 'cancelled', decided_by = auth.uid(), decided_staff = public._w1e_staff(), decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  perform public._w1e_audit('w1e_request_cancel', 'w1e_requests', p_id::text, jsonb_build_object('kind', r.kind, 'note', left(p_note, 300)));
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- the owner names the approver of ONE request (a person or a role); reason required; the maker is never the approver
create or replace function public.w1e_request_approver_set(p_id bigint, p_user uuid default null, p_role text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.w1e_requests; rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_user is null and rl is null then raise exception 'approver_required'; end if;
  select * into r from public.w1e_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  if p_user is not null then
    if p_user = r.requested_by then raise exception 'approver_is_maker'; end if;
    if not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  if rl is not null and not exists (select 1 from public.roles where code = rl and active) then raise exception 'bad_role'; end if;
  update public.w1e_requests set approver_user = p_user, approver_role = rl, approver_set_by = auth.uid(), approver_set_at = now(), approver_reason = left(btrim(p_reason), 300) where id = p_id;
  perform public._w1e_audit('w1e_request_approver_set', 'w1e_requests', p_id::text, jsonb_build_object('user', p_user, 'role', rl, 'reason', left(p_reason, 300)));
  return jsonb_build_object('id', p_id, 'approver_user', p_user, 'approver_role', rl);
end $$;

-- ---------- API: exceptions of this package, state, checks ----------
create or replace function public.w1e_exceptions_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object('rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
      select x.id, x.at, x.kind, x.event_type, x.amount, x.src_table, x.src_id, x.reason, x.status, x.resolve_note, x.resolved_at,
             case when x.kind in ('w1e_pay_account_duplicate', 'w1e_pay_account_changed') then 'red' else 'yellow' end as level
        from public.money_exceptions x
       where (x.kind like 'w1e\_%' or x.event_type like 'w1e\_%') and (p_status is null or x.status = p_status)
       order by x.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb),
    'grants', case when public.is_owner() then coalesce((select jsonb_agg(to_jsonb(g) order by g.id desc) from (
        select id, rule, event_type, for_user, client_id, reason, granted_at, expires_at, used_at, revoked from public.money_exception_grants where event_type like 'w1e\_%' or event_type is null order by id desc limit 100) g), '[]'::jsonb) else '[]'::jsonb end);
end $$;

create or replace function public.w1e_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ks text[] := array['owner_money_entry_mode', 'bank_slip_required', 'bank_move_large_over', 'bank_move_backdate_days', 'supplier_pay_dup_mode', 'supplier_pay_dup_hours', 'supplier_pay_over',
  'supplier_dup_mode', 'employee_pay_dup_mode', 'employee_pay_change_flag', 'journal_loc_check', 'mapping_type_guard', 'journal_attach_over', 'journal_control_acct_mode', 'journal_control_prefixes'];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'settings', coalesce((select jsonb_object_agg(r.key, coalesce(r.value, r.default_value)) from public.rules r where r.key = any (ks)), '{}'::jsonb),
    'pending', (select count(*) from public.w1e_requests where status = 'pending'
                  and (public.is_owner() or requested_by = auth.uid() or public._w1e_user_is_approver(auth.uid(), w1e_requests))),
    'approver', jsonb_build_object('mode', public._owner_mode(), 'role', public.rule_txt('owner_approver_role'), 'users', to_jsonb(public._owner_approver_users())),
    'hooks', jsonb_build_object(
      'pay_supplier', position('w1e94' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure)) > 0,
      'cash_move_add', position('w1e94c' in pg_get_functiondef('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure)) > 0,
      'acct_journal_post', coalesce(position('w1e95' in pg_get_functiondef(to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'))) > 0, false)),
    'is_owner', public.is_owner());
end $$;

-- read only: who shares a vendor identity or a pay account right now (owner or accounts); account numbers are masked
create or replace function public.w1e_checks() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._m_view() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'vendors', coalesce((select jsonb_agg(to_jsonb(v)) from (
        select a.id as a_id, a.name as a_name, b.id as b_id, b.name as b_name,
               case when public._w1e_nname(a.name) = public._w1e_nname(b.name) then 'name' when public._w1e_nmobile(a.mobile) is not null and public._w1e_nmobile(a.mobile) = public._w1e_nmobile(b.mobile) then 'mobile' else 'tin' end as by
          from public.suppliers a join public.suppliers b on a.id < b.id and a.active and b.active
           and (public._w1e_nname(a.name) = public._w1e_nname(b.name)
             or (public._w1e_nmobile(a.mobile) is not null and public._w1e_nmobile(a.mobile) = public._w1e_nmobile(b.mobile))
             or (public._w1e_nalnum(a.tin) is not null and public._w1e_nalnum(a.tin) = public._w1e_nalnum(b.tin))) limit 200) v), '[]'::jsonb),
    'pay_accounts', coalesce((select jsonb_agg(to_jsonb(v)) from (
        select a.id as a_id, a.employee_no as a_no, b.id as b_id, b.employee_no as b_no,
               case when public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account) then 'bank_account' else 'mobile_wallet' end as by,
               public._w1e_mask(case when public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account) then a.bank_account else a.mobile_wallet end) as account
          from public.employees a join public.employees b on a.id < b.id and a.status not in ('resigned', 'terminated', 'retired', 'discarded') and b.status not in ('resigned', 'terminated', 'retired', 'discarded')
           and ((public._w1e_nalnum(a.bank_account) is not null and public._w1e_nalnum(a.bank_account) = public._w1e_nalnum(b.bank_account))
             or (public._w1e_nmobile(a.mobile_wallet) is not null and public._w1e_nmobile(a.mobile_wallet) = public._w1e_nmobile(b.mobile_wallet))) limit 200) v), '[]'::jsonb));
end $$;

-- pre-checks for the screens (warn before saving)
create or replace function public.w1e_vendor_check(p_name text, p_mobile text default null, p_tin text default null, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public.has_grant('supplier_manage') or public.has_grant('purchase_entry')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('matches', public._w1e_vendor_match(p_name, p_mobile, p_tin, p_exclude), 'mode', public._w1e_choice('supplier_dup_mode', 'off'));
end $$;
create or replace function public.w1e_pay_account_check(p_bank text default null, p_wallet text default null, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._m_view() or public.has_grant('employee_manage')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('matches', public._w1e_pay_match(p_bank, p_wallet, p_exclude), 'mode', public._w1e_choice('employee_pay_dup_mode', 'off'));
end $$;

-- ---------- more separation-of-duty pairs (non blocking suggestions; shown on #/delegation through grant_separation_report) ----------
insert into public.grant_separation_pairs (code, entry_grant, approve_grant, label_bn, label_en) values
 ('cash_move_release', 'cash_move', 'release_decide', 'Cash move entry and release decision', 'Cash move entry and release decision'),
 ('supplier_pay_purchase', 'supplier_pay', 'purchase_entry', 'Supplier payment and purchase entry', 'Supplier payment and purchase entry'),
 ('payroll_employee', 'payroll_manage', 'employee_manage', 'Payroll and employee records', 'Payroll and employee records'),
 ('accounts_purchase', 'accounts_manage', 'purchase_entry', 'Accounts manage and purchase entry', 'Accounts manage and purchase entry'),
 ('supplier_pay_manage', 'supplier_manage', 'supplier_pay', 'Supplier records and supplier payment', 'Supplier records and supplier payment'),
 ('cash_move_accounts', 'cash_move', 'accounts_manage', 'Cash move entry and accounts manage', 'Cash move entry and accounts manage'),
 ('purchase_enter_void', 'purchase_entry', 'purchase_void', 'Purchase entry and purchase void', 'Purchase entry and purchase void')
on conflict (code) do nothing;

-- ---------- privileges: internals closed, API open to signed-in users (each function checks its own permission) ----------
revoke all on function public._p94_present(), public._w1e_add_exc_kinds(text[]), public._w1e_today(), public._w1e_staff(), public._w1e_choice(text, text), public._w1e_nalnum(text), public._w1e_nname(text),
  public._w1e_nmobile(text), public._w1e_mask(text), public._w1e_exc(text, text, numeric, text, text, text), public._w1e_audit(text, text, text, jsonb), public._w1e_user_is_approver(uuid, public.w1e_requests),
  public._w1e_cash_bi(), public._w1e_cash_pending(uuid), public._w1e_pay_gate(uuid, int, jsonb, uuid, text, numeric), public._w1e_vendor_match(text, text, text, uuid), public._w1e_supplier_bi(),
  public._w1e_pay_match(text, text, uuid), public._w1e_employee_bi(), public._w1e_apply_owner_money(public.w1e_requests), public._w1e_apply_supplier_pay(public.w1e_requests), public._w1e_apply(public.w1e_requests)
  from public, anon, authenticated;
revoke all on function public.w1e_requests_list(text, int), public.w1e_request_decide(bigint, boolean, text), public.w1e_request_cancel(bigint, text), public.w1e_request_approver_set(bigint, uuid, text, text),
  public.w1e_exceptions_list(text, int), public.w1e_state(), public.w1e_checks(), public.w1e_vendor_check(text, text, text, uuid), public.w1e_pay_account_check(text, text, uuid) from public, anon, authenticated;
grant execute on function public.w1e_requests_list(text, int), public.w1e_request_decide(bigint, boolean, text), public.w1e_request_cancel(bigint, text), public.w1e_request_approver_set(bigint, uuid, text, text),
  public.w1e_exceptions_list(text, int), public.w1e_state(), public.w1e_checks(), public.w1e_vendor_check(text, text, text, uuid), public.w1e_pay_account_check(text, text, uuid) to authenticated;

-- ===================== phase95.sql =====================
-- Phase 95 (bos95) - JOURNAL, CHART AND MAPPING CONTROLS (package W1-E, item U-08). Paste AFTER phase94 (which brings the request list and the approver logic). Paste-twice safe.
-- Earlier phase files are not edited. No shared function is replaced by this file. Controls that can be a trigger ARE triggers (they work without any hook):
--   journal_loc_check  - every line of a MANUAL journal must be in a place the caller may use (or the caller holds the all-places accounts right, or is the owner)
--   mapping_type_guard - a mapping key may only point to the account types listed in table w1e_mapping_types (owner editable)
-- Controls that need the whole journal (its total, its accounts) go through ONE gate function, _w1e_journal_gate, called by a hook in acct_journal_post (integrator, docs/integration/W1-E.md):
--   journal_attach_over        - blank = off; a manual journal above this total needs an attachment (the photo path)
--   journal_control_acct_mode  - allow (default) | request | block; a journal by a non-owner that touches a control account (cash, bank, receivable, payable, inventory)
-- SETTINGS (rules, module books, English label and hint, owner editable at any time, audit_log by the existing audit_rules trigger). Every default keeps TODAY'S behaviour:
--   journal_loc_check off, mapping_type_guard off, journal_attach_over blank, journal_control_acct_mode allow, journal_control_prefixes "11,1210,13,2100" (chart code prefixes of the control accounts)
-- Approval of a held journal uses the approver chosen under phase87 (see phase94). The maker never decides his own request. One-off exceptions: the phase87 grant (rule 'override'),
--   events w1e_journal_loc, w1e_journal_attach, w1e_journal_control, w1e_mapping; reason required, audit_log line, Exceptions row. A journal that does not balance is NEVER excepted.
-- Nothing is deleted. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p94_present()') is null then raise exception 'phase95 needs phase94 first'; end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null or to_regprocedure('public.acct_mapping_set(text,bigint)') is null then
    raise exception 'phase95 needs the accounting of phase40';
  end if;
end $g$;

create or replace function public._p95_present() returns boolean language sql immutable as $$ select true $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'books', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('journal_loc_check', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Check the place of every line of a manual journal',
   'When ON, a person may post a manual journal line only to a place he may use, and a line without a place needs the all-places right. Off = today. Recommended: ON.', 750),
 ('mapping_type_guard', 'switch', 'false'::jsonb, null, null, null, null,
   'Check the account type when a mapping is changed',
   'When ON, a mapping key (for example sales) may only point to the account types listed for it (for example income). Off = today. Recommended: ON.', 751),
 ('journal_attach_over', 'number', null, 'Tk', null, 0, 1000000000000,
   'A manual journal above this total needs an attachment',
   'Blank = off. Above this total the journal must carry a photo or file reference.', 752),
 ('journal_control_acct_mode', 'choice', '"allow"'::jsonb, null, '["allow","request","block"]'::jsonb, null, null,
   'Manual journal by a person who is not the owner on a cash, bank, receivable, payable or inventory account',
   'allow = today. request = the journal waits for the approver chosen under "Approval of the owner''s own entries". block = refused unless the owner allows one exception.', 753),
 ('journal_control_prefixes', 'text', '"11,1210,13,2100"'::jsonb, null, null, null, null,
   'Chart codes that count as control accounts',
   'Comma separated code beginnings. Default: 11 (cash, bank, wallets), 1210 (customer receivables), 13 (inventory), 2100 (supplier payables).', 754)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- which account types a mapping key may point to (editable by the owner, never deleted: switch a row off) ----------
create table if not exists public.w1e_mapping_types (
  key_like text primary key check (length(key_like) between 2 and 60),
  allowed text[] not null check (array_length(allowed, 1) >= 1 and allowed <@ array['asset', 'liability', 'equity', 'income', 'expense']),
  active boolean not null default true,
  note text, updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists w1e_mapping_types_nodel on public.w1e_mapping_types;
create trigger w1e_mapping_types_nodel before delete on public.w1e_mapping_types for each row execute function public.no_hard_delete();
drop trigger if exists audit_w1e_mapping_types on public.w1e_mapping_types;
create trigger audit_w1e_mapping_types after insert or update on public.w1e_mapping_types for each row execute function public.log_change('key_like');
alter table public.w1e_mapping_types enable row level security;
revoke all on public.w1e_mapping_types from public, anon, authenticated;
insert into public.w1e_mapping_types (key_like, allowed, note) values
 ('sales', '{income}', 'sales'), ('sales\_returns', '{income}', 'contra income'), ('sales\_discount', '{income}', 'contra income'), ('cogs', '{expense}', null),
 ('exp\_%', '{expense}', 'expense heads'), ('inv\_%', '{asset}', 'inventory'), ('receivable', '{asset}', null), ('payable', '{liability}', null), ('pay\_%', '{asset}', 'cash, bank, mobile, card'),
 ('cust\_advance', '{liability}', null), ('owner\_capital', '{equity}', null), ('owner\_drawings', '{equity}', 'contra equity'), ('retained', '{equity}', null), ('retained\_close', '{equity}', null),
 ('partner\_ps\_%', '{equity,expense}', 'partner profit share'), ('partner\_loan', '{liability}', null), ('partner\_payable', '{liability}', null),
 ('salary\_exp', '{expense}', null), ('salary\_accrued', '{liability}', null), ('staff\_advance', '{asset}', null), ('fixed\_assets', '{asset}', null), ('accum\_depr', '{asset}', 'contra asset'),
 ('depreciation', '{expense}', null), ('cash\_short', '{expense,income}', 'short or over'), ('wastage', '{expense}', null), ('transit\_loss', '{expense}', null), ('carrier\_claim', '{asset}', null),
 ('hub\_clearing', '{asset,liability}', 'clearing'), ('wallet\_fee', '{expense}', null), ('m\_bank\_charge', '{expense}', null), ('m\_interest\_income', '{income}', null),
 ('overhead\_absorbed', '{expense}', 'contra expense'), ('purch\_%', '{expense}', null), ('m\_acct\_%', '{asset}', 'money accounts'), ('d\_wallet\_%', '{asset}', 'legacy wallets')
on conflict (key_like) do nothing;

-- ---------- helpers ----------
create or replace function public._w1e_is_control(p_account bigint) returns boolean language plpgsql stable security definer set search_path = public as $$
declare code text; pf text;
begin
  select a.code into code from public.coa_accounts a where a.id = p_account;
  if code is null then return false; end if;
  for pf in select btrim(x) from unnest(string_to_array(coalesce(public.rule_txt('journal_control_prefixes'), '11,1210,13,2100'), ',')) x loop
    if pf <> '' and code like pf || '%' then return true; end if;
  end loop;
  return false;
end $$;

create or replace function public._w1e_journal_loc_ok(p_lines jsonb, p_loc int) returns boolean language plpgsql stable security definer set search_path = public as $$
declare e jsonb; lc int;
begin
  for e in select * from jsonb_array_elements(p_lines) loop
    lc := coalesce(nullif(e ->> 'location_id', '')::int, p_loc);
    if not (public._acct_all() or (lc is not null and public.can_loc(lc))) then return false; end if;
  end loop;
  return true;
end $$;

-- ---------- control 1: the place of every line of a manual journal (trigger; works without the hook) ----------
create or replace function public._w1e_jl_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare e record; lc int;
begin
  if auth.uid() is null or not public.rule_on('journal_loc_check') or coalesce(current_setting('w1e.apply', true), '') = '1' or coalesce(current_setting('w1e.jl_loc', true), '') = '1' then return new; end if;
  select entry_date, location_id, source_type, reverses_id, client_id, id into e from public.journal_entries where id = new.entry_id;
  if not found or e.source_type <> 'manual' or e.reverses_id is not null then return new; end if;
  lc := coalesce(new.location_id, e.location_id);
  if public._acct_all() or (lc is not null and public.can_loc(lc)) then return new; end if;
  if public._m_grant_take('override', 'w1e_journal_loc', e.client_id, null, null, e.entry_date, 'journal_entries:' || e.id::text) then
    perform set_config('w1e.jl_loc', '1', true);
    return new;
  end if;
  raise exception 'journal_place_not_allowed' using detail = 'line ' || new.line_no::text || ' place ' || coalesce(lc::text, 'none');
end $$;
drop trigger if exists a95_w1e_jl_bi on public.journal_lines;
create trigger a95_w1e_jl_bi before insert on public.journal_lines for each row execute function public._w1e_jl_bi();

-- ---------- control 2: the account type of a mapping (trigger; works without the hook) ----------
create or replace function public._w1e_mapping_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare t text; allowed text[];
begin
  if auth.uid() is null or not public.rule_on('mapping_type_guard') or coalesce(current_setting('w1e.apply', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and new.account_id is not distinct from old.account_id then return new; end if;
  select m.allowed into allowed from public.w1e_mapping_types m where m.active and new.key like m.key_like order by length(m.key_like) desc, m.key_like limit 1;
  if allowed is null then return new; end if;
  select a.type into t from public.coa_accounts a where a.id = new.account_id;
  if t = any (allowed) then return new; end if;
  if coalesce(current_setting('w1e.map_ok', true), '') = new.key || ':' || new.account_id::text then return new; end if;      -- INSERT .. ON CONFLICT fires the trigger twice: one exception covers both
  if public._m_grant_take('override', 'w1e_mapping', null, null, null, public._w1e_today(), 'acct_mappings:' || new.key) then
    perform set_config('w1e.map_ok', new.key || ':' || new.account_id::text, true);
    return new;
  end if;
  raise exception 'mapping_type_mismatch' using detail = 'key ' || new.key || ' needs ' || array_to_string(allowed, ' or ') || ', account is ' || coalesce(t, '?');
end $$;
drop trigger if exists a95_w1e_mapping_bi on public.acct_mappings;
create trigger a95_w1e_mapping_bi before insert or update on public.acct_mappings for each row execute function public._w1e_mapping_bi();

-- ---------- controls 3 and 4: attachment above a total, and journals on control accounts (called from the acct_journal_post hook with the resolved lines) ----------
create or replace function public._w1e_journal_gate(p_date date, p_loc int, p_memo text, p_lines jsonb, p_photo text, p_client uuid, p_total numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ov numeric := public.rule_num('journal_attach_over'); md text := public._w1e_choice('journal_control_acct_mode', 'allow'); ctl boolean := false; x jsonb; rid bigint; ex public.w1e_requests;
begin
  if auth.uid() is null or coalesce(current_setting('w1e.apply', true), '') = '1' then return null; end if;
  if p_client is not null then
    select * into ex from public.w1e_requests where client_id = p_client and kind = 'journal_control';
    if found then return jsonb_build_object('pending', true, 'request_id', ex.id, 'dup', true); end if;
  end if;
  if ov is not null and p_total > ov and nullif(btrim(coalesce(p_photo, '')), '') is null then
    if not public._m_grant_take('override', 'w1e_journal_attach', p_client, null, p_total, p_date, 'journal') then
      raise exception 'attachment_required' using detail = 'total ' || p_total::text || ' is above ' || ov::text;
    end if;
  end if;
  if md <> 'allow' and not public.is_owner() then
    for x in select * from jsonb_array_elements(p_lines) loop
      if public._w1e_is_control((x ->> 'account_id')::bigint) then ctl := true; exit; end if;
    end loop;
    if ctl then
      if md = 'block' then
        if not public._m_grant_take('override', 'w1e_journal_control', p_client, null, p_total, p_date, 'journal') then raise exception 'control_account_blocked'; end if;
      else
        if public.rule_on('journal_loc_check') and not public._w1e_journal_loc_ok(p_lines, p_loc) then      -- the approver posts it later: the maker's own place rights are checked now
          if not public._m_grant_take('override', 'w1e_journal_loc', p_client, null, null, p_date, 'journal') then raise exception 'journal_place_not_allowed'; end if;
        end if;
        insert into public.w1e_requests (kind, location_id, amount, ref_date, summary, payload, client_id, requested_by, requested_staff)
          values ('journal_control', p_loc, p_total, p_date, left('Manual journal ' || p_total::text || ' on ' || p_date::text || ': ' || coalesce(p_memo, ''), 300),
                  jsonb_build_object('date', p_date, 'loc', p_loc, 'memo', p_memo, 'lines', p_lines, 'photo', p_photo, 'client', p_client, 'total', p_total), p_client, auth.uid(), public._w1e_staff())
          returning id into rid;
        perform public._w1e_audit('w1e_request_create', 'w1e_requests', rid::text, jsonb_build_object('kind', 'journal_control', 'amount', p_total, 'date', p_date));
        perform public._w1e_exc('w1e_journal_request', 'w1e_journal_control', p_total, 'w1e_requests', rid::text, 'manual journal on a control account waits for the approver');
        return jsonb_build_object('pending', true, 'request_id', rid, 'total', p_total);
      end if;
    end if;
  end if;
  return null;
end $$;

create or replace function public._w1e_apply_journal_control(r public.w1e_requests) returns text language plpgsql security definer set search_path = public as $$
declare p jsonb := r.payload; id_ bigint;
begin
  perform public.lock_check((p ->> 'date')::date);
  id_ := public._acct_write((p ->> 'date')::date, nullif(p ->> 'loc', '')::int, 'manual', coalesce(nullif(p ->> 'client', ''), gen_random_uuid()::text), null,
                            left(coalesce(p ->> 'memo', ''), 240) || ' [request ' || r.id::text || ']', null, p -> 'lines', null, nullif(p ->> 'client', '')::uuid, nullif(p ->> 'photo', ''));
  return 'journal_entries:' || id_::text;
end $$;

-- ---------- API ----------
create or replace function public.w1e_mapping_check(p_key text, p_account bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t text; allowed text[];
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  select m.allowed into allowed from public.w1e_mapping_types m where m.active and p_key like m.key_like order by length(m.key_like) desc, m.key_like limit 1;
  select a.type into t from public.coa_accounts a where a.id = p_account;
  return jsonb_build_object('key', p_key, 'type', t, 'allowed', to_jsonb(allowed), 'ok', allowed is null or t = any (allowed), 'guard_on', public.rule_on('mapping_type_guard'));
end $$;

create or replace function public.w1e_mapping_types_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._acct_view() or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key_like', key_like, 'allowed', to_jsonb(allowed), 'active', active, 'note', note) order by key_like) from public.w1e_mapping_types), '[]'::jsonb);
end $$;

create or replace function public.w1e_mapping_type_set(p_key_like text, p_allowed text[], p_active boolean default true, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_ public.w1e_mapping_types;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_key_like is null or p_key_like !~ '^[a-z0-9_%\\]{2,60}$' then raise exception 'bad_key'; end if;
  select * into old_ from public.w1e_mapping_types where key_like = p_key_like;
  insert into public.w1e_mapping_types (key_like, allowed, active, note, updated_by, updated_at) values (p_key_like, p_allowed, coalesce(p_active, true), left(btrim(p_reason), 300), auth.uid(), now())
    on conflict (key_like) do update set allowed = excluded.allowed, active = excluded.active, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  perform public._w1e_audit('w1e_mapping_type_set', 'w1e_mapping_types', p_key_like, jsonb_build_object('old', case when old_.key_like is not null then jsonb_build_object('allowed', to_jsonb(old_.allowed), 'active', old_.active) end,
          'new', jsonb_build_object('allowed', to_jsonb(p_allowed), 'active', coalesce(p_active, true)), 'reason', left(p_reason, 300)));
  return jsonb_build_object('key_like', p_key_like, 'allowed', to_jsonb(p_allowed), 'active', coalesce(p_active, true));
end $$;

-- ---------- privileges ----------
revoke all on function public._p95_present(), public._w1e_is_control(bigint), public._w1e_journal_loc_ok(jsonb, int), public._w1e_jl_bi(), public._w1e_mapping_bi(),
  public._w1e_journal_gate(date, int, text, jsonb, text, uuid, numeric), public._w1e_apply_journal_control(public.w1e_requests) from public, anon, authenticated;
revoke all on function public.w1e_mapping_check(text, bigint), public.w1e_mapping_types_list(), public.w1e_mapping_type_set(text, text[], boolean, text) from public, anon, authenticated;
grant execute on function public.w1e_mapping_check(text, bigint), public.w1e_mapping_types_list(), public.w1e_mapping_type_set(text, text[], boolean, text) to authenticated;

-- ===================== phase96.sql =====================
-- Phase 96 (bos96) - W1-F / U-09: CHART AND MAPPING COMPLETENESS, expense heads, other income. Paste after phase87 (any later phase may come first), paste-twice safe.
-- Earlier phase files are not edited. No shared function is re-created here: every change to a shared function is a HOOK written in docs/integration/W1-F.md.
--
-- WHAT THIS ADDS
--   1. A seed catalogue (table w1f_seed_state) of chart accounts and mapping keys that a real shop needs: rent, utilities, marketing, other income (existing accounts 5300, 5400,
--      5500, 4900 get their mapping key), courier cash receivable 1250, staff security deposits 2700, purchase discounts 4910, rounding 5880, bad debts 5890, gain / loss on disposal
--      4920 / 5895, VAT payable 2800 and withholding tax payable 2810 (the last two inactive placeholders). An existing account is NEVER touched or overwritten: if the code is taken
--      the key stays unmapped and the owner chooses (_w1f_seed_map). Every name and mapping is editable by the owner (_w1f_seed_edit, _w1f_seed_map) and the owner can use another code (_w1f_seed_new_code: a new account takes over the key, the old one is retired when empty); each change has an audit_log line and a reason where it moves money between accounts.
--   2. Expense heads: rent, utilities and marketing are added to the list expense_heads as RETIRED rows (the 10-2 form does not offer them) until the owner turns each on with
--      _w1f_expense_head_set, which also sets the mapping key exp_<head>. Turning a head on never moves an old figure: documents older than the effective date that are still unposted
--      block it unless the owner gives a reason (audit_log + Exceptions row).
--   3. Other income (scrap, old oil, rent received, supplier discount ...): list other_income_heads, table other_income, entry _w1f_other_income_add (head, mode, money account from the
--      phase87 picker, photo), void, list. Dr cash / bank / wallet, Cr 4900 (or the head's own account). OFF until the owner switches rule other_income_on.
--   4. Mapping coverage check _w1f_mapping_coverage (unmapped key list for the Balance Check screen).
-- SETTINGS (rules; every change is written to audit_log by the rules trigger):  other_income_on (OFF)   other_income_from (blank = no start date)
-- HOOKS (not in this file, see the integration note): journal source _w1f_docs into _acct_docs, day book rows _w1f_daybook_rows into _daybook_lines, coverage line into _e_balance_check,
--   legacy wallets 1131-1134 into acct_cash_flow. Until the integrator pastes the hooks an other-income entry is recorded but not yet in the journal.

do $g$ begin
  if to_regprocedure('public._p87_present()') is null then raise exception 'phase96 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null or to_regclass('public.money_event_settings') is null then
    raise exception 'phase96 needs the money accounts of phase87';
  end if;
end $g$;

create or replace function public._w1f_present96() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic helpers ----------
-- exact-text patch of a LIVE function with a marker of the caller's choice. phase87 _m_patch is a no-op on every function that already carries bos87 (all of the shared ones do),
-- so the hooks of this package use this one. Any missing patch site stops the paste and nothing is half changed. Already patched (marker present) = no-op.
create or replace function public._w1f_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bos96') returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'marker_required'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

create or replace function public._w1f_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;

-- who may change the chart seeds and the heads: the owner (heads) and the accounts manager (seeds); a hidden button is also a refused request
create or replace function public._w1f_chart_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_manage()) $$;
create or replace function public._w1f_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public._acct_view()) $$;

-- a yellow line in the Exceptions list (table exceptions, the list used by void_collection) for a rule that was waived with a reason
create or replace function public._w1f_exception(p_form text, p_loc int, p_date date, p_flag text, p_amount numeric, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare lc int := coalesce(p_loc, (select min(ul.location_id) from public.user_locations ul where ul.user_id = auth.uid()), (select min(id) from public.locations));
begin
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
  values (null, null, p_form, lc, coalesce(p_date, public._acct_today()), p_flag, 'yellow', p_amount, jsonb_build_object('bn', p_text, 'en', p_text));
end $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('other_income_on', 'books', 'switch', 'false', 'Other income entry (scrap, old oil, rent received)', 'Other income entry (scrap, old oil, rent received)', 'Other income entry (scrap, old oil, rent received)',
  'OFF = the Other income screen refuses entries', 'OFF (default) = the Other income screen refuses entries. ON = staff with the cash move permission can record money that is not a sale, posted to Other income.', 960),
 ('other_income_from', 'books', 'text', null, 'Other income counts from this date', 'Other income counts from this date', 'Other income counts from this date (YYYY-MM-DD)',
  'Blank = any date', 'Blank = any date. When set, an entry dated before it is refused, so an old month never changes.', 961)
on conflict (key) do nothing;

-- ---------- the seed catalogue ----------
create table if not exists public.w1f_seed_state (
  key text primary key,                                   -- mapping key
  code text not null,                                     -- proposed chart code (the account may be recoded by the owner later)
  name_en text not null, name_bn text not null,
  type text not null check (type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_code text,
  purpose text not null,
  placeholder boolean not null default false,             -- created inactive
  existing boolean not null default false,                -- the account is one of the standard chart accounts: only the mapping key is added
  ord int not null default 100,
  status text not null default 'pending' check (status in ('pending', 'created', 'mapped_existing', 'owner_mapping_kept', 'code_taken', 'type_mismatch', 'history_exists')),
  account_id bigint references public.coa_accounts(id),
  note text,
  seeded_at timestamptz
);
insert into public.w1f_seed_state (key, code, name_en, name_bn, type, parent_code, purpose, placeholder, existing, ord) values
 ('exp_rent', '5300', 'Rent', 'Rent', 'expense', null, 'Rent paid for shops, factory and stores', false, true, 10),
 ('exp_utilities', '5400', 'Utilities', 'Utilities', 'expense', null, 'Electricity, gas, water and internet', false, true, 20),
 ('exp_marketing', '5500', 'Marketing', 'Marketing', 'expense', null, 'Advertising, printing and promotions', false, true, 30),
 ('other_income', '4900', 'Other income', 'Other income', 'income', null, 'Scrap, old oil, rent received and other money that is not a sale', false, true, 40),
 ('courier_receivable', '1250', 'Courier cash receivable', 'Courier cash receivable', 'asset', '1200', 'Cash on delivery collected by couriers and delivery platforms, not yet handed over', false, false, 50),
 ('staff_deposit', '2700', 'Staff security deposits', 'Staff security deposits', 'liability', '2000', 'Deposits held from staff and owed back to them', false, false, 60),
 ('purchase_discount', '4910', 'Purchase discounts received', 'Purchase discounts received', 'income', '4000', 'Discounts and rebates given by suppliers', false, false, 70),
 ('rounding', '5880', 'Rounding differences', 'Rounding differences', 'expense', null, 'Small rounding differences', false, false, 80),
 ('bad_debt', '5890', 'Bad debts written off', 'Bad debts written off', 'expense', null, 'Customer dues the owner has decided will not be paid', false, false, 90),
 ('disposal_gain', '4920', 'Gain on disposal of fixed assets', 'Gain on disposal of fixed assets', 'income', '4000', 'Profit when a fixed asset is sold above its book value', false, false, 100),
 ('disposal_loss', '5895', 'Loss on disposal of fixed assets', 'Loss on disposal of fixed assets', 'expense', null, 'Loss when a fixed asset is sold below its book value', false, false, 110),
 ('vat_payable', '2800', 'VAT payable (not in use yet)', 'VAT payable (not in use yet)', 'liability', '2000', 'Placeholder for VAT. Inactive until the owner and the adviser decide', true, false, 120),
 ('wht_payable', '2810', 'Withholding tax payable (not in use yet)', 'Withholding tax payable (not in use yet)', 'liability', '2000', 'Placeholder for withholding tax. Inactive until the owner and the adviser decide', true, false, 130)
on conflict (key) do nothing;

-- unposted documents that use an expense head and are dated before p_before (null = any date). Posted documents are in the journal already and never move.
create or replace function public._w1f_head_unposted(p_code text, p_before date default null) returns bigint language sql stable security definer set search_path = public as $$
  select (select count(*) from public.entries e
           where e.form_code = '10-2' and e.status in ('submitted', 'approved') and (p_before is null or e.entry_date < p_before)
             and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x
                          where regexp_replace(lower(coalesce(nullif(btrim(x ->> 'head'), ''), 'other')), '[^a-z0-9_]', '_', 'g') = p_code and public._acct_num(x ->> 'amount') > 0)
             and not exists (select 1 from public.journal_entries j where j.source_type = 'expense_voucher' and j.source_id like e.id::text || ':%' and j.reverses_id is null))
       + (select count(*) from public.quick_expenses q
           where q.head = p_code and q.status = 'done' and (p_before is null or q.exp_date < p_before)
             and not exists (select 1 from public.journal_entries j where j.source_type = 'quick_expense' and j.source_id = q.id::text and j.reverses_id is null)) $$;

-- one pass over the catalogue. Never overwrites: an existing account, an existing mapping key or a taken code is left exactly as it is.
create or replace function public._w1f_seed_run() returns int language plpgsql security definer set search_path = public as $$
declare r public.w1f_seed_state; a public.coa_accounts; m public.acct_mappings; par public.coa_accounts; n int := 0; nid bigint; st text; nt text;
begin
  for r in select * from public.w1f_seed_state where status in ('pending', 'code_taken', 'type_mismatch', 'history_exists') order by ord, key loop
    st := null; nt := null; nid := null;
    select * into m from public.acct_mappings where key = r.key;
    if found then
      st := 'owner_mapping_kept'; nid := m.account_id; nt := 'the key was already mapped; left as it is';
    else
      select * into a from public.coa_accounts where code = r.code;
      if found and r.existing then
        if a.type <> r.type or a.is_group then st := 'type_mismatch'; nt := 'code ' || r.code || ' exists with another type; the owner chooses the account';
        elsif r.key like 'exp\_%' and public._w1f_head_unposted(substring(r.key from 5), null) > 0 then st := 'history_exists'; nt := 'unposted documents already use this head; map it with a reason';
        else
          insert into public.acct_mappings (key, account_id, label_bn, label_en) values (r.key, a.id, r.name_en, r.purpose);
          st := 'mapped_existing'; nid := a.id;
        end if;
      elsif found then
        st := 'code_taken'; nt := 'code ' || r.code || ' is used by another account; the owner chooses the account';
      else
        select * into par from public.coa_accounts where code = r.parent_code and is_group and type = r.type;
        insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, active, sort)
          values (r.code, r.name_bn, r.name_en, r.type, case when r.type in ('asset', 'expense') then 'debit' else 'credit' end, par.id, false, false, not r.placeholder, 600 + r.ord)
          returning * into a;
        if not r.placeholder then insert into public.acct_mappings (key, account_id, label_bn, label_en) values (r.key, a.id, r.name_en, r.purpose); end if;   -- a placeholder is mapped when the owner switches it on
        st := 'created'; nid := a.id;
      end if;
    end if;
    if st is distinct from r.status or nid is distinct from r.account_id then
      update public.w1f_seed_state set status = st, account_id = nid, note = nt, seeded_at = now() where key = r.key;
      perform public._w1f_audit('w1f_seed', 'w1f_seed_state', r.key, jsonb_build_object('status', st, 'code', r.code, 'account_id', nid, 'note', nt));
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------- lists: other income heads (new list) and the three expense heads (retired until the owner turns them on) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('other_income_heads', 'scrap_sale', 'Scrap and packaging sale', 'Scrap and packaging sale', 'Scrap and packaging sale', 10, true, '{}'),
 ('other_income_heads', 'old_oil', 'Used cooking oil sale', 'Used cooking oil sale', 'Used cooking oil sale', 20, true, '{}'),
 ('other_income_heads', 'rent_received', 'Rent received', 'Rent received', 'Rent received', 30, true, '{}'),
 ('other_income_heads', 'supplier_discount', 'Supplier discount received in cash', 'Supplier discount received in cash', 'Supplier discount received in cash', 40, true, '{}'),
 ('other_income_heads', 'other', 'Other (write it)', 'Other (write it)', 'Other (write it)', 90, true, '{}')
on conflict (list_code, value_code) do nothing;
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra) values
 ('expense_heads', 'rent', 'Rent', 'Rent', 'Rent', 110, false, '{"w1f_seed": true}'),
 ('expense_heads', 'utilities', 'Utilities (electricity, gas, water)', 'Utilities (electricity, gas, water)', 'Utilities (electricity, gas, water)', 120, false, '{"w1f_seed": true}'),
 ('expense_heads', 'marketing', 'Marketing and advertising', 'Marketing and advertising', 'Marketing and advertising', 130, false, '{"w1f_seed": true}')
on conflict (list_code, value_code) do nothing;

select public._w1f_seed_run();
-- the supplier discount head books to the purchase discount account (only when that key exists and the head key does not)
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'oi_supplier_discount', m.account_id, 'Other income: supplier discount', 'Other income head: supplier discount' from public.acct_mappings m
 where m.key = 'purchase_discount' and not exists (select 1 from public.acct_mappings x where x.key = 'oi_supplier_discount');

-- ---------- reports for the screen ----------
create or replace function public._w1f_seed_report() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('key', s.key, 'proposed_code', s.code, 'purpose', s.purpose, 'status', s.status, 'placeholder', s.placeholder, 'note', s.note,
      'type', s.type, 'mapped', m.account_id is not null, 'has_account', c.id is not null, 'account_id', c.id, 'code', c.code, 'name_en', c.name_en, 'name_bn', c.name_bn, 'active', c.active,
      'has_lines', c.id is not null and exists (select 1 from public.journal_lines l where l.account_id = c.id)) order by s.ord)
    from public.w1f_seed_state s left join public.acct_mappings m on m.key = s.key left join public.coa_accounts c on c.id = coalesce(m.account_id, s.account_id)), '[]'::jsonb);
end $$;

-- the owner (or the accounts manager) edits a seeded account: names and active. The chart CODE of an account never changes (phase40 guard, BUILD-RULES: a code is never given to anything else);
-- to use another code the owner calls _w1f_seed_new_code below, which opens a new account and retires the old one when it is empty.
create or replace function public._w1f_seed_edit(p_key text, p_name_en text default null, p_name_bn text default null, p_active boolean default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; a public.coa_accounts; bal numeric; why text := nullif(btrim(coalesce(p_reason, '')), ''); changed jsonb := '{}';
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key;
  if not found then raise exception 'unknown_key'; end if;
  select c.* into a from public.coa_accounts c where c.id = coalesce((select m.account_id from public.acct_mappings m where m.key = p_key), s.account_id) for update;
  if not found then raise exception 'not_mapped'; end if;
  if p_name_en is not null and (length(btrim(p_name_en)) not between 1 and 120) then raise exception 'name_required'; end if;
  if p_name_bn is not null and (length(btrim(p_name_bn)) not between 1 and 120) then raise exception 'name_required'; end if;
  if p_active is not null and p_active is distinct from a.active then
    if p_active then
      if a.parent_id is not null and not exists (select 1 from public.coa_accounts p where p.id = a.parent_id and p.active) then raise exception 'parent_inactive'; end if;
    else
      select coalesce(sum(l.debit - l.credit), 0) into bal from public.journal_lines l where l.account_id = a.id;
      if abs(bal) > 0.004 then raise exception 'account_has_balance'; end if;
      if why is null or length(why) < 3 then raise exception 'reason_required'; end if;
    end if;
    changed := changed || jsonb_build_object('active', jsonb_build_array(a.active, p_active));
  end if;
  if p_name_en is not null and btrim(p_name_en) is distinct from a.name_en then changed := changed || jsonb_build_object('name_en', jsonb_build_array(a.name_en, btrim(p_name_en))); end if;
  if p_name_bn is not null and btrim(p_name_bn) is distinct from a.name_bn then changed := changed || jsonb_build_object('name_bn', jsonb_build_array(a.name_bn, btrim(p_name_bn))); end if;
  if changed = '{}'::jsonb then return jsonb_build_object('key', p_key, 'changed', false); end if;
  update public.coa_accounts set name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), name_bn = coalesce(nullif(btrim(p_name_bn), ''), name_bn), active = coalesce(p_active, active) where id = a.id;
  if p_active is true then   -- a placeholder gets its mapping key the day the owner switches it on
    insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values (p_key, a.id, s.name_en, s.purpose, auth.uid()) on conflict (key) do nothing;
  end if;
  perform public._w1f_audit('w1f_seed_edit', 'coa_accounts', a.id::text, jsonb_build_object('key', p_key, 'changes', changed, 'reason', why));
  return jsonb_build_object('key', p_key, 'changed', true, 'account_id', a.id);
end $$;

-- "use another code": a new account with the owner's code (same type and parent as the seed) takes over the key from now on. The old account is retired when it has no journal lines and
-- stays active when it has (its history is never moved). Works also for a key whose proposed code was taken (no account yet). Reason required when the key already pointed at an account.
create or replace function public._w1f_seed_new_code(p_key text, p_code text, p_name_en text default null, p_name_bn text default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; old public.coa_accounts; par public.coa_accounts; nw public.coa_accounts; why text := nullif(btrim(coalesce(p_reason, '')), ''); nm_en text; nm_bn text; retired boolean := false;
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key for update;
  if not found then raise exception 'unknown_key'; end if;
  if p_code is null or p_code !~ '^[0-9A-Za-z.\-]{1,12}$' then raise exception 'bad_code'; end if;
  if exists (select 1 from public.coa_accounts where code = p_code) then raise exception 'code_taken'; end if;
  select c.* into old from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = p_key;
  if old.id is not null and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  nm_en := left(coalesce(nullif(btrim(p_name_en), ''), old.name_en, s.name_en), 120);
  nm_bn := left(coalesce(nullif(btrim(p_name_bn), ''), old.name_bn, s.name_bn), 120);
  select * into par from public.coa_accounts where id = coalesce(old.parent_id, (select id from public.coa_accounts where code = s.parent_code and is_group and type = s.type));
  insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, active, sort)
    values (p_code, nm_bn, nm_en, s.type, case when s.type in ('asset', 'expense') then 'debit' else 'credit' end, par.id, false, false, true, 600 + s.ord) returning * into nw;
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values (p_key, nw.id, s.name_en, s.purpose, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  if old.id is not null and not old.is_system and not exists (select 1 from public.journal_lines l where l.account_id = old.id)
     and not exists (select 1 from public.money_accounts x where x.coa_account_id = old.id) then
    update public.coa_accounts set active = false where id = old.id; retired := true;
  end if;
  update public.w1f_seed_state set status = 'owner_mapping_kept', account_id = nw.id, note = 'owner chose code ' || p_code, seeded_at = now() where key = p_key;
  perform public._w1f_audit('w1f_seed_new_code', 'coa_accounts', nw.id::text, jsonb_build_object('key', p_key, 'old_account', old.id, 'old_code', old.code, 'new_code', p_code, 'old_retired', retired, 'reason', why));
  if old.id is not null then perform public._w1f_exception('ACCOUNTS', null, null, 'chart_code_replaced', null, 'Key ' || p_key || ' moved from ' || old.code || ' to ' || p_code || ' (' || why || ')'); end if;
  return jsonb_build_object('key', p_key, 'account_id', nw.id, 'code', p_code, 'old_retired', retired);
end $$;

-- point a seeded key at an account the owner chooses (used when the proposed code was taken, or to change where a key books). Future postings only: the journal is never rewritten.
create or replace function public._w1f_seed_map(p_key text, p_account_code text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.w1f_seed_state; a public.coa_accounts; m public.acct_mappings; why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public._w1f_chart_ok() then raise exception 'not allowed'; end if;
  select * into s from public.w1f_seed_state where key = p_key;
  if not found then raise exception 'unknown_key'; end if;
  select * into a from public.coa_accounts where code = p_account_code;
  if not found or a.is_group then raise exception 'bad_account'; end if;
  if a.type <> s.type then raise exception 'wrong_account_type'; end if;
  if not a.active and not s.placeholder then raise exception 'bad_account'; end if;
  select * into m from public.acct_mappings where key = p_key;
  if found and m.account_id = a.id then return jsonb_build_object('key', p_key, 'changed', false); end if;
  if found and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  if s.key like 'exp\_%' and public._w1f_head_unposted(substring(s.key from 5), null) > 0 and (why is null or length(why) < 3) then raise exception 'older_documents_unposted'; end if;
  insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values (p_key, a.id, s.name_en, s.purpose, auth.uid())
    on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  update public.w1f_seed_state set status = case when status in ('created', 'mapped_existing') then status else 'owner_mapping_kept' end, account_id = a.id, note = 'mapped by the owner', seeded_at = now() where key = p_key;
  perform public._w1f_audit('w1f_seed_map', 'acct_mappings', p_key, jsonb_build_object('from', m.account_id, 'to', a.id, 'code', a.code, 'reason', why));
  if why is not null then perform public._w1f_exception('ACCOUNTS', null, null, 'chart_mapping_changed', null, 'Mapping ' || p_key || ' set to ' || a.code || ' (' || why || ')'); end if;
  return jsonb_build_object('key', p_key, 'changed', true, 'account_id', a.id);
end $$;

-- ---------- expense heads ----------
create or replace function public._w1f_expense_heads() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'label_en', o.label_en, 'label_bn', o.label_bn, 'active', o.active, 'seeded', coalesce((o.extra ->> 'w1f_seed')::boolean, false),
      'effective_from', o.extra ->> 'effective_from', 'key', 'exp_' || o.value_code, 'mapped', m.account_id is not null, 'account_code', c.code, 'account_name', c.name_en,
      'unposted', public._w1f_head_unposted(o.value_code, null)) order by o.sort, o.value_code)
    from public.option_lists o left join public.acct_mappings m on m.key = 'exp_' || o.value_code left join public.coa_accounts c on c.id = m.account_id where o.list_code = 'expense_heads'), '[]'::jsonb);
end $$;

-- turn a head on / off or edit it (owner only). On: the option row is active and the key exp_<code> books to the chosen expense account. An unposted older document blocks it unless a reason is given.
create or replace function public._w1f_expense_head_set(p_code text, p_label_en text default null, p_label_bn text default null, p_account_code text default null, p_active boolean default true,
  p_effective_from date default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists; a public.coa_accounts; m public.acct_mappings; why text := nullif(btrim(coalesce(p_reason, '')), ''); eff date := coalesce(p_effective_from, public._acct_today()); n bigint; nm_changed boolean := false;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_head'; end if;
  select * into o from public.option_lists where list_code = 'expense_heads' and value_code = p_code for update;
  if not found and (p_label_en is null or length(btrim(p_label_en)) < 1) then raise exception 'name_required'; end if;
  if p_account_code is not null then
    select * into a from public.coa_accounts where code = p_account_code;
    if not found or a.is_group or a.type <> 'expense' or not a.active then raise exception 'bad_account'; end if;
  end if;
  select * into m from public.acct_mappings where key = 'exp_' || p_code;
  if coalesce(p_active, true) then
    if not found and a.id is null then raise exception 'account_required'; end if;
    if a.id is not null and (not found or m.account_id <> a.id) then
      n := public._w1f_head_unposted(p_code, eff);
      if n > 0 and (why is null or length(why) < 3) then raise exception 'older_documents_unposted' using detail = n::text || ' unposted document(s) dated before ' || eff::text; end if;
      insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('exp_' || p_code, a.id, coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), p_code), 'Expense head: ' || p_code, auth.uid())
        on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
      if n > 0 then perform public._w1f_exception('10-2', null, eff, 'expense_head_history', n, 'Head ' || p_code || ' mapped with ' || n::text || ' older unposted document(s): ' || why); end if;
    end if;
  elsif (why is null or length(why) < 3) then raise exception 'reason_required';
  end if;
  if o.list_code is null then
    insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active, extra)
      values ('expense_heads', p_code, coalesce(nullif(btrim(p_label_bn), ''), btrim(p_label_en)), btrim(p_label_en), btrim(p_label_en),
              coalesce((select max(sort) from public.option_lists where list_code = 'expense_heads'), 0) + 10, coalesce(p_active, true), jsonb_build_object('effective_from', eff::text));
  else
    update public.option_lists set label_en = coalesce(nullif(btrim(p_label_en), ''), label_en), label_mix = coalesce(nullif(btrim(p_label_en), ''), label_mix), label_bn = coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), label_bn),
      active = coalesce(p_active, active), retired_reason = case when coalesce(p_active, true) then null else left(why, 300) end,
      extra = case when coalesce(p_active, true) then extra || jsonb_build_object('effective_from', eff::text) else extra end
     where list_code = 'expense_heads' and value_code = p_code;
  end if;
  perform public._w1f_audit('w1f_expense_head_set', 'option_lists', 'expense_heads:' || p_code,
    jsonb_build_object('active', coalesce(p_active, true), 'account', a.code, 'effective_from', eff, 'unposted_older', n, 'reason', why));
  return jsonb_build_object('code', p_code, 'active', coalesce(p_active, true), 'account_code', a.code);
end $$;

-- ---------- other income heads ----------
create or replace function public._w1f_other_income_heads() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', o.value_code, 'label_en', o.label_en, 'active', o.active, 'key', 'oi_' || o.value_code, 'own_account', m.account_id is not null,
      'account_code', coalesce(c.code, c0.code), 'account_name', coalesce(c.name_en, c0.name_en)) order by o.sort, o.value_code)
    from public.option_lists o left join public.acct_mappings m on m.key = 'oi_' || o.value_code left join public.coa_accounts c on c.id = m.account_id
    left join public.acct_mappings m0 on m0.key = 'other_income' left join public.coa_accounts c0 on c0.id = m0.account_id where o.list_code = 'other_income_heads'), '[]'::jsonb);
end $$;

create or replace function public._w1f_other_income_head_set(p_code text, p_label_en text default null, p_label_bn text default null, p_account_code text default null, p_active boolean default true, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.option_lists; a public.coa_accounts; why text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_head'; end if;
  select * into o from public.option_lists where list_code = 'other_income_heads' and value_code = p_code for update;
  if not found and (p_label_en is null or length(btrim(p_label_en)) < 1) then raise exception 'name_required'; end if;
  if p_account_code is not null then
    select * into a from public.coa_accounts where code = p_account_code;
    if not found or a.is_group or a.type <> 'income' or not a.active then raise exception 'bad_account'; end if;
    insert into public.acct_mappings (key, account_id, label_bn, label_en, updated_by) values ('oi_' || p_code, a.id, 'Other income: ' || p_code, 'Other income head: ' || p_code, auth.uid())
      on conflict (key) do update set account_id = excluded.account_id, updated_by = auth.uid(), updated_at = now();
  end if;
  if not coalesce(p_active, true) and (why is null or length(why) < 3) then raise exception 'reason_required'; end if;
  if o.list_code is null then
    insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort, active)
      values ('other_income_heads', p_code, coalesce(nullif(btrim(p_label_bn), ''), btrim(p_label_en)), btrim(p_label_en), btrim(p_label_en),
              coalesce((select max(sort) from public.option_lists where list_code = 'other_income_heads' and value_code <> 'other'), 0) + 10, coalesce(p_active, true));
  else
    update public.option_lists set label_en = coalesce(nullif(btrim(p_label_en), ''), label_en), label_mix = coalesce(nullif(btrim(p_label_en), ''), label_mix), label_bn = coalesce(nullif(btrim(p_label_bn), ''), nullif(btrim(p_label_en), ''), label_bn),
      active = coalesce(p_active, active), retired_reason = case when coalesce(p_active, true) then null else left(why, 300) end
     where list_code = 'other_income_heads' and value_code = p_code;
  end if;
  perform public._w1f_audit('w1f_other_income_head_set', 'option_lists', 'other_income_heads:' || p_code, jsonb_build_object('active', coalesce(p_active, true), 'account', a.code, 'reason', why));
  return jsonb_build_object('code', p_code, 'active', coalesce(p_active, true), 'account_code', a.code);
end $$;

-- ---------- money source for an incoming payment (shared by other income here and by the customer receipts of phase97) ----------
-- Same rules as the phase87 payment source trigger (default account of the event, owner fixed source, require source, place, one-off owner exceptions), without needing the shared _m_event patch.
-- Returns the account to use (null = none, behave as before) and the payment mode that follows the account.
create or replace function public._w1f_pick_source(p_event text, p_acc bigint, p_loc int, p_mode text, p_amt numeric, p_client uuid, p_date date, p_ref text, out o_acc bigint, out o_mode text)
language plpgsql security definer set search_path = public as $$
declare st public.money_event_settings; a public.money_accounts; usr boolean := auth.uid() is not null; dflt boolean := false;
begin
  o_acc := null; o_mode := p_mode;
  select * into st from public.money_event_settings where event_type = p_event;
  if not found then raise exception 'unknown_event'; end if;
  o_acc := p_acc;
  if o_acc is null and st.default_account_id is not null then
    select * into a from public.money_accounts where id = st.default_account_id and active;
    if found and (p_mode is null or p_mode = public._m_mode_of_kind(a.kind) or (a.kind = 'bank' and p_mode = 'card')) and (a.location_id is null or p_loc is null or a.location_id = p_loc) then
      o_acc := a.id; dflt := true;
    end if;
  end if;
  if o_acc is null then
    if st.require_source and usr and not public._m_grant_take('require_source', p_event, p_client, null, p_amt, p_date, p_ref) then raise exception 'money_source_required'; end if;
    return;
  end if;
  select * into a from public.money_accounts where id = o_acc;
  if not found then raise exception 'unknown_money_account'; end if;
  if not a.active then raise exception 'money_account_inactive'; end if;
  if usr and not dflt and st.default_account_id is not null and o_acc <> st.default_account_id and not st.allow_override
     and not public._m_grant_take('override', p_event, p_client, o_acc, p_amt, p_date, p_ref) then raise exception 'money_source_fixed'; end if;
  if usr and a.location_id is not null and p_loc is not null and a.location_id <> p_loc and not public._m_grant_take('override', p_event, p_client, o_acc, p_amt, p_date, p_ref) then
    raise exception 'money_account_place';
  end if;
  o_mode := public._m_mode_of_kind(a.kind);
end $$;

insert into public.money_event_settings (event_type, label_en, dir, sort) values ('other_income', 'Other income received (not a sale)', 'in', 150) on conflict (event_type) do nothing;

-- ---------- other income: table, entry, void, list ----------
create table if not exists public.other_income (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  income_date date not null,
  head text not null,                                     -- value_code of the list other_income_heads (the id, never the label)
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  mode text not null check (mode in ('cash', 'mobile', 'bank')),
  money_account_id bigint references public.money_accounts(id),
  received_from text check (received_from is null or length(received_from) <= 120),
  ref text check (ref is null or length(ref) <= 80),
  note text check (note is null or length(note) <= 300),
  photo text check (photo is null or (length(photo) <= 300 and photo not like '%..%')),
  status text not null default 'done' check (status in ('done', 'void')),
  void_by uuid, void_at timestamptz, void_note text,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists other_income_d on public.other_income (income_date);
alter table public.other_income enable row level security;
revoke all on public.other_income from public, anon, authenticated;
drop trigger if exists other_income_nodel on public.other_income;
create trigger other_income_nodel before delete on public.other_income for each row execute function public.no_hard_delete();
drop trigger if exists audit_other_income on public.other_income;
create trigger audit_other_income after insert or update on public.other_income for each row execute function public.log_change('id');
drop trigger if exists other_income_money_bu on public.other_income;
create or replace function public._w1f_oi_bu() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.money_account_id is distinct from old.money_account_id or new.amount is distinct from old.amount or new.head is distinct from old.head or new.income_date is distinct from old.income_date
     or new.mode is distinct from old.mode or new.location_id is distinct from old.location_id then raise exception 'other_income_fixed'; end if;
  return new;
end $$;
create trigger other_income_money_bu before update on public.other_income for each row execute function public._w1f_oi_bu();

create or replace function public._w1f_other_income_add(p_loc int, p_date date, p_head text, p_amount numeric, p_mode text, p_money_account bigint default null, p_received_from text default null,
  p_ref text default null, p_note text default null, p_photo text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); r public.other_income; sid text; amt numeric := round(p_amount, 2);
  src record; frm text := public.rule_txt('other_income_from'); md text;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public._acct_manage() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if not public.rule_on('other_income_on') then raise exception 'other_income_off'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_head is null or not exists (select 1 from public.option_lists where list_code = 'other_income_heads' and value_code = p_head and active) then raise exception 'bad_head'; end if;
  if amt is null or not (amt between 0.01 and 1000000000) then raise exception 'bad_amount'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'bank') then raise exception 'bad_mode'; end if;
  if d < date '2000-01-01' or d > today + 1 then raise exception 'bad_date'; end if;
  if frm is not null and frm ~ '^\d{4}-\d{2}-\d{2}$' and d < frm::date then raise exception 'before_start_date' using detail = frm; end if;
  if p_photo is not null and (length(p_photo) > 300 or p_photo like '%..%') then raise exception 'bad_photo'; end if;
  perform public.lock_check(d);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.other_income where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  select * into src from public._w1f_pick_source('other_income', p_money_account, p_loc, p_mode, amt, p_client, d, 'other_income');
  md := coalesce(src.o_mode, p_mode);
  if p_dry then return jsonb_build_object('dry', true, 'amount', amt, 'mode', md, 'money_account_id', src.o_acc, 'date', d, 'head', p_head); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.other_income (client_id, location_id, income_date, head, amount, mode, money_account_id, received_from, ref, note, photo, created_by, created_staff)
    values (p_client, p_loc, d, p_head, amt, md, src.o_acc, left(nullif(btrim(p_received_from), ''), 120), left(nullif(btrim(p_ref), ''), 80), left(nullif(btrim(p_note), ''), 300), nullif(btrim(p_photo), ''), auth.uid(), sid)
    returning * into r;
  return jsonb_build_object('id', r.id, 'amount', r.amount, 'mode', r.mode, 'money_account_id', r.money_account_id);
end $$;

create or replace function public._w1f_other_income_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.other_income;
begin
  select * into r from public.other_income where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or public._acct_manage() or (r.created_by = auth.uid() and r.income_date = public._acct_today() and public.can_loc(r.location_id))) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'noop', true); end if;
  perform public.lock_check(r.income_date);
  update public.other_income set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

create or replace function public._w1f_other_income_list(p_loc int default null, p_from date default null, p_to date default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public._acct_view() or public._acct_manage() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return jsonb_build_object('on', public.rule_on('other_income_on'), 'from', public.rule_txt('other_income_from'), 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.income_date desc, z.created_at desc) from (
      select o.id, o.location_id, o.income_date, o.head, h.label_en as head_label, o.amount, o.mode, o.money_account_id, a.name_en as account_name, o.received_from, o.ref, o.note, o.photo, o.status, o.void_note, o.created_staff, o.created_at
        from public.other_income o left join public.option_lists h on h.list_code = 'other_income_heads' and h.value_code = o.head left join public.money_accounts a on a.id = o.money_account_id
       where (p_loc is null or o.location_id = p_loc) and o.income_date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2100-01-01') and (public.is_owner() or public._acct_view() or public.can_loc(o.location_id))
       order by o.income_date desc, o.created_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb));
end $$;

-- ---------- journal source and day book rows (HOOKED in by the integrator, see the note) ----------
create or replace function public._w1f_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  -- other income: Dr the cash / bank / wallet account the money went to, Cr the head's own account (key oi_<head>) or Other income
  return query
  select 'other_income'::text, o.id::text, o.income_date, o.location_id, ('Other income: ' || o.head)::text, null::text, o.status = 'done',
    coalesce((o.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when o.status = 'done' then jsonb_build_array(
      jsonb_build_object('a', public._m_key(o.money_account_id, public._acct_paykey(o.mode)), 'd', o.amount),
      jsonb_build_object('a', case when exists (select 1 from public.acct_mappings m where m.key = 'oi_' || o.head) then 'oi_' || o.head else 'other_income' end, 'c', o.amount)) end
  from public.other_income o
  where o.income_date >= p_start and public._acct_need('other_income', o.id::text, o.status = 'done');
end $$;

create or replace function public._w1f_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select o.location_id, o.income_date, 'in'::text, o.mode, 'other_income'::text, o.amount, o.ref,
         nullif(btrim(concat_ws(' · ', coalesce(h.label_en, o.head), o.received_from, a.name_en, o.note)), ''), o.created_staff, o.created_at, 'other_income'::text, o.id::text, false, false
    from public.other_income o left join public.option_lists h on h.list_code = 'other_income_heads' and h.value_code = o.head left join public.money_accounts a on a.id = o.money_account_id
   where o.status = 'done' and o.location_id = any (p_locs) and o.income_date between p_from and p_to $$;

-- ---------- mapping coverage ----------
create or replace function public._w1f_mapping_coverage() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb := '[]'; bad int := 0; r record; core text[] := array['sales', 'sales_discount', 'sales_returns', 'receivable', 'payable', 'pay_cash', 'pay_bank', 'pay_mobile', 'pay_card', 'cogs',
    'inv_finished', 'inv_raw', 'inv_pack', 'owner_capital', 'owner_drawings', 'exp_other', 'other_income'];
begin
  if not public._w1f_view_ok() then raise exception 'not allowed'; end if;
  for r in select k as key, 'core' as kind from unnest(core) k loop
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = r.key and c.active) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', r.kind, 'key', r.key, 'problem', 'not mapped to an active account'); end if;
  end loop;
  for r in select s.key, s.placeholder from public.w1f_seed_state s loop
    if r.placeholder then continue; end if;
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = r.key and c.active) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'seed', 'key', r.key, 'problem', 'not mapped to an active account'); end if;
  end loop;
  for r in select o.value_code from public.option_lists o where o.list_code = 'expense_heads' and o.active loop
    if not exists (select 1 from public.acct_mappings m join public.coa_accounts c on c.id = m.account_id where m.key = 'exp_' || r.value_code and c.active) then
      bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'expense_head', 'key', 'exp_' || r.value_code, 'problem', 'active head with no account: its money is booked to Other expenses');
    end if;
  end loop;
  for r in select a.id from public.money_accounts a where a.active loop
    if not exists (select 1 from public.acct_mappings m where m.key = 'm_acct_' || r.id::text) then bad := bad + 1; rows_ := rows_ || jsonb_build_object('kind', 'money_account', 'key', 'm_acct_' || r.id::text, 'problem', 'money account has no mapping'); end if;
  end loop;
  return jsonb_build_object('ran', true, 'ok', bad = 0, 'unmapped', bad, 'rows', rows_);
end $$;

-- ---------- privileges ----------
do $pv$ declare f record; pub text[] := array['_w1f_seed_report', '_w1f_seed_edit', '_w1f_seed_new_code', '_w1f_seed_map', '_w1f_expense_heads', '_w1f_expense_head_set', '_w1f_other_income_heads', '_w1f_other_income_head_set',
  '_w1f_other_income_add', '_w1f_other_income_void', '_w1f_other_income_list', '_w1f_mapping_coverage'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_w1f\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (pub) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
  revoke all on public.w1f_seed_state from public, anon, authenticated;
  alter table public.w1f_seed_state enable row level security;
  drop trigger if exists w1f_seed_state_nodel on public.w1f_seed_state;
  create trigger w1f_seed_state_nodel before delete on public.w1f_seed_state for each row execute function public.no_hard_delete();
end $pv$;

