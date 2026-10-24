-- ============================================================================
-- FRESH part 15 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase316 phase317 phase318 phase319 phase323 phase324 phase325 phase326 phase327 phase328 phase329 phase400 phase401 phase402 phase403 phase404 phase405 phase406 phase407 phase408
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase316.sql
-- ============================================================
-- BOS tool - Phase 316 (CRM package F, label 116): LOYALTY EXTRAS part 1 - shared helpers, points expiry, burn rules, manual adjustment alert.
-- Needs phase43 (customers, tiers, points ledger) and phase40 (books, only used by phase318). Paste after phase98/99. Paste twice is safe.
--
-- OWNER RULES KEPT (every item below is a SETTING, default = today's behaviour, nothing starts by itself):
--   * Nothing here writes a journal entry, a sale, a sale payment or a stock row. No existing function or file is edited or re-created.
--   * Points expiry: the month count AND the effective-from date are blank = points never expire (today). Nothing expires on its own: the owner
--     runs "Preview" (writes nothing) and then "Apply" (writes 'expire' rows once). Points earned before the effective-from date are treated as
--     earned ON that date, so switching expiry on never wipes old points the same day.
--   * Burn rules (cap as a percent of the bill, cap in points, step): all blank = the existing customer_points_redeem behaves as before.
--     The new wrapper crmf_points_redeem applies the rules and then calls the existing function; a rule can be passed with a reason
--     (owner or grant crm_loyalty_manage) which writes an audit line and a yellow Exceptions row.
--   * Manual adjustment: the existing customer_points_adjust already needs a reason. The wrapper crmf_points_adjust adds a yellow Exceptions row
--     when the size is above the alert setting (blank = no alert).
--
-- SETTINGS (rules, module crm; labels in English; the Switchboard / settings hub list them by themselves):
--   crm_points_expiry_months (blank)  crm_points_expiry_from (blank)  crm_points_expiry_warn_days (blank)
--   crm_burn_max_percent (blank)  crm_burn_max_points (blank)  crm_burn_step_points (blank)  crm_points_adjust_alert_over (blank)
-- GRANT: crm_loyalty_manage (apply expiry, rule override, referral decisions). The owner always may. `customer_manage` keeps its meaning (tier, credit limit, gifts, points).
-- EXPIRY RULE (no first-in-first-out tracking). The rule on screen is: points earned on or before the cut date, minus every point spent or expired since (oldest points are
--   assumed spent first, which is the kinder reading), never more than the balance. A second Apply the same day finds nothing.
-- Hooks for the POS (points burn at the till) are in docs/integration/CRM-F.md.
-- ============================================================

do $g$ begin
  if to_regclass('public.customer_points_ledger') is null or to_regprocedure('public._cust_mgr43()') is null or to_regprocedure('public.customer_points_redeem(uuid,int,text,uuid,boolean)') is null then
    raise exception 'phase316 needs phase43 first (customers, tiers, points ledger)';
  end if;
end $g$;

create or replace function public._crmf_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. helpers (closed to the browser) ----------
create or replace function public._crmf_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- who manages loyalty extras: the owner, a holder of customer_manage (existing meaning), or a holder of crm_loyalty_manage
create or replace function public._crmf_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage') or public.has_grant('crm_loyalty_manage'));
$$;
-- who may APPLY / OVERRIDE (stronger): the owner or the crm_loyalty_manage grant. customer_manage alone may preview, not apply.
create or replace function public._crmf_apply_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_loyalty_manage'));
$$;
create or replace function public._crmf_pos() returns boolean language sql stable security definer set search_path = public as $$
  select public._cust_pos43() or public._crmf_mgr();
$$;
create or replace function public._crmf_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;
create or replace function public._crmf_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
  values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_action, p_table, p_id, p_detail) $$;
-- a yellow line in the Exceptions list (same table POS uses) for something done with a reason outside the normal rule
create or replace function public._crmf_exception(p_flag text, p_loc int, p_date date, p_amount numeric, p_text text, p_sale uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare lc int := coalesce(p_loc, (select min(ul.location_id) from public.user_locations ul where ul.user_id = auth.uid()), (select min(id) from public.locations));
begin
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
  values (null, p_sale, 'POS', lc, coalesce(p_date, public._crmf_today()), p_flag, 'yellow', p_amount, jsonb_build_object('bn', left(p_text, 300), 'en', left(p_text, 300)));
end $$;
create or replace function public._crmf_mask(p_mobile text) returns text language sql immutable as $$
  select case when p_mobile is null then null when length(p_mobile) <= 5 then '****' else left(p_mobile, 3) || '****' || right(p_mobile, 2) end $$;
-- a stable uuid made from text, used as the client id of rows this package writes (so a rerun can never write the same row twice)
create or replace function public._crmf_uuid(p_text text) returns uuid language sql immutable as $$ select md5(p_text)::uuid $$;
create or replace function public._crmf_reason(p_text text) returns text language plpgsql immutable as $$
declare v text := left(btrim(coalesce(p_text, '')), 300);
begin if length(v) < 3 then raise exception 'reason_required'; end if; return v; end $$;

-- ---------- 2. the points ledger learns two more reasons (additive; the table stays append-only) ----------
do $c$
declare con text; def text; vals text[]; want text[] := array['sale', 'redeem', 'adjust', 'expire', 'referral', 'bonus'];
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.customer_points_ledger'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%reason%';
  if con is null then raise exception 'phase316: the reason check of customer_points_ledger was not found'; end if;
  select array_agg(distinct m[1]) into vals from regexp_matches(def, '''([a-z_]+)''', 'g') m;
  if vals is null or not (vals @> array['sale', 'redeem', 'adjust', 'expire']) then raise exception 'phase316: the reason check has an unknown shape: %', left(def, 150); end if;
  if vals @> want then return; end if;
  want := (select array_agg(distinct x order by x) from unnest(vals || want) x);
  execute format('alter table public.customer_points_ledger drop constraint %I', con);
  execute format('alter table public.customer_points_ledger add constraint %I check (reason = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
end $c$;

-- ---------- 3. grant ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_loyalty_manage', 'master', 72, 'Apply points expiry, referral decisions and loyalty rule overrides', 'Apply points expiry, referral decisions and loyalty rule overrides',
       'Apply points expiry, referral decisions and loyalty rule overrides', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_loyalty_manage');

-- ---------- 4. settings (all blank / OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_points_expiry_months', 'number', null::jsonb, 'months', 1::numeric, 120::numeric, 'Points expire after this many months',
   'Blank = points never expire (today). When set, points earned more than this many months ago (and not yet spent) can be expired by the owner after a preview. Needs the effective-from date as well.', 9610),
 ('crm_points_expiry_from', 'text', null, 'YYYY-MM-DD', null, null, 'Points expiry counts from this date',
   'Blank = expiry cannot be applied. Points earned before this date are treated as earned on this date, so old points are never wiped on the day expiry is switched on.', 9611),
 ('crm_points_expiry_warn_days', 'number', null, 'days', 1, 365, 'Warn customers this many days before points expire',
   'Blank = no warning list. The list shows who would lose points in this many days. Sending a message belongs to the campaign screens.', 9612),
 ('crm_burn_max_percent', 'number', null, '%', 1, 100, 'Points can pay at most this percent of a bill',
   'Blank = no limit (today). Used by the points-at-the-till check; the existing redeem function itself is unchanged.', 9613),
 ('crm_burn_max_points', 'number', null, 'pts', 1, 10000000, 'Most points that can be used on one bill',
   'Blank = no limit (today).', 9614),
 ('crm_burn_step_points', 'number', null, 'pts', 1, 100000, 'Points must be used in steps of',
   'Blank = any number of points (today). Example: 50 means 50, 100, 150 and so on.', 9615),
 ('crm_points_adjust_alert_over', 'number', null, 'pts', 1, 10000000, 'Tell the owner when a manual points change is larger than',
   'Blank = no alert. A change above this size still needs a reason and then also shows in the Exceptions list.', 9616)
 ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- text settings are checked when they are written, so a bad date or account can never sit in a setting waiting to fail later;
-- the voucher liability switch also needs its date, both accounts and accounting before it can go ON
create or replace function public._crmf_rules_guard() returns trigger language plpgsql set search_path = public as $$
declare v text; d date; a public.coa_accounts; was boolean; now_ boolean;
begin
  if new.key in ('crm_points_expiry_from', 'crm_voucher_liability_from') then
    v := nullif(btrim(coalesce(new.value, new.default_value) #>> '{}'), '');
    if v is not null then
      if v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
      begin d := v::date; exception when others then raise exception 'bad_value'; end;
      if d < date '2000-01-01' or d > date '2100-01-01' then raise exception 'bad_value'; end if;
    end if;
  end if;
  if new.key in ('crm_voucher_liability_account', 'crm_voucher_expense_account') then
    v := nullif(btrim(coalesce(new.value, new.default_value) #>> '{}'), '');
    if v is not null then
      select * into a from public.coa_accounts where code = v;
      if not found or a.is_group or not a.active then raise exception 'bad_account'; end if;
      if new.key = 'crm_voucher_liability_account' and a.type <> 'liability' then raise exception 'bad_account_type'; end if;
      if new.key = 'crm_voucher_expense_account' and a.type <> 'expense' then raise exception 'bad_account_type'; end if;
    end if;
  end if;
  if new.key = 'crm_voucher_liability_on' then
    now_ := coalesce((coalesce(new.value, new.default_value) #>> '{}')::boolean, false);
    was := case when tg_op = 'UPDATE' then coalesce((coalesce(old.value, old.default_value) #>> '{}')::boolean, false) else false end;
    if now_ and not was then
      v := public.rule_txt('crm_voucher_liability_from');
      if v is null then raise exception 'liability_from_needed'; end if;
      if v::date < (now() at time zone 'Asia/Dhaka')::date then raise exception 'liability_from_in_the_past'; end if;
      if public.rule_txt('crm_voucher_liability_account') is null or public.rule_txt('crm_voucher_expense_account') is null then raise exception 'liability_accounts_needed'; end if;
      if not public.rule_on('accounting_on') or public._acct_start() is null then raise exception 'accounting_not_on'; end if;
    end if;
  end if;
  return new;
end $$;

revoke all on function public._crmf_rules_guard() from public, anon, authenticated;
drop trigger if exists crmf_rules_guard on public.rules;
create trigger crmf_rules_guard before insert or update on public.rules for each row when (new.key like 'crm\_%') execute function public._crmf_rules_guard();

-- ---------- 5. expiry runs (append-only records) ----------
create table if not exists public.crmf_expiry_runs (
  id bigint generated by default as identity primary key,
  as_of date not null,
  cut_date date not null,
  months int not null,
  from_date date not null,
  client_id uuid unique,
  note text check (note is null or length(note) <= 300),
  by_user uuid, by_staff text,
  at timestamptz not null default now()
);
create table if not exists public.crmf_expiry_lines (
  run_id bigint not null references public.crmf_expiry_runs(id),
  customer_id uuid not null references public.customers(id),
  points int not null check (points > 0),
  ledger_id bigint references public.customer_points_ledger(id),
  primary key (run_id, customer_id)
);
drop trigger if exists crmf_expiry_runs_ro on public.crmf_expiry_runs;
create trigger crmf_expiry_runs_ro before update or delete on public.crmf_expiry_runs for each row execute function public._append_only43();
drop trigger if exists crmf_expiry_runs_ro_t on public.crmf_expiry_runs;
create trigger crmf_expiry_runs_ro_t before truncate on public.crmf_expiry_runs for each statement execute function public._append_only43();
drop trigger if exists crmf_expiry_lines_ro on public.crmf_expiry_lines;
create trigger crmf_expiry_lines_ro before update or delete on public.crmf_expiry_lines for each row execute function public._append_only43();
drop trigger if exists crmf_expiry_lines_ro_t on public.crmf_expiry_lines;
create trigger crmf_expiry_lines_ro_t before truncate on public.crmf_expiry_lines for each statement execute function public._append_only43();
alter table public.crmf_expiry_runs enable row level security;
alter table public.crmf_expiry_lines enable row level security;
drop policy if exists crmf_expiry_runs_read on public.crmf_expiry_runs;
create policy crmf_expiry_runs_read on public.crmf_expiry_runs for select to authenticated using (public._crmf_mgr());
drop policy if exists crmf_expiry_lines_read on public.crmf_expiry_lines;
create policy crmf_expiry_lines_read on public.crmf_expiry_lines for select to authenticated using (public._crmf_mgr());
revoke all on public.crmf_expiry_runs, public.crmf_expiry_lines from public, anon, authenticated;
grant select on public.crmf_expiry_runs, public.crmf_expiry_lines to authenticated;

-- ---------- 6. expiry: the one rule, in one place ----------
-- per customer: balance, earned (credits dated on or before the cut, where an earlier date counts as the effective-from date), used (every debit ever), expirable
create or replace function public._crmf_expiry_rows(p_cut date, p_from date, p_customer uuid default null)
returns table (customer_id uuid, balance int, earned int, used int, expirable int)
language sql stable security definer set search_path = public as $$
  select z.customer_id, z.bal, z.earned, z.used, least(z.bal, greatest(0, z.earned - z.used))
  from (select l.customer_id,
               sum(l.delta)::int as bal,
               coalesce(sum(l.delta) filter (where l.delta > 0 and greatest((l.at at time zone 'Asia/Dhaka')::date, p_from) <= p_cut), 0)::int as earned,
               (-coalesce(sum(l.delta) filter (where l.delta < 0), 0))::int as used
          from public.customer_points_ledger l
         where p_customer is null or l.customer_id = p_customer
         group by l.customer_id) z
  where z.bal > 0 and least(z.bal, greatest(0, z.earned - z.used)) > 0;
$$;

create or replace function public._crmf_expiry_cfg(p_as_of date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m numeric := public.rule_num('crm_points_expiry_months'); f text := public.rule_txt('crm_points_expiry_from'); a date := coalesce(p_as_of, public._crmf_today());
begin
  if m is null then return jsonb_build_object('off', true, 'reason', 'months_blank'); end if;
  if f is null then return jsonb_build_object('off', true, 'reason', 'from_blank'); end if;
  return jsonb_build_object('off', false, 'months', m::int, 'from', f::date, 'as_of', a, 'cut', (a - make_interval(months => m::int))::date);
end $$;

create or replace function public.crmf_points_expiry_preview(p_as_of date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; pv numeric := coalesce(public.rule_num('point_value_taka'), 0); n int; pts bigint; smp jsonb;
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if p_as_of is not null and (p_as_of > public._crmf_today() + 366 or p_as_of < date '2000-01-01') then raise exception 'bad_date'; end if;
  cfg := public._crmf_expiry_cfg(p_as_of);
  if (cfg->>'off')::boolean then return cfg || jsonb_build_object('customers', 0, 'points', 0, 'sample', '[]'::jsonb); end if;
  select count(*)::int, coalesce(sum(expirable), 0) into n, pts from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date);
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', r.customer_id, 'name', c.name, 'points', r.expirable, 'balance', r.balance) order by r.expirable desc), '[]'::jsonb) into smp
    from (select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date) order by expirable desc limit 100) r join public.customers c on c.id = r.customer_id;
  return cfg || jsonb_build_object('customers', n, 'points', pts, 'value_taka', round(pts * pv, 2), 'sample', smp,
    'rule', 'Points earned on or before the cut date, minus every point spent or expired since, never more than the balance.');
end $$;

-- who would lose points in the next N days (N = the warn setting unless given); the names only, the phone is masked
create or replace function public.crmf_points_expiry_soon(p_days int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; d int := coalesce(p_days, public.rule_num('crm_points_expiry_warn_days')::int); cfg2 jsonb; rows_ jsonb; n int;
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if d is null then return jsonb_build_object('off', true, 'reason', 'warn_days_blank', 'rows', '[]'::jsonb); end if;
  if d < 1 or d > 365 then raise exception 'bad_number'; end if;
  cfg := public._crmf_expiry_cfg(null);
  if (cfg->>'off')::boolean then return cfg || jsonb_build_object('rows', '[]'::jsonb); end if;
  cfg2 := public._crmf_expiry_cfg(public._crmf_today() + d);
  with later as (select * from public._crmf_expiry_rows((cfg2->>'cut')::date, (cfg->>'from')::date)),
       now_ as (select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date)),
       x as (select l.customer_id, l.expirable - coalesce(n.expirable, 0) as soon from later l left join now_ n on n.customer_id = l.customer_id)
  select count(*)::int, coalesce(jsonb_agg(jsonb_build_object('customer_id', x.customer_id, 'name', c.name, 'mobile', public._crmf_mask(c.mobile), 'points', x.soon) order by x.soon desc), '[]'::jsonb)
    into n, rows_ from (select * from x where soon > 0 order by soon desc limit 200) x join public.customers c on c.id = x.customer_id;
  return jsonb_build_object('off', false, 'days', d, 'until', public._crmf_today() + d, 'customers', n, 'rows', rows_);
end $$;

create or replace function public.crmf_points_expiry_apply(p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cfg jsonb; r record; cur record; run_id bigint; led bigint; tot int := 0; cnt int := 0; take int; note_ text := left(nullif(btrim(p_note), ''), 300); more_ boolean;
begin
  if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select id into run_id from public.crmf_expiry_runs where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'run_id', run_id); end if;
  end if;
  cfg := public._crmf_expiry_cfg(null);
  if (cfg->>'off')::boolean then raise exception 'expiry_not_set: %', cfg->>'reason'; end if;
  perform pg_advisory_xact_lock(hashtextextended('crmf_expiry', 0));
  if not exists (select 1 from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date)) then
    return jsonb_build_object('dup', false, 'run_id', null, 'customers', 0, 'points', 0, 'more', false);        -- nothing to expire: no record is written
  end if;
  insert into public.crmf_expiry_runs (as_of, cut_date, months, from_date, client_id, note, by_user, by_staff)
    values ((cfg->>'as_of')::date, (cfg->>'cut')::date, (cfg->>'months')::int, (cfg->>'from')::date, p_client, note_, auth.uid(), public._crmf_staff()) returning id into run_id;
  for r in select * from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date) order by customer_id limit 5000 loop
    perform 1 from public.customers where id = r.customer_id for update;
    select * into cur from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date, r.customer_id);   -- again, under the lock
    if not found then continue; end if;
    take := least(cur.expirable, cur.balance);
    if take <= 0 then continue; end if;
    led := null;
    insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
      values (r.customer_id, -take, 'expire', public._crmf_uuid('crmf_expire:' || run_id || ':' || r.customer_id), 'expiry run ' || run_id || ' (earned on or before ' || (cfg->>'cut') || ')', auth.uid(), public._crmf_staff())
      on conflict do nothing returning id into led;
    if led is null then continue; end if;
    insert into public.crmf_expiry_lines (run_id, customer_id, points, ledger_id) values (run_id, r.customer_id, take, led);
    tot := tot + take; cnt := cnt + 1;
  end loop;
  more_ := exists (select 1 from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date));
  perform public._crmf_audit('crmf_expiry_apply', 'crmf_expiry_runs', run_id::text, jsonb_build_object('customers', cnt, 'points', tot, 'cut', cfg->>'cut', 'months', cfg->'months', 'from', cfg->>'from', 'note', note_));
  return jsonb_build_object('dup', false, 'run_id', run_id, 'customers', cnt, 'points', tot, 'more', more_);
end $$;

create or replace function public.crmf_points_expiry_runs(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select r.id, r.as_of, r.cut_date, r.months, r.from_date, r.note, r.at, r.by_staff, count(l.customer_id)::int as customers, coalesce(sum(l.points), 0)::int as points
      from public.crmf_expiry_runs r left join public.crmf_expiry_lines l on l.run_id = r.id group by r.id order by r.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) z), '[]'::jsonb);
end $$;

-- ---------- 7. burn rules at the till ----------
-- Works out what the settings allow for this customer and bill. Writes nothing. p_bill = the bill total BEFORE points (needed when a percent cap is set).
create or replace function public._crmf_burn_eval(p_customer uuid, p_points int, p_bill numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bal int; pv numeric := coalesce(public.rule_num('point_value_taka'), 0); pct numeric := public.rule_num('crm_burn_max_percent'); mx numeric := public.rule_num('crm_burn_max_points');
        stp numeric := public.rule_num('crm_burn_step_points'); cap numeric; reasons text[] := '{}';
begin
  select coalesce(sum(delta), 0)::int into bal from public.customer_points_ledger where customer_id = p_customer;
  cap := bal;
  if mx is not null then cap := least(cap, mx); end if;
  if pct is not null then
    if p_bill is null then return jsonb_build_object('ok', false, 'reason', 'bill_total_needed', 'balance', bal); end if;
    if pv > 0 then cap := least(cap, floor(p_bill * pct / 100 / pv)); end if;
  end if;
  if stp is not null and stp > 0 then cap := floor(cap / stp) * stp; end if;
  if p_points is not null then
    if mx is not null and p_points > mx then reasons := reasons || 'over_max_points'::text; end if;
    if pct is not null and pv > 0 and p_points * pv > p_bill * pct / 100 then reasons := reasons || 'over_max_percent'::text; end if;
    if stp is not null and stp > 0 and (p_points % stp::int) <> 0 then reasons := reasons || 'not_in_steps'::text; end if;
  end if;
  return jsonb_build_object('ok', coalesce(array_length(reasons, 1), 0) = 0, 'reason', case when array_length(reasons, 1) > 0 then reasons[1] end, 'reasons', to_jsonb(reasons),
    'balance', bal, 'max_points', greatest(cap, 0)::int, 'max_value_taka', round(greatest(cap, 0) * pv, 2));
end $$;

create or replace function public.crmf_burn_check(p_customer uuid, p_points int default null, p_bill numeric default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_pos() then raise exception 'not allowed'; end if;
  if p_points is not null and (p_points <= 0 or p_points > 10000000) then raise exception 'bad_number'; end if;
  if p_bill is not null and (p_bill < 0 or p_bill = 'NaN'::numeric or p_bill > 1000000000000) then raise exception 'bad_number'; end if;
  return public._crmf_burn_eval(p_customer, p_points, p_bill);
end $$;

-- The till calls this instead of customer_points_redeem. All burn settings blank = the same answer the old function gives.
-- p_override: owner or crm_loyalty_manage may go past a burn rule with a reason (audit line + yellow Exceptions row). The balance and the
-- minimum-points rule of the old function are never overridden.
create or replace function public.crmf_points_redeem(p_customer uuid, p_points int, p_bill numeric default null, p_note text default null, p_client uuid default null,
  p_dry boolean default false, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ev jsonb; res jsonb; ov text := nullif(btrim(p_override), '');
begin
  if not (public._cust_mgr43() or (public.is_active() and public.can_do('POS', 'enter')) or public._crmf_apply_ok()) then raise exception 'not allowed'; end if;
  if p_points is null or p_points <= 0 or p_points > 10000000 then raise exception 'bad_number'; end if;
  if p_bill is not null and (p_bill < 0 or p_bill = 'NaN'::numeric or p_bill > 1000000000000) then raise exception 'bad_number'; end if;
  ev := public._crmf_burn_eval(p_customer, p_points, p_bill);
  if not (ev->>'ok')::boolean then
    if ev->>'reason' = 'bill_total_needed' then raise exception 'bill_total_needed'; end if;
    if ov is null then raise exception 'burn_rule: %', ev->>'reason'; end if;
    if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
    ov := public._crmf_reason(ov);
    if not coalesce(p_dry, false) and not (p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client)) then    -- a replay of the same client id writes no second line
      perform public._crmf_audit('crmf_burn_override', 'customer_points_ledger', p_customer::text, jsonb_build_object('points', p_points, 'bill', p_bill, 'rules', ev->'reasons', 'reason', ov));
      perform public._crmf_exception('loyalty_burn_override', null, null, p_points, 'Points used past a burn rule (' || (ev->>'reason') || '): ' || ov);
    end if;
  end if;
  res := public.customer_points_redeem(p_customer, p_points, p_note, p_client, p_dry);
  return res || jsonb_build_object('burn', ev);
end $$;

-- ---------- 8. manual adjustment: the existing function already needs a reason; this adds the owner alert for a large one ----------
create or replace function public.crmf_points_adjust(p_customer uuid, p_delta int, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; lim numeric := public.rule_num('crm_points_adjust_alert_over');
begin
  res := public.customer_points_adjust(p_customer, p_delta, p_note, p_client);              -- permission, reason, balance floor (never below zero) and idempotency stay in the old function
  if lim is not null and abs(p_delta) > lim and not coalesce((res->>'dup')::boolean, false) then
    perform public._crmf_exception('loyalty_adjust_large', null, null, abs(p_delta), 'Manual points change of ' || p_delta || ': ' || left(btrim(p_note), 200));
  end if;
  return res;
end $$;

-- ---------- 9. privileges: signed-in users only, helpers closed ----------
revoke all on function public._crmf_present(), public._crmf_today(), public._crmf_mgr(), public._crmf_apply_ok(), public._crmf_pos(), public._crmf_staff(),
  public._crmf_audit(text, text, text, jsonb), public._crmf_exception(text, int, date, numeric, text, uuid), public._crmf_mask(text), public._crmf_uuid(text), public._crmf_reason(text),
  public._crmf_expiry_rows(date, date, uuid), public._crmf_expiry_cfg(date), public._crmf_burn_eval(uuid, int, numeric) from public, anon, authenticated;
-- the table policies call _crmf_mgr(), so signed-in users must be able to execute it (it only answers true / false)
grant execute on function public._crmf_mgr() to authenticated;
revoke all on function public.crmf_points_expiry_preview(date), public.crmf_points_expiry_soon(int), public.crmf_points_expiry_apply(uuid, text), public.crmf_points_expiry_runs(int),
  public.crmf_burn_check(uuid, int, numeric), public.crmf_points_redeem(uuid, int, numeric, text, uuid, boolean, text), public.crmf_points_adjust(uuid, int, text, uuid) from public, anon;
grant execute on function public.crmf_points_expiry_preview(date), public.crmf_points_expiry_soon(int), public.crmf_points_expiry_apply(uuid, text), public.crmf_points_expiry_runs(int),
  public.crmf_burn_check(uuid, int, numeric), public.crmf_points_redeem(uuid, int, numeric, text, uuid, boolean, text), public.crmf_points_adjust(uuid, int, text, uuid) to authenticated;

-- ---------------------------------------------------------------- phase317.sql
-- ============================================================
-- BOS tool - Phase 317 (CRM package F, label 117): LOYALTY EXTRAS part 2 - REFERRAL codes and rewards.
-- Needs phase316 (and phase43). Paste after phase316. Paste twice is safe.
--
-- WHAT IT DOES: every customer can have a short referral code. When a NEW customer is told "referred by CODE", the link is kept as pending.
-- When that new customer's FIRST completed sale is recorded, the referrer (and optionally the new customer) gets bonus points, once.
-- If that first sale is later voided, the reward is taken back (never below a zero balance).
--
-- OWNER RULES KEPT:
--   * crm_referral_on is OFF: no code is made, no link is saved, no reward is given. The sales trigger below returns at once while OFF.
--   * crm_referral_reward_points is blank: no reward can be given even when the switch is ON (a blank number blocks, nothing is invented).
--   * Points only; no journal entry, no money, no sale change. A sale is never stopped by this package (the trigger turns an error into a warning).
--   * Rewards use the points ledger with reason 'referral'. Loyalty points must be ON (loyalty_points_on); otherwise no reward is written.
--   * Exceptions with a reason: a pending referral can be rejected with a reason (owner or crm_loyalty_manage).
--
-- SETTINGS (rules, module crm): crm_referral_on (OFF)  crm_referral_reward_points (blank)  crm_referral_referred_points (blank)  crm_referral_min_bill (blank)
-- Hooks for the POS ("Referred by" box) are in docs/integration/CRM-F.md: call crmf_referral_apply(customer_id, code, client) after the customer exists.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._crmf_present()') is null then raise exception 'phase317 needs phase316 first'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_referral_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric, 'Referral codes and rewards on',
   'OFF (default) = no referral code is made and no reward is given. ON = a new customer can be linked to the customer who referred them; the reward is given on the new customer''s first completed sale. Loyalty points must also be ON.', 9620),
 ('crm_referral_reward_points', 'number', null, 'pts', 1, 10000000, 'Points the referring customer earns',
   'Blank = no reward can be given, even when referral is ON. Given once, on the new customer''s first completed sale.', 9621),
 ('crm_referral_referred_points', 'number', null, 'pts', 1, 10000000, 'Points the new (referred) customer earns',
   'Blank = the new customer gets nothing extra. Given together with the referrer reward.', 9622),
 ('crm_referral_min_bill', 'number', null, '৳', 0, 1000000000, 'First bill must be at least',
   'Blank = any first bill counts. If the first bill is smaller, the referral is closed without a reward.', 9623)
 ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.crmf_referral_codes (
  customer_id uuid primary key references public.customers(id),
  code text not null unique check (code ~ '^[A-Z0-9]{6,10}$'),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.crmf_referrals (
  id bigint generated by default as identity primary key,
  referrer_id uuid not null references public.customers(id),
  referred_id uuid not null unique references public.customers(id),
  code text not null,
  status text not null default 'pending' check (status in ('pending', 'rewarded', 'rejected', 'reversed')),
  first_sale_id uuid references public.sales(id),
  reward_points int check (reward_points is null or reward_points > 0),
  referred_points int check (referred_points is null or referred_points > 0),
  reason text check (reason is null or length(reason) <= 300),
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz,
  check (referrer_id <> referred_id)
);
create index if not exists crmf_referrals_referrer on public.crmf_referrals (referrer_id);
create index if not exists crmf_referrals_sale on public.crmf_referrals (first_sale_id) where first_sale_id is not null;
drop trigger if exists audit_crmf_referrals on public.crmf_referrals;
create trigger audit_crmf_referrals after insert or update on public.crmf_referrals for each row execute function public.log_change('id');
drop trigger if exists crmf_referrals_no_delete on public.crmf_referrals;
create trigger crmf_referrals_no_delete before delete on public.crmf_referrals for each row execute function public.no_hard_delete();
drop trigger if exists crmf_referral_codes_no_delete on public.crmf_referral_codes;
create trigger crmf_referral_codes_no_delete before delete on public.crmf_referral_codes for each row execute function public.no_hard_delete();
alter table public.crmf_referral_codes enable row level security;
alter table public.crmf_referrals enable row level security;
drop policy if exists crmf_referral_codes_read on public.crmf_referral_codes;
create policy crmf_referral_codes_read on public.crmf_referral_codes for select to authenticated using (public._crmf_pos());
drop policy if exists crmf_referrals_read on public.crmf_referrals;
create policy crmf_referrals_read on public.crmf_referrals for select to authenticated using (public._crmf_mgr());
revoke all on public.crmf_referral_codes, public.crmf_referrals from public, anon, authenticated;
grant select on public.crmf_referral_codes, public.crmf_referrals to authenticated;

-- ---------- functions ----------
create or replace function public._crmf_ref_on() returns void language plpgsql stable security definer set search_path = public as $$
begin if not public.rule_on('crm_referral_on') then raise exception 'referral_off'; end if; end $$;

-- the customer's code (made on first ask). 6 letters / digits without the easy-to-confuse ones.
create or replace function public.crmf_referral_code(p_customer uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text; alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int; tries int := 0; row_ public.crmf_referral_codes;
begin
  if not public._crmf_pos() then raise exception 'not allowed'; end if;
  perform public._crmf_ref_on();
  select * into row_ from public.crmf_referral_codes where customer_id = p_customer;
  if found then return jsonb_build_object('code', row_.code, 'active', row_.active, 'new', false); end if;
  perform 1 from public.customers where id = p_customer and active for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into row_ from public.crmf_referral_codes where customer_id = p_customer;
  if found then return jsonb_build_object('code', row_.code, 'active', row_.active, 'new', false); end if;
  loop
    c := ''; for i in 1 .. 6 loop c := c || substr(alpha, 1 + floor(random() * length(alpha))::int, 1); end loop;
    begin
      insert into public.crmf_referral_codes (customer_id, code, created_by) values (p_customer, c, auth.uid());
      exit;
    exception when unique_violation then
      tries := tries + 1; if tries > 20 then raise exception 'code_busy'; end if;
    end;
  end loop;
  return jsonb_build_object('code', c, 'active', true, 'new', true);
end $$;

-- "referred by CODE" for a customer. Never blocks a sale: the till calls it after the customer exists and shows the answer.
create or replace function public.crmf_referral_apply(p_referred uuid, p_code text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cd public.crmf_referral_codes; ref public.crmf_referrals; k text := upper(btrim(coalesce(p_code, '')));
begin
  if not (public._crmf_mgr() or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  perform public._crmf_ref_on();
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into ref from public.crmf_referrals where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'id', ref.id, 'status', ref.status); end if;
  end if;
  if k !~ '^[A-Z0-9]{6,10}$' then return jsonb_build_object('ok', false, 'reason', 'bad_code'); end if;
  perform 1 from public.customers where id = p_referred and active for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into cd from public.crmf_referral_codes where code = k;
  if not found or not cd.active then return jsonb_build_object('ok', false, 'reason', 'code_not_found'); end if;
  if cd.customer_id = p_referred then return jsonb_build_object('ok', false, 'reason', 'self_referral'); end if;
  select * into ref from public.crmf_referrals where referred_id = p_referred;
  if found then return jsonb_build_object('ok', false, 'reason', 'already_referred', 'status', ref.status); end if;
  if exists (select 1 from public.sales where customer_id = p_referred and status = 'done') then return jsonb_build_object('ok', false, 'reason', 'not_a_new_customer'); end if;
  if not exists (select 1 from public.customers where id = cd.customer_id and active) then return jsonb_build_object('ok', false, 'reason', 'referrer_inactive'); end if;
  insert into public.crmf_referrals (referrer_id, referred_id, code, client_id, created_by, created_staff)
    values (cd.customer_id, p_referred, k, p_client, auth.uid(), public._crmf_staff()) returning * into ref;
  return jsonb_build_object('ok', true, 'dup', false, 'id', ref.id, 'status', ref.status);
end $$;

create or replace function public.crmf_referral_reject(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ref public.crmf_referrals; why text;
begin
  if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
  why := public._crmf_reason(p_reason);
  select * into ref from public.crmf_referrals where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if ref.status <> 'pending' then raise exception 'not_pending'; end if;
  update public.crmf_referrals set status = 'rejected', reason = why, decided_by = auth.uid(), decided_at = now() where id = p_id;
  perform public._crmf_audit('crmf_referral_reject', 'crmf_referrals', p_id::text, jsonb_build_object('reason', why));
  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'rejected');
end $$;

create or replace function public.crmf_referral_list(p_status text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('pending', 'rewarded', 'rejected', 'reversed') then raise exception 'bad_value'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select r.id, r.status, r.code, r.reward_points, r.referred_points, r.reason, r.created_at, r.first_sale_id,
           a.name as referrer_name, b.name as referred_name
      from public.crmf_referrals r join public.customers a on a.id = r.referrer_id join public.customers b on b.id = r.referred_id
     where p_status is null or r.status = p_status order by r.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- ---------- the reward: a trigger on sales, written in the style of the loyalty trigger (an error here is a warning, never a stopped sale) ----------
create or replace function public._crmf_sale_referral() returns trigger language plpgsql security definer set search_path = public as $$
declare ref public.crmf_referrals; rw numeric; rf numeric; mb numeric; ok_ boolean := true; r_led bigint;
begin
  if not public.rule_on('crm_referral_on') or new.customer_id is null or new.status <> 'done' then return new; end if;
  begin
    select * into ref from public.crmf_referrals where referred_id = new.customer_id and status = 'pending' for update;
    if not found then return new; end if;
    if exists (select 1 from public.sales s where s.customer_id = new.customer_id and s.status = 'done' and s.id <> new.id) then
      update public.crmf_referrals set status = 'rejected', reason = 'not the first sale', decided_at = now() where id = ref.id; return new;
    end if;
    rw := public.rule_num('crm_referral_reward_points'); rf := public.rule_num('crm_referral_referred_points'); mb := public.rule_num('crm_referral_min_bill');
    if rw is null or not public.rule_on('loyalty_points_on') then return new; end if;                      -- blank reward or points off: stays pending, nothing is written
    if mb is not null and new.total < mb then
      update public.crmf_referrals set status = 'rejected', reason = 'first bill below the minimum', decided_at = now() where id = ref.id; return new;
    end if;
    insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, client_id, note, by_user, by_staff)
      values (ref.referrer_id, rw::int, 'referral', new.id, public._crmf_uuid('crmf_ref:' || ref.id), 'referral reward, new customer first bill ' || new.receipt, new.created_by, new.created_staff)
      on conflict do nothing returning id into r_led;
    if r_led is null then return new; end if;
    if rf is not null then
      insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, client_id, note, by_user, by_staff)
        values (ref.referred_id, rf::int, 'referral', new.id, public._crmf_uuid('crmf_refd:' || ref.id), 'welcome points (referred by a customer)', new.created_by, new.created_staff)
        on conflict do nothing;
    end if;
    update public.crmf_referrals set status = 'rewarded', first_sale_id = new.id, reward_points = rw::int, referred_points = rf::int, decided_at = now() where id = ref.id;
  exception when others then
    raise warning 'crmf referral reward failed for sale %: %', new.id, sqlerrm;
  end;
  return new;
end $$;
revoke all on function public._crmf_sale_referral() from public, anon, authenticated;
drop trigger if exists sales_referral_crmf on public.sales;
create trigger sales_referral_crmf after insert on public.sales for each row execute function public._crmf_sale_referral();

-- the first sale is voided: the reward is taken back once, never beyond what the customer still has (the history keeps the full story)
create or replace function public._crmf_sale_referral_void() returns trigger language plpgsql security definer set search_path = public as $$
declare ref public.crmf_referrals; bal int; take int; leftover int;
begin
  if new.status <> 'void' or old.status is not distinct from 'void' then return new; end if;
  begin
    select * into ref from public.crmf_referrals where first_sale_id = new.id and status = 'rewarded' for update;
    if not found then return new; end if;
    perform 1 from public.customers where id = ref.referrer_id for update;
    select coalesce(sum(delta), 0)::int into bal from public.customer_points_ledger where customer_id = ref.referrer_id;
    take := least(ref.reward_points, greatest(bal, 0));
    if take > 0 then
      insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user)
        values (ref.referrer_id, -take, 'adjust', public._crmf_uuid('crmf_refrev:' || ref.id), 'referral reward taken back: first sale ' || new.receipt || ' was voided', auth.uid()) on conflict do nothing;
    end if;
    if ref.referred_points is not null then
      perform 1 from public.customers where id = ref.referred_id for update;
      select coalesce(sum(delta), 0)::int into bal from public.customer_points_ledger where customer_id = ref.referred_id;
      take := least(ref.referred_points, greatest(bal, 0));
      if take > 0 then
        insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user)
          values (ref.referred_id, -take, 'adjust', public._crmf_uuid('crmf_refdrev:' || ref.id), 'welcome points taken back: first sale ' || new.receipt || ' was voided', auth.uid()) on conflict do nothing;
      end if;
    end if;
    update public.crmf_referrals set status = 'reversed', reason = 'first sale voided', decided_at = now() where id = ref.id;
  exception when others then
    raise warning 'crmf referral reversal failed for sale %: %', new.id, sqlerrm;
  end;
  return new;
end $$;
revoke all on function public._crmf_sale_referral_void() from public, anon, authenticated;
drop trigger if exists sales_referral_void_crmf on public.sales;
create trigger sales_referral_void_crmf after update of status on public.sales for each row execute function public._crmf_sale_referral_void();

revoke all on function public._crmf_ref_on() from public, anon, authenticated;
revoke all on function public.crmf_referral_code(uuid), public.crmf_referral_apply(uuid, text, uuid), public.crmf_referral_reject(bigint, text), public.crmf_referral_list(text, int) from public, anon;
grant execute on function public.crmf_referral_code(uuid), public.crmf_referral_apply(uuid, text, uuid), public.crmf_referral_reject(bigint, text), public.crmf_referral_list(text, int) to authenticated;

-- ---------------------------------------------------------------- phase318.sql
-- ============================================================
-- BOS tool - Phase 318 (CRM package F, label 118): LOYALTY EXTRAS part 3 - COUPONS AND VOUCHERS.
-- Needs phase316 (and phase43; phase40 only for the optional voucher liability). Paste after phase317. Paste twice is safe.
--
-- WHAT IT DOES: a coupon / voucher is a code worth a percent or an amount off a bill, with a validity window, a minimum bill, a total use limit, a per-customer
-- limit and an optional scope (outlets, items, item categories). It can be for anyone or for one customer. Every use is written to a log.
-- V1 does NOT change record_sale2: the cashier asks crmf_coupon_check for the discount, types it through the normal discount control (normal approval
-- rules apply), then calls crmf_coupon_redeem_after_sale(code, sale). That records the use and raises a YELLOW Exceptions row when the discount on the bill
-- differs from what the coupon gives. Hook text: docs/integration/CRM-F.md.
--
-- OWNER RULES KEPT:
--   * crm_voucher_on is OFF: check and redeem refuse ("vouchers_off"). Coupons can be prepared while it is OFF; nothing starts by itself.
--   * crm_voucher_max_percent / crm_voucher_max_amount are blank: a coupon of that kind cannot be created (a blank number blocks, nothing is invented).
--     Above the maximum only the owner may create it, with a reason (audit line).
--   * Exceptions with a reason: the owner or a holder of crm_coupon_override may accept a coupon that is expired, not started, below the minimum bill, at another
--     outlet or past the per-customer limit, WITH a reason (audit line + yellow Exceptions row). A retired coupon, a coupon that is used up, a personal coupon
--     of another customer and a bill with nothing in the coupon's scope can never be overridden.
--   * Accounting figures never change unless the owner switches VOUCHER LIABILITY on (below). A coupon is a discount record; the discount is already inside the sale total.
--
-- VOUCHER LIABILITY (OFF by default; the ONLY thing in this package that writes to the books):
--   crm_voucher_liability_on (OFF)   crm_voucher_liability_from (blank = cannot be switched on)   crm_voucher_liability_account (a liability account code)   crm_voucher_expense_account (an expense account code)
--   Function crmf_voucher_liability_sync(): for each AMOUNT coupon marked "post liability" (max uses set, issued on or after the effective-from date) the books hold
--   (value x max uses) minus the discount already given, as a provision: Dr the chosen expense account, Cr the chosen liability account; it falls (Dr liability, Cr expense) as
--   the coupon is used, and goes to zero when the coupon expires, is retired, or a sale that used it is voided. Every entry has two lines and Dr = Cr (the one journal
--   writer of phase40 refuses anything else), is dated today (never in a closed period), and the sync is self-healing: it posts only the difference between what the
--   books hold and what should be held. crmf_voucher_liability_wind_down() moves everything back to zero (use it before switching the setting off).
--   Gift cards that are SOLD for cash (package F2) are a different thing and are not here. The accounting treatment is a proposal for the owner and the accountant to confirm.
-- GRANTS: crm_voucher_issue (create / edit coupons), crm_coupon_override (accept a coupon outside its limits with a reason). The owner always may.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._crmf_present()') is null then raise exception 'phase318 needs phase316 first'; end if;
  if to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null then raise exception 'phase318 needs phase40 (the books) first'; end if;
end $g$;

-- ---------- grants and settings ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'master', v.s, v.l, v.l, v.l, 'once', null from (values
  ('crm_voucher_issue', 73, 'Create and edit coupons and vouchers'),
  ('crm_coupon_override', 74, 'Accept a coupon outside its limits, with a reason')) v(c, s, l)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_voucher_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric, 'Coupons and vouchers on',
   'OFF (default) = the till cannot use a coupon. Coupons can still be prepared. ON = a coupon can be checked and recorded against a sale. The discount is still typed through the normal discount control.', 9630),
 ('crm_voucher_max_percent', 'number', null, '%', 1, 100, 'Largest percent a coupon may give',
   'Blank = percent coupons cannot be created. Above this only the owner can create one, with a reason.', 9631),
 ('crm_voucher_max_amount', 'number', null, '৳', 1, 1000000000, 'Largest taka amount a coupon may give',
   'Blank = amount coupons cannot be created. Above this only the owner can create one, with a reason.', 9632),
 ('crm_voucher_liability_on', 'switch', 'false', null, null, null, 'Book coupon liability in the accounts',
   'OFF (default) = coupons never touch the accounts. ON = for amount coupons marked "post liability" the accounts hold the unused value as a provision (see the effective-from date). Needs the date and both accounts below first.', 9633),
 ('crm_voucher_liability_from', 'text', null, 'YYYY-MM-DD', null, null, 'Coupon liability counts from this date',
   'Blank = the liability setting cannot be switched on. Only coupons created on or after this date are booked, so the past never changes. Must not be in the past when you switch it on.', 9634),
 ('crm_voucher_liability_account', 'text', null, 'code', null, null, 'Liability account for unused coupon value (chart code)',
   'Blank = cannot switch on. Type the code of an existing active liability account.', 9635),
 ('crm_voucher_expense_account', 'text', null, 'code', null, null, 'Expense account for the coupon provision (chart code)',
   'Blank = cannot switch on. Type the code of an existing active expense account.', 9636)
 ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- (the settings guard _crmf_rules_guard, with the liability switch-on rules, lives in phase316, so re-pasting an earlier phase can never remove a rule)

-- ---------- tables ----------
create table if not exists public.crmf_coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9-]{2,19}$'),
  name text not null check (length(btrim(name)) between 1 and 80),
  kind text not null check (kind in ('percent', 'amount')),
  value numeric not null check (value > 0 and value <= 1000000000),
  min_bill numeric check (min_bill is null or min_bill >= 0),
  max_discount numeric check (max_discount is null or max_discount > 0),
  valid_from date not null,
  valid_to date not null,
  max_uses int check (max_uses is null or max_uses >= 1),
  per_customer_uses int not null default 1 check (per_customer_uses >= 1),
  customer_id uuid references public.customers(id),
  campaign_ref text check (campaign_ref is null or length(campaign_ref) <= 60),
  note text check (note is null or length(note) <= 300),
  post_liability boolean not null default false,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (valid_to >= valid_from),
  check (kind <> 'percent' or value <= 100),
  check (not post_liability or (kind = 'amount' and max_uses is not null))
);
create table if not exists public.crmf_coupon_scope (
  coupon_id uuid not null references public.crmf_coupons(id),
  kind text not null check (kind in ('location', 'item', 'category')),
  ref text not null check (length(ref) between 1 and 80),
  primary key (coupon_id, kind, ref)
);
create table if not exists public.crmf_coupon_uses (
  id bigint generated by default as identity primary key,
  coupon_id uuid not null references public.crmf_coupons(id),
  sale_id uuid not null unique references public.sales(id),
  customer_id uuid references public.customers(id),
  location_id int,
  bill_total numeric not null,
  discount_expected numeric not null,
  discount_given numeric not null,
  mismatch boolean not null default false,
  override_reason text,
  client_id uuid unique,
  at timestamptz not null default now(),
  by_user uuid, by_staff text
);
create index if not exists crmf_coupon_uses_coupon on public.crmf_coupon_uses (coupon_id, customer_id);
create table if not exists public.crmf_liab_postings (
  id bigint generated by default as identity primary key,
  coupon_id uuid not null references public.crmf_coupons(id),
  delta numeric not null check (delta <> 0),
  entry_id bigint not null references public.journal_entries(id),
  why text not null,
  at timestamptz not null default now(),
  by_user uuid
);
create index if not exists crmf_liab_postings_coupon on public.crmf_liab_postings (coupon_id);
drop trigger if exists crmf_coupon_uses_ro on public.crmf_coupon_uses;
create trigger crmf_coupon_uses_ro before update or delete on public.crmf_coupon_uses for each row execute function public._append_only43();
drop trigger if exists crmf_coupon_uses_ro_t on public.crmf_coupon_uses;
create trigger crmf_coupon_uses_ro_t before truncate on public.crmf_coupon_uses for each statement execute function public._append_only43();
drop trigger if exists crmf_liab_postings_ro on public.crmf_liab_postings;
create trigger crmf_liab_postings_ro before update or delete on public.crmf_liab_postings for each row execute function public._append_only43();
drop trigger if exists crmf_liab_postings_ro_t on public.crmf_liab_postings;
create trigger crmf_liab_postings_ro_t before truncate on public.crmf_liab_postings for each statement execute function public._append_only43();
drop trigger if exists audit_crmf_coupons on public.crmf_coupons;
create trigger audit_crmf_coupons after insert or update on public.crmf_coupons for each row execute function public.log_change('id');
drop trigger if exists crmf_coupons_no_delete on public.crmf_coupons;
create trigger crmf_coupons_no_delete before delete on public.crmf_coupons for each row execute function public.no_hard_delete();
alter table public.crmf_coupons enable row level security;
alter table public.crmf_coupon_scope enable row level security;
alter table public.crmf_coupon_uses enable row level security;
alter table public.crmf_liab_postings enable row level security;
create or replace function public._crmf_voucher_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public._crmf_mgr() or (public.is_active() and public.has_grant('crm_voucher_issue'));
$$;
create or replace function public._crmf_override_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_coupon_override'));
$$;
drop policy if exists crmf_coupons_read on public.crmf_coupons;
create policy crmf_coupons_read on public.crmf_coupons for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_coupon_scope_read on public.crmf_coupon_scope;
create policy crmf_coupon_scope_read on public.crmf_coupon_scope for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_coupon_uses_read on public.crmf_coupon_uses;
create policy crmf_coupon_uses_read on public.crmf_coupon_uses for select to authenticated using (public._crmf_voucher_mgr());
drop policy if exists crmf_liab_postings_read on public.crmf_liab_postings;
create policy crmf_liab_postings_read on public.crmf_liab_postings for select to authenticated using (public._crmf_voucher_mgr() or public._acct_manage());
revoke all on public.crmf_coupons, public.crmf_coupon_scope, public.crmf_coupon_uses, public.crmf_liab_postings from public, anon, authenticated;
grant select on public.crmf_coupons, public.crmf_coupon_scope, public.crmf_coupon_uses, public.crmf_liab_postings to authenticated;

-- ---------- the rule check, in one place (used by the till check, the redemption and the report) ----------
-- Returns {ok, reason, overridden[], discount, eligible}. Business refusals are answers, not errors. p_override = the caller may and did give a reason.
create or replace function public._crmf_coupon_eval(c public.crmf_coupons, p_loc int, p_customer uuid, p_lines jsonb, p_subtotal numeric, p_date date, p_exclude uuid, p_override boolean)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare soft text[] := '{}'; hard text; elig numeric; disc numeric; live int; cl int; sc_loc boolean; sc_item boolean; ln jsonb; amt numeric; iid uuid; icat text; hit boolean;
begin
  if p_subtotal is null or p_subtotal < 0 then raise exception 'bad_number'; end if;
  if not c.active then return jsonb_build_object('ok', false, 'reason', 'retired', 'overridden', '[]'::jsonb); end if;
  if p_date < c.valid_from then soft := soft || 'not_started'::text; end if;
  if p_date > c.valid_to then soft := soft || 'expired'::text; end if;
  if c.customer_id is not null and p_customer is distinct from c.customer_id then hard := 'wrong_customer'; end if;
  if p_customer is null then soft := soft || 'customer_needed'::text; end if;
  select exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind = 'location') into sc_loc;
  if sc_loc and not exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind = 'location' and ref = p_loc::text) then soft := soft || 'wrong_outlet'::text; end if;
  select exists (select 1 from public.crmf_coupon_scope where coupon_id = c.id and kind in ('item', 'category')) into sc_item;
  if sc_item then
    elig := 0;
    for ln in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
      begin
        iid := nullif(ln->>'item_id', '')::uuid;
        amt := coalesce(nullif(ln->>'amount', '')::numeric, nullif(ln->>'qty', '')::numeric * nullif(ln->>'price', '')::numeric, 0);
      exception when others then raise exception 'bad_lines'; end;
      continue when iid is null or amt <= 0;
      select category into icat from public.items where id = iid;
      select exists (select 1 from public.crmf_coupon_scope s where s.coupon_id = c.id and ((s.kind = 'item' and s.ref = iid::text) or (s.kind = 'category' and icat is not null and s.ref = icat))) into hit;
      if hit then elig := elig + amt; end if;
    end loop;
    elig := least(elig, p_subtotal);
    if elig <= 0 and hard is null then hard := 'nothing_in_scope'; end if;
  else
    elig := p_subtotal;
  end if;
  if c.min_bill is not null and p_subtotal < c.min_bill then soft := soft || 'min_bill'::text; end if;
  select count(*)::int into live from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id
    where u.coupon_id = c.id and s.status = 'done' and u.sale_id is distinct from p_exclude;
  if c.max_uses is not null and live >= c.max_uses and hard is null then hard := 'used_up'; end if;
  if p_customer is not null then
    select count(*)::int into cl from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id
      where u.coupon_id = c.id and u.customer_id = p_customer and s.status = 'done' and u.sale_id is distinct from p_exclude;
    if cl >= c.per_customer_uses then soft := soft || 'customer_limit'::text; end if;
  end if;
  disc := case c.kind when 'percent' then round(elig * c.value / 100, 2) else least(c.value, elig) end;
  if c.kind = 'percent' and c.max_discount is not null then disc := least(disc, c.max_discount); end if;
  disc := greatest(least(disc, p_subtotal), 0);
  if hard is not null then return jsonb_build_object('ok', false, 'reason', hard, 'overridden', '[]'::jsonb, 'discount', 0, 'eligible', coalesce(elig, 0)); end if;
  if array_length(soft, 1) > 0 and not p_override then
    return jsonb_build_object('ok', false, 'reason', soft[1], 'reasons', to_jsonb(soft), 'overridable', true, 'overridden', '[]'::jsonb, 'discount', 0, 'eligible', elig);
  end if;
  return jsonb_build_object('ok', true, 'reason', null, 'overridden', to_jsonb(soft), 'discount', disc, 'eligible', elig, 'left_uses', case when c.max_uses is null then null else greatest(c.max_uses - live, 0) end);
end $$;

create or replace function public._crmf_code(p_code text) returns text language sql immutable as $$ select upper(btrim(coalesce(p_code, ''))) $$;

-- ---------- coupon master: create / edit ----------
-- p keys: code (new only), name, kind (percent|amount), value, min_bill, max_discount, valid_from, valid_to, max_uses, per_customer_uses, customer_id, campaign_ref, note,
--         post_liability, active, scope {"locations":[1,2],"items":["<uuid>"],"categories":["<text>"]}. A missing key is not changed; an empty value clears an optional field.
-- After the first use the money terms (kind, value, minimum, cap, customer, scope) are locked: retire the coupon and make a new one.
create or replace function public.crmf_coupon_save(p_id uuid, p jsonb, p_client uuid default null, p_override text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; n public.crmf_coupons; k text; v numeric; mx numeric; ov text := nullif(btrim(p_override), ''); sc jsonb; x jsonb; used int; kind_ text; val_ numeric; over_ boolean := false;
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  perform public._client_lock(p_client);
  if p_id is null then
    if p_client is not null then
      select * into c from public.crmf_coupons where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', c.id, 'code', c.code); end if;
    end if;
    k := public._crmf_code(p->>'code');
    if k !~ '^[A-Z0-9][A-Z0-9-]{2,19}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.crmf_coupons where code = k) then raise exception 'code_exists'; end if;
    kind_ := p->>'kind'; if kind_ is null or kind_ not in ('percent', 'amount') then raise exception 'bad_kind'; end if;
    val_ := public._n43(p, 'value', 0.01, 1000000000); if val_ is null then raise exception 'value_required'; end if;
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    if nullif(btrim(p->>'valid_from'), '') is null or nullif(btrim(p->>'valid_to'), '') is null then raise exception 'validity_required'; end if;
  else
    select * into c from public.crmf_coupons where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    kind_ := coalesce(p->>'kind', c.kind);
    val_ := coalesce(public._n43(p, 'value', 0.01, 1000000000), c.value);
    select count(*)::int into used from public.crmf_coupon_uses where coupon_id = c.id;
    if used > 0 and (kind_ is distinct from c.kind or val_ is distinct from c.value or p ? 'min_bill' or p ? 'max_discount' or p ? 'customer_id' or p ? 'scope' or p ? 'post_liability') then raise exception 'locked_after_use'; end if;
  end if;
  if kind_ = 'percent' then
    if val_ > 100 then raise exception 'bad_number'; end if;
    mx := public.rule_num('crm_voucher_max_percent'); if mx is null then raise exception 'max_percent_not_set'; end if;
  else
    mx := public.rule_num('crm_voucher_max_amount'); if mx is null then raise exception 'max_amount_not_set'; end if;
  end if;
  if val_ > mx and (p_id is null or val_ is distinct from c.value or kind_ is distinct from c.kind) then
    if not public.is_owner() then raise exception 'over_maximum'; end if;
    ov := public._crmf_reason(ov); over_ := true;
  end if;
  -- friendly messages before the table checks would speak
  if p_id is null then
    if public._d43(p, 'valid_to') < public._d43(p, 'valid_from') then raise exception 'bad_date'; end if;
    if coalesce((p->>'post_liability')::boolean, false) and (kind_ <> 'amount' or public._n43(p, 'max_uses', 1, 100000000) is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  else
    if coalesce(public._d43(p, 'valid_to'), c.valid_to) < coalesce(public._d43(p, 'valid_from'), c.valid_from) then raise exception 'bad_date'; end if;
    if (case when p ? 'post_liability' then coalesce((p->>'post_liability')::boolean, false) else c.post_liability end)
       and (kind_ <> 'amount' or (case when p ? 'max_uses' then public._n43(p, 'max_uses', 1, 100000000) else c.max_uses end) is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  end if;
  if p_id is null then
    insert into public.crmf_coupons (code, name, kind, value, min_bill, max_discount, valid_from, valid_to, max_uses, per_customer_uses, customer_id, campaign_ref, note, post_liability, client_id, created_by, created_staff)
      values (k, left(btrim(p->>'name'), 80), kind_, val_, public._n43(p, 'min_bill', 0, 1000000000), public._n43(p, 'max_discount', 0.01, 1000000000), public._d43(p, 'valid_from'), public._d43(p, 'valid_to'),
              public._n43(p, 'max_uses', 1, 100000000)::int, coalesce(public._n43(p, 'per_customer_uses', 1, 100000)::int, 1), nullif(p->>'customer_id', '')::uuid, left(nullif(btrim(p->>'campaign_ref'), ''), 60),
              left(nullif(btrim(p->>'note'), ''), 300), coalesce((p->>'post_liability')::boolean, false), p_client, auth.uid(), public._crmf_staff())
      returning * into n;
  else
    update public.crmf_coupons set
      name = case when p ? 'name' then coalesce(left(nullif(btrim(p->>'name'), ''), 80), name) else name end,
      kind = kind_, value = val_,
      min_bill = case when p ? 'min_bill' then public._n43(p, 'min_bill', 0, 1000000000) else min_bill end,
      max_discount = case when p ? 'max_discount' then public._n43(p, 'max_discount', 0.01, 1000000000) else max_discount end,
      valid_from = case when p ? 'valid_from' then coalesce(public._d43(p, 'valid_from'), valid_from) else valid_from end,
      valid_to = case when p ? 'valid_to' then coalesce(public._d43(p, 'valid_to'), valid_to) else valid_to end,
      max_uses = case when p ? 'max_uses' then public._n43(p, 'max_uses', 1, 100000000)::int else max_uses end,
      per_customer_uses = case when p ? 'per_customer_uses' then coalesce(public._n43(p, 'per_customer_uses', 1, 100000)::int, per_customer_uses) else per_customer_uses end,
      customer_id = case when p ? 'customer_id' then nullif(p->>'customer_id', '')::uuid else customer_id end,
      campaign_ref = case when p ? 'campaign_ref' then left(nullif(btrim(p->>'campaign_ref'), ''), 60) else campaign_ref end,
      note = case when p ? 'note' then left(nullif(btrim(p->>'note'), ''), 300) else note end,
      post_liability = case when p ? 'post_liability' then coalesce((p->>'post_liability')::boolean, false) else post_liability end,
      active = case when p ? 'active' then coalesce((p->>'active')::boolean, active) else active end,
      updated_at = now()
    where id = p_id returning * into n;
  end if;
  if p ? 'scope' and (p_id is null or used = 0) then
    sc := p->'scope';
    if sc is not null and jsonb_typeof(sc) = 'object' then
      delete from public.crmf_coupon_scope where coupon_id = n.id;
      for x in select * from jsonb_array_elements(coalesce(sc->'locations', '[]'::jsonb)) loop
        if not exists (select 1 from public.locations where id = (x #>> '{}')::int) then raise exception 'bad_location'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'location', x #>> '{}') on conflict do nothing;
      end loop;
      for x in select * from jsonb_array_elements(coalesce(sc->'items', '[]'::jsonb)) loop
        if not exists (select 1 from public.items where id = (x #>> '{}')::uuid) then raise exception 'bad_item'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'item', x #>> '{}') on conflict do nothing;
      end loop;
      for x in select * from jsonb_array_elements(coalesce(sc->'categories', '[]'::jsonb)) loop
        if length(btrim(x #>> '{}')) = 0 then raise exception 'bad_value'; end if;
        insert into public.crmf_coupon_scope (coupon_id, kind, ref) values (n.id, 'category', left(btrim(x #>> '{}'), 80)) on conflict do nothing;
      end loop;
    end if;
  end if;
  if n.valid_to < n.valid_from then raise exception 'bad_date'; end if;
  if n.post_liability and (n.kind <> 'amount' or n.max_uses is null) then raise exception 'liability_needs_amount_and_max_uses'; end if;
  if over_ then perform public._crmf_audit('crmf_coupon_over_maximum', 'crmf_coupons', n.id::text, jsonb_build_object('code', n.code, 'kind', n.kind, 'value', n.value, 'max', mx, 'reason', ov)); end if;
  if public.rule_on('crm_voucher_liability_on') and n.post_liability then perform public._crmf_liab_sync_one(n.id); end if;
  return jsonb_build_object('dup', false, 'id', n.id, 'code', n.code);
end $$;

create or replace function public.crmf_coupon_list(p_active boolean default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select c.id, c.code, c.name, c.kind, c.value, c.min_bill, c.max_discount, c.valid_from, c.valid_to, c.max_uses, c.per_customer_uses, c.customer_id, c.campaign_ref, c.note, c.post_liability, c.active, c.created_at,
           (select count(*) from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done')::int as uses,
           coalesce((select sum(u.discount_given) from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done'), 0) as discount_total,
           coalesce((select jsonb_agg(jsonb_build_object('kind', sc.kind, 'ref', sc.ref) order by sc.kind, sc.ref) from public.crmf_coupon_scope sc where sc.coupon_id = c.id), '[]'::jsonb) as scope
      from public.crmf_coupons c where p_active is null or c.active = p_active) z), '[]'::jsonb);
end $$;

-- ---------- the till: check (writes nothing) ----------
create or replace function public.crmf_coupon_check(p_code text, p_loc int, p_customer uuid, p_lines jsonb, p_subtotal numeric, p_override text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.crmf_coupons; ov boolean := false; ev jsonb;
begin
  if not (public._crmf_voucher_mgr() or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_on') then raise exception 'vouchers_off'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_loc is null then raise exception 'location_required'; end if;
  if nullif(btrim(p_override), '') is not null then
    if not public._crmf_override_ok() then raise exception 'not allowed'; end if;
    perform public._crmf_reason(p_override); ov := true;
  end if;
  select * into c from public.crmf_coupons where code = public._crmf_code(p_code);
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  ev := public._crmf_coupon_eval(c, p_loc, p_customer, p_lines, p_subtotal, public._crmf_today(), null, ov);
  return ev || jsonb_build_object('code', c.code, 'name', c.name, 'kind', c.kind, 'value', c.value);
end $$;

-- ---------- after the sale: record the use ----------
create or replace function public.crmf_coupon_redeem_after_sale(p_code text, p_sale uuid, p_override text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; s public.sales; u public.crmf_coupon_uses; ev jsonb; ov boolean := false; ovt text := nullif(btrim(p_override), ''); exp_ numeric; mism boolean; k text := public._crmf_code(p_code); mgr boolean;
begin
  mgr := public._crmf_voucher_mgr() or public._crmf_override_ok();       -- the owner, coupon managers and override holders may act on any sale; a cashier only on their own
  if not (mgr or (public.is_active() and public.can_do('POS', 'enter'))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_on') then raise exception 'vouchers_off'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into u from public.crmf_coupon_uses where client_id = p_client;
    if found then return jsonb_build_object('ok', true, 'dup', true, 'use_id', u.id); end if;
  end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.created_by is distinct from auth.uid() and not mgr then raise exception 'not allowed'; end if;
  if ovt is not null then
    if not public._crmf_override_ok() then raise exception 'not allowed'; end if;
    ovt := public._crmf_reason(ovt); ov := true;
  end if;
  select * into u from public.crmf_coupon_uses where sale_id = p_sale;
  if found then
    if u.coupon_id = (select id from public.crmf_coupons where code = k) then return jsonb_build_object('ok', true, 'dup', true, 'use_id', u.id); end if;
    return jsonb_build_object('ok', false, 'reason', 'sale_has_coupon');
  end if;
  select * into c from public.crmf_coupons where code = k for update;                          -- one redemption at a time per coupon: the race is decided here
  if not found then
    if s.discount > 0 then perform public._crmf_exception('coupon_refused', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || left(k, 20) || ' not found but the bill carries a discount', s.id); end if;
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  ev := public._crmf_coupon_eval(c, s.location_id, s.customer_id, s.lines, s.subtotal, s.sale_date, s.id, ov);
  if not (ev->>'ok')::boolean then
    if s.discount > 0 then
      perform public._crmf_exception('coupon_refused', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || c.code || ' refused (' || (ev->>'reason') || ') but the bill carries a discount', s.id);
    end if;
    return jsonb_build_object('ok', false, 'reason', ev->>'reason', 'overridable', coalesce((ev->>'overridable')::boolean, false));
  end if;
  exp_ := (ev->>'discount')::numeric;
  mism := abs(s.discount - exp_) > 0.01;
  insert into public.crmf_coupon_uses (coupon_id, sale_id, customer_id, location_id, bill_total, discount_expected, discount_given, mismatch, override_reason, client_id, by_user, by_staff)
    values (c.id, s.id, s.customer_id, s.location_id, s.total, exp_, s.discount, mism, case when jsonb_array_length(ev->'overridden') > 0 then ovt end, p_client, auth.uid(), public._crmf_staff()) returning * into u;
  if jsonb_array_length(ev->'overridden') > 0 then
    perform public._crmf_audit('crmf_coupon_override', 'crmf_coupon_uses', u.id::text, jsonb_build_object('code', c.code, 'sale', s.id, 'rules', ev->'overridden', 'reason', ovt));
    perform public._crmf_exception('coupon_override', s.location_id, s.sale_date, s.discount, 'Receipt ' || s.receipt || ': coupon ' || c.code || ' accepted past ' || (ev->>'overridden') || ': ' || ovt, s.id);
  end if;
  if mism then
    perform public._crmf_exception('coupon_discount_mismatch', s.location_id, s.sale_date, abs(s.discount - exp_), 'Receipt ' || s.receipt || ': coupon ' || c.code || ' gives ' || exp_ || ' but the bill discount is ' || s.discount, s.id);
  end if;
  if c.post_liability and public.rule_on('crm_voucher_liability_on') then perform public._crmf_liab_sync_one(c.id); end if;
  return jsonb_build_object('ok', true, 'dup', false, 'use_id', u.id, 'discount_expected', exp_, 'discount_given', s.discount, 'mismatch', mism);
end $$;

create or replace function public.crmf_coupon_uses_list(p_coupon uuid default null, p_from date default null, p_to date default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_voucher_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select u.id, u.coupon_id, c.code, u.sale_id, s.receipt, s.sale_date, s.status as sale_status, u.location_id, u.customer_id, cu.name as customer_name, u.bill_total,
           u.discount_expected, u.discount_given, u.mismatch, u.override_reason, u.at, u.by_staff
      from public.crmf_coupon_uses u join public.crmf_coupons c on c.id = u.coupon_id join public.sales s on s.id = u.sale_id left join public.customers cu on cu.id = u.customer_id
     where (p_coupon is null or u.coupon_id = p_coupon) and (p_from is null or s.sale_date >= p_from) and (p_to is null or s.sale_date <= p_to)
     order by u.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- ---------- voucher liability (OFF; the only writer to the books in this package) ----------
-- what the books should hold for one coupon right now
create or replace function public._crmf_liab_target(c public.crmf_coupons) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare used numeric;
begin
  if not c.post_liability or c.kind <> 'amount' or c.max_uses is null then return 0; end if;
  if not c.active or c.valid_to < public._crmf_today() then return 0; end if;
  select coalesce(sum(u.discount_given), 0) into used from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where u.coupon_id = c.id and s.status = 'done';
  return greatest(c.value * c.max_uses - used, 0);
end $$;

-- brings the books to the target for ONE coupon: posts only the difference, two lines, Dr = Cr. p_force_zero = wind down (target 0, even when the setting is OFF)
create or replace function public._crmf_liab_post(p_coupon uuid, p_force_zero boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.crmf_coupons; tgt numeric; posted numeric; d numeric; liab bigint; expn bigint; n int; eid bigint; lines jsonb; today date := public._crmf_today(); from_ date := public.rule_txt('crm_voucher_liability_from')::date;
begin
  select * into c from public.crmf_coupons where id = p_coupon for update;
  if not found then raise exception 'not found'; end if;
  select coalesce(sum(delta), 0), count(*)::int into posted, n from public.crmf_liab_postings where coupon_id = c.id;
  if p_force_zero then tgt := 0;
  else
    if from_ is null or (c.created_at at time zone 'Asia/Dhaka')::date < from_ then return jsonb_build_object('skipped', 'before_effective_date'); end if;
    tgt := public._crmf_liab_target(c);
  end if;
  d := round(tgt - posted, 2);
  if d = 0 then return jsonb_build_object('posted', 0, 'target', tgt, 'held', posted); end if;
  if not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  select id into liab from public.coa_accounts where code = public.rule_txt('crm_voucher_liability_account') and type = 'liability' and active and not is_group;
  select id into expn from public.coa_accounts where code = public.rule_txt('crm_voucher_expense_account') and type = 'expense' and active and not is_group;
  if liab is null or expn is null then raise exception 'liability_accounts_needed'; end if;
  if public._acct_locked(today) then raise exception 'period_closed'; end if;
  lines := case when d > 0
    then jsonb_build_array(jsonb_build_object('account_id', expn, 'debit', d, 'credit', 0, 'memo', 'Coupon ' || c.code), jsonb_build_object('account_id', liab, 'debit', 0, 'credit', d, 'memo', 'Coupon ' || c.code))
    else jsonb_build_array(jsonb_build_object('account_id', liab, 'debit', -d, 'credit', 0, 'memo', 'Coupon ' || c.code), jsonb_build_object('account_id', expn, 'debit', 0, 'credit', -d, 'memo', 'Coupon ' || c.code)) end;
  eid := public._acct_write(today, null, 'crmf_voucher', 'cp:' || c.id || ':' || (n + 1), 'voucher_liability',
           'Coupon ' || c.code || case when d > 0 then ': unused value held' else ': unused value released' end, null, lines);
  insert into public.crmf_liab_postings (coupon_id, delta, entry_id, why, by_user) values (c.id, d, eid, case when p_force_zero then 'wind_down' when d > 0 then 'issue' else 'use_or_expiry' end, auth.uid());
  return jsonb_build_object('posted', d, 'target', tgt, 'held', tgt, 'entry_id', eid);
end $$;

-- the automatic callers (after a save, a redemption, a void) must never stop the main action: an error is a warning, and the next sync repairs it
create or replace function public._crmf_liab_sync_one(p_coupon uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.rule_on('crm_voucher_liability_on') then return; end if;
  begin perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0)); perform public._crmf_liab_post(p_coupon, false);
  exception when others then raise warning 'crmf voucher liability sync failed for coupon %: %', p_coupon, sqlerrm; end;
end $$;

-- the named, owner-visible function: sync every marked coupon (or one). Owner or accounts manager. Self-healing: run it again any time.
create or replace function public.crmf_voucher_liability_sync(p_coupon uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; res jsonb; out_ jsonb := '[]'::jsonb; errs jsonb := '[]'::jsonb; n int := 0;
begin
  if not (public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_voucher_liability_on') then return jsonb_build_object('off', true); end if;
  perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0));
  for r in select id, code from public.crmf_coupons where (p_coupon is null or id = p_coupon)
            and (post_liability or exists (select 1 from public.crmf_liab_postings x where x.coupon_id = crmf_coupons.id)) order by created_at loop
    begin res := public._crmf_liab_post(r.id, false);
      if coalesce((res->>'posted')::numeric, 0) <> 0 then n := n + 1; out_ := out_ || jsonb_build_object('code', r.code, 'posted', res->'posted'); end if;
    exception when others then errs := errs || jsonb_build_object('code', r.code, 'error', sqlerrm); end;
  end loop;
  return jsonb_build_object('off', false, 'entries', n, 'rows', out_, 'errors', errs);
end $$;

-- move every held amount back to zero (use before switching the setting off). Owner or accounts manager; a reason is required.
create or replace function public.crmf_voucher_liability_wind_down(p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; res jsonb; n int := 0; tot numeric := 0; why text;
begin
  if not (public.is_owner() or public._acct_manage()) then raise exception 'not allowed'; end if;
  why := public._crmf_reason(p_reason);
  perform pg_advisory_xact_lock(hashtextextended('crmf_liab', 0));
  for r in select coupon_id from public.crmf_liab_postings group by coupon_id having sum(delta) <> 0 loop
    res := public._crmf_liab_post(r.coupon_id, true);
    n := n + 1; tot := tot + coalesce((res->>'posted')::numeric, 0);
  end loop;
  perform public._crmf_audit('crmf_voucher_liability_wind_down', 'crmf_liab_postings', null, jsonb_build_object('coupons', n, 'released', -tot, 'reason', why));
  return jsonb_build_object('coupons', n, 'released', -tot);
end $$;

create or replace function public.crmf_voucher_liability_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._acct_manage() or public._acct_view()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('crm_voucher_liability_on'), 'from', public.rule_txt('crm_voucher_liability_from'),
    'liability_account', public.rule_txt('crm_voucher_liability_account'), 'expense_account', public.rule_txt('crm_voucher_expense_account'),
    'held_total', coalesce((select sum(delta) from public.crmf_liab_postings), 0),
    'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.code) from (
      select c.code, c.name, c.value, c.max_uses, c.valid_to, c.active, public._crmf_liab_target(c) as should_hold, coalesce((select sum(delta) from public.crmf_liab_postings p where p.coupon_id = c.id), 0) as held
        from public.crmf_coupons c where c.post_liability or exists (select 1 from public.crmf_liab_postings p where p.coupon_id = c.id)) z), '[]'::jsonb));
end $$;

-- a voided sale gives its coupon use back: the liability follows (only while the setting is ON; an error never stops the void)
create or replace function public._crmf_sale_void_coupon() returns trigger language plpgsql security definer set search_path = public as $$
declare u public.crmf_coupon_uses;
begin
  if new.status <> 'void' or old.status is not distinct from 'void' or not public.rule_on('crm_voucher_liability_on') then return new; end if;
  begin
    select * into u from public.crmf_coupon_uses where sale_id = new.id;
    if found then perform public._crmf_liab_sync_one(u.coupon_id); end if;
  exception when others then raise warning 'crmf coupon void sync failed for sale %: %', new.id, sqlerrm; end;
  return new;
end $$;
revoke all on function public._crmf_sale_void_coupon() from public, anon, authenticated;
drop trigger if exists sales_void_coupon_crmf on public.sales;
create trigger sales_void_coupon_crmf after update of status on public.sales for each row execute function public._crmf_sale_void_coupon();

-- ---------- privileges ----------
revoke all on function public._crmf_voucher_mgr(), public._crmf_override_ok(), public._crmf_coupon_eval(public.crmf_coupons, int, uuid, jsonb, numeric, date, uuid, boolean), public._crmf_code(text),
  public._crmf_liab_target(public.crmf_coupons), public._crmf_liab_post(uuid, boolean), public._crmf_liab_sync_one(uuid) from public, anon, authenticated;
grant execute on function public._crmf_voucher_mgr() to authenticated;                 -- the table policies call it (answers true / false only)
revoke all on function public.crmf_coupon_save(uuid, jsonb, uuid, text), public.crmf_coupon_list(boolean), public.crmf_coupon_check(text, int, uuid, jsonb, numeric, text),
  public.crmf_coupon_redeem_after_sale(text, uuid, text, uuid), public.crmf_coupon_uses_list(uuid, date, date, int), public.crmf_voucher_liability_sync(uuid),
  public.crmf_voucher_liability_wind_down(text), public.crmf_voucher_liability_report() from public, anon;
grant execute on function public.crmf_coupon_save(uuid, jsonb, uuid, text), public.crmf_coupon_list(boolean), public.crmf_coupon_check(text, int, uuid, jsonb, numeric, text),
  public.crmf_coupon_redeem_after_sale(text, uuid, text, uuid), public.crmf_coupon_uses_list(uuid, date, date, int), public.crmf_voucher_liability_sync(uuid),
  public.crmf_voucher_liability_wind_down(text), public.crmf_voucher_liability_report() to authenticated;

-- ---------------------------------------------------------------- phase319.sql
-- ============================================================
-- BOS tool - Phase 319 (CRM package F, label 119): LOYALTY EXTRAS part 4 - birthday / anniversary / festival HOOKS (rules only), POINTS STATEMENT, LOYALTY SUMMARY, status.
-- Needs phase316, phase317, phase318. Paste after phase318. Paste twice is safe.
--
-- HOOKS: a hook is a RULE: "for birthdays, from N days before, give B bonus points and/or point to coupon C". Sending a message belongs to package D (campaigns);
-- these functions only say WHO is due (crmf_hooks_due) so D / E can use the list, and, when the owner runs it, grant the bonus points once per customer per year.
--   * crm_hooks_on is OFF: the due list is empty and nothing is granted. Nothing runs by itself: crmf_hook_run is a button (a scheduler can call it later; that is package E).
--   * A hook is created INACTIVE. Bonus points need loyalty points ON. A festival hook never grants points (the owner types festival dates each year; no date is invented).
-- POINTS STATEMENT: crmf_points_statement(customer, from, to): opening, every row with a running balance, closing. Reads only.
-- LOYALTY SUMMARY: crmf_loyalty_summary(from, to): points in / out / expired, outstanding points and their value, referrals, coupons, hooks, liability held. Reads only.
-- SETTINGS (rules, module crm): crm_hooks_on (OFF)
-- ============================================================

do $g$ begin
  if to_regprocedure('public._crmf_present()') is null or to_regclass('public.crmf_referrals') is null or to_regclass('public.crmf_coupons') is null then
    raise exception 'phase319 needs phases 316, 317 and 318 first';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select 'crm_hooks_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null, 'Birthday, anniversary and festival hooks on', 'Birthday, anniversary and festival hooks on', 'Birthday, anniversary and festival hooks on',
  'OFF (default) = the due list is empty and no bonus is given. ON = the owner can see who is due and run the bonus. Hooks only describe the rule; messages are sent from the campaign screens.',
  'OFF (default) = the due list is empty and no bonus is given. ON = the owner can see who is due and run the bonus. Hooks only describe the rule; messages are sent from the campaign screens.',
  'OFF (default) = the due list is empty and no bonus is given. ON = the owner can see who is due and run the bonus. Hooks only describe the rule; messages are sent from the campaign screens.', 9640
on conflict (key) do nothing;

create table if not exists public.crmf_hooks (
  id bigint generated by default as identity primary key,
  kind text not null check (kind in ('birthday', 'anniversary', 'festival')),
  name text not null check (length(btrim(name)) between 1 and 80),
  offset_days int not null default 0 check (offset_days between 0 and 60),
  festival_date date,
  bonus_points int check (bonus_points is null or (bonus_points > 0 and bonus_points <= 10000000)),
  coupon_id uuid references public.crmf_coupons(id),
  active boolean not null default false,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (kind <> 'festival' or festival_date is not null),
  check (kind = 'festival' or festival_date is null),
  check (kind <> 'festival' or bonus_points is null)
);
create table if not exists public.crmf_hook_grants (
  id bigint generated by default as identity primary key,
  hook_id bigint not null references public.crmf_hooks(id),
  customer_id uuid not null references public.customers(id),
  occasion_year int not null,
  points int not null check (points > 0),
  ledger_id bigint references public.customer_points_ledger(id),
  at timestamptz not null default now(),
  by_user uuid,
  unique (hook_id, customer_id, occasion_year)
);
drop trigger if exists crmf_hook_grants_ro on public.crmf_hook_grants;
create trigger crmf_hook_grants_ro before update or delete on public.crmf_hook_grants for each row execute function public._append_only43();
drop trigger if exists crmf_hook_grants_ro_t on public.crmf_hook_grants;
create trigger crmf_hook_grants_ro_t before truncate on public.crmf_hook_grants for each statement execute function public._append_only43();
drop trigger if exists audit_crmf_hooks on public.crmf_hooks;
create trigger audit_crmf_hooks after insert or update on public.crmf_hooks for each row execute function public.log_change('id');
drop trigger if exists crmf_hooks_no_delete on public.crmf_hooks;
create trigger crmf_hooks_no_delete before delete on public.crmf_hooks for each row execute function public.no_hard_delete();
alter table public.crmf_hooks enable row level security;
alter table public.crmf_hook_grants enable row level security;
drop policy if exists crmf_hooks_read on public.crmf_hooks;
create policy crmf_hooks_read on public.crmf_hooks for select to authenticated using (public._crmf_mgr());
drop policy if exists crmf_hook_grants_read on public.crmf_hook_grants;
create policy crmf_hook_grants_read on public.crmf_hook_grants for select to authenticated using (public._crmf_mgr());
revoke all on public.crmf_hooks, public.crmf_hook_grants from public, anon, authenticated;
grant select on public.crmf_hooks, public.crmf_hook_grants to authenticated;

-- the next time a yearly date (birthday / anniversary) comes round, on or after p_today. 29 February counts as 28 February in a year without one.
create or replace function public._crmf_next_occ(p_date date, p_today date) returns date language plpgsql immutable as $$
declare y int; cand date;
begin
  if p_date is null then return null; end if;
  for y in extract(year from p_today)::int .. extract(year from p_today)::int + 1 loop
    cand := case when extract(month from p_date) = 2 and extract(day from p_date) = 29 and not (y % 4 = 0 and (y % 100 <> 0 or y % 400 = 0)) then make_date(y, 2, 28)
                 else make_date(y, extract(month from p_date)::int, extract(day from p_date)::int) end;
    if cand >= p_today then return cand; end if;
  end loop;
  return null;
end $$;

create or replace function public.crmf_hook_save(p_id bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.crmf_hooks; k text; nm text; off_ int; fd date; bp int; cp uuid;
begin
  if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is null then
    k := p->>'kind'; if k is null or k not in ('birthday', 'anniversary', 'festival') then raise exception 'bad_kind'; end if;
    nm := nullif(btrim(p->>'name'), ''); if nm is null then raise exception 'name_required'; end if;
    off_ := coalesce(public._n43(p, 'offset_days', 0, 60)::int, 0); fd := public._d43(p, 'festival_date');
    bp := public._n43(p, 'bonus_points', 1, 10000000)::int; cp := nullif(p->>'coupon_id', '')::uuid;
    if k = 'festival' and fd is null then raise exception 'festival_date_required'; end if;
    if k <> 'festival' and fd is not null then raise exception 'bad_value'; end if;
    if k = 'festival' and bp is not null then raise exception 'festival_no_points'; end if;
    if cp is not null and not exists (select 1 from public.crmf_coupons where id = cp) then raise exception 'bad_coupon'; end if;
    insert into public.crmf_hooks (kind, name, offset_days, festival_date, bonus_points, coupon_id, note, created_by)
      values (k, left(nm, 80), off_, fd, bp, cp, left(nullif(btrim(p->>'note'), ''), 300), auth.uid()) returning * into h;
    return jsonb_build_object('id', h.id);
  end if;
  select * into h from public.crmf_hooks where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if p ? 'bonus_points' and h.kind = 'festival' and public._n43(p, 'bonus_points', 1, 10000000) is not null then raise exception 'festival_no_points'; end if;
  if p ? 'coupon_id' and nullif(p->>'coupon_id', '') is not null and not exists (select 1 from public.crmf_coupons where id = (p->>'coupon_id')::uuid) then raise exception 'bad_coupon'; end if;
  update public.crmf_hooks set
    name = case when p ? 'name' then coalesce(left(nullif(btrim(p->>'name'), ''), 80), name) else name end,
    offset_days = case when p ? 'offset_days' then coalesce(public._n43(p, 'offset_days', 0, 60)::int, offset_days) else offset_days end,
    festival_date = case when p ? 'festival_date' and kind = 'festival' then coalesce(public._d43(p, 'festival_date'), festival_date) else festival_date end,
    bonus_points = case when p ? 'bonus_points' then public._n43(p, 'bonus_points', 1, 10000000)::int else bonus_points end,
    coupon_id = case when p ? 'coupon_id' then nullif(p->>'coupon_id', '')::uuid else coupon_id end,
    note = case when p ? 'note' then left(nullif(btrim(p->>'note'), ''), 300) else note end,
    active = case when p ? 'active' then coalesce((p->>'active')::boolean, active) else active end,
    updated_at = now()
  where id = p_id returning * into h;
  return jsonb_build_object('id', h.id);
end $$;

create or replace function public.crmf_hook_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id) from (
    select h.id, h.kind, h.name, h.offset_days, h.festival_date, h.bonus_points, h.coupon_id, c.code as coupon_code, h.active, h.note,
           (select count(*) from public.crmf_hook_grants g where g.hook_id = h.id)::int as grants
      from public.crmf_hooks h left join public.crmf_coupons c on c.id = h.coupon_id) z), '[]'::jsonb);
end $$;

-- who is due today (or on p_date). Reads only. Empty while crm_hooks_on is OFF.
create or replace function public._crmf_hooks_due(p_date date, p_limit int) returns table (hook_id bigint, kind text, hook_name text, customer_id uuid, customer_name text, mobile text, occasion date, occasion_year int, bonus_points int, coupon_code text, granted boolean)
language sql stable security definer set search_path = public as $$
  select h.id, h.kind, h.name, c.id, c.name, public._crmf_mask(c.mobile), o.occ, extract(year from o.occ)::int, h.bonus_points, k.code,
         exists (select 1 from public.crmf_hook_grants g where g.hook_id = h.id and g.customer_id = c.id and g.occasion_year = extract(year from o.occ)::int)
    from public.crmf_hooks h
    join public.customers c on c.active and h.kind in ('birthday', 'anniversary')
    cross join lateral (select public._crmf_next_occ(case h.kind when 'birthday' then c.birthday else c.anniversary end, p_date) as occ) o
    left join public.crmf_coupons k on k.id = h.coupon_id
   where h.active and o.occ is not null and o.occ - p_date <= h.offset_days
  union all
  select h.id, h.kind, h.name, null::uuid, null, null, h.festival_date, extract(year from h.festival_date)::int, null::int, k.code, false
    from public.crmf_hooks h left join public.crmf_coupons k on k.id = h.coupon_id
   where h.active and h.kind = 'festival' and h.festival_date >= p_date and h.festival_date - p_date <= h.offset_days
  order by 7, 4
  limit least(greatest(coalesce(p_limit, 500), 1), 2000);
$$;

create or replace function public.crmf_hooks_due(p_date date default null, p_limit int default 500) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._crmf_today());
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_hooks_on') then return jsonb_build_object('off', true, 'rows', '[]'::jsonb); end if;
  return jsonb_build_object('off', false, 'date', d, 'rows', coalesce((select jsonb_agg(to_jsonb(z)) from public._crmf_hooks_due(d, p_limit) z), '[]'::jsonb));
end $$;

-- grant the bonus points of the active birthday / anniversary hooks. Dry run by default (writes nothing). Once per hook, customer and year.
create or replace function public.crmf_hook_run(p_date date default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(p_date, public._crmf_today()); r record; led bigint; n int := 0; pts int := 0; due int := 0;
begin
  if not public._crmf_apply_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_hooks_on') then raise exception 'hooks_off'; end if;
  if not coalesce(p_dry, true) then
    if not public.rule_on('loyalty_points_on') then raise exception 'loyalty_off'; end if;
    perform pg_advisory_xact_lock(hashtextextended('crmf_hook_run', 0));
  end if;
  for r in select * from public._crmf_hooks_due(d, 2000) x where x.kind in ('birthday', 'anniversary') and x.bonus_points is not null and not x.granted loop
    due := due + 1;
    if coalesce(p_dry, true) then continue; end if;
    perform 1 from public.customers where id = r.customer_id for update;
    led := null;
    insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
      values (r.customer_id, r.bonus_points, 'bonus', public._crmf_uuid('crmf_hook:' || r.hook_id || ':' || r.customer_id || ':' || r.occasion_year), r.hook_name || ' ' || r.occasion_year, auth.uid(), public._crmf_staff())
      on conflict do nothing returning id into led;
    if led is null then continue; end if;
    insert into public.crmf_hook_grants (hook_id, customer_id, occasion_year, points, ledger_id, by_user) values (r.hook_id, r.customer_id, r.occasion_year, r.bonus_points, led, auth.uid()) on conflict do nothing;
    n := n + 1; pts := pts + r.bonus_points;
  end loop;
  if not coalesce(p_dry, true) then
    perform public._crmf_audit('crmf_hook_run', 'crmf_hook_grants', d::text, jsonb_build_object('customers', n, 'points', pts));
  end if;
  return jsonb_build_object('dry', coalesce(p_dry, true), 'date', d, 'due', due, 'granted', n, 'points', pts);
end $$;

-- ---------- points statement ----------
create or replace function public.crmf_points_statement(p_customer uuid, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; f date := coalesce(p_from, date '2000-01-01'); t date := coalesce(p_to, public._crmf_today()); op int; cl int; rows_ jsonb; cfg jsonb; soon int := null;
        earned int; used int; exp_ int; d int := public.rule_num('crm_points_expiry_warn_days')::int;
begin
  if not public._crmf_pos() then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_date'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0)::int into op from public.customer_points_ledger where customer_id = p_customer and (at at time zone 'Asia/Dhaka')::date < f;
  select coalesce(sum(delta), 0)::int into cl from public.customer_points_ledger where customer_id = p_customer and (at at time zone 'Asia/Dhaka')::date <= t;
  select coalesce(sum(delta) filter (where delta > 0), 0)::int, (-coalesce(sum(delta) filter (where delta < 0 and reason <> 'expire'), 0))::int, (-coalesce(sum(delta) filter (where reason = 'expire'), 0))::int
    into earned, used, exp_ from public.customer_points_ledger where customer_id = p_customer and (at at time zone 'Asia/Dhaka')::date between f and t;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'reason', z.reason, 'delta', z.delta, 'balance', z.running, 'receipt', z.receipt, 'note', z.note, 'by', z.by_staff) order by z.id desc), '[]'::jsonb) into rows_
    from (select * from (select l.id, l.at, l.reason, l.delta, l.note, l.by_staff, s.receipt, op + sum(l.delta) over (order by l.id) as running, (l.at at time zone 'Asia/Dhaka')::date as dt
                          from public.customer_points_ledger l left join public.sales s on s.id = l.sale_id
                         where l.customer_id = p_customer and (l.at at time zone 'Asia/Dhaka')::date <= t) q
          where q.dt >= f order by q.id desc limit 1000) z;
  cfg := public._crmf_expiry_cfg(null);
  if not (cfg->>'off')::boolean and d is not null then
    select coalesce((select expirable from public._crmf_expiry_rows(((public._crmf_today() + d) - make_interval(months => (cfg->>'months')::int))::date, (cfg->>'from')::date, p_customer)), 0)
         - coalesce((select expirable from public._crmf_expiry_rows((cfg->>'cut')::date, (cfg->>'from')::date, p_customer)), 0) into soon;
  end if;
  return jsonb_build_object('customer', jsonb_build_object('id', c.id, 'name', c.name), 'from', f, 'to', t, 'opening', op, 'closing', cl, 'earned', earned, 'used', used, 'expired', exp_,
    'balance_now', (select coalesce(sum(delta), 0)::int from public.customer_points_ledger where customer_id = p_customer),
    'value_taka', round((select coalesce(sum(delta), 0) from public.customer_points_ledger where customer_id = p_customer) * coalesce(public.rule_num('point_value_taka'), 0), 2),
    'expiring_soon', soon, 'rows', rows_);
end $$;

-- ---------- loyalty summary ----------
create or replace function public.crmf_loyalty_summary(p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, date_trunc('month', public._crmf_today())::date); t date := coalesce(p_to, public._crmf_today()); pv numeric := coalesce(public.rule_num('point_value_taka'), 0);
        pts jsonb; refs jsonb; cps jsonb; hk jsonb; out_ bigint; mem int;
begin
  if not public._crmf_mgr() then raise exception 'not allowed'; end if;
  if t < f then raise exception 'bad_date'; end if;
  select jsonb_build_object(
      'earned_sales', coalesce(sum(delta) filter (where reason = 'sale'), 0),
      'earned_referral', coalesce(sum(delta) filter (where reason = 'referral' and delta > 0), 0),
      'earned_bonus', coalesce(sum(delta) filter (where reason = 'bonus'), 0),
      'adjusted_up', coalesce(sum(delta) filter (where reason = 'adjust' and delta > 0), 0),
      'adjusted_down', coalesce(-sum(delta) filter (where reason = 'adjust' and delta < 0), 0),
      'redeemed', coalesce(-sum(delta) filter (where reason = 'redeem'), 0),
      'expired', coalesce(-sum(delta) filter (where reason = 'expire'), 0),
      'rows', count(*)) into pts
    from public.customer_points_ledger where (at at time zone 'Asia/Dhaka')::date between f and t;
  select coalesce(sum(b), 0), count(*) filter (where b > 0) into out_, mem from (select sum(delta) b from public.customer_points_ledger group by customer_id) q;
  select jsonb_build_object('pending', count(*) filter (where status = 'pending'), 'rewarded', count(*) filter (where status = 'rewarded'), 'rejected', count(*) filter (where status = 'rejected'),
      'reversed', count(*) filter (where status = 'reversed'), 'reward_points', coalesce(sum(reward_points) filter (where status = 'rewarded'), 0)) into refs
    from public.crmf_referrals where (created_at at time zone 'Asia/Dhaka')::date between f and t;
  select jsonb_build_object('active', (select count(*) from public.crmf_coupons where active), 'uses', count(*), 'discount_given', coalesce(sum(u.discount_given), 0), 'mismatches', count(*) filter (where u.mismatch),
      'overrides', count(*) filter (where u.override_reason is not null),
      'top', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'uses', n, 'discount', dsc) order by n desc) from (
          select c.code, count(*) n, sum(u2.discount_given) dsc from public.crmf_coupon_uses u2 join public.sales s2 on s2.id = u2.sale_id join public.crmf_coupons c on c.id = u2.coupon_id
           where s2.status = 'done' and s2.sale_date between f and t group by c.code order by count(*) desc limit 10) tp), '[]'::jsonb)) into cps
    from public.crmf_coupon_uses u join public.sales s on s.id = u.sale_id where s.status = 'done' and s.sale_date between f and t;
  select jsonb_build_object('grants', count(*), 'points', coalesce(sum(points), 0)) into hk from public.crmf_hook_grants where (at at time zone 'Asia/Dhaka')::date between f and t;
  return jsonb_build_object('from', f, 'to', t, 'points', pts, 'outstanding_points', out_, 'outstanding_value_taka', round(out_ * pv, 2), 'members_with_points', mem, 'point_value_taka', pv,
    'referrals', refs, 'coupons', cps, 'hooks', hk,
    'voucher_liability_held', coalesce((select sum(delta) from public.crmf_liab_postings), 0),
    'note', 'Outstanding points are a figure for information. They are not booked in the accounts.');
end $$;

-- ---------- status: which extras are on, and what is still blank (so a screen can say "Set this first") ----------
create or replace function public.crmf_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmf_pos() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'loyalty_on', public.rule_on('loyalty_points_on'), 'gifts_on', public.rule_on('customer_gifts_on'), 'point_value_taka', public.rule_num('point_value_taka'),
    'expiry', jsonb_build_object('months', public.rule_num('crm_points_expiry_months'), 'from', public.rule_txt('crm_points_expiry_from'), 'warn_days', public.rule_num('crm_points_expiry_warn_days')),
    'burn', jsonb_build_object('max_percent', public.rule_num('crm_burn_max_percent'), 'max_points', public.rule_num('crm_burn_max_points'), 'step', public.rule_num('crm_burn_step_points')),
    'referral', jsonb_build_object('on', public.rule_on('crm_referral_on'), 'reward', public.rule_num('crm_referral_reward_points'), 'referred', public.rule_num('crm_referral_referred_points'), 'min_bill', public.rule_num('crm_referral_min_bill')),
    'voucher', jsonb_build_object('on', public.rule_on('crm_voucher_on'), 'max_percent', public.rule_num('crm_voucher_max_percent'), 'max_amount', public.rule_num('crm_voucher_max_amount'),
      'liability_on', public.rule_on('crm_voucher_liability_on'), 'liability_from', public.rule_txt('crm_voucher_liability_from')),
    'hooks_on', public.rule_on('crm_hooks_on'),
    'can', jsonb_build_object('manage', public._crmf_mgr(), 'apply', public._crmf_apply_ok(), 'voucher', public._crmf_voucher_mgr(), 'override', public._crmf_override_ok(), 'accounts', public._acct_manage()));
end $$;

revoke all on function public._crmf_next_occ(date, date), public._crmf_hooks_due(date, int) from public, anon, authenticated;
revoke all on function public.crmf_hook_save(bigint, jsonb), public.crmf_hook_list(), public.crmf_hooks_due(date, int), public.crmf_hook_run(date, boolean),
  public.crmf_points_statement(uuid, date, date), public.crmf_loyalty_summary(date, date), public.crmf_status() from public, anon;
grant execute on function public.crmf_hook_save(bigint, jsonb), public.crmf_hook_list(), public.crmf_hooks_due(date, int), public.crmf_hook_run(date, boolean),
  public.crmf_points_statement(uuid, date, date), public.crmf_loyalty_summary(date, date), public.crmf_status() to authenticated;

-- ---------------------------------------------------------------- phase323.sql
-- Phase 323 (bos323, package CRM-G label 123, part 1 of 5) - ENQUIRY AND LEAD PIPELINE, TASKS: SETTINGS, RIGHTS, LISTS, TABLES, GUARDS.
-- Paste AFTER phase98 (needs the rules table, grants, the Exceptions list of phase87, online orders of phase61/76, notifications). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created: every new name starts crm_ (tables) or _crmg_ (functions). Nothing here posts to the books.
--
-- WHAT THE FIVE FILES ADD
--   323  settings (rules, module crm, all OFF or blank), rights (grants), three owner-editable lists (lost reasons, sources, occasions), the tables, their guards
--   324  leads: save, notes, assign, stage moves, lost with a reason, reopen with a reason (an exception), quotes with items and validity, one lead
--   325  convert a won lead through the EXISTING order functions (online_order_save2 / save_entry) or link an existing record; lead list, board, win/loss report
--   326  tasks: add, done, snooze, skip, reassign, My tasks, counts for the Home strip, optional in-app reminders (OFF)
--   327  settings overview, hook state, readiness check
--
-- OWNER RULES MET: (1) every policy is a setting with a safe default; modules are OFF; nothing starts by itself; no reminder unless switched on.
-- (2) a lead, a quote and a task post NOTHING (no journal, no sale, no payment, no stock). (3) exceptions with a reason: reopen a lost lead, late quote,
-- win without a quote. (4) no approver is hard-coded: rights are grants the owner gives to roles or people. (5) English labels only. (7) a lead is visible to
-- the owner, to holders of crm_lead_all, and otherwise only inside the outlets the person works in (assignee, maker or holder of crm_lead_manage).

do $g$ begin
  if to_regprocedure('public._w1g_present()') is null then raise exception 'phase323 needs phase98 (and 80-97) first'; end if;
  if to_regclass('public.money_exceptions') is null or to_regclass('public.notifications') is null or to_regclass('public.online_orders') is null
     or to_regprocedure('public.online_order_save2(uuid,uuid,integer,integer,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regprocedure('public.save_entry(uuid,text,integer,date,jsonb,jsonb,text,jsonb)') is null then
    raise exception 'phase323 needs the online order channel (phase 61, 76), the paper forms (phase 17) and the Exceptions list (phase 87)';
  end if;
end $g$;

create or replace function public._crmg_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. EXCEPTIONS LIST: three more kinds (additive: keeps every kind another package added; same method as phase94)
-- ============================================================================
create or replace function public._crmg_add_exc_kinds(p_kinds text[]) returns void language plpgsql set search_path = public as $$
declare con text; def text; cur text[]; allk text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase323: money_exceptions kind check not found'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase323: money_exceptions kind check has an unknown shape'; end if;
  allk := cur;
  foreach k in array p_kinds loop if not (k = any (allk)) then allk := allk || k; end if; end loop;
  if allk = cur then return; end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(allk) x));
end $$;
select public._crmg_add_exc_kinds(array['crmg_lead_reopen', 'crmg_late_quote', 'crmg_win_without_quote']);

-- ============================================================================
-- 2. SETTINGS (rules, module crm). Every row: safe default, plain English label and hint. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_lead_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Track party, wholesale, corporate and gift enquiries',
   'OFF = no lead screens work (today). ON = staff can record an enquiry, send a quote, follow it up and mark it won or lost. A lead or quote never posts to the books.', 3200),
 ('crm_task_on', 'switch', 'false'::jsonb, null, null, null, null,
   'Use follow-up tasks and the My tasks list',
   'OFF = no task can be added (today). ON = staff can add a task with a due time, tick it done, snooze it, and see overdue ones on My tasks. A task never posts to the books.', 3201),
 ('crm_lead_lost_by', 'choice', '"manager"'::jsonb, null, '["manager","assignee"]'::jsonb, null, null,
   'Who may close an enquiry as lost',
   'manager = only the owner or a person holding the right Manage enquiries (default). assignee = the person the enquiry is assigned to may also close it. A lost reason from the list is always needed.', 3202),
 ('crm_lead_reopen_mode', 'choice', '"reason"'::jsonb, null, '["reason","owner","off"]'::jsonb, null, null,
   'Reopening a lost enquiry',
   'reason = a manager may reopen with a written reason; it goes to the Exceptions list (default). owner = only the owner may reopen. off = a lost enquiry can never be reopened (start a new one).', 3203),
 ('crm_lead_win_needs_quote', 'switch', 'false'::jsonb, null, null, null, null,
   'An enquiry can be won only after a quote was sent',
   'OFF = an enquiry can be marked won without a quote (today). ON = a sent quote is needed first; a manager can still win it with a written reason, which goes to the Exceptions list.', 3204),
 ('crm_lead_quote_valid_days', 'number', null, 'days', null, 1::numeric, 365::numeric,
   'Quote validity: default number of days',
   'Blank = the person must type the valid-until date for every quote (a quote without a date is refused). A number = the date is filled in as today plus this many days; it can still be changed.', 3205),
 ('crm_quote_min_lead_days', 'number', null, 'days', null, 0::numeric, 365::numeric,
   'Late quote: least days between the quote and the event',
   'Blank = no check. A number = a quote sent when the event is closer than this many days (or already past), or with a valid-until date in the past, needs a written reason and goes to the Exceptions list.', 3206),
 ('crm_lead_stale_days', 'number', null, 'days', null, 1::numeric, 365::numeric,
   'Flag an open enquiry as stale after this many days of silence',
   'Blank = no stale flag. A number = an open enquiry with no note, quote or stage change for this many days shows a Stale flag on the board and in the report.', 3207),
 ('crm_lead_list_add_mode', 'choice', '"owner"'::jsonb, null, '["owner","manager"]'::jsonb, null, null,
   'Who may add a lost reason, source or occasion to the lists',
   'owner = only the owner (default). manager = also a person holding the right Manage enquiries. The entry Other can never be removed.', 3208),
 ('crm_task_default_due_hours', 'number', null, 'hours', null, 1::numeric, 720::numeric,
   'Task due time when none is typed',
   'Blank = a task must have a due date and time typed (a task without one is refused). A number = the due time is filled in as now plus this many hours.', 3209),
 ('crm_task_snooze_max_days', 'number', null, 'days', null, 1::numeric, 90::numeric,
   'Longest snooze for a task',
   'Blank = no limit on how far a task can be snoozed. A number = a snooze cannot go further than this many days from now.', 3210),
 ('crm_order_task_days', 'number', null, 'days', null, 0::numeric, 30::numeric,
   'Add a delivery task when an enquiry becomes an order',
   'Blank = no task is added (today). A number = when a won enquiry is turned into an order that has a delivery date, a task for the assigned person is added that many days before the delivery (0 = on the day). It closes by itself when the order is delivered or cancelled. Needs tasks switched on.', 3212),
 ('crm_task_reminder_on', 'switch', 'false'::jsonb, null, null, null, null,
   'Send staff an in-app reminder for due tasks and stale enquiries',
   'OFF = nothing is sent; staff only see their list when they open My tasks (today). ON = the 30-minute notify job adds one in-app line per person per day with counts only (no customer name or phone). It never messages a customer.', 3211)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 3. RIGHTS (grants). None is given to anyone by default except through the owner.
-- ============================================================================
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('crm_lead_manage', 'crm', 3200, 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'once', null),
 ('crm_lead_all', 'crm', 3201, 'See and work on the enquiries of every outlet', 'See and work on the enquiries of every outlet', 'See and work on the enquiries of every outlet', 'once', null),
 ('crm_task_assign', 'crm', 3202, 'Give tasks to other people', 'Give tasks to other people', 'Give tasks to other people', 'once', null),
 ('crm_task_all', 'crm', 3203, 'See the tasks of every person', 'See the tasks of every person', 'See the tasks of every person', 'once', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 4. LISTS (lost reasons, sources, occasions). Rule 4 of the build rules: every list has Add new and Other; nothing is deleted, an entry is retired.
-- ============================================================================
create table if not exists public.crm_lead_lists (
  kind text not null check (kind in ('lost_reason', 'source', 'occasion')),
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  active boolean not null default true,
  sort int not null default 100,
  created_by uuid, created_at timestamptz not null default now(),
  primary key (kind, code)
);
insert into public.crm_lead_lists (kind, code, label, sort) values
 ('lost_reason', 'price_high', 'Price was too high', 10), ('lost_reason', 'other_shop', 'Chose another shop', 20), ('lost_reason', 'date_not_possible', 'We could not do the date', 30),
 ('lost_reason', 'plan_cancelled', 'The plan was cancelled', 40), ('lost_reason', 'no_reply', 'No reply after follow-ups', 50), ('lost_reason', 'other', 'Other (write a note)', 900),
 ('source', 'walk_in', 'Walked in', 10), ('source', 'phone', 'Phone call', 20), ('source', 'message', 'Message', 30), ('source', 'web_form', 'Web form', 40),
 ('source', 'referral', 'Referred by someone', 50), ('source', 'other', 'Other', 900),
 ('occasion', 'birthday', 'Birthday', 10), ('occasion', 'wedding', 'Wedding or engagement', 20), ('occasion', 'corporate', 'Corporate or office', 30),
 ('occasion', 'wholesale', 'Wholesale', 40), ('occasion', 'gift', 'Gift box or hamper', 50), ('occasion', 'festival', 'Festival', 60), ('occasion', 'other', 'Other', 900)
on conflict (kind, code) do nothing;

-- ============================================================================
-- 5. TABLES (RLS on, closed to browser roles, read and written only through the definer functions of phases 324 to 327)
-- ============================================================================
create table if not exists public.crm_leads (
  id uuid primary key default gen_random_uuid(),
  lead_no bigint generated always as identity,
  client_id uuid,
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  contact_name text not null check (char_length(btrim(contact_name)) between 1 and 80),
  contact_phone text check (contact_phone is null or char_length(contact_phone) between 6 and 20),
  source text,
  inbound_message_id bigint,
  occasion text,
  event_date date,
  guests int check (guests is null or guests between 1 and 100000),
  est_value numeric check (est_value is null or (est_value >= 0 and est_value <= 1000000000000)),
  stage text not null default 'enquiry' check (stage in ('enquiry', 'quoted', 'following_up', 'won', 'lost')),
  lost_reason text,
  lost_note text check (lost_note is null or char_length(lost_note) <= 300),
  owner_user uuid not null,
  next_follow_up timestamptz,
  quote_ref text check (quote_ref is null or char_length(quote_ref) <= 80),
  online_order_id uuid references public.online_orders(id),
  entry_id uuid references public.entries(id),
  converted_at timestamptz, converted_by uuid, convert_client uuid,
  reopened_count int not null default 0,
  note text check (note is null or char_length(note) <= 300),
  stage_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  closed_at timestamptz,
  created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((stage = 'lost') = (lost_reason is not null)),
  check (online_order_id is null or entry_id is null)
);
create unique index if not exists crm_leads_client_uq on public.crm_leads (created_by, client_id) where client_id is not null;
create unique index if not exists crm_leads_msg_uq on public.crm_leads (inbound_message_id) where inbound_message_id is not null;
create unique index if not exists crm_leads_order_uq on public.crm_leads (online_order_id) where online_order_id is not null;
create unique index if not exists crm_leads_entry_uq on public.crm_leads (entry_id) where entry_id is not null;
create index if not exists crm_leads_board on public.crm_leads (location_id, stage, next_follow_up);
create index if not exists crm_leads_owner on public.crm_leads (owner_user, stage);
create index if not exists crm_leads_customer on public.crm_leads (customer_id) where customer_id is not null;

create table if not exists public.crm_lead_events (               -- append only trail of everything that happens to a lead
  id bigint generated always as identity primary key,
  lead_id uuid not null references public.crm_leads(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  kind text not null check (kind in ('created', 'edited', 'stage', 'note', 'quote', 'assign', 'follow_up', 'convert', 'reopen', 'task')),
  from_stage text, to_stage text,
  note text check (note is null or char_length(note) <= 1000),
  detail jsonb
);
create index if not exists crm_lead_events_lead on public.crm_lead_events (lead_id, id);

create table if not exists public.crm_lead_quotes (                -- a quote is a priced list with a validity date; it is NOT an invoice and posts nothing
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.crm_leads(id),
  version int not null,
  client_id uuid,
  status text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'declined', 'superseded')),
  valid_until date,
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 100),
  subtotal numeric not null check (subtotal >= 0 and subtotal <= 1000000000000),
  discount numeric not null default 0 check (discount >= 0 and discount <= 1000000000000),
  total numeric not null check (total >= 0 and total <= 1000000000000),
  note text check (note is null or char_length(note) <= 300),
  late_reason text check (late_reason is null or char_length(late_reason) <= 300),
  created_by uuid not null, created_at timestamptz not null default now(),
  sent_at timestamptz, responded_at timestamptz, response_note text check (response_note is null or char_length(response_note) <= 300),
  unique (lead_id, version)
);
create unique index if not exists crm_lead_quotes_client_uq on public.crm_lead_quotes (created_by, client_id) where client_id is not null;

create table if not exists public.crm_tasks (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  location_id int references public.locations(id),
  customer_id uuid references public.customers(id),
  lead_id uuid references public.crm_leads(id),
  order_id uuid references public.online_orders(id),
  kind text not null default 'other' check (kind in ('call', 'message', 'visit', 'follow_up', 'other')),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  due_at timestamptz not null,
  snooze_until timestamptz,
  snooze_count int not null default 0,
  assigned_to uuid not null,
  status text not null default 'open' check (status in ('open', 'done', 'skipped')),
  done_note text check (done_note is null or char_length(done_note) <= 300),
  skip_reason text check (skip_reason is null or char_length(skip_reason) <= 300),
  source text not null default 'manual' check (source in ('manual', 'lead', 'order', 'auto')),
  created_by uuid not null, created_at timestamptz not null default now(),
  done_by uuid, done_at timestamptz, updated_at timestamptz not null default now(),
  check ((status = 'done') = (done_at is not null))
);
create unique index if not exists crm_tasks_client_uq on public.crm_tasks (created_by, client_id) where client_id is not null;
create index if not exists crm_tasks_mine on public.crm_tasks (assigned_to, status, due_at);
create index if not exists crm_tasks_lead on public.crm_tasks (lead_id) where lead_id is not null;

create table if not exists public.crm_task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.crm_tasks(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  kind text not null check (kind in ('created', 'edited', 'assigned', 'snoozed', 'done', 'skipped')),
  note text check (note is null or char_length(note) <= 300),
  detail jsonb
);
create index if not exists crm_task_events_task on public.crm_task_events (task_id, id);

-- ============================================================================
-- 6. GUARDS
-- ============================================================================
-- the trail tables can never be changed or deleted
create or replace function public._crmg_append_only() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the trail of a lead or a task cannot be changed or deleted'; end $$;

-- a lead moves only along the allowed lines. A direct change in the database is refused too (a hidden button is also a refused request).
-- won and lost are final; a lost lead can go back to enquiry or following_up ONLY through _crmg_lead_reopen (it sets crmg.reopen for its own transaction).
create or replace function public._crmg_stage_ok(p_from text, p_to text) returns boolean language sql immutable as $$
  select case p_from
    when 'enquiry' then p_to in ('quoted', 'following_up', 'won', 'lost')
    when 'quoted' then p_to in ('following_up', 'won', 'lost')
    when 'following_up' then p_to in ('quoted', 'won', 'lost')
    else false end $$;
create or replace function public._crmg_leads_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - close the enquiry as lost instead'; end if;
  if new.stage is distinct from old.stage then
    if old.stage = 'lost' and new.stage in ('enquiry', 'following_up') and coalesce(current_setting('crmg.reopen', true), '') = '1' then
      null;
    elsif not public._crmg_stage_ok(old.stage, new.stage) then
      raise exception 'illegal_stage_move: % to % is not allowed', old.stage, new.stage;
    end if;
    if new.stage = 'lost' and (new.lost_reason is null or not exists (select 1 from public.crm_lead_lists where kind = 'lost_reason' and code = new.lost_reason)) then
      raise exception 'lost_reason_required: choose a lost reason from the list';
    end if;
    new.stage_at := now();
    new.closed_at := case when new.stage in ('won', 'lost') then now() else null end;
  elsif old.stage in ('won', 'lost') then
    -- a closed lead keeps its facts; only the link to the created record and the activity clock may be filled in
    if (new.contact_name, new.contact_phone, new.customer_id, new.event_date, new.guests, new.est_value, new.occasion, new.source, new.owner_user, new.location_id, new.lost_reason, new.lost_note)
       is distinct from (old.contact_name, old.contact_phone, old.customer_id, old.event_date, old.guests, old.est_value, old.occasion, old.source, old.owner_user, old.location_id, old.lost_reason, old.lost_note)
       and not (old.stage = 'won' and old.converted_at is null) then
      raise exception 'lead_closed: a won or lost enquiry cannot be edited';
    end if;
  end if;
  if old.online_order_id is not null and new.online_order_id is distinct from old.online_order_id then raise exception 'already_converted: the linked order cannot be changed'; end if;
  if old.entry_id is not null and new.entry_id is distinct from old.entry_id then raise exception 'already_converted: the linked form cannot be changed'; end if;
  if old.converted_at is not null and new.converted_at is distinct from old.converted_at then raise exception 'already_converted: the conversion cannot be changed'; end if;
  new.updated_at := now();
  return new;
end $$;

-- a quote that was sent keeps its items, prices and validity; only its status and the answer can change
create or replace function public._crmg_quotes_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - a quote is replaced by a new version'; end if;
  if old.status <> 'draft' and (new.items, new.subtotal, new.discount, new.total, new.valid_until, new.version, new.lead_id) is distinct from (old.items, old.subtotal, old.discount, old.total, old.valid_until, old.version, old.lead_id) then
    raise exception 'quote_sent: a sent quote cannot be changed - make a new version';
  end if;
  return new;
end $$;

create or replace function public._crmg_tasks_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - skip the task with a reason instead'; end if;
  if old.status <> 'open' and (new.title, new.due_at, new.assigned_to, new.kind, new.lead_id, new.customer_id, new.order_id) is distinct from (old.title, old.due_at, old.assigned_to, old.kind, old.lead_id, old.customer_id, old.order_id) then
    raise exception 'task_closed: a done or skipped task cannot be changed';
  end if;
  if old.status <> 'open' and new.status is distinct from old.status then raise exception 'task_closed: a done or skipped task cannot be reopened'; end if;
  new.updated_at := now();
  return new;
end $$;

do $t$ declare t text; begin
  foreach t in array array['crm_leads', 'crm_lead_events', 'crm_lead_quotes', 'crm_tasks', 'crm_task_events', 'crm_lead_lists'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['crm_lead_events', 'crm_task_events'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro', t);
    execute format('create trigger %I before update on public.%I for each row execute function public._crmg_append_only()', t || '_ro', t);
  end loop;
  foreach t in array array['crm_leads', 'crm_lead_quotes', 'crm_tasks', 'crm_lead_lists'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, case when t = 'crm_lead_lists' then 'kind,code' else 'id' end);
  end loop;
end $t$;
drop trigger if exists crm_leads_guard on public.crm_leads;
create trigger crm_leads_guard before update on public.crm_leads for each row execute function public._crmg_leads_guard();
drop trigger if exists crm_lead_quotes_guard on public.crm_lead_quotes;
create trigger crm_lead_quotes_guard before update on public.crm_lead_quotes for each row execute function public._crmg_quotes_guard();
drop trigger if exists crm_tasks_guard on public.crm_tasks;
create trigger crm_tasks_guard before update on public.crm_tasks for each row execute function public._crmg_tasks_guard();

-- ============================================================================
-- 7. HELPERS (closed to browsers)
-- ============================================================================
create or replace function public._crmg_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid() $$;
create or replace function public._crmg_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._crmg_lead_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_lead_on') $$;
create or replace function public._crmg_task_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_task_on') $$;
create or replace function public._crmg_reason(p text) returns text language plpgsql immutable as $$
begin
  if p is null or char_length(btrim(p)) < 3 then raise exception 'reason_required: write a reason (at least 3 letters)'; end if;
  return left(btrim(p), 300);
end $$;
-- can this person work at this outlet? (owner, head office role, or listed for the outlet)
create or replace function public._crmg_user_at(p_user uuid, p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p_user and status = 'active') and (
    exists (select 1 from public.user_roles where user_id = p_user and role_code in ('owner', 'management'))
    or exists (select 1 from public.user_locations where user_id = p_user and location_id = p_loc)) $$;
-- who may see / work on a lead: owner, holders of crm_lead_all, else only inside own outlets as assignee, maker, or holder of crm_lead_manage
create or replace function public._crmg_lead_vis(p_loc int, p_owner uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all')
    or (public.can_loc(p_loc) and (p_owner = auth.uid() or p_created = auth.uid() or public.has_grant('crm_lead_manage', p_loc)))) $$;
-- a manager of the outlet: owner, crm_lead_all, or crm_lead_manage inside an outlet the person works in
create or replace function public._crmg_lead_mgr(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all') or (public.can_loc(p_loc) and public.has_grant('crm_lead_manage', p_loc))) $$;
create or replace function public._crmg_can_create(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all')
    or (public.can_loc(p_loc) and (public.has_grant('crm_lead_manage', p_loc) or public.can_do('POS', 'enter') or public.can_do('20-4', 'enter') or public.can_do('20-1', 'enter')))) $$;
-- phone shown to the caller: masked only when the privacy guard of the customer package exists and is ON (setting crm_pii_guard_on, not owned here)
create or replace function public._crmg_phone(p text, p_owner uuid) returns text language sql stable security definer set search_path = public as $$
  select case when p is null then null
              when public.rule_on('crm_pii_guard_on') and not (public.is_owner() or public.has_grant('crm_contact_view') or p_owner = auth.uid())
                then left(p, 3) || repeat('*', greatest(char_length(p) - 5, 1)) || right(p, 2)
              else p end $$;
create or replace function public._crmg_ev(p_lead uuid, p_kind text, p_from text, p_to text, p_note text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_lead_events (lead_id, by_user, by_staff, kind, from_stage, to_stage, note, detail)
    values (p_lead, auth.uid(), public._crmg_staff(), p_kind, p_from, p_to, left(nullif(btrim(p_note), ''), 1000), p_detail);
  update public.crm_leads set last_activity_at = now() where id = p_lead and p_kind <> 'edited';
end $$;
create or replace function public._crmg_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), public._crmg_staff(), p_action, p_table, p_id, p_detail);
end $$;
create or replace function public._crmg_exc(p_kind text, p_amount numeric, p_src_id text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user) values (p_kind, 'crm', p_amount, 'crm_leads', left(p_src_id, 120), left(p_reason, 300), auth.uid());
  perform public._crmg_audit('exception', 'crm_leads', p_src_id, jsonb_build_object('kind', p_kind, 'reason', left(p_reason, 300)));
end $$;
create or replace function public._crmg_list_ok(p_kind text, p_code text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.crm_lead_lists where kind = p_kind and code = p_code and active) $$;

-- ============================================================================
-- 8. LISTS API
-- ============================================================================
-- the three lists with their active entries (all entries for a person who may edit them)
create or replace function public._crmg_lists(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare can_edit boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  can_edit := public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage'));
  return jsonb_build_object('can_edit', can_edit,
    'lost_reason', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'lost_reason' and (active or (p_all and can_edit))), '[]'::jsonb),
    'source', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'source' and (active or (p_all and can_edit))), '[]'::jsonb),
    'occasion', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'occasion' and (active or (p_all and can_edit))), '[]'::jsonb));
end $$;

-- add a new entry, rename, retire or bring back (p_active). Who: the owner; or, when the owner set crm_lead_list_add_mode = manager, a holder of crm_lead_manage.
create or replace function public._crmg_list_save(p_kind text, p_code text, p_label text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text := lower(btrim(coalesce(p_code, ''))); l text := btrim(coalesce(p_label, '')); r public.crm_lead_lists; srt int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage'))) then raise exception 'not allowed'; end if;
  if p_kind not in ('lost_reason', 'source', 'occasion') then raise exception 'bad_list'; end if;
  if c !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code: use 2 to 31 small letters, digits or _'; end if;
  if char_length(l) not between 1 and 60 then raise exception 'bad_label'; end if;
  select * into r from public.crm_lead_lists where kind = p_kind and code = c for update;
  if found then
    if c = 'other' and not coalesce(p_active, true) then raise exception 'other_stays: the entry Other can never be removed'; end if;
    update public.crm_lead_lists set label = l, active = coalesce(p_active, true) where kind = p_kind and code = c;
    return jsonb_build_object('kind', p_kind, 'code', c, 'updated', true);
  end if;
  select coalesce(max(sort), 0) into srt from public.crm_lead_lists where kind = p_kind and code <> 'other' and sort < 900;
  insert into public.crm_lead_lists (kind, code, label, active, sort, created_by) values (p_kind, c, l, coalesce(p_active, true), srt + 10, auth.uid());
  return jsonb_build_object('kind', p_kind, 'code', c, 'created', true);
end $$;

-- ============================================================================
-- 9. PRIVILEGES: the API is open to signed-in users (each function checks the right itself); helpers are closed to browsers.
--    _crmg_lock(all names of THIS file, API names of THIS file) touches only the names it is given, so pasting one file never changes another file's grants.
-- ============================================================================
create or replace function public._crmg_lock(p_all text[], p_api text[]) returns void language plpgsql set search_path = public as $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (p_all) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (p_api) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
revoke all on function public._crmg_lock(text[], text[]) from public, anon, authenticated;
select public._crmg_lock(array['_crmg_present', '_crmg_add_exc_kinds', '_crmg_append_only', '_crmg_stage_ok', '_crmg_leads_guard', '_crmg_quotes_guard', '_crmg_tasks_guard', '_crmg_staff', '_crmg_today',
  '_crmg_lead_on', '_crmg_task_on', '_crmg_reason', '_crmg_user_at', '_crmg_lead_vis', '_crmg_lead_mgr', '_crmg_can_create', '_crmg_phone', '_crmg_ev', '_crmg_audit', '_crmg_exc', '_crmg_list_ok',
  '_crmg_lists', '_crmg_list_save'], array['_crmg_lists', '_crmg_list_save']);

-- ---------------------------------------------------------------- phase324.sql
-- Phase 324 (bos324, package CRM-G label 124, part 2 of 5) - LEADS: SAVE, NOTES, ASSIGN, STAGE MOVES, LOST WITH A REASON, REOPEN WITH A REASON, QUOTES.
-- Paste AFTER phase323. Paste-twice safe. Nothing here posts to the books: no journal, sale, payment or stock line is written; a quote is a priced list, not an invoice.
-- Rights: see phase323 (a lead is visible to the owner, to crm_lead_all, and otherwise only inside the outlets of the person as assignee, maker or crm_lead_manage).
-- Every function answers module_off while the switch crm_lead_on is OFF (default), and refuses a person without the right on the SERVER (a hidden button is also a refused request).

do $g$ begin
  if to_regprocedure('public._crmg_present()') is null or to_regclass('public.crm_leads') is null then raise exception 'phase324 needs phase323 first'; end if;
end $g$;

-- ============================================================================
-- 1. HELPERS
-- ============================================================================
-- a phone number as typed: a Bangladesh mobile is normalised (01XXXXXXXXX); any other number (a landline, a foreign number) is kept as digits and +
create or replace function public._crmg_norm_phone(p text) returns text language plpgsql immutable as $$
declare d text;
begin
  if p is null or btrim(p) = '' then return null; end if;
  begin return public.norm_mobile(p); exception when others then null; end;
  d := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9+]', '', 'g');
  if char_length(d) not between 6 and 20 or p ~ '[A-Za-z]' then raise exception 'bad_phone: the phone number is not valid'; end if;
  return d;
end $$;

-- may the caller work on this lead (not only see it)
create or replace function public._crmg_can_act(p_loc int, p_owner uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._crmg_lead_mgr(p_loc) or (public.can_loc(p_loc) and (p_owner = auth.uid() or p_created = auth.uid()))) $$;

-- load a lead the caller may see, locked for update; the answer for an unseen lead is the same as for a missing one (no hint that another outlet has it)
create or replace function public._crmg_lead_load(p_id uuid, p_lock boolean default true) returns public.crm_leads
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then raise exception 'module_off: enquiry tracking is switched off'; end if;
  if p_lock then select * into l from public.crm_leads where id = p_id for update; else select * into l from public.crm_leads where id = p_id; end if;
  if not found or not public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) then raise exception 'not_found'; end if;
  return l;
end $$;

-- open follow-up tasks of a lead are replaced by one task for the new date (only when tasks are switched on); nothing happens while crm_task_on is OFF
create or replace function public._crmg_lead_task_sync(p_lead uuid, p_due timestamptz, p_title text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; t uuid; r record;
begin
  if not public._crmg_task_on() then return null; end if;
  select * into l from public.crm_leads where id = p_lead;
  if not found then return null; end if;
  for r in select id from public.crm_tasks where lead_id = p_lead and source = 'lead' and kind = 'follow_up' and status = 'open' for update loop
    update public.crm_tasks set status = 'skipped', skip_reason = 'replaced by a new follow-up date', done_by = null where id = r.id;
    insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (r.id, auth.uid(), public._crmg_staff(), 'skipped', 'replaced by a new follow-up date');
  end loop;
  if p_due is null then return null; end if;
  insert into public.crm_tasks (location_id, customer_id, lead_id, kind, title, due_at, assigned_to, source, created_by)
    values (l.location_id, l.customer_id, l.id, 'follow_up', left(coalesce(nullif(btrim(p_title), ''), 'Follow up: ' || l.contact_name), 120), p_due, l.owner_user, 'lead', auth.uid()) returning id into t;
  insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (t, auth.uid(), public._crmg_staff(), 'created', 'made from the enquiry follow-up date');
  return t;
end $$;

-- the open lead tasks end when the lead is closed
create or replace function public._crmg_lead_tasks_close(p_lead uuid, p_why text) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from public.crm_tasks where lead_id = p_lead and source = 'lead' and status = 'open' for update loop
    update public.crm_tasks set status = 'skipped', skip_reason = p_why where id = r.id;
    insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (r.id, auth.uid(), public._crmg_staff(), 'skipped', p_why);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ============================================================================
-- 2. SAVE (create or edit). p_data keys: contact_name, contact_phone, customer_id, source, occasion, event_date, guests, est_value, owner_user, next_follow_up,
--    note, inbound_message_id, quote_ref, make_task. On an edit only the keys that are present change. Idempotent on p_client.
-- ============================================================================
create or replace function public._crmg_lead_save(p_id uuid, p_client uuid, p_loc int, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); l public.crm_leads; loc int; nm text; ph text; cust uuid; own uuid; nfu timestamptz; ev date; gs int; est numeric; src text; occ text; nt text; qr text;
        msg bigint; m public.inbound_messages; c public.customers; dups jsonb; changed text[] := '{}'; mob text; is_new boolean := p_id is null;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then raise exception 'module_off: enquiry tracking is switched off'; end if;
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if is_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into l from public.crm_leads where created_by = auth.uid() and client_id = p_client;
      if found then return jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'stage', l.stage, 'dup', true); end if;
    end if;
    loc := p_loc;
    if loc is null or not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'location_required'; end if;
    if not public._crmg_can_create(loc) then raise exception 'not allowed'; end if;
  else
    l := public._crmg_lead_load(p_id, true);
    loc := l.location_id;
    if not public._crmg_can_act(loc, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
    if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot be edited'; end if;
  end if;

  -- customer (an existing record only; a lead never creates a customer)
  cust := case when d ? 'customer_id' then nullif(d->>'customer_id', '')::uuid else l.customer_id end;
  if cust is not null then
    select * into c from public.customers where id = cust;
    if not found then raise exception 'customer_not_found'; end if;
  end if;
  nm := case when d ? 'contact_name' then left(btrim(coalesce(d->>'contact_name', '')), 80) else l.contact_name end;
  ph := case when d ? 'contact_phone' then public._crmg_norm_phone(d->>'contact_phone') else l.contact_phone end;
  -- an enquiry from the inbox: fill what is blank from the message; one message belongs to one enquiry
  msg := case when d ? 'inbound_message_id' then nullif(d->>'inbound_message_id', '')::bigint else l.inbound_message_id end;
  if msg is not null and msg is distinct from l.inbound_message_id then
    select * into m from public.inbound_messages where id = msg;
    if not found or not public.can_loc(m.location_id) then raise exception 'message_not_found'; end if;
    if m.location_id <> loc then raise exception 'message_other_outlet'; end if;
    if exists (select 1 from public.crm_leads x where x.inbound_message_id = msg) then raise exception 'message_already_tracked: this message already has an enquiry'; end if;
    if coalesce(nm, '') = '' then nm := left(btrim(coalesce(m.customer_name, '')), 80); end if;
  end if;
  if coalesce(nm, '') = '' and c.id is not null then nm := left(c.name, 80); end if;
  if coalesce(btrim(nm), '') = '' then raise exception 'contact_name_required'; end if;
  if cust is null and ph is not null then          -- link the customer who owns this exact mobile, if there is one
    begin mob := public.norm_mobile(ph); select id into cust from public.customers where mobile = mob; exception when others then null; end;
  end if;
  src := case when d ? 'source' then nullif(btrim(d->>'source'), '') else l.source end;
  if src is not null and not public._crmg_list_ok('source', src) then raise exception 'unknown_source'; end if;
  occ := case when d ? 'occasion' then nullif(btrim(d->>'occasion'), '') else l.occasion end;
  if occ is not null and not public._crmg_list_ok('occasion', occ) then raise exception 'unknown_occasion'; end if;
  begin ev := case when d ? 'event_date' then nullif(d->>'event_date', '')::date else l.event_date end; exception when others then raise exception 'bad_date'; end;
  begin gs := case when d ? 'guests' then nullif(d->>'guests', '')::int else l.guests end; exception when others then raise exception 'bad_guests'; end;
  if gs is not null and gs not between 1 and 100000 then raise exception 'bad_guests'; end if;
  begin est := case when d ? 'est_value' then nullif(d->>'est_value', '')::numeric else l.est_value end; exception when others then raise exception 'bad_amount'; end;
  if est is not null and (est = 'NaN'::numeric or est < 0 or est > 1000000000000) then raise exception 'bad_amount'; end if;
  begin nfu := case when d ? 'next_follow_up' then nullif(d->>'next_follow_up', '')::timestamptz else l.next_follow_up end; exception when others then raise exception 'bad_follow_up'; end;
  if nfu is not null and nfu > now() + interval '2 years' then raise exception 'bad_follow_up'; end if;
  nt := case when d ? 'note' then left(nullif(btrim(d->>'note'), ''), 300) else l.note end;
  qr := case when d ? 'quote_ref' then left(nullif(btrim(d->>'quote_ref'), ''), 80) else l.quote_ref end;
  own := case when d ? 'owner_user' and nullif(d->>'owner_user', '') is not null then (d->>'owner_user')::uuid else coalesce(l.owner_user, auth.uid()) end;
  if own is distinct from coalesce(l.owner_user, auth.uid()) or (is_new and own <> auth.uid()) then
    if not public._crmg_lead_mgr(loc) then raise exception 'not allowed: only a manager can give an enquiry to someone else'; end if;
    if not public._crmg_user_at(own, loc) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  end if;

  if is_new then
    insert into public.crm_leads (client_id, location_id, customer_id, contact_name, contact_phone, source, inbound_message_id, occasion, event_date, guests, est_value, owner_user,
        next_follow_up, quote_ref, note, created_by)
      values (p_client, loc, cust, btrim(nm), ph, src, msg, occ, ev, gs, est, own, nfu, qr, nt, auth.uid()) returning * into l;
    perform public._crmg_ev(l.id, 'created', null, 'enquiry', nt, jsonb_build_object('lead_no', l.lead_no, 'source', src, 'occasion', occ, 'owner_user', own));
    if msg is not null then
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) select msg, status, status, 'tracked as enquiry ' || l.lead_no, auth.uid() from public.inbound_messages where id = msg;
    end if;
  else
    if nm is distinct from l.contact_name then changed := changed || 'contact_name'::text; end if;
    if ph is distinct from l.contact_phone then changed := changed || 'contact_phone'::text; end if;
    if cust is distinct from l.customer_id then changed := changed || 'customer_id'::text; end if;
    if src is distinct from l.source then changed := changed || 'source'::text; end if;
    if occ is distinct from l.occasion then changed := changed || 'occasion'::text; end if;
    if ev is distinct from l.event_date then changed := changed || 'event_date'::text; end if;
    if gs is distinct from l.guests then changed := changed || 'guests'::text; end if;
    if est is distinct from l.est_value then changed := changed || 'est_value'::text; end if;
    if nfu is distinct from l.next_follow_up then changed := changed || 'next_follow_up'::text; end if;
    if own is distinct from l.owner_user then changed := changed || 'owner_user'::text; end if;
    if msg is distinct from l.inbound_message_id then changed := changed || 'inbound_message_id'::text; end if;
    update public.crm_leads set contact_name = btrim(nm), contact_phone = ph, customer_id = cust, source = src, occasion = occ, event_date = ev, guests = gs, est_value = est,
        owner_user = own, next_follow_up = nfu, quote_ref = qr, note = nt, inbound_message_id = msg where id = l.id returning * into l;
    if cardinality(changed) > 0 then
      perform public._crmg_ev(l.id, case when 'owner_user' = any (changed) then 'assign' else 'edited' end, l.stage, l.stage, null, jsonb_build_object('changed', changed));
    end if;
  end if;

  if coalesce((d->>'make_task')::boolean, false) and l.next_follow_up is not null and (is_new or 'next_follow_up' = any (changed)) then
    perform public._crmg_lead_task_sync(l.id, l.next_follow_up);
  end if;
  select coalesce(jsonb_agg(x.id), '[]'::jsonb) into dups from public.crm_leads x
    where x.id <> l.id and x.location_id = l.location_id and x.stage not in ('won', 'lost') and l.contact_phone is not null and x.contact_phone = l.contact_phone;
  return jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'stage', l.stage, 'customer_id', l.customer_id, 'same_phone_open_leads', dups);
end $$;

-- ============================================================================
-- 3. NOTES (call, visit, message, note) and ASSIGN
-- ============================================================================
create or replace function public._crmg_lead_note(p_lead uuid, p_kind text, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; k text := coalesce(nullif(btrim(p_kind), ''), 'note'); b text := btrim(coalesce(p_body, ''));
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if k not in ('call', 'visit', 'message', 'note') then raise exception 'bad_note_kind'; end if;
  if char_length(b) not between 1 and 1000 then raise exception 'note_required: write 1 to 1000 letters'; end if;
  perform public._crmg_ev(l.id, 'note', l.stage, l.stage, b, jsonb_build_object('activity', k));
  return jsonb_build_object('id', l.id, 'noted', true);
end $$;

create or replace function public._crmg_lead_assign(p_lead uuid, p_user uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; n int;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can give an enquiry to someone else'; end if;
  if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot be given to someone else'; end if;
  if p_user is null or not public._crmg_user_at(p_user, l.location_id) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  if p_user = l.owner_user then return jsonb_build_object('id', l.id, 'noop', true); end if;
  update public.crm_leads set owner_user = p_user where id = l.id;
  update public.crm_tasks set assigned_to = p_user where lead_id = l.id and source = 'lead' and status = 'open';
  get diagnostics n = row_count;
  perform public._crmg_ev(l.id, 'assign', l.stage, l.stage, p_reason, jsonb_build_object('from', l.owner_user, 'to', p_user, 'tasks_moved', n));
  return jsonb_build_object('id', l.id, 'owner_user', p_user, 'tasks_moved', n);
end $$;

-- ============================================================================
-- 4. STAGE MOVES
--    p_args: lost_reason (code from the list), follow_up (timestamp), make_task (boolean), reason (only to win without a quote, manager, an exception)
-- ============================================================================
create or replace function public._crmg_lead_stage(p_lead uuid, p_to text, p_note text default null, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; a jsonb := coalesce(p_args, '{}'::jsonb); lr text; fu timestamptz; has_q boolean; why text; closed_tasks int := 0; old_stage text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if p_to not in ('enquiry', 'quoted', 'following_up', 'won', 'lost') then raise exception 'bad_stage'; end if;
  if l.stage = p_to then return jsonb_build_object('id', l.id, 'stage', l.stage, 'noop', true); end if;
  if l.stage = 'lost' then raise exception 'illegal_stage_move: a lost enquiry can only be reopened (with a reason)'; end if;
  if l.stage = 'won' then raise exception 'illegal_stage_move: a won enquiry is final'; end if;
  if not public._crmg_stage_ok(l.stage, p_to) then raise exception 'illegal_stage_move: % to % is not allowed', l.stage, p_to; end if;
  select exists (select 1 from public.crm_lead_quotes where lead_id = l.id and status in ('sent', 'accepted')) into has_q;
  begin fu := nullif(a->>'follow_up', '')::timestamptz; exception when others then raise exception 'bad_follow_up'; end;

  if p_to = 'quoted' and not has_q then raise exception 'quote_needed: send a quote first (the quote moves the enquiry to Quoted by itself)'; end if;
  if p_to = 'won' and not has_q and public.rule_on('crm_lead_win_needs_quote') then
    if not public._crmg_lead_mgr(l.location_id) then raise exception 'quote_needed_to_win: a sent quote is needed first'; end if;
    why := public._crmg_reason(a->>'reason');
    perform public._crmg_exc('crmg_win_without_quote', l.est_value, l.id::text, why);
  end if;
  if p_to = 'lost' then
    if public.rule_txt('crm_lead_lost_by') is distinct from 'assignee' and not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can close an enquiry as lost'; end if;
    lr := nullif(btrim(a->>'lost_reason'), '');
    if lr is null or not public._crmg_list_ok('lost_reason', lr) then raise exception 'lost_reason_required: choose a lost reason from the list'; end if;
    if lr = 'other' and char_length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'lost_note_required: write a few words when the reason is Other'; end if;
  end if;

  old_stage := l.stage;
  update public.crm_leads set stage = p_to,
      lost_reason = case when p_to = 'lost' then lr else null end,
      lost_note = case when p_to = 'lost' then left(nullif(btrim(p_note), ''), 300) else null end,
      next_follow_up = case when p_to in ('won', 'lost') then null when fu is not null then fu else next_follow_up end
    where id = l.id returning * into l;
  perform public._crmg_ev(l.id, 'stage', old_stage, p_to, p_note, jsonb_strip_nulls(jsonb_build_object('lost_reason', lr, 'follow_up', fu, 'exception_reason', why)));
  if p_to in ('won', 'lost') then
    closed_tasks := public._crmg_lead_tasks_close(l.id, case when p_to = 'won' then 'the enquiry was won' else 'the enquiry was closed as lost' end);
    if p_to = 'won' then
      update public.crm_lead_quotes set status = 'accepted', responded_at = now() where id = (select id from public.crm_lead_quotes where lead_id = l.id and status = 'sent' order by version desc limit 1);
    else
      update public.crm_lead_quotes set status = 'declined', responded_at = now() where lead_id = l.id and status = 'sent';
    end if;
  elsif fu is not null and coalesce((a->>'make_task')::boolean, false) then
    perform public._crmg_lead_task_sync(l.id, fu);
  end if;
  return jsonb_build_object('id', l.id, 'stage', l.stage, 'tasks_closed', closed_tasks);
end $$;

-- reopen a lost enquiry. An exception: needs a written reason, goes to the Exceptions list, setting crm_lead_reopen_mode decides who may (reason / owner / off)
create or replace function public._crmg_lead_reopen(p_lead uuid, p_reason text, p_to text default 'enquiry') returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; mode text := coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason'); why text; old_reason text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if mode = 'off' then raise exception 'reopen_off: reopening is switched off - start a new enquiry'; end if;
  if mode = 'owner' then if not public.is_owner() then raise exception 'not allowed: only the owner can reopen a lost enquiry'; end if;
  elsif not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can reopen a lost enquiry'; end if;
  if l.stage <> 'lost' then raise exception 'not_lost: only a lost enquiry can be reopened'; end if;
  if p_to not in ('enquiry', 'following_up') then raise exception 'bad_stage'; end if;
  why := public._crmg_reason(p_reason);
  old_reason := l.lost_reason;
  perform set_config('crmg.reopen', '1', true);
  update public.crm_leads set stage = p_to, lost_reason = null, lost_note = null, reopened_count = reopened_count + 1 where id = l.id returning * into l;
  perform set_config('crmg.reopen', '', true);
  insert into public.crm_lead_events (lead_id, by_user, by_staff, kind, from_stage, to_stage, note, detail)
    values (l.id, auth.uid(), public._crmg_staff(), 'reopen', 'lost', p_to, why, jsonb_build_object('was_lost_because', old_reason));
  perform public._crmg_exc('crmg_lead_reopen', l.est_value, l.id::text, why);
  return jsonb_build_object('id', l.id, 'stage', l.stage, 'reopened', l.reopened_count);
end $$;

-- ============================================================================
-- 5. QUOTES (items, validity). A quote is a priced list; it is not an invoice and posts nothing.
--    p_data: quote_id (edit this draft), items [{item_id?, desc?, unit?, qty, price?}], discount, valid_until, note, late_reason, send (boolean)
-- ============================================================================
create or replace function public._crmg_quote_items(p_items jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e jsonb; it public.items; out jsonb := '[]'; q numeric; pr numeric; dsc text; sub numeric := 0; n int := 0; iid uuid;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'no_items: add at least one line'; end if;
  for e in select * from jsonb_array_elements(p_items) loop
    n := n + 1;
    iid := null; it := null;
    begin iid := nullif(e->>'item_id', '')::uuid; exception when others then raise exception 'item_not_found'; end;
    if iid is not null then
      select * into it from public.items where id = iid and is_active;
      if not found then raise exception 'item_not_found'; end if;
    end if;
    dsc := left(nullif(btrim(coalesce(e->>'desc', '')), ''), 160);
    if iid is null and dsc is null then raise exception 'line_needs_item_or_description'; end if;
    begin q := (e->>'qty')::numeric; exception when others then raise exception 'bad_qty'; end;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    begin pr := nullif(e->>'price', '')::numeric; exception when others then raise exception 'bad_price'; end;
    if pr is null and iid is not null then pr := it.sell_price; end if;
    if pr is null then raise exception 'price_required: write the price of line %', n; end if;
    if pr = 'NaN'::numeric or pr < 0 or pr > 1000000000 then raise exception 'bad_price'; end if;
    out := out || jsonb_build_object('item_id', iid, 'code', it.code, 'desc', coalesce(dsc, coalesce(it.name_en, it.name_bn)), 'unit', left(nullif(btrim(coalesce(e->>'unit', it.unit, '')), ''), 20),
                                     'qty', q, 'price', round(pr, 2), 'amount', round(q * pr, 2));
    sub := sub + round(q * pr, 2);
  end loop;
  return jsonb_build_object('items', out, 'subtotal', sub);
end $$;

create or replace function public._crmg_quote_save(p_lead uuid, p_client uuid, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); l public.crm_leads; qq public.crm_lead_quotes; norm jsonb; sub numeric; dsc numeric; vu date; send boolean := coalesce((d->>'send')::boolean, false);
        ver int; late boolean := false; lr text; minlead numeric := public.rule_num('crm_quote_min_lead_days'); defdays numeric := public.rule_num('crm_lead_quote_valid_days'); qid uuid := nullif(d->>'quote_id', '')::uuid;
        new_stage text;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if l.stage in ('won', 'lost') then raise exception 'lead_closed: a won or lost enquiry cannot get a new quote'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into qq from public.crm_lead_quotes where created_by = auth.uid() and client_id = p_client;
    if found then return jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'status', qq.status, 'total', qq.total, 'dup', true); end if;
  end if;
  norm := public._crmg_quote_items(d->'items'); sub := (norm->>'subtotal')::numeric;
  begin dsc := coalesce(nullif(d->>'discount', '')::numeric, 0); exception when others then raise exception 'bad_amount'; end;
  if dsc = 'NaN'::numeric or dsc < 0 or dsc > sub then raise exception 'bad_discount: the discount cannot be more than the total of the lines'; end if;
  begin vu := nullif(d->>'valid_until', '')::date; exception when others then raise exception 'bad_date'; end;
  if vu is null and send and defdays is not null then vu := public._crmg_today() + defdays::int; end if;
  if send and vu is null then raise exception 'validity_required: write the date until which the quote is valid'; end if;
  lr := left(nullif(btrim(d->>'late_reason'), ''), 300);
  if send then
    late := (vu < public._crmg_today()) or (minlead is not null and l.event_date is not null and (l.event_date - public._crmg_today()) < minlead);
    if late then
      lr := public._crmg_reason(lr);
      perform public._crmg_exc('crmg_late_quote', sub - dsc, l.id::text, lr);
    end if;
  end if;
  if qid is not null then
    select * into qq from public.crm_lead_quotes where id = qid and lead_id = l.id for update;
    if not found then raise exception 'not_found'; end if;
    if qq.status <> 'draft' then raise exception 'quote_sent: a sent quote cannot be changed - make a new version'; end if;
    update public.crm_lead_quotes set items = norm->'items', subtotal = sub, discount = dsc, total = sub - dsc, valid_until = vu, note = left(nullif(btrim(d->>'note'), ''), 300),
        late_reason = case when late then lr else null end, client_id = coalesce(client_id, p_client) where id = qq.id returning * into qq;
  else
    select coalesce(max(version), 0) + 1 into ver from public.crm_lead_quotes where lead_id = l.id;
    insert into public.crm_lead_quotes (lead_id, version, client_id, items, subtotal, discount, total, valid_until, note, late_reason, created_by)
      values (l.id, ver, p_client, norm->'items', sub, dsc, sub - dsc, vu, left(nullif(btrim(d->>'note'), ''), 300), case when late then lr else null end, auth.uid()) returning * into qq;
  end if;
  if send then
    update public.crm_lead_quotes set status = 'superseded' where lead_id = l.id and id <> qq.id and status in ('draft', 'sent');
    update public.crm_lead_quotes set status = 'sent', sent_at = now() where id = qq.id returning * into qq;
    new_stage := case when l.stage in ('enquiry', 'following_up') then 'quoted' else l.stage end;
    update public.crm_leads set stage = new_stage, est_value = coalesce(est_value, qq.total) where id = l.id returning * into l;
    perform public._crmg_ev(l.id, 'quote', null, l.stage, d->>'note', jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'total', qq.total, 'valid_until', qq.valid_until, 'late', late));
  else
    perform public._crmg_ev(l.id, 'quote', l.stage, l.stage, 'draft saved', jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'total', qq.total, 'draft', true));
  end if;
  return jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'status', qq.status, 'total', qq.total, 'valid_until', qq.valid_until, 'stage', l.stage);
end $$;

create or replace function public._crmg_quote_respond(p_quote uuid, p_result text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare qq public.crm_lead_quotes; l public.crm_leads;
begin
  select * into qq from public.crm_lead_quotes where id = p_quote for update;
  if not found then raise exception 'not_found'; end if;
  l := public._crmg_lead_load(qq.lead_id, true);
  if not public._crmg_can_act(l.location_id, l.owner_user, l.created_by) then raise exception 'not allowed'; end if;
  if p_result not in ('accepted', 'declined') then raise exception 'bad_result'; end if;
  if qq.status = p_result then return jsonb_build_object('quote_id', qq.id, 'status', qq.status, 'noop', true); end if;
  if qq.status <> 'sent' then raise exception 'quote_not_sent: only a sent quote can be answered'; end if;
  update public.crm_lead_quotes set status = p_result, responded_at = now(), response_note = left(nullif(btrim(p_note), ''), 300) where id = qq.id;
  perform public._crmg_ev(l.id, 'quote', l.stage, l.stage, p_note, jsonb_build_object('quote_id', qq.id, 'version', qq.version, 'answer', p_result));
  return jsonb_build_object('quote_id', qq.id, 'status', p_result);
end $$;

-- ============================================================================
-- 6. ONE LEAD WITH ITS QUOTES, TRAIL AND OPEN TASKS (the lead sheet)
-- ============================================================================
create or replace function public._crmg_lead_get(p_lead uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.crm_leads; sale_ok boolean; mgr boolean; act boolean; stale numeric := public.rule_num('crm_lead_stale_days'); cn text; ow text;
begin
  l := public._crmg_lead_load(p_lead, false);
  mgr := public._crmg_lead_mgr(l.location_id); act := public._crmg_can_act(l.location_id, l.owner_user, l.created_by);
  select name into cn from public.customers where id = l.customer_id;
  select staff_id into ow from public.profiles where id = l.owner_user;
  return jsonb_build_object(
    'lead', jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'location_id', l.location_id, 'customer_id', l.customer_id, 'customer_name', cn, 'contact_name', l.contact_name,
        'contact_phone', public._crmg_phone(l.contact_phone, l.owner_user), 'source', l.source, 'occasion', l.occasion, 'event_date', l.event_date, 'guests', l.guests, 'est_value', l.est_value,
        'stage', l.stage, 'lost_reason', l.lost_reason, 'lost_note', l.lost_note, 'owner_user', l.owner_user, 'owner_staff', ow, 'next_follow_up', l.next_follow_up, 'quote_ref', l.quote_ref,
        'online_order_id', l.online_order_id, 'entry_id', l.entry_id, 'converted_at', l.converted_at, 'reopened_count', l.reopened_count, 'note', l.note, 'stage_at', l.stage_at,
        'last_activity_at', l.last_activity_at, 'created_at', l.created_at, 'inbound_message_id', l.inbound_message_id,
        'overdue', l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now(),
        'stale', l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'version', q.version, 'status', q.status, 'expired', q.status = 'sent' and q.valid_until < public._crmg_today(), 'valid_until', q.valid_until,
        'items', q.items, 'subtotal', q.subtotal, 'discount', q.discount, 'total', q.total, 'note', q.note, 'late_reason', q.late_reason, 'sent_at', q.sent_at, 'responded_at', q.responded_at) order by q.version desc)
        from public.crm_lead_quotes q where q.lead_id = l.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'kind', z.kind, 'from', z.from_stage, 'to', z.to_stage, 'note', z.note, 'by', z.by_staff, 'detail', z.detail) order by z.id desc)
        from (select * from public.crm_lead_events e where e.lead_id = l.id order by e.id desc limit 200) z), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'kind', t.kind, 'due_at', t.due_at, 'snooze_until', t.snooze_until, 'assigned_to', t.assigned_to, 'status', t.status) order by t.due_at)
        from public.crm_tasks t where t.lead_id = l.id and t.status = 'open'), '[]'::jsonb),
    'can', jsonb_build_object('edit', act and l.stage not in ('won', 'lost'), 'note', act, 'quote', act and l.stage not in ('won', 'lost'), 'move', act and l.stage not in ('won', 'lost'),
        'assign', mgr and l.stage not in ('won', 'lost'), 'close_lost', l.stage not in ('won', 'lost') and (mgr or (act and public.rule_txt('crm_lead_lost_by') = 'assignee')),
        'reopen', l.stage = 'lost' and coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason') <> 'off' and case when coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason') = 'owner' then public.is_owner() else mgr end,
        'convert', mgr and l.converted_at is null and l.stage <> 'lost'));
end $$;

-- ============================================================================
-- 7. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_norm_phone', '_crmg_can_act', '_crmg_lead_load', '_crmg_lead_task_sync', '_crmg_lead_tasks_close', '_crmg_lead_save', '_crmg_lead_note', '_crmg_lead_assign',
  '_crmg_lead_stage', '_crmg_lead_reopen', '_crmg_quote_items', '_crmg_quote_save', '_crmg_quote_respond', '_crmg_lead_get'],
  array['_crmg_lead_save', '_crmg_lead_note', '_crmg_lead_assign', '_crmg_lead_stage', '_crmg_lead_reopen', '_crmg_quote_save', '_crmg_quote_respond', '_crmg_lead_get']);

-- ---------------------------------------------------------------- phase325.sql
-- Phase 325 (bos325, package CRM-G label 125, part 3 of 5) - CONVERT A WON LEAD TO THE EXISTING ORDER OR PARTY FORM, LEAD LIST, PIPELINE BOARD, WIN / LOSS REPORT.
-- Paste AFTER phase324. Paste-twice safe. Nothing here posts to the books.
--
-- HOW A WON LEAD BECOMES A REAL RECORD (never by copying the accounting of those records):
--   online_order : calls the EXISTING online_order_save2 (phase 76; it calls online_order_save of phase 61). The order is the normal order: stock, advance, delivery,
--                  and the books follow the order's own rules. The quote total becomes the order discount against the list price. No advance is taken here.
--   form_20_1    : calls the EXISTING save_entry to make a DRAFT customer order form (paper form 20-1) filled from the quote. The person completes and submits it as usual.
--   form_20_4    : the same for the party and wholesale invoice (paper form 20-4, "Invoice"). A draft: nothing is posted until the form is approved the usual way.
--   link_order / link_form : link a record that already exists (an order from the Orders screen, a 20-1 or 20-4 entry) instead of making one.
-- One lead converts once. A second conversion is refused (a repeat with the same client key returns the first answer).

do $g$ begin
  if to_regprocedure('public._crmg_lead_stage(uuid,text,text,jsonb)') is null then raise exception 'phase325 needs phase324 first'; end if;
end $g$;

-- ============================================================================
-- 1. CONVERT
--    p_kind: online_order | form_20_1 | form_20_4 | link_order | link_form
--    p_args: quote_id (default: the latest sent or accepted quote), reason (only to win without a quote when that setting is ON),
--            online_order: channel_id (required), delivery_mode (pickup|home|courier, default pickup), delivery_by, delivery_date, address, charge, note
--            link_order: order_id          link_form: entry_id
-- ============================================================================
create or replace function public._crmg_lead_convert(p_lead uuid, p_client uuid, p_kind text, p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare a jsonb := coalesce(p_args, '{}'::jsonb); l public.crm_leads; qq public.crm_lead_quotes; qid uuid; res jsonb := '{}'::jsonb; oid uuid; eid uuid; mob text; lines jsonb := '[]'; rows jsonb := '[]'; e jsonb;
        list_sub numeric := 0; disc numeric; it public.items; ch int; dm text; dd date; addr text; oo public.online_orders; en public.entries; msg bigint; task_days numeric; task_id uuid; cc text;
        form text; dat jsonb; st jsonb; warn text[] := '{}'; n int := 0;
begin
  l := public._crmg_lead_load(p_lead, true);
  if not public._crmg_lead_mgr(l.location_id) then raise exception 'not allowed: only a manager can turn an enquiry into an order'; end if;
  if p_kind not in ('online_order', 'form_20_1', 'form_20_4', 'link_order', 'link_form') then raise exception 'bad_kind'; end if;
  perform public._client_lock(p_client);
  if l.converted_at is not null then
    if p_client is not null and l.convert_client = p_client then
      return jsonb_build_object('id', l.id, 'online_order_id', l.online_order_id, 'entry_id', l.entry_id, 'dup', true);
    end if;
    raise exception 'already_converted: this enquiry already has its order or form';
  end if;
  if l.stage = 'lost' then raise exception 'lead_lost: reopen the enquiry first'; end if;

  -- the quote the record is made from
  qid := nullif(a->>'quote_id', '')::uuid;
  if qid is not null then
    select * into qq from public.crm_lead_quotes where id = qid and lead_id = l.id;
    if not found then raise exception 'not_found: that quote is not on this enquiry'; end if;
  else
    select * into qq from public.crm_lead_quotes where lead_id = l.id and status in ('accepted', 'sent') order by version desc limit 1;
  end if;
  if p_kind in ('online_order', 'form_20_1', 'form_20_4') and qq.id is null then raise exception 'quote_needed: send a quote first - the record is made from its lines'; end if;

  -- the enquiry becomes Won first (the normal stage rules apply, including the setting that asks for a quote)
  if l.stage <> 'won' then
    perform public._crmg_lead_stage(l.id, 'won', 'turned into an order', a);
    select * into l from public.crm_leads where id = l.id;
  end if;

  if p_kind = 'online_order' then
    if nullif(a->>'channel_id', '') is null then raise exception 'channel_required: choose the sales channel of the order'; end if;
    ch := (a->>'channel_id')::int;
    begin mob := public.norm_mobile(l.contact_phone); exception when others then mob := null; end;
    if mob is null then raise exception 'mobile_required: an order needs a valid mobile number on the enquiry'; end if;
    for e in select * from jsonb_array_elements(qq.items) loop
      n := n + 1;
      if nullif(e->>'item_id', '') is null then raise exception 'lines_need_items: line % has no item from the item list - use the party invoice form or link an order', n; end if;
      select * into it from public.items where id = (e->>'item_id')::uuid and is_active;
      if not found or it.sell_price is null then raise exception 'item_not_found: line % has no active item with a list price', n; end if;
      lines := lines || jsonb_build_object('item_id', it.id, 'qty', (e->>'qty')::numeric);
      list_sub := list_sub + round((e->>'qty')::numeric * it.sell_price, 2);
    end loop;
    disc := list_sub - qq.total;
    if disc < 0 then raise exception 'price_above_list: the quote total is above the list price - use the party invoice form or link an order'; end if;
    dm := coalesce(nullif(btrim(a->>'delivery_mode'), ''), 'pickup');
    begin dd := nullif(a->>'delivery_date', '')::date; exception when others then raise exception 'bad_date'; end;
    if dd is null and l.event_date between public._crmg_today() - 1 and public._crmg_today() + 365 then dd := l.event_date; end if;
    addr := nullif(btrim(a->>'address'), '');
    select inbound_message_id into msg from public.crm_leads where id = l.id;
    if msg is not null and not exists (select 1 from public.inbound_messages where id = msg and status in ('new', 'seen')) then msg := null; end if;
    st := public.online_order_save2(null, coalesce(p_client, gen_random_uuid()), l.location_id, ch, l.contact_name, mob, addr, lines, dm, nullif(btrim(a->>'delivery_by'), ''), dd,
            coalesce(nullif(a->>'charge', '')::numeric, 0), round(disc, 2), 0, null, null, coalesce(nullif(btrim(a->>'note'), ''), 'from enquiry ' || l.lead_no),
            null, 'crm_lead ' || l.lead_no, null, null, null, msg, false);
    oid := (st->>'id')::uuid;
    res := res || jsonb_build_object('order_no', st->>'order_no', 'order_status', st->>'status');
    -- optional delivery task for the assigned person (setting crm_order_task_days, tasks must be ON)
    task_days := public.rule_num('crm_order_task_days');
    if task_days is not null and public._crmg_task_on() and dd is not null then
      insert into public.crm_tasks (location_id, customer_id, lead_id, order_id, kind, title, due_at, assigned_to, source, created_by)
        values (l.location_id, l.customer_id, l.id, oid, 'follow_up', left('Delivery of order ' || (st->>'order_no') || ' for ' || l.contact_name, 120),
                ((dd - task_days::int)::text || ' 09:00 Asia/Dhaka')::timestamptz, l.owner_user, 'order', auth.uid()) returning id into task_id;
      insert into public.crm_task_events (task_id, by_user, by_staff, kind, note) values (task_id, auth.uid(), public._crmg_staff(), 'created', 'made when the enquiry became an order');
      res := res || jsonb_build_object('task_id', task_id);
    end if;

  elsif p_kind in ('form_20_1', 'form_20_4') then
    form := case p_kind when 'form_20_1' then '20-1' else '20-4' end;
    if not public.can_do(form, 'enter') then raise exception 'form_not_allowed: you do not hold the right to enter form %', form; end if;
    for e in select * from jsonb_array_elements(qq.items) loop
      if form = '20-4' then
        rows := rows || jsonb_build_object('item', coalesce(e->>'code', ''), 'desc', e->>'desc', 'unit', coalesce(e->>'unit', ''), 'qty', e->>'qty', 'rate', e->>'price');
      else
        rows := rows || jsonb_build_object('item', coalesce(e->>'code', ''), 'desc', e->>'desc', 'qty', e->>'qty');
      end if;
    end loop;
    if form = '20-4' then
      dat := jsonb_build_object('doc', 'invoice', 'party', l.contact_name, 'phone', coalesce(l.contact_phone, ''), 'order_no', 'ENQ-' || l.lead_no, 'lines', rows, 'discount', qq.discount::text);
    else
      dat := jsonb_build_object('order_type', 'custom', 'channel', 'party', 'cust_name', l.contact_name, 'cust_phone', coalesce(l.contact_phone, ''), 'deliv_mode', 'pickup',
        'items', rows, 'total', qq.subtotal::text, 'discount', qq.discount::text);
      if l.event_date is not null then dat := dat || jsonb_build_object('deliv_date', l.event_date::text); end if;
    end if;
    st := public.save_entry(null, form, l.location_id, public._crmg_today(), dat, '[]'::jsonb, 'from enquiry ' || l.lead_no, jsonb_build_object('client_id', coalesce(p_client, gen_random_uuid())));
    eid := (st->>'id')::uuid;
    res := res || jsonb_build_object('form', form, 'serial', st->>'serial', 'draft', true);

  elsif p_kind = 'link_order' then
    begin oid := nullif(a->>'order_id', '')::uuid; exception when others then raise exception 'not_found'; end;
    select * into oo from public.online_orders where id = oid;
    if not found or not public.can_loc(oo.location_id) then raise exception 'not_found'; end if;
    if oo.location_id <> l.location_id then raise exception 'other_outlet: the order belongs to another outlet'; end if;
    if oo.status = 'cancelled' then raise exception 'order_cancelled: a cancelled order cannot be linked'; end if;
    if exists (select 1 from public.crm_leads x where x.online_order_id = oid) then raise exception 'already_linked: this order belongs to another enquiry'; end if;
    begin if public.norm_mobile(l.contact_phone) is distinct from oo.customer_mobile then warn := warn || 'the order has a different mobile number'::text; end if; exception when others then null; end;
    res := res || jsonb_build_object('order_no', oo.order_no, 'order_status', oo.status);

  else   -- link_form
    begin eid := nullif(a->>'entry_id', '')::uuid; exception when others then raise exception 'not_found'; end;
    select * into en from public.entries where id = eid;
    if not found or en.form_code not in ('20-1', '20-4') or not public.can_loc(en.location_id) or not public.can_do(en.form_code, 'view') then raise exception 'not_found'; end if;
    if en.location_id <> l.location_id then raise exception 'other_outlet: the form belongs to another outlet'; end if;
    if exists (select 1 from public.crm_leads x where x.entry_id = eid) then raise exception 'already_linked: this form belongs to another enquiry'; end if;
    res := res || jsonb_build_object('form', en.form_code, 'serial', en.serial, 'form_status', en.status);
  end if;

  begin
    update public.crm_leads set online_order_id = oid, entry_id = eid, converted_at = now(), converted_by = auth.uid(), convert_client = p_client where id = l.id;
  exception when unique_violation then raise exception 'already_linked: this record belongs to another enquiry'; end;
  perform public._crmg_ev(l.id, 'convert', 'won', 'won', null, jsonb_build_object('kind', p_kind, 'order_id', oid, 'entry_id', eid, 'quote_id', qq.id));
  perform public._crmg_audit('convert', 'crm_leads', l.id::text, jsonb_build_object('kind', p_kind, 'order_id', oid, 'entry_id', eid));
  return jsonb_build_object('id', l.id, 'kind', p_kind, 'online_order_id', oid, 'entry_id', eid, 'warnings', to_jsonb(warn)) || res;
end $$;

-- ============================================================================
-- 2. LEAD LIST   p_filter: stage (text or array), loc, owner ('me' or a user id), q (name, phone or number), overdue, stale, converted, from, to (created date), limit (max 300), offset
-- ============================================================================
create or replace function public._crmg_lead_rows(p_filter jsonb) returns table (r jsonb, stage text, loc int)
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := coalesce(p_filter, '{}'::jsonb); stages text[]; own uuid; qtxt text := lower(btrim(coalesce(f->>'q', ''))); stale numeric := public.rule_num('crm_lead_stale_days');
begin
  if jsonb_typeof(f->'stage') = 'array' then select array_agg(x) into stages from jsonb_array_elements_text(f->'stage') x;
  elsif nullif(f->>'stage', '') is not null then stages := array[f->>'stage']; end if;
  own := case when f->>'owner' = 'me' then auth.uid() when nullif(f->>'owner', '') is not null then (f->>'owner')::uuid end;
  return query
    select jsonb_build_object('id', l.id, 'lead_no', l.lead_no, 'location_id', l.location_id, 'contact_name', l.contact_name, 'contact_phone', public._crmg_phone(l.contact_phone, l.owner_user),
        'stage', l.stage, 'source', l.source, 'occasion', l.occasion, 'event_date', l.event_date, 'guests', l.guests, 'est_value', l.est_value, 'owner_user', l.owner_user,
        'owner_staff', (select pr.staff_id from public.profiles pr where pr.id = l.owner_user), 'next_follow_up', l.next_follow_up,
        'overdue', l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now(),
        'stale', l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval,
        'quote_total', qt.total, 'quote_status', qt.status, 'quote_valid_until', qt.valid_until, 'quote_expired', qt.status = 'sent' and qt.valid_until < public._crmg_today(),
        'converted', l.converted_at is not null, 'lost_reason', l.lost_reason, 'created_at', l.created_at, 'stage_at', l.stage_at, 'last_activity_at', l.last_activity_at),
      l.stage, l.location_id
    from public.crm_leads l
    left join lateral (select q.total, q.status, q.valid_until from public.crm_lead_quotes q where q.lead_id = l.id and q.status in ('accepted', 'sent', 'draft') order by q.version desc limit 1) qt on true
    where public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by)
      and (stages is null or l.stage = any (stages))
      and (nullif(f->>'loc', '') is null or l.location_id = (f->>'loc')::int)
      and (own is null or l.owner_user = own)
      and (qtxt = '' or lower(l.contact_name) like '%' || qtxt || '%' or coalesce(l.contact_phone, '') like '%' || qtxt || '%' or l.lead_no::text = qtxt)
      and (not coalesce((f->>'overdue')::boolean, false) or (l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now()))
      and (not coalesce((f->>'stale')::boolean, false) or (l.stage not in ('won', 'lost') and stale is not null and l.last_activity_at < now() - (stale || ' days')::interval))
      and (nullif(f->>'converted', '') is null or (l.converted_at is not null) = (f->>'converted')::boolean)
      and (nullif(f->>'from', '') is null or (l.created_at at time zone 'Asia/Dhaka')::date >= (f->>'from')::date)
      and (nullif(f->>'to', '') is null or (l.created_at at time zone 'Asia/Dhaka')::date <= (f->>'to')::date)
    order by (l.stage in ('won', 'lost')), coalesce(l.next_follow_up, l.event_date::timestamptz, l.created_at), l.lead_no desc;
end $$;

create or replace function public._crmg_lead_list(p_filter jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(nullif(p_filter->>'limit', '')::int, 100), 1), 300); off int := greatest(coalesce(nullif(p_filter->>'offset', '')::int, 0), 0);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false, 'rows', '[]'::jsonb, 'total', 0); end if;
  return jsonb_build_object('on', true,
    'total', (select count(*) from public._crmg_lead_rows(p_filter)),
    'by_stage', coalesce((select jsonb_object_agg(s, c) from (select stage as s, count(*) as c from public._crmg_lead_rows(p_filter - 'stage') group by stage) z), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(z.r) from (select r from public._crmg_lead_rows(p_filter) offset off limit lim) z), '[]'::jsonb));
end $$;

-- ============================================================================
-- 3. PIPELINE BOARD: five columns with count, value and the cards. Won and lost show the last 30 days only.
-- ============================================================================
create or replace function public._crmg_lead_board(p_loc int default null, p_owner uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f jsonb := jsonb_build_object('loc', p_loc, 'owner', p_owner); out jsonb := '[]'::jsonb; s text; rows jsonb; cnt int; val numeric; since timestamptz := now() - interval '30 days';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false, 'stages', '[]'::jsonb); end if;
  foreach s in array array['enquiry', 'quoted', 'following_up', 'won', 'lost'] loop
    select coalesce(jsonb_agg(z.r), '[]'::jsonb), count(*), coalesce(sum(coalesce((z.r->>'quote_total')::numeric, (z.r->>'est_value')::numeric, 0)), 0) into rows, cnt, val
      from (select r from public._crmg_lead_rows(f || jsonb_build_object('stage', s)) x
            where s not in ('won', 'lost') or (x.r->>'stage_at')::timestamptz >= since limit 60) z;
    out := out || jsonb_build_object('stage', s, 'count', cnt, 'value', val, 'cards', rows);
  end loop;
  return jsonb_build_object('on', true, 'today', public._crmg_today(),
    'overdue', (select count(*) from public._crmg_lead_rows(f || '{"overdue":true}'::jsonb)),
    'stale', (select count(*) from public._crmg_lead_rows(f || '{"stale":true}'::jsonb)),
    'stages', out);
end $$;

-- ============================================================================
-- 4. WIN / LOSS REPORT (leads the caller may see). Read only; no figure of the books is touched.
--    created = enquiries made in the dates; won / lost = enquiries closed in the dates; win rate = won / (won + lost); value of a won lead = its accepted quote or estimate
-- ============================================================================
create or replace function public._crmg_lead_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d1 date := coalesce(p_from, public._crmg_today() - 30); d2 date := coalesce(p_to, public._crmg_today()); res jsonb; stale numeric := public.rule_num('crm_lead_stale_days');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_lead_on() then return jsonb_build_object('on', false); end if;
  if d2 < d1 or d2 - d1 > 800 then raise exception 'bad_dates'; end if;
  with base as (
    select l.*, coalesce((select q.total from public.crm_lead_quotes q where q.lead_id = l.id and q.status in ('accepted', 'sent') order by q.version desc limit 1), l.est_value, 0) as val,
           (select pr.staff_id from public.profiles pr where pr.id = l.owner_user) as owner_staff
      from public.crm_leads l
     where public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) and (p_loc is null or l.location_id = p_loc)),
  made as (select * from base where (created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  closed as (select * from base where closed_at is not null and (closed_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  w as (select * from closed where stage = 'won'), x as (select * from closed where stage = 'lost')
  select jsonb_build_object('on', true, 'from', d1, 'to', d2,
    'created', (select count(*) from made),
    'created_still_open', (select count(*) from made where stage not in ('won', 'lost')),
    'won', (select count(*) from w), 'lost', (select count(*) from x),
    'won_value', (select coalesce(sum(val), 0) from w), 'lost_value', (select coalesce(sum(val), 0) from x),
    'win_rate_pct', (select case when (select count(*) from closed) = 0 then null else round(100.0 * (select count(*) from w) / (select count(*) from closed), 1) end),
    'avg_days_to_close', (select round(avg(extract(epoch from closed_at - created_at) / 86400)::numeric, 1) from closed),
    'open_now', (select count(*) from base where stage not in ('won', 'lost')),
    'open_value', (select coalesce(sum(val), 0) from base where stage not in ('won', 'lost')),
    'overdue_open', (select count(*) from base where stage not in ('won', 'lost') and next_follow_up is not null and next_follow_up < now()),
    'stale_open', (select case when stale is null then null else count(*) end from base where stage not in ('won', 'lost') and stale is not null and last_activity_at < now() - (stale || ' days')::interval),
    'reopened', (select count(*) from base where reopened_count > 0),
    'lost_by_reason', coalesce((select jsonb_agg(jsonb_build_object('code', z.lost_reason, 'label', coalesce(li.label, z.lost_reason), 'count', z.c, 'value', z.v) order by z.c desc, z.lost_reason)
        from (select lost_reason, count(*) c, sum(val) v from x group by lost_reason) z left join public.crm_lead_lists li on li.kind = 'lost_reason' and li.code = z.lost_reason), '[]'::jsonb),
    'by_owner', coalesce((select jsonb_agg(jsonb_build_object('owner_staff', z.o, 'created', z.cr, 'won', z.wn, 'lost', z.ls, 'won_value', z.wv) order by z.wv desc nulls last, z.o)
        from (select o.owner_staff as o, (select count(*) from made m where m.owner_user = o.owner_user) cr, (select count(*) from w where w.owner_user = o.owner_user) wn,
                     (select count(*) from x where x.owner_user = o.owner_user) ls, (select coalesce(sum(val), 0) from w where w.owner_user = o.owner_user) wv
                from (select distinct owner_user, owner_staff from base) o) z where z.cr + z.wn + z.ls > 0), '[]'::jsonb),
    'by_source', coalesce((select jsonb_agg(jsonb_build_object('code', z.k, 'label', coalesce(li.label, z.k, 'Not written'), 'created', z.cr, 'won', z.wn, 'lost', z.ls) order by z.cr desc, z.k)
        from (select s.k, (select count(*) from made m where m.source is not distinct from s.k) cr, (select count(*) from w where w.source is not distinct from s.k) wn, (select count(*) from x where x.source is not distinct from s.k) ls
                from (select distinct source as k from base) s) z left join public.crm_lead_lists li on li.kind = 'source' and li.code = z.k where z.cr + z.wn + z.ls > 0), '[]'::jsonb),
    'by_occasion', coalesce((select jsonb_agg(jsonb_build_object('code', z.k, 'label', coalesce(li.label, z.k, 'Not written'), 'created', z.cr, 'won', z.wn, 'lost', z.ls) order by z.cr desc, z.k)
        from (select s.k, (select count(*) from made m where m.occasion is not distinct from s.k) cr, (select count(*) from w where w.occasion is not distinct from s.k) wn, (select count(*) from x where x.occasion is not distinct from s.k) ls
                from (select distinct occasion as k from base) s) z left join public.crm_lead_lists li on li.kind = 'occasion' and li.code = z.k where z.cr + z.wn + z.ls > 0), '[]'::jsonb))
  into res;
  return res;
end $$;

-- ============================================================================
-- 5. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_lead_convert', '_crmg_lead_rows', '_crmg_lead_list', '_crmg_lead_board', '_crmg_lead_report'],
  array['_crmg_lead_convert', '_crmg_lead_list', '_crmg_lead_board', '_crmg_lead_report']);

-- ---------------------------------------------------------------- phase326.sql
-- Phase 326 (bos326, package CRM-G label 126, part 4 of 5) - TASKS: ADD, DONE, SNOOZE, SKIP, REASSIGN, MY TASKS (overdue first), COUNTS FOR THE HOME STRIP, OPTIONAL IN-APP REMINDERS.
-- Paste AFTER phase325. Paste-twice safe. Nothing here posts to the books and nothing here messages a customer.
-- Every function answers module_off while the switch crm_task_on is OFF (default). The reminder scan does nothing while crm_task_reminder_on is OFF (default).
-- A task is seen by: the person it is assigned to, the person who made it, the owner, holders of crm_task_all, and a holder of crm_lead_manage inside the outlet of the task.
-- Giving a task to another person needs the owner or the right crm_task_assign.

do $g$ begin
  if to_regprocedure('public._crmg_lead_convert(uuid,uuid,text,jsonb)') is null then raise exception 'phase326 needs phase325 first'; end if;
end $g$;

-- ============================================================================
-- 1. HELPERS
-- ============================================================================
create or replace function public._crmg_task_vis(p_loc int, p_assigned uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_task_all') or p_assigned = auth.uid() or p_created = auth.uid()
    or (p_loc is not null and public.can_loc(p_loc) and public.has_grant('crm_lead_manage', p_loc))) $$;

create or replace function public._crmg_task_load(p_id uuid, p_lock boolean default true) returns public.crm_tasks
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then raise exception 'module_off: tasks are switched off'; end if;
  if p_lock then select * into t from public.crm_tasks where id = p_id for update; else select * into t from public.crm_tasks where id = p_id; end if;
  if not found or not public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by) then raise exception 'not_found'; end if;
  return t;
end $$;

create or replace function public._crmg_task_ev(p_task uuid, p_kind text, p_note text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare lid uuid;
begin
  insert into public.crm_task_events (task_id, by_user, by_staff, kind, note, detail) values (p_task, auth.uid(), public._crmg_staff(), p_kind, left(nullif(btrim(p_note), ''), 300), p_detail);
  -- work on a task counts as activity on its enquiry (it keeps the stale clock honest)
  select lead_id into lid from public.crm_tasks where id = p_task;
  if lid is not null and p_kind in ('done', 'snoozed') then update public.crm_leads set last_activity_at = now() where id = lid and stage not in ('won', 'lost'); end if;
end $$;

-- may the caller close, snooze or edit this task: assignee, maker, owner, crm_task_all, manager of the outlet
create or replace function public._crmg_task_act(t public.crm_tasks) returns boolean language sql stable security definer set search_path = public as $$
  select public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by) $$;

-- ============================================================================
-- 2. SAVE (create or edit an open task). p_data: kind, title, due_at, assigned_to, lead_id, customer_id, order_id, location_id.
-- ============================================================================
create or replace function public._crmg_task_save(p_id uuid, p_client uuid, p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'::jsonb); t public.crm_tasks; kd text; ttl text; due timestamptz; asg uuid; lid uuid; cid uuid; oid uuid; loc int; defh numeric := public.rule_num('crm_task_default_due_hours');
        l public.crm_leads; oo public.online_orders; src text := 'manual'; is_new boolean := p_id is null; changed text[] := '{}';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then raise exception 'module_off: tasks are switched off'; end if;
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if is_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into t from public.crm_tasks where created_by = auth.uid() and client_id = p_client;
      if found then return jsonb_build_object('id', t.id, 'status', t.status, 'due_at', t.due_at, 'dup', true); end if;
    end if;
  else
    t := public._crmg_task_load(p_id, true);
    if t.status <> 'open' then raise exception 'task_closed: a done or skipped task cannot be changed'; end if;
  end if;

  kd := coalesce(nullif(btrim(d->>'kind'), ''), case when is_new then 'other' else t.kind end);
  if kd not in ('call', 'message', 'visit', 'follow_up', 'other') then raise exception 'bad_kind'; end if;
  ttl := case when d ? 'title' then left(btrim(coalesce(d->>'title', '')), 120) else t.title end;
  if coalesce(ttl, '') = '' then raise exception 'title_required: write what has to be done'; end if;
  begin due := case when d ? 'due_at' then nullif(d->>'due_at', '')::timestamptz else t.due_at end; exception when others then raise exception 'bad_due'; end;
  if due is null then
    if defh is null then raise exception 'due_required: write the date and time the task is due'; end if;
    due := now() + (defh || ' hours')::interval;
  end if;
  if due > now() + interval '3 years' then raise exception 'bad_due'; end if;

  -- links: an enquiry (must be visible), a customer, an online order
  lid := case when d ? 'lead_id' then nullif(d->>'lead_id', '')::uuid else t.lead_id end;
  cid := case when d ? 'customer_id' then nullif(d->>'customer_id', '')::uuid else t.customer_id end;
  oid := case when d ? 'order_id' then nullif(d->>'order_id', '')::uuid else t.order_id end;
  loc := t.location_id;
  if lid is not null then
    select * into l from public.crm_leads where id = lid;
    if not found or not public._crmg_lead_vis(l.location_id, l.owner_user, l.created_by) then raise exception 'not_found'; end if;
    loc := l.location_id; cid := coalesce(cid, l.customer_id); src := 'lead';
  end if;
  if cid is not null and not exists (select 1 from public.customers where id = cid) then raise exception 'customer_not_found'; end if;
  if oid is not null then
    select * into oo from public.online_orders where id = oid;
    if not found or not public.can_loc(oo.location_id) then raise exception 'not_found'; end if;
    loc := coalesce(loc, oo.location_id); src := case when lid is null then 'order' else src end;
  end if;
  if loc is null and nullif(d->>'location_id', '') is not null then
    loc := (d->>'location_id')::int;
    if not exists (select 1 from public.locations where id = loc) or not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  end if;

  -- who does it
  asg := case when d ? 'assigned_to' and nullif(d->>'assigned_to', '') is not null then (d->>'assigned_to')::uuid else coalesce(t.assigned_to, auth.uid()) end;
  if asg <> auth.uid() and asg is distinct from t.assigned_to then
    if not (public.is_owner() or public.has_grant('crm_task_assign') or (loc is not null and public._crmg_lead_mgr(loc))) then raise exception 'not allowed: giving a task to someone else needs the right to assign tasks'; end if;
    if not exists (select 1 from public.profiles where id = asg and status = 'active') then raise exception 'assignee_not_active'; end if;
    if loc is not null and not public._crmg_user_at(asg, loc) then raise exception 'assignee_not_at_outlet: this person does not work at this outlet'; end if;
  end if;

  if is_new then
    insert into public.crm_tasks (client_id, location_id, customer_id, lead_id, order_id, kind, title, due_at, assigned_to, source, created_by)
      values (p_client, loc, cid, lid, oid, kd, ttl, due, asg, src, auth.uid()) returning * into t;
    perform public._crmg_task_ev(t.id, 'created', null, jsonb_build_object('assigned_to', asg, 'due_at', due));
    if lid is not null then perform public._crmg_ev(lid, 'task', null, null, 'task added: ' || ttl, jsonb_build_object('task_id', t.id, 'due_at', due)); end if;
  else
    if ttl is distinct from t.title then changed := changed || 'title'::text; end if;
    if due is distinct from t.due_at then changed := changed || 'due_at'::text; end if;
    if kd is distinct from t.kind then changed := changed || 'kind'::text; end if;
    if asg is distinct from t.assigned_to then changed := changed || 'assigned_to'::text; end if;
    update public.crm_tasks set kind = kd, title = ttl, due_at = due, assigned_to = asg, customer_id = cid, lead_id = lid, order_id = oid, location_id = loc,
        snooze_until = case when due is distinct from t.due_at then null else snooze_until end where id = t.id returning * into t;
    if cardinality(changed) > 0 then perform public._crmg_task_ev(t.id, case when 'assigned_to' = any (changed) then 'assigned' else 'edited' end, null, jsonb_build_object('changed', changed, 'assigned_to', asg)); end if;
  end if;
  return jsonb_build_object('id', t.id, 'status', t.status, 'due_at', t.due_at, 'assigned_to', t.assigned_to);
end $$;

-- ============================================================================
-- 3. DONE, SNOOZE, SKIP
-- ============================================================================
create or replace function public._crmg_task_done(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks;
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status = 'done' then return jsonb_build_object('id', t.id, 'status', 'done', 'noop', true); end if;
  if t.status <> 'open' then raise exception 'task_closed: a skipped task cannot be marked done'; end if;
  update public.crm_tasks set status = 'done', done_note = left(nullif(btrim(p_note), ''), 300), done_by = auth.uid(), done_at = now() where id = t.id;
  perform public._crmg_task_ev(t.id, 'done', p_note, null);
  return jsonb_build_object('id', t.id, 'status', 'done');
end $$;

-- put a task off until a later time. p_until, or p_hours from now. Not longer than crm_task_snooze_max_days when that is set.
create or replace function public._crmg_task_snooze(p_id uuid, p_until timestamptz default null, p_hours numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks; u timestamptz; mx numeric := public.rule_num('crm_task_snooze_max_days');
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status <> 'open' then raise exception 'task_closed: a done or skipped task cannot be snoozed'; end if;
  u := coalesce(p_until, case when p_hours is not null then now() + (p_hours || ' hours')::interval end);
  if u is null then raise exception 'snooze_until_required: say until when'; end if;
  if u <= now() then raise exception 'bad_snooze: the time must be in the future'; end if;
  if mx is not null and u > now() + (mx || ' days')::interval then raise exception 'snooze_too_long: the longest snooze is % days', mx::int; end if;
  update public.crm_tasks set snooze_until = u, snooze_count = snooze_count + 1 where id = t.id;
  perform public._crmg_task_ev(t.id, 'snoozed', p_note, jsonb_build_object('until', u));
  return jsonb_build_object('id', t.id, 'snooze_until', u, 'snooze_count', t.snooze_count + 1);
end $$;

-- skip a task: a written reason is needed (an exception that stays in the task trail and the audit log)
create or replace function public._crmg_task_skip(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.crm_tasks; why text;
begin
  t := public._crmg_task_load(p_id, true);
  if not public._crmg_task_act(t) then raise exception 'not allowed'; end if;
  if t.status = 'skipped' then return jsonb_build_object('id', t.id, 'status', 'skipped', 'noop', true); end if;
  if t.status <> 'open' then raise exception 'task_closed: a done task cannot be skipped'; end if;
  why := public._crmg_reason(p_reason);
  update public.crm_tasks set status = 'skipped', skip_reason = why where id = t.id;
  perform public._crmg_task_ev(t.id, 'skipped', why, null);
  perform public._crmg_audit('skip', 'crm_tasks', t.id::text, jsonb_build_object('reason', why));
  return jsonb_build_object('id', t.id, 'status', 'skipped');
end $$;

-- ============================================================================
-- 4. MY TASKS   p_scope: mine (default) | team (every task the caller may see) | user (p_user, if the caller may see them)
--    Buckets: overdue (the due time has passed and no snooze runs), today (due later today), upcoming, snoozed. Done and skipped are not listed (recent_done: last 7 days of the caller's own).
-- ============================================================================
create or replace function public._crmg_my_tasks(p_scope text default 'mine', p_user uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sc text := coalesce(p_scope, 'mine'); who uuid; today date := public._crmg_today(); res jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._crmg_task_on() then return jsonb_build_object('on', false); end if;
  if sc not in ('mine', 'team', 'user') then raise exception 'bad_scope'; end if;
  who := case when sc = 'mine' then auth.uid() when sc = 'user' then coalesce(p_user, auth.uid()) end;
  with t as (
    select t.*, (select pr.staff_id from public.profiles pr where pr.id = t.assigned_to) as staff, l.lead_no, l.contact_name as lead_name, l.stage as lead_stage, oo.order_no, oo.status as order_status,
           case when t.snooze_until is not null and t.snooze_until > now() then 'snoozed'
                when t.due_at < now() then 'overdue'
                when (t.due_at at time zone 'Asia/Dhaka')::date = today then 'today' else 'upcoming' end as bucket
      from public.crm_tasks t
      left join public.crm_leads l on l.id = t.lead_id
      left join public.online_orders oo on oo.id = t.order_id
     where t.status = 'open' and (who is null or t.assigned_to = who)
       and public._crmg_task_vis(t.location_id, t.assigned_to, t.created_by)
       and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))),
  j as (select bucket, jsonb_build_object('id', t.id, 'kind', t.kind, 'title', t.title, 'due_at', t.due_at, 'snooze_until', t.snooze_until, 'snooze_count', t.snooze_count, 'assigned_to', t.assigned_to,
        'assigned_staff', t.staff, 'lead_id', t.lead_id, 'lead_no', t.lead_no, 'lead_name', t.lead_name, 'customer_id', t.customer_id, 'order_id', t.order_id, 'order_no', t.order_no, 'source', t.source,
        'location_id', t.location_id, 'overdue_hours', case when t.bucket = 'overdue' then round(extract(epoch from now() - t.due_at) / 3600, 1) end) as r, t.due_at, t.snooze_until from t)
  select jsonb_build_object('on', true, 'now', now(), 'scope', sc,
    'counts', jsonb_build_object('overdue', (select count(*) from j where bucket = 'overdue'), 'today', (select count(*) from j where bucket = 'today'),
        'upcoming', (select count(*) from j where bucket = 'upcoming'), 'snoozed', (select count(*) from j where bucket = 'snoozed')),
    'overdue', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'overdue' order by due_at limit 200) z), '[]'::jsonb),
    'today', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'today' order by due_at limit 200) z), '[]'::jsonb),
    'upcoming', coalesce((select jsonb_agg(r order by due_at) from (select * from j where bucket = 'upcoming' order by due_at limit 100) z), '[]'::jsonb),
    'snoozed', coalesce((select jsonb_agg(r order by snooze_until) from (select * from j where bucket = 'snoozed' order by snooze_until limit 100) z), '[]'::jsonb),
    'recent_done', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'title', d.title, 'done_at', d.done_at, 'done_note', d.done_note) order by d.done_at desc)
        from (select * from public.crm_tasks d where d.status = 'done' and d.done_by = auth.uid() and d.done_at > now() - interval '7 days' order by d.done_at desc limit 20) d), '[]'::jsonb))
  into res;
  return res;
end $$;

-- numbers for the Home strip: the caller's own open tasks and own open enquiries with a missed follow-up. Cheap; never raises for a person without tasks.
create or replace function public._crmg_task_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._crmg_today(); r jsonb;
begin
  if not public.is_active() then return jsonb_build_object('on', false); end if;
  r := jsonb_build_object('on', public._crmg_task_on(), 'lead_on', public._crmg_lead_on());
  if public._crmg_task_on() then
    r := r || (select jsonb_build_object(
      'open', count(*) filter (where not (t.snooze_until is not null and t.snooze_until > now())),
      'overdue', count(*) filter (where t.due_at < now() and not (t.snooze_until is not null and t.snooze_until > now())),
      'today', count(*) filter (where t.due_at >= now() and (t.due_at at time zone 'Asia/Dhaka')::date = today and not (t.snooze_until is not null and t.snooze_until > now())),
      'snoozed', count(*) filter (where t.snooze_until is not null and t.snooze_until > now()))
      from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id
     where t.status = 'open' and t.assigned_to = auth.uid() and not (t.source = 'order' and oo.status in ('delivered', 'cancelled')));
  end if;
  if public._crmg_lead_on() then
    r := r || jsonb_build_object('leads_overdue', (select count(*) from public.crm_leads l where l.owner_user = auth.uid() and l.stage not in ('won', 'lost') and l.next_follow_up is not null and l.next_follow_up < now()));
  end if;
  return r;
end $$;

-- ============================================================================
-- 5. SWEEP AND REMINDERS (both run only for the owner, the notify bot or the database scheduler; the reminder does nothing while crm_task_reminder_on is OFF)
-- ============================================================================
create or replace function public._crmg_sched_ok() returns text language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is not null then
    if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
    return case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  end if;
  if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
  return 'database_scheduler';
end $$;

-- end the open tasks that follow a delivered or cancelled order (the My tasks list already hides them; this makes it stick)
create or replace function public._crmg_tasks_sweep(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare via text := public._crmg_sched_ok(); r record; n int := 0;
begin
  if not public._crmg_task_on() then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  for r in select t.id, oo.status from public.crm_tasks t join public.online_orders oo on oo.id = t.order_id where t.status = 'open' and t.source in ('order', 'lead') and oo.status in ('delivered', 'cancelled') and t.order_id is not null for update of t loop
    n := n + 1;
    if not p_dry then
      update public.crm_tasks set status = 'skipped', skip_reason = 'the order was ' || r.status where id = r.id;
      insert into public.crm_task_events (task_id, kind, note, detail) values (r.id, 'skipped', 'the order was ' || r.status, jsonb_build_object('via', via));
    end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'closed', n, 'dry', p_dry, 'via', via);
end $$;

-- the in-app reminder: one line per person per day, counts only (no customer name or phone). The existing notify job calls this (hook in docs/integration/CRM-G.md).
create or replace function public._crmg_task_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare via text := public._crmg_sched_ok(); r record; made int := 0; people int := 0; stale numeric := public.rule_num('crm_lead_stale_days'); sweep jsonb; n_over int; n_today int; n_stale int; body text;
begin
  if not public.rule_on('crm_task_reminder_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  if not p_dry and public._crmg_task_on() then sweep := public._crmg_tasks_sweep(false); end if;
  for r in
    select p.id as uid, p.staff_id,
           (select count(*) from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id where public._crmg_task_on() and t.status = 'open' and t.assigned_to = p.id and t.due_at < now()
              and not (t.snooze_until is not null and t.snooze_until > now()) and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))) as over_n,
           (select count(*) from public.crm_tasks t left join public.online_orders oo on oo.id = t.order_id where public._crmg_task_on() and t.status = 'open' and t.assigned_to = p.id and t.due_at >= now()
              and (t.due_at at time zone 'Asia/Dhaka')::date = public._crmg_today() and not (t.snooze_until is not null and t.snooze_until > now()) and not (t.source = 'order' and oo.status in ('delivered', 'cancelled'))) as today_n,
           (select count(*) from public.crm_leads l where public._crmg_lead_on() and l.owner_user = p.id and l.stage not in ('won', 'lost')
              and ((l.next_follow_up is not null and l.next_follow_up < now()) or (stale is not null and l.last_activity_at < now() - (stale || ' days')::interval))) as lead_n
      from public.profiles p where p.status = 'active'
  loop
    if r.over_n + r.today_n + r.lead_n = 0 then continue; end if;
    people := people + 1;
    if p_dry then continue; end if;
    body := r.over_n || ' overdue, ' || r.today_n || ' due today' || case when r.lead_n > 0 then ', ' || r.lead_n || ' enquiries need a follow-up' else '' end;
    insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key)
      values (r.uid, 'all', 'crm_task_due', case when r.over_n > 0 then 'warn' else 'info' end, 'You have tasks to do', 'You have tasks to do', body, body, 'crmtasks', r.uid::text)
      on conflict (kind, key, day) do nothing;
    if found then made := made + 1; end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'people', people, 'created', made, 'dry', p_dry, 'via', via, 'swept', sweep);
end $$;

-- ============================================================================
-- 6. PRIVILEGES
-- ============================================================================
select public._crmg_lock(array['_crmg_task_vis', '_crmg_task_load', '_crmg_task_ev', '_crmg_task_act', '_crmg_task_save', '_crmg_task_done', '_crmg_task_snooze', '_crmg_task_skip', '_crmg_my_tasks',
  '_crmg_task_counts', '_crmg_sched_ok', '_crmg_tasks_sweep', '_crmg_task_scan'],
  array['_crmg_task_save', '_crmg_task_done', '_crmg_task_snooze', '_crmg_task_skip', '_crmg_my_tasks', '_crmg_task_counts', '_crmg_tasks_sweep', '_crmg_task_scan']);

-- ---------------------------------------------------------------- phase327.sql
-- Phase 327 (bos327, package CRM-G label 127, part 5 of 5) - STATUS FOR THE SCREENS, SETTINGS OVERVIEW, GO-LIVE CHECKLIST.
-- Paste AFTER phase326. Paste-twice safe. Read only: nothing is written, nothing is posted.
--   _crmg_status()     what the signed-in person may do right now (drives which buttons the two screens draw; the server still decides every call)
--   _crmg_settings()   every setting of this package with its value, its default and the plain-English label and hint (owner, or a holder of Manage enquiries)
--   _crmg_readiness()  the go-live checklist: what must be set up before the screens are useful

do $g$ begin
  if to_regprocedure('public._crmg_task_scan(boolean)') is null then raise exception 'phase327 needs phase326 first'; end if;
end $g$;

create or replace function public._crmg_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if not public.is_active() then return jsonb_build_object('signed_in', false); end if;
  return jsonb_build_object('signed_in', true, 'uid', uid, 'lead_on', public._crmg_lead_on(), 'task_on', public._crmg_task_on(), 'reminder_on', public.rule_on('crm_task_reminder_on'),
    'is_owner', public.is_owner(),
    'can_create_lead', public.is_owner() or public.has_grant('crm_lead_all') or exists (select 1 from public.locations x where x.is_active and public._crmg_can_create(x.id)),
    'can_manage_leads', public.is_owner() or public.has_grant('crm_lead_all') or exists (select 1 from public.locations x where x.is_active and public._crmg_lead_mgr(x.id)),
    'sees_all_outlets', public.is_owner() or public.has_grant('crm_lead_all'),
    'can_assign_tasks', public.is_owner() or public.has_grant('crm_task_assign'),
    'sees_all_tasks', public.is_owner() or public.has_grant('crm_task_all'),
    'can_edit_lists', public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage')),
    'lost_by', coalesce(public.rule_txt('crm_lead_lost_by'), 'manager'), 'reopen_mode', coalesce(public.rule_txt('crm_lead_reopen_mode'), 'reason'),
    'win_needs_quote', public.rule_on('crm_lead_win_needs_quote'), 'quote_valid_days', public.rule_num('crm_lead_quote_valid_days'),
    'stale_days', public.rule_num('crm_lead_stale_days'), 'task_default_due_hours', public.rule_num('crm_task_default_due_hours'), 'snooze_max_days', public.rule_num('crm_task_snooze_max_days'),
    'online_orders_on', public.rule_on('online_orders_on'),
    'my_outlets', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'name', coalesce(x.name_en, x.name_bn)) order by x.sort, x.id) from public.locations x where x.is_active and x.kind in ('showroom', 'hub', 'online', 'other') and public.can_loc(x.id)), '[]'::jsonb),
    'staff_here', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'staff_id', p.staff_id, 'name', p.full_name) order by p.staff_id) from public.profiles p
        where p.status = 'active' and (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_task_assign') or public.has_grant('crm_lead_all')) ), '[]'::jsonb));
end $$;

create or replace function public._crmg_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_lead_all')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('rules', coalesce((select jsonb_agg(jsonb_build_object('key', r.key, 'kind', r.kind, 'value', r.value, 'default', r.default_value, 'effective', coalesce(r.value, r.default_value),
      'unit', r.unit, 'choices', r.choices, 'min', r.min_value, 'max', r.max_value, 'label', coalesce(r.label_en, r.label_bn), 'hint', coalesce(r.hint_en, r.hint_bn)) order by r.sort, r.key)
      from public.rules r where r.module = 'crm' and r.key in ('crm_lead_on', 'crm_task_on', 'crm_lead_lost_by', 'crm_lead_reopen_mode', 'crm_lead_win_needs_quote', 'crm_lead_quote_valid_days', 'crm_quote_min_lead_days',
        'crm_lead_stale_days', 'crm_lead_list_add_mode', 'crm_task_default_due_hours', 'crm_task_snooze_max_days', 'crm_order_task_days', 'crm_task_reminder_on')), '[]'::jsonb),
    'grants', coalesce((select jsonb_agg(jsonb_build_object('code', g.grant_code, 'label', coalesce(g.label_en, g.label_bn)) order by g.sort) from public.grant_defs g where g.grant_code in ('crm_lead_manage', 'crm_lead_all', 'crm_task_assign', 'crm_task_all')), '[]'::jsonb));
end $$;

create or replace function public._crmg_readiness() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare items jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('crm_lead_manage') or public.has_grant('crm_lead_all')) then raise exception 'not allowed'; end if;
  items := items || jsonb_build_array(
    jsonb_build_object('key', 'lead_on', 'label', 'Enquiry tracking is switched on', 'ok', public._crmg_lead_on(), 'hint', 'Switch Track party, wholesale, corporate and gift enquiries on in Settings.'),
    jsonb_build_object('key', 'task_on', 'label', 'Tasks are switched on', 'ok', public._crmg_task_on(), 'hint', 'Switch Use follow-up tasks and the My tasks list on in Settings.'),
    jsonb_build_object('key', 'manager_named', 'label', 'Someone besides the owner can manage enquiries',
      'ok', exists (select 1 from public.rule_grants g where g.grant_code = 'crm_lead_manage' and g.allowed) or exists (select 1 from public.user_grants g where g.grant_code = 'crm_lead_manage' and (g.valid_until is null or g.valid_until > now())),
      'hint', 'Give the right Manage enquiries of my outlets to a role or a person. Until then only the owner can assign, close or convert.'),
    jsonb_build_object('key', 'lists', 'label', 'The lists of lost reasons, sources and occasions are filled',
      'ok', (select count(*) from public.crm_lead_lists where kind = 'lost_reason' and active) >= 2 and (select count(*) from public.crm_lead_lists where kind = 'source' and active) >= 2 and (select count(*) from public.crm_lead_lists where kind = 'occasion' and active) >= 2,
      'hint', 'Add the reasons, sources and occasions your shop really uses. The entry Other stays.'),
    jsonb_build_object('key', 'quote_validity', 'label', 'Quote validity is decided', 'ok', public.rule_num('crm_lead_quote_valid_days') is not null,
      'hint', 'Blank means staff type the valid-until date for every quote. Set a number of days to fill it in for them.'),
    jsonb_build_object('key', 'online_orders_on', 'label', 'Online orders are switched on (needed to turn an enquiry into an order)', 'ok', public.rule_on('online_orders_on'),
      'hint', 'Without it an enquiry can still be turned into a draft party form or linked to an existing order.'),
    jsonb_build_object('key', 'channel', 'label', 'A sales channel exists for orders', 'ok', exists (select 1 from public.sales_channels where active),
      'hint', 'Orders made from an enquiry need a sales channel.'),
    jsonb_build_object('key', 'forms', 'label', 'Forms 20-1 and 20-4 are switched on', 'ok', (select count(*) from public.forms where code in ('20-1', '20-4') and enabled) = 2,
      'hint', 'Needed to make a draft customer order form or a draft party invoice from an enquiry.'),
    jsonb_build_object('key', 'reminders_off_is_fine', 'label', 'In-app reminders', 'ok', true, 'state', case when public.rule_on('crm_task_reminder_on') then 'on' else 'off' end,
      'hint', 'Off by default. Staff see their list when they open My tasks. Switch on only when the notify job calls the reminder (see the integration note).'));
  return jsonb_build_object('items', items, 'all_ok', not exists (select 1 from jsonb_array_elements(items) x where not (x->>'ok')::boolean));
end $$;

select public._crmg_lock(array['_crmg_status', '_crmg_settings', '_crmg_readiness'], array['_crmg_status', '_crmg_settings', '_crmg_readiness']);

-- ---------------------------------------------------------------- phase328.sql
-- Phase 328 (bos328, package CRM-H, part 1 of 2: label 128) - CUSTOMER COMPLAINTS WITH AN SLA CLOCK.
-- Paste AFTER phase98 (needs the sale return, exceptions, rules, grants and option lists of the older phases). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created. Every new name starts _crmh_ / crm_ so it cannot clash with another package.
-- Part 2 (phase329) adds ratings, repeat-complaint lists and the report.
--
-- WHY (CRM design 3.1.H, audit rows 46-48): today a complaint is a paper-replica line in form 20-3 (free-text customer, no due time, no owner, no clock).
-- A food-safety complaint needs a clock and the owner needs to see which outlet and which item keep producing complaints.
-- WHAT THIS FILE ADDS
--   1. Settings (rules, module crm), all OFF or blank: crm_complaints_on, one SLA target (hours) per severity, food-safety routing, repeat detection.
--   2. Three grants: crm_complaint_log, crm_complaint_manage, crm_feedback_view (nobody gets them by default; the owner always has them).
--   3. Three editable lists (option_lists): complaint categories, resolution types, reasons for closing without a resolution.
--   4. Tables: crm_complaints, crm_complaint_events (append only), crm_complaint_returns (link to the EXISTING sale return, never a second refund path).
--   5. A status guard trigger: illegal status changes are refused by the database itself; a closed complaint is locked; nothing is deleted.
--   6. API functions (all _crmh_*, SECURITY DEFINER, gated first, idempotent where a client id is given):
--        _crmh_complaint_save, _crmh_complaint_assign, _crmh_complaint_note, _crmh_complaint_move, _crmh_complaint_severity_set,
--        _crmh_complaint_link_return, _crmh_complaint_list, _crmh_complaint_get, _crmh_sla_scan, _crmh_counts, _crmh_settings
-- ACCOUNTING: a complaint posts nothing. No function here touches sales, sale_returns, sale_payments, journal_entries or journal_lines.
--   A refund goes through the existing sale_return function; this file only LINKS a finished return to a complaint (read only on sale_returns).
-- DEFAULTS: with crm_complaints_on OFF every write function answers 'complaints_off' and no report, screen or workflow changes.

do $g$ begin
  if to_regclass('public.sale_returns') is null or to_regclass('public.exceptions') is null or to_regclass('public.option_lists') is null
     or to_regclass('public.grant_defs') is null or to_regclass('public.customers') is null or to_regclass('public.online_orders') is null
     or to_regprocedure('public.rpt_mobile_ok()') is null or to_regprocedure('public._is_ops(text)') is null or to_regprocedure('public.has_grant(text,integer)') is null then
    raise exception 'phase328 needs the older phases (sale return, online orders, reports, notify, grants) first';
  end if;
end $g$;

create or replace function public._crmh_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). English text only. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_complaints_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
  'Record customer complaints and track them to a result',
  'OFF = nothing changes (today). ON = staff can log a complaint with outlet, item, severity and owner, and it has a status and a result. A complaint never posts any money; a refund is still made on the sale return screen.', 1280),
 ('crm_complaint_sla_hours_low', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a LOW severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1281),
 ('crm_complaint_sla_hours_medium', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a MEDIUM severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1282),
 ('crm_complaint_sla_hours_high', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a HIGH severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1283),
 ('crm_complaint_sla_hours_critical', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a CRITICAL severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1284),
 ('crm_complaint_fs_exception_on', 'switch', 'true'::jsonb, null, null, null, null,
  'Put a food-safety complaint on the Exceptions list',
  'Only used while complaints are ON. ON = a complaint marked food safety adds one red line to the Exceptions list so the owner sees it at once. OFF = it is only marked on the complaint.', 1285),
 ('crm_complaint_fs_categories', 'text', '"sick"'::jsonb, null, null, null, null,
  'Complaint categories that always count as food safety',
  'A comma list of category codes (for example sick). A complaint in one of these categories is marked food safety even if the box is not ticked. Blank = only the box decides. The default sick is the same "fell ill" cause that form 20-3 already flags.', 1286),
 ('crm_complaint_fs_severity', 'choice', '"keep"'::jsonb, null, '["keep","high","critical"]'::jsonb, null, null,
  'Lowest severity given to a food-safety complaint',
  'keep = the severity chosen by the person (today). high or critical = a food-safety complaint is never logged below that severity, so it gets the shorter clock.', 1287),
 ('crm_complaint_breach_exception_on', 'switch', 'true'::jsonb, null, null, null, null,
  'Put an overdue complaint on the Exceptions list',
  'Only used while complaints are ON and only when an SLA clock is set. ON = when the overdue check runs, each newly overdue complaint adds one yellow line to the Exceptions list. OFF = it is only marked on the complaint.', 1288),
 ('crm_repeat_days', 'number', null, 'days', null, 1, 3650,
  'Repeat complaint check: look back this many days',
  'Blank = no repeat check (today). A number marks a new complaint as a REPEAT when the same customer (and, by the next setting, the same item) already complained inside this many days.', 1289),
 ('crm_repeat_min', 'number', '2'::jsonb, 'complaints', null, 2, 50,
  'Repeat complaint check: complaints needed (this one included)',
  'Used only when the look-back days above are set. 2 = flag the second complaint. 3 = flag from the third.', 1290),
 ('crm_repeat_scope', 'choice', '"customer_item"'::jsonb, null, '["customer_item","customer"]'::jsonb, null, null,
  'Repeat complaint check: same customer and same item, or same customer only',
  'Used only when the look-back days above are set. customer_item = the same customer complained about the same item. customer = any complaint by the same customer.', 1291)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 2. GRANTS (nobody holds them by default; the owner always passes)
-- ============================================================================
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type) values
 ('crm_complaint_log', 'crm', 920, 'Log a customer complaint or rating', 'Log a customer complaint or rating', 'Log a customer complaint or rating', 'once'),
 ('crm_complaint_manage', 'crm', 921, 'Assign, resolve and close customer complaints', 'Assign, resolve and close customer complaints', 'Assign, resolve and close customer complaints', 'once'),
 ('crm_feedback_view', 'crm', 922, 'See customer complaint and rating lists and reports', 'See customer complaint and rating lists and reports', 'See customer complaint and rating lists and reports', 'once')
on conflict (grant_code) do nothing;

-- ============================================================================
-- 3. EDITABLE LISTS (BUILD-RULES 4: a list, not free text; the owner can add or retire entries on the lists screen)
--    Categories mirror the causes already on form 20-3 so the two registers speak the same words.
-- ============================================================================
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('crm_complaint_cats', 'taste', 'Taste', 'Taste', 'Taste', 1), ('crm_complaint_cats', 'smell', 'Smell or spoiled', 'Smell or spoiled', 'Smell or spoiled', 2),
 ('crm_complaint_cats', 'broken', 'Broken or damaged', 'Broken or damaged', 'Broken or damaged', 3), ('crm_complaint_cats', 'short', 'Short quantity', 'Short quantity', 'Short quantity', 4),
 ('crm_complaint_cats', 'wrong', 'Wrong goods', 'Wrong goods', 'Wrong goods', 5), ('crm_complaint_cats', 'late', 'Late delivery', 'Late delivery', 'Late delivery', 6),
 ('crm_complaint_cats', 'staff', 'Staff behaviour', 'Staff behaviour', 'Staff behaviour', 7), ('crm_complaint_cats', 'sick', 'Customer fell ill', 'Customer fell ill', 'Customer fell ill', 8),
 ('crm_complaint_cats', 'other', 'Other', 'Other', 'Other', 99),
 ('crm_resolution_types', 'explained', 'Explained to the customer', 'Explained to the customer', 'Explained to the customer', 1),
 ('crm_resolution_types', 'replaced', 'Goods replaced', 'Goods replaced', 'Goods replaced', 2),
 ('crm_resolution_types', 'refunded', 'Refund or credit given (sale return)', 'Refund or credit given (sale return)', 'Refund or credit given (sale return)', 3),
 ('crm_resolution_types', 'other', 'Other', 'Other', 'Other', 99),
 ('crm_close_reasons', 'no_contact', 'Customer could not be reached', 'Customer could not be reached', 'Customer could not be reached', 1),
 ('crm_close_reasons', 'not_valid', 'Not a valid complaint', 'Not a valid complaint', 'Not a valid complaint', 2),
 ('crm_close_reasons', 'duplicate', 'Same as another complaint', 'Same as another complaint', 'Same as another complaint', 3),
 ('crm_close_reasons', 'other', 'Other', 'Other', 'Other', 99)
on conflict (list_code, value_code) do nothing;

-- ============================================================================
-- 4. TABLES (closed to browser roles; read and written only through the definer functions below)
-- ============================================================================
create sequence if not exists public.crm_complaints_no_seq;
create table if not exists public.crm_complaints (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  ticket_no bigint not null default nextval('public.crm_complaints_no_seq'),
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  customer_name text check (customer_name is null or char_length(customer_name) <= 80),
  customer_phone text check (customer_phone is null or char_length(customer_phone) <= 20),
  sale_id uuid references public.sales(id),
  order_id uuid references public.online_orders(id),
  item_id uuid references public.items(id),
  category text not null,
  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  food_safety boolean not null default false,
  description text not null check (char_length(btrim(description)) between 3 and 1000),
  batch_ref text check (batch_ref is null or char_length(batch_ref) <= 60),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed', 'closed_no_resolution')),
  owner_user uuid references public.profiles(id),
  due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz, resolution_type text, resolution_note text check (resolution_note is null or char_length(resolution_note) <= 1000),
  closed_at timestamptz, close_reason text,
  sla_met boolean,
  breached_at timestamptz,
  repeat_flag boolean not null default false,
  repeat_count int not null default 0,
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists crm_complaints_loc_status on public.crm_complaints (location_id, status, created_at desc);
create index if not exists crm_complaints_cust on public.crm_complaints (customer_id, created_at desc) where customer_id is not null;
create index if not exists crm_complaints_item on public.crm_complaints (item_id, created_at desc) where item_id is not null;
create index if not exists crm_complaints_due on public.crm_complaints (due_at) where status in ('open', 'in_progress');

create table if not exists public.crm_complaint_events (            -- append only trail: who did what, when
  id bigserial primary key,
  complaint_id uuid not null references public.crm_complaints(id),
  at timestamptz not null default now(),
  kind text not null check (kind in ('created', 'assigned', 'status', 'note', 'contact', 'severity', 'link_return', 'sla_breach', 'repeat', 'food_safety', 'reopen')),
  from_status text, to_status text, note text check (note is null or char_length(note) <= 1000),
  by_user uuid, by_staff text
);
create index if not exists crm_complaint_events_c on public.crm_complaint_events (complaint_id, id);

create table if not exists public.crm_complaint_returns (           -- a finished sale return linked to a complaint (the refund itself stays on the sale return screen)
  id bigserial primary key,
  complaint_id uuid not null references public.crm_complaints(id),
  return_id uuid not null unique references public.sale_returns(id),
  linked_by uuid, linked_at timestamptz not null default now()
);
create index if not exists crm_complaint_returns_c on public.crm_complaint_returns (complaint_id);

do $t$ declare t text; begin
  foreach t in array array['crm_complaints', 'crm_complaint_events', 'crm_complaint_returns'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;
drop trigger if exists audit_crm_complaints on public.crm_complaints;
create trigger audit_crm_complaints after insert or update on public.crm_complaints for each row execute function public.log_change('id');

-- the events table is append only
create or replace function public._crmh_append_only() returns trigger language plpgsql as $$
begin raise exception 'append_only'; end $$;
drop trigger if exists crm_complaint_events_ro on public.crm_complaint_events;
create trigger crm_complaint_events_ro before update on public.crm_complaint_events for each row execute function public._crmh_append_only();

-- the status guard: the database itself refuses an illegal move, whoever asks (a hidden button is also a refused request)
--   open -> in_progress | resolved | closed_no_resolution ;  in_progress -> resolved | closed_no_resolution ;  resolved -> closed | in_progress (reopen)
--   closed and closed_no_resolution are final: the row is locked.
create or replace function public._crmh_complaint_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if new.id is distinct from old.id or new.client_id is distinct from old.client_id or new.ticket_no is distinct from old.ticket_no
     or new.location_id is distinct from old.location_id or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'complaint_immutable';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'open' and new.status in ('in_progress', 'resolved', 'closed_no_resolution'))
    or (old.status = 'in_progress' and new.status in ('resolved', 'closed_no_resolution'))
    or (old.status = 'resolved' and new.status in ('closed', 'in_progress'))) then
    raise exception 'illegal_status_change';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists crm_complaints_guard on public.crm_complaints;
create trigger crm_complaints_guard before update on public.crm_complaints for each row execute function public._crmh_complaint_guard();

-- ============================================================================
-- 5. INTERNAL HELPERS (closed to browsers)
-- ============================================================================
create or replace function public._crmh_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid() $$;

-- who may do what, per outlet (the server decides; owner always)
create or replace function public._crmh_log_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and (public.has_grant('crm_complaint_log', p_loc) or public.has_grant('crm_complaint_manage', p_loc) or public.can_do('POS', 'enter')))) $$;
create or replace function public._crmh_manage_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and public.has_grant('crm_complaint_manage', p_loc))) $$;
create or replace function public._crmh_view_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and (public.has_grant('crm_feedback_view', p_loc) or public.has_grant('crm_complaint_manage', p_loc)))) $$;
create or replace function public._crmh_phone_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_mobile_ok() or public._crmh_manage_ok(p_loc)) $$;
create or replace function public._crmh_mask(p text) returns text language sql immutable as $$
  select case when p is null or p = '' then p when char_length(p) <= 5 then '****' else left(p, 3) || '****' || right(p, 2) end $$;

create or replace function public._crmh_j_uuid(p jsonb, k text) returns uuid language plpgsql immutable as $$
declare v text := nullif(btrim(p ->> k), '');
begin
  if v is null then return null; end if;
  if v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_%', k; end if;
  return v::uuid;
end $$;
create or replace function public._crmh_j_bool(p jsonb, k text) returns boolean language sql immutable as $$
  select coalesce(lower(p ->> k) in ('true', 't', '1', 'yes'), false) $$;

create or replace function public._crmh_sla_hours(p_sev text) returns numeric language sql stable security definer set search_path = public as $$
  select public.rule_num('crm_complaint_sla_hours_' || p_sev) $$;
create or replace function public._crmh_sla_state(st text, due timestamptz, met boolean) returns text language sql stable as $$
  select case when st in ('resolved', 'closed') then case when met is true then 'met' when met is false then 'missed' else 'none' end
              when st = 'closed_no_resolution' then 'none'
              when due is null then 'none' when now() > due then 'overdue' else 'running' end $$;

create or replace function public._crmh_ev(p_c uuid, p_kind text, p_from text, p_to text, p_note text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_complaint_events (complaint_id, kind, from_status, to_status, note, by_user, by_staff)
    values (p_c, p_kind, p_from, p_to, left(p_note, 1000), auth.uid(), public._crmh_staff());
end $$;
create or replace function public._crmh_audit(p_action text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmh_staff(), p_action, 'crm_complaints', p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
-- one row in the Exceptions list; the same open flag for the same complaint is not written twice
create or replace function public._crmh_exc(p_loc int, p_flag text, p_level text, p_en text, p_ref text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.exceptions x where x.flag_code = p_flag and x.status = 'open' and x.text ->> 'ref' = p_ref) then return false; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, 'CRM', p_loc, (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, null, jsonb_build_object('bn', p_en, 'en', p_en, 'ref', p_ref));
  return true;
end $$;

-- may this user take part in an outlet (used before a complaint is assigned to them)
create or replace function public._crmh_user_loc_ok(p_user uuid, p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p_user and status = 'active')
     and (exists (select 1 from public.user_roles where user_id = p_user and role_code in ('owner', 'management'))
          or exists (select 1 from public.user_locations where user_id = p_user and location_id = p_loc)) $$;

-- how many earlier complaints match (repeat detection). 0 when the check is off or there is nothing to match on.
create or replace function public._crmh_repeat_prior(p_cust uuid, p_phone text, p_item uuid, p_before timestamptz) returns int
language plpgsql stable security definer set search_path = public as $$
declare days numeric := public.rule_num('crm_repeat_days'); scope text := coalesce(public.rule_txt('crm_repeat_scope'), 'customer_item'); n int;
begin
  if days is null then return 0; end if;
  if p_cust is null and nullif(btrim(coalesce(p_phone, '')), '') is null then return 0; end if;
  if scope = 'customer_item' and p_item is null then return 0; end if;
  select count(*) into n from public.crm_complaints x
   where x.created_at < p_before and x.created_at >= p_before - make_interval(days => days::int)
     and coalesce(x.close_reason, '') <> 'duplicate'
     and ((p_cust is not null and x.customer_id = p_cust)
          or (nullif(btrim(coalesce(p_phone, '')), '') is not null and nullif(public.norm_mobile(x.customer_phone), '') = public.norm_mobile(p_phone)))
     and (scope = 'customer' or x.item_id = p_item);
  return n;
end $$;

-- one complaint as JSON. The phone is masked unless the caller may see it for that outlet.
create or replace function public._crmh_row(cx public.crm_complaints) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ret jsonb; st text;
begin
  select jsonb_build_object('n', count(*), 'amount', coalesce(sum(r.amount), 0)) into ret
    from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id and r.status = 'done' where lr.complaint_id = cx.id;
  st := public._crmh_sla_state(cx.status, cx.due_at, cx.sla_met);
  return jsonb_build_object(
    'id', cx.id, 'ticket_no', cx.ticket_no, 'location_id', cx.location_id, 'location', (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = cx.location_id),
    'customer_id', cx.customer_id, 'customer_name', cx.customer_name,
    'customer_phone', case when public._crmh_phone_ok(cx.location_id) then cx.customer_phone else public._crmh_mask(cx.customer_phone) end,
    'sale_id', cx.sale_id, 'order_id', cx.order_id, 'item_id', cx.item_id,
    'item_name', (select coalesce(i.name_en, i.name_bn) from public.items i where i.id = cx.item_id),
    'category', cx.category, 'category_label', (select o.label_en from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.value_code = cx.category),
    'severity', cx.severity, 'food_safety', cx.food_safety, 'description', cx.description, 'batch_ref', cx.batch_ref,
    'status', cx.status, 'owner_user', cx.owner_user, 'owner_name', (select p.full_name from public.profiles p where p.id = cx.owner_user),
    'due_at', cx.due_at, 'first_response_at', cx.first_response_at, 'resolved_at', cx.resolved_at, 'resolution_type', cx.resolution_type, 'resolution_note', cx.resolution_note,
    'closed_at', cx.closed_at, 'close_reason', cx.close_reason,
    'sla_state', st, 'sla_met', cx.sla_met, 'breached_at', cx.breached_at,
    'minutes_left', case when st in ('running', 'overdue') then floor(extract(epoch from (cx.due_at - now())) / 60)::int end,
    'repeat_flag', cx.repeat_flag, 'repeat_count', cx.repeat_count, 'returns', ret,
    'created_by', cx.created_by, 'created_staff', cx.created_staff, 'created_at', cx.created_at, 'updated_at', cx.updated_at);
end $$;

-- ============================================================================
-- 6. API
-- ============================================================================
-- 6.1 log a complaint. p keys: location_id, sale_id, order_id, item_id, customer_id, customer_name, customer_phone, category, severity, food_safety, description, batch_ref, owner_user
create or replace function public._crmh_complaint_save(p_client uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); cx public.crm_complaints; s public.sales; o public.online_orders; cu public.customers; it public.items;
        loc int; sale_ uuid; ord_ uuid; item_ uuid; cust_ uuid; cat text; sev text; fs boolean; descr text; nm text; ph text; batch text; own uuid;
        fs_cats text[]; hrs numeric; due timestamptz; prior int := 0; rmin int; rflag boolean := false; fs_min text; t0 timestamptz := now(); item_name text := 'no item named';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_input'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if p_client is not null then
    select * into cx from public.crm_complaints where client_id = p_client;
    if found then
      if cx.created_by is distinct from uid and not public._crmh_manage_ok(cx.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', cx.id, 'ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'food_safety', cx.food_safety, 'repeat_flag', cx.repeat_flag);
    end if;
  end if;
  sale_ := public._crmh_j_uuid(p, 'sale_id'); ord_ := public._crmh_j_uuid(p, 'order_id'); item_ := public._crmh_j_uuid(p, 'item_id');
  cust_ := public._crmh_j_uuid(p, 'customer_id'); own := public._crmh_j_uuid(p, 'owner_user');
  cat := nullif(btrim(p ->> 'category'), ''); sev := coalesce(nullif(btrim(p ->> 'severity'), ''), 'medium');
  descr := btrim(coalesce(p ->> 'description', '')); nm := nullif(btrim(coalesce(p ->> 'customer_name', '')), ''); ph := nullif(btrim(coalesce(p ->> 'customer_phone', '')), '');
  batch := nullif(btrim(coalesce(p ->> 'batch_ref', '')), ''); fs := public._crmh_j_bool(p, 'food_safety');
  if sev not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  if char_length(descr) < 3 or char_length(descr) > 1000 then raise exception 'description_required'; end if;
  if cat is null or not exists (select 1 from public.option_lists where list_code = 'crm_complaint_cats' and value_code = cat and active) then raise exception 'bad_category'; end if;
  if nm is not null and char_length(nm) > 80 then raise exception 'bad_name'; end if;
  if ph is not null and ph !~ '^[0-9+ -]{6,20}$' then raise exception 'bad_phone'; end if;
  if batch is not null and char_length(batch) > 60 then raise exception 'bad_batch'; end if;
  -- the outlet comes from the sale or the order when one is given; the caller cannot name a different outlet
  if nullif(p ->> 'location_id', '') is not null and (p ->> 'location_id') !~ '^[0-9]{1,9}$' then raise exception 'bad_location'; end if;
  loc := nullif(p ->> 'location_id', '')::int;
  if sale_ is not null then
    select * into s from public.sales where id = sale_;
    if not found then raise exception 'sale_not_found'; end if;
    if loc is not null and loc <> s.location_id then raise exception 'sale_other_outlet'; end if;
    loc := s.location_id; if cust_ is null then cust_ := s.customer_id; end if;
  end if;
  if ord_ is not null then
    select * into o from public.online_orders where id = ord_;
    if not found then raise exception 'order_not_found'; end if;
    if loc is not null and loc <> o.location_id then raise exception 'order_other_outlet'; end if;
    loc := o.location_id;
    if sale_ is null and o.sale_id is not null then sale_ := o.sale_id; select * into s from public.sales where id = sale_; end if;
    if nm is null then nm := left(o.customer_name, 80); end if; if ph is null and o.customer_mobile ~ '^[0-9+ -]{6,20}$' then ph := o.customer_mobile; end if;
  end if;
  if loc is null then raise exception 'location_required'; end if;
  if not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'bad_location'; end if;
  if not public._crmh_log_ok(loc) then raise exception 'not allowed'; end if;
  if item_ is not null then
    select * into it from public.items where id = item_;
    if not found then raise exception 'item_not_found'; end if;
    item_name := coalesce(it.name_en, it.name_bn);
    if sale_ is not null and jsonb_typeof(s.lines) = 'array' and jsonb_array_length(s.lines) > 0
       and not exists (select 1 from jsonb_array_elements(s.lines) e where e ->> 'item_id' = item_::text) then raise exception 'item_not_in_sale'; end if;
  end if;
  if cust_ is not null then
    select * into cu from public.customers where id = cust_;
    if not found then raise exception 'customer_not_found'; end if;
    if nm is null then nm := left(cu.name, 80); end if; if ph is null and cu.mobile ~ '^[0-9+ -]{6,20}$' then ph := cu.mobile; end if;
  end if;
  if own is not null then
    if not public._crmh_manage_ok(loc) then raise exception 'not allowed'; end if;
    if not public._crmh_user_loc_ok(own, loc) then raise exception 'owner_other_outlet'; end if;
  end if;
  -- food safety: the box, or a category the owner listed
  fs_cats := string_to_array(replace(coalesce(public.rule_txt('crm_complaint_fs_categories'), ''), ' ', ''), ',');
  if cat = any (fs_cats) then fs := true; end if;
  fs_min := coalesce(public.rule_txt('crm_complaint_fs_severity'), 'keep');
  if fs and fs_min = 'high' and sev in ('low', 'medium') then sev := 'high'; end if;
  if fs and fs_min = 'critical' then sev := 'critical'; end if;
  hrs := public._crmh_sla_hours(sev);
  due := case when hrs is null then null else t0 + hrs * interval '1 hour' end;
  -- repeat check (off while crm_repeat_days is blank)
  prior := public._crmh_repeat_prior(cust_, ph, item_, t0);
  rmin := coalesce(public.rule_num('crm_repeat_min'), 2)::int;
  rflag := public.rule_num('crm_repeat_days') is not null and (prior + 1) >= rmin;
  insert into public.crm_complaints (client_id, location_id, customer_id, customer_name, customer_phone, sale_id, order_id, item_id, category, severity, food_safety, description, batch_ref,
                                     status, owner_user, due_at, repeat_flag, repeat_count, created_by, created_staff, created_at)
    values (p_client, loc, cust_, nm, ph, sale_, ord_, item_, cat, sev, fs, descr, batch, 'open', own, due, rflag, prior, uid, public._crmh_staff(), t0)
    returning * into cx;
  perform public._crmh_ev(cx.id, 'created', null, 'open', descr);
  if own is not null then perform public._crmh_ev(cx.id, 'assigned', null, null, 'owner set when logged'); end if;
  if fs then
    perform public._crmh_ev(cx.id, 'food_safety', null, null, 'marked food safety');
    if public.rule_on('crm_complaint_fs_exception_on') then
      perform public._crmh_exc(loc, 'crmh_food_safety', 'red', 'Food-safety complaint no. ' || cx.ticket_no || ' (' || item_name || ')', cx.id::text);
    end if;
  end if;
  if rflag then perform public._crmh_ev(cx.id, 'repeat', null, null, 'repeat complaint: ' || prior || ' earlier in the last ' || public.rule_num('crm_repeat_days')::int || ' days'); end if;
  perform public._crmh_audit('crmh_complaint_new', cx.id::text, jsonb_build_object('ticket_no', cx.ticket_no, 'severity', sev, 'food_safety', fs, 'repeat', rflag));
  return jsonb_build_object('dup', false, 'id', cx.id, 'ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'severity', sev, 'food_safety', fs, 'repeat_flag', rflag, 'repeat_count', prior);
end $function$;

-- 6.2 set (or clear) the person who owns a complaint
create or replace function public._crmh_complaint_assign(p_id uuid, p_user uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status not in ('open', 'in_progress') then raise exception 'complaint_locked'; end if;
  if p_user is not null and not public._crmh_user_loc_ok(p_user, cx.location_id) then raise exception 'owner_other_outlet'; end if;
  if cx.owner_user is not distinct from p_user then return public._crmh_row(cx); end if;
  update public.crm_complaints set owner_user = p_user where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'assigned', null, null, coalesce(nullif(btrim(p_note), ''), case when p_user is null then 'owner cleared' else 'owner set' end));
  return public._crmh_row(cx);
end $function$;

-- 6.3 add a note, or record that the customer was contacted (the first contact stops the "first response" clock)
create or replace function public._crmh_complaint_note(p_id uuid, p_kind text, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; b text := btrim(coalesce(p_body, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind not in ('note', 'contact') then raise exception 'bad_kind'; end if;
  if char_length(b) < 3 or char_length(b) > 1000 then raise exception 'note_required'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not (public._crmh_manage_ok(cx.location_id) or (coalesce(cx.owner_user = auth.uid(), false) and public.can_loc(cx.location_id))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if p_kind = 'contact' and cx.first_response_at is null then update public.crm_complaints set first_response_at = now() where id = p_id returning * into cx; end if;
  perform public._crmh_ev(cx.id, p_kind, null, null, b);
  return public._crmh_row(cx);
end $function$;

-- marks one overdue complaint (no new status; breached_at + one event + one yellow Exceptions line when the setting is ON)
create or replace function public._crmh_mark_breach(p_id uuid) returns boolean language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints;
begin
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found or cx.breached_at is not null or cx.due_at is null or now() <= cx.due_at then return false; end if;
  update public.crm_complaints set breached_at = now() where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'sla_breach', cx.status, cx.status, 'target was ' || to_char(cx.due_at at time zone 'Asia/Dhaka', 'DD Mon HH24:MI'));
  perform public._crmh_audit('crmh_sla_breach', cx.id::text, jsonb_build_object('ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'severity', cx.severity));
  if public.rule_on('crm_complaint_breach_exception_on') then
    perform public._crmh_exc(cx.location_id, 'crmh_sla_breach', case when cx.food_safety then 'red' else 'yellow' end, 'Complaint no. ' || cx.ticket_no || ' is overdue (' || cx.severity || ')', cx.id::text);
  end if;
  return true;
end $function$;

-- 6.4 move a complaint along. p_to: in_progress | resolved | closed | closed_no_resolution | in_progress again from resolved (reopen)
create or replace function public._crmh_complaint_move(p_id uuid, p_to text, p_note text default null, p_resolution text default null, p_close_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; uid uuid := auth.uid(); b text := btrim(coalesce(p_note, '')); mgr boolean; own boolean; from_ text; met boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_to not in ('in_progress', 'resolved', 'closed', 'closed_no_resolution') then raise exception 'illegal_status_change'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  mgr := public._crmh_manage_ok(cx.location_id); own := coalesce(cx.owner_user = uid, false) and public.can_loc(cx.location_id);
  if not (mgr or own) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  from_ := cx.status;
  if not ((from_ = 'open' and p_to in ('in_progress', 'resolved', 'closed_no_resolution'))
       or (from_ = 'in_progress' and p_to in ('resolved', 'closed_no_resolution'))
       or (from_ = 'resolved' and p_to in ('closed', 'in_progress'))) then raise exception 'illegal_status_change'; end if;
  -- the person who only owns the complaint may start it and resolve it; closing, closing without a result and reopening are for the managers
  if not mgr and p_to in ('closed', 'closed_no_resolution') then raise exception 'not allowed'; end if;
  if not mgr and from_ = 'resolved' then raise exception 'not allowed'; end if;

  if p_to = 'in_progress' and from_ = 'open' then
    update public.crm_complaints set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), owner_user = coalesce(owner_user, uid) where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'in_progress', nullif(b, ''));
  elsif p_to = 'in_progress' then                                           -- reopen a resolved complaint: needs a reason
    if char_length(b) < 3 then raise exception 'reason_required'; end if;
    update public.crm_complaints set status = 'in_progress', resolved_at = null, resolution_type = null, resolution_note = null, sla_met = null where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'reopen', from_, 'in_progress', b);
    perform public._crmh_audit('crmh_complaint_reopen', cx.id::text, jsonb_build_object('reason', b));
  elsif p_to = 'resolved' then
    if p_resolution is null or not exists (select 1 from public.option_lists where list_code = 'crm_resolution_types' and value_code = p_resolution and active) or char_length(b) < 3 then raise exception 'resolution_required'; end if;
    met := case when cx.due_at is null then null else now() <= cx.due_at end;
    update public.crm_complaints set status = 'resolved', resolved_at = now(), resolution_type = p_resolution, resolution_note = left(b, 1000), sla_met = met,
           first_response_at = coalesce(first_response_at, now()) where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'resolved', b);
    if met is false then perform public._crmh_mark_breach(cx.id); select * into cx from public.crm_complaints where id = p_id; end if;
  elsif p_to = 'closed' then
    update public.crm_complaints set status = 'closed', closed_at = now() where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'closed', nullif(b, ''));
  else                                                                       -- closed_no_resolution: an exception with a reason (owner rule 3)
    if p_close_reason is null or not exists (select 1 from public.option_lists where list_code = 'crm_close_reasons' and value_code = p_close_reason and active) or char_length(b) < 3 then raise exception 'reason_required'; end if;
    update public.crm_complaints set status = 'closed_no_resolution', closed_at = now(), close_reason = p_close_reason, sla_met = null where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'closed_no_resolution', p_close_reason || ': ' || b);
    perform public._crmh_audit('crmh_closed_no_resolution', cx.id::text, jsonb_build_object('reason_code', p_close_reason, 'note', b, 'food_safety', cx.food_safety));
    perform public._crmh_exc(cx.location_id, 'crmh_closed_unresolved', case when cx.food_safety then 'red' else 'yellow' end,
                             'Complaint no. ' || cx.ticket_no || ' closed without a result (' || p_close_reason || ')', cx.id::text);
  end if;
  return public._crmh_row(cx);
end $function$;

-- 6.5 change the severity (the clock restarts from the time the complaint was logged, with the new target)
create or replace function public._crmh_complaint_severity_set(p_id uuid, p_severity text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; hrs numeric; b text := btrim(coalesce(p_note, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if cx.severity = p_severity then return public._crmh_row(cx); end if;
  if char_length(b) < 3 then raise exception 'reason_required'; end if;
  hrs := public._crmh_sla_hours(p_severity);
  update public.crm_complaints set severity = p_severity, due_at = case when hrs is null then null else created_at + hrs * interval '1 hour' end where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'severity', null, null, cx.severity || ': ' || b);
  perform public._crmh_audit('crmh_severity_change', cx.id::text, jsonb_build_object('to', p_severity, 'reason', b));
  return public._crmh_row(cx);
end $function$;

-- 6.6 link a finished sale return to a complaint. READ ONLY on sale_returns: no refund is made, nothing is posted. The refund is made on the sale return screen first.
create or replace function public._crmh_complaint_link_return(p_id uuid, p_return uuid) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; r public.sale_returns; other uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  select * into r from public.sale_returns where id = p_return;
  if not found then raise exception 'return_not_found'; end if;
  if r.status <> 'done' then raise exception 'return_not_done'; end if;
  if r.location_id <> cx.location_id then raise exception 'return_other_outlet'; end if;
  if cx.sale_id is not null and cx.sale_id <> r.sale_id then raise exception 'return_other_sale'; end if;
  select complaint_id into other from public.crm_complaint_returns where return_id = p_return;
  if other is not null then
    if other = p_id then return public._crmh_row(cx); end if;
    raise exception 'return_already_linked';
  end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  insert into public.crm_complaint_returns (complaint_id, return_id, linked_by) values (p_id, p_return, auth.uid());
  if cx.sale_id is null then update public.crm_complaints set sale_id = r.sale_id where id = p_id returning * into cx; end if;
  perform public._crmh_ev(cx.id, 'link_return', null, null, 'sale return linked, value ' || r.amount);
  perform public._crmh_audit('crmh_link_return', cx.id::text, jsonb_build_object('return_id', p_return, 'amount', r.amount));
  return public._crmh_row(cx);
end $function$;

-- 6.7 the list. p keys: status (active | all | open | in_progress | resolved | closed | closed_no_resolution; default active), location_id, severity, food_safety, overdue, mine, repeat, item_id, customer_id, from, to, limit, offset
create or replace function public._crmh_complaint_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); st text := coalesce(nullif(p ->> 'status', ''), 'active'); loc int := nullif(p ->> 'location_id', '')::int; sev text := nullif(p ->> 'severity', '');
        d1 date := nullif(p ->> 'from', '')::date; d2 date := nullif(p ->> 'to', '')::date; lim int := least(greatest(coalesce(nullif(p ->> 'limit', '')::int, 30), 1), 100); off_ int := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
        item_ uuid := public._crmh_j_uuid(p, 'item_id'); cust_ uuid := public._crmh_j_uuid(p, 'customer_id'); rows jsonb; total int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if st not in ('active', 'all', 'open', 'in_progress', 'resolved', 'closed', 'closed_no_resolution') then raise exception 'bad_status'; end if;
  if sev is not null and sev not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  with f as (
    select x.* from public.crm_complaints x
     where (public._crmh_view_ok(x.location_id) or x.created_by = uid or (x.owner_user = uid and public.can_loc(x.location_id)))
       and (loc is null or x.location_id = loc)
       and (st = 'all' or (st = 'active' and x.status in ('open', 'in_progress')) or x.status = st)
       and (sev is null or x.severity = sev)
       and (not public._crmh_j_bool(p, 'food_safety') or x.food_safety)
       and (not public._crmh_j_bool(p, 'repeat') or x.repeat_flag)
       and (not public._crmh_j_bool(p, 'mine') or x.owner_user = uid)
       and (not public._crmh_j_bool(p, 'overdue') or (x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at))
       and (item_ is null or x.item_id = item_) and (cust_ is null or x.customer_id = cust_)
       and (d1 is null or (x.created_at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.created_at at time zone 'Asia/Dhaka')::date <= d2)),
  pg as (
    select f.id, row_number() over (order by case when f.status in ('open', 'in_progress') and f.due_at is not null and now() > f.due_at then 0 when f.food_safety and f.status in ('open', 'in_progress') then 1 else 2 end,
                                             f.due_at nulls last, f.created_at desc) as ord
      from f order by ord limit lim offset off_)
  select (select count(*) from f), coalesce((select jsonb_agg(public._crmh_row(c2) order by pg.ord) from pg join public.crm_complaints c2 on c2.id = pg.id), '[]'::jsonb) into total, rows;
  return jsonb_build_object('total', total, 'rows', rows, 'limit', lim, 'offset', off_, 'on', public.rule_on('crm_complaints_on'));
end $function$;

-- 6.8 one complaint with its trail and the linked returns. Also tells the screen which existing sale return to open (the refund is made THERE).
create or replace function public._crmh_complaint_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare cx public.crm_complaints; uid uuid := auth.uid(); ev jsonb; rets jsonb; hint jsonb := null; prev jsonb; s public.sales;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id;
  if not found then raise exception 'complaint_not_found'; end if;
  if not (public._crmh_view_ok(cx.location_id) or cx.created_by = uid or (coalesce(cx.owner_user = uid, false) and public.can_loc(cx.location_id))) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev
    from public.crm_complaint_events e where e.complaint_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('return_id', r.id, 'amount', r.amount, 'refund', r.refund_amount, 'credit', r.credit_amount, 'status', r.status, 'at', r.created_at) order by lr.id), '[]'::jsonb) into rets
    from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id where lr.complaint_id = p_id;
  if cx.sale_id is not null then
    select * into s from public.sales where id = cx.sale_id;
    hint := jsonb_build_object('sale_id', s.id, 'receipt', s.receipt, 'sold_at', s.sold_at, 'total', s.total,
                               'can_return', public.has_grant('sale_return', s.location_id), 'open', 'B.saleReturn.open(sale_id)',
                               'note', 'Make the refund on the sale return screen first, then link the finished return here. This screen never refunds.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'ticket_no', x.ticket_no, 'at', x.created_at, 'status', x.status, 'category', x.category) order by x.created_at desc), '[]'::jsonb) into prev
    from (select * from public.crm_complaints z where z.id <> p_id and z.created_at < cx.created_at
            and ((cx.customer_id is not null and z.customer_id = cx.customer_id)
                 or (nullif(public.norm_mobile(cx.customer_phone), '') is not null and public.norm_mobile(z.customer_phone) = public.norm_mobile(cx.customer_phone)))
            and (public._crmh_view_ok(z.location_id) or z.created_by = uid)
          order by z.created_at desc limit 10) x;
  return jsonb_build_object('complaint', public._crmh_row(cx), 'events', ev, 'returns', rets, 'return_hint', hint, 'earlier_by_same_customer', prev,
                            'can_manage', public._crmh_manage_ok(cx.location_id));
end $function$;

-- 6.9 the overdue check. Marks every open complaint that has passed its due time (once each). A dry run writes nothing and works while the switch is OFF.
--     Called by the owner, by a holder of crm_complaint_manage (their outlets only), by the notify bot (see docs/integration/CRM-H.md), or by the database's own scheduler.
create or replace function public._crmh_sla_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); via text; r record; n int := 0; ids jsonb := '[]'::jsonb; all_ boolean := false;
begin
  if uid is not null then
    all_ := public._is_ops('notify') or public.is_owner();
    if not (all_ or (public.is_active() and exists (select 1 from public.locations l where public._crmh_manage_ok(l.id)))) then raise exception 'not allowed'; end if;
    via := case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  else
    if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
    all_ := true; via := 'database_scheduler';
  end if;
  if not p_dry and not public.rule_on('crm_complaints_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  for r in select x.id, x.ticket_no, x.location_id from public.crm_complaints x
            where x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at and x.breached_at is null
              and (all_ or public._crmh_manage_ok(x.location_id)) order by x.due_at loop
    if p_dry then n := n + 1; ids := ids || to_jsonb(r.ticket_no);
    elsif public._crmh_mark_breach(r.id) then n := n + 1; ids := ids || to_jsonb(r.ticket_no); end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'dry', p_dry, 'marked', n, 'tickets', ids, 'via', via);
end $function$;

-- 6.10 small numbers for a badge (only the outlets the caller may see)
create or replace function public._crmh_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); r record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select count(*) filter (where x.status in ('open', 'in_progress')) as open_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at) as overdue_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.food_safety) as fs_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.repeat_flag) as repeat_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.owner_user is null) as unowned_n
    into r from public.crm_complaints x where public._crmh_view_ok(x.location_id) or x.created_by = uid or (x.owner_user = uid and public.can_loc(x.location_id));
  return jsonb_build_object('on', public.rule_on('crm_complaints_on'), 'open', r.open_n, 'overdue', r.overdue_n, 'food_safety', r.fs_n, 'repeat', r.repeat_n, 'unowned', r.unowned_n);
end $function$;

-- 6.11 the effective settings and lists, for the screen
create or replace function public._crmh_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'on', public.rule_on('crm_complaints_on'),
    'sla_hours', jsonb_build_object('low', public._crmh_sla_hours('low'), 'medium', public._crmh_sla_hours('medium'), 'high', public._crmh_sla_hours('high'), 'critical', public._crmh_sla_hours('critical')),
    'fs_exception_on', public.rule_on('crm_complaint_fs_exception_on'), 'fs_categories', public.rule_txt('crm_complaint_fs_categories'), 'fs_severity', coalesce(public.rule_txt('crm_complaint_fs_severity'), 'keep'),
    'breach_exception_on', public.rule_on('crm_complaint_breach_exception_on'),
    'repeat_days', public.rule_num('crm_repeat_days'), 'repeat_min', coalesce(public.rule_num('crm_repeat_min'), 2), 'repeat_scope', coalesce(public.rule_txt('crm_repeat_scope'), 'customer_item'),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.active),
    'resolutions', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_resolution_types' and o.active),
    'close_reasons', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_close_reasons' and o.active),
    'may_log', exists (select 1 from public.locations l where l.is_active and public._crmh_log_ok(l.id)),
    'may_manage', exists (select 1 from public.locations l where l.is_active and public._crmh_manage_ok(l.id)),
    'may_view', exists (select 1 from public.locations l where l.is_active and public._crmh_view_ok(l.id)),
    'is_owner', public.is_owner());
end $function$;

-- ============================================================================
-- 7. PRIVILEGES: helpers closed to browsers; the API is open to signed-in users only (each function checks its own right)
-- ============================================================================
revoke all on function public._crmh_present(), public._crmh_append_only(), public._crmh_complaint_guard(), public._crmh_staff(), public._crmh_log_ok(int), public._crmh_manage_ok(int), public._crmh_view_ok(int),
  public._crmh_phone_ok(int), public._crmh_mask(text), public._crmh_j_uuid(jsonb, text), public._crmh_j_bool(jsonb, text), public._crmh_sla_hours(text), public._crmh_sla_state(text, timestamptz, boolean),
  public._crmh_ev(uuid, text, text, text, text), public._crmh_audit(text, text, jsonb), public._crmh_exc(int, text, text, text, text), public._crmh_user_loc_ok(uuid, int),
  public._crmh_repeat_prior(uuid, text, uuid, timestamptz), public._crmh_row(public.crm_complaints), public._crmh_mark_breach(uuid) from public, anon, authenticated;
revoke all on function public._crmh_complaint_save(uuid, jsonb), public._crmh_complaint_assign(uuid, uuid, text), public._crmh_complaint_note(uuid, text, text),
  public._crmh_complaint_move(uuid, text, text, text, text), public._crmh_complaint_severity_set(uuid, text, text), public._crmh_complaint_link_return(uuid, uuid),
  public._crmh_complaint_list(jsonb), public._crmh_complaint_get(uuid), public._crmh_sla_scan(boolean), public._crmh_counts(), public._crmh_settings() from public, anon, authenticated;
grant execute on function public._crmh_complaint_save(uuid, jsonb), public._crmh_complaint_assign(uuid, uuid, text), public._crmh_complaint_note(uuid, text, text),
  public._crmh_complaint_move(uuid, text, text, text, text), public._crmh_complaint_severity_set(uuid, text, text), public._crmh_complaint_link_return(uuid, uuid),
  public._crmh_complaint_list(jsonb), public._crmh_complaint_get(uuid), public._crmh_sla_scan(boolean), public._crmh_counts(), public._crmh_settings() to authenticated;

-- ---------------------------------------------------------------- phase329.sql
-- Phase 329 (bos329, package CRM-H, part 2 of 2: label 129) - RATINGS, REPEAT-COMPLAINT LIST, COMPLAINTS AND RATINGS REPORT.
-- Paste AFTER phase328 (it reads the complaint tables and helpers of that file). Paste-twice safe. No earlier file is edited, no shared function is re-created.
-- If phase328 is pasted again later, paste this file again too (it only adds; nothing in it is replaced by phase328).
--
-- WHAT THIS FILE ADDS
--   1. Settings: crm_feedback_on (OFF), crm_feedback_low_max (blank), crm_feedback_window_days (blank).
--   2. crm_feedback: one star rating (1..5) with a comment, linked to ONE sale or online order. One rating per sale and per order.
--   3. API (all _crmh_*): _crmh_feedback_add, _crmh_feedback_followup, _crmh_feedback_to_complaint, _crmh_feedback_list, _crmh_feedback_settings,
--      _crmh_repeat_list, _crmh_report
-- ACCOUNTING: a rating posts nothing and changes no sale. Turning a low rating into a complaint creates a complaint only, never a refund.
-- DEFAULTS: with crm_feedback_on OFF the write functions answer 'feedback_off'. The report and lists are read only and work for people who hold the right.

do $g$ begin
  if to_regprocedure('public._crmh_present()') is null or to_regclass('public.crm_complaints') is null or to_regprocedure('public._crmh_complaint_save(uuid,jsonb)') is null then
    raise exception 'phase329 needs phase328 first';
  end if;
end $g$;

-- ============================================================================
-- 1. SETTINGS
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_feedback_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
  'Record customer ratings (1 to 5 stars) for a sale or order',
  'OFF = nothing changes (today). ON = staff can record a star rating and a short comment for a sale or an online order. One rating per sale. A rating posts no money.', 1295),
 ('crm_feedback_low_max', 'number', null, 'stars', null, 1, 4,
  'A rating at or below this many stars needs a follow-up call',
  'Blank = no rating needs a call (today). For example 2 = a 1 or 2 star rating is put on the "needs a call" list until someone records the call.', 1296),
 ('crm_feedback_window_days', 'number', null, 'days', null, 1, 3650,
  'Accept a rating only for a sale made in the last this many days',
  'Blank = any age. A number refuses a rating for a sale or order older than that.', 1297)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.crm_feedback (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  sale_id uuid references public.sales(id),
  order_id uuid references public.online_orders(id),
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500),
  channel text not null default 'counter' check (channel in ('counter', 'phone', 'message', 'other')),
  follow_up text not null default 'none' check (follow_up in ('none', 'needed', 'done')),
  follow_up_note text check (follow_up_note is null or char_length(follow_up_note) <= 500), follow_up_by uuid, follow_up_at timestamptz,
  complaint_id uuid references public.crm_complaints(id),
  collected_by uuid not null, collected_staff text, at timestamptz not null default now(),
  check (sale_id is not null or order_id is not null)
);
create unique index if not exists crm_feedback_one_per_sale on public.crm_feedback (sale_id) where sale_id is not null;
create unique index if not exists crm_feedback_one_per_order on public.crm_feedback (order_id) where order_id is not null;
create index if not exists crm_feedback_loc_at on public.crm_feedback (location_id, at desc);
create index if not exists crm_feedback_followup on public.crm_feedback (location_id) where follow_up = 'needed';

drop trigger if exists crm_feedback_nodel on public.crm_feedback;
create trigger crm_feedback_nodel before delete on public.crm_feedback for each row execute function public.no_hard_delete();
alter table public.crm_feedback enable row level security;
revoke all on public.crm_feedback from public, anon, authenticated;
drop trigger if exists audit_crm_feedback on public.crm_feedback;
create trigger audit_crm_feedback after insert or update on public.crm_feedback for each row execute function public.log_change('id');

-- a rating is a record: only the follow-up fields and the complaint link may change, and a follow-up never goes back
create or replace function public._crmh_feedback_guard() returns trigger language plpgsql as $$
begin
  if new.id is distinct from old.id or new.client_id is distinct from old.client_id or new.location_id is distinct from old.location_id or new.customer_id is distinct from old.customer_id
     or new.sale_id is distinct from old.sale_id or new.order_id is distinct from old.order_id or new.rating is distinct from old.rating or new.comment is distinct from old.comment
     or new.channel is distinct from old.channel or new.collected_by is distinct from old.collected_by or new.at is distinct from old.at then
    raise exception 'feedback_immutable';
  end if;
  if old.follow_up = 'done' and new.follow_up is distinct from 'done' then raise exception 'illegal_status_change'; end if;
  if old.follow_up = 'none' and new.follow_up is distinct from 'none' then raise exception 'illegal_status_change'; end if;
  if old.follow_up = 'needed' and new.follow_up = 'none' then raise exception 'illegal_status_change'; end if;
  if old.complaint_id is not null and new.complaint_id is distinct from old.complaint_id then raise exception 'feedback_immutable'; end if;
  return new;
end $$;
drop trigger if exists crm_feedback_guard on public.crm_feedback;
create trigger crm_feedback_guard before update on public.crm_feedback for each row execute function public._crmh_feedback_guard();

-- ============================================================================
-- 3. API
-- ============================================================================
-- 3.1 record a rating. p keys: sale_id and/or order_id, rating (1..5), comment, channel (counter | phone | message | other), customer_id
create or replace function public._crmh_feedback_add(p_client uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); f public.crm_feedback; s public.sales; o public.online_orders; sale_ uuid; ord_ uuid; cust_ uuid; loc int; rt int; cm text; ch text; low numeric; win numeric; fu text := 'none'; t_when timestamptz;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_input'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if p_client is not null then
    select * into f from public.crm_feedback where client_id = p_client;
    if found then
      if f.collected_by is distinct from uid and not public._crmh_manage_ok(f.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', f.id, 'follow_up', f.follow_up);
    end if;
  end if;
  sale_ := public._crmh_j_uuid(p, 'sale_id'); ord_ := public._crmh_j_uuid(p, 'order_id'); cust_ := public._crmh_j_uuid(p, 'customer_id');
  if coalesce(p ->> 'rating', '') !~ '^[1-5]$' then raise exception 'bad_rating'; end if;
  rt := (p ->> 'rating')::int;
  cm := nullif(btrim(coalesce(p ->> 'comment', '')), ''); if cm is not null and char_length(cm) > 500 then raise exception 'bad_comment'; end if;
  ch := coalesce(nullif(btrim(p ->> 'channel'), ''), 'counter'); if ch not in ('counter', 'phone', 'message', 'other') then raise exception 'bad_channel'; end if;
  if sale_ is null and ord_ is null then raise exception 'sale_or_order_required'; end if;
  if ord_ is not null then
    select * into o from public.online_orders where id = ord_;
    if not found then raise exception 'order_not_found'; end if;
    if o.status = 'cancelled' then raise exception 'order_cancelled'; end if;
    if sale_ is not null and o.sale_id is not null and o.sale_id <> sale_ then raise exception 'order_sale_mismatch'; end if;
    if sale_ is null then sale_ := o.sale_id; end if;
    loc := o.location_id; t_when := o.created_at;
  end if;
  if sale_ is not null then
    select * into s from public.sales where id = sale_;
    if not found then raise exception 'sale_not_found'; end if;
    if loc is not null and loc <> s.location_id then raise exception 'sale_other_outlet'; end if;
    if s.status <> 'done' then raise exception 'sale_void'; end if;
    loc := s.location_id; t_when := s.sold_at; if cust_ is null then cust_ := s.customer_id; end if;
  end if;
  if not public._crmh_log_ok(loc) then raise exception 'not allowed'; end if;
  if cust_ is not null and not exists (select 1 from public.customers where id = cust_) then raise exception 'customer_not_found'; end if;
  win := public.rule_num('crm_feedback_window_days');
  if win is not null and t_when < now() - win * interval '1 day' then raise exception 'too_old'; end if;
  if (sale_ is not null and exists (select 1 from public.crm_feedback where sale_id = sale_)) or (ord_ is not null and exists (select 1 from public.crm_feedback where order_id = ord_)) then raise exception 'already_rated'; end if;
  low := public.rule_num('crm_feedback_low_max');
  if low is not null and rt <= low then fu := 'needed'; end if;
  insert into public.crm_feedback (client_id, location_id, customer_id, sale_id, order_id, rating, comment, channel, follow_up, collected_by, collected_staff)
    values (p_client, loc, cust_, sale_, ord_, rt, cm, ch, fu, uid, public._crmh_staff()) returning * into f;
  perform public._crmh_audit('crmh_rating_new', f.id::text, jsonb_build_object('rating', rt, 'follow_up', fu));
  return jsonb_build_object('dup', false, 'id', f.id, 'rating', rt, 'follow_up', fu);
end $function$;

-- 3.2 record that the follow-up call was made (only when one was needed)
create or replace function public._crmh_feedback_followup(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare f public.crm_feedback; b text := btrim(coalesce(p_note, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into f from public.crm_feedback where id = p_id for update;
  if not found then raise exception 'feedback_not_found'; end if;
  if not public._crmh_manage_ok(f.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if f.follow_up = 'done' then return jsonb_build_object('dup', true, 'id', f.id, 'follow_up', 'done'); end if;
  if f.follow_up <> 'needed' then raise exception 'no_follow_up_needed'; end if;
  if char_length(b) < 3 or char_length(b) > 500 then raise exception 'note_required'; end if;
  update public.crm_feedback set follow_up = 'done', follow_up_note = b, follow_up_by = auth.uid(), follow_up_at = now() where id = p_id returning * into f;
  perform public._crmh_audit('crmh_rating_followup', f.id::text, jsonb_build_object('note', b));
  return jsonb_build_object('dup', false, 'id', f.id, 'follow_up', f.follow_up);
end $function$;

-- 3.3 open a complaint from a rating (the rating's sale / order and customer carry over). p keys: category, severity, description, item_id, food_safety. A complaint only: no refund.
create or replace function public._crmh_feedback_to_complaint(p_id uuid, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare f public.crm_feedback; res jsonb; p2 jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into f from public.crm_feedback where id = p_id for update;
  if not found then raise exception 'feedback_not_found'; end if;
  if not public._crmh_manage_ok(f.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_feedback_on') then raise exception 'feedback_off'; end if;
  if f.complaint_id is not null then return jsonb_build_object('dup', true, 'complaint_id', f.complaint_id); end if;
  p2 := coalesce(p, '{}'::jsonb) || jsonb_build_object('location_id', f.location_id, 'sale_id', f.sale_id, 'order_id', f.order_id, 'customer_id', f.customer_id);
  p2 := (select jsonb_object_agg(k, v) from jsonb_each(p2) e(k, v) where v <> 'null'::jsonb);
  if nullif(btrim(coalesce(p2 ->> 'description', '')), '') is null then p2 := p2 || jsonb_build_object('description', coalesce(f.comment, 'Rated ' || f.rating || ' of 5 stars')); end if;
  res := public._crmh_complaint_save(f.id, p2);                         -- the rating's own id is the client id: a second press returns the same complaint
  update public.crm_feedback set complaint_id = (res ->> 'id')::uuid,
         follow_up = case when follow_up = 'needed' then 'done' else follow_up end,
         follow_up_note = case when follow_up = 'needed' then 'Complaint opened' else follow_up_note end,
         follow_up_by = case when follow_up = 'needed' then auth.uid() else follow_up_by end,
         follow_up_at = case when follow_up = 'needed' then now() else follow_up_at end
   where id = p_id;
  return res || jsonb_build_object('complaint_id', res ->> 'id');
end $function$;

-- 3.4 the rating list with a small summary. p keys: location_id, rating_max, follow_up (none | needed | done), from, to, limit, offset
create or replace function public._crmh_feedback_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); loc int := nullif(p ->> 'location_id', '')::int; rmax int := nullif(p ->> 'rating_max', '')::int; fu text := nullif(p ->> 'follow_up', '');
        d1 date := nullif(p ->> 'from', '')::date; d2 date := nullif(p ->> 'to', '')::date; lim int := least(greatest(coalesce(nullif(p ->> 'limit', '')::int, 30), 1), 100); off_ int := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
        rows jsonb; sm record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if fu is not null and fu not in ('none', 'needed', 'done') then raise exception 'bad_status'; end if;
  with f as (
    select x.* from public.crm_feedback x
     where (public._crmh_view_ok(x.location_id) or x.collected_by = uid)
       and (loc is null or x.location_id = loc) and (rmax is null or x.rating <= rmax) and (fu is null or x.follow_up = fu)
       and (d1 is null or (x.at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.at at time zone 'Asia/Dhaka')::date <= d2))
  select count(*) as n, round(avg(rating), 2) as avg_r, count(*) filter (where follow_up = 'needed') as need_n into sm from f;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'at', z.at, 'location_id', z.location_id, 'location', (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = z.location_id),
         'rating', z.rating, 'comment', z.comment, 'channel', z.channel, 'sale_id', z.sale_id, 'receipt', (select s.receipt from public.sales s where s.id = z.sale_id),
         'order_id', z.order_id, 'order_no', (select o.order_no from public.online_orders o where o.id = z.order_id),
         'customer_id', z.customer_id, 'customer_name', (select c.name from public.customers c where c.id = z.customer_id),
         'follow_up', z.follow_up, 'follow_up_note', z.follow_up_note, 'complaint_id', z.complaint_id, 'by', z.collected_staff) order by z.at desc), '[]'::jsonb) into rows
    from (select x.* from public.crm_feedback x
           where (public._crmh_view_ok(x.location_id) or x.collected_by = uid)
             and (loc is null or x.location_id = loc) and (rmax is null or x.rating <= rmax) and (fu is null or x.follow_up = fu)
             and (d1 is null or (x.at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.at at time zone 'Asia/Dhaka')::date <= d2)
           order by x.at desc limit lim offset off_) z;
  return jsonb_build_object('total', sm.n, 'average', sm.avg_r, 'needs_call', sm.need_n, 'rows', rows, 'limit', lim, 'offset', off_, 'on', public.rule_on('crm_feedback_on'));
end $function$;

create or replace function public._crmh_feedback_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('crm_feedback_on'), 'low_max', public.rule_num('crm_feedback_low_max'), 'window_days', public.rule_num('crm_feedback_window_days'),
    'may_log', exists (select 1 from public.locations l where l.is_active and public._crmh_log_ok(l.id)),
    'may_manage', exists (select 1 from public.locations l where l.is_active and public._crmh_manage_ok(l.id)));
end $function$;

-- 3.5 repeat complaints: the same customer (and, by scope, the same item) with several complaints inside the window. p keys: days, min, scope, location_id
--     Uses the settings when a key is not given. With no days anywhere it answers 'days_required' (the check is off by default).
create or replace function public._crmh_repeat_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); days int := coalesce(nullif(p ->> 'days', '')::int, public.rule_num('crm_repeat_days')::int); mn int := coalesce(nullif(p ->> 'min', '')::int, public.rule_num('crm_repeat_min')::int, 2);
        sc text := coalesce(nullif(p ->> 'scope', ''), public.rule_txt('crm_repeat_scope'), 'customer_item'); loc int := nullif(p ->> 'location_id', '')::int; rows jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if days is null or days < 1 or days > 3650 then raise exception 'days_required'; end if;
  if sc not in ('customer_item', 'customer') then raise exception 'bad_scope'; end if;
  if mn < 2 then raise exception 'bad_min'; end if;
  with c as (
    select x.*, coalesce(x.customer_id::text, 'p:' || nullif(public.norm_mobile(x.customer_phone), '')) as ck
      from public.crm_complaints x
     where x.created_at >= now() - make_interval(days => days) and coalesce(x.close_reason, '') <> 'duplicate'
       and (public._crmh_view_ok(x.location_id) or x.created_by = uid) and (loc is null or x.location_id = loc)),
  g as (
    select ck, case when sc = 'customer_item' then item_id end as gi, count(*) as n, min(created_at) as first_at, max(created_at) as last_at,
           count(*) filter (where status in ('open', 'in_progress')) as open_n, count(distinct location_id) as outlets,
           (array_agg(ticket_no order by created_at desc))[1:10] as tickets, (array_agg(customer_name order by created_at desc))[1] as nm, (array_agg(customer_id order by created_at desc))[1] as cid
      from c where ck is not null and (sc = 'customer' or item_id is not null) group by ck, case when sc = 'customer_item' then item_id end having count(*) >= mn)
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', g.cid, 'customer_name', g.nm, 'item_id', g.gi, 'item_name', (select coalesce(i.name_en, i.name_bn) from public.items i where i.id = g.gi),
         'complaints', g.n, 'open', g.open_n, 'outlets', g.outlets, 'first_at', g.first_at, 'last_at', g.last_at, 'tickets', to_jsonb(g.tickets)) order by g.n desc, g.last_at desc), '[]'::jsonb) into rows from g;
  return jsonb_build_object('days', days, 'min', mn, 'scope', sc, 'rows', rows);
end $function$;

-- 3.6 the report. p keys: from, to (default: the last 30 days), by (outlet | item | category | severity | month | day; default outlet), location_id.
--     complaints: counts by status, overdue now, SLA met or missed, food safety, repeats, average hours to resolve, value of the linked sale returns.
--     ratings: count, average and 1..5 star counts, calls still needed. By item, a rating counts for every item on its sale or order. Only outlets the caller may view.
create or replace function public._crmh_report(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); d2 date := coalesce(nullif(p ->> 'to', '')::date, (now() at time zone 'Asia/Dhaka')::date); d1 date := coalesce(nullif(p ->> 'from', '')::date, (now() at time zone 'Asia/Dhaka')::date - 29);
        by_ text := coalesce(nullif(p ->> 'by', ''), 'outlet'); loc int := nullif(p ->> 'location_id', '')::int; cr jsonb; rr jsonb; tot jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if by_ not in ('outlet', 'item', 'category', 'severity', 'month', 'day') then raise exception 'bad_group'; end if;
  if d1 > d2 then raise exception 'bad_range'; end if;
  if d2 - d1 > 366 then raise exception 'range_too_long'; end if;
  if not exists (select 1 from public.locations l where public._crmh_view_ok(l.id)) then raise exception 'not allowed'; end if;

  with c as (
    select x.*, (x.created_at at time zone 'Asia/Dhaka')::date as dd,
           coalesce((select sum(r.amount) from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id and r.status = 'done' where lr.complaint_id = x.id), 0) as refund
      from public.crm_complaints x
     where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  k as (
    select c.*, case by_ when 'outlet' then c.location_id::text when 'item' then coalesce(c.item_id::text, 'none') when 'category' then c.category when 'severity' then c.severity
                         when 'month' then to_char(c.dd, 'YYYY-MM') else to_char(c.dd, 'YYYY-MM-DD') end as gk from c),
  g as (
    select gk, count(*) as total,
           count(*) filter (where status in ('open', 'in_progress')) as open_n, count(*) filter (where status in ('resolved', 'closed')) as resolved_n,
           count(*) filter (where status = 'closed_no_resolution') as closed_no_result_n,
           count(*) filter (where status in ('open', 'in_progress') and due_at is not null and now() > due_at) as overdue_now,
           count(*) filter (where breached_at is not null) as breached_n, count(*) filter (where sla_met is true) as sla_met_n, count(*) filter (where sla_met is false) as sla_missed_n,
           count(*) filter (where food_safety) as food_safety_n, count(*) filter (where repeat_flag) as repeat_n,
           round((avg(extract(epoch from (resolved_at - created_at))) filter (where resolved_at is not null) / 3600)::numeric, 1) as avg_resolve_hours,
           round(sum(refund), 2) as refund_total
      from k group by gk)
  select coalesce(jsonb_agg(jsonb_build_object('key', g.gk,
           'label', case by_ when 'outlet' then (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = g.gk::int)
                             when 'item' then coalesce((select coalesce(i.name_en, i.name_bn) from public.items i where i.id::text = g.gk), 'No item named')
                             when 'category' then coalesce((select o.label_en from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.value_code = g.gk), g.gk) else g.gk end,
           'total', g.total, 'open', g.open_n, 'resolved', g.resolved_n, 'closed_no_result', g.closed_no_result_n, 'overdue_now', g.overdue_now, 'breached', g.breached_n,
           'sla_met', g.sla_met_n, 'sla_missed', g.sla_missed_n, 'food_safety', g.food_safety_n, 'repeat', g.repeat_n, 'avg_resolve_hours', g.avg_resolve_hours, 'refund_total', g.refund_total)
           order by g.total desc, g.gk), '[]'::jsonb) into cr from g;

  if by_ in ('category', 'severity') then
    rr := '[]'::jsonb;
  else
    with fb as (
      select x.*, (x.at at time zone 'Asia/Dhaka')::date as dd from public.crm_feedback x
       where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2),
    fk as (
      select fb.id, fb.rating, fb.follow_up, case by_ when 'outlet' then fb.location_id::text when 'month' then to_char(fb.dd, 'YYYY-MM') when 'day' then to_char(fb.dd, 'YYYY-MM-DD') else it.item end as gk
        from fb
        left join lateral (
          select distinct e ->> 'item_id' as item
            from jsonb_array_elements(case when jsonb_typeof(coalesce((select s.lines from public.sales s where s.id = fb.sale_id), (select o.lines from public.online_orders o where o.id = fb.order_id))) = 'array'
                                           then coalesce((select s.lines from public.sales s where s.id = fb.sale_id), (select o.lines from public.online_orders o where o.id = fb.order_id)) else '[]'::jsonb end) e
           where by_ = 'item' and (e ->> 'item_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') it on by_ = 'item'),
    rg as (
      select gk, count(*) as n, round(avg(rating), 2) as avg_r, count(*) filter (where rating = 1) as r1, count(*) filter (where rating = 2) as r2, count(*) filter (where rating = 3) as r3,
             count(*) filter (where rating = 4) as r4, count(*) filter (where rating = 5) as r5, count(*) filter (where follow_up = 'needed') as need_n
        from fk where gk is not null group by gk)
    select coalesce(jsonb_agg(jsonb_build_object('key', rg.gk,
             'label', case by_ when 'outlet' then (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = rg.gk::int)
                               when 'item' then coalesce((select coalesce(i.name_en, i.name_bn) from public.items i where i.id::text = rg.gk), rg.gk) else rg.gk end,
             'n', rg.n, 'average', rg.avg_r, 'stars', jsonb_build_object('1', rg.r1, '2', rg.r2, '3', rg.r3, '4', rg.r4, '5', rg.r5), 'needs_call', rg.need_n) order by rg.n desc, rg.gk), '[]'::jsonb) into rr from rg;
  end if;

  select jsonb_build_object(
    'complaints', (select count(*) from public.crm_complaints x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.created_at at time zone 'Asia/Dhaka')::date between d1 and d2),
    'ratings', (select count(*) from public.crm_feedback x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2),
    'average_rating', (select round(avg(x.rating), 2) from public.crm_feedback x where public._crmh_view_ok(x.location_id) and (loc is null or x.location_id = loc) and (x.at at time zone 'Asia/Dhaka')::date between d1 and d2)) into tot;
  return jsonb_build_object('from', d1, 'to', d2, 'by', by_, 'complaints', cr, 'ratings', rr, 'totals', tot,
    'note', case when by_ = 'item' then 'Ratings are counted once for every item on the rated sale or order.' when by_ in ('category', 'severity') then 'Ratings have no category or severity.' else null end);
end $function$;

-- ============================================================================
-- 4. PRIVILEGES
-- ============================================================================
revoke all on function public._crmh_feedback_guard() from public, anon, authenticated;
revoke all on function public._crmh_feedback_add(uuid, jsonb), public._crmh_feedback_followup(uuid, text), public._crmh_feedback_to_complaint(uuid, jsonb), public._crmh_feedback_list(jsonb),
  public._crmh_feedback_settings(), public._crmh_repeat_list(jsonb), public._crmh_report(jsonb) from public, anon, authenticated;
grant execute on function public._crmh_feedback_add(uuid, jsonb), public._crmh_feedback_followup(uuid, text), public._crmh_feedback_to_complaint(uuid, jsonb), public._crmh_feedback_list(jsonb),
  public._crmh_feedback_settings(), public._crmh_repeat_list(jsonb), public._crmh_report(jsonb) to authenticated;

-- ---------------------------------------------------------------- phase400.sql
-- Phase 400 (bos400) - REPORTS: RETURNS AND REFUND CONSISTENCY (package RPT-B1, item R1). Paste after phase99. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md, defects D1 and D1b): the sales reports of the first report engine (report_run: sales_summary, sales_trend, sales_combined, item_sales, category_sales)
--      and the POS day close ignore sale returns, while the dashboard, the branch P&L and the margin report subtract them (rule reports_net_of_returns). The same day showed two different
--      sales figures. Worse, the POS day close "expected cash in drawer" ignores cash that was handed back to customers, so the drawer looked 400 over.
-- WHAT THIS FILE ADDS (read-only; nothing here writes to a business table, no existing column is changed or removed):
--   1. Three internal views of the DONE returns, shaped like the report fact views so the existing grouping, filters and compare keep working:
--        rpt_ret_b (one row per return), rpt_ret_l (one row per returned item line, with the discount share of the sale taken off, exactly like _cogs_lines72), rpt_ret_p (one row per refund payout).
--      A return is counted on the day it was made (Asia/Dhaka), the same rule as the dashboard (biz_daily, sales_summary). A voided return is not counted.
--   2. _rptb1_agg_wrap: used by the report engine (hook, see docs/integration/RPT-B1.md) to add NEW columns to the grouped reports:
--        sales_summary / sales_trend / sales_combined : returns_amt, net_after_returns
--        item_sales / category_sales                  : returns_amt, returns_qty, net_after_returns, qty_after_returns
--        payment_modes                                : refund_paid (money handed back by that payment mode), net_after_refunds
--      The old columns (net, qty, amount ...) keep exactly today's numbers. net_after_returns follows the rule reports_net_of_returns (default ON): with the rule OFF it equals net
--      and the report says so in a note; returns_amt is still shown because it is a fact.
--   3. _rptb1_day_close_wrap: POS day close gets refund_cash / refund_mobile / refund_card and expected_cash_after_refunds. expected_cash stays as it was. A day with a refund and no sale shows up too.
--   4. _rptb1_notes: the plain notes shown under a report that has the new columns.
--   5. _rptb1_patch: the exact-text patch helper (same design as _w1b_patch, own marker). _rptb1_hooked(): which hook sites are in place.
-- Nothing changes until the integrator runs docs/integration/RPT-B1_hooks.sql (the hooks). With the hooks every old column of every report is identical (proved by supabase/phase400_test.sql).
-- !! Re-pasting phase 9 (report_run, rpt_def, rpt_meas, rpt_agg_build, rpt_raw) removes the bos400 hooks: run docs/integration/RPT-B1_hooks.sql again (it is paste-twice safe).
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.report_run(text,jsonb,text,text,integer,boolean)') is null or to_regprocedure('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)') is null
     or to_regprocedure('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)') is null or to_regclass('public.sale_returns') is null
     or to_regprocedure('public.rpt_meas(text)') is null or to_regprocedure('public.rpt_def(text)') is null or to_regclass('public.report_brand_map') is null then
    raise exception 'phase400 needs the report engine (phase 9) and sale returns (phase 12)';
  end if;
end $g$;

create or replace function public._rptb1_p400_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (same design as _w1b_patch, marker is a parameter) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist, otherwise the call STOPS and nothing is half changed. Marker already inside = no-op (returns false).
create or replace function public._rptb1_patch(p_fn regprocedure, p_marker text, p_pairs text[]) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'phase400 patch needs a marker'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'phase400 patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'phase400 patch of % carries no marker', p_fn::text; end if;
  execute def;
  return true;
end $$;

-- ---------- the three views of done returns ----------
-- rpt_ret_b : one row per done return. Columns are the ones rpt_dims('bill') and rpt_where('bill') read from rpt_bill.
create or replace view public.rpt_ret_b as
select r.id as return_id, r.sale_id, s.receipt,
  (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as sold_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  s.created_staff as staff, 'done'::text as status, s.pay_mode, s.sale_type, s.customer_id, cu.name as customer_name, cu.mobile,
  s.total, r.amount as ret_amt, r.refund_amount, r.credit_amount,
  null::text as void_staff, null::text as void_note, null::text as discount_kind
from public.sale_returns r
join public.sales s on s.id = r.sale_id
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
left join public.customers cu on cu.id = s.customer_id
where r.status = 'done';

-- rpt_ret_l : one row per returned line. ret_amt = line amount x (return amount / sum of the return's line amounts) = the sale's discount share already taken off (same rule as _cogs_lines72).
create or replace view public.rpt_ret_l as
select r.id as return_id, r.sale_id, s.receipt,
  (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as sold_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  s.created_staff as staff, 'done'::text as status, s.sale_type, s.pay_mode, s.customer_id,
  it.id as item_id, it.code as item_code,
  coalesce(it.name_bn, nullif(e.v ->> 'name', ''), 'Quick sale') as item_name,
  coalesce(it.name_en, it.name_bn, nullif(e.v ->> 'name', ''), 'Quick sale') as item_name_en,
  it.category, coalesce(it.unit, nullif(e.v ->> 'unit', '')) as unit,
  case when it.id is not null then 'listed' else 'quick' end as line_kind,
  q.qty, q.amount * case when la.s > 0 then r.amount / la.s else 1 end as ret_amt,
  s.total as sale_total, null::text as discount_kind
from public.sale_returns r
join public.sales s on s.id = r.sale_id
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
cross join lateral jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) as e(v)
cross join lateral (select
    case when e.v ->> 'item_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.v ->> 'item_id')::uuid end as iid,
    case when e.v ->> 'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v ->> 'qty')::numeric else 0 end as qty,
    case when e.v ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v ->> 'amount')::numeric else 0 end as amount) q
cross join lateral (select coalesce(sum(case when x ->> 'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (x ->> 'amount')::numeric end), 0) as s
                    from jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) x) la
left join public.items it on it.id = q.iid
where r.status = 'done';

-- rpt_ret_p : one row per money payout of a done return (refund_amount > 0), by the refund mode. Columns are the ones rpt_dims('pay') and rpt_where('pay') read from rpt_pay.
create or replace view public.rpt_ret_p as
select r.id as pay_id, r.sale_id, (r.created_at at time zone 'Asia/Dhaka')::date as day, r.created_at as paid_at,
  extract(hour from r.created_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (r.created_at at time zone 'Asia/Dhaka')::date)::int as dow,
  r.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  r.created_staff as staff, 'refund'::text as kind, r.refund_mode as mode, r.wallet, r.ref, r.refund_amount as amount, false as voided,
  r.customer_id, cu.name as customer_name, cu.mobile
from public.sale_returns r
join public.locations lo on lo.id = r.location_id
left join public.report_brand_map bm on bm.location_id = r.location_id
left join public.customers cu on cu.id = r.customer_id
where r.status = 'done' and r.refund_amount > 0;

revoke all on public.rpt_ret_b, public.rpt_ret_l, public.rpt_ret_p from public, anon, authenticated;      -- like rpt_bill: only the report functions read them

-- ---------- the wrap used by rpt_agg_build ----------
-- Takes the SQL text of the old grouped query (p_t rows, p_tot totals) and returns the SQL of the same query WITH the new columns. Every old column is passed through untouched.
-- A group that has returns but no sales (a return made on a quiet day) appears as an extra row: the old columns of that row are 0 / empty, the new columns carry the return.
create or replace function public._rptb1_agg_wrap(p_def jsonb, p_gl text[], p_mkeys text[], p_flt jsonb, p_allowed int[], p_from date, p_to date, p_dexpr text, p_ws int, p_fym int,
  p_mobok boolean, p_costok boolean, p_t text, p_tot text) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; al text := case src when 'bill' then 'b' when 'line' then 'f' else 'p' end;
  newk text[] := case src when 'bill' then array['returns_amt', 'net_after_returns'] when 'line' then array['returns_amt', 'returns_qty', 'net_after_returns', 'qty_after_returns']
                          else array['refund_paid', 'net_after_refunds'] end;
  basek text := case src when 'pay' then 'amount' else 'net' end;                          -- the old column the new "after" column starts from
  amtk text := case src when 'pay' then 'refund_paid' else 'returns_amt' end;               -- the new money column
  netk text := case src when 'pay' then 'net_after_refunds' else 'net_after_returns' end;   -- the new "after" column
  rel text := case src when 'bill' then 'public.rpt_ret_b' when 'line' then 'public.rpt_ret_l' else 'public.rpt_ret_p' end;
  net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
  dims jsonb := public.rpt_dims(src); meas jsonb := public.rpt_meas(src);
  allow text[]; w text; g text; c jsonb; dsel text[] := '{}'; dnames text[] := '{}'; n int; mk text; k text; ex text;
  amts text; rq text; rqt text; nsel text; jn text; rows_sel text[] := '{}'; tot_sel text[] := '{}'; extra text[] := array['cogs', 'gp', 'gp_pct', 'uncosted_pct'];
  cost_extra boolean := p_costok and src = 'bill' and coalesce((p_def ->> 'cost_join')::int, 0) = 1;
begin
  if not (p_mkeys && newk) or not (basek = any (p_mkeys)) or (src = 'line' and not ('qty' = any (p_mkeys))) then return jsonb_build_object('t', p_t, 'tot', p_tot); end if;
  allow := coalesce((select array_agg(x) from jsonb_array_elements_text(p_def -> 'allow') x), public.rpt_filters_for(src));
  w := public.rpt_where(src, al, p_flt, p_allowed, p_from, p_to, allow, p_mobok) ->> 'w';      -- the same filters as the main query (locations the caller may see, brand, staff, mode ...)
  foreach g in array p_gl loop
    for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
      dsel := dsel || (public.rpt_tok(c ->> 1, al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));      -- the same dimension expressions as the main query
      dnames := dnames || (c ->> 0);
    end loop;
  end loop;
  n := cardinality(dnames);
  amts := case src when 'line' then format('coalesce(round(sum(%s.ret_amt), 2), 0) as r_amt, coalesce(round(sum(%s.qty), 3), 0) as r_qty', al, al)
                   when 'bill' then format('coalesce(sum(%s.ret_amt), 0) as r_amt', al) else format('coalesce(sum(%s.amount), 0) as r_amt', al) end;
  rqt := format('select %s from %s %s where %s', amts, rel, al, w);                                       -- the returns of the whole period (totals row)
  rq := format('select %s from %s %s where %s', array_to_string(dsel || amts, ', '), rel, al, w)          -- the returns per group
        || case when n > 0 then ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i) else '' end;
  -- old columns, passed through. A sum / count column of a return-only group is 0 (its own expression starts with coalesce or count); ratios stay empty.
  foreach k in array dnames loop rows_sel := rows_sel || format('coalesce(bq.%I, rq.%I) as %I', k, k, k); end loop;
  foreach mk in array p_mkeys loop
    continue when mk = any (newk);
    ex := coalesce(meas -> mk ->> 'expr', '');
    rows_sel := rows_sel || case when ex like 'coalesce(%' or ex like 'count(%' then format('coalesce(bq.%I, 0) as %I', mk, mk) else format('bq.%I as %I', mk, mk) end;
    tot_sel := tot_sel || format('bq.%I as %I', mk, mk);
  end loop;
  if cost_extra then
    foreach k in array extra loop rows_sel := rows_sel || format('bq.%I as %I', k, k); tot_sel := tot_sel || format('bq.%I as %I', k, k); end loop;
  end if;
  -- the new columns. "after returns" follows the rule reports_net_of_returns; with the rule off it equals the old column.
  nsel := format('coalesce(rq.r_amt, 0) as %I, %s as %I', amtk, case when net_on then format('coalesce(bq.%I, 0) - coalesce(rq.r_amt, 0)', basek) else format('coalesce(bq.%I, 0)', basek) end, netk);
  if src = 'line' then
    nsel := nsel || format(', coalesce(rq.r_qty, 0) as returns_qty, %s as qty_after_returns', case when net_on then 'coalesce(bq.qty, 0) - coalesce(rq.r_qty, 0)' else 'coalesce(bq.qty, 0)' end);
  end if;
  if n > 0 then
    jn := (select string_agg(format('bq.%I = rq.%I', k2, k2), ' and ') from unnest(dnames) k2);      -- dimension columns are never null, so this is a hash join
    return jsonb_build_object(
      't', format('select %s, %s from (%s) bq full join (%s) rq on %s', array_to_string(rows_sel, ', '), nsel, p_t, rq, jn),
      'tot', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(tot_sel, ', '), nsel, p_tot, rqt));
  end if;
  return jsonb_build_object(
    't', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(rows_sel, ', '), nsel, p_t, rqt),
    'tot', format('select %s, %s from (%s) bq cross join (%s) rq', array_to_string(tot_sel, ', '), nsel, p_tot, rqt));
end $$;

-- ---------- the notes shown under a report that has the new columns ----------
create or replace function public._rptb1_notes(p_def jsonb, p_gl text[], p_mkeys text[]) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; out_ jsonb := '[]'::jsonb;
begin
  if src = 'pay' then
    if not (p_mkeys && array['refund_paid', 'net_after_refunds']) then return out_; end if;
    return out_ || jsonb_build_array(jsonb_build_object('code', 'refund_basis',
      'text_en', 'Refund columns: money handed back to customers for sale returns, on the day of the return, by the refund mode. Returns settled against a customer due are not a payout and are not here.',
      'text_bn', 'ফেরতের কলাম: বিক্রি-ফেরতে গ্রাহককে ফেরত দেওয়া টাকা, ফেরতের দিনে, ফেরতের মাধ্যম অনুযায়ী। বাকির সাথে মেলানো ফেরত টাকা দেওয়া নয়, তাই এখানে নেই।'));
  end if;
  if not (p_mkeys && array['returns_amt', 'net_after_returns']) then return out_; end if;
  out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'returns_basis',
    'text_en', 'Returns columns: goods taken back, with the sale''s discount share taken off, counted on the day of the return (the same rule as the dashboard). Voided returns are not counted.',
    'text_bn', 'ফেরতের কলাম: ফেরত নেওয়া পণ্যের দাম (বিক্রির ছাড়ের অংশ বাদে), ফেরতের দিনে ধরা হয় (ড্যাশবোর্ডের মতোই)। বাতিল ফেরত ধরা হয় না।'));
  if not coalesce(public.rule_on('reports_net_of_returns'), true) then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'returns_not_netted',
      'text_en', 'The setting "Sales figures are net of sale returns" is off: the "after returns" columns equal the old columns. Returns are shown only for information.',
      'text_bn', '"বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ" নিয়মটি বন্ধ: "ফেরত বাদে" কলাম আগের কলামের সমান। ফেরত শুধু তথ্য হিসেবে দেখানো হলো।'));
  end if;
  return out_;
end $$;

-- ---------- POS day close: the cash that went back to customers ----------
-- p_sql is the old day-close query. The result has every old column unchanged plus refund_cash, refund_mobile, refund_card and expected_cash_after_refunds.
create or replace function public._rptb1_day_close_wrap(p_sql text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_allow text[], p_mobok boolean) returns text
language plpgsql stable set search_path = public as $$
declare w text := public.rpt_where('pay', 'r', p_flt, p_allowed, p_from, p_to, p_allow, p_mobok) ->> 'w';
begin
  return format($f$select coalesce(z.day, rf.day) as day, coalesce(z.location_id, rf.location_id) as location_id, coalesce(z.location_bn, rf.location_bn) as location_bn,
      coalesce(z.location_en, rf.location_en) as location_en, coalesce(z.bills, 0) as bills, coalesce(z.net, 0) as net, coalesce(z.discount, 0) as discount,
      coalesce(z.void_bills, 0) as void_bills, coalesce(z.void_amt, 0) as void_amt, coalesce(z.due_created, 0) as due_created,
      coalesce(z.cash_in, 0) as cash_in, coalesce(z.mobile_in, 0) as mobile_in, coalesce(z.card_in, 0) as card_in,
      coalesce(z.cash_collections, 0) as cash_collections, coalesce(z.mobile_collections, 0) as mobile_collections, coalesce(z.card_collections, 0) as card_collections,
      coalesce(z.total_in, 0) as total_in, coalesce(z.expected_cash, 0) as expected_cash,
      coalesce(rf.refund_cash, 0) as refund_cash, coalesce(rf.refund_mobile, 0) as refund_mobile, coalesce(rf.refund_card, 0) as refund_card,
      coalesce(z.expected_cash, 0) - coalesce(rf.refund_cash, 0) as expected_cash_after_refunds
    from (%s) z full join (
      select r.day, r.location_id, r.location_bn, r.location_en,
        coalesce(sum(r.amount) filter (where r.mode = 'cash'), 0) as refund_cash,
        coalesce(sum(r.amount) filter (where r.mode = 'mobile'), 0) as refund_mobile,
        coalesce(sum(r.amount) filter (where r.mode = 'card'), 0) as refund_card
      from public.rpt_ret_p r where %s group by 1, 2, 3, 4) rf on rf.day = z.day and rf.location_id = z.location_id$f$, p_sql, w);
end $$;

-- ---------- which hook sites are in place (the integrator and the tests read this) ----------
create or replace function public._rptb1_hooked() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'rpt_meas', position('bos400' in pg_get_functiondef('public.rpt_meas(text)'::regprocedure)) > 0,
    'rpt_def', position('bos400' in pg_get_functiondef('public.rpt_def(text)'::regprocedure)) > 0,
    'rpt_agg_build', position('bos400' in pg_get_functiondef('public.rpt_agg_build(jsonb,text[],text[],jsonb,integer[],date,date,text,integer,integer,boolean,boolean)'::regprocedure)) > 0,
    'rpt_raw', position('bos400' in pg_get_functiondef('public.rpt_raw(text,jsonb,integer[],date,date,boolean,integer[],numeric,date)'::regprocedure)) > 0,
    'report_run', position('bos400' in pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p400_present(), public._rptb1_patch(regprocedure, text, text[]),
  public._rptb1_agg_wrap(jsonb, text[], text[], jsonb, int[], date, date, text, int, int, boolean, boolean, text, text), public._rptb1_notes(jsonb, text[], text[]),
  public._rptb1_day_close_wrap(text, jsonb, int[], date, date, text[], boolean), public._rptb1_hooked() from public, anon, authenticated;

-- ---------------------------------------------------------------- phase401.sql
-- Phase 401 (bos401) - REPORTS: "DATA NOT CAPTURED" NOTICES (package RPT-B1, item R2). Paste after phase400. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md D3, D4, D5, D6): four reports show a number where the app holds no data, or leave a cost out without saying so.
--   D4  f3_raw_vs_recipe "Actually issued" is the recipe itself (production_post issues exactly the recipe), so it always showed 0.00 % difference although nothing was measured.
--   D5  the app never captures the real yield of a batch, so the costing Runs tab showed "Actual" equal to "Standard".
--   D6  with the location method "off" the conversion cost is booked as 0 and called complete: the Runs tab showed a cost of 0 with no word that labour and overhead were not costed.
--   D3  with profit_one_number_on OFF, wastage, count shrinkage, transit loss and cash short are left out of the branch profit and the gaps column said nothing about them.
-- RULE FOLLOWED: never show 0 or an estimate when the source data is missing; show "not captured" and say which form or field is needed. No stored number is changed; only what the reports SHOW.
-- WHAT THIS FILE ADDS (read-only helpers; the reports use them through the hooks in docs/integration/RPT-B1_hooks.sql, section 2):
--   1. _rptb1_loss_gaps(from, to, place): text for the gaps column of l1_pnl / l3_shop_pnl, e.g. "wastage (not in profit)". Only losses that exist in the ledger and are left out of the profit are listed.
--      A loss counts as "in the profit" exactly when phase92 counts it (master switch on, the cause on, the start date reached, not excluded by the owner).
--   2. _rptb1_loss_summary(from, to, places): the same losses as amounts, for the note under the report.
--   3. _rptb1_r3_notes(report, from, to, places, filters): the notes under f3_raw_vs_recipe ("not captured") and under l1_pnl / l3_shop_pnl (losses left out).
--   4. The report f3_raw_vs_recipe gets one more column, actual_status (measured / partly / not captured). With the hooks its "Actually issued" is empty unless a movement was posted for the batch AFTER
--      the automatic recipe issue (a real measurement). Today nothing posts one, so the column says "not captured" until the production capture package exists.
--   5. production_run_costs (costing Runs tab): conversion_cost is empty with conversion_status "not_captured" when the location method is off; actual_cost is empty with actual_status "not_captured"
--      when no actual yield was typed; unit_cost_basis tells whether the unit cost holds material only.
-- With the hooks NOT installed nothing changes. !! Re-pasting phase 26, 27, 24 or 74 / 79 removes the bos401 hooks: run docs/integration/RPT-B1_hooks.sql again.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p400_present()') is null then raise exception 'phase401 needs phase400 first'; end if;
  if to_regprocedure('public.report_run3(text,jsonb,text,text,integer)') is null or to_regprocedure('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)') is null
     or to_regprocedure('public._r3q_l1_pnl(date,date,integer[],jsonb)') is null or to_regprocedure('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)') is null
     or to_regprocedure('public.production_run_costs(integer,date,date)') is null or to_regclass('public.report_defs3') is null then
    raise exception 'phase401 needs the engine-3 reports (phases 24-27) and costing (phase 74)';
  end if;
end $g$;

create or replace function public._rptb1_p401_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. losses left out of the profit ----------
-- one row per cause with the amount that is NOT counted in the profit of the place and period. Empty when phase92 is not installed.
create or replace function public._rptb1_loss_rows(p_from date, p_to date, p_locs int[]) returns table (cause text, amt numeric)
language plpgsql stable security definer set search_path = public as $$
declare master boolean; f date;
begin
  if to_regprocedure('public._w1d_pl_rows(date,date,integer[])') is null or to_regclass('public.profit_row_exclusions') is null then return; end if;
  master := coalesce(public.rule_on('profit_one_number_on'), false);
  f := public._w1d_losses_from();
  return query
    select r.cause, round(sum(r.amt), 2)
      from public._w1d_pl_rows(p_from, p_to, p_locs) r
     where r.cause in ('wastage', 'count_shrink', 'transit_loss', 'cash_short')
       and not (master and public._w1d_cause_on(r.cause) and (f is null or r.d >= f))                       -- counted: nothing to say
       and not exists (select 1 from public.profit_row_exclusions x where x.cause = r.cause and x.source_id = r.source_id and x.status = 'active')   -- left out on purpose, with a reason
     group by r.cause
    having sum(r.amt) <> 0;
end $$;

create or replace function public._rptb1_loss_gaps(p_from date, p_to date, p_loc int) returns text
language sql stable security definer set search_path = public as $$
  select nullif(string_agg(case l.cause when 'wastage' then 'wastage' when 'count_shrink' then 'count shrink' when 'transit_loss' then 'transit loss' else 'cash short/over' end || ' (not in profit)',
                           ', ' order by l.cause), '')
    from public._rptb1_loss_rows(p_from, p_to, array[p_loc]) l;
$$;

create or replace function public._rptb1_loss_summary(p_from date, p_to date, p_locs int[]) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(l.cause, l.amt), '{}'::jsonb) from public._rptb1_loss_rows(p_from, p_to, p_locs) l;
$$;

-- ---------- 2. the notes of the engine-3 reports ----------
create or replace function public._rptb1_r3_notes(p_key text, d1 date, d2 date, locs int[], flt jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; n_all int; n_bad int; ls jsonb; txt_en text := ''; txt_bn text := ''; k text; v numeric;
begin
  if p_key = 'f3_raw_vs_recipe' then
    select count(*), count(*) filter (where r ->> 'actual_status' is distinct from 'measured') into n_all, n_bad from public._r3q_f3_raw_vs_recipe(d1, d2, locs, flt) r;
    if coalesce(n_bad, 0) > 0 then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'actual_issue', 'lines', n_bad, 'of', n_all,
        'text_en', 'Actual raw material use is not captured for ' || n_bad || ' of ' || n_all || ' lines, so no difference is shown. The app issues the recipe quantity automatically when production is posted, so it cannot be compared with itself. '
                   || 'Needed: the real issue of each batch (the issue slip 04-2 linked to the production run, or an actual-use entry when production is posted).',
        'text_bn', n_all || ' লাইনের মধ্যে ' || n_bad || 'টির কাঁচামালের আসল ব্যবহার ধরা হয়নি, তাই পার্থক্য দেখানো হয়নি। উৎপাদন পোস্ট করলে অ্যাপ নিজে রেসিপির পরিমাণ ইস্যু করে, নিজের সাথে নিজেকে মেলানো যায় না। '
                   || 'দরকার: প্রতিটি ব্যাচের আসল ইস্যু (উৎপাদনের সাথে যুক্ত ইস্যু স্লিপ ০৪-২, অথবা উৎপাদন পোস্টের সময় আসল ব্যবহার লেখা)।'));
    end if;
  elsif p_key in ('l1_pnl', 'l3_shop_pnl') then
    ls := public._rptb1_loss_summary(d1, d2, locs);
    if ls <> '{}'::jsonb then
      for k, v in select e.key, e.value::numeric from jsonb_each_text(ls) e order by e.key loop
        txt_en := txt_en || case when txt_en = '' then '' else ', ' end || case k when 'wastage' then 'wastage' when 'count_shrink' then 'count shrink' when 'transit_loss' then 'transit loss' else 'cash short/over' end || ' ' || v::text;
        txt_bn := txt_bn || case when txt_bn = '' then '' else ', ' end || case k when 'wastage' then 'অপচয়' when 'count_shrink' then 'গণনায় ঘাটতি' when 'transit_loss' then 'পথে ক্ষতি' else 'ক্যাশ কম/বেশি' end || ' ' || v::text;
      end loop;
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'losses_not_counted', 'amounts', ls,
        'text_en', 'The profit shown does not include: ' || txt_en || '. They are in the stock ledger / cash cases but the setting "One profit number: count losses in the profit" is off (or that loss is switched off). The gaps column marks the rows.',
        'text_bn', 'দেখানো লাভে এগুলো ধরা নেই: ' || txt_bn || '। স্টক-হিসাব/ক্যাশ কেসে আছে, কিন্তু "One profit number: count losses in the profit" নিয়মটি বন্ধ (বা সেই ক্ষতির সুইচ বন্ধ)। gaps কলামে সারিগুলো চিহ্নিত।'));
    end if;
  elsif p_key in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items') and to_regprocedure('public._rptb1_y_notes(text,date,date,integer[],jsonb)') is not null then
    out_ := out_ || public._rptb1_y_notes(p_key, d1, d2, locs, flt);      -- phase 403: the three added reports
  end if;
  return out_;
end $$;

-- ---------- 3. f3 gets the status column ----------
update public.report_defs3 set cols = cols || '[["actual_status","আসল মাপা?","Actual measured?","text"]]'::jsonb
 where key = 'f3_raw_vs_recipe' and not (cols::text like '%actual_status%');

-- ---------- 4. which hook sites are in place ----------
create or replace function public._rptb1_hooked401() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'f3', position('bos401' in pg_get_functiondef('public._r3q_f3_raw_vs_recipe(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'l1', position('bos401' in pg_get_functiondef('public._r3q_l1_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'l3', position('bos401' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)'::regprocedure)) > 0,
    'report_run3', position('bos401' in pg_get_functiondef('public.report_run3(text,jsonb,text,text,integer)'::regprocedure)) > 0,
    'production_run_costs', position('bos401' in pg_get_functiondef('public.production_run_costs(integer,date,date)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p401_present(), public._rptb1_loss_rows(date, date, int[]), public._rptb1_loss_gaps(date, date, int), public._rptb1_loss_summary(date, date, int[]),
  public._rptb1_r3_notes(text, date, date, int[], jsonb), public._rptb1_hooked401() from public, anon, authenticated;

-- ---------------------------------------------------------------- phase402.sql
-- Phase 402 (bos402) - REPORTS: ONE COST BASIS FOR ITEM SALES AND BUSINESS ANALYSIS (package RPT-B1, item R7). Paste after phase401. Paste-twice safe. Earlier phase files are not edited.
-- WHY (docs/REPORTS_AUDIT_1.md D2): two cost bases for the same item. The margin report (l2_margin) and the dashboard take the cost from the STOCK LEDGER (what the goods really cost when bought / made),
--      with the typed price list (item_costs) only as a fallback. The first report engine (item_sales, category_sales, sales_summary, sales_combined) and the ABC list of the business page
--      (biz_items) use the typed price list ONLY. On the same day item_sales showed profit "-" and "100 % uncosted" where l2_margin showed a margin of 83.71 %.
-- WHAT THIS FILE ADDS (money-affecting, therefore a SETTING whose default keeps today's figures):
--   1. Setting reports_cost_basis (owner): price_list (default = today: only the typed price list) | ledger_first (ledger cost first, the price list only where the ledger has no cost).
--   2. View rpt_line_cost: the cost per sold line = the ledger cost of that sale for that item (all-or-nothing: if any ledger row of the sale and item has no cost, the ledger is not used for that line),
--      else the price-list cost. cost_src says which. Read only by the report engine, only when the setting is ledger_first.
--   3. _rptb1_item_cost_split / _rptb1_biz_item_cost: the same rule per item for the business analysis page (biz_items). With the setting at its default they return exactly the rows biz_items used before.
--   4. _rptb1_cost_notes: the unknown-cost notes under the first-engine reports (the same idea as l2_margin: cost of goods covers the costed part only; an estimate from the price list is said to be an estimate;
--      when the price list has no cost but the ledger does, the note says so and names the setting). Shown in both settings: today's reports gain a note, not a number.
--   5. biz_cost_status(from, to, place): read-only answer for the business page note and its CSV: revenue, costed from the ledger, costed from the price list, unknown, and the basis in use.
-- Nothing changes until the hooks (docs/integration/RPT-B1_hooks.sql, section 3) are installed AND the owner sets ledger_first; the notes appear with the hooks.
-- !! Re-pasting phase 9 (rpt_agg_sql, report_run) or phase 4 / 14 (biz_items) removes the bos402 hooks: run the hooks file again.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p401_present()') is null then raise exception 'phase402 needs phase401 (and phase400) first'; end if;
  if to_regprocedure('public.biz_items(date,date,integer)') is null or to_regclass('public.item_costs') is null or to_regclass('public.sales_fact_t') is null
     or to_regprocedure('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)') is null then
    raise exception 'phase402 needs the report engine (phase 9), item costs and the business analysis functions (phase 4 / 14)';
  end if;
end $g$;

create or replace function public._rptb1_p402_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- 1. the setting (English only, default = today) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('reports_cost_basis', 'reports', 'choice', '"price_list"', null, '["price_list","ledger_first"]', null, null,
  'Report cost basis: where item sales reports take the cost from', 'Report cost basis: where item sales reports take the cost from', 'Report cost basis: where item sales reports take the cost from',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.',
  'price_list (default) = only the cost typed in the item master, as today. ledger_first = the cost from the stock ledger (what the goods really cost) first, the typed cost only where the ledger has none. Used by item sales, category sales, sales summary, combined sales and the business analysis page. The margin report already uses the ledger first.', 880)
 on conflict (key) do nothing;

create or replace function public._rptb1_cost_basis() returns text language sql stable security definer set search_path = public as $$
  select case when public.rule_txt('reports_cost_basis') = 'ledger_first' then 'ledger_first' else 'price_list' end $$;

-- ---------- 2. cost per sold line, ledger first ----------
-- cost_price is per unit of the sale line (ledger total cost of that sale and item divided by the quantity sold in that sale), so qty x cost_price is the cost of the line like item_costs.cost_price is.
-- Ledger = rows of the sale itself (ref_type sale, reasons sale_out / issue_out). A pack sale posts its parts under another ref_type: those lines use the price list or stay unknown.
create or replace view public.rpt_line_cost as
select t.sale_id, t.line_no,
  coalesce(lc.unit_cost, ic.cost_price) as cost_price,
  case when lc.unit_cost is not null then 'ledger' when ic.cost_price is not null then 'price_list' end as cost_src
from public.sales_fact_t t
left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = t.item_id
left join lateral (
  select sum(-l.qty_delta * l.unit_cost) / nullif((select sum(q.qty) from public.sales_fact_t q where q.sale_id = t.sale_id and q.item_id = t.item_id), 0) as unit_cost
    from public.stock_ledger l
   where l.ref_type = 'sale' and l.ref_id = t.sale_id::text and l.item_id = t.item_id and l.reason in ('sale_out', 'issue_out') and t.item_id is not null
  having count(*) > 0 and bool_and(coalesce(l.unit_cost, 0) > 0)) lc on true;
revoke all on public.rpt_line_cost from public, anon, authenticated;

-- ---------- 3. the same rule per item (business analysis page) ----------
-- one row per item sold in the period (done sales at the places the caller may see): revenue, quantity, ledger unit cost (all-or-nothing over the item's sales) and price-list cost (items that count in the business)
create or replace function public._rptb1_item_cost_split(p_from date, p_to date, p_loc int) returns table (item_id uuid, rev numeric, qty numeric, lp numeric, pl numeric)
language sql stable security definer set search_path = public as $$
  with ln as (
    select t.sale_id, t.item_id, sum(t.qty) as q, sum(t.net) as r
      from public.sales_fact_t t
     where t.status = 'done' and t.day between p_from and p_to and (p_loc is null or t.location_id = p_loc) and t.location_id in (select l.id from public.locations l where public.can_loc(l.id)) and t.item_id is not null
     group by 1, 2),
  ps as (
    select ln.item_id, ln.q, ln.r,
           (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = ln.sale_id::text and l.item_id = ln.item_id and l.reason in ('sale_out', 'issue_out')) as c,
           (select count(*) > 0 and bool_and(coalesce(l.unit_cost, 0) > 0) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = ln.sale_id::text and l.item_id = ln.item_id and l.reason in ('sale_out', 'issue_out')) as ok
      from ln),
  ag as (select ps.item_id, sum(ps.r) as rev, sum(ps.q) as qty, case when bool_and(coalesce(ps.ok, false)) then sum(ps.c) / nullif(sum(ps.q), 0) end as lp from ps group by 1)
  select ag.item_id, ag.rev, ag.qty, ag.lp, (select ic.cost_price from public.item_costs ic join public.items b on b.id = ic.item_id where ic.item_id = ag.item_id and b.count_in_business) as pl
    from ag;
$$;

-- the cost rows biz_items joins: default basis = exactly the rows it used before (the price list of items that count in the business); ledger_first = ledger unit cost first
create or replace function public._rptb1_biz_item_cost(p_from date, p_to date, p_loc int) returns table (item_id uuid, cost_price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if public._rptb1_cost_basis() <> 'ledger_first' then
    return query select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business;
    return;
  end if;
  return query
    select i.id, coalesce(s.lp, ic.cost_price)
      from public.items i
      left join public._rptb1_item_cost_split(p_from, p_to, p_loc) s on s.item_id = i.id
      left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = i.id
     where coalesce(s.lp, ic.cost_price) is not null;
end $$;

-- ---------- 4. read-only status for the business page (note + CSV) ----------
create or replace function public.biz_cost_status(p_from date, p_to date, p_loc integer default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare basis text := public._rptb1_cost_basis(); rev numeric; led numeric; fb numeric; unk numeric; could numeric; allrev numeric; pl_only numeric;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if not public.biz_cost_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  select coalesce(sum(t.net), 0) into allrev from public.sales_fact_t t
   where t.status = 'done' and t.day between p_from and p_to and (p_loc is null or t.location_id = p_loc) and t.location_id in (select l.id from public.locations l where public.can_loc(l.id));
  select coalesce(sum(s.rev), 0),
         coalesce(sum(s.rev) filter (where basis = 'ledger_first' and s.lp is not null), 0),
         coalesce(sum(s.rev) filter (where s.pl is not null and (basis = 'price_list' or s.lp is null)), 0),
         coalesce(sum(s.rev) filter (where basis = 'price_list' and s.pl is null and s.lp is not null), 0)
    into rev, led, fb, could
    from public._rptb1_item_cost_split(p_from, p_to, p_loc) s;
  unk := greatest(allrev - led - fb, 0);                    -- quick / unlisted lines and items with no cost anywhere
  return jsonb_build_object('basis', basis, 'revenue', round(allrev, 2), 'ledger_rev', round(led, 2), 'price_list_rev', round(fb, 2), 'unknown_rev', round(unk, 2),
    'unknown_pct', case when allrev > 0 then round(100 * unk / allrev, 2) end, 'ledger_could_cost_rev', round(could, 2));
end $$;

-- ---------- 5. the notes under the first-engine reports ----------
create or replace function public._rptb1_cost_notes(p_def jsonb, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_mobok boolean, p_costok boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare basis text := public._rptb1_cost_basis(); w text; tot numeric; led numeric; fb numeric; unk numeric; could numeric; out_ jsonb := '[]'::jsonb;
begin
  if not p_costok or not (p_def ->> 'src' = 'line' or coalesce((p_def ->> 'cost_join')::int, 0) = 1) then return out_; end if;
  w := public.rpt_where('line', 'f', p_flt, p_allowed, p_from, p_to, array['locations', 'brands', 'staff', 'modes', 'sale_type', 'customer', 'min_amount', 'max_amount', 'items', 'categories'], p_mobok) ->> 'w';
  -- price_list: only the lines without a typed cost look at the ledger (for the hint); ledger_first: every line does (that is the basis in use)
  execute format($q$with f0 as (select f.sale_id, f.line_no, f.net, ic.cost_price as pl from public.sales_fact f left join (select x.item_id, x.cost_price from public.item_costs x join public.items b on b.id = x.item_id where b.count_in_business) ic on ic.item_id = f.item_id where %s and f.status = 'done')
    select coalesce(sum(f0.net), 0),
      coalesce(sum(f0.net) filter (where %L = 'ledger_first' and c.cost_src = 'ledger'), 0),
      coalesce(sum(f0.net) filter ( where (%L = 'price_list' and f0.pl is not null) or (%L = 'ledger_first' and c.cost_src = 'price_list')), 0),
      coalesce(sum(f0.net) filter (where %L = 'price_list' and f0.pl is null and c.cost_src = 'ledger'), 0)
    from f0 left join public.rpt_line_cost c on c.sale_id = f0.sale_id and c.line_no = f0.line_no and (%L = 'ledger_first' or f0.pl is null)$q$, w, basis, basis, basis, basis, basis) into tot, led, fb, could;
  unk := greatest(tot - led - fb, 0);
  if unk > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_unknown', 'unknown_rev', round(unk, 2), 'unknown_pct', round(100 * unk / nullif(tot, 0), 2),
      'text_en', 'Cost is unknown for sales of ' || round(unk, 2)::text || ' (' || round(100 * unk / nullif(tot, 0), 1)::text || ' %): no '
                 || case basis when 'ledger_first' then 'stock-ledger cost and no cost in the item master' else 'cost in the item master' end
                 || '. Cost of goods and profit cover the costed part only. Needed: receive or produce the item with a cost, or type its cost price in the item master.',
      'text_bn', round(unk, 2)::text || ' টাকার বিক্রির খরচ জানা নেই (' || round(100 * unk / nullif(tot, 0), 1)::text || ' %): '
                 || case basis when 'ledger_first' then 'স্টক-হিসাবে খরচ নেই, আইটেম মাস্টারেও নেই' else 'আইটেম মাস্টারে খরচ লেখা নেই' end
                 || '। মালের খরচ ও লাভ শুধু খরচ-জানা অংশের। দরকার: খরচসহ মাল কেনা/বানানো, অথবা আইটেম মাস্টারে ক্রয়মূল্য লেখা।'));
  end if;
  if basis = 'ledger_first' and fb > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_estimate', 'price_list_rev', round(fb, 2),
      'text_en', 'Sales of ' || round(fb, 2)::text || ' have no stock-ledger cost; their cost comes from the typed price list (an estimate from the book cost).',
      'text_bn', round(fb, 2)::text || ' টাকার বিক্রির স্টক-হিসাবে খরচ নেই; খরচ নেওয়া হয়েছে লিখে রাখা খরচ-তালিকা থেকে (বইয়ের খরচ থেকে অনুমান)।'));
  end if;
  if basis = 'price_list' and could > 0.004 then
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_basis_hint', 'ledger_could_cost_rev', round(could, 2),
      'text_en', 'The stock ledger holds a cost for sales of ' || round(could, 2)::text || ' that have no cost in the item master. The setting "Report cost basis" = ledger_first would use it (the margin report already does).',
      'text_bn', round(could, 2)::text || ' টাকার বিক্রির খরচ আইটেম মাস্টারে নেই, কিন্তু স্টক-হিসাবে আছে। "Report cost basis" = ledger_first করলে তা ব্যবহার হবে (মার্জিন রিপোর্ট আগেই তা করে)।'));
  end if;
  return out_;
end $$;

create or replace function public._rptb1_hooked402() returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object(
    'rpt_agg_sql', position('bos402' in pg_get_functiondef('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)'::regprocedure)) > 0,
    'report_run', position('bos402' in pg_get_functiondef('public.report_run(text,jsonb,text,text,integer,boolean)'::regprocedure)) > 0,
    'biz_items', position('bos402' in pg_get_functiondef('public.biz_items(date,date,integer)'::regprocedure)) > 0);
$$;

revoke all on function public._rptb1_p402_present(), public._rptb1_cost_basis(), public._rptb1_item_cost_split(date, date, int), public._rptb1_biz_item_cost(date, date, int),
  public._rptb1_cost_notes(jsonb, jsonb, int[], date, date, boolean, boolean), public._rptb1_hooked402() from public, anon, authenticated;
revoke all on function public.biz_cost_status(date, date, integer) from public, anon;
grant execute on function public.biz_cost_status(date, date, integer) to authenticated;

-- ---------------------------------------------------------------- phase403.sql
-- Phase 403 (bos403) - THREE REPORTS A SWEETS / BAKERY BUSINESS NEEDS (package RPT-B1, item 5). Paste after phase402. Paste-twice safe. Earlier phase files are not edited.
-- Matched by PURPOSE against the existing reports first (docs/integration/RPT-B1.md, table "Why these three"): none of them exists today.
--   y1_daily_sellout     Daily sell-out / unsold at closing, per outlet, per item, per day. Opening + produced + received against sold, wasted, sent and what is left at closing, the sell-through %
--                        and the cost of the wastage of the day. Source: the stock ledger (the one truth for stock). k3_store_ledger gives period totals per kind, not the day, and no closing.
--   y2_festival_compare  The same items over the dates you pick against the same dates one year earlier (or other dates you choose), quantity and sales after returns, with a plain "no previous data" state.
--                        Source: the sales lines (sales_fact) and the returns (rpt_ret_l, phase 400). The report hub compares whole periods and totals, not item by item with an empty-last-year state.
--   y3_customer_items    What each of the top customers buys: the top N customers by sales (setting report_top_customers_n, blank = 10) and their items. Source: sales lines with a customer, returns.
--                        best_customers lists customers, not their items.
-- All three are engine-3 reports (report_defs3 + one _r3q_ function each): date and place filters, paging, CSV, print and the phone layout come from the report viewer. Every row carries _drill, and
-- report_drill(key, ref) returns the TRANSACTIONS behind a row (ledger movements, sale lines) so a number can be traced to its source. Read-only: nothing here writes to a business table.
-- Never an estimate: an item that is not stock-tracked is named in a "not captured" note (y1); a year with no sales is "no previous data", not 0 (y2); sales with no customer are counted and said (y3).
-- Open to the roles that already hold the group grant (report_stock, report_sales, report_customers). The cost of wastage is shown only to holders of the cost right.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._rptb1_p402_present()') is null then raise exception 'phase403 needs phase402 (and 400, 401) first'; end if;
  if to_regclass('public.rpt_ret_l') is null or to_regclass('public.report_defs3') is null or to_regprocedure('public._r2_locs(jsonb)') is null or to_regclass('public.sales_fact') is null then
    raise exception 'phase403 needs the report engines (phases 9, 21, 24) and phase 400';
  end if;
end $g$;

create or replace function public._rptb1_p403_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- setting (owner): how many top customers y3 lists. Blank = 10. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('report_top_customers_n', 'reports', 'number', null, 'customers', null, 1, 200,
  'Report: how many top customers "What the top customers buy" lists', 'Report: how many top customers "What the top customers buy" lists', 'Report: how many top customers "What the top customers buy" lists',
  'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 'Top customers are ranked by their sales in the chosen dates. Blank = 10.', 881)
 on conflict (key) do nothing;

-- ---------- y1: daily sell-out / unsold at closing ----------
create or replace function public._r3q_y1_daily_sellout(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cats text[] := public.rpt_arr_text(flt -> 'categories'); its uuid[] := public.rpt_arr_uuid(flt -> 'items'); cost_ok boolean := public.rpt_cost_ok();
        t1 timestamptz := (d1::timestamp at time zone 'Asia/Dhaka'); t2 timestamptz := ((d2 + 1)::timestamp at time zone 'Asia/Dhaka');
begin
  return query
  with it as (select i.id, i.code, i.name_bn, i.name_en, i.unit from public.items i
               where i.tracked and (cats is null or i.category = any (cats)) and (its is null or i.id = any (its))),
  base as (select l.location_id, l.item_id, sum(l.qty_delta) as q from public.stock_ledger l join it on it.id = l.item_id
            where l.location_id = any (locs) and l.made_at < t1 group by 1, 2),
  mv as (
    select l.location_id, l.item_id, (l.made_at at time zone 'Asia/Dhaka')::date as d,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'production_in'), 0) as produced,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'transfer_in'), 0) as received,
      coalesce(sum(l.qty_delta) filter (where l.reason = 'sale_return'), 0) as returned,
      coalesce(-sum(l.qty_delta) filter (where l.reason in ('sale_out', 'sale_void_in')), 0) as sold,
      coalesce(-sum(l.qty_delta) filter (where l.reason = 'wastage'), 0) as wasted,
      coalesce(-sum(l.qty_delta) filter (where l.reason = 'transfer_out'), 0) as sent,
      coalesce(sum(l.qty_delta) filter (where l.reason not in ('production_in', 'transfer_in', 'sale_return', 'sale_out', 'sale_void_in', 'wastage', 'transfer_out')), 0) as other,
      sum(l.qty_delta) as total,
      sum(-l.qty_delta * l.unit_cost) filter (where l.reason = 'wastage' and coalesce(l.unit_cost, 0) > 0) as w_cost,
      count(*) filter (where l.reason = 'wastage' and coalesce(l.unit_cost, 0) <= 0) as w_nocost
      from public.stock_ledger l join it on it.id = l.item_id
     where l.location_id = any (locs) and l.made_at >= t1 and l.made_at < t2
     group by 1, 2, 3),
  cu as (select mv.*, coalesce(b.q, 0) + sum(mv.total) over (partition by mv.location_id, mv.item_id order by mv.d) as closing
           from mv left join base b on b.location_id = mv.location_id and b.item_id = mv.item_id)
  select jsonb_build_object('day', cu.d, 'location_id', cu.location_id, 'location_bn', lo.name_bn, 'item_code', it.code, 'item_bn', it.name_bn, 'unit', it.unit,
      'opening', round(cu.closing - cu.total, 4), 'produced', round(cu.produced, 4), 'received', round(cu.received, 4), 'returned', round(cu.returned, 4),
      'sold', round(cu.sold, 4), 'wasted', round(cu.wasted, 4), 'sent', round(cu.sent, 4), 'other', round(cu.other, 4), 'closing', round(cu.closing, 4),
      'sell_through_pct', case when (cu.closing - cu.total) + cu.produced + cu.received > 0 then round(100 * (cu.sold - cu.returned) / ((cu.closing - cu.total) + cu.produced + cu.received), 1) end,
      'waste_cost', case when not cost_ok then null when cu.wasted = 0 then 0 when cu.w_nocost > 0 then null else round(cu.w_cost, 2) end,
      '_drill', jsonb_build_object('day', cu.d, 'loc', cu.location_id, 'item', it.id))
    from cu join it on it.id = cu.item_id join public.locations lo on lo.id = cu.location_id;
end $$;

-- ---------- y2: festival / season comparison ----------
create or replace function public._r3q_y2_festival_compare(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare cats text[] := public.rpt_arr_text(flt -> 'categories'); its uuid[] := public.rpt_arr_uuid(flt -> 'items');
        pf date := coalesce(public.rpt_date(flt ->> 'prev_from'), (d1 - interval '1 year')::date); pt date := coalesce(public.rpt_date(flt ->> 'prev_to'), (d2 - interval '1 year')::date);
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); anyprev boolean;
begin
  if pt < pf or pt - pf > 365 then raise exception 'bad_range'; end if;
  anyprev := exists (select 1 from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt);
  return query
  with k as (
    select 'cur'::text as per, f.item_id, f.qty, f.net from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2
    union all select 'prev', f.item_id, f.qty, f.net from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt
    union all select 'cur', r.item_id, -r.qty, -r.ret_amt from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.day between d1 and d2
    union all select 'prev', r.item_id, -r.qty, -r.ret_amt from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.day between pf and pt),
  agg as (
    select k.item_id,
      sum(k.qty) filter (where k.per = 'cur') as qn, sum(k.net) filter (where k.per = 'cur') as nn,
      sum(k.qty) filter (where k.per = 'prev') as qp, sum(k.net) filter (where k.per = 'prev') as np
      from k left join public.items i on i.id = k.item_id
     where (cats is null or i.category = any (cats)) and (its is null or k.item_id = any (its))
     group by k.item_id)
  select jsonb_build_object('item_code', coalesce(i.code, 'quick'), 'item_bn', coalesce(i.name_bn, 'Quick / unlisted sales (no item)'), 'category', i.category, 'unit', i.unit,
      'qty_now', round(coalesce(a.qn, 0), 3), 'net_now', round(coalesce(a.nn, 0), 2),
      'qty_prev', case when anyprev then round(coalesce(a.qp, 0), 3) end, 'net_prev', case when anyprev then round(coalesce(a.np, 0), 2) end,
      'qty_change', case when anyprev then round(coalesce(a.qn, 0) - coalesce(a.qp, 0), 3) end,
      'qty_change_pct', case when anyprev and coalesce(a.qp, 0) > 0 then round(100 * (coalesce(a.qn, 0) - a.qp) / a.qp, 1) end,
      'net_change_pct', case when anyprev and coalesce(a.np, 0) > 0 then round(100 * (coalesce(a.nn, 0) - a.np) / a.np, 1) end,
      'state', case when not anyprev then 'আগের তথ্য নেই / no previous data'
                    when coalesce(case when a.item_id is null then a.np else a.qp end, 0) <= 0 and coalesce(case when a.item_id is null then a.nn else a.qn end, 0) > 0 then 'গত বছর বিক্রি হয়নি / not sold last year'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) <= 0 and coalesce(case when a.item_id is null then a.np else a.qp end, 0) > 0 then 'এবার বিক্রি হয়নি / not sold this time'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) > coalesce(case when a.item_id is null then a.np else a.qp end, 0) then 'বেড়েছে / up'
                    when coalesce(case when a.item_id is null then a.nn else a.qn end, 0) < coalesce(case when a.item_id is null then a.np else a.qp end, 0) then 'কমেছে / down' else 'একই / same' end,
      '_drill', jsonb_build_object('item', a.item_id, 'from', d1, 'to', d2, 'pf', pf, 'pt', pt))
    from agg a left join public.items i on i.id = a.item_id;
end $$;

-- ---------- y3: what the top customers buy ----------
create or replace function public._r3q_y3_customer_items(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language plpgsql stable security definer set search_path = public as $$
declare n int := least(greatest(coalesce(public.rule_num('report_top_customers_n'), 10), 1), 200)::int; cust uuid[] := public.rpt_arr_uuid(flt -> 'customer');
        mob_ok boolean := public.rpt_mobile_ok(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
begin
  return query
  with k as (
    select f.customer_id, f.item_id, f.sale_id, f.day, f.qty, f.net from public.sales_fact f
     where f.status = 'done' and f.customer_id is not null and f.item_id is not null and f.location_id = any (locs) and f.day between d1 and d2 and (cust is null or f.customer_id = any (cust))
    union all
    select r.customer_id, r.item_id, null, null, -r.qty, -r.ret_amt from public.rpt_ret_l r
     where net_on and r.customer_id is not null and r.item_id is not null and r.location_id = any (locs) and r.day between d1 and d2 and (cust is null or r.customer_id = any (cust))),
  ci as (select k.customer_id, k.item_id, sum(k.qty) as qty, sum(k.net) as net, count(distinct k.sale_id) as bills, max(k.day) as last_day from k group by 1, 2),
  ct as (select ci.customer_id, sum(ci.net) as cnet, dense_rank() over (order by sum(ci.net) desc, ci.customer_id) as rk from ci group by ci.customer_id),
  top as (select * from ct where rk <= n)
  select jsonb_build_object('rank', top.rk, 'customer_name', coalesce(cu.name, '-'),
      'mobile', case when mob_ok then cu.mobile else left(cu.mobile, 3) || '****' || right(cu.mobile, 2) end,
      'customer_net', round(top.cnet, 2), 'item_code', it.code, 'item_bn', it.name_bn, 'unit', it.unit,
      'qty', round(ci.qty, 3), 'net', round(ci.net, 2), 'share_pct', case when top.cnet > 0 then round(100 * ci.net / top.cnet, 1) end, 'bills', ci.bills, 'last_bought', ci.last_day,
      '_drill', jsonb_build_object('customer', ci.customer_id, 'item', ci.item_id, 'from', d1, 'to', d2))
    from top join ci on ci.customer_id = top.customer_id join public.items it on it.id = ci.item_id left join public.customers cu on cu.id = top.customer_id
   where ci.qty <> 0 or ci.net <> 0;
end $$;

-- ---------- notes under the three reports (called by _rptb1_r3_notes, phase 401) ----------
create or replace function public._rptb1_y_notes(p_key text, d1 date, d2 date, locs int[], flt jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb := '[]'::jsonb; n_items int; q numeric; n_quick int; a_quick numeric; pf date; pt date; anyprev boolean; tot numeric; withc numeric; cats text[] := public.rpt_arr_text(flt -> 'categories');
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); nn int;
begin
  if p_key = 'y1_daily_sellout' then
    select count(distinct f.item_id), coalesce(sum(f.qty), 0) into n_items, q from public.sales_fact f join public.items i on i.id = f.item_id
     where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2 and not i.tracked and (cats is null or i.category = any (cats));
    select count(*), coalesce(sum(f.net), 0) into n_quick, a_quick from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2 and f.item_id is null and cats is null;
    if n_items > 0 or n_quick > 0 then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'untracked_items', 'items', n_items, 'quick_lines', n_quick,
        'text_en', 'Not in this report: ' || n_items || ' item(s) sold in these dates are not stock-tracked (quantity sold ' || q::text || ')' || case when n_quick > 0 then ' and ' || n_quick || ' quick / unlisted line(s) (' || round(a_quick, 2)::text || ') have no item' else '' end
                   || '. Their stock is not counted, so nothing can be said about what was left. Needed: switch stock tracking on for the item (item master, "tracked") and enter an opening stock; sell quick items from the item list.',
        'text_bn', 'এই রিপোর্টে নেই: এই সময়ে বিক্রি হওয়া ' || n_items || 'টি আইটেমের স্টক গোনা হয় না (বিক্রির পরিমাণ ' || q::text || ')' || case when n_quick > 0 then ' এবং ' || n_quick || 'টি কুইক/তালিকা-বহির্ভূত লাইনে (' || round(a_quick, 2)::text || ') আইটেম নেই' else '' end
                   || '। তাই কত বাকি ছিল বলা যায় না। দরকার: আইটেম মাস্টারে স্টক গোনা চালু করা ("tracked") ও শুরুর স্টক দেওয়া; কুইক আইটেম তালিকা থেকে বিক্রি করা।'));
    end if;
    if not public.rpt_cost_ok() then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'cost_hidden', 'text_en', 'The cost of wastage is hidden for your role', 'text_bn', 'অপচয়ের খরচ আপনার ভূমিকার জন্য ঢাকা'));
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'sellout_basis',
      'text_en', 'Left at closing = opening + produced + received + returned - sold - wasted - sent + other (counts, purchases, corrections). Sell-through % = (sold - returned) / (opening + produced + received). One row per day, place and item that had any stock movement.',
      'text_bn', 'দিনের শেষে বাকি = শুরু + তৈরি + গৃহীত + ফেরত − বিক্রি − নষ্ট − পাঠানো + অন্যান্য (গণনা, ক্রয়, সংশোধন)। বিক্রির হার % = (বিক্রি − ফেরত) / (শুরু + তৈরি + গৃহীত)। যে দিন, জায়গা ও আইটেমে স্টকের নড়াচড়া হয়েছে তার জন্য একটি সারি।'));
  elsif p_key = 'y2_festival_compare' then
    pf := coalesce(public.rpt_date(flt ->> 'prev_from'), (d1 - interval '1 year')::date); pt := coalesce(public.rpt_date(flt ->> 'prev_to'), (d2 - interval '1 year')::date);
    anyprev := exists (select 1 from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.day between pf and pt);
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'compare_range', 'from', pf, 'to', pt,
      'text_en', 'Compared with ' || pf::text || ' to ' || pt::text || ' (the same dates one year earlier unless you chose other dates in "Compare with"). Quantity and sales ' || case when net_on then 'are after returns.' else 'are before returns (the setting "Sales figures are net of sale returns" is off).' end,
      'text_bn', pf::text || ' থেকে ' || pt::text || ' এর সাথে তুলনা (এক বছর আগের একই তারিখ, "Compare with"-এ অন্য তারিখ না দিলে)। পরিমাণ ও বিক্রি ' || case when net_on then 'ফেরত বাদে।' else 'ফেরত বাদ দেওয়ার আগে ("বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ" নিয়ম বন্ধ)।' end));
    if not anyprev then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'not_captured', 'what', 'previous_sales',
        'text_en', 'No sales were recorded between ' || pf::text || ' and ' || pt::text || ' at the chosen places, so there is nothing to compare with and no previous figure is shown (not 0). The shop may not have used the app then. Needed: sales of that period in the app, or choose other dates in "Compare with".',
        'text_bn', pf::text || ' থেকে ' || pt::text || ' পর্যন্ত বাছা জায়গায় কোনো বিক্রি লেখা নেই, তাই তুলনা করার কিছু নেই; আগের কোনো সংখ্যা (০ নয়) দেখানো হয়নি। তখন হয়তো অ্যাপ ব্যবহার হয়নি। দরকার: সেই সময়ের বিক্রি অ্যাপে থাকা, অথবা "Compare with"-এ অন্য তারিখ বাছা।'));
    end if;
  elsif p_key = 'y3_customer_items' then
    select coalesce(sum(f.net), 0), coalesce(sum(f.net) filter (where f.customer_id is not null), 0) into tot, withc from public.sales_fact f
     where f.status = 'done' and f.location_id = any (locs) and f.day between d1 and d2;
    if tot > 0 and withc < tot then
      out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'customer_coverage', 'no_customer_rev', round(tot - withc, 2), 'pct', round(100 * (tot - withc) / tot, 1),
        'text_en', round(tot - withc, 2)::text || ' (' || round(100 * (tot - withc) / tot, 1)::text || ' %) of the sales in these dates have no customer recorded (walk-in), so they cannot be in this list. Only sales with a customer on the receipt are analysed.',
        'text_bn', 'এই সময়ের ' || round(tot - withc, 2)::text || ' টাকা (' || round(100 * (tot - withc) / tot, 1)::text || ' %) বিক্রিতে গ্রাহক লেখা নেই (সরাসরি ক্রেতা), তাই এই তালিকায় আসেনি। শুধু রসিদে গ্রাহক থাকা বিক্রি দেখা হয়।'));
    end if;
    nn := least(greatest(coalesce(public.rule_num('report_top_customers_n'), 10), 1), 200)::int;
    out_ := out_ || jsonb_build_array(jsonb_build_object('code', 'top_n', 'n', nn,
      'text_en', 'The top ' || nn || ' customers by sales in these dates' || case when net_on then ' (after returns)' else '' end || '. The number is the setting "Report: how many top customers ... lists" (blank = 10).',
      'text_bn', 'এই সময়ে বিক্রি অনুযায়ী সেরা ' || nn || ' জন গ্রাহক' || case when net_on then ' (ফেরত বাদে)' else '' end || '। সংখ্যাটি নিয়ম "Report: how many top customers ... lists" (ফাঁকা = ১০)।'));
  end if;
  return out_;
end $$;

-- ---------- registry rows ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('y1_daily_sellout', 'Y1', 'stock', 'দৈনিক বিক্রি-শেষ / অবিক্রীত (আউটলেট ও আইটেম)', 'Daily sell-out / unsold at closing', 'দৈনিক sell-out / অবিক্রীত',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["unit","একক","Unit","text"],["opening","শুরুতে","Opening","num"],["produced","তৈরি","Produced","num"],["received","গৃহীত","Received","num"],["returned","ফেরত (গ্রাহক)","Returned by customers","num"],["sold","বিক্রি","Sold","num"],["wasted","নষ্ট","Wasted","num"],["sent","পাঠানো","Sent out","num"],["other","অন্যান্য (±)","Other (+/-)","num"],["closing","শেষে বাকি","Left at closing","num"],["sell_through_pct","বিক্রির হার %","Sell-through %","pct"],["waste_cost","নষ্টের খরচ","Waste cost","money"]]'::jsonb,
  array['produced','received','returned','sold','wasted','sent','other','waste_cost'], 'day', 'desc', array['locations','categories'], false, false, false, 3101),
 ('y2_festival_compare', 'Y2', 'sales', 'উৎসব / মৌসুম তুলনা (গত বছরের সাথে)', 'Festival / season comparison (vs last year)', 'উৎসব / season তুলনা',
  '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["category","ক্যাটাগরি","Category","text"],["unit","একক","Unit","text"],["qty_now","এবার পরিমাণ","Quantity now","num"],["net_now","এবার বিক্রি","Sales now","money"],["qty_prev","আগের পরিমাণ","Quantity before","num"],["net_prev","আগের বিক্রি","Sales before","money"],["qty_change","পরিমাণের পার্থক্য","Quantity change","num"],["qty_change_pct","পরিমাণ %","Quantity %","pct"],["net_change_pct","বিক্রি %","Sales %","pct"],["state","অবস্থা","State","text"]]'::jsonb,
  array['net_now','net_prev'], 'net_now', 'desc', array['locations','categories','items','prev_from','prev_to'], false, false, false, 3102),
 ('y3_customer_items', 'Y3', 'customers', 'সেরা গ্রাহকরা কী কেনেন', 'What the top customers buy', 'সেরা Customer কী কেনেন',
  '[["rank","ক্রম","Rank","int"],["customer_name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["customer_net","গ্রাহকের মোট","Customer total","money"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["unit","একক","Unit","text"],["qty","পরিমাণ","Quantity","num"],["net","বিক্রি","Sales","money"],["share_pct","গ্রাহকের মোটের %","% of customer total","pct"],["bills","বিল","Bills","int"],["last_bought","শেষ কেনা","Last bought","date"]]'::jsonb,
  array['net'], 'rank', 'asc', array['locations','customer'], false, false, false, 3103)
 on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
   sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

-- ---------- drill-down: the transactions behind one row ----------
create or replace function public.report_drill(p_key text, p_ref jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; locs int[]; it uuid; lc int; dd date; df date; dt date; pf date; pt date; cu uuid; rows_ jsonb := '[]'::jsonb; cols jsonb; notes jsonb := '[]'::jsonb; cost_ok boolean := public.rpt_cost_ok();
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); ttl_bn text; ttl_en text; nm_bn text; nm_en text; cnt int; has_item boolean;
        uuid_re constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if not found or p_key not in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items') then raise exception 'unknown_report'; end if;
  if not public._r3_ok(d) then raise exception 'not allowed'; end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'bad_filter'; end if;
  locs := public._r2_locs('{}'::jsonb);
  has_item := p_ref ? 'item' and jsonb_typeof(p_ref -> 'item') = 'string';
  if has_item then
    if (p_ref ->> 'item') !~ uuid_re then raise exception 'bad_filter'; end if;
    it := (p_ref ->> 'item')::uuid;
  end if;

  if p_key = 'y1_daily_sellout' then
    dd := public.rpt_date(p_ref ->> 'day'); lc := case when p_ref ->> 'loc' ~ '^[0-9]{1,9}$' then (p_ref ->> 'loc')::int end;
    if dd is null or lc is null or it is null then raise exception 'bad_filter'; end if;
    select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into nm_bn, nm_en from public.items where id = it;
    ttl_bn := nm_bn || ' · ' || dd::text || ' · স্টকের নড়াচড়া'; ttl_en := nm_en || ' · ' || dd::text || ' · stock movements';
    cols := '[["time","সময়","Time","text"],["reason","ধরন","Kind","text"],["qty","পরিমাণ (±)","Quantity (+/-)","num"],["ref","উৎস","Source","text"],["staff","কে","By","text"],["note","নোট","Note","text"]'
            || case when cost_ok then ',["unit_cost","একক খরচ","Unit cost","money"]' else '' end || ']';
    select coalesce(jsonb_agg(jsonb_build_object('time', to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI'), 'reason', l.reason, 'qty', l.qty_delta,
        'ref', case when l.ref_type = 'sale' then coalesce((select 'Receipt ' || s.receipt::text from public.sales s where s.id::text = l.ref_id), 'sale') else coalesce(l.ref_type, '') || case when l.ref_id is not null then ' ' || left(l.ref_id, 8) else '' end end,
        'staff', (select p.staff_id from public.profiles p where p.id = l.created_by), 'note', l.note, 'unit_cost', case when cost_ok then l.unit_cost end) order by l.made_at, l.id), '[]'::jsonb)
      into rows_ from public.stock_ledger l
     where lc = any (locs) and l.location_id = lc and l.item_id = it and (l.made_at at time zone 'Asia/Dhaka')::date = dd;
  elsif p_key = 'y2_festival_compare' then
    df := public.rpt_date(p_ref ->> 'from'); dt := public.rpt_date(p_ref ->> 'to'); pf := public.rpt_date(p_ref ->> 'pf'); pt := public.rpt_date(p_ref ->> 'pt');
    if df is null or dt is null or pf is null or pt is null then raise exception 'bad_filter'; end if;
    if has_item then select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into nm_bn, nm_en from public.items where id = it; else nm_bn := 'কুইক / তালিকা-বহির্ভূত'; nm_en := 'Quick / unlisted'; end if;
    ttl_bn := nm_bn || ' · বিক্রির লেনদেন'; ttl_en := nm_en || ' · sales transactions';
    cols := '[["period","সময়","Period","text"],["day","তারিখ","Date","date"],["receipt","রসিদ","Receipt","int"],["location_bn","লোকেশন","Location","text"],["kind","ধরন","Kind","text"],["qty","পরিমাণ","Quantity","num"],["amount","টাকা","Amount","money"]]';
    select coalesce(jsonb_agg(x.j order by x.d, x.rc), '[]'::jsonb) into rows_ from (
      select f.day as d, f.receipt as rc, jsonb_build_object('period', case when f.day between df and dt then 'এবার / this time' else 'আগের / before' end, 'day', f.day, 'receipt', f.receipt, 'location_bn', f.location_bn,
             'kind', 'বিক্রি / sale', 'qty', f.qty, 'amount', round(f.net, 2)) as j
        from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and (f.item_id is not distinct from case when has_item then it end) and (f.day between df and dt or f.day between pf and pt)
      union all
      select r.day, r.receipt, jsonb_build_object('period', case when r.day between df and dt then 'এবার / this time' else 'আগের / before' end, 'day', r.day, 'receipt', r.receipt, 'location_bn', r.location_bn,
             'kind', 'ফেরত / return', 'qty', -r.qty, 'amount', -round(r.ret_amt, 2))
        from public.rpt_ret_l r where net_on and r.location_id = any (locs) and (r.item_id is not distinct from case when has_item then it end) and (r.day between df and dt or r.day between pf and pt)) x;
  else
    cu := case when (p_ref ->> 'customer') ~ uuid_re then (p_ref ->> 'customer')::uuid end; df := public.rpt_date(p_ref ->> 'from'); dt := public.rpt_date(p_ref ->> 'to');
    if cu is null or it is null or df is null or dt is null then raise exception 'bad_filter'; end if;
    select coalesce(name, '-') into nm_bn from public.customers where id = cu; select coalesce(name_bn, ''), coalesce(name_en, name_bn, '') into ttl_bn, ttl_en from public.items where id = it;
    ttl_en := nm_bn || ' · ' || ttl_en || ' · sales'; ttl_bn := nm_bn || ' · ' || ttl_bn || ' · বিক্রির লেনদেন';
    cols := '[["day","তারিখ","Date","date"],["receipt","রসিদ","Receipt","int"],["location_bn","লোকেশন","Location","text"],["kind","ধরন","Kind","text"],["qty","পরিমাণ","Quantity","num"],["amount","টাকা","Amount","money"]]';
    select coalesce(jsonb_agg(x.j order by x.d, x.rc), '[]'::jsonb) into rows_ from (
      select f.day as d, f.receipt as rc, jsonb_build_object('day', f.day, 'receipt', f.receipt, 'location_bn', f.location_bn, 'kind', 'বিক্রি / sale', 'qty', f.qty, 'amount', round(f.net, 2)) as j
        from public.sales_fact f where f.status = 'done' and f.location_id = any (locs) and f.customer_id = cu and f.item_id = it and f.day between df and dt
      union all
      select r.day, r.receipt, jsonb_build_object('day', r.day, 'receipt', r.receipt, 'location_bn', r.location_bn, 'kind', 'ফেরত / return', 'qty', -r.qty, 'amount', -round(r.ret_amt, 2))
        from public.rpt_ret_l r where net_on and r.location_id = any (locs) and r.customer_id = cu and r.item_id = it and r.day between df and dt) x;
  end if;
  cnt := jsonb_array_length(rows_);
  if cnt > 500 then
    rows_ := (select jsonb_agg(e) from (select e from jsonb_array_elements(rows_) e limit 500) z);
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', 500, 'groups', cnt));
  end if;
  return jsonb_build_object('title_bn', ttl_bn, 'title_en', ttl_en, 'rows', rows_, 'notes', notes, 'count', cnt,
    'columns', (select jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3)) from jsonb_array_elements(cols) c));
end $$;

revoke all on function public._rptb1_p403_present(), public._r3q_y1_daily_sellout(date, date, int[], jsonb), public._r3q_y2_festival_compare(date, date, int[], jsonb), public._r3q_y3_customer_items(date, date, int[], jsonb),
  public._rptb1_y_notes(text, date, date, int[], jsonb) from public, anon, authenticated;
revoke all on function public.report_drill(text, jsonb) from public, anon;
grant execute on function public.report_drill(text, jsonb) to authenticated;

-- ---------------------------------------------------------------- phase404.sql
-- Phase 404 (bos404) - RPT-B4 / R3a: PRODUCTION CAPTURE, TABLES AND HELPERS.
-- Paste after phase 99 (and after phases 400-403 / 430-436 if they are used; this file does not need them). Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #40, #44, #45, #49, #52, #53, #55 (data capture gaps: plan, order, actual issue, reject/rework).
--
-- WHAT THIS ADDS (tables only; the entry functions are in phase 405, the reports in 406-408)
--   production_plans        a plan line: day, place, item, planned batches and/or planned quantity (base unit). Cancelled, never deleted.
--   production_orders       an order for a product: ordered day, due day, producing place, optional requesting outlet, quantity (base unit), status open / closed / cancelled.
--   production_run_links    which plan / order a finished production run belongs to (written by a person; unlinked runs are matched to a plan by place + item + day in the report).
--   production_issue_actual what was REALLY taken for a run, per ingredient (the production screen books exactly the recipe need; a person records the real use). Replaced lines stay as history.
--   production_loss         reject / rework quantity per run with a reason from the existing list wastage_reasons; kind 'none' = "checked, no reject or rework".
-- Nothing here moves stock or money. A blank is "data not captured", never 0. Entry rights reuse the grant stock_production (owner always); reading uses the existing report / recipe rights.
-- Paper form code of the entry screens: to be given by owner.

do $g$ begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'production_runs' and column_name = 'yield_actual') then raise exception 'phase404 needs phase74 (production_runs.yield_actual)'; end if;
  if to_regclass('public.stock_transfers') is null or to_regclass('public.stock_wastage') is null then raise exception 'phase404 needs the stock phases (stock_transfers, stock_wastage)'; end if;
  if to_regprocedure('public._recipe_read()') is null then raise exception 'phase404 needs phase19 (_recipe_read)'; end if;
end $g$;

-- ---------- who may read / write ----------
-- reading production data: the owner, the stock report right, or anyone who may read recipes / production, or move stock between places; and the place must be theirs
create or replace function public._rb4_prod_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public._recipe_read() or public.has_grant('stock_transfer', p_loc));
$$;
-- writing production capture: the owner or the grant stock_production at that place
create or replace function public._rb4_prod_entry(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('stock_production', p_loc));
$$;
-- the Dhaka calendar day of a timestamp
create or replace function public._rb4_day(p_ts timestamptz) returns date language sql immutable as $$ select (p_ts at time zone 'Asia/Dhaka')::date $$;
create or replace function public._rb4_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- range check shared by every report: both days present, to >= from, at most 800 days
create or replace function public._rb4_range(p_from date, p_to date, out f date, out t date) language plpgsql stable as $$
begin
  f := coalesce(p_from, public._rb4_today() - 30); t := coalesce(p_to, public._rb4_today());
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
end $$;

-- ---------- tables ----------
create table if not exists public.production_plans (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  plan_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  recipe_id uuid references public.recipes(id),
  planned_batches numeric check (planned_batches is null or (planned_batches > 0 and planned_batches <= 100000)),
  planned_qty numeric check (planned_qty is null or (planned_qty > 0 and planned_qty <= 999999999)),      -- item base unit
  note text check (note is null or length(note) <= 300),
  status text not null default 'planned' check (status in ('planned', 'cancelled')),
  cancel_note text, cancelled_by uuid, cancelled_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (planned_batches is not null or planned_qty is not null)
);
create index if not exists production_plans_day on public.production_plans (plan_date, location_id);
create index if not exists production_plans_item on public.production_plans (item_id, plan_date);

create table if not exists public.production_orders (
  id bigint generated always as identity primary key,       -- shown as the order number; it is NOT a paper form code
  client_id uuid unique,
  order_date date not null,
  due_date date,
  location_id int not null references public.locations(id),          -- the producing place
  for_location_id int references public.locations(id),               -- the outlet that asked (blank = for stock)
  item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0 and qty <= 999999999),         -- item base unit
  note text check (note is null or length(note) <= 300),
  status text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  close_note text, closed_by uuid, closed_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check (due_date is null or due_date >= order_date)
);
create index if not exists production_orders_open on public.production_orders (status, due_date);
create index if not exists production_orders_loc on public.production_orders (location_id, order_date);

create table if not exists public.production_run_links (
  run_id uuid primary key references public.production_runs(id),
  plan_id uuid references public.production_plans(id),
  order_id bigint references public.production_orders(id),
  linked_by uuid, linked_at timestamptz not null default now()
);
create index if not exists production_run_links_plan on public.production_run_links (plan_id) where plan_id is not null;
create index if not exists production_run_links_order on public.production_run_links (order_id) where order_id is not null;

create table if not exists public.production_issue_actual (
  id bigserial primary key,
  run_id uuid not null references public.production_runs(id),
  item_id uuid not null references public.items(id),
  actual_qty numeric not null check (actual_qty >= 0 and actual_qty <= 999999999),     -- item base unit; 0 = checked, none used
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'replaced')),
  entered_by uuid, entered_staff text, entered_at timestamptz not null default now(),
  replaced_by uuid, replaced_at timestamptz
);
create unique index if not exists production_issue_actual_one on public.production_issue_actual (run_id, item_id) where status = 'active';
create index if not exists production_issue_actual_run on public.production_issue_actual (run_id);

create table if not exists public.production_loss (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  run_id uuid not null references public.production_runs(id),
  kind text not null check (kind in ('reject', 'rework', 'none')),
  qty numeric not null check (qty >= 0 and qty <= 999999999),          -- finished-item base unit; 0 only for kind 'none'
  reason_code text,                                                      -- option_lists.value_code of list wastage_reasons (the id, never the label)
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((kind = 'none' and qty = 0) or (kind <> 'none' and qty > 0))
);
create index if not exists production_loss_run on public.production_loss (run_id);

-- ---------- audit lines (who, when, what changed) and read rules ----------
do $t$
declare t text;
begin
  foreach t in array array['production_plans', 'production_orders', 'production_run_links', 'production_issue_actual', 'production_loss'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, case t when 'production_run_links' then 'run_id' else 'id' end);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $t$;
drop policy if exists production_plans_read on public.production_plans;
create policy production_plans_read on public.production_plans for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_orders_read on public.production_orders;
create policy production_orders_read on public.production_orders for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_run_links_read on public.production_run_links;
create policy production_run_links_read on public.production_run_links for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));
drop policy if exists production_issue_actual_read on public.production_issue_actual;
create policy production_issue_actual_read on public.production_issue_actual for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));
drop policy if exists production_loss_read on public.production_loss;
create policy production_loss_read on public.production_loss for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));

-- ---------- helpers are closed to browsers ----------
do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_prod_view', '_rb4_prod_entry', '_rb4_day', '_rb4_today', '_rb4_range') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);      -- row-level-security policies and the report functions run as the caller, so the checks must be callable
  end loop;
end $c$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase405.sql
-- Phase 405 (bos405) - RPT-B4 / R3b: PRODUCTION CAPTURE, ENTRY FUNCTIONS.
-- Paste after phase404. Paste-twice safe. No earlier phase file is edited; production_post is NOT touched (another package sends the actual yield from the production screen).
--
-- ENTRY FUNCTIONS (all need the owner or the grant stock_production at the place; every refusal is a server refusal, not only a hidden button)
--   prod_plan_add / prod_plan_cancel           a plan line for a day, place and item (batches and/or quantity)
--   prod_order_add / prod_order_close / prod_order_cancel   an order for a product (producing place, optional requesting outlet, quantity, due day)
--   prod_run_link                               tell which plan / order a finished run belongs to
--   prod_actual_issue_set                       the REAL quantity used per ingredient for a run (partial calls allowed; an older line becomes history)
--   prod_loss_add / prod_loss_void              reject / rework quantity with a reason, or "checked, none"
--   prod_run_detail / prod_runs_recent          read side of the entry screen (blind: the booked recipe quantity of a line is shown only after the real quantity was saved, BUILD-RULES 9)
-- Nothing here posts stock or money. The real use is a record; the stock was booked by the production screen from the recipe (see the note in docs/integration/RPT-B4.md).

do $g$ begin
  if to_regclass('public.production_loss') is null then raise exception 'phase405 needs phase404 first'; end if;
end $g$;

-- ---------- plan ----------
create or replace function public.prod_plan_add(p_date date, p_loc int, p_item uuid, p_batches numeric default null, p_qty numeric default null, p_unit text default null,
                                                p_recipe uuid default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_plans; it public.items; r public.recipes; sid text; id_ uuid; bq numeric; pq numeric; pb numeric := p_batches; n text := nullif(btrim(p_note), ''); yb numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_plans where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_prod_entry(p_loc) then raise exception 'not allowed'; end if;
  if p_date is null or abs(p_date - public._rb4_today()) > 400 then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if pb is null and p_qty is null then raise exception 'plan_needs_batches_or_qty'; end if;
  if pb is not null and not (pb > 0 and pb <= 100000) then raise exception 'bad_qty'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_recipe is not null then
    select * into r from public.recipes where id = p_recipe;
    if not found or r.item_id <> p_item then raise exception 'recipe_not_found'; end if;
  elsif pb is not null then
    select * into r from public.recipes where item_id = p_item and active order by version desc limit 1;      -- the newest active recipe of the item; none = the quantity stays blank
  end if;
  if p_qty is not null then
    bq := public._base_qty(p_item, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    pq := bq;
  elsif r.id is not null then
    yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
    if yb is not null and yb > 0 then pq := round(yb * pb, 4); end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_plans (client_id, plan_date, location_id, item_id, recipe_id, planned_batches, planned_qty, note, created_by, created_staff)
    values (p_client, p_date, p_loc, p_item, r.id, pb, pq, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'planned_batches', pb, 'planned_qty', pq, 'recipe_id', r.id);
end $$;

create or replace function public.prod_plan_cancel(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_plans;
begin
  select * into r from public.production_plans where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_plans set status = 'cancelled', cancel_note = left(btrim(p_note), 300), cancelled_by = auth.uid(), cancelled_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- ---------- order ----------
create or replace function public.prod_order_add(p_date date, p_due date, p_loc int, p_for_loc int, p_item uuid, p_qty numeric, p_unit text default null,
                                                 p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_orders; it public.items; sid text; id_ bigint; bq numeric; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_orders where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_for_loc is not null and (p_for_loc = p_loc or not exists (select 1 from public.locations where id = p_for_loc)) then raise exception 'bad_location'; end if;
  -- the producing place's production staff, or the requesting outlet's transfer staff, or the owner
  if not (public._rb4_prod_entry(p_loc) or (p_for_loc is not null and public.can_loc(p_for_loc) and public.has_grant('stock_transfer', p_for_loc))) then raise exception 'not allowed'; end if;
  if p_date is null or abs(p_date - public._rb4_today()) > 400 then raise exception 'bad_date'; end if;
  if p_due is not null and p_due < p_date then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_orders (client_id, order_date, due_date, location_id, for_location_id, item_id, qty, note, created_by, created_staff)
    values (p_client, p_date, p_due, p_loc, p_for_loc, p_item, bq, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'qty', bq);
end $$;

-- the quantity made so far on an order = the finished runs linked to it (void runs do not count)
create or replace function public._rb4_order_made(p_order bigint) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(r.yield_base), 0) from public.production_run_links k join public.production_runs r on r.id = k.run_id where k.order_id = p_order and r.status = 'done';
$$;

create or replace function public.prod_order_close(p_id bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.production_orders; made numeric;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb4_prod_entry(o.location_id) or (o.for_location_id is not null and public.can_loc(o.for_location_id) and public.has_grant('stock_transfer', o.for_location_id))) then raise exception 'not allowed'; end if;
  if o.status = 'closed' then return jsonb_build_object('dup', true, 'status', 'closed'); end if;
  if o.status <> 'open' then raise exception 'order_not_open'; end if;
  made := public._rb4_order_made(p_id);
  if made < o.qty and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- closing short of the ordered quantity needs a reason
  update public.production_orders set status = 'closed', close_note = left(btrim(p_note), 300), closed_by = auth.uid(), closed_at = now() where id = p_id;
  return jsonb_build_object('status', 'closed', 'made', made, 'ordered', o.qty);
end $$;

create or replace function public.prod_order_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.production_orders;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb4_prod_entry(o.location_id) or (o.for_location_id is not null and public.can_loc(o.for_location_id) and public.has_grant('stock_transfer', o.for_location_id))) then raise exception 'not allowed'; end if;
  if o.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if o.status <> 'open' then raise exception 'order_not_open'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_orders set status = 'cancelled', close_note = left(btrim(p_note), 300), closed_by = auth.uid(), closed_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- ---------- link a finished run to a plan / an order ----------
create or replace function public.prod_run_link(p_run uuid, p_plan uuid default null, p_order bigint default null, p_clear_plan boolean default false, p_clear_order boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; pl public.production_plans; o public.production_orders; k public.production_run_links; np uuid; no_ bigint;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  select * into k from public.production_run_links where run_id = p_run;
  np := case when p_clear_plan then null when p_plan is not null then p_plan else k.plan_id end;
  no_ := case when p_clear_order then null when p_order is not null then p_order else k.order_id end;
  if np is not null then
    select * into pl from public.production_plans where id = np;
    if not found or pl.item_id <> r.item_id or pl.location_id <> r.location_id then raise exception 'link_mismatch'; end if;
    if pl.status = 'cancelled' then raise exception 'plan_cancelled'; end if;
  end if;
  if no_ is not null then
    select * into o from public.production_orders where id = no_;
    if not found or o.item_id <> r.item_id or o.location_id <> r.location_id then raise exception 'link_mismatch'; end if;
    if o.status <> 'open' and no_ is distinct from k.order_id then raise exception 'order_not_open'; end if;      -- an already linked closed order keeps its link; a new link needs an open order
  end if;
  insert into public.production_run_links (run_id, plan_id, order_id, linked_by) values (p_run, np, no_, auth.uid())
    on conflict (run_id) do update set plan_id = excluded.plan_id, order_id = excluded.order_id, linked_by = excluded.linked_by, linked_at = now();
  return jsonb_build_object('run_id', p_run, 'plan_id', np, 'order_id', no_);
end $$;

-- ---------- the real use of ingredients ----------
-- p_lines = [{"item_id": "...", "qty": 4.2, "unit": "kg"}]; only the lines sent are set. A second call for the same ingredient keeps the first line as history.
create or replace function public.prod_actual_issue_set(p_run uuid, p_lines jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; ln jsonb; it public.items; bq numeric; sid text; n text := nullif(btrim(p_note), ''); done_ int := 0; ids uuid[] := '{}'; seen uuid[] := '{}';
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if jsonb_array_length(p_lines) > 100 then raise exception 'too_many_lines'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- checks first, nothing is written until every line is fine
  for ln in select * from jsonb_array_elements(p_lines) loop
    if coalesce(ln ->> 'item_id', '') !~ '^[0-9a-f-]{36}$' then raise exception 'item_not_found'; end if;
    select * into it from public.items where id = (ln ->> 'item_id')::uuid;
    if not found or not it.is_active then raise exception 'item_not_found'; end if;
    if (ln ->> 'item_id')::uuid = any (seen) then raise exception 'duplicate_item'; end if;
    seen := seen || (ln ->> 'item_id')::uuid;
    if coalesce(ln ->> 'qty', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'bad_qty'; end if;
    bq := public._base_qty(it.id, (ln ->> 'qty')::numeric, nullif(ln ->> 'unit', ''));
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  end loop;
  for ln in select * from jsonb_array_elements(p_lines) loop
    bq := round(public._base_qty((ln ->> 'item_id')::uuid, (ln ->> 'qty')::numeric, nullif(ln ->> 'unit', '')), 4);
    update public.production_issue_actual set status = 'replaced', replaced_by = auth.uid(), replaced_at = now() where run_id = p_run and item_id = (ln ->> 'item_id')::uuid and status = 'active';
    insert into public.production_issue_actual (run_id, item_id, actual_qty, note, entered_by, entered_staff) values (p_run, (ln ->> 'item_id')::uuid, bq, n, auth.uid(), sid);
    done_ := done_ + 1;
  end loop;
  return jsonb_build_object('run_id', p_run, 'lines', done_);
end $$;

-- ---------- reject / rework ----------
create or replace function public.prod_loss_add(p_run uuid, p_kind text, p_qty numeric default null, p_unit text default null, p_reason text default null,
                                                p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_loss; r public.production_runs; bq numeric; sid text; id_ uuid; n text := nullif(btrim(p_note), ''); used numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_loss where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_kind is null or p_kind not in ('reject', 'rework', 'none') then raise exception 'bad_kind'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_kind = 'none' then
    if exists (select 1 from public.production_loss where run_id = p_run and status = 'active' and kind in ('reject', 'rework')) then raise exception 'loss_already_recorded'; end if;
    bq := 0;
  else
    if p_qty is null then raise exception 'bad_qty'; end if;
    bq := public._base_qty(r.item_id, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
    select coalesce(sum(qty), 0) into used from public.production_loss where run_id = p_run and status = 'active' and kind in ('reject', 'rework');
    if used + bq > r.yield_base then raise exception 'exceeds_output'; end if;      -- reject + rework cannot be more than the run made
    -- a recorded loss replaces an earlier "checked, none" line of the run
    update public.production_loss set status = 'void', void_note = 'replaced by a loss entry', void_by = auth.uid(), void_at = now() where run_id = p_run and kind = 'none' and status = 'active';
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_loss (client_id, run_id, kind, qty, reason_code, note, created_by, created_staff)
    values (p_client, p_run, p_kind, bq, case when p_kind = 'none' then null else p_reason end, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'qty', bq);
end $$;

create or replace function public.prod_loss_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_loss; r public.production_runs;
begin
  select * into l from public.production_loss where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  select * into r from public.production_runs where id = l.run_id;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if l.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_loss set status = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

-- ---------- read side of the entry screen ----------
-- what the production screen booked out for a run (the recipe need at the average cost of the day)
create or replace function public._rb4_run_booked(p_run uuid) returns table (item_id uuid, qty numeric, unit_cost numeric)
language sql stable security definer set search_path = public as $$
  select l.item_id, sum(-l.qty_delta), case when sum(-l.qty_delta) > 0 then sum(-l.qty_delta * coalesce(l.unit_cost, 0)) / sum(-l.qty_delta) end
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = p_run::text and l.reason = 'issue_out' group by l.item_id;
$$;

create or replace function public.prod_run_detail(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs; out_ jsonb;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_view(r.location_id) then raise exception 'not allowed'; end if;
  select jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'day', public._rb4_day(r.made_at), 'status', r.status, 'location_id', r.location_id,
      'location', l.name_bn, 'location_en', l.name_en, 'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id),
      'batches', r.batches, 'output', r.yield_base, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'can_edit', public._rb4_prod_entry(r.location_id) and r.status = 'done',
      'link', (select jsonb_build_object('plan_id', k.plan_id, 'order_id', k.order_id) from public.production_run_links k where k.run_id = r.id),
      -- ingredients: the booked recipe quantity is shown ONLY for a line whose real quantity is already saved
      'issue_lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', u.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(u.item_id),
            'actual_qty', a.actual_qty, 'actual_at', a.entered_at, 'booked_qty', case when a.id is not null then u.qty end, 'diff', case when a.id is not null then round(a.actual_qty - u.qty, 4) end) order by ii.code)
          from public._rb4_run_booked(r.id) u join public.items ii on ii.id = u.item_id
          left join public.production_issue_actual a on a.run_id = r.id and a.item_id = u.item_id and a.status = 'active'), '[]'::jsonb),
      'extra_lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', a.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(a.item_id), 'actual_qty', a.actual_qty) order by ii.code)
          from public.production_issue_actual a join public.items ii on ii.id = a.item_id
         where a.run_id = r.id and a.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) u where u.item_id = a.item_id)), '[]'::jsonb),
      'losses', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'qty', x.qty, 'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn, 'note', x.note, 'created_staff', x.created_staff, 'created_at', x.created_at) order by x.created_at)
          from public.production_loss x left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code where x.run_id = r.id and x.status = 'active'), '[]'::jsonb),
      'candidate_plans', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'plan_date', p.plan_date, 'planned_qty', p.planned_qty, 'planned_batches', p.planned_batches) order by p.plan_date desc)
          from public.production_plans p where p.location_id = r.location_id and p.item_id = r.item_id and p.status = 'planned' and p.plan_date between public._rb4_day(r.made_at) - 14 and public._rb4_day(r.made_at) + 14), '[]'::jsonb),
      'open_orders', coalesce((select jsonb_agg(jsonb_build_object('id', o2.id, 'order_date', o2.order_date, 'due_date', o2.due_date, 'qty', o2.qty, 'made', public._rb4_order_made(o2.id)) order by o2.due_date nulls last, o2.id)
          from public.production_orders o2 where o2.location_id = r.location_id and o2.item_id = r.item_id and o2.status = 'open'), '[]'::jsonb))
    into out_ from public.locations l, public.items i where l.id = r.location_id and i.id = r.item_id;
  return out_;
end $$;

-- finished runs of a period with what is already captured for each (counts only; "none" for loss is its own state)
create or replace function public.prod_runs_recent(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'output', r.yield_base, 'yield_actual', r.yield_actual,
        'actual_issue_lines', (select count(*) from public.production_issue_actual a where a.run_id = r.id and a.status = 'active'),
        'loss_state', (select case when bool_or(x.kind in ('reject', 'rework')) then 'recorded' when bool_or(x.kind = 'none') then 'none' end from public.production_loss x where x.run_id = r.id and x.status = 'active'),
        'linked', exists (select 1 from public.production_run_links k where k.run_id = r.id and (k.plan_id is not null or k.order_id is not null)),
        'can_edit', public._rb4_prod_entry(r.location_id)) order by r.made_at desc)
      from (select * from public.production_runs x where x.status = 'done' and public._rb4_day(x.made_at) between f and t and (p_loc is null or x.location_id = p_loc) and public._rb4_prod_view(x.location_id) order by x.made_at desc limit 500) r
      join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_order_made', '_rb4_run_booked') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('prod_plan_add', 'prod_plan_cancel', 'prod_order_add', 'prod_order_close', 'prod_order_cancel', 'prod_run_link', 'prod_actual_issue_set', 'prod_loss_add', 'prod_loss_void', 'prod_run_detail', 'prod_runs_recent') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase406.sql
-- Phase 406 (bos406) - RPT-B4 / R4a: PLAN VS ACTUAL (#40), ORDER STATUS AND PENDING ORDERS (#52), PRODUCTION-TO-DISPATCH RECONCILIATION (#53).
-- Paste after phase405. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
-- Who may read: the owner, the stock report right (report_stock), the recipe / production readers, and the stock-transfer staff of the place. Every figure is limited to the places the reader may see.
-- What a report cannot know is said in words: "plan_not_captured", "qty_not_captured" ... a blank is never turned into 0 and never added into a total.
--
--   rb4_plan_vs_actual(from, to, place)   one row per plan key (place + item + plan day): planned batches / quantity against what was really made (finished runs, quantity actually booked);
--                                         runs with no plan are listed apart. A run belongs to its linked plan; an unlinked run belongs to the plan of the same place + item + day.
--   rb4_order_status(from, to, place, status)   orders of the period and every order still open: made so far (linked finished runs), balance, overdue days, a derived state.
--   rb4_dispatch_recon(from, to, place)   per day, producing place and item: made - sent - received - in transit - short, and the quantity on hand now at the producing place.

do $g$ begin
  if to_regprocedure('public.prod_run_link(uuid,uuid,bigint,boolean,boolean)') is null then raise exception 'phase406 needs phase405 first'; end if;
end $g$;

-- every finished run with the plan day it belongs to (linked plan first, else its own Dhaka day), limited to the places the reader may see
create or replace function public._rb4_pva_runs(f date, t date, p_loc int) returns table (run_id uuid, location_id int, item_id uuid, kday date, batches numeric, qty numeric)
language sql stable security definer set search_path = public as $$
  select r.id, r.location_id, r.item_id, coalesce(pp.plan_date, public._rb4_day(r.made_at)), r.batches, r.yield_base
    from public.production_runs r
    left join public.production_run_links k on k.run_id = r.id
    left join public.production_plans pp on pp.id = k.plan_id and pp.status = 'planned'
   where r.status = 'done' and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)
     and coalesce(pp.plan_date, public._rb4_day(r.made_at)) between f and t;
$$;

create or replace function public.rb4_plan_vs_actual(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; un jsonb; sm jsonb; nplans int; ncancel int; notes jsonb := '[]'::jsonb; td date := public._rb4_today();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select count(*) into nplans from public.production_plans p where p.status = 'planned' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id);
  select count(*) into ncancel from public.production_plans p where p.status = 'cancelled' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id);
  if nplans = 0 then notes := notes || jsonb_build_object('code', 'plan_not_captured', 'field', 'production plan'); end if;

  select coalesce(jsonb_agg(z.j order by z.pd desc, z.code, z.lid), '[]'::jsonb) into rows_ from (
    select k.plan_date as pd, i.code, k.location_id as lid, jsonb_build_object('plan_date', k.plan_date, 'location_id', k.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'item_id', k.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(k.item_id),
        'plans_n', k.plans_n, 'plan_ids', k.plan_ids,
        'planned_batches', case when k.batches_missing = 0 then k.batches end, 'planned_qty', case when k.qty_missing = 0 then k.qty end, 'planned_qty_missing_n', k.qty_missing,
        'actual_batches', coalesce(a.batches, 0), 'actual_qty', coalesce(a.qty, 0), 'runs_n', coalesce(a.runs_n, 0), 'run_ids', coalesce(a.run_ids, '[]'::jsonb),
        'achievement_pct', case when k.qty_missing = 0 and k.qty > 0 and (coalesce(a.runs_n, 0) > 0 or k.plan_date <= td) then round(coalesce(a.qty, 0) / k.qty * 100, 1) end,
        'status', case when k.qty_missing > 0 then 'qty_not_captured'
                       when coalesce(a.runs_n, 0) = 0 and k.plan_date > td then 'not_due_yet'
                       when coalesce(a.runs_n, 0) = 0 then 'not_made'
                       when a.qty < k.qty then 'short' when a.qty = k.qty then 'met' else 'over' end) as j
      from (select p.location_id, p.item_id, p.plan_date, count(*) as plans_n, jsonb_agg(p.id order by p.created_at) as plan_ids,
                   sum(p.planned_batches) as batches, count(*) filter (where p.planned_batches is null) as batches_missing,
                   sum(p.planned_qty) as qty, count(*) filter (where p.planned_qty is null) as qty_missing
              from public.production_plans p
             where p.status = 'planned' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id)
             group by p.location_id, p.item_id, p.plan_date) k
      left join (select ra.location_id, ra.item_id, ra.kday, sum(ra.batches) as batches, sum(ra.qty) as qty, count(*) as runs_n, jsonb_agg(ra.run_id) as run_ids from public._rb4_pva_runs(f, t, p_loc) ra group by 1, 2, 3) a
             on a.location_id = k.location_id and a.item_id = k.item_id and a.kday = k.plan_date
      join public.items i on i.id = k.item_id join public.locations l on l.id = k.location_id) z;

  select coalesce(jsonb_agg(jsonb_build_object('day', u.kday, 'location_id', u.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', u.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
      'base_unit', public._item_base(u.item_id), 'runs_n', u.runs_n, 'run_ids', u.run_ids, 'batches', u.batches, 'qty', u.qty) order by u.kday desc, i.code), '[]'::jsonb) into un
    from (select ra.location_id, ra.item_id, ra.kday, sum(ra.batches) as batches, sum(ra.qty) as qty, count(*) as runs_n, jsonb_agg(ra.run_id) as run_ids
            from public._rb4_pva_runs(f, t, p_loc) ra
           where not exists (select 1 from public.production_plans p where p.status = 'planned' and p.location_id = ra.location_id and p.item_id = ra.item_id and p.plan_date = ra.kday)
           group by 1, 2, 3) u join public.items i on i.id = u.item_id join public.locations l on l.id = u.location_id;

  select jsonb_build_object('plans', nplans, 'cancelled_plans', ncancel,
      'rows_met', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('met', 'over')),
      'rows_short', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'short'),
      'rows_not_made', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'not_made'),
      'rows_qty_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'qty_not_captured'),
      'unplanned_runs', coalesce((select sum((e ->> 'runs_n')::int) from jsonb_array_elements(un) e), 0)) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'unplanned', un, 'summary', sm, 'notes', notes);
end $$;

create or replace function public.rb4_order_status(p_from date default null, p_to date default null, p_loc int default null, p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; td date := public._rb4_today(); rows_ jsonb; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('open', 'closed', 'cancelled', 'pending', 'overdue') then raise exception 'bad_status'; end if;
  select coalesce(jsonb_agg(z.j order by z.so, z.due nulls last, z.id), '[]'::jsonb) into rows_ from (
    select o.id, o.due_date as due, case y.state when 'overdue' then 0 when 'not_started' then 1 when 'partly_made' then 2 when 'made_not_closed' then 3 when 'closed' then 4 else 5 end as so,
      jsonb_build_object('order_no', o.id, 'order_date', o.order_date, 'due_date', o.due_date, 'location_id', o.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'for_location_id', o.for_location_id, 'for_location', fl.name_bn, 'for_location_en', fl.name_en,
        'item_id', o.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(o.item_id),
        'qty', o.qty, 'made', y.made, 'balance', case when o.status = 'open' then greatest(o.qty - y.made, 0) end, 'runs_n', y.runs_n, 'run_ids', y.run_ids,
        'status', o.status, 'state', y.state, 'days_overdue', case when o.status = 'open' and o.due_date is not null and o.due_date < td and y.made < o.qty then td - o.due_date end,
        'due_not_captured', o.due_date is null, 'note', o.note, 'close_note', o.close_note, 'created_staff', o.created_staff) as j
      from public.production_orders o
      join public.items i on i.id = o.item_id join public.locations l on l.id = o.location_id left join public.locations fl on fl.id = o.for_location_id
      cross join lateral (select coalesce(sum(r.yield_base), 0) as made, count(r.id) as runs_n, coalesce(jsonb_agg(r.id), '[]'::jsonb) as run_ids,
          case when o.status = 'cancelled' then 'cancelled' when o.status = 'closed' then 'closed'
               when coalesce(sum(r.yield_base), 0) >= o.qty then 'made_not_closed'
               when o.due_date is not null and o.due_date < td then 'overdue'
               when coalesce(sum(r.yield_base), 0) > 0 then 'partly_made' else 'not_started' end as state
          from public.production_run_links k join public.production_runs r on r.id = k.run_id and r.status = 'done' where k.order_id = o.id) y
     where (o.order_date between f and t or o.status = 'open') and (p_loc is null or o.location_id = p_loc or o.for_location_id = p_loc)
       and (public._rb4_prod_view(o.location_id) or (o.for_location_id is not null and public._rb4_prod_view(o.for_location_id)))
       and (p_status is null or (p_status in ('open', 'closed', 'cancelled') and o.status = p_status) or (p_status = 'pending' and o.status = 'open') or (p_status = 'overdue' and y.state = 'overdue'))) z;
  select jsonb_build_object('orders', jsonb_array_length(rows_),
      'open', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'open'),
      'overdue', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'overdue'),
      'not_started', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'not_started'),
      'made_not_closed', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'made_not_closed'),
      'due_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'open' and (e ->> 'due_not_captured')::boolean)) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm,
    'notes', case when jsonb_array_length(rows_) = 0 and not exists (select 1 from public.production_orders) then jsonb_build_array(jsonb_build_object('code', 'order_not_captured', 'field', 'production order')) else '[]'::jsonb end);
end $$;

-- per day, producing place and item: made, sent, received, in transit, short, cancelled
create or replace function public._rb4_dr_rows(f date, t date, p_loc int) returns table (day date, location_id int, item_id uuid, made numeric, runs_n int, sent numeric, received numeric, in_transit numeric, short numeric, cancelled numeric, transfers_n int)
language sql stable security definer set search_path = public as $$
  select d.day, d.location_id, d.item_id, sum(d.made), sum(d.runs_n)::int, sum(d.sent), sum(d.received), sum(d.in_transit), sum(d.short), sum(d.cancelled), sum(d.transfers_n)::int
    from (
      select public._rb4_day(r.made_at) as day, r.location_id, r.item_id, r.yield_base as made, 1 as runs_n, 0::numeric as sent, 0::numeric as received, 0::numeric as in_transit, 0::numeric as short, 0::numeric as cancelled, 0 as transfers_n
        from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)
      union all
      select public._rb4_day(s.sent_at), s.from_location_id, s.item_id, 0, 0,
             case when s.status in ('sent', 'received') then s.qty else 0 end,
             case when s.status = 'received' then coalesce(s.received_qty, 0) else 0 end,
             case when s.status = 'sent' then s.qty else 0 end,
             case when s.status = 'received' then s.qty - coalesce(s.received_qty, 0) else 0 end,
             case when s.status = 'cancelled' then s.qty else 0 end, 1
        from public.stock_transfers s
       where public._rb4_day(s.sent_at) between f and t and (p_loc is null or s.from_location_id = p_loc) and public._rb4_prod_view(s.from_location_id)
         and exists (select 1 from public.production_runs r2 where r2.location_id = s.from_location_id and r2.item_id = s.item_id and r2.status = 'done')) d
   group by d.day, d.location_id, d.item_id;
$$;

create or replace function public.rb4_dispatch_recon(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('day', x.day, 'location_id', x.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
      'base_unit', public._item_base(x.item_id), 'made', x.made, 'runs_n', x.runs_n, 'sent', x.sent, 'received', x.received, 'in_transit', x.in_transit, 'short', x.short, 'cancelled', x.cancelled, 'transfers_n', x.transfers_n,
      'tie_ok', x.sent = x.received + x.in_transit + x.short) order by x.day desc, i.code, x.location_id), '[]'::jsonb) into rows_
    from public._rb4_dr_rows(f, t, p_loc) x join public.items i on i.id = x.item_id join public.locations l on l.id = x.location_id;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', s.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(s.item_id),
      'made', s.made, 'sent', s.sent, 'received', s.received, 'in_transit', s.in_transit, 'short', s.short, 'cancelled', s.cancelled, 'made_not_sent', s.made - s.sent,
      'on_hand_now', (select b.qty from public.stock_balance b where b.item_id = s.item_id and b.location_id = s.location_id), 'tie_ok', s.sent = s.received + s.in_transit + s.short) order by i.code, s.location_id), '[]'::jsonb) into sm
    from (select x.location_id, x.item_id, sum(x.made) as made, sum(x.sent) as sent, sum(x.received) as received, sum(x.in_transit) as in_transit, sum(x.short) as short, sum(x.cancelled) as cancelled from public._rb4_dr_rows(f, t, p_loc) x group by 1, 2) s
    join public.items i on i.id = s.item_id join public.locations l on l.id = s.location_id;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm,
    'basis', 'Made = finished runs (quantity really booked). Sent / received / in transit / short = stock transfers sent on that day from the producing place, for items that place has produced. Short = sent - received on a received transfer. On hand now = the balance today, not at the end of the period.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_plan_vs_actual', 'rb4_order_status', 'rb4_dispatch_recon') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

do $q$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_pva_runs', '_rb4_dr_rows') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $q$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase407.sql
-- Phase 407 (bos407) - RPT-B4 / R4b: REAL CONSUMPTION VS RECIPE (#44), STANDARD VS ACTUAL COST AND THE PRICE / USAGE / YIELD VARIANCE (#33, #43, #55).
-- Paste after phase406. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
-- BASIS (said on the screen too)
--   Standard quantity   = what the production screen booked out for the run (the recipe need). It is read from the stock ledger (ref production + run id), so it is exactly what was booked.
--   Real quantity       = the record a person made with prod_actual_issue_set. Nothing is guessed: a run or ingredient without a record is "not captured" and is left out of every total.
--   Booked price        = the average cost the ledger used when the standard quantity went out (blank or 0 = unknown).
--   Standard price      = the owner's price list (item_costs). An ingredient without a list price has no price variance.
--   Standard output     = production_runs.yield_std (the recipe yield x batches). Real output = the quantity the person typed at production (yield_actual); blank = "not captured".
--   Material variance of one fully measured run (all inputs present):
--       price  = sum (booked price - standard price) x real qty
--       usage  = sum (real qty - standard qty) x standard price
--       yield  = (standard output - real output) x (sum standard qty x standard price / standard output)
--       total  = sum real qty x booked price - real output x (sum standard qty x standard price / standard output)       and  total = price + usage + yield   exactly
--   Positive = more cost than the standard (unfavourable). Each part is also given alone when only its own inputs exist. Conversion cost (labour, overhead) has no standard in the system: it is shown as booked, not split.
--   Money is shown only with the cost right (_cost_ok at the run's place); otherwise the answer says cost_hidden and gives quantities only.

do $g$ begin
  if to_regprocedure('public.rb4_dispatch_recon(date,date,int)') is null then raise exception 'phase407 needs phase406 first'; end if;
end $g$;

create or replace function public.rb4_consumption_vs_recipe(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; sm jsonb; runs_n int; runs_any int; notes jsonb := '[]'::jsonb; trunc boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select count(*), count(*) filter (where exists (select 1 from public.production_issue_actual a where a.run_id = r.id and a.status = 'active')) into runs_n, runs_any
    from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id);
  if runs_any = 0 then notes := notes || jsonb_build_object('code', 'actual_issue_not_captured', 'field', 'real use of ingredients'); end if;

  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  lines as (
    select r.id as run_id, r.made_at, r.location_id, r.item_id as fg_id, x.item_id, x.std_qty, a.actual_qty
      from runs r
      cross join lateral (select b.item_id, b.qty as std_qty from public._rb4_run_booked(r.id) b
                          union all
                          select a2.item_id, null::numeric from public.production_issue_actual a2 where a2.run_id = r.id and a2.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b2 where b2.item_id = a2.item_id)) x
      left join public.production_issue_actual a on a.run_id = r.id and a.item_id = x.item_id and a.status = 'active')
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', l.run_id, 'day', public._rb4_day(l.made_at), 'location_id', l.location_id, 'location', lo.name_bn, 'location_en', lo.name_en,
           'fg_code', fi.code, 'fg_name_bn', fi.name_bn, 'fg_name_en', fi.name_en, 'item_id', l.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(l.item_id),
           'std_qty', l.std_qty, 'actual_qty', l.actual_qty, 'diff', case when l.std_qty is not null and l.actual_qty is not null then round(l.actual_qty - l.std_qty, 4) end,
           'diff_pct', case when l.std_qty > 0 and l.actual_qty is not null then round((l.actual_qty - l.std_qty) / l.std_qty * 100, 2) end,
           'status', case when l.std_qty is null then 'not_in_recipe' when l.actual_qty is null then 'not_captured' else 'measured' end)
           order by l.made_at desc, ii.code), '[]'::jsonb)
    into trunc, rows_
    from lines l join public.items ii on ii.id = l.item_id join public.items fi on fi.id = l.fg_id join public.locations lo on lo.id = l.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(g.item_id),
        'runs_issued', g.runs_total, 'runs_measured', g.runs_measured, 'runs_not_captured', g.runs_total - g.runs_measured,
        'std_qty_measured', case when g.runs_measured > 0 then g.std_sum end, 'actual_qty_measured', case when g.runs_measured > 0 then g.act_sum end,
        'diff', case when g.runs_measured > 0 then round(g.act_sum - g.std_sum, 4) end,
        'diff_pct', case when g.runs_measured > 0 and g.std_sum > 0 then round((g.act_sum - g.std_sum) / g.std_sum * 100, 2) end) order by ii.code), '[]'::jsonb) into sm
    from (select e ->> 'item_id' as item_id_t, (e ->> 'item_id')::uuid as item_id,
                 count(*) filter (where e ->> 'status' in ('measured', 'not_captured')) as runs_total, count(*) filter (where e ->> 'status' = 'measured') as runs_measured,
                 sum((e ->> 'std_qty')::numeric) filter (where e ->> 'status' = 'measured') as std_sum, sum((e ->> 'actual_qty')::numeric) filter (where e ->> 'status' = 'measured') as act_sum
            from jsonb_array_elements(rows_) e group by 1, 2) g
    join public.items ii on ii.id = g.item_id;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'runs', runs_n, 'runs_with_real_use', runs_any, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'Standard = the recipe quantity booked out by the production screen (stock ledger). Real = what a person recorded. Runs or ingredients with no record are not captured and are left out of the totals.');
end $$;

create or replace function public.rb4_cost_variance(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; r record; ln record; rows_ jsonb := '[]'::jsonb; lines jsonb; money boolean; hidden boolean := false; trunc boolean := false; cnt int := 0;
        n_ing int; n_sp int; n_aq int; n_ap int; extra_n int; sq_sp numeric; aq_ap numeric; aq_sp numeric; sq_ap numeric; yb numeric; ao numeric; stdunit numeric;
        pv numeric; uv numeric; yvv numeric; tv numeric; yield_ok boolean; usage_ok boolean; price_ok boolean; total_ok boolean; miss text[]; sm jsonb; ap_ numeric; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  for r in select pr.* from public.production_runs pr where pr.status = 'done' and public._rb4_day(pr.made_at) between f and t and (p_loc is null or pr.location_id = p_loc) and (p_item is null or pr.item_id = p_item)
              and public._rb4_prod_view(pr.location_id) order by pr.made_at desc limit 501 loop
    cnt := cnt + 1;
    if cnt > 500 then trunc := true; exit; end if;
    money := public._cost_ok(r.location_id); if not money then hidden := true; end if;
    n_ing := 0; n_sp := 0; n_aq := 0; n_ap := 0; sq_sp := 0; aq_ap := 0; aq_sp := 0; sq_ap := 0; lines := '[]'::jsonb; miss := '{}';
    for ln in select b.item_id, b.qty as sq, b.unit_cost as ap, ic.cost_price as sp, a.actual_qty as aq, i.code, i.name_bn, i.name_en
                from public._rb4_run_booked(r.id) b join public.items i on i.id = b.item_id
                left join public.item_costs ic on ic.item_id = b.item_id
                left join public.production_issue_actual a on a.run_id = r.id and a.item_id = b.item_id and a.status = 'active' order by i.code loop
      ap_ := case when ln.ap is null or ln.ap <= 0 then null else ln.ap end;       -- cost 0 or blank = unknown
      n_ing := n_ing + 1;
      if ln.sp is not null then n_sp := n_sp + 1; sq_sp := sq_sp + ln.sq * ln.sp; end if;
      if ln.aq is not null then n_aq := n_aq + 1; end if;
      if ap_ is not null then n_ap := n_ap + 1; end if;
      if ln.aq is not null and ln.sp is not null then aq_sp := aq_sp + ln.aq * ln.sp; end if;
      if ln.aq is not null and ap_ is not null then aq_ap := aq_ap + ln.aq * ap_; end if;
      lines := lines || jsonb_build_object('item_id', ln.item_id, 'code', ln.code, 'name_bn', ln.name_bn, 'name_en', ln.name_en, 'std_qty', ln.sq, 'actual_qty', ln.aq,
          'booked_price', case when money then ap_ end, 'std_price', case when money then ln.sp end,
          'price_var', case when money and ln.aq is not null and ln.sp is not null and ap_ is not null then round((ap_ - ln.sp) * ln.aq, 2) end,
          'usage_var', case when money and ln.aq is not null and ln.sp is not null then round((ln.aq - ln.sq) * ln.sp, 2) end);
    end loop;
    select count(*) into extra_n from public.production_issue_actual a where a.run_id = r.id and a.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b where b.item_id = a.item_id);
    yb := r.yield_std; ao := r.yield_actual;
    stdunit := case when yb > 0 and n_ing > 0 and n_sp = n_ing then sq_sp / yb end;
    yield_ok := ao is not null and stdunit is not null;
    usage_ok := n_ing > 0 and n_aq = n_ing and n_sp = n_ing and extra_n = 0;
    price_ok := usage_ok and n_ap = n_ing;
    total_ok := yield_ok and price_ok;
    pv := case when price_ok then round(aq_ap - aq_sp, 2) end;
    uv := case when usage_ok then round(aq_sp - sq_sp, 2) end;
    yvv := case when yield_ok then round((yb - ao) * stdunit, 2) end;
    tv := case when total_ok then round(aq_ap - ao * stdunit, 2) end;
    if n_ing = 0 then miss := array_append(miss, 'booked ingredients'::text); end if;
    if n_aq < n_ing or extra_n > 0 then miss := array_append(miss, 'real use of ingredients'::text); end if;
    if n_sp < n_ing then miss := array_append(miss, 'standard price (price list)'::text); end if;
    if n_ap < n_ing then miss := array_append(miss, 'booked cost'::text); end if;
    if ao is null then miss := array_append(miss, 'actual yield'::text); end if;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'item_id', r.item_id,
        'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'yield_var_qty', case when ao is not null and yb is not null then round(yb - ao, 4) end,
        'booked_unit_cost', case when money then r.unit_cost end, 'std_unit_cost_booked', case when money then r.std_cost end, 'material_cost', case when money then r.material_cost end,
        'conversion_cost', case when money then r.conversion_cost end, 'conversion_complete', r.conversion_complete, 'conversion_mode', r.conversion_mode,
        'std_unit_cost_list', case when money then round(stdunit, 6) end,
        'std_cost_for_real_output', case when money and total_ok then round(ao * stdunit, 2) end, 'real_material_cost', case when money and price_ok then round(aq_ap, 2) end,
        'price_var', case when money then pv end, 'usage_var', case when money then uv end, 'yield_var', case when money then yvv end, 'total_var', case when money then tv end,
        'price_var_ok', price_ok, 'usage_var_ok', usage_ok, 'yield_var_ok', yield_ok, 'measured', total_ok,
        'status', case when total_ok then 'measured' when yield_ok or usage_ok then 'partly' else 'not_measured' end, 'missing', to_jsonb(miss), 'lines', lines);
  end loop;
  -- names for the rows (kept out of the loop to keep it short)
  select coalesce(jsonb_agg(e || jsonb_build_object('location', l.name_bn, 'location_en', l.name_en, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base((e ->> 'item_id')::uuid))
         order by e ->> 'day' desc), '[]'::jsonb) into rows_
    from jsonb_array_elements(rows_) e join public.items i on i.id = (e ->> 'item_id')::uuid join public.locations l on l.id = (e ->> 'location_id')::int;
  -- summary per finished item: only runs where the part could be measured are added; the counts say how many
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_measured', g.rm, 'runs_partly', g.rp, 'runs_not_measured', g.runs - g.rm - g.rp,
        'price_var', case when g.n_price > 0 then g.s_price end, 'price_var_runs', g.n_price, 'usage_var', case when g.n_usage > 0 then g.s_usage end, 'usage_var_runs', g.n_usage,
        'yield_var', case when g.n_yield > 0 then g.s_yield end, 'yield_var_runs', g.n_yield,
        'total_var', case when g.rm > 0 then g.s_total end, 'std_cost_for_real_output', case when g.rm > 0 then g.s_std end, 'real_material_cost', case when g.rm > 0 then g.s_real end,
        'total_var_pct', case when g.rm > 0 and g.s_std > 0 then round(g.s_total / g.s_std * 100, 2) end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as rm, count(*) filter (where e ->> 'status' = 'partly') as rp,
                 count(*) filter (where (e ->> 'price_var_ok')::boolean) as n_price, sum((e ->> 'price_var')::numeric) filter (where (e ->> 'price_var_ok')::boolean) as s_price,
                 count(*) filter (where (e ->> 'usage_var_ok')::boolean) as n_usage, sum((e ->> 'usage_var')::numeric) filter (where (e ->> 'usage_var_ok')::boolean) as s_usage,
                 count(*) filter (where (e ->> 'yield_var_ok')::boolean) as n_yield, sum((e ->> 'yield_var')::numeric) filter (where (e ->> 'yield_var_ok')::boolean) as s_yield,
                 sum((e ->> 'total_var')::numeric) filter (where (e ->> 'measured')::boolean) as s_total, sum((e ->> 'std_cost_for_real_output')::numeric) filter (where (e ->> 'measured')::boolean) as s_std,
                 sum((e ->> 'real_material_cost')::numeric) filter (where (e ->> 'measured')::boolean) as s_real
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then
    notes := notes || jsonb_build_object('code', 'no_run_fully_measured', 'field', 'real use of ingredients, standard price, actual yield');
  end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'cost_hidden', hidden, 'truncated', trunc, 'notes', notes,
    'basis', 'Standard price = the owner price list (item_costs). Booked price = the average cost the ledger used for the run. Positive variance = more cost than the standard. Conversion cost has no standard and is not split. A part is shown only when all of its inputs were captured.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_consumption_vs_recipe', 'rb4_cost_variance') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase408.sql
-- Phase 408 (bos408) - RPT-B4 / R4c: RUN-LEVEL YIELD VS STANDARD (#45), REJECT / REWORK / PRODUCTION LOSS (#49), WASTAGE WITH THE BATCH AND PRODUCTION-RUN DIMENSION (#50).
-- Paste after phase407. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
--   rb4_run_yield(from, to, place, item)         one row per finished run: standard output, the output the person typed (blank = "not captured"), the difference and %, and the owner's warning limit
--                                                (rule yield_variance_warn_pct; blank limit = no flag, said in words). Another package may also list the same runs; the numbers come from production_runs only.
--   rb4_losses(from, to, place, item)            reject / rework per run (prod_loss_add): the run's state is recorded / checked-none / not captured. Percentages use only runs whose state is known.
--   rb4_wastage_dim(from, to, place, item)       the wastage records with the batch they were taken from and, when that batch was made by a production run, the run; by reason, item and batch.
--                                                Value = quantity x the ledger cost of the write-off, shown only with the cost right and only where the cost is known.

do $g$ begin
  if to_regprocedure('public.rb4_cost_variance(date,date,int,uuid)') is null then raise exception 'phase408 needs phase407 first'; end if;
end $g$;

create or replace function public.rb4_run_yield(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; thr numeric := public.rule_num('yield_variance_warn_pct'); rows_ jsonb; sm jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches,
           'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'booked_output', r.yield_base,
           'var_qty', case when r.yield_actual is not null and r.yield_std is not null then round(r.yield_actual - r.yield_std, 4) end,
           'var_pct', case when r.yield_actual is not null and r.yield_std > 0 then round((r.yield_actual - r.yield_std) / r.yield_std * 100, 2) end,
           'status', case when r.yield_std is null then 'standard_not_captured' when r.yield_actual is null then 'not_captured' else 'measured' end,
           'over_limit', case when thr is not null and r.yield_actual is not null and r.yield_std > 0 then abs((r.yield_actual - r.yield_std) / r.yield_std * 100) > thr end) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'measured', g.m, 'not_captured', g.runs - g.m, 'std_qty_measured', case when g.m > 0 then g.s_std end, 'actual_qty_measured', case when g.m > 0 then g.s_act end,
        'var_pct', case when g.m > 0 and g.s_std > 0 then round((g.s_act - g.s_std) / g.s_std * 100, 2) end, 'over_limit_runs', case when thr is not null then g.over end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m,
                 sum((e ->> 'yield_std')::numeric) filter (where e ->> 'status' = 'measured') as s_std, sum((e ->> 'yield_actual')::numeric) filter (where e ->> 'status' = 'measured') as s_act,
                 count(*) filter (where (e ->> 'over_limit')::boolean) as over
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if thr is null then notes := notes || jsonb_build_object('code', 'limit_not_set', 'field', 'yield_variance_warn_pct'); end if;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then notes := notes || jsonb_build_object('code', 'actual_yield_not_captured', 'field', 'actual yield'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'limit_pct', thr, 'truncated', coalesce(trunc, false), 'notes', notes);
end $$;

create or replace function public.rb4_losses(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; reasons jsonb; sm jsonb; items_ jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  agg as (
    select r.id, coalesce(sum(x.qty) filter (where x.kind = 'reject'), 0) as rej, coalesce(sum(x.qty) filter (where x.kind = 'rework'), 0) as rew,
           count(*) filter (where x.kind in ('reject', 'rework')) as recorded_n, count(*) filter (where x.kind = 'none') as none_n,
           coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'qty', x.qty, 'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn, 'note', x.note) order by x.created_at) filter (where x.kind in ('reject', 'rework')), '[]'::jsonb) as lines
      from runs r left join public.production_loss x on x.run_id = r.id and x.status = 'active'
      left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code group by r.id)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'output', r.yield_base,
           'state', case when a.recorded_n > 0 then 'recorded' when a.none_n > 0 then 'none' else 'not_captured' end,
           'reject_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rej end, 'rework_qty', case when a.recorded_n > 0 or a.none_n > 0 then a.rew end,
           'reject_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rej / r.yield_base * 100, 2) end,
           'rework_pct', case when (a.recorded_n > 0 or a.none_n > 0) and r.yield_base > 0 then round(a.rew / r.yield_base * 100, 2) end, 'lines', a.lines) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join agg a on a.id = r.id join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', z.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'reject_n', z.rn, 'rework_n', z.wn) order by z.rn + z.wn desc, z.rc), '[]'::jsonb) into reasons
    from (select l ->> 'reason_code' as rc, count(*) filter (where l ->> 'kind' = 'reject') as rn, count(*) filter (where l ->> 'kind' = 'rework') as wn
            from jsonb_array_elements(rows_) e, jsonb_array_elements(e -> 'lines') l group by 1) z left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = z.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_known', g.known, 'runs_not_captured', g.runs - g.known, 'output_known', case when g.known > 0 then g.out_k end, 'reject_qty', case when g.known > 0 then g.rej end, 'rework_qty', case when g.known > 0 then g.rew end,
        'reject_pct', case when g.known > 0 and g.out_k > 0 then round(g.rej / g.out_k * 100, 2) end, 'rework_pct', case when g.known > 0 and g.out_k > 0 then round(g.rew / g.out_k * 100, 2) end) order by i.code), '[]'::jsonb) into items_
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'state' <> 'not_captured') as known,
                 sum((e ->> 'output')::numeric) filter (where e ->> 'state' <> 'not_captured') as out_k, sum((e ->> 'reject_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rej,
                 sum((e ->> 'rework_qty')::numeric) filter (where e ->> 'state' <> 'not_captured') as rew
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('runs', jsonb_array_length(rows_), 'recorded', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'recorded'),
      'none', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'none'), 'not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'not_captured')) into sm;
  if (sm ->> 'runs')::int > 0 and (sm ->> 'recorded')::int + (sm ->> 'none')::int = 0 then notes := notes || jsonb_build_object('code', 'loss_not_captured', 'field', 'reject and rework'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', reasons, 'by_item', items_, 'summary', sm, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'A reject or rework is a record, not a stock movement: the output of the run is as booked. Percentages use only runs whose state is known (recorded, or checked and none). Stock written off is in the wastage report.');
end $$;

create or replace function public.rb4_wastage_dim(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; by_reason jsonb; by_item jsonb; by_batch jsonb; trunc boolean; hidden boolean := false; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select exists (select 1 from public.stock_wastage w where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and public._rb4_prod_view(w.location_id) and not public._cost_ok(w.location_id)) into hidden;
  with w as (
    select w.*, b.made_at as batch_made, b.qty_made as batch_qty, r.id as run_id, public._cost_ok(w.location_id) as money,
           case when lg.unit_cost is not null and lg.unit_cost > 0 then lg.unit_cost end as ucost
      from public.stock_wastage w
      left join public.stock_batches b on b.id = w.batch_id
      left join public.production_runs r on r.batch_id = w.batch_id and r.status = 'done'
      left join public.stock_ledger lg on lg.id = w.ledger_id
     where public._rb4_day(w.made_at) between f and t and (p_loc is null or w.location_id = p_loc) and (p_item is null or w.item_id = p_item) and public._rb4_prod_view(w.location_id)
     order by w.made_at desc limit 2001)
  select (select count(*) > 2000 from w),
         coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'day', public._rb4_day(x.made_at), 'location_id', x.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(x.item_id), 'qty', x.qty,
           'reason_code', x.reason_code, 'reason', o.label_en, 'reason_bn', o.label_bn,
           'batch_id', x.batch_id, 'batch_made_at', x.batch_made, 'run_id', x.run_id, 'batch_state', case when x.batch_id is null then 'batch_not_captured' when x.run_id is null then 'not_from_a_run' else 'from_run' end,
           'value', case when x.money and x.ucost is not null then round(x.qty * x.ucost, 2) end, 'value_state', case when not x.money then 'cost_hidden' when x.ucost is null then 'cost_not_captured' else 'known' end,
           'note', x.note, 'created_staff', x.created_staff) order by x.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from w limit 2000) x join public.items i on i.id = x.item_id join public.locations l on l.id = x.location_id left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = x.reason_code;

  select coalesce(jsonb_agg(jsonb_build_object('reason_code', g.rc, 'reason', o.label_en, 'reason_bn', o.label_bn, 'records', g.n, 'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by g.n desc, g.rc), '[]'::jsonb) into by_reason
    from (select e ->> 'reason_code' as rc, count(*) as n, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = g.rc;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id), 'records', g.n, 'qty', g.q,
        'value', case when g.vk > 0 then g.v end, 'value_known_n', g.vk, 'value_not_known_n', g.n - g.vk) order by i.code), '[]'::jsonb) into by_item
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q, count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v from jsonb_array_elements(rows_) e group by 1) g
    join public.items i on i.id = g.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', g.bid, 'run_id', g.rid, 'batch_made_at', g.bm, 'item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'records', g.n, 'qty', g.q, 'value', case when g.vk > 0 then g.v end, 'value_not_known_n', g.n - g.vk) order by g.bm desc nulls last), '[]'::jsonb) into by_batch
    from (select (e ->> 'batch_id')::bigint as bid, (e ->> 'run_id')::uuid as rid, (e ->> 'batch_made_at')::timestamptz as bm, (e ->> 'item_id')::uuid as item_id, count(*) as n, sum((e ->> 'qty')::numeric) as q,
                 count(*) filter (where e ->> 'value_state' = 'known') as vk, sum((e ->> 'value')::numeric) as v
            from jsonb_array_elements(rows_) e where e ->> 'batch_id' is not null group by 1, 2, 3, 4) g join public.items i on i.id = g.item_id;
  select jsonb_build_object('records', jsonb_array_length(rows_), 'batch_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'batch_not_captured'),
      'from_run', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'batch_state' = 'from_run'),
      'value_known_n', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known'),
      'value', (select sum((e ->> 'value')::numeric) from jsonb_array_elements(rows_) e where e ->> 'value_state' = 'known')) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_reason', by_reason, 'by_item', by_item, 'by_batch', by_batch, 'summary', sm, 'cost_hidden', hidden, 'truncated', coalesce(trunc, false),
    'basis', 'Quantity is never added across different items. A value is shown only where the ledger cost of the write-off is known and the reader has the cost right; the others are counted as not known, never as 0.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_run_yield', 'rb4_losses', 'rb4_wastage_dim') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';

-- ============================================================================
-- End of FRESH part 15 of 21.
