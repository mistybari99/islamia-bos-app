-- ============================================================================
-- FRESH part 4 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase42.sql
-- ============================================================
-- PHASE 42 (module B2): ATTENDANCE, LEAVE, AUTOMATIC PAYROLL and FINGERPRINT DEVICE integration.
-- Additive and idempotent (paste twice = no error). Needs phase8..phase28 and phase41 (employees, employee_pay, employee_pay_components,
-- leave_types, employee_leave_entitlements, _emp_ok / _emp_any / _loc_ok / _emp_pay_on / _pay_calc / _dhaka_today). No other new phase.
-- Nothing is deleted: punches are append-only (only a void flag / a late employee mapping may be written), payroll documents are voided, never removed.
--
-- WORKING STAFF = employees.status in ('active', 'on_leave'). A person who left this month (resigned / terminated / retired, status_date = last day
--   worked) is still paid up to status_date (final settlement). draft / discarded are not people yet.
--
-- TABLES
--   shifts(id, name_bn, name_en, location_id null = every place, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight,
--     min_hours_full_day, min_hours_half_day, is_default, active)       -- one default per place (or a company default with location_id null)
--   employee_shift_assignments(id, employee_id, shift_id, weekday_mask (bit 0 = Sunday .. bit 6 = Saturday, 127 = every day), off_mask null = use rule
--     att_weekly_off, from_date, to_date null, active)
--   holidays(id, day, location_id null = everywhere, name_bn, name_en, paid, active)
--   attendance_devices(id, name, location_id, vendor zkteco|hikvision|suprema|other, serial, token_hash (NOT readable), active, last_seen, rl_minute, rl_count)
--   attendance_import_batches(id uuid, location_id, device_id, file_name, rows_total, rows_new, rows_dup, rows_bad, rows_unmapped, date_from, date_to,
--     status active|void, created_by/at, void_by/at/reason)
--   attendance_punches(id, employee_id null = unmapped, device_id null, location_id, device_user_id, punched_at, direction in|out|unknown,
--     source device|file|manual|app, raw, import_batch, void)   unique (device_id, device_user_id, punched_at) nulls not distinct among non-void rows
--   attendance_days(employee_id, day) pk: status present|absent|late|half_day|leave|off|holiday|unpaid, day_kind normal|off|holiday, first_in, last_out,
--     worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch, shift_id, location_id, leave_type, paid_day,
--     source auto|manual, marked_by/at, approved_by/at, override_reason, note, computed_at
--   leave_requests(id, client_id, employee_id, leave_type, from_date, to_date, days, reason, status pending|approved|rejected|cancelled, requested_by/at,
--     decided_by/at, decision_note)
--   employee_advances(id, client_id, employee_id, location_id, adv_date, amount, instalment, recover_from, mode none|cash|bank|mobile, note, status active|void)
--   employee_advance_recoveries(id, advance_id, run_id, line_id, amount, status active|void)       -- written when a payroll run is approved
--   payroll_bonus_events(id, month, name, location_id null, active)   -- "the Eid bonus is paid with the salary of this month" (matches employee_pay.bonus_rules[].name)
--   payroll_runs(id, client_id, month (first day), location_id null = whole company (owner only), status draft|approved|paid|void, created_by/at,
--     approved_by/at, paid_at, void_by/at/reason, notes)
--   payroll_lines(id, run_id, month, employee_id, location_id, ... every figure of the calculation ..., gross, deductions, net, calc_detail, payment_status
--     unpaid|partly|paid, paid_amount, active)
--   payroll_payments(id, client_batch, run_id, line_id, employee_id, location_id, pay_date, mode cash|bank|mobile, amount, ref, note, status done|void)
--
-- PRIVACY: attendance (no money) = owner, the person himself (profile link), or attendance_manage / employee_view / employee_manage at the person's place.
--   Payroll, advances and pay figures = owner, salary_view or payroll_manage at the place. Payroll approve = owner only. Devices = owner registers.
-- FINGERPRINT: attendance_punch_push(token, rows) is the ONLY function anon may execute; it inserts punches for the token's device and nothing else.
-- RULES (module people, Switchboard): attendance_on, app_punch_on (OFF), att_weekly_off ("fri"), att_double_punch_min (5), att_ot_min_minutes (30),
--   att_ot_cap_hours (2), att_late_mode (count), att_lates_per_day (3), pay_weekly_off_paid, pay_holiday_paid, ot_mult_holiday (2), att_bonus_amount (0 = off),
--   pay_round_net (nearest), payroll_on, att_push_per_min (30).
-- GRANTS: attendance_manage (new; default for management / showroom_manager / factory_incharge / hr), payroll_manage (new), salary_view (existing).
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('attendance_on', 'people', 'switch', 'true', null, null, null, null, 'হাজিরা ও ছুটি চালু', 'Attendance ও leave চালু', 'Attendance and leave are on', 'বন্ধ করলে হাজিরা / ছুটি লেখা বন্ধ; দেখা চলবে।', 'Off = no attendance / leave writes; viewing still works.', 170),
 ('app_punch_on', 'people', 'switch', 'false', null, null, null, null, 'অ্যাপ থেকে হাজিরা (চেক ইন / আউট)', 'App থেকে check in / out', 'Staff may check in / out from the app', 'লগইন আছে এমন কর্মী নিজের ফোনে চেক ইন করতে পারবে।', 'Staff with a login can check in from their phone.', 171),
 ('att_weekly_off', 'people', 'text', '"fri"', null, null, null, null, 'সাপ্তাহিক ছুটির দিন (fri / fri,sat)', 'Weekly off দিন (fri / fri,sat)', 'Weekly off days (fri / fri,sat)', 'ইংরেজি তিন অক্ষর, কমা দিয়ে: sun mon tue wed thu fri sat', 'Three letters, comma separated: sun mon tue wed thu fri sat', 172),
 ('att_double_punch_min', 'people', 'number', '5', 'min', null, 1, 120, 'এত মিনিটের মধ্যে দুবার আঙুল দিলে একবার ধরা হবে', 'এত মিনিটের মধ্যে double punch = একবার', 'Punches closer than this are one punch', null, null, 173),
 ('att_ot_min_minutes', 'people', 'number', '30', 'min', null, 0, 240, 'এর কম ওভারটাইম গোনা হবে না (মিনিট)', 'এর কম overtime গোনা হবে না (min)', 'Overtime below this is ignored (minutes)', null, null, 174),
 ('att_ot_cap_hours', 'people', 'number', '2', 'hours', null, 0, 24, 'দিনে এর বেশি ওভারটাইম হলে অনুমোদন লাগবে (ঘণ্টা)', 'দিনে এর বেশি OT হলে approval লাগবে (ঘণ্টা)', 'Overtime above this per day needs approval (hours)', 'অনুমোদন না হলে বাড়তি অংশ বেতনে যোগ হবে না।', 'Without approval the extra part is not paid.', 175),
 ('att_late_mode', 'people', 'choice', '"count"', null, '["count","per_minute","none"]', null, null, 'দেরির কর্তন: count = কয়েক দিন দেরি = ১ দিনের বেতন, per_minute = মিনিট হিসাবে, none = নেই', 'Late কর্তন: count / per_minute / none', 'Late cut: count = N lates = 1 day, per_minute = by the minute, none', null, null, 176),
 ('att_lates_per_day', 'people', 'number', '3', 'lates', null, 1, 31, 'কতবার দেরি = ১ দিনের বেতন কাটা', 'কতবার late = ১ দিনের বেতন কাটা', 'This many late arrivals = one day cut', null, null, 177),
 ('pay_weekly_off_paid', 'people', 'switch', 'true', null, null, null, null, 'সাপ্তাহিক ছুটির দিনের বেতন আছে', 'Weekly off-এর বেতন আছে', 'Weekly off days are paid', null, null, 178),
 ('pay_holiday_paid', 'people', 'switch', 'true', null, null, null, null, 'সরকারি / উৎসব ছুটির বেতন আছে (ছুটির নিজস্ব সেটিং মেনে)', 'Holiday-র বেতন আছে', 'Holidays are paid (as each holiday says)', null, null, 179),
 ('ot_mult_holiday', 'people', 'number', '2', 'x', null, 1, 5, 'ছুটির দিনে ওভারটাইমের গুণ', 'Holiday / off-day OT গুণ', 'Overtime multiple on a holiday / weekly off', 'সাধারণ দিনের গুণ কর্মচারীর বেতন কাঠামোতে (যেমন ১.৫)।', 'The normal-day multiple is in the person''s pay structure (e.g. 1.5).', 180),
 ('att_bonus_amount', 'people', 'number', '0', 'BDT', null, 0, 1000000, 'হাজিরা বোনাস (মাসে কোনো অনুপস্থিতি / দেরি না হলে); ০ = বন্ধ', 'Attendance bonus; 0 = বন্ধ', 'Attendance bonus (no absence / late in the month); 0 = off', null, null, 181),
 ('pay_round_net', 'people', 'choice', '"nearest"', null, '["nearest","none"]', null, null, 'হাতে পাওয়া বেতন পূর্ণ টাকায় (nearest)', 'Net বেতন পূর্ণ টাকায়', 'Round the net pay to the nearest taka', null, null, 182),
 ('payroll_on', 'people', 'switch', 'true', null, null, null, null, 'বেতন শিট (payroll) চালু', 'Payroll চালু', 'Payroll is on', null, null, 183),
 ('att_push_per_min', 'people', 'number', '30', 'calls', null, 1, 600, 'একটি মেশিন মিনিটে কতবার পাঠাতে পারবে', 'Device মিনিটে কতবার push করতে পারবে', 'Device pushes allowed per minute', null, null, 184)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('attendance_manage', 74, 'হাজিরা হাতে লেখা / সংশোধন, ছুটি অনুমোদন, মেশিনের ফাইল আনা', 'Attendance লেখা / সংশোধন, leave approve, device file import', 'Mark / correct attendance, approve leave, import device files'),
 ('payroll_manage', 75, 'বেতন শিট তৈরি, সমন্বয় ও বেতন দেওয়া', 'Payroll তৈরি, adjust ও pay', 'Prepare payroll, adjust lines and pay salaries')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rule_grants (grant_code, role_code)
select 'attendance_manage', r.code from public.roles r where r.code in ('management', 'showroom_manager', 'factory_incharge', 'hr')
on conflict do nothing;

-- ---------- shifts, roster, holidays ----------
create table if not exists public.shifts (
  id serial primary key, name_bn text not null check (char_length(btrim(name_bn)) between 1 and 60), name_en text,
  location_id int references public.locations(id), start_time time not null, end_time time not null,
  grace_late_min int not null default 10 check (grace_late_min between 0 and 240), grace_early_min int not null default 10 check (grace_early_min between 0 and 240),
  break_min int not null default 60 check (break_min between 0 and 600), crosses_midnight boolean not null default false,
  min_hours_full_day numeric not null default 7 check (min_hours_full_day between 0 and 24), min_hours_half_day numeric not null default 4 check (min_hours_half_day between 0 and 24),
  is_default boolean not null default false, active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists shifts_one_default on public.shifts (coalesce(location_id, 0)) where is_default and active;
insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight, min_hours_full_day, min_hours_half_day, is_default)
select 'সাধারণ শিফট', 'General shift', null, '09:00', '18:00', 10, 10, 60, false, 7, 4, true
where not exists (select 1 from public.shifts);

create table if not exists public.employee_shift_assignments (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), shift_id int not null references public.shifts(id),
  weekday_mask int not null default 127 check (weekday_mask between 1 and 127), off_mask int check (off_mask is null or off_mask between 0 and 127),
  from_date date not null, to_date date, active boolean not null default true, created_by uuid, created_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date)
);
create index if not exists esa_emp on public.employee_shift_assignments (employee_id, from_date desc);

create table if not exists public.holidays (
  id serial primary key, day date not null, location_id int references public.locations(id), name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text, paid boolean not null default true, active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists holidays_one on public.holidays (day, coalesce(location_id, 0)) where active;

-- ---------- devices, punches, days ----------
create table if not exists public.attendance_devices (
  id serial primary key, name text not null check (char_length(btrim(name)) between 1 and 60), location_id int not null references public.locations(id),
  vendor text not null default 'zkteco' check (vendor in ('zkteco', 'hikvision', 'suprema', 'other')), serial text,
  token_hash text not null unique, active boolean not null default true, last_seen timestamptz, rl_minute timestamptz, rl_count int not null default 0,
  pushed_rows bigint not null default 0, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.attendance_import_batches (
  id uuid primary key default gen_random_uuid(), client_id uuid unique, location_id int not null references public.locations(id), device_id int references public.attendance_devices(id),
  file_name text, rows_total int not null default 0, rows_new int not null default 0, rows_dup int not null default 0, rows_bad int not null default 0, rows_unmapped int not null default 0,
  date_from timestamptz, date_to timestamptz, status text not null default 'active' check (status in ('active', 'void')),
  created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create table if not exists public.attendance_punches (
  id bigserial primary key, employee_id uuid references public.employees(id), device_id int references public.attendance_devices(id), location_id int references public.locations(id),
  device_user_id text not null check (char_length(device_user_id) between 1 and 60), punched_at timestamptz not null,
  direction text not null default 'unknown' check (direction in ('in', 'out', 'unknown')), source text not null check (source in ('device', 'file', 'manual', 'app')),
  raw jsonb, import_batch uuid references public.attendance_import_batches(id), void boolean not null default false, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists attendance_punches_uq on public.attendance_punches (device_id, device_user_id, punched_at) nulls not distinct where not void;
create index if not exists attendance_punches_emp on public.attendance_punches (employee_id, punched_at) where not void;
create index if not exists attendance_punches_unmapped on public.attendance_punches (location_id, device_user_id) where employee_id is null and not void;
create index if not exists attendance_punches_batch on public.attendance_punches (import_batch) where import_batch is not null;

create table if not exists public.attendance_days (
  employee_id uuid not null references public.employees(id), day date not null,
  status text not null check (status in ('present', 'absent', 'late', 'half_day', 'leave', 'off', 'holiday', 'unpaid')),
  day_kind text not null default 'normal' check (day_kind in ('normal', 'off', 'holiday')),
  first_in timestamptz, last_out timestamptz, worked_minutes int not null default 0, late_minutes int not null default 0, early_leave_minutes int not null default 0,
  ot_minutes int not null default 0 check (ot_minutes between 0 and 1440), ot_approved boolean not null default false, punch_count int not null default 0, single_punch boolean not null default false,
  shift_id int references public.shifts(id), location_id int references public.locations(id), leave_type text references public.leave_types(code), paid_day boolean,
  source text not null default 'auto' check (source in ('auto', 'manual')), marked_by uuid, marked_at timestamptz, approved_by uuid, approved_at timestamptz,
  override_reason text, note text, computed_at timestamptz not null default now(),
  primary key (employee_id, day)
);
create index if not exists attendance_days_day on public.attendance_days (day, location_id);

-- ---------- leave ----------
create table if not exists public.leave_requests (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), leave_type text not null references public.leave_types(code),
  from_date date not null, to_date date not null, days numeric not null check (days >= 0 and days <= 366), reason text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid, requested_at timestamptz not null default now(), decided_by uuid, decided_at timestamptz, decision_note text,
  check (to_date >= from_date)
);
create index if not exists leave_requests_emp on public.leave_requests (employee_id, from_date);

-- ---------- advances, bonus events, payroll ----------
create table if not exists public.employee_advances (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), location_id int references public.locations(id),
  adv_date date not null, amount numeric not null check (amount > 0 and amount <= 1000000000000), instalment numeric check (instalment is null or (instalment > 0 and instalment <= 1000000000000)),
  recover_from date not null, mode text not null default 'none' check (mode in ('none', 'cash', 'bank', 'mobile')), note text,
  status text not null default 'active' check (status in ('active', 'void')), created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists employee_advances_emp on public.employee_advances (employee_id);

create table if not exists public.payroll_bonus_events (
  id serial primary key, month date not null check (extract(day from month) = 1), name text not null check (char_length(btrim(name)) between 1 and 60),
  location_id int references public.locations(id), active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists payroll_bonus_events_one on public.payroll_bonus_events (month, lower(name), coalesce(location_id, 0)) where active;

create table if not exists public.payroll_runs (
  id bigserial primary key, client_id uuid unique, month date not null check (extract(day from month) = 1), location_id int references public.locations(id),
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid', 'void')), notes text,
  created_by uuid, created_at timestamptz not null default now(), approved_by uuid, approved_at timestamptz, paid_at timestamptz, void_by uuid, void_at timestamptz, void_reason text
);
create unique index if not exists payroll_runs_one on public.payroll_runs (month, coalesce(location_id, 0)) where status <> 'void';

create table if not exists public.payroll_lines (
  id bigserial primary key, run_id bigint not null references public.payroll_runs(id), month date not null, employee_id uuid not null references public.employees(id),
  location_id int references public.locations(id), employee_no text, name text, pay_id bigint, pay_basis text,
  basic numeric not null default 0, basic_amount numeric not null default 0, allowances jsonb not null default '[]', allowance_total numeric not null default 0,
  structure_deductions jsonb not null default '[]', structure_deduction_total numeric not null default 0,
  days_in_month int not null default 0, employed_days int not null default 0, paid_days numeric not null default 0, absent_days numeric not null default 0, half_days int not null default 0,
  unpaid_leave_days numeric not null default 0, paid_leave_days numeric not null default 0, off_days int not null default 0, holiday_days int not null default 0,
  late_count int not null default 0, late_minutes int not null default 0, late_deduction numeric not null default 0, absent_deduction numeric not null default 0,
  unpaid_deduction numeric not null default 0, not_employed_deduction numeric not null default 0, ot_minutes int not null default 0, ot_amount numeric not null default 0,
  bonus jsonb not null default '[]', advance_recovery numeric not null default 0, advances jsonb not null default '[]', other_deductions jsonb not null default '[]',
  adjustments jsonb not null default '[]', gross numeric not null default 0, deductions numeric not null default 0, round_adj numeric not null default 0, net numeric not null default 0,
  warnings jsonb not null default '[]', calc_detail jsonb not null default '{}', payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'partly', 'paid')),
  paid_amount numeric not null default 0, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists payroll_lines_one on public.payroll_lines (employee_id, month) where active;
create index if not exists payroll_lines_run on public.payroll_lines (run_id);

create table if not exists public.employee_advance_recoveries (
  id bigserial primary key, advance_id bigint not null references public.employee_advances(id), run_id bigint not null references public.payroll_runs(id),
  line_id bigint not null references public.payroll_lines(id), amount numeric not null check (amount > 0), status text not null default 'active' check (status in ('active', 'void')),
  created_at timestamptz not null default now()
);
create index if not exists employee_advance_recoveries_adv on public.employee_advance_recoveries (advance_id) where status = 'active';

create table if not exists public.payroll_payments (
  id bigserial primary key, client_batch uuid, run_id bigint not null references public.payroll_runs(id), line_id bigint not null references public.payroll_lines(id),
  employee_id uuid not null references public.employees(id), location_id int references public.locations(id), pay_date date not null,
  mode text not null check (mode in ('cash', 'bank', 'mobile')), amount numeric not null check (amount > 0 and amount <= 1000000000000), ref text, note text,
  status text not null default 'done' check (status in ('done', 'void')), created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists payroll_payments_line on public.payroll_payments (line_id) where status = 'done';
create index if not exists payroll_payments_day on public.payroll_payments (location_id, pay_date) where status = 'done';

-- ---------- guards: append-only records, immutable money documents ----------
create or replace function public._punch_guard42() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - array['employee_id', 'void']) is distinct from (to_jsonb(old) - array['employee_id', 'void'])
     or (old.employee_id is not null and new.employee_id is distinct from old.employee_id) or (old.void and not new.void) then
    raise exception 'append_only: a punch cannot be changed (only mapped once or voided)';
  end if;
  return new;
end $$;
drop trigger if exists attendance_punches_guard on public.attendance_punches;
create trigger attendance_punches_guard before update or delete on public.attendance_punches for each row execute function public._punch_guard42();

create or replace function public._status_guard42() returns trigger language plpgsql set search_path = public as $$
declare keep text[] := tg_argv;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - keep) is distinct from (to_jsonb(old) - keep) then raise exception 'append_only: % cannot be changed', tg_table_name; end if;
  if (to_jsonb(old) ->> 'status') in ('void', 'cancelled', 'rejected') and (to_jsonb(new) ->> 'status') is distinct from (to_jsonb(old) ->> 'status') then raise exception 'append_only: % is closed', tg_table_name; end if;
  return new;
end $$;
drop trigger if exists payroll_payments_guard on public.payroll_payments;
create trigger payroll_payments_guard before update or delete on public.payroll_payments for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason');
drop trigger if exists employee_advance_recoveries_guard on public.employee_advance_recoveries;
create trigger employee_advance_recoveries_guard before update or delete on public.employee_advance_recoveries for each row execute function public._status_guard42('status');
drop trigger if exists employee_advances_guard on public.employee_advances;
create trigger employee_advances_guard before update or delete on public.employee_advances for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason');
drop trigger if exists attendance_import_batches_guard on public.attendance_import_batches;
create trigger attendance_import_batches_guard before update or delete on public.attendance_import_batches for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason',
  'rows_total', 'rows_new', 'rows_dup', 'rows_bad', 'rows_unmapped', 'date_from', 'date_to');
drop trigger if exists leave_requests_guard on public.leave_requests;
create trigger leave_requests_guard before update or delete on public.leave_requests for each row execute function public._status_guard42('status', 'decided_by', 'decided_at', 'decision_note');

create or replace function public._run_guard42() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if new.month is distinct from old.month or new.location_id is distinct from old.location_id or new.created_by is distinct from old.created_by then raise exception 'payroll_run_immutable'; end if;
  if old.status = 'void' then raise exception 'payroll_run_void'; end if;
  return new;
end $$;
drop trigger if exists payroll_runs_guard on public.payroll_runs;
create trigger payroll_runs_guard before update or delete on public.payroll_runs for each row execute function public._run_guard42();

-- a line changes freely only while its run is a draft; afterwards only the payment state (and active, when the run is voided)
create or replace function public._line_guard42() returns trigger language plpgsql set search_path = public as $$
declare st text;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  select status into st from public.payroll_runs where id = old.run_id;
  if new.run_id <> old.run_id or new.employee_id <> old.employee_id or new.month <> old.month then raise exception 'payroll_line_immutable'; end if;
  if st <> 'draft' and (to_jsonb(new) - array['payment_status', 'paid_amount', 'active', 'updated_at']) is distinct from (to_jsonb(old) - array['payment_status', 'paid_amount', 'active', 'updated_at']) then
    raise exception 'payroll_locked: the run is %', st;
  end if;
  return new;
end $$;
drop trigger if exists payroll_lines_guard on public.payroll_lines;
create trigger payroll_lines_guard before update or delete on public.payroll_lines for each row execute function public._line_guard42();

do $$
declare t text;
begin
  foreach t in array array['shifts', 'employee_shift_assignments', 'holidays', 'attendance_devices', 'attendance_days', 'payroll_bonus_events'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;

-- audit (the device counters are not audited: they change on every push)
drop trigger if exists audit_shifts on public.shifts;
create trigger audit_shifts after insert or update on public.shifts for each row execute function public.log_change('id');
drop trigger if exists audit_employee_shift_assignments on public.employee_shift_assignments;
create trigger audit_employee_shift_assignments after insert or update on public.employee_shift_assignments for each row execute function public.log_change('id');
drop trigger if exists audit_holidays on public.holidays;
create trigger audit_holidays after insert or update on public.holidays for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_devices on public.attendance_devices;
create trigger audit_attendance_devices after insert or update of name, location_id, vendor, serial, token_hash, active on public.attendance_devices for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_import_batches on public.attendance_import_batches;
create trigger audit_attendance_import_batches after insert or update on public.attendance_import_batches for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_days on public.attendance_days;
create trigger audit_attendance_days after insert or update on public.attendance_days for each row execute function public.log_change('employee_id,day');
drop trigger if exists audit_leave_requests on public.leave_requests;
create trigger audit_leave_requests after insert or update on public.leave_requests for each row execute function public.log_change('id');
drop trigger if exists audit_employee_advances on public.employee_advances;
create trigger audit_employee_advances after insert or update on public.employee_advances for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_bonus_events on public.payroll_bonus_events;
create trigger audit_payroll_bonus_events after insert or update on public.payroll_bonus_events for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_runs on public.payroll_runs;
create trigger audit_payroll_runs after insert or update on public.payroll_runs for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_lines on public.payroll_lines;
create trigger audit_payroll_lines after insert or update on public.payroll_lines for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_payments on public.payroll_payments;
create trigger audit_payroll_payments after insert or update on public.payroll_payments for each row execute function public.log_change('id');

-- ---------- access helpers ----------
create or replace function public._att_view(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner()
    or exists (select 1 from public.employees e where e.id = p_emp and e.profile_id = auth.uid() and e.profile_id is not null)
    or public._emp_ok(p_emp, array['attendance_manage', 'employee_view', 'employee_manage'], true));
$$;
create or replace function public._att_loc_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (p_loc is not null and public.can_loc(p_loc)
    and (public.has_grant('attendance_manage', p_loc) or public.has_grant('employee_view', p_loc) or public.has_grant('employee_manage', p_loc))));
$$;
-- payroll / salary figures at a place: p_manage = payroll_manage needed (else salary_view or payroll_manage). Null place = owner only.
create or replace function public._pr_ok(p_loc int, p_manage boolean default false) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (p_loc is not null and public.can_loc(p_loc)
    and (public.has_grant('payroll_manage', p_loc) or (not p_manage and public.has_grant('salary_view', p_loc)))));
$$;

-- ---------- RLS: reads only; writes go through the functions ----------
do $$
declare t text;
begin
  foreach t in array array['shifts', 'employee_shift_assignments', 'holidays', 'attendance_devices', 'attendance_import_batches', 'attendance_punches', 'attendance_days',
                           'leave_requests', 'employee_advances', 'employee_advance_recoveries', 'payroll_bonus_events', 'payroll_runs', 'payroll_lines', 'payroll_payments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
drop policy if exists shifts_read on public.shifts;
create policy shifts_read on public.shifts for select to authenticated using (public.is_active());
drop policy if exists esa_read on public.employee_shift_assignments;
create policy esa_read on public.employee_shift_assignments for select to authenticated using (public._att_view(employee_id));
drop policy if exists holidays_read on public.holidays;
create policy holidays_read on public.holidays for select to authenticated using (public.is_active());
drop policy if exists attendance_devices_read on public.attendance_devices;
create policy attendance_devices_read on public.attendance_devices for select to authenticated using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)));
drop policy if exists attendance_import_batches_read on public.attendance_import_batches;
create policy attendance_import_batches_read on public.attendance_import_batches for select to authenticated using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)));
drop policy if exists attendance_punches_read on public.attendance_punches;
create policy attendance_punches_read on public.attendance_punches for select to authenticated using (
  case when employee_id is null then public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)) else public._att_view(employee_id) end);
drop policy if exists attendance_days_read on public.attendance_days;
create policy attendance_days_read on public.attendance_days for select to authenticated using (public._att_view(employee_id));
drop policy if exists leave_requests_read on public.leave_requests;
create policy leave_requests_read on public.leave_requests for select to authenticated using (public._att_view(employee_id));
drop policy if exists employee_advances_read on public.employee_advances;
create policy employee_advances_read on public.employee_advances for select to authenticated using (public._emp_ok(employee_id, array['salary_view', 'payroll_manage']));
drop policy if exists employee_advance_recoveries_read on public.employee_advance_recoveries;
create policy employee_advance_recoveries_read on public.employee_advance_recoveries for select to authenticated
  using (exists (select 1 from public.employee_advances a where a.id = advance_id and public._emp_ok(a.employee_id, array['salary_view', 'payroll_manage'])));
drop policy if exists payroll_bonus_events_read on public.payroll_bonus_events;
create policy payroll_bonus_events_read on public.payroll_bonus_events for select to authenticated using (public._emp_any(array['salary_view', 'payroll_manage']));
drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs for select to authenticated using (public._pr_ok(location_id));
drop policy if exists payroll_lines_read on public.payroll_lines;
create policy payroll_lines_read on public.payroll_lines for select to authenticated using (public._pr_ok(location_id));
drop policy if exists payroll_payments_read on public.payroll_payments;
create policy payroll_payments_read on public.payroll_payments for select to authenticated using (public._pr_ok(location_id));

grant select on public.shifts, public.employee_shift_assignments, public.holidays, public.attendance_import_batches, public.attendance_punches, public.attendance_days,
  public.leave_requests, public.employee_advances, public.employee_advance_recoveries, public.payroll_bonus_events, public.payroll_runs, public.payroll_lines, public.payroll_payments to authenticated;
-- the token hash is never readable
grant select (id, name, location_id, vendor, serial, active, last_seen, pushed_rows, created_by, created_at) on public.attendance_devices to authenticated;

-- ---------- small helpers ----------
create or replace function public._att_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('attendance_on') then raise exception 'attendance_off'; end if;
end $$;
create or replace function public._pr_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('payroll_on') then raise exception 'payroll_off'; end if;
end $$;
-- weekly off mask from the rule: "fri" / "fri,sat" (bit 0 = Sunday)
create or replace function public._att_rule_off_mask() returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(distinct case btrim(lower(x)) when 'sun' then 1 when 'mon' then 2 when 'tue' then 4 when 'wed' then 8 when 'thu' then 16 when 'fri' then 32 when 'sat' then 64 else 0 end), 0)::int
    from unnest(string_to_array(coalesce(public.rule_txt('att_weekly_off'), 'fri'), ',')) x;
$$;
create or replace function public._att_is_off(p_emp uuid, p_day date) returns boolean language sql stable security definer set search_path = public as $$
  select (coalesce((select a.off_mask from public.employee_shift_assignments a where a.employee_id = p_emp and a.active and a.off_mask is not null
                     and a.from_date <= p_day and (a.to_date is null or a.to_date >= p_day) order by a.from_date desc, a.id desc limit 1),
                   public._att_rule_off_mask()) & (1 << extract(dow from p_day)::int)) <> 0;
$$;
create or replace function public._att_holiday(p_loc int, p_day date) returns public.holidays language sql stable security definer set search_path = public as $$
  select * from public.holidays h where h.day = p_day and h.active and (h.location_id is null or h.location_id = p_loc) order by h.location_id nulls last, h.id limit 1;
$$;
-- the shift for a person on a day: assignment (weekday matches) > default of the place > company default
create or replace function public._att_shift_for(p_emp uuid, p_loc int, p_day date) returns public.shifts language plpgsql stable security definer set search_path = public as $$
declare s public.shifts;
begin
  select sh.* into s from public.employee_shift_assignments a join public.shifts sh on sh.id = a.shift_id
   where a.employee_id = p_emp and a.active and a.from_date <= p_day and (a.to_date is null or a.to_date >= p_day) and (a.weekday_mask & (1 << extract(dow from p_day)::int)) <> 0
   order by a.from_date desc, a.id desc limit 1;
  if found then return s; end if;
  select * into s from public.shifts where active and is_default and location_id = p_loc limit 1;
  if found then return s; end if;
  select * into s from public.shifts where active and is_default and location_id is null limit 1;
  return s;
end $$;
-- has an approved payroll locked this person's month?
create or replace function public._att_locked(p_emp uuid, p_day date) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
                  where l.employee_id = p_emp and l.month = date_trunc('month', p_day)::date and l.active and r.status in ('approved', 'paid'));
$$;
-- device time text -> timestamptz (no zone given = Dhaka local time)
create or replace function public._att_ts(p text) returns timestamptz language plpgsql stable as $$
declare v text := btrim(coalesce(p, ''));
begin
  if v !~ '^\d{4}-\d{2}-\d{2}[ T]\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?' then return null; end if;
  if substr(v, 11) ~ '(Z|z|[+-]\d{2}(:?\d{2})?)$' then return v::timestamptz; end if;
  return (v::timestamp) at time zone 'Asia/Dhaka';
exception when others then return null;
end $$;
create or replace function public._att_dir(p text) returns text language sql immutable as $$
  select case lower(btrim(coalesce(p, ''))) when 'in' then 'in' when 'i' then 'in' when 'checkin' then 'in' when 'check_in' then 'in' when '0' then 'in' when '3' then 'in' when '4' then 'in'
    when 'out' then 'out' when 'o' then 'out' when 'checkout' then 'out' when 'check_out' then 'out' when '1' then 'out' when '2' then 'out' when '5' then 'out' else 'unknown' end;
$$;
create or replace function public._hhmm(p text) returns time language plpgsql immutable as $$
begin
  if nullif(btrim(coalesce(p, '')), '') is null then return null; end if;
  if btrim(p) !~ '^\d{1,2}:\d{2}(:\d{2})?$' then raise exception 'bad_time'; end if;
  return btrim(p)::time;
exception when others then raise exception 'bad_time';
end $$;

-- ---------- derive one day (reads only) ----------
create or replace function public._att_derive(p_emp uuid, p_day date) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e public.employees; s public.shifts; hol public.holidays; lv record; v_kind text := 'normal';
  ws timestamptz; we timestamptz; ss timestamptz; se timestamptz; gap interval := make_interval(mins => coalesce(public.rule_num('att_double_punch_min'), 5)::int);
  p record; prev timestamptz; kept timestamptz[] := '{}'; n int; t_in timestamptz; t_out timestamptz;
  worked int := 0; late int := 0; early int := 0; ot int := 0; st text; v_paid boolean; v_leave text; otmin int := coalesce(public.rule_num('att_ot_min_minutes'), 30)::int;
begin
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then return null; end if;
  if e.joining_date is not null and p_day < e.joining_date then return null; end if;
  if e.status in ('resigned', 'terminated', 'retired') and e.status_date is not null and p_day > e.status_date then return null; end if;
  if p_day > public._dhaka_today() then return null; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  select r.leave_type, t.paid into lv from public.leave_requests r join public.leave_types t on t.code = r.leave_type
   where r.employee_id = e.id and r.status = 'approved' and p_day between r.from_date and r.to_date order by r.id limit 1;
  if s.id is not null then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    ws := ss - interval '4 hours';
  else
    ws := p_day::timestamp at time zone 'Asia/Dhaka';
  end if;
  we := ws + interval '24 hours';
  -- first punch = in, last = out; a punch closer than N minutes to the previous one is the same punch
  for p in select punched_at from public.attendance_punches where employee_id = e.id and not void and punched_at >= ws and punched_at < we order by punched_at loop
    if prev is null or p.punched_at - prev >= gap then kept := kept || p.punched_at; end if;
    prev := p.punched_at;
  end loop;
  n := coalesce(array_length(kept, 1), 0);
  if n = 0 then
    if lv.leave_type is not null then st := 'leave'; v_paid := lv.paid; v_leave := lv.leave_type;
    elsif v_kind = 'holiday' then st := 'holiday'; v_paid := hol.paid;
    elsif v_kind = 'off' then st := 'off';
    else st := 'absent'; end if;
  else
    t_in := kept[1]; if n > 1 then t_out := kept[n]; end if;
    if t_out is not null then worked := greatest(0, floor(extract(epoch from (t_out - t_in)) / 60)::int - coalesce(s.break_min, 0)); end if;
    if v_kind = 'normal' then
      if s.id is not null then
        if t_in > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (t_in - ss)) / 60)::int; end if;
        if t_out is not null and t_out < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - t_out)) / 60)::int; end if;
        if t_out is not null and t_out > se then ot := floor(extract(epoch from (t_out - se)) / 60)::int; end if;
      end if;
    else
      ot := worked;                                   -- every worked minute on a holiday / weekly off is overtime
    end if;
    if ot < otmin then ot := 0; end if;
    if v_kind <> 'normal' then st := 'present';
    elsif t_out is null then st := case when late > 0 then 'late' else 'present' end;
    elsif s.id is not null and worked < s.min_hours_half_day * 60 then st := 'absent'; late := 0; early := 0; ot := 0;
    elsif s.id is not null and worked < s.min_hours_full_day * 60 then st := 'half_day';
    elsif late > 0 then st := 'late';
    else st := 'present'; end if;
  end if;
  return jsonb_build_object('employee_id', e.id, 'day', p_day, 'status', st, 'day_kind', v_kind, 'first_in', t_in, 'last_out', t_out, 'worked_minutes', worked,
    'late_minutes', late, 'early_leave_minutes', early, 'ot_minutes', least(ot, 1440), 'punch_count', n, 'single_punch', (n = 1), 'shift_id', s.id,
    'location_id', e.primary_location_id, 'leave_type', v_leave, 'paid_day', v_paid, 'holiday', hol.name_bn);
end $$;

-- store one derived day; a manual row (approved or waiting) and a locked month are never overwritten
create or replace function public._att_store(p_emp uuid, p_day date) returns text language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  if exists (select 1 from public.attendance_days where employee_id = p_emp and day = p_day and source = 'manual') then return 'manual'; end if;
  if public._att_locked(p_emp, p_day) then return 'locked'; end if;
  j := public._att_derive(p_emp, p_day);
  if j is null then return 'none'; end if;
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, computed_at)
    values (p_emp, p_day, j ->> 'status', j ->> 'day_kind', (j ->> 'first_in')::timestamptz, (j ->> 'last_out')::timestamptz, (j ->> 'worked_minutes')::int, (j ->> 'late_minutes')::int,
      (j ->> 'early_leave_minutes')::int, (j ->> 'ot_minutes')::int, (j ->> 'punch_count')::int, (j ->> 'single_punch')::boolean, (j ->> 'shift_id')::int, (j ->> 'location_id')::int,
      j ->> 'leave_type', (j ->> 'paid_day')::boolean, 'auto', now())
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes,
      ot_approved = case when a.ot_minutes = excluded.ot_minutes then a.ot_approved else false end, ot_minutes = excluded.ot_minutes,
      punch_count = excluded.punch_count, single_punch = excluded.single_punch, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = excluded.leave_type,
      paid_day = excluded.paid_day, computed_at = now()
    where a.source = 'auto' and (a.status, a.day_kind, a.first_in, a.last_out, a.worked_minutes, a.late_minutes, a.early_leave_minutes, a.ot_minutes, a.punch_count, a.shift_id, a.location_id, a.leave_type, a.paid_day)
      is distinct from (excluded.status, excluded.day_kind, excluded.first_in, excluded.last_out, excluded.worked_minutes, excluded.late_minutes, excluded.early_leave_minutes, excluded.ot_minutes,
                        excluded.punch_count, excluded.shift_id, excluded.location_id, excluded.leave_type, excluded.paid_day);
  return 'saved';
end $$;

-- recompute a date range (max 62 days) for one person or every working person the caller manages
create or replace function public.attendance_recompute(p_from date, p_to date, p_employee uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_today date := public._dhaka_today(); v_to date; e record; d date; r text; n_saved int := 0; n_manual int := 0; n_locked int := 0; n_emp int := 0;
begin
  perform public._att_gate();
  if p_from is null or p_to is null or p_from < date '2020-01-01' or p_to < p_from or p_to - p_from > 61 then raise exception 'bad_range'; end if;
  v_to := least(p_to, v_today);
  if p_employee is not null and not public._emp_ok(p_employee, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_employee is null and not public._emp_any(array['attendance_manage']) then raise exception 'not allowed'; end if;
  -- late mapping: punches whose device id now belongs to a person
  update public.attendance_punches p set employee_id = x.id from public.employees x
   where p.employee_id is null and not p.void and x.device_user_id = p.device_user_id and x.status not in ('draft', 'discarded') and (p_employee is null or x.id = p_employee);
  for e in select x.id from public.employees x
            where (p_employee is null or x.id = p_employee)
              and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and coalesce(x.status_date, p_from) >= p_from))
              and (p_employee is not null or public._emp_ok(x.id, array['attendance_manage'])) loop
    n_emp := n_emp + 1;
    d := p_from;
    while d <= v_to loop
      r := public._att_store(e.id, d);
      if r = 'saved' then n_saved := n_saved + 1; elsif r = 'manual' then n_manual := n_manual + 1; elsif r = 'locked' then n_locked := n_locked + 1; end if;
      d := d + 1;
    end loop;
  end loop;
  return jsonb_build_object('employees', n_emp, 'days_saved', n_saved, 'manual_kept', n_manual, 'locked', n_locked, 'from', p_from, 'to', v_to);
end $$;

-- ---------- manual mark / approve / OT approve ----------
create or replace function public.attendance_mark(p_emp uuid, p_day date, p_status text, p_in text, p_out text, p_ot_minutes int, p_reason text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_today date := public._dhaka_today(); t1 time := public._hhmm(p_in); t2 time := public._hhmm(p_out);
  ti timestamptz; tout timestamptz; worked int := 0; late int := 0; early int := 0; ot int := coalesce(p_ot_minutes, 0); ss timestamptz; se timestamptz; v_kind text := 'normal'; hol public.holidays; v_appr boolean;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_day is null or p_day > v_today or p_day < v_today - 62 then raise exception 'bad_date'; end if;
  if e.joining_date is not null and p_day < e.joining_date then raise exception 'bad_date'; end if;
  if p_status not in ('present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid') then raise exception 'bad_status'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if ot < 0 or ot > 1440 then raise exception 'bad_ot'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  if t1 is not null then ti := (p_day + t1) at time zone 'Asia/Dhaka'; end if;
  if t2 is not null then tout := (p_day + t2 + case when t1 is not null and t2 <= t1 then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka'; end if;
  if ti is not null and tout is not null then worked := greatest(0, floor(extract(epoch from (tout - ti)) / 60)::int - coalesce(s.break_min, 0)); end if;
  if s.id is not null and ti is not null and v_kind = 'normal' then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    if ti > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (ti - ss)) / 60)::int; end if;
    if tout is not null and tout < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - tout)) / 60)::int; end if;
    if p_ot_minutes is null and tout is not null and tout > se then ot := floor(extract(epoch from (tout - se)) / 60)::int; end if;
  end if;
  if p_status in ('absent', 'off', 'holiday', 'unpaid') then late := 0; early := 0; end if;
  if p_status = 'late' and late = 0 then late := 1; end if;
  v_appr := public.is_owner() and public.rule_on('owner_self_approve');
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, marked_by, marked_at, approved_by, approved_at, override_reason, note, computed_at)
    values (p_emp, p_day, p_status, v_kind, ti, tout, worked, late, early, ot, v_appr, 0, false, s.id, e.primary_location_id, null,
      case when p_status = 'holiday' then coalesce(hol.paid, true) when p_status = 'unpaid' then false end, 'manual', auth.uid(), now(),
      case when v_appr then auth.uid() end, case when v_appr then now() end, btrim(p_reason), nullif(btrim(p_note), ''), now())
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes, ot_minutes = excluded.ot_minutes,
      ot_approved = excluded.ot_approved, punch_count = a.punch_count, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = null, paid_day = excluded.paid_day,
      source = 'manual', marked_by = excluded.marked_by, marked_at = excluded.marked_at, approved_by = excluded.approved_by, approved_at = excluded.approved_at,
      override_reason = excluded.override_reason, note = excluded.note, computed_at = now();
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'status', p_status, 'source', 'manual', 'approved', v_appr, 'late_minutes', late, 'ot_minutes', ot, 'worked_minutes', worked);
end $$;

-- approve a manual override (a second person; the owner is exempt while owner_self_approve is ON) or reject it (the day goes back to the punches)
create or replace function public.attendance_approve(p_emp uuid, p_day date, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.attendance_days;
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  select * into a from public.attendance_days where employee_id = p_emp and day = p_day for update;
  if not found or a.source <> 'manual' then raise exception 'not_found'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  if a.approved_by is not null and coalesce(p_approve, false) then return jsonb_build_object('approved', true, 'repeat', true); end if;
  if a.marked_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_approve'; end if;
  if coalesce(p_approve, false) then
    update public.attendance_days set approved_by = auth.uid(), approved_at = now(), ot_approved = true, note = coalesce(nullif(btrim(p_note), ''), note) where employee_id = p_emp and day = p_day;
    return jsonb_build_object('approved', true);
  end if;
  update public.attendance_days set source = 'auto', approved_by = null, approved_at = null, marked_by = null, marked_at = null, ot_approved = false,
         override_reason = null, note = left('rejected: ' || coalesce(btrim(p_note), ''), 300) where employee_id = p_emp and day = p_day;
  perform public._att_store(p_emp, p_day);
  return jsonb_build_object('approved', false, 'status', (select status from public.attendance_days where employee_id = p_emp and day = p_day));
end $$;

create or replace function public.attendance_ot_approve(p_emp uuid, p_day date, p_ok boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  update public.attendance_days set ot_approved = coalesce(p_ok, true) where employee_id = p_emp and day = p_day and ot_minutes > 0;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'ot_approved', coalesce(p_ok, true));
end $$;

-- ---------- boards ----------
create or replace function public.attendance_board(p_loc int, p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, public._dhaka_today()); rows_ jsonb; cnt jsonb;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  if d > public._dhaka_today() or d < date '2020-01-01' then raise exception 'bad_date'; end if;
  with emp as (
    select x.* from public.employees x
     where x.primary_location_id = p_loc and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and x.status_date >= d))
       and (x.joining_date is null or x.joining_date <= d)),
  r as (select emp.id, emp.employee_no, emp.full_name_bn, emp.full_name_en, emp.photo_path, emp.device_user_id,
               coalesce(to_jsonb(a.*), public._att_derive(emp.id, d)) j, a.employee_id is not null stored
          from emp left join public.attendance_days a on a.employee_id = emp.id and a.day = d)
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', r.id, 'employee_no', r.employee_no, 'name_bn', r.full_name_bn, 'name_en', r.full_name_en, 'photo_path', r.photo_path,
           'has_device_id', r.device_user_id is not null, 'status', r.j ->> 'status', 'day_kind', r.j ->> 'day_kind', 'first_in', r.j ->> 'first_in', 'last_out', r.j ->> 'last_out',
           'worked_minutes', (r.j ->> 'worked_minutes')::int, 'late_minutes', (r.j ->> 'late_minutes')::int, 'ot_minutes', (r.j ->> 'ot_minutes')::int, 'ot_approved', coalesce((r.j ->> 'ot_approved')::boolean, false),
           'single_punch', coalesce((r.j ->> 'single_punch')::boolean, false), 'leave_type', r.j ->> 'leave_type', 'source', coalesce(r.j ->> 'source', 'auto'),
           'pending', (r.j ->> 'source') = 'manual' and (r.j ->> 'approved_by') is null, 'marked_by', r.j ->> 'marked_by', 'reason', r.j ->> 'override_reason', 'stored', r.stored)
           order by r.employee_no nulls last, r.full_name_bn), '[]'),
         jsonb_build_object('total', count(*), 'present', count(*) filter (where r.j ->> 'status' in ('present', 'late', 'half_day')), 'late', count(*) filter (where r.j ->> 'status' = 'late'),
           'absent', count(*) filter (where r.j ->> 'status' = 'absent'), 'leave', count(*) filter (where r.j ->> 'status' = 'leave'),
           'off', count(*) filter (where r.j ->> 'status' in ('off', 'holiday')), 'pending', count(*) filter (where (r.j ->> 'source') = 'manual' and (r.j ->> 'approved_by') is null))
    into rows_, cnt from r;
  return jsonb_build_object('day', d, 'location_id', p_loc, 'rows', rows_, 'counts', cnt);
end $$;

create or replace function public.attendance_month(p_emp uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m0 date := date_trunc('month', p_month)::date; m1 date; out_ jsonb;
begin
  if not public._att_view(p_emp) then raise exception 'not allowed'; end if;
  if p_month is null or m0 < date '2020-01-01' or m0 > public._dhaka_today() then raise exception 'bad_date'; end if;
  m1 := (m0 + interval '1 month')::date - 1;
  select coalesce(jsonb_agg(coalesce(to_jsonb(a.*) || jsonb_build_object('stored', true), public._att_derive(p_emp, g.d::date) || jsonb_build_object('stored', false),
                                     jsonb_build_object('day', g.d::date, 'status', null)) order by g.d), '[]')
    into out_ from generate_series(m0, m1, interval '1 day') g(d) left join public.attendance_days a on a.employee_id = p_emp and a.day = g.d::date;
  return jsonb_build_object('employee_id', p_emp, 'month', m0, 'days', out_, 'locked', public._att_locked(p_emp, m0));
end $$;

-- ---------- shifts, roster, holidays: writes ----------
create or replace function public.shift_save(p_id int, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); s public.shifts; v_loc int;
begin
  perform public._att_gate();
  if p_id is not null then select * into s from public.shifts where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  v_loc := case when d ? 'location_id' then public._e_num(d, 'location_id', 1, 100000)::int else s.location_id end;
  if not (public.is_owner() or (v_loc is not null and public._loc_ok(v_loc, 'attendance_manage') and (p_id is null or s.location_id is not distinct from v_loc))) then raise exception 'not allowed'; end if;
  s.name_bn := coalesce(public._e_txt(d, 'name_bn', 60), s.name_bn); s.name_en := case when d ? 'name_en' then public._e_txt(d, 'name_en', 60) else s.name_en end;
  s.location_id := v_loc;
  s.start_time := coalesce(public._hhmm(d ->> 'start_time'), s.start_time); s.end_time := coalesce(public._hhmm(d ->> 'end_time'), s.end_time);
  s.grace_late_min := coalesce(public._e_num(d, 'grace_late_min', 0, 240)::int, s.grace_late_min, 10); s.grace_early_min := coalesce(public._e_num(d, 'grace_early_min', 0, 240)::int, s.grace_early_min, 10);
  s.break_min := coalesce(public._e_num(d, 'break_min', 0, 600)::int, s.break_min, 60);
  s.crosses_midnight := coalesce((d ->> 'crosses_midnight')::boolean, s.crosses_midnight, false);
  s.min_hours_full_day := coalesce(public._e_num(d, 'min_hours_full_day', 0, 24), s.min_hours_full_day, 7); s.min_hours_half_day := coalesce(public._e_num(d, 'min_hours_half_day', 0, 24), s.min_hours_half_day, 4);
  s.is_default := coalesce((d ->> 'is_default')::boolean, s.is_default, false); s.active := coalesce((d ->> 'active')::boolean, s.active, true);
  if s.name_bn is null then raise exception 'name_required'; end if;
  if s.start_time is null or s.end_time is null then raise exception 'bad_time'; end if;
  if s.min_hours_half_day > s.min_hours_full_day then raise exception 'bad_hours'; end if;
  if s.end_time <= s.start_time then s.crosses_midnight := true; end if;
  if s.is_default and s.active then update public.shifts set is_default = false where is_default and active and coalesce(location_id, 0) = coalesce(s.location_id, 0) and id is distinct from p_id; end if;
  if p_id is null then
    insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight, min_hours_full_day, min_hours_half_day, is_default, active, created_by)
      values (s.name_bn, s.name_en, s.location_id, s.start_time, s.end_time, s.grace_late_min, s.grace_early_min, s.break_min, s.crosses_midnight, s.min_hours_full_day, s.min_hours_half_day, s.is_default, s.active, auth.uid())
      returning id into s.id;
  else
    update public.shifts set name_bn = s.name_bn, name_en = s.name_en, location_id = s.location_id, start_time = s.start_time, end_time = s.end_time, grace_late_min = s.grace_late_min,
      grace_early_min = s.grace_early_min, break_min = s.break_min, crosses_midnight = s.crosses_midnight, min_hours_full_day = s.min_hours_full_day, min_hours_half_day = s.min_hours_half_day,
      is_default = s.is_default, active = s.active where id = p_id;
  end if;
  return to_jsonb(s);
end $$;

create or replace function public.shift_assign(p_emp uuid, p_shift int, p_from date, p_to date default null, p_weekdays int default 127, p_off_mask int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select id into v_id from public.employee_shift_assignments where client_id = p_client; if found then return jsonb_build_object('id', v_id, 'repeat', true); end if; end if;
  if not exists (select 1 from public.shifts where id = p_shift and active) then raise exception 'bad_shift'; end if;
  if p_from is null or p_from < public._dhaka_today() - 400 or p_from > public._dhaka_today() + 400 or (p_to is not null and p_to < p_from) then raise exception 'bad_date'; end if;
  if p_weekdays is null or p_weekdays not between 1 and 127 or (p_off_mask is not null and p_off_mask not between 0 and 127) then raise exception 'bad_mask'; end if;
  insert into public.employee_shift_assignments (client_id, employee_id, shift_id, weekday_mask, off_mask, from_date, to_date, created_by)
    values (p_client, p_emp, p_shift, p_weekdays, p_off_mask, p_from, p_to, auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.shift_assign_end(p_id bigint, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.employee_shift_assignments;
begin
  perform public._att_gate();
  select * into a from public.employee_shift_assignments where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(a.employee_id, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_to is null then update public.employee_shift_assignments set active = false where id = p_id;
  elsif p_to < a.from_date then raise exception 'bad_date';
  else update public.employee_shift_assignments set to_date = p_to where id = p_id; end if;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.holiday_save(p_day date, p_loc int, p_name_bn text, p_name_en text default null, p_paid boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int;
begin
  perform public._att_gate();
  if not (public.is_owner() or (p_loc is not null and public._loc_ok(p_loc, 'attendance_manage'))) then raise exception 'not allowed'; end if;
  if p_day is null or p_day < date '2020-01-01' or p_day > public._dhaka_today() + 730 then raise exception 'bad_date'; end if;
  if nullif(btrim(p_name_bn), '') is null or char_length(p_name_bn) > 80 or char_length(coalesce(p_name_en, '')) > 80 then raise exception 'name_required'; end if;
  select id into v_id from public.holidays where day = p_day and coalesce(location_id, 0) = coalesce(p_loc, 0) and active;
  if found then update public.holidays set name_bn = btrim(p_name_bn), name_en = nullif(btrim(p_name_en), ''), paid = coalesce(p_paid, true) where id = v_id;
  else insert into public.holidays (day, location_id, name_bn, name_en, paid, created_by) values (p_day, p_loc, btrim(p_name_bn), nullif(btrim(p_name_en), ''), coalesce(p_paid, true), auth.uid()) returning id into v_id; end if;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.holiday_retire(p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.holidays;
begin
  perform public._att_gate();
  select * into h from public.holidays where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (h.location_id is not null and public._loc_ok(h.location_id, 'attendance_manage'))) then raise exception 'not allowed'; end if;
  update public.holidays set active = false where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

-- ---------- leave ----------
create or replace function public._leave_days(p_emp uuid, p_from date, p_to date) returns numeric language sql stable security definer set search_path = public as $$
  select count(*)::numeric from generate_series(p_from, p_to, interval '1 day') g(d)
   where not public._att_is_off(p_emp, g.d::date)
     and (public._att_holiday((select primary_location_id from public.employees where id = p_emp), g.d::date)).id is null;
$$;
create or replace function public._leave_used(p_emp uuid, p_type text, p_year int, p_status text, p_exclude bigint default null) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(days), 0) from public.leave_requests where employee_id = p_emp and leave_type = p_type and status = p_status and extract(year from from_date) = p_year and id is distinct from p_exclude;
$$;
create or replace function public.leave_balances(p_emp uuid, p_year int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare y int := coalesce(p_year, extract(year from public._dhaka_today())::int);
begin
  if not public._att_view(p_emp) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('leave_type', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'paid', t.paid,
      'entitled', coalesce(en.days_per_year, 0), 'taken', public._leave_used(p_emp, t.code, y, 'approved'), 'pending', public._leave_used(p_emp, t.code, y, 'pending'),
      'remaining', case when t.paid then coalesce(en.days_per_year, 0) - public._leave_used(p_emp, t.code, y, 'approved') end) order by t.sort)
    from public.leave_types t left join public.employee_leave_entitlements en on en.employee_id = p_emp and en.leave_type = t.code where t.active), '[]');
end $$;

create or replace function public.leave_request_save(p_emp uuid, p_type text, p_from date, p_to date, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; t public.leave_types; v_days numeric; v_ent numeric; v_id bigint; v_today date := public._dhaka_today(); r public.leave_requests;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status not in ('active', 'on_leave') then raise exception 'not_found'; end if;
  if not (public._emp_ok(p_emp, array['attendance_manage']) or (e.profile_id is not null and e.profile_id = auth.uid())) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.leave_requests where client_id = p_client; if found then return to_jsonb(r) || jsonb_build_object('repeat', true); end if; end if;
  select * into t from public.leave_types where code = p_type and active;
  if not found then raise exception 'bad_leave_type'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_from < v_today - 62 or p_to > v_today + 366 or p_to - p_from > 180 then raise exception 'bad_date'; end if;
  if extract(year from p_from) <> extract(year from p_to) then raise exception 'leave_cross_year'; end if;
  if char_length(coalesce(p_reason, '')) > 300 then raise exception 'too_long: reason'; end if;
  if exists (select 1 from public.leave_requests x where x.employee_id = p_emp and x.status in ('pending', 'approved') and x.from_date <= p_to and x.to_date >= p_from) then raise exception 'leave_overlap'; end if;
  if exists (select 1 from generate_series(p_from, p_to, interval '1 day') g(d) where public._att_locked(p_emp, g.d::date)) then raise exception 'month_locked'; end if;
  v_days := public._leave_days(p_emp, p_from, p_to);
  if v_days <= 0 then raise exception 'leave_no_working_days'; end if;
  if t.paid then
    select coalesce(days_per_year, 0) into v_ent from public.employee_leave_entitlements where employee_id = p_emp and leave_type = p_type;
    if coalesce(v_ent, 0) - public._leave_used(p_emp, p_type, extract(year from p_from)::int, 'approved') - public._leave_used(p_emp, p_type, extract(year from p_from)::int, 'pending') < v_days then
      raise exception 'leave_balance_short';
    end if;
  end if;
  insert into public.leave_requests (client_id, employee_id, leave_type, from_date, to_date, days, reason, requested_by)
    values (p_client, p_emp, p_type, p_from, p_to, v_days, nullif(btrim(p_reason), ''), auth.uid()) returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.leave_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.leave_requests; t public.leave_types; v_ent numeric; d date;
begin
  perform public._att_gate();
  select * into r from public.leave_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then raise exception 'leave_not_pending'; end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_approve'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if coalesce(p_approve, false) then
    select * into t from public.leave_types where code = r.leave_type;
    if exists (select 1 from generate_series(r.from_date, r.to_date, interval '1 day') g(x) where public._att_locked(r.employee_id, g.x::date)) then raise exception 'month_locked'; end if;
    if t.paid then
      select coalesce(days_per_year, 0) into v_ent from public.employee_leave_entitlements where employee_id = r.employee_id and leave_type = r.leave_type;
      if coalesce(v_ent, 0) - public._leave_used(r.employee_id, r.leave_type, extract(year from r.from_date)::int, 'approved') < r.days then raise exception 'leave_balance_short'; end if;
    end if;
    update public.leave_requests set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
    d := r.from_date;
    while d <= least(r.to_date, public._dhaka_today()) loop perform public._att_store(r.employee_id, d); d := d + 1; end loop;
  else
    update public.leave_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
  end if;
  return (select to_jsonb(x) from public.leave_requests x where x.id = p_id);
end $$;

create or replace function public.leave_cancel(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.leave_requests; d date; mine boolean;
begin
  perform public._att_gate();
  select * into r from public.leave_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  mine := exists (select 1 from public.employees e where e.id = r.employee_id and e.profile_id = auth.uid());
  if not (public._emp_ok(r.employee_id, array['attendance_manage']) or (mine and r.status = 'pending')) then raise exception 'not allowed'; end if;
  if r.status not in ('pending', 'approved') then raise exception 'leave_not_open'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if r.status = 'approved' and exists (select 1 from generate_series(r.from_date, r.to_date, interval '1 day') g(x) where public._att_locked(r.employee_id, g.x::date)) then raise exception 'month_locked'; end if;
  update public.leave_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(p_reason), 300) where id = p_id;
  if r.status = 'approved' then
    d := r.from_date;
    while d <= least(r.to_date, public._dhaka_today()) loop perform public._att_store(r.employee_id, d); d := d + 1; end loop;
  end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- ---------- punches: ingest (shared by the device push and the file import) ----------
create or replace function public._att_ingest(p_rows jsonb, p_device int, p_loc int, p_source text, p_batch uuid, p_dry boolean, p_max int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := now(); v_ok jsonb; n_total int; n_bad int; bad jsonb; n_valid int; n_dist int; n_db int; unm jsonb; n_unm int; dmin timestamptz; dmax timestamptz; n_new int := 0; n_emp int; pair record;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_rows'; end if;
  n_total := jsonb_array_length(p_rows);
  if n_total > p_max then raise exception 'too_many_rows'; end if;
  with s as (
    select o.i, o.r, case when jsonb_typeof(o.r) = 'object' then nullif(btrim(coalesce(o.r ->> 'user_id', o.r ->> 'uid', '')), '') end uid,
           case when jsonb_typeof(o.r) = 'object' then public._att_ts(coalesce(o.r ->> 'ts', o.r ->> 'time')) end ts
      from jsonb_array_elements(p_rows) with ordinality o(r, i)),
  c as (select s.*, case when jsonb_typeof(s.r) <> 'object' then 'bad_row' when s.uid is null or s.uid !~ '^[A-Za-z0-9_.:-]{1,40}$' then 'bad_user_id' when s.ts is null then 'bad_time'
                       when s.ts < v_now - interval '400 days' or s.ts > v_now + interval '10 minutes' then 'time_out_of_range' end why from s)
  select count(*) filter (where why is not null),
         coalesce(jsonb_agg(jsonb_build_object('row', i, 'why', why) order by i) filter (where why is not null and i <= 1000), '[]'),
         coalesce(jsonb_agg(jsonb_build_object('u', uid, 't', date_trunc('second', ts), 'd', public._att_dir(coalesce(r ->> 'dir', r ->> 'state', r ->> 'direction')),
                                               'raw', jsonb_strip_nulls(jsonb_build_object('verify', r -> 'verify', 'workcode', r -> 'workcode', 'state', coalesce(r -> 'dir', r -> 'state'))))) filter (where why is null), '[]')
    into n_bad, bad, v_ok from c;
  n_valid := jsonb_array_length(v_ok);
  with v as (select distinct x ->> 'u' u, (x ->> 't')::timestamptz t from jsonb_array_elements(v_ok) x)
  select count(*), count(*) filter (where exists (select 1 from public.attendance_punches p where p.device_id is not distinct from p_device and p.device_user_id = v.u and p.punched_at = v.t and not p.void)),
         min(v.t), max(v.t)
    into n_dist, n_db, dmin, dmax from v;
  select coalesce(jsonb_agg(distinct x ->> 'u'), '[]') into unm from jsonb_array_elements(v_ok) x
   where not exists (select 1 from public.employees e where e.device_user_id = x ->> 'u' and e.status not in ('draft', 'discarded'));
  n_unm := jsonb_array_length(unm);
  select count(distinct e.id) into n_emp from jsonb_array_elements(v_ok) x join public.employees e on e.device_user_id = x ->> 'u' and e.status not in ('draft', 'discarded');
  if not p_dry then
    with v as (select distinct on (x ->> 'u', (x ->> 't')::timestamptz) x ->> 'u' u, (x ->> 't')::timestamptz t, x ->> 'd' d, x -> 'raw' raw from jsonb_array_elements(v_ok) x),
    ins as (insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, raw, import_batch, created_by)
            select (select e.id from public.employees e where e.device_user_id = v.u and e.status not in ('draft', 'discarded')), p_device, p_loc, v.u, v.t, v.d, p_source, nullif(v.raw, '{}'::jsonb), p_batch, auth.uid()
              from v
            on conflict (device_id, device_user_id, punched_at) where not void do nothing
            returning employee_id, punched_at)
    select count(*) into n_new from ins;
    -- the days touched (and the day before, for a night shift) are recomputed
    for pair in select distinct p.employee_id, g.d::date d from public.attendance_punches p
                  cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
                 where p.employee_id is not null and not p.void and p.created_at = v_now and p.device_id is not distinct from p_device and p.import_batch is not distinct from p_batch loop
      perform public._att_store(pair.employee_id, pair.d);
    end loop;
  end if;
  return jsonb_build_object('dry', p_dry, 'total', n_total, 'rejected', n_bad, 'rejected_rows', bad, 'valid', n_valid, 'duplicates_in_file', n_valid - n_dist,
    'already_in', n_db, 'new', case when p_dry then n_dist - n_db else n_new end, 'unmapped', n_unm, 'unmapped_ids', unm, 'employees', n_emp, 'from', dmin, 'to', dmax);
end $$;

-- the device bridge (anon key + device token). Inserts punches for THAT device only; reads nothing else and returns only counts.
create or replace function public.attendance_punch_push(p_token text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.attendance_devices; v_min timestamptz := date_trunc('minute', now()); lim int := coalesce(public.rule_num('att_push_per_min'), 30)::int; j jsonb;
begin
  if p_token is null or char_length(p_token) not between 20 and 200 then raise exception 'bad_token'; end if;
  select * into d from public.attendance_devices where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') and active for update;
  if not found then raise exception 'bad_token'; end if;
  if d.rl_minute = v_min and d.rl_count >= lim then raise exception 'rate_limited'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  update public.attendance_devices set last_seen = now(), rl_count = case when rl_minute = v_min then rl_count + 1 else 1 end, rl_minute = v_min where id = d.id;
  j := public._att_ingest(p_rows, d.id, d.location_id, 'device', null, false, 500);
  update public.attendance_devices set pushed_rows = pushed_rows + (j ->> 'new')::int where id = d.id;
  return jsonb_build_object('ok', true, 'received', j -> 'total', 'new', j -> 'new', 'duplicates', (j ->> 'already_in')::int + (j ->> 'duplicates_in_file')::int,
                            'rejected', j -> 'rejected', 'rejected_rows', j -> 'rejected_rows', 'unmapped', j -> 'unmapped');
end $$;

-- file import from the app: p_dry = preview (writes nothing)
create or replace function public.attendance_import(p_loc int, p_device int, p_rows jsonb, p_file text, p_dry boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.attendance_import_batches; j jsonb; v_id uuid := gen_random_uuid();
begin
  perform public._att_gate();
  if not public._loc_ok(p_loc, 'attendance_manage') then raise exception 'not allowed'; end if;
  if p_device is not null and not exists (select 1 from public.attendance_devices where id = p_device and location_id = p_loc) then raise exception 'bad_device'; end if;
  if char_length(coalesce(p_file, '')) > 200 then raise exception 'too_long: file'; end if;
  if p_dry then return public._att_ingest(p_rows, p_device, p_loc, 'file', null, true, 5000); end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into b from public.attendance_import_batches where client_id = p_client; if found then return to_jsonb(b) || jsonb_build_object('repeat', true); end if; end if;
  insert into public.attendance_import_batches (id, client_id, location_id, device_id, file_name, created_by) values (v_id, p_client, p_loc, p_device, nullif(btrim(p_file), ''), auth.uid());
  j := public._att_ingest(p_rows, p_device, p_loc, 'file', v_id, false, 5000);
  update public.attendance_import_batches set rows_total = (j ->> 'total')::int, rows_new = (j ->> 'new')::int, rows_dup = (j ->> 'already_in')::int + (j ->> 'duplicates_in_file')::int,
      rows_bad = (j ->> 'rejected')::int, rows_unmapped = (j ->> 'unmapped')::int, date_from = (j ->> 'from')::timestamptz, date_to = (j ->> 'to')::timestamptz where id = v_id;
  return j || jsonb_build_object('batch', v_id);
end $$;

create or replace function public.attendance_import_void(p_batch uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.attendance_import_batches; pair record; n int;
begin
  perform public._att_gate();
  select * into b from public.attendance_import_batches where id = p_batch for update;
  if not found then raise exception 'not_found'; end if;
  if not public._loc_ok(b.location_id, 'attendance_manage') then raise exception 'not allowed'; end if;
  if b.status = 'void' then return jsonb_build_object('id', b.id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.attendance_punches p where p.import_batch = b.id and p.employee_id is not null and public._att_locked(p.employee_id, (p.punched_at at time zone 'Asia/Dhaka')::date)) then raise exception 'month_locked'; end if;
  update public.attendance_import_batches set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = b.id;
  update public.attendance_punches set void = true where import_batch = b.id and not void;
  get diagnostics n = row_count;
  for pair in select distinct p.employee_id, g.d::date d from public.attendance_punches p
                cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
               where p.import_batch = b.id and p.employee_id is not null loop
    perform public._att_store(pair.employee_id, pair.d);
  end loop;
  return jsonb_build_object('id', b.id, 'status', 'void', 'punches_voided', n);
end $$;

create or replace function public.attendance_unmapped(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._loc_ok(p_loc, 'attendance_manage')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('device_user_id', z.device_user_id, 'device_id', z.device_id, 'device_name', dv.name, 'punches', z.n, 'first_at', z.f, 'last_at', z.l) order by z.l desc)
    from (select p.device_user_id, p.device_id, count(*) n, min(p.punched_at) f, max(p.punched_at) l from public.attendance_punches p
           where p.employee_id is null and not p.void and p.location_id = p_loc group by p.device_user_id, p.device_id) z
    left join public.attendance_devices dv on dv.id = z.device_id), '[]');
end $$;

-- give a device id to a person (employees.device_user_id) and attach the waiting punches
create or replace function public.attendance_map_user(p_device_user_id text, p_emp uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; n int; pair record;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp for update;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['attendance_manage', 'employee_manage']) then raise exception 'not allowed'; end if;
  if p_device_user_id is null or btrim(p_device_user_id) !~ '^[A-Za-z0-9_.:-]{1,40}$' then raise exception 'bad_user_id'; end if;
  if exists (select 1 from public.employees x where x.device_user_id = btrim(p_device_user_id) and x.id <> p_emp) then raise exception 'duplicate_device_id'; end if;
  if e.device_user_id is distinct from btrim(p_device_user_id) then
    if e.device_user_id is not null and exists (select 1 from public.attendance_punches p where p.employee_id = p_emp and p.device_user_id = e.device_user_id) then raise exception 'device_id_in_use'; end if;
    update public.employees set device_user_id = btrim(p_device_user_id), updated_by = auth.uid(), updated_at = now() where id = p_emp;
  end if;
  update public.attendance_punches set employee_id = p_emp where employee_id is null and not void and device_user_id = btrim(p_device_user_id);
  get diagnostics n = row_count;
  for pair in select distinct g.d::date d from public.attendance_punches p
                cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
               where p.employee_id = p_emp and p.device_user_id = btrim(p_device_user_id) and not p.void and p.punched_at > now() - interval '70 days' loop
    perform public._att_store(p_emp, pair.d);
  end loop;
  return jsonb_build_object('employee_id', p_emp, 'device_user_id', btrim(p_device_user_id), 'punches_mapped', n);
end $$;

-- devices: the owner registers a device and sees its token once (only a hash is stored)
create or replace function public.attendance_device_register(p_name text, p_loc int, p_vendor text default 'zkteco', p_serial text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tok text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); v_id int;
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if coalesce(p_vendor, 'zkteco') not in ('zkteco', 'hikvision', 'suprema', 'other') then raise exception 'bad_vendor'; end if;
  if char_length(coalesce(p_serial, '')) > 60 then raise exception 'too_long: serial'; end if;
  insert into public.attendance_devices (name, location_id, vendor, serial, token_hash, created_by)
    values (btrim(p_name), p_loc, coalesce(p_vendor, 'zkteco'), nullif(btrim(p_serial), ''), encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_tok, 'shown_once', true);
end $$;
create or replace function public.attendance_device_token_reset(p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tok text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.attendance_devices set token_hash = encode(sha256(convert_to(v_tok, 'UTF8')), 'hex') where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'token', v_tok, 'shown_once', true);
end $$;
create or replace function public.attendance_device_set_active(p_id int, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.attendance_devices set active = coalesce(p_active, false) where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'active', coalesce(p_active, false));
end $$;

-- optional staff check in / out from the app (rule app_punch_on, default OFF)
create or replace function public.attendance_app_punch(p_dir text default 'unknown') returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint;
begin
  perform public._att_gate();
  if not public.rule_on('app_punch_on') then raise exception 'app_punch_off'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then raise exception 'no_employee_record'; end if;
  if exists (select 1 from public.attendance_punches where employee_id = e.id and source = 'app' and punched_at > now() - interval '1 minute' and not void) then raise exception 'too_soon'; end if;
  insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, created_by)
    values (e.id, null, e.primary_location_id, 'app:' || e.id::text, date_trunc('second', now()), case when p_dir in ('in', 'out') then p_dir else 'unknown' end, 'app', auth.uid()) returning id into v_id;
  perform public._att_store(e.id, public._dhaka_today());
  if (now() at time zone 'Asia/Dhaka')::time < time '06:00' then perform public._att_store(e.id, public._dhaka_today() - 1); end if;
  return jsonb_build_object('id', v_id, 'at', now(), 'direction', case when p_dir in ('in', 'out') then p_dir else 'unknown' end);
end $$;

-- ---------- advances (salary-sensitive) ----------
create or replace function public._adv_outstanding(p_adv bigint) returns numeric language sql stable security definer set search_path = public as $$
  select a.amount - coalesce((select sum(r.amount) from public.employee_advance_recoveries r where r.advance_id = a.id and r.status = 'active'), 0) from public.employee_advances a where a.id = p_adv;
$$;
-- 02-3 register (paper form data): the latest written balance for this person, when the name / staff id matches. Information only.
create or replace function public._adv_02_3(p_emp uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._db_num(a.v -> 'balance') from public.employees e
    left join public.profiles pr on pr.id = e.profile_id
    join public.entries x on x.form_code = '02-3' and x.status in ('submitted', 'approved') and x.location_id = e.primary_location_id
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.data -> 'adv') = 'array' then x.data -> 'adv' else '[]'::jsonb end) with ordinality a(v, n)
   where e.id = p_emp and lower(btrim(split_part(coalesce(x.data ->> 'staff', ''), ' - ', 1))) in (lower(coalesce(e.employee_no, '-')), lower(e.full_name_bn), lower(coalesce(e.full_name_en, '-')), lower(coalesce(pr.staff_id, '-')), lower(coalesce(pr.full_name, '-')))
   order by x.entry_date desc, x.serial desc, a.n desc limit 1;
$$;

create or replace function public.staff_advance_add(p_emp uuid, p_date date, p_amount numeric, p_instalment numeric, p_mode text, p_recover_from date, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; r public.employee_advances; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['payroll_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.employee_advances where client_id = p_client; if found then return to_jsonb(r) || jsonb_build_object('repeat', true); end if; end if;
  if p_date is null or p_date > v_today or p_date < v_today - 400 then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount > 0 and p_amount <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_instalment is not null and not (p_instalment > 0 and p_instalment <= p_amount) then raise exception 'bad_instalment'; end if;
  if coalesce(p_mode, 'none') not in ('none', 'cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if coalesce(p_mode, 'none') <> 'none' then perform public.lock_check(p_date); end if;
  insert into public.employee_advances (client_id, employee_id, location_id, adv_date, amount, instalment, recover_from, mode, note, created_by)
    values (p_client, p_emp, e.primary_location_id, p_date, round(p_amount, 2), round(p_instalment, 2), date_trunc('month', coalesce(p_recover_from, p_date))::date, coalesce(p_mode, 'none'), nullif(btrim(p_note), ''), auth.uid())
    returning * into r;
  return to_jsonb(r) || jsonb_build_object('outstanding', r.amount);
end $$;
create or replace function public.staff_advance_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.employee_advances;
begin
  perform public._pr_gate();
  select * into a from public.employee_advances where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(a.employee_id, array['payroll_manage']) then raise exception 'not allowed'; end if;
  if a.status = 'void' then return jsonb_build_object('id', p_id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.employee_advance_recoveries r where r.advance_id = p_id and r.status = 'active') then raise exception 'advance_partly_recovered'; end if;
  if a.mode <> 'none' then perform public.lock_check(a.adv_date); end if;
  update public.employee_advances set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;
create or replace function public.staff_advances_list(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view', 'payroll_manage']) then raise exception 'not allowed'; end if;
  return jsonb_build_object('advances', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('outstanding', public._adv_outstanding(a.id)) order by a.adv_date desc, a.id desc)
                                                    from public.employee_advances a where a.employee_id = p_emp), '[]'),
                            'register_02_3_balance', public._adv_02_3(p_emp));
end $$;

create or replace function public.payroll_bonus_event_save(p_month date, p_name text, p_loc int default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; m date := date_trunc('month', p_month)::date;
begin
  perform public._pr_gate();
  if not (public.is_owner() or (p_loc is not null and public._pr_ok(p_loc, true))) then raise exception 'not allowed'; end if;
  if p_month is null or m < date '2020-01-01' or m > public._dhaka_today() + 400 then raise exception 'bad_date'; end if;
  if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
  select id into v_id from public.payroll_bonus_events where month = m and lower(name) = lower(btrim(p_name)) and coalesce(location_id, 0) = coalesce(p_loc, 0) and active;
  if found then
    if not coalesce(p_active, true) then update public.payroll_bonus_events set active = false where id = v_id; end if;
  elsif coalesce(p_active, true) then
    insert into public.payroll_bonus_events (month, name, location_id, created_by) values (m, btrim(p_name), p_loc, auth.uid()) returning id into v_id;
  end if;
  return jsonb_build_object('id', v_id, 'month', m, 'name', btrim(p_name), 'active', coalesce(p_active, true));
end $$;

-- ---------- payroll calculation (pure read; preview and create both use it, so their numbers are the same) ----------
create or replace function public._pr_totals(j jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g numeric; d numeric; raw numeric; net numeric; b numeric; od numeric; ap numeric; an numeric;
begin
  select coalesce(sum((x ->> 'amount')::numeric), 0) into b from jsonb_array_elements(coalesce(j -> 'bonus', '[]')) x;
  select coalesce(sum((x ->> 'amount')::numeric), 0) into od from jsonb_array_elements(coalesce(j -> 'other_deductions', '[]')) x;
  select coalesce(sum((x ->> 'amount')::numeric) filter (where (x ->> 'amount')::numeric > 0), 0), coalesce(-sum((x ->> 'amount')::numeric) filter (where (x ->> 'amount')::numeric < 0), 0)
    into ap, an from jsonb_array_elements(coalesce(j -> 'adjustments', '[]')) x;
  g := round(coalesce((j ->> 'basic_amount')::numeric, 0) + coalesce((j ->> 'allowance_total')::numeric, 0) + coalesce((j ->> 'ot_amount')::numeric, 0) + b + ap, 2);
  d := round(coalesce((j ->> 'not_employed_deduction')::numeric, 0) + coalesce((j ->> 'absent_deduction')::numeric, 0) + coalesce((j ->> 'unpaid_deduction')::numeric, 0)
           + coalesce((j ->> 'late_deduction')::numeric, 0) + coalesce((j ->> 'structure_deduction_total')::numeric, 0) + coalesce((j ->> 'advance_recovery')::numeric, 0) + od + an, 2);
  raw := g - d;
  net := case when coalesce(public.rule_txt('pay_round_net'), 'nearest') = 'nearest' then round(raw, 0) else round(raw, 2) end;
  return jsonb_build_object('gross', g, 'deductions', d, 'round_adj', net - raw, 'net', net, 'bonus_total', b);
end $$;

create or replace function public._payroll_calc(p_emp uuid, p_month date, p_last date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; pay public.employee_pay; m0 date := date_trunc('month', p_month)::date; m1 date; dim int; v_today date := public._dhaka_today();
  ef date; et date; employed int; notemp int; comps jsonb; pc jsonb; f numeric; c jsonb; allow jsonb := '[]'; sded jsonb := '[]'; at numeric := 0; sdt numeric := 0; v numeric;
  a record; w jsonb := '[]'; trail jsonb := '[]'; day_rate numeric; hourly numeric; hb numeric; basic_amt numeric; abs_eq numeric; unpaid_total numeric; paid_days numeric;
  notemp_ded numeric := 0; abs_ded numeric := 0; unp_ded numeric := 0; late_ded numeric := 0; late_mode text := coalesce(public.rule_txt('att_late_mode'), 'count'); late_n int := greatest(coalesce(public.rule_num('att_lates_per_day'), 3)::int, 1);
  ot_amt numeric := 0; m_norm numeric := 0; m_hol numeric := 0; bonus jsonb := '[]'; ev record; br jsonb; svc int; adv record; avail numeric; take numeric; rec numeric := 0; advs jsonb := '[]';
  pre jsonb; tot jsonb; line jsonb; off_paid boolean := public.rule_on('pay_weekly_off_paid'); hol_paid boolean := public.rule_on('pay_holiday_paid'); cap int := (coalesce(public.rule_num('att_ot_cap_hours'), 2) * 60)::int;
  ab numeric := coalesce(public.rule_num('att_bonus_amount'), 0); adv0203 numeric;
begin
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then return null; end if;
  m1 := (m0 + interval '1 month')::date - 1; dim := m1 - m0 + 1;
  ef := greatest(m0, coalesce(e.joining_date, m0));
  et := least(m1, coalesce(p_last, case when e.status in ('resigned', 'terminated', 'retired') then e.status_date end, m1));
  if et < ef then return null; end if;
  employed := et - ef + 1; notemp := dim - employed;
  if e.joining_date is null then w := w || '["no_joining_date"]'; end if;
  pay := public._emp_pay_on(e.id, et);
  if pay.id is null then
    return jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name', e.full_name_bn, 'name_en', e.full_name_en, 'location_id', e.primary_location_id, 'month', m0,
      'days_in_month', dim, 'employed_days', employed, 'basic', 0, 'basic_amount', 0, 'gross', 0, 'deductions', 0, 'net', 0, 'round_adj', 0, 'warnings', w || '["no_pay_structure"]', 'skip', true);
  end if;
  hb := coalesce(pay.ot_hours_basis, 8);
  f := employed::numeric / dim;
  select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'name', x.name, 'amount', x.amount, 'percent_of_basic', x.percent_of_basic) order by x.id), '[]') into comps
    from public.employee_pay_components x where x.pay_id = pay.id and x.active;
  pc := public._pay_calc(pay.basic, comps);
  for c in select * from jsonb_array_elements(pc -> 'components') loop
    v := round((c ->> 'calc')::numeric * f, 2);
    if c ->> 'kind' = 'allowance' then allow := allow || jsonb_build_array(jsonb_build_object('name', c ->> 'name', 'amount', v)); at := at + v;
    else sded := sded || jsonb_build_array(jsonb_build_object('name', c ->> 'name', 'amount', v)); sdt := sdt + v; end if;
  end loop;
  -- attendance of the employed days
  select count(*) filter (where d.employee_id is null and g.x::date <= v_today) missing, count(*) filter (where d.employee_id is null and g.x::date > v_today) future,
         count(*) filter (where d.status = 'absent') absent, count(*) filter (where d.status = 'half_day') half, count(*) filter (where d.status = 'unpaid') unpaid,
         count(*) filter (where d.status = 'leave' and coalesce(d.paid_day, true)) lpaid, count(*) filter (where d.status = 'leave' and d.paid_day = false) lunpaid,
         count(*) filter (where d.status = 'off') off, count(*) filter (where d.status = 'holiday' and coalesce(d.paid_day, true)) hpaid, count(*) filter (where d.status = 'holiday' and d.paid_day = false) hunpaid,
         count(*) filter (where d.late_minutes > 0 and d.status in ('present', 'late', 'half_day')) late_count,
         coalesce(sum(d.late_minutes) filter (where d.status in ('present', 'late', 'half_day')), 0) late_min,
         coalesce(sum(case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end) filter (where d.day_kind = 'normal'), 0) ot_norm,
         coalesce(sum(case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end) filter (where d.day_kind <> 'normal'), 0) ot_hol,
         coalesce(sum(d.ot_minutes - case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end), 0) ot_held,
         count(*) filter (where d.source = 'manual' and d.approved_by is null) pending, count(*) filter (where d.single_punch) single,
         coalesce(sum(d.worked_minutes), 0) worked
    into a from generate_series(ef, et, interval '1 day') g(x) left join public.attendance_days d on d.employee_id = e.id and d.day = g.x::date;
  if a.missing > 0 then w := w || jsonb_build_array('days_not_computed:' || a.missing); end if;
  if a.future > 0 then w := w || jsonb_build_array('month_not_finished:' || a.future); end if;
  if a.pending > 0 then w := w || jsonb_build_array('unapproved_days:' || a.pending); end if;
  if a.single > 0 then w := w || jsonb_build_array('single_punch_days:' || a.single); end if;
  if a.ot_held > 0 then w := w || jsonb_build_array('ot_waiting_approval_min:' || a.ot_held); end if;
  abs_eq := a.absent + 0.5 * a.half;
  unpaid_total := a.unpaid + a.lunpaid + a.hunpaid + case when off_paid then 0 else a.off end + case when hol_paid then 0 else a.hpaid end;
  paid_days := employed - abs_eq - unpaid_total;
  trail := trail || jsonb_build_array(jsonb_build_object('k', 'basic', 'f', pay.pay_basis || ' ' || pay.basic, 'v', pay.basic),
                                      jsonb_build_object('k', 'days', 'f', employed || ' / ' || dim, 'v', employed));
  if pay.pay_basis = 'monthly' then
    day_rate := pay.basic / dim; hourly := pay.basic / dim / hb; basic_amt := round(pay.basic, 2);
    notemp_ded := round(day_rate * notemp, 2); abs_ded := round(day_rate * abs_eq, 2); unp_ded := round(day_rate * unpaid_total, 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'day_rate', 'f', pay.basic || ' / ' || dim, 'v', round(day_rate, 4)));
    if notemp > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'not_employed', 'f', notemp || ' × ' || round(day_rate, 4), 'v', -notemp_ded)); end if;
    if abs_eq > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'absent', 'f', abs_eq || ' × ' || round(day_rate, 4), 'v', -abs_ded)); end if;
    if unpaid_total > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'unpaid', 'f', unpaid_total || ' × ' || round(day_rate, 4), 'v', -unp_ded)); end if;
  elsif pay.pay_basis = 'daily' then
    day_rate := pay.basic; hourly := pay.basic / hb; basic_amt := round(pay.basic * paid_days, 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'daily_pay', 'f', paid_days || ' × ' || pay.basic, 'v', basic_amt));
  else
    day_rate := pay.basic * hb; hourly := pay.basic;
    basic_amt := round(pay.basic * (a.worked / 60.0 + (a.lpaid + case when hol_paid then a.hpaid else 0 end + case when off_paid then a.off else 0 end) * hb), 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'hourly_pay', 'f', round(a.worked / 60.0, 2) || ' h × ' || pay.basic, 'v', basic_amt));
  end if;
  if at > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'allowances', 'f', case when f < 1 then 'x ' || employed || '/' || dim else '' end, 'v', at)); end if;
  -- late
  if late_mode = 'count' then
    late_ded := round(day_rate * floor(a.late_count::numeric / late_n), 2);
    if a.late_count > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'late', 'f', a.late_count || ' / ' || late_n || ' = ' || floor(a.late_count::numeric / late_n) || ' × ' || round(day_rate, 4), 'v', -late_ded)); end if;
  elsif late_mode = 'per_minute' then
    late_ded := round(a.late_min * day_rate / (hb * 60), 2);
    if a.late_min > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'late', 'f', a.late_min || ' min × ' || round(day_rate / (hb * 60), 4), 'v', -late_ded)); end if;
  end if;
  -- overtime
  if pay.ot_rule = 'multiple_of_hourly' then
    m_norm := pay.ot_value; m_hol := greatest(pay.ot_value, coalesce(public.rule_num('ot_mult_holiday'), 2));
    ot_amt := round(hourly * m_norm * a.ot_norm / 60.0 + hourly * m_hol * a.ot_hol / 60.0, 2);
  elsif pay.ot_rule = 'rate_per_hour' then
    hourly := pay.ot_value; m_norm := 1; m_hol := 1;
    ot_amt := round(pay.ot_value * (a.ot_norm + a.ot_hol) / 60.0, 2);
  elsif a.ot_norm + a.ot_hol > 0 then w := w || '["ot_not_paid_no_rule"]';
  end if;
  if ot_amt > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'ot', 'f', round(a.ot_norm / 60.0, 2) || ' h × ' || round(hourly, 4) || ' × ' || m_norm
                                       || case when a.ot_hol > 0 then ' + ' || round(a.ot_hol / 60.0, 2) || ' h × ' || round(hourly, 4) || ' × ' || m_hol else '' end, 'v', ot_amt)); end if;
  -- bonuses: attendance bonus, festival bonus (event of the month x the person's bonus rule)
  if ab > 0 and abs_eq = 0 and a.late_count = 0 and unpaid_total = 0 and a.missing = 0 and notemp = 0 then
    bonus := bonus || jsonb_build_array(jsonb_build_object('name', 'attendance_bonus', 'amount', round(ab, 2), 'auto', true));
  end if;
  for ev in select * from public.payroll_bonus_events b where b.month = m0 and b.active and (b.location_id is null or b.location_id = e.primary_location_id) order by b.id loop
    select x into br from jsonb_array_elements(coalesce(pay.bonus_rules, '[]')) x where lower(x ->> 'name') = lower(ev.name) limit 1;
    if br is null then continue; end if;
    svc := case when e.joining_date is null then 0 else (extract(year from age(m1 + 1, e.joining_date)) * 12 + extract(month from age(m1 + 1, e.joining_date)))::int end;
    if svc >= coalesce((br ->> 'min_service_months')::numeric, 0) then
      bonus := bonus || jsonb_build_array(jsonb_build_object('name', ev.name, 'amount', round(pay.basic * (br ->> 'months_of_basic')::numeric, 2), 'auto', true, 'service_months', svc));
    else
      w := w || jsonb_build_array('bonus_not_eligible:' || ev.name);
    end if;
  end loop;
  line := jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name', e.full_name_bn, 'name_en', e.full_name_en, 'location_id', e.primary_location_id, 'month', m0,
    'pay_id', pay.id, 'pay_basis', pay.pay_basis, 'basic', pay.basic, 'basic_amount', basic_amt, 'allowances', allow, 'allowance_total', at, 'structure_deductions', sded, 'structure_deduction_total', sdt,
    'days_in_month', dim, 'employed_days', employed, 'paid_days', paid_days, 'absent_days', a.absent, 'half_days', a.half, 'unpaid_leave_days', unpaid_total, 'paid_leave_days', a.lpaid,
    'off_days', a.off, 'holiday_days', a.hpaid + a.hunpaid, 'late_count', a.late_count, 'late_minutes', a.late_min, 'late_deduction', late_ded, 'absent_deduction', abs_ded,
    'unpaid_deduction', unp_ded, 'not_employed_deduction', notemp_ded, 'ot_minutes', a.ot_norm + a.ot_hol, 'ot_amount', ot_amt, 'bonus', bonus, 'advance_recovery', 0, 'advances', '[]'::jsonb,
    'other_deductions', '[]'::jsonb, 'adjustments', '[]'::jsonb);
  -- advance recovery: oldest first, instalment by instalment, never more than what is left of the pay
  pre := public._pr_totals(line);
  avail := greatest((pre ->> 'gross')::numeric - (pre ->> 'deductions')::numeric, 0);
  for adv in select x.id, x.instalment, public._adv_outstanding(x.id) os from public.employee_advances x
              where x.employee_id = e.id and x.status = 'active' and x.recover_from <= m0 order by x.adv_date, x.id loop
    if adv.os <= 0 then continue; end if;
    take := least(adv.os, coalesce(adv.instalment, adv.os), avail);
    if take < least(adv.os, coalesce(adv.instalment, adv.os)) then w := w || '["advance_recovery_capped"]'; end if;
    if take > 0 then advs := advs || jsonb_build_array(jsonb_build_object('advance_id', adv.id, 'amount', round(take, 2), 'outstanding_before', adv.os)); rec := rec + round(take, 2); avail := avail - take; end if;
  end loop;
  if rec > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'advance', 'f', jsonb_array_length(advs) || '', 'v', -rec)); end if;
  if sdt > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'structure_deductions', 'f', '', 'v', -sdt)); end if;
  line := line || jsonb_build_object('advance_recovery', rec, 'advances', advs);
  tot := public._pr_totals(line);
  if (tot ->> 'net')::numeric < 0 then w := w || '["negative_net"]'; end if;
  adv0203 := public._adv_02_3(e.id);
  if coalesce(adv0203, 0) > 0 and not exists (select 1 from public.employee_advances x where x.employee_id = e.id and x.status = 'active') then w := w || jsonb_build_array('register_02_3_advance:' || adv0203); end if;
  return line || tot || jsonb_build_object('warnings', w, 'calc_detail', jsonb_build_object('trail', trail, 'day_rate', round(day_rate, 4), 'hourly', round(hourly, 4), 'ot_mult', m_norm, 'ot_mult_holiday', m_hol,
    'late_mode', late_mode, 'lates_per_day', late_n, 'missing_days', a.missing, 'future_days', a.future, 'pending_days', a.pending, 'ot_held_minutes', a.ot_held, 'register_02_3_balance', adv0203,
    'period', jsonb_build_object('from', ef, 'to', et)));
end $$;

-- who goes into a run: working staff + leavers of the month, at the place, the caller has payroll rights there
create or replace function public._pr_people(p_month date, p_loc int, p_manage boolean) returns setof uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e
   where (p_loc is null or e.primary_location_id = p_loc)
     and (e.status in ('active', 'on_leave') or (e.status in ('resigned', 'terminated', 'retired') and e.status_date >= p_month))
     and (e.joining_date is null or e.joining_date <= (p_month + interval '1 month')::date - 1)
     and public._pr_ok(e.primary_location_id, p_manage)
   order by e.employee_no nulls last, e.full_name_bn;
$$;
create or replace function public._pr_month(p_month date) returns date language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date;
begin
  if p_month is null or m < date '2020-01-01' or m > date_trunc('month', public._dhaka_today())::date then raise exception 'bad_month'; end if;
  return m;
end $$;

create or replace function public.payroll_preview(p_month date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._pr_month(p_month); lines jsonb := '[]'; skipped jsonb := '[]'; j jsonb; x uuid; taken uuid;
begin
  perform public._pr_gate();
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._pr_ok(p_loc, false) then raise exception 'not allowed'; end if;
  for x in select * from public._pr_people(m, p_loc, false) loop
    select l.employee_id into taken from public.payroll_lines l where l.employee_id = x and l.month = m and l.active;
    j := public._payroll_calc(x, m);
    if j is null then continue; end if;
    if taken is not null then j := j || jsonb_build_object('warnings', (j -> 'warnings') || '["already_in_run"]', 'in_run', true); end if;
    lines := lines || jsonb_build_array(j);
  end loop;
  return jsonb_build_object('dry', true, 'month', m, 'location_id', p_loc, 'lines', lines, 'totals', jsonb_build_object(
    'people', (select count(*) from jsonb_array_elements(lines) l where not coalesce((l ->> 'skip')::boolean, false)),
    'gross', (select coalesce(sum((l ->> 'gross')::numeric), 0) from jsonb_array_elements(lines) l), 'deductions', (select coalesce(sum((l ->> 'deductions')::numeric), 0) from jsonb_array_elements(lines) l),
    'net', (select coalesce(sum((l ->> 'net')::numeric), 0) from jsonb_array_elements(lines) l),
    'warnings', (select count(*) from jsonb_array_elements(lines) l where jsonb_array_length(l -> 'warnings') > 0)));
end $$;

-- write one calculated line into a draft run (keeps the manual bonus / deduction / adjustment items of an existing line)
create or replace function public._pr_put_line(p_run bigint, p_emp uuid, p_month date) returns bigint language plpgsql security definer set search_path = public as $$
declare j jsonb; old public.payroll_lines; v_id bigint; tot jsonb;
begin
  j := public._payroll_calc(p_emp, p_month);
  if j is null or coalesce((j ->> 'skip')::boolean, false) then return null; end if;
  select * into old from public.payroll_lines where run_id = p_run and employee_id = p_emp and active;
  if found then
    j := j || jsonb_build_object('bonus', (j -> 'bonus') || coalesce((select jsonb_agg(x) from jsonb_array_elements(old.bonus) x where not coalesce((x ->> 'auto')::boolean, false)), '[]'),
                                 'other_deductions', old.other_deductions, 'adjustments', old.adjustments);
  end if;
  tot := public._pr_totals(j);
  j := j || tot;
  if old.id is not null then
    update public.payroll_lines set location_id = (j ->> 'location_id')::int, employee_no = j ->> 'employee_no', name = j ->> 'name', pay_id = (j ->> 'pay_id')::bigint, pay_basis = j ->> 'pay_basis',
      basic = (j ->> 'basic')::numeric, basic_amount = (j ->> 'basic_amount')::numeric, allowances = j -> 'allowances', allowance_total = (j ->> 'allowance_total')::numeric,
      structure_deductions = j -> 'structure_deductions', structure_deduction_total = (j ->> 'structure_deduction_total')::numeric, days_in_month = (j ->> 'days_in_month')::int,
      employed_days = (j ->> 'employed_days')::int, paid_days = (j ->> 'paid_days')::numeric, absent_days = (j ->> 'absent_days')::numeric, half_days = (j ->> 'half_days')::int,
      unpaid_leave_days = (j ->> 'unpaid_leave_days')::numeric, paid_leave_days = (j ->> 'paid_leave_days')::numeric, off_days = (j ->> 'off_days')::int, holiday_days = (j ->> 'holiday_days')::int,
      late_count = (j ->> 'late_count')::int, late_minutes = (j ->> 'late_minutes')::int, late_deduction = (j ->> 'late_deduction')::numeric, absent_deduction = (j ->> 'absent_deduction')::numeric,
      unpaid_deduction = (j ->> 'unpaid_deduction')::numeric, not_employed_deduction = (j ->> 'not_employed_deduction')::numeric, ot_minutes = (j ->> 'ot_minutes')::int, ot_amount = (j ->> 'ot_amount')::numeric,
      bonus = j -> 'bonus', advance_recovery = (j ->> 'advance_recovery')::numeric, advances = j -> 'advances', other_deductions = j -> 'other_deductions', adjustments = j -> 'adjustments',
      gross = (j ->> 'gross')::numeric, deductions = (j ->> 'deductions')::numeric, round_adj = (j ->> 'round_adj')::numeric, net = (j ->> 'net')::numeric, warnings = j -> 'warnings',
      calc_detail = j -> 'calc_detail', updated_at = now() where id = old.id;
    return old.id;
  end if;
  insert into public.payroll_lines (run_id, month, employee_id, location_id, employee_no, name, pay_id, pay_basis, basic, basic_amount, allowances, allowance_total, structure_deductions,
      structure_deduction_total, days_in_month, employed_days, paid_days, absent_days, half_days, unpaid_leave_days, paid_leave_days, off_days, holiday_days, late_count, late_minutes,
      late_deduction, absent_deduction, unpaid_deduction, not_employed_deduction, ot_minutes, ot_amount, bonus, advance_recovery, advances, other_deductions, adjustments,
      gross, deductions, round_adj, net, warnings, calc_detail)
    values (p_run, p_month, p_emp, (j ->> 'location_id')::int, j ->> 'employee_no', j ->> 'name', (j ->> 'pay_id')::bigint, j ->> 'pay_basis', (j ->> 'basic')::numeric, (j ->> 'basic_amount')::numeric,
      j -> 'allowances', (j ->> 'allowance_total')::numeric, j -> 'structure_deductions', (j ->> 'structure_deduction_total')::numeric, (j ->> 'days_in_month')::int, (j ->> 'employed_days')::int,
      (j ->> 'paid_days')::numeric, (j ->> 'absent_days')::numeric, (j ->> 'half_days')::int, (j ->> 'unpaid_leave_days')::numeric, (j ->> 'paid_leave_days')::numeric, (j ->> 'off_days')::int,
      (j ->> 'holiday_days')::int, (j ->> 'late_count')::int, (j ->> 'late_minutes')::int, (j ->> 'late_deduction')::numeric, (j ->> 'absent_deduction')::numeric, (j ->> 'unpaid_deduction')::numeric,
      (j ->> 'not_employed_deduction')::numeric, (j ->> 'ot_minutes')::int, (j ->> 'ot_amount')::numeric, j -> 'bonus', (j ->> 'advance_recovery')::numeric, j -> 'advances', j -> 'other_deductions',
      j -> 'adjustments', (j ->> 'gross')::numeric, (j ->> 'deductions')::numeric, (j ->> 'round_adj')::numeric, (j ->> 'net')::numeric, j -> 'warnings', j -> 'calc_detail')
    returning id into v_id;
  return v_id;
end $$;

create or replace function public._pr_run_json(p_run bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(r) || jsonb_build_object('lines', (select count(*) from public.payroll_lines l where l.run_id = r.id and l.active),
    'gross', (select coalesce(sum(l.gross), 0) from public.payroll_lines l where l.run_id = r.id and l.active), 'deductions', (select coalesce(sum(l.deductions), 0) from public.payroll_lines l where l.run_id = r.id and l.active),
    'net', (select coalesce(sum(l.net), 0) from public.payroll_lines l where l.run_id = r.id and l.active), 'paid', (select coalesce(sum(l.paid_amount), 0) from public.payroll_lines l where l.run_id = r.id and l.active))
  from public.payroll_runs r where r.id = p_run;
$$;

create or replace function public.payroll_create(p_month date, p_loc int default null, p_client uuid default null, p_notes text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._pr_month(p_month); r public.payroll_runs; v_id bigint; x uuid; n int := 0;
begin
  perform public._pr_gate();
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._pr_ok(p_loc, true) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.payroll_runs where client_id = p_client; if found then return public._pr_run_json(r.id) || jsonb_build_object('repeat', true); end if; end if;
  perform pg_advisory_xact_lock(hashtextextended('payroll:' || m::text, 0));
  if exists (select 1 from public.payroll_runs where month = m and coalesce(location_id, 0) = coalesce(p_loc, 0) and status <> 'void') then raise exception 'run_exists'; end if;
  if char_length(coalesce(p_notes, '')) > 500 then raise exception 'too_long: notes'; end if;
  insert into public.payroll_runs (client_id, month, location_id, notes, created_by) values (p_client, m, p_loc, nullif(btrim(p_notes), ''), auth.uid()) returning id into v_id;
  for x in select * from public._pr_people(m, p_loc, true) loop
    if exists (select 1 from public.payroll_lines l where l.employee_id = x and l.month = m and l.active) then continue; end if;
    if public._pr_put_line(v_id, x, m) is not null then n := n + 1; end if;
  end loop;
  return public._pr_run_json(v_id) || jsonb_build_object('created_lines', n);
end $$;

-- recompute every line of a draft (after an attendance fix); manual items stay
create or replace function public.payroll_refresh(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; x uuid; n int := 0;
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (r.location_id is not null and public._pr_ok(r.location_id, true))) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  for x in select * from public._pr_people(r.month, r.location_id, true) loop
    if exists (select 1 from public.payroll_lines l where l.employee_id = x and l.month = r.month and l.active and l.run_id <> r.id) then continue; end if;
    if public._pr_put_line(r.id, x, r.month) is not null then n := n + 1; end if;
  end loop;
  return public._pr_run_json(r.id) || jsonb_build_object('refreshed_lines', n);
end $$;

-- draft line: add a bonus, a deduction or a (+/-) adjustment, each with a reason; or remove one manual item (p_remove = index in its list)
create or replace function public.payroll_line_adjust(p_line bigint, p_kind text, p_name text, p_amount numeric, p_reason text, p_remove int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.payroll_lines; r public.payroll_runs; item jsonb; col text; arr jsonb; tot jsonb; j jsonb;
begin
  perform public._pr_gate();
  select * into l from public.payroll_lines where id = p_line for update;
  if not found or not l.active then raise exception 'not_found'; end if;
  select * into r from public.payroll_runs where id = l.run_id;
  if not (public.is_owner() or public._pr_ok(l.location_id, true)) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  if p_kind not in ('bonus', 'deduction', 'adjust') then raise exception 'bad_kind'; end if;
  col := case p_kind when 'bonus' then 'bonus' when 'deduction' then 'other_deductions' else 'adjustments' end;
  arr := to_jsonb(l) -> col;
  if p_remove is not null then
    if p_remove < 0 or p_remove >= jsonb_array_length(arr) or coalesce((arr -> p_remove ->> 'auto')::boolean, false) then raise exception 'bad_item'; end if;
    arr := arr - p_remove;
  else
    if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
    if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
    if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000000000 or (p_kind <> 'adjust' and p_amount < 0) then raise exception 'bad_amount'; end if;
    item := jsonb_build_object('name', btrim(p_name), 'amount', round(p_amount, 2), 'reason', btrim(p_reason), 'by', auth.uid(), 'at', now());
    arr := arr || jsonb_build_array(item);
  end if;
  j := to_jsonb(l) || jsonb_build_object(col, arr);
  tot := public._pr_totals(j);
  update public.payroll_lines set bonus = j -> 'bonus', other_deductions = j -> 'other_deductions', adjustments = j -> 'adjustments', gross = (tot ->> 'gross')::numeric,
         deductions = (tot ->> 'deductions')::numeric, round_adj = (tot ->> 'round_adj')::numeric, net = (tot ->> 'net')::numeric, updated_at = now(),
         warnings = case when (tot ->> 'net')::numeric < 0 then (select coalesce(jsonb_agg(w), '[]') from jsonb_array_elements(warnings) w where w <> '"negative_net"') || '["negative_net"]'
                         else (select coalesce(jsonb_agg(w), '[]') from jsonb_array_elements(warnings) w where w <> '"negative_net"') end
   where id = p_line;
  return (select to_jsonb(x) from public.payroll_lines x where x.id = p_line);
end $$;

-- owner approves: the month is locked for these people; advance recoveries are booked
create or replace function public.payroll_approve(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; l record; a jsonb;
begin
  perform public._pr_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status in ('approved', 'paid') then return public._pr_run_json(r.id) || jsonb_build_object('repeat', true); end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id and active) then raise exception 'run_empty'; end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and active and net < 0) then raise exception 'negative_net'; end if;
  for l in select * from public.payroll_lines where run_id = r.id and active loop
    for a in select * from jsonb_array_elements(l.advances) loop
      if (a ->> 'amount')::numeric > public._adv_outstanding((a ->> 'advance_id')::bigint) then raise exception 'advance_changed_refresh'; end if;
      insert into public.employee_advance_recoveries (advance_id, run_id, line_id, amount) values ((a ->> 'advance_id')::bigint, r.id, l.id, (a ->> 'amount')::numeric);
    end loop;
  end loop;
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = r.id;
  update public.payroll_lines set payment_status = case when net = 0 then 'paid' else 'unpaid' end where run_id = r.id and active;
  return public._pr_run_json(r.id);
end $$;

-- record salary payments (all unpaid lines, or the given lines; one line may be paid in part with p_amount)
create or replace function public.payroll_pay(p_run bigint, p_lines bigint[], p_mode text, p_date date, p_ref text default null, p_note text default null, p_client uuid default null, p_amount numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; l public.payroll_lines; v_due numeric; v_amt numeric; n int := 0; tot numeric := 0; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status not in ('approved', 'paid') then raise exception 'run_not_approved'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and exists (select 1 from public.payroll_payments where client_batch = p_client) then
    return public._pr_run_json(r.id) || jsonb_build_object('repeat', true);
  end if;
  if p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if p_date is null or p_date > v_today or p_date < r.month then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_ref, '')) > 80 or char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  if p_amount is not null and (coalesce(cardinality(p_lines), 0) <> 1 or not (p_amount > 0 and p_amount <= 1000000000000)) then raise exception 'bad_amount'; end if;
  perform public.lock_check(p_date);
  for l in select * from public.payroll_lines where run_id = r.id and active and (p_lines is null or id = any (p_lines)) order by id for update loop
    if not (public.is_owner() or public._pr_ok(l.location_id, true)) then raise exception 'not allowed'; end if;
    v_due := l.net - l.paid_amount;
    if v_due <= 0 then continue; end if;
    v_amt := coalesce(round(p_amount, 2), v_due);
    if v_amt > v_due then raise exception 'more_than_due'; end if;
    insert into public.payroll_payments (client_batch, run_id, line_id, employee_id, location_id, pay_date, mode, amount, ref, note, created_by)
      values (p_client, r.id, l.id, l.employee_id, l.location_id, p_date, p_mode, v_amt, nullif(btrim(p_ref), ''), nullif(btrim(p_note), ''), auth.uid());
    update public.payroll_lines set paid_amount = paid_amount + v_amt, payment_status = case when paid_amount + v_amt >= net then 'paid' else 'partly' end, updated_at = now() where id = l.id;
    n := n + 1; tot := tot + v_amt;
  end loop;
  if n = 0 then raise exception 'nothing_to_pay'; end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id and active and payment_status <> 'paid') then update public.payroll_runs set status = 'paid', paid_at = now() where id = r.id; end if;
  return public._pr_run_json(r.id) || jsonb_build_object('payments', n, 'amount', tot);
end $$;

create or replace function public.payroll_payment_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.payroll_payments;
begin
  perform public._pr_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into p from public.payroll_payments where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if p.status = 'void' then return jsonb_build_object('id', p_id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  perform public.lock_check(p.pay_date);
  update public.payroll_payments set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  update public.payroll_lines set paid_amount = paid_amount - p.amount, payment_status = case when paid_amount - p.amount <= 0 then 'unpaid' else 'partly' end, updated_at = now() where id = p.line_id;
  update public.payroll_runs set status = 'approved', paid_at = null where id = p.run_id and status = 'paid';
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;

-- void a run: a draft (payroll_manage) or an approved run without payments (owner); recoveries are undone, the month opens again
create or replace function public.payroll_void(p_run bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'status', 'void', 'repeat', true); end if;
  if r.status = 'draft' and not (public.is_owner() or (r.location_id is not null and public._pr_ok(r.location_id, true))) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' and not public.is_owner() then raise exception 'not allowed'; end if;
  if exists (select 1 from public.payroll_payments where run_id = r.id and status = 'done') then raise exception 'run_has_payments'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.employee_advance_recoveries set status = 'void' where run_id = r.id and status = 'active';
  update public.payroll_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = r.id;
  update public.payroll_lines set active = false, updated_at = now() where run_id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

-- final settlement helper (preview only): pay up to the last day + advances still owed
create or replace function public.payroll_settlement_preview(p_emp uuid, p_last_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  if not public._emp_ok(p_emp, array['salary_view', 'payroll_manage']) then raise exception 'not allowed'; end if;
  if p_last_day is null or p_last_day > v_today + 31 or p_last_day < v_today - 400 then raise exception 'bad_date'; end if;
  j := public._payroll_calc(p_emp, date_trunc('month', p_last_day)::date, p_last_day);
  return jsonb_build_object('dry', true, 'line', j, 'already_in_run', exists (select 1 from public.payroll_lines l where l.employee_id = p_emp and l.month = date_trunc('month', p_last_day)::date and l.active),
    'advances_left', coalesce((select sum(public._adv_outstanding(a.id)) from public.employee_advances a where a.employee_id = p_emp and a.status = 'active'), 0) - coalesce((j ->> 'advance_recovery')::numeric, 0));
end $$;

-- ---------- day book: _daybook_lines23 from phase23 re-created with payroll payments and money-moving staff advances (salary-sensitive) ----------
create or replace function public._daybook_lines23(p_locs int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable as $$
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
   where p.status = 'done' and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id));
$$;
revoke all on function public._daybook_lines23(int[], date, date) from public, anon, authenticated;

-- ---------- function grants: the browser calls the listed ones; anon only the device push; helpers closed ----------
do $$
declare p record;
  browser text[] := array['attendance_recompute', 'attendance_mark', 'attendance_approve', 'attendance_ot_approve', 'attendance_board', 'attendance_month', 'shift_save', 'shift_assign',
    'shift_assign_end', 'holiday_save', 'holiday_retire', 'leave_balances', 'leave_request_save', 'leave_decide', 'leave_cancel', 'attendance_import', 'attendance_import_void',
    'attendance_unmapped', 'attendance_map_user', 'attendance_device_register', 'attendance_device_token_reset', 'attendance_device_set_active', 'attendance_app_punch',
    'staff_advance_add', 'staff_advance_void', 'staff_advances_list', 'payroll_bonus_event_save', 'payroll_preview', 'payroll_create', 'payroll_refresh', 'payroll_line_adjust',
    'payroll_approve', 'payroll_pay', 'payroll_payment_void', 'payroll_void', 'payroll_settlement_preview', 'attendance_punch_push', '_att_view', '_att_loc_view', '_pr_ok'];
  helpers text[] := array['_punch_guard42', '_status_guard42', '_run_guard42', '_line_guard42', '_att_gate', '_pr_gate', '_att_rule_off_mask', '_att_is_off', '_att_holiday', '_att_shift_for',
    '_att_locked', '_att_ts', '_att_dir', '_hhmm', '_att_derive', '_att_store', '_leave_days', '_leave_used', '_att_ingest', '_adv_outstanding', '_adv_02_3', '_pr_totals', '_payroll_calc',
    '_pr_people', '_pr_month', '_pr_put_line', '_pr_run_json'];
begin
  for p in select oid::regprocedure as sig, proname from pg_proc where pronamespace = 'public'::regnamespace and (proname = any (browser) or proname = any (helpers)) loop
    execute format('revoke all on function %s from public, anon', p.sig);
    if p.proname = any (helpers) then
      execute format('revoke all on function %s from authenticated', p.sig);
    else
      execute format('grant execute on function %s to authenticated', p.sig);
    end if;
  end loop;
end $$;
-- the device bridge uses the anon key: this one function only
grant execute on function public.attendance_punch_push(text, jsonb) to anon;

-- ---------------------------------------------------------------- phase43.sql
-- ============================================================
-- Phase 43 - Module C: customer registration, customer tiers (Walk-in / Regular / Silver / Gold / Elite / Wholesale / Staff ...),
--            tier discount (pre-approved at the POS), gifts, loyalty points, automatic tier refresh.
-- Run AFTER phase28. Additive + idempotent (paste twice = no error). Nothing is deleted: a tier / rule / customer is retired with an active flag;
-- history and the points ledger are append-only. Every write goes through SECURITY DEFINER functions; the browser only reads (RLS).
--
-- What is NEW here
--   customer_tiers            the tier list (editable by the owner only; code never changes). Seeded with NAMES only: every discount is 0 and every
--                             threshold is blank - the owner decides the policy in #/tiers.
--   customers (+ columns)     tier_id, tier_locked, birthday, anniversary, address, customer_since, source, whatsapp (the old `note` column is the notes).
--   customer_tier_history     append-only: who moved from which tier to which, auto or manual, why.
--   customer_points_ledger    append-only loyalty points (sale / redeem / adjust / expire). Balance = sum(delta).
--   gift_rules, customer_gifts   gifts by tier / occasion; gifts_due(customer) lists what is owed; gift_claim() is idempotent.
--   sale_tier_use             one row per sale that used a pre-approved tier discount (for reports).
--   record_sale2              RE-CREATED from its latest definition (phase8 + the phase22 bos22-late patch). ONLY the marked "bos43" blocks differ.
--   Switches (all default OFF): tier_discount_on, customer_tier_auto_on, customer_tier_allow_downgrade, loyalty_points_on, customer_gifts_on.
-- ============================================================

-- ---------- 1. tiers ----------
create table if not exists public.customer_tiers (
  id bigint generated by default as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 60),
  name_en text not null check (length(btrim(name_en)) between 1 and 60),
  rank int not null default 10 check (rank between 0 and 1000),
  color text not null default '#64748b' check (color ~ '^#[0-9a-fA-F]{6}$'),
  badge text check (badge is null or length(badge) <= 8),
  is_default boolean not null default false,
  discount_percent numeric(5,2) not null default 0 check (discount_percent between 0 and 100),
  discount_cap_amount numeric check (discount_cap_amount is null or (discount_cap_amount >= 0 and discount_cap_amount <= 1e12)),
  credit_limit_default numeric check (credit_limit_default is null or (credit_limit_default >= 0 and credit_limit_default <= 1e12)),
  birthday_gift text check (birthday_gift is null or length(birthday_gift) <= 200),
  perks text check (perks is null or length(perks) <= 500),
  points_multiplier numeric not null default 1 check (points_multiplier >= 0 and points_multiplier <= 100),
  min_lifetime_spend numeric check (min_lifetime_spend is null or (min_lifetime_spend >= 0 and min_lifetime_spend <= 1e12)),
  min_orders int check (min_orders is null or (min_orders >= 0 and min_orders <= 1000000)),
  min_orders_12m int check (min_orders_12m is null or (min_orders_12m >= 0 and min_orders_12m <= 1000000)),
  min_months_active int check (min_months_active is null or (min_months_active >= 0 and min_months_active <= 1200)),
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists customer_tiers_one_default on public.customer_tiers (is_default) where is_default;

create or replace function public._tier_guard43() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.code is distinct from old.code then raise exception 'tier_code_fixed'; end if;
  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  if new.is_default and not new.active then raise exception 'default_tier_active'; end if;
  return new;
end $$;
drop trigger if exists customer_tiers_guard on public.customer_tiers;
create trigger customer_tiers_guard before insert or update on public.customer_tiers for each row execute function public._tier_guard43();
drop trigger if exists audit_customer_tiers on public.customer_tiers;
create trigger audit_customer_tiers after insert or update on public.customer_tiers for each row execute function public.log_change('id');
drop trigger if exists customer_tiers_no_delete on public.customer_tiers;
create trigger customer_tiers_no_delete before delete on public.customer_tiers for each row execute function public.no_hard_delete();

-- seed: NAMES ONLY (discount 0, no thresholds). The owner fills the policy in #/tiers.
insert into public.customer_tiers (code, name_bn, name_en, rank, color, badge, is_default) values
  ('walkin',    'ওয়াক-ইন',          'Walk-in',     10, '#64748b', '🚶', true),
  ('regular',   'নিয়মিত',           'Regular',     20, '#0ea5e9', '🙂', false),
  ('silver',    'সিলভার',           'Silver',      30, '#94a3b8', '🥈', false),
  ('gold',      'গোল্ড',            'Gold',        40, '#d97706', '🥇', false),
  ('elite',     'এলিট / ভিআইপি',    'Elite / VIP', 50, '#7c3aed', '👑', false),
  ('wholesale', 'পাইকারি / পার্টি', 'Wholesale / Party', 60, '#047857', '📦', false),
  ('staff',     'স্টাফ',            'Staff',       70, '#be185d', '🏷️', false)
on conflict (code) do nothing;

alter table public.customer_tiers enable row level security;
drop policy if exists customer_tiers_read on public.customer_tiers;
create policy customer_tiers_read on public.customer_tiers for select to authenticated using (public.is_active());
revoke all on public.customer_tiers from public, anon, authenticated;
grant select on public.customer_tiers to authenticated;

-- ---------- 2. customers: new columns ----------
alter table public.customers add column if not exists tier_id bigint references public.customer_tiers(id);
alter table public.customers add column if not exists tier_locked boolean not null default false;
alter table public.customers add column if not exists birthday date;
alter table public.customers add column if not exists anniversary date;
alter table public.customers add column if not exists address text;
alter table public.customers add column if not exists customer_since date;
alter table public.customers add column if not exists source text;
alter table public.customers add column if not exists whatsapp text;
create index if not exists customers_tier on public.customers (tier_id);
-- (the existing `note` column is the customer's notes)

-- a new customer (from the POS, an import or the new form) gets the default tier, a start date and the tier's default credit limit
create or replace function public._customer_new43() returns trigger language plpgsql security definer set search_path = public as $$
declare t public.customer_tiers;
begin
  if new.tier_id is null then select * into t from public.customer_tiers where is_default and active limit 1; else select * into t from public.customer_tiers where id = new.tier_id; end if;
  if found then
    new.tier_id := t.id;
    if new.credit_limit is null and t.credit_limit_default is not null then new.credit_limit := t.credit_limit_default; end if;
  end if;
  if new.customer_since is null then new.customer_since := (coalesce(new.created_at, now()) at time zone 'Asia/Dhaka')::date; end if;
  return new;
end $$;
revoke all on function public._customer_new43() from public, anon, authenticated;
drop trigger if exists customers_new43 on public.customers;
create trigger customers_new43 before insert on public.customers for each row execute function public._customer_new43();

-- existing customers: default tier + start date (no history row: this is the starting point)
update public.customers set tier_id = (select id from public.customer_tiers where is_default limit 1) where tier_id is null and exists (select 1 from public.customer_tiers where is_default);
update public.customers set customer_since = (created_at at time zone 'Asia/Dhaka')::date where customer_since is null;

-- ---------- 3. history + points (append-only) ----------
create or replace function public._append_only43() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
revoke all on function public._append_only43() from public, anon, authenticated;

create table if not exists public.customer_tier_history (
  id bigint generated by default as identity primary key,
  customer_id uuid not null references public.customers(id),
  from_tier bigint references public.customer_tiers(id),
  to_tier bigint not null references public.customer_tiers(id),
  reason text not null check (reason in ('auto', 'manual')),
  note text check (note is null or length(note) <= 300),
  by_user uuid,
  by_staff text,
  at timestamptz not null default now()
);
create index if not exists customer_tier_history_cust on public.customer_tier_history (customer_id, at desc);
drop trigger if exists customer_tier_history_ro on public.customer_tier_history;
create trigger customer_tier_history_ro before update or delete on public.customer_tier_history for each row execute function public._append_only43();
drop trigger if exists customer_tier_history_ro_t on public.customer_tier_history;
create trigger customer_tier_history_ro_t before truncate on public.customer_tier_history for each statement execute function public._append_only43();

create table if not exists public.customer_points_ledger (
  id bigint generated by default as identity primary key,
  customer_id uuid not null references public.customers(id),
  delta int not null check (delta <> 0 and abs(delta) <= 10000000),
  reason text not null check (reason in ('sale', 'redeem', 'adjust', 'expire')),
  sale_id uuid references public.sales(id),
  client_id uuid,
  note text check (note is null or length(note) <= 300),
  by_user uuid,
  by_staff text,
  at timestamptz not null default now()
);
create index if not exists customer_points_cust on public.customer_points_ledger (customer_id, at desc);
create unique index if not exists customer_points_one_sale on public.customer_points_ledger (sale_id) where reason = 'sale';
create unique index if not exists customer_points_one_void on public.customer_points_ledger (sale_id) where reason = 'adjust' and sale_id is not null;
create unique index if not exists customer_points_client on public.customer_points_ledger (client_id) where client_id is not null;
drop trigger if exists customer_points_ro on public.customer_points_ledger;
create trigger customer_points_ro before update or delete on public.customer_points_ledger for each row execute function public._append_only43();
drop trigger if exists customer_points_ro_t on public.customer_points_ledger;
create trigger customer_points_ro_t before truncate on public.customer_points_ledger for each statement execute function public._append_only43();

-- ---------- 4. gifts ----------
create table if not exists public.gift_rules (
  id bigint generated by default as identity primary key,
  tier_id bigint references public.customer_tiers(id),           -- null = every tier
  trigger text not null check (trigger in ('birthday', 'anniversary', 'first_purchase', 'every_n_purchases', 'spend_threshold', 'manual')),
  threshold numeric check (threshold is null or (threshold > 0 and threshold <= 1e12)),
  gift_text_bn text check (gift_text_bn is null or length(gift_text_bn) <= 200),
  gift_text_en text check (gift_text_en is null or length(gift_text_en) <= 200),
  value_taka numeric check (value_taka is null or (value_taka >= 0 and value_taka <= 1e12)),
  valid_days int check (valid_days is null or valid_days between 1 and 3650),
  active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  check (coalesce(gift_text_bn, gift_text_en) is not null),
  check (trigger not in ('every_n_purchases', 'spend_threshold') or threshold is not null)
);
drop trigger if exists audit_gift_rules on public.gift_rules;
create trigger audit_gift_rules after insert or update on public.gift_rules for each row execute function public.log_change('id');
drop trigger if exists gift_rules_no_delete on public.gift_rules;
create trigger gift_rules_no_delete before delete on public.gift_rules for each row execute function public.no_hard_delete();

create table if not exists public.customer_gifts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  rule_id bigint references public.gift_rules(id),
  occasion text not null,                                         -- e.g. birthday:2026, nth:3, spend:50000, first, manual:<uuid>
  gift_text_bn text,
  gift_text_en text,
  value_taka numeric,
  issued_at timestamptz not null default now(),
  issued_by uuid,
  valid_until date,
  claimed_at timestamptz,
  claimed_by uuid,
  claimed_staff text,
  claimed_sale_id uuid references public.sales(id),
  note text check (note is null or length(note) <= 300),
  unique (customer_id, rule_id, occasion)
);
create unique index if not exists customer_gifts_manual on public.customer_gifts (customer_id, occasion) where rule_id is null;
create index if not exists customer_gifts_cust on public.customer_gifts (customer_id, issued_at desc);
drop trigger if exists audit_customer_gifts on public.customer_gifts;
create trigger audit_customer_gifts after insert or update on public.customer_gifts for each row execute function public.log_change('id');
drop trigger if exists customer_gifts_no_delete on public.customer_gifts;
create trigger customer_gifts_no_delete before delete on public.customer_gifts for each row execute function public.no_hard_delete();

-- ---------- 5. sale_tier_use ----------
create table if not exists public.sale_tier_use (
  sale_id uuid primary key references public.sales(id),
  customer_id uuid references public.customers(id),
  tier_id bigint references public.customer_tiers(id),
  tier_percent numeric not null,
  tier_discount numeric not null,
  at timestamptz not null default now()
);
drop trigger if exists sale_tier_use_ro on public.sale_tier_use;
create trigger sale_tier_use_ro before update or delete on public.sale_tier_use for each row execute function public._append_only43();

-- RLS: read for POS users; no direct writes
alter table public.customer_tier_history enable row level security;
alter table public.customer_points_ledger enable row level security;
alter table public.gift_rules enable row level security;
alter table public.customer_gifts enable row level security;
alter table public.sale_tier_use enable row level security;
drop policy if exists cth_read on public.customer_tier_history;
create policy cth_read on public.customer_tier_history for select to authenticated using (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
drop policy if exists cpl_read on public.customer_points_ledger;
create policy cpl_read on public.customer_points_ledger for select to authenticated using (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
drop policy if exists gift_rules_read on public.gift_rules;
create policy gift_rules_read on public.gift_rules for select to authenticated using (public.is_active());
drop policy if exists cg_read on public.customer_gifts;
create policy cg_read on public.customer_gifts for select to authenticated using (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
drop policy if exists stu_read on public.sale_tier_use;
create policy stu_read on public.sale_tier_use for select to authenticated using (exists (select 1 from public.sales s where s.id = sale_id and public.can_loc(s.location_id)));
revoke all on public.customer_tier_history, public.customer_points_ledger, public.gift_rules, public.customer_gifts, public.sale_tier_use from public, anon, authenticated;
grant select on public.customer_tier_history, public.customer_points_ledger, public.gift_rules, public.customer_gifts, public.sale_tier_use to authenticated;

-- ---------- 6. switches and grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('tier_discount_on', 'customers', 'switch', 'false', null, null, null, null, 'গ্রাহকের স্তরের ডিসকাউন্ট POS-এ আগে-থেকে-অনুমোদিত', 'Customer tier এর discount POS-এ pre-approved', 'The customer tier discount is pre-approved at the POS',
  'চালু করলে স্তরের শতাংশ পর্যন্ত ডিসকাউন্টে ম্যানেজারের অনুমোদন লাগে না; তার উপরের অংশে আগের নিয়মই চলে।', 'On = a discount up to the tier percent needs no manager approval; anything above it follows the normal rule.', 430),
 ('customer_tier_auto_on', 'customers', 'switch', 'false', null, null, null, null, 'গ্রাহকের স্তর নিজে থেকে বাড়ানো (মোট কেনা/অর্ডার দেখে)', 'Customer tier নিজে থেকে upgrade (spend/order দেখে)', 'Move customers up a tier automatically (by spend / orders)',
  'বন্ধ থাকলে স্তর শুধু আপনি হাতে বদলান। চালানোর আগে "পরীক্ষা" দেখা যায়; তালা দেওয়া গ্রাহক বদলায় না।', 'Off = tiers change by hand only. A check (dry run) shows the changes first; locked customers never move.', 431),
 ('customer_tier_allow_downgrade', 'customers', 'switch', 'false', null, null, null, null, 'স্বয়ংক্রিয় রিফ্রেশে স্তর নামানোও চলবে', 'Auto refresh-এ tier নামানোও চলবে', 'The automatic refresh may also move a customer down',
  'বন্ধ থাকলে স্বয়ংক্রিয় রিফ্রেশ কখনও স্তর নামায় না।', 'Off = the automatic refresh never lowers a tier.', 432),
 ('loyalty_points_on', 'customers', 'switch', 'false', null, null, null, null, 'লয়্যালটি পয়েন্ট চালু', 'Loyalty points চালু', 'Loyalty points on',
  'চালু হলে প্রতিটি বিক্রিতে গ্রাহক পয়েন্ট পান (ধাপ: প্রতি ১০০ টাকায় কত পয়েন্ট)।', 'On = every sale with a customer earns points (see points per 100 taka).', 433),
 ('points_per_100_taka', 'customers', 'number', '1', 'pts', null, 0, 1000, 'প্রতি ১০০ টাকার বিক্রিতে পয়েন্ট', 'প্রতি 100 টাকায় points', 'Points per 100 taka of sale', 'আংশিক পয়েন্ট ধরা হয় না (নিচের পূর্ণ সংখ্যা)। স্তরের গুণক এর সাথে গুণ হয়।', 'Whole points only (rounded down). Multiplied by the tier multiplier.', 434),
 ('point_value_taka', 'customers', 'number', '1', '৳', null, 0, 100000, 'প্রতি পয়েন্টের মূল্য (টাকা)', 'প্রতি point এর value (টাকা)', 'Value of one point (taka)', 'পয়েন্ট ভাঙালে এই দামে টাকার সমান ধরা হয়।', 'Redeeming counts each point at this value.', 435),
 ('redeem_min_points', 'customers', 'number', '100', 'pts', null, 0, 10000000, 'কমপক্ষে কত পয়েন্ট জমলে ভাঙানো যাবে', 'কমপক্ষে কত points হলে redeem', 'Minimum points to redeem', null, null, 436),
 ('customer_gifts_on', 'customers', 'switch', 'false', null, null, null, null, 'গ্রাহকের উপহার চালু', 'Customer gift চালু', 'Customer gifts on', 'চালু হলে জন্মদিন/বার্ষিকী ইত্যাদির উপহার POS-এ মনে করিয়ে দেওয়া হয়।', 'On = birthday / anniversary etc. gifts are shown as a reminder at the POS.', 437),
 ('gift_window_days', 'customers', 'number', '7', 'days', null, 0, 60, 'জন্মদিন/বার্ষিকীর কত দিন আগে-পরে উপহার দেখাবে', 'Birthday/anniversary এর কত দিন আগে-পরে gift দেখাবে', 'Days before / after a birthday or anniversary a gift shows', null, null, 438),
 ('gift_valid_days', 'customers', 'number', '30', 'days', null, 1, 3650, 'উপহার কত দিন বৈধ', 'Gift কত দিন valid', 'How many days a gift stays valid', null, null, 439)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'customer_manage', 'master', 71, 'গ্রাহকের স্তর, বাকির সীমা, উপহার ও পয়েন্ট বদলানো', 'Customer tier, credit limit, gift ও points বদলানো', 'Change customer tier, credit limit, gifts and points', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'customer_manage');

-- ---------- 7. helpers ----------
create or replace function public._n43(p jsonb, k text, p_min numeric default null, p_max numeric default null) returns numeric
language plpgsql immutable set search_path = public as $$
declare v text := nullif(btrim(p ->> k), ''); n numeric;
begin
  if v is null then return null; end if;
  begin n := v::numeric; exception when others then raise exception 'bad_number'; end;
  if n = 'NaN'::numeric or abs(n) > 1e12 then raise exception 'bad_number'; end if;
  if (p_min is not null and n < p_min) or (p_max is not null and n > p_max) then raise exception 'bad_number'; end if;
  return n;
end $$;
create or replace function public._d43(p jsonb, k text) returns date
language plpgsql immutable set search_path = public as $$
declare v text := nullif(btrim(p ->> k), ''); d date;
begin
  if v is null then return null; end if;
  begin d := v::date; exception when others then raise exception 'bad_date'; end;
  if d < date '1900-01-01' or d > date '2100-01-01' then raise exception 'bad_date'; end if;
  return d;
end $$;
create or replace function public._today43() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._cust_pos43() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
$$;
create or replace function public._cust_mgr43() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage'));
$$;

-- lifetime numbers of one customer: net spend (done sales minus done returns), orders, orders in the last 12 months, first / last sale.
-- p_scoped = true: only the locations the caller may see (screens); false: everything (tier refresh, gifts - decided by the server alone).
create or replace function public._cust_stats43(p_customer uuid, p_scoped boolean default false)
returns table (spend numeric, orders int, orders_12m int, first_sale date, last_sale date)
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not p_scoped or public.can_loc(s.location_id))), 0)
       - coalesce((select sum(r.amount) from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and (not p_scoped or public.can_loc(s.location_id))), 0),
         (select count(*)::int from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not p_scoped or public.can_loc(s.location_id))),
         (select count(*)::int from public.sales s where s.customer_id = p_customer and s.status = 'done' and s.sale_date > public._today43() - 365 and (not p_scoped or public.can_loc(s.location_id))),
         (select min(s.sale_date) from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not p_scoped or public.can_loc(s.location_id))),
         (select max(s.sale_date) from public.sales s where s.customer_id = p_customer and s.status = 'done' and (not p_scoped or public.can_loc(s.location_id)));
$$;
revoke all on function public._n43(jsonb, text, numeric, numeric), public._d43(jsonb, text), public._today43(), public._cust_pos43(), public._cust_mgr43(), public._cust_stats43(uuid, boolean) from public, anon, authenticated;

-- ---------- 8. record_sale2: the tier discount is pre-approved ----------
-- RE-CREATED from the live definition (phase8 + the phase22 'bos22-late' patch). The ONLY differences are the lines marked "bos43":
--   (1) four variables, (2) bos.tier_use reset at the start, (3) the tier part of the discount is worked out before the approval check,
--   (4) the approval check and the "over the limit" exceptions look at the part of the discount ABOVE the tier part (with the switch off or no tier this part is the whole discount = unchanged),
--   (5) bos.tier_use is set just before the sale insert so the AFTER INSERT trigger can write sale_tier_use.
-- Old calls keep working (same signature, same result).
create or replace function public.record_sale2(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb,
  p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null,
  p_discount_kind text default null, p_discount_input numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; dkind text; dinput numeric; credit_over boolean := false; em text; ov_ok boolean;
  tier_id43 bigint; tier_pct43 numeric; tier_cap43 numeric; tier_amt43 numeric := 0;   -- bos43
begin
  perform set_config('bos.em_used', '', true);
  perform set_config('bos.tier_use', '', true);   -- bos43
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
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
      where cu.mobile = public.norm_mobile(p_customer_mobile) and cu.active and t.active and t.discount_percent > 0;
    if found then tier_amt43 := least(disc, round(sub * tier_pct43 / 100, 2), coalesce(tier_cap43, disc)); end if;
  end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > tier_amt43 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
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
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
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
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
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
end $$;

-- ---------- 9. sale triggers (separate from record_sale2): tier-discount record + loyalty points ----------
-- The tier-discount trigger only copies what record_sale2 decided (transaction setting bos.tier_use = tier|percent|amount).
create or replace function public._sale_tier_use43() returns trigger language plpgsql security definer set search_path = public as $$
declare v text := nullif(current_setting('bos.tier_use', true), ''); a text[];
begin
  if v is null or new.customer_id is null then return new; end if;
  a := string_to_array(v, '|');
  if array_length(a, 1) = 3 then
    insert into public.sale_tier_use (sale_id, customer_id, tier_id, tier_percent, tier_discount) values (new.id, new.customer_id, a[1]::bigint, a[2]::numeric, a[3]::numeric)
      on conflict (sale_id) do nothing;
  end if;
  return new;
end $$;
revoke all on function public._sale_tier_use43() from public, anon, authenticated;
drop trigger if exists sales_tier_use43 on public.sales;
create trigger sales_tier_use43 after insert on public.sales for each row execute function public._sale_tier_use43();

-- points: floor(total / 100 x points_per_100_taka x tier multiplier). One 'sale' row per sale (unique index), nothing when the switch is off.
create or replace function public.loyalty_award(p_sale uuid) returns int
language plpgsql security definer set search_path = public as $$
declare s public.sales; c public.customers; t public.customer_tiers; per numeric; pts int;
begin
  if not public.rule_on('loyalty_points_on') then return 0; end if;
  select * into s from public.sales where id = p_sale;
  if not found or s.customer_id is null or s.status <> 'done' then return 0; end if;
  select * into c from public.customers where id = s.customer_id;
  select * into t from public.customer_tiers where id = c.tier_id;
  per := coalesce(public.rule_num('points_per_100_taka'), 0);
  pts := floor(s.total * per * coalesce(t.points_multiplier, 1) / 100)::int;
  if pts <= 0 then return 0; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, note, by_user, by_staff)
    values (s.customer_id, pts, 'sale', s.id, 'receipt ' || s.receipt, s.created_by, s.created_staff) on conflict do nothing;
  return pts;
end $$;
revoke all on function public.loyalty_award(uuid) from public, anon, authenticated;

create or replace function public._sale_loyalty43() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.loyalty_award(new.id);
  exception when others then
    raise warning 'loyalty_award failed for sale %: %', new.id, sqlerrm;      -- points must never stop a sale
  end;
  return new;
end $$;
revoke all on function public._sale_loyalty43() from public, anon, authenticated;
drop trigger if exists sales_loyalty43 on public.sales;
create trigger sales_loyalty43 after insert on public.sales for each row execute function public._sale_loyalty43();

-- a voided sale takes its points back (once)
create or replace function public._sale_loyalty_void43() returns trigger language plpgsql security definer set search_path = public as $$
declare e public.customer_points_ledger;
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    select * into e from public.customer_points_ledger where sale_id = new.id and reason = 'sale';
    if found then
      insert into public.customer_points_ledger (customer_id, delta, reason, sale_id, note, by_user)
        values (e.customer_id, -e.delta, 'adjust', new.id, 'void receipt ' || new.receipt, auth.uid()) on conflict do nothing;
    end if;
  end if;
  return new;
end $$;
revoke all on function public._sale_loyalty_void43() from public, anon, authenticated;
drop trigger if exists sales_loyalty_void43 on public.sales;
create trigger sales_loyalty_void43 after update of status on public.sales for each row execute function public._sale_loyalty_void43();

-- ---------- 10. tiers: owner edits ----------
-- p keys: code (new only), name_bn, name_en, rank, color, badge, is_default, discount_percent, discount_cap_amount, credit_limit_default, birthday_gift, perks, points_multiplier,
--         min_lifetime_spend, min_orders, min_orders_12m, min_months_active, active. A key that is missing is not changed; an empty value clears an optional field.
create or replace function public.tier_save(p_id bigint, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.customer_tiers; code_ text; nbn text; nen text; mx int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is null then
    code_ := lower(btrim(coalesce(p ->> 'code', '')));
    if code_ !~ '^[a-z0-9_]{2,30}$' then raise exception 'bad_code'; end if;
    nbn := left(btrim(coalesce(p ->> 'name_bn', '')), 60); nen := left(btrim(coalesce(p ->> 'name_en', '')), 60);
    if nbn = '' and nen = '' then raise exception 'name_required'; end if;
    select coalesce(max(rank), 0) + 10 into mx from public.customer_tiers;
    insert into public.customer_tiers (code, name_bn, name_en, rank, created_by) values (code_, coalesce(nullif(nbn, ''), nen), coalesce(nullif(nen, ''), nbn), least(mx, 1000), auth.uid())
      on conflict (code) do nothing returning * into t;
    if not found then raise exception 'code_exists'; end if;
    p_id := t.id;
  else
    select * into t from public.customer_tiers where id = p_id for update;
    if not found then raise exception 'tier_not_found'; end if;
  end if;
  if p ? 'name_bn' and nullif(btrim(p ->> 'name_bn'), '') is not null then update public.customer_tiers set name_bn = left(btrim(p ->> 'name_bn'), 60) where id = p_id; end if;
  if p ? 'name_en' and nullif(btrim(p ->> 'name_en'), '') is not null then update public.customer_tiers set name_en = left(btrim(p ->> 'name_en'), 60) where id = p_id; end if;
  if p ? 'rank' then update public.customer_tiers set rank = coalesce(public._n43(p, 'rank', 0, 1000), rank)::int where id = p_id; end if;
  if p ? 'color' then
    if coalesce(p ->> 'color', '') !~ '^#[0-9a-fA-F]{6}$' then raise exception 'bad_color'; end if;
    update public.customer_tiers set color = p ->> 'color' where id = p_id;
  end if;
  if p ? 'badge' then update public.customer_tiers set badge = left(nullif(btrim(p ->> 'badge'), ''), 8) where id = p_id; end if;
  if p ? 'discount_percent' then update public.customer_tiers set discount_percent = round(coalesce(public._n43(p, 'discount_percent', 0, 100), 0), 2) where id = p_id; end if;
  if p ? 'discount_cap_amount' then update public.customer_tiers set discount_cap_amount = public._n43(p, 'discount_cap_amount', 0) where id = p_id; end if;
  if p ? 'credit_limit_default' then update public.customer_tiers set credit_limit_default = public._n43(p, 'credit_limit_default', 0) where id = p_id; end if;
  if p ? 'birthday_gift' then update public.customer_tiers set birthday_gift = left(nullif(btrim(p ->> 'birthday_gift'), ''), 200) where id = p_id; end if;
  if p ? 'perks' then update public.customer_tiers set perks = left(nullif(btrim(p ->> 'perks'), ''), 500) where id = p_id; end if;
  if p ? 'points_multiplier' then update public.customer_tiers set points_multiplier = coalesce(public._n43(p, 'points_multiplier', 0, 100), 1) where id = p_id; end if;
  if p ? 'min_lifetime_spend' then update public.customer_tiers set min_lifetime_spend = public._n43(p, 'min_lifetime_spend', 0) where id = p_id; end if;
  if p ? 'min_orders' then update public.customer_tiers set min_orders = floor(public._n43(p, 'min_orders', 0, 1000000))::int where id = p_id; end if;
  if p ? 'min_orders_12m' then update public.customer_tiers set min_orders_12m = floor(public._n43(p, 'min_orders_12m', 0, 1000000))::int where id = p_id; end if;
  if p ? 'min_months_active' then update public.customer_tiers set min_months_active = floor(public._n43(p, 'min_months_active', 0, 1200))::int where id = p_id; end if;
  if p ? 'is_default' and (p ->> 'is_default')::boolean is true then
    if not (select active from public.customer_tiers where id = p_id) then raise exception 'default_tier_active'; end if;
    update public.customer_tiers set is_default = false where is_default and id <> p_id;
    update public.customer_tiers set is_default = true where id = p_id;
  end if;
  if p ? 'active' then
    if (p ->> 'active')::boolean is not true and (select is_default from public.customer_tiers where id = p_id) then raise exception 'default_tier_active'; end if;
    update public.customer_tiers set active = coalesce((p ->> 'active')::boolean, active) where id = p_id;
  end if;
  return jsonb_build_object('id', p_id);
end $$;

-- new order of the tiers: p_ids from the lowest to the highest
create or replace function public.tier_reorder(p_ids bigint[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_ids is null or array_length(p_ids, 1) is null or array_length(p_ids, 1) > 200 then raise exception 'bad_value'; end if;
  if (select count(distinct x) from unnest(p_ids) x) <> array_length(p_ids, 1) or exists (select 1 from unnest(p_ids) x where not exists (select 1 from public.customer_tiers where id = x)) then raise exception 'bad_value'; end if;
  for i in 1 .. array_length(p_ids, 1) loop update public.customer_tiers set rank = least(i * 10, 1000) where id = p_ids[i]; end loop;
  return jsonb_build_object('count', array_length(p_ids, 1));
end $$;

-- gift rules (owner)
create or replace function public.gift_rule_save(p_id bigint, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g public.gift_rules; trg text; tid bigint; th numeric; v numeric; vd numeric; bn text; en text; act boolean;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if p_id is not null then select * into g from public.gift_rules where id = p_id for update; if not found then raise exception 'rule_not_found'; end if; end if;
  trg := coalesce(nullif(btrim(p ->> 'trigger'), ''), g.trigger);
  if trg is null or trg not in ('birthday', 'anniversary', 'first_purchase', 'every_n_purchases', 'spend_threshold', 'manual') then raise exception 'bad_trigger'; end if;
  tid := case when p ? 'tier_id' then nullif(p ->> 'tier_id', '')::bigint else g.tier_id end;
  if tid is not null and not exists (select 1 from public.customer_tiers where id = tid) then raise exception 'tier_not_found'; end if;
  th := case when p ? 'threshold' then public._n43(p, 'threshold', 0) else g.threshold end;
  v := case when p ? 'value_taka' then public._n43(p, 'value_taka', 0) else g.value_taka end;
  vd := case when p ? 'valid_days' then public._n43(p, 'valid_days', 1, 3650) else g.valid_days end;
  bn := case when p ? 'gift_text_bn' then left(nullif(btrim(p ->> 'gift_text_bn'), ''), 200) else g.gift_text_bn end;
  en := case when p ? 'gift_text_en' then left(nullif(btrim(p ->> 'gift_text_en'), ''), 200) else g.gift_text_en end;
  act := case when p ? 'active' then coalesce((p ->> 'active')::boolean, true) else coalesce(g.active, true) end;
  if bn is null and en is null then raise exception 'gift_text_required'; end if;
  if trg in ('every_n_purchases', 'spend_threshold') and (th is null or th <= 0) then raise exception 'threshold_required'; end if;
  if trg = 'every_n_purchases' and th <> floor(th) then raise exception 'bad_number'; end if;
  if p_id is null then
    insert into public.gift_rules (tier_id, trigger, threshold, gift_text_bn, gift_text_en, value_taka, valid_days, active, created_by) values (tid, trg, th, bn, en, v, vd::int, act, auth.uid()) returning id into p_id;
  else
    update public.gift_rules set tier_id = tid, trigger = trg, threshold = th, gift_text_bn = bn, gift_text_en = en, value_taka = v, valid_days = vd::int, active = act where id = p_id;
  end if;
  return jsonb_build_object('id', p_id);
end $$;

-- ---------- 11. customers: add / edit / tier / read ----------
-- Create (p_id null): mobile + name. A mobile that already exists is NOT an error: {dup:true, id, name} comes back so the screen can open that customer.
-- p keys: mobile (new only), name, type, birthday, anniversary, address, note, source, whatsapp; manager-only (owner or grant customer_manage): tier_id, tier_locked, credit_limit, active.
create or replace function public.customer_save(p_id uuid, p jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare mob text; c public.customers; nm text; ty text; mgr boolean; tid bigint; wa text; old_tier bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  mgr := public._cust_mgr43();
  if not (mgr or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_value'; end if;
  if (p ? 'birthday' and public._d43(p, 'birthday') > public._today43()) or (p ? 'anniversary' and public._d43(p, 'anniversary') > public._today43()) then raise exception 'bad_date'; end if;
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
end $$;

-- change the tier by hand (history row 'manual'). p_lock: true / false sets tier_locked; null = lock it (a manual choice stops the automatic refresh).
create or replace function public.customer_set_tier(p_customer uuid, p_tier bigint, p_reason text, p_lock boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; t public.customer_tiers; why text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select * into t from public.customer_tiers where id = p_tier;
  if not found or not t.active then raise exception 'tier_not_found'; end if;
  if c.tier_id is distinct from p_tier then
    insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
      values (c.id, c.tier_id, p_tier, 'manual', why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  end if;
  update public.customers set tier_id = p_tier, tier_locked = coalesce(p_lock, true) where id = c.id;
  return jsonb_build_object('id', c.id, 'tier_id', p_tier, 'changed', c.tier_id is distinct from p_tier, 'tier_locked', coalesce(p_lock, true));
end $$;

-- the customer master list (one call). Spend / orders / last sale count only the locations the caller may see.
create or replace function public.customer_directory(p_limit int default 5000)
returns table (id uuid, mobile text, name text, type text, active boolean, tier_id bigint, tier_locked boolean, birthday date, anniversary date, address text, whatsapp text, note text,
               credit_limit numeric, customer_since date, balance numeric, spend numeric, orders int, last_sale date, points int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  return query
    with s as (select x.customer_id cid, sum(x.total) tot, count(*)::int n, max(x.sale_date) last_d from public.sales x
               where x.status = 'done' and x.customer_id is not null and public.can_loc(x.location_id) group by 1),
         r as (select y.customer_id cid, sum(y.amount) amt from public.sale_returns y join public.sales z on z.id = y.sale_id
               where y.status = 'done' and y.customer_id is not null and public.can_loc(z.location_id) group by 1),
         d as (select q.id cid, q.balance bal from public.customer_dues() q),
         p as (select l.customer_id cid, sum(l.delta)::int pts from public.customer_points_ledger l group by 1)
    select c.id, c.mobile, c.name, c.type, c.active, c.tier_id, c.tier_locked, c.birthday, c.anniversary, c.address, c.whatsapp, c.note, c.credit_limit, c.customer_since,
           coalesce(d.bal, 0), coalesce(s.tot, 0) - coalesce(r.amt, 0), coalesce(s.n, 0), s.last_d, coalesce(p.pts, 0)
    from public.customers c left join s on s.cid = c.id left join r on r.cid = c.id left join d on d.cid = c.id left join p on p.cid = c.id
    order by lower(c.name), c.mobile limit least(greatest(coalesce(p_limit, 5000), 1), 20000);
end $$;

-- one customer, everything the profile screen shows
create or replace function public.customer_profile(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; st record; res jsonb;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into st from public._cust_stats43(p_customer, true);
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'mobile', c.mobile, 'name', c.name, 'type', c.type, 'active', c.active, 'tier_id', c.tier_id, 'tier_locked', c.tier_locked, 'birthday', c.birthday,
        'anniversary', c.anniversary, 'address', c.address, 'whatsapp', c.whatsapp, 'note', c.note, 'source', c.source, 'credit_limit', c.credit_limit, 'customer_since', c.customer_since),
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
end $$;

-- POS: tier chip, perks, tier discount, gifts due, points - after the mobile is typed. Shows nothing for an unknown mobile.
create or replace function public.customer_pos_info(p_mobile text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text; c public.customers; t public.customer_tiers; g int := 0;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  m := public.norm_mobile(p_mobile);
  select * into c from public.customers where mobile = m;
  if not found then return jsonb_build_object('found', false, 'mobile', m); end if;
  select * into t from public.customer_tiers where id = c.tier_id;
  if public.rule_on('customer_gifts_on') then select count(*)::int into g from public.gifts_due(c.id); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'name', c.name, 'birthday', c.birthday,
    'tier', case when t.id is null then null else jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'color', t.color, 'badge', t.badge, 'perks', t.perks,
        'discount_percent', t.discount_percent, 'discount_cap_amount', t.discount_cap_amount, 'birthday_gift', t.birthday_gift) end,
    'tier_discount_on', public.rule_on('tier_discount_on') and coalesce(t.discount_percent, 0) > 0 and c.active and coalesce(t.active, false),
    'gifts_due', g,
    'points', case when public.rule_on('loyalty_points_on') then coalesce((select sum(delta) from public.customer_points_ledger where customer_id = c.id), 0) end);
end $$;

-- ---------- 12. points ----------
create or replace function public.customer_points(p_customer uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when public._cust_pos43() then coalesce((select sum(delta) from public.customer_points_ledger where customer_id = p_customer), 0)::int end;
$$;

create or replace function public.customer_points_adjust(p_customer uuid, p_delta int, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare bal int; why text := left(btrim(coalesce(p_note, '')), 300);
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 10000000 then raise exception 'bad_number'; end if;
  if length(why) < 3 then raise exception 'note_required'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and exists (select 1 from public.customer_points_ledger where client_id = p_client) then
    return jsonb_build_object('dup', true, 'balance', (select sum(delta) from public.customer_points_ledger where customer_id = p_customer));
  end if;
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if bal + p_delta < 0 then raise exception 'not_enough_points'; end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, p_delta, 'adjust', p_client, why, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dup', false, 'balance', bal + p_delta);
end $$;

-- spend points: returns the taka value (points x point_value_taka) to give as a discount. PREVIEW first with p_dry (nothing is written).
create or replace function public.customer_points_redeem(p_customer uuid, p_points int, p_note text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  perform 1 from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select coalesce(sum(delta), 0) into bal from public.customer_points_ledger where customer_id = p_customer;
  if p_points > bal then raise exception 'not_enough_points'; end if;
  if coalesce(p_dry, false) then return jsonb_build_object('dry', true, 'points', p_points, 'value_taka', val, 'balance', bal, 'balance_after', bal - p_points); end if;
  insert into public.customer_points_ledger (customer_id, delta, reason, client_id, note, by_user, by_staff)
    values (p_customer, -p_points, 'redeem', p_client, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('dry', false, 'dup', false, 'points', p_points, 'value_taka', val, 'balance', bal - p_points);
end $$;

-- ---------- 13. gifts ----------
-- Everything the customer is owed today: issued-and-unclaimed gifts, plus gifts a rule makes due now that are not issued yet (issued = false, id null).
create or replace function public.gifts_due(p_customer uuid)
returns table (gift_id uuid, rule_id bigint, occasion text, kind text, text_bn text, text_en text, value_taka numeric, valid_until date, issued boolean)
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; st record; r public.gift_rules; today date := public._today43(); win int := coalesce(public.rule_num('gift_window_days'), 7)::int;
        y int; d date; occ text; vd int; k int;
begin
  if not public._cust_pos43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then return; end if;
  select * into c from public.customers where id = p_customer;
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
end $$;

-- hand a gift over (idempotent). Either claim an issued gift by p_gift, or claim a rule-made gift (p_rule + p_occasion: it is issued and claimed in one step).
-- Calling it again returns {dup:true} and changes nothing.
create or replace function public.gift_claim(p_customer uuid, p_gift uuid default null, p_rule bigint default null, p_occasion text default null, p_sale uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g public.customer_gifts; due record; r public.gift_rules; ok boolean := false; sid text;
begin
  if not (public.is_active() and (public.can_do('POS', 'enter') or public._cust_mgr43())) then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  perform 1 from public.customers where id = p_customer for update;
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
end $$;

-- a one-off gift typed by the owner / a manager (not from a rule)
create or replace function public.gift_issue(p_customer uuid, p_text_bn text, p_text_en text, p_value numeric default null, p_valid_until date default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g public.customer_gifts; occ text;
begin
  if not public._cust_mgr43() then raise exception 'not allowed'; end if;
  if not public.rule_on('customer_gifts_on') then raise exception 'gifts_off'; end if;
  if coalesce(nullif(btrim(p_text_bn), ''), nullif(btrim(p_text_en), '')) is null then raise exception 'gift_text_required'; end if;
  if p_value is not null and (p_value = 'NaN'::numeric or p_value < 0 or p_value > 1e12) then raise exception 'bad_number'; end if;
  if p_valid_until is not null and (p_valid_until < public._today43() or p_valid_until > public._today43() + 3650) then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  occ := 'manual:' || coalesce(p_client::text, gen_random_uuid()::text);
  perform 1 from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  select * into g from public.customer_gifts where customer_id = p_customer and rule_id is null and occasion = occ;
  if found then return jsonb_build_object('dup', true, 'id', g.id); end if;
  insert into public.customer_gifts (customer_id, rule_id, occasion, gift_text_bn, gift_text_en, value_taka, issued_by, valid_until, note)
    values (p_customer, null, occ, left(nullif(btrim(p_text_bn), ''), 200), left(nullif(btrim(p_text_en), ''), 200), round(p_value, 2), auth.uid(),
            coalesce(p_valid_until, public._today43() + coalesce(public.rule_num('gift_valid_days')::int, 30)), left(nullif(btrim(p_note), ''), 300)) returning * into g;
  return jsonb_build_object('dup', false, 'id', g.id);
end $$;

-- ---------- 14. automatic tier refresh (owner) ----------
-- A tier qualifies when EVERY threshold it has is met (a tier without any threshold is never given automatically). Highest rank wins. Locked customers are skipped.
-- Up only, unless customer_tier_allow_downgrade is ON. Customers sitting in a manual-only tier (no thresholds, not the default) are left alone.
-- p_dry (default TRUE) writes nothing and returns the list; a real run needs the switch customer_tier_auto_on and writes one history row per move.
create or replace function public.customer_tier_refresh(p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.customers; cur public.customer_tiers; tgt public.customer_tiers; t public.customer_tiers; st record; mths numeric; changes jsonb := '[]'::jsonb; n int := 0; down boolean;
        def public.customer_tiers; dry boolean := coalesce(p_dry, true);
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not dry and not public.rule_on('customer_tier_auto_on') then raise exception 'tier_auto_off'; end if;
  down := public.rule_on('customer_tier_allow_downgrade');
  select * into def from public.customer_tiers where is_default and active limit 1;
  for c in select * from public.customers x where x.active and not x.tier_locked order by x.name, x.id loop
    select * into cur from public.customer_tiers where id = c.tier_id;
    if found and cur.min_lifetime_spend is null and cur.min_orders is null and cur.min_orders_12m is null and cur.min_months_active is null and not cur.is_default then continue; end if;
    select * into st from public._cust_stats43(c.id, false);
    mths := case when coalesce(st.first_sale, c.customer_since) is null then 0 else
              ((public._today43() - coalesce(least(st.first_sale, c.customer_since), st.first_sale, c.customer_since)) / 30.4375) end;
    tgt := null;
    for t in select * from public.customer_tiers x where x.active and (x.min_lifetime_spend is not null or x.min_orders is not null or x.min_orders_12m is not null or x.min_months_active is not null) order by x.rank desc, x.id desc loop
      if (t.min_lifetime_spend is null or st.spend >= t.min_lifetime_spend) and (t.min_orders is null or st.orders >= t.min_orders)
         and (t.min_orders_12m is null or st.orders_12m >= t.min_orders_12m) and (t.min_months_active is null or mths >= t.min_months_active) then tgt := t; exit; end if;
    end loop;
    if tgt.id is null then
      if not down or def.id is null or c.tier_id = def.id or (cur.id is not null and cur.rank <= def.rank) then continue; end if;
      tgt := def;                                                    -- nothing qualifies any more and downgrades are allowed: back to the default tier
    end if;
    if tgt.id = c.tier_id then continue; end if;
    if cur.id is not null and tgt.rank < cur.rank and not down then continue; end if;
    if cur.id is not null and tgt.rank = cur.rank then continue; end if;
    n := n + 1;
    if jsonb_array_length(changes) < 2000 then
      changes := changes || jsonb_build_object('customer_id', c.id, 'name', c.name, 'mobile', c.mobile, 'from_id', cur.id, 'from_code', cur.code, 'to_id', tgt.id, 'to_code', tgt.code,
        'spend', st.spend, 'orders', st.orders, 'orders_12m', st.orders_12m, 'direction', case when cur.id is null or tgt.rank > cur.rank then 'up' else 'down' end);
    end if;
    if not dry then
      insert into public.customer_tier_history (customer_id, from_tier, to_tier, reason, note, by_user, by_staff)
        values (c.id, c.tier_id, tgt.id, 'auto', 'spend ' || st.spend || ', orders ' || st.orders, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
      update public.customers set tier_id = tgt.id where id = c.id;
    end if;
  end loop;
  return jsonb_build_object('dry', dry, 'count', n, 'changes', changes);
end $$;

-- ---------- 15. report: tier usage ----------
create or replace function public.tier_usage_report(p_from date, p_to date)
returns table (tier_id bigint, code text, name_bn text, name_en text, sales int, revenue numeric, tier_discount numeric, tier_sales int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
    select t.id, t.code, t.name_bn, t.name_en, count(s.id)::int, coalesce(sum(s.total), 0), coalesce(sum(u.tier_discount), 0), count(u.sale_id)::int
    from public.customer_tiers t
    join public.customers c on c.tier_id = t.id
    join public.sales s on s.customer_id = c.id and s.status = 'done' and s.sale_date between p_from and p_to and public.can_loc(s.location_id)
    left join public.sale_tier_use u on u.sale_id = s.id
    group by t.id, t.code, t.name_bn, t.name_en, t.rank order by t.rank;
end $$;

-- ---------- 16. privileges ----------
revoke all on function public.tier_save(bigint, jsonb, uuid), public.tier_reorder(bigint[]), public.gift_rule_save(bigint, jsonb),
  public.customer_save(uuid, jsonb, uuid), public.customer_set_tier(uuid, bigint, text, boolean), public.customer_directory(int), public.customer_profile(uuid),
  public.customer_pos_info(text), public.customer_points(uuid), public.customer_points_adjust(uuid, int, text, uuid), public.customer_points_redeem(uuid, int, text, uuid, boolean),
  public.gifts_due(uuid), public.gift_claim(uuid, uuid, bigint, text, uuid), public.gift_issue(uuid, text, text, numeric, date, text, uuid),
  public.customer_tier_refresh(boolean), public.tier_usage_report(date, date) from public, anon;
grant execute on function public.tier_save(bigint, jsonb, uuid), public.tier_reorder(bigint[]), public.gift_rule_save(bigint, jsonb),
  public.customer_save(uuid, jsonb, uuid), public.customer_set_tier(uuid, bigint, text, boolean), public.customer_directory(int), public.customer_profile(uuid),
  public.customer_pos_info(text), public.customer_points(uuid), public.customer_points_adjust(uuid, int, text, uuid), public.customer_points_redeem(uuid, int, text, uuid, boolean),
  public.gifts_due(uuid), public.gift_claim(uuid, uuid, bigint, text, uuid), public.gift_issue(uuid, text, text, numeric, date, text, uuid),
  public.customer_tier_refresh(boolean), public.tier_usage_report(date, date) to authenticated;
-- record_sale2 keeps its existing privileges (create or replace does not change them)

-- ---------------------------------------------------------------- phase44.sql
-- ============================================================
-- PHASE 44 (Module D): PARTNERSHIP / INVESTMENT / PROFIT-SHARING / FRANCHISE - a flexible DEED (agreement) engine.
-- Additive + idempotent (paste twice = no error). Needs phase27 (_p27_pl, the P&L extraction) and phase28 order. OWNER ONLY (sensitive).
--   * partner_parties       who (individual / company)
--   * partner_ventures      what the deal is about (a place, the business, a product line, anything), model own|franchise|funded|partnership|loan|custom
--   * partner_agreements    the DEED: editable clauses while draft; IMMUTABLE once active. An amendment is a new revision (supersedes_id); the old one stays readable.
--     agreement_parties     roles + stated share % per agreement
--   * partner_capital       append-only capital ledger (contribution / return_of_capital / loan_in / loan_repayment / owner_drawing), void flag only
--   * partner_rules         ordered steps of the profit-sharing ENGINE (step kinds below); partner_rule_validate(kind, config) checks every config
--   * partner_calculate     the trial calculation: returns the whole waterfall step by step and WRITES NOTHING
--   * partner_settlements (+lines, +payments)  preview -> save a draft snapshot -> approve -> payments -> party statement. Overlapping periods refused.
--   * partner_party_statement / partner_overview / partner_capital_balances  read models
-- Step kinds (config jsonb):  base | royalty | management_fee | expense_allow | expense_disallow | loss_carry_forward | priority_return | payback |
--   split | tiered_split | minimum_guarantee | cap | floor | rounding.   A party in a config is {"party_id": n} OR {"role": "investor"} (role = the one active party holding it).
--   Bases come from the books (sales net of returns, costed COGS, 10-2 expenses, 02-2 salary - the very _p27_pl extraction); a base that cannot be computed honestly
--   (items without a cost, product-line scope) is NULL + a warning and the owner types a manual base. Nothing is invented. The journal base of module A is not read here.
-- Settings: rule partners_module_on (default ON). Everything is audited (audit_log). Nothing is hard-deleted.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('partners_module_on', 'partners', 'switch', 'true', null, null, null, null, 'অংশীদারি / বিনিয়োগ / লাভ-ভাগ (চুক্তি) মডিউল', 'অংশীদারি / বিনিয়োগ / profit-ভাগ (deed) module', 'Partnership / investment / profit-sharing (deed) module',
  'শুধু মালিক দেখেন। বন্ধ করলে এই পর্দা ও হিসাব বন্ধ থাকে; আগের চুক্তি ও হিসাব মোছে না।', 'Owner only. Off = the screens and calculations stop; saved deeds and settlements are kept.', 94)
 on conflict (key) do nothing;

-- ============================================================
-- 1. tables
-- ============================================================
create table if not exists public.partner_parties (
  id bigserial primary key,
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null default 'individual' check (kind in ('individual', 'company')),
  mobile text check (mobile is null or length(mobile) <= 40), email text check (email is null or length(email) <= 200),
  nid_or_reg text check (nid_or_reg is null or length(nid_or_reg) <= 100), address text check (address is null or length(address) <= 500),
  photo_path text check (photo_path is null or length(photo_path) <= 300), notes text check (notes is null or length(notes) <= 2000),
  active boolean not null default true,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.partner_ventures (
  id bigserial primary key,
  name_bn text not null check (length(btrim(name_bn)) between 1 and 200), name_en text check (name_en is null or length(name_en) <= 200),
  scope text not null default 'business' check (scope in ('location', 'business', 'product_line', 'custom')),
  location_id int references public.locations(id),
  model text not null default 'partnership' check (model in ('own', 'franchise', 'funded', 'partnership', 'loan', 'custom')),
  start_date date, end_date date,
  status text not null default 'draft' check (status in ('draft', 'active', 'closed')),
  notes text check (notes is null or length(notes) <= 2000),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  check (scope <> 'location' or location_id is not null)
);
create table if not exists public.partner_agreements (
  id bigserial primary key,
  venture_id bigint not null references public.partner_ventures(id),
  title text not null check (length(btrim(title)) between 1 and 300),
  version int not null default 1,
  status text not null default 'draft' check (status in ('draft', 'active', 'amended', 'closed')),
  effective_from date, effective_to date,
  clauses jsonb not null default '[]'::jsonb check (jsonb_typeof(clauses) = 'array'),
  signed_doc_path text check (signed_doc_path is null or length(signed_doc_path) <= 300),
  supersedes_id bigint references public.partner_agreements(id),
  is_example boolean not null default false,
  activated_by uuid, activated_at timestamptz, closed_by uuid, closed_at timestamptz, closed_note text,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (effective_to is null or effective_from is null or effective_to >= effective_from)
);
create unique index if not exists partner_agreements_one_child on public.partner_agreements (supersedes_id) where supersedes_id is not null;
create index if not exists partner_agreements_venture on public.partner_agreements (venture_id);
create table if not exists public.agreement_parties (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  party_id bigint not null references public.partner_parties(id),
  role text not null check (role in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender')),
  share_percent numeric check (share_percent is null or (share_percent >= 0 and share_percent <= 100)),
  notes text check (notes is null or length(notes) <= 1000),
  active boolean not null default true,
  unique (agreement_id, party_id, role)
);
create table if not exists public.partner_rules (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  step_no int not null, step_key uuid not null default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 200),
  kind text not null check (kind in ('base', 'royalty', 'management_fee', 'expense_allow', 'expense_disallow', 'loss_carry_forward', 'priority_return', 'payback',
                                      'split', 'tiered_split', 'minimum_guarantee', 'cap', 'floor', 'rounding')),
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config) = 'object'),
  active boolean not null default true,
  unique (agreement_id, step_no)
);
create table if not exists public.partner_capital (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  party_id bigint not null references public.partner_parties(id),
  kind text not null check (kind in ('contribution', 'return_of_capital', 'loan_in', 'loan_repayment', 'owner_drawing')),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  cap_date date not null,
  mode text not null check (mode in ('cash', 'bank', 'mobile', 'in_kind')),
  description text check (description is null or length(description) <= 500), ref text check (ref is null or length(ref) <= 200),
  status text not null default 'posted' check (status in ('posted', 'void')),
  void_reason text, void_by uuid, void_at timestamptz,
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create index if not exists partner_capital_party on public.partner_capital (party_id, cap_date);
create table if not exists public.partner_settlements (
  id bigserial primary key,
  agreement_id bigint not null references public.partner_agreements(id),
  period_from date not null, period_to date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid', 'void')),
  calc jsonb not null, manual_base jsonb,
  total_distributable numeric not null,
  carry_out numeric not null default 0,
  approved_by uuid, approved_at timestamptz, void_reason text, void_by uuid, void_at timestamptz,
  note text check (note is null or length(note) <= 1000),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now(),
  check (period_to >= period_from)
);
create index if not exists partner_settlements_agr on public.partner_settlements (agreement_id, period_from);
create table if not exists public.partner_settlement_lines (
  id bigserial primary key,
  settlement_id bigint not null references public.partner_settlements(id),
  party_id bigint not null references public.partner_parties(id),
  amount numeric not null check (amount > 0),
  kind text not null check (kind in ('share', 'royalty', 'fee', 'return', 'payback', 'guarantee')),
  funded_outside boolean not null default false,
  paid_amount numeric not null default 0 check (paid_amount >= 0), paid_at date, pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile')),
  unique (settlement_id, party_id, kind, funded_outside)
);
create table if not exists public.partner_settlement_payments (
  id bigserial primary key,
  line_id bigint not null references public.partner_settlement_lines(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  paid_on date not null, mode text not null check (mode in ('cash', 'bank', 'mobile')),
  ref text check (ref is null or length(ref) <= 200),
  client_id uuid unique, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.partner_templates (
  code text primary key,
  name_bn text not null, name_en text not null, description_bn text, description_en text,
  model text not null, clauses jsonb not null default '[]'::jsonb, rules jsonb not null default '[]'::jsonb, roles jsonb not null default '[]'::jsonb,
  is_example boolean not null default true, active boolean not null default false
);

-- ============================================================
-- 2. helpers (private)
-- ============================================================
create or replace function public._a44_guard() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not coalesce(public.rule_on('partners_module_on'), true) then raise exception 'module_off'; end if;
end $$;
create or replace function public._a44_n(j jsonb) returns numeric language sql immutable as $$
  select case when j is null then null when jsonb_typeof(j) = 'number' then (j #>> '{}')::numeric
              when jsonb_typeof(j) = 'string' and (j #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then (j #>> '{}')::numeric end $$;
create or replace function public._a44_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._a44_chk_date(d date) returns void language plpgsql stable as $$
begin if d is null or d < date '2000-01-01' or d > public._a44_today() then raise exception 'bad_date'; end if; end $$;
create or replace function public._a44_chk_money(x numeric) returns void language plpgsql immutable as $$
begin if x is null or x <> x or x <= 0 or x > 1000000000000 then raise exception 'bad_amount'; end if; end $$;
-- all revisions of one deed (walk up to the first, then down)
create or replace function public._a44_chain(p_agr bigint) returns table (id bigint) language sql stable security definer set search_path = public as $$
  with recursive up as (select a.id, a.supersedes_id from public.partner_agreements a where a.id = p_agr
                        union all select a.id, a.supersedes_id from public.partner_agreements a join up on a.id = up.supersedes_id),
  dn as (select a.id from public.partner_agreements a where a.id = (select u.id from up u where u.supersedes_id is null limit 1)
         union all select a.id from public.partner_agreements a join dn on a.supersedes_id = dn.id)
  select dn.id from dn $$;
-- fraction of calendar months covered (a whole month = 1)
create or replace function public._a44_months(d1 date, d2 date) returns numeric language sql immutable as $$
  select coalesce(sum(((least(d2, ((g.ms + interval '1 month')::date) - 1) - greatest(d1, g.ms) + 1)::numeric) / (((g.ms + interval '1 month')::date) - g.ms)), 0)
  from (select ms::date as ms from generate_series(date_trunc('month', d1::timestamp), date_trunc('month', d2::timestamp), interval '1 month') ms) g $$;
create or replace function public._a44_round(x numeric, p_to numeric, p_mode text) returns numeric language sql immutable as $$
  select case when x is null then null else round(case p_mode when 'down' then floor(x / p_to) * p_to when 'up' then ceil(x / p_to) * p_to else round(x / p_to) * p_to end, 2) end $$;
-- a party reference {party_id|role} -> party id (must be active in that agreement; a role must be held by exactly one)
create or replace function public._a44_ref(p_agr bigint, p_ref jsonb) returns bigint language plpgsql stable security definer set search_path = public as $$
declare pid bigint; c int;
begin
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then return null; end if;
  if public._a44_n(p_ref -> 'party_id') is not null then
    pid := public._a44_n(p_ref -> 'party_id')::bigint;
    return (select ap.party_id from public.agreement_parties ap where ap.agreement_id = p_agr and ap.party_id = pid and ap.active limit 1);
  end if;
  if p_ref ->> 'role' is not null then
    select count(distinct ap.party_id), min(ap.party_id) into c, pid from public.agreement_parties ap where ap.agreement_id = p_agr and ap.active and ap.role = p_ref ->> 'role';
    if c = 1 then return pid; end if;
  end if;
  return null;
end $$;
create or replace function public._a44_need(p_agr bigint, p_ref jsonb, p_what text) returns bigint language plpgsql stable security definer set search_path = public as $$
declare pid bigint;
begin pid := public._a44_ref(p_agr, p_ref); if pid is null then raise exception 'party_unresolved: %', p_what; end if; return pid; end $$;
-- spread an amount over shares [{party_id|role, percent}]; the rounding remainder goes to the largest share
create or replace function public._a44_distribute(p_agr bigint, p_amount numeric, p_shares jsonb, p_to numeric, p_mode text, p_what text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e record; out jsonb := '[]'::jsonb; sum_a numeric := 0; big_ord int := 1; big_p numeric := -1; a numeric; pid bigint; i int := 0;
begin
  for e in select value as v, ord from jsonb_array_elements(p_shares) with ordinality as t(value, ord) order by ord loop
    pid := public._a44_need(p_agr, e.v, p_what);
    a := public._a44_round(p_amount * public._a44_n(e.v -> 'percent') / 100, p_to, p_mode);
    out := out || jsonb_build_array(jsonb_build_object('party_id', pid, 'amount', a, 'percent', public._a44_n(e.v -> 'percent')));
    sum_a := sum_a + a;
    if public._a44_n(e.v -> 'percent') > big_p then big_p := public._a44_n(e.v -> 'percent'); big_ord := e.ord; end if;
  end loop;
  if jsonb_array_length(out) > 0 then
    out := jsonb_set(out, array[(big_ord - 1)::text, 'amount'], to_jsonb(round((out -> (big_ord - 1) ->> 'amount')::numeric + (round(p_amount, 2) - sum_a), 2)));
  end if;
  return out;
end $$;
create or replace function public._a44_party_total(p_lines jsonb, p_party bigint, p_outside boolean default false) returns numeric language sql immutable as $$
  select coalesce(sum((e ->> 'amount')::numeric), 0) from jsonb_array_elements(p_lines) e
   where (e ->> 'party_id')::bigint = p_party and (p_outside or not coalesce((e ->> 'outside')::boolean, false)) $$;
-- capital balance of one party (all revisions of the deed) on a date: contributions + loans in - capital returned - loans repaid
create or replace function public._a44_cap(p_agr bigint, p_party bigint, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0)
  from public.partner_capital c where c.agreement_id in (select id from public._a44_chain(p_agr)) and c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_asof $$;
-- sum over every day of the period of the capital balance of that day (time-weighted capital)
create or replace function public._a44_capdays(p_agr bigint, p_party bigint, p_from date, p_to date) returns numeric language sql stable security definer set search_path = public as $$
  with m as (select c.cap_date, case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end as s
             from public.partner_capital c where c.agreement_id in (select id from public._a44_chain(p_agr)) and c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_to)
  select coalesce(sum((select coalesce(sum(m.s), 0) from m where m.cap_date <= d::date)), 0) from generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') d $$;
-- what earlier (non-void) settlements of the same deed already gave through one rule step
create or replace function public._a44_step_hist(p_agr bigint, p_from date, p_key text, out paid_before numeric, out shortfall_in numeric) language plpgsql stable security definer set search_path = public as $$
begin
  select coalesce(sum((e ->> 'core')::numeric), 0) into paid_before
    from public.partner_settlements s, jsonb_array_elements(s.calc -> 'steps') e
   where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from and e ->> 'key' = p_key;
  select coalesce((e ->> 'shortfall_out')::numeric, 0) into shortfall_in
    from public.partner_settlements s, jsonb_array_elements(s.calc -> 'steps') e
   where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to < p_from and e ->> 'key' = p_key
   order by s.period_to desc limit 1;
  shortfall_in := coalesce(shortfall_in, 0);
end $$;

-- ============================================================
-- 3. rule config validation
-- ============================================================
create or replace function public._a44_vref(c jsonb) returns void language plpgsql immutable as $$
begin
  if c is null or jsonb_typeof(c) <> 'object' or (public._a44_n(c -> 'party_id') is null and nullif(btrim(coalesce(c ->> 'role', '')), '') is null) then raise exception 'bad_config: party'; end if;
  if c ->> 'role' is not null and c ->> 'role' not in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender') then raise exception 'bad_config: role'; end if;
end $$;
create or replace function public._a44_vshares(sh jsonb) returns void language plpgsql immutable as $$
declare e jsonb; s numeric := 0; p numeric;
begin
  if sh is null or jsonb_typeof(sh) <> 'array' or jsonb_array_length(sh) < 1 or jsonb_array_length(sh) > 20 then raise exception 'bad_config: shares'; end if;
  for e in select value from jsonb_array_elements(sh) loop
    perform public._a44_vref(e); p := public._a44_n(e -> 'percent');
    if p is null or p <= 0 or p > 100 then raise exception 'bad_config: percent'; end if;
    s := s + p;
  end loop;
  if abs(s - 100) > 0.0001 then raise exception 'split_not_100'; end if;
end $$;
create or replace function public.partner_rule_validate(p_kind text, p_config jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c jsonb := coalesce(p_config, '{}'::jsonb); x numeric; e jsonb; prev numeric := 0; u numeric; n int := 0; allowed_b text[] := array['gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees'];
begin
  perform public._a44_guard();
  if jsonb_typeof(c) <> 'object' then raise exception 'bad_config: object'; end if;
  case p_kind
    when 'base' then
      if c ->> 'base' is null or c ->> 'base' not in ('gross_sales', 'net_sales', 'gross_profit', 'net_profit_before_fees', 'net_profit', 'fixed_amount', 'manual') then raise exception 'bad_config: base'; end if;
      if c ->> 'base' = 'fixed_amount' then x := public._a44_n(c -> 'amount'); if x is null or abs(x) > 1000000000000 then raise exception 'bad_config: amount'; end if; end if;
    when 'royalty' then
      perform public._a44_vref(c); x := public._a44_n(c -> 'percent');
      if x is null or x < 0 or x > 100 then raise exception 'bad_config: percent'; end if;
      if c ->> 'base' is not null and not (c ->> 'base' = any (allowed_b)) then raise exception 'bad_config: base'; end if;
    when 'management_fee' then
      perform public._a44_vref(c);
      if (public._a44_n(c -> 'percent') is null) = (public._a44_n(c -> 'fixed') is null) then raise exception 'bad_config: percent_or_fixed'; end if;
      x := coalesce(public._a44_n(c -> 'percent'), public._a44_n(c -> 'fixed'));
      if x < 0 or x > 1000000000000 or (public._a44_n(c -> 'percent') is not null and x > 100) then raise exception 'bad_config: amount'; end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
      if c ->> 'base' is not null and not (c ->> 'base' = any (allowed_b)) then raise exception 'bad_config: base'; end if;
    when 'expense_allow', 'expense_disallow' then
      if c -> 'items' is null or jsonb_typeof(c -> 'items') <> 'array' or jsonb_array_length(c -> 'items') > 50 then raise exception 'bad_config: items'; end if;
      for e in select value from jsonb_array_elements(c -> 'items') loop
        x := public._a44_n(e -> 'amount');
        if x is null or x < 0 or x > 1000000000000 or nullif(btrim(coalesce(e ->> 'name', '')), '') is null then raise exception 'bad_config: items'; end if;
      end loop;
    when 'loss_carry_forward' then null;
    when 'priority_return' then
      perform public._a44_vref(c);
      if (public._a44_n(c -> 'percent_per_year') is null) = (public._a44_n(c -> 'fixed_monthly') is null) then raise exception 'bad_config: percent_or_fixed'; end if;
      x := coalesce(public._a44_n(c -> 'percent_per_year'), public._a44_n(c -> 'fixed_monthly'));
      if x < 0 or x > 1000000000000 or (public._a44_n(c -> 'percent_per_year') is not null and x > 1000) then raise exception 'bad_config: amount'; end if;
      if c -> 'cap' is not null and jsonb_typeof(c -> 'cap') <> 'null' and (public._a44_n(c -> 'cap') is null or public._a44_n(c -> 'cap') < 0 or public._a44_n(c -> 'cap') > 1000000000000) then raise exception 'bad_config: cap'; end if;
      if c -> 'catch_up' is not null and jsonb_typeof(c -> 'catch_up') <> 'boolean' then raise exception 'bad_config: catch_up'; end if;
    when 'payback' then
      perform public._a44_vref(c); x := coalesce(public._a44_n(c -> 'percent'), 100);
      if x <= 0 or x > 100 then raise exception 'bad_config: percent'; end if;
      if c -> 'target' is not null and jsonb_typeof(c -> 'target') <> 'null' and (public._a44_n(c -> 'target') is null or public._a44_n(c -> 'target') <= 0 or public._a44_n(c -> 'target') > 1000000000000) then raise exception 'bad_config: target'; end if;
      if c -> 'then_percent' is not null and jsonb_typeof(c -> 'then_percent') <> 'null' and (public._a44_n(c -> 'then_percent') is null or public._a44_n(c -> 'then_percent') < 0 or public._a44_n(c -> 'then_percent') > 100) then raise exception 'bad_config: then_percent'; end if;
    when 'split' then perform public._a44_vshares(c -> 'shares');
    when 'tiered_split' then
      if c -> 'slabs' is null or jsonb_typeof(c -> 'slabs') <> 'array' or jsonb_array_length(c -> 'slabs') < 1 or jsonb_array_length(c -> 'slabs') > 10 then raise exception 'bad_config: slabs'; end if;
      for e in select value from jsonb_array_elements(c -> 'slabs') loop
        n := n + 1; perform public._a44_vshares(e -> 'shares');
        if e -> 'upto' is null or jsonb_typeof(e -> 'upto') = 'null' then
          if n <> jsonb_array_length(c -> 'slabs') then raise exception 'slab_order'; end if;
        else
          u := public._a44_n(e -> 'upto');
          if u is null or u <= prev or u > 1000000000000 then raise exception 'slab_order'; end if;
          prev := u;
        end if;
      end loop;
    when 'minimum_guarantee' then
      perform public._a44_vref(c); x := public._a44_n(c -> 'amount');
      if x is null or x < 0 or x > 1000000000000 then raise exception 'bad_config: amount'; end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
      if c ->> 'funded_by' is not null and c ->> 'funded_by' not in ('pool', 'outside') then raise exception 'bad_config: funded_by'; end if;
    when 'cap', 'floor' then
      x := public._a44_n(c -> 'amount');
      if x is null or x < 0 or x > 1000000000000 then raise exception 'bad_config: amount'; end if;
      if coalesce(c ->> 'target', 'pool') not in ('pool', 'party') then raise exception 'bad_config: target'; end if;
      if c ->> 'target' = 'party' then perform public._a44_vref(c); end if;
      if c ->> 'per' is not null and c ->> 'per' not in ('period', 'month') then raise exception 'bad_config: per'; end if;
    when 'rounding' then
      x := public._a44_n(c -> 'to');
      if x is null or x not in (0.01, 0.1, 1, 5, 10, 50, 100, 1000) then raise exception 'bad_config: to'; end if;
      if coalesce(c ->> 'mode', 'nearest') not in ('nearest', 'down', 'up') then raise exception 'bad_config: mode'; end if;
    else raise exception 'bad_kind';
  end case;
  return c;
end $$;

-- ============================================================
-- 4. guards (immutability, append-only)
-- ============================================================
create or replace function public._a44_agr_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a deed is never deleted'; end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' then
    if new.venture_id is distinct from old.venture_id or new.title is distinct from old.title or new.version is distinct from old.version
       or new.effective_from is distinct from old.effective_from or new.clauses is distinct from old.clauses
       or new.supersedes_id is distinct from old.supersedes_id or new.is_example is distinct from old.is_example or new.created_by is distinct from old.created_by then
      raise exception 'agreement_immutable: an active deed cannot be edited - make an amendment';
    end if;
    if new.status is distinct from old.status and not (old.status = 'active' and new.status in ('amended', 'closed')) then raise exception 'agreement_immutable: bad status change'; end if;
    if new.status is not distinct from old.status and new.effective_to is distinct from old.effective_to then raise exception 'agreement_immutable: dates are fixed'; end if;
  end if;
  if tg_op = 'UPDATE' and old.status = 'draft' and new.status not in ('draft', 'active') then raise exception 'agreement_immutable: bad status change'; end if;
  return new;
end $$;
drop trigger if exists partner_agreements_guard on public.partner_agreements;
create trigger partner_agreements_guard before update or delete on public.partner_agreements for each row execute function public._a44_agr_guard();

create or replace function public._a44_child_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare st text; aid bigint;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: retire it with the active flag, never delete'; end if;
  aid := new.agreement_id;
  select status into st from public.partner_agreements where id = aid;
  if st is distinct from 'draft' then raise exception 'agreement_immutable: the deed is not a draft - make an amendment'; end if;
  return new;
end $$;
drop trigger if exists partner_rules_guard on public.partner_rules;
create trigger partner_rules_guard before insert or update or delete on public.partner_rules for each row execute function public._a44_child_guard();
drop trigger if exists agreement_parties_guard on public.agreement_parties;
create trigger agreement_parties_guard before insert or update or delete on public.agreement_parties for each row execute function public._a44_child_guard();

create or replace function public._a44_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists partner_settlement_payments_ro on public.partner_settlement_payments;
create trigger partner_settlement_payments_ro before update or delete on public.partner_settlement_payments for each row execute function public._a44_ro();
drop trigger if exists partner_settlement_payments_ro_t on public.partner_settlement_payments;
create trigger partner_settlement_payments_ro_t before truncate on public.partner_settlement_payments for each statement execute function public._a44_ro();

create or replace function public._a44_cap_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: capital rows are never deleted - void them'; end if;
  if (to_jsonb(new) - 'status' - 'void_reason' - 'void_by' - 'void_at') is distinct from (to_jsonb(old) - 'status' - 'void_reason' - 'void_by' - 'void_at') then
    raise exception 'append_only: capital rows cannot be changed'; end if;
  if new.status is distinct from old.status and not (old.status = 'posted' and new.status = 'void') then raise exception 'append_only: a void row stays void'; end if;
  return new;
end $$;
drop trigger if exists partner_capital_guard on public.partner_capital;
create trigger partner_capital_guard before update or delete on public.partner_capital for each row execute function public._a44_cap_guard();
drop trigger if exists partner_capital_guard_t on public.partner_capital;
create trigger partner_capital_guard_t before truncate on public.partner_capital for each statement execute function public._a44_ro();

create or replace function public._a44_set_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: settlements are never deleted - void them'; end if;
  if new.agreement_id is distinct from old.agreement_id or new.period_from is distinct from old.period_from or new.period_to is distinct from old.period_to
     or new.calc is distinct from old.calc or new.manual_base is distinct from old.manual_base or new.total_distributable is distinct from old.total_distributable
     or new.carry_out is distinct from old.carry_out or new.created_by is distinct from old.created_by then
    raise exception 'settlement_immutable: the saved calculation cannot be changed - void it and make a new one';
  end if;
  if old.status in ('void') then raise exception 'settlement_immutable: a void settlement stays void'; end if;
  if new.status is distinct from old.status and not ((old.status = 'draft' and new.status in ('approved', 'void')) or (old.status = 'approved' and new.status in ('paid', 'void'))) then
    raise exception 'settlement_immutable: bad status change'; end if;
  if old.status <> 'draft' and new.note is distinct from old.note then raise exception 'settlement_immutable: the note is fixed after approval'; end if;
  return new;
end $$;
drop trigger if exists partner_settlements_guard on public.partner_settlements;
create trigger partner_settlements_guard before update or delete on public.partner_settlements for each row execute function public._a44_set_guard();
create or replace function public._a44_line_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: settlement lines are never deleted'; end if;
  if (to_jsonb(new) - 'paid_amount' - 'paid_at' - 'pay_mode') is distinct from (to_jsonb(old) - 'paid_amount' - 'paid_at' - 'pay_mode') then
    raise exception 'settlement_immutable: only payments can change a line'; end if;
  return new;
end $$;
drop trigger if exists partner_settlement_lines_guard on public.partner_settlement_lines;
create trigger partner_settlement_lines_guard before update or delete on public.partner_settlement_lines for each row execute function public._a44_line_guard();

-- audit
drop trigger if exists audit_partner_parties on public.partner_parties;
create trigger audit_partner_parties after insert or update on public.partner_parties for each row execute function public.log_change('id');
drop trigger if exists audit_partner_ventures on public.partner_ventures;
create trigger audit_partner_ventures after insert or update on public.partner_ventures for each row execute function public.log_change('id');
drop trigger if exists audit_partner_agreements on public.partner_agreements;
create trigger audit_partner_agreements after insert or update on public.partner_agreements for each row execute function public.log_change('id');
drop trigger if exists audit_agreement_parties on public.agreement_parties;
create trigger audit_agreement_parties after insert or update on public.agreement_parties for each row execute function public.log_change('id');
drop trigger if exists audit_partner_rules on public.partner_rules;
create trigger audit_partner_rules after insert or update on public.partner_rules for each row execute function public.log_change('id');
drop trigger if exists audit_partner_capital on public.partner_capital;
create trigger audit_partner_capital after insert or update on public.partner_capital for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlements on public.partner_settlements;
create trigger audit_partner_settlements after insert or update on public.partner_settlements for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlement_lines on public.partner_settlement_lines;
create trigger audit_partner_settlement_lines after insert or update on public.partner_settlement_lines for each row execute function public.log_change('id');
drop trigger if exists audit_partner_settlement_payments on public.partner_settlement_payments;
create trigger audit_partner_settlement_payments after insert on public.partner_settlement_payments for each row execute function public.log_change('id');

-- ============================================================
-- 5. RLS: owner reads, nobody writes directly
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['partner_parties', 'partner_ventures', 'partner_agreements', 'agreement_parties', 'partner_rules', 'partner_capital',
                           'partner_settlements', 'partner_settlement_lines', 'partner_settlement_payments', 'partner_templates'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner())', t || '_sel', t);
  end loop;
end $$;

-- ============================================================
-- 6. parties, ventures
-- ============================================================
create or replace function public.partner_party_save(p_id bigint, p_name text, p_kind text, p_mobile text, p_email text, p_nid text, p_address text, p_photo text, p_notes text, p_active boolean, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_parties;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name, '')), '') is null or length(p_name) > 200 then raise exception 'name_required'; end if;
  if coalesce(p_kind, 'individual') not in ('individual', 'company') then raise exception 'bad_kind'; end if;
  if p_id is null then
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_parties where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_parties (name, kind, mobile, email, nid_or_reg, address, photo_path, notes, active, client_id, created_by)
      values (btrim(p_name), coalesce(p_kind, 'individual'), nullif(btrim(p_mobile), ''), nullif(btrim(p_email), ''), nullif(btrim(p_nid), ''), nullif(btrim(p_address), ''), nullif(p_photo, ''), nullif(btrim(p_notes), ''),
              coalesce(p_active, true), p_client, auth.uid()) returning * into r;
  else
    update public.partner_parties set name = btrim(p_name), kind = coalesce(p_kind, kind), mobile = nullif(btrim(p_mobile), ''), email = nullif(btrim(p_email), ''), nid_or_reg = nullif(btrim(p_nid), ''),
           address = nullif(btrim(p_address), ''), photo_path = coalesce(nullif(p_photo, ''), photo_path), notes = nullif(btrim(p_notes), ''), active = coalesce(p_active, active)
     where id = p_id returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.partner_venture_save(p_id bigint, p_name_bn text, p_name_en text, p_scope text, p_location_id int, p_model text, p_start date, p_end date, p_status text, p_notes text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_ventures; st text := coalesce(p_status, 'draft');
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null then raise exception 'name_required'; end if;
  if coalesce(p_scope, 'business') not in ('location', 'business', 'product_line', 'custom') then raise exception 'bad_scope'; end if;
  if coalesce(p_model, 'partnership') not in ('own', 'franchise', 'funded', 'partnership', 'loan', 'custom') then raise exception 'bad_model'; end if;
  if st not in ('draft', 'active', 'closed') then raise exception 'bad_status'; end if;
  if coalesce(p_scope, 'business') = 'location' and not exists (select 1 from public.locations where id = p_location_id) then raise exception 'location_not_found'; end if;
  if p_end is not null and p_start is not null and p_end < p_start then raise exception 'bad_date'; end if;
  if p_id is null then
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_ventures where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_ventures (name_bn, name_en, scope, location_id, model, start_date, end_date, status, notes, client_id, created_by)
      values (btrim(p_name_bn), nullif(btrim(p_name_en), ''), coalesce(p_scope, 'business'), case when p_scope = 'location' then p_location_id end, coalesce(p_model, 'partnership'), p_start, p_end, st, nullif(btrim(p_notes), ''), p_client, auth.uid())
      returning * into r;
  else
    if st = 'closed' and exists (select 1 from public.partner_agreements where venture_id = p_id and status = 'active') then raise exception 'agreements_open'; end if;
    update public.partner_ventures set name_bn = btrim(p_name_bn), name_en = nullif(btrim(p_name_en), ''), scope = coalesce(p_scope, scope), location_id = case when coalesce(p_scope, scope) = 'location' then p_location_id end,
           model = coalesce(p_model, model), start_date = p_start, end_date = p_end, status = st, notes = nullif(btrim(p_notes), '') where id = p_id returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return to_jsonb(r);
end $$;

-- ============================================================
-- 7. agreements (deeds)
-- ============================================================
create or replace function public._a44_clauses_ok(c jsonb) returns void language plpgsql immutable as $$
declare e jsonb;
begin
  if c is null or jsonb_typeof(c) <> 'array' or jsonb_array_length(c) > 200 then raise exception 'bad_clauses'; end if;
  for e in select value from jsonb_array_elements(c) loop
    if jsonb_typeof(e) <> 'object' or length(coalesce(e ->> 'text_bn', '')) > 20000 or length(coalesce(e ->> 'text_en', '')) > 20000
       or length(coalesce(e ->> 'title_bn', '')) > 300 or length(coalesce(e ->> 'title_en', '')) > 300 then raise exception 'bad_clauses'; end if;
  end loop;
end $$;

-- create (p_id null) or edit a DRAFT deed. Clauses are free text, reordered by sending the array in the new order (no is renumbered here).
create or replace function public.partner_agreement_save(p_id bigint, p_venture bigint, p_title text, p_from date, p_to date, p_clauses jsonb, p_signed_doc text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_agreements; cl jsonb; i int := 0; e jsonb;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_title, '')), '') is null then raise exception 'name_required'; end if;
  if p_to is not null and p_from is not null and p_to < p_from then raise exception 'bad_date'; end if;
  perform public._a44_clauses_ok(coalesce(p_clauses, '[]'::jsonb));
  cl := '[]'::jsonb;
  for e in select value from jsonb_array_elements(coalesce(p_clauses, '[]'::jsonb)) loop i := i + 1; cl := cl || jsonb_build_array(jsonb_set(e, '{no}', to_jsonb(i))); end loop;
  if p_id is null then
    if not exists (select 1 from public.partner_ventures where id = p_venture) then raise exception 'venture_not_found'; end if;
    if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_agreements where client_id = p_client; if found then return to_jsonb(r); end if; end if;
    insert into public.partner_agreements (venture_id, title, effective_from, effective_to, clauses, signed_doc_path, client_id, created_by)
      values (p_venture, btrim(p_title), p_from, p_to, cl, nullif(p_signed_doc, ''), p_client, auth.uid()) returning * into r;
  else
    select * into r from public.partner_agreements where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if r.status <> 'draft' then
      -- the only thing a live deed accepts is the scan of the signed paper
      update public.partner_agreements set signed_doc_path = coalesce(nullif(p_signed_doc, ''), signed_doc_path) where id = p_id returning * into r;
    else
      update public.partner_agreements set title = btrim(p_title), effective_from = p_from, effective_to = p_to, clauses = cl, signed_doc_path = coalesce(nullif(p_signed_doc, ''), signed_doc_path) where id = p_id returning * into r;
    end if;
  end if;
  return to_jsonb(r);
end $$;

create or replace function public.partner_agreement_party_set(p_agr bigint, p_party bigint, p_role text, p_share numeric, p_notes text, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.agreement_parties;
begin
  perform public._a44_guard();
  if p_role not in ('owner', 'partner', 'investor', 'franchisee', 'manager', 'lender') then raise exception 'bad_role'; end if;
  if p_share is not null and (p_share < 0 or p_share > 100) then raise exception 'bad_percent'; end if;
  if not exists (select 1 from public.partner_agreements where id = p_agr) then raise exception 'not_found'; end if;
  if not exists (select 1 from public.partner_parties where id = p_party) then raise exception 'party_not_found'; end if;
  insert into public.agreement_parties (agreement_id, party_id, role, share_percent, notes, active) values (p_agr, p_party, p_role, p_share, nullif(btrim(p_notes), ''), coalesce(p_active, true))
    on conflict (agreement_id, party_id, role) do update set share_percent = excluded.share_percent, notes = excluded.notes, active = excluded.active returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.partner_rule_save(p_agr bigint, p_step_no int, p_name text, p_kind text, p_config jsonb, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_rules; cfg jsonb; n int := p_step_no;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_name, '')), '') is null then raise exception 'name_required'; end if;
  cfg := public.partner_rule_validate(p_kind, p_config);
  if not exists (select 1 from public.partner_agreements where id = p_agr) then raise exception 'not_found'; end if;
  if n is null then select coalesce(max(step_no), 0) + 1 into n from public.partner_rules where agreement_id = p_agr; end if;
  insert into public.partner_rules (agreement_id, step_no, name, kind, config, active) values (p_agr, n, btrim(p_name), p_kind, cfg, coalesce(p_active, true))
    on conflict (agreement_id, step_no) do update set name = excluded.name, kind = excluded.kind, config = excluded.config, active = excluded.active returning * into r;
  return to_jsonb(r);
end $$;

-- new order = array of step numbers
create or replace function public.partner_rules_reorder(p_agr bigint, p_order jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cnt int; i int := 0; e jsonb; st text;
begin
  perform public._a44_guard();
  select status into st from public.partner_agreements where id = p_agr;
  if st is null then raise exception 'not_found'; end if;
  if st <> 'draft' then raise exception 'agreement_immutable: the deed is not a draft'; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'array' then raise exception 'bad_order'; end if;
  select count(*) into cnt from public.partner_rules where agreement_id = p_agr;
  if jsonb_array_length(p_order) <> cnt or (select count(distinct v) from jsonb_array_elements_text(p_order) v) <> cnt
     or exists (select 1 from jsonb_array_elements_text(p_order) v where not exists (select 1 from public.partner_rules r where r.agreement_id = p_agr and r.step_no = v::int)) then raise exception 'bad_order'; end if;
  update public.partner_rules set step_no = step_no + 100000 where agreement_id = p_agr;
  for e in select value from jsonb_array_elements(p_order) loop
    i := i + 1; update public.partner_rules set step_no = i where agreement_id = p_agr and step_no = (e #>> '{}')::int + 100000;
  end loop;
  return jsonb_build_object('agreement_id', p_agr, 'steps', cnt);
end $$;

-- a deed must be coherent before it goes live
create or replace function public._a44_check_ready(p_agr bigint) returns void language plpgsql stable security definer set search_path = public as $$
declare r record; nb int := 0; first_kind text; i int := 0; e jsonb;
begin
  if not exists (select 1 from public.agreement_parties where agreement_id = p_agr and active) then raise exception 'no_parties'; end if;
  if (select count(*) from public.partner_rules where agreement_id = p_agr and active) = 0 then raise exception 'no_rules'; end if;
  for r in select * from public.partner_rules where agreement_id = p_agr and active order by step_no loop
    i := i + 1; perform public.partner_rule_validate(r.kind, r.config);
    if i = 1 then first_kind := r.kind; end if;
    if r.kind = 'base' then nb := nb + 1; end if;
    if r.kind in ('royalty', 'management_fee', 'priority_return', 'payback', 'minimum_guarantee') or (r.kind in ('cap', 'floor') and r.config ->> 'target' = 'party') then
      if public._a44_ref(p_agr, r.config) is null then raise exception 'party_unresolved: %', r.name; end if;
    elsif r.kind = 'split' then
      for e in select value from jsonb_array_elements(r.config -> 'shares') loop if public._a44_ref(p_agr, e) is null then raise exception 'party_unresolved: %', r.name; end if; end loop;
    elsif r.kind = 'tiered_split' then
      for e in select s.value from jsonb_array_elements(r.config -> 'slabs') sl, jsonb_array_elements(sl.value -> 'shares') s loop if public._a44_ref(p_agr, e) is null then raise exception 'party_unresolved: %', r.name; end if; end loop;
    end if;
  end loop;
  if nb <> 1 or first_kind is distinct from 'base' then raise exception 'base_step_first'; end if;
end $$;

create or replace function public.partner_agreement_activate(p_agr bigint, p_numbers_confirmed boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; prev public.partner_agreements;
begin
  perform public._a44_guard();
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'draft' then raise exception 'not_draft'; end if;
  if a.effective_from is null then raise exception 'dates_required'; end if;
  if a.is_example and not coalesce(p_numbers_confirmed, false) then raise exception 'example_numbers_not_confirmed'; end if;
  perform public._a44_check_ready(p_agr);
  if a.supersedes_id is not null then
    select * into prev from public.partner_agreements where id = a.supersedes_id for update;
    if prev.status <> 'active' then raise exception 'previous_not_active'; end if;
    if a.effective_from <= prev.effective_from then raise exception 'bad_date'; end if;
    if exists (select 1 from public.partner_settlements s where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and s.period_to >= a.effective_from) then raise exception 'period_already_settled'; end if;
    update public.partner_agreements set status = 'amended', effective_to = a.effective_from - 1, closed_at = now(), closed_by = auth.uid(), closed_note = 'amended by #' || a.id where id = prev.id;
  elsif exists (select 1 from public.partner_agreements x where x.venture_id = a.venture_id and x.status = 'active' and x.id <> a.id) then
    null;   -- several deeds on one venture are allowed (e.g. one per investor); the owner chooses
  end if;
  update public.partner_agreements set status = 'active', activated_by = auth.uid(), activated_at = now() where id = p_agr returning * into a;
  update public.partner_ventures set status = 'active' where id = a.venture_id and status = 'draft';
  return to_jsonb(a);
end $$;

create or replace function public.partner_agreement_amend(p_agr bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; n public.partner_agreements;
begin
  perform public._a44_guard();
  if p_client is not null then perform public._client_lock(p_client); select * into n from public.partner_agreements where client_id = p_client; if found then return to_jsonb(n); end if; end if;
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if exists (select 1 from public.partner_agreements where supersedes_id = a.id) then raise exception 'draft_exists'; end if;
  insert into public.partner_agreements (venture_id, title, version, status, effective_from, effective_to, clauses, signed_doc_path, supersedes_id, is_example, client_id, created_by)
    values (a.venture_id, a.title, a.version + 1, 'draft', null, null, a.clauses, null, a.id, false, p_client, auth.uid()) returning * into n;
  insert into public.agreement_parties (agreement_id, party_id, role, share_percent, notes, active) select n.id, party_id, role, share_percent, notes, active from public.agreement_parties where agreement_id = a.id;
  insert into public.partner_rules (agreement_id, step_no, step_key, name, kind, config, active) select n.id, step_no, step_key, name, kind, config, active from public.partner_rules where agreement_id = a.id;
  return to_jsonb(n);
end $$;

create or replace function public.partner_agreement_close(p_agr bigint, p_note text default null, p_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.partner_agreements; d date := coalesce(p_date, public._a44_today());
begin
  perform public._a44_guard();
  select * into a from public.partner_agreements where id = p_agr for update;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if d < a.effective_from then raise exception 'bad_date'; end if;
  update public.partner_agreements set status = 'closed', effective_to = d, closed_by = auth.uid(), closed_at = now(), closed_note = left(p_note, 500) where id = p_agr returning * into a;
  return to_jsonb(a);
end $$;

-- a draft deed from a seeded EXAMPLE template (parties and numbers still to be chosen; activation asks the owner to confirm the numbers)
create or replace function public.partner_agreement_from_template(p_venture bigint, p_code text, p_title text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.partner_templates; r public.partner_agreements; e jsonb; i int := 0;
begin
  perform public._a44_guard();
  select * into t from public.partner_templates where code = p_code;
  if not found then raise exception 'template_not_found'; end if;
  if not exists (select 1 from public.partner_ventures where id = p_venture) then raise exception 'venture_not_found'; end if;
  if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_agreements where client_id = p_client; if found then return to_jsonb(r); end if; end if;
  insert into public.partner_agreements (venture_id, title, clauses, is_example, client_id, created_by)
    values (p_venture, coalesce(nullif(btrim(p_title), ''), 'EXAMPLE - ' || t.name_en), t.clauses, true, p_client, auth.uid()) returning * into r;
  for e in select value from jsonb_array_elements(t.rules) loop
    i := i + 1;
    insert into public.partner_rules (agreement_id, step_no, name, kind, config, active) values (r.id, i, e ->> 'name', e ->> 'kind', e -> 'config', true);
  end loop;
  return to_jsonb(r);
end $$;

-- ============================================================
-- 8. capital ledger
-- ============================================================
create or replace function public.partner_capital_add(p_agr bigint, p_party bigint, p_kind text, p_amount numeric, p_date date, p_mode text, p_desc text, p_ref text, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.partner_capital; a public.partner_agreements; bal numeric;
begin
  perform public._a44_guard();
  if p_kind not in ('contribution', 'return_of_capital', 'loan_in', 'loan_repayment', 'owner_drawing') then raise exception 'bad_kind'; end if;
  if p_mode not in ('cash', 'bank', 'mobile', 'in_kind') then raise exception 'bad_mode'; end if;
  perform public._a44_chk_money(p_amount); perform public._a44_chk_date(p_date); perform public.lock_check(p_date);
  if p_client is not null then perform public._client_lock(p_client); select * into r from public.partner_capital where client_id = p_client; if found then return to_jsonb(r); end if; end if;
  select * into a from public.partner_agreements where id = p_agr;
  if not found then raise exception 'not_found'; end if;
  if a.status <> 'active' then raise exception 'not_active'; end if;
  if not exists (select 1 from public.agreement_parties where agreement_id = p_agr and party_id = p_party and active) then raise exception 'party_not_in_deed'; end if;
  if p_kind in ('return_of_capital', 'loan_repayment') then
    bal := public._a44_cap(p_agr, p_party, p_date);
    if p_amount > bal + 0.004 then raise exception 'exceeds_capital'; end if;
  end if;
  insert into public.partner_capital (agreement_id, party_id, kind, amount, cap_date, mode, description, ref, client_id, created_by)
    values (p_agr, p_party, p_kind, round(p_amount, 2), p_date, p_mode, nullif(btrim(p_desc), ''), nullif(btrim(p_ref), ''), p_client, auth.uid()) returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.partner_capital_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.partner_capital;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  select * into r from public.partner_capital where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'void' then return to_jsonb(r); end if;
  perform public.lock_check(r.cap_date);
  update public.partner_capital set status = 'void', void_reason = left(p_reason, 300), void_by = auth.uid(), void_at = now() where id = p_id returning * into r;
  return to_jsonb(r);
end $$;

-- per party: contributed, loans in, returned, repaid, drawings, balance, paid back through settlements, outstanding payback
create or replace function public.partner_capital_balances(p_agr bigint, p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._a44_today()); out jsonb;
begin
  perform public._a44_guard();
  select coalesce(jsonb_agg(x order by x ->> 'name'), '[]'::jsonb) into out from (
    select jsonb_build_object('party_id', p.id, 'name', p.name,
      'contributed', coalesce(sum(c.amount) filter (where c.kind = 'contribution'), 0), 'loan_in', coalesce(sum(c.amount) filter (where c.kind = 'loan_in'), 0),
      'returned', coalesce(sum(c.amount) filter (where c.kind = 'return_of_capital'), 0), 'repaid', coalesce(sum(c.amount) filter (where c.kind = 'loan_repayment'), 0),
      'drawings', coalesce(sum(c.amount) filter (where c.kind = 'owner_drawing'), 0),
      'balance', public._a44_cap(p_agr, p.id, d),
      'paid_back', (select coalesce(sum(l.amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and l.kind = 'payback' and l.party_id = p.id and s.period_to <= d),
      'outstanding_payback', public._a44_cap(p_agr, p.id, d) - (select coalesce(sum(l.amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                     where s.agreement_id in (select id from public._a44_chain(p_agr)) and s.status <> 'void' and l.kind = 'payback' and l.party_id = p.id and s.period_to <= d)) as x
    from public.partner_parties p
    left join public.partner_capital c on c.party_id = p.id and c.agreement_id in (select id from public._a44_chain(p_agr)) and c.status = 'posted' and c.cap_date <= d
    where p.id in (select party_id from public.agreement_parties where agreement_id in (select id from public._a44_chain(p_agr)))
    group by p.id, p.name) q;
  return out;
end $$;

-- ============================================================
-- 9. the calculation engine (trial - writes nothing)
-- ============================================================
create or replace function public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  ag public.partner_agreements; vn public.partner_ventures; locs int[]; k text; r record; cfg jsonb; sh jsonb; er record; er2 record;
  bases jsonb := '{}'::jsonb; src jsonb := '{}'::jsonb; warns jsonb := '[]'::jsonb; steps jsonb := '[]'::jsonb; lines jsonb := '[]'::jsonb; nl jsonb;
  v_gs numeric; v_ns numeric; v_costed numeric; v_cogs numeric; v_exp numeric; v_sal numeric; v_fix numeric; v_gp numeric; v_nf numeric; v_n int;
  pool numeric; poolset boolean := false; incomplete boolean := false; fees numeric := 0;
  rto numeric := 0.01; rmode text := 'nearest';
  carry_in numeric := 0; carry_out numeric := 0; retained numeric := 0; floor_added numeric := 0;
  amt numeric; core numeric; stepamt numeric; pool_before numeric; pid bigint; pct numeric; mths numeric := public._a44_months(p_from, p_to); days int := p_to - p_from + 1;
  capb numeric; due numeric; capc numeric; paid_b numeric; sf_in numeric; short_out numeric; outb numeric; a1 numeric; a2 numeric; used numeric; tgt numeric; lim numeric; tot numeric; exc numeric; rem numeric; red numeric;
  detail jsonb; skipped boolean; remaining numeric; prev_up numeric; size numeric; dist jsonb; d jsonb; need numeric; outside boolean; names jsonb; ptot jsonb; tdist numeric := 0; tout numeric := 0;
  nbase int := 0; newlines jsonb;
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
      bases := bases || jsonb_build_object('gross_profit', v_gp, 'net_profit_before_fees', v_nf);
    else
      warns := warns || jsonb_build_array(jsonb_build_object('code', 'uncosted_sales', 'detail', round(v_ns - v_costed, 2), 'msg', 'Some sold items have no cost price, so gross profit cannot be computed honestly. Type a manual base.'));
      bases := bases || jsonb_build_object('gross_profit', null, 'net_profit_before_fees', null);
    end if;
    bases := bases || jsonb_build_object('expenses', v_exp, 'salary', v_sal, 'fixed_cost', v_fix, 'cogs', v_cogs);
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
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'wrote', false);
end $$;

-- ============================================================
-- 10. settlements: draft snapshot -> approve -> pay -> void
-- ============================================================
create or replace function public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  insert into public.partner_settlements (agreement_id, period_from, period_to, status, calc, manual_base, total_distributable, carry_out, note, client_id, created_by)
    values (p_agr, p_from, p_to, 'draft', c, p_manual, (c ->> 'total_distributable')::numeric, (c ->> 'carry_out')::numeric, left(p_note, 1000), p_client, auth.uid()) returning * into s;
  insert into public.partner_settlement_lines (settlement_id, party_id, amount, kind, funded_outside)
    select s.id, (e ->> 'party_id')::bigint, round(sum((e ->> 'amount')::numeric), 2), e ->> 'kind', coalesce((e ->> 'outside')::boolean, false)
      from jsonb_array_elements(c -> 'lines') e group by 2, 4, 5 having round(sum((e ->> 'amount')::numeric), 2) > 0;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_approve(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.partner_settlements;
begin
  perform public._a44_guard();
  select * into s from public.partner_settlements where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status <> 'draft' then raise exception 'not_draft'; end if;
  update public.partner_settlements set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_id returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.partner_settlements;
begin
  perform public._a44_guard();
  if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
  select * into s from public.partner_settlements where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status not in ('draft', 'approved') then raise exception 'cannot_void'; end if;
  if exists (select 1 from public.partner_settlement_lines where settlement_id = p_id and paid_amount > 0) then raise exception 'has_payments'; end if;
  update public.partner_settlements set status = 'void', void_reason = left(p_reason, 300), void_by = auth.uid(), void_at = now() where id = p_id returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.partner_settlement_pay(p_line bigint, p_amount numeric, p_mode text, p_date date, p_ref text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.partner_settlement_lines; s public.partner_settlements; pay public.partner_settlement_payments;
begin
  perform public._a44_guard();
  if p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  perform public._a44_chk_money(p_amount); perform public._a44_chk_date(p_date); perform public.lock_check(p_date);
  if p_client is not null then perform public._client_lock(p_client); select * into pay from public.partner_settlement_payments where client_id = p_client; if found then return to_jsonb(pay); end if; end if;
  select * into l from public.partner_settlement_lines where id = p_line for update;
  if not found then raise exception 'not_found'; end if;
  select * into s from public.partner_settlements where id = l.settlement_id for update;
  if s.status <> 'approved' then raise exception 'not_approved'; end if;
  if p_date < s.period_from then raise exception 'bad_date'; end if;
  if l.paid_amount + round(p_amount, 2) > l.amount + 0.004 then raise exception 'overpay'; end if;
  insert into public.partner_settlement_payments (line_id, amount, paid_on, mode, ref, client_id, created_by) values (p_line, round(p_amount, 2), p_date, p_mode, nullif(btrim(p_ref), ''), p_client, auth.uid()) returning * into pay;
  update public.partner_settlement_lines set paid_amount = paid_amount + round(p_amount, 2), paid_at = p_date, pay_mode = p_mode where id = p_line;
  if not exists (select 1 from public.partner_settlement_lines where settlement_id = s.id and paid_amount < amount - 0.004) then
    update public.partner_settlements set status = 'paid' where id = s.id;
  end if;
  return to_jsonb(pay);
end $$;

-- ============================================================
-- 11. read models
-- ============================================================
create or replace function public.partner_party_statement(p_party bigint, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pt public.partner_parties; cap jsonb; due jsonb; pays jsonb; opening numeric; closing numeric; owed numeric; tdue numeric; tpaid numeric;
begin
  perform public._a44_guard();
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  select * into pt from public.partner_parties where id = p_party;
  if not found then raise exception 'not_found'; end if;
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) into opening
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date < p_from;
  select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) into closing
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date <= p_to;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'date', c.cap_date, 'kind', c.kind, 'amount', c.amount, 'mode', c.mode, 'agreement_id', c.agreement_id, 'description', c.description, 'ref', c.ref) order by c.cap_date, c.id), '[]'::jsonb) into cap
    from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.cap_date between p_from and p_to;
  select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'settlement_id', s.id, 'agreement_id', s.agreement_id, 'period_from', s.period_from, 'period_to', s.period_to, 'kind', l.kind, 'amount', l.amount, 'paid', l.paid_amount, 'status', s.status, 'outside', l.funded_outside) order by s.period_to, l.id), '[]'::jsonb) into due
    from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status in ('approved', 'paid') and s.period_to between p_from and p_to;
  select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'date', y.paid_on, 'amount', y.amount, 'mode', y.mode, 'ref', y.ref, 'line_id', y.line_id) order by y.paid_on, y.id), '[]'::jsonb) into pays
    from public.partner_settlement_payments y join public.partner_settlement_lines l on l.id = y.line_id where l.party_id = p_party and y.paid_on between p_from and p_to;
  select coalesce(sum(l.amount), 0) into tdue from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status in ('approved', 'paid') and s.period_to <= p_to;
  select coalesce(sum(y.amount), 0) into tpaid from public.partner_settlement_payments y join public.partner_settlement_lines l on l.id = y.line_id
   join public.partner_settlements s on s.id = l.settlement_id where l.party_id = p_party and s.status in ('approved', 'paid') and y.paid_on <= p_to;
  owed := tdue - tpaid;
  return jsonb_build_object('party', jsonb_build_object('id', pt.id, 'name', pt.name, 'kind', pt.kind, 'mobile', pt.mobile, 'email', pt.email, 'nid_or_reg', pt.nid_or_reg, 'address', pt.address),
    'from', p_from, 'to', p_to, 'capital_opening', opening, 'capital_movements', cap, 'capital_closing', closing,
    'drawings', (select coalesce(sum(c.amount), 0) from public.partner_capital c where c.party_id = p_party and c.status = 'posted' and c.kind = 'owner_drawing' and c.cap_date between p_from and p_to),
    'shares_due', due, 'payments', pays,
    'due_in_period', (select coalesce(sum((x ->> 'amount')::numeric), 0) from jsonb_array_elements(due) x),
    'paid_in_period', (select coalesce(sum((x ->> 'amount')::numeric), 0) from jsonb_array_elements(pays) x),
    'due_to_date', tdue, 'paid_to_date', tpaid, 'balance_owed', owed);
end $$;

create or replace function public.partner_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  perform public._a44_guard();
  select coalesce(jsonb_agg(x order by (x ->> 'id')::bigint), '[]'::jsonb) into out from (
    select jsonb_build_object('id', v.id, 'name_bn', v.name_bn, 'name_en', v.name_en, 'scope', v.scope, 'model', v.model, 'status', v.status, 'location_id', v.location_id,
      'agreements', (select count(*) from public.partner_agreements a where a.venture_id = v.id and a.status = 'active'),
      'drafts', (select count(*) from public.partner_agreements a where a.venture_id = v.id and a.status = 'draft'),
      'capital', (select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0)
                    from public.partner_capital c join public.partner_agreements a on a.id = c.agreement_id where a.venture_id = v.id and c.status = 'posted'),
      'next_due', (select min(coalesce((select max(s.period_to) + 1 from public.partner_settlements s where s.agreement_id in (select id from public._a44_chain(a.id)) and s.status <> 'void'), a.effective_from))
                     from public.partner_agreements a where a.venture_id = v.id and a.status = 'active'),
      'owed', (select coalesce(sum(l.amount - l.paid_amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                 join public.partner_agreements a on a.id = s.agreement_id where a.venture_id = v.id and s.status = 'approved')) as x
    from public.partner_ventures v) q;
  return jsonb_build_object('ventures', out, 'owed_total', (select coalesce(sum(l.amount - l.paid_amount), 0) from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id where s.status = 'approved'),
    'capital_total', (select coalesce(sum(case c.kind when 'contribution' then c.amount when 'loan_in' then c.amount when 'return_of_capital' then -c.amount when 'loan_repayment' then -c.amount else 0 end), 0) from public.partner_capital c where c.status = 'posted'));
end $$;

-- ============================================================
-- 12. example templates (EXAMPLE only - inactive, numbers are placeholders the owner must replace)
-- ============================================================
insert into public.partner_templates (code, name_bn, name_en, description_bn, description_en, model, clauses, roles, rules, is_example, active)
select * from (values
 ('franchise', 'উদাহরণ - ফ্র্যাঞ্চাইজ', 'Franchise (EXAMPLE)', 'বিক্রির উপর রয়্যালটি + মাসিক ফি; বাকি লাভ ফ্র্যাঞ্চাইজির। সংখ্যাগুলো উদাহরণ - বদলান।', 'Royalty on net sales + a monthly fee; the rest of the profit stays with the franchisee. Numbers are EXAMPLES - change them.', 'franchise',
  '[{"no":1,"title_bn":"চুক্তির উদ্দেশ্য","title_en":"Purpose","text_bn":"(এখানে লিখুন)","text_en":"(write here)"},{"no":2,"title_bn":"রয়্যালটি ও ফি","title_en":"Royalty and fee","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","franchisee"]'::jsonb,
  '[{"name":"Base: profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Royalty on net sales (EXAMPLE 5%)","kind":"royalty","config":{"role":"owner","percent":5,"base":"net_sales"}},
    {"name":"Monthly fee (EXAMPLE 10000)","kind":"management_fee","config":{"role":"owner","fixed":10000,"per":"month"}},
    {"name":"Rest to franchisee","kind":"split","config":{"shares":[{"role":"franchisee","percent":100}]}}]'::jsonb, true, false),
 ('investor_payback', 'উদাহরণ - বিনিয়োগকারীর পুঁজি ফেরত', 'Investor payback (EXAMPLE)', 'পুঁজি ফেরত না আসা পর্যন্ত লাভের একটি অংশ বিনিয়োগকারীর, তারপর কম অংশ। সংখ্যা উদাহরণ।', 'A share of profit goes to the investor until the capital is paid back, then a smaller share. Numbers are EXAMPLES.', 'funded',
  '[{"no":1,"title_bn":"বিনিয়োগ","title_en":"Investment","text_bn":"(এখানে লিখুন)","text_en":"(write here)"},{"no":2,"title_bn":"পুঁজি ফেরত","title_en":"Payback","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","investor"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Carry earlier losses","kind":"loss_carry_forward","config":{}},
    {"name":"Investor payback (EXAMPLE 50% then 20%)","kind":"payback","config":{"role":"investor","percent":50,"then_percent":20}},
    {"name":"Rest to owner","kind":"split","config":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb, true, false),
 ('partnership_5050', 'উদাহরণ - ৫০/৫০ অংশীদারি', '50/50 partnership (EXAMPLE)', 'ক্ষতি পরের মাসে টেনে নিয়ে বাকি লাভ সমান ভাগ। ভাগের হার উদাহরণ।', 'Losses are carried forward; the rest of the profit is split equally. The split is an EXAMPLE.', 'partnership',
  '[{"no":1,"title_bn":"মূলধন ও দায়িত্ব","title_en":"Capital and duties","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","partner"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Carry earlier losses","kind":"loss_carry_forward","config":{}},
    {"name":"Split (EXAMPLE 50/50)","kind":"split","config":{"shares":[{"role":"owner","percent":50},{"role":"partner","percent":50}]}}]'::jsonb, true, false),
 ('fixed_return_loan', 'উদাহরণ - নির্দিষ্ট রিটার্নের ঋণ', 'Fixed-return loan (EXAMPLE)', 'ঋণদাতা পুঁজির উপর বছরে নির্দিষ্ট % পান (ঘাটতি পরে মেটে); বাকি লাভ মালিকের। হার উদাহরণ।', 'The lender gets a fixed yearly % on the loan (a shortfall is caught up later); the rest of the profit is the owner''s. The rate is an EXAMPLE.', 'loan',
  '[{"no":1,"title_bn":"ঋণ ও সুদ/রিটার্ন","title_en":"Loan and return","text_bn":"(এখানে লিখুন)","text_en":"(write here)"}]'::jsonb,
  '["owner","lender"]'::jsonb,
  '[{"name":"Base: net profit before fees","kind":"base","config":{"base":"net_profit_before_fees"}},
    {"name":"Lender return (EXAMPLE 12% a year, catch-up)","kind":"priority_return","config":{"role":"lender","percent_per_year":12,"catch_up":true}},
    {"name":"Rest to owner","kind":"split","config":{"shares":[{"role":"owner","percent":100}]}}]'::jsonb, true, false)
) v(code, name_bn, name_en, description_bn, description_en, model, clauses, roles, rules, is_example, active)
where not exists (select 1 from public.partner_templates t where t.code = v.code);

-- ============================================================
-- 13. grants
-- ============================================================
revoke all on function public._a44_guard(), public._a44_n(jsonb), public._a44_today(), public._a44_chk_date(date), public._a44_chk_money(numeric), public._a44_chain(bigint),
  public._a44_months(date, date), public._a44_round(numeric, numeric, text), public._a44_ref(bigint, jsonb), public._a44_need(bigint, jsonb, text),
  public._a44_distribute(bigint, numeric, jsonb, numeric, text, text), public._a44_party_total(jsonb, bigint, boolean), public._a44_cap(bigint, bigint, date),
  public._a44_capdays(bigint, bigint, date, date), public._a44_step_hist(bigint, date, text), public._a44_vref(jsonb), public._a44_vshares(jsonb), public._a44_clauses_ok(jsonb),
  public._a44_check_ready(bigint), public._a44_agr_guard(), public._a44_child_guard(), public._a44_ro(), public._a44_cap_guard(), public._a44_set_guard(), public._a44_line_guard()
  from public, anon, authenticated;
revoke all on function public.partner_rule_validate(text, jsonb), public.partner_party_save(bigint, text, text, text, text, text, text, text, text, boolean, uuid),
  public.partner_venture_save(bigint, text, text, text, int, text, date, date, text, text, uuid), public.partner_agreement_save(bigint, bigint, text, date, date, jsonb, text, uuid),
  public.partner_agreement_party_set(bigint, bigint, text, numeric, text, boolean), public.partner_rule_save(bigint, int, text, text, jsonb, boolean), public.partner_rules_reorder(bigint, jsonb),
  public.partner_agreement_activate(bigint, boolean), public.partner_agreement_amend(bigint, uuid), public.partner_agreement_close(bigint, text, date),
  public.partner_agreement_from_template(bigint, text, text, uuid), public.partner_capital_add(bigint, bigint, text, numeric, date, text, text, text, uuid), public.partner_capital_void(bigint, text),
  public.partner_capital_balances(bigint, date), public.partner_calculate(bigint, date, date, jsonb), public.partner_settlement_save(bigint, date, date, jsonb, text, uuid),
  public.partner_settlement_approve(bigint), public.partner_settlement_void(bigint, text), public.partner_settlement_pay(bigint, numeric, text, date, text, uuid),
  public.partner_party_statement(bigint, date, date), public.partner_overview() from public, anon;
grant execute on function public.partner_rule_validate(text, jsonb), public.partner_party_save(bigint, text, text, text, text, text, text, text, text, boolean, uuid),
  public.partner_venture_save(bigint, text, text, text, int, text, date, date, text, text, uuid), public.partner_agreement_save(bigint, bigint, text, date, date, jsonb, text, uuid),
  public.partner_agreement_party_set(bigint, bigint, text, numeric, text, boolean), public.partner_rule_save(bigint, int, text, text, jsonb, boolean), public.partner_rules_reorder(bigint, jsonb),
  public.partner_agreement_activate(bigint, boolean), public.partner_agreement_amend(bigint, uuid), public.partner_agreement_close(bigint, text, date),
  public.partner_agreement_from_template(bigint, text, text, uuid), public.partner_capital_add(bigint, bigint, text, numeric, date, text, text, text, uuid), public.partner_capital_void(bigint, text),
  public.partner_capital_balances(bigint, date), public.partner_calculate(bigint, date, date, jsonb), public.partner_settlement_save(bigint, date, date, jsonb, text, uuid),
  public.partner_settlement_approve(bigint), public.partner_settlement_void(bigint, text), public.partner_settlement_pay(bigint, numeric, text, date, text, uuid),
  public.partner_party_statement(bigint, date, date), public.partner_overview() to authenticated;

-- ---------------------------------------------------------------- phase45.sql
-- Phase 45 · Module E: Owner mode board (customisable "must check" list).
-- Per-user widget list for the owner. The widget KINDS live in web/ownerboard.js (data-driven); this file stores which ones the owner picked,
-- their order, size, thresholds and notes. Additive + idempotent. Writes go only through owner_board_save (SECURITY DEFINER, owner only).
--   owner_board_get()        -> jsonb array of this owner's widgets (sorted)              [owner only]
--   owner_board_save(items)  -> replaces this owner's list atomically, returns the count   [owner only, max 60, validated]
-- Switch: rules key owner_board_on (default ON). OFF = the save is refused and the web page falls back to the normal Home.

create table if not exists public.owner_board_items (
  id bigserial primary key,
  user_id uuid not null,
  widget text not null,
  config jsonb not null default '{}'::jsonb,
  sort int not null default 0,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint owner_board_widget_chk check (widget ~ '^[a-z][a-z0-9_]{1,40}$'),
  constraint owner_board_config_chk check (jsonb_typeof(config) = 'object')
);
create index if not exists owner_board_items_user_idx on public.owner_board_items (user_id, sort);

alter table public.owner_board_items enable row level security;
drop policy if exists owner_board_sel on public.owner_board_items;
create policy owner_board_sel on public.owner_board_items for select to authenticated using (user_id = auth.uid() and public.is_owner());
revoke all on public.owner_board_items from public, anon, authenticated;
grant select on public.owner_board_items to authenticated;
revoke all on sequence public.owner_board_items_id_seq from public, anon, authenticated;

drop trigger if exists audit_owner_board_items on public.owner_board_items;
create trigger audit_owner_board_items after insert or update on public.owner_board_items for each row execute function public.log_change('id');

-- the setting (owner can flip it in #/switchboard)
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_board_on', 'ui', 'switch', 'true', null, null, null, null, 'মালিকের বোর্ড (প্রতিদিন যা দেখতে হবে)', 'Owner-এর board (প্রতিদিন যা দেখতে হবে)', 'Owner mode board (what to check every day)',
  'বন্ধ করলে বোর্ড লুকানো থাকে ও সেভ হয় না; হোম আগের মতো।', 'Off = the board is hidden and cannot be saved; Home stays as before.', 96)
on conflict (key) do nothing;

-- every widget kind the web page knows (the page hides the ones whose module is not installed)
create or replace function public._ob_kinds() returns text[]
language sql immutable set search_path = public as $$
  select array['sales_vs','cash_short','day_close','needs_you','exceptions','approvals','cust_dues','supp_dues','stock_low','wastage','voids_disc','unsent','top_sellers','parallel','rollout','backup','notifications','attendance','payroll','balance_check','report','page','counter','note']::text[];
$$;

create or replace function public.owner_board_get() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'widget', i.widget, 'config', i.config, 'sort', i.sort, 'enabled', i.enabled, 'updated_at', i.updated_at) order by i.sort, i.id)
                     from public.owner_board_items i where i.user_id = auth.uid()), '[]'::jsonb);
end $$;

-- p_items: [{widget, config?, enabled?}] in the wanted order (sort is set from the position)
create or replace function public.owner_board_save(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it jsonb; n int := 0; w text; cfg jsonb; k text; v jsonb; en boolean; kinds text[] := public._ob_kinds();
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('owner_board_on') then raise exception 'feature_off'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 60 then raise exception 'too_many_items'; end if;
  -- validate everything first, write after (atomic anyway: one transaction)
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then raise exception 'bad_item'; end if;
    w := it ->> 'widget';
    if w is null or not (w = any (kinds)) then raise exception 'bad_widget'; end if;
    cfg := coalesce(it -> 'config', '{}'::jsonb);
    if jsonb_typeof(cfg) <> 'object' then raise exception 'bad_config'; end if;
    if octet_length(cfg::text) > 4000 then raise exception 'config_too_big'; end if;
    for k, v in select * from jsonb_each(cfg) loop
      if k in ('warn_gt', 'bad_gt', 'warn_lt', 'bad_lt') then
        if jsonb_typeof(v) not in ('number', 'null') then raise exception 'bad_threshold'; end if;
        if jsonb_typeof(v) = 'number' and abs((v #>> '{}')::numeric) > 1e12 then raise exception 'bad_threshold'; end if;
      elsif k = 'size' then
        if v #>> '{}' not in ('compact', 'wide') then raise exception 'bad_size'; end if;
      elsif k in ('label', 'text', 'route', 'report', 'table', 'preset', 'repeat', 'done_on') then
        if jsonb_typeof(v) <> 'string' and jsonb_typeof(v) <> 'null' then raise exception 'bad_config'; end if;
        if length(coalesce(v #>> '{}', '')) > (case when k = 'text' then 300 else 120 end) then raise exception 'text_too_long'; end if;
      end if;
    end loop;
    if cfg ? 'repeat' and (cfg ->> 'repeat') not in ('daily', 'weekly', 'never') then raise exception 'bad_repeat'; end if;
    if it ? 'enabled' and jsonb_typeof(it -> 'enabled') <> 'boolean' then raise exception 'bad_item'; end if;
  end loop;
  delete from public.owner_board_items where user_id = auth.uid();
  for it in select * from jsonb_array_elements(p_items) loop
    en := coalesce((it ->> 'enabled')::boolean, true);
    insert into public.owner_board_items (user_id, widget, config, sort, enabled, updated_at)
      values (auth.uid(), it ->> 'widget', coalesce(it -> 'config', '{}'::jsonb), n, en, now());
    n := n + 1;
  end loop;
  return jsonb_build_object('count', n);
end $$;

revoke all on function public._ob_kinds() from public, anon, authenticated;
revoke all on function public.owner_board_get(), public.owner_board_save(jsonb) from public, anon;
grant execute on function public.owner_board_get(), public.owner_board_save(jsonb) to authenticated;

-- ============================================================
-- Home favourites in the ⋮ menu: order, own label and "hide from Home" per person (synced with the existing user_favourites rows)
-- ============================================================
alter table public.user_favourites add column if not exists sort int;
alter table public.user_favourites add column if not exists label text;
alter table public.user_favourites add column if not exists hidden boolean not null default false;

-- p_items: [{kind, key}] in the wanted order; the caller's own rows get sort = position (missing rows are created as pinned)
create or replace function public.fav_order_set(p_items jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare it jsonb; n int := 0; k text; ky text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  if jsonb_array_length(p_items) > 200 then raise exception 'too_many_items'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(it) <> 'object' then raise exception 'bad_item'; end if;
    k := it ->> 'kind'; ky := it ->> 'key';
    if k is null or k not in ('route', 'form') or ky is null or length(ky) = 0 or length(ky) > 120 then raise exception 'bad_item'; end if;
  end loop;
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.user_favourites (user_id, kind, key, pinned, sort) values (auth.uid(), it ->> 'kind', it ->> 'key', true, n)
      on conflict (user_id, kind, key) do update set sort = excluded.sort;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.fav_meta_set(p_kind text, p_key text, p_label text, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
declare lb text := nullif(btrim(coalesce(p_label, '')), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('route', 'form') or p_key is null or length(p_key) = 0 or length(p_key) > 120 then raise exception 'bad_item'; end if;
  if lb is not null and length(lb) > 40 then raise exception 'label_too_long'; end if;
  insert into public.user_favourites (user_id, kind, key, pinned, label, hidden) values (auth.uid(), p_kind, p_key, false, lb, coalesce(p_hidden, false))
    on conflict (user_id, kind, key) do update set label = excluded.label, hidden = excluded.hidden;
end $$;

revoke all on function public.fav_order_set(jsonb), public.fav_meta_set(text, text, text, boolean) from public, anon;
grant execute on function public.fav_order_set(jsonb), public.fav_meta_set(text, text, text, boolean) to authenticated;

-- ---------------------------------------------------------------- phase46.sql
-- ============================================================
-- Phase 46 - Module F: automatic backup + notifications (in-app bell, Gmail digest / alerts)
-- Run AFTER phase28. Additive and idempotent (paste it twice = no error). Nothing is hard-deleted.
--
-- Who does what
--   * The OWNER marks one dedicated, least-privilege Supabase Auth user as the "ops bot":  select ops_account_set('<user uuid>', 'backup', true);
--     (and 'notify'). The bot is NOT an owner, has no roles and sees no tables directly. It can call only the functions below.
--     The service_role key is never used.
--   * backup_dump / backup_manifest / backup_log  -> bot with purpose 'backup'  (GitHub Actions, tools/backup_dump.py)
--   * notify_scan / daily_digest / urgent_alerts / notifications_mark_emailed / notify_config -> bot with purpose 'notify' (or the owner)
--   * notifications_for_me / notification_read / notification_read_all / notifications_unread_count -> every active user (the bell)
--
-- Backup whitelist (backup_dump / backup_manifest): every BASE TABLE in schema public EXCEPT
--     - names containing "_secret", names starting "ops_"
--     - login data: login_failures, login_attempts, login_throttle
--     - the module's own run-time tables: backup_runs, notifications, notification_reads (re-created by the app; not business records)
--     - any table that has a column named like password / passwd / pin_hash / secret / token / salt / api_key / private_key
--   The list is computed at call time (public._backup_tables()), so new tables are included automatically.
--   Schemas auth / storage are never included (only schema public is read).
--
-- Rules (Switchboard / Settings): notify_*  switches and thresholds, day_close_deadline, backup_max_age_hours, notify_digest_times.
-- Timezone: Asia/Dhaka for "today". Money is numeric, rounded to 2.
-- ============================================================

-- ---------- ops accounts ----------
create table if not exists public.ops_accounts (
  user_id uuid not null references public.profiles(id),
  purpose text not null check (purpose in ('backup', 'notify')),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (user_id, purpose)
);
create table if not exists public.backup_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(), finished_at timestamptz not null default now(),
  status text not null check (status in ('ok', 'failed', 'partial')),
  tables int, rows bigint, bytes bigint,
  detail jsonb not null default '{}'::jsonb,
  destination text not null default 'github',
  logged_by uuid
);
create table if not exists public.notifications (
  id bigserial primary key,
  user_id uuid references public.profiles(id),                       -- null = everybody the audience covers
  audience text not null default 'owner' check (audience in ('owner', 'manager', 'all')),
  kind text not null check (kind ~ '^[a-z_]{2,40}$'),
  level text not null default 'info' check (level in ('info', 'warn', 'bad')),
  title_bn text not null, title_en text not null, body_bn text, body_en text,
  route text, location_id int references public.locations(id),
  key text not null default '' check (length(key) <= 80),
  day date not null default ((now() at time zone 'Asia/Dhaka')::date),
  created_at timestamptz not null default now(),
  read_at timestamptz, read_by uuid,                                  -- only for a note aimed at one user; per-user reads live in notification_reads
  emailed_at timestamptz,
  unique (kind, key, day)
);
create index if not exists notifications_recent on public.notifications (id desc);
create table if not exists public.notification_reads (
  notification_id bigint not null references public.notifications(id),
  user_id uuid not null, read_at timestamptz not null default now(),
  primary key (notification_id, user_id)
);

do $$ declare t text; begin
  foreach t in array array['ops_accounts', 'backup_runs', 'notifications', 'notification_reads'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
revoke usage, select on sequence public.backup_runs_id_seq, public.notifications_id_seq from public, anon, authenticated;

drop trigger if exists audit_ops_accounts on public.ops_accounts;
create trigger audit_ops_accounts after insert or update on public.ops_accounts for each row execute function public.log_change('user_id,purpose');

-- ---------- helpers (not callable from the browser) ----------
create or replace function public._is_ops(p_purpose text) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.ops_accounts o where o.user_id = auth.uid() and o.purpose = p_purpose and o.active);
$$;
create or replace function public._today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- who may see a note: aimed at me, or for everybody its audience covers (and the place, when it names one)
create or replace function public._notif_ok(p_user uuid, p_aud text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    case when p_user is not null then p_user = auth.uid()
         else (p_aud = 'all'
               or public.is_owner()
               or (p_aud = 'manager' and exists (select 1 from public.user_roles r where r.user_id = auth.uid()
                     and r.role_code in ('management', 'showroom_manager', 'cash_controller', 'factory_incharge', 'purchasing', 'hr')))) end
    and (p_loc is null or p_user is not null or public.can_loc(p_loc)));
$$;

drop policy if exists ops_accounts_read on public.ops_accounts;
create policy ops_accounts_read on public.ops_accounts for select to authenticated using (public.is_owner());
drop policy if exists backup_runs_read on public.backup_runs;
create policy backup_runs_read on public.backup_runs for select to authenticated using (public.is_owner());
drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications for select to authenticated using (public._notif_ok(user_id, audience, location_id));
drop policy if exists notification_reads_read on public.notification_reads;
create policy notification_reads_read on public.notification_reads for select to authenticated using (user_id = auth.uid());

-- the owner marks (or retires) an ops bot
create or replace function public.ops_account_set(p_user uuid, p_purpose text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_purpose not in ('backup', 'notify') or p_active is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then raise exception 'owner_cannot_be_bot'; end if;
  insert into public.ops_accounts (user_id, purpose, active, created_by) values (p_user, p_purpose, p_active, auth.uid())
    on conflict (user_id, purpose) do update set active = excluded.active, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'purpose', p_purpose, 'active', p_active);
end $$;

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('notify_on', 'notify', 'switch', 'true', null, null, null, null, 'নোটিফিকেশন (ঘণ্টা-আইকন)', 'Notification (bell)', 'Notifications (the bell)', 'বন্ধ করলে অ্যাপে নতুন নোটিফিকেশন তৈরি হবে না।', 'Off = no new notifications are made.', 300),
 ('notify_email_on', 'notify', 'switch', 'true', null, null, null, null, 'জিমেইলে জরুরি সতর্কতা ও দৈনিক সারাংশ', 'Gmail-এ জরুরি alert ও daily digest', 'Gmail urgent alerts and daily digest', 'বন্ধ করলে ইমেইল যাবে না (অ্যাপের ঘণ্টা চলবে)।', 'Off = no email is sent (the bell keeps working).', 301),
 ('notify_digest_times', 'notify', 'choice', '"08,21"', null, '["off","08","21","08,21"]', null, null, 'দৈনিক সারাংশ ইমেইলের সময় (ঢাকা, ঘণ্টা)', 'Daily digest email সময় (Dhaka, ঘণ্টা)', 'Daily digest email hours (Dhaka)', 'সকাল ৮টা, রাত ৯টা, দুটোই, অথবা বন্ধ।', '08 = 8am, 21 = 9pm, both, or off.', 302),
 ('notify_exceptions_on', 'notify', 'switch', 'true', null, null, null, null, 'লাল এক্সেপশন অনেকক্ষণ খোলা থাকলে জানান', 'Red exception অনেকক্ষণ open থাকলে জানান', 'Tell me when red exceptions stay open', null, null, 310),
 ('notify_exceptions_hours', 'notify', 'number', '24', 'ঘণ্টা', null, 1, 720, 'লাল এক্সেপশন কত ঘণ্টা খোলা থাকলে', 'Red exception কত ঘণ্টা open থাকলে', 'Red exception open for more than (hours)', null, null, 311),
 ('notify_approvals_on', 'notify', 'switch', 'true', null, null, null, null, 'অনুমোদন বাকি থাকলে জানান', 'Approval বাকি থাকলে জানান', 'Tell me when approvals wait too long', null, null, 312),
 ('notify_approvals_hours', 'notify', 'number', '24', 'ঘণ্টা', null, 1, 720, 'অনুমোদন কত ঘণ্টা বাকি থাকলে', 'Approval কত ঘণ্টা বাকি থাকলে', 'Approval waiting for more than (hours)', null, null, 313),
 ('notify_lowstock_on', 'notify', 'switch', 'true', null, null, null, null, 'কম স্টকের সতর্কতা', 'Low stock alert', 'Low stock alert', null, null, 314),
 ('notify_lowstock_min', 'notify', 'number', '1', 'আইটেম', null, 1, 10000, 'কমপক্ষে কয়টি আইটেম কম হলে জানাবেন', 'কমপক্ষে কয়টি item কম হলে', 'Alert when at least this many items are low', null, null, 315),
 ('notify_expiry_on', 'notify', 'switch', 'true', null, null, null, null, 'মেয়াদ শেষ হতে চলা ব্যাচের সতর্কতা', 'মেয়াদ শেষ হতে চলা batch-এর alert', 'Expiring batches alert', null, null, 316),
 ('notify_expiry_days', 'notify', 'number', '3', 'দিন', null, 0, 365, 'মেয়াদ শেষের কত দিন আগে', 'মেয়াদ শেষের কত দিন আগে', 'Days before expiry', null, null, 317),
 ('notify_supdue_on', 'notify', 'switch', 'true', null, null, null, null, 'সরবরাহকারীর মেয়াদোত্তীর্ণ পাওনা', 'Supplier-এর overdue পাওনা', 'Overdue supplier dues', null, null, 318),
 ('notify_supdue_min', 'notify', 'number', '1000', '৳', null, 0, 1000000000, 'মেয়াদোত্তীর্ণ পাওনা কত টাকার বেশি হলে', 'Overdue কত টাকার বেশি হলে', 'Overdue amount above (৳)', null, null, 319),
 ('notify_credit_on', 'notify', 'switch', 'true', null, null, null, null, 'গ্রাহকের বাকির সীমা পার হলে', 'Customer-এর credit limit পার হলে', 'Customer credit limit breached', null, null, 320),
 ('notify_dayclose_on', 'notify', 'switch', 'true', null, null, null, null, 'দিন-শেষের হিসাব (১৪-১) জমা না হলে', 'Day-close (14-1) জমা না হলে', 'Shop has not closed the day (14-1)', null, null, 321),
 ('day_close_deadline', 'notify', 'text', '"22:00"', null, null, null, null, 'দিন-শেষ জমার শেষ সময় (HH:MM, ঢাকা)', 'Day-close deadline (HH:MM, Dhaka)', 'Day-close deadline (HH:MM, Dhaka)', 'যেমন 22:00। এর পরেও জমা না হলে জানানো হয়।', 'Example 22:00. A shop that has not closed by then is reported.', 322),
 ('notify_wastage_on', 'notify', 'switch', 'true', null, null, null, null, 'অপচয় হঠাৎ বাড়লে জানান', 'Wastage হঠাৎ বাড়লে জানান', 'Wastage spike alert', null, null, 323),
 ('notify_wastage_factor', 'notify', 'number', '3', 'গুণ', null, 1, 100, 'আগের ৭ দিনের গড়ের কত গুণ হলে', 'আগের ৭ দিনের গড়ের কত গুণ', 'Times the previous 7-day average', null, null, 324),
 ('notify_wastage_min', 'notify', 'number', '1000', '৳', null, 0, 1000000000, 'অপচয় কত টাকার কম হলে জানাবেন না', 'Wastage কত টাকার কম হলে চুপ থাকবে', 'Ignore wastage below (৳)', null, null, 325),
 ('notify_cash_on', 'notify', 'switch', 'true', null, null, null, null, 'বড় ক্যাশ কম/বেশি হলে', 'বড় cash কম/বেশি হলে', 'Big cash short / over', null, null, 326),
 ('notify_cash_limit', 'notify', 'number', '500', '৳', null, 0, 1000000000, 'ক্যাশ কম/বেশি কত টাকার বেশি হলে', 'Cash কম/বেশি কত টাকার বেশি হলে', 'Cash short / over above (৳)', null, null, 327),
 ('notify_parallel_on', 'notify', 'switch', 'true', null, null, null, null, 'পাশাপাশি মাসের সিদ্ধান্ত বাকি থাকলে', 'Parallel month-এর decision বাকি থাকলে', 'Parallel-month decision waiting', null, null, 328),
 ('notify_backup_on', 'notify', 'switch', 'true', null, null, null, null, 'ব্যাকআপ পুরনো বা ব্যর্থ হলে জানান', 'Backup পুরনো বা failed হলে জানান', 'Backup stale or failed', null, null, 329),
 ('backup_max_age_hours', 'notify', 'number', '36', 'ঘণ্টা', null, 1, 720, 'শেষ সফল ব্যাকআপ কত ঘণ্টার পুরনো হলে সতর্কতা', 'শেষ OK backup কত ঘণ্টার পুরনো হলে alert', 'Alert when the last OK backup is older than (hours)', null, null, 330)
 on conflict (key) do nothing;

-- ---------- backup: whitelist, manifest, dump, log ----------
create or replace function public._backup_tables() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.relname::text order by c.relname), '{}'::text[])
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relispartition
     and c.relname::text not like '%\_secret%' escape '\'
     and c.relname::text not like 'ops\_%' escape '\'
     and c.relname::text not in ('login_failures', 'login_attempts', 'login_throttle', 'backup_runs', 'notifications', 'notification_reads')
     and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and a.attname::text ~* '(password|passwd|pin_hash|secret|token|salt|api_key|private_key)');
$$;

create or replace function public.backup_manifest() returns jsonb
language plpgsql security definer set search_path = public as $$
declare t text; n bigint; mx timestamptz; tabs jsonb := '[]'::jsonb; total bigint := 0; fp text; mxcol text;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  foreach t in array public._backup_tables() loop
    execute format('select count(*) from public.%I', t) into n;
    mxcol := (select a.attname::text from pg_attribute a where a.attrelid = ('public.' || quote_ident(t))::regclass and a.attname::text in ('updated_at', 'created_at') and not a.attisdropped order by a.attname::text desc limit 1);
    mx := null;
    if mxcol is not null then execute format('select max(%I) from public.%I', mxcol, t) into mx; end if;
    tabs := tabs || jsonb_build_object('name', t, 'rows', n, 'max_updated_at', mx,
      'columns_md5', (select md5(string_agg(a.attname::text || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum)) from pg_attribute a where a.attrelid = ('public.' || quote_ident(t))::regclass and a.attnum > 0 and not a.attisdropped));
    total := total + n;
  end loop;
  select md5(coalesce(string_agg(c.relname::text || '.' || a.attname::text || ':' || format_type(a.atttypid, a.atttypmod), ',' order by c.relname, a.attnum), '')) into fp
    from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
   where c.relnamespace = 'public'::regnamespace and c.relname::text = any (public._backup_tables());
  return jsonb_build_object('schema_version', 46, 'generated_at', now(), 'fingerprint', fp, 'table_count', jsonb_array_length(tabs), 'rows', total, 'tables', tabs);
end $$;

-- p_after_id is the cursor the previous call returned in "next" (a JSON array of the primary-key values, or "off:N" for a table without a primary key).
create or replace function public.backup_dump(p_table text, p_after_id text default null, p_limit int default 2000) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int; pk text[]; pt text[]; cols text; keyexpr text; cond text := ''; vals text; cur jsonb; i int;
        rows_ jsonb; last_k text; cnt int; total bigint; nxt text; off_ bigint := 0;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if p_table is null or not (p_table = any (public._backup_tables())) then raise exception 'table_not_allowed'; end if;
  lim := least(greatest(coalesce(p_limit, 2000), 1), 5000);
  select array_agg(a.attname::text order by k.ord), array_agg(format_type(a.atttypid, a.atttypmod) order by k.ord) into pk, pt
    from pg_index ix cross join lateral unnest(ix.indkey::int2[]) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = ix.indrelid and a.attnum = k.attnum
   where ix.indrelid = ('public.' || quote_ident(p_table))::regclass and ix.indisprimary;
  execute format('select count(*) from public.%I', p_table) into total;
  if pk is null then
    if p_after_id is not null then
      if p_after_id !~ '^off:[0-9]{1,12}$' then raise exception 'bad_cursor'; end if;
      off_ := substr(p_after_id, 5)::bigint;
    end if;
    execute format('select coalesce(jsonb_agg(j order by rn), ''[]''::jsonb), count(*) from (select to_jsonb(t) j, row_number() over (order by to_jsonb(t)::text) rn from public.%I t order by to_jsonb(t)::text offset %s limit %s) x', p_table, off_, lim) into rows_, cnt;
    nxt := case when cnt = lim then 'off:' || (off_ + lim) end;
  else
    cols := (select string_agg(format('t.%I', c), ', ') from unnest(pk) c);
    keyexpr := 'jsonb_build_array(' || cols || ')';
    if p_after_id is not null then
      begin cur := p_after_id::jsonb; exception when others then raise exception 'bad_cursor'; end;
      if jsonb_typeof(cur) <> 'array' or jsonb_array_length(cur) <> array_length(pk, 1) then raise exception 'bad_cursor'; end if;
      vals := '';
      for i in 1 .. array_length(pk, 1) loop vals := vals || case when i > 1 then ', ' else '' end || format('%L::%s', cur ->> (i - 1), pt[i]); end loop;
      cond := format(' where (%s) > (%s)', cols, vals);
    end if;
    execute format('select coalesce(jsonb_agg(j order by rn), ''[]''::jsonb), count(*), (array_agg(k::text order by rn desc))[1] from (select to_jsonb(t) j, %s k, row_number() over (order by %s) rn from public.%I t%s order by %s limit %s) x',
                   keyexpr, cols, p_table, cond, cols, lim) into rows_, cnt, last_k;
    nxt := case when cnt = lim then last_k end;
  end if;
  return jsonb_build_object('table', p_table, 'rows', rows_, 'next', nxt, 'total', total);
end $$;

create or replace function public.backup_log(p_status text, p_detail jsonb default '{}'::jsonb, p_started timestamptz default null, p_tables int default null,
                                             p_rows bigint default null, p_bytes bigint default null, p_destination text default 'github') returns bigint
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not public._is_ops('backup') then raise exception 'not allowed'; end if;
  if p_status not in ('ok', 'failed', 'partial') then raise exception 'bad_status'; end if;
  if p_detail is not null and pg_column_size(p_detail) > 200000 then raise exception 'detail_too_big'; end if;
  if coalesce(p_tables, 0) < 0 or coalesce(p_rows, 0) < 0 or coalesce(p_bytes, 0) < 0 then raise exception 'bad_input'; end if;
  insert into public.backup_runs (started_at, status, tables, rows, bytes, detail, destination, logged_by)
    values (coalesce(least(p_started, now()), now()), p_status, p_tables, p_rows, p_bytes, coalesce(p_detail, '{}'::jsonb), left(coalesce(nullif(btrim(p_destination), ''), 'github'), 40), auth.uid())
    returning id into rid;
  return rid;
end $$;

-- last runs and whether the newest OK run is too old (owner or the backup / notify bot)
create or replace function public.backup_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lastok record; lastrun record; maxh numeric := coalesce(public.rule_num('backup_max_age_hours'), 36); age numeric; configured boolean;
begin
  if not (public.is_owner() or public._is_ops('backup') or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  select * into lastok from public.backup_runs where status = 'ok' order by finished_at desc, id desc limit 1;
  select * into lastrun from public.backup_runs order by finished_at desc, id desc limit 1;
  configured := exists (select 1 from public.ops_accounts where purpose = 'backup' and active);
  age := case when lastok.id is null then null else round(extract(epoch from (now() - lastok.finished_at)) / 3600, 1) end;
  return jsonb_build_object('configured', configured, 'max_age_hours', maxh, 'age_hours', age,
    'last_ok', case when lastok.id is null then null else jsonb_build_object('at', lastok.finished_at, 'tables', lastok.tables, 'rows', lastok.rows, 'bytes', lastok.bytes, 'destination', lastok.destination) end,
    'last_run', case when lastrun.id is null then null else jsonb_build_object('at', lastrun.finished_at, 'status', lastrun.status) end,
    'failed_last', coalesce(lastrun.status = 'failed', false),
    'stale', configured and (age is null or age > maxh));
end $$;

-- ---------- notifications ----------
create or replace function public._notif_add(p_kind text, p_level text, p_tbn text, p_ten text, p_bbn text, p_ben text, p_route text, p_key text, p_aud text, p_loc int) returns boolean
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.notifications (audience, kind, level, title_bn, title_en, body_bn, body_en, route, location_id, key)
    values (p_aud, p_kind, p_level, p_tbn, p_ten, p_bbn, p_ben, p_route, p_loc, left(coalesce(p_key, ''), 80))
    on conflict (kind, key, day) do nothing;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- Generates today's notifications from existing data. Idempotent per day: (kind, key, day) is unique, so a second run adds nothing.
-- Every kind has a switch and thresholds (rules notify_*). Optional tables are guarded with to_regclass.
create or replace function public.notify_scan() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := public._today(); nowd timestamp := (now() at time zone 'Asia/Dhaka');
  made jsonb := '{}'::jsonb; cnt int; amt numeric; hrs numeric; r record; dl text; dl_t time; st jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_on') then return jsonb_build_object('created', 0, 'kinds', '{}'::jsonb, 'off', true); end if;

  -- 1. red exceptions open too long
  if public.rule_on('notify_exceptions_on') then
    hrs := coalesce(public.rule_num('notify_exceptions_hours'), 24);
    select count(*), round(max(extract(epoch from (now() - created_at)) / 3600)) into cnt, amt from public.exceptions where level = 'red' and status = 'open' and created_at < now() - make_interval(secs => hrs * 3600);
    if cnt > 0 and public._notif_add('red_exceptions', 'bad', cnt || 'টি লাল এক্সেপশন খোলা পড়ে আছে', cnt || ' red exception(s) still open',
         'সবচেয়ে পুরনোটি ' || amt || ' ঘণ্টা ধরে খোলা। দেখে নিষ্পত্তি করুন।', 'The oldest has been open ' || amt || ' hours. Please look and resolve.', 'exceptions', 'all', 'owner', null) then
      made := made || jsonb_build_object('red_exceptions', 1); end if;
  end if;

  -- 2. approvals waiting too long (same sources as phase 28 needs_you_oldest, for the owner's whole view)
  if public.rule_on('notify_approvals_on') then
    hrs := coalesce(public.rule_num('notify_approvals_hours'), 24);
    select count(*), round(max(extract(epoch from (now() - s)) / 3600)) into cnt, amt from (
      select coalesce(e.submitted_at, e.created_at) s from public.entries e where e.status = 'submitted'
      union all select rq.requested_at from public.release_requests rq where rq.status = 'pending'
      union all select q.created_at from public.emergency_requests q where q.status = 'pending'
      union all select c.requested_at from public.item_changes c where c.status = 'pending'
      union all select p.created_at from public.profiles p where p.status = 'pending'
      union all select w.requested_at from public.wastage_requests w where w.status = 'pending') u
     where u.s < now() - make_interval(secs => hrs * 3600);
    if cnt > 0 and public._notif_add('approvals_waiting', 'warn', cnt || 'টি অনুমোদন অপেক্ষায়', cnt || ' approval(s) waiting',
         'সবচেয়ে পুরনোটি ' || amt || ' ঘণ্টা ধরে অপেক্ষায়।', 'The oldest has waited ' || amt || ' hours.', 'pending', 'all', 'owner', null) then
      made := made || jsonb_build_object('approvals_waiting', 1); end if;
  end if;

  -- 3. low stock (per place)
  if public.rule_on('notify_lowstock_on') then
    for r in select b.location_id, count(*) c from public.stock_balance b join public.items i on i.id = b.item_id join public.locations l on l.id = b.location_id
              where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock and l.is_active and l.status = 'live'
              group by b.location_id having count(*) >= coalesce(public.rule_num('notify_lowstock_min'), 1) loop
      if public._notif_add('low_stock', 'warn', r.c || 'টি আইটেমের স্টক কম', r.c || ' item(s) low in stock', 'ন্যূনতম স্টকের নিচে নেমেছে।', 'At or below the minimum stock.', 'stock', r.location_id::text, 'manager', r.location_id) then
        made := made || jsonb_build_object('low_stock', coalesce((made ->> 'low_stock')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 4. batches about to expire (per place)
  if public.rule_on('notify_expiry_on') then
    for r in select b.location_id, count(*) c, min(b.expires_at) first_at from public.stock_batches b join public.items i on i.id = b.item_id
              where b.qty_remaining > 0 and b.expires_at is not null and b.expires_at < now() + make_interval(days => coalesce(public.rule_num('notify_expiry_days'), 3)::int)
              group by b.location_id loop
      if public._notif_add('expiring_batches', 'warn', r.c || 'টি ব্যাচের মেয়াদ শেষ হতে চলেছে', r.c || ' batch(es) expiring soon',
           'সবচেয়ে আগের মেয়াদ: ' || to_char(r.first_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), 'Earliest expiry: ' || to_char(r.first_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'), 'stock', r.location_id::text, 'manager', r.location_id) then
        made := made || jsonb_build_object('expiring_batches', coalesce((made ->> 'expiring_batches')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 5. supplier dues overdue
  if public.rule_on('notify_supdue_on') then
    select coalesce(sum(o.open_amt), 0), count(distinct o.supplier_id) into amt, cnt
      from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
     where o.open_amt > 0 and s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < today;
    if cnt > 0 and amt > coalesce(public.rule_num('notify_supdue_min'), 0) and public._notif_add('supplier_overdue', 'warn', cnt || ' সরবরাহকারীর পাওনা মেয়াদ পেরিয়েছে', cnt || ' supplier(s) overdue',
         'মোট ৳' || round(amt, 2), 'Total ৳' || round(amt, 2), 'payables', 'all', 'owner', null) then
      made := made || jsonb_build_object('supplier_overdue', 1); end if;
  end if;

  -- 6. customers over their credit limit
  if public.rule_on('notify_credit_on') then
    select count(*) into cnt from public.customers c where c.active and coalesce(c.credit_limit, 0) > 0 and public._cust_bal(c.id) > c.credit_limit;
    if cnt > 0 and public._notif_add('credit_breach', 'warn', cnt || ' জন গ্রাহকের বাকি সীমা ছাড়িয়েছে', cnt || ' customer(s) over their credit limit', 'বাকির তালিকা দেখুন।', 'See the dues list.', 'dues', 'all', 'owner', null) then
      made := made || jsonb_build_object('credit_breach', 1); end if;
  end if;

  -- 7. shops with no day-close (14-1) after the deadline
  if public.rule_on('notify_dayclose_on') then
    dl := coalesce(public.rule_txt('day_close_deadline'), '22:00');
    if dl !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then dl := '22:00'; end if;
    dl_t := dl::time;
    if nowd::time >= dl_t then
      for r in select l.id, l.name_bn, l.name_en from public.locations l where l.is_active and l.status = 'live' and l.kind = 'showroom' and public.rollout_mode('14-1', l.id) <> 'paper'
                  and not exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = today and e.status in ('submitted', 'approved')) loop
        if public._notif_add('day_close_missing', 'warn', r.name_bn || ': আজকের দিন-শেষ জমা হয়নি', r.name_en || ': today''s day-close is not submitted',
             'শেষ সময় ' || dl || ' পেরিয়ে গেছে।', 'The deadline ' || dl || ' has passed.', 'home', r.id::text, 'manager', r.id) then
          made := made || jsonb_build_object('day_close_missing', coalesce((made ->> 'day_close_missing')::int, 0) + 1); end if;
      end loop;
    end if;
  end if;

  -- 8. wastage spike (money value today vs the average of the previous 7 days)
  if public.rule_on('notify_wastage_on') then
    with w as (select (x.made_at at time zone 'Asia/Dhaka')::date d, round(sum(x.qty * coalesce(b.avg_cost, 0)), 2) v
                 from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id
                where (x.made_at at time zone 'Asia/Dhaka')::date between today - 7 and today group by 1)
    select coalesce((select v from w where d = today), 0), coalesce((select sum(v) from w where d < today), 0) / 7 into amt, hrs;
    if amt > 0 and amt >= coalesce(public.rule_num('notify_wastage_min'), 0) and amt >= coalesce(public.rule_num('notify_wastage_factor'), 3) * hrs
       and public._notif_add('wastage_spike', 'warn', 'আজ অপচয় হঠাৎ বেশি: ৳' || amt, 'Wastage spike today: ৳' || amt,
         'আগের ৭ দিনের গড় ৳' || round(hrs, 2), 'Previous 7-day average ৳' || round(hrs, 2), 'stock', 'all', 'owner', null) then
      made := made || jsonb_build_object('wastage_spike', 1); end if;
  end if;

  -- 9. big cash short / over (each exception once, ever)
  if public.rule_on('notify_cash_on') then
    for r in select x.id, x.location_id, x.amount, l.name_bn, l.name_en from public.exceptions x left join public.locations l on l.id = x.location_id
              where x.flag_code = 'cash_short_over' and x.status = 'open' and abs(coalesce(x.amount, 0)) > coalesce(public.rule_num('notify_cash_limit'), 500) and x.created_at > now() - interval '3 days'
                and not exists (select 1 from public.notifications n where n.kind = 'cash_gap' and n.key = x.id::text) loop
      if public._notif_add('cash_gap', 'bad', coalesce(r.name_bn, '') || ': ক্যাশ ' || case when r.amount < 0 then 'কম' else 'বেশি' end || ' ৳' || abs(r.amount),
           coalesce(r.name_en, '') || ': cash ' || case when r.amount < 0 then 'short' else 'over' end || ' ৳' || abs(r.amount), 'এক্সেপশন দেখে নিষ্পত্তি করুন।', 'Please look at the exception and resolve it.', 'exceptions', r.id::text, 'owner', r.location_id) then
        made := made || jsonb_build_object('cash_gap', coalesce((made ->> 'cash_gap')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 10. parallel-month decision waiting (same rule as phase 28 parallel_waiting, for the owner)
  if public.rule_on('notify_parallel_on') and public.rule_on('parallel_compare_on') then
    for r in select f.form_code, f.location_id from public.form_rollout f
              where f.mode = 'parallel'
                and exists (select 1 from public.comparison_days d where d.form_code = f.form_code and d.location_id = f.location_id
                              and d.day >= (date_trunc('month', today) - interval '1 month')::date and d.day < date_trunc('month', today)::date)
                and not exists (select 1 from public.parallel_months p where p.form_code = f.form_code and p.location_id = f.location_id and p.month = (date_trunc('month', today) - interval '1 month')::date) loop
      if public._notif_add('parallel_decision', 'info', r.form_code || ': গত মাসের পাশাপাশি সিদ্ধান্ত বাকি', r.form_code || ': last month''s parallel decision is waiting', 'পাস/ফেল ঠিক করুন।', 'Decide pass or fail.', 'parallel', r.form_code || ':' || r.location_id, 'owner', r.location_id) then
        made := made || jsonb_build_object('parallel_decision', coalesce((made ->> 'parallel_decision')::int, 0) + 1); end if;
    end loop;
  end if;

  -- 11. backup stale or failed
  if public.rule_on('notify_backup_on') then
    st := public.backup_status();
    if (st ->> 'stale')::boolean and public._notif_add('backup_stale', 'bad', 'ব্যাকআপ পুরনো হয়ে গেছে', 'Backup is out of date',
         coalesce('শেষ সফল ব্যাকআপ ' || (st ->> 'age_hours') || ' ঘণ্টা আগে।', 'এখনো কোনো সফল ব্যাকআপ নেই।'), coalesce('Last good backup ' || (st ->> 'age_hours') || ' hours ago.', 'There is no good backup yet.'), 'notifications', 'stale', 'owner', null) then
      made := made || jsonb_build_object('backup_stale', 1); end if;
    if (st ->> 'failed_last')::boolean and public._notif_add('backup_failed', 'bad', 'শেষ ব্যাকআপ ব্যর্থ হয়েছে', 'The last backup failed', 'GitHub Actions-এর লগ দেখুন।', 'Check the GitHub Actions log.', 'notifications', 'failed', 'owner', null) then
      made := made || jsonb_build_object('backup_failed', 1); end if;
  end if;

  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);
  return jsonb_build_object('created', cnt, 'kinds', made);
end $$;

-- the bell
create or replace function public.notifications_for_me(p_limit int default 50, p_unread_only boolean default false, p_level text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(x order by x.id desc), '[]'::jsonb) into out_ from (
    select n.id, n.kind, n.level, n.title_bn, n.title_en, n.body_bn, n.body_en, n.route, n.location_id, n.created_at,
           (r.user_id is not null) as is_read
      from public.notifications n left join public.notification_reads r on r.notification_id = n.id and r.user_id = auth.uid()
     where public._notif_ok(n.user_id, n.audience, n.location_id)
       and (not coalesce(p_unread_only, false) or r.user_id is null)
       and (p_level is null or n.level = p_level)
     order by n.id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) x;
  return out_;
end $$;
create or replace function public.notifications_unread_count() returns int
language plpgsql stable security definer set search_path = public as $$
declare c int;
begin
  if not public.is_active() then return 0; end if;
  select count(*) into c from public.notifications n
   where n.created_at > now() - interval '90 days' and public._notif_ok(n.user_id, n.audience, n.location_id)
     and not exists (select 1 from public.notification_reads r where r.notification_id = n.id and r.user_id = auth.uid());
  return c;
end $$;
create or replace function public.notification_read(p_id bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare n public.notifications;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into n from public.notifications where id = p_id;
  if not found or not public._notif_ok(n.user_id, n.audience, n.location_id) then raise exception 'not allowed'; end if;
  insert into public.notification_reads (notification_id, user_id) values (p_id, auth.uid()) on conflict do nothing;
  if n.user_id is not null and n.read_at is null then update public.notifications set read_at = now(), read_by = auth.uid() where id = p_id; end if;
  return true;
end $$;
create or replace function public.notification_read_all() returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  insert into public.notification_reads (notification_id, user_id)
    select n.id, auth.uid() from public.notifications n
     where n.created_at > now() - interval '90 days' and public._notif_ok(n.user_id, n.audience, n.location_id)
    on conflict do nothing;
  get diagnostics c = row_count;
  return c;
end $$;

-- ---------- e-mail side ----------
create or replace function public.notify_config() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return jsonb_build_object('email_on', public.rule_on('notify_email_on'), 'digest_times', coalesce(public.rule_txt('notify_digest_times'), '08,21'), 'now_hour', to_char(now() at time zone 'Asia/Dhaka', 'HH24'));
end $$;

create or replace function public.urgent_alerts(p_since timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $$;

create or replace function public.notifications_mark_emailed(p_ids bigint[]) returns int
language plpgsql security definer set search_path = public as $$
declare c int;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_ids is null or coalesce(array_length(p_ids, 1), 0) > 500 then raise exception 'bad_input'; end if;
  update public.notifications set emailed_at = now() where id = any (p_ids) and emailed_at is null;
  get diagnostics c = row_count;
  return c;
end $$;

-- money of one day: sales (done) and returns, net when the report rule says so (same logic as sales_summary)
create or replace function public._day_sales(p_d date) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a,
           'net', case when public.rule_on('reports_net_of_returns') then s.t - r.a else s.t end)
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = p_d) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = p_d) r;
$$;

-- numbers for the e-mail (labels are added by the sender). Owner or notify bot only.
create or replace function public.daily_digest(p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); td jsonb; yd jsonb; lw jsonb; byloc jsonb; top5 jsonb; cash jsonb; coll numeric; custdue numeric; custn int;
        sup jsonb; waste jsonb; voids jsonb; ex jsonb; appr int; lowc int; expc int; closes jsonb; st jsonb; plan_ numeric;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  td := public._day_sales(d); yd := public._day_sales(d - 1); lw := public._day_sales(d - 7);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'net', v.net) order by l.sort), '[]'::jsonb) into byloc
    from public.locations l cross join lateral (
      select coalesce((select sum(total) from public.sales where status = 'done' and sale_date = d and location_id = l.id), 0)
           - case when public.rule_on('reports_net_of_returns') then coalesce((select sum(amount) from public.sale_returns where status = 'done' and location_id = l.id and (created_at at time zone 'Asia/Dhaka')::date = d), 0) else 0 end as net) v
   where l.is_active and l.status = 'live' and l.kind = 'showroom';
  select coalesce(jsonb_agg(jsonb_build_object('name', z.nm, 'qty', z.q, 'amount', z.a) order by z.a desc), '[]'::jsonb) into top5 from (
    select coalesce(x.ln ->> 'name', '?') nm, round(sum((x.ln ->> 'qty')::numeric), 3) q, round(sum((x.ln ->> 'amount')::numeric), 2) a
      from (select jsonb_array_elements(s.lines) ln from public.sales s where s.status = 'done' and s.sale_date = d) x
     where (x.ln ->> 'amount') ~ '^-?[0-9.]+$' and (x.ln ->> 'qty') ~ '^-?[0-9.]+$' group by coalesce(x.ln ->> 'name', '?') order by sum((x.ln ->> 'amount')::numeric) desc limit 5) z;
  select jsonb_build_object('count', count(*), 'short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0)) into cash
    from public.exceptions where flag_code = 'cash_short_over' and entry_date = d;
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d;
  select coalesce(sum(b), 0), count(*) into custdue, custn from (select public._cust_bal(c.id) b from public.customers c) z where b > 0;
  select jsonb_build_object('payable', coalesce(sum(o.open_amt), 0), 'suppliers', count(distinct o.supplier_id),
           'overdue', coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < public._today()), 0)) into sup
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id where o.open_amt > 0;
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into waste
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id where (x.made_at at time zone 'Asia/Dhaka')::date = d;
  select jsonb_build_object('void_count', count(*) filter (where status = 'void'), 'void_total', coalesce(sum(total) filter (where status = 'void'), 0),
           'discount_count', count(*) filter (where status = 'done' and discount > 0), 'discount_total', coalesce(sum(discount) filter (where status = 'done'), 0)) into voids
    from public.sales where sale_date = d;
  select jsonb_build_object('red', count(*) filter (where level = 'red'), 'yellow', count(*) filter (where level = 'yellow')) into ex from public.exceptions where status = 'open';
  select count(*) into appr from (
      select 1 from public.entries where status = 'submitted' union all select 1 from public.release_requests where status = 'pending'
      union all select 1 from public.emergency_requests where status = 'pending' union all select 1 from public.item_changes where status = 'pending'
      union all select 1 from public.profiles where status = 'pending' union all select 1 from public.wastage_requests where status = 'pending') u;
  select count(*) into lowc from public.stock_balance b join public.items i on i.id = b.item_id where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock;
  select count(*) into expc from public.stock_batches where qty_remaining > 0 and expires_at is not null and expires_at < now() + make_interval(days => coalesce(public.rule_num('notify_expiry_days'), 3)::int);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en,
           'closed', exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = d and e.status in ('submitted', 'approved')),
           'mode', public.rollout_mode('14-1', l.id)) order by l.sort), '[]'::jsonb) into closes
    from public.locations l where l.is_active and l.status = 'live' and l.kind = 'showroom';
  st := public.backup_status();
  return jsonb_build_object('date', d, 'generated_at', now(),
    'sales', jsonb_build_object('today', td, 'yesterday', yd, 'last_week', lw,
       'vs_yesterday_pct', case when (yd ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (yd ->> 'net')::numeric) * 100 / (yd ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (lw ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (lw ->> 'net')::numeric) * 100 / (lw ->> 'net')::numeric, 1) end,
       'by_location', byloc),
    'top_items', top5, 'cash', cash, 'collections', coll,
    'dues', jsonb_build_object('customers_total', round(custdue, 2), 'customers', custn, 'suppliers', sup),
    'wastage', waste, 'voids_discounts', voids, 'exceptions_open', ex, 'approvals_pending', appr,
    'stock_alerts', jsonb_build_object('low_items', lowc, 'expiring_batches', expc),
    'day_close', closes, 'backup', st);
end $$;

-- ---------- photos: the backup bot may READ the private "photos" bucket (tools/backup_photos.py); nobody else gains anything ----------
do $$ begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists ops_photos_read on storage.objects';
    execute 'create policy ops_photos_read on storage.objects for select to authenticated using (bucket_id = ''photos'' and public._is_ops(''backup''))';
  end if;
end $$;

-- ---------- grants ----------
do $$ declare f text; r regprocedure; begin
  foreach f in array array['_is_ops', '_today', '_notif_ok', '_notif_add', '_backup_tables', '_day_sales', 'ops_account_set', 'backup_manifest', 'backup_dump', 'backup_log', 'backup_status',
      'notify_scan', 'notifications_for_me', 'notifications_unread_count', 'notification_read', 'notification_read_all', 'notify_config', 'urgent_alerts', 'notifications_mark_emailed', 'daily_digest'] loop
    for r in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f loop
      execute format('revoke all on function %s from public, anon, authenticated', r);
      if f in ('_is_ops', '_notif_ok', 'ops_account_set', 'backup_manifest', 'backup_dump', 'backup_log', 'backup_status', 'notify_scan', 'notifications_for_me', 'notifications_unread_count', 'notification_read', 'notification_read_all',
               'notify_config', 'urgent_alerts', 'notifications_mark_emailed', 'daily_digest') then
        execute format('grant execute on function %s to authenticated', r);
      end if;
    end loop;
  end loop;
end $$;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase47.sql
-- ============================================================
-- Phase 47 - Module G: business assistant (READ-ONLY MVP). Run AFTER phase28. Additive and idempotent (paste it twice = no error).
-- Does not depend on phases 40-46: optional modules (accounting, partners, tiers, backups) are detected at call time (to_regclass / pg_proc).
--
-- What this adds (nothing here changes business data):
--   * rules (Switchboard): assistant_on (ON), assistant_roles (blank = owner + head management + grant assistant_use), assistant_provider (local | llm_proxy,
--     default local), assistant_monthly_token_budget (blank = no paid model may run), assistant_cache_seconds (60), assistant_actions_on (OFF, reserved -
--     the MVP has no write actions), assistant_voice_on (OFF), assistant_rate_per_hour (120), assistant_closed_age_days (45)
--   * grants: assistant_use (may use the assistant), assistant_health (may run the configuration check)
--   * assistant_notes    owner-approved business rules / procedures / facts the assistant quotes as "approved by owner" (owner writes via RPC; never secrets)
--   * assistant_usage    append-only log WITHOUT business content: who, when, provider, intent, tool keys, ms, tokens, ok
--   * assistant_me()        what the caller may ask (capability map; the server still decides on every call)
--   * assistant_health()    read-only findings about incomplete / conflicting configuration, each with a route to the fixing screen
--   * assistant_log(...)    one usage row (with a per-hour rate limit); assistant_usage_summary(month) owner-only token / cost counters
--   * assistant_note_save / assistant_note_retire (owner only)
-- Security: every function is security definer with search_path public, checks is_active, and never takes SQL / table / function names from the caller.
-- ============================================================

-- ---------- rules ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('assistant_on', 'assistant', 'switch', 'true', null, null, null, null, 'ব্যবসার সহকারী (প্রশ্ন করুন) চালু', 'Business assistant (Ask) চালু', 'Business assistant (Ask) is on',
  'শুধু পড়ে: রিপোর্ট ও সেটআপ থেকে উত্তর দেয়, কিছু বদলায় না। কে ব্যবহার করবেন: মালিক, হেড ম্যানেজমেন্ট ও assistant_use অনুমতি।', 'Read-only: answers from reports and setup, changes nothing. Used by the owner, head management and holders of assistant_use.', 900),
 ('assistant_roles', 'assistant', 'text', null, null, null, null, null, 'আর কোন ভূমিকা সহকারী ব্যবহার করবে (কোড, কমা দিয়ে; * = সবাই)', 'আর কোন role assistant ব্যবহার করবে (code, comma; * = সবাই)', 'Other roles that may use the assistant (codes, comma separated; * = everyone)',
  'ফাঁকা = শুধু মালিক, হেড ম্যানেজমেন্ট ও assistant_use। প্রত্যেক উত্তর তবুও ব্যবহারকারীর নিজের অনুমতি মানে।', 'Blank = owner, head management and assistant_use only. Every answer still follows the person''s own rights.', 901),
 ('assistant_provider', 'assistant', 'choice', '"local"', null, '["local","llm_proxy"]'::jsonb, null, null, 'সহকারীর বুদ্ধি: ফোনেই (বিনা খরচে) / AI প্রক্সি', 'Assistant engine: phone-এ (free) / AI proxy', 'Assistant engine: on the phone (free) / AI proxy',
  'llm_proxy কাজ করবে শুধু মালিক Edge Function বসালে ও মাসিক টোকেন সীমা দিলে; নইলে ফোনেই চলে।', 'llm_proxy works only after the owner deploys the Edge Function and sets a monthly token budget; otherwise it stays local.', 902),
 ('assistant_monthly_token_budget', 'assistant', 'number', null, 'tokens', null, 0, 100000000, 'AI প্রক্সির মাসিক টোকেন সীমা', 'AI proxy-র monthly token limit', 'AI proxy monthly token budget',
  'ফাঁকা = কোনো পেইড মডেল চলবে না।', 'Blank = no paid model may run.', 903),
 ('assistant_cache_seconds', 'assistant', 'number', '60', 'sec', null, 0, 600, 'একই প্রশ্নের উত্তর কত সেকেন্ড মনে রাখবে', 'একই প্রশ্নের উত্তর কত second মনে রাখবে', 'Seconds a tool answer is reused', null, null, 904),
 ('assistant_actions_on', 'assistant', 'switch', 'false', null, null, null, null, 'সহকারী থেকে কাজ (লিখা) — এখন বন্ধ, পরে', 'Assistant থেকে action (write) — এখন বন্ধ', 'Assistant actions (writes) - reserved, off',
  'এই সংস্করণে সহকারী কিছুই লেখে না; শুধু সঠিক পেজ খোলার লিংক দেয়।', 'This version writes nothing; it only links to the right screen.', 905),
 ('assistant_voice_on', 'assistant', 'switch', 'false', null, null, null, null, 'সহকারীতে কথা বলে প্রশ্ন', 'Assistant-এ voice input', 'Voice input in the assistant', null, null, 906),
 ('assistant_rate_per_hour', 'assistant', 'number', '120', null, null, 1, 10000, 'এক ঘণ্টায় একজন সর্বোচ্চ কত প্রশ্ন', 'এক ঘণ্টায় একজন সর্বোচ্চ কত প্রশ্ন', 'Most questions per person per hour', null, null, 907),
 ('assistant_closed_age_days', 'assistant', 'number', '45', 'days', null, 1, 3650, 'হিসাব বন্ধের তারিখ কত দিনের পুরনো হলে মনে করাবে', 'Books closed date কত দিন পুরনো হলে মনে করাবে', 'Remind when the books-closed date is older than (days)', null, null, 908)
on conflict (key) do nothing;

-- ---------- grants ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_use', 'reports', 90, 'ব্যবসার সহকারী ব্যবহার', 'Business assistant ব্যবহার', 'Use the business assistant', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_use');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_health', 'reports', 91, 'সেটআপ-চেক (কনফিগারেশনের ঘাটতি) দেখা', 'Setup check (configuration gap) দেখা', 'See the setup check (configuration gaps)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_health');

-- ---------- who may use it ----------
create or replace function public._assistant_ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r text := coalesce(public.rule_txt('assistant_roles'), '');
begin
  if not public.is_active() then return false; end if;
  if not public.rule_on('assistant_on') then return false; end if;
  if public.is_owner() or public.has_grant('head_management') or public.has_grant('assistant_use') then return true; end if;
  if btrim(r) = '*' then return true; end if;
  return exists (select 1 from public.user_roles ur where ur.user_id = auth.uid()
                  and ur.role_code = any (select btrim(x) from unnest(string_to_array(r, ',')) x where btrim(x) <> ''));
end $$;

create or replace function public._assistant_health_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('head_management') or public.has_grant('assistant_health'));
$$;

-- does the caller hold a grant at ANY place (location-scoped grants included)
create or replace function public._assistant_any_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_grant(p_code) or exists (select 1 from public.locations l where public.has_grant(p_code, l.id));
$$;

-- ---------- notes (owner-approved rules / procedures / facts) ----------
create table if not exists public.assistant_notes (
  id bigserial primary key,
  kind text not null check (kind in ('rule', 'procedure', 'fact')),
  title text not null check (length(btrim(title)) between 2 and 120),
  body_bn text, body_en text,
  status text not null default 'approved' check (status in ('approved', 'retired')),
  client_id uuid unique,
  created_by uuid, at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz,
  retired_reason text,
  check (coalesce(length(body_bn), 0) + coalesce(length(body_en), 0) between 2 and 4000)
);
alter table public.assistant_notes enable row level security;
revoke all on public.assistant_notes from public, anon, authenticated;
grant select on public.assistant_notes to authenticated;
drop policy if exists assistant_notes_read on public.assistant_notes;
create policy assistant_notes_read on public.assistant_notes for select to authenticated using (public._assistant_ok() and (status = 'approved' or public.is_owner()));
drop trigger if exists assistant_notes_nodel on public.assistant_notes;
create trigger assistant_notes_nodel before delete on public.assistant_notes for each row execute function public.no_hard_delete();
drop trigger if exists audit_assistant_notes on public.assistant_notes;
create trigger audit_assistant_notes after insert or update on public.assistant_notes for each row execute function public.log_change('id');

-- text that looks like a secret is never stored (passwords, PINs, keys, tokens)
create or replace function public._assistant_secretish(p text) returns boolean
language sql immutable set search_path = public as $$
  select p is not null and (
       p ~* '(password|passwd|পাসওয়ার্ড|পাসওয়ার্ড|api[ _-]?key|secret|token|service_role|otp)'
    or p ~* '(pin|পিন)\s*(code|কোড|no|number|নম্বর)?\s*[:=]?\s*[0-9০-৯]{4,8}'
    or p ~ '(sk-[A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{20,}|[A-Za-z0-9_+/=-]{40,})');
$$;

create or replace function public.assistant_note_save(p_id bigint, p_client uuid, p_kind text, p_title text, p_body_bn text, p_body_en text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.assistant_notes; t text := btrim(coalesce(p_title, '')); bb text := nullif(btrim(coalesce(p_body_bn, '')), ''); be text := nullif(btrim(coalesce(p_body_en, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('rule', 'procedure', 'fact') then raise exception 'bad_kind'; end if;
  if length(t) < 2 or length(t) > 120 then raise exception 'title_required'; end if;
  if bb is null and be is null then raise exception 'body_required'; end if;
  if coalesce(length(bb), 0) + coalesce(length(be), 0) > 4000 then raise exception 'too_long'; end if;
  if public._assistant_secretish(t) or public._assistant_secretish(bb) or public._assistant_secretish(be) then raise exception 'looks_like_secret'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_required'; end if;
    perform public._client_lock(p_client);
    select * into r from public.assistant_notes where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'dup', true); end if;
    insert into public.assistant_notes (kind, title, body_bn, body_en, client_id, created_by) values (p_kind, t, bb, be, p_client, auth.uid()) returning * into r;
    return jsonb_build_object('id', r.id);
  end if;
  select * into r from public.assistant_notes where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'approved' then raise exception 'retired'; end if;
  update public.assistant_notes set kind = p_kind, title = t, body_bn = bb, body_en = be, updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.assistant_note_retire(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.assistant_notes;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into r from public.assistant_notes where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'retired' then return jsonb_build_object('id', p_id, 'status', 'retired', 'dup', true); end if;
  update public.assistant_notes set status = 'retired', retired_reason = left(btrim(p_reason), 300), updated_by = auth.uid(), updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'retired');
end $$;

-- ---------- usage log (no business content) ----------
create table if not exists public.assistant_usage (
  id bigserial primary key,
  user_id uuid not null,
  at timestamptz not null default now(),
  provider text not null check (provider in ('local', 'llm_proxy')),
  intent text not null check (intent ~ '^[a-z0-9_]{1,40}$'),
  tool_keys text[] not null default '{}',
  ms int not null default 0 check (ms between 0 and 600000),
  tokens_in int not null default 0 check (tokens_in between 0 and 10000000),
  tokens_out int not null default 0 check (tokens_out between 0 and 10000000),
  ok boolean not null default true
);
create index if not exists assistant_usage_user_at on public.assistant_usage (user_id, at);
create index if not exists assistant_usage_at on public.assistant_usage (at);
alter table public.assistant_usage enable row level security;
revoke all on public.assistant_usage from public, anon, authenticated;
grant select on public.assistant_usage to authenticated;
drop policy if exists assistant_usage_read on public.assistant_usage;
create policy assistant_usage_read on public.assistant_usage for select to authenticated using (public.is_owner());
create or replace function public._assistant_usage_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'assistant_usage is append-only'; end $$;
drop trigger if exists assistant_usage_ro on public.assistant_usage;
create trigger assistant_usage_ro before update or delete on public.assistant_usage for each row execute function public._assistant_usage_ro();
drop trigger if exists assistant_usage_ro_t on public.assistant_usage;
create trigger assistant_usage_ro_t before truncate on public.assistant_usage for each statement execute function public._assistant_usage_ro();

create or replace function public.assistant_log(p_provider text, p_intent text, p_tools text[], p_ms int, p_tokens_in int default 0, p_tokens_out int default 0, p_ok boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int; lim int := greatest(coalesce(public.rule_num('assistant_rate_per_hour'), 120), 1)::int; k text;
begin
  if not public._assistant_ok() then raise exception 'not allowed'; end if;
  if p_provider is null or p_provider not in ('local', 'llm_proxy') then raise exception 'bad_provider'; end if;
  if p_intent is null or p_intent !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_intent'; end if;
  if cardinality(coalesce(p_tools, '{}')) > 12 then raise exception 'too_many_tools'; end if;
  foreach k in array coalesce(p_tools, '{}') loop
    if k is null or k !~ '^[a-z0-9_]{1,40}$' then raise exception 'bad_tool_key'; end if;
  end loop;
  if p_ms is null or p_ms < 0 or p_ms > 600000 or coalesce(p_tokens_in, 0) not between 0 and 10000000 or coalesce(p_tokens_out, 0) not between 0 and 10000000 then raise exception 'bad_number'; end if;
  select count(*) into n from public.assistant_usage where user_id = auth.uid() and at > now() - interval '1 hour';
  if n >= lim then return jsonb_build_object('ok', false, 'limited', true, 'count_hour', n, 'limit', lim); end if;
  insert into public.assistant_usage (user_id, provider, intent, tool_keys, ms, tokens_in, tokens_out, ok)
    values (auth.uid(), p_provider, p_intent, coalesce(p_tools, '{}'), p_ms, coalesce(p_tokens_in, 0), coalesce(p_tokens_out, 0), coalesce(p_ok, true));
  return jsonb_build_object('ok', true, 'limited', false, 'count_hour', n + 1, 'limit', lim);
end $$;

-- owner: counts and tokens for one month (token cost is computed in the browser from documented prices, never stored as money)
create or replace function public.assistant_usage_summary(p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Dhaka')::date))::date; res jsonb; bud numeric := public.rule_num('assistant_monthly_token_budget');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select jsonb_build_object('month', m, 'questions', count(*), 'ok', count(*) filter (where ok), 'failed', count(*) filter (where not ok),
      'users', count(distinct user_id), 'avg_ms', coalesce(round(avg(ms)), 0),
      'local', count(*) filter (where provider = 'local'), 'llm_proxy', count(*) filter (where provider = 'llm_proxy'),
      'tokens_in', coalesce(sum(tokens_in), 0), 'tokens_out', coalesce(sum(tokens_out), 0),
      'budget', bud, 'budget_used_pct', case when bud > 0 then round(100.0 * coalesce(sum(tokens_in + tokens_out), 0) / bud, 1) end,
      'top_intents', coalesce((select jsonb_agg(jsonb_build_object('intent', z.intent, 'n', z.n) order by z.n desc) from (
          select intent, count(*) n from public.assistant_usage u2 where (u2.at at time zone 'Asia/Dhaka')::date >= m and (u2.at at time zone 'Asia/Dhaka')::date < (m + interval '1 month')::date
          group by intent order by count(*) desc limit 8) z), '[]'::jsonb))
    into res from public.assistant_usage u where (u.at at time zone 'Asia/Dhaka')::date >= m and (u.at at time zone 'Asia/Dhaka')::date < (m + interval '1 month')::date;
  return res;
end $$;

-- the edge function (if the owner ever deploys it) asks this with the caller's JWT before spending tokens
create or replace function public.assistant_proxy_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare bud numeric := public.rule_num('assistant_monthly_token_budget'); used numeric; m date := date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date;
begin
  if not public._assistant_ok() then return jsonb_build_object('ok', false, 'reason', 'not_allowed'); end if;
  if coalesce(public.rule_txt('assistant_provider'), 'local') <> 'llm_proxy' then return jsonb_build_object('ok', false, 'reason', 'provider_local'); end if;
  if bud is null or bud <= 0 then return jsonb_build_object('ok', false, 'reason', 'no_budget'); end if;
  select coalesce(sum(tokens_in + tokens_out), 0) into used from public.assistant_usage where provider = 'llm_proxy' and (at at time zone 'Asia/Dhaka')::date >= m;
  if used >= bud then return jsonb_build_object('ok', false, 'reason', 'budget_spent', 'used', used, 'budget', bud); end if;
  return jsonb_build_object('ok', true, 'used', used, 'budget', bud, 'left', bud - used);
end $$;

-- ---------- capability map: what this person may ask (the server still decides on every call) ----------
create or replace function public.assistant_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text; grp jsonb := '{}'::jsonb; opt jsonb := '[]'::jsonb; own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._assistant_ok() then
    return jsonb_build_object('allowed', false, 'reason', case when not public.rule_on('assistant_on') then 'assistant_off' else 'no_right' end);
  end if;
  foreach g in array array['sales','pos','cash','customers','stock','purchase','expense','staff','control','profit','orders','marketing','quality'] loop
    grp := grp || jsonb_build_object(g, public.rpt_access(g));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('name', p.proname,
           'args', coalesce((select jsonb_agg(a.n order by a.o) from unnest(coalesce(p.proargnames, '{}'::text[])) with ordinality a(n, o)
                              where p.proargmodes is null or p.proargmodes[a.o] in ('i', 'b')), '[]'::jsonb))
           order by p.proname), '[]'::jsonb) into opt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = any (array['acct_balance_sheet','acct_income_statement','acct_trial_balance','acct_overview','balance_sheet','income_statement','trial_balance','partner_overview','tier_usage_report','backup_status'])
     and has_function_privilege('authenticated', p.oid, 'execute');
  return jsonb_build_object('allowed', true, 'is_owner', own,
    'health', public._assistant_health_ok(), 'cost', public.rpt_cost_ok(), 'biz', public.biz_ok(),
    'salary', own or public._assistant_any_grant('salary_view'), 'daybook', own or public._assistant_any_grant('view_daybook'),
    'purchase', public._pur_ok(null) or exists (select 1 from public.locations l where public._pur_ok(l.id)),
    'pos', public.can_do('POS', 'view') or public.can_do('POS', 'enter'),
    'reports', grp, 'optional', opt,
    'provider', coalesce(public.rule_txt('assistant_provider'), 'local'), 'cache_seconds', coalesce(public.rule_num('assistant_cache_seconds'), 60),
    'actions_on', false, 'voice_on', public.rule_on('assistant_voice_on'), 'rate_per_hour', coalesce(public.rule_num('assistant_rate_per_hour'), 120));
end $$;

-- ---------- the configuration check ----------
create or replace function public._ah(p_code text, p_sev text, p_bn text, p_en text, p_detail text, p_route text, p_ev jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select jsonb_build_array(jsonb_build_object('code', p_code, 'severity', p_sev, 'title_bn', p_bn, 'title_en', p_en, 'detail', p_detail, 'route', p_route, 'evidence', coalesce(p_ev, '{}'::jsonb)));
$$;

create or replace function public.assistant_health() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  f jsonb := '[]'::jsonb; locs int[]; n bigint; n2 bigint; ev jsonb; r record; d date; today date := (now() at time zone 'Asia/Dhaka')::date;
  age int := coalesce(public.rule_num('assistant_closed_age_days'), 45)::int; sid bigint; miss text[]; k text; v jsonb; maxh numeric; last timestamptz; fin boolean;
  keys constant text[] := array['drawer_float', 'cash_tol', 'discount_limit', 'expense_max'];
begin
  if not public._assistant_health_ok() then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id order by l.id), '{}') into locs from public.locations l
   where coalesce(l.status, 'live') in ('live', 'setting_up') and (public.is_owner() or public.has_grant('head_management') or public.can_loc(l.id));

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
end $$;

-- ---------- privileges ----------
revoke all on function public._assistant_ok(), public._assistant_health_ok(), public._assistant_any_grant(text), public._assistant_secretish(text),
  public._ah(text, text, text, text, text, text, jsonb), public._assistant_usage_ro() from public, anon, authenticated;
grant execute on function public._assistant_ok() to authenticated;   -- used inside the notes read policy
revoke all on function public.assistant_me(), public.assistant_health(), public.assistant_log(text, text, text[], int, int, int, boolean), public.assistant_usage_summary(date),
  public.assistant_proxy_check(), public.assistant_note_save(bigint, uuid, text, text, text, text), public.assistant_note_retire(bigint, text) from public, anon;
grant execute on function public.assistant_me(), public.assistant_health(), public.assistant_log(text, text, text[], int, int, int, boolean), public.assistant_usage_summary(date),
  public.assistant_proxy_check(), public.assistant_note_save(bigint, uuid, text, text, text, text), public.assistant_note_retire(bigint, text) to authenticated;

-- ---------------------------------------------------------------- phase48.sql
-- ============================================================
-- Phase 48 - P1 slice 1: the "one record + locked shadow copy" engine and the owner path switches.
-- Run AFTER phase47. Additive + idempotent (paste twice = no error). No existing table or function is changed; nothing is posted by this file.
--
-- Rule: every transaction has ONE primary record. The other path (quick tab <-> formal paper form) gets a linked, locked "shadow copy".
--       A shadow is never counted: reports, the day book and the journal read the primary only. Posting stays unique on (source_type, source_id).
--
--   path_domains   the 7 places where two paths exist (payroll, stock issue / transfer / count, production, expense, owner money) with labels + default.
--   path_switch    the OWNER's choice per domain (and optionally per place): is path A open or locked, is path B open or locked, and which record is the
--                  primary when both exist: a | b | first (the earlier one).   location_id 0 = all places.  A locked path takes no NEW records.
--   shadow_links   primary record <-> shadow copy (pending until the second path is filled/confirmed; confirmed; void). Append-only trail.
--   Functions: path_cfg, path_primary, path_allowed, path_guard (used by later slices), path_switch_set / path_switches (owner),
--              shadow_link_add / shadow_confirm / shadow_void (internal), is_shadow, shadow_report, shadow_count_once_check (read-only).
-- ============================================================

-- ---------- 1. domains ----------
create table if not exists public.path_domains (
  domain text primary key check (domain ~ '^[a-z_]{2,30}$'),
  a_bn text not null, a_en text not null,                    -- path A (app / quick / screen)
  b_bn text not null, b_en text not null,                    -- path B (formal paper form / second screen)
  default_primary text not null default 'a' check (default_primary in ('a', 'b', 'first')),   -- which record is counted when both paths hold the same event
  legacy_rule text,                                          -- an older owner switch that already meant "the form is the record": while it is ON the default primary is b (keeps today's behaviour)
  allow_first boolean not null default false,                -- 'first one wins' only where the two records have a natural key (payroll month, owner money amount/date); not for stock
  note_bn text, note_en text,
  sort int not null default 0
);
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('payroll',       'অ্যাপে বেতন (পে-রোল)',      'App payroll (runs / payments)',   'ফর্ম 02-2 (মাসিক বেতন শিট)',   'Form 02-2 (monthly salary sheet)',     'a',
  'দুটোই খোলা; অ্যাপে বেতন শুরু হলে 02-2 লক হয়, গোপন শ্যাডো কপি থাকে।', 'Both open; once app payroll starts for the month, 02-2 is locked and kept as a shadow copy.', 10),
 ('stock_issue',   'স্টক স্ক্রিনে ইস্যু',         'Stock screen issue',               'ফর্ম 04-2 (ইস্যু স্লিপ)',        'Form 04-2 (issue slip)',                'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 20),
 ('stock_transfer','স্টক স্ক্রিনে ট্রান্সফার',    'Stock screen transfer',            'ফর্ম 03-1 (ট্রান্সফার চালান)',   'Form 03-1 (transfer challan)',          'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 30),
 ('stock_count',   'স্টক স্ক্রিনে গণনা',          'Stock screen count',               'ফর্ম 04-3 (স্টক কাউন্ট শিট)',    'Form 04-3 (stock count sheet)',         'a',
  'ডিফল্ট: স্ক্রিন মূল, ফর্ম রেফারেন্স।', 'Default: screen is primary, form is a reference.', 40),
 ('production',    'রেসিপি প্রোডাকশন রান',        'Recipe production run',            'ফর্ম 05-1 (কারখানা দৈনিক শিট)',  'Form 05-1 (factory daily sheet)',       'a',
  'ডিফল্ট: রান মূল, 05-1 রেফারেন্স।', 'Default: the run is primary, 05-1 is a reference.', 50),
 ('expense',       'ডে-বুকে দ্রুত খরচ এন্ট্রি',    'Day-book quick expense',           'ফর্ম 10-2 (ব্যয় ভাউচার)',       'Form 10-2 (expense voucher)',           'a',
  'দিনের শেষে দ্রুত এন্ট্রির 10-2 শ্যাডো কপি; এক ক্লিকে নিশ্চিত।', 'Quick entries get a 10-2 shadow at day end; one click confirms.', 60),
 ('owner_money',   'পার্টনার ক্যাপিটাল',          'Partner capital',                  'ক্যাশ মুভ (মালিকের জমা/উত্তোলন)', 'Cash move (owner top-up / draw)',       'a',
  'ডিফল্ট: পার্টনার ক্যাপিটাল মূল, ক্যাশ মুভ শ্যাডো।', 'Default: partner capital is primary, the cash move gets the shadow.', 70)
on conflict (domain) do nothing;
update public.path_domains set allow_first = true where domain in ('payroll', 'expense', 'owner_money') and not allow_first;
update public.path_domains set legacy_rule = 'forms_post_to_ledger' where domain in ('stock_issue', 'stock_transfer', 'stock_count', 'production') and legacy_rule is distinct from 'forms_post_to_ledger';

-- ---------- 2. the owner's switch ----------
create table if not exists public.path_switch (
  domain text not null references public.path_domains(domain),
  location_id int not null default 0 check (location_id >= 0),     -- 0 = every place
  a_open boolean not null default true,                            -- false = locked: path A takes no new records
  b_open boolean not null default true,
  primary_rule text check (primary_rule is null or primary_rule in ('a', 'b', 'first')),   -- null = the domain default
  note text check (note is null or length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now(),
  primary key (domain, location_id)
);
drop trigger if exists audit_path_switch on public.path_switch;
create trigger audit_path_switch after insert or update on public.path_switch for each row execute function public.log_change('domain,location_id');

-- ---------- 3. the shadow trail ----------
create table if not exists public.shadow_links (
  id bigint generated always as identity primary key,
  domain text not null references public.path_domains(domain),
  location_id int not null default 0,
  primary_type text not null check (length(primary_type) between 1 and 40),      -- e.g. payroll_runs, entries:02-2, partner_capital
  primary_id text not null check (length(primary_id) between 1 and 80),
  shadow_type text not null check (length(shadow_type) between 1 and 40),
  shadow_id text check (shadow_id is null or length(shadow_id) between 1 and 80),  -- null while the shadow is only pending
  state text not null default 'pending' check (state in ('pending', 'confirmed', 'void')),
  locked boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  confirmed_by uuid, confirmed_at timestamptz
);
-- one shadow of a kind per primary. Several primaries may share one shadow record (a day's quick entries -> one voucher): the shadow is simply never counted.
create unique index if not exists shadow_one_per_primary on public.shadow_links (domain, primary_type, primary_id, shadow_type) where state <> 'void';
create unique index if not exists shadow_pair_once on public.shadow_links (primary_type, primary_id, shadow_type, shadow_id) where shadow_id is not null and state <> 'void';
create index if not exists shadow_by_state on public.shadow_links (domain, state, location_id);
-- a primary can never also be a shadow (checked in shadow_link_add); the trail itself is append-only except pending -> confirmed -> void
create or replace function public._shadow_ro() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'state' - 'shadow_id' - 'confirmed_by' - 'confirmed_at' - 'note') = (to_jsonb(old) - 'state' - 'shadow_id' - 'confirmed_by' - 'confirmed_at' - 'note')
     and ((old.state = 'pending' and new.state in ('confirmed', 'void')) or (old.state = 'confirmed' and new.state = 'void') or (old.state = new.state and old.shadow_id is null)) then return new; end if;
  raise exception 'append_only: shadow_links is a trail, it cannot be changed or deleted (void it instead)';
end $$;
drop trigger if exists shadow_ro on public.shadow_links;
create trigger shadow_ro before update or delete on public.shadow_links for each row execute function public._shadow_ro();
drop trigger if exists audit_shadow_links on public.shadow_links;
create trigger audit_shadow_links after insert or update on public.shadow_links for each row execute function public.log_change('id');

do $$
declare t text;
begin
  foreach t in array array['path_domains', 'path_switch', 'shadow_links'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
create policy path_domains_sel on public.path_domains for select to authenticated using (public.is_active());
create policy path_switch_sel on public.path_switch for select to authenticated using (public.is_active());
create policy shadow_links_sel on public.shadow_links for select to authenticated using (public.is_owner() or (location_id > 0 and public.can_loc(location_id)));

-- ---------- 4. reading the switch ----------
-- the effective setting: a place row beats the all-places row beats the domain default
create or replace function public.path_cfg(p_domain text, p_loc int default 0) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('a_open', coalesce(x.a_open, true), 'b_open', coalesce(x.b_open, true), 'primary', coalesce(x.primary_rule, case when d.legacy_rule is not null and public.rule_on(d.legacy_rule) then 'b' else d.default_primary end))
    from public.path_domains d
    left join lateral (select s.* from public.path_switch s where s.domain = d.domain and s.location_id in (0, case when coalesce(p_loc, 0) > 0 then p_loc else 0 end)
                        order by s.location_id desc limit 1) x on true
   where d.domain = p_domain;
$$;
create or replace function public.path_primary(p_domain text, p_loc int default 0) returns text
language sql stable security definer set search_path = public as $$ select public.path_cfg(p_domain, p_loc) ->> 'primary' $$;

-- may this path ('a' | 'b') take a NEW record now?
create or replace function public.path_allowed(p_domain text, p_loc int, p_path text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.path_cfg(p_domain, p_loc) ->> (p_path || '_open'))::boolean, false) where p_path in ('a', 'b');
$$;

-- used INSIDE posting functions / triggers of later slices: refuse when the owner has locked this path
create or replace function public.path_guard(p_domain text, p_loc int, p_path text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if p_path not in ('a', 'b') then raise exception 'bad_path'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if not public.path_allowed(p_domain, p_loc, p_path) then raise exception 'path_locked: % path % is locked here by the owner', p_domain, p_path; end if;
end $$;

-- given two records of the same event (existing = already stored, incoming = the one arriving on path p_in), which one is the primary? returns 'incoming' | 'existing'
create or replace function public.path_winner(p_domain text, p_loc int, p_incoming_path text) returns text
language sql stable security definer set search_path = public as $$
  select case public.path_primary(p_domain, p_loc) when 'first' then 'existing' when p_incoming_path then 'incoming' else 'existing' end;
$$;

-- ---------- 5. owner sets the switch ----------
create or replace function public.path_switch_set(p_domain text, p_loc int, p_a_open boolean, p_b_open boolean, p_primary text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int := coalesce(p_loc, 0); old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if p_a_open is null or p_b_open is null then raise exception 'bad_mode'; end if;
  if p_primary is not null and p_primary not in ('a', 'b', 'first') then raise exception 'bad_primary'; end if;
  if p_primary = 'first' and not (select allow_first from public.path_domains where domain = p_domain) then raise exception 'first_not_allowed: stock and production records have no natural key, choose a or b'; end if;
  if loc > 0 and not exists (select 1 from public.locations where id = loc) then raise exception 'unknown_location'; end if;
  old := public.path_cfg(p_domain, loc);
  insert into public.path_switch (domain, location_id, a_open, b_open, primary_rule, note, updated_by, updated_at) values (p_domain, loc, p_a_open, p_b_open, p_primary, nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (domain, location_id) do update set a_open = excluded.a_open, b_open = excluded.b_open, primary_rule = excluded.primary_rule, note = excluded.note, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('domain', p_domain, 'location_id', loc, 'from', old, 'to', public.path_cfg(p_domain, loc));
end $$;

-- the full picture for the owner screen: every domain, the all-places setting and the per-place overrides
create or replace function public.path_switches() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('domain', d.domain, 'a_bn', d.a_bn, 'a_en', d.a_en, 'b_bn', d.b_bn, 'b_en', d.b_en, 'note_bn', d.note_bn, 'note_en', d.note_en,
      'default_primary', d.default_primary, 'cfg', public.path_cfg(d.domain, 0),
      'places', coalesce((select jsonb_agg(jsonb_build_object('location_id', s.location_id, 'cfg', public.path_cfg(d.domain, s.location_id), 'note', s.note) order by s.location_id) from public.path_switch s where s.domain = d.domain and s.location_id > 0), '[]'::jsonb))
      order by d.sort) from public.path_domains d), '[]'::jsonb);
end $$;

-- ---------- 6. the shadow engine (internal: called by the domain slices, never by the browser) ----------
create or replace function public.shadow_link_add(p_domain text, p_loc int, p_ptype text, p_pid text, p_stype text, p_sid text default null, p_note text default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare v bigint;
begin
  if not exists (select 1 from public.path_domains where domain = p_domain) then raise exception 'unknown_domain'; end if;
  if p_ptype is null or p_pid is null or p_stype is null then raise exception 'bad_link'; end if;
  if p_sid is not null and p_stype = p_ptype and p_sid = p_pid then raise exception 'self_shadow'; end if;
  -- a record that is already a shadow cannot become a primary, and a primary cannot become a shadow (this is what makes "count once" hold)
  if exists (select 1 from public.shadow_links x where x.shadow_type = p_ptype and x.shadow_id = p_pid and x.state <> 'void') then raise exception 'primary_is_already_a_shadow'; end if;
  if p_sid is not null and exists (select 1 from public.shadow_links x where x.primary_type = p_stype and x.primary_id = p_sid and x.state <> 'void') then raise exception 'shadow_is_already_a_primary'; end if;
  insert into public.shadow_links (domain, location_id, primary_type, primary_id, shadow_type, shadow_id, state, note, created_by)
    values (p_domain, coalesce(p_loc, 0), p_ptype, p_pid, p_stype, p_sid, case when p_sid is null then 'pending' else 'confirmed' end, p_note, auth.uid())
    on conflict (domain, primary_type, primary_id, shadow_type) where state <> 'void' do nothing
    returning id into v;
  if v is null then
    select id into v from public.shadow_links x where x.domain = p_domain and x.primary_type = p_ptype and x.primary_id = p_pid and x.shadow_type = p_stype and x.state <> 'void';
  end if;
  return v;
end $$;

-- the owner / a manager with place access confirms a pending shadow ("one click"): it points at the record that now holds the second copy
create or replace function public.shadow_confirm(p_link bigint, p_shadow_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.shadow_links;
begin
  select * into r from public.shadow_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (r.location_id > 0 and public.can_loc(r.location_id))) then raise exception 'not allowed'; end if;
  if r.state <> 'pending' then return jsonb_build_object('id', r.id, 'state', r.state, 'noop', true); end if;
  if coalesce(p_shadow_id, r.shadow_id) is null then raise exception 'shadow_id_needed'; end if;
  if exists (select 1 from public.shadow_links x where x.primary_type = r.shadow_type and x.primary_id = coalesce(p_shadow_id, r.shadow_id) and x.state <> 'void') then raise exception 'shadow_is_already_a_primary'; end if;
  update public.shadow_links set state = 'confirmed', shadow_id = coalesce(p_shadow_id, shadow_id), confirmed_by = auth.uid(), confirmed_at = now() where id = p_link;
  return jsonb_build_object('id', r.id, 'state', 'confirmed');
end $$;

create or replace function public.shadow_void(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.shadow_links;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  select * into r from public.shadow_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if r.state = 'void' then return jsonb_build_object('id', r.id, 'state', 'void', 'noop', true); end if;
  update public.shadow_links set state = 'void', note = left(coalesce(note || ' | ', '') || 'void: ' || btrim(p_note), 300) where id = p_link;
  return jsonb_build_object('id', r.id, 'state', 'void');
end $$;

-- is this record a (locked) shadow? posting / report functions of later slices skip it so it is counted once
create or replace function public.is_shadow(p_type text, p_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.shadow_links x where x.shadow_type = p_type and x.shadow_id = p_id and x.state <> 'void');
$$;

-- ---------- 7. read-only reports ----------
create or replace function public.shadow_report(p_domain text default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ok boolean := public.is_owner();
begin
  if not (ok or (p_loc is not null and p_loc > 0 and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'counts', coalesce((select jsonb_object_agg(k, c) from (select x.domain || ':' || x.state as k, count(*) as c from public.shadow_links x
                         where (p_domain is null or x.domain = p_domain) and (p_loc is null or x.location_id in (0, p_loc)) and (ok or x.location_id = p_loc) group by 1) q), '{}'::jsonb),
    'pending', coalesce((select jsonb_agg(to_jsonb(z)) from (select x.id, x.domain, x.location_id, x.primary_type, x.primary_id, x.shadow_type, x.created_at from public.shadow_links x
                         where x.state = 'pending' and (p_domain is null or x.domain = p_domain) and (p_loc is null or x.location_id in (0, p_loc)) and (ok or x.location_id = p_loc)
                         order by x.created_at limit 100) z), '[]'::jsonb));
end $$;

-- count-once check: a shadow that ALSO reached the journal (as its own source) would be a double count. Read-only, owner only.
create or replace function public.shadow_count_once_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'shadow_in_journal', coalesce((select jsonb_agg(jsonb_build_object('link', x.id, 'domain', x.domain, 'shadow_type', x.shadow_type, 'shadow_id', x.shadow_id, 'journal_id', j.id))
        from public.shadow_links x join public.journal_entries j on j.source_type = x.shadow_type and j.source_id = x.shadow_id and j.reverses_id is null
       where x.state <> 'void'), '[]'::jsonb),
    'both_roles', coalesce((select jsonb_agg(jsonb_build_object('type', a.primary_type, 'id', a.primary_id))
        from public.shadow_links a join public.shadow_links b on b.shadow_type = a.primary_type and b.shadow_id = a.primary_id and b.state <> 'void' where a.state <> 'void'), '[]'::jsonb));
end $$;

-- ---------- 8. privileges ----------
revoke all on function public.path_cfg(text, int), public.path_primary(text, int), public.path_allowed(text, int, text), public.path_guard(text, int, text), public.path_winner(text, int, text),
  public.path_switch_set(text, int, boolean, boolean, text, text), public.path_switches(),
  public.shadow_link_add(text, int, text, text, text, text, text), public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.is_shadow(text, text),
  public.shadow_report(text, int), public.shadow_count_once_check() from public, anon;
grant execute on function public.path_cfg(text, int), public.path_primary(text, int), public.path_allowed(text, int, text), public.path_switch_set(text, int, boolean, boolean, text, text), public.path_switches(),
  public.shadow_confirm(bigint, text), public.shadow_void(bigint, text), public.shadow_report(text, int), public.shadow_count_once_check() to authenticated;
-- internal: path_guard, path_winner, shadow_link_add, is_shadow are called by SECURITY DEFINER posting functions / triggers only
revoke all on function public.path_guard(text, int, text), public.path_winner(text, int, text), public.shadow_link_add(text, int, text, text, text, text, text), public.is_shadow(text, text) from authenticated;
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase49.sql
-- ============================================================
-- Phase 49 - P1 slice 2: READ-ONLY reports (gap #15 + roadmap A1). Nothing is written, no existing record is touched.
-- Run AFTER phase48. Idempotent (create or replace).
--   daybook_vs_journal(from, to, loc)   per payment mode and per kind of money movement: what the day book shows vs what the journal holds,
--                                       with the difference. Owner or accounts_manage only; needs the accounting start date.
--   dup_suspects(from, to)              owner only. Rows that look like the same event keyed on two paths (payroll D1, stock D2, production D3,
--                                       owner money D4, cash handover D8). A suspect list to review one by one - NOT a verdict, nothing is changed.
-- ============================================================

create or replace function public.daybook_vs_journal(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); d1 date; locs int[]; rows jsonb; tot jsonb; own boolean := public.is_owner();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'why', 'accounting_start_date'); end if;
  d1 := greatest(p_from, st);
  select array_agg(l.id) into locs from public.locations l where (p_loc is null or l.id = p_loc) and (own or public.can_loc(l.id));
  if locs is null then raise exception 'not allowed'; end if;
  with db as (  -- the day book, internal hub lines kept apart, signed per mode (card settles to bank in the day book)
    select case when u.typ in ('bill', 'supplier') then 'supplier_payment' else u.typ end as k, u.mode, u.internal, case when u.dir = 'in' then u.amount else -u.amount end as s
      from (select * from public._daybook_lines(locs, locs, d1, p_to) union all select * from public._daybook_lines12(locs, d1, p_to) union all select * from public._daybook_lines23(locs, d1, p_to)) u
  ), jr as (    -- the journal: movement on the cash / bank / mobile accounts, by kind (cash_move keeps its own kind)
    select case je.source_type when 'cash_move' then coalesce(je.subtype, 'cash_move') when 'expense_voucher' then 'expense' when 'quick_expense' then 'expense' else je.source_type end as k,
           case when a.key = 'pay_cash' then 'cash' when a.key = 'pay_mobile' then 'mobile' else 'bank' end as mode, (jl.debit - jl.credit) as s
      from public.journal_entries je
      join public.journal_lines jl on jl.entry_id = je.id
      join public.acct_mappings a on a.account_id = jl.account_id and a.key in ('pay_cash', 'pay_bank', 'pay_card', 'pay_mobile')
     where je.entry_date between d1 and p_to and je.source_type <> 'opening' and (je.location_id is null or je.location_id = any (locs))
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
    'note', 'Day book counts a 10-2 voucher when submitted, the journal only when approved; payroll payments and staff advances are in the day book but have no journal source until the auto-post slice. Reversals post on the day they are made.');
end $$;

create or replace function public.dup_suspects(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb));
end $$;

revoke all on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) from public, anon;
grant execute on function public.daybook_vs_journal(date, date, int), public.dup_suspects(date, date) to authenticated;
notify pgrst, 'reload schema';

-- ============================================================================
-- End of FRESH part 4 of 21.
