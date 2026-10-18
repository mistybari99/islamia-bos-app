-- ===================== phase75.sql =====================
-- ============================================================
-- Phase 75 (bos75) - STEP C-2ক: cost sources and allocation (separate or shared bills).
--   Needs phase8 ... phase71 + phase73 + phase74. Additive; paste-twice safe. Old phases are NOT edited.
--   One place to type a bill ONCE (electricity, gas, rent, licence, repair, water, internet, any type the owner adds), in any shape:
--     separate source  = one site pays it  -> the whole bill goes straight to its destination (no allocation step)
--     shared source    = one bill covers several sites -> an allocation RULE splits it: sub-meter reading | fixed percent | floor area | headcount | output kg | whole bill to one
--                        location | other (hand-typed amounts). Every share goes to ONE destination: factory (layer 2) | showroom (layer 3) | admin (layer 3).
--   Factory shares flow BY THEMSELVES into factory_cost_pools (phase74) with the component type mapped from the cost-source type; showroom / admin shares stay in the bill-share table
--   and are read by branch_overhead() for the branch P&L (nothing is absorbed into product cost). A month with no bill is marked 'বিল বাকি' - never filled by an average.
--   Rules: percent must total 100 or saving is refused; a remainder is an 'অভাগিত' row with a yellow flag; a rule applies from its effective date, bills already allocated never change;
--   the person who entered a rule cannot approve it (rule cost_rule_self_approve, default OFF). Everything starts BLANK; the list 'ভাগ নির্ধারিত নয়' shows what has no split yet.
--   A bill is compared with the approved / submitted 10-2 expense vouchers (same place, month, head, amount) -> a yellow duplicate flag; the bill holds the detail, the 10-2 only a number.
--   Cost-right holders only (view + edit), every write has client_id + audit. A new location appears in the pickers by itself (they read the locations table).
-- ============================================================

-- ---------- settings, grants ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_rule_self_approve', 'stock', 'switch', 'false',
  'যে ভাগের নিয়ম লিখেছে সে-ই অনুমোদন করতে পারবে', 'যে allocation rule লিখেছে সে-ই approve করতে পারবে', 'The person who entered an allocation rule may also approve it',
  'Off (default) = a second person with the cost_rule_approve grant is needed (the owner can always approve what he did not enter).', 740)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cost_bill_entry', 'cost', 80, 'খরচের বিল ও সোর্স লেখা', 'Cost bill ও source লেখা', 'Enter cost sources, bills and allocation rules', 'window', null),
 ('cost_rule_approve', 'cost', 81, 'ভাগের নিয়ম অনুমোদন', 'Allocation rule approve', 'Approve an allocation rule', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- types of cost source (owner may add types; each maps to a factory component type for the pool) ----------
create table if not exists public.cost_source_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 80),
  label_en text,
  component_type text not null default 'other' references public.cost_component_types(code),    -- the pool type a FACTORY share lands in
  builtin boolean not null default false,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
insert into public.cost_source_types (code, label_bn, label_en, component_type, builtin) values
 ('electricity', 'বিদ্যুৎ', 'Electricity', 'electricity', true), ('gas', 'গ্যাস', 'Gas', 'gas', true), ('rent', 'ঘর ভাড়া', 'Rent', 'factory_rent', true),
 ('licence_fee', 'লাইসেন্স ও ফি', 'Licence and fees', 'licence_fee', true), ('machine_repair', 'যন্ত্র মেরামত', 'Machine repair', 'machine_repair', true),
 ('water', 'পানি', 'Water', 'other', true), ('internet', 'ইন্টারনেট', 'Internet', 'other', true), ('other', '☐ অন্য: ______', 'Other: ______', 'other', true)
on conflict (code) do nothing;
create sequence if not exists public.cost_stype_seq;

-- ---------- sources, covered locations ----------
create table if not exists public.cost_sources (
  id bigserial primary key,
  code text generated always as ('src-' || id::text) stored,
  cost_type text not null references public.cost_source_types(code),
  provider text check (provider is null or length(provider) <= 120),                -- provider / meter / contract no (may be blank)
  kind text not null check (kind in ('separate', 'shared')),
  dest text check (dest is null or dest in ('factory', 'showroom', 'admin')),       -- separate sources: where the whole bill goes
  frequency text not null default 'monthly' check (frequency in ('monthly', 'yearly', 'irregular')),   -- only monthly / yearly sources get the 'বিল বাকি' marker
  effective_from date not null,
  active boolean not null default true,
  retired_at timestamptz, retired_reason text,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check (kind = 'shared' or dest is not null)
);
create table if not exists public.cost_source_locs (
  source_id bigint not null references public.cost_sources(id),
  location_id int not null references public.locations(id),
  primary key (source_id, location_id)
);

-- ---------- allocation rules (versions) ----------
create table if not exists public.cost_source_rules (
  id bigserial primary key,
  source_id bigint not null references public.cost_sources(id),
  method text not null check (method in ('sub_meter', 'fixed_percent', 'floor_area', 'headcount', 'output_kg', 'whole_to_one', 'other_manual')),
  effective_from date not null,
  status text not null default 'draft' check (status in ('draft', 'approved', 'superseded')),
  complete boolean not null default false,                       -- every needed value typed (and percentages total 100)
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz
);
create unique index if not exists csr_one_approved on public.cost_source_rules (source_id, effective_from) where status = 'approved';
create table if not exists public.cost_source_rule_shares (
  id bigserial primary key,
  rule_id bigint not null references public.cost_source_rules(id),
  location_id int not null references public.locations(id),
  dest text not null check (dest in ('factory', 'showroom', 'admin')),
  value numeric check (value is null or (value >= 0 and value <= 1000000000)),       -- percent | sq ft | headcount; blank until typed
  unique (rule_id, location_id, dest)
);

-- ---------- bills, per-bill inputs, the frozen allocation ----------
create table if not exists public.cost_source_bills (
  id bigserial primary key,
  source_id bigint not null references public.cost_sources(id),
  period_kind text not null default 'month' check (period_kind in ('month', 'year')),    -- a yearly fee is spread /12 by the pool code
  period_month date not null check (period_month = date_trunc('month', period_month)::date),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  pay_mode text check (pay_mode is null or pay_mode in ('cash', 'bank', 'mobile', 'card', 'other')),
  bill_no text check (bill_no is null or length(bill_no) <= 60),
  bill_date date,
  one_off boolean not null default false,                         -- a large irregular repair: 'একবারের খরচ'
  voucher_ref text check (voucher_ref is null or length(voucher_ref) <= 40),     -- the 10-2 number, a REFERENCE only
  status text not null default 'active' check (status in ('active', 'void')),
  void_by uuid, void_at timestamptz, void_note text,
  dup_entry_id uuid, dup_head text, dup_ack boolean not null default false, dup_ack_note text,     -- the 10-2 voucher this bill looks like (same place, month, head, amount) + the reason it was accepted as different
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists csb_bill_no on public.cost_source_bills (source_id, bill_no) where bill_no is not null and status = 'active';
create index if not exists csb_month on public.cost_source_bills (period_month) where status = 'active';
create table if not exists public.cost_bill_inputs (
  bill_id bigint not null references public.cost_source_bills(id),
  location_id int not null references public.locations(id),
  dest text not null check (dest in ('factory', 'showroom', 'admin')),
  value numeric not null check (value >= 0 and value <= 1000000000000),         -- sub-meter reading, or a hand-typed amount (method other_manual)
  primary key (bill_id, location_id, dest)
);
create table if not exists public.cost_bill_shares (
  id bigserial primary key,
  bill_id bigint not null references public.cost_source_bills(id),
  kind text not null check (kind in ('share', 'unallocated')),
  location_id int references public.locations(id),
  dest text check (dest is null or dest in ('factory', 'showroom', 'admin')),
  amount numeric not null check (amount >= 0),
  pct numeric,
  rule_id bigint references public.cost_source_rules(id),
  flag text,                                                       -- why an unallocated row exists: no_rule / meter_missing / no_output / remainder / ...
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'share' and location_id is not null and dest is not null) or kind = 'unallocated')
);
create index if not exists cbs_bill on public.cost_bill_shares (bill_id) where active;

-- ---------- triggers (audit, nothing is deleted) / RLS ----------
create or replace function public._cs_no_delete() returns trigger language plpgsql as $$ begin raise exception 'nothing is deleted – retire or void instead'; end $$;
drop trigger if exists cs_types_nd on public.cost_source_types; create trigger cs_types_nd before delete on public.cost_source_types for each row execute function public._cs_no_delete();
drop trigger if exists cs_src_nd on public.cost_sources; create trigger cs_src_nd before delete on public.cost_sources for each row execute function public._cs_no_delete();
drop trigger if exists cs_locs_nd on public.cost_source_locs; create trigger cs_locs_nd before delete on public.cost_source_locs for each row execute function public._cs_no_delete();
drop trigger if exists cs_rules_nd on public.cost_source_rules; create trigger cs_rules_nd before delete on public.cost_source_rules for each row execute function public._cs_no_delete();
drop trigger if exists cs_rsh_nd on public.cost_source_rule_shares; create trigger cs_rsh_nd before delete on public.cost_source_rule_shares for each row execute function public._cs_no_delete();
drop trigger if exists cs_bills_nd on public.cost_source_bills; create trigger cs_bills_nd before delete on public.cost_source_bills for each row execute function public._cs_no_delete();
drop trigger if exists cs_inp_nd on public.cost_bill_inputs; create trigger cs_inp_nd before delete on public.cost_bill_inputs for each row execute function public._cs_no_delete();
drop trigger if exists cs_shr_nd on public.cost_bill_shares; create trigger cs_shr_nd before delete on public.cost_bill_shares for each row execute function public._cs_no_delete();
drop trigger if exists audit_cs_types on public.cost_source_types; create trigger audit_cs_types after insert or update on public.cost_source_types for each row execute function public.log_change('code');
drop trigger if exists audit_cs_src on public.cost_sources; create trigger audit_cs_src after insert or update on public.cost_sources for each row execute function public.log_change('id');
drop trigger if exists audit_cs_rules on public.cost_source_rules; create trigger audit_cs_rules after insert or update on public.cost_source_rules for each row execute function public.log_change('id');
drop trigger if exists audit_cs_rsh on public.cost_source_rule_shares; create trigger audit_cs_rsh after insert or update on public.cost_source_rule_shares for each row execute function public.log_change('id');
drop trigger if exists audit_cs_bills on public.cost_source_bills; create trigger audit_cs_bills after insert or update on public.cost_source_bills for each row execute function public.log_change('id');
drop trigger if exists audit_cs_shr on public.cost_bill_shares; create trigger audit_cs_shr after insert or update on public.cost_bill_shares for each row execute function public.log_change('id');

-- the rights: view / edit = the cost right. bill + rule entry = cost right + (owner or cost_bill_entry). rule approval = cost right + (owner or cost_rule_approve): a different person.
create or replace function public._cs_view() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok(); $$;
create or replace function public._cs_enter() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_bill_entry')); $$;
create or replace function public._cs_approve() returns boolean language sql stable security definer set search_path = public as $$ select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_rule_approve')); $$;
-- a person who may not see all places sees only the sources that touch a place of his
create or replace function public._cs_src_ok(p_source bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public._cs_view() and (public._all_locs() or exists (select 1 from public.cost_source_locs l where l.source_id = p_source and public.can_loc(l.location_id)));
$$;

alter table public.cost_source_types enable row level security;
alter table public.cost_sources enable row level security;
alter table public.cost_source_locs enable row level security;
alter table public.cost_source_rules enable row level security;
alter table public.cost_source_rule_shares enable row level security;
alter table public.cost_source_bills enable row level security;
alter table public.cost_bill_inputs enable row level security;
alter table public.cost_bill_shares enable row level security;
drop policy if exists cs_types_read on public.cost_source_types; create policy cs_types_read on public.cost_source_types for select to authenticated using (public._cs_view());
drop policy if exists cs_src_read on public.cost_sources; create policy cs_src_read on public.cost_sources for select to authenticated using (public._cs_src_ok(id));
drop policy if exists cs_locs_read on public.cost_source_locs; create policy cs_locs_read on public.cost_source_locs for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_rules_read on public.cost_source_rules; create policy cs_rules_read on public.cost_source_rules for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_rsh_read on public.cost_source_rule_shares; create policy cs_rsh_read on public.cost_source_rule_shares for select to authenticated using (public._cs_src_ok((select r.source_id from public.cost_source_rules r where r.id = rule_id)));
drop policy if exists cs_bills_read on public.cost_source_bills; create policy cs_bills_read on public.cost_source_bills for select to authenticated using (public._cs_src_ok(source_id));
drop policy if exists cs_inp_read on public.cost_bill_inputs; create policy cs_inp_read on public.cost_bill_inputs for select to authenticated using (public._cs_src_ok((select b.source_id from public.cost_source_bills b where b.id = bill_id)));
drop policy if exists cs_shr_read on public.cost_bill_shares; create policy cs_shr_read on public.cost_bill_shares for select to authenticated using (public._cs_src_ok((select b.source_id from public.cost_source_bills b where b.id = bill_id)));
revoke all on public.cost_source_types, public.cost_sources, public.cost_source_locs, public.cost_source_rules, public.cost_source_rule_shares, public.cost_source_bills, public.cost_bill_inputs, public.cost_bill_shares from anon, authenticated;
grant select on public.cost_source_types, public.cost_sources, public.cost_source_locs, public.cost_source_rules, public.cost_source_rule_shares, public.cost_source_bills, public.cost_bill_inputs, public.cost_bill_shares to authenticated;
revoke all on sequence public.cost_sources_id_seq, public.cost_source_rules_id_seq, public.cost_source_rule_shares_id_seq, public.cost_source_bills_id_seq, public.cost_bill_shares_id_seq, public.cost_stype_seq from anon, authenticated;

-- ---------- types ----------
create or replace function public.cost_source_type_add(p_label_bn text, p_label_en text default null, p_component_type text default 'other') returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_label_bn is null or length(btrim(p_label_bn)) < 1 or length(btrim(p_label_bn)) > 80 then raise exception 'name_needed'; end if;
  if not exists (select 1 from public.cost_component_types where code = coalesce(p_component_type, 'other') and active) then raise exception 'unknown_type'; end if;
  c := 'y' || nextval('public.cost_stype_seq')::text;
  insert into public.cost_source_types (code, label_bn, label_en, component_type, builtin, created_by) values (c, btrim(p_label_bn), left(nullif(btrim(p_label_en), ''), 80), coalesce(p_component_type, 'other'), false, auth.uid());
  return jsonb_build_object('code', c);
end $$;

-- ---------- sources ----------
-- create (p_id null) or edit. After a bill exists the type / kind / places / destination no longer change (open a new source instead).
create or replace function public.cost_source_save(p_id bigint, p_type text, p_provider text, p_kind text, p_dest text, p_locs int[], p_frequency text, p_effective date, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; l int; n int := 0; sid bigint;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_kind not in ('separate', 'shared') then raise exception 'bad_value'; end if;
  if p_frequency not in ('monthly', 'yearly', 'irregular') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.cost_source_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  if p_locs is null or coalesce(array_length(p_locs, 1), 0) = 0 then raise exception 'locations_needed'; end if;
  foreach l in array p_locs loop
    if not exists (select 1 from public.locations where id = l) then raise exception 'unknown location'; end if;
    if not (public._all_locs() or public.can_loc(l)) then raise exception 'not allowed'; end if;
  end loop;
  if p_kind = 'separate' then
    if array_length(p_locs, 1) <> 1 then raise exception 'separate_one_location'; end if;
    if p_dest is null or p_dest not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
  else
    if (select count(distinct x) from unnest(p_locs) x) < 2 then raise exception 'shared_needs_two'; end if;
  end if;
  if p_id is null then
    if p_client is not null then
      select * into s from public.cost_sources where client_id = p_client;
      if found then return jsonb_build_object('dup', true, 'id', s.id, 'code', s.code); end if;
    end if;
    insert into public.cost_sources (cost_type, provider, kind, dest, frequency, effective_from, note, client_id, created_by)
      values (p_type, left(nullif(btrim(p_provider), ''), 120), p_kind, case when p_kind = 'separate' then p_dest end, p_frequency, p_effective, left(p_note, 300), p_client, auth.uid()) returning id into sid;
    insert into public.cost_source_locs (source_id, location_id) select sid, x from (select distinct unnest(p_locs) x) z;
  else
    select * into s from public.cost_sources where id = p_id for update;
    if not found then raise exception 'source_not_found'; end if;
    if exists (select 1 from public.cost_source_bills where source_id = p_id) and (s.cost_type <> p_type or s.kind <> p_kind or s.dest is distinct from (case when p_kind = 'separate' then p_dest end)
        or (select array_agg(location_id order by location_id) from public.cost_source_locs where source_id = p_id) is distinct from (select array_agg(x order by x) from (select distinct unnest(p_locs) x) z)) then raise exception 'source_in_use'; end if;
    update public.cost_sources set cost_type = p_type, provider = left(nullif(btrim(p_provider), ''), 120), kind = p_kind, dest = case when p_kind = 'separate' then p_dest end, frequency = p_frequency,
      effective_from = p_effective, note = left(p_note, 300) where id = p_id;
    insert into public.cost_source_locs (source_id, location_id) select p_id, x from (select distinct unnest(p_locs) x) z on conflict do nothing;
    sid := p_id;
  end if;
  return jsonb_build_object('id', sid, 'code', 'src-' || sid::text);
end $$;
create or replace function public.cost_source_set_active(p_id bigint, p_active boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cost_sources set active = p_active, retired_at = case when p_active then null else now() end, retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'source_not_found'; end if;
end $$;

-- ---------- allocation rules ----------
-- p_shares = [{location_id, dest, value}] ; value blank = not typed yet (the rule stays a draft that cannot be approved). Percentages: if every value is typed they must total 100.
create or replace function public.cost_rule_save(p_source bigint, p_method text, p_effective date, p_shares jsonb, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; x jsonb; rid bigint; v numeric; n int := 0; nblank int := 0; tot numeric := 0; seen text[] := '{}'; k text; loc int; ds text; dup public.cost_source_rules; cpl boolean;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into dup from public.cost_source_rules where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', dup.id); end if; end if;
  select * into s from public.cost_sources where id = p_source;
  if not found then raise exception 'source_not_found'; end if;
  if not public._cs_src_ok(p_source) then raise exception 'not allowed'; end if;
  if s.kind <> 'shared' then raise exception 'not_shared'; end if;
  if p_method not in ('sub_meter', 'fixed_percent', 'floor_area', 'headcount', 'output_kg', 'whole_to_one', 'other_manual') then raise exception 'bad_value'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  if p_shares is null or jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then raise exception 'no_lines'; end if;
  for x in select e from jsonb_array_elements(p_shares) e loop
    loc := nullif(x->>'location_id', '')::int; ds := x->>'dest';
    if loc is null or not exists (select 1 from public.cost_source_locs where source_id = p_source and location_id = loc) then raise exception 'location_not_covered'; end if;
    if ds is null or ds not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
    k := loc::text || ':' || ds;
    if k = any(seen) then raise exception 'dup_share'; end if;
    seen := seen || k; n := n + 1;
    v := nullif(btrim(x->>'value'), '')::numeric;
    if v is not null and not (v >= 0 and v <= 1000000000) then raise exception 'bad_qty'; end if;
    if v is null then nblank := nblank + 1; else tot := tot + v; end if;
  end loop;
  if p_method = 'whole_to_one' and n <> 1 then raise exception 'one_target_needed'; end if;
  if p_method <> 'whole_to_one' and n < 2 then raise exception 'two_targets_needed'; end if;
  if p_method = 'fixed_percent' and nblank = 0 and abs(tot - 100) > 0.0001 then raise exception 'percent_not_100' using detail = tot::text; end if;
  cpl := case when p_method in ('fixed_percent', 'floor_area', 'headcount') then nblank = 0 and (p_method <> 'fixed_percent' or abs(tot - 100) <= 0.0001) and (p_method = 'fixed_percent' or tot > 0) else true end;
  insert into public.cost_source_rules (source_id, method, effective_from, complete, note, client_id, created_by) values (p_source, p_method, p_effective, cpl, left(p_note, 300), p_client, auth.uid()) returning id into rid;
  for x in select e from jsonb_array_elements(p_shares) e loop
    insert into public.cost_source_rule_shares (rule_id, location_id, dest, value) values (rid, (x->>'location_id')::int, x->>'dest', case when p_method in ('fixed_percent', 'floor_area', 'headcount') then nullif(btrim(x->>'value'), '')::numeric end);
  end loop;
  return jsonb_build_object('id', rid, 'status', 'draft', 'complete', cpl, 'blank_values', nblank);
end $$;

-- ---------- the allocation of ONE bill (frozen at the time; never recomputed once fully allocated) ----------
create or replace function public._cs_rule_in_force(p_source bigint, p_month date) returns bigint
language sql stable security definer set search_path = public as $$
  select id from public.cost_source_rules where source_id = p_source and status = 'approved' and complete and effective_from <= (p_month + interval '1 month' - interval '1 day')::date
   order by effective_from desc, id desc limit 1;
$$;

create or replace function public._cs_alloc(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; s public.cost_sources; r public.cost_source_rules; sh record; inp record; rid bigint; tot numeric := 0; acc numeric := 0; n int := 0; i int := 0; amt numeric; pct numeric;
        why text := null; rem numeric; l1 int; kgs numeric; arr jsonb := '[]'::jsonb; e jsonb; m date;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  select * into s from public.cost_sources where id = b.source_id;
  update public.cost_bill_shares set active = false where bill_id = p_bill and active;
  if s.kind = 'separate' then
    select location_id into l1 from public.cost_source_locs where source_id = s.id limit 1;
    insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, created_by) values (p_bill, 'share', l1, s.dest, b.amount, 100, auth.uid());
  else
    rid := public._cs_rule_in_force(s.id, b.period_month);
    if rid is null then
      insert into public.cost_bill_shares (bill_id, kind, amount, flag, created_by) values (p_bill, 'unallocated', b.amount, 'no_rule', auth.uid());
    else
      select * into r from public.cost_source_rules where id = rid;
      -- a list of {location, dest, weight}
      if r.method = 'whole_to_one' then
        for sh in select * from public.cost_source_rule_shares where rule_id = rid loop arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', 1); end loop;
      elsif r.method in ('fixed_percent', 'floor_area', 'headcount') then
        for sh in select * from public.cost_source_rule_shares where rule_id = rid order by location_id, dest loop arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', sh.value); end loop;
      elsif r.method = 'sub_meter' then
        if exists (select 1 from public.cost_source_rule_shares h where h.rule_id = rid and not exists (select 1 from public.cost_bill_inputs i2 where i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest)) then why := 'meter_missing';
        else for sh in select h.location_id, h.dest, i2.value from public.cost_source_rule_shares h join public.cost_bill_inputs i2 on i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest where h.rule_id = rid order by h.location_id, h.dest loop
               arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', sh.value); end loop; end if;
      elsif r.method = 'output_kg' then
        m := b.period_month;
        for sh in select h.location_id, h.dest from public.cost_source_rule_shares h where h.rule_id = rid order by h.location_id, h.dest loop
          select coalesce(sum(pr.yield_base), 0) into kgs from public.production_runs pr join public.items it on it.id = pr.item_id
            where pr.location_id = sh.location_id and pr.status = 'done' and lower(coalesce(public._item_base(pr.item_id), '')) = 'kg'
              and public._m1((pr.made_at at time zone 'Asia/Dhaka')::date) = m;
          arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'w', kgs);
        end loop;
      else      -- other_manual: hand-typed AMOUNTS for this bill
        for sh in select h.location_id, h.dest, i2.value from public.cost_source_rule_shares h join public.cost_bill_inputs i2 on i2.bill_id = p_bill and i2.location_id = h.location_id and i2.dest = h.dest where h.rule_id = rid order by h.location_id, h.dest loop
          arr := arr || jsonb_build_object('l', sh.location_id, 'd', sh.dest, 'a', sh.value); end loop;
      end if;
      n := jsonb_array_length(arr);
      if why is null and n = 0 then why := case when r.method = 'other_manual' then 'amounts_missing' else 'no_targets' end; end if;
      if why is null and r.method <> 'other_manual' then
        select coalesce(sum((x->>'w')::numeric), 0) into tot from jsonb_array_elements(arr) x;
        if tot <= 0 then why := case when r.method = 'output_kg' then 'no_output' else 'zero_total' end; end if;
      end if;
      if why is not null then
        insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', b.amount, why, rid, auth.uid());
      elsif r.method = 'other_manual' then
        for e in select x from jsonb_array_elements(arr) x loop acc := acc + (e->>'a')::numeric; end loop;
        if acc > b.amount + 0.005 then
          insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', b.amount, 'shares_exceed_bill', rid, auth.uid());
        else
          for e in select x from jsonb_array_elements(arr) x loop
            insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, rule_id, created_by) values (p_bill, 'share', (e->>'l')::int, e->>'d', round((e->>'a')::numeric, 2), round((e->>'a')::numeric / b.amount * 100, 4), rid, auth.uid());
          end loop;
          rem := round(b.amount - round(acc, 2), 2);
          if rem > 0.004 then insert into public.cost_bill_shares (bill_id, kind, amount, flag, rule_id, created_by) values (p_bill, 'unallocated', rem, 'remainder', rid, auth.uid()); end if;
        end if;
      else
        i := 0; acc := 0;
        for e in select x from jsonb_array_elements(arr) x loop
          i := i + 1; pct := (e->>'w')::numeric / tot * 100;
          amt := case when i = n then round(b.amount - acc, 2) else round(b.amount * (e->>'w')::numeric / tot, 2) end;      -- the last share takes the rounding: the shares always sum to the bill
          acc := acc + amt;
          insert into public.cost_bill_shares (bill_id, kind, location_id, dest, amount, pct, rule_id, created_by) values (p_bill, 'share', (e->>'l')::int, e->>'d', amt, round(pct, 4), rid, auth.uid());
        end loop;
      end if;
    end if;
  end if;
  perform public._cs_push_pools(p_bill);
  if exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated') then
    select location_id into l1 from public.cost_source_locs where source_id = s.id order by location_id limit 1;
    perform public._stock_exc(l1, 'cost_bill_unallocated', 'yellow', 'খরচের বিলের অভাগিত অংশ আছে (' || s.code || ')', 'A cost bill has an unallocated part (' || s.code || ')', null, coalesce(b.bill_date, b.period_month), 'STOCK');
  end if;
end $$;

-- factory shares flow BY THEMSELVES into the pools (type mapped from the source type); the rows of a bill are replaced whenever it is allocated again; showroom / admin shares stay here (branch_overhead)
create or replace function public._cs_push_pools(p_bill bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; ct text; sh record;
begin
  select * into b from public.cost_source_bills where id = p_bill;
  update public.factory_cost_pools set active = false where source = 'allocated' and ref like 'bill:' || p_bill::text || ':%' and active;
  if b.status <> 'active' then return; end if;
  select t.component_type into ct from public.cost_sources s join public.cost_source_types t on t.code = s.cost_type where s.id = b.source_id;
  for sh in select location_id, sum(amount) amt from public.cost_bill_shares where bill_id = p_bill and active and kind = 'share' and dest = 'factory' group by location_id loop
    if sh.amt > 0 then
      insert into public.factory_cost_pools (location_id, month, component_type, period_kind, actual_amount, one_off, source, ref, note, created_by)
        values (sh.location_id, b.period_month, coalesce(ct, 'other'), b.period_kind, sh.amt, b.one_off, 'allocated', 'bill:' || p_bill::text || ':' || sh.location_id::text, 'from cost bill ' || p_bill::text, auth.uid());
    end if;
  end loop;
end $$;

-- ---------- bills ----------
-- p_inputs = [{location_id, dest, value}] : the sub-meter readings of this bill, or the hand-typed amounts (rule method other_manual). Everything else is derived.
create or replace function public.cost_bill_add(p_source bigint, p_period_kind text, p_month date, p_amount numeric, p_pay_mode text default null, p_bill_no text default null, p_bill_date date default null,
  p_one_off boolean default false, p_inputs jsonb default null, p_voucher_ref text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.cost_sources; b public.cost_source_bills; bid bigint; m date := public._m1(p_month); x jsonb; heads text[]; e record; shares jsonb; unalloc numeric; dupid uuid; duph text; bn text := nullif(btrim(p_bill_no), '');
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into b from public.cost_source_bills where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', b.id); end if; end if;
  select * into s from public.cost_sources where id = p_source;
  if not found then raise exception 'source_not_found'; end if;
  if not public._cs_src_ok(p_source) then raise exception 'not allowed'; end if;
  if not s.active then raise exception 'source_retired'; end if;
  if p_period_kind not in ('month', 'year') then raise exception 'bad_value'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount > 0 and p_amount <= 1000000000000) then raise exception 'bad_cost'; end if;
  if p_pay_mode is not null and p_pay_mode not in ('cash', 'bank', 'mobile', 'card', 'other') then raise exception 'bad_value'; end if;
  if bn is not null and exists (select 1 from public.cost_source_bills where source_id = p_source and bill_no = bn and status = 'active') then raise exception 'duplicate_bill'; end if;
  insert into public.cost_source_bills (source_id, period_kind, period_month, amount, pay_mode, bill_no, bill_date, one_off, voucher_ref, client_id, created_by)
    values (p_source, p_period_kind, m, p_amount, p_pay_mode, bn, p_bill_date, coalesce(p_one_off, false), left(nullif(btrim(p_voucher_ref), ''), 40), p_client, auth.uid()) returning id into bid;
  if p_inputs is not null and jsonb_typeof(p_inputs) = 'array' then
    for x in select e2 from jsonb_array_elements(p_inputs) e2 loop
      if not exists (select 1 from public.cost_source_locs where source_id = p_source and location_id = (x->>'location_id')::int) then raise exception 'location_not_covered'; end if;
      if (x->>'dest') not in ('factory', 'showroom', 'admin') then raise exception 'dest_needed'; end if;
      if nullif(btrim(x->>'value'), '') is not null then
        if not ((x->>'value')::numeric >= 0) then raise exception 'bad_qty'; end if;
        insert into public.cost_bill_inputs (bill_id, location_id, dest, value) values (bid, (x->>'location_id')::int, x->>'dest', (x->>'value')::numeric)
          on conflict (bill_id, location_id, dest) do update set value = excluded.value;
      end if;
    end loop;
  end if;
  -- the duplicate guard against form 10-2: same place, month, head and amount (an imprest voucher that already carries this cost)
  heads := case when s.cost_type in ('electricity', 'gas', 'water', 'internet', 'machine_repair') then array['repair'] else array['other'] end;
  select en.id, ln->>'head' into dupid, duph from public.entries en cross join lateral jsonb_array_elements(case when jsonb_typeof(en.data->'lines') = 'array' then en.data->'lines' else '[]'::jsonb end) ln
    where en.form_code = '10-2' and en.status in ('submitted', 'approved') and en.location_id in (select location_id from public.cost_source_locs where source_id = p_source)
      and public._m1(en.entry_date) = m and lower(coalesce(ln->>'head', '')) = any(heads) and public._acct_num(ln->>'amount') = p_amount
    order by en.entry_date desc limit 1;
  if dupid is not null then
    update public.cost_source_bills set dup_entry_id = dupid, dup_head = duph where id = bid;
    perform public._stock_exc((select location_id from public.cost_source_locs where source_id = p_source order by location_id limit 1), 'cost_bill_dup_voucher', 'yellow',
      'খরচের বিল ১০-২ ভাউচারের সাথে মিলে যাচ্ছে (একই জায়গা, মাস, খাত, টাকা) — একবারই ধরুন', 'A cost bill looks like a 10-2 voucher (same place, month, head, amount) - count it once', null, coalesce(p_bill_date, m), 'STOCK', p_amount);
  end if;
  -- hand-typed amounts (rule method other_manual) can never total more than the bill: the whole entry is refused
  if exists (select 1 from public.cost_source_rules r where r.id = public._cs_rule_in_force(p_source, m) and r.method = 'other_manual')
     and coalesce((select sum(value) from public.cost_bill_inputs where bill_id = bid), 0) > p_amount + 0.005 then raise exception 'shares_exceed_bill'; end if;
  perform public._cs_alloc(bid);
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'location_id', location_id, 'dest', dest, 'amount', amount, 'pct', pct, 'flag', flag) order by id), '[]'::jsonb), coalesce(sum(amount) filter (where kind = 'unallocated'), 0)
    into shares, unalloc from public.cost_bill_shares where bill_id = bid and active;
  return jsonb_build_object('id', bid, 'shares', shares, 'unallocated', unalloc, 'dup_voucher', dupid is not null, 'dup_voucher_id', dupid);
end $$;

-- a late sub-meter reading / a rule approved after the bill: allocate again - ONLY a bill that still has an unallocated part (a fully allocated bill never changes)
create or replace function public.cost_bill_reallocate(p_bill bigint, p_inputs jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills; x jsonb; unalloc numeric;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  select * into b from public.cost_source_bills where id = p_bill for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  if b.status <> 'active' then raise exception 'bill_void'; end if;
  if exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active) and not exists (select 1 from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated') then raise exception 'already_allocated'; end if;
  if p_inputs is not null and jsonb_typeof(p_inputs) = 'array' then
    for x in select e2 from jsonb_array_elements(p_inputs) e2 loop
      if not exists (select 1 from public.cost_source_locs where source_id = b.source_id and location_id = (x->>'location_id')::int) then raise exception 'location_not_covered'; end if;
      if nullif(btrim(x->>'value'), '') is not null then
        insert into public.cost_bill_inputs (bill_id, location_id, dest, value) values (p_bill, (x->>'location_id')::int, x->>'dest', (x->>'value')::numeric) on conflict (bill_id, location_id, dest) do update set value = excluded.value;
      end if;
    end loop;
  end if;
  perform public._cs_alloc(p_bill);
  select coalesce(sum(amount), 0) into unalloc from public.cost_bill_shares where bill_id = p_bill and active and kind = 'unallocated';
  return jsonb_build_object('id', p_bill, 'unallocated', unalloc);
end $$;

create or replace function public.cost_bill_void(p_bill bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into b from public.cost_source_bills where id = p_bill for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  if b.status = 'void' then return; end if;
  update public.cost_source_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_bill;
  update public.cost_bill_shares set active = false where bill_id = p_bill and active;
  perform public._cs_push_pools(p_bill);       -- the pool rows of this bill are retired
end $$;

-- "this is a different cost, not the 10-2 one": acknowledges the duplicate flag (kept in the audit log)
create or replace function public.cost_bill_dup_ack(p_bill bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.cost_source_bills;
begin
  if not public._cs_enter() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into b from public.cost_source_bills where id = p_bill;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(b.source_id) then raise exception 'not allowed'; end if;
  update public.cost_source_bills set dup_ack = true, dup_ack_note = left(btrim(p_note), 300) where id = p_bill and dup_entry_id is not null;
end $$;

-- ---------- approval of a rule: a different person; applies from its effective date, never to a fully allocated bill ----------
create or replace function public.cost_rule_approve(p_rule bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cost_source_rules; b record; n int := 0;
begin
  if not public._cs_approve() then raise exception 'not allowed'; end if;
  select * into r from public.cost_source_rules where id = p_rule for update;
  if not found then raise exception 'not_found'; end if;
  if not public._cs_src_ok(r.source_id) then raise exception 'not allowed'; end if;
  if r.status = 'approved' then return jsonb_build_object('dup', true, 'id', r.id); end if;
  if r.status <> 'draft' then raise exception 'rule_not_draft'; end if;
  if not r.complete then raise exception 'rule_incomplete'; end if;
  if r.created_by is not distinct from auth.uid() and not public.rule_on('cost_rule_self_approve') then raise exception 'self_approve_refused'; end if;
  update public.cost_source_rules set status = 'superseded' where source_id = r.source_id and status = 'approved' and effective_from = r.effective_from;      -- same date: the new one replaces the old (kept)
  update public.cost_source_rules set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_rule;
  -- bills that still wait for a split (no rule / blank) may now be allocated; fully allocated bills are NOT touched
  for b in select distinct bl.id from public.cost_source_bills bl where bl.source_id = r.source_id and bl.status = 'active' and bl.period_month >= date_trunc('month', r.effective_from)::date
      and (not exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active) or exists (select 1 from public.cost_bill_shares x where x.bill_id = bl.id and x.active and x.kind = 'unallocated')) loop
    perform public._cs_alloc(b.id); n := n + 1;
  end loop;
  return jsonb_build_object('id', p_rule, 'approved', true, 'bills_allocated', n);
end $$;

-- ---------- reports ----------
-- one screen's worth for a month: বিল বাকি, ভাগ নির্ধারিত নয়, অভাগিত, duplicates
create or replace function public.cost_sources_status(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); pend jsonb; noshare jsonb; unal jsonb; dups jsonb;
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'code', s.code, 'cost_type', s.cost_type, 'frequency', s.frequency, 'label_bn', 'বিল বাকি', 'label_en', 'Bill pending') order by s.id), '[]'::jsonb) into pend
    from public.cost_sources s where s.active and public._cs_src_ok(s.id) and s.effective_from <= (m + interval '1 month' - interval '1 day')::date and s.frequency in ('monthly', 'yearly')
     and not exists (select 1 from public.cost_source_bills b where b.source_id = s.id and b.status = 'active' and ((b.period_kind = 'month' and b.period_month = m) or (b.period_kind = 'year' and m >= b.period_month and m < (b.period_month + interval '12 months')::date)));
  select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'code', s.code, 'cost_type', s.cost_type, 'reason', case when rr.id is null then 'no_rule' when rr.status = 'draft' then 'draft' else 'incomplete' end, 'rule_id', rr.id,
      'label_bn', 'ভাগ নির্ধারিত নয়', 'label_en', 'Split not set') order by s.id), '[]'::jsonb) into noshare
    from public.cost_sources s left join lateral (select * from public.cost_source_rules x where x.source_id = s.id and x.status <> 'superseded' order by (x.status = 'approved') desc, x.effective_from desc, x.id desc limit 1) rr on true
   where s.active and s.kind = 'shared' and public._cs_src_ok(s.id) and (public._cs_rule_in_force(s.id, m) is null);
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', b.id, 'source_id', b.source_id, 'amount', x.amount, 'flag', x.flag, 'label_bn', 'অভাগিত', 'label_en', 'Unallocated') order by b.id), '[]'::jsonb) into unal
    from public.cost_bill_shares x join public.cost_source_bills b on b.id = x.bill_id where x.active and x.kind = 'unallocated' and b.status = 'active' and public._cs_src_ok(b.source_id) and b.period_month = m;
  select coalesce(jsonb_agg(jsonb_build_object('bill_id', b.id, 'source_id', b.source_id, 'amount', b.amount, 'voucher_head', b.dup_head, 'entry_id', b.dup_entry_id) order by b.id), '[]'::jsonb) into dups
    from public.cost_source_bills b where b.status = 'active' and b.dup_entry_id is not null and not b.dup_ack and public._cs_src_ok(b.source_id) and b.period_month = m;
  return jsonb_build_object('month', m, 'bills_pending', pend, 'split_not_set', noshare, 'unallocated', unal, 'duplicates', dups);
