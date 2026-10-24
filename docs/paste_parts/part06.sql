-- ============================================================================
-- FRESH part 6 of 21. Paste the WHOLE of this file into the Supabase SQL editor, press Run, wait for "Success", then paste the next part.
-- Phases in this part, in this order: phase73 phase74 phase75 phase76 phase77 phase78 phase79 phase506
-- Never paste: any *_test.sql, the phase84 / 84b / 84c TEST-PROJECT files, ALL_NEW2..ALL_NEW11*. Commit: see docs/PASTE_ORDER.md.
-- ============================================================================

-- ---------------------------------------------------------------- phase73.sql
-- ============================================================
-- Phase 73 (bos73) - STEP C-0: recipe master. Artisan register, recipe version history + approval, recipe steps, artisan-wise recipe book.
--   Needs phase8 ... phase71 (recipes/recipe_lines from phase19). Additive; paste-twice safe. Old phases are NOT edited.
--   C0.1 artisans        : the register. The NAME is stored ONLY in artisans.name (column not readable by browsers; only artisan_register() for the owner /
--                          artisan_manage). Everywhere else (recipe book, history, audit log, exceptions) only the artisan id (code 'artisan-N') + post (পদ).
--                          Ids are never reused (identity + no delete); a retired artisan stays in the register and on old recipes.
--   C0.2 recipes.artisan_id : one main artisan per recipe version (blank for every existing recipe - nothing is guessed). recipe_unassigned() = "কারিগর নির্ধারিত নয়".
--   C0.3 recipe_versions : append-only history of every change (who, when, previous values, new values). Approval: recipes.approved_at/by; the person who
--                          last changed a version may NOT approve it (rule recipe_self_approve, default OFF); approver = grant recipe_approve (role recipe_approver).
--                          Rule recipe_approval_required: off (default = today's behaviour) | warn (yellow line) | on (no cost / no production before approval).
--   C0.4 recipe_steps    : ordered method steps (name, free text, minutes, people, fuel, flame note, equipment, QC note, responsible post). minutes x people = a
--                          SUGGESTED labour-hours figure (recipe_labour_suggest) - it never enters any cost.
--   C0.5 recipe_book     : artisan-wise recipe book (no cost unless asked AND the caller has the cost right).
--   C0.6 grant recipe_view (owner + role recipe_approver), rule artisan_self_view (default OFF): a linked artisan sees only his own book. Every view is audited.
--   Functions re-created (tag bos73): recipe_save, recipe_copy (history + artisan + steps carried), recipe_cost, production_post (approval gate only).
-- ============================================================

-- ---------- settings, grants, role ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('recipe_approval_required', 'stock', 'choice', '"off"', '["off","warn","on"]', null, null,
  'রেসিপি অনুমোদনের আগে খরচ/উৎপাদন: বন্ধ / হলুদ সতর্কতা / আটকানো', 'Recipe approval এর আগে cost/production: off / warn / on', 'Cost and production before a recipe is approved: off, yellow warning, or refuse',
  'off = today''s behaviour (no approval needed). warn = yellow line for the owner. on = recipe_cost and production_post refuse an unapproved recipe (form 05-3: no costing before approval).', 720),
 ('recipe_self_approve', 'stock', 'switch', 'false', null, null, null,
  'যে রেসিপি বদলেছে সে-ই অনুমোদন করতে পারবে', 'যে recipe বদলেছে সে-ই approve করতে পারবে', 'The person who changed a recipe may also approve it',
  'Off (default) = the last changer can never approve; a second person with the recipe_approve grant is needed.', 721),
 ('artisan_self_view', 'stock', 'switch', 'false', null, null, null,
  'কারিগর শুধু নিজের রেসিপি দেখতে পারবে', 'Artisan শুধু নিজের recipe দেখতে পারবে', 'An artisan sees only his own recipes (recipe book)',
  'Off (default) = only holders of recipe_view see the recipe books. On = a login linked to an artisan in the register also sees that artisan''s own book, nobody else''s.', 722)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('recipe_view', 'master', 70, 'কারিগর-ভিত্তিক রেসিপি বই দেখা', 'Artisan-wise recipe book দেখা', 'View the artisan-wise recipe books', 'window', null),
 ('recipe_approve', 'master', 71, 'রেসিপি অনুমোদন', 'Recipe approve', 'Approve a recipe version', 'window', null),
 ('artisan_manage', 'master', 72, 'কারিগর রেজিস্টারে নাম ও তথ্য লেখা', 'Artisan register এ নাম ও তথ্য লেখা', 'Write names and details in the artisan register', 'window', null)
on conflict (grant_code) do nothing;

insert into public.roles (code, name_bn, name_mix, name_en, sort) values
 ('recipe_approver', 'রেসিপি অনুমোদনকারী', 'Recipe অনুমোদনকারী', 'Recipe approver', 95)
on conflict (code) do nothing;
insert into public.rule_grants (grant_code, role_code) values ('recipe_view', 'recipe_approver'), ('recipe_approve', 'recipe_approver')
on conflict do nothing;

-- ---------- C0.1 artisan register ----------
create table if not exists public.artisans (
  id int generated always as identity primary key,                 -- never reused
  post text not null check (post in ('karigor', 'chef', 'asst_karigor', 'other')),             -- কারিগর / শেফ / সহকারী কারিগর / অন্য
  post_other text,
  name text not null check (length(btrim(name)) between 2 and 80),   -- typed by the owner; lives ONLY here
  work_type text not null check (work_type in ('mishti', 'doi', 'jilapi', 'cake', 'bakery', 'other')),   -- মিষ্টি / দই / জিলাপি / কেক / বেকারি / অন্য
  work_other text,
  location_id int references public.locations(id),
  user_id uuid references public.profiles(id),                     -- optional: the login of this artisan (for artisan_self_view)
  active boolean not null default true,
  retired_at timestamptz, retired_by uuid, retired_reason text,
  note text,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  check (post <> 'other' or length(btrim(coalesce(post_other, ''))) > 0),
  check (work_type <> 'other' or length(btrim(coalesce(work_other, ''))) > 0)
);
create unique index if not exists artisans_user_one on public.artisans (user_id) where user_id is not null;
alter table public.artisans add column if not exists code text generated always as ('artisan-' || id::text) stored;

drop trigger if exists artisans_no_delete on public.artisans;
create trigger artisans_no_delete before delete on public.artisans for each row execute function public.no_hard_delete();

-- audit WITHOUT the name: the audit log must not carry the name either
create or replace function public._artisan_audit() returns trigger language plpgsql security definer set search_path = public as $$
declare o jsonb; n jsonb; k text; oldd jsonb := '{}'; newd jsonb := '{}'; sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  n := to_jsonb(new) - 'name';
  if tg_op = 'INSERT' then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'insert', 'artisans', new.id::text, jsonb_build_object('new', n));
    return new;
  end if;
  o := to_jsonb(old) - 'name';
  for k in select jsonb_object_keys(n) loop
    if n->k is distinct from o->k then oldd := oldd || jsonb_build_object(k, o->k); newd := newd || jsonb_build_object(k, n->k); end if;
  end loop;
  if new.name is distinct from old.name then newd := newd || jsonb_build_object('name_changed', true); end if;
  if newd = '{}'::jsonb then return new; end if;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'update', 'artisans', new.id::text, jsonb_build_object('old', oldd, 'new', newd));
  return new;
end $$;
drop trigger if exists audit_artisans on public.artisans;
create trigger audit_artisans after insert or update on public.artisans for each row execute function public._artisan_audit();

-- ---------- recipe columns ----------
alter table public.recipes add column if not exists artisan_id int references public.artisans(id);
alter table public.recipes add column if not exists approved_by uuid;
alter table public.recipes add column if not exists approved_at timestamptz;
alter table public.recipes add column if not exists approve_note text;
alter table public.recipes add column if not exists changed_by uuid;
alter table public.recipes add column if not exists changed_at timestamptz;
alter table public.recipes add column if not exists form_ref text;           -- the printed 05-3 card number: a REFERENCE only, the detail lives here
create index if not exists recipes_artisan on public.recipes (artisan_id) where artisan_id is not null;

-- ---------- C0.4 steps, C0.3 history ----------
create table if not exists public.recipe_steps (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  step_no int not null check (step_no >= 1),
  step_name text not null check (length(btrim(step_name)) between 1 and 120),
  description text,
  minutes numeric check (minutes is null or (minutes >= 0 and minutes <= 100000)),            -- null = blank = "অসম্পূর্ণ"
  people int check (people is null or (people >= 0 and people <= 1000)),
  fuel text check (fuel is null or fuel in ('gas', 'electric', 'other')),
  fuel_other text,
  flame_note text,
  equipment text,
  qc_note text,
  resp_post text check (resp_post is null or resp_post in ('karigor', 'chef', 'asst_karigor', 'other')),
  resp_other text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check (fuel is distinct from 'other' or length(btrim(coalesce(fuel_other, ''))) > 0)
);
create unique index if not exists recipe_steps_one on public.recipe_steps (recipe_id, step_no) where active;

create table if not exists public.recipe_versions (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  version int not null,
  seq int not null,
  kind text not null check (kind in ('created', 'edited', 'steps_edited', 'artisan_set', 'approved', 'activated', 'retired')),
  changed_by uuid, changed_at timestamptz not null default now(),
  summary text,
  prev jsonb,            -- the values BEFORE this change (kept for ever)
  snap jsonb,            -- the values after it
  client_id uuid unique,
  unique (recipe_id, seq)
);
create or replace function public._rv_immutable() returns trigger language plpgsql as $$ begin raise exception 'append_only'; end $$;
drop trigger if exists recipe_versions_immutable on public.recipe_versions;
create trigger recipe_versions_immutable before update or delete on public.recipe_versions for each row execute function public._rv_immutable();
drop trigger if exists recipe_steps_no_delete on public.recipe_steps;
create trigger recipe_steps_no_delete before delete on public.recipe_steps for each row execute function public.no_hard_delete();
drop trigger if exists audit_recipe_steps on public.recipe_steps;
create trigger audit_recipe_steps after insert or update on public.recipe_steps for each row execute function public.log_change('id');

