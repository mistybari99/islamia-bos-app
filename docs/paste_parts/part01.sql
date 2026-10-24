-- ============================================================================
-- FRESH part 1 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: schema phase2 phase3 phase4 ALL_NEW phase8 phase9 phase10 phase11
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- schema.sql
-- ============================================================
-- BOS tool · Phase 1 schema (Supabase / Postgres)
-- Run once in Supabase: SQL Editor -> paste all -> Run.
-- Safe to re-run? NO for the first run on a fresh project only.
-- ============================================================

-- ---------- Tables ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  staff_id text not null unique,
  full_name text not null default '',
  status text not null default 'pending' check (status in ('pending','active','disabled')),
  lang text not null default 'bn' check (lang in ('bn','mix','en')),
  created_at timestamptz not null default now()
);

create table public.roles (
  code text primary key,
  name_bn text not null, name_mix text, name_en text,
  sort int not null default 0,
  allow_self_approve boolean not null default false,
  active boolean not null default true
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_code text not null references public.roles(code),
  primary key (user_id, role_code)
);

create table public.locations (
  id serial primary key,
  code text not null unique,
  name_bn text not null, name_mix text, name_en text,
  sort int not null default 0,
  is_active boolean not null default true
);

create table public.user_locations (
  user_id uuid not null references public.profiles(id) on delete cascade,
  location_id int not null references public.locations(id),
  primary key (user_id, location_id)
);

create table public.forms (
  code text primary key,
  area text not null,
  name_bn text not null, name_mix text, name_en text,
  version text,
  sort int not null default 0,
  count_first boolean not null default true,   -- count before system figure is shown
  red_block boolean not null default true,     -- red control blocks day close
  enabled boolean not null default true
);

create table public.role_form_perms (
  role_code text not null references public.roles(code) on delete cascade,
  form_code text not null references public.forms(code) on delete cascade,
  can_view boolean not null default false,
  can_enter boolean not null default false,
  can_approve boolean not null default false,
  primary key (role_code, form_code)
);

create sequence public.item_code_seq;
create table public.items (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('I-' || lpad(nextval('public.item_code_seq')::text, 3, '0')),
  name_bn text not null, name_en text, name_mix text,
  category text, category_bn text,
  unit text,
  sell_price numeric(12,2) check (sell_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Cost price lives apart so it can be hidden from roles without the ITEM_COST permission.
create table public.item_costs (
  item_id uuid primary key references public.items(id) on delete cascade,
  cost_price numeric(12,2) check (cost_price >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Every item/price change by anyone but the owner waits here for final approval.
create table public.item_changes (
  id bigserial primary key,
  item_id uuid references public.items(id),     -- null = proposal to create a new item
  patch jsonb not null,
  note text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text
);

create table public.item_price_history (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  sell_price numeric(12,2), cost_price numeric(12,2),   -- one of them per row (the one that changed)
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create table public.settings (
  key text primary key,
  value jsonb,                 -- null means "data needed"
  label_bn text, label_mix text, label_en text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table public.audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid, staff_id text,
  action text not null, table_name text not null, record_id text,
  detail jsonb
);

create table public.corrections (
  id bigserial primary key,
  at timestamptz not null default now(),
  user_id uuid not null, staff_id text,
  form_code text, entry_id text,
  note text not null check (length(btrim(note)) > 0),
  before jsonb, after jsonb
);

create table public.login_failures (
  staff_id text primary key,
  fails int not null default 0,
  locked boolean not null default false,
  last_fail timestamptz not null default now()
);

-- ---------- Helper functions ----------
create or replace function public.is_active() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'active');
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and exists (
    select 1 from public.user_roles where user_id = auth.uid() and role_code = 'owner');
$$;

-- action: 'view' | 'enter' | 'approve'
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (
    public.is_active() and exists (
      select 1 from public.user_roles ur
      join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = auth.uid()
        and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                          when 'approve' then p.can_approve else false end));
$$;

-- ---------- Triggers ----------
-- New auth user -> profile. The very first user becomes the active owner.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select not exists (select 1 from public.profiles) into first_user;
  insert into public.profiles (id, staff_id, full_name, status)
  values (new.id, lower(split_part(new.email, '@', 1)),
          coalesce(new.raw_user_meta_data->>'full_name', ''),
          case when first_user then 'active' else 'pending' end);
  if first_user then
    insert into public.user_roles (user_id, role_code) values (new.id, 'owner');
  end if;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Generic audit trigger. tg_argv[0] = comma separated key columns.
create or replace function public.log_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}';
  cols text[] := string_to_array(tg_argv[0], ','); c text; rid text := ''; src jsonb; sid text;
begin
  if tg_op = 'DELETE' then src := to_jsonb(old); else src := to_jsonb(new); end if;
  foreach c in array cols loop rid := rid || case when rid = '' then '' else ':' end || coalesce(src->>c, ''); end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  if tg_op = 'UPDATE' then
    o := to_jsonb(old); n := to_jsonb(new);
    for k in select jsonb_object_keys(n) loop
      if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
    end loop;
    if newd = '{}'::jsonb then return new; end if;
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'update', tg_table_name, rid, jsonb_build_object('old', oldd, 'new', newd));
    return new;
  elsif tg_op = 'INSERT' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'insert', tg_table_name, rid, jsonb_build_object('new', to_jsonb(new)));
    return new;
  else
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'delete', tg_table_name, rid, jsonb_build_object('old', to_jsonb(old)));
    return old;
  end if;
end $$;

create trigger audit_items after insert or update on public.items for each row execute function public.log_change('id');
create trigger audit_item_costs after insert or update on public.item_costs for each row execute function public.log_change('item_id');
create trigger audit_item_changes after insert or update on public.item_changes for each row execute function public.log_change('id');
create trigger audit_roles after insert or update on public.roles for each row execute function public.log_change('code');
create trigger audit_forms after insert or update on public.forms for each row execute function public.log_change('code');
create trigger audit_locations after insert or update on public.locations for each row execute function public.log_change('id');
create trigger audit_settings after insert or update on public.settings for each row execute function public.log_change('key');
create trigger audit_profiles after update on public.profiles for each row execute function public.log_change('id');
create trigger audit_user_roles after insert or delete on public.user_roles for each row execute function public.log_change('user_id,role_code');
create trigger audit_user_locations after insert or delete on public.user_locations for each row execute function public.log_change('user_id,location_id');
create trigger audit_perms after insert or update or delete on public.role_form_perms for each row execute function public.log_change('role_code,form_code');

-- Items: code never changes; price history; who/when
create or replace function public.items_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.code is distinct from old.code then
    raise exception 'item code cannot be changed';
  end if;
  new.updated_at := now(); new.updated_by := auth.uid();
  return new;
end $$;
create trigger items_before before insert or update on public.items
  for each row execute function public.items_before();

create or replace function public.items_price_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.sell_price is distinct from old.sell_price then
    insert into public.item_price_history (item_id, sell_price, changed_by) values (new.id, new.sell_price, auth.uid());
  end if;
  return new;
end $$;
create trigger items_price_history after insert or update on public.items
  for each row execute function public.items_price_history();

create or replace function public.item_costs_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now(); new.updated_by := auth.uid();
  return new;
end $$;
create trigger item_costs_before before insert or update on public.item_costs
  for each row execute function public.item_costs_history();

create or replace function public.item_costs_history_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.cost_price is distinct from old.cost_price then
    insert into public.item_price_history (item_id, cost_price, changed_by) values (new.item_id, new.cost_price, auth.uid());
  end if;
  return new;
end $$;
create trigger item_costs_history_after after insert or update on public.item_costs
  for each row execute function public.item_costs_history_after();

-- Never leave the business without an active owner
create or replace function public.guard_last_owner() returns trigger
language plpgsql security definer set search_path = public as $$
declare uid uuid; others int;
begin
  if tg_table_name = 'user_roles' then
    if old.role_code <> 'owner' then return old; end if;
    uid := old.user_id;
  else
    if not (old.status = 'active' and new.status <> 'active') then return new; end if;
    uid := old.id;
    if not exists (select 1 from public.user_roles where user_id = uid and role_code = 'owner') then return new; end if;
  end if;
  select count(*) into others from public.user_roles ur join public.profiles p on p.id = ur.user_id
    where ur.role_code = 'owner' and p.status = 'active' and ur.user_id <> uid;
  if others = 0 then raise exception 'at least one active owner is required'; end if;
  if tg_table_name = 'user_roles' then return old; else return new; end if;
end $$;
create trigger guard_owner_roles before delete on public.user_roles for each row execute function public.guard_last_owner();
create trigger guard_owner_profile before update on public.profiles for each row execute function public.guard_last_owner();

-- Audit and login-failure tables are append-only for everyone but the system
-- (no update/delete privileges are granted below)

-- ---------- RPC (called by the app) ----------
create or replace function public.my_context() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.profiles; owner boolean; perms jsonb; roles_ jsonb; locs jsonb;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found then return null; end if;
  owner := p.status = 'active' and exists (select 1 from public.user_roles where user_id = p.id and role_code = 'owner');
  select coalesce(jsonb_agg(role_code), '[]') into roles_ from public.user_roles where user_id = p.id;
  select coalesce(jsonb_agg(location_id), '[]') into locs from public.user_locations where user_id = p.id;
  if p.status <> 'active' then perms := '{}'::jsonb;
  elsif owner then
    select coalesce(jsonb_object_agg(code, jsonb_build_object('view', true, 'enter', true, 'approve', true)), '{}') into perms from public.forms;
  else
    select coalesce(jsonb_object_agg(form_code, jsonb_build_object('view', v, 'enter', e, 'approve', a)), '{}') into perms from (
      select pf.form_code, bool_or(pf.can_view) v, bool_or(pf.can_enter) e, bool_or(pf.can_approve) a
      from public.user_roles ur join public.role_form_perms pf on pf.role_code = ur.role_code
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = p.id group by pf.form_code) x;
  end if;
  return jsonb_build_object('profile', to_jsonb(p), 'is_owner', owner, 'roles', roles_, 'locations', locs, 'perms', perms);
end $$;

create or replace function public.set_my_lang(p_lang text) returns void
language sql security definer set search_path = public as $$
  update public.profiles set lang = p_lang where id = auth.uid() and p_lang in ('bn','mix','en');
$$;