end $$;

-- the layer-3 view for the BRANCH P&L: showroom + admin shares per place and month (yearly fees spread /12), plus what went into product cost (factory)
create or replace function public.branch_overhead(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb;
begin
  if not (public._cs_view() and (public._all_locs() or public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('month', z.mth, 'dest', z.dest, 'cost_type', z.cost_type, 'amount', round(z.amt, 2)) order by z.mth, z.dest, z.cost_type), '[]'::jsonb) into rows_ from (
    select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.dest, s.cost_type,
           sum(case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
      from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id
      cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
     where sh.active and sh.kind = 'share' and b.status = 'active' and sh.location_id = p_loc
       and (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31')
     group by 1, 2, 3) z;
  return jsonb_build_object('location_id', p_loc, 'rows', rows_, 'note', 'showroom / admin rows go to the branch P&L; factory rows are in the product cost through the pools');
end $$;

-- the pickers: every active location of the business, new ones included (nothing in the code names a location)
create or replace function public.cost_pick_locations() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'code', l.code, 'name_bn', l.name_bn, 'name_en', l.name_en, 'kind', l.kind) order by l.id) from public.locations l where l.is_active and (public._all_locs() or public.can_loc(l.id))), '[]'::jsonb);
end $$;

-- ---------- re-created from phase74: pool_set now warns when a bill already feeds the same pool (two entries would count twice) ----------
create or replace function public.pool_set(p_loc int, p_month date, p_type text, p_amount numeric, p_period_kind text default 'month', p_one_off boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $$;

-- ---------- privileges ----------
grant execute on function public._cs_src_ok(bigint), public._cs_view() to authenticated;       -- used by the read policies
revoke all on function public._cs_no_delete(), public._cs_enter(), public._cs_approve(), public._cs_rule_in_force(bigint, date), public._cs_alloc(bigint), public._cs_push_pools(bigint) from public, anon, authenticated;
revoke all on function public._cs_view(), public._cs_src_ok(bigint) from public, anon;
revoke all on function public.cost_source_type_add(text, text, text), public.cost_source_save(bigint, text, text, text, text, int[], text, date, text, uuid), public.cost_source_set_active(bigint, boolean, text),
  public.cost_rule_save(bigint, text, date, jsonb, text, uuid), public.cost_bill_add(bigint, text, date, numeric, text, text, date, boolean, jsonb, text, uuid), public.cost_bill_reallocate(bigint, jsonb),
  public.cost_bill_void(bigint, text), public.cost_bill_dup_ack(bigint, text), public.cost_rule_approve(bigint, text), public.cost_sources_status(date), public.branch_overhead(int, date, date),
  public.cost_pick_locations(), public.pool_set(int, date, text, numeric, text, boolean, text, uuid) from public, anon;
grant execute on function public.cost_source_type_add(text, text, text), public.cost_source_save(bigint, text, text, text, text, int[], text, date, text, uuid), public.cost_source_set_active(bigint, boolean, text),
  public.cost_rule_save(bigint, text, date, jsonb, text, uuid), public.cost_bill_add(bigint, text, date, numeric, text, text, date, boolean, jsonb, text, uuid), public.cost_bill_reallocate(bigint, jsonb),
  public.cost_bill_void(bigint, text), public.cost_bill_dup_ack(bigint, text), public.cost_rule_approve(bigint, text), public.cost_sources_status(date), public.branch_overhead(int, date, date),
  public.cost_pick_locations(), public.pool_set(int, date, text, numeric, text, boolean, text, uuid) to authenticated;

-- ===================== phase76.sql =====================
-- ============================================================
-- Phase 76 (bos76) - Step H: sales channels + message inbox + web order form intake + Meta message intake (pull-in only).
-- Run AFTER phase61/62/70/71. Additive + idempotent (paste twice = no error). No old phase file is changed.
-- Re-created (latest definition, only bos76 lines changed): online_orders_list, online_order_get (customer phone/address mask + view audit).
--
--   H1  sales_channels (kind, branch, role, account ref, active). online_orders gets channel_id, external_ref, source, pay_mode(+other), pay_ref
--       (old text column `channel` keeps working). online_order_save2() = the EXISTING online_order_save + the new columns, one transaction.
--   H2  inbound_messages (unique per channel + external id) + trail; inbox_list / inbox_get / inbox_set_status / inbox_board.
--   H3  web_order_submit(): web / landing form, fully automatic, saves THROUGH online_order_save (never a table write). client id = submission id.
--       Price and total are computed by the server; only active + sellable items; captcha hook + rate limit (rules).
--   H4  inbound_message_receive(): Meta (Messenger / Instagram / WhatsApp) webhook receiver side; signature result comes from the Edge function
--       (the HMAC itself is also available in SQL: inbound_sig_verify). Idempotent on (channel, external id). Pull in only; no reply.
--   H5  messages never become orders by themselves. online_order_save2(p_draft) makes a DRAFT (switch inbox_autodraft_on, default OFF);
--       a draft cannot be confirmed / packed / delivered until a person verifies it (online_order_draft_verify). No AI call here.
--   H6  order_dup_flags (same customer + same item + same day, different channels = FLAG only), PII mask + view audit,
--       intake_failures (failed list + retry), inbox_board (new messages, last message time, silence warning).
-- Switches (all OFF unless noted): inbox_on, meta_intake_on, web_form_on, web_form_captcha_on, inbox_autodraft_on, inbox_pii_guard_on.
-- Numbers: web_form_rate_max, web_form_rate_window_min, inbox_silence_hours, intake_max_tries, intake_retry_min. Text: web_form_public_url.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('inbox_on', 'pos', 'switch', 'false', null, null, null, null, 'বার্তা ইনবক্স চালু', 'Message inbox চালু', 'Message inbox is on',
  'চালু হলে বাইরের বার্তা ইনবক্সে জমা হয়; অর্ডার বানায় মানুষ।', 'When on, outside messages collect in the inbox; a person makes the order.', 620),
 ('meta_intake_on', 'pos', 'switch', 'false', null, null, null, null, 'ফেসবুক/ইনস্টাগ্রাম/হোয়াটসঅ্যাপ বার্তা ঢোকা চালু', 'FB / IG / WhatsApp বার্তা intake চালু', 'Facebook / Instagram / WhatsApp message intake is on',
  'বাইরের সংযোগ (Edge ফাংশন) তৈরি না হওয়া পর্যন্ত এটি চালু করলেও কিছু আসবে না।', 'Nothing arrives until the outside connection (Edge function) exists, even if this is on.', 621),
 ('web_form_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব অর্ডার ফর্ম চালু', 'Web order form চালু', 'Web order form is on',
  'চালু হলে ওয়েব ফর্মের অর্ডার নিজে থেকে অর্ডার তালিকায় ঢোকে (নতুন অবস্থায়, স্টাফ নিশ্চিত করে)।', 'When on, web form orders enter the order list by themselves (status new; staff confirm).', 622),
 ('web_form_captcha_on', 'pos', 'switch', 'false', null, null, null, null, 'ওয়েব ফর্মে ক্যাপচা বাধ্যতামূলক', 'Web form-এ captcha বাধ্যতামূলক', 'Web form needs a captcha pass',
  'চালু হলে ক্যাপচা পাশ না করা জমা নেওয়া হয় না (ক্যাপচা পরিষেবা আলাদা সেটআপ লাগে)।', 'When on, a submission without a passed captcha is refused (needs a captcha service set up separately).', 623),
 ('web_form_rate_max', 'pos', 'number', '10', 'বার', null, 0, 1000, 'ওয়েব ফর্ম: এক ডিভাইস সর্বোচ্চ কতবার', 'Web form: এক device-এ সর্বোচ্চ কতবার', 'Web form: max submissions per device',
  '০ = সীমা নেই। সময়ের জানালা পরের সেটিংয়ে।', '0 = no limit. The time window is the next setting.', 624),
 ('web_form_rate_window_min', 'pos', 'number', '60', 'মিনিট', null, 1, 1440, 'ওয়েব ফর্ম: সীমার সময়ের জানালা', 'Web form: limit-এর সময়ের window', 'Web form: rate window',
  null, null, 625),
 ('inbox_autodraft_on', 'pos', 'switch', 'false', null, null, null, null, 'বার্তা থেকে অর্ডারের খসড়া (যাচাই বাকি) চালু', 'Message থেকে order খসড়া (যাচাই বাকি) চালু', 'Order drafts from messages (needs checking)',
  'খসড়া কখনো নিজে নিশ্চিত হয় না; মানুষ যাচাই না করলে স্টক/বিক্রি কিছু নড়ে না।', 'A draft never confirms itself; without a person checking it, no stock and no sale moves.', 626),
 ('inbox_pii_guard_on', 'pos', 'switch', 'false', null, null, null, null, 'গ্রাহকের ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের', 'Customer ফোন/ঠিকানা শুধু অনুমতিপ্রাপ্তদের', 'Customer phone/address only for authorised people',
  'চালু হলে মালিক বা "গ্রাহকের যোগাযোগ দেখা" অনুমতি ছাড়া ফোন/ঠিকানা ঢাকা থাকে। প্রতিবার দেখা লগে থাকে।', 'When on, phone/address are hidden unless owner or the contact-view grant. Every view is logged.', 627),
 ('inbox_silence_hours', 'pos', 'number', '24', 'ঘণ্টা', null, 0, 720, 'এত ঘণ্টা বার্তা না এলে সতর্কতা', 'এত ঘণ্টা message না এলে warning', 'Warn when no message for (hours)',
  '০ = সতর্কতা বন্ধ।', '0 = no warning.', 628),
 ('intake_max_tries', 'pos', 'number', '5', 'বার', null, 1, 20, 'ব্যর্থ ঢোকা কতবার আবার চেষ্টা', 'Failed intake কতবার retry', 'Failed intake: max tries', null, null, 629),
 ('intake_retry_min', 'pos', 'number', '5', 'মিনিট', null, 1, 1440, 'আবার চেষ্টার বিরতি (প্রতিবার এর গুণ)', 'Retry-র বিরতি (প্রতিবার এর গুণ)', 'Retry delay (times the try number)', null, null, 630)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('web_form_public_url', 'pos', 'text', '""', null, null, null, null, 'ওয়েব ফর্মের পাবলিক ঠিকানা (Edge ফাংশনের URL)', 'Web form public URL (Edge function)', 'Web form public URL (Edge function)',
  'ফাংশন চালু হওয়ার পরে এখানে বসান; এর আগে শেয়ার-লিংক তৈরি হয় না।', 'Fill after the function is deployed; no share link is made before.', 631)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'inbox_contact_view', 'pos', 95, 'গ্রাহকের ফোন/ঠিকানা দেখা (ইনবক্স/অনলাইন অর্ডার)', 'Customer ফোন/ঠিকানা দেখা (inbox / online order)', 'See customer phone / address (inbox / online orders)', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'inbox_contact_view');

-- =====================================================================
-- H1 channels
-- =====================================================================
create table if not exists public.sales_channels (
  id int generated always as identity primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,30}$'),
  kind text not null check (kind in ('web_form', 'facebook', 'instagram', 'whatsapp', 'phone', 'walkin', 'other')),
  other_text text check (other_text is null or char_length(other_text) <= 60),
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 60),
  location_id int references public.locations(id),
  role_code text,
  account_ref text check (account_ref is null or char_length(account_ref) <= 120),     -- Meta page id / phone number id / form id: not shown to staff
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (kind <> 'other' or other_text is not null)
);
create unique index if not exists sales_channels_ref on public.sales_channels (kind, account_ref) where account_ref is not null;

create table if not exists public.intake_bots (
  user_id uuid primary key references public.profiles(id), active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table public.online_orders add column if not exists channel_id int references public.sales_channels(id);
alter table public.online_orders add column if not exists external_ref text check (external_ref is null or char_length(external_ref) <= 120);
alter table public.online_orders add column if not exists source text check (source is null or char_length(source) <= 80);
alter table public.online_orders add column if not exists pay_mode text check (pay_mode is null or pay_mode in ('cod', 'cash', 'mobile', 'card', 'bank', 'other'));
alter table public.online_orders add column if not exists pay_mode_other text check (pay_mode_other is null or char_length(pay_mode_other) <= 60);
alter table public.online_orders add column if not exists pay_ref text check (pay_ref is null or char_length(pay_ref) <= 80);
alter table public.online_orders add column if not exists is_draft boolean not null default false;
alter table public.online_orders add column if not exists draft_note text check (draft_note is null or char_length(draft_note) <= 300);
alter table public.online_orders add column if not exists draft_verified_by uuid;
alter table public.online_orders add column if not exists draft_verified_at timestamptz;
create unique index if not exists online_orders_ext on public.online_orders (channel_id, external_ref) where channel_id is not null and external_ref is not null;

-- =====================================================================
-- H2 inbox
-- =====================================================================
create table if not exists public.inbound_messages (
  id bigint generated always as identity primary key,
  channel_id int not null references public.sales_channels(id), location_id int not null references public.locations(id),
  external_id text not null check (char_length(external_id) between 1 and 200),
  customer_handle text check (customer_handle is null or char_length(customer_handle) <= 120),
  customer_name text check (customer_name is null or char_length(customer_name) <= 120),
  msg_text text check (msg_text is null or char_length(msg_text) <= 4000),
  msg_time timestamptz, received_at timestamptz not null default now(),
  attachment_ref text check (attachment_ref is null or char_length(attachment_ref) <= 500),
  status text not null default 'new' check (status in ('new', 'seen', 'converted', 'ignored')),
  linked_order_id uuid references public.online_orders(id), draft_order_id uuid references public.online_orders(id),
  seen_by uuid, seen_at timestamptz, ignore_note text,
  unique (channel_id, external_id)
);
create index if not exists inbound_messages_board on public.inbound_messages (location_id, status, received_at desc);
alter table public.online_orders add column if not exists inbox_msg_id bigint references public.inbound_messages(id);

create table if not exists public.inbound_message_events (
  id bigint generated always as identity primary key, msg_id bigint not null references public.inbound_messages(id),
  from_status text, to_status text not null, note text, by_user uuid, at timestamptz not null default now()
);

create table if not exists public.intake_failures (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('message', 'web_order', 'bad_signature')),
  channel_id int, external_id text, error text, payload jsonb,
  attempts int not null default 0, next_try_at timestamptz, last_try_at timestamptz,
  state text not null default 'failed' check (state in ('failed', 'done', 'dead', 'rejected')),
  created_at timestamptz not null default now(), done_at timestamptz, note text
);
create index if not exists intake_failures_due on public.intake_failures (state, next_try_at);

create table if not exists public.intake_hits (
  id bigint generated always as identity primary key, channel_id int not null, key_hash text not null, at timestamptz not null default now()
);
create index if not exists intake_hits_k on public.intake_hits (channel_id, key_hash, at desc);

create table if not exists public.order_dup_flags (
  id bigint generated always as identity primary key,
  order_a uuid not null references public.online_orders(id), order_b uuid not null references public.online_orders(id),
  location_id int not null, day date not null, items jsonb not null,
  state text not null default 'open' check (state in ('open', 'reviewed')), review_note text, reviewed_by uuid, reviewed_at timestamptz,
  created_at timestamptz not null default now(), unique (order_a, order_b), check (order_a < order_b)
);

-- trails / read-only guards
create or replace function public._inb_ro76() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'inbound_message_events' then raise exception 'append_only: the message trail cannot be changed or deleted'; end if;
  if tg_table_name = 'order_dup_flags' then
    if tg_op = 'DELETE' then raise exception 'append_only: a flag is reviewed, never deleted'; end if;
    if (to_jsonb(new) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') <> (to_jsonb(old) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') then raise exception 'append_only: only the review can change'; end if;
    return new;
  end if;
  if tg_table_name = 'inbound_messages' then
    if tg_op = 'DELETE' then raise exception 'append_only: a message is never deleted'; end if;
    if new.external_id <> old.external_id or new.channel_id <> old.channel_id or new.msg_text is distinct from old.msg_text or new.customer_handle is distinct from old.customer_handle
       or new.received_at <> old.received_at then raise exception 'append_only: the received message cannot be changed'; end if;
    if old.status = 'converted' and new.status <> 'converted' then raise exception 'order_closed: a converted message stays converted'; end if;
    return new;
  end if;
  if tg_table_name = 'sales_channels' and tg_op = 'DELETE' then raise exception 'append_only: a channel is switched off, never deleted'; end if;
  return new;
end $$;
drop trigger if exists inbound_message_events_ro76 on public.inbound_message_events;
create trigger inbound_message_events_ro76 before update or delete on public.inbound_message_events for each row execute function public._inb_ro76();
drop trigger if exists order_dup_flags_ro76 on public.order_dup_flags;
create trigger order_dup_flags_ro76 before update or delete on public.order_dup_flags for each row execute function public._inb_ro76();
drop trigger if exists inbound_messages_ro76 on public.inbound_messages;
create trigger inbound_messages_ro76 before update or delete on public.inbound_messages for each row execute function public._inb_ro76();
drop trigger if exists sales_channels_ro76 on public.sales_channels;
create trigger sales_channels_ro76 before delete on public.sales_channels for each row execute function public._inb_ro76();

-- audit (no message text / handle / payload is copied into the audit log)
create or replace function public._inb_audit76() returns trigger language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  if tg_table_name = 'inbound_messages' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, lower(tg_op), tg_table_name, new.id::text, jsonb_build_object('channel_id', new.channel_id, 'external_id', new.external_id, 'status', new.status, 'linked_order_id', new.linked_order_id));
  elsif tg_table_name = 'intake_failures' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, lower(tg_op), tg_table_name, new.id::text, jsonb_build_object('kind', new.kind, 'state', new.state, 'attempts', new.attempts, 'error', left(new.error, 200)));
  end if;
  return new;
end $$;
drop trigger if exists audit_inbound_messages on public.inbound_messages;
create trigger audit_inbound_messages after insert or update on public.inbound_messages for each row execute function public._inb_audit76();
drop trigger if exists audit_intake_failures on public.intake_failures;
create trigger audit_intake_failures after insert or update on public.intake_failures for each row execute function public._inb_audit76();
drop trigger if exists audit_sales_channels on public.sales_channels;
create trigger audit_sales_channels after insert or update on public.sales_channels for each row execute function public.log_change('id');
drop trigger if exists audit_intake_bots on public.intake_bots;
create trigger audit_intake_bots after insert or update on public.intake_bots for each row execute function public.log_change('user_id');
drop trigger if exists audit_order_dup_flags on public.order_dup_flags;
create trigger audit_order_dup_flags after insert or update on public.order_dup_flags for each row execute function public.log_change('id');

-- a draft can never be confirmed / packed / delivered (nor linked to a sale) until a person verified it
create or replace function public._oo_draft_guard76() returns trigger language plpgsql set search_path = public as $$
begin
  if old.is_draft and new.is_draft and new.status is distinct from old.status and new.status in ('confirmed', 'packed', 'delivered') then
    raise exception 'draft_unverified: this order is a draft; a person must check and verify it first';
  end if;
  return new;
end $$;
drop trigger if exists online_orders_draft76 on public.online_orders;
create trigger online_orders_draft76 before update on public.online_orders for each row execute function public._oo_draft_guard76();

-- H6 duplicate flag: same customer (mobile) + same item + same day, from DIFFERENT channels => flag only
create or replace function public._oo_dup76() returns trigger language plpgsql security definer set search_path = public as $$
declare b public.online_orders; common jsonb; a_ uuid; b_ uuid;
begin
  if new.status = 'cancelled' then return new; end if;
  for b in select o.* from public.online_orders o
            where o.id <> new.id and o.customer_mobile = new.customer_mobile and o.status <> 'cancelled'
              and (o.created_at at time zone 'Asia/Dhaka')::date = (new.created_at at time zone 'Asia/Dhaka')::date
              and (o.channel is distinct from new.channel or o.channel_id is distinct from new.channel_id) loop
    select coalesce(jsonb_agg(distinct x->>'item_id'), '[]'::jsonb) into common
      from jsonb_array_elements(new.lines) x where (x->>'item_id') in (select y->>'item_id' from jsonb_array_elements(b.lines) y);
    if jsonb_array_length(common) > 0 then
      if new.id < b.id then a_ := new.id; b_ := b.id; else a_ := b.id; b_ := new.id; end if;
      insert into public.order_dup_flags (order_a, order_b, location_id, day, items) values (a_, b_, new.location_id, (new.created_at at time zone 'Asia/Dhaka')::date, common)
        on conflict (order_a, order_b) do nothing;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists online_orders_dup76 on public.online_orders;
create trigger online_orders_dup76 after insert or update of lines, customer_mobile on public.online_orders for each row execute function public._oo_dup76();

-- =====================================================================
-- helpers
-- =====================================================================
create or replace function public._inb_is_bot() returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists (select 1 from public.intake_bots b where b.user_id = auth.uid() and b.active);
$$;

create or replace function public.intake_bot_set(p_user uuid, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_active is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then raise exception 'owner_cannot_be_bot'; end if;
  insert into public.intake_bots (user_id, active, created_by) values (p_user, p_active, auth.uid())
    on conflict (user_id) do update set active = excluded.active, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'active', p_active);
end $$;

create or replace function public._inb_gate(p_loc int, p_action text default 'view') returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', p_action) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
end $$;

-- may this person see the customer phone / address of this place?
create or replace function public._inb_contact_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not public.rule_on('inbox_pii_guard_on') then public.can_do('POS', 'view') and public.can_loc(p_loc)
              else public.is_owner() or (public.can_loc(p_loc) and public.has_grant('inbox_contact_view', p_loc)) end;
$$;

create or replace function public._inb_audit_view(p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'view', p_table, p_id, p_detail);
end $$;

create or replace function public._inb_kind_text(p_kind text) returns text language sql immutable as $$
  select case p_kind when 'web_form' then 'website' when 'facebook' then 'facebook' when 'instagram' then 'instagram' when 'whatsapp' then 'whatsapp' when 'phone' then 'phone' else 'other' end;
$$;

-- pure-SQL HMAC-SHA256 (no extension needed); used by inbound_sig_verify and the tests (RFC 4231 vectors)
create or replace function public._inb_hmac_sha256(p_key bytea, p_msg bytea) returns text
language plpgsql immutable set search_path = public as $$
declare k bytea := p_key; ip bytea; op bytea; i int;
begin
  if length(k) > 64 then k := sha256(k); end if;
  k := k || decode(repeat('00', 64 - length(k)), 'hex');
  ip := k; op := k;
  for i in 0..63 loop ip := set_byte(ip, i, get_byte(k, i) # 54); op := set_byte(op, i, get_byte(k, i) # 92); end loop;
  return encode(sha256(op || sha256(ip || p_msg)), 'hex');
end $$;

-- Meta style header "sha256=<hex>" over the RAW body. The default place for this check is the Edge function (the secret stays there);
-- this SQL copy exists so the rule is testable and usable as a fallback. Never log the secret argument.
create or replace function public.inbound_sig_verify(p_secret text, p_raw_body text, p_header text) returns boolean
language plpgsql immutable set search_path = public as $$
declare exp text; got text; diff int := 0; i int;
begin
  if p_secret is null or p_secret = '' or p_raw_body is null or p_header is null or p_header !~ '^sha256=[0-9a-fA-F]{64}$' then return false; end if;
  exp := public._inb_hmac_sha256(convert_to(p_secret, 'UTF8'), convert_to(p_raw_body, 'UTF8'));
  got := lower(substr(p_header, 8));
  for i in 1..64 loop diff := diff | (ascii(substr(exp, i, 1)) # ascii(substr(got, i, 1))); end loop;
  return diff = 0;
end $$;

create or replace function public._intake_fail(p_kind text, p_channel int, p_ext text, p_err text, p_payload jsonb, p_state text default 'failed') returns bigint
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  insert into public.intake_failures (kind, channel_id, external_id, error, payload, state, next_try_at)
    values (p_kind, p_channel, left(p_ext, 200), left(p_err, 500), p_payload, p_state,
            case when p_state = 'failed' then now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int)) end)
    returning id into id_;
  return id_;
end $$;

-- =====================================================================
-- H1 channel functions
-- =====================================================================
create or replace function public.sales_channel_save(p_id int, p_code text, p_kind text, p_other text, p_name text, p_loc int, p_role text, p_account_ref text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.sales_channels;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_kind not in ('web_form', 'facebook', 'instagram', 'whatsapp', 'phone', 'walkin', 'other') then raise exception 'bad_kind'; end if;
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
end $$;

create or replace function public.sales_channels_list(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'kind', c.kind, 'other_text', c.other_text, 'name_bn', c.name_bn, 'location_id', c.location_id, 'role_code', c.role_code,
            'active', c.active, 'account_ref', case when o then c.account_ref end) order by c.id)
     from public.sales_channels c where (c.active or (p_all and o)) and (o or c.location_id is null or public.can_loc(c.location_id))), '[]'::jsonb);
end $$;

-- =====================================================================
-- H2 / H4 receive (called by the Edge function logged in as the intake bot)
-- =====================================================================
create or replace function public._inb_insert_message(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; m public.inbound_messages; n int;
begin
  select * into ch from public.sales_channels where kind = p->>'kind' and account_ref = p->>'account_ref' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  insert into public.inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, msg_time, attachment_ref)
    values (ch.id, ch.location_id, p->>'external_id', left(p->>'handle', 120), left(p->>'name', 120), left(p->>'text', 4000),
            nullif(p->>'msg_time', '')::timestamptz, left(p->>'attachment', 500))
    on conflict (channel_id, external_id) do nothing returning * into m;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, null, 'new', 'received', auth.uid());
  return jsonb_build_object('duplicate', false, 'id', m.id);
end $$;