-- an approved version never changes (yield, lines, steps); a change is a NEW version
create or replace function public._recipe_approved_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare rid uuid; ap timestamptz;
begin
  if tg_table_name = 'recipes' then
    if old.approved_at is not null and (new.item_id is distinct from old.item_id or new.version is distinct from old.version
       or new.yield_qty is distinct from old.yield_qty or new.yield_unit is distinct from old.yield_unit) then raise exception 'recipe_approved'; end if;
    if old.approved_at is not null and (new.approved_at is distinct from old.approved_at or new.approved_by is distinct from old.approved_by) then raise exception 'recipe_approved'; end if;
    return new;
  end if;
  rid := case when tg_op = 'DELETE' then old.recipe_id else new.recipe_id end;
  select approved_at into ap from public.recipes where id = rid;
  if ap is not null then raise exception 'recipe_approved'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists recipes_approved_guard on public.recipes;
create trigger recipes_approved_guard before update on public.recipes for each row execute function public._recipe_approved_guard();
drop trigger if exists recipe_lines_approved_guard on public.recipe_lines;
create trigger recipe_lines_approved_guard before insert or update or delete on public.recipe_lines for each row execute function public._recipe_approved_guard();
drop trigger if exists recipe_steps_approved_guard on public.recipe_steps;
create trigger recipe_steps_approved_guard before insert or update on public.recipe_steps for each row execute function public._recipe_approved_guard();

-- ---------- RLS ----------
alter table public.artisans enable row level security;
alter table public.recipe_steps enable row level security;
alter table public.recipe_versions enable row level security;
drop policy if exists artisans_read on public.artisans;
create policy artisans_read on public.artisans for select to authenticated using (public._recipe_read() or public.has_grant('recipe_view') or public.has_grant('artisan_manage'));
drop policy if exists recipe_steps_read on public.recipe_steps;
create policy recipe_steps_read on public.recipe_steps for select to authenticated using (public._recipe_read());
drop policy if exists recipe_versions_read on public.recipe_versions;
create policy recipe_versions_read on public.recipe_versions for select to authenticated using (public._recipe_read());
revoke all on public.artisans, public.recipe_steps, public.recipe_versions from anon, authenticated;
grant select (id, code, post, post_other, work_type, work_other, location_id, user_id, active, retired_at, retired_reason, note, created_at) on public.artisans to authenticated;      -- NOT name
grant select on public.recipe_steps, public.recipe_versions to authenticated;
revoke all on sequence public.recipe_steps_id_seq, public.recipe_versions_id_seq from anon, authenticated;

-- ---------- helpers ----------
-- the read right for the recipe tables: phase19 definition + the two new grants (an approver must be able to read what he approves)
create or replace function public._recipe_read() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recipe_manage') or public.has_grant('stock_production') or public.has_grant('stock_issue')
    or public.has_grant('recipe_view') or public.has_grant('recipe_approve')      -- bos73
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code in ('recipe_manage', 'stock_production', 'stock_issue') and (g.valid_until is null or g.valid_until > now())));
$$;
create or replace function public._artisan_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('artisan_manage'));
$$;
create or replace function public._artisan_of_user() returns int language sql stable security definer set search_path = public as $$
  select a.id from public.artisans a where a.user_id = auth.uid() and a.active limit 1;
$$;
create or replace function public._recipe_view_ok(p_artisan int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.has_grant('recipe_view') or (public.rule_on('artisan_self_view') and p_artisan is not null
    and exists (select 1 from public.artisans a where a.id = p_artisan and a.user_id = auth.uid())));
$$;
create or replace function public._audit_view(p_table text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), sid, 'view', p_table, p_rec, p_detail);
end $$;

create or replace function public._recipe_snapshot(p_recipe uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('item_id', r.item_id, 'version', r.version, 'yield_qty', r.yield_qty, 'yield_unit', r.yield_unit, 'active', r.active, 'note', r.note,
    'artisan_id', r.artisan_id, 'form_ref', r.form_ref, 'approved_at', r.approved_at,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'qty', l.qty, 'unit', l.unit, 'waste_pct', l.waste_pct, 'note', l.note) order by l.sort, l.id)
                       from public.recipe_lines l where l.recipe_id = r.id and l.active), '[]'::jsonb),
    'steps', coalesce((select jsonb_agg(jsonb_build_object('step_no', s.step_no, 'step_name', s.step_name, 'description', s.description, 'minutes', s.minutes, 'people', s.people,
                       'fuel', s.fuel, 'fuel_other', s.fuel_other, 'flame_note', s.flame_note, 'equipment', s.equipment, 'qc_note', s.qc_note, 'resp_post', s.resp_post, 'resp_other', s.resp_other) order by s.step_no)
                       from public.recipe_steps s where s.recipe_id = r.id and s.active), '[]'::jsonb))
  from public.recipes r where r.id = p_recipe;
$$;

create or replace function public._rv_log(p_recipe uuid, p_kind text, p_prev jsonb, p_summary text, p_client uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.recipes;
begin
  select * into r from public.recipes where id = p_recipe;
  insert into public.recipe_versions (recipe_id, version, seq, kind, changed_by, changed_at, summary, prev, snap, client_id)
    values (p_recipe, r.version, coalesce((select max(seq) from public.recipe_versions where recipe_id = p_recipe), 0) + 1, p_kind, auth.uid(), now(), left(p_summary, 300), p_prev, public._recipe_snapshot(p_recipe), p_client);
end $$;

-- ---------- C0.1 artisan writes / reads ----------
-- create (p_id null) or edit. The name is typed by the owner (or a person the owner gave artisan_manage). Returns id + code only.
create or replace function public.artisan_save(p_id int, p_post text, p_post_other text, p_name text, p_work_type text, p_work_other text, p_location int default null, p_user uuid default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.artisans; rid int;
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_post not in ('karigor', 'chef', 'asst_karigor', 'other') then raise exception 'bad_post'; end if;
  if p_work_type not in ('mishti', 'doi', 'jilapi', 'cake', 'bakery', 'other') then raise exception 'bad_work_type'; end if;
  if p_post = 'other' and length(btrim(coalesce(p_post_other, ''))) = 0 then raise exception 'post_other_needed'; end if;
  if p_work_type = 'other' and length(btrim(coalesce(p_work_other, ''))) = 0 then raise exception 'work_other_needed'; end if;
  if p_name is null or length(btrim(p_name)) < 2 or length(btrim(p_name)) > 80 then raise exception 'name_needed'; end if;
  if p_location is not null and not exists (select 1 from public.locations where id = p_location) then raise exception 'unknown location'; end if;
  if p_user is not null and not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_id is null then
    if p_client is not null then
      select * into a from public.artisans where client_id = p_client;
      if found then
        if a.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
        return jsonb_build_object('dup', true, 'id', a.id, 'code', a.code);
      end if;
    end if;
    insert into public.artisans (post, post_other, name, work_type, work_other, location_id, user_id, note, client_id, created_by)
      values (p_post, case when p_post = 'other' then left(btrim(p_post_other), 60) end, btrim(p_name), p_work_type, case when p_work_type = 'other' then left(btrim(p_work_other), 60) end,
              p_location, p_user, left(p_note, 300), p_client, auth.uid()) returning * into a;
  else
    update public.artisans set post = p_post, post_other = case when p_post = 'other' then left(btrim(p_post_other), 60) end, name = btrim(p_name), work_type = p_work_type,
      work_other = case when p_work_type = 'other' then left(btrim(p_work_other), 60) end, location_id = p_location, user_id = p_user, note = left(p_note, 300)
      where id = p_id returning * into a;
    if not found then raise exception 'artisan_not_found'; end if;
  end if;
  return jsonb_build_object('id', a.id, 'code', a.code);
end $$;

create or replace function public.artisan_set_active(p_id int, p_active boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  if not p_active and length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_required'; end if;
  update public.artisans set active = p_active, retired_at = case when p_active then null else now() end, retired_by = case when p_active then null else auth.uid() end,
    retired_reason = case when p_active then null else left(btrim(p_reason), 200) end where id = p_id;
  if not found then raise exception 'artisan_not_found'; end if;
end $$;

-- the register with names: owner / artisan_manage ONLY (audited as a view)
create or replace function public.artisan_register() returns jsonb language plpgsql security definer set search_path = public as $$
declare out jsonb;
begin
  if not public._artisan_mgr() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'name', a.name, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'user_id', a.user_id, 'active', a.active, 'retired_at', a.retired_at, 'retired_reason', a.retired_reason, 'note', a.note,
    'recipes', (select count(*) from public.recipes r where r.artisan_id = a.id and r.active)) order by a.id), '[]'::jsonb) into out from public.artisans a;
  perform public._audit_view('artisan_register', null, jsonb_build_object('n', jsonb_array_length(out)));
  return out;
end $$;

-- the list for pickers: id + code + post + work type + place. NEVER the name.
create or replace function public.artisan_list(p_include_retired boolean default false) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._recipe_read() or public.has_grant('recipe_view') or public._artisan_mgr()) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'code', a.code, 'post', a.post, 'post_other', a.post_other, 'work_type', a.work_type, 'work_other', a.work_other,
    'location_id', a.location_id, 'active', a.active) order by a.id) from public.artisans a where p_include_retired or a.active), '[]'::jsonb);
end $$;

-- ---------- C0.2 artisan on a recipe version ----------
create or replace function public._recipe_set_artisan(p_recipe uuid, p_artisan int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb;
begin
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if p_artisan is not null and not exists (select 1 from public.artisans where id = p_artisan and active) then raise exception 'artisan_not_found'; end if;
  if r.artisan_id is not distinct from p_artisan then return; end if;
  prev := public._recipe_snapshot(p_recipe);
  update public.recipes set artisan_id = p_artisan where id = p_recipe;
  perform public._rv_log(p_recipe, 'artisan_set', prev, left(p_note, 200));
end $$;
create or replace function public.recipe_set_artisan(p_recipe uuid, p_artisan int, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._recipe_set_artisan(p_recipe, p_artisan, p_note);
end $$;

-- recipes with no artisan: the list "কারিগর নির্ধারিত নয়"
create or replace function public.recipe_unassigned() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._recipe_mgr() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('recipe_id', r.id, 'version', r.version, 'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
    'approved', r.approved_at is not null) order by i.code, r.version) from public.recipes r join public.items i on i.id = r.item_id where r.active and r.artisan_id is null), '[]'::jsonb);
end $$;