-- Login lock: after max_fails wrong PINs the account is locked until the owner unlocks it.
create or replace function public.login_precheck(p_staff text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('locked', coalesce((select locked from public.login_failures where staff_id = lower(p_staff)), false));
$$;

create or replace function public.login_failed(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare mx int := coalesce((select (value #>> '{}')::int from public.settings where key = 'max_fails'), 5);
begin
  if not exists (select 1 from public.profiles where staff_id = lower(p_staff)) then return; end if;
  insert into public.login_failures (staff_id, fails, locked) values (lower(p_staff), 1, 1 >= mx)
  on conflict (staff_id) do update set fails = public.login_failures.fails + 1,
      locked = public.login_failures.fails + 1 >= mx, last_fail = now();
end $$;

create or replace function public.login_success() returns void
language sql security definer set search_path = public as $$
  delete from public.login_failures where staff_id = (select staff_id from public.profiles where id = auth.uid());
$$;

create or replace function public.unlock_staff(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  delete from public.login_failures where staff_id = lower(p_staff);
end $$;

-- ---------- Item change workflow ----------
-- Apply a patch to items (+ item_costs). Internal helper, not exposed to the app.
create or replace function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid := p_item; cp numeric;
begin
  if iid is null then
    insert into public.items (name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active)
    values (p_patch->>'name_bn', p_patch->>'name_en', p_patch->>'name_mix', p_patch->>'category', p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price','')::numeric, coalesce((p_patch->>'is_active')::boolean, true))
    returning id into iid;
  else
    update public.items set
      name_bn = coalesce(p_patch->>'name_bn', name_bn),
      name_en = case when p_patch ? 'name_en' then p_patch->>'name_en' else name_en end,
      name_mix = case when p_patch ? 'name_mix' then p_patch->>'name_mix' else name_mix end,
      category = case when p_patch ? 'category' then p_patch->>'category' else category end,
      category_bn = case when p_patch ? 'category_bn' then p_patch->>'category_bn' else category_bn end,
      unit = case when p_patch ? 'unit' then p_patch->>'unit' else unit end,
      sell_price = case when p_patch ? 'sell_price' then nullif(p_patch->>'sell_price','')::numeric else sell_price end,
      is_active = case when p_patch ? 'is_active' then (p_patch->>'is_active')::boolean else is_active end
    where id = iid;
  end if;
  if p_patch ? 'cost_price' then
    cp := nullif(p_patch->>'cost_price','')::numeric;
    insert into public.item_costs (item_id, cost_price) values (iid, cp)
      on conflict (item_id) do update set cost_price = excluded.cost_price;
  end if;
  return iid;
end $$;

-- Anyone allowed to enter ITEMS submits here. Owner's change is applied at once;
-- everyone else's waits for an approver.  Changing cost needs ITEM_COST 'enter'.
create or replace function public.submit_item_change(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint;
begin
  if not public.can_do('ITEMS', 'enter') then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if public.is_owner() then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff)
    values (p_item, p_patch, p_note, auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve')) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform public.apply_item_patch(c.item_id, c.patch); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- ---------- Privileges (Data API: nothing is open by default) ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public;
grant usage on schema public to anon, authenticated;

grant select on public.profiles, public.roles, public.user_roles, public.locations, public.user_locations,
  public.forms, public.role_form_perms, public.items, public.item_price_history, public.settings,
  public.audit_log, public.corrections, public.login_failures, public.item_costs, public.item_changes to authenticated;
grant update on public.profiles to authenticated;
grant insert, update, delete on public.user_roles, public.user_locations, public.role_form_perms to authenticated;
grant insert, update on public.roles, public.locations, public.forms, public.settings to authenticated;
grant insert on public.corrections to authenticated;
grant usage on sequence public.audit_log_id_seq, public.corrections_id_seq to authenticated;

grant execute on function public.is_active(), public.is_owner(), public.can_do(text, text),
  public.my_context(), public.set_my_lang(text), public.login_success(), public.unlock_staff(text),
  public.submit_item_change(uuid, jsonb, text), public.decide_item_change(bigint, boolean, text) to authenticated;
grant execute on function public.login_precheck(text), public.login_failed(text) to anon, authenticated;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;
alter table public.locations enable row level security;
alter table public.user_locations enable row level security;
alter table public.forms enable row level security;
alter table public.role_form_perms enable row level security;
alter table public.items enable row level security;
alter table public.item_price_history enable row level security;
alter table public.item_costs enable row level security;
alter table public.item_changes enable row level security;
alter table public.settings enable row level security;
alter table public.audit_log enable row level security;
alter table public.corrections enable row level security;
alter table public.login_failures enable row level security;   -- written only by security-definer functions; the owner may read it

create policy profiles_read on public.profiles for select to authenticated using (id = auth.uid() or public.is_owner());
create policy profiles_owner_update on public.profiles for update to authenticated using (public.is_owner()) with check (public.is_owner());

create policy roles_read on public.roles for select to authenticated using (public.is_active());
create policy roles_owner_write on public.roles for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy user_roles_read on public.user_roles for select to authenticated using (user_id = auth.uid() or public.is_owner());
create policy user_roles_owner_write on public.user_roles for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy locations_read on public.locations for select to authenticated using (public.is_active());
create policy locations_owner_write on public.locations for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy user_locations_read on public.user_locations for select to authenticated using (user_id = auth.uid() or public.is_owner());
create policy user_locations_owner_write on public.user_locations for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy forms_read on public.forms for select to authenticated using (public.is_active());
create policy forms_owner_write on public.forms for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy perms_read on public.role_form_perms for select to authenticated using (public.is_active());
create policy perms_owner_write on public.role_form_perms for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy items_read on public.items for select to authenticated using (public.is_active());
-- items are written only through submit_item_change / decide_item_change (no direct insert/update)

create policy item_costs_read on public.item_costs for select to authenticated using (public.can_do('ITEM_COST', 'view'));
create policy item_changes_read on public.item_changes for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_do('ITEMS', 'approve'));
create policy price_history_read on public.item_price_history for select to authenticated using (public.can_do('ITEM_COST', 'view'));

create policy settings_read on public.settings for select to authenticated using (public.is_active());
create policy settings_owner_write on public.settings for all to authenticated using (public.is_owner()) with check (public.is_owner());

create policy login_failures_owner_read on public.login_failures for select to authenticated using (public.is_owner());

create policy audit_owner_read on public.audit_log for select to authenticated using (public.is_owner());

create policy corrections_read on public.corrections for select to authenticated using (public.is_owner() or user_id = auth.uid());
create policy corrections_insert on public.corrections for insert to authenticated with check (user_id = auth.uid() and public.is_active());

-- ---------- Seed data ----------
insert into public.roles (code, name_bn, name_mix, name_en, sort) values
  ('owner','মালিক','মালিক (Owner)','Owner',1),
  ('management','ব্যবস্থাপনা','ব্যবস্থাপনা (Management)','Management',2),
  ('cash_controller','ক্যাশ নিয়ন্ত্রক','Cash নিয়ন্ত্রক','Cash Controller',3),
  ('showroom_manager','শোরুম ম্যানেজার','Showroom Manager','Showroom Manager',4),
  ('salesperson','বিক্রয়কারী','বিক্রয়কারী (Salesperson)','Salesperson',5),
  ('storekeeper','স্টোরকিপার','Storekeeper','Storekeeper',6),
  ('factory_incharge','কারখানা ইনচার্জ','Factory ইনচার্জ','Factory In-charge',7),
  ('purchasing','ক্রয় (দর সংগ্রহ)','ক্রয় (Purchasing)','Purchasing',8),
  ('party_coordinator','পার্টি ও পাইকারি সমন্বয়ক','Party ও Wholesale সমন্বয়ক','Party & Wholesale Coordinator',9),
  ('carrier','বাহক','বাহক (Carrier)','Carrier',10),
  ('hr','এইচআর ও প্রশাসন','HR ও প্রশাসন','HR & Admin',11);

insert into public.locations (code, name_bn, name_mix, name_en, sort) values
  ('main','ইসলামিয়া মেইন','ইসলামিয়া Main','Islamia Main',1),
  ('branch2','২য় শাখা','২য় Branch','2nd Branch',2),
  ('mishti_bari','মিষ্টি বাড়ি','মিষ্টি বাড়ি','Mishti Bari',3),
  ('al_cakes','আল-কেকিজ','আল-কেকিজ','Al-Cakes',4),
  ('mishti_factory','মিষ্টি কারখানা','মিষ্টি Factory','Sweet Factory',5),
  ('cake_factory','কেক কারখানা','কেক Factory','Cake Factory',6),
  ('godown','গোডাউন','Godown','Godown',7);

insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values
  ('ITEMS','master','আইটেম তালিকা ও দাম','Item তালিকা ও Price','Item List & Prices','',0),
  ('ITEM_COST','master','ক্রয়মূল্য (দেখা ও বদলানো)','Cost Price (দেখা ও বদলানো)','Cost Price (view & change)','',0),
  ('14-1','showroom','দৈনিক শোরুম শিট','দৈনিক Showroom Sheet','Daily Showroom Sheet','v2.18',1),
  ('03-1','stock','ট্রান্সফার চালান','Transfer Challan','Transfer Challan (IBT)','v2.10',2),
  ('20-1','sales','কাস্টমার অর্ডার ফরম','কাস্টমার Order Form','Customer Order Form','v3.6',3),
  ('10-1','cash','ক্যাশ হ্যান্ডওভার স্লিপ','Cash Handover Slip','Cash Handover Slip','v1.6',4),
  ('0-1','settings','লোকেশন সেটিংস শিট','Location Settings Sheet','Location Settings Sheet','v1.16',5),
  ('11-1','staff','শিফট হ্যান্ডওভার রেজিস্টার','Shift Handover Register','Shift Handover Register','v1.5',6),
  ('10-2','cash','ব্যয় ভাউচার','Expense Voucher','Expense Voucher','v1.9',7),
  ('04-1','stock','মালামাল গ্রহণ রসিদ','Goods Receive Receipt','Goods Received Note (GRN)','v1.11',8),
  ('04-2','stock','মালামাল ইস্যু স্লিপ','Goods Issue Slip','Material Issue Slip','v1.9',9),
  ('20-2','sales','ডিসকাউন্ট অনুমোদন স্লিপ','Discount Approval Slip','Discount Approval Slip','v1.7',10),
  ('20-3','sales','রিটার্ন ও অভিযোগ রেজিস্টার','Return ও Complaint Register','Return & Complaint Register','v1.9',11),
  ('05-1','factory','কারখানা দৈনিক শিট','Factory দৈনিক Sheet','Factory Daily Sheet','v1.7',12),
  ('05-2','factory','প্রোডাক্ট স্পেক কার্ড','Product স্পেক Card','Product Spec Card','v2.5',13),
  ('06-1','purchase','পারচেজ রিকুইজিশন','Purchase Requisition','Purchase Requisition (PR)','v1.9',14),
  ('06-2','purchase','কোটেশন তুলনা ও সাপ্লায়ার নির্বাচন','Quotation Comparison ও Supplier Selection','Comparative Statement (CS)','v1.4',15),
  ('06-3','purchase','পারচেজ অর্ডার','Purchase Order','Purchase Order (PO)','v1.8',16),
  ('06-4','purchase','বিল যাচাই ও পেমেন্ট অনুরোধ','বিল Check ও Payment Request','Bill Check & Payment Request','v1.8',17),
  ('06-5','purchase','সাপ্লায়ার লেজার','Supplier Ledger','Supplier Ledger','v1.8',18),
  ('10-3','cash','ডিজিটাল পেমেন্ট রিকনসিলিয়েশন রেজিস্টার','Digital Payment Reconciliation Register','Digital Payment Reconciliation Register','v1.8',19),
  ('10-4','cash','ক্যাশ পজিশন ও পারচেজ বাজেট','Cash Position ও Purchase Budget','Cash Position & Purchase Budget','v1.9',20),
  ('04-3','stock','স্টক কাউন্ট শিট','Stock Count Sheet','Stock Count Sheet','v1.8',21),
  ('10-5','cash','প্রাপ্য ও অ্যাডভান্স রিকনসিলিয়েশন','Receivable ও Advance Reconciliation','Receivable & Advance Reconciliation','v1.10',22),
  ('01-1','owner','সাপ্তাহিক রিভিউ নোট','সাপ্তাহিক Review Note','Weekly Review Note','v1.8',23),
  ('01-2','owner','মাসিক লাভ-ক্ষতি ও KPI শিট','মাসিক P&L ও KPI Sheet','Monthly P&L and KPI Sheet','v1.3',24),
  ('02-1','staff','মাসিক হাজিরা রেজিস্টার','মাসিক Attendance Register','Monthly Attendance Register','v1.8',25),
  ('02-2','staff','মাসিক বেতন শিট','মাসিক Salary Sheet','Monthly Salary Sheet','v1.8',26),
  ('02-3','staff','স্টাফ অ্যাডভান্স রেজিস্টার','Staff Advance Register','Staff Advance Register','v1.6',27),
  ('02-4','staff','নিয়োগপত্র শর্ত ও দায়িত্ব','নিয়োগপত্র শর্ত ও দায়িত্ব','Appointment Letter — Terms & Duties','v1.5',28),
  ('02-5','staff','ছুটির আবেদন ফরম','Leave Application Form','Leave Application','v1.6',29),
  ('02-6','staff','ছাড়পত্র এক্সিট ক্লিয়ারেন্স','ছাড়পত্র এক্সিট Clearance','Exit Clearance Form','v1.8',30),
  ('08-1','assets','মেইনটেন্যান্স অনুরোধ ও রেকর্ড','Maintenance Request ও Record','Maintenance Request & Record','v1.6',31),
  ('20-4','sales','পার্টি ও পাইকারি ইনভয়েস','Party ও Wholesale Invoice','Party & Wholesale Invoice','v1.5',32),
  ('20-5','sales','পার্টি ও পাইকারি লেজার','Party ও Wholesale Ledger','Party & Wholesale Ledger','v1.6',33),
  ('05-3','factory','রেসিপি কার্ড','Recipe Card','Recipe Card','v1.5',34),
  ('05-4','factory','ফলন টেস্ট শিট','Yield Test Sheet','Yield Test Sheet','v1.4',35),
  ('02-7','staff','ডিউটি ও ব্যাকআপ কার্ড','Duty ও Backup Card','Duty & Backup Card','v1.10',36),
  ('02-8','staff','স্কিল চেকলিস্ট','Skill Checklist','Skill Checklist','v1.10',37),
  ('14-2','showroom','জিলাপি কাউন্টার দৈনিক রেকর্ড','জিলাপি Counter দৈনিক Record','Jalebi Counter Daily Record','v1.6',38),
  ('04-4','stock','স্টোর লেজার','Store Ledger','Store Ledger','v1.4',39),
  ('18-1','sales','মার্কেটিং ব্যয় রেজিস্টার','Marketing Expense Register','Marketing Expense Register','v1.4',40),
  ('20-6','sales','অনলাইন ও ডেলিভারি লেজার','Online ও Delivery Ledger','Online & Delivery Ledger','v1.4',41),
  ('05-5','factory','নতুন প্রোডাক্ট সিদ্ধান্ত শিট','নতুন Product Decision Sheet','New Product Decision Sheet','v1.4',42)
;

create temp table seed_items (code text, name_bn text, name_en text, category text, category_bn text, unit text, sell_price numeric, cost_price numeric);
insert into seed_items values
  ('I-001','সাদা মিষ্টি – কেজি','White Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',260,230),
  ('I-002','কালো মিষ্টি – কেজি','Black Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',260,230),
  ('I-003','পোড়াবাড়ি – কেজি','Porabari KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-004','সাদা লম্বা – কেজি','White Lomba KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-005','কালো লম্বা – কেজি','Black Lomba KG','sweet_kg','মিষ্টি (কেজি)','kg',350,320),
  ('I-006','স্পঞ্জ মিষ্টি – কেজি','Sponge Misti KG','sweet_kg','মিষ্টি (কেজি)','kg',450,400),
  ('I-007','লাল লাড্ডু – কেজি','Red Laddu KG','sweet_kg','মিষ্টি (কেজি)','kg',300,280),
  ('I-008','সাদা লাড্ডু – কেজি','White Laddu KG','sweet_kg','মিষ্টি (কেজি)','kg',350,330),
  ('I-009','সাদা ক্রিমজাম – কেজি','White Creamjam KG','sweet_kg','মিষ্টি (কেজি)','kg',400,370),
  ('I-010','কালো ক্রিমজাম – কেজি','Black Creamjam KG','sweet_kg','মিষ্টি (কেজি)','kg',400,370),
  ('I-011','সরপুরিয়া – কেজি','Sarpuria KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-012','গুড়ের সন্দেশ – কেজি','Gurer Sandesh KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-013','কাজু সন্দেশ – কেজি','Cashew Sandesh KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-014','ইলিশপেটি – কেজি','Ilishpeti KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-015','ক্ষির আইটেম – কেজি','Kheer Item KG','sweet_kg','মিষ্টি (কেজি)','kg',500,470),
  ('I-016','রসমালাই - কেজি','Rasmalai KG','sweet_kg','মিষ্টি (কেজি)','kg',450,420),
  ('I-017','লাল দই বড় মালসা','Red Doi Large Malsha','doi','দই','pc',160,140),
  ('I-018','লাল দই মাঝারি মালসা','Red Doi Medium Malsha','doi','দই','pc',80,80),
  ('I-019','সাদা দই বড় মালসা','White Doi Large Malsha','doi','দই','pc',160,140),
  ('I-020','সাদা দই মাঝারি মালসা','White Doi Medium Malsha','doi','দই','pc',80,75),
  ('I-021','স্বরা দই (বাংলা)','Shara Doi (Bangla)','doi','দই','pc',180,170),
  ('I-022','স্বরা দই (বাটি)','Shara Doi (Bowl)','doi','দই','pc',200,180),
  ('I-023','স্বরা দই (প্লেট)','Shara Doi (Plate)','doi','দই','pc',250,230),
  ('I-024','কাপ দই','Cup Doi','doi','দই','pc',30,25),
  ('I-025','টক দই','Sour Doi','doi','দই','pc',120,140),
  ('I-026','মালাইকারি – পিস','Malaikari Piece','sweet_pc','মিষ্টি (পিস)','pc',50,45),
  ('I-027','রসগোল্লা ছোট – পিস','Rasgolla Small Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18),
  ('I-028','রসগোল্লা বড় – পিস','Rasgolla Large Piece','sweet_pc','মিষ্টি (পিস)','pc',30,25),
  ('I-029','সাদা মিষ্টি – পিস','White Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',15,12.11),
  ('I-030','কালো মিষ্টি – পিস','Black Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',15,12.11),
  ('I-031','পোড়াবাড়ি – পিস','Porabari Piece','sweet_pc','মিষ্টি (পিস)','pc',25,21.33),
  ('I-032','সাদা লম্বা – পিস','White Lomba Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18.82),
  ('I-033','কালো লম্বা – পিস','Black Lomba Piece','sweet_pc','মিষ্টি (পিস)','pc',20,18.82),
  ('I-034','স্পঞ্জ মিষ্টি – পিস','Sponge Misti Piece','sweet_pc','মিষ্টি (পিস)','pc',25,19.05),
  ('I-035','লাল লাড্ডু – পিস','Red Laddu Piece','sweet_pc','মিষ্টি (পিস)','pc',15,13.33),
  ('I-036','সাদা লাড্ডু – পিস','White Laddu Piece','sweet_pc','মিষ্টি (পিস)','pc',20,15.71),
  ('I-037','সাদা ক্রিমজাম – পিস','White Creamjam Piece','sweet_pc','মিষ্টি (পিস)','pc',30,20.56),
  ('I-038','কালো ক্রিমজাম – পিস','Black Creamjam Piece','sweet_pc','মিষ্টি (পিস)','pc',30,20.56),
  ('I-039','সরপুরিয়া – পিস','Sarpuria Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.11),
  ('I-040','গুড়ের সন্দেশ – পিস','Gurer Sandesh Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.11),
  ('I-041','কাজু সন্দেশ – পিস','Cashew Sandesh Piece','sweet_pc','মিষ্টি (পিস)','pc',30,22.38),
  ('I-042','ইলিশপেটি – পিস','Ilishpeti Piece','sweet_pc','মিষ্টি (পিস)','pc',30,18.8),
  ('I-043','ক্ষির আইটেম – পিস','Kheer Item Piece','sweet_pc','মিষ্টি (পিস)','pc',25,18.8),
  ('I-044','ভ্যানিলা রেগুলার ১ পাউন্ড','Vanilla Regular 1 Pound','cake_lb','কেক (পাউন্ড)','lb',300,200),
  ('I-045','চকলেট রেগুলার ১ পাউন্ড','Chocolate Regular 1 Pound','cake_lb','কেক (পাউন্ড)','lb',350,200),
  ('I-046','ভ্যানিলা স্পেশাল ১ পাউন্ড','Vanilla Special 1 Pound','cake_lb','কেক (পাউন্ড)','lb',400,200),
  ('I-047','চকলেট স্পেশাল ১ পাউন্ড','Chocolate Special 1 Pound','cake_lb','কেক (পাউন্ড)','lb',450,200),
  ('I-048','ভ্যানিলা রেগুলার ২ পাউন্ড','Vanilla Regular 2 Pound','cake_lb','কেক (পাউন্ড)','lb',600,400),
  ('I-049','চকলেট রেগুলার ২ পাউন্ড','Chocolate Regular 2 Pound','cake_lb','কেক (পাউন্ড)','lb',700,400),
  ('I-050','ভ্যানিলা স্পেশাল ২ পাউন্ড','Vanilla Special 2 Pound','cake_lb','কেক (পাউন্ড)','lb',800,400),
  ('I-051','চকলেট স্পেশাল ২ পাউন্ড','Chocolate Special 2 Pound','cake_lb','কেক (পাউন্ড)','lb',900,400),
  ('I-052','ভ্যানিলা হাফ পাউন্ড','Vanilla Half Pound','cake_lb','কেক (পাউন্ড)','lb',200,120),
  ('I-053','চকলেট হাফ পাউন্ড','Chocolate Half Pound','cake_lb','কেক (পাউন্ড)','lb',200,120),
  ('I-054','ভ্যানিলা স্লাইস (৮ পিস)','Vanilla Slice (৮ pcs)','cake_pc','কেক (পিস)','pc',70,50),
  ('I-055','চকলেট স্লাইস ( ৮ পিস )','Chocolate Slice (৮ Piece )','cake_pc','কেক (পিস)','pc',80,50),
  ('I-056','অরেঞ্জ স্লাইস( ৮ পিস)','Orange স্লাইস(৮ pcs)','cake_pc','কেক (পিস)','pc',80,50),
  ('I-057','জার কেক','Jar Cake','cake_pc','কেক (পিস)','pc',100,80)
;
insert into public.items (code, name_bn, name_en, category, category_bn, unit, sell_price)
  select code, name_bn, name_en, category, category_bn, unit, sell_price from seed_items order by code;
insert into public.item_costs (item_id, cost_price)
  select i.id, s.cost_price from seed_items s join public.items i on i.code = s.code;
select setval('public.item_code_seq', 57);

insert into public.settings (key, value, label_bn, label_mix, label_en) values
  ('max_fails', '5', 'ভুল PIN কতবার হলে লক হবে', 'ভুল PIN কতবার হলে Lock', 'Wrong PIN attempts before lock'),
  ('business_name', '"ইসলামিয়া মিষ্টি ঘর"', 'প্রতিষ্ঠানের নাম', 'প্রতিষ্ঠানের Name', 'Business name');

-- Suggested default permissions (owner can change every box in the app)
insert into public.role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values
  ('management','14-1',true,false,true),
  ('management','03-1',true,false,true),
  ('management','20-1',true,false,true),
  ('management','10-1',true,false,true),
  ('management','0-1',true,false,true),
  ('management','11-1',true,false,true),
  ('management','10-2',true,false,true),
  ('management','04-1',true,false,true),
  ('management','04-2',true,false,true),
  ('management','20-2',true,false,true),
  ('management','20-3',true,false,true),
  ('management','05-1',true,false,true),
  ('management','05-2',true,false,true),
  ('management','06-1',true,false,true),
  ('management','06-2',true,false,true),
  ('management','06-3',true,false,true),
  ('management','06-4',true,false,true),
  ('management','06-5',true,false,true),
  ('management','10-3',true,false,true),
  ('management','10-4',true,false,true),
  ('management','04-3',true,false,true),
  ('management','10-5',true,false,true),
  ('management','01-1',true,false,true),
  ('management','01-2',true,false,true),
  ('management','02-1',true,false,true),
  ('management','02-2',true,false,true),
  ('management','02-3',true,false,true),
  ('management','02-4',true,false,true),
  ('management','02-5',true,false,true),
  ('management','02-6',true,false,true),
  ('management','08-1',true,false,true),
  ('management','20-4',true,false,true),
  ('management','20-5',true,false,true),
  ('management','05-3',true,false,true),
  ('management','05-4',true,false,true),
  ('management','02-7',true,false,true),
  ('management','02-8',true,false,true),
  ('management','14-2',true,false,true),
  ('management','04-4',true,false,true),
  ('management','18-1',true,false,true),
  ('management','20-6',true,false,true),
  ('management','05-5',true,false,true),
  ('management','ITEMS',true,true,true),
  ('management','ITEM_COST',true,true,true),
  ('cash_controller','14-1',true,false,false),
  ('cash_controller','10-1',true,true,true),
  ('cash_controller','10-2',true,true,true),
  ('cash_controller','10-3',true,true,false),
  ('cash_controller','10-4',true,true,false),
  ('cash_controller','10-5',true,true,false),
  ('cash_controller','14-2',true,false,false),
  ('cash_controller','04-4',true,false,false),
  ('cash_controller','ITEMS',true,false,false),
  ('showroom_manager','14-1',true,true,false),
  ('showroom_manager','03-1',true,true,false),
  ('showroom_manager','20-1',true,true,false),
  ('showroom_manager','10-1',true,true,false),
  ('showroom_manager','11-1',true,true,false),
  ('showroom_manager','10-2',true,true,false),
  ('showroom_manager','20-2',true,true,false),
  ('showroom_manager','20-3',true,true,false),
  ('showroom_manager','04-3',true,true,false),
  ('showroom_manager','02-5',true,true,false),
  ('showroom_manager','08-1',true,true,false),
  ('showroom_manager','14-2',true,true,false),
  ('showroom_manager','04-4',true,false,false),
  ('showroom_manager','ITEMS',true,false,false),
  ('salesperson','14-1',true,false,false),
  ('salesperson','20-1',true,true,false),
  ('salesperson','20-3',true,true,false),
  ('salesperson','14-2',true,true,false),
  ('salesperson','ITEMS',true,false,false),
  ('storekeeper','03-1',true,true,false),
  ('storekeeper','04-1',true,true,false),
  ('storekeeper','04-2',true,true,false),
  ('storekeeper','06-3',true,false,false),
  ('storekeeper','04-3',true,true,false),
  ('storekeeper','04-4',true,true,false),
  ('storekeeper','ITEMS',true,false,false),
  ('factory_incharge','03-1',true,true,false),
  ('factory_incharge','04-2',true,true,false),
  ('factory_incharge','05-1',true,true,false),
  ('factory_incharge','05-2',true,true,false),
  ('factory_incharge','04-3',true,true,false),
  ('factory_incharge','05-3',true,true,false),
  ('factory_incharge','05-4',true,true,false),
  ('factory_incharge','05-5',true,true,false),
  ('factory_incharge','ITEMS',true,false,false),
  ('purchasing','04-1',true,false,false),
  ('purchasing','06-1',true,true,false),
  ('purchasing','06-2',true,true,false),
  ('purchasing','06-3',true,true,false),
  ('purchasing','06-4',true,false,false),
  ('purchasing','06-5',true,false,false),
  ('purchasing','ITEMS',true,true,false),
  ('purchasing','ITEM_COST',true,false,false),
  ('party_coordinator','20-1',true,true,false),
  ('party_coordinator','20-2',true,true,false),
  ('party_coordinator','20-4',true,true,false),
  ('party_coordinator','20-5',true,true,false),
  ('party_coordinator','ITEMS',true,false,false),
  ('carrier','03-1',true,false,false),
  ('carrier','10-1',true,false,false),
  ('carrier','20-6',true,true,false),
  ('hr','11-1',true,false,false),
  ('hr','02-1',true,true,false),
  ('hr','02-2',true,true,false),
  ('hr','02-3',true,true,false),
  ('hr','02-4',true,true,false),
  ('hr','02-5',true,true,false),
  ('hr','02-6',true,true,false),
  ('hr','02-7',true,true,false),
  ('hr','02-8',true,true,false);

-- ---------------------------------------------------------------- phase2.sql
-- ============================================================
-- BOS tool · Phase 2 schema: form entries, serials, exceptions,
-- red-control release requests, location settings.
-- Run AFTER schema.sql (SQL Editor -> paste -> Run). Run once.
-- ============================================================

create table public.location_settings (
  location_id int not null references public.locations(id),
  key text not null,
  value jsonb,                    -- null = "data needed"
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (location_id, key)
);

create table public.serials (
  form_code text not null, location_id int not null, last int not null default 0,
  primary key (form_code, location_id)
);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  serial int not null,
  entry_date date not null,
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  data jsonb not null default '{}',
  flags jsonb not null default '[]',               -- [{code, level:'red'|'yellow', amount, text:{bn,en}}]
  check_data jsonb not null default '{}',          -- the checker/receiver's part of the form
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  checked_by uuid, checked_staff text, checked_at timestamptz, check_note text,
  unique (form_code, location_id, serial)
);
create index entries_lookup on public.entries (form_code, location_id, entry_date desc);

create table public.exceptions (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  form_code text not null, location_id int not null, entry_date date not null,
  flag_code text not null, level text not null check (level in ('red','yellow')),
  amount numeric, text jsonb,
  status text not null default 'open' check (status in ('open','resolved')),
  created_at timestamptz not null default now(),
  resolved_by uuid, resolved_staff text, resolved_at timestamptz, resolved_note text
);
create index exceptions_open on public.exceptions (status, created_at desc);

create table public.release_requests (
  id bigserial primary key,
  entry_id uuid not null references public.entries(id),
  flag_code text not null,
  flag_amount numeric,                 -- a release only covers the amount that was asked about
  reason text not null check (length(btrim(reason)) > 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text
);
create unique index release_one_pending on public.release_requests (entry_id, flag_code) where status = 'pending';

-- ---------- helpers ----------
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc));
$$;

-- true when an existing non-empty value in "o" is changed or removed in "n" (filling blanks is free)
create or replace function public.jsonb_overwrites(o jsonb, n jsonb) returns boolean
language plpgsql immutable as $$
declare k text; i int;
begin
  if o is null or o = 'null'::jsonb or o = '""'::jsonb or o = '[]'::jsonb or o = '{}'::jsonb or o = 'false'::jsonb then return false; end if;
  if n is null then return true; end if;
  if jsonb_typeof(o) = 'object' then
    if jsonb_typeof(n) <> 'object' then return true; end if;
    for k in select jsonb_object_keys(o) loop
      if public.jsonb_overwrites(o->k, n->k) then return true; end if;
    end loop;
    return false;
  elsif jsonb_typeof(o) = 'array' then
    if jsonb_typeof(n) <> 'array' then return true; end if;
    for i in 0 .. jsonb_array_length(o) - 1 loop
      if public.jsonb_overwrites(o->i, n->i) then return true; end if;
    end loop;
    return false;
  else
    return o is distinct from n;
  end if;
end $$;

create or replace function public.staff_directory() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active()
    then coalesce((select jsonb_agg(jsonb_build_object('id', id, 'staff_id', staff_id, 'full_name', full_name) order by full_name)
                   from public.profiles where status = 'active'), '[]'::jsonb)
    else '[]'::jsonb end;
$$;

-- ---------- entry workflow (all writes go through these) ----------
create or replace function public.save_entry(p_id uuid, p_form text, p_loc int, p_date date, p_data jsonb, p_flags jsonb, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; n int; ow boolean;
begin
  if not public.can_do(p_form, 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not exists (select 1 from public.forms where code = p_form and enabled) then raise exception 'form is switched off'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_id is null then
    insert into public.serials (form_code, location_id, last) values (p_form, p_loc, 1)
      on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
    insert into public.entries (form_code, location_id, serial, entry_date, data, flags, created_by, created_staff)
      values (p_form, p_loc, n, p_date, coalesce(p_data, '{}'), coalesce(p_flags, '[]'), auth.uid(), sid) returning * into e;
    return jsonb_build_object('id', e.id, 'serial', e.serial);
  end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can edit'; end if;
  ow := public.jsonb_overwrites(e.data, coalesce(p_data, '{}'));
  if ow and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  if ow then
    insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
      values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), e.data, p_data);
  end if;
  update public.entries set data = coalesce(p_data, '{}'), flags = coalesce(p_flags, '[]'), entry_date = p_date, updated_at = now() where id = p_id;
  return jsonb_build_object('id', e.id, 'serial', e.serial, 'overwrote', ow);
end $$;

create or replace function public.submit_entry(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; f public.forms; fl jsonb; blocked text[] := '{}'; auto boolean;
begin
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status <> 'draft' then raise exception 'entry is locked'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can submit'; end if;
  if not public.can_do(e.form_code, 'enter') or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  select * into f from public.forms where code = e.form_code;
  if f.red_block then
    for fl in select * from jsonb_array_elements(e.flags) loop
      if fl->>'level' = 'red' and not exists (select 1 from public.release_requests r
           where r.entry_id = e.id and r.flag_code = fl->>'code' and r.status = 'approved'
             and r.flag_amount is not distinct from nullif(fl->>'amount','')::numeric) then
        blocked := blocked || (fl->>'code');
      end if;
    end loop;
    if array_length(blocked, 1) > 0 then raise exception 'red_blocked:%', array_to_string(blocked, ','); end if;
  end if;
  update public.entries set status = 'submitted', submitted_at = now(), updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  delete from public.exceptions where entry_id = e.id and status = 'open';
  if auto then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(e.flags) x;
  end if;
  return jsonb_build_object('status', 'submitted');
end $$;

create or replace function public.decide_entry(p_id uuid, p_approve boolean, p_note text default null, p_check jsonb default null, p_flags jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; self_ok boolean; auto boolean; newflags jsonb;
begin
  select * into e from public.entries where id = p_id for update;
  if not found or e.status <> 'submitted' then raise exception 'entry is not waiting for a decision'; end if;
  if not (public.can_do(e.form_code, 'approve') and public.can_loc(e.location_id)) then raise exception 'not allowed'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if e.created_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own entry'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  -- flags found while checking (receiver's count, etc.) are added to the maker's flags
  newflags := coalesce(p_flags, '[]'::jsonb);
  update public.entries set status = case when p_approve then 'approved' else 'rejected' end,
    check_data = coalesce(p_check, check_data),
    flags = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(e.flags) x where coalesce(x->>'src','') <> 'check') || newflags,
    checked_by = auth.uid(), checked_staff = sid, checked_at = now(), check_note = p_note, updated_at = now() where id = p_id;
  select coalesce((select (value #>> '{}')::boolean from public.settings where key = 'auto_exceptions'), true) into auto;
  if auto and jsonb_array_length(newflags) > 0 then
    delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code in (select x->>'code' from jsonb_array_elements(newflags) x);
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      select e.id, e.form_code, e.location_id, e.entry_date, x->>'code', x->>'level', nullif(x->>'amount','')::numeric, x->'text'
      from jsonb_array_elements(newflags) x;
  end if;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

-- send a submitted/rejected entry back to draft (note is mandatory, before/after kept in corrections)
create or replace function public.reopen_entry(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_id for update;
  if not found then raise exception 'entry not found'; end if;
  if e.status = 'draft' then return jsonb_build_object('status', 'draft'); end if;
  if e.status = 'approved' and not public.is_owner() then raise exception 'only the owner can reopen an approved entry'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can reopen'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.corrections (user_id, staff_id, form_code, entry_id, note, before, after)
    values (auth.uid(), sid, e.form_code, e.id::text, btrim(p_note), jsonb_build_object('status', e.status, 'data', e.data), null);
  update public.entries set status = 'draft', submitted_at = null, checked_by = null, checked_staff = null, checked_at = null, check_note = null, check_data = '{}', updated_at = now() where id = p_id;
  return jsonb_build_object('status', 'draft');
end $$;

create or replace function public.request_release(p_entry uuid, p_flag text, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; rid bigint;
begin
  if p_reason is null or length(btrim(p_reason)) = 0 then raise exception 'note_required'; end if;
  select * into e from public.entries where id = p_entry;
  if not found or e.status <> 'draft' then raise exception 'entry must be a draft'; end if;
  if e.created_by <> auth.uid() and not public.is_owner() then raise exception 'only the maker can ask'; end if;
  if not exists (select 1 from jsonb_array_elements(e.flags) x where x->>'code' = p_flag and x->>'level' = 'red') then raise exception 'no such red control'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.release_requests (entry_id, flag_code, flag_amount, reason, requested_by, requested_staff)
    values (p_entry, p_flag, (select nullif(x->>'amount','')::numeric from jsonb_array_elements(e.flags) x where x->>'code' = p_flag limit 1),
            btrim(p_reason), auth.uid(), sid) returning id into rid;
  return jsonb_build_object('id', rid);
end $$;

create or replace function public.decide_release(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; r public.release_requests;
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  select * into r from public.release_requests where id = p_id for update;
  if not found or r.status <> 'pending' then raise exception 'request is not pending'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.release_requests set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;

create or replace function public.resolve_exception(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare x public.exceptions; sid text;
begin
  select * into x from public.exceptions where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or public.can_do(x.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_staff = sid, resolved_at = now(), resolved_note = btrim(p_note) where id = p_id;
end $$;

-- audit: status changes of entries, and the new decision tables
create or replace function public.log_entry_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), sid, 'status', 'entries', new.id::text,
              jsonb_build_object('form', new.form_code, 'serial', new.serial, 'from', case when tg_op = 'INSERT' then null else old.status end, 'to', new.status));
  end if;
  return new;
end $$;
create trigger entries_status_log after insert or update on public.entries for each row execute function public.log_entry_status();
create trigger audit_release after insert or update on public.release_requests for each row execute function public.log_change('id');
create trigger audit_exceptions after update on public.exceptions for each row execute function public.log_change('id');
create trigger audit_loc_settings after insert or update on public.location_settings for each row execute function public.log_change('location_id,key');

-- ---------- privileges and row level security ----------
grant select on public.location_settings, public.entries, public.exceptions, public.release_requests to authenticated;
grant insert, update on public.location_settings to authenticated;
grant execute on function public.can_loc(int), public.staff_directory(),
  public.save_entry(uuid, text, int, date, jsonb, jsonb, text), public.submit_entry(uuid),
  public.decide_entry(uuid, boolean, text, jsonb, jsonb), public.reopen_entry(uuid, text),
  public.request_release(uuid, text, text), public.decide_release(bigint, boolean, text),
  public.resolve_exception(bigint, text) to authenticated;
alter table public.location_settings enable row level security;
alter table public.serials enable row level security;
alter table public.entries enable row level security;
alter table public.exceptions enable row level security;
alter table public.release_requests enable row level security;

create policy locset_read on public.location_settings for select to authenticated using (public.is_active());
create policy locset_owner_write on public.location_settings for all to authenticated using (public.is_owner()) with check (public.is_owner());
create policy entries_read on public.entries for select to authenticated using (public.can_do(form_code, 'view') and public.can_loc(location_id));
create policy exceptions_read on public.exceptions for select to authenticated using (public.is_owner() or public.can_do(form_code, 'approve'));
create policy release_read on public.release_requests for select to authenticated using (requested_by = auth.uid() or public.is_owner());

insert into public.settings (key, value, label_bn, label_mix, label_en) values
  ('auto_exceptions', 'true', 'গরমিল নিজে নিজে কাজের তালিকায় উঠবে', 'গরমিল নিজে নিজে Exception List-এ উঠবে', 'Variances go to the exceptions list automatically');

-- ---------------------------------------------------------------- phase3.sql
-- ============================================================
-- BOS tool · Phase 3 schema: POS sales, photos storage.
-- Run AFTER schema.sql and phase2.sql (SQL Editor -> paste -> Run). Run once.
-- ============================================================

-- ---------- the POS form entry in the form list + suggested default permissions ----------
insert into public.forms (code, area, name_bn, name_mix, name_en, version, sort) values
  ('POS','showroom','সেল (POS)','Sale (POS)','Sales (POS)','',0);
insert into public.role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values
  ('management','POS',true,false,true),
  ('cash_controller','POS',true,false,false),
  ('showroom_manager','POS',true,true,true),
  ('salesperson','POS',true,true,false);

-- ---------- sales ----------
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,                          -- set by the phone; makes a re-sent sale harmless
  location_id int not null references public.locations(id),
  receipt int not null,                           -- running receipt number per location
  sale_date date not null default (now() at time zone 'Asia/Dhaka')::date,
  sold_at timestamptz not null default now(),
  lines jsonb not null default '[]',              -- [{item_id,name,unit,qty,price,amount,override}] (price = snapshot)
  subtotal numeric not null,
  discount numeric not null default 0,
  total numeric not null,
  pay_mode text not null check (pay_mode in ('cash','mobile','card','due')),
  tendered numeric,                               -- cash given by the customer (for change)
  customer text,
  note text,
  quick boolean not null default false,
  status text not null default 'done' check (status in ('done','void')),
  created_by uuid not null, created_staff text,
  void_by uuid, void_staff text, void_at timestamptz, void_note text,
  unique (location_id, receipt)
);
create index sales_day on public.sales (location_id, sale_date, sold_at);

alter table public.exceptions alter column entry_id drop not null;
alter table public.exceptions add column sale_id uuid references public.sales(id);

create trigger audit_sales after insert or update on public.sales for each row execute function public.log_change('id');

-- ---------- record a sale (price check and totals are done here, not trusted from the phone) ----------
create or replace function public.record_sale(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_mode text,
  p_tendered numeric, p_customer text, p_note text, p_quick boolean, p_sold_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; at_ timestamptz := coalesce(p_sold_at, now());
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true); end if;
  end if;
  -- a sale made offline keeps its own time, but only within the last 3 days and never in the future
  if at_ > now() + interval '10 minutes' or at_ < now() - interval '3 days' then at_ := now(); end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if p_mode is null or p_mode not in ('cash','mobile','card','due') then raise exception 'bad_mode'; end if;
  if p_tendered is not null and (p_tendered < 0 or p_tendered = 'NaN'::numeric) then raise exception 'bad_amount'; end if;
  if disc = 'NaN'::numeric then raise exception 'bad_discount'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id','') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        -- the phone showed this price; if the list price moved meanwhile the list price wins and it is flagged
        shown := nullif(ln->>'price','')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit,
        'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    else
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name',''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if p_mode = 'due' and (p_customer is null or length(btrim(p_customer)) = 0) then raise exception 'due_needs_customer'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick, created_by, created_staff)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc, p_mode, p_tendered, left(nullif(btrim(p_customer), ''), 80), left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false), auth.uid(), sid)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true); end if;
    raise;
  end;
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total);
end $$;

-- ---------- void (a sale is never edited; a note is required) ----------
create or replace function public.void_sale(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.sales; sid text;
begin
  if not (public.is_owner() or public.can_do('POS', 'approve')) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into s from public.sales where id = p_id for update;
  if not found then raise exception 'sale not found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.status = 'void' then raise exception 'already void'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.sales set status = 'void', void_by = auth.uid(), void_staff = sid, void_at = now(), void_note = btrim(p_note) where id = p_id;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, s.id, 'POS', s.location_id, s.sale_date, 'sale_void', 'yellow', s.total,
      jsonb_build_object('bn', 'রসিদ ' || s.receipt || ' বাতিল: ' || btrim(p_note), 'en', 'Receipt ' || s.receipt || ' voided: ' || btrim(p_note)));
end $$;

-- ---------- privileges and RLS ----------
alter table public.sales enable row level security;
grant select on public.sales to authenticated;
grant execute on function public.record_sale(uuid, int, jsonb, numeric, text, numeric, text, text, boolean, timestamptz),
  public.void_sale(uuid, text) to authenticated;
create policy sales_read on public.sales for select to authenticated
  using (public.can_do('POS', 'view') and public.can_loc(location_id));

-- ---------- location scope for exceptions (POS exceptions follow the sale's location) ----------
drop policy exceptions_read on public.exceptions;
create policy exceptions_read on public.exceptions for select to authenticated
  using (public.is_owner() or (public.can_do(form_code, 'approve') and public.can_loc(location_id)));
create or replace function public.resolve_exception(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare x public.exceptions; sid text;
begin
  select * into x from public.exceptions where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public.is_owner() or (public.can_do(x.form_code, 'approve') and public.can_loc(x.location_id))) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.exceptions set status = 'resolved', resolved_by = auth.uid(), resolved_staff = sid, resolved_at = now(), resolved_note = btrim(p_note) where id = p_id;
end $$;

-- POS sales live in `sales`; the generic entry table must never carry a POS "form"
create or replace function public.no_pos_entries() returns trigger language plpgsql as $$
begin
  if new.form_code = 'POS' then raise exception 'POS has its own sale screen'; end if;
  return new;
end $$;
create trigger entries_no_pos before insert on public.entries for each row execute function public.no_pos_entries();

-- ---------- day / location / payment summary (the dashboard asks this instead of downloading every sale) ----------
create or replace function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount)
  from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- photos (receipts, goods, repairs) — path is <form code>/<location id>/<file>.jpg ----------
create or replace function public.photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active()
    and split_part(p_name, '/', 2) ~ '^[0-9]+$'
    and public.can_do(split_part(p_name, '/', 1), p_action)
    and public.can_loc(split_part(p_name, '/', 2)::int);
$$;
grant execute on function public.photo_ok(text, text) to authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos', 'photos', false, 3145728, array['image/jpeg']) on conflict (id) do nothing;
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.photo_ok(name, 'enter'));
create policy photos_read on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.photo_ok(name, 'view'));

-- ---------------------------------------------------------------- phase4.sql
-- ============================================================
-- BOS tool · Phase 4: business-logic functions (read-only analytics).
-- Run AFTER schema.sql, phase2.sql and phase3.sql. Run once. It changes no data.
--
-- Principle: nothing here is a fixed number. Every figure is computed from what staff entered
-- (sales, costs, expense vouchers), over a period the owner chooses, and limits are SUGGESTED from
-- history for the owner to accept, never applied automatically.
--   Cost-based figures (COGS, gross profit) need the cost-price permission (ITEM_COST view).
--   Costs use the CURRENT cost price of each item (price history is not re-costed).
--   Quick sales have no item, so they carry no cost: they are reported as "uncosted".
-- ============================================================

create index if not exists sales_date_loc on public.sales (sale_date, location_id);

-- who may look at sales analytics: owner, or a role with approve on the POS form
create or replace function public.biz_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve'));
$$;
create or replace function public.biz_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view'));
$$;

-- ---------- 1. day x location: revenue, discount, voids, cost of goods ----------
create or replace function public.biz_daily(p_from date, p_to date, p_loc int default null)
returns table (sale_date date, location_id int, n bigint, revenue numeric, discount numeric,
               void_n bigint, void_amt numeric, costed_rev numeric, cogs numeric)
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ok as (select * from s where s.status = 'done'),
  ln as (
    select o.sale_date, o.location_id, (case when o.subtotal > 0 then o.total / o.subtotal else 1 end) f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  lc as (select l.*, c.cost_price from ln l left join public.item_costs c on c.item_id = l.iid),
  ag as (
    select lc.sale_date, lc.location_id,
           sum(lc.amt * lc.f) filter (where lc.cost_price is not null) cr,
           sum(lc.qty * lc.cost_price) filter (where lc.cost_price is not null) cg
    from lc group by 1, 2),
  tot as (select ok.sale_date, ok.location_id, count(*) n, sum(ok.total) rev, sum(ok.discount) disc from ok group by 1, 2),
  vd as (select s.sale_date, s.location_id, count(*) vn, sum(s.total) va from s where s.status = 'void' group by 1, 2)
  select coalesce(t.sale_date, v.sale_date), coalesce(t.location_id, v.location_id),
         coalesce(t.n, 0), coalesce(t.rev, 0), coalesce(t.disc, 0), coalesce(v.vn, 0), coalesce(v.va, 0),
         case when cost_ok then round(coalesce(a.cr, 0), 2) end, case when cost_ok then round(coalesce(a.cg, 0), 2) end
  from tot t
  full join vd v on v.sale_date = t.sale_date and v.location_id = t.location_id
  left join ag a on a.sale_date = coalesce(t.sale_date, v.sale_date) and a.location_id = coalesce(t.location_id, v.location_id)
  order by 1, 2;
end $$;

-- ---------- 2. item velocity, margin and Pareto (ABC) class ----------
-- ABC: items are ranked by revenue; A = the items that make the first 80% of revenue, B = up to 95%, C = the rest
-- (standard Pareto cut-offs). Items with no sale in the period are listed with zero (candidates for review).
create or replace function public.biz_items(p_from date, p_to date, p_loc int default null)
returns table (item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric,
               cogs numeric, share_pct numeric, cum_pct numeric, abc text)
language plpgsql stable security definer set search_path = public as $$
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
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join public.item_costs c on c.item_id = i.id
    where i.is_active or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $$;

-- ---------- 3. staff control indicators vs peers (pass ONE location: with null the peers of all shops are pooled) ----------
-- Indicators only (not proof): each ratio is shown next to the peer MEDIAN. Whether a ratio counts as unusual is
-- the owner's call (setting `anomaly_ratio` in the app); no threshold is built in here.
create or replace function public.biz_staff(p_from date, p_to date, p_loc int default null)
returns table (staff_id text, n bigint, revenue numeric, discount_pct numeric, void_pct numeric, override_pct numeric,
               quick_pct numeric, due_pct numeric, med_discount_pct numeric, med_void_pct numeric,
               med_override_pct numeric, med_quick_pct numeric, med_due_pct numeric, peers bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ovr as (select s.id, bool_or(e->>'override' = 'true') o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (
    select s.created_staff st,
           count(*) filter (where s.status = 'done') n,
           coalesce(sum(s.total) filter (where s.status = 'done'), 0) rev,
           coalesce(sum(s.discount) filter (where s.status = 'done'), 0) disc,
           count(*) filter (where s.status = 'void') vn,
           count(*) filter (where s.status = 'done' and o.o) onum,
           count(*) filter (where s.status = 'done' and s.quick) qn,
           coalesce(sum(s.total) filter (where s.status = 'done' and s.pay_mode = 'due'), 0) duea
    from s left join ovr o on o.id = s.id group by s.created_staff),
  r as (
    select p.st, p.n, p.rev,
           case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end dp,
           case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end vp,
           case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end op,
           case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end qp,
           case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end up
    from per p)
  select r.st, r.n, r.rev, r.dp, r.vp, r.op, r.qp, r.up,
         (select (percentile_cont(0.5) within group (order by x.dp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.vp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.op))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.qp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.up))::numeric from r x),
         (select count(*) from r)
  from r order by r.rev desc;
end $$;

-- ---------- 4. purchase outlook: what the coming days are likely to need, from actual sales ----------
-- Every calendar day of the look-back counts (a closed or zero-sales day counts as 0, so the average is honest).
-- Expected revenue for a coming day = average of the same weekday over the look-back (needs at least 2 such days,
-- otherwise the plain daily average). Cost ratio = actual COGS / costed revenue. The purchase estimate is a RANGE:
--   low  = expected revenue x costed share x ratio   (only the item-wise part, which has a known cost)
--   high = expected revenue x ratio                   (assuming quick sales carry the same cost ratio)
-- It is a planning estimate, not a limit.
create or replace function public.biz_outlook(p_loc int, p_ahead int default 7, p_lookback int default 28)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  td date := (now() at time zone 'Asia/Dhaka')::date; fr date; trading int; rev numeric; costed numeric; cg numeric;
  avg_d numeric; exp_rev numeric; wd_used int; ratio numeric; share numeric;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_ahead < 1 or p_ahead > 31 or p_lookback < 7 or p_lookback > 120 then raise exception 'bad_range'; end if;
  fr := td - p_lookback;
  with d as materialized (select * from public.biz_daily(fr, td - 1, p_loc)),
       cal as (select g::date dt, coalesce(sum(d.revenue), 0) r, coalesce(sum(d.n), 0) n from generate_series(fr, td - 1, interval '1 day') g left join d on d.sale_date = g::date group by g),
       wd as (select extract(dow from dt)::int dw, count(*) cnt, avg(r) a from cal group by 1),
       fut as (select td + g dt from generate_series(0, p_ahead - 1) g),
       tot as (select count(*) filter (where n > 0) trading, avg(r) avg_d, sum(r) rev from cal),
       cs as (select sum(costed_rev) costed, sum(cogs) cg from d)
  select tot.trading, tot.rev, tot.avg_d, cs.costed, cs.cg,
         (select sum(case when wd.cnt >= 2 then wd.a else tot.avg_d end) from fut left join wd on wd.dw = extract(dow from fut.dt)::int),
         (select count(*) filter (where wd.cnt >= 2) from fut left join wd on wd.dw = extract(dow from fut.dt)::int)
    into trading, rev, avg_d, costed, cg, exp_rev, wd_used
  from tot, cs;
  if trading = 0 then return jsonb_build_object('lookback_days', p_lookback, 'trading_days', 0, 'enough', false); end if;
  if costed is not null and costed > 0 then ratio := cg / costed; share := costed / nullif(rev, 0); end if;
  return jsonb_build_object('lookback_days', p_lookback, 'trading_days', trading, 'avg_daily_revenue', round(avg_d, 2),
    'ahead_days', p_ahead, 'weekday_pattern_days', wd_used, 'expected_revenue', round(exp_rev, 2),
    'cost_ratio', case when ratio is not null then round(ratio, 4) end,
    'costed_share', case when share is not null then round(share, 4) end,
    'est_purchase_low', case when ratio is not null then round(exp_rev * share * ratio, 2) end,
    'est_purchase_high', case when ratio is not null then round(exp_rev * ratio, 2) end,
    'enough', trading >= 7);
end $$;

-- ---------- 5. limit suggestions from history (owner only; nothing is applied here) ----------
-- Expense voucher (10-2) lines of submitted/approved entries: spread of single expenses and of daily totals.
create or replace function public.biz_suggest(p_loc int, p_days int default 90)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_days < 14 or p_days > 365 then raise exception 'bad_range'; end if;
  with l as (
    select e.entry_date d, case when translate(x->>'amount', '০১২৩৪৫৬৭৮৯,', '0123456789') ~ '^[0-9]+(\.[0-9]+)?$' then translate(x->>'amount', '০১২৩৪৫৬৭৮৯,', '0123456789')::numeric end amt, (x->>'amount') raw
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
    where e.form_code = '10-2' and e.location_id = p_loc and e.status in ('submitted', 'approved')
      and e.entry_date >= (now() at time zone 'Asia/Dhaka')::date - p_days),
  dd as (select d, sum(amt) t from l where amt is not null group by d),
  a as (select count(amt) n, (percentile_cont(0.5) within group (order by amt))::numeric med, (percentile_cont(0.9) within group (order by amt))::numeric p90, max(amt) mx from l where amt is not null),
  b as (select count(*) n, (percentile_cont(0.5) within group (order by t))::numeric med, (percentile_cont(0.9) within group (order by t))::numeric p90, max(t) mx from dd)
  select jsonb_build_object('window_days', p_days,
      'expense', jsonb_build_object('n', a.n, 'skipped', (select count(*) from l where amt is null and raw is not null and raw <> ''), 'median', round(a.med, 2), 'p90', round(a.p90, 2), 'max', a.mx),
      'daily_total', jsonb_build_object('days', b.n, 'median', round(b.med, 2), 'p90', round(b.p90, 2), 'max', b.mx))
    into res from a, b;
  return res || jsonb_build_object(
    'current_expense_max', (select value from public.location_settings where location_id = p_loc and key = 'expense_max'),
    'current_imprest', (select value from public.location_settings where location_id = p_loc and key = 'imprest'));
end $$;

revoke all on function public.biz_ok(), public.biz_cost_ok(), public.biz_daily(date, date, int), public.biz_items(date, date, int), public.biz_staff(date, date, int), public.biz_outlook(int, int, int), public.biz_suggest(int, int) from public, anon;
grant execute on function public.biz_ok(), public.biz_cost_ok(),
  public.biz_daily(date, date, int), public.biz_items(date, date, int), public.biz_staff(date, date, int),
  public.biz_outlook(int, int, int), public.biz_suggest(int, int) to authenticated;

-- ---------------------------------------------------------------- ALL_NEW.sql
-- ============================================================
-- BOS tool · Phase 5: fixed brand names, official location names, paper-form numbering and gap audit.
-- Run AFTER phase3.sql and phase4.sql. Run once. Safe to run again (it only updates names and adds an index/functions).
-- ============================================================

-- ---------- brand and location names exactly as in the guidebook (seven locations) ----------
update public.locations set sort = 1, name_bn = 'ইসলামিয়া মিষ্টি ঘর — মেইন শোরুম ও মেইন (মিষ্টি) কারখানা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — Main Showroom ও Main (মিষ্টি) Factory', name_en = 'ISLAMIYA MISTY GHAR — Main Showroom & Main (Sweet) Factory' where code = 'main';
update public.locations set sort = 2, name_bn = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_mix = 'ইসলামিয়া মিষ্টি ঘর — ২য় শাখা', name_en = 'ISLAMIYA MISTY GHAR — 2nd Branch' where code = 'branch2';
update public.locations set sort = 3, name_bn = 'মিষ্টি বাড়ি', name_mix = 'মিষ্টি বাড়ি', name_en = 'MISTY BARI' where code = 'mishti_bari';
update public.locations set sort = 4, name_bn = 'AL-CAKIZ (বাসার নিচে)', name_mix = 'AL-CAKIZ (বাসার নিচে)', name_en = 'AL-CAKIZ (below the residence)' where code = 'al_cakes';
update public.locations set sort = 5, name_bn = 'কেক কারখানা (বাসার নিচে)', name_mix = 'Cake Factory (বাসার নিচে)', name_en = 'Cake Factory (below the residence)' where code = 'cake_factory';
update public.locations set sort = 6, name_bn = 'মুজগুন্নি মিষ্টি কারখানা (বন্ধ, যন্ত্র রাখা)', name_mix = 'মুজগুন্নি মিষ্টি Factory (বন্ধ, যন্ত্র রাখা)', name_en = 'Mujgunni Sweet Factory (closed, machines stored)' where code = 'mishti_factory';
update public.locations set sort = 7, name_bn = 'গোডাউন (ইসলামিয়ার পাশের গলি)', name_mix = 'Godown (ইসলামিয়ার পাশের গলি)', name_en = 'Godown (lane beside ISLAMIYA MISTY GHAR)' where code = 'godown';
update public.settings set value = '"ইসলামিয়া মিষ্টি ঘর"', label_en = 'Business name (fixed, never translated)' where key = 'business_name';
insert into public.settings (key, value, label_bn, label_mix, label_en)
  values ('business_name_latin', '"ISLAMIYA MISTY GHAR"', 'প্রতিষ্ঠানের নাম (ইংরেজি অক্ষরে, স্থির)', 'প্রতিষ্ঠানের Name (Latin, স্থির)', 'Business name in Latin letters (fixed)')
  on conflict (key) do update set value = excluded.value;

-- ---------- paper form number: the printed serial of the numbered paper book, stored in data.paper_no ----------
-- One printed number can be recorded once per form and location (a duplicate is refused by the database).
create unique index if not exists entries_paper_no_uq on public.entries (form_code, location_id, (btrim(data->>'paper_no')))
  where nullif(btrim(data->>'paper_no'), '') is not null;

-- ---------- gap audit: printed numbers that were never entered (a missing page = a missing transaction) ----------
-- The number is the trailing digits of what was typed (A-0012 -> 12). Works only on numbers that were entered.
create or replace function public.number_audit(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lo bigint; hi bigint; cnt bigint; miss bigint[]; miss_n bigint; unnum bigint;
begin
  if not (public.is_owner() or (public.can_do(p_form, 'approve') and public.can_loc(p_loc))) then raise exception 'not allowed'; end if;
  with n as (
    select nullif(substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$'), '')::bigint v
    from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is not null)
  select min(v), max(v), count(v) into lo, hi, cnt from n;
  select count(*) into unnum from public.entries e where e.form_code = p_form and e.location_id = p_loc and nullif(btrim(e.data->>'paper_no'), '') is null;
  if cnt is null or cnt = 0 then return jsonb_build_object('entered', 0, 'without_number', unnum, 'missing', '[]'::jsonb, 'missing_count', 0); end if;
  if hi - lo > 100000 then raise exception 'range too wide'; end if;
  select count(*) into miss_n from generate_series(lo, hi) g where not exists (
    select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
      and substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint = g);
  select coalesce(array_agg(g order by g), '{}') into miss from (
    select g from generate_series(lo, hi) g where not exists (
      select 1 from public.entries e where e.form_code = p_form and e.location_id = p_loc
        and substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint = g) order by g limit 200) m;
  return jsonb_build_object('entered', cnt, 'first', lo, 'last', hi, 'without_number', unnum, 'missing_count', miss_n, 'missing', to_jsonb(miss));
end $$;

-- one line per form and location that has at least one gap (for the dashboard)
create or replace function public.number_audit_summary() returns table (form_code text, location_id int, entered bigint, first_no bigint, last_no bigint, missing_count bigint)
language sql stable security definer set search_path = public as $$
  with n as (
    select e.form_code, e.location_id, substring(btrim(e.data->>'paper_no') from '([0-9]{1,15})\s*$')::bigint v
    from public.entries e where nullif(btrim(e.data->>'paper_no'), '') is not null and e.data->>'paper_no' ~ '[0-9]\s*$'),
  g as (select form_code, location_id, count(distinct v) c, min(v) lo, max(v) hi from n group by 1, 2)
  select g.form_code, g.location_id, g.c, g.lo, g.hi, (g.hi - g.lo + 1) - g.c
  from g
  where (g.hi - g.lo + 1) - g.c > 0 and g.hi - g.lo <= 100000
    and (public.is_owner() or (public.can_do(g.form_code, 'approve') and public.can_loc(g.location_id)))
  order by 6 desc;
$$;
revoke all on function public.number_audit(text, int), public.number_audit_summary() from public, anon;
grant execute on function public.number_audit(text, int), public.number_audit_summary() to authenticated;
-- ============================================================
-- BOS tool · Phase 6: customers, partial / split payment, due (baki) ledger, wholesale rules, editable option lists.
-- Run AFTER phase3/4/5. Run once. Existing sales are kept (their payments are back-filled).
-- ============================================================

-- ---------- Bangladesh mobile number: 01XXXXXXXXX (accepts +880 / 880 / Bangla digits / spaces / dashes) ----------
create or replace function public.norm_mobile(p text) returns text
language plpgsql immutable as $$
declare d text;
begin
  if p is null then return null; end if;
  if p ~ '[A-Za-z]' then raise exception 'bad_mobile'; end if;
  d := translate(p, '০১২৩৪৫৬৭৮৯', '0123456789');
  d := regexp_replace(d, '[^0-9+]', '', 'g');
  d := regexp_replace(d, '^(\+|00)?880', '0');
  if d ~ '^00[0-9]{10}$' then d := substr(d, 2); end if;
  if d !~ '^01[3-9][0-9]{8}$' then raise exception 'bad_mobile'; end if;
  return d;
end $$;

-- ---------- customers (one row per mobile number) ----------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  mobile text not null unique,
  name text not null,
  type text not null default 'retail' check (type in ('retail', 'wholesale')),
  credit_limit numeric check (credit_limit is null or credit_limit >= 0),   -- set by the owner; empty = no limit written
  note text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create trigger audit_customers after insert or update on public.customers for each row execute function public.log_change('id');

-- ---------- sales: customer, type, amounts paid / due; payments table ----------
alter table public.sales add column customer_id uuid references public.customers(id);
alter table public.sales add column sale_type text not null default 'retail' check (sale_type in ('retail', 'wholesale'));
alter table public.sales add column paid numeric not null default 0;
alter table public.sales add column due_amount numeric not null default 0;
alter table public.sales drop constraint sales_pay_mode_check;
alter table public.sales add constraint sales_pay_mode_check check (pay_mode in ('cash', 'mobile', 'card', 'due', 'split'));
create index sales_customer on public.sales (customer_id);

create table public.sale_payments (
  id bigserial primary key,
  sale_id uuid references public.sales(id),          -- null for a later collection of dues
  customer_id uuid references public.customers(id),
  location_id int not null references public.locations(id),
  kind text not null check (kind in ('sale', 'collection')),
  mode text not null check (mode in ('cash', 'mobile', 'card')),
  wallet text, ref text,                              -- bKash / Nagad ... and the transaction id
  amount numeric not null check (amount > 0),
  paid_at timestamptz not null default now(),
  note text,
  voided boolean not null default false, void_note text,
  created_by uuid, created_staff text,
  client_id uuid
);
create index sale_payments_client on public.sale_payments (client_id) where client_id is not null;
create index sale_payments_cust on public.sale_payments (customer_id) where not voided;
create index sale_payments_day on public.sale_payments (location_id, paid_at);
create trigger audit_sale_payments after insert or update on public.sale_payments for each row execute function public.log_change('id');

-- back-fill: earlier sales were all paid in full by one mode, except 'due' ones (nothing paid)
update public.sales set paid = case when pay_mode = 'due' then 0 else total end, due_amount = case when pay_mode = 'due' then total else 0 end;
insert into public.sale_payments (sale_id, location_id, kind, mode, amount, paid_at, created_by, created_staff, voided)
  select id, location_id, 'sale', pay_mode, total, sold_at, created_by, created_staff, status = 'void'
  from public.sales where pay_mode in ('cash', 'mobile', 'card') and total > 0;

-- ---------- balance of a customer = what was sold to them - what they paid (voided entries ignored) ----------
create or replace function public.customer_balance(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then
    coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
    - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0) end;
$$;

-- find a customer by mobile (for the sale screen): name, type, limit, current due
create or replace function public.find_customer(p_mobile text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m text := public.norm_mobile(p_mobile); c public.customers;
begin
  if not (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  select * into c from public.customers where mobile = m;
  if not found then return jsonb_build_object('mobile', m, 'found', false); end if;
  return jsonb_build_object('found', true, 'id', c.id, 'mobile', c.mobile, 'name', c.name, 'type', c.type, 'credit_limit', c.credit_limit, 'balance', public.customer_balance(c.id));
end $$;

-- ---------- record a sale (item lines, custom lines, quick lines; split / partial payment; customer rules) ----------
-- Lines: {item_id, qty, price, override?}  list item (price is fixed by the list unless override)
--        {item_id:null, name, qty, price}  an item that is not in the list yet (flagged for the owner)
--        {item_id:null, name, amount}      quick sale
-- Payments: [{mode: cash|mobile|card, amount, wallet?, ref?, tendered?}]. Whatever is not paid stays due.
-- A customer (mobile + name) is REQUIRED when anything is left due and for every wholesale sale.
create or replace function public.record_sale2(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb,
  p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; credit_over boolean := false; em text; ov_ok boolean;
begin
  perform set_config('bos.em_used', '', true);
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if disc = 'NaN'::numeric then raise exception 'bad_discount'; end if;
  disc := round(disc, 2);
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
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
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > 0 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
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
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due)
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
  if disc > 0 then
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
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id);
end $$;

-- ---------- collect money from a customer later (pays the oldest dues first, shown by the ledger) ----------
create or replace function public.collect_payment(p_client uuid, p_loc int, p_customer uuid, p_payments jsonb, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  if tot > bal then raise exception 'overpaid'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for pay in select * from jsonb_array_elements(p_payments) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, note, created_by, created_staff, client_id)
      values (null, p_customer, p_loc, 'collection', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2),
              left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  end loop;
  return jsonb_build_object('collected', tot, 'balance', bal - tot);
end $$;

-- ---------- dues list (who owes what, since when) and one customer's ledger ----------
create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  -- what is still unpaid on each sale = its total - what was paid at the sale; collections then clear the OLDEST unpaid sales first
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select customer_id, sum(amount) coll from public.sale_payments where kind = 'collection' and not voided and customer_id is not null group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;
create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done'
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided)
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

-- ---------- a wrongly entered collection can be reversed (owner or POS approver, with a reason) ----------
create or replace function public.void_collection(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.sale_payments;
begin
  if not public.can_grant('collection_void') then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.sale_payments where id = p_id and kind = 'collection' for update;
  if not found then raise exception 'not found'; end if;
  if p.voided then raise exception 'already void'; end if;
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.sale_payments set voided = true, void_note = btrim(p_note) where id = p_id;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, 'POS', p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'collection_void', 'yellow', p.amount,
      jsonb_build_object('bn', 'বাকি আদায় বাতিল: ' || btrim(p_note), 'en', 'A collection was reversed: ' || btrim(p_note)));
end $$;

-- ---------- void now also voids the sale's payments ----------
create or replace function public.void_sale(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.sales; sid text;
begin
  if not public.can_grant('sale_void') then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into s from public.sales where id = p_id for update;
  if not found then raise exception 'sale not found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if s.status = 'void' then raise exception 'already void'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.sales set status = 'void', void_by = auth.uid(), void_staff = sid, void_at = now(), void_note = btrim(p_note) where id = p_id;
  update public.sale_payments set voided = true, void_note = btrim(p_note) where sale_id = p_id and not voided;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, s.id, 'POS', s.location_id, s.sale_date, 'sale_void', 'yellow', s.total,
      jsonb_build_object('bn', 'রসিদ ' || s.receipt || ' বাতিল: ' || btrim(p_note), 'en', 'Receipt ' || s.receipt || ' voided: ' || btrim(p_note)));
end $$;

-- the dashboard summary also carries what was left due
drop function if exists public.sales_summary(date);
create function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric, due numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount), sum(s.due_amount)
  from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- money collected by mode and day (dashboard), and the owner's customer-due total ----------
create or replace function public.payments_summary(p_from date) returns table (pay_date date, location_id int, mode text, kind text, total numeric)
language sql stable security definer set search_path = public as $$
  select (p.paid_at at time zone 'Asia/Dhaka')::date, p.location_id, p.mode, p.kind, sum(p.amount)
  from public.sale_payments p
  where not p.voided and (p.paid_at at time zone 'Asia/Dhaka')::date >= p_from and public.can_do('POS', 'view') and public.can_loc(p.location_id)
  group by 1, 2, 3, 4;
$$;

-- staff indicator: the due share now comes from what was really left unpaid
create or replace function public.biz_staff(p_from date, p_to date, p_loc int default null)
returns table (staff_id text, n bigint, revenue numeric, discount_pct numeric, void_pct numeric, override_pct numeric,
               quick_pct numeric, due_pct numeric, med_discount_pct numeric, med_void_pct numeric,
               med_override_pct numeric, med_quick_pct numeric, med_due_pct numeric, peers bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ovr as (select s.id, bool_or(e->>'override' = 'true') o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (
    select s.created_staff st,
           count(*) filter (where s.status = 'done') n,
           coalesce(sum(s.total) filter (where s.status = 'done'), 0) rev,
           coalesce(sum(s.discount) filter (where s.status = 'done'), 0) disc,
           count(*) filter (where s.status = 'void') vn,
           count(*) filter (where s.status = 'done' and o.o) onum,
           count(*) filter (where s.status = 'done' and s.quick) qn,
           coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) duea
    from s left join ovr o on o.id = s.id group by s.created_staff),
  r as (
    select p.st, p.n, p.rev,
           case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end dp,
           case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end vp,
           case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end op,
           case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end qp,
           case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end up
    from per p)
  select r.st, r.n, r.rev, r.dp, r.vp, r.op, r.qp, r.up,
         (select (percentile_cont(0.5) within group (order by x.dp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.vp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.op))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.qp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.up))::numeric from r x),
         (select count(*) from r)
  from r order by r.rev desc;
end $$;

-- ---------- editable option lists (owner edits them in the app; forms read them) ----------
create table public.option_lists (
  list_code text not null, value_code text not null,
  label_bn text not null, label_mix text, label_en text,
  sort int not null default 0, active boolean not null default true,
  extra jsonb not null default '{}',
  primary key (list_code, value_code)
);
create trigger audit_option_lists after insert or update or delete on public.option_lists for each row execute function public.log_change('list_code,value_code');
alter table public.option_lists enable row level security;
create policy option_lists_read on public.option_lists for select to authenticated using (public.is_active());
create policy option_lists_owner on public.option_lists for all to authenticated using (public.is_owner()) with check (public.is_owner());
grant select, insert, update, delete on public.option_lists to authenticated;

insert into public.option_lists (list_code, value_code, label_bn, label_en, sort) values
 ('expense_heads', 'staff_meal', 'স্টাফের খাবার / নাস্তা', 'Staff meals / snacks', 1), ('expense_heads', 'transport', 'যাতায়াত / পরিবহন', 'Transport', 2),
 ('expense_heads', 'hospitality', 'কাস্টমার আপ্যায়ন', 'Customer hospitality', 3), ('expense_heads', 'repair', 'মেরামত / ইউটিলিটি', 'Repairs / utilities', 4),
 ('expense_heads', 'labour', 'অস্থায়ী শ্রমিকের মজুরি', 'Temporary labour wages', 5), ('expense_heads', 'sourcing', 'বাইরের সোর্সিংয়ের মালামাল', 'Outside-sourced goods', 6),
 ('expense_heads', 'other', 'অন্যান্য (লিখুন)', 'Other (write it)', 7),
 ('marketing_heads', '1', 'অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)', 'Online ads & boost (with VAT)', 1), ('marketing_heads', '2', 'কনটেন্ট তৈরি', 'Content creation', 2),
 ('marketing_heads', '3', 'ছাপা', 'Printing', 3), ('marketing_heads', '4', 'স্যাম্পল ও ট্রায়াল', 'Samples & trials', 4),
 ('marketing_heads', '5', 'অফার ও ছাড়ের ক্যাম্পেইন', 'Offer & discount campaigns', 5), ('marketing_heads', '6', 'ডেলিভারি ভর্তুকি', 'Delivery subsidy', 6),
 ('marketing_heads', '7', 'প্ল্যাটফর্ম কমিশন', 'Platform commission', 7), ('marketing_heads', '8', 'উৎসব ও ইভেন্ট', 'Festivals & events', 8),
 ('marketing_heads', '9', 'পার্টনার', 'Partners', 9), ('marketing_heads', '10', 'অন্যান্য (লিখুন)', 'Other (write it)', 10),
 ('wallets', 'bkash', 'বিকাশ', 'bKash', 1), ('wallets', 'nagad', 'Nagad (নগদ)', 'Nagad', 2), ('wallets', 'rocket', 'রকেট', 'Rocket', 3), ('wallets', 'upay', 'উপায়', 'Upay', 4);

-- ---------- privileges and row level security ----------
alter table public.customers enable row level security;
alter table public.sale_payments enable row level security;
create policy customers_read on public.customers for select to authenticated using (public.can_do('POS', 'view') or public.can_do('POS', 'enter'));
create policy customers_owner_write on public.customers for update to authenticated using (public.is_owner()) with check (public.is_owner());
create policy sale_payments_read on public.sale_payments for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
grant select on public.customers, public.sale_payments to authenticated;
grant update (credit_limit, note, active, type, name) on public.customers to authenticated;      -- the owner only (policy above)
revoke all on function public.norm_mobile(text), public.customer_balance(uuid), public.find_customer(text),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz),
  public.collect_payment(uuid, int, uuid, jsonb, text), public.customer_dues(), public.customer_ledger(uuid), public.payments_summary(date),
  public.void_sale(uuid, text), public.biz_staff(date, date, int), public.void_collection(bigint, text) from public, anon;
grant execute on function public.norm_mobile(text), public.customer_balance(uuid), public.find_customer(text),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz),
  public.collect_payment(uuid, int, uuid, jsonb, text), public.customer_dues(), public.customer_ledger(uuid), public.payments_summary(date),
  public.void_sale(uuid, text), public.biz_staff(date, date, int), public.void_collection(bigint, text) to authenticated;

-- ---------- books-closed date: after the owner closes a period (Rules page), changes dated on or before it need the grant or an emergency approval ----------
create or replace function public.lock_check(p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare v text; d date;
begin
  if p_date is null or public.is_owner() then return; end if;
  v := public.rule_txt('period_closed_until');
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return; end if;
  begin d := v::date; exception when others then return; end;      -- an impossible date (2026-02-30) locks nobody out
  if p_date > d then return; end if;
  if public.rule_ok('closed_period_edit', null, null, p_date, 'entry') then return; end if;
  raise exception 'period_closed';
end $$;
create or replace function public.entries_lock() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then perform public.lock_check(old.entry_date); end if;
  perform public.lock_check(new.entry_date);
  return new;
end $$;
create trigger entries_lock before insert or update on public.entries for each row execute function public.entries_lock();
create or replace function public.sales_lock() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then perform public.lock_check(old.sale_date); end if;
  perform public.lock_check(new.sale_date);
  return new;
end $$;
create trigger sales_lock before insert or update on public.sales for each row execute function public.sales_lock();
revoke all on function public.lock_check(date) from public, anon, authenticated;
-- ============================================================
-- BOS tool · Phase 7: business RULES the owner can edit, role GRANTS (who may do what), EMERGENCY requests.
-- Run AFTER phase6 (phase5/6/7 together are in ALL_NEW.sql). Run once.
--
-- Rules  : switches, numbers and choices (e.g. "customer mobile needed on a due sale: on/off").
-- Grants : which role may do a controlled action (e.g. give a discount above the limit). Owner always may.
-- Emergency: a staff member who is blocked by a rule asks at once; the owner approves for a short time (one use or a
--            short window) and later decides in the Rules page which roles should get the grant for good.
-- ============================================================

-- ---------- rules ----------
create table public.rules (
  key text primary key,
  module text not null,                                   -- pos | books | emergency | entries ...
  kind text not null check (kind in ('switch', 'number', 'text', 'choice')),
  value jsonb,                                            -- null = use the default
  default_value jsonb,
  unit text, choices jsonb,                               -- choices: ["block","warn","off"]
  min_value numeric, max_value numeric,                   -- bounds for a number rule
  label_bn text not null, label_mix text, label_en text,
  hint_bn text, hint_mix text, hint_en text,
  sort int not null default 0,
  updated_at timestamptz not null default now(), updated_by uuid
);
create trigger audit_rules after insert or update on public.rules for each row execute function public.log_change('key');
alter table public.rules enable row level security;
create policy rules_read on public.rules for select to authenticated using (public.is_active());
grant select on public.rules to authenticated;

create or replace function public.rule_val(p_key text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(value, default_value) from public.rules where key = p_key;
$$;
create or replace function public.rule_on(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((public.rule_val(p_key) #>> '{}')::boolean, false);
$$;
create or replace function public.rule_num(p_key text) returns numeric
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '')::numeric;
$$;
create or replace function public.rule_txt(p_key text) returns text
language sql stable security definer set search_path = public as $$
  select nullif(public.rule_val(p_key) #>> '{}', '');
$$;

-- owner changes a rule (validated by its kind); p_value null = back to the default
create or replace function public.set_rule(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rules;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.rules where key = p_key;
  if not found then raise exception 'rule not found'; end if;
  if p_value is not null and jsonb_typeof(p_value) <> 'null' then
    if r.kind = 'switch' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'bad_value'; end if;
    if r.kind = 'number' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric < coalesce(r.min_value, 0) or (p_value #>> '{}')::numeric > coalesce(r.max_value, 1000000000)) then raise exception 'bad_value'; end if;
    if r.kind = 'choice' and not (r.choices @> jsonb_build_array(p_value #>> '{}')) then raise exception 'bad_value'; end if;
    if r.kind = 'text' and jsonb_typeof(p_value) <> 'string' then raise exception 'bad_value'; end if;
    if p_key = 'period_closed_until' then
      if (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
      begin perform (p_value #>> '{}')::date; exception when others then raise exception 'bad_value'; end;
    end if;
  end if;
  update public.rules set value = case when p_value is null or jsonb_typeof(p_value) = 'null' then null else p_value end, updated_at = now(), updated_by = auth.uid() where key = p_key;
end $$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('pos_customer_on_due', 'pos', 'switch', 'true', null, null, null, null, 'বাকি রেখে সেল করলে গ্রাহকের মোবাইল নম্বর ও নাম লাগবে', 'Due রেখে sale করলে Customer এর mobile number ও নাম লাগবে', 'A customer mobile number and name are required when anything is left due', 'বন্ধ করলে বাকির সেল গ্রাহক ছাড়াই হবে — সুপারিশ করা হয় না', 'If off, a due sale can be made without a customer — not recommended', 10),
 ('pos_customer_on_wholesale', 'pos', 'switch', 'true', null, null, null, null, 'পাইকারি সেলে গ্রাহক লাগবে', 'Wholesale sale এ Customer লাগবে', 'A customer is required on every wholesale sale', null, null, 11),
 ('pos_customer_on_discount', 'pos', 'switch', 'false', null, null, null, null, 'যেকোনো ডিসকাউন্টে গ্রাহক লাগবে (খুচরা সহ)', 'যেকোনো Discount এ Customer লাগবে (retail সহ)', 'A customer is required on any discount, retail included', null, null, 12),
 ('pos_discount_manager', 'pos', 'switch', 'true', null, null, null, null, 'ডিসকাউন্ট সীমার উপরে (বা সীমা লেখা না থাকলে) নির্ধারিত ভূমিকা লাগবে', 'Discount limit এর উপরে (বা limit না থাকলে) নির্ধারিত role লাগবে', 'A granted role is needed for a discount above the limit (or when no limit is written)', 'কে পারবে তা নিচের "কে কী পারবে" ছকে ঠিক হয়', 'Who may is set in the "Who may do what" grid below', 13),
 ('pos_override_manager', 'pos', 'switch', 'true', null, null, null, null, 'তালিকার দাম বদলাতে নির্ধারিত ভূমিকা লাগবে', 'List এর দাম বদলাতে নির্ধারিত role লাগবে', 'A granted role is needed to change a list price', null, null, 14),
 ('pos_credit_mode', 'pos', 'choice', '"block"', null, '["block","warn","off"]', null, null, 'গ্রাহকের বাকির সীমা পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'Customer এর credit limit পার হলে: block = আটকাবে, warn = শুধু জানাবে, off = দেখবে না', 'When a customer’s credit limit is exceeded: block, warn only, or off', null, null, 15),
 ('pos_unlisted', 'pos', 'choice', '"flag"', null, '["allow","flag","block"]', null, null, 'তালিকায় নেই এমন আইটেম বিক্রি: allow = চলবে, flag = চলবে আর মালিককে জানাবে, block = আটকাবে', 'List এ নেই এমন item বিক্রি: allow, flag (মালিককে জানাবে), block', 'Selling an item that is not in the list: allow, flag (tell the owner), or block', null, null, 16),
 ('pos_offline_hours', 'pos', 'number', '72', 'ঘণ্টা', null, 1, 8760, 'ফোনে জমা থাকা সেল কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'ফোনে জমা sale কত ঘণ্টা পর্যন্ত নিজের সময়ে বসবে', 'How many hours an offline sale keeps its own time', 'এর পরে পাঠালে সেটা পাঠানোর সময়ে বসে', 'Sent later than this, it takes the time it was sent', 17),
 ('period_closed_until', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'হিসাব বন্ধের তারিখ — এই তারিখ পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'হিসাব বন্ধের date — এই date পর্যন্ত কিছু বদলাতে অনুমতি লাগবে', 'Books closed until — changing anything dated up to this day needs permission', 'যেমন 2026-09-30। ফাঁকা = কিছু বন্ধ নয়। মালিক সবসময় পারেন', 'e.g. 2026-09-30. Empty = nothing closed. The owner always may', 20),
 ('entry_paper_no_required', 'entries', 'switch', 'false', null, null, null, null, 'ফর্ম জমা দিতে কাগজের ছাপা নম্বর বাধ্যতামূলক', 'Form জমা দিতে কাগজের ছাপা number বাধ্যতামূলক', 'The printed paper number is required to submit a form', 'কাগজের ফর্ম আর অ্যাপ একসাথে চালালে চালু করুন', 'Turn on when paper forms run alongside the app', 30),
 ('em_enabled', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চালু', 'জরুরি request চালু', 'Emergency requests are on', 'বন্ধ করলে স্টাফ আটকে গেলে অনুরোধ পাঠাতে পারবে না', 'If off, a blocked staff member cannot send a request', 40),
 ('em_minutes', 'emergency', 'number', '30', 'মিনিট', null, 1, 1440, 'জরুরি অনুমোদন কত মিনিট চলবে', 'জরুরি অনুমোদন কত minute চলবে', 'How many minutes an emergency approval lasts', 'এই সময়ের মধ্যে ব্যবহার না হলে মেয়াদ শেষ', 'It expires if unused in this time', 41),
 ('em_discount', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চলবে: সীমার উপরে ডিসকাউন্ট', 'জরুরি request চলবে: limit এর উপরে discount', 'Emergency allowed for: discount above the limit', null, null, 42),
 ('em_price', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চলবে: দাম বদল', 'জরুরি request চলবে: দাম বদল', 'Emergency allowed for: price change', null, null, 43),
 ('em_credit', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চলবে: বাকির সীমা পার', 'জরুরি request চলবে: credit limit পার', 'Emergency allowed for: credit limit exceeded', null, null, 44),
 ('em_customer', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: গ্রাহকের মোবাইল ছাড়া সেল', 'জরুরি request চলবে: Customer এর mobile ছাড়া sale', 'Emergency allowed for: a sale without the customer mobile', 'ডিফল্টে বন্ধ — মোবাইল নম্বর নিয়ম কড়া রাখতে', 'Off by default — keeps the mobile-number rule strict', 45),
 ('em_period', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চলবে: বন্ধ হিসাবের তারিখে এন্ট্রি', 'জরুরি request চলবে: বন্ধ হিসাবের date এ entry', 'Emergency allowed for: an entry in a closed period', null, null, 46),
 ('em_access', 'emergency', 'switch', 'true', null, null, null, null, 'জরুরি অনুরোধ চলবে: যে ফর্ম বা লোকেশনে অনুমতি নেই', 'জরুরি request চলবে: যে form বা location এ অনুমতি নেই', 'Emergency allowed for: a form or location the person has no access to', null, null, 47);

-- ---------- grants: which role may do a controlled action ----------
create table public.rule_grants (
  grant_code text not null, role_code text not null references public.roles(code) on delete cascade,
  allowed boolean not null default true,
  primary key (grant_code, role_code)
);
create table public.grant_defs (
  grant_code text primary key, module text not null, sort int not null default 0,
  label_bn text not null, label_mix text, label_en text,
  window_type text not null default 'once' check (window_type in ('once', 'window')),     -- an emergency approval is used once, or lasts a short window
  emergency_rule text                                                                        -- the rule switch that allows an emergency request for it
);
create trigger audit_rule_grants after insert or update or delete on public.rule_grants for each row execute function public.log_change('grant_code,role_code');
alter table public.rule_grants enable row level security;
alter table public.grant_defs enable row level security;
create policy rule_grants_read on public.rule_grants for select to authenticated using (public.is_active());
create policy grant_defs_read on public.grant_defs for select to authenticated using (public.is_active());
grant select on public.rule_grants, public.grant_defs to authenticated;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('discount_over_limit', 'pos', 1, 'সীমার উপরে ডিসকাউন্ট দেওয়া', 'Limit এর উপরে discount দেওয়া', 'Give a discount above the limit', 'once', 'em_discount'),
 ('price_override', 'pos', 2, 'তালিকার দাম বদলানো', 'List এর দাম বদলানো', 'Change a list price', 'once', 'em_price'),
 ('credit_over_limit', 'pos', 3, 'গ্রাহকের বাকির সীমার উপরে বাকি দেওয়া', 'Customer এর credit limit এর উপরে due দেওয়া', 'Give credit above a customer’s limit', 'once', 'em_credit'),
 ('sale_without_customer', 'pos', 4, 'গ্রাহকের মোবাইল ছাড়া বাকি/পাইকারি সেল', 'Customer এর mobile ছাড়া due/wholesale sale', 'Make a due / wholesale sale without the customer mobile', 'once', 'em_customer'),
 ('sale_void', 'pos', 5, 'সেল বাতিল করা', 'Sale বাতিল করা', 'Void a sale', 'once', null),
 ('collection_void', 'pos', 6, 'বাকি আদায় বাতিল করা', 'বাকি আদায় বাতিল করা', 'Reverse a collection', 'once', null),
 ('closed_period_edit', 'books', 7, 'বন্ধ হিসাবের তারিখে এন্ট্রি দেওয়া/বদলানো', 'বন্ধ হিসাবের date এ entry দেওয়া/বদলানো', 'Enter or change something in a closed period', 'window', 'em_period'),
 ('form_access', 'access', 8, 'অনুমতি নেই এমন ফর্মে এন্ট্রি (অস্থায়ী)', 'অনুমতি নেই এমন form এ entry (অস্থায়ী)', 'Use a form without the permission (temporary)', 'window', 'em_access'),
 ('loc_access', 'access', 9, 'নিজের নয় এমন লোকেশনে কাজ (অস্থায়ী)', 'নিজের নয় এমন location এ কাজ (অস্থায়ী)', 'Work at a location that is not theirs (temporary)', 'window', 'em_access'),
 ('emergency_decide', 'emergency', 10, 'জরুরি অনুরোধ অনুমোদন করা', 'জরুরি request অনুমোদন করা', 'Decide emergency requests', 'once', null);
-- start the same as today: whoever could approve on the POS form keeps these grants
insert into public.rule_grants (grant_code, role_code)
  select g.grant_code, p.role_code from public.role_form_perms p
  cross join (values ('discount_over_limit'), ('price_override'), ('credit_over_limit'), ('sale_void'), ('collection_void')) g(grant_code)
  where p.form_code = 'POS' and p.can_approve
  on conflict do nothing;

create or replace function public.can_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and exists (
    select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = p_code and g.allowed
    join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid()));
$$;
create or replace function public.set_grant(p_code text, p_role text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_code) then raise exception 'unknown grant'; end if;
  if p_role = 'owner' then return; end if;
  if not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_allowed then insert into public.rule_grants (grant_code, role_code) values (p_code, p_role) on conflict (grant_code, role_code) do update set allowed = true;
  else delete from public.rule_grants where grant_code = p_code and role_code = p_role; end if;
end $$;

-- ---------- emergency requests ----------
create table public.emergency_requests (
  id bigserial primary key,
  grant_code text not null references public.grant_defs(grant_code),
  requested_by uuid not null, requested_staff text, location_id int,
  context jsonb not null default '{}',                       -- what was attempted, e.g. {"amount":120} or {"form":"10-2","action":"enter"}
  amount numeric,                                            -- the approval covers at most this amount (discount, credit due ...)
  for_date date,                                             -- a closed-period approval covers this date only
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'used', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  valid_until timestamptz, used_at timestamptz, used_ref text
);
create index emergency_open on public.emergency_requests (status, created_at desc);
create index emergency_user on public.emergency_requests (requested_by, grant_code, status);
create trigger audit_emergency after insert or update on public.emergency_requests for each row execute function public.log_change('id');
alter table public.emergency_requests enable row level security;
create policy emergency_read on public.emergency_requests for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_grant('emergency_decide'));
grant select on public.emergency_requests to authenticated;

create or replace function public.request_emergency(p_grant text, p_loc int, p_context jsonb, p_reason text) returns bigint
language plpgsql security definer set search_path = public as $$
declare d public.grant_defs; sid text; nid bigint; ctx jsonb := coalesce(p_context, '{}'); amt numeric; fd date; frm text; act text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('em_enabled') then raise exception 'emergency_off'; end if;
  select * into d from public.grant_defs where grant_code = p_grant;
  if not found or d.emergency_rule is null then raise exception 'emergency_not_available'; end if;
  if not public.rule_on(d.emergency_rule) then raise exception 'emergency_off'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if (select count(*) from public.emergency_requests where requested_by = auth.uid() and status = 'pending' and created_at > now() - interval '1 day') >= 5 then raise exception 'too_many_pending'; end if;
  if length(ctx::text) > 2000 or jsonb_typeof(ctx) <> 'object' then raise exception 'bad_context'; end if;
  if p_grant <> 'closed_period_edit' and p_grant <> 'form_access' then
    if p_loc is null or not exists (select 1 from public.locations where id = p_loc) or not public.can_loc(p_loc) and p_grant <> 'loc_access' then raise exception 'bad_location'; end if;
  end if;
  if p_grant = 'loc_access' and (p_loc is null or not exists (select 1 from public.locations where id = p_loc)) then raise exception 'bad_location'; end if;
  if ctx ? 'amount' then
    begin amt := (ctx->>'amount')::numeric; exception when others then raise exception 'bad_context'; end;
    if amt < 0 then raise exception 'bad_context'; end if;
  end if;
  if p_grant in ('discount_over_limit', 'credit_over_limit') and amt is null then raise exception 'bad_context'; end if;
  if p_grant = 'closed_period_edit' then
    if not (ctx ? 'date') then raise exception 'bad_context'; end if;
    begin fd := (ctx->>'date')::date; exception when others then raise exception 'bad_context'; end;
  end if;
  if p_grant = 'form_access' then
    frm := ctx->>'form'; act := coalesce(ctx->>'action', 'enter');
    if frm is null or frm in ('ITEM_COST') or not exists (select 1 from public.forms where code = frm) or act not in ('view', 'enter') then raise exception 'bad_context'; end if;
    ctx := jsonb_build_object('form', frm, 'action', act);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.emergency_requests (grant_code, requested_by, requested_staff, location_id, context, amount, for_date, reason)
    values (p_grant, auth.uid(), sid, p_loc, ctx, amt, fd, left(btrim(p_reason), 300)) returning id into nid;
  return nid;
end $$;

create or replace function public.decide_emergency(p_id bigint, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; sid text; mins numeric;
begin
  if not public.can_grant('emergency_decide') then raise exception 'not allowed'; end if;
  select * into r from public.emergency_requests where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'pending' then raise exception 'already decided'; end if;
  if r.created_at < now() - interval '1 day' then update public.emergency_requests set status = 'expired' where id = p_id; return; end if;      -- a day-old request is stale: ask again
  if r.requested_by = auth.uid() and not public.is_owner() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  mins := coalesce(public.rule_num('em_minutes'), 30);
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.emergency_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_by = auth.uid(), decided_staff = sid, decided_at = now(),
    decision_note = left(nullif(btrim(p_note), ''), 300), valid_until = case when p_approve then now() + make_interval(mins => mins::int) end where id = p_id;
end $$;

create or replace function public.cancel_emergency(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.emergency_requests set status = 'cancelled' where id = p_id and requested_by = auth.uid() and status = 'pending';
end $$;

-- use an approved request. It must cover what is being done (amount, date, location); 'once' grants are consumed, 'window' grants stay valid until they expire.
-- Every use leaves a trace: 'once' keeps used_at/used_ref, a window gets used_at on its first use plus an exception for the owner.
create or replace function public.use_emergency(p_grant text, p_loc int, p_ref text, p_amount numeric default null, p_date date default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare r public.emergency_requests; w text; sid text;
begin
  select * into r from public.emergency_requests
    where requested_by = auth.uid() and grant_code = p_grant and status = 'approved' and valid_until > now()
      and (location_id is null or p_loc is null or location_id = p_loc)
      and (amount is null or p_amount is null or p_amount <= amount)
      and (for_date is null or p_date is null or for_date = p_date)
    order by id limit 1 for update;
  if not found then return false; end if;
  select window_type into w from public.grant_defs where grant_code = p_grant;
  if w = 'once' then update public.emergency_requests set status = 'used', used_at = now(), used_ref = left(p_ref, 80) where id = r.id;
  elsif r.used_at is null then
    update public.emergency_requests set used_at = now(), used_ref = left(p_ref, 80) where id = r.id;
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, null, 'EMERGENCY', coalesce(p_loc, r.location_id, (select min(id) from public.locations)), (now() at time zone 'Asia/Dhaka')::date, 'emergency_window_used', 'yellow', null,
        jsonb_build_object('bn', 'জরুরি অনুমোদন ব্যবহার হয়েছে: ' || p_grant || ' · ' || coalesce(sid, ''), 'en', 'An emergency approval was used: ' || p_grant || ' · ' || coalesce(sid, '')));
  end if;
  perform set_config('bos.em_used', coalesce(current_setting('bos.em_used', true), '') || ',' || r.id || ':' || p_grant, true);
  return true;
end $$;
create or replace function public.rule_ok(p_grant text, p_loc int, p_amount numeric default null, p_date date default null, p_ref text default 'rule') returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.can_grant(p_grant) or public.use_emergency(p_grant, p_loc, p_ref, p_amount, p_date);
end $$;

-- approved requests that were never used become 'expired' when looked at
create or replace function public.my_emergency() returns table (id bigint, grant_code text, status text, reason text, decision_note text, created_at timestamptz, valid_until timestamptz, context jsonb)
language sql stable security definer set search_path = public as $$
  select r.id, r.grant_code, case when r.status = 'approved' and r.valid_until <= now() then 'expired' else r.status end, r.reason, r.decision_note, r.created_at, r.valid_until, r.context
  from public.emergency_requests r where r.requested_by = auth.uid() and r.created_at > now() - interval '2 days' order by r.id desc limit 30;
$$;

-- a short-window emergency approval also opens a form or a location for that person
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (
    public.is_active() and (exists (
      select 1 from public.user_roles ur
      join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
      join public.roles r on r.code = ur.role_code and r.active
      where ur.user_id = auth.uid()
        and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                          when 'approve' then p.can_approve else false end)
    or (p_action in ('view', 'enter') and exists (
      select 1 from public.emergency_requests e
      where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
        and p_form <> 'ITEM_COST' and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view')))));
$$;
create or replace function public.can_loc(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (
    public.is_owner()
    or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management')
    or exists (select 1 from public.user_locations where user_id = auth.uid() and location_id = p_loc)
    or exists (select 1 from public.emergency_requests e where e.requested_by = auth.uid() and e.grant_code = 'loc_access' and e.status = 'approved' and e.valid_until > now()
               and e.location_id = p_loc));
$$;

-- the printed paper number can be made mandatory for submitting a form
create or replace function public.entries_paper_required() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'submitted' and (tg_op = 'INSERT' or old.status is distinct from 'submitted') and public.rule_on('entry_paper_no_required')
     and nullif(btrim(new.data->>'paper_no'), '') is null then raise exception 'paper_no_required'; end if;
  return new;
end $$;
create trigger entries_paper_required before insert or update on public.entries for each row execute function public.entries_paper_required();

revoke all on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.use_emergency(text, int, text, numeric, date), public.rule_ok(text, int, numeric, date, text), public.my_emergency() from public, anon, authenticated;
grant execute on function public.rule_val(text), public.rule_on(text), public.rule_num(text), public.rule_txt(text), public.set_rule(text, jsonb), public.can_grant(text),
  public.set_grant(text, text, boolean), public.request_emergency(text, int, jsonb, text), public.decide_emergency(bigint, boolean, text), public.cancel_emergency(bigint),
  public.my_emergency() to authenticated;

-- ---------------------------------------------------------------- phase8.sql
-- ============================================================
-- BOS tool · Phase 8 (plan B1): masters + settings + grants + invoice templates + saved views + favourites + discount by amount OR percent.
-- Run AFTER phase7 (ALL_NEW.sql already contains phases 5-7). ADDITIVE and IDEMPOTENT: safe to run again; nothing is dropped except the
-- old 11-argument record_sale2 signature, which is replaced by the same function with two extra OPTIONAL arguments (old calls keep working).
--
-- Principles kept:
--   * no business number is invented: every new number/choice is null (= feature off) unless the owner wrote it, except safe switches
--     (vat_on false, stock_negative_mode warn, costing_method avg, ui_noperm_mode lock, both discount modes on = today's behaviour + percent).
--   * cost stays in item_costs (ITEM_COST). Nothing added to items is secret (wholesale price is a selling price).
--   * every new table has RLS; staff only read, the owner (or a person the owner granted) edits.
-- ============================================================

-- ---------- (a) lists: supplier types, customer types, units (all editable by the owner in Edit lists) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('supplier_types', 'milk', 'দুধ / ছানা', 'দুধ / ছানা', 'Milk / chhana', 1), ('supplier_types', 'sugar', 'চিনি', 'চিনি', 'Sugar', 2),
 ('supplier_types', 'packaging', 'প্যাকেজিং', 'Packaging', 'Packaging', 3), ('supplier_types', 'fuel', 'জ্বালানি', 'Fuel', 'Fuel', 4),
 ('supplier_types', 'gas', 'গ্যাস', 'Gas', 'Gas', 5), ('supplier_types', 'services', 'সেবা', 'Services', 'Services', 6),
 ('supplier_types', 'other', 'অন্যান্য', 'Other', 'Other', 9),
 ('customer_types', 'retail', 'খুচরা', 'Retail', 'Retail', 1), ('customer_types', 'wholesale', 'পাইকারি', 'Wholesale', 'Wholesale', 2),
 ('customer_types', 'party', 'পার্টি / অনুষ্ঠান', 'Party / event', 'Party / event', 3), ('customer_types', 'corporate', 'কর্পোরেট', 'Corporate', 'Corporate', 4),
 ('customer_types', 'online', 'অনলাইন', 'Online', 'Online', 5), ('customer_types', 'staff', 'স্টাফ', 'Staff', 'Staff', 6),
 ('units', 'kg', 'কেজি', 'kg', 'kg', 1), ('units', 'piece', 'পিস', 'piece', 'piece', 2), ('units', 'box', 'বক্স', 'box', 'box', 3),
 ('units', 'pack', 'প্যাক', 'pack', 'pack', 4), ('units', 'pound', 'পাউন্ড', 'pound', 'pound', 5), ('units', 'gram', 'গ্রাম', 'gram', 'gram', 6)
on conflict (list_code, value_code) do nothing;

-- customer type taken from the editable list (the old retail/wholesale column stays for the POS)
alter table public.customers add column if not exists type_code text;

-- ---------- (g) grants: new controlled actions; plus who-may per PERSON (and per location), not only per role ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('em_view_cost', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ক্রয়মূল্য দেখা', 'জরুরি request চলবে: cost দেখা', 'Emergency allowed for: seeing cost', 'Off by default', 50),
 ('em_view_profit', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: লাভ/ক্ষতি দেখা', 'জরুরি request চলবে: profit/loss দেখা', 'Emergency allowed for: seeing profit / loss', 'Off by default', 51),
 ('em_view_reports', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: রিপোর্ট দেখা', 'জরুরি request চলবে: report দেখা', 'Emergency allowed for: seeing reports', 'Off by default', 52),
 ('em_export_data', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ডেটা এক্সপোর্ট', 'জরুরি request চলবে: data export', 'Emergency allowed for: exporting data', 'Off by default', 53),
 ('em_salary_view', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: বেতন দেখা', 'জরুরি request চলবে: salary দেখা', 'Emergency allowed for: seeing salaries', 'Off by default', 54),
 ('em_supplier_manage', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: সাপ্লায়ার পরিচালনা', 'জরুরি request চলবে: supplier পরিচালনা', 'Emergency allowed for: managing suppliers', 'Off by default', 55),
 ('em_settings_invoice', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ইনভয়েস সেটিংস', 'জরুরি request চলবে: invoice settings', 'Emergency allowed for: invoice settings', 'Off by default', 56)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('view_cost', 'cost', 20, 'ক্রয়মূল্য ভিত্তিক হিসাব দেখা', 'Cost ভিত্তিক হিসাব দেখা', 'See cost-based figures', 'window', 'em_view_cost'),
 ('view_profit', 'cost', 21, 'লাভ/ক্ষতি দেখা', 'Profit/loss দেখা', 'See profit / loss', 'window', 'em_view_profit'),
 ('view_reports', 'reports', 22, 'রিপোর্ট দেখা', 'Report দেখা', 'See reports', 'window', 'em_view_reports'),
 ('export_data', 'reports', 23, 'ডেটা এক্সপোর্ট করা', 'Data export করা', 'Export data', 'once', 'em_export_data'),
 ('salary_view', 'people', 24, 'বেতন দেখা', 'Salary দেখা', 'See salaries', 'window', 'em_salary_view'),
 ('supplier_manage', 'master', 25, 'সাপ্লায়ার যোগ/বদলানো', 'Supplier যোগ/বদলানো', 'Add / change suppliers', 'window', 'em_supplier_manage'),
 ('settings_invoice', 'settings', 26, 'ইনভয়েস টেমপ্লেট ও প্রিন্ট সেটিংস বদলানো', 'Invoice template ও print settings বদলানো', 'Change invoice templates and print settings', 'window', 'em_settings_invoice')
on conflict (grant_code) do nothing;

-- a grant given to ONE PERSON (anyone, any role), for all locations (location_id null) or one, optionally until a date
create table if not exists public.user_grants (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  grant_code text not null references public.grant_defs(grant_code),
  location_id int references public.locations(id),
  valid_until timestamptz,
  note text,
  granted_by uuid, granted_at timestamptz not null default now()
);
create unique index if not exists user_grants_uq on public.user_grants (user_id, grant_code, coalesce(location_id, 0));
drop trigger if exists audit_user_grants on public.user_grants;
create trigger audit_user_grants after insert or update or delete on public.user_grants for each row execute function public.log_change('id');
alter table public.user_grants enable row level security;
drop policy if exists user_grants_read on public.user_grants;
create policy user_grants_read on public.user_grants for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.user_grants from anon, authenticated;
grant select on public.user_grants to authenticated;

-- owner gives / takes a grant to a person (p_allowed false = remove)
create or replace function public.set_user_grant(p_user uuid, p_code text, p_loc int default null, p_until timestamptz default null, p_allowed boolean default true, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_code) then raise exception 'unknown grant'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  if p_allowed then
    insert into public.user_grants (user_id, grant_code, location_id, valid_until, note, granted_by) values (p_user, p_code, p_loc, p_until, left(p_note, 200), auth.uid())
      on conflict (user_id, grant_code, coalesce(location_id, 0)) do update set valid_until = excluded.valid_until, note = excluded.note, granted_by = auth.uid(), granted_at = now();
  else
    delete from public.user_grants where user_id = p_user and grant_code = p_code and coalesce(location_id, 0) = coalesce(p_loc, 0);
  end if;
end $$;

-- may the caller do p_code (at location p_loc, or anywhere when null)?  owner · role grant · personal grant · approved emergency WINDOW (read only: nothing is consumed)
-- With p_loc null only personal grants that cover every location count; give a location to include location-limited personal grants.
-- KNOWN, DELIBERATE: an approved emergency WINDOW still counts when p_loc is null, even though request_emergency always ties a window to one
-- location (the only location-less requests are closed_period_edit / form_access, which are not windows). Making p_loc null require a
-- location-less window would switch every window approval off (supplier_manage, settings_invoice and the biz_ok / biz_cost_ok checks, whose callers
-- and RLS policies have no location to pass), so the approver's choice to open a window is what limits it: it is time boxed (em_minutes), needs the
-- em_* rule on, is decided by a second person and leaves a trace. Callers that DO have a location should pass it: has_grant(code, loc) then
-- accepts only a window for that location (or for all locations).
create or replace function public.has_grant(p_code text, p_loc int default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc))));
$$;

-- report / cost visibility now also honours the new grants (owner and the old POS-approver / ITEM_COST paths work exactly as before)
create or replace function public.biz_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve') or public.has_grant('view_reports'));
$$;
create or replace function public.biz_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost') or public.has_grant('view_profit'));
$$;

-- ---------- (e) settings keys in the existing rules table (null default = not set = feature off) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('fiscal_year_start_month', 'settings', 'number', null, null, 1, 12, 'অর্থবছর শুরুর মাস (১-১২)', 'Fiscal year শুরুর মাস (1-12)', 'Fiscal year start month (1-12)', 'Empty = calendar year', 60),
 ('fiscal_year_start_day', 'settings', 'number', null, null, 1, 31, 'অর্থবছর শুরুর দিন', 'Fiscal year শুরুর দিন', 'Fiscal year start day', 'Empty = day 1', 61),
 ('week_start', 'settings', 'choice', null, '["sat","sun","mon","tue","wed","thu","fri"]', null, null, 'সপ্তাহ শুরু হয় যে দিনে', 'Week শুরু হয় যে দিনে', 'Week starts on', 'Empty = Saturday in reports', 62),
 ('ui_noperm_mode', 'settings', 'choice', '"lock"', '["lock","hide"]', null, null, 'অনুমতি না থাকলে মডিউল: lock = তালা কার্ড, hide = লুকানো', 'Permission না থাকলে module: lock = তালা card, hide = লুকানো', 'Module without permission: lock card or hide', null, 63),
 ('barcode_camera_on', 'settings', 'switch', 'false', null, null, null, 'বারকোড: ক্যামেরা স্ক্যান চালু', 'Barcode: camera scan চালু', 'Barcode: camera scan on', 'Separate from the device option', 64),
 ('barcode_device_on', 'settings', 'switch', 'false', null, null, null, 'বারকোড: ডিভাইস/স্ক্যানার (টাইপ) চালু', 'Barcode: device scanner (typed) চালু', 'Barcode: device / hardware scanner on', 'Separate from the camera option', 65),
 ('costing_method', 'settings', 'choice', '"avg"', '["avg"]', null, null, 'ক্রয়মূল্য হিসাব পদ্ধতি', 'Costing method', 'Costing method', 'Only average for now; more can be added later', 66),
 ('discount_mode_amount_on', 'pos', 'switch', 'true', null, null, null, 'ডিসকাউন্ট: টাকার অঙ্কে দেওয়া চালু', 'Discount: amount (টাকা) চালু', 'Discount by amount is allowed', null, 67),
 ('discount_mode_percent_on', 'pos', 'switch', 'true', null, null, null, 'ডিসকাউন্ট: শতাংশে দেওয়া চালু', 'Discount: percent চালু', 'Discount by percent is allowed', 'Same limits apply (the limit is checked on the computed amount)', 68),
 ('vat_on', 'settings', 'switch', 'false', null, null, null, 'ভ্যাট চালু', 'VAT চালু', 'VAT is on', 'Off until the adviser confirms', 70),
 ('vat_rate', 'settings', 'number', null, null, 0, 100, 'ভ্যাটের হার (%)', 'VAT rate (%)', 'VAT rate (%)', 'No default: the owner enters it after the adviser answers', 71),
 ('stock_negative_mode', 'settings', 'choice', '"warn"', '["allow","warn","block"]', null, null, 'স্টকের চেয়ে বেশি বিক্রি: allow / warn / block', 'Stock এর চেয়ে বেশি sale: allow / warn / block', 'Selling more than the stock: allow, warn or block', 'Used when the stock ledger arrives (B2)', 72)
on conflict (key) do nothing;

-- fiscal-year / week helpers that follow the settings above (reports use these instead of a fixed January / Saturday)
create or replace function public.fiscal_year_start(p_date date default null) returns date
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); m int := coalesce(public.rule_num('fiscal_year_start_month'), 1)::int;
        dd int := coalesce(public.rule_num('fiscal_year_start_day'), 1)::int; y int := extract(year from d)::int; s date;
begin
  s := make_date(y, m, least(dd, extract(day from (make_date(y, m, 1) + interval '1 month - 1 day'))::int));
  if d < s then y := y - 1; s := make_date(y, m, least(dd, extract(day from (make_date(y, m, 1) + interval '1 month - 1 day'))::int)); end if;
  return s;
end $$;
create or replace function public.fiscal_year_end(p_date date default null) returns date
language sql stable security definer set search_path = public as $$
  select public.fiscal_year_start((public.fiscal_year_start(p_date) + 400)) - 1;
$$;
create or replace function public.week_start_date(p_date date default null) returns date
language sql stable security definer set search_path = public as $$
  with d as (select coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date) x),
       w as (select array_position(array['mon','tue','wed','thu','fri','sat','sun'], coalesce(public.rule_txt('week_start'), 'sat')) n)
  select (d.x - (((extract(isodow from d.x)::int - w.n) + 7) % 7))::date from d, w;
$$;

-- ---------- (a) suppliers master ----------
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  mobile text,
  type_code text,                                         -- from the editable list supplier_types
  address text,
  credit_days int check (credit_days is null or credit_days >= 0),      -- owner enters; empty = unknown
  opening_balance numeric,                                -- empty = not entered; positive = we owe the supplier
  nid text, tin text, note text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists suppliers_name on public.suppliers (lower(name));
drop trigger if exists audit_suppliers on public.suppliers;
create trigger audit_suppliers after insert or update on public.suppliers for each row execute function public.log_change('id');
alter table public.suppliers enable row level security;
drop policy if exists suppliers_read on public.suppliers;
create policy suppliers_read on public.suppliers for select to authenticated using (public.has_grant('supplier_manage'));
revoke all on public.suppliers from anon, authenticated;
grant select on public.suppliers to authenticated;

-- add (p_id null) or change a supplier; p_patch keys: name, mobile, type_code, address, credit_days, opening_balance, nid, tin, note, active
create or replace function public.save_supplier(p_id uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid := p_id; p jsonb := coalesce(p_patch, '{}');
begin
  if not public.has_grant('supplier_manage') then raise exception 'not allowed'; end if;
  if sid is null then
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    insert into public.suppliers (name, created_by) values (left(btrim(p->>'name'), 120), auth.uid()) returning id into sid;
  elsif not exists (select 1 from public.suppliers where id = sid) then raise exception 'not found';
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
end $$;

-- picker for forms: any active user sees only id, name, type of ACTIVE suppliers (no balances / ids)
create or replace function public.supplier_pick() returns table (id uuid, name text, type_code text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.type_code from public.suppliers s where public.is_active() and s.active order by lower(s.name);
$$;

-- ---------- (b) items: additive columns (all nullable / off by default; cost is NOT here) ----------
alter table public.items add column if not exists sub_category text;
alter table public.items add column if not exists base_unit text;
alter table public.items add column if not exists sell_units text[] not null default '{}';
alter table public.items add column if not exists wholesale_price numeric(12,2) check (wholesale_price is null or wholesale_price >= 0);
alter table public.items add column if not exists tracked boolean not null default false;      -- stock-tracked? off until the owner decides per item
alter table public.items add column if not exists min_stock numeric check (min_stock is null or min_stock >= 0);
alter table public.items add column if not exists barcode text;
alter table public.items add column if not exists source text check (source is null or source in ('made', 'bought'));
alter table public.items add column if not exists vat_applicable boolean;                       -- null = undecided
alter table public.items add column if not exists images text[] not null default '{}';
create unique index if not exists items_barcode_uq on public.items (barcode) where barcode is not null;

-- items are written only through the patch workflow; teach it the new columns (same signature, old patches behave as before)
create or replace function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid := p_item; cp numeric;
begin
  if iid is null then
    insert into public.items (name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active)
    values (p_patch->>'name_bn', p_patch->>'name_en', p_patch->>'name_mix', p_patch->>'category', p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price','')::numeric, coalesce((p_patch->>'is_active')::boolean, true))
    returning id into iid;
  else
    update public.items set
      name_bn = coalesce(p_patch->>'name_bn', name_bn),
      name_en = case when p_patch ? 'name_en' then p_patch->>'name_en' else name_en end,
      name_mix = case when p_patch ? 'name_mix' then p_patch->>'name_mix' else name_mix end,
      category = case when p_patch ? 'category' then p_patch->>'category' else category end,
      category_bn = case when p_patch ? 'category_bn' then p_patch->>'category_bn' else category_bn end,
      unit = case when p_patch ? 'unit' then p_patch->>'unit' else unit end,
      sell_price = case when p_patch ? 'sell_price' then nullif(p_patch->>'sell_price','')::numeric else sell_price end,
      is_active = case when p_patch ? 'is_active' then (p_patch->>'is_active')::boolean else is_active end
    where id = iid;
  end if;
  update public.items set
    sub_category = case when p_patch ? 'sub_category' then nullif(btrim(p_patch->>'sub_category'), '') else sub_category end,
    base_unit = case when p_patch ? 'base_unit' then nullif(btrim(p_patch->>'base_unit'), '') else base_unit end,
    sell_units = case when p_patch ? 'sell_units' then case when jsonb_typeof(p_patch->'sell_units') = 'array' then array(select jsonb_array_elements_text(p_patch->'sell_units')) else '{}'::text[] end else sell_units end,
    wholesale_price = case when p_patch ? 'wholesale_price' then nullif(p_patch->>'wholesale_price', '')::numeric else wholesale_price end,
    tracked = case when p_patch ? 'tracked' then coalesce((p_patch->>'tracked')::boolean, false) else tracked end,
    min_stock = case when p_patch ? 'min_stock' then nullif(p_patch->>'min_stock', '')::numeric else min_stock end,
    barcode = case when p_patch ? 'barcode' then nullif(btrim(p_patch->>'barcode'), '') else barcode end,
    source = case when p_patch ? 'source' then nullif(p_patch->>'source', '') else source end,
    vat_applicable = case when p_patch ? 'vat_applicable' then nullif(p_patch->>'vat_applicable', '')::boolean else vat_applicable end,
    images = case when p_patch ? 'images' then case when jsonb_typeof(p_patch->'images') = 'array' then array(select jsonb_array_elements_text(p_patch->'images')) else '{}'::text[] end else images end
  where id = iid and (p_patch ?| array['sub_category','base_unit','sell_units','wholesale_price','tracked','min_stock','barcode','source','vat_applicable','images']);
  if p_patch ? 'cost_price' then
    cp := nullif(p_patch->>'cost_price','')::numeric;
    insert into public.item_costs (item_id, cost_price) values (iid, cp)
      on conflict (item_id) do update set cost_price = excluded.cost_price;
  end if;
  return iid;
end $$;

-- ---------- (c) unit conversions: global (item_id null) or per item. "1 from_unit = factor to_unit" ----------
create table if not exists public.unit_conversions (
  id bigserial primary key,
  item_id uuid references public.items(id) on delete cascade,
  from_unit text not null, to_unit text not null,
  factor numeric not null check (factor > 0),
  active boolean not null default true,
  note text,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (from_unit <> to_unit)
);
create unique index if not exists unit_conv_uq on public.unit_conversions (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit);
drop trigger if exists audit_unit_conversions on public.unit_conversions;
create trigger audit_unit_conversions after insert or update or delete on public.unit_conversions for each row execute function public.log_change('id');
alter table public.unit_conversions enable row level security;
drop policy if exists unit_conv_read on public.unit_conversions;
drop policy if exists unit_conv_owner on public.unit_conversions;
create policy unit_conv_read on public.unit_conversions for select to authenticated using (public.is_active());
create policy unit_conv_owner on public.unit_conversions for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.unit_conversions from anon, authenticated;
grant select, insert, update, delete on public.unit_conversions to authenticated;
grant usage on sequence public.unit_conversions_id_seq to authenticated;

-- one hop: item rule first, then global; a rule works in both directions. null = unknown (nothing is guessed)
create or replace function public._unit_hop(p_item uuid, p_from text, p_to text) returns numeric
language sql stable security definer set search_path = public as $$
  select case when c.from_unit = p_from then c.factor else 1 / c.factor end
  from public.unit_conversions c
  where c.active and (c.item_id = p_item or c.item_id is null)
    and ((c.from_unit = p_from and c.to_unit = p_to) or (c.from_unit = p_to and c.to_unit = p_from))
  order by (c.item_id is null), (c.from_unit <> p_from) limit 1;
$$;
-- factor so that  qty_in_to = qty_in_from * factor ; tries a direct rule, then via the item's base_unit
create or replace function public.unit_factor(p_item uuid, p_from text, p_to text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare f numeric; b text; x numeric; y numeric;
begin
  if p_from is null or p_to is null then return null; end if;
  if p_from = p_to then return 1; end if;
  f := public._unit_hop(p_item, p_from, p_to);
  if f is not null then return f; end if;
  select base_unit into b from public.items where id = p_item;
  if b is not null and b <> p_from and b <> p_to then
    x := public._unit_hop(p_item, p_from, b); y := public._unit_hop(p_item, b, p_to);
    if x is not null and y is not null then return x * y; end if;
  end if;
  return null;
end $$;
create or replace function public.convert_qty(p_item uuid, p_qty numeric, p_from text, p_to text) returns numeric
language sql stable security definer set search_path = public as $$
  select p_qty * public.unit_factor(p_item, p_from, p_to);
$$;
-- owner sets / changes / removes a rule (p_factor null removes it)
create or replace function public.set_unit_conversion(p_item uuid, p_from text, p_to text, p_factor numeric, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_factor is null then
    delete from public.unit_conversions where coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_item, '00000000-0000-0000-0000-000000000000'::uuid) and from_unit = p_from and to_unit = p_to;
    return;
  end if;
  if p_factor <= 0 or p_factor = 'NaN'::numeric then raise exception 'bad_factor'; end if;
  insert into public.unit_conversions (item_id, from_unit, to_unit, factor, note, updated_by) values (p_item, p_from, p_to, p_factor, left(p_note, 200), auth.uid())
    on conflict (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit)
    do update set factor = excluded.factor, note = excluded.note, active = true, updated_at = now(), updated_by = auth.uid();
end $$;

-- ---------- (d) shelf life rules: per item or category (or everything), optionally for a season (month-day range, may wrap the year end) ----------
create table if not exists public.shelf_life_rules (
  id bigserial primary key,
  item_id uuid references public.items(id) on delete cascade,
  category text,                                          -- matches items.category
  season_label text,
  start_month smallint check (start_month between 1 and 12), start_day smallint check (start_day between 1 and 31),
  end_month smallint check (end_month between 1 and 12), end_day smallint check (end_day between 1 and 31),
  value numeric not null check (value > 0),
  unit text not null check (unit in ('hours', 'days')),
  active boolean not null default true,
  note text,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (item_id is null or category is null),
  check ((start_month is null and start_day is null and end_month is null and end_day is null)
      or (start_month is not null and start_day is not null and end_month is not null and end_day is not null))
);
drop trigger if exists audit_shelf_life_rules on public.shelf_life_rules;
create trigger audit_shelf_life_rules after insert or update or delete on public.shelf_life_rules for each row execute function public.log_change('id');
alter table public.shelf_life_rules enable row level security;
drop policy if exists shelf_read on public.shelf_life_rules;
drop policy if exists shelf_owner on public.shelf_life_rules;
create policy shelf_read on public.shelf_life_rules for select to authenticated using (public.is_active());
create policy shelf_owner on public.shelf_life_rules for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.shelf_life_rules from anon, authenticated;
grant select, insert, update, delete on public.shelf_life_rules to authenticated;
grant usage on sequence public.shelf_life_rules_id_seq to authenticated;

-- the most specific active rule for an item on a date:  item+season > item > category+season > category > everything+season > everything.
-- Among seasons, the shorter range wins, then the newer rule. No rule at all -> null (feature off).
create or replace function public.shelf_life_for(p_item uuid, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); md int := extract(month from d)::int * 100 + extract(day from d)::int;
        it public.items; r public.shelf_life_rules;
begin
  select * into it from public.items where id = p_item;
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
end $$;
create or replace function public.shelf_life_hours(p_item uuid, p_date date default null) returns numeric
language sql stable security definer set search_path = public as $$
  select (public.shelf_life_for(p_item, p_date) ->> 'hours')::numeric;
$$;

-- ---------- (f) invoice templates and print profiles ----------
create table if not exists public.invoice_templates (
  id bigserial primary key,
  name text not null check (length(btrim(name)) > 0),
  kind text not null check (kind in ('a4', 'thermal58', 'thermal80', 'label', 'common')),
  header jsonb not null default '{}',                    -- per language: {"bn": "...", "mix": "...", "en": "..."}
  footer jsonb not null default '{}',
  show_flags jsonb not null default '{}',               -- e.g. {"logo":true,"customer":true,"receipt_no":true,"item_code":false,"discount":true,"barcode":false}
  logo_ref text,                                         -- storage path or url
  vat_line_on boolean not null default false,           -- a printed VAT line also needs the rule vat_on
  paper_width_mm numeric check (paper_width_mm is null or paper_width_mm > 0),
  margins jsonb not null default '{}',                   -- {"top":..,"right":..,"bottom":..,"left":..} mm
  font_scale numeric not null default 1 check (font_scale > 0),
  location_id int references public.locations(id),      -- null = all locations
  is_default boolean not null default false,            -- the default of its kind for its location (or for all)
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
create unique index if not exists invoice_templates_default_uq on public.invoice_templates (kind, coalesce(location_id, 0)) where is_default and active;
drop trigger if exists audit_invoice_templates on public.invoice_templates;
create trigger audit_invoice_templates after insert or update or delete on public.invoice_templates for each row execute function public.log_change('id');

create table if not exists public.print_profiles (
  id bigserial primary key,
  name text not null check (length(btrim(name)) > 0),
  location_id int references public.locations(id),      -- null = all
  device_key text,                                       -- a device name the app stores; null = any device
  printer_type text not null check (printer_type in ('a4', 'thermal', 'label', 'other')),
  paper_size text,                                       -- free text from an editable list, e.g. A4 / 58mm / 80mm
  paper_width_mm numeric check (paper_width_mm is null or paper_width_mm > 0),
  template_id bigint references public.invoice_templates(id) on delete set null,
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
drop trigger if exists audit_print_profiles on public.print_profiles;
create trigger audit_print_profiles after insert or update or delete on public.print_profiles for each row execute function public.log_change('id');

alter table public.invoice_templates enable row level security;
alter table public.print_profiles enable row level security;
drop policy if exists invtpl_read on public.invoice_templates;
drop policy if exists invtpl_write on public.invoice_templates;
drop policy if exists printprof_read on public.print_profiles;
drop policy if exists printprof_write on public.print_profiles;
create policy invtpl_read on public.invoice_templates for select to authenticated using (public.is_active());
create policy invtpl_write on public.invoice_templates for all to authenticated using (public.has_grant('settings_invoice')) with check (public.has_grant('settings_invoice'));
create policy printprof_read on public.print_profiles for select to authenticated using (public.is_active());
create policy printprof_write on public.print_profiles for all to authenticated using (public.has_grant('settings_invoice')) with check (public.has_grant('settings_invoice'));
revoke all on public.invoice_templates, public.print_profiles from anon, authenticated;
grant select, insert, update, delete on public.invoice_templates, public.print_profiles to authenticated;
grant usage on sequence public.invoice_templates_id_seq, public.print_profiles_id_seq to authenticated;

-- the template to print with: the location's default of that kind, else the all-location default, else null
create or replace function public.template_for(p_kind text, p_loc int) returns public.invoice_templates
language sql stable security definer set search_path = public as $$
  select t.* from public.invoice_templates t
  where public.is_active() and t.active and t.is_default and t.kind = p_kind and (t.location_id = p_loc or t.location_id is null)
  order by (t.location_id is null) limit 1;
$$;

-- ---------- (h) saved report views, (i) favourites ----------
create table if not exists public.report_views (
  id bigserial primary key,
  owner_id uuid not null default auth.uid(),
  name text not null check (length(btrim(name)) > 0),
  report_code text not null,
  params jsonb not null default '{}',                    -- filters / grouping / period the view remembers (no data is stored)
  shared boolean not null default false,                 -- shared = every active user may open the view (the report's own access still applies)
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists report_views_owner on public.report_views (owner_id, report_code);
drop trigger if exists audit_report_views on public.report_views;
create trigger audit_report_views after insert or update or delete on public.report_views for each row execute function public.log_change('id');
alter table public.report_views enable row level security;
drop policy if exists rv_read on public.report_views;
drop policy if exists rv_ins on public.report_views;
drop policy if exists rv_upd on public.report_views;
drop policy if exists rv_del on public.report_views;
create policy rv_read on public.report_views for select to authenticated using (owner_id = auth.uid() or (shared and public.is_active()) or public.is_owner());
create policy rv_ins on public.report_views for insert to authenticated with check (owner_id = auth.uid() and public.is_active());
create policy rv_upd on public.report_views for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy rv_del on public.report_views for delete to authenticated using (owner_id = auth.uid() or public.is_owner());
revoke all on public.report_views from anon, authenticated;
grant select, insert, update, delete on public.report_views to authenticated;
grant usage on sequence public.report_views_id_seq to authenticated;

create table if not exists public.user_favourites (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null,                                    -- form | report | item | module ...
  key text not null,
  pinned boolean not null default false,
  uses int not null default 0 check (uses >= 0),
  last_used timestamptz,
  primary key (user_id, kind, key)
);
alter table public.user_favourites enable row level security;
drop policy if exists fav_own on public.user_favourites;
create policy fav_own on public.user_favourites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.user_favourites from anon, authenticated;
grant select, insert, update, delete on public.user_favourites to authenticated;

-- count one use (most-used list) / pin or unpin
create or replace function public.touch_favourite(p_kind text, p_key text) returns void
language sql security definer set search_path = public as $$
  insert into public.user_favourites (user_id, kind, key, uses, last_used) select auth.uid(), left(p_kind, 40), left(p_key, 120), 1, now() where public.is_active()
  on conflict (user_id, kind, key) do update set uses = public.user_favourites.uses + 1, last_used = now();
$$;
create or replace function public.set_pin(p_kind text, p_key text, p_pinned boolean) returns void
language sql security definer set search_path = public as $$
  insert into public.user_favourites (user_id, kind, key, pinned) select auth.uid(), left(p_kind, 40), left(p_key, 120), coalesce(p_pinned, false) where public.is_active()
  on conflict (user_id, kind, key) do update set pinned = coalesce(p_pinned, false);
$$;

-- owner-set defaults per role (shown in front for anyone with that role until they pin their own)
create table if not exists public.role_favourites (
  role_code text not null references public.roles(code) on delete cascade,
  kind text not null, key text not null, sort int not null default 0,
  primary key (role_code, kind, key)
);
alter table public.role_favourites enable row level security;
drop policy if exists rolefav_read on public.role_favourites;
drop policy if exists rolefav_owner on public.role_favourites;
create policy rolefav_read on public.role_favourites for select to authenticated using (public.is_active());
create policy rolefav_owner on public.role_favourites for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.role_favourites from anon, authenticated;
grant select, insert, update, delete on public.role_favourites to authenticated;

-- ---------- (j) discount by amount OR percent ----------
alter table public.sales add column if not exists discount_kind text check (discount_kind is null or discount_kind in ('amount', 'percent'));
alter table public.sales add column if not exists discount_input numeric check (discount_input is null or discount_input >= 0);   -- what was typed: the amount, or the percent

-- the old 11-argument signature is replaced by the same function with two OPTIONAL trailing arguments (old calls resolve to it unchanged)
drop function if exists public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz);

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
begin
  perform set_config('bos.em_used', '', true);
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
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
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
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > 0 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
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
  if disc > 0 then
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

-- ---------- privileges: every new function is closed first, then opened to signed-in users only ----------
revoke all on function public.set_user_grant(uuid, text, int, timestamptz, boolean, text), public.has_grant(text, int),
  public.biz_ok(), public.biz_cost_ok(),
  public.fiscal_year_start(date), public.fiscal_year_end(date), public.week_start_date(date),
  public.save_supplier(uuid, jsonb), public.supplier_pick(), public.apply_item_patch(uuid, jsonb),
  public._unit_hop(uuid, text, text), public.unit_factor(uuid, text, text), public.convert_qty(uuid, numeric, text, text),
  public.set_unit_conversion(uuid, text, text, numeric, text), public.shelf_life_for(uuid, date), public.shelf_life_hours(uuid, date),
  public.template_for(text, int), public.touch_favourite(text, text), public.set_pin(text, text, boolean),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric) from public, anon, authenticated;
grant execute on function public.set_user_grant(uuid, text, int, timestamptz, boolean, text), public.has_grant(text, int),
  public.biz_ok(), public.biz_cost_ok(),
  public.fiscal_year_start(date), public.fiscal_year_end(date), public.week_start_date(date),
  public.save_supplier(uuid, jsonb), public.supplier_pick(),
  public.unit_factor(uuid, text, text), public.convert_qty(uuid, numeric, text, text),
  public.set_unit_conversion(uuid, text, text, numeric, text), public.shelf_life_for(uuid, date), public.shelf_life_hours(uuid, date),
  public.template_for(text, int), public.touch_favourite(text, text), public.set_pin(text, text, boolean),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric) to authenticated;
-- apply_item_patch and _unit_hop stay internal (called by other security-definer functions only)

-- phase9 (reports) shows the discount kind of a sale through two views; rebuild them now that the discount columns exist, whichever file ran first
do $$ begin
  if to_regprocedure('public.rpt_views_refresh()') is not null then perform public.rpt_views_refresh(); end if;
end $$;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase9.sql
-- ============================================================
-- BOS tool · Phase 9: REPORT ENGINE core + the P1 reports that need no new data capture.
-- Run AFTER phase3/4/5/6/7 (ALL_NEW.sql). Additive and idempotent: safe to run again. Nothing existing is changed or dropped.
-- Does not depend on phase8, and works in EITHER order: optional phase8 columns (sales.discount_kind / discount_input) and grants
-- (has_grant, view_cost, view_reports ...) are detected when used. The two views that show the discount kind are (re)built by
-- rpt_views_refresh(); phase8 calls it at its end when phase9 is already there, and phase9 calls it below, so the order does not matter.
--
-- What is here
--   report_brand_map   location -> brand (owner editable; brand is not stored on sales)
--   rpt_bill / rpt_daily / sales_fact / rpt_pay   read-only fact views (NOT readable by the app: only report_run reads them)
--   report_presets()   date presets; a preset that needs a missing rule (fiscal year, week start) is returned as null
--   report_catalog()   the list of reports for the UI (names, group, grant, filters, dims, measures)
--   report_run(key, filters, group, sort, page, compare)   ONE server function; user input never becomes SQL
--                      (keys are looked up in a fixed whitelist; values are quoted with %L after type checks)
--
-- Security
--   * every call needs the grant report_<group> or the phase8 grant view_reports (owner always may; the owner edits them in "Who may do what")
--   * rows are limited to can_loc() locations, always
--   * cost columns (cogs, gp, gp_pct, uncosted_pct) are not even computed unless owner / ITEM_COST view / grant view_cost
--   * customer mobile numbers are masked unless owner / POS approve / grant view_customer_mobile
--   * thresholds are RULES with no invented value. Fiscal year start (month + day) and week start are the phase8 settings
--     fiscal_year_start_month / fiscal_year_start_day / week_start (sun..sat) and use exactly the fallbacks phase8 documents
--     (calendar year, Saturday); the old phase9 draft rule week_start_dow is read only when week_start is empty. Aging buckets,
--     near-limit % and page size have no value: missing -> the result says "data needed" (page size: documented 50).
-- ============================================================

create index if not exists sales_date_loc on public.sales (sale_date, location_id);
create index if not exists exceptions_sale on public.exceptions (sale_id) where sale_id is not null;
create index if not exists sale_payments_paid_at on public.sale_payments (paid_at);
create index if not exists sale_payments_sale on public.sale_payments (sale_id) where sale_id is not null;

-- ---------- brand of a location (sales do not store a brand; the owner maps locations to brands) ----------
create table if not exists public.report_brand_map (
  location_id int primary key references public.locations(id),
  brand_code text not null,
  brand_bn text not null,
  brand_en text not null
);
alter table public.report_brand_map enable row level security;
revoke all on public.report_brand_map from public, anon;
grant select, insert, update, delete on public.report_brand_map to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_read') then
    create policy report_brand_map_read on public.report_brand_map for select to authenticated using (public.is_active());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_owner') then
    create policy report_brand_map_owner on public.report_brand_map for all to authenticated using (public.is_owner()) with check (public.is_owner());
  end if;
end $$;
-- the three brands named in the guidebook (docs/LANGUAGE.md); factories and the godown are left UNMAPPED on purpose (owner decides)
insert into public.report_brand_map (location_id, brand_code, brand_bn, brand_en)
  select l.id, v.b, v.bn, v.en from public.locations l join (values
    ('main', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('branch2', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('mishti_bari', 'misty_bari', 'মিষ্টি বাড়ি', 'MISTY BARI'),
    ('al_cakes', 'al_cakiz', 'AL-CAKIZ', 'AL-CAKIZ')) v(code, b, bn, en) on v.code = l.code
  on conflict (location_id) do nothing;

-- ---------- rules ----------
-- The three settings below are IDENTICAL to the rows phase8 inserts (same module, labels, hints), so "on conflict do nothing" is harmless in either order.
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('fiscal_year_start_month', 'settings', 'number', null, null, 1, 12, 'অর্থবছর শুরুর মাস (১-১২)', 'Fiscal year শুরুর মাস (1-12)', 'Fiscal year start month (1-12)', 'Empty = calendar year', 60),
 ('fiscal_year_start_day', 'settings', 'number', null, null, 1, 31, 'অর্থবছর শুরুর দিন', 'Fiscal year শুরুর দিন', 'Fiscal year start day', 'Empty = day 1', 61),
 ('week_start', 'settings', 'choice', null, '["sat","sun","mon","tue","wed","thu","fri"]', null, null, 'সপ্তাহ শুরু হয় যে দিনে', 'Week শুরু হয় যে দিনে', 'Week starts on', 'Empty = Saturday in reports', 62)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('report_aging_buckets', 'reports', 'text', null, 'দিন', null, null, 'বাকির বয়স ভাগ (দিন, কমা দিয়ে, যেমন 7,30,60)', 'বাকির বয়স bucket (দিন, comma দিয়ে)', 'Receivable aging buckets in days, comma separated (e.g. 7,30,60)', 'ফাঁকা থাকলে বয়স ভাগ দেখাবে না', 'Empty = no aging buckets are shown', 62),
 ('report_near_limit_pct', 'reports', 'number', null, '%', 1, 1000, 'ক্রেডিট সীমার কত % হলে "সীমার কাছে" ধরা হবে', 'Credit limit এর কত % হলে "কাছাকাছি"', 'Share of the credit limit that counts as "near the limit"', 'ফাঁকা থাকলে "কাছাকাছি" দেখানো হবে না', 'Empty = no "near" status is shown', 63),
 ('report_page_size', 'reports', 'number', null, 'সারি', 10, 200, 'রিপোর্টের এক পাতায় কত সারি (ফাঁকা = ৫০)', 'Report এক পাতায় কত row (ফাঁকা = 50)', 'Rows per report page (empty = 50)', null, null, 64)
 on conflict (key) do nothing;
-- the first phase9 draft had its own week_start_dow rule; it is replaced by week_start. An unused row is removed; one the owner filled stays as a fallback only.
delete from public.rules where key = 'week_start_dow' and value is null;

-- ---------- grants: who may open which report group (owner always may; the owner edits these) ----------
-- Seeded ONLY when the grant does not exist yet: running this file again never brings back a grant the owner removed from a role.
do $$
declare r record;
begin
  for r in select * from (values
    ('report_sales', 60, 'রিপোর্ট: বিক্রি', 'Report: Sales', 'Reports: Sales'),
    ('report_pos', 61, 'রিপোর্ট: POS (দিনশেষ, বাতিল, কুইক)', 'Report: POS (day close, voids, quick)', 'Reports: POS (day close, voids, quick sales)'),
    ('report_cash', 62, 'রিপোর্ট: পেমেন্ট ও ওয়ালেট', 'Report: Payments & wallets', 'Reports: Payments and wallets'),
    ('report_customers', 63, 'রিপোর্ট: গ্রাহক ও বাকি', 'Report: Customers & dues', 'Reports: Customers and dues')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
        values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
      -- start the same as today: whoever may approve on the POS form gets the report grants (the owner can change this at any time)
      insert into public.rule_grants (grant_code, role_code)
        select r.code, p.role_code from public.role_form_perms p where p.form_code = 'POS' and p.can_approve
        on conflict do nothing;
    end if;
  end loop;
end $$;

-- one row per sale LINE, kept by a trigger (the json is parsed once, when the sale is written, not on every report).
-- The bill discount is spread over the lines in proportion to their amount (net). NO cost columns anywhere in here.
create table if not exists public.sales_fact_t (
  sale_id uuid not null references public.sales(id) on delete cascade, line_no int not null,
  receipt int, day date not null, sold_at timestamptz not null, location_id int not null,
  staff text, status text, sale_type text, pay_mode text, customer_id uuid,
  item_id uuid, line_name text, line_unit text, line_kind text,
  qty numeric, price numeric, gross numeric, net numeric, disc numeric, override boolean,
  sale_total numeric, sale_discount numeric,      -- (older drafts also stored discount_kind / discount_pct here: no longer filled, the views read them from sales)
  first_of_item boolean,      -- first line of this item (or custom name) in its sale: makes "bills per item" a cheap count
  primary key (sale_id, line_no)
);
alter table public.sales_fact_t add column if not exists first_of_item boolean;
delete from public.sales_fact_t where first_of_item is null;      -- facts of an older draft are derived data: reloaded below
create index if not exists sales_fact_t_day on public.sales_fact_t (day, location_id);
create index if not exists sales_fact_t_item on public.sales_fact_t (item_id, day) where item_id is not null;
alter table public.sales_fact_t enable row level security;     -- no policy: nobody reads it directly
revoke all on public.sales_fact_t from public, anon, authenticated;

-- ---------- fact views ----------
-- rpt_bill and sales_fact show the discount kind / percent of a sale. Those come from the phase8 columns sales.discount_kind and
-- sales.discount_input, read LIVE from sales (nothing is copied into the facts, so old facts are never stale and no rebuild is needed).
--   kind    = 'none' when the sale has no discount, else its stored kind (a discount from before phase8 is 'amount')
--   percent = the typed percent when kind is 'percent', else null
-- If phase8 is not there yet the two columns are null ('n/a' in the report). rpt_views_refresh() (re)builds the two views; it is called
-- here and at the end of phase8, so applying the files in either order (or again) gives the same result.
create or replace function public.rpt_views_refresh() returns void
language plpgsql set search_path = public as $v$
declare dk text := 'null::text'; dp text := 'null::numeric';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_kind') then
    dk := 'case when s.discount > 0 then coalesce(s.discount_kind, ''amount'') else ''none'' end';
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_input') then
      dp := 'case when s.discount > 0 and s.discount_kind = ''percent'' then s.discount_input end';
    end if;
  end if;

  -- one row per sale (all statuses). Money columns bills/gross/discount/net/paid/due count only done sales; *_raw / total are as stored.
  execute $q$
  create or replace view public.rpt_bill as
  select s.id as sale_id, s.receipt, s.sale_date as day, s.sold_at,
    extract(hour from s.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from s.sale_date)::int as dow,
    s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    s.created_staff as staff, s.status, s.pay_mode, s.sale_type, s.customer_id, cu.name as customer_name, cu.mobile, s.quick,
    s.subtotal, s.discount as discount_raw, s.total, s.paid as paid_raw, s.due_amount as due_raw,
    (s.status = 'done')::int as bills, (s.status = 'void')::int as void_bills,
    case when s.status = 'done' then s.subtotal else 0 end as gross,
    case when s.status = 'done' then s.discount else 0 end as discount,
    case when s.status = 'done' then s.total else 0 end as net,
    case when s.status = 'done' then s.paid else 0 end as paid,
    case when s.status = 'done' then s.due_amount else 0 end as due,
    (s.status = 'done' and s.quick)::int as quick_bills,
    case when s.status = 'void' then s.total else 0 end as void_amt,
    (s.status = 'done' and s.discount > 0)::int as disc_bills,
    s.void_staff, s.void_note, s.void_at,
    case when s.status = 'done' then coalesce(x.ov, 0) else 0 end as override_lines,
    case when s.status = 'done' then coalesce(x.cu_, 0) else 0 end as custom_lines,
    case when s.status = 'done' then coalesce(x.qk, 0) else 0 end as quick_lines,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct,
    case when s.status = 'done' and coalesce(ex.ol, false) then 1 else 0 end as over_limit_bills,
    case when s.status = 'done' and coalesce(ex.nl, false) then 1 else 0 end as no_limit_bills
  from public.sales s
  join public.locations lo on lo.id = s.location_id
  left join public.report_brand_map bm on bm.location_id = s.location_id
  left join public.customers cu on cu.id = s.customer_id
  left join (select sale_id, bool_or(flag_code = 'discount_over_limit') as ol, bool_or(flag_code = 'discount_no_limit') as nl
             from public.exceptions where sale_id is not null group by sale_id) ex on ex.sale_id = s.id
  left join lateral (
    select count(*) filter (where e->>'override' = 'true') as ov,
           count(*) filter (where e->>'custom' = 'true') as cu_,
           count(*) filter (where nullif(e->>'item_id', '') is null and coalesce(e->>'custom', '') <> 'true') as qk
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e) x on true $q$;

  execute $q$
  create or replace view public.sales_fact as
  select t.sale_id, t.line_no, t.receipt, t.day, t.sold_at,
    extract(hour from t.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from t.day)::int as dow,
    t.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    t.staff, t.status, t.sale_type, t.pay_mode, t.customer_id,
    t.item_id, it.code as item_code,
    coalesce(it.name_bn, t.line_name, 'Quick sale') as item_name,
    coalesce(it.name_en, it.name_bn, t.line_name, 'Quick sale') as item_name_en,
    it.category, coalesce(it.unit, t.line_unit) as unit,
    t.line_kind, t.qty, t.price, t.gross, t.net, t.disc, t.override, t.sale_total, t.sale_discount,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct, t.first_of_item
  from public.sales_fact_t t
  left join public.sales s on s.id = t.sale_id
  join public.locations lo on lo.id = t.location_id
  left join public.report_brand_map bm on bm.location_id = t.location_id
  left join public.items it on it.id = t.item_id $q$;
  revoke all on public.rpt_bill, public.sales_fact from public, anon, authenticated;      -- a rebuilt view must never be readable by the app
end $v$;
revoke all on function public.rpt_views_refresh() from public, anon, authenticated;
do $$ begin perform public.rpt_views_refresh(); end $$;

-- the day x location x staff x payment mode x sale type rollup (a plain grouped view: no lines, no customer, fast on a phone)
create or replace view public.rpt_daily as
select s.sale_date as day, s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff as staff, s.pay_mode, s.sale_type,
  count(*) filter (where s.status = 'done') as bills,
  count(*) filter (where s.status = 'void') as void_bills,
  coalesce(sum(s.subtotal) filter (where s.status = 'done'), 0) as gross,
  coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as discount,
  coalesce(sum(s.total) filter (where s.status = 'done'), 0) as net,
  coalesce(sum(s.paid) filter (where s.status = 'done'), 0) as paid,
  coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as due,
  count(*) filter (where s.status = 'done' and s.quick) as quick_bills,
  coalesce(sum(s.total) filter (where s.status = 'void'), 0) as void_amt,
  count(*) filter (where s.status = 'done' and s.discount > 0) as disc_bills
from public.sales s
join public.locations lo on lo.id = s.location_id
left join public.report_brand_map bm on bm.location_id = s.location_id
group by s.sale_date, s.location_id, lo.name_bn, lo.name_en, bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff, s.pay_mode, s.sale_type;


-- loads the line facts of one sale (or, with null, of every sale that has none yet). Cast-safe: bad json gives null/0, never an error.
create or replace function public.rpt_fact_load(p_sale uuid) returns void
language sql security definer set search_path = public as $f$
  insert into public.sales_fact_t (sale_id, line_no, receipt, day, sold_at, location_id, staff, status, sale_type, pay_mode, customer_id,
    item_id, line_name, line_unit, line_kind, qty, price, gross, net, disc, override, sale_total, sale_discount, first_of_item)
  select s.id, e.ord::int, s.receipt, s.sale_date, s.sold_at, s.location_id, s.created_staff, s.status, s.sale_type, s.pay_mode, s.customer_id,
    it.id, nullif(e.v->>'name', ''), nullif(e.v->>'unit', ''),
    case when it.id is not null then 'listed' when e.v->>'custom' = 'true' then 'unlisted' else 'quick' end,
    q.qty, q.price, q.amount, q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end,
    q.amount - q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end,
    (e.v->>'override' = 'true'), s.total, s.discount,
    (row_number() over (partition by s.id, q.iid, e.v->>'name' order by e.ord) = 1)
  from public.sales s
  cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality as e(v, ord)
  cross join lateral (select
      case when e.v->>'item_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.v->>'item_id')::uuid end as iid,
      case when e.v->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'qty')::numeric end as qty,
      case when e.v->>'price' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'price')::numeric end as price,
      case when e.v->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'amount')::numeric else 0 end as amount) q
  left join public.items it on it.id = q.iid
  where (p_sale is not null and s.id = p_sale)
     or (p_sale is null and not exists (select 1 from public.sales_fact_t t where t.sale_id = s.id))
  on conflict (sale_id, line_no) do nothing;
$f$;

create or replace function public.rpt_fact_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin      -- a problem here must never stop a sale from being saved; report_fact_rebuild() repairs the facts
    if tg_op = 'UPDATE' then delete from public.sales_fact_t where sale_id = new.id; end if;
    perform public.rpt_fact_load(new.id);
  exception when others then
    raise warning 'rpt_fact: % (sale %)', sqlerrm, new.id;
  end;
  return null;
end $$;
drop trigger if exists rpt_fact on public.sales;
do $t$      -- the discount columns are in the 'update of' list when they exist (phase8); the facts do not store them, so this is only to be complete
declare extra text := '';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_kind') then extra := extra || ', discount_kind'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_input') then extra := extra || ', discount_input'; end if;
  execute 'create trigger rpt_fact after insert or update of lines, status, subtotal, discount, total, location_id, sale_date, sold_at, created_staff, customer_id, sale_type, pay_mode'
    || extra || ' on public.sales for each row execute function public.rpt_fact_trg()';
end $t$;

-- the owner can rebuild the facts from the sales at any time (derived data only; sales are never touched)
create or replace function public.report_fact_rebuild() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  delete from public.sales_fact_t;
  perform public.rpt_fact_load(null);
  select count(*) into n from public.sales_fact_t;
  return jsonb_build_object('fact_rows', n, 'sales', (select count(*) from public.sales));
end $$;

do $$ begin perform public.rpt_fact_load(null); end $$;      -- back-fill existing sales (does nothing for sales that already have facts)

-- one row per payment (sale payments and later collections)
create or replace view public.rpt_pay as
select p.id as pay_id, p.sale_id, (p.paid_at at time zone 'Asia/Dhaka')::date as day, p.paid_at,
  extract(hour from p.paid_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (p.paid_at at time zone 'Asia/Dhaka')::date)::int as dow,
  p.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  p.created_staff as staff, p.kind, p.mode, p.wallet, p.ref, p.amount, p.voided,
  p.customer_id, cu.name as customer_name, cu.mobile
from public.sale_payments p
join public.locations lo on lo.id = p.location_id
left join public.report_brand_map bm on bm.location_id = p.location_id
left join public.customers cu on cu.id = p.customer_id;

revoke all on public.rpt_bill, public.rpt_daily, public.sales_fact, public.rpt_pay from public, anon, authenticated;
revoke all on function public.rpt_fact_load(uuid), public.rpt_fact_trg() from public, anon, authenticated;
revoke all on function public.report_fact_rebuild() from public, anon;
grant execute on function public.report_fact_rebuild() to authenticated;

-- ---------- permission helpers ----------
-- rpt_grant: the phase8 has_grant(code) (owner, role grant, personal grant, approved emergency window) when phase8 is installed, else the role grant
-- can_grant(code). A grant code that does not exist is simply false.
create or replace function public.rpt_grant(p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regprocedure('public.has_grant(text,integer)') is not null then return public.has_grant(p); end if;
  return public.can_grant(p);
end $$;
-- a report group is open to: the owner, a holder of report_<group>, or a holder of view_reports (the same grant that opens biz_ok)
create or replace function public.rpt_access(p_group text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_' || p_group) or public.rpt_grant('view_reports'));
$$;
-- cost: owner, ITEM_COST view, or the grants view_cost / view_profit (same as phase8 biz_cost_ok)
create or replace function public.rpt_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.rpt_grant('view_cost') or public.rpt_grant('view_profit'));
$$;
create or replace function public.rpt_mobile_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve') or public.rpt_grant('view_customer_mobile'));
$$;

-- ---------- small parsers: bad input raises 'bad_filter' and never reaches SQL as text ----------
create or replace function public.rpt_arr_text(j jsonb) returns text[]
language plpgsql immutable set search_path = public as $$
declare a text[];
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  if jsonb_typeof(j) = 'array' then
    if jsonb_array_length(j) > 200 then raise exception 'bad_filter'; end if;
    select coalesce(array_agg(e), '{}') into a from jsonb_array_elements_text(j) e;
  else a := array[j #>> '{}']; end if;
  if exists (select 1 from unnest(a) x where length(x) > 100) then raise exception 'bad_filter'; end if;
  if cardinality(a) = 0 then return null; end if;
  return a;
end $$;
create or replace function public.rpt_arr_int(j jsonb) returns int[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9]{1,9}$') then raise exception 'bad_filter'; end if;
  return a::int[];
end $$;
create or replace function public.rpt_arr_uuid(j jsonb) returns uuid[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_filter'; end if;
  return a::uuid[];
end $$;
create or replace function public.rpt_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare t text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  t := j #>> '{}';
  if t !~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then raise exception 'bad_filter'; end if;
  return t::numeric;
end $$;
create or replace function public.rpt_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) = '' then return null; end if;
  if t !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_filter'; end if;
  return t::date;
exception when others then raise exception 'bad_filter';
end $$;

-- ---------- week / fiscal-year settings: the phase8 rules, with the fallbacks phase8 documents ----------
--   week_start (sun..sat)            -> day of week 0..6.  Empty -> the old draft rule week_start_dow (only if the owner filled it) -> Saturday
--   fiscal_year_start_month / _day   -> Empty month = calendar year (1), empty day = 1.  A day past the month end is cut to the last day.
-- The fiscal start is passed around as ONE int: month * 100 + day (e.g. 701 = 1 July). src tells whether a fallback was used.
create or replace function public.rpt_week_cfg() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i int := array_position(array['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'], lower(btrim(coalesce(public.rule_txt('week_start'), ''))));
        n numeric;
begin
  if i is not null then return jsonb_build_object('dow', i - 1, 'src', 'rule'); end if;
  n := public.rule_num('week_start_dow');
  if n is not null and n between 0 and 6 and n = trunc(n) then return jsonb_build_object('dow', n::int, 'src', 'legacy'); end if;
  return jsonb_build_object('dow', 6, 'src', 'fallback');
end $$;
create or replace function public.rpt_fy_cfg() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m numeric := public.rule_num('fiscal_year_start_month'); d numeric := public.rule_num('fiscal_year_start_day'); mm int; dd int;
begin
  mm := case when m between 1 and 12 and m = trunc(m) then m::int end;
  dd := case when d between 1 and 31 and d = trunc(d) then d::int end;
  return jsonb_build_object('code', coalesce(mm, 1) * 100 + coalesce(dd, 1), 'src', case when mm is null then 'fallback' else 'rule' end);
end $$;
-- first day of the fiscal year that contains p_date (p_code = month * 100 + day)
create or replace function public.rpt_fy_start(p_date date, p_code int) returns date
language sql immutable set search_path = public as $$
  select case when p_date < a.s then b.s else a.s end
  from (select extract(year from p_date)::int as y, (p_code / 100) as m, (p_code % 100) as d) v
  cross join lateral (select make_date(v.y, v.m, least(v.d, extract(day from (make_date(v.y, v.m, 1) + interval '1 month - 1 day'))::int)) as s) a
  cross join lateral (select make_date(v.y - 1, v.m, least(v.d, extract(day from (make_date(v.y - 1, v.m, 1) + interval '1 month - 1 day'))::int)) as s) b;
$$;

-- ---------- date presets ----------
create or replace function public.report_presets() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Dhaka')::date; ws int := (public.rpt_week_cfg() ->> 'dow')::int; fc int := (public.rpt_fy_cfg() ->> 'code')::int;
  wk date := t - ((extract(dow from t)::int - ws + 7) % 7); fs date := public.rpt_fy_start(t, fc); ms date := date_trunc('month', t)::date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'today', jsonb_build_object('from', t, 'to', t),
    'yesterday', jsonb_build_object('from', t - 1, 'to', t - 1),
    'last_7', jsonb_build_object('from', t - 6, 'to', t),
    'last_30', jsonb_build_object('from', t - 29, 'to', t),
    'this_month', jsonb_build_object('from', ms, 'to', t),
    'last_month', jsonb_build_object('from', (ms - interval '1 month')::date, 'to', ms - 1),
    'this_week', jsonb_build_object('from', wk, 'to', t),
    'last_week', jsonb_build_object('from', wk - 7, 'to', wk - 1),
    'this_fy', jsonb_build_object('from', fs, 'to', t),
    'last_fy', jsonb_build_object('from', public.rpt_fy_start(fs - 1, fc), 'to', fs - 1));
end $$;

-- ============================================================
-- THE WHITELIST CATALOGUE. Every expression that can ever appear in a report query is written here, once.
-- Tokens: {T} table alias, {D} the (possibly shifted) day, {WS} week start (0=Sun), {FYC} fiscal start (month * 100 + day), {MOBOK} mobile visible.
-- ============================================================
create or replace function public.rpt_dims(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select $c${
   "day":{"time":1,"daily":1,"cols":[["day","{D}","দিন","Day","date"]]},
   "week":{"time":1,"daily":1,"need":"ws","cols":[["week","({D} - ((extract(dow from {D})::int - {WS} + 7) % 7))::date","সপ্তাহ (শুরুর দিন)","Week starting","date"]]},
   "month":{"time":1,"daily":1,"cols":[["month","date_trunc('month', {D})::date","মাস","Month","date"]]},
   "fy":{"time":1,"daily":1,"need":"fy","cols":[["fiscal_year","extract(year from public.rpt_fy_start({D}, {FYC}))::int","অর্থবছর (শুরুর সাল)","Fiscal year (start year)","int"]]},
   "location":{"daily":1,"cols":[["location_id","{T}.location_id","","","id"],["location_bn","{T}.location_bn","লোকেশন","Location","text"],["location_en","{T}.location_en","Location (EN)","Location (EN)","text"]]},
   "brand":{"daily":1,"cols":[["brand_code","coalesce({T}.brand_code, 'none')","","","id"],["brand_bn","coalesce({T}.brand_bn, 'ব্র্যান্ড ঠিক করা নেই')","ব্র্যান্ড","Brand","text"],["brand_en","coalesce({T}.brand_en, 'No brand set')","Brand (EN)","Brand (EN)","text"]]},
   "staff":{"daily":1,"cols":[["staff","coalesce({T}.staff, '-')","কর্মী","Staff","text"]]},
   "hour":{"cols":[["hour","{T}.hour","ঘণ্টা","Hour","int"]]},
   "weekday":{"cols":[["dow","{T}.dow","বার (০=রবি)","Weekday (0=Sun)","int"]]}
  }$c$::jsonb || case p_src
   when 'bill' then $c${
   "pay_mode":{"daily":1,"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"daily":1,"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]},
   "void_staff":{"cols":[["void_staff","coalesce({T}.void_staff, '-')","বাতিল করেছে","Voided by","text"]]},
   "void_reason":{"cols":[["void_reason","coalesce({T}.void_note, '-')","বাতিলের কারণ","Void reason","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   when 'line' then $c${
   "pay_mode":{"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "item":{"cols":[["item_id","coalesce({T}.item_id::text, 'none')","","","id"],["item_code","coalesce({T}.item_code, '-')","কোড","Code","text"],["item_name","{T}.item_name","আইটেম","Item","text"],["item_name_en","{T}.item_name_en","Item (EN)","Item (EN)","text"]]},
   "category":{"cols":[["category","coalesce({T}.category, '(none)')","ক্যাটাগরি","Category","text"]]},
   "line_kind":{"cols":[["line_kind","{T}.line_kind","লাইনের ধরন","Line kind","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   else $c${
   "mode":{"cols":[["mode","{T}.mode","মাধ্যম","Mode","text"]]},
   "wallet":{"cols":[["wallet","coalesce({T}.wallet, '-')","ওয়ালেট","Wallet","text"]]},
   "kind":{"cols":[["kind","{T}.kind","ধরন (সেল/আদায়)","Kind (sale/collection)","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]}
  }$c$::jsonb end;
$j$;

create or replace function public.rpt_meas(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select case p_src
   when 'bill' then $c${
   "bills":{"expr":"coalesce(sum({T}.bills), 0)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(sum({T}.gross), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "discount":{"expr":"coalesce(sum({T}.discount), 0)","bn":"ছাড়","en":"Discount","type":"money"},
   "net":{"expr":"coalesce(sum({T}.net), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "discount_pct":{"expr":"round(100 * sum({T}.discount) / nullif(sum({T}.gross), 0), 2)","bn":"ছাড় %","en":"Discount %","type":"pct"},
   "avg_bill":{"expr":"round(sum({T}.net) / nullif(sum({T}.bills), 0), 2)","bn":"গড় বিল","en":"Avg bill","type":"money"},
   "paid":{"expr":"coalesce(sum({T}.paid), 0)","bn":"পরিশোধ","en":"Paid","type":"money"},
   "due":{"expr":"coalesce(sum({T}.due), 0)","bn":"বাকি","en":"Due","type":"money"},
   "void_bills":{"expr":"coalesce(sum({T}.void_bills), 0)","bn":"বাতিল বিল","en":"Voided bills","type":"int"},
   "void_amt":{"expr":"coalesce(sum({T}.void_amt), 0)","bn":"বাতিল টাকা","en":"Voided amount","type":"money"},
   "void_pct":{"expr":"round(100 * sum({T}.void_bills)::numeric / nullif(sum({T}.bills) + sum({T}.void_bills), 0), 2)","bn":"বাতিল %","en":"Void %","type":"pct"},
   "quick_bills":{"expr":"coalesce(sum({T}.quick_bills), 0)","bn":"কুইক বিল","en":"Quick bills","type":"int"},
   "disc_bills":{"expr":"coalesce(sum({T}.disc_bills), 0)","bn":"ছাড়ের বিল","en":"Bills with discount","type":"int"},
   "avg_discount":{"expr":"round(sum({T}.discount) / nullif(sum({T}.disc_bills), 0), 2)","bn":"ছাড়ের বিলে গড় ছাড়","en":"Avg discount per discounted bill","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"coalesce(sum({T}.override_lines), 0)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int","daily":0},
   "over_limit_bills":{"expr":"coalesce(sum({T}.over_limit_bills), 0)","bn":"ছাড়ের সীমা পার বিল","en":"Bills over the discount limit","type":"int","daily":0},
   "no_limit_bills":{"expr":"coalesce(sum({T}.no_limit_bills), 0)","bn":"সীমা লেখা ছাড়া ছাড়ের বিল","en":"Discounts with no limit set","type":"int","daily":0},
   "custom_lines":{"expr":"coalesce(sum({T}.custom_lines), 0)","bn":"তালিকা-বহির্ভূত লাইন","en":"Unlisted lines","type":"int","daily":0},
   "customers":{"expr":"count(distinct {T}.customer_id)","bn":"গ্রাহক","en":"Customers","type":"int","daily":0},
   "first_sale":{"expr":"min({T}.day) filter (where {T}.bills = 1)","bn":"প্রথম কেনা","en":"First purchase","type":"date","daily":0},
   "last_sale":{"expr":"max({T}.day) filter (where {T}.bills = 1)","bn":"শেষ কেনা","en":"Last purchase","type":"date","daily":0}
  }$c$::jsonb
   when 'line' then $c${
   "qty":{"expr":"coalesce(round(sum({T}.qty), 3), 0)","bn":"পরিমাণ","en":"Qty","type":"num"},
   "lines":{"expr":"count(*)","bn":"লাইন","en":"Lines","type":"int"},
   "bills":{"expr":"count(distinct {T}.sale_id)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(round(sum({T}.gross), 2), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "disc":{"expr":"coalesce(round(sum({T}.disc), 2), 0)","bn":"ছাড় (ভাগ করা)","en":"Discount (allocated)","type":"money"},
   "net":{"expr":"coalesce(round(sum({T}.net), 2), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "avg_price":{"expr":"round(sum({T}.gross) / nullif(sum({T}.qty), 0), 2)","bn":"গড় দাম","en":"Avg price","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"count(*) filter (where {T}.override)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int"},
   "cogs":{"expr":"round(sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"পণ্যের খরচ","en":"Cost of goods","type":"money","cost":1},
   "costed_net":{"expr":"sum({T}.net) filter (where c.cost_price is not null)","bn":"খরচ জানা বিক্রি","en":"Sales with known cost","type":"money","cost":1},
   "net_all":{"expr":"sum({T}.net)","bn":"মোট বিক্রি","en":"All sales","type":"money","cost":1},
   "gp":{"expr":"round(sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"মোট লাভ (খরচ জানা অংশে)","en":"Gross profit (costed part)","type":"money","cost":1},
   "gp_pct":{"expr":"round(100 * (sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null)) / nullif(sum({T}.net) filter (where c.cost_price is not null), 0), 2)","bn":"লাভ %","en":"GP %","type":"pct","cost":1},
   "uncosted_pct":{"expr":"round(100 * (sum({T}.net) - coalesce(sum({T}.net) filter (where c.cost_price is not null), 0)) / nullif(sum({T}.net), 0), 2)","bn":"খরচ অজানা বিক্রি %","en":"Uncosted sales %","type":"pct","cost":1}
  }$c$::jsonb
   else $c${
   "payments":{"expr":"count(*)","bn":"পেমেন্ট","en":"Payments","type":"int"},
   "amount":{"expr":"coalesce(sum({T}.amount), 0)","bn":"টাকা","en":"Amount","type":"money"},
   "sale_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'sale'), 0)","bn":"সেলের সময়ে","en":"At sale","type":"money"},
   "collection_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'collection'), 0)","bn":"বাকি আদায়","en":"Collections","type":"money"},
   "cash_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'cash'), 0)","bn":"ক্যাশ","en":"Cash","type":"money"},
   "mobile_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'mobile'), 0)","bn":"মোবাইল","en":"Mobile money","type":"money"},
   "card_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'card'), 0)","bn":"কার্ড","en":"Card","type":"money"},
   "missing_ref":{"expr":"count(*) filter (where {T}.mode = 'mobile' and nullif(btrim({T}.ref), '') is null)","bn":"রেফারেন্স ছাড়া","en":"Without reference","type":"int"},
   "dup_refs":{"expr":"count(nullif(btrim({T}.ref), '')) - count(distinct nullif(btrim({T}.ref), ''))","bn":"ডুপ্লিকেট রেফারেন্স","en":"Duplicate references","type":"int"},
   "share_pct":{"expr":"round(100 * sum({T}.amount) / nullif(sum(sum({T}.amount)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"}
  }$c$::jsonb end;
$j$;

-- the reports. kind agg = grouped by whitelisted dims; raw = fixed query. group = access group (grant report_<group>).
create or replace function public.rpt_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "sales_summary":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির সারসংক্ষেপ","en":"Sales summary","mix":"Sales সারসংক্ষেপ",
     "dims":["day","week","month","fy","location","brand","staff","pay_mode","sale_type"],"gdef":"",
     "measures":["bills","gross","discount","discount_pct","net","avg_bill","paid","due","void_bills","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "sales_trend":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির ধারা","en":"Sales trend","mix":"Sales এর ধারা",
     "dims":["day","week","month","fy","location","brand","staff"],"gdef":"day",
     "measures":["bills","net","avg_bill","discount","void_bills"],"sort":"@dim","cmp":1},
   "sales_combined":{"group":"sales","kind":"agg","src":"bill","bn":"একত্রিত দোকান/ব্র্যান্ড-ওয়াইজ","en":"Combined by shop / brand","mix":"একত্রিত দোকান/Brand-wise",
     "dims":["location","brand"],"gdef":"location",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","paid","due","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "item_sales":{"group":"sales","kind":"agg","src":"line","bn":"আইটেম-ওয়াইজ বিক্রি","en":"Item-wise sales","mix":"Item-wise বিক্রি",
     "dims":["item","category","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"item",
     "measures":["qty","bills","gross","disc","net","avg_price","share_pct","override_lines","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "category_sales":{"group":"sales","kind":"agg","src":"line","bn":"ক্যাটাগরি-ওয়াইজ বিক্রি","en":"Category-wise sales","mix":"Category-wise বিক্রি",
     "dims":["category","item","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"category",
     "measures":["qty","bills","gross","disc","net","share_pct","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "receipt_register":{"group":"sales","kind":"raw","bn":"রসিদ তালিকা","en":"Receipt register","mix":"Receipt তালিকা","nocompare":1,
     "allow":["locations","brands","staff","modes","sale_type","customer","min_amount","max_amount","status","search"],"sort":"sold_at:desc",
     "columns":[["sale_id","","","id"],["receipt","রসিদ নং","Receipt #","int"],["day","দিন","Day","date"],["time","সময়","Time","text"],["sold_at","","","id"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["staff","কর্মী","Staff","text"],["sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"],["pay_mode","পেমেন্ট","Payment","text"],["status","অবস্থা","Status","text"],["customer_name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["subtotal","মোট","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","পরিশোধযোগ্য","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"]]},
   "hour_weekday":{"group":"sales","kind":"agg","src":"bill","bn":"সময় ও বার অনুযায়ী","en":"Hour and weekday","mix":"ঘণ্টা ও বার অনুযায়ী",
     "dims":["hour","weekday","location","brand"],"gdef":"hour","measures":["bills","net","avg_bill","share_pct"],"sort":"@dim","cmp":1},
   "retail_wholesale":{"group":"sales","kind":"agg","src":"bill","bn":"খুচরা বনাম পাইকারি","en":"Retail vs wholesale","mix":"খুচরা vs পাইকারি",
     "dims":["sale_type","location","brand","day","week","month","fy","staff"],"gdef":"sale_type",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","due"],"sort":"net:desc","cmp":1},
   "discounts":{"group":"sales","kind":"agg","src":"bill","bn":"ডিসকাউন্ট ও দাম বদল","en":"Discounts and price overrides","mix":"Discount ও দাম বদল","only_bill":1,
     "dims":["staff","location","brand","day","week","month","fy","discount_kind","sale_type"],"gdef":"staff",
     "measures":["bills","disc_bills","gross","discount","discount_pct","avg_discount","over_limit_bills","no_limit_bills","override_lines","net"],"sort":"discount:desc","cmp":1},
   "pos_day_close":{"group":"pos","kind":"raw","bn":"দিনশেষ রিপোর্ট (POS)","en":"POS day close","mix":"দিনশেষ (POS) report","nocompare":1,
     "allow":["locations","brands","staff"],"sort":"day:desc",
     "columns":[["day","দিন","Day","date"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["bills","বিল","Bills","int"],["net","বিক্রি","Sales","money"],["discount","ছাড়","Discount","money"],["void_bills","বাতিল বিল","Voided bills","int"],["void_amt","বাতিল টাকা","Voided amount","money"],["due_created","নতুন বাকি","New due","money"],["cash_in","ক্যাশ (সেল)","Cash at sale","money"],["mobile_in","মোবাইল (সেল)","Mobile at sale","money"],["card_in","কার্ড (সেল)","Card at sale","money"],["cash_collections","ক্যাশ আদায়","Cash collections","money"],["mobile_collections","মোবাইল আদায়","Mobile collections","money"],["card_collections","কার্ড আদায়","Card collections","money"],["total_in","মোট জমা","Total received","money"],["expected_cash","ড্রয়ারে থাকার কথা (ক্যাশ)","Expected cash in drawer","money"]]},
   "voids":{"group":"pos","kind":"agg","src":"bill","bn":"বাতিল বিল","en":"Voids","mix":"বাতিল Bill",
     "dims":["staff","void_staff","void_reason","location","brand","day","week","month","fy"],"gdef":"staff",
     "measures":["void_bills","void_amt","bills","void_pct"],"sort":"void_amt:desc","cmp":1,"having":"sum({T}.void_bills) > 0"},
   "quick_unlisted":{"group":"pos","kind":"agg","src":"line","bn":"কুইক ও তালিকা-বহির্ভূত বিক্রি","en":"Quick and unlisted sales","mix":"Quick ও unlisted বিক্রি",
     "dims":["line_kind","item","staff","location","brand","day","week","month","fy"],"gdef":"line_kind",
     "measures":["lines","bills","qty","net","share_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done' and {T}.line_kind <> 'listed'"},
   "payment_modes":{"group":"cash","kind":"agg","src":"pay","bn":"পেমেন্ট মাধ্যম অনুযায়ী","en":"By payment mode","mix":"Payment mode অনুযায়ী",
     "dims":["mode","wallet","kind","day","week","month","fy","location","brand","staff"],"gdef":"mode",
     "measures":["payments","sale_amount","collection_amount","amount","share_pct"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided"},
   "wallet_recon":{"group":"cash","kind":"agg","src":"pay","bn":"ওয়ালেট/মোবাইল পেমেন্ট মিল","en":"Wallet reconciliation","mix":"Wallet মিল",
     "dims":["wallet","day","week","month","fy","location","brand","staff"],"gdef":"wallet",
     "measures":["payments","amount","missing_ref","dup_refs"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided and {T}.mode = 'mobile'"},
   "collections":{"group":"cash","kind":"agg","src":"pay","bn":"বাকি আদায়","en":"Collections","mix":"বাকি আদায়",
     "dims":["day","week","month","fy","mode","wallet","staff","customer","location","brand"],"gdef":"day",
     "measures":["payments","amount","cash_amount","mobile_amount","card_amount","share_pct"],"sort":"@dim","cmp":1,"base":"not {T}.voided and {T}.kind = 'collection'"},
   "best_customers":{"group":"customers","kind":"agg","src":"bill","bn":"সেরা গ্রাহক","en":"Best customers","mix":"সেরা Customer","only_bill":1,
     "dims":["customer"],"gdef":"customer","measures":["bills","net","avg_bill","discount","due","first_sale","last_sale"],"sort":"net:desc","cmp":1,"base":"{T}.customer_id is not null"},
   "customer_dues":{"group":"customers","kind":"raw","bn":"গ্রাহকের কাছে পাওনা","en":"Due from customers","mix":"Customer এর কাছে পাওনা","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["oldest_due","সবচেয়ে পুরনো বাকির তারিখ","Oldest due since","date"],["days_old","কত দিনের পুরনো","Days old","int"]]},
   "receivable_aging":{"group":"customers","kind":"raw","bn":"বাকির বয়স","en":"Receivable aging","mix":"বাকির বয়স","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc"},
   "credit_limit_use":{"group":"customers","kind":"raw","bn":"ক্রেডিট সীমা ব্যবহার","en":"Credit-limit use","mix":"Credit limit ব্যবহার","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"use_pct:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["use_pct","সীমার % ব্যবহার","Limit used %","pct"],["status","অবস্থা","Status","text"]]}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public.rpt_keys() returns text[]
language sql immutable set search_path = public as $$ select array['sales_summary','sales_trend','sales_combined','item_sales','category_sales','receipt_register','hour_weekday','retail_wholesale','discounts',
  'pos_day_close','voids','quick_unlisted','payment_modes','wallet_recon','collections','best_customers','customer_dues','receivable_aging','credit_limit_use']; $$;

-- which filters each source can apply
create or replace function public.rpt_filters_for(p_src text) returns text[]
language sql immutable set search_path = public as $$
  select case p_src
    when 'bill' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount']
    when 'line' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount','items','categories']
    else array['locations','brands','staff','modes','customer','min_amount','max_amount'] end;
$$;

-- token replacement
create or replace function public.rpt_tok(p_expr text, p_al text, p_dexpr text, p_ws int, p_fym int, p_mobok boolean) returns text
language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(replace(p_expr, '{D}', p_dexpr), '{T}', p_al), '{WS}', coalesce(p_ws, 6)::text), '{FYC}', coalesce(p_fym, 101)::text),
                 '{MOBOK}', case when p_mobok then 'true' else 'false' end);
$$;

-- WHERE clause from the filters. Values are type-checked and quoted with %L; keys are looked up, never pasted.
create or replace function public.rpt_where(p_src text, p_al text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_allow text[], p_mobok boolean default false) returns jsonb
language plpgsql stable set search_path = public as $$
declare w text[] := '{}'; ign text[] := '{}'; k text; locs int[]; eff int[]; tx text[]; ux uuid[]; n1 numeric; n2 numeric; nb boolean := false; v text; col text;
begin
  for k in select jsonb_object_keys(p_flt) loop
    if k in ('from', 'to', 'preset', 'compare_mode') then continue; end if;
    if jsonb_typeof(p_flt -> k) = 'null' then continue; end if;
    if not (k = any (p_allow)) then ign := ign || left(k, 40); end if;
  end loop;
  locs := public.rpt_arr_int(p_flt -> 'locations');
  eff := case when locs is null then p_allowed else array(select unnest(p_allowed) intersect select unnest(locs)) end;
  w := w || format('%s.location_id = any (%L::int[])', p_al, eff);
  if p_from is not null then w := w || format('%s.day between %L::date and %L::date', p_al, p_from, p_to); end if;
  if 'brands' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'brands'); if tx is not null then w := w || format('%s.brand_code = any (%L::text[])', p_al, tx); end if; end if;
  if 'staff' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'staff'); if tx is not null then w := w || format('%s.staff = any (%L::text[])', p_al, tx); end if; end if;
  if 'modes' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'modes');
    if tx is not null then w := w || format('%s.%s = any (%L::text[])', p_al, case when p_src = 'pay' then 'mode' else 'pay_mode' end, tx); end if; end if;
  if 'sale_type' = any (p_allow) and p_src <> 'pay' then v := p_flt ->> 'sale_type';
    if v is not null then w := w || format('%s.sale_type = %L', p_al, v); end if; end if;
  if 'customer' = any (p_allow) then ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then w := w || format('%s.customer_id = any (%L::uuid[])', p_al, ux); nb := true; end if; end if;
  if 'items' = any (p_allow) and p_src = 'line' then ux := public.rpt_arr_uuid(p_flt -> 'items'); if ux is not null then w := w || format('%s.item_id = any (%L::uuid[])', p_al, ux); end if; end if;
  if 'categories' = any (p_allow) and p_src = 'line' then tx := public.rpt_arr_text(p_flt -> 'categories'); if tx is not null then w := w || format('%s.category = any (%L::text[])', p_al, tx); end if; end if;
  if 'min_amount' = any (p_allow) then n1 := public.rpt_num(p_flt -> 'min_amount'); n2 := public.rpt_num(p_flt -> 'max_amount');
    col := case p_src when 'bill' then 'total' when 'line' then 'sale_total' else 'amount' end;
    if n1 is not null then w := w || format('%s.%s >= %L::numeric', p_al, col, n1); nb := true; end if;
    if n2 is not null then w := w || format('%s.%s <= %L::numeric', p_al, col, n2); nb := true; end if; end if;
  if 'status' = any (p_allow) and p_src = 'bill' then v := p_flt ->> 'status';
    if v is not null then
      if v not in ('done', 'void') then raise exception 'bad_filter'; end if;
      w := w || format('%s.status = %L', p_al, v); nb := true; end if; end if;
  if 'search' = any (p_allow) and p_src = 'bill' then v := btrim(p_flt ->> 'search');
    if v is not null and v <> '' then
      if length(v) > 60 then raise exception 'bad_filter'; end if;
      w := w || format('(%s.receipt::text = %L or position(lower(%L) in lower(coalesce(%s.customer_name, ''''))) > 0 %s)', p_al, v, v, p_al,
        case when p_mobok then format('or position(%L in coalesce(%s.mobile, '''')) > 0', v, p_al) else '' end);
      nb := true; end if; end if;
  return jsonb_build_object('w', array_to_string(w, ' and '), 'ignored', to_jsonb(ign), 'needs_bill', nb);
end $$;

-- SQL text of one grouped query (plus joins to item_costs when the cost measures are wanted)
create or replace function public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_nodim boolean, p_withcost boolean) returns text
language plpgsql stable set search_path = public as $$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
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
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join public.item_costs c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $$;

-- builds the rows query and the totals query of an agg report for one period
create or replace function public.rpt_agg_build(p_def jsonb, p_gl text[], p_mkeys text[], p_flt jsonb, p_allowed int[], p_from date, p_to date,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_costok boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; al text := case src when 'bill' then 'b' when 'line' then 'f' else 'p' end;
  dims jsonb := public.rpt_dims(src); g text; c jsonb; needb boolean := coalesce((p_def ->> 'only_bill')::int = 1, false);
  wj jsonb; wl jsonb; rel text; nodim boolean := cardinality(p_gl) = 0; mk text; meas jsonb := public.rpt_meas(src);
  t text; tot text; ts text; tj text; conds text[] := '{}'; cj text; lw text; ign jsonb;
  extra text := ', cq.cogs, round(cq.costed_net - cq.cogs, 2) as gp, round(100 * (cq.costed_net - cq.cogs) / nullif(cq.costed_net, 0), 2) as gp_pct, round(100 * (cq.net_all - cq.costed_net) / nullif(cq.net_all, 0), 2) as uncosted_pct';
begin
  wj := public.rpt_where(src, al, p_flt, p_allowed, p_from, p_to, coalesce((select array_agg(x) from jsonb_array_elements_text(p_def -> 'allow') x), public.rpt_filters_for(src)), p_mobok);
  ign := wj -> 'ignored';
  if src = 'bill' then
    foreach g in array p_gl loop if coalesce((dims -> g ->> 'daily')::int, 0) = 0 then needb := true; end if; end loop;
    foreach mk in array p_mkeys loop if coalesce((meas -> mk ->> 'daily')::int, 1) = 0 then needb := true; end if; end loop;
    if (wj ->> 'needs_bill')::boolean then needb := true; end if;
    rel := case when needb then 'public.rpt_bill' else 'public.rpt_daily' end;
  else rel := case src when 'line' then 'public.sales_fact' else 'public.rpt_pay' end; end if;
  t := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', p_def ->> 'having', p_dexpr, p_ws, p_fym, p_mobok, nodim, src = 'line' and p_costok);
  tot := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', null, p_dexpr, p_ws, p_fym, p_mobok, true, src = 'line' and p_costok);
  if p_costok and coalesce((p_def ->> 'cost_join')::int, 0) = 1 then
    wl := public.rpt_where('line', 'f', p_flt, p_allowed, p_from, p_to, array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount'], p_mobok);
    lw := wl ->> 'w';
    ts := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, nodim, true);
    tj := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, true, true);
    if not nodim then
      foreach g in array p_gl loop
        for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
          conds := conds || format('bq.%I = cq.%I', c ->> 0, c ->> 0);      -- dimension columns are never null, so this can be a hash join
        end loop;
      end loop;
    end if;
    cj := coalesce(array_to_string(conds, ' and '), 'true'); if cj = '' then cj := 'true'; end if;
    t := format('select bq.*%s from (%s) bq left join (%s) cq on %s', extra, t, ts, cj);
    tot := format('select bq.*%s from (%s) bq cross join (%s) cq', extra, tot, tj);
  end if;
  return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);
end $$;

-- ============================================================
-- raw (non-grouped) reports: fixed SQL, only validated literals are inserted
-- ============================================================
create or replace function public.rpt_mobx(p_col text, p_ok boolean) returns text
language sql immutable set search_path = public as $$
  select case when p_ok then p_col else 'left(' || p_col || ', 3) || ''****'' || right(' || p_col || ', 2)' end;
$$;

create or replace function public.rpt_raw(p_key text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_mobok boolean, p_buckets int[], p_near numeric, p_today date) returns jsonb
language plpgsql stable set search_path = public as $$
declare def jsonb := public.rpt_def(p_key); al text[]; wj jsonb; wb text; wp text; sql text; tot text; cols jsonb; ign jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
  ux uuid[]; srch text; cfilter text := ''; alist text; i int; b text[] := '{}'; cond text; lo int; hi int; clist jsonb;
begin
  al := array(select jsonb_array_elements_text(def -> 'allow'));
  if p_key = 'receipt_register' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    sql := format($f$select b.sale_id, b.receipt, b.day, to_char(b.sold_at at time zone 'Asia/Dhaka', 'HH24:MI') as time, b.sold_at, b.location_id, b.location_bn, b.location_en,
      b.staff, b.sale_type, b.pay_mode, b.status, b.customer_name, %s as mobile, b.subtotal, b.discount_raw as discount, b.total, b.paid_raw as paid, b.due_raw as due
      from public.rpt_bill b where %s$f$, public.rpt_mobx('b.mobile', p_mobok), wb);
    tot := $f$count(*) as receipts, count(*) filter (where status = 'void') as void_receipts, coalesce(sum(subtotal) filter (where status = 'done'), 0) as subtotal,
      coalesce(sum(discount) filter (where status = 'done'), 0) as discount, coalesce(sum(total) filter (where status = 'done'), 0) as total,
      coalesce(sum(paid) filter (where status = 'done'), 0) as paid, coalesce(sum(due) filter (where status = 'done'), 0) as due$f$;
  elsif p_key = 'pos_day_close' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    wj := public.rpt_where('pay', 'p', p_flt, p_allowed, p_from, p_to, al, p_mobok); wp := wj ->> 'w';
    sql := format($f$with bb as (select b.day, b.location_id, b.location_bn, b.location_en, sum(b.bills) as bills, sum(b.net) as net, sum(b.discount) as discount,
        sum(b.void_bills) as void_bills, sum(b.void_amt) as void_amt, sum(b.due) as due_created
        from public.rpt_daily b where %s group by 1, 2, 3, 4),
      pb as (select p.day, p.location_id, p.location_bn, p.location_en,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'cash'), 0) as cash_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'mobile'), 0) as mobile_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'card'), 0) as card_in,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'cash'), 0) as cash_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'mobile'), 0) as mobile_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'card'), 0) as card_collections
        from public.rpt_pay p where not p.voided and %s group by 1, 2, 3, 4)
      select coalesce(bb.day, pb.day) as day, coalesce(bb.location_id, pb.location_id) as location_id, coalesce(bb.location_bn, pb.location_bn) as location_bn,
        coalesce(bb.location_en, pb.location_en) as location_en, coalesce(bb.bills, 0) as bills, coalesce(bb.net, 0) as net, coalesce(bb.discount, 0) as discount,
        coalesce(bb.void_bills, 0) as void_bills, coalesce(bb.void_amt, 0) as void_amt, coalesce(bb.due_created, 0) as due_created,
        coalesce(pb.cash_in, 0) as cash_in, coalesce(pb.mobile_in, 0) as mobile_in, coalesce(pb.card_in, 0) as card_in,
        coalesce(pb.cash_collections, 0) as cash_collections, coalesce(pb.mobile_collections, 0) as mobile_collections, coalesce(pb.card_collections, 0) as card_collections,
        coalesce(pb.cash_in + pb.mobile_in + pb.card_in + pb.cash_collections + pb.mobile_collections + pb.card_collections, 0) as total_in,
        coalesce(pb.cash_in + pb.cash_collections, 0) as expected_cash
      from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);
    tot := $f$sum(bills) as bills, sum(net) as net, sum(discount) as discount, sum(void_bills) as void_bills, sum(void_amt) as void_amt, sum(due_created) as due_created,
      sum(cash_in) as cash_in, sum(mobile_in) as mobile_in, sum(card_in) as card_in, sum(cash_collections) as cash_collections, sum(mobile_collections) as mobile_collections,
      sum(card_collections) as card_collections, sum(total_in) as total_in, sum(expected_cash) as expected_cash$f$;
  else
    -- customer reports: always all locations the caller may see; only customer / search filters apply
    ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then cfilter := cfilter || format(' and cu.id = any (%L::uuid[])', ux); end if;
    srch := btrim(p_flt ->> 'search');
    if srch is not null and srch <> '' then
      if length(srch) > 60 then raise exception 'bad_filter'; end if;
      cfilter := cfilter || format(' and (position(lower(%L) in lower(cu.name)) > 0 %s)', srch, case when p_mobok then format('or position(%L in cu.mobile) > 0', srch) else '' end);
    end if;
    ign := (select coalesce(jsonb_agg(left(k, 40)), '[]'::jsonb) from jsonb_object_keys(p_flt) k
            where k not in ('from', 'to', 'preset', 'compare_mode') and not (k = any (al)) and jsonb_typeof(p_flt -> k) <> 'null');
    alist := format('%L::int[]', p_allowed);
    if p_key = 'customer_dues' then
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce(pp.v, 0) as rem
          from public.sales x left join (select sale_id, sum(amount) as v from public.sale_payments where not voided and sale_id is not null group by 1) pp on pp.sale_id = x.id
          where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        t as (select customer_id, sum(rem) as rem from s group by 1)
        select cu.id as customer_id, cu.name, %s as mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0) as balance, o.od as oldest_due, %L::date - o.od as days_old
        from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
        left join lateral (select min(k.sale_date) as od from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0)) o on true
        where t.rem - coalesce(c.coll, 0) > 0%s$f$, alist, alist, public.rpt_mobx('cu.mobile', p_mobok), p_today, cfilter);
      tot := 'count(*) as customers, sum(balance) as balance, count(*) filter (where credit_limit is null) as no_limit_set';
    elsif p_key = 'receivable_aging' then
      -- buckets come from the rule report_aging_buckets (no built-in values)
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end;
          hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          cond := case when hi is null then format('age >= %s', lo) else format('age between %s and %s', lo, hi) end;
          b := b || format('coalesce(sum(portion) filter (where %s), 0) as bucket_%s', cond, i);
        end loop;
      end if;
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce(pp.v, 0) as rem
          from public.sales x left join (select sale_id, sum(amount) as v from public.sale_payments where not voided and sale_id is not null group by 1) pp on pp.sale_id = x.id
          where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        pt as (select k.customer_id, %L::date - k.sale_date as age, greatest(0, least(k.rem, k.cr - coalesce(c.coll, 0))) as portion from cum k left join c on c.customer_id = k.customer_id)
        select cu.id as customer_id, cu.name, %s as mobile, coalesce(sum(pt.portion), 0) as balance%s, max(pt.age) filter (where pt.portion > 0) as oldest_days
        from pt join public.customers cu on cu.id = pt.customer_id where true%s
        group by cu.id, cu.name, cu.mobile having coalesce(sum(pt.portion), 0) > 0$f$,
        alist, alist, p_today, public.rpt_mobx('cu.mobile', p_mobok), case when cardinality(b) > 0 then ', ' || array_to_string(b, ', ') else '' end, cfilter);
      clist := '[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["balance","মোট বাকি","Total due","money"]]';
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end; hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          clist := clist || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '-' || hi || ' দিন' end,
                                                               case when hi is null then lo || '+ days' else lo || '-' || hi || ' days' end, 'money'));
        end loop;
        tot := 'count(*) as customers, sum(balance) as balance, ' || array_to_string(array(select format('sum(bucket_%s) as bucket_%s', gs.n, gs.n) from generate_series(1, cardinality(p_buckets) + 1) gs(n)), ', ');
      else
        tot := 'count(*) as customers, sum(balance) as balance';
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_bn', 'বাকির বয়স ভাগ নিয়মে (report_aging_buckets) লেখা নেই', 'text_en', 'Aging buckets are not set in the rule report_aging_buckets'));
      end if;
      clist := clist || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"]]'::jsonb;
      cols := clist;
    elsif p_key = 'credit_limit_use' then
      sql := format($f$with sold as (select x.customer_id, sum(x.total) as v from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s) group by 1),
        paid as (select p.customer_id, sum(p.amount) as v from public.sale_payments p where not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        r as (select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(sold.v, 0) - coalesce(paid.v, 0) as balance
          from public.customers cu left join sold on sold.customer_id = cu.id left join paid on paid.customer_id = cu.id where cu.active%s)
        select r.id as customer_id, r.name, %s as mobile, r.type, r.credit_limit, r.balance,
          case when r.credit_limit > 0 then round(100 * r.balance / r.credit_limit, 1) end as use_pct,
          case when r.credit_limit is null then 'no_limit' when r.balance > r.credit_limit then 'over'
               %s else 'ok' end as status
        from r where r.credit_limit is not null or r.balance > 0$f$, alist, alist, cfilter, public.rpt_mobx('r.mobile', p_mobok),
        case when p_near is not null then format('when r.credit_limit > 0 and 100 * r.balance / r.credit_limit >= %L::numeric then ''near''', p_near) else '' end);
      tot := $f$count(*) as customers, count(*) filter (where status = 'over') as over_limit, count(*) filter (where status = 'near') as near_limit,
        count(*) filter (where status = 'no_limit') as no_limit_set, sum(balance) as balance$f$;
      if p_near is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_near_limit_pct', 'text_bn', '"সীমার কাছে" দেখাতে নিয়ম report_near_limit_pct লিখুন', 'text_en', 'Set the rule report_near_limit_pct to show a "near the limit" status')); end if;
    end if;
  end if;
  return jsonb_build_object('t', sql, 'tot', tot, 'cols', cols, 'ignored', coalesce(ign, '[]'::jsonb), 'notes', notes);
end $$;

-- ============================================================
-- the catalogue for the UI
-- ============================================================
create or replace function public.report_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; cost_ok boolean; dims jsonb; meas jsonb; src text; dl jsonb; ml jsonb; g text; mk text; fl text[]; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  cost_ok := public.rpt_cost_ok();
  foreach k in array public.rpt_keys() loop
    d := public.rpt_def(k); src := d ->> 'src';
    ok := public.rpt_access(d ->> 'group');
    dl := '[]'::jsonb; ml := '[]'::jsonb;
    if d ->> 'kind' = 'agg' then
      dims := public.rpt_dims(src); meas := public.rpt_meas(src);
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', coalesce((dims -> g ->> 'time')::int = 1, false),
              'label_bn', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 2,
              'label_en', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 3,
              'needs_rule', null));      -- week / fiscal grouping always work now (phase8 rules, documented fallbacks): nothing to set first
      end loop;
      for mk in select jsonb_array_elements_text(d -> 'measures') loop
        if cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0 then
          ml := ml || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
        end if;
      end loop;
      if cost_ok and coalesce((d ->> 'cost_join')::int, 0) = 1 then
        ml := ml || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","cost":true}]'::jsonb;
      end if;
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), public.rpt_filters_for(src));
    else
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}');
      ml := coalesce((select jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3)) from jsonb_array_elements(d -> 'columns') c where c ->> 3 <> 'id'), '[]'::jsonb);
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok,
      'kind', d ->> 'kind', 'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(array['date'] || fl), 'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', ml,
      'compare', coalesce((d ->> 'cmp')::int = 1, false), 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0));
  end loop;
  return out_;
end $$;

-- ============================================================
-- report_run
-- ============================================================
create or replace function public.report_run(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null,
  p_page int default 1, p_compare boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
-- Time guard: a function-level SET statement_timeout does NOT cancel the statement that is already running (tested), so the real guard is the
-- role timeout (Supabase sets 8s on the authenticated role) plus the hard limits here: 366-day range, 500-group cap, 200-row pages.
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
  cost_ok boolean; mob_ok boolean; allowed int[]; d1 date; d2 date; wcfg jsonb; fcfg jsonb; fym int; ws int; fgap_s bigint; fgap_f bigint;
  pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500;
  kind text; src text; dims jsonb; meas jsonb; gl text[] := '{}'; tok text; g text; mk text; mkeys text[] := '{}'; gtxt text;
  cols jsonb := '[]'::jsonb; allowkeys text[] := '{}'; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  b jsonb; t text; tot text; rows_ jsonb; totals_ jsonb; ngroups bigint := 0; cmp_ jsonb := null; ign jsonb; c jsonb; pr jsonb; preset text;
  cmode text; cf date; ct date; shiftlit text; shiftdays int; b2 jsonb; rows2 jsonb; tot2 jsonb; buckets int[]; bk text; near numeric; extra_cols jsonb := '[]'::jsonb;
  hm boolean; dn boolean := false; i int; x record; raw jsonb; nloc int; delta jsonb := '{}'::jsonb; k text; cu numeric; pv numeric; first_dim text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public.rpt_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public.rpt_access(def ->> 'group') then raise exception 'not allowed'; end if;
  kind := def ->> 'kind'; src := def ->> 'src';
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok(); mob_ok := public.rpt_mobile_ok();
  allowed := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  if cardinality(allowed) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you')); end if;
  select count(*) into nloc from public.locations;
  if cardinality(allowed) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope', 'text_en', 'Only your locations are included', 'text_bn', 'শুধু আপনার লোকেশনের হিসাব')); end if;
  wcfg := public.rpt_week_cfg(); ws := (wcfg ->> 'dow')::int;      -- phase8 rules week_start / fiscal_year_start_month + _day, with phase8's documented fallbacks
  fcfg := public.rpt_fy_cfg(); fym := (fcfg ->> 'code')::int;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);

  -- period
  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset',
            'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  end if;

  -- ---------------- grouped reports ----------------
  if kind = 'agg' then
    dims := public.rpt_dims(src); meas := public.rpt_meas(src);
    gtxt := case when p_group is null or btrim(p_group) = '' then null else lower(btrim(p_group)) end;
    if gtxt is null then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}');
    elsif gtxt in ('none', 'total', '-') then gl := '{}';
    else
      foreach tok in array string_to_array(gtxt, ',') loop
        tok := btrim(tok);
        if tok = '' then continue; end if;
        if (def -> 'dims') @> to_jsonb(tok) and not (tok = any (gl)) and cardinality(gl) < 3 then gl := gl || tok;
        else notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(tok, 30))); end if;
      end loop;
      if cardinality(gl) = 0 then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}'); end if;
    end if;
    -- dims that use a setting: say so when a documented fallback (calendar year / Saturday) is used
    foreach g in array gl loop
      if dims -> g ->> 'need' = 'fy' and fcfg ->> 'src' = 'fallback' then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'fy_default', 'what', 'fiscal_year_start_month', 'text_en', 'Fiscal-year start rule not set: the calendar year (from 1 January) is used', 'text_bn', 'অর্থবছর শুরুর নিয়ম নেই: জানুয়ারি থেকে বছর ধরা হয়েছে'));
      elsif dims -> g ->> 'need' = 'ws' and wcfg ->> 'src' = 'fallback' then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'week_default', 'what', 'week_start', 'text_en', 'Week start rule not set: weeks start on Saturday', 'text_bn', 'সপ্তাহ শুরুর নিয়ম নেই: শনিবার ধরা হয়েছে'));
      end if;
    end loop;
    -- measures
    for mk in select jsonb_array_elements_text(def -> 'measures') loop
      if meas ? mk and (cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0) then mkeys := mkeys || mk; end if;
    end loop;
    if not cost_ok and (coalesce((def ->> 'cost_join')::int, 0) = 1 or exists (select 1 from jsonb_array_elements_text(def -> 'measures') m where coalesce((meas -> m ->> 'cost')::int, 0) = 1)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden', 'text_en', 'Cost and profit columns are hidden for your role', 'text_bn', 'আপনার ভূমিকার জন্য খরচ ও লাভের কলাম বন্ধ'));
    end if;
    -- output columns
    foreach g in array gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 2, 'label_en', c ->> 3, 'type', c ->> 4, 'role', 'dim'));
        allowkeys := allowkeys || (c ->> 0);
        if first_dim is null and c ->> 4 <> 'id' then first_dim := c ->> 0; end if;
      end loop;
    end loop;
    foreach mk in array mkeys loop
      cols := cols || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'role', 'measure', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
      allowkeys := allowkeys || mk;
    end loop;
    if cost_ok and coalesce((def ->> 'cost_join')::int, 0) = 1 then
      cols := cols || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","role":"measure","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","role":"measure","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","role":"measure","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","role":"measure","cost":true}]'::jsonb;
      allowkeys := allowkeys || array['cogs', 'gp', 'gp_pct', 'uncosted_pct'];
    end if;
    -- sort (only whitelisted output names; anything else is ignored with a note)
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if dsort = '@dim' then sk := first_dim; sd := 'asc';
      elsif dsort is not null and split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
      if sk is null then sk := first_dim; sd := 'asc'; end if;
    end if;
    ordr := case when sk is null then '1' else quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1' end;

    -- main period
    b := public.rpt_agg_build(def, gl, mkeys, flt, allowed, d1, d2, '{T}.day', ws, fym, mob_ok, cost_ok);
    t := b ->> 't'; tot := b ->> 'tot'; ign := b -> 'ignored';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (%s) x', tot) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 groups: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি গ্রুপ: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;
    -- line reports read the facts: if some done sales in this range have no fact rows (a failed fact write), say so (the owner runs report_fact_rebuild())
    if src = 'line' then
      select count(*) into fgap_s from public.sales gs where gs.status = 'done' and gs.sale_date between d1 and d2 and gs.location_id = any (allowed)
        and jsonb_typeof(gs.lines) = 'array' and jsonb_array_length(gs.lines) > 0;
      select count(distinct t.sale_id) into fgap_f from public.sales_fact_t t where t.status = 'done' and t.day between d1 and d2 and t.location_id = any (allowed);
      if fgap_s <> fgap_f then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'fact_gap', 'sales', fgap_s, 'facts', fgap_f,
          'text_en', 'Some sales in this period are missing from the line facts (' || fgap_s || ' sales, ' || fgap_f || ' with facts): totals may be low until the owner runs report_fact_rebuild()',
          'text_bn', 'এই সময়ের কিছু বিক্রির লাইন-হিসাব তৈরি হয়নি (' || fgap_s || ' বিক্রি, ' || fgap_f || ' টির হিসাব আছে): মালিক report_fact_rebuild() চালানো পর্যন্ত যোগফল কম দেখাতে পারে'));
      end if;
    end if;

    -- compare with an earlier period (same length, same weekday last week, or last year)
    if p_compare and coalesce((def ->> 'cmp')::int, 0) = 1 and d1 is not null then
      cmode := coalesce(flt ->> 'compare_mode', 'prev');
      if cmode not in ('prev', 'week', 'year') then cmode := 'prev'; notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_mode_ignored')); end if;
      if cmode = 'prev' then shiftdays := d2 - d1 + 1; cf := d1 - shiftdays; ct := d1 - 1; shiftlit := format('interval ''%s days''', shiftdays);
      elsif cmode = 'week' then shiftdays := 7; cf := d1 - 7; ct := d2 - 7; shiftlit := 'interval ''7 days''';
      else shiftdays := 365; cf := (d1 - interval '1 year')::date; ct := (d2 - interval '1 year')::date; shiftlit := 'interval ''1 year'''; end if;
      b2 := public.rpt_agg_build(def, gl, mkeys, flt, allowed, cf, ct, format('({T}.day + %s)::date', shiftlit), ws, fym, mob_ok, cost_ok);
      execute format('select coalesce(jsonb_agg(to_jsonb(q) order by q._rn), ''[]''::jsonb) from (select z.*, row_number() over (order by %s) as _rn from (%s) z order by %s limit %s) q',
        ordr, b2 ->> 't', ordr, cap) into rows2;
      execute format('select to_jsonb(x) from (%s) x', b2 ->> 'tot') into tot2;
      rows2 := (select coalesce(jsonb_agg(e - '_rn'), '[]'::jsonb) from jsonb_array_elements(rows2) e);
      for k in select jsonb_object_keys(totals_) loop
        if jsonb_typeof(totals_ -> k) = 'number' and jsonb_typeof(tot2 -> k) = 'number' then
          cu := (totals_ ->> k)::numeric; pv := (tot2 ->> k)::numeric;
          delta := delta || jsonb_build_object(k, jsonb_build_object('current', cu, 'previous', pv, 'abs', cu - pv, 'pct', case when pv <> 0 then round(100 * (cu - pv) / abs(pv), 2) end));
        end if;
      end loop;
      cmp_ := jsonb_build_object('mode', cmode, 'from', cf, 'to', ct, 'shifted_days', case when cmode = 'year' then null else shiftdays end, 'totals', tot2, 'rows', rows2, 'delta', delta,
        'note', 'Time columns of compare rows are shifted forward to line up with the current period');
    elsif p_compare then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable'));
    end if;

  -- ---------------- fixed (list) reports ----------------
  else
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    near := public.rule_num('report_near_limit_pct');
    raw := public.rpt_raw(p_key, flt, allowed, d1, d2, mob_ok, buckets, near, today);
    t := raw ->> 't'; tot := raw ->> 'tot'; ign := raw -> 'ignored';
    if raw -> 'cols' is not null and jsonb_typeof(raw -> 'cols') = 'array' then
      for c in select * from jsonb_array_elements(raw -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    else
      for c in select * from jsonb_array_elements(def -> 'columns') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    end if;
    notes := notes || coalesce(raw -> 'notes', '[]'::jsonb);
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;
    if p_group is not null and btrim(p_group) <> '' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30))); end if;
    if p_compare then notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable')); end if;
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); else sk := allowkeys[1]; sd := 'asc'; end if;
    end if;
    ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 rows: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি সারি: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
  end if;

  if not mob_ok and exists (select 1 from jsonb_array_elements(cols) ce where ce ->> 'key' = 'mobile') then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'mobile_masked', 'text_en', 'Customer mobile numbers are masked for your role', 'text_bn', 'আপনার ভূমিকার জন্য গ্রাহকের মোবাইল নম্বর ঢাকা'));
  end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0
     or (kind = 'agg' and cardinality(gl) = 0 and not exists (select 1 from jsonb_each_text(totals_) kv where kv.value ~ '^-?[0-9.]+$' and kv.value::numeric <> 0)) then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', cols, 'rows', rows_, 'totals', totals_, 'compare', cmp_,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', to_jsonb(gl), 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'mobile_masked', not mob_ok, 'today', today));
end $$;

-- ---------- export log: the app calls this after it builds a CSV / print so the owner can see who took which data out ----------
-- Needs the owner or the grant export_data (role / personal / emergency window, see rpt_grant). It only WRITES one audit_log row; it does not
-- return data and is not what stops an export: the report data itself is already limited by report_run.
create or replace function public.log_report_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public.rpt_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges: nobody anonymous; signed-in users reach data only through the functions above ----------
revoke all on function public.rpt_grant(text), public.rpt_week_cfg(), public.rpt_fy_cfg(), public.rpt_fy_start(date, int), public.rpt_access(text), public.rpt_cost_ok(), public.rpt_mobile_ok(), public.rpt_arr_text(jsonb), public.rpt_arr_int(jsonb), public.rpt_arr_uuid(jsonb),
  public.rpt_num(jsonb), public.rpt_date(text), public.rpt_dims(text), public.rpt_meas(text), public.rpt_def(text), public.rpt_keys(), public.rpt_filters_for(text),
  public.rpt_tok(text, text, text, int, int, boolean), public.rpt_where(text, text, jsonb, int[], date, date, text[], boolean),
  public.rpt_agg_sql(text, text, text, text[], text[], text, text, text, text, int, int, boolean, boolean, boolean),
  public.rpt_agg_build(jsonb, text[], text[], jsonb, int[], date, date, text, int, int, boolean, boolean), public.rpt_mobx(text, boolean),
  public.rpt_raw(text, jsonb, int[], date, date, boolean, int[], numeric, date),
  public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean), public.log_report_export(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean), public.log_report_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase10.sql
-- ============================================================
-- BOS tool · Phase 10 (plan B2 + B3 + B4-light): STOCK LEDGER, purchases and supplier ledger, batches / expiry.
-- Run AFTER phase8 and phase9 (it needs: rules, grants, emergency helpers rule_ok / use_emergency, lock_check, can_loc, log_change,
-- suppliers, unit_conversions / unit_factor, shelf_life_for, items.tracked / min_stock / base_unit, exceptions, option_lists).
-- ADDITIVE and IDEMPOTENT: safe to run again. Nothing existing is dropped or changed except that two triggers are ADDED on public.sales.
--
-- Principles kept
--   * Stock is counted only for items the owner marked tracked (items.tracked). With no tracked item this file changes NOTHING in the POS.
--   * The ledger is APPEND-ONLY (update / delete / truncate are blocked by triggers); a mistake is fixed by a reversing row, like a void.
--   * stock_balance is only a cache, written by a trigger on the ledger under a row lock; stock_reconcile() proves it equals the ledger.
--   * COST IS SECRET: unit_cost / avg_cost / values are not granted on the tables to the app roles. They are shown only by the functions,
--     and only to the owner, ITEM_COST holders or a holder of the grant view_cost (for that location).
--   * No business number is invented: every limit is a rule that is empty (= off) until the owner writes it; new emergency switches are off.
--   * Offline POS: a sale that syncs late still posts its stock (made_at = the sale time). With stock_negative_mode = warn / allow it never blocks;
--     a sale older than 2 minutes never blocks in any mode (it already happened). The below-zero approval is used ONCE per whole sale.
--   * Every number that comes from outside is range-checked with `not (x between lo and hi)`, so NaN / Infinity / absurd values are refused (and CHECK constraints back this up).
-- ============================================================

-- ---------- (a) settings: rules, grants, lists ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('wastage_photo_above', 'stock', 'number', null, null, null, 0, 1000000000, 'এর বেশি পরিমাণ নষ্ট হলে ছবি লাগবে (বেস এককে)', 'এর বেশি quantity নষ্ট হলে photo লাগবে (base unit এ)', 'A photo is required for a wastage above this quantity (in the item base unit)', 'Empty = off. Quantity, not money, so that cost stays secret', 100),
 ('count_tolerance_pct', 'stock', 'number', null, '%', null, 0, 1000, 'গণনায় পার্থক্য এর বেশি হলে মালিককে জানানো (%)', 'Count এ পার্থক্য এর বেশি হলে মালিককে জানানো (%)', 'Tell the owner when a stock count differs by more than this %', 'Empty = off', 101),
 ('purchase_cost_jump_pct', 'purchase', 'number', null, '%', null, 0, 1000, 'আগের কেনার দামের চেয়ে এত % বেশি/কম হলে মালিককে জানানো', 'আগের কেনার দামের চেয়ে এত % বেশি/কম হলে মালিককে জানানো', 'Tell the owner when a unit cost differs from the last purchase by more than this %', 'Empty = off', 110),
 ('purchase_separate_poster', 'purchase', 'switch', 'false', null, null, null, null, 'যে বিল লিখেছে সে নিজে পোস্ট করতে পারবে না', 'যে bill লিখেছে সে নিজে post করতে পারবে না', 'The person who wrote a purchase bill cannot post it (the owner still can)', 'Off by default', 111),
 ('em_sell_below_zero', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: স্টকের চেয়ে বেশি বিক্রি', 'জরুরি request চলবে: stock এর চেয়ে বেশি বিক্রি', 'Emergency allowed for: selling more than the stock', 'Off by default', 120),
 ('em_stock_opening', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: প্রারম্ভিক স্টক', 'জরুরি request চলবে: opening stock', 'Emergency allowed for: opening stock', 'Off by default', 121),
 ('em_wastage', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: নষ্ট মাল বাদ দেওয়া', 'জরুরি request চলবে: wastage write-off', 'Emergency allowed for: wastage write-off', 'Off by default', 122),
 ('em_purchase_entry', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় এন্ট্রি', 'জরুরি request চলবে: purchase entry', 'Emergency allowed for: purchase entry', 'Off by default', 123),
 ('em_purchase_return', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় ফেরত', 'জরুরি request চলবে: purchase return', 'Emergency allowed for: purchase return', 'Off by default', 124),
 ('em_supplier_pay', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: সাপ্লায়ারকে পেমেন্ট', 'জরুরি request চলবে: supplier payment', 'Emergency allowed for: paying a supplier', 'Off by default', 125),
 ('em_purchase_void', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: ক্রয় বাতিল', 'জরুরি request চলবে: purchase void', 'Emergency allowed for: voiding a purchase', 'Off by default', 126)
on conflict (key) do nothing;

-- new grants. Role grants are seeded ONLY the first time a grant is created (an owner who removes one is not overruled by a re-run).
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('sell_below_zero', 'stock', 40, 'স্টকের চেয়ে বেশি বিক্রি', 'Stock এর চেয়ে বেশি বিক্রি', 'Sell more than the stock', 'once', 'em_sell_below_zero'),
   ('stock_opening', 'stock', 41, 'প্রারম্ভিক স্টক বসানো', 'Opening stock বসানো', 'Enter opening stock', 'once', 'em_stock_opening'),
   ('wastage_write_off', 'stock', 42, 'নষ্ট / অপচয় মাল বাদ দেওয়া', 'নষ্ট / wastage মাল বাদ দেওয়া', 'Write off wasted stock', 'once', 'em_wastage'),
   ('stock_count_adjust', 'stock', 43, 'গণনা অনুযায়ী স্টক ঠিক করা', 'Count অনুযায়ী stock ঠিক করা', 'Adjust stock to a count', 'once', null),
   ('stock_transfer', 'stock', 44, 'এক জায়গা থেকে অন্য জায়গায় মাল পাঠানো / গ্রহণ', 'এক জায়গা থেকে অন্য জায়গায় মাল পাঠানো / receive', 'Send / receive stock between locations', 'once', null),
   ('stock_issue', 'stock', 45, 'উৎপাদনে কাঁচামাল দেওয়া', 'Production এ কাঁচামাল issue', 'Issue material to production', 'once', null),
   ('stock_production', 'stock', 46, 'উৎপাদিত মাল স্টকে তোলা', 'Production এর মাল stock এ তোলা', 'Post production into stock', 'once', null),
   ('purchase_entry', 'purchase', 50, 'ক্রয় বিল লেখা ও পোস্ট করা', 'Purchase bill লেখা ও post করা', 'Write and post purchase bills', 'once', 'em_purchase_entry'),
   ('purchase_return', 'purchase', 51, 'সাপ্লায়ারকে মাল ফেরত', 'Supplier কে মাল ফেরত', 'Return goods to a supplier', 'once', 'em_purchase_return'),
   ('supplier_pay', 'purchase', 52, 'সাপ্লায়ারকে টাকা দেওয়া', 'Supplier কে টাকা দেওয়া', 'Pay a supplier', 'once', 'em_supplier_pay'),
   ('purchase_void', 'purchase', 53, 'ক্রয় বিল / সাপ্লায়ার পেমেন্ট বাতিল', 'Purchase bill / supplier payment বাতিল', 'Void a purchase or a supplier payment', 'once', 'em_purchase_void')
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('wastage_write_off', 'storekeeper'), ('wastage_write_off', 'showroom_manager'), ('wastage_write_off', 'factory_incharge'), ('wastage_write_off', 'management'),
    ('stock_count_adjust', 'management'),
    ('stock_transfer', 'storekeeper'), ('stock_transfer', 'showroom_manager'), ('stock_transfer', 'factory_incharge'),
    ('stock_issue', 'storekeeper'), ('stock_issue', 'factory_incharge'),
    ('stock_production', 'factory_incharge'),
    ('purchase_entry', 'purchasing'), ('purchase_entry', 'storekeeper')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'expired', 'মেয়াদ শেষ', 'মেয়াদ শেষ', 'Expired', 1), ('wastage_reasons', 'spoiled', 'নষ্ট / পচে গেছে', 'নষ্ট / spoiled', 'Spoiled', 2),
 ('wastage_reasons', 'burnt', 'পুড়ে গেছে', 'পুড়ে গেছে', 'Burnt', 3), ('wastage_reasons', 'broken', 'ভেঙে গেছে', 'ভেঙে গেছে', 'Broken', 4),
 ('wastage_reasons', 'sample', 'নমুনা / বিনামূল্যে', 'Sample / free', 'Sample / free', 5), ('wastage_reasons', 'staff_meal', 'স্টাফ খাবার', 'Staff meal', 'Staff meal', 6),
 ('wastage_reasons', 'unknown', 'কারণ অজানা', 'কারণ unknown', 'Unknown reason', 9),
 ('return_reasons', 'damaged', 'ক্ষতিগ্রস্ত', 'Damaged', 'Damaged', 1), ('return_reasons', 'wrong_item', 'ভুল মাল', 'ভুল item', 'Wrong item', 2),
 ('return_reasons', 'quality', 'মান ভালো না', 'Quality ভালো না', 'Poor quality', 3), ('return_reasons', 'excess', 'বেশি এসেছে', 'বেশি এসেছে', 'Excess delivered', 4),
 ('return_reasons', 'other', 'অন্যান্য', 'Other', 'Other', 9)
on conflict (list_code, value_code) do nothing;

-- ---------- (b) tables ----------
-- the ledger: one row per movement, in the item BASE unit. Never changed after it is written.
create table if not exists public.stock_batches (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  made_at timestamptz not null,
  qty_made numeric not null check (qty_made > 0),
  qty_remaining numeric not null check (qty_remaining >= 0),
  expires_at timestamptz,                                  -- null = no shelf-life rule: expiry features are off for this batch
  shelf_rule jsonb,                                        -- the shelf_life_for() answer used (season / scope), for the record
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists stock_batches_open on public.stock_batches (item_id, location_id, expires_at) where qty_remaining > 0;
create index if not exists stock_batches_exp on public.stock_batches (location_id, expires_at) where qty_remaining > 0 and expires_at is not null;

create table if not exists public.stock_ledger (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty_delta numeric not null check (qty_delta <> 0 and qty_delta <> 'NaN'::numeric),     -- in the item base unit; + in, - out
  unit_cost numeric check (unit_cost is null or unit_cost >= 0),                          -- per base unit. SECRET: not granted to the app roles
  reason text not null check (reason in ('opening', 'purchase_in', 'purchase_return', 'sale_out', 'sale_void_in', 'sale_return', 'issue_out',
                                         'production_in', 'transfer_out', 'transfer_in', 'wastage', 'count_adjust', 'reversal')),
  ref_type text, ref_id text,
  batch_id bigint references public.stock_batches(id),
  reverses_id bigint references public.stock_ledger(id),   -- set on a row that undoes another
  client_id uuid,                                          -- makes a re-sent phone request harmless
  made_at timestamptz not null default now(),              -- when it happened in the business (a late-synced sale keeps its sale time)
  note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists stock_ledger_pair on public.stock_ledger (item_id, location_id, id);
create index if not exists stock_ledger_ref on public.stock_ledger (ref_type, ref_id);
create index if not exists stock_ledger_loc_time on public.stock_ledger (location_id, made_at);
create unique index if not exists stock_ledger_one_reversal on public.stock_ledger (reverses_id) where reverses_id is not null;
create unique index if not exists stock_ledger_one_opening on public.stock_ledger (item_id, location_id) where reason = 'opening';
create unique index if not exists stock_ledger_client on public.stock_ledger (client_id, reason) where client_id is not null;

create table if not exists public.stock_balance (
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null default 0,
  avg_cost numeric,                                        -- weighted average per base unit. SECRET: not granted to the app roles
  updated_at timestamptz not null default now(),
  primary key (item_id, location_id)
);

create table if not exists public.stock_wastage (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0),                    -- base unit
  reason_code text not null,                               -- from the editable list wastage_reasons
  note text, photo text,
  batch_id bigint references public.stock_batches(id),
  ledger_id bigint references public.stock_ledger(id),     -- first ledger row (a write-off that spans batches has several rows with ref_id = this id)
  made_at timestamptz not null default now(),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists stock_wastage_loc on public.stock_wastage (location_id, made_at);

create table if not exists public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  from_location_id int not null references public.locations(id),
  to_location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  qty numeric not null check (qty > 0),                    -- base unit, as sent
  status text not null default 'sent' check (status in ('sent', 'received', 'cancelled')),
  received_qty numeric check (received_qty is null or received_qty >= 0),
  note text, receive_note text,
  sent_by uuid, sent_staff text, sent_at timestamptz not null default now(),
  received_by uuid, received_staff text, received_at timestamptz,
  cancelled_by uuid, cancelled_at timestamptz,
  check (from_location_id <> to_location_id)
);
create index if not exists stock_transfers_open on public.stock_transfers (to_location_id) where status = 'sent';

create table if not exists public.purchase_bills (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  kind text not null default 'bill' check (kind in ('bill', 'return')),         -- a return is money back from the supplier (a credit)
  supplier_id uuid not null references public.suppliers(id),
  bill_no text,                                            -- the supplier's own bill number
  bill_date date not null,
  location_id int not null references public.locations(id),
  status text not null default 'draft' check (status in ('draft', 'posted', 'void')),
  subtotal numeric not null default 0 check (subtotal >= 0),
  discount numeric not null default 0 check (discount >= 0),
  total numeric not null default 0 check (total >= 0),
  paid numeric not null default 0 check (paid >= 0),      -- paid at the time of posting (later payments are allocated oldest-first)
  due numeric generated always as (total - paid) stored,
  note text, photo text, reason_code text,
  ref_bill_id uuid references public.purchase_bills(id),
  variance numeric,                                        -- a return: credit given by the supplier minus the stock taken out at average cost (SECRET, a book difference)
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  posted_by uuid, posted_at timestamptz,
  void_by uuid, void_at timestamptz, void_note text,
  check (discount <= subtotal), check (paid <= total)
);
create unique index if not exists purchase_bills_client on public.purchase_bills (client_id) where client_id is not null;
create unique index if not exists purchase_bills_no on public.purchase_bills (supplier_id, lower(bill_no), kind) where bill_no is not null and status <> 'void';
create index if not exists purchase_bills_sup on public.purchase_bills (supplier_id, status);
create index if not exists purchase_bills_loc on public.purchase_bills (location_id, bill_date);

create table if not exists public.purchase_lines (
  id bigserial primary key,
  bill_id uuid not null references public.purchase_bills(id) on delete cascade,
  line_no int not null,
  item_id uuid references public.items(id),                -- null = a free-text, non-stock line (gas, transport ...)
  description text,
  qty numeric not null check (qty > 0),
  unit text,
  unit_cost numeric not null check (unit_cost >= 0),       -- SECRET (per the unit written on the line)
  amount numeric not null check (amount >= 0),
  base_qty numeric,                                        -- filled when posted (tracked items)
  unit_cost_base numeric,                                  -- per base unit, before the bill discount; filled when posted
  check (item_id is not null or nullif(btrim(description), '') is not null),
  unique (bill_id, line_no)
);

create table if not exists public.supplier_payments (
  id bigserial primary key,
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  bill_id uuid references public.purchase_bills(id),       -- paid against one bill at posting; null = a general payment, allocated to the oldest bills
  kind text not null default 'payment' check (kind in ('payment')),
  mode text not null check (mode in ('cash', 'mobile', 'card', 'bank')),
  wallet text, ref text,
  amount numeric not null check (amount > 0),
  paid_at timestamptz not null default now(),
  note text,
  voided boolean not null default false, void_note text, void_by uuid,
  created_by uuid, created_staff text,
  client_id uuid
);
create index if not exists supplier_payments_sup on public.supplier_payments (supplier_id) where not voided;
create index if not exists supplier_payments_client on public.supplier_payments (client_id) where client_id is not null;
create index if not exists supplier_payments_loc on public.supplier_payments (location_id, paid_at);

-- audit trail for the changeable tables (the ledger itself needs none: it can never change)
drop trigger if exists audit_stock_transfers on public.stock_transfers;
create trigger audit_stock_transfers after insert or update on public.stock_transfers for each row execute function public.log_change('id');
drop trigger if exists audit_purchase_bills on public.purchase_bills;
create trigger audit_purchase_bills after insert or update on public.purchase_bills for each row execute function public.log_change('id');
drop trigger if exists audit_supplier_payments on public.supplier_payments;
create trigger audit_supplier_payments after insert or update on public.supplier_payments for each row execute function public.log_change('id');
drop trigger if exists audit_stock_wastage on public.stock_wastage;
create trigger audit_stock_wastage after insert on public.stock_wastage for each row execute function public.log_change('id');
drop trigger if exists audit_purchase_lines on public.purchase_lines;      -- the lines carry the costs: every change of a draft is on record
create trigger audit_purchase_lines after insert or update or delete on public.purchase_lines for each row execute function public.log_change('id');

-- a column added after the first release of this file
alter table public.purchase_bills add column if not exists variance numeric;

-- defence in depth: no NaN / Infinity / absurd number can ever sit in these tables (the functions refuse them first; this is the last wall).
-- `between` is false for NaN and Infinity, and a NULL passes (NOT NULL columns say so themselves).
do $$
declare c record;
begin
  for c in select * from (values
    ('stock_ledger',     'stock_ledger_finite',     'qty_delta between -1000000000000 and 1000000000000 and unit_cost between 0 and 1000000000000'),
    ('stock_balance',    'stock_balance_finite',    'qty between -1000000000000 and 1000000000000 and avg_cost between 0 and 1000000000000'),
    ('stock_batches',    'stock_batches_finite',    'qty_made between 0 and 1000000000000 and qty_remaining between 0 and 1000000000000'),
    ('stock_wastage',    'stock_wastage_finite',    'qty between 0 and 1000000000000'),
    ('stock_transfers',  'stock_transfers_finite',  'qty between 0 and 1000000000000 and received_qty between 0 and 1000000000000'),
    ('purchase_bills',   'purchase_bills_finite',   'subtotal between 0 and 1000000000000 and discount between 0 and 1000000000000 and total between 0 and 1000000000000 and paid between 0 and 1000000000000 and variance between -1000000000000 and 1000000000000'),
    ('purchase_lines',   'purchase_lines_finite',   'qty between 0 and 1000000000000 and unit_cost between 0 and 1000000000000 and amount between 0 and 1000000000000 and base_qty between 0 and 1000000000000 and unit_cost_base between 0 and 1000000000000'),
    ('supplier_payments','supplier_payments_finite','amount between 0 and 1000000000000')) v(t, n, e) loop
    if not exists (select 1 from pg_constraint where conname = c.n and conrelid = ('public.' || c.t)::regclass) then
      execute format('alter table public.%I add constraint %I check (%s)', c.t, c.n, c.e);
    end if;
  end loop;
end $$;

-- ---------- (c) helpers (internal) ----------
-- management and the owner can work at every location
create or replace function public._all_locs() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.user_roles where user_id = auth.uid() and role_code = 'management'));
$$;

-- may the caller use grant p_code at location p_loc? owner / role / personal grant / approved emergency WINDOW (read only) or a ONE-USE emergency approval (consumed here)
create or replace function public._may(p_code text, p_loc int, p_ref text default 'stock', p_amount numeric default null) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  return public.has_grant(p_code, p_loc) or public._use_em(p_code, p_loc, p_ref, p_amount);
end $$;

-- an emergency approval used inside the stock / purchase functions: use_emergency consumes it, and the owner gets a yellow line every time
create or replace function public._use_em(p_grant text, p_loc int, p_ref text, p_amount numeric default null) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.use_emergency(p_grant, p_loc, p_ref, p_amount, null) then return false; end if;
  perform public._stock_exc(p_loc, 'emergency_used', 'yellow', 'জরুরি অনুমোদনে কাজ হয়েছে: ' || p_grant || ' (' || left(coalesce(p_ref, ''), 60) || ')',
    'An emergency approval was used: ' || p_grant || ' (' || left(coalesce(p_ref, ''), 60) || ')', null, null, 'EMERGENCY', p_amount);
  return true;
end $$;

-- two requests with the same client id (a phone retry racing the first try) queue here, so the second one sees the first one's rows
create or replace function public._client_lock(p_client uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_client is not null then perform pg_advisory_xact_lock(hashtextextended('bos10:' || p_client::text, 0)); end if;
end $$;

-- may the caller see cost figures for this location?
create or replace function public._cost_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost', p_loc));
$$;

-- may the caller read purchase / supplier-payable figures (they contain costs)? p_loc null = the whole company
create or replace function public._pur_ok(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (case when p_loc is null then public._all_locs() else public.can_loc(p_loc) end)
    and (public.is_owner() or public.has_grant('purchase_entry', p_loc) or public.has_grant('purchase_return', p_loc) or public.has_grant('supplier_pay', p_loc)
         or public.has_grant('purchase_void', p_loc) or public.has_grant('view_cost', p_loc));
$$;

create or replace function public._item_base(p_item uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(btrim(base_unit), ''), nullif(btrim(unit), '')) from public.items where id = p_item;
$$;

-- quantity written in p_unit -> item base unit. null when the conversion is unknown (nothing is guessed). No unit = already base.
create or replace function public._base_qty(p_item uuid, p_qty numeric, p_unit text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare b text := public._item_base(p_item); f numeric;
begin
  if p_unit is null or btrim(p_unit) = '' or b is null or p_unit = b then return p_qty; end if;
  f := public.unit_factor(p_item, p_unit, b);
  if f is null then return null; end if;
  return p_qty * f;
end $$;
create or replace function public._unit_factor_base(p_item uuid, p_unit text) returns numeric      -- base units in ONE p_unit
language plpgsql stable security definer set search_path = public as $$
declare b text := public._item_base(p_item);
begin
  if p_unit is null or btrim(p_unit) = '' or b is null or p_unit = b then return 1; end if;
  return public.unit_factor(p_item, p_unit, b);
end $$;

-- weighted-average cost: the one rule used by the trigger and by the replay in stock_reconcile
--   in with a cost  -> (old_qty * old_avg + qty * cost) / (old_qty + qty)   (old stock <= 0 or unknown cost: the new cost)
--   out             -> average unchanged, except a reversal of a costed receipt, which takes its cost back out
--                      (a purchase return leaves the stock at the CURRENT average, so it never moves the average)
create or replace function public._avg_next(p_qty numeric, p_avg numeric, p_delta numeric, p_cost numeric, p_reason text) returns numeric
language plpgsql immutable as $$
declare r numeric;
begin
  if p_delta > 0 then
    if p_cost is null then return p_avg; end if;
    if p_avg is null or p_qty <= 0 then return round(p_cost, 6); end if;
    return round((p_qty * p_avg + p_delta * p_cost) / (p_qty + p_delta), 6);
  end if;
  if p_reason = 'reversal' and p_cost is not null and p_avg is not null and p_qty + p_delta > 0 then
    r := (p_qty * p_avg + p_delta * p_cost) / (p_qty + p_delta);
    if r >= 0 then return round(r, 6); end if;
  end if;
  return p_avg;
end $$;

-- one yellow / red line for the owner in the exceptions list (once per sale, flag and text)
create or replace function public._stock_exc(p_loc int, p_flag text, p_level text, p_bn text, p_en text, p_sale uuid default null, p_date date default null, p_form text default 'STOCK', p_amount numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_sale is not null and exists (select 1 from public.exceptions where sale_id = p_sale and flag_code = p_flag and text->>'en' = p_en) then return; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, p_sale, p_form, p_loc, coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date), p_flag, p_level, p_amount, jsonb_build_object('bn', p_bn, 'en', p_en));
end $$;

-- ---------- (d) the ledger: immutability and the balance cache ----------
create or replace function public._ledger_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'ledger_immutable' using hint = 'Fix a mistake with a reversing row, never by editing the ledger';
end $$;
drop trigger if exists stock_ledger_no_update on public.stock_ledger;
create trigger stock_ledger_no_update before update or delete on public.stock_ledger for each row execute function public._ledger_immutable();
drop trigger if exists stock_ledger_no_truncate on public.stock_ledger;
create trigger stock_ledger_no_truncate before truncate on public.stock_ledger for each statement execute function public._ledger_immutable();
drop trigger if exists stock_wastage_no_update on public.stock_wastage;
create trigger stock_wastage_no_update before update or delete on public.stock_wastage for each row execute function public._ledger_immutable();

-- every ledger row moves the cache in the same transaction (the caller already holds the row lock; this also covers a first row)
create or replace function public._ledger_to_balance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.stock_balance set avg_cost = public._avg_next(qty, avg_cost, new.qty_delta, new.unit_cost, new.reason),
         qty = qty + new.qty_delta, updated_at = now()
   where item_id = new.item_id and location_id = new.location_id;
  if not found then
    insert into public.stock_balance (item_id, location_id, qty, avg_cost)
      values (new.item_id, new.location_id, new.qty_delta, public._avg_next(0, null, new.qty_delta, new.unit_cost, new.reason));
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_balance on public.stock_ledger;
create trigger stock_ledger_balance after insert on public.stock_ledger for each row execute function public._ledger_to_balance();

-- THE ONLY WRITER of the ledger. Internal (no app role may call it).  p_qty is in the BASE unit.
--   p_neg: 'full' = stock_negative_mode applies (allow / warn / block, block lifted by grant or emergency 'sell_below_zero')
--          'soft' = warn only (never blocks: reversals, late-synced sales)   'none' = no check (opening, count adjustments, receipts)
-- A stock-out is taken from the open batches: NOT-expired ones first (oldest expiry first), expired ones last (and a sale from an expired batch is a RED
-- exception 'sold_expired'); the rest without a batch.  Returns the first ledger id.
-- The same p_client (a re-sent request) returns the first ledger id again and writes nothing (checked under the balance row lock, so a race is safe).
create or replace function public.stock_post(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_ref_type text default null, p_ref_id text default null,
  p_unit_cost numeric default null, p_batch bigint default null, p_made_at timestamptz default null, p_note text default null,
  p_reverses bigint default null, p_neg text default 'full', p_sale uuid default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        -- the approval is asked ONCE per whole sale: when one line was let through, the other lines of the same sale are too
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          -- (a POS sale already writes its own 'emergency_used' line for the sale, so the helper that writes one is used only outside a sale)
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      -- a yellow line for the owner, once per item / location / day, and only for an item that has been opened (a tracked item never opened is not "negative", it is not started)
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
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      -- a rest under 0.0005 of a base unit is conversion dust: the batch closes
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
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
    elsif p_reason in ('sale_void_in', 'reversal') then
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $$;

-- ---------- (e) POS hook: sale_out when a sale is saved, sale_void_in when it is voided (tracked items only; record_sale2 is NOT changed) ----------
create or replace function public._sale_stock_out() returns trigger
language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
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
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, স্টক কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_stock_out on public.sales;
create trigger sales_stock_out after insert on public.sales for each row execute function public._sale_stock_out();

create or replace function public._sale_stock_void() returns trigger
language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  for r in select * from public.stock_ledger o where o.ref_type = 'sale' and o.ref_id = new.id::text and o.reason = 'sale_out'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'sale_void_in', 'sale', new.id::text, r.unit_cost, r.batch_id, now(), null, r.id, 'none', new.id);
  end loop;
  return new;
end $$;
drop trigger if exists sales_stock_void on public.sales;
create trigger sales_stock_void after update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_stock_void();

-- ---------- (f) stock functions (all SECURITY DEFINER) ----------
-- checks shared by the manual stock functions: item tracked, caller allowed at the location, period open
create or replace function public._stock_guard(p_item uuid, p_loc int, p_grant text, p_date date default null) returns public.items
language plpgsql security definer set search_path = public as $$
declare it public.items;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if not it.tracked then raise exception 'item_not_tracked'; end if;
  if p_date is not null then perform public.lock_check(p_date); end if;
  return it;
end $$;

-- counted opening balance: once per item and location (a later error is fixed with stock_count_adjust)
create or replace function public.stock_opening(p_item uuid, p_loc int, p_qty numeric, p_unit_cost numeric default null, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; f numeric; cost numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_opening', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'opening'; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  if not public._may('stock_opening', p_loc, 'opening:' || p_item::text) then raise exception 'not allowed'; end if;
  perform 1 from public.items where id = p_item for no key update;                -- two people entering the same opening wait here (NO KEY UPDATE: ledger inserts take a KEY SHARE lock on the item, so this can never deadlock with them)
  if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and reason = 'opening') then raise exception 'opening_exists'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  cost := case when p_unit_cost is null then null else p_unit_cost / f end;       -- cost given per p_unit -> per base unit
  lid := public.stock_post(p_item, p_loc, bq, 'opening', 'opening', null, cost, null, now(), left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $$;

-- write off wasted stock. Reason from the editable list wastage_reasons. Photo required above the owner's quantity limit (rule wastage_photo_above, empty = off).
create or replace function public.stock_wastage(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_note text default null, p_photo text default null,
  p_unit text default null, p_client uuid default null, p_batch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; wid uuid := gen_random_uuid(); lim numeric; sid text; nm text;
begin
  it := public._stock_guard(p_item, p_loc, 'wastage_write_off', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'wastage' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  lim := public.rule_num('wastage_photo_above');
  if lim is not null and bq > lim and nullif(btrim(p_photo), '') is null then raise exception 'photo_required'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if not public._may('wastage_write_off', p_loc, 'wastage:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if p_batch is not null and not exists (select 1 from public.stock_batches where id = p_batch and item_id = p_item and location_id = p_loc) then raise exception 'batch_not_found'; end if;
  begin
    lid := public.stock_post(p_item, p_loc, -bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
      values (wid, p_item, p_loc, bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, auth.uid(), sid);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins, this one is the duplicate
    select id into lid from public.stock_ledger where p_client is not null and client_id = p_client and reason = 'wastage' order by id limit 1;
    if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    raise;
  end;
  if p_reason = 'unknown' then
    nm := it.name_bn;
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', nm || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, nm) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', bq);
end $$;

-- move the end-of-day unsold / expired part of ONE batch to wastage
create or replace function public.stock_expire_batch(p_batch bigint, p_reason text default 'expired', p_note text default null, p_photo text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.stock_batches;
begin
  select * into b from public.stock_batches where id = p_batch;
  if not found then raise exception 'batch_not_found'; end if;
  if b.qty_remaining <= 0 then raise exception 'batch_empty'; end if;
  return public.stock_wastage(b.item_id, b.location_id, b.qty_remaining, p_reason, p_note, p_photo, null, null, b.id);
end $$;

-- the physical count says p_counted: post the difference (needs a note). Tolerance rule count_tolerance_pct (empty = off) only informs the owner.
create or replace function public.stock_count_adjust(p_item uuid, p_loc int, p_counted numeric, p_note text, p_unit text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  lid := public.stock_post(p_item, p_loc, d, 'count_adjust', 'count', null, null, null, now(), left(p_note, 200), null, 'none', null, p_client);
  tol := public.rule_num('count_tolerance_pct');
  if tol is not null and (bal.qty = 0 or abs(d) / abs(bal.qty) * 100 > tol) then
    perform public._stock_exc(p_loc, 'stock_count_variance', 'yellow', it.name_bn || ': গণনায় ' || d::text || ' পার্থক্য', coalesce(it.name_en, it.name_bn) || ': the count differs from the book by ' || d::text);
  end if;
  return jsonb_build_object('ledger_id', lid, 'delta', d, 'qty', bq);
end $$;

-- material issued to production
create or replace function public.stock_issue(p_item uuid, p_loc int, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint;
begin
  it := public._stock_guard(p_item, p_loc, 'stock_issue', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id into lid from public.stock_ledger where client_id = p_client and reason = 'issue_out' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_issue', p_loc, 'issue:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  lid := public.stock_post(p_item, p_loc, -bq, 'issue_out', 'issue', null, null, null, now(), left(p_note, 200), null, 'full', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'qty', bq);
end $$;

-- finished goods made: stock in + a batch whose expiry comes from the owner's shelf-life rules (no rule = no expiry, expires_at null)
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric; ucb numeric; pct numeric; av numeric;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  -- the cost of what was made against the average cost already in stock: a big move is told to the owner (same limit as purchases, rule purchase_cost_jump_pct)
  pct := public.rule_num('purchase_cost_jump_pct');
  if p_unit_cost is not null and pct is not null then
    ucb := p_unit_cost / f;
    select avg_cost into av from public.stock_balance where item_id = p_item and location_id = p_loc;
    if av is not null and av > 0 and abs(ucb - av) / av * 100 > pct then
      perform public._stock_exc(p_loc, 'production_cost_jump', 'yellow',
        it.name_bn || ': উৎপাদন খরচ গড় খরচের চেয়ে ' || round((ucb - av) / av * 100, 1)::text || '% বদলেছে',
        coalesce(it.name_en, it.name_bn) || ': production cost moved ' || round((ucb - av) / av * 100, 1)::text || '% from the average cost in stock', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
    end if;
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- transfer: OUT at the sender at once, IN at the receiver only when they receive it (in between it is "in transit", not lost)
create or replace function public.stock_transfer(p_from int, p_to int, p_item uuid, p_qty numeric, p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; tid uuid := gen_random_uuid(); sid text; t public.stock_transfers; lid bigint;
begin
  it := public._stock_guard(p_item, p_from, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  end if;
  if p_to is null or p_to = p_from or not exists (select 1 from public.locations where id = p_to) then raise exception 'bad_location'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if not public._may('stock_transfer', p_from, 'transfer:' || p_item::text, bq) then raise exception 'not allowed'; end if;
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
end $$;

-- the destination receives (p_received_qty in the BASE unit, default = all that was sent). Less than sent -> an exception (transit_short).
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; cost numeric; ob public.stock_batches; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty then raise exception 'over_received'; end if;
  rem := rq;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    take := least(-o.qty_delta, rem);
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
  update public.stock_transfers set status = 'received', received_qty = rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || rq::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || rq::text || ' — short in transit');
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', rq, 'short', t.qty - rq);
end $$;

-- the sender takes back a transfer that is still in transit (a reversing row)
create or replace function public.stock_cancel_transfer(p_id uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; o public.stock_ledger;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'cancelled' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  perform public._stock_guard(t.item_id, t.from_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not (t.sent_by = auth.uid() or public.is_owner() or public.has_grant('stock_transfer', t.from_location_id)) then raise exception 'not allowed'; end if;
  for o in select * from public.stock_ledger x where x.ref_type = 'transfer' and x.ref_id = t.id::text and x.reason = 'transfer_out' order by x.id loop
    perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', 'transfer', t.id::text, o.unit_cost, o.batch_id, now(), left(p_note, 200), o.id, 'none');
  end loop;
  update public.stock_transfers set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now(), receive_note = left(p_note, 200) where id = t.id;
  return jsonb_build_object('id', t.id, 'status', 'cancelled');
end $$;

-- ---------- (g) stock reads ----------
-- stock on hand. p_filters: {"category":"..","q":"name or code","below_min":true,"include_zero":true,"item_ids":["uuid",..]}
-- Staff see quantities at their own locations; avg_cost and value only where the caller may see cost.
create or replace function public.stock_levels(p_loc int default null, p_filters jsonb default '{}'::jsonb)
returns table (item_id uuid, code text, name_bn text, name_en text, category text, base_unit text, location_id int, qty numeric, min_stock numeric, below_min boolean, avg_cost numeric, value numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare f jsonb := coalesce(p_filters, '{}'::jsonb); ids uuid[]; locs int[]; clocs int[];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  -- who may see which location is worked out ONCE (a few locations), never per row (thousands of items)
  select coalesce(array_agg(x.id), '{}') into locs from public.locations x where public.can_loc(x.id);
  select coalesce(array_agg(x.id), '{}') into clocs from public.locations x where x.id = any (locs) and public._cost_ok(x.id);
  if f ? 'item_ids' and jsonb_typeof(f->'item_ids') = 'array' then select array_agg(x::uuid) into ids from jsonb_array_elements_text(f->'item_ids') x; end if;
  return query
    select i.id, i.code, i.name_bn, i.name_en, i.category, public._item_base(i.id), l.id,
           coalesce(b.qty, 0), i.min_stock,
           (i.min_stock is not null and coalesce(b.qty, 0) < i.min_stock),
           case when l.id = any (clocs) then b.avg_cost end,
           case when l.id = any (clocs) and b.avg_cost is not null then round(b.qty * b.avg_cost, 2) end
    from public.items i
    cross join public.locations l
    left join public.stock_balance b on b.item_id = i.id and b.location_id = l.id
    where i.tracked and i.is_active
      and l.id = any (locs) and (p_loc is null or l.id = p_loc)
      and (b.item_id is not null or p_loc is not null)
      and (coalesce((f->>'include_zero')::boolean, false) or p_loc is not null or coalesce(b.qty, 0) <> 0)
      and (f->>'category' is null or i.category = f->>'category')
      and (f->>'q' is null or i.name_bn ilike '%' || (f->>'q') || '%' or i.name_en ilike '%' || (f->>'q') || '%' or i.code ilike '%' || (f->>'q') || '%')
      and (ids is null or i.id = any (ids))
      and (not coalesce((f->>'below_min')::boolean, false) or (i.min_stock is not null and coalesce(b.qty, 0) < i.min_stock))
    order by i.code, l.id;
end $$;

-- weighted-average cost of an item at a location: null for anyone who may not see cost
create or replace function public.stock_avg_cost(p_item uuid, p_loc int) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public._cost_ok(p_loc) and public.can_loc(p_loc) then (select avg_cost from public.stock_balance where item_id = p_item and location_id = p_loc) end;
$$;

-- the movements of one item / location (cost shown only to those who may see it)
create or replace function public.stock_ledger_rows(p_loc int, p_item uuid default null, p_from date default null, p_to date default null, p_limit int default 200)
returns table (id bigint, item_id uuid, location_id int, qty_delta numeric, unit_cost numeric, reason text, ref_type text, ref_id text, batch_id bigint, made_at timestamptz, note text, created_by uuid, reverses_id bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare ck boolean; pk boolean;
begin
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  ck := public._cost_ok(p_loc); pk := public._pur_ok(p_loc);             -- once: every row here is at p_loc
  return query
    select l.id, l.item_id, l.location_id, l.qty_delta, case when ck then l.unit_cost end, l.reason, l.ref_type,
           case when l.ref_type = 'purchase' and not pk then null else l.ref_id end,          -- a purchase id would open the bill (costs): only the purchase people get it
           l.batch_id, l.made_at, l.note, l.created_by, l.reverses_id
    from public.stock_ledger l
    where l.location_id = p_loc and (p_item is null or l.item_id = p_item)
      and (p_from is null or (l.made_at at time zone 'Asia/Dhaka')::date >= p_from) and (p_to is null or (l.made_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by l.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;

-- goods on the way
create or replace function public.stock_in_transit(p_loc int default null)
returns table (id uuid, item_id uuid, code text, name_bn text, from_location_id int, to_location_id int, qty numeric, sent_at timestamptz, sent_staff text, note text)
language sql stable security definer set search_path = public as $$
  select t.id, t.item_id, i.code, i.name_bn, t.from_location_id, t.to_location_id, t.qty, t.sent_at, t.sent_staff, t.note
  from public.stock_transfers t join public.items i on i.id = t.item_id
  where t.status = 'sent' and (public.can_loc(t.from_location_id) or public.can_loc(t.to_location_id))
    and (p_loc is null or t.from_location_id = p_loc or t.to_location_id = p_loc)
  order by t.sent_at;
$$;

-- batches that expire within p_hours_ahead hours (already expired ones included). No shelf-life rule -> the batch has no expiry and never shows here.
create or replace function public.expiry_list(p_loc int default null, p_hours_ahead numeric default 24)
returns table (batch_id bigint, item_id uuid, code text, name_bn text, name_en text, location_id int, made_at timestamptz, expires_at timestamptz, qty_remaining numeric, hours_left numeric, expired boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare locs int[]; hrs numeric := coalesce(p_hours_ahead, 24);
begin
  if not (hrs between -1000000 and 1000000) then hrs := 24; end if;     -- NaN / Infinity / absurd -> the default
  select coalesce(array_agg(x.id), '{}') into locs from public.locations x where public.can_loc(x.id);
  return query
    select b.id, b.item_id, i.code, i.name_bn, i.name_en, b.location_id, b.made_at, b.expires_at, b.qty_remaining,
           round((extract(epoch from (b.expires_at - now())) / 3600)::numeric, 2), b.expires_at <= now()
    from public.stock_batches b join public.items i on i.id = b.item_id
    where b.qty_remaining > 0 and b.expires_at is not null and b.location_id = any (locs)
      and (p_loc is null or b.location_id = p_loc)
      and b.expires_at <= now() + (hrs::float8 * interval '1 hour')
    order by b.expires_at, b.id;
end $$;

-- stock value at average cost (cost-gated: only locations where the caller may see cost)
create or replace function public.stock_valuation(p_loc int default null)
returns table (location_id int, item_id uuid, code text, name_bn text, qty numeric, avg_cost numeric, value numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare clocs int[];
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not (public.can_loc(p_loc) and public._cost_ok(p_loc)) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(x.id), '{}') into clocs from public.locations x where public.can_loc(x.id) and public._cost_ok(x.id);     -- once, not per row
  return query
    select b.location_id, b.item_id, i.code, i.name_bn, b.qty, b.avg_cost, round(b.qty * b.avg_cost, 2)
    from public.stock_balance b join public.items i on i.id = b.item_id
    where b.qty <> 0 and b.avg_cost is not null and (p_loc is null or b.location_id = p_loc)
      and b.location_id = any (clocs)
    order by b.location_id, i.code;
end $$;

-- owner: does the cache equal the ledger?  p_fix = true rewrites the CACHE (never the ledger) from the ledger.
-- With p_fix every balance row is locked while its ledger is replayed, so a sale that is being posted can never be overwritten by a stale recount.
create or replace function public.stock_reconcile(p_fix boolean default false)
returns table (item_id uuid, location_id int, ledger_qty numeric, cached_qty numeric, qty_diff numeric, cached_avg numeric, replay_avg numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare r record; l record; q numeric; a numeric; bq numeric; bavg numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
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
        update public.stock_balance z set qty = q, avg_cost = a, updated_at = now() where z.item_id = r.iid and z.location_id = r.lid;
      end if;
      return next;
    end if;
  end loop;
end $$;

-- ---------- (h) purchases and the supplier ledger ----------
-- Supplier balance = opening + posted bills - returns - payments (positive = we owe). Payments made with a bill are tied to it; later (general)
-- payments and returns clear open bills like customer dues, in two steps: (1) a payment / return made AT a location clears the oldest open bills OF THAT
-- LOCATION first; (2) what is left over (a location with nothing open, or more credit than bills there, or a credit opening balance) clears the
-- oldest open bills of the supplier anywhere. The allocation is computed, never stored, so a void just re-flows.
create or replace function public._sup_open(p_supplier uuid default null)
returns table (supplier_id uuid, bill_id uuid, bill_no text, bill_date date, location_id int, rem numeric, open_amt numeric)
language sql stable security definer set search_path = public as $$
  with bills as (
    select b.supplier_id, b.id bill_id, b.bill_no, b.bill_date, b.location_id, b.total - b.paid rem, coalesce(b.posted_at, b.created_at) ord_at, coalesce(b.location_id, -1) lk
    from public.purchase_bills b where b.status = 'posted' and b.kind = 'bill' and b.total - b.paid > 0 and (p_supplier is null or b.supplier_id = p_supplier)
    union all
    select s.id, null::uuid, 'opening', null::date, null::int, s.opening_balance, '-infinity'::timestamptz, -1
    from public.suppliers s where s.opening_balance > 0 and (p_supplier is null or s.id = p_supplier)),
  lc as (                                                                                     -- credit made at a location
    select z.supplier_id, z.lk, sum(z.x) credit from (
      select p.supplier_id, p.location_id lk, p.amount x from public.supplier_payments p where not p.voided and p.bill_id is null and (p_supplier is null or p.supplier_id = p_supplier)
      union all select b.supplier_id, b.location_id, b.total from public.purchase_bills b where b.status = 'posted' and b.kind = 'return' and (p_supplier is null or b.supplier_id = p_supplier)) z
    group by 1, 2),
  oc as (select s.id supplier_id, -s.opening_balance credit from public.suppliers s where s.opening_balance < 0 and (p_supplier is null or s.id = p_supplier)),
  c1 as (select bills.*, sum(bills.rem) over (partition by bills.supplier_id, bills.lk order by bills.bill_date nulls first, bills.ord_at, bills.bill_id) c from bills),
  a1 as (                                                                                     -- step 1: same location
    select c1.supplier_id, c1.bill_id, c1.bill_no, c1.bill_date, c1.location_id, c1.rem, c1.ord_at,
           c1.rem - least(c1.rem, greatest(0, coalesce(lc.credit, 0) - (c1.c - c1.rem))) rem2
    from c1 left join lc on lc.supplier_id = c1.supplier_id and lc.lk = c1.lk),
  pool as (                                                                                   -- what step 1 did not use
    select z.supplier_id, sum(z.credit) - coalesce((select sum(a1.rem - a1.rem2) from a1 where a1.supplier_id = z.supplier_id), 0) spill
    from (select lc.supplier_id, lc.credit from lc union all select oc.supplier_id, oc.credit from oc) z group by 1),
  c2 as (select a1.*, sum(a1.rem2) over (partition by a1.supplier_id order by a1.bill_date nulls first, a1.ord_at, a1.bill_id) cc from a1)
  select c2.supplier_id, c2.bill_id, c2.bill_no, c2.bill_date, c2.location_id, c2.rem,
         c2.rem2 - least(c2.rem2, greatest(0, coalesce(pool.spill, 0) - (c2.cc - c2.rem2)))
  from c2 left join pool on pool.supplier_id = c2.supplier_id;
$$;

create or replace function public._sup_balance(p_supplier uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0);
$$;

-- A return must stay inside the bill it points to: per item, quantity <= the bill's quantity minus what earlier (non-void) returns already took back,
-- and the unit cost <= the bill's unit cost. p_lines: [{"item_id","description","qty","unit","unit_cost"}] (unit already resolved). p_exclude = the return itself.
-- p_posted_only: at posting only POSTED earlier returns count (two drafts must not block each other).
create or replace function public._return_check(p_ref uuid, p_exclude uuid, p_lines jsonb, p_posted_only boolean default false) returns void
language plpgsql stable security definer set search_path = public as $$
declare r record;
begin
  for r in
    with rl as (
      select z.k, sum(z.bq) q, max(z.ucb) uc from (
        select case when nullif(e->>'item_id', '') is not null then e->>'item_id' else 'd:' || lower(btrim(coalesce(e->>'description', ''))) end k,
               coalesce(public._base_qty(nullif(e->>'item_id', '')::uuid, (e->>'qty')::numeric, nullif(e->>'unit', '')), (e->>'qty')::numeric) bq,
               (e->>'unit_cost')::numeric / coalesce(nullif(public._unit_factor_base(nullif(e->>'item_id', '')::uuid, nullif(e->>'unit', '')), 0), 1) ucb
        from jsonb_array_elements(p_lines) e) z group by z.k),
    bl as (
      select z.k, sum(z.bq) q, max(z.ucb) uc from (
        select case when pl.item_id is not null then pl.item_id::text else 'd:' || lower(btrim(coalesce(pl.description, ''))) end k,
               coalesce(public._base_qty(pl.item_id, pl.qty, pl.unit), pl.qty) bq,
               pl.unit_cost / coalesce(nullif(public._unit_factor_base(pl.item_id, pl.unit), 0), 1) ucb
        from public.purchase_lines pl where pl.bill_id = p_ref) z group by z.k),
    dn as (
      select z.k, sum(z.bq) q from (
        select case when pl.item_id is not null then pl.item_id::text else 'd:' || lower(btrim(coalesce(pl.description, ''))) end k,
               coalesce(public._base_qty(pl.item_id, pl.qty, pl.unit), pl.qty) bq
        from public.purchase_lines pl join public.purchase_bills x on x.id = pl.bill_id
        where x.ref_bill_id = p_ref and x.kind = 'return' and x.id is distinct from p_exclude
          and (x.status = 'posted' or (x.status = 'draft' and not p_posted_only))) z group by z.k)
    select rl.k, rl.q rq, rl.uc ruc, bl.q bq, bl.uc buc, coalesce(dn.q, 0) dq
    from rl left join bl on bl.k = rl.k left join dn on dn.k = rl.k loop
    if r.bq is null or r.rq > r.bq - r.dq + 0.00005 then raise exception 'return_exceeds_bill'; end if;
    if r.ruc > r.buc * 1.000001 + 0.000001 then raise exception 'return_cost_above_bill'; end if;
  end loop;
end $$;

-- write (or change, while it is still a draft) a purchase bill / return. Lines: [{"item_id":uuid | "description":"gas cylinder","qty":10,"unit":"kg","unit_cost":120}]
-- p_client makes a re-sent request return the same bill. Totals are computed here.
-- A RETURN must name the bill it returns from (p_ref_bill); only the owner may write one without (it then shows as a red exception when posted).
create or replace function public.save_purchase(p_client uuid, p_id uuid, p_supplier uuid, p_loc int, p_bill_no text, p_bill_date date, p_lines jsonb,
  p_discount numeric default 0, p_note text default null, p_photo text default null, p_kind text default 'bill', p_ref_bill uuid default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
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
end $$;

-- post a draft: stock IN (or OUT for a return) for tracked items with the weighted-average update, the payable, and optional payments made at once
-- p_payments: [{"mode":"cash","wallet":null,"ref":null,"amount":500}]  (needs the grant supplier_pay)
-- A return takes the goods out at the CURRENT average cost (the average never moves); the difference to the credit the supplier gives is kept on the bill as `variance`.
create or replace function public.post_purchase(p_id uuid, p_payments jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; it public.items; gcode text; f numeric; bq numeric; ucb numeric; net numeric; last_c numeric; pct numeric; sid text;
        pay jsonb; pm text; amt numeric; psum numeric := 0; jumped boolean := false; nm text; lid bigint; av numeric; var numeric := 0; norm jsonb;
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
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'posted' then return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'dup', true); end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if public.rule_on('purchase_separate_poster') and pb.created_by = auth.uid() and not public.is_owner() then raise exception 'poster_must_differ'; end if;
  perform public.lock_check(pb.bill_date);
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
    if it.tracked then
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
  return jsonb_build_object('id', pb.id, 'status', 'posted', 'total', pb.total, 'paid', psum, 'due', pb.total - psum);
end $$;

-- void a posted purchase: reversing ledger rows, and the payments made with it are voided. A draft can be cancelled by its writer.
create or replace function public.void_purchase(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; r public.stock_ledger;
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
  perform 1 from public.suppliers where id = pb.supplier_id for update;      -- one posting / payment / void at a time per supplier
  select * into pb from public.purchase_bills where id = p_id for update;
  if pb.status = 'void' then return jsonb_build_object('id', pb.id, 'status', 'void', 'dup', true); end if;
  if pb.status = 'draft' then
    update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
    return jsonb_build_object('id', pb.id, 'status', 'void');
  end if;
  perform public.lock_check(pb.bill_date);
  for r in select * from public.stock_ledger o where o.ref_type = 'purchase' and o.ref_id = pb.id::text and o.reason in ('purchase_in', 'purchase_return')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'purchase', pb.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
  end loop;
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where bill_id = pb.id and not voided;
  update public.purchase_bills set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = pb.id;
  perform public._stock_exc(pb.location_id, 'purchase_void', 'yellow', 'ক্রয় বিল বাতিল: ' || left(btrim(p_note), 100), 'A posted purchase was voided: ' || left(btrim(p_note), 100), null, pb.bill_date, 'PURCHASE', pb.total);
  return jsonb_build_object('id', pb.id, 'status', 'void');
end $$;

-- pay a supplier: one or more payments, allocated to the oldest open bills. Not more than the balance.
create or replace function public.pay_supplier(p_supplier uuid, p_loc int, p_payments jsonb, p_client uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  perform 1 from public.suppliers where id = p_supplier for update;           -- one payment at a time per supplier
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
end $$;

-- reverse a supplier payment made by mistake
create or replace function public.void_supplier_payment(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.supplier_payments;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into p from public.supplier_payments where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(p.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', p.location_id) or public._use_em('purchase_void', p.location_id, 'void_payment:' || p_id::text, p.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p.supplier_id for update;       -- one posting / payment / void at a time per supplier
  select * into p from public.supplier_payments where id = p_id for update;
  if p.voided then raise exception 'already void'; end if;
  if p.bill_id is not null then raise exception 'void_the_bill'; end if;     -- a payment made with a bill goes with the bill
  perform public.lock_check((p.paid_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_payments set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(p.location_id, 'supplier_payment_void', 'yellow', 'সাপ্লায়ার পেমেন্ট বাতিল: ' || left(btrim(p_note), 100), 'A supplier payment was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', p.amount);
end $$;

-- who we owe, since when. p_loc null = whole company (management / owner), else only the open amount of that location's bills.
create or replace function public.supplier_dues(p_loc int default null)
returns table (supplier_id uuid, name text, mobile text, type_code text, credit_days int, balance numeric, oldest date, overdue numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    select s.id, s.name, s.mobile, s.type_code, s.credit_days, sum(o.open_amt), min(o.bill_date),
           coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < (now() at time zone 'Asia/Dhaka')::date), 0)
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
    where o.open_amt > 0 and (p_loc is null or o.location_id = p_loc)
    group by s.id, s.name, s.mobile, s.type_code, s.credit_days
    order by 6 desc;
end $$;

-- open bills of one supplier (after the oldest-first allocation)
create or replace function public.supplier_open_bills(p_supplier uuid, p_loc int default null)
returns table (bill_id uuid, bill_no text, bill_date date, location_id int, bill_due numeric, open_amt numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query select o.bill_id, o.bill_no, o.bill_date, o.location_id, o.rem, o.open_amt from public._sup_open(p_supplier) o
    where o.open_amt > 0 and (p_loc is null or o.location_id = p_loc) order by o.bill_date nulls first, o.bill_id;
end $$;

-- the supplier's running account (debit = bill, credit = payment / return)
create or replace function public.supplier_ledger(p_supplier uuid, p_loc int default null)
returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint, bill_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with e as (
      select '-infinity'::timestamptz at, 'opening'::text kind, null::text ref, null::int location_id, greatest(s.opening_balance, 0) debit, greatest(-s.opening_balance, 0) credit, null::text note, null::bigint pid, null::uuid bill_id, 0 srt
        from public.suppliers s where s.id = p_supplier and p_loc is null and coalesce(s.opening_balance, 0) <> 0
      union all
      select (b.bill_date::timestamp at time zone 'Asia/Dhaka'), case b.kind when 'bill' then 'bill' else 'return' end, coalesce(b.bill_no, '-'), b.location_id,
             case when b.kind = 'bill' then b.total else 0 end, case when b.kind = 'return' then b.total else 0 end, b.note, null::bigint, b.id, 1
        from public.purchase_bills b where b.supplier_id = p_supplier and b.status = 'posted' and (p_loc is null or b.location_id = p_loc)
      union all
      select p.paid_at, case when p.bill_id is null then 'payment' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id, p.bill_id, 2
        from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided and (p_loc is null or p.location_id = p_loc))
    select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, e.srt, e.pid, e.bill_id), e.note, e.pid, e.bill_id
    from e order by e.at, e.srt, e.pid, e.bill_id;
end $$;

-- the payables on one screen (p_loc null = whole company)
create or replace function public.payables_summary(p_loc int default null)
returns table (total_payable numeric, suppliers_owed int, overdue numeric, overdue_suppliers int, oldest date, credit_total numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with d as (select * from public.supplier_dues(p_loc)),
    c as (select coalesce(sum(-b), 0) credit from (select public._sup_balance(s.id) b from public.suppliers s) z where p_loc is null and b < 0)
    select coalesce((select sum(d.balance) from d), 0), (select count(*)::int from d), coalesce((select sum(d.overdue) from d), 0),
           (select count(*)::int from d where d.overdue > 0), (select min(d.oldest) from d), (select c.credit from c);
end $$;

-- lists for the screens
create or replace function public.purchase_list(p_loc int default null, p_from date default null, p_to date default null, p_supplier uuid default null, p_status text default null, p_limit int default 100)
returns table (id uuid, kind text, supplier_id uuid, supplier_name text, bill_no text, bill_date date, location_id int, status text, total numeric, discount numeric, paid numeric, due numeric, photo text, created_staff text, n_lines bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare locs int[];
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(x.id), '{}') into locs from public.locations x where public.can_loc(x.id);        -- once, not per row
  return query
    select b.id, b.kind, b.supplier_id, s.name, b.bill_no, b.bill_date, b.location_id, b.status, b.total, b.discount, b.paid, b.due, b.photo, b.created_staff,
           (select count(*) from public.purchase_lines l where l.bill_id = b.id)
    from public.purchase_bills b join public.suppliers s on s.id = b.supplier_id
    where (p_loc is null or b.location_id = p_loc) and b.location_id = any (locs)
      and (p_from is null or b.bill_date >= p_from) and (p_to is null or b.bill_date <= p_to)
      and (p_supplier is null or b.supplier_id = p_supplier) and (p_status is null or b.status = p_status)
    order by b.bill_date desc, b.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

create or replace function public.purchase_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.purchase_bills;
begin
  select * into b from public.purchase_bills where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public._pur_ok(b.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(b) || jsonb_build_object('supplier_name', (select name from public.suppliers where id = b.supplier_id),
    'lines', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no) from public.purchase_lines l where l.bill_id = b.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'mode', p.mode, 'wallet', p.wallet, 'ref', p.ref, 'amount', p.amount, 'paid_at', p.paid_at, 'voided', p.voided) order by p.id) from public.supplier_payments p where p.bill_id = b.id), '[]'::jsonb));
end $$;

-- ---------- (i) security: RLS everywhere, no direct writes, cost columns not granted ----------
alter table public.stock_batches enable row level security;
alter table public.stock_ledger enable row level security;
alter table public.stock_balance enable row level security;
alter table public.stock_wastage enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.purchase_bills enable row level security;
alter table public.purchase_lines enable row level security;
alter table public.supplier_payments enable row level security;

drop policy if exists stock_batches_read on public.stock_batches;
create policy stock_batches_read on public.stock_batches for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_ledger_read on public.stock_ledger;
create policy stock_ledger_read on public.stock_ledger for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_balance_read on public.stock_balance;
create policy stock_balance_read on public.stock_balance for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_wastage_read on public.stock_wastage;
create policy stock_wastage_read on public.stock_wastage for select to authenticated using (public.can_loc(location_id));
drop policy if exists stock_transfers_read on public.stock_transfers;
create policy stock_transfers_read on public.stock_transfers for select to authenticated using (public.can_loc(from_location_id) or public.can_loc(to_location_id));
drop policy if exists purchase_bills_read on public.purchase_bills;
create policy purchase_bills_read on public.purchase_bills for select to authenticated using (public._pur_ok(location_id));
drop policy if exists purchase_lines_read on public.purchase_lines;
create policy purchase_lines_read on public.purchase_lines for select to authenticated
  using (exists (select 1 from public.purchase_bills b where b.id = bill_id and public._pur_ok(b.location_id)));
drop policy if exists supplier_payments_read on public.supplier_payments;
create policy supplier_payments_read on public.supplier_payments for select to authenticated using (public._pur_ok(location_id));

revoke all on public.stock_batches, public.stock_ledger, public.stock_balance, public.stock_wastage, public.stock_transfers,
  public.purchase_bills, public.purchase_lines, public.supplier_payments from public, anon, authenticated;
revoke all on sequence public.stock_batches_id_seq, public.stock_ledger_id_seq, public.purchase_lines_id_seq, public.supplier_payments_id_seq from public, anon, authenticated;
grant select on public.stock_batches, public.stock_wastage, public.stock_transfers, public.purchase_bills, public.purchase_lines, public.supplier_payments to authenticated;
-- the cost columns (unit_cost, avg_cost) are left out of the column grants on purpose
grant select (id, item_id, location_id, qty_delta, reason, ref_type, ref_id, batch_id, reverses_id, made_at, note, created_by, created_at) on public.stock_ledger to authenticated;
grant select (item_id, location_id, qty, updated_at) on public.stock_balance to authenticated;
-- purchase_lines.unit_cost / amount and the bill totals ARE costs; the policies above already limit them to holders of the purchase / cost grants

-- functions: closed to everyone first, then opened to signed-in users only (anon and public get nothing). Internal helpers stay closed.
revoke all on function public._all_locs(), public._may(text, int, text, numeric), public._cost_ok(int), public._pur_ok(int), public._item_base(uuid),
  public._base_qty(uuid, numeric, text), public._unit_factor_base(uuid, text), public._avg_next(numeric, numeric, numeric, numeric, text),
  public._stock_exc(int, text, text, text, text, uuid, date, text, numeric), public._ledger_immutable(), public._ledger_to_balance(),
  public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid),
  public._sale_stock_out(), public._sale_stock_void(), public._stock_guard(uuid, int, text, date),
  public._sup_open(uuid), public._sup_balance(uuid), public._use_em(text, int, text, numeric), public._client_lock(uuid),
  public._return_check(uuid, uuid, jsonb, boolean),
  public.stock_opening(uuid, int, numeric, numeric, text, text, uuid), public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint),
  public.stock_expire_batch(bigint, text, text, text), public.stock_count_adjust(uuid, int, numeric, text, text, uuid),
  public.stock_issue(uuid, int, numeric, text, text, uuid), public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric),
  public.stock_transfer(int, int, uuid, numeric, text, text, uuid), public.stock_receive_transfer(uuid, numeric, text), public.stock_cancel_transfer(uuid, text),
  public.stock_levels(int, jsonb), public.stock_avg_cost(uuid, int), public.stock_ledger_rows(int, uuid, date, date, int), public.stock_in_transit(int),
  public.expiry_list(int, numeric), public.stock_valuation(int), public.stock_reconcile(boolean),
  public.save_purchase(uuid, uuid, uuid, int, text, date, jsonb, numeric, text, text, text, uuid, text), public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text),
  public.pay_supplier(uuid, int, jsonb, uuid, text), public.void_supplier_payment(bigint, text),
  public.supplier_dues(int), public.supplier_open_bills(uuid, int), public.supplier_ledger(uuid, int), public.payables_summary(int),
  public.purchase_list(int, date, date, uuid, text, int), public.purchase_get(uuid) from public, anon, authenticated;

grant execute on function public._all_locs(), public._cost_ok(int), public._pur_ok(int),                       -- used inside the read policies
  public.stock_opening(uuid, int, numeric, numeric, text, text, uuid), public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint),
  public.stock_expire_batch(bigint, text, text, text), public.stock_count_adjust(uuid, int, numeric, text, text, uuid),
  public.stock_issue(uuid, int, numeric, text, text, uuid), public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric),
  public.stock_transfer(int, int, uuid, numeric, text, text, uuid), public.stock_receive_transfer(uuid, numeric, text), public.stock_cancel_transfer(uuid, text),
  public.stock_levels(int, jsonb), public.stock_avg_cost(uuid, int), public.stock_ledger_rows(int, uuid, date, date, int), public.stock_in_transit(int),
  public.expiry_list(int, numeric), public.stock_valuation(int), public.stock_reconcile(boolean),
  public.save_purchase(uuid, uuid, uuid, int, text, date, jsonb, numeric, text, text, text, uuid, text), public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text),
  public.pay_supplier(uuid, int, jsonb, uuid, text), public.void_supplier_payment(bigint, text),
  public.supplier_dues(int), public.supplier_open_bills(uuid, int), public.supplier_ledger(uuid, int), public.payables_summary(int),
  public.purchase_list(int, date, date, uuid, text, int), public.purchase_get(uuid) to authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------- phase11.sql
-- BOS tool · Phase 11 (W1 hardening): audit_log append-only, immutable codes, no hard deletes, server-side PIN lockout + failed-login log.
-- Additive and re-runnable. Run AFTER phase8, phase9, phase10. Paste whole in the Supabase SQL editor.
-- No client behaviour changes: login_precheck(text)->jsonb, login_failed(text)->void, login_success()->void, unlock_staff(text)->void keep their signatures.

-- ---------- (a) audit_log is append-only (rows can never be changed, deleted or truncated, by anyone, not even postgres) ----------
create or replace function public.audit_log_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'audit_log is append-only'; end $$;

drop trigger if exists audit_log_no_change on public.audit_log;
create trigger audit_log_no_change before update or delete on public.audit_log for each row execute function public.audit_log_append_only();
drop trigger if exists audit_log_no_truncate on public.audit_log;
create trigger audit_log_no_truncate before truncate on public.audit_log for each statement execute function public.audit_log_append_only();
-- ENABLE ALWAYS: still fires when session_replication_role = replica (so a bulk-restore tool cannot bypass it either)
alter table public.audit_log enable always trigger audit_log_no_change;
alter table public.audit_log enable always trigger audit_log_no_truncate;
revoke update, delete, truncate on public.audit_log from anon, authenticated;

-- ---------- (b) codes are immutable (a code is never changed or reused for something else; same-value updates and first assignment of an empty code are allowed) ----------
create or replace function public.code_immutable() returns trigger
language plpgsql set search_path = public as $$
declare c text; o text; n text;
begin
  foreach c in array tg_argv loop
    o := to_jsonb(old) ->> c; n := to_jsonb(new) ->> c;
    if o is not null and o is distinct from n then raise exception 'code is immutable'; end if;
  end loop;
  return new;
end $$;

drop trigger if exists locations_code_immutable on public.locations;
create trigger locations_code_immutable before update on public.locations for each row execute function public.code_immutable('code');
drop trigger if exists forms_code_immutable on public.forms;
create trigger forms_code_immutable before update on public.forms for each row execute function public.code_immutable('code');
drop trigger if exists option_lists_code_immutable on public.option_lists;
create trigger option_lists_code_immutable before update on public.option_lists for each row execute function public.code_immutable('list_code', 'value_code');
drop trigger if exists items_code_immutable on public.items;
create trigger items_code_immutable before update on public.items for each row execute function public.code_immutable('code');
drop trigger if exists roles_code_immutable on public.roles;
create trigger roles_code_immutable before update on public.roles for each row execute function public.code_immutable('code');

-- ---------- (c) nothing is hard-deleted ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- exceptions: only an OPEN flag may be dropped (submit_entry / decide_entry re-evaluate open flags); a decided/closed exception is never deleted
create or replace function public.no_hard_delete_exceptions() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.status = 'open' then return old; end if;
  raise exception 'nothing is deleted – retire instead';
end $$;

do $$
declare t text;
begin
  foreach t in array array['option_lists','locations','forms','items','profiles','entries','sales','customers','suppliers'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
drop trigger if exists exceptions_no_delete on public.exceptions;
create trigger exceptions_no_delete before delete on public.exceptions for each row execute function public.no_hard_delete_exceptions();

-- the client can no longer delete from these (the web UI retires them with active=false). Personal convenience tables
-- (report_views, user_favourites, role_favourites) and the permission matrices (role_form_perms, user_roles, user_locations, rule_grants,
-- user_grants; all have audit triggers) keep DELETE because the permission screens switch a tick off by deleting its row.
revoke delete on public.option_lists, public.unit_conversions, public.shelf_life_rules, public.invoice_templates,
  public.print_profiles, public.report_brand_map from anon, authenticated;

-- ---------- unit_conversions: retire, never delete (readers such as _unit_hop already filter active) ----------
create or replace function public.set_unit_conversion(p_item uuid, p_from text, p_to text, p_factor numeric, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_factor is null then
    update public.unit_conversions set active = false, updated_at = now(), updated_by = auth.uid()
      where coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_item, '00000000-0000-0000-0000-000000000000'::uuid) and from_unit = p_from and to_unit = p_to;
    return;
  end if;
  if not (p_factor > 0 and p_factor < 1e12) then raise exception 'bad_factor'; end if;
  insert into public.unit_conversions (item_id, from_unit, to_unit, factor, note, updated_by) values (p_item, p_from, p_to, p_factor, left(p_note, 200), auth.uid())
    on conflict (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit)
    do update set factor = excluded.factor, note = excluded.note, active = true, updated_at = now(), updated_by = auth.uid();
end $$;

-- ---------- (d) server-side PIN lockout + failed-login log ----------
insert into public.settings (key, value, label_bn, label_mix, label_en) values
 ('lock_minutes', '10', 'ভুল PIN-এ লক কত মিনিট (এবং গণনার সময়সীমা)', 'ভুল PIN-এ Lock কত মিনিট (ও গণনার সময়)', 'Lock minutes after too many wrong PINs (also the counting window)'),
 ('lockout_auto_release', 'true', 'সময় শেষে লক নিজে খুলবে (false = শুধু মালিক খুলবে)', 'সময় শেষে Lock নিজে খুলবে (false = শুধু owner)', 'Lock releases by itself after the time (false = only the owner unlocks)')
on conflict (key) do nothing;

create table if not exists public.login_attempts (
  id bigserial primary key,
  staff_id text not null,
  at timestamptz not null default now(),
  ok boolean not null,
  ip_hint text
);
create index if not exists login_attempts_staff_at on public.login_attempts (staff_id, at desc);
alter table public.login_attempts enable row level security;
drop policy if exists login_attempts_owner_read on public.login_attempts;
create policy login_attempts_owner_read on public.login_attempts for select to authenticated using (public.is_owner());
revoke all on public.login_attempts from anon, authenticated;
grant select on public.login_attempts to authenticated;
revoke all on sequence public.login_attempts_id_seq from anon, authenticated;

-- global / per-bucket spam counters (one row per bucket per minute); nobody but the security-definer functions touches it
create table if not exists public.login_throttle (
  bucket text primary key,
  window_start timestamptz not null default now(),
  n int not null default 0
);
alter table public.login_throttle enable row level security;
revoke all on public.login_throttle from anon, authenticated;

alter table public.login_failures add column if not exists locked_until timestamptz;
alter table public.login_failures add column if not exists window_start timestamptz not null default now();

-- true if this call may be written to login_attempts (max p_limit per bucket per minute; the counter row is the throttle)
create or replace function public._login_throttle(p_bucket text, p_limit int) returns boolean
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into public.login_throttle (bucket, window_start, n) values (p_bucket, now(), 1)
  on conflict (bucket) do update set
    window_start = case when public.login_throttle.window_start < now() - interval '1 minute' then now() else public.login_throttle.window_start end,
    n = case when public.login_throttle.window_start < now() - interval '1 minute' then 1 else public.login_throttle.n + 1 end
  returning n into k;
  return k <= p_limit;
end $$;

create or replace function public._login_setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then
                            case when (value #>> '{}')::numeric between 1 and 100000 then (value #>> '{}')::numeric end end
                   from public.settings where key = p_key), p_default);
$$;

create or replace function public._login_auto_release() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value = 'true'::jsonb from public.settings where key = 'lockout_auto_release' and value is not null), true);
$$;

-- auto-release applies when the setting is on, and ALWAYS for an owner account (an owner can never be locked out for good by someone typing wrong PINs)
create or replace function public._login_auto_release_for(p_staff text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._login_auto_release() or exists (
    select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id where p.staff_id = lower(btrim(coalesce(p_staff, ''))) and ur.role_code = 'owner');
$$;

create or replace function public.login_precheck(p_staff text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f public.login_failures; sec int := 0; lk boolean := false; s text := lower(btrim(coalesce(p_staff, '')));
begin
  select * into f from public.login_failures where staff_id = s;
  if found and f.locked then
    if f.locked_until is null or not public._login_auto_release_for(s) then lk := true; sec := null;      -- locked until the owner unlocks
    elsif f.locked_until > now() then lk := true; sec := ceil(extract(epoch from (f.locked_until - now())))::int;
    end if;
  end if;
  -- same shape for known and unknown ids; no per-id counters are returned (they would reveal which ids exist)
  return jsonb_build_object('locked', lk, 'seconds_left', sec);
end $$;

create or replace function public.login_failed(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare s text := left(lower(btrim(coalesce(p_staff, ''))), 64); mx int := public._login_setting_num('max_fails', 5)::int;
        lm int := public._login_setting_num('lock_minutes', 10)::int; known boolean; f public.login_failures; nf int;
begin
  if s = '' then return; end if;
  select exists (select 1 from public.profiles where staff_id = s) into known;
  -- spam guard: unknown ids share ONE global bucket; known ids get 50 log rows per minute each. Unknown/known look the same to the caller.
  if not public._login_throttle(case when known then 'sid:' || s else 'unknown' end, case when known then 20 else 60 end) then return; end if;
  insert into public.login_attempts (staff_id, ok, ip_hint) values (s, false, null);
  if not known then return; end if;
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
end $$;

create or replace function public.login_success() returns void
language plpgsql security definer set search_path = public as $$
declare s text := (select staff_id from public.profiles where id = auth.uid());
begin
  if s is null then return; end if;
  delete from public.login_failures where staff_id = s;
  if public._login_throttle('sid:' || s, 50) then insert into public.login_attempts (staff_id, ok) values (s, true); end if;
end $$;

create or replace function public.unlock_staff(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare s text := lower(btrim(coalesce(p_staff, '')));
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  delete from public.login_failures where staff_id = s;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'unlock', 'login_failures', s, jsonb_build_object('staff_id', s));
end $$;

revoke execute on function public.login_precheck(text), public.login_failed(text), public.login_success(), public.unlock_staff(text),
  public._login_throttle(text, int), public._login_setting_num(text, numeric), public._login_auto_release(), public.audit_log_append_only(),
  public.code_immutable(), public.no_hard_delete(), public.no_hard_delete_exceptions() from public;
revoke execute on function public._login_throttle(text, int), public._login_setting_num(text, numeric), public._login_auto_release(),
  public.audit_log_append_only(), public.code_immutable(), public.no_hard_delete(), public.no_hard_delete_exceptions() from anon, authenticated;
grant execute on function public.login_precheck(text), public.login_failed(text) to anon, authenticated;
grant execute on function public.login_success(), public.unlock_staff(text) to authenticated;
revoke execute on function public.login_success(), public.unlock_staff(text) from anon;

-- ---------- OPTIONAL Supabase Auth hook (NOT enabled automatically) ----------
-- The lockout above guards the app's login screen only; the Auth endpoint itself can still be called directly. To make the lock real, the owner can enable
-- this function in Supabase Dashboard > Authentication > Hooks > "Password verification attempt" (Postgres function public.hook_password_verification_attempt).
-- It rejects a sign-in while the account is locked and records a failed attempt on a wrong password. Until enabled it has no effect.
create or replace function public.hook_password_verification_attempt(event jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s text; locked boolean;
begin
  select staff_id into s from public.profiles where id = nullif(event ->> 'user_id', '')::uuid;
  if s is not null then
    locked := (public.login_precheck(s) ->> 'locked')::boolean;
    if locked then return jsonb_build_object('decision', 'reject', 'message', 'Account locked, try later or ask the owner'); end if;
    if not coalesce((event ->> 'valid')::boolean, true) then perform public.login_failed(s); end if;
  end if;
  return jsonb_build_object('decision', 'continue');
end $$;
revoke execute on function public.hook_password_verification_attempt(jsonb) from public, anon, authenticated;
revoke execute on function public._login_auto_release_for(text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.hook_password_verification_attempt(jsonb) to supabase_auth_admin;
    grant select on public.profiles, public.login_failures to supabase_auth_admin;
  end if;
end $$;

-- ============================================================================
-- End of FRESH part 1 of 21.