create or replace function public.inbound_message_receive(p_kind text, p_account_ref text, p_external_id text, p_handle text, p_name text, p_text text,
                                                          p_msg_time timestamptz, p_attachment text, p_signature_ok boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl jsonb; res jsonb; fid bigint; ch int;
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('inbox_on') then return jsonb_build_object('off', true); end if;
  if p_kind in ('facebook', 'instagram', 'whatsapp') and not public.rule_on('meta_intake_on') then return jsonb_build_object('off', true); end if;
  if p_kind not in ('facebook', 'instagram', 'whatsapp', 'web_form', 'other') or p_signature_ok is null or p_external_id is null or char_length(p_external_id) not between 1 and 200
     or char_length(coalesce(p_account_ref, '')) > 120 or char_length(coalesce(p_text, '')) > 20000 then raise exception 'bad_input'; end if;
  if not p_signature_ok then
    -- a wrong signature is never stored as a message; only the fact (no body) goes to the failed list for the owner to see
    fid := public._intake_fail('bad_signature', null, p_external_id, 'bad_signature', jsonb_build_object('kind', p_kind), 'rejected');
    return jsonb_build_object('rejected', 'bad_signature', 'failure_id', fid);
  end if;
  pl := jsonb_build_object('kind', p_kind, 'account_ref', p_account_ref, 'external_id', p_external_id, 'handle', p_handle, 'name', p_name, 'text', p_text,
                           'msg_time', p_msg_time, 'attachment', p_attachment);
  select id into ch from public.sales_channels where kind = p_kind and account_ref = p_account_ref;
  begin
    res := public._inb_insert_message(pl);
  exception when others then
    fid := public._intake_fail('message', ch, p_external_id, sqlerrm, pl);
    return jsonb_build_object('failed', true, 'queued', true, 'failure_id', fid);
  end;
  return res;
end $$;

create or replace function public.inbox_list(p_loc int default null, p_status text default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; unmasked boolean := false; l int[];
begin
  perform public._inb_gate(p_loc, 'view');
  if p_status is not null and p_status not in ('new', 'seen', 'converted', 'ignored') then raise exception 'bad_input'; end if;
  select coalesce(array_agg(x.id), '{}') into l from public.locations x where public.can_loc(x.id) and (p_loc is null or x.id = p_loc);
  select coalesce(jsonb_agg(z.j order by z.rid desc), '[]'::jsonb) into r from (
    select m.id rid, jsonb_build_object('id', m.id, 'channel_id', m.channel_id, 'channel', c.name_bn, 'kind', c.kind, 'location_id', m.location_id, 'status', m.status, 'received_at', m.received_at, 'msg_time', m.msg_time,
      'linked_order_id', m.linked_order_id, 'draft_order_id', m.draft_order_id, 'has_attachment', m.attachment_ref is not null,
      'handle', case when public._inb_contact_ok(m.location_id) then m.customer_handle end, 'name', case when public._inb_contact_ok(m.location_id) then m.customer_name end,
      'text', case when public._inb_contact_ok(m.location_id) then left(m.msg_text, 200) end, 'masked', not public._inb_contact_ok(m.location_id)) j
      from public.inbound_messages m join public.sales_channels c on c.id = m.channel_id
     where m.location_id = any (l) and (p_status is null or m.status = p_status)
     order by m.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then
    perform public._inb_audit_view('inbound_messages', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.inbox_get(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
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
    'handle', case when ok then m.customer_handle end, 'name', case when ok then m.customer_name end, 'text', case when ok then m.msg_text end, 'attachment_ref', case when ok then m.attachment_ref end,
    'events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'at', e.at) order by e.id) from public.inbound_message_events e where e.msg_id = m.id), '[]'::jsonb));
end $$;

create or replace function public.inbox_set_status(p_id bigint, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.inbound_messages;
begin
  select * into m from public.inbound_messages where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._inb_gate(m.location_id, 'enter');
  if p_to not in ('new', 'seen', 'ignored') then raise exception 'bad_status'; end if;
  if m.status = p_to then return jsonb_build_object('id', m.id, 'status', m.status, 'noop', true); end if;
  if m.status = 'converted' then raise exception 'order_closed: a converted message stays converted'; end if;
  if p_to = 'new' and m.status <> 'ignored' then raise exception 'bad_status'; end if;
  if p_to = 'ignored' and nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.inbound_messages set status = p_to, seen_by = case when p_to = 'seen' then auth.uid() else seen_by end, seen_at = case when p_to = 'seen' then now() else seen_at end,
      ignore_note = case when p_to = 'ignored' then left(btrim(p_note), 300) else ignore_note end where id = m.id;
  insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, m.status, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid());
  return jsonb_build_object('id', m.id, 'status', p_to);
end $$;

-- board numbers: new messages, last message time, silence warning, failed list size, open duplicate flags, drafts
create or replace function public.inbox_board(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
        from public.sales_channels c where c.active and c.kind in ('facebook', 'instagram', 'whatsapp') and (c.location_id is null or c.location_id = any (l))), '[]'::jsonb));
end $$;

-- =====================================================================
-- order save with channel columns (wraps the EXISTING online_order_save), draft support, inbox link
-- =====================================================================
create or replace function public.online_order_save2(p_id uuid, p_client uuid, p_loc int, p_channel_id int, p_name text, p_mobile text, p_address text, p_lines jsonb,
  p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text,
  p_external_ref text default null, p_source text default null, p_pay_mode text default null, p_pay_mode_other text default null, p_pay_ref text default null,
  p_msg_id bigint default null, p_draft boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; m public.inbound_messages; res jsonb; oid uuid; o public.online_orders; ext text := nullif(btrim(p_external_ref), '');
begin
  if p_channel_id is null then raise exception 'channel_required'; end if;
  if p_id is null and p_client is not null then          -- a retry of an already saved order returns it before anything else is checked
    select * into o from public.online_orders where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'dup', true); end if;
  end if;
  select * into ch from public.sales_channels where id = p_channel_id;
  if not found or not ch.active then raise exception 'channel_not_found'; end if;
  if p_id is not null then select * into o from public.online_orders where id = p_id; if not found then raise exception 'not_found'; end if; end if;
  if ch.location_id is not null and ch.location_id <> coalesce(o.location_id, p_loc) then raise exception 'channel_other_location'; end if;
  if p_pay_mode is not null and p_pay_mode not in ('cod', 'cash', 'mobile', 'card', 'bank', 'other') then raise exception 'bad_pay_mode'; end if;
  if p_pay_mode = 'other' and nullif(btrim(p_pay_mode_other), '') is null then raise exception 'pay_mode_other_required'; end if;
  if coalesce(p_draft, false) then
    if not public.rule_on('inbox_autodraft_on') then raise exception 'module_off: drafts are off'; end if;
    if p_id is not null and not o.is_draft then raise exception 'not_a_draft'; end if;
  elsif p_id is not null and o.is_draft then
    null;   -- editing a draft keeps it a draft until verified
  end if;
  if p_msg_id is not null then
    select * into m from public.inbound_messages where id = p_msg_id for update;
    if not found or m.channel_id <> p_channel_id then raise exception 'message_not_found'; end if;
    perform public._inb_gate(m.location_id, 'enter');
    if m.status in ('converted', 'ignored') then raise exception 'message_closed: this message is already converted or ignored'; end if;
    if m.draft_order_id is not null and p_id is distinct from m.draft_order_id and not coalesce(p_draft, false) then raise exception 'message_has_draft: verify the draft instead'; end if;
    ext := coalesce(ext, m.external_id);
  end if;
  res := public.online_order_save(p_id, p_client, p_loc, public._inb_kind_text(ch.kind), p_name, p_mobile, p_address, p_lines, p_delivery_mode, p_delivery_by, p_delivery_date,
                                  p_charge, p_discount, p_advance, p_adv_mode, p_adv_wallet, p_note);
  if coalesce((res->>'dup')::boolean, false) then return res; end if;
  oid := (res->>'id')::uuid;
  update public.online_orders set channel_id = ch.id, external_ref = ext, source = left(nullif(btrim(p_source), ''), 80), pay_mode = p_pay_mode,
      pay_mode_other = case when p_pay_mode = 'other' then left(btrim(p_pay_mode_other), 60) end, pay_ref = left(nullif(btrim(p_pay_ref), ''), 80),
      inbox_msg_id = coalesce(p_msg_id, inbox_msg_id), is_draft = case when p_id is null then coalesce(p_draft, false) else is_draft end,
      draft_note = case when p_id is null and coalesce(p_draft, false) then 'খসড়া, যাচাই বাকি' else draft_note end
    where id = oid;
  if p_msg_id is not null and p_id is null then
    if coalesce(p_draft, false) then
      update public.inbound_messages set draft_order_id = oid where id = p_msg_id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (p_msg_id, m.status, m.status, 'draft order made (unverified)', auth.uid());
    else
      update public.inbound_messages set status = 'converted', linked_order_id = oid, seen_by = coalesce(seen_by, auth.uid()), seen_at = coalesce(seen_at, now()) where id = p_msg_id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (p_msg_id, m.status, 'converted', 'order made', auth.uid());
    end if;
  end if;
  return res || jsonb_build_object('draft', coalesce(p_draft, false) and p_id is null);
end $$;

create or replace function public.online_order_draft_verify(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; m public.inbound_messages;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'enter');
  if not o.is_draft then return jsonb_build_object('id', o.id, 'noop', true); end if;
  if o.status <> 'new' then raise exception 'order_closed'; end if;
  update public.online_orders set is_draft = false, draft_verified_by = auth.uid(), draft_verified_at = now(), draft_note = left(coalesce(nullif(btrim(p_note), ''), 'যাচাই হয়েছে'), 300), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'new', 'new', 'draft verified by a person' || coalesce(' | ' || nullif(btrim(p_note), ''), ''));
  if o.inbox_msg_id is not null then
    select * into m from public.inbound_messages where id = o.inbox_msg_id for update;
    if found and m.status not in ('converted') then
      update public.inbound_messages set status = 'converted', linked_order_id = o.id where id = m.id;
      insert into public.inbound_message_events (msg_id, from_status, to_status, note, by_user) values (m.id, m.status, 'converted', 'draft verified', auth.uid());
    end if;
  end if;
  return jsonb_build_object('id', o.id, 'verified', true);
end $$;

-- =====================================================================
-- H3 web / landing form
-- =====================================================================
create or replace function public._web_order_run(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; sub uuid := (p->>'submission')::uuid; ex public.online_orders; clean jsonb := '[]'; ln jsonb; it public.items; q numeric; res jsonb; n int := 0;
begin
  select * into ch from public.sales_channels where code = p->>'channel' and kind = 'web_form' and active;
  if not found then raise exception 'channel_not_found'; end if;
  if ch.location_id is null then raise exception 'channel_no_location'; end if;
  select * into ex from public.online_orders where channel_id = ch.id and external_ref = sub::text;
  if found then return jsonb_build_object('order_no', ex.order_no, 'status', ex.status, 'subtotal', ex.subtotal, 'dup', true); end if;
  if p->>'delivery_mode' not in ('pickup', 'home') then raise exception 'bad_delivery_mode'; end if;
  if jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') not between 1 and 100 then raise exception 'no_lines'; end if;
  for ln in select * from jsonb_array_elements(p->'lines') loop
    n := n + 1;
    begin q := (ln->>'qty')::numeric; exception when others then raise exception 'bad_qty'; end;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    begin select * into it from public.items where id = (ln->>'item_id')::uuid; exception when others then raise exception 'item_not_found'; end;
    -- only active, sellable, visible, priced items; the CLIENT PRICE (if any) is dropped here: only item_id + qty go on
    if not found or not it.is_active or not it.sellable or it.hidden or it.retired_at is not null or it.sell_price is null then raise exception 'item_unavailable'; end if;
    clean := clean || jsonb_build_object('item_id', it.id, 'qty', q);
  end loop;
  res := public.online_order_save2(null, sub, ch.location_id, ch.id, p->>'name', p->>'mobile', p->>'address', clean, p->>'delivery_mode', null, null, 0, 0, 0, null, null, p->>'note',
                                   sub::text, p->>'source', p->>'pay_mode', p->>'pay_mode_other', p->>'pay_ref', null, false);
  return jsonb_build_object('order_no', res->'order_no', 'status', res->'status', 'subtotal', res->'subtotal', 'dup', coalesce((res->>'dup')::boolean, false));
end $$;

create or replace function public.web_order_submit(p_channel text, p_submission uuid, p_name text, p_mobile text, p_address text, p_delivery_mode text, p_lines jsonb, p_note text,
  p_source text default null, p_pay_mode text default null, p_pay_ref text default null, p_key_hash text default null, p_captcha_ok boolean default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ch public.sales_channels; pl jsonb; res jsonb; fid bigint; mx int; win int; c int; k text := coalesce(p_key_hash, '');
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if p_submission is null then raise exception 'bad_input'; end if;
  select * into ch from public.sales_channels where code = p_channel and kind = 'web_form' and active;
  if not found then return jsonb_build_object('ok', false, 'error', 'channel_not_found'); end if;
  if public.rule_on('web_form_captcha_on') and p_captcha_ok is not true then return jsonb_build_object('ok', false, 'error', 'captcha_required'); end if;
  -- same submission twice must never count as spam: an existing order is just returned
  if exists (select 1 from public.online_orders where channel_id = ch.id and external_ref = p_submission::text) then
    return jsonb_build_object('ok', true) || public._web_order_run(jsonb_build_object('channel', p_channel, 'submission', p_submission));
  end if;
  mx := coalesce(public.rule_num('web_form_rate_max'), 0)::int; win := greatest(1, coalesce(public.rule_num('web_form_rate_window_min'), 60)::int);
  if mx > 0 then
    select count(*) into c from public.intake_hits where channel_id = ch.id and key_hash = k and at > now() - make_interval(mins => win);
    if c >= mx then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  end if;
  insert into public.intake_hits (channel_id, key_hash) values (ch.id, k);
  -- whitelist: only the necessary fields are kept
  pl := jsonb_build_object('channel', p_channel, 'submission', p_submission, 'name', left(btrim(p_name), 80), 'mobile', left(p_mobile, 30), 'address', left(p_address, 300),
          'delivery_mode', p_delivery_mode, 'lines', p_lines, 'note', left(p_note, 300), 'source', left(p_source, 80), 'pay_mode', p_pay_mode, 'pay_ref', left(p_pay_ref, 80));
  begin
    res := public._web_order_run(pl);
  exception when others then
    if sqlerrm ~ '^(bad_|item_|customer_name|address_required|no_lines|no_price|too_long|advance_|channel_not_found|pay_mode_other)' then
      return jsonb_build_object('ok', false, 'error', split_part(sqlerrm, ':', 1));
    end if;
    fid := public._intake_fail('web_order', ch.id, p_submission::text, sqlerrm, pl);
    return jsonb_build_object('ok', false, 'queued', true, 'failure_id', fid);
  end;
  return jsonb_build_object('ok', true) || res;
end $$;

-- the catalogue for the public form: ONLY active + sellable + visible + priced items; the price is for display, the server recomputes
create or replace function public.web_form_catalog(p_channel text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('web_form_on') then return jsonb_build_object('off', true); end if;
  if not exists (select 1 from public.sales_channels where code = p_channel and kind = 'web_form' and active) then return jsonb_build_object('ok', false, 'error', 'channel_not_found'); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name_bn', i.name_bn, 'name_en', i.name_en, 'unit', i.unit, 'price', i.sell_price) order by i.name_bn)
     from public.items i where i.is_active and i.sellable and not i.hidden and i.retired_at is null and i.sell_price is not null), '[]'::jsonb));
end $$;

-- share link / embed code for the owner's phone (the public URL is a setting; nothing is made up before the function exists)
create or replace function public.web_form_embed(p_channel text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u text := nullif(btrim(coalesce(public.rule_val('web_form_public_url') #>> '{}', '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sales_channels where code = p_channel and kind = 'web_form') then raise exception 'channel_not_found'; end if;
  if u is null then return jsonb_build_object('configured', false); end if;
  return jsonb_build_object('configured', true, 'link', rtrim(u, '/') || '?c=' || p_channel,
    'embed', '<iframe src="' || rtrim(u, '/') || '?c=' || p_channel || '" style="width:100%;max-width:480px;height:720px;border:0" loading="lazy"></iframe>');
end $$;

-- =====================================================================
-- H6 failed list + retry; dup flags
-- =====================================================================
create or replace function public.intake_failures_list(p_state text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select f.id, f.kind, f.channel_id, f.external_id, f.error, f.attempts, f.next_try_at, f.last_try_at, f.state, f.created_at, f.done_at
      from public.intake_failures f where p_state is null or f.state = p_state order by f.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.intake_retry_due(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.intake_failures; mt int := greatest(1, coalesce(public.rule_num('intake_max_tries'), 5)::int); ok int := 0; bad int := 0; dead int := 0; res jsonb; err text;
begin
  if not (public._inb_is_bot() or public.is_owner()) then raise exception 'not allowed'; end if;
  for f in select * from public.intake_failures where state = 'failed' and next_try_at <= now() order by id limit least(greatest(coalesce(p_limit, 20), 1), 200) for update skip locked loop
    begin
      if f.kind = 'message' then res := public._inb_insert_message(f.payload);
      elsif f.kind = 'web_order' then res := public._web_order_run(f.payload);
      else raise exception 'not_retryable'; end if;
      update public.intake_failures set state = 'done', attempts = attempts + 1, last_try_at = now(), done_at = now(), error = null where id = f.id;
      ok := ok + 1;
    exception when others then
      err := sqlerrm;
      update public.intake_failures set attempts = attempts + 1, last_try_at = now(), error = left(err, 500),
          state = case when attempts + 1 >= mt then 'dead' else 'failed' end,
          next_try_at = now() + make_interval(mins => greatest(1, coalesce(public.rule_num('intake_retry_min'), 5)::int) * (attempts + 1)) where id = f.id;
      if f.attempts + 1 >= mt then dead := dead + 1; else bad := bad + 1; end if;
    end;
  end loop;
  return jsonb_build_object('done', ok, 'failed_again', bad, 'dead', dead);
end $$;

create or replace function public.intake_failure_dismiss(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.intake_failures set state = 'dead', note = left(btrim(p_note), 300), payload = null where id = p_id and state in ('failed', 'rejected');
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'state', 'dead');
end $$;

create or replace function public.order_dup_flags_list(p_loc int default null, p_state text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'order_a', d.order_a, 'order_b', d.order_b, 'order_no_a', a.order_no, 'order_no_b', b.order_no, 'channel_a', a.channel, 'channel_b', b.channel,
        'day', d.day, 'items', d.items, 'state', d.state, 'location_id', d.location_id) order by d.id desc)
     from public.order_dup_flags d join public.online_orders a on a.id = d.order_a join public.online_orders b on b.id = d.order_b
     where public.can_loc(d.location_id) and (p_loc is null or d.location_id = p_loc) and (p_state is null or d.state = p_state)), '[]'::jsonb);
end $$;

create or replace function public.order_dup_flag_review(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.order_dup_flags;
begin
  select * into d from public.order_dup_flags where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_active() or not public.can_do('POS', 'approve') or not public.can_loc(d.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.order_dup_flags set state = 'reviewed', review_note = left(btrim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'state', 'reviewed');
end $$;

-- =====================================================================
-- re-created: online_orders_list / online_order_get (latest = phase61) + bos76 mask and view audit
-- =====================================================================
create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name,
           case when public._inb_contact_ok(o.location_id) then o.customer_mobile end as customer_mobile,   -- bos76
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked                           -- bos76
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['sales_channels', 'intake_bots', 'inbound_messages', 'inbound_message_events', 'intake_failures', 'intake_hits', 'order_dup_flags'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
grant select (id, code, kind, other_text, name_bn, location_id, role_code, active, created_at, updated_at) on public.sales_channels to authenticated;
grant select (id, channel_id, location_id, external_id, msg_time, received_at, status, linked_order_id, draft_order_id, seen_by, seen_at) on public.inbound_messages to authenticated;   -- text / handle / name / attachment: only via inbox_get (audited)
grant select on public.inbound_message_events, public.order_dup_flags to authenticated;
grant select (channel_id, external_ref, source, pay_mode, pay_mode_other, pay_ref, is_draft, draft_note, draft_verified_by, draft_verified_at, inbox_msg_id) on public.online_orders to authenticated;
create policy sales_channels_sel on public.sales_channels for select to authenticated using (public.is_active());
create policy inbound_messages_sel on public.inbound_messages for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
create policy inbound_message_events_sel on public.inbound_message_events for select to authenticated
  using (exists (select 1 from public.inbound_messages m where m.id = msg_id and public.can_do('POS', 'view') and public.can_loc(m.location_id)));
create policy order_dup_flags_sel on public.order_dup_flags for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
revoke usage, select on sequence public.sales_channels_id_seq, public.inbound_messages_id_seq, public.inbound_message_events_id_seq, public.intake_failures_id_seq, public.intake_hits_id_seq, public.order_dup_flags_id_seq from public, anon, authenticated;

-- phone / address column hide follows the switch (direct table reads); the functions above are the way to read them with the mask + audit
create or replace function public._inb_pii_cols76() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.key = 'inbox_pii_guard_on' then
    if coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false) then
      revoke select (customer_mobile, address) on public.online_orders from authenticated;
    else
      grant select (customer_mobile, address) on public.online_orders to authenticated;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists rules_pii76 on public.rules;
create trigger rules_pii76 after insert or update on public.rules for each row execute function public._inb_pii_cols76();

revoke all on function public.intake_bot_set(uuid, boolean), public.sales_channel_save(int, text, text, text, text, int, text, text, boolean), public.sales_channels_list(boolean),
  public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean), public.inbox_list(int, text, int), public.inbox_get(bigint), public.inbox_set_status(bigint, text, text),
  public.inbox_board(int), public.online_order_save2(uuid, uuid, int, int, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text, text, text, text, text, text, bigint, boolean),
  public.online_order_draft_verify(uuid, text), public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean), public.web_form_catalog(text), public.web_form_embed(text),
  public.intake_failures_list(text, int), public.intake_retry_due(int), public.intake_failure_dismiss(bigint, text), public.order_dup_flags_list(int, text), public.order_dup_flag_review(bigint, text),
  public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.inbound_sig_verify(text, text, text) from public, anon;
grant execute on function public.intake_bot_set(uuid, boolean), public.sales_channel_save(int, text, text, text, text, int, text, text, boolean), public.sales_channels_list(boolean),
  public.inbound_message_receive(text, text, text, text, text, text, timestamptz, text, boolean), public.inbox_list(int, text, int), public.inbox_get(bigint), public.inbox_set_status(bigint, text, text),
  public.inbox_board(int), public.online_order_save2(uuid, uuid, int, int, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text, text, text, text, text, text, bigint, boolean),
  public.online_order_draft_verify(uuid, text), public.web_order_submit(text, uuid, text, text, text, text, jsonb, text, text, text, text, text, boolean), public.web_form_catalog(text), public.web_form_embed(text),
  public.intake_failures_list(text, int), public.intake_retry_due(int), public.intake_failure_dismiss(bigint, text), public.order_dup_flags_list(int, text), public.order_dup_flag_review(bigint, text),
  public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid), public.inbound_sig_verify(text, text, text) to authenticated;
revoke all on function public._inb_ro76(), public._inb_audit76(), public._oo_draft_guard76(), public._oo_dup76(), public._inb_is_bot(), public._inb_gate(int, text), public._inb_contact_ok(int),
  public._inb_audit_view(text, text, jsonb), public._inb_kind_text(text), public._inb_hmac_sha256(bytea, bytea), public._intake_fail(text, int, text, text, jsonb, text), public._inb_insert_message(jsonb),
  public._web_order_run(jsonb), public._inb_pii_cols76() from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ===================== phase77.sql =====================
-- ============================================================
-- Phase 77 (bos77) - Step E9: existing online-order gaps (audit a2-F6). Run AFTER phase76. Additive + idempotent (paste twice = no error).
--   1. PACK-TIME STOCK WARNING   online_order_status('packed') now ANSWERS with a "short" list when the stock of a tracked item is below the order qty.
--                                It never blocks. Switch online_pack_warn_on (OFF). online_order_stock_check(id) = the same check as a read-only preview.
--                                Soft reservation (switch online_pack_reserve_on, OFF): other PACKED, undelivered orders of the same place count as reserved
--                                in the warning. It is advisory only - the counter (POS) is not blocked; nothing is written for it.
--   2. KEEP THE ORDER'S PRICE    switch online_keep_order_price (OFF = today: list price at delivery, price_changed exception if it moved).
--                                ON: online_order_deliver sends override=true for a line whose order price differs from today's list price; record_sale2 then
--                                keeps the order price, applies its own approval rule (price_override grant when pos_override_manager is on) and records
--                                its yellow 'price_override' exception. A refused approval rolls the whole delivery back (order stays packed).
--   3. VOIDED SALE => FLAG        trigger on sales: when the sale of a delivered/linked order is voided, an `online_order_flags` row (kind sale_voided, open),
--                                an order trail line and a RED exception are written. The order status is NOT silently changed. Owner/POS approver reviews the flag.
--   4. PACKAGING ON RETURN       NOT changed - see the proposal in docs/briefs_p2p3/step_E9_REPORT.md.
-- Re-created functions (latest definitions, only bos77 lines changed): online_order_status, online_order_deliver (phase61), online_orders_list, online_order_get (phase76).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('online_pack_warn_on', 'pos', 'switch', 'false', null, null, null, null, 'প্যাক করার সময় স্টক কম হলে সতর্কতা', 'Pack করার সময় stock কম হলে warning', 'Warn at pack time when stock is short',
  'শুধু সতর্কতা; প্যাক আটকায় না।', 'Warning only; packing is never blocked.', 640),
 ('online_pack_reserve_on', 'pos', 'switch', 'false', null, null, null, null, 'প্যাক হওয়া অর্ডারের স্টক ধরে রাখা (নরম, শুধু সতর্কতায়)', 'Packed order-এর stock ধরে রাখা (soft, শুধু warning-এ)', 'Soft-reserve stock of packed orders (warnings only)',
  'চালু হলে অন্য প্যাক হওয়া অর্ডারের পরিমাণ সতর্কতার হিসাবে বাদ যায়। কাউন্টারের বিক্রি আটকায় না।', 'When on, quantities of other packed orders are deducted in the warning. The counter is not blocked.', 641),
 ('online_keep_order_price', 'pos', 'switch', 'false', null, null, null, null, 'ডেলিভারিতে অর্ডারের দাম ধরে রাখা', 'Delivery-তে order-এর দাম ধরে রাখা', 'Keep the order price at delivery',
  'বন্ধ = আজকের তালিকা দাম। চালু = অর্ডারে লেখা দাম; দাম বদলালে সাধারণ ওভাররাইড-অনুমতির নিয়ম লাগে ও হলুদ এক্সেপশন হয়।', 'Off = today''s list price. On = the price on the order; a different price needs the normal override approval and logs a yellow exception.', 642)
 on conflict (key) do nothing;

create table if not exists public.online_order_flags (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.online_orders(id), location_id int not null, sale_id uuid,
  kind text not null check (kind in ('sale_voided')), note text,
  state text not null default 'open' check (state in ('open', 'reviewed')), review_note text, reviewed_by uuid, reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists online_order_flags_one on public.online_order_flags (order_id, kind, sale_id);
create or replace function public._oo_flag_ro77() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a flag is reviewed, never deleted'; end if;
  if (to_jsonb(new) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') <> (to_jsonb(old) - 'state' - 'review_note' - 'reviewed_by' - 'reviewed_at') then raise exception 'append_only: only the review can change'; end if;
  return new;
end $$;
drop trigger if exists online_order_flags_ro77 on public.online_order_flags;
create trigger online_order_flags_ro77 before update or delete on public.online_order_flags for each row execute function public._oo_flag_ro77();
drop trigger if exists audit_online_order_flags on public.online_order_flags;
create trigger audit_online_order_flags after insert or update on public.online_order_flags for each row execute function public.log_change('id');

-- 3. the sale of an order was voided: no silent drift
create or replace function public._oo_salevoid77() returns trigger language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  for o in select * from public.online_orders where sale_id = new.id loop
    insert into public.online_order_flags (order_id, location_id, sale_id, kind, note)
      values (o.id, o.location_id, new.id, 'sale_voided', left('sale receipt ' || new.receipt || ' was voided: ' || coalesce(new.void_note, ''), 300)) on conflict do nothing;
    perform public._oo_event61(o.id, o.status, o.status, 'SALE VOIDED (receipt ' || new.receipt || ') - the order still says delivered; check it');
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, new.id, 'POS', o.location_id, new.sale_date, 'online_order_sale_voided', 'red', new.total,
        jsonb_build_object('bn', 'অনলাইন অর্ডার #' || o.order_no || ' এর বিক্রি (রসিদ ' || new.receipt || ') বাতিল হয়েছে — অর্ডার এখনো "ডেলিভারি হয়েছে" দেখাচ্ছে, যাচাই করুন',
                           'en', 'The sale of online order #' || o.order_no || ' (receipt ' || new.receipt || ') was voided - the order still says delivered; please check'));
  end loop;
  return new;
end $$;
drop trigger if exists sales_void_oo77 on public.sales;
create trigger sales_void_oo77 after update of status on public.sales for each row
  when (old.status is distinct from new.status and new.status = 'void') execute function public._oo_salevoid77();

create or replace function public.online_order_flags_list(p_loc int default null, p_state text default 'open') returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'order_id', f.order_id, 'order_no', o.order_no, 'kind', f.kind, 'note', f.note, 'state', f.state, 'sale_id', f.sale_id, 'location_id', f.location_id, 'at', f.created_at) order by f.id desc)
     from public.online_order_flags f join public.online_orders o on o.id = f.order_id
    where public.can_loc(f.location_id) and (p_loc is null or f.location_id = p_loc) and (p_state is null or f.state = p_state)), '[]'::jsonb);
end $$;

create or replace function public.online_order_flag_review(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.online_order_flags;
begin
  select * into f from public.online_order_flags where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_active() or not public.can_do('POS', 'approve') or not public.can_loc(f.location_id) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'reason_required'; end if;
  update public.online_order_flags set state = 'reviewed', review_note = left(btrim(p_note), 300), reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'state', 'reviewed');
end $$;

-- 1. stock short list for an order (tracked items only)
create or replace function public._oo_short77(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders; r record; res jsonb := '[]'::jsonb; rsv boolean := public.rule_on('online_pack_reserve_on'); have numeric; reserved numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then return res; end if;
  for r in select (l->>'item_id')::uuid as item_id, sum((l->>'qty')::numeric) as need from jsonb_array_elements(o.lines) l where nullif(l->>'item_id', '') is not null group by 1 loop
    if not exists (select 1 from public.items i where i.id = r.item_id and i.tracked) then continue; end if;
    select coalesce(b.qty, 0) into have from (select 1) z left join public.stock_balance b on b.item_id = r.item_id and b.location_id = o.location_id;
    reserved := 0;
    if rsv then
      select coalesce(sum((l2->>'qty')::numeric), 0) into reserved from public.online_orders o2, jsonb_array_elements(o2.lines) l2
       where o2.location_id = o.location_id and o2.status = 'packed' and o2.id <> o.id and l2->>'item_id' = r.item_id::text;
    end if;
    if r.need > have - reserved then
      res := res || jsonb_build_object('item_id', r.item_id, 'name', (select name_bn from public.items where id = r.item_id), 'need', r.need, 'have', have, 'reserved', reserved, 'short_by', r.need - (have - reserved));
    end if;
  end loop;
  return res;
end $$;

create or replace function public.online_order_stock_check(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'view');
  if not public.rule_on('online_pack_warn_on') then return jsonb_build_object('on', false, 'short', '[]'::jsonb); end if;
  return jsonb_build_object('on', true, 'reserve', public.rule_on('online_pack_reserve_on'), 'short', public._oo_short77(o.id));
end $$;

-- re-created (phase61 definition): bos77 = the warning at pack time. Never blocks.
create or replace function public.online_order_status(p_id uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sh jsonb := '[]'::jsonb; nt text := p_note;   -- bos77
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_to not in ('confirmed', 'packed') then raise exception 'bad_status'; end if;
  if o.status = p_to then return jsonb_build_object('id', o.id, 'status', o.status, 'noop', true); end if;
  if not ((o.status = 'new' and p_to = 'confirmed') or (o.status = 'confirmed' and p_to = 'packed')) then raise exception 'bad_status: % -> % is not allowed', o.status, p_to; end if;
  if p_to = 'packed' and public.rule_on('online_pack_warn_on') then                                      -- bos77
    sh := public._oo_short77(o.id);                                                                       -- bos77
    if jsonb_array_length(sh) > 0 then nt := left(coalesce(nullif(btrim(p_note), '') || ' | ', '') || 'STOCK SHORT: ' || (select string_agg(x->>'name' || ' need ' || (x->>'need') || ' have ' || (x->>'have'), ', ') from jsonb_array_elements(sh) x), 300); end if;   -- bos77
  end if;                                                                                                 -- bos77
  update public.online_orders set status = p_to, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, p_to, nt);
  return jsonb_build_object('id', o.id, 'status', p_to) || case when jsonb_array_length(sh) > 0 then jsonb_build_object('warn', true, 'short', sh) else '{}'::jsonb end;   -- bos77
end $$;

-- re-created (phase61 definition): bos77 = optional "keep the order price"
create or replace function public.online_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sl jsonb := '[]'; ln jsonb; pay jsonb := '[]'; res jsonb; sid uuid; cur numeric; nl jsonb; keep boolean := public.rule_on('online_keep_order_price');   -- bos77
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.sale_id is not null then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    select sell_price into cur from public.items where id = (ln->>'item_id')::uuid;                                                      -- bos77
    nl := jsonb_build_object('item_id', ln->>'item_id', 'qty', (ln->>'qty')::numeric, 'price', (ln->>'price')::numeric);
    if keep and cur is distinct from (ln->>'price')::numeric then nl := nl || jsonb_build_object('override', true); end if;   -- bos77
    sl := sl || nl;
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

create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE (now writes the view audit)
declare r jsonb;
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  r := coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name,
           case when public._inb_contact_ok(o.location_id) then o.customer_mobile end as customer_mobile,   -- bos76
           o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at,
           o.channel_id, o.is_draft, not public._inb_contact_ok(o.location_id) as masked,                          -- bos76
           (select count(*) from public.online_order_flags f where f.order_id = o.id and f.state = 'open') as flags_open   -- bos77
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'masked')::boolean is false) then   -- bos76
    perform public._inb_audit_view('online_orders', 'list', jsonb_build_object('count', jsonb_array_length(r), 'loc', p_loc, 'status', p_status));
  end if;
  return r;
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$   -- bos76: was STABLE
declare o public.online_orders; ok boolean; j jsonb;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  ok := public._inb_contact_ok(o.location_id);                                                                -- bos76
  if ok then perform public._inb_audit_view('online_orders', o.id::text, jsonb_build_object('fields', 'customer_mobile,address')); end if;   -- bos76
  j := to_jsonb(o) - 'sale_client';
  if not ok then j := (j - 'customer_mobile' - 'address') || jsonb_build_object('masked', true); end if;      -- bos76
  j := j || jsonb_build_object('flags', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'note', f.note, 'state', f.state, 'at', f.created_at) order by f.id) from public.online_order_flags f where f.order_id = o.id), '[]'::jsonb));   -- bos77
  return j || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;


-- =====================================================================
-- RLS + privileges
-- =====================================================================
alter table public.online_order_flags enable row level security;
revoke all on public.online_order_flags from public, anon, authenticated;
drop policy if exists online_order_flags_sel on public.online_order_flags;
grant select on public.online_order_flags to authenticated;
create policy online_order_flags_sel on public.online_order_flags for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
revoke usage, select on sequence public.online_order_flags_id_seq from public, anon, authenticated;
revoke all on function public.online_order_flags_list(int, text), public.online_order_flag_review(bigint, text), public.online_order_stock_check(uuid), public.online_order_status(uuid, text, text),
  public.online_order_deliver(uuid, jsonb), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid) from public, anon;
grant execute on function public.online_order_flags_list(int, text), public.online_order_flag_review(bigint, text), public.online_order_stock_check(uuid), public.online_order_status(uuid, text, text),
  public.online_order_deliver(uuid, jsonb), public.online_orders_list(int, text, date, date, int), public.online_order_get(uuid) to authenticated;
revoke all on function public._oo_flag_ro77(), public._oo_salevoid77(), public._oo_short77(uuid) from public, anon, authenticated;
notify pgrst, 'reload schema';