-- ---------- C0.4 steps ----------
create or replace function public.recipe_steps_save(p_recipe uuid, p_steps jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; s jsonb; n int := 0; prev jsonb; mins numeric; ppl int; fu text; rp text; dup public.recipe_versions;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into dup from public.recipe_versions where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'recipe_id', dup.recipe_id); end if;
  end if;
  select * into r from public.recipes where id = p_recipe for update;
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
end $$;

-- SUGGESTION only: minutes x people / 60. It is never read by recipe_cost, production_post or any report.
create or replace function public.recipe_labour_suggest(p_recipe uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tot numeric; n int; miss int;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select coalesce(sum(minutes * people) filter (where minutes is not null and people is not null), 0), count(*), count(*) filter (where minutes is null or people is null)
    into tot, n, miss from public.recipe_steps where recipe_id = p_recipe and active;
  return jsonb_build_object('suggested_labour_hours', round(tot / 60, 2), 'steps_total', n, 'steps_incomplete', miss, 'incomplete', miss > 0, 'note', 'suggestion_only');
end $$;

-- ---------- C0.3 approval ----------
create or replace function public.recipe_approve(p_recipe uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; prev jsonb;
begin
  if not public.is_active() or not public.has_grant('recipe_approve') then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe for update;
  if not found then raise exception 'recipe_not_found'; end if;
  if r.approved_at is not null then return jsonb_build_object('dup', true, 'recipe_id', r.id, 'approved_at', r.approved_at); end if;
  if not exists (select 1 from public.recipe_lines where recipe_id = r.id and active) then raise exception 'no_lines'; end if;
  if coalesce(r.changed_by, r.created_by) is not distinct from auth.uid() and not public.rule_on('recipe_self_approve') then raise exception 'self_approve_refused'; end if;
  prev := public._recipe_snapshot(r.id);
  update public.recipes set approved_by = auth.uid(), approved_at = now(), approve_note = left(p_note, 200) where id = r.id;
  perform public._rv_log(r.id, 'approved', prev, left(p_note, 200));
  return jsonb_build_object('recipe_id', r.id, 'approved', true);
end $$;

-- the approval gate for cost / production. off = today's behaviour; warn = continue (the caller adds a yellow line); on = refuse.
create or replace function public._recipe_gate73(p_recipe uuid) returns text language plpgsql stable security definer set search_path = public as $$
declare m text := coalesce(public.rule_txt('recipe_approval_required'), 'off'); ap timestamptz;
begin
  select approved_at into ap from public.recipes where id = p_recipe;
  if ap is not null or m = 'off' then return 'ok'; end if;
  if m = 'on' then raise exception 'recipe_not_approved'; end if;
  return 'warn';
end $$;

-- ---------- re-created: recipe_save (history, changer, approved guard) ----------
create or replace function public.recipe_save(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; r public.recipes; v int; rid uuid; yu text := nullif(btrim(p_yield_unit), ''); prev jsonb; /* bos73 */
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_yield_qty is null or not (p_yield_qty > 0 and p_yield_qty < 1000000000) then raise exception 'bad_qty'; end if;
  if p_id is not null then
    select * into r from public.recipes where id = p_id for update;
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
    select * into it from public.items where id = p_item;
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
end $$;

-- ---------- re-created: recipe_copy (artisan + steps follow a same-product copy; history row) ----------
create or replace function public.recipe_copy(p_from uuid, p_item uuid default null, p_retire_old boolean default false, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.recipes; tgt public.items; v int; rid uuid; dup public.recipes;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into s from public.recipes where id = p_from;
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
end $$;

-- one atomic call for the editor: lines + steps + artisan + form reference
create or replace function public.recipe_save_full(p_id uuid, p_item uuid, p_yield_qty numeric, p_yield_unit text, p_note text, p_lines jsonb, p_steps jsonb default null,
  p_artisan int default null, p_set_artisan boolean default false, p_form_ref text default null, p_client uuid default null, p_retire_old boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb; rid uuid;
begin
  if not public._recipe_mgr() then raise exception 'not allowed'; end if;
  res := public.recipe_save(p_id, p_item, p_yield_qty, p_yield_unit, p_note, p_lines, p_client, p_retire_old);
  if (res->>'dup')::boolean is true then return res; end if;
  rid := (res->>'id')::uuid;
  if p_steps is not null then perform public.recipe_steps_save(rid, p_steps, null); end if;
  if p_set_artisan then perform public._recipe_set_artisan(rid, p_artisan, null); end if;
  if p_form_ref is not null then update public.recipes set form_ref = left(nullif(btrim(p_form_ref), ''), 40) where id = rid; end if;
  return res;
end $$;

-- ---------- re-created: recipe_cost (approval gate; same maths as phase19) ----------
create or replace function public.recipe_cost(p_recipe uuid, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; ls jsonb := '[]'::jsonb; total numeric := 0; complete boolean := true; l record; need numeric; av numeric; yb numeric; gate text;
begin
  if p_loc is not null then
    if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;      -- same rule as the stock cost columns
  elsif not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  gate := public._recipe_gate73(p_recipe);      -- bos73: 'on' = refuse an unapproved recipe
  for l in select x.*, i.code, i.name_bn, i.name_en from public.recipe_lines x join public.items i on i.id = x.ingredient_item_id where x.recipe_id = p_recipe and x.active order by x.sort, x.id loop
    need := round(public._base_qty(l.ingredient_item_id, l.qty, l.unit) * (1 + coalesce(l.waste_pct, 0) / 100), 4);
    if p_loc is not null then
      select avg_cost into av from public.stock_balance where item_id = l.ingredient_item_id and location_id = p_loc;
    else
      select sum(qty * avg_cost) / nullif(sum(qty), 0) into av from public.stock_balance
        where item_id = l.ingredient_item_id and qty > 0 and avg_cost is not null and (public._all_locs() or public.can_loc(location_id)) and public._cost_ok(location_id);
    end if;
    if av is null then complete := false; else total := total + need * av; end if;
    ls := ls || jsonb_build_object('ingredient_item_id', l.ingredient_item_id, 'code', l.code, 'need_base', need, 'unit_cost', av, 'line_cost', case when av is null then null else round(need * av, 4) end,
      'waste_missing', l.waste_pct is null);
  end loop;
  yb := public._base_qty(r.item_id, r.yield_qty, r.yield_unit);
  return jsonb_build_object('recipe_id', p_recipe, 'lines', ls, 'complete', complete, 'batch_cost', case when complete then round(total, 4) end,
    'unit_cost', case when complete and yb > 0 then round(total / yb, 6) end, 'yield_base', yb, 'approved', r.approved_at is not null, 'approval_warn', gate = 'warn');
end $$;

-- ---------- re-created: production_post (ONLY change: the approval gate, marked bos73) ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
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
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, yb, wm, left(p_note, 200), auth.uid());
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
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
  if gate = 'warn' then      -- bos73
    perform public._stock_exc(p_loc, 'recipe_not_approved', 'yellow', it.name_bn || ': রেসিপি (ভার্সন ' || r.version::text || ') অনুমোদিত নয়',
      coalesce(it.name_en, it.name_bn) || ': recipe version ' || r.version::text || ' is not approved', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  return jsonb_build_object('run_id', rid, 'ledger_id', lid, 'batch_id', bid, 'qty', yb, 'expires_at', exp, 'consumed', used, 'waste_missing', wm) || case when public._cost_ok(p_loc) then jsonb_build_object('cost_complete', cost_ok) else '{}'::jsonb end;
end $$;

-- ---------- C0.5 / C0.6 the artisan-wise recipe book ----------
-- p_artisan null = the caller's own artisan record (artisan_self_view). Cost columns only when asked AND the caller has the cost right. Every call is audited.
create or replace function public.recipe_book(p_artisan int default null, p_with_cost boolean default false, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.artisans; aid int := coalesce(p_artisan, public._artisan_of_user()); rs jsonb := '[]'::jsonb; r record; ln jsonb; st jsonb; lab jsonb; cst jsonb; cost_on boolean;
begin
  if aid is null or not public._recipe_view_ok(aid) then raise exception 'not allowed'; end if;
  select * into a from public.artisans where id = aid;
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
end $$;

-- ---------- privileges ----------
revoke all on function public._artisan_audit(), public._rv_immutable(), public._recipe_approved_guard(), public._artisan_mgr(), public._artisan_of_user(), public._audit_view(text, text, jsonb),
  public._recipe_snapshot(uuid), public._rv_log(uuid, text, jsonb, text, uuid), public._recipe_set_artisan(uuid, int, text), public._recipe_gate73(uuid) from public, anon, authenticated;
revoke all on function public._recipe_view_ok(int) from public, anon;
grant execute on function public._recipe_view_ok(int) to authenticated;
revoke all on function public.artisan_save(int, text, text, text, text, text, int, uuid, text, uuid), public.artisan_set_active(int, boolean, text), public.artisan_register(), public.artisan_list(boolean),
  public.recipe_set_artisan(uuid, int, text), public.recipe_unassigned(), public.recipe_steps_save(uuid, jsonb, uuid), public.recipe_labour_suggest(uuid), public.recipe_approve(uuid, text),
  public.recipe_save_full(uuid, uuid, numeric, text, text, jsonb, jsonb, int, boolean, text, uuid, boolean), public.recipe_book(int, boolean, int) from public, anon;
grant execute on function public.artisan_save(int, text, text, text, text, text, int, uuid, text, uuid), public.artisan_set_active(int, boolean, text), public.artisan_register(), public.artisan_list(boolean),
  public.recipe_set_artisan(uuid, int, text), public.recipe_unassigned(), public.recipe_steps_save(uuid, jsonb, uuid), public.recipe_labour_suggest(uuid), public.recipe_approve(uuid, text),
  public.recipe_save_full(uuid, uuid, numeric, text, text, jsonb, jsonb, int, boolean, text, uuid, boolean), public.recipe_book(int, boolean, int) to authenticated;

-- ---------------------------------------------------------------- phase74.sql
-- ============================================================
-- Phase 74 (bos74) - STEP C: costing and overhead (conversion cost into product cost).
--   Needs phase8 ... phase71 + phase73. Additive; paste-twice safe. Old phases are NOT edited.
--   Cost structure the code follows:
--     layer 1 raw material      = weighted-average cost (existing) + "আজকের কেনা দাম" (latest purchase_in cost) shown in a SEPARATE row, never booked (C5)
--     layer 2 conversion cost   = labour, gas/fuel, electricity, factory rent, licence & fees, machine repair, depreciation, other (+ owner-added types). GOES INTO product cost (C1-C3)
--     layer 3 showroom + admin  = NOT in product cost; it goes to the branch P&L (nothing here touches it)
--   Product cost = material cost + conversion rate x quantity.
--   Two ways to get the conversion rate, chosen PER LOCATION (location_cost_cfg.mode): off (default = today's behaviour) | recipe | pool.
--     recipe : rates typed on the recipe (recipe_cost_components: per batch / per base unit / per labour-hour). A blank amount = "রূপান্তর খরচ অসম্পূর্ণ".
--     pool   : monthly pool of actual factory cost per component type (factory_cost_pools) / NORMAL monthly output of the location (not actual output).
--              Smoothing (settings on the type, cost_type_smoothing): none = that month, yearly12 = a yearly amount / 12 per month, avg_n = the N months ending at the run month (repair 12, gas and electricity 3)
--              divided by the months since the first entry (capped at N); months with no entry are counted as gaps, never filled by a guess.
--   Changes marked bos74: production_post (new 7-argument core with p_actual_yield; the 6-argument signature stays as a thin wrapper; conversion cost; run snapshot columns), recipe_cost (same _recipe_need as the run; raw / packaging /
--   conversion rows; today-price row), stock_production_in (reason + yellow flag for a typed cost), _acct_docs (production journal: Dr 1310 / Cr 1320 + 1330 + overhead_absorbed).
--   !! A parallel change (phase72, Part 1 step B) also re-creates production_post / recipe_cost / _p27_pl: the lead MUST re-merge those functions (see docs/briefs_p2p3/step_C_REPORT.md).
-- ============================================================

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('cost_gap_warn_pct', 'stock', 'number', null, null, 0, 1000,
  '"আজকের কেনা দাম" ও গড় দামের ফারাক % — এর বেশি হলে হলুদ সতর্কতা', '"আজকের কেনা দাম" vs গড় দামের gap % — এর বেশি হলে yellow', 'Yellow warning when today''s purchase price differs from the average cost by more than this %',
  'Blank = no warning. It is a display warning only; it never changes a booked cost.', 730),
 ('yield_variance_warn_pct', 'stock', 'number', null, null, 0, 1000,
  'আসল উৎপাদন রেসিপির ফলন থেকে এর বেশি % আলাদা হলে হলুদ সতর্কতা', 'Actual yield recipe yield থেকে এর বেশি % আলাদা হলে yellow', 'Yellow warning when the actual yield differs from the recipe yield by more than this %',
  'Blank = no warning.', 731),
 ('production_manual_needs_reason', 'stock', 'switch', 'false', null, null, null,
  'সরাসরি "উৎপাদিত মাল তোলা"-য় কারণ (নোট) বাধ্যতামূলক', 'Direct "Production in"-এ reason (note) বাধ্যতামূলক', 'The direct production-in needs a reason note',
  'Off (default) = as today. On = a note of at least 3 characters is required while production_requires_recipe is off. Recommended: switch production_requires_recipe ON instead.', 732)
on conflict (key) do nothing;

-- ---------- types of conversion cost (owner may add types) ----------
create table if not exists public.cost_component_types (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 80),
  label_en text,
  builtin boolean not null default false,
  smooth text not null default 'none' check (smooth in ('none', 'yearly12', 'avg_n')),     -- how the pool figure of a month is made
  avg_months int check (avg_months is null or avg_months between 1 and 36),                  -- the window for avg_n (a setting)
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
insert into public.cost_component_types (code, label_bn, label_en, builtin, smooth, avg_months) values
 ('labour', 'শ্রম / মজুরি', 'Labour', true, 'none', null),
 ('gas', 'গ্যাস / জ্বালানি', 'Gas / fuel', true, 'avg_n', 3),
 ('electricity', 'বিদ্যুৎ', 'Electricity', true, 'avg_n', 3),
 ('factory_rent', 'কারখানার ভাড়া', 'Factory rent', true, 'none', null),
 ('licence_fee', 'লাইসেন্স ও ফি', 'Licence and fees', true, 'yearly12', null),
 ('machine_repair', 'যন্ত্র মেরামত', 'Machine repair', true, 'avg_n', 12),
 ('depreciation', 'অবচয়', 'Depreciation', true, 'none', null),
 ('other', '☐ অন্য: ______', 'Other: ______', true, 'none', null)
on conflict (code) do nothing;
create sequence if not exists public.cost_type_seq;

-- ---------- C1: conversion cost rates on a recipe (amounts may be blank) ----------
create table if not exists public.recipe_cost_components (
  id bigserial primary key,
  recipe_id uuid not null references public.recipes(id),
  component_type text not null references public.cost_component_types(code),
  type_note text,                                                      -- for "other": what it is (typed)
  basis text not null check (basis in ('per_batch', 'per_unit', 'per_labour_hour')),   -- per batch / per base unit (kg) of output / per labour-hour
  amount numeric check (amount is null or (amount >= 0 and amount <= 1000000000)),    -- BLANK = "রূপান্তর খরচ অসম্পূর্ণ"
  hours_per_batch numeric check (hours_per_batch is null or (hours_per_batch >= 0 and hours_per_batch <= 100000)),   -- typed by hand for per_labour_hour (the step suggestion never flows in by itself)
  note text,
  active boolean not null default true,                                -- a change retires the row and inserts a new one: previous values are kept
  set_by uuid, set_at timestamptz not null default now(),
  client_id uuid unique
);
create unique index if not exists rcc_one_active on public.recipe_cost_components (recipe_id, component_type, coalesce(type_note, '')) where active;

-- ---------- C2: monthly pools of ACTUAL factory cost + the per-location choice ----------
create table if not exists public.factory_cost_pools (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  month date not null check (month = date_trunc('month', month)::date),
  component_type text not null references public.cost_component_types(code),
  period_kind text not null default 'month' check (period_kind in ('month', 'year')),   -- a 'year' amount (licence) starts at its month and is spread /12 over 12 months
  actual_amount numeric not null check (actual_amount >= 0 and actual_amount <= 1000000000000),
  one_off boolean not null default false,                              -- a large irregular repair: flagged "একবারের খরচ"
  source text not null default 'manual' check (source in ('manual', 'allocated')),    -- allocated = pushed by a cost source bill (phase75)
  ref text,                                                            -- source bill id for allocated rows
  note text,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists fcp_one_active on public.factory_cost_pools (location_id, month, component_type, period_kind, source, coalesce(ref, '')) where active;
create index if not exists fcp_loc_month on public.factory_cost_pools (location_id, month) where active;

create table if not exists public.location_cost_cfg (
  location_id int primary key references public.locations(id),
  mode text not null default 'off' check (mode in ('off', 'recipe', 'pool')),
  normal_monthly_output numeric check (normal_monthly_output is null or (normal_monthly_output > 0 and normal_monthly_output <= 1000000000)),   -- base units (kg) per month; BLANK until the owner sets it
  updated_by uuid, updated_at timestamptz not null default now()
);

-- ---------- production_runs: the cost snapshot of a run (visible only through production_run_costs; the browser column grant of phase19 does not include them) ----------
alter table public.production_runs add column if not exists material_cost numeric;
alter table public.production_runs add column if not exists conversion_cost numeric;
alter table public.production_runs add column if not exists unit_cost numeric;          -- booked per base unit (material + conversion) / output booked
alter table public.production_runs add column if not exists std_cost numeric;           -- (material + conversion) / the recipe's standard yield
alter table public.production_runs add column if not exists actual_cost numeric;        -- (material + conversion) / the actual output
alter table public.production_runs add column if not exists conversion_mode text;
alter table public.production_runs add column if not exists conversion_complete boolean;
alter table public.production_runs add column if not exists conversion_detail jsonb;
alter table public.production_runs add column if not exists yield_std numeric;
alter table public.production_runs add column if not exists yield_actual numeric;
alter table public.production_runs add column if not exists yield_var_pct numeric;

-- triggers / RLS
drop trigger if exists cost_types_no_delete on public.cost_component_types;
create trigger cost_types_no_delete before delete on public.cost_component_types for each row execute function public.no_hard_delete();
drop trigger if exists rcc_no_delete on public.recipe_cost_components;
create trigger rcc_no_delete before delete on public.recipe_cost_components for each row execute function public.no_hard_delete();
drop trigger if exists fcp_no_delete on public.factory_cost_pools;
create trigger fcp_no_delete before delete on public.factory_cost_pools for each row execute function public.no_hard_delete();
drop trigger if exists lcc_no_delete on public.location_cost_cfg;
create trigger lcc_no_delete before delete on public.location_cost_cfg for each row execute function public.no_hard_delete();
drop trigger if exists audit_cost_types on public.cost_component_types;
create trigger audit_cost_types after insert or update on public.cost_component_types for each row execute function public.log_change('code');
drop trigger if exists audit_rcc on public.recipe_cost_components;
create trigger audit_rcc after insert or update on public.recipe_cost_components for each row execute function public.log_change('id');
drop trigger if exists audit_fcp on public.factory_cost_pools;
create trigger audit_fcp after insert or update on public.factory_cost_pools for each row execute function public.log_change('id');
drop trigger if exists audit_lcc on public.location_cost_cfg;
create trigger audit_lcc after insert or update on public.location_cost_cfg for each row execute function public.log_change('location_id');

alter table public.cost_component_types enable row level security;
alter table public.recipe_cost_components enable row level security;
alter table public.factory_cost_pools enable row level security;
alter table public.location_cost_cfg enable row level security;
drop policy if exists cost_types_read on public.cost_component_types;
create policy cost_types_read on public.cost_component_types for select to authenticated using (public.is_active());
drop policy if exists rcc_read on public.recipe_cost_components;
create policy rcc_read on public.recipe_cost_components for select to authenticated using (public._recipe_cost_ok());
drop policy if exists fcp_read on public.factory_cost_pools;
create policy fcp_read on public.factory_cost_pools for select to authenticated using (public._recipe_cost_ok() and public.can_loc(location_id));
drop policy if exists lcc_read on public.location_cost_cfg;
create policy lcc_read on public.location_cost_cfg for select to authenticated using (public._recipe_cost_ok() and public.can_loc(location_id));
revoke all on public.cost_component_types, public.recipe_cost_components, public.factory_cost_pools, public.location_cost_cfg from anon, authenticated;
grant select on public.cost_component_types, public.recipe_cost_components, public.factory_cost_pools, public.location_cost_cfg to authenticated;
revoke all on sequence public.recipe_cost_components_id_seq, public.factory_cost_pools_id_seq, public.cost_type_seq from anon, authenticated;

-- ---------- helpers ----------
-- the first day of the month of a date in Dhaka
create or replace function public._m1(p_date date) returns date language sql immutable as $$ select date_trunc('month', p_date)::date $$;

-- ACTUAL cost of a type in a month: month rows + year rows / 12 that cover the month. null = nothing entered (never 0 by guess).
create or replace function public._pool_month_actual(p_loc int, p_month date, p_type text) returns numeric
language sql stable security definer set search_path = public as $$
  select case when count(*) = 0 then null else coalesce(sum(case when period_kind = 'month' then actual_amount else actual_amount / 12 end), 0) end
    from public.factory_cost_pools
   where active and location_id = p_loc and component_type = p_type
     and ((period_kind = 'month' and month = p_month) or (period_kind = 'year' and p_month >= month and p_month < (month + interval '12 months')::date));
$$;

-- the figure used for the RATE of a month, after the type's smoothing. avg_n = sum of the N months ending at the run month / the months of that window since the first
-- entry (so a young book is not understated); months with no entry inside the span are counted as gaps ("বিল বাকি") and are NOT filled by a guess.
-- returns {amount, span, gaps}; amount null = nothing entered at all.
create or replace function public._pool_rate(p_loc int, p_month date, p_type text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t public.cost_component_types; s numeric := 0; i int; v numeric; first_m date; span int; gaps int := 0; k int;
begin
  select * into t from public.cost_component_types where code = p_type;
  if not found then return jsonb_build_object('amount', null, 'span', 0, 'gaps', 0); end if;
  if t.smooth <> 'avg_n' or t.avg_months is null then
    v := public._pool_month_actual(p_loc, p_month, p_type);
    return jsonb_build_object('amount', v, 'span', case when v is null then 0 else 1 end, 'gaps', 0);
  end if;
  select min(month) into first_m from public.factory_cost_pools where active and location_id = p_loc and component_type = p_type and month <= p_month;
  if first_m is null then return jsonb_build_object('amount', null, 'span', 0, 'gaps', 0); end if;
  k := (extract(year from age(p_month, first_m)) * 12 + extract(month from age(p_month, first_m)))::int + 1;       -- months from the first entry to the run month, inclusive
  span := least(t.avg_months, k);
  for i in 0 .. span - 1 loop
    v := public._pool_month_actual(p_loc, (p_month - make_interval(months => i))::date, p_type);
    if v is null then gaps := gaps + 1; else s := s + v; end if;
  end loop;
  return jsonb_build_object('amount', s / span, 'span', span, 'gaps', gaps);
end $$;
create or replace function public._pool_rate_amount(p_loc int, p_month date, p_type text) returns numeric
language sql stable security definer set search_path = public as $$ select (public._pool_rate(p_loc, p_month, p_type) ->> 'amount')::numeric $$;

-- the conversion cost of ONE production (or of one batch for the preview): jsonb {mode, amount, complete, detail[], reason}
-- p_force_mode lets recipe_cost show the recipe rate when no location is given. Never guesses: a blank amount / blank normal output = complete false.
create or replace function public._conv_cost(p_recipe uuid, p_loc int, p_batches numeric, p_out numeric, p_date date, p_force_mode text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare md text; c record; ty record; det jsonb := '[]'::jsonb; tot numeric := 0; complete boolean := true; amt numeric; norm numeric; m date := public._m1(p_date); any_pool boolean := false; ncomp int := 0; why text := null; a numeric; pr jsonb;
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
    select normal_monthly_output into norm from public.location_cost_cfg where location_id = p_loc;
    if lower(coalesce((select public._item_base(r.item_id) from public.recipes r where r.id = p_recipe), '')) <> 'kg' then complete := false; why := 'pool_unit_not_kg';      -- the pool rate is per kg of output: a piece-based product needs recipe rates
    elsif norm is null or norm <= 0 then complete := false; why := 'normal_output_blank';
    else
      for ty in select code from public.cost_component_types where active order by code loop
        pr := public._pool_rate(p_loc, m, ty.code); a := (pr ->> 'amount')::numeric;
        if a is not null then any_pool := true; amt := a / norm * p_out; tot := tot + amt;
          det := det || jsonb_build_object('type', ty.code, 'basis', 'pool', 'rate', round(a / norm, 8), 'amount', round(amt, 6), 'incomplete', false, 'months', pr -> 'span', 'gap_months', pr -> 'gaps'); end if;
      end loop;
      if not any_pool then complete := false; why := 'no_pool'; end if;
    end if;
  end if;
  return jsonb_build_object('mode', md, 'amount', tot, 'complete', complete, 'detail', det, 'reason', why);
end $$;

-- the latest booked purchase price of an item (a purchase_in row that has not been reversed); optional place
create or replace function public._today_cost(p_item uuid, p_loc int) returns numeric
language sql stable security definer set search_path = public as $$
  select l.unit_cost from public.stock_ledger l
   where l.item_id = p_item and l.reason = 'purchase_in' and l.unit_cost is not null and (p_loc is null or l.location_id = p_loc)
     and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
     and (p_loc is not null or ((public._all_locs() or public.can_loc(l.location_id)) and public._cost_ok(l.location_id)))
   order by l.made_at desc, l.id desc limit 1;
$$;

-- ---------- C1 writes ----------
create or replace function public.cost_type_add(p_label_bn text, p_label_en text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  if p_label_bn is null or length(btrim(p_label_bn)) < 1 or length(btrim(p_label_bn)) > 80 then raise exception 'name_needed'; end if;
  c := 'x' || nextval('public.cost_type_seq')::text;
  insert into public.cost_component_types (code, label_bn, label_en, builtin, created_by) values (c, btrim(p_label_bn), left(nullif(btrim(p_label_en), ''), 80), false, auth.uid());
  return jsonb_build_object('code', c);
end $$;
create or replace function public.cost_type_smoothing(p_code text, p_smooth text, p_months int default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  if p_smooth not in ('none', 'yearly12', 'avg_n') then raise exception 'bad_value'; end if;
  if p_smooth = 'avg_n' and (p_months is null or p_months not between 1 and 36) then raise exception 'bad_value'; end if;
  update public.cost_component_types set smooth = p_smooth, avg_months = case when p_smooth = 'avg_n' then p_months end where code = p_code;
  if not found then raise exception 'unknown_type'; end if;
end $$;

-- set / change one conversion rate of a recipe. The old row is retired (kept), a new active one is inserted: previous values stay. Cost-right holders only.
create or replace function public.recipe_cost_component_set(p_recipe uuid, p_type text, p_basis text, p_amount numeric, p_hours numeric default null, p_type_note text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.recipe_cost_components; nid bigint; tn text := nullif(btrim(p_type_note), '');
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into d from public.recipe_cost_components where client_id = p_client; if found then return jsonb_build_object('dup', true, 'id', d.id); end if; end if;
  if not exists (select 1 from public.recipes where id = p_recipe) then raise exception 'recipe_not_found'; end if;
  if not exists (select 1 from public.cost_component_types where code = p_type and active) then raise exception 'unknown_type'; end if;
  if p_type = 'other' and tn is null then raise exception 'type_note_needed'; end if;
  if p_basis not in ('per_batch', 'per_unit', 'per_labour_hour') then raise exception 'bad_value'; end if;
  if p_amount is not null and not (p_amount >= 0 and p_amount <= 1000000000) then raise exception 'bad_cost'; end if;
  if p_hours is not null and not (p_hours >= 0 and p_hours <= 100000) then raise exception 'bad_qty'; end if;
  update public.recipe_cost_components set active = false where recipe_id = p_recipe and component_type = p_type and coalesce(type_note, '') = coalesce(tn, '') and active;
  insert into public.recipe_cost_components (recipe_id, component_type, type_note, basis, amount, hours_per_batch, note, set_by, client_id)
    values (p_recipe, p_type, case when p_type = 'other' then left(tn, 80) end, p_basis, p_amount, case when p_basis = 'per_labour_hour' then p_hours end, left(p_note, 200), auth.uid(), p_client) returning id into nid;
  return jsonb_build_object('id', nid, 'incomplete', p_amount is null or (p_basis = 'per_labour_hour' and p_hours is null));
end $$;
create or replace function public.recipe_cost_component_retire(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  update public.recipe_cost_components set active = false where id = p_id and active;
  if not found then raise exception 'not_found'; end if;
end $$;

-- the components of a recipe with the flag "রূপান্তর খরচ অসম্পূর্ণ" (cost-right holders only)
create or replace function public.recipe_cost_components_get(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; inc boolean;
begin
  if not public._recipe_cost_ok() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'type', c.component_type, 'type_note', c.type_note, 'label_bn', t.label_bn, 'label_en', t.label_en, 'basis', c.basis, 'amount', c.amount, 'hours_per_batch', c.hours_per_batch, 'note', c.note,
    'incomplete', c.amount is null or (c.basis = 'per_labour_hour' and c.hours_per_batch is null)) order by t.code, c.id), '[]'::jsonb) into rows_
    from public.recipe_cost_components c join public.cost_component_types t on t.code = c.component_type where c.recipe_id = p_recipe and c.active;
  inc := jsonb_array_length(rows_) = 0 or exists (select 1 from jsonb_array_elements(rows_) x where (x->>'incomplete')::boolean);
  return jsonb_build_object('recipe_id', p_recipe, 'components', rows_, 'incomplete', inc, 'flag', case when inc then 'রূপান্তর খরচ অসম্পূর্ণ' end,
    'suggested_labour_hours', public.recipe_labour_suggest(p_recipe)->'suggested_labour_hours');
end $$;

-- ---------- C2 writes ----------
create or replace function public.pool_set(p_loc int, p_month date, p_type text, p_amount numeric, p_period_kind text default 'month', p_one_off boolean default false, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.factory_cost_pools; nid bigint; m date := public._m1(p_month);
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
  return jsonb_build_object('id', nid);
end $$;

-- the per-location choice (owner only): off | recipe | pool, and the NORMAL monthly output (base units)
create or replace function public.loc_cost_cfg_set(p_loc int, p_mode text, p_normal numeric default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_mode not in ('off', 'recipe', 'pool') then raise exception 'bad_value'; end if;
  if p_normal is not null and not (p_normal > 0 and p_normal <= 1000000000) then raise exception 'bad_qty'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  insert into public.location_cost_cfg (location_id, mode, normal_monthly_output, updated_by, updated_at) values (p_loc, p_mode, p_normal, auth.uid(), now())
    on conflict (location_id) do update set mode = excluded.mode, normal_monthly_output = excluded.normal_monthly_output, updated_by = auth.uid(), updated_at = now();
end $$;

-- ---------- C4 / C5: recipe_cost - the SAME _recipe_need as the production run (packaging included), raw / packaging / conversion as separate rows, "today's price" in its own row ----------
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

-- ---------- C3 / C7: production_post with conversion cost and an optional actual yield ----------
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid, p_made_at timestamptz, p_note text, p_actual_yield numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.recipes; it public.items; at_ timestamptz := coalesce(p_made_at, now()); run public.production_runs; n record; rid uuid := gen_random_uuid();
        mode text; neg text; yb numeric; f numeric; sl jsonb; exp timestamptz; bid bigint; lin bigint; lid bigint; tot numeric := 0; cost_ok boolean := true; av numeric; wm int := 0;
        shorts text := ''; used jsonb := '[]'::jsonb; ucb numeric; derived uuid; gate text;
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
  if not public._may('stock_production', p_loc, 'production:' || r.item_id::text, yb) then raise exception 'not allowed'; end if;
  insert into public.production_runs (id, client_id, location_id, recipe_id, item_id, batches, made_at, yield_base, waste_missing, note, created_by)
    values (rid, p_client, p_loc, r.id, r.item_id, p_batches, at_, outq, wm, left(p_note, 200), auth.uid());      -- bos74: yield_base = the quantity really booked
  -- ingredient (and packaging) OUT at the weighted average cost, fixed item order so two productions can never wait on each other in a circle
  for n in select * from public._recipe_need(r.id, p_batches, p_loc) order by item_id loop
    if n.need < 0.0001 then continue; end if;
    select avg_cost into av from public.stock_balance where item_id = n.item_id and location_id = p_loc;
    if av is null then cost_ok := false; else tot := tot + n.need * av; end if;
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

-- the 6-argument signature stays (callers and older tests use it): it is a thin wrapper, there is NO default on the 7th parameter so a 6-argument call is never ambiguous
create or replace function public.production_post(p_loc int, p_recipe uuid, p_batches numeric, p_client uuid default null, p_made_at timestamptz default null, p_note text default null) returns jsonb
language sql security definer set search_path = public as $$
  select public.production_post(p_loc, p_recipe, p_batches, p_client, p_made_at, p_note, null::numeric);
$$;

-- the cost snapshot of runs: cost-right holders ONLY (the new production_runs columns are not in the browser column grant)
create or replace function public.production_run_costs(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public._cost_ok(p_loc) and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'made_at', r.made_at, 'status', r.status, 'item_id', r.item_id, 'code', i.code, 'batches', r.batches, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'yield_var_pct', r.yield_var_pct, 'output', r.yield_base, 'material_cost', r.material_cost, 'conversion_cost', r.conversion_cost, 'unit_cost', r.unit_cost, 'std_cost', r.std_cost, 'actual_cost', r.actual_cost,
      'conversion_mode', r.conversion_mode, 'conversion_complete', r.conversion_complete, 'conversion_detail', r.conversion_detail) order by r.made_at, r.id)
    from public.production_runs r join public.items i on i.id = r.item_id
    where r.location_id = p_loc and (r.made_at at time zone 'Asia/Dhaka')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $$;

-- ---------- C6: month-end true-up: ACTUAL factory cost (pools) vs ABSORBED into products; the difference is the row 'অনাবশোষিত ওভারহেড' ----------
create or replace function public.overhead_trueup(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._m1(p_month); rows_ jsonb := '[]'::jsonb; t record; act numeric; ab numeric; act_tot numeric := 0; ab_tot numeric := 0; ab_noact numeric := 0; have_actual boolean := false; oneoff int;
begin
  if not (public._recipe_cost_ok() and public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  for t in select c.code, c.label_bn, c.label_en from public.cost_component_types c where c.active order by c.code loop
    act := public._pool_month_actual(p_loc, m, t.code);
    select coalesce(sum((d->>'amount')::numeric), 0) into ab from public.production_runs r, jsonb_array_elements(coalesce(r.conversion_detail, '[]'::jsonb)) d
      where r.location_id = p_loc and r.status = 'done' and public._m1((r.made_at at time zone 'Asia/Dhaka')::date) = m and d->>'type' = t.code and (d->>'amount') is not null;
    if act is null and ab = 0 then continue; end if;
    if act is not null then have_actual := true; act_tot := act_tot + act; ab_tot := ab_tot + ab; else ab_noact := ab_noact + ab; end if;
    rows_ := rows_ || jsonb_build_object('type', t.code, 'label_bn', t.label_bn, 'label_en', t.label_en, 'actual', act, 'absorbed', round(ab, 2), 'unabsorbed', case when act is null then null else round(act - ab, 2) end,
      'note', case when act is null then 'বাস্তব খরচ ঢোকানো নেই / no actual entered' end);
  end loop;
  select count(*) into oneoff from public.factory_cost_pools where active and location_id = p_loc and month = m and one_off;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'rows', rows_, 'actual_total', case when have_actual then round(act_tot, 2) end, 'absorbed_total', round(ab_tot + ab_noact, 2),
    'absorbed_matched', round(ab_tot, 2), 'absorbed_without_actual', round(ab_noact, 2),
    'unabsorbed_overhead', case when have_actual then round(act_tot - ab_tot - ab_noact, 2) end, 'unabsorbed_label_bn', 'অনাবশোষিত ওভারহেড', 'unabsorbed_label_en', 'Unabsorbed overhead',
    'one_off_rows', oneoff, 'note', 'showroom and admin cost are not absorbed into products');
end $$;

-- ---------- C7: the 05-4 yield test gives a SUGGESTION only; the recipe is never changed ----------
create or replace function public.recipe_yield_suggestion(p_recipe uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.recipes; it public.items; e record; lines_ jsonb;
begin
  if not (public._recipe_read() or public.has_grant('recipe_view')) then raise exception 'not allowed'; end if;
  select * into r from public.recipes where id = p_recipe;
  if not found then raise exception 'recipe_not_found'; end if;
  select * into it from public.items where id = r.item_id;
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
end $$;

-- ---------- C8: the manual production path ----------
create or replace function public.stock_production_in(p_item uuid, p_loc int, p_qty numeric, p_made_at timestamptz default null, p_unit text default null,
  p_note text default null, p_client uuid default null, p_unit_cost numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; at_ timestamptz := coalesce(p_made_at, now()); sl jsonb; exp timestamptz; bid bigint; f numeric; ucb numeric; pct numeric; av numeric;
begin
  if at_ is null or at_ = 'infinity'::timestamptz or at_ = '-infinity'::timestamptz then raise exception 'bad_date'; end if;
  it := public._stock_guard(p_item, p_loc, 'stock_production', (at_ at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then select id, batch_id into lid, bid from public.stock_ledger where client_id = p_client and reason = 'production_in' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid, 'batch_id', bid); end if; end if;
  if public.rule_on('production_requires_recipe') then raise exception 'recipe_required'; end if;
  if public.rule_on('production_manual_needs_reason') and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- bos74
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if at_ > now() + interval '10 minutes' then raise exception 'bad_date'; end if;
  if p_unit_cost is not null and not (p_unit_cost between 0 and 999999999) then raise exception 'bad_cost'; end if;
  if p_unit_cost is not null and not public._cost_ok(p_loc) then raise exception 'not allowed'; end if;      -- cost is secret: only who may see it may write it
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not public._may('stock_production', p_loc, 'production:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  f := public._unit_factor_base(p_item, p_unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
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
  if p_unit_cost is not null then      -- bos74: a hand-typed cost on the no-recipe path is always flagged
    perform public._stock_exc(p_loc, 'production_manual_cost', 'yellow', it.name_bn || ': উৎপাদনের খরচ হাতে লেখা (রেসিপি ছাড়া) — রেসিপি দিয়ে উৎপাদন করুন',
      coalesce(it.name_en, it.name_bn) || ': production cost was typed by hand (no recipe) — prefer a recipe production', null, (at_ at time zone 'Asia/Dhaka')::date, 'STOCK');
  end if;
  sl := public.shelf_life_for(p_item, (at_ at time zone 'Asia/Dhaka')::date);
  exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
    values (p_item, p_loc, at_, bq, bq, exp, sl, left(p_note, 200), auth.uid()) returning id into bid;
  lid := public.stock_post(p_item, p_loc, bq, 'production_in', 'production', bid::text, case when p_unit_cost is null then null else p_unit_cost / f end, bid, at_, left(p_note, 200), null, 'none', null, p_client);
  return jsonb_build_object('ledger_id', lid, 'batch_id', bid, 'qty', bq, 'expires_at', exp);
end $$;

-- ---------- C6: the GL account + mapping key overhead_absorbed (the owner may re-point it with acct_mapping_set) ----------
insert into public.coa_accounts (code, name_bn, name_en, type, normal_side, is_group, is_system, sort)
  values ('5950', 'কারখানার ওভারহেড অবশোষিত (বিপরীত খরচ)', 'Factory overhead absorbed into products (contra expense)', 'expense', 'credit', false, true, 5950)
  on conflict (code) do nothing;
insert into public.acct_mappings (key, account_id, label_bn, label_en)
  select 'overhead_absorbed', a.id, 'পণ্যের খরচে ধরা কারখানার ওভারহেড', 'Factory overhead absorbed into products' from public.coa_accounts a where a.code = '5950'
  on conflict (key) do nothing;

-- ---------- privileges ----------
-- the read policies of the new cost tables call this helper as the signed-in person
grant execute on function public._recipe_cost_ok() to authenticated;
revoke all on function public._m1(date), public._pool_month_actual(int, date, text), public._pool_rate(int, date, text), public._pool_rate_amount(int, date, text), public._conv_cost(uuid, int, numeric, numeric, date, text), public._today_cost(uuid, int) from public, anon, authenticated;
revoke all on function public.cost_type_add(text, text), public.cost_type_smoothing(text, text, int), public.recipe_cost_component_set(uuid, text, text, numeric, numeric, text, text, uuid), public.recipe_cost_component_retire(bigint),
  public.recipe_cost_components_get(uuid), public.pool_set(int, date, text, numeric, text, boolean, text, uuid), public.loc_cost_cfg_set(int, text, numeric), public.production_run_costs(int, date, date),
  public.overhead_trueup(int, date), public.recipe_yield_suggestion(uuid), public.recipe_cost(uuid, int), public.production_post(int, uuid, numeric, uuid, timestamptz, text, numeric), public.production_post(int, uuid, numeric, uuid, timestamptz, text) from public, anon;
grant execute on function public.cost_type_add(text, text), public.cost_type_smoothing(text, text, int), public.recipe_cost_component_set(uuid, text, text, numeric, numeric, text, text, uuid), public.recipe_cost_component_retire(bigint),
  public.recipe_cost_components_get(uuid), public.pool_set(int, date, text, numeric, text, boolean, text, uuid), public.loc_cost_cfg_set(int, text, numeric), public.production_run_costs(int, date, date),
  public.overhead_trueup(int, date), public.recipe_yield_suggestion(uuid), public.recipe_cost(uuid, int), public.production_post(int, uuid, numeric, uuid, timestamptz, text, numeric), public.production_post(int, uuid, numeric, uuid, timestamptz, text) to authenticated;
revoke all on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) from public, anon;
grant execute on function public.stock_production_in(uuid, int, numeric, timestamptz, text, text, uuid, numeric) to authenticated;

-- ---------- C6: the journal source _acct_docs re-created (LATEST definition = phase52; only the production block changed, marked bos74) ----------
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
        select 1 o, jsonb_build_object('a', 'inv_finished', 'd', c.amt + round(coalesce(r.conversion_cost, 0), 2)) j /* bos74: material + conversion */
        union all select 2, jsonb_build_object('a', public._acct_inv_key(z.t), 'c', z.amt)
          from (select it.item_type t, round(sum(-l.qty_delta * l.unit_cost), 2) amt from public.stock_ledger l join public.items it on it.id = l.item_id
                where l.ref_type = 'production' and l.ref_id = r.id::text and l.reason = 'issue_out' and l.unit_cost is not null group by it.item_type) z where z.amt > 0
        union all select 3, jsonb_build_object('a', 'overhead_absorbed', 'c', round(r.conversion_cost, 2)) where coalesce(r.conversion_cost, 0) >= 0.005 /* bos74: Cr overhead absorbed */
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

-- ---------------------------------------------------------------- phase75.sql
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

-- ---------------------------------------------------------------- phase76.sql
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

-- ---------------------------------------------------------------- phase77.sql
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

-- ---------------------------------------------------------------- phase78.sql
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

-- ---------------------------------------------------------------- phase79.sql
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

-- ---------------------------------------------------------------- phase506.sql
-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase80.sql there and is already pasted on the live database under that name.
-- Renumbered to phase506.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- ============================================================
-- Phase 506 (bos80) - Step S1: follow-ups of the owner's delegated decisions. Run AFTER phase79. Additive + paste-twice safe.
--   1. FREE-COST ITEM FLAG      table item_cost_flags (cost-right readable only) + item_cost_free_set(item, bool, reason, client). An item marked "cost really zero"
--                               is a KNOWN cost of 0: production_post (refuse rule + finished-good cost), the report COGS (_cogs_lines72: not "unknown cost revenue"),
--                               and the posting flags of _acct_docs (cogs_missing) treat it as known. Everything else with cost 0 / blank stays UNKNOWN (bos72).
--                               cost_unknown_items(loc) lists the tracked items whose cost is unknown (the 'cost_missing' list for the screen). Nothing is marked by default.
--   2. PARTNER BASE SWITCH      rule partner_base_estimate = warn | refuse (default warn). partner_calculate always adds an 'estimated_base' warning when part of the
--                               cost of goods sold is the item-cost-list ESTIMATE (cogs_fallback); refuse makes partner_settlement_save raise base_estimated when a
--                               profit base is used (a typed manual profit base replaces it).
--   3. PACKAGING ON RETURN      rule packaging_return_mode = none | restore | wastage (default none = today). restore: the packaging that the sale took out
--                               (sale_pack) comes back in proportion (stock_ledger row on the return, so the books and void_sale_return follow it);
--                               wastage: a record only (the packaging stays expensed in COGS). Table sale_return_packaging80 (quantities only, no cost).
--   4. DEDICATED INTAKE BOT     role intake_bot + form ONLINE_INTAKE (enter only). The bot can CREATE online orders and receive messages / web orders; it has NO POS
--                               right (cannot sell, edit, confirm, deliver, read the inbox). intake_bot_create(user, place) = owner-only one-step setup, intake_bot_check(user).
-- Re-created functions (latest definitions, only bos80 lines changed): production_post (7-arg), _acct_docs, _cogs_lines72, partner_calculate, partner_settlement_save,
--   sale_return, online_order_save. Every rule default = today's behaviour.
-- ============================================================

do $g$ begin
  if to_regprocedure('public._acct_inv_split72(text[], text, text[], integer)') is null
     or to_regprocedure('public._oo_flag_ro77()') is null
     or to_regprocedure('public._inb_is_bot()') is null
     or position('bos72' in coalesce(pg_get_functiondef(to_regprocedure('public.production_post(integer, uuid, numeric, uuid, timestamp with time zone, text, numeric)')), '')) = 0 then
    raise exception 'phase506 needs phases 72..79 pasted first (phase79 last)';
  end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('partner_base_estimate', 'partners', 'choice', '"warn"', null, '["warn","refuse"]', null, null,
  'অংশীদার লাভের ভিত্তিতে অনুমানের খরচ থাকলে: সতর্কতা / আটকানো', 'Partner profit base-এ অনুমানের cost থাকলে: warn / refuse', 'When the partner profit base contains an estimated cost: warn, or refuse the settlement',
  'warn = শুধু সতর্কতা দেখায়। refuse = অনুমানের খরচসহ লাভের ভিত্তিতে হিসাব সংরক্ষণ হয় না (নিজে ভিত্তি টাইপ করলে চলে)।',
  'warn = a warning only. refuse = a settlement on a profit base with an estimated cost is not saved (a typed manual base is accepted).', 760),
 ('packaging_return_mode', 'stock', 'choice', '"none"', null, '["none","restore","wastage"]', null, null,
  'পণ্য ফেরতে প্যাকেজিং: কিছু না / স্টকে ফেরত / নষ্ট হিসাব', 'Product return-এ packaging: none / stock-এ restore / wastage', 'Packaging on a sale return: none, restore to stock, or record as wastage',
  'none = আজকের মতো কিছু হয় না। restore = বিক্রিতে কাটা প্যাকেজিং অনুপাতে স্টকে ফেরত। wastage = শুধু নষ্ট হিসাবে রেকর্ড (স্টক বাড়ে না)।',
  'none = nothing, as today. restore = the packaging the sale took out goes back to stock in proportion. wastage = a record only (stock does not grow).', 761)
 on conflict (key) do nothing;

-- ---------- 1. free-cost flag ----------
create table if not exists public.item_cost_flags (
  item_id uuid primary key references public.items(id) on delete cascade,
  cost_free boolean not null default false,
  reason text check (reason is null or char_length(reason) <= 300),
  last_client uuid,
  set_by uuid, set_at timestamptz not null default now()
);
alter table public.item_cost_flags enable row level security;
drop policy if exists item_cost_flags_read on public.item_cost_flags;
create policy item_cost_flags_read on public.item_cost_flags for select to authenticated using (public.can_do('ITEM_COST', 'view'));
drop trigger if exists audit_item_cost_flags on public.item_cost_flags;
create trigger audit_item_cost_flags after insert or update on public.item_cost_flags for each row execute function public.log_change('item_id');

create or replace function public._cost_free80(p_item uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select f.cost_free from public.item_cost_flags f where f.item_id = p_item), false);
$$;

create or replace function public.item_cost_free_set(p_item uuid, p_free boolean, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f public.item_cost_flags;
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('ITEM_COST', 'enter')) then raise exception 'not allowed'; end if;
  if p_item is null or p_free is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'not_found'; end if;
  if p_free and char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  perform public._client_lock(p_client);
  select * into f from public.item_cost_flags where item_id = p_item for update;
  if found and p_client is not null and f.last_client = p_client then return jsonb_build_object('item_id', p_item, 'cost_free', f.cost_free, 'dup', true); end if;
  if found and f.cost_free = p_free then return jsonb_build_object('item_id', p_item, 'cost_free', f.cost_free, 'noop', true); end if;
  insert into public.item_cost_flags (item_id, cost_free, reason, last_client, set_by, set_at)
    values (p_item, p_free, left(nullif(btrim(p_reason), ''), 300), p_client, auth.uid(), now())
    on conflict (item_id) do update set cost_free = excluded.cost_free, reason = excluded.reason, last_client = excluded.last_client, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('item_id', p_item, 'cost_free', p_free);
end $$;

create or replace function public.item_cost_flags_list() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cost_ok(null) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'reason', f.reason, 'set_at', f.set_at) order by i.code)
    from public.item_cost_flags f join public.items i on i.id = f.item_id where f.cost_free), '[]'::jsonb);
end $$;

-- tracked items of a place whose cost is UNKNOWN (blank or 0) and not marked "cost really zero": the 'cost_missing' list
create or replace function public.cost_unknown_items(p_loc int) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._cost_ok(p_loc) or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', b.qty, 'label', 'cost_missing') order by i.code)
    from public.stock_balance b join public.items i on i.id = b.item_id
    where i.tracked and i.count_in_business and (p_loc is null or b.location_id = p_loc) and public.can_loc(b.location_id)
      and coalesce(b.avg_cost, 0) <= 0 and not public._cost_free80(i.id)), '[]'::jsonb);
end $$;

-- ---------- 4. dedicated intake bot: role + form + gate ----------
insert into public.roles (code, name_bn, name_mix, name_en, sort, allow_self_approve, active)
values ('intake_bot', 'ইনটেক বট (শুধু অনলাইন অর্ডার ঢোকানো)', 'Intake bot (শুধু online order ঢোকানো)', 'Intake bot (online orders only)', 125, false, true)
on conflict (code) do nothing;
insert into public.forms (code, area, name_bn, name_mix, name_en, sort, count_first, red_block, enabled)
values ('ONLINE_INTAKE', 'showroom', 'অনলাইন অর্ডার ঢোকানো (বট)', 'Online order ঢোকানো (bot)', 'Online order intake (bot)', 125, false, false, true)
on conflict (code) do nothing;
insert into public.form_rollout (form_code, location_id, mode, note)
select f.code, l.id, 'app', 'start: live forms stay on the app' from public.forms f cross join public.locations l where f.code = 'ONLINE_INTAKE'
on conflict (form_code, location_id) do nothing;
insert into public.role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values ('intake_bot', 'ONLINE_INTAKE', false, true, false)
on conflict (role_code, form_code) do nothing;

create or replace function public._oo_gate80(p_loc int, p_create boolean) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_create and public._inb_is_bot() and public.can_do('ONLINE_INTAKE', 'enter') then
    if not public.is_active() then raise exception 'not allowed'; end if;
    if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
    if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  else
    perform public._oo_gate61(p_loc, 'enter');
  end if;
end $$;

-- ---------- 3. packaging on a sale return ----------
create table if not exists public.sale_return_packaging80 (
  id bigint generated always as identity primary key,
  return_id uuid not null references public.sale_returns(id), sale_id uuid not null, location_id int not null,
  item_id uuid not null references public.items(id), qty numeric not null check (qty > 0), mode text not null check (mode in ('restore', 'wastage')),
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists sale_return_packaging80_sale on public.sale_return_packaging80 (sale_id, item_id);
create or replace function public._srp_ro80() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: a packaging return record is never changed or deleted'; end $$;
drop trigger if exists sale_return_packaging80_ro on public.sale_return_packaging80;
create trigger sale_return_packaging80_ro before update or delete on public.sale_return_packaging80 for each row execute function public._srp_ro80();
drop trigger if exists audit_sale_return_packaging80 on public.sale_return_packaging80;
create trigger audit_sale_return_packaging80 after insert on public.sale_return_packaging80 for each row execute function public.log_change('id');
alter table public.sale_return_packaging80 enable row level security;
drop policy if exists srp80_read on public.sale_return_packaging80;
create policy srp80_read on public.sale_return_packaging80 for select to authenticated using (public.is_active() and public.can_loc(location_id) and public.can_do('POS', 'view'));

-- called by sale_return (inside its transaction) when packaging_return_mode <> none
create or replace function public._ret_pack80(p_ret uuid, p_sale uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare mode text := coalesce(public.rule_txt('packaging_return_mode'), 'none'); s public.sales; pk record; outq numeric; ucost numeric; prior numeric; take numeric; nm record;
begin
  if mode not in ('restore', 'wastage') then return; end if;
  select * into s from public.sales where id = p_sale;
  if not found or jsonb_typeof(p_lines) <> 'array' then return; end if;
  for pk in
    select pp.packaging_item_id as item_id, sum(public._base_qty(li.iid, li.q, li.u) * pp.qty_per_unit) as want
      from (select (x->>'item_id')::uuid as iid, nullif(x->>'qty', '')::numeric as q, x->>'unit' as u from jsonb_array_elements(p_lines) x where nullif(x->>'item_id', '') is not null) li
      join public.product_packaging pp on pp.product_item_id = li.iid and pp.active and pp.applies_to = 'sale'
     where li.q > 0 group by pp.packaging_item_id order by pp.packaging_item_id loop
    if pk.want is null then continue; end if;
    -- what this sale really took out and what earlier (live) returns already settled: nothing is invented, never more than the sale took
    select coalesce(-sum(o.qty_delta), 0), (sum(-o.qty_delta * o.unit_cost) filter (where o.unit_cost is not null)) / nullif(sum(-o.qty_delta) filter (where o.unit_cost is not null), 0)
      into outq, ucost
      from public.stock_ledger o where o.ref_type = 'sale_pack' and o.ref_id = p_sale::text and o.reason = 'issue_out' and o.item_id = pk.item_id
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id);
    select coalesce(sum(x.qty), 0) into prior from public.sale_return_packaging80 x join public.sale_returns r on r.id = x.return_id
     where x.sale_id = p_sale and x.item_id = pk.item_id and r.status = 'done' and x.return_id <> p_ret;
    take := least(round(pk.want, 4), round(outq - prior, 4));
    if take < 0.0001 then continue; end if;
    if mode = 'restore' then
      perform public.stock_post(pk.item_id, s.location_id, take, 'sale_return', 'sale_return', p_ret::text, ucost, null, now(), left('packaging back, receipt ' || s.receipt, 200), null, 'none');
    end if;
    insert into public.sale_return_packaging80 (return_id, sale_id, location_id, item_id, qty, mode, created_by) values (p_ret, p_sale, s.location_id, pk.item_id, take, mode, auth.uid());
    select i.name_bn, i.name_en into nm from public.items i where i.id = pk.item_id;
    if mode = 'wastage' then
      perform public._stock_exc(s.location_id, 'return_packaging_wastage', 'yellow', 'রসিদ ' || s.receipt || ': ফেরতে প্যাকেজিং নষ্ট ধরা হয়েছে — ' || coalesce(nm.name_bn, '') || ' ' || take::text,
        'Receipt ' || s.receipt || ': packaging of the return recorded as wastage - ' || coalesce(nm.name_en, nm.name_bn, '') || ' ' || take::text, p_sale, s.sale_date, 'POS');
    end if;
  end loop;
end $$;

-- ---------- production_post (7-arg core): latest = phase79 (bos72 + bos73 + bos74) + bos80 free-cost item ----------
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
end $function$;

-- ---------- _acct_docs: latest = phase79 (bos50 + bos52 + bos72 + bos74) + bos80 free-cost item ----------
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
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
    select round(sum(-l.qty_delta * l.unit_cost) filter (where l.unit_cost is not null), 2) amt, count(*) filter (where coalesce(l.unit_cost, 0) = 0 and not public._cost_free80(l.item_id)) nulls /* bos72 */ /* bos80 */
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

-- ---------- _cogs_lines72: latest = phase72 + bos80 free-cost item (known cost, not 'unknown cost revenue') ----------
CREATE OR REPLACE FUNCTION public._cogs_lines72(d1 date, d2 date, locs integer[])
 RETURNS TABLE(src text, doc_id uuid, d date, loc integer, item_id uuid, qty numeric, rev numeric, led_cogs numeric, led_rev numeric, fb_cogs numeric, fb_rev numeric, unk_rev numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
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
$function$;

-- ---------- partner_calculate: latest = phase44 + bos80 estimated-base warning ----------
CREATE OR REPLACE FUNCTION public.partner_calculate(p_agr bigint, p_from date, p_to date, p_manual jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'total_distributable', round(tdist, 2), 'outside_total', round(tout, 2), 'warnings', warns, 'wrote', false);
end $function$;

-- ---------- partner_settlement_save: latest = phase44 + bos80 ----------
CREATE OR REPLACE FUNCTION public.partner_settlement_save(p_agr bigint, p_from date, p_to date, p_manual jsonb, p_note text, p_client uuid DEFAULT NULL::uuid)
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
end $function$;

-- ---------- sale_return: latest = phase11/12 definition + bos80 packaging_return_mode ----------
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
    bq := public._base_qty(it.id, ln.q, ln.u);
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
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $function$;

-- ---------- online_order_save: latest = phase61 + bos80 gate ----------
CREATE OR REPLACE FUNCTION public.online_order_save(p_id uuid, p_client uuid, p_loc integer, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb, p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text)
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
end $function$;

-- ---------- 4. owner-only one-step setup of the intake bot ----------
create or replace function public.intake_bot_create(p_user uuid, p_loc int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_loc is null then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user and role_code = 'owner') then raise exception 'owner_cannot_be_bot'; end if;
  -- a user who already holds a role with the POS enter / approve right is refused: the whole point is that the bot cannot enter POS
  if exists (select 1 from public.user_roles ur join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = 'POS'
              where ur.user_id = p_user and ur.role_code <> 'intake_bot' and (p.can_enter or p.can_approve)) then raise exception 'bot_has_pos_role'; end if;
  insert into public.user_roles (user_id, role_code) values (p_user, 'intake_bot') on conflict do nothing;
  insert into public.user_locations (user_id, location_id) values (p_user, p_loc) on conflict do nothing;
  insert into public.intake_bots (user_id, active, created_by) values (p_user, true, auth.uid())
    on conflict (user_id) do update set active = true, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'role', 'intake_bot', 'location_id', p_loc, 'active', true);
end $$;

create or replace function public.intake_bot_check(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('user_id', p_user,
    'is_bot', exists (select 1 from public.intake_bots b where b.user_id = p_user and b.active),
    'has_intake_role', exists (select 1 from public.user_roles where user_id = p_user and role_code = 'intake_bot'),
    'pos_enter', exists (select 1 from public.user_roles ur join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = 'POS' join public.roles r on r.code = ur.role_code and r.active
                          where ur.user_id = p_user and (p.can_enter or p.can_approve)));
end $$;

-- ---------- privileges: internal helpers are not callable from the browser; the screen functions are ----------
revoke all on function public._cost_free80(uuid), public._oo_gate80(int, boolean), public._ret_pack80(uuid, uuid, jsonb), public._srp_ro80() from public, anon, authenticated;
revoke all on public.item_cost_flags, public.sale_return_packaging80 from public, anon, authenticated;
grant select on public.item_cost_flags, public.sale_return_packaging80 to authenticated;
revoke usage, select on sequence public.sale_return_packaging80_id_seq from public, anon, authenticated;
revoke all on function public.item_cost_free_set(uuid, boolean, text, uuid), public.item_cost_flags_list(), public.cost_unknown_items(int), public.intake_bot_create(uuid, int), public.intake_bot_check(uuid) from public, anon;
grant execute on function public.item_cost_free_set(uuid, boolean, text, uuid), public.item_cost_flags_list(), public.cost_unknown_items(int), public.intake_bot_create(uuid, int), public.intake_bot_check(uuid) to authenticated;

-- ============================================================================
-- End of FRESH part 6 of 21.