-- ===================== phase78.sql =====================
-- ============================================================
-- Phase 78 (bos78) - STEP C-2খ: where does showroom / admin cost belong (profit-and-cost attribution) + approval separation hint.
--   Needs phase8 ... phase71 + phase73 + phase74 + phase75 (phase72 is another branch and is NOT needed). Additive; paste-twice safe. Old phases are NOT edited.
--   1. location_cost_attribution : per place (and optionally per cost type) the owner chooses where the layer-3 cost SHARES of a cost bill (phase75 cost_bill_shares,
--                                  dest showroom / admin) are charged: showroom (that place's own P&L) | main_centre | unallocated. Effective-dated: a new choice applies from its month
--                                  (this month or later - an earlier month is never rewritten); the old row stays (active=false when replaced, previous values copied). Default = no row = unallocated.
--   2. cost_attrib_main          : which place is the 'main centre' (effective-dated, may be blank = the main centre stays a bucket that only the cost view shows).
--   3. cost_share_reassign       : APPEND-ONLY trail. A single share can be re-assigned to another showroom / the main centre / unallocated, MANDATORY reason, old + new destination,
--                                  never silent; a locked (closed) period is refused for non-owners, an owner override is flagged (row + yellow exception).
--   4. branch_cost_view(month, loc) : read-only list of every share and where it is charged (and why).
--   5. The numbers reach the branch P&L (l1_pnl, l3_shop_pnl) ONLY when rule cost_attrib_in_pl is ON (default OFF = today's output, byte for byte). ON adds SEPARATE ROWS
--      (row_type 'cost_share'); the existing rows and every other function that reads _p27_pl (owner sheet, break-even, partner profit) are untouched.
--   6. grant_separation_hint(user, grant): a NON-BLOCKING suggestion when the same person would hold both the entry and the approve right (recipes, cost bills / allocation rules).
--   Cost-right holders only (view); changing = owner or grant cost_attrib_manage. Every write has an audit row (client_id where it creates something). Nothing is seeded (blank start).
--   NOT built: switch cost_bill_creates_payment (a bill that also posts the payment / payable) - it touches cash, bank and the ledger; owner decision, see the report.
-- ============================================================

-- ---------- settings, grants ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_attrib_in_pl', 'stock', 'switch', 'false',
  'খরচের বিলের শোরুম/অ্যাডমিন অংশ শাখার লাভ-ক্ষতিতে আলাদা সারিতে দেখান', 'Cost bill-এর showroom/admin অংশ branch P&L-এ আলাদা সারিতে দেখান', 'Show the showroom / admin cost-bill shares as separate rows in the branch P&L',
  'Off (default) = the branch P&L is exactly as today. On = the shares, as attributed in the cost-attribution screen, are added as separate rows (existing rows never change).', 745)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('cost_attrib_manage', 'cost', 82, 'খরচ কোন শাখার — ঠিক ও বদল', 'Cost কোন শাখার — set ও change', 'Set and change which showroom a cost belongs to', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- helpers ----------
create or replace function public._c78_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public._recipe_cost_ok() and (public.is_owner() or public.has_grant('cost_attrib_manage'));
$$;
create or replace function public._c78_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- is the date inside the closed period? (the same test lock_check uses, but it only answers)
create or replace function public._c78_locked(p_date date) returns boolean language plpgsql stable security definer set search_path = public as $$
declare v text; d date;
begin
  if p_date is null then return false; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return false; end if;
  begin d := v::date; exception when others then return false; end;
  return p_date <= d;
end $$;
create or replace function public._c78_nodml() returns trigger language plpgsql as $$ begin raise exception 'nothing is deleted or rewritten – the trail is append-only'; end $$;

-- ---------- tables ----------
create table if not exists public.location_cost_attribution (
  id bigserial primary key,
  location_id int not null references public.locations(id),          -- the place where the share ARISES (the share's own place)
  cost_type text references public.cost_source_types(code),          -- null = every cost type of that place; a typed row beats the general one
  dest text not null check (dest in ('showroom', 'main_centre', 'unallocated')),
  effective_from date not null check (effective_from = date_trunc('month', effective_from)::date),
  active boolean not null default true,
  reason text check (reason is null or length(reason) <= 300),
  prev_id bigint, prev_dest text, prev_effective_from date,           -- the setting this one replaced (previous values kept)
  replaced_by bigint, retired_at timestamptz, retired_by uuid, retired_reason text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists lca_one_active on public.location_cost_attribution (location_id, coalesce(cost_type, ''), effective_from) where active;
create index if not exists lca_lookup on public.location_cost_attribution (location_id, effective_from) where active;

create table if not exists public.cost_attrib_main (
  id bigserial primary key,
  location_id int references public.locations(id),                   -- blank = no place stands for the main centre (its shares then show only in the cost view)
  effective_from date not null check (effective_from = date_trunc('month', effective_from)::date),
  active boolean not null default true,
  reason text check (reason is null or length(reason) <= 300),
  replaced_by bigint, retired_at timestamptz, retired_by uuid,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists cam_one_active on public.cost_attrib_main (effective_from) where active;

create table if not exists public.cost_share_reassign (
  id bigserial primary key,
  share_id bigint not null references public.cost_bill_shares(id),
  bill_id bigint not null references public.cost_source_bills(id),
  share_loc int not null references public.locations(id),
  cost_type text,
  period_month date not null,
  amount numeric not null,                                            -- snapshot of the share at that time
  from_kind text not null check (from_kind in ('location', 'main_centre', 'unallocated')),
  from_loc int references public.locations(id),
  to_kind text not null check (to_kind in ('location', 'main_centre', 'unallocated')),
  to_loc int references public.locations(id),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  locked_override boolean not null default false,                     -- the period was closed and the owner (or a rule) allowed it: flagged
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check ((to_kind = 'location') = (to_loc is not null))
);
create index if not exists csr78_share on public.cost_share_reassign (share_id, id desc);

create table if not exists public.grant_separation_pairs (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  entry_grant text not null references public.grant_defs(grant_code),
  approve_grant text not null references public.grant_defs(grant_code),
  label_bn text not null, label_en text not null
);
insert into public.grant_separation_pairs (code, entry_grant, approve_grant, label_bn, label_en) values
 ('recipe', 'recipe_manage', 'recipe_approve', 'রেসিপি লেখা ও অনুমোদন', 'Recipe entry and approval'),
 ('cost_rules', 'cost_bill_entry', 'cost_rule_approve', 'খরচের বিল / ভাগের নিয়ম লেখা ও অনুমোদন', 'Cost bill / allocation rule entry and approval')
on conflict (code) do nothing;

-- ---------- triggers (audit, nothing is deleted) / RLS ----------
create or replace function public._c78_lca_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire or replace instead'; end if;
  if new.location_id is distinct from old.location_id or new.cost_type is distinct from old.cost_type or new.dest is distinct from old.dest or new.effective_from is distinct from old.effective_from
     or new.reason is distinct from old.reason or new.prev_id is distinct from old.prev_id or new.prev_dest is distinct from old.prev_dest or new.client_id is distinct from old.client_id then
    raise exception 'a setting is never rewritten – add a new one from a later month';
  end if;
  return new;
end $$;
drop trigger if exists lca_guard on public.location_cost_attribution;
create trigger lca_guard before update or delete on public.location_cost_attribution for each row execute function public._c78_lca_guard();
create or replace function public._c78_cam_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted – retire or replace instead'; end if;
  if new.location_id is distinct from old.location_id or new.effective_from is distinct from old.effective_from or new.reason is distinct from old.reason or new.client_id is distinct from old.client_id then
    raise exception 'a setting is never rewritten – add a new one from a later month';
  end if;
  return new;
end $$;
drop trigger if exists cam_guard on public.cost_attrib_main;
create trigger cam_guard before update or delete on public.cost_attrib_main for each row execute function public._c78_cam_guard();
drop trigger if exists csr78_nodml on public.cost_share_reassign;
create trigger csr78_nodml before update or delete on public.cost_share_reassign for each row execute function public._c78_nodml();
drop trigger if exists gsp_nd on public.grant_separation_pairs;
create trigger gsp_nd before delete on public.grant_separation_pairs for each row execute function public._cs_no_delete();
drop trigger if exists audit_lca on public.location_cost_attribution; create trigger audit_lca after insert or update on public.location_cost_attribution for each row execute function public.log_change('id');
drop trigger if exists audit_cam on public.cost_attrib_main; create trigger audit_cam after insert or update on public.cost_attrib_main for each row execute function public.log_change('id');
drop trigger if exists audit_csr78 on public.cost_share_reassign; create trigger audit_csr78 after insert on public.cost_share_reassign for each row execute function public.log_change('id');

alter table public.location_cost_attribution enable row level security;
alter table public.cost_attrib_main enable row level security;
alter table public.cost_share_reassign enable row level security;
alter table public.grant_separation_pairs enable row level security;
drop policy if exists lca_read on public.location_cost_attribution; create policy lca_read on public.location_cost_attribution for select to authenticated using (public._cs_view() and (public._all_locs() or public.can_loc(location_id)));
drop policy if exists cam_read on public.cost_attrib_main; create policy cam_read on public.cost_attrib_main for select to authenticated using (public._cs_view());
drop policy if exists csr78_read on public.cost_share_reassign; create policy csr78_read on public.cost_share_reassign for select to authenticated using (public._cs_view() and (public._all_locs() or public.can_loc(share_loc)));
drop policy if exists gsp_read on public.grant_separation_pairs; create policy gsp_read on public.grant_separation_pairs for select to authenticated using (public.is_active());
revoke all on public.location_cost_attribution, public.cost_attrib_main, public.cost_share_reassign, public.grant_separation_pairs from anon, authenticated;
grant select on public.location_cost_attribution, public.cost_attrib_main, public.cost_share_reassign, public.grant_separation_pairs to authenticated;
revoke all on sequence public.location_cost_attribution_id_seq, public.cost_attrib_main_id_seq, public.cost_share_reassign_id_seq from anon, authenticated;

-- ---------- where does a share go? ----------
-- the main-centre place in force for a month (null = none chosen)
create or replace function public._c78_main_loc(p_month date) returns int language sql stable security definer set search_path = public as $$
  select location_id from public.cost_attrib_main where active and effective_from <= public._m1(p_month) order by effective_from desc, id desc limit 1;
$$;
-- (kind, place, how): a re-assignment beats the place's setting; a typed cost type beats the general row; nothing set = unallocated (today)
create or replace function public._c78_dest(p_share bigint, p_month date) returns table (dkind text, dloc int, via text)
language plpgsql stable security definer set search_path = public as $$
declare r public.cost_share_reassign; sh public.cost_bill_shares; a public.location_cost_attribution; ct text; m date := public._m1(p_month);
begin
  select * into r from public.cost_share_reassign where share_id = p_share order by id desc limit 1;
  if found then
    dkind := r.to_kind; dloc := case when r.to_kind = 'main_centre' then public._c78_main_loc(m) else r.to_loc end; via := 'reassigned'; return next; return;
  end if;
  select * into sh from public.cost_bill_shares where id = p_share;
  select s.cost_type into ct from public.cost_source_bills b join public.cost_sources s on s.id = b.source_id where b.id = sh.bill_id;
  select * into a from public.location_cost_attribution where active and location_id = sh.location_id and cost_type = ct and effective_from <= m order by effective_from desc, id desc limit 1;
  if not found then
    select * into a from public.location_cost_attribution where active and location_id = sh.location_id and cost_type is null and effective_from <= m order by effective_from desc, id desc limit 1;
  end if;
  if not found or a.dest = 'unallocated' then dkind := 'unallocated'; dloc := null; via := case when found then 'setting' else 'default' end;
  elsif a.dest = 'showroom' then dkind := 'location'; dloc := sh.location_id; via := 'setting';
  else dkind := 'main_centre'; dloc := public._c78_main_loc(m); via := 'setting';
  end if;
  return next;
end $$;

-- every layer-3 share (showroom / admin) with its attribution, month by month (a yearly fee is spread /12 like branch_overhead)
create or replace function public._c78_rows(p_from date, p_to date) returns table (mth date, share_id bigint, bill_id bigint, source_code text, cost_type text, type_bn text, type_en text,
  share_loc int, share_dest text, amount numeric, dkind text, dloc int, via text)
language sql stable security definer set search_path = public as $$
  select z.mth, z.share_id, z.bill_id, z.code, z.cost_type, z.tbn, z.ten, z.share_loc, z.share_dest, z.amt, d.dkind, d.dloc, d.via
    from (
      select (case when b.period_kind = 'month' then b.period_month else (b.period_month + make_interval(months => g))::date end) mth, sh.id share_id, b.id bill_id, s.code, s.cost_type,
             t.label_bn tbn, coalesce(t.label_en, t.label_bn) ten, sh.location_id share_loc, sh.dest share_dest, (case when b.period_kind = 'month' then sh.amount else sh.amount / 12 end) amt
        from public.cost_bill_shares sh join public.cost_source_bills b on b.id = sh.bill_id join public.cost_sources s on s.id = b.source_id join public.cost_source_types t on t.code = s.cost_type
        cross join lateral generate_series(0, case when b.period_kind = 'year' then 11 else 0 end) g
       where sh.active and sh.kind = 'share' and sh.dest in ('showroom', 'admin') and b.status = 'active') z
    cross join lateral public._c78_dest(z.share_id, z.mth) d
   where z.mth between public._m1(coalesce(p_from, date '2000-01-01')) and coalesce(p_to, date '2999-12-31');
$$;

-- ---------- the read-only report: each share and where it is charged ----------
create or replace function public.branch_cost_view(p_month date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(coalesce(p_month, public._c78_today())); rows_ jsonb; tot jsonb; allv boolean;
begin
  if not public._cs_view() then raise exception 'not allowed'; end if;
  allv := public._all_locs();
  if p_loc is not null and not (allv or public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('share_id', r.share_id, 'bill_id', r.bill_id, 'source', r.source_code, 'cost_type', r.cost_type, 'type_bn', r.type_bn, 'type_en', r.type_en,
      'share_location', r.share_loc, 'share_dest', r.share_dest, 'amount', round(r.amount, 2), 'dest_kind', r.dkind, 'dest_location', r.dloc, 'via', r.via,
      'reassigned', r.via = 'reassigned', 'reason', (select x.reason from public.cost_share_reassign x where x.share_id = r.share_id order by x.id desc limit 1),
      'locked_override', coalesce((select x.locked_override from public.cost_share_reassign x where x.share_id = r.share_id order by x.id desc limit 1), false)) order by r.share_loc, r.cost_type, r.share_id), '[]'::jsonb)
    into rows_ from public._c78_rows(m, m) r
   where (allv or public.can_loc(r.share_loc) or (r.dloc is not null and public.can_loc(r.dloc)))
     and (p_loc is null or r.share_loc = p_loc or r.dloc = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('dest_kind', k, 'dest_location', l, 'amount', a) order by k, l), '[]'::jsonb) into tot
    from (select x->>'dest_kind' k, nullif(x->>'dest_location', '')::int l, round(sum((x->>'amount')::numeric), 2) a from jsonb_array_elements(rows_) x group by 1, 2) q;
  return jsonb_build_object('month', m, 'location_id', p_loc, 'in_pl', public.rule_on('cost_attrib_in_pl'), 'main_centre_location', public._c78_main_loc(m), 'rows', rows_, 'totals', tot,
    'note', 'showroom / admin shares only; factory shares are in the product cost. A share with no setting is unallocated (not charged anywhere).');
end $$;

-- ---------- the owner's choice per place (and cost type), effective from a month ----------
create or replace function public.cost_attrib_set(p_loc int, p_cost_type text, p_dest text, p_effective date, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.location_cost_attribution; prev public.location_cost_attribution; same public.location_cost_attribution; m date; nid bigint; ct text := nullif(btrim(p_cost_type), ''); cur date := public._m1(public._c78_today()); rs text := nullif(btrim(p_reason), '');
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into a from public.location_cost_attribution where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', a.id); end if; end if;
  if p_dest is null or p_dest not in ('showroom', 'main_centre', 'unallocated') then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'unknown_location'; end if;
  if not (public._all_locs() or public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if ct is not null and not exists (select 1 from public.cost_source_types where code = ct) then raise exception 'unknown_type'; end if;
  if p_effective is null then raise exception 'bad_date'; end if;
  m := public._m1(p_effective);
  if m < cur then raise exception 'effective_in_past'; end if;        -- an earlier month is never rewritten
  if rs is not null and length(rs) > 300 then raise exception 'bad_value'; end if;
  perform public.lock_check(m);
  select * into prev from public.location_cost_attribution where active and location_id = p_loc and cost_type is not distinct from ct and effective_from <= m order by effective_from desc, id desc limit 1;
  if found and (rs is null or length(rs) < 3) then raise exception 'reason_required'; end if;
  select * into same from public.location_cost_attribution where active and location_id = p_loc and cost_type is not distinct from ct and effective_from = m;
  if found then update public.location_cost_attribution set active = false, retired_at = now(), retired_by = auth.uid(), retired_reason = 'replaced' where id = same.id; end if;
  insert into public.location_cost_attribution (location_id, cost_type, dest, effective_from, reason, prev_id, prev_dest, prev_effective_from, client_id, created_by)
    values (p_loc, ct, p_dest, m, rs, prev.id, prev.dest, prev.effective_from, p_client, auth.uid()) returning id into nid;
  if same.id is not null then update public.location_cost_attribution set replaced_by = nid where id = same.id; end if;
  return jsonb_build_object('id', nid, 'effective_from', m, 'previous', prev.dest);
end $$;

-- take a not-yet-past setting back (the earlier setting applies again). Only this month or later; the row stays, inactive.
create or replace function public.cost_attrib_retire(p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.location_cost_attribution;
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  select * into a from public.location_cost_attribution where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._all_locs() or public.can_loc(a.location_id)) then raise exception 'not allowed'; end if;
  if not a.active then return; end if;
  if a.effective_from < public._m1(public._c78_today()) then raise exception 'effective_in_past'; end if;
  perform public.lock_check(a.effective_from);
  update public.location_cost_attribution set active = false, retired_at = now(), retired_by = auth.uid(), retired_reason = left(btrim(p_reason), 300) where id = p_id;
end $$;

-- which place stands for the 'main centre' (blank = none); effective from a month, never earlier than this month
create or replace function public.cost_attrib_main_set(p_loc int, p_effective date, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.cost_attrib_main; same public.cost_attrib_main; m date; nid bigint; cur date := public._m1(public._c78_today());
begin
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
end $$;

-- ---------- re-assign ONE share (reason compulsory, trail append-only, locked period respected) ----------
create or replace function public.cost_share_reassign(p_share bigint, p_to_kind text, p_to_loc int, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sh public.cost_bill_shares; b public.cost_source_bills; s public.cost_sources; o public.cost_share_reassign; cur record; nid bigint; lk boolean; rs text := nullif(btrim(p_reason), ''); tkind text := p_to_kind; tloc int := p_to_loc;
begin
  if not public._c78_manage() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into o from public.cost_share_reassign where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', o.id); end if; end if;
  if rs is null or length(rs) < 3 then raise exception 'reason_required'; end if;
  if length(rs) > 300 then raise exception 'bad_value'; end if;
  if tkind is null or tkind not in ('location', 'main_centre', 'unallocated') then raise exception 'bad_value'; end if;
  if tkind <> 'location' then tloc := null; end if;
  if tkind = 'location' and not exists (select 1 from public.locations where id = tloc and is_active) then raise exception 'unknown_location'; end if;
  select * into sh from public.cost_bill_shares where id = p_share;
  if not found then raise exception 'not_found'; end if;
  select * into b from public.cost_source_bills where id = sh.bill_id;
  select * into s from public.cost_sources where id = b.source_id;
  if not public._cs_src_ok(s.id) then raise exception 'not allowed'; end if;
  if not sh.active or sh.kind <> 'share' or b.status <> 'active' then raise exception 'share_not_active'; end if;
  if sh.dest not in ('showroom', 'admin') then raise exception 'factory_share_not_reassignable'; end if;     -- the factory share is product cost (layer 2)
  if exists (select 1 from public.cost_bill_shares where bill_id = b.id and active and kind = 'unallocated') then raise exception 'bill_not_fully_allocated'; end if;
  select * into cur from public._c78_dest(p_share, b.period_month);
  if cur.dkind = tkind and cur.dloc is not distinct from (case when tkind = 'main_centre' then public._c78_main_loc(b.period_month) else tloc end) then raise exception 'same_destination'; end if;
  lk := public._c78_locked(b.period_month);
  perform public.lock_check(b.period_month);           -- a non-owner is refused in a closed period (period_closed); the owner passes and is flagged below
  insert into public.cost_share_reassign (share_id, bill_id, share_loc, cost_type, period_month, amount, from_kind, from_loc, to_kind, to_loc, reason, locked_override, client_id, created_by)
    values (p_share, b.id, sh.location_id, s.cost_type, b.period_month, sh.amount, cur.dkind, cur.dloc, tkind, tloc, rs, lk, p_client, auth.uid()) returning id into nid;
  if lk then
    perform public._stock_exc(sh.location_id, 'cost_share_locked_reassign', 'yellow', 'বন্ধ হিসাব-মাসের খরচের ভাগ বদলানো হয়েছে (মালিক/অনুমতিপ্রাপ্ত)', 'A cost share of a closed period was re-assigned (owner / allowed)', null, b.period_month, 'STOCK', sh.amount);
  end if;
  return jsonb_build_object('id', nid, 'from_kind', cur.dkind, 'from_location', cur.dloc, 'to_kind', tkind, 'to_location', tloc, 'locked_override', lk);
end $$;

-- ---------- the branch P&L: shares reach it ONLY through rule cost_attrib_in_pl (default off) ----------
-- Both functions below are re-created from their LATEST definitions (phase27 _r3q_*; _p27_pl last changed in phase50). Only the lines tagged bos78 are new.
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'month', to_char(z.mth, 'YYYY-MM'), 'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.mth, r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3, 4) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs integer[], flt jsonb)
 returns setof jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

-- ---------- approval separation hint (NON-BLOCKING) ----------
-- Does this person hold the right: his own grant (not expired) or through one of his roles. The owner holds everything.
create or replace function public._c78_holds(p_user uuid, p_grant text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner')
      or exists (select 1 from public.user_grants g where g.user_id = p_user and g.grant_code = p_grant and (g.valid_until is null or g.valid_until > now()))
      or exists (select 1 from public.user_roles ur join public.rule_grants rg on rg.role_code = ur.role_code and rg.allowed where ur.user_id = p_user and rg.grant_code = p_grant);
$$;
-- p_user: the person who is being given p_grant. suggest = true when he would then hold BOTH sides of an entry/approve pair. Never raises for the owner's choice, never blocks anything.
create or replace function public.grant_separation_hint(p_user uuid, p_grant text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pr record; other text; hit jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then
    return jsonb_build_object('suggest', false, 'blocking', false, 'reason', 'owner', 'pairs', '[]'::jsonb);      -- the owner can always do everything
  end if;
  for pr in select * from public.grant_separation_pairs where p_grant in (entry_grant, approve_grant) order by code loop
    other := case when p_grant = pr.entry_grant then pr.approve_grant else pr.entry_grant end;
    if public._c78_holds(p_user, other) then
      hit := hit || jsonb_build_object('code', pr.code, 'entry_grant', pr.entry_grant, 'approve_grant', pr.approve_grant, 'label_bn', pr.label_bn, 'label_en', pr.label_en);
    end if;
  end loop;
  return jsonb_build_object('suggest', jsonb_array_length(hit) > 0, 'blocking', false, 'pairs', hit,
    'message_bn', case when jsonb_array_length(hit) > 0 then 'অন্য কাউকে অনুমোদনের দায়িত্ব দেওয়া ভালো — একই ব্যক্তি এন্ট্রি ও অনুমোদন দুটোই করলে ঝুঁকি' end,
    'message_en', case when jsonb_array_length(hit) > 0 then 'Better to give the approval to someone else - if the same person enters and approves, there is a risk' end);
end $$;
-- the same question for everybody at once: who holds both sides today (owner only; the owner himself is not listed)
create or replace function public.grant_separation_report() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', u.id, 'pair', pr.code, 'label_bn', pr.label_bn, 'label_en', pr.label_en) order by pr.code, u.id)
    from public.profiles u cross join public.grant_separation_pairs pr
   where u.status = 'active' and not exists (select 1 from public.user_roles where user_id = u.id and role_code = 'owner')
     and public._c78_holds(u.id, pr.entry_grant) and public._c78_holds(u.id, pr.approve_grant)), '[]'::jsonb);
end $$;

-- ---------- privileges ----------
revoke all on function public._c78_manage(), public._c78_today(), public._c78_locked(date), public._c78_nodml(), public._c78_lca_guard(), public._c78_cam_guard(), public._c78_main_loc(date), public._c78_dest(bigint, date),
  public._c78_rows(date, date), public._c78_holds(uuid, text) from public, anon, authenticated;
revoke all on function public.branch_cost_view(date, int), public.cost_attrib_set(int, text, text, date, text, uuid), public.cost_attrib_retire(bigint, text), public.cost_attrib_main_set(int, date, text, uuid),
  public.cost_share_reassign(bigint, text, int, text, uuid), public.grant_separation_hint(uuid, text), public.grant_separation_report() from public, anon;
grant execute on function public.branch_cost_view(date, int), public.cost_attrib_set(int, text, text, date, text, uuid), public.cost_attrib_retire(bigint, text), public.cost_attrib_main_set(int, date, text, uuid),
  public.cost_share_reassign(bigint, text, int, text, uuid), public.grant_separation_hint(uuid, text), public.grant_separation_report() to authenticated;
revoke all on function public._r3q_l1_pnl(date, date, integer[], jsonb), public._r3q_l3_shop_pnl(date, date, integer[], jsonb) from public, anon, authenticated;

-- ===================== phase79.sql =====================
-- Phase 79 (bos79) - INTEGRATION: the final, merged definitions of every function that more than one of phases 72..78 re-created.
-- Paste order: 72, 73, 74, 75, 76, 77, 78, 79 (this file LAST). Additive, paste-twice safe (create or replace only; no table, no data, no rule changes).
--
-- Why: each of 72 / 73 / 74 / 78 re-creates a whole function body from the definition that was latest when that phase was written, so a later phase
-- silently overwrites the change of an earlier one. This file re-creates each such function from the LATEST definition on a database built through
-- phase 78 and re-applies the earlier tagged lines, so the final body contains every change:
--   _acct_docs        = phase52 base + bos72 (rounding split per item type, cost 0 = unknown) + bos74 (conversion cost on inv_finished, Cr overhead_absorbed)
--   production_post   = 7-arg core: phase74 (bos73 approval gate, bos74 conversion cost / actual yield / snapshot) + bos72 (production_requires_cost, cost 0 = unknown);
--                       6-arg wrapper re-asserted as the thin wrapper
--   recipe_cost       = phase74 definition (bos73 approval gate + bos74 rows); phase72 never touched it
--   pool_set          = phase75 definition (bos74 + bos75)
--   _r3q_l1_pnl, _r3q_l3_shop_pnl = phase72 body (bos72 cogs_fallback / unknown_cost_rev) + phase78 union rows (bos78 cost-share rows)
-- Functions touched by only ONE phase are not repeated here (they survive the paste order unchanged); supabase/phase79_test.sql proves every tag is present.
-- Defaults = today's behaviour: production_requires_cost = warn, cost_attrib_in_pl off, conversion mode off, recipe_approval off.

do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public._recipe_gate73(uuid)') is null
     or to_regprocedure('public._conv_cost(uuid, integer, numeric, numeric, date, text)') is null
     or to_regprocedure('public._cs_alloc(bigint)') is null
     or to_regprocedure('public._inb_audit76()') is null
     or to_regprocedure('public._oo_flag_ro77()') is null
     or to_regprocedure('public._c78_rows(date, date)') is null then
    raise exception 'phase79 needs phases 72, 73, 74, 75, 76, 77 and 78 pasted first (in that order)';
  end if;
end $g$;


-- ---------- _acct_docs: phase52 base + bos72 (rounding split, cost 0 = unknown) + bos74 (conversion cost / overhead absorbed in the production block) ----------
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
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
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

-- ---------- recipe_cost: phase74 definition (contains bos73 approval gate + bos74 rows); phase72 did not change it ----------
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; raw_t numeric := 0; pack_t numeric := 0; raw_d numeric := 0; pack_d numeric := 0; complete boolean := true; n record; av numeric; td numeric; yb numeric; gate text;
        conv jsonb; conv_amt numeric; mat numeric; matd numeric; gap numeric; thr numeric; gl numeric; fb int := 0; cinc boolean; mode_ text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
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
end $$;

-- ---------- production_post, 7-argument core: phase74 definition (bos73 gate + bos74 conversion / actual yield) + bos72 (production_requires_cost, cost 0 = unknown) ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamptz, p_note text, p_actual_yield numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  if mode = 'refuse' and coalesce(public.rule_txt('stock_negative_mode'), 'warn') <> 'allow' and not public.has_grant('sell_below_zero', p_loc) then
    for n in select * from public._recipe_need(r.id, p_batches, p_loc) where need > on_hand order by code loop
      shorts := shorts || case when shorts = '' then '' else '; ' end || coalesce(n.code, '') || ' ' || coalesce(n.name_bn, '') || ' (' || round(n.on_hand, 4)::text || ' / ' || n.need::text || ')';
    end loop;
    if shorts <> '' then raise exception 'insufficient_stock' using detail = shorts, hint = 'production'; end if;
  end if;
  -- bos72: rule production_requires_cost = refuse: no ingredient may have an unknown (NULL or 0) cost (default warn = today's behaviour)
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
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if coalesce(av, 0) <= 0 then cost_ok := false; else tot := tot + n.need * av; end if;   -- bos72: cost 0 = unknown
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
end $$;

-- the 6-argument signature stays a thin wrapper (as in phase74)
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language sql security definer set search_path = public as $$
  select public.production_post(p_loc, p_recipe, p_batches, p_client, p_made_at, p_note, null::numeric);
$$;

-- ---------- pool_set: phase75 definition (bos74 + bos75 double-entry warning), re-asserted ----------
create or replace function public.pool_set(p_loc int, p_month date, p_type text, p_amount numeric, p_period_kind text default 'month', p_one_off boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  return jsonb_build_object('id', nid, 'allocated_exists', alloc);
end $$;

-- ---------- l1 / l3: phase72 body (bos72 split columns) + phase78 union rows (bos78 cost shares) ----------
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
  left join public._p27_src72(d1, d2, locs) sx on sx.o_m = p.o_m and sx.o_loc = p.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'month', to_char(z.mth, 'YYYY-MM'), 'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.mth, r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3, 4) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;

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
  from a join public.locations l on l.id = a.o_loc left join sx on sx.o_loc = a.o_loc
  union all  -- bos78: attributed cost-bill shares as SEPARATE rows (only when the switch is on)
  select jsonb_build_object(
    'location_id', l.id,
    'location_bn', l.name_bn || ' · খরচ ভাগ: ' || z.type_bn || case when z.dkind = 'main_centre' then ' (মূল কেন্দ্র)' else '' end,
    'location_en', coalesce(l.name_en, l.name_bn) || ' · cost share: ' || z.type_en || case when z.dkind = 'main_centre' then ' (main centre)' else '' end,
    'expenses', z.amt, 'profit', -z.amt, 'row_type', 'cost_share', 'cost_type', z.cost_type, 'cost_share_dest', z.dkind)
  from (select r.dloc, r.dkind, r.cost_type, min(r.type_bn) type_bn, min(r.type_en) type_en, round(sum(r.amount), 2) amt
          from public._c78_rows(d1, d2) r where r.dkind <> 'unallocated' and r.dloc = any (locs) group by 1, 2, 3) z
  join public.locations l on l.id = z.dloc
  where public.rule_on('cost_attrib_in_pl');
$function$;
-- ISLAMIA BOS: part 3 of 5: phases 80 to 317 (39 files). Paste ALL of this part in one go, wait for Success, then the next part.
-- Every file below is safe to paste twice. If this part stops with an error, tell Claude the error text; do not skip ahead.


-- ===================== phase80.sql =====================
-- Phase 80: (A) one-step opening balance (stock, cash per place, wallets, dues, payables, owner / partner capital) and
--           (B) owner approval modes (G15): one owner-only setting with four modes.
-- Additive; paste-twice safe. Paste after phase79. Own tag: bos80.
-- (A) opening_balance_post(json, client, dry, plug) builds ONE opening journal entry through the existing acct_opening and posts the
--     stock openings through the existing stock_opening in the same transaction. Debit must equal credit, otherwise nothing is
--     written (no balancing figure unless p_plug is true). A second post is refused (opening_exists). Every post writes an
--     append-only opening_batches row and one audit_log line. A dry run writes nothing.
-- (B) rules owner_approval_mode (self | named | logged | off, default self = today's behaviour) and owner_approver_role (blank).
--     owner_approval_mode_set() is owner-only, writes one audit_log line and keeps the legacy switch owner_self_approve in step
--     (self / logged / off = ON, named = OFF), so every existing approval check keeps working. In named mode only a holder of the
--     named role may decide a request made by the owner (trigger on entries and entry_change_requests).

-- ---------- (A) opening batches ----------
create table if not exists public.opening_batches (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  journal_entry_id bigint,
  payload_hash text not null,
  summary jsonb not null default '{}'::jsonb,
  by_user uuid,
  at timestamptz not null default now()
);
alter table public.opening_batches enable row level security;
drop policy if exists opening_batches_read on public.opening_batches;
create policy opening_batches_read on public.opening_batches for select to authenticated using (public._acct_view());
revoke all on public.opening_batches from public, anon, authenticated;
grant select on public.opening_batches to authenticated;
create or replace function public._opening_batches_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted: opening_batches is append-only'; end $$;
drop trigger if exists opening_batches_ro on public.opening_batches;
create trigger opening_batches_ro before update or delete on public.opening_batches for each row execute function public._opening_batches_ro();
drop trigger if exists opening_batches_ro_t on public.opening_batches;
create trigger opening_batches_ro_t before truncate on public.opening_batches for each statement execute function public._opening_batches_ro();

-- p_json: {"stock":[{item_id,location_id,qty,unit,unit_cost}], "cash":[{location_id,mode:cash|bank|mobile|card,amount,wallet}],
--          "customer_dues":[{customer_id,amount,location_id}], "supplier_dues":[{supplier_id,amount,location_id}],
--          "capital":[{kind:owner|partner,amount,party_id}], "other":[{code,debit,credit,memo}]}
create or replace function public.opening_balance_post(p_json jsonb, p_client uuid default null, p_dry boolean default false, p_plug boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ln jsonb := '[]'::jsonb; x jsonb; it public.items; amt numeric; td numeric := 0; tc numeric := 0; k text; diff numeric; r jsonb; jid bigint; h text;
  stock_n int := 0; sec text;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_json is null or jsonb_typeof(p_json) <> 'object' then raise exception 'bad_payload'; end if;
  for sec in select jsonb_object_keys(p_json) loop
    if sec not in ('stock', 'cash', 'customer_dues', 'supplier_dues', 'capital', 'other') then raise exception 'bad_payload'; end if;
    if jsonb_typeof(p_json->sec) <> 'array' then raise exception 'bad_payload'; end if;
  end loop;
  h := md5(p_json::text);
  if p_client is not null and not p_dry then
    perform public._client_lock(p_client);
    select journal_entry_id into jid from public.opening_batches where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', jid); end if;
  end if;
  -- stock: Dr inventory (by item type) = qty x unit cost; a missing cost is refused (never invented)
  for x in select * from jsonb_array_elements(coalesce(p_json->'stock', '[]')) loop
    select * into it from public.items where id = nullif(x->>'item_id', '')::uuid;
    if not found then raise exception 'unknown_item'; end if;
    if nullif(x->>'unit_cost', '') is null then raise exception 'cost_missing'; end if;
    if (x->>'qty') !~ '^[0-9]{1,9}(\.[0-9]{1,4})?$' or (x->>'unit_cost') !~ '^[0-9]{1,9}(\.[0-9]{1,4})?$' then raise exception 'bad_amount'; end if;
    amt := round((x->>'qty')::numeric * (x->>'unit_cost')::numeric, 2);
    ln := ln || jsonb_build_object('a', public._acct_inv_key(it.item_type), 'debit', amt, 'memo', left('stock ' || coalesce(it.name_en, ''), 120), 'location_id', (x->>'location_id')::int);
    stock_n := stock_n + 1;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'cash', '[]')) loop
    k := public._acct_paykey(x->>'mode');
    if (x->>'mode') not in ('cash', 'bank', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    ln := ln || jsonb_build_object('a', k, 'debit', x->>'amount', 'memo', left(coalesce(nullif(x->>'wallet', ''), x->>'mode'), 60), 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'customer_dues', '[]')) loop
    if nullif(x->>'customer_id', '') is null or not exists (select 1 from public.customers where id = (x->>'customer_id')::uuid) then raise exception 'unknown_party'; end if;
    ln := ln || jsonb_build_object('a', 'receivable', 'debit', x->>'amount', 'party_type', 'customer', 'party_id', x->>'customer_id', 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'supplier_dues', '[]')) loop
    if nullif(x->>'supplier_id', '') is null or not exists (select 1 from public.suppliers where id = (x->>'supplier_id')::uuid) then raise exception 'unknown_party'; end if;
    ln := ln || jsonb_build_object('a', 'payable', 'credit', x->>'amount', 'party_type', 'supplier', 'party_id', x->>'supplier_id', 'location_id', x->>'location_id');
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'capital', '[]')) loop
    if (x->>'kind') = 'owner' then ln := ln || jsonb_build_object('code', '3100', 'credit', x->>'amount', 'party_type', null, 'party_id', null);
    elsif (x->>'kind') = 'partner' then ln := ln || jsonb_build_object('code', '3200', 'credit', x->>'amount', 'party_type', 'partner', 'party_id', x->>'party_id');
    else raise exception 'bad_kind'; end if;
  end loop;
  for x in select * from jsonb_array_elements(coalesce(p_json->'other', '[]')) loop
    ln := ln || jsonb_build_object('code', x->>'code', 'debit', coalesce(x->>'debit', '0'), 'credit', coalesce(x->>'credit', '0'), 'memo', x->>'memo');
  end loop;
  if jsonb_array_length(ln) = 0 then raise exception 'no_lines'; end if;
  -- totals from the resolved lines (dry run answers even when unbalanced; a real post refuses)
  select coalesce(sum((e->>'debit')::numeric), 0), coalesce(sum((e->>'credit')::numeric), 0) into td, tc from jsonb_array_elements(public._acct_resolve(ln, null)) e;
  diff := round(td - tc, 2);
  if p_dry then
    return jsonb_build_object('dry', true, 'total_debit', td, 'total_credit', tc, 'difference', diff, 'balanced', diff = 0, 'lines', jsonb_array_length(ln), 'stock_lines', stock_n);
  end if;
  if diff <> 0 and not coalesce(p_plug, false) then raise exception 'unbalanced' using detail = 'debit ' || td::text || ' credit ' || tc::text; end if;
  -- the one journal entry (raises opening_exists on a second post, unbalanced / data_needed otherwise); the whole call is one transaction
  r := public.acct_opening(ln, coalesce(p_plug, false), 'Opening balances', p_client, false);
  jid := (r->>'id')::bigint;
  for x in select * from jsonb_array_elements(coalesce(p_json->'stock', '[]')) loop
    perform public.stock_opening((x->>'item_id')::uuid, (x->>'location_id')::int, (x->>'qty')::numeric, (x->>'unit_cost')::numeric, nullif(x->>'unit', ''), 'opening balance', null);
  end loop;
  insert into public.opening_batches (client_id, journal_entry_id, payload_hash, summary, by_user)
    values (p_client, jid, h, jsonb_build_object('total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n), auth.uid());
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'opening_post', 'journal_entries', jid::text,
      jsonb_build_object('payload_hash', h, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n));
  return jsonb_build_object('id', jid, 'total_debit', td, 'total_credit', tc, 'plug', diff, 'stock_lines', stock_n);
end $$;

-- ---------- (B) owner approval modes ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('owner_approval_mode', 'lists', 'choice', '"self"', null, '["self","named","logged","off"]', null, null,
  'মালিকের নিজের এন্ট্রির অনুমোদন', 'Owner এর নিজের entry এর approval', 'Approval of the owner''s own entries',
  'self = মালিক নিজে, named = নির্ধারিত ভূমিকা, logged = নিজে ও সবসময় লগে, off = নিয়ন্ত্রণ বন্ধ', 'self = owner approves, named = a named role approves, logged = owner approves and it is always shown in the log, off = control off', 15),
 ('owner_approver_role', 'lists', 'text', null, null, null, null, null,
  'নির্ধারিত অনুমোদনকারী ভূমিকা (named হলে)', 'Named approver role (named mode)', 'Named approver role (used in named mode)',
  'ফাঁকা থাকলে named মোড চালু করা যায় না', 'Blank blocks named mode', 16)
on conflict (key) do nothing;

create or replace function public._owner_mode() returns text language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_txt('owner_approval_mode'), 'self') $$;

create or replace function public.owner_approval_mode() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'approver_role', public.rule_txt('owner_approver_role'), 'owner_self_approve', public.rule_on('owner_self_approve'));
end $$;

create or replace function public.owner_approval_mode_set(p_mode text, p_role text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if p_mode = 'named' then
    rl := coalesce(rl, old_r);
    if rl is null then raise exception 'data_needed:owner_approver_role'; end if;
    if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
  end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r), 'new', jsonb_build_object('mode', p_mode, 'role', coalesce(rl, old_r)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', coalesce(rl, old_r), 'owner_self_approve', p_mode <> 'named');
end $$;

-- the log display (owner only, every mode): owner-made entries and change requests with who decided and how
create or replace function public.owner_approval_log(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('mode', public._owner_mode(), 'rows', coalesce((select jsonb_agg(z order by z->>'at' desc) from (
    select jsonb_build_object('kind', 'entry', 'id', e.id, 'form', e.form_code, 'status', e.status, 'maker', e.created_by, 'decided_by', e.checked_by, 'at', e.checked_at,
      'how', case when e.checked_by = e.created_by then 'self' else 'other' end) z
      from public.entries e where e.checked_by is not null and exists (select 1 from public.user_roles ur where ur.user_id = e.created_by and ur.role_code = 'owner')
    union all
    select jsonb_build_object('kind', 'change', 'id', c.id, 'form', null, 'status', c.status, 'maker', c.requested_by, 'decided_by', c.decided_by, 'at', c.decided_at,
      'how', case when c.decided_by = c.requested_by then 'self' else 'other' end)
      from public.entry_change_requests c where c.decided_by is not null and exists (select 1 from public.user_roles ur where ur.user_id = c.requested_by and ur.role_code = 'owner')
    order by 1 desc limit greatest(1, least(coalesce(p_limit, 100), 500))) q), '[]'::jsonb));
end $$;

-- named mode: a decision on the owner's own record must come from a holder of the named role
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  if rl is null or decider is null or not exists (select 1 from public.user_roles where user_id = decider and role_code = rl) then raise exception 'named_approver_only'; end if;
  return new;
end $$;
drop trigger if exists entries_named_guard80 on public.entries;
create trigger entries_named_guard80 before update on public.entries for each row execute function public._owner_named_guard();
drop trigger if exists ecr_named_guard80 on public.entry_change_requests;
create trigger ecr_named_guard80 before update on public.entry_change_requests for each row execute function public._owner_named_guard();

-- the mode rule may only be changed through owner_approval_mode_set (keeps the legacy switch in step)
create or replace function public._rules_mode_guard80() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key in ('owner_approval_mode', 'owner_approver_role') and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos80.setting', true), '') <> '1' then raise exception 'use owner_approval_mode_set'; end if;
  return new;
end $$;
drop trigger if exists rules_mode_guard80 on public.rules;
create trigger rules_mode_guard80 before update on public.rules for each row execute function public._rules_mode_guard80();
revoke all on function public.opening_balance_post(jsonb, uuid, boolean, boolean), public.owner_approval_mode(), public.owner_approval_mode_set(text, text, text), public.owner_approval_log(int),
  public._owner_mode(), public._owner_named_guard(), public._opening_batches_ro(), public._rules_mode_guard80() from public, anon, authenticated;
grant execute on function public.opening_balance_post(jsonb, uuid, boolean, boolean), public.owner_approval_mode(), public.owner_approval_mode_set(text, text, text), public.owner_approval_log(int) to authenticated;

-- ===================== phase81.sql =====================
-- Phase 81 (bos81) - SHORTAGES: G4 hub/count cash short, G5 customer advance check, G6 transit short.
-- Paste AFTER phase79 (phase80 is a different, independent file). Additive and paste-twice safe: create or replace / if not exists / on conflict do nothing.
-- It edits NO existing function. The new journal sources are served by ONE new function, public._b_docs(date), which has exactly the columns of
-- public._acct_docs(date). The integrator adds one line to _acct_docs (see docs/integration/B.md). Until then, public.b_post_pending() posts them itself.
--
-- G4  shortage_cash_cases   one case per cash count with a short/over (made by a trigger on exceptions flag cash_short_over). Nothing posts until the
--                           owner approves. Source 'cash_short' (count date). short: Dr cash short/over 5800, Cr cash. over: Dr cash, Cr 5800.
--                           Owner setting cash_short_treatment 'staff_receivable' books a SHORT as Dr staff advances (1220, the named employee) instead of expense.
-- G5  cust_advance_check()  read-only: customer advance held per cash moves vs per journal account 2300. The posting already exists (phase40/52/79).
-- G6  shortage_transit      one row per transfer received short (trigger on stock_transfers). Value from the ledger cost at send. Owner decides:
--                           claim to carrier (Dr 1240 receivable from carrier, Cr inventory), recover (Dr cash/bank/mobile, Cr 1240),
--                           write off (Dr loss 5100, Cr inventory, or Cr 1240 after a claim). Every step is an append-only event = one journal source.
-- Owner decisions NOT guessed, all are rules with a safe default:
--   cash_short_post_on        OFF   (approved cases wait, nothing is posted)
--   cash_short_treatment      expense | staff_receivable   default expense
--   short_decider             owner | accounts_manager     default owner
--   transit_short_bearer      ask | carrier | shop         default ask (owner picks claim or write-off case by case)

do $g$ begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_write(date,integer,text,text,text,text,text,jsonb,bigint,uuid,text)') is null
     or to_regclass('public.stock_transfers') is null or to_regclass('public.exceptions') is null or to_regclass('public.rules') is null then
    raise exception 'phase81 needs the accounts (phase40) and stock (phase10) phases pasted first';
  end if;
end $g$;

-- ---------- chart: 1240 Receivable from carrier (take 1240 unless the code is used for something else) ----------
do $seed$ declare code_ text;
begin
  if not exists (select 1 from public.coa_accounts where code = '1240' and name_en = 'Receivable from carrier') then
    code_ := case when exists (select 1 from public.coa_accounts where code = '1240') then '1245' else '1240' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select code_, 'বাহকের কাছে পাওনা (পথে কম)', 'Receivable from carrier', 'asset', 'debit', false, true, 24, (select id from public.coa_accounts where code = '1200')
       where not exists (select 1 from public.coa_accounts where code = code_);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('cash_short', '5800', 'ক্যাশ কম / বেশি', 'Cash short / over'),
  ('transit_loss', '5100', 'পথে কমে যাওয়া মালের ক্ষতি', 'Loss on goods short in transit')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'carrier_claim', a.id, 'বাহকের কাছে পাওনা', 'Receivable from carrier' from public.coa_accounts a where a.name_en = 'Receivable from carrier' and a.is_system
on conflict (key) do nothing;

-- ---------- owner settings (rules) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('cash_short_post_on', 'books', 'switch', 'false', null, null, null, null, 'ক্যাশ কম/বেশি অনুমোদনের পর খাতায় লিখুন', 'Cash কম/বেশি approve হলে খাতায় লিখুন', 'Post an approved cash short/over to the books',
  'বন্ধ থাকলে অনুমোদিত কেস অপেক্ষায় থাকে, খাতায় কিছু লেখা হয় না।', 'Off = approved cases wait and nothing is posted.', 820),
 ('cash_short_treatment', 'books', 'choice', '"expense"', null, '["expense","staff_receivable"]', null, null, 'ক্যাশ ঘাটতি কীভাবে ধরা হবে', 'Cash ঘাটতি কীভাবে ধরা হবে', 'How a cash SHORT is booked',
  'expense = ক্যাশ কম/বেশি খরচ (৫৮০০)। staff_receivable = নির্দিষ্ট কর্মীর কাছে পাওনা (১২২০)। বেশি হলে সবসময় ৫৮০০।', 'expense = cash short/over account (5800). staff_receivable = owed by the named employee (1220). An OVER always goes to 5800.', 821),
 ('short_decider', 'books', 'choice', '"owner"', null, '["owner","accounts_manager"]', null, null, 'কম/বেশির সিদ্ধান্ত কে নেবে', 'কম/বেশির সিদ্ধান্ত কে নেবে', 'Who decides cash short and transit short cases',
  'owner = শুধু মালিক। accounts_manager = হিসাবের ম্যানেজ অনুমতিওয়ালাও।', 'owner = only the owner. accounts_manager = also people with the accounts manage grant. Nobody decides a count they made themselves.', 822),
 ('transit_short_bearer', 'books', 'choice', '"ask"', null, '["ask","carrier","shop"]', null, null, 'পথে কম মালের ক্ষতি কে বহন করবে', 'পথে কম মালের loss কে বহন করবে', 'Who bears goods short in transit',
  'ask = প্রতিটি কেসে মালিক ঠিক করেন। carrier = আগে বাহকের কাছে দাবি করতে হবে। shop = দাবি নয়, সরাসরি ক্ষতি।', 'ask = the owner chooses per case. carrier = claim to the carrier first (no direct write-off). shop = no claim, write off as loss.', 823)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.shortage_cash_cases (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null unique references public.entries(id),
  form_code text,
  location_id int not null references public.locations(id),
  case_date date not null,                                        -- the count date: the journal date
  amount numeric not null check (amount <> 0),                    -- signed: counted minus expected. negative = SHORT, positive = OVER
  reason text,
  status text not null default 'open' check (status in ('open', 'approved', 'rejected', 'void')),
  treatment text check (treatment is null or treatment in ('expense', 'staff_receivable')),   -- frozen when approved
  employee_id uuid references public.employees(id),
  decided_by uuid, decided_at timestamptz, decide_note text,
  void_by uuid, void_at timestamptz, void_note text,
  created_at timestamptz not null default now(),
  check (treatment <> 'staff_receivable' or employee_id is not null)
);
create index if not exists shortage_cash_status on public.shortage_cash_cases (status, case_date);

create table if not exists public.shortage_transit (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null unique references public.stock_transfers(id),
  item_id uuid not null references public.items(id),
  from_location_id int not null references public.locations(id),
  to_location_id int not null references public.locations(id),
  qty_short numeric not null check (qty_short > 0),
  value numeric check (value is null or value > 0),               -- cost at send. null = cost missing: nothing posts until the owner enters a cost
  value_source text check (value_source is null or value_source in ('ledger', 'owner')),
  status text not null default 'open' check (status in ('open', 'claimed', 'recovered', 'written_off')),
  claimed_amount numeric not null default 0 check (claimed_amount >= 0),
  recovered_amount numeric not null default 0 check (recovered_amount >= 0),
  written_off_amount numeric not null default 0 check (written_off_amount >= 0),
  received_on date not null,
  decided_by uuid, decided_at timestamptz, note text,
  created_at timestamptz not null default now()
);
create index if not exists shortage_transit_status on public.shortage_transit (status);

create table if not exists public.shortage_transit_events (
  id uuid primary key default gen_random_uuid(),
  shortage_id uuid not null references public.shortage_transit(id),
  kind text not null check (kind in ('claim', 'recover', 'writeoff')),
  amount numeric not null check (amount > 0),
  mode text check (mode is null or mode in ('cash', 'bank', 'mobile')),
  against_claim boolean not null default false,                   -- a write-off made after a claim (Cr 1240 instead of inventory)
  location_id int not null references public.locations(id),
  event_date date not null,
  note text not null check (length(btrim(note)) >= 3),
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'recover') = (mode is not null))
);
create unique index if not exists shortage_one_claim on public.shortage_transit_events (shortage_id) where kind = 'claim';
create index if not exists shortage_events_sh on public.shortage_transit_events (shortage_id);

create or replace function public._b_events_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: shortage events are a record, they cannot be changed or deleted'; end $$;
drop trigger if exists shortage_events_ro on public.shortage_transit_events;
create trigger shortage_events_ro before update or delete on public.shortage_transit_events for each row execute function public._b_events_ro();
drop trigger if exists shortage_events_ro_t on public.shortage_transit_events;
create trigger shortage_events_ro_t before truncate on public.shortage_transit_events for each statement execute function public._b_events_ro();

drop trigger if exists audit_shortage_cash on public.shortage_cash_cases;
create trigger audit_shortage_cash after insert or update on public.shortage_cash_cases for each row execute function public.log_change('id');
drop trigger if exists audit_shortage_transit on public.shortage_transit;
create trigger audit_shortage_transit after insert or update on public.shortage_transit for each row execute function public.log_change('id');
drop trigger if exists audit_shortage_events on public.shortage_transit_events;
create trigger audit_shortage_events after insert on public.shortage_transit_events for each row execute function public.log_change('id');

alter table public.shortage_cash_cases enable row level security;
alter table public.shortage_transit enable row level security;
alter table public.shortage_transit_events enable row level security;
drop policy if exists shortage_cash_read on public.shortage_cash_cases;
create policy shortage_cash_read on public.shortage_cash_cases for select to authenticated using (public._acct_view() and public.can_loc(location_id));
drop policy if exists shortage_transit_read on public.shortage_transit;
create policy shortage_transit_read on public.shortage_transit for select to authenticated using (public._acct_view() and (public.can_loc(from_location_id) or public.can_loc(to_location_id)));
drop policy if exists shortage_events_read on public.shortage_transit_events;
create policy shortage_events_read on public.shortage_transit_events for select to authenticated using (public._acct_view() and public.can_loc(location_id));
revoke all on public.shortage_cash_cases, public.shortage_transit, public.shortage_transit_events from public, anon, authenticated;
grant select on public.shortage_cash_cases, public.shortage_transit, public.shortage_transit_events to authenticated;

-- ---------- helpers ----------
create or replace function public._b_may_decide() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (coalesce(public.rule_txt('short_decider'), 'owner') = 'accounts_manager' and public._acct_manage()));
$$;

-- every posting line set must balance; refuse otherwise (used before a decision is stored and by the tests)
create or replace function public._b_assert_balanced(p_lines jsonb) returns void language plpgsql immutable set search_path = public as $$
declare d numeric := 0; c numeric := 0; e jsonb;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'need_two_lines'; end if;
  for e in select * from jsonb_array_elements(p_lines) loop
    d := d + coalesce(nullif(e->>'d', '')::numeric, 0); c := c + coalesce(nullif(e->>'c', '')::numeric, 0);
  end loop;
  if d <> c or d <= 0 then raise exception 'unbalanced' using detail = 'debit ' || d::text || ' credit ' || c::text; end if;
end $$;

create or replace function public._b_need_map(p_key text) returns void language plpgsql stable security definer set search_path = public as $$
begin if not exists (select 1 from public.acct_mappings where key = p_key) then raise exception 'mapping_missing:%', p_key; end if; end $$;

create or replace function public._b_check_date(p_date date) returns void language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start();
begin
  if st is null then raise exception 'data_needed'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  if p_date < st then raise exception 'before_start'; end if;
  if public._acct_locked(p_date) then raise exception 'period_locked'; end if;
end $$;

-- ---------- G4: a case is made for every cash_short_over exception ----------
create or replace function public._b_cash_case_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.flag_code = 'cash_short_over' and coalesce(new.amount, 0) <> 0 and new.entry_id is not null and new.location_id is not null then  -- bos85: an exception without an entry or a place makes no case (it must never block the exception insert; phase46 test)
    insert into public.shortage_cash_cases (entry_id, form_code, location_id, case_date, amount)
      values (new.entry_id, new.form_code, new.location_id, new.entry_date, new.amount)
      on conflict (entry_id) do update set amount = excluded.amount, case_date = excluded.case_date, location_id = excluded.location_id
        where public.shortage_cash_cases.status = 'open';
  end if;
  return null;
end $$;
drop trigger if exists exceptions_cash_case on public.exceptions;
create trigger exceptions_cash_case after insert on public.exceptions for each row execute function public._b_cash_case_trg();

-- owner: make cases for short/over exceptions that existed before this phase (not automatic)
create or replace function public.cash_short_backfill() returns jsonb language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  with ins as (
    insert into public.shortage_cash_cases (entry_id, form_code, location_id, case_date, amount)
    select distinct on (x.entry_id) x.entry_id, x.form_code, x.location_id, x.entry_date, x.amount from public.exceptions x
     where x.flag_code = 'cash_short_over' and coalesce(x.amount, 0) <> 0 order by x.entry_id, x.id desc
    on conflict (entry_id) do nothing returning 1)
  select count(*) into n from ins;
  return jsonb_build_object('made', n);
end $$;

create or replace function public.cash_short_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(j order by j->>'case_date' desc, j->>'created_at' desc) from (
    select jsonb_build_object('id', c.id, 'entry_id', c.entry_id, 'form_code', c.form_code, 'location_id', c.location_id, 'location', coalesce(l.name_en, l.name_bn),
      'case_date', c.case_date, 'amount', c.amount, 'kind', case when c.amount < 0 then 'short' else 'over' end, 'status', c.status, 'treatment', c.treatment,
      'employee_id', c.employee_id, 'decide_note', c.decide_note, 'decided_at', c.decided_at, 'created_at', c.created_at,
      'posted', exists (select 1 from public.journal_entries e where e.source_type = 'cash_short' and e.source_id = c.id::text and e.reverses_id is null),
      'can_decide', public._b_may_decide() and c.status = 'open') j
    from public.shortage_cash_cases c left join public.locations l on l.id = c.location_id
    where public.can_loc(c.location_id) and (p_status is null or c.status = p_status)
    order by c.case_date desc, c.created_at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q), '[]'::jsonb);
end $$;

create or replace function public.cash_short_decide(p_id uuid, p_approve boolean, p_note text, p_employee uuid default null, p_force boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.shortage_cash_cases; en public.entries; tr text; dup boolean := false; lines jsonb; a numeric;
begin
  if p_approve is null then raise exception 'bad_input'; end if;
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into c from public.shortage_cash_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(c.location_id) then raise exception 'not allowed for this location'; end if;
  if c.status <> 'open' then raise exception 'already_decided'; end if;
  select * into en from public.entries where id = c.entry_id;
  if en.created_by = auth.uid() and not public.is_owner() then raise exception 'own_count'; end if;   -- nobody decides the count they made
  if not p_approve then
    update public.shortage_cash_cases set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decide_note = left(btrim(p_note), 300) where id = c.id;
    return jsonb_build_object('id', c.id, 'status', 'rejected');
  end if;
  a := abs(c.amount);
  tr := coalesce(public.rule_txt('cash_short_treatment'), 'expense');
  if c.amount > 0 then tr := 'expense'; end if;                    -- an over always goes to the cash short/over account
  if tr = 'staff_receivable' and (p_employee is null or not exists (select 1 from public.employees where id = p_employee)) then raise exception 'employee_required'; end if;
  perform public._b_need_map('cash_short'); perform public._b_need_map('pay_cash');
  if tr = 'staff_receivable' then perform public._b_need_map('staff_advance'); end if;
  perform public._b_check_date(c.case_date);
  lines := public._b_cash_lines(c.amount, tr, p_employee);
  perform public._b_assert_balanced(lines);
  -- double count warning (a manual journal for the same short on the same day and place)
  select exists (select 1 from public.journal_entries e join public.journal_lines l on l.entry_id = e.id
                   where e.entry_date = c.case_date and e.location_id = c.location_id and e.source_type = 'manual' and e.reverses_id is null
                     and l.account_id = (select account_id from public.acct_mappings where key = 'cash_short')) into dup;
  if dup and not coalesce(p_force, false) then raise exception 'possible_duplicate' using hint = 'a manual journal for cash short/over already exists on this day and place; repeat with p_force = true if it is a different amount'; end if;
  update public.shortage_cash_cases set status = 'approved', treatment = tr, employee_id = case when tr = 'staff_receivable' then p_employee end,
    decided_by = auth.uid(), decided_at = now(), decide_note = left(btrim(p_note), 300) where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'approved', 'amount', c.amount, 'treatment', tr, 'duplicate_warning', dup, 'posts_now', public.rule_on('cash_short_post_on'));
end $$;

create or replace function public.cash_short_void(p_id uuid, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.shortage_cash_cases;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into c from public.shortage_cash_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(c.location_id) then raise exception 'not allowed for this location'; end if;
  if c.status <> 'approved' then raise exception 'not_approved'; end if;
  update public.shortage_cash_cases set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'void');
end $$;

-- the two journal sides of a case (keys resolve through acct_mappings)
create or replace function public._b_cash_lines(p_amount numeric, p_treatment text, p_employee uuid) returns jsonb language sql immutable set search_path = public as $$
  select case
    when p_amount < 0 and p_treatment = 'staff_receivable' then jsonb_build_array(jsonb_build_object('a', 'staff_advance', 'd', abs(p_amount), 'pt', 'staff', 'pid', p_employee::text), jsonb_build_object('a', 'pay_cash', 'c', abs(p_amount)))
    when p_amount < 0 then jsonb_build_array(jsonb_build_object('a', 'cash_short', 'd', abs(p_amount)), jsonb_build_object('a', 'pay_cash', 'c', abs(p_amount)))
    else jsonb_build_array(jsonb_build_object('a', 'pay_cash', 'd', abs(p_amount)), jsonb_build_object('a', 'cash_short', 'c', abs(p_amount))) end;
$$;

-- ---------- G6: a row for every transfer received short ----------
create or replace function public._b_transit_make(p_transfer uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; ov numeric; iv numeric; miss boolean; v numeric; id_ uuid;
begin
  select * into t from public.stock_transfers where id = p_transfer;
  if not found or t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then return null; end if;
  select coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0), count(*) = 0 or bool_or(coalesce(l.unit_cost, 0) <= 0) into ov, miss
    from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_out';
  select coalesce(sum(l.qty_delta * coalesce(l.unit_cost, 0)), 0), miss or coalesce(bool_or(coalesce(l.unit_cost, 0) <= 0), false) into iv, miss
    from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_in';
  v := round(ov - iv, 2);
  if miss or v <= 0 then v := null; end if;                        -- unknown cost stays unknown, never guessed
  insert into public.shortage_transit (transfer_id, item_id, from_location_id, to_location_id, qty_short, value, value_source, received_on)
    values (t.id, t.item_id, t.from_location_id, t.to_location_id, t.qty - t.received_qty, v, case when v is not null then 'ledger' end,
            coalesce((t.received_at at time zone 'Asia/Dhaka')::date, public._acct_today()))
    on conflict (transfer_id) do nothing returning id into id_;
  return id_;
end $$;
create or replace function public._b_transit_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'received' and old.status is distinct from 'received' then perform public._b_transit_make(new.id); end if;
  return null;
end $$;
drop trigger if exists stock_transfers_short on public.stock_transfers;
create trigger stock_transfers_short after update on public.stock_transfers for each row execute function public._b_transit_trg();

create or replace function public.transit_short_backfill() returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for r in select id from public.stock_transfers where status = 'received' and received_qty < qty loop
    if public._b_transit_make(r.id) is not null then n := n + 1; end if;
  end loop;
  return jsonb_build_object('made', n);
end $$;

create or replace function public.transit_short_list(p_status text default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(j order by j->>'received_on' desc) from (
    select jsonb_build_object('id', s.id, 'transfer_id', s.transfer_id, 'item_id', s.item_id, 'item_bn', i.name_bn, 'item_en', coalesce(i.name_en, i.name_bn),
      'from_location_id', s.from_location_id, 'to_location_id', s.to_location_id, 'from_name', coalesce(lf.name_en, lf.name_bn), 'to_name', coalesce(lt.name_en, lt.name_bn),
      'qty_short', s.qty_short, 'value', s.value, 'cost_missing', s.value is null, 'status', s.status, 'claimed_amount', s.claimed_amount, 'recovered_amount', s.recovered_amount,
      'written_off_amount', s.written_off_amount, 'outstanding_claim', s.claimed_amount - s.recovered_amount - (select coalesce(sum(e.amount), 0) from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim),
      'received_on', s.received_on, 'note', s.note, 'bearer_rule', coalesce(public.rule_txt('transit_short_bearer'), 'ask'), 'can_decide', public._b_may_decide() and s.status in ('open', 'claimed')) j
    from public.shortage_transit s join public.items i on i.id = s.item_id
    left join public.locations lf on lf.id = s.from_location_id left join public.locations lt on lt.id = s.to_location_id
    where (public.can_loc(s.from_location_id) or public.can_loc(s.to_location_id)) and (p_status is null or s.status = p_status)
    order by s.received_on desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) q), '[]'::jsonb);
end $$;

-- one place for the checks every transit decision shares; returns the locked row
create or replace function public._b_transit_pick(p_id uuid, p_note text, p_date date) returns public.shortage_transit language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into s from public.shortage_transit where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.can_loc(s.from_location_id) or public.can_loc(s.to_location_id)) then raise exception 'not allowed for this location'; end if;
  if s.status in ('recovered', 'written_off') then raise exception 'already_decided'; end if;
  if s.value is null then raise exception 'cost_missing'; end if;
  if p_date is not null and p_date < s.received_on then raise exception 'bad_date'; end if;
  perform public._b_check_date(coalesce(p_date, public._acct_today()));
  return s;
end $$;

create or replace function public.transit_short_set_cost(p_id uuid, p_unit_cost numeric, p_note text) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit;
begin
  if not public._b_may_decide() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_unit_cost is null or not (p_unit_cost > 0 and p_unit_cost <= 1000000000) then raise exception 'bad_amount'; end if;
  select * into s from public.shortage_transit where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.status <> 'open' then raise exception 'already_decided'; end if;
  if s.value is not null then raise exception 'cost_known'; end if;
  update public.shortage_transit set value = round(p_unit_cost * qty_short, 2), value_source = 'owner', note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'value', round(p_unit_cost * s.qty_short, 2));
end $$;

create or replace function public.transit_short_claim(p_id uuid, p_note text, p_date date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); it text;
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  if s.status <> 'open' then raise exception 'already_decided'; end if;
  if coalesce(public.rule_txt('transit_short_bearer'), 'ask') = 'shop' then raise exception 'shop_bears'; end if;
  perform public._b_need_map('carrier_claim');
  select item_type into it from public.items where id = s.item_id; perform public._b_need_map(public._acct_inv_key(it));
  perform public._b_assert_balanced(public._b_transit_lines('claim', s.value, null, false, it));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, against_claim, location_id, event_date, note, created_by)
    values (ev, s.id, 'claim', s.value, false, s.from_location_id, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set status = 'claimed', claimed_amount = s.value, decided_by = auth.uid(), decided_at = now(), note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'claimed', 'event_id', ev, 'amount', s.value);
end $$;

create or replace function public.transit_short_recover(p_id uuid, p_amount numeric, p_mode text, p_note text, p_date date default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); out_ numeric; loc int; it text;
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  if s.status <> 'claimed' then raise exception 'not_claimed'; end if;
  if p_mode is null or p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  select s.claimed_amount - s.recovered_amount - coalesce(sum(e.amount), 0) into out_ from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim;
  p_amount := round(coalesce(p_amount, out_), 2);
  if p_amount is null or p_amount <= 0 or p_amount > out_ then raise exception 'bad_amount' using detail = 'outstanding ' || out_::text; end if;
  loc := coalesce(p_loc, s.from_location_id);
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  perform public._b_need_map('carrier_claim'); perform public._b_need_map(public._acct_paykey(p_mode));
  perform public._b_assert_balanced(public._b_transit_lines('recover', p_amount, p_mode, false, null));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, mode, location_id, event_date, note, created_by)
    values (ev, s.id, 'recover', p_amount, p_mode, loc, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set recovered_amount = s.recovered_amount + p_amount, decided_by = auth.uid(), decided_at = now(),
    status = case when out_ - p_amount = 0 then 'recovered' else 'claimed' end where id = s.id;
  return jsonb_build_object('id', s.id, 'status', case when out_ - p_amount = 0 then 'recovered' else 'claimed' end, 'event_id', ev, 'amount', p_amount, 'outstanding', out_ - p_amount);
end $$;

create or replace function public.transit_short_writeoff(p_id uuid, p_note text, p_date date default null) returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.shortage_transit; d date := coalesce(p_date, public._acct_today()); ev uuid := gen_random_uuid(); amt numeric; ac boolean; it text; bearer text := coalesce(public.rule_txt('transit_short_bearer'), 'ask');
begin
  s := public._b_transit_pick(p_id, p_note, p_date);
  ac := s.status = 'claimed';
  if not ac and bearer = 'carrier' then raise exception 'claim_first'; end if;
  if ac then
    select s.claimed_amount - s.recovered_amount - coalesce(sum(e.amount), 0) into amt from public.shortage_transit_events e where e.shortage_id = s.id and e.kind = 'writeoff' and e.against_claim;
  else amt := s.value; end if;
  if amt is null or amt <= 0 then raise exception 'bad_amount'; end if;
  select item_type into it from public.items where id = s.item_id;
  perform public._b_need_map('transit_loss'); perform public._b_need_map(case when ac then 'carrier_claim' else public._acct_inv_key(it) end);
  perform public._b_assert_balanced(public._b_transit_lines('writeoff', amt, null, ac, it));
  insert into public.shortage_transit_events (id, shortage_id, kind, amount, against_claim, location_id, event_date, note, created_by)
    values (ev, s.id, 'writeoff', amt, ac, s.from_location_id, d, left(btrim(p_note), 300), auth.uid());
  update public.shortage_transit set status = 'written_off', written_off_amount = amt, decided_by = auth.uid(), decided_at = now(), note = left(btrim(p_note), 300) where id = s.id;
  return jsonb_build_object('id', s.id, 'status', 'written_off', 'event_id', ev, 'amount', amt);
end $$;

create or replace function public._b_transit_lines(p_kind text, p_amount numeric, p_mode text, p_against_claim boolean, p_item_type text) returns jsonb language sql immutable set search_path = public as $$
  select case p_kind
    when 'claim' then jsonb_build_array(jsonb_build_object('a', 'carrier_claim', 'd', p_amount), jsonb_build_object('a', public._acct_inv_key(p_item_type), 'c', p_amount))
    when 'recover' then jsonb_build_array(jsonb_build_object('a', public._acct_paykey(p_mode), 'd', p_amount), jsonb_build_object('a', 'carrier_claim', 'c', p_amount))
    else jsonb_build_array(jsonb_build_object('a', 'transit_loss', 'd', p_amount), jsonb_build_object('a', case when p_against_claim then 'carrier_claim' else public._acct_inv_key(p_item_type) end, 'c', p_amount)) end;
$$;

-- ---------- the journal source: same columns as _acct_docs, the integrator calls it from there (docs/integration/B.md) ----------
create or replace function public._b_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
begin
  -- G4: an approved cash short / over (a voided one is reversed)
  return query
  select 'cash_short'::text, c.id::text, c.case_date, c.location_id,
    ('Cash ' || case when c.amount < 0 then 'short' else 'over' end || ' at count ' || c.case_date::text)::text, null::text,
    c.status = 'approved', (c.void_at at time zone 'Asia/Dhaka')::date, null::text,
    case when c.status = 'approved' and not public.rule_on('cash_short_post_on') then 'cash_short_post_off' end,
    public._b_cash_lines(c.amount, coalesce(c.treatment, 'expense'), c.employee_id)
  from public.shortage_cash_cases c
  where c.case_date >= p_start and c.status in ('approved', 'void') and public._acct_need('cash_short', c.id::text, c.status = 'approved');

  -- G6: claim / recover / write-off events (append-only, never voided)
  return query
  select ('transit_' || e.kind)::text, e.id::text, e.event_date, e.location_id,
    (case e.kind when 'claim' then 'Transit short claimed from carrier' when 'recover' then 'Transit short recovered from carrier' else 'Transit short written off' end)::text, null::text,
    true, null::date, null::text, null::text,
    public._b_transit_lines(e.kind, e.amount, e.mode, e.against_claim, it.item_type)
  from public.shortage_transit_events e join public.shortage_transit s on s.id = e.shortage_id join public.items it on it.id = s.item_id
  where e.event_date >= p_start and public._acct_need('transit_' || e.kind, e.id::text, true);
end $fn$;

-- standalone poster for these sources (same rules as acct_post_pending). Not needed once the one-line hook is in _acct_docs.
create or replace function public.b_post_pending(p_dry boolean default false) returns jsonb language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; ln jsonb; orig public.journal_entries; rdate date; posted int := 0; rev int := 0; locked int := 0; waiting int := 0; errors jsonb := '[]';
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._b_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := waiting + 1; continue; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        if not p_dry then perform public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln); end if;
        posted := posted + 1;
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if not p_dry then perform public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1;
      end if;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'posted', posted, 'reversed', rev, 'locked', locked, 'waiting', waiting, 'errors', errors);
end $$;

-- ---------- G5: customer advance held, cash moves vs journal 2300 (read only) ----------
create or replace function public.cust_advance_check() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); adv bigint; rows_ jsonb; tot_j numeric; tot_m numeric;
begin
  if not public._acct_view() or not public._acct_all() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  select account_id into adv from public.acct_mappings where key = 'cust_advance';
  if adv is null then raise exception 'mapping_missing:cust_advance'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('customer_id', x.cid, 'name', x.nm, 'journal', x.j, 'cash_moves', x.m, 'difference', x.j - x.m) order by abs(x.j - x.m) desc), '[]'::jsonb)
    into rows_ from (
      select c.id::text cid, c.name nm, coalesce(j.bal, 0) j, coalesce(m.bal, 0) m
        from public.customers c
        left join (select party_id, sum(credit - debit) bal from public.journal_lines where account_id = adv and party_type = 'customer' group by party_id) j on j.party_id = c.id::text
        left join (select customer_id, sum(case when kind = 'cust_advance' then amount else -amount end) bal from public.cash_moves
                    where status = 'done' and kind like 'cust_advance%' and move_date >= st group by customer_id) m on m.customer_id = c.id
       where coalesce(j.bal, 0) <> 0 or coalesce(m.bal, 0) <> 0) x
    where abs(x.j - x.m) > 0.005;
  select coalesce(sum(credit - debit), 0) into tot_j from public.journal_lines where account_id = adv;
  select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) into tot_m from public.cash_moves where status = 'done' and kind like 'cust_advance%' and move_date >= st;
  return jsonb_build_object('start', st, 'account_total_journal', tot_j, 'account_total_cash_moves', tot_m, 'difference', tot_j - tot_m, 'customers_off', rows_,
    'note', 'Cash moves before the accounting start date are not in the books; a difference equal to such an old advance is expected until an opening balance is posted.');
end $$;

-- ---------- privileges ----------
revoke all on function public._b_events_ro(), public._b_assert_balanced(jsonb), public._b_need_map(text), public._b_check_date(date), public._b_may_decide(),
  public._b_cash_case_trg(), public._b_cash_lines(numeric, text, uuid), public._b_transit_make(uuid), public._b_transit_trg(), public._b_transit_pick(uuid, text, date),
  public._b_transit_lines(text, numeric, text, boolean, text), public._b_docs(date) from public, anon, authenticated;
revoke all on function public.cash_short_backfill(), public.cash_short_list(text, int), public.cash_short_decide(uuid, boolean, text, uuid, boolean), public.cash_short_void(uuid, text),
  public.transit_short_backfill(), public.transit_short_list(text, int), public.transit_short_set_cost(uuid, numeric, text), public.transit_short_claim(uuid, text, date),
  public.transit_short_recover(uuid, numeric, text, text, date, int), public.transit_short_writeoff(uuid, text, date), public.b_post_pending(boolean), public.cust_advance_check() from public, anon;
grant execute on function public.cash_short_backfill(), public.cash_short_list(text, int), public.cash_short_decide(uuid, boolean, text, uuid, boolean), public.cash_short_void(uuid, text),
  public.transit_short_backfill(), public.transit_short_list(text, int), public.transit_short_set_cost(uuid, numeric, text), public.transit_short_claim(uuid, text, date),
  public.transit_short_recover(uuid, numeric, text, text, date, int), public.transit_short_writeoff(uuid, text, date), public.b_post_pending(boolean), public.cust_advance_check() to authenticated;

-- ===================== phase82.sql =====================
-- Phase 82 (bos82, builder C) - G1 + G12 + G8: salary accrual, Monthly Close, partner profit share posting.
-- Additive and paste-twice safe (create or replace / if not exists / on conflict do nothing). Paste AFTER phase79 (and after phase80/81 if they exist).
--
-- WHAT THIS DOES
--   G1  Salary is a MONTHLY ACCRUAL, not a daily expense. When the owner turns the rule payroll_accrual_on ON (default OFF) and gives the first month
--       (payroll_accrual_from), an approved payroll run posts ONE entry per place on the month end:  Dr 5200 salary expense (net pay + advance recovery),
--       Cr 2200 accrued salaries (net pay), Cr 1220 staff advances (advance recovery).  A salary payment then posts  Dr 2200, Cr cash / bKash / bank.
--       Runs of earlier months, and runs that already have a payment posted the old way, stay on today's cash-basis posting (the choice is sticky per run).
--   G12 Salary is not a daily cost. biz_daily (verified in phase72) holds sales and COGS only, so the day sheet never carried salary. c_daily_profit() gives a
--       day profit that leaves salary out (rule salary_in_daily_off, default ON); c_month_close_preview() carries the salary as the monthly cost.
--       Where the salary is PAID FROM is the rule salary_pay_source: by_payment (default, what the payer chose) | cash | mobile (bKash) | bank.
--   G8  Partner profit share posting: an approved partner settlement posts Dr 3400 partner profit share (appropriation), Cr 2600 partner profit payable;
--       a settlement payment posts Dr 2600, Cr cash / bank / wallet. Rule partner_settlement_post_on (default OFF), rule partner_accrue_at:
--       approval (default: liability is booked when approved) | payment (nothing is booked until the money is paid: Dr 3400, Cr cash).
--       c_partner_month_split() is the monthly profit split by the share % written in the agreements (read only, never invents a percent).
--   Monthly Close: c_month_close_preview / c_month_close / c_month_reopen / c_month_closes (append-only log, blockers, snapshot).
--
-- HOW THIS FILE STAYS OUT OF THE SHARED FUNCTIONS
--   Nothing existing is edited. The journal sources are produced by _c_docs(p_start), which returns exactly the columns of _acct_docs. Until the integrator adds the
--   one-line hooks in docs/integration/C.md, c_post_pending() (own poster, same _acct_write) posts the partner sources only; the payroll accrual stays dormant
--   (the hook guard _c_hooks_ok() keeps the basis on cash) so a half-integrated database can never count a salary twice.
--
-- Needs: phase40 (journal), phase42 (payroll), phase44 (partners), phase52 (shadow engine, salary_exp / staff_advance mappings), phase79 (_acct_docs).

do $g$ begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._acct_sid52(text, text)') is null
     or to_regprocedure('public.payroll_approve(bigint)') is null or to_regprocedure('public.partner_settlement_approve(bigint)') is null then
    raise exception 'phase82 needs phases 40, 42, 44, 52 and 79 pasted first';
  end if;
end $g$;

-- ---------- 1. rules (owner decisions, safe defaults) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('payroll_accrual_on', 'people', 'switch', 'false', null, null, null, null,
  'বেতন মাসের খরচ হিসেবে জমা (accrual)', 'বেতন monthly accrual হিসেবে হিসাবে ওঠে', 'Book salary as a monthly accrual',
  'বন্ধ থাকলে আগের মতোই: বেতন দেওয়ার দিনে খরচ। চালু হলে অনুমোদিত বেতন শিট মাসের শেষে খরচ ও বকেয়া বেতন হিসেবে ওঠে, পরে টাকা দিলে বকেয়া কমে। শুরুর মাস নিচের সেটিংয়ে দিতে হবে।',
  'Off = as before: salary is a cost on the day it is paid. On = an approved payroll run is booked at month end as a cost and as accrued salary; paying it later clears the accrual. Give the first month below.', 830),
 ('payroll_accrual_from', 'people', 'text', null, null, null, null, null,
  'কোন মাস থেকে বেতন accrual (তারিখ YYYY-MM-01)', 'Accrual শুরুর মাস (YYYY-MM-01)', 'First month of salary accrual (YYYY-MM-01)',
  'ফাঁকা থাকলে accrual চালু থাকলেও কিছু উঠবে না। আগের মাসগুলো আগের নিয়মেই থাকে।', 'Blank = nothing is accrued even if the switch is on. Earlier months keep the old posting.', 831),
 ('salary_pay_source', 'people', 'choice', '"by_payment"', null, '["by_payment","cash","mobile","bank"]', null, null,
  'বেতন কোথা থেকে দেওয়া হয়: by_payment = যে মাধ্যমে দেওয়া হলো, cash = নগদ, mobile = বিকাশ/ওয়ালেট, bank = ব্যাংক',
  'Salary কোথা থেকে দেওয়া হয়', 'Salary is paid from',
  'by_payment হলে বেতন দেওয়ার সময় বাছা মাধ্যম হিসাবে যাবে। অন্যটি বাছলে সব বেতন সেই হিসাব থেকে বের হবে। এখনও যা পোস্ট হয়নি শুধু তার ওপর খাটবে।',
  'by_payment = the mode picked when paying. The others send every salary payment to that account. Only affects entries not yet posted.', 832),
 ('salary_in_daily_off', 'people', 'switch', 'true', null, null, null, null,
  'দৈনিক লাভে বেতন ধরা হবে না (মাসিক ক্লোজে ধরা হয়)', 'Daily profit-এ salary ধরা হবে না', 'Keep salary out of the daily profit (Monthly Close carries it)',
  'চালু (ডিফল্ট) = দৈনিক লাভে বেতন নেই, মাসের হিসাবে আছে। বন্ধ = দৈনিক লাভের রিপোর্টে মাসের বেতন দিনে ভাগ না করে আলাদা লাইনে দেখায়।',
  'On (default) = daily profit leaves salary out; the month carries it. Off = the daily profit report shows the month salary as a separate line.', 833),
 ('partner_settlement_post_on', 'books', 'switch', 'false', null, null, null, null,
  'অংশীদারের মুনাফার ভাগ খতিয়ানে ওঠে', 'Partner profit share journal-এ উঠবে', 'Post partner profit shares to the books',
  'বন্ধ = এখনকার মতো কিছু উঠে না। চালু হলে অনুমোদিত সেটেলমেন্ট ও তার পেমেন্ট খতিয়ানে ওঠে।',
  'Off = nothing is posted, as today. On = an approved settlement and its payments are posted to the books.', 840),
 ('partner_accrue_at', 'books', 'choice', '"approval"', null, '["approval","payment"]', null, null,
  'অংশীদারের মুনাফা কখন খতিয়ানে: approval = অনুমোদনের দিন (দেনা), payment = টাকা দেওয়ার দিন',
  'Partner profit কখন book হবে: approval | payment', 'Book the partner profit at: approval | payment',
  'মালিক ঠিক করবেন কখন দেওয়া হবে। approval হলে অনুমোদনেই দেনা ওঠে; payment হলে টাকা দিলে তবেই ওঠে। একটি সেটেলমেন্ট একবার উঠলে তার নিয়ম বদলায় না।',
  'The owner decides when the profit is paid. approval = the debt is booked when approved; payment = booked only when paid. A settlement keeps the basis it was first posted with.', 841)
 on conflict (key) do nothing;

-- ---------- 2. chart + mappings ----------
do $seed$
declare c1 text; c2 text;
begin
  if not exists (select 1 from public.coa_accounts where is_system and name_en = 'Partner profit payable') then
    c1 := case when exists (select 1 from public.coa_accounts where code = '2600') then '2610' else '2600' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select c1, 'অংশীদারের মুনাফা দেনা', 'Partner profit payable', 'liability', 'credit', false, true, 106, (select id from public.coa_accounts where code = '2000')
       where not exists (select 1 from public.coa_accounts where code = c1);
  end if;
  if not exists (select 1 from public.coa_accounts where is_system and name_en = 'Partner profit share (appropriation)') then
    c2 := case when exists (select 1 from public.coa_accounts where code = '3400') then '3410' else '3400' end;
    insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort, parent_id)
      select c2, 'অংশীদারের মুনাফার ভাগ (বণ্টন, বিয়োগ)', 'Partner profit share (appropriation)', 'equity', 'debit', false, true, 204, (select id from public.coa_accounts where code = '3000')
       where not exists (select 1 from public.coa_accounts where code = c2);
  end if;
end $seed$;

insert into public.acct_mappings (key, account_id, label_bn, label_en)
select v.k, a.id, v.lb, v.le from (values
  ('salary_accrued', '2200', 'বকেয়া বেতন (মাসের accrual)', 'Accrued salaries (monthly accrual)')
) as v(k, c, lb, le) join public.coa_accounts a on a.code = v.c
on conflict (key) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_payable', a.id, 'অংশীদারের মুনাফা দেনা', 'Partner profit payable'
  from public.coa_accounts a where a.is_system and a.name_en = 'Partner profit payable' order by a.code limit 1
on conflict (key) do nothing;
-- one mapping per settlement line kind, all pointing at the appropriation account by default; the owner may re-point royalty / fee to an expense account
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'partner_ps_' || k.kind, a.id, 'অংশীদার সেটেলমেন্ট: ' || k.kind, 'Partner settlement: ' || k.kind
  from (values ('share'), ('royalty'), ('fee'), ('return'), ('payback'), ('guarantee')) k(kind)
  cross join lateral (select x.id from public.coa_accounts x where x.is_system and x.name_en = 'Partner profit share (appropriation)' order by x.code limit 1) a
on conflict (key) do nothing;

-- ---------- 3. tables ----------
-- Monthly Close trail: append-only. The state of a month is its newest row (close or reopen).
create table if not exists public.c_month_close_log (
  id bigserial primary key,
  month date not null check (extract(day from month) = 1),
  action text not null check (action in ('close', 'reopen')),
  snapshot jsonb,
  note text check (note is null or length(note) <= 500),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists c_month_close_log_m on public.c_month_close_log (month, id);

create or replace function public._c_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the month close trail cannot be changed or deleted'; end $$;
drop trigger if exists c_month_close_log_ro on public.c_month_close_log;
create trigger c_month_close_log_ro before update or delete on public.c_month_close_log for each row execute function public._c_ro();
drop trigger if exists c_month_close_log_ro_t on public.c_month_close_log;
create trigger c_month_close_log_ro_t before truncate on public.c_month_close_log for each statement execute function public._c_ro();
drop trigger if exists audit_c_month_close_log on public.c_month_close_log;
create trigger audit_c_month_close_log after insert on public.c_month_close_log for each row execute function public.log_change('id');

alter table public.c_month_close_log enable row level security;
revoke all on public.c_month_close_log from public, anon, authenticated;
grant select on public.c_month_close_log to authenticated;
drop policy if exists c_month_close_log_sel on public.c_month_close_log;
create policy c_month_close_log_sel on public.c_month_close_log for select to authenticated using (public._acct_manage());

-- ---------- 4. small helpers ----------
create or replace function public._c_me(p_m date) returns date language sql immutable as $$ select (date_trunc('month', p_m) + interval '1 month' - interval '1 day')::date $$;

create or replace function public._c_accrual_from() returns date language plpgsql stable security definer set search_path = public as $$
declare t text := public.rule_txt('payroll_accrual_from');
begin
  if t is null or t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return null; end if;
  return date_trunc('month', t::date)::date;
exception when others then return null;
end $$;

-- are the one-line hooks of docs/integration/C.md installed in _acct_docs? Without them the accrual must stay dormant (no double count).
create or replace function public._c_hooks_ok() returns boolean language sql stable security definer set search_path = public as $$
  select position('_c_docs' in d) > 0 and position('_c_run_skip' in d) > 0
    from (select pg_get_functiondef('public._acct_docs(date)'::regprocedure) d) z
$$;

-- 'accrual' or 'cash' for one payroll run. Sticky: once an accrual (or an accrual-style payment) is posted the run stays accrual; once a cash-style payment is posted it stays cash.
create or replace function public._c_run_basis(p_run bigint) returns text language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs; f date;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then return 'cash'; end if;
  if exists (select 1 from public.journal_entries e where e.source_type = 'payroll_accrual' and e.reverses_id is null and e.source_id like p_run::text || ':%') then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.payroll_payments p on p.run_id = p_run and e.source_type = 'payroll_pay_accr' and e.source_id = p.id::text and e.reverses_id is null) then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.payroll_payments p on p.run_id = p_run and e.source_type = 'payroll_payment'
              and (e.source_id = p.id::text or e.source_id like p.id::text || ':g%') and e.reverses_id is null) then return 'cash'; end if;
  f := public._c_accrual_from();
  if public.rule_on('payroll_accrual_on') and f is not null and r.month >= f and public._c_hooks_ok() then return 'accrual'; end if;
  return 'cash';
end $$;

create or replace function public._c_accrual_covers(p_run bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public._c_run_basis(p_run) = 'accrual' $$;

-- HOOK 1: replaces  public.is_shadow('payroll_runs', p.run_id::text)  in the payroll_payment block of _acct_docs
create or replace function public._c_run_skip(p_run bigint) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_shadow('payroll_runs', p_run::text) or public._c_run_basis(p_run) = 'accrual' $$;

-- HOOK 2: replaces  public._acct_paykey(p.mode)  on the credit line of the payroll_payment block. The account the salary leaves from.
create or replace function public._c_salary_paykey(p_mode text) returns text language sql stable security definer set search_path = public as $$
  select public._acct_paykey(case coalesce(public.rule_txt('salary_pay_source'), 'by_payment') when 'cash' then 'cash' when 'mobile' then 'mobile' when 'bank' then 'bank' else p_mode end) $$;

-- the payment mode the screen should pre-select when salary is paid (null = the payer chooses)
create or replace function public.c_salary_pay_default() returns text language sql stable security definer set search_path = public as $$
  select case coalesce(public.rule_txt('salary_pay_source'), 'by_payment') when 'by_payment' then null else public.rule_txt('salary_pay_source') end $$;

-- 'accrual' (booked when approved) or 'payment' (booked when paid) for one partner settlement. Sticky once something is posted.
create or replace function public._c_settle_basis(p_s bigint) returns text language plpgsql stable security definer set search_path = public as $$
declare pa bigint;
begin
  if exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle' and e.source_id = p_s::text and e.reverses_id is null) then return 'accrual'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  if exists (select 1 from public.journal_entries e join public.partner_settlement_payments pp on e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null
              join public.partner_settlement_lines l on l.id = pp.line_id and l.settlement_id = p_s
             where exists (select 1 from public.journal_lines jl where jl.entry_id = e.id and jl.account_id = pa)) then return 'accrual'; end if;
  if exists (select 1 from public.journal_entries e join public.partner_settlement_payments pp on e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null
              join public.partner_settlement_lines l on l.id = pp.line_id and l.settlement_id = p_s) then return 'payment'; end if;
  return case coalesce(public.rule_txt('partner_accrue_at'), 'approval') when 'payment' then 'payment' else 'accrual' end;
end $$;

-- exact split of a total over percentages, to the paisa, largest remainder first: the parts always add up to the total
create or replace function public._c_split(p_total numeric, p_pcts numeric[]) returns numeric[] language plpgsql immutable as $$
declare n int := coalesce(array_length(p_pcts, 1), 0); cents numeric := round(p_total * 100); base numeric[] := '{}'; rem numeric[] := '{}'; i int; left_ numeric; tot numeric := 0; idx int; best numeric; res numeric[] := '{}';
begin
  if n = 0 then return '{}'; end if;
  if p_total < 0 then raise exception 'negative_total'; end if;
  for i in 1..n loop
    if p_pcts[i] is null or p_pcts[i] < 0 then raise exception 'bad_share'; end if;
    tot := tot + p_pcts[i];
  end loop;
  if abs(tot - 100) > 0.0001 then raise exception 'shares_not_100'; end if;
  left_ := cents;
  for i in 1..n loop
    base[i] := floor(cents * p_pcts[i] / 100); rem[i] := cents * p_pcts[i] / 100 - base[i]; left_ := left_ - base[i];
  end loop;
  while left_ > 0 loop
    idx := 1; best := rem[1];
    for i in 2..n loop if rem[i] > best then idx := i; best := rem[i]; end if; end loop;
    base[idx] := base[idx] + 1; rem[idx] := -1; left_ := left_ - 1;
  end loop;
  for i in 1..n loop res[i] := base[i] / 100; end loop;
  return res;
end $$;

-- the lines of one salary accrual entry (one run, one place)
create or replace function public._c_accrual_lines(p_run bigint, p_loc int) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(j order by o, e), '[]'::jsonb) from (
    select 1 o, l.employee_id::text e, jsonb_build_object('a', 'salary_exp', 'd', l.net + l.advance_recovery, 'pt', 'staff', 'pid', l.employee_id::text) j
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.net + l.advance_recovery > 0
    union all
    select 2, l.employee_id::text, jsonb_build_object('a', 'salary_accrued', 'c', l.net, 'pt', 'staff', 'pid', l.employee_id::text)
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.net > 0
    union all
    select 3, l.employee_id::text, jsonb_build_object('a', 'staff_advance', 'c', l.advance_recovery, 'pt', 'staff', 'pid', l.employee_id::text)
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
     where l.run_id = p_run and l.active and coalesce(l.location_id, r.location_id, 0) = coalesce(p_loc, 0) and l.advance_recovery > 0
  ) y $$;

-- ---------- 5. the journal sources (same columns as _acct_docs) ----------
create or replace function public._c_docs(p_start date) returns table(
  source_type text, source_id text, entry_date date, location_id int, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $fn$
declare p_on boolean := public.rule_on('partner_settlement_post_on');
begin
  -- 1. salary accrual: one entry per (run, place), dated the month end (not later than today). Only runs whose basis is accrual.
  return query
  select 'payroll_accrual'::text, g.sid, g.d, nullif(g.loc, 0), ('Salary accrued ' || to_char(g.month, 'YYYY-MM') || ' PR-' || g.run_id::text)::text, null::text,
         g.status in ('approved', 'paid') and not g.shadow, (g.void_at at time zone 'Asia/Dhaka')::date, null::text,
         case when g.status in ('approved', 'paid') and not g.shadow and g.bad then 'advance_recovery_exceeds_balance' end,
         case when g.status in ('approved', 'paid') and not g.shadow and not g.bad then public._c_accrual_lines(g.run_id, g.loc) end
  from (
    select r.id run_id, r.month, r.status, r.void_at, coalesce(l.location_id, r.location_id, 0) loc,
           r.id::text || ':' || coalesce(l.location_id, r.location_id, 0)::text sid,
           least(public._c_me(r.month), public._acct_today()) d,
           public.is_shadow('payroll_runs', r.id::text) shadow,
           bool_or(l.advance_recovery > coalesce((select sum(x.amount) from public.employee_advance_recoveries x where x.line_id = l.id and x.status = 'active'), 0) + 0.004 and r.status <> 'void') bad
      from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id
     where public._c_run_basis(r.id) = 'accrual'
     group by r.id, r.month, r.status, r.void_at, coalesce(l.location_id, r.location_id, 0)) g
  where g.d >= p_start
    and public._acct_need('payroll_accrual', g.sid, g.status in ('approved', 'paid') and not g.shadow);

  -- 2. salary payments of an accrual run: Dr accrued salaries, Cr cash / bKash / bank (rule salary_pay_source)
  return query
  select 'payroll_pay_accr'::text, p.id::text, p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
         p.status = 'done', (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
         case when p.status = 'done' then jsonb_build_array(
           jsonb_build_object('a', 'salary_accrued', 'd', p.amount, 'pt', 'staff', 'pid', p.employee_id::text),
           jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount)) end
  from public.payroll_payments p
  where p.pay_date >= p_start and public._c_run_basis(p.run_id) = 'accrual' and not public.is_shadow('payroll_runs', p.run_id::text)
    and public._acct_need('payroll_pay_accr', p.id::text, p.status = 'done');

  -- 3. partner settlement approved: Dr profit share (appropriation), Cr partner profit payable. Funded-outside lines never touch the business books.
  return query
  select 'partner_settle'::text, s.id::text, (s.approved_at at time zone 'Asia/Dhaka')::date, v.location_id, ('Partner profit share PS-' || s.id::text)::text, null::text,
         s.status in ('approved', 'paid'), (s.void_at at time zone 'Asia/Dhaka')::date, null::text,
         case when s.status in ('approved', 'paid') and not exists (select 1 from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside) then 'all_funded_outside' end,
         case when s.status in ('approved', 'paid') then (
           select jsonb_agg(j order by o, k) from (
             select 1 o, l.id k, jsonb_build_object('a', 'partner_ps_' || l.kind, 'd', l.amount, 'pt', 'partner', 'pid', l.party_id::text) j
               from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside
             union all
             select 2, l.id, jsonb_build_object('a', 'partner_payable', 'c', l.amount, 'pt', 'partner', 'pid', l.party_id::text)
               from public.partner_settlement_lines l where l.settlement_id = s.id and not l.funded_outside) y) end
  from public.partner_settlements s
  join public.partner_agreements a on a.id = s.agreement_id join public.partner_ventures v on v.id = a.venture_id
  where s.approved_at is not null and (s.approved_at at time zone 'Asia/Dhaka')::date >= p_start
    and (p_on or exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle' and e.source_id = s.id::text and e.reverses_id is null))
    and public._c_settle_basis(s.id) = 'accrual'
    and public._acct_need('partner_settle', s.id::text, s.status in ('approved', 'paid'));

  -- 4. partner settlement payments: Dr payable (accrual basis) or Dr profit share (payment basis), Cr cash / bank / wallet
  return query
  select 'partner_settle_pay'::text, pp.id::text, pp.paid_on, v.location_id, ('Partner payment PS-' || s.id::text)::text, null::text,
         s.status <> 'void', null::date, null::text, null::text,
         jsonb_build_array(
           jsonb_build_object('a', case when public._c_settle_basis(s.id) = 'accrual' then 'partner_payable' else 'partner_ps_' || l.kind end, 'd', pp.amount, 'pt', 'partner', 'pid', l.party_id::text),
           jsonb_build_object('a', public._acct_paykey(pp.mode), 'c', pp.amount))
  from public.partner_settlement_payments pp
  join public.partner_settlement_lines l on l.id = pp.line_id and not l.funded_outside
  join public.partner_settlements s on s.id = l.settlement_id
  join public.partner_agreements a on a.id = s.agreement_id join public.partner_ventures v on v.id = a.venture_id
  where pp.paid_on >= p_start
    and (p_on or exists (select 1 from public.journal_entries e where e.source_type = 'partner_settle_pay' and e.source_id = pp.id::text and e.reverses_id is null))
    and public._acct_need('partner_settle_pay', pp.id::text, s.status <> 'void');
end $fn$;
revoke all on function public._c_docs(date) from public, anon, authenticated;

-- ---------- 6. own poster (same engine as acct_post_pending, only for the sources above) ----------
create or replace function public.c_post_pending(p_dry boolean default false, p_limit int default 500) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st date := public._acct_start(); d record; n int := 0; posted int := 0; rev int := 0; locked int := 0; ln jsonb; orig public.journal_entries; rdate date;
        by_type jsonb := '{}'; waiting jsonb := '{}'; errors jsonb := '[]'; prev jsonb := '[]'; tot_d numeric := 0; tot_c numeric := 0; lim int := least(greatest(coalesce(p_limit, 500), 1), 3000);
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if st is null then return jsonb_build_object('data_needed', true, 'dry', p_dry); end if;
  if not p_dry and not public.rule_on('accounting_on') then raise exception 'accounting_off'; end if;
  if not p_dry then perform pg_advisory_xact_lock(hashtextextended('acct_post', 0)); end if;
  for d in select * from public._c_docs(st) order by 3, 1, 2 loop
    if d.waiting is not null then waiting := jsonb_set(waiting, array[d.waiting], to_jsonb(coalesce((waiting->>d.waiting)::int, 0) + 1)); continue; end if;
    if n >= lim then exit; end if;
    begin
      if d.live then
        if public._acct_locked(d.entry_date) then locked := locked + 1; continue; end if;
        ln := public._acct_resolve(public._acct_merge(d.lines), d.location_id);
        select coalesce(sum((x->>'debit')::numeric), 0), coalesce(sum((x->>'credit')::numeric), 0) into tot_d, tot_c from jsonb_array_elements(ln) x;
        if tot_d <> tot_c or tot_d <= 0 then raise exception 'unbalanced: debit % credit %', tot_d, tot_c; end if;
        if p_dry then
          if jsonb_array_length(prev) < 40 then prev := prev || jsonb_build_object('date', d.entry_date, 'source_type', d.source_type, 'source_id', d.source_id, 'memo', d.memo, 'debit', tot_d, 'credit', tot_c); end if;
        else
          perform public._acct_write(d.entry_date, d.location_id, d.source_type, d.source_id, d.subtype, d.memo, d.flags, ln);
        end if;
        posted := posted + 1;
        by_type := jsonb_set(by_type, array[d.source_type], to_jsonb(coalesce((by_type->>d.source_type)::int, 0) + 1));
      else
        select * into orig from public.journal_entries o where o.source_type = d.source_type and o.source_id = d.source_id and o.reverses_id is null;
        rdate := greatest(coalesce(d.void_date, public._acct_today()), orig.entry_date);
        if public._acct_locked(rdate) then locked := locked + 1; continue; end if;
        if not p_dry then perform public._acct_reverse(orig.id, rdate, 'Reversal: ' || orig.memo); end if;
        rev := rev + 1;
        by_type := jsonb_set(by_type, array[d.source_type || '_reversed'], to_jsonb(coalesce((by_type->>(d.source_type || '_reversed'))::int, 0) + 1));
      end if;
      n := n + 1;
    exception when others then
      errors := errors || jsonb_build_object('source_type', d.source_type, 'source_id', d.source_id, 'error', sqlerrm);
      n := n + 1;
    end;
  end loop;
  return jsonb_build_object('dry', p_dry, 'start', st, 'posted', posted, 'reversed', rev, 'by_type', by_type, 'locked', locked, 'waiting', waiting, 'errors', errors,
    'hooks_installed', public._c_hooks_ok(), 'preview', case when p_dry then prev end);
end $$;

-- ---------- 7. read helpers for the P&L / screens ----------
-- HOOK 3 (P&L): salary expense of the app payroll by month and place (accrual: net pay + advance recovery of an approved or paid run; shadow runs are the form's)
create or replace function public.c_salary_by_month(d1 date, d2 date, locs int[]) returns table(m date, loc int, amt numeric)
language sql stable security definer set search_path = public as $$
  select r.month, coalesce(l.location_id, r.location_id), round(sum(l.net + l.advance_recovery), 2)
    from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id and l.active
   where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)
     and r.month between date_trunc('month', d1)::date and d2 and coalesce(l.location_id, r.location_id) = any (locs)
   group by 1, 2 $$;
revoke all on function public.c_salary_by_month(date, date, int[]) from public, anon, authenticated;

-- day profit with salary left out (rule salary_in_daily_off). Sales are net of discounts as biz_daily gives them; expenses are the approved 10-2 vouchers and quick expenses.
create or replace function public.c_daily_profit(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sal_off boolean := coalesce(public.rule_on('salary_in_daily_off'), true); sal numeric := 0;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('day', b.sale_date, 'location_id', b.location_id, 'revenue', b.revenue, 'cogs', b.cogs, 'costed_revenue', b.costed_rev,
           'profit_before_expenses', case when b.cogs is null then null else round(b.revenue - b.cogs, 2) end) order by b.sale_date, b.location_id), '[]'::jsonb)
    into rows from public.biz_daily(p_from, p_to, p_loc) b;
  if not sal_off and (public.is_owner() or public.has_grant('salary_view')) then
    select coalesce(sum(s.amt), 0) into sal from public.c_salary_by_month(p_from, p_to, (select coalesce(array_agg(l.id), '{}') from public.locations l where (p_loc is null or l.id = p_loc) and public.can_loc(l.id))) s;
  end if;
  return jsonb_build_object('from', p_from, 'to', p_to, 'location_id', p_loc, 'days', rows, 'salary_included_in_days', false,
    'salary_in_daily_off', sal_off, 'month_salary_line', case when sal_off then null else sal end,
    'note', 'Salary is a monthly cost. See Monthly Close for the month salary and the month profit.');
end $$;

-- ---------- 8. Monthly Close ----------
create or replace function public._c_close_state(p_m date) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select case when action = 'close' then 'closed' else 'open' end from public.c_month_close_log where month = p_m order by id desc limit 1), 'open') $$;

create or replace function public.c_month_close_preview(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; me date := public._c_me(p_month); st date := public._acct_start(); runs jsonb; blockers jsonb := '[]'; warns jsonb := '[]';
        pl jsonb; sal_j numeric := 0; sid bigint; unposted int := 0; waiting int := 0; unb bigint; adv_out numeric; nrun int; ndraft int; v_pend jsonb;
        sal_exp numeric := 0; sal_paid numeric := 0; sal_net numeric := 0; hooks boolean := public._c_hooks_ok();
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_month'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'location_id', r.location_id, 'status', r.status, 'shadow', public.is_shadow('payroll_runs', r.id::text),
           'basis', case when public.is_shadow('payroll_runs', r.id::text) then 'form' else public._c_run_basis(r.id) end, 'staff', x.n, 'net', x.net, 'advance_recovery', x.rec, 'salary_expense', x.net + x.rec, 'paid', x.paid, 'unpaid', x.net - x.paid,
           'accrual_posted', exists (select 1 from public.journal_entries e where e.source_type = 'payroll_accrual' and e.reverses_id is null and e.source_id like r.id::text || ':%')) order by r.id), '[]'::jsonb),
         count(*), count(*) filter (where r.status = 'draft'),
         coalesce(sum(x.net + x.rec) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0),
         coalesce(sum(x.paid) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0),
         coalesce(sum(x.net) filter (where r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), 0)
    into runs, nrun, ndraft, sal_exp, sal_paid, sal_net
    from public.payroll_runs r
    cross join lateral (select count(*) n, coalesce(sum(l.net), 0) net, coalesce(sum(l.advance_recovery), 0) rec, coalesce(sum(l.paid_amount), 0) paid
                          from public.payroll_lines l where l.run_id = r.id and l.active) x
   where r.month = m and r.status <> 'void';
  if st is null then blockers := blockers || to_jsonb('accounting_start_missing'::text); end if;
  if me > public._acct_today() then blockers := blockers || to_jsonb('month_not_finished'::text); end if;
  if ndraft > 0 then blockers := blockers || to_jsonb('payroll_run_not_approved'::text); end if;
  if nrun = 0 then warns := warns || to_jsonb('no_payroll_run'::text); end if;
  if public.rule_on('payroll_accrual_on') and not hooks then warns := warns || to_jsonb('accrual_hook_missing'::text); end if;
  if public.rule_on('payroll_accrual_on') and public._c_accrual_from() is null then warns := warns || to_jsonb('accrual_from_missing'::text); end if;
  if public._c_close_state(m) = 'closed' then blockers := blockers || to_jsonb('already_closed'::text); end if;
  if st is not null then
    select count(*) filter (where d.waiting is null), count(*) filter (where d.waiting is not null) into unposted, waiting
      from public._c_docs(st) d where d.entry_date between m and me and d.source_type in ('payroll_accrual', 'payroll_pay_accr');
    if unposted > 0 then blockers := blockers || to_jsonb('payroll_not_posted'::text); end if;
    if waiting > 0 then blockers := blockers || to_jsonb('advance_recovery_exceeds_balance'::text); end if;
    if me >= st then
      pl := public.acct_income_statement(greatest(m, st), me, null);
      select account_id into sid from public.acct_mappings where key = 'salary_exp';
      select coalesce(sum(b.dr - b.cr), 0) into sal_j from public._acct_bal(greatest(m, st), me, null) b where b.account_id = sid;
      -- every counted run of the month is accrual basis, so the books should carry exactly the run total; a difference is a reversal dated in another month or a manual entry on the salary account
      if coalesce((select bool_and(public._c_run_basis(r.id) = 'accrual') from public.payroll_runs r where r.month = m and r.status in ('approved', 'paid') and not public.is_shadow('payroll_runs', r.id::text)), false)
         and abs(sal_j - sal_exp) > 0.004 then warns := warns || to_jsonb('salary_journal_differs_from_runs'::text); end if;
    end if;
  end if;
  select count(*) into unb from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z;
  if unb > 0 then blockers := blockers || to_jsonb('unbalanced_entries'::text); end if;
  select coalesce(sum(a.amount - coalesce((select sum(r.amount) from public.employee_advance_recoveries r where r.advance_id = a.id and r.status = 'active'), 0)), 0)
    into adv_out from public.employee_advances a where a.status = 'active';
  return jsonb_build_object('month', m, 'to', me, 'state', public._c_close_state(m), 'blockers', blockers, 'warnings', warns, 'can_close', jsonb_array_length(blockers) = 0,
    'payroll', jsonb_build_object('runs', runs, 'salary_expense', sal_exp, 'paid', sal_paid, 'net_pay', sal_net, 'unpaid', sal_net - sal_paid, 'salary_in_journal', sal_j,
                                  'pending_postings', unposted, 'accrual_on', public.rule_on('payroll_accrual_on'), 'accrual_from', public._c_accrual_from(), 'hooks_installed', hooks,
                                  'pay_source', coalesce(public.rule_txt('salary_pay_source'), 'by_payment')),
    'advances', jsonb_build_object('outstanding_all_staff', adv_out),
    'profit', case when pl is null then null else jsonb_build_object('income', pl -> 'total_income', 'expense', pl -> 'total_expense', 'net_profit', pl -> 'net_profit',
                'salary_in_journal', sal_j, 'profit_before_salary', (pl ->> 'net_profit')::numeric + sal_j, 'source', 'journal') end);
end $$;

create or replace function public.c_month_close(p_month date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; pv jsonb; sp jsonb; staff text; id_ bigint;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_note is not null and char_length(p_note) > 500 then raise exception 'too_long'; end if;
  perform pg_advisory_xact_lock(hashtextextended('c_month_close', extract(year from m)::int * 100 + extract(month from m)::int));
  pv := public.c_month_close_preview(m);
  if jsonb_array_length(pv -> 'blockers') > 0 then raise exception 'blocked: %', (select string_agg(x, ', ') from jsonb_array_elements_text(pv -> 'blockers') x); end if;
  begin sp := public.c_partner_month_split(m); exception when others then sp := null; end;
  select staff_id into staff from public.profiles where id = auth.uid();
  insert into public.c_month_close_log (month, action, snapshot, note, created_by, created_staff)
    values (m, 'close', pv || jsonb_build_object('partner_split', sp), left(nullif(btrim(p_note), ''), 500), auth.uid(), staff) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'state', 'closed');
end $$;

create or replace function public.c_month_reopen(p_month date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; staff text; id_ bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if public._c_close_state(m) <> 'closed' then raise exception 'not_closed'; end if;
  select staff_id into staff from public.profiles where id = auth.uid();
  insert into public.c_month_close_log (month, action, snapshot, note, created_by, created_staff) values (m, 'reopen', null, left(btrim(p_reason), 500), auth.uid(), staff) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'state', 'open');
end $$;

create or replace function public.c_month_closes(p_months int default 12) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare n int := least(greatest(coalesce(p_months, 12), 1), 60);
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('month', z.month, 'state', case when z.action = 'close' then 'closed' else 'open' end, 'at', z.created_at, 'by', z.created_staff, 'note', z.note,
           'net_profit', z.snapshot #> '{profit,net_profit}', 'salary_expense', z.snapshot #> '{payroll,salary_expense}') order by z.month desc)
    from (select distinct on (month) * from public.c_month_close_log order by month, id desc) z
    where z.month >= (date_trunc('month', public._acct_today()) - make_interval(months => n))::date), '[]'::jsonb);
end $$;

-- ---------- 9. partner profit split + share report ----------
create or replace function public.c_partner_month_split(p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; me date := public._c_me(p_month); st date := public._acct_start(); a record; pc record; out jsonb := '[]'; prof jsonb; base numeric; amts numeric[];
        pcts numeric[]; ids jsonb; parts jsonb; status_ text; missing int; npart int; settled numeric;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if st is null or me < st then return jsonb_build_object('month', m, 'data_needed', true, 'agreements', '[]'::jsonb); end if;
  for a in select ag.id, ag.title, v.id venture_id, v.scope, v.location_id from public.partner_agreements ag join public.partner_ventures v on v.id = ag.venture_id
            where ag.status = 'active' and ag.effective_from <= me and (ag.effective_to is null or ag.effective_to >= m) order by ag.id loop
    prof := public.acct_income_statement(greatest(m, st), me, case when a.scope = 'location' then a.location_id end);
    base := (prof ->> 'net_profit')::numeric;
    select count(*) filter (where ap.share_percent is null), count(*) into missing, npart
      from public.agreement_parties ap where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee');
    parts := '[]'; pcts := '{}'; status_ := 'ok'; amts := null;
    if npart = 0 then status_ := 'no_shares';
    elsif missing > 0 then status_ := 'share_missing';
    else
      select array_agg(ap.share_percent order by ap.id) into pcts from public.agreement_parties ap
       where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee');
      if abs((select sum(x) from unnest(pcts) x) - 100) > 0.0001 then status_ := 'shares_not_100';
      elsif base <= 0 then status_ := case when base < 0 then 'loss_month' else 'no_profit' end;
      else amts := public._c_split(base, pcts); end if;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('party_id', z.party_id, 'name', z.name, 'role', z.role, 'share_percent', z.share_percent,
             'amount', case when amts is not null then amts[z.rn::int] end) order by z.rn), '[]'::jsonb)
      into parts from (select ap.party_id, pp.name, ap.role, ap.share_percent, row_number() over (order by ap.id) rn
                         from public.agreement_parties ap join public.partner_parties pp on pp.id = ap.party_id
                        where ap.agreement_id = a.id and ap.active and ap.role in ('owner', 'partner', 'investor', 'franchisee')) z;
    select coalesce(sum(s.total_distributable), 0) into settled from public.partner_settlements s
     where s.agreement_id = a.id and s.status <> 'void' and s.period_from <= me and s.period_to >= m;
    out := out || jsonb_build_object('agreement_id', a.id, 'title', a.title, 'venture_id', a.venture_id, 'scope', a.scope, 'location_id', case when a.scope = 'location' then a.location_id end,
      'status', status_, 'base_profit', base, 'distributable', case when amts is not null then base end, 'parties', parts, 'settlement_total_in_month', settled);
  end loop;
  return jsonb_build_object('month', m, 'basis', 'journal net profit of the month (salary accrual included)', 'agreements', out,
    'note', 'Preview by the share percent written in each agreement. The contract rules (royalty, fees, tiers) are in the settlement, which is what posts to the books.');
end $$;

-- per-partner share report: settlement lines, paid, outstanding, and what the books carry on the payable account for this partner
create or replace function public.c_partner_share_report(p_party bigint, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pa bigint; rows jsonb; books numeric := 0; acc_out numeric := 0; tot_a numeric := 0; tot_p numeric := 0;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  select coalesce(jsonb_agg(jsonb_build_object('settlement_id', s.id, 'period_from', s.period_from, 'period_to', s.period_to, 'status', s.status, 'kind', l.kind, 'amount', l.amount,
           'paid', l.paid_amount, 'outstanding', l.amount - l.paid_amount, 'funded_outside', l.funded_outside, 'basis', public._c_settle_basis(s.id)) order by s.period_from, s.id, l.id), '[]'::jsonb),
         coalesce(sum(l.amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside), 0),
         coalesce(sum(l.paid_amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside), 0),
         coalesce(sum(l.amount - l.paid_amount) filter (where s.status in ('approved', 'paid') and not l.funded_outside and public._c_settle_basis(s.id) = 'accrual'), 0)
    into rows, tot_a, tot_p, acc_out
    from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
   where l.party_id = p_party and s.status <> 'void' and (p_from is null or s.period_to >= p_from) and (p_to is null or s.period_from <= p_to);
  select coalesce(sum(jl.credit - jl.debit), 0) into books from public.journal_lines jl where jl.account_id = pa and jl.party_type = 'partner' and jl.party_id = p_party::text;
  return jsonb_build_object('party_id', p_party, 'lines', rows, 'approved_total', tot_a, 'paid_total', tot_p, 'outstanding_accrual_basis', acc_out, 'payable_in_books', books);
end $$;

-- every partner: is the payable account equal to the unpaid part of the approved settlements?
create or replace function public.c_partner_payable_check() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pa bigint;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  select account_id into pa from public.acct_mappings where key = 'partner_payable';
  return coalesce((select jsonb_agg(jsonb_build_object('party_id', z.pid, 'books', z.books, 'settlements', z.owed, 'difference', z.books - z.owed) order by z.pid)
    from (select coalesce(b.pid, o.pid) pid, coalesce(b.books, 0) books, coalesce(o.owed, 0) owed
            from (select jl.party_id::bigint pid, sum(jl.credit - jl.debit) books from public.journal_lines jl where jl.account_id = pa and jl.party_type = 'partner' group by 1) b
            full join (select l.party_id pid, sum(l.amount - l.paid_amount) owed from public.partner_settlement_lines l join public.partner_settlements s on s.id = l.settlement_id
                        where s.status in ('approved', 'paid') and not l.funded_outside and public._c_settle_basis(s.id) = 'accrual' group by 1) o on o.pid = b.pid) z), '[]'::jsonb);
end $$;

-- ---------- 10. grants ----------
revoke all on function public._c_docs(date), public._c_run_basis(bigint), public._c_accrual_covers(bigint), public._c_run_skip(bigint), public._c_salary_paykey(text),
  public._c_settle_basis(bigint), public._c_hooks_ok(), public._c_accrual_from(), public._c_accrual_lines(bigint, int), public._c_close_state(date), public._c_split(numeric, numeric[]),
  public._c_me(date) from public, anon, authenticated;
revoke all on function public.c_post_pending(boolean, int), public.c_daily_profit(date, date, int), public.c_month_close_preview(date), public.c_month_close(date, text),
  public.c_month_reopen(date, text), public.c_month_closes(int), public.c_partner_month_split(date), public.c_partner_share_report(bigint, date, date), public.c_partner_payable_check(),
  public.c_salary_pay_default() from public, anon;
grant execute on function public.c_post_pending(boolean, int), public.c_daily_profit(date, date, int), public.c_month_close_preview(date), public.c_month_close(date, text),
  public.c_month_reopen(date, text), public.c_month_closes(int), public.c_partner_month_split(date), public.c_partner_share_report(bigint, date, date), public.c_partner_payable_check(),
  public.c_salary_pay_default() to authenticated;

-- ===================== phase83.sql =====================
-- ============================================================================
-- phase83 (BUILDER D): G9 separate wallets (bKash / Nagad / Rocket / others) and G10 production materials.
-- Additive; paste-twice safe. Own tag bos83. Needs phase40 (books) and phase19/73/74 (recipes). No existing function is replaced.
--
-- G9  - d_wallets: one chart account per wallet (1131 bKash, 1132 Nagad, 1133 Rocket, 1134 Upay; more can be added by d_wallet_add)
--       - a wallet balance per wallet (register balance = opening + wallet sales/collections - wallet supplier payments
--         + wallet moves - wallet fees; journal balance = the wallet's chart account)
--       - d_wallet_fees: the fee the wallet company takes, kept as its OWN expense (account 5815, mapping key wallet_fee)
--       - d_wallet_moves: cash-in / cash-out / bank / wallet-to-wallet transfers
--       - d_wallet_checks: the phone balance typed first (blind, form 10-3 rule), then the book figure and the difference are shown
--       - _d_acct_docs(date): the journal sources of this phase, in the exact column shape of _acct_docs, for the integrator to plug in
--         (a payment that names a wallet is moved from the generic mobile account 1130 to the wallet account by a separate balanced
--          entry; an unknown wallet text stays on 1130, so nothing is lost)
-- G10 - d_material_roles (milk, chhana, packing), d_item_roles (which item is which role), d_product_role_req (which product needs which role)
--       - a recipe or a production run that lacks a required role is warned or refused (setting d_recipe_materials_mode, default off)
--       - d_recipe_cost_gaps: ingredients and packaging without a cost
--       - d_material_unit_cost: cost of a material by the chosen method (setting d_material_cost_method, default average_purchase = today)
--       - d_production_cost_breakdown: what a production run really consumed (milk / chhana / packing / other) + conversion
--       NO item is created here. Item master entries are the owner's (import tooling d_item_roles_import maps existing items by code).
--
-- Owner decisions are SETTINGS (rules), safe defaults:
--   d_wallet_fee_treatment   separate_expense (default) | not_posted
--   d_wallet_negative_mode   refuse (default) | warn
--   d_recipe_materials_mode  off (default) | warn | block
--   d_material_cost_method   average_purchase (default) | last_purchase | fixed_price
-- ============================================================================

do $guard$ begin
  if to_regclass('public.coa_accounts') is null or to_regclass('public.journal_entries') is null then raise exception 'phase83 needs phase40 (books) first'; end if;
  if to_regclass('public.recipes') is null or to_regclass('public.production_runs') is null then raise exception 'phase83 needs the recipe phases (19, 73, 74) first'; end if;
end $guard$;

-- ---------- settings (owner decisions; defaults keep today''s behaviour) ----------
insert into public.rules (key, module, kind, default_value, choices, label_bn, label_mix, label_en, hint_en, sort) values
 ('d_wallet_fee_treatment', 'books', 'choice', '"separate_expense"', '["separate_expense","not_posted"]',
  'ওয়ালেটের ফি: আলাদা খরচ হিসেবে খতিয়ানে / খতিয়ানে নয়', 'Wallet fee: আলাদা expense হিসেবে books এ / books এ না',
  'Wallet fee treatment: booked as its own expense (Dr Wallet fees, Cr the wallet), or kept in the register only',
  'separate_expense = every fee is booked as expense 5815 and lowers the wallet balance. not_posted = fees are listed in the wallet register but not booked. Owner decision (question Q1).', 830),
 ('d_wallet_negative_mode', 'books', 'choice', '"refuse"', '["refuse","warn"]',
  'ওয়ালেট ব্যালান্স ঋণাত্মক হলে: আটকানো / সতর্কতা', 'Wallet balance negative হলে: refuse / warn',
  'When a fee or a move would make a wallet balance negative: refuse it, or warn',
  'refuse = the fee or move is refused (wallet_negative). warn = it is saved and the answer carries a warning.', 831),
 ('d_recipe_materials_mode', 'stock', 'choice', '"off"', '["off","warn","block"]',
  'রেসিপিতে প্রয়োজনীয় কাঁচামাল (দুধ, ছানা, প্যাকিং) না থাকলে: বন্ধ / সতর্কতা / আটকানো', 'Recipe এ required material (দুধ, ছানা, packing) না থাকলে: off / warn / block',
  'When a recipe lacks a material its product requires (milk, chhana, packing): off, warn, or block activation and production',
  'off = today''s behaviour. warn = production is saved with a yellow stock exception. block = recipe activation and production are refused (recipe_missing_material).', 832),
 ('d_material_cost_method', 'stock', 'choice', '"average_purchase"', '["average_purchase","last_purchase","fixed_price"]',
  'কাঁচামালের দাম ধরার পদ্ধতি: গড় কেনা দাম / শেষ কেনা দাম / নির্ধারিত দাম', 'Material cost method: average purchase / last purchase / fixed price',
  'How a material''s unit cost is taken: weighted average of purchases, last purchase bill, or an owner-fixed price',
  'Used by d_material_unit_cost and the cost-gap report. average_purchase = what the stock already uses. fixed_price needs a row in d_material_fixed_price. Owner decision (question Q5).', 833)
on conflict (key) do nothing;

-- ---------- chart: wallet fee expense 5815 + mapping ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
values ('5815', 'ওয়ালেট ফি', 'Wallet fees', 'expense', 'debit', false, true, 409)
on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
select 'wallet_fee', a.id, 'ওয়ালেট ফি (বিকাশ/নগদ/রকেট)', 'Wallet fees (bKash / Nagad / Rocket)' from public.coa_accounts a where a.code = '5815'
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.d_wallets (
  id serial primary key,
  code text not null unique check (code ~ '^[a-z0-9]{2,30}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (length(btrim(name_en)) between 1 and 80),
  aliases text[] not null default '{}',                       -- lower-case spellings found in the free-text wallet column
  coa_account_id bigint not null references public.coa_accounts(id),
  opening_amount numeric not null default 0 check (opening_amount >= 0 and opening_amount <= 1000000000000),
  opening_date date,
  active boolean not null default true,
  sort int not null default 100,
  created_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.d_wallet_fees (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  fee_date date not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  kind text not null default 'other' check (kind in ('cash_out', 'send_money', 'merchant', 'payment', 'other')),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  voided boolean not null default false,
  void_note text, void_by uuid, void_at timestamptz,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists d_wallet_fees_w on public.d_wallet_fees (wallet_id, fee_date);

create table if not exists public.d_wallet_moves (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  move_date date not null,
  direction text not null check (direction in ('in', 'out')),            -- in = money comes INTO wallet_id
  counter text not null check (counter in ('cash', 'bank', 'wallet')),
  counter_wallet_id int references public.d_wallets(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  ref text check (ref is null or length(ref) <= 60),
  note text check (note is null or length(note) <= 200),
  voided boolean not null default false,
  void_note text, void_by uuid, void_at timestamptz,
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  check ((counter = 'wallet') = (counter_wallet_id is not null)),
  check (counter_wallet_id is distinct from wallet_id)
);
create index if not exists d_wallet_moves_w on public.d_wallet_moves (wallet_id, move_date);

create table if not exists public.d_wallet_checks (
  id bigserial primary key,
  wallet_id int not null references public.d_wallets(id),
  location_id int references public.locations(id),
  check_date date not null,
  phone_balance numeric not null check (phone_balance >= 0 and phone_balance <= 1000000000000),   -- typed FIRST by the counter
  book_register numeric not null,                                                                    -- frozen when saved
  book_journal numeric not null,
  diff numeric not null,                                                                             -- phone - book_register, always written, even 0
  status text not null check (status in ('matched', 'difference', 'explained')),
  reason text check (reason is null or length(reason) <= 300),
  reason_by uuid, reason_at timestamptz,
  client_id uuid unique,
  counted_by uuid, counted_staff text, counted_at timestamptz not null default now()
);
create index if not exists d_wallet_checks_w on public.d_wallet_checks (wallet_id, check_date);

-- G10
create table if not exists public.d_material_roles (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null, name_en text not null,
  kind text not null check (kind in ('raw', 'packaging')),
  active boolean not null default true, sort int not null default 100
);
insert into public.d_material_roles (code, name_bn, name_en, kind, sort) values
  ('milk', 'দুধ', 'Milk', 'raw', 10), ('chhana', 'ছানা', 'Chhana (cottage cheese)', 'raw', 20), ('packing', 'প্যাকিং', 'Packing', 'packaging', 30)
on conflict (code) do nothing;

create table if not exists public.d_item_roles (
  item_id uuid not null references public.items(id),
  role_code text not null references public.d_material_roles(code),
  active boolean not null default true,
  created_at timestamptz not null default now(), created_by uuid,
  primary key (item_id, role_code)
);
create table if not exists public.d_product_role_req (
  product_item_id uuid not null references public.items(id),
  role_code text not null references public.d_material_roles(code),
  required boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid,
  primary key (product_item_id, role_code)
);
create table if not exists public.d_material_fixed_price (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  price numeric not null check (price > 0 and price <= 1000000),     -- per base unit of the item
  from_date date not null,
  note text check (note is null or length(note) <= 200),
  created_at timestamptz not null default now(), created_by uuid
);

-- no hard delete, audit, RLS on every table
do $t$ declare t text; begin
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks', 'd_material_roles', 'd_item_roles', 'd_product_role_req', 'd_material_fixed_price'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
  end loop;
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
end $t$;

-- ---------- permission helpers ----------
create or replace function public._d_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._acct_view() or public.can_do('10-3', 'view') or public.can_do('10-3', 'enter'));
$$;
create or replace function public._d_cash_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._acct_manage() or public.can_do('10-3', 'enter')) and (p_loc is null or public.can_loc(p_loc));
$$;

do $p$ declare t text; begin
  foreach t in array array['d_wallets', 'd_wallet_fees', 'd_wallet_moves', 'd_wallet_checks'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public._d_view_ok())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['d_material_roles', 'd_item_roles', 'd_product_role_req'] loop
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active())', t || '_read', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  execute 'create policy d_material_fixed_price_read on public.d_material_fixed_price for select to authenticated using (public._recipe_cost_ok())';
  execute 'grant select on public.d_material_fixed_price to authenticated';
end $p$;

-- ---------- wallet helpers ----------
create or replace function public._d_wallet_of(p_text text) returns int language sql stable security definer set search_path = public as $$
  select w.id from public.d_wallets w
   where nullif(btrim(p_text), '') is not null
     and (lower(btrim(p_text)) in (w.code, lower(w.name_en), lower(w.name_bn)) or lower(btrim(p_text)) = any (w.aliases))
   order by w.active desc, w.id limit 1;
$$;

-- creates the wallet + its chart account + its mapping key (internal, no permission check)
create or replace function public._d_wallet_create(p_code text, p_bn text, p_en text, p_aliases text[], p_opening numeric, p_odate date, p_sort int, p_by uuid) returns int
language plpgsql security definer set search_path = public as $$
declare ac text; aid bigint; wid int; par bigint; n int; al text[] := '{}'; x text;
begin
  if p_code is null or p_code !~ '^[a-z0-9]{2,30}$' then raise exception 'bad_code'; end if;
  select id into wid from public.d_wallets where code = p_code;
  if wid is not null then return wid; end if;
  select min(c) into ac from (select (1130 + g)::text c from generate_series(1, 9) g) z where not exists (select 1 from public.coa_accounts a where a.code = z.c);
  if ac is null then raise exception 'no_free_account_code'; end if;
  select id into par from public.coa_accounts where code = '1100';
  insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, parent_id, is_group, is_system, sort)
    values (ac, left(btrim(p_bn), 120), left(btrim(p_en), 120), 'asset', 'debit', par, false, true, 14) returning id into aid;
  foreach x in array coalesce(p_aliases, '{}') loop
    if nullif(btrim(x), '') is not null then al := al || lower(left(btrim(x), 40)); end if;
  end loop;
  insert into public.d_wallets (code, name_bn, name_en, aliases, coa_account_id, opening_amount, opening_date, sort, created_by)
    values (p_code, btrim(p_bn), btrim(p_en), al, aid, coalesce(p_opening, 0), p_odate, coalesce(p_sort, 100), p_by) returning id into wid;
  insert into public.acct_mappings (key, account_id, label_bn, label_en) values ('d_wallet_' || p_code, aid, btrim(p_bn) || ' ওয়ালেট', btrim(p_en) || ' wallet')
    on conflict (key) do nothing;
  return wid;
end $$;

-- the wallets that exist today in the option list (structure only, zero opening)
do $seed$ begin
  perform public._d_wallet_create('bkash', 'বিকাশ', 'bKash', array['bkash', 'b-kash', 'বিকাশ'], 0, null, 10, null);
  perform public._d_wallet_create('nagad', 'নগদ', 'Nagad', array['nagad', 'নগদ', 'nagad (নগদ)'], 0, null, 20, null);
  perform public._d_wallet_create('rocket', 'রকেট', 'Rocket', array['rocket', 'রকেট'], 0, null, 30, null);
  perform public._d_wallet_create('upay', 'উপায়', 'Upay', array['upay', 'উপায়'], 0, null, 40, null);
end $seed$;

-- every movement of one wallet, signed (+ into the wallet)
create or replace function public._d_wallet_flows(p_wallet int) returns table(d date, loc int, kind text, amt numeric, src text, src_id text)
language sql stable security definer set search_path = public as $$
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, case p.kind when 'collection' then 'collection' else 'sale' end, p.amount, 'sale_payment'::text, p.id::text
    from public.sale_payments p left join public.sales s on s.id = p.sale_id
   where p.mode = 'mobile' and not p.voided and p.kind in ('sale', 'collection') and (p.sale_id is null or s.status = 'done') and public._d_wallet_of(p.wallet) = p_wallet
  union all
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, 'supplier_payment', -p.amount, 'supplier_payment', p.id::text
    from public.supplier_payments p where p.mode = 'mobile' and not p.voided and public._d_wallet_of(p.wallet) = p_wallet
  union all
  select f.fee_date, f.location_id, 'fee', -f.amount, 'd_wallet_fee', f.id::text from public.d_wallet_fees f where f.wallet_id = p_wallet and not f.voided
  union all
  select m.move_date, m.location_id, 'move_' || m.counter, case m.direction when 'in' then m.amount else -m.amount end, 'd_wallet_move', m.id::text
    from public.d_wallet_moves m where m.wallet_id = p_wallet and not m.voided
  union all
  select m.move_date, m.location_id, 'move_wallet', case m.direction when 'in' then -m.amount else m.amount end, 'd_wallet_move', m.id::text
    from public.d_wallet_moves m where m.counter_wallet_id = p_wallet and not m.voided;
$$;

create or replace function public._d_wallet_book(p_wallet int, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select case when w.opening_date is null or w.opening_date <= p_asof then w.opening_amount else 0 end
         + coalesce((select sum(f.amt) from public._d_wallet_flows(w.id) f where f.d <= p_asof and (w.opening_date is null or f.d >= w.opening_date)), 0)
    from public.d_wallets w where w.id = p_wallet;
$$;

create or replace function public._d_wallet_journal(p_wallet int, p_asof date) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   join public.d_wallets w on w.coa_account_id = l.account_id where w.id = p_wallet and e.entry_date <= p_asof;
$$;

-- refuse (or warn about) a negative wallet balance, now and at the date of the entry
create or replace function public._d_neg_check(p_wallet int, p_date date, p_amount numeric) returns boolean
language plpgsql security definer set search_path = public as $$
declare b_at numeric; b_all numeric; warn boolean := false;
begin
  b_at := public._d_wallet_book(p_wallet, p_date); b_all := public._d_wallet_book(p_wallet, date '9999-12-31');
  if coalesce(b_at, 0) - p_amount < 0 or coalesce(b_all, 0) - p_amount < 0 then
    if coalesce(public.rule_txt('d_wallet_negative_mode'), 'refuse') = 'refuse' then
      raise exception 'wallet_negative' using detail = 'balance at date ' || coalesce(b_at, 0)::text || ', balance now ' || coalesce(b_all, 0)::text || ', amount ' || p_amount::text;
    end if;
    warn := true;
  end if;
  return warn;
end $$;

-- ---------- journal sources of this phase (same columns as _acct_docs; the integrator plugs this in) ----------
create or replace function public._d_acct_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
declare treat text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense');
begin
  -- a sale or collection paid into a named wallet: move it from the generic mobile account to the wallet account
  return query
  select 'd_wallet_split'::text, 'sp:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' payment received')::text, null::text,
    (not p.voided and (p.sale_id is null or s.status = 'done')), public._acct_today(), null::text, null::text,
    case when not p.voided and (p.sale_id is null or s.status = 'done') then jsonb_build_array(jsonb_build_object('a', 'd_wallet_' || w.code, 'd', p.amount), jsonb_build_object('a', 'pay_mobile', 'c', p.amount)) end
  from public.sale_payments p left join public.sales s on s.id = p.sale_id join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.kind in ('sale', 'collection') and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and public._acct_need('d_wallet_split', 'sp:' || p.id::text, (not p.voided and (p.sale_id is null or s.status = 'done')));
  -- a supplier payment from a named wallet
  return query
  select 'd_wallet_split'::text, 'sup:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' supplier payment')::text, null::text,
    not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', p.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', p.amount)) end
  from public.supplier_payments p join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('d_wallet_split', 'sup:' || p.id::text, not p.voided);
  -- wallet fees: Dr Wallet fees (5815), Cr the wallet
  return query
  select 'd_wallet_fee'::text, f.id::text, f.fee_date, f.location_id, ('Wallet fee ' || w.code)::text, f.kind, (not f.voided and treat = 'separate_expense'), coalesce((f.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()),
    null::text, null::text,
    case when not f.voided and treat = 'separate_expense' then jsonb_build_array(jsonb_build_object('a', 'wallet_fee', 'd', f.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._acct_need('d_wallet_fee', f.id::text, (not f.voided and treat = 'separate_expense'));
  -- wallet moves: cash / bank / other wallet on the other side
  return query
  select 'd_wallet_move'::text, m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' ' || m.direction || ' ' || m.counter)::text, m.counter, not m.voided,
    coalesce((m.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then 'd_wallet_' || w.code else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'd_wallet_' || w2.code end end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'out' then 'd_wallet_' || w.code else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else 'd_wallet_' || w2.code end end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id left join public.d_wallets w2 on w2.id = m.counter_wallet_id
  where m.move_date >= p_start and public._acct_need('d_wallet_move', m.id::text, not m.voided);
end $$;

-- the wallet fee as an expense for the P&L and the day book (integrator hooks; same shapes as the existing readers)
create or replace function public._d_wallet_fee_rows(p_from date, p_to date, p_locs int[]) returns table(m date, loc int, amount numeric)
language sql stable security definer set search_path = public as $$
  select date_trunc('month', f.fee_date)::date, f.location_id, f.amount from public.d_wallet_fees f
   where not f.voided and f.fee_date between p_from and p_to and (p_locs is null or f.location_id = any (p_locs))
     and coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') = 'separate_expense';
$$;
create or replace function public._d_daybook_rows(p_locs int[], p_from date, p_to date)
returns table(loc integer, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamp with time zone, src text, src_id text, internal boolean, sensitive boolean)
language sql stable security definer set search_path = public as $$
  select f.location_id, f.fee_date, 'out'::text, 'mobile'::text, 'wallet_fee'::text, f.amount, f.ref, nullif(btrim(concat_ws(' · ', w.name_en, f.kind, f.note)), ''), f.created_staff, f.created_at,
         'd_wallet_fee'::text, f.id::text, false, false
    from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
   where not f.voided and f.location_id = any (p_locs) and f.fee_date between p_from and p_to
     and coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense') = 'separate_expense';
$$;

-- ---------- wallet API ----------
create or replace function public.d_wallet_add(p_code text, p_name_bn text, p_name_en text, p_aliases text[] default '{}', p_opening numeric default 0, p_opening_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare wid int; w public.d_wallets;
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) = 0 or p_name_en is null or length(btrim(p_name_en)) = 0 then raise exception 'name_required'; end if;
  if exists (select 1 from public.d_wallets where code = p_code) then raise exception 'code_taken'; end if;
  if coalesce(p_opening, 0) < 0 then raise exception 'bad_amount'; end if;
  wid := public._d_wallet_create(p_code, p_name_bn, p_name_en, p_aliases, coalesce(p_opening, 0), p_opening_date, 100, auth.uid());
  select * into w from public.d_wallets where id = wid;
  return jsonb_build_object('id', w.id, 'code', w.code, 'account_id', w.coa_account_id);
end $$;

create or replace function public.d_wallet_update(p_wallet int, p_name_bn text, p_name_en text, p_aliases text[], p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; al text[] := '{}'; x text;
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  select * into w from public.d_wallets where id = p_wallet for update;
  if not found then raise exception 'not found'; end if;
  foreach x in array coalesce(p_aliases, w.aliases) loop if nullif(btrim(x), '') is not null then al := al || lower(left(btrim(x), 40)); end if; end loop;
  if p_active is false and abs(public._d_wallet_book(w.id, date '9999-12-31')) > 0.004 then raise exception 'wallet_not_empty'; end if;
  update public.d_wallets set name_bn = coalesce(nullif(btrim(p_name_bn), ''), name_bn), name_en = coalesce(nullif(btrim(p_name_en), ''), name_en), aliases = al, active = coalesce(p_active, active) where id = w.id;
  return jsonb_build_object('id', w.id);
end $$;

-- opening of one wallet: typed here (register) - the book journal gets it through the opening screen (G3) on the wallet's account
create or replace function public.d_wallet_opening_set(p_wallet int, p_amount numeric, p_date date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000000000 or p_date is null then raise exception 'bad_amount'; end if;
  if exists (select 1 from public.d_wallet_checks where wallet_id = p_wallet) then raise exception 'opening_locked_after_check'; end if;
  update public.d_wallets set opening_amount = round(p_amount, 2), opening_date = p_date where id = p_wallet;
  if not found then raise exception 'not found'; end if;
  return jsonb_build_object('wallet', p_wallet, 'opening', round(p_amount, 2), 'date', p_date);
end $$;

create or replace function public.d_wallet_fee_add(p_wallet int, p_loc int, p_date date, p_amount numeric, p_kind text default 'other', p_ref text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; f public.d_wallet_fees; sid text; amt numeric := round(p_amount, 2); warn boolean;
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_kind is null or p_kind not in ('cash_out', 'send_money', 'merchant', 'payment', 'other') then raise exception 'bad_kind'; end if;
  perform public.lock_check(p_date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into f from public.d_wallet_fees where client_id = p_client;
    if found then if f.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if; return jsonb_build_object('dup', true, 'id', f.id); end if;
  end if;
  select * into w from public.d_wallets where id = p_wallet for update;
  if not found or not w.active then raise exception 'wallet_not_found'; end if;
  warn := public._d_neg_check(w.id, p_date, amt);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_fees (wallet_id, location_id, fee_date, amount, kind, ref, note, client_id, created_by, created_staff)
    values (w.id, p_loc, p_date, amt, p_kind, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_client, auth.uid(), sid) returning * into f;
  return jsonb_build_object('id', f.id, 'balance_after', public._d_wallet_book(w.id, date '9999-12-31'), 'warning', case when warn then 'wallet_negative' end);
end $$;

create or replace function public.d_wallet_fee_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.d_wallet_fees;
begin
  select * into f from public.d_wallet_fees where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(f.location_id) then raise exception 'not allowed'; end if;
  if f.voided then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(f.fee_date);
  update public.d_wallet_fees set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = f.id;
  return jsonb_build_object('id', f.id, 'voided', true);
end $$;

create or replace function public.d_wallet_move_add(p_wallet int, p_loc int, p_date date, p_direction text, p_counter text, p_counter_wallet int, p_amount numeric,
  p_ref text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallets; w2 public.d_wallets; m public.d_wallet_moves; sid text; amt numeric := round(p_amount, 2); warn boolean := false; warn2 boolean := false;
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() + 1 then raise exception 'bad_date'; end if;
  if p_direction not in ('in', 'out') or p_counter not in ('cash', 'bank', 'wallet') then raise exception 'bad_kind'; end if;
  if (p_counter = 'wallet') <> (p_counter_wallet is not null) then raise exception 'wallet_mismatch'; end if;
  if p_counter_wallet is not null and p_counter_wallet = p_wallet then raise exception 'wallet_mismatch'; end if;
  perform public.lock_check(p_date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into m from public.d_wallet_moves where client_id = p_client;
    if found then if m.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if; return jsonb_build_object('dup', true, 'id', m.id); end if;
  end if;
  select * into w from public.d_wallets where id = p_wallet order by id for update;
  if not found or not w.active then raise exception 'wallet_not_found'; end if;
  if p_counter_wallet is not null then
    select * into w2 from public.d_wallets where id = p_counter_wallet for update;
    if not found or not w2.active then raise exception 'wallet_not_found'; end if;
  end if;
  if p_direction = 'out' then warn := public._d_neg_check(w.id, p_date, amt);
  elsif p_counter_wallet is not null then warn := public._d_neg_check(w2.id, p_date, amt); end if;      -- money into this wallet comes OUT of the other wallet
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_moves (wallet_id, location_id, move_date, direction, counter, counter_wallet_id, amount, ref, note, client_id, created_by, created_staff)
    values (w.id, p_loc, p_date, p_direction, p_counter, p_counter_wallet, amt, left(nullif(btrim(p_ref), ''), 60), left(nullif(btrim(p_note), ''), 200), p_client, auth.uid(), sid) returning * into m;
  return jsonb_build_object('id', m.id, 'balance_after', public._d_wallet_book(w.id, date '9999-12-31'), 'warning', case when warn then 'wallet_negative' end);
end $$;

create or replace function public.d_wallet_move_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m public.d_wallet_moves; src int;
begin
  select * into m from public.d_wallet_moves where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(m.location_id) then raise exception 'not allowed'; end if;
  if m.voided then raise exception 'already_void'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  perform public.lock_check(m.move_date);
  -- voiding an "in" must not leave the wallet negative (the money may already be spent)
  if m.direction = 'in' and coalesce(public.rule_txt('d_wallet_negative_mode'), 'refuse') = 'refuse'
     and public._d_wallet_book(m.wallet_id, date '9999-12-31') - m.amount < 0 then raise exception 'wallet_negative'; end if;
  update public.d_wallet_moves set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid(), void_at = now() where id = m.id;
  return jsonb_build_object('id', m.id, 'voided', true);
end $$;

-- the phone total typed FIRST; the book figure and the difference are returned only after it is saved
create or replace function public.d_wallet_check_save(p_wallet int, p_date date, p_phone numeric, p_loc int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w public.d_wallet_checks; wl public.d_wallets; br numeric; bj numeric; df numeric; sid text; ph numeric := round(p_phone, 2);
begin
  if not public._d_cash_ok(p_loc) then raise exception 'not allowed'; end if;
  if ph is null or ph < 0 or ph > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_date is null or p_date > public._acct_today() then raise exception 'bad_date'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into w from public.d_wallet_checks where client_id = p_client;
    if found then if w.counted_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', w.id, 'book', w.book_register, 'diff', w.diff, 'status', w.status); end if;
  end if;
  select * into wl from public.d_wallets where id = p_wallet;
  if not found then raise exception 'wallet_not_found'; end if;
  br := public._d_wallet_book(wl.id, p_date); bj := public._d_wallet_journal(wl.id, p_date); df := round(ph - br, 2);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.d_wallet_checks (wallet_id, location_id, check_date, phone_balance, book_register, book_journal, diff, status, client_id, counted_by, counted_staff)
    values (wl.id, p_loc, p_date, ph, br, bj, df, case when df = 0 then 'matched' else 'difference' end, p_client, auth.uid(), sid) returning * into w;
  return jsonb_build_object('id', w.id, 'phone', w.phone_balance, 'book', w.book_register, 'book_journal', w.book_journal, 'diff', w.diff, 'status', w.status);
end $$;

-- the reason for a difference: written once
create or replace function public.d_wallet_check_explain(p_check bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.d_wallet_checks;
begin
  select * into c from public.d_wallet_checks where id = p_check for update;
  if not found then raise exception 'not found'; end if;
  if not public._d_cash_ok(c.location_id) then raise exception 'not allowed'; end if;
  if c.status <> 'difference' then raise exception 'nothing_to_explain'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.d_wallet_checks set reason = left(btrim(p_reason), 300), status = 'explained', reason_by = auth.uid(), reason_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'status', 'explained');
end $$;

-- balances of every wallet (register and journal side by side). Owner/accounts: always. A counter sees the book figure of a wallet only after the count of that day is saved.
create or replace function public.d_wallet_balances(p_asof date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_asof, public._acct_today()); full_ boolean;
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  full_ := public._acct_manage() or public.is_owner();
  return coalesce((select jsonb_agg(jsonb_build_object('wallet_id', w.id, 'code', w.code, 'name_bn', w.name_bn, 'name_en', w.name_en, 'account', a.code, 'active', w.active,
      'counted', exists (select 1 from public.d_wallet_checks c where c.wallet_id = w.id and c.check_date = d),
      'book', case when full_ or exists (select 1 from public.d_wallet_checks c where c.wallet_id = w.id and c.check_date = d) then public._d_wallet_book(w.id, d) end,
      'journal', case when full_ then public._d_wallet_journal(w.id, d) end,
      'journal_gap', case when full_ then public._d_wallet_book(w.id, d) - public._d_wallet_journal(w.id, d) end) order by w.sort, w.id)
    from public.d_wallets w join public.coa_accounts a on a.id = w.coa_account_id), '[]'::jsonb);
end $$;

-- the 10-3 reconcile report: phone total versus book, per wallet, for one day
create or replace function public.d_wallet_recon_report(p_date date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._acct_today()); full_ boolean; unas numeric;
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  full_ := public._acct_manage() or public.is_owner();
  select coalesce((select sum(p.amount) from public.sale_payments p left join public.sales s on s.id = p.sale_id
                    where p.mode = 'mobile' and not p.voided and p.kind in ('sale', 'collection') and (p.sale_id is null or s.status = 'done')
                      and (p.paid_at at time zone 'Asia/Dhaka')::date <= d and public._d_wallet_of(p.wallet) is null), 0)
       - coalesce((select sum(p.amount) from public.supplier_payments p where p.mode = 'mobile' and not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date <= d and public._d_wallet_of(p.wallet) is null), 0)
    into unas;
  return jsonb_build_object('date', d, 'unassigned_mobile', unas,
    'wallets', coalesce((select jsonb_agg(jsonb_build_object('wallet_id', w.id, 'code', w.code, 'name_en', w.name_en,
        'check_id', c.id, 'phone', c.phone_balance, 'status', coalesce(c.status, 'not_counted'), 'reason', c.reason,
        'book', case when c.id is not null then c.book_register when full_ then public._d_wallet_book(w.id, d) end,
        'book_journal', case when c.id is not null then c.book_journal when full_ then public._d_wallet_journal(w.id, d) end,
        'diff', c.diff) order by w.sort, w.id)
      from public.d_wallets w
      left join lateral (select * from public.d_wallet_checks k where k.wallet_id = w.id and k.check_date = d and (p_loc is null or k.location_id is not distinct from p_loc) order by k.id desc limit 1) c on true
      where w.active), '[]'::jsonb));
end $$;

create or replace function public.d_wallet_statement(p_wallet int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._d_view_ok() then raise exception 'not allowed'; end if;
  if not (public._acct_manage() or public.is_owner()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('date', f.d, 'kind', f.kind, 'amount', f.amt, 'src', f.src, 'src_id', f.src_id, 'location_id', f.loc) order by f.d, f.src, f.src_id)
    from public._d_wallet_flows(p_wallet) f where f.d between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '9999-12-31')), '[]'::jsonb);
end $$;

-- ---------- G10: materials ----------
create or replace function public.d_item_role_set(p_item uuid, p_role text, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.d_material_roles where code = p_role and active) then raise exception 'role_not_found'; end if;
  insert into public.d_item_roles (item_id, role_code, active, created_by) values (p_item, p_role, coalesce(p_on, true), auth.uid())
    on conflict (item_id, role_code) do update set active = excluded.active;      -- never deleted: switched off
  return jsonb_build_object('item_id', p_item, 'role', p_role, 'on', coalesce(p_on, true));
end $$;

-- optional import tooling: [{"item_code":"...","role":"milk"}]; unknown codes are reported, nothing is created
create or replace function public.d_item_roles_import(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; iid uuid; ok int := 0; bad jsonb := '[]'; n int := 0;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    n := n + 1;
    select id into iid from public.items where code = r->>'item_code';
    if iid is null or not exists (select 1 from public.d_material_roles where code = r->>'role' and active) then bad := bad || jsonb_build_object('row', n, 'item_code', r->>'item_code', 'role', r->>'role');
    else insert into public.d_item_roles (item_id, role_code, created_by) values (iid, r->>'role', auth.uid()) on conflict (item_id, role_code) do update set active = true; ok := ok + 1; end if;
  end loop;
  return jsonb_build_object('mapped', ok, 'rejected', bad);
end $$;

create or replace function public.d_product_req_set(p_product uuid, p_role text, p_required boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_product) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.d_material_roles where code = p_role and active) then raise exception 'role_not_found'; end if;
  insert into public.d_product_role_req (product_item_id, role_code, required, updated_by) values (p_product, p_role, coalesce(p_required, true), auth.uid())
    on conflict (product_item_id, role_code) do update set required = excluded.required, updated_at = now(), updated_by = auth.uid();
  return jsonb_build_object('product', p_product, 'role', p_role, 'required', coalesce(p_required, true));
end $$;

create or replace function public.d_fixed_price_set(p_item uuid, p_price numeric, p_from date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not (public._recipe_mgr() and public._recipe_cost_ok()) then raise exception 'not allowed'; end if;
  if p_price is null or p_price <= 0 or p_price > 1000000 or p_from is null then raise exception 'bad_amount'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  insert into public.d_material_fixed_price (item_id, price, from_date, note, created_by) values (p_item, round(p_price, 6), p_from, left(p_note, 200), auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_);
end $$;

-- roles a recipe is missing (a required role is met by an active ingredient line or an active packaging line of the product)
create or replace function public._d_missing_roles(p_recipe uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(q.role_code order by q.role_code), '{}') from public.recipes r
   join public.d_product_role_req q on q.product_item_id = r.item_id and q.required
   where r.id = p_recipe
     and not exists (select 1 from public.recipe_lines l join public.d_item_roles ir on ir.item_id = l.ingredient_item_id
                      where l.recipe_id = r.id and l.active and ir.active and ir.role_code = q.role_code)
     and not exists (select 1 from public.product_packaging pp join public.d_item_roles ir on ir.item_id = pp.packaging_item_id
                      where pp.product_item_id = r.item_id and pp.active and ir.active and ir.role_code = q.role_code);
$$;

create or replace function public._d_material_cost(p_item uuid, p_loc int) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase'); c numeric;
begin
  if m = 'fixed_price' then
    select price into c from public.d_material_fixed_price where item_id = p_item and from_date <= public._acct_today() order by from_date desc, id desc limit 1;
  elsif m = 'last_purchase' then
    select l.unit_cost_base into c from public.purchase_lines l join public.purchase_bills b on b.id = l.bill_id
     where l.item_id = p_item and b.status = 'posted' and b.kind = 'bill' and coalesce(l.unit_cost_base, 0) > 0 and (p_loc is null or b.location_id = p_loc)
     order by b.bill_date desc, l.id desc limit 1;
  else
    select case when p_loc is null then sum(qty * avg_cost) / nullif(sum(qty) filter (where avg_cost is not null), 0) else max(avg_cost) end into c
      from public.stock_balance where item_id = p_item and (p_loc is null or location_id = p_loc) and (p_loc is not null or qty > 0);
  end if;
  return case when coalesce(c, 0) > 0 then c end;
end $$;

create or replace function public.d_material_unit_cost(p_item uuid, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is null then
    if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  elsif not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return jsonb_build_object('item_id', p_item, 'method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase'), 'unit_cost', public._d_material_cost(p_item, p_loc));
end $$;

create or replace function public.d_recipe_material_check(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare miss text[];
begin
  if not (public._recipe_read() or public._recipe_mgr()) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.recipes where id = p_recipe) then raise exception 'recipe_not_found'; end if;
  miss := public._d_missing_roles(p_recipe);
  return jsonb_build_object('recipe_id', p_recipe, 'ok', coalesce(array_length(miss, 1), 0) = 0, 'missing_roles', to_jsonb(miss),
    'has_lines', exists (select 1 from public.recipe_lines where recipe_id = p_recipe and active), 'mode', coalesce(public.rule_txt('d_recipe_materials_mode'), 'off'));
end $$;

-- ingredients and packaging of active recipes that have no cost under the chosen method
create or replace function public.d_recipe_cost_gaps(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if p_loc is null or not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'kind', z.kind,
      'roles', coalesce((select jsonb_agg(ir.role_code order by ir.role_code) from public.d_item_roles ir where ir.item_id = z.item_id and ir.active), '[]'::jsonb),
      'recipes', z.n, 'method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase')) order by i.code)
    from (select x.item_id, min(x.kind) kind, count(distinct x.recipe_id) n from (
            select l.ingredient_item_id item_id, 'ingredient'::text kind, r.id recipe_id from public.recipe_lines l join public.recipes r on r.id = l.recipe_id where l.active and r.active
            union all
            select pp.packaging_item_id, 'packaging', r.id from public.product_packaging pp join public.recipes r on r.item_id = pp.product_item_id where pp.active and r.active) x
          group by x.item_id) z
    join public.items i on i.id = z.item_id
    where public._d_material_cost(z.item_id, p_loc) is null), '[]'::jsonb);
end $$;

-- what one production run really consumed (from the stock ledger) split by role / type, plus the conversion cost
create or replace function public.d_production_cost_breakdown(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs; mat numeric; lines jsonb; roles jsonb; pack numeric; raw numeric;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'run_not_found'; end if;
  if not (public._cost_ok(r.location_id) and public.can_loc(r.location_id) and public._recipe_read()) then raise exception 'not allowed'; end if;
  select coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 0),
         coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)) filter (where i.item_type = 'packaging'), 0),
         coalesce(sum(-l.qty_delta * coalesce(l.unit_cost, 0)) filter (where i.item_type <> 'packaging'), 0),
         coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'code', i.code, 'type', i.item_type, 'qty', -l.qty_delta, 'unit_cost', l.unit_cost, 'amount', round(-l.qty_delta * coalesce(l.unit_cost, 0), 4)) order by i.code), '[]'::jsonb)
    into mat, pack, raw, lines
    from public.stock_ledger l join public.items i on i.id = l.item_id
   where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out';
  select coalesce(jsonb_object_agg(role_code, amt), '{}'::jsonb) into roles from (
    select ir.role_code, round(sum(-l.qty_delta * coalesce(l.unit_cost, 0)), 4) amt
      from public.stock_ledger l join public.d_item_roles ir on ir.item_id = l.item_id and ir.active
     where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' group by ir.role_code) z;
  return jsonb_build_object('run_id', r.id, 'material_total', round(mat, 4), 'raw_total', round(raw, 4), 'packaging_total', round(pack, 4), 'by_role', roles,
    'conversion', coalesce(r.conversion_cost, 0), 'production_total', round(mat + coalesce(r.conversion_cost, 0), 4),
    'matches_run_record', r.material_cost is null or abs(coalesce(r.material_cost, 0) - round(mat, 4)) < 0.01, 'lines', lines);
end $$;

-- the guards: self-contained triggers (no existing function is edited)
create or replace function public._d_prod_gate() returns trigger language plpgsql security definer set search_path = public as $$
declare mode_ text := coalesce(public.rule_txt('d_recipe_materials_mode'), 'off'); miss text[]; it public.items;
begin
  if mode_ = 'off' then return new; end if;
  miss := public._d_missing_roles(new.recipe_id);
  if coalesce(array_length(miss, 1), 0) = 0 then return new; end if;
  if mode_ = 'block' then raise exception 'recipe_missing_material' using detail = array_to_string(miss, ', '); end if;
  select * into it from public.items where id = new.item_id;
  perform public._stock_exc(new.location_id, 'recipe_material_missing', 'yellow', coalesce(it.name_bn, '') || ': রেসিপিতে প্রয়োজনীয় কাঁচামাল নেই (' || array_to_string(miss, ', ') || ')',
    coalesce(it.name_en, it.name_bn, '') || ': the recipe lacks a required material (' || array_to_string(miss, ', ') || ')', null, (new.made_at at time zone 'Asia/Dhaka')::date, 'STOCK');
  return new;
end $$;
drop trigger if exists d_production_runs_gate on public.production_runs;
create trigger d_production_runs_gate before insert on public.production_runs for each row execute function public._d_prod_gate();

create or replace function public._d_recipe_activate_gate() returns trigger language plpgsql security definer set search_path = public as $$
declare miss text[];
begin
  if coalesce(public.rule_txt('d_recipe_materials_mode'), 'off') <> 'block' then return new; end if;
  miss := public._d_missing_roles(new.id);
  if coalesce(array_length(miss, 1), 0) > 0 then raise exception 'recipe_missing_material' using detail = array_to_string(miss, ', '); end if;
  return new;
end $$;
drop trigger if exists d_recipes_activate_gate on public.recipes;
create trigger d_recipes_activate_gate before update of active on public.recipes for each row when (new.active and not old.active) execute function public._d_recipe_activate_gate();

-- ---------- privileges: internals closed (the two permission helpers stay callable: the row-level-security policies call them) ----------, API open to signed-in users (each function checks the permission itself) ----------
revoke all on function public._d_view_ok(), public._d_cash_ok(int), public._d_wallet_of(text), public._d_wallet_create(text, text, text, text[], numeric, date, int, uuid), public._d_wallet_flows(int),
  public._d_wallet_book(int, date), public._d_wallet_journal(int, date), public._d_neg_check(int, date, numeric), public._d_acct_docs(date), public._d_wallet_fee_rows(date, date, int[]),
  public._d_daybook_rows(int[], date, date), public._d_missing_roles(uuid), public._d_material_cost(uuid, int), public._d_prod_gate(), public._d_recipe_activate_gate() from public, anon, authenticated;
revoke all on function public.d_wallet_add(text, text, text, text[], numeric, date), public.d_wallet_update(int, text, text, text[], boolean), public.d_wallet_opening_set(int, numeric, date),
  public.d_wallet_fee_add(int, int, date, numeric, text, text, text, uuid), public.d_wallet_fee_void(bigint, text),
  public.d_wallet_move_add(int, int, date, text, text, int, numeric, text, text, uuid), public.d_wallet_move_void(bigint, text),
  public.d_wallet_check_save(int, date, numeric, int, uuid), public.d_wallet_check_explain(bigint, text), public.d_wallet_balances(date), public.d_wallet_recon_report(date, int),
  public.d_wallet_statement(int, date, date), public.d_item_role_set(uuid, text, boolean), public.d_item_roles_import(jsonb), public.d_product_req_set(uuid, text, boolean),
  public.d_fixed_price_set(uuid, numeric, date, text), public.d_material_unit_cost(uuid, int), public.d_recipe_material_check(uuid), public.d_recipe_cost_gaps(int),
  public.d_production_cost_breakdown(uuid) from public, anon, authenticated;
grant execute on function public.d_wallet_add(text, text, text, text[], numeric, date), public.d_wallet_update(int, text, text, text[], boolean), public.d_wallet_opening_set(int, numeric, date),
  public.d_wallet_fee_add(int, int, date, numeric, text, text, text, uuid), public.d_wallet_fee_void(bigint, text),
  public.d_wallet_move_add(int, int, date, text, text, int, numeric, text, text, uuid), public.d_wallet_move_void(bigint, text),
  public.d_wallet_check_save(int, date, numeric, int, uuid), public.d_wallet_check_explain(bigint, text), public.d_wallet_balances(date), public.d_wallet_recon_report(date, int),
  public.d_wallet_statement(int, date, date), public.d_item_role_set(uuid, text, boolean), public.d_item_roles_import(jsonb), public.d_product_req_set(uuid, text, boolean),
  public.d_fixed_price_set(uuid, numeric, date, text), public.d_material_unit_cost(uuid, int), public.d_recipe_material_check(uuid), public.d_recipe_cost_gaps(int),
  public.d_production_cost_breakdown(uuid) to authenticated;
grant execute on function public._d_view_ok(), public._d_cash_ok(int) to authenticated;

-- ===================== phase84.sql =====================
-- Phase 84 (bos84) - BALANCE CHECK (G11). READ ONLY. Safe for the live project.
-- Paste after phase79 (or after whatever is latest). Additive, paste-twice safe: create or replace function only. No existing function, table or rule is changed.
-- The guarded test-project reset (G13) is NOT in this file: it lives in supabase/phase84_test_project_only.sql, which belongs in TEST projects only.
--
-- _e_balance_check(p_date, p_loc, p_days)   READ ONLY. One jsonb answer, one red/green status:
--   equation       assets = liabilities + equity + earnings (acct_balance_sheet), RED when the difference is not 0
--   trial_balance  total debit = total credit (acct_trial_balance), RED when not equal
--   journal        every journal entry where sum Dr <> sum Cr, and entries with no lines (list, max 200), RED when any
--   stock_identity per place and item: opening + in - out must equal stock_balance.qty (list, max 200), RED when any
--   cross_checks   AMBER only (they have known timing reasons and never turn the whole status red):
--                  day book vs journal (daybook_vs_journal), stock valuation vs journal (inventory_vs_gl),
--                  documents not yet posted and posting errors (acct_status)
--   status         red | green | data_needed (accounting start date not set). Amber cross-checks are listed in "warnings".
-- Hazard (HANDOVER_5): re-pasting an OLD phase never touches this function; it calls existing reports only.

-- ---------- PART 1: balance check (read only) ----------
create or replace function public._e_balance_check(p_date date default null, p_loc int default null, p_days int default 31)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  st date := public._acct_start(); d date := coalesce(p_date, public._acct_today()); bs jsonb; tb jsonb; days int := least(greatest(coalesce(p_days, 31), 1), 366);
  eq jsonb; trial jsonb; jr jsonb; stk jsonb; dbk jsonb; invg jsonb; sts jsonb; xc jsonb := '{}'::jsonb; warn jsonb := '[]'::jsonb;
  jr_n bigint; jr_list jsonb; st_n bigint; st_list jsonb; red boolean := false; v_all boolean := public._acct_all();
begin
  if not public._acct_view() then raise exception 'not allowed'; end if;
  if p_loc is null and not v_all then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if st is null then return jsonb_build_object('status', 'data_needed', 'why', 'accounting_start_date', 'as_of', d, 'location_id', p_loc); end if;

  -- 1 the equation
  bs := public.acct_balance_sheet(d, p_loc);
  eq := jsonb_build_object('assets', bs -> 'total_assets', 'liabilities', bs -> 'total_liabilities', 'equity', bs -> 'total_equity', 'earnings', bs -> 'retained_earnings',
          'liabilities_equity_earnings', bs -> 'total_liabilities_and_equity', 'difference', bs -> 'difference', 'ok', not coalesce((bs ->> 'unbalanced')::boolean, true));
  -- 2 the trial balance
  tb := public.acct_trial_balance(st, d, p_loc);
  trial := jsonb_build_object('total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'difference', tb -> 'diff', 'ok', coalesce((tb ->> 'balanced')::boolean, false));
  -- 3 journal entries where Dr <> Cr (or no lines at all)
  with z as (
    select e.id, e.entry_date, e.source_type, e.source_id, coalesce(sum(l.debit), 0) dr, coalesce(sum(l.credit), 0) cr, count(l.entry_id) n
      from public.journal_entries e left join public.journal_lines l on l.entry_id = e.id
     where e.entry_date <= d and (p_loc is null or exists (select 1 from public.journal_lines x where x.entry_id = e.id and x.location_id = p_loc))
     group by e.id, e.entry_date, e.source_type, e.source_id
    having coalesce(sum(l.debit), 0) <> coalesce(sum(l.credit), 0) or count(l.entry_id) = 0)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('entry_id', id, 'date', entry_date, 'source_type', source_type, 'source_id', source_id, 'debit', dr, 'credit', cr, 'diff', dr - cr, 'lines', n)
         order by id) filter (where rn <= 200), '[]'::jsonb)
    into jr_n, jr_list from (select z.*, row_number() over (order by z.id) rn from z) z;
  jr := jsonb_build_object('broken', jr_n, 'rows', jr_list, 'truncated', jr_n > 200, 'ok', jr_n = 0);
  -- 4 stock identity per place and item: opening + in - out = closing (stock_balance), as of now
  with l as (
    select item_id, location_id,
           coalesce(sum(qty_delta) filter (where reason = 'opening'), 0) op,
           coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta > 0), 0) qin,
           -coalesce(sum(qty_delta) filter (where reason <> 'opening' and qty_delta < 0), 0) qout
      from public.stock_ledger where p_loc is null or location_id = p_loc group by item_id, location_id),
  j as (
    select coalesce(l.item_id, b.item_id) item_id, coalesce(l.location_id, b.location_id) location_id, coalesce(l.op, 0) op, coalesce(l.qin, 0) qin, coalesce(l.qout, 0) qout,
           coalesce(b.qty, 0) closing, coalesce(l.op, 0) + coalesce(l.qin, 0) - coalesce(l.qout, 0) expected
      from l full join (select * from public.stock_balance where p_loc is null or location_id = p_loc) b on b.item_id = l.item_id and b.location_id = l.location_id),
  br as (select j.*, row_number() over (order by j.location_id, j.item_id) rn from j where j.expected <> j.closing)
  select count(*), coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'location_id', location_id, 'opening', op, 'in', qin, 'out', qout, 'expected_closing', expected,
         'stock_balance', closing, 'diff', closing - expected) order by rn) filter (where rn <= 200), '[]'::jsonb)
    into st_n, st_list from br;
  stk := jsonb_build_object('broken', st_n, 'rows', st_list, 'truncated', st_n > 200, 'ok', st_n = 0, 'as_of', 'now');

  -- 5 cross-checks (amber). Each is skipped, not failed, when the caller may not run the report.
  begin
    dbk := public.daybook_vs_journal(greatest(d - days, st), d, p_loc);
    xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', coalesce(dbk -> 'total' is not null, false), 'kinds_differing', dbk #> '{total,kinds_differing}',
            'diff', dbk #> '{total,diff}', 'rows', coalesce(dbk -> 'rows', '[]'::jsonb), 'from', dbk -> 'from', 'to', dbk -> 'to', 'ok', coalesce((dbk #>> '{total,kinds_differing}')::int, 0) = 0));
    if coalesce((dbk #>> '{total,kinds_differing}')::int, 0) > 0 then warn := warn || to_jsonb('daybook_vs_journal'::text); end if;
  exception when others then xc := xc || jsonb_build_object('daybook_vs_journal', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    invg := public.inventory_vs_gl(d, p_loc);
    xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', coalesce(invg -> 'total' is not null, false), 'gl', invg #> '{total,gl}', 'valuation', invg #> '{total,valuation}',
            'diff', invg #> '{total,diff}', 'unexplained', invg #> '{total,unexplained}', 'ok', coalesce((invg ->> 'agree')::boolean, true)));
    if not coalesce((invg ->> 'agree')::boolean, true) then warn := warn || to_jsonb('inventory_vs_gl'::text); end if;
  exception when others then xc := xc || jsonb_build_object('inventory_vs_gl', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;
  begin
    sts := public.acct_status();
    xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', true, 'pending', sts -> 'pending', 'errors', sts -> 'errors', 'waiting', sts -> 'waiting',
            'ok', coalesce((sts ->> 'pending')::int, 0) = 0 and coalesce((sts ->> 'errors')::int, 0) = 0));
    if coalesce((sts ->> 'pending')::int, 0) > 0 or coalesce((sts ->> 'errors')::int, 0) > 0 then warn := warn || to_jsonb('unposted_sources'::text); end if;
  exception when others then xc := xc || jsonb_build_object('unposted_sources', jsonb_build_object('ran', false, 'skipped', sqlerrm));
  end;

  red := not (eq ->> 'ok')::boolean or not (trial ->> 'ok')::boolean or jr_n > 0 or st_n > 0;
  return jsonb_build_object('status', case when red then 'red' else 'green' end, 'as_of', d, 'location_id', p_loc, 'start', st,
    'equation', eq, 'trial_balance', trial, 'journal', jr, 'stock_identity', stk, 'cross_checks', xc, 'warnings', warn,
    'reds', (select coalesce(jsonb_agg(k), '[]'::jsonb) from (values ('equation', not (eq ->> 'ok')::boolean), ('trial_balance', not (trial ->> 'ok')::boolean),
                ('journal', jr_n > 0), ('stock_identity', st_n > 0)) v(k, bad) where bad),
    'note', 'Read only: nothing is posted or changed. Red = a book rule is broken. Amber (warnings) = two reports disagree and need a look (timing or an unposted document is the usual reason); amber never turns the status red. Stock identity is checked as of now.');
end $$;
revoke all on function public._e_balance_check(date, int, int) from public, anon;
grant execute on function public._e_balance_check(date, int, int) to authenticated;

-- ===================== phase85.sql =====================
-- Phase 85 (bos85) - INTEGRATION of phases 81, 82 and 83 into the shared functions. Paste LAST (after phase84), paste-twice safe.
-- Each function below is re-created from the LATEST definition (taken from the file named next to it) with only the lines tagged bos85 added:
--   _acct_docs   latest = phase79. Adds the three journal-source hooks (_b_docs: cash short + transit short; _c_docs: salary accrual + partner settlement;
--                _d_acct_docs: mobile wallets) and builder C's replacements _c_run_skip (3 places) and _c_salary_paykey (1 place).
--   _p27_pl      latest = phase72. Expense: + wallet fee rows (_d_wallet_fee_rows). Salary: 02-2 forms that are not a shadow + approved/paid app payroll runs
--                (c_salary_by_month). A salary is counted ONCE: a form is either a shadow of an app run (run counted) or not (form counted).
--   _daybook_lines latest = phase50. Adds the wallet fee rows (_d_daybook_rows; type wallet_fee, mode mobile, out).
-- NOTHING IS TURNED ON BY THIS FILE. Payroll accrual stays off until the owner sets payroll_accrual_on AND payroll_accrual_from; cash short posting stays
-- off (cash_short_post_on); partner settlement posting stays off; the recipe material gate stays off; the wallet fee treatment keeps its default.
-- !! Re-pasting an OLDER phase that re-creates one of these three functions (13, 40, 50, 52, 72, 74, 79) removes the hooks: paste this file again afterwards.
-- !! phase84_test_project_only.sql (the guarded test reset) is NOT part of the live paste order; it belongs to test projects only.
-- Paste order: ... 79, 80, 81, 82, 83, 84, 85.

do $g$ begin
  if to_regprocedure('public._acct_docs(date)') is null or to_regprocedure('public._p27_pl(date,date,integer[])') is null
     or to_regprocedure('public._daybook_lines(integer[],integer[],date,date)') is null then
    raise exception 'phase85 needs the shared functions of phases 13, 40, 50, 72 and 79';
  end if;
  if to_regprocedure('public._b_docs(date)') is null then raise exception 'phase85 needs phase81 pasted first'; end if;
  if to_regprocedure('public._c_docs(date)') is null or to_regprocedure('public._c_run_skip(bigint)') is null
     or to_regprocedure('public._c_salary_paykey(text)') is null or to_regprocedure('public.c_salary_by_month(date,date,integer[])') is null then
    raise exception 'phase85 needs phase82 pasted first';
  end if;
  if to_regprocedure('public._d_acct_docs(date)') is null or to_regprocedure('public._d_wallet_fee_rows(date,date,integer[])') is null
     or to_regprocedure('public._d_daybook_rows(integer[],date,date)') is null then
    raise exception 'phase85 needs phase83 pasted first';
  end if;
end $g$;

-- ---------- _acct_docs (phase79 body + bos85 hooks) ----------
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
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from public._acct_inv_split72(array['production'], r.id::text, array['issue_out'], -1) z where z.amt > 0 /* bos72 */
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
      ) y) end
  from public.production_runs r cross join lateral (
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0) nulls /* bos72 */
    from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out') c
  where (r.made_at at time zone 'Asia/Dhaka')::date >= p_start and public._acct_need('production', r.id::text, r.status = 'done');

  -- bos52: payroll payments of the app payroll (a run whose sheet is the record, i.e. the run is a locked shadow, is skipped). Dr salary expense, Cr cash / bank / mobile.
  -- The advance recovery on the pay line is split over the payments pro rata and credited to the staff-advance asset (data: payroll_lines.advance_recovery).
  return query
  select 'payroll_payment'::text, public._acct_sid52('payroll_payment', p.id::text), p.pay_date, p.location_id, ('Salary payment PR-' || p.run_id::text)::text, null::text,
    p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */, (p.void_at at time zone 'Asia/Dhaka')::date, null::text, null::text,
    case when p.status = 'done' and not public._c_run_skip(p.run_id) /* bos85 */ then
      jsonb_build_array(jsonb_build_object('a', 'salary_exp', 'd', p.amount + r.rec, 'pt', 'staff', 'pid', p.employee_id::text),
                        jsonb_build_object('a', public._c_salary_paykey(p.mode), 'c', p.amount /* bos85 */))
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
  -- bos85: sources of phases 81, 82, 83 (cash short / transit short, salary accrual + partner settlement, mobile wallets)
  return query select * from public._b_docs(p_start); /* bos85 */
  return query select * from public._c_docs(p_start); /* bos85 */
  return query select * from public._d_acct_docs(p_start); /* bos85 */
end $function$;

-- ---------- _p27_pl (phase72 body + bos85 wallet fee + salary by month) ----------
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
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
      union all  -- bos85: mobile wallet fees (phase83), zero rows while the fee treatment is not_posted
      select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),
  sa as (  -- bos85: salary = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app payroll runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id,
             sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and not public.is_shadow('entries', e.id::text) /* bos85 */
        and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2
      union all
      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c /* bos85 */) z group by 1, 2),
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

-- ---------- _daybook_lines (phase50 body + bos85 wallet fee rows) ----------
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
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to
  union all  -- bos85: mobile wallet fees (phase83)
  select * from public._d_daybook_rows(p_locs, p_from, p_to) /* bos85 */;
$function$;

-- ===================== phase86.sql =====================
-- Phase 86 (bos86) - FIXES after the independent check of phases 80-85. Paste LAST (after phase85), paste-twice safe. Earlier phase files are not edited.
--   M1  Named approver mode could be bypassed: owner_self_approve_set(true) turned the legacy switch ON again while the mode still read "named".
--       Now ANY change that turns owner_self_approve ON is refused while owner_approval_mode = named (trigger on rules, covers lists, releases, emergencies, item changes).
--   M2  Named mode: the decider must differ from the maker; the owner cannot enter named mode (or set the approver role) while he holds that role himself.
--   M3  _p27_pl: salary is exactly what it was before phase85 (all 02-2 sheets) while payroll_accrual_on is OFF. The app payroll runs (c_salary_by_month)
--       and the "shadow sheet is not counted" rule apply only when the owner has switched payroll accrual ON. Counted once in both cases.
--   M4  Wallet split switch d_wallet_split_on (default OFF). OFF: nothing moves from 1130 to the wallet accounts, wallet fees and moves post on 1130.
--       ON: the split of phase83 applies. Entries already posted are never rewritten (a posted split is still reversed if its payment is voided).
--   m5  Wallet negative block also covers a supplier payment made from a wallet (only a wallet that has an opening date, i.e. one the owner has started to keep).
--   m8  Recovery when the only other holder of the named role is gone: the owner can always switch the mode back to self (owner_approval_mode_set, audit line). Tested.
-- NOTHING IS TURNED ON BY THIS FILE. If phase83, phase85 or phase17/80 are pasted again later, paste this file again afterwards.

do $g$ begin
  if to_regprocedure('public._d_acct_docs(date)') is null or to_regprocedure('public._owner_named_guard()') is null
     or to_regprocedure('public._p27_pl(date,date,integer[])') is null or to_regprocedure('public.c_salary_by_month(date,date,integer[])') is null then
    raise exception 'phase86 needs phases 80, 82, 83 and 85 first';
  end if;
end $g$;

create or replace function public._p86_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- M4 rule ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('d_wallet_split_on', 'books', 'switch', 'false', null, null, null, null,
  'ওয়ালেট আলাদা খতিয়ান-হিসাবে ভাগ (বিকাশ, নগদ...)', 'Wallet আলাদা account এ ভাগ (bKash, Nagad...)', 'Book each mobile wallet on its own account',
  'বন্ধ থাকলে সব মোবাইল টাকা আগের মতোই একটি হিসাবে (1130)। চালু করলে নতুন লেনদেন ওয়ালেটের নিজের হিসাবে যায়; আগে উঠে যাওয়া এন্ট্রি বদলায় না।',
  'Off = all mobile money stays on the one mobile account (1130), as before; wallet fees and moves also use it. On = new sales, collections and supplier payments that name a wallet are moved to that wallet''s own account (1131-1134). Entries already posted are not changed.', 832)
on conflict (key) do nothing;

create or replace function public._d_split_on() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rule_on('d_wallet_split_on'), false) $$;

-- ---------- M1 the legacy switch may not go ON while the named mode is active ----------
create or replace function public._rules_named_switch_guard86() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and new.key = 'owner_self_approve' and coalesce(new.value, new.default_value) = 'true'::jsonb
     and public._owner_mode() = 'named' and coalesce(current_setting('bos80.setting', true), '') <> '1' then
    raise exception 'named_mode_active';
  end if;
  return new;
end $$;
drop trigger if exists rules_named_switch_guard86 on public.rules;
create trigger rules_named_switch_guard86 before update on public.rules for each row execute function public._rules_named_switch_guard86();

-- ---------- M2 named guard: decider <> maker ----------
create or replace function public._owner_named_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare maker uuid; decider uuid; rl text;
begin
  if public._owner_mode() <> 'named' then return new; end if;
  if tg_table_name = 'entries' then
    if not (old.status = 'submitted' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.created_by; decider := new.checked_by;
  else
    if not (old.status = 'pending' and new.status in ('approved', 'rejected')) then return new; end if;
    maker := new.requested_by; decider := new.decided_by;
  end if;
  if not exists (select 1 from public.user_roles where user_id = maker and role_code = 'owner') then return new; end if;
  rl := public.rule_txt('owner_approver_role');
  if rl is null or decider is null or decider = maker /* bos86 */ or not exists (select 1 from public.user_roles where user_id = decider and role_code = rl) then raise exception 'named_approver_only'; end if;
  return new;
end $$;

create or replace function public.owner_approval_mode_set(p_mode text, p_role text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_m text := public._owner_mode(); old_r text := public.rule_txt('owner_approver_role'); rl text := nullif(btrim(coalesce(p_role, '')), '');
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode is null or p_mode not in ('self', 'named', 'logged', 'off') then raise exception 'bad_value'; end if;
  if p_mode = 'named' then
    rl := coalesce(rl, old_r);
    if rl is null then raise exception 'data_needed:owner_approver_role'; end if;
    if not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active' and p.id <> auth.uid()) then raise exception 'no_other_approver'; end if;
  end if;
  -- bos86: the owner who makes the setting must not hold the approver role himself (in any mode, so the role cannot be pointed at a role he holds)
  if rl is not null and exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = rl) then raise exception 'owner_holds_approver_role'; end if;
  perform set_config('bos80.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = 'owner_approval_mode';
  if rl is not null then update public.rules set value = to_jsonb(rl), updated_at = now(), updated_by = auth.uid() where key = 'owner_approver_role'; end if;
  perform public.set_rule('owner_self_approve', to_jsonb(p_mode <> 'named'));
  perform set_config('bos80.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'owner_approval_mode', 'rules', 'owner_approval_mode',
      jsonb_build_object('old', jsonb_build_object('mode', old_m, 'role', old_r), 'new', jsonb_build_object('mode', p_mode, 'role', coalesce(rl, old_r)), 'note', left(p_note, 300)));
  return jsonb_build_object('mode', p_mode, 'approver_role', coalesce(rl, old_r), 'owner_self_approve', p_mode <> 'named');
end $$;

create or replace function public._d_on_mobile86(p_type text, p_id text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.acct_mappings am on am.key = 'pay_mobile' and am.account_id = l.account_id
                  where e.source_type = p_type and e.source_id = p_id and e.reverses_id is null) $$;

-- ---------- M4 the wallet journal source with the switch ----------
create or replace function public._d_acct_docs(p_start date)
returns table(source_type text, source_id text, entry_date date, location_id integer, memo text, subtype text, live boolean, void_date date, flags text, waiting text, lines jsonb)
language plpgsql stable security definer set search_path = public as $$
declare treat text := coalesce(public.rule_txt('d_wallet_fee_treatment'), 'separate_expense'); sp boolean := public._d_split_on();
begin
  -- a sale or collection paid into a named wallet: move it from the generic mobile account to the wallet account (only with the split switch ON, or to reverse one already posted)
  return query
  select 'd_wallet_split'::text, 'sp:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' payment received')::text, null::text,
    (not p.voided and (p.sale_id is null or s.status = 'done')), public._acct_today(), null::text, null::text,
    case when not p.voided and (p.sale_id is null or s.status = 'done') then jsonb_build_array(jsonb_build_object('a', 'd_wallet_' || w.code, 'd', p.amount), jsonb_build_object('a', 'pay_mobile', 'c', p.amount)) end
  from public.sale_payments p left join public.sales s on s.id = p.sale_id join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.kind in ('sale', 'collection') and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'sp:' || p.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'sp:' || p.id::text, (not p.voided and (p.sale_id is null or s.status = 'done')));
  -- a supplier payment from a named wallet
  return query
  select 'd_wallet_split'::text, 'sup:' || p.id::text, (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, ('Wallet ' || w.code || ' supplier payment')::text, null::text,
    not p.voided, public._acct_today(), null::text, null::text,
    case when not p.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', p.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', p.amount)) end
  from public.supplier_payments p join public.d_wallets w on w.id = public._d_wallet_of(p.wallet)
  where p.mode = 'mobile' and p.amount > 0 and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_start
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'sup:' || p.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'sup:' || p.id::text, not p.voided);
  -- wallet fees: Dr Wallet fees (5815), Cr the wallet (its own account with the split ON, else the mobile account 1130)
  return query
  select 'd_wallet_fee'::text, f.id::text, f.fee_date, f.location_id, ('Wallet fee ' || w.code)::text, f.kind, (not f.voided and treat = 'separate_expense'), coalesce((f.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()),
    null::text, null::text,
    case when not f.voided and treat = 'separate_expense' then jsonb_build_array(jsonb_build_object('a', 'wallet_fee', 'd', f.amount),
      jsonb_build_object('a', case when sp then 'd_wallet_' || w.code else 'pay_mobile' end, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._acct_need('d_wallet_fee', f.id::text, (not f.voided and treat = 'separate_expense'));
  -- wallet moves: cash / bank / other wallet on the other side; with the split OFF the wallet side is 1130 and a wallet-to-wallet move has nothing to book
  return query
  select 'd_wallet_move'::text, m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' ' || m.direction || ' ' || m.counter)::text, m.counter, not m.voided,
    coalesce((m.void_at at time zone 'Asia/Dhaka')::date, public._acct_today()), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then case when sp then 'd_wallet_' || w.code else 'pay_mobile' end
                         else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else case when sp then 'd_wallet_' || w2.code else 'pay_mobile' end end end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'out' then case when sp then 'd_wallet_' || w.code else 'pay_mobile' end
                         else case m.counter when 'cash' then 'pay_cash' when 'bank' then 'pay_bank' else case when sp then 'd_wallet_' || w2.code else 'pay_mobile' end end end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id left join public.d_wallets w2 on w2.id = m.counter_wallet_id
  where m.move_date >= p_start
    and (sp or m.counter_wallet_id is null or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_move' and je.source_id = m.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_move', m.id::text, not m.voided);
  -- the split switch turned ON later: a fee or a move out/in with cash or bank that was posted on the mobile account while the switch was OFF is moved to the wallet account
  return query
  select 'd_wallet_split'::text, 'fee:' || f.id::text, f.fee_date, f.location_id, ('Wallet ' || w.code || ' fee moved to the wallet account')::text, null::text, not f.voided,
    public._acct_today(), null::text, null::text,
    case when not f.voided then jsonb_build_array(jsonb_build_object('a', 'pay_mobile', 'd', f.amount), jsonb_build_object('a', 'd_wallet_' || w.code, 'c', f.amount)) end
  from public.d_wallet_fees f join public.d_wallets w on w.id = f.wallet_id
  where f.fee_date >= p_start and public._d_on_mobile86('d_wallet_fee', f.id::text)
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'fee:' || f.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'fee:' || f.id::text, not f.voided);
  return query
  select 'd_wallet_split'::text, 'mv:' || m.id::text, m.move_date, m.location_id, ('Wallet ' || w.code || ' move moved to the wallet account')::text, null::text, not m.voided,
    public._acct_today(), null::text, null::text,
    case when not m.voided then jsonb_build_array(
      jsonb_build_object('a', case m.direction when 'in' then 'd_wallet_' || w.code else 'pay_mobile' end, 'd', m.amount),
      jsonb_build_object('a', case m.direction when 'in' then 'pay_mobile' else 'd_wallet_' || w.code end, 'c', m.amount)) end
  from public.d_wallet_moves m join public.d_wallets w on w.id = m.wallet_id
  where m.move_date >= p_start and m.counter_wallet_id is null and public._d_on_mobile86('d_wallet_move', m.id::text)
    and (sp or exists (select 1 from public.journal_entries je where je.source_type = 'd_wallet_split' and je.source_id = 'mv:' || m.id::text and je.reverses_id is null))
    and public._acct_need('d_wallet_split', 'mv:' || m.id::text, not m.voided);
end $$;

-- ---------- m5 supplier payment from a wallet: the same negative check as fees and moves ----------
create or replace function public._d_supplier_pay_neg86() returns trigger language plpgsql security definer set search_path = public as $$
declare wid int;
begin
  if new.mode = 'mobile' and not coalesce(new.voided, false) and coalesce(new.amount, 0) > 0 then
    wid := public._d_wallet_of(new.wallet);
    if wid is not null and exists (select 1 from public.d_wallets w where w.id = wid and w.opening_date is not null) then
      perform public._d_neg_check(wid, (coalesce(new.paid_at, now()) at time zone 'Asia/Dhaka')::date, new.amount);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists supplier_pay_wallet_neg86 on public.supplier_payments;
create trigger supplier_pay_wallet_neg86 before insert on public.supplier_payments for each row execute function public._d_supplier_pay_neg86();

revoke all on function public._p86_present(), public._d_split_on(), public._rules_named_switch_guard86(), public._d_supplier_pay_neg86(), public._d_on_mobile86(text, text), public._d_acct_docs(date), public.owner_approval_mode_set(text, text, text), public._owner_named_guard() from public, anon, authenticated;
grant execute on function public.owner_approval_mode_set(text, text, text) to authenticated;

-- ---------- M3 _p27_pl: phase85 body, salary of the app payroll runs only when payroll_accrual_on is ON ----------
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
      where q.status = 'done' and q.exp_date between d1 and d2 and q.location_id = any (locs)
      union all  -- bos85: mobile wallet fees (phase83), zero rows while the fee treatment is not_posted
      select w.m, w.loc, w.amount from public._d_wallet_fee_rows(d1, d2, locs) w) u group by 1, 2),
  sa as (  -- bos86 (replaces the bos85 comment here): accrual OFF = all 02-2 forms, exactly as before phase85; accrual ON = the 02-2 forms that are not a shadow of an app payroll run + the approved or paid app runs (each salary once)
    select z.m, z.location_id, sum(z.amt) as amt from (
      select date_trunc('month', e.entry_date)::date as m, e.location_id,
             sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
      from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and (not public.rule_on('payroll_accrual_on') or not public.is_shadow('entries', e.id::text)) /* bos85 bos86 */
        and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2
      union all
      select c.m, c.loc, c.amt from public.c_salary_by_month(d1, d2, locs) c where public.rule_on('payroll_accrual_on') /* bos85 bos86 */) z group by 1, 2),
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

revoke all on function public._p27_pl(date, date, int[]) from public, anon, authenticated;

